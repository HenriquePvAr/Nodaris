# Autenticação GitHub do repositório

## Estado confirmado em 13/10/2026

- Repositório: `HenriquePvAr/Nodaris`, remoto `origin` por HTTPS.
- `gh api user` confirmou a conta `HenriquePvAr`.
- A conta tem permissão `ADMIN` no repositório.
- O Git Credential Manager global permanece configurado para outros projetos. Neste repositório, `.git/config` redefine os helpers herdados e usa `gh auth git-credential`, isolando a conta correta sem mudar a configuração global.
- Os commits `61d23e3` e `7d3041f` foram enviados sem force; o SHA remoto confirmado é `7d3041fdfa76e87206126026888800abf89f31fa`.
- Autoria e committer dos dois commits: `Henrique <henriquepaiva128@gmail.com>`. Não há trailer `Co-authored-by`.

## Verificação sem revelar credenciais

```powershell
gh auth status
gh api user --jq .login
gh repo view HenriquePvAr/Nodaris --json viewerPermission
git remote -v
git ls-remote origin refs/heads/main
```

Não imprima a saída integral de `git credential fill`: ela contém o segredo. Para confirmar apenas o nome efetivo do usuário Git, filtre a resposta:

```powershell
@('protocol=https','host=github.com','','') | git credential fill | Where-Object { $_ -like 'username=*' }
```

## Login e isolamento local

Se o token expirar, execute `gh auth login --hostname github.com --git-protocol https --web` e autorize a conta proprietária no navegador oficial. Para alternar a conta ativa do GitHub CLI: `gh auth switch --hostname github.com --user HenriquePvAr`.

Não use `gh auth setup-git` sem avaliar o efeito global. Para este repositório, o helper local pode ser configurado assim:

```powershell
git config --local --replace-all credential.helper ""
git config --local --add credential.helper "!gh auth git-credential"
```

Essas entradas ficam no `.git/config`, não são commitadas e não alteram os outros projetos. Nunca cole senhas, tokens ou códigos de login em chat, tickets ou arquivos versionados.
