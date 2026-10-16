<!-- SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# Plano do piloto Windows Home (WIN-01)

## Resultado desta preparação

Esta etapa não instala nem configura outro computador. A leitura dos scripts Windows da M01
mostra componentes portáveis em escopo de usuário (`LOCALAPPDATA`, launcher VBS invisível e tarefa
`Nodaris User Session`), mas também acoplamentos que precisam ser resolvidos antes de um piloto:

- O supervisor atual contém a raiz autorizada da instalação Dell; não copiar essa configuração.
- A tarefa, o mutex e o estado são locais à máquina/usuário, mas seus nomes e caminhos podem colidir
  com uma instalação existente no mesmo perfil.
- As portas atuais são 3333 (gateway), 3334 (agente) e 8080 (UI/health do tunnel-client), todas
  destinadas a loopback; qualquer ocupação deve bloquear a instalação.
- O tunnel-client `v0.0.15`, perfil `nodaris-local`, `tunnel_id` e runtime key são específicos da
  instalação e não podem ser copiados. Um `tunnel_id` não comprova roteamento multi-dispositivo.
- O Bearer é secreto local e não deve ser reutilizado. A configuração de raízes deve ser criada
  explicitamente para o novo dispositivo e conter somente a raiz escolhida pelo proprietário.
- Node/pnpm são ferramentas atuais de desenvolvimento/instalação assistida. A versão final deve
  dispensar pnpm manual; empacotamento ainda depende de spike.
- Instalação, diagnóstico e remoção atuais focam o Windows Dell. Rollback completo em outra máquina
  ainda não foi comprovado.

O módulo `inspectWindowsHome` em `packages/core/src/windows-home-preflight.ts` avalia um snapshot
fornecido pelo chamador e retorna códigos sanitizados. É puro: não consulta Windows, não inicia
processos, não abre listeners e não altera arquivos. `ready` significa apenas que os fatos
fornecidos não revelam bloqueios; não substitui uma sonda real, instalação nem prova de
identidade/dispositivo. `conflictingPath` é um fato fornecido pelo chamador, assim como tarefa,
portas e instância; resultados incorretos ou incompletos não são detectados por este avaliador.

## Pré-condições para WIN-02

1. Proprietário presente no PC pessoal e autorização explícita da pasta de projeto escolhida.
2. Checkout `main` revisado; não importar estado, tokens, chaves ou perfil de túnel do Dell.
3. Confirmar Node `>=22 <25` e pnpm 12 na instalação assistida, ou usar artefato empacotado validado.
4. Confirmar que tarefa, mutex e instância Nodaris não conflitam; listener apenas em loopback.
5. Criar identidade local nova, Bearer novo e configuração privada com ACL restrita ao usuário/SYSTEM.
6. Provisionar um túnel e runtime key independentes por procedimento oficial e interação do proprietário.
7. Aplicar allowlist vazia por padrão; aprovar somente a raiz pessoal selecionada.
8. Executar smoke tests isolados, depois validar agente/gateway, nove ferramentas MCP e recuperação.
9. Testar remoção/rollback em janela autorizada sem apagar dados do usuário.

### Gates de portabilidade para WIN-02

- [ ] Medir os pré-requisitos em Windows suportado, sem confiar apenas em snapshot declarado.
- [ ] Instalar por artefato reproduzível; o usuário comum não deve precisar instalar pnpm manualmente.
- [ ] Fazer spike e registrar decisão de empacotamento; Tauri, Electron, SEA ou alternativa seguem em aberto.
- [ ] Demonstrar estado limpo quando tarefa, path, portas, identidade, credenciais ou túnel não forem verificáveis.
- [ ] Testar com paths contendo espaços, caracteres Unicode, instalação não padrão e perfil sem pnpm.
- [ ] Confirmar remoção/rollback e preservar configurações preexistentes não criadas pelo piloto.
- [ ] Separar compatibilidade do snapshot puro de evidência de instalação e operação real.

## Procedimento proposto

1. Registrar snapshot sanitizado de Git, dependências, tarefa, processos, portas e caminhos.
2. Parar somente instalação Nodaris identificada naquela máquina; se identidade ou estado forem
   inconclusivos, interromper. Não tocar na instalação Dell.
3. Preparar diretórios privados antes de escrever segredos/configuração; gerar identidade e credencial
   novas pelo mecanismo escolhido e conferir ACLs.
4. Revisar plano de instalação e raízes com o proprietário. Não provisionar diretório pai nem home
   inteiro por conveniência.
5. Configurar túnel independente, preservar autenticação Bearer e iniciar pelo mecanismo suportado.
6. Validar listeners loopback, health autenticado, readiness e consultas reais autorizadas.
7. Fazer rollback só com autorização: desabilitar tarefa da instalação pessoal, encerrar processos
   por identidade validada, confirmar portas liberadas, preservar dados/diagnósticos e remover
   somente artefatos criados pelo piloto.

## Critérios

**PASS do piloto:** dependências, identidade/credenciais próprias, ACL privada, uma raiz explicitamente
aprovada, listeners loopback, nove ferramentas compatíveis, túnel independente, recuperação e
rollback foram observados no segundo PC. **FAIL:** exposição externa, identidade divergente, acesso
fora da raiz, credencial reutilizada ou falha de autorização. **PARTIAL:** componente não observado
ou evidência incompleta. Até WIN-02, `WIN_HOME_READINESS=PARTIAL` e `SECOND_PC_CONNECTED=NO`.

Nenhuma configuração do Dell é alterada por este plano.

## Preflight local WIN-02A

`scripts/windows/home-preflight.ps1` é um diagnóstico nativo PowerShell 5.1 separado dos scripts
operacionais M01. `inspect` coleta facts somente leitura; `plan` imprime operações futuras sem
executá-las; `validate` resume o estado e os bloqueios. Cada verificação usa `PASS`, `BLOCKED`,
`INCONCLUSIVE` ou `NOT_CHECKED`. Códigos e contagens são sanitizados: o script não imprime caminhos,
nomes de usuário, SIDs, PIDs, argumentos, valores de segredos ou conteúdos de arquivos privados.
Perfis, configuração de raízes e arquivos privados são avaliados somente pela presença. Uma
configuração já presente é bloqueio para não reutilizá-la automaticamente.

O agregador nativo PowerShell e `inspectWindowsHomeChecks` em
`packages/core/src/windows-home-preflight.ts` usam o mesmo contrato de checks e a mesma regra:
qualquer bloqueio gera `BLOCKED`, e estado `INCONCLUSIVE`/`NOT_CHECKED` nunca vira `PASS`. A suíte
compara os resultados serializados do fixture PowerShell com o avaliador TypeScript. O CLI continua
nativo para poder informar que Node está ausente sem depender de Node/tsx para iniciar.

No Dell, a execução read-only de 16/10/2026 identificou Windows 10 x64, Node 24, pnpm 12 e espaço
livre acima do limiar de 2 GiB. A preparação foi corretamente `BLOCKED`: checkout com alterações
locais, tarefa e mutex existentes, quatro processos Nodaris identificados, portas ocupadas pela
instalação existente, configuração de raízes e dados privados presentes. Nenhum conteúdo privado
foi lido. Isso caracteriza o Dell e não comprova qualquer estado do PC pessoal.

O preflight não testa escrita só para descobrir permissões; acesso de escrita em escopo de usuário
fica `NOT_CHECKED` até um piloto autorizado. A prontidão de polling do plano de controle também não
é sondada, e `/readyz` local não prova ChatGPT. Uma porta ocupada por processo identificado é
`BLOCKED`; proprietário/identidade não confirmados ficam `INCONCLUSIVE` e também impedem prosseguir.
Nenhuma tarefa, mutex, listener ou processo é criado para testar conflito.

## Distribuição e inventário

Não há artefato ZIP autossuficiente nem instalador nesta etapa. Um ZIP criado do Git seria apenas
um pacote de código-fonte; a instalação assistida requer Windows PowerShell 5.1, checkout versionado,
Node 22 ou 24, pnpm 12 e `pnpm install --frozen-lockfile`. Não copiamos `node_modules` do Dell, e
nenhum teste de instalação limpa foi executado. O piloto depende de rede/registry para instalar
dependências e de provisionamento manual separado para credenciais/túnel.

Inventário previsto: arquivos rastreados do repositório (`package.json`, `pnpm-lock.yaml`,
`pnpm-workspace.yaml`, configuração TypeScript, `apps/`, `packages/`, `scripts/`, documentação e
avisos de licença). Excluir `.git`, `node_modules`, `.env*` real, credenciais, perfis do tunnel-client,
estado, diagnósticos, roots config, projetos não Nodaris e qualquer vault Obsidian pessoal.
O artefato não foi gerado, logo não há SHA-256 de pacote a reportar.

## Gates de aceitação WIN-02B

- [ ] Executar o preflight no PC pessoal e revisar cada `BLOCKED`, `INCONCLUSIVE` e `NOT_CHECKED`.
- [ ] Confirmar identidade da instalação e usuário, tarefa, mutex, processos, portas e bind loopback.
- [ ] Obter checkout limpo da `main`, Node suportado, pnpm 12 e lockfile íntegro.
- [ ] Instalar somente após autorização separada; sem admin, tarefas ou serviço antes da revisão.
- [ ] Provisionar identidade/token/configuração de raízes novos e uma única raiz explicitamente aprovada.
- [ ] Provisionar perfil/túnel/runtime key independentes; demonstrar readiness sem expor segredos.
- [ ] Validar as nove ferramentas read-only e a conexão ChatGPT inequívoca para este computador.
- [ ] Provar rollback em janela autorizada, removendo apenas artefatos criados pelo piloto.
- [ ] Manter `HOME_INSTALL_READY=NO` até todos os gates serem observados no PC de destino.

O primeiro vault Obsidian pessoal é uma etapa futura, separada e condicionada ao MEM-02: aprovação
local confiável, ACL nativa, proteção de reparse points, backup/recuperação e política de conflitos.
Não vincular conteúdo pessoal a projetos corporativos automaticamente.
