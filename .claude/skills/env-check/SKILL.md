---
description: Verifica se o ambiente local (dev server, .env, supabase/config.toml) deste repo MarineFlow ERP está apontando para o projeto Supabase canônico, sem nunca ler o conteúdo de .env/.env.local. Rodar no início de qualquer sessão neste repo, e sempre que um erro "column ... does not exist"/"schema cache" aparecer de forma persistente ou inesperada.
---

# Verificação de ambiente — MarineFlow ERP

## Contexto

Este repo já teve um incidente (01/07/2026) onde `.env`/`supabase/config.toml`
da própria pasta canônica ficaram apontando para um projeto Supabase antigo
(`zssewfqhmrlagqbfqsmb`, inacessível via MCP) enquanto todas as migrations
recentes eram aplicadas no projeto correto (`okurngvcodmljjicopdp`). Isso
causa erros "column ... does not exist"/"schema cache" que PARECEM cache do
PostgREST mas na verdade são o frontend conversando com o banco errado — e
nenhuma verificação feita do lado do Supabase (reload de cache, curl na REST
API) pega isso, porque essas checagens também miram o projeto certo.

O projeto Supabase canônico é `okurngvcodmljjicopdp` — confirmar contra
`CANONICAL-SOURCE.md` (`git show chore/version-orphan-rename-migration:CANONICAL-SOURCE.md`)
se houver dúvida, esse arquivo é a fonte mais autoritativa.

## Passo 1 — checar o project_id sem ler .env

```bash
# supabase/config.toml não é segredo, pode ler direto
grep '^project_id' supabase/config.toml

# Para .env/.env.local: NUNCA usar cat/Read. Confirmar o projeto embutido no
# bundle já compilado (a URL não é segredo, é pública):
grep -oE '"https://[a-z0-9]+\.supabase\.co"' dist/assets/index-*.js 2>/dev/null | sort -u
# Se não houver dist/ ainda, rodar `npm run build` primeiro.
```

Ambos devem mostrar `okurngvcodmljjicopdp`. Se mostrarem outra coisa,
`.env`/`.env.local` estão desatualizados.

## Passo 2 — corrigir sem nunca ver o valor antigo (se necessário)

```bash
# Nomes exatos das env vars esperadas (confirmar via grep no código, não no .env):
grep -r "import.meta.env.VITE_" src/integrations/supabase/client.ts

# Buscar valores corretos via MCP Supabase:
#   mcp__claude_ai_Supabase__get_project_url(project_id="okurngvcodmljjicopdp")
#   mcp__claude_ai_Supabase__get_publishable_keys(project_id="okurngvcodmljjicopdp")

# Sobrescrever às cegas (nunca imprime valor antigo nem novo):
sed -i 's|^VITE_SUPABASE_PROJECT_ID=.*|VITE_SUPABASE_PROJECT_ID=okurngvcodmljjicopdp|' .env
sed -i 's|^VITE_SUPABASE_URL=.*|VITE_SUPABASE_URL=https://okurngvcodmljjicopdp.supabase.co|' .env
sed -i 's|^VITE_SUPABASE_PUBLISHABLE_KEY=.*|VITE_SUPABASE_PUBLISHABLE_KEY=<chave nova>|' .env
```

Editar `.env`/`.env.local` é uma ação sobre arquivo de credenciais — confirmar
com o usuário antes de rodar o `sed` acima (mesmo sendo uma sobrescrita às
cegas, sem ler segredo nenhum).

## Passo 3 — checar processos órfãos de dev server

Se o Vite subir em porta diferente de 8080 "porque a porta está em uso",
quase certo que há um processo `node .../vite.js` **desta mesma pasta**
sobrevivendo de uma sessão anterior (encerrar o task tracker não mata
sempre o processo filho). Servindo o `.env` antigo em memória mesmo depois
de você corrigir o arquivo.

```bash
netstat -ano | grep -E ':8080.*LISTENING'
```

No Windows, identificar o processo (não presumir, confirmar antes de matar):

```powershell
Get-CimInstance Win32_Process -Filter "ProcessId=<PID>" | Select-Object ProcessId,CommandLine
```

Só encerrar (`Stop-Process -Id <PID> -Force`) depois de confirmar que é
`node ... vite.js` a partir desta pasta — e com autorização do usuário, já
que é uma ação potencialmente destrutiva sobre um processo já rodando.

## Passo 4 — reconfirmar as colunas esperadas existem no projeto certo

```
mcp__claude_ai_Supabase__execute_sql(project_id="okurngvcodmljjicopdp", query="select table_name, column_name from information_schema.columns where table_name in (...) and column_name in (...)")
```
