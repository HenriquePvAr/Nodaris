# Nodaris

O Nodaris conecta clientes MCP a pastas de projeto aprovadas pelo operador. O agente local valida cada solicitação e o Gateway publica as ferramentas de consulta por MCP Streamable HTTP, ligado a `127.0.0.1` por padrão.

## Runtime portátil para Windows

O clone oferece uma configuração local por usuário para leitura. Ela gera uma identidade e um token próprios, mantém a allowlist vazia até a seleção explícita de pastas, protege o token com DPAPI e conserva Agent e Gateway em loopback. O túnel Secure MCP é opcional: cada operador usa sua conta, tunnel ID e runtime API key. A conexão do túnel exige confirmação local e usa o supervisor portátil. Veja [instalação em outro PC](docs/guides/INSTALLATION_NEW_PC.md) e [conexão do ChatGPT](docs/guides/CHATGPT_MCP_CONNECTION.md).

```powershell
git clone https://github.com/HenriquePvAr/Nodaris.git
Set-Location Nodaris
corepack pnpm install --frozen-lockfile
corepack pnpm typecheck
corepack pnpm lint
corepack pnpm test
```

Depois dos checks, siga o guia de instalação. A configuração local exige aprovação no PowerShell e não lê credenciais, IDs, Registry, vaults ou políticas de outro computador.

## Limites

- O runtime portátil oferece ferramentas de leitura de projetos e inspeção Git. Ele não concede `memory.write` nem `project.write` e não cria ou altera notas.
- Cada pessoa cria/associa seu próprio túnel no OpenAI Platform. O Gateway não deve ser exposto diretamente à Internet.
- Fixtures não comprovam a instalação em outro PC físico nem chamadas externas no ChatGPT. A validação externa exige o tunnel-client ativo e chamadas reais no workspace do operador.
- O repositório usa PolyForm Noncommercial 1.0.0. É software source-available, não uma licença aprovada pela OSI, e restringe usos comerciais. Consulte [LICENSE](LICENSE), [resumo da licença](docs/legal/LICENSING.md) e [avisos de terceiros](THIRD_PARTY_NOTICES.md).

## Documentação

- [Instalação portátil](docs/guides/INSTALLATION_NEW_PC.md)
- [Handoff para Claude Code](docs/guides/CLAUDE_INSTALLATION_HANDOFF.md)
- [Conexão do ChatGPT](docs/guides/CHATGPT_MCP_CONNECTION.md)
- [Configuração do Obsidian](docs/guides/OBSIDIAN_MEMORY_SETUP.md)
- [Solução de problemas](docs/guides/TROUBLESHOOTING.md)
- [Desenvolvimento](docs/guides/DEVELOPMENT.md)
- [Segurança](docs/security/SECURITY.md)
