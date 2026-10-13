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

const config = loadConfig();
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
  if (!response.ok)
    throw new Error(
      response.status === 401
        ? "Agente recusou a autenticação."
        : "Agente local indisponível ou requisição recusada."
    );
  const result: unknown = await response.json();
  if (typeof result === "object" && result !== null && "error" in result)
    throw new Error(String(result.error));
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
          return {
            content: [
              { type: "text", text: error instanceof Error ? error.message : "Falha interna." }
            ],
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
  const supplied = req.headers.authorization?.startsWith("Bearer ")
    ? Buffer.from(req.headers.authorization.slice(7))
    : Buffer.alloc(0);
  if (supplied.length !== token.length || !timingSafeEqual(supplied, token)) {
    res.writeHead(401, { "cache-control": "no-store" }).end();
    return;
  }
  if (req.url !== "/mcp") {
    res.writeHead(404).end();
    return;
  }
  req.method ??= "GET";
  void nodeHandler(req as never, res);
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
