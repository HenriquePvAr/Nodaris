# Quadro do projeto

## Objetivo

Conectar ChatGPT a projetos locais explicitamente autorizados por MCP privado, com consultas somente leitura e autorização aplicada pelo agente local.

## Snapshot verificado em 13/10/2026

- Repositório oficial `HenriquePvAr/Nodaris`, público e vazio no clone; branch `main`, remote `origin` correto; nenhuma raiz real cadastrada.
- Ambiente: Git 2.55.0.windows.4, Node 24.19.0, pnpm 12.8.1.
- Dependências base fixadas: MCP Server 2.3.1, Node adapter 2.1.1, MCP Client 2.3.1, Zod 4.6.7, TypeScript 5.9.3, Vitest 5.0.4.
- Typecheck, ESLint e Prettier passaram; `pnpm audit --json` reportou 0 vulnerabilidades.
- Testes executados entre processos com cliente MCP: 9 passaram (4 filesystem/Git e 5 integração).
- MCP Inspector 2.10.1 conectou por Streamable HTTP e listou as nove ferramentas; todas anunciaram `readOnlyHint: true`.
- Leitura, busca, árvore, Git status/log/diff, concorrência, agente offline/reconexão e bloqueios de token/caminhos externos foram exercitados em fixtures.
- Secure MCP Tunnel não configurado/testado. A conexão ChatGPT é **BLOCKED**: faltam tunnel ID, runtime API key, permissões, raiz real aprovada e estratégia de autenticação compatível com ChatGPT.
- Credencial GitHub local está inválida; push remoto não disponível.

## Frentes e estado

| Frente                  | Estado                                                                   | Próxima ação                                                                           |
| ----------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Fundação                | Implementada e validada localmente                                       | Revisão final, commit local em `main`, push quando autenticação estiver renovada       |
| Filesystem/Git          | Ferramentas Nodaris somente leitura; testes em fixtures aprovados        | Aprovar uma raiz real candidata e repetir inspeção sem expor áreas não autorizadas     |
| Integração MCP          | Gateway Streamable HTTP e agente separados; Inspector listou ferramentas | Executar leitura e diff via Inspector se necessário para evidência adicional           |
| Secure MCP Tunnel       | Bloqueado por pré-requisitos externos e OAuth                            | Obter tunnel ID/runtime key/permissões e implementar auth compatível antes de conectar |
| Integrações open source | Avaliadas; nenhuma ferramenta com escrita foi exposta                    | Serena M02, MetaMCP M03, conforme decisões documentadas                                |

## Limitações conhecidas

- Allowlist real segue vazia. Não ativar acesso a diretórios pessoais sem aprovação explícita do usuário.
- O gateway local usa bearer estático; a UI ChatGPT custom MCP documenta OAuth/sem autenticação e não oferece bearer arbitrário. Não remover auth como atalho.
- Node/Windows não garante proteção completa contra toda condição de corrida TOCTOU; está documentado como risco residual.
- `gh auth status` informa token inválido; commit/push precisam ser concluídos depois da renovação manual da sessão.

## Próximos passos

1. Fazer revisão de segurança do diff local e criar commit Conventional Commit em `main`.
2. Renovar autenticação GitHub e enviar fast-forward para a `main` remota sem força.
3. O usuário indicar/aprovar uma raiz local específica para habilitar descoberta real.
4. Resolver autenticação OAuth e dados/permissões do Secure MCP Tunnel; testar uma chamada real do ChatGPT.
5. M02: avaliar Serena isolada somente leitura, mantendo revisão da licença GPL-3.0-or-later.
