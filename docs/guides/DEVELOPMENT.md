# Desenvolvimento local

## Configuração

Use Node 22 ou 24 e pnpm 12. Instale com `pnpm install`. Gere token aleatório de pelo menos 32 caracteres e configure a mesma variável `NODARIS_TOKEN` nos dois processos. Configure `NODARIS_ALLOWED_ROOTS` somente com pastas aprovadas explicitamente; deixe vazia para não descobrir projetos.

## Executar

1. Inicie `pnpm dev:agent` em terminal.
2. Inicie `pnpm dev:gateway` em outro terminal com o mesmo token e raízes.
3. Conecte um cliente MCP Streamable HTTP a `http://127.0.0.1:3333/mcp` com Bearer token.
4. Para parar, use Ctrl+C nos dois processos.

## Verificações

`pnpm typecheck`, `pnpm lint`, `pnpm format:check`, `pnpm test`. Testes usam diretórios temporários e fixture controlado. Para Inspector, iniciar localmente com token/raiz de fixture; nunca fornecer uma raiz real sem autorização.

## Limitações

O agente mantém a descoberta até reiniciar. A M01 não tem instalação de serviço Windows, UI, reconexão automática, gestão de tokens, rotação ou transporte autenticado mTLS entre processos. O token bearer local deve ser tratado como segredo.
