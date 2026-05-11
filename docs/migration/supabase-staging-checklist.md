# Supabase Staging Checklist

## 1. Objetivo

Criar um Supabase staging limpo para validar a migração Lovable -> Vercel/Supabase sem contaminar produção.

Regras de uso desta fase:

- staging nao e producao;
- nao usar dados reais alem do backup controlado;
- nao usar Lovable como fonte de secrets;
- nao usar `service_role` no frontend;
- nao apontar Vercel production para staging;
- nao importar em producao nesta fase.

## 2. Decisao tecnica

Decisao: **B1 - novo projeto Supabase staging**

Motivos:

- melhor isolamento;
- menor risco de confundir producao com teste;
- rollback mais simples;
- comparacao mais confiavel;
- evita mexer no Supabase destino contaminado;
- evita a complexidade de schema separado no mesmo projeto.

Alternativas recusadas:

- B2 - schema separado no mesmo projeto;
- B3 - limpar banco atual e reimportar;
- B4 - database branch/branch Supabase, se disponivel, como alternativa conceitual.

## 3. Pre-requisitos manuais

Depois, manualmente, sera preciso:

- criar um novo projeto Supabase staging;
- escolher a regiao;
- usar o nome sugerido `marineflow-erp-staging`;
- anotar Project URL;
- anotar Project Ref;
- anotar publishable/anon key;
- anotar service/secret key apenas para uso server-side local seguro;
- nunca colocar service key em `VITE_*`;
- criar um arquivo local `.env.staging.local` nao versionado;
- configurar Vercel Preview futuramente, nao production.

## 4. Variaveis de ambiente

| Variavel | Ambiente | Publico? | Uso | Observacao |
|---|---|---:|---|---|
| `VITE_SUPABASE_URL` | local/staging preview | sim | Client web com leitura publicavel | Nunca guardar segredo aqui |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | local/staging preview | sim | Client web com leitura publicavel | Nao e service key |
| `SUPABASE_URL` | local/server/staging tools | nao | CLI, scripts e validacao | Pode ser o mesmo endpoint do staging |
| `SUPABASE_ANON_KEY` | local/server/staging tools | sim | Leitura publica controlada | Nao usar para escrita privilegiada |
| `SUPABASE_SERVICE_ROLE_KEY` | local/server-side seguro | nao | Apenas tarefas server-side autorizadas | Nunca versionar nem expor ao frontend |
| `VITE_VAPID_PUBLIC_KEY` | local/staging preview | sim | Notificacoes publicas no cliente | Publica apenas |
| `VAPID_PRIVATE_KEY` | local/server-side seguro | nao | Assinatura server-side | Nunca versionar |
| `VAPID_SUBJECT` | local/server-side seguro | nao | Identificacao de envio | Nao sensivel, mas manter fora do frontend |
| `ZAPI_INSTANCE_ID` | local/server-side seguro | nao | Integracao externa | Manter fora do cliente |
| `ZAPI_TOKEN` | local/server-side seguro | nao | Integracao externa | Secreto |
| `ZAPI_CLIENT_TOKEN` | local/server-side seguro | nao | Integracao externa | Secreto |
| `GEMINI_API_KEY` | local/server-side seguro | nao | Integracao externa | Secreto |
| `APP_PUBLIC_URL` | local/staging/production | sim | Link base da aplicacao | Deve apontar para o ambiente certo |

Regras:

- `VITE_*` somente publico;
- `SUPABASE_SERVICE_ROLE_KEY` apenas local seguro/server-side;
- ZAPI/Gemini/VAPID private apenas server-side;
- nenhum segredo versionado;
- `.env.staging.local` deve estar no `.gitignore`.

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

Observacao importante:

- `supabase/config.toml` hoje aponta para `project_id = "zssewfqhmrlagqbfqsmb"`;
- isso nao deve ser alterado sem plano;
- staging deve usar variaveis ou configuracao de CLI controlada;
- nao sobrescrever producao.

## 6. Edge Functions

Existem Edge Functions no repo e elas precisam ser avaliadas antes do staging.

Atenção especial para funcoes com JWT desabilitado:

- `whatsapp-webhook`;
- `submit-signature`;
- `whatsapp-process-scheduled`.

Riscos:

- funcoes sem JWT precisam validacao de seguranca;
- secrets server-side devem ser configurados no staging;
- nao copiar secrets de producao cegamente;
- integracoes externas como WhatsApp, ZAPI e Gemini podem ficar desativadas inicialmente no staging.

## 7. Fluxo de validacao de dados

Fluxo futuro:

1. rodar `migration:analyze` no backup Lovable;
2. rodar `migration:dry-run` contra staging vazio;
3. confirmar que o staging esta realmente vazio antes da importacao;
4. implementar importacao real apenas com `CONFIRM_IMPORT=true`;
5. rodar `migration:validate`;
6. validar contagens;
7. validar duplicados;
8. validar orfaos;
9. validar OSs com vinculos;
10. validar financeiro;
11. validar logs e audit;
12. testar a app local apontando para staging.

## 8. Criterios de sucesso

- schema aplicado sem erro;
- migrations aplicadas;
- types gerados;
- dry-run sem schema errors;
- importacao real executada apenas em staging;
- contagens batem com o backup quando aplicavel;
- zero orfaos criticos;
- duplicados naturais documentados;
- app local abre e navega nos modulos principais;
- Vercel production nao foi alterado;
- Lovable nao foi alterado.

## 9. Criterios de bloqueio

Parar se ocorrer qualquer um destes pontos:

- migration falha;
- tabela critica ausente;
- schema diverge;
- RLS impede validacao;
- importacao geraria duplicacao nao controlada;
- orfaos criticos;
- secrets aparecem em diff ou log;
- app local quebra em modulos principais;
- qualquer risco de apontar production para staging ou staging para production.

## 10. Plano de rollback

- staging pode ser descartado sem afetar producao;
- se a importacao falhar, apagar e recriar o staging e preferivel a tentar consertar dados contaminados;
- producao e Lovable permanecem intactos nesta fase.

## 11. Proximos comandos futuros

Exemplos de comandos futuros, apenas para referencia:

```powershell
# Futuro - exemplo, nao executar agora
npm.cmd run migration:analyze -- "D:\Dowloads SSD\EXPORTACAO MARINEFLOW\marineflow_backup_2026-05-10.json"

# Futuro - dry-run contra staging com env staging carregado
npm.cmd run migration:dry-run -- "D:\Dowloads SSD\EXPORTACAO MARINEFLOW\marineflow_backup_2026-05-10.json"

# Futuro - importacao real somente em staging
$env:CONFIRM_IMPORT="true"
npm.cmd run migration:import -- "D:\Dowloads SSD\EXPORTACAO MARINEFLOW\marineflow_backup_2026-05-10.json"

# Futuro - validacao
npm.cmd run migration:validate
```

Importante: `migration:import` nao deve ser executado agora.

## 12. Estado atual conhecido

- branch local: `codex/migration-audit`;
- commits locais:
  - `0c7f0f3 chore: prepare safe migration audit tooling`;
  - `78fc994 chore: enable read-only migration dry run`;
- backup Lovable: 23 tabelas;
- recomendacao atual: B1 staging limpo;
- Supabase destino atual nao deve receber nova importacao;
- secrets ainda nao foram rotacionados;
- push e deploy continuam proibidos.

