-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê"), pacote P6: as leituras — o foco habilidades (*agenda quem faz*,
-- "quem faz o quê?": o que cada pessoa faz e de onde veio, o que cada OS pede e por qual linha, o responsável, o que a agenda teria mudado
-- em teste hoje e as medidas dos últimos 30 dias; com uma OS, só o bloco dela) e o porquê "falta quem o serviço pede" nos textos do que
-- ficou de fora (o foco gestor, o aviso do gestor e a linha da semana do fechamento).
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§R5.3-6, §R5.4, §R5.5 item 6, §R5.6, §R5.1-6, §5.6, §6.7, §8.3
-- agenda_fase7c_leituras.sql, §8.5); nomes: fase7-registro.md §1 (7c P6); respostas do dono: fase7-padroes.md (AG7-10 "sem etiqueta = pode
-- tudo, menos comissionar"; AG7-15 sem resposta no prazo fica como proposto).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (o foco gestor e os textos do fora da correção 2, 20261031100985; agenda_ver
-- de 20261031100600), da 7b inteira e da 7c P1 a P5 (20261102100000 .. 100400: agenda_etiquetas, agenda_habilidades, os_exigencias,
-- _agenda_atende, o responsável, as avaliações do publicado; o motor e o fora habilidade; a conversa; a rodada, as ações de teste e
-- agenda_habilidade_medidas).
--
-- ═══ DDL — OK NOMEADO ═══ (1 função nova e 5 recriadas; nenhuma tabela, coluna, lista ou dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7c/p6/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o
-- montador para se outra migration anterior a esta a definir depois da origem) — agenda_ver de 20261031100600_agenda_fase7a_rodada.sql,
-- _agenda_linha_da_semana de 20261025100500_agenda_fase2_leituras.sql e _agenda_gestor_motivo_texto, _agenda_gestor_motivo_ordem e
-- _agenda_aviso_fora_texto de 20261031100985_agenda_fase77a_correcao2.sql (o R5.4 diz o mesmo) —, e as mudanças entram SÓ como inserções:
-- um bloco "-- FASE 7c: … -- FASE 7c: fim" antes de uma linha que aparece uma vez no corpo. Nenhuma linha de antes é trocada. Tirados os
-- blocos, cada corpo é o da origem, byte a byte (o montador e o L6 de supabase/tests/agenda_fase7c_leituras.sql conferem).
--
-- POR QUE: o P1 a P5 deram a cada pessoa o que ela faz, a cada OS o que ela pede, o responsável, a proposta do gestor e a conferência em
-- teste — mas o dono não tinha onde ler nada disso: a palavra *agenda quem faz* do P4 ia a um agenda_ver que não conhecia o foco. E a OS
-- que o motor da 7c deixa de fora por falta de quem o serviço pede (o fora habilidade do P2) caía em "outro motivo" no foco gestor e no
-- aviso do gestor, e não aparecia no "Fora:" da linha da semana.
--
-- O QUE MUDA:
--   1. _agenda_ver_habilidades(p_hoje, p_agora, p_os default null) — o foco (§6.7), {ok, rota 'habilidades', texto, dados {pessoas, os,
--      em_teste, medidas}}: a 1ª linha diz o modo ("Quem faz o quê (em teste: ainda escalo como antes):"; ligado "(já escalo por isso):";
--      desligado "(desligado: a agenda não usa):"); uma linha por pessoa (você primeiro; a grade de hoje a +13 e quem tem etiqueta), com
--      de onde veio cada coisa — "(padrão)", "(você disse)", "(eu marquei: 32 diárias desde 23/08; vale desde ter 03/11)" e, na proposta do
--      gestor que ainda não vale, "(eu marquei: …; espero você até ter 03/11)" (o prazo de veto; antes de a pergunta ser vista, "espero
--      você ver a pergunta"; em teste, "(em teste, eu marcaria: …)"); o que vale para quem não tem nada marcado; "O que as OS pedem:", uma
--      linha por OS da carteira que pede alguém em especial (as marcadas primeiro), com a linha do orçamento que disparou e o responsável
--      que o dono disse ou que fez o 1º dia; "Em teste, hoje eu teria mudado: …" (as ações de teste de hoje); "Nos últimos 30 dias: …"
--      (agenda_habilidade_medidas); e "Para corrigir, me diga numa frase (ex.: …)." O conteúdo vai até texto_max (corta pelas linhas de OS,
--      com "e mais N OS"), e a linha "Para corrigir" vem depois, num teto estrutural de 1.500 (R5.6). Com p_os, só o bloco da OS: o que
--      ela pede e de onde veio, o fechamento que cobre o último dia, o responsável, quem vai, quem faz sozinho o que ela pede (e quem
--      precisa de alguém junto, com o porquê), os meios-dias marcados sem quem o serviço pede, o que eu teria mudado nela em teste.
--   2. agenda_ver (recriada da 20261031100600; um bloco) — o foco habilidades, antes da conferência dos 19 da Fase 6 (como o gestor: o
--      foco que não existe continua com a mensagem dos 19, R5.6); a porta do aprendizado: sem p_hoje, 22004; com login, só administrador
--      e financeiro (42501, antes de ler a config); a leitura desligada, a frase de sempre; com os, a OS pelo resolvedor (a que não existe
--      ou é ambígua: a frase dele, como os outros focos).
--   3. _agenda_linha_da_semana (recriada da 20261025100500; um bloco) — o fora habilidade também vai no "Fora:" da semana publicada.
--   4. _agenda_gestor_motivo_texto, _agenda_gestor_motivo_ordem e _agenda_aviso_fora_texto (recriadas da 20261031100985; um bloco cada;
--      R5.3-6) — o motivo habilidade é "falta quem o serviço pede" (no foco gestor, antes de "sem lugar na agenda"; no aviso do gestor),
--      não "outro motivo".
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7c_leituras.sql; registradas em notas-fase77c.md, P6):
--   · _agenda_ver_habilidades tem grant a authenticated e service_role (a §5.6 dizia "definer, sem grant"), com a porta explícita (com
--     login, só admin/financeiro, senão 42501; sem login, só o service_role): agenda_ver é invoker e é lida pelo painel e pelo WhatsApp —
--     sem o grant, todo agenda_ver foco habilidades dava 42501. É definer porque lê o responsável e as avaliações do publicado, que o P1
--     deixou sem grant a ninguém (o molde do agenda_habilidade_medidas do P5);
--   · a proposta do gestor aparece na linha da pessoa no lugar do que vale hoje (o R5.1-6: "Alex: instala sozinho (eu marquei: você disse
--     que ele vem todo dia útil; espero você até ter 03/11)"), com o motivo (o §6.7 dava "(eu marquei; espero …)" sem ele); antes de a
--     pergunta ser vista não há prazo: "espero você ver a pergunta"; a proposta em teste: "(em teste, eu marcaria: …)";
--   · na linha da OS, o responsável só quando o dono disse ou alguém fez o 1º dia (o planejado só desempata: com p_os, os três);
--   · o bloco da OS (com p_os; a §5.6 só dizia "o que pede, de onde veio, o responsável, quem iria"): "quem iria" é quem vai no plano
--     (_agenda_pessoas_texto) e quem da equipe faz sozinho o que ela pede, pela regra única (_agenda_atende), com o porquê de quem precisa
--     de alguém junto ("João (é ajudante: não vai sozinho em serviço de risco)") — é o que responde "por que o João não vai sozinho no
--     Lenine?" (o H76) com o texto do banco.
--
-- O QUE NÃO MUDA: os outros focos de agenda_ver (o bloco novo só roda com o foco habilidades, antes de tudo); a linha da semana sem fora
-- habilidade; os textos do fora com os outros motivos. O motivo habilidade só nasce com modo_habilidade ligado (o fora do P2): com a 7c
-- desligada ou em teste, as 4 recriadas devolvem o de antes, byte a byte. O foco só lê: nenhuma escrita, nenhuma mensagem.
--
-- ORDEM DE LIGAR (spec §10, R5.5): depois de 20261102100000 .. 100400 (P1 a P5); antes de 20261102100550 (P8). O 7d P8 recria agenda_ver
-- copiando DESTA (a cadeia do fase7-registro §2).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7c_leituras.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261102100500
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261102100500_agenda_fase7c_leituras.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261102100500', 'agenda_fase7c_leituras');"
--
-- DESFAZER: recriar agenda_ver com o corpo de 20261031100600, _agenda_linha_da_semana com o de 20261025100500 e as 3 do fora com o de
--   20261031100985; e
--   drop function if exists public._agenda_ver_habilidades(date, timestamptz, uuid);
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. O foco habilidades (spec §5.6, §6.7; R5.6, R5.1-6) ───────────────────────────────────────────────────────────

-- Quem faz o quê na equipe e o que cada OS pede, na palavra do dono. Só lê. Definer (o responsável e as avaliações do publicado não
-- têm grant), com a porta dentro: com login, só admin/financeiro (42501); sem login, só o service_role. authenticated e service_role
-- (agenda_ver, invoker, a chama).
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
  'Agenda de Produção (Fase 7c, P6; spec §5.6, §6.7; R5.6, R5.1-6): o foco habilidades de agenda_ver — quem faz o quê na equipe e o que cada OS pede, na palavra do dono. "Quem faz o quê (em teste: ainda escalo como antes):" (ligado "(já escalo por isso):"; desligado "(desligado: a agenda não usa):"); uma linha por pessoa (você primeiro; a grade de hoje a +13 e quem tem etiqueta: o texto de agenda_habilidades, com "; vale desde ter 03/11" na etiqueta do gestor e, no lugar do instala/ajudante, a proposta do gestor que ainda não vale — "Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você até ter 03/11)", "espero você ver a pergunta" antes de vista, "(em teste, eu marcaria: …)" em teste); "Quem não tem nada marcado pode tudo, menos comissionar."; "O que as OS pedem:" (as da carteira que pedem alguém em especial, as marcadas primeiro: "• Lenine: quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Substituição baterias - chumbo para litio"); responsável: Roberto (fez o 1º dia)."); "Em teste, hoje eu teria mudado: Ivo, ter 10/11 à tarde (poria Roberto)." (as ações de teste de hoje); "Nos últimos 30 dias: 0 vezes alguém sozinho em serviço que pede outra pessoa; 0 trocas de responsável; 3 meios-dias seus em serviço que outro faria." (agenda_habilidade_medidas); "Para corrigir, me diga numa frase (ex.: "o João instala sozinho")." O conteúdo até texto_max (saem as linhas de OS do fim, "• e mais N OS."), a linha "Para corrigir" depois; teto 1.500. Com p_os, só o bloco da OS: o que pede e de onde veio, o fechamento do dono que cobre o último dia, o responsável (_agenda_lider_da_os), quem vai no plano (_agenda_pessoas_texto), quem da equipe faz sozinho o que ela pede e quem precisa de alguém junto, com o porquê (_agenda_atende), os meios-dias marcados sem quem o serviço pede (_agenda_meios_sem_quem_pede, até 3) e o que eu teria mudado nela em teste. {ok, rota habilidades, texto, dados {pessoas, os, em_teste, medidas}}. Só lê. STABLE; definer (o responsável e as avaliações do publicado não têm grant), com a porta dentro (com login, só admin/financeiro: 42501; sem login, só o service_role); authenticated e service_role (agenda_ver, invoker, a chama).';

-- ── 2. agenda_ver (o foco habilidades) ──────────────────────────────────────────────────────────────────────────────

-- agenda_ver (de 20261031100600_agenda_fase7a_rodada.sql)
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
  -- FASE 7: (7a P7) o foco gestor (spec §6.2: o que o gestor da agenda marcou ou marcaria sozinho e por quê, o que perguntou
  -- antes, o que fica de fora e como ele conta — _agenda_ver_gestor), antes da conferência dos 19 da Fase 6, que o foco gestor
  -- não alcança (o foco que não existe continua com a mensagem dos 19). Com login, só administrador e financeiro (42501, antes
  -- de ler a config); desligada a leitura, a frase de sempre.
  if v_foco = 'gestor' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'O gestor da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    return public._agenda_ver_gestor(p_hoje) || jsonb_build_object('rota', 'gestor');
  end if;
  -- FASE 7: fim
  -- FASE 7c: (7c P6, spec §5.6, R5.6) o foco habilidades (quem faz o quê na equipe e o que cada OS pede: _agenda_ver_habilidades),
  -- antes da conferência dos 19 da Fase 6, que o foco não alcança (como o gestor: o foco que não existe continua com a mensagem dos 19).
  -- A porta do aprendizado: sem p_hoje, 22004; com login, só administrador e financeiro (42501, antes de ler a config); desligada a
  -- leitura, a frase de sempre. Com os, só o bloco da OS (a que não existe ou é ambígua: a frase do resolvedor, como os outros focos).
  if v_foco = 'habilidades' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'Quem faz o quê é com o administrador ou o financeiro.' using errcode = '42501';
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
    end if;
    return public._agenda_ver_habilidades(p_hoje, v_agora, (v_ro ->> 'id')::uuid) || jsonb_build_object('rota', 'habilidades');
  end if;
  -- FASE 7c: fim
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

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is
  'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6; Fase 5, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; FASE 5: foco clientes (com ou sem os; a OS concluída também) → as mensagens ao cliente (_agenda_ver_clientes); foco fora da lista (os 18) lança 22023. Devolve {ok, texto, dados, rota}. FASE 6 (P8): foco aprendizado → o que a agenda aprendeu com o que aconteceu (_agenda_ver_aprendizado: o fator por tipo de OS, a presença do dono, os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga, com o n de cada um, e as medidas); com login, só administrador e financeiro (42501). A lista dos focos passa a 19. CORREÇÃO 29/10 (P2): com a agenda automática ligada, o foco livre é UMA resposta, a do plano (agenda_livre_de_verdade.texto_completo: quem ainda pega serviço em cada uma das 3 semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa ninguém até destravar), sem a fila em faixa da Fase 1; na semana, a linha do livre (agenda_livre_de_verdade.texto) vai logo depois do marcado, no lugar da fila em faixa, e a linha do livre lá de baixo sai; simular (agenda_simular) em ligado é o encaixe do motor. Fora de ligado, tudo como antes. FASE 7 (7a P7, spec §6.2): foco gestor → o que o gestor da agenda marcou (ligado) ou marcaria (em teste) e por quê, o que perguntou antes de marcar, o que fica de fora, as compras da semana, os orçamentos que caberiam e como ele conta (_agenda_ver_gestor); com login, só administrador e financeiro (42501); desligada a leitura, a frase de sempre. A lista dos focos passa a 20. FASE 7c (P6, spec §5.6, R5.6): foco habilidades → _agenda_ver_habilidades (quem faz o quê na equipe, o que cada OS pede, o responsável, o que a agenda teria mudado em teste e as medidas; com os, só o bloco da OS), antes da conferência dos 19 (o foco que não existe continua com a mensagem dos 19, como o gestor); sem p_hoje, 22004; com login, só administrador e financeiro (42501); a leitura desligada, a frase de sempre; a OS que não existe ou é ambígua, a frase do resolvedor.';

-- ── 3. A linha da semana do fechamento (o fora habilidade no "Fora:") ───────────────────────────────────────────────

-- _agenda_linha_da_semana (de 20261025100500_agenda_fase2_leituras.sql)
create or replace function public._agenda_linha_da_semana(p_proposta uuid, p_acao_ids jsonb, p_desfazivel boolean, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_max   constant int := 480;   -- estrutural: a linha da semana no fechamento (não é parâmetro de negócio)
  v_tit   text;
  v_fora  jsonb;
  v_itens text[];
  v_foras text[];
  v_back  text;
  v_cab   text;
  v_tail  text;
  v_txt   text;
  k       int;
  n       int;
begin
  select regexp_replace(coalesce(p.textos ->> 'titulo', 'Semana'), '^Semana', 'a semana'), p.fora into v_tit, v_fora
    from public.agenda_propostas p where p.id = p_proposta;
  v_itens := array(
    select case when q.reserva then 'reserva para ' || q.nome else q.nome end || ' (' || public._agenda_dias_texto(q.dias) || ')'
      from (select a.id,
                   public._agenda_rotulo(jsonb_build_object('curto', public._agenda_nome_curto(cl.name), 'numero', so.service_order_number,
                                                            'eh_orc', false, 'n_nome', coalesce(kk.n_nome, 1)), 'np') as nome,
                   array(select distinct (x ->> 'dia')::date from jsonb_array_elements(coalesce(a.depois -> 'alocacoes', '[]'::jsonb)) x
                          order by 1) as dias,
                   exists (select 1 from public.agenda_alocacoes al where al.id = any (a.alocacoes_criadas) and al.tipo = 'reserva') as reserva,
                   so.service_order_number as numero
              from public.agenda_acoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
              left join (select k.service_order_id, count(*) over (partition by public._agenda_normal(k.cliente_curto)) as n_nome
                           from public.os_carteira(p_hoje) k) kk on kk.service_order_id = a.service_order_id
             where a.id in (select x::uuid from jsonb_array_elements_text(coalesce(p_acao_ids, '[]'::jsonb)) x)
               and a.tipo = 'publicar') q
     order by q.reserva, q.dias[1], q.numero, q.id);
  v_foras := array(
    select coalesce(f ->> 'cliente_curto', f ->> 'numero') || ' ('
           || case when f ->> 'motivo' = 'nao_cabe' then 'preciso de você'
                   else regexp_replace(regexp_replace(coalesce(f ->> 'texto', ''), '^[^:]*: ', ''), '( \(| —|\.$).*$', '') end || ')'
      from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) with ordinality t(f, o)
     where f ->> 'motivo' in ('nao_cabe', 'depois', 'sem_encaixe', 'so_com_voce', 'padrao_do_dono')
       -- FASE 7c: (7c P6, spec §5.6) o fora habilidade (não coube com quem o serviço pede; só nasce com modo_habilidade ligado)
       or f ->> 'motivo' = 'habilidade'
       -- FASE 7c: fim
     order by o);
  select r.contagens #>> '{backlog,texto}' into v_back
    from public.agenda_vigia_rodadas r
   where r.p_hoje = $4 and nullif(r.contagens #>> '{backlog,texto}', '') is not null
   order by r.rodou_em desc, r.id desc limit 1;
  v_cab := 'Agenda: publiquei ' || v_tit || ': ';
  v_tail := ' *agenda plano* mostra tudo' || case when p_desfazivel then '; *desfaz semana* volta.' else '.' end;
  n := cardinality(v_itens);
  for k in reverse n .. 1 loop
    v_txt := v_cab || public._agenda_lista(v_itens, k) || '.'
             || coalesce(' Fora: ' || nullif(public._agenda_lista(v_foras, 3), '') || '.', '') || coalesce(' ' || v_back, '') || v_tail;
    exit when char_length(v_txt) <= c_max;
  end loop;
  if char_length(v_txt) > c_max then
    v_txt := v_cab || public._agenda_lista(v_itens, 1) || '.' || coalesce(' ' || v_back, '') || v_tail;
  end if;
  if char_length(v_txt) > c_max then
    v_txt := v_cab || public._agenda_lista(v_itens, 1) || '.' || v_tail;
  end if;
  return v_txt;
end;
$function$;

comment on function public._agenda_linha_da_semana(uuid, jsonb, boolean, date) is
  'Agenda de Produção (Fase 2, P5): a linha da semana publicada no fechamento — as OS com os dias (a reserva diz que é reserva), o que estava pronto e ficou fora (não cabe → "preciso de você"; começa depois), a fila curta da vigia e *agenda plano* / *desfaz semana*. Até 480 caracteres, tirando OS do fim, depois o "Fora", depois a fila. FASE 7c (P6, spec §5.6): o fora habilidade (a OS que o motor da 7c deixou de fora por falta de quem o serviço pede; só com modo_habilidade ligado) também vai no "Fora:", com o porquê do fora. Sem ele, a de antes.';

-- ── 4. O porquê do que ficou de fora (R5.3-6) ───────────────────────────────────────────────────────────────────────

-- _agenda_gestor_motivo_texto (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public._agenda_gestor_motivo_texto(p_motivo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_motivo = 'cliente' then 'esperando o cliente'
    when p_motivo = 'orcamento' then 'orçamento sem virar OS'
    when p_motivo = 'sinal' then 'esperando o sinal'
    when p_motivo in ('padrao_do_dono', 'so_com_voce', 'dono') then 'precisa de você em campo'
    when p_motivo in ('material', 'compra', 'compre_ate', 'sem_previsao', 'conferir_material', 'material_nao_conferido') then 'material'
    when p_motivo = 'escopo' then 'escopo em aberto'
    when p_motivo = 'bem' then 'esperando o barco ou o motorhome'
    when p_motivo in ('espera', 'nao_cabe') then 'esperando a sua decisão'
    when p_motivo in ('situacao', 'estimativa', 'duracao') then 'falta saber os dias'
    -- FASE 7: (7a correção 2) a dupla sem a 2ª pessoa e o *desfaz* do dono (os dois saíam "sem lugar na agenda")
    when p_motivo = 'dupla' then 'falta a 2ª pessoa'
    when p_motivo = 'desfeito' then 'você desfez (me diga os dias para eu marcar de novo)'
    -- FASE 7: fim
    -- FASE 7c: (7c P6, R5.3-6) o fora habilidade (não coube com quem o serviço pede; só nasce com modo_habilidade ligado)
    when p_motivo = 'habilidade' then 'falta quem o serviço pede'
    -- FASE 7c: fim
    when p_motivo in ('sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'depois', 'fixar_recusado') then 'sem lugar na agenda'
    else 'outro motivo'
  end;
$function$;

comment on function public._agenda_gestor_motivo_texto(text) is
  'Agenda de Produção (Fase 7a, P7): o porquê de uma OS de fora numa palavra só, para o dono — cliente "esperando o cliente", orcamento "orçamento sem virar OS", sinal "esperando o sinal", padrao_do_dono/so_com_voce/dono "precisa de você em campo", o material "material", escopo, bem, a decisão crítica, os dias que faltam saber, sem lugar; o resto "outro motivo". IMMUTABLE. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): dupla "falta a 2ª pessoa"; desfeito "você desfez (me diga os dias para eu marcar de novo)". FASE 7c (P6, R5.3-6): habilidade "falta quem o serviço pede" (o fora do motor da 7c; só nasce com modo_habilidade ligado).';

-- _agenda_gestor_motivo_ordem (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public._agenda_gestor_motivo_ordem(p_texto text)
 returns int
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(array_position(array['esperando o cliente', 'orçamento sem virar OS', 'esperando o sinal', 'precisa de você em campo',
                                       'material', 'escopo em aberto', 'esperando o barco ou o motorhome', 'esperando a sua decisão',
                                       -- (7a correção 2) os dois grupos novos, antes de "sem lugar na agenda"
                                       'falta saber os dias', 'falta a 2ª pessoa', 'você desfez (me diga os dias para eu marcar de novo)',
                                       -- FASE 7c: (7c P6, R5.3-6) o grupo da habilidade, antes de "sem lugar na agenda"
                                       'falta quem o serviço pede',
                                       -- FASE 7c: fim
                                       'sem lugar na agenda', 'outro motivo'], p_texto), 99);
$function$;

comment on function public._agenda_gestor_motivo_ordem(text) is
  'Agenda de Produção (Fase 7a, P7): a ordem dos grupos de fora (a de _agenda_gestor_motivo_texto: do que mais segura para o que menos). IMMUTABLE. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): "falta a 2ª pessoa" e "você desfez (…)" depois de "falta saber os dias". FASE 7c (P6, R5.3-6): "falta quem o serviço pede" antes de "sem lugar na agenda".';

-- _agenda_aviso_fora_texto (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public._agenda_aviso_fora_texto(p_fora jsonb, p_sem uuid[])
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  with f as (
    select t.o, t.e ->> 'numero' as numero,
           coalesce(public._agenda_nome_curto(t.e ->> 'cliente_curto'), t.e ->> 'numero', 'uma OS') as curto,
           case
             when t.e ->> 'motivo' in ('material', 'atrasado', 'sem_previsao', 'comprado_sem_previsao', 'compra_sem_prazo',
                                       'compre_ate', 'material_nao_conferido', 'peca_embutida') then 'material'
             when t.e ->> 'motivo' = 'cliente' then 'esperando o cliente'
             when t.e ->> 'motivo' = 'bem' then 'esperando o barco ou o veículo'
             when t.e ->> 'motivo' = 'sinal' then 'esperando o sinal'
             when t.e ->> 'motivo' = 'orcamento' then 'orçamento que não virou OS'
             when t.e ->> 'motivo' = 'escopo' then 'falta fechar o que fazer'
             when t.e ->> 'motivo' = 'duracao' then 'falta saber quantos dias'
             -- (7a correção, achado 6) os motivos do gestor que pergunta antes de marcar
             when t.e ->> 'motivo' = 'situacao' then 'falta saber se já começou'
             when t.e ->> 'motivo' = 'estimativa' then 'falta saber quantos dias'
             when t.e ->> 'motivo' = 'so_com_voce' then 'só com você'
             when t.e ->> 'motivo' = 'padrao_do_dono' then 'falta saber os seus dias em campo'
             -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) o motivo do gestor que espera a 2ª pessoa (só com a regra uma_pessoa)
             when t.e ->> 'motivo' = 'dupla' then 'falta a 2ª pessoa'
             -- FASE 7: fim
             -- FASE 7c: (7c P6, R5.3-6) o fora habilidade (só nasce com modo_habilidade ligado)
             when t.e ->> 'motivo' = 'habilidade' then 'falta quem o serviço pede'
             -- FASE 7c: fim
             when t.e ->> 'motivo' in ('sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'nao_cabe') then 'sem lugar na equipe'
             when t.e ->> 'motivo' in ('depois', 'nao_antes') then 'só mais para a frente'
             when t.e ->> 'motivo' = 'espera' then 'esperando a sua decisão'
             when t.e ->> 'motivo' = 'parada' then 'parou?'
             when t.e ->> 'motivo' = 'congelada' then 'em espera'
             else 'outro motivo' end as rotulo
      from jsonb_array_elements(coalesce(p_fora, '[]'::jsonb)) with ordinality t(e, o)
     where coalesce(t.e ->> 'motivo', '') not in ('fora_da_carteira', 'nao_achei')
       and not coalesce(nullif(t.e ->> 'os', '')::uuid = any (coalesce(p_sem, '{}'::uuid[])), false)
  ),
  n as (
    select f.*, case when count(*) over (partition by public._agenda_normal(f.curto)) > 1 and f.numero is not null
                          and f.curto is distinct from f.numero
                     then f.curto || ' ' || f.numero else f.curto end as nome
      from f
  ),
  g as (
    select n.rotulo, min(n.o) as o, public._agenda_lista(array_agg(n.nome order by n.o), 4) as nomes from n group by n.rotulo
  )
  select case when (select count(*) from n) = 0 then null
              when (select count(*) from n) = 1
                then format('Ficou de fora: %s.', (select g.nomes || ' (' || g.rotulo || ')' from g))
              else format('Ficaram de fora %s: %s.', (select count(*) from n),
                          (select string_agg(g.nomes || ' (' || g.rotulo || ')', '; ' order by g.o) from g)) end;
$function$;

comment on function public._agenda_aviso_fora_texto(jsonb, uuid[]) is
  'Agenda de Produção (correção de 29/10, P4): a linha curta do que ficou de fora no aviso do gestor — "Ficaram de fora 10: Rodrigo OS-00096 (só com você); Vanderlei, Flávio, Nelson e Giancarlo (material); Kalmar OS-00032, Kalmar OS-00033 e Rodrigo OS-00076 (esperando o cliente); …" (o porquê numa palavra pelo motivo da proposta; o número quando o nome se repete; até 4 nomes por porquê). Sem as OS de p_sem nem as fora da carteira. Nada = null. CORREÇÃO DA 7a (revisão da etapa; achado 6): os motivos do gestor — situacao ("falta saber se já começou") e estimativa ("falta saber quantos dias") — não caem mais em "outro motivo". CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): o motivo dupla (a classe 4 da dupla sem a 2ª pessoa, só com a regra uma_pessoa) diz "falta a 2ª pessoa". Com o gestor desligado o motivo não nasce: a saída é a de antes. FASE 7c (P6, R5.3-6): o motivo habilidade (o fora do motor da 7c, só com modo_habilidade ligado) diz "falta quem o serviço pede", não "outro motivo".';

-- ── 5. Portas (as de antes das recriadas continuam: create or replace não mexe no grant; reafirmadas aqui) ──────────────
revoke all on function public._agenda_ver_habilidades(date, timestamptz, uuid) from public, anon;
grant execute on function public._agenda_ver_habilidades(date, timestamptz, uuid) to authenticated, service_role;
revoke all on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) from public, anon;
grant execute on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) to authenticated, service_role;
