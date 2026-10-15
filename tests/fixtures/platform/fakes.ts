// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type {
  AutostartAction,
  AutostartManager,
  AutostartPlan,
  AutostartState
} from "../../../packages/core/src/platform/autostart-manager.js";
import type {
  CredentialMaterial,
  CredentialReference,
  CredentialStore
} from "../../../packages/core/src/platform/credential-store.js";
import type {
  ApprovalDecisionStatus,
  LocalApprovalDecisionRecord
} from "../../../packages/core/src/platform/local-approval.js";
import type {
  PathAuthorizationDecision,
  PathPolicy,
  RootReference,
  UntrustedLocalPath
} from "../../../packages/core/src/platform/path-policy.js";
import type {
  ProcessIdentity,
  ProcessSupervisor,
  RecoveryPolicy
} from "../../../packages/core/src/platform/process-supervisor.js";
import type {
  PrivateStateSnapshot,
  PrivateStateStore
} from "../../../packages/core/src/platform/private-state-store.js";
import {
  failure,
  success,
  type AdapterResult,
  type PlatformName
} from "../../../packages/core/src/platform/types.js";

/** Fakes determinísticos usados somente pelos testes; não fazem I/O nem chamam o SO. */
export class FakePathPolicy implements PathPolicy {
  constructor(
    private readonly outcome: "authorized" | "denied" | "inconclusive" = "inconclusive"
  ) {}

  async authorize(
    root: RootReference,
    input: UntrustedLocalPath
  ): Promise<PathAuthorizationDecision> {
    if (this.outcome === "denied") return { status: "denied", reason: "outside-authorized-root" };
    if (this.outcome === "inconclusive")
      return { status: "inconclusive", reason: "verification-unavailable" };
    return {
      status: "authorized",
      projectId: root.projectId,
      canonicalRoot: root.value,
      canonicalPath: `${root.value}/${input.value}`,
      validation: {
        canonicalization: "verified",
        containment: "contained",
        symbolicLinks: "absent",
        reparsePoints: "absent",
        alternateDataStreams: "absent",
        aliases: "absent"
      }
    };
  }
}

export class FakeCredentialStore implements CredentialStore {
  private readonly values = new Map<string, string>();

  constructor(private readonly available = true) {}

  async store(reference: CredentialReference, material: CredentialMaterial) {
    if (!this.available) return failure("UNAVAILABLE");
    this.values.set(reference.id, material.value);
    return success(undefined);
  }

  async resolve(reference: CredentialReference) {
    if (!this.available) return failure<CredentialMaterial>("UNAVAILABLE");
    const value = this.values.get(reference.id);
    return value === undefined ? failure<CredentialMaterial>("UNAVAILABLE") : success({ value });
  }

  async rotate(reference: CredentialReference, replacement: CredentialMaterial) {
    if (!this.available || !this.values.has(reference.id)) return failure("UNAVAILABLE");
    this.values.set(reference.id, replacement.value);
    return success(undefined);
  }

  async delete(reference: CredentialReference) {
    if (!this.available) return failure("UNAVAILABLE");
    this.values.delete(reference.id);
    return success(undefined);
  }
}

export class FakeProcessSupervisor implements ProcessSupervisor {
  constructor(private readonly observed: ProcessIdentity | null) {}

  async inspect(): Promise<AdapterResult<ProcessIdentity | null>> {
    return success(this.observed);
  }

  verifyIdentity(expected: ProcessIdentity, observed: ProcessIdentity | null) {
    if (!observed) return "inconclusive" as const;
    return expected.pid === observed.pid &&
      expected.createdAt === observed.createdAt &&
      expected.executableIdentity === observed.executableIdentity
      ? ("confirmed" as const)
      : ("mismatch" as const);
  }

  assessTermination(verdict: "confirmed" | "mismatch" | "inconclusive") {
    return verdict === "confirmed" ? ("allow" as const) : ("deny" as const);
  }

  planRecovery(attempt: number, policy: RecoveryPolicy) {
    if (attempt < 1 || attempt > policy.maxAttempts) return failure<{ delayMs: number }>("DENIED");
    const delayMs = Math.min(policy.initialBackoffMs * 2 ** (attempt - 1), policy.maximumBackoffMs);
    return success({ delayMs });
  }
}

export class FakeAutostartManager implements AutostartManager {
  constructor(
    private readonly platform: PlatformName,
    private readonly state: AutostartState
  ) {}

  capabilities() {
    return {
      platform: this.platform,
      userScoped: true,
      requiresElevation: "no" as const,
      supportedActions: ["inspect"] as const
    };
  }

  async inspect() {
    return success(this.state);
  }

  async plan(action: AutostartAction): Promise<AdapterResult<AutostartPlan>> {
    if (action !== "inspect") return failure("UNSUPPORTED");
    return success({
      action,
      state: this.state,
      requiresUserApproval: true,
      requiresElevation: "no"
    });
  }
}

export class FakePrivateStateStore implements PrivateStateStore {
  readonly protection = "private-acl" as const;
  readonly requirements = {
    atomicReplacement: true,
    protection: "private-acl-or-posix-mode"
  } as const;
  private snapshot: PrivateStateSnapshot<unknown> | null = null;

  async load<T>(schemaVersion: number): Promise<AdapterResult<PrivateStateSnapshot<T> | null>> {
    if (!this.snapshot) return success(null);
    if (this.snapshot.schemaVersion !== schemaVersion) return failure("INVALID_INPUT");
    return success(this.snapshot as PrivateStateSnapshot<T>);
  }

  async save<T>(snapshot: PrivateStateSnapshot<T>) {
    this.snapshot = structuredClone(snapshot);
    return success(undefined);
  }
}

export function fakeApproval(status: ApprovalDecisionStatus): LocalApprovalDecisionRecord {
  return {
    requestId: "fixture-approval",
    status,
    scope: {
      deviceId: "fixture-device",
      workspaceId: "fixture-workspace",
      capability: "project.read",
      requesterId: "fixture-requester"
    },
    decidedAt: "2028-01-01T00:00:00.000Z",
    expiresAt: "2030-01-01T00:00:00.000Z",
    provenance: "unverified-record"
  };
}
