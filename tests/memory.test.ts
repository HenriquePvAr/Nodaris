// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import {
  link as createHardLink,
  mkdtemp,
  mkdir,
  readFile,
  rm,
  stat,
  symlink,
  writeFile
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { MemoryVaultStore } from "../packages/core/src/memory/store.js";
import type {
  MemoryApprovalPolicy,
  MemoryProposal,
  MemoryVaultSecurityPolicy
} from "../packages/core/src/memory/types.js";

const vaults: string[] = [];

async function createVault() {
  const root = await mkdtemp(path.join(os.tmpdir(), "nodaris-memory-test-"));
  vaults.push(root);
  const approval: MemoryApprovalPolicy = {
    async approve(proposal: MemoryProposal) {
      return {
        approved: true,
        operationId: proposal.operationId,
        expiresAt: new Date(Date.now() + 60_000).toISOString(),
        source: "isolated_test"
      };
    }
  };
  const security: MemoryVaultSecurityPolicy = {
    async verifyVault(candidate) {
      return candidate === root;
    },
    async verifyManagedDirectory(candidate) {
      return candidate === root || candidate.startsWith(root + path.sep);
    },
    async prepareManagedDirectory(candidate) {
      if (!(candidate === root || candidate.startsWith(root + path.sep))) return false;
      await mkdir(candidate, { mode: 0o700 });
      return true;
    },
    async verifyManagedFile(candidate) {
      return candidate.startsWith(root + path.sep);
    }
  };
  return { root, approval, security, store: new MemoryVaultStore(root, approval, security) };
}

afterEach(async () => {
  await Promise.all(vaults.splice(0).map((vault) => rm(vault, { recursive: true, force: true })));
});

describe("writer Markdown de memória em vault temporário", () => {
  it("cria projeto, missões, submissão, eventos e recupera continuidade em nova sessão", async () => {
    const fixture = await createVault();
    const save = async (proposal: MemoryProposal) =>
      fixture.store.apply(await fixture.store.approve(proposal));
    await save(
      await fixture.store.createProject({
        id: "Nodaris",
        projectId: "Nodaris",
        title: "Nodaris",
        body: "Agente local MCP",
        source: "owner_confirmation"
      })
    );
    await save(
      await fixture.store.createMission({
        id: "WIN-01",
        projectId: "Nodaris",
        title: "Windows Home MVP",
        missionCode: "WIN-01",
        body: "Preflight e plano.",
        status: "IN_PROGRESS",
        source: "codex_report"
      })
    );
    await save(
      await fixture.store.createMission({
        id: "MEM-01",
        projectId: "Nodaris",
        title: "Memory MVP",
        missionCode: "MEM-01",
        body: "Writer de fixture.",
        status: "IN_PROGRESS",
        source: "codex_report"
      })
    );
    await save(
      await fixture.store.createSubmission({
        id: "MEM-01.1",
        projectId: "Nodaris",
        title: "Persistência",
        missionCode: "MEM-01.1",
        parentMissionId: "MEM-01",
        body: "Implementação de notas.",
        status: "COMPLETED",
        source: "test_observation"
      })
    );
    const failedAttempt = await fixture.store.createRecord({
      id: "attempt-1",
      projectId: "Nodaris",
      type: "Attempt",
      title: "Primeira tentativa",
      body: "Falhou por conflito de revisão.",
      source: "test_observation",
      relations: [
        {
          type: "ATTEMPT_FAILED_BECAUSE",
          targetId: "bug-1",
          source: "test_observation",
          inferred: false,
          evidenceIds: []
        }
      ]
    });
    await save(failedAttempt);
    const bug = await fixture.store.createRecord({
      id: "bug-1",
      projectId: "Nodaris",
      type: "Bug",
      title: "Revisão obsoleta",
      body: "A gravação é recusada.",
      source: "test_observation"
    });
    await save(bug);
    const finding = await fixture.store.createRecord({
      id: "finding-1",
      projectId: "Nodaris",
      type: "Finding",
      title: "Correção",
      body: "Atualizar a revisão esperada.",
      source: "test_observation",
      relations: [
        {
          type: "FINDING_RELATES_TO",
          targetId: "bug-1",
          source: "test_observation",
          inferred: false,
          evidenceIds: []
        }
      ]
    });
    await save(finding);
    await save(
      await fixture.store.createRecord({
        id: "decision-1",
        projectId: "Nodaris",
        type: "Decision",
        title: "Frontmatter JSON/YAML",
        body: "Usar JSON como subconjunto YAML para evitar injeção de chaves.",
        source: "test_observation",
        relations: [
          {
            type: "EVIDENCE_SUPPORTS",
            targetId: "finding-1",
            source: "test_observation",
            inferred: false,
            evidenceIds: []
          }
        ]
      })
    );
    let mission = await fixture.store.getById("Nodaris", "MEM-01", "Mission");
    await save(
      await fixture.store.propose({
        id: mission.id,
        projectId: mission.projectId,
        type: "Mission",
        title: mission.title,
        body: mission.body,
        source: "test_observation",
        ...(mission.missionCode ? { missionCode: mission.missionCode } : {}),
        relations: [
          {
            type: "MISSION_RESOLVES_BUG",
            targetId: "bug-1",
            source: "test_observation",
            inferred: false,
            evidenceIds: []
          }
        ]
      })
    );
    mission = await fixture.store.getById("Nodaris", "MEM-01", "Mission");
    const state = await fixture.store.proposeState(
      "MEM-01",
      "Nodaris",
      mission.title,
      "PARTIAL",
      "Persistência fixture validada.",
      "test_observation",
      mission.revision
    );
    await save(state);
    await save(
      await fixture.store.recordEvent({
        id: "event-1",
        projectId: "Nodaris",
        title: "Transição",
        body: "Estado atualizado após aprovação isolada.",
        source: "test_observation",
        relations: [
          {
            type: "EVIDENCE_SUPPORTS",
            targetId: "MEM-01",
            source: "test_observation",
            inferred: false,
            evidenceIds: []
          }
        ]
      })
    );

    const missionPath = path.join(fixture.root, "Projects", "Nodaris", "Missions", "MEM-01.md");
    const savedMarkdown = await readFile(missionPath, "utf8");
    expect(savedMarkdown).toContain('"status": "PARTIAL"');
    expect(savedMarkdown).toContain("---");
    expect(
      (await fixture.store.eventHistory("Nodaris", "MEM-01")).map((event) => event.id)
    ).toContain("event-1");

    // Sessão B é uma instância nova e recupera apenas do Markdown persistido.
    const sessionB = new MemoryVaultStore(fixture.root, fixture.approval, fixture.security);
    const reopened = await sessionB.getById("Nodaris", "MEM-01", "Mission");
    expect(reopened.status).toBe("PARTIAL");
    expect(reopened.claims.at(-1)?.source).toBe("test_observation");
    expect(reopened.statusHistory).toHaveLength(2);
    expect(reopened.body).toContain("Writer de fixture.");
    expect(await sessionB.continuitySummary("Nodaris")).toContain("MEM-01");
    expect(await sessionB.getById("Nodaris", "MEM-01.1", "Mission")).toMatchObject({
      parentMissionId: "MEM-01"
    });
    expect(reopened.relations).toContainEqual(
      expect.objectContaining({ type: "MISSION_RESOLVES_BUG", targetId: "bug-1" })
    );
    expect((await sessionB.getById("Nodaris", "decision-1", "Decision")).relations).toHaveLength(1);
  });

  it("preview não escreve e aplicação idempotente preserva uma nota", async () => {
    const fixture = await createVault();
    const proposal = await fixture.store.createProject({
      id: "Nodaris",
      projectId: "Nodaris",
      title: "Projeto",
      body: "Fixture",
      source: "owner_confirmation"
    });
    expect(await stat(path.join(fixture.root, "Projects")).catch(() => null)).toBeNull();
    const receipt = await fixture.store.approve(proposal);
    const first = await fixture.store.apply(receipt);
    const second = await fixture.store.apply(receipt);
    expect(second.id).toBe(first.id);
    const secondSession = new MemoryVaultStore(fixture.root, fixture.approval, fixture.security);
    const replay = await secondSession.createProject({
      id: "Nodaris",
      projectId: "Nodaris",
      title: "Projeto",
      body: "Fixture",
      source: "owner_confirmation"
    });
    expect(replay.operation).toBe("noop");
    expect((await secondSession.apply(await secondSession.approve(replay))).revision).toBe(
      first.revision
    );
    expect(
      await readFile(path.join(fixture.root, "Projects", "Nodaris", "PROJECT.md"), "utf8")
    ).toBe(proposal.previewMarkdown);
  });

  it("nega aprovação fabricada, expirada, não confiável e caminho traversal", async () => {
    const fixture = await createVault();
    const proposal = await fixture.store.createProject({
      id: "Nodaris",
      projectId: "Nodaris",
      title: "Projeto",
      body: "Fixture",
      source: "codex_report"
    });
    await expect(
      fixture.store.apply({
        operationId: proposal.operationId,
        expiresAt: new Date(Date.now() + 60_000).toISOString()
      })
    ).rejects.toMatchObject({ code: "DENIED" });
    const expiredPolicy: MemoryApprovalPolicy = {
      async approve(value) {
        return {
          approved: true,
          operationId: value.operationId,
          expiresAt: new Date(0).toISOString(),
          source: "isolated_test"
        };
      }
    };
    const expiredStore = new MemoryVaultStore(fixture.root, expiredPolicy, fixture.security);
    const expiredProposal = await expiredStore.createProject({
      id: "Other",
      projectId: "Other",
      title: "Projeto",
      body: "Fixture",
      source: "codex_report"
    });
    await expect(expiredStore.approve(expiredProposal)).rejects.toMatchObject({ code: "EXPIRED" });
    const untrustedPolicy: MemoryApprovalPolicy = {
      async approve(value) {
        return {
          approved: true,
          operationId: value.operationId,
          expiresAt: new Date(Date.now() + 60_000).toISOString(),
          source: "untrusted"
        };
      }
    };
    const untrustedStore = new MemoryVaultStore(fixture.root, untrustedPolicy, fixture.security);
    const untrustedProposal = await untrustedStore.createProject({
      id: "Third",
      projectId: "Third",
      title: "Projeto",
      body: "Fixture",
      source: "codex_report"
    });
    await expect(untrustedStore.approve(untrustedProposal)).rejects.toMatchObject({
      code: "DENIED"
    });
    await expect(
      fixture.store.createProject({
        id: "../outside",
        projectId: "Nodaris",
        title: "Escape",
        body: "x",
        source: "codex_report"
      })
    ).rejects.toMatchObject({ code: "INVALID_INPUT" });
  });

  it("detecta revisão concorrente e preserva a nota anterior diante de falha", async () => {
    const fixture = await createVault();
    const original = await fixture.store.createProject({
      id: "Nodaris",
      projectId: "Nodaris",
      title: "Projeto",
      body: "Original",
      source: "owner_confirmation"
    });
    await fixture.store.apply(await fixture.store.approve(original));
    const notePath = path.join(fixture.root, "Projects", "Nodaris", "PROJECT.md");
    const originalText = await readFile(notePath, "utf8");
    const update = await fixture.store.propose(
      {
        id: "Nodaris",
        projectId: "Nodaris",
        type: "Project",
        title: "Projeto",
        body: "Atualizado",
        source: "codex_report"
      },
      1
    );
    const editedByHuman = originalText.replace("Original", "Nota humana");
    await writeFile(notePath, editedByHuman, "utf8");
    await expect(fixture.store.apply(await fixture.store.approve(update))).rejects.toMatchObject({
      code: "CONFLICT"
    });
    expect(await readFile(notePath, "utf8")).toBe(editedByHuman);
    expect((await stat(notePath)).isFile()).toBe(true);

    let allowFileSecurity = true;
    const guardedSecurity: MemoryVaultSecurityPolicy = {
      async verifyVault(candidate) {
        return candidate === fixture.root;
      },
      async verifyManagedDirectory(candidate) {
        return candidate === fixture.root || candidate.startsWith(fixture.root + path.sep);
      },
      async prepareManagedDirectory() {
        return false;
      },
      async verifyManagedFile(candidate) {
        return allowFileSecurity && candidate.startsWith(fixture.root + path.sep);
      }
    };
    const recoveryStore = new MemoryVaultStore(fixture.root, fixture.approval, guardedSecurity);
    const failureProposal = await recoveryStore.propose(
      {
        id: "Nodaris",
        projectId: "Nodaris",
        type: "Project",
        title: "Projeto",
        body: "Não gravar",
        source: "codex_report"
      },
      1
    );
    const failureReceipt = await recoveryStore.approve(failureProposal);
    allowFileSecurity = false;
    await expect(recoveryStore.apply(failureReceipt)).rejects.toMatchObject({
      code: "DENIED"
    });
    expect(await readFile(notePath, "utf8")).toBe(editedByHuman);
  });

  it("serializa atualizações concorrentes e preserva uma única revisão vencedora", async () => {
    const fixture = await createVault();
    const initial = await fixture.store.createProject({
      id: "Nodaris",
      projectId: "Nodaris",
      title: "Projeto",
      body: "Original",
      source: "owner_confirmation"
    });
    await fixture.store.apply(await fixture.store.approve(initial));
    const draft = (body: string) => ({
      id: "Nodaris",
      projectId: "Nodaris",
      type: "Project" as const,
      title: "Projeto",
      body,
      source: "test_observation" as const
    });
    const [left, right] = await Promise.all([
      fixture.store.propose(draft("Atualização A"), 1),
      fixture.store.propose(draft("Atualização B"), 1)
    ]);
    const [leftReceipt, rightReceipt] = await Promise.all([
      fixture.store.approve(left),
      fixture.store.approve(right)
    ]);
    const results = await Promise.allSettled([
      fixture.store.apply(leftReceipt),
      fixture.store.apply(rightReceipt)
    ]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(results.filter((result) => result.status === "rejected")).toHaveLength(1);
    const saved = await fixture.store.getById("Nodaris", "Nodaris", "Project");
    expect(saved.revision).toBe(2);
    expect(saved.body).toMatch(/Atualização [AB]/);
  });

  it("nega vault, ACL/policy ausente e destinos com extensão não Markdown", async () => {
    const fixture = await createVault();
    const denied: MemoryVaultSecurityPolicy = {
      async verifyVault() {
        return false;
      },
      async verifyManagedDirectory() {
        return false;
      },
      async prepareManagedDirectory() {
        return false;
      },
      async verifyManagedFile() {
        return false;
      }
    };
    const store = new MemoryVaultStore(fixture.root, fixture.approval, denied);
    await expect(
      store.createProject({
        id: "Nodaris",
        projectId: "Nodaris",
        title: "Projeto",
        body: "Fixture",
        source: "codex_report"
      })
    ).rejects.toMatchObject({
      code: "VAULT_UNAVAILABLE"
    });
    expect(
      () => new MemoryVaultStore("relative-vault", fixture.approval, fixture.security)
    ).toThrow();
  });

  it.each(["../outside", "note:stream", "CON", "name.", ".env"])(
    "rejeita ID ambíguo ou ADS (%s)",
    async (id) => {
      const fixture = await createVault();
      await expect(
        fixture.store.createProject({
          id,
          projectId: "Nodaris",
          title: "Inválido",
          body: "Fixture",
          source: "codex_report"
        })
      ).rejects.toMatchObject({ code: "INVALID_INPUT" });
    }
  );

  it("bloqueia junction/symlink em diretório gerenciado", async () => {
    const fixture = await createVault();
    const mission = await fixture.store.createMission({
      id: "M-1",
      projectId: "Nodaris",
      title: "Fixture",
      missionCode: "M01",
      body: "Fixture",
      source: "test_observation"
    });
    await fixture.store.apply(await fixture.store.approve(mission));
    const outside = await mkdtemp(path.join(os.tmpdir(), "nodaris-memory-outside-"));
    vaults.push(outside);
    const managed = path.join(fixture.root, "Projects", "Nodaris", "Missions");
    await rm(managed, { recursive: true, force: true });
    await symlink(outside, managed, process.platform === "win32" ? "junction" : "dir");
    await expect(fixture.store.getById("Nodaris", "M-1", "Mission")).rejects.toMatchObject({
      code: "UNSAFE_PATH"
    });
  });

  it("rejeita arquivos de nota com hardlink externo", async () => {
    const fixture = await createVault();
    const proposal = await fixture.store.createProject({
      id: "Nodaris",
      projectId: "Nodaris",
      title: "Projeto",
      body: "Fixture",
      source: "test_observation"
    });
    await fixture.store.apply(await fixture.store.approve(proposal));
    const notePath = path.join(fixture.root, "Projects", "Nodaris", "PROJECT.md");
    const outsidePath = path.join(os.tmpdir(), `nodaris-memory-hardlink-${Date.now()}.md`);
    await createHardLink(notePath, outsidePath);
    try {
      await expect(fixture.store.getById("Nodaris", "Nodaris", "Project")).rejects.toMatchObject({
        code: "UNSAFE_PATH"
      });
    } finally {
      await rm(outsidePath, { force: true });
    }
  });
});
