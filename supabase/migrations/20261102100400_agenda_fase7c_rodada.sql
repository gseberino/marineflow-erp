-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê"), pacote P5: a rodada diária de quem faz o quê — a proposta pelo
-- histórico e pelo técnico que o dono declarou (uma pergunta só ao dono), o prazo de veto contado da 1ª vez que ela foi vista, a
-- conferência em teste do publicado, a pergunta por OS quando ninguém com o que o serviço pede fica livre (só ligado) e as medidas; e a
-- linha (n) "a equipe" do fechamento passa a levar a pergunta de quem faz o quê, com o portão separado por etapa, o "Também" fora do
-- registro e o prazo na forma curta.
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§R5.1-6, §R5.4 item 4, §R5.5 item 5, §R5.7-7, §R5.10-6/-7/-8, §5.5, §6.4–§6.6,
-- §8.3 agenda_fase7c_rodada.sql, §8.4); nomes: fase7-registro.md §1 (7c P5); respostas do dono: fase7-padroes.md (AG7-01 ligar direto;
-- AG7-03 a equipe — Alex e o dono, Mateus e Vinicius sob demanda; AG7-10 "sem etiqueta = pode tudo, menos comissionar" e "o gestor
-- propõe pelo histórico"; AG7-15 sem resposta no prazo fica como proposto).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (veto_du/veto_hora e _agenda_veto_ate; o ampliador), da 7b inteira (o
-- novato, quem vem sob demanda, a pessoa a mais, os dias curtos; a correção 3, 20261101100860, de onde _agenda_linhas_do_fechamento
-- é copiada) e da 7c P1 a P4 (20261102100000 .. 100300: agenda_etiquetas, agenda_habilidades, os_exigencias, _agenda_atende, as
-- avaliações do publicado, o técnico declarado, o modo da pergunta habilidade; o motor e o fora habilidade; a conversa).
--
-- ═══ DDL — OK NOMEADO ═══ (7 funções novas e 1 recriada; nenhuma tabela, coluna, lista ou dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7c/p5/montar-migration.mjs: a recriada (_agenda_linhas_do_fechamento) é o corpo da definição MAIS NOVA
-- (conferida a cada montagem: o montador para se outra migration anterior a esta a definir depois da origem) — 20261101100860_agenda_
-- fase77b_correcao3.sql (o R5.4 diz o mesmo) —, e as mudanças entram SÓ como inserções: blocos "-- FASE 7c: … -- FASE 7c: fim" fora dos
-- blocos de antes e, dentro do bloco "-- FASE 7b: (7b P3, R4.2(d))" da linha (n), a marca de dentro "-- (7c P5 …) … -- (7c: fim)" (R5.4
-- item 2: os tiradores que não contam aninhamento fecham no 1º "fim"). Nenhuma linha de antes é trocada. Tirados os blocos e as marcas,
-- o corpo é o da origem, byte a byte (o montador e o R9 de supabase/tests/agenda_fase7c_rodada.sql conferem).
--
-- POR QUE: o P1 deu a cada pessoa o que ela faz, mas ninguém propunha nada — sem etiqueta vale o padrão ("pode tudo, menos comissionar"),
-- e a proteção do ajudante e do novo só existe quando a etiqueta vale. O AG7-10 manda o gestor propor pelo histórico e o dono corrigir
-- numa frase; o AG7-15, que sem resposta no prazo fique como proposto. E a pergunta tem de chegar: pela pergunta de fato do fechamento
-- (perda 30) ela nunca entraria nas vagas (as duas de fornecedor estão abertas e nunca vistas desde 28/10), então vai na linha da equipe
-- (n), com vaga própria enquanto não foi vista — e, com o Secretário cheio, na forma curta que diz o que foi marcado e o prazo (o registro
-- não sabe qual forma saiu e conta a pergunta como vista).
--
-- O QUE MUDA:
--   1. agenda_habilidade(p_hoje, p_agora) — a rodada (definer, só service_role; o passo 0b2a do task-automations, a cada tique), o molde
--      de agenda_aprender: uma vez por dia a partir de habilidade_hora (16:10, o tique das 16:15; antes → {rodou: false, cedo: true}; o 2º
--      tique → {ja_rodou: true}); os passos, cada um no seu bloco (o que falha vai a app_error_logs, context agenda, action
--      habilidade:<passo>, e os outros seguem): (1) propor, com modo_habilidade_propor fora de desligado; (2) vetos, sempre (só age na
--      pergunta ligada e já mostrada); (3) conferir, com modo_habilidade ou modo_lider em teste; (4) perguntas_os, com modo_habilidade
--      ligado; (5) medir, sempre. Grava agenda_vigia_rodadas (rotina habilidade).
--   2. _agenda_habilidade_propor — a proposta (R5.1-6, vale sobre o §5.5): a população é a grade de p_hoje a p_hoje + 13 (agenda_capacidade,
--      nunca "quem tem perfil de diária"), sem o dono, sem a pessoa a mais da 7b e sem quem vem sob demanda; as regras, nesta ordem: (1) o
--      dono já disse instala ou ajudante → nada; (2) o técnico que o dono declarou (_agenda_tecnico_declarado) → instala 2, "você disse que
--      ele vem todo dia útil"; (3) com perfil de diária vigente: o novato da 7b → ajudante 1 ("começou em 20/10, 3 diárias"); 20 diárias
--      ou mais em 90 dias e 60 dias de casa ou mais → instala 2 ("33 diárias desde 23/08"); senão ajudante 2 ("entrou em 29/09, 15
--      diárias"); (4) senão nada (vale o padrão). Nunca comissiona nem altura. Uma pergunta só, habilidade:equipe:<dia> (ligada com
--      modo_habilidade_propor ligado; senão em teste), com o texto do R5.1-6 e sem data (o prazo só existe depois de vista); refeita
--      quando a proposta muda ou o modo muda (a de antes vira descartada: "a proposta mudou: perguntei de novo").
--   3. _agenda_habilidade_vetos — o prazo (§R2): na 1ª rodada depois de a pergunta ligada ser mostrada, veto_ate = _agenda_veto_ate(
--      mostrada_em), uma vez (mostrá-la de novo não adia); passado o prazo, as propostas valem, a pergunta fecha ("sem resposta no prazo:
--      ficou como eu marquei") e UMA ação habilidade (executada) entra no "o que mudou" (§6.5).
--   4. _agenda_habilidade_conferir — em teste (modo_habilidade ou modo_lider em sombra): o publicado dos próximos dias avaliado com as
--      regras de ligado (_agenda_meios_sem_quem_pede; _agenda_lideres_ausentes) vira ação habilidade de teste (executada = false: vai às
--      linhas de sombra do fechamento, nunca ao texto do dono), no máximo 6 por dia, sem repetir no dia, com quem eu poria (§6.6).
--   5. _agenda_habilidade_perguntas_os — com modo_habilidade ligado, a OS que a última proposta de hoje deixou de fora por falta de quem o
--      serviço pede ganha a pergunta habilidade:os:<os> (§6.4); a que voltou a caber fecha ("coube: a equipe tem quem o serviço pede").
--   6. agenda_habilidade_medidas(p_de, p_ate, p_hoje) — as medidas (§5.5; o 7g e o foco as leem): alguém sozinho em serviço que pede outra
--      pessoa, o responsável ausente, as trocas avisadas, os meios-dias do dono em serviço que outro faria, as correções do dono sobre quem
--      vai, os critérios, as etiquetas; o retrabalho não é medido.
--   7. _agenda_habilidade_pergunta_texto — o texto da pergunta da equipe (§6.4, R5.1-6), em até 600 letras.
--   8. _agenda_linhas_do_fechamento (recriada da 20261101100860; R5.4 item 4) — a linha (n) "a equipe" leva, depois das perguntas da 7b,
--      as de quem faz o quê (primeiro a da equipe, depois as de OS). O portão do bloco passa a "a 7b OU a 7c fora de desligado", mas
--      dentro dele as perguntas da 7b só entram com o portão da 7b e as da 7c só com o da 7c, e a pergunta de fato (e) exclui só os tipos
--      que a (n) levou (R5.10-8: sem isso, com a 7b desligada e a 7c em teste, a chamada da 7a sairia da (e), perda 30, para a (n), perda
--      75). A da equipe que vai só como "Também: quem faz o quê (marquei: …; responda em *agenda pendências*)." fica fora de pergunta_ids
--      (não conta como vista: o achado 17 da 7b estendido); a forma curta da linha (texto_curto) diz o que foi marcado e, na que é
--      contada, o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00, fica assim" (a data é a
--      que _agenda_habilidade_vetos grava depois do registro).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7c_rodada.sql; registradas em notas-fase77c.md, P5):
--   · agenda_habilidade_medidas é DEFINER (a spec dizia invoker), com a porta explícita (com login, só admin/financeiro, senão 42501;
--     sem login, só o service_role): ela lê as avaliações do publicado (_agenda_meios_sem_quem_pede, _agenda_lideres_ausentes), que o P1
--     deixou sem grant a ninguém — como invoker, ninguém de fora conseguiria chamá-la;
--   · as diárias da proposta são as linhas de work_shifts (normal ou diaria) na janela, contadas (a régua da consulta da spec, wf7c_08);
--     o novato é o da 7b (_agenda_e_novato), a regra única;
--   · em teste (modo_habilidade_propor em sombra), a proposta nunca troca uma etiqueta que já vale (o índice de uma viva por etiqueta faria a
--     proposta substituí-la, e em teste nada pode mudar);
--   · a pergunta da equipe é refeita também quando o modo dela muda (a de teste não é vista: ao ligar, nasce a ligada) ou quando uma
--     proposta dela deixou de valer (o dono disse outra coisa antes de ver); sem nenhuma proposta viva, ela é descartada;
--   · a conferência do responsável fixo junta os dois turnos do mesmo dia numa ação só ("Edu, qua 11/11 — …"), como o texto da §6.6;
--   · na linha (n), a pergunta de OS que vai como "Também" conta como vista (vai com a pergunta toda, como o telefone e o contato da 7b).
--
-- O QUE NÃO MUDA: com os modos da 7c desligados (a linha nasce assim), a rodada só grava a linha dela em agenda_vigia_rodadas (o passo
-- vetos não acha pergunta ligada; a medida só lê) e _agenda_linhas_do_fechamento sai byte a byte a de antes, com a 7b desligada e em
-- teste. Em teste, as linhas ligadas do fechamento (as que o dono lê) saem byte a byte: só nascem linhas de modo sombra. Nenhuma
-- mensagem nova à equipe ou ao cliente: ao dono, só a pergunta da agenda (na linha da equipe), o "o que mudou" e as linhas de teste.
--
-- ORDEM DE LIGAR (spec §10, R5.5): depois de 20261102100000 .. 100300 (P1 a P4); antes de 20261102100500 (P6) e de 20261102100550 (P8,
-- que recria _agenda_linhas_do_fechamento copiando DESTA). O passo 0b2a do task-automations chama agenda_habilidade a cada tique; o código
-- publicado antes desta migration pula calado (PGRST202/42883).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7c_rodada.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261102100400
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261102100400_agenda_fase7c_rodada.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261102100400', 'agenda_fase7c_rodada');"
--
-- DESFAZER: recriar _agenda_linhas_do_fechamento com o corpo de 20261101100860; e
--   drop function if exists public.agenda_habilidade(date, timestamptz), public._agenda_habilidade_propor(date, timestamptz),
--     public._agenda_habilidade_vetos(date, timestamptz), public._agenda_habilidade_conferir(date, timestamptz),
--     public._agenda_habilidade_perguntas_os(date, timestamptz), public.agenda_habilidade_medidas(date, date, date),
--     public._agenda_habilidade_pergunta_texto(date, uuid[]);
--   (as propostas, as perguntas e as ações já gravadas ficam: agenda_etiquetas, agenda_perguntas e agenda_acoes não se apagam)
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. O texto da pergunta da equipe (spec §6.4; R5.1-6) ───────────────────────────────────────────────────────────

-- As propostas (p_ids, de agenda_etiquetas) na palavra do dono: primeiro quem instala sozinho, depois o ajudante e o novo, e o nome;
-- "Alex instala sozinho, também com 220 V ou banco de bateria, e sobe no teto (você disse que ele vem todo dia útil)" (o 220 V quando
-- o nível vale para o energizado; o teto quando a pessoa sobe, pela etiqueta dela ou pelo padrão); "João é ajudante: não vai sozinho
-- em serviço de risco (entrou em 29/09, 15 diárias)"; "Bruno é novo: nunca vai sozinho (começou em 20/10, 3 diárias)". Depois, o
-- comissionar com o dono (enquanto o padrão não comissiona), o prazo sem data (veto_hora e veto_du: "do próximo dia útil depois de ver
-- esta pergunta") e os exemplos de correção pelos nomes da proposta. Em até 600 letras: primeiro sem o 220 V e o teto, depois com o
-- rótulo curto ("João é ajudante"), e só então as que não cabem vão para o "e mais N (*agenda quem faz* mostra)". STABLE, sem grant (só
-- a proposta, definer, a chama).
create or replace function public._agenda_habilidade_pergunta_texto(p_hoje date, p_ids uuid[])
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 600;   -- estrutural: o CHECK de agenda_perguntas.texto
  v_it    text[];
  v_med   text[];
  v_cur   text[];
  v_a     text;
  v_i     text;
  v_cauda text;
  v_txt   text;
  v_lista text[];
  k       int;
begin
  -- cada proposta em três tamanhos: o inteiro (quem instala sozinho com o 220 V e o teto), o do texto da etiqueta e o curto (o rótulo
  -- antes dos dois-pontos: "João é ajudante"); o texto encolhe nessa ordem antes de deixar alguém para o "e mais N"
  select array_agg(x.nm || ' ' || x.longo || x.mot order by x.o), array_agg(x.nm || ' ' || x.medio || x.mot order by x.o),
         array_agg(x.nm || ' ' || split_part(x.medio, ':', 1) || x.mot order by x.o),
         (array_agg(x.nm order by x.o) filter (where x.etiqueta = 'ajudante'))[1],
         (array_agg(x.nm order by x.o) filter (where x.etiqueta = 'instala' and x.nivel >= 2))[1]
    into v_it, v_med, v_cur, v_a, v_i
    from (select e.etiqueta, e.nivel, public._agenda_nome_curto(py.name) as nm, ' (' || e.motivo || ')' as mot,
                 row_number() over (order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                             public._agenda_nome_curto(py.name), e.id) as o,
                 public._agenda_etiqueta_texto(e.etiqueta, e.nivel) as medio,
                 case when e.etiqueta = 'instala' and e.nivel >= 2
                      then public._agenda_etiqueta_texto('instala', e.nivel)
                           || case when e.nivel >= cf.habilidade_nivel_energizado and coalesce(h.altura >= cf.habilidade_nivel_altura, false)
                                     then ', também com 220 V ou banco de bateria, e sobe no teto'
                                   when e.nivel >= cf.habilidade_nivel_energizado then ', também com 220 V ou banco de bateria'
                                   when coalesce(h.altura >= cf.habilidade_nivel_altura, false) then ' e sobe no teto'
                                   else '' end
                      else public._agenda_etiqueta_texto(e.etiqueta, e.nivel) end as longo
            from public.agenda_etiquetas e
            join public.payees py on py.id = e.payee_id
            left join lateral (select hh.altura from public.agenda_habilidades(p_hoje, array[e.payee_id]) hh) h on true
           where e.id = any (coalesce(p_ids, '{}'::uuid[]))) x;
  if coalesce(cardinality(v_it), 0) = 0 then
    return null;
  end if;
  v_cauda := case when coalesce((cf.habilidade_padrao ->> 'comissiona')::int, 0) < cf.habilidade_nivel_comissionar
                  then ' Comissionar Victron fica com você.' else '' end
             || format(' Se você não responder até as %s %s, fica assim.', to_char(cf.veto_hora, 'HH24:MI'),
                       case when cf.veto_du = 0 then 'do dia em que vir esta pergunta'
                            when cf.veto_du = 1 then 'do próximo dia útil depois de ver esta pergunta'
                            else format('do %sº dia útil depois de ver esta pergunta', cf.veto_du) end)
             || format(' Para corrigir, me diga numa frase (ex.: %s).',
                       case when v_a is not null and v_i is not null
                              then format('"o %s instala sozinho" ou "o %s não sobe no teto"', v_a, v_i)
                            when v_i is not null then format('"o %s não sobe no teto" ou "o %s é ajudante"', v_i, v_i)
                            else format('"o %s instala sozinho" ou "o %s não sobe no teto"', v_a, v_a) end);
  foreach v_lista slice 1 in array array[v_it, v_med] loop
    v_txt := 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: ' || array_to_string(v_lista, '; ') || '.'
             || v_cauda;
    if char_length(v_txt) <= c_max then
      return v_txt;
    end if;
  end loop;
  for k in reverse cardinality(v_cur) .. 1 loop
    v_txt := 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: ' || array_to_string(v_cur[1:k], '; ')
             || case when k < cardinality(v_cur) then format('; e mais %s (*agenda quem faz* mostra)', cardinality(v_cur) - k) else '' end
             || '.' || v_cauda;
    exit when char_length(v_txt) <= c_max;
  end loop;
  return public._agenda_corta(v_txt, c_max);
end;
$function$;

comment on function public._agenda_habilidade_pergunta_texto(date, uuid[]) is
  'Agenda de Produção (Fase 7c, P5; spec §6.4, R5.1-6): o texto da pergunta habilidade:equipe para as propostas p_ids — "Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: Alex instala sozinho, também com 220 V ou banco de bateria, e sobe no teto (você disse que ele vem todo dia útil). Comissionar Victron fica com você. Se você não responder até as 18:00 do próximo dia útil depois de ver esta pergunta, fica assim. Para corrigir, me diga numa frase (ex.: "o Alex não sobe no teto" ou "o Alex é ajudante")." Primeiro quem instala sozinho, depois o ajudante e o novo; o 220 V pelo habilidade_nivel_energizado e o teto pela altura da pessoa (etiqueta ou padrão); o comissionar com o dono enquanto o padrão não comissiona; o prazo sem data, pela veto_hora e o veto_du; em até 600 letras — encolhe primeiro sem o 220 V e o teto, depois com o rótulo curto ("João é ajudante", "Bruno é novo"), e só então deixa gente para o "e mais N (*agenda quem faz* mostra)". Sem proposta = nulo. STABLE, sem grant.';

-- ── 2. A proposta pelo histórico e pelo que o dono declarou (spec §5.5, R5.1-6) ─────────────────────────────────────

create or replace function public._agenda_habilidade_propor(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_dono  uuid := public._agenda_dono(null);
  v_extra uuid := public._agenda_pessoa_extra_id();
  v_modo  text;
  r       record;
  v_et    text;
  v_nv    smallint;
  v_mot   text;
  v_ev    jsonb;
  v_desde date;
  v_n     int;
  v_casa  int;
  v_qtas  text;
  v_dias  smallint[];
  v_pess  int := 0;
  v_novas jsonb := '[]'::jsonb;
  v_vivas uuid[];
  v_qid   uuid;
  v_qmodo text;
  v_refaz boolean;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_habilidade_propor: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  v_modo := case when cf.modo_habilidade_propor = 'ligado' then 'ligado' else 'sombra' end;

  -- A população: a grade de p_hoje a p_hoje + 13 (agenda_capacidade: quem a agenda conta; o perfil de diária é do pagamento), sem o dono,
  -- sem a pessoa a mais da 7b e sem quem vem sob demanda em todo dia em que está na grade (a ele o gestor não propõe nada: vale a 7b —
  -- nunca sozinho — até a palavra do dono, R5.1-3).
  for r in
    select py.id, public._agenda_nome_curto(py.name) as nm, py.created_at
      from (select k.payee_id, bool_and(public._agenda_e_sob_demanda(k.payee_id, k.dia)) as sob
              from (select distinct c.payee_id, c.dia
                      from public.agenda_capacidade(p_hoje, p_hoje + 13, p_hoje) c
                     where not c.eh_dono) k
             group by k.payee_id) g
      join public.payees py on py.id = g.payee_id
     where not g.sob and g.payee_id is distinct from v_dono and g.payee_id is distinct from v_extra
     order by public._agenda_nome_curto(py.name), py.id
  loop
    v_pess := v_pess + 1;
    -- (1) o dono já disse se ele instala ou é ajudante: nada (a palavra dele vale)
    continue when exists (select 1 from public.agenda_etiquetas e
                           where e.payee_id = r.id and e.origem = 'dono' and e.estado = 'vale' and e.etiqueta in ('instala', 'ajudante'));
    v_et := null;
    if public._agenda_tecnico_declarado(r.id, p_hoje) then
      -- (2) o técnico que o dono declarou (o padrão dele, vivo ou substituído, e o cadastro de novato_dias ou mais antes): instala
      -- sozinho, pelo que o dono disse dos dias
      select d.dias_semana into v_dias
        from public.agenda_disponibilidade d
       where d.payee_id = r.id and d.origem = 'dono' and d.dias_semana is not null and cardinality(d.dias_semana) > 0
         and d.situacao in ('disponivel', 'confirmada')
       order by d.criado_em desc, d.id desc
       limit 1;
      v_et := 'instala';
      v_nv := 2;
      v_mot := format('você disse que ele vem %s',
                      case when array(select distinct x from unnest(v_dias) x order by 1) = '{1,2,3,4,5}'::smallint[] then 'todo dia útil'
                           else public._agenda_dias_curtos(v_dias) end);
      v_ev := jsonb_build_object('declarado', true,
                                 'desde', (select min(d.criado_em) from public.agenda_disponibilidade d
                                            where d.payee_id = r.id and d.origem = 'dono' and d.dias_semana is not null
                                              and cardinality(d.dias_semana) > 0 and d.situacao in ('disponivel', 'confirmada')),
                                 'cadastro', r.created_at, 'dias', to_jsonb(v_dias));
    elsif exists (select 1 from public.work_profiles w
                   where w.payee_id = r.id and w.vigencia_inicio <= p_hoje and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje)) then
      -- (3) com perfil de diária vigente: o histórico (a 1ª vigência e as diárias da janela)
      v_desde := (select min(w.vigencia_inicio) from public.work_profiles w where w.payee_id = r.id);
      v_n := (select count(*)::int from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
               where w.payee_id = r.id and ws.tipo in ('normal', 'diaria')
                 and ws.data > p_hoje - cf.habilidade_janela_dias and ws.data <= p_hoje);
      v_casa := p_hoje - v_desde;
      v_qtas := case when v_n = 0 then 'ainda sem diária' when v_n = 1 then '1 diária' else v_n || ' diárias' end;
      if public._agenda_e_novato(r.id, p_hoje) then
        v_et := 'ajudante'; v_nv := 1; v_mot := format('começou em %s, %s', to_char(v_desde, 'DD/MM'), v_qtas);
      elsif v_n >= cf.habilidade_instala_diarias and v_casa >= cf.habilidade_instala_dias then
        v_et := 'instala'; v_nv := 2; v_mot := format('%s desde %s', v_qtas, to_char(v_desde, 'DD/MM'));
      else
        v_et := 'ajudante'; v_nv := 2; v_mot := format('entrou em %s, %s', to_char(v_desde, 'DD/MM'), v_qtas);
      end if;
      v_ev := jsonb_build_object('diarias', v_n, 'desde', v_desde, 'dias_de_casa', v_casa, 'janela', cf.habilidade_janela_dias);
    end if;
    -- (4) sem nada disso: nada (vale o padrão; o dia fixo sem perfil já é o papel novo de agenda_habilidades)
    continue when v_et is null;
    -- a viva do gestor já é esta (proposta ou valendo): nada
    continue when exists (select 1 from public.agenda_etiquetas e
                           where e.payee_id = r.id and e.origem = 'gestor' and e.estado in ('proposta', 'vale')
                             and e.etiqueta = v_et and e.nivel = v_nv);
    -- em teste, a proposta nunca troca o que já vale (o gatilho de exclusividade a substituiria)
    continue when v_modo = 'sombra'
                  and exists (select 1 from public.agenda_etiquetas e
                               where e.payee_id = r.id and e.estado = 'vale' and e.etiqueta in ('instala', 'ajudante'));
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, evidencia, criado_em)
    values (r.id, v_et, v_nv, 'gestor', 'proposta', v_mot, v_ev, p_agora);
    v_novas := v_novas || jsonb_build_object('payee_id', r.id, 'nome', r.nm, 'etiqueta', v_et, 'nivel', v_nv, 'motivo', v_mot);
  end loop;

  -- Uma pergunta só, com todas as propostas vivas. Refeita quando há proposta nova, quando o modo dela mudou (a de teste nunca é vista)
  -- ou quando uma proposta dela deixou de valer (o dono disse outra coisa antes de ver); sem nenhuma proposta viva, a aberta sai.
  v_vivas := array(select e.id from public.agenda_etiquetas e where e.origem = 'gestor' and e.estado = 'proposta' order by e.id);
  select q.id, q.modo into v_qid, v_qmodo
    from public.agenda_perguntas q
   where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta'
   order by q.criada_em desc, q.id desc
   limit 1;
  v_refaz := jsonb_array_length(v_novas) > 0
             or (cardinality(v_vivas) > 0
                 and (v_qid is null or v_qmodo <> v_modo
                      or exists (select 1 from public.agenda_etiquetas e where e.id = any (v_vivas) and e.pergunta_id is distinct from v_qid)
                      or exists (select 1 from public.agenda_etiquetas e where e.pergunta_id = v_qid and e.estado <> 'proposta')))
             or (cardinality(v_vivas) = 0 and v_qid is not null);
  if v_refaz then
    update public.agenda_perguntas q
       set estado = 'descartada',
           resolvida_motivo = case when cardinality(v_vivas) > 0 then 'a proposta mudou: perguntei de novo'
                                   else 'a proposta mudou: não sobrou nada a perguntar' end
     where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta';
    v_qid := null;
    if cardinality(v_vivas) > 0 then
      insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, criada_em)
      values ('habilidade', 'habilidade:equipe:' || p_hoje, public._agenda_habilidade_pergunta_texto(p_hoje, v_vivas), v_modo,
              '[]'::jsonb, p_agora)
      returning id into v_qid;
      update public.agenda_etiquetas set pergunta_id = v_qid where id = any (v_vivas);
    end if;
  end if;
  return jsonb_build_object('pessoas', v_pess, 'propostas', v_novas, 'vivas', cardinality(v_vivas), 'pergunta_id', v_qid,
                            'refeita', v_refaz, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_habilidade_propor(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5, R5.1-6): a proposta de quem faz o quê. População: a grade de p_hoje a p_hoje + 13 (agenda_capacidade), sem o dono, sem a pessoa a mais da 7b e sem quem vem sob demanda (_agenda_e_sob_demanda em todo dia da grade). Regras, nesta ordem: (1) com etiqueta vale do dono em instala ou ajudante → nada; (2) o técnico que o dono declarou (_agenda_tecnico_declarado) → instala 2, "você disse que ele vem todo dia útil" (os dias do padrão do dono; evidência {declarado, desde, cadastro, dias}); (3) com perfil de diária vigente — o novato da 7b (_agenda_e_novato) → ajudante 1 ("começou em 20/10, 3 diárias"), habilidade_instala_diarias ou mais diárias (as linhas normal/diaria de work_shifts na janela de habilidade_janela_dias) e habilidade_instala_dias ou mais de casa (desde a 1ª vigência) → instala 2 ("33 diárias desde 23/08"), senão ajudante 2 ("entrou em 29/09, 15 diárias"); evidência {diarias, desde, dias_de_casa, janela}; (4) senão nada. Nunca comissiona nem altura. Não repete a viva do gestor igual; em teste, não troca etiqueta que já vale. A proposta (origem gestor, estado proposta, criado_em = p_agora) substitui a do gestor de antes (o gatilho de exclusividade). UMA pergunta habilidade:equipe:<p_hoje> (ligada com modo_habilidade_propor ligado; senão em teste; perda_em nulo, sem opções; o texto de _agenda_habilidade_pergunta_texto), refeita com proposta nova, com o modo mudado ou com proposta dela que deixou de valer — a aberta de antes vira descartada ("a proposta mudou: perguntei de novo"); toda proposta viva aponta para ela. {pessoas, propostas [{payee_id, nome, etiqueta, nivel, motivo}], vivas, pergunta_id, refeita, modo}. Definer, sem grant (só a rodada agenda_habilidade a chama).';

-- ── 3. O prazo de veto (spec §5.5, §R2, §6.5; AG7-15) ───────────────────────────────────────────────────────────────

create or replace function public._agenda_habilidade_vetos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_q     record;
  v_prazo int;
  v_n     int := 0;
  v_m     int;
  v_lst   text;
  v_a     text;
  v_i     text;
  v_pay   jsonb;
  v_ets   jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_habilidade_vetos: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  -- O prazo, UMA vez: na 1ª rodada depois de a pergunta ligada ser mostrada (inteira, ou na forma curta com o prazo), contado da hora em
  -- que ela foi mostrada (o veto_ate vai de nulo a valor uma vez: mostrá-la de novo não adia). A que nunca foi mostrada nunca vence.
  update public.agenda_perguntas q
     set veto_ate = public._agenda_veto_ate(q.mostrada_em)
   where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta' and q.modo = 'ligado'
     and q.mostrada_em is not null and q.veto_ate is null;
  get diagnostics v_prazo = row_count;

  for v_q in
    select q.id
      from public.agenda_perguntas q
     where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta' and q.modo = 'ligado'
       and q.veto_ate is not null and p_agora > q.veto_ate
     order by q.criada_em, q.id
     for update
  loop
    select string_agg(x.nm || ' ' || x.curta, '; ' order by x.o),
           (array_agg(x.nm order by x.o) filter (where x.etiqueta = 'ajudante'))[1],
           (array_agg(x.nm order by x.o) filter (where x.etiqueta = 'instala'))[1],
           jsonb_agg(x.payee_id order by x.o),
           jsonb_agg(jsonb_build_object('payee_id', x.payee_id, 'nome', x.nm, 'etiqueta', x.etiqueta, 'nivel', x.nivel) order by x.o)
      into v_lst, v_a, v_i, v_pay, v_ets
      from (select e.payee_id, e.etiqueta, e.nivel, public._agenda_nome_curto(py.name) as nm,
                   split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1) as curta,
                   row_number() over (order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                               public._agenda_nome_curto(py.name), e.id) as o
              from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
             where e.pergunta_id = v_q.id and e.estado = 'proposta') x;
    update public.agenda_etiquetas set estado = 'vale', vale_desde = p_agora where pergunta_id = v_q.id and estado = 'proposta';
    get diagnostics v_m = row_count;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'sem resposta no prazo: ficou como eu marquei'
     where id = v_q.id;
    if v_m > 0 then
      insert into public.agenda_acoes (dia, executada, origem, tipo, pergunta_id, texto, depois, criada_em)
      values (p_hoje, true, 'vigia', 'habilidade', v_q.id,
              public._agenda_corta(format('Quem faz o quê: sem resposta no prazo, ficou como eu marquei — %s. Para mudar, me diga (ex.: "%s").',
                                          v_lst, case when v_a is not null then format('o %s instala sozinho', v_a)
                                                      else format('o %s é ajudante', coalesce(v_i, v_a)) end), 400),
              jsonb_build_object('payees', v_pay, 'etiquetas', v_ets), p_agora);
    end if;
    v_n := v_n + v_m;
  end loop;
  return jsonb_build_object('prazos', v_prazo, 'valeram', v_n);
end;
$function$;

comment on function public._agenda_habilidade_vetos(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5, §R2, §6.5; AG7-15): o prazo da pergunta habilidade:equipe ligada — na 1ª rodada depois de ela ser mostrada, veto_ate = _agenda_veto_ate(mostrada_em) (veto_du/veto_hora; uma vez: mostrá-la de novo não adia; a nunca mostrada nunca vence); com p_agora depois do prazo, as propostas dela valem (vale_desde = p_agora), a pergunta fecha ("sem resposta no prazo: ficou como eu marquei") e UMA ação habilidade (origem vigia, executada, sem *desfaz*: para mudar, o dono diz a frase) entra no "o que mudou": "Quem faz o quê: sem resposta no prazo, ficou como eu marquei — Roberto instala sozinho; João é ajudante. Para mudar, me diga (ex.: "o João instala sozinho")." {prazos, valeram}. Definer, sem grant.';

-- ── 4. A conferência em teste (spec §5.5, §6.6) ─────────────────────────────────────────────────────────────────────

create or replace function public._agenda_habilidade_conferir(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_linhas_max constant int := 6;   -- estrutural (como os c_ de agenda_propor): quantas ações de teste por dia, no máximo
  c_bits       constant jsonb := '{"energizado": 1, "comissionamento": 2, "altura": 4, "diagnostico": 8}';
  cf       public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_de     date;
  v_ate    date;
  v_n      jsonb;
  v_meios  jsonb := '[]'::jsonb;
  v_lid    jsonb := '[]'::jsonb;
  v_cand   jsonb := '[]'::jsonb;
  v_hab    jsonb := '{}'::jsonb;
  v_livres jsonb := '{}'::jsonb;
  v_exg    jsonb := '{}'::jsonb;
  v_dalt   int;
  v_nlid   int := 0;
  m        jsonb;
  r        record;
  h        record;
  c        record;
  v_l      jsonb;
  v_ex     int;
  v_eq     text[];
  v_nomes  text[];
  v_novos  text[];
  v_cli    text;
  v_quem   text;
  v_por    text;
  v_txt    text;
  v_ids    text[];
  v_hoje_n int;
  v_ins    int := 0;
  v_cort   int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_habilidade_conferir: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  v_de := public.agenda_somar_du(p_hoje, 1);
  v_ate := p_hoje + 7 * cf.habilidade_conferir_semanas;
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);

  -- o publicado avaliado com as regras de ligado (as etiquetas valem como se ligado): os meios-dias sem quem o serviço pede e os sem
  -- o responsável que fez o 1º dia (os dois turnos do mesmo dia, com a mesma equipe, numa linha)
  if cf.modo_habilidade = 'sombra' then
    select coalesce(jsonb_agg(jsonb_build_object('os', s.os, 'dia', s.dia, 'turno', s.turno, 'falta', s.falta,
                                                 'equipe', to_jsonb(s.equipe), 'dono_turno', s.dono_turno, 'ultimo', s.ultimo)
                              order by s.dia, s.turno = 'tarde', s.os), '[]'::jsonb)
      into v_meios
      from public._agenda_meios_sem_quem_pede(v_de, v_ate, p_hoje) s;
  end if;
  if cf.modo_lider = 'sombra' then
    select coalesce(jsonb_agg(jsonb_build_object('os', l.os, 'dia', l.dia, 'turnos', to_jsonb(l.turnos), 'lider', l.lider,
                                                 'lider_nome', l.lider_nome, 'equipe', to_jsonb(l.equipe))
                              order by l.dia, l.os), '[]'::jsonb),
           coalesce(sum(cardinality(l.turnos)), 0)
      into v_lid, v_nlid
      from (select x.os, x.dia, array_agg(x.turno order by x.turno = 'tarde') as turnos, x.lider, x.lider_nome, x.equipe
              from public._agenda_lideres_ausentes(v_de, v_ate, p_hoje) x
             group by x.os, x.dia, x.lider, x.lider_nome, x.equipe) l;
  end if;

  -- quem está livre em cada meio-dia (fora o dono) e o que cada um faz (uma leitura de cada)
  if jsonb_array_length(v_meios) > 0 or jsonb_array_length(v_lid) > 0 then
    for r in
      select g.dia, g.turno, array_agg(g.payee_id::text order by g.nome, g.payee_id) as ids
        from public.agenda_grade(v_de, v_ate, p_hoje) g
       where g.livre and not g.eh_dono
       group by g.dia, g.turno
    loop
      v_livres := v_livres || jsonb_build_object(r.dia || ' ' || r.turno, to_jsonb(r.ids));
    end loop;
    for h in
      select * from public.agenda_habilidades(p_hoje,
                 array(select distinct u.x::uuid from jsonb_each(v_livres) e, jsonb_array_elements_text(e.value) u(x))
                 || array(select distinct u.x::uuid from jsonb_array_elements(v_meios || v_lid) e, jsonb_array_elements_text(e -> 'equipe') u(x))
                 || v_dono)
    loop
      v_hab := v_hab || jsonb_build_object(h.payee_id::text, jsonb_build_array(h.instala, h.comissiona, h.altura, h.papel, h.nome));
      if h.eh_dono then
        v_dalt := h.altura;
      end if;
    end loop;
  end if;

  -- (a) o meio-dia sem quem o serviço pede
  for m in select e from jsonb_array_elements(v_meios) e loop
    v_cli := (select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                from public.service_orders so left join public.clients cl on cl.id = so.client_id where so.id = (m ->> 'os')::uuid);
    v_eq := array(select u.x from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o);
    v_nomes := array(select v_hab -> u.x ->> 4 from unnest(v_eq) u(x) order by v_hab -> u.x ->> 4, u.x);
    if m ->> 'falta' = 'novato_sozinho' then
      v_novos := array(select v_hab -> u.x ->> 4 from unnest(v_eq) u(x) where (v_hab -> u.x ->> 3)::int = 2 order by v_hab -> u.x ->> 4, u.x);
      v_quem := case when cardinality(v_novos) <= 1
                     then format('%s é novo e iria %s', coalesce(v_novos[1], v_nomes[1]),
                                 case when cardinality(v_eq) > 1 then 'sem um responsável junto' else 'sozinho' end)
                     else format('%s são novos e iriam %s', public._agenda_lista(v_novos, null),
                                 case when cardinality(v_eq) > cardinality(v_novos) then 'sem um responsável junto' else 'sozinhos' end) end;
      v_txt := format('Em teste (quem faz o quê): %s, %s — %s; eu poria alguém junto.', v_cli,
                      public._agenda_meio_texto((m ->> 'dia')::date, m ->> 'turno'), v_quem);
    else
      -- a máscara do meio-dia (a régua de _agenda_meios_sem_quem_pede): o que a OS pede em todos e, no último, o do último, menos
      -- quando o fechamento do dono naquele dia cobre
      if not v_exg ? (m ->> 'os') then
        v_exg := v_exg || jsonb_build_object(m ->> 'os', public.os_exigencias((m ->> 'os')::uuid, p_hoje));
      end if;
      v_ex := coalesce((v_exg #>> array[m ->> 'os', 'todos'])::int, 0)
              | case when (m ->> 'ultimo')::boolean
                          and not (cf.habilidade_fechamento_cobre
                                   and exists (select 1 from public.agenda_alocacoes x
                                                where x.service_order_id = (m ->> 'os')::uuid and x.dia = (m ->> 'dia')::date
                                                  and x.presenca = 'fechamento' and x.payee_id is not distinct from v_dono
                                                  and x.estado in ('publicada', 'fixada')))
                     then coalesce((v_exg #>> array[m ->> 'os', 'ultimo'])::int, 0) else 0 end;
      v_quem := case cardinality(v_eq) when 0 then 'só você iria' when 1 then v_nomes[1] || ' iria sozinho'
                                       else public._agenda_lista(v_nomes, null) || ' iriam sozinhos' end;
      -- quem eu poria: o 1º livre no meio-dia (o menos qualificado que dá conta, depois o nome) com quem a equipe passa a atender
      v_por := null;
      for c in
        select u.x as id, v_hab -> u.x ->> 4 as nome
          from jsonb_array_elements_text(coalesce(v_livres -> ((m ->> 'dia') || ' ' || (m ->> 'turno')), '[]'::jsonb)) u(x)
         where not (u.x = any (v_eq)) and v_hab ? u.x
         order by (v_hab -> u.x ->> 0)::int, v_hab -> u.x ->> 4, u.x
      loop
        v_ids := v_eq || c.id;
        if public._agenda_atende(v_ex,
             array(select (v_hab -> t.y ->> 0)::int from unnest(v_ids) with ordinality t(y, o) order by t.o),
             array(select (v_hab -> t.y ->> 1)::int from unnest(v_ids) with ordinality t(y, o) order by t.o),
             array(select (v_hab -> t.y ->> 2)::int from unnest(v_ids) with ordinality t(y, o) order by t.o),
             array(select (v_hab -> t.y ->> 3)::int from unnest(v_ids) with ordinality t(y, o) order by t.o),
             (m ->> 'dono_turno')::boolean, v_dalt, v_n) is null then
          v_por := c.nome;
          exit;
        end if;
      end loop;
      v_txt := format('Em teste (quem faz o quê): %s, %s — %s, e esse dia pede %s; %s.', v_cli,
                      public._agenda_meio_texto((m ->> 'dia')::date, m ->> 'turno'), v_quem,
                      public._agenda_exigencia_texto((c_bits ->> (m ->> 'falta'))::int, null),
                      coalesce('eu poria ' || v_por, 'ninguém com isso está livre: eu mudaria o dia'));
    end if;
    v_cand := v_cand || jsonb_build_object('dia', m -> 'dia', 't', case when m ->> 'turno' = 'manha' then 1 else 2 end, 'k', 0,
                                           'os', m -> 'os',
                                           'antes', jsonb_build_object('os', m -> 'os', 'dia', m -> 'dia', 'turno', m -> 'turno',
                                                                       'codigo', m -> 'falta'),
                                           'texto', public._agenda_corta(v_txt, 400));
  end loop;

  -- (b) o meio-dia sem o responsável que fez o 1º dia (ou que o dono disse), sem o dono no turno
  for m in select e from jsonb_array_elements(v_lid) e loop
    v_cli := (select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                from public.service_orders so left join public.clients cl on cl.id = so.client_id where so.id = (m ->> 'os')::uuid);
    v_l := public._agenda_lider_da_os((m ->> 'os')::uuid, p_hoje);
    v_nomes := array(select coalesce(v_hab -> u.x ->> 4, (select public._agenda_nome_curto(py.name) from public.payees py where py.id = u.x::uuid))
                       from jsonb_array_elements_text(m -> 'equipe') u(x) order by 1);
    v_txt := format('Em teste (responsável fixo): %s, %s — o responsável é %s (%s), mas o dia está com %s; eu manteria %s.', v_cli,
                    case when jsonb_array_length(m -> 'turnos') = 1 then public._agenda_meio_texto((m ->> 'dia')::date, m -> 'turnos' ->> 0)
                         else public._dia_curto((m ->> 'dia')::date) end,
                    m ->> 'lider_nome', case v_l ->> 'fonte' when 'dono' then 'você disse' else 'fez o 1º dia' end,
                    public._agenda_lista(v_nomes, null), m ->> 'lider_nome');
    v_cand := v_cand || jsonb_build_object('dia', m -> 'dia',
                                           't', case when jsonb_array_length(m -> 'turnos') > 1 then 0
                                                     when m -> 'turnos' ->> 0 = 'manha' then 1 else 2 end,
                                           'k', 1, 'os', m -> 'os',
                                           'antes', jsonb_build_object('os', m -> 'os', 'dia', m -> 'dia',
                                                                       'turno', case when jsonb_array_length(m -> 'turnos') = 1
                                                                                     then m -> 'turnos' -> 0 else 'null'::jsonb end,
                                                                       'codigo', 'lider'),
                                           'texto', public._agenda_corta(v_txt, 400));
  end loop;

  -- as ações de teste: no máximo c_linhas_max por dia, sem repetir a do mesmo meio-dia e código (o mesmo antes) no dia
  select count(*)::int into v_hoje_n
    from public.agenda_acoes a where a.tipo = 'habilidade' and not a.executada and a.origem = 'vigia' and a.dia = p_hoje;
  for m in
    select e from jsonb_array_elements(v_cand) e
     order by e ->> 'dia', (e ->> 't')::int, (e ->> 'k')::int,
              (select so.service_order_number from public.service_orders so where so.id = (e ->> 'os')::uuid)
  loop
    continue when exists (select 1 from public.agenda_acoes a
                           where a.tipo = 'habilidade' and not a.executada and a.origem = 'vigia' and a.dia = p_hoje
                             and a.antes = m -> 'antes');
    if v_hoje_n >= c_linhas_max then
      v_cort := v_cort + 1;
      continue;
    end if;
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, texto, antes, criada_em)
    values (p_hoje, false, 'vigia', 'habilidade', (m ->> 'os')::uuid, m ->> 'texto', m -> 'antes', p_agora);
    v_hoje_n := v_hoje_n + 1;
    v_ins := v_ins + 1;
  end loop;
  return jsonb_build_object('meios_sem_quem_pede', jsonb_array_length(v_meios), 'sem_lider', v_nlid, 'acoes', v_ins,
                            'cortadas', v_cort, 'de', v_de, 'ate', v_ate);
end;
$function$;

comment on function public._agenda_habilidade_conferir(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5, §6.6): a conferência em teste do publicado, do próximo dia útil a p_hoje + 7 × habilidade_conferir_semanas — com modo_habilidade em sombra, os meios-dias sem quem o serviço pede (_agenda_meios_sem_quem_pede, as etiquetas como se ligado); com modo_lider em sombra, os sem o responsável que fez o 1º dia (_agenda_lideres_ausentes; os dois turnos do mesmo dia numa linha). Cada um vira uma ação habilidade de teste (origem vigia, executada = false, dia = p_hoje, antes = {os, dia, turno, codigo}): "Em teste (quem faz o quê): Ivo, ter 10/11 à tarde — João iria sozinho, e esse dia pede quem instala sozinho com 220 V ou banco de bateria; eu poria Roberto." (quem eu poria: o 1º livre no meio-dia, o menos qualificado que dá conta, com quem a equipe passa a atender; sem ninguém, "ninguém com isso está livre: eu mudaria o dia"); "… — Bruno é novo e iria sozinho; eu poria alguém junto."; "Em teste (responsável fixo): Edu, qua 11/11 — o responsável é Roberto (fez o 1º dia), mas o dia está com João; eu manteria Roberto.". No máximo 6 por dia (c_linhas_max), sem repetir o mesmo antes no dia (as que passam contam em cortadas). Vão às linhas de sombra do fechamento, nunca ao texto do dono. {meios_sem_quem_pede, sem_lider, acoes, cortadas, de, ate}. Definer, sem grant.';

-- ── 5. A pergunta por OS (spec §5.5, §6.4) ─────────────────────────────────────────────────────────────────────────

create or replace function public._agenda_habilidade_perguntas_os(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_bits constant int[] := array[1, 2, 4, 8];
  cf     public.agenda_config := public._agenda_cfg();
  v_pid  uuid;
  v_alvo uuid[];
  v_fora jsonb;
  f      jsonb;
  v_os   uuid;
  v_ex   jsonb;
  v_pede text;
  v_bit  int;
  v_resp text;
  v_cli  text;
  v_ab   int := 0;
  v_res  int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_habilidade_perguntas_os: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  -- a última proposta do motor de hoje (qualquer escopo)
  select x.id, x.os_alvo, x.fora into v_pid, v_alvo, v_fora
    from public.agenda_propostas x
   where (x.parametros ->> 'p_hoje')::date = p_hoje
   order by x.criada_em desc, x.id desc
   limit 1;
  if v_pid is null then
    return jsonb_build_object('proposta', null, 'abertas', 0, 'resolvidas', 0);
  end if;
  -- o exemplo de quem pode ser o responsável: o 1º responsável da grade (sem o dono)
  select h.nome into v_resp from public.agenda_habilidades(p_hoje) h where not h.eh_dono and h.papel = 0 order by h.nome, h.payee_id limit 1;

  for f in select e from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) e where e ->> 'motivo' = 'habilidade' loop
    v_os := (f ->> 'os')::uuid;
    continue when v_os is null
                  or exists (select 1 from public.agenda_perguntas q where q.chave = 'habilidade:os:' || v_os and q.estado = 'aberta');
    v_ex := public.os_exigencias(v_os, p_hoje);
    v_pede := concat_ws(' e ', public._agenda_exigencia_texto(nullif(coalesce((v_ex ->> 'todos')::int, 0), 0), 'todos'),
                               public._agenda_exigencia_texto(nullif(coalesce((v_ex ->> 'ultimo')::int, 0), 0), 'ultimo'));
    continue when nullif(v_pede, '') is null;
    v_bit := (select b from unnest(c_bits) b where (coalesce((v_ex ->> 'todos')::int, 0) | coalesce((v_ex ->> 'ultimo')::int, 0)) & b <> 0
               order by b limit 1);
    v_cli := coalesce(nullif(f ->> 'cliente_curto', ''), f ->> 'numero');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo, opcoes, criada_em)
    values ('habilidade', 'habilidade:os:' || v_os, v_os,
            public._agenda_corta(format('%s: o serviço pede %s, e nas próximas %s semanas não acho ninguém com isso livre. Quem pode? Me diga numa frase (ex.: %s).',
                                        v_cli, v_pede, cf.horizonte_semanas,
                                        concat_ws(' ou ', case when v_resp is not null then format('"o responsável do %s é o %s"', v_cli, v_resp) end,
                                                  format('"o %s não precisa de %s"', v_cli, public._agenda_exigencia_texto(v_bit, null)))), 600),
            'ligado', '[]'::jsonb, p_agora);
    v_ab := v_ab + 1;
  end loop;

  -- a aberta de uma OS que voltou a caber (estava na proposta e não ficou de fora) fecha
  update public.agenda_perguntas q
     set estado = 'resolvida', resolvida_motivo = 'coube: a equipe tem quem o serviço pede'
   where q.tipo = 'habilidade' and q.chave like 'habilidade:os:%' and q.estado = 'aberta'
     and q.service_order_id = any (coalesce(v_alvo, '{}'::uuid[]))
     and not exists (select 1 from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) e where (e ->> 'os')::uuid = q.service_order_id);
  get diagnostics v_res = row_count;
  return jsonb_build_object('proposta', v_pid, 'abertas', v_ab, 'resolvidas', v_res);
end;
$function$;

comment on function public._agenda_habilidade_perguntas_os(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5, §6.4): com modo_habilidade ligado — a última agenda_propostas de hoje (qualquer escopo): cada OS que ela deixou de fora com o motivo habilidade ganha UMA pergunta habilidade:os:<os> (ligada, não crítica, sem prazo): "Caio: o serviço pede quem comissiona Victron em todos os dias, e nas próximas 6 semanas não acho ninguém com isso livre. Quem pode? Me diga numa frase (ex.: "o responsável do Caio é o Alex" ou "o Caio não precisa de quem comissiona Victron")." (o exemplo do responsável: o 1º responsável da grade); a aberta de uma OS que estava na proposta e não ficou de fora fecha ("coube: a equipe tem quem o serviço pede"). {proposta, abertas, resolvidas}. Definer, sem grant.';

-- ── 6. As medidas (spec §5.5; o 7g e o foco as leem) ───────────────────────────────────────────────────────────────

create or replace function public.agenda_habilidade_medidas(p_de date, p_ate date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_uid   uuid := auth.uid();
  v_papel text;
  v_dono  uuid := public._agenda_dono(null);
  v_n     jsonb;
  v_sr    jsonb;
  v_sl    jsonb;
  v_dt    jsonb := '[]'::jsonb;
  v_hab   jsonb := '{}'::jsonb;
  v_livres jsonb := '{}'::jsonb;
  v_exg   jsonb := '{}'::jsonb;
  v_dalt  int;
  v_ex    int;
  r       record;
  h       record;
  k       text;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (a rodada, o foco pelo WhatsApp).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'As medidas de quem faz o quê são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'As medidas de quem faz o quê são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_de is null or p_ate is null or p_hoje is null then
    raise exception 'agenda_habilidade_medidas: p_de, p_ate e p_hoje são obrigatórios.' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);

  -- alguém sozinho em serviço que pede outra pessoa: a janela inteira (as passadas cumpridas também), pelas etiquetas de p_hoje, com a
  -- equipe dita pelo dono (o que ele disse também conta na medida)
  select coalesce(jsonb_agg(jsonb_build_object('os', s.os, 'numero', so.service_order_number, 'dia', s.dia, 'turno', s.turno,
                                               'falta', s.falta) order by s.dia, s.turno = 'tarde', so.service_order_number), '[]'::jsonb)
    into v_sr
    from public._agenda_meios_sem_quem_pede(p_de, p_ate, p_hoje, null, true) s
    join public.service_orders so on so.id = s.os;
  -- o responsável que fez o 1º dia (ou que o dono disse) ausente
  select coalesce(jsonb_agg(jsonb_build_object('os', l.os, 'numero', so.service_order_number, 'dia', l.dia, 'turno', l.turno,
                                               'lider', l.lider_nome) order by l.dia, l.turno = 'tarde', so.service_order_number), '[]'::jsonb)
    into v_sl
    from public._agenda_lideres_ausentes(p_de, p_ate, p_hoje) l
    join public.service_orders so on so.id = l.os;

  -- os meios-dias do dono de turno em que alguém da equipe estava livre e atendia sozinho o que o meio-dia pedia
  if exists (select 1 from public.agenda_alocacoes a
              where a.payee_id = v_dono and a.presenca = 'turno' and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
                and a.dia between p_de and p_ate) then
    for r in
      select g.dia, g.turno, array_agg(g.payee_id::text order by g.nome, g.payee_id) as ids
        from public.agenda_grade(p_de, p_ate, p_hoje) g
       where g.livre and not g.eh_dono
       group by g.dia, g.turno
    loop
      v_livres := v_livres || jsonb_build_object(r.dia || ' ' || r.turno, to_jsonb(r.ids));
    end loop;
    for h in
      select * from public.agenda_habilidades(p_hoje,
                 array(select distinct u.x::uuid from jsonb_each(v_livres) e, jsonb_array_elements_text(e.value) u(x)) || v_dono)
    loop
      v_hab := v_hab || jsonb_build_object(h.payee_id::text, jsonb_build_array(h.instala, h.comissiona, h.altura, h.papel, h.nome));
      if h.eh_dono then
        v_dalt := h.altura;
      end if;
    end loop;
    for r in
      select d.os, d.dia, d.turno, d.numero,
             (d.dia, d.turno) = (f.dia, f.turno) as ultimo,
             exists (select 1 from public.agenda_alocacoes x
                      where x.service_order_id = d.os and x.dia = d.dia and x.presenca = 'fechamento'
                        and x.payee_id is not distinct from v_dono and x.estado in ('publicada', 'fixada')) as fecha
        from (select distinct a.service_order_id as os, a.dia, a.turno, so.service_order_number as numero
                from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id
               where a.payee_id = v_dono and a.presenca = 'turno' and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
                 and a.dia between p_de and p_ate) d
        left join lateral (select x.dia, x.turno from public.agenda_alocacoes x
                            where x.service_order_id = d.os and x.presenca = 'turno' and x.tipo <> 'reserva'
                              and x.estado in ('publicada', 'fixada')
                            order by x.dia desc, x.turno desc limit 1) f on true
       order by d.dia, d.turno = 'tarde', d.numero
    loop
      if not v_exg ? r.os::text then
        v_exg := v_exg || jsonb_build_object(r.os::text, public.os_exigencias(r.os, p_hoje));
      end if;
      v_ex := coalesce((v_exg #>> array[r.os::text, 'todos'])::int, 0)
              | case when r.ultimo and not (cf.habilidade_fechamento_cobre and r.fecha)
                     then coalesce((v_exg #>> array[r.os::text, 'ultimo'])::int, 0) else 0 end;
      select u.x into k
        from jsonb_array_elements_text(coalesce(v_livres -> (r.dia || ' ' || r.turno), '[]'::jsonb)) u(x)
       where v_hab ? u.x
         and public._agenda_atende(v_ex, array[(v_hab -> u.x ->> 0)::int], array[(v_hab -> u.x ->> 1)::int],
                                   array[(v_hab -> u.x ->> 2)::int], array[(v_hab -> u.x ->> 3)::int], false, v_dalt, v_n) is null
       order by (v_hab -> u.x ->> 0)::int, v_hab -> u.x ->> 4, u.x
       limit 1;
      if k is not null then
        v_dt := v_dt || jsonb_build_object('os', r.os, 'numero', r.numero, 'dia', r.dia, 'turno', r.turno, 'quem', v_hab -> k ->> 4);
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'de', p_de, 'ate', p_ate,
    'sozinho_em_risco', jsonb_array_length(v_sr),
    'sem_lider', jsonb_array_length(v_sl),
    'troca_de_lider', (select count(distinct a.service_order_id)::int from public.agenda_alocacoes a
                        where (a.criado_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
                          and a.criterio_detalhe ->> 'lider_trocado' = 'true'),
    'dono_em_tarefa_de_outro', jsonb_array_length(v_dt),
    'correcoes_quem_vai', (select count(*)::int from public.agenda_rascunho x
                            where x.gravado_em is not null
                              and (x.gravado_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
                              and (x.tipo = 'habilidade' or (x.tipo = 'marcar' and x.dados ? 'pessoa')
                                   or (x.tipo = 'planejar' and x.dados ? 'com_quem'))),
    'criterios', coalesce((select jsonb_object_agg(z.criterio, z.n order by z.criterio)
                             from (select coalesce(a.criterio, 'regra:' || coalesce(a.criterio_detalhe ->> 'regra', 'nenhuma')) as criterio,
                                          count(*)::int as n
                                     from public.agenda_alocacoes a
                                    where (a.criado_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
                                    group by 1) z), '{}'::jsonb),
    'etiquetas', jsonb_build_object(
      'dono', (select count(*)::int from public.agenda_etiquetas e where e.origem = 'dono' and e.estado = 'vale'),
      'gestor_vale', (select count(*)::int from public.agenda_etiquetas e where e.origem = 'gestor' and e.estado = 'vale'),
      'propostas', (select count(*)::int from public.agenda_etiquetas e where e.estado = 'proposta')),
    'retrabalho', 'nao_medido',
    'detalhe', jsonb_build_object('sozinho_em_risco', v_sr, 'sem_lider', v_sl, 'dono_em_tarefa_de_outro', v_dt));
end;
$function$;

comment on function public.agenda_habilidade_medidas(date, date, date) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5, §11): as medidas de quem faz o quê, de p_de a p_ate, pelas etiquetas de p_hoje — sozinho_em_risco (os meios-dias de turno publicados, também os passados e os da equipe dita pelo dono, sem quem o serviço pede: _agenda_meios_sem_quem_pede; meta 0), sem_lider (_agenda_lideres_ausentes), troca_de_lider (as OS com alocação criada na janela com criterio_detalhe.lider_trocado), dono_em_tarefa_de_outro (os meios-dias do dono de turno em que alguém da equipe estava livre e atendia sozinho o que o meio-dia pedia), correcoes_quem_vai (os rascunhos gravados na janela de quem faz o quê, do marcar com pessoa e do planejar com com_quem), criterios (as alocações criadas na janela por critério; sem critério, "regra:<regra>"), etiquetas {dono, gestor_vale, propostas}, retrabalho "nao_medido" e detalhe {sozinho_em_risco, sem_lider, dono_em_tarefa_de_outro} (as linhas). Com login, só admin/financeiro (senão 42501); sem login, só o service_role. STABLE; definer (a spec dizia invoker: as avaliações do publicado não têm grant a ninguém); authenticated e service_role.';

-- ── 7. A rodada (spec §5.5; o molde de agenda_aprender) ─────────────────────────────────────────────────────────────

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
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada de quem faz o quê.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_habilidade'));
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('modo_habilidade', cf.modo_habilidade, 'modo_lider', cf.modo_lider,
                                'modo_habilidade_propor', cf.modo_habilidade_propor);
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
  'Agenda de Produção (Fase 7c, P5; spec §5.5): a rodada de quem faz o quê (o passo 0b2a do task-automations, a cada tique; o molde de agenda_aprender) — uma vez por dia, a partir de habilidade_hora (antes: {rodou: false, cedo: true}; o 2º tique do dia: {rodou: false, ja_rodou: true}); com pg_advisory_xact_lock. Os passos, cada um no seu bloco (o que falha vai a log_app_error, context agenda, action habilidade:<passo>, e os outros seguem): propor (_agenda_habilidade_propor, com modo_habilidade_propor fora de desligado), vetos (_agenda_habilidade_vetos, sempre), conferir (_agenda_habilidade_conferir, com modo_habilidade ou modo_lider em sombra), perguntas_os (_agenda_habilidade_perguntas_os, com modo_habilidade ligado) e medir (agenda_habilidade_medidas dos últimos 30 dias, sem o detalhe; sempre). Grava agenda_vigia_rodadas (rotina habilidade; contagens com o resultado de cada passo, os 3 modos e as falhas). {rodou, modos, contagens, erros, falhas}. Nenhuma mensagem a ninguém. Definer; só service_role.';

-- ── 8. A linha (n) do fechamento com as perguntas de quem faz o quê (R5.4 item 4; recriada da 20261101100860) ─────────

-- (FASE 7b correção 3, 20261101100860, a origem; o 7c P8 recria de novo a partir DESTA)
-- _agenda_linhas_do_fechamento (de 20261101100860_agenda_fase77b_correcao3.sql)
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
        -- (7c P5) as perguntas da equipe da 7b só com o portão da 7b (o bloco pode estar rodando só pela 7c)
        continue when not v_7c_7b;
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o R5.10-7): na linha (n) da equipe, a forma curta (texto_curto, a que o Secretário cheio usa, e o registro conta as pergunta_ids da linha sem saber qual forma saiu) leva, em cada pergunta que vence, o prazo e o "sigo assim" — "Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra." —, com a data que o vencimento grava: a chamada contada na linha, com o cadastro fora de desligado, em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (ou o veto_ate já gravado); a dos dias da semana, com modo_dias fora de desligado, no prazo da semana dela (perda_em, hora_do_plano − equipe_dias_fechar_antes). O telefone e o contato não vencem: como antes. A forma longa e o resto, byte a byte. FASE 7c (P5, R5.4 item 4, R5.1-6, R5.10-7/-8): o portão da linha (n) passa a "a 7b (modo_dias ou modo_cadastro) OU a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado"; dentro dela, as perguntas da 7b só com o portão da 7b e, depois delas, as de quem faz o quê (habilidade: primeiro a habilidade:equipe, depois as habilidade:os) só com o da 7c, com o modo de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade). A da equipe que vai só como "Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)." fica fora de pergunta_ids (não conta como vista); a de OS ("Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).") conta. A forma curta leva o que foi marcado e, na da equipe contada e ligada, o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00, fica assim" (o veto_ate, ou _agenda_veto_ate do dia de hoje: a data que _agenda_habilidade_vetos grava depois do registro). A pergunta de fato (e) exclui as da 7b só com o portão da 7b e as de quem faz o quê só com o da 7c. Com os modos da 7c desligados, a saída de antes, byte a byte (com a 7b desligada e em teste).';

-- ── 9. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────
-- A rodada: só o service_role (o task-automations). As medidas: o painel (admin/financeiro, conferido dentro) e o service_role; nunca
-- anon. As peças de dentro (os passos e o texto da pergunta): sem grant a ninguém, nem service_role (só a rodada, definer, as chama).
-- A recriada mantém as portas dela (create or replace não muda a ACL; repetidas aqui para a migration se bastar): leitura do painel.
revoke all on function public.agenda_habilidade(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_habilidade(date, timestamptz) to service_role;
revoke all on function public.agenda_habilidade_medidas(date, date, date) from public, anon;
grant execute on function public.agenda_habilidade_medidas(date, date, date) to authenticated, service_role;
revoke all on function
  public._agenda_habilidade_propor(date, timestamptz), public._agenda_habilidade_vetos(date, timestamptz),
  public._agenda_habilidade_conferir(date, timestamptz), public._agenda_habilidade_perguntas_os(date, timestamptz),
  public._agenda_habilidade_pergunta_texto(date, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_linhas_do_fechamento(date) from public, anon;
grant execute on function public._agenda_linhas_do_fechamento(date) to authenticated, service_role;
