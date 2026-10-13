# Preparação da conexão privada com ChatGPT

Estado em 13/10/2026: compatibilidade técnica preparada, mas conexão ainda não configurada nem testada. O Secure MCP Tunnel mantém o servidor privado: o cliente oficial inicia conexões HTTPS de saída e encaminha MCP para o endpoint acessível localmente. Não abrir porta inbound pública.

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

O `tunnel-client` foi baixado para pasta temporária e `help quickstart` foi executado. O SHA-256 do ZIP Windows v0.0.15 conferiu com `SHA256SUMS.txt` da release oficial; o executável não tem assinatura Authenticode. O binário não foi instalado persistentemente, nem iniciado com credenciais.

## Procedimento após liberação

1. Iniciar Nodaris e validar localmente `nodaris_health` e `nodaris_projects_list`.
2. Obter o cliente oficial fixado `v0.0.15` pela página de releases, conferir o SHA-256 da release e instalar de forma controlada. Manter `CONTROL_PLANE_API_KEY` fora do repositório e do histórico de comandos.
3. Criar um perfil local usando o exemplo `sample_mcp_remote_no_auth` e o URL `http://127.0.0.1:3333/mcp`. Configurar `mcp.extra_headers.Authorization` por referência `env:` ou `file:` para o header Bearer Nodaris, sem valor literal no YAML. Validar com `tunnel-client doctor --profile <perfil> --explain` antes de iniciar.
4. Iniciar Nodaris e `tunnel-client`; confirmar `/healthz`, `/readyz` e `/ui` locais.
5. Em ChatGPT, abrir Configurações → Connectors → Create → Tunnel; selecionar o túnel da organização/workspace corretos, escolher sem autenticação no lado ChatGPT somente se a identidade de serviço compartilhada for aceita, revisar o aviso e criar o conector.
6. Testar listagem de projetos, leitura de arquivo autorizado e Git status/diff. Confirmar com chamada real no ChatGPT; só então marcar PASS.

## Dados que faltam para executar Etapa B/C

- `tunnel_id` fornecido pela Platform.
- runtime API key provisionada de forma segura (não enviar em chat nem gravar no repositório).
- confirmação de Tunnels Read + Use e associação com o workspace alvo.
- permissão no workspace ChatGPT para custom MCP server.
- aprovação explícita do caminho local que será a primeira raiz autorizada.
- confirmar se o modelo de identidade de serviço compartilhada com header estático satisfaz a política do workspace; caso contrário, desenhar OAuth Nodaris.

O cliente oficial aceita MCP via HTTP e header MCP estático em perfil; portanto existe uma rota técnica para preservar o Bearer do gateway. Isso ainda não comprova compatibilidade operacional nem autorização individual: falta configurar e testar no tunnel/workspace reais. Não desative a autenticação do gateway nem crie túnel alternativo ou endpoint público.

Referências oficiais consultadas: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [tunnel-client v0.0.15](https://github.com/openai/tunnel-client/tree/v0.0.15) e [releases](https://github.com/openai/tunnel-client/releases).
