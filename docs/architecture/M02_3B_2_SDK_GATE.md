# M02.3B.2 — Gate de compatibilidade dos SDKs MCP

**Data da avaliação:** 16/10/2026
**Escopo:** fixture isolada em memória e inspeção estática dos pacotes fixados.
**Resultado:** compatibilidade de protocolo aprovada; OAuth de produção não habilitado.

## Resumo executivo

Os SDKs atualmente fixados interoperam com as duas eras de protocolo MCP testadas. O cliente mantém o modo legado por padrão; `auto` e `pin` negociam a era moderna `2026-07-28`. O servidor `createMcpHandler` atende as duas eras por padrão, e pode rejeitar explicitamente a era legada. Não é necessário atualizar dependências para obter essa compatibilidade.

O gate **não aprova OAuth real**. O resource server possui helpers para Protected Resource Metadata (PRM), validação Bearer e scopes, mas não existe Authorization Server, emissão de tokens, fluxo PKCE real nem teste com ChatGPT. Além disso, o tipo público de registro `McpServer.registerTool` em `@modelcontextprotocol/server@2.3.1` não declara nem serializa `securitySchemes` por ferramenta. O fixture confirmou que `_meta["mcp/www_authenticate"]` pode ser devolvido em um resultado MCP; o helper `scopeChallenge`, por sua vez, gera um desafio HTTP 403, que não substitui o metadado MCP esperado pelo ChatGPT.

## Versões e licença inspecionadas

| Pacote                         | Versão fixada | Licença    | Evidência                 |
| ------------------------------ | ------------: | ---------- | ------------------------- |
| `@modelcontextprotocol/node`   |         2.1.1 | Apache-2.0 | `package.json` e lockfile |
| `@modelcontextprotocol/server` |         2.3.1 | Apache-2.0 | `package.json` e lockfile |
| `@modelcontextprotocol/client` |         2.3.1 | Apache-2.0 | `package.json` e lockfile |

Nenhuma dependência, manifesto ou lockfile foi alterado. A API Node `toNodeHandler` adapta o handler Web ao servidor HTTP Node; ela foi inspecionada estaticamente, sem abrir listener. Os testes chamam `handler.fetch` diretamente, sem TCP, processos de serviço ou contato com o runtime Nodaris.

## Matriz observada

| Cenário                                          | Resultado do fixture                                                                                       |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| Cliente sem `versionNegotiation`                 | Usa handshake `initialize` e versão `2025-11-25`; sem probe `server/discover`.                             |
| Cliente `auto` contra `createMcpHandler`         | Descobre `2026-07-28`, chama ferramenta e o handler recebe `era=modern`.                                   |
| Cliente com pin `2026-07-28`                     | Conecta na era moderna.                                                                                    |
| Pin de versão inexistente                        | Resposta MCP rejeita com `ProtocolError` (`-32022`, versão não suportada); sem fallback para `initialize`. |
| Timeout HTTP no probe `auto`                     | Rejeita; não interpreta timeout como servidor legado nem tenta fallback.                                   |
| HTTP 401/403 no probe `auto`                     | Falha como autorização; não interpreta a resposta como era legada nem tenta `initialize`.                  |
| Cliente legado contra servidor dual              | Conecta normalmente pela era legada.                                                                       |
| Cliente legado contra handler `legacy: "reject"` | Recebe rejeição HTTP durante `initialize`.                                                                 |

A documentação da versão fixada chama a família até `2025-11-25` de `legacy` e a revisão `2026-07-28` de `modern`. O valor `LATEST_PROTOCOL_VERSION=2025-11-25` exportado pelo runtime não significa que a revisão moderna esteja indisponível: a versão moderna é negociada pelo fluxo explícito de descoberta. Para confirmar esse ponto foi usada a API real `createMcpHandler` e um cliente real do pacote fixado, com `fetch` injetado em memória.

## OAuth e fronteiras de autenticação

O fixture verificou os helpers públicos `buildOAuthProtectedResourceMetadata`, `getOAuthProtectedResourceMetadataUrl`, `oauthMetadataResponse`, `requireBearerAuth` e `verifyBearerToken` com valores sintéticos. A cobertura inclui PRM, ausência de credencial, token inválido, resource/audience diferente, expiração, scope ausente, scope insuficiente e token válido. O middleware pode emitir HTTP 401/403 com `WWW-Authenticate`; sem um verifier disponível, o harness falha fechado.

Esses helpers são uma camada de **resource server**. Eles não implementam Authorization Server, login, emissão ou renovação de tokens, registro de cliente, armazenamento seguro de sessão ou validação criptográfica de JWT/JWKS. O verifier deve ser fornecido pela aplicação e precisa validar emissor, audiência/resource, expiração, scopes e assinatura segundo o provedor escolhido.

O teste de ferramenta confirmou:

- `scopeChallenge: requireScopes(...)` responde com HTTP 403 e cabeçalho Bearer quando o scope está ausente. Isso não equivale ao erro MCP de ferramenta contendo `_meta["mcp/www_authenticate"]`.
- O callback de ferramenta consegue devolver resultado de erro MCP com `_meta["mcp/www_authenticate"]`; o cliente preserva esse campo.
- O `registerTool` público da versão fixada não contém `securitySchemes` em seu tipo de configuração, e `tools/list` não serializa esse campo quando ausente da API pública.
- O cliente MCP recebeu a resposta real de `tools/list`; como o servidor não publicou `securitySchemes`, não há metadata por ferramenta que o cliente possa consumir nesse cenário.

A documentação atual da OpenAI requer metadados PRM, `securitySchemes` por ferramenta e um erro de ferramenta com `_meta["mcp/www_authenticate"]` para acionar o vínculo OAuth no ChatGPT. Portanto, a lacuna de `securitySchemes` precisa de spike/decisão específica antes de integrar OAuth. Não se deve contornar os tipos com casts ou mutação interna do SDK, nem anunciar OAuth ou remover o Bearer existente com base neste gate.

## Decisão sobre atualização e próximos passos

**Atualização de SDK para compatibilidade de protocolo: não necessária.** A versão instalada negociou as duas eras nos testes.

**Atualização ou adaptação para completar o contrato OAuth/OpenAI: não determinada.** A API de registro não expõe `securitySchemes`; a próxima investigação deve comparar uma atualização futura do SDK, uma extensão pública suportada ou uma camada própria pequena e testável. Essa decisão exige revisão de API, licença, dependências e segurança antes de implementação. Não há autorização para implementar qualquer alternativa neste gate.

O próximo gate recomendado é **M02.3B.2B — SecuritySchemes Integration Strategy**: examinar APIs públicas suportadas da versão atual e versões oficiais posteriores, alternativas oficiais e uma adaptação mínima, sem tocar na instalação M01. A **M02.3B.3 fica reservada ao primeiro OAuth real**, somente depois de aprovada a estratégia por ferramenta.

| Alternativa                      | Compatibilidade e evidência                                                                                                                           | Licença/manutenção/risco                                                                                                          | Decisão deste gate                                              |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Configuração dos SDKs fixados    | `auto`/`pin` e `createMcpHandler` comprovam as duas eras; handler dual preserva clientes antigos.                                                     | Apache-2.0; nenhuma migração ou dependência adicional.                                                                            | Recomendada para interoperabilidade MCP.                        |
| Helpers públicos da mesma versão | PRM, validação Bearer, resource e scopes testados; `_meta` de erro pode ser serializado pelo resultado da ferramenta.                                 | Apache-2.0; aplicação ainda mantém verifier confiável e precisa implementar AS/fluxo OAuth.                                       | Reutilizar quando um desenho OAuth for autorizado.              |
| Atualizar o SDK                  | A release list consultada ainda identifica 2.3.1 como latest; não foi encontrada evidência de versão oficial posterior que resolva `securitySchemes`. | Atualização futura exige comparação de API, transitivas, advisories e testes de regressão.                                        | Não atualiza agora; necessidade para OAuth permanece em aberto. |
| Adaptador próprio limitado       | Poderia preencher metadado de ferramenta se suportado pelo contrato MCP/host, sem alterar autorização em produção.                                    | Maior custo de manutenção e risco de divergência de wire format; exige teste explícito de compatibilidade e revisão de segurança. | Apenas alternativa a investigar, não implementada.              |

Assim, a recomendação de manter a versão atual vale para o protocolo e para o gate isolado, não é aprovação de OAuth de produção. A decisão completa de atualização permanece **NOT_DETERMINED** até resolver como expor `securitySchemes` com API suportada e concluir o fluxo de autorização.

Não habilitar `versionNegotiation: "auto"` no cliente de produção somente por este resultado. No gateway atual, a compatibilidade legada foi validada em fixture; a negociação moderna real do gateway não foi ativada nem testada contra ChatGPT. O uso de `createMcpHandler` com uma factory por requisição é coerente com a recomendação de isolamento de instâncias do SDK; nenhum processo de produção foi exercitado.

## Revisão limitada de segurança de dependências

A inspeção de advisories públicos do repositório SDK foi comparada com os pacotes fixados. Na data da revisão, os advisories consultados incluem correções com versões mínimas já atendidas pelas versões diretas aqui avaliadas: autenticação Bearer/audience do servidor (`@modelcontextprotocol/server` 2.3.0+), isolamento de instâncias do servidor (2.3.0+), limite de request/batch para Node (2.1.0+) e proteção do cliente OAuth contra troca de issuer (`@modelcontextprotocol/client` 2.2.0+). Isso não prova a ausência de outros problemas nem substitui uma auditoria completa de dependências transitivas, advisories de todos os pacotes e execução de scanner no lockfile.

**DEPENDENCY_SECURITY_REVIEW=PARTIAL.** Nenhuma atualização foi feita nesta missão. Antes de produção, executar auditoria integral do lockfile e avaliar também limites de tamanho/complexidade de entrada configurados na aplicação e em `createMcpHandler`.

## Evidência e limites

- Testes novos: `tests/mcp-sdk-compatibility.test.ts` e `tests/fixtures/sdk-gate/server.ts`.
- Testes MCP executados no gate: 12, todos em memória, com tokens, issuer, resource e arquivos sintéticos.
- Validação desta execução: suíte completa 116/116; typecheck, lint e `format:check` passaram; `git diff --check` e varredura direcionada de segredos passaram. A suíte geral usa os harnesses existentes de testes, mas o fixture MCP deste gate não abre TCP.
- Markdown: documento revisado, sem links relativos ou blocos Mermaid; as referências externas são documentação oficial do SDK, OpenAI e advisories GitHub.
- Não houve consulta a projeto local via as ferramentas de produção, abertura de porta, chamada ChatGPT, alteração do runtime, ativação OAuth, instalação/atualização de pacote, commit ou push.

## Referências

1. [TypeScript SDK v2.3.1 — suporte à revisão 2026-07-28](https://github.com/modelcontextprotocol/typescript-sdk/blob/v2.3.1/docs/migration/support-2026-07-28.md).
2. [TypeScript SDK v2.3.1 — eras e negociação de protocolo](https://github.com/modelcontextprotocol/typescript-sdk/blob/v2.3.1/docs/protocol-versions.md).
3. [OpenAI — autenticação para MCP plugins](https://developers.openai.com/plugins/build/auth).
4. [GHSA-rvq5-wwqv-78pq — validação de audience no Bearer server](https://github.com/modelcontextprotocol/typescript-sdk/security/advisories/GHSA-rvq5-wwqv-78pq).
5. [GHSA-jm63-cq47-j5jp — isolamento de instâncias HTTP](https://github.com/modelcontextprotocol/typescript-sdk/security/advisories/GHSA-jm63-cq47-j5jp).
6. [GHSA-46jr-4wx8-v453 — custo de validação de entrada](https://github.com/modelcontextprotocol/typescript-sdk/security/advisories/GHSA-46jr-4wx8-v453).
7. [GHSA-f897-62hf-6gxq — limite de corpo e batch HTTP](https://github.com/modelcontextprotocol/typescript-sdk/security/advisories/GHSA-f897-62hf-6gxq).
8. [GHSA-6qxp-vccf-f47h — vínculo do OAuth client ao issuer](https://github.com/modelcontextprotocol/typescript-sdk/security/advisories/GHSA-6qxp-vccf-f47h).
9. [Releases oficiais do TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk/releases) — versão latest observada na consulta: 2.3.1.
