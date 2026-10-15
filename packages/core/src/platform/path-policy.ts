// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

/** Referência do chamador. Projeto e caminho não provam allowlist nem canonicalização. */
export interface RootReference {
  readonly projectId: string;
  readonly value: string;
}

/** Entrada não confiável: nunca deve ser usada diretamente como caminho do SO. */
export interface UntrustedLocalPath {
  readonly value: string;
}

export type PathBlockReason =
  | "outside-authorized-root"
  | "symbolic-link"
  | "reparse-point"
  | "alternate-data-stream"
  | "alias"
  | "ambiguous"
  | "verification-unavailable"
  | "validation-inconclusive";

/** Evidências que o adaptador nativo precisa verificar em runtime. Strings não são prova. */
export interface NativePathValidation {
  readonly canonicalization: "verified" | "failed" | "unavailable";
  readonly containment: "contained" | "outside" | "unknown";
  readonly symbolicLinks: "absent" | "present" | "unknown";
  readonly reparsePoints: "absent" | "present" | "unknown";
  readonly alternateDataStreams: "absent" | "present" | "unknown";
  readonly aliases: "absent" | "present" | "unknown";
}

/** Resultado reportado pelo adaptador confiável após as verificações reais do SO. */
export type PathAuthorizationDecision =
  | {
      readonly status: "authorized";
      readonly projectId: string;
      readonly canonicalRoot: string;
      readonly canonicalPath: string;
      readonly validation: NativePathValidation;
    }
  | { readonly status: "denied"; readonly reason: PathBlockReason }
  | { readonly status: "inconclusive"; readonly reason: PathBlockReason };

/**
 * Contrato futuro: a implementação precisa validar a referência e o caminho no SO a cada uso.
 * Tipos e objetos estruturais não são controles de segurança nem prova de autorização.
 */
export interface PathPolicy {
  authorize(root: RootReference, input: UntrustedLocalPath): Promise<PathAuthorizationDecision>;
}
