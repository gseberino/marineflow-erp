-- Agenda de Produção — pacote 1 do assistente, A5 + A4 (26/11/2026): a conferência de ontem e as perguntas que sobraram do fechamento das 17:30
-- vão na mensagem da manhã das 07:30, até agenda_config.manha_sobras_max linhas. Sem mensagem nova.
--
-- Por quê (especificação: D:/IA-HBR/Trabalho/avaliacao-assistente-20261124/pacote1/spec-agenda.md, seções A4 e A5; críticas critica-risco.md ponto 4
-- e critica-viabilidade.md seção 4): o bloco das 17:30 cai fora do horário do dono e mostra 1 ou 2 perguntas por noite contra 7 a 13 abertas. Em
-- 24/11, 11 de 17 perguntas abertas nunca tinham sido mostradas, entre elas uma crítica. A conferência do dia ("dia feito") fica aberta na manhã
-- seguinte e em 60 dias foi mostrada 2 vezes em 6, sem nenhuma resposta.
--
-- O que muda:
--   1. _agenda_ontem_da_manha(p_cli, p_hoje, p_agora) — NOVA, stable, invoker, search_path = public, ninguém de fora executa (a de
--      _agenda_terminou_da_manha). Recebe o que a manhã já montou ({total, linhas, texto}) e, com manha_sobras_max = 0 (o padrão), devolve p_cli
--      como veio, sem ler mais nada. Com N > 0, junta, depois de uma linha em branco:
--        "Da agenda, ficou de ontem:"   ("ficou de sex 20/11:" quando o dia útil anterior não é ontem)
--        • A4, a conferência do dia útil anterior (agenda_somar_du(p_hoje, -1)) ainda aberta, em ligado, com o plano de v_agenda_dia (reserva fora;
--          até 3 OS, "e mais N"); a palavra leva a data (dd/mm) e nenhuma pergunta de sim ou não:
--          "Ontem (seg 23/11) o plano era: Fernando (OS-00131) com o Alex, o dia todo. Se foi como o plano, responda *dia feito 23/11*; se não,
--           *dia parcial* ou *dia não* com o motivo e a data (ex.: *dia parcial material 23/11*)."
--          (o dia útil anterior que não é ontem: "Em sex 20/11 o plano era: …")
--        • A5, as abertas na ordem de agenda_perguntas_em_ordem, até completar N linhas contando a da conferência: o título (efeito opcao) ou a
--          frase (_agenda_pergunta_frases), em até 200 letras. A que tem "?" sem palavra entre asteriscos leva " (*agenda pendências* mostra
--          inteira)" (o M8 da crítica de risco). Ficam de fora: cliente_aprovar e terminou:% (têm bloco próprio), as que a manhã já escreveu, as
--          que o último fechamento ENVIADO mostrou (agenda_fechamento_fila via fechamento, o dia mais recente antes de hoje, fora a que caiu), as
--          já mostradas perguntas_vezes_max vezes, as com opção escolhida e as que um aviso do gestor de hoje já levou (salvo a crítica: as duas
--          regras do bloco das 17:30) e TODA pergunta com prazo gravado (veto_ate não nulo): a manhã escreve só o título, sem a data, e mostrar a
--          pergunta antes do prazo é o que arma a opção padrão (_agenda_gestor_vetos, nos dois laços, só a aplica com mostrada_em < veto_ate).
--          Sem número de opção, sem "Decisão N:", sem "Sem resposta até": a manhã sai como ai_briefing, fora da trava do "1", e o registro da
--          manhã não grava prazo.
--        • "• e mais N em *agenda pendências*" com o que passou dos N; e, com ao menos uma pergunta além da conferência, a última linha
--          "Não responda só *sim*: use as suas palavras ou as de *agenda pendências*, onde estão as opções de cada uma."
--      As linhas escritas vão para linhas[] ({pergunta_id, texto}): o Secretário (aprovacoesDaResposta, guardarAprovacoesDaManha) já registra
--      cada pergunta_id como mostrada via 'manha' quando a fila disser 'sent', e a conferência também tem pergunta_id. ontem = {total, escritas}.
--      Nada a juntar: p_cli como veio. Erro ao montar (uma pergunta que não fecha): p_cli como veio mais ontem = {erro, sqlstate}, sem derrubar o
--      bloco do cliente nem o "terminou?" (a função roda na transação só de leitura do PostgREST: não há onde registrar o erro).
--   2. agenda_aprovacoes_da_manha recriada do corpo de PRODUÇÃO (md5 de pg_get_functiondef 05a224c69f64ee2168d5ffdb396d5ca8, conferido em 26/11/2026)
--      com 3 blocos "-- P1 AGENDA: … -- P1 AGENDA: fim": nas três saídas, _agenda_terminou_da_manha(X, …) vira
--      _agenda_ontem_da_manha(_agenda_terminou_da_manha(X, …), …), com a linha de antes em "--antes:". Tirados os blocos (e devolvidas as
--      linhas "--antes:"), o corpo é o de produção, byte a byte. Continua SECURITY DEFINER, stable e só do service_role (create or replace não
--      mexe na ACL).
--
-- Nenhuma tabela, coluna, CHECK, modo, cron ou edge function. A chave manha_sobras_max já existe (20270301120000) e nasce 0: com ela em 0 a manhã
-- sai byte a byte como antes. Ligar = 3, com o OK do dono.
-- PROVA: supabase/tests/agenda_p1_manha.sql (e agenda_aprovacao_na_manha.sql e agenda_terminou_falta_dia.sql sem mudar o esperado).
-- DESFAZER: update public.agenda_config set manha_sobras_max = 0 where id; (efeito na manhã seguinte), ou recriar agenda_aprovacoes_da_manha com o
-- corpo de produção (o de 20270223100000), tirar do comentário dela o trecho "P1 AGENDA (A5/A4" e
-- drop function public._agenda_ontem_da_manha(jsonb, date, timestamptz).

-- ── 1. A conferência de ontem e as sobras do fechamento (nova) ─────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_ontem_da_manha(p_cli jsonb, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_linha_max constant int := 200;   -- estrutural: a linha da manhã (a do fechamento é 220 com o "Decisão N: " e o prazo, que a manhã não escreve)
  c_os_max    constant int := 3;     -- estrutural: as OS do plano de ontem na linha da conferência; o resto, "e mais N"
  c_inteira   constant text := ' (*agenda pendências* mostra inteira)';
  cf       public.agenda_config := public._agenda_cfg();
  v_max    int;
  v_ant    date;
  v_ddmm   text;
  v_ja     text[];
  v_dia_f  date;
  v_fech   text[];
  v_conf   uuid;
  v_nconf  int := 0;
  v_itens  text[];
  v_txt    text[] := '{}';
  v_linhas jsonb := '[]'::jsonb;
  v_sobras int := 0;
  v_escr   int := 0;
  e        jsonb;
  q        public.agenda_perguntas;
  v_fr     jsonb;
  v_base   text;
  v_linha  text;
  v_bloco  text;
  v_est    text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_ontem_da_manha: sem o dia ou a hora.' using errcode = '22004';
  end if;
  v_max := coalesce(cf.manha_sobras_max, 0);
  if v_max <= 0 then
    return p_cli;
  end if;
  begin
    v_ant := public.agenda_somar_du(p_hoje, -1);
    v_ddmm := to_char(v_ant, 'DD/MM');
    -- o que a manhã já escreveu (o bloco do cliente e o "terminou?") não se repete
    v_ja := array(select x ->> 'pergunta_id'
                    from jsonb_array_elements(case when jsonb_typeof(p_cli -> 'linhas') = 'array' then p_cli -> 'linhas' else '[]'::jsonb end) x
                   where x ->> 'pergunta_id' is not null);

    -- A4: a conferência do dia útil anterior, aberta, com o plano de v_agenda_dia (a vista do veredito do bloco das 17:30)
    select x.id into v_conf from public.agenda_perguntas x
     where x.tipo = 'conferencia' and x.modo = 'ligado' and x.estado = 'aberta' and x.dia = v_ant and not (x.id::text = any (v_ja))
     order by x.criada_em desc, x.id desc
     limit 1;
    if v_conf is not null then
      v_itens := array(
        select coalesce(d.cliente_curto || ' (' || d.numero || ')', d.numero)
               || case when cardinality(t.nomes) = 0 then coalesce(', ' || t.dono, '')
                       else ' com ' || case when t.um_quando is not null then public._agenda_lista(t.nomes) || ', ' || t.um_quando
                                            else public._agenda_lista(t.cada) end
                            || coalesce(' (' || t.dono || ')', '') end
          from public.v_agenda_dia d
          cross join lateral (
            -- quem trabalha no turno ("você" é o dono) e quando; o dono que só abre ou fecha vai entre parênteses
            select coalesce(array_agg(p.nome order by p.o), '{}') as nomes,
                   coalesce(array_agg(p.nome || coalesce(' ' || p.quando, '') order by p.o), '{}') as cada,
                   case when count(*) > 0 and count(distinct coalesce(p.quando, '-')) = 1 then min(p.quando) end as um_quando,
                   (select case max(pj ->> 'presenca') when 'abertura' then 'você abre' when 'fechamento' then 'você fecha'
                                                       when 'abre_e_fecha' then 'você abre e fecha' end
                      from jsonb_array_elements(d.pessoas) w(pj)
                     where coalesce((pj ->> 'eh_dono')::boolean, false) and pj ->> 'presenca' <> 'turno') as dono
              from (select min(u.o) as o, u.nome, u.quando
                      from (select o, case when coalesce((pj ->> 'eh_dono')::boolean, false) then 'você' else 'o ' || (pj ->> 'nome') end as nome,
                                   case when pj -> 'turnos' @> '["manha", "tarde"]'::jsonb then 'o dia todo'
                                        when pj -> 'turnos' @> '["manha"]'::jsonb then 'de manhã'
                                        when pj -> 'turnos' @> '["tarde"]'::jsonb then 'à tarde' end as quando
                              from jsonb_array_elements(d.pessoas) with ordinality w(pj, o)
                             where pj ->> 'presenca' = 'turno') u
                     where u.nome is not null
                     group by u.nome, u.quando) p
          ) t
         where d.dia = v_ant and not d.reserva
         order by d.primeiro_inicio, d.numero, d.service_order_id);
      if cardinality(v_itens) > 0 then
        v_linha := format('%s o plano era: %s. Se foi como o plano, responda *dia feito %s*; se não, *dia parcial* ou *dia não* com o motivo e a data (ex.: *dia parcial material %s*).',
                          case when v_ant = p_hoje - 1 then 'Ontem (' || public._dia_curto(v_ant) || ')' else 'Em ' || public._dia_curto(v_ant) end,
                          array_to_string(v_itens[1:c_os_max], '; ')
                          || case when cardinality(v_itens) > c_os_max then format('; e mais %s', cardinality(v_itens) - c_os_max) else '' end,
                          v_ddmm, v_ddmm);
        v_txt := v_txt || v_linha;
        v_linhas := v_linhas || jsonb_build_object('pergunta_id', v_conf, 'texto', v_linha);
        v_nconf := 1;
      end if;
    end if;

    -- A5: o que o último fechamento enviado mostrou (as linhas guardadas com a fila; a que caiu não saiu)
    select max(f.dia) into v_dia_f from public.agenda_fechamento_fila f where f.via = 'fechamento' and f.dia < p_hoje;
    v_fech := array(select distinct z.id
                      from public.agenda_fechamento_fila f
                      cross join lateral jsonb_array_elements(f.linhas) l
                      cross join lateral (select l ->> 'pergunta_id' as id
                                          union all
                                          select jsonb_array_elements_text(case when jsonb_typeof(l -> 'pergunta_ids') = 'array' then l -> 'pergunta_ids'
                                                                                else '[]'::jsonb end)) z
                     where f.via = 'fechamento' and f.dia = v_dia_f and f.estado <> 'caiu' and z.id is not null);
    -- A5: as que sobraram, na ordem do bloco
    for e in select x from jsonb_array_elements(public.agenda_perguntas_em_ordem(p_hoje, p_agora)) x order by (x ->> 'ordem')::int loop
      select * into q from public.agenda_perguntas x where x.id = (e ->> 'id')::uuid;
      continue when not found;
      continue when q.tipo in ('cliente_aprovar', 'conferencia') or q.chave like 'terminou:%'
                 or q.id::text = any (v_ja) or q.id::text = any (v_fech)
                 or q.mostrada_vezes >= cf.perguntas_vezes_max
                 or q.opcao_escolhida is not null
                 or q.veto_ate is not null
                 or (not coalesce(q.critica, false)
                     and exists (select 1 from public.agenda_dono_avisos v
                                  where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and q.id = any (v.pergunta_ids)));
      v_sobras := v_sobras + 1;
      continue when cardinality(v_txt) >= v_max;
      v_fr := public._agenda_pergunta_frases(q, p_hoje);
      v_base := coalesce(nullif(btrim(case when q.padrao_efeito = 'opcao' then v_fr ->> 'titulo' else v_fr ->> 'frase' end), ''), btrim(q.texto));
      v_linha := case when v_base ~ '[?]' and v_base !~ '[*][^*]+[*]'
                      then public._agenda_corta(v_base, c_linha_max - char_length(c_inteira)) || c_inteira
                      else public._agenda_corta(v_base, c_linha_max) end;
      v_txt := v_txt || v_linha;
      v_linhas := v_linhas || jsonb_build_object('pergunta_id', q.id, 'texto', v_linha);
      v_escr := v_escr + 1;
    end loop;

    if cardinality(v_txt) = 0 then
      return p_cli;
    end if;
    v_bloco := case when v_ant = p_hoje - 1 then 'Da agenda, ficou de ontem:' else 'Da agenda, ficou de ' || public._dia_curto(v_ant) || ':' end
               || E'\n' || array_to_string(array(select '• ' || t from unnest(v_txt) t), E'\n')
               || case when v_sobras > v_escr then format(E'\n• e mais %s em *agenda pendências*', v_sobras - v_escr) else '' end
               || case when v_escr > 0
                       then E'\nNão responda só *sim*: use as suas palavras ou as de *agenda pendências*, onde estão as opções de cada uma.' else '' end;
    return coalesce(p_cli, '{}'::jsonb)
           || jsonb_build_object(
                'texto', case when nullif(btrim(coalesce(p_cli ->> 'texto', '')), '') is null then v_bloco
                              else (p_cli ->> 'texto') || E'\n\n' || v_bloco end,
                'linhas', coalesce(case when jsonb_typeof(p_cli -> 'linhas') = 'array' then p_cli -> 'linhas' end, '[]'::jsonb) || v_linhas,
                'ontem', jsonb_build_object('total', v_nconf + v_sobras, 'escritas', cardinality(v_txt)));
  exception when others then
    get stacked diagnostics v_est = returned_sqlstate, v_msg = message_text;
    return coalesce(p_cli, '{}'::jsonb) || jsonb_build_object('ontem', jsonb_build_object('erro', left(v_msg, 200), 'sqlstate', v_est));
  end;
end;
$function$;

comment on function public._agenda_ontem_da_manha(jsonb, date, timestamptz) is
  'Agenda de Produção, pacote 1 do assistente, A5/A4 (26/11/2026; 20270301120400): o pedaço da manhã depois do "terminou?". Com agenda_config.manha_sobras_max = 0 (o padrão), p_cli como veio. Com N > 0, depois de uma linha em branco, "Da agenda, ficou de ontem:" (ou "de <dia curto>:") e até N linhas: (A4) a conferência aberta em ligado do dia útil anterior, com o plano de v_agenda_dia (reserva fora, até 3 OS) e *dia feito dd/mm* / *dia parcial* / *dia não* com a data, sem pergunta de sim ou não; (A5) as abertas na ordem de agenda_perguntas_em_ordem, pelo título (efeito opcao) ou pela frase (_agenda_pergunta_frases), até 200 letras, com " (*agenda pendências* mostra inteira)" na que tem "?" sem palavra entre asteriscos, fora cliente_aprovar, terminou:%, as que a manhã já escreveu, as que o último fechamento enviado mostrou, as mostradas perguntas_vezes_max vezes, as com opção escolhida, as que um aviso do gestor de hoje levou (salvo a crítica) e as com prazo (veto_ate: mostrar sem a data armaria a opção padrão). "• e mais N em *agenda pendências*" e, com pergunta além da conferência, "Não responda só *sim*: …". Sem número de opção nem prazo. As escritas vão para linhas[] ({pergunta_id, texto}); ontem = {total, escritas}; nada a juntar = p_cli; erro = p_cli + ontem {erro, sqlstate}. Só lê. Invoker, sem grant (a chamadora é definer).';

-- ── 2. agenda_aprovacoes_da_manha (corpo de PRODUÇÃO de 26/11/2026 + 3 blocos P1 AGENDA) ──────────────────────────────────────────────
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
    -- P1 AGENDA: (A5/A4, 26/11/2026) sem o bloco do cliente, depois do "terminou ou falta dia?": a conferência de ontem e as perguntas que sobraram do fechamento (_agenda_ontem_da_manha; agenda_config.manha_sobras_max = 0: nada muda). A linha de antes, em "--antes:".
--antes:    return public._agenda_terminou_da_manha(jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), p_hoje, p_agora);
    return public._agenda_ontem_da_manha(public._agenda_terminou_da_manha(jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), p_hoje, p_agora), p_hoje, p_agora);
    -- P1 AGENDA: fim
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
    -- P1 AGENDA: (A5/A4, 26/11/2026) nenhuma mensagem ao cliente esperando: o mesmo. A linha de antes, em "--antes:".
--antes:    return public._agenda_terminou_da_manha(jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), p_hoje, p_agora);
    return public._agenda_ontem_da_manha(public._agenda_terminou_da_manha(jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), p_hoje, p_agora), p_hoje, p_agora);
    -- P1 AGENDA: fim
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
  -- P1 AGENDA: (A5/A4, 26/11/2026) depois do bloco do cliente e do "terminou ou falta dia?", o mesmo. A linha de antes, em "--antes:".
--antes:  return public._agenda_terminou_da_manha(jsonb_build_object('total', v_total, 'linhas', v_linhas, 'texto', v_bloco), p_hoje, p_agora);
  return public._agenda_ontem_da_manha(public._agenda_terminou_da_manha(jsonb_build_object('total', v_total, 'linhas', v_linhas, 'texto', v_bloco), p_hoje, p_agora), p_hoje, p_agora);
  -- P1 AGENDA: fim
  -- TERMINOU: fim
end;
$function$;

-- ── 3. O comentário da recriada (o de antes + o que mudou; uma vez só) ──────────────────────────────────────────────────────────────────
do $c$
declare
  c_f constant text := 'public.agenda_aprovacoes_da_manha(date,timestamptz)';
begin
  if coalesce(obj_description(to_regprocedure(c_f), 'pg_proc'), '') not like '%P1 AGENDA (A5/A4, 26/11/2026%' then
    execute format('comment on function %s is %L', c_f, coalesce(obj_description(to_regprocedure(c_f), 'pg_proc'), '')
      || ' P1 AGENDA (A5/A4, 26/11/2026, 20270301120400): nas três saídas, depois do "terminou?", _agenda_ontem_da_manha junta a conferência de ontem e as perguntas que sobraram do fechamento, até agenda_config.manha_sobras_max linhas (as escritas em linhas[] com pergunta_id; ontem = {total, escritas}). Com a chave em 0, a saída de antes, byte a byte.');
  end if;
end
$c$;

-- ── 4. Portas ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- A recriada mantém a de antes (definer, só service_role: create or replace não mexe na ACL). A nova interna: ninguém de fora (a manhã é definer).
revoke all on function public._agenda_ontem_da_manha(jsonb, date, timestamptz) from public, anon, authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name) values ('20270301120400','agenda_p1_manha_de_ontem');
