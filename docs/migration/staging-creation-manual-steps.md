# Manual de criacao do Supabase staging

## 1. Aviso inicial

Este guia e manual. Nao executar importacao ainda.

Nao conectar Vercel production.
Nao usar secrets do Lovable.
Nao colar `service key` em frontend.
Nao alterar o projeto Supabase atual `vmareepfbgocyleknrgg`.
Nao alterar `zssewfqhmrlagqbfqsmb` sem confirmar antes o que ele representa.
Staging deve ser novo, limpo e isolado.

## 2. Criar novo projeto Supabase

No painel do Supabase, criar um projeto novo com nome sugerido:

`marineflow-erp-staging`

Depois, anotar localmente, sem enviar no chat e sem commit:

```text
STAGING_SUPABASE_PROJECT_REF=
STAGING_SUPABASE_URL=
STAGING_SUPABASE_PUBLISHABLE_KEY=
STAGING_SUPABASE_ANON_KEY=
STAGING_SUPABASE_SERVICE_ROLE_KEY=
```

Regras:

- esses valores nao devem ser enviados no chat;
- nao devem ser commitados;
- devem ficar apenas em `.env.staging.local`;
- `SERVICE_ROLE` so sera usado em scripts locais ou server-side aprovados no futuro.

## 3. Arquivo `.env.staging.local`

Criar um arquivo local nao versionado com este formato base:

```env
VITE_SUPABASE_URL=
VITE_SUPABASE_PUBLISHABLE_KEY=

SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

APP_PUBLIC_URL=http://localhost:5173
```

Regras:

- o arquivo deve ficar local;
- nao deve ser versionado;
- `.gitignore` ja deve bloquear `.env.*.local`;
- nao usar valores de producao por engano.

## 4. Separacao de ambientes

| Ambiente | Projeto Supabase | Uso | Pode receber importacao? | Pode ser usado no Vercel production? |
|---|---|---|---|---|
| Lovable original | origem do backup | referencia historica | nao | nao |
| Supabase atual/controlado `vmareepfbgocyleknrgg` | destino atual | leitura e auditoria local | nao nesta fase | nao |
| Supabase staging novo | ambiente limpo | validacao e importacao futura | sim, quando estiver pronto | nao |
| Vercel production | producao | usuarios finais | nao | sim, somente com o banco correto |
| App local | maquina local | desenvolvimento e validacao | sim, contra staging futuro | nao |

## 5. Depois de criar o staging

Proximos passos tecnicos futuros, sem executar agora:

1. configurar `.env.staging.local`;
2. verificar conexao read-only;
3. aplicar migrations;
4. verificar schema;
5. gerar types;
6. rodar `migration:dry-run`;
7. so depois discutir `migration:import`.

## 6. Criterios de bloqueio manual

Parar se ocorrer qualquer um destes casos:

- o usuario nao tiver certeza se esta no projeto certo;
- o painel mostrar `vmareepfbgocyleknrgg`;
- o painel mostrar o projeto Lovable/origem;
- houver duvida sobre a regiao;
- houver duvida sobre a senha do banco;
- qualquer chave for copiada para o lugar errado;
- qualquer valor secreto aparecer no terminal, no chat ou em arquivo versionado.

## 7. Bloco para preenchimento depois

Preencher apenas depois, sem colar valores sensiveis:

```text
Staging criado: sim/nao
Nome do projeto:
Project ref:
Project URL configurada localmente: sim/nao
Publishable/anon configurada localmente: sim/nao
Service role configurada localmente: sim/nao
.env.staging.local criado: sim/nao
```

Nao colar chaves reais aqui.

