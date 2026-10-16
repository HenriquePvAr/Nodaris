// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { readFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  assessAuthorizationFlow,
  assessMetadata,
  assessUnauthorizedChallenge,
  fixtureIssuer,
  fixtureResource,
  isAuthorizationResponseIssuerValid,
  isAllowedRedirect,
  readonlyToolFixture,
  requiredFixtureScopes,
  validAuthorizationServerMetadata,
  validProtectedResourceMetadata
} from "./fixtures/oauth-mcp/compatibility-harness.js";

const validExchange = {
  authorizeResource: fixtureResource,
  tokenResource: fixtureResource,
  audience: fixtureResource,
  expiresAt: 1_900_000_000,
  scopes: [...requiredFixtureScopes],
  issuer: fixtureIssuer,
  subject: "synthetic-subject"
};

describe("fixtures locais de compatibilidade OAuth/MCP", () => {
  it("aceita PRM e metadata AS sintéticas coerentes com PKCE S256", () => {
    expect(
      assessMetadata(validProtectedResourceMetadata, validAuthorizationServerMetadata)
    ).toEqual({
      status: "PASS"
    });
  });

  it.each([
    [
      "resource sem HTTPS",
      { ...validProtectedResourceMetadata, resource: "http://mcp.fixture.invalid" }
    ],
    [
      "issuer divergente",
      {
        ...validProtectedResourceMetadata,
        authorization_servers: ["https://other.fixture.invalid"]
      }
    ],
    [
      "mais de um authorization server ambíguo",
      {
        ...validProtectedResourceMetadata,
        authorization_servers: [fixtureIssuer, "https://other.fixture.invalid"]
      }
    ],
    [
      "escopos duplicados",
      { ...validProtectedResourceMetadata, scopes_supported: ["files:read", "files:read"] }
    ]
  ] as const)("nega PRM inválido: %s", (_name, prm) => {
    expect(assessMetadata(prm, validAuthorizationServerMetadata).status).toBe("DENY");
  });

  it.each([
    [
      "issuer incoerente",
      { ...validAuthorizationServerMetadata, issuer: "https://other.fixture.invalid" }
    ],
    [
      "PKCE S256 ausente",
      { ...validAuthorizationServerMetadata, code_challenge_methods_supported: ["plain"] }
    ],
    [
      "endpoint sem HTTPS",
      {
        ...validAuthorizationServerMetadata,
        token_endpoint: "http://identity.fixture.invalid/token"
      }
    ],
    [
      "registro em URL insegura",
      {
        ...validAuthorizationServerMetadata,
        registration_endpoint: "http://identity.fixture.invalid/register"
      }
    ]
  ] as const)("nega metadata AS inválida: %s", (_name, asMetadata) => {
    expect(assessMetadata(validProtectedResourceMetadata, asMetadata).status).toBe("DENY");
  });

  it("reconhece CIMD, DCR e cliente pré-registrado como opções distintas de registro", () => {
    const cimd = {
      ...validAuthorizationServerMetadata,
      client_id_metadata_document_supported: true
    };
    const dcr = {
      ...validAuthorizationServerMetadata,
      registration_endpoint: `${fixtureIssuer}register`
    };
    const preRegistered = {
      ...validAuthorizationServerMetadata,
      client_id_metadata_document_supported: false
    };
    expect(assessMetadata(validProtectedResourceMetadata, cimd).status).toBe("PASS");
    expect(assessMetadata(validProtectedResourceMetadata, dcr).status).toBe("PASS");
    expect(assessMetadata(validProtectedResourceMetadata, preRegistered).status).toBe("PASS");
  });

  it("aceita fluxo simulado quando resource é propagado e audience, issuer, expiração e scopes batem", () => {
    expect(
      assessAuthorizationFlow(validExchange, {
        issuer: fixtureIssuer,
        resource: fixtureResource,
        requiredScopes: requiredFixtureScopes,
        now: 1_800_000_000
      })
    ).toEqual({ status: "PASS" });
  });

  it("exige o issuer exato nas respostas OAuth quando RFC 9207 é anunciado", () => {
    expect(isAuthorizationResponseIssuerValid(true, fixtureIssuer, fixtureIssuer)).toBe(true);
    expect(
      isAuthorizationResponseIssuerValid(true, "https://other.fixture.invalid/", fixtureIssuer)
    ).toBe(false);
    expect(isAuthorizationResponseIssuerValid(true, undefined, fixtureIssuer)).toBe(false);
  });

  it.each([
    ["resource divergente no authorize", { authorizeResource: "https://other.fixture.invalid" }],
    ["resource divergente no token", { tokenResource: "https://other.fixture.invalid" }],
    ["audience incorreta", { audience: "https://other.fixture.invalid" }],
    ["issuer incorreto", { issuer: "https://other.fixture.invalid" }],
    ["token expirado", { expiresAt: 1_799_999_999 }],
    ["scope insuficiente", { scopes: ["files:read"] }]
  ] as const)("nega fluxo inválido: %s", (_name, changes) => {
    const exchange = { ...validExchange, ...changes };
    expect(
      assessAuthorizationFlow(exchange, {
        issuer: fixtureIssuer,
        resource: fixtureResource,
        requiredScopes: requiredFixtureScopes,
        now: 1_800_000_000
      }).status
    ).toBe("DENY");
  });

  it("aceita challenge 401 com metadados HTTPS e nega status/header ambíguos", () => {
    const header =
      'Bearer resource_metadata="https://mcp.fixture.invalid/.well-known/oauth-protected-resource", scope="files:read"';
    expect(assessUnauthorizedChallenge(401, header).status).toBe("PASS");
    expect(assessUnauthorizedChallenge(200, header).status).toBe("DENY");
    expect(
      assessUnauthorizedChallenge(401, `${header}, resource_metadata="https://attacker.invalid/x"`)
        .status
    ).toBe("DENY");
    expect(
      assessUnauthorizedChallenge(
        401,
        'Bearer resource_metadata="https://mcp.fixture.invalid/.well-known/oauth-protected-resource/mcp"'
      ).status
    ).toBe("PASS");
  });

  it("só aceita redirect HTTPS exato previamente registrado", () => {
    const allowed = "https://chatgpt.com/connector_platform_oauth_redirect";
    expect(isAllowedRedirect(allowed, [allowed])).toBe(true);
    expect(
      isAllowedRedirect("http://chatgpt.com/connector_platform_oauth_redirect", [allowed])
    ).toBe(false);
    expect(isAllowedRedirect("https://attacker.invalid/callback", [allowed])).toBe(false);
    expect(isAllowedRedirect("https://user@chatgpt.com/callback", [allowed])).toBe(false);
  });

  it("confere que o gateway expõe somente as nove ferramentas MCP de leitura", async () => {
    const gateway = await readFile(path.join(process.cwd(), "apps/gateway/src/index.ts"), "utf8");
    const exposedTools = Array.from(
      gateway.matchAll(/^\s+"(nodaris_[a-z_]+)",$/gm),
      (match) => match[1]
    );
    expect(readonlyToolFixture).toHaveLength(9);
    expect(exposedTools).toEqual(readonlyToolFixture);
    expect(readonlyToolFixture).not.toContain("nodaris_file_write" as never);
    expect(readonlyToolFixture).not.toContain("nodaris_shell" as never);
    expect(readonlyToolFixture).not.toContain("nodaris_git_commit" as never);
  });

  it("não expõe segredos em fixtures/saídas nem importa o harness em entrypoints operacionais", async () => {
    const entrypoints = ["apps/agent/src/index.ts", "apps/gateway/src/index.ts"];
    const [source, harness] = await Promise.all([
      Promise.all(entrypoints.map((file) => readFile(path.join(process.cwd(), file), "utf8"))),
      readFile(
        path.join(process.cwd(), "tests/fixtures/oauth-mcp/compatibility-harness.ts"),
        "utf8"
      )
    ]);
    expect(source.join("\n")).not.toMatch(/oauth-mcp|compatibility-harness/);
    expect(harness).not.toMatch(/console\.(?:log|warn|error)/);
    expect(
      JSON.stringify({ prm: validProtectedResourceMetadata, as: validAuthorizationServerMetadata })
    ).not.toMatch(/fixture-secret-value|Bearer\s+[A-Za-z0-9._-]{12,}/i);
    const output = assessAuthorizationFlow(
      { ...validExchange, subject: "fixture-secret-value" },
      {
        issuer: fixtureIssuer,
        resource: fixtureResource,
        requiredScopes: requiredFixtureScopes,
        now: 1_800_000_000
      }
    );
    expect(JSON.stringify(output)).not.toContain("fixture-secret-value");
  });
});
