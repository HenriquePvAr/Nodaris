# Desenvolvimento local

## Configuração

Use Node 22 ou 24 e pnpm 12. Instale com `pnpm install`. Gere token aleatório de pelo menos 32 caracteres e configure a mesma variável `NODARIS_TOKEN` nos dois processos. Configure `NODARIS_ALLOWED_ROOTS` somente com pastas aprovadas explicitamente; deixe vazia para não descobrir projetos.

## Executar

1. Inicie `pnpm dev:agent` em terminal.
2. Inicie `pnpm dev:gateway` em outro terminal com o mesmo token e raízes.
3. Conecte um cliente MCP Streamable HTTP a `http://127.0.0.1:3333/mcp` com Bearer token.
4. Para parar, use Ctrl+C nos dois processos.

## Verificações

`pnpm typecheck`, `pnpm lint`, `pnpm format:check`, `pnpm test`. Testes usam diretórios temporários e fixture controlado. Para Inspector, iniciar localmente com token/raiz de fixture; nunca fornecer uma raiz real sem autorização.

## Limitações

O agente descobre os projetos ao iniciar; reiniciar o processo refaz a descoberta. O gateway encaminha cada chamada ao agente e não mantém fila de recuperação. Os comandos `pnpm dev:*` são processos interativos e não usam o supervisor. A implantação automática da máquina usa `scripts/windows/` e a tarefa `Nodaris User Session`, documentadas em [DEPLOYMENT.md](DEPLOYMENT.md).

O `tunnel-client` executa seu loop de polling enquanto o processo está ativo. O estado atual `control-plane: ok/polling` confirma comunicação no momento da observação, mas a recuperação após interrupção de rede ainda precisa ser testada. Não presumir reconexão ponta a ponta só porque o processo voltou a responder localmente; verifique o estado do plano de controle e repita chamadas reais do ChatGPT conforme o [plano de estabilidade](STABILITY_TESTS.md).

## Diagnóstico da inicialização Windows (M01.9)

O supervisor grava transições sanitizadas em `%LOCALAPPDATA%\Nodaris\supervisor\startup-events.jsonl`, com três arquivos rotacionados (`.1` a `.3`), limite de 256 KiB por arquivo. A pasta e cada arquivo ficam com ACL protegida para a conta atual e `SYSTEM`. O schema registra timestamp UTC, duração, componente, etapa, tentativa, timeout, backoff, status e `reasonCode` de uma lista fechada. Nunca grava mensagem de exceção, linha de comando, PID, token, header, caminho de projeto ou conteúdo de arquivo. Se a escrita do diagnóstico falhar, o supervisor continua a inicialização e recuperação sem expor o erro bruto.

Para ler a linha do tempo sem abrir conteúdo arbitrário, execute:

```powershell
$path = Join-Path $env:LOCALAPPDATA 'Nodaris\supervisor\startup-events.jsonl'
Get-Content -LiteralPath $path | ForEach-Object { $_ | ConvertFrom-Json } |
  Select-Object timestampUtc, durationMs, component, stage, attempt, timeoutSeconds, backoffSeconds, status, reasonCode |
  Format-Table -AutoSize
```

Eventos `process/started` separam criação do processo de `health/healthy`; o túnel gera `readiness/ready` somente depois que `control-plane` informa polling recente. `/readyz` local isoladamente não prova prontidão para chamadas ChatGPT. A linha do tempo anterior à M01.9 não foi preservada, então não determina a causa dos 2min43s observados. A nova instrumentação fica pronta para o próximo logon; não iniciar, parar ou reiniciar o supervisor só para coletar dados.

Não salve `NODARIS_TOKEN` no repositório, no histórico de comandos ou em argumentos. A inicialização manual deve reutilizar o mecanismo local protegido de segredo e a raiz explicitamente autorizada. Não usar `.env` real nem ampliar `NODARIS_ALLOWED_ROOTS` durante uma recuperação.
