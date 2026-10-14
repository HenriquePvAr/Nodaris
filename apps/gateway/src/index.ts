// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { createMcpHandler, McpServer } from "@modelcontextprotocol/server";
import {
  toNodeHandler,
  localhostHostValidation,
  localhostOriginValidation
} from "@modelcontextprotocol/node";
import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { z } from "zod/v4";
import { loadConfig } from "../../../packages/core/src/config.js";
import { rpcRequestSchema } from "../../../packages/core/src/contracts.js";
import { NodarisError, safeError, safeErrorFromCode } from "../../../packages/core/src/errors.js";

function reportStartupFailure(error: unknown): never {
  const safe = safeError(error);
  console.error(
    JSON.stringify({
      componente: "gateway",
      operacao: "startup",
      motivo: safe.reason,
      resultado: "erro"
    })
  );
  process.exit(1);
}

let config: ReturnType<typeof loadConfig>;
try {
  config = loadConfig();
} catch (error) {
  reportStartupFailure(error);
}
const token = Buffer.from(config.token);
const validHost = localhostHostValidation();
const validOrigin = localhostOriginValidation();

async function callAgent(input: unknown): Promise<unknown> {
  const payload = rpcRequestSchema.parse(input);
  const response = await fetch(`http://${config.agentHost}:${config.agentPort}/rpc`, {
    method: "POST",
    headers: { authorization: `Bearer ${config.token}`, "content-type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(8_000)
  });
  if (!response.ok) {
    if (response.status === 401) throw new NodarisError("AGENT_UNAUTHORIZED");
    if (response.status === 400) {
      try {
        const body: unknown = await response.json();
        if (typeof body === "object" && body !== null && "code" in body) {
          const safe = safeErrorFromCode(body.code);
          throw new NodarisError(safe.code);
        }
      } catch (error) {
        if (error instanceof NodarisError) throw error;
      }
    }
    throw new NodarisError("AGENT_UNAVAILABLE");
  }
  const result: unknown = await response.json();
  if (typeof result === "object" && result !== null && "error" in result) {
    const code = "code" in result ? result.code : undefined;
    throw new NodarisError(safeErrorFromCode(code).code);
  }
  return result;
}

function createServerForRequest(): McpServer {
  const server = new McpServer({ name: "nodaris", version: "0.1.0" });
  const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;
  const register = (
    server as unknown as {
      registerTool: (
        name: string,
        config: { description: string; inputSchema: object; annotations: typeof readOnly },
        callback: (args: Record<string, unknown>) => Promise<unknown>
      ) => unknown;
    }
  ).registerTool.bind(server);
  const add = (
    name: string,
    description: string,
    inputSchema: { shape: object },
    operation: (args: Record<string, unknown>) => unknown
  ) => {
    register(
      name,
      { description, inputSchema: inputSchema.shape, annotations: readOnly },
      async (args) => {
        try {
          const result = await operation(args);
          return { content: [{ type: "text", text: JSON.stringify(result) }] };
        } catch (error) {
          const safe = safeError(error);
          console.warn(
            JSON.stringify({
              componente: "gateway",
              operacao: name,
              motivo: safe.reason,
              resultado: "erro"
            })
          );
          return {
            content: [{ type: "text", text: safe.message }],
            isError: true
          };
        }
      }
    );
  };
  add(
    "nodaris_health",
    "Verifica gateway, agente local e quantidade de projetos descobertos.",
    z.object({}),
    () => callAgent({ operation: "health" })
  );
  add(
    "nodaris_machines_list",
    "Lista computadores Nodaris cadastrados e estados de conexão.",
    z.object({}),
    () => callAgent({ operation: "machines.list" })
  );
  add(
    "nodaris_projects_list",
    "Lista projetos nas raízes explicitamente autorizadas.",
    z.object({}),
    () => callAgent({ operation: "projects.list" })
  );
  add(
    "nodaris_project_tree",
    "Lista a árvore limitada de diretórios de um projeto autorizado.",
    z.object({
      projectId: z.string(),
      path: z.string().optional(),
      depth: z.number().int().min(0).max(8).default(4)
    }),
    (args) => callAgent({ operation: "project.tree", ...args })
  );
  add(
    "nodaris_code_search",
    "Pesquisa texto em arquivos de código não sensíveis do projeto.",
    z.object({
      projectId: z.string(),
      query: z.string().min(1).max(200),
      maxResults: z.number().int().min(1).max(100).default(30)
    }),
    (args) => callAgent({ operation: "code.search", ...args })
  );
  add(
    "nodaris_file_read",
    "Lê arquivo textual permitido de projeto autorizado.",
    z.object({ projectId: z.string(), path: z.string() }),
    (args) => callAgent({ operation: "file.read", ...args })
  );
  add(
    "nodaris_git_status",
    "Consulta o estado local de um repositório Git autorizado.",
    z.object({ projectId: z.string() }),
    (args) => callAgent({ operation: "git.status", ...args })
  );
  add(
    "nodaris_git_diff",
    "Consulta diff local com limites e bloqueio de conteúdo potencialmente sensível.",
    z.object({ projectId: z.string() }),
    (args) => callAgent({ operation: "git.diff", ...args })
  );
  add(
    "nodaris_git_log",
    "Consulta commits recentes de um repositório autorizado.",
    z.object({ projectId: z.string(), limit: z.number().int().min(1).max(50).default(10) }),
    (args) => callAgent({ operation: "git.log", ...args })
  );
  return server;
}

const handler = createMcpHandler(createServerForRequest, { responseMode: "json" });
const nodeHandler = toNodeHandler(handler);
const http = createServer((req, res) => {
  if (!validHost(req, res) || !validOrigin(req, res)) return;
  if (req.url !== "/mcp") {
    res.writeHead(404, { "cache-control": "no-store" }).end();
    return;
  }
  const supplied = req.headers.authorization?.startsWith("Bearer ")
    ? Buffer.from(req.headers.authorization.slice(7))
    : Buffer.alloc(0);
  if (supplied.length !== token.length || !timingSafeEqual(supplied, token)) {
    res.writeHead(401, { "cache-control": "no-store" }).end();
    return;
  }
  req.method ??= "GET";
  void nodeHandler(req as never, res).catch((error: unknown) => {
    const safe = safeError(error);
    console.warn(
      JSON.stringify({
        componente: "gateway",
        operacao: "mcp.transport",
        motivo: safe.reason,
        resultado: "erro"
      })
    );
    if (!res.headersSent)
      res
        .writeHead(500, {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store"
        })
        .end(JSON.stringify({ error: "Falha interna." }));
  });
});

http.on("error", (error) => {
  const safe = safeError(error);
  console.error(
    JSON.stringify({
      componente: "gateway",
      operacao: "listen",
      motivo: safe.reason,
      resultado: "erro"
    })
  );
  process.exitCode = 1;
});

http.listen(config.gatewayPort, config.gatewayHost, () =>
  console.info(
    JSON.stringify({
      evento: "gateway_pronto",
      host: config.gatewayHost,
      porta: config.gatewayPort,
      transporte: "Streamable HTTP"
    })
  )
);
process.on("SIGINT", () => {
  void handler.close().finally(() => http.close());
});
process.on("SIGTERM", () => {
  void handler.close().finally(() => http.close());
});
