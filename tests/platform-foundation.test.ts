// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { readFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { createPlatformInfo } from "../packages/core/src/platform/platform-info.js";
import {
  assessLocalApproval,
  type LocalApprovalRequest
} from "../packages/core/src/platform/local-approval.js";
import { assessTermination } from "../packages/core/src/platform/process-supervisor.js";
import { authorizeCapability, NODARIS_CAPABILITIES } from "../packages/core/src/platform/types.js";
import {
  FakeAutostartManager,
  FakeCredentialStore,
  FakePathPolicy,
  FakePrivateStateStore,
  FakeProcessSupervisor,
  fakeApproval
} from "./fixtures/platform/fakes.js";

const repository = process.cwd();

describe("contratos de plataforma isolados", () => {
  it.each(["windows", "macos", "linux"] as const)(
    "representa %s sem sondagem do sistema",
    (name) => {
      const info = createPlatformInfo(name, "x64", { "user-autostart": true });
      expect(info.name).toBe(name);
      expect(info.supports("user-autostart")).toBe(true);
      expect(info.supports("secure-credential-store")).toBe(false);
    }
  );

  it("mantém plataforma desconhecida sem capacidade inferida", () => {
    const info = createPlatformInfo("unknown", "unknown", { "user-autostart": true });
    expect(info.supports("user-autostart")).toBe(false);
  });

  it("nega capacidades por padrão, desconhecidas e escrita futura", () => {
    expect(authorizeCapability("project.read")).toBe(false);
    expect(authorizeCapability("not-a-capability", ["not-a-capability"])).toBe(false);
    expect(authorizeCapability("workspace.write.approved", ["workspace.write.approved"])).toBe(
      false
    );
    expect(authorizeCapability("test.run.approved", ["test.run.approved"])).toBe(false);
    expect(authorizeCapability("team.manage", ["team.manage"])).toBe(true);
    expect(NODARIS_CAPABILITIES).toHaveLength(11);
  });

  it("não confia em referência de raiz fornecida pelo chamador sem validação runtime", async () => {
    const policy = new FakePathPolicy();
    const callerReference = { value: "fixture-root", projectId: "fixture-project" };
    const decision = await policy.authorize(callerReference, { value: "file.ts" });
    expect(decision).toEqual({ status: "inconclusive", reason: "verification-unavailable" });
    expect(decision.status).not.toBe("authorized");
  });

  it("não usa fallback em texto quando o cofre está indisponível", async () => {
    const store = new FakeCredentialStore(false);
    const reference = { id: "fixture-reference", purpose: "test" };
    const secret = "fixture-secret-sentinel";
    const writeResult = await store.store(reference, { value: secret });
    const result = await store.resolve(reference);
    expect(writeResult).toEqual({ ok: false, error: { code: "UNAVAILABLE" } });
    expect(result).toEqual({ ok: false, error: { code: "UNAVAILABLE" } });
    expect(JSON.stringify([writeResult, result])).not.toContain(secret);
  });

  it("não autoriza encerramento se a identidade de processo for inconclusiva", async () => {
    const supervisor = new FakeProcessSupervisor(null);
    const identity = { pid: 10, createdAt: "2030-01-01T00:00:00Z", executableIdentity: "fixture" };
    const result = await supervisor.inspect();
    const verdict = supervisor.verifyIdentity(identity, result.ok ? result.value : null);
    expect(verdict).toBe("inconclusive");
    expect(supervisor.assessTermination(verdict)).toBe("deny");
    expect(assessTermination("mismatch")).toBe("deny");
  });

  it("limita recuperação fake e não altera autostart", async () => {
    const policy = new FakeProcessSupervisor(null);
    expect(
      policy.planRecovery(2, { maxAttempts: 3, initialBackoffMs: 100, maximumBackoffMs: 250 })
    ).toEqual({ ok: true, value: { delayMs: 200 } });
    expect(
      policy.planRecovery(4, { maxAttempts: 3, initialBackoffMs: 100, maximumBackoffMs: 250 })
    ).toEqual({ ok: false, error: { code: "DENIED" } });
    const autostart = new FakeAutostartManager("windows", "absent");
    await expect(autostart.plan("enable")).resolves.toEqual({
      ok: false,
      error: { code: "UNSUPPORTED" }
    });
    await expect(autostart.inspect()).resolves.toEqual({ ok: true, value: "absent" });
  });

  it("armazena estado fake apenas em memória", async () => {
    const store = new FakePrivateStateStore();
    await expect(store.save({ schemaVersion: 1, value: { marker: "fixture" } })).resolves.toEqual({
      ok: true,
      value: undefined
    });
    await expect(store.load<{ marker: string }>(1)).resolves.toEqual({
      ok: true,
      value: { schemaVersion: 1, value: { marker: "fixture" } }
    });
  });

  it.each(["DENIED", "EXPIRED", "REVOKED"] as const)(
    "não torna registro %s uma autorização",
    (status) => {
      const scope = {
        deviceId: "fixture-device",
        workspaceId: "fixture-workspace",
        capability: "project.read" as const,
        requesterId: "fixture-requester"
      };
      const assessment = assessLocalApproval(
        fakeApproval(status),
        scope,
        new Date("2029-01-01T00:00:00Z")
      );
      expect(assessment.effectiveAuthorization).toBe(false);
      expect(assessment.recordAppearsCurrent).toBe(false);
    }
  );

  it("separa pedido remoto fabricado de decisão local com proveniência não verificada", () => {
    const scope = {
      deviceId: "fixture-device",
      workspaceId: "fixture-workspace",
      capability: "project.read" as const,
      requesterId: "fixture-requester"
    };
    const remoteRequest: LocalApprovalRequest = {
      id: "fixture-request",
      ...scope,
      requestedAt: "2028-01-01T00:00:00.000Z",
      requestedExpiresAt: "2030-01-01T00:00:00.000Z"
    };
    const fabricatedPayload = {
      ...remoteRequest,
      status: "APPROVED",
      approvalChannel: "trusted-local"
    };
    expect("status" in remoteRequest).toBe(false);
    expect("provenance" in fabricatedPayload).toBe(false);

    const unverifiedDecision = fakeApproval("APPROVED");
    const assessment = assessLocalApproval(
      unverifiedDecision,
      scope,
      new Date("2029-01-01T00:00:00Z")
    );
    expect(assessment.recordWellFormed).toBe(true);
    expect(assessment.recordAppearsCurrent).toBe(true);
    expect(assessment.effectiveAuthorization).toBe(false);
  });

  it("nega registro expirado ou associado a outro escopo", () => {
    const scope = {
      deviceId: "fixture-device",
      workspaceId: "fixture-workspace",
      capability: "project.read" as const,
      requesterId: "fixture-requester"
    };
    const approved = fakeApproval("APPROVED");
    const expired = assessLocalApproval(
      { ...approved, expiresAt: "2028-12-31T23:59:59.000Z" },
      scope,
      new Date("2029-01-01T00:00:00Z")
    );
    const wrongScope = assessLocalApproval(
      approved,
      { ...scope, workspaceId: "other" },
      new Date("2029-01-01T00:00:00Z")
    );
    expect(expired.recordAppearsCurrent).toBe(false);
    expect(expired.effectiveAuthorization).toBe(false);
    expect(wrongScope.scopeMatches).toBe(false);
    expect(wrongScope.effectiveAuthorization).toBe(false);
    expect(authorizeCapability("workspace.write.approved", ["workspace.write.approved"])).toBe(
      false
    );
  });

  it("mantém os fakes fora da composição de produção", async () => {
    const productionFiles = [
      "apps/agent/src/index.ts",
      "apps/gateway/src/index.ts",
      "packages/core/src/config.ts",
      "packages/core/src/filesystem.ts",
      "packages/core/src/git.ts",
      "scripts/windows/supervisor.ps1",
      "scripts/windows/launcher.vbs"
    ];
    const sources = await Promise.all(
      productionFiles.map((file) => readFile(path.join(repository, file), "utf8"))
    );
    expect(sources.join("\n")).not.toMatch(
      /fixtures\/platform|Fake(?:PathPolicy|CredentialStore|ProcessSupervisor)/
    );
  });
});

describe("compatibilidade MCP M01", () => {
  it("preserva as nove ferramentas públicas e suas operações RPC", async () => {
    const gateway = await readFile(path.join(repository, "apps/gateway/src/index.ts"), "utf8");
    const expectedTools = [
      "nodaris_health",
      "nodaris_machines_list",
      "nodaris_projects_list",
      "nodaris_project_tree",
      "nodaris_code_search",
      "nodaris_file_read",
      "nodaris_git_status",
      "nodaris_git_diff",
      "nodaris_git_log"
    ];
    for (const name of expectedTools) expect(gateway).toContain(`"${name}"`);
    expect(gateway.match(/readOnlyHint: true/g)).toHaveLength(1);
    expect(gateway).not.toMatch(/registerTool\(\s*["'][^"']*(?:write|execute|shell|branch)/i);

    const contracts = await readFile(
      path.join(repository, "packages/core/src/contracts.ts"),
      "utf8"
    );
    const operations = [
      "health",
      "machines.list",
      "projects.list",
      "project.tree",
      "code.search",
      "file.read",
      "git.status",
      "git.diff",
      "git.log"
    ];
    for (const operation of operations) expect(contracts).toContain(`z.literal("${operation}")`);
  });
});
