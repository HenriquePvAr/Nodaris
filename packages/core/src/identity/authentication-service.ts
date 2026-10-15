// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type {
  AuthenticationDecision,
  DeviceAuthenticationDecision,
  DeviceAuthenticationPolicy,
  DeviceSessionVerifier,
  DeviceStatusReader,
  ReplayGuard,
  SessionRevocationReader,
  TrustedAuthenticationPolicy,
  TrustedClock,
  TokenVerifier
} from "./types.js";
import { authorizeCapability } from "../platform/types.js";

/**
 * Orquestrador deny-by-default. Em produção, TokenVerifier e os leitores devem vir de
 * adaptadores confiáveis; estruturas fornecidas pelo request não entram como resultado verificado.
 */
export class AuthenticationService {
  constructor(
    private readonly verifier: TokenVerifier,
    private readonly sessions: SessionRevocationReader,
    private readonly policy: TrustedAuthenticationPolicy,
    private readonly clock: TrustedClock,
    private readonly replayGuard?: ReplayGuard
  ) {}

  async authenticate(input: {
    readonly credential: string | undefined;
    readonly operationNonce?: string;
  }): Promise<AuthenticationDecision> {
    if (!input.credential) return { outcome: "DENY", reason: "MISSING_CREDENTIAL" };
    const policy = this.policy;
    let now: number;
    try {
      now = this.clock.nowEpochSeconds();
    } catch {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    if (!Number.isSafeInteger(now)) return { outcome: "DENY", reason: "INCONCLUSIVE" };
    if (!isValidTrustedPolicy(policy)) {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    const skew = policy.maximumClockSkewSeconds;
    if (!Number.isSafeInteger(skew) || skew < 0 || skew > 120) {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    if (policy.requiredScopes.some((scope) => !authorizeCapability(scope, [scope]))) {
      return { outcome: "DENY", reason: "INSUFFICIENT_SCOPE" };
    }

    let result;
    try {
      result = await this.verifier.verify(input.credential, policy, now);
    } catch {
      return { outcome: "DENY", reason: "VERIFIER_UNAVAILABLE" };
    }
    if (result.outcome === "REJECTED" || result.outcome === "INCONCLUSIVE")
      return { outcome: "DENY", reason: result.reason };
    if (
      result.outcome !== "VERIFIED" ||
      typeof result.identity?.issuer !== "string" ||
      !result.identity.issuer ||
      typeof result.identity.subject !== "string" ||
      !result.identity.subject ||
      !result.tokenId ||
      !result.sessionId ||
      !Array.isArray(result.scopes) ||
      !Number.isSafeInteger(result.sessionEpoch) ||
      result.sessionEpoch < 0
    ) {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }

    if (result.identity.issuer !== policy.issuer)
      return { outcome: "DENY", reason: "ISSUER_MISMATCH" };
    if (result.audience !== policy.audience)
      return { outcome: "DENY", reason: "AUDIENCE_MISMATCH" };
    if (result.resource !== policy.resource)
      return { outcome: "DENY", reason: "AUDIENCE_MISMATCH" };
    if (
      !Number.isSafeInteger(result.issuedAt) ||
      !Number.isSafeInteger(result.notBefore) ||
      !Number.isSafeInteger(result.expiresAt) ||
      result.expiresAt <= result.issuedAt ||
      result.issuedAt > now + skew ||
      result.notBefore > now + skew
    ) {
      return { outcome: "DENY", reason: "NOT_YET_VALID" };
    }
    if (result.expiresAt <= now - skew) return { outcome: "DENY", reason: "EXPIRED" };
    if (policy.requiredScopes.some((scope) => !result.scopes.includes(scope))) {
      return { outcome: "DENY", reason: "INSUFFICIENT_SCOPE" };
    }

    let revocation;
    try {
      revocation = await this.sessions.read(result.identity, result.sessionId);
    } catch {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    if (
      !revocation ||
      !Number.isSafeInteger(revocation.minimumSessionEpoch) ||
      revocation.minimumSessionEpoch < 0 ||
      typeof revocation.revokedSessionIds?.has !== "function"
    ) {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    if (revocation.status !== "ACTIVE") {
      const reason =
        revocation.status === "REVOKED"
          ? "SESSION_REVOKED"
          : revocation.status === "EXPIRED"
            ? "EXPIRED"
            : revocation.status === "INVALID"
              ? "INVALID_SESSION"
              : "INCONCLUSIVE";
      return { outcome: "DENY", reason };
    }
    if (
      revocation.revokedSessionIds.has(result.sessionId) ||
      result.sessionEpoch < revocation.minimumSessionEpoch
    ) {
      return { outcome: "DENY", reason: "SESSION_REVOKED" };
    }
    if (policy.replayProtection === "REQUIRED" && input.operationNonce === undefined) {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    if (input.operationNonce !== undefined) {
      if (!input.operationNonce || !this.replayGuard)
        return { outcome: "DENY", reason: "INCONCLUSIVE" };
      let consumed;
      try {
        consumed = await this.replayGuard.consume({
          sessionId: result.sessionId,
          resource: policy.resource,
          nonce: input.operationNonce,
          nowEpochSeconds: now
        });
      } catch {
        return { outcome: "DENY", reason: "INCONCLUSIVE" };
      }
      if (consumed === null) return { outcome: "DENY", reason: "INCONCLUSIVE" };
      if (!consumed) return { outcome: "DENY", reason: "REPLAY_DETECTED" };
    }

    return {
      outcome: "AUTHENTICATED",
      context: {
        user: { issuer: result.identity.issuer, subject: result.identity.subject },
        sessionId: result.sessionId,
        resource: policy.resource,
        scopes: [...policy.requiredScopes],
        authenticatedAt: new Date(now * 1000).toISOString()
      }
    };
  }
}

function isValidTrustedPolicy(policy: TrustedAuthenticationPolicy): boolean {
  if (
    !policy ||
    typeof policy.issuer !== "string" ||
    typeof policy.audience !== "string" ||
    typeof policy.resource !== "string" ||
    !Array.isArray(policy.requiredScopes) ||
    !Number.isSafeInteger(policy.maximumClockSkewSeconds) ||
    (policy.replayProtection !== "OPTIONAL" && policy.replayProtection !== "REQUIRED")
  ) {
    return false;
  }
  const isHttpsUrl = (value: string): boolean => {
    try {
      return new URL(value).protocol === "https:";
    } catch {
      return false;
    }
  };
  return (
    isHttpsUrl(policy.issuer) &&
    isHttpsUrl(policy.resource) &&
    policy.audience.trim().length > 0 &&
    policy.requiredScopes.length > 0 &&
    new Set(policy.requiredScopes).size === policy.requiredScopes.length
  );
}

/** Autentica somente a instalação solicitante; não concede acesso ao host-alvo. */
export class DeviceAuthenticationService {
  constructor(
    private readonly verifier: DeviceSessionVerifier,
    private readonly devices: DeviceStatusReader,
    private readonly policy: DeviceAuthenticationPolicy,
    private readonly clock: TrustedClock,
    private readonly replayGuard?: ReplayGuard
  ) {}

  async authenticate(input: {
    readonly credential: string | undefined;
    readonly operationNonce?: string;
  }): Promise<DeviceAuthenticationDecision> {
    if (!input.credential) return { outcome: "DENY", reason: "MISSING_CREDENTIAL" };
    const policy = this.policy;
    let now: number;
    try {
      now = this.clock.nowEpochSeconds();
    } catch {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    if (
      !Number.isSafeInteger(now) ||
      !isValidDevicePolicy(policy) ||
      policy.maximumClockSkewSeconds < 0 ||
      policy.maximumClockSkewSeconds > 120 ||
      !isHttps(policy.resource) ||
      !policy.audience.trim() ||
      policy.requiredScopes.length === 0 ||
      new Set(policy.requiredScopes).size !== policy.requiredScopes.length ||
      policy.requiredScopes.some((scope) => !authorizeCapability(scope, [scope]))
    ) {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }

    let result;
    try {
      result = await this.verifier.verify(input.credential, policy, now);
    } catch {
      return { outcome: "DENY", reason: "VERIFIER_UNAVAILABLE" };
    }
    if (result.outcome === "REJECTED" || result.outcome === "INCONCLUSIVE")
      return { outcome: "DENY", reason: result.reason };
    if (result.outcome !== "VERIFIED") return { outcome: "DENY", reason: "INCONCLUSIVE" };
    const session = result.session;
    if (
      typeof session.id !== "string" ||
      !session.id ||
      typeof session.deviceId !== "string" ||
      !session.deviceId ||
      session.audience !== policy.audience ||
      session.resource !== policy.resource ||
      !Number.isSafeInteger(session.issuedAt) ||
      !Number.isSafeInteger(session.notBefore) ||
      !Number.isSafeInteger(session.expiresAt) ||
      session.expiresAt <= session.issuedAt ||
      session.issuedAt > now + policy.maximumClockSkewSeconds ||
      !Number.isSafeInteger(session.sessionEpoch) ||
      session.sessionEpoch < 0 ||
      typeof session.proofNonce !== "string" ||
      !session.proofNonce ||
      !Array.isArray(session.scopes) ||
      policy.requiredScopes.some((scope) => !session.scopes.includes(scope))
    ) {
      return { outcome: "DENY", reason: "INVALID_TOKEN" };
    }
    if (session.notBefore > now + policy.maximumClockSkewSeconds)
      return { outcome: "DENY", reason: "NOT_YET_VALID" };
    if (session.expiresAt <= now - policy.maximumClockSkewSeconds)
      return { outcome: "DENY", reason: "EXPIRED" };

    let state;
    try {
      state = await this.devices.read(session.deviceId);
    } catch {
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    }
    if (!state) return { outcome: "DENY", reason: "INCONCLUSIVE" };
    if (state.status !== "ENROLLED") return { outcome: "DENY", reason: "DEVICE_UNAVAILABLE" };
    if (!Number.isSafeInteger(state.minimumSessionEpoch) || state.minimumSessionEpoch < 0)
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    if (session.sessionEpoch < state.minimumSessionEpoch)
      return { outcome: "DENY", reason: "SESSION_REVOKED" };

    if (policy.replayProtection === "REQUIRED" && input.operationNonce === undefined)
      return { outcome: "DENY", reason: "INCONCLUSIVE" };
    if (input.operationNonce !== undefined) {
      if (!input.operationNonce || !this.replayGuard)
        return { outcome: "DENY", reason: "INCONCLUSIVE" };
      let consumed;
      try {
        consumed = await this.replayGuard.consume({
          sessionId: session.id,
          resource: policy.resource,
          nonce: input.operationNonce,
          nowEpochSeconds: now
        });
      } catch {
        return { outcome: "DENY", reason: "INCONCLUSIVE" };
      }
      if (consumed === null) return { outcome: "DENY", reason: "INCONCLUSIVE" };
      if (!consumed) return { outcome: "DENY", reason: "REPLAY_DETECTED" };
    }

    return {
      outcome: "DEVICE_AUTHENTICATED",
      deviceId: session.deviceId,
      resource: policy.resource
    };
  }
}

function isHttps(value: string): boolean {
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

function isValidDevicePolicy(policy: DeviceAuthenticationPolicy): boolean {
  return Boolean(
    policy &&
      typeof policy.audience === "string" &&
      typeof policy.resource === "string" &&
      Array.isArray(policy.requiredScopes) &&
      Number.isSafeInteger(policy.maximumClockSkewSeconds) &&
      (policy.replayProtection === "OPTIONAL" || policy.replayProtection === "REQUIRED")
  );
}
