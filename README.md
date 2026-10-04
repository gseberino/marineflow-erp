# MarineFlow ERP

ERP da HBR Marine: ordens de serviço e orçamentos, estoque, compras e cotações, financeiro
(extrato bancário, conciliação, contas a pagar e a receber, fechamento do mês), emissão de NF-e e
NFS-e, agenda e o assistente de IA pelo WhatsApp e pelo painel.

## Stack

- **Frontend:** React + Vite + TypeScript, Tailwind e shadcn/ui (`src/`). Publicado na Vercel a cada
  push na `main`.
- **Backend:** Supabase — Postgres com RLS, migrations em `supabase/migrations/`, Edge Functions em
  Deno em `supabase/functions/` (publicadas à mão, uma a uma).
- **WhatsApp:** Evolution API rodando no PC da HBR, exposta por túnel (o provedor Z-API é legado).
- **IA:** Claude (Anthropic) no assistente; ferramentas em `supabase/functions/_shared/ai/tools/`.

## Rodar

```bash
npm install
npm run dev          # site local
npm run typecheck    # tsc -b (o --noEmit não checa nada neste projeto)
npm test             # vitest
npm run check:edge   # deno check de todas as Edge Functions
npm run test:edge    # testes Deno das Edge Functions
npm run build
```

Testes do banco: `supabase/tests/*.sql`, cada um termina em `ROLLBACK`
(`npx supabase db query --linked -f supabase/tests/<arquivo>.sql`).

## Onde está o quê

- `CLAUDE.md` — regras de trabalho no repositório (migrations, segurança, testes).
- `audit/` — auditorias e achados (`novos-achados.md` é a fila viva de defeitos).
- `plans/` — planos por frente; `docs/` — playbooks (NFS-e nacional, devolução).
- O estado do dia a dia (o que está no ar, o que espera decisão) fica no Diário de Bordo, fora do
  repositório.

`.lovable/plan.md` e `docs/HANDOFF-EVOLUTION-CUTOVER.md` são registros históricos de maio/julho de
2026, não descrevem o sistema atual.
