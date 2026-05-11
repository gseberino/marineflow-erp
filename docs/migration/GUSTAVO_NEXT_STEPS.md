# Handoff Final Para Gustavo

## Estado atual

Estamos na branch local `codex/migration-audit`.

Commits locais existentes:
- `0c7f0f3` `chore: prepare safe migration audit tooling`
- `78fc994` `chore: enable read-only migration dry run`
- `ffaf48f` `docs: add Supabase staging migration checklist`
- `dd9611d` `docs: add manual Supabase staging creation steps`
- `4389f8a` `chore: add staging env support for migration tools`
- `9cc245e` `chore: prepare staging readiness workflow`
- `babc98b` `docs: add final local migration handoff`

O que já está pronto:
- build passou;
- testes passaram;
- `migration:analyze` passou;
- `migration:dry-run` read-only funciona com chave pública;
- `migration:check-staging` existe e responde de forma segura;
- documentação de staging foi criada;
- o fechamento local foi reconciliado com o HEAD real da branch;
- pacote local de preservação existe;
- nada foi enviado ao GitHub;
- produção não foi alterada;
- banco não foi alterado.

## O que nao fazer ainda

- nao fazer push;
- nao conectar Vercel;
- nao mexer no Lovable;
- nao importar dados;
- nao rodar `migration:import`;
- nao colar chaves no chat;
- nao alterar o Supabase atual `vmareepfbgocyleknrgg`;
- nao alterar `zssewfqhmrlagqbfqsmb`;
- nao usar `service_role` no frontend;
- nao publicar branch enquanto Vercel e Lovable nao estiverem contidos.

## Proxima acao manual do Gustavo

1. Criar um novo projeto Supabase chamado `marineflow-erp-staging`.
2. Nao usar projetos existentes para essa etapa.
3. Nao conectar Vercel production.
4. Anotar localmente, sem compartilhar:
   - Project Ref;
   - Project URL;
   - Publishable/anon key;
   - Service role/secret key.
5. Criar `.env.staging.local` a partir de `.env.staging.example`.
6. Nunca colar esses valores no chat ou no Git.

## Bloco seguro para preencher

```text
Staging criado: sim/nao
Nome do projeto:
Project Ref anotado localmente: sim/nao
Project URL configurada no .env.staging.local: sim/nao
Publishable/anon key configurada no .env.staging.local: sim/nao
Service role configurada no .env.staging.local: sim/nao
.env.staging.local criado: sim/nao
```

## Comandos futuros depois do staging criado

```powershell
npm.cmd run migration:check-staging
npm.cmd run migration:dry-run:staging -- "D:\Dowloads SSD\EXPORTAÇÃO MARINEFLOW\marineflow_backup_2026-05-10.json"
```

Ordem esperada:
- primeiro `migration:check-staging`;
- se falhar, parar;
- nao rodar `migration:import`;
- so aplicar migrations depois de nova avaliacao;
- so usar service role quando a etapa for explicitamente aprovada.

## Quando parar e pedir nova avaliacao

Parar se:
- houver duvida se o projeto criado e o certo;
- aparecer `vmareepfbgocyleknrgg`;
- aparecer `zssewfqhmrlagqbfqsmb`;
- `migration:check-staging` falhar;
- qualquer secret aparecer em terminal, chat ou diff;
- qualquer comando pedir confirmacao de escrita no banco;
- qualquer comando mencionar production.

## Onde estao os documentos tecnicos

- `docs/migration/staging-creation-manual-steps.md`
- `docs/migration/supabase-staging-checklist.md`
- `docs/migration/staging-schema-application-plan.md`
- `docs/migration/local-branch-status.md`
- `docs/migration/schema-migrations-inventory.md`
- `scripts/migration/README.md`
