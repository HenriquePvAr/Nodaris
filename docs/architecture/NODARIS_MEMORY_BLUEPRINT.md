<!-- SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# Blueprint do Nodaris Memory MVP

## Fonte de verdade e estado da entrega

O vault Markdown é a fonte de verdade. SQLite FTS5, índices vetoriais e caches são derivados e
reconstruíveis; nenhum foi adicionado nesta etapa. A estrutura implementada pelo writer é
`Projects/<projectId>/PROJECT.md` e subpastas `Missions/`, `Bugs/`, `Findings/`, `Attempts/`,
`Decisions/`, `Proposals/`, `Experiments/`, `Evidence/` e `Sessions/`. `Shared/` e `Templates/`
podem ser adicionados em missão posterior. Os nomes de arquivo derivam de IDs estáveis, não de
títulos editáveis.

O core está em `packages/core/src/memory/`, isolado dos entrypoints M01. A serialização usa um bloco
JSON válido como subconjunto YAML 1.2 para impedir injeção de chaves no frontmatter. O Obsidian
documenta Properties como YAML frontmatter e requer nomes de propriedade únicos; o JSON usado aqui
é um subconjunto de YAML, mas a apresentação e edição das Properties ainda precisam de validação na
interface do aplicativo. A compatibilidade de UI permanece parcial. Títulos e corpos são texto não
confiável, nunca instruções executáveis. [Documentação oficial de Properties](https://obsidian.md/help/properties).

## Modelo

Tipos do schema: Project, Mission, MissionEvent, Bug, Finding, Attempt, Decision, Proposal,
Experiment, Evidence, TestResult, CommitReference, ProjectSnapshot e MemorySession. Missões têm ID,
código legível, título, estado, revisão, claims com origem e verificação, relações e submissão por
`parentMissionId`. Códigos como `M02.3B.2A` não são usados para inferir ordem temporal.

Estados: `PLANNED`, `READY`, `IN_PROGRESS`, `BLOCKED`, `PARTIAL`, `COMPLETED`, `FAILED`, `CANCELED`
e `SUPERSEDED`. Alterações são propostas com revisão esperada; conflito exige novo preview. Eventos
de missão são notas separadas, preservando tentativas e limitações após conclusão.

Cada relação declara tipo, destino, origem, `inferred` e evidências. Os tipos são
`MISSION_HAS_CHILD`, `MISSION_DEPENDS_ON`, `MISSION_RESOLVES_BUG`, `ATTEMPT_ADDRESSES_BUG`,
`ATTEMPT_FAILED_BECAUSE`, `DECISION_SUPERSEDES`, `EVIDENCE_SUPPORTS`, `TEST_VALIDATES`,
`COMMIT_IMPLEMENTS`, `PROJECT_USES`, `FINDING_RELATES_TO` e `PROPOSAL_ADDRESSES`. Claims separam
`codex_report`, `test_observation`, `git_verification`, `owner_confirmation` e
`unverified_conclusion`; uma afirmação reportada não vira fato verificado por ser persistida.

## Escrita em três fases

1. **Preview:** `propose` valida IDs e gera Markdown em memória; não escreve.
2. **Aprovação:** `approve` chama uma política injetada, exige escopo de operação, validade e origem
   diferente de `untrusted`. A composição de produção/aprovação local confiável não existe ainda;
   somente fake isolado dos testes fornece `isolated_test`.
3. **Aplicação:** `apply` exige receipt opaco emitido para aquele preview, revalida vault, diretórios,
   caminho e revisão; cria arquivo exclusivamente, ou atualiza com hash esperado, lock cooperativo e
   rename. Operação repetida com o mesmo receipt é idempotente. Conteúdo Markdown não pode escolher
   caminhos nem permissões.

O writer não é importado por agent/gateway, não concede `workspace.write.approved`, não executa shell,
Git mutável ou ferramentas MCP e não permite request definir caminho absoluto. O contrato de
segurança exige `verifyVault`, `verifyManagedDirectory` e `prepareManagedDirectory` de adaptador
local confiável. Não existe adaptador Windows de ACL nesta entrega. Portanto, não há autorização de
vault real; a integração manual/ChatGPT permanece desabilitada.

## Proteções e limitações

IDs rejeitam separadores, `..`, dois-pontos/ADS, caracteres fora do conjunto restrito e extensões
não entram no request. A resolução é derivada de categorias gerenciadas; realpath/lstat rejeitam
links simbólicos nos segmentos observados. Projetos não compartilham diretórios. O vault raiz deve
existir e ser explícito. Escrita requer política de segurança; falha ou incerteza nega.

O writer rejeita symlinks/junctions observáveis e arquivos com mais de um hardlink (`nlink > 1`), mas
isso não constitui uma proteção portátil contra toda corrida de filesystem. O Node não fornece por si
só validação portátil de ACL NTFS, detecção completa de reparse points, proteção contra todo TOCTOU
externo ou compare-and-swap atômico do Windows. O lock impede writers cooperantes, não um editor
humano que modifique o arquivo no intervalo entre hash e rename. `MemoryVaultSecurityPolicy` é uma
porta, não uma garantia: implementação real deve provar ACL privada e operações seguras ou negar.
Não usar para vault real antes de WIN-02/MEM-02.

## Continuidade e pesquisa futura

Nova sessão abre uma instância nova e lê notas persistidas; o teste não depende de cache da sessão A.
`listMissions`, `eventHistory` e `continuitySummary` entregam estado e claims com rótulo de origem.
Próxima missão MEM-02 pode criar índice SQLite FTS5 reconstruível, busca exata e ranking, filtro por
projeto/estado e expansão limitada por relações/recência/verificação. Embeddings são opcionais e
fora desta etapa.

Ferramentas futuras: `nodaris_memory_context`, `nodaris_memory_search`, `nodaris_memory_related`,
`nodaris_missions_list`, `nodaris_mission_get`. `nodaris_memory_propose_write` e
`nodaris_memory_apply_approved_write` exigem canal de aprovação local confiável e vault autorizado;
nenhuma é exposta agora.

## Roteiro

- **WIN-02:** instalação independente, identidade e credenciais novas, ACL privada, raiz explicitamente
  aprovada, túnel próprio e rollback comprovado em PC pessoal.
- **MEM-02:** adaptador de segurança/ACL real, UX local de aprovação e índice reconstruível.
- **MEM-03:** integração de leitura e, somente após revisão própria, proposta/aplicação local. Não
  herdar autorização entre dispositivos nem sincronizar dados empresariais.

O futuro piloto WIN-02 deve criar um vault Obsidian pessoal separado somente depois dos gates MEM-02
(aprovação local confiável, ACL nativa, proteção contra reparse points, backup/recuperação e
conflitos com editores). Memória fica isolada por projeto; nenhuma memória pessoal é associada a
dados corporativos por conveniência ou inferência.
