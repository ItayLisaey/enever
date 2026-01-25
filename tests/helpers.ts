import { join, dirname } from "path";

// Binary must be built before running tests: `zig build` or `npm test`
const isWindows = process.platform === "win32" || Bun.env.OS?.includes("Windows");
const binaryName = isWindows ? "enever.exe" : "enever";
const BINARY_PATH = join(dirname(import.meta.dir), "zig-out", "bin", binaryName);

export interface RunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export async function run(...args: string[]): Promise<RunResult> {
  const proc = Bun.spawn([BINARY_PATH, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });

  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;

  // Debug: print stderr if exit code is unexpected (not 0 or 2)
  if (exitCode !== 0 && exitCode !== 2 && stderr) {
    console.log(`[DEBUG] run(${args.join(', ')}) stderr:`, stderr);
  }

  return { stdout, stderr, exitCode };
}

export async function runInDir(cwd: string, ...args: string[]): Promise<RunResult> {
  const proc = Bun.spawn([BINARY_PATH, ...args], {
    stdout: "pipe",
    stderr: "pipe",
    cwd,
  });

  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;

  // Debug: print stderr if exit code is unexpected (not 0 or 2)
  if (exitCode !== 0 && exitCode !== 2 && stderr) {
    console.log(`[DEBUG] runInDir(${cwd}, ${args.join(', ')}) stderr:`, stderr);
  }

  return { stdout, stderr, exitCode };
}

export function fixture(name: string): string {
  return join(import.meta.dir, "fixtures", name);
}
