# Quadro do projeto

## Objetivo

Conectar ChatGPT a projetos locais explicitamente autorizados por MCP privado, com consultas somente leitura e autorização aplicada pelo agente local.

## Snapshot verificado em 13/10/2026

- Repositório oficial `HenriquePvAr/Nodaris`; branch única `main`, sincronizada antes deste registro com `origin/main`; única raiz autorizada para o ensaio M01.2: `C:\Users\Dell\Downloads\Nodaris`.
- Ambiente: Git 2.55.0.windows.4, Node 24.19.0, pnpm 12.8.1.
- Dependências base fixadas: MCP Server 2.3.1, Node adapter 2.1.1, MCP Client 2.3.1, Zod 4.6.7, TypeScript 5.9.3, Vitest 5.0.4.
- Typecheck, ESLint e Prettier passaram; `pnpm audit --json` reportou 0 vulnerabilidades.
- Testes executados entre processos com cliente MCP: 9 passaram (4 filesystem/Git e 5 integração).
- MCP Inspector 2.10.1 conectou por Streamable HTTP e listou as nove ferramentas; todas anunciaram `readOnlyHint: true`.
- Leitura, busca, árvore, Git status/log/diff, concorrência, agente offline/reconexão e bloqueios de token/caminhos externos foram exercitados em fixtures.
- Login GitHub refeito como `HenriquePvAr`; permissão ADMIN confirmada; helper Git configurado apenas localmente para este repositório.
- Commits iniciais de M01.1 enviados à `main` por push normal, atribuídos a Henrique e sem coautores.
- `tunnel-client v0.0.15` instalado localmente em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`, checksum oficial conferido e licença/SPDX preservados. Perfil `nodaris-local` aponta para o túnel existente, o runtime key e o Bearer Nodaris usam arquivos locais protegidos. Após o proprietário atualizar o TXT local, `admin tunnels get` autenticou e confirmou o ID; `doctor --explain` passou e o cliente permaneceu ativo. `/healthz`, `/readyz` e `/ui` retornaram HTTP 200; `/health?details=true` informou `control-plane: ok/polling`.
- M01.2: agente/gateway executados em `127.0.0.1:3334/3333`, allowlist exclusiva Nodaris; o agente descobriu 1 projeto. Cliente MCP real listou 9 tools e validou health, machines, projects, árvore (41 entradas), busca, leitura de README, Git status/diff/log; `.env.local`, `.git/config` e caminho absoluto externo foram negados. `pnpm test` 9/9 e typecheck passaram.
- M01.3: Bearer Nodaris e runtime key mantidos fora do repositório, em arquivos locais protegidos; o conteúdo não foi impresso, incluído em argumentos ou salvo em logs. O TXT temporário de origem ainda deve ser removido pelo proprietário.
- Em 13/10/2026, o proprietário confirmou chamadas reais do ChatGPT ao computador local pelas ferramentas `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read`, `nodaris_code_search`, `nodaris_git_status` e `nodaris_git_log`. README e busca retornaram dados locais; só Nodaris foi identificado.
- Revisão de estabilidade M01.7: os listeners estão em loopback; a tarefa de logon foi criada depois e o proprietário confirmou o primeiro reinício. Recuperação de rede segue não testada. O TXT de origem da runtime key ainda estava em Downloads.
- Verificação M01.5 desta atualização documental: `pnpm test` 9/9, `pnpm typecheck`, `pnpm lint` e `pnpm format:check` passaram.

## Frentes e estado

### M01.8 — Inicialização invisível Windows (13/10/2026)

- `AUTO_START`: PASS — após sair/entrar novamente, o proprietário confirmou ausência de janela. `LastRunTime=15:17:17`, `LastTaskResult=0`, supervisor iniciou às 15:17:45; árvore confirmou os serviços descendentes do supervisor.
- `PROCESS_RECOVERY`: PARTIAL — supervisor preparado com ordem agente → gateway → tunnel-client, mutex, fail-closed em conflito de porta e backoff limitado; recuperação/stop/restart não exercitados porque os processos estão ativos.
- `NETWORK_RECONNECT`: PENDING — health local do cliente respondeu HTTP 200; nenhuma queda/restauração foi provocada.
- `WINDOWS_RESTART`: PASS — após novo logon, a tarefa iniciou a cadeia sem janela visível; supervisor e filhos foram observados ativos, e ChatGPT consultou os dados locais. Latência de startup permanece registrada separadamente como parcial.
- `CHATGPT_REVALIDATION`: PASS — após novo logon, proprietário confirmou health, projetos, leitura de README, Git status/log e busca de código. A primeira chamada teve timeout de polling reportado; o reteste funcionou.
- `SECURITY`: PASS — raízes/binds do supervisor fixos, nove tools preservadas, ACL do Bearer/runtime key/perfil restritas a conta atual + SYSTEM; perfil corrigido de valor literal para referência `file:` protegida; lookup read-only do túnel com a chave protegida retornou sucesso. TXT temporário não foi usado nem removido.
- `TESTS`: PASS — 12/12 testes, typecheck, lint, formatação, `git diff --check` e parse PowerShell passaram; os testes cobrem o launcher, backup e distinção entre health local e polling do plano de controle.
- `STARTUP_LATENCY`: PARTIAL — supervisor iniciou 28s após `LastRunTime`; agente 2min43s depois; gateway +15s; túnel +3s. A amostra registra despacho às 15:21:01 e polling bem-sucedido às 15:29:07; primeiro poll/dispatch não foi retido. Estado anotou uma tentativa adicional do agente. Histórico operacional desabilitado, sem causa comprovável para o intervalo.
- `TUNNEL_READINESS`: PASS — telemetria às 15:29:17 reportou `ok/polling`, zero falhas consecutivas, poll com 10,6s e seis despachos concluídos. `nodaris.ps1 status` agora separa `/readyz` local da prontidão baseada em polling recente. A primeira falha não tem timestamp/log local; o reteste foi confirmado pelo proprietário.
- Nodaris Teams permanece somente ideia futura, sem implementação.

### M01.6 — Licenciamento

- Licença PolyForm Noncommercial 1.0.0 (`PolyForm-Noncommercial-1.0.0`) aplicada e registrada em `LICENSE`, `THIRD_PARTY_NOTICES.md`, `docs/legal/` e ADR-0001. Commit `3242b96` enviado à `origin/main`.
- Dependências foram inventariadas a partir do lockfile e grafo instalado; runtimes e ferramentas de desenvolvimento permanecem sob licenças próprias. Nenhum MCP novo ou código de terceiros foi incorporado.
- Validação da M01.6: typecheck, lint, formatação, `git diff --check` e 9 testes passaram.
- M01.7: tarefa de logon instalada; scripts de supervisão local preparados; validação após reinício, interrupção de serviço e queda de rede continua pendente. Nenhum serviço foi parado nesta tarefa.
- Uso comercial depende de autorização separada conforme a licença; contribuições externas requerem confirmação explícita dos termos documentados.

| Frente                  | Estado                                                                              | Próxima ação                                            |
| ----------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Fundação                | MVP local e raiz única validados; conexão real ChatGPT confirmada pelo proprietário | Executar testes de estabilidade                         |
| Filesystem/Git          | Sete ferramentas reais chamadas; leitura e busca retornaram dados locais            | Repetir após reinício e queda/restauração de rede       |
| Integração MCP          | Gateway Streamable HTTP; bearer obrigatório; ferramentas só leitura                 | Manter confirmação de isolamento                        |
| Secure MCP Tunnel       | Runtime key autenticada; processo ativo; plano de controle `ok/polling`             | Testar reconexão após indisponibilidade de rede         |
| Integrações open source | Avaliadas; nenhuma ferramenta com escrita foi exposta                               | Serena M02, MetaMCP M03, conforme decisões documentadas |
| Nodaris Teams           | Ideia futura, sem implementação                                                     | Avaliar somente após estabilização local                |

## Estados independentes M01.5

| Estado                  | Resultado | Evidência/pendência                                                                           |
| ----------------------- | --------- | --------------------------------------------------------------------------------------------- |
| LOCAL_MCP               | PASS      | Nove tools locais; README lido; token inválido negado; raiz única                             |
| TUNNEL_CONFIG           | PASS      | Perfil `nodaris-local`; `doctor --explain` passou                                             |
| TUNNEL_RUNTIME          | PASS      | API autenticada; `doctor` PASS; probes HTTP 200; health detalhado `control-plane: ok/polling` |
| CHATGPT_PLUGIN          | PASS      | Proprietário confirmou o plugin no workspace pessoal                                          |
| CHATGPT_REAL_CONNECTION | PASS      | Proprietário confirmou sete tools; README e pesquisa retornaram dados locais                  |
| WINDOWS_RESTART         | PENDING   | Sem serviço/tarefa de início automático; teste após reinício ainda não executado              |
| NETWORK_RECONNECT       | PENDING   | Polling atual observado; interrupção/restauração de internet ainda não testada                |
| CREDENTIAL_CLEANUP      | PENDING   | Cópia TXT da runtime key continua em Downloads; proprietário deve removê-la manualmente       |

## Limitações conhecidas

- Allowlist do ensaio contém exclusivamente `C:\Users\Dell\Downloads\Nodaris`, autorizado expressamente. Não adicionar outras raízes sem nova autorização.
- O gateway local usa bearer estático. A UI ChatGPT não recebe bearer arbitrário; o tunnel-client v0.0.15 injeta o header de serviço local com a conexão ChatGPT no modo sem auth individual. O proprietário aprovou provisoriamente essa identidade compartilhada para o workspace pessoal. Não remover auth como atalho.
- Node/Windows não garante proteção completa contra toda condição de corrida TOCTOU; está documentado como risco residual.
- A conta `HenriquePvAr` está autenticada. A configuração local de helper fica em `.git/config`; o Git Credential Manager global dos demais projetos não foi alterado.
- A árvore ainda mostra `?? docs/status/`; os arquivos do dashboard do usuário foram preservados sem alterações ou inclusão nos commits.

## Próximos passos

1. Proprietário remover manualmente a cópia TXT temporária da runtime key em Downloads.
2. Executar os cenários pendentes de reinício e recuperação de internet em [STABILITY_TESTS.md](guides/STABILITY_TESTS.md), sem marcar PASS antecipadamente.
3. Manter a raiz exclusiva autorizada e repetir as chamadas ChatGPT após cada cenário.
4. Não iniciar M02 antes de fechar a estabilidade M01.5.
