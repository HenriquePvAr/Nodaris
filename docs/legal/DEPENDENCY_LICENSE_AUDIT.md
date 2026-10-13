# Auditoria de licenças de dependências

Snapshot local da M01.6 — 13/10/2026. As versões abaixo foram verificadas no manifesto/lockfile e na instalação local; elas não representam garantia sobre versões futuras. Revalidar antes de atualizar ou distribuir.

## Escopo e método

Inventário derivado de `package.json`, `pnpm-lock.yaml`, `pnpm licenses list` e metadados `package.json`/arquivos de licença da árvore pnpm instalada. Contagens distinguem nome-versão, pois pacotes duplicados em versões diferentes contam separadamente. Dependências opcionais e específicas de plataforma podem variar conforme ambiente.

Foram observadas 157 combinações nome-versão no grafo instalado: 6 de runtime e 153 de desenvolvimento, incluindo duplicações de versões entre dependências. As licenças declaradas no grafo foram MIT (120), Apache-2.0 (20), ISC (7), BSD-2-Clause (6), BSD-3-Clause (2), BlueOak-1.0.0 (1) e Python-2.0 (1). Metadados de licença estavam presentes para as entradas verificadas. Doze entradas não tinham arquivo de licença na raiz do pacote instalado; portanto, confirme e obtenha o texto de licença upstream antes de empacotar essas ferramentas. A lista e contagem são fotografia do ambiente, não inventário universal de todas as plataformas.

## Dependências diretas

| Escopo          | Pacote                         | Versão fixada | Licença declarada |
| --------------- | ------------------------------ | ------------- | ----------------- |
| Runtime         | `@modelcontextprotocol/node`   | 2.1.1         | Apache-2.0        |
| Runtime         | `@modelcontextprotocol/server` | 2.3.1         | Apache-2.0        |
| Runtime         | `zod`                          | 4.6.7         | MIT               |
| Desenvolvimento | `@eslint/js`                   | 9.37.0        | MIT               |
| Desenvolvimento | `@modelcontextprotocol/client` | 2.3.1         | Apache-2.0        |
| Desenvolvimento | `@types/node`                  | 24.7.2        | MIT               |
| Desenvolvimento | `eslint`                       | 9.37.0        | MIT               |
| Desenvolvimento | `prettier`                     | 3.6.2         | MIT               |
| Desenvolvimento | `tsx`                          | 4.20.6        | MIT               |
| Desenvolvimento | `typescript`                   | 5.9.3         | Apache-2.0        |
| Desenvolvimento | `typescript-eslint`            | 8.71.2        | MIT               |
| Desenvolvimento | `vitest`                       | 5.0.4         | MIT               |

Dependências transitivas observadas diretamente no runtime incluem `@modelcontextprotocol/core` 2.3.1 (Apache-2.0), `@hono/node-server` 1.19.17 (MIT) e `hono` 4.13.13 (MIT). Consulte sempre o lockfile e a árvore instalada para as demais entradas transitivas e suas versões exatas.

## Decisão e ressalvas

Não foi identificado código-fonte de dependências copiado ao repositório. Não foi observada licença copyleft no grafo instalado analisado, mas esta constatação não substitui revisão jurídica nem auditoria de artefatos de distribuição. Licenças de terceiros não são substituídas pela PolyForm do Nodaris.

As ferramentas de desenvolvimento não são dependências runtime do Nodaris. Se uma distribuição futura as incluir, ou incluir binários e dependências transitivas, gere inventário da distribuição concreta e preserve todos os avisos e textos aplicáveis. O `tunnel-client` v0.0.15 é ferramenta externa separada, fora do grafo pnpm e do repositório; sua distribuição informa Apache-2.0 e deve conservar os notices fornecidos com o binário.
