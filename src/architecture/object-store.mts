import { createHash } from "node:crypto";
import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

export type ArtifactKind = "MODEL_SOURCE" | "GOVERNANCE_BUNDLE" | "DIFF" | "LOG" | "OTHER";

export interface StoredObject {
  readonly key: string;
  readonly sha256: string;
  readonly sizeBytes: number;
  readonly contentType: string;
}

export interface ObjectArtifactStore {
  put(orgId: string, kind: ArtifactKind, content: Uint8Array, contentType: string): Promise<StoredObject>;
  get(key: string): Promise<Uint8Array>;
}

export interface S3ArtifactStoreOptions {
  readonly bucket: string;
  readonly region: string;
  readonly endpoint?: string;
  readonly accessKeyId?: string;
  readonly secretAccessKey?: string;
  readonly forcePathStyle?: boolean;
  readonly prefix?: string;
  readonly client?: S3Client;
}
export function s3ArtifactStoreFromEnvironment(
  environment: Readonly<Record<string, string | undefined>> = process.env,
): S3ArtifactStore {
  const bucket = requiredEnvironment(environment, "SIGNALBOX_OBJECT_BUCKET");
  const region = requiredEnvironment(environment, "SIGNALBOX_OBJECT_REGION");
  const forcePathStyleValue = environment.SIGNALBOX_OBJECT_FORCE_PATH_STYLE;
  if (forcePathStyleValue !== undefined && forcePathStyleValue !== "true" && forcePathStyleValue !== "false") {
    throw new TypeError("SIGNALBOX_OBJECT_FORCE_PATH_STYLE must be 'true' or 'false'");
  }
  return new S3ArtifactStore({
    bucket,
    region,
    endpoint: environment.SIGNALBOX_OBJECT_ENDPOINT,
    accessKeyId: environment.SIGNALBOX_OBJECT_ACCESS_KEY_ID,
    secretAccessKey: environment.SIGNALBOX_OBJECT_SECRET_ACCESS_KEY,
    forcePathStyle: forcePathStyleValue === undefined ? undefined : forcePathStyleValue === "true",
    prefix: environment.SIGNALBOX_OBJECT_PREFIX,
  });
}


function digest(content: Uint8Array): string {
  return `sha256:${createHash("sha256").update(content).digest("hex")}`;
}

function safeSegment(value: string, name: string): string {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)) throw new TypeError(`${name} is invalid`);
  return value;
}

function objectKey(prefix: string, orgId: string, kind: ArtifactKind, sha256: string): string {
  const hash = sha256.slice("sha256:".length);
  return [prefix, safeSegment(orgId, "orgId"), kind.toLowerCase(), hash.slice(0, 2), hash].filter(Boolean).join("/");
}
function requiredEnvironment(environment: Readonly<Record<string, string | undefined>>, name: string): string {
  const value = environment[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}


export class S3ArtifactStore implements ObjectArtifactStore {
  readonly #bucket: string;
  readonly #prefix: string;
  readonly #client: S3Client;

  constructor(options: S3ArtifactStoreOptions) {
    if (!options.bucket) throw new TypeError("Object storage bucket is required");
    if (!options.region) throw new TypeError("Object storage region is required");
    if ((options.accessKeyId === undefined) !== (options.secretAccessKey === undefined)) {
      throw new TypeError("Object storage access key ID and secret must be configured together");
    }
    this.#bucket = options.bucket;
    this.#prefix = (options.prefix ?? "signalbox").replace(/^\/+|\/+$/g, "");
    this.#client = options.client ?? new S3Client({
      region: options.region,
      endpoint: options.endpoint,
      forcePathStyle: options.forcePathStyle,
      ...(options.accessKeyId && options.secretAccessKey
        ? { credentials: { accessKeyId: options.accessKeyId, secretAccessKey: options.secretAccessKey } }
        : {}),
    });
  }

  async put(orgId: string, kind: ArtifactKind, content: Uint8Array, contentType: string): Promise<StoredObject> {
    if (!contentType || contentType.length > 255) throw new TypeError("Artifact content type is invalid");
    const sha256 = digest(content);
    const key = objectKey(this.#prefix, orgId, kind, sha256);
    await this.#client.send(new PutObjectCommand({
      Bucket: this.#bucket,
      Key: key,
      Body: content,
      ContentType: contentType,
      ChecksumSHA256: Buffer.from(sha256.slice("sha256:".length), "hex").toString("base64"),
      Metadata: { signalbox_sha256: sha256.slice("sha256:".length), signalbox_kind: kind },
    }));
    return { key, sha256, sizeBytes: content.byteLength, contentType };
  }

  async get(key: string): Promise<Uint8Array> {
    if (!key.startsWith(`${this.#prefix}/`)) throw new TypeError("Artifact key is outside the configured prefix");
    const response = await this.#client.send(new GetObjectCommand({ Bucket: this.#bucket, Key: key }));
    if (!response.Body) throw new Error(`Object storage returned an empty body for '${key}'`);
    const content = Uint8Array.from(await response.Body.transformToByteArray());
    verifyContentAddress(key, content);
    return content;
  }
}

export class MemoryArtifactStore implements ObjectArtifactStore {
  readonly #prefix: string;
  readonly #objects = new Map<string, Uint8Array>();

  constructor(prefix = "signalbox") {
    this.#prefix = safeSegment(prefix, "prefix");
  }

  async put(orgId: string, kind: ArtifactKind, content: Uint8Array, contentType: string): Promise<StoredObject> {
    const sha256 = digest(content);
    const key = objectKey(this.#prefix, orgId, kind, sha256);
    this.#objects.set(key, Uint8Array.from(content));
    return { key, sha256, sizeBytes: content.byteLength, contentType };
  }

  async get(key: string): Promise<Uint8Array> {
    const content = this.#objects.get(key);
    if (!content) throw new Error(`Artifact '${key}' does not exist`);
    verifyContentAddress(key, content);
    return Uint8Array.from(content);
  }
}

function verifyContentAddress(key: string, content: Uint8Array): void {
  const expected = key.slice(key.lastIndexOf("/") + 1);
  const actual = digest(content).slice("sha256:".length);
  if (!/^[0-9a-f]{64}$/.test(expected) || actual !== expected) {
    throw new Error(`Artifact '${key}' failed content-address verification`);
  }
}
