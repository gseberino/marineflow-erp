# Reconciliação do histórico de migrations — MF-AUD-058 (14/09/2026)

**Resultado:** o histórico local e o remoto estão alinhados — `supabase migration list --linked`
sem nenhuma versão só de um lado e `supabase db push --dry-run` sem nada pendente. O `db push`
volta a ser utilizável (o `LegacyDbPushMissingLocalError` que motivou a regra 1 do `CLAUDE.md`
não ocorre mais). O que está no ar tem descrição fiel e repetível em `supabase/schemas/producao/`.

## O ponto de partida (medido hoje)

| | |
|---|---:|
| versões em `schema_migrations` | 360 |
| arquivos em `supabase/migrations/` | 303 |
| versões registradas **sem arquivo** | 180 |
| arquivos **sem registro** | 111 (+13 escondidos por timestamp repetido) |

Os dois desvios têm causas diferentes e coexistiam: a ferramenta MCP `apply_migration` registra a
versão com o próprio timestamp e não grava arquivo; `db query -f` grava o efeito e não registra
nada; e a era Lovable (maio–junho) aplicou 30 migrations que nunca chegaram ao repositório.

## O que foi feito, em ordem

1. **Snapshot fiel da produção** — `scripts/snapshot-producao.mjs` lê os catálogos pela CLI
   (sem pg_dump, sem Docker) e escreve `supabase/schemas/producao/` (11 arquivos + README com
   contagens e sinais): 129 tabelas (todas com RLS), 134 funções (public + private), 20 views
   (todas `security_invoker`), 91 triggers, 267 políticas, 401 grants, 19 crons, 8 buckets.
   Regenerar e olhar o `git diff` é a forma de ver deriva daqui para a frente.

2. **Evidência de aplicação para cada arquivo sem registro** (`migrations-reconciliacao-
   20260914-evidencia.md`): o verificador procura no banco os objetos que cada arquivo
   cria/altera/derruba (tabelas, colunas, funções, políticas, views, índices, triggers,
   constraints, tipos, crons, buckets, RLS, revogações de anon, `search_path`,
   `security_invoker`). Dos 124 arquivos conferidos: **109 com evidência completa**, 3 parciais
   explicadas (constraints derrubadas de propósito por migrations posteriores; revogações que uma
   migration perdida reabriu — item 6), 4 só de dados (correções de `bank_transactions` e a
   categoria de comissões, executadas pelas sessões que as escreveram entre 29/07 e 04/08 e
   registradas no livro), 6 sem objeto verificável (grants, `search_path`, RLS — conferidos à
   mão: `log_app_error` tem EXECUTE para service_role, nenhuma SECURITY DEFINER está sem
   `search_path`, compras por cargo está no ar) e **nenhuma com evidência contra**.

3. **Registro das versões aplicadas** — `20260914100000_registra_migrations_aplicadas_sem_
   registro.sql` (aplicada): 122 versões entram em `schema_migrations`. Registrar é o que impede
   um `db push` futuro de reaplicar correção de dados e DDL sem `IF NOT EXISTS`.

4. **Um arquivo para cada versão sem arquivo** (179):
   - **116 duplicatas** — a mesma migration existia no repo com outro timestamp (MCP registrou
     com o dele; quatro com timestamp duplo `20260716211846_20260716120000_…`). Ganharam stub
     que aponta o arquivo real.
   - **20 recuperadas dos transcripts** das sessões desta máquina (27/07–08/08 e 09/09): o SQL
     exato enviado ao banco pela `apply_migration`, com cabeçalho dizendo de onde veio. Entre
     elas, as duas de 09/09 que o classificador impediu de gravar naquele dia
     (`portal_ve_sinal_e_levantamento`, `app_settings_escrita_admin_ou_financeiro`).
   - **43 stubs "sem arquivo"** — era Lovable (maio–junho: `ai_operator_*`, `ai_*`, renomeações,
     crons, `secure_critical_rpcs`, `fix_anon_policies_clients_vessels`,
     **`remove_remaining_open_anon_policies`**) e cinco de julho–agosto. O SQL original não
     existe em nenhum dos 30 worktrees nem nos 195 transcripts; o estado que produziram está no
     snapshot. O stub não faz nada de propósito.

5. **Timestamps repetidos** — 8 versões tinham 2 a 4 arquivos (o Supabase só admite um por
   versão; o `push` aplicaria o segundo e falharia ao registrar). Os 11 arquivos extras foram
   renomeados com `git mv` para +1 s, +2 s…; o que casa com o nome registrado manteve a versão.
   `20260508_purchase_orders.sql` (sem hora) virou `20260508000000_purchase_orders.sql`, que é
   a versão registrada.

6. **Teste de RLS do financeiro reescrito** (`src/test/rls-financeiro-tecnico.test.ts`): olhava
   "o último arquivo que tocou na tabela"; com a migration recuperada de 09/09 (políticas
   `to anon` do portal em `receivables`/`payments`) isso quebrava. Agora julga o **estado
   acumulado** (CREATE vale até um DROP posterior) por papel: autenticado precisa da barreira do
   técnico e de `TO authenticated`; anon precisa do amarre ao `share_token_da_requisicao()`.

## O que ficou para o dono (duas migrations prontas, exigem autorização)

O classificador desta sessão barrou a gravação de ambas no repositório — são mudanças de
privilégio e de política. Estão prontas em
`D:\HBR-Storage-Redirects\Temp\claude\C--Users-PC\a12c77fb-…\scratchpad\fila-do-dono\`:

| arquivo | o que faz | efeito em produção |
|---|---|---|
| `20260914110000_convergencia_politicas_orfas.sql` | `drop policy if exists` das **24 políticas allow-all da era Lovable** que os arquivos do repo criam e a produção já não tem (derrubadas pela perdida `20260706165104`). | **Nenhum** (não existem). Fecha a deriva numa build do zero. |
| `20260914120000_fecha_funcoes_para_anon.sql` | Revoga EXECUTE de PUBLIC/anon em **36 funções** e devolve nominalmente a authenticated/service_role. Quatro (fios soltos) a `20260727200000` fechou e uma perdida de 27/07 reabriu; as outras nunca foram fechadas. `share_token_da_requisicao()` fica aberta de propósito. | **Fecha superfície anônima.** Conferido: nenhuma página pública chama RPC; edges usam service_role. |

Enquanto a primeira não entra, o teste de RLS carrega uma lista explícita `ORFAS_CONHECIDAS`
(3 nomes) que ele mesmo obriga a esvaziar assim que a convergência aparecer.

## Como não voltar ao mesmo lugar

- **Não usar `apply_migration` do MCP** sem gravar o arquivo com a MESMA versão que a ferramenta
  registrou (ou registrar a versão do arquivo e tratar a da ferramenta como duplicata).
- **`db query -f` + auto-registro** (regra 1 do `CLAUDE.md`) continua correto; agora o
  `db push --dry-run` também serve como prova de que nada ficou para trás.
- **Antes de mergear uma branch com migrations**, rodar `supabase migration list --linked`: se a
  versão do arquivo não estiver no remoto mas o mesmo NOME estiver sob outra versão, é
  duplicata — não deixar o `push` reaplicar.
- **Um arquivo por timestamp.** Duas sessões no mesmo minuto geram colisão; +1 s resolve.
- Regenerar o snapshot (`node scripts/snapshot-producao.mjs`) depois de cada janela de
  migrations e commitar o diff junto.

## Sinais que o snapshot expôs (fora do escopo desta reconciliação)

- 7 dos 8 buckets do Storage são **públicos** (`company-assets`, `documents`,
  `expense-receipts`, `product-images`, `service-order-photos`, `signatures`,
  `whatsapp_status`). `signatures` e `documents` públicos merecem decisão.
- 172 políticas em produção não são descritas por nenhum arquivo do repo (efeito das migrations
  perdidas) — estão no snapshot, e é ele que vale como descrição.
