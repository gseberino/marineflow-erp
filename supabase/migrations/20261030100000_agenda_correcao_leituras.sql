-- Agenda de Produção, correção de 29/10 (pacote P1): o que o dono VÊ quando pergunta.
-- (2 funções novas; 3 recriadas; nenhuma tabela, coluna, CHECK nem parâmetro novo; nenhum dado muda)
--
-- NÃO APLICADA. Montada por scratchpad/agenda-pesquisa/p1c/montar-migration.mjs (edite as partes ou o montador, nunca este
-- .sql). Cada função recriada é o corpo da definição MAIS NOVA (conferido com grep: _agenda_semana_de e agenda_semana só em
-- 20261024160500; _agenda_ver_plano só em 20261025100500), com as mudanças só em blocos "-- CORREÇÃO 29/10 (P1): …
-- -- CORREÇÃO 29/10 (P1): fim"; fora deles nenhuma linha muda (o C6 de supabase/tests/agenda_correcao_2910_p1.sql confere).
--
-- ═══ POR QUE ═══ (auditoria de 29/10, leitor "entrega")
--   · Às 17:03 de qui 29/10 o dono mandou *agenda* e leu "Esta semana (seg 26/10 a sáb 31/10) não tem nada marcado…" e "Quer
--     que eu pergunte o que falta para montar a semana que vem?". A palavra mostra a semana corrente e o motor publica a
--     SEGUINTE na quinta às 16:30: de quinta a sábado *agenda* nunca mostra o que acabou de ser publicado (a reserva do Lenine
--     de 05, 06 e 10/11), e a oferta fala de montar uma semana que já foi montada.
--   · *agenda plano* não dizia quem vai na reserva ("Reserva: Lenine (OS-00074), se você disser até…") e cortava o bloco no
--     sábado da semana que vem (o 10/11 do Lenine sumia); *agenda semana que vem* também cortava ("qui 05 e sex 06/11").
--
-- ═══ O QUE MUDA ═══ (só com a agenda automática ligada, modo_proposta = 'ligado', em que o marcado é o plano)
--   1. _agenda_marcados_bloco (nova): o texto da semana de cada OS do plano com o bloco inteiro de um dia em diante e quem
--      vai ("Lenine (reserva, qui 05, sex 06 e ter 10/11, com João e Roberto)").
--   2. _agenda_plano_reservas (nova): no *agenda plano*, a reserva diz quem vai e que é reserva ("Lenine (OS-00074): João o
--      dia todo, Roberto o dia todo — reservado, se você disser até qua 04/11 se tem peça a comprar").
--   3. agenda_semana (de 20261024160500): a semana desta (o que *agenda* lê) mostra também a semana que vem quando ela já tem
--      plano ou quando nesta não sobra nada de hoje em diante: o resto desta semana ("De hoje a sáb 31/10 não tem mais nada
--      marcado…") e a semana que vem com o bloco inteiro e quem vai; a semana que vem (*agenda semana
--      que vem*) mostra o bloco inteiro e quem vai; e a oferta diz o que já tem na semana que vem.
--   4. _agenda_semana_de (de 20261024160500): monta essa 1ª linha (o resto e a semana que vem, as listas encolhem como as
--      outras) e a oferta com o que já tem ("Para marcar mais que a reserva para Lenine na semana que vem, preciso de umas
--      respostas suas: quer que eu pergunte? Uma resposta por OS; dá para responder num áudio."). A oferta continua: é a porta
--      da rodada de aprontar (agenda_ver foco aprontar, prompt.ts). Sem plano na semana que vem, a de sempre.
--   5. _agenda_ver_plano (de 20261025100500): a reserva pela função 2, e o bloco que tem dia no período e passa do fim dele
--      aparece inteiro, só com as OS dele ("Ter 10/11 (continua): …").
--   Não muda: agenda_linhas_do_dia (o "Hoje" da manhã e o "Amanhã" do fechamento), agenda_ver, o texto de *livre* (só lê o
--   resumo e o livre de agenda_semana, que ficam iguais) e o resumo da publicação.
--
-- Ordem de ligar: depois das migrations das Fases 0 a 6 (todas em produção); nenhuma chave nova. Aplicar com o OK nomeado do
-- dono. Prova: supabase/tests/agenda_correcao_2910_p1.sql (bancada).
--
-- DESFAZER: recriar cada função com o corpo da migration de onde ela foi copiada (a linha "-- <nome> (de <arquivo>)" acima de
-- cada uma); as duas novas podem ficar (ninguém as chama sem as recriadas desta migration) ou sair com
--   drop function if exists public._agenda_marcados_bloco(jsonb, date, date, boolean);
--   drop function if exists public._agenda_plano_reservas(jsonb, date, uuid[]);

-- ── 1. O bloco inteiro de cada OS do plano (e quem vai) ──────────────────────────────────────────────────────────
-- _agenda_marcados_bloco(p_marc, p_de, p_ate, p_pessoas): o marcado de _agenda_marcados com o texto da semana de cada OS do
-- PLANO (o item cujo "o" tem a chave reserva: _agenda_marcados em 'ligado') refeito com os dias dela no plano vigente de p_de
-- até p_ate — sem p_ate, o bloco inteiro, o dia depois do fim do período também ("Lenine (reserva, qui 05, sex 06 e ter
-- 10/11)") — e, com p_pessoas, quem vai (você primeiro, depois na ordem em que entra; só o nome que a leitura pode ver:
-- "…, com João e Roberto"). A hora do dia único é a do 1º meio-dia dele. O compromisso com hora e a janela antiga ficam como
-- vieram; a OS sem dia no intervalo também. Acrescenta texto_curto (sem quem vai), dias_bloco e pessoas_bloco ao item refeito. Os dias vêm de
-- v_agenda_dia; nada é calculado além do texto.
create or replace function public._agenda_marcados_bloco(p_marc jsonb, p_de date, p_ate date default null,
                                                         p_pessoas boolean default true)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_out  jsonb := '[]'::jsonb;
  e      jsonb;
  v_os   uuid;
  v_dias date[];
  v_hora text;
  v_res  boolean;
  v_pes  text;
  v_curto text;
  v_txt  text;
begin
  if p_de is null then
    raise exception '_agenda_marcados_bloco: sem o dia de início' using errcode = '22004';
  end if;
  for e in select x from jsonb_array_elements(coalesce(p_marc, '[]'::jsonb)) with ordinality t(x, o) order by o loop
    v_os := case when e ->> 'tipo' = 'os' and coalesce(e -> 'o', '{}'::jsonb) ? 'reserva' then (e #>> '{o,os}')::uuid end;
    v_dias := null;
    if v_os is not null then
      select array_agg(v.dia order by v.dia), bool_and(v.reserva),
             (array_agg(to_char(v.primeiro_inicio at time zone 'America/Sao_Paulo', 'HH24:MI') order by v.dia))[1]
        into v_dias, v_res, v_hora
        from public.v_agenda_dia v
       where v.service_order_id = v_os and v.dia >= p_de and (p_ate is null or v.dia <= p_ate);
    end if;
    if coalesce(cardinality(v_dias), 0) = 0 then
      v_out := v_out || jsonb_build_array(e);
      continue;
    end if;
    v_pes := null;
    if coalesce(p_pessoas, true) then
      -- (o mesmo nome uma vez só: o dono é "você")
      select nullif(public._agenda_lista(array_agg(q.quem order by q.dono desc, q.primeiro, q.quem), null), '')
        into v_pes
        from (select p.quem, bool_or(p.dono) as dono, min(p.dia) as primeiro
                from (select case when coalesce((x ->> 'eh_dono')::boolean, false) then 'você' else x ->> 'nome' end as quem,
                             coalesce((x ->> 'eh_dono')::boolean, false) as dono, v.dia
                        from public.v_agenda_dia v
                       cross join lateral jsonb_array_elements(v.pessoas) x
                       where v.service_order_id = v_os and v.dia >= p_de and (p_ate is null or v.dia <= p_ate)) p
               where p.quem is not null
               group by p.quem) q;
    end if;
    -- o texto sem quem vai (texto_curto: o que sai quando o com quem não cabe no teto) e o texto da semana
    v_curto := case when v_res then format('%s (reserva, %s)', e ->> 'nome', public._agenda_dias_texto(v_dias))
                    when cardinality(v_dias) = 1 then format('%s (%s%s)', e ->> 'nome', public._dia_curto(v_dias[1]),
                                                             coalesce(' às ' || v_hora, ''))
                    else format('%s (%s)', e ->> 'nome', public._agenda_dias_texto(v_dias)) end;
    v_txt := case when v_pes is null then v_curto else left(v_curto, -1) || ', com ' || v_pes || ')' end;
    v_out := v_out || jsonb_build_array(e || jsonb_build_object('texto_semana', v_txt, 'texto_curto', v_curto,
                                                               'dias_bloco', to_jsonb(v_dias), 'pessoas_bloco', v_pes));
  end loop;
  return v_out;
end;
$function$;

comment on function public._agenda_marcados_bloco(jsonb, date, date, boolean) is
  'Agenda de Produção (correção de 29/10, P1): o marcado de _agenda_marcados com o texto da semana de cada OS do plano refeito com os dias dela de p_de até p_ate (sem p_ate, o bloco inteiro, o dia depois do fim do período também: "Lenine (reserva, qui 05, sex 06 e ter 10/11)") e, com p_pessoas, quem vai (você primeiro; só o nome que a leitura pode ver: "Vanderlei (ter 03 a qui 05/11, com você e Roberto)", "Rodrigo OS-00096 (ter 03/11 às 13:00, com você)"). O compromisso, a janela antiga e a OS sem dia no intervalo ficam como vieram. Acrescenta texto_curto (sem quem vai), dias_bloco e pessoas_bloco. Invoker, STABLE.';

-- ── 2. A reserva no plano diz quem vai e que é reserva ─────────────────────────────────────────────────────────────
-- _agenda_plano_reservas(p_lin, p_dia, p_vistas): as linhas de agenda_linhas_do_dia (que o fechamento e a manhã usam e que
-- aqui não mudam) com o texto de cada RESERVA refeito para o *agenda plano*: o nome e o número, quem vai e "reservado"
-- ("Lenine (OS-00074): João o dia todo, Roberto o dia todo — reservado, se você disser até qua 04/11 se tem peça a
-- comprar"; no pátio "reservado no pátio"; acima da carga "reservado (acima da carga)"). A OS que já está em p_vistas
-- (apareceu antes na mesma leitura) diz "(mesma condição)" no lugar da condição. A linha que não é reserva fica como veio.
create or replace function public._agenda_plano_reservas(p_lin jsonb, p_dia date, p_vistas uuid[] default '{}')
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(
           case when coalesce((x ->> 'reserva')::boolean, false) and v.service_order_id is not null then
             x || jsonb_build_object('texto',
               coalesce(v.cliente_curto || ' (' || v.numero || ')', v.numero)
               || coalesce(': ' || nullif(public._agenda_pessoas_do_dia(v.pessoas), ''), '')
               || ' — reservado'
               || case v.reserva_de when 'patio' then ' no pátio' when 'teto' then ' (acima da carga)' else '' end
               || case when v.condicao is null then ''
                       when v.service_order_id = any (coalesce(p_vistas, '{}'::uuid[])) then ' (mesma condição)'
                       else ', ' || v.condicao end)
           else x end
           order by t.o), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_lin, '[]'::jsonb)) with ordinality t(x, o)
    left join public.v_agenda_dia v on v.dia = p_dia and v.service_order_id = (x ->> 'os')::uuid;
$function$;

comment on function public._agenda_plano_reservas(jsonb, date, uuid[]) is
  'Agenda de Produção (correção de 29/10, P1): as linhas de agenda_linhas_do_dia com o texto de cada reserva refeito para o *agenda plano* — o nome e o número, quem vai e "reservado" ("Lenine (OS-00074): João o dia todo, Roberto o dia todo — reservado, se você disser até qua 04/11 se tem peça a comprar"; "reservado no pátio"; "reservado (acima da carga)"); a OS que já está em p_vistas diz "(mesma condição)". A linha que não é reserva fica como veio. agenda_linhas_do_dia (a manhã e o fechamento) não muda. Invoker, STABLE.';

-- ── 3. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO 29/10 (P1):") ──────────
-- Fora dos blocos nenhuma linha muda (o C6 de supabase/tests/agenda_correcao_2910_p1.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration.

-- _agenda_semana_de (de 20261024160500_agenda_fase1_leituras.sql)
create or replace function public._agenda_semana_de(p_pn jsonb, p_de date, p_ate date, p_marc jsonb, p_lim jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_hoje    date := (p_pn ->> 'hoje')::date;
  v_rot     text := public._agenda_periodo_rotulo(p_de, p_ate, v_hoje);
  v_ela     boolean := v_rot like 'Esta semana%' or v_rot like 'A semana que vem%';
  v_aviso   text := p_pn ->> 'aviso_diarias';
  v_quase   jsonb := public._agenda_lista_de(p_pn, 'quase');
  v_prontos jsonb;
  v_andam   jsonb;
  v_trav    jsonb;
  v_esper   jsonb;
  v_parad   jsonb;
  v_espera  jsonb;
  v_listas  jsonb := '{}'::jsonb;
  l_marc    text;
  l_resumo  text := public._agenda_resumo(p_pn, v_ela);
  l_prontos text;
  l_andam   text;
  l_trav    text;
  l_esper   text;
  l_parad   text;
  l_espera  text;
  l_livre   text := public._agenda_livre_linha(p_pn, true);
  l_oferta  text;
  -- CORREÇÃO 29/10 (P1): o resto desta semana e a semana que vem já montada (p_pn.seguinte, de agenda_semana)
  v_seg     jsonb := p_pn -> 'seguinte';
  v_resto   jsonb;
  v_prox    jsonb;
  v_rot_r   text;
  v_rot_p   text;
  l_resto   text;
  l_prox    text;
  v_tem     text[];
  -- CORREÇÃO 29/10 (P1): fim
begin
  if jsonb_array_length(p_marc) = 0 then
    l_marc := v_rot || ' não tem nada marcado' || coalesce(', e ' || v_aviso, '') || '.';
  else
    l_marc := v_rot || ': ' || public._agenda_lista(array(select e ->> 'texto_semana' from jsonb_array_elements(p_marc)
                                                            with ordinality t(e, o) order by o), public._agenda_lim(p_lim, 'marc'))
              || '.' || coalesce(' ' || public._agenda_maiuscula(v_aviso) || '.', '');
    v_listas := v_listas || jsonb_build_object('marc', jsonb_build_object('linha', 0, 'n', jsonb_array_length(p_marc)));
  end if;
  -- CORREÇÃO 29/10 (P1): com a semana que vem já montada (ou sem nada desta semana de hoje em diante), a 1ª linha diz o
  -- resto desta semana e a semana que vem, cada OS da semana que vem com o bloco inteiro ("Lenine (reserva, qui 05, sex 06 e
  -- ter 10/11)"). Quem decide é agenda_semana (p_pn.seguinte.modo = 'estendida'). O marcado é a resposta de *agenda*: as
  -- listas dele ('marc' = o resto desta semana, 'prox' = a semana que vem; e a 'marc' da semana que vem, modo 'bloco') ficam
  -- com a linha 99, fora do texto, para _agenda_encolher só tirar nome delas depois de as outras listas chegarem a um nome;
  -- a que perdeu nome termina com "(*agenda plano* mostra tudo)".
  if v_seg ->> 'modo' = 'estendida' then
    v_resto := coalesce(v_seg -> 'resto', '[]'::jsonb);
    v_prox := coalesce(v_seg -> 'marc', '[]'::jsonb);
    v_listas := v_listas - 'marc';
    -- (no domingo esta semana já passou: só a semana que vem)
    if v_hoje <= p_ate then
      v_rot_r := case when v_hoje <= p_de then v_rot
                      when v_hoje = p_ate then public._agenda_dia_rotulo(v_hoje, v_hoje)
                      else 'De hoje a ' || public._dia_curto(p_ate) end;
      if jsonb_array_length(v_resto) = 0 then
        l_resto := v_rot_r || case when v_hoje <= p_de then ' não tem nada marcado' else ' não tem mais nada marcado' end
                   || coalesce(', e ' || v_aviso, '') || '.';
      else
        l_resto := v_rot_r || ': '
                   || public._agenda_lista(array(select e ->> 'texto_semana' from jsonb_array_elements(v_resto) with ordinality t(e, o)
                                                  order by o), public._agenda_lim(p_lim, 'marc'))
                   || case when public._agenda_lim(p_lim, 'marc') < jsonb_array_length(v_resto) then ' (*agenda plano* mostra tudo)' else '' end
                   || '.' || coalesce(' ' || public._agenda_maiuscula(v_aviso) || '.', '');
        v_listas := v_listas || jsonb_build_object('marc', jsonb_build_object('linha', 99, 'n', jsonb_array_length(v_resto)));
      end if;
    end if;
    v_rot_p := public._agenda_periodo_rotulo((v_seg ->> 'de')::date, (v_seg ->> 'ate')::date, v_hoje);
    if jsonb_array_length(v_prox) = 0 then
      l_prox := v_rot_p || ' ainda não tem nada marcado.';
    else
      l_prox := v_rot_p || ': '
                || public._agenda_lista(array(select e ->> 'texto_semana' from jsonb_array_elements(v_prox) with ordinality t(e, o)
                                               order by o), public._agenda_lim(p_lim, 'prox'))
                || case when public._agenda_lim(p_lim, 'prox') < jsonb_array_length(v_prox) then ' (*agenda plano* mostra tudo)' else '' end
                || '.';
      v_listas := v_listas || jsonb_build_object('prox', jsonb_build_object('linha', 99, 'n', jsonb_array_length(v_prox)));
    end if;
    -- sem o resto desta semana, o aviso das diárias vai na linha da semana que vem
    if l_resto is null and v_aviso is not null then
      l_prox := l_prox || ' ' || public._agenda_maiuscula(v_aviso) || '.';
    end if;
    l_marc := concat_ws(E'\n', l_resto, l_prox);
  elsif v_seg ->> 'modo' = 'bloco' and v_listas ? 'marc' then
    v_listas := jsonb_set(v_listas, '{marc,linha}', '99'::jsonb);
    -- (passou do teto: primeiro sai o com quem, depois os nomes do fim; a lista que perdeu nome diz onde está tudo)
    if public._agenda_lim(p_lim, 'marc') < jsonb_array_length(p_marc) then
      l_marc := v_rot || ': '
                || public._agenda_lista(array(select coalesce(e ->> 'texto_curto', e ->> 'texto_semana') from jsonb_array_elements(p_marc)
                                               with ordinality t(e, o) order by o), public._agenda_lim(p_lim, 'marc') + 1)
                || case when public._agenda_lim(p_lim, 'marc') + 1 < jsonb_array_length(p_marc) then ' (*agenda plano* mostra tudo)' else '' end
                || '.' || coalesce(' ' || public._agenda_maiuscula(v_aviso) || '.', '');
    end if;
  end if;
  -- CORREÇÃO 29/10 (P1): fim

  -- Prontos ("a partir de" quando o material ou o bem seguram) e quase (só falta dizer se tem peça a comprar).
  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when (e ->> 'est')::date > public.agenda_somar_du(v_hoje, 1) then 'a partir de ' || (e ->> 'est_texto') end)
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  l_prontos := 'Prontos para começar: '
    || coalesce(nullif(public._agenda_nomes(v_prontos, public._agenda_lim(p_lim, 'prontos')), ''), 'nenhum') || '.'
    || case when jsonb_array_length(v_quase) > 0 then
         ' Quase: ' || public._agenda_nomes(v_quase, public._agenda_lim(p_lim, 'quase'))
         || case when jsonb_array_length(v_quase) = 1 then ', se não tiver peça a comprar.' else ', se não tiverem peça a comprar.' end
       else '' end;
  if jsonb_array_length(v_prontos) > 0 then
    v_listas := v_listas || jsonb_build_object('prontos', jsonb_build_object('linha', 2, 'n', jsonb_array_length(v_prontos)));
  end if;
  if jsonb_array_length(v_quase) > 0 then
    v_listas := v_listas || jsonb_build_object('quase', jsonb_build_object('linha', 2, 'n', jsonb_array_length(v_quase)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when e ->> 'estado' = 'parada' then regexp_replace(e ->> 'estado_texto', '^em andamento ', '') end)
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_andam from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'andamento';
  if jsonb_array_length(v_andam) > 0 then
    l_andam := 'Em andamento: ' || public._agenda_nomes(v_andam, public._agenda_lim(p_lim, 'andam')) || '.';
    v_listas := v_listas || jsonb_build_object('andam', jsonb_build_object('linha', 3, 'n', jsonb_array_length(v_andam)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo', public._agenda_restricao_curta(e -> 'principal'))
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_trav from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'travado';
  if jsonb_array_length(v_trav) > 0 then
    l_trav := 'Travados por material: ' || public._agenda_nomes(v_trav, public._agenda_lim(p_lim, 'trav')) || '.';
    v_listas := v_listas || jsonb_build_object('trav', jsonb_build_object('linha', 4, 'n', jsonb_array_length(v_trav)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           replace(e ->> 'estado_texto', ' e nunca virou OS', ', nunca virou OS'))
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_esper from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'esperando';
  if jsonb_array_length(v_esper) > 0 then
    l_esper := 'Esperando você: ' || public._agenda_nomes(v_esper, public._agenda_lim(p_lim, 'esper')) || '.';
    v_listas := v_listas || jsonb_build_object('esper', jsonb_build_object('linha', 5, 'n', jsonb_array_length(v_esper)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when e ->> 'estado' = 'sem_sinal' then 'sinal'
                when e ->> 'status' = 'awaiting_client' then null
                else e ->> 'estado_texto' end)
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_parad from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'parado';
  if jsonb_array_length(v_parad) > 0 then
    l_parad := 'Parados no cliente: ' || public._agenda_nomes(v_parad, public._agenda_lim(p_lim, 'parad')) || '.';
    v_listas := v_listas || jsonb_build_object('parad', jsonb_build_object('linha', 6, 'n', jsonb_array_length(v_parad)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo', substring(e ->> 'estado_texto' from 'até [^ ]+ [^ ]+'))
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_espera from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'espera';
  if jsonb_array_length(v_espera) > 0 then
    l_espera := 'Em espera (você pediu): ' || public._agenda_nomes(v_espera, public._agenda_lim(p_lim, 'espera')) || '.';
    v_listas := v_listas || jsonb_build_object('espera', jsonb_build_object('linha', 7, 'n', jsonb_array_length(v_espera)));
  end if;

  if (p_pn ->> 'oferta')::boolean then
    l_oferta := 'Quer que eu pergunte o que falta para montar a semana que vem? Uma resposta por OS; dá para responder num áudio.';
    -- CORREÇÃO 29/10 (P1): com a semana que vem já montada, a oferta diz o que já tem nela (continua sendo a porta da
    -- rodada de aprontar: "quer que eu pergunte?"); p_pn.seguinte.plano vem de agenda_semana, na ordem do 1º dia
    v_tem := array(select x from jsonb_array_elements_text(coalesce(v_seg -> 'plano', '[]'::jsonb)) with ordinality t(x, o)
                    order by o);
    if cardinality(v_tem) > 0 then
      l_oferta := case when cardinality(v_tem) <= 3
                       then format('Para marcar mais que %s na semana que vem', public._agenda_lista(v_tem, null))
                       else 'Para marcar mais na semana que vem' end
                  || ', preciso de umas respostas suas: quer que eu pergunte? Uma resposta por OS; dá para responder num áudio.';
    end if;
    -- CORREÇÃO 29/10 (P1): fim
  end if;

  -- As linhas na posição fixa (as vazias somem em _agenda_juntar); "listas" diz em que linha está cada lista.
  return jsonb_build_object(
    'linhas', jsonb_build_array(l_marc, l_resumo, l_prontos, l_andam, l_trav, l_esper, l_parad, l_espera, l_livre, l_oferta),
    'listas', v_listas,
    'textos', jsonb_build_object('marcados', l_marc, 'aviso', v_aviso, 'resumo', l_resumo, 'prontos', l_prontos,
                                 'andamento', l_andam, 'travados', l_trav, 'esperando', l_esper, 'parados', l_parad,
                                 'espera', l_espera, 'livre', l_livre, 'oferta', l_oferta),
    'dados', jsonb_build_object('de', p_de, 'ate', p_ate, 'marcados', p_marc, 'fila', p_pn -> 'backlog',
                                'capacidade', p_pn -> 'comprometivel', 'conta_dono', p_pn #> '{cap,conta_dono}',
                                'livre', p_pn -> 'livre',
                                'grupos', (select coalesce(jsonb_object_agg(x.g, x.n), '{}'::jsonb) from (
                                             select e ->> 'grupo' as g, count(*) as n from jsonb_array_elements(p_pn -> 'oss') e
                                              group by 1) x)));
end;
$function$;

comment on function public._agenda_semana_de(jsonb, date, date, jsonb, jsonb) is 'Agenda de Produção (Fase 1, P4): as linhas da semana a partir do painel e do marcado, com os limites de nomes por lista (p_lim). Devolve {linhas (posição fixa), listas {nome:{linha, n}}, textos, dados}. CORREÇÃO 29/10 (P1): com p_pn.seguinte.modo = ''estendida'' (agenda_semana: a semana desta com a semana que vem já montada, ou sem nada desta de hoje em diante) a 1ª linha diz o resto desta semana ("De hoje a sáb 31/10 não tem mais nada marcado…") e a semana que vem com o bloco inteiro e quem vai (listas marc e prox, que encolhem como as outras); com p_pn.seguinte.plano (o que já está na semana que vem), a oferta diz o que já tem ("Para marcar mais que a reserva para Lenine na semana que vem, preciso de umas respostas suas: quer que eu pergunte? …"); sem isso, a de sempre.';

-- agenda_semana (de 20261024160500_agenda_fase1_leituras.sql)
create or replace function public.agenda_semana(p_de date default null, p_ate date default null,
                                                p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn   jsonb;
  v_r    jsonb;
  v_de   date;
  v_ate  date;
  v_max  int;
  v_marc jsonb;
  v_lim  jsonb := '{}'::jsonb;
  v_novo jsonb;
  v_lin  text[];
  v_tar  text;
  v_n    int;
  v_atr  int;
  v_usu  uuid;
  -- CORREÇÃO 29/10 (P1): a segunda-feira desta semana, a agenda automática ligada, o que já está na semana que vem, o resto
  -- desta semana e o que vai a _agenda_semana_de (p_pn.seguinte)
  v_seg1 date := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_lig  boolean;
  v_plan text[];
  v_rest jsonb;
  v_prox jsonb;
  v_ext  jsonb;
  -- CORREÇÃO 29/10 (P1): fim
begin
  if p_hoje is null then
    raise exception 'agenda_semana: sem o dia de hoje' using errcode = '22004';
  end if;
  v_de := coalesce(p_de, p_hoje - (extract(isodow from p_hoje)::int - 1));
  v_ate := coalesce(p_ate, v_de + 5);
  if v_ate < v_de then
    raise exception 'agenda_semana: período invertido (% a %)', v_de, v_ate using errcode = '22023';
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_max := (v_pn ->> 'texto_max')::int;
  v_marc := public._agenda_marcados(v_de, v_ate, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
  -- CORREÇÃO 29/10 (P1): com a agenda automática ligada (o marcado é o plano), a semana desta (seg a sáb de hoje) mostra
  -- também a semana que vem quando ela já tem plano ou quando nesta não sobra nada de hoje em diante (o motor publica a
  -- semana SEGUINTE na quinta: de quinta a sábado *agenda* dizia "nada marcado" com a semana que vem montada); a semana que
  -- vem mostra o bloco inteiro (o dia depois do sábado também) e quem vai; e a oferta diz o que já tem na semana que vem.
  v_lig := coalesce((public._agenda_cfg()).modo_proposta = 'ligado', false);
  if v_lig and v_de = v_seg1 and v_ate = v_seg1 + 5 then
    v_prox := public._agenda_marcados(v_seg1 + 7, v_seg1 + 12, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
  elsif v_lig and v_de = v_seg1 + 7 and v_ate = v_seg1 + 12 then
    v_prox := v_marc;
  end if;
  if v_prox is not null then
    -- o que já está no plano da semana que vem, na ordem do 1º dia ("Vanderlei", "a reserva para Lenine")
    v_plan := array(select case when coalesce((e #>> '{o,reserva}')::boolean, false) then 'a reserva para ' || (e ->> 'nome')
                                else e ->> 'nome' end
                      from jsonb_array_elements(v_prox) with ordinality t(e, o)
                     where e ->> 'tipo' = 'os' and coalesce(e -> 'o', '{}'::jsonb) ? 'reserva'
                     order by o);
    if v_de = v_seg1 then
      -- o resto desta semana: o que termina hoje ou depois, com os dias de hoje ao sábado
      v_rest := public._agenda_marcados_bloco(
                  coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_marc) with ordinality t(e, o)
                             where (e ->> 'ate')::date >= p_hoje), '[]'::jsonb), p_hoje, v_seg1 + 5, false);
      if cardinality(v_plan) > 0 or jsonb_array_length(v_rest) = 0 then
        -- a semana que vem com o bloco inteiro de cada OS (sem quem vai: cabe no teto; quem vai está em *agenda plano* e em
        -- *agenda semana que vem*)
        v_prox := public._agenda_marcados_bloco(v_prox, v_seg1 + 7, null, false);
        v_ext := jsonb_build_object('modo', 'estendida', 'resto', v_rest, 'de', v_seg1 + 7, 'ate', v_seg1 + 12, 'marc', v_prox,
                                    'plano', to_jsonb(v_plan));
      end if;
    else
      v_marc := public._agenda_marcados_bloco(v_marc, v_de, null, true);
      v_ext := jsonb_build_object('modo', 'bloco', 'plano', to_jsonb(v_plan));
    end if;
    if v_ext is not null then
      v_pn := v_pn || jsonb_build_object('seguinte', v_ext);
    end if;
  end if;
  -- CORREÇÃO 29/10 (P1): fim
  -- Até 5 nomes por lista; passou do teto, a lista da linha mais longa perde um nome por vez ("e mais N").
  loop
    v_r := public._agenda_semana_de(v_pn, v_de, v_ate, v_marc, v_lim);
    exit when char_length(public._agenda_juntar(public._agenda_linhas(v_r), null)) <= v_max;
    v_novo := public._agenda_encolher(v_r, v_lim);
    exit when v_novo is null;
    v_lim := v_novo;
  end loop;
  -- As tarefas do dono no período (a regra de my_agenda; sem as que já estão no marcado) e, se o período inclui
  -- hoje, as atrasadas: só a contagem, depois do marcado, quando cabe no teto (a semana é a da produção; o título de
  -- cada tarefa está no dia: *agenda hoje*).
  v_lin := public._agenda_linhas(v_r);
  v_usu := (v_pn ->> 'dono_usuario')::uuid;
  if v_usu is not null then
    -- Com hoje no período, o "com prazo" conta de hoje em diante (o que ficou para trás é a atrasada: não conta duas vezes).
    select count(*) filter (where x.ancora >= ((case when p_hoje between v_de and v_ate then p_hoje else v_de end)::timestamp
                                               at time zone 'America/Sao_Paulo')
                              and x.ancora < ((v_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
                              and not x.no_marcado),
           count(*) filter (where p_hoje between v_de and v_ate
                              and x.ancora < (p_hoje::timestamp at time zone 'America/Sao_Paulo'))
      into v_n, v_atr
      from (select coalesce(t.due_at, t.scheduled_start_at) as ancora,
                   coalesce(t.scheduled_start_at >= (v_de::timestamp at time zone 'America/Sao_Paulo')
                            and t.scheduled_start_at < ((v_ate + 1)::timestamp at time zone 'America/Sao_Paulo'), false)
                     as no_marcado
              from public.agenda_tasks t
             where t.assignee_user_id = v_usu and t.status in ('pending', 'in_progress')) x;
    if v_n > 0 or v_atr > 0 then
      v_tar := 'Tarefas: ' || concat_ws(' e ',
                 case when v_n > 0 then public._agenda_plural(v_n, 'com prazo no período', 'com prazo no período') end,
                 case when v_atr > 0 then public._agenda_plural(v_atr, 'atrasada', 'atrasadas') end) || '.';
      if char_length(public._agenda_juntar(v_lin, null)) + 1 + char_length(v_tar) <= v_max then
        v_lin := v_lin[1:1] || v_tar || v_lin[2:];
      end if;
    end if;
  end if;
  -- CORREÇÃO 29/10 (P1): o que a 1ª linha mostrou da semana que vem (e do resto desta), para quem lê os dados
  if v_ext is not null then
    v_r := jsonb_set(v_r, '{dados,semana_que_vem}', v_ext);
  end if;
  -- CORREÇÃO 29/10 (P1): fim
  return jsonb_build_object('ok', true,
    'texto', public._agenda_juntar(v_lin, v_max),
    'dados', (v_r -> 'dados') || jsonb_build_object('textos', v_r -> 'textos', 'tarefas_no_periodo', v_n,
                                                    'tarefas_atrasadas', v_atr));
end;
$function$;

comment on function public.agenda_semana(date, date, date) is 'Agenda de Produção (Fase 1, P4): "como tá a semana?" — o marcado no período (janela antiga + compromisso com hora do dono), o aviso de diárias faltando, a fila em faixa com o único número de capacidade, prontos/quase/travados por material/esperando você/parados no cliente, o livre de verdade em faixa e a oferta da rodada. Sem período: seg–sáb da semana de p_hoje. Até 5 nomes por lista; passou de texto_max, a lista mais longa perde nomes ("e mais N"). {ok, texto, dados{…, textos}}. CORREÇÃO 29/10 (P1): com a agenda automática ligada (modo_proposta ligado: o marcado é o plano), a semana desta (seg a sáb de hoje) mostra também a semana que vem quando ela já tem plano ou quando nesta não sobra nada de hoje em diante (o resto desta semana e a semana que vem, cada OS com o bloco inteiro e quem vai: _agenda_marcados_bloco); a semana que vem mostra o bloco inteiro (os dias depois do sábado também) e quem vai; e, com a semana que vem já montada, a oferta diz o que já tem nela. dados.semana_que_vem = {modo (estendida|bloco), resto, de, ate, marc, plano}. Fora de ligado, ou em outro período, tudo como antes.';

-- _agenda_ver_plano (de 20261025100500_agenda_fase2_leituras.sql)
create or replace function public._agenda_ver_plano(p_de date, p_ate date, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_de   date := coalesce(p_de, p_hoje);
  v_ate  date := coalesce(p_ate, p_hoje - (extract(isodow from p_hoje)::int - 1) + 12);
  v_l    text[] := '{}';
  v_d    date;
  v_lin  jsonb;
  v_n    int := 0;
  v_ab   jsonb;
  p      record;
  v_fer  text;
  -- CORREÇÃO 29/10 (P1): as reservas que já disseram a condição e o dia da continuação do bloco
  v_vistas uuid[] := '{}';
  v_dc     date;
  -- CORREÇÃO 29/10 (P1): fim
begin
  if v_ate < v_de then
    raise exception 'agenda_ver: período invertido (% a %)', v_de, v_ate using errcode = '22023';
  end if;
  if cf.modo_proposta = 'ligado' then
    v_d := v_de;
    while v_d <= v_ate loop
      v_lin := public.agenda_linhas_do_dia(v_d, null, p_hoje);
      -- CORREÇÃO 29/10 (P1): a reserva diz quem vai e que é reserva ("Lenine (OS-00074): João o dia todo, Roberto o dia todo
      -- — reservado, se …"); a condição só na 1ª vez em que a OS aparece, depois "(mesma condição)"
      v_lin := public._agenda_plano_reservas(v_lin, v_d, v_vistas);
      v_vistas := v_vistas || array(select (x ->> 'os')::uuid from jsonb_array_elements(v_lin) x
                                     where coalesce((x ->> 'reserva')::boolean, false));
      -- CORREÇÃO 29/10 (P1): fim
      v_fer := public.agenda_feriado(v_d);
      if jsonb_array_length(v_lin) > 0 then
        v_n := v_n + jsonb_array_length(v_lin);
        v_l := v_l || (public._agenda_dia_rotulo(v_d, p_hoje) || ': '
                       || (select string_agg((x ->> 'hora') || ' ' || (x ->> 'texto'), '; ' order by o)
                             from jsonb_array_elements(v_lin) with ordinality t(x, o)) || '.');
      elsif v_fer is not null and extract(isodow from v_d) between 1 and 5 then
        v_l := v_l || (public._agenda_dia_rotulo(v_d, p_hoje) || ': ' || v_fer || '.');
      end if;
      v_d := v_d + 1;
    end loop;
    -- CORREÇÃO 29/10 (P1): o bloco que tem dia no período e passa do fim dele aparece inteiro, só com as OS dele ("Ter 10/11
    -- (continua): 08:00 Lenine (OS-00074): … — reservado (mesma condição).")
    for v_dc in select distinct v.dia from public.v_agenda_dia v
                 where v.dia > v_ate
                   and v.service_order_id in (select w.service_order_id from public.v_agenda_dia w where w.dia between v_de and v_ate)
                 order by 1 loop
      v_lin := coalesce((select jsonb_agg(x order by o)
                           from jsonb_array_elements(public.agenda_linhas_do_dia(v_dc, null, p_hoje)) with ordinality t(x, o)
                          where (x ->> 'os')::uuid in (select w.service_order_id from public.v_agenda_dia w
                                                        where w.dia between v_de and v_ate)), '[]'::jsonb);
      v_lin := public._agenda_plano_reservas(v_lin, v_dc, v_vistas);
      v_vistas := v_vistas || array(select (x ->> 'os')::uuid from jsonb_array_elements(v_lin) x
                                     where coalesce((x ->> 'reserva')::boolean, false));
      if jsonb_array_length(v_lin) > 0 then
        v_l := v_l || (public._agenda_dia_rotulo(v_dc, p_hoje) || ' (continua): '
                       || (select string_agg((x ->> 'hora') || ' ' || (x ->> 'texto'), '; ' order by o)
                             from jsonb_array_elements(v_lin) with ordinality t(x, o)) || '.');
      end if;
    end loop;
    -- CORREÇÃO 29/10 (P1): fim
    v_l := array[public._agenda_periodo_rotulo(v_de, v_ate, p_hoje)
                 || case when v_n = 0 then ': nada publicado na agenda.' else ', o que está publicado:' end] || v_l;
    v_ab := public.agenda_propostas_abertas(p_agora);
    if jsonb_array_length(v_ab) > 0 then
      v_l := v_l || ('Montei e ainda não publiquei: '
                     || (select string_agg(format('%s) %s', x ->> 'n', coalesce(x ->> 'titulo', 'uma mudança')), '; ' order by (x ->> 'n')::int)
                           from jsonb_array_elements(v_ab) x)
                     || '. Para publicar, diga "publica a 1".');
    end if;
  elsif cf.modo_proposta = 'sombra' then
    select pr.* into p from public.agenda_propostas pr
     where pr.modo = 'sombra' and pr.escopo = 'semana'
     order by pr.criada_em desc, pr.id desc limit 1;
    if p.id is null then
      v_l := array['Em teste: ainda não montei nenhuma semana.'];
    else
      v_l := array['Em teste (nada foi publicado): eu montaria assim — ' || coalesce(p.textos ->> 'titulo', 'a semana') || '.']
             || array(select x from jsonb_array_elements_text(coalesce(p.textos -> 'linhas', '[]'::jsonb)) with ordinality t(x, o) order by o)
             || array(select 'Fora: ' || regexp_replace(x, '\?\.$', '?')
                        from jsonb_array_elements_text(coalesce(p.textos -> 'fora', '[]'::jsonb)) with ordinality t(x, o)
                       order by o);
    end if;
  else
    v_l := array['A agenda automática está desligada: não há plano publicado.'];
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('de', v_de, 'ate', v_ate, 'linhas', v_n,
                                                        'abertas', coalesce(v_ab, '[]'::jsonb)));
end;
$function$;

comment on function public._agenda_ver_plano(date, date, date, timestamptz) is
  'Agenda de Produção (Fase 2, P5): agenda_ver foco plano — em ligado, o publicado de [p_de, p_ate] dia a dia ("Ter 03/11: 08:00 Vanderlei (OS-00069), dia 1 de 3: você abre, Roberto o dia todo; 13:00 …"), o feriado de dia útil no meio, e as montadas e não publicadas numeradas por agenda_propostas_abertas ("publica a 1"); em sombra, a última semana montada pela sombra ("Em teste (nada foi publicado): eu montaria assim — …"); desligado diz que não há plano. Sem período: de hoje ao sábado da semana que vem. {ok, texto, dados}. CORREÇÃO 29/10 (P1): a reserva diz quem vai e que é reserva ("Qui 05/11: 08:00 Lenine (OS-00074): João o dia todo, Roberto o dia todo — reservado, se você disser até qua 04/11 se tem peça a comprar."; a condição só na 1ª vez, depois "(mesma condição)"; no pátio "reservado no pátio"; acima da carga "reservado (acima da carga)"), e o bloco que começou no período e passa do fim dele aparece inteiro, só com as OS dele ("Ter 10/11 (continua): 08:00 Lenine (OS-00074): … — reservado (mesma condição).").';

-- ── 4. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- As duas novas (invoker, STABLE): authenticated (o painel, com o login do admin) e service_role (o WhatsApp), nunca anon.
revoke all on function public._agenda_marcados_bloco(jsonb, date, date, boolean), public._agenda_plano_reservas(jsonb, date, uuid[])
  from public, anon;
grant execute on function public._agenda_marcados_bloco(jsonb, date, date, boolean), public._agenda_plano_reservas(jsonb, date, uuid[])
  to authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a migration valer sozinha).
revoke all on function
  public._agenda_semana_de(jsonb, date, date, jsonb, jsonb),
  public.agenda_semana(date, date, date),
  public._agenda_ver_plano(date, date, date, timestamptz)
  from public, anon;
grant execute on function
  public._agenda_semana_de(jsonb, date, date, jsonb, jsonb),
  public.agenda_semana(date, date, date),
  public._agenda_ver_plano(date, date, date, timestamptz)
  to authenticated, service_role;
