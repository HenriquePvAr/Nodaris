# Claude Code: instalação local do Nodaris

Copie o roteiro abaixo no Claude Code depois de clonar o repositório no computador novo. Ele orienta uma instalação real do runtime Windows portátil e mantém o túnel, Obsidian e capacidades de escrita como etapas separadas.

```text
Configure o Nodaris somente neste computador e neste clone. Leia README.md e os guias INSTALLATION_NEW_PC.md, CHATGPT_MCP_CONNECTION.md, OBSIDIAN_MEMORY_SETUP.md e TROUBLESHOOTING.md por completo. Primeiro inspecione Windows, PowerShell, Git, Node, Corepack/pnpm, NTFS, estado do clone, ferramentas e tarefas Nodaris existentes. Nunca imprima credenciais, tokens, caminhos privados de outras instalações ou conteúdos do vault.

Não copie nem infira machineId, repositoryId, workspaceId, tunnel ID, runtime key, token, Registry, vault, backup ou política de outra máquina. Não edite nem execute scripts home-* do desenvolvedor original. Use apenas scripts/windows/nodaris-portable.ps1 para configurar o runtime local de leitura.

Faça clone limpo/instalação fixada e rode typecheck, lint e suíte completa. Então rode doctor, que é somente leitura. Antes de `configure`, mostre que ele criará `%LOCALAPPDATA%\Nodaris\portable\runtime.json` e `gateway-token.dpapi`, gerará machineId/token novos e gravará somente as raízes NTFS que o operador selecionar. Peça aprovação local; depois execute o comando em PowerShell interativo e deixe o operador confirmar o escopo no TTY. Não invente nem preencha aprovações.

Após a configuração, valide a ACL privada, DPAPI, raízes e flags de escrita desligadas. Antes de `start`, mostre portas loopback 3333/3334, raízes e que Agent/Gateway serão iniciados; aguarde aprovação local. Confirme dono do PID/porta, health autenticado e MCP initialize/tools/list. Se portas ou processos tiverem identidade desconhecida, pare sem encerrar nada.

O autostart é opcional. Mostre o nome, usuário, ação, checkout, diretório e estado inicial disabled antes de `task-install`; a tarefa será de usuário, limitada e IgnoreNew. Para habilitar, peça aprovação local separada e deixe o operador digitar `ENABLE NODARIS TASK`. Não crie tarefas duplicadas. Teste rollback com task-disable/remove somente após aprovação local específica.

O script não cria recursos na conta OpenAI nem instala o binário. Para ChatGPT, conduza o operador pelo guia CHATGPT_MCP_CONNECTION.md: cliente oficial e checksum, tunnel ID e runtime key próprios, `tunnel-prepare-install`, `tunnel-configure` com prompt protegido, doctor e aprovação local separada em `tunnel-enable`. Só depois `start` inclui o tunnel-client na supervisão do mesmo runtime; autostart continua opcional e usa uma única tarefa do supervisor. Não solicite nem aceite chave administrativa. Nunca exponha o Gateway publicamente. Se o plano/conta não oferecer o recurso MCP requerido, registre o bloqueio sem contorno.

Obsidian é opcional e ainda não está pronto como writer multi-PC. Não crie ou vincule vault, não faça backup real, não habilite Memory Read/Write, UPDATE, APPEND, HISTORY ou Project Write. Reporte que faltam política por instalação, writer confiável generalizado, backup VSS independente e teste em PC físico limpo. Não chame fixture de validação em segundo PC.

Não altere outra máquina, checkout, vault, projeto ou runtime. Não faça commit ou push nesta instalação. Termine com evidência por gate: checks de clone, configuração, ACL/DPAPI, health, MCP tools/list, tarefa, túnel externo, Memory V1, aprovações pendentes e limitações.
```

O roteiro é uma instrução de trabalho, não substitui consentimento local para gravações, registro de tarefa, credenciais ou permissões. A pessoa operadora deve confirmar as ações no PowerShell e na OpenAI Platform.
