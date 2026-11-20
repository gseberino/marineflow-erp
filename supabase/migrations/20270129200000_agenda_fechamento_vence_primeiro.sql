-- Agenda de Produção — VENCE PRIMEIRO (20/11/2026): no fechamento das 17:30 a mensagem ao cliente mostrada inteira é a que vence primeiro.
--
-- Por quê (inventário de 19/11, roteiro T1-1): o fechamento mostra UMA mensagem esperando o *manda cliente* inteira e as outras como "E mais N".
-- Ela era escolhida pela hora de saída (enviar_em); a que vencia antes podia ficar escondida no "E mais N" e vencer sem o dono ver. A manhã
-- (Opção A, 20270128100000) já ordena pelo prazo: least(valida_ate, expira_em). Agora o fechamento usa o mesmo prazo.
--
-- O que muda: só a ordem do 1º laço de _agenda_cliente_fechamento (bloco "-- VENCE PRIMEIRO: … -- VENCE PRIMEIRO: fim"; a linha de antes em
-- "--antes:"). Tirado o bloco e devolvida a linha "--antes:", o corpo é o de produção de 20/11 (md5 sem CR 6744241e). Texto, perda, palavras,
-- a linha de perda 40 e as permissões (authenticated, service_role; sem anon) não mudam.
--
-- DESFAZER: reaplicar o corpo de 20261028100800_agenda_fase5_correcao_rodada.sql (a função _agenda_cliente_fechamento).

create or replace function public._agenda_cliente_fechamento(p_hoje date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  -- estrutural: a linha da aprovação leva a mensagem inteira (até 400) e as palavras; o secretário aceita até 640 por
  -- linha (secretario-tarde-coleta.ts, LINHA_DA_AGENDA_MAX)
  c_max_cliente constant int := 600;
  v_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_am     date := public._agenda_cliente_dia_seguinte(p_hoje);
  v_out    jsonb := '[]'::jsonb;
  r        record;
  v_n      int := 0;
  v_txt    text;
  v_itens  text[] := '{}';
  v_nomes  text[] := '{}';
  v_ini    timestamptz;
  v_rot    text;
begin
  for r in
    select m.tipo, m.texto, m.enviar_em, q.id as pergunta_id,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m
      join public.agenda_perguntas q on q.id = m.pergunta_id
      join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
       and q.tipo = 'cliente_aprovar' and q.estado = 'aberta'
       and (m.enviar_em at time zone 'America/Sao_Paulo')::date <= v_am
  -- VENCE PRIMEIRO: (20/11/2026) a 1ª (a inteira, com as palavras) é a que vence primeiro — o prazo da manhã, least(valida_ate, expira_em) —, não a que sai primeiro
--antes:     order by m.enviar_em, cl.name, m.tipo, m.id
     order by least(m.valida_ate, coalesce(q.expira_em, m.valida_ate)) nulls last, m.enviar_em, cl.name, m.tipo, m.id
  -- VENCE PRIMEIRO: fim
  loop
    v_n := v_n + 1;
    if v_n = 1 then
      v_txt := format('Mensagem para o %s (%s), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.', r.nome,
                      public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                      r.texto, r.nome, r.nome);
      if char_length(v_txt) + 80 > c_max_cliente then
        v_txt := format('Mensagem para o %s (%s), sai %s: "%s" (*agenda clientes* mostra inteira). *manda cliente %s* ou *segura cliente %s*.',
                        r.nome, public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                        public._agenda_corta(r.texto, 300), r.nome, r.nome);
      end if;
      -- CORREÇÃO FASE 5: (item 15) "Mensagem para Lucenira (…)" — sem artigo antes do nome (não há gênero no cadastro)
      v_txt := replace(v_txt, 'Mensagem para o ' || r.nome || ' (', 'Mensagem para ' || r.nome || ' (');
      -- CORREÇÃO FASE 5: fim
      v_out := jsonb_build_array(jsonb_build_object('tipo', 'cliente', 'texto', v_txt, 'perda', 75, 'pergunta_id', r.pergunta_id,
                                                    'acao_ids', '[]'::jsonb, 'modo', 'ligado'));
    end if;
  end loop;
  if v_n > 1 then
    v_out := jsonb_set(v_out, '{0,texto}', to_jsonb(left(v_txt || format(' E mais %s: *agenda clientes* mostra; *manda cliente* manda todas.', v_n - 1),
                                                          c_max_cliente)));
  end if;

  for r in
    select m.tipo, m.enviar_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono') and m.aprovacao in ('livre', 'aprovada')
       and (m.enviar_em at time zone 'America/Sao_Paulo')::date = v_am and v_am > p_hoje
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_ini := coalesce(v_ini, r.enviar_em);
    v_itens := v_itens || format('%s ao %s', public._agenda_cliente_o_que(r.tipo, r.dia), r.nome);
    -- CORREÇÃO FASE 5: (item 15) "a confirmação de ter 03/11 para Flávio" (sem artigo antes do nome)
    v_itens[cardinality(v_itens)] := format('%s para %s', public._agenda_cliente_o_que(r.tipo, r.dia), r.nome);
    -- CORREÇÃO FASE 5: fim
    if not r.nome = any (v_nomes) then
      v_nomes := v_nomes || r.nome;
    end if;
  end loop;
  if cardinality(v_itens) > 0 then
    v_rot := case when v_am = p_hoje + 1 then 'Amanhã' else 'Em ' || public._dia_curto(v_am) end;
    v_txt := format('%s, a partir das %s, vou mandar: %s%s. Para não mandar: *segura cliente %s*.', v_rot,
                    to_char(v_ini at time zone 'America/Sao_Paulo', 'HH24:MI'), public._agenda_lista(v_itens, 3),
                    case when cardinality(v_itens) > 3 then ' (*agenda clientes* mostra)' else '' end, v_nomes[1]);
    v_out := v_out || jsonb_build_object('tipo', 'cliente', 'texto', public._agenda_corta(v_txt, c_max_cliente), 'perda', 40,
                                         'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'ligado');
  end if;
  return v_out;
end;
$function$;

comment on function public._agenda_cliente_fechamento(date) is
  'Agenda de Produção (Fase 5, P5): as linhas tipo cliente do fechamento (só com modo_cliente ligado; quem chama, _agenda_linhas_do_fechamento, confere) — perda 75: a mensagem que espera *manda cliente* e sai até o próximo dia de janela ("Mensagem para o Nelson (aviso de atraso), sai amanhã às 09:00: "…". *manda cliente Nelson* ou *segura cliente Nelson*.", a 1ª inteira; com mais de uma, "E mais N: *agenda clientes* mostra; *manda cliente* manda todas."; acima de 600 caracteres o texto da mensagem é cortado em 300 com "(*agenda clientes* mostra inteira)"); perda 40: "Amanhã, a partir das 09:00, vou mandar: a confirmação de ter 03/11 ao Flávio e … Para não mandar: *segura cliente Flávio*." (as livres e aprovadas do próximo dia de janela, até 3). [{tipo, texto, perda, pergunta_id, acao_ids, modo}]. CORREÇÃO FASE 5 (C2, item 15): sem artigo antes do nome ("Mensagem para Nelson (aviso de atraso), sai amanhã às 09:00: …"; "… a confirmação de ter 03/11 para Flávio …"). VENCE PRIMEIRO (20/11/2026, 20270129200000; roteiro do inventário de 19/11, T1-1): a mensagem inteira da linha de perda 75 é a que VENCE primeiro (least(valida_ate, expira_em), o mesmo prazo de agenda_aprovacoes_da_manha), depois a que sai primeiro; antes era só a que sai primeiro, e a que vencia antes podia ficar no "E mais N". O resto, byte a byte.';

insert into supabase_migrations.schema_migrations (version, name) values ('20270129200000','agenda_fechamento_vence_primeiro');
