-- Prova da ficha paga, parte B (18/11/2026, migration 20270126100000; plano agenda-pesquisa/via-os129-1711/plano/F2b/RESUMO.md), com as
-- respostas do dono de 18/11: "já começou" = "Só antes de começar"; "concluída" = "Nunca mandar"; "mande antes da baixa" = "Continua
-- valendo" (o F5 de agenda_ficha_paga.sql). Sobre a carteira REAL de 29/10 (o replay da 7a: o Lenine, OS-00074, pela estimativa — o João
-- em ter 03 e qua 04 (o dia 1 é ter 03), o Roberto de qui 05 a ter 10/11; o Vanderlei, OS-00069, a partir de qui 12/11; o ligar do gestor
-- qui 29/10 16:46, a janela da ficha de 21 dias).
-- bancada: depende de 20270126100000
--
--   B0 as portas e o que é (sem fixture; roda também em produção depois de aplicar): as 3 leituras novas invoker, STABLE, authenticated e
--      service_role, nunca anon; as 7 recriadas com as portas de antes; a OS que não existe não começou; tirados os blocos "-- FICHA PAGA B:",
--      as 7 são as de produção (a F2; a saúde, a resposta da equipe e o decidir de 18/11), byte a byte, pelo md5; tirados também os da F2,
--      a liberada, as fichas e a ficha das 19:30 são as de antes da F2; os comentários são os de antes com o "FICHA PAGA B" no fim
--   B1 o começou só por PROVA DE TRABALHO do técnico (revisões do coordenador e respostas do dono P1 e P4, 18/11): o dia só planejado nunca
--      conta (o caso OS-00129); o dia de antes "cumprido" ou "parcial" conta, "não cumprido" e o "sem registro" da vigia não; o check-in,
--      o "em andamento" e a reabertura com check-in NÃO contam (com o "como foi" OK, sim); a confirmação da manhã respondida "sim" sem
--      divergência por quem estava na OS num turno que confirmou; a diária lançada (aprovada) na OS; horas apontadas ou passo iniciado. O
--      próprio dia nunca conta
--   B2 a OS paga que AINDA NÃO começou fica segurada: a pergunta de sex 30/10 para a ficha de ter 03/11 (o dia 1) diz "já está PAGA e
--      ainda não começou: o serviço ainda vai ser feito?" (padrão e recomendação 2); às 19:30 a ficha fica, o porquê ao dono, a pergunta
--      fecha com o motivo dela; com o dia 1 só planejado, o dia 2 continua segurado (B2c); só o check-in e "em andamento" seguram (B2d); a
--      reabertura com check-in segura (B2e)
--   B3 a OS paga que JÁ começou (o "como foi" do dia 1 e do 2 respondido) volta à regra de antes: dentro da janela, a pergunta de sempre
--      (padrão 1, sem o PAGA) e, mostrada, a ficha sai sem *mande*; fora da janela e sem o ligar do gestor, nenhuma pergunta e a ficha sai
--   B4 a OS concluída, faturada ou cancelada nunca manda a ficha: sem pergunta, a ficha fica (recusada, veto), o porquê "a OS já está
--      concluída" ("faturada", "cancelada"), por concluida; nem com o *mande*; fora da janela e sem o ligar; de qualquer alocação; a
--      confirmação da manhã e a ficha do "como foi" também ficam; a pergunta aberta fecha com o motivo dela; o dono sempre tem a ficha;
--      (P3) a cancelada; (correção da revisão) o *mande* depois da conclusão responde "A OS-… já está concluída: a ficha não sai."
--   B5 o dia misto: o parêntese cita TODAS as OS do dia e o porquê nomeia a encerrada ou a paga; a encerrada vence a paga; duas OS pagas
--      no dia: a pergunta no plural ("As … já estão PAGAS e ainda não começaram: os serviços ainda vão ser feitos?")
--   B6 a saúde (C4 da revisão da F2): um fechamento ligado de 1.100 letras com a crítica numerada, a do gestor na CURTA da ficha paga
--      ("… eu seguro a ficha. Para mandar, me diga *mande*.") e a do cliente não é bloco_grande; na saúde de produção (sem o bloco B) era;
--      com a curta de antes ("Para segurar, me diga.") as duas não contam. (O mesmo pelo caminho de verdade, com a fixture da 7f: P6p de
--      agenda_prazo_no_bloco.sql.)
--   B7 (P2) "o que tem pra amanhã?" com a ficha segurada: "Vou ver com <dono> e te falo." e a pergunta equipe_resposta ao dono (OS paga sem
--      *mande*; OS concluída); com a ficha liberada, o plano como antes
--   V3 (revisão da v2, wf_aa4ccd8c) B2f: o "2) Segure" do dono vale mesmo se a prova de trabalho chega depois (o obrigatório); B2g: o Segure de OS não paga, o de antes; B7d–B7g:
--      a P2 em sombra, com o *mande* dado, só pelo veto da estimativa, e duas vezes no dia; B4j: a alocação cancelada da OS encerrada no
--      dia misto; B4k: o *mande* depois da baixa (faturada, cancelada); B1g–B1i: passo de outra OS, o "ok" à ficha, o turno normal;
--      B9a/B9b DOCUMENTAM o "ok" ao "como foi" de um dia segurado (vira prova; muda na F2c, com o cartão ao dono)
--   X  os casos da revisão adversarial (X01–X08: quem estava na OS, a alocação cancelada, "presença", a diária paga, folga e falta, a de
--      outra OS, o passo no próprio dia, as horas de outra OS, o dia feito de outra OS, o fuso, o dia misto com *mande*)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_ficha_paga_b.sql
--   Seguro em produção: B0 só lê; B1 a B9, V3 e X usam o replay e só rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select py.id from public.payees py where py.name = p_nome and py.active order by py.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O texto sem os blocos "-- FICHA PAGA B: … -- FICHA PAGA B: fim" (contados por nível) e, com p_f2, também sem os "-- FICHA PAGA:" da F2
-- (a linha de antes que um bloco trocou volta: "--antes:" na coluna 0).
create function pg_temp.sem_b(p text, p_f2 boolean default false) returns text language sql immutable as $f$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ x.abre and l !~ x.fim then 1 when l ~ x.fim then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ x.fim as fecha
                     from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o),
                          (select case when p_f2 then '^\s*-- FICHA PAGA( B)?:' else '^\s*-- FICHA PAGA B:' end as abre,
                                  case when p_f2 then '^\s*-- FICHA PAGA( B)?: fim' else '^\s*-- FICHA PAGA B: fim' end as fim) x) y
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$f$;
-- O replay com o gestor ligado (o ligar de qui 29/10 16:46), o Lenine e o Vanderlei pela estimativa (como a 7a P11) e o João na rotina.
create function pg_temp.fixtures() returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  execute current_setting('agenda_teste.replay2910');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  update public.payees set phone = '5547900000004' where name = 'João' and phone is null;
  update public.agenda_config
     set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
         modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03',
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
  v_p := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00069'), pg_temp.os('OS-00074')], '{}'::jsonb, true, 'vigia',
                              null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
  v_p := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-10-29',
                               timestamptz '2026-10-29 16:52-03');
  -- o João na rotina (no replay ele não está): a ficha de ter 03/11 é dele
  insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
  values (pg_temp.pessoa('João'), true, 'dono', timestamptz '2026-10-20 10:00-03')
  on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
  return v_p;
end $f$;
-- Uma conta a receber paga: o que falta para a OS ficar paga por inteiro.
create function pg_temp.pagar(p_os uuid) returns void language plpgsql as $f$
begin
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                  balance_amount, is_deposit)
  select gen_random_uuid(), so.client_id, so.id, 'Pago (teste da ficha paga B)', date '2026-10-20', date '2026-10-20', f.falta, 'paid', f.falta, 0, false
    from public.service_orders so,
         lateral (select so.grand_total - coalesce((select sum(coalesce(r.paid_amount, 0)) from public.receivables r
                                                     where r.service_order_id = so.id and r.status is distinct from 'cancelled'), 0) as falta) f
   where so.id = p_os;
end $f$;
-- O status gravado direto (só para a leitura: a porta da OS faria mais coisas) e o check-in.
create function pg_temp.status(p_os uuid, p_status text, p_check_in timestamptz default null) returns void language plpgsql as $f$
begin
  alter table public.service_orders disable trigger user;
  update public.service_orders set status = p_status, check_in_at = coalesce(p_check_in, check_in_at) where id = p_os;
  alter table public.service_orders enable trigger user;
end $f$;
-- Mexe na alocação vigente de uma pessoa num dia (turno opcional) sem os gatilhos: a OS, o resultado, o estado, o tipo, a fonte.
create function pg_temp.aloc(p_os uuid, p_dia date, p_set text, p_payee uuid default null, p_turno text default null) returns int language plpgsql as $f$
declare
  v_n int;
begin
  alter table public.agenda_alocacoes disable trigger user;
  execute format('update public.agenda_alocacoes set %s where service_order_id = $1 and dia = $2 and estado in (''publicada'', ''fixada'')
                    and ($3 is null or payee_id = $3) and ($4 is null or turno = $4)', p_set)
    using p_os, p_dia, p_payee, p_turno;
  get diagnostics v_n = row_count;
  alter table public.agenda_alocacoes enable trigger user;
  return v_n;
end $f$;
-- As mensagens à equipe de uma pessoa: "tipo dia estado/motivo [leva]".
create function pg_temp.equipe(p_payee uuid) returns text language sql stable as $f$
  select string_agg(format('%s %s %s%s', m.tipo, m.dia, m.estado || coalesce('/' || m.recusa_motivo, ''),
                           coalesce(' leva ' || m.leva_ficha_de, '')), ' | ' order by m.dia, m.criada_em, m.tipo)
    from public.agenda_equipe_mensagens m where m.payee_id = p_payee and m.modo = 'ligado'
$f$;
-- A ação ao dono da ficha segurada de uma pessoa: "texto [por]".
create function pg_temp.acao(p_payee uuid) returns text language sql stable as $f$
  select string_agg(a.texto || ' [' || coalesce(a.depois ->> 'por', '-') || ']', ' | ' order by a.criada_em)
    from public.agenda_acoes a where a.tipo = 'equipe' and a.origem = 'vigia' and a.payee_id = p_payee and a.depois ->> 'motivo' = 'ficha_segurada'
$f$;

-- ── B0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, auth, srv, vol, definer) as (values
  ('public._agenda_os_comecou(uuid, date)', true, true, 's', false),
  ('public._agenda_ficha_os_concluidas(uuid, date)', true, true, 's', false),
  ('public._agenda_ficha_os_concluidas_texto(uuid[])', true, true, 's', false),
  ('public._agenda_ficha_os_pagas(uuid, date)', true, true, 's', false),
  ('public._agenda_ficha_liberada(uuid, date, timestamptz)', true, true, 's', false),
  ('public._agenda_gestor_fichas(date, timestamptz)', false, false, 'v', false),
  ('public._agenda_rotina_ficha(date, timestamptz)', false, false, 'v', false),
  ('public._agenda_saude_comunicacao(date, timestamptz)', true, true, 's', true),
  ('public.agenda_resposta_da_equipe(text, text, text, timestamptz)', false, true, 'v', true),
  ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', false, false, 'v', true))
insert into _resultado
select 'B0a as portas: as 3 leituras novas invoker, STABLE, para authenticated e service_role; as 7 recriadas como eram (a saúde, a resposta da equipe e o decidir definer; a resposta só service_role); nunca anon; search_path fixo',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and not has_function_privilege('public', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = f.auth
                and has_function_privilege('service_role', f.assinatura, 'execute') = f.srv
                and p.prosecdef = f.definer and p.provolatile::text = f.vol
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> f.auth
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> f.srv
                                              or p.prosecdef <> f.definer or p.provolatile::text <> f.vol)
  from f join pg_proc p on p.oid = f.assinatura::regprocedure;

do $b0$
declare
  v_res jsonb := '[]'::jsonb;
  r     record;
  v     text;
  v_t   text := '';
  v_ok  boolean := true;
begin
  v_res := pg_temp.ok(v_res, 'B0b a OS que não existe (ou nula) não começou; a pessoa sem alocação não tem OS encerrada; sem OS encerrada, o texto do estado é nulo',
    not public._agenda_os_comecou(gen_random_uuid(), date '2026-11-05') and not public._agenda_os_comecou(null, date '2026-11-05')
    and public._agenda_ficha_os_concluidas(gen_random_uuid(), date '2026-11-05') = '{}'::uuid[]
    and public._agenda_ficha_os_concluidas_texto(array[gen_random_uuid()]) is null and public._agenda_ficha_os_concluidas_texto('{}'::uuid[]) is null, null);
  -- tirados os blocos B: a F2 (os md5 "depois" dela) e as de produção de 18/11; tirados também os da F2: as de antes da F2
  for r in select * from (values
      ('public._agenda_ficha_os_pagas(uuid, date)', '9b51d37226c72ec40dca7758460e6995', null, 1),
      ('public._agenda_ficha_liberada(uuid, date, timestamptz)', '46b2eaa697100267c9c66888738dc2fd', 'ec5ad2b9c7015dd67adf286846dbf285', 1),
      ('public._agenda_gestor_fichas(date, timestamptz)', '61b60204be07e8d91a93df3f3485731c', 'b652c8f60de5d8795391e89e3b814031', 3),
      ('public._agenda_rotina_ficha(date, timestamptz)', 'c0f0f48b02e4a7b80888d3112fa7cc40', '592d7ce112fa55352963cce9262406b5', 5),
      ('public._agenda_saude_comunicacao(date, timestamptz)', '00926f7360872e00e572b5dd5fce6a6c', null, 1),
      ('public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 'f572cd9e2068d952b3c862be24c9d46a', null, 2),
      ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'ed6693488bfa2c8a7c30583c2c5f0478', null, 2)) x(sig, f2, antes, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v from pg_proc p where p.oid = r.sig::regprocedure;
    v_ok := v_ok and md5(pg_temp.sem_b(v)) = r.f2 and (r.antes is null or md5(pg_temp.sem_b(v, true)) = r.antes)
            and (select count(*) from regexp_matches(v, '-- FICHA PAGA B: fim', 'g')) = r.blocos;
    v_t := v_t || format('%s: %s%s, %s blocos; ', split_part(r.sig, '(', 1), left(md5(pg_temp.sem_b(v)), 8),
                         case when r.antes is null then '' else '/' || left(md5(pg_temp.sem_b(v, true)), 8) end,
                         (select count(*) from regexp_matches(v, '-- FICHA PAGA B: fim', 'g')));
  end loop;
  v_res := pg_temp.ok(v_res, 'B0c a F2b só acrescenta: sem os blocos "-- FICHA PAGA B:" as 7 são as de produção (a F2; a saúde, a resposta da equipe e o decidir de 18/11), byte a byte; sem esses e os da F2, a liberada, as fichas e a ficha das 19:30 são as de antes da F2',
    v_ok, v_t);
  v_res := pg_temp.ok(v_res, 'B0d as 3 novas são as da migration (md5 do corpo) e só as 7 recriadas têm blocos "-- FICHA PAGA B:"',
    (select md5(replace(p.prosrc, E'\r\n', E'\n')) from pg_proc p where p.oid = 'public._agenda_os_comecou(uuid, date)'::regprocedure) = 'be56ca4d90c597912d1586c04ae6ee1c'
    and (select md5(replace(p.prosrc, E'\r\n', E'\n')) from pg_proc p where p.oid = 'public._agenda_ficha_os_concluidas(uuid, date)'::regprocedure) = '7f95cd1c57df9bed990fda7d430aefc3'
    and (select md5(replace(p.prosrc, E'\r\n', E'\n')) from pg_proc p where p.oid = 'public._agenda_ficha_os_concluidas_texto(uuid[])'::regprocedure) = 'b9ba37f0ab5e3f5cdcc69c2b12b34c8d'
    and (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%-- FICHA PAGA B:%')
        = '_agenda_ficha_liberada,_agenda_ficha_os_pagas,_agenda_gestor_decidir,_agenda_gestor_fichas,_agenda_rotina_ficha,_agenda_saude_comunicacao,agenda_resposta_da_equipe',
    (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%-- FICHA PAGA B:%'));
  -- os comentários: o de antes inteiro (o da F2; o de produção) e o "FICHA PAGA B" no fim
  v_t := '';
  v_ok := true;
  for r in select * from (values
      ('public._agenda_ficha_os_pagas(uuid, date)', 'f5f52cc199bda35fa40827118a15f22b'),
      ('public._agenda_ficha_liberada(uuid, date, timestamptz)', '777a166856bbc702a80769c14a4ab486'),
      ('public._agenda_gestor_fichas(date, timestamptz)', '7e8b518fa1323c08c8825537ff77688b'),
      ('public._agenda_rotina_ficha(date, timestamptz)', '79bae61929ea3f7987efe9c0bb313da7'),
      ('public._agenda_saude_comunicacao(date, timestamptz)', '99581f277e07b814f39c73233418ba79'),
      ('public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 'fbefa808f7ed57b9200e2fc5a0181fca'),
      ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'd2fcc43fed6ccf2e548899749834b915')) x(sig, antes)
  loop
    v := obj_description(r.sig::regprocedure, 'pg_proc');
    v_ok := v_ok and md5(split_part(v, ' FICHA PAGA B (18/11/2026, 20270126100000', 1)) = r.antes and v like '% FICHA PAGA B (18/11/2026, 20270126100000%';
    v_t := v_t || left(md5(split_part(v, ' FICHA PAGA B (18/11/2026, 20270126100000', 1)), 8) || ' ';
  end loop;
  v_res := pg_temp.ok(v_res, 'B0e os comentários das 7: o de antes inteiro (o da F2; o de produção) e o "FICHA PAGA B (18/11/2026, 20270126100000…" no fim', v_ok, v_t);
  perform pg_temp.gravar(v_res);
end
$b0$;

-- ── B1 a B5 e B7. Com o replay de 29/10 ───────────────────────────────────────────────────────────────────────
do $bx$
declare
  v_res   jsonb := '[]'::jsonb;
  c_s30   constant date := date '2026-10-30';
  c_t03   constant date := date '2026-11-03';
  c_q04   constant date := date '2026-11-04';
  c_q05   constant date := date '2026-11-05';
  c_s06   constant date := date '2026-11-06';
  -- a pergunta da ficha de ter 03/11 (o dia 1 do Lenine) com a OS paga, feita na sex 30/10
  c_paga  constant text := 'Hoje às 19:30 a ficha de terça vai para João: OS-00074 Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. A OS-00074 já está PAGA e ainda não começou: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).';
  -- a pergunta de qui 05/11 (o dia 3), a de antes (a OS paga que já começou não muda nada)
  c_nao   constant text := 'Hoje às 19:30 a ficha de amanhã vai para Roberto: OS-00074 Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
  c_conc  constant text := 'Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está concluída. Fale com Roberto. [concluida]';
  v_len   uuid;
  v_van   uuid;
  v_rob   uuid;
  v_joao  uuid;
  v_dono  uuid;
  v_adm   uuid;
  v_q     uuid;
  r       jsonb;
  r2      jsonb;
  v_t     text;
  v_t2    text;
  v_n     int;
  v_ok    boolean;
  v_dono_nome text;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('B1 a B5 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    v_dono := public._agenda_dono(null);
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;

    -- ── B1. O começou: só PROVA DE TRABALHO do técnico antes do dia (revisões do coordenador e respostas do dono P1 e P4, 18/11) ──
    v_res := pg_temp.ok(v_res, 'B1a o dia só PLANEJADO nunca conta (o caso OS-00129): o Lenine tem dias vigentes em 03 e 04/11 sem resultado e não começou em 03, 04, 05 nem 11/11; o Vanderlei, em 13/11',
      not public._agenda_os_comecou(v_len, c_t03) and not public._agenda_os_comecou(v_len, c_q04) and not public._agenda_os_comecou(v_len, c_q05)
      and not public._agenda_os_comecou(v_len, date '2026-11-11') and not public._agenda_os_comecou(v_van, date '2026-11-13'),
      format('%s %s %s %s %s', public._agenda_os_comecou(v_len, c_t03), public._agenda_os_comecou(v_len, c_q04), public._agenda_os_comecou(v_len, c_q05),
             public._agenda_os_comecou(v_len, date '2026-11-11'), public._agenda_os_comecou(v_van, date '2026-11-13')));
    begin
      v_t := '';
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''nao_cumprido'', motivo = ''clima'', resultado_via = ''equipe'', resultado_em = now()');
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''sem_registro'', motivo = null, resultado_via = ''sistema''');
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''cumprido'', resultado_via = ''equipe''');
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',' || public._agenda_os_comecou(v_len, c_t03) || ',';
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''parcial'', motivo = ''clima'', resultado_via = ''conversa''');
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04);
      v_res := pg_temp.ok(v_res, 'B1b o dia de antes: "não cumprido" e o "sem registro" da vigia não contam; "cumprido" (o "como foi") e "parcial" (o dono) contam; o próprio dia não',
        v_t = 'false,false,true,false,true', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- (P1, P4) o check-in e o "em andamento" sozinhos NÃO provam: a porta os grava ao abrir e ao REABRIR a OS
      perform pg_temp.status(v_len, 'scheduled', pg_temp.em(date '2026-11-02', '08:00'));
      v_t := public._agenda_os_comecou(v_len, c_t03) || ',' || public._agenda_os_comecou(v_len, c_q04);
      perform pg_temp.status(v_len, 'in_progress');
      v_t := v_t || ',' || public._agenda_os_comecou(v_len, c_q04);
      -- a reabertura: a OS concluída volta a em andamento com o check-in gravado (como a OS-00104 e a OS-00134 em 16/11)
      perform pg_temp.status(v_len, 'completed');
      perform pg_temp.status(v_len, 'in_progress', pg_temp.em(date '2026-11-02', '11:22'));
      v_t := v_t || ',' || public._agenda_os_comecou(v_len, c_q04);
      -- o check-in com o "como foi" do dia 1 respondido OK: aí sim
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''cumprido'', resultado_via = ''equipe'', resultado_em = now()', v_joao);
      v_t := v_t || ',' || public._agenda_os_comecou(v_len, c_q04);
      v_res := pg_temp.ok(v_res, 'B1c (P1, P4) o check-in sozinho não conta, nem o "em andamento", nem a reabertura com check-in; o check-in com o "como foi" OK do dia 1, sim',
        v_t = 'false,false,false,false,true', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- a confirmação da manhã de ter 03/11 do João (que estava na OS-00074 o dia todo), respondida
      v_t := '';
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em, resposta_texto, resposta_em, leitura)
      values (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste da ficha paga B', pg_temp.em(c_t03, '07:45'), 'respondida',
              'teste-f2b:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'), 'ok', pg_temp.em(c_t03, '07:50'), '{"tipo": "ok"}');
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',' || public._agenda_os_comecou(v_len, c_t03) || ',' || public._agenda_os_comecou(v_van, date '2026-11-13') || ',';
      update public.agenda_equipe_mensagens set leitura = '{"tipo": "turnos", "turnos": ["tarde", "manha"], "ok": true}' where dedupe_key like 'teste-f2b:confirmar:%';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      -- (C3 da revisão) "ok, só de manhã" com o dia todo no plano: o tratador vê divergência e manda ao dono — não confirma
      update public.agenda_equipe_mensagens set leitura = '{"tipo": "turnos", "turnos": ["manha"], "ok": true}' where dedupe_key like 'teste-f2b:confirmar:%';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      -- "meio" com os dois turnos no plano também diverge
      update public.agenda_equipe_mensagens set leitura = '{"tipo": "turnos", "turnos": ["meio"], "ok": true}' where dedupe_key like 'teste-f2b:confirmar:%';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      update public.agenda_equipe_mensagens set leitura = '{"tipo": "turnos", "turnos": ["manha", "tarde"]}' where dedupe_key like 'teste-f2b:confirmar:%';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      update public.agenda_equipe_mensagens set leitura = '{"tipo": "nao_entendi"}' where dedupe_key like 'teste-f2b:confirmar:%';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      update public.agenda_equipe_mensagens set leitura = '{"tipo": "ok"}', estado = 'sem_resposta', resposta_texto = null, resposta_em = null
       where dedupe_key like 'teste-f2b:confirmar:%';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04);
      alter table public.agenda_equipe_mensagens enable trigger user;
      v_res := pg_temp.ok(v_res, 'B1d a confirmação da manhã de um dia antes, respondida "sim" sem divergência (ok; os turnos do plano com ok) por quem estava na OS, conta; o próprio dia, outra OS, turnos diferentes do plano ("ok, só de manhã"; "meio" com os dois turnos), turnos sem ok, "não entendi" e sem resposta, não',
        v_t = 'true,false,false,true,false,false,false,false,false', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o turno que ele confirmou: o João em ter 03/11 com a OS-00074 de manhã e a OS-00069 à tarde
      v_t := '';
      perform pg_temp.aloc(v_len, c_t03, format('service_order_id = %L', v_van), v_joao, 'tarde');
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em, resposta_texto, resposta_em, leitura)
      values (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste da ficha paga B', pg_temp.em(c_t03, '07:45'), 'respondida',
              'teste-f2b:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'), 'ok, de tarde', pg_temp.em(c_t03, '07:50'),
              '{"tipo": "ok", "turnos": ["tarde"]}');
      -- "ok" com só a tarde dita: a OS da tarde (OS-00069) conta, a da manhã (OS-00074), não
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',' || public._agenda_os_comecou(v_van, c_q04) || ',';
      -- com um turno só no plano (a tarde dele cancelada), "meio" é esse turno
      perform pg_temp.aloc(v_van, c_t03, 'estado = ''cancelada'', cancelada_em = now(), cancelada_motivo = ''replanejado''', v_joao);
      update public.agenda_equipe_mensagens set leitura = '{"tipo": "turnos", "turnos": ["meio"], "ok": true}' where dedupe_key like 'teste-f2b:confirmar:%';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',' || public._agenda_os_comecou(v_van, c_q04);
      alter table public.agenda_equipe_mensagens enable trigger user;
      v_res := pg_temp.ok(v_res, 'B1d2 a confirmação conta só para a OS de um turno que ele confirmou ("ok, de tarde": a OS da tarde sim, a da manhã não); "meio" com um turno só no plano é esse turno',
        v_t = 'false,true,true,false', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- a diária do João de ter 03/11 na OS-00074
      v_t := '';
      alter table public.work_shifts disable trigger user;
      alter table public.work_shift_os disable trigger user;
      insert into public.work_shifts (id, work_profile_id, data, tipo, origem, status, aprovado_por, aprovado_em, fracao, valor_diaria, service_order_id)
      values ('f2b00000-0000-4000-8000-000000000001', gen_random_uuid(), c_t03, 'diaria', 'painel', 'aprovado', v_adm, now(), 1, 200, v_len);
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',' || public._agenda_os_comecou(v_len, c_t03) || ',';
      update public.work_shifts set status = 'rascunho', aprovado_por = null, aprovado_em = null where id = 'f2b00000-0000-4000-8000-000000000001';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      update public.work_shifts set status = 'aprovado', aprovado_por = v_adm, aprovado_em = now(), tipo = 'falta', fracao = 0 where id = 'f2b00000-0000-4000-8000-000000000001';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      update public.work_shifts set tipo = 'diaria', fracao = 0.5, service_order_id = null where id = 'f2b00000-0000-4000-8000-000000000001';
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      insert into public.work_shift_os (shift_id, service_order_id) values ('f2b00000-0000-4000-8000-000000000001', v_len);
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04);
      alter table public.work_shifts enable trigger user;
      alter table public.work_shift_os enable trigger user;
      v_res := pg_temp.ok(v_res, 'B1e a diária lançada (aprovada) num dia antes, na OS (pela OS da diária ou por work_shift_os), conta; o próprio dia, a em rascunho, a falta e a diária sem OS (sem service_order_id e sem work_shift_os), não',
        v_t = 'true,false,false,false,false,true', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      v_t := '';
      alter table public.time_entries disable trigger user;
      insert into public.time_entries (service_order_id, technician_user_id, started_at) values (v_len, v_adm, pg_temp.em(c_t03, '09:00'));
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',' || public._agenda_os_comecou(v_len, c_t03) || ',';
      delete from public.time_entries where service_order_id = v_len;
      alter table public.time_entries enable trigger user;
      alter table public.service_order_steps disable trigger user;
      insert into public.service_order_steps (service_order_id, seq, title, status, started_at) values (v_len, 990, 'Passo de teste da ficha paga B', 'in_progress', pg_temp.em(c_t03, '10:00'));
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04) || ',';
      update public.service_order_steps set started_at = null, status = 'pending' where service_order_id = v_len and seq = 990;
      v_t := v_t || public._agenda_os_comecou(v_len, c_q04);
      alter table public.service_order_steps enable trigger user;
      v_res := pg_temp.ok(v_res, 'B1f horas apontadas ou um passo da execução iniciado num dia antes contam; no próprio dia, ou o passo não iniciado, não',
        v_t = 'true,false,true,false', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── B2. A OS paga que ainda não começou fica segurada ──
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      v_q := (select (x ->> 'pergunta_id')::uuid from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João');
      select format('%s|%s|%s', q.opcao_padrao, q.recomendacao, q.texto) into v_t from public.agenda_perguntas q where q.id = v_q;
      v_res := pg_temp.ok(v_res, 'B2a a OS paga que ainda não começou (o dia 1): "… A OS-00074 já está PAGA e ainda não começou: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure … (recomendo)." — padrão e recomendação 2',
        public._agenda_ficha_os_pagas(v_joao, c_t03) = array[v_len] and v_t = '2|2|' || c_paga, coalesce(v_t, '-') || ' | ' || r::text);
      v_ok := public._agenda_ficha_liberada(v_joao, c_t03, pg_temp.em(c_s30, '19:31'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:32'));
      v_res := pg_temp.ok(v_res, 'B2b às 19:30 a ficha de ter 03/11 fica (recusada, veto); o porquê ao dono, "… (OS-00074 Lenine): a OS já está paga por inteiro e você não viu a pergunta. …" (paga_nao_vista); a pergunta fecha com o motivo dela',
        not v_ok and pg_temp.equipe(v_joao) = 'ficha 2026-11-03 recusada/veto'
        and pg_temp.acao(v_joao) = 'Não mandei a ficha de ter 03/11 a João (OS-00074 Lenine): a OS já está paga por inteiro e você não viu a pergunta. Fale com João. [paga_nao_vista]'
        and (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q)
            = 'resolvida:a OS estava paga por inteiro e você não viu a pergunta: a ficha não saiu',
        coalesce(pg_temp.equipe(v_joao), '-') || ' | ' || coalesce(pg_temp.acao(v_joao), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- (revisão do coordenador) o dia 1 (ter 03/11) só planejado — passou "sem registro" pela vigia, ninguém confirmou nem disse como
      -- foi: a ficha do dia 2 (qua 04/11) continua segurada, e a do dia 3 também
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''sem_registro'', resultado_via = ''sistema'', resultado_em = now()');
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_t03, pg_temp.em(c_t03, '16:52'));
      v_q := (select (x ->> 'pergunta_id')::uuid from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João');
      select format('%s|%s', q.opcao_padrao, q.texto) into v_t from public.agenda_perguntas q where q.id = v_q;
      v_ok := public._agenda_ficha_liberada(v_joao, c_q04, pg_temp.em(c_t03, '19:31')) or public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q04, '19:31'));
      perform public._agenda_rotina_ficha(c_t03, pg_temp.em(c_t03, '19:32'));
      v_res := pg_temp.ok(v_res, 'B2c OS paga com o dia 1 só planejado (sem registro, sem confirmação, sem "como foi"): o dia 2 continua segurado — a pergunta é a da paga não começada, às 19:30 a ficha de qua 04/11 fica e o dono é avisado; o dia 3 também não solta',
        not public._agenda_os_comecou(v_len, c_q04) and public._agenda_ficha_os_pagas(v_joao, c_q04) = array[v_len]
        and v_t like '2|Hoje às 19:30 a ficha de amanhã vai para João: OS-00074 Lenine, qua 04/11 o dia todo — dia 2 de 6, pela minha estimativa. A OS-00074 já está PAGA e ainda não começou: o serviço ainda vai ser feito?%'
        and not v_ok and pg_temp.equipe(v_joao) = 'ficha 2026-11-04 recusada/veto'
        and pg_temp.acao(v_joao) = 'Não mandei a ficha de qua 04/11 a João (OS-00074 Lenine): a OS já está paga por inteiro e você não viu a pergunta. Fale com João. [paga_nao_vista]',
        coalesce(v_t, '-') || ' | ' || coalesce(pg_temp.equipe(v_joao), '-') || ' | ' || coalesce(pg_temp.acao(v_joao), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    begin
      -- (P1) a OS paga com check-in e "em andamento", sem prova de trabalho: segura a ficha do dia 1 e a do dia 2
      perform pg_temp.pagar(v_len);
      perform pg_temp.status(v_len, 'in_progress', pg_temp.em(date '2026-11-02', '08:00'));
      v_ok := public._agenda_ficha_liberada(v_joao, c_t03, pg_temp.em(c_s30, '19:31')) or public._agenda_ficha_liberada(v_joao, c_q04, pg_temp.em(c_t03, '19:31'));
      v_res := pg_temp.ok(v_res, 'B2d (P1) a OS paga só com o check-in e "em andamento" (sem prova de trabalho) segura a ficha do dia 1 e a do dia 2',
        public._agenda_os_paga_por_inteiro(v_len) and public._agenda_ficha_os_pagas(v_joao, c_t03) = array[v_len]
        and public._agenda_ficha_os_pagas(v_joao, c_q04) = array[v_len] and not v_ok,
        format('pagas03=%s pagas04=%s liberada=%s', public._agenda_ficha_os_pagas(v_joao, c_t03), public._agenda_ficha_os_pagas(v_joao, c_q04), v_ok));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- (P4) a reabertura: a OS concluída e reaberta (em andamento, check-in da reabertura), paga: segura
      perform pg_temp.status(v_len, 'completed');
      perform pg_temp.pagar(v_len);
      perform pg_temp.status(v_len, 'in_progress', pg_temp.em(date '2026-11-02', '11:22'));
      r := public._agenda_gestor_fichas(c_t03, pg_temp.em(c_t03, '16:52'));
      v_q := (select (x ->> 'pergunta_id')::uuid from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João');
      v_t := (select q.opcao_padrao || '|' || q.texto from public.agenda_perguntas q where q.id = v_q);
      perform public._agenda_rotina_ficha(c_t03, pg_temp.em(c_t03, '19:32'));
      v_res := pg_temp.ok(v_res, 'B2e (P4) a OS reaberta com check-in e paga: a pergunta é a da paga não começada e às 19:30 a ficha do dia 2 fica',
        v_t like '2|%A OS-00074 já está PAGA e ainda não começou%' and pg_temp.equipe(v_joao) = 'ficha 2026-11-04 recusada/veto',
        coalesce(v_t, '-') || ' | ' || coalesce(pg_temp.equipe(v_joao), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── B3. A OS paga que já começou (o João fez o dia 1 e o 2: o "como foi" respondido): a regra de antes ──
    begin
      perform pg_temp.status(v_len, 'scheduled', pg_temp.em(date '2026-11-02', '08:00'));  -- e o check-in: com o "como foi", começou
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''cumprido'', resultado_via = ''equipe'', resultado_em = now()', v_joao);
      perform pg_temp.aloc(v_len, c_q04, 'resultado = ''cumprido'', resultado_via = ''equipe'', resultado_em = now()', v_joao);
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      select format('%s|%s|%s', q.opcao_padrao, q.recomendacao, q.texto) into v_t from public.agenda_perguntas q where q.id = v_q;
      perform public.agenda_fechamento_registrar(c_q04,
        (select jsonb_agg(x) from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_q04)) x where x ->> 'pergunta_id' = v_q::text),
        'fechamento', pg_temp.em(c_q04, '17:30'));
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B3a dentro da janela, a OS paga que já começou (qui 05/11, o dia 3; o dia 1 e o 2 feitos): a pergunta de sempre (padrão 1, sem o PAGA) e, mostrada, a ficha sai sem *mande*',
        public._agenda_os_paga_por_inteiro(v_len) and public._agenda_ficha_os_pagas(v_rob, c_q05) = '{}'::uuid[]
        and v_t = '1|1|' || c_nao and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada' and pg_temp.acao(v_rob) is null,
        coalesce(v_t, '-') || ' | ' || coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''cumprido'', resultado_via = ''equipe'', resultado_em = now()', v_joao);
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_t := r ->> 'motivo';
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      update public.agenda_config set marcar_sozinho_desde = null where id;
      r2 := public._agenda_gestor_fichas(c_q05, pg_temp.em(c_q05, '16:52'));
      perform public._agenda_rotina_ficha(c_q05, pg_temp.em(c_q05, '19:30'));
      v_res := pg_temp.ok(v_res, 'B3b fora da janela (o ligar de 01/10) e sem o ligar do gestor, a OS paga que já começou (o dia 1 feito): nenhuma pergunta e a ficha sai (qui 05 e sex 06/11)',
        v_t = 'fora da janela da ficha' and (r2 ->> 'pulado')::boolean
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada | ficha 2026-11-06 enfileirada'
        and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'ficha_estimativa'),
        coalesce(v_t, '-') || ' | ' || r2::text || ' | ' || coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── B4. A OS concluída ou faturada nunca manda a ficha ──
    begin
      perform pg_temp.status(v_len, 'completed');
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_ok := not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q04, '19:30'))
              and not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q05, '07:45'))
              and public._agenda_ficha_os_concluidas(v_rob, c_q05) = array[v_len];
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      perform public._agenda_rotina_confirmar(c_q05, pg_temp.em(c_q05, '07:45'));
      v_res := pg_temp.ok(v_res, 'B4a concluída, dentro da janela: nenhuma pergunta; a ficha de qui 05/11 e a confirmação da manhã ficam (recusada, veto); o porquê ao dono: "Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está concluída. Fale com Roberto." (por concluida)',
        v_ok and (r ->> 'perguntas')::int = 0
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto | confirmar 2026-11-05 recusada/veto' and pg_temp.acao(v_rob) = c_conc,
        r::text || ' | ' || coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- a pergunta nasceu antes da baixa e o dono disse *mande*; depois a OS foi concluída
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_q04, pg_temp.em(c_q04, '17:40'));
      perform pg_temp.status(v_len, 'completed');
      v_ok := not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q04, '19:30'));
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B4b nem com o *mande* do dono: a OS concluída depois da resposta, a ficha fica e o porquê é o da concluída',
        v_ok and r2 ->> 'texto' = 'Combinado: mando a ficha de qui 05/11 para Roberto.'
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto' and pg_temp.acao(v_rob) = c_conc,
        coalesce(r2 ->> 'texto', '-') || ' | ' || coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- faturada, sem o ligar do gestor, e o dia que não é pela estimativa (a régua de antes soltaria nos dois)
      perform pg_temp.status(v_len, 'invoiced');
      update public.agenda_config set marcar_sozinho_desde = null where id;
      perform pg_temp.aloc(v_len, c_q05, 'duracao_fonte = ''dono''', v_rob);
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B4c faturada, sem o ligar do gestor e com o dia que não é pela estimativa: a ficha fica e o porquê é "a OS já está faturada"',
        (r ->> 'pulado')::boolean and not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q04, '19:30'))
        and public._agenda_ficha_os_pagas(v_rob, c_q05) = '{}'::uuid[]
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto'
        and pg_temp.acao(v_rob) = 'Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está faturada. Fale com Roberto. [concluida]',
        coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- a pergunta aberta (nasceu antes de concluir) fecha com o motivo dela
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      perform pg_temp.status(v_len, 'completed');
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B4d a pergunta aberta de quem tem OS concluída fecha às 19:30 com o motivo dela ("a OS já estava concluída, faturada ou cancelada: a ficha não saiu")',
        (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q)
          = 'resolvida:a OS já estava concluída, faturada ou cancelada: a ficha não saiu' and pg_temp.acao(v_rob) = c_conc,
        (select q.estado || ':' || coalesce(q.resolvida_motivo, '-') from public.agenda_perguntas q where q.id = v_q) || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o "como foi" de qui 05/11 (o Roberto na OS-00069 nesse dia) não leva a ficha de sex 06/11 da OS-00074 concluída; sem a
      -- conclusão, levava. Fora da janela (sem o ligar), para a regra de antes não segurar nada.
      update public.agenda_config set marcar_sozinho_desde = null where id;
      perform pg_temp.aloc(v_len, c_q05, format('service_order_id = %L', v_van), v_rob);
      begin
        perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
        perform public._agenda_rotina_confirmar(c_q05, pg_temp.em(c_q05, '07:45'));
        perform public._agenda_rotina_como_foi(c_q05, pg_temp.em(c_q05, '17:05'));
        v_t := pg_temp.equipe(v_rob);
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      perform pg_temp.status(v_len, 'completed');
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      perform public._agenda_rotina_confirmar(c_q05, pg_temp.em(c_q05, '07:45'));
      perform public._agenda_rotina_como_foi(c_q05, pg_temp.em(c_q05, '17:05'));
      v_t2 := pg_temp.equipe(v_rob);
      perform public._agenda_rotina_ficha(c_q05, pg_temp.em(c_q05, '19:30'));
      v_res := pg_temp.ok(v_res, 'B4e o "como foi" não leva a ficha do dia da OS concluída (sem a conclusão, levava); às 19:30 ela fica (recusada, veto) com o porquê da concluída',
        v_t like '%como_foi 2026-11-05 enfileirada leva 2026-11-06%'
        and v_t2 like '%como_foi 2026-11-05 enfileirada' and v_t2 not like '%leva%'
        and pg_temp.equipe(v_rob) like '%ficha 2026-11-06 recusada/veto%'
        and pg_temp.acao(v_rob) = 'Não mandei a ficha de sex 06/11 a Roberto (OS-00074 Lenine): a OS já está concluída. Fale com Roberto. [concluida]',
        coalesce(v_t, '-') || ' || ' || coalesce(v_t2, '-') || ' || ' || coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.status(v_len, 'completed');
      v_res := pg_temp.ok(v_res, 'B4f o dono, com a OS concluída no dia (ter 10/11 no Lenine), sempre tem a ficha',
        cardinality(public._agenda_ficha_os_concluidas(v_dono, date '2026-11-10')) > 0
        and public._agenda_ficha_liberada(v_dono, date '2026-11-10', pg_temp.em(date '2026-11-09', '19:30')),
        public._agenda_ficha_os_concluidas(v_dono, date '2026-11-10')::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    begin
      -- (P3) a OS cancelada entra no "nunca"
      perform pg_temp.status(v_len, 'cancelled');
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_ok := public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q04, '19:30'));
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B4g (P3) cancelada: sem pergunta, a ficha fica (recusada, veto) e o porquê é "a OS já está cancelada"',
        not v_ok and (r ->> 'perguntas')::int = 0 and public._agenda_ficha_os_concluidas(v_rob, c_q05) = array[v_len]
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto'
        and pg_temp.acao(v_rob) = 'Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está cancelada. Fale com Roberto. [concluida]',
        r::text || ' | ' || coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- (correção da revisão) a pergunta nasceu, a OS foi concluída, e DEPOIS o dono disse *mande*: a resposta diz que a ficha não sai
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      perform pg_temp.status(v_len, 'completed');
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_q04, pg_temp.em(c_q04, '17:40'));
      v_t := (select q.estado || ':' || coalesce(q.opcao_escolhida::text, '-') from public.agenda_perguntas q where q.id = v_q);
      v_ok := public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q04, '19:30'));
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B4h o *mande* depois da conclusão responde "A OS-00074 já está concluída: a ficha não sai." (a resposta fica gravada; a ficha fica, com o porquê da concluída)',
        r2 ->> 'texto' = 'A OS-00074 já está concluída: a ficha não sai.' and v_t = 'respondida:1' and not v_ok
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto' and pg_temp.acao(v_rob) = c_conc,
        coalesce(r2 ->> 'texto', '-') || ' | ' || coalesce(v_t, '-') || ' | ' || coalesce(pg_temp.equipe(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o *segure* depois da conclusão e o *mande* com a OS em aberto: o de antes
      r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      perform pg_temp.status(v_len, 'invoiced');
      r2 := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', 'segure', c_q04, pg_temp.em(c_q04, '17:40'));
      -- o texto do estado (cada leitura no seu comando: o auxiliar é STABLE)
      v_t := public._agenda_ficha_os_concluidas_texto(array[v_len]);
      perform pg_temp.status(v_van, 'cancelled');
      v_t := v_t || '|' || public._agenda_ficha_os_concluidas_texto(array[v_len, v_van]);
      perform pg_temp.status(v_len, 'completed');
      v_t := v_t || '|' || public._agenda_ficha_os_concluidas_texto(array[v_len, v_van]) || '|' || public._agenda_ficha_os_concluidas_texto(array[v_van]);
      v_res := pg_temp.ok(v_res, 'B4i o *segure* da OS encerrada é o de antes ("Combinado: não mando …"); o texto do estado: faturada; faturadas ou canceladas; concluídas ou canceladas; cancelada',
        r2 ->> 'texto' = 'Combinado: não mando a ficha de qui 05/11 para Roberto, nem a confirmação da manhã. Fale com Roberto.'
        and v_t = 'faturada|faturadas ou canceladas|concluídas ou canceladas|cancelada',
        coalesce(r2 ->> 'texto', '-') || ' | ' || coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── B5. O dia misto ──
    begin
      -- o Roberto em qui 05: a OS-00074 (concluída) de manhã e a OS-00069 (não) à tarde
      perform pg_temp.aloc(v_len, c_q05, format('service_order_id = %L', v_van), v_rob, 'tarde');
      perform pg_temp.status(v_len, 'completed');
      perform public._agenda_rotina_ficha(c_q04, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B5a dia misto com a concluída: o parêntese cita as 2 OS do dia e o porquê nomeia a concluída ("… (OS-00074 Lenine e OS-00069 Vanderlei): a OS-00074 já está concluída. …")',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto'
        and pg_temp.acao(v_rob) = 'Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine e OS-00069 Vanderlei): a OS-00074 já está concluída. Fale com Roberto. [concluida]',
        coalesce(pg_temp.equipe(v_rob), '-') || ' | ' || coalesce(pg_temp.acao(v_rob), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o João em ter 03: a OS-00074 (paga, não começou) de manhã e a OS-00069 (não paga) à tarde
      perform pg_temp.aloc(v_len, c_t03, format('service_order_id = %L', v_van), v_joao, 'tarde');
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      v_q := (select (x ->> 'pergunta_id')::uuid from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João');
      v_t := (select q.texto from public.agenda_perguntas q where q.id = v_q);
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:32'));
      v_res := pg_temp.ok(v_res, 'B5b dia misto com a paga: a pergunta nomeia a paga ("A OS-00074 já está PAGA e ainda não começou"); o parêntese do porquê cita as 2 OS e o porquê nomeia a paga ("a OS-00074 já está paga por inteiro e …")',
        v_t like '%OS-00074 Lenine, ter 03/11 de manhã%OS-00069 Vanderlei, ter 03/11 à tarde%. A OS-00074 já está PAGA e ainda não começou: o serviço ainda vai ser feito?%'
        and pg_temp.equipe(v_joao) = 'ficha 2026-11-03 recusada/veto'
        and pg_temp.acao(v_joao) = 'Não mandei a ficha de ter 03/11 a João (OS-00074 Lenine e OS-00069 Vanderlei): a OS-00074 já está paga por inteiro e você não viu a pergunta. Fale com João. [paga_nao_vista]',
        coalesce(v_t, '-') || ' | ' || coalesce(pg_temp.acao(v_joao), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- as 2 pagas (nenhuma começou em ter 03): a pergunta no plural; o porquê é o da F2 ("as OS já estão pagas por inteiro")
      perform pg_temp.aloc(v_len, c_t03, format('service_order_id = %L', v_van), v_joao, 'tarde');
      perform pg_temp.pagar(v_len);
      perform pg_temp.pagar(v_van);
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      v_q := (select (x ->> 'pergunta_id')::uuid from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João');
      v_t := (select q.texto from public.agenda_perguntas q where q.id = v_q);
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:32'));
      v_res := pg_temp.ok(v_res, 'B5c duas OS pagas no dia: "As OS-00074 e OS-00069 já estão PAGAS e ainda não começaram: os serviços ainda vão ser feitos?"; o porquê, "as OS já estão pagas por inteiro"',
        v_t like '%. As OS-00074 e OS-00069 já estão PAGAS e ainda não começaram: os serviços ainda vão ser feitos? Sem resposta até 19:30, eu seguro a ficha.%'
        and pg_temp.acao(v_joao) = 'Não mandei a ficha de ter 03/11 a João (OS-00074 Lenine e OS-00069 Vanderlei): as OS já estão pagas por inteiro e você não viu a pergunta. Fale com João. [paga_nao_vista]',
        coalesce(v_t, '-') || ' | ' || coalesce(pg_temp.acao(v_joao), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- a concluída vence a paga: o João em ter 03 com a OS-00074 paga de manhã e a OS-00069 concluída à tarde
      perform pg_temp.aloc(v_len, c_t03, format('service_order_id = %L', v_van), v_joao, 'tarde');
      perform pg_temp.pagar(v_len);
      perform pg_temp.status(v_van, 'completed');
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:32'));
      v_res := pg_temp.ok(v_res, 'B5d a concluída vence a paga: sem pergunta ao João; o porquê é o da concluída, com as 2 OS no parêntese',
        not exists (select 1 from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João')
        and pg_temp.equipe(v_joao) = 'ficha 2026-11-03 recusada/veto'
        and pg_temp.acao(v_joao) = 'Não mandei a ficha de ter 03/11 a João (OS-00074 Lenine e OS-00069 Vanderlei): a OS-00069 já está concluída. Fale com João. [concluida]',
        r::text || ' | ' || coalesce(pg_temp.acao(v_joao), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── B7. (P2) "o que tem pra amanhã?" com a ficha segurada ──
    v_dono_nome := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_dono);
    begin
      -- o João pergunta na seg 02/11 às 10:00 o que tem amanhã (ter 03/11, o dia 1 da OS-00074, paga e sem o *mande*)
      perform pg_temp.pagar(v_len);
      r := public.agenda_resposta_da_equipe('5547900000004', 'o que tem pra amanhã?', 'wa-f2b-b7a', pg_temp.em(date '2026-11-02', '10:00'));
      v_t := (select string_agg(m.texto, ' | ') from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'resposta' and m.dia = c_t03);
      v_t2 := (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:%s:pergunta', v_joao, c_t03));
      v_res := pg_temp.ok(v_res, 'B7a (P2) a ficha segurada por OS paga sem *mande*: a resposta é "Vou ver com <dono> e te falo." (não o plano) e o dono recebe a pergunta: "O João perguntou o que tem amanhã (ter 03/11), e a ficha dele está segurada: a OS-00074 já está paga e você não disse *mande*. …"',
        r ->> 'tipo' = 'pergunta' and coalesce((r ->> 'ficha_segurada')::boolean, false)
        and v_t = format('Vou ver com %s e te falo.', v_dono_nome)
        and v_t2 like 'O João perguntou o que tem amanhã (ter 03/11), e a ficha dele está segurada: a OS-00074 já está paga e você não disse *mande*. Diga a ele o que fazer.%',
        r::text || ' | ' || coalesce(v_t, '-') || ' | ' || coalesce(v_t2, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o Roberto pergunta na qua 04/11 às 10:00 o que tem amanhã (qui 05/11), com a OS-00074 concluída
      perform pg_temp.status(v_len, 'completed');
      r := public.agenda_resposta_da_equipe('5547900000002', 'o que tem pra amanhã?', 'wa-f2b-b7b', pg_temp.em(c_q04, '10:00'));
      v_t := (select string_agg(m.texto, ' | ') from public.agenda_equipe_mensagens m where m.payee_id = v_rob and m.tipo = 'resposta' and m.dia = c_q05);
      v_t2 := (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:%s:pergunta', v_rob, c_q05));
      v_res := pg_temp.ok(v_res, 'B7b (P2) a ficha segurada por OS concluída: "Vou ver com <dono> e te falo." e a pergunta ao dono diz "a OS-00074 já está concluída"',
        coalesce((r ->> 'ficha_segurada')::boolean, false) and v_t = format('Vou ver com %s e te falo.', v_dono_nome)
        and v_t2 like 'O Roberto perguntou o que tem amanhã (qui 05/11), e a ficha dele está segurada: a OS-00074 já está concluída. Diga a ele o que fazer.%',
        r::text || ' | ' || coalesce(v_t, '-') || ' | ' || coalesce(v_t2, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- sem a ficha segurada (sem o ligar do gestor e sem OS paga nem encerrada): o plano, como antes, e nenhuma pergunta ao dono
      update public.agenda_config set marcar_sozinho_desde = null where id;
      v_t2 := public.agenda_equipe_ficha(v_joao, c_t03, date '2026-11-02') ->> 'texto_resposta';
      r := public.agenda_resposta_da_equipe('5547900000004', 'o que tem pra amanhã?', 'wa-f2b-b7c', pg_temp.em(date '2026-11-02', '10:00'));
      v_t := (select string_agg(m.texto, ' | ') from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'resposta' and m.dia = c_t03);
      v_res := pg_temp.ok(v_res, 'B7c (P2) com a ficha liberada a resposta é o plano, como antes (agenda_equipe_ficha.texto_resposta), sem "Vou ver" e sem pergunta ao dono',
        r ->> 'tipo' = 'pergunta' and not coalesce((r ->> 'ficha_segurada')::boolean, false)
        and v_t = v_t2 and v_t not like 'Vou ver%' and length(v_t) > 20
        and not exists (select 1 from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:%s:pergunta', v_joao, c_t03)),
        r::text || ' | ' || coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then
    v_res := pg_temp.ok(v_res, 'B1-B5 sem erro', false, sqlstate || ': ' || sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$bx$;

-- ── B6. A saúde (C4 da revisão da F2) ───────────────────────────────────────────────────────────────────
-- A bancada não tem resumo_tarde (é do Secretário): ela nasce aqui só com as colunas que a saúde lê, como em agenda_prazo_no_bloco.sql, e
-- some no rollback. A saúde de produção de 18/11 roda como pg_temp (a viva sem o bloco B).
do $b6$
declare
  v_res    jsonb := '[]'::jsonb;
  c_h      constant date := date '2026-11-04';
  c_a      constant timestamptz := timestamptz '2026-11-04 18:00-03';
  c_paga   constant text := 'Agenda: Hoje às 19:30 a ficha de amanhã vai para Roberto: OS-00074 Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. A OS-00074 já está PAGA e ainda não começou: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).';
  c_nao    constant text := 'Agenda: Hoje às 19:30 a ficha de amanhã vai para Roberto: OS-00074 Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
  c_cli    constant text := 'Mensagem para Vera (véspera), sai qui 05/11 às 09:00: "Amanhã estamos aí às 8h. Está confirmado? Responda SIM.". *manda cliente Vera* ou *segura cliente Vera*.';
  v_x      text := '';
  r        record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('B6 (a saúde)', true, 'PULADO: rode pela bancada');
    return;
  end if;
  execute format('create function pg_temp.saude_sem_b(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable set search_path to ''public'' as %L',
                 pg_temp.sem_b((select p.prosrc from pg_proc p where p.oid = 'public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure)));
  if to_regclass('public.resumo_tarde') is null then
    create table public.resumo_tarde (id uuid primary key default gen_random_uuid(), dia date not null, phone_normalized text not null, turno text not null,
                                      modo text not null, formato text not null, texto text, detalhe jsonb not null default '{}'::jsonb,
                                      criado_em timestamptz not null default now());
  end if;
  -- o mesmo fechamento (1.100 letras; no mínimo: o veredito, a crítica numerada, a do gestor na curta e a do cliente), com a curta da
  -- ficha paga e com a de antes
  for r in select * from (values
      ('paga', c_paga, regexp_replace(c_paga, '^Agenda: (.*) 1\) Mande; 2\) Segure.*$', '· \1 Para mandar, me diga *mande*.')),
      ('antes', c_nao, regexp_replace(c_nao, '^Agenda: (.*) 1\) Mande \(recomendo\); 2\) Segure.*$', '· \1 Para segurar, me diga.'))) x(caso, inteira, curta)
  loop
    delete from public.resumo_tarde;
    insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, detalhe)
    values (c_h, '5547900000210', 'fechamento', 'novo', 'ligado', 'Fechamento de teste.',
            jsonb_build_object('caracteres', 1100, 'agenda', jsonb_build_object(
              'modo', 'ligado',
              'bloco_diria', jsonb_build_object('modo', 'ligado', 'nivel', 4, 'chars', 900, 'nada_mudou', false, 'incompleto', false, 'linhas', '[]'::jsonb),
              'bloco_mostrou', jsonb_build_array(
                jsonb_build_object('parte', 'veredito', 'texto', 'Agenda de amanhã: 3 decisões.'),
                jsonb_build_object('parte', 'decisao', 'texto', '· Decisão 1: a OS-00069 perde o prazo amanhã. 1) Adio; 2) Mantenho.'),
                jsonb_build_object('parte', 'decisao', 'texto', r.curta),
                jsonb_build_object('parte', 'decisao', 'texto',
                  btrim(regexp_replace('· ' || public._agenda_corta(regexp_replace(c_cli, ': ".*"( \(\*agenda clientes\* mostra inteira\))?\. \*manda', '. *manda'), 220), '\s+', ' ', 'g')))),
              'linhas_diria', jsonb_build_array(
                jsonb_build_object('tipo', 'pergunta', 'perda', 76, 'modo', 'ligado', 'texto', r.inteira),
                jsonb_build_object('tipo', 'cliente', 'perda', 50, 'modo', 'ligado', 'texto', c_cli)))));
    v_x := v_x || r.caso || '=' || (public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande') || '/'
                 || (pg_temp.saude_sem_b(c_h, c_a) ->> 'bloco_grande') || ' ';
  end loop;
  v_res := pg_temp.ok(v_res, 'B6 a saúde: no mínimo do bloco, a curta da ficha paga ("… eu seguro a ficha. Para mandar, me diga *mande*.") conta como a do gestor — não é bloco_grande (a de produção, sem o bloco B, contava 1); com a curta de antes ("Para segurar, me diga.") as duas dão 0 (F2b/produção)',
    btrim(v_x) = 'paga=0/1 antes=0/0', v_x);
  perform pg_temp.gravar(v_res);
end
$b6$;

-- ── V3. A revisão da v2 (wf_aa4ccd8c): o "2) Segure" que a prova de trabalho não desfaz, os casos que faltavam (R2–R10) e o que DOCUMENTA
--     o comportamento atual do "como foi" num dia segurado (C3, C5: muda na F2c, com o cartão ao dono) ──
do $v3$
declare
  v_res   jsonb := '[]'::jsonb;
  c_s30   constant date := date '2026-10-30';
  c_t03   constant date := date '2026-11-03';
  c_q04   constant date := date '2026-11-04';
  c_q05   constant date := date '2026-11-05';
  v_len   uuid;
  v_van   uuid;
  v_rob   uuid;
  v_joao  uuid;
  v_dono  uuid;
  v_adm   uuid;
  v_q     uuid;
  v_q2    uuid;
  r       jsonb;
  r2      jsonb;
  v_t     text;
  v_t2    text;
  v_st    text;
  v_ok    boolean;
  v_n     int;
  v_dono_nome text;
  v_f2c   boolean;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('V3 (o replay de 29/10)', true, 'PULADO: rode pela bancada');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    v_dono := public._agenda_dono(null);
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
    v_dono_nome := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_dono);

    -- B2f (o obrigatório da revisão da v2; o S2 de revisao-v2/cetico-comecou-segure) fora da janela, a OS paga: o dono dá *mande* ao dia 1,
    -- diz "2) Segure" ao dia 2 às 17:10 e às 18:00 dá o "dia feito" do dia 1 (a prova de trabalho chega DEPOIS do Segure): a ficha do dia
    -- 2 e a confirmação da manhã ficam, como o decidir disse ("Combinado: não mando a ficha de qua 04/11 …")
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      v_q := (select q.id from public.agenda_perguntas q where q.chave = format('ficha_estimativa:%s:%s', v_joao, c_t03) and q.estado = 'aberta');
      update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_s30, '16:55'), mostrada_via = 'conversa' where id = v_q;
      r := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_s30, pg_temp.em(c_s30, '17:10'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
      r := public._agenda_gestor_fichas(c_t03, pg_temp.em(c_t03, '16:52'));
      v_q2 := (select q.id from public.agenda_perguntas q where q.chave = format('ficha_estimativa:%s:%s', v_joao, c_q04) and q.estado = 'aberta');
      update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_t03, '16:55'), mostrada_via = 'conversa' where id = v_q2;
      r2 := public.agenda_decidir(v_q2, 2::smallint, v_adm, 'whatsapp', 'segure', c_t03, pg_temp.em(c_t03, '17:10'));
      r := public.agenda_conferir_dia(v_adm, 'cumprido', null, null, 'whatsapp', c_t03, pg_temp.em(c_t03, '18:00'));
      v_ok := public._agenda_ficha_liberada(v_joao, c_q04, pg_temp.em(c_t03, '19:30'));
      v_t := 'comecou(04/11)=' || public._agenda_os_comecou(v_len, c_q04) || ' pagas(04/11)=' || public._agenda_ficha_os_pagas(v_joao, c_q04)::text;
      perform public._agenda_rotina_ficha(c_t03, pg_temp.em(c_t03, '19:30'));
      perform public._agenda_rotina_confirmar(c_q04, pg_temp.em(c_q04, '07:45'));
      v_res := pg_temp.ok(v_res, 'B2f (o obrigatório da revisão da v2) fora da janela: o "2) Segure" do dono ao dia 2 e DEPOIS o "dia feito" do dia 1 (a OS começa): a ficha do dia 2 e a confirmação da manhã ficam, como o decidir disse',
        v_q2 is not null and r2 ->> 'texto' like 'Combinado: não mando a ficha de qua 04/11 para João%' and v_t = 'comecou(04/11)=true pagas(04/11)={}'
        and not v_ok and pg_temp.equipe(v_joao) like '%ficha 2026-11-04 recusada/veto%' and pg_temp.equipe(v_joao) like '%confirmar 2026-11-04 recusada/veto%'
        and pg_temp.equipe(v_joao) not like '%2026-11-04 enfileirada%',
        coalesce(r2 ->> 'texto', '-') || ' | ' || v_t || ' liberada=' || v_ok || ' | ' || coalesce(pg_temp.equipe(v_joao), '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B2g o Segure da OS NÃO paga fora da janela segue a regra de antes (a F2b só estende o Segure ao dia com OS paga por inteiro): a
    -- pergunta nasceu dentro da janela, o dono disse "2) Segure", e a janela fechou (o ligar movido para 01/10): a ficha sai, como antes
    begin
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      v_q := (select q.id from public.agenda_perguntas q where q.chave = format('ficha_estimativa:%s:%s', v_joao, c_t03) and q.estado = 'aberta');
      r2 := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', 'segure', c_s30, pg_temp.em(c_s30, '17:10'));
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      v_ok := public._agenda_ficha_liberada(v_joao, c_t03, pg_temp.em(c_s30, '19:30'));
      v_res := pg_temp.ok(v_res, 'B2g o "2) Segure" de OS NÃO paga, com a janela fechada depois, segue a regra de antes: a ficha sai (a F2b só estende o Segure ao dia com OS paga)',
        v_q is not null and r2 ->> 'texto' like 'Combinado: não mando a ficha de ter 03/11 para João%' and not public._agenda_os_paga_por_inteiro(v_len) and v_ok,
        coalesce(r2 ->> 'texto', '-') || ' | liberada=' || v_ok);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B7d (R2) P2 em SOMBRA, com a ficha segurada: o de antes (sem "Vou ver", nenhuma pergunta ligada ao dono)
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set modo_equipe = 'sombra' where id;
      v_ok := public._agenda_ficha_liberada(v_joao, c_t03, pg_temp.em(date '2026-11-02', '10:00'));
      r := public.agenda_resposta_da_equipe('5547900000004', 'o que tem pra amanhã?', 'wa-f2b-b7d', pg_temp.em(date '2026-11-02', '10:00'));
      v_t := (select string_agg(m.modo || ':' || left(coalesce(m.texto, '-'), 30), ' | ') from public.agenda_equipe_mensagens m
               where m.payee_id = v_joao and m.tipo = 'resposta' and m.dia = c_t03);
      v_n := (select count(*) from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:%s:pergunta', v_joao, c_t03) and q.modo = 'ligado');
      v_res := pg_temp.ok(v_res, 'B7d (R2) P2 em sombra com a ficha segurada: o de antes (sem "Vou ver", sem pergunta ligada ao dono)',
        not v_ok and not coalesce((r ->> 'ficha_segurada')::boolean, false) and coalesce(v_t, '') not like '%Vou ver%' and v_n = 0,
        format('liberada=%s r=%s msgs=%s perguntas_ligadas=%s', v_ok, r, coalesce(v_t, '-'), v_n));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B7e (R3) P2 com a OS paga e o *mande* do dono dado: a ficha está liberada, a resposta é o plano (não "Vou ver")
    begin
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      v_q := (select (x ->> 'pergunta_id')::uuid from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João');
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_s30, pg_temp.em(c_s30, '17:40'));
      v_ok := public._agenda_ficha_liberada(v_joao, c_t03, pg_temp.em(date '2026-11-02', '10:00'));
      v_t2 := public.agenda_equipe_ficha(v_joao, c_t03, date '2026-11-02') ->> 'texto_resposta';
      r := public.agenda_resposta_da_equipe('5547900000004', 'o que tem pra amanhã?', 'wa-f2b-b7e', pg_temp.em(date '2026-11-02', '10:00'));
      v_t := (select string_agg(m.texto, ' | ') from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'resposta' and m.dia = c_t03);
      v_res := pg_temp.ok(v_res, 'B7e (R3) P2 com a OS paga e o *mande* dado: a ficha está liberada e a resposta é o plano',
        v_q is not null and v_ok and not coalesce((r ->> 'ficha_segurada')::boolean, false) and v_t = v_t2 and v_t not like 'Vou ver%',
        format('q=%s mande=%s liberada=%s r=%s txt=%s', v_q is not null, coalesce(r2 ->> 'texto', '-'), v_ok, r, left(coalesce(v_t, '-'), 80)));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B7f (R4) P2 com a ficha segurada só pelo veto da estimativa (OS não paga, dentro da janela, a pergunta da ficha ainda não vista)
    begin
      v_ok := public._agenda_ficha_liberada(v_joao, c_t03, pg_temp.em(date '2026-11-02', '10:00'));
      r := public.agenda_resposta_da_equipe('5547900000004', 'o que tem pra amanhã?', 'wa-f2b-b7f', pg_temp.em(date '2026-11-02', '10:00'));
      v_t := (select string_agg(m.texto, ' | ') from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'resposta' and m.dia = c_t03);
      v_t2 := (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:%s:pergunta', v_joao, c_t03));
      v_res := pg_temp.ok(v_res, 'B7f (R4) P2 com a ficha segurada só pelo veto da estimativa (OS não paga): "Vou ver" e o porquê "o dia é pela minha estimativa …"',
        not v_ok and not public._agenda_os_paga_por_inteiro(v_len) and coalesce((r ->> 'ficha_segurada')::boolean, false)
        and v_t = format('Vou ver com %s e te falo.', v_dono_nome)
        and v_t2 like '%a ficha dele está segurada: o dia é pela minha estimativa e a pergunta da ficha ainda não foi vista (ou você a segurou).%',
        format('liberada=%s r=%s txt=%s pergunta=%s', v_ok, r, coalesce(v_t, '-'), coalesce(v_t2, '-')));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B7g (R9) a mesma pergunta duas vezes no dia com a ficha segurada: duas respostas "Vou ver", UMA pergunta ao dono (aberta)
    begin
      perform pg_temp.pagar(v_len);
      r := public.agenda_resposta_da_equipe('5547900000004', 'o que tem pra amanhã?', 'wa-f2b-b7g1', pg_temp.em(date '2026-11-02', '10:00'));
      r2 := public.agenda_resposta_da_equipe('5547900000004', 'o que tem pra amanhã?', 'wa-f2b-b7g2', pg_temp.em(date '2026-11-02', '11:00'));
      v_t := format('vou_ver=%s perguntas=%s abertas=%s',
        (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'resposta' and m.dia = c_t03 and m.texto like 'Vou ver%'),
        (select count(*) from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:%s:pergunta', v_joao, c_t03)),
        (select count(*) from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:%s:pergunta', v_joao, c_t03) and q.estado = 'aberta'));
      v_res := pg_temp.ok(v_res, 'B7g (R9) a pergunta duas vezes no dia com a ficha segurada: "Vou ver" nas duas e uma pergunta só ao dono',
        coalesce((r ->> 'ficha_segurada')::boolean, false) and coalesce((r2 ->> 'ficha_segurada')::boolean, false)
        and v_t like 'vou_ver=_ perguntas=1 abertas=1' and v_t not like 'vou_ver=0%', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B4j (R6) o Roberto em qui 05: a OS-00074 (concluída) de manhã com a alocação CANCELADA (a vigia tirou o dia) e a OS-00069 à tarde,
    -- fora da janela: a alocação cancelada não segura a ficha da outra OS
    begin
      update public.agenda_config set marcar_sozinho_desde = null where id;
      perform pg_temp.aloc(v_len, c_q05, format('service_order_id = %L', v_van), v_rob, 'tarde');
      v_n := pg_temp.aloc(v_len, c_q05, 'estado = ''cancelada'', cancelada_em = now(), cancelada_motivo = ''replanejado''', v_rob);
      perform pg_temp.status(v_len, 'completed');
      v_ok := public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_q04, '19:30'));
      v_res := pg_temp.ok(v_res, 'B4j (R6) a alocação cancelada da OS concluída não segura a ficha da outra OS do dia',
        v_n > 0 and v_ok and public._agenda_ficha_os_concluidas(v_rob, c_q05) = '{}'::uuid[],
        format('canceladas=%s liberada=%s concluidas=%s', v_n, v_ok, public._agenda_ficha_os_concluidas(v_rob, c_q05)));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B4k (R5) o *mande* depois da baixa com a OS FATURADA e com a OS CANCELADA: o texto diz o estado certo
    begin
      v_t := '';
      foreach v_st in array array['invoiced', 'cancelled'] loop
        begin
          r := public._agenda_gestor_fichas(c_q04, pg_temp.em(c_q04, '16:52'));
          v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
          perform pg_temp.status(v_len, v_st);
          r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_q04, pg_temp.em(c_q04, '17:40'));
          v_t := v_t || coalesce(r2 ->> 'texto', '-') || '|';
          raise exception 'desfaz' using errcode = 'P0097';
        exception when sqlstate 'P0097' then null;
        end;
      end loop;
      v_res := pg_temp.ok(v_res, 'B4k (R5) o *mande* depois da baixa diz "faturada" e "cancelada"',
        v_t = 'A OS-00074 já está faturada: a ficha não sai.|A OS-00074 já está cancelada: a ficha não sai.|', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B1g (R7) o passo iniciado em OUTRA OS não conta
    begin
      alter table public.service_order_steps disable trigger user;
      insert into public.service_order_steps (service_order_id, seq, title, status, started_at)
      values (v_van, 992, 'Passo de teste da ficha paga B (v3)', 'in_progress', pg_temp.em(c_t03, '10:00'));
      alter table public.service_order_steps enable trigger user;
      v_t := format('len=%s van=%s', public._agenda_os_comecou(v_len, c_q04), public._agenda_os_comecou(v_van, c_q04));
      v_res := pg_temp.ok(v_res, 'B1g (R7) passo iniciado em outra OS não conta para esta (e conta para aquela)', v_t = 'len=f van=t', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B1h (R8) o "ok" à FICHA da véspera (não é a confirmação da manhã) não conta
    begin
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em, resposta_texto, resposta_em, leitura)
      values (v_joao, c_t03, 'ficha', 'ligado', 'Ficha de teste da ficha paga B (v3)', pg_temp.em(date '2026-11-02', '19:30'), 'respondida',
              'teste-f2b-v3:ficha:' || v_joao || ':' || c_t03, pg_temp.em(date '2026-11-02', '19:30'), 'ok', pg_temp.em(date '2026-11-02', '19:40'), '{"tipo": "ok"}');
      alter table public.agenda_equipe_mensagens enable trigger user;
      v_t := 'comecou=' || public._agenda_os_comecou(v_len, c_q04);
      v_res := pg_temp.ok(v_res, 'B1h (R8) o "ok" à ficha da véspera não é a confirmação da manhã e não conta', v_t = 'comecou=false', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B1i (R10) o turno NORMAL (a jornada por hora, o tipo padrão; fração nula) aprovado na OS num dia antes conta
    begin
      alter table public.work_shifts disable trigger user;
      insert into public.work_shifts (id, work_profile_id, data, tipo, origem, status, aprovado_por, aprovado_em, service_order_id)
      values ('f2b00000-0000-4000-8000-0000000000aa', gen_random_uuid(), c_t03, 'normal', 'painel', 'aprovado', v_adm, now(), v_len);
      alter table public.work_shifts enable trigger user;
      v_t := 'comecou=' || public._agenda_os_comecou(v_len, c_q04);
      v_res := pg_temp.ok(v_res, 'B1i (R10) o turno normal (por hora, fração nula) aprovado na OS conta', v_t = 'comecou=true', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- B9a e B9b DOCUMENTAM o comportamento atual (C3 e C5 de revisao-v2/cetico-comecou; a causa é de antes da F2b: _agenda_rotina_como_foi
    -- manda o "como foi" sem olhar a liberada). Fora da janela, a OS paga, o dia 1 segurado (sem *mande*): o "ok" do João ao "como foi" do
    -- dia 1 marca o dia cumprido (via equipe), a OS começa, e a ficha do dia 2 (17:30) ou a confirmação da manhã (19:45) SAI sem o *mande*.
    -- NÃO é o que a F2b quer mudar agora: vai ao dono num cartão (F2c). Com a F2c no ar (20270127100000, o "como foi" do dia segurado não sai),
    -- os dois casos mostram o comportamento novo: o "ok" não chega a existir, nada vira prova, e o dia 2 fica.
    v_f2c := exists (select 1 from pg_proc p where p.oid = 'public._agenda_rotina_como_foi(date, timestamptz)'::regprocedure and p.prosrc like '%-- FICHA PAGA C:%');
    for v_st in select unnest(array['17:30', '19:45']) loop
      begin
        perform pg_temp.pagar(v_len);
        update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
        r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
        perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
        perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
        r := public._agenda_gestor_fichas(c_t03, pg_temp.em(c_t03, '16:52'));
        perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
        if v_st = '17:30' then
          r2 := public.agenda_resposta_da_equipe('5547900000004', 'ok', 'wa-f2b-b9a', pg_temp.em(c_t03, '17:30'));
        end if;
        perform public._agenda_rotina_ficha(c_t03, pg_temp.em(c_t03, '19:30'));
        if v_st = '19:45' then
          r2 := public.agenda_resposta_da_equipe('5547900000004', 'ok', 'wa-f2b-b9b', pg_temp.em(c_t03, '19:45'));
          perform public._agenda_rotina_confirmar(c_q04, pg_temp.em(c_q04, '07:45'));
        end if;
        v_t := pg_temp.equipe(v_joao);
        v_t2 := 'comecou(04/11)=' || public._agenda_os_comecou(v_len, c_q04);
        if v_st = '17:30' and v_f2c then
          v_res := pg_temp.ok(v_res, 'B9a (com a F2c no ar) fora da janela, o dia 1 segurado: sem o "como foi", o "ok" das 17:30 não vira prova e a ficha do dia 2 fica',
            v_t2 = 'comecou(04/11)=false' and v_t = 'ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 recusada/veto | ficha 2026-11-04 recusada/veto',
            v_t2 || ' | ' || coalesce(v_t, '-'));
        elsif v_st = '19:45' and v_f2c then
          v_res := pg_temp.ok(v_res, 'B9b (com a F2c no ar) fora da janela, o dia 1 segurado: sem o "como foi", o "ok" das 19:45 não vira prova e a confirmação do dia 2 fica',
            v_t2 = 'comecou(04/11)=false' and v_t = 'ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 recusada/veto | ficha 2026-11-04 recusada/veto | confirmar 2026-11-04 recusada/veto',
            v_t2 || ' | ' || coalesce(v_t, '-'));
        elsif v_st = '17:30' then
          v_res := pg_temp.ok(v_res, 'B9a (DOCUMENTA, C3; muda na F2c) fora da janela, o dia 1 segurado: o "ok" ao "como foi" às 17:30 vira prova e a ficha do dia 2 SAI sem o *mande*',
            v_t2 = 'comecou(04/11)=true' and v_t like 'ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 recusada/veto | como_foi 2026-11-03 respondida | ficha 2026-11-04 enfileirada%',
            v_t2 || ' | ' || coalesce(v_t, '-'));
        else
          v_res := pg_temp.ok(v_res, 'B9b (DOCUMENTA, C5; muda na F2c) fora da janela, o dia 1 segurado: o "ok" ao "como foi" às 19:45 (depois da ficha segurada) vira prova e a confirmação da manhã do dia 2 SAI',
            v_t2 = 'comecou(04/11)=true' and v_t like '%ficha 2026-11-04 recusada/veto | confirmar 2026-11-04 enfileirada%',
            v_t2 || ' | ' || coalesce(v_t, '-'));
        end if;
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then
    v_res := pg_temp.ok(v_res, 'V3 sem erro', false, sqlstate || ': ' || sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$v3$;

-- ── X. Os casos da revisão adversarial da F2b (revisao/forca-testes/extra/casos-extra.sql; cada um mira um mutante que sobrevivia) ──
-- (X07 vale agora para as horas apontadas: o check-in saiu da régua, P1 do dono)
do $xx$
declare
  v_res   jsonb := '[]'::jsonb;
  c_s30   constant date := date '2026-10-30';
  c_t03   constant date := date '2026-11-03';
  c_q04   constant date := date '2026-11-04';
  v_len   uuid;
  v_van   uuid;
  v_rob   uuid;
  v_joao  uuid;
  v_adm   uuid;
  v_q     uuid;
  r       jsonb;
  r2      jsonb;
  v_t     text;
  v_ok    boolean;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('X (o replay de 29/10)', true, 'PULADO: rode pela bancada');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;

    -- X01 (N01) a confirmação de OUTRA pessoa (o Roberto, que não estava na OS-00074 em ter 03/11) não conta, mesmo com o João na OS
    begin
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em, resposta_texto, resposta_em, leitura)
      values (v_rob, c_t03, 'confirmar', 'ligado', 'Confirmação de teste (revisão)', pg_temp.em(c_t03, '07:45'), 'respondida',
              'rev-f2b:confirmar:' || v_rob || ':' || c_t03, pg_temp.em(c_t03, '07:45'), 'ok', pg_temp.em(c_t03, '07:50'), '{"tipo": "ok"}');
      alter table public.agenda_equipe_mensagens enable trigger user;
      v_t := format('rob_na_os=%s joao_na_os=%s comecou=%s',
        exists (select 1 from public.agenda_alocacoes a where a.payee_id = v_rob and a.dia = c_t03 and a.service_order_id = v_len and a.estado in ('publicada', 'fixada')),
        exists (select 1 from public.agenda_alocacoes a where a.payee_id = v_joao and a.dia = c_t03 and a.service_order_id = v_len and a.estado in ('publicada', 'fixada')),
        public._agenda_os_comecou(v_len, c_q04));
      v_res := pg_temp.ok(v_res, 'X01 (N01) confirmação "ok" de quem NÃO estava na OS no dia não conta (outra pessoa na OS)',
        v_t = 'rob_na_os=f joao_na_os=t comecou=f', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- X02 (N02) a confirmação do João em ter 03/11 com a alocação dele CANCELADA (a vigia moveu o dia, como o 18/11 da OS-00129) não conta
    begin
      perform pg_temp.aloc(v_len, c_t03, 'estado = ''cancelada'', cancelada_em = now(), cancelada_motivo = ''replanejado''', v_joao);
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em, resposta_texto, resposta_em, leitura)
      values (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste (revisão)', pg_temp.em(c_t03, '07:45'), 'respondida',
              'rev-f2b:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'), 'ok', pg_temp.em(c_t03, '07:50'), '{"tipo": "ok"}');
      alter table public.agenda_equipe_mensagens enable trigger user;
      v_t := format('cancelada=%s comecou=%s',
        exists (select 1 from public.agenda_alocacoes a where a.payee_id = v_joao and a.dia = c_t03 and a.service_order_id = v_len and a.estado = 'cancelada'),
        public._agenda_os_comecou(v_len, c_q04));
      v_res := pg_temp.ok(v_res, 'X02 (N02) confirmação "ok" num dia em que a alocação da pessoa na OS foi cancelada não conta',
        v_t = 'cancelada=t comecou=f', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- X03 (N11) a confirmação respondida "presença" ("cheguei", "a caminho") conta
    begin
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em, resposta_texto, resposta_em, leitura)
      values (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste (revisão)', pg_temp.em(c_t03, '07:45'), 'respondida',
              'rev-f2b:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'), 'cheguei', pg_temp.em(c_t03, '07:58'),
              public._agenda_ler_resposta_da_equipe('cheguei'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      v_t := format('leitura=%s comecou=%s', public._agenda_ler_resposta_da_equipe('cheguei') ->> 'tipo', public._agenda_os_comecou(v_len, c_q04));
      v_res := pg_temp.ok(v_res, 'X03 (N11) confirmação respondida "cheguei" (presenca) conta', v_t = 'leitura=presenca comecou=t', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- X04 (N05, N06, N07) a diária: PAGA conta; folga e falta sem fração (as que o CHECK permite) na OS não contam; work_shift_os de OUTRA OS não conta
    begin
      v_t := '';
      alter table public.work_shifts disable trigger user;
      alter table public.work_shift_os disable trigger user;
      insert into public.work_shifts (id, work_profile_id, data, tipo, origem, status, aprovado_por, aprovado_em, fracao, valor_diaria, service_order_id)
      values ('f2bfe000-0000-4000-8000-000000000001', gen_random_uuid(), c_t03, 'diaria', 'painel', 'pago', v_adm, now(), 1, 200, v_len);
      v_t := v_t || 'pago=' || public._agenda_os_comecou(v_len, c_q04);
      update public.work_shifts set tipo = 'folga', fracao = null, valor_diaria = null, status = 'aprovado' where id = 'f2bfe000-0000-4000-8000-000000000001';
      v_t := v_t || ' folga=' || public._agenda_os_comecou(v_len, c_q04);
      update public.work_shifts set tipo = 'falta' where id = 'f2bfe000-0000-4000-8000-000000000001';
      v_t := v_t || ' falta_sem_fracao=' || public._agenda_os_comecou(v_len, c_q04);
      update public.work_shifts set tipo = 'diaria', fracao = 1, valor_diaria = 200, service_order_id = null where id = 'f2bfe000-0000-4000-8000-000000000001';
      insert into public.work_shift_os (shift_id, service_order_id) values ('f2bfe000-0000-4000-8000-000000000001', v_van);
      v_t := v_t || ' wso_outra_os=' || public._agenda_os_comecou(v_len, c_q04) || '/' || public._agenda_os_comecou(v_van, c_q04);
      alter table public.work_shifts enable trigger user;
      alter table public.work_shift_os enable trigger user;
      v_res := pg_temp.ok(v_res, 'X04 (N05 N06 N07) diária PAGA conta; folga e falta sem fração na OS não contam; a diária ligada (work_shift_os) a OUTRA OS não conta para esta (e conta para aquela)',
        v_t = 'pago=true folga=false falta_sem_fracao=false wso_outra_os=false/true', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- X05 (N08, N09) o passo iniciado NO PRÓPRIO dia não conta; horas apontadas em OUTRA OS não contam
    begin
      v_t := '';
      alter table public.service_order_steps disable trigger user;
      insert into public.service_order_steps (service_order_id, seq, title, status, started_at) values (v_len, 991, 'Passo de teste (revisão)', 'in_progress', pg_temp.em(c_q04, '10:00'));
      v_t := v_t || 'passo_no_dia=' || public._agenda_os_comecou(v_len, c_q04);
      delete from public.service_order_steps where service_order_id = v_len and seq = 991;
      alter table public.service_order_steps enable trigger user;
      alter table public.time_entries disable trigger user;
      insert into public.time_entries (service_order_id, technician_user_id, started_at) values (v_van, v_adm, pg_temp.em(c_t03, '09:00'));
      v_t := v_t || ' horas_outra_os=' || public._agenda_os_comecou(v_len, c_q04) || '/' || public._agenda_os_comecou(v_van, c_q04);
      alter table public.time_entries enable trigger user;
      v_res := pg_temp.ok(v_res, 'X05 (N08 N09) passo iniciado no próprio dia não conta; horas apontadas em OUTRA OS não contam para esta (e contam para aquela)',
        v_t = 'passo_no_dia=false horas_outra_os=false/true', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- X06 (N10) o dia "cumprido" de OUTRA OS não conta
    begin
      perform pg_temp.aloc(v_len, c_t03, 'resultado = ''cumprido'', resultado_via = ''equipe'', resultado_em = now()', v_joao);
      v_t := format('len=%s van=%s', public._agenda_os_comecou(v_len, c_q04), public._agenda_os_comecou(v_van, date '2026-11-13'));
      v_res := pg_temp.ok(v_res, 'X06 (N10) o dia "cumprido" da OS-00074 conta para ela e não para a OS-00069', v_t = 'len=t van=f', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- X07 (N14) horas apontadas tarde da noite da véspera (02/11 23:30 de Brasília = 03/11 02:30 UTC) contam para o dia 03/11, também com a
    -- sessão em UTC (o dia é o de Brasília)
    begin
      alter table public.time_entries disable trigger user;
      insert into public.time_entries (service_order_id, technician_user_id, started_at) values (v_len, v_adm, pg_temp.em(date '2026-11-02', '23:30'));
      alter table public.time_entries enable trigger user;
      v_t := format('tz_bancada=%s comecou=%s', current_setting('TimeZone'), public._agenda_os_comecou(v_len, c_t03));
      perform set_config('TimeZone', 'UTC', true);
      v_t := v_t || format(' tz=%s comecou=%s', current_setting('TimeZone'), public._agenda_os_comecou(v_len, c_t03));
      perform set_config('TimeZone', 'Etc/GMT+3', true);
      v_res := pg_temp.ok(v_res, 'X07 (N14) horas apontadas às 23:30 da véspera (Brasília) contam para o dia seguinte, também com a sessão em UTC', v_t like '%comecou=t tz=UTC comecou=t', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- X08 (N12) dia misto: OS-00074 PAGA (não começou) de manhã e OS-00069 à tarde; o dono diz *mande* às 17:40 e DEPOIS a OS-00069 é
    -- concluída: às 19:30 a ficha NÃO sai (a concluída vence o *mande* da paga)
    begin
      perform pg_temp.aloc(v_len, c_t03, format('service_order_id = %L', v_van), v_joao, 'tarde');
      perform pg_temp.pagar(v_len);
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      v_q := (select (x ->> 'pergunta_id')::uuid from jsonb_array_elements(r -> 'pessoas') x where x ->> 'nome' = 'João');
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'mande', c_s30, pg_temp.em(c_s30, '17:40'));
      perform pg_temp.status(v_van, 'completed');
      v_ok := public._agenda_ficha_liberada(v_joao, c_t03, pg_temp.em(c_s30, '19:31'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:32'));
      v_t := format('pergunta=%s mande=%s liberada=%s equipe=%s acao=%s', v_q is not null, coalesce(r2 ->> 'texto', '-'), v_ok,
                    coalesce(pg_temp.equipe(v_joao), '-'), coalesce(pg_temp.acao(v_joao), '-'));
      v_res := pg_temp.ok(v_res, 'X08 (N12) dia misto: *mande* dado na paga e a outra OS concluída depois: a ficha fica, porquê da concluída',
        v_q is not null and not v_ok and pg_temp.equipe(v_joao) = 'ficha 2026-11-03 recusada/veto'
        and pg_temp.acao(v_joao) like '%a OS-00069 já está concluída%[concluida]', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then
    v_res := pg_temp.ok(v_res, 'X sem erro', false, sqlstate || ': ' || sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$xx$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
