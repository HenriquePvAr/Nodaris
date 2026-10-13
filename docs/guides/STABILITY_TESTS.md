# Plano de testes de estabilidade M01.9

Atualizado em 13/10/2026. A conexão real pelo ChatGPT e a inicialização silenciosa após novo logon foram confirmadas pelo proprietário. A queda/restauração da internet e a recuperação após encerramento inesperado de serviços continuam pendentes.

## M01.10 — recuperação controlada (B1.2 concluída)

**Estado: B1.2 concluída; Fase B2 aguarda autorização específica.** A inspeção anterior da Fase A está registrada abaixo como histórico. Nesta janela, foi executada uma única parada supervisionada e, após comprovação do encerramento, uma única inicialização oficial da versão corrigida. Nenhum restart adicional, falha provocada, reinício do Windows ou interrupção de rede foi executado.

### Evidência da transição B1.2 — 13/10/2026

- A pré-validação confirmou os PIDs antigos (supervisor 5000, agente 20212, gateway 19788, tunnel-client 9308), identidade dos componentes e listeners. A tentativa histórica anterior de parada incompleta não foi repetida como segunda tentativa nesta janela; o procedimento autorizado foi monitorado de ponta a ponta.
- A solicitação oficial de parada ocorreu às 16:28:11.404. `stop.request` foi criado às 16:28:13.718 e permaneceu presente durante o encerramento. Os listeners foram liberados; o estado chegou a `stopped` às 16:28:18.079. O comando confirmou a parada às 16:28:20.549, após 9,15 s. Os processos antigos foram confirmados encerrados, sem processos Nodaris órfãos e sem listeners nas portas 3333, 3334 e 8080.
- A inicialização oficial foi solicitada às 16:30:07.976. A tarefa `Nodaris User Session` iniciou o supervisor corrigido sem janela visível. Novos PIDs: supervisor 9376, agente 7036, gateway 12508 e tunnel-client 11312. Cada componente apareceu uma vez; os listeners permaneceram em loopback e corresponderam aos processos esperados.
- O supervisor registrou as transições no `startup-events.jsonl`. O readiness primeiro reportou `control_plane_not_polling` e depois `poll_current`; `tunnel_chatgpt_readiness=READY` foi observado às 16:30:55.494, 47,52 s após a solicitação de início. A health autenticada do agente e a saúde local dos serviços passaram. A telemetria não incluiu credenciais ou conteúdo de arquivos.
- Após a transição, o proprietário confirmou quatro chamadas reais do ChatGPT pelo Nodaris MCP: `nodaris_health` (ok, 1 projeto), `nodaris_projects_list` (Nodaris localizado), `nodaris_file_read` (`README.md`) e `nodaris_git_status` (`main` sincronizada com `origin/main`; somente `docs/status/` não rastreado). Essa confirmação fecha a validação ponta a ponta da B1.2; não é inferida apenas de health local ou polling.
- O snapshot de PIDs/readiness acima é evidência da janela B1.2; não foi feita nova leitura nem ciclo de processos após a revalidação informada pelo proprietário. `docs/status/` foi preservado sem alteração.

**Resultados B1.2:** `STOP_RECOVERY=PASS`; `START_RECOVERY=PASS`; `TUNNEL_READINESS=PASS`; `CHATGPT_REVALIDATION=PASS` (quatro chamadas reais confirmadas pelo proprietário). **Fase B2:** `PENDING_OWNER_AUTHORIZATION` para restart e recuperação após falha controlada. Não iniciar esses testes sem autorização específica.

### Histórico da inspeção da Fase A

A consulta local anterior confirmou a tarefa `Nodaris User Session` habilitada em `Ready`, usuário Dell, logon `Interactive`, nível `Limited`, política `IgnoreNew`, ação `wscript.exe` com `launcher.vbs`. A árvore então mostrava supervisor PID 5000, agente PID 20212 (filho Node PID 18440), gateway PID 19788 (filho Node PID 13560) e tunnel-client PID 9308. O status indicava saúde local e túnel `READY` (`ok/polling`, `poll_current`); `startup-events.jsonl` ainda não existia porque aquela sessão antecedia o supervisor instrumentado. A primeira consulta de arquivos protegidos foi limitada pelo sandbox; a consulta local autorizada subsequente confirmou o estado. Nenhum processo foi iniciado, parado ou encerrado durante aquela inspeção.

**Falhas de implementação corrigidas na Fase A:** a recuperação de filho abria o circuito após uma única tentativa malsucedida, embora a política anunciasse até cinco retries. Agora o helper percorre tentativas, registra cada backoff e só abre o circuito ao atingir o limite. O comando `restart` também aguardava apenas dois segundos após `stop`; agora exige estado terminal confirmado em até 30 segundos e cancela o reinício se não houver confirmação. A parada final do supervisor usa uma única função que mantém a ordem tunnel-client → gateway → agente.

O harness PowerShell isolado cobre parada em ordem e continuação após falha parcial, falha de porta/health e recuperação, sequência de reinício, backoff 5/15/30/60/120 e cancelamento durante backoff, circuito aberto, mutex verificado por outro processo PowerShell, integridade do log sanitizado e rejeição de componentes fora do escopo. O comando `node --import tsx` foi validado sem iniciar serviços. Os fixtures não exercitam uma árvore de servidor real nem provam recuperação após falha inesperada; a parada supervisionada real e a inicialização corrigida foram comprovadas na B1.2, enquanto restart e falha provocada seguem pendentes da Fase B2.

`tunnel_chatgpt_readiness=READY` confirma polling recente do cliente ao control plane, mas isoladamente não demonstra chamada MCP ponta a ponta. Na B1.2, essa lacuna foi fechada pelas quatro chamadas reais confirmadas pelo proprietário após a transição.

### Gate da Fase B2

O próximo ensaio afetará os serviços atuais; seus PIDs precisam ser validados novamente no início de uma janela autorizada. A B1.2 não autoriza novo restart, encerramento controlado de processos, reinício do Windows ou teste de rede.

Sequência proposta para B2, sujeita a autorização específica: (1) capturar status, saúde, PIDs, readiness e fim do JSONL; (2) executar um restart oficial e confirmar término dos PIDs antigos antes dos novos; (3) em autorização separada ou incluída expressamente, encerrar um PID filho validado por PID e relação com o supervisor, observando evento, backoff e readiness; (4) confirmar status e solicitar revalidação real pelo ChatGPT. A B1.2 já validou a parada e inicialização controladas, portanto não repetir esse ciclo como parte do registro atual.

#### Plano de medição B2 (não executado)

- **Snapshot antes/depois de cada cenário:** timestamp UTC e local; saída sanitizada de `nodaris.ps1 status`; `state.json`; PIDs, executáveis, horários de criação e relações pai-filho; proprietários/listeners em 3333, 3334 e 8080; estado da tarefa; readiness; posição/tamanho e últimas linhas sanitizadas do JSONL. Não registrar argumentos/ambiente com segredos nem conteúdo de arquivos.
- **`RESTART_RECOVERY`:** após validar identidade de todos os processos atuais, executar uma vez `nodaris.ps1 restart`. Limites: stop confirmado em até 30 s; observar inicialização por até 25 min, cobrindo o pior caso documentado de aproximadamente 23min30s para seis tentativas. Confirmar ausência dos PIDs antigos e órfãos antes de aceitar novos PIDs; exigir uma instância por componente, listeners apenas em loopback, health autenticada e `tunnel_chatgpt_readiness=READY`.
- **`PROCESS_FAILURE_RECOVERY`:** um componente por vez, com janela e autorização expressa. Antes de provocar falha, validar PID, caminho executável, horário de criação, pai supervisor, papel do processo e listener quando aplicável. Encerrar somente o PID exato do filho autorizado; nunca usar nome genérico. Aguardar recuperação e health antes do próximo componente.
- **`DUPLICATE_PROTECTION`:** com os serviços saudáveis e snapshot inicial registrado, chamar uma vez `nodaris.ps1 start`. O resultado esperado é “Supervisor Nodaris já está em execução”, sem PID novo; comparar supervisor/mutex, processos por identidade, PIDs em `state.json` e listeners antes/depois. A tarefa mantém `IgnoreNew`. Interromper diante de PID inesperado, segunda instância, listener sem correspondência ou estado divergente; não iniciar outro supervisor manualmente.
- **`BACKOFF` e `TELEMETRY`:** comparar timestamps dos eventos `recovery/failed`, `recovery/backoff`, `recovery/started`, `health` e `readiness` com a política de até cinco retries e atrasos 5/15/30/60/120 s. Em circuito aberto, interromper e não insistir; preservar eventos e coletar diagnóstico sanitizado.
- **Limites e critérios de interrupção:** stop >30 s, timeout de health por tentativa (45 s agente/túnel; 30 s gateway), readiness não alcançada em 25 min no restart, ou recuperação individual sem health após o limite de retries/backoff (até cerca de 10 min). Interromper também em circuito aberto, erro de autenticação, porta não liberada, processo órfão, duplicidade, PID reutilizado/divergente, bind fora de loopback ou evento/log inconsistente. Ao interromper, não repetir stop nem matar outros processos; recolher snapshot e decidir a recuperação com o proprietário.
- **Recuperação e fechamento:** usar somente o mecanismo oficial `nodaris.ps1 status|start|stop|restart`; `start` apenas após comprovar ausência do supervisor anterior, ausência de listeners e ausência de órfãos. Não executar start automático após falha de restart. Depois de cada cenário, confirmar health/readiness, revisar telemetria sanitizada e solicitar ao proprietário as chamadas MCP reais (`health`, projetos, leitura README e Git status). Registrar resultado independentemente por cenário.

Referência histórica de indisponibilidade: aproximadamente 2–4 minutos para stop/start ou restart saudável, baseada na amostra M01.8 de 2min43s até o agente, sem causa comprovada. Na B1.2, a parada confirmou em 9,15 s e o readiness do túnel foi observado 47,52 s após a solicitação de início. Recuperação de falha individual acrescenta o backoff corrente (agente 15s pela contagem atual; gateway e túnel 5s) e até 45s de health. O pior caso de startup, com seis tentativas e todos os timeouts/backoffs no limite, é aproximadamente 23min30s. A parada controlada tem limite de confirmação de 30 segundos; em timeout, `restart` cancela e não lança uma segunda instância.

Recuperação manual: consultar `scripts/windows/nodaris.ps1 status`; se o stop/restart não confirmar, não abrir outro supervisor nem encerrar processo por nome. Registrar a saída sanitizada e pedir orientação antes de qualquer intervenção fora do procedimento. Critérios de interrupção: timeout de parada, porta ainda ocupada, PID inesperado, evento `circuit_open`, readiness perdida ou comportamento diferente do processo autorizado.

**Resultados:** parada/inicialização e revalidação ChatGPT da B1.2 estão PASS com evidências reais acima. `RESTART_RECOVERY=PENDING_OWNER_AUTHORIZATION`; `PROCESS_FAILURE_RECOVERY=PENDING_OWNER_AUTHORIZATION`. Fixtures não substituem os ensaios reais pendentes.

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

**Status: PASS para início automático e chamadas ChatGPT; diagnóstico histórico limitado.** Em 13/10/2026, o proprietário confirmou novo logon sem janela e chamadas locais após o reinício. `LastRunTime` foi 15:17:17, `LastTaskResult=0`, supervisor iniciado às 15:17:45 e os processos descendiam do supervisor. A amostra M01.8 registrou o agente 2min43s após o supervisor, com `restartCount=1`. Os logs detalhados do Agendador estavam desabilitados e o estado do supervisor só retinha o snapshot mais recente, portanto a causa não pode ser determinada retroativamente. A telemetria M01.9 ficará disponível no próximo logon, que não será iniciado automaticamente.

1. Agendar um período em que o proprietário possa interromper a sessão; salvar os demais trabalhos e confirmar que consegue acessar os segredos locais sem mostrá-los.
2. Antes do reinício, registrar a hora e confirmar `/healthz`, `/readyz` e `/health?details=true` em loopback. Não guardar corpos que possam conter dados além dos campos de estado necessários.
3. Reiniciar o Windows e entrar na conta autorizada.
4. Verificar a execução da tarefa habilitada e listeners em `127.0.0.1:3333`, `127.0.0.1:3334` e `127.0.0.1:8080`.
5. Se a tarefa não iniciar a pilha, use o comando de status e anote o erro sem coletar conteúdo de segredo; não amplie allowlist nem desative Bearer.
6. Confirmar `/healthz` e `/readyz` em HTTP 200 e `control-plane: ok/polling` no endpoint local de detalhes.
7. Repetir pelo ChatGPT `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read` (`README.md`), `nodaris_code_search`, `nodaris_git_status` e `nodaris_git_log`. Confirmar que a lista continua limitada a Nodaris.
8. Registrar hora, resultados por etapa e qualquer inicialização manual necessária. O proprietário confirmou conectividade após restart e ausência de console no novo logon; a instrumentação agora prepara a captura detalhada no próximo logon.

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

## Observabilidade M01.9

Os eventos são gravados em `%LOCALAPPDATA%\Nodaris\supervisor\startup-events.jsonl`, mais três arquivos rotacionados, limitados a 256 KiB cada. ACL protegida: usuário atual e SYSTEM. O JSONL registra timestamp UTC, duração, componente, estágio, tentativa, timeout, backoff, status e motivo enumerado. Mensagens de exceção, linhas de comando, PIDs, credenciais e conteúdo de projeto são excluídos.

O fixture Windows `tests/fixtures/windows/diagnostics-smoke.ps1` cobre tentativa falha, backoff agendado, saúde do túnel pendente/pronto/obsoleto, rejeição de motivos livres, sanitização do schema, rotação e ACL. Isso não inicia agente/gateway/túnel reais. Para coletar a causa dos 2min43s, aguardar a próxima inicialização natural e analisar transições `process`, `health`, `backoff` e `readiness`; não reiniciar o PC, serviço ou rede para gerar a amostra.

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

| Cenário                         | Estado atual                                     | Evidência necessária para PASS                                                                                                               |
| ------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Conexão real ChatGPT            | PASS, confirmada pelo proprietário em 13/10/2026 | Sete ferramentas; leitura de README e busca com dados locais; projeto Nodaris exclusivo                                                      |
| Reinício do Windows             | PASS                                             | Proprietário confirmou tarefa automática silenciosa e consultas locais pelo ChatGPT; latência fina pendente da próxima amostra instrumentada |
| Queda e restauração de internet | PENDING                                          | Estado do polling durante/depois, tempo até recuperação e chamadas reais após a restauração                                                  |

Não alterar o dashboard `docs/status/` durante esses ensaios sem aprovação específica; atualizar este registro e `docs/PROJECT_BOARD.md` com resultados observados.
