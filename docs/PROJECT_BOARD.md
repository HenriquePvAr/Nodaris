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
- Commits `61d23e3` e `7d3041f` enviados sem force; `origin/main` confirma `7d3041fdfa76e87206126026888800abf89f31fa`. Ambos atribuídos a Henrique, sem coautores.
- `tunnel-client v0.0.15` instalado localmente em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`, checksum oficial conferido e licença/SPDX preservados. Perfil `nodaris-local` aponta para o túnel existente, o runtime key e o Bearer Nodaris usam arquivos locais protegidos. Após o proprietário atualizar o TXT local, `admin tunnels get` autenticou e confirmou o ID; `doctor --explain` passou e o cliente permaneceu ativo com `/healthz`, `/readyz` e `/ui` retornando HTTP 200 em loopback.
- M01.2: agente/gateway executados em `127.0.0.1:3334/3333`, allowlist exclusiva Nodaris; o agente descobriu 1 projeto. Cliente MCP real listou 9 tools e validou health, machines, projects, árvore (41 entradas), busca, leitura de README, Git status/diff/log; `.env.local`, `.git/config` e caminho absoluto externo foram negados. `pnpm test` 9/9 e typecheck passaram.
- M01.3: Bearer Nodaris e runtime key mantidos fora do repositório, em arquivos locais protegidos; o conteúdo não foi impresso, incluído em argumentos ou salvo em logs. O TXT temporário de origem ainda deve ser removido pelo proprietário.
- O túnel e workspace foram criados pelo proprietário. Autenticação de controle confirmada com consulta somente leitura; o runtime está ativo localmente. O proprietário ainda precisa adicionar o túnel como servidor MCP no ChatGPT e executar chamadas reais.

## Frentes e estado

| Frente                  | Estado                                                                           | Próxima ação                                            |
| ----------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Fundação                | Implementada e validada em `main`; raiz Nodaris autorizada para M01.2            | Completar chamada real pelo cliente ChatGPT             |
| Filesystem/Git          | 9 ferramentas chamadas no projeto real autorizado; segredos/traversal bloqueados | Revalidar pelo ChatGPT depois de configurar o túnel     |
| Integração MCP          | Gateway Streamable HTTP; MCP real funciona e exige Bearer em `/mcp`              | Revalidar chamada após iniciar túnel                    |
| Secure MCP Tunnel       | Runtime key autenticada; processo ativo; endpoints locais 200                    | Proprietário adicionar o túnel no ChatGPT               |
| Integrações open source | Avaliadas; nenhuma ferramenta com escrita foi exposta                            | Serena M02, MetaMCP M03, conforme decisões documentadas |

## Estados independentes M01.3

| Estado                  | Resultado | Evidência/pendência                                                                                |
| ----------------------- | --------- | -------------------------------------------------------------------------------------------------- |
| LOCAL_MCP               | PASS      | Nove tools locais; README lido; token inválido negado; raiz única                                  |
| TUNNEL_CONFIG           | PASS      | Perfil `nodaris-local`; `doctor --explain` passou                                                  |
| TUNNEL_RUNTIME          | PASS      | `admin tunnels get` autenticado; `doctor` PASS; `/healthz`, `/readyz` e `/ui` HTTP 200 em loopback |
| CHATGPT_PLUGIN          | PENDING   | Criar/instalar manualmente após o túnel ficar pronto                                               |
| CHATGPT_REAL_CONNECTION | PENDING   | Nenhuma chamada real pelo ChatGPT                                                                  |

## Limitações conhecidas

- Allowlist do ensaio contém exclusivamente `C:\Users\Dell\Downloads\Nodaris`, autorizado expressamente. Não adicionar outras raízes sem nova autorização.
- O gateway local usa bearer estático. A UI ChatGPT não recebe bearer arbitrário; o tunnel-client v0.0.15 suporta injetá-lo por header de serviço local quando a conexão ChatGPT usa modo sem auth. Isso é uma identidade compartilhada e ainda precisa de validação e aprovação do workspace. Não remover auth como atalho.
- Node/Windows não garante proteção completa contra toda condição de corrida TOCTOU; está documentado como risco residual.
- A conta `HenriquePvAr` está autenticada. A configuração local de helper fica em `.git/config`; o Git Credential Manager global dos demais projetos não foi alterado.
- A árvore ainda mostra `?? docs/status/`; dashboard do usuário foi inspecionado somente para preparar proposta, sem alterações ou inclusão nos commits.

## Próximos passos

1. Proprietário remover manualmente o TXT temporário da runtime key em Downloads, após confirmar que o túnel segue operacional.
2. Proprietário criar/instalar o servidor MCP personalizado no ChatGPT, selecionando o túnel Nodaris e o workspace pessoal autorizado.
3. Executar no ChatGPT `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read` em `README.md` e `nodaris_git_status`; validar também a recusa de caminhos externos antes de liberar PASS ponta a ponta.
4. M02: avaliar Serena isolada somente leitura, mantendo revisão da licença GPL-3.0-or-later.
