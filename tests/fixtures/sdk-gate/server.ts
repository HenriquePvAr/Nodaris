// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { McpServer, createMcpHandler, requireScopes } from "@modelcontextprotocol/server";
import * as z from "zod/v4";

export const legacyProtocolVersion = "2025-11-25";
export const modernProtocolVersion = "2026-07-28";
export const syntheticResource = new URL("https://mcp.fixture.invalid/nodaris");
export const syntheticIssuer = "https://identity.fixture.invalid/";
export const syntheticScopes = ["resource:read", "files:read"] as const;

export function createSdkGateServer(options: { legacy?: "stateless" | "reject" } = {}) {
  const servedEras: Array<"legacy" | "modern"> = [];
  const handler = createMcpHandler(
    (context) => {
      servedEras.push(context.era);
      const server = new McpServer({ name: "nodaris-sdk-gate-fixture", version: "1.0.0" });
      server.registerTool(
        "fixture_read",
        {
          description: "Retorna um valor sintético de leitura.",
          inputSchema: z.object({}),
          annotations: { readOnlyHint: true, destructiveHint: false }
        },
        async () => ({ content: [{ type: "text", text: "fixture-ok" }] })
      );
      server.registerTool(
        "fixture_oauth_read",
        {
          description: "Leitura sintética que exige scope.",
          inputSchema: z.object({}),
          annotations: { readOnlyHint: true, destructiveHint: false }
        },
        async () =>
          context.authInfo?.scopes.includes("files:read")
            ? { content: [{ type: "text", text: "fixture-authorized" }] }
            : {
                content: [{ type: "text", text: "Autenticação necessária para esta ferramenta." }],
                isError: true,
                _meta: {
                  "mcp/www_authenticate": [
                    'Bearer resource_metadata="https://mcp.fixture.invalid/.well-known/oauth-protected-resource/mcp", error="insufficient_scope", error_description="Scope de leitura necessário"'
                  ]
                }
              }
      );
      server.registerTool(
        "fixture_http_scope_read",
        {
          description: "Leitura sintética com scopeChallenge do SDK.",
          inputSchema: z.object({}),
          annotations: { readOnlyHint: true, destructiveHint: false },
          scopeChallenge: requireScopes("files:read")
        },
        async () => ({ content: [{ type: "text", text: "fixture-authorized" }] })
      );
      return server;
    },
    { legacy: options.legacy ?? "stateless", keepAliveMs: 0 }
  );

  return { handler, servedEras };
}
