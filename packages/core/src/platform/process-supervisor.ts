// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type { AdapterResult } from "./types.js";

export type SupervisedProcessState =
  | "starting"
  | "healthy"
  | "stopping"
  | "stopped"
  | "failed"
  | "degraded";

export interface ProcessIdentity {
  readonly pid: number;
  readonly createdAt: string;
  readonly executableIdentity: string;
}

export interface SupervisedProcess {
  readonly component: "agent" | "gateway" | "tunnel-client";
  readonly expectedIdentity: ProcessIdentity;
  readonly state: SupervisedProcessState;
}

export type IdentityVerdict = "confirmed" | "mismatch" | "inconclusive";
export type TerminationAssessment = "allow" | "deny";

export interface RecoveryPolicy {
  readonly maxAttempts: number;
  readonly initialBackoffMs: number;
  readonly maximumBackoffMs: number;
}

export interface ProcessSupervisor {
  inspect(process: SupervisedProcess): Promise<AdapterResult<ProcessIdentity | null>>;
  verifyIdentity(expected: ProcessIdentity, observed: ProcessIdentity | null): IdentityVerdict;
  assessTermination(verdict: IdentityVerdict): TerminationAssessment;
  planRecovery(attempt: number, policy: RecoveryPolicy): AdapterResult<{ delayMs: number }>;
}

/** A identidade incerta nunca autoriza encerramento. */
export function assessTermination(verdict: IdentityVerdict): TerminationAssessment {
  return verdict === "confirmed" ? "allow" : "deny";
}
