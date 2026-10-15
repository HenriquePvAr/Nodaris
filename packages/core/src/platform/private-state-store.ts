// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import type { AdapterResult } from "./types.js";

export interface PrivateStateSnapshot<T> {
  readonly schemaVersion: number;
  readonly value: T;
}

export type PrivateStateProtection = "private-acl" | "private-posix-mode" | "unverified";

export interface PrivateStateRequirements {
  readonly atomicReplacement: true;
  readonly protection: "private-acl-or-posix-mode";
}

export interface PrivateStateStore {
  readonly protection: PrivateStateProtection;
  readonly requirements: PrivateStateRequirements;
  load<T>(schemaVersion: number): Promise<AdapterResult<PrivateStateSnapshot<T> | null>>;
  save<T>(snapshot: PrivateStateSnapshot<T>): Promise<AdapterResult<void>>;
}
