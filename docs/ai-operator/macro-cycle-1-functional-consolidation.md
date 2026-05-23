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
