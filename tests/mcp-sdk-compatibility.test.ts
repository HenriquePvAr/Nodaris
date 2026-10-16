// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { afterEach, describe, expect, it } from "vitest";
import {
  buildOAuthProtectedResourceMetadata,
  getOAuthProtectedResourceMetadataUrl,
  OAuthError,
  OAuthErrorCode,
  oauthMetadataResponse,
  requireBearerAuth,
  verifyBearerToken,
  type AuthInfo,
  type OAuthMetadata
} from "@modelcontextprotocol/server";
import {
  Client,
  StreamableHTTPClientTransport,
  type FetchLike
} from "@modelcontextprotocol/client";
import type { McpServer } from "@modelcontextprotocol/server";
import {
  createSdkGateServer,
  legacyProtocolVersion,
  modernProtocolVersion,
  syntheticIssuer,
  syntheticResource,
  syntheticScopes
} from "./fixtures/sdk-gate/server.js";

const fixtureUrl = new URL("https://mcp.fixture.invalid/mcp");
const oauthMetadata: OAuthMetadata = {
  issuer: syntheticIssuer,
  authorization_endpoint: `${syntheticIssuer}authorize`,
  token_endpoint: `${syntheticIssuer}token`,
  response_types_supported: ["code"],
  code_challenge_methods_supported: ["S256"],
  token_endpoint_auth_methods_supported: ["none"]
};
const resourceMetadataOptions = {
  oauthMetadata,
  resourceServerUrl: fixtureUrl,
  scopesSupported: [...syntheticScopes]
};
const resourceMetadataUrl = getOAuthProtectedResourceMetadataUrl(fixtureUrl);

interface CapturedRequest {
  method: string;
  protocolVersion: string | null;
  rpcMethod?: string;
  status?: number;
  wwwAuthenticate?: string | null;
  requestBody?: unknown;
  responseBody?: unknown;
}

const openHandlers: Array<{ close: () => Promise<void> }> = [];
const openClients: Array<{ close: () => Promise<void> }> = [];

afterEach(async () => {
  await Promise.all(openClients.splice(0).map((client) => client.close().catch(() => undefined)));
  await Promise.all(
    openHandlers.splice(0).map((handler) => handler.close().catch(() => undefined))
  );
});

function createFetch(
  handler: ReturnType<typeof createSdkGateServer>["handler"],
  options: {
    authInfo?: AuthInfo;
    intercept?: (request: Request, next: () => Promise<Response>) => Promise<Response>;
    delayDiscoverMs?: number;
  } = {}
): { fetch: FetchLike; requests: CapturedRequest[] } {
  const requests: CapturedRequest[] = [];
  const fetch: FetchLike = async (input, init) => {
    const request = new Request(input, init);
    let body: unknown;
    try {
      body = await request.clone().json();
    } catch {
      body = undefined;
    }
    const rpcMethod =
      typeof body === "object" &&
      body !== null &&
      "method" in body &&
      typeof body.method === "string"
        ? body.method
        : undefined;
    const captured: CapturedRequest = {
      method: request.method,
      protocolVersion:
        request.headers.get("MCP-Protocol-Version") ?? request.headers.get("Mcp-Protocol-Version"),
      ...(rpcMethod ? { rpcMethod } : {}),
      ...(body === undefined ? {} : { requestBody: body })
    };
    requests.push(captured);

    const dispatch = async (): Promise<Response> => {
      if (rpcMethod === "server/discover" && options.delayDiscoverMs !== undefined) {
        await new Promise<void>((resolve, reject) => {
          const timer = setTimeout(resolve, options.delayDiscoverMs);
          request.signal.addEventListener(
            "abort",
            () => {
              clearTimeout(timer);
              reject(request.signal.reason ?? new DOMException("Aborted", "AbortError"));
            },
            { once: true }
          );
        });
      }
      return handler.fetch(request, options.authInfo ? { authInfo: options.authInfo } : undefined);
    };

    const response = options.intercept
      ? await options.intercept(request, dispatch)
      : await dispatch();
    captured.status = response.status;
    captured.wwwAuthenticate = response.headers.get("WWW-Authenticate");
    try {
      captured.responseBody = await response.clone().json();
    } catch {
      captured.responseBody = undefined;
    }
    return response;
  };
  return { fetch, requests };
}

function createClient(fetch: FetchLike, mode?: "legacy" | "auto" | { pin: string }) {
  const transport = new StreamableHTTPClientTransport(fixtureUrl, { fetch });
  const client = new Client({ name: "nodaris-sdk-gate-client", version: "1.0.0" });
  if (mode !== undefined) client.setVersionNegotiation({ mode });
  openClients.push(client);
  return { client, transport };
}

function syntheticVerifier() {
  return {
    async verifyAccessToken(token: string): Promise<AuthInfo> {
      if (token === "fixture-invalid-token") {
        throw new OAuthError(OAuthErrorCode.InvalidToken, "Credencial sintética inválida");
      }
      if (!["fixture-valid-token", "fixture-insufficient-scope"].includes(token)) {
        throw new OAuthError(OAuthErrorCode.InvalidToken, "Credencial sintética inválida");
      }
      return {
        token,
        clientId: "fixture-client",
        scopes: token === "fixture-valid-token" ? [...syntheticScopes] : ["resource:read"],
        expiresAt: Math.floor(Date.now() / 1000) + 300,
        resource: syntheticResource
      };
    }
  };
}

function createProtectedFetch(
  handler: ReturnType<typeof createSdkGateServer>["handler"],
  options: { verifierAvailable?: boolean; requiredScopes?: string[] } = {}
): FetchLike {
  if (options.verifierAvailable === false) {
    return async () => new Response("authorization unavailable", { status: 503 });
  }
  const gate = requireBearerAuth({
    verifier: syntheticVerifier(),
    expectedResource: syntheticResource,
    resourceMetadataUrl,
    ...(options.requiredScopes ? { requiredScopes: options.requiredScopes } : {})
  });
  return async (input, init) => {
    const request = new Request(input, init);
    const metadata = oauthMetadataResponse(request, resourceMetadataOptions);
    if (metadata) return metadata;
    const authInfo = await gate(request);
    if (authInfo instanceof Response) return authInfo;
    return handler.fetch(request, { authInfo });
  };
}

describe("SDK MCP compatibility gate in-memory", () => {
  it("preserva o protocolo legado por padrão e encaminha a chamada pelo handler.fetch", async () => {
    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const memory = createFetch(fixture.handler);
    const { client, transport } = createClient(memory.fetch);

    await client.connect(transport);
    const result = await client.callTool({ name: "fixture_read", arguments: {} });

    expect(transport.protocolVersion).toBe(legacyProtocolVersion);
    expect(fixture.servedEras).toContain("legacy");
    expect(result.isError).not.toBe(true);
    expect(memory.requests.some((request) => request.rpcMethod === "initialize")).toBe(true);
    expect(memory.requests.some((request) => request.rpcMethod === "server/discover")).toBe(false);
    expect(
      memory.requests.find((request) => request.rpcMethod === "initialize")?.requestBody
    ).toMatchObject({
      params: { protocolVersion: legacyProtocolVersion }
    });
  });

  it("mode auto descobre e negocia 2026-07-28 com createMcpHandler", async () => {
    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const memory = createFetch(fixture.handler);
    const { client, transport } = createClient(memory.fetch, "auto");

    await client.connect(transport);
    const result = await client.callTool({ name: "fixture_read", arguments: {} });

    expect(transport.protocolVersion).toBe(modernProtocolVersion);
    expect(fixture.servedEras).toContain("modern");
    expect(result.isError).not.toBe(true);
    expect(memory.requests[0]?.rpcMethod).toBe("server/discover");
    expect(memory.requests.some((request) => request.rpcMethod === "initialize")).toBe(false);
    expect(
      memory.requests.some((request) => request.protocolVersion === modernProtocolVersion)
    ).toBe(true);
  });

  it("pin moderno funciona e pin de revisão não suportada falha sem fallback", async () => {
    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const memory = createFetch(fixture.handler);
    const { client, transport } = createClient(memory.fetch, { pin: modernProtocolVersion });
    await client.connect(transport);
    expect(transport.protocolVersion).toBe(modernProtocolVersion);
    await client.close();

    const unsupportedFixture = createSdkGateServer();
    openHandlers.push(unsupportedFixture.handler);
    const unsupportedMemory = createFetch(unsupportedFixture.handler);
    const unsupported = createClient(unsupportedMemory.fetch, { pin: "2099-01-01" });
    await expect(unsupported.client.connect(unsupported.transport)).rejects.toMatchObject({
      code: -32022,
      name: "ProtocolError"
    });
    expect(unsupportedMemory.requests.some((request) => request.rpcMethod === "initialize")).toBe(
      false
    );
  });

  it("timeout do probe HTTP é erro tipado e não cai silenciosamente para legado", async () => {
    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const memory = createFetch(fixture.handler, { delayDiscoverMs: 100 });
    const { client, transport } = createClient(memory.fetch, "auto");
    client.setVersionNegotiation({ mode: "auto", probe: { timeoutMs: 5, maxRetries: 0 } });

    await expect(client.connect(transport)).rejects.toThrow();
    expect(memory.requests).toHaveLength(1);
    expect(memory.requests[0]?.rpcMethod).toBe("server/discover");
    expect(memory.requests.some((request) => request.rpcMethod === "initialize")).toBe(false);
  });

  it("401 e 403 durante o probe são erros de autorização, não evidência de protocolo legado", async () => {
    for (const status of [401, 403]) {
      const fixture = createSdkGateServer();
      openHandlers.push(fixture.handler);
      const memory = createFetch(fixture.handler, {
        intercept: async () =>
          new Response(
            JSON.stringify({ error: status === 401 ? "invalid_token" : "insufficient_scope" }),
            {
              status,
              headers: {
                "content-type": "application/json",
                "www-authenticate": `Bearer error="${status === 401 ? "invalid_token" : "insufficient_scope"}"`
              }
            }
          )
      });
      const { client, transport } = createClient(memory.fetch, "auto");

      await expect(client.connect(transport)).rejects.toThrow();
      expect(memory.requests).toHaveLength(1);
      expect(memory.requests[0]?.rpcMethod).toBe("server/discover");
      expect(memory.requests[0]?.status).toBe(status);
      expect(memory.requests.some((request) => request.rpcMethod === "initialize")).toBe(false);
    }
  });

  it("servidor dual mantém cliente legado; endpoint modern-only rejeita cliente legado", async () => {
    const dual = createSdkGateServer({ legacy: "stateless" });
    openHandlers.push(dual.handler);
    const legacyMemory = createFetch(dual.handler);
    const legacyClient = createClient(legacyMemory.fetch, "legacy");
    await legacyClient.client.connect(legacyClient.transport);
    expect(legacyClient.transport.protocolVersion).toBe(legacyProtocolVersion);
    expect(dual.servedEras).toContain("legacy");

    const modernOnly = createSdkGateServer({ legacy: "reject" });
    openHandlers.push(modernOnly.handler);
    const rejectedMemory = createFetch(modernOnly.handler);
    const rejectedClient = createClient(rejectedMemory.fetch, "legacy");
    await expect(rejectedClient.client.connect(rejectedClient.transport)).rejects.toThrow();
    expect(rejectedMemory.requests[0]?.rpcMethod).toBe("initialize");
    expect(rejectedMemory.requests[0]?.status).toBeGreaterThanOrEqual(400);
  });

  it("helper de resource server publica PRM, challenge HTTP e falha fechado sem verifier", async () => {
    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const fetch = createProtectedFetch(fixture.handler);
    const prm = await fetch(resourceMetadataUrl);
    const prmBody = (await prm.json()) as { resource?: string; authorization_servers?: string[] };
    expect(prm.status).toBe(200);
    expect(prmBody.resource).toBe(fixtureUrl.href);
    expect(prmBody.authorization_servers).toEqual([syntheticIssuer]);

    const unauthenticated = await fetch(fixtureUrl);
    expect(unauthenticated.status).toBe(401);
    expect(unauthenticated.headers.get("WWW-Authenticate")).toContain(resourceMetadataUrl);

    const unavailableVerifier = createProtectedFetch(fixture.handler, { verifierAvailable: false });
    const unavailable = await unavailableVerifier(fixtureUrl);
    expect(unavailable.status).toBe(503);
  });

  it("rejeita token inválido e responde 403 com challenge de insufficient_scope", async () => {
    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const fetch = createProtectedFetch(fixture.handler, {
      requiredScopes: ["resource:read", "files:read"]
    });
    const invalid = await fetch(fixtureUrl, {
      headers: { authorization: "Bearer fixture-invalid-token" }
    });
    expect(invalid.status).toBe(401);
    expect(invalid.headers.get("WWW-Authenticate")).toContain("invalid_token");

    const insufficient = await fetch(fixtureUrl, {
      headers: { authorization: "Bearer fixture-insufficient-scope" }
    });
    expect(insufficient.status).toBe(403);
    expect(insufficient.headers.get("WWW-Authenticate")).toContain("insufficient_scope");
  });

  it("verifyBearerToken valida formato, resource, expiração e scopes", async () => {
    const options = {
      verifier: syntheticVerifier(),
      expectedResource: syntheticResource,
      requiredScopes: ["files:read"]
    };
    const valid = await verifyBearerToken("Bearer fixture-valid-token", options);
    expect(valid.resource?.href).toBe(syntheticResource.href);
    expect(valid.scopes).toContain("files:read");

    await expect(verifyBearerToken(undefined, options)).rejects.toMatchObject({
      code: OAuthErrorCode.InvalidToken
    });
    await expect(verifyBearerToken("Bearer fixture-invalid-token", options)).rejects.toMatchObject({
      code: OAuthErrorCode.InvalidToken
    });
    await expect(
      verifyBearerToken("Bearer fixture-insufficient-scope", {
        ...options,
        requiredScopes: ["files:write"]
      })
    ).rejects.toMatchObject({ code: OAuthErrorCode.InsufficientScope });

    const wrongResourceVerifier = {
      async verifyAccessToken(token: string): Promise<AuthInfo> {
        return {
          token,
          clientId: "fixture-client",
          scopes: [...syntheticScopes],
          expiresAt: Math.floor(Date.now() / 1000) + 300,
          resource: new URL("https://other.fixture.invalid/")
        };
      }
    };
    await expect(
      verifyBearerToken("Bearer fixture-valid-token", {
        ...options,
        verifier: wrongResourceVerifier
      })
    ).rejects.toMatchObject({ code: OAuthErrorCode.InvalidToken });

    const expiredVerifier = {
      async verifyAccessToken(token: string): Promise<AuthInfo> {
        return {
          token,
          clientId: "fixture-client",
          scopes: [...syntheticScopes],
          expiresAt: Math.floor(Date.now() / 1000) - 1,
          resource: syntheticResource
        };
      }
    };
    await expect(
      verifyBearerToken("Bearer fixture-valid-token", { ...options, verifier: expiredVerifier })
    ).rejects.toMatchObject({ code: OAuthErrorCode.InvalidToken });
  });

  it("distingue scopeChallenge HTTP do SDK de _meta por ferramenta e permite leitura autorizada", async () => {
    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const memory = createFetch(fixture.handler, {
      authInfo: {
        token: "fixture-insufficient-scope",
        clientId: "fixture-client",
        scopes: ["resource:read"],
        expiresAt: Math.floor(Date.now() / 1000) + 300,
        resource: syntheticResource
      }
    });
    const transport = new StreamableHTTPClientTransport(fixtureUrl, {
      fetch: memory.fetch,
      requestInit: { headers: { authorization: "Bearer fixture-insufficient-scope" } },
      onInsufficientScope: "throw"
    });
    const client = new Client({ name: "nodaris-oauth-fixture-client", version: "1.0.0" });
    client.setVersionNegotiation({ mode: "auto" });
    openClients.push(client);
    await client.connect(transport);
    await expect(
      client.callTool({ name: "fixture_http_scope_read", arguments: {} })
    ).rejects.toThrow();
    expect(memory.requests.at(-1)?.status).toBe(403);
    expect(memory.requests.at(-1)?.wwwAuthenticate).toContain("insufficient_scope");
    const denied = await client.callTool({ name: "fixture_oauth_read", arguments: {} });
    expect(denied.isError).toBe(true);
    expect(denied._meta?.["mcp/www_authenticate"]).toBeDefined();

    const authorizedFixture = createSdkGateServer();
    openHandlers.push(authorizedFixture.handler);
    const authorizedMemory = createFetch(authorizedFixture.handler, {
      authInfo: {
        token: "fixture-valid-token",
        clientId: "fixture-client",
        scopes: [...syntheticScopes],
        expiresAt: Math.floor(Date.now() / 1000) + 300,
        resource: syntheticResource
      }
    });
    const authorizedTransport = new StreamableHTTPClientTransport(fixtureUrl, {
      fetch: authorizedMemory.fetch,
      requestInit: { headers: { authorization: "Bearer fixture-valid-token" } }
    });
    const authorizedClient = new Client({
      name: "nodaris-authorized-fixture-client",
      version: "1.0.0"
    });
    authorizedClient.setVersionNegotiation({ mode: "auto" });
    openClients.push(authorizedClient);
    await authorizedClient.connect(authorizedTransport);
    const allowed = await authorizedClient.callTool({ name: "fixture_oauth_read", arguments: {} });
    expect(allowed.isError).not.toBe(true);
  });

  it("documenta que a API pública não tipa nem serializa securitySchemes por ferramenta", async () => {
    type ToolRegistration = Parameters<McpServer["registerTool"]>[1];
    const publicApiHasSecuritySchemes: "securitySchemes" extends keyof ToolRegistration
      ? true
      : false = false;
    expect(publicApiHasSecuritySchemes).toBe(false);

    const fixture = createSdkGateServer();
    openHandlers.push(fixture.handler);
    const memory = createFetch(fixture.handler);
    const { client, transport } = createClient(memory.fetch, "auto");
    await client.connect(transport);
    const listed = await client.listTools();
    const oauthTool = listed.tools.find((tool) => tool.name === "fixture_oauth_read");
    expect(oauthTool?.annotations?.readOnlyHint).toBe(true);
    expect(oauthTool && "securitySchemes" in oauthTool).toBe(false);
  });

  it("rejeita metadata OAuth inválida sem fazer descoberta ou requisição de rede", () => {
    expect(() =>
      buildOAuthProtectedResourceMetadata({
        ...resourceMetadataOptions,
        oauthMetadata: {
          ...oauthMetadata,
          issuer: "http://identity.fixture.invalid/"
        }
      })
    ).toThrow();
    expect(syntheticScopes).toEqual(["resource:read", "files:read"]);
  });
});
