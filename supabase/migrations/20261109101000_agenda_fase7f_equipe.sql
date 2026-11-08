-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P5: a equipe — a semana prevista na quinta (junto da ficha), a mudança nos dias
-- que a pessoa já ouviu (uma por pessoa às 19:30, ou na hora quando o dia já teve ficha) e o convite com SIM para o dia novo em cima da hora.
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§3.2, §5.5, §6.3, §6.4, §8.3 agenda_fase7f_equipe.sql e o bloco R8, que vale sobre o corpo: R8.1, R8.5-16 a
-- 19, R8.6, R8.7, R8.8, R8.11, R8.12, R8.13, R8.14); nomes: fase7-registro.md; notas: notas-fase7f.md, seções P1 a P4, P7 e P8.
-- Respostas do dono que valem aqui (respostas/<id> da página Respostas do Diário, conferidas em 08/11): ag7-convite (AG7-23) "Sim, só vira dia dele com o sim";
-- ag7-dupla "Sim, 1 pessoa e dupla só quando precisa"; ag7-ligar "Ligar direto quando estiver pronto" (publicar em teste pelo OK permanente, cada *ligar* pelo OK
-- nomeado); ag7-equipe: Alex e o dono, com o Mateus e o Vinicius sob demanda e SEM cadastro (esta migration não cria ninguém).
-- Depende das Fases 1 a 6, do lote de 30/10, das etapas 7a a 7d e de 20261109100000 a 20261109100300, 20261109100600 e do dado 20261109100900 da 7f (nasce depois
-- dele: R8.2). NÃO depende da 7e.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (11 novas; 8 recriadas, 1 delas com a assinatura nova; 1 comentário de coluna; nenhum dado, nenhuma tabela, nenhuma coluna)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p5/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA
-- (conferida a cada montagem), e a mudança está só nos blocos "-- FASE 7f: … -- FASE 7f: fim". Tirados os blocos, o corpo é o da origem, byte a byte (o montador e o E9 de
-- supabase/tests/agenda_fase7f_equipe.sql conferem). As origens e o md5 do corpo de antes (prosrc, sem CR):
--   _agenda_equipe_registrar           20261101100200_agenda_fase7b_pergunta_semanal.sql:880  94cafa59a9c3c64cfd2a2ddbe00d96f9 (a assinatura muda: drop da de 7 argumentos)
--   _agenda_equipe_previstas_hoje      20261101100200_agenda_fase7b_pergunta_semanal.sql:146  c4f3a720a437d861db9561d2fd534ea7
--   _agenda_rotina_sem_resposta        20261101100200_agenda_fase7b_pergunta_semanal.sql:959  1f9c000b58ce22e7f4b47350b833bcae
--   _agenda_rotina_como_foi            20261031100850_agenda_fase7a_protecoes.sql:645  f1845ec32fc68d68f7a20eb3cf8cbf35
--   _agenda_rotina_ficha               20261031100985_agenda_fase77a_correcao2.sql:794  8cc124d4d1cef4e1a1635c97959f7b15
--   agenda_resposta_da_equipe          20261102100550_agenda_fase7c_tarefas.sql:3608  1fa2260202bec00870db6e8d336ae341
--   _agenda_texto_do_acorde            20261026100300_agenda_fase3_equipe_diarias.sql:3024  d96fee72f6d32d5622ac2a34e214e8b1
--   _agenda_rotina_acordes_da_equipe   20261026100300_agenda_fase3_equipe_diarias.sql:2114  e47d6fd5e3687e0ecbef5236ed1cb341
--
-- POR QUE: a equipe só fica sabendo do dia pela ficha da véspera. A semana dela, o que muda nela e o dia novo em cima da hora chegam pelo dono, quando chegam
-- (NOVO-agenda-76: a mensagem de mudança à equipe nunca foi feita). Hoje nada disto chega a ninguém: o Alex, a única pessoa da rotina, não tem telefone no cadastro,
-- e o Mateus e o Vinicius não têm cadastro. Com os 2 modos desligados (como esta migration deixa) ou em teste, o texto à equipe é o de antes, byte a byte.
--
-- O QUE MUDA (só com modo_equipe_previsto / modo_equipe_convite fora de desligado; os 2 respeitam o freio por _agenda_fala_modo, R8.6: com *gestor, só propor* o
-- ligado vale teste e nada vai à fila; em teste só se registra, com a chave ":sombra", como na Fase 3):
--   1. _agenda_dias_avisados, _agenda_dias_do_plano_da_pessoa, _agenda_equipe_semana_da_pessoa (novas): o que a pessoa já ouviu (as mensagens com dias, na ordem de
--      envio; a última da semana substitui), os dias dela no plano publicado sem reserva (a reserva não avisa a equipe: Fase 2) e a conta da semana — o previsto da
--      quinta, a mudança (sai, entra, fica; o dia novo a menos de equipe_convite_antecedencia_h fica para o convite) e os textos da §6.4.
--   2. _agenda_equipe_registrar (recriada, assinatura nova, R8.5-16): ramo próprio para previsto, mudanca e convite, no molde do dias, com dias, alocacao_ids e a chave
--      pronta; a ficha pode gravar os dias que leva.
--   3. _agenda_rotina_ficha e _agenda_rotina_como_foi (recriadas): a ficha não sai a quem tem o convite do dia sem o SIM (AG7-23); com o previsto ligado de verdade,
--      a ficha (a das 19:30, ou a que vai no "como foi" das 17:00) leva a mudança da semana e, na quinta, o previsto (uma mensagem só).
--   4. _agenda_comunicar_previsto, _agenda_comunicar_mudancas_equipe, _agenda_comunicar_convites, _agenda_comunicar_convites_vencidos (novas): os 4 passos da equipe
--      que a rodada comunicar (P2/P4) já chama pelo nome. Sem ninguém da rotina com telefone, cada um sai na 1ª leitura (R8.8).
--   5. _agenda_equipe_mudanca_na_hora, _agenda_equipe_ja_avisei (novas), _agenda_texto_do_acorde e _agenda_rotina_acordes_da_equipe (recriadas): o dia que já teve
--      ficha e saiu do plano por decisão do dono ou pela falta de outra pessoa vira mensagem na hora; o acorde diz " Já avisei o Roberto." só com ela na fila.
--   6. agenda_resposta_da_equipe (recriada): SIM ao convite confirma e responde "Combinado, até <dia>." (o SIM grava antes: acima do teto de respostas ele vale); NÃO =
--      o caminho do "não vou"; ao previsto e à mudança, ok = ciência e o resto vai ao dono, sem remanejar.
--   7. _agenda_equipe_previstas_hoje (recriada, R8.5-19): o previsto que vai sozinho na quinta conta no teto de 2 (a pergunta dos dias da 7b o vê).
--   8. _agenda_rotina_sem_resposta (recriada): o convite não fecha pela validade da resposta; vale até o prazo (a ficha da véspera).
--   9. _agenda_equipe_convite_prazo (nova): o prazo do SIM = o dia útil anterior ao dia do convite, às equipe_hora_ficha (d10 da §3.3).
--
-- O QUE NÃO MUDA: com os 2 modos desligados, a ficha, o "como foi", a confirmação, o acorde e a resposta da equipe saem como antes, byte a byte (o E8 e o replay
-- da carteira real conferem); a rodada comunicar não é recriada (ela já chama os 4 passos pelo nome e dizia "ainda não existe"); _agenda_chave_telefone,
-- agenda_dia_util, agenda_somar_du, agenda_feriado, _agenda_cliente_dia e _agenda_nome_curto não mudam (pedidos-do-retorno.md, item 13). O convite confirmado grava em
-- agenda_disponibilidade como o ok à ficha (a linha de sempre, origem diarista): nenhuma coluna nova.
--
-- ORDEM DE LIGAR (spec R8.14): depois de 20261109100900 (o dado do núcleo). Aplicar sozinha não muda nada para ninguém (modo_equipe_previsto e modo_equipe_convite
-- seguem desligados). O dado que os põe em teste, o pós-deploy e os md5 são do pacote seguinte (depois do P6).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_equipe.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109101000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261109101000_agenda_fase7f_equipe.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261109101000', 'agenda_fase7f_equipe');"
--
-- DESFAZER: com os 2 modos desligados nada disto roda. Para voltar o código: reaplicar as definições das origens acima (a de _agenda_equipe_registrar depois de
--   drop function public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text, date[], uuid[], text), com o revoke de lá), e
--   drop function if exists public._agenda_comunicar_previsto(date, timestamptz), public._agenda_comunicar_mudancas_equipe(date, timestamptz),
--     public._agenda_comunicar_convites(date, timestamptz), public._agenda_comunicar_convites_vencidos(date, timestamptz),
--     public._agenda_equipe_mudanca_na_hora(uuid, date, timestamptz), public._agenda_equipe_previsto_sozinho(uuid, date),
--     public._agenda_equipe_semana_da_pessoa(uuid, date, timestamptz, text), public._agenda_equipe_ja_avisei(uuid, date, uuid),
--     public._agenda_equipe_convite_prazo(date), public._agenda_dias_do_plano_da_pessoa(uuid, date, date, date), public._agenda_dias_avisados(uuid, date, date, text);
--   (a rodada comunicar volta a dizer "ainda não existe" para os 4 passos). Mensagem que já saiu à equipe não volta.
--
-- IDEMPOTENTE: drop function if exists (a assinatura velha), create or replace function, revoke/grant e comment.

-- ── 0. A assinatura velha do registro sai (R8.5-16) ─────────────────────────────────────────────────
-- create or replace com outra lista de argumentos criaria uma 2ª função, e toda chamada de 5 a 7 argumentos viraria "não é única" (42725). A nova tem os 3 a mais
-- com default null: as chamadas de antes continuam iguais. O revoke vem de novo no fim (a função é outra).
drop function if exists public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text);

-- ── 1. O que a pessoa já ouviu ──────────────────────────────────────────────────────────────────────
-- §5.5, R2 (o nome não é _agenda_dias_ditos: os dias DECLARADOS são da 7b). As mensagens com dias, em ligado só as que foram à fila (enfileirada, respondida,
-- sem_resposta), em teste as registradas (é a simulação do que ela teria ouvido). Na ordem de envio (o convite, pela hora do SIM): o convite com SIM soma o dia; a
-- mudança na hora (alocacao_ids: as que saíram) troca o dia dela; o previsto, a ficha com dias (a das 19:30 ou a do "como foi") e a mudança das 19:30 trocam a
-- janela da semana deles inteira — do dia depois do próximo dia útil ao domingo da semana seguinte, contados do dia em que saíram —, porque cada uma grava em dias o
-- conjunto inteiro que ficou ali.
create or replace function public._agenda_dias_avisados(p_payee uuid, p_de date, p_ate date, p_modo text default 'ligado')
 returns date[]
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_set date[] := '{}';
  m     record;
  v_s   date;
  v_lo  date;
  v_hi  date;
begin
  if p_payee is null or p_de is null or p_ate is null then
    raise exception '_agenda_dias_avisados: sem a pessoa ou os dias' using errcode = '22004';
  end if;
  if p_modo is null or p_modo not in ('ligado', 'sombra') then
    raise exception '_agenda_dias_avisados: o modo "%" não existe.', coalesce(p_modo, '') using errcode = '22023';
  end if;
  for m in
    select x.tipo, x.dia, x.dias, x.alocacao_ids, x.enviar_em,
           coalesce(case when x.tipo = 'convite' then x.resposta_em end, x.enviar_em) as quando, x.criada_em, x.id
      from public.agenda_equipe_mensagens x
     where x.payee_id = p_payee and x.modo = p_modo and x.dias is not null
       and x.enviar_em >= ((p_de - 15)::timestamp at time zone 'America/Sao_Paulo')
       and case when p_modo = 'ligado' then x.estado in ('enfileirada', 'respondida', 'sem_resposta') else x.estado = 'registrada' end
       and (x.tipo in ('previsto', 'mudanca', 'ficha', 'como_foi')
            or (x.tipo = 'convite' and x.estado = 'respondida' and x.leitura ->> 'convite' = 'sim'))
     order by 6, x.criada_em, x.id
  loop
    if m.tipo = 'convite' then
      v_set := v_set || m.dias;
    elsif m.tipo = 'mudanca' and m.alocacao_ids is not null then
      v_set := array(select d from unnest(v_set) d where d <> m.dia) || m.dias;
    else
      v_s := (m.enviar_em at time zone 'America/Sao_Paulo')::date;
      v_lo := public.agenda_somar_du(v_s, 1) + 1;
      v_hi := date_trunc('week', v_s)::date + 13;
      v_set := array(select d from unnest(v_set) d where d not between v_lo and v_hi) || m.dias;
    end if;
  end loop;
  return array(select distinct d from unnest(v_set) d where d between p_de and p_ate order by d);
end;
$function$;

comment on function public._agenda_dias_avisados(uuid, date, date, text) is
  'Agenda de Produção (Fase 7f, P5; §5.5, R2): os dias entre p_de e p_ate que a pessoa OUVIU da agenda — as mensagens com dias (previsto, a ficha que levou a semana, mudança, convite com SIM), em ligado só as que foram à fila, em teste (p_modo sombra) as registradas. Na ordem de envio (o convite pela hora do SIM): o convite soma o dia; a mudança na hora (alocacao_ids) troca o dia dela; o previsto, a ficha e a mudança das 19:30 trocam a janela inteira (do dia depois do próximo dia útil ao domingo da semana seguinte, contados de quando saíram). Os dias declarados pela pessoa são outra coisa (_agenda_dias_declarados, 7b). STABLE, invoker, sem grant.';

-- ── 2. Os dias da pessoa no plano ───────────────────────────────────────────────────────────────────
-- §5.5 (R2: era agenda_equipe_semana, nome que a 7b usa para a rodada semanal). O publicado sem reserva: a reserva não avisa a equipe (Fase 2); a OS com sinal
-- pendente é compromisso firme e entra (AG7-09).
create or replace function public._agenda_dias_do_plano_da_pessoa(p_payee uuid, p_de date, p_ate date, p_hoje date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select jsonb_build_object('dias', to_jsonb(x.dias), 'texto_dias', public._agenda_dias_texto(x.dias),
                            'texto_previsto', case when cardinality(x.dias) > 0
                                                   then format('Semana que vem (previsto, pode mudar): %s.', public._agenda_dias_texto(x.dias)) end)
    from (select array(select distinct a.dia from public.agenda_alocacoes a
                        where a.payee_id = p_payee and a.dia between p_de and p_ate and a.dia >= p_hoje
                          and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        order by a.dia) as dias) x;
$function$;

comment on function public._agenda_dias_do_plano_da_pessoa(uuid, date, date, date) is
  'Agenda de Produção (Fase 7f, P5; §5.5, R2): os dias da pessoa no plano publicado sem reserva (a reserva não avisa a equipe: Fase 2) entre p_de e p_ate, de p_hoje em diante. {dias, texto_dias ("ter 17 e qua 18/11", _agenda_dias_texto), texto_previsto}. STABLE, invoker, só o service_role.';

-- ── 3. O prazo do SIM ───────────────────────────────────────────────────────────────────────────────
-- §3.3 d10: até a ficha da véspera (equipe_hora_ficha do dia útil anterior). Sem parâmetro novo: é a hora em que a ficha decidiria.
create or replace function public._agenda_equipe_convite_prazo(p_dia date)
 returns timestamptz
 language sql
 stable
 set search_path to 'public'
as $function$
  select (public.agenda_somar_du(p_dia, -1) + (public._agenda_cfg()).equipe_hora_ficha) at time zone 'America/Sao_Paulo';
$function$;

comment on function public._agenda_equipe_convite_prazo(date) is
  'Agenda de Produção (Fase 7f, P5; §3.3 d10, AG7-23): o prazo do SIM ao convite do dia — o dia útil anterior, às equipe_hora_ficha (a hora da ficha da véspera), em Brasília. STABLE, invoker, sem grant.';

-- ── 4. "Já avisei" ──────────────────────────────────────────────────────────────────────────────────
-- §5.4, R8.12-9: o acorde só diz que avisou com a mensagem de mudança DESTA ação na fila (ligada; a chave é a da mudança na hora). Sem ela, o texto de antes.
create or replace function public._agenda_equipe_ja_avisei(p_payee uuid, p_dia date, p_acao uuid)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select exists (select 1 from public.agenda_equipe_mensagens x
                  where x.dedupe_key = format('agenda-equipe:mudanca:%s:%s:%s', p_payee, p_dia, p_acao)
                    and x.payee_id = p_payee and x.tipo = 'mudanca' and x.modo = 'ligado'
                    and x.estado in ('enfileirada', 'respondida', 'sem_resposta'));
$function$;

comment on function public._agenda_equipe_ja_avisei(uuid, date, uuid) is
  'Agenda de Produção (Fase 7f, P5; §5.4, NOVO-agenda-76, R8.12-9): a pessoa recebeu a mensagem de mudança desta ação para esse dia — ligada e na fila (enfileirada, respondida ou sem resposta), a chave agenda-equipe:mudanca:<pessoa>:<dia>:<ação>. É o que deixa o acorde dizer "Já avisei o Roberto.". STABLE, invoker; authenticated e service_role (_agenda_texto_do_acorde é invoker e tem os dois).';

-- ── 5. A semana da pessoa ───────────────────────────────────────────────────────────────────────────
-- §5.5 (a), §6.4, R8.5-17. A janela: do dia depois do próximo dia útil (amanhã é da ficha) ao domingo da semana seguinte. Na quinta (dia_do_plano), o previsto =
-- os dias do plano da semana que vem, e a mudança fica com o resto da janela; nos outros dias, a mudança tem a janela inteira. Mudança = a pessoa já ouviu algum dia da
-- janela (§5.5: "com dias ditos") e saiu um dia que ela ouviu ou entrou um que ela não ouviu; o dia novo a menos de equipe_convite_antecedencia_h não entra (é o
-- convite). Os estados: o que ela passa a ter ouvido na janela inteira depois do previsto, da mudança e dos dois (é o que a mensagem grava em dias). Os textos da §6.4.
create or replace function public._agenda_equipe_semana_da_pessoa(p_payee uuid, p_hoje date, p_agora timestamptz, p_modo text default 'ligado')
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_lo     date;
  v_seg    date;
  v_hi     date;
  v_mhi    date;
  v_plano  date[];
  v_ouv    date[];
  v_prev   date[] := '{}';
  v_temp   boolean := false;
  v_sai    date[];
  v_novos  date[];
  v_entra  date[];
  v_fica   date[];
  v_ficam  date[];
  v_mud    boolean;
  v_nome   text;
  v_partes text[];
begin
  if p_payee is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_equipe_semana_da_pessoa: sem a pessoa, o dia ou a hora' using errcode = '22004';
  end if;
  v_lo := public.agenda_somar_du(p_hoje, 1) + 1;
  v_seg := date_trunc('week', p_hoje)::date + 7;
  v_hi := v_seg + 6;
  v_plano := array(select distinct a.dia from public.agenda_alocacoes a
                    where a.payee_id = p_payee and a.dia between v_lo and v_hi and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by a.dia);
  v_ouv := public._agenda_dias_avisados(p_payee, v_lo, v_hi, p_modo);
  if extract(isodow from p_hoje)::int = cf.dia_do_plano then
    v_prev := array(select d from unnest(v_plano) d where d >= v_seg order by d);
    v_temp := cardinality(v_prev) > 0;
  end if;
  v_mhi := case when v_temp then v_seg - 1 else v_hi end;
  v_sai := array(select d from unnest(v_ouv) d where d between v_lo and v_mhi and not (d = any (v_plano)) order by d);
  v_novos := array(select d from unnest(v_plano) d where d between v_lo and v_mhi and not (d = any (v_ouv)) order by d);
  v_entra := array(select d from unnest(v_novos) d
                    where ((d + cf.manha_inicio) at time zone 'America/Sao_Paulo')
                          - (select min(a.criado_em) from public.agenda_alocacoes a
                              where a.payee_id = p_payee and a.dia = d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
                          >= make_interval(hours => cf.equipe_convite_antecedencia_h)
                    order by d);
  v_fica := array(select d from unnest(v_ouv) d where d between v_lo and v_mhi and d = any (v_plano) order by d);
  v_ficam := array(select distinct d from unnest(v_fica || v_entra) d order by d);
  v_mud := exists (select 1 from unnest(v_ouv) d where d between v_lo and v_mhi)
           and (cardinality(v_sai) > 0 or cardinality(v_entra) > 0);
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = p_payee);
  v_partes := array_remove(array[case when cardinality(v_sai) > 0 then 'sai ' || public._agenda_dias_texto(v_sai) end,
                                  case when cardinality(v_entra) > 0 then 'entra ' || public._agenda_dias_texto(v_entra) end], null);
  return jsonb_build_object(
    'de', v_lo, 'ate', v_hi, 'seg', v_seg, 'ouvidos', to_jsonb(v_ouv), 'plano', to_jsonb(v_plano),
    'previsto', to_jsonb(v_prev),
    'mudanca', case when v_mud then jsonb_build_object('sai', to_jsonb(v_sai), 'entra', to_jsonb(v_entra), 'fica', to_jsonb(v_ficam)) end,
    'estado_previsto', case when v_temp
                            then to_jsonb(array(select distinct d from unnest(array(select x from unnest(v_ouv) x where x < v_seg) || v_prev) d order by d)) end,
    'estado_mudanca', case when v_mud
                           then to_jsonb(array(select distinct d from unnest(array(select x from unnest(v_ouv) x where x > v_mhi) || v_ficam) d order by d)) end,
    'estado_ambos', case when v_temp or v_mud
                         then to_jsonb(array(select distinct d
                                               from unnest(array(select x from unnest(v_ouv) x
                                                                  where not (v_mud and x between v_lo and v_mhi) and not (v_temp and x >= v_seg))
                                                           || case when v_temp then v_prev else '{}'::date[] end
                                                           || case when v_mud then v_ficam else '{}'::date[] end) d
                                              order by d)) end,
    'texto_previsto_junto', case when v_temp then format(' Semana que vem (previsto, pode mudar): %s.', public._agenda_dias_texto(v_prev)) end,
    'texto_previsto', case when v_temp
                           then format('%s, semana que vem (previsto, pode mudar): %s. Se algum desses dias não der, me fala.', v_nome,
                                       public._agenda_dias_texto(v_prev)) end,
    'texto_mudanca_junto', case when v_mud then format(' Na semana: %s.', array_to_string(v_partes, '; ')) end,
    'texto_mudanca', case when v_mud
                          then format('%s, mudou a sua semana: %s. %s', v_nome, array_to_string(v_partes, '; '),
                                      case when cardinality(v_ficam) > 0 then 'Fica: ' || public._agenda_dias_texto(v_ficam) || '.'
                                           else 'Por enquanto, nenhum dia marcado.' end) end);
end;
$function$;

comment on function public._agenda_equipe_semana_da_pessoa(uuid, date, timestamptz, text) is
  'Agenda de Produção (Fase 7f, P5; §5.5 (a), §6.4, R8.5-17): a semana da pessoa — o que ela ouviu (_agenda_dias_avisados) contra o plano publicado sem reserva, do dia depois do próximo dia útil ao domingo da semana seguinte. Na quinta, previsto = os dias da semana que vem (e a mudança fica com o resto da janela). Mudança = já ouviu algum dia da janela e saiu um dia ouvido ou entrou um novo (o dia novo a menos de equipe_convite_antecedencia_h é o convite, não entra). {de, ate, seg, ouvidos, plano, previsto (vazio fora da quinta), mudanca {sai, entra, fica} ou nulo, estado_previsto, estado_mudanca, estado_ambos (o que ela passa a ter ouvido; vai em dias), texto_previsto_junto, texto_previsto, texto_mudanca_junto, texto_mudanca}. Sem valor, sem número de OS, sem nome de cliente. STABLE, invoker, sem grant.';

-- ── 6. O previsto que vai sozinho ───────────────────────────────────────────────────────────────────
-- R8.5-19 e R2: a pergunta dos dias (7b) só sai abaixo do teto de 2 contando o que ainda vai sair hoje; o previsto só é mensagem a mais quando não vai junto da ficha
-- (a pessoa não tem plano amanhã, ou a ficha de amanhã foi recusada).
create or replace function public._agenda_equipe_previsto_sozinho(p_payee uuid, p_hoje date)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_am  date;
  v_seg date;
begin
  if p_payee is null or p_hoje is null then
    raise exception '_agenda_equipe_previsto_sozinho: sem a pessoa ou o dia' using errcode = '22004';
  end if;
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano or not public.agenda_dia_util(p_hoje) then
    return false;
  end if;
  v_am := public.agenda_somar_du(p_hoje, 1);
  v_seg := date_trunc('week', p_hoje)::date + 7;
  if not exists (select 1 from public.agenda_alocacoes a
                  where a.payee_id = p_payee and a.dia between v_seg and v_seg + 6 and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') then
    return false;
  end if;
  -- já recebeu o previsto da semana, ou tem a ficha de amanhã (não recusada; também a que foi no "como foi"): ela levou o previsto, e nada sai a mais (R8.5-17)
  if exists (select 1 from public.agenda_equipe_mensagens m
              where m.payee_id = p_payee and m.modo = 'ligado'
                and ((m.tipo = 'previsto' and m.dia = v_seg)
                     or (m.estado <> 'recusada' and ((m.tipo = 'ficha' and m.dia = v_am) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_am))))) then
    return false;
  end if;
  -- a ficha de amanhã ainda vai sair (às 17:00 no "como foi" ou às 19:30) e vai levá-lo
  return not (exists (select 1 from public.agenda_alocacoes a
                       where a.payee_id = p_payee and a.dia = v_am and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
              and not exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = p_payee and m.modo = 'ligado'
                                 and ((m.tipo = 'ficha' and m.dia = v_am) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_am))));
end;
$function$;

comment on function public._agenda_equipe_previsto_sozinho(uuid, date) is
  'Agenda de Produção (Fase 7f, P5; R8.5-19, R2): na quinta (dia_do_plano, dia útil), o previsto da pessoa vai SOZINHO às 19:30 — ela tem dia na semana que vem, ainda não recebeu o previsto, não tem a ficha de amanhã (não recusada; também a do "como foi": essa o levou) e a ficha de amanhã não vai mais sair para levá-lo (sem plano amanhã, ou a ficha foi recusada). É o +1 de _agenda_equipe_previstas_hoje. STABLE, invoker; o service_role (a conta da 7b o tem).';

-- ── 7. A mudança na hora ────────────────────────────────────────────────────────────────────────────
-- §5.5 (b), §6.4, NOVO-agenda-76: o dia que já teve ficha (ou a confirmação, ou o "como foi" que a levou) e saiu do plano da pessoa por esta ação — a decisão do dono ou
-- o replano da falta de outra pessoa (quem chama escolhe a ação) — vira mensagem à pessoa na hora, uma por pessoa, dia e ação. Quem faltou não recebe (ele sabe); o
-- dono não recebe; sem telefone ou fora da rotina, nada (o acorde segue dizendo ao dono "avise ele"). Fora da janela da equipe, espera o próximo tique dentro dela.
create or replace function public._agenda_equipe_mudanca_na_hora(p_acao uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  a        public.agenda_acoes%rowtype;
  r        record;
  v_fala   text;
  v_modo   text;
  v_dono   uuid := public._agenda_dono(null);
  v_chave  text;
  v_nome   text;
  v_cli    text;
  v_f      jsonb;
  v_partes text;
  v_ainda  boolean;
  v_txt    text;
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
begin
  if p_acao is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_equipe_mudanca_na_hora: sem a ação, o dia ou a hora' using errcode = '22004';
  end if;
  v_fala := public._agenda_fala_modo('previsto');
  if v_fala = 'desligado' or cf.modo_equipe = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado');
  end if;
  select * into a from public.agenda_acoes x where x.id = p_acao;
  if not found or not a.executada or a.desfeita_em is not null or cardinality(a.alocacoes_canceladas) = 0 then
    return jsonb_build_object('pulado', true, 'motivo', 'sem_troca');
  end if;
  if public._agenda_equipe_fora_da_janela('mudanca', p_agora, p_agora) is not null then
    return jsonb_build_object('pulado', true, 'motivo', 'janela');
  end if;
  v_modo := case when cf.modo_equipe = 'ligado' and v_fala = 'ligado' then 'ligado' else 'sombra' end;
  for r in
    select b.payee_id, b.dia, array_agg(b.id order by b.id) as alocs, array_agg(distinct b.service_order_id) as os
      from public.agenda_alocacoes b
     where b.id = any (a.alocacoes_canceladas) and b.dia >= p_hoje and b.tipo <> 'reserva' and b.payee_id is distinct from v_dono
     group by b.payee_id, b.dia
     order by b.dia, b.payee_id
  loop
    continue when not exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = r.payee_id and m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                 and ((m.tipo in ('ficha', 'confirmar') and m.dia = r.dia) or (m.tipo = 'como_foi' and m.leva_ficha_de = r.dia)));
    continue when exists (select 1 from public.agenda_disponibilidade d
                           where d.payee_id = r.payee_id and d.substituida_em is null and d.situacao = 'indisponivel' and d.turno is null
                             and d.periodo @> r.dia);
    continue when not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = r.payee_id and c.recebe_rotina and c.parou_em is null)
                  or not public._agenda_equipe_tem_telefone(r.payee_id);
    v_chave := format('agenda-equipe:mudanca:%s:%s:%s', r.payee_id, r.dia, a.id);
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.dedupe_key = v_chave || case when v_modo = 'sombra' then ':sombra' else '' end);
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = r.payee_id);
    v_cli := public._agenda_lista(array(select coalesce(public._agenda_nome_curto(cl.name), 'serviço')
                                          from unnest(r.os) u(os) join public.service_orders so on so.id = u.os
                                          left join public.clients cl on cl.id = so.client_id
                                         order by 1), null);
    v_ainda := exists (select 1 from public.agenda_alocacoes b
                        where b.payee_id = r.payee_id and b.dia = r.dia and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva');
    if not v_ainda then
      v_txt := format('%s, %s não precisa vir: o serviço do %s %s. Desculpa o aviso em cima.', v_nome, public._agenda_dia_da_equipe(r.dia, p_hoje), v_cli,
                      case when exists (select 1 from public.agenda_alocacoes b
                                         where b.service_order_id = any (r.os) and b.dia >= p_hoje and b.dia <> r.dia
                                           and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva')
                           then 'mudou de dia' else 'mudou' end);
    else
      v_f := public.agenda_equipe_ficha(r.payee_id, r.dia, p_hoje);
      v_partes := rtrim(regexp_replace(coalesce(v_f ->> 'texto_curto', ''), '^[^:]*: ', ''), '.');
      v_txt := format('%s, %s mudou', v_nome, public._agenda_dia_da_equipe(r.dia, p_hoje))
               || case when v_partes <> '' then ': ' || v_partes else '' end
               || case when exists (select 1 from public.agenda_alocacoes b
                                     where b.payee_id = r.payee_id and b.dia = r.dia and b.service_order_id = any (r.os)
                                       and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva')
                       then '' else format(', em vez do %s', v_cli) end
               || '. Responde OK.';
    end if;
    v_r := public._agenda_equipe_registrar(r.payee_id, r.dia, 'mudanca', v_txt, p_agora, null, null,
                                           case when v_ainda then array[r.dia] else '{}'::date[] end, r.alocs, v_chave);
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'), coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('acao', p_acao, 'por_estado', v_cont);
end;
$function$;

comment on function public._agenda_equipe_mudanca_na_hora(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7f, P5; §5.5 (b), §6.4, NOVO-agenda-76): para cada pessoa que a ação tirou de um dia (de hoje em diante) em que ela já tinha a ficha, a confirmação ou o "como foi" que a levou, a mensagem de mudança na hora (tipo mudanca, chave agenda-equipe:mudanca:<pessoa>:<dia>:<ação>, dias = o dia se ainda tem plano nele, alocacao_ids = as que saíram): "Roberto, amanhã (qua 11/11) não precisa vir: o serviço do Nelson mudou de dia. Desculpa o aviso em cima." ou "… mudou: 8h no motorhome do Lenine, em vez do Nelson. Responde OK.". Não manda a quem faltou, ao dono, a quem não tem telefone ou não está na rotina; fora da janela, {pulado: janela}. O modo é o do previsto (_agenda_fala_modo). {acao, por_estado}. Volatile, invoker, sem grant.';

-- ── 8. As recriadas ─────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_equipe_registrar(p_payee uuid, p_dia date, p_tipo text, p_texto text,
                                                           p_enviar_em timestamptz, p_leva_ficha_de date default null,
                                                           p_responde text default null, p_dias date[] default null,
                                                           p_alocacoes uuid[] default null, p_chave text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_modo text;
  v_id   uuid;
  v_r    jsonb;
  v_enviar timestamptz;
  -- FASE 7f: (7f P5) o previsto, a mudança e o convite
  v_7f_fala text;
  -- FASE 7f: fim
begin
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  -- FASE 7b: (7b P3, §5.2) a pergunta dos dias da semana (tipo dias; p_dia = a segunda da semana perguntada): com a pergunta dos dias
  -- desligada (modo_dias), nada; ligada só com a equipe e a pergunta dos dias ligadas (senão em teste, a chave com ":sombra"); a chave
  -- agenda-equipe:dias:<pessoa>:<segunda>; a janela, o teto do dia e a trava da fila valem como para a ficha (_agenda_equipe_enfileirar)
  if p_tipo = 'dias' then
    if cf.modo_dias = 'desligado' then
      return jsonb_build_object('criada', false, 'modo', 'desligado');
    end if;
    if nullif(btrim(coalesce(p_texto, '')), '') is null then
      raise exception 'A mensagem à equipe veio sem texto.' using errcode = '22023';
    end if;
    if p_dia is null or extract(isodow from p_dia)::int <> 1 then
      raise exception 'A pergunta dos dias é de uma semana: o dia é a segunda (veio %).', p_dia using errcode = '22023';
    end if;
    v_modo := case when cf.modo_equipe = 'ligado' and cf.modo_dias = 'ligado' then 'ligado' else 'sombra' end;
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, dedupe_key,
                                                responde_wa_id, criada_em)
    values (p_payee, p_dia, 'dias', null, v_modo, left(p_texto, 600), p_enviar_em,
            format('agenda-equipe:dias:%s:%s', p_payee, p_dia) || case when v_modo = 'sombra' then ':sombra' else '' end,
            null, p_enviar_em)
    on conflict do nothing
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe');
    end if;
    v_r := public._agenda_equipe_enfileirar(v_id);
    return v_r || jsonb_build_object('criada', true, 'modo', v_modo, 'id', v_id);
  end if;
  -- FASE 7b: fim
  -- FASE 7f: (7f P5, §5.5, R8.5-16, R8.6) o previsto, a mudança e o convite: ramo próprio, no molde do dias. Respeitam o freio: o modo é o de
  -- _agenda_fala_modo ('previsto' para o previsto e a mudança, 'convite' para o convite); desligado = nada; ligado só com a equipe ligada; o resto em
  -- teste (a chave com ":sombra", nada vai à fila). A chave pode vir pronta (p_chave: a mudança tem mais de uma por dia, a das 19:30 e a da hora);
  -- senão agenda-equipe:<tipo>:<pessoa>:<dia>. Grava dias (o que a pessoa passa a ter ouvido: _agenda_dias_avisados os lê) e alocacao_ids (o convite:
  -- as alocações que o SIM confirma; a mudança na hora: as que saíram). A janela, o teto do dia e a trava da fila valem como para a ficha.
  if p_tipo in ('previsto', 'mudanca', 'convite') then
    v_7f_fala := public._agenda_fala_modo(case when p_tipo = 'convite' then 'convite' else 'previsto' end);
    if v_7f_fala = 'desligado' then
      return jsonb_build_object('criada', false, 'modo', 'desligado');
    end if;
    if nullif(btrim(coalesce(p_texto, '')), '') is null then
      raise exception 'A mensagem à equipe veio sem texto.' using errcode = '22023';
    end if;
    if p_dias is null or (p_tipo <> 'mudanca' and cardinality(p_dias) = 0) then
      raise exception 'A mensagem à equipe (%) vem com os dias que ela diz.', p_tipo using errcode = '22023';
    end if;
    if p_tipo = 'convite' and (coalesce(cardinality(p_alocacoes), 0) = 0 or p_dias <> array[p_dia]) then
      raise exception 'O convite é de um dia só, com as alocações que o SIM confirma.' using errcode = '22023';
    end if;
    v_modo := case when cf.modo_equipe = 'ligado' and v_7f_fala = 'ligado' then 'ligado' else 'sombra' end;
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, dedupe_key, responde_wa_id, criada_em,
                                                dias, alocacao_ids)
    values (p_payee, p_dia, p_tipo, null, v_modo, left(p_texto, 600), p_enviar_em,
            coalesce(nullif(p_chave, ''), format('agenda-equipe:%s:%s:%s', p_tipo, p_payee, p_dia))
            || case when v_modo = 'sombra' then ':sombra' else '' end,
            null, p_enviar_em, p_dias, p_alocacoes)
    on conflict do nothing
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe');
    end if;
    v_r := public._agenda_equipe_enfileirar(v_id);
    return v_r || jsonb_build_object('criada', true, 'modo', v_modo, 'id', v_id);
  end if;
  -- FASE 7f: fim
  if p_tipo is null or p_tipo not in ('ficha', 'confirmar', 'como_foi', 'resposta') then
    raise exception 'Tipo de mensagem à equipe desconhecido: "%".', coalesce(p_tipo, '') using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_texto, '')), '') is null then
    raise exception 'A mensagem à equipe veio sem texto.' using errcode = '22023';
  end if;
  v_modo := case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end;
  -- (C1, NOVO-agenda-28) a resposta a uma mensagem dele: na hora entre equipe_resposta_direta_inicio e _fim (fora do
  -- domingo); senão no início da janela da equipe (a mensagem registrada nunca muda: a hora entra certa)
  v_enviar := case when p_tipo = 'resposta' then public._agenda_equipe_quando_responder(p_enviar_em) else p_enviar_em end;
  -- FASE 7f: (7f P5, §5.5 (2) e (3), R8.5-17) a ficha (a das 19:30, ou a que vai no "como foi") que leva o previsto da quinta ou a mudança da semana grava, ao
  -- nascer, os dias que a pessoa passa a ter ouvido (_agenda_dias_avisados os lê; a mensagem registrada não muda depois: o gatilho só deixa o estado, a fila e a
  -- resposta). Sem p_dias, o insert de antes (o if abre aqui e fecha no bloco de baixo, para o corpo sem os blocos seguir igual à origem).
  if p_tipo in ('ficha', 'como_foi') and p_dias is not null then
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, dedupe_key, responde_wa_id, criada_em,
                                                dias)
    values (p_payee, p_dia, p_tipo, p_leva_ficha_de, v_modo, left(p_texto, 600), v_enviar,
            format('agenda-equipe:%s:%s:%s', p_tipo, p_payee, p_dia) || case when v_modo = 'sombra' then ':sombra' else '' end,
            null, p_enviar_em, p_dias)
    on conflict do nothing
    returning id into v_id;
  else
  -- FASE 7f: fim
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, dedupe_key,
                                              responde_wa_id, criada_em)
  values (p_payee, p_dia, p_tipo, p_leva_ficha_de, v_modo, left(p_texto, 600), v_enviar,
          case when p_tipo = 'resposta'
               then format('agenda-equipe:resposta:%s:%s', p_payee, coalesce(p_responde, md5(p_texto || p_enviar_em::text)))
               else format('agenda-equipe:%s:%s:%s', p_tipo, p_payee, p_dia) end
          || case when v_modo = 'sombra' then ':sombra' else '' end,
          case when p_tipo = 'resposta' then p_responde end, p_enviar_em)
  on conflict do nothing
  returning id into v_id;
  -- FASE 7f: (7f P5) o fim do if de cima
  end if;
  -- FASE 7f: fim
  if v_id is null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe');
  end if;
  v_r := public._agenda_equipe_enfileirar(v_id);
  return v_r || jsonb_build_object('criada', true, 'modo', v_modo, 'id', v_id);
end;
$function$;

comment on function public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text, date[], uuid[], text) is
  'Agenda de Produção (Fase 3, P4; revisão C1): grava a mensagem à equipe no modo de agora (desligado = nada; sombra = estado registrada e a chave agenda-equipe:<tipo>:<pessoa>:<dia> com ":sombra"; ligado = a chave sem sufixo, a mesma da fila) e chama _agenda_equipe_enfileirar. Uma por pessoa, dia, tipo e modo (as respostas pela mensagem dele). A resposta (NOVO-agenda-28) entra com a hora de _agenda_equipe_quando_responder: na hora, entre equipe_resposta_direta_inicio e _fim; senão no início da janela. Sem grant. FASE 7b (P3, §5.2): o tipo dias — a pergunta dos dias da semana (p_dia = a segunda da semana perguntada; outra data = 22023): com modo_dias desligado, {criada: false} e nada; ligada só com modo_equipe e modo_dias ligados (senão sombra, a chave com ":sombra"); a chave agenda-equipe:dias:<pessoa>:<segunda>; a janela, o teto do dia (conta como as que o sistema começa) e a trava da fila valem como para a ficha. Os outros tipos, o de antes, byte a byte. FASE 7f (P5): a assinatura ganhou p_dias date[], p_alocacoes uuid[] e p_chave text (default null; a de 7 argumentos saiu, R8.5-16). Os tipos previsto, mudanca e convite têm ramo próprio, no molde do dias: o modo é o de _agenda_fala_modo (previsto para o previsto e a mudança, convite para o convite; com o freio é teste); desligado = nada; ligado só com a equipe ligada; em teste a chave com ":sombra" e nada vai à fila. A chave pode vir pronta (a mudança tem mais de uma por dia). Grava dias e alocacao_ids. A ficha com p_dias grava os dias que a pessoa passa a ter ouvido (o previsto da quinta ou a mudança junto). A janela, o teto e a trava da fila são os de sempre.';

create or replace function public._agenda_equipe_previstas_hoje(p_payee uuid, p_hoje date, p_agora timestamptz)
 returns integer
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_modo text;
  v_am   date;
  v_n    int := 0;
begin
  if p_payee is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_equipe_previstas_hoje: sem a pessoa, o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_modo_da_equipe();
  v_am := public.agenda_somar_du(p_hoje, 1);
  if exists (select 1 from public.agenda_alocacoes a
              where a.payee_id = p_payee and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
     and not exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = p_payee and m.modo = v_modo and m.tipo = 'como_foi' and m.dia = p_hoje) then
    v_n := v_n + 1;
  end if;
  if public.agenda_dia_util(p_hoje)
     and exists (select 1 from public.agenda_alocacoes a
                  where a.payee_id = p_payee and a.dia = v_am and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
     and not exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = p_payee and m.modo = v_modo
                        and ((m.tipo = 'ficha' and m.dia = v_am) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_am)))
     and not exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = p_payee and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
                        and m.estado <> 'recusada') then
    v_n := v_n + 1;
  end if;
  -- FASE 7f: (7f P5, R8.5-19, R2) na quinta, o previsto que vai SOZINHO às 19:30 (a pessoa não tem a ficha de amanhã, ou ela já saiu no "como foi")
  -- também é mensagem do dia: a pergunta dos dias (7b) o conta, e o previsto nunca é a 3ª. O que vai junto da ficha já está contado nela. Só com o
  -- previsto ligado de verdade (_agenda_fala_modo: com o freio é teste) e a equipe ligada; fora disso, a conta de antes.
  if v_modo = 'ligado' and public._agenda_fala_modo('previsto') = 'ligado' and public._agenda_equipe_previsto_sozinho(p_payee, p_hoje) then
    v_n := v_n + 1;
  end if;
  -- FASE 7f: fim
  return v_n;
end;
$function$;

comment on function public._agenda_equipe_previstas_hoje(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7b, P3; §3.1-7, §5.2): quantas mensagens a rotina da equipe ainda vai começar hoje para a pessoa, pelos critérios de _agenda_rotina_como_foi e _agenda_rotina_ficha — +1 pelo "como foi" (meio-dia não reserva vigente hoje e o "como foi" de hoje ainda não registrado, no modo da equipe); +1 pela ficha (dia útil, meio-dia vigente no próximo dia útil, sem ficha dele registrada, sem o "como foi" que a leve e sem a confirmação de hoje registrada: no dia em que a confirmação sai, a ficha vai dentro do "como foi" e não conta de novo). A pergunta da semana só sai quando as que já entraram + estas cabem no teto do dia (equipe_proativas_dia_max). STABLE, invoker. FASE 7f (P5): na quinta, com o previsto ligado de verdade e a equipe ligada, o previsto que vai sozinho às 19:30 (_agenda_equipe_previsto_sozinho) conta +1; o que vai junto da ficha já está contado nela (R8.5-19).';

create or replace function public._agenda_rotina_sem_resposta(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_n int;
begin
  update public.agenda_equipe_mensagens m set estado = 'sem_resposta'
   where m.tipo <> 'resposta' and m.estado = 'enfileirada' and m.resposta_em is null
     -- FASE 7b: (7b P3; A2 = NOVO-agenda-53) a pergunta dos dias da semana não fecha aqui: quem a fecha é o prazo da semana dela
     -- (agenda_equipe_semana, o passo fechar)
     and m.tipo <> 'dias'
     -- FASE 7b: fim
     -- FASE 7f: (7f P5, §5.5, AG7-23) o convite não fecha aqui: vale até o prazo dele (a ficha da véspera), e quem o fecha é o passo
     -- convites_vencidos da rodada comunicar (o caminho do "não vou")
     and m.tipo <> 'convite'
     -- FASE 7f: fim
     and m.enviar_em + cf.equipe_resposta_validade < p_agora;
  get diagnostics v_n = row_count;
  return jsonb_build_object('sem_resposta', v_n);
end;
$function$;

comment on function public._agenda_rotina_sem_resposta(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): o passo sem_resposta da rotina da equipe — a mensagem que o sistema começou (não a resposta), enfileirada, sem resposta e com equipe_resposta_validade vencida vira sem_resposta. {sem_resposta}. FASE 7b (P3; A2 = NOVO-agenda-53): menos a pergunta dos dias da semana (tipo dias), que vale até o prazo da semana dela — quem a fecha é o passo fechar de agenda_equipe_semana. Sem grant. FASE 7f (P5): o convite não fecha aqui: vale até o prazo (a ficha da véspera) e fecha no passo convites_vencidos da rodada comunicar.';

create or replace function public._agenda_rotina_como_foi(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date := public.agenda_somar_du(p_hoje, 1);
  v_p     uuid;
  v_f     jsonb;
  v_fd    jsonb;
  v_leva  boolean;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
  -- FASE 7f: (7f P5) o previsto e a mudança junto da ficha que vai no "como foi"
  v_7f_s    jsonb;
  v_7f_prev boolean;
  v_7f_mud  boolean;
  v_7f_txt  text;
  v_7f_dias date[];
  -- FASE 7f: fim
begin
  if v_local::time < cf.equipe_hora_como_foi then
    return jsonb_build_object('como_foi', 0);
  end if;
  for v_p in select x from public._agenda_contatos_com_plano(p_hoje) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'como_foi' and m.dia = p_hoje);
    v_f := public.agenda_equipe_ficha(v_p, p_hoje, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    v_leva := exists (select 1 from public.agenda_equipe_mensagens m
                       where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
                         and m.estado <> 'recusada')
              and not exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'ficha' and m.dia = v_d);
    v_fd := case when v_leva then public.agenda_equipe_ficha(v_p, v_d, p_hoje) end;
    v_leva := v_leva and coalesce((v_fd ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) a ficha de amanhã que iria junto do "como foi hoje?" obedece a mesma
    -- proteção da ficha das 19:30 (_agenda_ficha_liberada) e mais: o "como foi" sai antes da hora da ficha, quando o dono ainda
    -- pode segurá-la; então a ficha de um dia pela estimativa na janela de veto só vai junto com o "mande" dele (opção 1). Senão o
    -- "como foi" vai sem ela, e a rotina da hora da ficha decide.
    if v_leva and v_modo = 'ligado'
       and (not public._agenda_ficha_liberada(v_p, v_d, p_agora)
            or exists (select 1 from public.agenda_perguntas q
                        where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
                          and q.opcao_escolhida is distinct from 1)) then
      v_leva := false;
    end if;
    -- FASE 7: fim
    -- FASE 7f: (7f P5, §5.5 (2) e (3), R8.5-17) a ficha de amanhã que vai no "como foi" (às 17:00, quando a confirmação de hoje saiu) leva o mesmo que a das
    -- 19:30 levaria: a mudança da semana e, na quinta, o previsto (uma mensagem só; a ficha das 19:30 não sai para quem já a recebeu aqui). Só com o previsto
    -- ligado de verdade e a equipe ligada; sem nada a dizer ou passando de 600 letras, o de antes, byte a byte.
    v_7f_txt := null;
    v_7f_dias := null;
    if v_leva and v_modo = 'ligado' and public._agenda_fala_modo('previsto') = 'ligado' then
      v_7f_s := public._agenda_equipe_semana_da_pessoa(v_p, p_hoje, p_agora);
      v_7f_prev := jsonb_array_length(coalesce(v_7f_s -> 'previsto', '[]'::jsonb)) > 0
                   and not exists (select 1 from public.agenda_equipe_mensagens m
                                    where m.payee_id = v_p and m.tipo = 'previsto' and m.dia = (v_7f_s ->> 'seg')::date and m.modo = 'ligado');
      v_7f_mud := jsonb_typeof(v_7f_s -> 'mudanca') = 'object'
                  and not exists (select 1 from public.agenda_equipe_mensagens m
                                   where m.dedupe_key = format('agenda-equipe:mudanca:%s:%s:19h', v_p, p_hoje));
      if v_7f_prev or v_7f_mud then
        v_7f_txt := case when v_7f_mud then v_7f_s ->> 'texto_mudanca_junto' else '' end
                    || case when v_7f_prev then v_7f_s ->> 'texto_previsto_junto' else '' end;
        v_7f_dias := array(select x::date from jsonb_array_elements_text(v_7f_s -> case when v_7f_prev and v_7f_mud then 'estado_ambos'
                                                                                   when v_7f_prev then 'estado_previsto'
                                                                                   else 'estado_mudanca' end) x order by 1);
        if char_length(coalesce(v_f ->> 'texto_como_foi', '')) + 1 + char_length(coalesce(v_fd ->> 'texto_curto', '')) + char_length(v_7f_txt) > 600 then
          v_7f_txt := null;
          v_7f_dias := null;
        end if;
      end if;
    end if;
    if v_7f_txt is not null then
      v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'como_foi', (v_f ->> 'texto_como_foi') || ' ' || (v_fd ->> 'texto_curto') || v_7f_txt,
                                             p_agora, v_d, null, v_7f_dias);
    else
    -- FASE 7f: fim
    v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'como_foi',
             (v_f ->> 'texto_como_foi') || case when v_leva then ' ' || (v_fd ->> 'texto_curto') else '' end,
             p_agora, case when v_leva then v_d end);
    -- FASE 7f: (7f P5) o fim do if de cima
    end if;
    -- FASE 7f: fim
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('por_estado', v_cont);
end;
$function$;

comment on function public._agenda_rotina_como_foi(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): o "como foi hoje?" (equipe_hora_como_foi) a quem teve plano hoje; no dia em que a confirmação da manhã saiu, ele leva a ficha de amanhã (e a hora da ficha não manda nada). FASE 7 (7a P11; AG7-15): a ficha de amanhã de um dia pela estimativa na janela de veto só vai junto com o "mande" do dono (a opção 1 da pergunta ficha_estimativa) — o "como foi" sai antes do fechamento e da hora da ficha; sem isso (ou com _agenda_ficha_liberada falso), ele vai sem a ficha e a rotina da hora da ficha decide. Fora disso, a de antes, byte a byte. FASE 7f (P5): a ficha de amanhã que vai junto do "como foi" leva, com o previsto ligado de verdade e a equipe ligada, a mudança da semana e, na quinta, o previsto (uma mensagem só), e grava em dias o que a pessoa passa a ter ouvido. Fora disso, o de antes, byte a byte.';

create or replace function public._agenda_rotina_ficha(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date;
  v_p     uuid;
  v_f     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
  -- FASE 7: (7a P11) a ficha de um dia pela estimativa, na janela de veto
  v_f11_q   public.agenda_perguntas%rowtype;
  v_f11_m   uuid;
  v_f11_a   uuid;
  v_f11_os  uuid[];
  v_f11_cli text;
  v_f11_nom text;
  v_f72_fecha boolean := false;  -- (7a correção 2) a pergunta da ficha fecha depois do registro, com o que houve
  -- FASE 7: fim
  -- FASE 7f: (7f P5) o previsto e a mudança junto da ficha
  v_7f_s    jsonb;
  v_7f_prev boolean;
  v_7f_mud  boolean;
  v_7f_txt  text;
  v_7f_dias date[];
  -- FASE 7f: fim
begin
  if v_local::time < cf.equipe_hora_ficha or not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('fichas', 0);
  end if;
  v_d := public.agenda_somar_du(p_hoje, 1);
  for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo
                             and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)));
    -- FASE 7f: (7f P5, §5.5 (1), AG7-23 "Sim, só vira dia dele com o sim") quem tem o convite de amanhã enviado e ainda sem o SIM não recebe a ficha:
    -- o dia ainda não é dele. Só com o convite ligado de verdade (com o freio, o de antes: a ficha sai).
    continue when public._agenda_fala_modo('convite') = 'ligado'
                  and exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.tipo = 'convite' and m.dia = v_d and m.modo = 'ligado'
                                 and m.estado in ('enfileirada', 'sem_resposta', 'respondida')
                                 and m.leitura ->> 'convite' is distinct from 'sim');
    -- FASE 7f: fim
    v_f := public.agenda_equipe_ficha(v_p, v_d, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) nas primeiras ficha_veto_dias a partir do ligar do gestor, a ficha de
    -- um dia marcado pela estimativa (a alocação da pessoa no dia com duracao_fonte orcamento) só sai com a pergunta
    -- ficha_estimativa daquele dia mostrada ao dono e não segurada (_agenda_ficha_liberada). Senão ela fica registrada como
    -- recusada (veto): nada vai à fila nem conta no teto da pessoa. Se o dono não soube (não viu a pergunta a tempo, ou ela nem
    -- nasceu), o que mudou conta para ele (a ação equipe da vigia: o fechamento e o *o que mudou* do dia seguinte). A pergunta do
    -- dia fecha aqui: a hora da ficha chegou. Só com a mensagem de verdade (em teste nada sai de todo jeito).
    if v_modo = 'ligado' then
      v_f11_q := null;
      select q.* into v_f11_q from public.agenda_perguntas q
       where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
       order by q.criada_em desc, q.id desc limit 1;
      if not public._agenda_ficha_liberada(v_p, v_d, p_agora) then
        insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key,
                                                    criada_em)
        values (v_p, v_d, 'ficha', 'ligado', left(v_f ->> 'texto_ficha', 600), p_agora, 'recusada', 'veto',
                format('agenda-equipe:ficha:%s:%s', v_p, v_d), p_agora)
        returning id into v_f11_m;
        if v_f11_q.id is null or v_f11_q.opcao_escolhida is distinct from 2 then
          v_f11_os := array(select a.service_order_id from public.agenda_alocacoes a
                             where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.duracao_fonte = 'orcamento'
                             group by a.service_order_id order by min(lower(a.periodo)), a.service_order_id);
          v_f11_cli := public._agenda_lista(array(
                         select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                           from unnest(v_f11_os) with ordinality u(os, o)
                           join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                          order by u.o), null);
          v_f11_nom := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_p);
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
          values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_f11_os[1], v_f11_os, v_p,
                  jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                     -- (7a correção 2) quem não tem telefone não ganha a pergunta: o porquê é esse
                                     'por', case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p) then 'sem_telefone'
                                                 when v_f11_q.id is null then 'sem_pergunta' else 'nao_vista' end),
                  left(format('Não mandei a ficha de %s a %s (%s): o dia é pela minha estimativa e %s. Fale com %s.',
                              public._dia_curto(v_d), v_f11_nom, v_f11_cli,
                              -- (7a correção 2) sem telefone no cadastro: o gestor não pergunta a ficha (ela não sairia), e o
                              -- dono fica sabendo que tem de avisar de boca
                              case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p)
                                     then format('%s não tem telefone no cadastro', v_f11_nom)
                                   when v_f11_q.id is null then 'não consegui te perguntar antes'
                                   else 'você não viu a pergunta antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI') end,
                              v_f11_nom), 400))
          returning id into v_f11_a;
          update public.agenda_equipe_mensagens set acao_id = v_f11_a where id = v_f11_m;
        end if;
        update public.agenda_perguntas
           set estado = 'resolvida', resolvida_motivo = 'na hora da ficha você não tinha visto a pergunta: a ficha não saiu'
         where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        v_cont := v_cont || jsonb_build_object('recusada', coalesce((v_cont ->> 'recusada')::int, 0) + 1);
        continue;
      end if;
      -- (7a correção 2) a pergunta fecha logo abaixo, depois do registro: antes ela fechava aqui "ela foi como eu disse" e o
      -- registro recusava em seguida (sem telefone, teto, janela) — o dono lia que a ficha tinha ido
      v_f72_fecha := true;
    end if;
    -- FASE 7: fim
    -- FASE 7f: (7f P5, §5.5 (2) e (3), §6.4, R8.5-17) com o previsto ligado de verdade (o freio = teste) e a equipe ligada, a ficha leva o que a
    -- semana da pessoa tem a dizer, numa mensagem só: a mudança dos dias que ela já ouviu ("Na semana: sai …; entra …") e, na quinta, o previsto da
    -- semana que vem. A ficha grava em dias o que a pessoa passa a ter ouvido. Sem nada a dizer, ou passando de 600 letras, a ficha de antes (e os
    -- passos previsto e mudancas_equipe da rodada comunicar mandam o que ficou de fora, sozinho). Fora disso, byte a byte a de antes.
    v_7f_txt := null;
    v_7f_dias := null;
    if v_modo = 'ligado' and public._agenda_fala_modo('previsto') = 'ligado' then
      v_7f_s := public._agenda_equipe_semana_da_pessoa(v_p, p_hoje, p_agora);
      v_7f_prev := jsonb_array_length(coalesce(v_7f_s -> 'previsto', '[]'::jsonb)) > 0
                   and not exists (select 1 from public.agenda_equipe_mensagens m
                                    where m.payee_id = v_p and m.tipo = 'previsto' and m.dia = (v_7f_s ->> 'seg')::date and m.modo = 'ligado');
      v_7f_mud := jsonb_typeof(v_7f_s -> 'mudanca') = 'object'
                  and not exists (select 1 from public.agenda_equipe_mensagens m
                                   where m.dedupe_key = format('agenda-equipe:mudanca:%s:%s:19h', v_p, p_hoje));
      if v_7f_prev or v_7f_mud then
        v_7f_txt := case when v_7f_mud then v_7f_s ->> 'texto_mudanca_junto' else '' end
                    || case when v_7f_prev then v_7f_s ->> 'texto_previsto_junto' else '' end;
        v_7f_dias := array(select x::date from jsonb_array_elements_text(v_7f_s -> case when v_7f_prev and v_7f_mud then 'estado_ambos'
                                                                                   when v_7f_prev then 'estado_previsto'
                                                                                   else 'estado_mudanca' end) x order by 1);
        if char_length(coalesce(v_f ->> 'texto_ficha', '')) + char_length(v_7f_txt) > 600 then
          v_7f_txt := null;
          v_7f_dias := null;
        end if;
      end if;
    end if;
    if v_7f_txt is not null then
      v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', (v_f ->> 'texto_ficha') || v_7f_txt, p_agora, null, null, v_7f_dias);
    else
    -- FASE 7f: fim
    v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', v_f ->> 'texto_ficha', p_agora);
    -- FASE 7f: (7f P5) o fim do if de cima
    end if;
    -- FASE 7f: fim
    -- FASE 7: (7a correção 2, a ficha prometida a quem não tem telefone) a pergunta da ficha liberada fecha com o que aconteceu
    -- no registro: enfileirada = "ela foi como eu disse"; recusada (o teto, a janela, o telefone que sumiu) = o porquê
    if v_f72_fecha then
      update public.agenda_perguntas
         set estado = 'resolvida',
             resolvida_motivo = case when v_r ->> 'estado' = 'recusada'
                                     then format('na hora da ficha você não a segurou, mas ela não saiu (%s)',
                                                 case v_r ->> 'motivo' when 'sem_telefone' then 'sem telefone no cadastro'
                                                                       when 'teto' then 'o limite de mensagens do dia'
                                                                       when 'janela' then 'fora do horário de mandar'
                                                                       when 'parou' then 'a pessoa não recebe mais a rotina'
                                                                       else coalesce(v_r ->> 'motivo', 'recusada') end)
                                     else 'na hora da ficha você não a segurou: ela foi como eu disse' end
       where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
      v_f72_fecha := false;
    end if;
    -- FASE 7: fim
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('dia', v_d, 'por_estado', v_cont);
end;
$function$;

comment on function public._agenda_rotina_ficha(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a ficha da véspera (equipe_hora_ficha num dia útil) para o próximo dia útil — não vai a quem já recebeu a ficha desse dia nem a quem recebeu o "como foi hoje?" levando a ficha; o texto de agenda_equipe_ficha, pelo _agenda_equipe_registrar. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15): com a mensagem de verdade, a ficha que _agenda_ficha_liberada não solta (na janela de veto do ligar, um dia da pessoa marcado pela estimativa sem a pergunta ficha_estimativa mostrada, ou segurada com a 2) fica registrada como recusada (veto) — nada vai à fila nem conta no teto — e, se o dono não soube, a ação equipe da vigia conta no que mudou ("Não mandei a ficha de ter 03/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto."); a pergunta do dia fecha (resolvida). Fora disso, a de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): a ficha segurada de quem não tem telefone diz o porquê ("Não mandei a ficha de qui 05/11 a Alex (Lenine): o dia é pela minha estimativa e Alex não tem telefone no cadastro. Fale com Alex.", por = sem_telefone); e a pergunta da ficha que fechou "ela foi como eu disse" com a ficha recusada no registro ganha o motivo verdadeiro ("… mas ela não saiu (sem telefone no cadastro)"). FASE 7f (P5): com o convite ligado de verdade, quem tem o convite de amanhã sem o SIM não recebe a ficha (AG7-23); com o previsto ligado de verdade e a equipe ligada, a ficha leva a mudança da semana ("Na semana: sai …; entra …") e, na quinta, o previsto da semana que vem, numa mensagem só, e grava em dias o que a pessoa passa a ter ouvido. Fora disso, a de antes, byte a byte.';

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
  -- FASE 7c: (7c P8) as etapas no "como foi"
  v_p8_dp    jsonb;
  v_p8_lista jsonb;
  v_p8_lt    jsonb;
  v_p8_its   jsonb;
  v_p8_parc  jsonb := '{}'::jsonb;
  v_p8_conf  text[];
  v_p8_os    text;
  v_p8_tu    text[];
  -- FASE 7c: fim
  -- FASE 7f: (7f P5) o convite, o previsto e a mudança
  v_7f_cv    public.agenda_equipe_mensagens%rowtype;
  v_7f_x     uuid;
  v_7f_plano text[];
  v_7f_sim   boolean;
  v_7f_resp  text;
  -- FASE 7f: fim
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
  -- FASE 7f: (7f P5, §5.5, AG7-23) o convite vale até o prazo dele (a ficha da véspera), não só equipe_resposta_validade: o aberto e mais novo que a
  -- mensagem de cima é a mensagem a que ele responde (a última que o sistema começou, como sempre).
  select * into v_7f_cv from public.agenda_equipe_mensagens x
   where x.payee_id = v_payee and x.tipo = 'convite' and x.modo = 'ligado' and x.estado = 'enfileirada' and x.enviar_em <= p_recebida_em
     and public._agenda_equipe_convite_prazo(x.dia) > p_recebida_em
   order by x.enviar_em desc, x.criada_em desc limit 1;
  if v_7f_cv.id is not null and (m.id is null or v_7f_cv.enviar_em > m.enviar_em) then
    m := v_7f_cv;
  end if;
  -- FASE 7f: fim
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

  -- FASE 7f: (7f P5, §5.5, §6.4, AG7-23, E5, E6) antes do "não vou":
  --   · o NÃO ao convite é o "não vou" do dia do convite: o caminho de baixo, com a mensagem tratada como a ficha daquele dia (m.tipo só aqui, na
  --     variável; a linha continua convite). A disponibilidade, o replano, a ação e o "Tá bom, aviso o Gustavo." são os de sempre;
  --   · a ficha que levou a semana (o previsto ou a mudança, dias gravados): "não posso quarta" de outro dia que não o da ficha é dia que a gramática
  --     não conhece: vai ao dono com o trecho, e nada é remanejado (a ficha continua esperando o OK dela).
  if m.id is not null and m.tipo = 'convite' and v_tipo <> 'pergunta'
     and (v_tipo = 'nao_vou' or public._agenda_normal(p_body) ~ '^(nao|n)\M') then
    v_tipo := 'nao_vou';
    v_l := v_l || jsonb_build_object('tipo', 'nao_vou', 'convite', 'nao');
    m.tipo := 'ficha';
  end if;
  if m.id is not null and v_tipo = 'nao_vou' and m.tipo = 'ficha' and m.dias is not null
     and exists (select 1 from unnest(public._agenda_dias_citados(p_body)) d where d <> extract(isodow from m.dia)::int) then
    perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:semana', v_payee, m.dia), v_payee, null, m.dia,
      format('O %s respondeu "%s" à ficha de %s, que levava a semana dele, e eu não mudei nada: diga o que fazer com o dia que ele falou.',
             v_nome, public._agenda_corta(v_trecho, 120), public._dia_curto(m.dia)),
      'ligado', p_recebida_em);
    update public.agenda_equipe_mensagens
       set leitura = coalesce(leitura, '{}'::jsonb) || jsonb_build_object('semana', v_trecho, 'semana_em', p_recebida_em)
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'semana', true, 'resposta', null);
  end if;
  -- FASE 7f: fim
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
    -- FASE 7f: (7f P5, §5.5 (b), NOVO-agenda-76) quem a troca tirou do dia que já tinha ficha fica sabendo na hora (a mensagem de mudança), antes do
    -- acorde: o "Já avisei" do acorde (_agenda_texto_do_acorde) só sai com ela na fila. O que falhar aqui não derruba o "não vou": registra e segue.
    if public._agenda_fala_modo('previsto') <> 'desligado' then
      begin
        for v_7f_x in select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(v_rep -> 'acoes', '[]'::jsonb)) x loop
          perform public._agenda_equipe_mudanca_na_hora(v_7f_x, v_hoje, p_recebida_em);
        end loop;
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform public.log_app_error('db', 'agenda: a mudança na hora depois do "não vou" falhou: ' || v_msg, 'agenda', 'equipe:mudanca', 'error',
                                     jsonb_build_object('payee', v_payee, 'dia', v_dia, 'sqlstate', v_estado));
      end;
    end if;
    -- FASE 7f: fim
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

  -- FASE 7f: (7f P5, §5.5, §6.4, R8.7, E5, E5b, E6) a resposta ao convite, ao previsto e à mudança:
  --   · ao convite, o SIM (ok, presença, ou os turnos do plano com o ok) confirma: grava ANTES a disponibilidade confirmada no dia (como o ok à ficha)
  --     e a mensagem respondida, e depois responde "Combinado, até <dia>." — acima do teto de respostas do dia a resposta é recusada e o SIM vale;
  --     o que não é SIM nem NÃO vai ao dono com o trecho, e o convite segue esperando o SIM até o prazo (o NÃO é o caminho do "não vou", acima);
  --   · ao previsto e à mudança, o ok é ciência (respondida, nada muda, sem resposta automática); o resto vai ao dono com o trecho, sem remanejar.
  if m.tipo = 'convite' then
    v_7f_plano := array(select distinct a.turno from public.agenda_alocacoes a
                         where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' order by 1);
    v_7f_sim := v_tipo in ('ok', 'presenca')
                or (v_tipo = 'turnos' and coalesce((v_l ->> 'ok')::boolean, false)
                    and (jsonb_typeof(v_l -> 'turnos') is distinct from 'array'
                         or array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1) = v_7f_plano
                         or (v_l -> 'turnos' = '["meio"]'::jsonb and cardinality(v_7f_plano) = 1)));
    if v_7f_sim then
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'confirmada'
                        and d.turno is null and d.periodo @> m.dia) then
        insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
        values (v_payee, daterange(m.dia, m.dia, '[]'), 'confirmada', 'diarista', left('Disse SIM ao convite: ' || v_trecho, 200),
                left(v_trecho, 300), p_recebida_em);
      end if;
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_l || jsonb_build_object('convite', 'sim')
       where id = m.id;
      v_7f_resp := format('Combinado, até %s.', public._dia_curto(m.dia));
      v_r := public._agenda_equipe_registrar(v_payee, m.dia, 'resposta', v_7f_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'convite', 'leitura', 'sim', 'dia', m.dia,
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7f_resp end, 'envio', v_r ->> 'estado');
    end if;
    perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:convite', v_payee, m.dia), v_payee, null, m.dia,
      format('O %s respondeu "%s" ao convite de %s, e eu não entendi. Sem o SIM dele até %s, ele sai do dia.', v_nome,
             public._agenda_corta(v_trecho, 120), public._dia_curto(m.dia),
             public._dia_curto((public._agenda_equipe_convite_prazo(m.dia) at time zone 'America/Sao_Paulo')::date) || ' às '
             || to_char(public._agenda_equipe_convite_prazo(m.dia) at time zone 'America/Sao_Paulo', 'HH24:MI')),
      'ligado', p_recebida_em);
    update public.agenda_equipe_mensagens
       set leitura = coalesce(leitura, '{}'::jsonb) || jsonb_build_object('nao_entendi', v_trecho, 'recebida_em', p_recebida_em)
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', 'convite', 'leitura', 'nao_entendi', 'resposta', null);
  end if;
  if m.tipo in ('previsto', 'mudanca') then
    if v_tipo = 'ok' then
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_l || jsonb_build_object('ciencia', true)
       where id = m.id;
      return jsonb_build_object('consumiu', true, 'tipo', m.tipo, 'ciencia', true, 'resposta', null);
    end if;
    perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:%s', v_payee, m.dia, m.tipo), v_payee, null, m.dia,
      format('O %s respondeu "%s" à %s, e eu não mudei nada: diga o que fazer.', v_nome, public._agenda_corta(v_trecho, 120),
             case m.tipo when 'previsto' then 'semana prevista dele' else 'mudança da semana dele' end),
      'ligado', p_recebida_em);
    update public.agenda_equipe_mensagens
       set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
           leitura = v_l || jsonb_build_object('ao_dono', true)
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', m.tipo, 'ao_dono', true, 'resposta', null);
  end if;
  -- FASE 7f: fim
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
  -- FASE 7c: (7c P8, §16.5.3, §16.3.8; AG7-10b) com modo_tarefas ligado, as etapas do que devia ficar pronto hoje (de quem responde, sem
  -- resultado: _agenda_tarefas_da_pessoa) lidas sem IA (_agenda_ler_tarefas_da_resposta); com o "como foi" que não tem mais a lista de
  -- agora (_agenda_tarefas_texto_confere), os números não valem e só as palavras são lidas. A resposta só das etapas, sem turno nem OK,
  -- vale os turnos do plano para a diária só com tarefas_resposta_vale_dia = sempre, ou = tudo e "tudo"/"fiz tudo" — sem virar o tipo ok
  -- (o "fiz tudo" é sobre hoje: não confirma a ficha de amanhã que o "como foi" levava).
  if cf.modo_tarefas = 'ligado' then
    v_p8_dp := public._agenda_tarefas_da_pessoa(v_payee, m.dia, v_hoje);
    v_p8_lista := coalesce(v_p8_dp -> 'pergunta', '[]'::jsonb);
    if jsonb_array_length(v_p8_lista) > 0 then
      v_p8_lt := public._agenda_ler_tarefas_da_resposta(
                   case when public._agenda_tarefas_texto_confere(m.texto, v_p8_lista) then p_body
                        else regexp_replace(coalesce(p_body, ''), '[0-9]+', ' ', 'g') end,
                   v_p8_lista);
      if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) and not v_ent and v_tipo in ('nao_entendi', 'turnos')
         and jsonb_typeof(v_l -> 'turnos') is distinct from 'array' and not coalesce((v_l ->> 'ok')::boolean, false)
         and (cf.tarefas_resposta_vale_dia = 'sempre'
              or (cf.tarefas_resposta_vale_dia = 'tudo' and coalesce((v_p8_lt ->> 'tudo')::boolean, false))) then
        v_ent := true;
        v_ditos := v_plano;
        v_term := coalesce((v_p8_lt ->> 'tudo')::boolean, false);
      end if;
    end if;
  end if;
  -- FASE 7c: fim
  update public.agenda_equipe_mensagens
     set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
         leitura = v_l || jsonb_build_object('entendeu', v_ent, 'turnos_lidos', to_jsonb(v_ditos), 'turnos_plano', to_jsonb(v_plano),
                                             'terminou', v_term)
   where id = m.id;
  -- FASE 7c: (7c P8, §16.5.3, §16.6.4) a leitura das etapas fica na mensagem (tarefas e a lista perguntada); a entendida grava as feitas
  -- e as pendentes (via equipe, por _agenda_tarefas_registrar: vale sobre a conferência); a que falou de falta sem dizer qual vira a
  -- pergunta equipe_resposta ao dono, e nada muda nas etapas.
  if v_p8_lt is not null then
    update public.agenda_equipe_mensagens
       set leitura = coalesce(leitura, '{}'::jsonb) || jsonb_build_object('tarefas', v_p8_lt, 'lista', v_p8_lista)
     where id = m.id;
    v_p8_its := coalesce(v_p8_dp -> 'itens', '[]'::jsonb);
    if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) then
      perform public._agenda_tarefas_registrar(
        array(select (i ->> 'linha_id')::uuid from jsonb_array_elements(v_p8_its) i
               where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'feitas') x)
                 and i ->> 'linha_id' is not null),
        'feita', 'equipe', v_trecho, m.id, p_recebida_em);
      perform public._agenda_tarefas_registrar(
        array(select (i ->> 'linha_id')::uuid from jsonb_array_elements(v_p8_its) i
               where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'pendentes') x)
                 and i ->> 'linha_id' is not null),
        'pendente', 'equipe', v_trecho, m.id, p_recebida_em);
    elsif coalesce((v_p8_lt ->> 'falou_de_falta')::boolean, false) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:tarefas', v_payee, m.dia), v_payee,
        (v_p8_its -> 0 ->> 'os')::uuid, m.dia,
        format('O %s respondeu "%s" ao "como foi" do %s (%s), e não entendi o que faltou. Me diga qual (ex.: "no %s falta %s").',
               v_nome, public._agenda_corta(v_trecho, 120), v_p8_its -> 0 ->> 'cliente', public._dia_curto(m.dia),
               v_p8_its -> 0 ->> 'cliente',
               lower(left(v_p8_lista -> 0 ->> 'texto', 1)) || substr(v_p8_lista -> 0 ->> 'texto', 2)),
        'ligado', p_recebida_em);
    end if;
  end if;
  -- FASE 7c: fim
  if v_ent then
    v_conf := array(select x from unnest(v_ditos) x where x = any (v_plano) order by 1);
    perform set_config('agenda.hoje', v_hoje::text, true);
    -- FASE 7c: (7c P8, §16.5.3, §16.3.9) com a leitura das etapas entendida: o turno confirmado em que termina uma etapa pendente sai do
    -- cumprido e vai a parcial (o motivo da leitura, senão estimativa), por OS, logo depois do cumprido dos outros; as etapas que terminavam
    -- num turno que ele não confirmou ficam pendentes (via equipe).
    if v_p8_lt is not null then
      v_p8_conf := v_conf;
      v_p8_its := coalesce(v_p8_dp -> 'itens', '[]'::jsonb);
      if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) then
        select coalesce(jsonb_object_agg(z.os, z.tus), '{}'::jsonb) into v_p8_parc
          from (select i ->> 'os' as os, jsonb_agg(distinct d.turno) as tus
                  from jsonb_array_elements(v_p8_its) i
                  join public.os_tarefas_dia d on d.id = (i ->> 'linha_id')::uuid
                 where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'pendentes') x)
                   and d.turno = any (v_conf)
                 group by i ->> 'os') z;
        v_conf := array(select x from unnest(v_conf) x
                         where not exists (select 1 from jsonb_each(v_p8_parc) p, jsonb_array_elements_text(p.value) t where t = x)
                         order by 1);
      end if;
      perform public._agenda_tarefas_registrar(
        array(select d.id from jsonb_array_elements(coalesce(v_p8_dp -> 'pergunta', '[]'::jsonb)) q
                join jsonb_array_elements(v_p8_its) i on (i ->> 'n')::int = (q ->> 'n')::int
                join public.os_tarefas_dia d on d.id = (i ->> 'linha_id')::uuid
               where not (d.turno = any (v_p8_conf))
                 and not (v_ditos = array['meio'] and cardinality(v_plano) = 1)
                 and not (coalesce((v_p8_lt ->> 'entendeu')::boolean, false)
                          and (q ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'feitas') x))),
        'pendente', 'equipe', v_trecho, m.id, p_recebida_em);
    end if;
    -- FASE 7c: fim
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
    -- FASE 7c: (7c P8, §16.5.3) o turno com etapa pendente: parcial, por OS (agenda_registrar_dia via equipe, só os turnos dela)
    for v_p8_os in select k from jsonb_object_keys(v_p8_parc) k order by 1 loop
      begin
        v_p8_tu := array(select x from jsonb_array_elements_text(v_p8_parc -> v_p8_os) x order by 1);
        perform set_config('agenda.turnos_equipe', array_to_string(v_p8_tu, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'parcial', coalesce(v_p8_lt ->> 'motivo', 'estimativa'), v_p8_os::uuid,
                                           array[v_payee], 'equipe', v_trecho, v_hoje, p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.turnos_equipe', '', true);
        perform public.log_app_error('db', 'agenda: anotar o parcial pelas etapas da equipe falhou: ' || v_msg, 'agenda',
                                     'tarefas:parcial', 'error',
                                     jsonb_build_object('payee', v_payee, 'dia', m.dia, 'os', v_p8_os, 'sqlstate', v_estado));
      end;
    end loop;
    -- FASE 7c: fim
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
  'Agenda de Produção (Fase 3, P4): a mensagem do técnico (número que não é login de admin), chamada pelo whatsapp-webhook antes da confirmação do cliente e da conferência do recibo. modo_equipe desligado, telefone de ninguém da equipe (ou de dois) = {consumiu: false}. A mesma mensagem (p_message_id) de novo = nada muda. Lida por _agenda_ler_resposta_da_equipe. Decide a última mensagem que o sistema mandou (ligado, enfileirada, dentro de equipe_resposta_validade); o recibo de diárias mandado depois dela fica com o "ok" (NOVO-agenda-17: consumiu false). pergunta → a ficha do publicado (agenda_equipe_ficha.texto_resposta) como resposta enfileirada (sem plano: a pergunta equipe_resposta ao dono); em sombra só registra (consumiu false). nao_vou → indisponível no dia (agenda_disponibilidade origem diarista), replano (modo_proposta ligado, origem vigia), ação equipe com o acorde para a rotina e "Tá bom, aviso o Gustavo."; em sombra só a ação executada = false. ok/presença à ficha ou à confirmação → confirmada, sem resposta; não entendido → equipe_resposta ao dono, sem remanejo. Ao "como foi hoje?": ok = os turnos do plano e terminou; os turnos ditos viram resultado (agenda_registrar_dia via equipe, só os turnos confirmados) e a diária (_agenda_diaria_do_dia); não entendido = a pergunta crítica da diária. Sem pendente (ok, turnos, presença, não entendi) = consumiu false. {consumiu, tipo, resposta, acao_id}. Só service_role. FASE 7b (P3, §5.2; A1 = NOVO-agenda-52, A2, A3 = NOVO-agenda-54): com modo_dias ligado, a resposta à pergunta dos dias da semana (a mensagem dias ligada, enfileirada, mandada antes e com o prazo da semana por vir) é lida por _agenda_ler_dias_da_equipe ANTES da pergunta, do "não vou" e do "como foi": os dias ou "nenhum" (em qualquer ordem) gravam a semana presa e o padrão de quem tem (_agenda_equipe_dias_gravar, origem diarista; a exceção do dono no dia vence e volta em leitura.conflitos), a mensagem fica respondida e sai "Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!" / "… você não pode. Obrigado por avisar!"; "igual"/"ok" com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!"; não entendido com a pergunta por último (e a leitura geral não é pergunta, presença nem turnos; o "não vou" junto de um dia da semana também — "segunda não posso" nunca vira o "não vou" da ficha): 1ª vez "Não entendi os dias da semana de 16/11. Mande só os dias, assim: seg ter qui (ou "nenhum")." (chave agenda-equipe:resposta:<pessoa>:dias:<segunda>), 2ª vez a pergunta equipe_resposta ao dono e a mensagem respondida. {consumiu: true, tipo: dias, leitura, …}. A "última que o sistema começou" do resto não é mais a pergunta da semana. Fora disso, o de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 8): com modo_dias ligado, a pergunta da semana aberta só leva a resposta (os dias ou "nenhum") quando é a última mensagem mandada a ele, quando a frase fala da semana ou quando é só a lista dos dias e a leitura de sempre não a entende; com a ficha, a confirmação ou o "como foi" mandados depois, "não posso", "ok, sexta tô lá", "sim, todos prontos" e "terminei todos" seguem o caminho de antes (o "não vou", a confirmação, os turnos) e a pergunta da semana continua aberta. FASE 7c (P8, §16.5.3, §16.3.8; AG7-10b): com modo_tarefas ligado, no "como foi" a lista do que devia ficar pronto (de quem responde, sem resultado) é lida por _agenda_ler_tarefas_da_resposta (com o texto que não tem mais a lista de agora, só as palavras) e gravada na mensagem (tarefas, lista); a entendida grava as feitas e as pendentes via equipe (_agenda_tarefas_registrar), o turno confirmado em que termina uma pendente sai do cumprido e vai a parcial (o motivo da leitura, senão estimativa), por OS, e as etapas de turno não confirmado ficam pendentes; a que falou de falta sem dizer qual vira a pergunta equipe_resposta ao dono ("O Alex respondeu "faltou umas coisas" ao "como foi" do Lenine (qua 04/11), e não entendi o que faltou. Me diga qual (…)."); a resposta só das etapas vale os turnos do plano para a diária com tarefas_resposta_vale_dia sempre, ou tudo e "tudo" (sem virar o tipo ok). Desligado ou em teste: a de antes, byte a byte. FASE 7f (P5): o convite vale até o prazo dele: SIM (ok, presença, os turnos do plano com o ok) grava a disponibilidade confirmada e a mensagem respondida ANTES de responder "Combinado, até <dia>." (acima do teto de respostas a resposta é recusada e o SIM vale); NÃO = o caminho do "não vou" com o dia do convite; o resto vai ao dono e o convite segue esperando. Ao previsto e à mudança, ok = ciência, o resto vai ao dono sem remanejar; à ficha que levou a semana, "não posso quarta" de outro dia vai ao dono. Depois do replano do "não vou", a mudança na hora de quem já tinha a ficha (_agenda_equipe_mudanca_na_hora).';

create or replace function public._agenda_texto_do_acorde(p_acao uuid, p_perda date, p_hoje date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select format('Mudei a agenda de %s: %s', case when p_perda = p_hoje then 'hoje' when p_perda = p_hoje + 1 then 'amanhã'
                                                 else public._dia_curto(p_perda) end, a.texto)
         || case when a.desfazivel_ate is not null
                 then format(' *desfaz %s* volta como estava.',
                             coalesce(public._agenda_nome_curto(cl.name), so.service_order_number, 'isso'))
                 else '' end
         -- FASE 7f: (7f P5, §5.4, NOVO-agenda-76, R8.12-9) quem já tinha a ficha (ou a confirmação) do dia e recebeu a mensagem de mudança desta
         -- ação (na fila, ligada: _agenda_equipe_ja_avisei) — " Já avisei o Roberto." no lugar do "avise ele"; sem ela (sem telefone, teto, fora da
         -- janela, em teste), o texto de antes, abaixo. Quem faltou não entra, como antes.
         || coalesce((select format(' Já avisei o %s.', public._agenda_nome_curto(py.name))
                        from public.agenda_equipe_mensagens m join public.payees py on py.id = m.payee_id
                       where m.modo = 'ligado' and m.tipo in ('ficha', 'confirmar') and m.dia = p_perda
                         and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
                         and m.payee_id in (select b.payee_id from public.agenda_alocacoes b
                                             where b.id = any (a.alocacoes_canceladas || a.alocacoes_criadas))
                         and public._agenda_equipe_ja_avisei(m.payee_id, m.dia, p_acao)
                         and not exists (select 1 from public.agenda_disponibilidade d
                                          where d.payee_id = m.payee_id and d.substituida_em is null and d.situacao = 'indisponivel'
                                            and d.periodo @> m.dia)
                       order by m.enviar_em desc, m.id limit 1), '')
         -- FASE 7f: fim
         -- FASE 3: quem já recebeu a ficha (ou a confirmação) do dia que mudou: o dono avisa (a mensagem de mudança à
         -- equipe é da Fase 5). Quem faltou (indisponível no dia) não entra.
         || coalesce((select format(' O %s já recebeu a ficha de %s com o %s: avise ele da mudança.', public._agenda_nome_curto(py.name),
                                    case when m.dia = p_hoje then 'hoje' when m.dia = p_hoje + 1 then 'amanhã' else public._dia_curto(m.dia) end,
                                    coalesce(public._agenda_nome_curto(cl.name), 'serviço'))
                        from public.agenda_equipe_mensagens m join public.payees py on py.id = m.payee_id
                       where m.modo = 'ligado' and m.tipo in ('ficha', 'confirmar') and m.dia = p_perda
                         and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
                         and m.payee_id in (select b.payee_id from public.agenda_alocacoes b
                                             where b.id = any (a.alocacoes_canceladas || a.alocacoes_criadas))
                         -- FASE 7f: (7f P5) quem a mensagem de mudança já avisou sai daqui: o "Já avisei" de cima é o dele
                         and not public._agenda_equipe_ja_avisei(m.payee_id, m.dia, p_acao)
                         -- FASE 7f: fim
                         and not exists (select 1 from public.agenda_disponibilidade d
                                          where d.payee_id = m.payee_id and d.substituida_em is null and d.situacao = 'indisponivel'
                                            and d.periodo @> m.dia)
                       order by m.enviar_em desc, m.id limit 1), '')
    from public.agenda_acoes a
    left join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where a.id = p_acao;
$function$;

comment on function public._agenda_texto_do_acorde(uuid, date, date) is
  'Agenda de Produção (Fase 2, P3): o acorde de uma mudança feita sozinha — "Mudei a agenda de amanhã: <a frase da ação> *desfaz Vanderlei* volta como estava." Fase 3: quando a mudança atinge quem já recebeu a ficha do dia (e não faltou), "O Roberto já recebeu a ficha de amanhã com o Lenine: avise ele da mudança." FASE 7f (P5): quem tinha a ficha do dia e já recebeu a mensagem de mudança desta ação (_agenda_equipe_ja_avisei: ligada, na fila) — " Já avisei o Roberto." no lugar do "avise ele da mudança"; sem ela, o texto de antes.';

create or replace function public._agenda_rotina_acordes_da_equipe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  r        record;
  v_rep    uuid;
  v_nome   text;
  v_txt    text;
  v_acordes jsonb := '[]'::jsonb;
begin
  for r in
    select e.* from public.agenda_acoes e
     where e.tipo = 'equipe' and e.executada and e.contada_em is null and coalesce((e.depois ->> 'acorde')::boolean, false)
       and e.dia >= p_hoje - 1
       and (e.depois ->> 'dia')::date between p_hoje and public.agenda_somar_du(p_hoje, cf.congelamento_du)
     order by e.criada_em, e.id
  loop
    -- a mudança que o replano fez (a 1ª executada); o acorde sai uma vez (a mudança ou o aviso contados)
    select a.id into v_rep from public.agenda_acoes a
     where a.id in (select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(r.depois -> 'replano_acoes', '[]'::jsonb)) x)
       and a.executada
     order by a.criada_em, a.id limit 1;
    continue when exists (select 1 from public.agenda_acoes a
                           where a.contada_via = 'acorde'
                             and (a.id = v_rep or a.id in (select (x #>> '{}')::uuid
                                                              from jsonb_array_elements(coalesce(r.depois -> 'replano_acoes', '[]'::jsonb)) x)));
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = r.payee_id);
    v_txt := case r.depois ->> 'motivo'
               when 'silencio' then split_part(r.texto, '.', 1) || '.'
               else format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe((r.depois ->> 'dia')::date, p_hoje)) end
             || case when v_rep is not null then ' ' || public._agenda_texto_do_acorde(v_rep, (r.depois ->> 'dia')::date, p_hoje)
                     else ' A agenda automática não está ligada: reveja o dia dele.' end;
    -- FASE 7f: (7f P5, §6.3) o convite sem o SIM no prazo (sem_sim) e o dia novo sem tempo de convidar (convite_sem_prazo): a pessoa não "avisou que
    -- não vem". A frase é a da ação (a 1ª, sem o replano); o replano vem do acorde de sempre.
    if r.depois ->> 'motivo' = 'sem_sim' then
      v_txt := split_part(r.texto, '.', 1) || '.'
               || case when v_rep is not null then ' ' || public._agenda_texto_do_acorde(v_rep, (r.depois ->> 'dia')::date, p_hoje)
                       else ' A agenda automática não está ligada: reveja o dia dele.' end;
    elsif r.depois ->> 'motivo' = 'convite_sem_prazo' then
      v_txt := r.texto;
    end if;
    -- FASE 7f: fim
    v_acordes := v_acordes || jsonb_build_object('chave', 'agenda:' || coalesce(v_rep, r.id), 'assunto', 'equipe:' || r.payee_id,
                   'acao_id', coalesce(v_rep, r.id), 'os', r.service_order_id, 'perda_em', r.depois ->> 'dia', 'texto', v_txt);
  end loop;
  return jsonb_build_object('acordes_da_equipe', jsonb_array_length(v_acordes), 'acordes', v_acordes);
end;
$function$;

comment on function public._agenda_rotina_acordes_da_equipe(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): os acordes ao dono que a resposta da equipe pede (o não vou, o silêncio de manhã): a ação equipe executada com acorde, não contada, do dia de hoje ao congelamento; a frase da ação e o texto do acorde do replano (_agenda_texto_do_acorde), uma vez. FASE 7f (P5): o convite sem o SIM (motivo sem_sim) e o dia novo sem tempo de convidar (convite_sem_prazo) têm a frase da ação, não "avisou que não vem".';

-- ── 9. Os 4 passos da equipe da rodada comunicar ─────────────────────────────────────────────────────
-- A rodada (agenda_comunicar_rodar, P2/P4, NÃO recriada) chama cada um pelo nome, na ordem previsto, mudancas_equipe, convites, convites_vencidos, no seu bloco (erro =
-- comunicar:<passo>, e segue). Cada um sai na 1ª leitura quando ninguém da rotina tem telefone (R8.8; o caso de hoje: o Alex não tem).

-- §5.5, R8.5-17: só no dia_do_plano (dia útil), a partir de equipe_hora_ficha, dentro da janela da equipe. Quem leva o previsto é a ficha (a das 19:30, _agenda_rotina_ficha,
-- que roda antes no tique, ou a que foi no "como foi" das 17:00); este passo só cuida de quem ficou sem: sem plano amanhã, ou a ficha recusada. Uma por pessoa e
-- semana (chave agenda-equipe:previsto:<pessoa>:<segunda>, dia = a segunda). Laço pelos dias da semana que vem (_agenda_contatos_com_plano recebe 1 dia).
create or replace function public._agenda_comunicar_previsto(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_fala  text;
  v_modo  text;
  v_seg   date;
  v_am    date;
  v_d     date;
  v_p     uuid;
  v_vistos uuid[] := '{}';
  v_s     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora do previsto da equipe.' using errcode = '22023';
  end if;
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano or not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('pulado', true, 'motivo', 'dia');
  end if;
  if v_local::time < cf.equipe_hora_ficha then
    return jsonb_build_object('pulado', true, 'motivo', 'cedo');
  end if;
  v_fala := public._agenda_fala_modo('previsto');
  if v_fala = 'desligado' or cf.modo_equipe = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado');
  end if;
  if not exists (select 1 from public.agenda_equipe_contato c join public.payees p on p.id = c.payee_id
                  where c.recebe_rotina and c.parou_em is null and p.active and public._agenda_equipe_tem_telefone(p.id)) then
    return jsonb_build_object('pulado', true, 'motivo', 'sem_telefone');
  end if;
  if public._agenda_equipe_fora_da_janela('previsto', p_agora, p_agora) is not null then
    return jsonb_build_object('pulado', true, 'motivo', 'janela');
  end if;
  v_modo := case when cf.modo_equipe = 'ligado' and v_fala = 'ligado' then 'ligado' else 'sombra' end;
  v_seg := date_trunc('week', p_hoje)::date + 7;
  v_am := public.agenda_somar_du(p_hoje, 1);
  for v_d in select g::date from generate_series(v_seg, v_seg + 6, interval '1 day') g order by 1 loop
    for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
      continue when v_p = any (v_vistos);
      v_vistos := v_vistos || v_p;
      if not public._agenda_equipe_tem_telefone(v_p) then
        v_cont := v_cont || jsonb_build_object('sem_telefone', coalesce((v_cont ->> 'sem_telefone')::int, 0) + 1);
        continue;
      end if;
      if exists (select 1 from public.agenda_equipe_mensagens m
                  where m.payee_id = v_p and m.tipo = 'previsto' and m.dia = v_seg and m.modo = v_modo) then
        v_cont := v_cont || jsonb_build_object('ja_existe', coalesce((v_cont ->> 'ja_existe')::int, 0) + 1);
        continue;
      end if;
      -- tem a ficha de amanhã (não recusada; também a que foi no "como foi"): o previsto foi junto dela, e não se recria o que já foi à fila (R8.5-17)
      if exists (select 1 from public.agenda_equipe_mensagens m
                  where m.payee_id = v_p and m.modo = v_modo and m.estado <> 'recusada'
                    and ((m.tipo = 'ficha' and m.dia = v_am) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_am))) then
        v_cont := v_cont || jsonb_build_object('tem_ficha', coalesce((v_cont ->> 'tem_ficha')::int, 0) + 1);
        continue;
      end if;
      v_s := public._agenda_equipe_semana_da_pessoa(v_p, p_hoje, p_agora, v_modo);
      continue when jsonb_array_length(coalesce(v_s -> 'previsto', '[]'::jsonb)) = 0;
      v_r := public._agenda_equipe_registrar(v_p, v_seg, 'previsto', v_s ->> 'texto_previsto', p_agora, null, null,
                                             array(select x::date from jsonb_array_elements_text(v_s -> 'estado_previsto') x order by 1));
      v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'), coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
    end loop;
  end loop;
  return jsonb_build_object('semana', v_seg, 'modo', v_modo, 'por_estado', v_cont);
end;
$function$;

comment on function public._agenda_comunicar_previsto(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P5; §5.5, §6.4, R8.5-17): o passo previsto da rodada comunicar. Só no dia_do_plano (dia útil), a partir de equipe_hora_ficha e dentro da janela da equipe; desligado (o modo do previsto pela _agenda_fala_modo, ou a equipe) = {pulado}; ninguém da rotina com telefone = {pulado: sem_telefone} na 1ª leitura. Para cada pessoa com telefone e dia na semana que vem (_agenda_contatos_com_plano, dia a dia), que ainda não recebeu o previsto e não tem a ficha de amanhã (não recusada; também a do "como foi": ela o leva): "Roberto, semana que vem (previsto, pode mudar): ter 17 e qua 18/11. Se algum desses dias não der, me fala." (chave agenda-equipe:previsto:<pessoa>:<segunda>; em teste, ":sombra"). {semana, modo, por_estado}. Volatile, invoker, sem grant.';

-- §5.5 (a) e (b). (a) às equipe_hora_ficha de dia útil, uma mudança por pessoa que já ouviu dias da semana (a chave das 19:30 do dia); quem a ficha das 19:30 levou já
-- não tem diferença (a ficha grava o que ela passa a ter ouvido). (b) em qualquer tique dentro da janela, a mudança na hora pelas ações de ontem e hoje que tiraram
-- alguém de um dia que já teve ficha: a decisão do dono (a crítica respondida, ou a do dono, do assistente, da tela, da aprovação) ou o replano da falta de outra
-- pessoa (as replano_acoes da ação equipe de um "não vou", do silêncio ou do convite sem SIM).
create or replace function public._agenda_comunicar_mudancas_equipe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_fala  text;
  v_modo  text;
  v_p     uuid;
  v_a     uuid;
  v_chave text;
  v_s     jsonb;
  v_r     jsonb;
  v_c19   jsonb := '{}'::jsonb;
  v_ch    jsonb := '{}'::jsonb;
  k       text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da mudança da equipe.' using errcode = '22023';
  end if;
  v_fala := public._agenda_fala_modo('previsto');
  if v_fala = 'desligado' or cf.modo_equipe = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado');
  end if;
  if not exists (select 1 from public.agenda_equipe_contato c join public.payees p on p.id = c.payee_id
                  where c.recebe_rotina and c.parou_em is null and p.active and public._agenda_equipe_tem_telefone(p.id)) then
    return jsonb_build_object('pulado', true, 'motivo', 'sem_telefone');
  end if;
  if public._agenda_equipe_fora_da_janela('mudanca', p_agora, p_agora) is not null then
    return jsonb_build_object('pulado', true, 'motivo', 'janela');
  end if;
  v_modo := case when cf.modo_equipe = 'ligado' and v_fala = 'ligado' then 'ligado' else 'sombra' end;
  -- (a) às 19:30 de dia útil
  if public.agenda_dia_util(p_hoje) and v_local::time >= cf.equipe_hora_ficha then
    for v_p in
      select c.payee_id from public.agenda_equipe_contato c join public.payees py on py.id = c.payee_id
       where c.recebe_rotina and c.parou_em is null and py.active
         and exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = c.payee_id and m.modo = v_modo and m.dias is not null and m.enviar_em >= p_agora - interval '15 days')
       order by c.payee_id
    loop
      continue when not public._agenda_equipe_tem_telefone(v_p);
      v_chave := format('agenda-equipe:mudanca:%s:%s:19h', v_p, p_hoje);
      continue when exists (select 1 from public.agenda_equipe_mensagens m
                             where m.dedupe_key = v_chave || case when v_modo = 'sombra' then ':sombra' else '' end);
      v_s := public._agenda_equipe_semana_da_pessoa(v_p, p_hoje, p_agora, v_modo);
      continue when jsonb_typeof(v_s -> 'mudanca') is distinct from 'object';
      v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'mudanca', v_s ->> 'texto_mudanca', p_agora, null, null,
                                             array(select x::date from jsonb_array_elements_text(v_s -> 'estado_mudanca') x order by 1), null, v_chave);
      v_c19 := v_c19 || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'), coalesce((v_c19 ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
    end loop;
  end if;
  -- (b) na hora
  for v_a in
    select a.id from public.agenda_acoes a
     where a.dia >= p_hoje - 1 and a.executada and a.desfeita_em is null and a.criada_em <= p_agora
       and cardinality(a.alocacoes_canceladas) > 0
       and (a.critica or a.origem in ('dono', 'assistente', 'tela', 'aprovacao')
            or exists (select 1 from public.agenda_acoes e
                        where e.tipo = 'equipe' and e.executada and e.dia >= p_hoje - 2
                          and e.depois ->> 'motivo' in ('nao_vou', 'sem_sim', 'silencio')
                          and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) @> jsonb_build_array(a.id::text)))
       and exists (select 1 from public.agenda_alocacoes b where b.id = any (a.alocacoes_canceladas) and b.dia >= p_hoje)
     order by a.criada_em, a.id
  loop
    v_r := public._agenda_equipe_mudanca_na_hora(v_a, p_hoje, p_agora);
    for k in select jsonb_object_keys(coalesce(v_r -> 'por_estado', '{}'::jsonb)) loop
      v_ch := v_ch || jsonb_build_object(k, coalesce((v_ch ->> k)::int, 0) + (v_r -> 'por_estado' ->> k)::int);
    end loop;
  end loop;
  return jsonb_build_object('modo', v_modo, 'as_19h', v_c19, 'na_hora', v_ch);
end;
$function$;

comment on function public._agenda_comunicar_mudancas_equipe(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P5; §5.5, §6.4): o passo mudancas_equipe da rodada comunicar. (a) Às equipe_hora_ficha de dia útil, para cada pessoa da rotina com telefone que já ouviu dias da semana (_agenda_equipe_semana_da_pessoa): a diferença vira UMA mensagem (chave agenda-equipe:mudanca:<pessoa>:<dia>:19h) — "Roberto, mudou a sua semana: sai ter 17/11; entra qui 19/11. Fica: qua 18 e qui 19/11."; quem a ficha das 19:30 levou não tem diferença. (b) Em qualquer tique dentro da janela, a mudança na hora (_agenda_equipe_mudanca_na_hora) das ações de ontem e hoje que tiraram alguém de um dia que já teve ficha, pela decisão do dono ou pelo replano da falta de outra pessoa. O modo é o do previsto (_agenda_fala_modo); desligado = {pulado}; ninguém com telefone = {pulado: sem_telefone} na 1ª leitura; fora da janela = {pulado: janela}. {modo, as_19h, na_hora}. Volatile, invoker, sem grant.';

-- §5.5, R8.5-18, AG7-23: o dia novo de quem não tem o dia declarado (_agenda_tecnico_declarado não cobre: o Alex, prestador declarado pelo dono, nunca é convidado),
-- marcado a menos de equipe_convite_antecedencia_h do início da manhã do dia, em que a pessoa não tinha alocação vigente antes, sem ficha nem convite do dia: UM convite
-- por pessoa e dia, com o prazo do SIM (_agenda_equipe_convite_prazo). Prazo já passado não convida: vai ao dono como exceção (a ação equipe convite_sem_prazo, com
-- acorde), uma vez. Fora da janela ou no teto do dia, espera o próximo tique (o prazo é a saída). Laço pelos dias (_agenda_contatos_com_plano recebe 1 dia).
create or replace function public._agenda_comunicar_convites(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_local  timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_fala   text;
  v_modo   text;
  v_meq    text := public._agenda_modo_da_equipe();
  v_dono   uuid := public._agenda_dono(null);
  v_jan    text;
  v_ate    date;
  v_d      date;
  v_p      uuid;
  v_desde  timestamptz;
  v_alocs  uuid[];
  v_os     uuid[];
  v_prazo  timestamptz;
  v_nome   text;
  v_f      jsonb;
  v_partes text;
  v_txt    text;
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora do convite da equipe.' using errcode = '22023';
  end if;
  v_fala := public._agenda_fala_modo('convite');
  if v_fala = 'desligado' or cf.modo_equipe = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado');
  end if;
  if not exists (select 1 from public.agenda_equipe_contato c join public.payees p on p.id = c.payee_id
                  where c.recebe_rotina and c.parou_em is null and p.active and public._agenda_equipe_tem_telefone(p.id)) then
    return jsonb_build_object('pulado', true, 'motivo', 'sem_telefone');
  end if;
  v_modo := case when cf.modo_equipe = 'ligado' and v_fala = 'ligado' then 'ligado' else 'sombra' end;
  v_jan := public._agenda_equipe_fora_da_janela('convite', p_agora, p_agora);
  v_ate := ((p_agora + make_interval(hours => cf.equipe_convite_antecedencia_h)) at time zone 'America/Sao_Paulo')::date;
  for v_d in select g::date from generate_series(p_hoje, v_ate, interval '1 day') g order by 1 loop
    for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
      continue when v_p = v_dono;
      continue when public._agenda_tecnico_declarado(v_p, v_d);
      continue when not public._agenda_equipe_tem_telefone(v_p);
      select min(a.criado_em), array_agg(a.id order by a.id), array_agg(distinct a.service_order_id)
        into v_desde, v_alocs, v_os
        from public.agenda_alocacoes a
       where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
      continue when ((v_d + cf.manha_inicio) at time zone 'America/Sao_Paulo') - v_desde >= make_interval(hours => cf.equipe_convite_antecedencia_h);
      -- a pessoa já tinha o dia antes da ação que o criou (a troca dentro do mesmo dia não é dia novo)
      continue when exists (select 1 from public.agenda_alocacoes b
                             where b.payee_id = v_p and b.dia = v_d and b.tipo <> 'reserva' and b.criado_em < v_desde
                               and (b.cancelada_em is null or b.cancelada_em >= v_desde));
      -- sem ficha do dia (tem ficha = não recusada; também a que foi no "como foi") e sem convite do dia
      continue when exists (select 1 from public.agenda_equipe_mensagens m
                             where m.payee_id = v_p and m.modo = v_meq and m.estado <> 'recusada'
                               and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)));
      continue when exists (select 1 from public.agenda_equipe_mensagens m
                             where m.payee_id = v_p and m.tipo = 'convite' and m.dia = v_d and m.modo = v_modo);
      v_nome := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_p);
      v_prazo := public._agenda_equipe_convite_prazo(v_d);
      if v_prazo <= p_agora then
        -- o prazo já passou: não convida (nasceria vencido); o dono fica sabendo na hora, uma vez (em teste, só a conta)
        if v_modo = 'ligado'
           and not exists (select 1 from public.agenda_acoes e
                            where e.tipo = 'equipe' and e.payee_id = v_p and e.depois ->> 'motivo' = 'convite_sem_prazo' and e.depois ->> 'dia' = v_d::text) then
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
          values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_os[1], v_os, v_p,
                  jsonb_build_object('motivo', 'convite_sem_prazo', 'dia', v_d, 'alocacoes', to_jsonb(v_alocs), 'prazo', v_prazo,
                                     'acorde', v_d <= public.agenda_somar_du(p_hoje, cf.congelamento_du)),
                  left(format('O %s foi marcado para %s em cima da hora, e já passou a hora de pedir o SIM dele (%s às %s): fale com ele.',
                              v_nome, public._dia_curto(v_d), public._dia_curto((v_prazo at time zone 'America/Sao_Paulo')::date),
                              to_char(v_prazo at time zone 'America/Sao_Paulo', 'HH24:MI')), 400));
        end if;
        v_cont := v_cont || jsonb_build_object('sem_prazo', coalesce((v_cont ->> 'sem_prazo')::int, 0) + 1);
        continue;
      end if;
      if v_jan is not null then
        v_cont := v_cont || jsonb_build_object('espera_janela', coalesce((v_cont ->> 'espera_janela')::int, 0) + 1);
        continue;
      end if;
      if v_modo = 'ligado' and public._agenda_equipe_no_dia(v_p, v_local::date, false, null) >= cf.equipe_proativas_dia_max then
        v_cont := v_cont || jsonb_build_object('espera_teto', coalesce((v_cont ->> 'espera_teto')::int, 0) + 1);
        continue;
      end if;
      v_f := public.agenda_equipe_ficha(v_p, v_d, p_hoje);
      v_partes := rtrim(regexp_replace(coalesce(v_f ->> 'texto_curto', ''), '^[^:]*: ', ''), '.');
      v_txt := format('%s, apareceu serviço para %s: %s. Pode vir? Responde SIM ou NÃO até %s às %s.', v_nome, public._dia_curto(v_d), v_partes,
                      public._dia_curto((v_prazo at time zone 'America/Sao_Paulo')::date), to_char(v_prazo at time zone 'America/Sao_Paulo', 'HH24:MI'));
      if char_length(v_txt) > 600 then
        v_txt := format('%s, apareceu serviço para %s: %s. Pode vir? Responde SIM ou NÃO até %s às %s.', v_nome, public._dia_curto(v_d),
                        split_part(v_partes, '. ', 1), public._dia_curto((v_prazo at time zone 'America/Sao_Paulo')::date),
                        to_char(v_prazo at time zone 'America/Sao_Paulo', 'HH24:MI'));
      end if;
      v_r := public._agenda_equipe_registrar(v_p, v_d, 'convite', v_txt, p_agora, null, null, array[v_d], v_alocs);
      v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'), coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
    end loop;
  end loop;
  return jsonb_build_object('modo', v_modo, 'por_estado', v_cont);
end;
$function$;

comment on function public._agenda_comunicar_convites(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P5; §5.5, §6.4, R8.5-18, AG7-23 "Sim, só vira dia dele com o sim"): o passo convites da rodada comunicar. Para cada pessoa da rotina com telefone, que não é o dono nem o técnico declarado (_agenda_tecnico_declarado: o Alex nunca), com dia novo marcado a menos de equipe_convite_antecedencia_h do início da manhã dele (sem alocação vigente antes), sem ficha nem convite do dia: "Roberto, apareceu serviço para sex 13/11: 8h no motorhome do Lenine, com o Gustavo. Pode vir? Responde SIM ou NÃO até qui 12/11 às 19:30." (chave agenda-equipe:convite:<pessoa>:<dia>, dias = {dia}, alocacao_ids). Prazo já passado: não convida, e a ação equipe convite_sem_prazo (com acorde) diz ao dono, uma vez. Fora da janela ou no teto, espera. O modo é o do convite (_agenda_fala_modo); desligado = {pulado}; ninguém com telefone = {pulado: sem_telefone} na 1ª leitura. {modo, por_estado}. Volatile, invoker, sem grant.';

-- §5.5, AG7-23: o convite ligado, na fila e sem resposta, com o prazo passado: o caminho do "não vou" da Fase 3 com o dia do convite — indisponível no dia (origem
-- diarista, nota "Não respondeu ao convite"), o replano da falta, a ação equipe com motivo sem_sim e acorde (é exceção, §3.1 item 4); a mensagem fica sem_resposta; quem
-- o replano tirou de um dia com ficha recebe a mudança na hora. Só com o convite ligado de verdade (com o freio, conta e não mexe: o gestor só propõe).
create or replace function public._agenda_comunicar_convites_vencidos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       record;
  v_fala  text;
  v_nome  text;
  v_os    uuid[];
  v_cli   text;
  v_disp  uuid;
  v_rep   jsonb;
  v_acao  uuid;
  v_x     uuid;
  v_n     int := 0;
  v_teria int := 0;
  v_estado text;
  v_msg   text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora dos convites vencidos.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.agenda_equipe_mensagens x where x.tipo = 'convite' and x.modo = 'ligado' and x.estado = 'enfileirada') then
    return jsonb_build_object('vencidos', 0);
  end if;
  v_fala := public._agenda_fala_modo('convite');
  for m in
    select x.* from public.agenda_equipe_mensagens x
     where x.tipo = 'convite' and x.modo = 'ligado' and x.estado = 'enfileirada' and public._agenda_equipe_convite_prazo(x.dia) <= p_agora
     order by x.dia, x.payee_id, x.id
       for update
  loop
    if v_fala <> 'ligado' or cf.modo_equipe <> 'ligado' then
      v_teria := v_teria + 1;
      continue;
    end if;
    perform set_config('agenda.hoje', p_hoje::text, true);
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = m.payee_id and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    v_cli := public._agenda_lista(array(select coalesce(public._agenda_nome_curto(cl.name), 'serviço')
                                          from unnest(v_os) u(os) join public.service_orders so on so.id = u.os
                                          left join public.clients cl on cl.id = so.client_id
                                         order by 1), null);
    v_disp := null;
    v_rep := null;
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = m.payee_id and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> m.dia) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
      values (m.payee_id, daterange(m.dia, m.dia, '[]'), 'indisponivel', 'diarista', 'Não respondeu ao convite', p_agora)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        perform set_config('agenda.replano_da_falta', 'on', true);
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', p_hoje, p_agora, null);
        perform set_config('agenda.replano_da_falta', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.replano_da_falta', '', true);
        perform public.log_app_error('db', 'agenda: replanejar depois do convite sem SIM falhou: ' || v_msg, 'agenda',
                                     'equipe:replanejar', 'error',
                                     jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado, 'payee', m.payee_id));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_os[1], v_os, m.payee_id,
            jsonb_build_object('motivo', 'sem_sim', 'dia', m.dia, 'disponibilidade', v_disp, 'mensagem', m.id,
                               'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb),
                               'acorde', m.dia <= public.agenda_somar_du(p_hoje, cf.congelamento_du)),
            left(format('O %s não respondeu ao convite de %s: tirei ele %s.', v_nome, public._dia_curto(m.dia),
                        case when cardinality(v_os) > 0 then 'do ' || v_cli else 'do dia' end)
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400))
    returning id into v_acao;
    update public.agenda_equipe_mensagens set estado = 'sem_resposta', acao_id = v_acao where id = m.id;
    for v_x in select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(v_rep -> 'acoes', '[]'::jsonb)) x loop
      perform public._agenda_equipe_mudanca_na_hora(v_x, p_hoje, p_agora);
    end loop;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('vencidos', v_n) || case when v_teria > 0 then jsonb_build_object('teria', v_teria) else '{}'::jsonb end;
end;
$function$;

comment on function public._agenda_comunicar_convites_vencidos(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P5; §5.5, §3.2, AG7-23): o passo convites_vencidos da rodada comunicar. A 1ª leitura são os convites ligados na fila sem resposta (nenhum = {vencidos: 0}). Com o prazo passado (_agenda_equipe_convite_prazo) e o convite ligado de verdade: o caminho do "não vou" com o dia do convite — indisponível no dia (diarista, "Não respondeu ao convite"), o replano da falta (agenda.replano_da_falta), a ação equipe com depois.motivo = sem_sim e acorde ("O Roberto não respondeu ao convite de sex 13/11: tirei ele do Lenine." e o replano), a mensagem sem_resposta, e a mudança na hora de quem o replano tirou de um dia com ficha. Com o freio (o convite em teste), {teria} e nada muda. {vencidos, teria}. Volatile, invoker, sem grant.';

comment on column public.agenda_equipe_mensagens.alocacao_ids is
  'Agenda de Produção (Fase 7f, AG7-23): convite: as alocações que o SIM confirma. Fase 7f (P5): mudança na hora: as alocações da pessoa que a ação tirou daquele dia (é o que a distingue da mudança das 19:30, que fica nula).';

-- ── 10. Portas ──────────────────────────────────────────────────────────────────────────────────────
-- As novas: sem grant, menos as que uma função com grant chama sendo invoker (o "Já avisei" no texto do acorde, que tem authenticated e service_role; o previsto
-- sozinho na conta da 7b, que tem o service_role) e _agenda_dias_do_plano_da_pessoa (só o service_role, §5.5). O registro é função nova (drop + create): o revoke é
-- obrigatório aqui. As outras recriadas: as portas de antes, repetidas para a migration valer sozinha.
revoke all on function public._agenda_dias_avisados(uuid, date, date, text),
                       public._agenda_dias_do_plano_da_pessoa(uuid, date, date, date),
                       public._agenda_equipe_convite_prazo(date),
                       public._agenda_equipe_ja_avisei(uuid, date, uuid),
                       public._agenda_equipe_semana_da_pessoa(uuid, date, timestamptz, text),
                       public._agenda_equipe_previsto_sozinho(uuid, date),
                       public._agenda_equipe_mudanca_na_hora(uuid, date, timestamptz),
                       public._agenda_comunicar_previsto(date, timestamptz),
                       public._agenda_comunicar_mudancas_equipe(date, timestamptz),
                       public._agenda_comunicar_convites(date, timestamptz),
                       public._agenda_comunicar_convites_vencidos(date, timestamptz),
                       public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text, date[], uuid[], text),
                       public._agenda_rotina_sem_resposta(date, timestamptz),
                       public._agenda_rotina_como_foi(date, timestamptz),
                       public._agenda_rotina_ficha(date, timestamptz),
                       public._agenda_rotina_acordes_da_equipe(date, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public._agenda_dias_do_plano_da_pessoa(uuid, date, date, date),
                          public._agenda_equipe_previsto_sozinho(uuid, date)
  to service_role;
grant execute on function public._agenda_equipe_ja_avisei(uuid, date, uuid) to authenticated, service_role;
revoke all on function public._agenda_equipe_previstas_hoje(uuid, date, timestamptz),
                       public.agenda_resposta_da_equipe(text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public._agenda_equipe_previstas_hoje(uuid, date, timestamptz),
                          public.agenda_resposta_da_equipe(text, text, text, timestamptz)
  to service_role;
revoke all on function public._agenda_texto_do_acorde(uuid, date, date) from public, anon;
grant execute on function public._agenda_texto_do_acorde(uuid, date, date) to authenticated, service_role;
