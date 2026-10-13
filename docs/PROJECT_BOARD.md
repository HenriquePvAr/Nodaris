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
- `tunnel-client v0.0.15` oficial baixado para diretório temporário; checksum SHA-256 conferido com manifesto da release; `help quickstart` executado. Binário Windows sem Authenticode; não instalado persistentemente nem conectado.
- M01.2: agente/gateway executados em `127.0.0.1:3334/3333`, allowlist exclusiva Nodaris; o agente descobriu 1 projeto. Cliente MCP real listou 9 tools e validou health, machines, projects, árvore (41 entradas), busca, leitura de README, Git status/diff/log; `.env.local`, `.git/config` e caminho absoluto externo foram negados. `pnpm test` 9/9 e typecheck passaram.
- Token Bearer de ensaio criado fora do repositório em `%LOCALAPPDATA%\Nodaris`, ACL restrita; sem impressão, log, argumento ou inclusão em Git.
- `tunnel-client v0.0.15` instalado localmente em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`, com checksum oficial previamente conferido e licença/SPDX preservados. `help quickstart`, `help init` e `help doctor` consultados. Não foi iniciado contra a OpenAI.
- Secure MCP Tunnel ainda aguarda configuração manual do usuário na OpenAI Platform: criar/confirmar túnel, `tunnel_id`, runtime key local, permissões e workspace. ChatGPT real **BLOCKED/PENDING**; não houve chamada real.

## Frentes e estado

| Frente                  | Estado                                                                   | Próxima ação                                                                |
| ----------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| Fundação                | Implementada e validada em `main`; raiz Nodaris autorizada para M01.2    | Completar chamada real pelo cliente ChatGPT                                 |
| Filesystem/Git          | 9 ferramentas chamadas no projeto real autorizado; segredos/traversal bloqueados | Revalidar pelo ChatGPT depois de configurar o túnel                         |
| Integração MCP          | Gateway Streamable HTTP e agente separados; chamadas reais locais aprovadas | Configurar perfil, doctor e conexão ChatGPT após gate manual                 |
| Secure MCP Tunnel       | Cliente oficial v0.0.15 instalado; sem perfil/credenciais OpenAI            | Usuário configurar túnel, permissões, workspace e runtime key                |
| Integrações open source | Avaliadas; nenhuma ferramenta com escrita foi exposta                    | Serena M02, MetaMCP M03, conforme decisões documentadas                     |

## Limitações conhecidas

- Allowlist do ensaio contém exclusivamente `C:\Users\Dell\Downloads\Nodaris`, autorizado expressamente. Não adicionar outras raízes sem nova autorização.
- O gateway local usa bearer estático. A UI ChatGPT não recebe bearer arbitrário; o tunnel-client v0.0.15 suporta injetá-lo por header de serviço local quando a conexão ChatGPT usa modo sem auth. Isso é uma identidade compartilhada e ainda precisa de validação e aprovação do workspace. Não remover auth como atalho.
- Node/Windows não garante proteção completa contra toda condição de corrida TOCTOU; está documentado como risco residual.
- A conta `HenriquePvAr` está autenticada. A configuração local de helper fica em `.git/config`; o Git Credential Manager global dos demais projetos não foi alterado.
- A árvore ainda mostra `?? docs/status/`; dashboard do usuário foi inspecionado somente para preparar proposta, sem alterações ou inclusão nos commits.

## Próximos passos

1. Usuário criar/confirmar o túnel na Platform e verificar `Tunnels Read + Use`, organização e workspace pessoais; fornecer apenas o `tunnel_id` e manter a runtime key local.
2. Criar perfil, executar `tunnel-client doctor --explain`, validar health/ready e preparar o connector no ChatGPT; parar se a checagem exigir metadata OAuth/PRMD que a arquitetura ainda não oferece.
3. Usuário criar/instalar o connector e executar consulta real; exigir `nodaris_projects_list` e `nodaris_file_read` para liberar PASS ponta a ponta.
4. Atualizar a apresentação do quadro estático somente após aprovação específica do autor, preservando o HTML e IDs existentes.
5. M02: avaliar Serena isolada somente leitura, mantendo revisão da licença GPL-3.0-or-later.
