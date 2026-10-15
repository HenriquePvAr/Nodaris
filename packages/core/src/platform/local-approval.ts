// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type { NodarisCapability } from "./types.js";

export type ApprovalStatus = "REQUESTED" | "APPROVED" | "DENIED" | "EXPIRED" | "REVOKED";
export type ApprovalDecisionStatus = Exclude<ApprovalStatus, "REQUESTED">;

/** Pedido remoto/local descreve intenção; não contém decisão nem concede autorização. */
export interface LocalApprovalRequest {
  readonly id: string;
  readonly deviceId: string;
  readonly workspaceId: string;
  readonly capability: NodarisCapability;
  readonly requesterId: string;
  readonly requestedAt: string;
  readonly requestedExpiresAt: string;
}

export interface LocalApprovalScope {
  readonly deviceId: string;
  readonly workspaceId: string;
  readonly capability: NodarisCapability;
  readonly requesterId: string;
}

/**
 * Registro de decisão ainda sem proveniência autenticada. O campo literal evita sugerir que
 * campos fornecidos pelo chamador ou pelo ChatGPT comprovem uma aprovação local.
 */
export interface LocalApprovalDecisionRecord {
  readonly requestId: string;
  readonly status: ApprovalDecisionStatus;
  readonly scope: LocalApprovalScope;
  readonly decidedAt: string;
  readonly expiresAt: string;
  readonly provenance: "unverified-record";
}

export interface LocalApprovalAssessment {
  readonly recordWellFormed: boolean;
  readonly scopeMatches: boolean;
  readonly recordAppearsCurrent: boolean;
  /** Literal false até existir um verificador confiável de origem e consentimento. */
  readonly effectiveAuthorization: false;
}

export interface LocalApproval {
  assess(
    record: LocalApprovalDecisionRecord,
    expectedScope: LocalApprovalScope,
    now: Date
  ): LocalApprovalAssessment;
}

/** Valida formato e escopo para diagnóstico; nunca transforma o registro em autorização. */
export function assessLocalApproval(
  record: LocalApprovalDecisionRecord,
  expectedScope: LocalApprovalScope,
  now: Date
): LocalApprovalAssessment {
  const decidedAt = Date.parse(record.decidedAt);
  const expiresAt = Date.parse(record.expiresAt);
  const recordWellFormed =
    record.provenance === "unverified-record" &&
    Number.isFinite(decidedAt) &&
    Number.isFinite(expiresAt) &&
    expiresAt > decidedAt;
  const scopeMatches =
    record.scope.deviceId === expectedScope.deviceId &&
    record.scope.workspaceId === expectedScope.workspaceId &&
    record.scope.capability === expectedScope.capability &&
    record.scope.requesterId === expectedScope.requesterId;
  const recordAppearsCurrent =
    record.status === "APPROVED" && recordWellFormed && scopeMatches && expiresAt > now.getTime();

  return { recordWellFormed, scopeMatches, recordAppearsCurrent, effectiveAuthorization: false };
}

export const localApprovalPolicy: LocalApproval = { assess: assessLocalApproval };
