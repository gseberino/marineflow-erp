-- Prova da migration de dado da Fase 7a da Agenda de Produção (pacote P7; 20261031100990_agenda_fase7a_sombra.sql), que a
-- bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a carteira real de 29/10 (o
-- replay).
-- bancada: depende de 20261031100600
--
--   S  os 5 modos do gestor: desligado → sombra (marcar, vaga, encaixe, revisao, compre_ate); o resto da linha igual (os modos das
--      Fases 1–6, a lista das regras, *gestor, só propor*, os números); de novo não muda nada (nem a hora); ligado nunca é
--      rebaixado; o que o dono desligou depois de ligar (marcar_sozinho_desde preenchido) não volta a teste
--   N  nada muda fora disso: alocações, propostas, ações, perguntas, mensagens e a fila iguais; e em sombra a rodada do gestor
--      faz a conta do "eu marcaria assim" (o diário do dia) sem escrever no plano
--   D  o DESFAZER do cabeçalho: um bloco só (do $desfaz$ … $desfaz$;), um UPDATE, nenhum DELETE; volta a sombra a desligado e não
--      mexe no ligado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é a chave gestor
--   de agenda_saude (só leitura). Termina em ROLLBACK.
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
-- A linha de agenda_config sem os 5 modos do gestor e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto_da_config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_marcar_sozinho' - 'modo_vaga_fechamento' - 'modo_encaixe_aprovacao' - 'modo_revisao_diaria'
         - 'modo_compre_ate' - 'atualizado_em' - 'atualizado_por'
    from public.agenda_config c
$f$;
create function pg_temp.modos() returns text language sql stable as $f$
  select concat_ws(' ', c.modo_marcar_sozinho, c.modo_vaga_fechamento, c.modo_encaixe_aprovacao, c.modo_revisao_diaria, c.modo_compre_ate)
    from public.agenda_config c
$f$;
-- O que não pode mudar: o plano, as propostas, as ações, as perguntas, as mensagens e a fila.
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select count(*) from public.agenda_acoes),
    'perguntas', (select count(*) from public.agenda_perguntas),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'fila', (select count(*) from public.whatsapp_send_queue),
    'plano', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.service_order_id), '')) from public.os_planejamento p))
$f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase7a', true);
  v_res    jsonb := '[]'::jsonb;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_desf   text;
  v_bloco  text;
  v_alocs  text;
  r        jsonb;
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261031100990 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase7a ou agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  -- O DESFAZER do cabeçalho: as linhas de SQL ("--   …") entre "-- DESFAZER" e a linha "--" que fecha o bloco.
  v_bloco := substr(v_mig, position(E'\n-- DESFAZER' in v_mig) + 1);
  v_bloco := left(v_bloco, position(E'\n--\n' in v_bloco));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into v_desf
    from regexp_split_to_table(v_bloco, E'\n') with ordinality t(l, n)
   where t.l like '--   %';

  execute current_setting('agenda_teste.replay2910');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';

  -- ── S: a 1ª vez, a 2ª vez, o ligado, o desligado depois de ligar ─────────────────────────────────────────────
  begin
    update public.agenda_config
       set modo_marcar_sozinho = 'desligado', modo_vaga_fechamento = 'desligado', modo_encaixe_aprovacao = 'desligado',
           modo_revisao_diaria = 'desligado', modo_compre_ate = 'desligado', marcar_sozinho_desde = null, gestor_so_propor = false,
           atualizado_em = timestamptz '2026-10-29 12:00-03'
     where id;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S1 os 5 modos do gestor de desligado para sombra (marcar, vaga, encaixe, revisao, compre_ate)',
      pg_temp.modos() = 'sombra sombra sombra sombra sombra', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S2 o resto da linha não muda (os modos das Fases 1–6, as regras, *gestor, só propor*, os números); atualizado_por nulo e a hora nova',
      pg_temp.resto_da_config() = v_resto and v_linha ->> 'atualizado_por' is null
      and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-10-29 12:00-03', pg_temp.resto_da_config()::text);
    v_res := pg_temp.res(v_res, 'N1 nada muda fora disso: o plano, as propostas, as ações, as perguntas, as mensagens e a fila iguais',
      pg_temp.contagens() = v_cont, pg_temp.contagens()::text);

    execute v_mig;
    v_res := pg_temp.res(v_res, 'S3 idempotente: a 2ª vez não muda nada (nem a hora)', (select to_jsonb(c) from public.agenda_config c) = v_linha, null);

    -- em sombra a rodada do gestor faz a conta e não escreve no plano
    v_alocs := v_cont ->> 'alocacoes';
    r := public.agenda_gestor_rodar(date '2026-10-29', (timestamp '2026-10-29 16:52') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.res(v_res, 'N2 em sombra a rodada das 16:52 faz o "eu marcaria assim" (o diário do dia com o texto do fechamento) e não escreve alocação, proposta, ação nem mensagem',
      (r ->> 'rodou')::boolean and (r ->> 'diaria')::boolean
      and (select texto_sombra like 'Agenda em teste (nada mudou): eu marcaria assim — %' from public.agenda_gestor_dia where dia = date '2026-10-29')
      and pg_temp.contagens() ->> 'alocacoes' = v_alocs and (pg_temp.contagens() ->> 'propostas') = (v_cont ->> 'propostas')
      and (pg_temp.contagens() ->> 'acoes') = (v_cont ->> 'acoes') and (pg_temp.contagens() ->> 'equipe') = (v_cont ->> 'equipe')
      and (pg_temp.contagens() ->> 'cliente') = (v_cont ->> 'cliente') and (pg_temp.contagens() ->> 'fila') = (v_cont ->> 'fila'),
      left(r::text, 400));

    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado',
                                    marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03', atualizado_em = timestamptz '2026-10-29 12:00-03'
     where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 nunca rebaixa ligado (o gestor ligado fica, com a hora)',
      pg_temp.modos() = 'ligado sombra ligado sombra sombra'
      and (select atualizado_em from public.agenda_config) = timestamptz '2026-10-29 12:00-03', pg_temp.modos());
    update public.agenda_config set modo_marcar_sozinho = 'desligado', modo_compre_ate = 'desligado' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5 o dono desligou depois de ligar (marcar_sozinho_desde preenchido): a migration não volta a teste calada',
      pg_temp.modos() = 'desligado sombra ligado sombra desligado', pg_temp.modos());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D: o DESFAZER do cabeçalho ─────────────────────────────────────────────────────────────────────────
  begin
    v_res := pg_temp.res(v_res, 'D0 o cabeçalho tem o DESFAZER num bloco só (do $desfaz$ … $desfaz$;): um UPDATE, nenhum DELETE',
      v_desf is not null and v_desf ~ '^\s*do \$desfaz\$' and v_desf ~ '\$desfaz\$;\s*$'
      and (length(v_desf) - length(replace(v_desf, '$desfaz$', ''))) / length('$desfaz$') = 2
      and (length(v_desf) - length(replace(v_desf, 'update public.', ''))) / length('update public.') = 1
      and position('delete' in lower(v_desf)) = 0, coalesce(v_desf, '(sem o bloco)'));
    update public.agenda_config
       set modo_marcar_sozinho = 'desligado', modo_vaga_fechamento = 'desligado', modo_encaixe_aprovacao = 'desligado',
           modo_revisao_diaria = 'desligado', modo_compre_ate = 'desligado', marcar_sozinho_desde = null
     where id;
    execute v_mig;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta os 5 de sombra a desligado; o resto da linha e o plano ficam',
      pg_temp.modos() = 'desligado desligado desligado desligado desligado' and pg_temp.resto_da_config() = v_resto
      and pg_temp.contagens() = v_cont and (select atualizado_por from public.agenda_config) is null, pg_temp.modos());
    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_vaga_fechamento = 'sombra' where id;
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D2 o DESFAZER não mexe no que já foi ligado (para isso, *gestor, só propor* ou o modo para sombra)',
      pg_temp.modos() = 'ligado desligado desligado desligado desligado', pg_temp.modos());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
