# MarineFlow AI Operator - Macro Cycle 1 (security hardening)

> Continuacao da branch `feat/marineflow-ai-operator-macro-cycle-1`.
> Este documento registra o estado real ja aplicado no staging apos a foundation,
> o hardening de `search_path`, o deploy do `ai-operator-core` e a remediacao
> operacional de paridade da trigger `ai_op_protect_pending_action()`.

## Bloqueios enderecados

| # | Bloqueio | Status | Onde foi corrigido |
| --- | --- | --- | --- |
| 5.1 | Audit declarado append-only, mas com UPDATE policy | Corrigido | `20260522190000_ai_operator_foundation.sql` remove escrita por `authenticated`; gravacao fica server-only. |
| 5.2 | Pending actions com UPDATE generico | Corrigido | foundation + trigger `ai_op_protect_pending_action()` bloqueando campos imutaveis e transicoes invalidas. |
| 5.3 | Aprovacao/rejeicao sem checagem de papel | Corrigido | helpers SQL `ai_op_can_approve` / `ai_op_can_reject` + validacao no `ai-operator-core`. |
| 5.4 | Session ID aceito sem ownership | Corrigido | `sessionBelongsTo` valida `owner_user_id = auth.uid()` (ou admin). |
| 5.5 | Channel intake fail-open sem secret | Corrigido em codigo | intake continua fora de deploy nesta rodada. |
| 5.6 | Memoria tecnica virava fato confirmado | Corrigido | `verification_status` = `candidate|verified|rejected`; IA cria sempre `candidate`. |
| 5.7 | WhatsApp bridge aplicaria ingestao real | Fora do escopo por decisao | migration fica em `supabase/deferred-migrations/` e continua nao aplicada. |
| 5.8 | Modelo hardcoded | Corrigido | `AI_OPERATOR_MODEL` com default `gemini-2.5-flash`. |
| 5.9 | RLS ampla demais | Corrigido | policies granulares de leitura; escritas sensiveis seguem server-only. |

## Matriz de aprovacao - Macro Cycle 1 restritiva

Politica vigente para a primeira homologacao:

- `approve_action`: somente `admin`.
- `verify_memory_note` / `reject_memory_note`: `admin` ou `technician`.
- `reject` de pending action operacional: `admin` ou o proprio solicitante.
- `external_seller` nao participa da governanca de pending actions.
- Toda tentativa negada e auditada com `event_category='security'`.

## Governanca de memoria tecnica

| verification_status | admin | technician | financial | seller | other | external_seller | created_by |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| `verified` | x | x | x | x | x | - | - |
| `candidate` | x | x | - | - | - | - | x |
| `rejected` | x | x | - | - | - | - | x |

## Validacao de referencias do ERP

Antes de gravar `client_id`, `vessel_id`, `product_id` ou `service_id`, o
`ai-operator-core` valida visibilidade com o JWT real do usuario:

- visivel -> grava a referencia;
- invisivel por RLS ou inexistente -> grava sem a referencia e audita `entity_reference_blocked`;
- erro de banco -> trata como invisivel (fail-closed).

## Aplicacao em staging - estado atual

- Projeto Supabase staging: `okurngvcodmljjicopdp`
- Foundation aplicada remotamente: `20260523005653_ai_operator_foundation`
- Hardening de `search_path` aplicado remotamente: `20260523010000_ai_operator_harden_pending_trigger_search_path`
- Edge Function `ai-operator-core` implantada: `ACTIVE`, `version: 1`, `verify_jwt: true`
- `ai-operator-channel-intake`: nao implantada
- Bridge WhatsApp (`supabase/deferred-migrations/20260522190100_ai_operator_whatsapp_bridge.sql`): nao aplicada

### Limites funcionais preservados no staging

- origem interna aceita pelo core: somente `web`;
- leitura de entidades continua sujeita a RLS do usuario;
- acoes sensiveis viram `pending_actions`;
- nenhuma OS oficial e criada automaticamente;
- nenhum WhatsApp e enviado;
- nenhum estoque ou financeiro e alterado automaticamente;
- memoria tecnica criada pela IA continua `candidate`;
- aprovacao operacional continua admin-only;
- referencias cross-session seguem bloqueadas;
- tentativas de spoofing de canal seguem auditadas.

## Pos-DDL Advisor - remediacao de search_path

Apos a foundation, o Supabase Security Advisor sinalizou dois alertas
`function_search_path_mutable`:

1. `public.ai_op_protect_pending_action()`
2. `public.set_updated_at_now()`

A migration `20260523010000_ai_operator_harden_pending_trigger_search_path.sql`
foi a resposta aditiva aprovada para endurecer as duas funcoes:

- `public.ai_op_protect_pending_action()` com `set search_path = ''`
- `public.set_updated_at_now()` com `set search_path = ''` e `pg_catalog.now()`

### Divergencia operacional encontrada no staging

Durante a transferencia conectada do SQL para o Supabase, a definicao remota de
`public.ai_op_protect_pending_action()` ficou com divergencia textual em uma
mensagem de excecao: faltou o caractere final `)` na string do estado terminal.
A logica de protecao permaneceu equivalente, mas o texto ficou diferente do
arquivo aprovado no Git.

### Remediacao de paridade

Para restaurar a definicao exata revisada no Git, foi aplicada uma remediacao
minima no staging:

- migration remota: `20260523030326_ai_operator_restore_pending_trigger_definition_parity`
- migration local correspondente: `supabase/migrations/20260523030326_ai_operator_restore_pending_trigger_definition_parity.sql`

Essa migration de paridade:

- faz `CREATE OR REPLACE` somente de `public.ai_op_protect_pending_action()`;
- preserva `set search_path = ''`;
- preserva `REVOKE/GRANT` server-only da funcao;
- restaura a mensagem correta `estado terminal nao pode mudar (% -> %)`;
- nao altera tabelas, policies, dados, outras funcoes, intake ou WhatsApp.

### Observacao operacional importante

O historico remoto do staging hoje contem dois registros com o nome
`ai_operator_harden_pending_trigger_search_path`.

Isso deve ser apenas documentado. Nao apagar, nao editar e nao reaplicar
migrations remotas de forma destrutiva.

### Estado do Advisor apos a correcao

Depois da correcao:

- os alertas `function_search_path_mutable` de `public.ai_op_protect_pending_action()`
  e `public.set_updated_at_now()` nao aparecem mais;
- alertas globais preexistentes de outros modulos continuam fora do escopo;
- esses alertas globais serao tratados em macro ciclo separado.

## Modelo de IA para homologacao

- default do `ai-operator-core`: `gemini-2.5-flash`
- override opcional: `AI_OPERATOR_MODEL`
- recomendacao para o cenario Raymarine: manter o default homologado

## Superficie RPC / SECURITY DEFINER

### Funcoes em `private`

Helpers de papel e atividade vivem em `schema private`, fora da Data API:

- `private.ai_op_is_admin(uuid)`
- `private.ai_op_is_active(uuid)`
- `private.ai_op_is_admin_or_financial(uuid)`
- `private.ai_op_is_internal(uuid)`

Elas seguem usaveis nas policies de RLS via `GRANT EXECUTE`, sem exposicao por RPC.

### Funcoes em `public` server-only

Continuam travadas para uso operacional interno:

- `public.ai_op_can_approve(uuid, text)` -> `service_role`
- `public.ai_op_can_reject(uuid, uuid)` -> `service_role`
- `public.ai_op_protect_pending_action()` -> trigger engine / `service_role`

## Estado aplicado em staging - o que NAO repetir nesta sessao

1. Nao reaplicar `20260522190000_ai_operator_foundation.sql`.
2. Nao reaplicar `20260523010000_ai_operator_harden_pending_trigger_search_path.sql`.
3. Nao reaplicar `20260523030326_ai_operator_restore_pending_trigger_definition_parity`.
4. Nao implantar `ai-operator-channel-intake`.
5. Nao aplicar a bridge WhatsApp em `supabase/deferred-migrations/`.
6. Nao tratar alertas globais do Advisor fora do AI Operator nesta rodada.

## Proximo passo para homologacao manual

Validar o Preview da branch `feat/marineflow-ai-operator-macro-cycle-1` com o
cenario Raymarine, confirmando:

- login normal no frontend;
- uso do Modo Operador (beta) via canal `web`;
- criacao apenas de artefatos internos (`ai_operator_sessions`, `messages`,
  `drafts`, `draft_items`, `audit`);
- ausencia de OS oficial automatica;
- ausencia de WhatsApp real;
- ausencia de intake ou bridge externa.
