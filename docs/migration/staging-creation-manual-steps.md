# Manual de criação do Supabase staging

## 1. Aviso inicial

Este guia é manual. Não executar importação ainda.

Não conectar Vercel production.
Não usar secrets do Lovable.
Não colar `service key` em frontend.
Não alterar o projeto Supabase atual `vmareepfbgocyleknrgg`.
Não alterar `zssewfqhmrlagqbfqsmb` sem confirmar antes o que ele representa.
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

- esses valores não devem ser enviados no chat;
- não devem ser commitados;
- devem ficar apenas em `.env.staging.local`;
- `SERVICE_ROLE` só será usado em scripts locais ou server-side aprovados no futuro.

## 3. Arquivo `.env.staging.local`

Criar um arquivo local não versionado com este formato base:

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
- não deve ser versionado;
- `.gitignore` já deve bloquear `.env.*.local`;
- não usar valores de produção por engano.

## 4. Separação de ambientes

| Ambiente | Projeto Supabase | Uso | Pode receber importação? | Pode ser usado no Vercel production? |
|---|---|---|---|---|
| Lovable original | origem do backup | referência histórica | não | não |
| Supabase atual/controlado `vmareepfbgocyleknrgg` | destino atual | leitura e auditoria local | não nesta fase | não |
| Supabase staging novo | ambiente limpo | validação e importação futura | sim, quando estiver pronto | não |
| Vercel production | produção | usuários finais | não | sim, somente com o banco correto |
| App local | máquina local | desenvolvimento e validação | sim, contra staging futuro | não |

## 5. Depois de criar o staging

Próximos passos técnicos futuros, sem executar agora:

1. configurar `.env.staging.local`;
2. verificar conexão read-only;
3. aplicar migrations;
4. verificar schema;
5. gerar types;
6. rodar `migration:check-staging`;
7. rodar `migration:dry-run:staging`;
8. só depois discutir `migration:import`.

## 6. Critérios de bloqueio manual

Parar se ocorrer qualquer um destes casos:

- o usuário não tiver certeza se está no projeto certo;
- o painel mostrar `vmareepfbgocyleknrgg`;
- o painel mostrar o projeto Lovable/origem;
- houver dúvida sobre a região;
- houver dúvida sobre a senha do banco;
- qualquer chave for copiada para o lugar errado;
- qualquer valor secreto aparecer no terminal, no chat ou em arquivo versionado.

## 7. Bloco para preenchimento depois

Preencher apenas depois, sem colar valores sensíveis:

```text
Staging criado: sim/nao
Nome do projeto:
Project ref:
Project URL configurada localmente: sim/nao
Publishable/anon configurada localmente: sim/nao
Service role configurada localmente: sim/nao
.env.staging.local criado: sim/nao
```

Não colar chaves reais aqui.

## 8. Como usar o `.env.staging.local` depois de criado

1. Copiar `.env.staging.example` para `.env.staging.local`.
2. Preencher os valores localmente, sem enviar para o chat.
3. Rodar `npm.cmd run migration:check-staging`.
4. Rodar `npm.cmd run migration:dry-run:staging -- "D:\Dowloads SSD\EXPORTAÇÃO MARINEFLOW\marineflow_backup_2026-05-10.json"`.
5. Rodar `npm.cmd run migration:validate:staging` somente quando o staging estiver pronto.
6. Não rodar `migration:import` ainda.
