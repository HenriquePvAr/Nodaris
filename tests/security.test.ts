// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { performance } from "node:perf_hooks";
import { afterEach, describe, expect, it } from "vitest";
import { vi } from "vitest";
import { ProjectStore } from "../packages/core/src/filesystem.js";
import { loadConfig } from "../packages/core/src/config.js";
import { gitDiff, gitLog, gitStatus } from "../packages/core/src/git.js";
import { NodarisError, safeError } from "../packages/core/src/errors.js";

describe("classificação segura de erros", () => {
  it("não expõe exceções nativas, caminhos absolutos ou sentinelas", () => {
    const sentinel = "C:\\Users\\PrivateFixture\\secret-sentinel.txt API_TOKEN=sentinel-value";
    const mapped = safeError(new Error(`ENOENT ${sentinel}`), "file.read");
    expect(mapped).toEqual({
      code: "FILESYSTEM_FAILURE",
      message: "Falha ao processar arquivo ou diretório.",
      reason: "filesystem.failure"
    });
    expect(JSON.stringify(mapped)).not.toContain(sentinel);
    const denied = Object.assign(new Error(`EACCES ${sentinel}`), { code: "EACCES" });
    expect(JSON.stringify(safeError(denied, "file.read"))).not.toContain(sentinel);
    expect(
      JSON.stringify(safeError(new Error(`git stderr ${sentinel}`), "git.status"))
    ).not.toContain(sentinel);
  });

  it("preserva somente mensagens funcionais tipadas e códigos de pesquisa seguros", () => {
    expect(safeError(new NodarisError("ADS_BLOCKED")).message).toBe(
      "Fluxos de dados alternativos NTFS não são permitidos."
    );
    expect(safeError(new NodarisError("SYMLINK_BLOCKED")).message).toBe(
      "Acesso por link simbólico não é permitido."
    );
    expect(safeError(new NodarisError("SEARCH_LIMIT")).message).toBe(
      "Pesquisa interrompida pelo limite de recursos."
    );
    expect(safeError(new NodarisError("SEARCH_CONCURRENCY_LIMIT")).message).toBe(
      "Limite de pesquisas simultâneas atingido."
    );
    expect(safeError(new Error("arbitrary private text")).message).toBe("Falha interna.");
  });
});

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

describe("bind local obrigatório", () => {
  const baseEnv: NodeJS.ProcessEnv = { NODARIS_TOKEN: "a".repeat(64) };

  it("aceita o endereço IPv4 literal de loopback por padrão e explicitamente", () => {
    const defaults = loadConfig(baseEnv);
    expect(defaults.gatewayHost).toBe("127.0.0.1");
    expect(defaults.agentHost).toBe("127.0.0.1");
    expect(
      loadConfig({ ...baseEnv, GATEWAY_HOST: "127.0.0.1", AGENT_HOST: "127.0.0.1" })
    ).toMatchObject({ gatewayHost: "127.0.0.1", agentHost: "127.0.0.1" });
  });

  it.each([
    "0.0.0.0",
    "::",
    "::1",
    "localhost",
    "192.0.2.10",
    "10.0.0.5",
    "127.0.0.2",
    "::ffff:127.0.0.1",
    " 127.0.0.1"
  ])("rejeita bind não autorizado: %s", (host) => {
    expect(() => loadConfig({ ...baseEnv, GATEWAY_HOST: host })).toThrow();
    expect(() => loadConfig({ ...baseEnv, AGENT_HOST: host })).toThrow();
  });

  it("faz agente e gateway validarem configuração antes de criar listeners", async () => {
    const agentSource = await readFile(
      new URL("../apps/agent/src/index.ts", import.meta.url),
      "utf8"
    );
    const gatewaySource = await readFile(
      new URL("../apps/gateway/src/index.ts", import.meta.url),
      "utf8"
    );

    expect(agentSource.indexOf("const config = loadConfig()")).toBeLessThan(
      agentSource.indexOf("const server = createServer")
    );
    expect(agentSource.indexOf("const config = loadConfig()")).toBeLessThan(
      agentSource.indexOf("server.listen(")
    );
    expect(gatewaySource.indexOf("const config = loadConfig()")).toBeLessThan(
      gatewaySource.indexOf("const http = createServer")
    );
    expect(gatewaySource.indexOf("const config = loadConfig()")).toBeLessThan(
      gatewaySource.indexOf("http.listen(")
    );
  });
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

  it.skipIf(process.platform !== "win32")(
    "rejeita Alternate Data Streams NTFS antes de leitura, árvore e pesquisa",
    async ({ skip }) => {
      const root = await tempDir();
      const projectPath = path.join(root, "app");
      await mkdir(projectPath);
      await writeFile(path.join(projectPath, "package.json"), "{}");
      await writeFile(path.join(projectPath, "README.md"), "consulta segura\n");
      const streamPath = path.join(projectPath, "README.md:nodaris-ads-fixture");
      try {
        await writeFile(streamPath, "conteudo-ads-fixture\n");
        expect(await readFile(streamPath, "utf8")).toContain("conteudo-ads-fixture");
      } catch {
        skip("O filesystem temporário não permite criar Alternate Data Streams NTFS.");
        return;
      }

      const store = await ProjectStore.create([root], "ads-test");
      const project = (await store.discover())[0]!;
      const variants = [
        "README.md:nodaris-ads-fixture",
        "README.md::$DATA",
        "nested\\README.md:nodaris-ads-fixture",
        "nested/README.md:nodaris-ads-fixture",
        "nested\\..\\README.md:nodaris-ads-fixture"
      ];
      for (const relativePath of variants) {
        await expect(store.resolveFile(project.id, relativePath)).rejects.toThrow(
          /fluxos de dados alternativos/i
        );
        await expect(store.readText(project.id, relativePath)).rejects.toThrow(
          /fluxos de dados alternativos/i
        );
        await expect(store.tree(project.id, relativePath)).rejects.toThrow(
          /fluxos de dados alternativos/i
        );
      }
      await expect(store.readText(project.id, "README.md")).resolves.toContain("consulta segura");
      await expect(store.search(project.id, "conteudo-ads-fixture", 10)).resolves.toEqual([]);
      await expect(store.search(project.id, "consulta segura", 10)).resolves.toHaveLength(1);
    },
    10_000
  );
});

describe("orçamento agregado da pesquisa de código", () => {
  async function createSearchStore(): Promise<{
    projectPath: string;
    store: ProjectStore;
    projectId: string;
  }> {
    const root = await tempDir();
    const projectPath = path.join(root, "app");
    await mkdir(projectPath);
    await writeFile(path.join(projectPath, "package.json"), "{}");
    const store = await ProjectStore.create([root], "search-budget-test");
    const project = (await store.discover()).find((candidate) => candidate.path === projectPath);
    if (!project) throw new Error("Fixture de pesquisa não foi descoberta.");
    return { projectPath, store, projectId: project.id };
  }

  it("retorna pesquisa pequena, preserva resultados vazios e ignora arquivos sensíveis", async () => {
    const { projectPath, store, projectId } = await createSearchStore();
    await writeFile(path.join(projectPath, "README.md"), "linha segura\nneedle encontrada\n");
    await writeFile(path.join(projectPath, ".env"), "needle=segredo-fixture\n");
    await writeFile(
      path.join(projectPath, "unsafe.ts"),
      'const API_KEY = "AbcdefghijklmnopQRSTUV";\nneedle segredo\n'
    );
    const outside = path.join(path.dirname(projectPath), "outside.ts");
    await writeFile(outside, "needle fora do projeto\n");
    try {
      await symlink(outside, path.join(projectPath, "linked.ts"));
    } catch {
      /* O sistema pode impedir symlinks; os demais casos continuam isolados. */
    }

    await expect(store.search(projectId, "needle", 10)).resolves.toEqual([
      { path: "README.md", line: 2, text: "needle encontrada" }
    ]);
    await expect(store.search(projectId, "ausente", 10)).resolves.toEqual([]);
  });

  it("falha sem retornar resultados parciais ao atingir o orçamento de arquivos", async () => {
    const { projectPath, store, projectId } = await createSearchStore();
    await Promise.all(
      Array.from({ length: 201 }, (_, index) =>
        writeFile(path.join(projectPath, `${index.toString().padStart(3, "0")}.ts`), "needle\n")
      )
    );

    await expect(store.search(projectId, "needle", 500)).rejects.toThrow(
      "Pesquisa interrompida pelo limite de recursos."
    );
    await Promise.all(
      Array.from({ length: 201 }, (_, index) =>
        rm(path.join(projectPath, `${index.toString().padStart(3, "0")}.ts`), { force: true })
      )
    );
    await expect(store.search(projectId, "needle", 10)).resolves.toEqual([]);
  });

  it("falha sem retornar resultados parciais ao atingir o orçamento acumulado de bytes", async () => {
    const { projectPath, store, projectId } = await createSearchStore();
    const prefix = 'const API_KEY = "AbcdefghijklmnopQRSTUV";\n';
    const contents = prefix + "x".repeat(1_000_000 - Buffer.byteLength(prefix));
    const files = Array.from({ length: 9 }, (_, index) => path.join(projectPath, `${index}.txt`));
    await Promise.all(files.map((file) => writeFile(file, contents)));

    await expect(store.search(projectId, "needle", 20)).rejects.toThrow(
      "Pesquisa interrompida pelo limite de recursos."
    );
    await Promise.all(files.map((file) => rm(file, { force: true })));
    await expect(store.search(projectId, "needle", 10)).resolves.toEqual([]);
  });

  it("aplica o limite de duração após operações assíncronas e libera o handle", async () => {
    const { projectPath, store, projectId } = await createSearchStore();
    await writeFile(path.join(projectPath, "README.md"), "needle\n");
    let clockCalls = 0;
    const clock = vi.spyOn(performance, "now").mockImplementation(() => {
      clockCalls++;
      return clockCalls < 4 ? 0 : Number.MAX_SAFE_INTEGER;
    });
    try {
      await expect(store.search(projectId, "needle", 10)).rejects.toThrow(
        "Pesquisa interrompida pelo limite de recursos."
      );
      expect(clockCalls).toBeGreaterThanOrEqual(4);
    } finally {
      clock.mockRestore();
    }
    await expect(store.search(projectId, "needle", 10)).resolves.toHaveLength(1);
  });

  it("responde no prazo sem iniciar novas operações após o timeout", async () => {
    const { projectPath, store, projectId } = await createSearchStore();
    await writeFile(path.join(projectPath, "README.md"), "needle\n");
    let signalEntered!: () => void;
    let releaseOperation!: () => void;
    const entered = new Promise<void>((resolve) => {
      signalEntered = resolve;
    });
    const pendingOperation = new Promise<void>((resolve) => {
      releaseOperation = resolve;
    });
    const internals = store as unknown as {
      resolveFileWithCheckpoint: (
        id: string,
        relativePath: string,
        checkpoint: () => void
      ) => Promise<string>;
    };
    const originalResolve = internals.resolveFileWithCheckpoint.bind(store);
    const resolveSpy = vi
      .spyOn(internals, "resolveFileWithCheckpoint")
      .mockImplementation(async (id, relativePath, checkpoint) => {
        signalEntered();
        await pendingOperation;
        return originalResolve(id, relativePath, checkpoint);
      });

    vi.useFakeTimers();
    try {
      const search = store.search(projectId, "needle", 10);
      const rejectedSearch = expect(search).rejects.toThrow(
        "Pesquisa interrompida pelo limite de recursos."
      );
      await entered;
      await vi.advanceTimersByTimeAsync(5_000);
      await rejectedSearch;
      expect(resolveSpy).toHaveBeenCalledTimes(1);

      releaseOperation();
      await vi.advanceTimersByTimeAsync(0);
      await Promise.resolve();
    } finally {
      releaseOperation();
      resolveSpy.mockRestore();
      vi.useRealTimers();
    }
    await new Promise<void>((resolve) => setImmediate(resolve));
    await expect(store.search(projectId, "needle", 10)).resolves.toHaveLength(1);
  });

  it("rejeita chamadas simultâneas excedentes sem fila e libera o limite após conclusão", async () => {
    const { projectPath, store, projectId } = await createSearchStore();
    await writeFile(path.join(projectPath, "README.md"), "needle\n");
    const first = store.search(projectId, "needle", 10);
    const second = store.search(projectId, "needle", 10);
    const third = store.search(projectId, "needle", 10);

    await expect(third).rejects.toThrow("Limite de pesquisas simultâneas atingido.");
    await expect(Promise.all([first, second])).resolves.toEqual([
      [{ path: "README.md", line: 1, text: "needle" }],
      [{ path: "README.md", line: 1, text: "needle" }]
    ]);
    await expect(store.search(projectId, "needle", 10)).resolves.toHaveLength(1);
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
