# Plano de testes de estabilidade M01.5

Atualizado em 13/10/2026. A conexão real pelo ChatGPT foi confirmada pelo proprietário. Os cenários abaixo ainda não foram executados; este documento não os marca como aprovados.

## Estado antes dos testes

- Agente, gateway e `tunnel-client v0.0.15` estavam ativos em `127.0.0.1:3334`, `127.0.0.1:3333` e `127.0.0.1:8080`.
- O health detalhado mostrou `control-plane: ok/polling`; isso é uma observação pontual, não comprova recuperação de uma queda futura.
- Não foram encontrados serviços Windows, tarefas agendadas, entradas Run ou atalhos Startup com nome Nodaris ou tunnel-client. Início após reinício do Windows não está configurado e requer operação manual.
- A raiz autorizada segue exclusivamente `C:\Users\Dell\Downloads\Nodaris`.
- ACL dos arquivos locais de segredo inclui apenas a conta Windows atual e SYSTEM. A cópia TXT de origem da runtime key ainda estava em Downloads; removê-la manualmente.

## Cenário A — reinício do Windows

**Status: PENDING / NÃO EXECUTADO.**

1. Agendar um período em que o proprietário possa interromper a sessão; salvar os demais trabalhos e confirmar que consegue acessar os segredos locais sem mostrá-los.
2. Antes do reinício, registrar a hora e confirmar `/healthz`, `/readyz` e `/health?details=true` em loopback. Não guardar corpos que possam conter dados além dos campos de estado necessários.
3. Reiniciar o Windows e entrar na conta autorizada.
4. Verificar se existem listeners em `127.0.0.1:3333`, `127.0.0.1:3334` e `127.0.0.1:8080`. Como não há serviço/tarefa configurado, a ausência de listeners é esperada e demonstra que o início automático não está disponível.
5. Iniciar manualmente agente e gateway pelo procedimento local aprovado, mantendo `NODARIS_TOKEN` fora de argumentos e logs e usando somente a raiz autorizada. Iniciar o perfil `nodaris-local` pelo mecanismo de segredo já provisionado.
6. Confirmar `/healthz` e `/readyz` em HTTP 200 e `control-plane: ok/polling` no endpoint local de detalhes.
7. Repetir pelo ChatGPT `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read` (`README.md`), `nodaris_code_search`, `nodaris_git_status` e `nodaris_git_log`. Confirmar que a lista continua limitada a Nodaris.
8. Registrar hora, resultados por etapa e qualquer inicialização manual necessária. O cenário de recuperação manual só passa se MCP e chamadas reais voltarem a funcionar; início automático permanece NOT_CONFIGURED até existir e ser testado uma configuração específica.

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
