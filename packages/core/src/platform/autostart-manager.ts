// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type { AdapterResult, PlatformName } from "./types.js";

export type AutostartAction = "install" | "inspect" | "enable" | "disable" | "remove";
export type AutostartState = "installed-enabled" | "installed-disabled" | "absent" | "unknown";

export interface AutostartCapabilities {
  readonly platform: PlatformName;
  readonly userScoped: boolean;
  readonly requiresElevation: "yes" | "no" | "unknown";
  readonly supportedActions: readonly AutostartAction[];
}

export interface AutostartPlan {
  readonly action: AutostartAction;
  readonly state: AutostartState;
  readonly requiresUserApproval: true;
  readonly requiresElevation: "yes" | "no" | "unknown";
}

/** Contrato para planejamento e consulta; não altera autostart por si só. */
export interface AutostartManager {
  capabilities(): AutostartCapabilities;
  inspect(): Promise<AdapterResult<AutostartState>>;
  plan(action: AutostartAction): Promise<AdapterResult<AutostartPlan>>;
}
