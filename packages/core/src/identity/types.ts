// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type { NodarisCapability } from "../platform/types.js";

/** Identidade estável derivada somente de issuer e subject verificados. */
export interface UserIdentity {
  readonly issuer: string;
  readonly subject: string;
}

/** Claims de perfil declaradas; nunca são evidência de autenticação ou chave de identidade. */
export interface DeclaredIdentityClaims {
  readonly name?: string;
  readonly email?: string;
  readonly username?: string;
}

export type SessionStatus = "ACTIVE" | "EXPIRED" | "REVOKED" | "INVALID" | "INCONCLUSIVE";
export type AuthenticationFailure =
  | "MISSING_CREDENTIAL"
  | "INVALID_TOKEN"
  | "ISSUER_MISMATCH"
  | "AUDIENCE_MISMATCH"
  | "NOT_YET_VALID"
  | "EXPIRED"
  | "INSUFFICIENT_SCOPE"
  | "SESSION_REVOKED"
  | "INVALID_SESSION"
  | "DEVICE_UNAVAILABLE"
  | "REPLAY_DETECTED"
  | "VERIFIER_UNAVAILABLE"
  | "INCONCLUSIVE";

export interface UserSession {
  readonly id: string;
  readonly user: UserIdentity;
  readonly issuer: string;
  readonly audience: string;
  readonly scopes: readonly NodarisCapability[];
  readonly issuedAt: string;
  readonly notBefore: string;
  readonly expiresAt: string;
  readonly sessionEpoch: number;
  readonly status: SessionStatus;
  readonly revocationId: string;
}

/** Dados de identidade associados à requisição somente após verificação confiável em runtime. */
export interface AuthenticationContext {
  readonly user: UserIdentity;
  readonly sessionId: string;
  readonly resource: string;
  readonly scopes: readonly NodarisCapability[];
  readonly authenticatedAt: string;
}

/** `VERIFIED` só é confiável quando produzido pelo adaptador verificador confiável do servidor. */
export type TokenVerificationResult =
  | {
      readonly outcome: "VERIFIED";
      readonly identity: UserIdentity;
      readonly declaredClaims: DeclaredIdentityClaims;
      readonly audience: string;
      readonly resource: string;
      readonly scopes: readonly string[];
      readonly issuedAt: number;
      readonly notBefore: number;
      readonly expiresAt: number;
      readonly sessionEpoch: number;
      readonly tokenId: string;
      readonly sessionId: string;
    }
  | { readonly outcome: "REJECTED"; readonly reason: AuthenticationFailure }
  | { readonly outcome: "INCONCLUSIVE"; readonly reason: AuthenticationFailure };

export type DeviceStatus =
  | "UNREGISTERED"
  | "PENDING_APPROVAL"
  | "ENROLLED"
  | "SUSPENDED"
  | "REVOKED";

export interface DeviceIdentity {
  readonly id: string;
  readonly publicKey: string;
  readonly keyAlgorithm: "Ed25519" | "ES256";
  readonly status: DeviceStatus;
  readonly enrolledAt?: string;
  readonly keyVersion: number;
}

export interface DeviceEnrollmentRequest {
  readonly requestId: string;
  readonly publicKey: string;
  readonly keyAlgorithm: DeviceIdentity["keyAlgorithm"];
  readonly requestedScopes: readonly NodarisCapability[];
  readonly requestedAt: string;
}

export interface DeviceEnrollmentChallenge {
  readonly id: string;
  readonly deviceId: string;
  readonly nonce: string;
  readonly issuedAt: string;
  readonly expiresAt: string;
  readonly status: "ISSUED" | "CONSUMED" | "EXPIRED" | "REVOKED";
}

export interface DeviceProofOfPossession {
  readonly challengeId: string;
  readonly signature: string;
  readonly algorithm: DeviceIdentity["keyAlgorithm"];
}

export type DeviceEnrollmentResult =
  | { readonly outcome: "PENDING_APPROVAL"; readonly deviceId: string }
  | { readonly outcome: "ENROLLED"; readonly device: DeviceIdentity }
  | { readonly outcome: "DENIED"; readonly reason: AuthenticationFailure }
  | { readonly outcome: "INCONCLUSIVE"; readonly reason: AuthenticationFailure };

export interface DeviceSession {
  readonly id: string;
  readonly deviceId: string;
  readonly audience: string;
  readonly resource: string;
  readonly issuedAt: number;
  readonly notBefore: number;
  readonly expiresAt: number;
  readonly scopes: readonly NodarisCapability[];
  readonly sessionEpoch: number;
  readonly proofNonce: string;
}

export interface DeviceRevocation {
  readonly deviceId: string;
  readonly revokedAt: string;
  readonly revocationId: string;
  readonly reason: "OWNER_REQUEST" | "SECURITY_POLICY";
}

export interface SessionRevocationState {
  readonly revokedSessionIds: ReadonlySet<string>;
  readonly minimumSessionEpoch: number;
  readonly status: SessionStatus;
}

/** Política originada pela composição confiável do servidor, nunca pela requisição MCP. */
export interface TrustedAuthenticationPolicy {
  readonly issuer: string;
  readonly audience: string;
  readonly resource: string;
  readonly requiredScopes: readonly NodarisCapability[];
  readonly maximumClockSkewSeconds: number;
  readonly replayProtection: "OPTIONAL" | "REQUIRED";
}

export interface TrustedClock {
  nowEpochSeconds(): number;
}

export type AuthenticationRequirements = TrustedAuthenticationPolicy;

/** Porta para uma implementação futura baseada em verificador OIDC/OAuth auditado. */
export interface TokenVerifier {
  verify(
    credential: string,
    requirements: TrustedAuthenticationPolicy,
    nowEpochSeconds: number
  ): Promise<TokenVerificationResult>;
}

export interface SessionRevocationReader {
  read(user: UserIdentity, sessionId: string): Promise<SessionRevocationState | null>;
}

export interface DeviceStatusReader {
  read(deviceId: string): Promise<DeviceAuthorizationState | null>;
}

export interface ReplayGuard {
  /** Deve ser atômico; `null` significa que a verificação não pôde ser confirmada. */
  consume(input: {
    readonly sessionId: string;
    readonly resource: string;
    readonly nonce: string;
    readonly nowEpochSeconds: number;
  }): Promise<boolean | null>;
}

export interface DeviceAuthorizationState {
  readonly status: DeviceStatus;
  readonly minimumSessionEpoch: number;
}

export interface DeviceAuthenticationPolicy {
  readonly audience: string;
  readonly resource: string;
  readonly requiredScopes: readonly NodarisCapability[];
  readonly maximumClockSkewSeconds: number;
  readonly replayProtection: "OPTIONAL" | "REQUIRED";
}

export type DeviceSessionVerificationResult =
  | { readonly outcome: "VERIFIED"; readonly session: DeviceSession }
  | { readonly outcome: "REJECTED"; readonly reason: AuthenticationFailure }
  | { readonly outcome: "INCONCLUSIVE"; readonly reason: AuthenticationFailure };

export interface DeviceSessionVerifier {
  verify(
    credential: string,
    policy: DeviceAuthenticationPolicy,
    nowEpochSeconds: number
  ): Promise<DeviceSessionVerificationResult>;
}

export type DeviceAuthenticationDecision =
  | {
      readonly outcome: "DEVICE_AUTHENTICATED";
      readonly deviceId: string;
      readonly resource: string;
    }
  | { readonly outcome: "DENY"; readonly reason: AuthenticationFailure };

/** Referência ao host de destino; não representa grant nem prova de propriedade do usuário. */
export interface WorkspaceTarget {
  readonly deviceId: string;
  readonly projectId: string;
}

export type WorkspaceAuthorizationStatus = "NOT_IMPLEMENTED";
export const WORKSPACE_AUTHORIZATION_STATUS: WorkspaceAuthorizationStatus = "NOT_IMPLEMENTED";

export interface AuthenticatedIdentityResolver {
  resolve(issuer: string, subject: string): Promise<UserIdentity | null>;
}

/** Interface conceitual; aprovação local confiável não existe nesta fase. */
export interface DeviceEnrollmentAuthority {
  issueChallenge(
    user: UserIdentity,
    request: DeviceEnrollmentRequest,
    now: Date
  ): Promise<DeviceEnrollmentChallenge>;
  completeProof(
    challenge: DeviceEnrollmentChallenge,
    proof: DeviceProofOfPossession,
    now: Date
  ): Promise<DeviceEnrollmentResult>;
  revoke(revocation: DeviceRevocation): Promise<DeviceStatus>;
}

/** AUTHENTICATED confirma autenticação e não implica autorização de workspace. */
export type AuthenticationDecision =
  | { readonly outcome: "AUTHENTICATED"; readonly context: AuthenticationContext }
  | { readonly outcome: "DENY"; readonly reason: AuthenticationFailure };

/** OAuth/OIDC adapter contract; no cryptographic implementation is provided here. */
export interface OidcProviderMetadata {
  readonly issuer: string;
  readonly authorizationEndpoint: string;
  readonly tokenEndpoint: string;
  readonly jwksUri: string;
  readonly protectedResourceMetadataUri: string;
  readonly codeChallengeMethodsSupported: readonly ["S256", ...string[]];
  readonly clientIdentification: "CIMD" | "DCR" | "PRE_REGISTERED";
  readonly tokenEndpointAuthMethods: readonly string[];
}
