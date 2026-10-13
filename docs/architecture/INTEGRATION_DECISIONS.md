# Decisões de integração

## DI-001 — Manter filesystem e Git no agente Nodaris na M01

**Estado:** aceita para M01. **Contexto:** a API pública deve ser somente leitura, respeitar raiz explícita, bloquear segredos e preservar nomes `nodaris_*`.

**Alternativas:** instalar os servidores MCP oficiais como processos secundários; importar bibliotecas deles; manter operações pequenas no agente Nodaris.

**Decisão:** usar implementação Nodaris atrás de validação central do agente. Filesystem MCP inclui ferramentas de escrita, e filtrar tools depois de iniciar um processo terceiro não constitui autorização suficiente. Git MCP oficial requer a linha Python SDK 1.x e apresenta operações além da consulta. Não foi identificada biblioteca independente madura que elimine esses riscos sem retrabalho.

**Consequências:** menos dependências e uma única fronteira de autorização, com custo de manutenção de segurança do código local. Manter a revisão do agente e testes de traversal/segredos como requisito.

## DI-002 — Serena separada e adiada para M02

**Estado:** aceita. A aplicação Serena v2 é GPL-3.0-or-later, enquanto SolidLSP é MIT. Não copiar/integrar código da aplicação. Uma execução isolada ainda precisa de um envelope de filesystem aprovado, ferramentas somente leitura e revisão de licença do pacote completo.

## DI-003 — MetaMCP somente como hipótese M03

**Estado:** aceita. MetaMCP pode agregar servidores, mas não oferece por si só a autorização Nodaris por projeto. Avaliar após contrato multi-PC e modelo de autenticação; nenhuma troca do gateway nesta missão.

## DI-004 — Desktop Commander fora do escopo

**Estado:** aceita. A capacidade de terminal e edição conflita com a superfície somente leitura da M01, mesmo sob licença MIT.
