# Obsidian e Memory V1 em uma instalação nova

Obsidian é opcional. Não há migração nem sincronização de vault. Cada pessoa deve criar o próprio vault vazio e manter Registry, IDs, políticas e backup dentro da instalação local daquele computador.

## Preparação segura do vault

Depois de instalar Obsidian por fonte oficial, crie um vault vazio em uma pasta local NTFS dentro de uma área privada do usuário. Não use raiz de volume, diretório compartilhado, OneDrive, symlink, junction ou vault pessoal preexistente. Não coloque `.obsidian`, notas, manifestos VSS ou backups no checkout Git.

Antes de qualquer bind, a implementação local precisa demonstrar: registro do repositório nesse PC; identidade `repositoryId`/`workspaceId` local; identidade física NTFS por volume/File ID; contenção dos ancestrais; ACL privada; ausência de reparse points; escopo aprovado pelo proprietário. Não reutilize IDs do PC do desenvolvedor.

## Estado da portabilidade

O runtime portátil atual desliga Memory Read, Memory Write e Project Write. Os scripts domésticos e o serviço de writer ainda não são uma instalação genérica por usuário: política de vault, localização e provisioning VSS precisam ser parametrizados e testados em Windows limpo. Por isso, não execute `memory-bootstrap`, `memory-bind`, concessão de capability, `home-memory-*`, produção/restauração VSS ou variável `NODARIS_MEMORY_WRITE_V1_ENABLED` em uma instalação nova nesta versão.

O contrato pretendido, ainda sem gate multi-PC aprovado, é:

1. Registrar um projeto localmente após preview e aprovação TTY específica.
2. Criar um vault vazio e validar identidade NTFS/ACL/reparse points.
3. Preparar backup VSS com requester oficial, manifesto completo, hash e restauração em destino isolado.
4. Habilitar Memory Read somente para `repositoryId`, `workspaceId`, `vaultId` e identidade física que o Registry local confirmou.
5. Conceder `memory.write` localmente, separada de `project.write`, somente depois do backup e restore aprovados.
6. O contrato futuro deverá manter CREATE, UPDATE, APPEND e HISTORY em capacidades independentes; DELETE permanece indisponível salvo futura implementação própria. Esses writers ainda não são oferecidos pelo runtime portátil.

Não marque o passo como concluído porque fixture passou, vault existe ou MCP anuncia uma ferramenta. Verifique a operação real, inventário de ferramentas e resultado persistido na máquina-alvo. Uma fixture não é prova de um segundo PC físico.

## Próximo gate técnico

Antes de habilitar Memory V1 em multi-PC, falta concluir e validar: política/manifesto configuráveis por instalação; provisionamento de ACL e identidade sem IDs codificados; serviço writer com localização privada por usuário e autorização Registry local; backup VSS e recuperação genéricos; provas concorrentes e crash recovery; teste em conta Windows e clone limpos; aprovação TTY por operação. Até esse gate, use o runtime somente para leitura de arquivos de projeto e não vincule o vault.

Veja também [instalação nova](INSTALLATION_NEW_PC.md), [conexão ChatGPT](CHATGPT_MCP_CONNECTION.md) e [troubleshooting](TROUBLESHOOTING.md).
