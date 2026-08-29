#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

function run(command, args) {
  const result = spawnSync(command, args, { stdio: "inherit", shell: process.platform === "win32" });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

run("npm", ["run", "modellang:check"]);
run("npm", ["run", "modellang:build"]);
run("npm", ["run", "generated:build"]);
run("npm", ["run", "host:build"]);

const generated = await import(pathToFileURL(resolve("generated/signalbox/dist/mcp-server.js")).href);
const host = await import(pathToFileURL(resolve("dist/boundary.mjs")).href);
if (typeof generated.createSignalboxMcpHandler !== "function" || typeof host.createSignalboxBoundary !== "function") {
  throw new Error("Generated MCP or authenticated host boundary export is missing");
}
console.log("ModelLang smoke check passed: model, generated runtime, authenticated host, REST, and MCP imports.");
