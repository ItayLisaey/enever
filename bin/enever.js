#!/usr/bin/env node

const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

const BINARY_NAME = process.platform === "win32" ? "enever.exe" : "enever";
const BINARY_PATH = path.join(__dirname, BINARY_NAME);

if (!fs.existsSync(BINARY_PATH)) {
  console.error("enever binary not found. Try reinstalling the package:");
  console.error("  npm uninstall enever && npm install enever");
  process.exit(1);
}

const child = spawn(BINARY_PATH, process.argv.slice(2), {
  stdio: "inherit",
  env: process.env,
});

child.on("error", (err) => {
  console.error("Failed to run enever:", err.message);
  process.exit(1);
});

child.on("close", (code) => {
  process.exit(code ?? 0);
});
