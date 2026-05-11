# Supabase Staging Checklist

## 1. Objetivo

Criar um Supabase staging limpo para validar a migração Lovable -> Vercel/Supabase sem contaminar produção.

Regras de uso desta fase:

- staging não é produção;
- não usar dados reais além do backup controlado;
- não usar Lovable como fonte de secrets;
- não usar `service_role` no frontend;
- não apontar Vercel production para staging;
- não importar em produção nesta fase.

## 2. Decisão técnica

Decisão: **B1 - novo projeto Supabase staging**

Motivos:

- melhor isolamento;
- menor risco de confundir produção com teste;
- rollback mais simples;
- comparação mais confiável;
- evita mexer no Supabase destino contaminado;
- evita a complexidade de schema separado no mesmo projeto.

Alternativas recusadas:

- B2 - schema separado no mesmo projeto;
- B3 - limpar banco atual e reimportar;
- B4 - database branch/branch Supabase, se disponível, como alternativa conceitual.

## 3. Pré-requisitos manuais

Depois, manualmente, será preciso:

- criar um novo projeto Supabase staging;
- escolher a região;
- usar o nome sugerido `marineflow-erp-staging`;
- anotar Project URL;
- anotar Project Ref;
- anotar publishable/anon key;
- anotar service/secret key apenas para uso server-side local seguro;
- nunca colocar service key em `VITE_*`;
- criar um arquivo local `.env.staging.local` não versionado;
- partir de `.env.staging.example` como template;
- configurar Vercel Preview futuramente, não production.

## 4. Variáveis de ambiente

| Variável | Ambiente | Público? | Uso | Observação |
|---|---|---:|---|---|
| `VITE_SUPABASE_URL` | local/staging preview | sim | Client web com leitura publicável | Nunca guardar segredo aqui |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | local/staging preview | sim | Client web com leitura publicável | Não é service key |
| `SUPABASE_URL` | local/server/staging tools | não | CLI, scripts e validação | Pode ser o mesmo endpoint do staging |
| `SUPABASE_ANON_KEY` | local/server/staging tools | sim | Leitura pública controlada | Não usar para escrita privilegiada |
| `SUPABASE_SERVICE_ROLE_KEY` | local/server-side seguro | não | Apenas tarefas server-side autorizadas | Nunca versionar nem expor ao frontend |
| `VITE_VAPID_PUBLIC_KEY` | local/staging preview | sim | Notificações públicas no cliente | Pública apenas |
| `VAPID_PRIVATE_KEY` | local/server-side seguro | não | Assinatura server-side | Nunca versionar |
| `VAPID_SUBJECT` | local/server-side seguro | não | Identificação de envio | Não sensível, mas manter fora do frontend |
| `ZAPI_INSTANCE_ID` | local/server-side seguro | não | Integração externa | Manter fora do cliente |
| `ZAPI_TOKEN` | local/server-side seguro | não | Integração externa | Secreto |
| `ZAPI_CLIENT_TOKEN` | local/server-side seguro | não | Integração externa | Secreto |
| `GEMINI_API_KEY` | local/server-side seguro | não | Integração externa | Secreto |
| `APP_PUBLIC_URL` | local/staging/production | sim | Link base da aplicação | Deve apontar para o ambiente certo |

Regras:

- `VITE_*` somente público;
- `SUPABASE_SERVICE_ROLE_KEY` apenas local seguro/server-side;
- ZAPI/Gemini/VAPID private apenas server-side;
- nenhum segredo versionado;
- `.env.staging.local` deve estar no `.gitignore`.

Como usar depois:

1. copiar `.env.staging.example` para `.env.staging.local`;
2. preencher localmente;
3. usar `npm.cmd run migration:check-staging` quando o staging existir;
4. usar `npm.cmd run migration:dry-run:staging` quando o staging existir;
5. não rodar `migration:import` ainda.

## 5. Schema e migrations

Fluxo futuro:

1. criar o staging;
2. apontar o Supabase CLI para o projeto staging;
3. aplicar migrations;
4. verificar tabelas;
5. verificar functions e RPCs;
6. verificar RLS;
7. gerar types;
8. comparar `types.ts`.

Observação importante:

- `supabase/config.toml` hoje aponta para `project_id = "zssewfqhmrlagqbfqsmb"`;
- isso não deve ser alterado sem plano;
- staging deve usar variáveis ou configuração de CLI controlada;
- não sobrescrever produção.

## 6. Edge Functions

Existem Edge Functions no repo e elas precisam ser avaliadas antes do staging.

Atenção especial para funções com JWT desabilitado:

- `whatsapp-webhook`;
- `submit-signature`;
- `whatsapp-process-scheduled`.

Riscos:

- funções sem JWT precisam validação de segurança;
- secrets server-side devem ser configurados no staging;
- não copiar secrets de produção cegamente;
- integrações externas como WhatsApp, ZAPI e Gemini podem ficar desativadas inicialmente no staging.

## 7. Fluxo de validação de dados

Fluxo futuro:

1. rodar `migration:analyze` no backup Lovable;
2. rodar `migration:check-staging` contra staging vazio;
3. rodar `migration:dry-run` contra staging vazio;
4. confirmar que o staging está realmente vazio antes da importação;
5. implementar importação real apenas com `CONFIRM_IMPORT=true`;
6. rodar `migration:validate`;
7. validar contagens;
8. validar duplicados;
9. validar órfãos;
10. validar OSs com vínculos;
11. validar financeiro;
12. validar logs e audit;
13. testar a app local apontando para staging.

## 8. Critérios de sucesso

- schema aplicado sem erro;
- migrations aplicadas;
- types gerados;
- readiness check mostra staging acessível ou bloqueado de forma esperada;
- dry-run sem schema errors;
- importação real executada apenas em staging;
- contagens batem com o backup quando aplicável;
- zero órfãos críticos;
- duplicados naturais documentados;
- app local abre e navega nos módulos principais;
- Vercel production não foi alterado;
- Lovable não foi alterado.

## 9. Critérios de bloqueio

Parar se ocorrer qualquer um destes pontos:

- migration falha;
- tabela crítica ausente;
- schema diverge;
- RLS impede validação;
- importação geraria duplicação não controlada;
- órfãos críticos;
- secrets aparecem em diff ou log;
- app local quebra em módulos principais;
- qualquer risco de apontar production para staging ou staging para production.

## 10. Plano de rollback

- staging pode ser descartado sem afetar produção;
- se a importação falhar, apagar e recriar o staging é preferível a tentar consertar dados contaminados;
- produção e Lovable permanecem intactas nesta fase.

## 11. Próximos comandos futuros

Exemplos de comandos futuros, apenas para referência:

```powershell
# Futuro - exemplo, não executar agora
npm.cmd run migration:analyze -- "D:\Dowloads SSD\EXPORTAÇÃO MARINEFLOW\marineflow_backup_2026-05-10.json"

# Futuro - readiness check contra staging com env staging carregado
npm.cmd run migration:check-staging

# Futuro - dry-run contra staging com env staging carregado
npm.cmd run migration:dry-run:staging -- "D:\Dowloads SSD\EXPORTAÇÃO MARINEFLOW\marineflow_backup_2026-05-10.json"

# Futuro - importação real somente em staging
$env:CONFIRM_IMPORT="true"
npm.cmd run migration:import -- "D:\Dowloads SSD\EXPORTAÇÃO MARINEFLOW\marineflow_backup_2026-05-10.json"

# Futuro - validação
npm.cmd run migration:validate
```

Importante: `migration:import` não deve ser executado agora.

## 12. Estado atual conhecido

- branch local: `codex/migration-audit`;
- commits locais:
  - `0c7f0f3 chore: prepare safe migration audit tooling`;
  - `78fc994 chore: enable read-only migration dry run`;
- backup Lovable: 23 tabelas;
- recomendação atual: B1 staging limpo;
- Supabase destino atual não deve receber nova importação;
- secrets ainda não foram rotacionados;
- push e deploy continuam proibidos.
