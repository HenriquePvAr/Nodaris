import { timingSafeEqual } from "node:crypto";
import { createServer } from "node:http";
import { loadConfig } from "../../../packages/core/src/config.js";
import { rpcRequestSchema } from "../../../packages/core/src/contracts.js";
import { ProjectStore } from "../../../packages/core/src/filesystem.js";
import { gitDiff, gitLog, gitStatus } from "../../../packages/core/src/git.js";

const config = loadConfig();
const store = await ProjectStore.create(config.roots, config.machineId);
await store.discover();
const expected = Buffer.from(config.token);
const authorized = (header: string | undefined): boolean => {
  if (!header?.startsWith("Bearer ")) return false;
  const actual = Buffer.from(header.slice(7));
  return actual.length === expected.length && timingSafeEqual(actual, expected);
};

const server = createServer(async (req, res) => {
  if (req.method !== "POST" || req.url !== "/rpc") {
    res.writeHead(404).end();
    return;
  }
  if (!authorized(req.headers.authorization)) {
    res.writeHead(401).end(JSON.stringify({ error: "Não autorizado." }));
    return;
  }
  let body = "";
  req.on("data", (chunk: Buffer) => {
    body += chunk.toString("utf8");
    if (body.length > 32_000) req.destroy();
  });
  req.on("end", async () => {
    try {
      const parsed = rpcRequestSchema.parse(JSON.parse(body));
      const result = await execute(parsed);
      res
        .writeHead(200, {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store"
        })
        .end(JSON.stringify(result));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Falha interna.";
      console.warn(JSON.stringify({ evento: "rpc_recusada", mensagem: message.slice(0, 160) }));
      res
        .writeHead(400, {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store"
        })
        .end(JSON.stringify({ error: message }));
    }
  });
});

async function execute(request: ReturnType<typeof rpcRequestSchema.parse>): Promise<unknown> {
  switch (request.operation) {
    case "health":
      return { status: "ok", machineId: config.machineId, projects: store.list().length };
    case "machines.list":
      return [{ id: config.machineId, status: "online", projects: store.list().length }];
    case "projects.list":
      return store.list();
    case "project.tree":
      return await store.tree(request.projectId, request.path ?? "", request.depth);
    case "code.search":
      return await store.search(request.projectId, request.query, request.maxResults);
    case "file.read":
      return { path: request.path, content: await store.readText(request.projectId, request.path) };
    case "git.status":
      return await gitStatus(store.getProject(request.projectId));
    case "git.diff":
      return await gitDiff(store.getProject(request.projectId));
    case "git.log":
      return await gitLog(store.getProject(request.projectId), request.limit);
  }
}

server.listen(config.agentPort, config.agentHost, () =>
  console.info(
    JSON.stringify({
      evento: "agente_pronto",
      host: config.agentHost,
      porta: config.agentPort,
      projetos: store.list().length
    })
  )
);
