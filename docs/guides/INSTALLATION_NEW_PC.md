# Instalação portátil por usuário no Windows

Este procedimento prepara Agent e Gateway locais, somente leitura, a partir de um clone. Ele gera identidade e credencial independentes por usuário, exige seleção explícita de cada raiz de projeto e mantém o bind em loopback. O túnel é opcional e pertence ao operador. Registry, Obsidian e escrita MCP continuam como gates separados.

## Requisitos

- Windows 10 ou 11 com PowerShell 5.1 ou PowerShell 7.
- Node.js 22 ou 24, Git, Corepack e pnpm 12.8.1.
- NTFS para raízes que serão inspecionadas com o preflight do Windows.
- Para conexão remota: conta OpenAI Platform com acesso próprio a Secure MCP Tunnel e o `tunnel-client` oficial. Veja [conexão ChatGPT](CHATGPT_MCP_CONNECTION.md).

## Clonar e validar

Use PowerShell não elevado. Instalação e configuração inicial não precisam de Administrador.

```powershell
git clone https://github.com/HenriquePvAr/Nodaris.git
Set-Location .\Nodaris
node --version
corepack pnpm --version
corepack pnpm install --frozen-lockfile
corepack pnpm typecheck
corepack pnpm lint
corepack pnpm test
```

Confirme Node 22 ou 24 e pnpm 12.8.1. Se os checks falharem, pare e resolva a incompatibilidade antes de configurar o runtime.

Para validar Agent/Gateway sem usar configuração ou raízes reais, execute o smoke isolado abaixo. Ele escolhe portas loopback efêmeras, cria uma raiz descartável, confirma health e exige as nove ferramentas de leitura exatas em `tools/list`; no fim encerra os processos próprios e remove a fixture. Ele não testa tunnel-client nem a conta ChatGPT.

```powershell
& .\tests\fixtures\windows\nodaris-portable-runtime-smoke.ps1
```

## Criar configuração local de leitura

O script não lê configuração de outro checkout. O estado deste usuário fica em `%LOCALAPPDATA%\Nodaris\portable`, fora do Git. O token é gerado localmente e protegido com DPAPI `CurrentUser`; o JSON contém apenas identidade, raízes selecionadas, portas loopback e capacidades desligadas. Se a configuração já existir, o script falha sem sobrescrevê-la.

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
.\scripts\windows\nodaris-portable.ps1 configure
.\scripts\windows\nodaris-portable.ps1 doctor
```

Em `configure`, informe cada caminho absoluto de projeto individualmente e confira a lista exibida. Pressione Enter no primeiro prompt para manter a allowlist vazia. O comando exige `CONFIGURE NODARIS` no terminal local antes de gravar a configuração. As raízes precisam existir em NTFS e não podem atravessar reparse points. A allowlist nunca inclui automaticamente a pasta do usuário ou uma raiz de volume. Não compartilhe o token DPAPI nem copie a pasta `portable` para outro perfil ou computador.

`doctor` não inicia processos nem altera tarefas. Ele verifica configuração, versão do Node, dependências e conflitos nas portas locais.

## Iniciar e validar Agent/Gateway

```powershell
.\scripts\windows\nodaris-portable.ps1 start
```

O supervisor obtém um mutex por usuário, recusa portas ocupadas, inicia apenas os executáveis Node do clone atual e confirma o dono das portas. Depois verifica o health autenticado do Agent e executa `initialize`/`tools/list` MCP no Gateway. O token é passado no ambiente privado do processo e removido ao terminar. `start` não encerra nem assume processos preexistentes. Se não for possível identificar o dono de uma porta, o início falha fechado.

Para parar a instância própria, use:

```powershell
.\scripts\windows\nodaris-portable.ps1 stop
```

O comando apenas grava um marcador no diretório privado; o supervisor que detém o mutex observa o marcador e encerra exclusivamente seus processos, após conferir PID, caminho do executável, linha de comando e horário de criação.

## Autostart opcional

A tarefa é por usuário, `RunLevel Limited`, marcada `IgnoreNew` e inicialmente desabilitada. O registro e a ativação são comandos separados:

```powershell
.\scripts\windows\nodaris-portable.ps1 task-install
.\scripts\windows\nodaris-portable.ps1 task-enable
```

O segundo comando exige `ENABLE NODARIS TASK` no terminal local. `task-install` não substitui uma tarefa existente. `task-disable` desabilita a tarefa sem remover configuração; `task-remove` remove somente a tarefa cuja identidade, usuário e comando ainda correspondem exatamente ao clone atual. A configuração local permanece no disco. Verifique `status` antes e depois de qualquer mudança.

```powershell
.\scripts\windows\nodaris-portable.ps1 status
.\scripts\windows\nodaris-portable.ps1 task-disable
```

## Projetos e autorização

Cada raiz escolhida pelo operador é disponibilizada para leitura pelo Agent. Use diretórios de projeto específicos, não uma pasta que contenha outros projetos. Para mudar a seleção, faça backup da configuração local e altere-a manualmente somente após revisar o schema; o instalador não oferece edição destrutiva nesta versão. A máquina recebe um `machineId` aleatório próprio. Não copie IDs, credenciais ou Registry de outra instalação.

## Túnel Secure MCP opcional e ChatGPT

O script não cria recursos de conta OpenAI nem instala o binário. Cada operador instala o `tunnel-client` oficial, verifica o checksum da release e cria/associa seu túnel e runtime API key na própria organização Platform. Depois usa os comandos em [conexão independente ChatGPT](CHATGPT_MCP_CONNECTION.md). O script guarda a chave runtime com DPAPI, gera um perfil de escopo fixo e mantém o túnel desativado até uma aprovação TTY separada. Quando habilitado, o mesmo supervisor gerencia Agent, Gateway e túnel; a única tarefa opcional por usuário inicia esse supervisor. Não reutilize túnel doméstico. Se a conta não disponibilizar Secure MCP Tunnel ou MCP customizado, registre o bloqueio; não exponha o Gateway publicamente nem use outro túnel para contorná-lo.

## Obsidian e Memory V1

Obsidian é opcional. O runtime portátil não cria vault nem grava notas. O procedimento e os limites estão em [Obsidian Memory setup](OBSIDIAN_MEMORY_SETUP.md). Registro do projeto, criação do vault, vinculação, backup verificável, restauração isolada e cada capacidade de escrita requerem gates locais independentes.

Nesta versão, o supervisor portátil mantém Memory Read, Memory Write e Project Write desligados. O fluxo operacional de escrita Windows/VSS ainda não foi generalizado e validado para uma instalação limpa; criação, atualização, append, histórico e recuperação não são prometidos pela configuração portátil. Não habilite variáveis manuais para contornar essa limitação.

## Limites de validação

O fixture exercita DPAPI, ACL e integridade do perfil no usuário que o executa, mas não equivale a uma validação em outro PC físico. Testes do repositório não validam permissões da conta OpenAI, polling real do control plane, tarefa após reboot em outro computador, chamadas MCP do ChatGPT ou Memory V1 operacional. O binário e os recursos de conta devem ser validados na máquina-alvo. A licença PolyForm Noncommercial restringe usos comerciais; consulte [LICENSE](../../LICENSE).

Para o roteiro executável do Claude Code, veja [Claude Code installation handoff](CLAUDE_INSTALLATION_HANDOFF.md). Para falhas, veja [Troubleshooting](TROUBLESHOOTING.md).
