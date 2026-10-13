# Segurança de componentes terceiros

- O agente Nodaris é a fronteira de autorização. Nenhum processo MCP secundário recebe caminho de projeto antes de validar `machineId`, `projectId` e allowlist.
- Filtrar o catálogo de ferramentas não impede um servidor de executar funções não anunciadas; processo separado não significa sandbox. Integrações futuras precisam de isolamento do sistema operacional, configuração de filesystem somente leitura e catálogo allowlist de ferramentas.
- Filesystem MCP oficial é MIT, mas oferece escrita e ampla entrada de caminho. Vulnerabilidades/relatos públicos de traversal e comportamento do Roots Protocol exigem inspeção da versão exata. Não usar como substituto das validações Nodaris.
- Git MCP oficial é MIT e ainda depende do MCP Python SDK 1.x na documentação avaliada. Comandos de escrita e configuração de repositório ficam fora do proxy.
- Serena v2 é GPL-3.0-or-later como aplicação; SolidLSP permanece MIT. Distribuição/combinação exige análise de licenciamento antes da M02. Não carregar prompts/código de fontes não confiáveis como instruções.
- MetaMCP é MIT na documentação atual, mas sua agregação amplia o catálogo e a cadeia de confiança; exige autenticação, isolamento e revisão do caminho de cada tool.
- Desktop Commander é MIT, mas entrega terminal, edição e escrita. Não instalar na M01 nem repassar suas ferramentas.
- ChatGPT custom MCP documenta somente OAuth, nenhuma autenticação, ou modo misto OAuth/nenhuma; não há configuração de bearer estático arbitrário. O gateway Nodaris ainda exige bearer e precisa de uma estratégia compatível antes do túnel.
- Fixar versões e lockfile; registrar origem e hash no momento da adoção. Rever avisos de segurança e dependências upstream antes de cada atualização.
