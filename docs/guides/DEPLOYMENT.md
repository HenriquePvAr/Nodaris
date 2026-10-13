# Implantação local e conexão privada

## Escopo M01.2

O primeiro computador executa três processos na mesma fronteira de confiança: agente Nodaris (`127.0.0.1:3334`), gateway MCP Streamable HTTP (`127.0.0.1:3333`) e, após configuração aprovada, o `tunnel-client` oficial. Nenhum processo deve escutar em interface pública. O túnel abre conexão HTTPS de saída para o plano de controle OpenAI e encaminha JSON-RPC MCP ao servidor privado.

O endpoint Nodaris não fica público. Não usar ngrok, port forwarding, listener em `0.0.0.0` ou regra inbound no firewall como substituto do Secure MCP Tunnel.

## Pré-condições antes de iniciar o túnel

1. Aprovar explicitamente a raiz local a ser exposta e confirmar a allowlist vazia/estreita no agente. Para o ensaio M01.2, a única raiz autorizada foi `C:\Users\Dell\Downloads\Nodaris`.
2. Criar ou obter o `tunnel_id` na organização Platform e associar o workspace ChatGPT alvo.
3. Obter runtime API key com `Tunnels Read + Use`; a chave administrativa com `Tunnels Read + Manage` não deve ser usada pelo processo de longa duração.
4. Provisionar `NODARIS_TOKEN` e a runtime key em ambiente/arquivo de segredo local, sem argumentos de processo, repositório ou chat.
5. Escolher uma política para identidade do ChatGPT: header estático compartilhado no tunnel-client, limitado pelas permissões do workspace, ou uma futura integração OAuth Nodaris para identidade por usuário.
6. Fixar e verificar a release do `tunnel-client`; a versão avaliada foi `v0.0.15` e seu ZIP Windows teve checksum comparado com o manifesto da release.

## Inicialização e validação

1. Iniciar `pnpm dev:agent` e `pnpm dev:gateway` com o mesmo token e apenas as raízes aprovadas.
2. Validar a conexão MCP local com fixtures e, depois de autorização explícita, com a raiz real. No ensaio local de 13/10/2026, as nove ferramentas foram listadas e chamadas; leitura, árvore, pesquisa, Git status/diff/log e negações de caminhos sensíveis/externos responderam conforme esperado.
3. Criar perfil do `tunnel-client` com a release fixada, `tunnel_id`, MCP URL `http://127.0.0.1:3333/mcp` e runtime API key carregada como segredo. `tunnel-client v0.0.15` está instalado em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`; `nodaris-local` foi criado. A consulta de leitura autenticada confirmou o túnel, `doctor` passou e o cliente está ativo.
4. Configurar o header Bearer Nodaris via referência `env:` ou `file:` do campo `mcp.extra_headers`; manter o valor fora do YAML versionado.
5. Executar `tunnel-client doctor --profile nodaris-local --explain`; confirmar a runtime key com `tunnel-client admin tunnels get <tunnel_id>`. Após autenticação aprovada, iniciar o cliente e verificar `/healthz`, `/readyz` e `/ui` somente em loopback. Esses endpoints retornaram HTTP 200 em 13/10/2026.
6. O proprietário deve criar o conector Tunnel no workspace ChatGPT apropriado. Validar a conexão ponta a ponta com chamadas reais do ChatGPT; ainda não realizadas.
7. Interromper processos com Ctrl+C quando o ensaio terminar; M01.3 ainda não configura serviço persistente do Windows.

## Limites e rollback

- As ferramentas Nodaris continuam somente leitura e a autorização por projeto continua no agente.
- A autenticação de transporte do `tunnel-client` é independente do Bearer Nodaris usado no endpoint local.
- A configuração sem autenticação no lado ChatGPT combinada a um header estático é uma identidade de serviço compartilhada. Não atende isolamento individual por usuário.
- Se `/readyz`, autenticação do gateway, allowlist ou associação de workspace falhar, parar o cliente; não relaxar a autenticação ou aumentar a allowlist para contornar o erro.
- O cliente está ativo localmente, mas ainda não foi configurado como serviço persistente do Windows; após reinicialização, deverá ser iniciado manualmente. O conector e a conexão real do ChatGPT ainda estão pendentes.

Referências: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [guia de configuração do tunnel-client v0.0.15](https://github.com/openai/tunnel-client/blob/v0.0.15/docs/configuration.md).
