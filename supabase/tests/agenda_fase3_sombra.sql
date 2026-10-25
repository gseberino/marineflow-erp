-- Prova da migration de dado da Fase 3 da Agenda de Produção (pacote P7b; 20261026101000_agenda_fase3_sombra.sql), que a
-- bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a carteira de 23/10
-- (fixture-2310.sql: a última diária é sáb 17/10; Roberto e João com diária recente, Mickael com a última em 18/09; o dono
-- é o sócio, sem perfil de diária).
-- bancada: depende de 20261026100700
--
--   S  os modos: desligado → sombra (equipe e diária); o resto da linha igual; de novo não muda nada (nem a hora); ligado
--      nunca é rebaixado
--   E  a semente de agenda_equipe_contato pela regra da d14: com telefone, ativo, perfil de diária vigente e diária recente —
--      só o Roberto (o João sem telefone, o Mickael sem diária recente, o dono nunca); a regra, não o nome (o João com
--      telefone entra); quem parou continua parado; o que o dono incluiu continua dele; sem diária nenhuma, ninguém
--   N  nada sai nem é lançado: a fila do WhatsApp, as mensagens à equipe, as diárias e as ações da agenda iguais
--   D  o DESFAZER do cabeçalho: os modos de volta a desligado e quem entrou pela regra marcado como parado (nada apagado)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o
--   supabase/tests/agenda_fase3_pos_deploy.sql (só leitura). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create function pg_temp.res(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false),
                                                      case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
-- A linha de agenda_config sem os modos da Fase 3 e sem o carimbo (o que a migration não pode mexer).
create function pg_temp.resto_da_config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_equipe' - 'modo_diaria' - 'atualizado_em' - 'atualizado_por' from public.agenda_config c
$f$;
create function pg_temp.lista() returns text language sql stable as $f$
  select coalesce(string_agg(split_part(p.name, ' ', 1) || ':' || l.incluido_por || ':' || l.recebe_rotina::text, ', '
                             order by p.name), 'ninguém')
    from public.agenda_equipe_contato l join public.payees p on p.id = l.payee_id
$f$;
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'fila', (select count(*) from public.whatsapp_send_queue),
    'mensagens', (select count(*) from public.agenda_equipe_mensagens),
    'turnos', (select count(*) from public.work_shifts),
    'acoes', (select count(*) from public.agenda_acoes),
    'perguntas', (select count(*) from public.agenda_perguntas))
$f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase3', true);
  v_res    jsonb := '[]'::jsonb;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_desf   text;
  v_bloco  text;
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao    constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_mickael constant uuid := 'bb000000-0000-4000-8000-000000000004';
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
begin
  if coalesce(v_mig, '') = '' then
    insert into _resultado values ('S0 a migration 20261026101000 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase3 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  -- O DESFAZER do cabeçalho: as linhas de SQL ("--   …") entre "-- DESFAZER" e a linha "--" que fecha o bloco.
  v_bloco := substr(v_mig, position(E'\n-- DESFAZER' in v_mig) + 1);
  v_bloco := left(v_bloco, position(E'\n--\n' in v_bloco));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into v_desf
    from regexp_split_to_table(v_bloco, E'\n') with ordinality t(l, n)
   where t.l like '--   %';

  -- O "hoje" do teste: sáb 24/10 (a migration usa _hoje_brt, o relógio de verdade). Dentro da transação: o ROLLBACK desfaz.
  create or replace function public._hoje_brt() returns date language sql stable set search_path to 'public' as $h$
    select coalesce(nullif(current_setting('agenda_teste.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date)
  $h$;
  perform set_config('agenda_teste.hoje', '2026-10-24', true);
  -- Telefones sintéticos: o Roberto, o Mickael (sem diária recente) e o dono (sócio); o João continua sem (como em produção).
  update public.payees set phone = '5547900000001' where id = c_roberto;
  update public.payees set phone = '5547900000003' where id = c_mickael;
  update public.payees set phone = '5547900000009' where id = c_dono;

  -- ── S e E: a 1ª vez, a 2ª vez, o ligado ─────────────────────────────────────────────────────────────────
  begin
    update public.agenda_config set modo_equipe = 'desligado', modo_diaria = 'desligado',
                                    atualizado_em = timestamptz '2026-10-24 12:00-03' where id;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    v_res := pg_temp.res(v_res, 'E0 antes: a lista da rotina vazia', pg_temp.lista() = 'ninguém', pg_temp.lista());

    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S1 desligado → sombra: modo_equipe e modo_diaria',
      v_linha ->> 'modo_equipe' = 'sombra' and v_linha ->> 'modo_diaria' = 'sombra', v_linha::text);
    v_res := pg_temp.res(v_res, 'S2 o resto da linha não muda (leitura, proposta, vigia, cliente, os números); atualizado_por nulo',
      pg_temp.resto_da_config() = v_resto and v_linha ->> 'atualizado_por' is null, pg_temp.resto_da_config()::text);
    v_res := pg_temp.res(v_res, 'E1 a semente pela regra: só o Roberto (o João sem telefone, o Mickael sem diária recente, o dono nunca)',
      pg_temp.lista() = 'Roberto:regra:true', pg_temp.lista());
    v_res := pg_temp.res(v_res, 'N1 nada sai nem é lançado: a fila, as mensagens à equipe, as diárias, as ações e as perguntas iguais',
      pg_temp.contagens() = v_cont, pg_temp.contagens()::text);

    v_linha := (select to_jsonb(c) from public.agenda_config c)
               || jsonb_build_object('lista', (select jsonb_agg(to_jsonb(l) order by l.payee_id) from public.agenda_equipe_contato l));
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S3 idempotente: a 2ª vez não muda nada (nem a hora, nem a lista, nem incluido_em)',
      (select to_jsonb(c) from public.agenda_config c)
      || jsonb_build_object('lista', (select jsonb_agg(to_jsonb(l) order by l.payee_id) from public.agenda_equipe_contato l))
      = v_linha, null);

    update public.agenda_config set modo_diaria = 'ligado', modo_equipe = 'desligado' where id;
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S4 nunca rebaixa ligado (a diária ligada fica; a equipe desligada vai a sombra)',
      v_linha ->> 'modo_diaria' = 'ligado' and v_linha ->> 'modo_equipe' = 'sombra', v_linha::text);
    update public.agenda_config set modo_diaria = 'ligado', modo_equipe = 'ligado',
                                    atualizado_em = timestamptz '2026-10-24 12:00-03' where id;
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S5 os dois ligados: nada muda (nem a hora)',
      v_linha ->> 'modo_diaria' = 'ligado' and v_linha ->> 'modo_equipe' = 'ligado'
      and (v_linha ->> 'atualizado_em')::timestamptz = timestamptz '2026-10-24 12:00-03', v_linha::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── E: a regra, não o nome; quem parou; o que o dono incluiu; sem diária ────────────────────────────────
  begin
    update public.payees set phone = '(47) 90000-0002' where id = c_joao;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'E2 a regra, não o nome: o João com telefone (com máscara) entra também',
      pg_temp.lista() = 'João:regra:true, Roberto:regra:true', pg_temp.lista());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em, parou_em, parou_motivo)
    values (c_roberto, false, 'regra', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-21 12:00-03', 'para de mandar');
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values (c_mickael, true, 'dono', timestamptz '2026-10-20 12:00-03');
    execute v_mig;
    v_res := pg_temp.res(v_res, 'E3 quem parou continua parado e o que o dono incluiu continua dele (on conflict do nothing)',
      pg_temp.lista() = 'Mickael:dono:true, Roberto:regra:false'
      and (select parou_motivo from public.agenda_equipe_contato where payee_id = c_roberto) = 'para de mandar',
      pg_temp.lista());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    delete from public.work_shift_os;
    delete from public.work_shifts;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'E4 sem diária lançada nenhuma, ninguém entra (e os modos vão a sombra igual)',
      pg_temp.lista() = 'ninguém' and (select modo_equipe = 'sombra' from public.agenda_config), pg_temp.lista());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D: o DESFAZER do cabeçalho ─────────────────────────────────────────────────────────────────────────
  begin
    v_res := pg_temp.res(v_res, 'D0 o cabeçalho tem o DESFAZER: dois UPDATE, nenhum DELETE',
      v_desf is not null and (length(v_desf) - length(replace(v_desf, 'update public.', ''))) / length('update public.') = 2
      and position('delete' in lower(v_desf)) = 0, coalesce(v_desf, '(sem o bloco)'));
    update public.agenda_config set modo_equipe = 'desligado', modo_diaria = 'desligado' where id;
    execute v_mig;
    v_cont := pg_temp.contagens();
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta os dois modos a desligado e marca quem entrou pela regra como parado (sem apagar)',
      (select modo_equipe = 'desligado' and modo_diaria = 'desligado' from public.agenda_config)
      and pg_temp.lista() = 'Roberto:regra:false'
      and (select parou_motivo = 'desfeita a migration 20261026101000' and parou_em is not null
             from public.agenda_equipe_contato where payee_id = c_roberto)
      and pg_temp.contagens() = v_cont, pg_temp.lista());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
