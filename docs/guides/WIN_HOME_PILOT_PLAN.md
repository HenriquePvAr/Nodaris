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
