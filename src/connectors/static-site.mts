import { cp, lstat, mkdir, readFile, rename, rm, symlink, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import {
  ConnectorFailure,
  type ExecutionClaim,
  type ExecutionConnector,
  requireString,
  throwIfAborted,
} from "./connector.mjs";

export interface StaticSiteConnectorOptions {
  readonly sourceDirectory: string;
  readonly publishDirectory: string;
  readonly publicBaseUrl: string;
}

interface ReleaseManifest {
  readonly executionId: string;
  readonly requestId: string;
  readonly commitSha: string;
}

export class StaticSiteConnector implements ExecutionConnector {
  readonly kind = "STATIC_SITE" as const;
  private readonly sourceDirectory: string;
  private readonly publishDirectory: string;
  private readonly publicBaseUrl: URL;

  constructor(options: StaticSiteConnectorOptions) {
    this.sourceDirectory = resolve(options.sourceDirectory);
    this.publishDirectory = resolve(options.publishDirectory);
    this.publicBaseUrl = new URL(options.publicBaseUrl);
    if (!/^https?:$/.test(this.publicBaseUrl.protocol)
      || this.publicBaseUrl.username
      || this.publicBaseUrl.password
      || this.publicBaseUrl.search
      || this.publicBaseUrl.hash) {
      throw new Error("Static site public base URL must be an HTTP(S) URL without credentials, query, or fragment");
    }
    const publishFromSource = relative(this.sourceDirectory, this.publishDirectory);
    if (publishFromSource === "" || (!publishFromSource.startsWith(`..${sep}`) && publishFromSource !== ".." && !isAbsolute(publishFromSource))) {
      throw new Error("Static site publish directory must be outside the source directory");
    }
  }

  async recover(claim: ExecutionClaim, signal: AbortSignal): Promise<string | undefined> {
    if (claim.requestKind !== "DEPLOYMENT") throw new ConnectorFailure("CONNECTOR_KIND_MISMATCH", false);
    const manifest: ReleaseManifest = {
      executionId: claim.executionId,
      requestId: requireString(claim.payload, "requestId"),
      commitSha: requireString(claim.payload, "commitSha"),
    };
    const releaseDirectory = join(this.publishDirectory, "releases", claim.executionId);
    if (!await manifestMatches(join(releaseDirectory, ".signalbox-release.json"), manifest)) return undefined;
    await this.activate(releaseDirectory, claim, signal);
    return this.reference(claim.executionId);
  }

  async execute(claim: ExecutionClaim, signal: AbortSignal): Promise<string> {
    if (claim.requestKind !== "DEPLOYMENT") throw new ConnectorFailure("CONNECTOR_KIND_MISMATCH", false);
    throwIfAborted(signal);
    const requestId = requireString(claim.payload, "requestId");
    const commitSha = requireString(claim.payload, "commitSha");
    const manifest: ReleaseManifest = { executionId: claim.executionId, requestId, commitSha };
    const releasesDirectory = join(this.publishDirectory, "releases");
    const releaseDirectory = join(releasesDirectory, claim.executionId);
    const stagingDirectory = join(releasesDirectory, `.${claim.executionId}.${claim.claimToken}.staging`);
    const manifestPath = join(releaseDirectory, ".signalbox-release.json");

    await mkdir(releasesDirectory, { recursive: true });
    if (await manifestMatches(manifestPath, manifest)) {
      await this.activate(releaseDirectory, claim, signal);
      return this.reference(claim.executionId);
    }
    if (await pathExists(releaseDirectory)) throw new ConnectorFailure("STATIC_RELEASE_CONFLICT", false);

    try {
      await cp(this.sourceDirectory, stagingDirectory, {
        recursive: true,
        errorOnExist: true,
        force: false,
        filter: async (source) => {
          throwIfAborted(signal);
          const entry = await lstat(source);
          if (!entry.isDirectory() && !entry.isFile()) {
            throw new ConnectorFailure("STATIC_SOURCE_UNSAFE", false);
          }
          return true;
        },
      });
      throwIfAborted(signal);
      await writeFile(join(stagingDirectory, ".signalbox-release.json"), `${JSON.stringify(manifest)}\n`, { flag: "wx" });
      await rename(stagingDirectory, releaseDirectory);
    } catch (error) {
      await rm(stagingDirectory, { recursive: true, force: true });
      if (error instanceof ConnectorFailure) throw error;
      throw new ConnectorFailure("STATIC_PUBLISH_FAILED", true, { cause: error });
    }

    await this.activate(releaseDirectory, claim, signal);
    return this.reference(claim.executionId);
  }

  private async activate(releaseDirectory: string, claim: ExecutionClaim, signal: AbortSignal): Promise<void> {
    throwIfAborted(signal);
    const currentPath = join(this.publishDirectory, "current");
    const temporaryPath = join(this.publishDirectory, `.current.${claim.claimToken}`);
    const relativeTarget = relative(dirname(currentPath), releaseDirectory);
    try {
      await rm(temporaryPath, { force: true });
      await symlink(relativeTarget, temporaryPath, "dir");
      await rename(temporaryPath, currentPath);
    } catch (error) {
      await rm(temporaryPath, { force: true });
      throw new ConnectorFailure("STATIC_ACTIVATION_FAILED", true, { cause: error });
    }
  }

  private reference(executionId: string): string {
    const root = this.publicBaseUrl.href.endsWith("/") ? this.publicBaseUrl : new URL(`${this.publicBaseUrl.href}/`);
    return new URL(`releases/${encodeURIComponent(executionId)}/`, root).href;
  }
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await lstat(path);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
    throw error;
  }
}

async function manifestMatches(path: string, expected: ReleaseManifest): Promise<boolean> {
  try {
    const actual = JSON.parse(await readFile(path, "utf8")) as Partial<ReleaseManifest>;
    return actual.executionId === expected.executionId
      && actual.requestId === expected.requestId
      && actual.commitSha === expected.commitSha;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
    if (error instanceof SyntaxError) return false;
    throw error;
  }
}
