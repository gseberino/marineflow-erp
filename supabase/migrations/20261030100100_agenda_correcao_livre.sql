-- Agenda de Produção, correção de 29/10 (pacote P2): "quando tenho agenda livre" passa a ter UMA resposta.
-- (3 funções novas; 1 reescrita; 2 recriadas; nenhuma tabela, coluna, CHECK nem parâmetro novo; nenhum dado muda)
--
-- NÃO APLICADA. Montada por scratchpad/agenda-pesquisa/p2c/montar-migration.mjs (edite as partes ou o montador, nunca este
-- .sql). agenda_simular e agenda_ver são o corpo da definição MAIS NOVA (conferido com grep: agenda_simular só em
-- 20261024160500; agenda_ver por último em 20261029100800, e nenhuma migration 20261030* a recria), com as mudanças só em
-- blocos "-- CORREÇÃO 29/10 (P2): … -- CORREÇÃO 29/10 (P2): fim"; fora deles nenhuma linha muda (o K de
-- supabase/tests/agenda_correcao_2910_p2.sql confere). agenda_livre_de_verdade é REESCRITA (o corpo inteiro é novo: a
-- simulação da carteira inteira, que dizia "a equipe já está livre", saiu); a assinatura, as portas, a conferência de quem
-- vê e o contrato com quem chama ({fonte: 'simulacao', texto} em ligado; {fonte: 'projecao'} fora dele) ficam.
--
-- ═══ POR QUE ═══ (auditoria de 29/10, leitores "entrega" e "crítica")
--   Às 17:15 de qui 29/10, com a agenda automática ligada e o plano com só a reserva do Lenine (qui 05, sex 06 e ter 10/11,
--   João e Roberto), a mesma pergunta tinha TRÊS respostas:
--   1. *livre* começava pela fila em faixa da Fase 1: "Livre ela não está: há 7 serviços aprovados, uns 18 a 34 dias de
--      equipe — de 3 a 6 semanas…" (_agenda_resumo: a fila ÷ o ritmo das diárias, contando a OS travada como se ocupasse
--      a equipe);
--   2. e logo depois dizia "Livre de verdade (pela simulação da agenda): … a equipe já está livre" (agenda_livre_de_verdade:
--      simulava a carteira inteira e, sem nada pronto, achava a equipe vazia, sem olhar a reserva nem o teto de cada um);
--   3. "um serviço de 2 dias, quando dá?" (agenda_ver simular → agenda_simular) respondia "no fim da fila, começa entre
--      qui 26/11 e qui 17/12", pela mesma projeção da Fase 1, que nunca passou a usar o motor.
--
-- ═══ O QUE MUDA ═══ (só com a agenda automática ligada, modo_proposta = 'ligado'; fora dela tudo sai igual, byte a byte)
--   1. _agenda_meios_texto (nova): meios-dias em palavras ("nada", "meio dia", "1 dia e meio", "3 dias").
--   2. _agenda_grade_de_agora (nova, só service_role): a janela e a grade que a agenda_propor monta para encaixar uma OS
--      (da segunda desta semana ao fim do horizonte, o plano vigente inteiro na grade: o marcado e o reservado).
--   3. agenda_livre_de_verdade (reescrita): o livre pelo plano e pelo teto de cada pessoa. Para cada uma das 3 semanas a
--      partir do 1º dia que a agenda ainda pode mudar, quantos meios-dias cada pessoa ainda pega = o menor entre o teto de
--      compromisso menos o compromisso, o teto de 100% menos compromisso e reserva, e os meios-dias livres dela na grade (a
--      mesma conta que o encaixe faz). Diz também o que ocupa a equipe (o plano, com quem vai), o que não ocupa ninguém até
--      destravar (os travados, os parados no cliente) e, sem os dias do dono em campo, que ele fica de fora da conta.
--      texto = a linha da semana e da tela ("Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de
--      09/11, …"); texto_completo = a resposta do *livre*.
--   4. agenda_encaixe_do_novo (nova): o serviço que ainda não existe ("2 dias, com o Roberto") no encaixe do motor
--      (_agenda_encaixar, só leitura) sobre a grade de agora, como a OS nova entraria: compromisso, o teto de 80%, a regra da
--      presença do dono, a equipe dita ou a sugerida, todos os inícios até o horizonte. Sem caber na carga de sempre, tenta
--      acima dela (100%). O dono "o tempo todo" sem os dias dele em campo o motor não marca: a resposta diz isso e simula com
--      ele só abrindo e fechando. Nada é gravado.
--   5. agenda_simular (de 20261024160500): em ligado, o 1º dia que cabe vem da 4 ("pelo plano de agora, cabe em sex 13 e
--      ter 17/11, com João e Roberto; você abre e fecha. É simulação: não marca nada."), no lugar de "no fim da fila…".
--   6. agenda_ver (de 20261029100800): o foco livre em ligado é só o texto_completo da 3 (sem a fila em faixa); na semana
--      (*agenda*, *agenda semana que vem*), a linha da 3 vai no lugar da fila em faixa, logo depois do marcado, e a linha do
--      livre lá de baixo sai.
--   Não muda: agenda_semana e _agenda_semana_de (o texto delas é o mesmo; quem troca as linhas é a agenda_ver), o fechamento
--   das 17:30, a projeção da Fase 1 fora de ligado, agenda_ctp ("se o cliente aprovar hoje") e o motor (nenhuma função dele
--   é recriada: a 2 e a 4 só chamam _agenda_contexto e _agenda_encaixar).
--
-- Ordem de ligar: depois das migrations das Fases 0 a 6 (todas em produção) e da 20261030100000 (P1); nenhuma chave nova.
-- Aplicar com o OK nomeado do dono. Prova: supabase/tests/agenda_correcao_2910_p2.sql (bancada).
--
-- DESFAZER: recriar agenda_simular, agenda_ver e agenda_livre_de_verdade com o corpo da migration de onde cada uma veio
-- (agenda_simular: 20261024160500; agenda_ver: 20261029100800; agenda_livre_de_verdade: 20261026100500); as três novas
-- podem ficar (ninguém as chama sem as recriadas desta migration) ou sair com
--   drop function if exists public.agenda_encaixe_do_novo(numeric, jsonb, text, date);
--   drop function if exists public._agenda_grade_de_agora(date);
--   drop function if exists public._agenda_meios_texto(integer);

-- ── 1. Meios-dias em palavras ───────────────────────────────────────────────────────────────────────────────
-- 0 → "nada"; 1 → "meio dia"; 2 → "1 dia"; 3 → "1 dia e meio"; 6 → "3 dias"; 7 → "3 dias e meio".
create or replace function public._agenda_meios_texto(p_meios integer)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_meios is null or p_meios <= 0 then 'nada'
              when p_meios = 1 then 'meio dia'
              when p_meios % 2 = 0 then public._agenda_plural(p_meios / 2, 'dia', 'dias')
              else public._agenda_plural(p_meios / 2, 'dia', 'dias') || ' e meio' end;
$function$;

comment on function public._agenda_meios_texto(integer) is
  'Agenda de Produção (correção de 29/10, P2): meios-dias em palavras — 0 "nada", 1 "meio dia", 2 "1 dia", 3 "1 dia e meio", 6 "3 dias", 7 "3 dias e meio".';

-- ── 2. A grade do motor de agora ──────────────────────────────────────────────────────────────────────────────
-- _agenda_grade_de_agora(p_hoje): a janela e a grade que a agenda_propor monta para encaixar uma OS (escopo 'os'): da
-- segunda desta semana ao domingo depois do horizonte (horizonte_semanas a partir do 1º dia que a agenda ainda pode mudar:
-- o dia útil depois do congelado), com o plano vigente inteiro na grade (o compromisso e a reserva, nada ignorado).
-- {ini (a segunda desta semana), cong (o último dia congelado), de (o 1º dia que a agenda ainda pode mudar), hor, fim,
-- min_h (o 1º meio-dia depois do congelado, como v_minh_n da agenda_propor), ctx (_agenda_contexto)}. Só lê.
create or replace function public._agenda_grade_de_agora(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_cong date;
  v_ini  date;
  v_de   date;
  v_hor  date;
  v_fim  date;
begin
  if p_hoje is null then
    raise exception '_agenda_grade_de_agora: sem o dia de hoje' using errcode = '22004';
  end if;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_ini := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_de := public.agenda_somar_du(v_cong, 1);
  v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, v_de + 7 * cf.horizonte_semanas);
  v_fim := v_hor + (7 - extract(isodow from v_hor)::int);
  return jsonb_build_object('ini', v_ini, 'cong', v_cong, 'de', v_de, 'hor', v_hor, 'fim', v_fim,
                            'min_h', 2 * (v_cong + 1 - v_ini) + 1,
                            'ctx', public._agenda_contexto(v_ini, v_fim, p_hoje, '{}'::uuid[], '{}'::uuid[]));
end;
$function$;

comment on function public._agenda_grade_de_agora(date) is
  'Agenda de Produção (correção de 29/10, P2): a janela e a grade do motor para encaixar uma OS hoje, como a agenda_propor escopo ''os'' monta (da segunda desta semana ao domingo depois do horizonte; o plano vigente inteiro na grade, o marcado e o reservado). {ini, cong, de (o 1º dia que a agenda ainda pode mudar), hor, fim, min_h (o 1º meio-dia depois do congelado), ctx (_agenda_contexto)}. Invoker, STABLE, só o service_role (como as peças do motor): quem a chama é a agenda_livre_de_verdade e a agenda_encaixe_do_novo, que conferem quem vê.';

-- ── 3. O livre pelo plano e pelo teto de cada pessoa (reescrita) ───────────────────────────────────────────────
-- agenda_livre_de_verdade(p_hoje, p_agora), com a agenda automática ligada (fora dela, {fonte: 'projecao'}, e quem chama usa
-- a frase da Fase 1, como antes). Para cada uma das 3 semanas a partir do 1º dia que a agenda ainda pode mudar, quantos
-- meios-dias cada pessoa ainda pega num serviço novo — a mesma conta do encaixe (_agenda_tentar_bloco): o menor entre
-- teto80 − compromisso, teto100 − compromisso − reserva e os meios-dias dela livres na grade (vem, dia útil, depois do
-- congelado, sem outra OS nem reserva). O dono só entra com os dias dele em campo; sem eles, a frase diz que ele fica de
-- fora da conta. Depois: o que ocupa a equipe (o plano de hoje ao sábado da última semana, por OS, com quem vai), o que não
-- ocupa ninguém até destravar (a carteira fora do plano: travados, esperando o dono, parados no cliente, em espera; o
-- pronto que ainda não tem lugar; o em andamento sem dia no plano) e como perguntar de um serviço novo.
--   texto           a linha da semana (*agenda*) e da tela: "Livre de verdade: na semana de 03/11, Roberto 1 dia e meio,
--                   João nada; na de 09/11, Roberto 3 dias, João 1 dia."
--   texto_completo  a resposta do *livre* (até texto_max).
-- 'fonte' continua 'simulacao' em ligado: é o sinal que a agenda_ver e a agenda_tela_semana leem para usar o texto daqui.
-- Nada é gravado.
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
  v_txt := public._agenda_juntar(v_lin, cf.texto_max);
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
  'Agenda de Produção (Fase 3, P6; REESCRITA na correção de 29/10, P2): "quando a gente fica livre de verdade?" pelo plano e pelo teto de cada pessoa — só com modo_proposta ligado (fora disso {fonte: projecao}: quem chama usa a frase da Fase 1). Para cada uma das 3 semanas a partir do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado), os meios-dias que cada pessoa ainda pega num serviço novo, a mesma conta do encaixe: o menor entre teto80 − compromisso, teto100 − compromisso − reserva e os meios-dias dela livres na grade (_agenda_grade_de_agora: o marcado e o reservado ocupam); o dono só com os dias dele em campo (sem eles, voce_fora e a frase "Você fica de fora da conta"). Depois, o que ocupa a equipe (o plano de hoje ao sábado da última semana, por OS, com quem fica o turno), o que não ocupa ninguém até destravar (a carteira fora do plano: travados, esperando o dono, parados no cliente, em espera; o pronto sem lugar; o em andamento sem dia) e como perguntar de um serviço novo. {fonte: simulacao (o sinal de "use o texto daqui" para a agenda_ver e a agenda_tela_semana), base: plano, de, ate, semanas[{seg, de, ate, rotulo, pessoas[{payee_id, nome, eh_dono, meios, celulas, teto, compromisso, reserva}], texto}], voce_fora, ocupa[{os, numero, reserva, dias, pessoas, texto}], nao_ocupam{travados, prontos, andamento, parados, em_espera}, texto (a linha da semana e da tela: "Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia."), texto_completo (a resposta do *livre*, até texto_max), ms}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role.';

-- ── 4. Um serviço novo no encaixe do motor ─────────────────────────────────────────────────────────────────
-- agenda_encaixe_do_novo(p_dias, p_gente, p_dono, p_hoje): o serviço que ainda não existe, como uma OS nova entraria no
-- encaixe (_agenda_encaixar, só leitura) sobre a grade de agora (_agenda_grade_de_agora: o marcado e o reservado ocupam):
-- compromisso (classe 2), a partir do 1º dia que a agenda ainda pode mudar, todos os inícios até o horizonte, o teto de
-- compromisso (sem caber, tenta acima dele, até 100%). p_gente é a lista que a agenda_simular resolve
-- ([{payee_id, nome, eh_dono, turnos (dia|manha|tarde)}]): o dono nela fica o turno dele; os outros são os ditos por turno;
-- sem ninguém, equipe_sugerida pessoas por turno (o motor escolhe quem está livre). A presença do dono: p_dono quando dito;
-- senão o turno dele quando está na lista; senão ele abre e fecha (o padrão da regra). Dono o turno inteiro sem os dias
-- dele em campo o motor não marca (padrao_do_dono): simula com ele só abrindo e fechando e a frase diz por quê. Meios-dias:
-- dias × 2 (quem só vem num turno: 1 por dia). A pessoa que não está na grade (sem os dias na agenda) para a conta.
-- {ok, cabe, acima (só coube acima da carga de sempre), so_pontas, motivo, de, ate, dias, pessoas, pontas, horizonte,
-- meios_por_semana[{payee_id, seg, meios}], texto (o fim da frase da agenda_simular: "pelo plano de agora, cabe em sex 13
-- e ter 17/11, com João e Roberto; você abre e fecha. É simulação: não marca nada.")}. Nada é gravado.
create or replace function public.agenda_encaixe_do_novo(p_dias numeric, p_gente jsonb default '[]'::jsonb,
                                                         p_dono text default null,
                                                         p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_lista  jsonb := case when jsonb_typeof(coalesce(p_gente, '[]'::jsonb)) = 'array' then coalesce(p_gente, '[]'::jsonb)
                         else '[]'::jsonb end;
  v_g      jsonb;
  v_ctx    jsonb;
  v_ini    date;
  v_de     date;
  v_hor    date;
  v_pes    uuid[];
  v_nomes  text[];
  v_dono   int;
  v_padrao boolean;
  v_pm     int[] := '{}';
  v_pt     int[] := '{}';
  v_dtm    boolean := false;
  v_dtt    boolean := false;
  v_abre   boolean := false;
  v_fora   text[] := '{}';
  v_dm     int;
  v_dtd    int;
  v_passos int;
  v_e      jsonb;
  v_par    jsonb;
  v_r      jsonb;
  v_b      jsonb;
  v_acima  boolean := false;
  v_pontas_so boolean := false;
  v_dias   date[] := '{}';
  v_quem   text;
  v_pontas text;
  v_trocados text[] := '{}';
  v_bt     text;
  v_txt    text;
  v_msem   jsonb := '[]'::jsonb;
  e        jsonb;
  q        int;
begin
  if p_hoje is null then
    raise exception 'agenda_encaixe_do_novo: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_dias is null or p_dias <= 0 then
    raise exception 'agenda_encaixe_do_novo: sem os dias do serviço' using errcode = '22023';
  end if;
  if p_dono is not null and p_dono not in ('abre_e_fecha', 'sempre', 'nunca') then
    raise exception 'agenda_encaixe_do_novo: presença do dono "%" não existe (abre_e_fecha, sempre ou nunca)', p_dono
      using errcode = '22023';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;

  v_g := public._agenda_grade_de_agora(p_hoje);
  v_ctx := v_g -> 'ctx';
  v_ini := (v_g ->> 'ini')::date;
  v_de := (v_g ->> 'de')::date;
  v_hor := (v_g ->> 'hor')::date;
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') with ordinality t(x, o) order by o);
  v_nomes := array(select x from jsonb_array_elements_text(v_ctx -> 'nomes') with ordinality t(x, o) order by o);
  v_dono := coalesce((v_ctx ->> 'dono')::int, 0);
  v_padrao := coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false);

  -- Quem vai: o dono fica o turno dele; os outros pelo lugar na grade, por turno ("dia" vale nos dois).
  for e in select x from jsonb_array_elements(v_lista) with ordinality t(x, o) order by o loop
    if coalesce((e ->> 'eh_dono')::boolean, false) then
      v_dtm := v_dtm or coalesce(e ->> 'turnos', 'dia') in ('dia', 'manha');
      v_dtt := v_dtt or coalesce(e ->> 'turnos', 'dia') in ('dia', 'tarde');
      continue;
    end if;
    q := array_position(v_pes, nullif(e ->> 'payee_id', '')::uuid);
    if q is null then
      v_fora := v_fora || coalesce(e ->> 'nome', 'essa pessoa');
      continue;
    end if;
    if coalesce(e ->> 'turnos', 'dia') in ('dia', 'manha') and not (q = any (v_pm)) then v_pm := v_pm || q; end if;
    if coalesce(e ->> 'turnos', 'dia') in ('dia', 'tarde') and not (q = any (v_pt)) then v_pt := v_pt || q; end if;
  end loop;
  if cardinality(v_fora) > 0 then
    return jsonb_build_object('ok', true, 'cabe', false, 'motivo', 'sem_dias', 'sem_dias', to_jsonb(v_fora),
      'texto', format('não sei em que dias %s %s, então não consigo encaixar. É simulação: não marca nada.',
                      public._agenda_lista(v_fora, null), case when cardinality(v_fora) = 1 then 'vem' else 'vêm' end));
  end if;

  -- A presença do dono: a dita; sem ela, o turno dele quando está na lista; senão ele abre e fecha (o padrão da regra).
  if p_dono is not null then
    v_dtm := p_dono = 'sempre';
    v_dtt := v_dtm;
    v_abre := p_dono = 'abre_e_fecha';
  elsif not (v_dtm or v_dtt) then
    v_abre := true;
  end if;
  -- Quantos da equipe por turno: os ditos; sem ninguém dito, a equipe sugerida (o dono no turno é uma das pessoas).
  if jsonb_array_length(v_lista) = 0 then
    v_dm := greatest(cf.equipe_sugerida - case when v_dtm then 1 else 0 end, 0);
    v_dtd := greatest(cf.equipe_sugerida - case when v_dtt then 1 else 0 end, 0);
  else
    v_dm := cardinality(v_pm);
    v_dtd := cardinality(v_pt);
  end if;
  -- O dono o turno inteiro sem os dias dele em campo: o motor não marca (padrao_do_dono). Simula com ele só abrindo e
  -- fechando, e a frase diz por quê.
  if (v_dtm or v_dtt) and not v_padrao then
    v_pontas_so := true;
    v_dtm := false;
    v_dtt := false;
    v_abre := true;
  end if;
  v_abre := v_abre and v_dono > 0;
  -- Os meios-dias: dias × 2 com gente nos dois turnos; quem só vem num turno faz 1 por dia.
  v_passos := case when (v_dm > 0 or v_dtm) and (v_dtd > 0 or v_dtt) then ceil(p_dias * 2)::int
                   when v_dm > 0 or v_dtm or v_dtd > 0 or v_dtt then ceil(p_dias)::int
                   else 0 end;
  if v_passos = 0 then
    return jsonb_build_object('ok', true, 'cabe', false, 'motivo', 'sem_equipe', 'so_pontas', v_pontas_so,
      'texto', case when v_pontas_so
                    then 'com você o tempo todo não consigo encaixar: não sei em que dias você fica em campo, e sem você não fica ninguém da equipe no serviço. É simulação: não marca nada.'
                    else 'não fica ninguém da equipe no serviço: diga com quem. É simulação: não marca nada.' end);
  end if;

  -- A OS nova na fila do encaixe: compromisso (classe 2), a partir do 1º dia que a agenda ainda pode mudar, o índice depois
  -- das OS da grade (não é frente de nenhuma), sem bem fora, sem pátio, sem reserva.
  v_e := jsonb_build_object(
    'i', jsonb_array_length(coalesce(v_ctx -> 'oss', '[]'::jsonb)) + 1, 'os', null, 'numero', null,
    'classe', 2, 'ordem', 1, 'tipo_os', 'execucao', 'passos', v_passos,
    'abre', v_abre, 'fecha', v_abre, 'dt_m', v_dtm, 'dt_t', v_dtt, 'dm', v_dm, 'dtd', v_dtd,
    'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', 0,
    'est', v_de - v_ini + 1, 'est_cond', v_de - v_ini + 1, 'est_patio', v_de - v_ini + 1, 'min_h', (v_g ->> 'min_h')::int,
    'bem', '[]'::jsonb, 'patio_passos', 0, 'patio_bem', '[]'::jsonb,
    'tem_reserva', false, 'tem_fixada', false, 'evento_real', false, 'teto100', false, 'dono_impossivel', false);
  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', (v_ctx ->> 'nd')::int,
                              'semana', false, 'acima', false);
  v_r := public._agenda_encaixar(v_ctx, jsonb_build_array(v_e), v_par);
  v_b := (select b from jsonb_array_elements(coalesce(v_r -> 'colocadas', '[]'::jsonb)) b where b ->> 'tipo' = 'compromisso' limit 1);
  if v_b is null then
    v_r := public._agenda_encaixar(v_ctx, jsonb_build_array(v_e), v_par || jsonb_build_object('acima', true));
    v_b := (select b from jsonb_array_elements(coalesce(v_r -> 'colocadas', '[]'::jsonb)) b where b ->> 'tipo' = 'compromisso' limit 1);
    v_acima := v_b is not null;
  end if;

  if v_b is not null then
    -- os dias do bloco (as pontas do dono também), quem fica o turno (você primeiro, depois na ordem em que entra) e as pontas
    v_dias := array(select distinct v_ini + (h + 1) / 2 - 1 from unnest(public._agenda_ints(v_b -> 'h')) h order by 1);
    select public._agenda_lista(array_agg(case when z.p = v_dono then 'você' else v_nomes[z.p] end
                                          order by z.p = v_dono desc, z.h0, z.p), null)
      into v_quem
      from (select t.p, min(t.h) as h0
              from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
             where t.pr = 0 group by t.p) z;
    select case when bool_or(t.pr = 1) and bool_or(t.pr = 2) then 'você abre e fecha'
                when bool_or(t.pr = 1) then 'você abre'
                when bool_or(t.pr = 2) then 'você fecha' end
      into v_pontas
      from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
     where t.pr in (1, 2);
    -- os meios-dias de cada pessoa por semana (o turno inteiro): a conta que o livre de verdade mostra
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', v_pes[z.p], 'seg', z.seg, 'meios', z.n) order by z.seg, z.p), '[]'::jsonb)
      into v_msem
      from (select t.p, (v_ini + (t.h + 1) / 2 - 1) - (extract(isodow from v_ini + (t.h + 1) / 2 - 1)::int - 1) as seg, count(*)::int as n
              from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
             where t.pr = 0 group by 1, 2) z;
    -- quem o dono disse e não ficou com lugar: o motor troca por outro diarista livre (a frase diz no lugar de quem)
    v_trocados := array(select v_nomes[d.q] from unnest(v_pm || v_pt) with ordinality d(q, o)
                         where not (d.q = any (public._agenda_ints(v_b -> 'p')))
                         group by d.q order by min(d.o));
    v_bt := public._agenda_dias_texto(v_dias)
            || case when (v_b ->> 'ini')::int % 2 = 0 then ' (começa à tarde)' else '' end
            || coalesce(', com ' || nullif(v_quem, ''), '')
            || coalesce(' (no lugar de ' || nullif(public._agenda_lista(v_trocados, null), '') || ')', '')
            || coalesce('; ' || v_pontas, '') || '.';
  end if;

  v_txt := case
    when v_b is null then format('não cabe até %s com a equipe de agora, nem acima da carga de sempre.', public._dia_curto(v_hor))
    when v_acima then format('na carga de sempre da equipe não cabe até %s; acima dela, cabe em %s', public._dia_curto(v_hor), v_bt)
    else 'pelo plano de agora, cabe em ' || v_bt end;
  if v_pontas_so then
    v_txt := 'com você o tempo todo não consigo encaixar: não sei em que dias você fica em campo. '
             || case when v_b is null then public._agenda_maiuscula(v_txt)
                     when v_abre then 'Com você só abrindo e fechando, ' || v_txt
                     else 'Sem você, ' || v_txt end;
  end if;
  v_txt := v_txt || ' É simulação: não marca nada.';

  return jsonb_build_object(
    'ok', true, 'cabe', v_b is not null, 'acima', v_acima, 'so_pontas', v_pontas_so,
    'motivo', case when v_b is null then 'sem_encaixe' end,
    'de', v_dias[1], 'ate', v_dias[cardinality(v_dias)], 'dias', to_jsonb(v_dias), 'pessoas', v_quem, 'pontas', v_pontas,
    'horizonte', v_hor, 'meios_por_semana', v_msem, 'texto', v_txt);
end;
$function$;

comment on function public.agenda_encaixe_do_novo(numeric, jsonb, text, date) is
  'Agenda de Produção (correção de 29/10, P2): um serviço que ainda não existe ("2 dias, com o Roberto") no encaixe do motor (_agenda_encaixar, só leitura) sobre a grade de agora (_agenda_grade_de_agora: o marcado e o reservado ocupam), como uma OS nova entraria — compromisso (classe 2), a partir do 1º dia que a agenda ainda pode mudar, todos os inícios até o horizonte, o teto de compromisso (sem caber, acima dele, até 100%: acima = true). p_gente = a lista da agenda_simular [{payee_id, nome, eh_dono, turnos}]: o dono fica o turno dele, os outros por turno; sem ninguém, equipe_sugerida pessoas por turno. A presença do dono: p_dono (abre_e_fecha, sempre, nunca); senão o turno dele na lista; senão ele abre e fecha. O dono o turno inteiro sem os dias dele em campo o motor não marca: so_pontas = true, simula com ele só abrindo e fechando e a frase diz por quê. Meios-dias: dias × 2 (quem só vem num turno: 1 por dia). Pessoa fora da grade: motivo sem_dias. {ok, cabe, acima, so_pontas, motivo (sem_encaixe, sem_dias, sem_equipe), de, ate, dias, pessoas, pontas, horizonte, meios_por_semana[{payee_id, seg, meios}], texto ("pelo plano de agora, cabe em sex 13 e ter 17/11, com João e Roberto; você abre e fecha. É simulação: não marca nada.")}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role.';

-- ── 5. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO 29/10 (P2):") ──────────
-- Fora dos blocos nenhuma linha muda (o K de supabase/tests/agenda_correcao_2910_p2.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration.

-- agenda_simular (de 20261024160500_agenda_fase1_leituras.sql)
create or replace function public.agenda_simular(p_dias numeric, p_com_quem jsonb default '[]'::jsonb,
                                                 p_dono text default null, p_autor uuid default null,
                                                 p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn     jsonb;
  v_lista  jsonb := case when jsonb_typeof(coalesce(p_com_quem, '[]'::jsonb)) = 'array' then coalesce(p_com_quem, '[]'::jsonb)
                         else jsonb_build_array(p_com_quem) end;
  v_e      jsonb;
  v_ref    text;
  v_turnos text;
  v_rp     jsonb;
  v_gente  jsonb := '[]'::jsonb;
  v_eq     numeric := 0;
  v_com_dono boolean := false;
  v_nomes  text[];
  v_por    text[];
  v_atraso int;
  v_cdia   numeric;
  v_quem   text;
  v_conta  text;
  l1 text; l2 text;
  -- CORREÇÃO 29/10 (P2): o encaixe do motor (com a agenda automática ligada)
  v_enc    jsonb;
  -- CORREÇÃO 29/10 (P2): fim
begin
  if p_hoje is null then
    raise exception 'agenda_simular: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_dias is null or p_dias <= 0 or p_dias > 60 then
    return jsonb_build_object('ok', false, 'texto', 'Para simular, diga quantos dias o serviço leva (por exemplo, 2 dias).');
  end if;
  if p_dono is not null and p_dono not in ('abre_e_fecha', 'sempre', 'nunca') then
    raise exception 'agenda_simular: presença do dono "%" não existe (abre_e_fecha, sempre ou nunca)', p_dono using errcode = '22023';
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_cdia := (v_pn ->> 'cap_dia')::numeric;

  -- Quem vai: nomes ("eu", "Roberto") ou {pessoa, turnos}. Pessoa que não existe = a frase do resolvedor.
  for v_e in select x from jsonb_array_elements(v_lista) x loop
    v_ref := case when jsonb_typeof(v_e) = 'string' then v_e #>> '{}' else v_e ->> 'pessoa' end;
    v_turnos := coalesce(case when jsonb_typeof(v_e) = 'object' then v_e ->> 'turnos' end, 'dia');
    if v_turnos not in ('dia', 'manha', 'tarde') then
      raise exception 'agenda_simular: turno "%" não existe (dia, manha ou tarde)', v_turnos using errcode = '22023';
    end if;
    v_rp := public.agenda_resolver_pessoa(v_ref, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto');
    end if;
    if exists (select 1 from jsonb_array_elements(v_gente) g where g ->> 'payee_id' = v_rp ->> 'payee_id') then
      continue;
    end if;
    v_gente := v_gente || jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                             'eh_dono', (v_rp ->> 'eh_dono')::boolean, 'turnos', v_turnos,
                                             -- a mesma conta de os_prontidao: só um turno = 1 meio-dia por dia ocupado
                                             'diarias', trim_scale(case when v_turnos = 'dia' then p_dias * 2
                                                                        else ceil(p_dias) end / 2));
  end loop;
  v_com_dono := exists (select 1 from jsonb_array_elements(v_gente) g where (g ->> 'eh_dono')::boolean);

  -- As diárias da equipe: os meios-dias ÷ 2 de quem é equipe (o dia todo = dias × 2; só um turno = 1 por dia ocupado;
  -- você só entra quando tem padrão). Sem ninguém dito,
  -- a equipe sugerida.
  if jsonb_array_length(v_gente) = 0 then
    v_eq := p_dias * (v_pn ->> 'equipe_sugerida')::int;
    v_quem := '';
    v_conta := format('(conto %s pessoas, %s, porque você não disse com quem)', v_pn ->> 'equipe_sugerida',
                      public._agenda_plural(ceil(v_eq)::int, 'diária', 'diárias'));
    if v_eq <> trunc(v_eq) then
      v_conta := format('(conto %s pessoas, %s diárias, porque você não disse com quem)', v_pn ->> 'equipe_sugerida',
                        public._agenda_num(v_eq, 2));
    end if;
  else
    select coalesce(sum((g ->> 'diarias')::numeric) filter (where not (g ->> 'eh_dono')::boolean
                                                            or (v_pn ->> 'dono_padrao')::boolean), 0)
      into v_eq from jsonb_array_elements(v_gente) g;
    v_nomes := array(select case when (g ->> 'eh_dono')::boolean then 'você' else g ->> 'nome' end
                              || case g ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                       from jsonb_array_elements(v_gente) with ordinality t(g, o)
                      order by (g ->> 'eh_dono')::boolean desc, o);
    v_quem := ' com ' || public._agenda_lista(v_nomes, null);
    v_por := array(select format('%s %s', case when (g ->> 'eh_dono')::boolean then 'você' else g ->> 'nome' end,
                                 public._agenda_num((g ->> 'diarias')::numeric, 2))
                     from jsonb_array_elements(v_gente) with ordinality t(g, o)
                    where not (g ->> 'eh_dono')::boolean or (v_pn ->> 'dono_padrao')::boolean
                    order by (g ->> 'eh_dono')::boolean desc, o);
    v_conta := '(são ' || case when v_eq = 1 then '1 diária de equipe' else public._agenda_num(v_eq, 2) || ' diárias de equipe' end
               || case when cardinality(v_por) > 1 then ': ' || public._agenda_lista(v_por, null) else '' end
               || case when v_com_dono and not (v_pn ->> 'dono_padrao')::boolean then '; você não entra nessa conta' else '' end
               || ')';
    if v_eq = 0 then
      v_conta := '(é só você, e você não entra na conta da equipe)';
    end if;
  end if;
  if p_dono is not null and not v_com_dono then
    v_quem := v_quem || case p_dono when 'abre_e_fecha' then ', você abre e fecha' when 'sempre' then ', você junto o tempo todo'
                                    else ', sem você' end;
  end if;

  l1 := format('Um serviço de %s%s %s: ', public._agenda_dias(p_dias), v_quem, v_conta);
  -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, o 1º início que cabe sai do encaixe do motor sobre o plano de agora
  -- (o marcado, o reservado e o teto da semana de cada pessoa: agenda_encaixe_do_novo), não da fila ÷ ritmo da Fase 1 ("no
  -- fim da fila, começa entre …"), que contava a OS travada como se ocupasse a equipe. Nada é gravado.
  if (public._agenda_cfg()).modo_proposta = 'ligado' then
    v_enc := public.agenda_encaixe_do_novo(p_dias, v_gente, p_dono, p_hoje);
    return jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[l1 || (v_enc ->> 'texto')], (v_pn ->> 'texto_max')::int),
      'dados', jsonb_build_object('dias', p_dias, 'com_quem', v_gente, 'diarias_equipe', trim_scale(v_eq), 'encaixe', v_enc));
  end if;
  -- CORREÇÃO 29/10 (P2): fim
  if v_cdia is null or v_cdia <= 0 then
    l1 := l1 || 'não sei o ritmo da equipe (não há diárias lançadas para medir), então não sei dizer quando cabe.';
    l2 := 'É projeção: não reserva nada.';
  else
    l1 := l1 || case
      when (v_pn #>> '{backlog,n}')::int = 0 or v_pn -> 'livre' is null or jsonb_typeof(v_pn -> 'livre') = 'null' then
        'a fila está vazia, começa ' || public._dia_curto((v_pn ->> 'inicio_furando')::date) || '.'
      when v_pn #>> '{livre,ot}' = v_pn #>> '{livre,re}' then
        'no fim da fila, começa por volta de ' || public._dia_curto((v_pn #>> '{livre,ot}')::date) || '.'
      else format('no fim da fila, começa entre %s e %s.', public._dia_curto((v_pn #>> '{livre,ot}')::date),
                  public._dia_curto((v_pn #>> '{livre,re}')::date)) end;
    v_atraso := ceil(v_eq / v_cdia)::int;
    l2 := case when (v_pn #>> '{backlog,n}')::int = 0 then ''
               else format('Passando na frente de tudo, dá para começar %s, e o resto %s. ',
                           public._dia_curto((v_pn ->> 'inicio_furando')::date),
                           case when v_atraso = 0 then 'não atrasa'
                                when v_atraso = 1 then 'atrasa uns 1 dia útil'
                                else format('atrasa uns %s dias úteis', v_atraso) end) end
          || 'É projeção: não reserva nada.';
    l2 := replace(l2, 'uns 1 dia útil', '1 dia útil');
  end if;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1 || ' ' || l2], (v_pn ->> 'texto_max')::int),
    'dados', jsonb_build_object('dias', p_dias, 'com_quem', v_gente, 'diarias_equipe', trim_scale(v_eq),
                                'fila', v_pn -> 'livre', 'inicio_furando', v_pn -> 'inicio_furando', 'atraso_du', v_atraso));
end;
$function$;

comment on function public.agenda_simular(numeric, jsonb, text, uuid, date) is 'Agenda de Produção (Fase 1, P4): serviço hipotético sem orçamento ("um serviço de 2 dias, eu e o Roberto") — as diárias da equipe (meios-dias ÷ 2 de quem é equipe: o dia todo = dias × 2, só de manhã ou só à tarde = 1 por dia ocupado; o dono fora da conta enquanto não tem padrão), no fim da fila (a faixa do livre de verdade) e passando na frente (agenda_somar_du(p_hoje, congelamento_du + 1); o resto atrasa ceil(diárias ÷ capacidade diária) dias úteis). "É projeção: não reserva nada." Pessoa que não existe = {ok:false, texto do resolvedor}. CORREÇÃO 29/10 (P2): com a agenda automática ligada (modo_proposta ligado), o 1º início sai do encaixe do motor sobre o plano de agora (agenda_encaixe_do_novo: o marcado, o reservado e o teto da semana de cada pessoa; a OS travada não ocupa ninguém), no lugar de "no fim da fila…/passando na frente…": "Um serviço de 2 dias com Roberto (são 2 diárias de equipe): pelo plano de agora, cabe em seg 09 e qua 11/11, com Roberto; você abre e fecha. É simulação: não marca nada." dados.encaixe = o resultado do encaixe. Fora de ligado, a projeção de antes, byte a byte.';

-- agenda_ver (de 20261029100800_agenda_fase6_leituras.sql)
create or replace function public.agenda_ver(p_autor uuid default null, p_periodo text default null,
                                             p_pessoa text default null, p_foco text default null, p_os text default null,
                                             p_simular jsonb default null, p_simular_aprovacao boolean default false,
                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_foco    text := coalesce(nullif(btrim(lower(p_foco)), ''), 'tudo');
  v_rp      jsonb;
  v_payee   uuid;
  v_eh_dono boolean := true;
  v_de      date;
  v_ate     date;
  v_ro      jsonb;
  v_r       jsonb;
  v_pn      jsonb;
  v_rota    text;
  v_max     int;
  v_l       text[];
  k         int;
  -- FASE 2: a hora de agora (desfazer ainda vale? a decisão venceu?). now(); a bancada fixa com agenda.agora.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  -- FASE 3: o livre de verdade (a simulação do motor) e o mês da comissão
  v_lv      jsonb;
  v_mes     date;
begin
  -- FASE 6: (P8) o foco aprendizado (spec-fase6 §5.8 e §6.2: o que a agenda aprendeu com o que aconteceu,
  -- _agenda_ver_aprendizado) e a conferência do foco com os 19 — antes da conferência dos 18 da Fase 5, que o foco
  -- aprendizado não alcança. Com login, só administrador e financeiro (42501, antes de ler a config); desligada a leitura, a
  -- frase de sempre.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes', 'aprendizado') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores, clientes ou aprendizado)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'aprendizado' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    return public._agenda_ver_aprendizado(p_hoje) || jsonb_build_object('rota', 'aprendizado');
  end if;
  -- FASE 6: fim
  -- FASE 5: o foco clientes (a mensagem ao cliente: _agenda_ver_clientes, com ou sem a OS; a OS concluída também) e a
  -- conferência do foco com os 18 — antes da conferência dos 17 da Fase 4, que o foco clientes não alcança.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores ou clientes)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'clientes' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    if nullif(btrim(p_os), '') is not null then
      v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
      if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
        return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                  'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                  'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
      return public._agenda_ver_clientes((v_ro ->> 'id')::uuid, p_hoje) || jsonb_build_object('rota', 'clientes_os');
    end if;
    return public._agenda_ver_clientes(null, p_hoje) || jsonb_build_object('rota', 'clientes');
  end if;
  -- FASE 5: fim
  -- FASE 2: os focos decisoes, mudancas e plano
  -- FASE 3: os focos ppc, diarias, marcos, comissao e equipe
  -- FASE 4: os focos compras e fornecedores (a conferência e a mensagem com os 17)
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras ou fornecedores)', p_foco
      using errcode = '22023';
  end if;
  -- FASE 4: fim
  if p_hoje is null then
    raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Desligada (agenda_config.modo_leitura), a agenda de produção não responde: o assistente volta à agenda de antes
  -- (my_agenda: tarefas e compromissos do dono). Quem não lê agenda_config continua recebendo erro (nunca "livre").
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                              'texto', 'A agenda de produção está desligada agora.');
  end if;

  -- Pessoa: "eu" ou o nome. Quem não existe ou é ambíguo volta a frase do resolvedor (nunca um erro cru).
  if nullif(btrim(p_pessoa), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'rota', 'pessoa', 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto',
                                'opcoes', coalesce(v_rp -> 'opcoes', '[]'::jsonb));
    end if;
    v_payee := (v_rp ->> 'payee_id')::uuid;
    v_eh_dono := coalesce((v_rp ->> 'eh_dono')::boolean, false);
  end if;

  -- Período: hoje, amanhã, semana, próxima semana ou o que o dono disse.
  -- FASE 3: a comissão lê o mês ("outubro", "mês passado"), não um período de dias.
  if v_foco = 'comissao' then
    begin
      v_mes := public._agenda_mes_dito(p_periodo, p_hoje);
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  else
    begin
      select x.de, x.ate into v_de, v_ate from public._agenda_periodo(p_periodo, p_hoje) x;
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  end if;

  if coalesce(p_simular_aprovacao, false) and nullif(btrim(p_os), '') is null then
    return jsonb_build_object('ok', false, 'rota', 'ctp',
      'texto', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).',
      'pergunta', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).');
  end if;

  if nullif(btrim(p_os), '') is not null then
    v_ro := public.agenda_resolver_os(p_os, p_hoje, coalesce(p_simular_aprovacao, false));
    if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
      return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    if coalesce(p_simular_aprovacao, false) then
      v_rota := 'ctp';
      v_r := public.agenda_ctp((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 3: os marcos da OS (dentro ou fora da carteira: a concluída e a entregue já saíram dela)
    elsif v_foco = 'marcos' then
      v_rota := 'marcos';
      v_r := public._agenda_ver_marcos((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 4: as compras e a espera de peça da OS (também fora da carteira: a concluída nos últimos 180 dias); os
    -- fornecedores não são de uma OS
    elsif v_foco = 'compras' then
      v_rota := 'compras_os';
      v_r := public._agenda_ver_compras((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_foco = 'fornecedores' then
      v_rota := 'fornecedores';
      v_r := public._agenda_ver_fornecedores(p_hoje);
    -- FASE 4: fim
    elsif v_ro ->> 'status' = 'fora_da_carteira' then
      v_rota := 'os';
      v_r := jsonb_build_object('ok', true, 'texto', v_ro ->> 'texto', 'dados', jsonb_build_object('numero', v_ro ->> 'numero'));
    elsif v_foco = 'material' then
      v_rota := 'material_os';
      v_r := public.agenda_ver_material((v_ro ->> 'id')::uuid, p_hoje);
    else
      v_rota := 'os';
      v_r := public._agenda_ver_os((v_ro ->> 'id')::uuid, p_hoje);
    end if;
  -- FASE 3: os marcos pedem a OS
  elsif v_foco = 'marcos' then
    return jsonb_build_object('ok', false, 'rota', 'marcos',
      'texto', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).',
      'pergunta', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).');
  elsif p_simular is not null and jsonb_typeof(p_simular) = 'object' then
    v_rota := 'simular';
    v_r := public.agenda_simular((p_simular ->> 'dias')::numeric, coalesce(p_simular -> 'com_quem', '[]'::jsonb),
                                 nullif(p_simular ->> 'dono', ''), p_autor, p_hoje);
  -- FASE 2: o que espera o dono, o que mudou sozinho e o plano publicado
  elsif v_foco = 'decisoes' then
    v_rota := 'decisoes';
    v_r := public._agenda_ver_decisoes(p_hoje, v_agora);
  elsif v_foco = 'mudancas' then
    v_rota := 'mudancas';
    v_r := public._agenda_ver_mudancas(p_hoje, v_agora);
  elsif v_foco = 'plano' then
    v_rota := 'plano';
    v_r := public._agenda_ver_plano(v_de, v_ate, p_hoje, v_agora);
  -- FASE 3: a semana medida, as diárias da agenda, a comissão do mês e o que a equipe respondeu
  elsif v_foco = 'ppc' then
    v_rota := 'ppc';
    v_r := public._agenda_ver_ppc(v_de, p_hoje);
  elsif v_foco = 'diarias' then
    v_rota := 'diarias';
    v_r := public._agenda_ver_diarias(v_de, v_ate, p_hoje);
  elsif v_foco = 'comissao' then
    v_rota := 'comissao';
    v_r := public._agenda_ver_comissao(v_mes, p_hoje);
  elsif v_foco = 'equipe' then
    v_rota := 'equipe';
    v_r := public._agenda_ver_equipe(p_hoje);
  -- FASE 4: o que comprar e até quando, as notas, o tempo até comprar e a pergunta ao fornecedor; como conto o prazo de
  -- cada fornecedor
  elsif v_foco = 'compras' then
    v_rota := 'compras';
    v_r := public._agenda_ver_compras(null, p_hoje);
  elsif v_foco = 'fornecedores' then
    v_rota := 'fornecedores';
    v_r := public._agenda_ver_fornecedores(p_hoje);
  -- FASE 4: fim
  elsif v_foco = 'o_que_fazer' then
    if v_payee is not null and not v_eh_dono then
      v_rota := 'dia_da_pessoa';
      v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
    else
      v_rota := 'o_que_fazer';
      v_r := public.agenda_o_que_fazer(coalesce(v_payee, public._agenda_dono(p_autor)), p_hoje);
    end if;
  elsif v_foco in ('atrasos', 'riscos') then
    v_rota := 'atrasos';
    v_r := public.agenda_atrasos(p_hoje);
  elsif v_foco = 'material' then
    v_rota := 'material';
    v_r := public.agenda_ver_material(null, p_hoje);
  elsif v_foco = 'livre' then
    v_rota := 'livre';
    v_r := public.agenda_semana(null, null, p_hoje);
    -- FASE 3: com a agenda automática ligada, o livre de verdade sai da simulação do motor (fora disso, a projeção)
    if (public._agenda_cfg()).modo_proposta = 'ligado' then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
    end if;
    v_r := jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[v_r #>> '{dados,textos,resumo}',
                                           case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto'
                                                else v_r #>> '{dados,textos,livre}' end],
                                     (select texto_max from public._agenda_cfg())),
      'dados', jsonb_build_object('fila', v_r #> '{dados,fila}', 'livre', v_r #> '{dados,livre}',
                                  'capacidade', v_r #> '{dados,capacidade}',
                                  'livre_de_verdade', coalesce(v_lv, jsonb_build_object('fonte', 'projecao'))));
    -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, o livre é UMA resposta, a do plano (quem ainda pega serviço em cada
    -- uma das próximas semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa
    -- ninguém até destravar), no lugar da fila em faixa da Fase 1 ("Livre ela não está: … de 3 a 6 semanas", que conta a OS
    -- travada como se ocupasse a equipe) seguida da frase da simulação ("a equipe já está livre")
    if v_lv ->> 'fonte' = 'simulacao' and nullif(v_lv ->> 'texto_completo', '') is not null then
      v_r := jsonb_set(v_r, '{texto}', to_jsonb(v_lv ->> 'texto_completo'));
    end if;
    -- CORREÇÃO 29/10 (P2): fim
  elsif v_foco = 'aprontar' then
    v_rota := 'aprontar';
    v_r := public.agenda_aprontar(p_hoje);
  elsif v_payee is not null and not v_eh_dono and (v_de is null or v_de = v_ate) then
    v_rota := 'dia_da_pessoa';
    v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
  elsif v_de is not null and v_de = v_ate then
    v_rota := 'dia';
    v_pn := public._agenda_painel(p_hoje);
    v_max := (v_pn ->> 'texto_max')::int;
    for k in reverse 5 .. 1 loop
      v_l := public._agenda_dia_de(v_pn, v_de, k);
      exit when char_length(public._agenda_juntar(v_l, null)) <= v_max;
    end loop;
    v_r := jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, v_max), 'dados', jsonb_build_object('dia', v_de));
  else
    v_rota := 'semana';
    v_r := public.agenda_semana(v_de, v_ate, p_hoje);
    -- FASE 3: com a agenda automática ligada, a frase do livre da semana é a da simulação do motor
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,livre}', '') is not null
       and position((v_r #>> '{dados,textos,livre}') in (v_r ->> 'texto')) > 0 then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(v_r ->> 'texto', v_r #>> '{dados,textos,livre}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
    -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, a linha do livre (a do plano) vai logo depois do marcado, no lugar
    -- da fila em faixa da Fase 1 (o resumo "Livre ela não está: … de 3 a 6 semanas", que contradizia o livre), e a linha do
    -- livre lá de baixo sai: a semana diz o livre uma vez só
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,resumo}', '') is not null
       and position((v_r #>> '{dados,textos,resumo}') in (v_r ->> 'texto')) > 0 then
      v_lv := coalesce(v_lv, public.agenda_livre_de_verdade(p_hoje, v_agora));
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(replace(v_r ->> 'texto', E'\n' || (v_lv ->> 'texto'), ''),
                                                          v_r #>> '{dados,textos,resumo}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
    -- CORREÇÃO 29/10 (P2): fim
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6; Fase 5, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; FASE 5: foco clientes (com ou sem os; a OS concluída também) → as mensagens ao cliente (_agenda_ver_clientes); foco fora da lista (os 18) lança 22023. Devolve {ok, texto, dados, rota}. FASE 6 (P8): foco aprendizado → o que a agenda aprendeu com o que aconteceu (_agenda_ver_aprendizado: o fator por tipo de OS, a presença do dono, os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga, com o n de cada um, e as medidas); com login, só administrador e financeiro (42501). A lista dos focos passa a 19. CORREÇÃO 29/10 (P2): com a agenda automática ligada, o foco livre é UMA resposta, a do plano (agenda_livre_de_verdade.texto_completo: quem ainda pega serviço em cada uma das 3 semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa ninguém até destravar), sem a fila em faixa da Fase 1; na semana, a linha do livre (agenda_livre_de_verdade.texto) vai logo depois do marcado, no lugar da fila em faixa, e a linha do livre lá de baixo sai; simular (agenda_simular) em ligado é o encaixe do motor. Fora de ligado, tudo como antes.';

-- ── 6. Portas ───────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras novas (o texto dos meios-dias, invoker; o encaixe do serviço novo, definer que confere quem vê):
-- authenticated (o painel, com o login do admin) e service_role (o WhatsApp), nunca anon. A grade de agora é peça do motor
-- (lê a grade e o plano inteiros): só o service_role, como _agenda_contexto; quem a chama são as duas definer.
revoke all on function public._agenda_meios_texto(integer), public.agenda_encaixe_do_novo(numeric, jsonb, text, date)
  from public, anon;
grant execute on function public._agenda_meios_texto(integer), public.agenda_encaixe_do_novo(numeric, jsonb, text, date)
  to authenticated, service_role;
revoke all on function public._agenda_grade_de_agora(date) from public, anon, authenticated;
grant execute on function public._agenda_grade_de_agora(date) to service_role;

-- A reescrita e as recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a migration
-- valer sozinha).
revoke all on function
  public.agenda_livre_de_verdade(date, timestamptz),
  public.agenda_simular(numeric, jsonb, text, uuid, date),
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)
  from public, anon;
grant execute on function
  public.agenda_livre_de_verdade(date, timestamptz),
  public.agenda_simular(numeric, jsonb, text, uuid, date),
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)
  to authenticated, service_role;
