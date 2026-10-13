# Implantação local e conexão privada

## Instalação local M01.5

O primeiro computador executa três processos na mesma fronteira de confiança: agente Nodaris (`127.0.0.1:3334`), gateway MCP Streamable HTTP (`127.0.0.1:3333`) e, após configuração aprovada, o `tunnel-client` oficial. Nenhum processo deve escutar em interface pública. O túnel abre conexão HTTPS de saída para o plano de controle OpenAI e encaminha JSON-RPC MCP ao servidor privado.

O endpoint Nodaris não fica público. Não usar ngrok, port forwarding, listener em `0.0.0.0` ou regra inbound no firewall como substituto do Secure MCP Tunnel.

## Pré-condições antes de iniciar o túnel

1. Aprovar explicitamente a raiz local a ser exposta e confirmar a allowlist vazia/estreita no agente. Para o ensaio M01.2, a única raiz autorizada foi `C:\Users\Dell\Downloads\Nodaris`.
2. Criar ou obter o `tunnel_id` na organização Platform e associar o workspace ChatGPT alvo.
3. Obter runtime API key com `Tunnels Read + Use`; a chave administrativa com `Tunnels Read + Manage` não deve ser usada pelo processo de longa duração.
4. Provisionar `NODARIS_TOKEN` e a runtime key em ambiente/arquivo de segredo local, sem argumentos de processo, repositório ou chat.
5. Escolher uma política para identidade do ChatGPT: header estático compartilhado no tunnel-client, limitado pelas permissões do workspace, ou uma futura integração OAuth Nodaris para identidade por usuário.
6. Fixar e verificar a release do `tunnel-client`; a versão avaliada foi `v0.0.15` e seu ZIP Windows teve checksum comparado com o manifesto da release.

## Inicialização e validação observadas

1. Iniciar `pnpm dev:agent` e `pnpm dev:gateway` com o mesmo token e apenas as raízes aprovadas.
2. Validar a conexão MCP local com fixtures e, depois de autorização explícita, com a raiz real. No ensaio local de 13/10/2026, as nove ferramentas foram listadas e chamadas; leitura, árvore, pesquisa, Git status/diff/log e negações de caminhos sensíveis/externos responderam conforme esperado.
3. Criar perfil do `tunnel-client` com a release fixada, `tunnel_id`, MCP URL `http://127.0.0.1:3333/mcp` e runtime API key carregada como segredo. `tunnel-client v0.0.15` está instalado em `%LOCALAPPDATA%\Nodaris\tunnel-client\v0.0.15`; `nodaris-local` foi criado. A consulta de leitura autenticada confirmou o túnel, `doctor` passou e o cliente está ativo.
4. Configurar o header Bearer Nodaris via referência `env:` ou `file:` do campo `mcp.extra_headers`; manter o valor fora do YAML versionado.
5. Executar `tunnel-client doctor --profile nodaris-local --explain`; confirmar a runtime key com `tunnel-client admin tunnels get <tunnel_id>`. Após autenticação aprovada, iniciar o cliente e verificar `/healthz`, `/readyz` e `/ui` somente em loopback. Esses endpoints retornaram HTTP 200 em 13/10/2026.
6. Em 13/10/2026, o proprietário validou chamadas reais pelo ChatGPT: health, lista de projetos, árvore, leitura, busca de código, Git status e Git log. `README.md` e a pesquisa retornaram dados locais; somente o projeto Nodaris foi identificado.
7. Os listeners Nodaris e do tunnel-client foram observados em `127.0.0.1:3333`, `127.0.0.1:3334` e `127.0.0.1:8080`. Não foram encontrados serviço, tarefa agendada, entrada Run ou atalho Startup Nodaris/tunnel-client. O início após reinício exige operação manual neste momento.
8. Para interromper manualmente, use Ctrl+C nos processos interativos. A inicialização persistente do Windows não faz parte da instalação atual.

## Limites e rollback

- As ferramentas Nodaris continuam somente leitura e a autorização por projeto continua no agente.
- A autenticação de transporte do `tunnel-client` é independente do Bearer Nodaris usado no endpoint local.
- A configuração sem autenticação no lado ChatGPT combinada a um header estático é uma identidade de serviço compartilhada. Não atende isolamento individual por usuário.
- Se `/readyz`, autenticação do gateway, allowlist ou associação de workspace falhar, parar o cliente; não relaxar a autenticação ou aumentar a allowlist para contornar o erro.
- O cliente está ativo localmente, mas ainda não foi configurado como serviço persistente do Windows; após reinicialização, deverá ser iniciado manualmente. As chamadas reais pelo ChatGPT foram validadas; reinicialização do Windows e recuperação após queda de internet ainda não foram testadas.

Consulte o [plano de testes de estabilidade](STABILITY_TESTS.md) antes de avaliar essas duas pendências. Não registre PASS sem evidência coletada após cada evento.

## Inicialização no Windows (M01.7/M01.8)

O suporte M01.7 adiciona scripts locais em `scripts/windows/` para registrar uma tarefa do Agendador no logon do usuário atual com nível `Limited` e execução interativa. Ela não usa `SYSTEM`, não armazena credenciais na definição da tarefa e não inicia no momento da instalação. O primeiro disparo ocorrerá no próximo logon após a tarefa ser habilitada.

Abra PowerShell na raiz do Nodaris e use:

```powershell
.\scripts\windows\nodaris.ps1 install
.\scripts\windows\nodaris.ps1 repair
.\scripts\windows\nodaris.ps1 status
.\scripts\windows\nodaris.ps1 start
.\scripts\windows\nodaris.ps1 stop
.\scripts\windows\nodaris.ps1 restart
.\scripts\windows\nodaris.ps1 disable
.\scripts\windows\nodaris.ps1 enable
.\scripts\windows\nodaris.ps1 uninstall
```

`install` cria a tarefa do usuário e uma pasta de estado com ACL restrita à conta atual e SYSTEM; não inicia nem interrompe processos existentes. `repair` exporta a definição anterior para `%LOCALAPPDATA%\Nodaris\supervisor\task-before-invisible-launcher.xml` com ACL restrita e altera somente a ação da tarefa para `wscript.exe` + `launcher.vbs`. A definição, gatilho, usuário, nível `Limited` e política `IgnoreNew` são preservados. O launcher GUI chama PowerShell com modo oculto; o próprio Agendador não inicia um console diretamente. `start` inicia a tarefa ou, se desabilitada, usa o mesmo launcher; `stop` pede ao supervisor o encerramento dos filhos que ele próprio iniciou; `disable` impede disparos futuros sem desinstalar. `uninstall` remove a tarefa, mas preserva estado, backup, segredos e outros arquivos locais. `status` não mostra credenciais. `repair` afeta apenas o próximo disparo e não reinicia uma tarefa já ativa.

O supervisor carrega o Bearer somente do arquivo local protegido, fixa a allowlist M01 na raiz Nodaris aprovada e força bind `127.0.0.1`. Inicia agente, verifica sua resposta autenticada, inicia gateway e então o `tunnel-client` pelo perfil local existente. O perfil aponta runtime API key e Bearer para arquivos locais protegidos; os valores não são escritos na definição da tarefa ou argumentos, e a API key é removida do ambiente herdado pelo tunnel-client. Se houver conflito de portas, não cria uma segunda instância. O `tunnel-client v0.0.15` mantém seu polling e documenta retry com backoff exponencial limitado e jitter para erros de transporte; o supervisor não o reinicia por perda de prontidão do control plane. Essa é evidência de comportamento implementado no cliente, não prova de reconexão após uma queda real. Saídas dos serviços não são gravadas em arquivo. Falhas de processo usam backoff limitado; ao abrir o circuito, é necessária inspeção local e comando explícito `restart`/`start`.

O proprietário confirmou após reiniciar o Windows chamadas reais do ChatGPT a `nodaris_health`, `nodaris_projects_list`, `nodaris_file_read` (`README.md`) e `nodaris_git_status`. A inspeção do Agendador confirmou tarefa `Running`, usuário `Dell`, logon `Interactive`, nível `Limited`, resultado `0x41301` (tarefa em execução), e os PIDs do agente, gateway e túnel descendiam do PowerShell iniciado pelo serviço do Agendador. A janela azul permaneceu visível mesmo com `-WindowStyle Hidden`; portanto a conectividade MCP pós-reinício está comprovada, mas a invisibilidade do novo launcher só será comprovada no próximo logon. Não fechar a sessão atual para testar.

Referências: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [guia de configuração do tunnel-client v0.0.15](https://github.com/openai/tunnel-client/blob/v0.0.15/docs/configuration.md).
