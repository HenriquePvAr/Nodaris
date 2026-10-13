# Nodaris

## Licença

O Nodaris é disponibilizado sob a [PolyForm Noncommercial 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`). É software com código-fonte disponível sob termos que restringem usos comerciais; não é uma licença aprovada pela Open Source Initiative. Consulte [visão geral do licenciamento](docs/legal/LICENSING.md), [licenciamento comercial](docs/legal/COMMERCIAL_LICENSING.md), [política de contribuições](docs/legal/CONTRIBUTION_POLICY.md) e [avisos de terceiros](THIRD_PARTY_NOTICES.md).

O Nodaris conecta um cliente MCP a projetos locais por meio de um gateway Streamable HTTP e um agente local. O agente aplica as raízes autorizadas, valida caminhos e limita operações; o gateway publica apenas ferramentas de consulta.

## Estado da M01

MVP local versionado em `main`. Em 13/10/2026, o proprietário confirmou uma conexão real pelo ChatGPT ao computador Nodaris: foram chamadas `nodaris_health`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_file_read`, `nodaris_code_search`, `nodaris_git_status` e `nodaris_git_log`. A leitura de `README.md` e a busca retornaram conteúdo local, e foi identificado somente o projeto Nodaris. As ferramentas permanecem somente leitura.

A raiz autorizada para esse ensaio é exclusivamente `C:\Users\Dell\Downloads\Nodaris`; novas instalações continuam sem raízes configuradas por padrão. O agente, gateway e `tunnel-client` estão em loopback. A inicialização automática no Windows não está configurada. Reinício do Windows e recuperação após queda de internet permanecem sem teste; veja [plano de estabilidade](docs/guides/STABILITY_TESTS.md).

## Requisitos

- Windows ou Linux; Node.js 22 ou 24; pnpm 12.
- Repositório oficial: <https://github.com/HenriquePvAr/Nodaris> (`main`).
- Uma chave local `NODARIS_TOKEN` com ao menos 32 caracteres aleatórios.

## Instalação

```powershell
pnpm install
$env:NODARIS_TOKEN = (node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))")
$env:NODARIS_ALLOWED_ROOTS = 'C:\caminho\aprovado'
```

Defina `NODARIS_ALLOWED_ROOTS` somente depois de aprovar conscientemente cada caminho. Múltiplas raízes são separadas por `;`. Não configure a raiz do disco ou uma pasta que contenha projetos que não devam ser consultados. Para não autorizar nenhum projeto, deixe a variável vazia.

Em terminais separados, com as mesmas variáveis de ambiente:

```powershell
pnpm dev:agent
pnpm dev:gateway
```

O agente e o gateway escutam apenas em `127.0.0.1` por padrão. O endpoint MCP é `http://127.0.0.1:3333/mcp` e exige `Authorization: Bearer <NODARIS_TOKEN>`. O token nunca deve ser salvo no Git.

## Ferramentas MCP

`nodaris_health`, `nodaris_machines_list`, `nodaris_projects_list`, `nodaris_project_tree`, `nodaris_code_search`, `nodaris_file_read`, `nodaris_git_status`, `nodaris_git_diff` e `nodaris_git_log`. Todas são somente leitura. Arquivos são limitados a 1 MB, árvores a 500 entradas, diffs a 200 KB e chamadas Git a 5 segundos.

## Qualidade

```powershell
pnpm typecheck
pnpm lint
pnpm format:check
pnpm test
```

Veja [desenvolvimento](docs/guides/DEVELOPMENT.md), [implantação local e inicialização no Windows](docs/guides/DEPLOYMENT.md), [plano de estabilidade](docs/guides/STABILITY_TESTS.md), [autenticação GitHub](docs/guides/GITHUB_AUTH.md), [conexão ChatGPT](docs/guides/CHATGPT_TUNNEL.md), [arquitetura](docs/architecture/ARCHITECTURE.md) e [segurança](docs/security/SECURITY.md).
