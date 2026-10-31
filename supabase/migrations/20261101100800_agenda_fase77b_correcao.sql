-- Agenda de Produção — Fase 7b, correção da revisão da etapa (20261101100800). NÃO aplicada.
--
-- O que conserta (os achados da revisão da 7b; cada mudança num bloco "-- FASE 7b: (correção da revisão da 7b, achado N) …
-- -- FASE 7b: fim" — ou, dentro de um bloco "-- FASE 7b:" de antes, "-- (correção da revisão da 7b, achado N) … -- (correção da
-- revisão da 7b: fim)", que sai junto com o bloco de fora nos tiradores de antes —, só acréscimo; tirados esses blocos, o corpo é o da
-- definição de antes — a mais nova, da própria 7b —, byte a byte: o montador scratchpad/agenda-pesquisa/f7b/corr2/montar-migration.mjs
-- e o X0 de supabase/tests/agenda_fase77b_correcao.sql conferem):
--   1. _agenda_ver_gestor (de 20261101100500): o bloco "Quem chamar" sai do meio do foco e vai para o fim que sempre entra (antes do
--      "Como eu conto"; até 700 letras): com o texto_max de sempre ele sumia (achados 1 e 15) e, em teste, tomava o lugar das linhas
--      da 7a ("Fora:", "Se aprovar:"; achado 9). A OS em que a dupla é só nota (o espaço confinado) continua com o "Pode precisar de
--      dupla", com o que *com dupla* quer dizer na 7b (o tempo todo) e os dias do ajudante antes (achados 5 e 11); o exemplo da dupla
--      de 1 pessoa diz todos os dias (achado 23). O que a 7b acrescenta às linhas da 7a soma ao texto_max: o conteúdo da 7a não perde
--      linha por isso (achado 9).
--  1b. agenda_livre_de_verdade (de 20261101100500): a linha de quem chamar entra depois do corte do texto_max (o corte do fim a tirava;
--      achados 15 e 25).
--   2. _agenda_quem_chamar (de 20261101100500): a OS que já tem lugar (a reserva vigente, a desta conta ou a do "eu marcaria" de
--      hoje) não é "sem lugar" (achado 20); os meios-dias de "mais uma pessoa" são os de quem trabalha, sem os do dono e um por pessoa
--      e meio-dia (achado 19); a dupla dita que só cabe depois do prazo firme diz isso (achado 22); a pergunta da quinta e o *livre*
--      dizem o que falar para cumprir o prazo (achado 25).
--   3. agenda_rascunho_disponibilidade (de 20261101100100): com a pergunta dos dias fora de desligado, "Alex saiu" (nao_vem, padrao,
--      "seg a sáb") vale como a semana inteira (achados 2, 13 e 21); as datas de quem vem sob demanda ditas por extenso ("qua 18/11 e
--      qui 19/11", "18/11 e 19/11", "quarta dia 18 e quinta dia 19", "dia 18 e 19") viram essas datas (achado 16).
--   4. _agenda_equipe_dias_gravar (de 20261101100100) e agenda_decidir (de 20261101100200): a semana dita pelo dono prende só aquela
--      semana; o padrão só muda pela opção da pergunta dias_semana que diz "toda semana" ("Fico em campo de seg a sex"), e a resposta
--      diz isso (achados 3 e 10).
--   5. agenda_resposta_da_equipe (de 20261101100200): com modo_dias ligado, a pergunta da semana só leva a resposta quando é a última
--      mensagem mandada, quando a frase fala da semana ou quando é só a lista dos dias; a resposta à ficha, à confirmação e ao "como
--      foi" segue o caminho de antes (achado 8).
--   6. _agenda_linhas_do_fechamento (de 20261101100200): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como
--      "Também: … (responda em *agenda pendências*)" não contam como mostradas (achado 17); a chamada da 7a (sem opções) é do gestor
--      que marca, mesmo com o cadastro da 7b em teste (achado 7).
--   7. _agenda_carga_da_pessoa (de 20261101100300): em teste (modo_dias sombra), o teto do dono é o de antes; a meia capacidade só
--      com modo_dias ligado (achado 14).
--   8. agenda_desfazer (de 20261101100200): desfazer a 2ª pessoa que o gestor pôs na dupla diz que só ela saiu; a recusa por
--      sobreposição no serviço com a dupla completada diz como voltar (achado 18).
--   9. _agenda_gestor_dupla (de 20261101100500): acima da carga só quando a revisão do dia seguinte pode cortar o fim; senão, dentro
--      do teto (achado 4).
--  10. _agenda_contexto (de 20261101100300): em teste (modo_sabado sombra), o gancho do sábado do 7a continua valendo (achado 12).
--  11. agenda_propor (de 20261101100300): o exemplo da dupla de 1 pessoa diz todos os dias (achado 23); a dupla dita que espera e
--      só tem dias de quem vem sob demanda antes de a OS ficar pronta diz isso (achado 22).
--
-- O que NÃO muda aqui (ver scratchpad/agenda-pesquisa/notas-fase77b.md, seção CORR2): o achado 24 (a pergunta da quinta sem o
-- "2) Fico em campo" enquanto a padrao_do_dono do lote está aberta: é a mesma pergunta, feita uma vez), o 26 (o corte da 7a com a
-- linha do dono: é da 7a, fora da 7b) e o resto do 7 (a chamada da 7a cede à da 7b com o cadastro fora de desligado, como manda o R2).
--
-- Quem recriar depois qualquer uma destas funções copia DESTA migration (spec-fase7b §R4.6, fim).
--
-- DESFAZER: recriar cada função com o corpo da definição de antes (as migrations 20261101100100, 100200, 100300 e 100500, a mesma
-- de onde esta copiou). As portas não mudam.

-- _agenda_ver_gestor (de 20261101100500_agenda_fase7b_quem_chamar.sql)
create or replace function public._agenda_ver_gestor(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_ef    text := public._agenda_gestor_modo('marcar');
  v_l     text[] := '{}';
  v_desde date;
  v_sdia  date;
  v_s     jsonb;
  v_cart  uuid[];
  v_fora  jsonb := '[]'::jsonb;
  v_n     int;
  v_comp  jsonb;
  v_orc   jsonb;
  v_mo    numeric := public._agenda_mo_por_diaria_real();
  x       jsonb;
  r       record;
  -- (7a correção, achado 3) o "Como eu conto" à parte, sempre no fim
  v_como  text;
  v_k     int;
  -- FASE 7: (7a correção 2) quem a grade tem (a dupla sem a 2ª pessoa) e o fim do dia (o *desfaz* do dono)
  v_f72_tec   text[];
  v_f72_dup   text;
  v_f72_agora timestamptz;
  -- FASE 7: fim
  -- FASE 7b: (7b P6) a dupla de 1 pessoa no lugar do "Pode precisar de dupla" e o bloco "Quem chamar"
  v_7b_dupla boolean := (public._agenda_cfg()).modo_dupla <> 'desligado';
  v_7b_tf    text;
  v_7b_m     jsonb;
  v_7b_pl    jsonb;
  v_7b_d     jsonb;
  v_7b_fa    jsonb;
  v_7b_ni    int;
  v_7b_nf    int;
  v_7b_x     text;
  v_7b_y     text;
  v_7b_r1    text;
  v_7b_r2    text;
  v_7b_z     text;
  v_7b_ch    jsonb;
  v_7b_cdia  date;
  v_7b_cab   text;
  v_7b_pela  text;
  v_7b_bul   text[];
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 1, 5, 9, 11, 15 e 23) o bloco "Quem chamar" no fim que sempre entra, a dupla que é só
  -- nota e o exemplo com todos os dias. c_7bc_max é estrutural: o tamanho do bloco no fim (o resto, "(e mais N linhas)").
  c_7bc_max  constant int := 700;
  v_7bc_n    int := 0;
  v_7bc_ch   text[] := '{}';
  v_7bc_l0   text;
  v_7bc_dias text;
  v_7bc_mais int := 0;
  -- FASE 7b: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_gestor: sem o dia de hoje' using errcode = '22004';
  end if;

  -- 1. o estado (uma linha)
  if cf.gestor_so_propor then
    v_l := v_l || case when cf.gestor_so_propor_em is not null
                       then format('Desde %s você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.',
                                   public._dia_curto((cf.gestor_so_propor_em at time zone 'America/Sao_Paulo')::date))
                       else 'Você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.' end;
  elsif cf.modo_marcar_sozinho = 'ligado' then
    v_l := v_l || case when cf.marcar_sozinho_desde is not null
                       then format('Eu marco sozinho desde %s e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.',
                                   public._dia_curto((cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date))
                       else 'Eu marco sozinho e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.' end;
  elsif cf.modo_marcar_sozinho = 'sombra' then
    select min(g.dia) into v_desde from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.modos ->> 'marcar' = 'sombra'
       and g.dia > coalesce((select max(h.dia) from public.agenda_gestor_dia h
                              where h.dia <= p_hoje and h.modos ->> 'marcar' is distinct from 'sombra'), date '-infinity');
    v_l := v_l || case when v_desde is not null
                       then format('O gestor está em teste desde %s: calcula o que marcaria, mas não muda nada.', public._dia_curto(v_desde))
                       else 'O gestor está em teste: calcula o que marcaria, mas não muda nada.' end;
  else
    v_l := v_l || 'O gestor da agenda está desligado: não marco nada sozinho.'::text;
  end if;

  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, o "Pode precisar de dupla" diz que falta a
  -- 2ª pessoa e o que fazer antes do *<nome> com dupla* (sem isso a palavra tirava a OS da agenda, calada)
  v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
  v_f72_dup := case when cardinality(v_f72_tec) < 2
                    then replace(format('hoje %s: para ir dupla, chame um ajudante e ', public._agenda_tecnicos_frase(v_f72_tec)), '%', '%%')
                    else '' end;
  v_f72_agora := (p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
  -- FASE 7: fim
  -- FASE 7b: (7b P6) quem a grade tem, na frase da dupla de 1 pessoa (a da marcação do P4)
  v_7b_tf := case when cardinality(v_f72_tec) >= 2 then 'ninguém mais está livre nesses meios-dias'
                  else public._agenda_tecnicos_frase(v_f72_tec) end;
  -- FASE 7b: fim
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k
                   where not public._agenda_os_tem_dia(k.service_order_id, p_hoje));

  if v_ef = 'sombra' then
    -- 2–4 em teste: a última conta do "eu marcaria assim" (o diário do gestor)
    select g.dia, g.sombra into v_sdia, v_s from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.sombra <> '{}'::jsonb order by g.dia desc limit 1;
    if v_s is null then
      v_l := v_l || 'Eu marcaria: ainda não fiz a conta (faço todo dia útil no fim da tarde).'::text;
    else
      if jsonb_array_length(coalesce(v_s -> 'itens', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(v_s -> 'reservas', '[]'::jsonb)) = 0 then
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ': nada agora.');
      else
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ':');
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'itens', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: %s, %s — %s (%s)%s.%s', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas',
                               public._agenda_dias((x ->> 'dias')::numeric),
                               case x ->> 'fonte' when 'orcamento' then 'estimativa minha' else 'você disse' end,
                               case when x ->> 'compre_ate' is not null
                                    then format('; compre até %s: %s',
                                                case when (x ->> 'compre_ate')::date <= p_hoje then 'hoje'
                                                     else public._dia_curto((x ->> 'compre_ate')::date) end,
                                                public._agenda_itens((x ->> 'itens_a_comprar')::int))
                                    else '' end,
                               case when jsonb_typeof(x -> 'alerta_dupla') = 'object'
                                    then format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                public._agenda_gestor_dupla_texto(x -> 'alerta_dupla'), x ->> 'cliente')
                                    else '' end);
          -- FASE 7b: (correção da revisão da 7b, achados 5 e 9) a linha como o 7a a deixou (o bloco do P6, logo abaixo, a troca)
          v_7bc_l0 := v_l[cardinality(v_l)];
          -- FASE 7b: fim
          -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com
          -- dupla*" do 7a sai: com a 7b, *com dupla* é "o tempo todo" e faz a OS esperar a 2ª pessoa. Em teste do gestor não há plano:
          -- a frase da dupla de 1 pessoa (R4.3(a)(3)) na forma curta, sem as datas ("Nos 2 primeiros meios-dias a troca do banco de
          -- baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga os dias dele."), pelos meios-dias do que
          -- a tarefa pede (_agenda_dupla_da_os: fora da simulação, o molde não tem o dk da regra uma_pessoa do gestor em teste)
          if v_7b_dupla and jsonb_typeof(x -> 'alerta_dupla') = 'object' then
            v_7b_m := public._agenda_dupla_da_os((x ->> 'os')::uuid);
            if v_7b_m ->> 'fonte' = 'regra' then
              v_7b_ni := coalesce((v_7b_m ->> 'inicio')::int, 0);
              v_7b_nf := coalesce((v_7b_m ->> 'fim')::int, 0);
              v_7b_x := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
              v_7b_y := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
              v_7b_z := case
                when coalesce((v_7b_m ->> 'todos')::boolean, false)
                  then format(' O serviço todo pede 2 pessoas (%s) e %s: se chamar um ajudante, me diga os dias dele.',
                              coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                         where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf)
                when v_7b_ni > 0 and v_7b_nf > 0
                  then format(' %s %s e %s %s pedem 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                when v_7b_ni > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              v_7b_tf)
                when v_7b_nf > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                else '' end;
              v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
            end if;
          end if;
          -- FASE 7b: fim
          -- FASE 7b: (correção da revisão da 7b, achado 5) com modo_dupla fora de desligado, a OS em que a dupla é só nota (o espaço
          -- confinado: _agenda_dupla_da_os sem fonte de regra nem do dono) continua com o "Pode precisar de dupla" do 7a, mas dizendo o que
          -- *com dupla* quer dizer na 7b (o tempo todo: com só um técnico, a OS espera a 2ª pessoa) e, com menos de 2 técnicos, os dias do
          -- ajudante antes da palavra.
          if v_7b_dupla and jsonb_typeof(x -> 'alerta_dupla') = 'object' and v_l[cardinality(v_l)] like '% Pode precisar de dupla (%'
             and coalesce(public._agenda_dupla_da_os((x ->> 'os')::uuid) ->> 'fonte', '') not in ('regra', 'dono') then
            v_l[cardinality(v_l)] := replace(replace(v_l[cardinality(v_l)], 'chame um ajudante e diga *', 'chame um ajudante, me diga os dias dele e diga *'),
                                             ' com dupla*.', ' com dupla* (em dupla o tempo todo).');
          end if;
          -- (achado 9) o que a 7b acrescentou à linha da 7a não tira espaço das outras linhas da 7a (o "Fora:", o "Se aprovar:")
          v_7bc_mais := v_7bc_mais + char_length(v_l[cardinality(v_l)]) - char_length(v_7bc_l0);
          -- FASE 7b: fim
        end loop;
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'reservas', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: reservaria %s, %s.', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas');
        end loop;
      end if;
      if jsonb_array_length(coalesce(v_s -> 'perguntas', '[]'::jsonb)) > 0 then
        v_l := v_l || 'Antes de marcar eu perguntaria:'::text;
        for x in select e from jsonb_array_elements(v_s -> 'perguntas') with ordinality t(e, o) order by o loop
          v_l := v_l || (format('• %s: %s', x ->> 'cliente', x ->> 'curto')
                         || case when right(x ->> 'curto', 1) in ('?', '.') then '' else '.' end);
        end loop;
      end if;
      v_fora := coalesce(v_s -> 'fora', '[]'::jsonb);
    end if;
  elsif v_ef = 'ligado' then
    -- 2. o que o gestor marcou nos últimos 7 dias: as OS com compromisso vigente pela estimativa (duracao_fonte orcamento)
    v_n := 0;
    v_l := v_l || 'Marquei nos últimos 7 dias:'::text;
    for r in select a.service_order_id as os, min(a.dia) as de, max(a.dia) as ate,
                    count(*) filter (where a.presenca = 'turno') as meios,
                    jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia,
                                                 'turno', a.turno, 'presenca', a.presenca)) as alocs
               from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento'
                and a.dia >= p_hoje and a.resultado is null
              group by a.service_order_id
             having min((a.criado_em at time zone 'America/Sao_Paulo')::date) >= p_hoje - 7
              order by min(a.dia), a.service_order_id loop
      v_n := v_n + 1;
      v_l := v_l || format('• %s: %s, %s — %s (estimativa minha).%s',
                           coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                       join public.clients cl on cl.id = so.client_id where so.id = r.os), 'serviço'),
                           public._agenda_gestor_faixa(r.de, r.ate), public._agenda_gestor_pessoas(r.alocs),
                           public._agenda_dias(r.meios::numeric / 2),
                           coalesce((select format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                   public._agenda_gestor_dupla_texto(d.a), public._agenda_nome_curto(cl.name))
                                       from (select public.os_duracao_sugerida(r.os) -> 'alerta_dupla' as a) d,
                                            public.service_orders so join public.clients cl on cl.id = so.client_id
                                      where so.id = r.os and jsonb_typeof(d.a) = 'object'), ''));
      -- FASE 7b: (correção da revisão da 7b, achados 11 e 23) a linha como o 7a a deixou (o bloco do P6, logo abaixo, a troca)
      v_7bc_l0 := v_l[cardinality(v_l)];
      -- FASE 7b: fim
      -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla" do 7a vira a frase da dupla
      -- de 1 pessoa (R4.3(a)(3), a da marcação do P4) com as datas do plano: os meios-dias em que a dupla pela tarefa ainda está sem a
      -- 2ª pessoa (_agenda_dupla_no_plano, fora da reserva). Com a 2ª pessoa em todos (a dupla completa), nada.
      if v_7b_dupla and v_l[cardinality(v_l)] like '% Pode precisar de dupla (%' then
        v_7b_pl := public._agenda_dupla_no_plano(r.os, p_hoje);
        v_7b_d := public._agenda_dupla_da_os(r.os);
        select coalesce(jsonb_agg(e order by (e ->> 'dia')::date, e ->> 'turno'), '[]'::jsonb) into v_7b_fa
          from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) e
         where not coalesce((e ->> 'reserva')::boolean, false) and v_7b_pl ->> 'fonte' = 'regra';
        select public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e
                          where e ->> 'onde' in ('inicio', 'todos')) z
                  group by z.d order by z.d)),
               public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim') z
                  group by z.d order by z.d))
          into v_7b_x, v_7b_y;
        v_7b_ni := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'inicio');
        v_7b_nf := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim');
        v_7b_r1 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
        v_7b_r2 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
        v_7b_z := case
          when jsonb_array_length(v_7b_fa) = 0 then ''
          when exists (select 1 from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'todos')
            then format(' O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                   where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf,
                        public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> '' and v_7b_y <> ''
            then format(' %s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> ''
            then format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          else format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                      v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date)) end;
        v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
      end if;
      -- FASE 7b: fim
      -- FASE 7b: (correção da revisão da 7b, achados 11 e 23) a dupla que é só nota (o espaço confinado) não some: o bloco do P6 tirava o
      -- "Pode precisar de dupla" e não punha nada (sem dupla pela tarefa, a frase dele fica vazia) — volta a do 7a, dizendo que *com
      -- dupla* é o tempo todo e, com menos de 2 técnicos, os dias do ajudante antes. Na dupla pela tarefa, o exemplo diz todos os dias em
      -- que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem qua 18 e qui 19/11").
      if v_7b_dupla and v_7bc_l0 like '% Pode precisar de dupla (%' then
        if coalesce(v_7b_d ->> 'fonte', '') not in ('regra', 'dono') and coalesce(v_7b_pl ->> 'fonte', '') <> 'regra' then
          v_l[cardinality(v_l)] := replace(replace(v_7bc_l0, 'chame um ajudante e diga *', 'chame um ajudante, me diga os dias dele e diga *'),
                                           ' com dupla*.', ' com dupla* (em dupla o tempo todo).');
        elsif jsonb_array_length(coalesce(v_7b_fa, '[]'::jsonb)) > 0
              and (select count(distinct e ->> 'dia') from jsonb_array_elements(v_7b_fa) e) > 1 then
          v_7bc_dias := regexp_replace(public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_fa) e order by 1)),
                                       ' \([^()]*\)$', '');
          v_l[cardinality(v_l)] := replace(v_l[cardinality(v_l)],
                                           format('(ex.: Mateus vem %s).', public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date)),
                                           format('(ex.: Mateus vem %s).', v_7bc_dias));
        end if;
      end if;
      -- (achado 9) o que a 7b acrescentou à linha da 7a não tira espaço das outras linhas da 7a (o "Fora:", o "Se aprovar:")
      v_7bc_mais := v_7bc_mais + char_length(v_l[cardinality(v_l)]) - char_length(v_7bc_l0);
      -- FASE 7b: fim
    end loop;
    if v_n = 0 then
      v_l[cardinality(v_l)] := 'Marquei nos últimos 7 dias: nada.';
    end if;
    -- 3. o que ele perguntou antes de marcar (as abertas de verdade, com o prazo)
    v_n := 0;
    for r in select q.* from public.agenda_perguntas q
                     left join public.service_orders so on so.id = q.service_order_id
              where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
              order by q.veto_ate nulls last, so.service_order_number desc nulls last, q.id loop
      if v_n = 0 then
        v_l := v_l || 'Perguntei antes de marcar:'::text;
      end if;
      v_n := v_n + 1;
      v_l := v_l || format('• %s: %s — %s',
        -- (7a correção 2) o número da OS junto quando o nome se repete nas perguntas abertas (Kalmar OS-00032 e OS-00033)
        case when (select count(*) from public.agenda_perguntas q2
                     join public.service_orders s2 on s2.id = q2.service_order_id
                     left join public.clients c2 on c2.id = s2.client_id
                    where q2.estado = 'aberta' and q2.modo = 'ligado' and q2.tipo in ('situacao', 'estimativa')
                      and public._agenda_nome_curto(c2.name) is not distinct from
                          (select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id)) > 1
             then public._agenda_rotulo_da_os(r.service_order_id)
             else coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                              join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id), 'serviço') end,
        coalesce(nullif(public._agenda_gestor_estimativa(r.service_order_id, p_hoje) ->> 'texto', ''),
                 case split_part(r.chave, ':', 3) when 'comecada' then 'já começou?' when 'rastro' then 'quanto falta?'
                                                  when 'parada' then 'ainda é para fazer?' when 'grande' then 'muitas diárias pela estimativa'
                                                  when 'embutida' then 'pode ter peça junto'
                                                  else 'não tem mão de obra separada' end),
        case when r.opcao_escolhida is not null then 'você vai me dizer os dias.'
             when r.veto_ate is not null
               then format('sem resposta até %s %s, marco assim.',
                           public._dia_curto((r.veto_ate at time zone 'America/Sao_Paulo')::date),
                           to_char(r.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI'))
             else 'espero você.' end);
    end loop;
    -- 4. quem fica de fora: o porquê da última conta do motor (a proposta de verdade mais nova que falou da OS, em 8 dias),
    -- das OS da carteira sem compromisso e sem pergunta aberta do gestor
    select coalesce(jsonb_agg(jsonb_build_object('os', t.os, 'cliente', t.cliente, 'motivo', t.motivo,
                                                 'grupo', public._agenda_gestor_motivo_texto(
                                                   -- (7a correção 2) a OS que o dono desfez: o porquê é o *desfaz*, não "sem lugar"
                                                   case when public._agenda_gestor_desfeito(t.os::uuid, v_f72_agora) then 'desfeito'
                                                        else t.motivo end)) order by t.numero), '[]'::jsonb)
      into v_fora
      from (select distinct on (f ->> 'os') f ->> 'os' as os, f ->> 'cliente_curto' as cliente, f ->> 'motivo' as motivo,
                   f ->> 'numero' as numero
              from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
             where pr.modo = 'ligado' and pr.criada_em >= ((p_hoje - 8)::timestamp at time zone 'America/Sao_Paulo')
               and f ->> 'motivo' is distinct from 'fora_da_carteira'
               and (f ->> 'os')::uuid = any (v_cart)
               and not exists (select 1 from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
                                  and q.service_order_id = (f ->> 'os')::uuid)
             order by f ->> 'os', pr.criada_em desc, pr.id desc) t;
  end if;

  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) onde o bloco "Quem chamar" começa
  v_7bc_n := coalesce(cardinality(v_l), 0);
  -- FASE 7b: fim
  -- FASE 7b: (7b P6, R4.4 "Onde aparece") o bloco "Quem chamar" (depois de "Perguntei antes de marcar"), só com modo_chamar fora de
  -- desligado: o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de
  -- …" quando não é de hoje). Em teste, "Em teste:" na frente. Só sugere: quem chama é o dono.
  if cf.modo_chamar <> 'desligado' then
    select g.dia, g.chamar into v_7b_cdia, v_7b_ch from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.chamar ? 'calculado_em' order by g.dia desc limit 1;
    v_7b_cab := case when cf.modo_chamar = 'sombra' then 'Em teste: quem chamar' else 'Quem chamar' end;
    v_7b_pela := case when v_7b_cdia is not null and v_7b_cdia <> p_hoje then format('pela conta de %s', public._dia_curto(v_7b_cdia)) end;
    if v_7b_ch is null then
      v_l := v_l || (v_7b_cab || ': ainda não fiz a conta (faço todo dia útil no fim da tarde).');
    else
      v_7b_bul := array(select u.l from unnest(string_to_array(coalesce(v_7b_ch ->> 'texto', ''), E'\n')) with ordinality u(l, o)
                         where u.l like '•%' order by u.o);
      if cardinality(v_7b_bul) = 0 then
        v_l := v_l || (v_7b_cab || coalesce(' (' || v_7b_pela || ')', '') || ': ninguém — a equipe de hoje dá conta da carteira que está pronta.');
      else
        v_l := v_l || (v_7b_cab || ' (' || concat_ws('; ', v_7b_pela, 'só sugiro; quem chama é você') || '):') || v_7b_bul;
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) o bloco "Quem chamar" sai do meio do foco: o corte (_agenda_gestor_juntar,
  -- no meio) o escondia com o texto_max de sempre — em teste ele é o único lugar da sugestão — e, em teste, ele tomava o lugar das linhas
  -- da 7a ("Fora:", "Se aprovar:"). Vai para o fim que sempre entra, logo antes do "Como eu conto" (abaixo).
  if cf.modo_chamar <> 'desligado' and coalesce(cardinality(v_l), 0) > v_7bc_n then
    v_7bc_ch := v_l[v_7bc_n + 1 : cardinality(v_l)];
    v_l := v_l[1 : v_7bc_n];
  end if;
  -- FASE 7b: fim
  -- 4. Fora: agrupado pelo porquê, os nomes (o número junto quando o nome se repete)
  if jsonb_array_length(v_fora) > 0 then
    v_l := v_l || ('Fora: ' || (
      select string_agg(g.grupo || ': ' || g.nomes, '; ' order by public._agenda_gestor_motivo_ordem(g.grupo), g.grupo)
        from (select h.grupo, public._agenda_lista(array_agg(h.nome || case when h.n > 1 then format(' (%s)', h.n) else '' end
                                                             order by h.primeiro), 4) as nomes
                from (select f ->> 'grupo' as grupo, f ->> 'cliente' as nome, count(*) as n, min(o) as primeiro
                        from jsonb_array_elements(v_fora) with ordinality t(f, o)
                       group by f ->> 'grupo', f ->> 'cliente') h
               group by h.grupo) g) || '.');
  end if;

  -- 5. as compras da semana (o diário do gestor; o P10 grava) e 6. os orçamentos que caberiam (o P12 grava): de até 3 dias
  select g.compras into v_comp from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.compras <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_comp, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Compras da semana:'::text;
    -- (7a correção, achado 3) até 3 por seção: toda seção cabe com o "Como eu conto"
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_comp) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_comp) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s em *agenda compras*)', v_k - 3);
    end if;
  end if;
  select g.orcamentos into v_orc from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.orcamentos <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_orc, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Se aprovar:'::text;
    -- (7a correção, achado 3) até 3 (os de maior valor)
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_orc) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_orc) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s %s)', v_k - 3, case when v_k - 3 = 1 then 'orçamento' else 'orçamentos' end);
    end if;
  end if;

  -- 7. como eu conto (todos os números dos parâmetros)
  -- (7a correção, achado 3) o "Como eu conto" à parte: entra sempre, no fim (_agenda_gestor_juntar)
  v_como := format('Como eu conto: estimativa pelo valor do orçamento (R$ %s de mão de obra por diária, sem deslocamento); '
                       || '%s por serviço (dupla quando você marcar); peça sem fornecedor: %s; peça abaixo de R$ %s: separar na '
                       || 'véspera; entre decidir e comprar: %s%s; pergunto antes acima de %s diárias e quando o serviço já começou.',
                       replace(to_char(round(v_mo), 'FM999,999,990'), ',', '.'),
                       case when cf.equipe_padrao = 1 then '1 pessoa' else cf.equipe_padrao || ' pessoas' end,
                       public._agenda_plural(cf.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis'),
                       replace(to_char(round(cf.critico_valor_min), 'FM999,999,990'), ',', '.'),
                       public._agenda_plural(cf.compra_interna_du, 'dia útil', 'dias úteis'),
                       case when cf.compra_urgente_du > 0
                            then format(' (com o serviço a menos de %s, a compra é para hoje)',
                                        public._agenda_plural(cf.compra_urgente_du, 'dia útil', 'dias úteis'))
                            else '' end,
                       public._agenda_num(cf.estimativa_max_diarias));

  -- (7a correção, achado 3) o conteúdo até texto_max, e o "Como eu conto" (os parâmetros, spec §6.2 item 7) depois dele: as 7 seções
  -- da spec não cabem em texto_max com ele dentro, e era ele que sumia
  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) o bloco "Quem chamar" entra no fim, junto do "Como eu conto": o conteúdo da
  -- 7a continua com o texto_max inteiro, e o bloco vem depois dele, até c_7bc_max letras (o resto "(e mais N linhas)")
  if cardinality(v_7bc_ch) > 0 then
    v_como := public._agenda_juntar(v_7bc_ch, c_7bc_max) || E'\n' || v_como;
  end if;
  -- (achado 9) e o que a 7b acrescentou às linhas da 7a (a frase da dupla de 1 pessoa, a da dupla que é só nota) não tira lugar das
  -- outras linhas da 7a: o conteúdo ganha esse tanto (nunca perde)
  cf.texto_max := cf.texto_max + greatest(v_7bc_mais, 0);
  -- FASE 7b: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_gestor_juntar(v_l, cf.texto_max + 1 + char_length(v_como), v_como),
                            'dados', jsonb_build_object('modo', v_ef, 'so_propor', cf.gestor_so_propor, 'conta_de', v_sdia,
                                                        'sombra', v_s, 'fora', v_fora));
end;
$function$;

comment on function public._agenda_ver_gestor(date) is
  'Agenda de Produção (Fase 7a, P7; spec §6.2): o foco gestor de agenda_ver — (1) o estado: "O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada." / "Eu marco sozinho desde ter 03/11 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz." / "Desde sex 06/11 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta." / desligado; (2) em teste, "Eu marcaria:" pela última conta do diário (agenda_gestor_dia.sombra), um por linha ("• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*."); ligado, "Marquei nos últimos 7 dias:" (as OS com compromisso vigente pela estimativa); (3) "Antes de marcar eu perguntaria:" (teste) ou "Perguntei antes de marcar:" com o prazo ("• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim."); (4) "Fora:" agrupado pelo porquê ("esperando o cliente: Kalmar (2) e Rodrigo; …"; ligado, pela última conta de verdade do motor em 8 dias); (5) "Compras da semana:" e (6) "Se aprovar:" pelo diário (agenda_gestor_dia.compras e .orcamentos, [{texto}], de até 3 dias; o P10 e o P12 gravam); (7) "Como eu conto:" com os parâmetros. {ok, texto (≤ texto_max), dados}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa; achado 3): o "Como eu conto" entra sempre, no fim (_agenda_gestor_juntar: o corte é no meio, nunca num título sem linha embaixo, como o "Se aprovar:" vazio); as compras da semana e o "Se aprovar" mostram até 3 cada (o resto: "(e mais 3 orçamentos)", "(e mais N em *agenda compras*)"). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): (a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, "Pode precisar de dupla (banco de baterias): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Lenine com dupla*."; (o desfaz) ligado, a OS de fora que o dono desfez vai no grupo "você desfez (me diga os dias para eu marcar de novo)", não em "sem lugar na agenda"; (o número) em "Perguntei antes de marcar", o número da OS junto quando o nome se repete ("Kalmar (OS-00032)"). FASE 7b (P6, R4.4): com modo_chamar fora de desligado, o bloco "Quem chamar" depois de "Perguntei antes de marcar" — o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de …" quando não é de hoje): "Quem chamar (só sugiro; quem chama é você):" e uma linha por sugestão, ou "Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta."; em teste, "Em teste: quem chamar …". Com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com dupla*" do 7a vira a frase da dupla de 1 pessoa (R4.3(a)(3)): ligado, com as datas do plano (_agenda_dupla_no_plano: "Nos 2 primeiros meios-dias (ter 10/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem ter 10/11)."; com a dupla completa, nada); em teste do gestor, a forma curta sem as datas. Com modo_chamar e modo_dupla desligados, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 1, 5, 9, 11, 15 e 23): o bloco "Quem chamar" vai para o fim que sempre entra, logo antes do "Como eu conto" (até 700 letras; o conteúdo da 7a continua com o texto_max inteiro) — antes ele ficava no meio e o corte o escondia, ou tomava o lugar do "Fora:" e do "Se aprovar:"; com modo_dupla fora de desligado, a OS em que a dupla é só nota (o espaço confinado) continua com o "Pode precisar de dupla (espaço apertado): … diga *Otávio com dupla* (em dupla o tempo todo)." (com menos de 2 técnicos, "chame um ajudante, me diga os dias dele e diga …"), também ligado (antes sumia); o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa.';

-- agenda_livre_de_verdade (de 20261101100500_agenda_fase7b_quem_chamar.sql)
create or replace function public.agenda_livre_de_verdade(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  -- quantas semanas o livre mostra (a 1ª é a do 1º dia que a agenda ainda pode mudar) e quantas vão na linha da semana
  c_semanas  constant int := 3;
  c_na_linha constant int := 2;
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_t0     timestamptz := clock_timestamp();
  v_g      jsonb;
  v_ctx    jsonb;
  v_ini    date;
  v_de     date;
  v_minh   int;
  v_nh     int;
  v_nw     int;
  v_np     int;
  v_dono   int;
  v_padrao boolean;
  v_util   boolean[];
  v_sem    int[];
  v_cap    int[];
  v_ocup   int[];
  v_t80    int[];
  v_t100   int[];
  v_uc     int[];
  v_ur     int[];
  v_pes    uuid[];
  v_nomes  text[];
  v_seg1   date;
  v_ate    date;
  v_seg    date;
  v_d0     date;
  v_d1     date;
  v_dsem   date;
  v_w      int;
  k        int;
  v_pessoas jsonb;
  v_semanas jsonb := '[]'::jsonb;
  v_quem   text;
  v_rot    text;
  v_plano  uuid[];
  v_ocupa  jsonb;
  v_pn     jsonb;
  v_trav   jsonb;
  v_pront  jsonb;
  v_andam  jsonb;
  v_parad  int;
  v_esp    int;
  v_lin    text[];
  v_curta  text[] := '{}';
  v_txt    text;
  v_linha  text;
  -- CORREÇÃO 29/10 (revisão): a 1ª semana da linha curta foi pela metade
  v_meia   boolean := false;
  -- CORREÇÃO 29/10 (revisão): fim
  -- FASE 7: (7a correção, achado 23) o teto da equipe-semana e o dono fora da conta de técnico
  v_f77_teq  boolean := public._agenda_gestor_regra('teto_equipe');
  v_f77_te   int[];
  v_f77_rest int;
  -- FASE 7: fim
  -- FASE 7b: (7b P6) a linha de quem chamar
  v_7b_liv text;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 15 e 25) a linha de quem chamar fora do corte
  v_7bc_liv text;
  -- FASE 7b: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_livre_de_verdade: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  -- O plano só manda em 'ligado': fora disso, quem chama usa a projeção da Fase 1 (fila ÷ capacidade).
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('fonte', 'projecao', 'motivo', 'a agenda automática não está ligada');
  end if;

  -- A grade do motor de agora (o plano vigente inteiro: o marcado e o reservado).
  v_g := public._agenda_grade_de_agora(p_hoje);
  v_ctx := v_g -> 'ctx';
  v_ini := (v_g ->> 'ini')::date;
  v_de := (v_g ->> 'de')::date;
  v_minh := (v_g ->> 'min_h')::int;
  v_nh := (v_ctx ->> 'nh')::int;
  v_nw := (v_ctx ->> 'nw')::int;
  v_np := (v_ctx ->> 'np')::int;
  v_dono := coalesce((v_ctx ->> 'dono')::int, 0);
  v_padrao := coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false);
  v_util := public._agenda_bools(v_ctx -> 'util');
  v_sem := public._agenda_ints(v_ctx -> 'sem');
  v_cap := public._agenda_ints(v_ctx -> 'cap');
  v_ocup := public._agenda_ints(v_ctx -> 'ocup');
  v_t80 := public._agenda_ints(v_ctx -> 'teto80');
  v_t100 := public._agenda_ints(v_ctx -> 'teto100');
  v_uc := public._agenda_ints(v_ctx -> 'uso_c');
  v_ur := public._agenda_ints(v_ctx -> 'uso_r');
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') with ordinality t(x, o) order by o);
  v_nomes := array(select x from jsonb_array_elements_text(v_ctx -> 'nomes') with ordinality t(x, o) order by o);
  v_seg1 := v_de - (extract(isodow from v_de)::int - 1);
  v_ate := v_seg1 + 7 * (c_semanas - 1) + 5;

  -- ── As semanas: quantos meios-dias cada pessoa ainda pega (a conta do encaixe) ──
  for k in 0 .. c_semanas - 1 loop
    v_seg := v_seg1 + 7 * k;
    v_w := (v_seg - v_ini) / 7 + 1;
    exit when v_w > v_nw;
    -- o 1º e o último dia útil que contam (na 1ª semana, a partir do 1º dia que a agenda ainda pode mudar) e o 1º da semana
    select min(g::date) filter (where g::date >= v_de), max(g::date) filter (where g::date >= v_de), min(g::date)
      into v_d0, v_d1, v_dsem
      from generate_series(v_seg, v_seg + 5, interval '1 day') g
     where public.agenda_dia_util(g::date);
    continue when v_d0 is null;
    select coalesce(jsonb_agg(jsonb_build_object(
             'payee_id', v_pes[s.q], 'nome', case when s.q = v_dono then 'você' else v_nomes[s.q] end, 'eh_dono', s.q = v_dono,
             'meios', s.meios, 'celulas', s.cels, 'teto', s.t80, 'compromisso', s.uc, 'reserva', s.ur)
             order by s.meios desc, s.q), '[]'::jsonb)
      into v_pessoas
      from (select z.q, z.cels, z.t80, z.uc, z.ur, greatest(0, least(z.t80 - z.uc, z.t100 - z.uc - z.ur, z.cels)) as meios
              from (select q,
                           v_t80[(q - 1) * v_nw + v_w] as t80, v_t100[(q - 1) * v_nw + v_w] as t100,
                           v_uc[(q - 1) * v_nw + v_w] as uc, v_ur[(q - 1) * v_nw + v_w] as ur,
                           (select count(*)::int from generate_series(1, v_nh) h
                             where v_sem[(h + 1) / 2] = v_w and v_util[(h + 1) / 2] and h >= v_minh
                               and v_cap[(q - 1) * v_nh + h] = 1 and v_ocup[(q - 1) * v_nh + h] = 0) as cels
                      from generate_series(1, v_np) q
                     where q <> v_dono or v_padrao) z) s;
    -- FASE 7: (7a correção, achado 23) com a regra teto_equipe (o motor do gestor): o dono não é vaga de técnico — o motor nunca o
    -- põe no turno de um serviço novo, só para abrir, fechar e no diagnóstico —, então sai da conta mesmo com os dias dele em
    -- campo; e a equipe não pega na semana mais do que teto_equipe − o compromisso dela (a mesma conta do encaixe), repartido de
    -- quem tem mais para quem tem menos (a ordem de v_pessoas). Antes, com a linha do dono, o *livre* prometia "você 2 dias, Alex
    -- nada" e "Alex 1 dia" com a equipe já no teto.
    if v_f77_teq then
      v_f77_te := coalesce(v_f77_te, public._agenda_ints(v_ctx -> 'teto_equipe'));
      v_f77_rest := case when v_w <= coalesce(cardinality(v_f77_te), 0)
                         then greatest(0, v_f77_te[v_w] - (select coalesce(sum(v_uc[(q - 1) * v_nw + v_w]), 0)::int
                                                              from generate_series(1, v_np) q where q <> v_dono)) end;
      select coalesce(jsonb_agg(case when v_f77_rest is null then p.e
                                     else p.e || jsonb_build_object('meios', greatest(0, least(p.acum, v_f77_rest)
                                                                                       - least(p.acum - (p.e ->> 'meios')::int, v_f77_rest))) end
                                order by p.o), '[]'::jsonb)
        into v_pessoas
        from (select t.e, t.o, sum((t.e ->> 'meios')::int) over (order by t.o) as acum
                from jsonb_array_elements(v_pessoas) with ordinality t(e, o)
               where not coalesce((t.e ->> 'eh_dono')::boolean, false)) p;
    end if;
    -- FASE 7: fim
    v_quem := case
      when jsonb_array_length(v_pessoas) = 0 then 'ninguém da equipe tem os dias na agenda'
      when not exists (select 1 from jsonb_array_elements(v_pessoas) e where (e ->> 'meios')::int > 0) then 'ninguém livre'
      else array_to_string(array(select format('%s %s', e ->> 'nome', public._agenda_meios_texto((e ->> 'meios')::int))
                                   from jsonb_array_elements(v_pessoas) with ordinality t(e, o) order by o), ', ') end;
    -- (a 1ª semana pela metade: "De qua 04 a sex 06/11"; um dia só: "Sex 06/11")
    v_rot := case when v_d0 = v_dsem then public._agenda_titulo_da_semana(v_seg)
                  when v_d0 = v_d1 then public._agenda_maiuscula(public._dia_curto(v_d0))
                  else format('De %s a %s', case when to_char(v_d0, 'MM') = to_char(v_d1, 'MM') then public._agenda_dia_sem_mes(v_d0)
                                                 else public._dia_curto(v_d0) end, public._dia_curto(v_d1)) end;
    v_semanas := v_semanas || jsonb_build_object('seg', v_seg, 'de', v_d0, 'ate', v_d1, 'rotulo', v_rot, 'pessoas', v_pessoas,
                                                 'texto', format('• %s: %s.', v_rot, v_quem));
    if jsonb_array_length(v_semanas) <= c_na_linha then
      v_curta := v_curta || format('%s %s, %s', case when jsonb_array_length(v_semanas) = 1 then 'na semana de' else 'na de' end,
                                   to_char(v_d0, 'DD/MM'), v_quem);
    end if;
    -- CORREÇÃO 29/10 (revisão): a 1ª semana pela metade (o 1º dia que a agenda ainda pode mudar cai no meio dela) não
    -- é "a semana de 04/11" (04/11 é quarta): sai o rótulo do *livre* ("de qua 04 a sex 06/11"; um dia só, "na sex 06/11"), e a
    -- seguinte vira "na semana de 09/11".
    if jsonb_array_length(v_semanas) <= c_na_linha then
      if v_d0 <> v_dsem then
        v_curta[cardinality(v_curta)] := format('%s, %s', case when v_d0 = v_d1 then 'na ' || public._dia_curto(v_d0)
                                                               else 'de ' || substr(v_rot, 4) end, v_quem);
        v_meia := true;
      elsif v_meia and jsonb_array_length(v_semanas) = 2 then
        v_curta[cardinality(v_curta)] := format('na semana de %s, %s', to_char(v_d0, 'DD/MM'), v_quem);
      end if;
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
  end loop;

  -- ── O que ocupa a equipe: o plano de hoje ao sábado da última semana, por OS, com quem fica o turno ──
  -- (o nome como nas outras listas da agenda: o número só quando o nome se repete na carteira, "Rodrigo OS-00096")
  v_pn := public._agenda_painel(p_hoje);
  v_plano := array(select distinct a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje);
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', z.os, 'numero', z.numero, 'reserva', z.reserva, 'dias', to_jsonb(z.dias), 'pessoas', z.pessoas,
           'texto', format('%s (%s%s%s)', z.nome, case when z.reserva then 'reserva, ' else '' end, public._agenda_dias_texto(z.dias),
                           coalesce(', com ' || nullif(z.pessoas, ''), '')))
           order by z.d1, z.numero collate "C"), '[]'::jsonb)
    into v_ocupa
    from (select y.*
            from (select v.service_order_id as os, min(v.numero) as numero,
                         coalesce((select public._agenda_rotulo(e, 'np') from jsonb_array_elements(coalesce(v_pn -> 'oss', '[]'::jsonb)) e
                                    where (e ->> 'os')::uuid = v.service_order_id limit 1),
                                  min(v.cliente_curto), min(v.numero)) as nome,
                         bool_and(v.reserva) as reserva, min(v.dia) as d1, array_agg(v.dia order by v.dia) as dias,
                         (select public._agenda_lista(array_agg(p.quem order by p.dono desc, p.primeiro, p.quem), null)
                            from (select case when coalesce((x ->> 'eh_dono')::boolean, false) then 'você' else x ->> 'nome' end
                                           as quem,
                                         bool_or(coalesce((x ->> 'eh_dono')::boolean, false)) as dono, min(v2.dia) as primeiro
                                    from public.v_agenda_dia v2
                                   cross join lateral jsonb_array_elements(v2.pessoas) x
                                   where v2.service_order_id = v.service_order_id and v2.dia between p_hoje and v_ate
                                     and x ->> 'presenca' = 'turno'
                                   group by 1) p
                           where p.quem is not null) as pessoas
                    from public.v_agenda_dia v
                   where v.dia between p_hoje and v_ate
                   group by v.service_order_id) y) z;

  -- ── O que não ocupa ninguém: a carteira fora do plano ──
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int)
                    filter (where e ->> 'grupo' in ('quase', 'travado', 'esperando')), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int) filter (where e ->> 'grupo' = 'pronto'), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int)
                    filter (where e ->> 'grupo' in ('andamento', 'marcado')), '[]'::jsonb),
         count(*) filter (where e ->> 'grupo' = 'parado')::int,
         count(*) filter (where e ->> 'grupo' = 'espera')::int
    into v_trav, v_pront, v_andam, v_parad, v_esp
    from jsonb_array_elements(coalesce(v_pn -> 'oss', '[]'::jsonb)) e
   where not ((e ->> 'os')::uuid = any (v_plano));

  -- ── O texto ──
  v_lin := array['Livre de verdade (pelo plano de agora e pelos dias que cada um vem):']
           || array(select e ->> 'texto' from jsonb_array_elements(v_semanas) with ordinality t(e, o) order by o);
  -- FASE 7: (7a correção, achado 23) com a regra teto_equipe, o dono com os dias em campo também fica fora da conta de técnico
  if v_dono > 0 and v_padrao and v_f77_teq then
    v_lin := v_lin || 'Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você).'::text;
  end if;
  -- FASE 7: fim
  if v_dono > 0 and not v_padrao then
    v_lin := v_lin || 'Você fica de fora da conta: não sei em que dias você fica em campo (é só me dizer, por exemplo, "fico em campo de segunda a sexta").'::text;
  end if;
  v_lin := v_lin || case
    when jsonb_array_length(v_ocupa) = 0 then format('Até %s, nada do plano ocupa a equipe.', public._dia_curto(v_ate))
    else 'Ocupa a equipe: '
         || public._agenda_lista(array(select e ->> 'texto' from jsonb_array_elements(v_ocupa) with ordinality t(e, o) order by o), 3)
         || case when jsonb_array_length(v_ocupa) > 3 then ' (*agenda plano* mostra tudo)' else '' end || '.' end;
  if jsonb_array_length(v_trav) > 0 or v_parad > 0 or v_esp > 0 then
    v_lin := v_lin || ('Não ocupam ninguém até destravar: '
                       || concat_ws('; ', nullif(public._agenda_nomes(v_trav, 3), ''),
                                    case when v_parad > 0 then public._agenda_plural(v_parad, 'parado no cliente', 'parados no cliente') end,
                                    case when v_esp > 0 then public._agenda_plural(v_esp, 'em espera (você pediu)', 'em espera (você pediu)') end)
                       || '.');
  end if;
  if jsonb_array_length(v_pront) > 0 then
    v_lin := v_lin || (case when jsonb_array_length(v_pront) = 1 then 'Pronto, mas ainda sem lugar no plano (não entra na conta): '
                            else 'Prontos, mas ainda sem lugar no plano (não entram na conta): ' end
                       || public._agenda_nomes(v_pront, 3) || '.');
  end if;
  if jsonb_array_length(v_andam) > 0 then
    v_lin := v_lin || ('Em andamento sem dia no plano (não entra na conta): ' || public._agenda_nomes(v_andam, 3) || '.');
  end if;
  v_lin := v_lin || 'Para um serviço novo, me diga quantos dias e com quem, que eu digo o 1º dia que cabe.'::text;
  -- FASE 7b: (7b P6, R4.4 "*livre*") com quem chamar ligado, no fim: o que fica sem lugar com a equipe de hoje e quantos meios-dias
  -- de mais uma pessoa fazem caber (o passo diário chamar do gestor, a conta mais nova de até 3 dias): "Sem lugar com a equipe de hoje:
  -- Nelson e César. Com mais uma pessoa 9 meios-dias, cabem até 20/11 (*agenda gestor* diz quando)."
  if cf.modo_chamar = 'ligado' then
    v_7b_liv := (select g.chamar ->> 'texto_livre' from public.agenda_gestor_dia g
                  where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.chamar ? 'calculado_em' order by g.dia desc limit 1);
    if nullif(btrim(coalesce(v_7b_liv, '')), '') is not null then
      v_lin := v_lin || v_7b_liv;
    end if;
  end if;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 15 e 25) a linha de quem chamar (a última) não entra no corte do texto_max: o corte é
  -- do fim, e era ela que sumia ("(e mais 1 linha)"), também com o prazo que só fecha com um ajudante. O resto do *livre* continua com
  -- o texto_max inteiro, e ela vem depois.
  if nullif(btrim(coalesce(v_7b_liv, '')), '') is not null and cardinality(v_lin) > 0 and v_lin[cardinality(v_lin)] = v_7b_liv then
    v_lin := v_lin[1 : cardinality(v_lin) - 1];
    v_7bc_liv := v_7b_liv;
  end if;
  -- FASE 7b: fim
  v_txt := public._agenda_juntar(v_lin, cf.texto_max);
  -- FASE 7b: (correção da revisão da 7b, achados 15 e 25) e entra depois do corte, sempre
  if v_7bc_liv is not null then
    v_txt := v_txt || E'\n' || v_7bc_liv;
  end if;
  -- FASE 7b: fim
  v_linha := 'Livre de verdade: '
             || coalesce(nullif(array_to_string(v_curta, '; '), ''), 'não tenho os dias da equipe nas próximas semanas') || '.';

  return jsonb_build_object(
    'fonte', 'simulacao', 'base', 'plano', 'de', v_de, 'ate', v_ate, 'semanas', v_semanas,
    'voce_fora', v_dono > 0 and not v_padrao, 'ocupa', v_ocupa,
    'nao_ocupam', jsonb_build_object(
      'travados', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_trav) with ordinality t(e, o)),
      'prontos', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_pront) with ordinality t(e, o)),
      'andamento', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_andam) with ordinality t(e, o)),
      'parados', v_parad, 'em_espera', v_esp),
    'texto', v_linha, 'texto_completo', v_txt,
    'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$function$;

comment on function public.agenda_livre_de_verdade(date, timestamptz) is
  'Agenda de Produção (Fase 3, P6; REESCRITA na correção de 29/10, P2): "quando a gente fica livre de verdade?" pelo plano e pelo teto de cada pessoa — só com modo_proposta ligado (fora disso {fonte: projecao}: quem chama usa a frase da Fase 1). Para cada uma das 3 semanas a partir do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado), os meios-dias que cada pessoa ainda pega num serviço novo, a mesma conta do encaixe: o menor entre teto80 − compromisso, teto100 − compromisso − reserva e os meios-dias dela livres na grade (_agenda_grade_de_agora: o marcado e o reservado ocupam); o dono só com os dias dele em campo (sem eles, voce_fora e a frase "Você fica de fora da conta"). Depois, o que ocupa a equipe (o plano de hoje ao sábado da última semana, por OS, com quem fica o turno), o que não ocupa ninguém até destravar (a carteira fora do plano: travados, esperando o dono, parados no cliente, em espera; o pronto sem lugar; o em andamento sem dia) e como perguntar de um serviço novo. {fonte: simulacao (o sinal de "use o texto daqui" para a agenda_ver e a agenda_tela_semana), base: plano, de, ate, semanas[{seg, de, ate, rotulo, pessoas[{payee_id, nome, eh_dono, meios, celulas, teto, compromisso, reserva}], texto}], voce_fora, ocupa[{os, numero, reserva, dias, pessoas, texto}], nao_ocupam{travados, prontos, andamento, parados, em_espera}, texto (a linha da semana e da tela: "Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia."), texto_completo (a resposta do *livre*, até texto_max), ms}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role. CORREÇÃO 29/10 (revisão): na linha curta (texto), a 1ª semana pela metade sai com o rótulo do *livre* ("Livre de verdade: de qua 04 a sex 06/11, Roberto 1 dia, João nada; na semana de 09/11, …"; um dia só, "na sex 06/11"), não "na semana de 04/11". CORREÇÃO DA 7a (revisão da etapa; achado 23): com a regra teto_equipe do gestor, (1) o dono não entra na conta do livre como técnico, mesmo com os dias em campo (o motor só o põe para abrir, fechar e no diagnóstico): "Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você)."; (2) os meios-dias da equipe na semana não passam do teto da equipe-semana (teto_equipe − o compromisso da equipe nela), repartidos de quem tem mais para quem tem menos. Sem a regra, a de antes, byte a byte. FASE 7b (P6, R4.4): com modo_chamar ligado, no fim do texto_completo, a linha de quem chamar do diário do gestor (a conta mais nova de até 3 dias, chamar.texto_livre): "Sem lugar com a equipe de hoje: Nelson e César. Com mais uma pessoa 9 meios-dias, cabem até 20/11 (*agenda gestor* diz quando)." Sem ela, ou fora de ligado, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 15 e 25): a linha de quem chamar (com modo_chamar ligado) entra depois do corte do texto_max, sempre: o resto do *livre* continua com o texto_max inteiro (antes ela era a última linha e o corte do fim a tirava).';

-- _agenda_quem_chamar (de 20261101100500_agenda_fase7b_quem_chamar.sql)
create or replace function public._agenda_quem_chamar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_t0     timestamptz := clock_timestamp();
  v_dono   uuid := public._agenda_dono(null);
  -- com o gestor que marca em teste, a conta é a que ele faria (as regras dele valem só aqui dentro, como na sombra)
  v_simula boolean := public._agenda_gestor_modo('marcar') = 'sombra'
                      and coalesce(current_setting('agenda.gestor', true), '') <> 'sombra';
  v_cart   uuid[];
  v_prazos jsonb := '{}'::jsonb;
  v_restr  jsonb;
  v_p1     jsonb := '{}'::jsonb;
  v_p2     jsonb := '{}'::jsonb;
  v_tec    text[];
  v_tecf   text;
  v_tp     jsonb;
  v_hor    date;
  v_dupla  jsonb := '[]'::jsonb;
  v_prazo  jsonb := '[]'::jsonb;
  v_sem    jsonb := '[]'::jsonb;
  v_cabem  jsonb := '[]'::jsonb;
  v_extra  jsonb;
  v_partes jsonb := '[]'::jsonb;
  v_lin    text[] := '{}';
  v_perg   text[] := '{}';
  v_texto  text;
  v_livre  text;
  v_txt    text;
  v_pt     text;
  v_os     uuid;
  v_pz     date;
  v_m      jsonb;
  v_d      jsonb;
  v_e      jsonb;
  v_f      jsonb;
  v_bl     jsonb;
  v_sl     jsonb;
  v_pm     int;
  v_n2     int;
  v_n      int;
  v_k      int;
  v_meios  int;
  v_dias   numeric;
  v_ate    date;
  v_nomes  text[];
  v_ondes  text[];
  v_frases text[];
  v_dn     date[];
  v_dt     date[];
  v_semt   text;
  v_cabt   text;
  v_tlist  text;
  x        jsonb;
  y        jsonb;
  -- FASE 7b: (correção da revisão da 7b, achados 19, 20, 22 e 25) a OS que já tem lugar, o prazo que só fecha com ajudante no *livre*
  v_7bc_res  uuid[];
  v_7bc_pz   text[] := '{}';
  -- FASE 7b: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_quem_chamar: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- a carteira sem compromisso de hoje em diante (a mesma da sombra do gestor) e o prazo firme de cada OS (o que o cliente pediu ou
  -- o prometido firme, o que vier antes)
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k
                   where not public._agenda_os_tem_dia(k.service_order_id, p_hoje)
                   order by k.numero, k.service_order_id);
  select coalesce(jsonb_object_agg(pl.service_order_id::text, z.prazo), '{}'::jsonb) into v_prazos
    from public.os_planejamento pl
    cross join lateral (select least(pl.precisa_ate, case when pl.prometido_tipo = 'firme' then pl.prometido_ate end) as prazo) z
   where pl.service_order_id = any (v_cart) and z.prazo is not null;
  -- as duas contas aceitam o atraso de quem tem prazo firme: o motor de verdade tira a OS que não cabe no prazo e pergunta (não
  -- cabe); aqui ela entra, para o bloco de 1 pessoa que passa do prazo sair na conta
  v_restr := jsonb_build_object('aceitar_atraso', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from jsonb_object_keys(v_prazos) k));
  v_tec := public._agenda_tecnicos_da_grade(p_hoje);
  v_tecf := case when cardinality(v_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_tec) end;
  -- o técnico da grade (o 1º de dias fixos, sem o dono): o bloco que ele faria sozinho na dita que espera
  v_tp := (select q.e from jsonb_array_elements(coalesce(public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb))
                           with ordinality q(e, o)
            where not coalesce((q.e ->> 'eh_dono')::boolean, false) order by q.o limit 1);

  begin
    if v_simula then
      perform set_config('agenda.gestor', 'sombra', true);
    end if;
    -- 1ª conta: a equipe de hoje, sem gravar nada
    if cardinality(v_cart) > 0 then
      v_p1 := public.agenda_propor('os', null, null, v_cart, v_restr, false, 'vigia', null, p_hoje, p_agora);
    end if;
    v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, coalesce((v_p1 #>> '{periodo,ate}')::date, p_hoje));

    -- (prazo) a OS com prazo firme cujo bloco de 1 pessoa passa dele: com um ajudante junto do técnico, a dupla rende 2 (d7) e o
    -- serviço leva ceil(pm / 2) meios-dias nos mesmos meios-dias, do início do bloco em diante; cumpre o prazo = a sugestão do
    -- prazo; senão, fica sem lugar (passa do prazo)
    for x in select e from jsonb_array_elements(coalesce(v_p1 -> 'itens', '[]'::jsonb)) e
              where e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' and v_prazos ? (e ->> 'os')
              order by e ->> 'numero', e ->> 'os' loop
      v_os := (x ->> 'os')::uuid;
      v_pz := (v_prazos ->> v_os::text)::date;
      continue when (x ->> 'ate')::date <= v_pz;
      v_m := public.agenda_meios_da_os(v_os, p_hoje);
      v_pm := coalesce((v_m #>> '{dupla,pm}')::int, (v_m ->> 'total')::int * coalesce((v_m ->> 'pessoas_sugeridas')::int, 1));
      select coalesce(jsonb_agg(jsonb_build_object('dia', s.dia, 'turno', s.turno) order by s.dia, s.turno), '[]'::jsonb) into v_bl
        from (select distinct (a ->> 'dia')::date as dia, a ->> 'turno' as turno
                from jsonb_array_elements(coalesce(x -> 'alocacoes', '[]'::jsonb)) a
               where coalesce(a ->> 'presenca', 'turno') = 'turno') s;
      v_nomes := array(select z.q from (select case when (a ->> 'payee_id')::uuid is not distinct from v_dono then 'você' else a ->> 'nome' end as q,
                                               min((a ->> 'dia')::date) as d0
                                          from jsonb_array_elements(coalesce(x -> 'alocacoes', '[]'::jsonb)) a
                                         where coalesce(a ->> 'presenca', 'turno') = 'turno' group by 1) z order by z.d0, z.q);
      v_n2 := ceil(coalesce(v_pm, 0)::numeric / 2)::int;
      if coalesce(v_pm, 0) >= 2 and jsonb_array_length(v_bl) >= v_n2 and (v_bl -> (v_n2 - 1) ->> 'dia')::date <= v_pz then
        v_prazo := v_prazo || jsonb_build_object(
          'os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto', 'prazo', v_pz, 'fim_hoje', (x ->> 'ate')::date,
          'fim_com_ajudante', (v_bl -> (v_n2 - 1) ->> 'dia')::date, 'pm', v_pm, 'tecnicos', to_jsonb(v_nomes),
          'meios', (select jsonb_agg(b.e order by b.o) from jsonb_array_elements(v_bl) with ordinality b(e, o) where b.o <= v_n2));
      else
        v_sem := v_sem || jsonb_build_object('os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto', 'pm', v_pm,
                                             'fim_hoje', (x ->> 'ate')::date, 'prazo', v_pz);
      end if;
    end loop;
    -- (capacidade) o que fica sem lugar no horizonte
    for x in select f from jsonb_array_elements(coalesce(v_p1 -> 'fora', '[]'::jsonb)) f
              where f ->> 'motivo' in ('sem_encaixe', 'nao_cabe') order by f ->> 'numero', f ->> 'os' loop
      v_os := (x ->> 'os')::uuid;
      v_m := public.agenda_meios_da_os(v_os, p_hoje);
      v_sem := v_sem || jsonb_build_object(
        'os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto',
        'pm', coalesce((v_m #>> '{dupla,pm}')::int, (v_m ->> 'total')::int * coalesce((v_m ->> 'pessoas_sugeridas')::int, 1)),
        'fim_hoje', null, 'prazo', v_prazos -> v_os::text);
    end loop;
    select coalesce(jsonb_agg(s order by s ->> 'numero', s ->> 'os'), '[]'::jsonb) into v_sem from jsonb_array_elements(v_sem) s;
    -- FASE 7b: (correção da revisão da 7b, achado 20) a OS que já tem lugar não é "sem lugar": a reserva vigente de hoje em diante (a
    -- que o gestor acabou de pôr acima da carga, na mesma rodada), a reserva desta conta ou, com o gestor em teste, a reserva do "eu
    -- marcaria" de hoje (agenda_gestor_dia.sombra). Antes, o foco e a pergunta da quinta diziam "sem lugar" da OS que a marcação do
    -- mesmo dia tinha reservado.
    v_7bc_res := array(
      select a.service_order_id from public.agenda_alocacoes a
       where a.tipo = 'reserva' and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
      union
      select (i ->> 'os')::uuid from jsonb_array_elements(coalesce(v_p1 -> 'itens', '[]'::jsonb)) i
       where i ->> 'op' = 'criar' and i ->> 'tipo' = 'reserva'
      union
      select (r ->> 'os')::uuid from public.agenda_gestor_dia g
       cross join lateral jsonb_array_elements(coalesce(g.sombra -> 'reservas', '[]'::jsonb)) r
       where g.dia = p_hoje and public._agenda_gestor_modo('marcar') = 'sombra' and r ->> 'os' is not null);
    select coalesce(jsonb_agg(s order by s ->> 'numero', s ->> 'os'), '[]'::jsonb) into v_sem
      from jsonb_array_elements(v_sem) s
     where not ((s ->> 'os')::uuid = any (v_7bc_res));
    -- FASE 7b: fim

    -- 2ª conta: a mesma, com mais uma pessoa que trabalhe sozinha (o gancho do P4: nunca gravada; a variável volta a vazio). A conta
    -- é do trabalho que passa a caber, não do uso da pessoa a mais: o motor guloso pode pô-la em qualquer OS.
    if jsonb_array_length(v_sem) > 0 then
      perform set_config('agenda.pessoa_extra', 'tecnico', true);
      v_p2 := public.agenda_propor('os', null, null, v_cart, v_restr, false, 'vigia', null, p_hoje, p_agora);
      perform set_config('agenda.pessoa_extra', '', true);
    end if;

    -- (dupla, a dita que espera) a classe 4 dupla ou o "fora" dupla do R4.3(c): o bloco que o técnico da grade faria sozinho para a
    -- OS como ela é (os dias de 2 pessoas: agenda_meios_da_os.total / 2), os meios-dias da dupla nele, menos os que quem vem sob
    -- demanda já tem livres
    for x in select f from jsonb_array_elements(coalesce(v_p1 -> 'fora', '[]'::jsonb)) f
              where f ->> 'motivo' = 'dupla' order by f ->> 'numero', f ->> 'os' loop
      v_os := (x ->> 'os')::uuid;
      v_d := public._agenda_dupla_da_os(v_os);
      continue when v_d ->> 'fonte' is distinct from 'dono' or v_tp is null;
      v_m := public.agenda_meios_da_os(v_os, p_hoje);
      v_dias := coalesce((v_m ->> 'total')::numeric, 0) / 2;
      continue when v_dias <= 0;
      v_e := public.agenda_encaixe_do_novo(v_dias,
               jsonb_build_array(jsonb_build_object('payee_id', v_tp ->> 'payee_id', 'nome', v_tp ->> 'nome', 'eh_dono', false,
                                                    'turnos', 'dia')),
               case when v_m ->> 'presenca' in ('abre_e_fecha', 'sempre', 'nunca') then v_m ->> 'presenca' end, p_hoje);
      continue when not coalesce((v_e ->> 'cabe')::boolean, false);
      -- os meios-dias do bloco: manhã e tarde de cada dia, menos a manhã do 1º quando ele começa à tarde e a tarde do último que sobra
      v_n := ceil(v_dias * 2)::int;
      select coalesce(jsonb_agg(jsonb_build_object('dia', s.d, 'turno', s.t) order by s.d, s.t), '[]'::jsonb) into v_sl
        from (select dd::date as d, tt.t from jsonb_array_elements_text(coalesce(v_e -> 'dias', '[]'::jsonb)) dd,
                     unnest(array['manha', 'tarde']) tt(t)) s;
      if jsonb_array_length(v_sl) > v_n and coalesce(v_e ->> 'texto', '') like '%(começa à tarde)%' then
        v_sl := v_sl - 0;
      end if;
      while jsonb_array_length(v_sl) > v_n loop
        v_sl := v_sl - (jsonb_array_length(v_sl) - 1);
      end loop;
      select coalesce(jsonb_agg(b.e order by b.o), '[]'::jsonb) into v_sl
        from jsonb_array_elements(v_sl) with ordinality b(e, o)
       where coalesce((v_d ->> 'todos')::boolean, false) or b.o <= coalesce((v_d ->> 'inicio')::int, 0)
          or b.o > jsonb_array_length(v_sl) - coalesce((v_d ->> 'fim')::int, 0);
      select coalesce(jsonb_agg(b.e order by b.o), '[]'::jsonb) into v_sl
        from jsonb_array_elements(v_sl) with ordinality b(e, o)
       where not exists (select 1 from public.agenda_capacidade((b.e ->> 'dia')::date, (b.e ->> 'dia')::date, p_hoje) k
                          where not k.eh_dono and k.situacao = 'livre' and k.turno = b.e ->> 'turno'
                            and public._agenda_e_sob_demanda(k.payee_id, p_hoje)
                            and not exists (select 1 from public.agenda_alocacoes a
                                             where a.payee_id = k.payee_id and a.dia = k.dia and a.turno = k.turno
                                               and a.estado in ('publicada', 'fixada')));
      continue when jsonb_array_length(v_sl) = 0;
      v_dupla := v_dupla || jsonb_build_object(
        'os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto', 'fonte', 'dono', 'marcada', false,
        'motivo', case when coalesce((v_d ->> 'todos')::boolean, false) then 'dupla o tempo todo'
                       when coalesce((v_d ->> 'inicio')::int, 0) = 1 then 'dupla no primeiro meio-dia'
                       when coalesce((v_d ->> 'inicio')::int, 0) > 1 then format('dupla nos %s primeiros meios-dias', v_d ->> 'inicio')
                       when coalesce((v_d ->> 'fim')::int, 0) = 1 then 'dupla no último meio-dia'
                       else format('dupla nos %s últimos meios-dias', v_d ->> 'fim') end,
        'cabe_de', v_e -> 'de', 'meios', v_sl);
      -- FASE 7b: (correção da revisão da 7b, achado 22) até quando o bloco vai (a sugestão diz quando ele passa do prazo firme)
      v_dupla := jsonb_set(v_dupla, array[(jsonb_array_length(v_dupla) - 1)::text, 'cabe_ate'],
                           coalesce(v_e -> 'ate', (select to_jsonb(max(dd::date)) from jsonb_array_elements_text(coalesce(v_e -> 'dias', '[]'::jsonb)) dd),
                                    'null'::jsonb));
      -- FASE 7b: fim
    end loop;
  exception when others then
    perform set_config('agenda.pessoa_extra', '', true);
    if v_simula then
      perform set_config('agenda.gestor', '', true);
    end if;
    raise;
  end;
  if v_simula then
    perform set_config('agenda.gestor', '', true);
  end if;

  -- (capacidade) as OS sem lugar que passam a caber na 2ª conta (com prazo: até ele) e os meios-dias de turno delas (de quem for)
  for x in select s from jsonb_array_elements(v_sem) s loop
    y := (select i from jsonb_array_elements(coalesce(v_p2 -> 'itens', '[]'::jsonb)) i
           where i ->> 'os' = x ->> 'os' and i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' limit 1);
    continue when y is null or (x ->> 'prazo' is not null and (y ->> 'ate')::date > (x ->> 'prazo')::date);
    v_cabem := v_cabem || jsonb_build_object(
      'os', x -> 'os', 'numero', x ->> 'numero', 'cliente', x ->> 'cliente', 'de', y -> 'de', 'ate', y -> 'ate',
      'alocs', (select coalesce(jsonb_agg(jsonb_build_object('dia', a -> 'dia', 'turno', a -> 'turno')), '[]'::jsonb)
                  from jsonb_array_elements(coalesce(y -> 'alocacoes', '[]'::jsonb)) a where coalesce(a ->> 'presenca', 'turno') = 'turno'));
  end loop;
  -- FASE 7b: (correção da revisão da 7b, achado 19) os meios-dias de "mais uma pessoa que trabalhe sozinha" são os de quem trabalha nas
  -- OS que passam a caber: sem os do dono (a presença dele no turno, que outra pessoa não troca) e um por pessoa e meio-dia. Antes, os
  -- turnos do dono "sempre" e os repetidos entravam, e o Lenine (12 meios-dias de trabalho) pedia 22.
  select coalesce(jsonb_agg(t.c || jsonb_build_object('alocs', (
           select coalesce(jsonb_agg(jsonb_build_object('dia', z.dia, 'turno', z.turno) order by z.dia, z.turno, z.p), '[]'::jsonb)
             from (select distinct a ->> 'dia' as dia, a ->> 'turno' as turno, a ->> 'payee_id' as p
                     from jsonb_array_elements(coalesce((select i -> 'alocacoes' from jsonb_array_elements(coalesce(v_p2 -> 'itens', '[]'::jsonb)) i
                                                          where i ->> 'os' = t.c ->> 'os' and i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva'
                                                          limit 1), '[]'::jsonb)) a
                    where coalesce(a ->> 'presenca', 'turno') = 'turno' and (a ->> 'payee_id')::uuid is distinct from v_dono) z))
         order by t.o), '[]'::jsonb)
    into v_cabem
    from jsonb_array_elements(v_cabem) with ordinality t(c, o);
  -- FASE 7b: fim
  v_meios := (select count(*) from jsonb_array_elements(v_cabem) c, jsonb_array_elements(c -> 'alocs') a)::int;
  if jsonb_array_length(v_cabem) > 0 and v_meios >= cf.chamar_min_meios then
    v_extra := jsonb_build_object(
      'meios_total', v_meios,
      'semanas', (select jsonb_agg(jsonb_build_object('seg', w.seg, 'meios', w.n) order by w.seg)
                    from (select (a ->> 'dia')::date - (extract(isodow from (a ->> 'dia')::date)::int - 1) as seg, count(*)::int as n
                            from jsonb_array_elements(v_cabem) c, jsonb_array_elements(c -> 'alocs') a group by 1) w),
      'os', (select jsonb_agg(jsonb_build_object('os', c -> 'os', 'de', c -> 'de', 'ate', c -> 'ate') order by c ->> 'numero')
               from jsonb_array_elements(v_cabem) c));
  end if;

  -- (dupla, a pela tarefa marcada com 1 pessoa) os meios-dias do plano sem a 2ª pessoa
  for v_os in select distinct a.service_order_id from public.agenda_alocacoes a
               where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno' and a.dia >= p_hoje
               order by 1 loop
    v_f := public._agenda_dupla_faltando(v_os, p_hoje);
    continue when jsonb_array_length(v_f) = 0;
    v_d := public._agenda_dupla_da_os(v_os);
    v_ondes := array(select distinct e ->> 'onde' from jsonb_array_elements(v_f) e);
    v_frases := array(select distinct on (m ->> 'motivo') m ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) m
                       where m ->> 'onde' = any (v_ondes) and m ->> 'onde' <> 'todos' order by m ->> 'motivo');
    v_dupla := v_dupla || jsonb_build_object(
      'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
      'cliente', coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
                            where so.id = v_os), (select so.service_order_number from public.service_orders so where so.id = v_os)),
      'fonte', 'regra', 'marcada', true,
      'motivo', case when 'todos' = any (v_ondes) then (select e ->> 'motivo' from jsonb_array_elements(v_f) e where e ->> 'onde' = 'todos' limit 1)
                     else public._agenda_lista(v_frases) end,
      'pede', case when 'todos' = any (v_ondes)
                   then format('o serviço todo pede 2 pessoas (%s)', (select e ->> 'motivo' from jsonb_array_elements(v_f) e where e ->> 'onde' = 'todos' limit 1))
                   else format('%s %s 2 pessoas', public._agenda_lista(v_frases), case when cardinality(v_frases) > 1 then 'pedem' else 'pede' end) end,
      'tecnicos', (select coalesce(jsonb_agg(z.q order by z.q), '[]'::jsonb)
                     from (select distinct case when p::uuid is not distinct from v_dono then 'você' else public._agenda_nome_curto(py.name) end as q
                             from jsonb_array_elements(v_f) e cross join lateral jsonb_array_elements_text(coalesce(e -> 'pessoas', '[]'::jsonb)) p
                             join public.payees py on py.id = p::uuid) z),
      'meios', (select jsonb_agg(jsonb_build_object('dia', e -> 'dia', 'turno', e -> 'turno', 'travado', e -> 'travado') order by o)
                  from jsonb_array_elements(v_f) with ordinality t(e, o)));
  end loop;
  -- a marcada antes (pelo 1º meio-dia), depois a dita que espera (pelo número)
  select coalesce(jsonb_agg(e order by not (e ->> 'marcada')::boolean, e #>> '{meios,0,dia}', e ->> 'numero'), '[]'::jsonb) into v_dupla
    from jsonb_array_elements(v_dupla) e;

  -- ── Os textos: o foco (uma linha por sugestão, até chamar_max_os por parte), a pergunta da quinta (as partes, com os dias) e o
  -- *livre*. Só sugere: quem chama é o dono ("Se chamar, diga: …" com as datas, que o rascunho lê como datas)
  v_k := 0;
  for x in select e from jsonb_array_elements(v_dupla) e loop
    v_k := v_k + 1;
    exit when v_k > cf.chamar_max_os;
    v_dn := array(select distinct (m ->> 'dia')::date from jsonb_array_elements(x -> 'meios') m
                   where not coalesce((m ->> 'travado')::boolean, false) order by 1);
    v_dt := array(select distinct (m ->> 'dia')::date from jsonb_array_elements(x -> 'meios') m
                   where coalesce((m ->> 'travado')::boolean, false) order by 1);
    if (x ->> 'marcada')::boolean then
      -- quem já está livre nos meios-dias que eu ainda posso completar (fora o dono e quem já vai): o passo dupla o põe; sem ninguém,
      -- quem a grade tem e o que o dono diz para chamar
      v_nomes := array(select distinct public._agenda_nome_curto(k.pessoa)
                         from jsonb_array_elements(x -> 'meios') m
                         cross join lateral public.agenda_capacidade((m ->> 'dia')::date, (m ->> 'dia')::date, p_hoje) k
                        where not coalesce((m ->> 'travado')::boolean, false) and k.turno = m ->> 'turno' and k.situacao = 'livre'
                          and not k.eh_dono and k.payee_id is distinct from v_dono
                          and not exists (select 1 from public.agenda_alocacoes a
                                           where a.payee_id = k.payee_id and a.estado in ('publicada', 'fixada')
                                             and a.periodo && public.agenda_periodo((m ->> 'dia')::date, m ->> 'turno', 'turno'))
                        order by 1);
      v_txt := format('• Ajudante para a dupla: %s %s — %s', x ->> 'cliente', public._agenda_meios_frase(x -> 'meios'), x ->> 'pede')
               || case when cardinality(v_dn) > 0 and cardinality(v_nomes) > 0
                       then format('; %s %s livre nesses meios-dias.', public._agenda_lista(v_nomes),
                                   case when cardinality(v_nomes) > 1 then 'estão' else 'está' end)
                       when cardinality(v_dn) > 0
                       then format(' e %s. Se chamar, diga: Mateus vem %s.', v_tecf,
                                   regexp_replace(public._agenda_dias_texto(v_dn), ' \([^()]*\)$', ''))
                       else '.' end
               || case when cardinality(v_dt) > 0
                       then format(' Em %s eu não mexo: %s.', regexp_replace(public._agenda_dias_texto(v_dt), ' \([^()]*\)$', ''),
                                   case when cardinality(v_dt) = 1 then 'o dia já foi avisado' else 'os dias já foram avisados' end)
                       else '' end;
      v_pt := format('%s precisa de um ajudante junto de %s %s: %s.', x ->> 'cliente',
                     coalesce(nullif(public._agenda_lista(array(select jsonb_array_elements_text(x -> 'tecnicos'))), ''), 'quem vai'),
                     public._agenda_meios_frase(x -> 'meios'), x ->> 'pede');
    else
      v_txt := format('• %s (você disse: %s) espera a 2ª pessoa: com um ajudante %s, ele cabe.', x ->> 'cliente', x ->> 'motivo',
                      public._agenda_meios_frase(x -> 'meios'));
      v_pt := format('%s (você disse: %s) só cabe com um ajudante %s.', x ->> 'cliente', x ->> 'motivo', public._agenda_meios_frase(x -> 'meios'));
      -- FASE 7b: (correção da revisão da 7b, achado 22) com prazo firme, o bloco que termina depois dele diz isso: "ele cabe" mandava
      -- chamar um ajudante para dias que não cumprem o prazo (o motor deixa a OS no "não cabe")
      if v_prazos ? (x ->> 'os') and jsonb_typeof(x -> 'cabe_ate') = 'string'
         and (x ->> 'cabe_ate')::date > (v_prazos ->> (x ->> 'os'))::date then
        v_txt := format('• %s (você disse: %s) espera a 2ª pessoa: com um ajudante %s, ele termina %s, depois do prazo de %s.',
                        x ->> 'cliente', x ->> 'motivo', public._agenda_meios_frase(x -> 'meios'),
                        public._dia_curto((x ->> 'cabe_ate')::date), public._dia_curto((v_prazos ->> (x ->> 'os'))::date));
        v_pt := format('%s (você disse: %s) só cabe com um ajudante %s e termina %s, depois do prazo de %s.',
                       x ->> 'cliente', x ->> 'motivo', public._agenda_meios_frase(x -> 'meios'),
                       public._dia_curto((x ->> 'cabe_ate')::date), public._dia_curto((v_prazos ->> (x ->> 'os'))::date));
      end if;
      -- FASE 7b: fim
    end if;
    v_lin := v_lin || v_txt;
    v_perg := v_perg || v_pt;
    v_partes := v_partes || jsonb_build_object('tipo', 'dupla', 'os', jsonb_build_array(x -> 'os'), 'nomes', jsonb_build_array(x ->> 'cliente'),
                                               'texto', v_pt, 'dias', (select coalesce(jsonb_agg(distinct m -> 'dia'), '[]'::jsonb)
                                                                        from jsonb_array_elements(x -> 'meios') m));
  end loop;
  if jsonb_array_length(v_dupla) > cf.chamar_max_os then
    v_lin := v_lin || format('• E mais %s com a dupla sem a 2ª pessoa.', jsonb_array_length(v_dupla) - cf.chamar_max_os);
  end if;
  v_k := 0;
  for x in select e from jsonb_array_elements(v_prazo) e loop
    v_k := v_k + 1;
    exit when v_k > cf.chamar_max_os;
    v_dn := array(select distinct (m ->> 'dia')::date from jsonb_array_elements(x -> 'meios') m order by 1);
    v_tlist := coalesce(nullif(public._agenda_lista(array(select jsonb_array_elements_text(x -> 'tecnicos'))), ''), 'quem vai');
    v_txt := format('• %s (prazo %s): com %s %s termina %s; com um ajudante junto %s %s, termina no prazo. Se chamar, diga: %s com dupla; Mateus vem %s.',
                    x ->> 'cliente', public._dia_curto((x ->> 'prazo')::date), v_tlist,
                    case when jsonb_array_length(x -> 'tecnicos') > 1 then 'sozinhos' else 'sozinho' end,
                    public._dia_curto((x ->> 'fim_hoje')::date), case when jsonb_array_length(x -> 'tecnicos') > 1 then 'deles' else 'dele' end,
                    public._agenda_meios_frase(x -> 'meios'), x ->> 'cliente',
                    regexp_replace(public._agenda_dias_texto(v_dn), ' \([^()]*\)$', ''));
    v_pt := format('%s só cumpre o prazo de %s com um ajudante junto de %s %s.', x ->> 'cliente', public._dia_curto((x ->> 'prazo')::date),
                   v_tlist, public._agenda_meios_frase(x -> 'meios', false));
    -- FASE 7b: (correção da revisão da 7b, achado 25) a pergunta da quinta e o *livre* dizem também o que falar para cumprir o prazo (o
    -- foco já dizia)
    v_pt := v_pt || format(' Se chamar, diga: %s com dupla; Mateus vem %s.', x ->> 'cliente',
                           regexp_replace(public._agenda_dias_texto(v_dn), ' \([^()]*\)$', ''));
    v_7bc_pz := v_7bc_pz || v_pt;
    -- FASE 7b: fim
    v_lin := v_lin || v_txt;
    v_perg := v_perg || v_pt;
    v_partes := v_partes || jsonb_build_object('tipo', 'prazo', 'os', jsonb_build_array(x -> 'os'), 'nomes', jsonb_build_array(x ->> 'cliente'),
                                               'texto', v_pt, 'dias', to_jsonb(v_dn));
  end loop;
  if jsonb_array_length(v_prazo) > cf.chamar_max_os then
    v_lin := v_lin || format('• E mais %s com prazo que só fecha com um ajudante.', jsonb_array_length(v_prazo) - cf.chamar_max_os);
  end if;
  if v_extra is not null then
    -- quem fica sem lugar até o horizonte; quem passa do prazo; as semanas; até quando as que passam a caber cabem
    v_nomes := array(select s ->> 'cliente' from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is null order by s ->> 'numero', s ->> 'os');
    v_semt := concat_ws('; ',
      case when cardinality(v_nomes) > 0 then format('%s (só depois de %s)', public._agenda_lista(v_nomes, cf.chamar_max_os), to_char(v_hor, 'DD/MM')) end,
      nullif(public._agenda_lista(array(select format('%s (termina %s, depois do prazo de %s)', s ->> 'cliente',
                                                      public._dia_curto((s ->> 'fim_hoje')::date), public._dia_curto((s ->> 'prazo')::date))
                                          from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is not null order by s ->> 'numero', s ->> 'os'),
                                    cf.chamar_max_os), ''));
    v_ate := (select max((c ->> 'ate')::date) from jsonb_array_elements(v_cabem) c);
    v_cabt := case when jsonb_array_length(v_cabem) = jsonb_array_length(v_sem)
                   then case jsonb_array_length(v_sem) when 1 then format('%s cabe até %s', v_sem -> 0 ->> 'cliente', to_char(v_ate, 'DD/MM'))
                                                       when 2 then format('os dois cabem até %s', to_char(v_ate, 'DD/MM'))
                                                       else format('os %s cabem até %s', jsonb_array_length(v_sem), to_char(v_ate, 'DD/MM')) end
                   else format('%s %s até %s', public._agenda_lista(array(select c ->> 'cliente' from jsonb_array_elements(v_cabem) c
                                                                           order by c ->> 'numero'), cf.chamar_max_os),
                               case when jsonb_array_length(v_cabem) = 1 then 'cabe' else 'cabem' end, to_char(v_ate, 'DD/MM')) end;
    v_txt := (select string_agg(case when w.o = 1 then 'semana de ' else 'de ' end || to_char((w.e ->> 'seg')::date, 'DD/MM') || ': ' || (w.e ->> 'meios'),
                                '; ' order by w.o)
                from jsonb_array_elements(v_extra -> 'semanas') with ordinality w(e, o));
    v_lin := v_lin || format('• Sem lugar com a equipe de hoje: %s. Com mais uma pessoa que trabalhe sozinha em %s (%s), %s.', v_semt,
                             public._agenda_plural(v_meios, 'meio-dia', 'meios-dias'), v_txt, v_cabt);
    v_nomes := array(select s ->> 'cliente' from jsonb_array_elements(v_sem) s order by s ->> 'numero', s ->> 'os');
    v_pt := format('Com a equipe de hoje, %s %s; com mais uma pessoa que trabalhe sozinha em %s (%s), %s.',
                   public._agenda_lista(v_nomes, cf.chamar_max_os),
                   case when not exists (select 1 from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is not null)
                          then format('%s sem lugar até %s', case when cardinality(v_nomes) = 1 then 'fica' else 'ficam' end, to_char(v_hor, 'DD/MM'))
                        when not exists (select 1 from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is null)
                          then case when cardinality(v_nomes) = 1 then 'passa do prazo' else 'passam do prazo' end
                        else 'ficam sem lugar ou passam do prazo' end,
                   public._agenda_plural(v_meios, 'meio-dia', 'meios-dias'), v_txt, v_cabt);
    v_perg := v_perg || v_pt;
    v_partes := v_partes || jsonb_build_object(
      'tipo', 'capacidade', 'os', (select jsonb_agg(c -> 'os' order by c ->> 'numero') from jsonb_array_elements(v_cabem) c),
      'nomes', to_jsonb(v_nomes), 'texto', v_pt,
      'dias', (select coalesce(jsonb_agg(distinct a -> 'dia'), '[]'::jsonb) from jsonb_array_elements(v_cabem) c, jsonb_array_elements(c -> 'alocs') a));
    v_livre := format('Sem lugar com a equipe de hoje: %s. Com mais uma pessoa %s, %s até %s (*agenda gestor* diz quando).',
                      public._agenda_lista(v_nomes, cf.chamar_max_os), public._agenda_plural(v_meios, 'meio-dia', 'meios-dias'),
                      case when jsonb_array_length(v_cabem) = jsonb_array_length(v_sem)
                           then case when jsonb_array_length(v_cabem) = 1 then 'cabe' else 'cabem' end
                           else public._agenda_lista(array(select c ->> 'cliente' from jsonb_array_elements(v_cabem) c order by c ->> 'numero'),
                                                     cf.chamar_max_os)
                                || case when jsonb_array_length(v_cabem) = 1 then ' cabe' else ' cabem' end end,
                      to_char(v_ate, 'DD/MM'));
  end if;
  -- FASE 7b: (correção da revisão da 7b, achado 25) o *livre* leva também o prazo que só fecha com um ajudante (antes, só a capacidade;
  -- sem ela, nada)
  if cardinality(v_7bc_pz) > 0 then
    v_livre := concat_ws(' ', array_to_string(v_7bc_pz, ' '), v_livre);
  end if;
  -- FASE 7b: fim
  v_texto := case when cardinality(v_lin) = 0 then 'Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta.'
                  else array_to_string(array['Quem chamar (só sugiro; quem chama é você):'] || v_lin, E'\n') end;

  return jsonb_build_object(
    'calculado_em', p_agora, 'modo', cf.modo_chamar, 'dupla', v_dupla,
    'capacidade', jsonb_build_object('sem_lugar', v_sem, 'extra', v_extra, 'horizonte', v_hor), 'prazo', v_prazo,
    'partes', v_partes, 'texto', v_texto,
    'texto_pergunta', case when cardinality(v_perg) > 0 then array_to_string(v_perg, ' ') || ' Quem chama é você.' end,
    'texto_livre', v_livre,
    'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$function$;

comment on function public._agenda_quem_chamar(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P6; R4.4 item 2, R4.9-4): quem chamar — a sugestão do gestor, sem gravar nada. dupla: (i) as OS marcadas com a dupla pela tarefa sem a 2ª pessoa (_agenda_dupla_faltando) → {os, numero, cliente, fonte regra, marcada true, motivo, pede, tecnicos, meios [{dia, turno, travado}]}; (ii) a dupla dita que espera (a classe 4 dupla ou o fora dupla do R4.3(c) da 1ª conta) → o bloco que o técnico da grade faria sozinho (agenda_encaixe_do_novo com os dias de 2 pessoas, agenda_meios_da_os.total / 2), os meios-dias da dupla nele (todos; os primeiros ou os últimos dupla_meios), menos os que quem vem sob demanda já tem livres → {…, fonte dono, marcada false, cabe_de, meios}. prazo: a OS com prazo firme (precisa_ate ou o prometido firme) cujo bloco de 1 pessoa na 1ª conta passa do prazo e que, com um ajudante junto do técnico (ceil(pm / 2) meios-dias, a dupla rende 2; pm = dupla.pm ou total × pessoas), termina no prazo → {os, numero, cliente, prazo, fim_hoje, fim_com_ajudante, pm, tecnicos, meios}. capacidade: a 1ª conta (agenda_propor os sobre a carteira sem compromisso, sem gravar, com aceitar_atraso para quem tem prazo firme; as regras do gestor com ele em teste) → sem_lugar (o fora sem_encaixe e o que passa do prazo sem o ajudante resolver) [{os, numero, cliente, pm, fim_hoje (nulo = fora do horizonte), prazo}]; havendo, a 2ª conta com agenda.pessoa_extra = tecnico → extra {meios_total (os meios-dias de turno, de quem for, das OS de sem_lugar que passam a caber, com prazo até ele), semanas [{seg, meios}], os [{os, de, ate}]} só com meios_total >= chamar_min_meios; senão nulo. Textos (até chamar_max_os por parte, depois "e mais N"): texto (o foco: "Quem chamar (só sugiro; quem chama é você):" e uma linha por sugestão — "• Ajudante para a dupla: Lenine em ter 10/11 (manhã e tarde) — a troca do banco de baterias pede 2 pessoas e só Alex está na equipe. Se chamar, diga: Mateus vem ter 10/11." (com alguém já livre nesses meios-dias, "…; Mateus está livre nesses meios-dias."; no dia já avisado, "… Em ter 10/11 eu não mexo: o dia já foi avisado."), "• Lenine (você disse: dupla o tempo todo) espera a 2ª pessoa: com um ajudante de qua 11 a sex 13/11 (6 meios-dias), ele cabe.", "• Vanderlei (prazo …): com Alex sozinho termina …; com um ajudante junto dele de … (… meios-dias), termina no prazo. Se chamar, diga: Vanderlei com dupla; Mateus vem ….", "• Sem lugar com a equipe de hoje: Nelson e César (só depois de 15/12). Com mais uma pessoa que trabalhe sozinha em 9 meios-dias (semana de 09/11: 5; de 16/11: 4), os dois cabem até 20/11."; sem nada, "Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta."), texto_pergunta (as partes da pergunta da quinta e "Quem chama é você."; nulo sem sugestão), partes [{tipo, os, nomes, texto, dias}] (o motivo chamar de _agenda_dias_semana_motivos lê as que têm dia na semana perguntada ou depois), texto_livre (só com extra: "Sem lugar com a equipe de hoje: Nelson e César. Com mais uma pessoa 9 meios-dias, cabem até 20/11 (*agenda gestor* diz quando)."). {calculado_em, modo, dupla, capacidade {sem_lugar, extra, horizonte}, prazo, partes, texto, texto_pergunta, texto_livre, ms}. Escreve agenda.pessoa_extra só aqui (sempre de volta a vazio, também no erro) e, com o gestor que marca em teste, agenda.gestor = sombra só aqui dentro. VOLATILE, invoker, sem grant (só _agenda_gestor_chamar a chama). CORREÇÃO DA REVISÃO DA 7b (achados 19, 20, 22 e 25): a OS que já tem lugar — a reserva vigente de hoje em diante, a reserva da 1ª conta ou, com o gestor em teste, a reserva do "eu marcaria" de hoje — não entra em sem_lugar; os meios-dias de extra (meios_total, semanas) são os de quem trabalha nas OS que passam a caber, sem os do dono e um por pessoa e meio-dia; a dupla dita que espera ganha cabe_ate, e com prazo firme passado o texto diz "ele termina …, depois do prazo de …" (não "ele cabe"); a parte prazo da pergunta da quinta ganha "Se chamar, diga: Vanderlei com dupla; Mateus vem …." e o texto_livre começa por ela.';

-- agenda_rascunho_disponibilidade (de 20261101100100_agenda_fase7b_disponibilidade.sql)
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
  'Agenda de Produção (Fase 1, P5): quem vem quando vira RASCUNHO (nada em agenda_disponibilidade). p_situacao vem (disponível), nao_vem (indisponível), so_manha (a tarde indisponível), so_tarde (a manhã indisponível); p_padrao = toda semana (agenda_dias_da_semana_ditos: "segunda a sexta"; sábado só por data, salvo sabado_util: só sábado = pergunta, com outros dias sai do padrão e a releitura avisa), senão a data dita (agenda_data_dita, futuro). Pessoa resolvida no banco ("eu" = o sócio do login); os dias têm de estar no trecho. Devolve {ok, item, releitura} ou {ok:false, pergunta}. Fase 7b (P2): assinatura nova com p_semana no fim (a de 8 argumentos saiu; a chamada por nome de antes continua casando). Com a pergunta dos dias fora de desligado (modo_dias): p_semana ("semana que vem", "semana de 16/11", por _agenda_semana_dita) = os dias da semana dita (vem + os dias, o sábado de manhã; nao_vem + "a semana toda" = nenhum; um dia só é por data), nunca padrão, sem turno; chave disp:<pessoa>:s<segunda>; a releitura "Roberto, semana de 16/11: vem seg, ter e qui (e não vem qua e sex)." — o *grava* prende a semana (_agenda_equipe_dias_gravar). Sem padrão e sem semana, "vem" com 2 ou mais dias da semana que não são uma faixa ("qua e qui") = as datas desses dias na 1ª semana (seg a sáb) em que todos ainda estão por vir, estritamente depois de hoje; só dia útil (o feriado é recusado com o nome); sábado só com sabado_manha ≠ nunca e só de manhã; chave disp:<pessoa>:l<d1>_<d2>…:dia; nunca padrão; "qua a sex" continua faixa. Quem não está na equipe mas está no cadastro (prestador, diarista ou funcionário ativo; o 1º nome igual vence) entra pelo rascunho com "vem" e a releitura diz que, com *grava*, ele entra; ninguém = "Não achei Vinicius no cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo."; vários = "Qual Mateus: …?". Com modo_dias desligado, o de antes, byte a byte, e p_semana é recusado com a frase. CORREÇÃO DA REVISÃO DA 7b (achados 2, 13, 16 e 21): com modo_dias fora de desligado — (a) "Alex saiu" (nao_vem, padrao, os dias da semana inteira, "seg a sáb" ou "seg a sex") com saiu, saíram, não vem mais, não trabalha mais, não está mais, parou de vir ou foi embora no trecho vale como a semana inteira, sem os dias no trecho: o mesmo rascunho de "não vem mais de segunda a sábado"; (b) as datas de quem vem sob demanda ditas por extenso (duas ou mais: dd/mm, ou "dia" com os números, cada número no trecho; "qua 18/11 e qui 19/11", "18/11 e 19/11", "quarta dia 18 e quinta dia 19", "dia 18 e 19") são essas datas, de hoje em diante (sem o ano, o próximo; sem o mês, este ou o seguinte), o dia da semana dito tem de bater ("Os dias da semana e as datas não batem (…): me diga de novo."), só dia útil e o sábado como antes; a faixa ("qui 19 a qua 25/11") e os dias da semana sem número seguem como antes. Desligado, a de antes.';

-- _agenda_equipe_dias_gravar (de 20261101100100_agenda_fase7b_disponibilidade.sql)
create or replace function public._agenda_equipe_dias_gravar(p_payee uuid, p_seg date, p_dias smallint[], p_sabado boolean,
                                                             p_origem text, p_trecho text, p_agora timestamptz,
                                                             p_mensagem uuid default null, p_pergunta uuid default null,
                                                             p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_eh_dono  boolean;
  v_hoje     date;
  v_dias     smallint[];
  v_sab      boolean := coalesce(p_sabado, false);
  v_nome     text;
  v_semana   text;
  v_trecho   text := public._agenda_corta(nullif(btrim(coalesce(p_trecho, '')), ''), 300);
  v_d        date;
  v_sit      text;
  v_turno    text;
  v_nota     text;
  v_dono_sit text;
  v_quer     jsonb := '[]'::jsonb;
  v_tem      jsonb;
  v_conf     jsonb := '[]'::jsonb;
  v_linhas   jsonb := '[]'::jsonb;
  v_x        jsonb;
  v_id       uuid;
  v_tem_pad  boolean;
  v_hist     boolean;
  v_atual    smallint[];
  v_pad      boolean;
  v_txt      text;
  v_fora     smallint[];
begin
  -- 1. as entradas e quem é
  if p_payee is null or p_seg is null or p_agora is null then
    raise exception '_agenda_equipe_dias_gravar: sem a pessoa, a semana ou a hora' using errcode = '22004';
  end if;
  if p_origem is null or p_origem not in ('diarista', 'dono', 'agente') then
    raise exception '_agenda_equipe_dias_gravar: origem "%" inválida (diarista, dono ou agente)', p_origem using errcode = '22023';
  end if;
  if extract(isodow from p_seg)::int <> 1 then
    raise exception '_agenda_equipe_dias_gravar: a semana começa na segunda (veio %)', p_seg using errcode = '22023';
  end if;
  v_dias := array(select distinct x from unnest(coalesce(p_dias, '{}'::smallint[])) x order by 1);
  if not (v_dias <@ array[1, 2, 3, 4, 5]::smallint[]) then
    raise exception '_agenda_equipe_dias_gravar: os dias vão de 1 (seg) a 5 (sex); o sábado é p_sabado (veio %)', p_dias
      using errcode = '22023';
  end if;
  select public._agenda_nome_curto(py.name) into v_nome from public.payees py where py.id = p_payee;
  if not found then
    raise exception '_agenda_equipe_dias_gravar: a pessoa % não está no cadastro', p_payee using errcode = 'P0001';
  end if;
  v_eh_dono := p_payee is not distinct from public._agenda_dono(null);
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_semana := to_char(p_seg, 'DD/MM');

  -- 2 e 3. o que a semana deve ter, dia a dia (de hoje em diante; de seg a sex só dia útil; o sábado só de manhã, nunca
  -- "não vem"); a exceção do dono no dia vence a resposta do diarista (pula e volta em conflitos)
  for v_d in select g::date from generate_series(p_seg, p_seg + 5, interval '1 day') g loop
    continue when v_d < v_hoje;
    if extract(isodow from v_d)::int = 6 then
      continue when public.agenda_feriado(v_d) is not null
                 or exists (select 1 from public.agenda_disponibilidade r
                             where r.payee_id is null and r.situacao = 'indisponivel' and r.turno is null
                               and r.substituida_em is null and r.periodo @> v_d);
      v_sit := case when v_sab then 'disponivel' end;
      v_turno := 'manha';
    else
      continue when not public.agenda_dia_util(v_d);
      v_sit := case when extract(isodow from v_d)::smallint = any (v_dias) then 'disponivel'
                    when v_eh_dono then 'so_pontas' else 'indisponivel' end;
      v_turno := null;
    end if;
    if p_origem = 'diarista' then
      select d.situacao into v_dono_sit
        from public.agenda_disponibilidade d
       where d.payee_id = p_payee and d.substituida_em is null and d.origem = 'dono' and d.periodo @> v_d
       order by d.criado_em desc, d.id desc limit 1;
      if found then
        v_conf := v_conf || jsonb_build_array(jsonb_build_object('dia', v_d, 'situacao_do_dono', v_dono_sit));
        continue;
      end if;
    end if;
    v_quer := v_quer || jsonb_build_array(jsonb_build_object('dia', v_d, 'situacao', v_sit, 'turno', v_turno));
  end loop;

  -- 4. o padrão: só com dias, só para quem já tem padrão ou é o dono (quem vem sob demanda só prende a semana, R4.2(c)(4)), e só
  -- quando é outro (a semente do histórico sempre sai: a 1ª declaração a substitui)
  v_tem_pad := exists (select 1 from public.agenda_disponibilidade d
                        where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                          and d.situacao in ('disponivel', 'confirmada'));
  v_hist := exists (select 1 from public.agenda_disponibilidade d
                     where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                       and d.situacao in ('disponivel', 'confirmada') and d.origem = 'historico');
  v_atual := nullif(array(select distinct x
                            from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                           where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                             and d.situacao in ('disponivel', 'confirmada') and d.origem <> 'historico'
                           order by 1), '{}'::smallint[]);
  v_pad := cardinality(v_dias) > 0 and (v_tem_pad or v_eh_dono) and (v_hist or v_atual is distinct from v_dias);
  -- FASE 7b: (correção da revisão da 7b, achados 3 e 10) a semana dita pelo dono (origem dono: o rascunho com a semana, de outra pessoa
  -- ou dele mesmo) prende SÓ aquela semana: o padrão não muda (antes, "o Alex só pode seg e ter na semana que vem" virava o padrão de
  -- toda semana, calado). A exceção é a opção da pergunta dias_semana que diz os dias de toda semana ("Fico em campo de seg a sex",
  -- R4.2(b)): agenda_decidir liga agenda.dias_padrao_do_dono só nessa chamada.
  if p_origem = 'dono' and not (v_eh_dono and coalesce(current_setting('agenda.dias_padrao_do_dono', true), '') = 'sim') then
    v_pad := false;
  end if;
  -- FASE 7b: fim

  -- 5. o mesmo já gravado (as linhas vivas da semana iguais, nos dias de agora) e o padrão igual = nada muda
  select coalesce(jsonb_agg(jsonb_build_object('dia', lower(d.periodo), 'situacao', d.situacao, 'turno', d.turno)
                            order by lower(d.periodo), d.turno), '[]'::jsonb)
    into v_tem
    from public.agenda_disponibilidade d
   where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg and d.origem = p_origem
     and lower(d.periodo) in (select (e ->> 'dia')::date from jsonb_array_elements(v_quer) e);
  if not v_pad
     and v_tem = coalesce((select jsonb_agg(e order by (e ->> 'dia')::date, e ->> 'turno') from jsonb_array_elements(v_quer) e
                            where e ->> 'situacao' is not null), '[]'::jsonb)
     and not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg
                        and d.origem <> p_origem
                        and lower(d.periodo) in (select (e ->> 'dia')::date from jsonb_array_elements(v_quer) e)) then
    return jsonb_build_object('mudou', false, 'linhas', '[]'::jsonb, 'conflitos', v_conf, 'padrao_mudou', false,
                              'semente_saiu', false, 'semana', p_seg, 'dias', to_jsonb(v_dias), 'sabado', v_sab,
                              'texto', 'Já estava anotado assim.');
  end if;

  -- 2. troca e grava a semana (uma linha por dia)
  for v_x in select e from jsonb_array_elements(v_quer) e loop
    v_d := (v_x ->> 'dia')::date;
    update public.agenda_disponibilidade
       set substituida_em = p_agora
     where payee_id = p_payee and substituida_em is null and semana_dita = p_seg and periodo @> v_d;
    continue when v_x ->> 'situacao' is null;
    v_nota := case
      when p_origem = 'dono' and v_eh_dono then
        case v_x ->> 'situacao' when 'disponivel' then format('Você disse que fica em campo (semana de %s)', v_semana)
                                else format('Você disse que só abre e fecha (semana de %s)', v_semana) end
      when p_origem = 'dono' then
        case v_x ->> 'situacao' when 'disponivel' then format('Você disse que vem (semana de %s)', v_semana)
                                else format('Você disse que não vem (semana de %s)', v_semana) end
      when p_origem = 'agente' then
        case v_x ->> 'situacao' when 'disponivel' then format('Anotado que pode (semana de %s)', v_semana)
                                else format('Anotado que não pode (semana de %s)', v_semana) end
      else
        case v_x ->> 'situacao' when 'disponivel' then format('Disse que pode (semana de %s)', v_semana)
                                else format('Disse que não pode (semana de %s)', v_semana) end end;
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, semana_dita, mensagem_id,
                                               pergunta_id, criado_em, criado_por)
    values (p_payee, daterange(v_d, v_d, '[]'), v_x ->> 'turno', v_x ->> 'situacao', p_origem, v_nota, v_trecho, p_seg, p_mensagem,
            p_pergunta, p_agora, p_autor)
    returning id into v_id;
    v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('id', v_id, 'dia', v_d, 'situacao', v_x ->> 'situacao',
                                                                 'turno', v_x ->> 'turno'));
  end loop;

  -- 4. o padrão novo troca TODOS os padrões "vem" vivos da pessoa (qualquer origem); o padrão "não vem" de um turno fica
  if v_pad then
    update public.agenda_disponibilidade
       set substituida_em = p_agora
     where payee_id = p_payee and substituida_em is null and dias_semana is not null and situacao in ('disponivel', 'confirmada');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, mensagem_id, pergunta_id,
                                               criado_em, criado_por)
    values (p_payee, v_dias, null, 'disponivel', p_origem,
            case when p_origem = 'dono' then format('você disse em %s', to_char(v_hoje, 'DD/MM'))
                 else format('Disse em %s', to_char(v_hoje, 'DD/MM')) end,
            v_trecho, p_mensagem, p_pergunta, p_agora, p_autor);
  end if;

  -- 6. o texto (o dono: §6.3; a pessoa: §6.1; o dono sobre outra pessoa: a mesma forma)
  v_fora := array(select x::smallint from generate_series(1, 5) x
                   where not (x::smallint = any (v_dias))
                     and exists (select 1 from jsonb_array_elements(v_quer) e
                                  where extract(isodow from (e ->> 'dia')::date)::int = x));
  v_txt := case
    when v_eh_dono and p_origem = 'dono' then
      case when cardinality(v_dias) = 0 and not v_sab then format('Anotei: na semana de %s você só abre e fecha.', v_semana)
           when cardinality(v_fora) = 0 then format('Anotei: na semana de %s você fica em campo %s.', v_semana,
                                                    public._agenda_dias_curtos(v_dias, v_sab))
           else format('Anotei: na semana de %s você fica em campo %s; nos outros dias, só abre e fecha.', v_semana,
                       public._agenda_dias_curtos(v_dias, v_sab)) end
    when p_origem = 'dono' then
      case when cardinality(v_dias) = 0 and not v_sab then format('Anotei: na semana de %s %s não vem.', v_semana, v_nome)
           else format('Anotei: na semana de %s %s vem %s.', v_semana, v_nome, public._agenda_dias_curtos(v_dias, v_sab)) end
    else
      case when cardinality(v_dias) = 0 and not v_sab then format('Anotei: na semana de %s você não pode. Obrigado por avisar!', v_semana)
           else format('Anotei: na semana de %s você pode %s. Obrigado!', v_semana, public._agenda_dias_curtos(v_dias, v_sab)) end end;

  -- FASE 7b: (correção da revisão da 7b, achados 3 e 10) quando o padrão do dono muda (a opção "toda semana" da pergunta dos dias), a
  -- resposta diz que é toda semana, não só a semana da pergunta
  if v_pad and v_eh_dono and p_origem = 'dono' then
    v_txt := case when cardinality(v_fora) = 0
                  then format('Anotei: você fica em campo %s, toda semana a partir de agora. Se mudar, me diga.',
                              public._agenda_dias_curtos(v_dias, v_sab))
                  else format('Anotei: você fica em campo %s, toda semana a partir de agora; nos outros dias, só abre e fecha. Se mudar, me diga.',
                              public._agenda_dias_curtos(v_dias, v_sab)) end;
  end if;
  -- FASE 7b: fim
  return jsonb_build_object('mudou', true, 'linhas', v_linhas, 'conflitos', v_conf, 'padrao_mudou', v_pad,
                            'semente_saiu', v_pad and v_hist, 'semana', p_seg, 'dias', to_jsonb(v_dias), 'sabado', v_sab,
                            'texto', v_txt);
end;
$function$;

comment on function public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid) is
  'Agenda de Produção (Fase 7b, P2): o ÚNICO que escreve a semana presa (agenda_disponibilidade.semana_dita) — a resposta da pessoa à pergunta da semana (origem diarista, P3), a opção do dono na pergunta dias_semana (P3) e a semana dita pelo dono no rascunho (origem dono). Para cada dia de seg a sex da semana de p_seg, de hoje em diante e só dia útil: troca a linha viva da semana nesse dia e grava [d, d] disponível nos dias de p_dias e, nos outros, so_pontas (o dono: só abre e fecha) ou indisponível (os outros); o sábado (p_seg + 5), só com p_sabado, disponível de manhã (nunca "não vem"). Com origem diarista, a exceção viva do dono no dia vence: o dia fica e volta em conflitos [{dia, situacao_do_dono}]. O padrão: com dias, para quem já tem padrão ou é o dono (quem vem sob demanda só prende a semana), quando é outro — troca TODOS os padrões "vem" vivos da pessoa (qualquer origem: a semente sai) e grava o novo (sem frequência); "nenhum" prende só a semana. O mesmo de novo = nada muda ({mudou: false}). {mudou, linhas [{id, dia, situacao, turno}], conflitos, padrao_mudou, semente_saiu, semana, dias, sabado, texto ("Anotei: …")}. Security definer, search_path fixo, sem grant a ninguém (só as funções da agenda o chamam). CORREÇÃO DA REVISÃO DA 7b (achados 3 e 10): com origem dono, o padrão só muda com agenda.dias_padrao_do_dono = sim (a opção com dias da pergunta dias_semana do dono, que agenda_decidir liga só nessa chamada; "Anotei: você fica em campo de seg a sex, toda semana a partir de agora. Se mudar, me diga."); a semana dita pelo dono no rascunho, de outra pessoa ou dele mesmo, prende só a semana. A resposta da pessoa (origem diarista) continua como antes.';

-- agenda_decidir (de 20261101100200_agenda_fase7b_pergunta_semanal.sql)
create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
  -- FASE 7b: (7b P3) a chamada da equipe, o contato e a pergunta dos dias do dono
  v_7b_g    jsonb;
  v_7b_txt  text;
  v_7b_nome text;
  v_7b_dias smallint[];
  v_7b_acao uuid;
  -- FASE 7b: fim
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  -- CORREÇÃO FASE 6: (C1) regressão B2: a pergunta do aprendizado toma a trava da rodada do aprendizado ANTES de travar a
  -- pergunta (é aqui, e não em _agenda_aprendizado_decidir, que a linha da pergunta é travada primeiro); as outras não
  if exists (select 1 from public.agenda_perguntas q where q.id = p_pergunta and q.tipo = 'aprendizado') then
    perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  end if;
  -- CORREÇÃO FASE 6: fim
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  -- FASE 3: a diária (a pergunta crítica que diverge e a de ligar a OS) tem o efeito dela e o modo dela (modo_diaria):
  -- _agenda_decidir_diaria (20261026100300).
  if v_q.tipo in ('diaria', 'diaria_ligar') then
    return public._agenda_decidir_diaria(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 5: a mensagem ao cliente (cliente_aprovar, a aprovação dos primeiros dias, e cliente_aviso, a crítica do aviso de
  -- atraso) tem o efeito dela e o modo dela (modo_cliente): _agenda_cliente_decidir (20261028100300).
  if v_q.tipo in ('cliente_aprovar', 'cliente_aviso') then
    return public._agenda_cliente_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_agora);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) a pergunta do aprendizado (a troca grande de um valor medido, a carga de cada pessoa pelo plano cumprido e
  -- o planejador mais forte) tem o efeito dela e o modo dela (modo_aprendizado e aprendizado_ligados):
  -- _agenda_aprendizado_decidir (20261029100600). A opção 1 da carga é a única escrita de parâmetro (carga_max), com *desfaz*.
  if v_q.tipo = 'aprendizado' then
    return public._agenda_aprendizado_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7: (7a P4) as perguntas do gestor da agenda (situacao e estimativa decidem aqui; os outros 8 tipos, nos pacotes que os
  -- criam, que recriam _agenda_gestor_decidir) têm o efeito delas e o modo delas (o do gestor): _agenda_gestor_decidir
  -- (20261031100300). dia_avisado e dia_prometido não: são críticas do plano e seguem a decisão de sempre, abaixo; a
  -- equipe_cadastro desta etapa não tem opções ("não é de decisão").
  if v_q.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado', 'bem_livre',
                  'compre_ate', 'sinal') then
    return public._agenda_gestor_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 7: fim
  -- FASE 7b: (7b P3; R4.1-3, R4.1-6, R4.2(b)) as perguntas da equipe com opções — a chamada (1 está certo; 2 mudou: "Me diga quem
  -- saiu ou quem entrou e em que dias vem …", sem diária), o contato (1 põe na rotina, com *desfaz*; 2 grava a recusa: a linha parada,
  -- e nem a regra d14 nem a pergunta voltam) e a pergunta dos dias do dono (a opção com dias grava a semana pelo
  -- _agenda_equipe_dias_gravar, origem dono — a 2, "Fico em campo de seg a sex", cria o padrão dele —; a 1 só fica respondida). Só
  -- com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados. A chamada da 7a (sem opções) segue o caminho de antes.
  if v_q.tipo = 'dias_semana' or (v_q.tipo = 'equipe_cadastro' and jsonb_array_length(v_q.opcoes) > 0) then
    if v_q.estado <> 'aberta' then
      return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
    end if;
    if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
      return jsonb_build_object('ok', false, 'texto', 'Essa pergunta da equipe ainda está em teste: mostro como ficaria, mas não mudo nada.');
    end if;
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_7b_nome := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_q.payee_id), 'a pessoa');
    if v_q.tipo = 'dias_semana' then
      if v_opc -> 'efeito' ? 'dias' then
        v_7b_dias := array(select y::smallint from jsonb_array_elements_text(v_opc #> '{efeito,dias}') y);
        -- (correção da revisão da 7b, achados 3 e 10) a opção com dias da pergunta dos dias do dono ("Fico em campo de seg a
        -- sex") diz os dias dele de toda semana: só ela troca o padrão (o gravador prende só a semana em qualquer outra fala do dono)
        if cardinality(v_7b_dias) > 0 and v_q.payee_id is not distinct from public._agenda_dono(null) then
          perform set_config('agenda.dias_padrao_do_dono', 'sim', true);
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_g := public._agenda_equipe_dias_gravar(v_q.payee_id, v_q.dia, v_7b_dias,
                                                    coalesce((v_opc #>> '{efeito,sabado}')::boolean, false), 'dono',
                                                    'opção ' || p_opcao, p_agora, null, v_q.id, p_autor);
        -- (correção da revisão da 7b, achados 3 e 10) a variável volta a vazio logo depois
        perform set_config('agenda.dias_padrao_do_dono', '', true);
        -- (correção da revisão da 7b: fim)
        v_7b_txt := v_7b_g ->> 'texto';
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, pergunta_id, depois, texto, autor)
        values (clock_timestamp(), p_hoje, true, 'dono', 'equipe', v_q.payee_id, v_q.id,
                jsonb_build_object('motivo', 'dias_semana', 'semana', v_q.dia, 'dias', to_jsonb(v_7b_dias),
                                   'mudou', v_7b_g -> 'mudou', 'padrao_mudou', v_7b_g -> 'padrao_mudou'),
                left(v_7b_txt, 400), p_autor)
        returning id into v_7b_acao;
      else
        v_7b_txt := format('Anotei: na semana de %s fica assim.', to_char(v_q.dia, 'DD/MM'));
      end if;
      return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao);
    end if;
    if v_opc #>> '{efeito,contato}' = 'por' then
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_q.payee_id, true, 'dono', p_agora)
      on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
      v_7b_txt := format('Pus %s na rotina da equipe, como você pediu. *desfaz* tira.', v_7b_nome);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, pergunta_id, depois, texto, autor,
                                       desfazivel_ate)
      values (clock_timestamp(), p_hoje, true, 'dono', 'equipe', v_q.payee_id, v_q.id,
              jsonb_build_object('motivo', 'contato', 'payee', v_q.payee_id), left(v_7b_txt, 400), p_autor,
              p_agora + cf.desfazer_validade)
      returning id into v_7b_acao;
      return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao);
    end if;
    if v_opc #>> '{efeito,contato}' = 'nao' then
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em, parou_em, parou_motivo)
      values (v_q.payee_id, false, 'dono', p_agora, p_agora, 'você disse que não')
      on conflict (payee_id) do nothing;
      return jsonb_build_object('ok', true, 'texto', format('Anotei: %s fica fora da rotina da equipe.', v_7b_nome));
    end if;
    if v_opc #>> '{efeito,chamada}' = 'mudou' then
      return jsonb_build_object('ok', true,
        'texto', 'Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça).');
    end if;
    return jsonb_build_object('ok', true, 'texto', 'Anotei: sigo com a equipe que tenho.');
  end if;
  -- FASE 7b: fim
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista). CORREÇÃO FASE 6 (C1, regressão B2): a pergunta do aprendizado toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do for update da pergunta. FASE 7 (7a P4): as perguntas do gestor da agenda (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal) vão a _agenda_gestor_decidir (o efeito e o modo delas: o do gestor); dia_avisado e dia_prometido seguem a decisão crítica de sempre; equipe_cadastro, a de antes. FASE 7b (P3; R4.1-3, R4.1-6, R4.2(b)): as perguntas da equipe com opções têm o efeito delas, com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados (senão "ainda está em teste") — equipe_cadastro chamada: 1 "Anotei: sigo com a equipe que tenho."; 2 "Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça)." (sem diária); equipe_cadastro contato: 1 põe na lista da rotina (agenda_equipe_contato recebe_rotina, incluido_por dono) com a ação equipe desfazível ("Pus Mateus na rotina da equipe, como você pediu. *desfaz* tira.", depois.motivo contato); 2 grava a recusa — a linha parada (recebe_rotina false, parou_em agora, "você disse que não"): nem a regra d14 nem a pergunta voltam; dias_semana: a opção com dias grava a semana pelo _agenda_equipe_dias_gravar (origem dono; a 2, "Fico em campo de seg a sex", cria o padrão do dono {1..5} sem frequência; a 3, "Nenhum dia", prende só a semana), com a ação equipe do dono; a 1 ("Fica assim") só fica respondida. A chamada da 7a (sem opções) e o telefone (sem opções) seguem o de antes. CORREÇÃO DA REVISÃO DA 7b (achados 3 e 10): na pergunta dias_semana do dono, a opção com dias grava com agenda.dias_padrao_do_dono = sim (só nessa chamada): ela é a única fala do dono que troca o padrão dele ("Fico em campo de seg a sex" = toda semana); a resposta diz "toda semana a partir de agora".';

-- agenda_resposta_da_equipe (de 20261101100200_agenda_fase7b_pergunta_semanal.sql)
create or replace function public.agenda_resposta_da_equipe(p_phone text, p_body text, p_message_id text,
                                                            p_recebida_em timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_recebida_em at time zone 'America/Sao_Paulo')::date;
  v_hora   time := (p_recebida_em at time zone 'America/Sao_Paulo')::time;
  v_ids    uuid[];
  v_payee  uuid;
  v_nome   text;
  v_l      jsonb;
  v_tipo   text;
  m        public.agenda_equipe_mensagens%rowtype;
  v_recibo timestamptz;
  v_trecho text := left(btrim(coalesce(p_body, '')), 500);
  v_wa     text := nullif(btrim(coalesce(p_message_id, '')), '');
  v_dia    date;
  v_f      jsonb;
  v_r      jsonb;
  v_os     uuid[];
  v_disp   uuid;
  v_rep    jsonb;
  v_acao   uuid;
  v_plano  text[];
  v_ditos  text[];
  v_conf   text[];
  v_term   boolean;
  v_ent    boolean;
  v_estado text;
  v_msg    text;
  v_resp   text;
  v_div    boolean;
  -- FASE 7b: (7b P3, §5.2; A1, A3) a pergunta dos dias da semana: a mensagem aberta dela, a leitura, a gravação e a resposta
  v_7b_mq   public.agenda_equipe_mensagens%rowtype;
  v_7b_vd   jsonb;
  v_7b_g    jsonb;
  v_7b_resp text;
  v_7b_ult  boolean;
  v_7b_sem  text;
  v_7b_dias smallint[];
  v_7b_sab  boolean;
  -- FASE 7b: fim
begin
  if v_trecho = '' or p_recebida_em is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_ids := public._agenda_payees_do_telefone(p_phone, v_hoje);
  if cardinality(v_ids) > 1 then
    perform public.log_app_error('db', 'agenda: o telefone de uma mensagem é de mais de uma pessoa da equipe; não li a resposta',
                                 'agenda', 'equipe:telefone', 'warn', jsonb_build_object('payees', to_jsonb(v_ids)));
    return jsonb_build_object('consumiu', false, 'motivo', 'ambiguo');
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  v_payee := v_ids[1];
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_payee);
  -- a mesma mensagem dele de novo: nada muda
  if v_wa is not null and exists (select 1 from public.agenda_equipe_mensagens x
                                   where x.payee_id = v_payee and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)) then
    return jsonb_build_object('consumiu', exists (select 1 from public.agenda_equipe_mensagens x
                                                   where x.payee_id = v_payee and x.modo = 'ligado'
                                                     and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)),
                              'repetida', true);
  end if;

  -- FASE 7b: (7b P3, §5.2 item 1) a pergunta dos dias da semana aberta — ligada, enfileirada, mandada antes desta mensagem e com o
  -- prazo da semana por vir (a quinta que planeja a semana, hora_do_plano − equipe_dias_fechar_antes) — e a leitura dela, sem IA. Só
  -- com a pergunta dos dias ligada (modo_dias): em teste ela nunca sai, e nada daqui muda.
  if cf.modo_dias = 'ligado' then
    select * into v_7b_mq from public.agenda_equipe_mensagens x
     where x.payee_id = v_payee and x.tipo = 'dias' and x.modo = 'ligado' and x.estado = 'enfileirada'
       and x.enviar_em <= p_recebida_em
       and p_recebida_em < (((x.dia - 7 + (cf.dia_do_plano - 1)) + cf.hora_do_plano) - cf.equipe_dias_fechar_antes)
                           at time zone 'America/Sao_Paulo'
     order by x.enviar_em desc, x.criada_em desc limit 1;
    if v_7b_mq.id is not null then
      v_7b_vd := public._agenda_ler_dias_da_equipe(p_body);
    end if;
  end if;
  -- FASE 7b: fim
  v_l := public._agenda_ler_resposta_da_equipe(p_body);
  v_tipo := v_l ->> 'tipo';
  -- a quem ele responde: a última que o sistema começou (ligado, enfileirada, dentro da validade)
  select * into m from public.agenda_equipe_mensagens x
   where x.payee_id = v_payee and x.tipo <> 'resposta' and x.modo = 'ligado' and x.estado = 'enfileirada'
     -- FASE 7b: (7b P3, §5.2 item 2) a pergunta dos dias da semana não é a mensagem a que ele responde no resto (ela tem o ramo dela)
     and x.tipo <> 'dias'
     -- FASE 7b: fim
     and x.enviar_em <= p_recebida_em and x.enviar_em >= p_recebida_em - cf.equipe_resposta_validade
   order by x.enviar_em desc, x.criada_em desc limit 1;
  -- o recibo das diárias mandado depois dela: o "ok" é do recibo (NOVO-agenda-17); a pergunta é sempre da agenda
  select max(a.enviado_ao_freelancer_em) into v_recibo
    from public.acertos_diarias a
   where a.favorecido_id = v_payee and a.status = 'fechado' and a.conferido_em is null
     and a.enviado_ao_freelancer_em > p_recebida_em - interval '7 days' and a.enviado_ao_freelancer_em <= p_recebida_em;
  if v_tipo <> 'pergunta' and v_recibo is not null and (m.id is null or v_recibo > m.enviar_em) then
    return jsonb_build_object('consumiu', false, 'motivo', 'recibo');
  end if;
  -- FASE 7b: (7b P3, §5.2 item 3; A1 = NOVO-agenda-52, A3 = NOVO-agenda-54) a resposta à pergunta dos dias da semana, antes da
  -- pergunta, do "não vou" e do "como foi":
  --   · os dias ou "nenhum" (em qualquer ordem: a frase com os dias é sobre a semana) gravam a semana presa — e o padrão de quem tem —
  --     pelo _agenda_equipe_dias_gravar (origem diarista; a exceção do dono no dia vence e volta em conflitos) e respondem
  --     "Anotei: …" (§6.1);
  --   · "igual" (ou "ok") com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!";
  --   · não entendi com a pergunta por último, e a leitura geral não é pergunta, presença nem turnos (o "não vou" junto de um dia da
  --     semana também: "segunda não posso" é sobre a semana, A3): na 1ª vez, "Não entendi os dias da semana de 16/11. …"; na 2ª, a
  --     pergunta equipe_resposta ao dono, e a mensagem fica respondida.
  -- Fora disso, o de antes (a mensagem a que ele responde é a última que o sistema começou, fora a pergunta da semana).
  if v_7b_mq.id is not null then
    v_7b_ult := v_7b_mq.enviar_em > coalesce(m.enviar_em, '-infinity'::timestamptz);
    v_7b_sem := to_char(v_7b_mq.dia, 'DD/MM');
    -- (correção da revisão da 7b, achado 8) a resposta só é da pergunta da semana quando ela é a última mensagem que o sistema
    -- mandou a ele (v_7b_ult), quando a frase fala da semana, ou quando é só a lista dos dias (o formato que a pergunta pede: "seg ter qui",
    -- "nenhum") e a leitura de sempre não a entende. Com a ficha, a confirmação ou o "como foi" mandados depois dela, "não posso", "ok,
    -- sexta tô lá", "sim, todos prontos" e "terminei todos" são a resposta a essas (o caminho de antes) e a pergunta da semana continua
    -- aberta: antes, viravam os dias da semana (e o padrão dele), e a falta de amanhã ficava sem replano.
    if not v_7b_ult and v_7b_vd ->> 'tipo' in ('dias', 'nenhum')
       and not (public._agenda_normal(p_body) ~ '\msemana\M')
       and not (v_tipo = 'nao_entendi'
                and btrim(regexp_replace(public._agenda_normal(p_body),
                                         '\m(segunda|terca|quarta|quinta|sexta|sabado|seg|ter|qua|qui|sex|sab|feira|nenhum|nenhuma|dia|dias|e|a|ate|so|somente|apenas|posso|consigo|vou|venho|todos|todo|toda|na|no|nos|de|do|da)s?\M',
                                         '', 'g')) = '') then
      v_7b_vd := v_7b_vd || jsonb_build_object('tipo', 'outra_mensagem');
    end if;
    -- (correção da revisão da 7b: fim)
    if v_7b_vd ->> 'tipo' in ('dias', 'nenhum') then
      v_7b_dias := array(select y::smallint from jsonb_array_elements_text(coalesce(v_7b_vd -> 'dias', '[]'::jsonb)) y);
      v_7b_sab := coalesce((v_7b_vd ->> 'sabado')::boolean, false);
      v_7b_g := public._agenda_equipe_dias_gravar(v_payee, v_7b_mq.dia, v_7b_dias, v_7b_sab, 'diarista', v_trecho, p_recebida_em,
                                                  v_7b_mq.id);
      v_7b_resp := case when cardinality(v_7b_dias) = 0 and not v_7b_sab
                        then format('Anotei: na semana de %s você não pode. Obrigado por avisar!', v_7b_sem)
                        else format('Anotei: na semana de %s você pode %s. Obrigado!', v_7b_sem,
                                    public._agenda_dias_curtos(v_7b_dias, v_7b_sab)) end;
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_7b_vd || jsonb_build_object('mudou', v_7b_g -> 'mudou', 'padrao_mudou', v_7b_g -> 'padrao_mudou',
                                                     'conflitos', coalesce(v_7b_g -> 'conflitos', '[]'::jsonb))
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', v_7b_vd ->> 'tipo', 'mudou', v_7b_g -> 'mudou',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'igual' and v_7b_ult then
      v_7b_resp := format('Anotei: semana de %s igual (%s). Obrigado!', v_7b_sem,
                          public._agenda_dias_declarados(v_payee, v_7b_mq.dia) ->> 'texto');
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_7b_vd
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'igual',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'nao_entendi' and v_7b_ult
       and (v_tipo not in ('pergunta', 'nao_vou', 'presenca', 'turnos')
            or (v_tipo = 'nao_vou'
                and public._agenda_normal(p_body) ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|seg|ter|qua|qui|sex|sab)s?\M')) then
      if coalesce((v_7b_mq.leitura ->> 'nao_entendi')::int, 0) = 0 then
        v_7b_resp := format('Não entendi os dias da semana de %s. Mande só os dias, assim: seg ter qui (ou "nenhum").', v_7b_sem);
        update public.agenda_equipe_mensagens
           set leitura = coalesce(leitura, '{}'::jsonb)
                         || jsonb_build_object('nao_entendi', 1, 'trecho', v_trecho, 'recebida_em', p_recebida_em)
         where id = v_7b_mq.id;
        v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                               'dias:' || v_7b_mq.dia);
        return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 1,
                                  'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
      end if;
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:dias', v_payee, v_7b_mq.dia), v_payee,
        null, v_7b_mq.dia,
        format('%s respondeu "%s" à pergunta dos dias da semana de %s, e eu não entendi. Diga os dias dele (ex.: %s vem seg e ter na semana de %s).',
               v_nome, public._agenda_corta(v_trecho, 120), v_7b_sem, v_nome, v_7b_sem),
        'ligado', p_recebida_em);
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = coalesce(v_7b_mq.leitura, '{}'::jsonb) || v_7b_vd || jsonb_build_object('nao_entendi', 2)
       where id = v_7b_mq.id;
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 2, 'resposta', null);
    end if;
  end if;
  -- FASE 7b: fim

  -- ── pergunta: a ficha do publicado, sem valores (em sombra só registra) ──────────────────────────────
  if v_tipo = 'pergunta' then
    v_dia := case when v_l ->> 'dia' = 'amanha' then v_hoje + 1 else v_hoje end;
    v_f := public.agenda_equipe_ficha(v_payee, v_dia, v_hoje);
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_f ->> 'texto_resposta', p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    if v_r ? 'id' then
      update public.agenda_equipe_mensagens
         set leitura = v_l || jsonb_build_object('pergunta', v_trecho, 'recebida_em', p_recebida_em)
       where id = (v_r ->> 'id')::uuid;
    end if;
    if not coalesce((v_f ->> 'tem_plano')::boolean, false) and public.agenda_dia_util(v_dia) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:pergunta', v_payee, v_dia), v_payee,
        null, v_dia, format('O %s perguntou o que tem %s e ainda não tem plano para ele. Diga a ele o que fazer.', v_nome,
                            case when v_dia = v_hoje then 'hoje' else 'amanhã (' || public._dia_curto(v_dia) || ')' end),
        case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end, p_recebida_em);
    end if;
    return jsonb_build_object('consumiu', cf.modo_equipe = 'ligado', 'tipo', v_tipo,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_f ->> 'texto_resposta' end,
                              'envio', v_r ->> 'estado');
  end if;

  -- ── não vou (à ficha ou à confirmação; sem nada pendente: hoje antes do meio-dia, senão o próximo dia útil) ─
  -- (Revisão C1, item 3) também ao "como foi hoje?": aí o dia é o da ficha que ele levava (senão o próximo dia útil), e o
  -- "como foi" de hoje continua esperando a resposta de hoje (não vira a pergunta da diária de hoje)
  if v_tipo = 'nao_vou' and (m.id is null or m.tipo in ('ficha', 'confirmar', 'como_foi')) then
    -- (antes do fim da manhã, hoje; depois, o próximo dia útil)
    v_dia := case when m.tipo = 'como_foi' then coalesce(m.leva_ficha_de, public.agenda_somar_du(m.dia, 1))
                  else coalesce(m.dia, case when v_hora < cf.manha_fim then v_hoje else public.agenda_somar_du(v_hoje, 1) end) end;
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = v_payee and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    if cf.modo_equipe <> 'ligado' then
      -- em sombra nada muda: só o que faria
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
      values (clock_timestamp(), v_hoje, false, 'equipe', 'equipe', v_os[1], v_os, v_payee,
              jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho),
              left(format('Em teste: o %s avisou que não vem %s; eu tiraria ele do plano desse dia.', v_nome,
                          public._agenda_dia_ref(v_dia, v_hoje)), 400));
      return jsonb_build_object('consumiu', false, 'tipo', v_tipo, 'modo', 'sombra');
    end if;
    perform set_config('agenda.hoje', v_hoje::text, true);
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> v_dia) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(v_dia, v_dia, '[]'), 'indisponivel', 'diarista', left('Avisou que não vem: ' || v_trecho, 200),
              left(v_trecho, 300), p_recebida_em)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        -- (C1, NOVO-agenda-27) a falta é evento real: o replano refaz os meios-dias que sobram da OS num bloco só, amanhã
        -- incluído (_agenda_violacoes lê agenda.replano_da_falta); o *desfaz* volta tudo
        perform set_config('agenda.replano_da_falta', 'on', true);
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', v_hoje, p_recebida_em, null);
        perform set_config('agenda.replano_da_falta', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.replano_da_falta', '', true);
        perform public.log_app_error('db', 'agenda: replanejar depois do "não vou" da equipe falhou: ' || v_msg, 'agenda',
                                     'equipe:replanejar', 'error',
                                     jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado, 'payee', v_payee));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), v_hoje, true, 'equipe', 'equipe', v_os[1], v_os, v_payee,
            jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho, 'disponibilidade', v_disp,
                               'mensagem', m.id, 'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb),
                               'acorde', v_dia <= public.agenda_somar_du(v_hoje, cf.congelamento_du)),
            left(format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe(v_dia, v_hoje))
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400))
    returning id into v_acao;
    -- (C1, item 3) o "como foi" de hoje não é respondido pelo "não vou" de amanhã: ele segue esperando a resposta de hoje
    if m.id is not null and m.tipo <> 'como_foi' then
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l,
             acao_id = v_acao
       where id = m.id;
    end if;
    v_resp := format('Tá bom, aviso %s.', coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p
                                                              where p.id = public._agenda_dono(null)), 'o responsável'));
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_resp, p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'acao_id', v_acao, 'dia', v_dia,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_resp end, 'envio', v_r ->> 'estado');
  end if;

  -- Daqui em diante só a resposta a uma mensagem que o sistema mandou.
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'tipo', v_tipo);
  end if;

  -- ── à ficha ou à confirmação ────────────────────────────────────────────────────────────────────────
  if m.tipo in ('ficha', 'confirmar') then
    -- (Revisão C1, item 7) o "ok" com os turnos ditos diferentes do plano ("ok, só de manhã" com o dia todo no plano) não
    -- confirma o dia: vai ao dono, como o não entendido (com o plano no texto)
    v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                      where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      order by 1);
    v_ditos := case when jsonb_typeof(v_l -> 'turnos') = 'array'
                    then array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1) end;
    v_div := v_tipo = 'turnos' and v_ditos is not null
             and not (v_ditos = v_plano or (v_ditos = array['meio'] and cardinality(v_plano) = 1));
    if not v_div
       and (v_tipo in ('ok', 'presenca') or (v_tipo = 'turnos' and coalesce((v_l ->> 'ok')::boolean, false))) then
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'confirmada'
                        and d.turno is null and d.periodo @> m.dia) then
        insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
        values (v_payee, daterange(m.dia, m.dia, '[]'), 'confirmada', 'diarista',
                left(case m.tipo when 'ficha' then 'Confirmou a ficha: ' else 'Confirmou de manhã: ' end || v_trecho, 200),
                left(v_trecho, 300), p_recebida_em);
      end if;
    else
      -- não entendi (ou turnos sem ok): vai ao dono com o trecho, e nada muda (nem remaneja: não é silêncio)
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:%s', v_payee, m.dia, m.tipo), v_payee,
        null, m.dia, format('O %s respondeu "%s" à %s de %s', v_nome, public._agenda_corta(v_trecho, 120),
                            case m.tipo when 'ficha' then 'ficha' else 'confirmação' end, public._dia_curto(m.dia))
                     || case when v_div
                             then ', e o plano é ' || case when v_plano = array['manha', 'tarde'] then 'o dia todo'
                                                           when v_plano = array['manha'] then 'a manhã'
                                                           when v_plano = array['tarde'] then 'a tarde'
                                                           else 'sem nada para ele' end || '.'
                             else '.' end,
        'ligado', p_recebida_em);
    end if;
    update public.agenda_equipe_mensagens
       set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'resposta', null);
  end if;

  -- ── ao "como foi hoje?" ─────────────────────────────────────────────────────────────────────────────
  v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                    where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
  v_ent := true;
  if v_tipo = 'ok' or (v_tipo = 'turnos' and v_l -> 'turnos' = 'null'::jsonb and coalesce((v_l ->> 'ok')::boolean, false)) then
    -- "ok" = tudo como o previsto: os turnos do plano e terminou (salvo "ok, mas não terminei")
    v_ditos := v_plano;
    v_term := coalesce((v_l ->> 'terminou')::boolean, true);
  elsif v_tipo = 'turnos' and jsonb_typeof(v_l -> 'turnos') = 'array' then
    v_ditos := array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1);
    v_term := (v_l ->> 'terminou')::boolean;
  else
    -- não entendi, "terminei" sem o dia, "não vou"/presença fora de hora: a diária vira pergunta (crítica)
    v_ent := false;
    v_ditos := null;
    v_term := (v_l ->> 'terminou')::boolean;
  end if;
  update public.agenda_equipe_mensagens
     set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
         leitura = v_l || jsonb_build_object('entendeu', v_ent, 'turnos_lidos', to_jsonb(v_ditos), 'turnos_plano', to_jsonb(v_plano),
                                             'terminou', v_term)
   where id = m.id;
  if v_ent then
    v_conf := array(select x from unnest(v_ditos) x where x = any (v_plano) order by 1);
    perform set_config('agenda.hoje', v_hoje::text, true);
    begin
      if cardinality(v_conf) > 0 then
        -- os turnos que ele confirmou viram resultado (via equipe), e a diária é decidida em seguida
        perform set_config('agenda.turnos_equipe', array_to_string(v_conf, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'cumprido', null, null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      elsif v_ditos = '{}'::text[] then
        v_r := public.agenda_registrar_dia(null, m.dia, 'nao_cumprido', 'equipe', null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform set_config('agenda.turnos_equipe', '', true);
      perform public.log_app_error('db', 'agenda: anotar o dia pela resposta da equipe falhou: ' || v_msg, 'agenda',
                                   'equipe:dia', 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
    end;
    -- o "ok" ao "como foi" que levava a ficha de amanhã confirma amanhã também — (C1, item 3) salvo se ele já disse que
    -- não vem amanhã (o "ok" depois do "amanhã não vou" é sobre hoje)
    if v_tipo = 'ok' and m.leva_ficha_de is not null
       and not exists (select 1 from public.agenda_disponibilidade d
                        where d.payee_id = v_payee and d.substituida_em is null and d.situacao in ('confirmada', 'indisponivel')
                          and d.turno is null and d.periodo @> m.leva_ficha_de) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(m.leva_ficha_de, m.leva_ficha_de, '[]'), 'confirmada', 'diarista',
              left('Confirmou a ficha junto do "como foi": ' || v_trecho, 200), left(v_trecho, 300), p_recebida_em);
    end if;
  end if;
  -- a diária do dia (idempotente: o agenda_registrar_dia já a chamou quando anotou)
  begin
    v_r := public._agenda_diaria_do_dia(v_payee, m.dia, 'equipe', v_hoje, p_recebida_em);
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a diária pela resposta da equipe falhou: ' || v_msg, 'agenda', 'equipe:diaria',
                                 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
  end;
  return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'entendeu', v_ent, 'resposta', null, 'diaria', v_r ->> 'status');
end;
$function$;

comment on function public.agenda_resposta_da_equipe(text, text, text, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a mensagem do técnico (número que não é login de admin), chamada pelo whatsapp-webhook antes da confirmação do cliente e da conferência do recibo. modo_equipe desligado, telefone de ninguém da equipe (ou de dois) = {consumiu: false}. A mesma mensagem (p_message_id) de novo = nada muda. Lida por _agenda_ler_resposta_da_equipe. Decide a última mensagem que o sistema mandou (ligado, enfileirada, dentro de equipe_resposta_validade); o recibo de diárias mandado depois dela fica com o "ok" (NOVO-agenda-17: consumiu false). pergunta → a ficha do publicado (agenda_equipe_ficha.texto_resposta) como resposta enfileirada (sem plano: a pergunta equipe_resposta ao dono); em sombra só registra (consumiu false). nao_vou → indisponível no dia (agenda_disponibilidade origem diarista), replano (modo_proposta ligado, origem vigia), ação equipe com o acorde para a rotina e "Tá bom, aviso o Gustavo."; em sombra só a ação executada = false. ok/presença à ficha ou à confirmação → confirmada, sem resposta; não entendido → equipe_resposta ao dono, sem remanejo. Ao "como foi hoje?": ok = os turnos do plano e terminou; os turnos ditos viram resultado (agenda_registrar_dia via equipe, só os turnos confirmados) e a diária (_agenda_diaria_do_dia); não entendido = a pergunta crítica da diária. Sem pendente (ok, turnos, presença, não entendi) = consumiu false. {consumiu, tipo, resposta, acao_id}. Só service_role. FASE 7b (P3, §5.2; A1 = NOVO-agenda-52, A2, A3 = NOVO-agenda-54): com modo_dias ligado, a resposta à pergunta dos dias da semana (a mensagem dias ligada, enfileirada, mandada antes e com o prazo da semana por vir) é lida por _agenda_ler_dias_da_equipe ANTES da pergunta, do "não vou" e do "como foi": os dias ou "nenhum" (em qualquer ordem) gravam a semana presa e o padrão de quem tem (_agenda_equipe_dias_gravar, origem diarista; a exceção do dono no dia vence e volta em leitura.conflitos), a mensagem fica respondida e sai "Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!" / "… você não pode. Obrigado por avisar!"; "igual"/"ok" com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!"; não entendido com a pergunta por último (e a leitura geral não é pergunta, presença nem turnos; o "não vou" junto de um dia da semana também — "segunda não posso" nunca vira o "não vou" da ficha): 1ª vez "Não entendi os dias da semana de 16/11. Mande só os dias, assim: seg ter qui (ou "nenhum")." (chave agenda-equipe:resposta:<pessoa>:dias:<segunda>), 2ª vez a pergunta equipe_resposta ao dono e a mensagem respondida. {consumiu: true, tipo: dias, leitura, …}. A "última que o sistema começou" do resto não é mais a pergunta da semana. Fora disso, o de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 8): com modo_dias ligado, a pergunta da semana aberta só leva a resposta (os dias ou "nenhum") quando é a última mensagem mandada a ele, quando a frase fala da semana ou quando é só a lista dos dias e a leitura de sempre não a entende; com a ficha, a confirmação ou o "como foi" mandados depois, "não posso", "ok, sexta tô lá", "sim, todos prontos" e "terminei todos" seguem o caminho de antes (o "não vou", a confirmação, os turnos) e a pergunta da semana continua aberta.';

-- _agenda_linhas_do_fechamento (de 20261101100200_agenda_fase7b_pergunta_semanal.sql)
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
  -- FASE 7b: fim
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
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
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
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste.';

-- _agenda_carga_da_pessoa (de 20261101100300_agenda_fase7b_motor.sql)
create or replace function public._agenda_carga_da_pessoa(p_payee uuid)
 returns numeric
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c public.agenda_config := public._agenda_cfg();
  v numeric;
begin
  if p_payee is not null and p_payee = public._agenda_dono(null) then
    -- FASE 7b: (correção da revisão da 7b, achado 14) em teste (modo_dias sombra) o teto do dono é o de antes: com a linha do dono, a meia
    -- capacidade já em teste deixava o Lenine (o dono "sempre", 12 meios-dias de presença) como reserva acima da carga e mudava o plano.
    -- A meia capacidade vale com modo_dias ligado; antes de ligar, falta o dono dizer como a presença "sempre" (acompanhar) conta nela.
    if c.modo_dias = 'sombra' then
      v := public._agenda_aprendido('capacidade_dono', 'dono');
      return coalesce(least(v, c.carga_max), c.carga_max);
    end if;
    -- FASE 7b: fim
    -- FASE 7b: (7b P4, R4.5; AG7-02, confirmado no fio) com modo_dias fora de desligado, o dono vai até dono_carga_max (a meia
    -- capacidade que ele disse): o aprendido (capacidade_dono) só abaixa, a palavra dele é o teto. Desligado, o de antes.
    if c.modo_dias <> 'desligado' then
      return least(coalesce(public._agenda_aprendido('capacidade_dono', 'dono'), c.dono_carga_max), c.dono_carga_max);
    end if;
    -- FASE 7b: fim
    v := public._agenda_aprendido('capacidade_dono', 'dono');
    if v is not null then
      return least(v, c.carga_max);
    end if;
  end if;
  return c.carga_max;
end;
$function$;

comment on function public._agenda_carga_da_pessoa(uuid) is
  'Agenda de Produção (Fase 6, P4): a parte da semana de uma pessoa que o motor compromete — o dono com capacidade_dono em uso (_agenda_aprendido: só com modo_aprendizado ligado e capacidade_dono na lista) → o valor, nunca acima de carga_max; os outros (e o dono sem nada em uso) → carga_max. Lida pelo teto80 de _agenda_contexto e pela regra 6 de _agenda_validar_itens. FASE 7b (P4, R4.5; AG7-02): com modo_dias fora de desligado, o dono → least(coalesce(o aprendido capacidade_dono, dono_carga_max), dono_carga_max): a meia capacidade que ele disse é o teto (com a linha seg–sex, 5 meios-dias de turno por semana); o aprendido só abaixa. Desligado, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 14): com modo_dias em teste (sombra), o dono → o de antes (o aprendido até carga_max, ou carga_max); a meia capacidade (dono_carga_max) só com modo_dias ligado.';

-- agenda_desfazer (de 20261101100200_agenda_fase7b_pergunta_semanal.sql)
create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
  -- FASE 7: (7a P7) os ramos das ações do gestor (estimar, dupla, gestor) e quem saiu da equipe
  v_f7_pl    public.os_planejamento%rowtype;
  v_f7_txt   text;
  v_f7_acao  uuid;
  v_f7_sai   uuid[] := '{}';
  v_f7_fora  uuid[] := '{}';
  v_f7_ficam int := 0;
  v_f7_nomes text;
  -- FASE 7: fim
  -- FASE 7b: (7b P3) quem entrou na rotina da equipe sai
  v_7b_acao uuid;
  v_7b_txt  text;
  v_7b_nome text;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa da dupla
  v_7bc_ajud text;
  -- FASE 7b: fim
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3 (P4): a diária que a agenda lançou: apaga o turno que ela criou, se o acerto está aberto (_agenda_desfazer_diaria).
  if v_a.tipo = 'diaria' then
    return public._agenda_desfazer_diaria(v_a.id, p_autor, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 4: a mudança do material que o gestor fez sozinho (a previsão pela mensagem do fornecedor, a chegada pela nota
  -- importada): as linhas voltam como estavam, se ninguém mexeu nelas depois (_agenda_desfazer_material, 20261027100400).
  if v_a.tipo = 'material' then
    return public._agenda_desfazer_material(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 4: fim
  -- FASE 5: o que a resposta do cliente mudou (a confirmação, o pedido de dia, o acesso: a ação com depois.resposta_id) tem
  -- o desfazer dela (_agenda_desfazer_cliente, 20261028100400); a mensagem enviada não se desmanda; o acorde e a decisão do
  -- aviso crítico não mudaram nada na agenda.
  if v_a.origem = 'cliente' and v_a.tipo in ('fixar', 'cliente') and v_a.depois ? 'resposta_id' then
    return public._agenda_desfazer_cliente(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  if v_a.tipo = 'cliente' then
    return jsonb_build_object('ok', false,
      'texto', case when v_a.depois ? 'mensagem_id' then 'Mensagem enviada não se desmanda.'
                    else 'Isso foi um aviso para você: nada mudou na agenda para desfazer.' end);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) o que o aprendizado mudou (a troca que entrou sozinha e a decisão 1 ou 3 do dono) tem o desfazer dele: o
  -- valor de antes volta e a chave fica travada; a carga volta carga_max (_agenda_desfazer_aprendizado, 20261029100600).
  if v_a.tipo = 'aprendizado' then
    return public._agenda_desfazer_aprendizado(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7: (7a P7, spec R3 e §5.7) as ações do gestor que não são de alocação têm o ramo delas: estimar (os dias que o gestor
  -- gravou pelo prazo ou pela opção 1: os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação), dupla
  -- (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (*gestor, só propor* / *pode marcar*: gestor_so_propor e
  -- gestor_so_propor_em voltam). Só se nada mudou depois da ação (o que está gravado é o depois dela); senão a recusa diz o que
  -- mudou. reparar e reestimar são de alocação e seguem o caminho de sempre.
  if v_a.tipo in ('estimar', 'dupla', 'gestor') then
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', case when v_a.tipo = 'gestor' then 'Não dá mais para desfazer: passou o prazo. Diga *gestor, só propor* ou *gestor, pode marcar*.'
                      else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga.', v_nome) end);
    end if;
    if v_a.tipo = 'gestor' then
      if (select c.gestor_so_propor from public.agenda_config c where c.id)
         is distinct from (v_a.depois ->> 'gestor_so_propor')::boolean then
        return jsonb_build_object('ok', false,
          'texto', 'Não desfaço: depois disso você já mudou o gestor de novo. Diga *gestor, só propor* ou *gestor, pode marcar*.');
      end if;
      update public.agenda_config
         set gestor_so_propor = coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false),
             gestor_so_propor_em = (v_a.antes ->> 'gestor_so_propor_em')::timestamptz,
             atualizado_em = p_agora, atualizado_por = p_autor
       where id;
      v_f7_txt := case when coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false)
                       then 'Desfeito: voltei a só sugerir. *gestor, pode marcar* volta a marcar.'
                       else 'Desfeito: voltei a marcar sozinho; o que eu marcar vem no seu fechamento, com *desfaz*.' end;
    else
      select * into v_f7_pl from public.os_planejamento where service_order_id = v_os for update;
      if not found then
        return jsonb_build_object('ok', false, 'texto', format('Não achei o planejamento do %s: nada mudou.', v_nome));
      end if;
      if v_a.tipo = 'estimar' then
        if v_f7_pl.dias is distinct from (v_a.depois ->> 'dias')::numeric or v_f7_pl.estimativa_fonte is distinct from 'orcamento' then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso os dias do %s mudaram (%s). Para mudar de novo, me diga os dias.', v_nome,
                            coalesce(public._agenda_dias(v_f7_pl.dias), 'sem dias')));
        end if;
        update public.os_planejamento
           set dias = (v_a.antes ->> 'dias')::numeric, estimativa_fonte = v_a.antes ->> 'estimativa_fonte',
               estimativa_em = (v_a.antes ->> 'estimativa_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := case when v_a.antes ->> 'dias' is null
                         then format('Desfeito: o %s volta sem os dias que eu contei (%s). Me diga quantos dias são.',
                                     public._agenda_rotulo_da_os(v_os), public._agenda_dias((v_a.depois ->> 'dias')::numeric))
                         else format('Desfeito: o %s volta a %s, como estava.', public._agenda_rotulo_da_os(v_os),
                                     public._agenda_dias((v_a.antes ->> 'dias')::numeric)) end;
      else
        if v_f7_pl.dupla_dita is distinct from v_a.depois ->> 'dupla_dita'
           or v_f7_pl.dupla_meios is distinct from (v_a.depois ->> 'dupla_meios')::smallint then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso a dupla do %s mudou. Diga *%s com dupla* ou *%s sem dupla*.', v_nome, v_nome, v_nome));
        end if;
        update public.os_planejamento
           set dupla_dita = v_a.antes ->> 'dupla_dita', dupla_meios = (v_a.antes ->> 'dupla_meios')::smallint,
               dupla_motivo = v_a.antes ->> 'dupla_motivo', dupla_em = (v_a.antes ->> 'dupla_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_agora, 'autor', p_autor, 'por', 'dono', 'trecho', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := format('Desfeito: o %s volta %s.', public._agenda_rotulo_da_os(v_os),
                           case v_a.antes ->> 'dupla_dita'
                             when 'todos' then 'com dupla'
                             when 'nao' then 'sem dupla'
                             when 'inicio' then 'com dupla no início'
                             when 'fim' then 'com dupla no fim'
                             else 'ao normal: 1 pessoa, e dupla só quando você marcar' end);
      end if;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto,
                                     autor, desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
            v_a.os_ids, false, jsonb_build_object('acao', v_a.id), v_a.antes, left(v_f7_txt, 400), p_autor, v_a.id)
    returning id into v_f7_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_f7_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_f7_txt, 'acao_id', v_f7_acao, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, §5.2) a entrada na rotina da equipe — a ação equipe da regra d14 (vigia) ou do "1) Ponho" do dono (depois.motivo
  -- regra_d14 ou contato) — sai: recebe_rotina false e a linha parada ("desfeito pelo dono"); a regra não a põe de novo (a linha existe).
  if v_a.tipo = 'equipe' and v_a.depois ->> 'motivo' in ('regra_d14', 'contato') then
    v_7b_nome := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_a.payee_id), 'a pessoa');
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', format('Não dá mais para desfazer: passou o prazo. Se quiser tirar %s da rotina da equipe, me diga.', v_7b_nome));
    end if;
    update public.agenda_equipe_contato
       set recebe_rotina = false, parou_em = p_agora, parou_motivo = 'desfeito pelo dono'
     where payee_id = v_a.payee_id and parou_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'texto', format('%s já não está na rotina da equipe: nada mudou.', v_7b_nome));
    end if;
    v_7b_txt := format('Desfeito: %s sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias.', v_7b_nome);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, os_ids, critica, antes, depois, texto, autor,
                                     desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer',
            v_a.payee_id, '{}'::uuid[], false, jsonb_build_object('acao', v_a.id), jsonb_build_object('recebe_rotina', false),
            left(v_7b_txt, 400), p_autor, v_a.id)
    returning id into v_7b_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_7b_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao, 'recriadas', '[]'::jsonb,
                              'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7b: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    -- FASE 7b: (correção da revisão da 7b, achado 18) no serviço em que o gestor completou a dupla, a revisão encurtou o fim e outra OS
    -- ocupou o meio-dia que sobrou: a recusa (a regra de sempre: o *desfaz* nunca sobrepõe) diz como voltar — desfazer antes o que
    -- ocupou o lugar
    if v_os is not null and exists (select 1 from public.agenda_alocacoes a
                                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa') then
      v_7bc_ajud := public._agenda_lista(array(
                      select distinct public._agenda_nome_curto(py.name) from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa' order by 1));
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: o %s já está no %s %s. Com %s junto, o %s acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz %s* e depois *desfaz %s*.',
                        public._agenda_nome_curto(v_x.pessoa), coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'),
                        public._agenda_meio_texto(v_x.dia, v_x.turno), v_7bc_ajud, v_nome,
                        coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), v_nome));
    end if;
    -- FASE 7b: fim
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- FASE 7: (7a P7; fase7-padroes "medição de 30/10", item 4) o que a ação tirou e era de quem não está mais na equipe (a
  -- grade, agenda_capacidade, naquele dia) não volta: o *desfaz* restaura só o que cabe e diz o resto. Se tudo o que voltaria é
  -- de quem saiu e a ação não criou nada que ainda esteja de pé, nada muda (a recusa diz por quê): voltar o Lenine com João e
  -- Roberto, que saíram, faria a vigia remanejar de novo e mandar outro aviso com outro *desfaz*.
  select coalesce(array_agg(c.id) filter (where not g.na_grade), '{}'), coalesce(array_agg(distinct c.payee_id) filter (where not g.na_grade), '{}'),
         count(*) filter (where g.na_grade)
    into v_f7_sai, v_f7_fora, v_f7_ficam
    from public.agenda_alocacoes c
    cross join lateral (select exists (select 1 from public.agenda_capacidade(c.dia, c.dia, p_hoje) k
                                        where k.payee_id = c.payee_id) as na_grade) g
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora;
  if cardinality(v_f7_fora) > 0 then
    v_f7_nomes := public._agenda_lista(array(select public._agenda_nome_curto(py.name) from public.payees py
                                              where py.id = any (v_f7_fora) order by py.name, py.id), null);
  end if;
  if cardinality(v_f7_fora) > 0 and v_f7_ficam = 0
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')) then
    return jsonb_build_object('ok', false, 'status', 'saiu_da_equipe',
      'texto', format('Não dá para desfazer como estava: %s não %s mais na equipe, e era com %s que o %s estava. Nada mudou; ele volta à agenda com a equipe de agora.',
                      v_f7_nomes, case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                      case when cardinality(v_f7_fora) = 1 then 'ele' else 'eles' end, v_nome));
  end if;
  -- FASE 7: fim
  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    -- FASE 7: (7a P7) o meio-dia de quem saiu da equipe não volta
    continue when v_x.id = any (v_f7_sai);
    -- FASE 7: fim
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa que o gestor pôs na dupla (as alocações com o motivo
  -- dupla_completa) tira só ela: o serviço continua marcado — o texto de antes dizia que ele saía da agenda
  if cardinality(v_novas) = 0 and cardinality(v_canc) > 0 and v_os is not null and public._agenda_os_tem_dia(v_os, p_hoje)
     and not exists (select 1 from public.agenda_alocacoes a where a.id = any (v_canc) and not coalesce(a.motivos ? 'dupla_completa', false)) then
    v_txt := format('Desfeito: tirei %s do %s %s; o resto do serviço fica como estava.',
                    public._agenda_lista(array(select distinct public._agenda_nome_curto(py.name)
                                                 from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                                                where a.id = any (v_canc) order by 1)),
                    public._agenda_rotulo_da_os(v_os),
                    public._agenda_meios_frase((select jsonb_agg(jsonb_build_object('dia', a.dia, 'turno', a.turno) order by a.dia, a.turno)
                                                  from public.agenda_alocacoes a where a.id = any (v_canc))));
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P7) e diz o que não voltou
  if cardinality(v_f7_fora) > 0 then
    v_txt := v_txt || format(' %s não %s mais na equipe: os dias %s não voltam.', v_f7_nomes,
                             case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                             case when cardinality(v_f7_fora) = 1 then 'dele' else 'deles' end);
  end if;
  -- FASE 7: fim
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  -- FASE 3: o replano que a ausência da equipe causou ("não vou" ou o silêncio até as 9h): desfazer também tira a ausência
  -- daquele dia (senão a vigia replanejaria de novo no tique seguinte). "Se ele estiver lá, *desfaz Vanderlei*."
  update public.agenda_disponibilidade d set substituida_em = p_agora
   where d.substituida_em is null
     and d.id in (select (e.depois ->> 'disponibilidade')::uuid from public.agenda_acoes e
                   where e.tipo = 'equipe' and e.depois ->> 'disponibilidade' is not null
                     and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text);
  -- FASE 3: fim
  -- FASE 5: o replano que o pedido de dia do cliente causou, desfeito direto (sem a ação do cliente): o pedido sai junto (o
  -- bem indisponível e o "não antes de" voltam; senão a vigia replanejaria de novo no tique seguinte) e a ação do cliente
  -- fica desfeita. Quem desfaz pela ação do cliente (_agenda_desfazer_cliente) liga agenda.desfazer_cliente e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_cliente', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'cliente' and e.origem = 'cliente' and e.executada and e.desfeita_em is null
                  and e.depois ->> 'efeito' = 'replanejou'
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_cliente_restaurar_pedido(v_x.id, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 5: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita. Fase 6 (P6): a ação aprendizado vai a _agenda_desfazer_aprendizado (o em_uso de antes volta, nulo = o padrão, e a chave fica travada por aprender_trava_dias; a da carga volta carga_max). FASE 7 (7a P7, spec R3): as ações do gestor que não são de alocação têm o ramo delas — estimar (os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação: "Desfeito: o Nelson (OS-00112) volta sem os dias que eu contei (4 dias). Me diga quantos dias são."), dupla (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (gestor_so_propor e gestor_so_propor_em voltam), cada uma só se nada mudou depois dela (senão a recusa diz o que mudou), dentro do desfazivel_ate; reparar e reestimar seguem o caminho de alocação de sempre. E (a medição de 30/10, item 4) o que a ação tirou e era de quem não está mais na equipe naquele dia (agenda_capacidade) não volta: o desfazer restaura só o que cabe e diz o resto ("… João e Roberto não estão mais na equipe: os dias deles não voltam."); se tudo o que voltaria é de quem saiu e a ação não criou nada de pé, nada muda ({ok: false, status saiu_da_equipe}). FASE 7b (P3, §5.2): a ação equipe que pôs alguém na rotina da equipe — pela regra d14 (vigia, depois.motivo regra_d14) ou pelo "1) Ponho" do dono (depois.motivo contato) — se desfaz dentro do desfazivel_ate: a linha em agenda_equipe_contato fica parada (recebe_rotina false, parou_em, "desfeito pelo dono"; a regra não a põe de novo) e "Desfeito: Rafael sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias."; já fora da rotina = nada muda. CORREÇÃO DA REVISÃO DA 7b (achado 18): desfazer a ação que só pôs a 2ª pessoa na dupla (alocações com o motivo dupla_completa) diz "Desfeito: tirei Mateus do Lenine (OS-00074) em ter 10/11 (manhã e tarde); o resto do serviço fica como estava." (não "sai da agenda"); a recusa por sobreposição no serviço com a dupla completada acrescenta "Com Mateus junto, o Lenine acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz Tânia* e depois *desfaz Lenine*.".';

-- _agenda_gestor_dupla (de 20261101100500_agenda_fase7b_quem_chamar.sql)
create or replace function public._agenda_gestor_dupla(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_marc  text := public._agenda_gestor_modo('marcar');
  v_seco  boolean;
  v_dono  uuid := public._agenda_dono(null);
  v_cong  date;
  v_os    uuid;
  v_f     jsonb;
  v_d     jsonb;
  v_pront jsonb;
  v_novas jsonb;
  v_try   jsonb;
  v_item  jsonb;
  v_val   jsonb;
  v_tipo  text;
  v_fonte text;
  v_ult   date;
  v_ondes text[];
  v_frases text[];
  v_pede  text;
  v_cli   text;
  v_txt   text;
  v_pid   uuid;
  v_its   jsonb;
  v_exp   timestamptz;
  v_a     jsonb;
  v_usado jsonb := '[]'::jsonb;
  v_feitas jsonb := '[]'::jsonb;
  v_acoes jsonb := '[]'::jsonb;
  v_fp    text;
  v_fp0   text;
  v_ditas uuid[] := '{}';
  v_semtec int;
  v_r     jsonb;
  m       jsonb;
  c       record;
  -- FASE 7b: (correção da revisão da 7b, achado 4) a revisão do dia seguinte pode cortar o fim do serviço?
  v_7bc_cort boolean;
  -- FASE 7b: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_dupla: sem o dia ou a hora' using errcode = '22004';
  end if;
  if cf.modo_dupla = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'dupla desligada');
  end if;
  if v_marc = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor desligado');
  end if;
  v_seco := cf.modo_dupla <> 'ligado' or v_marc <> 'ligado' or cf.modo_proposta <> 'ligado';
  perform set_config('agenda.hoje', p_hoje::text, true);
  if not v_seco then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- (i) a 2ª pessoa na dupla pela tarefa que foi com 1: em cada meio-dia de _agenda_dupla_faltando fora da zona travada, depois do
  -- congelado e que ainda não começou, a 1ª pessoa livre que não é o dono — primeiro quem o dono disse para aquela data, depois quem
  -- tem dias fixos —, sem outra coisa no meio-dia, validada pelas 14 regras (o teto) junto das outras já aceitas da OS. Nunca sozinha
  -- (o meio-dia já tem quem vai); nunca move o que já está.
  for v_os in select distinct a.service_order_id from public.agenda_alocacoes a
               where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno' and a.dia >= p_hoje
               order by 1 loop
    v_f := public._agenda_dupla_faltando(v_os, p_hoje);
    continue when jsonb_array_length(v_f) = 0;
    v_pront := public.os_prontidao(v_os, p_hoje);
    select min(a.tipo), min(a.duracao_fonte), max(a.dia) into v_tipo, v_fonte, v_ult
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
    -- FASE 7b: (correção da revisão da 7b, achado 4) acima da carga (sem o teto da equipe-semana) só quando a revisão do dia seguinte pode
    -- cortar o fim: o último dia do serviço depois do congelado e sem ficha à equipe nem aviso ao cliente nele (_agenda_dia_avisado de
    -- quem está nele). Senão a semana
    -- ficaria acima do teto até alguém mexer: a 2ª pessoa só entra dentro do teto (as 14 regras sem acima_da_carga).
    v_7bc_cort := v_ult > v_cong
                  and not exists (select 1 from public.agenda_alocacoes a
                                   where a.service_order_id = v_os and a.dia = v_ult and a.estado in ('publicada', 'fixada')
                                     and a.tipo <> 'reserva' and public._agenda_dia_avisado(a.payee_id, v_os, v_ult) is not null);
    -- FASE 7b: fim
    v_novas := '[]'::jsonb;
    for m in select e from jsonb_array_elements(v_f) e
              where not coalesce((e ->> 'travado')::boolean, false) and (e ->> 'dia')::date > v_cong
                and lower(public.agenda_periodo((e ->> 'dia')::date, e ->> 'turno', 'turno')) > p_agora
              order by (e ->> 'dia')::date, e ->> 'turno' loop
      for c in
        select k.payee_id, public._agenda_nome_curto(k.pessoa) as nome
          from public.agenda_capacidade((m ->> 'dia')::date, (m ->> 'dia')::date, p_hoje) k
         where k.turno = m ->> 'turno' and k.situacao = 'livre' and not k.eh_dono and k.payee_id is distinct from v_dono
           and not (to_jsonb(k.payee_id::text) <@ coalesce(m -> 'pessoas', '[]'::jsonb))
           and not exists (select 1 from public.agenda_alocacoes x
                            where x.payee_id = k.payee_id and x.estado in ('publicada', 'fixada')
                              and x.periodo && public.agenda_periodo((m ->> 'dia')::date, m ->> 'turno', 'turno'))
           and not exists (select 1 from jsonb_array_elements(v_usado) u
                            where u ->> 'payee_id' = k.payee_id::text and u ->> 'dia' = m ->> 'dia' and u ->> 'turno' = m ->> 'turno')
           and (exists (select 1 from public.agenda_disponibilidade d
                         where d.payee_id = k.payee_id and d.substituida_em is null and d.origem = 'dono' and d.periodo is not null
                           and d.periodo @> (m ->> 'dia')::date and d.situacao in ('disponivel', 'confirmada')
                           and (d.turno is null or d.turno = m ->> 'turno'))
                or not public._agenda_e_sob_demanda(k.payee_id, p_hoje))
         order by exists (select 1 from public.agenda_disponibilidade d
                           where d.payee_id = k.payee_id and d.substituida_em is null and d.origem = 'dono' and d.periodo is not null
                             and d.periodo @> (m ->> 'dia')::date and d.situacao in ('disponivel', 'confirmada')
                             and (d.turno is null or d.turno = m ->> 'turno')) desc,
                  k.pessoa, k.payee_id
      loop
        v_try := v_novas || jsonb_build_object('payee_id', c.payee_id, 'nome', c.nome, 'dia', m -> 'dia', 'turno', m -> 'turno',
                                               'presenca', 'turno');
        v_item := jsonb_build_object(
          'op', 'criar', 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
          'tipo', v_tipo, 'reserva_de', null, 'alocacoes', v_try,
          'de', (select min(e ->> 'dia') from jsonb_array_elements(v_try) e), 'ate', (select max(e ->> 'dia') from jsonb_array_elements(v_try) e),
          'fim_antes', v_ult, 'fim_depois', v_ult, 'atraso_du', null, 'condicao_tipo', null, 'critica', null, 'pergunta_chave', null,
          'decisao', null, 'espera', false, 'interrupcoes', 0, 'meios_do_dono', 0, 'fonte', v_fonte, 'dias', v_pront -> 'dias',
          'evento_real', false, 'fixar_dono', false, 'aviso_material', null, 'abre', false, 'fecha', false,
          'motivos', jsonb_build_array('dupla_completa'), 'texto', null, 'aplicado', false);
        -- acima da carga: o teto de 100% da pessoa e sem o teto da equipe-semana da 7a — o bloco de 1 pessoa já ocupa a semana do
        -- técnico, e a dupla acrescenta o que a revisão do dia seguinte corta no fim (as mesmas diárias-pessoa); sem isso, a dupla
        -- nunca se completaria na semana cheia
        v_val := public._agenda_validar_itens(jsonb_build_array(v_item),
                                              jsonb_build_object('p_restricoes', jsonb_build_object('acima_da_carga', true)), p_hoje, p_agora,
                                              false, jsonb_build_object(v_os::text, v_pront));
        -- FASE 7b: (correção da revisão da 7b, achado 4) sem o corte possível, dentro do teto
        if not v_7bc_cort then
          v_val := public._agenda_validar_itens(jsonb_build_array(v_item), jsonb_build_object('p_restricoes', '{}'::jsonb), p_hoje, p_agora,
                                                false, jsonb_build_object(v_os::text, v_pront));
        end if;
        -- FASE 7b: fim
        if jsonb_array_length(v_val) = 0 then
          v_novas := v_try;
          v_usado := v_usado || jsonb_build_object('payee_id', c.payee_id, 'dia', m -> 'dia', 'turno', m -> 'turno');
          exit;
        end if;
      end loop;
    end loop;
    continue when jsonb_array_length(v_novas) = 0;
    -- a frase (spec R4.4 item 4): "Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2
    -- pessoas. *desfaz Lenine* volta."
    v_d := public._agenda_dupla_da_os(v_os);
    v_ondes := array(select distinct e ->> 'onde' from jsonb_array_elements(v_f) e
                      where exists (select 1 from jsonb_array_elements(v_novas) n where n ->> 'dia' = e ->> 'dia' and n ->> 'turno' = e ->> 'turno'));
    v_frases := array(select distinct on (q ->> 'motivo') q ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) q
                       where q ->> 'onde' = any (v_ondes) and q ->> 'onde' <> 'todos' order by q ->> 'motivo');
    v_pede := case when 'todos' = any (v_ondes)
                   then format('o serviço todo pede 2 pessoas (%s)', (select q ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) q
                                                                        where q ->> 'onde' = 'todos' limit 1))
                   else format('%s %s 2 pessoas', public._agenda_lista(v_frases), case when cardinality(v_frases) > 1 then 'pedem' else 'pede' end) end;
    v_cli := coalesce(v_pront ->> 'cliente_curto', v_pront ->> 'numero');
    v_txt := format('Pus %s com %s no %s %s: %s. *desfaz %s* volta.',
                    public._agenda_lista(array(select z.n from (select n ->> 'nome' as n, min(o) as o from jsonb_array_elements(v_novas) with ordinality t(n, o)
                                                                group by 1) z order by z.o)),
                    coalesce(nullif(public._agenda_lista(array(
                      select distinct case when p::uuid is not distinct from v_dono then 'você' else public._agenda_nome_curto(py.name) end
                        from jsonb_array_elements(v_f) e cross join lateral jsonb_array_elements_text(coalesce(e -> 'pessoas', '[]'::jsonb)) p
                        join public.payees py on py.id = p::uuid
                       where exists (select 1 from jsonb_array_elements(v_novas) n where n ->> 'dia' = e ->> 'dia' and n ->> 'turno' = e ->> 'turno')
                       order by 1)), ''), 'quem vai'),
                    v_cli, public._agenda_meios_frase(v_novas), v_pede, v_cli);
    if v_seco then
      v_feitas := v_feitas || jsonb_build_object('os', v_os, 'numero', v_pront ->> 'numero', 'alocacoes', v_novas, 'texto', v_txt);
      continue;
    end if;
    -- a proposta só com as alocações novas, validada e aplicada por agenda_aplicar (o molde de _agenda_gestor_reparar): a ação
    -- reparar, desfazível; a marca dupla_completa na proposta e nas alocações
    v_its := jsonb_build_array(v_item - 'alocacoes' || jsonb_build_object(
               'alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                               from jsonb_array_elements(v_novas) with ordinality u(a, j)),
               'de', (select min(e ->> 'dia') from jsonb_array_elements(v_novas) e), 'ate', (select max(e ->> 'dia') from jsonb_array_elements(v_novas) e),
               'texto', v_txt));
    v_pid := gen_random_uuid();
    v_exp := least(p_agora + cf.proposta_validade,
                   coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', 'turno')))
                               from jsonb_array_elements(v_novas) a), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, 'replano',
            daterange((select min((e ->> 'dia')::date) from jsonb_array_elements(v_novas) e),
                      (select max((e ->> 'dia')::date) from jsonb_array_elements(v_novas) e), '[]'),
            array[v_os], cf.versao_plano, 'ligado', 'aberta', v_its, '[]'::jsonb, '{}'::jsonb,
            jsonb_build_object('titulo', 'Mudanças na agenda', 'linhas', jsonb_build_array(v_txt), 'fora', '[]'::jsonb, 'resumo', v_txt),
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', null, 'p_ate', null, 'p_os', jsonb_build_array(v_os),
                               'p_restricoes', jsonb_build_object('acima_da_carga', true), 'escopo', 'replano', 'origem', 'vigia',
                               'gestor', jsonb_build_object('tipo', 'reparar', 'motivo', 'dupla_completa',
                                                            'textos', jsonb_build_object(v_os::text, v_txt))),
            null, 'vigia', null, p_agora, v_exp);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         duracao_fonte, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, v_os, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno', 'turno', v_tipo,
           'proposta', 'motor', v_pid, v_fonte, jsonb_build_array('dupla_completa'), p_agora
      from jsonb_array_elements(v_its -> 0 -> 'alocacoes') with ordinality u(a, j)
     order by j;
    v_a := public.agenda_aplicar(v_pid, null, 'vigia', null, null, p_hoje, p_agora);
    if not coalesce((v_a ->> 'ok')::boolean, false) then
      perform public.agenda_descartar(v_pid, null, 'a dupla não passou no aplicar');
      perform public.log_app_error('db', 'agenda: a 2ª pessoa da dupla não aplicou: ' || coalesce(v_a ->> 'texto', '?'),
                                   'agenda', 'gestor:dupla', 'warn',
                                   jsonb_build_object('os', v_os, 'proposta', v_pid, 'violacoes', v_a -> 'violacoes',
                                                      'p_hoje', p_hoje, 'p_agora', p_agora));
      continue;
    end if;
    v_feitas := v_feitas || jsonb_build_object('os', v_os, 'numero', v_pront ->> 'numero', 'alocacoes', v_novas, 'texto', v_txt,
                                               'proposta_id', v_pid);
    v_acoes := v_acoes || coalesce(v_a -> 'acoes', '[]'::jsonb);
  end loop;

  -- (ii) a dupla dita (sem compromisso) que esperava a 2ª pessoa e agora a tem pela régua dos técnicos só por quem vem sob demanda (a
  -- classe não é mais a 4 dupla, mas os de dias fixos não bastam: o dupla_sd do P4, R4.3(c)): a montagem dela (_agenda_propor_e_aplicar,
  -- a vigia; a onda K vale). Só quando os dias de alguém mudaram desde o tique que fez isso por último (fp: as linhas de disponibilidade
  -- vivas) — a dita que continua sem bloco (o fora dupla do R4.3(c)) não vira uma proposta nova a cada tique.
  v_fp := md5(coalesce((select string_agg(d.id::text, ',' order by d.id) from public.agenda_disponibilidade d
                         where d.substituida_em is null and d.payee_id is distinct from v_dono), ''));
  select r.contagens #>> '{dupla,fp}' into v_fp0
    from public.agenda_vigia_rodadas r
   where r.rotina = 'gestor' and r.p_agora <= p_agora and jsonb_typeof(r.contagens -> 'dupla') = 'object' and (r.contagens -> 'dupla') ? 'fp'
   order by r.p_agora desc, r.rodou_em desc limit 1;
  if v_seco or v_fp is distinct from v_fp0 then
    v_semtec := (select count(*)::int from jsonb_array_elements(coalesce(public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) q
                  where not coalesce((q ->> 'eh_dono')::boolean, false));
    v_ditas := array(
      select z.os from (
        select k.service_order_id as os, k.numero, mm.v as m, public._agenda_classe_agora(k.service_order_id, p_hoje) as cl
          from public.os_carteira(p_hoje) k
          join public.os_planejamento pl on pl.service_order_id = k.service_order_id
          cross join lateral (select public.agenda_meios_da_os(k.service_order_id, p_hoje) as v) mm
         where pl.dupla_dita in ('todos', 'inicio', 'fim') and not public._agenda_os_tem_dia(k.service_order_id, p_hoje)) z
       where not coalesce((z.m ->> 'equipe_dita')::boolean, false)
         and not (z.cl ->> 'classe' = '4' and z.cl ->> 'motivo' = 'dupla')
         and v_semtec < greatest(coalesce((z.m #>> '{por_turno,manha,desejado}')::int, 0), coalesce((z.m #>> '{por_turno,tarde,desejado}')::int, 0),
                                 coalesce((select max(dd::int) from jsonb_array_elements_text(coalesce(z.m -> 'dk', '[]'::jsonb)) dd), 0)
                                 - case when coalesce((z.m ->> 'dk_dono_conta')::boolean, true)
                                             and (coalesce((z.m #>> '{dono_turno,manha}')::boolean, false)
                                                  or coalesce((z.m #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end)
       order by z.numero, z.os);
    if not v_seco and cardinality(v_ditas) > 0 then
      v_r := public._agenda_propor_e_aplicar('os', v_ditas, 'vigia', null, p_hoje, p_agora);
      v_acoes := v_acoes || coalesce(v_r -> 'acoes', '[]'::jsonb);
    end if;
  end if;

  if v_seco then
    return jsonb_build_object('pulado', true, 'motivo', 'em teste', 'em_teste', true,
                              'completaria', v_feitas, 'ditas', to_jsonb(v_ditas));
  end if;
  return jsonb_build_object('completadas', jsonb_array_length(v_feitas), 'os', v_feitas, 'acoes', v_acoes,
                            'ditas', to_jsonb(v_ditas),
                            'marcou', case when v_r is not null then jsonb_build_object('ok', v_r -> 'ok', 'texto', v_r -> 'texto',
                                                                                         'fora', v_r -> 'fora') end,
                            'fp', v_fp);
end;
$function$;

comment on function public._agenda_gestor_dupla(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P6; R4.4 item 4, R4.9-5): o passo de todo tique dupla da rodada do gestor (barato: só as OS com dupla). modo_dupla desligado ou o gestor que marca desligado = {pulado}. (i) A 2ª pessoa na dupla pela tarefa que foi com 1: em cada meio-dia de _agenda_dupla_faltando fora da zona travada, depois do congelado e que ainda não começou, a 1ª pessoa livre que não é o dono (primeiro quem o dono disse para aquela data, depois quem tem dias fixos), sem outra coisa no meio-dia, validada pelas 14 regras com as outras já aceitas da OS e acima da carga (o teto de 100% da pessoa, sem o teto da equipe-semana: a revisão do dia seguinte corta o que a dupla encurta); nunca sozinha, nunca move o que já está. Uma proposta por OS (escopo replano, criada_por vigia, modo ligado; parametros.gestor {tipo reparar, motivo dupla_completa, textos}) só com as alocações novas (motivos [dupla_completa]), aplicada por agenda_aplicar: a ação reparar, desfazível — "Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas. *desfaz Lenine* volta." Não passou no aplicar = descartada, app_error_logs gestor:dupla (warn). (ii) A dupla dita (sem compromisso) que esperava a 2ª pessoa e agora a tem pela régua dos técnicos só por quem vem sob demanda (a classe deixou de ser a 4 dupla, e os de dias fixos não bastam: o dupla_sd do P4): _agenda_propor_e_aplicar(os, …, vigia) — a onda K vale; só quando as linhas de disponibilidade vivas mudaram desde o tique que fez isso por último (fp na contagem da rodada). Em teste (modo_dupla ou o gestor em sombra, ou a agenda automática fora de ligado): {pulado, em_teste, completaria, ditas}, nada gravado. {completadas, os, acoes, ditas, marcou, fp}. VOLATILE, invoker, sem grant (só a rodada do gestor o chama). CORREÇÃO DA REVISÃO DA 7b (achado 4): acima da carga (o teto de 100% da pessoa, sem o teto da equipe-semana) só quando a revisão do dia seguinte pode cortar o fim — o último dia do serviço depois do congelado e sem ficha ou aviso ao cliente (_agenda_dia_avisado); senão a 2ª pessoa é validada e aplicada dentro do teto (sem acima_da_carga), e na semana cheia a dupla fica sem a 2ª pessoa (o foco e o cartão dizem).';

-- _agenda_contexto (de 20261101100300_agenda_fase7b_motor.sql)
create or replace function public._agenda_contexto(p_d_ini date, p_d_fim date, p_hoje date,
                                                   p_ignorar uuid[] default '{}'::uuid[], p_fila uuid[] default '{}'::uuid[])
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_nd    int;
  v_nh    int;
  v_seg   date;
  v_nw    int;
  v_g     jsonb;
  v_pes   uuid[];
  v_nomes text[];
  v_np    int;
  v_dono  int := 0;
  v_oss   uuid[] := coalesce(p_fila, '{}'::uuid[]);
  v_cap   int[];
  v_esp   numeric[];
  v_curta int[];
  v_ocup  int[];
  v_fr    int[];
  v_util  boolean[];
  v_sem   int[];
  v_espw  numeric[];
  v_t80   int[];
  v_t100  int[];
  v_uc    int[];
  v_ur    int[];
  v_loc   int[];
  v_padrao boolean;
  r       record;
  v_h     int;
  v_cel   int;
  v_mark  int;
  v_w     int;
  v_k     int;
  s       int;
  v_achou boolean;
  -- FASE 6: a carga de cada pessoa no teto de compromisso (o índice da pessoa e da semana; v_pp/v_ww: pp e ww são nomes de
  -- coluna da consulta do teto)
  v_pp    int;
  v_ww    int;
  v_carga numeric;
  -- FASE 6: fim
  -- FASE 7: (7a P5) o teto da equipe-semana (a regra teto_equipe do gestor) e o gancho do sábado (a variável agenda.sabado)
  v_f7_teq  boolean := public._agenda_gestor_regra('teto_equipe');
  v_f7_te   int[];
  v_f7_soma numeric;
  v_f7_sab  boolean;
  v_f7_cel  int;
  v_f7_quem int[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4) o sábado da 7b (os índices dos sábados e a manhã livre de cada pessoa por semana), quem nunca fica sozinho, o
  -- dono técnico e o gancho da pessoa a mais (R4.4)
  v_7b_extra jsonb := '{}'::jsonb;
  v_7b_sab   int[];
  v_7b_bon   int[];
  v_7b_nov   int[];
  v_7b_d     int;
  v_7b_p     int;
  v_7b_util  boolean[];
  v_7b_cap   int[];
  -- FASE 7b: fim
begin
  if p_d_ini is null or p_d_fim is null or p_d_fim < p_d_ini then
    raise exception 'agenda: período inválido para a grade (% a %)', p_d_ini, p_d_fim using errcode = '22023';
  end if;
  v_nd := p_d_fim - p_d_ini + 1;
  v_nh := 2 * v_nd;
  v_seg := p_d_ini - (extract(isodow from p_d_ini)::int - 1);
  v_nw := (p_d_fim - v_seg) / 7 + 1;

  select coalesce(jsonb_agg(to_jsonb(g) order by g.eh_dono desc, g.nome, g.payee_id, g.dia, g.turno = 'tarde'), '[]'::jsonb)
    into v_g
    from public.agenda_grade(p_d_ini, p_d_fim, p_hoje, coalesce(p_ignorar, '{}'::uuid[])) g;

  -- As pessoas: você primeiro, depois a equipe pelo nome (a ordem da grade).
  select coalesce(array_agg(q.payee_id order by q.eh_dono desc, q.nome, q.payee_id), '{}'::uuid[]),
         coalesce(array_agg(q.nome order by q.eh_dono desc, q.nome, q.payee_id), '{}'::text[]),
         coalesce(bool_or(q.eh_dono), false)
    into v_pes, v_nomes, v_padrao
    from (select distinct (e ->> 'payee_id')::uuid as payee_id, e ->> 'nome' as nome, (e ->> 'eh_dono')::boolean as eh_dono
            from jsonb_array_elements(v_g) e) q;
  v_np := cardinality(v_pes);
  if v_padrao then v_dono := 1; end if;

  -- O esperado só conta dia útil: o sábado combinado ("o Roberto vem sábado") a agenda automática não marca, e contá-lo
  -- subiria o teto dos dias úteis (10 meios + 2 do sábado = teto de 9, 90% da semana útil).
  select coalesce(array_agg(case when e ->> 'situacao' = 'livre' then 1 else 0 end order by o), '{}'::int[]),
         coalesce(array_agg(case when public.agenda_dia_util((e ->> 'dia')::date) then (e ->> 'meios_esperados')::numeric else 0 end
                            order by o), '{}'::numeric[])
    into v_cap, v_esp
    from jsonb_array_elements(v_g) with ordinality t(e, o);
  if coalesce(cardinality(v_cap), 0) <> v_np * v_nh then
    raise exception 'agenda: a grade veio incompleta (% células para % pessoas × % meios-dias)', cardinality(v_cap), v_np, v_nh;
  end if;
  -- FASE 7b: (7b P4, R4.4: o gancho do P6, inerte sem a variável) com agenda.pessoa_extra = tecnico — só _agenda_quem_chamar a liga,
  -- dentro da conta e sem gravar —, uma pessoa que não existe (_agenda_pessoa_extra_id, "mais uma pessoa") entra por último: livre
  -- nas manhãs e tardes de todo dia útil da grade (sem feriado nem recesso), não novato, não sob demanda, não o dono, com o teto de
  -- carga_max (_agenda_carga_da_pessoa) e contada no teto da equipe do 7a. Sem a variável, nada muda.
  if coalesce(current_setting('agenda.pessoa_extra', true), '') = 'tecnico' then
    v_pes := v_pes || public._agenda_pessoa_extra_id();
    v_nomes := v_nomes || 'mais uma pessoa'::text;
    v_np := v_np + 1;
    select v_cap || array_agg(case when public.agenda_dia_util(p_d_ini + (h - 1) / 2) then 1 else 0 end order by h),
           v_esp || array_agg(case when public.agenda_dia_util(p_d_ini + (h - 1) / 2) then 1::numeric else 0::numeric end order by h)
      into v_cap, v_esp
      from generate_series(1, v_nh) h;
  end if;
  -- FASE 7b: fim

  -- As pontas livres do dono: bit 1 = abertura, bit 2 = fechamento.
  v_curta := array_fill(0, array[v_nh]);
  if v_dono > 0 then
    select array_agg((case when e -> 'curta_livre' ? 'abertura' then 1 else 0 end)
                     + (case when e -> 'curta_livre' ? 'fechamento' then 2 else 0 end) order by o)
      into v_curta
      from jsonb_array_elements(v_g) with ordinality t(e, o)
     where o <= v_nh;
  end if;
  v_padrao := v_dono > 0 and exists (select 1 from jsonb_array_elements(v_g) with ordinality t(e, o)
                                      where o <= v_nh and e ->> 'situacao' = 'livre');

  -- As OS: as da fila primeiro (o índice delas é a posição), depois as que já ocupam a grade.
  v_oss := v_oss || coalesce(array(
    select distinct a.service_order_id from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia between p_d_ini and p_d_fim
       and not (a.id = any (coalesce(p_ignorar, '{}'::uuid[]))) and not (a.service_order_id = any (v_oss))
     order by 1), '{}'::uuid[]);

  -- O que o plano vigente já ocupa: célula, frentes e uso da semana (compromisso e reserva).
  v_ocup := array_fill(0, array[greatest(v_np * v_nh, 1)]);
  v_fr := array_fill(0, array[v_nh * 4]);
  v_uc := array_fill(0, array[greatest(v_np * v_nw, 1)]);
  v_ur := array_fill(0, array[greatest(v_np * v_nw, 1)]);
  for r in
    select a.dia, a.turno, a.presenca, a.tipo, array_position(v_pes, a.payee_id) as pi,
           array_position(v_oss, a.service_order_id) as oi
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia between p_d_ini and p_d_fim
       and not (a.id = any (coalesce(p_ignorar, '{}'::uuid[])))
     order by a.dia, a.turno = 'tarde', a.service_order_id, a.payee_id, a.id
  loop
    v_h := 2 * (r.dia - p_d_ini) + case when r.turno = 'tarde' then 2 else 1 end;
    v_mark := case when r.tipo = 'reserva' then -r.oi else r.oi end;
    if r.pi is not null then
      v_cel := (r.pi - 1) * v_nh + v_h;
      if v_ocup[v_cel] = 0 or (v_ocup[v_cel] < 0 and v_mark > 0) then v_ocup[v_cel] := v_mark; end if;
      if r.presenca = 'turno' then
        v_w := (r.dia - v_seg) / 7 + 1;
        v_k := (r.pi - 1) * v_nw + v_w;
        if r.tipo = 'reserva' then v_ur[v_k] := v_ur[v_k] + 1; else v_uc[v_k] := v_uc[v_k] + 1; end if;
      end if;
    end if;
    v_achou := false;
    for s in 1 .. 4 loop
      v_k := (v_h - 1) * 4 + s;
      if abs(v_fr[v_k]) = r.oi then
        if v_fr[v_k] < 0 and v_mark > 0 then v_fr[v_k] := v_mark; end if;
        v_achou := true;
        exit;
      end if;
    end loop;
    if not v_achou then
      for s in 1 .. 4 loop
        v_k := (v_h - 1) * 4 + s;
        if v_fr[v_k] = 0 then v_fr[v_k] := v_mark; exit; end if;
      end loop;
    end if;
  end loop;

  select array_agg(public.agenda_dia_util(p_d_ini + g) order by g), array_agg(((p_d_ini + g) - v_seg) / 7 + 1 order by g)
    into v_util, v_sem
    from generate_series(0, v_nd - 1) g;
  -- FASE 7b: (7b P4, §R2) o gancho do sábado do 7a (a pergunta crítica sabado, logo abaixo) só vale com modo_sabado desligado:
  -- com sombra ou ligado vale o sábado desta etapa (sab e sab_bonus: a manhã de quem se ofereceu). A grade de antes do gancho fica
  -- guardada e volta logo depois dele.
  v_7b_util := v_util;
  v_7b_cap := v_cap;
  -- FASE 7b: fim
  -- FASE 7: (7a P5) o gancho do sábado (AG7-08; spec-fase7a §5.5 e d9). Só com a variável agenda.sabado = 'on' — quem a liga
  -- é a decisão da pergunta crítica sabado (P12), dentro da transação, e a desliga em seguida — e com sabado_manha diferente de
  -- 'nunca': a manhã de cada sábado do período que ainda não é útil (sabado_util desligado) e não é feriado vira útil, com
  -- lugar só para quem tem o padrão de sábado de manhã (linha vigente de agenda_disponibilidade com dias_semana contendo o
  -- sábado, de manhã ou o dia todo, vem) e não tem exceção nem recesso que tire aquele dia (a grade já diz 'indisponivel'); a
  -- tarde fica sem ninguém. O sábado em que ninguém pode vir não muda (útil e vazio, ele contaria como dia parado de todo
  -- serviço que o atravessa). O sábado não entra no esperado: o teto da semana não sobe (o esperado já foi lido acima, só de
  -- dia útil). Sem a variável, nada muda.
  v_f7_sab := coalesce(current_setting('agenda.sabado', true), '') = 'on' and cf.sabado_manha <> 'nunca';
  if v_f7_sab then
    for f7_d in 1 .. v_nd loop
      continue when extract(isodow from p_d_ini + f7_d - 1)::int <> 6 or v_util[f7_d]
                    or public.agenda_feriado(p_d_ini + f7_d - 1) is not null;
      -- quem vem nessa manhã: o padrão de sábado, sem exceção nem recesso no dia (a célula da manhã na grade é a
      -- (pessoa − 1) × nh + 2 × (dia − 1) + 1; o jsonb conta de 0)
      v_f7_quem := array(select g.p from generate_series(1, coalesce(v_np, 0)) g(p)
                          where (v_g -> ((g.p - 1) * v_nh + 2 * (f7_d - 1)) ->> 'situacao') is distinct from 'indisponivel'
                            and exists (select 1 from public.agenda_disponibilidade d
                                         where d.payee_id = v_pes[g.p] and d.substituida_em is null
                                           and d.dias_semana @> array[6]::smallint[]
                                           and d.situacao in ('disponivel', 'confirmada')
                                           and (d.turno is null or d.turno = 'manha'))
                          order by g.p);
      continue when cardinality(v_f7_quem) = 0;
      v_util[f7_d] := true;
      for f7_p in 1 .. coalesce(v_np, 0) loop
        v_f7_cel := (f7_p - 1) * v_nh + 2 * (f7_d - 1) + 1;   -- a manhã de f7_p nesse sábado (a tarde é a célula seguinte)
        v_cap[v_f7_cel] := case when f7_p = any (v_f7_quem) then 1 else 0 end;
        v_cap[v_f7_cel + 1] := 0;
      end loop;
    end loop;
  end if;
  -- FASE 7: fim
  -- FASE 7b: (correção da revisão da 7b, achado 12) em teste (modo_sabado sombra) o gancho do sábado do 7a continua valendo: a pergunta
  -- crítica sabado da 7a ligada acha o sábado (antes, o modo em teste a desligava sem pôr nada visível no lugar). A grade guardada passa a
  -- ser a de depois dele, e a volta logo abaixo não muda nada. Só ligado o sábado é só o desta etapa.
  if cf.modo_sabado = 'sombra' then
    v_7b_util := v_util;
    v_7b_cap := v_cap;
  end if;
  -- FASE 7b: fim
  -- FASE 7b: (7b P4, §R2) com modo_sabado fora de desligado, o gancho do sábado do 7a não vale: a grade volta à de antes dele
  if cf.modo_sabado <> 'desligado' then
    v_util := v_7b_util;
    v_cap := v_7b_cap;
  end if;
  -- FASE 7b: fim

  -- O esperado de cada pessoa por semana ISO e os dois tetos: compromisso (carga_max) e compromisso + reserva (100%).
  with cel as (
    select (u.o - 1) / v_nh + 1 as p, ((u.o - 1) % v_nh) / 2 + 1 as d, u.x as esp
      from unnest(v_esp) with ordinality u(x, o)
  ),
  soma as (select cel.p, (v_sem)[cel.d] as w, sum(cel.esp) as e from cel group by 1, 2)
  select coalesce(array_agg(coalesce(soma.e, 0) order by pp, ww), '{}'::numeric[]),
         coalesce(array_agg(floor(cf.carga_max * coalesce(soma.e, 0))::int order by pp, ww), '{}'::int[]),
         coalesce(array_agg(floor(coalesce(soma.e, 0))::int order by pp, ww), '{}'::int[])
    into v_espw, v_t80, v_t100
    from generate_series(1, greatest(v_np, 1)) pp
    cross join generate_series(1, v_nw) ww
    left join soma on soma.p = pp and soma.w = ww
   where v_np > 0;
  -- FASE 6: (P4) a carga de cada pessoa (spec-fase6 §5.4): o teto de compromisso da semana é floor(carga × esperado), com a
  -- carga de _agenda_carga_da_pessoa (o dono com capacidade_dono em uso; os outros, e o dono sem nada em uso, carga_max). A
  -- pessoa pp é v_pes[pp] (a mesma ordem da grade: você primeiro) e a célula dela na semana ww é (pp − 1) × nw + ww — a
  -- ordem "order by pp, ww" do array_agg de cima, a mesma de esperado. Só a pessoa com outra carga muda; com o modo fora de
  -- ligado (ou sem o item na lista, ou nada em uso), nada muda: a saída é a de antes, byte a byte.
  for v_pp in 1 .. coalesce(v_np, 0) loop
    v_carga := public._agenda_carga_da_pessoa(v_pes[v_pp]);
    continue when v_carga = cf.carga_max;
    for v_ww in 1 .. v_nw loop
      v_t80[(v_pp - 1) * v_nw + v_ww] := floor(v_carga * v_espw[(v_pp - 1) * v_nw + v_ww])::int;
    end loop;
  end loop;
  -- FASE 6: fim

  -- FASE 7: (7a P5) o teto da equipe-semana (a regra teto_equipe; spec-fase7a §5.5 e d8). Com o portão, cada pessoa da equipe
  -- (todas menos o dono) pode chegar a 100% do que se espera dela na semana (o teto de compromisso vira o de 100%: teto80 =
  -- teto100), e a equipe inteira, a floor(carga_max × a soma do esperado dela) — arredonda uma vez, na soma, e não pessoa a
  -- pessoa (João 4,25 e Roberto 2 esperados: por pessoa 3 + 1 = 4; a equipe, floor(0,8 × 6,25) = 5). O dono continua com o
  -- teto dele (_agenda_carga_da_pessoa, a Fase 6, logo acima) e fica fora da conta da equipe: ele é presença (abrir, fechar,
  -- diagnóstico), não capacidade de técnico. A saída ganha teto_equipe (um número por semana, na ordem de sem). Sem o portão,
  -- nada muda.
  if v_f7_teq then
    v_f7_te := '{}'::int[];
    for f7_w in 1 .. v_nw loop
      v_f7_soma := 0;
      for f7_p in 1 .. coalesce(v_np, 0) loop
        continue when f7_p = v_dono;
        v_f7_soma := v_f7_soma + coalesce(v_espw[(f7_p - 1) * v_nw + f7_w], 0);
        v_t80[(f7_p - 1) * v_nw + f7_w] := v_t100[(f7_p - 1) * v_nw + f7_w];
      end loop;
      v_f7_te := v_f7_te || floor(cf.carga_max * v_f7_soma)::int;
    end loop;
  end if;
  -- FASE 7: fim
  -- O local de cada OS (a marina, senão a cidade do cliente), para o desempate "mesmo local".
  select coalesce(array_agg(q.loc order by q.o), '{}'::int[]) into v_loc
    from (select k.o, case when k.chave is null then 0 else dense_rank() over (order by k.chave)::int end as loc
            from (select u.o, coalesce('m:' || so.marina_id::text, 'c:' || nullif(lower(btrim(cl.city)), '')) as chave
                    from unnest(v_oss) with ordinality u(os, o)
                    left join public.service_orders so on so.id = u.os
                    left join public.clients cl on cl.id = so.client_id) k) q;

  -- FASE 7b: (7b P4, §5.3) o que o motor da 7b lê, só com os modos dela (sem eles, nenhuma chave nova: a saída de antes):
  -- (1) sab = os índices dos sábados do período sem feriado nem recesso de manhã, com modo_sabado fora de desligado e sabado_manha
  -- diferente de nunca; (2) sab_bonus por pessoa e semana ((pessoa − 1) × nw + semana) = as manhãs de sábado em que ela está livre
  -- (cap = 1: a manhã que ela ofereceu, a exceção "vem"): o encaixe soma ao teto dela só na tentativa com o sábado; (3) novato = os
  -- índices de quem nunca fica sozinho num meio-dia na 1ª data da grade — o novato (_agenda_e_novato, com novato_sozinho falso) e
  -- quem vem sob demanda (_agenda_e_sob_demanda, com sob_demanda_sozinho falso) —, com modo_dupla fora de desligado (a segurança,
  -- como a dupla em teste); nunca o dono nem a pessoa a mais; (4) dono_tec = dono_como_tecnico (com modo_dias fora de desligado: os
  -- dias de campo que ele disse). Os tetos não mudam aqui.
  if cf.modo_sabado <> 'desligado' and cf.sabado_manha <> 'nunca' then
    v_7b_sab := array(select g + 1 from generate_series(0, v_nd - 1) g
                       where extract(isodow from p_d_ini + g)::int = 6 and public.agenda_feriado(p_d_ini + g) is null
                         and not exists (select 1 from public.agenda_disponibilidade d
                                          where d.payee_id is null and d.situacao = 'indisponivel' and d.substituida_em is null
                                            and d.periodo @> (p_d_ini + g) and (d.turno is null or d.turno = 'manha'))
                       order by g);
    if cardinality(v_7b_sab) > 0 then
      v_7b_bon := array_fill(0, array[greatest(v_np * v_nw, 1)]);
      foreach v_7b_d in array v_7b_sab loop
        for v_7b_p in 1 .. coalesce(v_np, 0) loop
          if v_cap[(v_7b_p - 1) * v_nh + 2 * (v_7b_d - 1) + 1] = 1 then
            v_7b_bon[(v_7b_p - 1) * v_nw + v_sem[v_7b_d]] := v_7b_bon[(v_7b_p - 1) * v_nw + v_sem[v_7b_d]] + 1;
          end if;
        end loop;
      end loop;
      v_7b_extra := v_7b_extra || jsonb_build_object('sab', to_jsonb(v_7b_sab), 'sab_bonus', to_jsonb(v_7b_bon));
    end if;
  end if;
  if cf.modo_dupla <> 'desligado' then
    v_7b_nov := array(select g.p from generate_series(1, coalesce(v_np, 0)) g(p)
                       where g.p <> v_dono and v_pes[g.p] is distinct from public._agenda_pessoa_extra_id()
                         and ((not cf.novato_sozinho and public._agenda_e_novato(v_pes[g.p], p_d_ini))
                              or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(v_pes[g.p], p_d_ini)))
                       order by g.p);
    if cardinality(v_7b_nov) > 0 then
      v_7b_extra := v_7b_extra || jsonb_build_object('novato', to_jsonb(v_7b_nov));
    end if;
  end if;
  if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_dono > 0 then
    v_7b_extra := v_7b_extra || jsonb_build_object('dono_tec', true);
  end if;
  if v_7b_extra <> '{}'::jsonb then
    return jsonb_build_object(
      'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
      'dono', v_dono, 'dono_tem_padrao', v_padrao,
      'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
      'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
      'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
      'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
      'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc))
      || case when v_f7_teq then jsonb_build_object('teto_equipe', to_jsonb(coalesce(v_f7_te, '{}'::int[]))) else '{}'::jsonb end
      || v_7b_extra;
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P5) com o portão do teto da equipe, a mesma saída de baixo (chave a chave; o T7 de
  -- supabase/tests/agenda_fase7a_teto.sql confere que só teto80 e teto_equipe mudam) com o teto da equipe por semana.
  if v_f7_teq then
    return jsonb_build_object(
      'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
      'dono', v_dono, 'dono_tem_padrao', v_padrao,
      'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
      'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
      'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
      'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
      'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc),
      'teto_equipe', to_jsonb(coalesce(v_f7_te, '{}'::int[])));
  end if;
  -- FASE 7: fim
  return jsonb_build_object(
    'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
    'dono', v_dono, 'dono_tem_padrao', v_padrao,
    'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
    'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
    'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
    'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
    'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc));
end;
$function$;

comment on function public._agenda_contexto(date, date, date, uuid[], uuid[]) is
  'Agenda de Produção (Fase 2, P2): a grade do motor em arrays (agenda_grade de p_d_ini a p_d_fim, sem as alocações de p_ignorar): pessoas (você primeiro), dias úteis, semana ISO de cada dia, quem está livre em cada meio-dia (cap), as pontas livres do dono (curta: 1 abertura, 2 fechamento), o que o vigente ocupa (ocup, frentes: o índice da OS em oss, negativo = reserva), o uso por pessoa e semana (compromisso e reserva) e os tetos floor(carga_max × esperado) e floor(esperado) — o esperado só de dia útil (o sábado combinado não sobe o teto). As OS de p_fila vêm primeiro em oss. FASE 6 (P4): o teto80 de cada pessoa usa _agenda_carga_da_pessoa (o dono com capacidade_dono em uso: floor(carga dele × esperado); os outros, carga_max) — a posição (pp − 1) × nw + ww é a pessoa v_pes[pp] na semana ww; fora de ligado, a saída de antes. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe'') (falso = a saída de antes, byte a byte): cada pessoa da equipe (todas menos o dono) pode chegar a 100% do esperado dela na semana (teto80 = teto100); a equipe inteira, a teto_equipe[semana] = floor(carga_max × a soma do esperado da equipe), arredondado uma vez, na soma; o dono mantém o teto dele (_agenda_carga_da_pessoa) e fica fora da soma (é presença, não capacidade de técnico); a saída ganha teto_equipe (um número por semana, na ordem de sem). O gancho do sábado (AG7-08): só com a variável agenda.sabado = ''on'' (a decisão da pergunta crítica sabado a liga) e sabado_manha diferente de nunca, a manhã de cada sábado que ainda não é útil e não é feriado vira útil, com lugar só para quem tem o padrão de sábado de manhã (sem exceção nem recesso naquele dia); a tarde fica sem ninguém; o sábado não entra no esperado (o teto não sobe). Sem a variável, nada muda. FASE 7b (P4, §5.3, §R2, R4.4): (0) o gancho do sábado do 7a (agenda.sabado) só com modo_sabado desligado; (1) sab = os sábados do período sem feriado nem recesso de manhã e (2) sab_bonus por pessoa e semana = as manhãs de sábado livres dela (a que ela ofereceu), com modo_sabado fora de desligado e sabado_manha diferente de nunca; (3) novato = os índices de quem nunca fica sozinho — o novato (_agenda_e_novato, novato_sozinho falso) e quem vem sob demanda (_agenda_e_sob_demanda, sob_demanda_sozinho falso) —, com modo_dupla fora de desligado, nunca o dono; (4) dono_tec = dono_como_tecnico com modo_dias fora de desligado. O gancho da pessoa a mais (R4.4, inerte sem a variável): com agenda.pessoa_extra = tecnico, "mais uma pessoa" (_agenda_pessoa_extra_id) entra por último, livre nas manhãs e tardes de todo dia útil, não novato nem sob demanda, com o teto de carga_max e contada no teto da equipe. Os tetos não mudam. Sem os modos e sem a variável, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 12): o gancho do sábado do 7a (agenda.sabado) vale também com modo_sabado em teste (sombra); só com modo_sabado ligado vale só o desta etapa.';

-- agenda_propor (de 20261101100300_agenda_fase7b_motor.sql)
create or replace function public.agenda_propor(
  p_escopo     text,
  p_de         date        default null,
  p_ate        date        default null,
  p_os         uuid[]      default null,
  p_restricoes jsonb       default '{}'::jsonb,
  p_persistir  boolean     default false,
  p_origem     text        default 'motor',
  p_autor      uuid        default null,
  p_hoje       date        default public._hoje_brt(),
  p_agora      timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  -- Os pesos da pontuação (plano §4.4, os do Timefold): estrutura para comparar alternativas, não parâmetro do dono.
  c_peso_atraso  constant int := 1000000;
  c_peso_mudanca constant int := 100;
  c_peso_dono    constant int := 10;
  c_peso_interr  constant int := 50;
  c_peso_fim     constant int := 1;
  -- "atrasar" leva a OS para o fim da classe: a ordem dela passa à frente de qualquer posição real da fila.
  c_fim_da_classe constant int := 1000000;
  -- quantas OS que X empurraria entram na pergunta "não cabe" (as mais próximas dela na fila)
  c_candidatas   constant int := 3;
  cf        public.agenda_config;
  v_r       jsonb := coalesce(p_restricoes, '{}'::jsonb);
  v_modo    text;
  v0        bigint;
  v_cong    date;
  v_seg     date;
  v_de      date;
  v_ate     date;
  v_hor     date;
  v_ini     date;
  v_fim     date;
  v_cart    uuid[];
  v_cartj   jsonb;
  v_escopo  uuid[];
  v_tirar   uuid[];
  v_atrasar uuid[];
  v_aceitar uuid[];
  v_acima   boolean;
  v_decisao uuid;
  v_fixar   jsonb;
  v_depois  jsonb;
  v_info    jsonb := '{}'::jsonb;
  v_canc    jsonb;
  v_ign     uuid[];
  v_fila_os uuid[];
  v_ctx     jsonb;
  v_pes     uuid[];
  v_fila    jsonb := '[]'::jsonb;
  v_ent     jsonb;
  v_par     jsonb;
  v_parh    jsonb;
  v_r0      jsonb;
  v_rf      jsonb;
  v_ctxf    jsonb;
  v_base    jsonb;
  v_sim     jsonb;
  v_minh_n  int;
  v_minh_a  int;
  v_os      uuid;
  v_i       int;
  v_e       jsonb;
  v_b       jsonb;
  v_pront   jsonb;
  v_meios   jsonb;
  v_pl      record;
  v_status  text;
  v_k       record;
  v_cl      jsonb;
  v_classe  int;
  v_fx      jsonb;
  v_fp      int;
  v_evento  boolean;
  v_passos  int;
  v_abre    boolean;
  v_fecha   boolean;
  v_dtm     boolean;
  v_dtt     boolean;
  v_fixa    int;
  v_pm      int[];
  v_pt      int[];
  v_est     date;
  v_estc    date;
  v_minh    int;
  v_bem     int[];
  v_pat_p   int;
  v_pat_b   int[];
  v_bem_tudo boolean;
  v_fora    jsonb := '[]'::jsonb;
  v_crit    jsonb := '{}'::jsonb;
  v_xnc     int[] := '{}';
  v_xoc     int[] := '{}';
  v_cands   jsonb := '{}'::jsonb;
  v_h       int[] := '{}';
  v_sem_q   int[] := '{}';
  v_tentativa int;
  v_usadas  jsonb;
  v_perg    jsonb := '[]'::jsonb;
  v_held    jsonb := '[]'::jsonb;
  v_itens   jsonb := '[]'::jsonb;
  v_opc     jsonb;
  v_rec     int;
  v_rec_txt text;
  v_txt     text;
  v_chave   text;
  v_tipo    text;
  v_fim_x   date;
  v_ini_x   date;
  v_fim_c   date;
  v_ini_c   date;
  v_x       int;
  v_c       int;
  v_cb      jsonb;
  v_xb      jsonb;
  v_canc_os uuid[];
  v_ini_antes date;
  v_fim_dep date;
  v_carga   jsonb;
  v_textos  jsonb;
  v_linhas  text[];
  v_tfora   text[];
  v_titulo  text;
  v_texto   text;
  v_pont    jsonb;
  v_viol    jsonb;
  v_pid     uuid;
  v_expira  timestamptz;
  v_dono    uuid := public._agenda_dono(null);
  v_feriados text[];
  v_q       jsonb;
  v_n       int;
  v_aviso   text;
  -- CORREÇÃO 29/10 (P3): a reserva da própria OS no encaixe do compromisso dela (res_propria) e o resumo que separa o
  -- marcado firme do reservado
  v_rp       int[];
  v_marc     text[];
  v_resv     text[];
  v_contagem text;
  -- CORREÇÃO 29/10 (P3): fim
  -- FASE 7: (7a P8) a zona travada: o que fica fora da conta do dia já avisado
  v_f7_fora uuid[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4) a dupla por meio-dia, o prazo firme, o sábado e as linhas em teste
  v_7b_pk     int[];
  v_7b_dk     int[];
  v_7b_tot    int;
  v_7b_prazo  date;
  v_7b_n      int;
  v_7b_semtec int;
  v_7b_tec    text[];
  v_7b_teste  text[] := '{}';
  v_7b_b      jsonb;
  v_7b_e      jsonb;
  v_7b_x      text;
  v_7b_y      text;
  v_7b_dias   date[];
  v_7b_nomes  text[];
  v_7b_z      text;
  v_7b_n2     int;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 22 e 23) o exemplo com todos os dias e a dupla dita antes de a OS ficar pronta
  v_7bc_dias date[];
  v_7bc_est  date;
  v_7bc_max  date;
  -- FASE 7b: fim
begin
  -- ── 0. Entrada ──
  if p_escopo is null or p_escopo not in ('semana', 'os', 'replano') then
    raise exception 'Escopo desconhecido: "%" (semana, os ou replano).', coalesce(p_escopo, '') using errcode = '22023';
  end if;
  if p_origem is null or p_origem not in ('motor', 'vigia', 'dono', 'assistente', 'tela', 'aprovacao') then
    raise exception 'Origem desconhecida: "%".', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null or jsonb_typeof(v_r) <> 'object' then
    raise exception 'Faltam o dia, a hora ou as restrições do plano.' using errcode = '22023';
  end if;
  if p_escopo in ('os', 'replano') and coalesce(cardinality(p_os), 0) = 0 then
    raise exception 'Diga de que OS é o plano.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  if p_persistir then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  cf := public._agenda_cfg();
  v_modo := cf.modo_proposta;
  if p_persistir and v_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'simulacao', false, 'texto', 'A agenda automática está desligada: não monto o plano.');
  end if;
  v0 := cf.versao_plano;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- ── 1. A janela ──
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  if p_escopo = 'semana' then
    v_de := coalesce(p_de, public.agenda_somar_du(v_seg + 7, 0));
    v_ate := coalesce(p_ate, v_seg + 7 + 5);
  else
    v_de := coalesce(p_de, public.agenda_somar_du(v_cong, 1));
    v_ate := coalesce(p_ate, v_de + 7 * cf.horizonte_semanas);
  end if;
  if v_ate < v_de then
    raise exception 'O período do plano termina antes de começar (% a %).', v_de, v_ate using errcode = '22023';
  end if;
  v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, v_ate);
  v_ini := v_seg;
  v_fim := v_hor + (7 - extract(isodow from v_hor)::int);

  -- ── Restrições (ids e datas já resolvidos por quem chama) ──
  v_tirar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'tirar', '[]'::jsonb)) x);
  v_atrasar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'atrasar', '[]'::jsonb)) x);
  v_aceitar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'aceitar_atraso', '[]'::jsonb)) x);
  v_acima := coalesce((v_r ->> 'acima_da_carga')::boolean, false);
  v_decisao := nullif(v_r ->> 'decisao', '')::uuid;
  if exists (select 1 from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e
              where e ->> 'os' is null or e ->> 'de' is null) then
    raise exception 'fixar precisa da OS e do dia.' using errcode = '22023';
  end if;
  select coalesce(jsonb_object_agg(e ->> 'os', jsonb_build_object('de', e -> 'de', 'ate', coalesce(e -> 'ate', e -> 'de'),
                                                                  'pessoa', e -> 'pessoa')), '{}'::jsonb)
    into v_fixar from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e;
  select coalesce(jsonb_object_agg(e ->> 'os', e -> 'dia'), '{}'::jsonb)
    into v_depois from jsonb_array_elements(coalesce(v_r -> 'so_depois_de', '[]'::jsonb)) e;

  -- ── 2. A carteira, o escopo e o que se sabe de cada OS ──
  select coalesce(array_agg(k.service_order_id order by k.numero collate "C", k.service_order_id), '{}'::uuid[]),
         coalesce(jsonb_object_agg(k.service_order_id::text, jsonb_build_object('sinal', k.sinal_pago > 0, 'aprovada_em', k.aprovada_em)), '{}'::jsonb)
    into v_cart, v_cartj
    from public.os_carteira(p_hoje) k;
  if p_escopo = 'semana' then
    v_escopo := v_cart;
  else
    v_escopo := array(select distinct x from unnest(p_os) x order by 1);
  end if;
  for v_os in
    select x from (select unnest(v_escopo) as x
                   union
                   select a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                      and p_escopo = 'semana' and not (a.service_order_id = any (v_cart))) q
     order by 1
  loop
    v_info := v_info || jsonb_build_object(v_os::text, jsonb_build_object(
                'pront', public.os_prontidao(v_os, p_hoje), 'meios', public.agenda_meios_da_os(v_os, p_hoje)));
  end loop;

  -- ── 3. Estabilidade: o que não pode mais acontecer sai (e o pedido do dono tira o que a OS tinha) ──
  v_canc := public._agenda_violacoes(v_escopo, v_cart, p_escopo = 'semana', v_info, p_hoje, v_cong);
  v_canc := v_canc || coalesce((
    select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'os', a.service_order_id, 'motivo', 'dono', 'violada', false,
             'congelado', a.dia <= v_cong, 'tipo', a.tipo, 'estado', a.estado, 'fixado_por', a.fixado_por,
             'reserva_de', a.reserva_de, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca)
             order by a.service_order_id, a.dia, a.turno = 'tarde', a.payee_id, a.id)
      from public.agenda_alocacoes a
     where v_fixar ? a.service_order_id::text and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
       and a.resultado is null and lower(a.periodo) > p_agora
       and not exists (select 1 from jsonb_array_elements(v_canc) c where (c ->> 'alocacao_id')::uuid = a.id)), '[]'::jsonb);
  v_ign := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c);

  -- ── 4. A grade e a fila ──
  v_fila_os := array(select x from unnest(v_escopo) x where not (x = any (v_tirar)) order by 1);
  v_ctx := public._agenda_contexto(v_ini, v_fim, p_hoje, v_ign, v_fila_os);
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') x);
  -- o 1º meio-dia que dá: depois do congelado; e, para o evento real e o pedido do dono, o 1º que ainda não começou
  v_minh_n := 2 * (v_cong + 1 - v_ini) + 1;
  v_minh_a := case when lower(public.agenda_periodo(p_hoje, 'manha')) > p_agora then 2 * (p_hoje - v_ini) + 1
                   when lower(public.agenda_periodo(p_hoje, 'tarde')) > p_agora then 2 * (p_hoje - v_ini) + 2
                   else 2 * (p_hoje + 1 - v_ini) + 1 end;

  for v_os in select unnest(v_tirar) loop
    if v_os = any (v_escopo) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'tirado', 'texto', public._agenda_rotulo_da_os(v_os) || ': você tirou.');
    end if;
  end loop;

  for v_i in 1 .. coalesce(cardinality(v_fila_os), 0) loop
    v_os := v_fila_os[v_i];
    v_pront := v_info -> v_os::text -> 'pront';
    v_meios := v_info -> v_os::text -> 'meios';
    select pl.* into v_pl from public.os_planejamento pl where pl.service_order_id = v_os;
    select so.status into v_status from public.service_orders so where so.id = v_os;
    -- o que fica do plano dela (sem o que a proposta cancela)
    select count(distinct (a.dia, a.turno)) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido'), false) as algum,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as ultimo,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as ultimo_fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.estado = 'fixada' and a.dia >= p_hoje and a.resultado is null), false) as fixada,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje), false) as reserva,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de = 'patio' and a.dia >= p_hoje), false) as patio
      into v_k
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and not (a.id = any (v_ign));
    v_bem_tudo := (v_pl.bem_indisponivel is not null and not isempty(v_pl.bem_indisponivel)
                   and not exists (select 1 from generate_series(p_hoje + 1, v_hor, interval '1 day') g
                                    where not (v_pl.bem_indisponivel @> g::date)))
                  or coalesce(v_pl.nao_antes_de > v_hor, false);
    v_cl := public._agenda_classe_da_os(v_pront, v_meios, p_hoje, v_k.fixada, v_bem_tudo);
    v_classe := (v_cl ->> 'classe')::int;
    v_fx := v_fixar -> v_os::text;
    if v_fx is not null then
      if v_classe = 4 then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_cl ->> 'texto', '.')));
        continue;
      end if;
      v_classe := 1;
    end if;
    v_evento := exists (select 1 from jsonb_array_elements(v_canc) c
                         where (c ->> 'os')::uuid = v_os and (c ->> 'violada')::boolean
                           and ((c ->> 'congelado')::boolean or (v_cl ->> 'classe')::int = 1));
    v_passos := case when (v_meios ->> 'total') is null then 0
                     else ceil(greatest((v_meios ->> 'total')::numeric - coalesce((v_meios ->> 'cumpridos')::numeric, 0)
                                        - coalesce(v_k.fut, 0), 0))::int end;
    v_fecha := v_meios ->> 'presenca' = 'abre_e_fecha';
    v_abre := v_fecha and not v_k.algum and coalesce((v_meios ->> 'cumpridos')::numeric, 0) = 0 and v_status <> 'in_progress';
    v_dtm := coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false);
    v_dtt := coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false);
    v_fixa := 0;
    if v_fx is not null and v_fx ->> 'pessoa' is not null then
      v_fp := array_position(v_pes, (v_fx ->> 'pessoa')::uuid);
      if v_fp is null then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: essa pessoa não está na equipe de agora.', public._agenda_rotulo_da_os(v_os)));
        continue;
      elsif v_fp = (v_ctx ->> 'dono')::int then
        v_dtm := true; v_dtt := true; v_abre := false; v_fecha := false;
      else
        v_fixa := v_fp;
      end if;
    end if;
    v_pm := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,manha,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    v_pt := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,tarde,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    -- EST': o dia em que fica pronta, depois do congelado (o evento real e o pedido do dono podem usar o que ainda não
    -- começou), depois do "só depois de" e depois do que ela já tem marcado.
    if v_fx is not null then
      v_est := greatest((v_fx ->> 'de')::date, p_hoje);
      v_minh := v_minh_a;
    elsif v_evento then
      v_est := greatest(coalesce((v_pront #>> '{material,inicio_mat}')::date, p_hoje), v_pl.nao_antes_de, p_hoje,
                        (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_a;
    else
      v_est := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                        public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_n;
    end if;
    v_estc := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                       public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date);
    v_bem := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                    where coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    -- o pátio: o que dá para adiantar sem o bem, enquanto ele está fora (dentro da janela)
    v_pat_p := 0;
    v_pat_b := '{}';
    if v_pl.adiantavel_patio_dias is not null and not v_k.patio and v_classe in (1, 2, 3) and v_passos > 0
       and exists (select 1 from generate_series(greatest(v_de, public.agenda_somar_du(v_cong, 1)), v_ate, interval '1 day') g
                    where coalesce(v_pl.bem_indisponivel @> g::date, false)) then
      v_pat_p := (v_pl.adiantavel_patio_dias * 2)::int;
      v_pat_b := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                        where not coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    end if;
    v_e := jsonb_build_object(
      'i', v_i, 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
      'classe', v_classe, 'motivo', v_cl ->> 'motivo', 'texto', v_cl ->> 'texto', 'condicao_tipo', v_cl ->> 'condicao_tipo',
      'passos', v_passos, 'abre', v_abre, 'fecha', v_fecha, 'dt_m', v_dtm, 'dt_t', v_dtt,
      'dm', coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0), 'dtd', coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
      'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', v_fixa,
      'est', v_est - v_ini + 1, 'est_cond', v_estc - v_ini + 1, 'est_patio', public.agenda_somar_du(v_cong, 1) - v_ini + 1,
      'min_h', v_minh, 'bem', to_jsonb(v_bem), 'patio_passos', v_pat_p, 'patio_bem', to_jsonb(v_pat_b),
      'tem_reserva', v_k.reserva, 'tem_fixada', v_k.fixada, 'evento_real', v_evento, 'teto100', v_fx is not null,
      'dono_impossivel', ((v_dtm or v_dtt) and not coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false))
                         or ((v_abre or v_fecha or v_dtm or v_dtt) and coalesce((v_ctx ->> 'dono')::int, 0) = 0),
      'atrasar', v_os = any (v_atrasar), 'prio', v_pl.prioridade_manual, 'razao', v_pront -> 'razao_critica',
      'sinal', coalesce((v_cartj -> v_os::text ->> 'sinal')::boolean, false), 'aprovada_em', v_pront ->> 'aprovada_em',
      'fonte', v_meios ->> 'fonte', 'dias', v_meios -> 'dias', 'precisa', v_pl.precisa_ate,
      'fim_antes', v_pront #>> '{plano,ultimo_dia}', 'kept_max', v_k.ultimo, 'tipo_os',
      -- o tipo do meio-dia: o motivo da regra d05 (diagnóstico, comissionamento), mesmo quando o dono está na equipe
      case v_meios ->> 'regra_motivo' when 'diagnóstico' then 'diagnostico' when 'comissionamento' then 'comissionamento'
           else 'execucao' end)
      || case when v_fx is not null then jsonb_build_object('fixar_de', greatest((v_fx ->> 'de')::date, p_hoje) - v_ini + 1,
                                                            'fixar_ate', (v_fx ->> 'ate')::date - v_ini + 1)
              else '{}'::jsonb end;
    -- CORREÇÃO 29/10 (P3): a reserva DELA (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira
    -- compromisso" cancela) não conta contra ela mesma no encaixe do compromisso. O encaixe já deixava o compromisso usar a
    -- célula da própria reserva, mas o lugar até 100% da semana (teto100 − compromisso − reserva) contava a reserva dela:
    -- com o teto apertado (o João, 4 de 4 meios-dias na semana, todos na reserva do Lenine) a promoção nunca cabia. Vai na
    -- entrada da fila só quando há: res_propria = a pessoa × semana ((pessoa − 1) × nw + semana, a posição de uso_r no
    -- contexto) de cada meio-dia reservado, uma vez por alocação.
    if v_k.reserva then
      v_rp := array(select (array_position(v_pes, a.payee_id) - 1) * (v_ctx ->> 'nw')::int + (a.dia - v_ini) / 7 + 1
                      from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'
                       and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje and a.dia between v_ini and v_fim
                       and a.presenca = 'turno' and a.payee_id = any (v_pes) and not (a.id = any (v_ign))
                     order by 1);
      if cardinality(v_rp) > 0 then
        v_e := v_e || jsonb_build_object('res_propria', to_jsonb(v_rp));
      end if;
    end if;
    -- CORREÇÃO 29/10 (P3): fim
    -- FASE 7b: (7b P4, §5.3, R4.3) a entrada da fila, só com os modos da 7b: a dupla por meio-dia (dk = as pessoas dos passos que
    -- restam, os últimos v_passos do molde; dk_dono_conta; a fonte; o texto do cartão); da dupla inferida, o bloco de 1 pessoa
    -- (passos1: ligado com a duração que conserva as diárias-pessoa, a soma do dk — cada meio-dia de dupla vira dois de 1 pessoa —; em
    -- teste ou com os dias ditos pelo dono, os passos de antes), os meios-dias
    -- dela que restam no início e no fim (dupla_ni, dupla_nf; ou dupla_todos) e o nome do que a tarefa pede; o prazo firme (prazo_h =
    -- o índice da tarde de least(precisa_ate, o prometido firme) na grade); e a dupla dita que só passa pela régua dos técnicos com
    -- quem vem sob demanda (dupla_sd: sem eles, a classe daria 4; R4.3(c)).
    v_7b_dk := '{}'::int[];
    if v_meios ? 'dk' then
      v_7b_pk := public._agenda_ints(v_meios #> '{dupla,pk}');
      v_7b_tot := cardinality(v_7b_pk);
      v_7b_dk := case when v_passos > 0 then v_7b_pk[greatest(v_7b_tot - v_passos + 1, 1) : v_7b_tot] else '{}'::int[] end;
      v_e := v_e || jsonb_build_object('dk', to_jsonb(v_7b_dk), 'dk_dono_conta', v_meios -> 'dk_dono_conta',
                                       'dupla_fonte', v_meios #>> '{dupla,fonte}', 'dupla_texto', v_meios #>> '{dupla,texto}');
      if v_meios #>> '{dupla,fonte}' = 'regra' and v_passos > 0 then
        v_e := v_e || jsonb_build_object(
          'passos1', case when (v_meios #>> '{dupla,pm_estimativa}') is not null then (select sum(x)::int from unnest(v_7b_dk) x)
                          else v_passos end,
          'dupla_todos', coalesce((v_meios #>> '{dupla,todos}')::boolean, false),
          'dupla_ni', least(greatest(coalesce((v_meios #>> '{dupla,ni}')::int, 0) - (v_7b_tot - v_passos), 0), v_passos),
          'dupla_nf', least(coalesce((v_meios #>> '{dupla,nf}')::int, 0), v_passos),
          'dupla_rot_ini', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'inicio' order by m ->> 'motivo')),
          'dupla_rot_fim', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'fim' order by m ->> 'motivo')),
          'dupla_rot_todos', (select m ->> 'rotulo' from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                               where m ->> 'onde' = 'todos' limit 1));
      end if;
    end if;
    if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_meios ->> 'presenca' = 'nunca' then
      v_e := v_e || jsonb_build_object('dono_nunca', true);
    end if;
    if cf.modo_sabado <> 'desligado' or v_meios ? 'dk' then
      v_7b_prazo := least(v_pl.precisa_ate, case when v_pl.prometido_tipo = 'firme' then v_pl.prometido_ate end);
      if v_7b_prazo between v_ini and v_fim then
        v_e := v_e || jsonb_build_object('prazo_h', 2 * (v_7b_prazo - v_ini) + 2, 'prazo', v_7b_prazo);
      end if;
    end if;
    if cf.modo_dupla <> 'desligado' and v_pl.dupla_dita in ('todos', 'inicio', 'fim')
       and not coalesce((v_meios ->> 'equipe_dita')::boolean, false) and v_passos > 0 then
      v_7b_n := greatest(coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0),
                         coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
                         coalesce((select max(x) from unnest(v_7b_dk) x), 0)
                         - case when coalesce((v_meios ->> 'dk_dono_conta')::boolean, true)
                                     and (coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false)
                                          or coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end);
      if v_7b_n >= 2 then
        v_7b_semtec := coalesce(v_7b_semtec, (select count(*)::int from jsonb_array_elements(coalesce(
                         public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) x
                        where not coalesce((x ->> 'eh_dono')::boolean, false)));
        if v_7b_semtec < v_7b_n then
          v_e := v_e || jsonb_build_object('dupla_sd', true, 'dupla_n', v_7b_n,
                                           'dupla_meios_n', case when cardinality(v_7b_dk) > 0
                                                                 then (select count(*)::int from unnest(v_7b_dk) x where x >= 2)
                                                                 else v_passos end);
        end if;
      end if;
    end if;
    -- FASE 7b: fim
    v_fila := v_fila || v_e;
  end loop;

  -- A ordem: (classe, atrasar, prioridade do dono, razão crítica, sinal pago, aprovação, número, id).
  select coalesce(jsonb_agg(x.e || jsonb_build_object('ordem', x.rn) order by x.rn), '[]'::jsonb) into v_fila
    from (select e, row_number() over (order by (e ->> 'classe')::int, (e ->> 'atrasar')::boolean, (e ->> 'prio')::int nulls last,
                                                (e ->> 'razao')::numeric nulls last, (e ->> 'sinal')::boolean desc,
                                                (e ->> 'aprovada_em')::date nulls last, e ->> 'numero' collate "C", e ->> 'os') as rn
            from jsonb_array_elements(v_fila) e) x;
  select coalesce(jsonb_object_agg(e ->> 'i', e), '{}'::jsonb) into v_ent from jsonb_array_elements(v_fila) e;

  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', cf.inicios_tentados_du,
                              'semana', p_escopo = 'semana', 'jan_de', v_de - v_ini + 1, 'jan_ate', v_ate - v_ini + 1,
                              'acima', v_acima);
  -- FASE 7b: (7b P4) os parâmetros do sábado (modo e política) e da dupla (modo; a espera: ligado, dupla_espera_max_du dias úteis;
  -- em teste, 0 — a dupla só entra quando não termina depois do bloco de 1 pessoa, d8), só com os modos da 7b
  if cf.modo_sabado <> 'desligado' or cf.modo_dupla <> 'desligado' then
    v_par := v_par || jsonb_build_object('sab_modo', cf.modo_sabado, 'sab_politica', cf.sabado_manha, 'dupla_modo', cf.modo_dupla,
                                         'dupla_espera', case when cf.modo_dupla = 'ligado' then cf.dupla_espera_max_du else 0 end);
  end if;
  -- FASE 7b: fim
  v_parh := v_par || jsonb_build_object('semana', false);

  -- ── 5. O encaixe e a sobrecarga (o banco nunca escolhe quem atrasa) ──
  for v_tentativa in 1 .. 3 loop
    -- (quem ficou sem saída na volta anterior sai da fila: fica fora, sem encaixe)
    v_r0 := public._agenda_encaixar(v_ctx,
              (select jsonb_agg(case when (e ->> 'i')::int = any (v_sem_q) then e || '{"tirar": true}'::jsonb else e end)
                 from jsonb_array_elements(v_fila) e), v_par);
    -- o que é crítico em cada compromisso colocado
    v_crit := '{}'::jsonb;
    for v_b in select e from jsonb_array_elements(v_r0 -> 'colocadas') e where e ->> 'tipo' = 'compromisso' loop
      v_e := v_ent -> (v_b ->> 'i');
      continue when v_e ? 'fixar_de';
      v_os := (v_e ->> 'os')::uuid;
      v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
      v_fim_x := greatest(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date);
      v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
      v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                       where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os, '{}');
      -- FASE 7: (7a P8, spec §3.2 e §5.8) a zona travada (a regra zona_travada): a criticidade de novo, agora sabendo o que fica
      -- fora da conta do dia já avisado — o que não pode mais acontecer, o resto do meio-dia dele e o que volta igual neste
      -- encaixe (_agenda_zona_fora; o fixado pelo dono nunca fica fora: a regra dele não muda).
      if public._agenda_gestor_regra('zona_travada') then
        v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
        v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os,
                                             v_f7_fora);
      end if;
      -- FASE 7: fim
      if v_tipo is not null then
        v_crit := v_crit || jsonb_build_object(v_b ->> 'i', jsonb_build_object('tipo', v_tipo, 'fim', v_fim_x, 'ini', v_ini_x));
      end if;
    end loop;
    -- as críticas ainda sem decisão
    v_xnc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' = 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    v_xoc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' <> 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    -- quem X empurraria: as da classe 2 colocadas antes dela, novas e sem fixado, as mais próximas
    v_cands := '{}'::jsonb;
    foreach v_x in array v_xnc loop
      v_cands := v_cands || jsonb_build_object(v_x::text, coalesce((
        select jsonb_agg(q.i order by q.ordem desc)
          from (select (b ->> 'i')::int as i, (v_ent -> (b ->> 'i') ->> 'ordem')::int as ordem
                  from jsonb_array_elements(v_r0 -> 'colocadas') b
                 where b ->> 'tipo' = 'compromisso'
                   and (v_ent -> (b ->> 'i') ->> 'classe')::int = 2 and not (v_ent -> (b ->> 'i')) ? 'fixar_de'
                   and not (v_ent -> (b ->> 'i') ->> 'tem_fixada')::boolean and v_ent -> (b ->> 'i') ->> 'fim_antes' is null
                   and (v_ent -> (b ->> 'i') ->> 'ordem')::int < (v_ent -> v_x::text ->> 'ordem')::int
                   and not ((b ->> 'i')::int = any (v_xnc || v_xoc))
                   -- (na 2ª volta, só as que deram opção: quem não faz X caber não fica esperando a decisão)
                   and (v_usadas is null or coalesce(v_usadas -> v_x::text, '[]'::jsonb) @> to_jsonb((b ->> 'i')::int))
                 order by 2 desc limit c_candidatas) q), '[]'::jsonb));
    end loop;
    v_h := array(select distinct x from (select unnest(v_xnc || v_xoc) as x
                                          union select (j)::int from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(v) j) u
                  order by 1);
    exit when cardinality(v_h) = 0;

    -- O que é publicado sem esperar sai desta mesma rodada (as reservas foram depois de todos os compromissos, e não
    -- tomam o lugar de quem espera a decisão); quem espera fica como item crítico (X, a que não cabe, sai).
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx,
                (select coalesce(jsonb_agg(b), '[]'::jsonb) from jsonb_array_elements(v_r0 -> 'colocadas') b
                  where not ((b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')));
    -- a decisão vai encontrar a grade já com o resto publicado: as opções são simuladas sobre ela
    v_base := public._agenda_encaixar(v_ctxf,
                (select jsonb_agg(e) from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
    v_perg := '[]'::jsonb;
    v_n := cardinality(v_sem_q);
    foreach v_x in array v_xnc || v_xoc loop
      v_e := v_ent -> v_x::text;
      v_os := (v_e ->> 'os')::uuid;
      v_tipo := v_crit -> v_x::text ->> 'tipo';
      v_xb := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
      v_fim_x := case when v_xb is null then null
                      else greatest(v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date) end;
      v_opc := '[]'::jsonb;
      if v_tipo = 'nao_cabe' then
        if v_fim_x is not null then
          v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x),
                     'sem_data', false, 'atraso_du', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x), 'numero', v_e ->> 'numero',
                     'texto', format('%s atrasa: termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                     public._dia_curto((v_e ->> 'precisa')::date)),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                     'espera', jsonb_build_object(v_os::text, v_fim_x));
        end if;
        for v_c in select (j)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) j loop
          v_sim := public._agenda_encaixar(v_ctxf,
                     (select jsonb_agg(case when (e ->> 'i')::int = v_c
                                            then e || jsonb_build_object('ordem', (e ->> 'ordem')::int + c_fim_da_classe) else e end)
                        from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
          v_xb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
          v_cb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          continue when v_xb is null or v_cb is null
                     or v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1 > (v_e ->> 'precisa')::date;
          v_ini_c := v_ini + ((v_cb ->> 'ini')::int + 1) / 2 - 1;
          v_fim_c := v_ini + ((v_cb ->> 'fim')::int + 1) / 2 - 1;
          v_b := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          v_opc := v_opc || jsonb_build_object('n', jsonb_array_length(v_opc) + 1, 'os', v_ent -> v_c::text -> 'os', 'c', v_c,
                     'atraso_dito', case when v_ent -> v_c::text ->> 'precisa' is null then 0
                                         else greatest(public.agenda_du_entre((v_ent -> v_c::text ->> 'precisa')::date, v_fim_c), 0) end,
                     'sem_data', v_ent -> v_c::text ->> 'precisa' is null,
                     'atraso_du', case when v_b is null then 0
                                       else greatest(public.agenda_du_entre(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, v_fim_c), 0) end,
                     'numero', v_ent -> v_c::text ->> 'numero',
                     'texto', format('%s passa para %s (%s)', public._agenda_rotulo_da_os((v_ent -> v_c::text ->> 'os')::uuid),
                                     public._agenda_dias_texto(array(select distinct v_ini + (h - 1) / 2
                                                                       from unnest(public._agenda_ints(v_cb -> 'h')) h)),
                                     case when v_ent -> v_c::text ->> 'precisa' is null then 'sem data dita pelo cliente'
                                          else 'precisa até ' || public._dia_curto((v_ent -> v_c::text ->> 'precisa')::date) end),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('atrasar', jsonb_build_array(v_ent -> v_c::text -> 'os'))),
                     'espera', jsonb_build_object(v_os::text, v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1,
                                                  v_ent -> v_c::text ->> 'os', v_fim_c));
          exit when jsonb_array_length(v_opc) >= 4;
        end loop;
      elsif v_fim_x is not null then
        v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', 0, 'sem_data', false, 'atraso_du', 0, 'numero', v_e ->> 'numero',
                   'texto', format('Sigo: %s termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                   public._dia_curto((v_e ->> 'fim_antes')::date)),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                   'espera', jsonb_build_object(v_os::text, v_fim_x));
      end if;
      if jsonb_array_length(v_opc) = 0 then
        -- sem saída nenhuma: não é pergunta (fica fora, sem encaixe); a próxima volta refaz sem ela na espera
        v_sem_q := v_sem_q || v_x;
        continue;
      end if;
      if jsonb_array_length(v_opc) = 1 then
        v_opc := v_opc || jsonb_build_object('n', 2, 'os', v_os, 'atraso_dito', null, 'sem_data', false, 'atraso_du', null,
                   'numero', v_e ->> 'numero',
                   'texto', format('Deixo o %s fora do plano por enquanto', public._agenda_nome_curto(v_e ->> 'cliente_curto')),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('tirar', jsonb_build_array(v_os))),
                   'espera', '{}'::jsonb);
      end if;
      -- a recomendação: o menor atraso sobre datas ditas; no empate, quem não tem data dita, o menor atraso, o número
      if v_tipo = 'nao_cabe' then
        select (o ->> 'n')::int into v_rec from jsonb_array_elements(v_opc) o
         where o ->> 'atraso_dito' is not null
         order by (o ->> 'atraso_dito')::int, (o ->> 'sem_data')::boolean desc, (o ->> 'atraso_du')::int, o ->> 'numero' collate "C"
         limit 1;
        v_rec := coalesce(v_rec, 1);
        v_q := v_opc -> (v_rec - 1);
        v_rec_txt := case when (v_q ->> 'sem_data')::boolean
                            then format('o %s não tem data dita pelo cliente', public._agenda_nome_curto((select cl.name from public.service_orders so
                                          join public.clients cl on cl.id = so.client_id where so.id = (v_q ->> 'os')::uuid)))
                          when v_rec = 1 then format('é o menor atraso (%s)', public._agenda_plural((v_q ->> 'atraso_du')::int, 'dia útil', 'dias úteis'))
                          else 'é o menor atraso sobre o que o cliente pediu' end;
        v_txt := format('Não cabe tudo até %s. Qual aceita atrasar? %s. Recomendo a %s: %s.',
                        public._dia_curto((v_e ->> 'precisa')::date),
                        (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int) from jsonb_array_elements(v_opc) o),
                        v_rec, v_rec_txt);
      else
        v_rec := 1;
        v_rec_txt := case v_tipo
          when 'atraso_longo' then 'Recomendo seguir e você ligar para o cliente hoje'
          when 'segundo_atraso' then 'É o 2º atraso desta OS: recomendo seguir e você ligar para o cliente hoje'
          when 'remarcar_confirmado' then 'O cliente tinha confirmado o dia: recomendo seguir e você ligar para ele hoje'
          else 'Você tinha fixado o dia, que não dá mais: recomendo seguir no novo dia' end;
        -- FASE 7: (7a P3) a recomendação das críticas da zona travada do gestor (P8: o dia que a equipe já recebeu na ficha e o
        -- que o cliente já ouviu); inertes até lá (_agenda_criticidade ainda não dá esses tipos)
        if v_tipo = 'dia_avisado' then
          v_rec_txt := 'A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia';
        elsif v_tipo = 'dia_prometido' then
          v_rec_txt := 'É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje';
        end if;
        -- FASE 7: fim
        v_txt := format('%s só dá para terminar em %s, %s depois do que estava no plano. 1) %s; 2) %s. %s.',
                        public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                        public._agenda_plural(v_fim_x - (v_e ->> 'fim_antes')::date, 'dia', 'dias'),
                        v_opc -> 0 ->> 'texto', v_opc -> 1 ->> 'texto', v_rec_txt);
      end if;
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
      v_perg := v_perg || jsonb_build_object(
        'tipo', v_tipo, 'chave', v_chave, 'service_order_id', v_os,
        'os_ids', (select jsonb_agg(v_ent -> j::text -> 'os' order by j) from unnest(array[v_x] || coalesce(
                     array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[])) j),
        'texto', left(v_txt, 600), 'opcoes', v_opc, 'recomendacao', v_rec, 'recomendacao_texto', left(v_rec_txt, 300),
        'perda_em', (select min(v_ini + ((b ->> 'ini')::int + 1) / 2 - 1) from jsonb_array_elements(v_base -> 'colocadas') b
                      where (b ->> 'i')::int = any (array[v_x] || coalesce(
                        array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[]))),
        'x', v_x);
    end loop;
    -- quem ficou sem saída sai da espera e a conta é refeita
    continue when cardinality(v_sem_q) <> v_n;
    -- as que não fazem X caber não ficam esperando a decisão: a conta é refeita só com as que deram opção (uma vez)
    if v_usadas is null and exists (
         select 1 from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(t.v) j
          where not exists (select 1 from jsonb_array_elements(v_perg) q, jsonb_array_elements(q -> 'opcoes') o
                             where (q ->> 'x')::int = t.k::int and (o ->> 'c')::int = j::int)) then
      select coalesce(jsonb_object_agg(q ->> 'x', coalesce((select jsonb_agg((o ->> 'c')::int) from jsonb_array_elements(q -> 'opcoes') o
                                                             where o ? 'c'), '[]'::jsonb)), '{}'::jsonb)
        into v_usadas from jsonb_array_elements(v_perg) q;
      continue;
    end if;
    exit;
  end loop;
  if cardinality(v_h) = 0 then
    v_xnc := '{}';
    v_xoc := '{}';
    v_perg := '[]'::jsonb;
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx, v_rf -> 'colocadas');
    v_base := jsonb_build_object('colocadas', '[]'::jsonb);
  end if;

  -- ── 6. Os itens: o que sai, o que entra, o que espera a decisão ──
  -- (a) o que sai (a violação, o resto do meio-dia, o pedido do dono)
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', g.numero, 'cliente_curto', g.cliente_curto, 'tipo', g.tipo,
             'motivo', g.motivo, 'violada', g.violada, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: sai %s — %s.', public._agenda_rotulo_da_os(g.os), public._agenda_dias_texto(g.dias),
                             case g.motivo when 'pessoa' then 'quem ia não está mais livre' when 'material' then 'o material não chega a tempo'
                                           when 'cliente' then 'o cliente ou o bem não está liberado' when 'os_saiu' then 'a OS saiu da carteira'
                                           when 'condicao_vencida' then 'a condição da reserva venceu' when 'dono' then 'você pediu outro dia'
                                           when 'espera' then coalesce('você pôs em espera até ' || public._dia_curto(
                                             (select pl.congelada_ate from public.os_planejamento pl where pl.service_order_id = g.os)),
                                             'você pôs em espera')
                                           else 'replanejado junto' end))
             order by g.numero, g.os, g.motivo)
      from (select (c ->> 'os')::uuid as os, min(v_info -> (c ->> 'os') -> 'pront' ->> 'numero') as numero,
                   min(v_info -> (c ->> 'os') -> 'pront' ->> 'cliente_curto') as cliente_curto,
                   case when bool_and(c ->> 'tipo' = 'reserva') then 'reserva' else min(c ->> 'tipo') end as tipo,
                   c ->> 'motivo' as motivo, bool_or((c ->> 'violada')::boolean) as violada,
                   jsonb_agg(jsonb_build_object('alocacao_id', c -> 'alocacao_id', 'payee_id', c -> 'payee_id',
                               'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = (c ->> 'payee_id')::uuid),
                               'dia', c -> 'dia', 'turno', c -> 'turno', 'presenca', c -> 'presenca', 'estado', c -> 'estado',
                               'fixado_por', c -> 'fixado_por')
                             order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id') as alocs,
                   array_agg((c ->> 'dia')::date) as dias, min((c ->> 'dia')::date) as de, max((c ->> 'dia')::date) as ate
              from jsonb_array_elements(v_canc) c
             group by (c ->> 'os')::uuid, c ->> 'motivo') g), '[]'::jsonb);
  -- (b) a reserva que virou compromisso nesta proposta
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', v_ent -> g.i ->> 'numero', 'cliente_curto', v_ent -> g.i ->> 'cliente_curto',
             'tipo', 'reserva', 'motivo', 'promovida', 'violada', false, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: a reserva vira compromisso.', public._agenda_rotulo_da_os(g.os)))
             order by v_ent -> g.i ->> 'numero')
      from (select b ->> 'i' as i, (v_ent -> (b ->> 'i') ->> 'os')::uuid as os,
                   (select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                     'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado, 'fixado_por', a.fixado_por)
                                     order by a.dia, a.turno = 'tarde', a.payee_id)
                      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                     where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid and a.estado in ('publicada', 'fixada')
                       and a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje
                       and not (a.id = any (v_ign))) as alocs,
                   (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as de,
                   (select max(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as ate
              from jsonb_array_elements(v_rf -> 'colocadas') b
             where b ->> 'tipo' = 'compromisso' and coalesce((b ->> 'na_janela')::boolean, true)
               and (v_ent -> (b ->> 'i') ->> 'tem_reserva')::boolean and not ((b ->> 'i')::int = any (v_h))) g
     where g.alocs is not null), '[]'::jsonb);
  -- (c) o que entra: publicável sem esperar, ou (d) esperando a decisão (a X que não cabe sai da proposta)
  for v_b in
    select b || jsonb_build_object('espera', (b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')
      from jsonb_array_elements(v_rf -> 'colocadas') b
     where coalesce((b ->> 'na_janela')::boolean, true)
       and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso')
  loop
    v_e := v_ent -> (v_b ->> 'i');
    v_os := (v_e ->> 'os')::uuid;
    v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
    v_fim_x := v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1;
    v_fim_dep := greatest(v_fim_x, (v_e ->> 'kept_max')::date);
    v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
    v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                     where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
    v_tipo := case when v_b ->> 'tipo' = 'reserva' or v_e ? 'fixar_de' then null
                   else public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                                   v_canc_os, '{}') end;
    -- FASE 7: (7a P8) a zona travada, como no encaixe acima (o que espera a decisão de outra OS segue a de antes)
    if v_b ->> 'tipo' <> 'reserva' and not v_e ? 'fixar_de' and not coalesce((v_b ->> 'espera')::boolean, false)
       and public._agenda_gestor_regra('zona_travada') then
      v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                           v_canc_os, v_f7_fora);
    end if;
    -- FASE 7: fim
    -- quem espera a decisão de uma X: o tipo dela e a chave da pergunta
    v_chave := null;
    if (v_b ->> 'espera')::boolean then
      select q ->> 'chave', coalesce(v_tipo, q ->> 'tipo') into v_chave, v_tipo from jsonb_array_elements(v_perg) q
       where q -> 'os_ids' @> jsonb_build_array(v_os) order by q ->> 'chave' limit 1;
    elsif v_tipo is not null and v_decisao is null and not (v_os = any (v_aceitar)) then
      -- crítico sem pergunta (não deveria acontecer: a pergunta foi feita acima); fica esperando
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
    end if;
    -- O pedido do dono num dia antes de o material estar garantido: fica (a decisão é dele), com o aviso na frase.
    v_aviso := case when v_e ? 'fixar_de' and v_b ->> 'tipo' <> 'reserva'
                    then public._agenda_aviso_do_material(v_info -> v_os::text -> 'pront', v_e ->> 'condicao_tipo', v_e ->> 'texto', v_ini_x) end;
    v_txt := case
      when v_b ->> 'tipo' = 'reserva' then
        format('%s: %s, %s%s.',
               case v_b ->> 'reserva_de' when 'patio' then 'Reserva no pátio' when 'teto' then 'Reserva (acima da carga)' else 'Reserva' end
                 || ' ' || public._agenda_rotulo_da_os(v_os),
               public._agenda_faixa_texto(v_ini_x, case when (v_b ->> 'ini')::int % 2 = 1 then 'manha' else 'tarde' end,
                                          v_fim_x, case when (v_b ->> 'fim')::int % 2 = 1 then 'manha' else 'tarde' end),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono), '')
      else
        format('%s%s: %s, %s%s.', public._agenda_rotulo_da_os(v_os),
               case v_e ->> 'tipo_os' when 'diagnostico' then ', diagnóstico' when 'comissionamento' then ', comissionamento' else '' end,
               public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date
                                                 from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a)),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono),
               coalesce(' — mas ' || v_aviso, '')) end;
    -- FASE 7: (7a P3, D7-1) o compromisso marcado pela estimativa do orçamento (a fonte 'orcamento' de agenda_meios_da_os, que
    -- só existe com a regra estimativa) diz isso no fim: "… com Roberto e João (estimativa minha: 6 dias)."
    if v_e ->> 'fonte' = 'orcamento' and v_b ->> 'tipo' <> 'reserva' and right(v_txt, 1) = '.' then
      v_txt := left(v_txt, -1) || format(' (estimativa minha: %s).', public._agenda_dias((v_e ->> 'dias')::numeric));
    end if;
    -- FASE 7: fim
    -- FASE 7b: (7b P4, §6.3, R4.3(a)(3)) ligado: o compromisso com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael
    -- se ofereceu), para cumprir o prazo de qua 18/11."); o bloco de 1 pessoa da dupla inferida diz em que meios-dias a tarefa pede
    -- 2 e o que fazer (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex
    -- está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."). Em teste, nada aqui (a linha "Em teste" abaixo).
    if v_b ? 'sabado' and right(v_txt, 1) = '.' then
      select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
        from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a
       where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
      v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                             from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) with ordinality t(a, o)
                                            where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                           order by y.o);
      v_txt := left(v_txt, -1) || format(' — com %s de manhã (%s %s)%s.', public._agenda_dias_texto(v_7b_dias),
                 public._agenda_lista(v_7b_nomes), case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end,
                 case when v_e ? 'prazo' then ', para cumprir o prazo de ' || public._dia_curto((v_e ->> 'prazo')::date) else '' end);
    end if;
    if v_b ? 'dupla_falta' and cf.modo_dupla = 'ligado' and jsonb_array_length(v_b -> 'dupla_falta') > 0 then
      if v_7b_tec is null then
        v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      end if;
      -- os meios-dias de cada parte: "qua 04/11, manhã e tarde", "qua 04/11 de manhã"
      select public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' in ('inicio', 'todos')) z
                group by z.d order by z.d)),
             public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'fim') z
                group by z.d order by z.d))
        into v_7b_x, v_7b_y;
      v_7b_n := (select count(*)::int from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'inicio');
      v_7b_z := case
        when coalesce((v_e ->> 'dupla_todos')::boolean, false)
          then format('O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      coalesce(v_e ->> 'dupla_rot_todos', 'o orçamento previu 2 técnicos'),
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        when v_7b_x <> '' and v_7b_y <> ''
          then format('%s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_7b_x,
                      v_e ->> 'dupla_rot_ini',
                      case when jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n = 1 then 'no último meio-dia'
                           else format('nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n) end, v_7b_y,
                      v_e ->> 'dupla_rot_fim',
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        else format('%s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                    case when v_7b_x <> '' then case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end
                         when jsonb_array_length(v_b -> 'dupla_falta') = 1 then 'No último meio-dia'
                         else format('Nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta')) end,
                    case when v_7b_x <> '' then v_7b_x else v_7b_y end,
                    case when v_7b_x <> '' then v_e ->> 'dupla_rot_ini' else v_e ->> 'dupla_rot_fim' end,
                    case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                    public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)) end;
      -- (correção da revisão da 7b, achado 23) o exemplo diz todos os dias em que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem
      -- qua 18 e qui 19/11"): quem seguisse o exemplo ao pé da letra deixava os outros meios-dias sem a 2ª pessoa
      v_7bc_dias := array(select distinct v_ini + ((f ->> 'h')::int + 1) / 2 - 1 from jsonb_array_elements(v_b -> 'dupla_falta') f order by 1);
      if cardinality(v_7bc_dias) > 1 then
        v_7b_z := replace(v_7b_z, format('(ex.: Mateus vem %s).', public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)),
                          format('(ex.: Mateus vem %s).', regexp_replace(public._agenda_dias_texto(v_7bc_dias), ' \([^()]*\)$', '')));
      end if;
      -- (correção da revisão da 7b: fim)
      -- o texto da ação (agenda_acoes.texto, até 400) junta os itens da mesma OS: com a frase da dupla, o item fica em até 320 — sem
      -- caber a frase inteira, a curta (sem os dias e sem quem está na equipe)
      if char_length(v_txt) + 1 + char_length(v_7b_z) > 320 then
        v_7b_n2 := jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n;
        v_7b_z := case
          when coalesce((v_e ->> 'dupla_todos')::boolean, false) then 'O serviço todo pede 2 pessoas: se chamar um ajudante, me diga os dias dele.'
          when v_7b_x <> '' and v_7b_y <> ''
            then format('%s e %s pedem 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'O primeiro meio-dia' else format('Os %s primeiros meios-dias', v_7b_n) end,
                        case when v_7b_n2 = 1 then 'o último' else format('os %s últimos', v_7b_n2) end)
          when v_7b_x <> ''
            then format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_e ->> 'dupla_rot_ini')
          else format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                      case when v_7b_n2 = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_n2) end, v_e ->> 'dupla_rot_fim') end;
      end if;
      v_txt := public._agenda_corta(v_txt || ' ' || v_7b_z, 320);
    end if;
    -- FASE 7b: fim
    v_itens := v_itens || jsonb_build_object(
      'op', 'criar', 'os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
      'tipo', case when v_b ->> 'tipo' = 'reserva' then 'reserva' else v_e ->> 'tipo_os' end,
      'reserva_de', v_b ->> 'reserva_de', 'alocacoes', public._agenda_alocs_do_bloco(v_ctx, v_b),
      'de', v_ini_x, 'ate', v_fim_x, 'fim_antes', v_e ->> 'fim_antes', 'fim_depois', v_fim_dep,
      'atraso_du', case when v_b ->> 'tipo' <> 'reserva' and v_e ->> 'fim_antes' is not null and v_fim_dep > (v_e ->> 'fim_antes')::date
                        then public.agenda_du_entre((v_e ->> 'fim_antes')::date, v_fim_dep) end,
      'condicao_tipo', case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'condicao_tipo' end,
      'critica', v_tipo, 'pergunta_chave', v_chave, 'decisao', v_decisao, 'espera', (v_b ->> 'espera')::boolean,
      'interrupcoes', (v_b ->> 'int')::int, 'meios_do_dono', (v_b ->> 'md')::int, 'fonte', v_e ->> 'fonte', 'dias', v_e -> 'dias',
      'evento_real', (v_e ->> 'evento_real')::boolean, 'fixar_dono', v_e ? 'fixar_de', 'aviso_material', v_aviso,
      'abre', (v_e ->> 'abre')::boolean and v_b ->> 'tipo' <> 'reserva', 'fecha', (v_e ->> 'fecha')::boolean and v_b ->> 'tipo' <> 'reserva',
      'motivos', to_jsonb(array_remove(array[
         case when v_e ->> 'classe' = '1' and not v_e ? 'fixar_de' then 'em andamento ou fixada' end,
         case when v_e ? 'fixar_de' then 'você pediu' end,
         case when (v_e ->> 'evento_real')::boolean then 'replanejado por um imprevisto de hoje ou amanhã' end,
         case when v_b ->> 'tipo' <> 'reserva' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'teto' then 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%' end,
         case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'patio' then 'adiantar no pátio enquanto o bem está fora' end], null)),
      'texto', v_txt, 'aplicado', false);
    -- FASE 7b: (7b P4, §6.4) o item leva a dupla da OS (o texto do cartão e do foco), os meios-dias que pediam 2 e não têm a 2ª pessoa
    -- (dupla_falta [{dia, turno, onde}]) e o sábado usado; só com os modos da 7b
    if v_e ? 'dk' or v_b ? 'sabado' then
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_strip_nulls(jsonb_build_object(
        'dupla', v_e ->> 'dupla_texto', 'dupla_fonte', v_e ->> 'dupla_fonte',
        'dupla_falta', (select jsonb_agg(jsonb_build_object('dia', v_ini + ((f ->> 'h')::int + 1) / 2 - 1,
                                                           'turno', case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end,
                                                           'onde', f ->> 'onde') order by (f ->> 'h')::int)
                          from jsonb_array_elements(v_b -> 'dupla_falta') f),
        'sabado', case when v_b ? 'sabado' then true end)));
    end if;
    -- FASE 7b: fim
    -- CORREÇÃO FASE 6: (C1) item 14: a reserva por teto da OS que precisa do dono (abre, fecha ou o turno dele), com a
    -- capacidade do dono em uso abaixo da carga de todos (_agenda_carga_da_pessoa), diz a parte da semana DELE: "não coube na
    -- sua parte da semana (56%)", e não "na carga de 80%". Sem nada em uso, o item é o de antes, byte a byte.
    if v_b ->> 'reserva_de' = 'teto'
       and (coalesce((v_e ->> 'abre')::boolean, false) or coalesce((v_e ->> 'fecha')::boolean, false)
            or coalesce((v_e ->> 'dt_m')::boolean, false) or coalesce((v_e ->> 'dt_t')::boolean, false))
       and public._agenda_carga_da_pessoa(v_dono) < cf.carga_max then
      v_itens := jsonb_set(v_itens, '{-1,motivos}',
                   (select coalesce(jsonb_agg(case when m #>> '{}' = 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%'
                                                   then to_jsonb('não coube na sua parte da semana ('
                                                                 || public._agenda_num(public._agenda_carga_da_pessoa(v_dono) * 100, 0) || '%)')
                                                   else m end order by o), '[]'::jsonb)
                      from jsonb_array_elements(v_itens -> -1 -> 'motivos') with ordinality t(m, o)));
    end if;
    -- CORREÇÃO FASE 6: fim
  end loop;

  -- A condição e a data-limite das reservas condicionadas (do 1º dia de cada uma: o "compre até" daquele início).
  select coalesce(jsonb_agg(case when i ->> 'reserva_de' = 'condicionada' then
             i || x.c || jsonb_build_object('texto', rtrim(i ->> 'texto', '.') || ' — ' || (x.c ->> 'condicao') || '.')
           else i end order by k), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(v_itens) with ordinality t(i, k)
    cross join lateral (select case when i ->> 'reserva_de' = 'condicionada'
                                    then public._agenda_condicao_da_reserva((i ->> 'os')::uuid, i ->> 'condicao_tipo', (i ->> 'de')::date,
                                                                            v_info -> (i ->> 'os') -> 'pront', p_hoje) end as c) x;

  -- ── 7. O que fica de fora, com quem trava ──
  for v_e in select e from jsonb_array_elements(v_fila) e order by (e ->> 'ordem')::int loop
    v_os := (v_e ->> 'os')::uuid;
    continue when exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'os')::uuid = v_os and i ->> 'op' = 'criar');
    v_x := (v_e ->> 'i')::int;
    v_txt := null;
    v_chave := null;
    if v_x = any (v_xnc) and exists (select 1 from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x) then
      select q ->> 'chave' into v_chave from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x;
      v_txt := format('%s: não cabe até %s — preciso de você.', public._agenda_rotulo_da_os(v_os), public._dia_curto((v_e ->> 'precisa')::date));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'nao_cabe', 'texto', v_txt, 'pergunta_chave', v_chave);
      continue;
    end if;
    if v_x = any (v_sem_q) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                 'motivo', 'sem_encaixe',
                 'texto', format('%s: sem encaixe com a equipe de hoje (nem atrasando outra OS).', public._agenda_rotulo_da_os(v_os)));
      continue;
    end if;
    if (v_e ->> 'classe')::int = 4 then
      v_txt := format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_e ->> 'texto', '.'));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', v_e ->> 'motivo', 'texto', v_txt);
      continue;
    end if;
    continue when coalesce((v_e ->> 'passos')::int, 0) <= 0;
    -- FASE 7b: (7b P4, R4.3(c)) a dupla dita que só saiu da espera da classe 4 por quem vem sob demanda (dupla_sd) e não achou bloco:
    -- vai ao "fora" com o motivo dupla (o da classe 4: o aviso, o foco e o cartão dizem "falta a 2ª pessoa"), com as datas de quem
    -- vem — nunca o "sem lugar" calado.
    if coalesce((v_e ->> 'dupla_sd')::boolean, false)
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and f ->> 'motivo' in ('sem_encaixe', 'sem_reserva')) then
      select public._agenda_lista(array_agg(format('%s só vem %s (%s)', x.nome, public._agenda_dias_texto(x.dias),
                                                  public._agenda_plural(x.n, 'meio-dia', 'meios-dias')) order by x.nome)),
             count(*)::int
        into v_7b_x, v_7b_n
        from (select k.pessoa as nome, k.payee_id, array_agg(distinct k.dia order by k.dia) as dias, count(*)::int as n
                from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
               where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje)
               group by k.pessoa, k.payee_id) x;
      v_txt := format('%s: precisa de %s pessoas em %s e %s: me diga mais dias %s ou chame outro ajudante.',
                      public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                      public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'),
                      coalesce(nullif(v_7b_x, ''), 'quem vem sob demanda não cobre'), case when v_7b_n > 1 then 'deles' else 'dele' end);
      -- (correção da revisão da 7b, achado 22) quando os dias de quem vem sob demanda são todos antes de a OS ficar pronta, o
      -- porquê é a data, não a falta de dias ("… e Mateus só vem seg 09 e qui 12/11 (4 meios-dias), antes de o serviço ficar pronto (qua
      -- 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.")
      v_7bc_est := (public.os_prontidao(v_os, p_hoje) ->> 'est')::date;
      select max(k.dia) into v_7bc_max
        from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
       where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje);
      if v_7bc_est is not null and v_7bc_max is not null and v_7bc_max < v_7bc_est and nullif(v_7b_x, '') is not null then
        v_txt := format('%s: precisa de %s pessoas em %s e %s, antes de o serviço ficar pronto (%s): me diga dias %s a partir de %s ou chame outro ajudante.',
                        public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                        public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'), v_7b_x,
                        public._dia_curto(v_7bc_est), case when v_7b_n > 1 then 'deles' else 'dele' end, public._dia_curto(v_7bc_est));
      end if;
      -- (correção da revisão da 7b: fim)
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'dupla', 'texto', v_txt);
      continue;
    end if;
    -- FASE 7b: fim
    select f ->> 'motivo' into v_tipo from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x limit 1;
    if v_tipo is null then
      select b into v_b from jsonb_array_elements(v_rf -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso';
      if v_b is not null and not coalesce((v_b ->> 'na_janela')::boolean, true) then
        v_tipo := 'depois';
        v_txt := format('%s: começa %s%s.', public._agenda_rotulo_da_os(v_os),
                        public._dia_curto(v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1),
                        coalesce(' (' || (select r ->> 'texto' from jsonb_array_elements(v_info -> v_os::text -> 'pront' -> 'restricoes') r
                                           where r ->> 'tipo' in ('bem', 'nao_antes') limit 1) || ')', ''));
      elsif v_x = any (v_h) then
        v_tipo := 'espera';
        v_txt := format('%s: espera a sua decisão.', public._agenda_rotulo_da_os(v_os));
      end if;
    end if;
    continue when v_tipo is null;
    v_txt := coalesce(v_txt, format('%s: %s.', public._agenda_rotulo_da_os(v_os), case v_tipo
      when 'padrao_do_dono' then 'falta você dizer quais dias fica em campo'
      when 'fixar_nao_cabe' then format('não cabe %s: %s', public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                        public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
      when 'sem_reserva' then rtrim(v_e ->> 'texto', '.') || ' (sem lugar para a reserva nesta semana)'
      when 'so_com_voce' then rtrim(v_e ->> 'texto', '.') || ' (é só com você: entra quando isso estiver respondido)'
      else format('sem encaixe em %s semanas com a equipe de hoje', cf.horizonte_semanas) end));
    v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                           'motivo', v_tipo, 'texto', v_txt);
  end loop;
  -- (as que saíram da carteira e tinham plano)
  v_fora := v_fora || coalesce((
    select jsonb_agg(jsonb_build_object('os', x.os, 'numero', v_info -> x.os::text -> 'pront' ->> 'numero',
             'cliente_curto', v_info -> x.os::text -> 'pront' ->> 'cliente_curto', 'motivo', 'fora_da_carteira',
             'texto', format('%s: %s.', public._agenda_rotulo_da_os(x.os), v_info -> x.os::text -> 'pront' ->> 'estado_texto'))
             order by v_info -> x.os::text -> 'pront' ->> 'numero')
      from (select distinct (c ->> 'os')::uuid as os from jsonb_array_elements(v_canc) c where c ->> 'motivo' = 'os_saiu') x
     where not (x.os = any (v_escopo))), '[]'::jsonb);

  -- ── 8. A carga por pessoa e semana (o publicável sem esperar) ──
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object('nome', p.nome, 'semanas', p.semanas)), '{}'::jsonb) into v_carga
    from (select (v_ctx -> 'pessoas' ->> (pp - 1)) as id, (v_ctx -> 'nomes' ->> (pp - 1)) as nome,
                 jsonb_agg(jsonb_build_object(
                   'semana', v_seg + 7 * (ww - 1),
                   'esperado', (v_ctxf -> 'esperado' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto80', (v_ctxf -> 'teto80' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto100', (v_ctxf -> 'teto100' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'compromisso', (v_ctxf -> 'uso_c' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'reserva', (v_ctxf -> 'uso_r' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1))) order by ww) as semanas
            from generate_series(1, (v_ctx ->> 'np')::int) pp
            cross join generate_series((v_de - v_seg) / 7 + 1, (v_ate - v_seg) / 7 + 1) ww
           group by pp) p;

  -- ── 9. A pontuação (para comparar alternativas) ──
  select jsonb_build_object(
           'atraso_dias', coalesce(sum(greatest((i ->> 'fim_depois')::date - (v_ent -> x.ii ->> 'precisa')::date, 0))
                                     filter (where v_ent -> x.ii ->> 'precisa' is not null), 0),
           'mudancas', (select count(*) from jsonb_array_elements(v_canc) c where not (c ->> 'violada')::boolean and c ->> 'motivo' = 'replanejado'),
           'meios_do_dono', coalesce(sum((i ->> 'meios_do_dono')::int), 0),
           'interrupcoes', coalesce(sum((i ->> 'interrupcoes')::int), 0),
           'fim', coalesce(sum((i ->> 'ate')::date - v_ini), 0))
    into v_pont
    from jsonb_array_elements(v_itens) i
    cross join lateral (select (select e ->> 'i' from jsonb_array_elements(v_fila) e where e ->> 'os' = i ->> 'os') as ii) x
   where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false);
  v_pont := v_pont || jsonb_build_object('total',
    (v_pont ->> 'atraso_dias')::bigint * c_peso_atraso + (v_pont ->> 'mudancas')::bigint * c_peso_mudanca
    + (v_pont ->> 'meios_do_dono')::bigint * c_peso_dono + (v_pont ->> 'interrupcoes')::bigint * c_peso_interr
    + (v_pont ->> 'fim')::bigint * c_peso_fim);

  -- ── 10. Os textos prontos ──
  v_feriados := array(select format('%s é %s', public._agenda_dia_sem_mes(g::date), public.agenda_feriado(g::date))
                        from generate_series(v_de - (extract(isodow from v_de)::int - 1), v_ate, interval '1 day') g
                       where extract(isodow from g)::int <= 5 and public.agenda_feriado(g::date) is not null order by g);
  v_titulo := case when p_escopo = 'semana'
    then format('Semana de %s a %s', to_char(v_de, 'DD'),
                to_char(coalesce((select max(g::date) from generate_series(v_de, v_ate, interval '1 day') g
                                   where public.agenda_dia_util(g::date)), v_ate), 'DD/MM'))
         || coalesce(' (' || nullif(array_to_string(v_feriados, ', '), '') || ')', '')
    else 'Mudanças na agenda' end;
  v_linhas := array(select i ->> 'texto' || case when coalesce((i ->> 'espera')::boolean, false) then ' (espera a sua decisão)' else '' end
                      from jsonb_array_elements(v_itens) with ordinality t(i, k)
                     order by i ->> 'op' = 'cancelar', (i ->> 'de')::date, i ->> 'numero' collate "C", k);
  v_tfora := array(select f ->> 'texto' from jsonb_array_elements(v_fora) with ordinality t(f, k) order by k);
  v_textos := jsonb_build_object('titulo', v_titulo, 'linhas', to_jsonb(v_linhas), 'fora', to_jsonb(v_tfora),
    'carga', to_jsonb(array(
      select format('%s: %s de %s meios-dias de serviço na semana de %s',
                    case when p.key::uuid is not distinct from v_dono then 'Você' else p.value ->> 'nome' end,
                    s ->> 'compromisso', s ->> 'teto80', to_char((s ->> 'semana')::date, 'DD/MM'))
        from jsonb_each(v_carga) p, jsonb_array_elements(p.value -> 'semanas') s
       where (s ->> 'esperado')::numeric > 0
       order by (s ->> 'semana')::date, p.key::uuid is not distinct from v_dono desc, p.value ->> 'nome')),
    'resumo', format('%s: %s, %s.', v_titulo,
                     public._agenda_plural((select count(distinct i ->> 'os')::int from jsonb_array_elements(v_itens) i
                                             where i ->> 'op' = 'criar' and not (i ->> 'espera')::boolean), 'serviço marcado', 'serviços marcados'),
                     public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
  -- CORREÇÃO 29/10 (P3): o marcado firme e o reservado separados no resumo e no título da semana (com a agenda automática
  -- ligada). A reserva só guarda o lugar da equipe (nada está marcado até a condição dela se cumprir), e o resumo de antes
  -- contava como "serviço marcado" toda OS que entra: com só a reserva do Lenine, "1 serviço marcado". Com reserva no que
  -- entra (sem o que espera a decisão), o resumo diz quem: "1 reservado (Lenine), nada marcado firme, 10 de fora"; e o título
  -- da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme"): é ele que abre o
  -- "Publiquei a semana de …" da aplicação, do que mudou e do fechamento, que listam as OS logo depois. A OS com algum
  -- meio-dia firme conta como marcada. No resumo, o nome curto do cliente, com o número quando o nome se repete ("Kalmar
  -- OS-00032"); até 3 nomes, depois "e mais N". Sem reserva, ou fora de ligado, os dois são os de antes, byte a byte.
  if v_modo = 'ligado' then
    select coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where x.firme), '{}'::text[]),
           coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where not x.firme), '{}'::text[])
      into v_marc, v_resv
      from (select y.numero, y.de, y.firme,
                   case when count(*) over (partition by y.curto) > 1 then concat_ws(' ', y.curto, y.numero) else y.curto end as nome
              from (select min(i ->> 'numero') as numero, min((i ->> 'de')::date) as de, bool_or(i ->> 'tipo' <> 'reserva') as firme,
                           coalesce(public._agenda_nome_curto(min(i ->> 'cliente_curto')), min(i ->> 'numero')) as curto
                      from jsonb_array_elements(v_itens) i
                     where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false)
                     group by i ->> 'os') y) x;
  end if;
  if cardinality(v_resv) > 0 then
    v_contagem := case when cardinality(v_marc) > 0
                       then format('%s (%s), %s (%s)',
                                   public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                   public._agenda_lista(v_marc, 3),
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                       else format('%s (%s), nada marcado firme',
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                  end;
    v_textos := v_textos || jsonb_build_object('resumo', format('%s: %s, %s.', v_titulo, v_contagem,
                                                               public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
    if p_escopo = 'semana' then
      v_titulo := v_titulo || ' — '
                  || case when cardinality(v_marc) > 0
                          then format('%s, %s', public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                      public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                          else format('%s, nada marcado firme', public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                     end;
      v_textos := v_textos || jsonb_build_object('titulo', v_titulo);
    end if;
  end if;
  -- CORREÇÃO 29/10 (P3): fim
  v_texto := v_titulo
    || coalesce(E'\n' || nullif(array_to_string(array(select '• ' || x from unnest(v_linhas) x), E'\n'), ''), E'\nNada a mudar.')
    || coalesce(E'\nFora: ' || nullif(array_to_string(v_tfora, '; '), ''), '')
    || case when p_persistir then '' else E'\nÉ simulação: não muda nada.' end;

  -- FASE 7b: (7b P4, §6.3, R4.3(a)4) em teste, o que a 7b faria e não fez — o sábado ("Em teste: para cumprir o prazo de Vanderlei
  -- (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu.") e a dupla de 1 pessoa ("Em teste: no Lenine eu pediria
  -- um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas."): textos.em_teste e no fim do texto.
  for v_7b_b in select e from jsonb_array_elements(coalesce(v_rf -> 'sab_teste', '[]'::jsonb)) e loop
    v_7b_e := v_ent -> (v_7b_b ->> 'i');
    select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
      from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) a
     where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
    v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                           from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) with ordinality t(a, o)
                                          where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                         order by y.o);
    v_7b_teste := v_7b_teste || case when v_7b_e ? 'prazo'
      then format('Em teste: para cumprir o prazo de %s (%s), eu usaria %s de manhã com %s, que %s.',
                  public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'), public._dia_curto((v_7b_e ->> 'prazo')::date),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end)
      else format('Em teste: %s terminaria antes com %s de manhã (%s %s).', public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end) end;
  end loop;
  if cf.modo_dupla = 'sombra' then
    for v_7b_b in select b from jsonb_array_elements(v_rf -> 'colocadas') b
                   where b ? 'dupla_falta' and jsonb_array_length(b -> 'dupla_falta') > 0 and coalesce((b ->> 'na_janela')::boolean, true)
                     and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso') loop
      v_7b_e := v_ent -> (v_7b_b ->> 'i');
      v_7b_teste := v_7b_teste || format('Em teste: no %s eu pediria um ajudante em %s: %s pede 2 pessoas.',
        public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
        public._agenda_lista(array(
          select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ' (manhã e tarde)'
                                                when bool_or(z.t = 'manha') then ' (manhã)' else ' (tarde)' end
            from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                    from jsonb_array_elements(v_7b_b -> 'dupla_falta') f) z
           group by z.d order by z.d)),
        coalesce(case when coalesce((v_7b_e ->> 'dupla_todos')::boolean, false) then v_7b_e ->> 'dupla_rot_todos' end,
                 nullif(public._agenda_lista(array_remove(array[nullif(v_7b_e ->> 'dupla_rot_ini', ''), nullif(v_7b_e ->> 'dupla_rot_fim', '')], null)), ''),
                 'a tarefa'));
    end loop;
  end if;
  if cardinality(v_7b_teste) > 0 then
    v_textos := v_textos || jsonb_build_object('em_teste', to_jsonb(v_7b_teste));
    v_texto := v_texto || E'\n' || array_to_string(v_7b_teste, E'\n');
  end if;
  -- FASE 7b: fim
  -- ── 11. A validação: proposta inválida nunca sai ──
  v_viol := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', v_r), p_hoje, p_agora, false,
              (select jsonb_object_agg(k, x -> 'pront') from jsonb_each(v_info) t(k, x)));
  if jsonb_array_length(v_viol) > 0 then
    raise exception 'agenda_propor: a proposta saiu inválida (erro do motor): %', v_viol::text
      using errcode = 'P0001', detail = left(v_texto, 2000);
  end if;

  -- ── 12. Persistir ──
  if p_persistir then
    -- a aberta anterior do mesmo escopo e modo (e das mesmas OS, fora da semana) fica obsoleta; as alocações dela saem
    for v_q in
      select to_jsonb(pr) from public.agenda_propostas pr
       where pr.estado = 'aberta' and pr.escopo = p_escopo and pr.modo = v_modo
         and (p_escopo = 'semana' or pr.os_alvo && v_escopo)
       order by pr.criada_em, pr.id
    loop
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'refeita' where id = (v_q ->> 'id')::uuid;
      delete from public.agenda_alocacoes where proposta_id = (v_q ->> 'id')::uuid and estado = 'proposta';
    end loop;
    v_pid := gen_random_uuid();
    -- os ids das alocações novas entram no item (é por eles que o aplicar publica)
    select coalesce(jsonb_agg(case when i ->> 'op' = 'criar'
             then i || jsonb_build_object('alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                                                          from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)))
             else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
    v_expira := least(p_agora + cf.proposta_validade,
                      coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca')))
                                  from jsonb_array_elements(v_itens) i, jsonb_array_elements(i -> 'alocacoes') a
                                 where i ->> 'op' = 'criar'), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, p_escopo, daterange(v_de, v_ate, '[]'), v_escopo, v0, v_modo, 'aberta', v_itens, v_fora, v_carga, v_textos,
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', p_de, 'p_ate', p_ate, 'p_os', to_jsonb(p_os),
                               'p_restricoes', v_r, 'escopo', p_escopo, 'origem', p_origem, 'de', v_de, 'ate', v_ate),
            v_pont, p_origem, p_autor, p_agora, v_expira);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         reserva_de, condicao, condicao_tipo, condicao_ate, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, (i ->> 'os')::uuid, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno',
           a ->> 'presenca', i ->> 'tipo', 'proposta', case when (i ->> 'fixar_dono')::boolean then 'dono' else 'motor' end, v_pid,
           i ->> 'reserva_de', case when a ->> 'presenca' = 'turno' then i ->> 'condicao' end,
           case when a ->> 'presenca' = 'turno' then i ->> 'condicao_tipo' end,
           case when a ->> 'presenca' = 'turno' then (i ->> 'condicao_ate')::date end,
           coalesce(i -> 'motivos', '[]'::jsonb), p_agora
      from jsonb_array_elements(v_itens) with ordinality t(i, k), jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)
     where i ->> 'op' = 'criar'
     order by k, j;
    -- as perguntas críticas (a mesma pergunta não abre duas vezes; a de uma versão anterior da mesma OS sai)
    for v_q in select q from jsonb_array_elements(v_perg) q loop
      update public.agenda_perguntas p
         set estado = 'descartada', resolvida_motivo = 'a agenda mudou: a pergunta foi refeita'
       where p.estado = 'aberta' and p.modo = v_modo and p.tipo = v_q ->> 'tipo'
         and p.service_order_id = (v_q ->> 'service_order_id')::uuid and p.chave <> v_q ->> 'chave';
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao,
                                           recomendacao_texto, proposta_id, versao_base, modo, criada_em)
      values (v_q ->> 'tipo', v_q ->> 'chave', (v_q ->> 'service_order_id')::uuid,
              array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x), null, (v_q ->> 'perda_em')::date,
              v_q ->> 'texto', v_q -> 'opcoes', (v_q ->> 'recomendacao')::smallint, v_q ->> 'recomendacao_texto', v_pid, v0, v_modo, p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true, 'proposta_id', v_pid, 'versao_base', v0, 'escopo', p_escopo, 'modo', v_modo,
    'periodo', jsonb_build_object('de', v_de, 'ate', v_ate), 'simulacao', not p_persistir,
    'itens', v_itens, 'fora', v_fora, 'carga', v_carga,
    'perguntas', (select coalesce(jsonb_agg(q - 'x' order by q ->> 'chave'), '[]'::jsonb) from jsonb_array_elements(v_perg) q),
    'pontuacao', v_pont, 'textos', v_textos, 'texto', v_texto);
end;
$function$;

comment on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada, a criticidade de cada compromisso colocado é refeita com p_violadas = _agenda_zona_fora (o que não conta para o dia já avisado: a violação, o resto do meio-dia dela e o que volta igual neste encaixe; nunca o fixado pelo dono): o meio-dia de um dia já dito à equipe ou ao cliente que sairia sem ter ficado impossível, e o fim que passaria do prometido firme, viram as críticas dia_avisado e dia_prometido, com a pergunta e a recomendação de sempre. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, §6.3, R4.3): só com os modos da 7b — a entrada da fila ganha dk (as pessoas dos passos que restam), dk_dono_conta, dupla_fonte e o texto da dupla; da dupla inferida, passos1 (o bloco de 1 pessoa: ligado, a soma do dk; em teste, os passos de antes), dupla_ni/dupla_nf/dupla_todos e os nomes do que a tarefa pede; prazo_h (o índice da tarde de least(precisa_ate, o prometido firme)) e prazo; e dupla_sd na dupla dita que só passa pela régua dos técnicos com quem vem sob demanda. p_par ganha sab_modo, sab_politica, dupla_modo e dupla_espera. Ligado, o item com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael se ofereceu), para cumprir o prazo de qua 18/11.") e o bloco de 1 pessoa da dupla inferida diz em que meios-dias chamar um ajudante (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."); o item leva dupla (o texto do cartão), dupla_fonte, dupla_falta [{dia, turno, onde}] e sabado. A dupla dita com dupla_sd sem bloco vai ao fora com o motivo dupla ("Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante."), nunca sem_encaixe. Em teste, textos.em_teste e o fim do texto: "Em teste: para cumprir o prazo de Vanderlei (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu." e "Em teste: no Lenine eu pediria um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.". Sem os modos da 7b, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 22 e 23): o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa ("ex.: Mateus vem qua 18 e qui 19/11"); a dupla dita que só passou da espera por quem vem sob demanda e cujos dias livres são todos antes de a OS ficar pronta (os_prontidao.est) vai ao fora dupla com "…, antes de o serviço ficar pronto (qua 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.".';

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar).
revoke all on function public._agenda_ver_gestor(date), public.agenda_livre_de_verdade(date, timestamptz) from public, anon;
grant execute on function public._agenda_ver_gestor(date), public.agenda_livre_de_verdade(date, timestamptz) to authenticated, service_role;
revoke all on function public._agenda_quem_chamar(date, timestamptz), public._agenda_gestor_dupla(date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text) from public, anon;
grant execute on function public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)
  to authenticated, service_role;
revoke all on function public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.agenda_resposta_da_equipe(text, text, text, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public.agenda_resposta_da_equipe(text, text, text, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  to service_role;
revoke all on function public._agenda_linhas_do_fechamento(date), public._agenda_carga_da_pessoa(uuid) from public, anon;
grant execute on function public._agenda_linhas_do_fechamento(date), public._agenda_carga_da_pessoa(uuid) to authenticated, service_role;
revoke all on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  to service_role;
