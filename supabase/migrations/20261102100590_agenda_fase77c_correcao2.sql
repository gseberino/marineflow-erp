-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê" e as tarefas do dia): a CORREÇÃO 2 DA REVISÃO (a 2ª revisão da etapa,
-- dom 01/11/2026; notas-fase77c.md, seção "Correção 2 da revisão"). Fica DEPOIS da correção da revisão (20261102100580) e ANTES do dado
-- (20261102100600). NÃO APLICADA. Só recria funções (6; nenhuma nova, as mesmas portas: create or replace mantém os grants e o security),
-- cada uma copiada da definição MAIS NOVA pelo nome do arquivo e só com acréscimos — blocos "-- FASE 7c: (7c correção 2, achado N) …
-- -- FASE 7c: fim" e, dentro de um bloco de antes, marcas "-- (7c correção 2, achado N) … -- (7c: fim)". Tirados eles, cada corpo é a
-- origem byte a byte (o montador scratchpad/agenda-pesquisa/f7c/rev2/corr2/montar-migration.mjs e o C0 de
-- supabase/tests/agenda_fase77c_correcao2.sql conferem):
--   · _agenda_linhas_do_fechamento (da 20261102100580): (achados 1 e 13) quando uma linha da 7c ligada espera demais — a (n) com quem
--     faz o quê nunca vista há 2 dias úteis, que a 100580 subia a 77, ou a (o) "Etapas" da véspera do último dia —, sobem a 77 TODAS as
--     linhas ligadas de 75 (a mensagem ao cliente, a (o), a (n)): sai a pergunta do gestor (76) que não perde hoje, nunca a mensagem ao
--     cliente; (achado 13) na véspera de um dia de revisão (o 1º dia útil da semana ou do mês, quando o Secretário não traz as linhas da
--     agenda), a (o) já cobra o último dia que cai no dia útil seguinte; (achado 15) a forma curta da (o) diz o dia ("seg 09/11"), não
--     "amanhã", quando o próximo dia útil não é amanhã; (achado 11) a pergunta de quem faz o quê da equipe, ligada, que vai como
--     "Também" leva o que foi marcado E o prazo, e conta como vista;
--   · _agenda_tarefas_planejar (da 20261102100580): (achado 12) as etapas repartem a duração do PLANO (os meios-dias marcados, os feitos
--     pelo peso), quando ele é maior que a da OS (a dupla inferida da 7b supõe 2 pessoas e o motor marcou 1: o Lenine 10 × 12);
--   · _agenda_tarefas_sincronizar (da 20261102100550): (achado 5) a linha de os_planejamento que a rodada das etapas cria nasce com o
--     carimbo da OS (service_orders.created_at), não com o de agora — em teste, a rodada não acorda o encaixe nem solta a trava do
--     *desfaz* da 7a;
--   · agenda_habilidade (da 20261102100580): (achado 2) a cada tique, a pergunta LIGADA de quem faz o quê ou das etapas cujo modo voltou
--     a teste é descartada ("o modo voltou a teste") — ela fazia a linha (n) inteira ir ao detalhe e escondia do dono a chamada ligada da
--     7b, para sempre;
--   · _agenda_ver_habilidades (da 20261102100580): (achado 16) logo depois do ligar da pergunta, a proposta ainda de teste diz "ainda vou te
--     perguntar", não "em teste, eu marcaria"; (achado 3) com a escalação fora de ligado e a dupla da 7b ligada, a linha de quem tem perfil
--     de diária e uma palavra do dono valendo diz que ela já vale para quem é novo;
--   · agenda_rascunho_disponibilidade (da 20261101100800, a correção da revisão da 7b): (achado 14) as datas ditas com o mês só na última
--     ("qui 19 e seg 23/11", "24, 25 e 26/11") são essas datas — antes, só a que tinha o mês contava e, sem 2 datas, valia o dia da
--     semana na 1ª semana por vir, calado.
-- Com os 4 modos da 7c desligados, tudo é o de antes, byte a byte, salvo o achado 14 (a 7b: uma diferença deliberada, só nas frases com
-- o mês só na última data, que antes saíam erradas) e o achado 5 (o carimbo da linha nova de os_planejamento, que só a rodada das etapas
-- cria, com modo_tarefas fora de desligado). Em teste (o dado), o motor, os textos à equipe e ao cliente e as linhas ligadas do
-- fechamento ficam byte a byte; só mudam leituras do dono em teste. Nenhuma mensagem nova a ninguém.
--
-- QUEM RECRIAR DEPOIS uma destas 6 copia DESTA (a regra da função mais nova; fase7-registro.md §2).

-- _agenda_linhas_do_fechamento (de 20261102100580_agenda_fase77c_correcao.sql)
create or replace function public._agenda_linhas_do_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 480;   -- estrutural: uma linha da agenda no fechamento
  -- FASE 3: o fim do texto da conferência da vigia (é o que a linha dia troca quando tem o que contar da equipe)
  c_cauda constant text := ' Foi isso? Responda *dia feito* ou conte o que mudou.';
  v_ini   date;
  v_am1   date;
  v_am2   date;
  v_out   jsonb := '[]'::jsonb;
  q       record;
  g       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_conf  record;
  v_txts  text[];
  v_ids   jsonb;
  v_txt   text;
  v_mod   text;
  v_n     int;
  k       int;
  m       text;
  -- FASE 3
  v_eq    jsonb;
  v_base  text;
  v_dia   text;
  v_som   text;
  v_extra text;
  v_cauda text;
  v_pend  jsonb;
  v_tec   text;
  v_cob   text;
  v_ppc   jsonb;
  v_com   jsonb;
  -- FASE 7: (7a P7) a linha do gestor em teste e a das compras da semana
  v_f7_txt   text;
  v_f7_cmp   jsonb;
  v_f7_min   date;
  v_f7_urg   boolean;
  v_f7_perda int;
  -- FASE 7: fim
  -- FASE 7: (7a correção, achados 15 e 18) a linha das perguntas do gestor
  c_max_perg  constant int := 600;   -- estrutural: até 640 na coleta, como a do cliente
  v_f77_ids   jsonb;
  v_f77_txt   text;
  v_f77_prazo boolean;
  v_f77_segs  text[];
  v_f77_grupo text;
  v_f77_itens text[];
  v_f77_rest  int;
  v_f77_nl    text;
  v_f77_item  text;
  v_f77_ns    text[];
  v_f77_ni    text[];
  v_f77_l     text;
  v_f77_q     record;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) a linha (n) da equipe
  v_7b_on     boolean;
  v_7b_ids    jsonb;
  v_7b_txt    text;
  v_7b_itens  text[];
  v_7b_curtos text[];
  v_7b_rest   int;
  v_7b_perde  boolean;
  v_7b_lig    boolean;
  v_7b_item   text;
  v_7b_curto  text;
  v_7b_l      text;
  v_7b_q      record;
  -- (correção 3) o prazo de quem vence, na forma curta
  v_c3_ate    timestamptz;
  -- (correção 3: fim)
  -- FASE 7b: fim
  -- FASE 7c: (7c P5, R5.4 item 4) a linha (n) com as perguntas de quem faz o quê
  v_7c_on    boolean;
  v_7c_7b    boolean;
  v_7c_q     record;
  v_7c_eq    boolean;
  v_7c_marc  text;
  v_7c_exig  text;
  v_7c_ate   timestamptz;
  -- FASE 7c: fim
  -- FASE 7c: (7c P8, R5.4 item 4, R5.2-2(b)) as perguntas das etapas na linha (n) e a linha (o) das etapas
  v_p8_on     boolean;
  v_p8_q      record;
  v_p8_quem   boolean;
  v_p8_pess   record;
  v_p8_h      jsonb;
  v_p8_a      jsonb;
  v_p8_hi     jsonb;
  v_p8_ai     jsonb;
  v_p8_nomes  text[] := '{}';
  v_p8_nfone  int;
  v_p8_nrot   int;
  v_p8_hoje   jsonb := '[]'::jsonb;
  v_p8_amanha jsonb := '[]'::jsonb;
  v_p8_txt    text;
  v_p8_curto  text;
  v_p8_alta   boolean;
  v_p8_k      int;
  v_p8_g      record;
  v_p8_parte  text[];
  v_p8_dia    text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achados 14, 8 e 2) a 7b que espera a vez dela, a forma curta do cliente e a (n) que ficou de fora
  c_c2_dias   constant int := 2;    -- estrutural: os dias úteis que a pergunta de quem faz o quê espera sem ser vista antes de subir
  c_c2_perda  constant int := 77;   -- estrutural: acima das perguntas do gestor (76), abaixo da compra e da decisão (80)
  v_c14_pula  boolean;
  v_c8_agora  timestamptz;
  v_c8_tipo   text;
  v_c8_env    timestamptz;
  v_c8_qid    uuid;
  v_c8_nome   text;
  v_c8_n      int;
  v_c8_curto  text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção 2, achados 1, 11, 13 e 15) a cobrança do último dia antes de um dia de revisão, as linhas de 75 que sobem
  -- juntas e a "Também" de quem faz o quê que conta
  v_c13_av     jsonb := '[]'::jsonb;
  v_c13_d      date;
  v_c13_prox   date;
  v_c13_k      int;
  v_c13_p      record;
  v_c13_u      jsonb;
  v_c13_rev    boolean;
  v_c13_q      text;
  v_c13_parte  text[];
  v_c13_ult    boolean := false;
  v_c11_tambem boolean := false;
  -- FASE 7c: fim
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_ini := p_hoje - 6;
  v_am1 := public.agenda_somar_du(p_hoje, 1);
  v_am2 := public.agenda_somar_du(p_hoje, 2);

  -- (a) as decisões críticas abertas
  -- FASE 3: menos a da diária, que tem a linha dela (b2)
  for q in select x.* from public.agenda_perguntas x where x.critica and x.estado = 'aberta' and x.tipo <> 'diaria'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'decisao',
      'texto', 'Agenda, preciso de você. ' || q.texto || ' Me responda aqui.',
      'perda', case when q.perda_em is not null and q.perda_em <= v_am1 then 100
                    when q.perda_em is not null and q.perda_em <= v_am2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (a2): a diária que diverge do plano (crítica): as opções, a recomendação e as palavras que respondem.
  -- A perda: o banco não sabe quando o acerto fecha (o dono fecha quando quer); com 2 dias úteis sem resposta, 80.
  for q in select x.* from public.agenda_perguntas x where x.tipo = 'diaria' and x.estado = 'aberta'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'diaria',
      'texto', 'Diária, preciso de você: ' || public._agenda_texto_da_diaria(q.id),
      'perda', case when public.agenda_du_entre(coalesce(q.dia, q.perda_em, p_hoje), p_hoje) >= 2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (b) o que mudou sozinho (de verdade e na sombra), ainda não contado
  v_m := public._agenda_mudancas(v_ini, p_hoje, true, true, null);
  v_ms := public._agenda_mudancas(v_ini, p_hoje, false, true, null);

  -- (c) a semana publicada
  for g in select x from jsonb_array_elements(v_m) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', (g ->> 'desfazivel')::boolean, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids',
      'modo', case when cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  for g in select x from jsonb_array_elements(v_ms) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', false, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids', 'modo', 'sombra');
  end loop;

  -- (d) a conferência de hoje, com o que mudou sozinho; sem ela, o que mudou numa linha só
  select x.* into v_conf from public.agenda_perguntas x
   where x.tipo = 'conferencia' and x.estado = 'aberta' and x.dia = p_hoje
   order by (x.modo = 'ligado') desc, x.criada_em desc, x.id desc limit 1;
  -- FASE 3: o que a equipe confirmou, a diária que a agenda lançou, quem falta confirmar e o último dia da OS
  v_eq := public._agenda_dia_da_equipe(p_hoje);
  v_pend := v_eq -> 'pendentes';
  v_extra := nullif(array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'lig') x
                                          union all select x from jsonb_array_elements_text(v_eq -> 'ultimo') x), ' '), '');
  for m in select unnest(array['ligado', 'sombra']) loop
    v_txts := array(select public._agenda_mudanca_texto(x, false)
                      from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o)
                     where x ->> 'tipo' = 'acao' order by o);
    v_ids := coalesce((select jsonb_agg(y order by o, o2)
                         from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o),
                              jsonb_array_elements(x -> 'acao_ids') with ordinality u(y, o2)
                        where x ->> 'tipo' = 'acao'), '[]'::jsonb);
    v_mod := case when m = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end;
    if v_conf.id is not null and v_conf.modo = m then
      -- FASE 3: o texto do dia com a equipe. Sem nada a contar, é o da conferência, byte a byte.
      v_dia := v_conf.texto;
      if v_extra is not null or jsonb_array_length(v_pend) > 0 then
        v_base := case when right(v_conf.texto, char_length(c_cauda)) = c_cauda
                       then left(v_conf.texto, char_length(v_conf.texto) - char_length(c_cauda)) else v_conf.texto end;
        v_cauda := case
          when jsonb_array_length(v_pend) = 1
            then format(' Foi isso para o %s? *dia feito* lança a %s dele, ou conte o que mudou.', v_pend -> 0 ->> 'nome',
                        case when (v_pend -> 0 ->> 'meios')::int = 1 then 'meia diária' else 'diária' end)
          when jsonb_array_length(v_pend) > 1
            then format(' Foi isso para %s? *dia feito* lança as diárias deles, ou conte o que mudou.',
                        public._agenda_lista(array(select 'o ' || (e ->> 'nome') from jsonb_array_elements(v_pend) with ordinality t(e, o)
                                                    order by o), null))
          when (v_eq ->> 'aguardando')::int > 0 and cf.modo_diaria = 'ligado' then ' Foi isso? *dia feito* lança agora.'
          else c_cauda end;
        v_dia := v_base || coalesce(' ' || v_extra, '') || v_cauda;
      end if;
      v_ids := v_ids || (v_eq -> 'ids');
      for k in reverse cardinality(v_txts) .. 0 loop
        v_txt := v_dia
                 || case when k > 0 then ' Mudei sozinho: ' || array_to_string(v_txts[1:k], ' ')
                                         || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end
                         when cardinality(v_txts) > 0 then format(' Mudei sozinho %s: *o que mudou* mostra.',
                                                                   public._agenda_plural(cardinality(v_txts), 'coisa', 'coisas'))
                         else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', v_txt, 'perda', 70, 'pergunta_id', v_conf.id, 'acao_ids', v_ids,
        'modo', case when v_conf.modo = 'ligado' and cf.modo_vigia = 'ligado' and v_mod = 'ligado' then 'ligado' else 'sombra' end);
      -- FASE 3: o que a sombra da equipe e da diária diria, só no detalhe
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_som := v_dia || ' ' || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' ');
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_som, c_max), 'perda', 70,
                                             'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    elsif cardinality(v_txts) > 0 then
      for k in reverse cardinality(v_txts) .. 1 loop
        v_txt := 'Agenda, mudei sozinho. ' || array_to_string(v_txts[1:k], ' ')
                 || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'mudancas', 'texto', v_txt, 'perda', 40, 'pergunta_id', null, 'acao_ids', v_ids,
                                           'modo', v_mod);
    end if;
  end loop;
  -- a conferência na sombra sem nada a contar junto, ou de um modo sem mudança (o laço acima já cobriu quem teve)
  -- (nada a fazer: o laço passa pelos dois modos)

  -- FASE 3 (d1): sem a conferência aberta (todos confirmaram), o dia com o que a equipe e a diária contam numa linha
  -- própria: a diária que a agenda lançou ("*diária Roberto meia* corrige") e o último dia da OS.
  if v_conf.id is null and (v_extra is not null or jsonb_array_length(v_eq -> 'som') > 0) then
    v_base := public._agenda_texto_do_dia(p_hoje);
    if v_base is not null then
      v_cauda := case when jsonb_array_length(v_eq -> 'lancadas') > 0
                      then format(' *diária %s %s* corrige.', v_eq -> 'lancadas' -> 0 ->> 'nome',
                                  case when (v_eq -> 'lancadas' -> 0 ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end)
                      else '' end;
      if v_extra is not null then
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_base || ' ' || v_extra || v_cauda, c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', v_eq -> 'ids',
          'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
      end if;
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_out := v_out || jsonb_build_object('tipo', 'dia',
          'texto', public._agenda_corta(v_base || coalesce(' ' || v_extra, '') || ' '
                                        || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' '), c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    end if;
  end if;

  -- FASE 3 (d2): o que o gestor concluiu pela palavra do técnico (o técnico disse que terminou e era o último dia do
  -- plano), ainda não contado: a cobrança que a conclusão disse e o *desfaz* pelo número (a OS saiu da carteira).
  for q in select x.* from public.agenda_acoes x
            where x.tipo = 'concluir' and x.origem = 'equipe' and x.contada_em is null and x.desfeita_em is null
              and x.dia between v_ini and p_hoje
            order by x.criada_em, x.id loop
    v_tec := (select public._agenda_nome_curto(py.name) from public.agenda_equipe_mensagens em
                join public.payees py on py.id = em.payee_id where em.acao_id = q.id
               order by em.resposta_em desc nulls last limit 1);
    if q.executada then
      -- revisão da Fase 3 (item 5): o "vence hoje" de outro dia pelo ajudante único
      v_cob := public._agenda_vence_no_dia(regexp_replace(q.texto, '^[^—]* — saída [^.]*\.\s*', ''), q.dia, p_hoje);
      v_txt := format('Concluí o %s%s: o %s disse que terminou e era o último dia do plano.%s *desfaz %s* reabre.',
                      public._agenda_rotulo_da_os(q.service_order_id),
                      case when q.dia <> p_hoje then ' ' || public._dia_curto(q.dia) else '' end,
                      coalesce(v_tec, 'técnico'), coalesce(' ' || nullif(v_cob, q.texto), ''),
                      (select so.service_order_number from public.service_orders so where so.id = q.service_order_id));
    else
      v_txt := q.texto;
    end if;
    v_out := v_out || jsonb_build_object('tipo', 'conclusao', 'texto', public._agenda_corta(v_txt, c_max), 'perda', 45,
      'pergunta_id', null, 'acao_ids', jsonb_build_array(q.id),
      'modo', case when q.executada and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 7: (7a correção, achados 15 e 18; no lugar da linha (l) do 7a P11) (m) as perguntas do gestor que esperam o dono numa
  -- linha só: a ficha_estimativa de hoje (a ficha das 19:30 de um dia pela estimativa, que perde hoje), a situacao, a estimativa e
  -- o reestimar. Antes, cada uma disputava sozinha a vaga da pergunta de fato (e), de perda 30, e nenhuma chegava ao dono: o prazo
  -- só vale com a pergunta vista, e o gestor não marcava (Nelson, Flávio, Giancarlo e MP fora a semana inteira); a da ficha perdia
  -- para a mensagem ao cliente da véspera, e a ficha do 1º dia ficava segurada. A 1ª (a ficha; depois a de prazo mais perto) vai
  -- com o texto inteiro; as outras curtas, agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4
  -- dias; Flávio (OS-00104) 3,5 dias."; sem prazo: "Espero você: Giancarlo (OS-00130)."), até c_max_perg; o resto fica para
  -- *agenda gestor*. O fechamento que sai conta como mostradas todas as que a linha leva (pergunta_ids). Perda 75 com alguma de
  -- prazo (ela perde no prazo), 30 sem; modo = o da vigia.
  for m in select unnest(array['ligado', 'sombra']) loop
    v_f77_ids := '[]'::jsonb;
    v_f77_txt := null;
    v_f77_prazo := false;
    v_f77_segs := '{}';
    v_f77_grupo := null;
    v_f77_itens := '{}';
    v_f77_rest := 0;
    for v_f77_q in
      select x.id, x.texto, x.veto_ate, x.service_order_id, x.tipo,
             case when x.veto_ate is null then null
                  else public._dia_curto((x.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                       || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
             (select (o -> 'efeito' ->> 'dias')::numeric from jsonb_array_elements(coalesce(x.opcoes, '[]'::jsonb)) o
               where (o ->> 'n')::int = x.opcao_padrao limit 1) as dias_padrao
        from public.agenda_perguntas x
       where x.estado = 'aberta' and x.modo = m and not x.critica and x.opcao_escolhida is null
         and ((x.tipo = 'ficha_estimativa' and x.veto_ate is not null
               and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
              or (x.tipo in ('situacao', 'estimativa', 'reestimar')
                  and (x.veto_ate is null or (x.veto_ate at time zone 'America/Sao_Paulo')::date >= p_hoje)))
         and x.mostrada_vezes < cf.perguntas_vezes_max
         and not exists (select 1 from public.agenda_dono_avisos v
                          where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       order by x.tipo = 'ficha_estimativa' desc, x.veto_ate nulls last, x.criada_em, x.id
    loop
      if v_f77_txt is null then
        v_f77_txt := 'Agenda: ' || v_f77_q.texto;
        v_f77_ids := jsonb_build_array(v_f77_q.id);
        v_f77_prazo := v_f77_q.veto_ate is not null;
        continue;
      end if;
      if v_f77_rest > 0 then
        v_f77_rest := v_f77_rest + 1;
        continue;
      end if;
      -- (7a correção 2) sem prazo, o porquê junto: acima do teto de diárias o gestor não marca sozinho
      v_f77_nl := case when v_f77_q.ate is null then 'Espero você (não marco sozinho): ' else format('Também, sem resposta até %s: ', v_f77_q.ate) end;
      v_f77_item := public._agenda_rotulo_da_os(v_f77_q.service_order_id)
                    || case when v_f77_q.dias_padrao is not null then ' ' || public._agenda_dias(v_f77_q.dias_padrao) else '' end;
      if v_f77_nl is distinct from v_f77_grupo then
        v_f77_ns := v_f77_segs || case when v_f77_grupo is not null then array[v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.']
                                       else '{}'::text[] end;
        v_f77_ni := array[v_f77_item];
      else
        v_f77_ns := v_f77_segs;
        v_f77_ni := v_f77_itens || v_f77_item;
      end if;
      v_f77_l := v_f77_txt || ' ' || array_to_string(v_f77_ns || (v_f77_nl || array_to_string(v_f77_ni, '; ') || '.'), ' ');
      -- cabe com o "(e mais N em *agenda gestor*)" que pode vir depois
      if char_length(v_f77_l) > c_max_perg - 32 then
        v_f77_rest := 1;
        continue;
      end if;
      v_f77_segs := v_f77_ns;
      v_f77_grupo := v_f77_nl;
      v_f77_itens := v_f77_ni;
      v_f77_ids := v_f77_ids || to_jsonb(v_f77_q.id);
      v_f77_prazo := v_f77_prazo or v_f77_q.veto_ate is not null;
    end loop;
    continue when v_f77_txt is null;
    v_f77_l := v_f77_txt
               || case when v_f77_grupo is not null
                       then ' ' || array_to_string(v_f77_segs || (v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.'), ' ')
                       else '' end
               || case when v_f77_rest > 0 then format(' (e mais %s em *agenda gestor*)', v_f77_rest) else '' end;
    -- (7a correção 2, os achados 15/18 de novo) perda 76 com alguma de prazo: entre as linhas que perdem hoje ela ganha o desempate
    -- (antes, 75 com a mensagem ao cliente, ela perdia pelo tipo — "cliente" < "pergunta" — e saía primeiro no corte de 1.000)
    -- (7a correção 2) o objeto da linha entre parênteses: a forma curta (abaixo) entra nele, não como outro item da lista
    v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_f77_l, 'perda', case when v_f77_prazo then 76 else 30 end,
      'pergunta_id', v_f77_ids ->> 0, 'pergunta_ids', v_f77_ids, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end)
      -- (7a correção 2, o corte de 1.000 do fechamento) a mesma linha na forma curta (texto_curto), com as MESMAS perguntas: a
      -- ficha sem as opções ("… pela minha estimativa. Para segurar, me diga.") e cada uma pelo prazo e pelo que o gestor faz sem
      -- resposta ("Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; …"). O Secretário cheio (3 que ficaram, ~900
      -- caracteres) usa esta antes de tirar a linha — a inteira (~400) não cabia e as perguntas nunca eram vistas.
      || coalesce((select jsonb_build_object('texto_curto', k.t) from (select
           'Agenda: ' || concat_ws(' ',
             (select split_part(pc.texto, ' 1) Mande', 1) || ' Para segurar, me diga.' from public.agenda_perguntas pc
               where pc.id = (v_f77_ids ->> 0)::uuid and pc.tipo = 'ficha_estimativa'),
             (select string_agg(g.grupo || g.itens || '.', ' ' order by g.ord)
                from (select case when y.ate is null then 'Espero você (não marco sozinho): '
                                  else format('Sem resposta até %s, conto: ', y.ate) end as grupo,
                             string_agg(y.item, '; ' order by y.o) as itens, min(y.o) as ord
                        from (select t.o,
                                     case when pc.veto_ate is null then null
                                          else public._dia_curto((pc.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                                               || to_char(pc.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
                                     public._agenda_rotulo_da_os(pc.service_order_id)
                                     || coalesce(' ' || public._agenda_dias((select (op -> 'efeito' ->> 'dias')::numeric
                                                                               from jsonb_array_elements(coalesce(pc.opcoes, '[]'::jsonb)) op
                                                                              where (op ->> 'n')::int = pc.opcao_padrao limit 1)), '') as item
                                from jsonb_array_elements_text(v_f77_ids) with ordinality t(id, o)
                                join public.agenda_perguntas pc on pc.id = t.id::uuid
                               where pc.tipo <> 'ficha_estimativa') y
                       group by y.ate) g)) as t) k
         where char_length(k.t) < char_length(v_f77_l)), '{}'::jsonb));
  end loop;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) (n) a equipe: as perguntas abertas da equipe — a chamada (equipe_cadastro:chamada), a dos dias do
  -- dono (dias_semana), o telefone e o contato — numa linha só, nesta ordem e depois a mais antiga. Pela pergunta de fato (e), de perda
  -- 30, elas nunca entravam nas vagas (as de fornecedor estão abertas e nunca vistas desde 28/10): a chamada nunca seria vista nem
  -- venceria, e a pergunta da semana ficaria esperando por ela. A 1ª vai com o texto inteiro; as outras, curtas, até c_max_perg; o
  -- resto "(e mais N em *agenda equipe*)". pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas;
  -- a chamada vista ganha o prazo na rodada da semana). Perda 75 enquanto alguma nunca foi mostrada (o prazo só começa depois de vista)
  -- ou perde hoje (o veto_ate ou o perda_em de hoje): vaga própria entre as que perdem hoje; senão 30. Modo ligado só com a pergunta
  -- em ligado e o modo dela (o de _agenda_modo_da_pergunta: modo_dias; modo_cadastro fora de desligado, senão o do gestor) ligado.
  -- texto_curto = as mesmas perguntas só pelo nome. Só com modo_dias ou modo_cadastro fora de desligado (senão, o de antes); a (e)
  -- não as repete.
  v_7b_on := cf.modo_dias <> 'desligado' or cf.modo_cadastro <> 'desligado';
  -- (7c P5, R5.4 item 4, R5.10-8) o portão da linha separado por etapa: o bloco roda com a 7b (modo_dias ou modo_cadastro) OU com
  -- a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado; dentro dele, as perguntas da 7b só entram com o portão da 7b
  -- (v_7c_7b) e as de quem faz o quê só com o da 7c (v_7c_on). v_7b_on volta a ser só o da 7b logo depois do bloco: a pergunta de fato
  -- (e) exclui só os tipos que a (n) levou (sem isso, com a 7b desligada e a 7c em teste, a chamada da 7a sairia da (e), perda 30,
  -- para a (n), perda 75, e o texto do dono mudaria).
  v_7c_on := cf.modo_habilidade_propor <> 'desligado' or cf.modo_habilidade <> 'desligado';
  v_7c_7b := v_7b_on;
  v_7b_on := v_7b_on or v_7c_on;
  -- (7c: fim)
  -- (7c P8, R5.4 item 4) e com as etapas (modo_tarefas) fora de desligado: as perguntas das etapas (tarefa) só com o portão delas
  v_p8_on := cf.modo_tarefas <> 'desligado';
  v_7b_on := v_7b_on or v_p8_on;
  -- (7c: fim)
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
      -- (7c correção, achado 14) a 7b não gasta a vez dela por causa da 7c: sem nenhuma pergunta da 7b que perca hoje (nunca vista, o
      -- veto ou o prazo de hoje) e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia — a da
      -- 7c vai primeiro e inteira (conta como vista) e a chamada não é contada como mostrada num dia que não é o dela. Antes, com a de
      -- quem faz o quê só como "Também" (não conta), a perda 75 dela fazia a chamada sair e gastar as 2 vezes antes do dia em que vence,
      -- e quem faz o quê só era vista quando a chamada saía da linha. Com a 7b perdendo hoje, a de antes (a 7b primeiro). Sem a 7c, a de antes.
      v_c14_pula := v_7c_7b and (v_7c_on or v_p8_on)
        and not exists (select 1 from public.agenda_perguntas x
                         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
                           and x.mostrada_vezes < cf.perguntas_vezes_max
                           and not exists (select 1 from public.agenda_dono_avisos v
                                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                           and (x.mostrada_vezes = 0
                                or (x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                or x.perda_em is not distinct from p_hoje))
        and exists (select 1 from public.agenda_perguntas x
                     where x.estado = 'aberta' and x.modo = m and not x.critica
                       and ((v_7c_on and x.tipo = 'habilidade') or (v_p8_on and x.tipo = 'tarefa'))
                       and x.mostrada_vezes < cf.perguntas_vezes_max
                       and not exists (select 1 from public.agenda_dono_avisos v
                                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                       and (x.mostrada_vezes = 0
                            or (x.tipo = 'habilidade'
                                and ((x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                     or x.perda_em is not distinct from p_hoje))
                            or (x.tipo = 'tarefa' and x.chave not like 'tarefa:quem:%' and x.perda_em is not null and x.perda_em <= v_am1)));
      -- (7c: fim)
      for v_7b_q in
        select x.id, x.tipo, x.chave, x.texto, x.dia, x.mostrada_vezes, x.veto_ate, x.perda_em,
               coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = x.payee_id), '') as nome,
               case when x.tipo = 'dias_semana' then cf.modo_dias
                    when cf.modo_cadastro <> 'desligado' then cf.modo_cadastro
                    else public._agenda_gestor_modo('marcar') end as modo_agora
          from public.agenda_perguntas x
         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
           and x.mostrada_vezes < cf.perguntas_vezes_max
           and not exists (select 1 from public.agenda_dono_avisos v
                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
         order by case when x.chave like 'equipe_cadastro:chamada:%' then 1 when x.tipo = 'dias_semana' then 2
                       when x.chave like 'equipe_cadastro:telefone:%' then 3 else 4 end, x.criada_em, x.id
      loop
        -- (7c P5) as perguntas da equipe da 7b só com o portão da 7b (o bloco pode estar rodando só pela 7c)
        continue when not v_7c_7b;
        -- (7c: fim)
        -- (7c correção, achado 14) neste dia as da 7b esperam o dia delas (acima)
        continue when v_c14_pula;
        -- (7c: fim)
        v_7b_curto := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' then 'a equipe da agenda está certa?'
          when v_7b_q.tipo = 'dias_semana' then format('os dias da semana de %s', to_char(v_7b_q.dia, 'DD/MM'))
          when v_7b_q.chave like 'equipe_cadastro:telefone:%' then format('o telefone do %s', v_7b_q.nome)
          else format('%s na rotina da equipe?', v_7b_q.nome) end;
        if v_7b_txt is null then
          v_7b_txt := 'Agenda: ' || v_7b_q.texto;
        else
          if v_7b_rest > 0 then
            v_7b_rest := v_7b_rest + 1;
            continue;
          end if;
          v_7b_item := case
            when v_7b_q.chave like 'equipe_cadastro:telefone:%'
              then format('Também: o telefone do %s (sem ele não mando a ficha).', v_7b_q.nome)
            when v_7b_q.chave like 'equipe_cadastro:contato:%'
              then format('Também: %s tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*.', v_7b_q.nome)
            when v_7b_q.tipo = 'dias_semana'
              then format('Também: os dias da semana de %s (responda em *agenda pendências*).', to_char(v_7b_q.dia, 'DD/MM'))
            else 'Também: a chamada da equipe (responda em *agenda pendências*).' end;
          if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
            v_7b_rest := 1;
            continue;
          end if;
          v_7b_itens := v_7b_itens || v_7b_item;
        end if;
        v_7b_ids := v_7b_ids || to_jsonb(v_7b_q.id);
        -- (correção da revisão da 7b, achado 17) a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda
        -- pendências*)" não contam como mostradas: o dono não leu a pergunta (a dos dias, com a sugestão de quem chamar, contava como vista
        -- e vencia na quinta seguinte sem ele a ter lido). Elas ficam com mostrada_vezes 0 (a linha segue com perda 75) e saem inteiras no
        -- fechamento em que vierem primeiro. O telefone e o contato vão com a pergunta toda na forma curta e contam.
        if jsonb_array_length(v_7b_ids) > 1 and (v_7b_q.tipo = 'dias_semana' or v_7b_q.chave like 'equipe_cadastro:chamada:%') then
          v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
        end if;
        -- (correção da revisão da 7b: fim)
        -- (correção 3) a forma curta (texto_curto, a que o Secretário cheio usa) leva o prazo de cada pergunta que vence e o
        -- "sigo assim": o registro não sabe qual das formas saiu e conta como vistas todas as pergunta_ids (agenda_fechamento_registrar),
        -- então a chamada vista só como "a equipe da agenda está certa?" ganhava o prazo de equipe_chamada_prazo_du dias úteis sem o dono
        -- ter lido o "sigo assim". A data é a que o vencimento grava: a chamada contada aqui (a 1ª da linha; a do "Também" não conta, achado
        -- 17), com o cadastro fora de desligado, vence em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (a rodada da semana
        -- grava o veto_ate no tique seguinte; já gravado, o dele); a dos dias da semana, com modo_dias fora de desligado, vence no prazo da
        -- semana dela (o dia do plano em perda_em, hora_do_plano − equipe_dias_fechar_antes: o passo fechar de agenda_equipe_semana), vista
        -- ou não. O telefone e o contato não vencem: como antes. A forma longa não muda.
        v_c3_ate := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'desligado' and v_7b_ids ? v_7b_q.id::text
            then coalesce(v_7b_q.veto_ate,
                          public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo', cf.equipe_chamada_prazo_du))
          when v_7b_q.tipo = 'dias_semana' and cf.modo_dias <> 'desligado' and v_7b_q.perda_em is not null
            then ((v_7b_q.perda_em + cf.hora_do_plano) - cf.equipe_dias_fechar_antes) at time zone 'America/Sao_Paulo' end;
        if v_c3_ate is not null then
          v_7b_curto := v_7b_curto || format(' — sem resposta até %s às %s, sigo assim',
                                             public._dia_curto((v_c3_ate at time zone 'America/Sao_Paulo')::date),
                                             to_char(v_c3_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
        end if;
        -- (correção 3: fim)
        v_7b_curtos := v_7b_curtos || v_7b_curto;
        -- (correção da revisão da 7b, achado 7) a chamada da 7a (sem opções) é do gestor que marca, também com o cadastro da 7b
        -- em teste: a de antes, já aberta e ligada, não vira teste (o dono deixava de vê-la)
        if v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'ligado'
           and not exists (select 1 from public.agenda_perguntas p where p.id = v_7b_q.id and jsonb_array_length(p.opcoes) > 0) then
          v_7b_q.modo_agora := public._agenda_gestor_modo('marcar');
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_lig := v_7b_lig and v_7b_q.modo_agora = 'ligado';
        v_7b_perde := v_7b_perde or v_7b_q.mostrada_vezes = 0
                      or (v_7b_q.veto_ate is not null and (v_7b_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                      or v_7b_q.perda_em is not distinct from p_hoje;
      end loop;
      -- (7c P5, R5.4 item 4, R5.1-6, R5.10-7) as perguntas de quem faz o quê (habilidade), depois das da 7b: primeiro a da equipe
      -- (habilidade:equipe:…), depois as de OS (habilidade:os:…), e a mais antiga; só com o portão da 7c. A 1ª da linha vai inteira; as
      -- outras curtas, até c_max_perg ("Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)."; a de
      -- OS: "Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).").
      -- A da equipe que vai só como "Também" não conta como mostrada (sai de pergunta_ids: o achado 17 da 7b estendido) e sai inteira no
      -- fechamento em que vier primeiro; a de OS conta (vai com a pergunta toda, como o telefone e o contato). Na forma curta
      -- (texto_curto, a que o Secretário cheio usa — o registro não sabe qual forma saiu), a da equipe leva o que foi marcado e, quando é
      -- contada e vence (modo ligado), o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00,
      -- fica assim" (a data que _agenda_habilidade_vetos grava depois do registro: o veto_ate, ou _agenda_veto_ate do dia de hoje). O
      -- modo de cada uma é o de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade), que a linha não
      -- pode chamar (é só do service_role; a linha é lida pelo painel). A perda é a da (n): 75 enquanto alguma nunca foi vista inteira ou
      -- perde hoje.
      if v_7c_on then
        for v_7c_q in
          select x.id, x.tipo, x.chave, x.texto, x.modo, x.mostrada_vezes, x.veto_ate, x.perda_em,
                 coalesce(public._agenda_rotulo_da_os(x.service_order_id), '') as nome,
                 case when x.chave like 'habilidade:os:%' then cf.modo_habilidade else cf.modo_habilidade_propor end as modo_agora
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'habilidade'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'habilidade:equipe:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_7c_eq := v_7c_q.chave like 'habilidade:equipe:%';
          -- o que foi marcado (as propostas vivas da pergunta, lidas sob a RLS de agenda_etiquetas) e o que a OS pede
          v_7c_marc := case when v_7c_eq then nullif(public._agenda_lista(array(
                         select public._agenda_nome_curto(py.name) || ' ' || split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1)
                           from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
                          where e.pergunta_id = v_7c_q.id and e.estado = 'proposta'
                          order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                   public._agenda_nome_curto(py.name), e.id), null), '') end;
          v_7c_exig := case when not v_7c_eq then substring(v_7c_q.texto from ': o serviço pede (.*), e nas próximas ') end;
          v_7b_curto := case when v_7c_eq then 'quem faz o quê' || coalesce(' — marquei: ' || v_7c_marc, '')
                             else format('%s: falta %s', v_7c_q.nome, coalesce(v_7c_exig, 'quem o serviço pede')) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_7c_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := case
              when v_7c_eq then format('Também: quem faz o quê (%sresponda em *agenda pendências*).',
                                       coalesce('marquei: ' || v_7c_marc || '; ', ''))
              else format('Também: %s: falta %s; quem pode? (responda em *agenda pendências*).', v_7c_q.nome,
                          coalesce(v_7c_exig, 'quem o serviço pede')) end;
            -- (7c correção 2, achado 11) a de quem faz o quê da equipe, ligada (a pergunta e o modo dela), que vai como "Também" atrás de
            -- uma pergunta da 7b que perde hoje leva o que foi marcado E o prazo — o mesmo que a forma curta dela, que já contava como
            -- vista — e conta (abaixo). Antes, só como "Também: quem faz o quê (marquei: …; responda em *agenda pendências*)." ela nunca
            -- contava: na semana real a chamada (no dia do prazo) e depois o telefone do Alex iam primeiro, e o prazo nunca começava. Em
            -- teste, a de antes.
            v_c11_tambem := v_7c_eq and m = 'ligado' and v_7c_q.modo = 'ligado' and v_7c_q.modo_agora = 'ligado';
            if v_c11_tambem then
              v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
              v_7b_item := format('Também: quem faz o quê (%ssem resposta até %s às %s, fica assim; responda em *agenda pendências*).',
                                  coalesce('marquei: ' || v_7c_marc || '; ', ''),
                                  public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                  to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
            end if;
            -- (7c: fim)
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          if jsonb_array_length(v_7b_ids) > 1 and v_7c_eq then
            v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
          end if;
          -- (7c correção 2, achado 11) e a "Também" com o prazo conta: volta a pergunta_ids (o achado 17 da 7b a tirava)
          if v_c11_tambem and not v_7b_ids ? v_7c_q.id::text then
            v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          end if;
          v_c11_tambem := false;
          -- (7c: fim)
          if v_7c_eq and v_7c_q.modo = 'ligado' and v_7b_ids ? v_7c_q.id::text then
            v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
            v_7b_curto := v_7b_curto || format('; sem resposta até %s às %s, fica assim',
                                               public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                               to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
          end if;
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and v_7c_q.modo_agora = 'ligado';
          v_7b_perde := v_7b_perde or v_7c_q.mostrada_vezes = 0
                        or (v_7c_q.veto_ate is not null and (v_7c_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                        or v_7c_q.perda_em is not distinct from p_hoje;
        end loop;
      end if;
      -- (7c: fim)
      -- (7c P8, R5.4 item 4, R5.2-2(c)) as perguntas das etapas (tarefa), depois das de quem faz o quê: primeiro a de quem faça a etapa de
      -- risco (tarefa:quem:<os>), depois a de prazo (tarefa:prazo:<os>), e a mais antiga; só com o portão das etapas. A 1ª da linha vai
      -- inteira; as outras curtas, até c_max_perg ("Também: Lenine: quem vai junto em "…"? (responda em *agenda pendências*)."). As duas
      -- contam como mostradas (vão com a pergunta toda, como a de OS de quem faz o quê). O modo é o de _agenda_modo_da_pergunta
      -- (modo_tarefas), que a linha não pode chamar. A de prazo cujo prazo (perda_em) é hoje ou o próximo dia útil perde hoje.
      if v_p8_on then
        for v_p8_q in
          select x.id, x.chave, x.texto, x.mostrada_vezes, x.perda_em,
                 coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = x.service_order_id),
                          public._agenda_rotulo_da_os(x.service_order_id), '') as cli
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'tarefa'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'tarefa:quem:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_p8_quem := v_p8_q.chave like 'tarefa:quem:%';
          v_7b_curto := case when v_p8_quem then format('%s: quem vai junto%s?', v_p8_q.cli,
                                                         coalesce(' em ' || substring(v_p8_q.texto from '"[^"]+"'), ''))
                             else format('%s: as etapas não cabem até %s', v_p8_q.cli, public._dia_curto(v_p8_q.perda_em)) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_p8_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := format('Também: %s (responda em *agenda pendências*).', v_7b_curto);
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_p8_q.id);
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and cf.modo_tarefas = 'ligado';
          v_7b_perde := v_7b_perde or v_p8_q.mostrada_vezes = 0
                        or (not v_p8_quem and v_p8_q.perda_em is not null and v_p8_q.perda_em <= v_am1);
        end loop;
      end if;
      -- (7c: fim)
      continue when v_7b_txt is null;
      v_7b_l := array_to_string(array[v_7b_txt] || v_7b_itens, ' ')
                || case when v_7b_rest > 0 then format(' (e mais %s em *agenda equipe*)', v_7b_rest) else '' end;
      v_7b_curto := 'Agenda, equipe: ' || array_to_string(v_7b_curtos, '; ')
                    || case when right(v_7b_curtos[cardinality(v_7b_curtos)], 1) = '?' then '' else '.' end
                    || ' *agenda pendências* mostra.';
      v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_7b_l, 'perda', case when v_7b_perde then 75 else 30 end,
        'pergunta_id', v_7b_ids ->> 0, 'pergunta_ids', v_7b_ids, 'acao_ids', '[]'::jsonb,
        'modo', case when m = 'ligado' and v_7b_lig then 'ligado' else 'sombra' end)
        || case when char_length(v_7b_curto) < char_length(v_7b_l) then jsonb_build_object('texto_curto', v_7b_curto)
                else '{}'::jsonb end);
    end loop;
  end if;
  -- FASE 7b: fim
  -- FASE 7c: (7c P5, R5.10-8) o portão da 7b volta a ser só o dela: a (e) exclui as perguntas da 7b só com ele (e as de quem faz o quê
  -- só com o da 7c, abaixo)
  v_7b_on := v_7c_7b;
  -- FASE 7c: fim
  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max
     order by x.perda_em nulls last, x.criada_em, x.id limit 1;
    v_out := v_out || jsonb_build_object('tipo', 'pergunta',
      'texto', 'Agenda: ' || q.texto || case when v_n > 1 then format(' (e mais %s em *agenda pendências*)', v_n - 1) else '' end,
      'perda', 30, 'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 7c: (7c P8, R5.2-2(b), R5.10-6, -10, -13) (o) as etapas de quem não recebe pelo WhatsApp (sem telefone pela régua da 7a,
  -- _agenda_equipe_tem_telefone — a mesma do registro —, ou fora da lista da rotina) com etapa no plano de hoje ou do próximo dia útil: o
  -- que hoje devia ficar pronto (o dono passa e confere) e o que fazer amanhã, sem números (as listas do dia e a da OS numeram
  -- diferente), até c_max, cortando por etapa inteira ("e mais N"); o texto_curto para o Secretário cheio. Perda 75 só quando amanhã é
  -- o último dia de uma OS (a cobrança da véspera) ou volta primeiro uma pendente dita; senão 70 (a etapa de risco sozinha não sobe a
  -- perda). Tipo dia, sem pergunta: nada vence por ela. Em teste, modo sombra e "Em teste: " (vai ao detalhe, nunca ao texto do dono).
  -- Só com a porta das etapas aberta (o administrador ou o financeiro logado, ou sem login).
  if cf.modo_tarefas <> 'desligado' and (auth.uid() is null or public.is_admin_or_financial(auth.uid())) then
    for v_p8_pess in
      select x.payee_id, x.nome, public._agenda_equipe_tem_telefone(x.payee_id) as fone,
             exists (select 1 from public.agenda_equipe_contato c
                      where c.payee_id = x.payee_id and c.recebe_rotina and c.parou_em is null) as rotina
        from (select distinct a.payee_id, public._agenda_nome_curto(py.name) as nome
                from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
               where a.dia in (p_hoje, v_am1) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
                 and a.payee_id is distinct from public._agenda_dono(null)) x
       order by x.nome, x.payee_id
    loop
      continue when v_p8_pess.fone and v_p8_pess.rotina;
      v_p8_h := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, p_hoje, p_hoje);
      v_p8_a := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, v_am1, p_hoje);
      -- hoje: o que terminava e ainda não tem resultado (uma vez por etapa)
      v_p8_hi := coalesce((select jsonb_agg(i order by (i ->> 'n')::int) from jsonb_array_elements(v_p8_h -> 'itens') i
                            where (i ->> 'termina')::boolean and i -> 'resultado' = 'null'::jsonb
                              and not exists (select 1 from jsonb_array_elements(v_p8_hoje) j where j ->> 'tarefa' = i ->> 'tarefa')),
                           '[]'::jsonb);
      -- amanhã: o que a pessoa faz, por OS, com o último dia e a pendente dita que volta primeiro
      v_p8_ai := coalesce((select jsonb_agg(i || jsonb_build_object('nome', v_p8_pess.nome, 'payee', v_p8_pess.payee_id,
                                  'com', case when (i ->> 'com_dono')::boolean then 'você' end,
                                  'ultimo', (v_p8_a -> 'ultimo_dia') @> jsonb_build_array(jsonb_build_object('os', i ->> 'os')),
                                  'pdita', exists (select 1 from public.os_tarefas t where t.id = (i ->> 'tarefa')::uuid
                                                      and t.estado = 'viva' and t.pendente_vezes > 0))
                                order by (i ->> 'n')::int)
                           from jsonb_array_elements(v_p8_a -> 'itens') i), '[]'::jsonb);
      -- só quem tem o que conferir hoje ou o que fazer amanhã entra no "Etapas (… não tem telefone …)"
      continue when jsonb_array_length(v_p8_hi) = 0 and jsonb_array_length(v_p8_ai) = 0;
      v_p8_nomes := v_p8_nomes || v_p8_pess.nome;
      v_p8_nfone := coalesce(v_p8_nfone, 0) + case when v_p8_pess.fone then 0 else 1 end;
      v_p8_nrot := coalesce(v_p8_nrot, 0) + case when v_p8_pess.rotina then 0 else 1 end;
      v_p8_hoje := v_p8_hoje || v_p8_hi;
      v_p8_amanha := v_p8_amanha || v_p8_ai;
    end loop;
    -- (7c correção 2, achado 13) o dia útil de amanhã é dia de revisão (o 1º dia útil da semana ou do mês: a tarde do Secretário é a
    -- revisão, sem as linhas da agenda) — a véspera do último dia que cai no dia útil seguinte a ele nunca chegava ao dono (a OS que
    -- termina na terça; o dia útil depois de um feriado na segunda). A linha de hoje já cobra esse último dia, de quem trabalha amanhã;
    -- até 2 dias de revisão seguidos (a do mês e a da semana).
    v_c13_d := v_am1;
    for v_c13_k in 1 .. 2 loop
        select exists (
          with s as (
            select w.x, (select min(make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n)
                           from generate_series(0, 9) c13n
                          where extract(isodow from make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n) between 1 and 5
                            and public.agenda_feriado(make_date(extract(year from w.x)::int, extract(month from w.x)::int, 1) + c13n) is null) as rm
              from (select v_c13_d - (extract(isodow from v_c13_d)::int - 1) + c13n as x from generate_series(0, 4) c13n) w
          )
          select 1 where extract(isodow from v_c13_d) between 1 and 5 and public.agenda_feriado(v_c13_d) is null
            and (v_c13_d = (select s.rm from s where s.x = v_c13_d)
                 or v_c13_d = (select min(s.x) from s where extract(isodow from s.x) between 1 and 5 and public.agenda_feriado(s.x) is null
                                                  and s.x <> s.rm))) into v_c13_rev;
      exit when not v_c13_rev;
      v_c13_prox := public.agenda_somar_du(v_c13_d, 1);
      for v_c13_p in select distinct i ->> 'payee' as payee, i ->> 'nome' as nome from jsonb_array_elements(v_p8_amanha) i order by 2, 1 loop
        v_c13_u := public._agenda_tarefas_da_pessoa((v_c13_p.payee)::uuid, v_c13_prox, p_hoje) -> 'ultimo_dia';
        v_c13_av := v_c13_av || coalesce((select jsonb_agg(jsonb_build_object('dia', v_c13_prox, 'rev', v_c13_d, 'nome', v_c13_p.nome,
                                                                              'cliente', u ->> 'cliente', 'os', u ->> 'os') order by o)
                                            from jsonb_array_elements(coalesce(v_c13_u, '[]'::jsonb)) with ordinality t(u, o)), '[]'::jsonb);
      end loop;
      v_c13_d := v_c13_prox;
    end loop;
    -- (7c: fim)
    if jsonb_array_length(v_p8_hoje) > 0 or jsonb_array_length(v_p8_amanha) > 0 then
      v_p8_dia := case when v_am1 = p_hoje + 1 then 'Amanhã (' || public._dia_curto(v_am1) || ')'
                       else public._agenda_maiuscula(public._dia_curto(v_am1)) end;
      -- monta com até v_p8_k etapas por lista; corta por etapa inteira até caber em c_max
      v_p8_k := 5;
      loop
        v_p8_txt := format('Etapas (%s %s: quem passa e confere é você).', public._agenda_lista(v_p8_nomes, null),
                           case when v_p8_nfone = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não tem telefone' else 'não têm telefone' end
                                when v_p8_nrot = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não está na rotina da equipe' else 'não estão na rotina da equipe' end
                                else 'não recebem pelo WhatsApp' end);
        for v_p8_g in select i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_hoje) i group by i ->> 'cliente' order by 2 loop
          v_p8_txt := v_p8_txt || format(' Hoje no %s devia ficar pronto: %s.', v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, false, false));
        end loop;
        if jsonb_array_length(v_p8_hoje) > 0 then
          v_p8_txt := v_p8_txt || format(' Se faltou alguma, me diga qual (ex.: no %s falta "%s").', v_p8_hoje -> 0 ->> 'cliente',
                                         lower(left(v_p8_hoje -> 0 ->> 'texto', 1)) || substr(v_p8_hoje -> 0 ->> 'texto', 2));
        end if;
        for v_p8_g in select i ->> 'nome' as nome, i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             bool_or((i ->> 'ultimo')::boolean) as ult, jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                       order by i ->> 'nome', 3 loop
          v_p8_txt := v_p8_txt || format(' %s, %s no %s: %s.', v_p8_dia, v_p8_g.nome, v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, true, false))
                      || case when v_p8_g.ult then ' É o último dia: tem que ficar tudo pronto.' else '' end;
        end loop;
        -- (7c correção 2, achado 13) a cobrança do último dia depois do dia de revisão, sempre inteira: com o porquê, quando cabe; sem
        -- ele, quando não ("Qui 05/11 é o último dia do Lenine (Alex): tem que ficar tudo pronto."); o que não cabe sai das listas (o k)
        for v_c13_p in select a ->> 'dia' as dia, a ->> 'rev' as rev, a ->> 'nome' as nome, a ->> 'cliente' as cli
                         from jsonb_array_elements(v_c13_av) with ordinality t(a, o) order by o loop
          v_c13_q := format(' %s é o último dia do %s (%s): tem que ficar tudo pronto — aviso hoje porque %s é dia de revisão.',
                            public._agenda_maiuscula(public._dia_curto(v_c13_p.dia::date)), v_c13_p.cli, v_c13_p.nome,
                            public._dia_curto(v_c13_p.rev::date));
          if char_length(v_p8_txt || v_c13_q) + (case when cf.modo_tarefas = 'ligado' then 0 else 10 end) > c_max then
            v_c13_q := format(' %s é o último dia do %s (%s): tem que ficar tudo pronto.',
                              public._agenda_maiuscula(public._dia_curto(v_c13_p.dia::date)), v_c13_p.cli, v_c13_p.nome);
          end if;
          v_p8_txt := v_p8_txt || v_c13_q;
        end loop;
        -- (7c: fim)
        v_p8_txt := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end || v_p8_txt;
        exit when char_length(v_p8_txt) <= c_max or v_p8_k = 1;
        v_p8_k := v_p8_k - 1;
      end loop;
      v_p8_txt := public._agenda_corta(v_p8_txt, c_max);
      -- a forma curta (o Secretário cheio)
      v_p8_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                      then format('amanhã é o último dia do %s (%s, %s)', i ->> 'cliente', i ->> 'nome',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                      else format('amanhã, %s no %s (%s)', i ->> 'nome', i ->> 'cliente',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                            from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                           order by i ->> 'nome', min((i ->> 'n')::int))
                  || case when jsonb_array_length(v_p8_hoje) > 0
                          then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
      v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                    || 'Etapas: ' || array_to_string(v_p8_parte, '; ') || '.'
                    || case when jsonb_array_length(v_p8_amanha) > 0
                            then format(' Pergunte o que o %s faz amanhã.', v_p8_amanha -> 0 ->> 'nome') else '' end;
      v_p8_alta := exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean or (i ->> 'pdita')::boolean);
      -- (7c correção 2, achados 15 e 13) a forma curta com o dia quando o próximo dia útil não é amanhã (a sexta, a véspera de feriado:
      -- "seg 09/11 é o último dia do Lenine (Alex, 2 etapas). Pergunte o que o Alex faz na seg 09/11." — antes, "amanhã", e o "o que o
      -- Alex faz amanhã?" respondia pelo sábado) e com o último dia depois do dia de revisão; o último dia (o de amanhã ou o depois da
      -- revisão) marca a linha para subir com as outras de 75 (no fim). Sem nada disso, a de antes.
      if v_am1 <> p_hoje + 1 or jsonb_array_length(v_c13_av) > 0 then
        v_c13_q := case when v_am1 = p_hoje + 1 then 'amanhã' else public._dia_curto(v_am1) end;
        v_c13_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                         then format('%s é o último dia do %s (%s, %s)', v_c13_q, i ->> 'cliente', i ->> 'nome',
                                                     public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                         else format('%s, %s no %s (%s)', v_c13_q, i ->> 'nome', i ->> 'cliente',
                                                     public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                               from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                              order by i ->> 'nome', min((i ->> 'n')::int))
                       || array(select format('%s é o último dia do %s (%s)', public._dia_curto((a ->> 'dia')::date), a ->> 'cliente',
                                              a ->> 'nome')
                                  from jsonb_array_elements(v_c13_av) with ordinality t(a, o) order by o)
                       || case when jsonb_array_length(v_p8_hoje) > 0
                               then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
        v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                      || 'Etapas: ' || array_to_string(v_c13_parte, '; ') || '.'
                      || case when jsonb_array_length(v_p8_amanha) > 0
                              then format(' Pergunte o que o %s faz %s.', v_p8_amanha -> 0 ->> 'nome',
                                          case when v_am1 = p_hoje + 1 then 'amanhã' else 'na ' || public._dia_curto(v_am1) end)
                              else '' end;
      end if;
      v_p8_alta := v_p8_alta or jsonb_array_length(v_c13_av) > 0;
      v_c13_ult := cf.modo_tarefas = 'ligado'
                   and (jsonb_array_length(v_c13_av) > 0
                        or exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean));
      -- (7c: fim)
      v_out := v_out || (jsonb_build_object('tipo', 'dia', 'texto', v_p8_txt, 'perda', case when v_p8_alta then 75 else 70 end,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_tarefas = 'ligado' then 'ligado' else 'sombra' end)
        || case when char_length(v_p8_curto) < char_length(v_p8_txt) then jsonb_build_object('texto_curto', v_p8_curto)
                else '{}'::jsonb end);
    end if;
  end if;
  -- FASE 7c: fim
  -- FASE 3 (f): o PPC no último dia útil da semana (sexta; com feriado, o dia útil antes), se a semana teve compromisso
  v_ppc := public.agenda_ppc(p_hoje, p_hoje);
  if (v_ppc ->> 'ultimo_dia_util')::boolean and (v_ppc ->> 'compromissos')::int > 0 and v_ppc ->> 'linha' is not null then
    v_out := v_out || jsonb_build_object('tipo', 'ppc', 'texto', public._agenda_corta(v_ppc ->> 'linha', c_max), 'perda', 55,
      'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end if;

  -- FASE 3 (g): a comissão do mês que fechou, no 1º dia útil do mês (só a conta: nada é pago). Quem não pode ver a
  -- comissão (42501) não ganha a linha.
  if p_hoje = public.agenda_somar_du(make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1), 0) then
    begin
      v_com := public.comissao_resumo_do_mes(null, p_hoje);
    exception when sqlstate '42501' then
      v_com := null;
    end;
    if coalesce((v_com ->> 'primeiro_dia_util')::boolean, false) and nullif(v_com ->> 'linha', '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'comissao', 'texto', v_com ->> 'linha', 'perda', 20,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;

  -- FASE 7: (7a P7) (i) o "eu marcaria assim" do gestor em teste (spec §6.1): com o modo marcar em sombra, o texto_sombra do
  -- diário de hoje (a rodada do gestor das 16:52 o grava), perda 65, com o modo da vigia (o dono lê de verdade o que o gestor
  -- faria). (j) As compras da semana (agenda_gestor_dia.compras de hoje, que o P10 grava, [{texto, compre_ate, urgente}]): perda
  -- 80 com alguma compra urgente (AG7-07: o serviço começa a menos de compra_urgente_du dias úteis — vai como decisão), 65 com
  -- "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis; sem nada disso, nenhuma linha. O modo é o do compre_ate.
  if public._agenda_gestor_modo('marcar') = 'sombra' then
    select g.texto_sombra into v_f7_txt from public.agenda_gestor_dia g where g.dia = p_hoje;
    if nullif(btrim(v_f7_txt), '') is not null then
      -- (7a correção, achado 14) em teste, perda 25: abaixo de toda linha de verdade (só a comissão é menor) — a linha de teste
      -- não tira o lugar da semana publicada, da diária, da conclusão nem da pergunta que o dono precisa ver
      v_out := v_out || jsonb_build_object('tipo', 'gestor', 'texto', v_f7_txt, 'perda', 25, 'pergunta_id', null,
        'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  select g.compras into v_f7_cmp from public.agenda_gestor_dia g where g.dia = p_hoje;
  if jsonb_array_length(coalesce(v_f7_cmp, '[]'::jsonb)) > 0 then
    select min((e ->> 'compre_ate')::date), coalesce(bool_or((e ->> 'urgente')::boolean), false)
      into v_f7_min, v_f7_urg from jsonb_array_elements(v_f7_cmp) e;
    -- (7a correção, achado 19) o "compre até" de hoje (ou vencido, que comprando hoje ainda chega) é decisão de hoje: perda 80
    v_f7_perda := case when v_f7_urg or (v_f7_min is not null and v_f7_min <= p_hoje) then 80
                       when v_f7_min is not null and v_f7_min <= v_am1 then 65
                       when v_f7_min is not null and v_f7_min <= public.agenda_somar_du(p_hoje, cf.compras_aviso_du) then 45 end;
    v_f7_txt := array_to_string(array(select btrim(e ->> 'texto') from jsonb_array_elements(v_f7_cmp) with ordinality t(e, o)
                                       where nullif(btrim(e ->> 'texto'), '') is not null order by o), ' ');
    if v_f7_perda is not null and nullif(v_f7_txt, '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'compras', 'texto', public._agenda_corta('Compras: ' || v_f7_txt, c_max),
        'perda', v_f7_perda, 'pergunta_id', null, 'acao_ids', '[]'::jsonb,
        'modo', case when public._agenda_gestor_modo('compre_ate') = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  -- FASE 7: fim
  -- FASE 5: (h) a mensagem ao cliente, só com modo_cliente ligado: a que espera *manda cliente* e sai até o próximo dia de
  -- janela (perda 75; até 600 caracteres, c_max_cliente de _agenda_cliente_fechamento) e o que sai sozinho amanhã (perda 40,
  -- com *segura cliente*). As críticas (cliente_aviso) já entram pela linha decisao; o que saiu, pela linha mudancas.
  if cf.modo_cliente = 'ligado' then
    v_out := v_out || public._agenda_cliente_fechamento(p_hoje);
  end if;
  -- FASE 5: fim
  -- FASE 7c: (7c correção, achados 8 e 2) o fechamento cheio com uma linha da 7c ligada que perde hoje (a (o) "Etapas" ou a (n) com
  -- uma pergunta de quem faz o quê ou das etapas). O Secretário (textoDaTarde) encolhe só as linhas que têm forma curta antes de tirar
  -- uma, e a do cliente (75, a mensagem que espera *manda cliente*, até 600 letras) não tinha: com ela, a (o) e a (n) caíam (a semana
  -- real da revisão, 5 fechamentos com uma linha de cliente). Sem a 7c ligada (desligada ou em teste), a de antes, byte a byte.
  if exists (select 1 from jsonb_array_elements(v_out) x
              where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int >= 75
                and ((x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas%')
                     or exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                  join public.agenda_perguntas qq on qq.id = u.id::uuid
                                 where qq.tipo in ('habilidade', 'tarefa')))) then
    -- (8) a mensagem ao cliente ganha a forma curta (a coleta só a usa no fechamento enxuto, com linha garantida prestes a sair): quem,
    -- o tipo, quando sai e a palavra — "Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter
    -- 10/11 às 09:00); *agenda clientes* mostra." — com a mesma 1ª mensagem de _agenda_cliente_fechamento
    if cf.modo_cliente = 'ligado' then
      v_c8_agora := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
      select m2.tipo, m2.enviar_em, q2.id,
             public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)), count(*) over ()
        into v_c8_tipo, v_c8_env, v_c8_qid, v_c8_nome, v_c8_n
        from public.agenda_cliente_mensagens m2
        join public.agenda_perguntas q2 on q2.id = m2.pergunta_id
        join public.clients cl on cl.id = m2.client_id
       where m2.modo = 'ligado' and m2.estado = 'aguardando_dono' and m2.aprovacao = 'pedida'
         and q2.tipo = 'cliente_aprovar' and q2.estado = 'aberta'
         and (m2.enviar_em at time zone 'America/Sao_Paulo')::date <= public._agenda_cliente_dia_seguinte(p_hoje)
       order by m2.enviar_em, cl.name, m2.tipo, m2.id
       limit 1;
      if v_c8_qid is not null then
        v_c8_curto := case when v_c8_n > 1
          then format('Mensagem para %s (%s) e mais %s esperam *manda cliente* (a 1ª sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_n - 1, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora))
          else format('Mensagem para %s (%s) espera *manda cliente %s* (sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_nome, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora)) end;
        v_out := (select coalesce(jsonb_agg(case when x ->> 'tipo' = 'cliente' and (x ->> 'perda')::int = 75
                                                  and x ->> 'pergunta_id' = v_c8_qid::text and not x ? 'texto_curto'
                                                  and char_length(v_c8_curto) < char_length(x ->> 'texto')
                                             then x || jsonb_build_object('texto_curto', v_c8_curto) else x end order by o), '[]'::jsonb)
                    from jsonb_array_elements(v_out) with ordinality t(x, o));
      end if;
    end if;
    -- (2) a (n) com uma pergunta de quem faz o quê ou das etapas, ligada, contada na linha e nunca vista há c_c2_dias dias úteis (ela
    -- perdeu c_c2_dias fechamentos: com a compra (80) e as perguntas do gestor (76), as três não cabem nem na forma curta, e a de menor
    -- perda saía todo dia — o prazo nunca corria e a proposta nunca valia) sobe a c_c2_perda: neste dia sai a de menor perda das outras
    -- (a das perguntas do gestor, ou uma de 75), uma vez, e no dia seguinte, vista, ela volta à de sempre. Não sobe se a linha que ela
    -- tiraria (perda 76 a 79) perde algo hoje: a ficha de amanhã (ficha_estimativa) ou um prazo (veto ou perda) de hoje.
    if not exists (select 1 from jsonb_array_elements(v_out) x
                    where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int between 76 and 79
                      and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                    join public.agenda_perguntas qq on qq.id = u.id::uuid
                                   where qq.tipo = 'ficha_estimativa'
                                      or (qq.veto_ate is not null and (qq.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                      or qq.perda_em is not distinct from p_hoje)) then
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 75
                                                and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                                              join public.agenda_perguntas qq on qq.id = u.id::uuid
                                                             where qq.tipo in ('habilidade', 'tarefa') and qq.modo = 'ligado'
                                                               and qq.estado = 'aberta' and qq.mostrada_vezes = 0
                                                               and public.agenda_du_entre((qq.criada_em at time zone 'America/Sao_Paulo')::date,
                                                                                          p_hoje) >= c_c2_dias)
                                           then jsonb_set(x, '{perda}', to_jsonb(c_c2_perda)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    end if;
  end if;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção 2, achados 1 e 13) quando uma linha da 7c ligada espera demais — a (n) com quem faz o quê nunca vista há
  -- c_c2_dias dias úteis (a 100580 a subiu a c_c2_perda, acima) ou a (o) "Etapas" da véspera do último dia (o de amanhã ou o depois
  -- de um dia de revisão) —, sobem a c_c2_perda TODAS as linhas ligadas de 75 (as que perdem hoje: a mensagem ao cliente que espera
  -- *manda cliente*, a (o), a (n)), na ordem de sempre entre elas. Quem sai no corte de 1.000 é a pergunta do gestor (76) que não perde
  -- hoje — ela espera um dia —, nunca a mensagem ao cliente (antes, só a (n) subia: com 4 linhas de 75 ou mais, saía o cliente, a de
  -- menor perda). Não sobe se uma linha de 76 a 79 perde algo hoje (a ficha de amanhã, um veto ou um prazo de hoje: a mesma guarda
  -- da 100580). Só com a pergunta do gestor de 76 para ceder; sem ela, nada passa à frente, e a (n) que a 100580 subiu volta a 75 (ela
  -- só tiraria o lugar de outra de 75). A vaga garantida não muda (75 e 77 contam igual). Sem a 7c ligada, nada disto acontece.
  if (exists (select 1 from jsonb_array_elements(v_out) x
               where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = c_c2_perda)
      or (v_c13_ult
         and exists (select 1 from jsonb_array_elements(v_out) x
                      where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas%' and (x ->> 'perda')::int = 75)
         and not exists (select 1 from jsonb_array_elements(v_out) x
                          where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int between 76 and 79
                          and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                        join public.agenda_perguntas qq on qq.id = u.id::uuid
                                       where qq.tipo = 'ficha_estimativa'
                                          or (qq.veto_ate is not null and (qq.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                          or qq.perda_em is not distinct from p_hoje)
                         ))) then
    if exists (select 1 from jsonb_array_elements(v_out) x where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 76) then
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and (x ->> 'perda')::int = 75
                                               then jsonb_set(x, '{perda}', to_jsonb(c_c2_perda)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    else
      -- sem a de 76, a (n) que a 100580 subiu só passaria à frente das outras de 75 (a mensagem ao cliente): volta a 75
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = c_c2_perda
                                               then jsonb_set(x, '{perda}', to_jsonb(75)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    end if;
  end if;
  -- FASE 7c: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o R5.10-7): na linha (n) da equipe, a forma curta (texto_curto, a que o Secretário cheio usa, e o registro conta as pergunta_ids da linha sem saber qual forma saiu) leva, em cada pergunta que vence, o prazo e o "sigo assim" — "Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra." —, com a data que o vencimento grava: a chamada contada na linha, com o cadastro fora de desligado, em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (ou o veto_ate já gravado); a dos dias da semana, com modo_dias fora de desligado, no prazo da semana dela (perda_em, hora_do_plano − equipe_dias_fechar_antes). O telefone e o contato não vencem: como antes. A forma longa e o resto, byte a byte. FASE 7c (P5, R5.4 item 4, R5.1-6, R5.10-7/-8): o portão da linha (n) passa a "a 7b (modo_dias ou modo_cadastro) OU a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado"; dentro dela, as perguntas da 7b só com o portão da 7b e, depois delas, as de quem faz o quê (habilidade: primeiro a habilidade:equipe, depois as habilidade:os) só com o da 7c, com o modo de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade). A da equipe que vai só como "Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)." fica fora de pergunta_ids (não conta como vista); a de OS ("Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).") conta. A forma curta leva o que foi marcado e, na da equipe contada e ligada, o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00, fica assim" (o veto_ate, ou _agenda_veto_ate do dia de hoje: a data que _agenda_habilidade_vetos grava depois do registro). A pergunta de fato (e) exclui as da 7b só com o portão da 7b e as de quem faz o quê só com o da 7c. Com os modos da 7c desligados, a saída de antes, byte a byte (com a 7b desligada e em teste). FASE 7c (P8, R5.4 item 4, R5.2-2(b) e (c)): com modo_tarefas fora de desligado, a linha (n) leva também as perguntas das etapas (tarefa:quem:<os>, depois tarefa:prazo:<os>; a de prazo que vence hoje ou no próximo dia útil perde hoje), só com o portão delas, e a (e) não as repete; e a linha (o) das etapas (tipo dia; até 480, sem números): a quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) com etapa hoje ou no próximo dia útil — "Etapas (Alex não tem telefone: quem passa e confere é você). Hoje no Lenine devia ficar pronto: …. Se faltou alguma, me diga qual (…). Amanhã (qui 05/11), Alex no Lenine: Terminar: …; … — com você. É o último dia: tem que ficar tudo pronto." —, texto_curto "Etapas: amanhã é o último dia do Lenine (Alex, 2 etapas); hoje, 2 para conferir. Pergunte o que o Alex faz amanhã.", perda 75 só com o último dia de uma OS amanhã ou com uma pendente dita que volta primeiro (senão 70), sem pergunta; em teste, modo sombra e "Em teste: ". Com modo_tarefas desligado, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7c (20261102100580): (achado 14) na linha (n), sem nenhuma pergunta da 7b que perca hoje e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia (a da 7c vai primeiro, inteira, e conta como vista; a chamada não gasta a vez dela num dia que não é o seu); (achado 8) com uma linha da 7c ligada de perda >= 75 (a (o) "Etapas" ou a (n) com pergunta de quem faz o quê ou das etapas), a linha do cliente de perda 75 ganha a forma curta ("Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter 10/11 às 09:00); *agenda clientes* mostra."; com mais de uma, "… e mais N esperam *manda cliente* (a 1ª sai …) …"), para o Secretário cheio encolher a do cliente antes de tirar a da 7c; (achado 2) a (n) com uma pergunta de quem faz o quê ou das etapas ligada, contada, aberta e nunca vista há 2 dias úteis ou mais sobe de 75 a 77 (acima das perguntas do gestor, abaixo da compra e da decisão), salvo se uma linha de perda 76 a 79 perde algo hoje (a ficha de amanhã, um veto ou um prazo de hoje). Sem a 7c ligada, a de antes, byte a byte. CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590): (achados 1 e 13) com a (n) de quem faz o quê nunca vista há 2 dias úteis (a que a 100580 sobe a 77) ou com a (o) "Etapas" ligada da véspera do último dia, todas as linhas ligadas de 75 sobem a 77 juntas quando há a pergunta do gestor de 76 para ceder (sai no corte a de 76, que não perde hoje, nunca a mensagem ao cliente) — sem ela, a (n) que a 100580 sobe volta a 75 —, salvo com uma linha de 76 a 79 que perde algo hoje; (achado 13) quando o próximo dia útil é dia de revisão da tarde (o 1º dia útil da semana ou do mês: turnoDaTarde), a (o) de hoje já cobra o último dia que cai no dia útil seguinte ("Ter 10/11 é o último dia do Lenine (Alex): tem que ficar tudo pronto — aviso hoje porque seg 09/11 é dia de revisão."), também na forma curta, com perda 75; (achado 15) a forma curta da (o) diz o dia ("seg 09/11", "Pergunte o que o Alex faz na seg 09/11.") quando o próximo dia útil não é amanhã; (achado 11) a de quem faz o quê da equipe, ligada, que vai como "Também" leva o que foi marcado e o prazo e conta como vista. Sem a 7c ligada, a de antes.';

-- _agenda_tarefas_planejar (de 20261102100580_agenda_fase77c_correcao.sql)
create or replace function public._agenda_tarefas_planejar(p_os uuid, p_hoje date, p_modo text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_resto  constant numeric := 0.25;    -- estrutural (spec §16.3.6): a etapa começada pede ao menos ¼ de meio-dia
  c_resid  constant numeric := 0.001;   -- estrutural: o resíduo das frações (3 casas) não é etapa a fazer
  c_folga  constant numeric := 0.01;    -- estrutural: a sobra de um meio-dia abaixo disso não leva outra etapa
  cf       public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_n      jsonb;
  v_total  numeric;
  v_soma   numeric;
  v_ids    uuid[] := '{}';
  v_meios  numeric[] := '{}';
  v_need   numeric[] := '{}';
  v_ex     int[] := '{}';
  v_fin    boolean[] := '{}';
  v_ini    boolean[] := '{}';
  v_pend   boolean[] := '{}';
  v_pdia   date[] := '{}';
  v_ord    numeric[] := '{}';
  v_at     boolean[] := '{}';
  v_k      int;
  e        record;
  l        record;
  r        record;
  v_md     jsonb := '[]'::jsonb;
  v_hab    jsonb := '{}'::jsonb;
  v_fone   jsonb := '{}'::jsonb;
  v_dalt   int;
  v_lid    uuid;
  h        record;
  v_pes    uuid[];
  v_out    jsonb := '[]'::jsonb;
  v_itens  jsonb;
  v_cap    numeric;
  v_pos    int;
  v_f      numeric;
  v_term   boolean;
  v_fila   int[];
  v_atende boolean;
  v_mask   int;
  v_resp   uuid;
  v_prazo  date;
  v_snap   numeric;
  v_ate    int := 0;
  v_falta  numeric;
  v_futuro int := 0;
  v_faltam uuid[];
  m        jsonb;
  -- FASE 7c: (7c correção 2, achado 12) a duração do plano e a dupla da OS
  v_c12_plano numeric;
  v_c12_dup   jsonb;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achado 10) o total da OS e o que ela já fez antes de ter etapas neste modo
  v_c10_tot  numeric;
  v_c10_sem  numeric;
  -- FASE 7c: fim
begin
  if p_os is null or p_hoje is null or p_modo is null or p_modo not in ('sombra', 'ligado') then
    raise exception 'Faltam a OS, o dia e o modo (sombra ou ligado) para planejar as etapas.' using errcode = '22023';
  end if;
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);
  v_total := nullif((public.agenda_meios_da_os(p_os, p_hoje) ->> 'total')::numeric, 0);
  select coalesce(sum(x.horas), 0) into v_soma from public.os_tarefas x where x.service_order_id = p_os and x.estado in ('viva', 'feita');

  -- FASE 7c: (7c correção 2, achado 12) as etapas somam a duração do PLANO. Com a dupla inferida da 7b ligada, agenda_meios_da_os conta
  -- os meios-dias da dupla (o meio-dia em dupla rende 2: Lenine 12 → 10), mas, sem a 2ª pessoa, o motor marca 1 só (o bloco de 1
  -- pessoa da 7b: o Alex sozinho de qui 05 a qui 12/11, 12 meios-dias). Repartidas por 10, as etapas acabavam um dia antes do plano: o
  -- último dia ficava sem o que fazer e a cobrança da véspera ("É o último dia") nunca saía. A duração do plano: os meios-dias marcados
  -- da OS de hoje em diante (alocação vigente de turno, sem reserva) mais os passados pelo resultado (a régua do achado 10: cumprido,
  -- sem registro ou sem resultado = 1; parcial = meio; não cumprido = 0). Vale só com a dupla da 7b ligada (ni + nf > 0, a que encolhe
  -- o total) e quando o plano é maior que a da OS, até as diárias-pessoa da estimativa (pm, a duração de 1 pessoa): o plano ainda
  -- parcial, o mais longo por outro motivo e a dupla em teste ficam com a da OS, como antes. O total da saída passa a ser este.
  if v_total is not null then
    select trim_scale(coalesce(sum(case when y.dia >= p_hoje then 2 else y.peso end), 0)::numeric / 2) into v_c12_plano
      from (select a.dia, a.turno,
                   max(case when a.resultado in ('cumprido', 'sem_registro') or a.resultado is null then 2
                            when a.resultado = 'parcial' then 1 else 0 end) as peso
              from public.agenda_alocacoes a
             where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.presenca = 'turno'
             group by a.dia, a.turno) y;
    if v_c12_plano > v_total then
      v_c12_dup := public.agenda_meios_da_os(p_os, p_hoje) -> 'dupla';
      if v_c12_dup ->> 'modo' = 'ligado' and coalesce((v_c12_dup ->> 'ni')::int, 0) + coalesce((v_c12_dup ->> 'nf')::int, 0) > 0 then
        v_total := least(v_c12_plano, coalesce((v_c12_dup ->> 'pm')::numeric, v_c12_plano));
      end if;
    end if;
  end if;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achado 10) os meios-dias que a OS já fez ANTES de ter etapas neste modo (a OS começada antes de as etapas
  -- nascerem ou de serem ligadas) saem do total: cada etapa pede a sua parte do que FALTA. Sem isso, o Edu (3 dias ditos, 1 feito pelo
  -- Roberto sem linha de etapa) pedia os 3 dias inteiros, e o dono recebia "não cabe até o prazo" com o plano exato dos 2 que faltam.
  -- A conta é a do plano da OS (_agenda_plano_da_os, d20): cada meio-dia passado de turno, sem reserva, vigente, pelo melhor resultado
  -- (cumprido, sem registro ou passado sem resultado = 1; parcial = meio; não cumprido = 0), só os que não têm nenhuma linha de etapa
  -- neste modo (os que têm já descontam pela linha, abaixo). Sem nada a descontar, o de antes; sem sobrar nada, a conta pelas horas. O
  -- total da saída continua o da OS.
  v_c10_tot := v_total;
  if v_total is not null then
    select coalesce(sum(y.peso), 0)::numeric / 2 into v_c10_sem
      from (select a.dia, a.turno,
                   max(case when a.resultado in ('cumprido', 'sem_registro') or a.resultado is null then 2
                            when a.resultado = 'parcial' then 1 else 0 end) as peso
              from public.agenda_alocacoes a
             where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.presenca = 'turno' and a.dia < p_hoje
             group by a.dia, a.turno) y
     where not exists (select 1 from public.os_tarefas_dia d
                        where d.service_order_id = p_os and d.dia = y.dia and d.turno = y.turno and d.modo = p_modo
                          and d.estado = 'planejada');
    if v_c10_sem > 0 then
      v_total := nullif(greatest(v_total - v_c10_sem, 0), 0);
    end if;
  end if;
  -- FASE 7c: fim
  -- 1. As etapas vivas, cada uma com o que ainda pede (need), pelo que o plano congelado de antes de hoje levou.
  for e in select x.* from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' order by x.ordem, x.id loop
    v_ids := v_ids || e.id;
    v_ord := v_ord || e.ordem;
    v_ex := v_ex || e.exige::int;
    v_fin := v_fin || (e.chave = 'entrega');
    v_meios := v_meios || case when v_total is not null and v_soma > 0 then e.horas / v_soma * v_total
                               else e.horas / (cf.jornada_horas / 2) end;
    v_k := cardinality(v_ids);
    v_need := v_need || v_meios[v_k];
    v_ini := v_ini || false;
    v_pend := v_pend || false;
    v_pdia := v_pdia || null::date;
    v_at := v_at || false;
    for l in select d.* from public.os_tarefas_dia d
              where d.tarefa_id = e.id and d.modo = p_modo and d.estado = 'planejada' and d.dia < p_hoje
              order by d.dia, d.turno = 'tarde', d.posicao loop
      v_need[v_k] := v_need[v_k] - l.fracao;
      v_ini[v_k] := true;
      if l.termina then
        if l.resultado = 'pendente' then
          v_need[v_k] := cf.tarefas_pendente_meios;
          v_ini[v_k] := false;
          v_pend[v_k] := true;
          v_pdia[v_k] := l.dia;
        else
          -- feita, sem registro (R5.2-3) ou ainda sem resultado: conta como feita para o plano
          v_need[v_k] := 0;
          v_ini[v_k] := false;
          v_pend[v_k] := false;
        end if;
      end if;
    end loop;
    if v_ini[v_k] and v_need[v_k] > 0 then
      v_need[v_k] := greatest(v_need[v_k], c_resto);
    elsif v_ini[v_k] and v_need[v_k] <= 0 then
      v_need[v_k] := c_resto;
    end if;
  end loop;
  -- FASE 7c: (7c correção, achado 10) o total da saída é o da OS (o descontado só reparte o que falta entre as etapas)
  v_total := v_c10_tot;
  -- FASE 7c: fim
  v_falta := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
  v_faltam := array(select v_ids[k] from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid
                     order by case when v_pend[k] then 0 when v_ini[k] then 1 else 2 end, v_pdia[k] nulls last, v_ord[k], k);

  -- 2. Os meios-dias da OS de hoje em diante (alocação vigente de turno, sem reserva): a equipe (sem o dono), o dono no turno, na
  -- abertura e no fechamento.
  select coalesce(jsonb_agg(jsonb_build_object('dia', x.dia, 'turno', x.turno, 'equipe', to_jsonb(x.eq), 'dono_turno', x.dt,
                                               'dono_fecha', x.df, 'dono_abre', x.da) order by x.dia, x.turno = 'tarde'), '[]'::jsonb)
    into v_md
    from (select a.dia, a.turno,
                 coalesce(array_agg(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono), '{}'::uuid[]) as eq,
                 coalesce(bool_or(a.payee_id is not distinct from v_dono), false) as dt,
                 exists (select 1 from public.agenda_alocacoes b
                          where b.service_order_id = p_os and b.dia = a.dia and b.turno = a.turno and b.presenca = 'fechamento'
                            and b.payee_id is not distinct from v_dono and b.estado in ('publicada', 'fixada')) as df,
                 exists (select 1 from public.agenda_alocacoes b
                          where b.service_order_id = p_os and b.dia = a.dia and b.turno = a.turno and b.presenca = 'abertura'
                            and b.payee_id is not distinct from v_dono and b.estado in ('publicada', 'fixada')) as da
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
             and a.dia >= p_hoje
           group by a.dia, a.turno) x;

  -- As habilidades (uma leitura: as etiquetas efetivas, qualquer que seja o modo_habilidade, §16.3.5), quem recebe pelo WhatsApp e o
  -- responsável da OS.
  v_pes := array(select distinct u.x::uuid from jsonb_array_elements(v_md) d, jsonb_array_elements_text(d -> 'equipe') u(x));
  for h in select * from public.agenda_habilidades(p_hoje, v_pes || v_dono) loop
    v_hab := v_hab || jsonb_build_object(h.payee_id::text, jsonb_build_object('i', h.instala, 'c', h.comissiona, 'a', h.altura,
                                                                             'p', h.papel, 'n', h.nome));
    if h.eh_dono then
      v_dalt := h.altura;
    end if;
    v_fone := v_fone || jsonb_build_object(h.payee_id::text,
      public._agenda_equipe_tem_telefone(h.payee_id)
      and exists (select 1 from public.agenda_equipe_contato c where c.payee_id = h.payee_id and c.recebe_rotina and c.parou_em is null));
  end loop;
  v_lid := (public._agenda_lider_da_os(p_os, p_hoje) ->> 'payee_id')::uuid;
  v_prazo := (public.os_prontidao(p_os, p_hoje) ->> 'prazo_efetivo')::date;
  if v_prazo is null and jsonb_array_length(v_md) > 0 then
    v_prazo := (v_md -> -1 ->> 'dia')::date;
  end if;

  -- 3. Cada meio-dia, na ordem.
  for m in select d from jsonb_array_elements(v_md) d loop
    if v_snap is null and v_prazo is not null and (m ->> 'dia')::date > v_prazo then
      v_snap := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
    end if;
    -- o plano até o prazo: os meios-dias que ainda vão acontecer (o de hoje já congelado e todo respondido não conta mais)
    if v_prazo is not null and (m ->> 'dia')::date <= v_prazo
       and ((m ->> 'dia')::date > p_hoje
            or not exists (select 1 from public.os_tarefas_dia d
                            where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                              and d.estado = 'planejada')
            or exists (select 1 from public.os_tarefas_dia d
                        where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                          and d.estado = 'planejada' and d.termina and d.resultado is null)) then
      v_ate := v_ate + 1;
    end if;
    v_itens := '[]'::jsonb;
    if exists (select 1 from public.os_tarefas_dia d
                where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                  and d.estado = 'planejada') then
      -- congelado: entra com as linhas dele, sem refazer
      v_resp := null;
      for l in select d.* from public.os_tarefas_dia d
                where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                  and d.estado = 'planejada'
                order by d.posicao, d.id loop
        v_resp := l.responde;
        v_k := array_position(v_ids, l.tarefa_id);
        if v_k is not null then
          v_need[v_k] := v_need[v_k] - l.fracao;
          v_ini[v_k] := true;
          v_pend[v_k] := false;
          if l.termina then
            if l.resultado = 'pendente' then
              v_need[v_k] := cf.tarefas_pendente_meios;
              v_ini[v_k] := false;
              v_pend[v_k] := true;
              v_pdia[v_k] := l.dia;
            else
              v_need[v_k] := 0;
              v_ini[v_k] := false;
            end if;
          elsif v_need[v_k] <= 0 then
            v_need[v_k] := c_resto;
          end if;
        end if;
        v_itens := v_itens || jsonb_build_array(jsonb_build_object('tarefa', l.tarefa_id, 'fracao', l.fracao, 'termina', l.termina,
                                                                   'comeca', l.comeca, 'posicao', l.posicao, 'linha_id', l.id,
                                                                   'resultado', l.resultado));
      end loop;
      v_out := v_out || jsonb_build_array(m || jsonb_build_object('congelado', true, 'responde', v_resp, 'itens', v_itens,
        'equipe', coalesce((select to_jsonb(d.equipe) from public.os_tarefas_dia d
                             where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno'
                               and d.modo = p_modo and d.estado = 'planejada' order by d.posicao limit 1), m -> 'equipe')));
      continue;
    end if;

    v_futuro := v_futuro + 1;
    v_cap := 1;
    v_pos := 0;
    -- a fila deste meio-dia: a pendente (pela data, depois a ordem), a começada, as outras (pela ordem)
    v_fila := array(select k from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid
                     order by case when v_pend[k] then 0 when v_ini[k] then 1 else 2 end, v_pdia[k] nulls last, v_ord[k], k);
    foreach v_k in array v_fila loop
      -- o fechamento do dono (com habilidade_fechamento_cobre) cobre a etapa final inteira e o comissionar e o diagnóstico das outras
      -- (o que é do dono, AG7-02); o 220 V e o teto pedem quem os faz na equipe do meio-dia
      v_mask := case when (m ->> 'dono_fecha')::boolean and cf.habilidade_fechamento_cobre
                     then case when v_fin[v_k] then 0 else v_ex[v_k] & ~10 end
                     else v_ex[v_k] end;
      if v_mask = 0 then
        v_atende := true;
      else
        v_atende := public._agenda_atende(
          v_mask,
          array(select (v_hab -> u.x ->> 'i')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'c')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'a')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'p')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          (m ->> 'dono_turno')::boolean, v_dalt, v_n) is null;
      end if;
      if not v_atende then
        continue;   -- espera um meio-dia que atenda; as outras seguem
      end if;
      v_at[v_k] := true;
      continue when v_cap <= c_folga;
      v_f := least(v_need[v_k], v_cap);
      v_term := v_need[v_k] - v_f <= c_folga;
      if v_term then
        v_f := v_need[v_k];
      end if;
      v_f := least(greatest(round(v_f, 3), c_resid), 1);
      v_pos := v_pos + 1;
      v_itens := v_itens || jsonb_build_array(jsonb_build_object('tarefa', v_ids[v_k], 'fracao', v_f, 'termina', v_term,
                                                                 'comeca', not v_ini[v_k], 'posicao', v_pos, 'linha_id', null,
                                                                 'resultado', null));
      v_need[v_k] := case when v_term then 0 else v_need[v_k] - v_f end;
      v_ini[v_k] := true;
      v_pend[v_k] := false;
      v_cap := v_cap - v_f;
    end loop;

    -- quem responde pelas etapas do meio-dia (§16.3.6): o responsável da OS na equipe; senão o responsável da equipe de maior instala
    -- (o nome); senão, só com ajudante e o dono presente, o dono (nulo); senão o ajudante. Quem não recebe pelo WhatsApp (sem telefone
    -- pela régua da 7a, ou fora da rotina) não responde: vale a conferência do dono (nulo, R5.2-4).
    v_resp := null;
    if v_lid is not null and (m -> 'equipe') ? v_lid::text then
      v_resp := v_lid;
    else
      select u.x::uuid into v_resp
        from jsonb_array_elements_text(m -> 'equipe') u(x)
       where (v_hab -> u.x ->> 'p')::int = 0
       order by (v_hab -> u.x ->> 'i')::int desc, v_hab -> u.x ->> 'n', u.x limit 1;
      if v_resp is null and not ((m ->> 'dono_turno')::boolean or (m ->> 'dono_fecha')::boolean or (m ->> 'dono_abre')::boolean) then
        select u.x::uuid into v_resp from jsonb_array_elements_text(m -> 'equipe') u(x) order by v_hab -> u.x ->> 'n', u.x limit 1;
      end if;
    end if;
    -- FASE 7c: (7c correção, achado 1) AG7-10c, a resposta do dono ("Sim, o responsável da OS"; fase7-padroes, que vale sobre a
    -- spec): quem responde pelas etapas do meio-dia é só o responsável da OS (_agenda_lider_da_os, qualquer fonte) quando ele está na
    -- equipe. Sem ele, ninguém da equipe responde — nem o "responsável da equipe" de maior instala, nem o ajudante, que só recebe a
    -- lista na ficha (e o "como foi" de antes) — e vale a conferência do dono (nulo, R5.2-4). O §16.3.6, itens 2 a 4, dava a vez a eles.
    if v_resp is distinct from v_lid then
      v_resp := null;
    end if;
    -- FASE 7c: fim
    if v_resp is not null and not coalesce((v_fone ->> v_resp::text)::boolean, false) then
      v_resp := null;
    end if;
    v_out := v_out || jsonb_build_array(m || jsonb_build_object('congelado', false, 'responde', v_resp, 'itens', v_itens));
  end loop;
  if v_snap is null then
    v_snap := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
  end if;

  return jsonb_build_object(
    'os', p_os, 'modo', p_modo, 'total', v_total, 'falta', round(v_falta, 3), 'faltam', to_jsonb(v_faltam), 'meios', v_out,
    'sobra', coalesce((select jsonb_agg(jsonb_build_object('tarefa', v_ids[k], 'need', round(v_need[k], 3)) order by k)
                         from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid), '[]'::jsonb),
    'sobra_meios', round((select coalesce(sum(x), 0) from unnest(v_need) x where x > c_resid), 3),
    'sem_quem', coalesce((select jsonb_agg(v_ids[k] order by k) from generate_subscripts(v_ids, 1) k
                           where v_need[k] > c_resid and v_ex[k] <> 0 and not v_at[k] and v_futuro > 0), '[]'::jsonb),
    'prazo', v_prazo, 'sobra_no_prazo', round(v_snap, 3), 'meios_ate_prazo', v_ate);
end;
$function$;

comment on function public._agenda_tarefas_planejar(uuid, date, text) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.5, §16.3.6; R5.2-3, R5.2-4): a distribuição das etapas vivas da OS pelos meios-dias marcados (alocação vigente de turno, sem reserva) de p_hoje em diante, no modo p_modo — o que cada etapa pede em meios-dias é o peso dela sobre o total (agenda_meios_da_os.total; sem base, horas ÷ meia jornada) menos o que o plano congelado de antes de hoje levou (a começada, no mínimo 0,25; a pendente dita, tarefas_pendente_meios; a que terminou com feita, sem registro ou ainda sem resultado: nada, conta como feita para o plano). O meio-dia já congelado entra com as linhas dele; cada outro leva até 1,0, na fila pendente → começada → as outras pela ordem; a etapa de risco (exige) só vai ao meio-dia cuja equipe atende (_agenda_atende com as etiquetas efetivas; a final conta o fechamento do dono com habilidade_fechamento_cobre), e as outras seguem. Quem responde: o responsável da OS na equipe, senão o responsável da equipe de maior instala, senão (só ajudante e o dono presente) o dono (nulo), senão o ajudante; quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) não responde (nulo = o dono pela conferência). {os, modo, total, falta, meios [{dia, turno, congelado, equipe, dono_turno, dono_fecha, dono_abre, responde, itens [{tarefa, fracao, termina, comeca, posicao, linha_id, resultado}]}], sobra [{tarefa, need}], sobra_meios, sem_quem [tarefa] (a de risco que nenhum meio-dia futuro atende), prazo (o prazo efetivo; sem ele, o último dia do plano), sobra_no_prazo (o que não coube até o prazo), meios_ate_prazo}. STABLE, sem grant. CORREÇÃO DA REVISÃO DA 7c (20261102100580): (achado 1, AG7-10c) quem responde é só o responsável da OS na equipe do meio-dia; sem ele, nulo (o dono pela conferência) — nunca o responsável da equipe de maior instala nem o ajudante; (achado 10) os meios-dias que a OS fez antes de ter etapas neste modo (passados de turno, sem linha de etapa; cumprido, sem registro ou sem resultado = 1, parcial = meio) saem do total que as etapas repartem (a OS começada antes das etapas não pede de novo o que já foi feito); o total da saída continua o da OS. CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590, achado 12): as etapas repartem a duração do plano — os meios-dias marcados de hoje em diante mais os passados pelo resultado (cumprido, sem registro ou sem resultado = 1; parcial = meio) — quando ela é maior que a de agenda_meios_da_os só com a dupla da 7b ligada (ni + nf > 0) e até pm, as diárias-pessoa (a dupla inferida supõe 2 pessoas e o motor marcou 1: o Lenine 10 × 12); o total da saída passa a ser esse. Sem isso, as etapas acabavam antes do último dia do plano.';

-- _agenda_tarefas_sincronizar (de 20261102100550_agenda_fase7c_tarefas.sql)
create or replace function public._agenda_tarefas_sincronizar(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_casa   constant numeric := 0.001;   -- estrutural: a menor casa de os_tarefas.ordem (numeric(8,3))
  cf      public.agenda_config := public._agenda_cfg();
  v_f     jsonb;
  v_ass   text;
  v_prim  boolean;
  i       jsonb;
  t       public.os_tarefas%rowtype;
  v_novas text[] := '{}';
  v_saiu  int := 0;
  v_atu   int := 0;
  v_n     int := 0;
  v_ord   numeric;
  v_x     numeric;
  v_ant   numeric;
  v_qtd   int;
  v_pass  uuid[];
  v_cli   text;
  v_txt   text;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam a OS, o dia e a hora para sincronizar as etapas.' using errcode = '22023';
  end if;
  v_f := public.os_tarefas_fonte(p_os, p_hoje);
  if not coalesce((v_f ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'mudou', false);
  end if;
  select pl.tarefas_assinatura into v_ass from public.os_planejamento pl where pl.service_order_id = p_os;
  v_prim := not exists (select 1 from public.os_tarefas x where x.service_order_id = p_os);
  if not v_prim and v_ass is not distinct from (v_f ->> 'assinatura')
     and not exists (select 1 from jsonb_array_elements(v_f -> 'itens') e
                       join public.os_tarefas x on x.service_order_id = p_os and x.chave = e ->> 'chave' and x.estado in ('viva', 'feita')
                      where x.exige <> (e ->> 'exige')::int) then
    return jsonb_build_object('ok', true, 'mudou', false, 'novas', 0, 'saiu', 0, 'atualizadas', 0, 'escopo', '[]'::jsonb);
  end if;

  for i in select e from jsonb_array_elements(v_f -> 'itens') with ordinality t(e, o) order by o loop
    v_n := v_n + 1;
    v_pass := array(select x::uuid from jsonb_array_elements_text(coalesce(i -> 'passos', '[]'::jsonb)) x);
    select * into t from public.os_tarefas x
     where x.service_order_id = p_os and x.chave = i ->> 'chave' and x.estado in ('viva', 'feita') limit 1;
    if found then
      if (t.texto, t.fase, t.horas, t.exige, t.passos)
         is distinct from (i ->> 'texto', (i ->> 'fase')::smallint, (i ->> 'horas')::numeric, (i ->> 'exige')::smallint, v_pass) then
        update public.os_tarefas
           set texto = i ->> 'texto', fase = (i ->> 'fase')::smallint, horas = (i ->> 'horas')::numeric,
               exige = (i ->> 'exige')::smallint, passos = v_pass, mudou_em = p_agora
         where id = t.id;
        v_atu := v_atu + 1;
      end if;
      continue;
    end if;
    -- a dividida: as partes recebem o peso ÷ n e a máscara dela
    select * into t from public.os_tarefas x
     where x.service_order_id = p_os and x.chave = i ->> 'chave' and x.estado = 'substituida' order by x.mudou_em desc, x.id limit 1;
    if found then
      select count(*) into v_qtd from public.os_tarefas p where p.pai_id = t.id and p.estado in ('viva', 'feita');
      if v_qtd > 0 then
        update public.os_tarefas p
           set horas = round((i ->> 'horas')::numeric / v_qtd, 2), exige = (i ->> 'exige')::smallint, mudou_em = p_agora
         where p.pai_id = t.id and p.estado in ('viva', 'feita')
           and (p.horas, p.exige) is distinct from (round((i ->> 'horas')::numeric / v_qtd, 2), (i ->> 'exige')::smallint);
      end if;
      continue;
    end if;
    -- a nova: na 1ª vez, pela ordem do serviço; depois, no fim, antes da 1ª viva de fase >= testar (a de fase >= 5, antes da final)
    if v_prim then
      v_ord := v_n;
    else
      if (i ->> 'fase')::int >= 5 then
        select min(x.ordem) into v_x from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' and x.chave = 'entrega';
      else
        select min(x.ordem) into v_x from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' and x.fase >= 5;
      end if;
      if v_x is null then
        select coalesce(max(x.ordem), 0) + 1 into v_ord from public.os_tarefas x where x.service_order_id = p_os;
      else
        select coalesce(max(x.ordem), v_x - 1) into v_ant from public.os_tarefas x where x.service_order_id = p_os and x.ordem < v_x;
        v_ord := round((v_ant + v_x) / 2, 3);
        if v_ord <= v_ant or v_ord >= v_x then
          v_ord := v_x - c_casa;
        end if;
      end if;
    end if;
    insert into public.os_tarefas (service_order_id, chave, origem, service_order_service_id, texto, fase, ordem, horas, exige, passos,
                                   estado, nova_no_escopo, criada_em, mudou_em)
    values (p_os, i ->> 'chave', i ->> 'origem', (i ->> 'service_order_service_id')::uuid, i ->> 'texto', (i ->> 'fase')::smallint,
            v_ord, (i ->> 'horas')::numeric, (i ->> 'exige')::smallint, v_pass, 'viva', not v_prim, p_agora, p_agora);
    if not v_prim then
      v_novas := v_novas || (i ->> 'texto');
    end if;
  end loop;

  -- A que saiu da base (a linha apagada, virou material): saiu. A feita fica feita; as do dono e as partes não são tocadas.
  update public.os_tarefas x
     set estado = 'saiu', mudou_em = p_agora
   where x.service_order_id = p_os and x.estado = 'viva' and x.pai_id is null and (x.chave like 'linha:%' or x.chave = 'entrega')
     and not exists (select 1 from jsonb_array_elements(v_f -> 'itens') e where e ->> 'chave' = x.chave);
  get diagnostics v_saiu = row_count;

  -- O escopo que aumentou: UMA ação ao dono (no "o que mudou"), em teste com "Em teste: ".
  if cardinality(v_novas) > 0 and cf.modo_tarefas <> 'desligado' then
    v_cli := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
                        where so.id = p_os), public._agenda_rotulo_da_os(p_os));
    v_txt := format('%s: entrou %s (o orçamento aumentou). %s no fim%s', v_cli,
                    public._agenda_lista(array(select '"' || x || '"' from unnest(v_novas) with ordinality u(x, o) order by o), null),
                    case when cardinality(v_novas) = 1 then 'Ficou' else 'Ficaram' end,
                    case when exists (select 1 from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' and x.fase >= 5
                                         and not (x.texto = any (v_novas)))
                         then ', antes de testar e entregar.' else '.' end);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), p_hoje, cf.modo_tarefas = 'ligado', 'vigia', 'tarefa', p_os, array[p_os],
            jsonb_build_object('os', p_os, 'novas', to_jsonb(v_novas)), jsonb_build_object('motivo', 'escopo'),
            left(case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end || v_txt, 400));
  end if;

  -- FASE 7c: (7c correção 2, achado 5) a linha de os_planejamento que esta rodada cria nasce com o carimbo da OS
  -- (service_orders.created_at, nunca depois de p_agora), não com o DEFAULT now() de atualizado_em: o encaixe da 7a
  -- (_agenda_gestor_encaixe) conta como candidata a OS cujo planejamento mudou depois da marca d'água, e _agenda_gestor_desfeito solta a
  -- trava do *desfaz* pelo mesmo carimbo — com a 7c em teste, a OS posta em andamento pelo app, sem dia, ganhava a pergunta situacao
  -- na hora (e não no passo diário da 7a), e a OS desfeita voltava a ser tentada. O carimbo da OS não acorda ninguém: o encaixe já conta
  -- o created_at, e o *desfaz* é sempre depois dele. A linha que já existe não muda (o on conflict de baixo só grava as colunas das
  -- etapas; os_planejamento não tem gatilho).
  insert into public.os_planejamento (service_order_id, atualizado_em)
  select so.id, least(coalesce(so.created_at, p_agora), p_agora) from public.service_orders so where so.id = p_os
  on conflict (service_order_id) do nothing;
  -- FASE 7c: fim
  insert into public.os_planejamento (service_order_id, tarefas_assinatura, tarefas_sincronizadas_em)
  values (p_os, v_f ->> 'assinatura', p_agora)
  on conflict (service_order_id) do update
    set tarefas_assinatura = excluded.tarefas_assinatura, tarefas_sincronizadas_em = excluded.tarefas_sincronizadas_em;
  return jsonb_build_object('ok', true, 'mudou', true, 'novas', cardinality(v_novas), 'saiu', v_saiu, 'atualizadas', v_atu,
                            'escopo', to_jsonb(v_novas), 'primeira', v_prim);
end;
$function$;

comment on function public._agenda_tarefas_sincronizar(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.1): as etapas gravadas (os_tarefas) seguem a base (os_tarefas_fonte) — a mesma assinatura e a mesma máscara = {mudou: false}; senão a etapa viva ou feita de mesma chave atualiza texto, fase, peso, máscara e passos (o estado fica), a dividida passa o peso ÷ n e a máscara às partes, a nova entra viva (na 1ª sincronização pela ordem do serviço; depois com nova_no_escopo, logo antes da 1ª viva de fase >= testar — a de fase >= 5, logo antes da final), a viva de chave linha:*/entrega que saiu da base vira saiu (a feita fica feita; as do dono e as partes não são tocadas). Com etapa nova do escopo e modo_tarefas fora de desligado: UMA ação tarefa (origem vigia, executada = ligado, sem *desfaz*, antes {os, novas}) — "Flávio: entrou "Instalação do compressor e recarga de gás" (o orçamento aumentou). Ficou no fim, antes de testar e entregar." (em teste com "Em teste: "). Grava os_planejamento.tarefas_assinatura e tarefas_sincronizadas_em. {ok, mudou, novas, saiu, atualizadas, escopo, primeira}. Definer, sem grant. CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590, achado 5): a linha de os_planejamento que a sincronização cria nasce com atualizado_em = o created_at da OS (nunca depois de p_agora), não now() — o encaixe e a trava do *desfaz* da 7a não a tomam como "o planejamento mudou"; a linha que já existe não muda.';

-- agenda_habilidade (de 20261102100580_agenda_fase77c_correcao.sql)
create or replace function public.agenda_habilidade(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos  constant text[] := array['propor', 'vetos', 'conferir', 'perguntas_os', 'medir'];
  c_medida  constant int := 30;   -- estrutural: a janela da linha das medidas do foco (spec §6.7), em dias
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_modos   jsonb;
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
  -- FASE 7c: (7c correção, achado 7) a pergunta por OS a cada tique
  v_c7_r    jsonb;
  -- FASE 7c: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada de quem faz o quê.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_habilidade'));
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('modo_habilidade', cf.modo_habilidade, 'modo_lider', cf.modo_lider,
                                'modo_habilidade_propor', cf.modo_habilidade_propor);
  -- FASE 7c: (7c correção 2, achado 2) a pergunta LIGADA de quem faz o quê ou das etapas cujo modo voltou a teste (o DESFAZER 1 ou 2
  -- do ligar-fase7c.sql, o do ligar-fase7c-tarefas.sql, ou o modo mudado à mão) é descartada a cada tique, em qualquer modo. Aberta,
  -- ela levava a linha (n) inteira ao detalhe (o modo de agora dela não é ligado) e escondia do dono a chamada ligada da 7b, e nada a
  -- fechava (a pergunta por OS só roda com modo_habilidade ligado; as etapas só resolvem as do próprio modo). A rodada refaz a de
  -- teste (a proposta fica). Sem pergunta assim — o estado de sempre: em teste não nasce pergunta ligada —, nada muda.
  update public.agenda_perguntas q
     set estado = 'descartada', resolvida_motivo = 'o modo voltou a teste: a pergunta ligada não vale mais (correção 2 da 7c)'
   where q.estado = 'aberta' and q.modo = 'ligado'
     and ((q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and cf.modo_habilidade_propor <> 'ligado')
          or (q.tipo = 'habilidade' and q.chave like 'habilidade:os:%' and cf.modo_habilidade <> 'ligado')
          or (q.tipo = 'tarefa' and cf.modo_tarefas <> 'ligado'));
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achado 7) com modo_habilidade ligado, a pergunta por OS também a cada tique fora da rodada do dia (antes de
  -- habilidade_hora e depois que ela rodou): a vigia (o passo 0c, depois deste) e o gestor (às :53) deixam OS de fora por falta de
  -- quem o serviço pede depois da rodada; no tique seguinte a pergunta nasce (ou fecha, quando a OS volta a caber). Idempotente; o
  -- que falha vai a log_app_error (agenda / habilidade:perguntas_os) e o tique segue. A saída é a de antes com perguntas_os.
  if cf.modo_habilidade = 'ligado'
     and ((p_agora at time zone 'America/Sao_Paulo')::time < cf.habilidade_hora
          or exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'habilidade' and x.p_hoje = p_hoje)) then
    begin
      v_c7_r := public._agenda_habilidade_perguntas_os(p_hoje, p_agora);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_c7_r := jsonb_build_object('sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('quem faz o quê, passo perguntas_os (tique): %s', v_msg), 'agenda',
                                   'habilidade:perguntas_os', 'error',
                                   jsonb_build_object('passo', 'perguntas_os', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
    return case when (p_agora at time zone 'America/Sao_Paulo')::time < cf.habilidade_hora
                then jsonb_build_object('rodou', false, 'cedo', true, 'modos', v_modos, 'hora', cf.habilidade_hora)
                else jsonb_build_object('rodou', false, 'ja_rodou', true, 'modos', v_modos) end
           || jsonb_build_object('perguntas_os', v_c7_r);
  end if;
  -- FASE 7c: fim
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.habilidade_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'modos', v_modos, 'hora', cf.habilidade_hora);
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'habilidade' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true, 'modos', v_modos);
  end if;

  -- (1) propor: com modo_habilidade_propor fora de desligado; (2) vetos: sempre (só age na pergunta ligada e já mostrada); (3)
  -- conferir: com modo_habilidade ou modo_lider em teste; (4) perguntas_os: com modo_habilidade ligado; (5) medir: sempre (só lê)
  foreach v_passo in array c_passos loop
    continue when v_passo = 'propor' and cf.modo_habilidade_propor = 'desligado';
    continue when v_passo = 'conferir' and cf.modo_habilidade <> 'sombra' and cf.modo_lider <> 'sombra';
    continue when v_passo = 'perguntas_os' and cf.modo_habilidade <> 'ligado';
    begin
      if v_passo = 'propor' then
        v_r := public._agenda_habilidade_propor(p_hoje, p_agora);
      elsif v_passo = 'vetos' then
        v_r := public._agenda_habilidade_vetos(p_hoje, p_agora);
      elsif v_passo = 'conferir' then
        v_r := public._agenda_habilidade_conferir(p_hoje, p_agora);
      elsif v_passo = 'perguntas_os' then
        v_r := public._agenda_habilidade_perguntas_os(p_hoje, p_agora);
      else
        v_r := public.agenda_habilidade_medidas(p_hoje - c_medida, p_hoje, p_hoje) - 'detalhe';
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('quem faz o quê, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'habilidade:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'habilidade', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modos', v_modos, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_habilidade(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5): a rodada de quem faz o quê (o passo 0b2a do task-automations, a cada tique; o molde de agenda_aprender) — uma vez por dia, a partir de habilidade_hora (antes: {rodou: false, cedo: true}; o 2º tique do dia: {rodou: false, ja_rodou: true}); com pg_advisory_xact_lock. Os passos, cada um no seu bloco (o que falha vai a log_app_error, context agenda, action habilidade:<passo>, e os outros seguem): propor (_agenda_habilidade_propor, com modo_habilidade_propor fora de desligado), vetos (_agenda_habilidade_vetos, sempre), conferir (_agenda_habilidade_conferir, com modo_habilidade ou modo_lider em sombra), perguntas_os (_agenda_habilidade_perguntas_os, com modo_habilidade ligado) e medir (agenda_habilidade_medidas dos últimos 30 dias, sem o detalhe; sempre). Grava agenda_vigia_rodadas (rotina habilidade; contagens com o resultado de cada passo, os 3 modos e as falhas). {rodou, modos, contagens, erros, falhas}. Nenhuma mensagem a ninguém. Definer; só service_role. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 7): com modo_habilidade ligado, fora da rodada do dia (antes de habilidade_hora e depois que ela rodou), cada tique roda _agenda_habilidade_perguntas_os (o erro vai a log_app_error, action habilidade:perguntas_os) e a saída de antes ganha perguntas_os — a OS que a vigia ou o gestor tira por falta de quem o serviço pede depois da rodada ganha a pergunta no tique seguinte. CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590, achado 2): a cada tique, antes de tudo, a pergunta ligada aberta de quem faz o quê (habilidade:equipe com modo_habilidade_propor fora de ligado; habilidade:os com modo_habilidade fora de ligado) ou das etapas (tarefa com modo_tarefas fora de ligado) é descartada, com o motivo "o modo voltou a teste": ela levava a linha (n) ao detalhe e escondia a chamada ligada da 7b.';

-- _agenda_ver_habilidades (de 20261102100580_agenda_fase77c_correcao.sql)
create or replace function public._agenda_ver_habilidades(p_hoje date, p_agora timestamptz, p_os uuid default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_max     constant int := 1500;  -- estrutural: o teto do foco (o conteúdo até texto_max, a linha "Para corrigir" depois; R5.6)
  c_medidas constant int := 30;    -- estrutural: a janela das medidas no foco ("Nos últimos 30 dias", spec §6.7)
  c_teste   constant int := 3;     -- estrutural: quantas mudanças de teste a linha "Em teste" mostra (o resto: "e mais N")
  c_faltas  constant int := 3;     -- estrutural: quantos meios-dias sem quem o serviço pede o bloco da OS mostra (o resto: "e mais N")
  c_bits    constant jsonb := '{"energizado": 1, "comissionamento": 2, "altura": 4, "diagnostico": 8}';
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_dono    uuid := public._agenda_dono(null);
  v_n       jsonb;
  v_modo    text;
  v_pes     jsonb := '[]'::jsonb;
  v_lpes    text[] := '{}';
  v_dalt    int;
  h         record;
  e         record;
  q         record;
  r         record;
  k         record;
  v_partes  jsonb;
  v_linha   text;
  v_suf     text;
  v_grupo   text;
  v_gsuf    text;
  v_ate     timestamptz;
  v_pi      int;
  v_pc      int;
  v_pa      int;
  v_padrao  text;
  v_oss     jsonb := '[]'::jsonb;
  v_los     text[] := '{}';
  v_ex      jsonb;
  v_lid     jsonb;
  v_pede    text;
  v_cit     text;
  v_todos   int;
  v_ult     int;
  v_nome    text;
  v_teste   text[];
  v_lteste  text;
  v_m       jsonb;
  v_lmed    text;
  v_fim     text;
  v_exemplo text;
  v_cab     text;
  v_l       text[];
  v_txt     text;
  v_corte   int;
  v_max     int;
  v_mask    int;
  v_sozinho text[];
  v_junto   text[];
  v_cod     text;
  v_rot     text;
  v_cli     text;
  v_alocs   jsonb;
  v_dias    date[];
  v_fecha   boolean;
  v_faltas  text[];
  v_nf      int;
  v_resp    text;
  i         int;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (o WhatsApp do dono).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'Quem faz o quê é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'Quem faz o quê é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_ver_habilidades: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);
  v_modo := case cf.modo_habilidade when 'ligado' then '(já escalo por isso)' when 'sombra' then '(em teste: ainda escalo como antes)'
                                    else '(desligado: a agenda não usa)' end;

  -- ── as pessoas: o que vale hoje (agenda_habilidades, na ordem dela: você primeiro, depois o nome; você também quando não está na
  -- grade) e, no lugar do instala/ajudante, a proposta do gestor que ainda não vale ──
  for h in
    with todos as (
      select x.* from public.agenda_habilidades(p_hoje)
             with ordinality x(payee_id, nome, eh_dono, instala, comissiona, altura, papel, fonte, texto, pos)
    )
    select t.payee_id, t.nome, t.eh_dono, t.instala, t.comissiona, t.altura, t.papel, t.fonte, t.texto, t.pos from todos t
    union all
    select x.payee_id, x.nome, x.eh_dono, x.instala, x.comissiona, x.altura, x.papel, x.fonte, x.texto, 0
      from public.agenda_habilidades(p_hoje, array[v_dono]) x
     where v_dono is not null and not exists (select 1 from todos t where t.payee_id = v_dono)
     order by 10
  loop
    v_linha := h.texto;
    if h.eh_dono then
      v_dalt := h.altura;
    else
      select e2.* into e from public.agenda_etiquetas e2
       where e2.payee_id = h.payee_id and e2.etiqueta in ('instala', 'ajudante') and e2.estado in ('proposta', 'vale')
       order by e2.criado_em desc, e2.id desc limit 1;
      if found and e.estado = 'proposta' and e.origem = 'gestor' then
        -- a proposta: [texto, de onde] da proposta e das outras etiquetas vivas (comissiona, altura); as seguidas com o mesmo
        -- "você disse" dividem o parêntese, como em agenda_habilidades
        v_partes := '[]'::jsonb;
        for e in
          select e2.* from public.agenda_etiquetas e2
           where e2.payee_id = h.payee_id and e2.estado in ('proposta', 'vale')
           order by case e2.etiqueta when 'instala' then 0 when 'ajudante' then 0 when 'comissiona' then 1 else 2 end, e2.criado_em desc, e2.id
        loop
          if e.origem = 'dono' then
            v_suf := 'você disse';
          elsif e.estado = 'vale' then
            v_suf := format('eu marquei: %s; vale desde %s', e.motivo, public._dia_curto((e.vale_desde at time zone 'America/Sao_Paulo')::date));
          else
            select x.estado, x.modo, x.veto_ate, x.mostrada_em into q from public.agenda_perguntas x where x.id = e.pergunta_id;
            if q.estado = 'aberta' and q.modo = 'ligado' then
              v_ate := coalesce(q.veto_ate, case when q.mostrada_em is not null then public._agenda_veto_ate(q.mostrada_em) end);
              v_suf := format('eu marquei: %s; %s', e.motivo,
                              coalesce('espero você até ' || public._dia_curto((v_ate at time zone 'America/Sao_Paulo')::date),
                                       'espero você ver a pergunta'));
            else
              v_suf := format('em teste, eu marcaria: %s', e.motivo);
            end if;
          end if;
          -- FASE 7c: (7c correção 2, achado 16) com a pergunta já ligada e a proposta ainda a de teste (do ligar até a rodada seguinte),
          -- a linha não diz "em teste" debaixo de "(já escalo por isso)": diz que a pergunta ainda vai sair, e por quê
          if cf.modo_habilidade_propor = 'ligado' and v_suf like 'em teste, eu marcaria: %' then
            v_suf := format('ainda vou te perguntar; eu marcaria porque %s', e.motivo);
          end if;
          -- FASE 7c: fim
          v_partes := v_partes || jsonb_build_array(jsonb_build_array(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), v_suf));
        end loop;
        v_linha := null;
        v_grupo := null;
        v_gsuf := null;
        for i in 0 .. jsonb_array_length(v_partes) - 1 loop
          if v_grupo is not null and v_gsuf = 'você disse' and v_partes -> i ->> 1 = v_gsuf then
            v_grupo := v_grupo || '; ' || (v_partes -> i ->> 0);
          else
            if v_grupo is not null then
              v_linha := concat_ws('; ', v_linha, format('%s (%s)', v_grupo, v_gsuf));
            end if;
            v_grupo := v_partes -> i ->> 0;
            v_gsuf := v_partes -> i ->> 1;
          end if;
        end loop;
        v_linha := format('%s: %s.', h.nome, concat_ws('; ', v_linha, format('%s (%s)', v_grupo, v_gsuf)));
      else
        -- o que vale: o texto de agenda_habilidades, com "vale desde" na etiqueta do gestor
        for e in
          select e2.* from public.agenda_etiquetas e2
           where e2.payee_id = h.payee_id and e2.estado = 'vale' and e2.origem = 'gestor' and e2.vale_desde is not null
        loop
          v_linha := replace(v_linha, format(' (eu marquei: %s)', e.motivo),
                             format(' (eu marquei: %s; vale desde %s)', e.motivo,
                                    public._dia_curto((e.vale_desde at time zone 'America/Sao_Paulo')::date)));
        end loop;
      end if;
    end if;
    -- FASE 7c: (7c correção 2, achado 3) a palavra do dono já vale para quem é novo, também com a escalação desligada ou em teste
    -- (_agenda_e_novato e _agenda_tecnico_declarado leem a etiqueta sem portão de modo: R5.1-5, a exceção deliberada): com a dupla da 7b
    -- ligada, "o Bruno instala sozinho" tira a proteção de novato (ele pode ir sozinho) e "o X é ajudante" a devolve a quem tem perfil
    -- novo (nunca sozinho). O cabeçalho ("a agenda não usa", "ainda escalo como antes") fala da escalação; a linha de quem tem perfil
    -- de diária novo e uma palavra do dono valendo diz o que já vale. Sem perfil novo (o Alex hoje), nada muda.
    if cf.modo_habilidade <> 'ligado' and cf.modo_dupla = 'ligado' and not h.eh_dono
       and exists (select 1 from public.agenda_etiquetas e2
                    where e2.payee_id = h.payee_id and e2.origem = 'dono' and e2.estado = 'vale' and e2.etiqueta in ('instala', 'ajudante'))
       and exists (select 1 from public.work_profiles w
                    where w.payee_id = h.payee_id and w.vigencia_inicio <= p_hoje and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
       and (select min(w.vigencia_inicio) from public.work_profiles w where w.payee_id = h.payee_id) > p_hoje - cf.novato_dias
       and coalesce((select sum(ws.fracao) from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
                      where w.payee_id = h.payee_id and ws.data <= p_hoje and ws.tipo = 'diaria' and ws.fracao is not null), 0)
           < cf.novato_diarias then
      v_linha := v_linha || case when public._agenda_e_novato(h.payee_id, p_hoje)
                                 then ' (Isto já vale hoje: sendo novo, ele nunca vai sozinho.)'
                                 else ' (Isto já vale hoje: sendo novo, ele pode ir sozinho, porque você disse.)' end;
    end if;
    -- FASE 7c: fim
    v_pes := v_pes || jsonb_build_array(jsonb_build_object(
      'payee_id', h.payee_id, 'nome', h.nome, 'eh_dono', h.eh_dono, 'instala', h.instala, 'comissiona', h.comissiona,
      'altura', h.altura, 'papel', h.papel, 'fonte', h.fonte, 'texto', v_linha));
    v_lpes := v_lpes || ('• ' || v_linha);
  end loop;

  -- quem não tem nada marcado (o padrão da casa, AG7-10, pela mesma régua de agenda_habilidades)
  v_pi := (cf.habilidade_padrao ->> 'instala')::int;
  v_pc := (cf.habilidade_padrao ->> 'comissiona')::int;
  v_pa := (cf.habilidade_padrao ->> 'altura')::int;
  v_padrao := case when v_pi >= cf.habilidade_nivel_energizado and v_pa >= cf.habilidade_nivel_altura
                   then case when v_pc >= cf.habilidade_nivel_comissionar then 'Quem não tem nada marcado pode tudo.'
                             else 'Quem não tem nada marcado pode tudo, menos comissionar.' end
                   else format('Quem não tem nada marcado: %s.',
                               concat_ws('; ', public._agenda_etiqueta_texto('instala', v_pi::smallint),
                                         public._agenda_etiqueta_texto('comissiona', v_pc::smallint),
                                         public._agenda_etiqueta_texto('altura', v_pa::smallint))) end;

  -- o que eu teria mudado hoje em teste (as ações de teste da rodada: "Ivo, ter 10/11 à tarde (poria Roberto)")
  v_teste := array(
    select coalesce(substring(a.texto from '^Em teste \([^)]*\): ([^—]+) — ')
                    || coalesce(' (' || substring(a.texto from '(?:; |: )eu ((?:poria|mudaria|manteria) [^.]*)\.$') || ')', ''),
                    a.texto)
      from public.agenda_acoes a
     where a.tipo = 'habilidade' and not a.executada and a.dia = p_hoje
       and (p_os is null or a.service_order_id = p_os)
     order by a.criada_em, a.id);
  v_lteste := case when cardinality(v_teste) > 0
                   then 'Em teste, hoje eu teria mudado: ' || array_to_string(v_teste[1:c_teste], '; ')
                        || case when cardinality(v_teste) > c_teste then format('; e mais %s', cardinality(v_teste) - c_teste) else '' end
                        || '.' end;

  -- ── o bloco de uma OS (com p_os) ──
  if p_os is not null then
    v_rot := public._agenda_rotulo_da_os(p_os);
    v_ex := public.os_exigencias(p_os, p_hoje);
    if v_rot is null or not coalesce((v_ex ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'rota', 'habilidades', 'texto', 'Não encontrei esse serviço.');
    end if;
    v_cli := (select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                from public.service_orders so left join public.clients cl on cl.id = so.client_id where so.id = p_os);
    v_todos := coalesce((v_ex ->> 'todos')::int, 0);
    v_ult := coalesce((v_ex ->> 'ultimo')::int, 0);
    v_l := array[format('%s — quem faz o quê %s:', v_rot, v_modo)];
    -- o que pede e de onde veio (a 1ª linha de cada parte, como os_exigencias)
    v_pede := null;
    if v_todos <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'todos' and v_todos & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := format('%s (%s)', public._agenda_exigencia_texto(v_todos, null), v_cit);
    end if;
    if v_ult <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'ultimo' and v_ult & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := concat_ws(' e ', v_pede, format('%s, no último dia (%s)', public._agenda_exigencia_texto(v_ult, null), v_cit));
    end if;
    v_l := v_l || case when v_pede is null then '• Não pede ninguém em especial.' else format('• Pede %s.', v_pede) end;
    -- o plano de hoje em diante (as alocações vigentes, fora a reserva): quem vai e o fechamento do dono no último dia
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia,
                                                 'turno', a.turno, 'presenca', a.presenca) order by a.dia, a.turno, py.name), '[]'::jsonb),
           array_agg(distinct a.dia) filter (where a.presenca = 'turno')
      into v_alocs, v_dias
      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
    v_fecha := v_ult <> 0 and cf.habilidade_fechamento_cobre and cardinality(v_dias) > 0
               and exists (select 1 from public.agenda_alocacoes a
                            where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.presenca = 'fechamento'
                              and a.payee_id is not distinct from v_dono
                              and a.dia = (select max(d) from unnest(v_dias) d));
    if v_fecha then
      v_l := v_l || '• No último dia você fecha: isso cobre o que ele pede.'::text;
    end if;
    -- o que conta para ir sozinho: o de todos os dias e o do último, menos quando o fechamento do dono o cobre (a régua da avaliação do
    -- publicado, _agenda_meios_sem_quem_pede)
    v_mask := v_todos | case when v_fecha then 0 else v_ult end;
    v_lid := public._agenda_lider_da_os(p_os, p_hoje);
    v_l := v_l || case when v_lid is null then '• Sem responsável fixo.' else format('• Responsável: %s.', v_lid ->> 'texto') end;
    v_l := v_l || case when cardinality(v_dias) > 0
                       then format('• Quem vai (%s): %s.', public._agenda_dias_texto(v_dias), public._agenda_pessoas_texto(v_alocs, v_dono))
                       else '• Ainda sem dia marcado.' end;
    -- quem da equipe faz sozinho o que ela pede (a regra única) e quem precisa de alguém junto, com o porquê
    v_sozinho := '{}';
    v_junto := '{}';
    for i in 0 .. jsonb_array_length(v_pes) - 1 loop
      continue when (v_pes -> i ->> 'eh_dono')::boolean;
      v_cod := public._agenda_atende(v_mask, array[(v_pes -> i ->> 'instala')::int], array[(v_pes -> i ->> 'comissiona')::int],
                                     array[(v_pes -> i ->> 'altura')::int], array[(v_pes -> i ->> 'papel')::int], false, v_dalt, v_n);
      if v_cod is null then
        v_sozinho := v_sozinho || (v_pes -> i ->> 'nome');
      else
        v_junto := v_junto || format('%s (%s)', v_pes -> i ->> 'nome', case
          when (v_pes -> i ->> 'papel')::int = 2 then public._agenda_etiqueta_texto('ajudante', 1::smallint)
          when v_cod = 'altura' then public._agenda_etiqueta_texto('altura', (v_pes -> i ->> 'altura')::smallint)
          when v_cod in ('comissionamento', 'diagnostico') then public._agenda_etiqueta_texto('comissiona', (v_pes -> i ->> 'comissiona')::smallint)
          when (v_pes -> i ->> 'papel')::int = 1 then public._agenda_etiqueta_texto('ajudante', 2::smallint)
          else public._agenda_etiqueta_texto('instala', (v_pes -> i ->> 'instala')::smallint) end);
      end if;
    end loop;
    if v_mask = 0 then
      v_l := v_l || case when cardinality(v_junto) = 0 then '• Qualquer um da equipe vai sozinho.'
                         else format('• Qualquer um da equipe vai sozinho, menos %s.', public._agenda_lista(v_junto, null)) end;
    else
      v_resp := case when cardinality(v_sozinho) = 0
                     then 'Ninguém da equipe faz isso sozinho' || case when public._agenda_atende(v_mask, '{}', '{}', '{}', '{}', true, v_dalt, v_n) is null
                                                                       then ': fica com você no turno.' else '.' end
                     when cardinality(v_sozinho) = 1 then format('Faz sozinho o que ela pede: %s.', v_sozinho[1])
                     else format('Fazem sozinhos o que ela pede: %s.', public._agenda_lista(v_sozinho, null)) end;
      if cardinality(v_junto) > 0 then
        v_resp := v_resp || format(' %s de alguém junto: %s.', case when cardinality(v_junto) = 1 then 'Precisa' else 'Precisam' end,
                                   public._agenda_lista(v_junto, null));
      end if;
      v_l := v_l || ('• ' || v_resp);
    end if;
    -- os meios-dias marcados sem quem o serviço pede (a avaliação do publicado, com a equipe dita pelo dono)
    v_faltas := '{}';
    v_nf := 0;
    if cardinality(v_dias) > 0 then
      for r in
        select s.* from public._agenda_meios_sem_quem_pede(p_hoje, (select max(d) from unnest(v_dias) d), p_hoje, array[p_os], true) s
         order by s.dia, s.turno = 'tarde'
      loop
        v_nf := v_nf + 1;
        continue when v_nf > c_faltas;
        v_nome := public._agenda_lista(array(select public._agenda_nome_curto(py.name) from unnest(r.equipe) u(x)
                                                join public.payees py on py.id = u.x order by 1), null);
        v_faltas := v_faltas || case
          when r.falta = 'novato_sozinho' then format('• %s: %s é novo e iria %s.', public._agenda_meio_texto(r.dia, r.turno), v_nome,
                                                      case when cardinality(r.equipe) > 1 then 'sem um responsável junto' else 'sozinho' end)
          when cardinality(r.equipe) = 0 then format('• %s: só você iria, e esse dia pede %s.', public._agenda_meio_texto(r.dia, r.turno),
                                                     public._agenda_exigencia_texto((c_bits ->> r.falta)::int, null))
          else format('• %s: %s %s, e esse dia pede %s.', public._agenda_meio_texto(r.dia, r.turno), v_nome,
                      case when cardinality(r.equipe) > 1 then 'iriam sozinhos' else 'iria sozinho' end,
                      public._agenda_exigencia_texto((c_bits ->> r.falta)::int, null)) end;
      end loop;
    end if;
    if v_nf > c_faltas then
      v_faltas := v_faltas || format('• e mais %s %s sem quem o serviço pede.', v_nf - c_faltas,
                                     case when v_nf - c_faltas = 1 then 'meio-dia' else 'meios-dias' end);
    end if;
    v_l := v_l || v_faltas;
    if v_lteste is not null then
      v_l := v_l || v_lteste;
    end if;
    -- o exemplo de correção: o responsável (o 1º responsável da grade) e o que ela pede
    v_nome := (select p ->> 'nome' from jsonb_array_elements(v_pes) with ordinality t(p, o)
                where not (p ->> 'eh_dono')::boolean and (p ->> 'papel')::int = 0 order by o limit 1);
    v_fim := format('Para corrigir, me diga numa frase (ex.: %s).', concat_ws(' ou ',
               case when v_nome is not null then format('"o responsável do %s é o %s"', v_cli, v_nome) end,
               case when v_todos | v_ult <> 0
                    then format('"o %s não precisa de %s"', v_cli,
                                public._agenda_exigencia_texto(case when (v_todos | v_ult) & 1 <> 0 then 1 when (v_todos | v_ult) & 2 <> 0 then 2
                                                                    when (v_todos | v_ult) & 4 <> 0 then 4 else 8 end, null))
                    else format('"o %s pede quem sobe no teto"', v_cli) end));
    -- o conteúdo até texto_max (e nunca além do teto menos a linha final: o "Para corrigir" sempre cabe)
    v_max := least(cf.texto_max, c_max - 1 - char_length(v_fim));
    v_txt := public._agenda_gestor_juntar(v_l, v_max + 1 + char_length(v_fim), v_fim);
    return jsonb_build_object('ok', true, 'rota', 'habilidades', 'texto', public._agenda_corta(v_txt, c_max),
      'dados', jsonb_build_object(
        'pessoas', v_pes,
        'os', jsonb_build_object('os', p_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = p_os),
                                 'todos', v_todos, 'ultimo', v_ult, 'itens', v_ex -> 'itens', 'lider', v_lid, 'fechamento_cobre', coalesce(v_fecha, false),
                                 'sozinhos', to_jsonb(v_sozinho), 'com_alguem_junto', to_jsonb(v_junto), 'faltas', v_nf),
        'em_teste', to_jsonb(v_teste), 'medidas', null));
  end if;

  -- ── o que as OS da carteira pedem (as marcadas de hoje em diante primeiro, depois o número; a que não pede nada fica fora) ──
  for k in
    select c.service_order_id as os, c.numero, c.cliente_curto,
           (select min(a.dia) from public.agenda_alocacoes a
             where a.service_order_id = c.service_order_id and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje) as prox
      from public.os_carteira(p_hoje) c
     order by 4 nulls last, c.numero collate "C", c.service_order_id
  loop
    v_ex := public.os_exigencias(k.os, p_hoje);
    v_todos := coalesce((v_ex ->> 'todos')::int, 0);
    v_ult := coalesce((v_ex ->> 'ultimo')::int, 0);
    continue when v_todos = 0 and v_ult = 0;
    v_pede := null;
    if v_todos <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'todos' and v_todos & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := format('%s (%s)', public._agenda_exigencia_texto(v_todos, null), v_cit);
    end if;
    if v_ult <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'ultimo' and v_ult & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := concat_ws(' e ', v_pede, format('%s, no último dia (%s)', public._agenda_exigencia_texto(v_ult, null), v_cit));
    end if;
    -- o responsável, só o que o dono disse ou quem fez o 1º dia (o planejado só desempata), e só lido onde pode haver um
    v_lid := null;
    if exists (select 1 from public.os_planejamento pl where pl.service_order_id = k.os and pl.lider_payee_id is not null)
       or exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.os and a.presenca = 'turno' and a.tipo <> 'reserva'
                     and a.estado in ('publicada', 'fixada') and a.dia <= p_hoje)
       or exists (select 1 from public.work_shift_os x where x.service_order_id = k.os) then
      v_lid := public._agenda_lider_da_os(k.os, p_hoje);
      if v_lid ->> 'fonte' not in ('dono', 'fez') then
        v_lid := null;
      end if;
    end if;
    v_oss := v_oss || jsonb_build_array(jsonb_build_object('os', k.os, 'numero', k.numero, 'cliente', k.cliente_curto, 'todos', v_todos,
                                                           'ultimo', v_ult, 'pede', v_pede, 'lider', v_lid));
  end loop;
  for i in 0 .. jsonb_array_length(v_oss) - 1 loop
    -- o número junto quando o nome se repete na lista ("Kalmar (OS-00032)")
    v_nome := coalesce(v_oss -> i ->> 'cliente', v_oss -> i ->> 'numero');
    if (select count(*) from jsonb_array_elements(v_oss) x
         where public._agenda_normal(coalesce(x ->> 'cliente', x ->> 'numero')) = public._agenda_normal(v_nome)) > 1 then
      v_nome := format('%s (%s)', v_nome, v_oss -> i ->> 'numero');
    end if;
    v_los := v_los || format('• %s: %s%s.', v_nome, v_oss -> i ->> 'pede',
                             case when v_oss -> i -> 'lider' is not null and jsonb_typeof(v_oss -> i -> 'lider') = 'object'
                                  then format('; responsável: %s (%s)', v_oss -> i -> 'lider' ->> 'nome',
                                              case v_oss -> i -> 'lider' ->> 'fonte' when 'dono' then 'você disse' else 'fez o 1º dia' end)
                                  else '' end);
  end loop;

  -- as medidas dos últimos 30 dias (spec §6.7)
  v_m := public.agenda_habilidade_medidas(p_hoje - c_medidas, p_hoje, p_hoje);
  v_lmed := format('Nos últimos %s dias: %s alguém sozinho em serviço que pede outra pessoa; %s de responsável; %s em serviço que outro faria.',
                   c_medidas, public._agenda_plural(coalesce((v_m ->> 'sozinho_em_risco')::int, 0), 'vez', 'vezes'),
                   public._agenda_plural(coalesce((v_m ->> 'troca_de_lider')::int, 0), 'troca', 'trocas'),
                   public._agenda_plural(coalesce((v_m ->> 'dono_em_tarefa_de_outro')::int, 0), 'meio-dia seu', 'meios-dias seus'));

  -- o exemplo de correção: o 1º ajudante, senão o 1º novo ("o João instala sozinho"), senão o 1º responsável ("o Alex é ajudante")
  v_exemplo := (select format('o %s instala sozinho', p ->> 'nome') from jsonb_array_elements(v_pes) with ordinality t(p, o)
                 where not (p ->> 'eh_dono')::boolean and (p ->> 'papel')::int > 0 order by (p ->> 'papel')::int, o limit 1);
  -- FASE 7c: (7c correção, achado 16) "o X instala sozinho" só para o ajudante (papel 1): ao novo (o novato, quem vem sob demanda ou
  -- tem um dia fixo sem diária — nunca vai sozinho, R5.1-5 e o padrão do R5.8-3) a frase tiraria a proteção (instala 2 do dono tira o
  -- papel novo). Sem ajudante, o exemplo do responsável ("o Alex é ajudante").
  v_exemplo := (select format('o %s instala sozinho', p ->> 'nome') from jsonb_array_elements(v_pes) with ordinality t(p, o)
                 where not (p ->> 'eh_dono')::boolean and (p ->> 'papel')::int = 1 order by o limit 1);
  -- FASE 7c: fim
  v_exemplo := coalesce(v_exemplo, (select format('o %s é ajudante', p ->> 'nome') from jsonb_array_elements(v_pes) with ordinality t(p, o)
                                     where not (p ->> 'eh_dono')::boolean order by o limit 1));
  v_fim := case when v_exemplo is null then 'Para corrigir, me diga numa frase o que cada um faz.'
                else format('Para corrigir, me diga numa frase (ex.: "%s").', v_exemplo) end;

  -- o conteúdo até texto_max: primeiro saem as linhas de OS do fim ("• e mais N OS."; sem nenhuma, uma linha só: "O que as OS pedem:
  -- 21 OS pedem alguém em especial (me pergunte por uma)."), depois a linha do padrão (cada pessoa sem nada marcado já diz "(padrão)") e
  -- depois a das OS; só então o corte de sempre, do fim (_agenda_juntar). A linha "Para corrigir" vem depois (R5.6).
  v_cab := 'Quem faz o quê ' || v_modo || ':';
  v_max := least(cf.texto_max, c_max - 1 - char_length(v_fim));
  for i in 0 .. cardinality(v_los) + 2 loop
    v_corte := greatest(cardinality(v_los) - i, 0);
    v_l := array[v_cab] || v_lpes || case when i <= cardinality(v_los) then v_padrao else '' end
           || case when cardinality(v_los) = 0 or i > cardinality(v_los) + 1 then '{}'::text[]
                   when v_corte = 0
                   then array[format('O que as OS pedem: %s alguém em especial (me pergunte por uma).',
                                     public._agenda_plural(cardinality(v_los), 'OS pede', 'OS pedem'))]
                   else array['O que as OS pedem:'] || v_los[1:v_corte]
                        || case when v_corte < cardinality(v_los)
                                then array[format('• e mais %s OS.', cardinality(v_los) - v_corte)] else '{}'::text[] end end
           || coalesce(v_lteste, '') || v_lmed;
    v_txt := array_to_string(array(select x from unnest(v_l) with ordinality u(x, o) where x <> '' order by o), E'\n');
    exit when char_length(v_txt) <= v_max;
  end loop;
  if char_length(v_txt) > v_max then
    v_txt := public._agenda_juntar(v_l, v_max);
  end if;
  v_txt := public._agenda_corta(v_txt || E'\n' || v_fim, c_max);
  return jsonb_build_object('ok', true, 'rota', 'habilidades', 'texto', v_txt,
    'dados', jsonb_build_object('pessoas', v_pes, 'os', v_oss, 'em_teste', to_jsonb(v_teste), 'medidas', v_m,
                                'modo', cf.modo_habilidade, 'os_mostradas', v_corte));
end;
$function$;

comment on function public._agenda_ver_habilidades(date, timestamptz, uuid) is
  'Agenda de Produção (Fase 7c, P6; spec §5.6, §6.7; R5.6, R5.1-6): o foco habilidades de agenda_ver — quem faz o quê na equipe e o que cada OS pede, na palavra do dono. "Quem faz o quê (em teste: ainda escalo como antes):" (ligado "(já escalo por isso):"; desligado "(desligado: a agenda não usa):"); uma linha por pessoa (você primeiro; a grade de hoje a +13 e quem tem etiqueta: o texto de agenda_habilidades, com "; vale desde ter 03/11" na etiqueta do gestor e, no lugar do instala/ajudante, a proposta do gestor que ainda não vale — "Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você até ter 03/11)", "espero você ver a pergunta" antes de vista, "(em teste, eu marcaria: …)" em teste); "Quem não tem nada marcado pode tudo, menos comissionar."; "O que as OS pedem:" (as da carteira que pedem alguém em especial, as marcadas primeiro: "• Lenine: quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Substituição baterias - chumbo para litio"); responsável: Roberto (fez o 1º dia)."); "Em teste, hoje eu teria mudado: Ivo, ter 10/11 à tarde (poria Roberto)." (as ações de teste de hoje); "Nos últimos 30 dias: 0 vezes alguém sozinho em serviço que pede outra pessoa; 0 trocas de responsável; 3 meios-dias seus em serviço que outro faria." (agenda_habilidade_medidas); "Para corrigir, me diga numa frase (ex.: "o João instala sozinho")." O conteúdo até texto_max (saem as linhas de OS do fim, "• e mais N OS."), a linha "Para corrigir" depois; teto 1.500. Com p_os, só o bloco da OS: o que pede e de onde veio, o fechamento do dono que cobre o último dia, o responsável (_agenda_lider_da_os), quem vai no plano (_agenda_pessoas_texto), quem da equipe faz sozinho o que ela pede e quem precisa de alguém junto, com o porquê (_agenda_atende), os meios-dias marcados sem quem o serviço pede (_agenda_meios_sem_quem_pede, até 3) e o que eu teria mudado nela em teste. {ok, rota habilidades, texto, dados {pessoas, os, em_teste, medidas}}. Só lê. STABLE; definer (o responsável e as avaliações do publicado não têm grant), com a porta dentro (com login, só admin/financeiro: 42501; sem login, só o service_role); authenticated e service_role (agenda_ver, invoker, a chama). CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 16): o exemplo "o X instala sozinho" só para o 1º ajudante (papel 1); o novo (papel 2: o novato, quem vem sob demanda ou tem um dia fixo sem diária) nunca é o exemplo (a frase tiraria a proteção dele); sem ajudante, "o <responsável> é ajudante". CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590): (achado 16) com modo_habilidade_propor ligado e a proposta ainda de teste, "(ainda vou te perguntar; eu marcaria porque …)" no lugar de "(em teste, eu marcaria: …)"; (achado 3) com modo_habilidade fora de ligado e modo_dupla ligado, a linha de quem tem perfil de diária novo e uma etiqueta do dono valendo (instala ou ajudante) termina "(Isto já vale hoje: sendo novo, ele pode ir sozinho, porque você disse.)" ou "(… ele nunca vai sozinho.)", pelo _agenda_e_novato.';

-- agenda_rascunho_disponibilidade (de 20261101100800_agenda_fase77b_correcao.sql)
create or replace function public.agenda_rascunho_disponibilidade(p_autor uuid, p_canal text, p_pessoa text, p_situacao text,
                                                                  p_dias text, p_padrao boolean default false,
                                                                  p_trecho text default null,
                                                                  p_hoje date default public._hoje_brt(),
                                                                  p_semana text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_rp     jsonb;
  v_turno  text;
  v_sit    text;
  v_dias   smallint[];
  v_dt     jsonb;
  v_chave  text;
  v_dados  jsonb;
  v_txt    text;
  v_sab    boolean := false;
  -- FASE 7b: (7b P2) a semana dita, as datas de quem vem sob demanda e a pessoa do cadastro
  v_7b_modo  text := (public._agenda_cfg()).modo_dias;
  v_7b_sab   text := (public._agenda_cfg()).sabado_manha;
  v_7b_fora  boolean := false;
  v_7b_sem   jsonb;
  v_7b_seg   date;
  v_7b_dl    smallint[];
  v_7b_w     date;
  v_7b_datas date[];
  v_7b_d     date;
  v_7b_cad   jsonb;
  v_7b_n     int;
  v_7b_tok   text[];
  c_7b_vazias constant text[] := array['o', 'a', 'do', 'da', 'de', 'com', 'e', 'seu', 'sua', 'sr', 'senhor', 'tecnico'];
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 2, 13, 16 e 21) as datas ditas por extenso
  v_7bc_datas date[];
  v_7bc_d     date;
  v_7bc_dow   smallint[];
  v_7bc_m     text[];
  v_7bc_k     int;
  v_7bc_tr    text;
  -- FASE 7b: fim
  -- FASE 7c: (7c correção 2, achado 14) os números sem o mês nas datas ditas
  v_c14_r     record;
  v_c14_mes   int;
  v_c14_ano   int;
  -- FASE 7c: fim
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_disponibilidade: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  select x.turno, x.sit into v_turno, v_sit
    from (values ('vem', null, 'disponivel'), ('nao_vem', null, 'indisponivel'),
                 ('so_manha', 'tarde', 'indisponivel'), ('so_tarde', 'manha', 'indisponivel')) x(dito, turno, sit)
   where x.dito = lower(btrim(coalesce(p_situacao, '')));
  if not found then
    raise exception 'agenda_rascunho_disponibilidade: situação "%" não existe (vem, nao_vem, so_manha ou so_tarde)', p_situacao
      using errcode = '22023';
  end if;
  -- FASE 7b: (7b P2) a semana dita (p_semana): só com a pergunta dos dias fora de desligado (modo_dias); nunca padrão; os dias
  -- inteiros (meio dia só por data)
  if nullif(btrim(coalesce(p_semana, '')), '') is not null then
    if v_7b_modo = 'desligado' then
      return public._agenda_recusa('Anotar os dias de uma semana só ainda não está ligado. Diga as datas (ex.: "Roberto vem quarta dia 18") ou os dias de toda semana (ex.: "Roberto vem toda terça").',
                                   'semana_desligada');
    end if;
    if coalesce(p_padrao, false) then
      raise exception 'agenda_rascunho_disponibilidade: semana e padrão juntos (a semana dita nunca é padrão)' using errcode = '22023';
    end if;
    if v_turno is not null then
      return public._agenda_recusa('Para a semana, me diga os dias inteiros; meio dia só por data.', 'semana_turno');
    end if;
  end if;
  -- FASE 7b: fim
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras quem vem e quando.', 'sem_trecho');
  end if;
  if nullif(btrim(p_dias), '') is null then
    return public._agenda_recusa('Quais dias?', 'sem_dias');
  end if;

  v_rp := public.agenda_resolver_pessoa(p_pessoa, v_autor, p_hoje);
  -- FASE 7b: (7b P2, R4.2(c)3) quem o dono chama quando precisa (Mateus) ainda não está na equipe: com "vem" e a pergunta dos
  -- dias fora de desligado, procura entre as pessoas ATIVAS do cadastro (prestador, diarista ou funcionário; nunca o sócio) pela
  -- régua do nome do resolvedor (todo pedaço começa uma palavra do nome; o 1º nome igual vence)
  if v_7b_modo <> 'desligado' and v_rp ->> 'status' = 'nao_achei' and v_sit = 'disponivel' and v_turno is null then
    v_7b_tok := array(select t from unnest(string_to_array(public._agenda_normal(p_pessoa), ' ')) with ordinality u(t, o)
                       where length(t) >= 2 and t <> all (c_7b_vazias) order by o);
    if cardinality(v_7b_tok) > 0 then
      with gente as (
        select p.id, p.name, string_to_array(public._agenda_normal(p.name), ' ') as palavras
          from public.payees p
         where p.active and p.kind in ('prestador', 'diarista', 'funcionario')
      ),
      casam as (
        select g.*, g.palavras[1] = v_7b_tok[1] as exato from gente g
         where not exists (select 1 from unnest(v_7b_tok) t
                            where not exists (select 1 from unnest(g.palavras) w where w like t || '%'))
      ),
      melhor as (select c.* from casam c where c.exato or not exists (select 1 from casam x where x.exato))
      select coalesce(jsonb_agg(jsonb_build_object('payee_id', m.id, 'nome', m.name, 'nome_curto', public._agenda_nome_curto(m.name))
                                order by m.name, m.id), '[]'::jsonb), count(*)
        into v_7b_cad, v_7b_n
        from melhor m;
      if v_7b_n = 0 then
        return public._agenda_recusa(format('Não achei %s no cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo.',
                                            btrim(p_pessoa)), 'pessoa_sem_cadastro');
      end if;
      if v_7b_n > 1 then
        return public._agenda_recusa(format('Qual %s: %s ou %s?', btrim(p_pessoa),
                 array_to_string(array(select e ->> 'nome' from jsonb_array_elements(v_7b_cad) with ordinality t(e, o)
                                        where o < v_7b_n order by o), ', '),
                 v_7b_cad -> (v_7b_n - 1) ->> 'nome'),
               'pessoa_ambiguo', coalesce((select jsonb_agg(e ->> 'nome' order by o) from jsonb_array_elements(v_7b_cad) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      v_rp := jsonb_build_object('status', 'ok', 'payee_id', v_7b_cad -> 0 ->> 'payee_id', 'nome_curto', v_7b_cad -> 0 ->> 'nome_curto',
                                 'eh_dono', false, 'texto', v_7b_cad -> 0 ->> 'nome_curto');
      v_7b_fora := true;
    end if;
  end if;
  -- FASE 7b: fim
  if v_rp ->> 'status' <> 'ok' then
    return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
      coalesce((select jsonb_agg(e ->> 'nome' order by o)
                  from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
  end if;

  v_dados := jsonb_build_object(
    'grupo', 'pessoa:' || (v_rp ->> 'payee_id'), 'payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
    'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
    'rotulo_grupo', case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'Você' else v_rp ->> 'nome_curto' end,
    'padrao', coalesce(p_padrao, false), 'turno', v_turno, 'situacao', v_sit, 'dito', lower(btrim(p_situacao)));

  -- FASE 7b: (7b P2) a pessoa fora da equipe (a do cadastro) vai marcada no rascunho: a releitura diz que, com *grava*, ela entra
  if v_7b_modo <> 'desligado' then
    v_dados := v_dados || jsonb_build_object('fora_da_equipe', v_7b_fora);
  end if;
  -- a semana dita: os dias inteiros dela, nunca padrão (_agenda_equipe_dias_gravar prende a semana no *grava*)
  if nullif(btrim(coalesce(p_semana, '')), '') is not null then
    v_7b_sem := public._agenda_semana_dita(p_semana, p_trecho, p_hoje);
    if not (v_7b_sem ->> 'ok')::boolean then return v_7b_sem; end if;
    v_7b_seg := (v_7b_sem ->> 'seg')::date;
    if v_sit = 'disponivel' then
      begin
        v_dias := public.agenda_dias_da_semana_ditos(p_dias);
      exception when sqlstate '22007' then
        return public._agenda_recusa(sqlerrm, 'dias');
      end;
      if not (v_dias::int[] <@ public._agenda_dias_citados(p_trecho)) then
        return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quais dias.', btrim(p_dias)), 'fora_do_trecho');
      end if;
      v_sab := 6 = any (v_dias);
      v_dias := array_remove(v_dias, 6::smallint);
    elsif public._agenda_normal(p_dias) ~ '\m(nenhum|semana|todo|todos|toda|inteira)\M' then
      v_dias := '{}';
      v_sab := false;
    else
      return public._agenda_recusa('Para um dia só, me diga a data (ex.: "Roberto não vem quarta dia 18"); para a semana, os dias em que vem (ex.: "Roberto vem seg, ter e qui na semana que vem").',
                                   'semana_nao_vem_dia');
    end if;
    v_chave := format('disp:%s:s%s', v_rp ->> 'payee_id', v_7b_seg);
    v_dados := v_dados || jsonb_build_object(
      'grupo', 'pessoa:' || (v_rp ->> 'payee_id') || ':s' || v_7b_seg,
      'rotulo_grupo', (case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'Você' else v_rp ->> 'nome_curto' end)
                      || ', semana de ' || to_char(v_7b_seg, 'DD/MM'),
      'semana', v_7b_seg, 'dias_semana', to_jsonb(v_dias), 'sabado', v_sab, 'padrao', false);
    v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
    return jsonb_build_object('ok', true, 'item', v_txt,
                              'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
  end if;
  -- as datas de quem vem sob demanda ("Mateus vem qua e qui"): 2 ou mais dias da semana que não são uma faixa (a data dita é um
  -- dia só, ou não deu para ler) viram as datas desses dias na 1ª semana (seg a sáb) em que todos ainda estão por vir, estritamente
  -- depois de hoje; só dia útil; o sábado só de manhã e só com sabado_manha ≠ nunca. Nunca padrão.
  if v_7b_modo <> 'desligado' and not coalesce(p_padrao, false) and v_sit = 'disponivel' and v_turno is null then
    v_dt := public._agenda_data_conferida(p_dias, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean or v_dt ->> 'de' = v_dt ->> 'ate' then
      -- (correção da revisão da 7b, achado 16) as datas ditas por extenso — "qua 18/11 e qui 19/11", "18/11 e 19/11", "quarta dia
      -- 18 e quinta dia 19", "dia 18 e 19" — são essas datas: antes, o dia da semana vencia (qua e qui da 1ª semana por vir) ou só a 1ª
      -- data ficava, calada. Duas ou mais datas (dd/mm, ou "dia" com os números), cada número no que o dono disse; o dia da semana dito,
      -- se houver, tem de bater com elas; de hoje em diante (sem o ano: o próximo 18/11; sem o mês: este mês, ou o seguinte se o dia já
      -- passou); só dia útil, o sábado só de manhã e só com sabado_manha diferente de nunca. Nunca padrão.
      v_7bc_datas := '{}';
      v_7bc_tr := public._agenda_normal(p_trecho);
      if p_dias ~ '\d{1,2}/\d{1,2}' then
        for v_7bc_m in select m from regexp_matches(p_dias, '(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?', 'g') m loop
          continue when not (v_7bc_tr ~ ('\m0?' || v_7bc_m[1]::int || '\M'));
          begin
            v_7bc_d := make_date(case when v_7bc_m[3] is null then extract(year from p_hoje)::int
                                      when length(v_7bc_m[3]) = 2 then 2000 + v_7bc_m[3]::int else v_7bc_m[3]::int end,
                                 v_7bc_m[2]::int, v_7bc_m[1]::int);
          exception when others then
            return public._agenda_recusa(format('Não entendi a data "%s/%s": me diga de novo.', v_7bc_m[1], v_7bc_m[2]), 'data');
          end;
          if v_7bc_m[3] is null and v_7bc_d < p_hoje then
            v_7bc_d := make_date(extract(year from p_hoje)::int + 1, v_7bc_m[2]::int, v_7bc_m[1]::int);
          end if;
          if v_7bc_d < p_hoje then
            return public._agenda_recusa(format('"%s" já passou. Para quando é?', public._dia_curto(v_7bc_d)), 'data_passada');
          end if;
          v_7bc_datas := v_7bc_datas || v_7bc_d;
        end loop;
        -- (7c correção 2, achado 14) os números sem o mês, antes ou depois de uma data com o mês, são desse mês: "qui 19 e seg 23/11"
        -- = 19/11 e 23/11 (o "Se chamar, diga: Mateus vem qui 19 e seg 23/11" do quem chamar), "24, 25 e 26/11", "ter 10 e qua 11/11 e
        -- ter 24 e qua 25/11". Antes só a data com o mês contava e, sem 2 datas, valia o dia da semana na 1ª semana por vir, calado
        -- ("seg 09/11 e qui 12/11"). O mês (e o ano) é o da próxima data com o mês — o número maior que o dia dela é do mês de antes ("30
        -- e 02/12" = 30/11) —; sem uma depois, o da última antes. Hora ("8h", "8:00", "às 8", "das 8") e quantidade ("3 dias", "2 vezes")
        -- não são dia. Cada número no que o dono disse,
        -- de hoje em diante; o dia da semana dito continua tendo de bater, e o resto (dia útil, sábado, feriado) é o de antes (abaixo).
        for v_c14_r in
          with t as (
            select x.m[2]::int as d, x.m[3]::int as mes, x.m[4] as ano, x.m[1] as antes, x.m[5] as depois, x.o
              from regexp_matches(p_dias, '(\m(?:[aà]s|das)\s+)?(?<![\d/])(\d{1,2})(?!\d)(?:/(\d{1,2})(?:/(\d{2,4}))?)?(\s*(?:h|:|dias?\M|di[aá]rias?\M|vez(?:es)?\M|semanas?\M|m[eê]s(?:es)?\M|pessoas?\M))?', 'gi')
                   with ordinality x(m, o)
          )
          select t.d, t.antes, t.depois,
                 (select t2.d from t t2 where t2.o > t.o and t2.mes is not null order by t2.o limit 1) as d_dep,
                 (select t2.mes from t t2 where t2.o > t.o and t2.mes is not null order by t2.o limit 1) as mes_dep,
                 (select t2.ano from t t2 where t2.o > t.o and t2.mes is not null order by t2.o limit 1) as ano_dep,
                 (select t2.mes from t t2 where t2.o < t.o and t2.mes is not null order by t2.o desc limit 1) as mes_ant,
                 (select t2.ano from t t2 where t2.o < t.o and t2.mes is not null order by t2.o desc limit 1) as ano_ant
            from t where t.mes is null order by t.o
        loop
          continue when v_c14_r.antes is not null or v_c14_r.depois is not null or v_c14_r.d not between 1 and 31
                        or coalesce(v_c14_r.mes_dep, v_c14_r.mes_ant) is null;
          continue when not (v_7bc_tr ~ ('\m0?' || v_c14_r.d || '\M'));
          v_c14_mes := coalesce(v_c14_r.mes_dep, v_c14_r.mes_ant);
          v_c14_ano := case when coalesce(v_c14_r.ano_dep, v_c14_r.ano_ant) is null then extract(year from p_hoje)::int
                            when length(coalesce(v_c14_r.ano_dep, v_c14_r.ano_ant)) = 2 then 2000 + coalesce(v_c14_r.ano_dep, v_c14_r.ano_ant)::int
                            else coalesce(v_c14_r.ano_dep, v_c14_r.ano_ant)::int end;
          if v_c14_r.mes_dep is not null and v_c14_r.d > v_c14_r.d_dep then
            v_c14_ano := case when v_c14_mes = 1 then v_c14_ano - 1 else v_c14_ano end;
            v_c14_mes := case when v_c14_mes = 1 then 12 else v_c14_mes - 1 end;
          end if;
          begin
            v_7bc_d := make_date(v_c14_ano, v_c14_mes, v_c14_r.d);
          exception when others then
            return public._agenda_recusa(format('Não entendi o dia %s: me diga a data com o mês (ex.: 18/11).', v_c14_r.d), 'data');
          end;
          if coalesce(v_c14_r.ano_dep, v_c14_r.ano_ant) is null and v_7bc_d < p_hoje then
            v_7bc_d := (v_7bc_d + interval '1 year')::date;
          end if;
          if v_7bc_d < p_hoje then
            return public._agenda_recusa(format('"%s" já passou. Para quando é?', public._dia_curto(v_7bc_d)), 'data_passada');
          end if;
          v_7bc_datas := v_7bc_datas || v_7bc_d;
        end loop;
        -- (7c: fim)
      elsif public._agenda_normal(p_dias) ~ '\mdias?\s+\d{1,2}\M' then
        for v_7bc_k in select m[1]::int from regexp_matches(public._agenda_normal(p_dias), '\m(\d{1,2})\M', 'g') m loop
          continue when not (v_7bc_tr ~ ('\m0?' || v_7bc_k || '\M'));
          begin
            v_7bc_d := case when v_7bc_k >= extract(day from p_hoje)::int
                            then make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, v_7bc_k)
                            else make_date(extract(year from (date_trunc('month', p_hoje) + interval '1 month'))::int,
                                           extract(month from (date_trunc('month', p_hoje) + interval '1 month'))::int, v_7bc_k) end;
          exception when others then
            return public._agenda_recusa(format('Não entendi o dia %s: me diga a data com o mês (ex.: 18/11).', v_7bc_k), 'data');
          end;
          v_7bc_datas := v_7bc_datas || v_7bc_d;
        end loop;
      end if;
      v_7bc_datas := array(select distinct x from unnest(v_7bc_datas) x order by 1);
      if cardinality(v_7bc_datas) >= 2 then
        begin
          v_7bc_dow := public.agenda_dias_da_semana_ditos(p_dias);
        exception when others then
          v_7bc_dow := null;
        end;
        if cardinality(v_7bc_dow) > 0
           and array(select distinct x from unnest(v_7bc_dow) x order by 1)
               is distinct from array(select distinct extract(isodow from x)::smallint from unnest(v_7bc_datas) x order by 1) then
          return public._agenda_recusa(format('Os dias da semana e as datas não batem (%s): me diga de novo.',
                                              public._agenda_lista(array(select public._dia_curto(x) from unnest(v_7bc_datas) x order by x))),
                                       'datas_nao_batem');
        end if;
        foreach v_7bc_d in array v_7bc_datas loop
          if extract(isodow from v_7bc_d)::int = 6 then
            if v_7b_sab = 'nunca' then
              return public._agenda_recusa('Sábado eu não conto na agenda agora. Diga só os dias de segunda a sexta.', 'sabado_nunca');
            end if;
            if public.agenda_feriado(v_7bc_d) is not null then
              return public._agenda_recusa(format('%s é feriado (%s): outro dia?', public._dia_curto(v_7bc_d), public.agenda_feriado(v_7bc_d)),
                                           'feriado');
            end if;
          elsif not public.agenda_dia_util(v_7bc_d) then
            return public._agenda_recusa(case when public.agenda_feriado(v_7bc_d) is not null
                                              then format('%s é feriado (%s): outro dia?', public._dia_curto(v_7bc_d), public.agenda_feriado(v_7bc_d))
                                              else format('%s não é dia de trabalho na agenda: outro dia?', public._dia_curto(v_7bc_d)) end,
                                         'feriado');
          end if;
        end loop;
        v_chave := format('disp:%s:l%s:dia', v_rp ->> 'payee_id', array_to_string(v_7bc_datas, '_'));
        v_dados := v_dados || jsonb_build_object('datas', to_jsonb(v_7bc_datas));
        v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
        return jsonb_build_object('ok', true, 'item', v_txt,
                                  'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
      end if;
      -- (correção da revisão da 7b: fim)
      begin
        v_7b_dl := public.agenda_dias_da_semana_ditos(p_dias);
      exception when sqlstate '22007' then
        v_7b_dl := null;
      end;
      if cardinality(v_7b_dl) >= 2 and v_7b_dl::int[] <@ public._agenda_dias_citados(p_trecho) then
        v_7b_w := p_hoje - (extract(isodow from p_hoje)::int - 1);
        if exists (select 1 from unnest(v_7b_dl) x where v_7b_w + (x - 1) <= p_hoje) then
          v_7b_w := v_7b_w + 7;
        end if;
        v_7b_datas := array(select v_7b_w + (x - 1) from unnest(v_7b_dl) x order by 1);
        foreach v_7b_d in array v_7b_datas loop
          if extract(isodow from v_7b_d)::int = 6 then
            if v_7b_sab = 'nunca' then
              return public._agenda_recusa('Sábado eu não conto na agenda agora. Diga só os dias de segunda a sexta.', 'sabado_nunca');
            end if;
            if public.agenda_feriado(v_7b_d) is not null then
              return public._agenda_recusa(format('%s é feriado (%s): outro dia?', public._dia_curto(v_7b_d), public.agenda_feriado(v_7b_d)),
                                           'feriado');
            end if;
          elsif not public.agenda_dia_util(v_7b_d) then
            return public._agenda_recusa(case when public.agenda_feriado(v_7b_d) is not null
                                              then format('%s é feriado (%s): outro dia?', public._dia_curto(v_7b_d), public.agenda_feriado(v_7b_d))
                                              else format('%s não é dia de trabalho na agenda: outro dia?', public._dia_curto(v_7b_d)) end,
                                         'feriado');
          end if;
        end loop;
        v_chave := format('disp:%s:l%s:dia', v_rp ->> 'payee_id', array_to_string(v_7b_datas, '_'));
        v_dados := v_dados || jsonb_build_object('datas', to_jsonb(v_7b_datas));
        v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
        return jsonb_build_object('ok', true, 'item', v_txt,
                                  'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  if coalesce(p_padrao, false) then
    begin
      v_dias := public.agenda_dias_da_semana_ditos(p_dias);
    exception when sqlstate '22007' then
      return public._agenda_recusa(sqlerrm, 'dias');
    end;
    -- FASE 7b: (correção da revisão da 7b, achados 2, 13 e 21) "Alex saiu": o prompt manda nao_vem com padrao e "seg a sáb", e a opção 2
    -- da chamada dá esse exemplo, mas os dias não estão no que o dono disse (a régua dos dias no trecho recusava). Com a pergunta dos dias
    -- fora de desligado, quem saiu (saiu, saíram, não vem mais, não trabalha mais, não está mais, parou de vir, foi embora) vale a semana
    -- inteira: o mesmo rascunho de "não vem mais de segunda a sábado". Desligado, a recusa de antes.
    if v_7b_modo <> 'desligado' and v_sit = 'indisponivel' and v_turno is null
       and array[1, 2, 3, 4, 5]::smallint[] <@ v_dias
       and public._agenda_normal(p_trecho) ~ '\m(saiu|sairam|nao vem mais|nao vai mais|nao trabalha mais|nao esta mais|parou de vir|parou de trabalhar|foi embora|deixou a equipe)\M' then
      v_sab := 6 = any (v_dias) and not (public._agenda_cfg()).sabado_util;
      if v_sab then
        v_dias := array_remove(v_dias, 6::smallint);
      end if;
      v_chave := format('disp:%s:p%s:%s', v_rp ->> 'payee_id', array_to_string(v_dias, ''), coalesce(v_turno, 'dia'));
      v_dados := v_dados || jsonb_build_object('dias_semana', to_jsonb(v_dias), 'sabado_por_data', v_sab);
      v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
      return jsonb_build_object('ok', true, 'item', v_txt,
                                'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
    end if;
    -- FASE 7b: fim
    if not (v_dias::int[] <@ public._agenda_dias_citados(p_trecho)) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quais dias.', btrim(p_dias)), 'fora_do_trecho');
    end if;
    -- Sábado só por data (agenda_config.sabado_util): a capacidade e a grade não leem padrão de sábado. Só sábado =
    -- pergunta qual; com outros dias ("segunda a sábado"), fica o resto e a releitura diz que o sábado é por data.
    v_sab := 6 = any (v_dias) and not (public._agenda_cfg()).sabado_util;
    if v_sab then
      if cardinality(v_dias) = 1 then
        return public._agenda_recusa(case when v_sit = 'disponivel'
                                          then 'Sábado eu só conto por data: qual sábado? (por exemplo, "sábado dia 31")'
                                          else 'Sábado já fica fora da conta: só conto sábado quando você diz a data.' end,
                                     'sabado_padrao');
      end if;
      v_dias := array_remove(v_dias, 6::smallint);
    end if;
    v_chave := format('disp:%s:p%s:%s', v_rp ->> 'payee_id', array_to_string(v_dias, ''), coalesce(v_turno, 'dia'));
    -- sabado_por_data sempre escrito: a correção da mesma chave não herda o aviso de um sábado que não foi dito de novo.
    v_dados := v_dados || jsonb_build_object('dias_semana', to_jsonb(v_dias), 'sabado_por_data', v_sab);
  else
    v_dt := public._agenda_data_conferida(p_dias, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Para quando é?', btrim(p_dias)), 'data_passada');
    end if;
    v_chave := format('disp:%s:d%s_%s:%s', v_rp ->> 'payee_id', greatest((v_dt ->> 'de')::date, p_hoje), v_dt ->> 'ate',
                      coalesce(v_turno, 'dia'));
    v_dados := v_dados || jsonb_build_object('de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date);
  end if;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text) is
  'Agenda de Produção (Fase 1, P5): quem vem quando vira RASCUNHO (nada em agenda_disponibilidade). p_situacao vem (disponível), nao_vem (indisponível), so_manha (a tarde indisponível), so_tarde (a manhã indisponível); p_padrao = toda semana (agenda_dias_da_semana_ditos: "segunda a sexta"; sábado só por data, salvo sabado_util: só sábado = pergunta, com outros dias sai do padrão e a releitura avisa), senão a data dita (agenda_data_dita, futuro). Pessoa resolvida no banco ("eu" = o sócio do login); os dias têm de estar no trecho. Devolve {ok, item, releitura} ou {ok:false, pergunta}. Fase 7b (P2): assinatura nova com p_semana no fim (a de 8 argumentos saiu; a chamada por nome de antes continua casando). Com a pergunta dos dias fora de desligado (modo_dias): p_semana ("semana que vem", "semana de 16/11", por _agenda_semana_dita) = os dias da semana dita (vem + os dias, o sábado de manhã; nao_vem + "a semana toda" = nenhum; um dia só é por data), nunca padrão, sem turno; chave disp:<pessoa>:s<segunda>; a releitura "Roberto, semana de 16/11: vem seg, ter e qui (e não vem qua e sex)." — o *grava* prende a semana (_agenda_equipe_dias_gravar). Sem padrão e sem semana, "vem" com 2 ou mais dias da semana que não são uma faixa ("qua e qui") = as datas desses dias na 1ª semana (seg a sáb) em que todos ainda estão por vir, estritamente depois de hoje; só dia útil (o feriado é recusado com o nome); sábado só com sabado_manha ≠ nunca e só de manhã; chave disp:<pessoa>:l<d1>_<d2>…:dia; nunca padrão; "qua a sex" continua faixa. Quem não está na equipe mas está no cadastro (prestador, diarista ou funcionário ativo; o 1º nome igual vence) entra pelo rascunho com "vem" e a releitura diz que, com *grava*, ele entra; ninguém = "Não achei Vinicius no cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo."; vários = "Qual Mateus: …?". Com modo_dias desligado, o de antes, byte a byte, e p_semana é recusado com a frase. CORREÇÃO DA REVISÃO DA 7b (achados 2, 13, 16 e 21): com modo_dias fora de desligado — (a) "Alex saiu" (nao_vem, padrao, os dias da semana inteira, "seg a sáb" ou "seg a sex") com saiu, saíram, não vem mais, não trabalha mais, não está mais, parou de vir ou foi embora no trecho vale como a semana inteira, sem os dias no trecho: o mesmo rascunho de "não vem mais de segunda a sábado"; (b) as datas de quem vem sob demanda ditas por extenso (duas ou mais: dd/mm, ou "dia" com os números, cada número no trecho; "qua 18/11 e qui 19/11", "18/11 e 19/11", "quarta dia 18 e quinta dia 19", "dia 18 e 19") são essas datas, de hoje em diante (sem o ano, o próximo; sem o mês, este ou o seguinte), o dia da semana dito tem de bater ("Os dias da semana e as datas não batem (…): me diga de novo."), só dia útil e o sábado como antes; a faixa ("qui 19 a qua 25/11") e os dias da semana sem número seguem como antes. Desligado, a de antes. CORREÇÃO 2 DA REVISÃO DA 7c (20261102100590, achado 14; a 7b): com uma data com o mês, os números sem o mês antes ou depois dela também são datas desse mês ("qui 19 e seg 23/11" = 19/11 e 23/11; "24, 25 e 26/11"; o número maior que o dia da próxima data é do mês de antes; sem uma depois, o mês da última antes; hora e quantidade — "3 dias" — não são dia), cada um no que o dono disse; o dia da semana dito tem de bater, como antes. Antes, só a data com o mês contava e valia o dia da semana na 1ª semana por vir.';
