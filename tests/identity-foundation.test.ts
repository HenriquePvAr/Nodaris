// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { readFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  AuthenticationService,
  DeviceAuthenticationService
} from "../packages/core/src/identity/authentication-service.js";
import {
  FakeClock,
  FakeDeviceReader,
  FakeDeviceSessionVerifier,
  FakeEnrollmentRegistry,
  FakeReplayGuard,
  FakeSessionReader,
  FakeTokenVerifier,
  fixtureIdentity,
  verifiedFixture
} from "./fixtures/identity/fakes.js";
import type {
  DeviceAuthenticationPolicy,
  TokenVerificationResult,
  TrustedAuthenticationPolicy
} from "../packages/core/src/identity/types.js";
import { WORKSPACE_AUTHORIZATION_STATUS } from "../packages/core/src/identity/types.js";

const now = 1_800_000_100;
const userPolicy: TrustedAuthenticationPolicy = {
  issuer: "https://issuer.fixture.invalid",
  audience: "nodaris-resource",
  resource: "https://nodaris.fixture.invalid",
  requiredScopes: ["project.read"],
  maximumClockSkewSeconds: 30,
  replayProtection: "OPTIONAL"
};
const devicePolicy: DeviceAuthenticationPolicy = {
  audience: "nodaris-device",
  resource: userPolicy.resource,
  requiredScopes: ["project.read"],
  maximumClockSkewSeconds: 30,
  replayProtection: "OPTIONAL"
};

function setup(result: TokenVerificationResult = verifiedFixture(), policy = userPolicy) {
  const verifier = new FakeTokenVerifier(result);
  const sessions = new FakeSessionReader();
  const clock = new FakeClock(now);
  const service = new AuthenticationService(verifier, sessions, policy, clock);
  return { service, verifier, sessions, clock };
}

describe("identidade individual e fronteira confiável", () => {
  it("não compõe os contratos nem os fakes novos nos entrypoints operacionais", async () => {
    const files = ["apps/agent/src/index.ts", "apps/gateway/src/index.ts"];
    const content = (
      await Promise.all(files.map((file) => readFile(path.join(process.cwd(), file), "utf8")))
    ).join("\n");
    expect(content).not.toMatch(/identity\/(?:authentication-service|index)|fixtures\/identity/);
  });

  it("autentica usuário sem exigir que seja proprietário ou usuário do dispositivo-alvo", async () => {
    const { service } = setup();
    const result = await service.authenticate({ credential: "fixture-only" });
    expect(result).toMatchObject({
      outcome: "AUTHENTICATED",
      context: { user: fixtureIdentity, resource: userPolicy.resource }
    });

    const target = { deviceId: "maria-host-device", projectId: "fixture-project" };
    const workspaceAuthorization = WORKSPACE_AUTHORIZATION_STATUS;
    expect(target.deviceId).not.toBe(fixtureIdentity.subject);
    expect(workspaceAuthorization).toBe("NOT_IMPLEMENTED");
    expect(result.outcome).not.toBe("ALLOW");
  });

  it("mantém usuário, instalação solicitante e computador-alvo como identidades diferentes", () => {
    const user = fixtureIdentity;
    const device = {
      id: "requesting-installation",
      publicKey: "fixture-public-key",
      keyAlgorithm: "Ed25519" as const,
      status: "ENROLLED" as const,
      keyVersion: 1
    };
    const target = { deviceId: "target-host", projectId: "fixture-project" };
    expect("publicKey" in user).toBe(false);
    expect("subject" in device).toBe(false);
    expect(device.id).not.toBe(target.deviceId);
    expect("owner" in device).toBe(false);
  });

  it("usa somente política e relógio confiáveis fornecidos na composição", async () => {
    const { service, verifier, clock } = setup();
    const untrustedRequest = {
      credential: "fixture-only",
      issuer: "https://attacker.invalid",
      audience: "attacker-resource",
      resource: "https://attacker.invalid",
      requiredScopes: ["workspace.write.approved"],
      nowEpochSeconds: 1,
      authenticated: true
    } as unknown as Parameters<typeof service.authenticate>[0];
    const result = await service.authenticate(untrustedRequest);
    expect(result.outcome).toBe("AUTHENTICATED");
    expect(verifier.lastRequirements).toEqual(userPolicy);
    expect(verifier.lastNow).toBe(now);
    expect(clock.nowEpochSeconds()).toBe(now);
  });

  it.each([
    [
      "issuer incorreto",
      { identity: { issuer: "https://attacker.invalid", subject: "s" } },
      "ISSUER_MISMATCH"
    ],
    ["audience incorreta", { audience: "other-resource" }, "AUDIENCE_MISMATCH"],
    ["resource incorreto", { resource: "https://other.invalid" }, "AUDIENCE_MISMATCH"],
    ["token expirado", { expiresAt: now - 31 }, "EXPIRED"],
    ["token ainda não válido", { notBefore: now + 31 }, "NOT_YET_VALID"],
    [
      "subject desconhecido",
      { identity: { issuer: userPolicy.issuer, subject: "" } },
      "INCONCLUSIVE"
    ]
  ] as const)("nega %s", async (_case, overrides, reason) => {
    const { service } = setup(verifiedFixture(overrides));
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason
    });
  });

  it("nega configuração vazia ou ambígua", async () => {
    const empty = setup(verifiedFixture(), {
      ...userPolicy,
      issuer: "",
      requiredScopes: []
    } as unknown as TrustedAuthenticationPolicy);
    await expect(empty.service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
    const ambiguous = setup(verifiedFixture(), {
      ...userPolicy,
      requiredScopes: ["project.read", "project.read"]
    });
    await expect(ambiguous.service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
  });

  it("nega credencial ausente, escopo insuficiente e resultado não confirmado", async () => {
    const { service, verifier } = setup();
    await expect(service.authenticate({ credential: undefined })).resolves.toEqual({
      outcome: "DENY",
      reason: "MISSING_CREDENTIAL"
    });
    verifier.result = verifiedFixture({ scopes: ["git.read"] });
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INSUFFICIENT_SCOPE"
    });
    verifier.result = { outcome: "INCONCLUSIVE", reason: "INCONCLUSIVE" };
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
    verifier.result = { outcome: "REJECTED", reason: "INVALID_TOKEN" };
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INVALID_TOKEN"
    });
  });

  it("nega falha do verificador, sessão revogada/antiga e estado ausente", async () => {
    const { service, verifier, sessions } = setup();
    verifier.verify = async () => {
      throw new Error("private-token-sentinel");
    };
    const error = await service.authenticate({ credential: "fixture-only" });
    expect(error).toEqual({ outcome: "DENY", reason: "VERIFIER_UNAVAILABLE" });
    expect(JSON.stringify(error)).not.toContain("private-token-sentinel");

    verifier.verify = async () => verifiedFixture();
    sessions.state = {
      revokedSessionIds: new Set(["fixture-session-id"]),
      minimumSessionEpoch: 1,
      status: "ACTIVE"
    };
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "SESSION_REVOKED"
    });
    sessions.state = {
      revokedSessionIds: new Set(),
      minimumSessionEpoch: 5,
      status: "ACTIVE"
    };
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "SESSION_REVOKED"
    });
    sessions.state = null;
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
    sessions.state = {
      revokedSessionIds: new Set(),
      minimumSessionEpoch: Number.NaN,
      status: "ACTIVE"
    };
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
  });

  it("nega sessão expirada/inválida, falhas de relógio e claims fabricadas", async () => {
    const { service, verifier, sessions, clock } = setup();
    verifier.verify = async () => verifiedFixture();
    for (const [status, reason] of [
      ["EXPIRED", "EXPIRED"],
      ["INVALID", "INVALID_SESSION"],
      ["REVOKED", "SESSION_REVOKED"],
      ["INCONCLUSIVE", "INCONCLUSIVE"]
    ] as const) {
      sessions.state = { revokedSessionIds: new Set(), minimumSessionEpoch: 1, status };
      await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
        outcome: "DENY",
        reason
      });
    }
    sessions.state = {
      revokedSessionIds: new Set(),
      minimumSessionEpoch: 1,
      status: "ACTIVE"
    };
    clock.now = Number.NaN;
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
    const fabricated = { authenticated: true, signatureValid: true, userId: "fixture-user" };
    const fakeResult = setup(fabricated as unknown as TokenVerificationResult);
    await expect(fakeResult.service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
  });

  it("consome nonce exigido uma vez e nega replay ou guarda indisponível", async () => {
    const verifier = new FakeTokenVerifier(verifiedFixture());
    const sessions = new FakeSessionReader();
    const replay = new FakeReplayGuard();
    const service = new AuthenticationService(
      verifier,
      sessions,
      userPolicy,
      new FakeClock(now),
      replay
    );
    const request = { credential: "fixture-only", operationNonce: "fixture-operation-nonce" };
    await expect(service.authenticate(request)).resolves.toMatchObject({
      outcome: "AUTHENTICATED"
    });
    await expect(service.authenticate(request)).resolves.toEqual({
      outcome: "DENY",
      reason: "REPLAY_DETECTED"
    });
    replay.available = false;
    await expect(
      service.authenticate({ ...request, operationNonce: "another-nonce" })
    ).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
  });

  it("nega quando a política exige replay protection e a requisição não traz nonce", async () => {
    const requiredPolicy = { ...userPolicy, replayProtection: "REQUIRED" as const };
    const { service } = setup(verifiedFixture(), requiredPolicy);
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
  });

  it("não transforma autenticação em capacidade de escrita ou de acesso a workspace", async () => {
    const { service } = setup();
    const result = await service.authenticate({ credential: "fixture-only" });
    expect(result.outcome).toBe("AUTHENTICATED");
    if (result.outcome === "AUTHENTICATED") {
      expect(result.context.scopes).not.toContain("workspace.write.approved");
      expect(result.context.scopes).not.toContain("test.run.approved");
    }
    expect(WORKSPACE_AUTHORIZATION_STATUS).toBe("NOT_IMPLEMENTED");
  });
});

describe("identidade e autenticação independente do dispositivo", () => {
  it("não confunde claims de usuário com uma chave de dispositivo", () => {
    expect("publicKey" in fixtureIdentity).toBe(false);
    const device = {
      id: "requesting-installation",
      publicKey: "fixture-public-key",
      keyAlgorithm: "Ed25519" as const,
      status: "ENROLLED" as const,
      keyVersion: 1
    };
    expect("subject" in device).toBe(false);
    expect("owner" in device).toBe(false);
  });

  it("não exige enrollment do host-alvo para autenticar uma pessoa", async () => {
    const { service } = setup();
    await expect(service.authenticate({ credential: "fixture-only" })).resolves.toMatchObject({
      outcome: "AUTHENTICATED",
      context: { user: fixtureIdentity }
    });
    const target = { deviceId: "maria-host", projectId: "fixture-project" };
    expect(target.deviceId).not.toBe("fixture-device-id");
    expect(WORKSPACE_AUTHORIZATION_STATUS).toBe("NOT_IMPLEMENTED");
  });

  it("nega autenticação independente de dispositivo não registrado, suspenso ou revogado", async () => {
    const verifier = new FakeDeviceSessionVerifier();
    const devices = new FakeDeviceReader();
    const service = new DeviceAuthenticationService(
      verifier,
      devices,
      devicePolicy,
      new FakeClock(now)
    );
    for (const status of ["UNREGISTERED", "PENDING_APPROVAL", "SUSPENDED", "REVOKED"] as const) {
      devices.state = { status, minimumSessionEpoch: 1 };
      await expect(service.authenticate({ credential: "fixture-device-only" })).resolves.toEqual({
        outcome: "DENY",
        reason: "DEVICE_UNAVAILABLE"
      });
    }
    devices.state = { status: "ENROLLED", minimumSessionEpoch: Number.NaN };
    await expect(service.authenticate({ credential: "fixture-device-only" })).resolves.toEqual({
      outcome: "DENY",
      reason: "INCONCLUSIVE"
    });
  });

  it("DEVICE_AUTHENTICATED confirma o dispositivo solicitante, não o grant do workspace", async () => {
    const verifier = new FakeDeviceSessionVerifier();
    const devices = new FakeDeviceReader();
    const service = new DeviceAuthenticationService(
      verifier,
      devices,
      devicePolicy,
      new FakeClock(now)
    );
    await expect(service.authenticate({ credential: "fixture-device-only" })).resolves.toEqual({
      outcome: "DEVICE_AUTHENTICATED",
      deviceId: "fixture-device-id",
      resource: devicePolicy.resource
    });
    expect(WORKSPACE_AUTHORIZATION_STATUS).toBe("NOT_IMPLEMENTED");
  });
});

describe("contrato conceitual de enrollment", () => {
  it("usa challenge de uso único, expira, nega offline e mantém aprovação local indisponível", () => {
    const registry = new FakeEnrollmentRegistry();
    registry.issue("fixture-challenge", now, 30);
    expect(registry.prove("fixture-challenge", now + 1, true)).toBe("PENDING_APPROVAL");
    expect(registry.prove("fixture-challenge", now + 2, true)).toBe("DENY");
    registry.issue("expired-challenge", now, 1);
    expect(registry.prove("expired-challenge", now + 1, true)).toBe("DENY");
    registry.issue("offline-challenge", now, 30);
    registry.online = false;
    expect(registry.prove("offline-challenge", now + 1, true)).toBe("DENY");
    expect(registry.assessOwnerApproval(true)).toBe("INCONCLUSIVE");
  });
});
