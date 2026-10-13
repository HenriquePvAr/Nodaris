# Segurança

## Modelo de ameaças

Entradas MCP e arquivos do projeto são dados não confiáveis. O agente limita os projetos às raízes configuradas; o gateway não acessa filesystem diretamente. O gateway e o agente usam bearer token compartilhado; bind local padrão limita acesso à máquina.

## Controles atuais

- Allowlist vazia por padrão e descoberta só dentro das raízes configuradas.
- IDs de projeto validados; traversal, caminhos absolutos, `.git`, symlinks e nomes de segredo bloqueados.
- Tipos textuais selecionados, NUL/binary e arquivos >1 MB recusados; árvore e busca limitadas.
- Comandos Git executados sem shell, com timeout, buffer limitado e somente subcomandos de consulta.
- Diff limitado a 200 KB e recusado quando há arquivo sensível alterado ou padrões de credenciais.
- MCP valida Host/Origin de localhost, bearer token exigido, respostas `no-store`; logs não incluem conteúdo de arquivo.
- Tools são somente leitura e não há terminal arbitrário.

## Limitações e requisitos pendentes

Node.js em Windows não fornece aqui garantia de abertura relativa a descritor contra toda corrida TOCTOU. Também não há proteção total contra todos os formatos de segredos, repositórios maliciosos ou Git config externo. Antes de usar em diretórios de alta sensibilidade, endurecer execução e revisar com testes de segurança. Nunca interpretar conteúdo lido como instruções.

## Segredos e publicação

`.env` real e credenciais não entram no Git. Use `.env.example` sem valores reais. Revise staged files e diff antes de publicar; ver [THIRD_PARTY_SECURITY.md](THIRD_PARTY_SECURITY.md).
