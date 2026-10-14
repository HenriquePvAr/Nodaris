// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { ZodError } from "zod/v4";

export const publicErrorCatalog = {
  REQUEST_INVALID: {
    message: "Requisição inválida.",
    reason: "request.invalid"
  },
  PROJECT_NOT_AUTHORIZED: {
    message: "Projeto não encontrado ou não autorizado.",
    reason: "authorization.denied"
  },
  PATH_INVALID: { message: "Caminho inválido.", reason: "filesystem.validation" },
  ADS_BLOCKED: {
    message: "Fluxos de dados alternativos NTFS não são permitidos.",
    reason: "filesystem.policy_denied"
  },
  PATH_BLOCKED: {
    message: "Caminho bloqueado pela política de segurança.",
    reason: "filesystem.policy_denied"
  },
  ACCESS_OUTSIDE_PROJECT: {
    message: "Acesso fora do projeto autorizado.",
    reason: "authorization.denied"
  },
  SYMLINK_BLOCKED: {
    message: "Acesso por link simbólico não é permitido.",
    reason: "filesystem.policy_denied"
  },
  ROOT_INVALID: {
    message: "Raiz autorizada precisa ser um diretório.",
    reason: "filesystem.invalid"
  },
  FILE_TOO_LARGE: {
    message: "Arquivo inválido ou acima do limite de 1 MB.",
    reason: "filesystem.limit"
  },
  FILE_TYPE_BLOCKED: {
    message: "Tipo de arquivo não textual permitido.",
    reason: "filesystem.policy_denied"
  },
  BINARY_BLOCKED: {
    message: "Arquivo binário não pode ser lido.",
    reason: "filesystem.policy_denied"
  },
  SENSITIVE_CONTENT_BLOCKED: {
    message: "Conteúdo potencialmente sensível bloqueado.",
    reason: "filesystem.policy_denied"
  },
  SEARCH_LIMIT: {
    message: "Pesquisa interrompida pelo limite de recursos.",
    reason: "search.budget_exceeded"
  },
  SEARCH_CONCURRENCY_LIMIT: {
    message: "Limite de pesquisas simultâneas atingido.",
    reason: "search.concurrency_limited"
  },
  GIT_REPOSITORY_BLOCKED: {
    message: "Consultas Git bloqueadas para repositório com metadados externos.",
    reason: "git.policy_denied"
  },
  GIT_METADATA_OUTSIDE: {
    message: "Metadados Git fora do projeto autorizado.",
    reason: "git.policy_denied"
  },
  GIT_DIFF_SENSITIVE_FILE: {
    message: "Diff bloqueado porque o repositório contém arquivos sensíveis alterados.",
    reason: "git.policy_denied"
  },
  GIT_ATTRIBUTES_INVALID: {
    message: "Diff bloqueado porque .gitattributes não é arquivo regular.",
    reason: "git.policy_denied"
  },
  GIT_ATTRIBUTES_OUTSIDE: {
    message: "Diff bloqueado porque .gitattributes sai do projeto.",
    reason: "git.policy_denied"
  },
  GIT_EXTERNAL_FILTER: {
    message: "Diff bloqueado porque o repositório configura filtros Git externos.",
    reason: "git.policy_denied"
  },
  GIT_DIFF_TOO_LARGE: { message: "Diff excede o limite de 200 KB.", reason: "git.limit" },
  GIT_DIFF_SENSITIVE_CONTENT: {
    message: "Diff bloqueado por conter conteúdo que parece credencial.",
    reason: "git.policy_denied"
  },
  GIT_POSSIBLE_CREDENTIAL: {
    message: "Diff bloqueado por conter uma possível credencial.",
    reason: "git.policy_denied"
  },
  FILESYSTEM_FAILURE: {
    message: "Falha ao processar arquivo ou diretório.",
    reason: "filesystem.failure"
  },
  GIT_FAILURE: { message: "Falha ao consultar o repositório Git.", reason: "git.failure" },
  AGENT_UNAUTHORIZED: { message: "Agente recusou a autenticação.", reason: "authorization.denied" },
  AGENT_UNAVAILABLE: {
    message: "Agente local indisponível ou requisição recusada.",
    reason: "agent.unavailable"
  },
  INTERNAL: { message: "Falha interna.", reason: "internal.failure" }
} as const;

export type PublicErrorCode = keyof typeof publicErrorCatalog;
export type SafeOperation =
  | "health"
  | "machines.list"
  | "projects.list"
  | "project.tree"
  | "code.search"
  | "file.read"
  | "git.status"
  | "git.diff"
  | "git.log";

export class NodarisError extends Error {
  readonly code: PublicErrorCode;

  constructor(code: PublicErrorCode) {
    super(publicErrorCatalog[code].message);
    this.name = "NodarisError";
    this.code = code;
  }
}

export interface SafeError {
  code: PublicErrorCode;
  message: string;
  reason: string;
}

export function isPublicErrorCode(value: unknown): value is PublicErrorCode {
  return typeof value === "string" && Object.hasOwn(publicErrorCatalog, value);
}

export function safeError(error: unknown, operation?: SafeOperation): SafeError {
  let code: PublicErrorCode = "INTERNAL";
  if (error instanceof NodarisError) code = error.code;
  else if (error instanceof ZodError || error instanceof SyntaxError) code = "REQUEST_INVALID";
  else if (operation === "file.read" || operation === "project.tree" || operation === "code.search")
    code = "FILESYSTEM_FAILURE";
  else if (operation?.startsWith("git.")) code = "GIT_FAILURE";

  const entry = publicErrorCatalog[code];
  return { code, message: entry.message, reason: entry.reason };
}

export function safeErrorFromCode(value: unknown): SafeError {
  const code = isPublicErrorCode(value) ? value : "INTERNAL";
  const entry = publicErrorCatalog[code];
  return { code, message: entry.message, reason: entry.reason };
}
