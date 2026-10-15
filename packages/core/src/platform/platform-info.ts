// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type { CpuArchitecture, PlatformCapability, PlatformName } from "./types.js";

export interface PlatformInfo {
  readonly name: PlatformName;
  readonly architecture: CpuArchitecture;
  readonly capabilities: Readonly<Partial<Record<PlatformCapability, boolean>>>;
  supports(capability: PlatformCapability): boolean;
}

/** Contrato futuro de detecção; não existe provider nativo nesta etapa. */
export interface PlatformInfoProvider {
  detect(): PlatformInfo;
}

/** Cria um retrato a partir de dados fornecidos pelo chamador; não consulta hardware. */
export function createPlatformInfo(
  name: PlatformName,
  architecture: CpuArchitecture,
  capabilities: Readonly<Partial<Record<PlatformCapability, boolean>>> = {}
): PlatformInfo {
  const snapshot = Object.freeze({ ...capabilities });
  return Object.freeze({
    name,
    architecture,
    capabilities: snapshot,
    supports: (capability: PlatformCapability) =>
      name !== "unknown" && snapshot[capability] === true
  });
}
