-- Agenda de Produção — "A OS-X terminou ou falta dia?" (23/11/2026, NOVO-testes-01, opção A do dono).
--
-- Decisão do dono (23/11, resposta "a"): o sistema pergunta, de manhã, "A OS-X terminou ou falta dia?" para toda OS em execução cujo plano já foi
-- cumprido e que não tem dia futuro. Plano e cartões: D:/IA-HBR/Trabalho/terminou-ou-falta-dia/PLANO.md.
--
-- Por quê (medido 21–23/11, só leitura): a OS-00136 (Jorge, in_progress desde 17/11) teve um só meio-dia, qui 19/11 à tarde, do próprio dono, sem
-- resultado. A conferência daquele dia ("Foi isso? Responda *dia feito*") nunca foi mostrada; a pergunta concluir só nasce para a EQUIPE (o "terminei"
-- do "como foi"); a reavaliar (diagnóstico feito) espera o resultado do dia. Ninguém pergunta, e agenda_saude().gestor.aprovada_sem_data = 1 derruba o
-- ok (o contador só olhava service_order_id; a conferência tem a OS só em os_ids). Hoje entra só a OS-00136.
--
-- O que muda (o mínimo; reaproveita o que existe):
--   1. _agenda_terminou_candidatas (nova, stable): quem entra — in_progress, um meio-dia antes de hoje não "nao_cumprido", nada publicado/fixado de
--      hoje em diante, agenda_meios_da_os.passos = 0 (o plano acabou), sem pergunta concluir aberta da OS. O dia do dono entra.
--   2. _agenda_terminou_rodar (nova): no passo conclusao da rotina de 15 min, a pergunta tipo concluir (já no CHECK) de chave terminou:<os> (1 por OS
--      pelo índice único), sem prazo e sem opções: "A OS-00136 (Jorge) terminou ou falta dia? Responda *concluiu OS-00136* ou *falta dia OS-00136*."
--      Fecha a que não vale mais (a OS saiu de em andamento, voltou a ter dia, ou o motor voltou a ter o que encaixar).
--   3. _agenda_terminou_da_manha (nova) e agenda_aprovacoes_da_manha recriada (corpo de PRODUÇÃO + blocos "-- TERMINOU:"): a pergunta entra no resumo da
--      manhã pelo MESMO caminho da Opção A (20270128100000): o edge guarda as perguntas de linhas[] com via 'manha' e elas contam quando a fila disser
--      'sent'. O bloco do cliente fica byte a byte; o "terminou?" vem depois. Nada vence: sem resposta, volta na manhã seguinte. O edge não muda.
--   4. Respostas por texto (sem botão): "terminou" = a palavra que já existe, *concluiu OS-00136* (agenda_concluir_dito → a porta: o dono pode concluir
--      pelo WhatsApp; a pergunta fecha no tique seguinte). "falta dia" = palavra nova *falta dia [<alvo>]* → agenda_falta_dia_dito (nova): o último dia
--      da OS "andou em parte (estimativa)" só dela (agenda_registrar_dia com p_os — o caminho do *dia parcial estimativa*), o motor encaixa o que falta
--      na mesma transação, e a pergunta fecha. A palavra está em _shared/agenda/comandos.ts e executar.ts (ai-agent e whatsapp-webhook).
--   5. _agenda_rotina_conclusao recriada (corpo de PRODUÇÃO + blocos "-- TERMINOU:"): chama _agenda_terminou_rodar num begin/exception próprio.
--   6. agenda_saude recriada (corpo de PRODUÇÃO + 1 bloco "-- TERMINOU:"): aprovada_sem_data enxerga a pergunta aberta também por os_ids.
-- Os corpos recriados: tirados os blocos "-- TERMINOU: … -- TERMINOU: fim" e devolvidas as linhas "--antes:" de dentro deles, o md5 sem CR volta a ser o
-- de produção de 23/11 (agenda_aprovacoes_da_manha 2b1ce097…, _agenda_rotina_conclusao ff5397d8…, agenda_saude cd5841fe…).
--
-- Nenhuma tabela, coluna, CHECK, modo ou cron novo. Nenhuma mensagem nova ao cliente.
-- DESFAZER: recriar agenda_aprovacoes_da_manha de 20270128100000, _agenda_rotina_conclusao de 20261102100550 e agenda_saude de 20261112100500 (os
-- corpos de antes); drop function public.agenda_falta_dia_dito(uuid, text, text, date, timestamptz), public._agenda_terminou_da_manha(jsonb, date,
-- timestamptz), public._agenda_terminou_rodar(date, timestamptz), public._agenda_terminou_candidatas(date); fechar as perguntas abertas
-- (update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'desfeito' where estado = 'aberta' and chave like 'terminou:%').


-- ── 1. Quem entra ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- A OS em execução (in_progress, não juntada) cujo plano acabou: ao menos um meio-dia (não reserva, publicado ou fixado) antes de hoje que
-- não foi "não cumprido"; nada publicado ou fixado de hoje em diante (o mesmo filtro do aprovada_sem_data da saúde); o motor sem o que
-- encaixar (agenda_meios_da_os.passos = 0); e sem pergunta concluir aberta da OS (a "terminou?" dela ou a da equipe). O dia do dono entra
-- (nenhum filtro de pessoa). O último dia é o maior desses meios-dias.
create or replace function public._agenda_terminou_candidatas(p_hoje date)
 returns table(service_order_id uuid, numero text, curto text, ultimo_dia date)
 language sql
 stable
 set search_path to 'public'
as $function$
  select so.id, so.service_order_number,
         coalesce(public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)), so.service_order_number),
         u.ultimo
    from public.service_orders so
    left join public.clients cl on cl.id = so.client_id
    cross join lateral (select max(a.dia) as ultimo from public.agenda_alocacoes a
                         where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                           and a.dia < p_hoje and a.resultado is distinct from 'nao_cumprido') u
   where so.status = 'in_progress' and so.merged_into_id is null
     and u.ultimo is not null
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
     and not exists (select 1 from public.agenda_perguntas q
                      where q.estado = 'aberta' and q.tipo = 'concluir' and q.service_order_id = so.id)
     and coalesce((public.agenda_meios_da_os(so.id, p_hoje) ->> 'passos')::int, 0) = 0
   order by so.service_order_number collate "C", so.id;
$function$;

comment on function public._agenda_terminou_candidatas(date) is
  'Agenda de Produção, "terminou ou falta dia?" (23/11/2026, NOVO-testes-01, opção A do dono; 20270223100000): as OS que ganham a pergunta — status in_progress, não juntada, com ao menos um meio-dia (não reserva, publicada/fixada) antes de p_hoje e não "nao_cumprido", sem alocação publicada/fixada sem resultado de p_hoje em diante, agenda_meios_da_os(...).passos = 0 (o plano acabou) e sem pergunta concluir aberta da OS (a dela ou a da equipe). {service_order_id, numero, curto (o nome curto do cliente), ultimo_dia}. Só lê. Invoker, sem grant: só _agenda_terminou_rodar a chama.';

-- ── 2. Abre e fecha a pergunta (o passo "conclusao" da rotina de 15 min) ───────────────────────────────────────────────────────────────
-- Abre, com o motor ligado (a resposta *falta dia* replaneja), uma pergunta concluir por OS candidata, de chave terminou:<os>, em ligado,
-- sem prazo, sem opções, não crítica, com a OS em service_order_id e os_ids e o último dia em dia. Fecha (resolvida, com o motivo) a
-- "terminou?" aberta que não vale mais: a OS saiu de em andamento (concluída: a limpeza da vigia também fecha), voltou a ter dia no plano,
-- ou o motor voltou a ter o que encaixar.
create or replace function public._agenda_terminou_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  r       record;
  v_st    text;
  v_mot   text;
  v_n     int;
  v_abre  int := 0;
  v_fecha int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_terminou_rodar: sem o dia ou a hora.' using errcode = '22004';
  end if;
  for r in select q.id, q.service_order_id as os from public.agenda_perguntas q
            where q.estado = 'aberta' and q.tipo = 'concluir' and q.chave like 'terminou:%'
            order by q.criada_em, q.id loop
    select so.status into v_st from public.service_orders so where so.id = r.os;
    v_mot := case
      when v_st is null then 'a OS não existe mais'
      when v_st in ('completed', 'invoiced') then 'a OS foi concluída'
      when v_st <> 'in_progress' then 'a OS não está mais em andamento'
      when exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = r.os and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
        then 'a OS voltou a ter dia no plano'
      when coalesce((public.agenda_meios_da_os(r.os, p_hoje) ->> 'passos')::int, 0) > 0 then 'a agenda voltou a ter o que marcar'
    end;
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200)
       where id = r.id and estado = 'aberta';
      get diagnostics v_n = row_count;
      v_fecha := v_fecha + v_n;
    end if;
  end loop;
  if cf.modo_proposta = 'ligado' then
    for r in select * from public._agenda_terminou_candidatas(p_hoje) loop
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, texto, opcoes, modo, criada_em)
      values ('concluir', 'terminou:' || r.service_order_id, r.service_order_id, array[r.service_order_id], r.ultimo_dia,
              left(format('A %s (%s) terminou ou falta dia? Responda *concluiu %s* ou *falta dia %s*.',
                          r.numero, r.curto, r.numero, r.numero), 600),
              '[]'::jsonb, 'ligado', p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
      get diagnostics v_n = row_count;
      v_abre := v_abre + v_n;
    end loop;
  end if;
  return jsonb_build_object('abertas', v_abre, 'fechadas', v_fecha);
end;
$function$;

comment on function public._agenda_terminou_rodar(date, timestamptz) is
  'Agenda de Produção, "terminou ou falta dia?" (23/11/2026; 20270223100000): no passo conclusao da rotina de 15 min (_agenda_rotina_conclusao, num begin/exception próprio). Fecha (resolvida, com o motivo) a pergunta concluir terminou:<os> aberta cuja OS não está mais em andamento (concluída, faturada, outro status), voltou a ter dia publicado/fixado de p_hoje em diante ou voltou a ter o que o motor encaixar (passos > 0). Com modo_proposta ligado, abre uma por OS de _agenda_terminou_candidatas: tipo concluir, chave terminou:<os>, ligado, sem prazo (expira_em e veto_ate nulos), sem opções, não crítica, service_order_id e os_ids = a OS, dia = o último dia; texto "A OS-00136 (Jorge) terminou ou falta dia? Responda *concluiu OS-00136* ou *falta dia OS-00136*.". {abertas, fechadas}. Invoker, sem grant.';

-- ── 3. As linhas da manhã ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Junta ao que agenda_aprovacoes_da_manha montou (o bloco do cliente, ou o vazio) as perguntas "terminou?" abertas em ligado de OS ainda em
-- andamento, a mais antiga primeiro, 1 linha por OS (a chave garante). Cabem as linhas que sobram de 5 (o limite do bloco), nunca menos
-- de 1; o resto, "e mais N (voltam amanhã)". Sem pergunta, devolve p_cli como veio (byte a byte). As perguntas escritas entram em linhas[]
-- ({pergunta_id, os, texto}): o edge as guarda com via 'manha' e elas contam quando a fila disser 'sent'. Nada vence: sem resposta, a
-- pergunta continua aberta e volta na manhã seguinte.
create or replace function public._agenda_terminou_da_manha(p_cli jsonb, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_max    constant int := 5;
  v_cabe   int;
  r        record;
  v_txt    text[] := '{}';
  v_linhas jsonb := '[]'::jsonb;
  v_total  int := 0;
  v_linha  text;
  v_bloco  text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_terminou_da_manha: sem o dia ou a hora.' using errcode = '22004';
  end if;
  v_cabe := greatest(c_max - coalesce(jsonb_array_length(case when jsonb_typeof(p_cli -> 'linhas') = 'array' then p_cli -> 'linhas' end), 0), 1);
  for r in
    select q.id, q.texto, so.id as os, so.service_order_number as numero,
           coalesce(public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)), so.service_order_number) as curto,
           count(*) over () as n
      from public.agenda_perguntas q
      join public.service_orders so on so.id = q.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo = 'concluir' and q.chave like 'terminou:%'
       and so.status = 'in_progress' and q.criada_em <= p_agora
     order by q.criada_em, so.service_order_number collate "C", q.id
  loop
    v_total := r.n;
    exit when cardinality(v_txt) >= v_cabe;
    v_linha := format('%s (%s): *concluiu %s* ou *falta dia %s*', r.numero, r.curto, r.numero, r.numero);
    v_txt := v_txt || case when r.n = 1 then r.texto else v_linha end;
    v_linhas := v_linhas || jsonb_build_object('pergunta_id', r.id, 'os', r.os, 'texto', case when r.n = 1 then r.texto else v_linha end);
  end loop;
  if v_total = 0 then
    return p_cli;
  end if;
  v_bloco := case when v_total = 1 then '🔧 ' || v_txt[1]
                  else '🔧 Terminou ou falta dia?' || E'\n' || array_to_string(array(select '• ' || t from unnest(v_txt) t), E'\n')
                       || case when v_total > cardinality(v_txt)
                               then format(E'\n• e mais %s (voltam amanhã)', v_total - cardinality(v_txt)) else '' end end;
  return coalesce(p_cli, '{}'::jsonb)
         || jsonb_build_object(
              'texto', case when nullif(btrim(coalesce(p_cli ->> 'texto', '')), '') is null then v_bloco
                            else (p_cli ->> 'texto') || E'\n\n' || v_bloco end,
              'linhas', coalesce(case when jsonb_typeof(p_cli -> 'linhas') = 'array' then p_cli -> 'linhas' end, '[]'::jsonb) || v_linhas,
              'terminou', jsonb_build_object('total', v_total, 'escritas', cardinality(v_txt)));
end;
$function$;

comment on function public._agenda_terminou_da_manha(jsonb, date, timestamptz) is
  'Agenda de Produção, "terminou ou falta dia?" (23/11/2026; 20270223100000): o pedaço da manhã. Recebe o que agenda_aprovacoes_da_manha montou ({total, linhas, texto}) e junta as perguntas concluir terminou:<os> abertas em ligado de OS in_progress, a mais antiga primeiro: 1 só = "🔧 " + o texto da pergunta; mais = "🔧 Terminou ou falta dia?" e "• OS-00136 (Jorge): *concluiu OS-00136* ou *falta dia OS-00136*" por OS. Cabem 5 menos as linhas do cliente, nunca menos de 1; o resto "• e mais N (voltam amanhã)". O texto vai depois do bloco do cliente (uma linha em branco); as perguntas escritas vão para linhas[] ({pergunta_id, os, texto}); terminou = {total, escritas}. Sem pergunta, p_cli como veio. Só lê. Invoker, sem grant (a chamadora é definer).';

-- ── 4. A palavra *falta dia [<alvo>]* ──────────────────────────────────────────────────────────────────────────────────────────────────
-- O caminho que o código já usa para "precisa de mais": o último dia da OS andou em parte pela estimativa (agenda_registrar_dia só dela,
-- via dia_feito, como o *dia parcial estimativa*), e o motor encaixa o que falta na mesma transação (agenda_replanejar). A pergunta
-- "terminou?" da OS fecha (respondida). Sem alvo = a única "terminou?" aberta. O nome que não acha OS (nao_achei) segue ao modelo.
create or replace function public.agenda_falta_dia_dito(p_autor uuid, p_alvo text default null, p_canal text default 'whatsapp',
                                                     p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_alvo  text := nullif(btrim(coalesce(p_alvo, '')), '');
  v_ro    jsonb;
  v_ids   uuid[];
  v_os    uuid;
  v_st    text;
  v_rot   text;
  v_curto text;
  v_fut   date[];
  v_dia   date;
  v_r     jsonb;
  v_n     int;
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_falta_dia_dito: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_falta_dia_dito: sem o dia ou a hora.' using errcode = '22004';
  end if;
  if cf.modo_proposta is distinct from 'ligado' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'em_teste',
                              'texto', 'A agenda automática ainda está em teste: nada mudou.');
  end if;

  if v_alvo is null then
    select coalesce(array_agg(q.service_order_id order by q.criada_em, q.id), '{}') into v_ids
      from public.agenda_perguntas q
     where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo = 'concluir' and q.chave like 'terminou:%';
    if cardinality(v_ids) = 0 then
      return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nenhuma',
        'texto', 'Não tenho pergunta "terminou ou falta dia?" aberta. Diga *falta dia* e o número da OS (ex.: *falta dia OS-00136*).');
    end if;
    if cardinality(v_ids) > 1 then
      return jsonb_build_object('ok', false, 'mudou', false, 'status', 'ambiguo',
        'opcoes', (select jsonb_agg(public._agenda_rotulo_da_os(x) order by o) from unnest(v_ids) with ordinality u(x, o)),
        'texto', format('Qual? %s. Diga *falta dia %s*.',
                        (select string_agg(public._agenda_rotulo_da_os(x), ' ou ' order by o) from unnest(v_ids) with ordinality u(x, o)),
                        (select so.service_order_number from public.service_orders so where so.id = v_ids[1])));
    end if;
    v_os := v_ids[1];
  else
    v_ro := public.agenda_resolver_os(v_alvo, p_hoje, false);
    if v_ro ->> 'status' = 'fora_da_carteira' and v_ro ->> 'situacao' in ('completed', 'invoiced') then
      return jsonb_build_object('ok', true, 'mudou', false, 'status', 'ja_concluida',
        'texto', format('%s (%s) já está %s: nada mudou.', v_ro ->> 'cliente_curto', v_ro ->> 'numero',
                        public._agenda_status_texto(v_ro ->> 'situacao')));
    end if;
    if v_ro ->> 'status' <> 'ok' then
      -- nao_achei: o turno segue ao modelo ("falta dia de chuva" não é de OS nenhuma)
      return jsonb_build_object('ok', false, 'mudou', false, 'status', v_ro ->> 'status', 'texto', v_ro ->> 'texto',
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    v_os := (v_ro ->> 'id')::uuid;
  end if;

  v_rot := public._agenda_rotulo_da_os(v_os);
  select so.status, coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_st, v_curto
    from public.service_orders so left join public.clients cl on cl.id = so.client_id where so.id = v_os;
  if v_st is distinct from 'in_progress' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'fora_de_andamento',
      'texto', format('%s não está em andamento (%s): nada mudou.', v_rot, public._agenda_status_texto(v_st)));
  end if;
  v_fut := array(select distinct a.dia from public.agenda_alocacoes a
                  where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    and a.dia >= p_hoje and a.resultado is null order by 1);
  if cardinality(v_fut) > 0 then
    return jsonb_build_object('ok', true, 'mudou', false, 'status', 'tem_dia',
      'texto', format('%s já tem dia no plano (%s): nada mudou. Se precisar de mais, diga quantos dias (ex.: "%s precisa de mais 2 dias").',
                      v_rot, public._agenda_dias_texto(v_fut), v_curto));
  end if;
  select max(a.dia) into v_dia from public.agenda_alocacoes a
   where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
     and a.dia < p_hoje and a.resultado is distinct from 'nao_cumprido';
  if v_dia is null then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'sem_dia',
      'texto', format('%s não tem dia passado no plano: diga quantos dias faltam (ex.: "%s precisa de 2 dias").', v_rot, v_curto));
  end if;

  v_r := public.agenda_registrar_dia(v_autor, v_dia, 'parcial', 'estimativa', v_os, null, 'dia_feito',
                                     left('falta dia' || coalesce(' ' || v_alvo, ''), 300), p_hoje, p_agora, p_canal);
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    return v_r || jsonb_build_object('status', 'recusada');
  end if;
  update public.agenda_perguntas
     set estado = 'respondida', respondida_em = p_agora, respondida_por = v_autor, respondida_via = p_canal,
         resposta = left('falta dia' || coalesce(' ' || v_alvo, ''), 500)
   where estado = 'aberta' and tipo = 'concluir' and chave = 'terminou:' || v_os;
  get diagnostics v_n = row_count;
  return v_r || jsonb_build_object('status', 'ok', 'os', v_os, 'dia', v_dia, 'pergunta', v_n,
    'texto', left(coalesce(v_r ->> 'texto', format('Anotei: falta dia em %s.', v_rot))
                  || format(' Se faltar mais de meio dia, diga quantos (ex.: "%s precisa de mais 2 dias").', v_curto), 600));
end;
$function$;

comment on function public.agenda_falta_dia_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção, "terminou ou falta dia?" (23/11/2026; 20270223100000): a palavra *falta dia [<alvo>]* do dono (WhatsApp ou painel; só o administrador, pelo _autor_da_agenda). Com modo_proposta ligado: resolve a OS (alvo pelo agenda_resolver_os; sem alvo, a única pergunta terminou:<os> aberta — nenhuma ou mais de uma = a frase, nada muda); só OS in_progress, sem dia de hoje em diante (senão "já tem dia", nada muda); o último dia passado (não "nao_cumprido") vira "andou em parte (estimativa)" só dela (agenda_registrar_dia com p_os, via dia_feito: o caminho do *dia parcial estimativa*) — o motor encaixa o que falta na mesma transação (agenda_replanejar) — e a pergunta terminou:<os> aberta fica respondida. {ok, mudou, status: ok|em_teste|nenhuma|ambiguo|nao_achei|ja_concluida|fora_de_andamento|tem_dia|sem_dia|recusada, texto, ...a resposta de agenda_registrar_dia}. nao_achei com alvo: o edge segue ao modelo. Definer; authenticated e service_role.';

-- ── 5. agenda_aprovacoes_da_manha (corpo de PRODUÇÃO + blocos TERMINOU) ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.agenda_aprovacoes_da_manha(p_hoje date DEFAULT _hoje_brt(), p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  c_max    constant int := 5;
  r        record;
  v_linhas jsonb := '[]'::jsonb;
  v_txt    text[] := '{}';
  v_total  int := 0;
  v_nomes  text[] := '{}';
  v_nome   text;
  v_dia    date;
  v_hora   text;
  v_vence  text;
  v_oque   text;
  v_linha  text;
  v_bloco  text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aprovacoes_da_manha: sem o dia ou a hora.' using errcode = '22004';
  end if;
  if cf.modo_cliente is distinct from 'ligado' then
    -- TERMINOU: (23/11/2026) sem o bloco do cliente, o "terminou ou falta dia?" ainda entra (_agenda_terminou_da_manha). A linha de antes, em "--antes:".
--antes:    return jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null);
    return public._agenda_terminou_da_manha(jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), p_hoje, p_agora);
    -- TERMINOU: fim
  end if;
  for r in
    with base as (
      select m.id as msg, q.id as pergunta_id, m.client_id, m.tipo, m.enviar_em,
             coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
             least(m.valida_ate, coalesce(q.expira_em, m.valida_ate)) as vence,
             public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as curto,
             coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name) as completo,
             cl.name as ordem_nome, so.service_order_number as os_num
        from public.agenda_cliente_mensagens m
        join public.agenda_perguntas q on q.id = m.pergunta_id
        join public.clients cl on cl.id = m.client_id
        left join public.service_orders so on so.id = m.service_order_id
       where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
         and q.tipo = 'cliente_aprovar' and q.estado = 'aberta' and q.modo = 'ligado'
         and m.valida_ate > p_agora and (q.expira_em is null or q.expira_em > p_agora)
    ), mesmo_nome as (
      select public._agenda_normal(b.curto) as chave from base b group by 1 having count(distinct b.client_id) > 1
    )
    select b.*, (public._agenda_normal(b.curto) in (select x.chave from mesmo_nome x)) as ambiguo, count(*) over () as n,
           count(*) over (partition by b.client_id) as do_cliente
      from base b
     order by b.vence, b.enviar_em, b.ordem_nome, b.msg
  loop
    v_total := r.n;
    exit when cardinality(v_txt) >= c_max;
    v_nome := case when r.ambiguo then r.completo else r.curto end;
    v_dia := (r.vence at time zone 'America/Sao_Paulo')::date;
    v_hora := to_char(r.vence at time zone 'America/Sao_Paulo', 'FMHH24') || 'h'
              || case when extract(minute from r.vence at time zone 'America/Sao_Paulo') <> 0
                      then to_char(r.vence at time zone 'America/Sao_Paulo', 'MI') else '' end;
    v_vence := 'vence ' || case when v_dia = p_hoje then v_hora
                                when v_dia = p_hoje + 1 then 'amanhã ' || v_hora
                                else public._dia_curto(v_dia) || ' ' || v_hora end;
    v_oque := coalesce(public._agenda_cliente_o_que(r.tipo, r.dia),
                       'a mensagem' || coalesce(' (' || public._agenda_cliente_tipo_texto(r.tipo) || ')', ''));
    -- o mesmo cliente com mais de uma mensagem: a OS diz qual é qual (o *manda cliente <nome>* manda as dele)
    v_linha := format('%s%s: %s. Mando? (%s)', v_nome, case when r.do_cliente > 1 and r.os_num is not null then ' (' || r.os_num || ')' else '' end,
                      v_oque, v_vence);
    v_txt := v_txt || v_linha;
    if not v_nome = any (v_nomes) then
      v_nomes := v_nomes || v_nome;
    end if;
    v_linhas := v_linhas || jsonb_build_object('pergunta_id', r.pergunta_id, 'mensagem_id', r.msg, 'nome', v_nome,
                                               'texto', v_linha, 'vence_em', r.vence);
  end loop;
  if v_total = 0 then
    -- TERMINOU: (23/11/2026) nenhuma mensagem ao cliente esperando: o "terminou ou falta dia?" ainda entra. A linha de antes, em "--antes:".
--antes:    return jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null);
    return public._agenda_terminou_da_manha(jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), p_hoje, p_agora);
    -- TERMINOU: fim
  end if;
  v_bloco := case when v_total = 1 then '📨 Mensagem ao cliente esperando o seu sim:' else '📨 Mensagens ao cliente esperando o seu sim:' end
             || E'\n' || array_to_string(array(select '• ' || t from unnest(v_txt) t), E'\n')
             || case when v_total > cardinality(v_txt)
                     then format(E'\n• e mais %s (*agenda clientes* mostra)', v_total - cardinality(v_txt)) else '' end
             || E'\n'
             || case when cardinality(v_nomes) = 1 and v_total = cardinality(v_txt)
                     then format('Para mandar: *manda cliente %s*. Para não mandar: *segura cliente %s*.', v_nomes[1], v_nomes[1])
                     else format('Para mandar: *manda cliente %s* (ou *manda cliente*: as %s). Para não mandar: *segura cliente %s*.',
                                 v_nomes[1], v_total, v_nomes[1]) end
             || ' O texto: *agenda clientes*.';
  -- TERMINOU: (23/11/2026) depois do bloco do cliente (uma linha em branco), o "terminou ou falta dia?". A linha de antes, em "--antes:".
--antes:  return jsonb_build_object('total', v_total, 'linhas', v_linhas, 'texto', v_bloco);
  return public._agenda_terminou_da_manha(jsonb_build_object('total', v_total, 'linhas', v_linhas, 'texto', v_bloco), p_hoje, p_agora);
  -- TERMINOU: fim
end;
$function$;

-- ── 6. _agenda_rotina_conclusao (corpo de PRODUÇÃO + blocos TERMINOU) ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_rotina_conclusao(p_hoje date, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       record;
  v_os    uuid[];
  v_x     uuid;
  v_st    text;
  v_fut   date[];
  v_rest  numeric;
  v_r     jsonb;
  v_acao  uuid;
  v_nome  text;
  v_cli   text;
  v_conc  int := 0;
  v_perg  int := 0;
  -- FASE 7c: (7c P8) as etapas pendentes ditas da OS
  v_p8_pend text[];
  -- FASE 7c: fim
  -- TERMINOU: (23/11/2026) o "terminou ou falta dia?" do dono
  v_term     jsonb;
  v_term_est text;
  v_term_msg text;
  -- TERMINOU: fim
begin
  for m in
    select x.* from public.agenda_equipe_mensagens x
     where x.tipo = 'como_foi' and x.modo = 'ligado' and x.dia = p_hoje and x.acao_id is null
       and coalesce((x.leitura ->> 'terminou')::boolean, false)
     order by x.resposta_em, x.id
  loop
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = m.payee_id and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva');
    continue when cardinality(v_os) <> 1;
    v_x := v_os[1];
    select so.status into v_st from public.service_orders so where so.id = v_x;
    continue when v_st not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client');
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
    v_cli := (select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
               where so.id = v_x);
    v_fut := array(select distinct a.dia from public.agenda_alocacoes a
                    where a.service_order_id = v_x and a.dia > p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
    v_rest := (public.agenda_meios_da_os(v_x, p_hoje + 1) ->> 'restantes')::numeric;
    -- FASE 7c: (7c P8, §16.3.9 (c), §16.6.6; AG7-10d; R5.2-3, R5.10-11) com modo_tarefas ligado e tarefas_concluir_sem_pendente, o
    -- "terminei" no último dia não conclui a OS que tem etapa pendente DITA (uma etapa viva cuja última linha com resultado é pendente: pela
    -- equipe, pela conferência ou pelo dono); vira a pergunta concluir com o que falta. A sem registro e a etapa sem linha não seguram. O
    -- *concluiu* do dono conclui como hoje.
    if cardinality(v_fut) = 0 and v_rest = 0 and cf.modo_tarefas = 'ligado' and cf.tarefas_concluir_sem_pendente then
      v_p8_pend := array(select t.texto from public.os_tarefas t
                          where t.service_order_id = v_x and t.estado = 'viva'
                            and (select d.resultado from public.os_tarefas_dia d
                                  where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.resultado is not null
                                  order by d.dia desc, d.turno = 'tarde' desc, d.resultado_em desc limit 1) = 'pendente'
                          order by t.ordem, t.id);
      if cardinality(v_p8_pend) > 0 then
        if public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
             format('O %s disse que terminou o %s, mas não concluí: ainda falta %s. *concluiu %s* fecha a OS mesmo assim.', v_nome,
                    coalesce(v_cli, public._agenda_rotulo_da_os(v_x)),
                    public._agenda_lista(array(select '"' || x || '"' from unnest(v_p8_pend) with ordinality u(x, o) order by o), 3),
                    coalesce(v_cli, (select so.service_order_number from public.service_orders so where so.id = v_x))),
             'ligado', p_agora) then
          v_perg := v_perg + 1;
        end if;
        continue;
      end if;
    end if;
    -- FASE 7c: fim
    if cardinality(v_fut) = 0 and v_rest = 0 then
      if cf.modo_proposta = 'ligado' then
        v_r := public.os_registrar_marco(v_x, 'conclusao', 'equipe', null, null,
                                         left(format('O %s disse que terminou: "%s"', v_nome, m.resposta_texto), 200), p_hoje, p_agora);
        if coalesce((v_r ->> 'ok')::boolean, false) and v_r ->> 'acao_id' is not null then
          update public.agenda_equipe_mensagens set acao_id = (v_r ->> 'acao_id')::uuid where id = m.id;
          v_conc := v_conc + 1;
        else
          -- a porta recusou (o período fechado, o levantamento…): a pergunta, com a frase dela
          perform public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
            format('O %s disse que terminou o %s, mas não concluí: %s', v_nome, public._agenda_rotulo_da_os(v_x),
                   coalesce(v_r ->> 'texto', 'a porta recusou.')), 'ligado', p_agora);
          v_perg := v_perg + 1;
        end if;
      else
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
        values (clock_timestamp(), p_hoje, false, 'equipe', 'concluir', v_x, array[v_x], m.payee_id,
                jsonb_build_object('mensagem', m.id),
                left(format('Em teste: concluiria o %s (o %s disse que terminou e era o último dia do plano).',
                            public._agenda_rotulo_da_os(v_x), v_nome), 400))
        returning id into v_acao;
        update public.agenda_equipe_mensagens set acao_id = v_acao where id = m.id;
        v_conc := v_conc + 1;
      end if;
    else
      if public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
           format('O %s disse que terminou o %s, mas o plano tinha mais %s. *concluiu %s* fecha a OS.', v_nome,
                  public._agenda_rotulo_da_os(v_x),
                  case when cardinality(v_fut) > 0
                       then public._agenda_plural(cardinality(v_fut), 'dia', 'dias') || ' (' || public._agenda_dias_texto(v_fut) || ')'
                       else 'serviço do que você disse' end,
                  coalesce(v_cli, (select so.service_order_number from public.service_orders so where so.id = v_x))),
           'ligado', p_agora) then
        v_perg := v_perg + 1;
      end if;
    end if;
  end loop;
  -- TERMINOU: (23/11/2026, NOVO-testes-01, opção A do dono) a OS em execução com o plano cumprido e sem dia futuro ganha a pergunta
  -- "A OS-X terminou ou falta dia?" (_agenda_terminou_rodar; também fecha a que não vale mais). Num bloco próprio: o erro dela vai para
  -- app_error_logs (rotina:terminou) e não desfaz as conclusões da equipe deste passo. A linha de antes, em "--antes:".
  begin
    v_term := public._agenda_terminou_rodar(p_hoje, p_agora);
  exception when others then
    get stacked diagnostics v_term_est = returned_sqlstate, v_term_msg = message_text;
    perform public.log_app_error('db', 'rotina da agenda, terminou ou falta dia: ' || v_term_msg, 'agenda', 'rotina:terminou', 'error',
                                 jsonb_build_object('sqlstate', v_term_est, 'p_hoje', p_hoje, 'p_agora', p_agora));
    v_term := jsonb_build_object('erro', left(v_term_msg, 200));
  end;
--antes:  return jsonb_build_object('concluidas', v_conc, 'perguntas', v_perg);
  return jsonb_build_object('concluidas', v_conc, 'perguntas', v_perg, 'terminou', v_term);
  -- TERMINOU: fim
end;
$function$;

-- ── 7. agenda_saude (corpo de PRODUÇÃO + 1 bloco TERMINOU no aprovada_sem_data) ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.agenda_saude(p_hoje date DEFAULT _hoje_brt(), p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
  -- FASE 6: o aprendizado
  v_arod    record;
  v_apeq    int;
  v_afora   int;
  v_agrande int;
  v_aatras  int;
  v_asemcl  int;
  v_afat    int;
  v_amet    jsonb;
  v_zeros6  boolean;
  v_apr     jsonb;
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros de antes do aprendizado (para o ok sair com as janelas de agenda_config)
  v_z4_antes boolean;
  -- FASE 7: (7a P7) o gestor da agenda
  v_ges     jsonb;
  v_gz      jsonb;
  v_gzeros  boolean;
  v_gdesde  timestamptz;
  v_gmodos  jsonb;
  v_gult    record;
  v_gr      jsonb;
  -- FASE 7: fim
  -- CORREÇÃO FASE 6: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros obrigatórios de antes do aprendizado (o bloco do aprendizado os junta aos dele; o
  -- bloco da C2 depois dele refaz essa junta com as janelas de agenda_config)
  v_z4_antes := v_zeros4;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) o aprendizado (spec-fase6 §11) — o modo, a lista, a rodada, os itens e as métricas. Os "0 obrigatórios"
  -- (entram no ok pelo v_zeros4, como os das Fases 4 e 5): nada em uso com menos medidas que o mínimo; nada que a ÚLTIMA
  -- rodada gravou em uso com o modo dela fora de ligado ou o item fora da lista dela (logo depois de o dono desligar, o leitor
  -- já devolve o padrão; a linha muda na rodada seguinte); nenhuma troca grande que entrou sozinha (as ações da vigia em 7 dias
  -- contra os limites de hoje: a regra de _agenda_aprendizado_troca_cabe, que não tem porta para quem lê a saúde); nenhuma
  -- rodada atrasada (depois da 1ª, nenhuma em 26 h); nenhuma medida sem classe; nenhum fator fora de [fator_min, fator_max].
  -- Os erros de aprender:% em 24 h e as métricas não reprovam.
  select x.p_agora, x.p_hoje, x.contagens into v_arod
    from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  select count(*) into v_apeq
    from public.agenda_aprendizado a
   where a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min;
  select count(*) into v_afora
    from public.agenda_aprendizado a
   where v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
     and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
          or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false));
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '7 days'
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null and v_arod.p_agora < p_agora - interval '26 hours' then 1 else 0 end;
  select count(*) into v_asemcl from public.agenda_medidas_os m where m.classe_bem is null or m.classe_sistema is null;
  select count(*) into v_afat
    from public.agenda_aprendizado a
   where a.item = 'fator'
     and ((a.calculado is not null and a.calculado not between cf.fator_min and cf.fator_max)
          or (a.em_uso is not null and a.em_uso not between cf.fator_min and cf.fator_max));
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a group by a.item) t), '{}'::jsonb),
    'medidas', (select jsonb_build_object('total', count(*), 'validas', count(*) filter (where m.valida),
                                          'invalidas', coalesce((select jsonb_object_agg(y.motivo, y.n)
                                                                   from (select z.motivo, count(*) as n from public.agenda_medidas_os z
                                                                          where not z.valida
                                                                            and z.concluida_em > p_hoje - cf.aprender_janela_dias
                                                                          group by z.motivo) y), '{}'::jsonb))
                  from public.agenda_medidas_os m where m.concluida_em > p_hoje - cf.aprender_janela_dias),
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '30 days'),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - interval '30 days'),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida' and q.respondida_em > p_agora - interval '30 days'),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '30 days')),
    -- o erro do fator: das OS válidas concluídas depois que o fator da classe delas passou a valer, quantas ficaram dentro dele
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t),
    -- a pontualidade com o cliente antes e depois de a folga do aviso valer
    'pontualidade_folga', (select case when f.desde is not null then jsonb_build_object(
                                     'desde', f.desde,
                                     'antes_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                    where m.atraso_cliente_du is not null and m.concluida_em < f.desde),
                                     'depois_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                     where m.atraso_cliente_du is not null and m.concluida_em >= f.desde)) end
                             from (select (min(a.em_uso_desde) at time zone 'America/Sao_Paulo')::date as desde
                                     from public.agenda_aprendizado a where a.item = 'aviso_folga' and a.em_uso is not null) f),
    -- parar (§11): o item que o dono desfez 2 vezes em 4 semanas (recomendar tirá-lo da lista; a decisão é dele)
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '28 days'
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb))
    into v_amet;
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_zeros4 and v_zeros6;
  v_apr := jsonb_build_object(
    'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
    'ultima_rodada', v_arod.p_agora,
    'rodou_hoje', exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'aprender:%'
                     and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora, 'troca_grande_sem_pergunta', v_agrande,
    'rodada_atrasada', v_aatras, 'medida_sem_classe', v_asemcl, 'fator_fora_dos_limites', v_afat,
    'metricas', v_amet);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: as janelas do aprendizado na saúde vêm de agenda_config (eram números escritos aqui): a
  -- troca grande que entrou sozinha, nas ações dos últimos aprender_saude_dias (era 7 dias); a rodada atrasada, sem rodada há
  -- mais de aprender_atraso_h (era 26 h); as trocas das métricas, nos últimos aprender_parar_dias (era 30 dias; a chave
  -- trocas_30d fica com o nome); o item desfeito 2 vezes dentro de aprender_trava_dias (era 28 dias, as "4 semanas" da §11).
  -- As contas de cima não valem mais: refeitas aqui com o parâmetro (com os DEFAULTs, o mesmo resultado), e com elas os
  -- zeros, o ok e o bloco aprendizado.
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
     and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null
                        and v_arod.p_agora < p_agora - make_interval(hours => cf.aprender_atraso_h) then 1 else 0 end;
  v_amet := v_amet || jsonb_build_object(
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                      and a.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida'
                       and q.respondida_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - make_interval(days => cf.aprender_parar_dias))),
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado'
                                                     and a.desfeita_em > p_agora - make_interval(days => cf.aprender_trava_dias)
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb));
  -- (7e P7; §5.6, R7.5-17, a correção do P4; marca sem FASE porque está dentro do bloco da correção C2 da Fase 6) os itens da margem têm os zeros e os números deles na chave margem
  -- (_agenda_saude_margem, no fim): aqui eles saem dos zeros e das métricas do aprendizado da Fase 6, que não os conhecem. Sem isso, com a margem ligada, o "em uso fora de ligado" contava
  -- todo item da margem recalculado na última rodada (_agenda_aprendizado_da_lista é nula para eles: nunca estão em aprendizado_ligados), a "troca grande sem pergunta" contava toda ação
  -- da margem (o case não os conhece) e o "em uso com amostra pequena" contava a folga da semana que volta ao padrão por passo sem medida (R7.4): o ok da saúde cairia a cada passo.
  -- Cada conta tira exatamente o que a de cima contou dos itens da margem (as mesmas condições). Sem linha nem ação da margem, tira 0 e as métricas são as de antes, byte a byte.
  v_apeq := v_apeq - (select count(*) from public.agenda_aprendizado a
                       where a.item = 'folga_semana' and a.calculado is null
                         and a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min);
  v_afora := v_afora - (select count(*) from public.agenda_aprendizado a
                         where a.item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor')
                           and v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
                           and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
                                or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false)));
  v_agrande := v_agrande - (select count(*) from public.agenda_acoes a
                             where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                               and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
                               and a.antes ->> 'item' in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'));
  v_apr := v_apr || jsonb_build_object('em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora);
  v_amet := v_amet || jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a where a.item not in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor') group by a.item) t), '{}'::jsonb));
  -- (7e: fim)
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_z4_antes and v_zeros6;
  v_apr := v_apr || jsonb_build_object('troca_grande_sem_pergunta', v_agrande, 'rodada_atrasada', v_aatras, 'metricas', v_amet);
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P7, spec §11) o bloco gestor: os modos efetivos, a última rodada (rotina gestor), os erros de gestor:% em 24 h, os
  -- zeros obrigatórios (entram no ok, salvo prazo_vencido_sem_mostrar, que só se conta: a pergunta fica aberta) e os números. Os
  -- zeros do que o gestor muda sozinho contam a partir do OK de ligar (marcar_sozinho_desde): antes dele não há o que contar.
  -- E (aviso do P6) o erro do fator só com as medidas que têm fator: a medida por estimativa é válida e não tem fator.
  v_gdesde := cf.marcar_sozinho_desde;
  v_gmodos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                 'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                 'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor, 'desde', v_gdesde);
  select max(x.p_agora) as ultima,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         coalesce(bool_or(x.p_hoje = p_hoje and x.contagens ? 'diaria'), false) as diaria_hoje,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_gult from public.agenda_vigia_rodadas x where x.rotina = 'gestor';
  v_gz := jsonb_build_object(
    -- o dia que o cliente ouviu e o dia que a equipe já sabia, mudados sem a pergunta crítica (a regra de _agenda_criticidade_da_acao)
    'zona_travada_mexida', (select count(*) from public.agenda_acoes a
                             where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                               and a.origem in ('motor', 'vigia', 'conferencia')
                               and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                               and public._agenda_criticidade_da_acao(a.id) = 'dia_prometido'),
    'dia_avisado_sem_pergunta', (select count(*) from public.agenda_acoes a
                                  where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                    and a.origem in ('motor', 'vigia', 'conferencia')
                                    and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                                    and public._agenda_criticidade_da_acao(a.id) = 'dia_avisado'),
    -- marcada pela estimativa sem a pergunta que ela pedia (grande, começada/parada, sem mão de obra, peça embutida)
    'estimativa_sem_pergunta', case when not public._agenda_gestor_regra('estimativa') then 0 else (
       select count(*) from (select distinct a.service_order_id as os from public.agenda_alocacoes a
                               left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
                              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                                and a.resultado is null and a.duracao_fonte = 'orcamento' and pl.dias is null) o
        where coalesce(public._agenda_gestor_estimativa(o.os, p_hoje) ->> 'motivo', '') in ('grande', 'situacao', 'sem_base', 'embutida')) end,
    'prazo_em_critica', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.critica and q.veto_ate is not null),
    'prazo_em_dia_prometido', (select count(*) from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.veto_ate is not null and q.tipo = 'dia_prometido'),
    -- aprovada há mais de aprovada_sem_data_min sem dia, sem reserva, sem pergunta aberta e sem o motor ter dito por que fica de
    -- fora depois da aprovação (com o encaixe na aprovação ligado: antes dele, quem encaixa é a vigia e a publicação)
    'aprovada_sem_data', case when public._agenda_gestor_modo('encaixe') <> 'ligado' then 0 else (
       select count(*) from public.os_carteira(p_hoje) k join public.service_orders so on so.id = k.service_order_id
        where coalesce(so.converted_to_os_at, so.signed_at) is not null
          and coalesce(so.converted_to_os_at, so.signed_at) < p_agora - make_interval(mins => cf.aprovada_sem_data_min)
          and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.service_order_id
                           and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
          -- TERMINOU: (23/11/2026, NOVO-testes-01) a pergunta aberta da OS também pelos os_ids (a conferência do dia tem a OS só em os_ids). A linha
          -- de antes, em "--antes:". A pergunta "terminou ou falta dia?" tem service_order_id: a OS com ela aberta não conta como sem data.
--antes:          and not exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = k.service_order_id)
          and not exists (select 1 from public.agenda_perguntas q
                           where q.estado = 'aberta' and (q.service_order_id = k.service_order_id or k.service_order_id = any (q.os_ids)))
          -- TERMINOU: fim
          and not exists (select 1 from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                           where pr.criada_em >= coalesce(so.converted_to_os_at, so.signed_at)
                             and (f ->> 'os')::uuid = k.service_order_id)) end,
    -- sem rodada do gestor em 40 min, de 07:30 a 21:00 de dia útil, com algum modo do gestor fora de desligado
    'rodada_gestor_atrasada', case when (v_gmodos ->> 'marcar' <> 'desligado' or v_gmodos ->> 'encaixe' <> 'desligado'
                                         or v_gmodos ->> 'revisao' <> 'desligado' or v_gmodos ->> 'compre_ate' <> 'desligado')
                                        and public.agenda_dia_util(p_hoje)
                                        and (p_agora at time zone 'America/Sao_Paulo')::time between time '07:30' and time '21:00'
                                        and coalesce(v_gult.ultima < p_agora - interval '40 minutes', true) then 1 else 0 end,
    -- a mensagem ao cliente por estimativa que saiu sem o sim do dono antes de somar cliente_aprovacao_dias dias aprovados
    'cliente_estimativa_sem_aprovacao', (
       select count(*) from public.agenda_cliente_mensagens m
        where v_gdesde is not null and m.criada_em >= v_gdesde and m.base -> 'dados' ->> 'por_estimativa' = 'true'
          and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta') and m.aprovacao <> 'aprovada'
          and (select count(distinct (n.aprovada_em at time zone 'America/Sao_Paulo')::date) from public.agenda_cliente_mensagens n
                where n.tipo = m.tipo and n.base -> 'dados' ->> 'por_estimativa' = 'true' and n.aprovacao = 'aprovada'
                  and n.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias),
    -- a ficha de um dia por estimativa que saiu na janela de veto sem a pergunta ficha_estimativa mostrada (ou segurada com 2)
    'ficha_estimativa_sem_veto', (
       select count(*) from public.agenda_equipe_mensagens em
        where v_gdesde is not null and em.tipo = 'ficha' and em.modo = 'ligado'
          and em.estado in ('enfileirada', 'respondida', 'sem_resposta')
          and em.dia >= (v_gdesde at time zone 'America/Sao_Paulo')::date
          and em.dia < (v_gdesde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias
          and exists (select 1 from public.agenda_alocacoes a where a.payee_id = em.payee_id and a.dia = em.dia
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento')
          and not exists (select 1 from public.agenda_perguntas q
                           where q.chave = 'ficha_estimativa:' || em.payee_id || ':' || em.dia and q.mostrada_vezes > 0
                             and q.opcao_escolhida is distinct from 2)),
    -- a rodada que mudou o dia de mais de gestor_k_os OS de uma vez sem a pergunta onda
    'onda_aplicada_sem_pergunta', (
       select count(*) from (select a.proposta_id from public.agenda_acoes a
                               where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                 and a.origem in ('motor', 'vigia') and a.tipo = 'mover' and a.proposta_id is not null
                               group by a.proposta_id having count(distinct a.service_order_id) > cf.gestor_k_os) p
        where not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda' and q.proposta_id = p.proposta_id)),
    -- o compromisso novo sem de onde veio a duração (o gatilho _agenda_alocacao_fonte grava em toda alocação nova)
    'alocacao_sem_fonte', (select count(*) from public.agenda_alocacoes a
                            where v_gdesde is not null and a.criado_em >= v_gdesde and a.tipo <> 'reserva' and a.duracao_fonte is null),
    -- a ação do gestor feita numa rodada em que o modo dela não estava ligado (estimar: marcar; reestimar e reparar: revisao)
    'regra_em_sombra_aplicada', (
       select count(*) from public.agenda_acoes a
        where a.executada and a.origem = 'vigia' and a.tipo in ('estimar', 'reestimar', 'reparar')
          and a.criada_em > p_agora - interval '7 days'
          and coalesce((select r.contagens -> 'modos' ->> case when a.tipo = 'estimar' then 'marcar' else 'revisao' end
                          from public.agenda_vigia_rodadas r
                         where r.rotina = 'gestor' and r.p_agora <= a.criada_em
                         order by r.p_agora desc, r.rodou_em desc limit 1), 'desligado') <> 'ligado'),
    -- a pergunta com prazo vencido que o dono nunca viu antes do prazo: fica aberta (aqui só se conta; não entra no ok)
    'prazo_vencido_sem_mostrar', (select count(*) from public.agenda_perguntas q
                                   where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora
                                     and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)));
  -- (7f P7; R2, P2b, AG7-15; dentro do bloco do gestor da 7a: por isso a marca, não o bloco) prazo_em_critica: desde a 7f a crítica pode ter prazo e vencer (AG7-15, "sem resposta
  -- fica como ele propôs"). O zero passa a ser o prazo em crítica que nunca venceria: fora de veto_tipos ou com veto_espera. Hoje, 0 críticas na história: 0 nos dois jeitos.
  v_gz := v_gz || jsonb_build_object('prazo_em_critica', (select count(*) from public.agenda_perguntas q
                                                         where q.estado = 'aberta' and q.critica and q.veto_ate is not null
                                                           and (not q.tipo = any (cf.veto_tipos) or q.veto_espera is not null)));
  -- (7f: fim)
  v_gzeros := not exists (select 1 from jsonb_each(v_gz) z where z.key <> 'prazo_vencido_sem_mostrar' and (z.value)::text <> '0');
  v_ges := jsonb_build_object(
    'modos', v_gmodos, 'regras', to_jsonb(cf.marcar_regras),
    'ultima_rodada', v_gult.ultima, 'rodadas_24h', coalesce(v_gult.n24, 0), 'diaria_hoje', coalesce(v_gult.diaria_hoje, false),
    'erros_ultima_rodada', coalesce(v_gult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'gestor:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', v_gzeros,
    'numeros', jsonb_build_object(
      'os_por_estimativa', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.resultado is null and a.duracao_fonte = 'orcamento'),
      'perguntas_com_prazo', jsonb_build_object(
        'abertas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null),
        'vencidas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora),
        'respondidas_7d', (select count(*) from public.agenda_perguntas q where q.estado = 'respondida' and q.veto_ate is not null
                             and q.respondida_em > p_agora - interval '7 days'),
        'pelo_prazo_7d', (select count(*) from public.agenda_acoes a where a.tipo = 'estimar' and a.origem = 'vigia' and a.executada
                            and a.criada_em > p_agora - interval '7 days')),
      'compre_ate', jsonb_build_object(
        'gravados', (select count(*) from public.os_material m where m.compre_ate is not null),
        'cobrados', (select count(*) from public.os_material m where m.cobrado_vezes > 0),
        'empurrados', (select count(*) from public.os_material m where m.empurrada_vezes > 0)),
      'fichas_seguradas_7d', (select count(*) from public.agenda_equipe_mensagens em
                               where em.recusa_motivo = 'veto' and em.criada_em > p_agora - interval '7 days'))) || v_gz;
  v_amet := v_amet || jsonb_build_object(
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.fator is not null
                                 and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t));
  v_apr := v_apr || jsonb_build_object('metricas', v_amet);
  v_gr := jsonb_build_object(
    -- os zeros obrigatórios da execução (a Fase 3), do material e da mensagem ao fornecedor (a Fase 4) e os do gestor entram no ok
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          and v_zeros4
          and v_gzeros,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    'cliente', v_cli,
    'aprendizado', v_apr,
    'material', v_mat,
    'gestor', v_ges);
  -- FASE 7b (P5, §5.4, R4.3(g); dentro do bloco do gestor da 7a, que monta a saída e volta aqui — por isso sem os dois-pontos depois
  -- de "7b": os tiradores de antes tiram o bloco do gestor inteiro e não o leem como bloco próprio): a chave equipe_dias
  -- (_agenda_saude_equipe7b: as mensagens dias à equipe, a dupla no plano, quem nunca fica sozinho, o sábado, o dono numa vaga e a
  -- resposta gravada), com os zeros obrigatórios no ok. Sem os modos da 7b, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('equipe_dias', public._agenda_saude_equipe7b(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{equipe_dias,zeros_ok}')::boolean, true)));
  -- FASE 7b (P5): fim
  -- (7d P8; §11, R6.3-11; dentro do bloco do gestor: por isso a marca, não o bloco) a chave local (_agenda_saude_local), com os zeros obrigatórios no ok. Sem os modos da 7d, os
  -- zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('local', public._agenda_saude_local(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{local,zeros_ok}')::boolean, true)));
  -- O M11 na lista dos liberados (o recado do P6): aqui, e não na lista dos 11 lá em cima, que fica dentro do bloco da Fase 5
  if public._agenda_cliente_tipo_liberado('onde_fica') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["onde_fica"]'::jsonb);
  end if;
  -- (7d: fim)
  -- (7f P7; §11, R8.13; dentro do bloco do gestor: por isso a marca, não o bloco) a chave comunicacao (_agenda_saude_comunicacao), com os zeros obrigatórios no ok. Sem os modos
  -- da 7f e sem nada do que eles fazem, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('comunicacao', public._agenda_saude_comunicacao(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{comunicacao,zeros_ok}')::boolean, true)));
  -- (7f: fim)
  -- (7f P6; dentro do bloco do gestor: por isso a marca, não o bloco) o M12 na lista dos liberados, como o M11 da 7d: aqui, e não na lista dos 11 lá em cima,
  -- que fica dentro do bloco da Fase 5. Só a contagem: a semana nunca entra em cliente_tipos_ligados por aqui (o ligar é do dono)
  if public._agenda_cliente_tipo_liberado('semana') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["semana"]'::jsonb);
  end if;
  -- (7f: fim)
  -- (7e P7; §5.6, R7.5-17; dentro do bloco do gestor: por isso a marca, não o bloco) a chave margem (_agenda_saude_margem), com os zeros obrigatórios no ok. Sem nada da margem (nenhuma
  -- linha nem ação dela, o puxar sem rodar fora de hora), os zeros são 0 e o ok é o de antes. A chave existe em todos os modos e não traz os modos (não muda de um para o outro).
  v_gr := v_gr || jsonb_build_object('margem', public._agenda_saude_margem(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{margem,zeros_ok}')::boolean, true)));
  -- (7e: fim)
  -- (7g P6; §11, R9.5-17; dentro do bloco do gestor: por isso a marca, não o bloco) a chave explicar (_agenda_saude_explicar), com os zeros obrigatórios no
  -- ok. Sem os modos da 7g e sem nada do que eles fazem, os zeros são 0 e o ok é o de antes. A chave existe em todos os modos e não traz os modos.
  v_gr := v_gr || jsonb_build_object('explicar', public._agenda_saude_explicar(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{explicar,zeros_ok}')::boolean, true)));
  -- (7g: fim)
  return v_gr;
  -- FASE 7: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 6: o aprendizado
    'aprendizado', v_apr,
    -- FASE 6: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

-- ── 8. Os comentários das recriadas (o de antes + o que mudou; uma vez só) ────────────────────────────────────────────────────────────
do $c$
declare
  r record;
begin
  for r in select * from (values
      ('public.agenda_aprovacoes_da_manha(date,timestamptz)',
       ' TERMINOU (23/11/2026, 20270223100000): depois do bloco do cliente, _agenda_terminou_da_manha junta as perguntas "A OS-X terminou ou falta dia?" (concluir terminou:<os>) abertas — também com modo_cliente fora de ligado ou sem mensagem ao cliente —, as escritas em linhas[] ({pergunta_id, os, texto}) e terminou = {total, escritas}. Sem elas, a saída de antes, byte a byte.'),
      ('public._agenda_rotina_conclusao(date,timestamptz)',
       ' TERMINOU (23/11/2026, 20270223100000): no fim, num begin/exception próprio, _agenda_terminou_rodar abre e fecha a pergunta "A OS-X terminou ou falta dia?" (erro = app_error_logs rotina:terminou, as conclusões da equipe ficam); a saída ganha terminou = {abertas, fechadas}.'),
      ('public.agenda_saude(date,timestamptz)',
       ' TERMINOU (23/11/2026, 20270223100000): gestor.aprovada_sem_data enxerga a pergunta aberta da OS também por os_ids (a conferência do dia).')
    ) x(f, mais)
  loop
    if coalesce(obj_description(to_regprocedure(r.f), 'pg_proc'), '') not like '%TERMINOU (23/11/2026%' then
      execute format('comment on function %s is %L', r.f, coalesce(obj_description(to_regprocedure(r.f), 'pg_proc'), '') || r.mais);
    end if;
  end loop;
end
$c$;

-- ── 9. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- As recriadas mantêm as de antes (create or replace não mexe na ACL). As novas internas: ninguém de fora (a rotina e a manhã são definer).
-- A palavra: como agenda_concluir_dito (o painel com o login do administrador; o WhatsApp pelo service_role, que passa p_autor).
revoke all on function public._agenda_terminou_candidatas(date) from public, anon, authenticated, service_role;
revoke all on function public._agenda_terminou_rodar(date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public._agenda_terminou_da_manha(jsonb, date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.agenda_falta_dia_dito(uuid, text, text, date, timestamptz) from public, anon;
grant execute on function public.agenda_falta_dia_dito(uuid, text, text, date, timestamptz) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name) values ('20270223100000','agenda_terminou_falta_dia');
