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

## Instalação local M01.5

- Raiz de projeto autorizada para o ensaio: exclusivamente `C:\Users\Dell\Downloads\Nodaris`. O proprietário confirmou que a chamada real listou somente esse projeto. Não ampliar a allowlist.
- Os listeners foram verificados em `127.0.0.1:3333`, `127.0.0.1:3334` e `127.0.0.1:8080`; não foi observada interface pública.
- ACLs dos arquivos de segredo em `%LOCALAPPDATA%\Nodaris` foram revisadas: conta Windows atual e SYSTEM têm acesso. O perfil do tunnel-client aponta para referências locais, sem gravar os valores no YAML versionado.
- A cópia TXT de origem da runtime key ainda existia em Downloads na revisão de 13/10/2026. Removê-la manualmente após confirmar a cópia protegida; o conteúdo não foi aberto nem registrado.
- Não foram encontrados serviços Windows, tarefas agendadas, entradas Run ou atalhos Startup com nome Nodaris/tunnel-client. O início automático e a recuperação após reinício ou queda de rede não foram testados.

## Segredos e publicação

`.env` real e credenciais não entram no Git. Use `.env.example` sem valores reais. Revise staged files e diff antes de publicar; ver [THIRD_PARTY_SECURITY.md](THIRD_PARTY_SECURITY.md).
