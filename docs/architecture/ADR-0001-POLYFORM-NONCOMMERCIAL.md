# ADR-0001: licença PolyForm Noncommercial

- Estado: Aceita
- Data: 2026-10-13

## Contexto

O titular escolheu distribuir o Nodaris sob termos não comerciais. O projeto precisa distinguir seus próprios direitos dos direitos de dependências e comunicar claramente que código-fonte disponível não equivale a software aprovado pela OSI.

## Decisão

Adotar PolyForm Noncommercial 1.0.0, SPDX `PolyForm-Noncommercial-1.0.0`, com `Required Notice: Copyright Henrique Paiva Araujo`. Manter o texto oficial integral em `LICENSE`, o projeto marcado `private` no manifesto e versões de dependências fixadas. Não copiar código de terceiros sem necessidade e não alterar licenças de dependências.

## Consequências

- Redistribuições devem atender ao texto PolyForm e preservar o aviso obrigatório.
- Uso comercial depende de autorização/licença separada do titular; este ADR não define preço nem canal de venda.
- O projeto é source-available sob restrição de finalidade, não deve alegar aprovação OSI.
- Contribuições externas exigem confirmação explícita dos termos da política e compatibilidade de direitos; a licença desta contribuição não concede por si só autorização para relicenciamento comercial.
- A árvore de dependências deve ser auditada quando versões ou artefatos de distribuição mudarem.

## Referências

- <https://polyformproject.org/licenses/noncommercial/1.0.0>
- <https://spdx.org/licenses/PolyForm-Noncommercial-1.0.0.html>
- <https://opensource.org/osd>
