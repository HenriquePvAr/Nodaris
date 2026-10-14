# Identidade segura dos processos Windows

O estado do supervisor registra evidências mínimas para comparar processos, sem persistir caminho privado, linha de comando ou SID em texto aberto. São armazenados PID, horário UTC de criação, sessão, PID pai e hashes SHA-256 do executável, da linha de comando, do SID e do caminho do script quando aplicável.

O comando `start` só considera uma instância ativa quando a identidade persistida coincide com a observada, o executável e o script correspondem à instalação, usuário e sessão são compatíveis com o contexto atual e a tarefa agendada corresponde ao launcher e ao usuário esperados. A verificação do mutex não espera por sua liberação. Estado antigo sem esses metadados não identifica um processo.

Antes de iniciar serviços, o supervisor consulta sua própria identidade pelo mesmo provedor CIM/.NET. Se essa verificação prévia falhar, nenhum filho é iniciado. Após `Start-Process`, o PID retornado é registrado no estado antes da consulta de identidade. O horário de criação lido pelo handle retornado é comparado com a consulta posterior, para detectar troca do PID durante a coleta. Se a consulta falhar, o componente é marcado para intervenção manual, o evento sanitizado usa o código controlado `process_start_failed` e a política abre o circuit breaker sem retry nem tentativa de encerramento por PID.

Estados ausentes ou corrompidos, consulta de identidade inconclusiva, mutex ocupado sem identidade confirmada e portas ocupadas por processo desconhecido bloqueiam uma nova inicialização. A recuperação de estado obsoleto só é considerada quando o processo original não existe ou o PID foi reutilizado por processo não correspondente e mutex e portas estão livres.

Antes de encerrar um filho, o supervisor compara novamente a identidade com a registrada. O encerramento usa o objeto de processo individual e não percorre a árvore de descendentes. Se a identidade não puder ser confirmada, o supervisor não encerra o PID. Descendentes não confirmados podem manter uma porta ocupada; nesse caso a parada falha fechada e requer diagnóstico manual.

No caso excepcional em que um filho foi criado, mas sua identidade não pôde ser obtida, o PID observado e o estado de intervenção ficam registrados sem linha de comando, caminho ou SID. O cleanup recusa encerrar esse filho. Se ele mantiver uma porta aberta, o manager classifica os recursos como ambíguos e bloqueia novas inicializações até diagnóstico manual.

Os hashes não substituem ACLs. O arquivo de estado permanece no diretório privado do Nodaris. A implementação não altera a tarefa agendada nem inicia, para ou reinicia serviços por conta própria; sua adoção depende do fluxo de operação autorizado.
