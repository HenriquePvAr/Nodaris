// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type {
  DeviceAuthenticationPolicy,
  DeviceAuthorizationState,
  DeviceSessionVerificationResult,
  DeviceSessionVerifier,
  ReplayGuard,
  SessionRevocationState,
  TokenVerificationResult,
  TokenVerifier,
  TrustedAuthenticationPolicy,
  TrustedClock,
  UserIdentity
} from "../../../packages/core/src/identity/types.js";

export const fixtureIdentity: UserIdentity = {
  issuer: "https://issuer.fixture.invalid",
  subject: "fixture-subject"
};

export function verifiedFixture(
  overrides: Partial<Extract<TokenVerificationResult, { outcome: "VERIFIED" }>> = {}
): Extract<TokenVerificationResult, { outcome: "VERIFIED" }> {
  return {
    outcome: "VERIFIED",
    identity: fixtureIdentity,
    declaredClaims: { email: "untrusted-profile@example.invalid" },
    audience: "nodaris-resource",
    resource: "https://nodaris.fixture.invalid",
    scopes: ["project.read", "code.search"],
    issuedAt: 1_800_000_000,
    notBefore: 1_800_000_000,
    expiresAt: 1_800_000_600,
    sessionEpoch: 4,
    tokenId: "fixture-token-id",
    sessionId: "fixture-session-id",
    ...overrides
  };
}

export class FakeTokenVerifier implements TokenVerifier {
  lastRequirements: TrustedAuthenticationPolicy | undefined;
  lastNow: number | undefined;

  constructor(public result: TokenVerificationResult = verifiedFixture()) {}

  async verify(
    _credential: string,
    requirements: TrustedAuthenticationPolicy,
    nowEpochSeconds: number
  ): Promise<TokenVerificationResult> {
    void _credential;
    this.lastRequirements = requirements;
    this.lastNow = nowEpochSeconds;
    return this.result;
  }
}

export class FakeClock implements TrustedClock {
  constructor(public now: number) {}

  nowEpochSeconds(): number {
    return this.now;
  }
}

export class FakeSessionReader {
  state: SessionRevocationState | null = {
    revokedSessionIds: new Set(),
    minimumSessionEpoch: 1,
    status: "ACTIVE"
  };

  async read(): Promise<SessionRevocationState | null> {
    return this.state;
  }
}

export class FakeDeviceReader {
  state: DeviceAuthorizationState | null = {
    status: "ENROLLED",
    minimumSessionEpoch: 1
  };

  async read(): Promise<DeviceAuthorizationState | null> {
    return this.state;
  }
}

export class FakeDeviceSessionVerifier implements DeviceSessionVerifier {
  lastPolicy: DeviceAuthenticationPolicy | undefined;
  lastNow: number | undefined;
  constructor(
    public result: DeviceSessionVerificationResult = {
      outcome: "VERIFIED",
      session: {
        id: "fixture-device-session",
        deviceId: "fixture-device-id",
        audience: "nodaris-device",
        resource: "https://nodaris.fixture.invalid",
        issuedAt: 1_800_000_000,
        notBefore: 1_800_000_000,
        expiresAt: 1_800_000_600,
        scopes: ["project.read"],
        sessionEpoch: 2,
        proofNonce: "fixture-proof-nonce"
      }
    }
  ) {}

  async verify(
    _credential: string,
    _policy: DeviceAuthenticationPolicy,
    _nowEpochSeconds: number
  ): Promise<DeviceSessionVerificationResult> {
    void _credential;
    this.lastPolicy = _policy;
    this.lastNow = _nowEpochSeconds;
    return this.result;
  }
}

/** Simula challenge em memória; confirmação de prova nunca equivale à aprovação do proprietário. */
export class FakeEnrollmentRegistry {
  private readonly challenges = new Map<string, { expiresAt: number; consumed: boolean }>();
  online = true;

  issue(id: string, now: number, lifetimeSeconds: number): void {
    this.challenges.set(id, { expiresAt: now + lifetimeSeconds, consumed: false });
  }

  prove(id: string, now: number, proofMatches: boolean): "PENDING_APPROVAL" | "DENY" {
    if (!this.online) return "DENY";
    const challenge = this.challenges.get(id);
    if (!challenge || challenge.consumed || challenge.expiresAt <= now || !proofMatches)
      return "DENY";
    challenge.consumed = true;
    return "PENDING_APPROVAL";
  }

  assessOwnerApproval(approvedByCaller: boolean): "INCONCLUSIVE" {
    void approvedByCaller;
    return "INCONCLUSIVE";
  }
}

export class FakeReplayGuard implements ReplayGuard {
  private readonly consumed = new Set<string>();
  available = true;

  async consume(input: {
    readonly sessionId: string;
    readonly resource: string;
    readonly nonce: string;
  }): Promise<boolean | null> {
    if (!this.available) return null;
    const key = `${input.sessionId}:${input.resource}:${input.nonce}`;
    if (this.consumed.has(key)) return false;
    this.consumed.add(key);
    return true;
  }
}
