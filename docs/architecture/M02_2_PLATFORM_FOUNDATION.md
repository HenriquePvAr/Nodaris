<!-- SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# Fundação de plataforma da M02.2

## Estado e limite

Esta etapa introduz contratos TypeScript independentes de sistema operacional e fakes
determinísticos em `tests/fixtures/platform/`. Não há implementação nativa, detecção automática do
host, integração com o agente/gateway, nem mudança no supervisor Windows. Windows, macOS e Linux
são representados pelos contratos; uma plataforma desconhecida não recebe capacidades por
inferência.

Os contratos não concedem autorização por si. Capacidades precisam ser explicitamente habilitadas;
as capacidades futuras `workspace.write.approved` e `test.run.approved` são sempre negadas nesta
etapa, mesmo que apareçam em uma lista informada pelo chamador. Nenhuma ferramenta MCP, rota,
handler de escrita, shell ou operação Git mutável foi criada.

## Módulos

- `platform/types.ts`: nomes de plataformas e arquiteturas, capacidades, falhas sanitizadas e
  decisão deny-by-default.
- `platform/platform-info.ts`: representação da plataforma, arquitetura e capacidades observadas;
  o provider de detecção é apenas um contrato.
- `platform/path-policy.ts`: diferencia referência fornecida pelo chamador, validação nativa em
  runtime e decisão reportada pelo adaptador. Bloqueios modelados incluem traversal/fora da raiz,
  symlink, reparse point, NTFS ADS, alias, ambiguidade e verificação indisponível. Não substitui o
  filesystem seguro da M01.
- `platform/credential-store.ts`: contrato de guardar, resolver, rotacionar e excluir referências.
  Uma implementação futura pode avaliar DPAPI/Credential Manager, Keychain ou Secret Service; esta
  etapa não acessa cofres e não permite fallback para texto simples.
- `platform/process-supervisor.ts`: estados, identidade verificável e política de recuperação. Uma
  identidade diferente ou inconclusiva nunca autoriza encerramento. Não executa ações de processo.
- `platform/autostart-manager.ts`: capacidades e planejamento/consulta de instalação, ativação,
  desativação e remoção. O plano exige aprovação do usuário; não altera Agendador, launchd ou
  systemd.
- `platform/private-state-store.ts`: contrato de leitura/gravação versionada e requisito explícito
  de substituição atômica e ACL privada ou permissões POSIX. Nenhum estado real é aberto ou gravado.
- `platform/local-approval.ts`: separa solicitação de registro de decisão. Valida formato, escopo e
  prazo para diagnóstico, sem aceitar um campo `trusted-local` como prova de origem.

Falhas de adaptador contêm apenas códigos enumerados, sem mensagem de exceção, caminho ou segredo.
Os tipos de capacidade abrangem leitura (`metadata.read`, `project.read`, `code.search`, `git.read`,
`workspace.diff.read`), administração (`team.manage`, `member.invite`, `member.remove`,
`grant.manage`) e capacidades futuras de escrita/teste. A enumeração é vocabulário, não concessão.

## Fakes e isolamento

As classes `Fake*` existem exclusivamente em `tests/fixtures/platform/fakes.ts`; são importadas
somente pelos testes. Usam memória e valores de fixture, não acessam filesystem privado, processos,
serviços, rede ou credenciais reais. Os testes também verificam que os entrypoints ativos não
importam os fakes e que o contrato MCP da M01 mantém nomes, propriedades de entrada e anotação
somente leitura.

Não há configuração, variável de ambiente, factory ou composição de produção que selecione um fake.
Os contratos não implementam canonicalização ou persistência: indisponibilidade ou verificação
inconclusiva deve resultar em negação.

## Limites de confiança

Uma solicitação `LocalApprovalRequest` representa apenas a intenção enviada pelo solicitante. Um
payload remoto fabricado com campos extras como `status: APPROVED` ou `approvalChannel:
trusted-local` não cria um registro de decisão. Mesmo um `LocalApprovalDecisionRecord` com status
aprovado, escopo correspondente e prazo válido é marcado como `unverified-record`; a avaliação
informa formato/escopo/tempo e se o registro aparenta estar vigente, mas
`effectiveAuthorization` permanece literalmente `false`. A autorização real segue indisponível até
existir uma origem local verificável e um verificador
confiável, planejados para decisão e implementação futura da M02.4. Não há interface de aprovação
nem ferramenta MCP nesta etapa.

`RootReference` também é apenas uma referência estrutural do chamador: `projectId` e string de caminho
não provam allowlist, canonicalização ou containment. Uma futura implementação de `PathPolicy`
precisa validar no sistema operacional a raiz autorizada e cada caminho, incluindo containment,
symlinks, reparse points, ADS e aliases. O resultado `authorized` só pode ser emitido por esse
adaptador após verificações efetivas; objetos ou marcas TypeScript não são controles de segurança.
Como não há adaptador nativo nesta missão, os testes usam fake inconclusivo por padrão e demonstram
que uma referência fornecida pelo chamador não concede acesso.

## Verificações

Com as dependências já instaladas, executar na raiz do repositório:

```powershell
pnpm test
pnpm typecheck
pnpm lint
pnpm format:check
```

Os testes da camada ficam em `tests/platform-foundation.test.ts`. A suíte de integração MCP usa
projetos temporários, portas efêmeras em loopback e processos de teste encerrados no teardown; não
usa o runtime operacional nem suas raízes privadas.

## Próximos passos fora desta entrega

Antes de cada implementação nativa, comparar pacote, biblioteca, processo MCP e implementação
própria, verificar licença/versão/dependências/segurança e documentar a decisão. Implementar
providers separados para Windows, macOS e Linux com fakes ainda isolados; integrar ao core apenas
após testes de contrato e revisão de segurança. A experiência desktop/headless, empacotamento,
armazenamento de credenciais, persistência, autostart e qualquer escrita supervisionada seguem
abertos e não são decididos por esta fundação.
