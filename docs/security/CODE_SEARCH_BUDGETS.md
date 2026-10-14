# Orçamentos da pesquisa de código

A ferramenta `nodaris_code_search` executa a busca no agente local e mantém a autorização de projeto aplicada pelo `ProjectStore`. Cada chamada é independente: quando um orçamento é excedido, a operação falha com mensagem genérica e não devolve os resultados já acumulados.

## Limites por chamada

| Recurso                                                    |          Limite |
| ---------------------------------------------------------- | --------------: |
| Arquivos textuais examinados                               |             200 |
| Entradas de diretório visitadas, incluindo itens ignorados |             500 |
| Bytes realmente lidos no total                             |           8 MiB |
| Tamanho individual existente                               | 1.000.000 bytes |
| Duração observada                                          |      5 segundos |
| Leituras simultâneas                                       |     2, sem fila |
| Tamanho de cada leitura do filesystem                      |          64 KiB |

Arquivos acima do limite individual, binários, sensíveis, inacessíveis ou alterados durante a leitura são ignorados conforme a política existente. Os bytes lidos de arquivos que depois são classificados como binários, sensíveis ou instáveis também contam para o orçamento agregado. Se a busca precisar continuar além do limite de arquivos, entradas ou bytes, ela falha em vez de apresentar um conjunto parcial como completo.

## Limite temporal e operações em andamento

O agente aplica o prazo antes e depois de operações assíncronas e também usa um temporizador para devolver falha sanitizada ao solicitante ao atingir cinco segundos. JavaScript não cancela automaticamente uma operação de filesystem já iniciada. Por isso, uma chamada que excedeu o prazo não inicia novas leituras após a operação pendente retornar; o slot de concorrência permanece ocupado até o worker terminar. As leituras de arquivo são feitas em blocos de até 64 KiB e os diretórios são percorridos por iterador, evitando carregar o conteúdo ou a listagem inteira de uma pasta na memória.

`opendir`, avanço do iterador, `lstat`, `realpath`, `open`, `stat`, `read` e `close` continuam dependentes da conclusão do sistema operacional. Se uma dessas operações ficar bloqueada, a resposta MCP ainda falha no prazo, mas o worker mantém um dos dois slots até a operação pendente se resolver. Essa limitação evita criar uma fila ou workers ilimitados e pode reduzir temporariamente a disponibilidade de novas buscas.

## Segurança preservada

Cada caminho continua sendo validado contra o projeto autorizado, traversal, symlinks, `.git`, Alternate Data Streams NTFS e nomes sensíveis. A extensão permitida, a detecção de conteúdo sensível, o bloqueio de binários e o limite individual de leitura continuam aplicados. A API pública MCP e suas nove ferramentas somente leitura não mudam.

Os testes usam projetos temporários e não acessam a configuração privada, serviços ativos ou portas do Nodaris.
