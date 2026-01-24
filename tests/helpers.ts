import { join, dirname } from "path";

// Binary must be built before running tests: `zig build` or `npm test`
const BINARY_PATH = join(dirname(import.meta.dir), "zig-out/bin/enever");

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

  return { stdout, stderr, exitCode };
}

export function fixture(name: string): string {
  return join(import.meta.dir, "fixtures", name);
}
