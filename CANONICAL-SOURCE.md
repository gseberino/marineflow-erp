# Fonte única da verdade — MarineFlow ERP

> Leia antes de buildar, deployar ou criar branches. Este arquivo existe por
> causa de um incidente real (jun/2026) em que um deploy a partir de uma cópia
> antiga reverteu a migração Evolution e quebrou as colunas em produção.

## Onde trabalhar e deployar

- **Pasta canônica:** `C:\Users\PC\Documents\Claude Code\marineflow-erp`
- **Branch de produção:** `main`
- **Projeto Vercel:** `marineflow-erp` (alias `marineflow-erp.vercel.app`)
- **Projeto Supabase:** `okurngvcodmljjicopdp`

Deploy: a partir da pasta/branch acima → `npm run build && npx vercel --prod`.

## ⚠️ NÃO use estas cópias para deploy

- `C:\Users\PC\Documents\marineflow-staging` — clone antigo, branches divergentes
  (Z-API + nomes de coluna antigos). Deployar dela **regride a produção**.
- Branch `fix/schema-column-sync` — find-replace equivocado; **não mergear**.

## Como evitar drift (regra de ouro)

1. O banco é a fonte da verdade do schema. Antes de mexer em queries, rode
   `npx supabase gen types typescript --project-id okurngvcodmljjicopdp` e
   confira o `types.ts`.
2. Toda alteração de schema aplicada no banco **tem que** virar migration
   versionada em `supabase/migrations/` no mesmo PR.
3. Sinais de que você está na pasta/branch errada: aparece "Enviar via Z-API"
   na UI, ou erro "column ... does not exist" em produção.

## Linha do tempo do incidente (resumo)

- 11/06: migração Z-API → Evolution (commit `a360031`, na `main`).
- 12/06: rename de colunas no banco + frontend (`be13642`, na `main`); a
  migration do rename ficou órfã (só agora versionada).
- 19/06: última versão boa (`f797f73`) → deploy `qq9no6ubk`.
- 20-21/06: deploys a partir de cópia antiga regrediram a produção; restaurado
  via redeploy da `main`.
