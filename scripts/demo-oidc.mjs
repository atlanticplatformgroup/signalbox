// Demo OIDC issuer: generates a signing key, publishes a JWKS, and mints
// human bearer tokens for the Governance Studio.
//
// Signalbox verifies a human bearer against GitHub or an OIDC issuer
// (src/identity.mts). For a hosted demo, GitHub is the wrong tool: sharing a
// personal access token means sharing a GitHub login, and GitHub's terms allow
// only one free account per person. A self-hosted OIDC issuer avoids the third
// party entirely and exercises a real production auth path.
//
// The issuer must serve its key set at <issuer>/.well-known/jwks.json, which
// jose fetches through createRemoteJWKSet. Point a reverse proxy at the
// generated file.
//
//   node scripts/demo-oidc.mjs init  --dir /etc/signalbox --jwks /var/www/wellknown/jwks.json
//   node scripts/demo-oidc.mjs mint  --dir /etc/signalbox \
//        --issuer https://demo.example.com --audience signalbox-demo \
//        --subject demo-reviewer --expires 2027-01-31
//
// The private key never leaves --dir. Only the public JWKS is published.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { exportJWK, exportPKCS8, generateKeyPair, importPKCS8, SignJWT } from "jose";

const ALG = "RS256";
const KID = "signalbox-demo";

function argument(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) {
    if (fallback === undefined) throw new Error(`--${name} is required`);
    return fallback;
  }
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`--${name} requires a value`);
  return value;
}

const command = process.argv[2];
if (command !== "init" && command !== "mint") {
  throw new Error("usage: demo-oidc.mjs <init|mint> [options]");
}

const dir = argument("dir", "/etc/signalbox");
const privatePath = join(dir, "oidc-private.pem");

if (command === "init") {
  const jwksPath = argument("jwks");
  const { privateKey, publicKey } = await generateKeyPair(ALG, { extractable: true });
  const jwk = await exportJWK(publicKey);
  jwk.kid = KID;
  jwk.alg = ALG;
  jwk.use = "sig";

  await mkdir(dir, { recursive: true, mode: 0o700 });
  await writeFile(privatePath, await exportPKCS8(privateKey), { encoding: "utf8", mode: 0o600 });
  await mkdir(dirname(jwksPath), { recursive: true });
  await writeFile(jwksPath, `${JSON.stringify({ keys: [jwk] }, null, 2)}\n`, { encoding: "utf8", mode: 0o644 });

  process.stdout.write(`${JSON.stringify({ action: "init", privateKey: privatePath, jwks: jwksPath, kid: KID, alg: ALG }, null, 2)}\n`);
} else {
  const issuer = argument("issuer");
  const audience = argument("audience");
  const subject = argument("subject", "demo-reviewer");
  const expiresRaw = argument("expires", "2027-01-31");
  const expiresAt = new Date(`${expiresRaw}T00:00:00Z`);
  if (Number.isNaN(expiresAt.getTime())) throw new Error(`--expires must be a date, received '${expiresRaw}'`);
  if (expiresAt <= new Date()) throw new Error("--expires must be in the future");

  const privateKey = await importPKCS8(await readFile(privatePath, "utf8"), ALG);
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: ALG, kid: KID })
    .setIssuer(issuer)
    .setSubject(subject)
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(privateKey);

  process.stdout.write(`${JSON.stringify({
    action: "mint",
    issuer,
    audience,
    subject,
    expiresAt: expiresAt.toISOString(),
    bindSubjectAs: subject,
    token,
  }, null, 2)}\n`);
}
