# Plano de testes de estabilidade M01.8

Atualizado em 13/10/2026. A conexão real pelo ChatGPT e a inicialização silenciosa após novo logon foram confirmadas pelo proprietário. A queda/restauração da internet e a recuperação após encerramento inesperado de serviços continuam pendentes.

## Estado antes dos testes

- Agente, gateway e `tunnel-client v0.0.15` estavam ativos em `127.0.0.1:3334`, `127.0.0.1:3333` e `127.0.0.1:8080`.
- O health detalhado mostrou `control-plane: ok/polling`; isso é uma observação pontual, não comprova recuperação de uma queda futura.
- Na inspeção M01.7, foi registrada `Nodaris User Session`, habilitada, com gatilho `AtLogOn`, usuário `Dell`, logon `Interactive` e nível `Limited`. Listeners loopback já estavam ativos, por isso nenhum serviço foi parado ou reiniciado. O supervisor ainda não foi executado.
- A raiz autorizada segue exclusivamente `C:\Users\Dell\Downloads\Nodaris`.
- ACLs verificadas para `gateway-token.txt` e `secrets/control-plane-api-key.txt`: permissões FullControl somente para a conta atual e SYSTEM. A remoção do TXT temporário de Downloads continua sendo ação manual do proprietário.

## Tarefa de logon e supervisor

**Estado: inicialização automática silenciosa confirmada; testes de interrupção pendentes.** Os scripts em `scripts/windows/` criam tarefa no logon interativo do usuário atual, nível `Limited`, sem `SYSTEM`. A definição não contém segredos. A inicialização é sequencial: agente (health autenticado), gateway (listener de loopback), tunnel-client (perfil fixado). Uma única instância é solicitada pelo Agendador e mutex local; conflito de porta interrompe a tentativa em vez de abrir outro listener.

Use `scripts/windows/nodaris.ps1 install|start|stop|restart|status|enable|disable|uninstall`. A instalação não inicia nem encerra processos ativos. O supervisor observa somente a saída dos próprios processos, usa backoff 5/15/30/60/120 segundos e abre circuito após cinco tentativas. Ele não reinicia tunnel-client por perda de internet: o cliente v0.0.15 documenta polling com retry/backoff de erros de transporte ([código/documentação oficial](https://github.com/openai/tunnel-client/blob/v0.0.15/pkg/controlplane/doc.go)); health/readiness precisam ser observados após a restauração. Essa capacidade documentada ainda não substitui o teste real de queda/restauração.

Os processos Nodaris/tunnel-client estavam ativos na revisão, então validar `stop`/`restart` depende de janela aprovada pelo proprietário. Não executar esses comandos até obter autorização específica para interromper os processos ativos.

## Smoke checks M01.7 — 13/10/2026

- Parser PowerShell: `nodaris.ps1` e `supervisor.ps1` passaram.
- Agendador: tarefa consultada com `Ready`, habilitada, `User=Dell`, `RunLevel=Limited`, `LogonType=Interactive`, gatilho `MSFT_TaskLogonTrigger`; `disable` retornou `Enabled=False` e `enable` restaurou `Enabled=True`. Nenhuma execução manual foi solicitada.
- Estado local: status mostrou portas 3333, 3334 e 8080 escutando em loopback, supervisor sem estado (não executado). `/healthz` e `/readyz` responderam HTTP 200.
- Credenciais: ACL dos arquivos Bearer/runtime API key e do perfil protegidas contra herança, FullControl somente para os SIDs da conta atual e SYSTEM. Foi detectado que o perfil mantinha a runtime key como valor literal; sem exibir/copiar esse valor, ele foi substituído por `file:` apontando ao arquivo protegido e o perfil recebeu ACL restrita. `tunnel-client admin tunnels get` read-only usando a chave carregada somente em memória do arquivo protegido retornou sucesso, sem usar a cópia TXT de Downloads. `doctor` confirmou perfil, tunnel ID, referência da API key e alvo MCP; resultado global FAIL apenas pelo conflito no bind `127.0.0.1:8080`, já ocupado pelo tunnel-client ativo. Saídas com metadados foram descartadas e nenhuma chave foi impressa.
- Validação automatizada: `pnpm typecheck`, `pnpm lint`, `pnpm format:check`, `pnpm test` (9/9) e `git diff --check` passaram; parser dos dois scripts passou. Smoke status confirmou tarefa habilitada e conta/SID esperado, supervisor ainda não executado, nove ferramentas no gateway, raiz Nodaris fixa e health local `/readyz` HTTP 200.
- Queda/restauração de internet, reinício do Windows, stop/restart e chamada real pelo ChatGPT após esses eventos não foram testados.

## Cenário A — reinício do Windows

**Status: PARCIAL.** Em 13/10/2026, o proprietário confirmou chamadas ChatGPT locais após reinício (`health`, lista de projetos, leitura de README e Git status). A tarefa estava `Running`; seu último resultado era `0x41301`, que indica execução em andamento. Os PIDs dos três serviços tinham como ancestral o PowerShell iniciado por `svchost.exe` do Agendador. A tarefa executou realmente, mas deixou uma janela visível. Após instalar o launcher invisível, falta novo logon para confirmar ausência da janela.

1. Agendar um período em que o proprietário possa interromper a sessão; salvar os demais trabalhos e confirmar que consegue acessar os segredos locais sem mostrá-los.
2. Antes do reinício, registrar a hora e confirmar `/healthz`, `/readyz` e `/health?details=true` em loopback. Não guardar corpos que possam conter dados além dos campos de estado necessários.
3. Reiniciar o Windows e entrar na conta autorizada.
4. Verificar a execução da tarefa habilitada e listeners em `127.0.0.1:3333`, `127.0.0.1:3334` e `127.0.0.1:8080`.
5. Se a tarefa não iniciar a pilha, use o comando de status e anote o erro sem coletar conteúdo de segredo; não amplie allowlist nem desative Bearer.
6. Confirmar `/healthz` e `/readyz` em HTTP 200 e `control-plane: ok/polling` no endpoint local de detalhes.
7. Repetir pelo ChatGPT `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read` (`README.md`), `nodaris_code_search`, `nodaris_git_status` e `nodaris_git_log`. Confirmar que a lista continua limitada a Nodaris.
8. Registrar hora, resultados por etapa e qualquer inicialização manual necessária. O proprietário confirmou conectividade após restart e ausência de console no novo logon; ainda falta observar perda/restauração de internet.

## Cenário C — launcher invisível e readiness do túnel

**Status: PASS para logon silencioso e conexões ChatGPT; telemetria de tempos parcial.** Em 13/10/2026, após novo logon, o proprietário confirmou ausência de janela e reteste ChatGPT. A tarefa teve `LastRunTime=15:17:17`, código `0`; PowerShell supervisor iniciou `15:17:45`. Processo supervisor → agente/gateway/tunnel-client foi confirmado pela árvore de processos. Não há log detalhado de todas as transições: o Operational do Agendador está desabilitado e o arquivo de estado do supervisor mantém somente o estado mais recente.

### Sequência e latência observadas (hora Manaus)

| Marco                                           | Horário  | Evidência                                                       |
| ----------------------------------------------- | -------- | --------------------------------------------------------------- |
| Último início registrado da tarefa; resultado 0 | 15:17:17 | `Get-ScheduledTaskInfo`; código 0 observado depois              |
| Supervisor PowerShell iniciou                   | 15:17:45 | horário de início do processo e PID pai dos serviços            |
| Agente iniciou                                  | 15:20:28 | árvore de processos; estado atual `restartCount=1`              |
| Gateway iniciou                                 | 15:20:43 | árvore de processos                                             |
| tunnel-client iniciou                           | 15:20:46 | árvore de processos; processo v0.0.15                           |
| Último despacho na amostra                      | 15:21:01 | telemetria do dispatcher; não indica o primeiro despacho        |
| Poll bem-sucedido da amostra                    | 15:29:07 | `last_success` no endpoint de health                            |
| Snapshot saudável observado                     | 15:29:17 | `ready=true`, `ok/polling`, 0 falhas, seis despachos concluídos |

Latências derivadas: 28s entre o horário registrado da tarefa e início do supervisor; 2min43s do supervisor ao agente; 15s do agente ao gateway; 3s do gateway ao tunnel-client. O último despacho na amostra ocorreu 15s após o início do tunnel-client. O horário do primeiro polling/dispatch não está disponível. O log não explica a espera de 2min43s e o horário da primeira mensagem de timeout não foi registrado; não inferir relação causal entre os eventos.

`/readyz` HTTP 200 representa health local do tunnel-client e não prova polling ao plano de controle. Antes de usar o plugin, execute `scripts/windows/nodaris.ps1 status` e aguarde `tunnel_chatgpt_readiness=READY`, que requer `ok/polling` e último sucesso recente, calculado pela janela de espera efetiva + deadline publicada pelo cliente. Após isso, faça uma chamada de health e reteste qualquer chamada que falhar. Essa prontidão não prova que o transporte MCP foi totalmente observado pelo endpoint local: a telemetria registrou `mcp=unknown` por ausência de evidência do transporte, mesmo com chamadas reais confirmadas pelo ChatGPT.

## Cenário B — perda e restauração de internet

**Status: PENDING / NÃO EXECUTADO.**

1. Executar em uma janela de teste com acesso local ao computador. Manter os processos Nodaris ativos e confirmar o estado saudável e uma chamada real de referência pelo ChatGPT.
2. Interromper temporariamente o acesso externo à internet usando um método reversível escolhido pelo proprietário. Não alterar firewall, portas inbound, allowlist, credenciais ou configurações do gateway.
3. Observar localmente `/healthz`, `/readyz` e somente os campos de estado do componente `control-plane` em `/health?details=true`. Não registrar headers, tokens, corpos MCP ou logs HTTP brutos.
4. Anotar se o processo continua vivo, como o plano de controle reporta a falha e se o MCP remoto fica temporariamente indisponível. Não classificar uma falha durante o corte como defeito de segurança nem como reconexão aprovada.
5. Restaurar a internet. Aguardar `control-plane: ok/polling` e readiness local; anotar o tempo de recuperação.
6. Repetir as sete chamadas reais do ChatGPT listadas no Cenário A e confirmar leitura e busca de dados locais apenas do projeto Nodaris.
7. O cenário só passa se a mesma instalação se recuperar sem ampliar acesso, desativar Bearer ou reiniciar/reconfigurar manualmente componentes fora do procedimento previsto. Se for necessária intervenção manual, documentar o resultado como recuperação manual e revisar a meta antes de marcar PASS.

## Registro de resultado

| Cenário                         | Estado atual                                     | Evidência necessária para PASS                                                                           |
| ------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| Conexão real ChatGPT            | PASS, confirmada pelo proprietário em 13/10/2026 | Sete ferramentas; leitura de README e busca com dados locais; projeto Nodaris exclusivo                  |
| Reinício do Windows             | PENDING                                          | Observações antes/depois do reinício, início manual ou automático identificado, chamadas reais repetidas |
| Queda e restauração de internet | PENDING                                          | Estado do polling durante/depois, tempo até recuperação e chamadas reais após a restauração              |

Não alterar o dashboard `docs/status/` durante esses ensaios sem aprovação específica; atualizar este registro e `docs/PROJECT_BOARD.md` com resultados observados.
