#!/usr/bin/env node

const https = require("https");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const zlib = require("zlib");

const REPO = "itaylisaey/enever";
const BIN_DIR = path.join(__dirname, "..", "bin");
const BINARY_NAME = process.platform === "win32" ? "enever.exe" : "enever";
const BINARY_PATH = path.join(BIN_DIR, BINARY_NAME);

function getPlatformInfo() {
  const platform = process.platform;
  const arch = process.arch;

  const platformMap = {
    darwin: "darwin",
    linux: "linux",
    win32: "windows",
  };

  const archMap = {
    x64: "x86_64",
    arm64: "aarch64",
  };

  const mappedPlatform = platformMap[platform];
  const mappedArch = archMap[arch];

  if (!mappedPlatform || !mappedArch) {
    throw new Error(`Unsupported platform: ${platform}-${arch}`);
  }

  const extension = platform === "win32" ? "zip" : "tar.gz";
  const artifactName = `enever-${mappedPlatform}-${mappedArch}.${extension}`;

  return { artifactName, extension };
}

function httpsGet(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { "User-Agent": "enever-npm" } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          httpsGet(res.headers.location).then(resolve).catch(reject);
          return;
        }
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode}: ${res.statusMessage}`));
          return;
        }
        resolve(res);
      })
      .on("error", reject);
  });
}

async function getLatestReleaseUrl(artifactName) {
  const apiUrl = `https://api.github.com/repos/${REPO}/releases/latest`;

  return new Promise((resolve, reject) => {
    https
      .get(apiUrl, { headers: { "User-Agent": "enever-npm" } }, (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          if (res.statusCode !== 200) {
            reject(new Error(`Failed to fetch release info: HTTP ${res.statusCode}`));
            return;
          }
          try {
            const release = JSON.parse(data);
            const asset = release.assets.find((a) => a.name === artifactName);
            if (!asset) {
              reject(new Error(`No binary found for ${artifactName}`));
              return;
            }
            resolve(asset.browser_download_url);
          } catch (e) {
            reject(e);
          }
        });
      })
      .on("error", reject);
  });
}

async function downloadAndExtract(url, extension) {
  console.log(`Downloading from ${url}...`);

  const res = await httpsGet(url);
  const chunks = [];

  return new Promise((resolve, reject) => {
    res.on("data", (chunk) => chunks.push(chunk));
    res.on("end", () => {
      const buffer = Buffer.concat(chunks);

      if (!fs.existsSync(BIN_DIR)) {
        fs.mkdirSync(BIN_DIR, { recursive: true });
      }

      if (extension === "tar.gz") {
        const tempTar = path.join(BIN_DIR, "temp.tar.gz");
        fs.writeFileSync(tempTar, buffer);

        try {
          execSync(`tar -xzf "${tempTar}" -C "${BIN_DIR}"`, { stdio: "inherit" });
          fs.unlinkSync(tempTar);
          fs.chmodSync(BINARY_PATH, 0o755);
          resolve();
        } catch (e) {
          reject(e);
        }
      } else if (extension === "zip") {
        const tempZip = path.join(BIN_DIR, "temp.zip");
        fs.writeFileSync(tempZip, buffer);

        try {
          execSync(`powershell -Command "Expand-Archive -Path '${tempZip}' -DestinationPath '${BIN_DIR}' -Force"`, {
            stdio: "inherit",
          });
          fs.unlinkSync(tempZip);
          resolve();
        } catch (e) {
          reject(e);
        }
      }
    });
    res.on("error", reject);
  });
}

async function main() {
  try {
    if (fs.existsSync(BINARY_PATH)) {
      console.log("enever binary already exists, skipping download.");
      return;
    }

    const { artifactName, extension } = getPlatformInfo();
    console.log(`Installing enever for ${process.platform}-${process.arch}...`);

    const downloadUrl = await getLatestReleaseUrl(artifactName);
    await downloadAndExtract(downloadUrl, extension);

    console.log("enever installed successfully!");
  } catch (error) {
    console.error("Failed to install enever:", error.message);
    console.error("You can download the binary manually from:");
    console.error(`https://github.com/${REPO}/releases`);
    process.exit(1);
  }
}

main();
