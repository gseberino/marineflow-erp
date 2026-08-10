# 20 — Auth + RLS (Etapa 2, módulo 10)

Auditado **fora da ordem**, antecipado por conter o achado de maior severidade da Fase 1.

Superfície: `src/hooks/use-auth.tsx`, `src/components/ProtectedRoute.tsx`, `src/App.tsx` (matriz de rotas ×
papéis), as políticas RLS nas 243 migrations **e o estado real do banco de produção**.

> **Nota de método.** Este módulo é o único em que consultei o banco: `SELECT` em `pg_policies`,
> `pg_tables` e `app_users` (agregado, sem PII), mais o *security advisor* do Supabase. Nenhuma escrita, nenhum
> DDL, nenhuma migration. A consulta foi necessária porque **as migrations não descrevem o estado real** — e é
> justamente essa diferença que produz o achado MF-AUD-021.

---

## 20.0 Modelo de acesso, como está desenhado

Papéis declarados em `src/hooks/use-auth.tsx:17`:
`'admin' | 'technician' | 'financial' | 'seller' | 'external_seller' | 'other'`.

Autorização no frontend: `ProtectedRoute` (`src/components/ProtectedRoute.tsx:39-61`) libera se o papel está na
lista **ou** se o `groupId` da rota está em `user.metadata.visible_areas`/`user.department` **ou** se é admin.
Exemplo: `/financial` exige `['admin','financial']` (`src/App.tsx:248`).

Autorização no banco: RLS em 120 das 124 tabelas, 214 políticas, das quais **1 é RESTRICTIVE** (em
`app_settings`) e 33 carregam alguma regra de cargo.

População atual (`app_users`, agregado): 5 usuários — 3 `admin` (1 ativo), 1 `technician`, 1 `financial`.
**Zero `external_seller`.**

---

## 20.1 Achados

### [MF-AUD-020] O controle de acesso por cargo do financeiro existe só no frontend
- **Módulo:** Auth/RLS + Financeiro
- **Arquivo:linha:** `src/App.tsx:248-258` (rotas restritas) vs políticas reais de `payments`, `receivables`,
  `bank_transactions`, `invoices`, `payables` no banco
- **Categoria:** F — **Severidade:** P1
- **Descrição:** As tabelas centrais do dinheiro têm política única
  `FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL)`. Qualquer usuário
  autenticado — inclusive `technician` — pode, com o próprio JWT e uma chamada REST direta
  (`/rest/v1/payments`, `/rest/v1/payables?id=eq.…` com `DELETE`), **ler, alterar e apagar** o financeiro inteiro.
  A tela nega o acesso; a API não. O `ProtectedRoute` é uma cortina, não uma porta.

  Não é hipotético: o mesmo projeto já demonstrou saber fazer diferente — `app_users` (só admin),
  `commissions` (admin ou o próprio), `periodos_fechados` (admin/financial) e `payables_select` (categoria
  sensível só para admin) estão corretamente escopadas. A lacuna é seletiva, não sistemática.

  Impacto hoje é limitado pela população (1 técnico ativo, nenhum vendedor externo), mas o produto é vendido como
  SaaS vertical e o papel `external_seller` já existe no código.
- **Evidência** (consulta a `pg_policies` em 08/08/2026):
  ```
  payments            | authenticated_all_payments            | ALL | (auth.uid() IS NOT NULL)
  receivables         | authenticated_all_receivables         | ALL | (auth.uid() IS NOT NULL)
  bank_transactions   | authenticated_all_bank_transactions   | ALL | (auth.uid() IS NOT NULL)
  invoices            | authenticated_all_invoices            | ALL | (auth.uid() IS NOT NULL)
  payables            | payables_insert/update/delete         |     | (auth.uid() IS NOT NULL)
  ```
  contra
  ```
  commissions | commissions_admin_all  | ALL    | is_admin(auth.uid())
  commissions | commissions_self_select| SELECT | (auth.uid() = user_id)
  app_users   | app_users_update_admin_only | UPDATE | is_admin(auth.uid())
  ```
  ```tsx
  // src/App.tsx:248 — a única barreira hoje
  <Route path="/financial" element={<ProtectedRoute roles={['admin','financial']}>…
  ```
- **Ação recomendada:** aplicar `is_admin_or_financial(auth.uid())` (a função já existe e já é usada na frente de
  Compras) às cinco tabelas, uma política por comando, `TO authenticated`, provando com `set role` antes e depois
  — exatamente o procedimento que a frente de Compras registrou em 30/07.
- **Esforço:** M — **Decisão do Gustavo:** Sim — definir a matriz: o técnico deve **ver** o financeiro da OS dele?
  Deve ver `payments`? A resposta muda o predicado (pode ser `is_admin_or_financial OR pertence à minha OS`).

### [MF-AUD-021] As migrations, se replayadas, reabrem `clients` e `vessels` para o público anônimo
- **Módulo:** Auth/RLS + Banco
- **Arquivo:linha:** `supabase/migrations/20260421131952_e48d2328-b603-410c-b57f-22014e3b7820.sql:20-25`;
  ausência de `DROP` em `20260706100000_remove_staging_open_anon_policies.sql:99-108`
- **Categoria:** J/F — **Severidade:** P1 (**não** é vazamento em produção hoje — ver "estado real")
- **Descrição:** A migration de 21/04 criou seis políticas `FOR SELECT TO anon USING (TRUE)`. Quatro foram
  removidas depois, por migrations rastreáveis:
  - `Public document viewing via share_token` → dropada em `20260729144824_*.sql:41`
  - `Public parts viewing via service order` → dropada em `20260706100000_*.sql:107`
  - `Public services viewing via service order` → dropada em `20260706100000_*.sql:108`
  - `Public company settings viewing` → dropada em `20260723080000_*.sql:13`

  **As duas restantes — `Public clients viewing via service order` e `Public vessels viewing via service order` —
  não são dropadas por nenhuma das 243 migrations.** O comentário de `20260706100000_*.sql:99-101` explica o
  descuido: "clients/vessels já têm anon_clients_via_share_token/anon_vessels_via_share_token de uma correção
  anterior — não precisam de política nova, só a remoção das staging_open_* acima já resolve". O raciocínio
  ignora que políticas PERMISSIVE se somam por **OR**: manter uma `USING (TRUE)` ao lado de uma restrita anula a
  restrita.

  **Estado real do banco (verificado):** as duas políticas **não existem** em produção. Foram removidas fora do
  versionamento. Hoje `clients` e `vessels` só têm, para `anon`, as políticas amarradas ao token:
  ```
  clients | anon_clients_via_share_token | SELECT |
    EXISTS (SELECT 1 FROM service_orders so
            WHERE so.client_id = clients.id AND so.share_token::text = share_token_da_requisicao())
  ```
  Ou seja: **produção está mais segura do que o repositório**. O risco é de reprodutibilidade — qualquer
  ambiente novo criado a partir das migrations (staging, disaster recovery, um segundo cliente do SaaS,
  `supabase db reset`) nasce com a base de clientes e embarcações legível por qualquer portador da chave
  publishable, que por definição vai no bundle.
- **Evidência:**
  ```sql
  -- 20260421131952_*.sql:20-25 — criadas e nunca dropadas no repo
  CREATE POLICY "Public clients viewing via service order" ON clients
    FOR SELECT TO anon USING (TRUE);
  CREATE POLICY "Public vessels viewing via service order" ON vessels
    FOR SELECT TO anon USING (TRUE);
  ```
  `grep -rn "Public clients viewing" supabase/migrations/` → **uma única ocorrência**, a do CREATE.
- **Ação recomendada:** migration de convergência que faça `DROP POLICY IF EXISTS` das duas (no-op em produção,
  corretiva em qualquer ambiente novo). Mais importante: adotar a regra de que **toda correção de RLS feita no
  dashboard vira migration no mesmo dia** — este achado é a prova de que a divergência já aconteceu pelo menos
  três vezes (ver MF-AUD-022).
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-022] Drift geral entre as migrations e o RLS real do banco
- **Módulo:** Auth/RLS + Banco
- **Arquivo:linha:** `supabase/migrations/20260420172126_*.sql:12-16` vs políticas reais de `app_settings`;
  `supabase/migrations/20260729130000_scope_internal_tables_to_staff.sql:1-16` (auto-relato)
- **Categoria:** J — **Severidade:** P1
- **Descrição:** O repositório não é a fonte da verdade do RLS. Três evidências independentes:
  1. `app_settings` nas migrations termina com `authenticated_full_access FOR ALL USING (true) WITH CHECK (true)`.
     No banco existem quatro políticas por comando (`app_settings_auth_select/insert/update/delete`), todas com
     `key <> 'cron_worker_secret'`, mais a RESTRICTIVE `deny_internal_secrets` que bloqueia `cron_%`/`internal_%`.
     Nenhuma migration do repositório cria essas cinco.
  2. As duas políticas anônimas de MF-AUD-021 existem no repo e não no banco.
  3. A própria migration `20260729130000` documenta o problema no cabeçalho: *"Este arquivo foi commitado em
     29/07 (caf5246) mas NUNCA chegou ao banco — descoberto ao conciliar pg_policies com o repositório: só 8
     policies tinham regra de cargo… As tabelas internas seguiam abertas a vendedor externo por dois dias."*
     E registra que, ao ser finalmente aplicada em 31/07, **cinco `ALTER` foram omitidos** — ou seja, o arquivo
     versionado nunca foi executado como está escrito.
- **Evidência:** as três acima; contagem atual: 214 políticas no banco, 1 RESTRICTIVE, 33 com regra de cargo.
- **Ação recomendada:** gerar um dump de `pg_policies` e conciliar com o repositório uma vez (é um trabalho de
  algumas horas), commitar uma migration de convergência, e depois manter a disciplina. Sem isso, toda auditoria
  futura precisa consultar o banco para saber a verdade — como esta precisou.
- **Esforço:** L — **Decisão do Gustavo:** Sim — autorizar a migration de convergência (é DDL em produção,
  ainda que idempotente e sem efeito prático se bem feita).

### [MF-AUD-023] `payables`: a proteção de categoria sensível é contornável por UPDATE
- **Módulo:** Auth/RLS + Financeiro
- **Arquivo:linha:** políticas `payables_select` × `payables_update` (banco)
- **Categoria:** F — **Severidade:** P2
- **Descrição:** O `SELECT` de `payables` esconde despesas de categoria sensível de quem não é admin:
  `((auth.uid() IS NOT NULL) AND (is_admin(auth.uid()) OR expense_category IS NULL OR NOT categoria_e_sensivel(expense_category)))`.
  Mas o `UPDATE` tem `USING (auth.uid() IS NOT NULL)` e `WITH CHECK (auth.uid() IS NOT NULL)` — sem a mesma
  condição. Um usuário não-admin pode alterar `expense_category` de uma linha sensível para uma não-sensível
  (o `USING` do UPDATE o autoriza a alcançar a linha) e, feito isso, **passa a poder lê-la** pelo SELECT.
  A proteção depende de o atacante não pensar nisso.
- **Evidência:**
  ```
  payables | payables_select | SELECT | ((auth.uid() IS NOT NULL) AND (is_admin(auth.uid()) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category))))
  payables | payables_update | UPDATE | (auth.uid() IS NOT NULL)   with_check: (auth.uid() IS NOT NULL)
  payables | payables_delete | DELETE | (auth.uid() IS NOT NULL)
  ```
- **Ação recomendada:** replicar o predicado do SELECT no `USING` do UPDATE e do DELETE, e no `WITH CHECK` do
  UPDATE/INSERT (senão dá para *criar* uma sensível e depois editá-la).
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-024] Quatro tabelas com RLS ligada e nenhuma política
- **Módulo:** Auth/RLS + Banco
- **Arquivo:linha:** advisor de segurança do Supabase (`rls_enabled_no_policy`), 08/08/2026
- **Categoria:** J — **Severidade:** P2
- **Descrição:** `ai_operator_alerts_log`, `fiscal_document_sequences`, `pluggy_amostra_payload` e
  **`reparo_coremma_20260805`** têm RLS habilitada sem política nenhuma — inacessíveis a `anon` e `authenticated`,
  só alcançáveis por `service_role`. Para as três primeiras isso pode ser intencional (só Edge Function escreve),
  mas então merece um comentário na migration; se alguma tela precisar delas, falha com resultado vazio e sem
  erro — o modo de falha mais caro de diagnosticar (o projeto já viveu isso, cf. memória "lista vazia + contador
  cheio"). A quarta, `reparo_coremma_20260805`, é uma **tabela de reparo pontual de 05/08 esquecida no banco** e
  não existe em nenhuma migration do repositório.
- **Evidência:** advisor `rls_enabled_no_policy` para as quatro tabelas; `grep -rn "reparo_coremma" supabase/`
  → nenhum resultado.
- **Ação recomendada:** documentar as três primeiras como "service_role only" (com policy explícita de negação ou
  comentário na tabela); avaliar o descarte da tabela de reparo com o Gustavo.
- **Esforço:** S — **Decisão do Gustavo:** Sim — `reparo_coremma_20260805` pode ser descartada?

### [MF-AUD-025] Funções de trigger e utilitárias expostas como RPC ao papel `anon`
- **Módulo:** Auth/RLS
- **Arquivo:linha:** advisor `anon_security_definer_function_executable`
- **Categoria:** F — **Severidade:** P3
- **Descrição:** Três funções `SECURITY DEFINER` chamáveis por `anon` via `/rest/v1/rpc/…`:
  `trg_sync_fiscal_note_items()`, `valida_categoria_de_despesa()` e `valida_recebivel_coerente()`. As três são
  **funções de gatilho** — invocadas fora de um trigger elas erram (`can only be called as trigger`), então o
  risco de execução é baixo. O problema é de superfície e de higiene: a migration
  `20260729120000_revoke_anon_execute_security_definer.sql` fez exatamente esse trabalho para outras funções e
  não pegou estas — provavelmente por serem criadas depois. É a classe de bug que a memória do projeto já
  registrou ("function nova: revoke de public NÃO fecha anon").
  A quarta função na lista, `share_token_da_requisicao()`, é **intencional e inofensiva**: devolve apenas o
  cabeçalho que o próprio chamador enviou, e é necessária para as políticas do link público.
- **Evidência:** advisor de segurança, 08/08/2026, quatro entradas `anon_security_definer_function_executable`.
- **Ação recomendada:** `REVOKE EXECUTE ... FROM anon, public` nas três funções de trigger; incluir o revoke no
  template de toda migration que criar função nova.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-026] Proteção contra senha vazada desativada no Supabase Auth
- **Módulo:** Auth
- **Arquivo:linha:** advisor `auth_leaked_password_protection`
- **Categoria:** F — **Severidade:** P3
- **Descrição:** O Supabase Auth pode checar senhas contra o HaveIBeenPwned no cadastro/troca. Está desligado.
  Num sistema em que qualquer usuário autenticado alcança o financeiro inteiro (MF-AUD-020), a força da senha é
  a última linha.
- **Evidência:** advisor de segurança, entrada `auth_leaked_password_protection`.
- **Ação recomendada:** ligar no painel (não é código, é configuração — 1 clique).
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-027] `visible_areas` amplia permissão de rota sem contrapartida no banco
- **Módulo:** Auth
- **Arquivo:linha:** `src/components/ProtectedRoute.tsx:44-50`
- **Categoria:** F/H — **Severidade:** P3
- **Descrição:** Além do papel, a rota libera por `groupId` presente em `user.metadata.visible_areas` ou no campo
  legado `user.department` (string separada por vírgula). São dois mecanismos de permissão convivendo, ambos
  puramente de frontend, e o legado é um campo de texto livre — "financeiro, operacional" digitado com espaço
  extra funciona por acaso do `.trim()`. Como o banco não distingue cargos nessas tabelas (MF-AUD-020), o efeito
  prático é só de navegação, mas quando o RLS for corrigido esta segunda porta precisa entrar na conta.
- **Evidência:**
  ```tsx
  // ProtectedRoute.tsx:44-48
  const visibleAreas = (user.metadata as any)?.visible_areas as string[] | undefined;
  const legacyAreas = user.department ? user.department.split(',').map(s => s.trim()) : [];
  const allowedGroups = visibleAreas || legacyAreas;
  ```
- **Ação recomendada:** decidir por um dos dois mecanismos e migrar o outro; ao corrigir o RLS, espelhar a mesma
  regra no predicado.
- **Esforço:** M — **Decisão do Gustavo:** Sim — manter `visible_areas` como modelo de permissão?

---

## 20.2 Verificações feitas que **não** produziram achado

- **Link público da OS (`/view/:token`): bem resolvido.** A migration `20260729144824` amarra sete políticas
  anônimas ao cabeçalho `x-share-token` via `share_token_da_requisicao()`, com "nega por omissão" quando o
  cabeçalho falta, comparação como texto para evitar oráculo por erro de cast, e verificação registrada com o
  papel `anon` real em transação abortada. É o melhor trabalho de segurança do repositório. Confirmei no banco
  que as sete estão vigentes.
- **`deny_internal_secrets` é RESTRICTIVE** (verificado em `pg_policies`), então de fato **nega** leitura de
  chaves `cron_%`/`internal_%` a `anon` e `authenticated`, em vez de apenas permitir o resto. Estava correto.
- **Corrida de autorização no `ProtectedRoute`:** tratada. O componente espera `profileReady` antes de avaliar o
  papel (`:31-37`), com o motivo documentado (evitar o flash de "Acesso não autorizado").
- **`app_users`, `commissions`, `periodos_fechados`:** políticas corretas, por comando, com `is_admin` /
  `is_admin_or_financial` / `auth.uid() = user_id`.
- **Tabelas sem RLS:** nenhuma. 120 das 124 têm política; as outras 4 estão em MF-AUD-024 (RLS ligada, sem
  política — fechadas, não abertas).

---

*Módulo 10 auditado. 8 achados (`MF-AUD-020`..`MF-AUD-027`), sendo 3 de severidade P1.*
