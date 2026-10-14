# Nodaris — relatório final de validação da M01

**Data:** 14/10/2026<br>
**Branch:** `main`<br>
**HEAD revisado:** `ed96512aa7d458340c3b256648a410f770a1b8e7`<br>
**Classificação:** `READY_WITH_LIMITATIONS`

## 1. Resumo executivo

A M01 entregou um agente local, gateway MCP autenticado, encaminhamento pelo Secure MCP Tunnel e inicialização supervisionada no Windows. A autorização de arquivos continua limitada à raiz Nodaris aprovada neste computador. O proprietário informou que a versão atual foi ativada depois de um reinício planejado; o estado pós-reinício e a recuperação do agente foram relatados por ele. Nesta consolidação, o Codex confirmou o estado do Git e executou as nove ferramentas MCP disponíveis em consultas de leitura.

O núcleo da conexão local está operacional. A classificação não é `PASS` integral porque permanecem resultados parciais e causas não determinadas: o ensaio de Wi‑Fi excedeu o limite de 60 segundos; houve latência histórica de inicialização sem causa conhecida; a primeira falha de health do agente após o reboot não teve causa raiz determinada; e os fingerprints de processos informados como presentes após o reboot não foram reauditados integralmente nesta consolidação.

Este relatório distingue evidência: (a) código/histórico e verificações locais do Codex; (b) chamadas MCP reais executadas pelo Codex nesta sessão; e (c) resultados de ensaios pós-reinício e testes anteriores informados pelo proprietário ou registrados em missões anteriores. Não foram reiniciados processos, serviços, Windows ou rede nesta missão.

## 2. Arquitetura entregue

- **Agente:** valida projetos autorizados e executa as operações locais de filesystem e Git. A API interna usa Bearer e a autorização de projeto é aplicada no agente.
- **Gateway:** expõe o MCP Streamable HTTP em loopback, valida Bearer e encaminha as operações permitidas ao agente.
- **Tunnel-client:** versão fixada `v0.0.15`; abre conexão HTTPS de saída e encaminha ao endpoint MCP local. O gateway mantém o Bearer obrigatório.
- **Supervisor Windows:** inicia agente, gateway e tunnel-client, aplica política de recuperação, mutex, checagens de identidade e telemetria sanitizada.
- **Agendador:** tarefa interativa no logon do usuário atual, nível limitado, instância `IgnoreNew`; o launcher `wscript.exe` inicia o PowerShell sem janela de console. Não usa `SYSTEM` como identidade de execução.
- **Limites de rede:** agente `127.0.0.1:3334`, gateway `127.0.0.1:3333` e tunnel-client `127.0.0.1:8080`. Nenhuma ferramenta Nodaris permite escrita, alteração de Git ou execução arbitrária de shell.
- **Autorização de arquivos:** uma raiz local Nodaris explicitamente autorizada, em configuração privada por computador. A autorização não se transfere para outra máquina.

As nove ferramentas públicas são `nodaris_health`, `nodaris_machines_list`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_code_search`, `nodaris_file_read`, `nodaris_git_status`, `nodaris_git_diff` e `nodaris_git_log`. Os handlers conferidos em [`apps/gateway/src/index.ts`](../../apps/gateway/src/index.ts) e [`apps/agent/src/index.ts`](../../apps/agent/src/index.ts) encaminham somente saúde, listagem, leitura, pesquisa e consultas Git.

## 3. Marcos e commits

O histórico de `main` confirma a sequência abaixo; os hashes completos foram obtidos localmente com `git log`:

| Marco                                            | Evidência no histórico                                                                                                             |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Fundação do MVP local                            | `61d23e3353f758df34807e5fe308f58759240180` — `feat: cria fundacao local segura do Nodaris`                                         |
| Preparação e conexão do Secure MCP Tunnel        | `c79f6c8e2c3dffa652b0b756600b245d16f828aa`, `314a287e59f11aad12389c851f31b63c5c7c4719`, `1e5b1546cb47c510f11ac79d982a3317e01dfca0` |
| Conexão real e consolidação M01.5                | `122ad47917ff8b7dce3cb5b132b5a73513d5003b`                                                                                         |
| PolyForm Noncommercial 1.0.0                     | `3242b96b5435bba177bac8484aad4575c5b0cd5c`                                                                                         |
| Supervisor e launcher invisível                  | `2bf6e05b37dbb273741597f2fc212a28a77cc1e0`, `cc694ff14f2159fabc85c6b3fae1388dd39387c9`                                             |
| Fechamento documental M01.11 e base da auditoria | `488373f37681f7163b5a4bb7a67107e42c0e49d4`                                                                                         |
| Instrumentação precoce do startup                | `b7e6450235b2e52a12a8d7e602d8ab61dd2ad736`                                                                                         |
| Leitor e integração da raiz privada (M12-01)     | `9baae9f161b8a6e99d53ac2497b6401e7961e0a1`, `4263157990f3f32de667139ed91e389a4ba7b837`                                             |
| Loopback e bloqueio de NTFS ADS (M12-02/03)      | `c988cc995cc6a62b19878f9f3156625aa2f6fb41`                                                                                         |
| Limites de pesquisa (M12-04)                     | `8cde70482fb5ad3514d8c9846a48d78a9e708b25`                                                                                         |
| Sanitização de erros (M12-05)                    | `47f8c8d05eae3a208262c4697879dce3aa8ff230`                                                                                         |
| Identidade de processos (M12-06)                 | `c9efccf4e18449c44d9f840bb7332f48661f11ef`                                                                                         |
| Finalização resiliente (M12-07)                  | `ed96512aa7d458340c3b256648a410f770a1b8e7`                                                                                         |

## 4. Correções M12-01 a M12-07

| Achado                                   | Correção publicada e evidência                                                                                                                                                                                                                         | Limite de validação                                                                                                                                                    |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **M12-01 — raiz fixa no supervisor**     | Leitor de raízes por computador com schema estrito, ACL privada, sem fallback; integração antes do início dos serviços. Commits `9baae9f` e `4263157`. A configuração autorizada local foi validada no Windows PowerShell 5.1 com exatamente uma raiz. | A autorização é específica a esta instalação; não prova portabilidade nem autoriza outra raiz.                                                                         |
| **M12-02 — bind fora de loopback**       | Validação fail-closed de host no core, aplicada por agente e gateway. `c988cc9`.                                                                                                                                                                       | Não constitui auditoria de rede de todas as configurações futuras; runtime deve continuar a ser verificado após mudanças.                                              |
| **M12-03 — NTFS Alternate Data Streams** | Rejeição explícita de `:` em caminhos relativos, preservando validações de traversal, `.git`, symlinks e nomes sensíveis. `c988cc9`.                                                                                                                   | Cobertura de fixture e ambiente Windows documentada; não é prova formal contra toda condição TOCTOU.                                                                   |
| **M12-04 — orçamento de pesquisa**       | Limites por chamada: 200 arquivos, 500 entradas, 8 MiB, 5 s, duas pesquisas simultâneas sem fila, blocos de 64 KiB e limite individual de 1.000.000 bytes. Falha genérica, sem resultados parciais. `8cde704`.                                         | Uma operação do sistema operacional já pendente não é cancelada pelo timeout JavaScript; o slot permanece ocupado até ela terminar.                                    |
| **M12-05 — exposição de erros**          | Mensagens públicas convertidas para códigos/mensagens permitidos e sanitizados nas fronteiras do agente e gateway, filesystem e Git. `47f8c8d`.                                                                                                        | A sanitização reduz exposição, mas não equivale a prova formal para todas as mensagens futuras.                                                                        |
| **M12-06 — identidade/PID reutilizado**  | Verificação de PID, horário de criação, executável, linha de comando por hash, usuário por hash, sessão, relação pai e caminho esperado antes de ações de ciclo de vida. `c9efccf`.                                                                    | O proprietário informou que o novo estado pós-reboot contém quatro identidades PASS. Esta consolidação não reexecutou uma comparação integral dos quatro fingerprints. |
| **M12-07 — cleanup e estado terminal**   | Finalização resiliente, persistência de `stopped`/`error`/`degraded` conforme o motivo e o estado dos filhos, manutenção de indicadores de intervenção manual e liberação do mutex em `finally`. `ed96512`.                                            | Testes de fixture não substituem teste de todas as falhas possíveis do sistema operacional ou de persistência física.                                                  |

Documentação técnica relacionada: [`LOCAL_ALLOWED_ROOTS.md`](../security/LOCAL_ALLOWED_ROOTS.md), [`CODE_SEARCH_BUDGETS.md`](../security/CODE_SEARCH_BUDGETS.md), [`SUPERVISOR_FINALIZATION.md`](../security/SUPERVISOR_FINALIZATION.md) e [`SECURITY.md`](../security/SECURITY.md). A auditoria detalhada M01.12 existe como evidência local de trabalho não publicada e não é apresentada como link público.

## 5. Testes automatizados

O relatório da validação de publicação M12-07 fornecido para esta missão registra **43/43 testes PASS**, fixture PowerShell de finalização PASS, parser PowerShell PASS, typecheck PASS, lint PASS, formatação PASS, `git diff --check` PASS e varredura direcionada de segredos PASS. Esses resultados são evidência do Codex em execução anterior; a suíte completa não foi repetida durante a consolidação documental.

As fixtures cobrem, entre outros casos, roots JSON/ACL, paths ADS, limites de pesquisa, respostas sanitizadas e finalização do supervisor. Elas são isoladas e não provam comportamento sob toda condição de hardware/rede em produção. Esta missão fez inspeção documental e chamadas MCP de leitura, não testes destrutivos, de carga, rede ou reinicialização.

## 6. Validação após reinício

**Fonte principal: resultados fornecidos pelo proprietário após reinício planejado.** O comando oficial `nodaris.ps1 status` reportou `SUPERVISOR=running`; agente e gateway `healthy`; tunnel-client `healthy local`; listeners 3333, 3334 e 8080; health local HTTP 200; control plane `ok/polling`; `tunnel_chatgpt_readiness=READY`, motivo `poll_current`. O novo `state.json` foi reportado com `SUPERVISOR_IDENTITY`, `AGENT_IDENTITY`, `GATEWAY_IDENTITY` e `TUNNEL_IDENTITY` em PASS.

O proprietário também reportou uma recuperação automática do agente: um timeout de health `health_transport_error`, tentativa falha, backoff e nova inicialização, seguida de health saudável (`restarts=1`). A recuperação foi bem-sucedida; **a causa raiz do timeout inicial não foi determinada**. Os metadados PASS confirmam presença/resultados do status, mas não substituem uma auditoria independente integral de cada fingerprint.

Histórico anterior: a inicialização já apresentou intervalos elevados entre a tarefa, supervisor, agente e primeiro polling. A instrumentação M01.12.1 foi publicada para registrar checkpoints precoces. O atraso de 7min23,8s entre criação do PowerShell e primeiro evento persistido permaneceu sem causa comprovada; a ausência de registro precoce não prova ausência de execução.

O ensaio M01.11 de reconexão Wi‑Fi permanece **PARTIAL**: desconexão observada de aproximadamente **63,367 s**, acima da meta de 60 s; dez sondagens do observador falharam sem causa conclusiva; a readiness retornou depois. Não reclassificar como PASS por causa do retorno posterior.

Mais contexto e sequências estão em [`STABILITY_TESTS.md`](STABILITY_TESTS.md) e [`DEPLOYMENT.md`](DEPLOYMENT.md).

## 7. Validação independente pelo ChatGPT

O proprietário informou que as nove ferramentas passaram após o reboot. Além disso, nesta consolidação, o Codex executou as nove ferramentas pelo conector Nodaris, todas sem erro (9/9):

1. `nodaris_health` — status `ok`.
2. `nodaris_machines_list` — máquina `online`.
3. `nodaris_projects_list` — um projeto Nodaris autorizado.
4. `nodaris_project_tree` — árvore do projeto retornada.
5. `nodaris_code_search` — resultado local retornado.
6. `nodaris_file_read` — `README.md` lido.
7. `nodaris_git_status` — status retornado; `main` sincronizada, com alterações documentais preexistentes.
8. `nodaris_git_diff` — resposta de leitura retornada.
9. `nodaris_git_log` — commit recente retornado.

As chamadas MCP são evidência direta da conexão disponível nesta sessão. A atribuição específica ao reboot deriva do relato do proprietário e das evidências pós-reinício apresentadas por ele; não se infere que essas chamadas, sozinhas, auditem todos os fingerprints internos.

## 8. Segurança e isolamento

- **Raiz:** configuração local lida pelo leitor publicado no Windows PowerShell 5.1: schema 1, exatamente uma raiz e correspondência com o projeto Nodaris. As ACLs de diretório e arquivo passaram pelos validadores; não foi identificado fallback. Essa raiz não autoriza outras pastas ou computadores.
- **Rede e autenticação:** bind local em `127.0.0.1`; gateway e agente mantêm suas validações Bearer. O tunnel-client estabelece conexão de saída; nenhuma porta pública foi aberta nesta missão.
- **Processos:** o código atual compara identidade e horário de criação antes de operações de ciclo de vida. Resultados de fingerprints pós-reboot foram fornecidos pelo proprietário, sem auditoria integral independente nesta consolidação.
- **Filesystem e pesquisa:** traversal, symlinks/reparse points, `.git`, ADS, arquivos sensíveis, tamanho individual e orçamento agregado são tratados pelo core.
- **Erros e telemetria:** respostas públicas são sanitizadas; eventos locais usam campos enumerados e dependem da ACL privada. Segredos e conteúdo de arquivos não devem entrar em logs.
- **API MCP:** os nove handlers revisados são de consulta. Não existe shell MCP, escrita de arquivo, operação Git mutável ou alteração de branch.
- **Lockfile e licença:** dependências diretas fixadas no `package.json` e lockfile; licença PolyForm Noncommercial 1.0.0 preservada. Nenhum servidor terceiro adicional foi instalado nesta missão.

## 9. Limitações e riscos residuais

1. **M01.11 — rede:** resultado `PARTIAL`; a janela de 60 s foi excedida em 3,367 s e a causa das dez sondagens não foi isolada.
2. **Inicialização:** latências históricas elevadas; checkpoints melhoram a observabilidade, mas a causa original continua `UNCONFIRMED`.
3. **Agente pós-reboot:** recuperação automática reportada; motivo do primeiro `health_transport_error` continua desconhecido.
4. **Identidade:** status pós-reboot informa quatro identidades PASS, mas esta consolidação não comparou novamente cada fingerprint. A identidade deve ser revalidada em mudanças de runtime.
5. **Dependências:** `pnpm audit --prod --json` da validação informada reportou zero vulnerabilidades conhecidas em 21 dependências de produção; a consulta `pnpm audit --prod` disponível nesta sessão também não encontrou vulnerabilidades conhecidas. Dependências de desenvolvimento não estão cobertas por essa conclusão. Advisories futuros, vulnerabilidades não publicadas ou falhas não detectadas continuam possíveis.
6. **TOCTOU:** pode haver intervalo entre validação de caminho/processo e uso efetivo; validações por handle reduzem, mas não eliminam todo risco do ambiente.
7. **Identidade incerta e descendentes:** componentes sem identidade confirmável exigem intervenção manual; processos descendentes fora da árvore observada podem sobreviver em situações excepcionais.
8. **Segredos:** detecção heurística pode não reconhecer todos os formatos; diffs binários têm limites de análise.
9. **Conteúdo não confiável:** arquivos de projeto podem conter prompt injection; autorização de leitura não torna seu conteúdo confiável.
10. **Configuração privada:** segurança depende da integridade contínua das ACLs e do arquivo local; uma raiz nova exige aprovação explícita do proprietário.

Não foram observados nesta consolidação indícios de exploração ativa. Os itens acima são limites e riscos residuais, não afirmações de comprometimento.

## 10. Recomendações operacionais

- Após logon e atualizações, consultar `scripts/windows/nodaris.ps1 status` e aguardar `tunnel_chatgpt_readiness=READY` com polling recente antes de atribuir falha ao plugin.
- Manter `startup-events.jsonl` e suas rotações com ACL privada; registrar somente códigos e tempos sanitizados. Preservar a telemetria de um startup lento antes de outra tentativa.
- Em falha, distinguir tarefa, supervisor, configuração, agente, gateway e túnel usando status local, health e telemetria. Não remover `state.json`, não criar `stop.request` e não usar encerramento genérico de processos.
- Para atualizações, revisar diff, executar testes e validações documentadas, inspecionar staging restrito e só então publicar. Não tratar health do processo antigo como validação do código novo.
- Repetir auditoria de dependências incluindo desenvolvimento antes de releases; revisar advisories por versão e aplicabilidade. Não interpretar zero advisories como garantia de ausência de vulnerabilidades.

## 11. Critérios técnicos para a M02

O encerramento da M01 **não inicia nem aprova automaticamente a M02**. Antes de considerar um segundo computador:

1. Obter autorização explícita nesse computador para uma raiz exata; manter allowlist vazia até a aprovação.
2. Provisionar credenciais, perfil do túnel e ACLs de forma independente; nunca copiar tokens ou configuração privada desta instalação.
3. Validar identidade do usuário/tarefa, bind loopback, autorização por projeto e comportamento fail-closed no próprio destino.
4. Executar testes isolados e chamadas MCP reais após instalação; verificar readiness, recovery, ausência de duplicatas e telemetria sanitizada.
5. Revisar dependências de produção e desenvolvimento, versões fixadas, licenças e advisories antes de distribuir.
6. Avaliar componentes como Serena ou agregadores somente por decisão documentada, isolamento e autorização por projeto; não ampliar para edição, terminal ou acesso de terceiros sem nova revisão.

Até esses gates serem concluídos, a instalação validada é somente a deste computador e da raiz já aprovada.

## 12. Conclusão

**`M01_FINAL_AUDIT=READY_WITH_LIMITATIONS`** para o uso local atual. O projeto está publicado na `main`, a conexão MCP local está funcional, as nove ferramentas de consulta responderam nesta sessão e o proprietário reportou startup e recovery após reboot. Os sete achados M12 estão representados por commits verificáveis até `ed96512`.

Esta classificação não significa ausência de vulnerabilidades, validação integral dos quatro fingerprints pós-reboot, aprovação para outro computador ou início da M02. M01.11 continua `PARTIAL`; causas dos atrasos e do primeiro erro do agente permanecem não determinadas; a cobertura de dependências de desenvolvimento não foi confirmada. Essas limitações devem acompanhar futuras decisões de expansão.

**Fontes técnicas:** [`implantação`](DEPLOYMENT.md), [`estabilidade`](STABILITY_TESTS.md), [`roots locais`](../security/LOCAL_ALLOWED_ROOTS.md), [`orçamentos de pesquisa`](../security/CODE_SEARCH_BUDGETS.md) e [`finalização do supervisor`](../security/SUPERVISOR_FINALIZATION.md). A auditoria detalhada M01.12 é evidência local de trabalho não publicada, sem link público.
