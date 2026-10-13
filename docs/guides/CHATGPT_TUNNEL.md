# Preparação da conexão privada com ChatGPT

Estado em 13/10/2026: documentação preparada; conexão não configurada nem testada. O Secure MCP Tunnel não exige porta inbound pública, mas precisa de configuração na OpenAI Platform e no workspace ChatGPT.

## Pré-requisitos do gate

1. Um `tunnel_id` criado nas configurações de Tunnels da OpenAI Platform.
2. Uma runtime API key para executar `tunnel-client`. Essa chave é diferente do `NODARIS_TOKEN` do Nodaris.
3. Permissões Platform `Tunnels Read + Manage` para criar/editar o túnel; `Tunnels Read + Use` para executá-lo/selecioná-lo.
4. O túnel associado à organização Platform e workspace ChatGPT corretos.
5. Permissão do workspace para adicionar/usar custom MCP servers.
6. Host Nodaris executando o agente e gateway em `127.0.0.1`, com uma raiz aprovada. O `tunnel-client` deve alcançar o endpoint MCP local.

O host do tunnel-client faz HTTPS de saída para `api.openai.com:443` (ou `mtls.api.openai.com:443` quando configurado) e alcança o servidor MCP privado. Não abrir inbound firewall.

## Procedimento após liberação

1. Iniciar Nodaris e validar localmente `nodaris_health` e `nodaris_projects_list`.
2. Iniciar o `tunnel-client` oficial na mesma fronteira de confiança, apontando-o ao MCP HTTP `http://127.0.0.1:3333/mcp`, com o `tunnel_id` e runtime API key oficiais.
3. Confirmar no painel local `/ui` que o cliente está saudável, pronto e conectado.
4. Em ChatGPT, abrir Plugins → `+` → Add custom MCP server → Tunnel; selecionar o túnel listado ou informar o `tunnel_id` válido.
5. Escolher na UI uma opção de autenticação suportada para custom MCP (OAuth, sem autenticação, ou OAuth/sem autenticação) e revisar o aviso de risco. A UI documentada não oferece uma credencial bearer arbitrária.
6. Testar listagem de projetos, leitura de arquivo autorizado e Git status/diff. Confirmar com uma chamada real em ChatGPT; só então marcar PASS.

## Dados que faltam para executar Etapa B/C

- `tunnel_id` fornecido pela Platform.
- runtime API key provisionada de forma segura (não enviar em chat nem gravar no repositório).
- confirmação de Tunnels Read + Use e associação com o workspace alvo.
- permissão no workspace ChatGPT para custom MCP server.
- aprovação explícita do caminho local que será a primeira raiz autorizada.
- decisão/implementação de autenticação compatível com a UI ChatGPT: o gateway atual exige bearer estático para todas as requisições MCP e ainda não oferece OAuth.

O teste local usa bearer estático e não comprova a compatibilidade de autenticação do app ChatGPT. Não desative a autenticação do gateway para contornar essa lacuna. Até o OAuth Nodaris ou uma alternativa autenticada oficialmente compatível ser implementada e os pré-requisitos estarem disponíveis, o resultado de conexão ChatGPT é BLOCKED, não PASS. Não criar túnel alternativo nem endpoint público.
