# Preparação da conexão privada com ChatGPT

Estado em 13/10/2026: agente e gateway foram iniciados em loopback e o gateway foi validado por chamadas MCP reais contra a raiz autorizada `C:\Users\Dell\Downloads\Nodaris`. O cliente oficial `tunnel-client v0.0.15` está instalado; o perfil local `nodaris-local` usa o túnel Nodaris existente. Após o proprietário atualizar a cópia local do runtime key, `admin tunnels get` autenticou, `doctor --explain` passou e o cliente iniciou. `/healthz`, `/readyz` e `/ui` retornam HTTP 200 em `127.0.0.1:8080`. O plugin e as chamadas reais do ChatGPT continuam pendentes. Não abrir porta inbound pública.

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

No ChatGPT, selecionar a opção de autenticação sem autenticação para essa conexão faz o túnel atuar como transporte e o `tunnel-client` encaminhar o header estático configurado. O gateway continua validando o token. O acesso passa a ser uma identidade de serviço compartilhada: controle de quem pode invocar depende das permissões do workspace/túnel, sem identidade individual propagada pelo Bearer Nodaris. Isso precisa ser revisado para o workspace específico antes da ativação. Não escolher essa configuração se acesso individual por usuário for requisito; nesse caso, desenhar OAuth Nodaris.

O ZIP Windows amd64 do `tunnel-client v0.0.15` teve SHA-256 conferido com `SHA256SUMS.txt` da release oficial; o executável não tem assinatura Authenticode. A release foi instalada em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`, incluindo licença e inventário SPDX. `help quickstart`, `help init` e `help doctor` foram consultados; o comando `run` está ativo e os endpoints locais estão saudáveis.

## Evidências locais M01.2

- Allowlist do processo: somente `C:\Users\Dell\Downloads\Nodaris`; o agente descobriu exatamente um projeto.
- Gateway `127.0.0.1:3333` e agente `127.0.0.1:3334`; token aleatório mantido fora do repositório, em `%LOCALAPPDATA%\Nodaris`, sem aparecer em argumentos ou logs.
- Cliente MCP conectou ao endpoint `/mcp` com Bearer. As nove ferramentas Nodaris foram listadas: health, machines list, projects list, project tree, code search, file read, Git status, diff e log.
- `README.md` foi lido; árvore retornou 41 entradas; pesquisa por `NODARIS_TOKEN` retornou resultados limitados; status, diff e log Git responderam.
- A leitura de `.env.local`, `.git/config` e de um caminho absoluto externo foi recusada.
- `pnpm test`: 9/9 testes aprovados; `pnpm typecheck`: aprovado.
- Essas evidências validam o Nodaris local, não o túnel nem o ChatGPT.

## Estado M01.3

- A runtime key foi importada do TXT local para `%LOCALAPPDATA%\Nodaris\secrets\control-plane-api-key.txt`; o conteúdo não foi impresso, passado em argumentos, registrado em log ou salvo no repositório. A pasta e o arquivo têm ACL somente para a conta Windows atual e SYSTEM.
- O TXT de origem foi atualizado pelo proprietário e permaneceu em Downloads até que a autenticação do túnel fosse validada. Agora que a autenticação passou, o proprietário deve apagar manualmente essa cópia temporária.
- Perfil `nodaris-local`: `control_plane.api_key` usa `file:`, MCP aponta para `http://127.0.0.1:3333/mcp`, e os cabeçalhos runtime e discovery referenciam o arquivo Bearer local protegido.
- `tunnel-client doctor --profile nodaris-local --explain`: PASS. `/mcp` retornou 401 sem Bearer nas probes; os metadados OAuth ausentes retornaram 404 e a checagem reconheceu o servidor MCP sem OAuth.
- Consulta read-only `tunnel-client admin tunnels get` com o runtime key protegido: PASS; o túnel retornado corresponde ao ID configurado. Não houve exposição do conteúdo do segredo.
- `tunnel-client doctor --profile nodaris-local --explain`: PASS. Cliente `run` permaneceu ativo e `/healthz`, `/readyz` e `/ui` retornaram HTTP 200 em loopback.
- ChatGPT plugin e conexão real: pendentes. Não marcar PASS antes de chamadas ChatGPT reais.

## Procedimento após liberação

1. O runtime key atualizado já foi validado pela API de leitura do túnel e o cliente está ativo; não compartilhar o segredo.
2. O proprietário deve apagar manualmente o TXT temporário em Downloads, mantendo a cópia protegida em `%LOCALAPPDATA%\Nodaris\secrets`.
3. No ChatGPT, criar o connector no workspace pessoal correto, escolher a opção de túnel, selecionar Nodaris e usar o modo sem autenticação individual aprovado provisoriamente.
4. Validar `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read` para `README.md` e `nodaris_git_status` em chamadas reais do ChatGPT.
5. Confirmar que tentativa de caminho externo é negada. Só então marcar a conexão ponta a ponta como PASS.

## Dados que faltam para executar Etapa B/C

- permissão no workspace ChatGPT para custom MCP server.
- criação/instalação manual do connector pelo proprietário e chamadas reais das ferramentas.
- confirmar se o modelo de identidade de serviço compartilhada com header estático satisfaz a política do workspace; caso contrário, desenhar OAuth Nodaris.

O cliente oficial aceita MCP via HTTP e header MCP estático em perfil; portanto existe uma rota técnica para preservar o Bearer do gateway. Runtime key e saúde local foram validadas; a integração de ponta a ponta ainda depende do connector e de chamadas reais do ChatGPT. Não desative a autenticação do gateway nem crie túnel alternativo ou endpoint público.

Referências oficiais consultadas: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [tunnel-client v0.0.15](https://github.com/openai/tunnel-client/tree/v0.0.15) e [releases](https://github.com/openai/tunnel-client/releases).
