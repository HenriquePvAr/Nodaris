// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { createHash, randomUUID } from "node:crypto";
import { link, lstat, open, readFile, realpath, rename, rm, unlink } from "node:fs/promises";
import path from "node:path";
import {
  MemoryError,
  type MemoryApprovalPolicy,
  type MemoryDraft,
  type MemoryEntity,
  type MemoryProposal,
  type MemoryRelation,
  type MemoryVaultSecurityPolicy,
  type MissionStatus
} from "./types.js";

const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
const MAX_NOTE_BYTES = 1_000_000;
const CLAIM_SOURCES = [
  "codex_report",
  "test_observation",
  "git_verification",
  "owner_confirmation",
  "unverified_conclusion"
] as const;
const PROJECTS_DIR = "Projects";
const CATEGORY: Record<MemoryEntity["type"], string> = {
  Project: "",
  Mission: "Missions",
  MissionEvent: "Sessions",
  Bug: "Bugs",
  Finding: "Findings",
  Attempt: "Attempts",
  Decision: "Decisions",
  Proposal: "Proposals",
  Experiment: "Experiments",
  Evidence: "Evidence",
  TestResult: "Evidence",
  CommitReference: "Evidence",
  ProjectSnapshot: "Sessions",
  MemorySession: "Sessions"
};

function filenameFor(id: string, type: MemoryEntity["type"]): string {
  return type === "Project" ? "PROJECT.md" : `${slug(id)}.md`;
}

const TERMINAL_STATUSES: readonly MissionStatus[] = ["COMPLETED", "FAILED", "CANCELED"];

function validId(value: string): boolean {
  return (
    ID_PATTERN.test(value) &&
    !value.endsWith(".") &&
    !/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i.test(value) &&
    !value.includes(":") &&
    !value.includes("/") &&
    !value.includes("\\")
  );
}

function safeText(value: string, maximum = 20_000): boolean {
  return value.length <= maximum && !value.includes("\0");
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableJson(record[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

function serialize(entity: MemoryEntity): string {
  // JSON is a strict YAML 1.2 subset: strings and arrays cannot inject frontmatter keys.
  const frontmatter = JSON.stringify(entity, null, 2);
  return `---\n${frontmatter}\n---\n\n${entity.body.trimEnd()}\n`;
}

function parseEntity(markdown: string): MemoryEntity {
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n(?:\r?\n)?([\s\S]*)$/.exec(markdown);
  if (!match?.[1] || match[2] === undefined) throw new MemoryError("CORRUPT_NOTE");
  let data: unknown;
  try {
    data = JSON.parse(match[1]);
  } catch {
    throw new MemoryError("CORRUPT_NOTE");
  }
  if (!data || typeof data !== "object" || Array.isArray(data))
    throw new MemoryError("CORRUPT_NOTE");
  const entity = data as Partial<MemoryEntity>;
  if (
    entity.schemaVersion !== 1 ||
    typeof entity.id !== "string" ||
    !validId(entity.id) ||
    typeof entity.projectId !== "string" ||
    !validId(entity.projectId) ||
    typeof entity.title !== "string" ||
    typeof entity.type !== "string" ||
    !Array.isArray(entity.relations) ||
    !Array.isArray(entity.claims) ||
    typeof entity.revision !== "number"
  )
    throw new MemoryError("CORRUPT_NOTE");
  return { ...(entity as MemoryEntity), body: match[2] };
}

function slug(value: string): string {
  if (!validId(value)) throw new MemoryError("INVALID_INPUT");
  return value;
}

export interface MemoryApprovalReceipt {
  readonly operationId: string;
  readonly expiresAt: string;
}

/**
 * Writer Markdown isolado do runtime Nodaris. Exige políticas locais injetadas e não possui
 * integração com MCP. Em produção, as políticas precisam validar ACL e consentimento locais.
 */
export class MemoryVaultStore {
  readonly #root: string;
  readonly #approval: MemoryApprovalPolicy;
  readonly #security: MemoryVaultSecurityPolicy;
  readonly #pending = new WeakMap<
    object,
    {
      draft: MemoryDraft;
      proposal: MemoryProposal;
      path: string;
      expectedHash: string | null;
      markdown: string;
    }
  >();
  readonly #receipts = new WeakMap<object, { proposal: MemoryProposal; expiresAt: number }>();
  readonly #applied = new Map<string, string>();

  constructor(root: string, approval: MemoryApprovalPolicy, security: MemoryVaultSecurityPolicy) {
    if (!path.isAbsolute(root)) throw new MemoryError("INVALID_INPUT");
    this.#root = path.resolve(root);
    this.#approval = approval;
    this.#security = security;
  }

  async propose(draft: MemoryDraft, expectedRevision?: number): Promise<MemoryProposal> {
    this.#validateDraft(draft);
    const notePath = await this.#notePath(draft);
    const current = await this.#readExisting(notePath);
    const expected = current?.entity.revision ?? null;
    if (expectedRevision !== undefined && expectedRevision !== expected)
      throw new MemoryError("CONFLICT");
    if (current && current.entity.id !== draft.id) throw new MemoryError("CONFLICT");
    if (current && current.entity.type !== draft.type) throw new MemoryError("CONFLICT");
    if (current && current.entity.projectId !== draft.projectId) throw new MemoryError("CONFLICT");
    const now = new Date().toISOString();
    const status = draft.status ?? current?.entity.status;
    const missionCode = draft.missionCode ?? current?.entity.missionCode;
    const parentMissionId = draft.parentMissionId ?? current?.entity.parentMissionId;
    const objective = draft.objective ?? current?.entity.objective;
    const scope = draft.scope ?? current?.entity.scope;
    const acceptanceCriteria = draft.acceptanceCriteria ?? current?.entity.acceptanceCriteria;
    const priority = draft.priority ?? current?.entity.priority;
    const dependencies = draft.dependencies ?? current?.entity.dependencies;
    const results = draft.results ?? current?.entity.results;
    const problems = draft.problems ?? current?.entity.problems;
    const attempts = draft.attempts ?? current?.entity.attempts;
    const corrections = draft.corrections ?? current?.entity.corrections;
    const evidenceIds = draft.evidenceIds ?? current?.entity.evidenceIds;
    const commitIds = draft.commitIds ?? current?.entity.commitIds;
    const decisionIds = draft.decisionIds ?? current?.entity.decisionIds;
    const nextSteps = draft.nextSteps ?? current?.entity.nextSteps;
    const statusHistory = [
      ...(current?.entity.statusHistory ?? []),
      ...(draft.status && draft.status !== current?.entity.status
        ? [
            {
              from: current?.entity.status ?? null,
              to: draft.status,
              changedAt: now,
              source: draft.source
            }
          ]
        : [])
    ];
    const operationId = createHash("sha256").update(stableJson(draft)).digest("hex");
    if (current?.entity.appliedOperationIds?.includes(operationId)) {
      const proposal: MemoryProposal = Object.freeze({
        operationId,
        operation: "noop",
        projectId: draft.projectId,
        noteId: draft.id,
        entityType: draft.type,
        fields: Object.freeze([]),
        beforeRevision: expected,
        afterRevision: expected!,
        relations: Object.freeze([]),
        source: draft.source,
        previewMarkdown: serialize(current.entity)
      });
      this.#pending.set(proposal, {
        draft,
        proposal,
        path: notePath,
        expectedHash: current.hash,
        markdown: serialize(current.entity)
      });
      return proposal;
    }
    const body = current
      ? `${current.entity.body.trimEnd()}\n\n## Revisão ${current.entity.revision + 1}\n\n${draft.body}`
      : draft.body;
    const claims = [
      ...(current?.entity.claims ?? []),
      ...(draft.claims ?? [
        { text: draft.body, source: draft.source, evidenceIds: [], verified: false }
      ])
    ];
    const relations: MemoryRelation[] = [
      ...(current?.entity.relations ?? []),
      ...(draft.relations ?? []).filter(
        (candidate) =>
          !current?.entity.relations.some(
            (existing) =>
              existing.type === candidate.type &&
              existing.targetId === candidate.targetId &&
              existing.source === candidate.source
          )
      )
    ];
    const entity: MemoryEntity = {
      schemaVersion: 1,
      id: draft.id,
      type: draft.type,
      projectId: draft.projectId,
      title: draft.title,
      createdAt: current?.entity.createdAt ?? now,
      updatedAt: now,
      revision: (expected ?? 0) + 1,
      appliedOperationIds: [
        ...(current?.entity.appliedOperationIds ?? []).filter((id) => id !== operationId),
        operationId
      ].slice(-256),
      relations,
      claims,
      body,
      ...(status ? { status } : {}),
      ...(missionCode ? { missionCode } : {}),
      ...(parentMissionId ? { parentMissionId } : {}),
      ...(objective !== undefined ? { objective } : {}),
      ...(scope !== undefined ? { scope } : {}),
      ...(acceptanceCriteria !== undefined ? { acceptanceCriteria } : {}),
      ...(priority !== undefined ? { priority } : {}),
      ...(dependencies !== undefined ? { dependencies } : {}),
      ...(results !== undefined ? { results } : {}),
      ...(problems !== undefined ? { problems } : {}),
      ...(attempts !== undefined ? { attempts } : {}),
      ...(corrections !== undefined ? { corrections } : {}),
      ...(evidenceIds !== undefined ? { evidenceIds } : {}),
      ...(commitIds !== undefined ? { commitIds } : {}),
      ...(decisionIds !== undefined ? { decisionIds } : {}),
      ...(nextSteps !== undefined ? { nextSteps } : {}),
      ...(status ? { statusHistory } : {})
    };
    const markdown = serialize(entity);
    const proposal: MemoryProposal = Object.freeze({
      operationId,
      operation: current ? "update" : "create",
      projectId: draft.projectId,
      noteId: draft.id,
      entityType: draft.type,
      fields: Object.freeze(["title", "body", "claims", "relations", "status"]),
      beforeRevision: expected,
      afterRevision: entity.revision,
      relations: Object.freeze([...(draft.relations ?? [])]),
      source: draft.source,
      previewMarkdown: markdown
    });
    this.#pending.set(proposal, {
      draft,
      proposal,
      path: notePath,
      expectedHash: current?.hash ?? null,
      markdown
    });
    return proposal;
  }

  async approve(proposal: MemoryProposal): Promise<MemoryApprovalReceipt> {
    if (!this.#pending.has(proposal)) throw new MemoryError("DENIED");
    const result = await this.#approval.approve(proposal);
    const expiry = Date.parse(result.expiresAt);
    if (
      !result.approved ||
      result.source === "untrusted" ||
      result.operationId !== proposal.operationId ||
      !Number.isFinite(expiry) ||
      expiry <= Date.now()
    ) {
      throw new MemoryError(expiry <= Date.now() ? "EXPIRED" : "DENIED");
    }
    const receipt = Object.freeze({
      operationId: proposal.operationId,
      expiresAt: result.expiresAt
    });
    this.#receipts.set(receipt, { proposal, expiresAt: expiry });
    return receipt;
  }

  async apply(receipt: MemoryApprovalReceipt): Promise<MemoryEntity> {
    const approved = this.#receipts.get(receipt);
    const pending = approved ? this.#pending.get(approved.proposal) : undefined;
    if (!approved || !pending || receipt.operationId !== approved.proposal.operationId)
      throw new MemoryError("DENIED");
    if (approved.expiresAt <= Date.now()) throw new MemoryError("EXPIRED");
    const previous = this.#applied.get(receipt.operationId);
    if (previous) return parseEntity(previous);
    if (!(await this.#security.verifyVault(this.#root))) throw new MemoryError("VAULT_UNAVAILABLE");
    const parent = path.dirname(pending.path);
    await this.#prepareParent(parent);
    if (!(await this.#security.verifyManagedDirectory(parent))) throw new MemoryError("DENIED");
    await this.#assertContainedAndSafe(pending.path);
    const current = await this.#readExisting(pending.path);
    if ((current?.hash ?? null) !== pending.expectedHash) throw new MemoryError("CONFLICT");
    if (pending.proposal.operation === "noop" && current) return current.entity;
    const entity = parseEntity(pending.markdown);
    const tempPath = path.join(parent, `.${entity.id}.${randomUUID()}.tmp`);
    let temporaryCreated = false;
    try {
      const handle = await open(tempPath, "wx", 0o600);
      temporaryCreated = true;
      try {
        if (!(await this.#security.verifyManagedFile(tempPath))) throw new MemoryError("DENIED");
        await handle.writeFile(pending.markdown, { encoding: "utf8" });
        await handle.sync();
      } finally {
        await handle.close();
      }
      await this.#assertContainedAndSafe(tempPath);
      // Create is exclusive; update uses a short-lived cooperative lock plus hash recheck.
      if (pending.expectedHash === null) {
        await link(tempPath, pending.path);
      } else {
        const lockPath = `${pending.path}.nodaris-lock`;
        let lock;
        try {
          lock = await open(lockPath, "wx", 0o600);
        } catch {
          throw new MemoryError("CONFLICT");
        }
        try {
          const latest = await this.#readExisting(pending.path);
          if (latest?.hash !== pending.expectedHash) throw new MemoryError("CONFLICT");
          await rename(tempPath, pending.path);
          temporaryCreated = false;
        } finally {
          await lock.close();
          await rm(lockPath, { force: true });
        }
      }
      if (temporaryCreated) {
        await unlink(tempPath);
        temporaryCreated = false;
      }
      const persisted = await this.#readExisting(pending.path);
      if (
        !persisted ||
        persisted.hash !== createHash("sha256").update(pending.markdown).digest("hex")
      ) {
        throw new MemoryError("IO_FAILURE");
      }
      this.#applied.set(receipt.operationId, pending.markdown);
      return persisted.entity;
    } catch (error) {
      if (temporaryCreated) await rm(tempPath, { force: true }).catch(() => undefined);
      if (error instanceof MemoryError) throw error;
      throw new MemoryError("IO_FAILURE");
    }
  }

  async createProject(draft: Omit<MemoryDraft, "type">): Promise<MemoryProposal> {
    return this.propose({ ...draft, type: "Project" });
  }

  async createMission(draft: Omit<MemoryDraft, "type">): Promise<MemoryProposal> {
    return this.propose({ ...draft, type: "Mission" });
  }

  async createSubmission(draft: Omit<MemoryDraft, "type">): Promise<MemoryProposal> {
    return this.propose({ ...draft, type: "Mission" });
  }

  async recordEvent(draft: Omit<MemoryDraft, "type">): Promise<MemoryProposal> {
    return this.propose({ ...draft, type: "MissionEvent" });
  }

  async proposeState(
    id: string,
    projectId: string,
    title: string,
    status: MissionStatus,
    body: string,
    source: MemoryDraft["source"],
    expectedRevision: number
  ): Promise<MemoryProposal> {
    const existing = await this.getById(projectId, id, "Mission");
    return this.propose(
      {
        id,
        projectId,
        type: "Mission",
        title,
        body,
        status,
        source,
        relations: existing.relations,
        claims: [{ text: body, source, evidenceIds: [], verified: false }],
        ...(existing.objective ? { objective: existing.objective } : {}),
        ...(existing.scope ? { scope: existing.scope } : {}),
        ...(existing.acceptanceCriteria ? { acceptanceCriteria: existing.acceptanceCriteria } : {}),
        ...(existing.priority ? { priority: existing.priority } : {}),
        ...(existing.dependencies ? { dependencies: existing.dependencies } : {}),
        ...(existing.results ? { results: existing.results } : {}),
        ...(existing.problems ? { problems: existing.problems } : {}),
        ...(existing.attempts ? { attempts: existing.attempts } : {}),
        ...(existing.corrections ? { corrections: existing.corrections } : {}),
        ...(existing.evidenceIds ? { evidenceIds: existing.evidenceIds } : {}),
        ...(existing.commitIds ? { commitIds: existing.commitIds } : {}),
        ...(existing.decisionIds ? { decisionIds: existing.decisionIds } : {}),
        ...(existing.nextSteps ? { nextSteps: existing.nextSteps } : {}),
        ...(existing.missionCode ? { missionCode: existing.missionCode } : {}),
        ...(existing.parentMissionId ? { parentMissionId: existing.parentMissionId } : {})
      },
      expectedRevision
    );
  }

  async createRecord(draft: MemoryDraft): Promise<MemoryProposal> {
    if (["Project", "Mission", "MissionEvent"].includes(draft.type))
      throw new MemoryError("INVALID_INPUT");
    return this.propose(draft);
  }

  async getById(projectId: string, id: string, type: MemoryEntity["type"]): Promise<MemoryEntity> {
    if (!validId(projectId) || !validId(id)) throw new MemoryError("INVALID_INPUT");
    const notePath = await this.#pathFor(projectId, id, type);
    const loaded = await this.#readExisting(notePath);
    if (!loaded) throw new MemoryError("NOT_FOUND");
    if (
      loaded.entity.projectId !== projectId ||
      loaded.entity.id !== id ||
      loaded.entity.type !== type
    )
      throw new MemoryError("CORRUPT_NOTE");
    return loaded.entity;
  }

  async listMissions(projectId: string): Promise<readonly MemoryEntity[]> {
    const directory = await this.#safeDirectory(projectId, "Missions", false, true);
    let entries;
    try {
      entries = await (
        await import("node:fs/promises")
      ).readdir(directory, { withFileTypes: true });
    } catch {
      return [];
    }
    const missions: MemoryEntity[] = [];
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".md")) continue;
      const id = entry.name.slice(0, -3);
      if (!validId(id)) continue;
      try {
        missions.push(await this.getById(projectId, id, "Mission"));
      } catch {
        /* Corrupt note is omitted, never interpreted. */
      }
    }
    return missions.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  async eventHistory(projectId: string, missionId: string): Promise<readonly MemoryEntity[]> {
    const directory = await this.#safeDirectory(projectId, "Sessions", false, true);
    let entries;
    try {
      entries = await (
        await import("node:fs/promises")
      ).readdir(directory, { withFileTypes: true });
    } catch {
      return [];
    }
    const events: MemoryEntity[] = [];
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".md") || !validId(entry.name.slice(0, -3)))
        continue;
      try {
        const event = await this.getById(projectId, entry.name.slice(0, -3), "MissionEvent");
        if (event.relations.some((relation) => relation.targetId === missionId)) events.push(event);
      } catch {
        /* Ignore notes of other session types and malformed notes. */
      }
    }
    return events.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }

  async continuitySummary(projectId: string): Promise<string> {
    const missions = await this.listMissions(projectId);
    const recent = missions.slice(0, 12).map((mission) => {
      const claims = mission.claims
        .map(
          (claim) =>
            `- ${claim.verified ? "Verificado" : "Relatado"} (${claim.source}): ${claim.text}`
        )
        .join("\n");
      return `## ${mission.missionCode ?? mission.id}: ${mission.title} — ${mission.status ?? "sem estado"}\n${claims}`;
    });
    return [`# Continuidade ${projectId}`, "", ...recent].join("\n");
  }

  async #notePath(draft: MemoryDraft): Promise<string> {
    const directory = await this.#safeDirectory(draft.projectId, CATEGORY[draft.type], false, true);
    return path.join(directory, filenameFor(draft.id, draft.type));
  }

  async #pathFor(projectId: string, id: string, type: MemoryEntity["type"]): Promise<string> {
    const directory = await this.#safeDirectory(projectId, CATEGORY[type], false, false);
    return path.join(directory, filenameFor(id, type));
  }

  async #safeDirectory(
    projectId: string,
    category: string,
    _create: boolean,
    allowMissing: boolean
  ): Promise<string> {
    if (!validId(projectId)) throw new MemoryError("INVALID_INPUT");
    const rootReal = await realpath(this.#root).catch(() => {
      throw new MemoryError("VAULT_UNAVAILABLE");
    });
    const rootStat = await lstat(this.#root).catch(() => {
      throw new MemoryError("VAULT_UNAVAILABLE");
    });
    if (rootStat.isSymbolicLink() || !rootStat.isDirectory() || rootReal !== this.#root)
      throw new MemoryError("UNSAFE_PATH");
    if (!(await this.#security.verifyVault(rootReal))) throw new MemoryError("VAULT_UNAVAILABLE");
    const projectPath = path.join(rootReal, PROJECTS_DIR, slug(projectId));
    const parts = category
      ? [PROJECTS_DIR, slug(projectId), category]
      : [PROJECTS_DIR, slug(projectId)];
    let current = rootReal;
    for (let index = 0; index < parts.length; index += 1) {
      current = path.join(current, parts[index]!);
      let stat;
      try {
        stat = await lstat(current);
      } catch {
        if (allowMissing) {
          current = path.join(current, ...parts.slice(index + 1));
          break;
        }
        throw new MemoryError("NOT_FOUND");
      }
      if (!stat.isDirectory() || stat.isSymbolicLink()) throw new MemoryError("UNSAFE_PATH");
      if ((await realpath(current).catch(() => "")) !== current)
        throw new MemoryError("UNSAFE_PATH");
      if (!(await this.#security.verifyManagedDirectory(current))) throw new MemoryError("DENIED");
    }
    if (!projectPath.startsWith(rootReal + path.sep)) throw new MemoryError("OUTSIDE_VAULT");
    return current;
  }

  async #prepareParent(parent: string): Promise<void> {
    const relative = path.relative(this.#root, parent);
    if (!relative || relative.startsWith("..") || path.isAbsolute(relative))
      throw new MemoryError("OUTSIDE_VAULT");
    let current = this.#root;
    for (const segment of relative.split(path.sep)) {
      if (!segment || segment === "." || segment === ".." || segment.includes(":"))
        throw new MemoryError("UNSAFE_PATH");
      current = path.join(current, segment);
      let exists = true;
      try {
        await lstat(current);
      } catch {
        exists = false;
      }
      if (!exists && !(await this.#security.prepareManagedDirectory(current)))
        throw new MemoryError("DENIED");
      const stat = await lstat(current).catch(() => {
        throw new MemoryError("IO_FAILURE");
      });
      if (
        !stat.isDirectory() ||
        stat.isSymbolicLink() ||
        (await realpath(current).catch(() => "")) !== current
      )
        throw new MemoryError("UNSAFE_PATH");
      if (!(await this.#security.verifyManagedDirectory(current))) throw new MemoryError("DENIED");
    }
  }

  async #assertContainedAndSafe(filePath: string): Promise<void> {
    const relative = path.relative(this.#root, filePath);
    if (
      !relative ||
      relative.startsWith("..") ||
      path.isAbsolute(relative) ||
      relative.includes(":")
    )
      throw new MemoryError("OUTSIDE_VAULT");
    for (const segment of relative.split(path.sep)) {
      if (!segment || segment === "." || segment === ".." || segment.includes(":"))
        throw new MemoryError("UNSAFE_PATH");
    }
    const parent = path.dirname(filePath);
    if ((await realpath(parent).catch(() => "")) !== parent) throw new MemoryError("UNSAFE_PATH");
    try {
      const stat = await lstat(filePath);
      if (stat.isSymbolicLink() || !stat.isFile() || stat.nlink > 1)
        throw new MemoryError("UNSAFE_PATH");
    } catch (error) {
      if (error instanceof MemoryError) throw error;
      // A missing destination is valid for create; apply rechecks revision before writing.
    }
  }

  async #readExisting(filePath: string): Promise<{ entity: MemoryEntity; hash: string } | null> {
    try {
      if ((await realpath(path.dirname(filePath)).catch(() => null)) === null) return null;
      await this.#assertContainedAndSafe(filePath);
      const metadata = await lstat(filePath);
      if (metadata.size > MAX_NOTE_BYTES) throw new MemoryError("CORRUPT_NOTE");
      const bytes = await readFile(filePath);
      if (bytes.byteLength > MAX_NOTE_BYTES) throw new MemoryError("CORRUPT_NOTE");
      const text = bytes.toString("utf8");
      return { entity: parseEntity(text), hash: createHash("sha256").update(bytes).digest("hex") };
    } catch (error) {
      if (error instanceof MemoryError && error.code === "UNSAFE_PATH") throw error;
      if (error instanceof MemoryError && error.code === "CORRUPT_NOTE") throw error;
      return null;
    }
  }

  #validateDraft(draft: MemoryDraft): void {
    if (
      !draft ||
      !validId(draft.id) ||
      !validId(draft.projectId) ||
      !safeText(draft.title, 300) ||
      !draft.title.trim() ||
      !safeText(draft.body)
    )
      throw new MemoryError("INVALID_INPUT");
    if (
      !draft.type ||
      ![
        "Project",
        "Mission",
        "MissionEvent",
        "Bug",
        "Finding",
        "Attempt",
        "Decision",
        "Proposal",
        "Experiment",
        "Evidence",
        "TestResult",
        "CommitReference",
        "ProjectSnapshot",
        "MemorySession"
      ].includes(draft.type) ||
      !draft.source ||
      !CLAIM_SOURCES.includes(draft.source) ||
      (draft.relations?.length ?? 0) > 100 ||
      draft.relations?.some(
        (relation) =>
          !validId(relation.targetId) ||
          !relation.type ||
          typeof relation.inferred !== "boolean" ||
          !CLAIM_SOURCES.includes(relation.source) ||
          relation.evidenceIds.some((id) => !validId(id))
      ) ||
      (draft.claims?.length ?? 0) > 100 ||
      draft.claims?.some(
        (claim) =>
          !safeText(claim.text) ||
          !CLAIM_SOURCES.includes(claim.source) ||
          typeof claim.verified !== "boolean" ||
          claim.evidenceIds.some((id) => !validId(id))
      )
    )
      throw new MemoryError("INVALID_INPUT");
    for (const id of [
      draft.parentMissionId,
      ...(draft.dependencies ?? []),
      ...(draft.evidenceIds ?? []),
      ...(draft.commitIds ?? []),
      ...(draft.decisionIds ?? [])
    ]) {
      if (id !== undefined && !validId(id)) throw new MemoryError("INVALID_INPUT");
    }
    for (const values of [
      draft.scope,
      draft.acceptanceCriteria,
      draft.problems,
      draft.attempts,
      draft.corrections,
      draft.nextSteps
    ]) {
      if (values && (values.length > 100 || values.some((value) => !safeText(value, 2_000))))
        throw new MemoryError("INVALID_INPUT");
    }
    if (
      draft.missionCode &&
      !/^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)?(?:\.[A-Za-z0-9]+(?:-[A-Za-z0-9]+)?)*$/.test(
        draft.missionCode
      )
    )
      throw new MemoryError("INVALID_INPUT");
  }
}

export function isTerminalMissionStatus(status: MissionStatus): boolean {
  return TERMINAL_STATUSES.includes(status);
}
