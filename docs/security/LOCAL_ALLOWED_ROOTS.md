# Configuração local de raízes autorizadas — preparação M01.12.2B1

## Estado

O leitor abaixo é uma preparação isolada. `scripts/windows/supervisor.ps1` continua usando a política atual e não carrega `local-roots.ps1`. Nenhum arquivo real em `%LOCALAPPDATA%` foi criado, lido ou alterado nesta etapa. A raiz Dell já autorizada não foi migrada.

## Caminho e schema propostos

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

## Ativação futura (M01.12.2B2 — não executada)

1. Revisar e aprovar este módulo e o schema antes de qualquer mudança no supervisor.
2. Com os serviços atuais ainda intactos, preparar a configuração real fora do Git com a raiz exata previamente autorizada pelo proprietário neste computador; não copiar essa autorização para outras máquinas. Criar diretório/arquivo com ACL protegida de usuário atual e SYSTEM e persistir o arquivo atomicamente. Essa criação exige autorização específica na etapa de ativação.
3. Executar o leitor em modo somente leitura contra o arquivo real e confirmar o único caminho canônico retornado. Não imprimir conteúdo, nem emitir caminhos em logs.
4. Confirmar antes de editar o startup que a configuração foi criada, ACLs conferem e a leitura é válida. Se falhar, parar e reparar o arquivo local antes de ativar; jamais reintroduzir fallback amplo.
5. Alterar o supervisor para carregar o módulo e validar a configuração antes de definir `NODARIS_ALLOWED_ROOTS`. A alteração em disco não afeta processos já carregados; manter esses processos ativos e programar a adoção para inicialização natural aprovada, sem parar/reiniciar nesta preparação.
6. Antes da próxima inicialização natural, fazer revisão estática/testes isolados do startup e deixar procedimento manual para restaurar o código anterior se a nova execução falhar. A configuração válida deve permanecer presente; rollback não deve ampliar raízes nem usar uma allowlist embutida.
7. Após a inicialização futura, confirmar health e que projetos listados limitam-se à raiz aprovada; tentar um caminho externo e comprovar rejeição. Não declarar ativação até validação MCP real.
8. Em segundo computador, criar uma configuração nova após autorização explícita do proprietário local. Nunca copiar a allowlist Dell.

### Bloqueio operacional

Como o Nodaris é iniciado pelo Agendador e está em uso, não é seguro provar uma alteração de startup interrompendo a instância atual. A B2 deve separar preparação da configuração, revisão do código e adoção na próxima inicialização autorizada. Se a instância antiga continuar disponível após essa adoção, ela manterá a política em memória até sair; não iniciar um supervisor paralelo.

## Recuperação

Se a configuração falhar antes da adoção, manter o supervisor atual intacto e corrigir a fixture/configuração fora do runtime. Se uma futura inicialização com o novo leitor falhar, não permitir nenhum projeto e não iniciar cópia paralela; preservar diagnóstico sanitizado, revisar ACL/schema e corrigir a configuração autorizada. O rollback de código só pode restaurar a política anteriormente revisada, mantendo a raiz Dell estrita; não criar fallback automático para diretórios mais amplos. A execução concreta desse rollback pertence à missão de ativação e requer autorização específica.

## Testes e limites desta etapa

`tests/fixtures/windows/local-roots-smoke.ps1` usa uma pasta temporária, com ACL fixture, e não consulta `%LOCALAPPDATA%\Nodaris\config`. A suíte também verifica estaticamente que o supervisor não carrega nem chama o leitor. Os testes não modificam tarefa agendada, serviços, segredos, allowlist ativa ou processos.
