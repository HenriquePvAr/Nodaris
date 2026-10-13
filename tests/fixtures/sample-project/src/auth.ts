// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

export function isAuthenticated(token: string): boolean {
  return token.length > 0;
}
