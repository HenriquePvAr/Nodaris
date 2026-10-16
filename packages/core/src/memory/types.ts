// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

export const MISSION_STATUSES = [
  "PLANNED",
  "READY",
  "IN_PROGRESS",
  "BLOCKED",
  "PARTIAL",
  "COMPLETED",
  "FAILED",
  "CANCELED",
  "SUPERSEDED"
] as const;

export type MissionStatus = (typeof MISSION_STATUSES)[number];

export const MEMORY_RELATIONS = [
  "MISSION_HAS_CHILD",
  "MISSION_DEPENDS_ON",
  "MISSION_RESOLVES_BUG",
  "ATTEMPT_ADDRESSES_BUG",
  "ATTEMPT_FAILED_BECAUSE",
  "DECISION_SUPERSEDES",
  "EVIDENCE_SUPPORTS",
  "TEST_VALIDATES",
  "COMMIT_IMPLEMENTS",
  "PROJECT_USES",
  "FINDING_RELATES_TO",
  "PROPOSAL_ADDRESSES"
] as const;

export type MemoryRelationType = (typeof MEMORY_RELATIONS)[number];
export type MemoryEntityType =
  | "Project"
  | "Mission"
  | "MissionEvent"
  | "Bug"
  | "Finding"
  | "Attempt"
  | "Decision"
  | "Proposal"
  | "Experiment"
  | "Evidence"
  | "TestResult"
  | "CommitReference"
  | "ProjectSnapshot"
  | "MemorySession";

export type ClaimSource =
  | "codex_report"
  | "test_observation"
  | "git_verification"
  | "owner_confirmation"
  | "unverified_conclusion";

export interface MemoryRelation {
  readonly type: MemoryRelationType;
  readonly targetId: string;
  readonly source: ClaimSource;
  readonly inferred: boolean;
  readonly evidenceIds: readonly string[];
}

export interface MemoryClaim {
  readonly text: string;
  readonly source: ClaimSource;
  readonly evidenceIds: readonly string[];
  readonly verified: boolean;
}

export interface MemoryEntity {
  readonly schemaVersion: 1;
  readonly id: string;
  readonly type: MemoryEntityType;
  readonly projectId: string;
  readonly title: string;
  readonly createdAt: string;
  readonly updatedAt: string;
  readonly revision: number;
  readonly appliedOperationIds?: readonly string[];
  readonly relations: readonly MemoryRelation[];
  readonly claims: readonly MemoryClaim[];
  readonly body: string;
  readonly status?: MissionStatus;
  readonly missionCode?: string;
  readonly parentMissionId?: string;
  readonly objective?: string;
  readonly scope?: readonly string[];
  readonly acceptanceCriteria?: readonly string[];
  readonly priority?: "LOW" | "NORMAL" | "HIGH" | "URGENT";
  readonly dependencies?: readonly string[];
  readonly results?: readonly MemoryClaim[];
  readonly problems?: readonly string[];
  readonly attempts?: readonly string[];
  readonly corrections?: readonly string[];
  readonly evidenceIds?: readonly string[];
  readonly commitIds?: readonly string[];
  readonly decisionIds?: readonly string[];
  readonly nextSteps?: readonly string[];
  readonly statusHistory?: readonly {
    readonly from: MissionStatus | null;
    readonly to: MissionStatus;
    readonly changedAt: string;
    readonly source: ClaimSource;
  }[];
}

export interface MemoryProposal {
  readonly operationId: string;
  readonly operation: "create" | "update" | "noop";
  readonly projectId: string;
  readonly noteId: string;
  readonly entityType: MemoryEntityType;
  readonly fields: readonly string[];
  readonly beforeRevision: number | null;
  readonly afterRevision: number;
  readonly relations: readonly MemoryRelation[];
  readonly source: ClaimSource;
  readonly previewMarkdown: string;
}

export type MemoryErrorCode =
  | "INVALID_INPUT"
  | "NOT_FOUND"
  | "CONFLICT"
  | "DENIED"
  | "EXPIRED"
  | "OUTSIDE_VAULT"
  | "UNSAFE_PATH"
  | "VAULT_UNAVAILABLE"
  | "IO_FAILURE"
  | "CORRUPT_NOTE";

export class MemoryError extends Error {
  constructor(readonly code: MemoryErrorCode) {
    super(code);
    this.name = "MemoryError";
  }
}

export interface MemoryApprovalPolicy {
  approve(proposal: MemoryProposal): Promise<{
    readonly approved: boolean;
    readonly operationId: string;
    readonly expiresAt: string;
    readonly source: "local_interaction" | "isolated_test" | "untrusted";
  }>;
}

/** Deve ser implementado pela composição local; ausência ou incerteza sempre nega. */
export interface MemoryVaultSecurityPolicy {
  verifyVault(root: string): Promise<boolean>;
  verifyManagedDirectory(path: string): Promise<boolean>;
  /** Cria somente a pasta informada com ACL/permissões privadas antes de qualquer conteúdo. */
  prepareManagedDirectory(path: string): Promise<boolean>;
  /** Confirma ACL privada do arquivo antes de escrever e novamente após a persistência. */
  verifyManagedFile(path: string): Promise<boolean>;
}

export interface MemoryDraft {
  readonly id: string;
  readonly type: MemoryEntityType;
  readonly projectId: string;
  readonly title: string;
  readonly body: string;
  readonly source: ClaimSource;
  readonly claims?: readonly MemoryClaim[];
  readonly relations?: readonly MemoryRelation[];
  readonly status?: MissionStatus;
  readonly missionCode?: string;
  readonly parentMissionId?: string;
  readonly objective?: string;
  readonly scope?: readonly string[];
  readonly acceptanceCriteria?: readonly string[];
  readonly priority?: "LOW" | "NORMAL" | "HIGH" | "URGENT";
  readonly dependencies?: readonly string[];
  readonly results?: readonly MemoryClaim[];
  readonly problems?: readonly string[];
  readonly attempts?: readonly string[];
  readonly corrections?: readonly string[];
  readonly evidenceIds?: readonly string[];
  readonly commitIds?: readonly string[];
  readonly decisionIds?: readonly string[];
  readonly nextSteps?: readonly string[];
}
