// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { execFile } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:net";
import { promisify } from "node:util";
import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const exec = promisify(execFile);
const repository = process.cwd();
const token = "a".repeat(64);
const fixtureRoot = path.join(repository, "tests", "fixtures");
let temporaryGitRoot = "";
let agentPort = 0;
let gatewayPort = 0;
let agent: ChildProcess | undefined;
let gateway: ChildProcess | undefined;
let client: Client | undefined;

async function freePort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string")
    throw new Error("Não foi possível reservar uma porta de teste.");
  const port = address.port;
  await new Promise<void>((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve()))
  );
  return port;
}

async function waitFor(
  url: string,
  headers: Record<string, string>,
  process: ChildProcess
): Promise<void> {
  const started = Date.now();
  while (Date.now() - started < 8_000) {
    if (process.exitCode !== null)
      throw new Error("Processo Nodaris terminou antes de abrir a porta.");
    try {
      const response = await fetch(url, {
        method: "POST",
        headers,
        body: JSON.stringify({ operation: "health" })
      });
      if (response.status === 200 || (url.endsWith("/mcp") && response.status !== 401)) return;
    } catch {
      /* serviço ainda inicializando */
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Serviço Nodaris não iniciou: ${url}`);
}

function start(script: string): ChildProcess {
  const tsx = path.join(repository, "node_modules", "tsx", "dist", "cli.mjs");
  return spawn(process.execPath, [tsx, path.join(repository, script)], {
    cwd: repository,
    windowsHide: true,
    env: {
      ...process.env,
      NODARIS_TOKEN: token,
      NODARIS_ALLOWED_ROOTS: `${fixtureRoot};${temporaryGitRoot}`,
      NODARIS_MACHINE_ID: "integration-test",
      AGENT_HOST: "127.0.0.1",
      GATEWAY_HOST: "127.0.0.1",
      AGENT_PORT: String(agentPort),
      GATEWAY_PORT: String(gatewayPort)
    },
    stdio: "ignore"
  });
}

async function stop(process: ChildProcess | undefined): Promise<void> {
  if (!process || process.exitCode !== null) return;
  process.kill("SIGTERM");
  await Promise.race([
    new Promise<void>((resolve) => process.once("exit", () => resolve())),
    new Promise<void>((resolve) => setTimeout(resolve, 2_000))
  ]);
  if (process.exitCode === null) process.kill("SIGKILL");
}

beforeAll(async () => {
  temporaryGitRoot = await mkdtemp(path.join(tmpdir(), "nodaris-process-test-"));
  await exec("git", ["init", temporaryGitRoot]);
  await exec("git", ["-C", temporaryGitRoot, "config", "user.email", "nodaris@example.invalid"]);
  await exec("git", ["-C", temporaryGitRoot, "config", "user.name", "Nodaris Integration"]);
  await writeFile(path.join(temporaryGitRoot, "README.md"), "fixture git\n");
  await exec("git", ["-C", temporaryGitRoot, "add", "README.md"]);
  await exec("git", ["-C", temporaryGitRoot, "commit", "-m", "fixture"]);
  agentPort = await freePort();
  gatewayPort = await freePort();
  agent = start("apps/agent/src/index.ts");
  const authHeaders = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  await waitFor(`http://127.0.0.1:${agentPort}/rpc`, authHeaders, agent);
  gateway = start("apps/gateway/src/index.ts");
  const transport = new StreamableHTTPClientTransport(
    new URL(`http://127.0.0.1:${gatewayPort}/mcp`),
    {
      requestInit: { headers: { authorization: `Bearer ${token}` } }
    }
  );
  client = new Client({ name: "nodaris-integration-test", version: "1.0.0" });
  client.setVersionNegotiation({ mode: "auto" });
  await waitFor(`http://127.0.0.1:${gatewayPort}/mcp`, authHeaders, gateway);
  await client.connect(transport);
}, 20_000);

afterAll(async () => {
  await client?.close().catch(() => undefined);
  await stop(gateway);
  await stop(agent);
  if (temporaryGitRoot) await rm(temporaryGitRoot, { recursive: true, force: true });
});

describe("MCP local entre processos", () => {
  it("anuncia as nove tools Nodaris exclusivamente de leitura", async () => {
    const listed = await client!.listTools();
    expect(listed.tools.map((tool) => tool.name)).toHaveLength(9);
    expect(listed.tools.every((tool) => tool.annotations?.readOnlyHint === true)).toBe(true);
  });

  it("encaminha health, descoberta, árvore, busca e leitura do fixture", async () => {
    const health = await client!.callTool({ name: "nodaris_health", arguments: {} });
    expect((health.content[0] as { text: string }).text).toContain('"status":"ok"');
    const listed = await client!.callTool({ name: "nodaris_projects_list", arguments: {} });
    const projects = JSON.parse((listed.content[0] as { text: string }).text) as Array<{
      id: string;
      name: string;
    }>;
    const sample = projects.find((project) => project.name === "sample-project");
    expect(sample).toBeDefined();
    const file = await client!.callTool({
      name: "nodaris_file_read",
      arguments: { projectId: sample!.id, path: "src/auth.ts" }
    });
    expect(JSON.stringify(file)).toContain("isAuthenticated");
    const search = await client!.callTool({
      name: "nodaris_code_search",
      arguments: { projectId: sample!.id, query: "isAuthenticated" }
    });
    expect(JSON.stringify(search)).toContain("isAuthenticated");
    const tree = await client!.callTool({
      name: "nodaris_project_tree",
      arguments: { projectId: sample!.id, depth: 3 }
    });
    expect(JSON.stringify(tree)).toContain("src/auth.ts");
  });

  it("nega caminhos externos e mantém Git em leitura", async () => {
    const listed = await client!.callTool({ name: "nodaris_projects_list", arguments: {} });
    const projects = JSON.parse((listed.content[0] as { text: string }).text) as Array<{
      id: string;
      path: string;
    }>;
    const gitProject = projects.find((project) => project.path === temporaryGitRoot);
    expect(gitProject).toBeDefined();
    const denied = await client!.callTool({
      name: "nodaris_file_read",
      arguments: { projectId: gitProject!.id, path: "../../outside.txt" }
    });
    expect("isError" in denied && denied.isError).toBe(true);
    const status = await client!.callTool({
      name: "nodaris_git_status",
      arguments: { projectId: gitProject!.id }
    });
    expect(JSON.stringify(status)).toContain("##");
    const log = await client!.callTool({
      name: "nodaris_git_log",
      arguments: { projectId: gitProject!.id, limit: 1 }
    });
    expect(JSON.stringify(log)).toContain("fixture");
    await writeFile(path.join(temporaryGitRoot, "README.md"), "fixture alterado\n");
    const diff = await client!.callTool({
      name: "nodaris_git_diff",
      arguments: { projectId: gitProject!.id }
    });
    expect(JSON.stringify(diff)).toContain("fixture alterado");
  });

  it("recusa token inválido no agente", async () => {
    const response = await fetch(`http://127.0.0.1:${agentPort}/rpc`, {
      method: "POST",
      headers: { authorization: "Bearer inválido", "content-type": "application/json" },
      body: JSON.stringify({ operation: "projects.list" })
    });
    expect(response.status).toBe(401);
    const gatewayResponse = await fetch(`http://127.0.0.1:${gatewayPort}/mcp`, {
      method: "POST",
      headers: { authorization: "Bearer inválido", "content-type": "application/json" },
      body: "{}"
    });
    expect(gatewayResponse.status).toBe(401);

    const discoveryResponse = await fetch(
      `http://127.0.0.1:${gatewayPort}/.well-known/oauth-protected-resource/mcp`
    );
    expect(discoveryResponse.status).toBe(404);
  });

  it("limita chamadas simultâneas e se recupera após o agente voltar", async () => {
    const calls = await Promise.all(
      Array.from({ length: 8 }, () => client!.callTool({ name: "nodaris_health", arguments: {} }))
    );
    expect(calls.every((result) => !("isError" in result && result.isError))).toBe(true);

    await stop(agent);
    agent = undefined;
    const offline = await client!.callTool({ name: "nodaris_health", arguments: {} });
    expect("isError" in offline && offline.isError).toBe(true);

    agent = start("apps/agent/src/index.ts");
    await waitFor(
      `http://127.0.0.1:${agentPort}/rpc`,
      {
        authorization: `Bearer ${token}`,
        "content-type": "application/json"
      },
      agent
    );
    const recovered = await client!.callTool({ name: "nodaris_health", arguments: {} });
    expect((recovered.content[0] as { text: string }).text).toContain('"status":"ok"');
  });
});
