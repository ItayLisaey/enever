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

/** Run the binary in `cwd`, piping `input` to its stdin. */
export async function runWithInput(
  input: string,
  cwd: string,
  ...args: string[]
): Promise<RunResult> {
  const proc = Bun.spawn([BINARY_PATH, ...args], {
    stdin: new TextEncoder().encode(input),
    stdout: "pipe",
    stderr: "pipe",
    cwd,
  });

  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;

  return { stdout, stderr, exitCode };
}

/** Create a fresh empty temp directory for mutation tests. */
export function tempDir(): string {
  const dir = join(
    require("os").tmpdir(),
    `enever-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  require("fs").mkdirSync(dir, { recursive: true });
  return dir;
}
