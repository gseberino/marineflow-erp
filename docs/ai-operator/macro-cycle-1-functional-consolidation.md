# MarineFlow AI Operator - Macro Cycle 1 Functional Consolidation

> Branch: `feat/marineflow-ai-operator-macro-cycle-1`
> Date: `2026-05-23`
> Scope: persistent operator drafts, structured continuity, safe entity linking,
> truthful UI/operator responses, and immediate bootstrap drafts for clear
> operational demands.

## Hotfix note - explicit-only entity linking

An independent review after the functional consolidation found that the
published code still had parallel write paths where the model could send
`client_id` and `vessel_id` through `create_draft`, `update_draft`, and
`register_memory_candidate`.

RLS visibility was still being enforced, but that was not enough: a wrong UUID
that was valid and visible could still be persisted without explicit user
confirmation.

This hotfix closes that gap:

- `create_draft`, `update_draft`, and `register_memory_candidate` no longer
  accept model-controlled entity links as writable inputs;
- the backend now inherits only already-confirmed `client_id` and `vessel_id`
  from the active session and/or active draft context;
- unexpected entity-link arguments coming from the model are ignored and
  audited;
- `link_draft_entities`, called by the authenticated UI, remains the only
  allowed path to create or change a client/vessel link;
- RLS is still required, but is treated as a visibility gate, not as a
  substitute for explicit human confirmation.

## Why this phase exists

The security foundation of the AI Operator was already active in staging, but
the real Raymarine homologation exposed a product gap:

- the operator could create a useful internal draft;
- the backend correctly blocked unsafe entity references;
- the frontend still treated drafts as ephemeral chat artifacts;
- the model could still end up carrying internal UUIDs across turns.

This phase closes that gap without creating official service orders, without
executing pending actions, and without activating WhatsApp or intake flows.

## Functional outcomes

### 1. Persistent operator draft area

The branch now provides a real navigable area for operator drafts:

- list route: `/operator/drafts`
- detail route: `/operator/drafts/:id`
- visible navigation entry: `Rascunhos do Operador`
- direct link from the inline chat draft card to the persistent draft detail

The list is intentionally separate from official `service_orders`. Drafts remain
internal operator artifacts and are clearly labeled as such.

### 2. Draft continuity without UUID copying

Continuing a draft no longer depends on copying IDs into the chat.

The detail page can reopen the operator flow with:

- persisted `session_id`
- active `draft_id`
- server-side session ownership validation
- structured draft context injected back into the operator core

This allows the user to keep working on the same draft while preserving audit
trails and without asking the model to reconstruct internal identifiers.

### 3. Structured entity linking

The Raymarine case proved that the backend was correct to reject a mutated
client UUID. The fix in this cycle is not to weaken validation, but to stop
depending on model-transported UUIDs.

The implemented flow is:

1. Search and select the client explicitly in the UI.
2. Select the vessel explicitly under that client when applicable.
3. Persist the link through `link_draft_entities`.
4. Re-validate visibility and ownership in the backend before saving.
5. Audit the link event in `ai_operator_audit`.
6. Keep model tools restricted to content updates only; no link mutation is
   allowed there.

If the reference is invalid or not visible under RLS, the backend still blocks
it.

After the explicit-link hotfix, draft and memory writes inherit only
server-confirmed context:

- `create_draft` can create an unlinked draft when the session has no confirmed
  entity yet;
- `create_draft` can inherit links only from an already-confirmed session;
- `update_draft` can update content, but cannot create, swap, or remove entity
  links on behalf of the model;
- `register_memory_candidate` can inherit the confirmed draft/session context,
  but cannot attach a new entity chosen by the model.

### 4. Immediate bootstrap drafts for clear operational intent

Clear operational demands can now create a draft immediately, even before all
information is known.

Examples covered by the bootstrap detector:

- installation quote
- diagnosis request
- service plan
- technical visit/evaluation
- structured customer-facing response suggestion

When the initial message is operationally clear but incomplete, the core can
open a draft with:

- a coherent title
- summary of understood intent
- preliminary draft items
- pending technical questions
- next steps
- hypotheses
- `awaiting_info` status when appropriate

This keeps the operator honest and useful from the first turn.

## Raymarine evidence preserved

The staging draft created during homologation remains the baseline evidence for
this phase:

- title: `Orcamento: Instalacao Raymarine Axiom 12 no Fly`
- kind: `quote`
- historic status in staging: `draft`
- 12 draft items persisted
- `service_order_id = null`
- `converted_service_order_id = null`
- no related `pending_action`
- `client_id = null` because the backend correctly blocked an unsafe reference

The new UI is expected to make this historical draft discoverable and
continuable without silently rewriting its original data.

## Truthfulness rules enforced by this phase

The operator and UI must not claim capabilities that do not exist.

This phase aligns the experience with reality by ensuring:

- the user is directed to a real draft area that now exists;
- drafts are explicitly shown as internal and not official service orders;
- blocked entity links are not described as successful;
- UUID-like identifiers are sanitized before being shown to the user.

## Files introduced in this phase

- `src/pages/AIOperatorDraftListPage.tsx`
- `src/pages/AIOperatorDraftDetailPage.tsx`
- `src/hooks/use-ai-operator-drafts.ts`
- `src/lib/ai-operator-display.ts`
- `supabase/functions/ai-operator-core/operational-intent.ts`
- `supabase/functions/ai-operator-core/session-history.ts`
- `supabase/functions/ai-operator-core/entity-linking.ts`

## Files materially updated in this phase

- `src/App.tsx`
- `src/components/AppLayout.tsx`
- `src/components/ai/AIOperatorDraftCard.tsx`
- `src/hooks/use-ai-operator.ts`
- `supabase/functions/ai-operator-core/index.ts`
- `supabase/functions/ai-operator-core/prompt.ts`
- `supabase/functions/ai-operator-core/tools.ts`
- `src/test/ai-operator-entity-linking.test.ts`
- `src/test/ai-operator-tools-contract.test.ts`

## Security boundaries preserved

- No official service order is created automatically.
- No pending action executor was introduced.
- No WhatsApp flow was activated.
- `ai-operator-channel-intake` remains undeployed.
- No stock, financial, or schedule side effect is executed automatically.
- RLS and ownership checks remain in force.
- The operator core still accepts only the internal `web` origin in this phase.

## Explicitly out of scope

The legacy HTTP 400 issues observed in the HAR from other ERP modules remain
out of scope for this branch, including canonical schema mismatches such as:

- `suppliers.name`
- `external_quote_leads.name`
- `clients.name`
- `products.name`

Those issues should be handled in a separate branch focused on legacy schema
normalization, not inside the AI Operator consolidation work.

---

## Operational evolution — deterministic intent routing, safe link proposal, cancel lifecycle (2026-05-23)

> Commit: `a8ddde3` (HEAD at the time of this addendum)
> Edge function: `ai-operator-core` v4 ACTIVE, `verify_jwt = true`
> Migration applied to staging only: `20260523120000_ai_operator_draft_cancel_status.sql`

### Why this addendum exists

After the explicit-only entity linking hotfix shipped at `79cc7a1`, real usage
showed that the area of drafts was still operationally rough:

- the floating widget on `/operator/drafts` created a brand-new draft every
  time the user typed something that referenced an existing draft, because
  the deterministic intent detector matched single words like `orcamento` or
  `instalacao` without considering link/cancel/lookup verbs;
- "Continuar com o Operador" on the detail page only toggled an inline card
  far below the page header, producing a confusing UX;
- list and detail screens still displayed raw technical labels like `quote`
  or `awaiting_info`;
- there was no safe way to cancel a draft that the system itself created by
  mistake.

This addendum closes those gaps without reopening any of the security
guarantees already in place.

### Deterministic intent routing

`operational-intent.ts` now exposes a trinary `classifyMessage(message)`:

- `new_demand` — clear new operational request (quote/diagnosis/etc.)
- `operate_on_existing` — reference to an existing draft (vincular,
  cancelar, abrir/continuar, anaforic pronouns, "do <Nome>" ownership)
- `none` — neither

Reference detection wins over bootstrap. Messages like "vincule o rascunho
do Célio à embarcação Andoca" or "cancele o rascunho criado errado" no
longer cause a new bootstrap, even when they contain words like `orcamento`
or `instalacao`. When `operate_on_existing` triggers and no active draft is
in context, the chat handler returns a list of recent visible drafts so the
UI can render a selection card. The model is not called and no draft is
created in this path.

### Safe natural linking — `propose_entity_link`

A new safe tool `propose_entity_link` lets the model suggest a client
and/or vessel candidate based on prior `search_clients` / `search_vessels`
results. Critical contract:

- the tool schema has no `draft_id` parameter; the backend always resolves
  the target draft from the active session/UI context;
- the tool does not persist anything; it produces a structured
  `proposed_link` payload with human-readable names that the UI renders as
  a confirmation card;
- only after explicit user confirmation does the frontend call the existing
  `link_draft_entities` endpoint, which remains the single write path for
  client/vessel links;
- visibility is validated via RLS-backed `validateAllReferences` before any
  proposal is even rendered.

### Cancel lifecycle

A new `cancel_draft` endpoint allows the user to cancel drafts created in
error. The migration `20260523120000_ai_operator_draft_cancel_status.sql`
extends the status check constraint additively to include `cancelled`. The
endpoint enforces:

- only drafts in `draft` or `awaiting_info` can be cancelled (approved,
  rejected, converted, awaiting_approval are blocked with explicit reasons);
- drafts with pending_actions in `pending` status are blocked;
- cancellation reason persisted in `metadata.cancellation_reason`;
- event `draft_cancelled` recorded in `ai_operator_audit`.

The list view hides `cancelled` drafts by default; a toggle reveals them.
There is no hard delete in this cycle.

### UX polish

- `AIAgentWidget` now reads `entityType=operator_draft` from `ai-context`
  and passes `initialDraftId` to `useAIOperator`, so opening the floating
  chat on a draft detail page always scopes the conversation to that draft.
- `AIOperatorDraftDetailPage` replaces the inline operator card with a
  focused right-side `Sheet` drawer that auto-focuses the textarea on open
  — clicking "Continuar com o Operador" now gives an obvious response.
- PT-BR labels via `src/lib/ai-operator-display.ts` (`formatDraftKind`,
  `formatDraftStatus`, `statusBadgeVariant`, etc.) replace technical labels
  everywhere (`quote → Orçamento`, `awaiting_info → Aguardando
  informações`, etc.).
- "Abrir detalhe" → "Abrir detalhes" on cards and lists.

### Files added in this addendum

- `src/components/ai/AIOperatorDraftSelectionCard.tsx`
- `src/components/ai/AIOperatorLinkProposalCard.tsx`
- `supabase/migrations/20260523120000_ai_operator_draft_cancel_status.sql`

### Files materially updated in this addendum

- `src/components/ai/AIAgentWidget.tsx`
- `src/components/ai/AIOperatorDraftCard.tsx`
- `src/hooks/use-ai-operator.ts`
- `src/hooks/use-ai-operator-drafts.ts`
- `src/lib/ai-context.ts`
- `src/lib/ai-operator-display.ts`
- `src/pages/AIOperatorDraftDetailPage.tsx`
- `src/pages/AIOperatorDraftListPage.tsx`
- `src/pages/AIOperatorDraftPages.test.tsx`
- `src/test/ai-operator-entity-linking.test.ts`
- `src/test/ai-operator-operational-intent.test.ts`
- `src/test/ai-operator-tools-contract.test.ts`
- `supabase/functions/ai-operator-core/entity-linking.ts`
- `supabase/functions/ai-operator-core/index.ts`
- `supabase/functions/ai-operator-core/operational-intent.ts`
- `supabase/functions/ai-operator-core/prompt.ts`
- `supabase/functions/ai-operator-core/risk.ts`
- `supabase/functions/ai-operator-core/tools.ts`

---

## Session ownership fix — resume_draft endpoint (2026-05-23)

> Commit: `a6b94de`
> Edge function: `ai-operator-core` redeployed, `verify_jwt = true` preserved

### Why this fix exists

After the operational evolution addendum shipped at `a8ddde3`, `selectDraftCandidate`
in `use-ai-operator.ts` had a session mismatch bug:

- Selecting a draft candidate sent `session_id: <new widget session>` with
  `draft_id: <original session's draft>`.
- `findActiveDraft(admin, sessionId, requestedDraftId)` correctly rejected the
  cross-session reference (`requested.session_id !== sessionId`).
- The selection silently fell through and the UI returned to the candidate card
  instead of resuming the selected draft.

### New `resume_draft` action

A new backend endpoint resolves the ownership issue:

1. Accepts `draft_id` from the UI (human-selected, never model-controlled).
2. Validates visibility via the user's JWT client (RLS — same as all other reads).
3. Validates ownership via `sessionBelongsTo(admin, ...)` with service role.
4. Returns `{ ok: true, session_id: originalSessionId, draft_id }` — the
   backend is the authoritative source of the authorized `session_id`.
5. Audits denied attempts as `draft_resume_denied` (security category) and
   successful resumptions as `draft_resumed` (info category).

### `selectDraftCandidate` — two-step secure flow

The hook now:

1. Calls `resume_draft` with the human-selected `draft_id`.
2. Receives `authorizedSessionId` from the backend.
3. Updates hook state: `setSessionId(authorizedSessionId)`, `setActiveDraftId(authorizedDraftId)`.
4. Sends the follow-up chat message with `session_id: authorizedSessionId` — never
   the widget's current `sessionId` from the closure.
5. On error from `resume_draft`: shows error, does NOT call chat, does NOT
   activate the foreign draft in state.

### Floating widget suppressed on draft detail routes

`AIAgentWidget` returns `null` when `context.entityType === 'operator_draft'`
and `context.entityId` is set. The detail page already has a dedicated `Sheet`
drawer (`AIOperatorDraftDetailPage`) — two simultaneous chat contexts for the
same draft would diverge.

The floating widget remains active on `/operator/drafts` (list route, no entity
ID) so users can still interact with the operator from the list context.

### Tests added in this fix

- `ai-operator-tools-contract`: `resume_draft` is not in `OPERATOR_TOOLS` —
  the model cannot trigger session switches.
- `ai-operator-resume-draft` (new file): 4 behavioral tests for `selectDraftCandidate`:
  - calls `resume_draft` first, then `chat` with authorized `session_id`;
  - stops after `resume_draft` and shows error when backend denies ownership;
  - stops after `resume_draft` and shows error on network failure;
  - marks selection card as resolved even when `resume_draft` subsequently fails.

168 tests / 24 test files — all pass.

### Security guarantees still preserved

- `create_draft`, `update_draft` and `register_memory_candidate` continue to
  reject model-controlled `client_id`/`vessel_id`;
- `propose_entity_link` does not accept `draft_id` and does not persist;
- `link_draft_entities` remains the only write path for entity links;
- UUIDs continue to be redacted from chat text;
- no official service order, WhatsApp message, inventory, financial or
  agenda side effect is executed automatically;
- migration applied only to Supabase staging `okurngvcodmljjicopdp`;
- main, `staging/marineflow-functional` and Production untouched.

---

## Structured entity link resolution without model UUIDs (2026-05-23)

### Root cause confirmed

Manual homologation confirmed that `resume_draft` resumed the original
Raymarine draft session successfully, but the next entity-linking turn failed
because the model tried to reuse sanitized internal references. The visible and
model conversation history had replaced UUIDs with `[referencia interna
oculta]`; later, the old `propose_entity_link` contract still expected
`client_id` and `vessel_id`, and `search_vessels` still accepted a
model-controlled `client_id` filter. That allowed the placeholder to reach a
UUID query path and produced a false permission/ownership diagnosis.

This was not treated as an RLS proof. A safe staging read, without exposing IDs
or personal data in reports, confirmed:

- the Célio/Dondoka relation exists as a single compatible match;
- the active Raymarine draft remains unlinked, so no incorrect entity link was
  persisted;
- `ai-operator-core` was ACTIVE before this fix, version 5, with
  `verify_jwt=true`.

### New contract

The model now works with intention and human terms:

- `propose_entity_link` accepts `client_query`, `vessel_query`, and optional
  `rationale`;
- it no longer exposes `client_id`, `vessel_id`, or `draft_id` in the model
  tool schema;
- `search_vessels` no longer exposes a `client_id` filter;
- `get_vessel_history` resolves a vessel by `vessel_query`, not by a model
  supplied `vessel_id`;
- `update_draft`, `add_draft_item`, `ask_pending_question`, and
  `propose_action` operate on the active draft resolved by backend context,
  instead of requiring the model to repeat `draft_id`.

### Resolution behavior

`ai-operator-core` resolves candidates server-side with the authenticated JWT
client, then returns a structured UI proposal only when the result is safe:

- unique compatible client + vessel: show a confirmation card with human names
  and the compatibility message "Esta embarcacao ja esta cadastrada para este
  cliente.";
- ambiguity: return minimized candidate choices for UI selection, not an
  automatic guess;
- not found, invalid sanitized reference, real mismatch, and unexpected
  technical errors are distinct outcomes;
- proposal never persists links. `link_draft_entities` remains the only write
  path after explicit UI confirmation.

### Data minimization

Normal responses now sanitize `tool_events` returned to the browser:

- no raw tool args with internal UUIDs;
- no CPF/CNPJ, phone, WhatsApp, or email in frontend tool-event payloads;
- search results exposed to the model for clients/vessels are minimized to
  human labels needed for conversation;
- full forensic/audit needs remain server-side in `ai_operator_audit`.

### Tests added/updated

- tool contract tests ensure model tools do not expose UUID-based linking or
  draft-scoped IDs;
- entity validation blocks `[referencia interna oculta]` before any DB lookup;
- structured resolution tests cover Célio/Dondoka compatibility, true mismatch,
  ambiguity, no pre-confirmation persistence, and frontend tool-event
  minimization;
- existing `resume_draft`, draft selection, cancellation, and draft-surface
  tests remain passing.

### Explicit non-scope

No migration or migration repair was executed for this correction. The HTTP 400
errors from legacy ERP screens (`external_quote_leads.name`, `clients.name`,
`products.name`, and related schema-canonicalization debt) remain out of scope
for this branch.

---

## Draft lifecycle and pending-action governance hardening (2026-05-24)

### Homologation update

Manual staging homologation after commit `3e1ca50` confirmed:

- `resume_draft` continued to resume the existing Raymarine draft correctly;
- structured entity linking by human terms successfully linked the draft to
  CELIO YUDI SHIOKAWA JUNIOR and the vessel Dondoka;
- compatibility was shown correctly: the vessel was already registered for
  that client;
- no official service order, formal `external_quotes` record, WhatsApp,
  inventory, financial or agenda side effect was executed.

### Governance issue discovered

The same homologation exposed a Macro Cycle 1 governance gap:

- the internal AI Operator draft was promoted to `approved` without a formal
  ERP quote in `external_quotes`;
- three `create_service_order` pending actions existed for the same draft, all
  `approved` and unexecuted;
- an informational question about how to turn the draft into an OS had created
  a high-risk pending action instead of receiving procedural guidance;
- a quote draft was allowed to propose direct OS creation, even though the
  correct product flow is draft -> formal quote -> review/approval -> service
  order.

This state was confirmed by safe staging reads only. No data remediation was
performed in this cycle.

### Lifecycle policy implemented

Model-controlled draft status is now limited to operational states:

- allowed from model tools: `draft`, `awaiting_info`;
- blocked from model tools: `awaiting_approval`, `approved`, `rejected`,
  `converted`, `cancelled`.

If the model attempts a blocked status during `create_draft`, the backend
downgrades to the safe operational default (`awaiting_info` when there are
pending questions, otherwise `draft`) and audits `model_draft_status_blocked`.
If it attempts a blocked status during `update_draft`, safe content updates
still proceed but the governance status is stripped and audited.

`cancelled` remains reachable only through the authenticated cancel endpoint.
`converted` remains reserved for a future formal conversion executor.

### Action proposal governance

`propose_action` now passes through deterministic backend gates before any
`ai_operator_pending_actions` insert:

- informational/hypothetical user messages such as "qual o procedimento",
  "como vira OS" and "quais os proximos passos" are blocked with
  `action_proposal_blocked_informational_request`;
- `create_service_order` for an internal quote draft is blocked with
  `service_order_proposal_blocked_quote_requires_formalization`;
- duplicate open actions for the same `draft_id` and `action_name` in
  `pending` or `approved` status with `executed_at is null` are suppressed with
  `duplicate_pending_action_suppressed`;
- rejected or already executed actions do not count as open duplicates.

The quote-draft block intentionally points to the next Macro Cycle 2 capability:
`create_external_quote_from_draft`. This capability is not implemented in Macro
Cycle 1 and no `external_quotes` rows are created by this hardening.

### Tests added/updated

- lifecycle tests cover blocked governance statuses on `create_draft` and
  `update_draft`;
- tool-contract tests ensure only operational statuses are exposed to the
  model;
- action-governance tests cover informational intent, direct quote-to-OS block,
  allowed explicit diagnosis proposal, and deduplication;
- existing tests for `resume_draft`, structured Célio/Dondoka linking,
  `link_draft_entities`, cancellation and tool-event minimization remain in the
  regression suite.

### Staging remediation remains pending

The contaminated staging data must not be remediated automatically. A future
authorized remediation should:

- preserve the confirmed Célio/Dondoka link;
- move the Raymarine draft back to an operational state appropriate to its
  remaining questions, likely `awaiting_info`;
- reject or otherwise close the three unexecuted `create_service_order`
  pending actions with explicit audit records;
- document that no OS or formal quote was created during the correction.

---

## Protected-state immutability fix (2026-05-24)

Independent review after `4c54f63` found one remaining lifecycle risk:
`update_draft` filtered model-provided governance statuses, but still allowed
content updates when the persisted draft was already in a protected state.

The final policy is now:

- current `draft` or `awaiting_info`: the model may refine safe content and may
  alternate only between these two operational statuses;
- current `awaiting_approval`, `approved`, `rejected`, `converted`, or
  `cancelled`: `update_draft` from the model is fully blocked before any patch
  is applied.

The protected-state block prevents:

- silent remediation of contaminated staging data by the model;
- post-approval changes to title, summary, scope, estimates, questions, next
  steps, or hypotheses;
- reopening or rewriting converted, cancelled, rejected, or awaiting-review
  drafts without a future explicit human flow.

Blocked attempts are audited as
`model_draft_update_blocked_protected_state`. This patch does not add a reopen,
approval, review, quote formalization, or conversion endpoint. The Raymarine
staging draft and the three historical `create_service_order` actions remain
unchanged pending explicit remediation authorization.

---

## Global protected-draft mutation gate (2026-05-24)

Independent review after the v8 immutability patch found that the invariant was
implemented only on `update_draft`. Three parallel mutation paths still needed
the same protection:

- `add_draft_item` could insert new services, products, materials, prices or
  notes into a protected draft;
- `ask_pending_question` could append pending questions to a protected draft;
- `link_draft_entities`, although UI-confirmed, could still change
  client/vessel links on a protected draft without a formal reopen/correction
  flow.

The policy is now centralized:

- mutable operational statuses: `draft`, `awaiting_info`;
- protected statuses: `awaiting_approval`, `approved`, `rejected`,
  `converted`, `cancelled`;
- read/resume operations remain allowed;
- separate-record operations such as `register_memory_candidate` and
  proposal-only operations such as `propose_action` keep their own governance
  because they do not directly mutate draft content.

The following mutation gates are enforced before writes:

- `update_draft`: blocks all model content/status mutations on protected drafts
  and audits `model_draft_update_blocked_protected_state`;
- `add_draft_item`: blocks item insertion and audits
  `model_draft_item_blocked_protected_state`;
- `ask_pending_question`: blocks pending-question updates and audits
  `model_draft_question_blocked_protected_state`;
- `link_draft_entities`: blocks UI entity-link changes and audits
  `draft_entity_link_blocked_protected_state`.

`resume_draft` remains allowed because it resumes viewing/conversation without
changing draft content. `cancel_draft` keeps its existing explicit endpoint
policy: only operational drafts without open pending actions can be cancelled.

This patch still does not remediate staging data, does not create
`external_quotes`, does not create service orders, and does not implement a
reopen/remediation endpoint. The Raymarine draft, its Célio/Dondoka link, its
existing items/questions, and the three historical `create_service_order`
pending actions remain untouched until explicit remediation authorization.
