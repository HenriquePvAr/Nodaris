# Avisos de componentes de terceiros

Este repositório contém o Nodaris, licenciado pela PolyForm Noncommercial 1.0.0. Os avisos abaixo tratam exclusivamente de componentes de terceiros e não alteram suas licenças.

Required Notice: Copyright Henrique Paiva Araujo

Texto integral da licença: [`LICENSE`](LICENSE) e <https://polyformproject.org/licenses/noncommercial/1.0.0>. Ao redistribuir o Nodaris, forneça aos destinatários o texto integral da licença ou seu endereço, preserve este aviso e todos os avisos aplicáveis.

## Dependências de produção fixadas

| Pacote                         | Versão | Licença declarada | Origem                  |
| ------------------------------ | ------ | ----------------- | ----------------------- |
| `@modelcontextprotocol/node`   | 2.1.1  | Apache-2.0        | npm; pacote oficial MCP |
| `@modelcontextprotocol/server` | 2.3.1  | Apache-2.0        | npm; pacote oficial MCP |
| `zod`                          | 4.6.7  | MIT               | npm                     |

As dependências transitivas de runtime também foram auditadas. Inventário e ressalvas estão em [`docs/legal/DEPENDENCY_LICENSE_AUDIT.md`](docs/legal/DEPENDENCY_LICENSE_AUDIT.md). Os textos de licença e notices devem ser preservados conforme os pacotes originais quando redistribuídos. Nenhum código-fonte de terceiros foi copiado para este repositório.

Dependências de desenvolvimento são ferramentas de construção e teste e não integram o código-fonte distribuído pelo Nodaris como dependências de produção. Caso sejam empacotadas em uma distribuição futura, seus avisos e licenças também deverão ser incluídos.

O executável externo `tunnel-client` v0.0.15 não está incorporado neste repositório nem é instalado como dependência npm. Sua distribuição possui licença Apache-2.0 e inventário/notices próprios; preserve os materiais fornecidos com o binário.
