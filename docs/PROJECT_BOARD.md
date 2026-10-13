# Quadro do projeto

## Objetivo

Conectar ChatGPT a projetos locais explicitamente autorizados por MCP privado, com consultas somente leitura e autorização aplicada pelo agente local.

## Snapshot verificado em 13/10/2026

- Repositório oficial `HenriquePvAr/Nodaris`; branch única `main`, sincronizada com `origin/main` após o push da M01.1; nenhuma raiz real cadastrada.
- Ambiente: Git 2.55.0.windows.4, Node 24.19.0, pnpm 12.8.1.
- Dependências base fixadas: MCP Server 2.3.1, Node adapter 2.1.1, MCP Client 2.3.1, Zod 4.6.7, TypeScript 5.9.3, Vitest 5.0.4.
- Typecheck, ESLint e Prettier passaram; `pnpm audit --json` reportou 0 vulnerabilidades.
- Testes executados entre processos com cliente MCP: 9 passaram (4 filesystem/Git e 5 integração).
- MCP Inspector 2.10.1 conectou por Streamable HTTP e listou as nove ferramentas; todas anunciaram `readOnlyHint: true`.
- Leitura, busca, árvore, Git status/log/diff, concorrência, agente offline/reconexão e bloqueios de token/caminhos externos foram exercitados em fixtures.
- Login GitHub refeito como `HenriquePvAr`; permissão ADMIN confirmada; helper Git configurado apenas localmente para este repositório.
- Commits `61d23e3` e `7d3041f` enviados sem force; `origin/main` confirma `7d3041fdfa76e87206126026888800abf89f31fa`. Ambos atribuídos a Henrique, sem coautores.
- `tunnel-client v0.0.15` oficial baixado para diretório temporário; checksum SHA-256 conferido com manifesto da release; `help quickstart` executado. Binário Windows sem Authenticode; não instalado persistentemente nem conectado.
- Secure MCP Tunnel ainda não configurado/testado. Uma rota para preservar o Bearer do Nodaris via `mcp.extra_headers` do tunnel-client foi identificada; conexão real segue **BLOCKED** por falta de `tunnel_id`, runtime key, permissões/associação e aprovação da raiz.

## Frentes e estado

| Frente                  | Estado                                                                   | Próxima ação                                                                |
| ----------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| Fundação                | Implementada, validada, commitada e sincronizada em `main`               | Aprovar uma raiz de projeto e validar pelo cliente ChatGPT                  |
| Filesystem/Git          | Ferramentas Nodaris somente leitura; testes em fixtures aprovados        | Aguardar autorização explícita para a raiz Nodaris                          |
| Integração MCP          | Gateway Streamable HTTP e agente separados; Inspector listou ferramentas | Testar via tunnel-client e ChatGPT após os gates                            |
| Secure MCP Tunnel       | Compatibilidade técnica e header Bearer estático preparados              | Obter tunnel ID/runtime key/permissões, aprovar raiz e configurar workspace |
| Integrações open source | Avaliadas; nenhuma ferramenta com escrita foi exposta                    | Serena M02, MetaMCP M03, conforme decisões documentadas                     |

## Limitações conhecidas

- Allowlist real segue vazia. Não ativar acesso a diretórios pessoais sem aprovação explícita do usuário.
- O gateway local usa bearer estático. A UI ChatGPT não recebe bearer arbitrário; o tunnel-client v0.0.15 suporta injetá-lo por header de serviço local quando a conexão ChatGPT usa modo sem auth. Isso é uma identidade compartilhada e ainda precisa de validação e aprovação do workspace. Não remover auth como atalho.
- Node/Windows não garante proteção completa contra toda condição de corrida TOCTOU; está documentado como risco residual.
- A conta `HenriquePvAr` está autenticada. A configuração local de helper fica em `.git/config`; o Git Credential Manager global dos demais projetos não foi alterado.
- A árvore ainda mostra `?? docs/status/`; dashboard do usuário foi inspecionado somente para preparar proposta, sem alterações ou inclusão nos commits.

## Próximos passos

1. Solicitar aprovação explícita para `C:\Users\Dell\Downloads\Nodaris` como primeira raiz autorizada.
2. Obter tunnel ID/runtime API key e confirmar permissões/associação com a organização e workspace alvo.
3. Validar header estático via tunnel-client `v0.0.15` e testar uma chamada real do ChatGPT; manter gateway autenticado.
4. Atualizar a apresentação do quadro estático somente após aprovação explícita do autor, preservando o HTML e IDs existentes.
5. M02: avaliar Serena isolada somente leitura, mantendo revisão da licença GPL-3.0-or-later.
