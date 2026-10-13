# Implantação local e conexão privada

## Escopo M01.1

O primeiro computador executa três processos na mesma fronteira de confiança: agente Nodaris (`127.0.0.1:3334`), gateway MCP Streamable HTTP (`127.0.0.1:3333`) e, após configuração aprovada, o `tunnel-client` oficial. Nenhum processo deve escutar em interface pública. O túnel abre conexão HTTPS de saída para o plano de controle OpenAI e encaminha JSON-RPC MCP ao servidor privado.

O endpoint Nodaris não fica público. Não usar ngrok, port forwarding, listener em `0.0.0.0` ou regra inbound no firewall como substituto do Secure MCP Tunnel.

## Pré-condições antes de iniciar o túnel

1. Aprovar explicitamente a raiz local a ser exposta e confirmar a allowlist vazia/estreita no agente.
2. Criar ou obter o `tunnel_id` na organização Platform e associar o workspace ChatGPT alvo.
3. Obter runtime API key com `Tunnels Read + Use`; a chave administrativa com `Tunnels Read + Manage` não deve ser usada pelo processo de longa duração.
4. Provisionar `NODARIS_TOKEN` e a runtime key em ambiente/arquivo de segredo local, sem argumentos de processo, repositório ou chat.
5. Escolher uma política para identidade do ChatGPT: header estático compartilhado no tunnel-client, limitado pelas permissões do workspace, ou uma futura integração OAuth Nodaris para identidade por usuário.
6. Fixar e verificar a release do `tunnel-client`; a versão avaliada foi `v0.0.15` e seu ZIP Windows teve checksum comparado com o manifesto da release.

## Inicialização e validação

1. Iniciar `pnpm dev:agent` e `pnpm dev:gateway` com o mesmo token e apenas as raízes aprovadas.
2. Validar a conexão MCP local com fixture antes de configurar acesso a dados reais.
3. Criar perfil do `tunnel-client` com a release fixada, `tunnel_id`, MCP URL `http://127.0.0.1:3333/mcp` e runtime API key carregada como segredo.
4. Configurar o header Bearer Nodaris via referência `env:` ou `file:` do campo `mcp.extra_headers`; manter o valor fora do YAML versionado.
5. Executar `tunnel-client doctor --profile <perfil> --explain`; depois iniciar o cliente em primeiro plano e verificar `/healthz`, `/readyz` e `/ui` somente em loopback.
6. Criar o conector Tunnel no workspace ChatGPT apropriado. Uma chamada real do ChatGPT é o único critério para validar a conexão ponta a ponta.
7. Interromper processos com Ctrl+C quando o ensaio terminar; M01.1 ainda não configura serviço persistente do Windows.

## Limites e rollback

- As ferramentas Nodaris continuam somente leitura e a autorização por projeto continua no agente.
- A autenticação de transporte do `tunnel-client` é independente do Bearer Nodaris usado no endpoint local.
- A configuração sem autenticação no lado ChatGPT combinada a um header estático é uma identidade de serviço compartilhada. Não atende isolamento individual por usuário.
- Se `/readyz`, autenticação do gateway, allowlist ou associação de workspace falhar, parar o cliente; não relaxar a autenticação ou aumentar a allowlist para contornar o erro.
- A instalação testada foi temporária. Uma instalação persistente e inicialização em background exigem processo de implantação próprio, revisão operacional e instruções do usuário.

Referências: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [guia de configuração do tunnel-client v0.0.15](https://github.com/openai/tunnel-client/blob/v0.0.15/docs/configuration.md).
