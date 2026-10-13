// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { afterEach, describe, expect, it } from "vitest";
import { ProjectStore } from "../packages/core/src/filesystem.js";
import { gitDiff, gitLog, gitStatus } from "../packages/core/src/git.js";

const exec = promisify(execFile);
const temporaryDirectories: string[] = [];
async function tempDir(): Promise<string> {
  const directory = await mkdtemp(path.join(tmpdir(), "nodaris-test-"));
  temporaryDirectories.push(directory);
  return directory;
}
afterEach(async () => {
  await Promise.all(
    temporaryDirectories
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true }))
  );
});

describe("isolamento do filesystem", () => {
  it("descobre projetos Git e projetos sem Git, sem retornar vazios", async () => {
    const root = await tempDir();
    await mkdir(path.join(root, "repo"));
    await mkdir(path.join(root, "sem-git"));
    await mkdir(path.join(root, "repo", ".git"));
    await writeFile(path.join(root, "sem-git", "package.json"), "{}");
    const store = await ProjectStore.create([root], "test-machine");
    const result = await store.discover();
    expect(result).toHaveLength(2);
    expect(result.map((project) => project.kind).sort()).toEqual(["git", "package.json"]);
    expect(await (await ProjectStore.create([await tempDir()], "empty")).discover()).toEqual([]);
  });

  it("rejeita traversal, caminhos absolutos, segredos e .git", async () => {
    const root = await tempDir();
    await mkdir(path.join(root, "app"));
    await writeFile(path.join(root, "app", "package.json"), "{}");
    await writeFile(path.join(root, "app", ".env"), "SECRET=never");
    await writeFile(path.join(root, "app", ".env.example"), "NODARIS_TOKEN=\n");
    await writeFile(
      path.join(root, "app", "config.ts"),
      'const API_KEY = "AbcdefghijklmnopQRSTUV";\n'
    );
    const store = await ProjectStore.create([root], "m");
    const project = (await store.discover())[0]!;
    await expect(store.readText(project.id, "../outside.txt")).rejects.toThrow();
    await expect(
      store.readText(project.id, path.join(root, "app", "package.json"))
    ).rejects.toThrow();
    await expect(store.readText(project.id, ".env")).rejects.toThrow();
    await expect(store.readText(project.id, "config.ts")).rejects.toThrow();
    await expect(store.readText(project.id, ".env.example")).resolves.toContain("NODARIS_TOKEN");
    await expect(store.readText(project.id, ".git/config")).rejects.toThrow();
  });

  it("bloqueia links simbólicos e conteúdo binário ou acima do limite", async () => {
    const root = await tempDir();
    const projectPath = path.join(root, "app");
    await mkdir(projectPath);
    await writeFile(path.join(projectPath, "package.json"), "{}");
    await writeFile(path.join(projectPath, "image.png"), Buffer.from([0, 1, 2]));
    await writeFile(path.join(projectPath, "large.txt"), "x".repeat(1_000_001));
    const outside = path.join(root, "outside.txt");
    await writeFile(outside, "não ler");
    let linkCreated = true;
    try {
      await symlink(outside, path.join(projectPath, "link.txt"));
    } catch {
      /* Windows pode exigir Developer Mode/privilégio; o teste é omitido nessa condição. */
      linkCreated = false;
    }
    const store = await ProjectStore.create([root], "m");
    const project = (await store.discover())[0]!;
    await expect(store.readText(project.id, "image.png")).rejects.toThrow();
    await expect(store.readText(project.id, "large.txt")).rejects.toThrow();
    if (linkCreated) {
      await expect(store.readText(project.id, "link.txt")).rejects.toThrow();
    }
  });
});

describe("consultas Git", () => {
  it("reporta status limpo, mudanças, diff e log com limite", async () => {
    const root = await tempDir();
    await exec("git", ["init", root]);
    await exec("git", ["-C", root, "config", "user.email", "nodaris@example.invalid"]);
    await exec("git", ["-C", root, "config", "user.name", "Nodaris Test"]);
    await writeFile(path.join(root, "README.md"), "inicial\n");
    await exec("git", ["-C", root, "add", "README.md"]);
    await exec("git", ["-C", root, "commit", "-m", "inicial"]);
    const project = {
      id: "p",
      machineId: "m",
      name: "repo",
      path: root,
      kind: "git",
      languages: []
    };
    expect(await gitStatus(project)).toContain("##");
    expect(await gitLog(project, 1)).toContain("inicial");
    await writeFile(path.join(root, "README.md"), "alterado\n");
    expect(await gitStatus(project)).toContain("M");
    expect(await gitDiff(project)).toContain("alterado");
    await writeFile(path.join(root, "README.md"), 'private_token = "AbcdefghijklmnopQRSTUV"\n');
    await expect(gitDiff(project)).rejects.toThrow(/credencial/);
  });
});
