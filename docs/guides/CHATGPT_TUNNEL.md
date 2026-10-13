# Preparação da conexão privada com ChatGPT

Estado em 13/10/2026: agente e gateway foram iniciados em loopback e o gateway foi validado por chamadas MCP reais contra a raiz autorizada `C:\Users\Dell\Downloads\Nodaris`. O cliente oficial `tunnel-client v0.0.15` foi instalado localmente, sem credenciais OpenAI. O túnel e a conexão pelo ChatGPT continuam pendentes de configuração manual na OpenAI Platform; ainda não houve chamada real pelo ChatGPT. Não abrir porta inbound pública.

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

O ZIP Windows amd64 do `tunnel-client v0.0.15` teve SHA-256 conferido com `SHA256SUMS.txt` da release oficial; o executável não tem assinatura Authenticode. A release foi extraída em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`, incluindo licença e inventário SPDX, com ACL limitada à conta local, ao processo Nodaris e ao sistema. `help quickstart`, `help init` e `help doctor` foram consultados. O cliente ainda não foi iniciado contra a OpenAI.

## Evidências locais M01.2

- Allowlist do processo: somente `C:\Users\Dell\Downloads\Nodaris`; o agente descobriu exatamente um projeto.
- Gateway `127.0.0.1:3333` e agente `127.0.0.1:3334`; token aleatório mantido fora do repositório, em `%LOCALAPPDATA%\Nodaris`, sem aparecer em argumentos ou logs.
- Cliente MCP conectou ao endpoint `/mcp` com Bearer. As nove ferramentas Nodaris foram listadas: health, machines list, projects list, project tree, code search, file read, Git status, diff e log.
- `README.md` foi lido; árvore retornou 41 entradas; pesquisa por `NODARIS_TOKEN` retornou resultados limitados; status, diff e log Git responderam.
- A leitura de `.env.local`, `.git/config` e de um caminho absoluto externo foi recusada.
- `pnpm test`: 9/9 testes aprovados; `pnpm typecheck`: aprovado.
- Essas evidências validam o Nodaris local, não o túnel nem o ChatGPT.

## Procedimento após liberação

1. Na OpenAI Platform, criar/confirmar o túnel na organização e workspace pessoais autorizados e confirmar as permissões Tunnels Read + Use. O usuário deverá informar somente o `tunnel_id` (nunca a runtime key).
2. Criar uma runtime key com Tunnels Read + Use e provisioná-la localmente, sem enviá-la pelo chat. O usuário precisa confirmar quando a chave estiver disponível localmente.
3. Gerar perfil `sample_mcp_remote_no_auth` para `http://127.0.0.1:3333/mcp`, usando o `tunnel_id` real e referência de segredo para `CONTROL_PLANE_API_KEY`; configurar `Authorization` via `file:` para `%LOCALAPPDATA%\Nodaris\gateway-authorization.txt`.
4. Executar `tunnel-client doctor --profile <perfil> --explain`. Se doctor exigir OAuth/PRMD incompatível com a modalidade selecionada, parar e documentar a necessidade de rever autenticação, sem remover o Bearer.
5. Iniciar `tunnel-client` e confirmar `/healthz`, `/readyz` e `/ui` em loopback.
6. No ChatGPT, criar o connector no workspace correto. Usar sem autenticação no lado ChatGPT apenas se a identidade de serviço compartilhada for aceita para esse workspace.
7. Validar `nodaris_projects_list` e `nodaris_file_read` em chamada real pelo ChatGPT. Só então marcar a conexão ponta a ponta como PASS.

## Dados que faltam para executar Etapa B/C

- `tunnel_id` criado/confirmado pelo usuário na Platform.
- runtime API key criada pelo usuário e provisionada localmente (não enviar em chat nem gravar no repositório).
- confirmação visual de Tunnels Read + Use e associação com organização/workspace pessoais autorizados.
- permissão no workspace ChatGPT para custom MCP server.
- confirmação do usuário de que a configuração da Platform e a runtime key local foram concluídas.
- confirmar se o modelo de identidade de serviço compartilhada com header estático satisfaz a política do workspace; caso contrário, desenhar OAuth Nodaris.

O cliente oficial aceita MCP via HTTP e header MCP estático em perfil; portanto existe uma rota técnica para preservar o Bearer do gateway. As permissões reais da conta/workspace e a compatibilidade operacional do perfil ainda não foram confirmadas. Não desative a autenticação do gateway nem crie túnel alternativo ou endpoint público.

Referências oficiais consultadas: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [tunnel-client v0.0.15](https://github.com/openai/tunnel-client/tree/v0.0.15) e [releases](https://github.com/openai/tunnel-client/releases).
