# Conexão privada real com ChatGPT

Estado em 13/10/2026: o proprietário confirmou a conexão real do ChatGPT e chamadas às ferramentas `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read`, `nodaris_code_search`, `nodaris_git_status` e `nodaris_git_log`. A leitura de `README.md` e a pesquisa retornaram dados locais, e o agente identificou exclusivamente o projeto Nodaris. O agente, gateway e cliente oficial `tunnel-client v0.0.15` usam loopback; o plano de controle foi observado em `ok/polling`. Não abrir porta inbound pública. Reinício do Windows e reconexão após queda de internet ainda não foram testados.

## Pré-requisitos do gate

1. Um `tunnel_id` criado nas configurações de Tunnels da OpenAI Platform.
2. Uma runtime API key para executar `tunnel-client`. Essa chave é diferente do `NODARIS_TOKEN` do Nodaris.
3. Permissões Platform `Tunnels Read + Manage` para criar/editar o túnel; `Tunnels Read + Use` para executá-lo/selecioná-lo.
4. O túnel associado à organização Platform e workspace ChatGPT corretos.
5. Permissão do workspace para adicionar/usar custom MCP servers.
6. Host Nodaris executando agente e gateway em `127.0.0.1`, com uma raiz aprovada. O `tunnel-client` deve alcançar o endpoint MCP local.

O host do tunnel-client faz HTTPS de saída para `api.openai.com:443` (ou `mtls.api.openai.com:443` quando configurado) e alcança o servidor MCP privado. Não abrir inbound firewall. O protocolo MCP do gateway Nodaris é Streamable HTTP; o `tunnel-client` oficial aceita um servidor MCP via HTTP, além de stdio.

## Autenticação do MCP Nodaris

O gateway continuará exigindo o Bearer Nodaris. A versão oficial `tunnel-client v0.0.15` documenta `mcp.extra_headers` e referências `env:VAR`/`file:/path`; isso permite que o cliente injete um header `Authorization: Bearer ...` somente nas requisições ao endpoint MCP local. A chave fica no ambiente ou arquivo de segredo local, nunca em argumentos, perfil versionado, log ou chat.

No ChatGPT, foi selecionada a opção sem autenticação individual para essa conexão; o `tunnel-client` encaminha o header estático e o gateway continua validando o Bearer. O proprietário aprovou provisoriamente essa identidade de serviço compartilhada para o workspace pessoal. O acesso individual por usuário não é propagado; antes de ampliar o uso, desenhar OAuth Nodaris.

O ZIP Windows amd64 do `tunnel-client v0.0.15` teve SHA-256 conferido com `SHA256SUMS.txt` da release oficial; o executável não tem assinatura Authenticode. A release foi instalada em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`, incluindo licença e inventário SPDX. `help quickstart`, `help init` e `help doctor` foram consultados; o comando `run` está ativo e os endpoints locais estão saudáveis.

## Evidências locais M01.2

- Allowlist do processo: somente `C:\Users\Dell\Downloads\Nodaris`; o agente descobriu exatamente um projeto.
- Gateway `127.0.0.1:3333` e agente `127.0.0.1:3334`; token aleatório mantido fora do repositório, em `%LOCALAPPDATA%\Nodaris`, sem aparecer em argumentos ou logs.
- Cliente MCP conectou ao endpoint `/mcp` com Bearer. As nove ferramentas Nodaris foram listadas: health, machines list, projects list, project tree, code search, file read, Git status, diff e log.
- `README.md` foi lido; árvore retornou 41 entradas; pesquisa por `NODARIS_TOKEN` retornou resultados limitados; status, diff e log Git responderam.
- A leitura de `.env.local`, `.git/config` e de um caminho absoluto externo foi recusada.
- `pnpm test`: 9/9 testes aprovados; `pnpm typecheck`: aprovado.
- Essas evidências de M01.2 validaram o Nodaris local. A validação ponta a ponta posterior, confirmada pelo proprietário em 13/10/2026, está registrada abaixo.

## Estado M01.5

- A runtime key foi importada do TXT local para `%LOCALAPPDATA%\Nodaris\secrets\control-plane-api-key.txt`; o conteúdo não foi impresso, passado em argumentos, registrado em log ou salvo no repositório. A pasta e o arquivo têm ACL somente para a conta Windows atual e SYSTEM.
- O TXT de origem foi atualizado pelo proprietário e permaneceu em Downloads até que a autenticação do túnel fosse validada. Agora que a autenticação passou, o proprietário deve apagar manualmente essa cópia temporária.
- Perfil `nodaris-local`: `control_plane.api_key` usa `file:`, MCP aponta para `http://127.0.0.1:3333/mcp`, e os cabeçalhos runtime e discovery referenciam o arquivo Bearer local protegido.
- `tunnel-client doctor --profile nodaris-local --explain`: PASS. `/mcp` retornou 401 sem Bearer nas probes; os metadados OAuth ausentes retornaram 404 e a checagem reconheceu o servidor MCP sem OAuth.
- Consulta read-only `tunnel-client admin tunnels get` com o runtime key protegido: PASS; o túnel retornado corresponde ao ID configurado. Não houve exposição do conteúdo do segredo.
- `tunnel-client doctor --profile nodaris-local --explain`: PASS. Cliente `run` permaneceu ativo; `/healthz`, `/readyz` e `/ui` retornaram HTTP 200 em loopback. Na captura local anterior à validação real, `/health?details=true` mostrou `control-plane: ok/polling` e `mcp: not_observed`. Depois, o proprietário confirmou chamadas reais às ferramentas Nodaris pelo ChatGPT.
- ChatGPT plugin e conexão real: validados pelo proprietário em chamadas reais às sete ferramentas listadas acima. A validação foi informada pelo proprietário; este registro não afirma evidência adicional além das chamadas descritas.
- Estabilidade após reinício do Windows e queda de internet: pendente, não testada.

## Operação e pendências

1. Manter a raiz autorizada exclusivamente em `C:\Users\Dell\Downloads\Nodaris` e as credenciais em arquivos locais protegidos; nunca copiar segredos para este guia.
2. A cópia TXT de origem da runtime key ainda existia em Downloads durante a revisão de 13/10/2026; o proprietário deve removê-la manualmente depois de confirmar a cópia protegida.
3. Executar os cenários de reinício e perda/restauração de rede descritos em [STABILITY_TESTS.md](STABILITY_TESTS.md), registrando PASS/FAIL por cenário somente após executar.

## Pendências de estabilidade

- executar e registrar o teste após reinício do Windows.
- executar e registrar o teste de reconexão após indisponibilidade temporária de internet.
- avaliar identidade individual/OAuth antes de ampliar o uso além do workspace pessoal aprovado.

O cliente oficial aceita MCP via HTTP e header MCP estático em perfil; portanto existe uma rota técnica para preservar o Bearer do gateway. A conexão real foi validada pelo proprietário, com a identidade de serviço compartilhada aprovada provisoriamente para o workspace pessoal. Não desative a autenticação do gateway nem crie túnel alternativo ou endpoint público.

Referências oficiais consultadas: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [tunnel-client v0.0.15](https://github.com/openai/tunnel-client/tree/v0.0.15) e [releases](https://github.com/openai/tunnel-client/releases).
