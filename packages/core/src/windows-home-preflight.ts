// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

/** Entrada já observada pelo chamador. Este preflight não executa processos nem altera o host. */
export interface WindowsHomeSnapshot {
  readonly platform: "windows" | "macos" | "linux" | "unknown";
  readonly nodeVersion: string | null;
  readonly pnpmVersion: string | null;
  readonly repositoryPathAbsolute: boolean;
  readonly repositoryPathContainsLegacyUserPath: boolean;
  readonly allowedRootExplicitlySelected: boolean;
  readonly privateCredentialStoreAvailable: boolean | null;
  readonly independentTunnelProvisioned: boolean;
  readonly conflictingTask: boolean | null;
  readonly conflictingPath: boolean | null;
  readonly conflictingPorts: readonly number[];
  readonly conflictingInstance: boolean | null;
  readonly tunnelProfileAvailable: boolean | null;
}

export type HomePreflightCode =
  | "UNSUPPORTED_HOST"
  | "NODE_VERSION_UNSUPPORTED"
  | "PNPM_VERSION_UNSUPPORTED"
  | "REPOSITORY_PATH_INVALID"
  | "LEGACY_PATH_DETECTED"
  | "ROOT_NOT_APPROVED"
  | "CREDENTIAL_STORE_UNAVAILABLE"
  | "TUNNEL_NOT_PROVISIONED"
  | "TASK_CONFLICT"
  | "PATH_CONFLICT"
  | "PORT_CONFLICT"
  | "INSTANCE_CONFLICT"
  | "TUNNEL_PROFILE_UNAVAILABLE"
  | "HOST_FACTS_INCOMPLETE";

export interface WindowsHomePreflight {
  readonly status: "ready" | "blocked" | "inconclusive";
  readonly findings: readonly HomePreflightCode[];
  readonly plannedPorts: readonly [3333, 3334, 8080];
  readonly effectsPerformed: false;
}

function major(version: string | null): number | null {
  if (!version) return null;
  const match = /^v?(\d+)\./.exec(version);
  return match?.[1] ? Number(match[1]) : null;
}

/** Retorna somente códigos enumerados; nenhum caminho, usuário, token ou comando é revelado. */
export function inspectWindowsHome(snapshot: WindowsHomeSnapshot): WindowsHomePreflight {
  const findings: HomePreflightCode[] = [];
  if (snapshot.platform !== "windows") findings.push("UNSUPPORTED_HOST");
  const node = major(snapshot.nodeVersion);
  if (node === null) findings.push("HOST_FACTS_INCOMPLETE");
  else if (node < 22 || node >= 25) findings.push("NODE_VERSION_UNSUPPORTED");
  const pnpm = major(snapshot.pnpmVersion);
  if (pnpm === null) findings.push("HOST_FACTS_INCOMPLETE");
  else if (pnpm !== 12) findings.push("PNPM_VERSION_UNSUPPORTED");
  if (!snapshot.repositoryPathAbsolute) findings.push("REPOSITORY_PATH_INVALID");
  if (snapshot.repositoryPathContainsLegacyUserPath) findings.push("LEGACY_PATH_DETECTED");
  if (!snapshot.allowedRootExplicitlySelected) findings.push("ROOT_NOT_APPROVED");
  if (snapshot.privateCredentialStoreAvailable === false)
    findings.push("CREDENTIAL_STORE_UNAVAILABLE");
  if (
    snapshot.privateCredentialStoreAvailable === null ||
    snapshot.conflictingTask === null ||
    snapshot.conflictingPath === null ||
    snapshot.conflictingInstance === null ||
    snapshot.tunnelProfileAvailable === null
  )
    findings.push("HOST_FACTS_INCOMPLETE");
  if (!snapshot.independentTunnelProvisioned) findings.push("TUNNEL_NOT_PROVISIONED");
  if (snapshot.conflictingTask) findings.push("TASK_CONFLICT");
  if (snapshot.conflictingPath) findings.push("PATH_CONFLICT");
  if (snapshot.conflictingPorts.some((port) => [3333, 3334, 8080].includes(port)))
    findings.push("PORT_CONFLICT");
  if (snapshot.conflictingInstance) findings.push("INSTANCE_CONFLICT");
  if (snapshot.tunnelProfileAvailable === false) findings.push("TUNNEL_PROFILE_UNAVAILABLE");
  const unique = [...new Set(findings)];
  const blocked = unique.some((code) => code !== "HOST_FACTS_INCOMPLETE");
  return {
    status: blocked ? "blocked" : unique.length ? "inconclusive" : "ready",
    findings: unique,
    plannedPorts: [3333, 3334, 8080],
    effectsPerformed: false
  };
}
