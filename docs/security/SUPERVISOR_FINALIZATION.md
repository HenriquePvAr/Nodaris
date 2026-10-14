# Finalização segura do supervisor

O encerramento é centralizado em `Invoke-NodarisFinalization`, compartilhada entre o supervisor e os fixtures. A função tenta parar cada componente na ordem definida, registra somente códigos enumerados, verifica o estado real de cada filho e tenta persistir o estado terminal antes de liberar o mutex. Uma falha em um filho não interrompe as tentativas dos demais.

## Estados terminais

- `stopped`: solicitado pelo fluxo normal, sem circuit breaker, e todos os componentes foram confirmados encerrados, sem listener local correspondente.
- `degraded`: o circuit breaker está ativo, algum componente continua ativo ou não pôde ser confirmado como encerrado, ou houve necessidade de intervenção manual. O motivo `degraded` prevalece mesmo quando o cleanup encerra todos os filhos com sucesso.
- `error`: ocorreu falha de configuração ou inicialização sem circuit breaker, e todos os filhos foram confirmados encerrados. O estado continua identificando a falha de inicialização; não declara a operação como parada normal.

O supervisor escolhe o estado solicitado antes da finalização: o fluxo normal escolhe `degraded` quando `$circuitOpen` está ativo e `stopped` caso contrário; o fluxo de exceção escolhe `degraded` com circuit breaker e `error` sem ele. A função compartilhada também aceita `degraded` e nunca o rebaixa para `stopped` após cleanup completo.

Os estados `identity_unconfirmed_manual_intervention` e `cleanup_failed_manual_intervention` são preservados por componente. A identidade inconclusiva não autoriza encerramento por PID. O snapshot terminal mantém PID observado, identidade confirmada quando disponível, contador de recuperação e status de intervenção, mesmo após o handle do filho ser removido da lista ativa.

O comando `start` interpreta qualquer um desses estados persistidos como `identity_inconclusive` e bloqueia uma nova instância, mesmo que o supervisor antigo já tenha terminado e a porta pareça livre. Isso evita cobrir a evidência de um possível processo órfão com um novo estado de inicialização.

## Falha de persistência

Se a gravação atômica de `state.json` falhar, a função retorna `persisted=false`, tenta registrar `state_write_failed` pelo gravador de diagnóstico existente e ainda tenta liberar o mutex. O diagnóstico só grava em `startup-events.jsonl` no diretório Nodaris cuja ACL privada é verificada. Não há fallback para diretório temporário, perfil público, permissões ampliadas ou arquivo alternativo.

Se nem o estado nem a telemetria puderem ser gravados, não é possível garantir persistência física. A recuperação exige consulta local de `nodaris.ps1 status`, comparação dos processos por CIM com os dados disponíveis, verificação das portas locais e inspeção sanitizada dos eventos existentes. Não remover arquivos de estado nem encerrar processos cuja identidade não esteja confirmada. Solicitar uma janela de manutenção para diagnóstico manual; não executar `taskkill` por nome ou árvore.

O mutex é liberado no bloco `finally`, inclusive quando cleanup, diagnóstico ou persistência falham. Se a própria operação do sistema operacional para liberar o mutex falhar, o resultado indica `mutexReleased=false` e a telemetria tenta registrar `mutex_release_failed`; o teste isolado verifica a liberação real com um mutex temporário.
