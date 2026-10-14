# Configuração local de raízes autorizadas — M01.12.2B

## Estado

O leitor `scripts/windows/local-roots.ps1` está integrado ao código do supervisor após o mutex e durante a fase de configuração, antes de iniciar qualquer serviço. O processo supervisor atualmente ativo foi carregado antes desta alteração e continua em execução com a política que já tinha carregado; a nova integração ainda não foi ativada nem validada em uma inicialização real.

Neste computador, a configuração privada foi provisionada fora do Git e validada pelo leitor no Windows PowerShell 5.1. Ela contém exatamente uma raiz previamente autorizada. Não registre seu conteúdo ou caminho na telemetria. Esta autorização não se transfere a outras instalações ou computadores.

## Caminho e schema

O caminho padrão futuro é `%LOCALAPPDATA%\Nodaris\config\allowed-roots.json`. O arquivo UTF-8 deve conter exatamente as propriedades abaixo:

```json
{
  "schemaVersion": 1,
  "allowedRoots": ["C:\\caminho\\do\\projeto"]
}
```

São aceitas de 1 a 32 raízes. O leitor não cria diretórios/arquivos e não oferece valores padrão. Arquivo ausente, inválido, vazio ou com versão desconhecida falha fechado com `NODARIS_ROOT_CONFIG_REJECTED`, sem incluir caminhos ou conteúdo na mensagem.

## Validações

- Objeto JSON com exatamente `schemaVersion` e `allowedRoots`; chaves duplicadas são rejeitadas antes de `ConvertFrom-Json` porque o Windows PowerShell 5.1 pode aceitar duplicatas.
- O schema aceita somente `schemaVersion` como número inteiro JSON (`Int32`/`Int64`) com valor exato 1; Boolean, texto, decimal, null e versões desconhecidas falham.
- A unicidade das chaves é verificada por parser estrutural que decodifica escapes JSON antes da comparação e rejeita nomes iguais sem distinção de caixa, inclusive combinações de escapes Unicode. Isso evita colisões que `ConvertFrom-Json` do Windows PowerShell 5.1 mascara ao materializar o objeto.
- O parser limitado rejeita profundidade acima de 8 e mais de 4096 tokens/operações; a fixture roda em processo Windows PowerShell separado com timeout.
- O tamanho físico do arquivo é conferido antes de `ReadAllText` e o conteúdo decodificado é novamente limitado a 32 KiB.
- Versão 1, lista com limites, strings não vazias e caminhos absolutos locais canônicos; UNC, caminhos relativos, separadores `/`, `;`, ADS, wildcard, unidade raiz, `.`/`..`, segmentos com aliases do Windows, diretórios ausentes, duplicados e raízes sobrepostas são rejeitados. O `;` é proibido porque o consumidor atual de `NODARIS_ALLOWED_ROOTS` o usa como delimitador.
- Uma raiz que contenha o diretório de instalação do Nodaris é rejeitada, exceto quando a raiz é exatamente o diretório de instalação. Isso impede aprovar inadvertidamente um pai amplo como Downloads.
- Componentes existentes de cada caminho não podem ser reparse points. O leitor não segue junctions/symlinks como autorização implícita.
- Diretório da configuração e arquivo exigem DACL protegida contra herança e exatamente duas ACEs explícitas: usuário atual e SYSTEM, ambas Allow/FullControl, com flags de herança apropriadas para diretório ou arquivo. O leitor somente verifica ACL; não as modifica.
- Não há tokens, credenciais, logs de conteúdo, nem fallback para repositório, home, Downloads, unidade ou variável de desenvolvimento.

O formato usa caminhos Windows absolutos, conforme o escopo deste módulo. A ACL é verificada via Windows PowerShell 5.1 e APIs NTFS. O teste de junction exige criar o reparse point em fixture e falha (em vez de declarar PASS) se a política local impedir a criação. O teste também confirma a regra de elegibilidade: uma raiz igual ao diretório de instalação não é classificada como ampliação; seu pai é.

## Próxima adoção (pendente de autorização)

1. Antes da janela, confirmar que o código revisado e a configuração privada são compatíveis, que o runtime antigo permanece saudável e que a lista MCP mostra somente a raiz aprovada.
2. Comparar supervisor, agente, gateway e tunnel-client antes e depois da adoção; confirmar ausência de duplicatas e listeners exclusivamente em loopback.
3. Após uma inicialização natural expressamente autorizada, confirmar health autenticado, readiness do túnel e eventos sanitizados de carregamento e validação das raízes.
4. Validar novamente a lista de projetos e fazer uma tentativa negativa de consulta fora da raiz aprovada. Não imprimir conteúdo ou caminho privado em relatórios.
5. Não iniciar supervisor paralelo. Se a nova inicialização falhar, preservar o estado, consultar `state.json` e eventos sanitizados e interromper a adoção. Não criar raízes, alterar ACLs, modificar o leitor ou ativar uma allowlist alternativa para contornar a falha.
6. Recuperação manual: com autorização específica, restaurar a versão previamente revisada do supervisor ou corrigir a configuração local por procedimento igualmente revisado; verificar o diff e preservar a configuração privada. Só então usar o mecanismo oficial de inicialização em janela aprovada. Nenhum fallback automático está implementado.
7. Em outro computador, exigir autorização própria e provisionamento local independente; nunca copiar a configuração deste equipamento.

### Bloqueio operacional

Como o Nodaris é iniciado pelo Agendador e está em uso, alterações no arquivo do supervisor não modificam o processo carregado na memória. A integração está apenas no código em disco; a política da instância ativa permanece inalterada até uma inicialização futura autorizada. Não parar serviços, alterar a tarefa ou iniciar supervisor paralelo nesta etapa.

## Recuperação

Se a configuração falhar antes da adoção, manter o supervisor atual intacto e corrigir fixtures fora do runtime. Se uma inicialização futura falhar, o leitor bloqueia o startup antes de iniciar componentes e remove `NODARIS_ALLOWED_ROOTS`, sem recorrer ao caminho fixo antigo. Preservar os diagnósticos sanitizados e a configuração; não iniciar cópia paralela. Qualquer restauração de código ou correção da configuração exige autorização e revisão próprias. O achado M12-07 — falha durante cleanup poder impedir a gravação final do estado — permanece fora do escopo desta etapa e não foi corrigido nem retestado.

## Testes e limites desta etapa

`tests/fixtures/windows/local-roots-smoke.ps1` valida o leitor em uma pasta temporária. `tests/fixtures/windows/supervisor-roots-smoke.ps1` extrai e executa somente as funções de integração do supervisor, com configurações temporárias e diagnóstico simulado; nunca executa o supervisor real nem consulta a configuração privada. Os testes não modificam tarefa agendada, serviços, credenciais, configuração real ou processos.
