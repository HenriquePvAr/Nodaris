// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { createHash } from "node:crypto";
import { lstat, readdir, readFile, realpath, stat } from "node:fs/promises";
import path from "node:path";
import type { Project } from "./contracts.js";

const ignored = new Set([
  ".git",
  "node_modules",
  ".pnpm-store",
  "dist",
  "build",
  "coverage",
  ".next",
  ".cache",
  ".aws",
  ".ssh",
  ".gnupg",
  ".azure",
  ".kube",
  "vendor",
  "target"
]);
const secretName =
  /(^|\.)env($|\.)|(^|[._-])(id_rsa|id_ed25519|credentials|secrets?|service-account|firebase-adminsdk|npmrc|pypirc|netrc|dockerconfigjson)([._-]|$)|\.(pem|key|p12|pfx|keystore)$/i;
const secretContent =
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|(?:password|api[_-]?key|access[_-]?token|client[_-]?secret|secret|token)\s*[:=]\s*["']?(?!<|\$\{|your_|changeme)[A-Za-z0-9/+=_.-]{16,})/i;
const textExtensions = new Set([
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".cjs",
  ".json",
  ".md",
  ".txt",
  ".yml",
  ".yaml",
  ".toml",
  ".css",
  ".html",
  ".py",
  ".go",
  ".rs",
  ".java",
  ".kt",
  ".cs",
  ".sh",
  ".ps1",
  ".sql",
  ".xml",
  ".svg",
  ".env.example"
]);
const languageByExt: Record<string, string> = {
  ".ts": "TypeScript",
  ".tsx": "TypeScript",
  ".js": "JavaScript",
  ".jsx": "JavaScript",
  ".py": "Python",
  ".go": "Go",
  ".rs": "Rust",
  ".java": "Java",
  ".cs": "C#"
};

function inside(parent: string, candidate: string): boolean {
  const relative = path.relative(parent, candidate);
  return (
    relative === "" ||
    (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative))
  );
}

async function rejectSymlinkComponents(root: string, target: string): Promise<void> {
  const relative = path.relative(root, target);
  if (relative.startsWith("..") || path.isAbsolute(relative))
    throw new Error("Acesso fora das raízes autorizadas.");
  let current = root;
  for (const segment of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    const entry = await lstat(current);
    if (entry.isSymbolicLink()) throw new Error("Acesso por link simbólico não é permitido.");
  }
}

export class ProjectStore {
  private readonly projects = new Map<string, Project>();
  private readonly roots: string[];

  private constructor(
    roots: string[],
    private readonly machineId: string
  ) {
    this.roots = roots;
  }

  static async create(configuredRoots: string[], machineId: string): Promise<ProjectStore> {
    const roots: string[] = [];
    for (const configured of configuredRoots) {
      const canonical = await realpath(path.resolve(configured));
      if (!(await stat(canonical)).isDirectory())
        throw new Error("Raiz autorizada precisa ser um diretório.");
      if (!(await lstat(canonical)).isSymbolicLink()) roots.push(canonical);
    }
    return new ProjectStore([...new Set(roots)], machineId);
  }

  async discover(): Promise<Project[]> {
    this.projects.clear();
    let totalEntries = 0;
    const visit = async (directory: string, depth: number): Promise<void> => {
      if (depth > 5 || totalEntries >= 5000) return;
      let entries;
      try {
        entries = await readdir(directory, { withFileTypes: true });
      } catch {
        return;
      }
      totalEntries += entries.length;
      const names = new Set(entries.map((entry) => entry.name));
      const gitEntry = entries.find((entry) => entry.name === ".git");
      // Worktrees usam um arquivo apontador para fora do projeto; não os tratamos como repo permitido.
      const isGit = gitEntry?.isDirectory() === true;
      const configFile = [
        "package.json",
        "pyproject.toml",
        "Cargo.toml",
        "go.mod",
        "pom.xml",
        "Makefile"
      ].find((name) => names.has(name));
      if (isGit || configFile) {
        const id = createHash("sha256")
          .update(
            `${this.machineId}\0${process.platform === "win32" ? directory.toLocaleLowerCase() : directory}`
          )
          .digest("hex")
          .slice(0, 24);
        const languages = [
          ...new Set(
            entries
              .map((entry) => languageByExt[path.extname(entry.name).toLowerCase()])
              .filter((value): value is string => Boolean(value))
          )
        ];
        this.projects.set(id, {
          id,
          machineId: this.machineId,
          name: path.basename(directory),
          path: directory,
          kind: isGit ? "git" : (configFile ?? "projeto"),
          languages
        });
        return;
      }
      for (const entry of entries) {
        if (
          !entry.isDirectory() ||
          ignored.has(entry.name.toLowerCase()) ||
          entry.name.startsWith(".")
        )
          continue;
        const candidate = path.join(directory, entry.name);
        try {
          if (!(await lstat(candidate)).isSymbolicLink()) await visit(candidate, depth + 1);
        } catch {
          /* entradas que mudaram são ignoradas */
        }
      }
    };
    for (const root of this.roots) await visit(root, 0);
    return [...this.projects.values()];
  }

  list(): Project[] {
    return [...this.projects.values()];
  }
  getProject(id: string): Project {
    const project = this.projects.get(id);
    if (!project) throw new Error("Projeto não encontrado ou não autorizado.");
    return project;
  }

  async resolveFile(projectId: string, relativePath: string): Promise<string> {
    const project = this.getProject(projectId);
    if (
      path.isAbsolute(relativePath) ||
      /^[a-z]:/i.test(relativePath) ||
      relativePath.startsWith("\\\\") ||
      relativePath.includes("\0")
    )
      throw new Error("Caminho inválido.");
    const segments = relativePath.replaceAll("\\", "/").split("/");
    if (process.platform === "win32" && segments.some((part) => part.includes(":")))
      throw new Error("Fluxos de dados alternativos NTFS não são permitidos.");
    if (
      segments.some(
        (part) =>
          part === ".." ||
          part.toLowerCase() === ".git" ||
          (part.toLowerCase() !== ".env.example" && secretName.test(part))
      )
    )
      throw new Error("Caminho bloqueado pela política de segurança.");
    const candidate = path.resolve(project.path, relativePath);
    if (!inside(project.path, candidate)) throw new Error("Acesso fora do projeto autorizado.");
    await rejectSymlinkComponents(project.path, candidate);
    if (!inside(project.path, await realpath(candidate)))
      throw new Error("Acesso fora do projeto autorizado.");
    return candidate;
  }

  async readText(projectId: string, relativePath: string): Promise<string> {
    const file = await this.resolveFile(projectId, relativePath);
    const fileStat = await stat(file);
    if (!fileStat.isFile() || fileStat.size > 1_000_000)
      throw new Error("Arquivo inválido ou acima do limite de 1 MB.");
    const extension = path.extname(file).toLowerCase();
    if (
      !textExtensions.has(extension) &&
      path.basename(file).toLowerCase() !== ".env.example" &&
      path.basename(file) !== "LICENSE"
    )
      throw new Error("Tipo de arquivo não textual permitido.");
    const bytes = await readFile(file);
    if (bytes.includes(0)) throw new Error("Arquivo binário não pode ser lido.");
    const text = bytes.toString("utf8");
    if (secretContent.test(text)) throw new Error("Conteúdo potencialmente sensível bloqueado.");
    return text;
  }

  async tree(projectId: string, relativePath = "", maxDepth = 4): Promise<string[]> {
    const base = relativePath
      ? await this.resolveFile(projectId, relativePath)
      : this.getProject(projectId).path;
    const output: string[] = [];
    const walk = async (directory: string, depth: number): Promise<void> => {
      if (depth > maxDepth || output.length >= 500) return;
      let entries;
      try {
        entries = await readdir(directory, { withFileTypes: true });
      } catch {
        return;
      }
      entries.sort((a, b) => a.name.localeCompare(b.name));
      for (const entry of entries) {
        if (output.length >= 500) break;
        if (
          ignored.has(entry.name.toLowerCase()) ||
          (entry.name.toLowerCase() !== ".env.example" && secretName.test(entry.name))
        )
          continue;
        if (entry.isSymbolicLink()) continue;
        const full = path.join(directory, entry.name);
        output.push(
          path.relative(this.getProject(projectId).path, full).replaceAll("\\", "/") +
            (entry.isDirectory() ? "/" : "")
        );
        if (entry.isDirectory()) await walk(full, depth + 1);
      }
    };
    await walk(base, 0);
    return output;
  }

  async search(
    projectId: string,
    query: string,
    maxResults: number
  ): Promise<Array<{ path: string; line: number; text: string }>> {
    const results: Array<{ path: string; line: number; text: string }> = [];
    const base = this.getProject(projectId).path;
    const files = await this.tree(projectId, "", 6);
    for (const relative of files) {
      if (results.length >= maxResults) break;
      if (
        relative.endsWith("/") ||
        (!textExtensions.has(path.extname(relative).toLowerCase()) &&
          path.basename(relative).toLowerCase() !== ".env.example")
      )
        continue;
      try {
        const content = await this.readText(projectId, relative);
        content.split(/\r?\n/).forEach((line, index) => {
          if (
            results.length < maxResults &&
            line.toLocaleLowerCase().includes(query.toLocaleLowerCase())
          )
            results.push({
              path: path.relative(base, path.join(base, relative)).replaceAll("\\", "/"),
              line: index + 1,
              text: line.slice(0, 300)
            });
        });
      } catch {
        /* binários, arquivos sensíveis e entradas voláteis são ignorados */
      }
    }
    return results;
  }
}

export { secretContent, secretName };
