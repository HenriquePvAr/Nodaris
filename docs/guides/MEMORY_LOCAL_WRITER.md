<!-- SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# Writer local de memória — estado do MVP

## Escopo executável

`MemoryVaultStore` em `packages/core/src/memory/store.ts` fornece preview, aprovação por política
injetada, criação/atualização Markdown, leitura por ID, lista de missões, histórico de eventos e
resumo de continuidade. O teste grava arquivos reais apenas em `mkdtemp` sob o diretório temporário
do sistema e os remove no teardown. Não configure nem passe vault pessoal/corporativo.

Exemplo conceitual de composição para testes:

```ts
const store = new MemoryVaultStore(tempVault, isolatedApprovalFake, tempVaultSecurityFake);
const proposal = await store.createMission(draft); // somente preview
const receipt = await store.approve(proposal); // aprovação da fixture
await store.apply(receipt); // gravação Markdown no vault temporário
```

Este exemplo não é CLI de produção. Não existe comando de autoaprovação, configuração por variável
de ambiente, daemon, serviço ou ferramenta MCP para escrita. A política real de aprovação local e
verificação de ACL Windows ainda não existe. Sem essas políticas, a escrita deve permanecer
desabilitada.

## Quatro fronteiras de escrita

| Fronteira                                          | Estado nesta etapa                                                                                |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Persistência temporária em fixtures de teste       | Permitida apenas nos diretórios temporários criados pelo teste e removidos no teardown.           |
| Gravação em vault pessoal expressamente autorizado | Não habilitada; a autorização do vault não substitui aprovação por operação nem validação de ACL. |
| Escrita iniciada por MCP/ChatGPT                   | Não implementada; nenhuma ferramenta MCP de escrita é registrada.                                 |
| Edição geral de código ou arquivos do projeto      | Fora do escopo do writer; as ferramentas M01 continuam somente leitura.                           |

Essas fronteiras não se promovem automaticamente entre si. Uma futura gravação em vault pessoal
precisa de política local confiável, verificação Windows de ACL/reparse points e tratamento de
conflito com Obsidian e outros editores; uma chamada MCP exigirá revisão e autorização próprias.

## Conflitos e recuperação

Criação usa destino exclusivo; repetição do mesmo receipt na instância retorna o documento já
aplicado. Atualização requer revisão/hash esperado, lock cooperativo e troca por rename. Escritas
concorrentes cooperantes com a mesma revisão permitem um vencedor; a outra recebe conflito. Arquivos
com hardlinks múltiplos e diretórios com symlinks/junctions observáveis são rejeitados. Um conflito
ou falha antes da troca preserva a nota anterior. A rotina não apaga notas anteriores. Como um editor
humano não respeita o lock, ainda existe uma janela TOCTOU entre última verificação e rename; isso
impede habilitar o writer em vault real até um adaptador nativo CAS/ACL ser validado.

Notas são Markdown com frontmatter JSON/YAML 1.2, IDs restritos e corpo literal. Backlinks podem ser
representados por relações tipadas e links `[[ID]]`, mas leitura de links/backlinks não concede
permissão de filesystem. Ao restaurar, copiar o vault completo de backup; não reconstruir registros
de logs ou de contexto de chat.

## Próximos passos seguros

1. Implementar verificador Windows de reparse points, ACL e criação de diretório privada.
2. Implementar canal local interativo de aprovação, vinculado a vault, operação, revisão e prazo.
3. Acrescentar histórico append-only obrigatório de transições de estado e journaling/recuperação.
4. Validar frontmatter, tipos e experiência Properties no Obsidian real sem usar vault pessoal como fixture automatizada.
5. Só depois propor CLI local explícita; não assumir integração com ChatGPT.
6. Criar ferramentas MCP em etapa separada, inicialmente leitura e sob autorização de projeto.

As ferramentas M01 permanecem somente leitura e sem alteração de schema/nome.
