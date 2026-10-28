-- Agenda de Produção, pós-merge (C): agrupar e desagrupar OS conhecendo a agenda — 29/10/2026.
-- Montada por scratchpad agenda-pesquisa/posmerge/montar-migration.mjs (edite as partes, nunca este arquivo).
--
-- ═══ POR QUE ═══
-- O agrupar_os (main, 28/10, 20261028120000) não conhecia as tabelas da agenda. Ao juntar OS-A + OS-B na OS-N:
--   · o material de cada origem (os_material: o que falta, o que está a caminho e com que previsão, o que o dono disse)
--     ficava na origem cancelada, e a OS-N nascia sem nada: a sincronização da carteira recriaria as linhas como "falta"
--     e a peça já comprada voltaria para a lista de compras;
--   · os meios-dias publicados das origens continuavam no plano: a ficha da equipe, a diária automática e a conferência
--     seguiriam falando de uma OS cancelada até a próxima rodada do motor;
--   · a data dita ao cliente (os_planejamento.prometido_*) ficava na origem: a OS-N, que é o serviço de verdade, não tinha
--     promessa nenhuma — o aviso de atraso (M6) nunca sairia;
--   · o desagrupar devolvia o status das origens com UPDATE direto, por fora da porta única (os_transicionar_status).
-- Inventário das tabelas da agenda com vínculo à OS (grep nas migrations 2026102[4-9]*, colunas service_order_id/os_ids):
--   MOVE      os_material (vínculo à OS e à linha copiada; volta no desagrupar por os_agrupamento_movidos)
--   SAI DO PLANO  agenda_alocacoes vigentes sem resultado (cancelada_motivo 'os_saiu', o motivo do motor para a OS que saiu
--             da carteira: não conta contra a capacidade do dono — que só lê dono/pessoa — nem contra o aprendizado);
--             agenda_propostas abertas que contam com a OS (obsoletas, como a vigia faz quando a agenda muda);
--             agenda_rascunho aberto da OS (descartado: o *grava* não pode aplicar numa OS cancelada)
--   PASSA     os_planejamento.prometido_* (a data dita ao cliente, pela _agenda_cliente_gravar_prometido, o gravador da
--             Fase 5; a mais cedo, se mais de uma origem tem)
--   FICA      (história, ou já protegido no caminho de saída) os_planejamento e os_planejamento_equipe das origens (o
--             desagrupar precisa deles); agenda_alocacoes com resultado; agenda_acoes, agenda_perguntas (a limpeza da vigia
--             resolve a pergunta da OS que saiu da carteira), agenda_intervencoes_do_dono, agenda_medidas_os,
--             material_sinais, material_remessas, agenda_cliente_respostas; agenda_cliente_mensagens pendentes (o envio
--             revalida na hora — _agenda_cliente_revalidar devolve 'status' para OS cancelada — e o worker não manda);
--             agenda_fornecedor_mensagens (a pergunta segue a linha de material, que agora é da OS-N e continua valendo);
--             agenda_equipe_mensagens (sem vínculo à OS).
--
-- ═══ O QUE FAZ ═══ (4 funções novas e 5 recriadas; cada recriada copia a definição MAIS NOVA e só ganha os blocos
-- "-- PÓS-MERGE: (C) … -- PÓS-MERGE: fim" — o _desagrupar_os_desfazer também perde a linha do status no UPDATE das
-- origens, que passa a ir pela porta)
--   NOVAS
--   · _os_agenda_execucao(os): o dia que a conferência anotou como feito (cumprido ou parcial) — é execução, como a hora
--     apontada. Texto pronto ou nulo.
--   · _agenda_os_saiu_por_agrupar(os, outra, texto, autor): tira a OS do plano — os meios-dias vigentes sem resultado
--     cancelados com 'os_saiu' (o fixado também: a OS não existe mais como estava), a ação 'cancelar' (origem sistema) com
--     o texto, as propostas abertas obsoletas e o rascunho aberto descartado.
--   · _agrupar_os_agenda(agrupamento, origens, nova, principal, número, mapas, autor): o material das origens passa à nova
--     (cada linha com a peça/serviço copiado, guardada em os_agrupamento_movidos para o desagrupar devolver; previsões e o
--     original ficam como estavam), cada origem sai do plano, a data dita ao cliente passa e os avisos.
--   · _os_porta_desagrupar(os, para, autor, hoje, agora): o caminho do desagrupar na porta — só com a chave
--     marineflow.desagrupar_os = a OS (ligada pelo _desagrupar_os_desfazer), admin ou financeiro, de cancelada para um status
--     de antes de começar; escreve pela _agenda_escrever_os e grava a ação 'status'.
--   RECRIADAS
--   · os_transicionar_status (de 20261026100700): a via 'desagrupar' vai à _os_porta_desagrupar. Nada mais muda.
--   · _os_impedimento_para_agrupar (de 20261028120000): o dia feito na agenda recusa como execução.
--   · _os_impedimento_para_desagrupar (de 20261028120000): o dia feito na agenda recusa; a data dita ao cliente DEPOIS de
--     agrupar recusa (é da agrupada; as originais não a têm).
--   · _agrupar_os_montar (de 20261028120000): chama _agrupar_os_agenda depois de cancelar as origens; os avisos entram.
--   · _desagrupar_os_desfazer (de 20261028120000): o status das origens volta pela porta (via desagrupar); a agrupada sai
--     do plano como as origens saíram; o material volta com os outros movidos (o laço genérico de os_agrupamento_movidos).
--
-- DECISÃO (C, item 2 — a data já dita ao cliente): PASSA para a OS agrupada, em vez de recusar o agrupar. Recusar não tinha
-- saída: a promessa só some quando a OS é concluída (e aí ela já começou e não agrupa mais), então toda OS com data dita
-- ficaria impossível de agrupar. Passando, nada se perde calado: a OS-N fica com a mesma promessa (tipo, faixa, fonte, a 1ª
-- data), a rodada do cliente confere o plano novo contra ela e o M6/a pergunta ao dono saem pelo caminho de sempre se não
-- couber; o aviso do agrupar diz. Os meios-dias saem com 'os_saiu' e a OS-N entra no próximo planejamento.
--
-- APLICAR (só com o OK nomeado do dono; depois de 20261028120000 e 20261029101000):
--   npx supabase db query --linked -f supabase/migrations/20261029110000_agenda_posmerge_agrupar_os.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029110000', 'agenda_posmerge_agrupar_os');"
--   Sem redeploy de edge function: o agrupar e o desagrupar são do banco (a tela e o assistente chamam agrupar_os/desagrupar_os).
--
-- PROVA: supabase/tests/agenda_posmerge_agrupar.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029110000
--
-- DESFAZER (volta as 5 recriadas ao que eram e tira as 4 novas; o material já movido por um agrupar continua na OS
-- agrupada, e o desagrupar de antes também o devolve — o laço de os_agrupamento_movidos é genérico):
--   npx supabase db query --linked -f supabase/migrations/20261026100700_agenda_fase3_levantamento_na_porta.sql
--   npx supabase db query --linked -f supabase/migrations/20261028120000_agrupar_os.sql
--   npx supabase db query --linked -e "drop function if exists public._os_porta_desagrupar(uuid, text, uuid, date, timestamptz);
--     drop function if exists public._agrupar_os_agenda(uuid, uuid[], uuid, uuid, text, jsonb, jsonb, uuid);
--     drop function if exists public._agenda_os_saiu_por_agrupar(uuid, uuid, text, uuid);
--     drop function if exists public._os_agenda_execucao(uuid);
--     delete from supabase_migrations.schema_migrations where version = '20261029110000';"
--   (as duas migrations reaplicadas são idempotentes: create or replace, if not exists, drop trigger if exists.)
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 1. As 4 funções novas ──────────────────────────────────────────────────────────────────────────────

-- O dia que a conferência anotou como feito (ou feito em parte) numa OS: é execução, como a hora apontada. Nulo = nenhum.
create or replace function public._os_agenda_execucao(p_os uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select 'dia anotado como feito na agenda (' || public._dia_curto(min(a.dia)) || ')'
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.resultado in ('cumprido', 'parcial')
  having count(*) > 0
$$;

comment on function public._os_agenda_execucao(uuid) is
  'Agenda de Produção (pós-merge C): o dia da OS que a conferência anotou como feito (cumprido ou parcial) — "dia anotado como feito na agenda (ter 03/11)", o mais antigo — ou nulo. É execução para o agrupar e o desagrupar de OS, como a hora apontada (_os_execucao_iniciada). Sem grant.';

-- A OS saiu do plano porque foi agrupada (ou porque a agrupada foi desfeita). O que já foi conferido fica (é história).
-- p_texto: o texto da ação, com {dias} no lugar dos dias que saíram.
create or replace function public._agenda_os_saiu_por_agrupar(p_os uuid, p_outra uuid, p_texto text, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_hoje  date := public._agenda_hoje();
  v_ids   uuid[];
  v_dias  date[];
  v_antes jsonb;
  v_va    bigint;
  v_vd    bigint;
  v_props uuid[];
  v_rasc  integer;
  v_acao  uuid;
begin
  -- 1. Os meios-dias vigentes sem resultado saem com 'os_saiu' (o motivo do motor para a OS que saiu da carteira: a
  --    capacidade do dono só conta o que saiu por ele ou pela pessoa, e o aprendizado não mede o que não aconteceu). O
  --    fixado também sai: a OS como estava não existe mais. Uma ação 'cancelar' (origem sistema) diz o que saiu.
  select coalesce(array_agg(a.id order by a.dia, a.turno, a.payee_id, a.id), '{}'),
         coalesce(array_agg(distinct a.dia), '{}'),
         coalesce(jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno,
                                               'tipo', a.tipo, 'estado', a.estado, 'fixado_por', a.fixado_por)
                            order by a.dia, a.turno, a.payee_id, a.id), '[]'::jsonb)
    into v_ids, v_dias, v_antes
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.resultado is null;
  if cardinality(v_ids) > 0 then
    v_va := (public._agenda_cfg()).versao_plano;
    perform set_config('agenda.mexe_fixado', 'on', true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'os_saiu' where id = any (v_ids);
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_vd := (public._agenda_cfg()).versao_plano;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, versao_antes,
                                     versao_depois, alocacoes_canceladas, antes, depois, texto, motivo, autor)
    values (clock_timestamp(), v_hoje, true, 'sistema', 'cancelar', p_os, array_remove(array[p_os, p_outra], null), v_va, v_vd,
            v_ids, jsonb_build_object('alocacoes', v_antes),
            jsonb_build_object('alocacoes', '[]'::jsonb, 'motivo', 'os_saiu', 'outra_os', p_outra),
            left(replace(p_texto, '{dias}', public._agenda_dias_texto(array(select d from unnest(v_dias) d order by d))), 400),
            'os_saiu', p_autor)
    returning id into v_acao;
  end if;
  -- 2. O plano montado (aberto) que conta com ela não se publica mais: obsoleto, como a vigia faz quando a agenda muda.
  with x as (
    update public.agenda_propostas p set estado = 'obsoleta', motivo_fim = 'a agenda mudou'
     where p.estado = 'aberta'
       and (p_os = any (p.os_alvo)
            or exists (select 1 from jsonb_array_elements(p.itens) e where e ->> 'os' = p_os::text))
    returning p.id)
  select coalesce(array_agg(x.id), '{}') into v_props from x;
  delete from public.agenda_alocacoes where proposta_id = any (v_props) and estado = 'proposta';
  -- 3. O rascunho do dono sobre ela, ainda sem o *grava*, não vale mais (gravaria numa OS que saiu).
  update public.agenda_rascunho r set estado = 'descartado' where r.service_order_id = p_os and r.estado = 'aberto';
  get diagnostics v_rasc = row_count;
  return jsonb_build_object('alocacoes_canceladas', cardinality(v_ids), 'dias', to_jsonb(v_dias), 'acao_id', v_acao,
                            'propostas_obsoletas', cardinality(v_props), 'rascunhos_descartados', v_rasc);
end $$;

comment on function public._agenda_os_saiu_por_agrupar(uuid, uuid, text, uuid) is
  'Agenda de Produção (pós-merge C): tira do plano a OS que o agrupar (ou o desagrupar) tirou de cena — os meios-dias vigentes sem resultado saem com cancelada_motivo os_saiu (o fixado também, com agenda.mexe_fixado), com uma ação cancelar de origem sistema e o texto (p_texto, {dias} = os dias que saíram); as propostas abertas que contam com ela ficam obsoletas ("a agenda mudou", e as alocações de proposta delas saem); o rascunho aberto dela fica descartado. O que já tem resultado fica. {alocacoes_canceladas, dias, acao_id, propostas_obsoletas, rascunhos_descartados}. Sem grant.';

-- O agrupar e a agenda: o material, o plano e a data dita ao cliente. Chamada pelo _agrupar_os_montar depois de cancelar
-- as origens (p_mapa_peca e p_mapa_serv: a linha da origem → a linha copiada na nova).
create or replace function public._agrupar_os_agenda(p_agrupamento uuid, p_ids uuid[], p_novo uuid, p_base uuid, p_numero text,
                                                     p_mapa_peca jsonb, p_mapa_serv jsonb, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_mat    integer := 0;
  v_canc   integer := 0;
  v_props  integer := 0;
  v_rasc   integer := 0;
  v_saiu   text[] := '{}';
  v_r      jsonb;
  o        record;
  v_prom   record;
  v_quando text;
  v_prom_de text;
  v_avisos text[] := '{}';
begin
  -- 1. Material: cada linha das origens passa à nova, ligada à peça/serviço copiado (a origem guarda as linhas dela como
  --    histórico). Só o vínculo muda: situação, quantidades, fornecedor, previsões e o original ficam como estavam (o gatilho
  --    do original não mexe nele numa troca de vínculo). Cada coluna mudada fica em os_agrupamento_movidos: o desagrupar
  --    devolve a linha à origem e à peça/serviço de antes.
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id)
  select p_agrupamento, 'os_material', 'service_order_id', m.id, m.service_order_id
    from public.os_material m where m.service_order_id = any (p_ids);
  get diagnostics v_mat = row_count;
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select p_agrupamento, 'os_material', 'service_order_part_id', m.id, m.service_order_id, m.service_order_part_id
    from public.os_material m where m.service_order_id = any (p_ids) and m.service_order_part_id is not null;
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select p_agrupamento, 'os_material', 'service_order_service_id', m.id, m.service_order_id, m.service_order_service_id
    from public.os_material m where m.service_order_id = any (p_ids) and m.service_order_service_id is not null;
  update public.os_material m
     set service_order_id = p_novo,
         service_order_part_id = (p_mapa_peca ->> m.service_order_part_id::text)::uuid,
         service_order_service_id = (p_mapa_serv ->> m.service_order_service_id::text)::uuid
   where m.service_order_id = any (p_ids);
  if exists (select 1 from public.os_material m where m.service_order_id = any (p_ids))
     or exists (select 1 from public.os_material m
                  join public.os_agrupamento_movidos x on x.agrupamento_id = p_agrupamento and x.tabela = 'os_material'
                                                      and x.registro_id = m.id and x.coluna <> 'service_order_id'
                 where (x.coluna = 'service_order_part_id' and m.service_order_part_id is null)
                    or (x.coluna = 'service_order_service_id' and m.service_order_service_id is null)) then
    raise exception 'Conferência falhou: o material das OS originais não passou inteiro para a OS agrupada. Nada foi gravado.';
  end if;
  if v_mat > 0 then
    v_avisos := v_avisos || format('O material das originais (%s linha(s): o que falta, o que está a caminho e as previsões) passou para a %s.',
                                   v_mat, p_numero);
  end if;

  -- 2. O plano: cada origem sai (os_saiu); a nova entra no próximo planejamento.
  for o in select so.id, so.service_order_number as numero from public.service_orders so
            where so.id = any (p_ids) order by so.created_at, so.id loop
    v_r := public._agenda_os_saiu_por_agrupar(o.id, p_novo,
             format('Tirei do plano a %s, agrupada na %s: saíram {dias}. A %s entra no próximo planejamento.', o.numero, p_numero, p_numero),
             p_autor);
    v_canc := v_canc + (v_r ->> 'alocacoes_canceladas')::int;
    v_props := v_props + (v_r ->> 'propostas_obsoletas')::int;
    v_rasc := v_rasc + (v_r ->> 'rascunhos_descartados')::int;
    if (v_r ->> 'alocacoes_canceladas')::int > 0 then
      v_saiu := v_saiu || (o.numero || ' (' || public._agenda_dias_texto(array(
                  select (d #>> '{}')::date from jsonb_array_elements(v_r -> 'dias') d order by 1)) || ')');
    end if;
  end loop;
  if cardinality(v_saiu) > 0 then
    v_avisos := v_avisos || format('Saíram do plano da agenda os dias de %s; a %s entra no próximo planejamento.',
                                   array_to_string(v_saiu, ', '), p_numero);
  end if;

  -- 3. A data dita ao cliente passa para a nova (a mais cedo, se mais de uma origem tem; no empate, a da principal), pelo
  --    gravador da Fase 5, com a 1ª data dita (a pontualidade da Fase 6 mede contra ela). A rodada do cliente confere o
  --    plano novo contra ela e avisa pelo caminho de sempre se não couber.
  select p.prometido_tipo, p.prometido_de, p.prometido_ate, p.prometido_fonte, p.prometido_mensagem_id,
         p.prometido_original_ate, p.prometido_primeiro_ate, so.service_order_number as numero
    into v_prom
    from public.os_planejamento p
    join public.service_orders so on so.id = p.service_order_id
   where p.service_order_id = any (p_ids) and p.prometido_ate is not null
   order by p.prometido_ate, (p.service_order_id = p_base) desc, so.created_at, so.id
   limit 1;
  if found then
    v_prom_de := v_prom.numero;
    perform public._agenda_cliente_gravar_prometido(p_novo, v_prom.prometido_tipo, v_prom.prometido_de, v_prom.prometido_ate,
              v_prom.prometido_fonte, v_prom.prometido_mensagem_id, now(),
              format('Veio da %s, agrupada na %s.', v_prom.numero, p_numero));
    update public.os_planejamento p
       set prometido_original_ate = coalesce(v_prom.prometido_original_ate, p.prometido_original_ate),
           prometido_primeiro_ate = coalesce(v_prom.prometido_primeiro_ate, v_prom.prometido_original_ate, p.prometido_primeiro_ate)
     where p.service_order_id = p_novo;
    v_quando := case when v_prom.prometido_de is not null and v_prom.prometido_de < v_prom.prometido_ate
                     then public._dia_curto(v_prom.prometido_de) || ' a ' || public._dia_curto(v_prom.prometido_ate)
                     else public._dia_curto(v_prom.prometido_ate) end;
    v_avisos := v_avisos || format('A data dita ao cliente na %s (%s) passou para a %s: a agenda confere o plano dela contra essa data e avisa se não couber.',
                                   v_prom.numero, v_quando, p_numero);
  end if;

  return jsonb_build_object('materiais', v_mat, 'alocacoes_canceladas', v_canc, 'propostas_obsoletas', v_props,
                            'rascunhos_descartados', v_rasc, 'prometido_de', v_prom_de, 'avisos', to_jsonb(v_avisos));
end $$;

comment on function public._agrupar_os_agenda(uuid, uuid[], uuid, uuid, text, jsonb, jsonb, uuid) is
  'Agenda de Produção (pós-merge C): o que o agrupar de OS faz na agenda, depois de cancelar as origens — (1) toda linha de os_material das origens passa à nova com a peça/serviço copiado (p_mapa_peca/p_mapa_serv), sem mudar situação, previsões nem o original, guardada em os_agrupamento_movidos (o desagrupar devolve); confere que nada ficou na origem; (2) cada origem sai do plano (_agenda_os_saiu_por_agrupar, os_saiu); (3) a data dita ao cliente (os_planejamento.prometido_*) da origem mais cedo (empate: a principal) passa à nova pela _agenda_cliente_gravar_prometido, com o original e a 1ª data dita dela. {materiais, alocacoes_canceladas, propostas_obsoletas, rascunhos_descartados, prometido_de, avisos}. Sem grant.';

-- O caminho do desagrupar na porta única: a origem cancelada pelo agrupar volta ao status de antes.
create or replace function public._os_porta_desagrupar(p_os uuid, p_para text, p_autor uuid, p_hoje date, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_os    record;
  v_texto text;
  v_acao  uuid;
begin
  -- Só de dentro do desagrupar (a chave é local à transação e não se liga pela API: set_config não está no schema exposto).
  if p_os is null or coalesce(current_setting('marineflow.desagrupar_os', true), '') <> p_os::text then
    raise exception 'Uma OS cancelada só volta pelo "Desagrupar" da OS agrupada.' using errcode = '42501';
  end if;
  if v_autor is null or not public.is_admin_or_financial(v_autor) then
    raise exception 'Só administrador ou financeiro pode desagrupar OS.' using errcode = '42501';
  end if;
  select so.id, so.service_order_number as numero, so.status into v_os
    from public.service_orders so where so.id = p_os for update;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;
  if v_os.status is distinct from 'cancelled' then
    return public._agenda_porta_fica(false, v_os.status,
      format('A %s não está cancelada: o desagrupar não muda o status dela.', v_os.numero));
  end if;
  if p_para is null or p_para not in ('open', 'approved', 'scheduled', 'awaiting_parts', 'awaiting_client') then
    return public._agenda_porta_fica(false, v_os.status,
      format('O desagrupar só devolve a %s a uma situação de antes de começar (aberta, aprovada, agendada ou aguardando).', v_os.numero));
  end if;
  perform public._agenda_escrever_os(p_os, p_para, null, null, null, false);
  v_texto := format('%s: volta a %s (desagrupada).', v_os.numero, public._agenda_status_texto(p_para));
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes, status_depois,
                                   antes, depois, texto, autor)
  values (clock_timestamp(), coalesce(p_hoje, public._hoje_brt()), true, 'sistema', 'status', p_os, array[p_os], 'cancelled', p_para,
          jsonb_build_object('status', 'cancelled'), jsonb_build_object('status', p_para, 'via', 'desagrupar'), left(v_texto, 400),
          v_autor)
  returning id into v_acao;
  return jsonb_build_object('ok', true, 'mudou', true, 'de', 'cancelled', 'para', p_para, 'texto', left(v_texto, 400),
                            'acao_id', v_acao);
end $$;

comment on function public._os_porta_desagrupar(uuid, text, uuid, date, timestamptz) is
  'Agenda de Produção (pós-merge C): a via desagrupar da porta única (os_transicionar_status). Só com a chave marineflow.desagrupar_os = a OS (o _desagrupar_os_desfazer a liga para cada origem; senão 42501), o autor admin/financeiro, a OS cancelada e o pedido aberta/aprovada/agendada/aguardando (senão {ok false} com a frase): escreve pela _agenda_escrever_os e grava a ação status (origem sistema, depois.via desagrupar). {ok, mudou, de, para, texto, acao_id}. Sem grant.';

-- ── 2. A porta (corpo de 20261026100700; o bloco "-- PÓS-MERGE: (C)" no começo) ────────────────────────────
create or replace function public.os_transicionar_status(
  p_os        uuid,
  p_para      text,
  p_via       text,
  p_motivo    text        default null,
  p_autor     uuid        default null,
  p_check_in  timestamptz default null,
  p_hoje      date        default public._hoje_brt(),
  p_agora     timestamptz default now(),
  p_check_out timestamptz default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config;
  v_uid    uuid := auth.uid();
  v_papel  text;
  v_autor  uuid;
  v_os     record;
  v_de     text;
  v_para   text := p_para;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_nome   text;
  v_check  timestamptz;
  v_novo_check boolean := false;
  v_falta  text;
  v_antes  text;
  v_texto  text;
  v_origem text;
  v_acao   uuid;
  -- FASE 3: quem pode, a conversão, a conclusão e o desfazer dela.
  v_tipo      text;
  v_gestor    boolean := false;
  v_tecnico   boolean := false;
  v_vendedor  boolean := false;
  v_num_novo  text;
  v_acao_conv uuid;
  v_r         jsonb;
  v_conc      public.agenda_acoes%rowtype;
  v_saida     timestamptz;
  v_venc      jsonb;
  v_venc_cob  jsonb;
  v_com_antes uuid[];
  v_coms      uuid[];
  v_rec       jsonb;
  v_ids       uuid[];
  v_erro      text;
  v_cob       text;
  v_venc_dia  date;
  v_venc_soma numeric;
  -- FASE 3: fim
  -- FASE 3 (P7a): a regra que só depende do cargo, do status, do pedido e do caminho (_os_porta_regra).
  v_regra     jsonb;
begin
  -- PÓS-MERGE: (C) o desagrupar de OS (_desagrupar_os_desfazer) devolve a origem cancelada pelo agrupar ao status de antes por aqui,
  -- como todo caminho que muda status: _os_porta_desagrupar decide (só com a chave do desagrupar daquela OS) e escreve pela
  -- _agenda_escrever_os, com a linha em agenda_acoes. Nenhum outro caminho tira uma OS de cancelada.
  if p_via = 'desagrupar' then
    return public._os_porta_desagrupar(p_os, p_para, p_autor, p_hoje, p_agora);
  end if;
  -- PÓS-MERGE: fim
  if p_via is null or p_via not in ('tela_agendar', 'aprovacao', 'assistente', 'check_in', 'oc', 'motor', 'vigia',
                                    'conferencia', 'dono', 'desfazer',
                                    -- FASE 3: a tela (a mudança genérica de status), a assinatura do cliente e o gestor
                                    -- pela palavra do técnico.
                                    'tela', 'assinatura', 'equipe') then
    raise exception 'Caminho desconhecido para mudar o status: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_para is null or p_para not in ('draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client',
                                      'approved', 'completed', 'invoiced', 'cancelled') then
    raise exception 'Status desconhecido: "%".', coalesce(p_para, '') using errcode = '22023';
  end if;
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam a OS, o dia ou a hora para mudar o status.' using errcode = '22023';
  end if;

  perform set_config('agenda.hoje', p_hoje::text, true);
  c := public._agenda_cfg();

  select so.id, so.service_order_number as numero, so.status, so.check_in_at, cl.name as cliente,
         -- FASE 3: o que a conclusão, a entrega e a conversão leem.
         so.check_out_at, so.delivered_at, so.converted_to_os_at, so.grand_total, so.original_quote_amount
    into v_os
    from public.service_orders so
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os
     for update of so;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  -- Quem pede: com login, o próprio login; sem login (service role, o próprio banco), p_autor — motor e vigia podem
  -- vir sem. Um JWT de outro papel sem login não ganha o direito de dizer quem é.
  if v_uid is not null then
    -- FASE 3: a assinatura do cliente vem só pela service_role (submit-signature), nunca com login. Revisão da Fase 3 (R6):
    -- com login, quem chama não escolhe a via — o motor, a vigia e o gestor (equipe) também são só do banco, e o dono e a
    -- conferência, só do administrador ou do financeiro.
    if p_via in ('assinatura', 'equipe', 'motor', 'vigia')
       or (p_via in ('dono', 'conferencia') and not public.is_admin_or_financial(v_uid)) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    v_autor := v_uid;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    -- FASE 3: além do motor e da vigia, o gestor (equipe) e a assinatura do cliente vêm sem autor.
    if v_papel not in ('', 'service_role') or (p_autor is null and p_via not in ('motor', 'vigia', 'equipe', 'assinatura')) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    -- FASE 3: a assinatura é do cliente: nunca tem autor.
    v_autor := case when p_via = 'assinatura' then null else p_autor end;
  end if;

  -- FASE 3: quem pode muda com o que se pede (spec-fase3 §5.3). A régua da Fase 2 (admin/financeiro ativo ou técnico ativo
  -- da OS, com a mesma frase) continua para o status de agenda, e o vendedor ativo entra nela pela tela; converter,
  -- concluir, faturar e reabrir têm a régua e a frase delas.
  if v_autor is not null then
    v_gestor   := public.is_admin_or_financial(v_autor);
    v_tecnico  := exists (select 1 from public.service_order_technicians t
                            join public.app_users u on u.id = t.user_id
                           where t.service_order_id = p_os and t.user_id = v_autor and u.active);
    v_vendedor := exists (select 1 from public.app_users u where u.id = v_autor and u.active and u.role = 'seller');
  end if;
  -- FASE 3 (P7a): o tipo do pedido, quem pode e as passagens que não dependem de dado vêm de _os_porta_regra — a mesma
  -- função que a tela (os_status_da_tela) lê para esconder da lista rápida e dos kanbans o que a porta recusa.
  v_regra := public._os_porta_regra(v_os.status, v_para, p_via, v_gestor, v_tecnico, v_vendedor, v_autor is not null,
                                    v_motivo is not null, c.modo_proposta = 'ligado');
  v_tipo := v_regra ->> 'tipo';
  if v_regra ->> 'recusa' = 'quem' then
    raise exception '%', v_regra ->> 'texto' using errcode = '42501';
  end if;
  -- FASE 3 (P7a): fim
  -- FASE 3: a origem de cada caminho (estava depois da escrita; a conclusão e a conversão também a usam).
  v_origem := case p_via
    when 'tela_agendar' then 'tela'
    when 'check_in'     then 'sistema'
    when 'oc'           then 'sistema'
    when 'desfazer'     then 'dono'
    when 'assinatura'   then 'sistema'
    else p_via end;
  -- FASE 3: fim

  v_de   := v_os.status;
  v_nome := coalesce(public._agenda_nome_curto(v_os.cliente) || ' (' || v_os.numero || ')', v_os.numero);

  -- FASE 3 (P7a): cancelada, faturada, cancelar, concluída, orçamento sem converter, voltar a orçamento, faturar antes de
  -- concluir, "já está", a OS que já começou, a agendada pela tela e o cliente que não liberou: a frase de _os_porta_regra
  -- (1 = o número, 2 = o nome, 3 = o status de agora, 4 = o pedido).
  if v_regra ->> 'recusa' = 'passagem' then
    return public._agenda_porta_fica((v_regra ->> 'fica')::boolean, v_de,
      format(v_regra ->> 'texto', v_os.numero, v_nome, public._agenda_status_texto(v_de), public._agenda_status_texto(v_para)))
      -- Revisão da Fase 3 (R2): só faltou o motivo (em andamento → aguardando, pelo dono ou pela tela): quem chama pede.
      || case when coalesce((v_regra ->> 'pede_motivo')::boolean, false) then jsonb_build_object('pede_motivo', true)
              else '{}'::jsonb end;
  end if;
  -- FASE 3 (P7a): fim

  -- FASE 3: encerrada, faturada, cancelada e orçamento. A Fase 2 recusava tudo aqui ("concluir é pela tela"); agora a
  -- conclusão, o faturamento, a reabertura e a conversão são da porta. Cancelar continua no botão Cancelar OS.
  -- FASE 3 (P7a): cancelada, faturada, cancelar e concluída sem ser faturar/reabrir/desfazer saíram para _os_porta_regra.
  if v_de = 'completed' then

    -- O desfazer da conclusão (só de dentro do agenda_desfazer, que diz qual ação desfaz em agenda.desfaz_conclusao):
    -- volta ao status de antes, e a saída sai se foi a conclusão que a gravou.
    if p_via = 'desfazer' then
      select a.* into v_conc
        from public.agenda_acoes a
       where a.id::text = coalesce(current_setting('agenda.desfaz_conclusao', true), '')
         and a.service_order_id = p_os and a.tipo = 'concluir' and a.executada and a.desfeita_em is null;
      if not found or v_conc.status_antes is distinct from v_para then
        return public._agenda_porta_fica(false, v_de,
          'Desfazer a conclusão é pelo *desfaz* da agenda; para reabrir, use a tela da OS.');
      end if;
      perform public._agenda_escrever_conclusao(p_os, v_para, null, (v_conc.antes ->> 'check_out_at') is null, null, null);
      v_texto := format('%s: de concluída para %s (desfeito).', v_nome, public._agenda_status_texto(v_para));
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
              jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at),
              jsonb_build_object('status', v_para, 'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os),
                                 'via', p_via, 'desfaz_conclusao', v_conc.id),
              left(v_texto, 400), v_autor)
      returning id into v_acao;
      return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                                'acao_id', v_acao, 'check_in_at', v_os.check_in_at,
                                'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os));
    end if;

    if v_para = 'invoiced' then
      perform public._agenda_escrever_os(p_os, 'invoiced', null, null, null, false);
      v_texto := format('%s: faturada.', v_nome);
    else
      -- Reabrir (paridade com a tela: a saída e as cobranças ficam; o início, se faltava, como no "em andamento").
      if v_para = 'in_progress' and v_os.check_in_at is null then
        v_check := coalesce(p_check_in, p_agora);
        v_novo_check := true;
      end if;
      perform public._agenda_escrever_os(p_os, v_para, v_check, null, null, false);
      v_texto := format('Reabri o %s', v_nome)
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.status <> 'cancelled')
                then '. As cobranças da conclusão continuam; se for o caso, ajuste no financeiro.'
                else ' (agora está ' || public._agenda_status_texto(v_para) || ').' end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor)
    values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
            jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at, 'check_out_at', v_os.check_out_at),
            jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
            left(v_texto, 400), left(v_motivo, 200), v_autor)
    returning id into v_acao;
    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check),
                              'check_out_at', v_os.check_out_at);
  end if;

  if v_de = 'draft' then
    -- FASE 3 (P7a): o orçamento sem conversão saiu para _os_porta_regra.
    -- A conversão: o número troca SÓ o prefixo (ORÇ-00119 → OS-00119), converted_to_os_at e original_quote_amount uma vez;
    -- depois, na mesma chamada, a regra de aprovada → X. Se o passo X recusar, a conversão também não fica.
    v_num_novo := case when v_os.numero like 'ORÇ-%' then 'OS-' || substr(v_os.numero, 5) else v_os.numero end;
    if v_num_novo <> v_os.numero
       and exists (select 1 from public.service_orders o2 where o2.service_order_number = v_num_novo and o2.id <> p_os) then
      return public._agenda_porta_fica(false, v_de, format('Não converti: o número %s já é de outra OS.', v_num_novo));
    end if;
    begin
      perform public._agenda_escrever_conclusao(p_os, 'approved', null, false, null,
        jsonb_build_object('numero', v_num_novo, 'converted_to_os_at', coalesce(v_os.converted_to_os_at, p_agora),
                           'original_quote_amount', coalesce(v_os.original_quote_amount, nullif(v_os.grand_total, 0))));
      v_texto := format('Orçamento %s virou a %s (aprovada).', v_os.numero, v_num_novo);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], 'draft', 'approved',
              jsonb_build_object('status', 'draft', 'numero', v_os.numero, 'converted_to_os_at', v_os.converted_to_os_at),
              jsonb_build_object('status', 'approved', 'numero', v_num_novo, 'convertido', true, 'via', p_via),
              left(v_texto, 400), v_autor)
      returning id into v_acao_conv;
      if v_para = 'approved' then
        return jsonb_build_object('ok', true, 'mudou', true, 'de', 'draft', 'para', 'approved', 'texto', left(v_texto, 400),
                                  'acao_id', v_acao_conv, 'convertido', true, 'numero', v_num_novo,
                                  'numero_antes', v_os.numero, 'check_in_at', v_os.check_in_at);
      end if;
      v_r := public.os_transicionar_status(p_os, v_para, p_via, p_motivo, p_autor, p_check_in, p_hoje, p_agora, p_check_out);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = v_r::text;
      end if;
    exception when sqlstate 'P0098' then
      return sqlerrm::jsonb || jsonb_build_object('de', 'draft', 'para', 'draft', 'mudou', false);
    end;
    return v_r || jsonb_build_object('de', 'draft', 'mudou', true, 'convertido', true, 'numero', v_num_novo,
                                     'numero_antes', v_os.numero, 'acao_conversao', v_acao_conv,
                                     'acao_id', coalesce(v_r -> 'acao_id', to_jsonb(v_acao_conv)),
                                     'texto', left(v_texto || ' ' || coalesce(v_r ->> 'texto', ''), 400));
  end if;

  -- FASE 3 (P7a): voltar a orçamento e faturar antes de concluir saíram para _os_porta_regra.

  -- A conclusão (ativo → concluída): (1) a OS já está travada; (2) as cobranças ANTES do status, como a tela (o gatilho do
  -- vencimento "na entrega" roda depois e as acerta); (3) um UPDATE com o status e a saída; (4) a ação concluir com as
  -- cobranças criadas. Erro em (2) ou (3) = nada muda (a OS, as cobranças e a saída ficam como estavam) e o texto diz por quê.
  if v_para = 'completed' then
    -- FASE 3 (P7b): D11 (decisão do dono, 17/09/2026) em TODO caminho de conclusão — a tela (o formulário, a lista rápida,
    -- os kanbans), a assinatura, a equipe, as palavras e a conversa (os_registrar_marco), o assistente: concluir exige o
    -- levantamento RESPONDIDO nos serviços marcados "exige levantamento". Nada muda (nem a conversão do orçamento que vinha
    -- junto) e a frase é a do formulário, a que o dono já conhece (NOVO-agenda-24).
    if cardinality(public._os_levantamentos_pendentes(p_os)) > 0 then
      return public._agenda_porta_fica(false, v_de,
        public._os_texto_do_levantamento(public._os_levantamentos_pendentes(p_os)));
    end if;
    -- FASE 3 (P7b): fim
    -- O retrato do que a conclusão vai mexer, para o desfazer: os vencimentos "na entrega" que o gatilho move e as comissões
    -- que já existiam (a de vendedor nasce no gatilho).
    select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'due_date', r.due_date) order by r.id), '[]'::jsonb) into v_venc
      from public.receivables r
     where r.service_order_id = p_os and r.due_on_completion and r.status not in ('paid', 'cancelled');
    select coalesce(jsonb_agg(jsonb_build_object('id', cc.id, 'due_date', cc.due_date) order by cc.id), '[]'::jsonb) into v_venc_cob
      from public.collections cc
      join public.receivables r on r.id = cc.receivable_id
     where r.service_order_id = p_os and r.due_on_completion and cc.status = 'pending';
    v_com_antes := array(select cm.id from public.commissions cm where cm.service_order_id = p_os);
    v_saida := coalesce(v_os.check_out_at, p_check_out, p_agora);
    begin
      v_rec := public._os_criar_recebiveis_da_conclusao(p_os, p_hoje);
      perform public._agenda_escrever_conclusao(p_os, 'completed', v_saida, false, null, null);
    exception when others then
      get stacked diagnostics v_erro = message_text;
      return public._agenda_porta_fica(false, v_de, public._os_erro_da_conclusao(v_erro));
    end;
    v_ids  := coalesce(array(select (x #>> '{}')::uuid from jsonb_array_elements(v_rec -> 'criados') x), '{}');
    v_coms := array(select cm.id from public.commissions cm
                     where cm.service_order_id = p_os and not (cm.id = any (v_com_antes)) order by cm.id);

    if v_rec ->> 'motivo' in ('parcelas', 'titulo_unico') then
      v_cob := case when cardinality(v_ids) = 1 then 'Cobrança: ' else 'Cobranças: ' end
               || public._os_cobrancas_texto(v_ids, p_hoje, v_os.numero) || '.';
    elsif v_rec ->> 'motivo' = 'total_zero' then
      v_cob := 'Sem cobrança: o total da OS está zerado.';
    else
      select min(r.due_date), sum(r.amount) into v_venc_dia, v_venc_soma
        from public.receivables r
       where r.id in (select (x ->> 'id')::uuid from jsonb_array_elements(v_venc) x);
      v_cob := 'As cobranças já existiam'
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.is_deposit
                                                                 and r.status in ('paid', 'partially_paid'))
                then ' (sinal pago)' else '' end
        || case when v_venc_dia is not null
                then format('; o saldo na entrega (%s) passa a vencer %s', public._brl(v_venc_soma),
                            case when v_venc_dia = p_hoje then 'hoje' else public._dia_curto(v_venc_dia) end)
                else '' end
        || '.';
    end if;
    v_texto := format('%s: concluída — saída %s %s.', v_nome,
                      public._dia_curto((v_saida at time zone 'America/Sao_Paulo')::date),
                      to_char(v_saida at time zone 'America/Sao_Paulo', 'HH24:MI'))
               || ' ' || v_cob;

    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor, desfazivel_ate, receivable_ids)
    values (clock_timestamp(), p_hoje, true, v_origem, 'concluir', p_os, array[p_os], v_de, 'completed',
            jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at, 'vencimentos', v_venc,
                               'cobrancas_vencimento', v_venc_cob),
            jsonb_build_object('status', 'completed', 'check_out_at', v_saida, 'via', p_via, 'cobrancas', v_rec ->> 'motivo',
                               'comissoes', to_jsonb(v_coms)),
            left(v_texto, 400), left(v_motivo, 200), v_autor,
            -- o gestor (equipe) e o dono (palavra, conversa) desfazem; a tela e a assinatura reabrem pela tela.
            case when v_origem in ('equipe', 'dono') then p_agora + c.desfazer_validade end,
            v_ids)
    returning id into v_acao;

    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', 'completed', 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', v_os.check_in_at, 'check_out_at', v_saida,
                              'cobrancas', v_rec, 'cobrancas_texto', v_cob);
  end if;
  -- FASE 3: fim

  -- Igual: nada a fazer — menos o início que faltava numa OS em andamento. FASE 3 (P7a): o "já está" dos outros status
  -- sai de _os_porta_regra; aqui só chega a OS em andamento (o início que falta depende do dado).
  if v_para = v_de then
    if v_de = 'in_progress' and v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    else
      return public._agenda_porta_fica(true, v_de, format('%s já está %s.', v_nome, public._agenda_status_texto(v_de)));
    end if;
  end if;

  -- A regra de cada passagem (vale em todos os modos; a do dia no plano, só em 'ligado').
  if v_para = 'scheduled' then
    -- FASE 3 (P7a): a OS que já começou e o cliente que não liberou saíram para _os_porta_regra.
    if v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    end if;
    if c.modo_proposta = 'ligado' and not public._agenda_os_tem_dia(p_os, p_hoje) then
      return public._agenda_porta_fica(true, v_de,
        format('Sem dia no plano: a OS continua %s.', public._agenda_status_texto(v_de)));
    end if;

  elsif v_para = 'in_progress' then
    if v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    end if;

  -- FASE 3 (P7a): aguardar depois de começar (a OC, o "parou" sem o dono ou sem o motivo) saiu para _os_porta_regra.

  elsif v_para in ('open', 'approved') then
    -- FASE 3 (P7a): a OS que já começou e a agendada pela tela saíram para _os_porta_regra.
    if v_de = 'scheduled' then
      if public._agenda_os_tem_dia(p_os, p_hoje) then
        return public._agenda_porta_fica(false, v_de, 'A OS ainda tem dia no plano: tire o dia antes.');
      end if;
      -- Volta ao que era antes de agendar (aberta ou aprovada); sem registro, aprovada. Revisão da Fase 3 (R2): pela tela
      -- (o administrador ou o financeiro, com a agenda automática fora de ligado: _os_porta_regra), o status que ele
      -- escolheu.
      if p_via <> 'tela' then
        select a.status_antes into v_antes
          from public.agenda_acoes a
         where a.service_order_id = p_os and a.tipo = 'status' and a.executada and a.status_depois = 'scheduled'
         order by a.criada_em desc, a.id desc
         limit 1;
        v_para := case when v_antes in ('open', 'approved') then v_antes else 'approved' end;
      end if;
    elsif v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    -- FASE 3 (P7a): o cliente que não liberou saiu para _os_porta_regra.
    end if;
  end if;

  -- Grava (a única escrita) e registra.
  perform public._agenda_escrever_os(p_os, case when v_para <> v_de then v_para end, v_check, null, null, false);

  v_texto := case
    when v_para = v_de then format('%s: início registrado', v_nome)
    else format('%s: de %s para %s', v_nome, public._agenda_status_texto(v_de), public._agenda_status_texto(v_para)) end
    || case when v_novo_check
            then format(' (%s às %s)', public._dia_curto((v_check at time zone 'America/Sao_Paulo')::date),
                        to_char(v_check at time zone 'America/Sao_Paulo', 'HH24:MI'))
            else '' end
    || coalesce(' — ' || rtrim(v_motivo, '. '), '') || '.';
  -- FASE 3: a origem de cada caminho saiu daqui para antes das regras (a conclusão e a conversão também a usam).

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                   status_depois, antes, depois, texto, motivo, autor, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
          jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at),
          jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
          left(v_texto, 400), left(v_motivo, 200), v_autor,
          -- FASE 3: o gestor (equipe) desfaz como o motor e a vigia: é ação autônoma.
          case when v_origem in ('motor', 'vigia', 'equipe') then p_agora + c.desfazer_validade end)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                            'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check));
end;
$function$;

comment on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 2; Fase 3: conclusão, faturamento, reabertura, conversão e p_check_out; Fase 3, P7a: as regras que só dependem do cargo, do status, do pedido e do caminho moram em _os_porta_regra, a mesma função que a tela lê; Fase 3, P7b: o D11 — concluir exige o levantamento respondido nos serviços marcados "exige levantamento", em todo caminho, com a frase do formulário): a porta única de status da OS. Vias: tela, tela_agendar, aprovacao, assistente, check_in, oc, motor, vigia, equipe, conferencia, dono, assinatura, desfazer. Status de agenda (todos os modos): em andamento nunca volta (agendada/aberta/aprovada) e só volta a aguardar com o motivo, pelo dono ou pela tela (admin/financeiro, técnico da OS; sem o motivo {ok false, pede_motivo true}) (a OC: ok, nada muda); aguardando peças só sai com o material completo; aguardando o cliente só sai pelo dono, a tela de agendar, a aprovação ou a assinatura do cliente; agendada só volta (para o status de antes) pela agenda ou pelo dono e sem dia no plano, e pela tela (para o status escolhido) só o admin/financeiro com a agenda automática fora de ligado; com login, as vias motor, vigia, equipe e assinatura são recusadas (42501), e dono e conferência só valem para admin/financeiro; em modo_proposta ligado, agendada só com dia no plano; check_in_at uma vez. Fase 3: concluir (ativo → concluída) exige o levantamento respondido (_os_levantamentos_pendentes vazio; senão nada muda e {ok false} com "Para concluir, responda o levantamento de: …"), cria as cobranças da condição (_os_criar_recebiveis_da_conclusao, paridade com a tela) ANTES do status e grava a saída num UPDATE só, tudo ou nada ({ok false} com o texto); faturar só concluída; reabrir concluída (tela, dono) mantém saída e cobranças; orçamento → X (tela, assistente, dono, aprovação, assinatura) converte trocando só o prefixo do número e aplica aprovada → X na mesma chamada (se X recusar, a conversão também não fica); cancelar é Cancelar OS. Quem pode: status de agenda = admin/financeiro, técnico da OS, vendedor pela tela; converter = admin/financeiro, vendedor (tela, assistente), assinatura; concluir = admin/financeiro, técnico da OS, assinatura, equipe; faturar/reabrir/desfazer a conclusão = admin/financeiro. Toda mudança: linha em agenda_acoes (status; concluir com receivable_ids; desfazível quando foi motor/vigia/equipe, e a conclusão pela equipe ou pelo dono). Devolve {ok, mudou, de, para, texto, acao_id, check_in_at, check_out_at; na conclusão cobrancas e cobrancas_texto; na conversão convertido, numero, numero_antes}. PÓS-MERGE (C): via desagrupar — só de dentro do _desagrupar_os_desfazer (a chave marineflow.desagrupar_os), decidida e escrita pela _os_porta_desagrupar (cancelada → o status de antes de agrupar).';

-- ── 3. O agrupar e o desagrupar (corpos de 20261028120000; os blocos "-- PÓS-MERGE: (C)") ─────────────────
create or replace function public._os_impedimento_para_agrupar(p_os uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.service_orders;
  v_destino text;
  v_motivo text;
  v_calc numeric;
begin
  select so.* into r from public.service_orders so where so.id = p_os;
  if r.id is null then
    return 'OS não encontrada. Recarregue a tela.';
  end if;
  if r.merged_into_id is not null then
    select d.service_order_number into v_destino from public.service_orders d where d.id = r.merged_into_id;
    return format('%s já foi agrupada em %s.', r.service_order_number, coalesce(v_destino, 'outra OS'));
  end if;
  if r.status = 'draft' then
    return format('%s ainda é um orçamento (não virou OS). Para juntar orçamentos, use "Agrupar orçamentos".',
                  r.service_order_number);
  end if;
  if r.status = 'cancelled' then
    return format('%s está cancelada e não pode ser agrupada.', r.service_order_number);
  end if;
  v_motivo := public._os_execucao_iniciada(p_os);
  if v_motivo <> '' then
    return format('%s já começou a ser executada (%s). Agrupar só junta OS que ainda não começaram; cada OS executada mantém seu histórico.',
                  r.service_order_number, v_motivo);
  end if;
  -- PÓS-MERGE: (C) a agenda: o dia que a conferência anotou como feito (ou feito em parte) também é execução — a mesma frase.
  v_motivo := public._os_agenda_execucao(p_os);
  if v_motivo is not null then
    return format('%s já começou a ser executada (%s). Agrupar só junta OS que ainda não começaram; cada OS executada mantém seu histórico.',
                  r.service_order_number, v_motivo);
  end if;
  -- PÓS-MERGE: fim
  if r.status not in ('scheduled', 'open', 'awaiting_parts', 'awaiting_client', 'approved') then
    return format('%s está numa situação que não permite agrupar (%s).', r.service_order_number, r.status);
  end if;
  if coalesce(r.card_fee_passthrough_enabled, false) then
    return format('%s repassa a taxa do cartão ao cliente. Desligue o repasse nela antes de agrupar (dá para ligar de novo na OS nova).',
                  r.service_order_number);
  end if;
  v_motivo := public._os_vinculos_que_impedem(p_os);
  if v_motivo <> '' then
    return format('%s tem %s. Uma OS com nota, fatura ou comissão não entra num agrupamento: resolva isso antes ou deixe-a de fora.',
                  r.service_order_number, v_motivo);
  end if;
  select c.grand_total into v_calc from public.calc_so_totals(r.id) c;
  if abs(coalesce(r.grand_total, 0) - coalesce(v_calc, 0)) > 0.005 then
    return format('O total gravado de %s (%s) está desatualizado (o certo é %s). Abra e salve essa OS antes de agrupar.',
                  r.service_order_number, public._agrupar_orcamentos_reais(r.grand_total), public._agrupar_orcamentos_reais(v_calc));
  end if;
  return null;
end $$;

create or replace function public._os_impedimento_para_desagrupar(p_agrupado uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ag public.service_orders;
  v_grupo uuid;
  v_saldo uuid;
  v_destino text;
  v_motivo text;
begin
  select so.* into v_ag from public.service_orders so where so.id = p_agrupado;
  if v_ag.id is null then
    return 'OS não encontrada. Recarregue a tela.';
  end if;
  select g.id, g.saldo_criado_id into v_grupo, v_saldo from public.orcamento_agrupamentos g
   where g.agrupado_id = p_agrupado and g.desfeito_em is null and g.tipo = 'os';
  if v_grupo is null then
    return format('%s não é uma OS agrupada (ou já foi desagrupada).', v_ag.service_order_number);
  end if;
  if v_ag.merged_into_id is not null then
    select d.service_order_number into v_destino from public.service_orders d where d.id = v_ag.merged_into_id;
    return format('%s foi agrupada de novo em %s. Desagrupe %s primeiro.',
                  v_ag.service_order_number, coalesce(v_destino, 'outra OS'), coalesce(v_destino, 'essa'));
  end if;
  if v_ag.status = 'cancelled' then
    return format('%s está cancelada: não dá mais para desagrupar.', v_ag.service_order_number);
  end if;
  v_motivo := public._os_execucao_iniciada(p_agrupado);
  if v_motivo <> '' then
    return format('%s já começou a ser executada (%s): não dá mais para desagrupar. As originais ficam como histórico.',
                  v_ag.service_order_number, v_motivo);
  end if;
  -- PÓS-MERGE: (C) a agenda: o dia anotado como feito na agrupada também é execução (a mesma frase); e a data dita ao cliente
  -- DEPOIS de agrupar é da agrupada — as originais não a têm, e desagrupar a deixaria numa OS cancelada, sem aviso.
  v_motivo := public._os_agenda_execucao(p_agrupado);
  if v_motivo is not null then
    return format('%s já começou a ser executada (%s): não dá mais para desagrupar. As originais ficam como histórico.',
                  v_ag.service_order_number, v_motivo);
  end if;
  if exists (select 1 from public.os_planejamento p
              join public.orcamento_agrupamentos g on g.id = v_grupo
             where p.service_order_id = p_agrupado and p.prometido_ate is not null and p.prometido_em > g.criado_em) then
    return format('%s tem data dita ao cliente depois de agrupar (%s): desagrupar a deixaria numa OS cancelada e o cliente ficaria sem ela. Mantenha a %s agrupada.',
                  v_ag.service_order_number,
                  (select public._dia_curto(p.prometido_ate) from public.os_planejamento p where p.service_order_id = p_agrupado),
                  v_ag.service_order_number);
  end if;
  -- PÓS-MERGE: fim
  if v_ag.signed_at is not null
     or exists (select 1 from public.service_order_signatures s where s.service_order_id = p_agrupado) then
    return format('%s já foi assinada pelo cliente: não dá para desagrupar.', v_ag.service_order_number);
  end if;
  v_motivo := public._os_vinculos_que_impedem(p_agrupado);
  if v_motivo <> '' then
    return format('%s tem %s: não dá para desagrupar.', v_ag.service_order_number, v_motivo);
  end if;
  -- O saldo que o próprio agrupar lançou é cancelado no desagrupar; com dinheiro recebido nele, não dá
  -- (o pagamento não tem original para onde voltar).
  if v_saldo is not null
     and exists (select 1 from public.receivables x where x.id = v_saldo and x.status is distinct from 'cancelled'
                   and (coalesce(x.paid_amount, 0) > 0 or x.status in ('paid', 'partially_paid'))) then
    return format('%s já recebeu pagamento no saldo que o agrupar lançou ("Saldo — %s"): não dá para desagrupar.',
                  v_ag.service_order_number, v_ag.service_order_number);
  end if;
  -- Lançado na agrupada DEPOIS de agrupar (não veio de nenhuma original): ficaria preso na agrupada cancelada.
  -- O lançamento do extrato conciliado pelo pagamento de um recebível MOVIDO não prende: volta com ele
  -- (_desagrupar_os_desfazer).
  select concat_ws(', ',
    case when exists (select 1 from public.receivables x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and x.id is distinct from v_saldo
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'receivables' and m.registro_id = x.id)) then 'conta a receber' end,
    case when exists (select 1 from public.collections x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'collections' and m.registro_id = x.id)) then 'cobrança' end,
    case when exists (select 1 from public.bank_charges x where x.service_order_id = p_agrupado
                        and coalesce(x.status, '') not in ('cancelled', 'failed')
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'bank_charges' and m.registro_id = x.id)) then 'boleto/Pix de cobrança' end,
    case when exists (select 1 from public.payables x where x.linked_service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'payables' and m.registro_id = x.id)) then 'conta a pagar' end,
    case when exists (select 1 from public.purchase_orders x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'purchase_orders' and m.registro_id = x.id)) then 'pedido de compra' end,
    case when exists (select 1 from public.quote_requests x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'quote_requests' and m.registro_id = x.id)) then 'cotação a fornecedor' end,
    case when exists (select 1 from public.comprovantes x where x.destino_os_id = p_agrupado
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'comprovantes' and m.registro_id = x.id)) then 'comprovante' end,
    case when exists (select 1 from public.bank_transactions t where t.reconciled_service_order_id = p_agrupado
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'bank_transactions' and m.registro_id = t.id)
                        and not exists (select 1 from public.payments p
                                          join public.os_agrupamento_movidos m on m.agrupamento_id = v_grupo
                                           and m.tabela = 'receivables' and m.registro_id = p.receivable_id
                                         where p.id = t.reconciled_payment_id or p.bank_transaction_id = t.id))
         then 'lançamento do extrato conciliado' end,
    case when exists (select 1 from public.anotacoes_do_extrato x where x.os_id = p_agrupado and x.status is distinct from 'cancelada'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'anotacoes_do_extrato' and m.registro_id = x.id)) then 'anotação do extrato' end
  ) into v_motivo;
  if v_motivo <> '' then
    return format('%s ganhou %s depois de agrupar. Cancele ou mova isso para uma das originais antes de desagrupar.',
                  v_ag.service_order_number, v_motivo);
  end if;
  return null;
end $$;

create or replace function public._agrupar_os_montar(
  p_ids uuid[],
  p_base uuid,
  p_numero text,            -- null = gera OS- pelo document_number_seq DEPOIS de validar tudo
  p_autor uuid,
  p_total_esperado numeric  -- soma dos grand_total que a tela mostrou; null = não confere
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_travados uuid[];
  v_ordem uuid[];
  v_numeros text[];
  v_n integer;
  v_base public.service_orders;
  v_desloc public.service_orders;
  r public.service_orders;
  v_bloqueio text;
  v_qtd integer;
  v_lista text;
  v_soma_gravada numeric := 0;
  v_soma_base numeric := 0;
  v_calc_base numeric;
  v_seq text;
  v_numero text;
  v_quem text;
  v_novo uuid;
  v_agrupamento uuid;
  v_novo_linha uuid;
  v_mapa_serv jsonb := '{}'::jsonb;
  v_mapa_peca jsonb := '{}'::jsonb;
  v_ts timestamptz := clock_timestamp();
  v_total numeric;
  v_motivo text;
  v_receb_antes numeric;
  v_receb_qtd integer;
  v_receb_movido numeric;
  v_pagamento text;
  v_pagamento_certo text;
  v_original numeric;
  v_avisos text[] := '{}';
  v_assinadas text;
  v_quote_status text;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_saldo_id uuid;
  v_saldo_valor numeric;
  v_receb_nova numeric;
  n_servicos integer := 0;
  n_pecas integer := 0;
  n_passos integer := 0;
  n_tecnicos integer := 0;
  n_envios integer := 0;
  n_receb integer := 0;
  n_cobr integer := 0;
  n_tarefas integer := 0;
  n_movidos integer := 0;
  n_x integer;
  t_problema text[]; t_achados text[]; t_diagnostico text[]; t_solucao text[]; t_escopo text[]; t_interno text[];
  t_instrucoes text[]; t_acesso text[]; t_financeiro text[]; t_notas_tec text[]; t_relatorio text[];
  v_desconto numeric; v_imposto numeric; v_subcontrato numeric; v_horas numeric;
  v_desc_serv numeric; v_desc_pecas numeric;
  s record;
  pc record;
  st record;
  v_produto uuid;
  -- PÓS-MERGE: (C) o que o agrupar fez na agenda (_agrupar_os_agenda): o material, o plano e a data dita ao cliente.
  v_agenda jsonb;
  -- PÓS-MERGE: fim
begin
  -- 0. Quem pede (a checagem mora aqui também: _montar nunca roda sem cargo)
  if p_autor is null then
    raise exception 'Faça login para agrupar OS.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar OS.' using errcode = '42501';
  end if;

  -- 1. Entrada
  if p_ids is null or cardinality(p_ids) = 0 or array_position(p_ids, null) is not null then
    raise exception 'Escolha pelo menos 2 OS para agrupar.' using errcode = '22023';
  end if;
  v_ids := array(select distinct x from unnest(p_ids) x);
  if cardinality(v_ids) <> cardinality(p_ids) then
    raise exception 'A mesma OS foi escolhida duas vezes.' using errcode = '22023';
  end if;
  v_n := cardinality(v_ids);
  if v_n < 2 then
    raise exception 'Escolha pelo menos 2 OS para agrupar.' using errcode = '22023';
  end if;
  if v_n > 10 then
    raise exception 'Agrupe no máximo 10 OS de uma vez.' using errcode = '22023';
  end if;

  -- 2. Trava as origens sempre na mesma ordem (dois agrupamentos simultâneos não se travam; o segundo
  --    espera o primeiro e cai em "já foi agrupada")
  select array_agg(t.id) into v_travados
    from (select so.id from public.service_orders so where so.id = any(v_ids) order by so.id for update) t;
  if coalesce(cardinality(v_travados), 0) <> v_n then
    raise exception 'Alguma OS escolhida não existe mais. Recarregue a tela.' using errcode = 'P0002';
  end if;

  select array_agg(so.id order by so.created_at, so.id),
         array_agg(so.service_order_number order by so.created_at, so.id)
    into v_ordem, v_numeros
    from public.service_orders so where so.id = any(v_ids);

  -- 3. Principal: contato, marina, prioridade, tipo, situação, data, condições de pagamento e comissão
  if p_base is not null and not (p_base = any(v_ids)) then
    raise exception 'A OS principal precisa estar entre as escolhidas.' using errcode = '22023';
  end if;
  select so.* into v_base from public.service_orders so where so.id = coalesce(p_base, v_ordem[1]);

  -- 4. Cada origem: as regras dela (as mesmas que a leitura mostra) e depois as que comparam com a principal
  for r in select so.* from public.service_orders so where so.id = any(v_ids) order by so.created_at, so.id loop
    v_bloqueio := public._os_impedimento_para_agrupar(r.id);
    if v_bloqueio is not null then
      raise exception '%', v_bloqueio using errcode = '22023';
    end if;
    if r.client_id <> v_base.client_id then
      raise exception 'Só dá para agrupar OS do mesmo cliente (% é de outro cliente).', r.service_order_number
        using errcode = '22023';
    end if;
    if r.vessel_id <> v_base.vessel_id then
      raise exception 'Só dá para agrupar OS da mesma embarcação (% é de outra). Uma OS tem uma embarcação só.',
        r.service_order_number using errcode = '22023';
    end if;
    select c.base into v_calc_base from public.calc_so_totals(r.id) c;
    v_soma_gravada := v_soma_gravada + coalesce(r.grand_total, 0);
    v_soma_base := v_soma_base + coalesce(v_calc_base, 0);
  end loop;

  -- 5. Deslocamento: no máximo um (somar cobraria a viagem duas vezes)
  select count(*), string_agg(so.service_order_number, ', ' order by so.created_at, so.id)
    into v_qtd, v_lista
    from public.service_orders so
   where so.id = any(v_ids)
     and (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
          or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0);
  if v_qtd > 1 then
    raise exception 'Mais de uma OS tem deslocamento (%). Deixe o deslocamento em uma só antes de agrupar, para não cobrar a viagem duas vezes.',
      v_lista using errcode = '22023';
  end if;
  select so.* into v_desloc from public.service_orders so
   where so.id = any(v_ids)
     and (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
          or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0)
   limit 1;   -- nenhuma: campos nulos -> padrões abaixo

  if p_total_esperado is not null and round(p_total_esperado, 2) <> round(v_soma_gravada, 2) then
    raise exception 'As OS mudaram desde que a tela abriu (soma agora %). Feche e abra o agrupamento de novo.',
      public._agrupar_orcamentos_reais(v_soma_gravada) using errcode = '22023';
  end if;

  -- Dinheiro das origens ANTES de mover (a conferência do fim compara com o que chegou na nova)
  select coalesce(sum(x.amount), 0), count(*) into v_receb_antes, v_receb_qtd
    from public.receivables x where x.service_order_id = any(v_ids) and x.status is distinct from 'cancelled';

  -- 6. Cabeçalho da nova
  select array_agg(so.problem_description order by so.created_at, so.id),
         array_agg(so.initial_findings order by so.created_at, so.id),
         array_agg(so.diagnosis order by so.created_at, so.id),
         array_agg(so.solution_applied order by so.created_at, so.id),
         array_agg(so.extra_notes order by so.created_at, so.id),
         array_agg(so.internal_notes order by so.created_at, so.id),
         array_agg(so.technician_instructions order by so.created_at, so.id),
         array_agg(so.site_access order by so.created_at, so.id),
         array_agg(so.financial_notes order by so.created_at, so.id),
         array_agg(so.technician_notes order by so.created_at, so.id),
         array_agg(so.customer_visible_report order by so.created_at, so.id),
         sum(coalesce(so.discount_amount, 0)), sum(coalesce(so.tax_amount, 0)),
         sum(coalesce(so.subcontract_cost_total, 0)), sum(coalesce(so.estimated_hours, 0)),
         -- Rótulo do desconto em lote no PDF: só copia se for igual em todas (mesma regra do orçamento)
         case when count(distinct so.discount_services_pct) = 1
                   and (bool_and(coalesce(so.discount_amount, 0) > 0) or bool_and(coalesce(so.discount_amount, 0) = 0))
              then max(so.discount_services_pct) else 0 end,
         case when count(distinct so.discount_parts_pct) = 1
                   and (bool_and(coalesce(so.discount_amount, 0) > 0) or bool_and(coalesce(so.discount_amount, 0) = 0))
              then max(so.discount_parts_pct) else 0 end,
         case when bool_or(so.original_quote_amount is not null)
              then sum(coalesce(so.original_quote_amount, so.grand_total, 0)) end
    into t_problema, t_achados, t_diagnostico, t_solucao, t_escopo, t_interno, t_instrucoes, t_acesso, t_financeiro,
         t_notas_tec, t_relatorio,
         v_desconto, v_imposto, v_subcontrato, v_horas, v_desc_serv, v_desc_pecas, v_original
    from public.service_orders so where so.id = any(v_ids);

  select u.full_name into v_quem from public.app_users u where u.id = p_autor;

  if p_numero is not null then
    v_numero := p_numero;
  else
    v_seq := public.next_document_number()::text;            -- só depois de tudo validado
    v_numero := 'OS-' || lpad(v_seq, greatest(5, length(v_seq)), '0');
  end if;

  -- Situação = a da principal; data de atendimento = a da principal. quote_status 'approved': é OS — salvo
  -- quando a principal ainda espera o sinal (awaiting_deposit, sinal sem pagamento): a nova herda o "falta o
  -- sinal", e o sinal movido, quando pago, a aprova (handle_quote_deposit_payment olha o recebível).
  -- converted_to_os_at no INSERT: o gatilho orcamento_aprovado_ao_converter é BEFORE UPDATE, não dispara.
  v_quote_status := case
    when v_base.quote_status = 'awaiting_deposit'
         and not exists (select 1 from public.receivables x where x.service_order_id = v_base.id and x.is_deposit
                           and x.status in ('paid', 'partially_paid'))
      then 'awaiting_deposit'
    else 'approved' end;
  insert into public.service_orders (
    service_order_number, client_id, vessel_id, marina_id, requested_by_contact_id, requested_by_name,
    status, quote_status, converted_to_os_at, priority, service_type, currency,
    scheduled_start_at, scheduled_end_at,
    problem_description, initial_findings, diagnosis, solution_applied, extra_notes, internal_notes,
    technician_instructions, site_access, financial_notes, technician_notes, customer_visible_report,
    hourly_rate, estimated_hours,
    travel_distance_km, travel_cost_per_km, technician_count_for_travel, travel_hours, ferry_cost,
    travel_type, is_travel_billable, travel_cost_total,
    subcontract_cost_total, operational_cost_total, discount_amount, tax_amount,
    discount_services_pct, discount_parts_pct,
    payment_conditions, payment_condition_preset_id, payment_method, payment_method_preferred,
    card_installments, custom_payment_installments, card_fee_passthrough_enabled,
    customer_po_number, customer_buyer_name,
    commission_rate, commissioned_user_id, commissioned_person,
    quote_validity_days, quote_validity_date, original_quote_amount, created_by
  ) values (
    v_numero, v_base.client_id, v_base.vessel_id, v_base.marina_id, v_base.requested_by_contact_id, v_base.requested_by_name,
    v_base.status, v_quote_status, now(), coalesce(v_base.priority, 'normal'), v_base.service_type, coalesce(v_base.currency, 'BRL'),
    v_base.scheduled_start_at, v_base.scheduled_end_at,
    coalesce(public._agrupar_orcamentos_juntar(v_numeros, t_problema), 'OS que reúne ' || array_to_string(v_numeros, ', ')),
    public._agrupar_orcamentos_juntar(v_numeros, t_achados),
    public._agrupar_orcamentos_juntar(v_numeros, t_diagnostico),
    public._agrupar_orcamentos_juntar(v_numeros, t_solucao),
    public._agrupar_orcamentos_juntar(v_numeros, t_escopo),
    concat_ws(E'\n\n',
      'Reúne ' || array_to_string(v_numeros, ', ') || ' — agrupadas em '
        || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ' por ' || coalesce(v_quem, 'sistema')
        || '. Preços mantidos como estavam em cada OS. Situação, data, condições de pagamento e comissão vêm da '
        || v_base.service_order_number || '.',
      public._agrupar_orcamentos_juntar(v_numeros, t_interno)),
    public._agrupar_orcamentos_juntar(v_numeros, t_instrucoes),
    public._agrupar_orcamentos_juntar(v_numeros, t_acesso),
    public._agrupar_orcamentos_juntar(v_numeros, t_financeiro),
    public._agrupar_orcamentos_juntar(v_numeros, t_notas_tec),
    public._agrupar_orcamentos_juntar(v_numeros, t_relatorio),
    v_base.hourly_rate, v_horas,
    coalesce(v_desloc.travel_distance_km, 0), coalesce(v_desloc.travel_cost_per_km, 0),
    coalesce(v_desloc.technician_count_for_travel, 1), coalesce(v_desloc.travel_hours, 0), coalesce(v_desloc.ferry_cost, 0),
    coalesce(v_desloc.travel_type, 'comercial'), coalesce(v_desloc.is_travel_billable, true), coalesce(v_desloc.travel_cost_total, 0),
    v_subcontrato, 0, v_desconto, v_imposto,
    coalesce(v_desc_serv, 0), coalesce(v_desc_pecas, 0),
    v_base.payment_conditions, v_base.payment_condition_preset_id, v_base.payment_method, v_base.payment_method_preferred,
    coalesce(v_base.card_installments, 1), v_base.custom_payment_installments, false,
    v_base.customer_po_number, v_base.customer_buyer_name,
    coalesce(v_base.commission_rate, 0), v_base.commissioned_user_id, v_base.commissioned_person,
    coalesce(v_base.quote_validity_days, 15), null, v_original, p_autor
  )
  returning id into v_novo;

  -- 7. Serviços: TODAS as colunas de composição (como orçamento). Fora: execução (started/finished/elapsed,
  --    field_status — nenhuma começou). created_at em sequência explícita: as telas ordenam por created_at.
  for s in
    select x.*, o.ord
      from public.service_order_services x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.created_at nulls first, x.id
  loop
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_services (
      service_order_id, service_id, name_snapshot, description_snapshot, billing_unit_snapshot,
      quantity, unit_price_snapshot, line_total, discount_pct, discount_amount, notes,
      technician_user_id, warranty_days, warranty_months,
      service_system, service_verb, fiscal_verb, technician_instructions, created_at, updated_at
    ) values (
      v_novo, s.service_id, s.name_snapshot, s.description_snapshot, s.billing_unit_snapshot,
      s.quantity, s.unit_price_snapshot, s.line_total, s.discount_pct, s.discount_amount, s.notes,
      s.technician_user_id, s.warranty_days, s.warranty_months,
      s.service_system, s.service_verb, s.fiscal_verb, s.technician_instructions, v_ts, v_ts
    )
    returning id into v_novo_linha;
    v_mapa_serv := v_mapa_serv || jsonb_build_object(s.id::text, v_novo_linha);
    n_servicos := n_servicos + 1;
  end loop;

  -- 8. Peças: idem + source e o vínculo peça->serviço (kit) remapeado para a linha nova
  for pc in
    select x.*, o.ord
      from public.service_order_parts x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.created_at nulls first, x.id
  loop
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_parts (
      service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, currency_snapshot,
      line_total_cost, line_total_sale, discount_pct, discount_amount, notes,
      warranty_days, warranty_months, serial_number, source, service_order_service_id, created_at, updated_at
    ) values (
      v_novo, pc.product_id, pc.quantity, pc.unit_cost_snapshot, pc.unit_sale_snapshot, pc.currency_snapshot,
      pc.line_total_cost, pc.line_total_sale, pc.discount_pct, pc.discount_amount, pc.notes,
      pc.warranty_days, pc.warranty_months, pc.serial_number, pc.source,
      nullif(v_mapa_serv ->> (pc.service_order_service_id::text), '')::uuid, v_ts, v_ts
    )
    returning id into v_novo_linha;
    v_mapa_peca := v_mapa_peca || jsonb_build_object(pc.id::text, v_novo_linha);
    n_pecas := n_pecas + 1;
  end loop;

  -- 9. Passos de roteiro (todos pendentes: o _os_execucao_iniciada garantiu). Copiados com o serviço
  --    remapeado; seq renumerado em sequência (a ordem de cada OS, uma depois da outra).
  for st in
    select x.*, o.ord
      from public.service_order_steps x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.seq, x.created_at, x.id
  loop
    n_passos := n_passos + 1;
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_steps (
      service_order_id, service_order_service_id, template_id, seq, block, title, detail, kind, mode,
      standard_minutes, is_killer, requires_photo, requires_measure, measure_unit, status, assigned_user_id,
      origin, ai_confidence, ai_source, approved_by, approved_at, notes, block_key, block_note, created_at, updated_at
    ) values (
      v_novo, nullif(v_mapa_serv ->> (st.service_order_service_id::text), '')::uuid, st.template_id, n_passos,
      st.block, st.title, st.detail, st.kind, st.mode,
      st.standard_minutes, st.is_killer, st.requires_photo, st.requires_measure, st.measure_unit, 'pending', st.assigned_user_id,
      st.origin, st.ai_confidence, st.ai_source, st.approved_by, st.approved_at, st.notes, st.block_key, st.block_note, v_ts, v_ts
    );
  end loop;

  -- 10. Técnicos: a união, sem repetir pessoa (a principal primeiro, depois a ordem das OS)
  insert into public.service_order_technicians (service_order_id, user_id, role_in_order)
  select distinct on (t.user_id) v_novo, t.user_id, t.role_in_order
    from public.service_order_technicians t
    join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = t.service_order_id
   order by t.user_id, (t.service_order_id = v_base.id) desc, o.ord, t.created_at
  on conflict do nothing;
  get diagnostics n_tecnicos = row_count;

  -- 11. Totais pelo banco + comissão da principal sobre o total novo (mesma fórmula do orçamento)
  perform public.recalc_so_totals(v_novo);
  update public.service_orders so
     set commission_amount = case when coalesce(so.commission_rate, 0) > 0
                                  then round(coalesce(so.grand_total, 0) * so.commission_rate / 100, 2) else 0 end
   where so.id = v_novo
  returning so.grand_total into v_total;

  -- 12. Conferência dura do total (tolerância só para o arredondamento de cada origem a 2 casas)
  if v_total is null or abs(v_total - round(v_soma_base, 2)) > 0.005 * v_n then
    raise exception 'Conferência falhou: a OS agrupada deu % e a soma das originais é %. Nada foi gravado.',
      public._agrupar_orcamentos_reais(v_total), public._agrupar_orcamentos_reais(v_soma_base);
  end if;

  -- 13. Histórico do agrupamento (o "antes" de cada origem, para o desagrupar)
  insert into public.orcamento_agrupamentos (agrupado_id, criado_por, tipo) values (v_novo, p_autor, 'os')
  returning id into v_agrupamento;
  insert into public.orcamento_agrupamento_origens (
    agrupamento_id, origem_id, ordem, numero, quote_status_antes, share_token_antes,
    cancelled_at_antes, cancellation_reason_antes, grand_total_antes, status_antes
  )
  select v_agrupamento, so.id, o.ord, so.service_order_number, so.quote_status, so.share_token,
         so.cancelled_at, so.cancellation_reason, so.grand_total, so.status
    from public.service_orders so
    join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = so.id;

  -- 14. Mover para a nova o que é dinheiro/compromisso (cada registro guardado para o desagrupar)
  n_receb := public._os_agrupar_mover(v_agrupamento, 'receivables', 'service_order_id', v_ids, v_novo,
                                      'x.status is distinct from ''cancelled''');
  n_cobr := public._os_agrupar_mover(v_agrupamento, 'collections', 'service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_receb + n_cobr;
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'bank_charges', 'service_order_id', v_ids, v_novo,
                                     'coalesce(x.status, '''') not in (''cancelled'', ''failed'')');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'bank_transactions', 'reconciled_service_order_id', v_ids, v_novo);
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'payables', 'linked_service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'purchase_orders', 'service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'quote_requests', 'service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'comprovantes', 'destino_os_id', v_ids, v_novo);
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'anotacoes_do_extrato', 'os_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelada''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'finance_review_queue', 'suggested_service_order_id', v_ids, v_novo,
                                     'x.status = ''pending''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'entity_open_loops', 'service_order_id', v_ids, v_novo,
                                     'x.status = ''open''');
  n_tarefas := public._os_agrupar_mover(v_agrupamento, 'agenda_tasks', 'related_entity_id', v_ids, v_novo,
                                     'x.related_entity_type in (''service_order'', ''quote'') and x.source <> ''automation'' '
                                     || 'and x.status in (''pending'', ''in_progress'')');
  n_movidos := n_movidos + n_tarefas;
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'agenda_suggestions', 'related_entity_id', v_ids, v_novo,
                                     'x.related_entity_type = ''service_order'' and x.status = ''pending''');
  -- Missões vivas: ativas e as que esperam a resposta do cliente (as duas seguem acompanhando a OS)
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'ai_followup_missions', 'service_order_id', v_ids, v_novo,
                                     'x.status in (''active'', ''waiting_reply'')');
  -- Lembrete de cobrança agendado (ligado a recebível) acompanha o recebível
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'whatsapp_scheduled_sends', 'service_order_id', v_ids, v_novo,
                                     'x.receivable_id is not null and x.status in (''pending'', ''processing'')');

  -- Vínculos a LINHA dos registros movidos: para a linha nova (valor_antes = a linha original)
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select v_agrupamento, 'quote_request_items', 'service_order_part_id', i.id, p.service_order_id, i.service_order_part_id
    from public.quote_request_items i
    join public.service_order_parts p on p.id = i.service_order_part_id
   where p.service_order_id = any(v_ids)
     and exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_agrupamento
                   and m.tabela = 'quote_requests' and m.registro_id = i.quote_request_id);
  update public.quote_request_items i
     set service_order_part_id = (v_mapa_peca ->> m.valor_antes::text)::uuid
    from public.os_agrupamento_movidos m
   where m.agrupamento_id = v_agrupamento and m.tabela = 'quote_request_items' and m.coluna = 'service_order_part_id'
     and m.registro_id = i.id;
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select v_agrupamento, 'quote_request_items', 'service_order_service_id', i.id, s2.service_order_id, i.service_order_service_id
    from public.quote_request_items i
    join public.service_order_services s2 on s2.id = i.service_order_service_id
   where s2.service_order_id = any(v_ids)
     and exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_agrupamento
                   and m.tabela = 'quote_requests' and m.registro_id = i.quote_request_id);
  update public.quote_request_items i
     set service_order_service_id = (v_mapa_serv ->> m.valor_antes::text)::uuid
    from public.os_agrupamento_movidos m
   where m.agrupamento_id = v_agrupamento and m.tabela = 'quote_request_items' and m.coluna = 'service_order_service_id'
     and m.registro_id = i.id;
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select v_agrupamento, 'comprovantes', 'so_part_id', c.id, p.service_order_id, c.so_part_id
    from public.comprovantes c
    join public.service_order_parts p on p.id = c.so_part_id
   where p.service_order_id = any(v_ids);
  update public.comprovantes c
     set so_part_id = (v_mapa_peca ->> m.valor_antes::text)::uuid
    from public.os_agrupamento_movidos m
   where m.agrupamento_id = v_agrupamento and m.tabela = 'comprovantes' and m.coluna = 'so_part_id'
     and m.registro_id = c.id;

  -- 14b. Saldo sem título. Alguma original já tinha conta a receber e a soma delas não cobre o total novo
  --      (OS-A com sinal pago + OS-B que seria cobrada só na conclusão): a conclusão não gera nada numa OS
  --      que já tem recebível vivo (completion-receivables), e a diferença nunca seria cobrada. Um título
  --      pendente pela diferença, vencendo na conclusão — a mesma saída do assistente quando o sinal não
  --      bate com a condição (saldo-do-sinal.ts, "saldo que some é dinheiro que ninguém cobra"). Tolerância
  --      de R$ 1 (a mesma de lá): centavos de arredondamento das parcelas não viram título. Nenhuma original
  --      com recebível: nada aqui, a conclusão gera o plano inteiro da condição.
  if v_receb_qtd > 0 and round(v_total - v_receb_antes, 2) > 1 then
    v_saldo_valor := round(v_total - v_receb_antes, 2);
    insert into public.receivables (
      client_id, service_order_id, description, issue_date, due_date, amount, balance_amount, paid_amount,
      status, is_deposit, due_on_completion, notes
    ) values (
      v_base.client_id, v_novo, 'Saldo — ' || v_numero, v_hoje,
      coalesce((v_base.scheduled_end_at at time zone 'America/Sao_Paulo')::date, v_hoje + 30),
      v_saldo_valor, v_saldo_valor, 0, 'pending', false, true,
      'Lançado ao agrupar ' || array_to_string(v_numeros, ', ') || ': as OS somavam '
        || public._agrupar_orcamentos_reais(v_total) || ' e as contas a receber delas, '
        || public._agrupar_orcamentos_reais(v_receb_antes) || '.'
    )
    returning id into v_saldo_id;
    update public.orcamento_agrupamentos g set saldo_criado_id = v_saldo_id where g.id = v_agrupamento;
  end if;

  -- 15. Auditoria (antes de mudar as origens, para guardar o "antes")
  v_motivo := 'Agrupada em ' || v_numero || ' (reúne ' || array_to_string(v_numeros, ', ') || ')';
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason,
                                triggered_by_table, triggered_by_id)
  select 'service_orders', so.id, 'cancel', coalesce(v_quem, 'sistema'),
         jsonb_build_object('status', so.status, 'quote_status', so.quote_status, 'grand_total', so.grand_total,
                            'payment_status', so.payment_status),
         jsonb_build_object('status', 'cancelled', 'merged_into_id', v_novo,
                            'merged_into_number', v_numero, 'link_publico', 'desligado'),
         v_motivo, 'service_orders', v_novo
    from public.service_orders so where so.id = any(v_ids);
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_novo, 'update', coalesce(v_quem, 'sistema'), null,
          jsonb_build_object('agrupa', to_jsonb(v_numeros), 'origens', to_jsonb(v_ordem), 'grand_total', v_total,
                             'principal', v_base.service_order_number, 'tipo', 'os',
                             'recebiveis_movidos', n_receb, 'registros_movidos', n_movidos,
                             'saldo_lancado', v_saldo_valor, 'saldo_receivable_id', v_saldo_id),
          'Criada agrupando ' || array_to_string(v_numeros, ', '));

  -- 16. Origens: histórico, link morto, apontando para a nova. Só situação/cancelamento/link/vínculo — NUNCA
  --     totais, textos ou descontos (assinatura!). A situação muda -> so_status_stock recalcula as reservas.
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  update public.service_orders so
     set status = 'cancelled',
         cancelled_at = now(),
         cancellation_reason = v_motivo,
         share_token = null,
         merged_into_id = v_novo
   where so.id = any(v_ids);
  perform set_config('marineflow.agrupar_orcamentos', '', true);

  -- 17. Envios agendados com o link antigo (sem recebível): cancelados, como no orçamento
  update public.whatsapp_scheduled_sends w
     set status = 'cancelled', last_error = 'Cancelado: OS agrupada em ' || v_numero, updated_at = now()
   where w.service_order_id = any(v_ids) and w.status in ('pending', 'processing') and w.receivable_id is null;
  get diagnostics n_envios = row_count;

  -- PÓS-MERGE: (C) a agenda (as tabelas que o agrupar não conhecia): o material das origens passa à nova com a peça/serviço
  -- copiado (os_agrupamento_movidos: o desagrupar devolve), cada origem sai do plano (os_saiu) e a data dita ao cliente
  -- passa. Erro aqui = nada é gravado (é a mesma transação).
  v_agenda := public._agrupar_os_agenda(v_agrupamento, v_ids, v_novo, v_base.id, v_numero, v_mapa_peca, v_mapa_serv, p_autor);
  -- PÓS-MERGE: fim
  -- 18. Situação de pagamento: a nova pelos recebíveis que chegaram; as origens ficaram sem nenhum
  v_pagamento := public._os_recalcular_payment_status(v_novo);
  for r in select so.* from public.service_orders so where so.id = any(v_ids) loop
    perform public._os_recalcular_payment_status(r.id);
  end loop;

  -- 19. Reserva de estoque dos produtos das linhas envolvidas (a nova reserva pela situação dela)
  if public.stock_model_v2_on() then
    for v_produto in
      select distinct p.product_id from public.service_order_parts p
       where p.service_order_id = any(v_ids || v_novo) and p.product_id is not null
    loop
      perform public.recompute_product_reservations(v_produto);
    end loop;
  end if;

  -- 20. Conferências duras do dinheiro (senão nada é gravado)
  select coalesce(sum(x.amount), 0) into v_receb_movido
    from public.receivables x
    join public.os_agrupamento_movidos m on m.registro_id = x.id and m.agrupamento_id = v_agrupamento and m.tabela = 'receivables'
   where x.service_order_id = v_novo;
  if n_receb <> v_receb_qtd or round(v_receb_movido, 2) <> round(v_receb_antes, 2) then
    raise exception 'Conferência falhou: os recebíveis das originais somavam % e chegaram % na OS agrupada. Nada foi gravado.',
      public._agrupar_orcamentos_reais(v_receb_antes), public._agrupar_orcamentos_reais(v_receb_movido);
  end if;
  if exists (select 1 from public.receivables x where x.service_order_id = any(v_ids) and x.status is distinct from 'cancelled')
     or exists (select 1 from public.collections x where x.service_order_id = any(v_ids) and x.status is distinct from 'cancelled')
     or exists (select 1 from public.bank_charges x where x.service_order_id = any(v_ids)
                  and coalesce(x.status, '') not in ('cancelled', 'failed')) then
    raise exception 'Conferência falhou: ficou recebível ou cobrança ativa numa OS original. Nada foi gravado.';
  end if;
  -- Com recebível em alguma original, os da nova cobrem o total (o saldo do 14b fecha a diferença)
  select coalesce(sum(x.amount), 0) into v_receb_nova
    from public.receivables x where x.service_order_id = v_novo and x.status is distinct from 'cancelled';
  if v_receb_qtd > 0 and v_receb_nova < v_total - 1 then
    raise exception 'Conferência falhou: as contas a receber da OS agrupada (%) não cobrem o total (%). Nada foi gravado.',
      public._agrupar_orcamentos_reais(v_receb_nova), public._agrupar_orcamentos_reais(v_total);
  end if;
  select case when coalesce(sum(x.amount), 0) = 0 then 'unpaid'
              when coalesce(sum(x.paid_amount), 0) >= sum(x.amount) then 'paid'
              when coalesce(sum(x.paid_amount), 0) > 0 then 'partially_paid'
              else 'unpaid' end
    into v_pagamento_certo
    from public.receivables x where x.service_order_id = v_novo and x.status <> 'cancelled';
  if (select so.payment_status from public.service_orders so where so.id = v_novo) is distinct from v_pagamento_certo then
    raise exception 'Conferência falhou: a situação de pagamento da OS agrupada não bate com os recebíveis. Nada foi gravado.';
  end if;

  -- 21. Avisos para a tela/assistente mostrarem depois de agrupar
  select string_agg(so.service_order_number, ', ' order by so.created_at, so.id) into v_assinadas
    from public.service_orders so
   where so.id = any(v_ids)
     and (so.signed_at is not null or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id));
  if v_assinadas is not null then
    v_avisos := v_avisos || ('As assinaturas ficaram nas OS originais (' || v_assinadas || '): a ' || v_numero
                             || ' nasce sem assinatura. Se precisar, peça ao cliente para assinar a OS nova.');
  end if;
  v_avisos := v_avisos || ('Condição de pagamento, contato e comissão vêm da ' || v_base.service_order_number
                           || '; a comissão foi recalculada sobre o total novo.');
  select string_agg(so.service_order_number, ', ' order by so.created_at, so.id) into v_lista
    from public.service_orders so
    join public.orcamento_agrupamento_origens x on x.origem_id = so.id and x.agrupamento_id = v_agrupamento
   where x.status_antes is distinct from v_base.status;
  if v_lista is not null then
    v_avisos := v_avisos || ('As OS estavam em situações diferentes: a ' || v_numero
                             || ' ficou com a situação da principal (' || v_base.service_order_number || ').');
  end if;
  select string_agg(so.service_order_number || ' (' || to_char(so.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ')',
                    ', ' order by so.created_at, so.id) into v_lista
    from public.service_orders so
   where so.id = any(v_ids) and so.id <> v_base.id and so.scheduled_start_at is not null
     and so.scheduled_start_at is distinct from v_base.scheduled_start_at;
  if v_lista is not null then
    v_avisos := v_avisos || ('Tinha atendimento marcado em outra data: ' || v_lista || '. A ' || v_numero
                             || ' ficou com a data da principal: confira a agenda.');
  end if;
  if v_saldo_id is not null then
    v_avisos := v_avisos || ('As OS somavam ' || public._agrupar_orcamentos_reais(v_total) || ', mas só '
                             || public._agrupar_orcamentos_reais(v_receb_antes) || ' tinham conta a receber: a ' || v_numero
                             || ' ganhou o recebível "Saldo — ' || v_numero || '" de ' || public._agrupar_orcamentos_reais(v_saldo_valor)
                             || ', pendente, que vence na conclusão. Confira as parcelas no financeiro.');
  end if;
  -- Chegada no barco registrada numa original: fica nela (não é copiada; ver o cabeçalho)
  select string_agg(so.service_order_number || ' ('
                    || to_char(coalesce(so.check_in_at, so.check_out_at) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || ')',
                    ', ' order by so.created_at, so.id) into v_lista
    from public.service_orders so
   where so.id = any(v_ids) and (so.check_in_at is not null or so.check_out_at is not null);
  if v_lista is not null then
    v_avisos := v_avisos || ('Já houve chegada no barco registrada em ' || v_lista || ': o registro fica na original, e a '
                             || v_numero || ' começa sem chegada registrada.');
  end if;
  -- PÓS-MERGE: (C) os avisos da agenda (o material que veio, os dias que saíram do plano, a data dita ao cliente).
  v_avisos := v_avisos || array(select jsonb_array_elements_text(coalesce(v_agenda -> 'avisos', '[]'::jsonb)));
  -- PÓS-MERGE: fim
  v_avisos := array_append(v_avisos, 'Na hora da nota: uma NFS-e cobre um tomador, um código de serviço e uma competência.');

  return jsonb_build_object(
    'service_order_id', v_novo, 'numero', v_numero, 'agrupamento_id', v_agrupamento,
    'origens', to_jsonb(v_numeros), 'principal', v_base.service_order_number,
    'servicos', n_servicos, 'pecas', n_pecas, 'passos', n_passos,
    'recebiveis_movidos', n_receb, 'cobrancas_movidas', n_cobr, 'tarefas_movidas', n_tarefas,
    'registros_movidos', n_movidos, 'tecnicos', n_tecnicos, 'envios_cancelados', n_envios,
    'total_geral', v_total, 'payment_status', v_pagamento,
    'saldo_lancado', v_saldo_valor,
    'comissao', (select so.commission_amount from public.service_orders so where so.id = v_novo),
    'avisos', to_jsonb(v_avisos));
end $$;

create or replace function public._desagrupar_os_desfazer(p_agrupado uuid, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ag public.service_orders;
  v_grupo public.orcamento_agrupamentos;
  v_bloqueio text;
  v_quem text;
  v_numeros text[];
  v_ids uuid[];
  v_qtd integer;
  v_motivo text;
  n_envios integer := 0;
  n_reativados integer := 0;
  n_devolvidos integer := 0;
  n_x integer;
  o record;
  m record;
  v_produto uuid;
  -- PÓS-MERGE: (C) a resposta da porta (o status de cada origem volta por ela).
  v_porta jsonb;
  -- PÓS-MERGE: fim
begin
  if p_autor is null then
    raise exception 'Faça login para desagrupar OS.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode desagrupar OS.' using errcode = '42501';
  end if;
  if p_agrupado is null then
    raise exception 'Escolha a OS agrupada.' using errcode = '22023';
  end if;

  select so.* into v_ag from public.service_orders so where so.id = p_agrupado for update;
  if v_ag.id is null then
    raise exception 'OS não encontrada. Recarregue a tela.' using errcode = 'P0002';
  end if;

  select g.* into v_grupo from public.orcamento_agrupamentos g
   where g.agrupado_id = p_agrupado and g.desfeito_em is null and g.tipo = 'os'
   for update;
  if v_grupo.id is null then
    raise exception '% não é uma OS agrupada (ou já foi desagrupada).', v_ag.service_order_number
      using errcode = '22023';
  end if;

  v_bloqueio := public._os_impedimento_para_desagrupar(p_agrupado);
  if v_bloqueio is not null then
    raise exception '%', v_bloqueio using errcode = '22023';
  end if;

  -- Trava as origens (mesma ordem do agrupar) e confere que seguem presas a esta agrupada
  select array_agg(t.id) into v_ids
    from (select so.id from public.service_orders so
            join public.orcamento_agrupamento_origens x on x.origem_id = so.id and x.agrupamento_id = v_grupo.id
           order by so.id for update of so) t;
  select count(*) into v_qtd from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  if coalesce(cardinality(v_ids), 0) <> v_qtd or v_qtd = 0 then
    raise exception 'Alguma OS original deste agrupamento não existe mais. Nada foi desfeito.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.service_orders so where so.id = any(v_ids)
              and (so.merged_into_id is distinct from v_ag.id or so.status <> 'cancelled')) then
    raise exception 'As originais de % não estão mais como o agrupamento deixou. Nada foi desfeito.',
      v_ag.service_order_number using errcode = '22023';
  end if;

  select array_agg(x.numero order by x.ordem) into v_numeros
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  select u.full_name into v_quem from public.app_users u where u.id = p_autor;
  v_motivo := 'Desagrupada em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
           || ' por ' || coalesce(v_quem, 'sistema') || ': voltaram a valer ' || array_to_string(v_numeros, ', ');

  -- Auditoria antes de mexer (guarda o "antes")
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason,
                                triggered_by_table, triggered_by_id)
  select 'service_orders', x.origem_id, 'reopen', coalesce(v_quem, 'sistema'),
         jsonb_build_object('status', 'cancelled', 'merged_into_id', v_ag.id, 'merged_into_number', v_ag.service_order_number),
         jsonb_build_object('status', x.status_antes, 'quote_status', x.quote_status_antes, 'link_publico', 'religado'),
         'Desagrupada de ' || v_ag.service_order_number, 'service_orders', v_ag.id
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_ag.id, 'cancel', coalesce(v_quem, 'sistema'),
          jsonb_build_object('status', v_ag.status, 'quote_status', v_ag.quote_status, 'grand_total', v_ag.grand_total),
          jsonb_build_object('status', 'cancelled', 'desagrupado', to_jsonb(v_numeros), 'link_publico', 'desligado'),
          v_motivo);

  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  -- Origens PRIMEIRO (limpar merged_into_id): a guarda do recebível recusa recebível em origem agrupada
  for o in select x.* from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id order by x.ordem loop
    update public.service_orders so
       set
           -- PÓS-MERGE: (C) o status não muda aqui: volta pela porta única (os_transicionar_status, via desagrupar), logo depois
           -- deste laço, com a OS já fora do agrupamento.
           -- PÓS-MERGE: fim
           quote_status = o.quote_status_antes,
           cancelled_at = o.cancelled_at_antes,
           cancellation_reason = o.cancellation_reason_antes,
           share_token = coalesce(o.share_token_antes, gen_random_uuid()),
           merged_into_id = null
     where so.id = o.origem_id;
  end loop;
  -- PÓS-MERGE: (C) o status de antes de cada origem volta pela porta única (via desagrupar, só com a chave desta OS); a porta
  -- recusar = nada é desfeito.
  for o in select x.* from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id order by x.ordem loop
    perform set_config('marineflow.desagrupar_os', o.origem_id::text, true);
    v_porta := public.os_transicionar_status(o.origem_id, coalesce(o.status_antes, 'approved'), 'desagrupar', null, p_autor);
    perform set_config('marineflow.desagrupar_os', '', true);
    if not coalesce((v_porta ->> 'ok')::boolean, false) then
      raise exception 'A porta do status não devolveu a % (%). Nada foi desfeito.', o.numero, coalesce(v_porta ->> 'texto', '?')
        using errcode = '22023';
    end if;
  end loop;
  -- PÓS-MERGE: fim

  -- Cada registro movido volta à sua OS (só se ainda está na agrupada; vínculo a linha volta à linha original)
  for m in select x.* from public.os_agrupamento_movidos x where x.agrupamento_id = v_grupo.id
            order by x.tabela, x.coluna, x.registro_id loop
    if m.valor_antes is not null then
      execute format('update public.%I x set %I = $1 where x.id = $2', m.tabela, m.coluna)
        using m.valor_antes, m.registro_id;
    else
      execute format('update public.%I x set %I = $1 where x.id = $2 and x.%I = $3', m.tabela, m.coluna, m.coluna)
        using m.origem_id, m.registro_id, v_ag.id;
    end if;
    get diagnostics n_x = row_count;
    n_devolvidos := n_devolvidos + n_x;
  end loop;

  -- Lançamento do extrato conciliado na agrupada DEPOIS de agrupar, pagando um recebível que acabou de voltar
  -- (o Pix do saldo conciliado na OS-N): segue o recebível — senão o extrato diria "conciliado com a OS-N
  -- (cancelada)". O impedimento já garantiu que os demais lançamentos conciliados na agrupada vieram das origens.
  update public.bank_transactions t
     set reconciled_service_order_id = r.service_order_id
    from public.payments p
    join public.receivables r on r.id = p.receivable_id
   where (t.reconciled_payment_id = p.id or p.bank_transaction_id = t.id)
     and t.reconciled_service_order_id = v_ag.id
     and r.service_order_id is not null and r.service_order_id <> v_ag.id;
  get diagnostics n_x = row_count;
  n_devolvidos := n_devolvidos + n_x;

  -- Origem que esperava o sinal (awaiting_deposit) e cujo sinal, movido, foi pago na agrupada: o gatilho
  -- handle_quote_deposit_payment só age quando o recebível MUDA de situação, então quem acerta é aqui.
  update public.service_orders so
     set quote_status = 'approved'
   where so.id = any(v_ids) and so.quote_status = 'awaiting_deposit'
     and exists (select 1 from public.receivables x where x.service_order_id = so.id and x.is_deposit
                   and x.status in ('paid', 'partially_paid'));

  -- O saldo que o agrupar lançou não tem original: cancelado (o impedimento garantiu que nada foi pago nele)
  if v_grupo.saldo_criado_id is not null then
    update public.receivables x
       set status = 'cancelled',
           notes = concat_ws(E'\n', x.notes, 'Cancelado: ' || v_ag.service_order_number || ' desagrupada.')
     where x.id = v_grupo.saldo_criado_id and x.status is distinct from 'cancelled';
  end if;

  -- Agrupada: cancelada como histórico, link desligado (a guarda da agrupada deixa passar só aqui)
  update public.service_orders so
     set status = 'cancelled',
         cancelled_at = now(),
         cancellation_reason = v_motivo,
         share_token = null
   where so.id = v_ag.id;
  -- PÓS-MERGE: (C) a agenda: a agrupada sai do plano como as originais saíram no agrupar (os_saiu); o material volta com os
  -- outros registros movidos (o laço acima) e as originais entram no próximo planejamento.
  perform public._agenda_os_saiu_por_agrupar(v_ag.id, null,
    format('Tirei do plano a %s, desagrupada (voltaram a valer %s): saíram {dias}. As originais entram no próximo planejamento.',
           v_ag.service_order_number, array_to_string(v_numeros, ', ')), p_autor);
  -- PÓS-MERGE: fim
  perform set_config('marineflow.agrupar_orcamentos', '', true);

  -- Totais das origens pelo banco (alguém pode ter mexido numa linha enquanto estavam canceladas; numa
  -- original assinada, só um total que MUDOU de fato supera a assinatura — e aí ela tem mesmo de ser refeita)
  for o in select x.origem_id from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id loop
    perform public.recalc_so_totals(o.origem_id);
    perform public._os_recalcular_payment_status(o.origem_id);
  end loop;
  perform public._os_recalcular_payment_status(v_ag.id);

  if public.stock_model_v2_on() then
    for v_produto in
      select distinct p.product_id from public.service_order_parts p
       where p.service_order_id = any(v_ids || v_ag.id) and p.product_id is not null
    loop
      perform public.recompute_product_reservations(v_produto);
    end loop;
  end if;

  -- Envios agendados das origens que o agrupar cancelou voltam (o link voltou), se a hora ainda não passou
  update public.whatsapp_scheduled_sends w
     set status = 'pending', last_error = null, updated_at = now()
   where w.service_order_id = any(v_ids) and w.status = 'cancelled'
     and w.last_error = 'Cancelado: OS agrupada em ' || v_ag.service_order_number
     and w.next_run_at > now();
  get diagnostics n_reativados = row_count;

  -- Lembrete de cobrança criado na agrupada DEPOIS de agrupar para um recebível que voltou: acompanha o
  -- recebível (o cliente continua sendo cobrado). Os de link da agrupada, e os do saldo cancelado, morrem.
  update public.whatsapp_scheduled_sends w
     set service_order_id = r.service_order_id, updated_at = now()
    from public.receivables r
   where w.receivable_id = r.id and w.service_order_id = v_ag.id
     and w.status in ('pending', 'processing')
     and r.service_order_id is not null and r.service_order_id <> v_ag.id
     and r.status is distinct from 'cancelled';
  get diagnostics n_x = row_count;
  n_devolvidos := n_devolvidos + n_x;

  update public.whatsapp_scheduled_sends w
     set status = 'cancelled', last_error = 'Cancelado: OS desagrupada', updated_at = now()
   where w.service_order_id = v_ag.id and w.status in ('pending', 'processing');
  get diagnostics n_envios = row_count;

  update public.orcamento_agrupamentos g
     set desfeito_em = now(), desfeito_por = p_autor
   where g.id = v_grupo.id;

  return jsonb_build_object(
    'agrupado_id', v_ag.id, 'agrupado', v_ag.service_order_number,
    'origens', to_jsonb(v_numeros), 'origens_ids', (select to_jsonb(array_agg(x.origem_id order by x.ordem))
                                                      from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id),
    'registros_devolvidos', n_devolvidos,
    'envios_cancelados', n_envios, 'envios_reativados', n_reativados);
end $$;

-- ── 4. Portas: as novas sem grant (só as definer chamam); as recriadas com as mesmas de antes ────────────────
revoke all on function public._os_agenda_execucao(uuid) from public, anon, authenticated;
revoke all on function public._agenda_os_saiu_por_agrupar(uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public._agrupar_os_agenda(uuid, uuid[], uuid, uuid, text, jsonb, jsonb, uuid) from public, anon, authenticated;
revoke all on function public._os_porta_desagrupar(uuid, text, uuid, date, timestamptz) from public, anon, authenticated;
revoke all on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  to authenticated, service_role;
revoke all on function public._os_impedimento_para_agrupar(uuid) from public, anon, authenticated;
revoke all on function public._os_impedimento_para_desagrupar(uuid) from public, anon, authenticated;
revoke all on function public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public._desagrupar_os_desfazer(uuid, uuid) from public, anon, authenticated;
grant execute on function public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric) to service_role;
grant execute on function public._desagrupar_os_desfazer(uuid, uuid) to service_role;
