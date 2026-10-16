<!-- SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# WIN-02A — preparação do computador pessoal

## Estado e limites

Este guia prepara o diagnóstico e um plano para um computador Windows pessoal. WIN-02A não instala
o Nodaris, não cria tarefa, não configura raízes, não provisiona identidade/credenciais/túnel e não
conecta o ChatGPT. O teste read-only feito no Dell descreve somente o Dell. `HOME_INSTALL_READY=NO`
até que todos os critérios WIN-02B sejam observados no computador de destino.

O comando `home-preflight.ps1` é independente de Node e pnpm, para conseguir reportar quando eles
estiverem ausentes. Use Windows PowerShell 5.1 no contexto do usuário atual, sem “Executar como
administrador”. Nenhum comando deste guia foi executado no PC pessoal.

## 1. Preparar o computador e obter o checkout

1. Confirme que está no computador pessoal e que tem acesso local à sessão Windows.
2. Escolha manualmente uma pasta de trabalho dedicada. Não use `C:\`, `C:\Users`, Desktop,
   Documents, Downloads ou OneDrive inteiros como raiz autorizada.
3. Obtenha o repositório versionado por um canal Git confiável, na branch `main`. Exemplo de
   comando a executar no PC pessoal após decidir a pasta:

   ```powershell
   git clone https://github.com/HenriquePvAr/Nodaris.git "$env:USERPROFILE\Projects\Nodaris"
   Set-Location "$env:USERPROFILE\Projects\Nodaris"
   git status --short --branch
   git rev-parse HEAD
   ```

   O clone é uma ação manual no computador de destino; nenhum acesso a credenciais ou conteúdo de
   outro projeto é necessário. Verifique a licença PolyForm Noncommercial antes de usar/distribuir.

4. Confirme que o checkout está limpo, na `main`, e que `pnpm-lock.yaml` e
   `pnpm-workspace.yaml` estão presentes. Se a origem, branch, integridade ou lockfile não puderem
   ser confirmados, pare.

## 2. Pré-requisitos e inventário

Para o piloto assistido, use Windows 10/11 x64, Node 22 ou 24 e pnpm 12, conforme os engines e o
`packageManager` fixados no repositório. O usuário comum poderá precisar instalar pnpm
temporariamente no piloto. O destino comercial deverá dispensar essa instalação manual; isso
depende de um spike de empacotamento ainda não feito.

Arquivos-fonte necessários: `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `tsconfig.json`,
`apps/`, `packages/`, `scripts/`, testes, documentação, `LICENSE` e `THIRD_PARTY_NOTICES.md`.
Dependências são instaladas no próprio PC com lockfile após aprovação futura. Não copiar `node_modules`
do Dell.

Não incluir `.env` real, tokens, runtime keys, perfis de túnel, arquivos de estado, logs privados,
`allowed-roots.json`, projetos corporativos ou qualquer vault Obsidian pessoal. Não foi criado ZIP:
um archive do Git seria somente fonte, não autossuficiente; falta testar instalação limpa e dependências
precisam ser instaladas no destino. Nenhum hash de pacote existe.

## 3. Executar o preflight real

Na raiz do checkout, execute os modos separadamente e guarde a saída JSON localmente apenas se
necessário. A saída não contém caminhos, contas, SIDs, PIDs, argumentos, tokens nem conteúdos:

```powershell
$preflight = Join-Path (Get-Location) 'scripts\windows\home-preflight.ps1'
$target = (Get-Location).Path
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight inspect -TargetPath $target
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight plan -TargetPath $target
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight validate -TargetPath $target
```

Cada checagem traz `PASS`, `BLOCKED`, `INCONCLUSIVE` ou `NOT_CHECKED`, além de código enumerado.
`INCONCLUSIVE` e `NOT_CHECKED` não contam como aprovação. Uma porta ocupada precisa de proprietário
identificado; identidade desconhecida bloqueia. Um bind não loopback bloqueia. Configuração privada
presente gera bloqueio de reutilização; o preflight verifica presença e não abre o conteúdo.

Exemplo sanitizado (ilustrativo, não é resultado do PC pessoal):

```json
{
  "overallStatus": "INCONCLUSIVE",
  "checks": [
    { "name": "node", "status": "BLOCKED", "code": "NODE_MISSING" },
    {
      "name": "port_3333",
      "status": "INCONCLUSIVE",
      "code": "PORT_OWNER_OR_BIND_IDENTITY_UNCONFIRMED"
    },
    {
      "name": "user_scope_write_access",
      "status": "NOT_CHECKED",
      "code": "NO_WRITE_PROBE_PERFORMED"
    }
  ],
  "effectsPerformed": false,
  "privateFileContentsRead": false
}
```

O modo `plan` lista o que uma futura instalação aprovada faria, incluindo rollback. Ele sempre
retorna `installationAllowed=false` e não executa nada. Não tente corrigir automaticamente qualquer
bloqueio; registre o código e peça revisão antes da WIN-02B.

## 4. Identidade, raízes e túnel — somente após outra autorização

Não gere identidade ou segredos na máquina de trabalho. Em missão posterior e no próprio PC pessoal:

- Criar identidade por instalação independente; `HOME_DEVICE_ID`, `HOME_NODARIS_TOKEN`,
  `HOME_LOCAL_ROOTS` e `HOME_TUNNEL_PROFILE` são nomes de responsabilidades, ainda não variáveis
  públicas fechadas.
- Gerar/provisionar token Bearer e runtime key localmente, com ACL privada, sem serial de hardware,
  argumentos, logs, Git ou chat.
- Obter aprovação explícita para uma única raiz, idealmente o checkout pessoal do Nodaris.
- Configurar túnel/perfil com credenciais próprias e `http://127.0.0.1:3333/mcp`; não abrir portas
  inbound e não reutilizar `tunnel_id` automaticamente.
- Nomear distintamente as conexões Dell e pessoal no ChatGPT. Não há roteamento multi-PC automático.
- Não criar vault Obsidian ainda. Isso só pode ser proposto depois de MEM-02 implementar aprovação
  local confiável, ACL e proteção de reparse points nativas, backup/recuperação e conflitos com
  editores. Dados pessoais e corporativos ficam separados.

## 5. Rollback proposto para WIN-02B

Rollback não é automatizado. Se houver instalação parcial, dependência ausente, token não provisionado,
túnel indisponível, conflito de porta/tarefa, processo desconhecido, supervisor falho, checkout
inconsistente ou raiz não aprovada:

1. Pare a validação e preserve a saída sanitizada do preflight.
2. Não encerre processo por nome, não remova tarefa ou estado preexistente, não apague credenciais,
   vault ou dados pessoais.
3. Reidentifique executáveis, horários de criação, usuário, sessão, pai/filho e proprietários de
   portas. Se houver dúvida, interrompa e peça revisão.
4. Em janela separada, peça autorização para desabilitar somente a tarefa que o piloto comprovou
   ter criado e parar processos por identidade validada.
5. Remova apenas artefatos cujo caminho e criação pelo piloto forem comprovados; preserve configuração
   de usuário e qualquer arquivo preexistente. Não modificar o Dell.

## 6. Checklist de aceite WIN-02B

- [ ] Diagnóstico foi executado no PC de destino; Dell não foi usado como substituto.
- [ ] Windows, arquitetura, Node/pnpm, checkout limpo e espaço foram confirmados.
- [ ] Tarefa, mutex, processos e cada porta tiveram identidade conclusiva; listeners são loopback.
- [ ] Instalação por usuário sem elevação foi validada sem afetar recursos existentes.
- [ ] A instalação usou lockfile fixo e não trouxe projetos, dados ou dependências do Dell.
- [ ] Tarefa/supervisor e configuração/credenciais independentes foram aprovados e validados.
- [ ] Só existe uma raiz pessoal explicitamente autorizada.
- [ ] Túnel próprio está `LIVE/READY` e nenhuma porta pública/inbound foi criada.
- [ ] As nove ferramentas MCP permanecem somente leitura; ChatGPT consultou o host pessoal real.
- [ ] Rollback foi ensaiado em janela autorizada e preservou tudo que não foi criado pelo piloto.
- [ ] Identidade do endpoint no ChatGPT é inequívoca; não se presume roteamento multi-PC.

Até todos os gates passarem no computador pessoal: `HOME_INSTALL_READY=NO`,
`HOME_INSTALL_EXECUTED=NO`, `SECOND_PC_CONNECTED=NO`.
