// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type { AdapterResult } from "./types.js";

export interface CredentialReference {
  readonly id: string;
  readonly purpose: string;
}

/** Material secreto é transitório e não deve integrar erros, telemetria ou serialização. */
export interface CredentialMaterial {
  readonly value: string;
}

export interface CredentialStore {
  store(reference: CredentialReference, material: CredentialMaterial): Promise<AdapterResult<void>>;
  resolve(reference: CredentialReference): Promise<AdapterResult<CredentialMaterial>>;
  rotate(
    reference: CredentialReference,
    replacement: CredentialMaterial
  ): Promise<AdapterResult<void>>;
  delete(reference: CredentialReference): Promise<AdapterResult<void>>;
}
