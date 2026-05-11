# Plano de Aplicação de Schema no Supabase Staging

## 1. Pré-requisitos

Antes de aplicar qualquer migration, confirmar:

- o Supabase staging foi criado manualmente;
- `.env.staging.local` foi preenchido localmente a partir de `.env.staging.example`;
- o Supabase CLI está instalado e funcional, se for necessário para aplicar migrations;
- `supabase/config.toml` ainda aponta para `project_id = "zssewfqhmrlagqbfqsmb"` e isso não será sobrescrito por engano;
- o projeto de staging não é `vmareepfbgocyleknrgg`;
- o projeto de staging não é `zssewfqhmrlagqbfqsmb`;
- production não será alterado durante essa fase.

## 2. Estratégias possíveis

### A. CLI com projeto staging linkado temporariamente

- útil quando o projeto de staging já existe e está claramente isolado;
- exige disciplina para não deixar o repo apontando para o projeto errado;
- deve ser revertido assim que a validação terminar.

### B. Aplicar migrations SQL manualmente no staging

- útil quando se quer controle explícito do que entra primeiro;
- reduz o risco de link acidental com outro projeto;
- demanda atenção maior para manter a ordem das migrations.

### C. Ambiente temporário separado

- útil para experimentação controlada;
- bom para validar migrations, types e RLS antes de tocar no staging final;
- exige mais gestão manual.

### D. Nunca aplicar no projeto errado

- regra absoluta para qualquer estratégia;
- se houver dúvida de project ref, parar.

## 3. Gate antes de aplicar migrations

Antes de executar qualquer migration, confirmar:

1. o project ref do staging foi anotado localmente;
2. não é `vmareepfbgocyleknrgg`;
3. não é `zssewfqhmrlagqbfqsmb`;
4. o staging é novo e limpo;
5. o backup relevante está preservado;
6. production não será alterado.

## 4. Passo futuro para migrations

Ordem futura recomendada:

1. rodar `migration:check-staging`;
2. aplicar migrations no staging;
3. rodar `migration:check-staging` novamente;
4. gerar types;
5. rodar `migration:validate-staging-schema`;
6. rodar `migration:dry-run:staging`;
7. só então discutir importação.

## 5. Critérios de bloqueio

Parar se houver qualquer um destes sinais:

- project ref errado;
- schema não limpo;
- migrations falhando;
- tabelas críticas ausentes;
- RLS impedindo validação;
- secrets em log ou diff;
- app local não conecta;
- qualquer indício de que production ou o Supabase atual poderiam ser afetados.

## 6. Rollback

- descartar e recriar o staging é preferível a tentar consertar um staging contaminado;
- production e Lovable ficam fora desse rollback.
