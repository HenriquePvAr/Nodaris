import { execFile } from "node:child_process";
import { lstat, readFile, realpath } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { secretContent, secretName } from "./filesystem.js";
import type { Project } from "./contracts.js";

const run = promisify(execFile);
function safeEnvironment(): NodeJS.ProcessEnv {
  const environment = { ...process.env };
  for (const key of Object.keys(environment)) if (key.startsWith("GIT_")) delete environment[key];
  environment["GIT_CONFIG_NOSYSTEM"] = "1";
  environment["GIT_PAGER"] = "cat";
  environment["PAGER"] = "cat";
  environment["GIT_OPTIONAL_LOCKS"] = "0";
  environment["GIT_TERMINAL_PROMPT"] = "0";
  return environment;
}

async function assertSafeRepository(project: Project): Promise<void> {
  const marker = path.join(project.path, ".git");
  const info = await lstat(marker);
  if (!info.isDirectory() || info.isSymbolicLink())
    throw new Error("Consultas Git bloqueadas para repositório com metadados externos.");
  const canonical = await realpath(marker);
  const relative = path.relative(project.path, canonical);
  if (relative.startsWith("..") || path.isAbsolute(relative))
    throw new Error("Metadados Git fora do projeto autorizado.");
}

const safeGit = async (project: Project, args: string[], maxBuffer = 200_000): Promise<string> => {
  await assertSafeRepository(project);
  const result = await run(
    "git",
    ["-C", project.path, "-c", "core.fsmonitor=false", "-c", "core.pager=cat", ...args],
    {
      timeout: 5_000,
      maxBuffer,
      windowsHide: true,
      env: safeEnvironment()
    }
  );
  return result.stdout;
};

export async function gitStatus(project: Project): Promise<string> {
  return safeGit(project, ["status", "--short", "--branch"]);
}

export async function gitLog(project: Project, limit: number): Promise<string> {
  return safeGit(project, ["log", `-${limit}`, "--date=iso-strict", "--pretty=format:%h %ad %s"]);
}

export async function gitDiff(project: Project): Promise<string> {
  const changedPaths = (await safeGit(project, ["diff", "--name-only", "-z", "HEAD"]))
    .split("\0")
    .filter(Boolean);
  if (changedPaths.some((file) => secretName.test(path.basename(file)))) {
    throw new Error("Diff bloqueado porque o repositório contém arquivos sensíveis alterados.");
  }
  for (const relative of (await safeGit(project, ["ls-files", "--cached", "-z"]))
    .split("\0")
    .filter(Boolean)) {
    if (path.basename(relative) !== ".gitattributes") continue;
    const attributesPath = path.join(project.path, relative);
    const attributesInfo = await lstat(attributesPath);
    if (!attributesInfo.isFile() || attributesInfo.isSymbolicLink())
      throw new Error("Diff bloqueado porque .gitattributes não é arquivo regular.");
    const canonical = await realpath(attributesPath);
    if (!canonical.startsWith(`${path.resolve(project.path)}${path.sep}`))
      throw new Error("Diff bloqueado porque .gitattributes sai do projeto.");
    const content = await readFile(canonical, "utf8");
    if (/\bfilter\s*=|\btextconv\s*=|\bdiff\s*=\s*\S+/i.test(content))
      throw new Error("Diff bloqueado porque o repositório configura filtros Git externos.");
  }
  const output = await safeGit(
    project,
    ["diff", "--no-ext-diff", "--no-textconv", "--binary", "HEAD", "--", "."],
    300_000
  );
  if (Buffer.byteLength(output, "utf8") > 200_000)
    throw new Error("Diff excede o limite de 200 KB.");
  if (secretContent.test(output))
    throw new Error("Diff bloqueado por conter conteúdo que parece credencial.");
  if (/^\+.*(?:password|api[_-]?key|token|secret)\s*[:=]\s*\S+/im.test(output))
    throw new Error("Diff bloqueado por conter uma possível credencial.");
  return output;
}
