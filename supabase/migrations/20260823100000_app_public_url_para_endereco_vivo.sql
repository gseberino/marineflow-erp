-- ═══════════════════════════════════════════════════════════════════════════
-- `app_public_url` passa a apontar para um endereço que FUNCIONA
--
-- ═══ O QUE ESTÁ QUEBRADO (NOVO-lev-42) ═══
--
-- `hbrmarine.online` serve um build antigo, de antes da troca de projeto
-- Supabase, e o projeto daquele build (`zssewfqhmrlagqbfqsmb`) não existe mais —
-- o host nem resolve. Todo `/view/<token>` aberto por lá mostra
-- "Documento indisponível — TypeError: Failed to fetch".
--
-- Medido: o domínio responde `Server: cloudflare` e NÃO está configurado na
-- Vercel (o projeto tem só os dois `.vercel.app`). Os deploys de produção saem
-- normalmente e apontam para o projeto certo — quem está velho é o domínio.
--
-- ═══ O QUE ESTA MIGRATION RESOLVE, E O QUE NÃO ═══
--
-- Existem DUAS fontes de link para o cliente:
--
--   1. As telas do ERP montam com `window.location.origin` — o endereço que a
--      pessoa tem aberto. Esta migration NÃO os afeta.
--   2. O agente de IA e o worker de WhatsApp agendado leem `app_public_url`
--      (`_shared/ai/tools/whatsapp.ts`, `whatsapp-process-scheduled`). Estes
--      estavam mandando o link morto SEMPRE, sem depender de quem clicou.
--
-- Só o caso 2 é consertado aqui, e só para links NOVOS. Os já enviados continuam
-- apontando para o `.online`.
--
-- ═══ POR QUE UM `.vercel.app`, E POR QUANTO TEMPO ═══
--
-- `marineflow-erp.vercel.app` é o alias de produção do projeto: responde 200,
-- acompanha o último deploy e aponta para `okurngvcodmljjicopdp`. Não é bonito
-- num link de cliente — é provisório.
--
-- O conserto de raiz é apontar `hbrmarine.online` para a Vercel (acrescentar o
-- domínio no projeto e mudar o DNS no Cloudflare). Feito isso, esta linha volta
-- para o `.online` — é um UPDATE de uma linha.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

update public.app_settings
   set value = 'https://marineflow-erp.vercel.app'
 where key = 'app_public_url';

-- A chave pode simplesmente não existir num ambiente novo.
insert into public.app_settings (key, value)
select 'app_public_url', 'https://marineflow-erp.vercel.app'
where not exists (select 1 from public.app_settings where key = 'app_public_url');

commit;
