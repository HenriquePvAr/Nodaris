// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

/** Vocabulário compartilhado da camada de plataforma, sem dependência do SO. */
export type PlatformName = "windows" | "macos" | "linux" | "unknown";

export type CpuArchitecture = "x64" | "arm64" | "arm" | "ia32" | "unknown";

export type PlatformCapability =
  | "secure-credential-store"
  | "process-identity-inspection"
  | "user-autostart"
  | "private-state-permissions"
  | "atomic-state-replacement";

export const NODARIS_CAPABILITIES = [
  "metadata.read",
  "project.read",
  "code.search",
  "git.read",
  "workspace.diff.read",
  "team.manage",
  "member.invite",
  "member.remove",
  "grant.manage",
  "workspace.write.approved",
  "test.run.approved"
] as const;

export type NodarisCapability = (typeof NODARIS_CAPABILITIES)[number];
export type FutureWriteCapability = "workspace.write.approved" | "test.run.approved";

export type AdapterErrorCode =
  | "UNAVAILABLE"
  | "UNSUPPORTED"
  | "DENIED"
  | "INVALID_INPUT"
  | "INCONCLUSIVE"
  | "CONFLICT";

/** Erro tipado deliberadamente sem mensagem de exceção ou dados do sistema. */
export interface AdapterFailure {
  readonly code: AdapterErrorCode;
}

export type AdapterResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: AdapterFailure };

export function success<T>(value: T): AdapterResult<T> {
  return { ok: true, value };
}

export function failure<T = never>(code: AdapterErrorCode): AdapterResult<T> {
  return { ok: false, error: { code } };
}

/** Concede apenas capacidades conhecidas explicitamente habilitadas; escrita futura é negada. */
export function authorizeCapability(
  capability: string,
  enabled: readonly string[] = []
): capability is NodarisCapability {
  if (!(NODARIS_CAPABILITIES as readonly string[]).includes(capability)) return false;
  if (capability === "workspace.write.approved" || capability === "test.run.approved") return false;
  return enabled.includes(capability);
}
