// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

/** Fixture pura do spike. Não faz rede nem valida tokens reais. */
export interface ProtectedResourceMetadataFixture {
  resource: string;
  authorization_servers: readonly string[];
  scopes_supported: readonly string[];
}

export interface AuthorizationServerMetadataFixture {
  issuer: string;
  authorization_endpoint: string;
  token_endpoint: string;
  code_challenge_methods_supported: readonly string[];
  token_endpoint_auth_methods_supported: readonly string[];
  authorization_response_iss_parameter_supported: boolean;
  client_id_metadata_document_supported?: boolean;
  registration_endpoint?: string;
}

export interface OAuthExchangeFixture {
  authorizeResource: string;
  tokenResource: string;
  audience: string | string[];
  expiresAt: number;
  scopes: readonly string[];
  issuer: string;
  subject: string;
}

export type FixtureAssessment =
  | { status: "PASS" }
  | { status: "DENY"; reason: "INVALID_METADATA" | "INVALID_FLOW" };

export const fixtureResource = "https://mcp.fixture.invalid/nodaris";
export const fixtureIssuer = "https://identity.fixture.invalid/";
export const requiredFixtureScopes = ["projects:read", "files:read", "git:read"] as const;

export const validProtectedResourceMetadata: ProtectedResourceMetadataFixture = {
  resource: fixtureResource,
  authorization_servers: [fixtureIssuer],
  scopes_supported: [...requiredFixtureScopes]
};

export const validAuthorizationServerMetadata: AuthorizationServerMetadataFixture = {
  issuer: fixtureIssuer,
  authorization_endpoint: `${fixtureIssuer}authorize`,
  token_endpoint: `${fixtureIssuer}token`,
  code_challenge_methods_supported: ["S256"],
  token_endpoint_auth_methods_supported: ["none", "private_key_jwt"],
  authorization_response_iss_parameter_supported: true,
  client_id_metadata_document_supported: true
};

function isCanonicalHttps(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      url.username === "" &&
      url.password === "" &&
      url.search === "" &&
      url.hash === "" &&
      url.href === value
    );
  } catch {
    return false;
  }
}

export function assessMetadata(
  prm: ProtectedResourceMetadataFixture,
  asMetadata: AuthorizationServerMetadataFixture
): FixtureAssessment {
  if (
    !isCanonicalHttps(prm.resource) ||
    prm.authorization_servers.length !== 1 ||
    prm.authorization_servers[0] !== asMetadata.issuer ||
    !isCanonicalHttps(asMetadata.issuer) ||
    !isCanonicalHttps(asMetadata.authorization_endpoint) ||
    !isCanonicalHttps(asMetadata.token_endpoint) ||
    !asMetadata.code_challenge_methods_supported.includes("S256") ||
    asMetadata.token_endpoint_auth_methods_supported.length === 0 ||
    new Set(prm.scopes_supported).size !== prm.scopes_supported.length ||
    (asMetadata.registration_endpoint !== undefined &&
      !isCanonicalHttps(asMetadata.registration_endpoint))
  ) {
    return { status: "DENY", reason: "INVALID_METADATA" };
  }
  return { status: "PASS" };
}

export function assessAuthorizationFlow(
  exchange: OAuthExchangeFixture,
  expected: { issuer: string; resource: string; requiredScopes: readonly string[]; now: number }
): FixtureAssessment {
  const audience = Array.isArray(exchange.audience) ? exchange.audience : [exchange.audience];
  if (
    exchange.issuer !== expected.issuer ||
    exchange.authorizeResource !== expected.resource ||
    exchange.tokenResource !== expected.resource ||
    !audience.includes(expected.resource) ||
    !Number.isFinite(exchange.expiresAt) ||
    exchange.expiresAt <= expected.now ||
    exchange.subject.length === 0 ||
    !expected.requiredScopes.every((scope) => exchange.scopes.includes(scope))
  ) {
    return { status: "DENY", reason: "INVALID_FLOW" };
  }
  return { status: "PASS" };
}

export function isAuthorizationResponseIssuerValid(
  advertised: boolean,
  responseIssuer: string | undefined,
  expectedIssuer: string
): boolean {
  return advertised ? responseIssuer === expectedIssuer : true;
}

export function assessUnauthorizedChallenge(status: number, header: string): FixtureAssessment {
  const match =
    /^Bearer resource_metadata="(https:\/\/[^\s"]+\.well-known\/oauth-protected-resource(?:\/[^\s"]*)?)"(?:, scope="([A-Za-z0-9:._ -]+)")?$/.exec(
      header
    );
  if (status !== 401 || !match || !isCanonicalHttps(match[1] ?? "")) {
    return { status: "DENY", reason: "INVALID_METADATA" };
  }
  return { status: "PASS" };
}

export function isAllowedRedirect(
  candidate: string,
  registeredRedirects: readonly string[]
): boolean {
  if (!isCanonicalHttps(candidate)) return false;
  return registeredRedirects.includes(candidate);
}

export const readonlyToolFixture = [
  "nodaris_health",
  "nodaris_machines_list",
  "nodaris_projects_list",
  "nodaris_project_tree",
  "nodaris_code_search",
  "nodaris_file_read",
  "nodaris_git_status",
  "nodaris_git_diff",
  "nodaris_git_log"
] as const;
