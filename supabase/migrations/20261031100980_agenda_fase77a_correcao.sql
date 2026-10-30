-- Agenda de Produção, Fase 7a ("ele marca sozinho"): a CORREÇÃO DOS ACHADOS DA REVISÃO DA ETAPA (30/10/2026).
-- (5 funções novas; 23 recriadas da definição mais nova; o comentário de modo_compre_ate; o job agenda-gestor reagendado nos minutos
-- ímpares; nenhuma tabela, coluna, lista ou dado muda)
--
-- NÃO APLICADA. Depende de 20261031100000 a 20261031100950 (as 13 da 7a); vai antes do dado 20261031100990 (os modos em sombra).
--
-- ═══ POR QUE ═══ (a revisão da 7a, pela lente do dono: uma semana de produção simulada na bancada, sem resposta do dono)
--   O gestor marcava o 1º tique e parava: as perguntas com prazo nunca chegavam ao dono (a vaga do fechamento ia para outra
--   linha, e o aviso não as contava como vistas), então o "sem resposta, marco como disse" nunca valia; a ficha do 1º dia de cada
--   serviço ficava segurada pela mesma disputa; a compra de hoje não chegava ao dono; a dupla dita cortava metade dos dias; o
--   *desfaz* do dono era refeito às 16:52; o teto de 8 diárias só adiava um dia a duração absurda; a peça embutida segurava 7 dos
--   9 orçamentos grandes; e a vigia ficava 4 vezes mais lenta com o gestor ligado.
--
-- ═══ O QUE MUDA (o número é o do achado da revisão) ═══
--   1. O aviso conta as ações novas do gestor: reparar, reestimar, estimar e a ficha segurada (_agenda_aviso_mudancas); o texto
--      não repete o "*desfaz*" que a ação já diz (_agenda_mudanca_texto).
--   2/11/22. A OS que a própria agenda pôs em "aguardando peças" ao tirá-la do plano pelo material não é "começada": volta à
--      reserva com o "de quem e quando?", sem a pergunta "o serviço já começou?" (_agenda_os_situacao).
--   3. O foco *agenda gestor*: o "Como eu conto" sempre entra e nenhum título fica sem linha (_agenda_ver_gestor,
--      _agenda_gestor_juntar).
--   4. A chamada semanal da equipe não cita quem só tem a diária cadastrada (o Mickael) (_agenda_gestor_equipe).
--   5. O "se aprovar" conta com 1 pessoa (equipe_padrao, a regra uma_pessoa) e diz quando pergunta antes (_agenda_gestor_orcamentos,
--      agenda_encaixe_do_novo).
--   6. O aviso diz "falta saber se já começou" / "falta saber quantos dias", não "outro motivo" (_agenda_aviso_fora_texto).
--   8. O comentário de modo_compre_ate diz o que o passo faz em teste (só o diário).
--   10. A vigia com o gestor ligado: a situação da OS não lê ações nem perguntas (a memória da vigia volta à marca de sempre), e a
--       duração de cada OS é lembrada na rodada (_agenda_rodada_marca, _agenda_os_situacao, os_duracao_sugerida).
--   12. O job agenda-gestor nos minutos 7, 23, 37 e 53 (fora dos minutos pares dos comprovantes).
--   13. O prazo das perguntas só trava o plano quando vai aplicar alguma (_agenda_gestor_vetos).
--   14. Em teste, a linha "eu marcaria assim" fica abaixo de toda linha de verdade do fechamento (perda 25).
--   15/18. As perguntas do gestor que esperam o dono (a ficha de hoje, situacao, estimativa, reestimar) vão numa linha só do
--       fechamento, que perde hoje (75) e conta todas como vistas (pergunta_ids); cada linha que perde hoje tem a sua vaga, até 3;
--       o aviso conta como vistas as do gestor das OS que ele cobre (_agenda_linhas_do_fechamento, agenda_textos_do_fechamento,
--       agenda_fechamento_registrar, agenda_aviso_pecas; o Secretário passa pergunta_ids e aceita 3 vagas).
--   16. A sobra e a falta contra a estimativa em pessoa-meio-dia: a dupla dita não corta os dias (_agenda_gestor_corte,
--       _agenda_gestor_revisao, _agenda_gestor_pessoa_meios).
--   17. O *desfaz* do dono vale até a OS mudar: a revisão e o encaixe não a marcam de novo (_agenda_gestor_desfeito).
--   19. A compra de hoje (ou vencida que ainda chega) vai como decisão no fechamento (perda 80).
--   20. Acima de 8 diárias o gestor não marca sozinho: a pergunta sai sem prazo e sem opção padrão (o grande, o "já começou" de um
--       serviço grande, o parado) (_agenda_gestor_perguntas_da_os; os textos em _agenda_os_situacao e os_prontidao).
--   21. A peça embutida não segura a OS: a estimativa conta tudo como mão de obra e vale (_agenda_gestor_estimativa).
--   23. O *livre*, com a regra teto_equipe, não conta o dono como técnico e respeita o teto da equipe-semana
--       (agenda_livre_de_verdade).
--   24. A suposição sem pergunta não vira linha vazia no aviso (_agenda_aprontar_de); a duração que o gestor pergunta trava a
--       prontidão (a OS não é "pronta para começar" enquanto ele espera).
--   (7 — o eval S80 — e 9 — a medida do aceite com a equipe de 30/10 — estão nos evals e nos testes, não aqui.)
--
-- As funções nascidas na 7a (e as do lote de 30/10 que só a 7a usa) são corrigidas no lugar, com as linhas marcadas "(7a correção";
-- as de antes da 7a só ganham blocos "-- FASE 7: (7a correção … -- FASE 7: fim" (ou linhas marcadas dentro de um bloco da 7a que já
-- existia): sem os blocos da Fase 7, o corpo de antes da 7a, byte a byte. Prova: supabase/tests/agenda_fase77a_correcao.sql.
--
-- APLICAR (só com o OK nomeado do dono, junto das outras da 7a, depois de 20261031100950 e antes de 20261031100990):
--   npx supabase db query --linked -f supabase/migrations/20261031100980_agenda_fase77a_correcao.sql
--
-- DESFAZER: recriar cada função com o corpo da origem (o arquivo dito antes de cada uma); apagar as 5 novas
-- (_agenda_gestor_desfeito, _agenda_gestor_juntar, _agenda_gestor_pessoa_meios, _agenda_rodada_duracao_lembrar,
-- _agenda_rodada_duracao_guardar) depois; e o job: select cron.alter_job((select jobid from cron.job where jobname =
-- 'agenda-gestor'), schedule := '7,22,37,52 10-23 * * 1-6');
--
-- IDEMPOTENTE: create or replace function, comment, revoke/grant e o job desagendado e agendado de novo pelo nome.


-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- (achado 17, o vaivém do *desfaz*) A OS cuja última marcação do gestor (ou da vigia, ou do motor) o dono desfez, e nada de
-- novo aconteceu nela desde então: a revisão diária e o encaixe na aprovação não a marcam de novo. "Nada de novo" são os sinais
-- do encaixe na aprovação (P8): a conversão, a assinatura, a troca de status para aberta, aprovada ou agendada, o planejamento
-- ou o material mudados pelo dono, pelo fornecedor, pela nota ou pelo Pix — depois do *desfaz* e fora dos 5 minutos dele (o
-- próprio *desfaz* volta o status e o planejamento na mesma hora). Uma ação de plano da OS que ainda vale, feita depois do
-- *desfaz* (o dono, o cliente ou o motor a marcaram de novo), também desfaz a trava. Lê agenda_acoes: nunca é chamada pela
-- conta da prontidão (a memória da vigia).
create or replace function public._agenda_gestor_desfeito(p_os uuid, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  with u as (
    select max(d.criada_em) as em
      from public.agenda_acoes a
      join public.agenda_acoes d on d.id = a.desfeita_pela
     where (a.service_order_id = p_os or p_os = any (a.os_ids))
       and a.executada and a.origem in ('motor', 'vigia')
       and a.tipo in ('publicar', 'criar', 'mover', 'promover_reserva', 'reparar', 'reestimar', 'estimar')
       and d.origem not in ('motor', 'vigia') and d.criada_em <= p_agora
  )
  select coalesce(
           u.em is not null
           and not exists (select 1 from public.agenda_acoes a
                            where (a.service_order_id = p_os or p_os = any (a.os_ids)) and a.executada and a.desfeita_em is null
                              and a.tipo in ('publicar', 'criar', 'mover', 'promover_reserva', 'reparar', 'reestimar', 'estimar', 'fixar')
                              and a.criada_em > u.em and a.criada_em <= p_agora)
           and not exists (select 1 from public.service_orders so
                            where so.id = p_os
                              and ((so.converted_to_os_at > u.em + interval '5 minutes' and so.converted_to_os_at <= p_agora)
                                   or (so.signed_at > u.em + interval '5 minutes' and so.signed_at <= p_agora)))
           and not exists (select 1 from public.ai_lifecycle_events e
                            where e.entity_id = p_os and e.event_type = 'status_change'
                              and e.new_value in ('open', 'approved', 'scheduled')
                              and e.created_at > u.em + interval '5 minutes' and e.created_at <= p_agora)
           and not exists (select 1 from public.os_planejamento pl
                            where pl.service_order_id = p_os and pl.atualizado_em > u.em + interval '5 minutes'
                              and pl.atualizado_em <= p_agora)
           and not exists (select 1 from public.os_material m
                            where m.service_order_id = p_os and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix')
                              and m.atualizado_em > u.em and m.atualizado_em <= p_agora),
           false)
    from u;
$function$;

comment on function public._agenda_gestor_desfeito(uuid, timestamptz) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 17): true quando a última marcação automática da OS (publicar, criar, mover, promover_reserva, reparar, reestimar ou estimar da vigia ou do motor) foi desfeita por quem não é o motor (o *desfaz* do dono) e nada de novo aconteceu nela depois — nenhuma ação de plano que ainda valha, nem a conversão, a assinatura, o status aberta/aprovada/agendada, o planejamento (fora dos 5 minutos do *desfaz*, que volta o status e o planejamento na hora) ou o material do dono, do fornecedor, da nota ou do Pix. A revisão diária e o encaixe na aprovação do gestor pulam essa OS: o *desfaz* do dono vale até a OS mudar. STABLE, invoker, sem grant (os passos do gestor a leem).';

-- (achado 3) Junta as linhas de um foco como _agenda_juntar, mas a última linha (p_fim: o "Como eu conto") sempre entra e o
-- corte nunca termina num título de seção (a linha que termina em ":"): o título sem nenhuma linha embaixo sai junto.
create or replace function public._agenda_gestor_juntar(p_linhas text[], p_max integer, p_fim text)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v   text[] := array(select x from unnest(coalesce(p_linhas, '{}'::text[])) with ordinality u(x, o)
                       where nullif(btrim(x), '') is not null order by o);
  n   int := cardinality(v);
  k   int;
  v_f text := nullif(btrim(coalesce(p_fim, '')), '');
  v_t text;
begin
  if v_f is null then
    return public._agenda_juntar(p_linhas, p_max);
  end if;
  if n = 0 then
    return v_f;
  end if;
  v_t := array_to_string(v, E'\n') || E'\n' || v_f;
  if p_max is null or char_length(v_t) <= p_max then
    return v_t;
  end if;
  for k in reverse n - 1 .. 1 loop
    continue when right(v[k], 1) = ':';
    v_t := array_to_string(v[1:k], E'\n') || E'\n'
           || format('(e mais %s %s)', n - k, case when n - k = 1 then 'linha' else 'linhas' end) || E'\n' || v_f;
    if char_length(v_t) <= p_max then
      return v_t;
    end if;
  end loop;
  return v_f;
end;
$function$;

comment on function public._agenda_gestor_juntar(text[], integer, text) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 3): junta as linhas de um foco até p_max caracteres como _agenda_juntar ("(e mais N linhas)"), mas p_fim (o "Como eu conto" do foco gestor) entra sempre, no fim, e o corte nunca termina num título de seção (a linha terminada em ":", como "Se aprovar:"): título sem linha embaixo não sai. Sem p_fim, é _agenda_juntar. IMMUTABLE.';

-- (achado 10) A memória da duração na rodada da vigia: os_duracao_sugerida de cada OS calculada uma vez e lembrada enquanto a
-- transação não grava nada no que ela lê (a marca de _agenda_rodada_marca, a mesma da prontidão) e o portão do gestor
-- (agenda.gestor) é o mesmo. Só com a rodada aberta (agenda.rodada) e só com as regras do gestor na duração: com o portão
-- falso, a duração é barata e a conta de sempre.
create or replace function public._agenda_rodada_duracao_lembrar(p_chave text)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  e jsonb := nullif(current_setting('agenda.rodada_dur', true), '')::jsonb -> p_chave;
begin
  if e is null or (e ->> 'm')::bigint is distinct from public._agenda_rodada_marca() then
    return null;
  end if;
  perform public._agenda_rodada_contar('duracao_lembradas');
  return e -> 'v';
end;
$function$;

comment on function public._agenda_rodada_duracao_lembrar(text) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 10): a duração (os_duracao_sugerida) lembrada na rodada da vigia pela chave <OS>:<agenda.gestor>, se a marca das escritas da transação é a mesma de quando foi calculada; senão null.';

create or replace function public._agenda_rodada_duracao_guardar(p_chave text, p_marca bigint, p_valor jsonb)
 returns void
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
begin
  perform set_config('agenda.rodada_dur',
                     (coalesce(nullif(current_setting('agenda.rodada_dur', true), '')::jsonb, '{}'::jsonb)
                      || jsonb_build_object(p_chave, jsonb_build_object('m', p_marca, 'v', p_valor)))::text, true);
  perform public._agenda_rodada_contar('duracao_calculadas');
end;
$function$;

comment on function public._agenda_rodada_duracao_guardar(text, bigint, jsonb) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 10): guarda na memória da rodada a duração da OS (chave <OS>:<agenda.gestor>) com a marca de quando a conta começou.';

-- (achado 16) Quanto a estimativa pede e quanto o plano tem da OS em pessoa-meio-dia (não em meio-dia de calendário): pede =
-- os meios-dias da estimativa (agenda_meios_da_os.total) × as pessoas dela (a sugestão; com a equipe dita, as de cada turno, com
-- o dono quando fica o turno); tem = os meios-dias de turno de cada pessoa no plano vigente (fora a reserva; o passado pelo
-- resultado: cumprido ou sem registro 1, parcial meio, não cumprido 0; o futuro 1). Com a dupla dita depois de marcar (2 pessoas
-- × 3 dias), um plano de 1 pessoa × 6 dias tem o mesmo que pede: nada a cortar nem a acrescentar.
create or replace function public._agenda_gestor_pessoa_meios(p_os uuid, p_hoje date, p_meios jsonb)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with p as (
    select coalesce((p_meios ->> 'pessoas_sugeridas')::int,
                    greatest(coalesce((p_meios #>> '{por_turno,manha,desejado}')::int, 0)
                             + case when coalesce((p_meios #>> '{dono_turno,manha}')::boolean, false) then 1 else 0 end, 1)) as pessoas
  )
  select jsonb_build_object(
           'pessoas', p.pessoas,
           'precisa', case when (p_meios ->> 'total') is null then null else (p_meios ->> 'total')::int * p.pessoas end,
           'tem', (select trim_scale(coalesce(sum(case when a.resultado in ('cumprido', 'sem_registro') then 1
                                                     when a.resultado = 'parcial' then 0.5
                                                     when a.resultado = 'nao_cumprido' then 0
                                                     else 1 end), 0))
                     from public.agenda_alocacoes a
                    where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.presenca = 'turno'))
    from p;
$function$;

comment on function public._agenda_gestor_pessoa_meios(uuid, date, jsonb) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 16): {pessoas, precisa, tem} da OS em pessoa-meio-dia — precisa = agenda_meios_da_os.total × as pessoas da estimativa (pessoas_sugeridas; com a equipe dita, as da manhã, com o dono quando fica o turno); tem = os meios-dias de turno de cada pessoa no plano vigente, fora a reserva (cumprido e sem registro 1, parcial meio, não cumprido 0, o resto 1). A revisão diária e o corte do gestor comparam por aqui: a dupla dita depois de marcar não vira corte. STABLE, invoker, sem grant.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7: (7a correção") ──────────────
-- Fora dos blocos nenhuma linha muda (o Z9 de supabase/tests/agenda_fase77a_correcao.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration.

-- _agenda_os_situacao (de 20261031100100_agenda_fase7a_duracao.sql)
create or replace function public._agenda_os_situacao(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  so       record;
  v_tipo   text;
  v_rastro boolean;
  v_desde  date;
  v_diaria date;
  v_ult    timestamptz;
  v_prop   numeric;
  v_sug    jsonb;
  v_est    numeric;
  v_pid    uuid;
  v_txt    text;
  v_curto  text;
  v_nada   constant jsonb := jsonb_build_object('pendente', false);
  -- (7a correção, achado 20) a estimativa inteira passa do teto de diárias: o gestor não tem o que fazer sozinho
  v_semp   boolean := false;
begin
  if p_hoje is null then
    raise exception '_agenda_os_situacao: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_os is null or not public._agenda_gestor_regra('situacao') then
    return v_nada;
  end if;
  select o.id, o.status, o.check_in_at, o.converted_to_os_at, o.signed_at, o.updated_at
    into so from public.service_orders o where o.id = p_os;
  if not found then
    return v_nada;
  end if;
  if exists (select 1 from public.os_planejamento pl where pl.service_order_id = p_os and pl.dias is not null)
     or exists (select 1 from public.agenda_alocacoes a
                 where a.service_order_id = p_os and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')) then
    return v_nada;
  end if;
  cf := public._agenda_cfg();

  select min(v.primeiro_dia) into v_diaria
    from public.v_dias_por_os_e_pessoa v
   where v.service_order_id = p_os and v.dias > 0 and v.primeiro_dia <= p_hoje;
  v_rastro := so.check_in_at is not null or so.status = 'in_progress' or v_diaria is not null;
  -- (7a correção, achados 2, 11 e 22) a OS que a própria agenda pôs em aguardando peças ao tirá-la do plano pelo material
  -- (agenda_aplicar: sem dia, com o cancelamento pelo material) não é "começada": sem check-in nem diária ligada e com a última
  -- retirada do plano (as alocações canceladas juntas por último, fora a reserva) feita pelo material — alguma delas com o motivo
  -- material: a remarcação cancela as violadas pelo material e as outras como replanejadas, no mesmo instante —, ela não pende:
  -- volta à reserva pelo material, com o "de quem e quando?" (spec §3.2, Compra). O "aguardando peças" posto pelo dono (Nelson,
  -- Flávio: NOVO-agenda-50) continua perguntando.
  if so.status = 'awaiting_parts' and not v_rastro
     and exists (select 1 from public.agenda_alocacoes a
                  where a.service_order_id = p_os and a.tipo <> 'reserva' and a.estado = 'cancelada' and a.cancelada_motivo = 'material'
                    and a.cancelada_em = (select max(b.cancelada_em) from public.agenda_alocacoes b
                                           where b.service_order_id = p_os and b.tipo <> 'reserva' and b.estado = 'cancelada')) then
    return v_nada;
  end if;

  if so.check_in_at is not null or so.status in ('in_progress', 'awaiting_parts') then
    v_tipo := 'comecada';
    -- desde quando: o check-in ou a 1ª diária ligada; sem eles, o dia em que a OS entrou no status de agora (senão a
    -- última atualização)
    v_desde := least((so.check_in_at at time zone 'America/Sao_Paulo')::date, v_diaria);
    if v_desde is null then
      select (max(e.created_at) at time zone 'America/Sao_Paulo')::date into v_desde
        from public.ai_lifecycle_events e
       where e.entity_id = p_os and e.event_type = 'status_change' and e.new_value = so.status;
      v_desde := coalesce(v_desde, (so.updated_at at time zone 'America/Sao_Paulo')::date);
    end if;
  elsif so.status in ('open', 'approved', 'scheduled') then
    v_ult := greatest(so.converted_to_os_at, so.signed_at, so.updated_at,
                      (select max(e.created_at) from public.ai_lifecycle_events e where e.entity_id = p_os),
                      -- (7a correção, achado 10) a última mexida da agenda na OS pelas alocações (criar, mover, cancelar, promover,
                      -- soltar), não pelas ações: a conta da prontidão não lê agenda_acoes, e a memória da vigia volta à marca de sempre
                      (select max(greatest(a.criado_em, a.cancelada_em)) from public.agenda_alocacoes a where a.service_order_id = p_os));
    if v_ult is null or (v_ult at time zone 'America/Sao_Paulo')::date >= p_hoje - cf.situacao_dias then
      return v_nada;
    end if;
    v_tipo := 'parada';
    v_desde := (v_ult at time zone 'America/Sao_Paulo')::date;
  else
    return v_nada;
  end if;

  -- a estimativa inteira (com as regras da duração); o "quanto falta" nunca passa dela
  v_sug := public.os_duracao_sugerida(p_os);
  v_est := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null else (v_sug ->> 'dias_realista')::numeric end;
  if v_tipo = 'comecada' and v_rastro then
    v_prop := least(cf.quanto_falta_dias, coalesce(v_est, cf.quanto_falta_dias));
  else
    v_prop := coalesce(v_est, cf.sem_mo_dias);
  end if;
  -- (7a correção, achado 10) a pergunta aberta da OS não é lida aqui: a conta da prontidão (que chama esta função pela
  -- estimativa) não lê as perguntas nem as ações da agenda, e a memória da vigia volta à marca de sempre
  v_semp := coalesce((v_sug ->> 'dp_realista')::numeric > cf.estimativa_max_diarias, false);

  v_curto := case when v_tipo = 'parada' then 'parado desde ' || to_char(v_desde, 'DD/MM') else 'já começou?' end;
  v_txt := case
    -- (7a correção, achado 20) acima de estimativa_max_diarias o gestor não marca sozinho: espera o dono
    when v_semp and v_tipo = 'parada' then
      format('falta você dizer se ainda é para fazer o serviço inteiro (parado desde %s); pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você',
             to_char(v_desde, 'DD/MM'), public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(cf.estimativa_max_diarias))
    when v_semp and v_rastro then
      format('falta você dizer quanto falta (começou em %s); pelo orçamento o serviço inteiro dá %s diárias, mais de %s: não marco sozinho, espero você',
             to_char(v_desde, 'DD/MM'), public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(cf.estimativa_max_diarias))
    when v_semp then
      format('falta você dizer se o serviço já começou (está como "%s", sem check-in nem diária ligada); pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você',
             public._agenda_status_texto(so.status), public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(cf.estimativa_max_diarias))
    when v_tipo = 'parada' then
      format('falta você dizer se ainda é para fazer o serviço inteiro (parado desde %s); sem resposta, conto o serviço inteiro (%s, estimativa minha)',
             to_char(v_desde, 'DD/MM'), public._agenda_dias(v_prop))
    when v_rastro then
      format('falta você dizer quanto falta (começou em %s); sem resposta, marco %s para terminar',
             to_char(v_desde, 'DD/MM'), public._agenda_dias(v_prop))
    else
      format('falta você dizer se o serviço já começou (está como "%s", sem check-in nem diária ligada); sem resposta, conto o serviço inteiro (%s, estimativa minha)',
             public._agenda_status_texto(so.status), public._agenda_dias(v_prop))
  end;
  return jsonb_build_object('pendente', true, 'tipo', v_tipo, 'rastro', v_rastro, 'desde', v_desde,
                            'proposta_dias', trim_scale(v_prop), 'sem_padrao', v_semp, 'status', so.status,
                            'curto', v_curto, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_os_situacao(uuid, date) is
  'Agenda de Produção (Fase 7a, P2; AG7-11): a OS que começou ou parou, antes de o gestor contar a estimativa cheia. Só com o portão situacao, sem os_planejamento.dias e sem alocação de compromisso vigente. comecada = check-in ou status in_progress/awaiting_parts; parada = open/approved/scheduled sem atividade (conversão, assinatura, updated_at, ai_lifecycle_events, agenda_acoes) há mais de situacao_dias. rastro = check-in, in_progress ou diária ligada. proposta_dias = quanto_falta_dias com rastro (nunca mais que a estimativa inteira), senão os dias da estimativa (sem base: sem_mo_dias). {pendente, tipo, rastro, desde, proposta_dias, pergunta_id (a pergunta situacao aberta), status, curto (a linha curta do "eu perguntaria"), texto (a restrição ao dono)}; senão {pendente: false}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa): (achados 2, 11 e 22) a OS em aguardando peças sem check-in nem diária ligada cuja última alocação cancelada (fora a reserva) saiu pelo material — a própria agenda (agenda_aplicar) a pôs em aguardando peças ao tirá-la do plano — não é "começada": não pende (volta à reserva pelo material, com o "de quem e quando?", spec §3.2); (achado 10) a parada conta a última mexida da agenda pelas alocações e pelo planejamento, não por agenda_acoes, e a saída não traz mais pergunta_id: a conta da prontidão não lê agenda_acoes nem agenda_perguntas, e a memória da vigia volta à marca de sempre; (achado 20) com a estimativa inteira acima de estimativa_max_diarias (sem_padrao), o texto diz que o gestor não marca sozinho e espera o dono.';

-- _agenda_gestor_estimativa (de 20261031100100_agenda_fase7a_duracao.sql)
create or replace function public._agenda_gestor_estimativa(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_dito numeric;
  v_sug  jsonb;
  v_sit  jsonb;
  v_emb  jsonb;
  v_dias numeric;
  v_pes  int;
  v_base jsonb;
begin
  if p_hoje is null then
    raise exception '_agenda_gestor_estimativa: sem o dia de hoje' using errcode = '22004';
  end if;
  select pl.dias into v_dito from public.os_planejamento pl where pl.service_order_id = p_os;
  if v_dito is not null then
    return jsonb_build_object('usa', false, 'motivo', 'dito');
  end if;
  if not public._agenda_gestor_regra('estimativa') then
    return jsonb_build_object('usa', false, 'motivo', 'regra_desligada');
  end if;
  cf := public._agenda_cfg();
  v_sug := public.os_duracao_sugerida(p_os);
  if not coalesce((v_sug ->> 'ok')::boolean, false) then
    return jsonb_build_object('usa', false, 'motivo', 'sem_os', 'texto', v_sug ->> 'texto');
  end if;
  v_dias := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null else (v_sug ->> 'dias_realista')::numeric end;
  v_pes := (v_sug ->> 'pessoas')::int;
  v_emb := public._agenda_peca_embutida(p_os);
  v_base := jsonb_build_object('usa', false, 'dias', trim_scale(v_dias), 'dp', (v_sug ->> 'dp_realista')::numeric,
                               'pessoas', v_pes, 'alerta_dupla', v_sug -> 'alerta_dupla', 'embutida', v_emb,
                               'proposta_dias', null);

  v_sit := public._agenda_os_situacao(p_os, p_hoje);
  if coalesce((v_sit ->> 'pendente')::boolean, false) then
    return v_base || jsonb_build_object('motivo', 'situacao', 'proposta_dias', v_sit -> 'proposta_dias',
                                        'texto', v_sit ->> 'curto', 'situacao', v_sit);
  end if;
  if v_dias is null then
    return v_base || jsonb_build_object('motivo', 'sem_base', 'proposta_dias', trim_scale(cf.sem_mo_dias),
                                        'texto', 'não tem mão de obra separada');
  end if;
  if (v_sug ->> 'dp_realista')::numeric > cf.estimativa_max_diarias then
    return v_base || jsonb_build_object('motivo', 'grande', 'proposta_dias', trim_scale(v_dias),
                                        'texto', public._agenda_num((v_sug ->> 'diarias_realista')::numeric) || ' diárias pela estimativa');
  end if;
  -- (7a correção, achado 21) a peça embutida não é motivo de perguntar antes: contar tudo como mão de obra é a conta mais longa e
  -- é o que a pergunta faria sem resposta — o gestor marca (D7-1) e a suposição fica dita na prontidão ("Contei que não; se
  -- tiver, me diga") e aqui (embutida_suposta). Antes, 7 dos 9 orçamentos grandes reais ficavam fora esperando a resposta.
  if jsonb_array_length(v_emb) > 0 and public._agenda_gestor_regra('embutida_suposta') then
    v_base := v_base || jsonb_build_object('embutida_suposta', true);
  end if;
  return v_base || jsonb_build_object('usa', true, 'motivo', null,
    'texto', case when coalesce((v_sug ->> 'diagnostico')::boolean, false) then v_sug ->> 'texto'
                  else public._agenda_dias(v_dias)
                       || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
                       || ' (estimativa minha, pelo valor do orçamento)' end);
end;
$function$;

comment on function public._agenda_gestor_estimativa(uuid, date) is
  'Agenda de Produção (Fase 7a, P2; D7-1, AG7-11): a estimativa do orçamento que o gestor usa como dias firmes, ou o motivo de perguntar antes — dito (os_planejamento.dias), regra_desligada (portão estimativa), situacao (_agenda_os_situacao pendente), sem_base (proposta sem_mo_dias), grande (dp_realista > estimativa_max_diarias), embutida (_agenda_peca_embutida com o portão embutida_suposta); senão usa (o dias_realista de os_duracao_sugerida). {usa, motivo, dias, dp, pessoas, texto, proposta_dias, alerta_dupla, embutida} (+ situacao). Nada é gravado: é leitura (agenda_meios_da_os, a prontidão e as perguntas do gestor leem daqui). STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa; achado 21): a peça embutida não é mais motivo de perguntar antes (embutida): a estimativa conta tudo como mão de obra (a conta mais longa, o que a pergunta faria sem resposta) e vale (usa), com embutida_suposta true; a suposição fica dita na prontidão ("Contei que não; se tiver, me diga"). D7-1: o gestor marca e o dono corrige depois.';

-- _agenda_gestor_perguntas_da_os (de 20261031100300_agenda_fase7a_perguntas.sql)
create or replace function public._agenda_gestor_perguntas_da_os(p_os uuid, p_hoje date, p_agora timestamptz, p_seco boolean)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_seco  boolean := coalesce(p_seco, false);
  v_base  jsonb;
  v_modo  text;
  v_cl    jsonb;
  v_est   jsonb;
  v_sit   jsonb;
  v_sug   jsonb;
  v_mot   text;
  v_var   text;
  v_tipo  text;
  v_chave text;
  v_prop  numeric;
  v_dias  text;
  v_veto  timestamptz;
  v_ate   text;
  v_rot   text;
  v_lin   text;
  v_perg  text;
  v_feito text;
  v_ops   jsonb;
  v_rec   smallint := 1;
  v_txt   text;
  v_nova  boolean;
  v_id    uuid;
  -- (7a correção, achado 20) acima do teto de diárias: sem prazo e sem o que fazer sozinho
  v_semp  boolean := false;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_perguntas_da_os: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  v_base := jsonb_build_object('os', p_os, 'perguntou', false);
  if not v_seco then
    v_modo := public._agenda_gestor_modo('marcar');
    if v_modo = 'desligado' then
      return v_base || jsonb_build_object('por', 'desligado');
    end if;
  end if;
  v_cl := public._agenda_classe_agora(p_os, p_hoje) - 'pront';
  if coalesce((v_cl ->> 'classe')::int, 0) <> 4 or coalesce(v_cl ->> 'motivo', '') not in ('situacao', 'estimativa', 'material') then
    return v_base || jsonb_build_object('por', 'nada_a_perguntar', 'classe', v_cl -> 'classe', 'classe_motivo', v_cl -> 'motivo');
  end if;
  v_est := public._agenda_gestor_estimativa(p_os, p_hoje);
  v_mot := v_est ->> 'motivo';
  if coalesce(v_mot, '') not in ('situacao', 'grande', 'embutida', 'sem_base') then
    return v_base || jsonb_build_object('por', 'nada_a_perguntar', 'classe', v_cl -> 'classe', 'classe_motivo', v_cl -> 'motivo',
                                        'estimativa', v_mot);
  end if;

  cf := public._agenda_cfg();
  v_prop := (v_est ->> 'proposta_dias')::numeric;
  v_dias := public._agenda_dias(v_prop);
  v_veto := public._agenda_veto_ate(p_agora);
  v_ate := public._dia_curto((v_veto at time zone 'America/Sao_Paulo')::date) || ' às '
           || to_char(v_veto at time zone 'America/Sao_Paulo', 'HH24:MI');
  v_rot := public._agenda_rotulo_da_os(p_os);
  -- (7a correção, achado 20) a estimativa inteira passa de estimativa_max_diarias (Giancarlo 10 diárias, Kalmar 18,3): o gestor
  -- não tem o que fazer sozinho — nem "marco os dias inteiros", nem "1 dia para terminar" um serviço de 18 diárias. A pergunta
  -- sai sem prazo e sem opção padrão: o dono decide (a recomendação é "eu digo").
  v_semp := coalesce((v_est ->> 'dp')::numeric > cf.estimativa_max_diarias, false);
  if v_semp then
    v_veto := null;
  end if;

  if v_mot = 'situacao' then
    v_tipo := 'situacao';
    v_sit := v_est -> 'situacao';
    v_var := case when v_sit ->> 'tipo' = 'parada' then 'parada'
                  when coalesce((v_sit ->> 'rastro')::boolean, false) then 'rastro'
                  else 'comecada' end;
    if v_var = 'parada' then
      v_perg := format('%s está parado desde %s: ainda é para fazer o serviço inteiro? Se você não me disser nada até %s, conto o serviço inteiro (%s, estimativa minha).',
                       v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), v_ate, v_dias);
      v_feito := format('contei o serviço inteiro, %s (estimativa minha)', v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Sim, inteiro', 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo o que falta', 'efeito', jsonb_build_object('dizer', true)),
        jsonb_build_object('n', 3, 'texto', 'Não é mais para fazer', 'efeito', jsonb_build_object('nao_fazer', true)));
    elsif v_var = 'rastro' then
      v_perg := format('%s já começou em %s: quanto falta? Se você não me disser nada até %s, marco %s para terminar.',
                       v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), v_ate, v_dias);
      v_feito := format('contei %s para terminar (estimativa minha)', v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', upper(left(v_dias, 1)) || substr(v_dias, 2),
                           'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo quanto falta', 'efeito', jsonb_build_object('dizer', true)),
        jsonb_build_object('n', 3, 'texto', 'Já terminou', 'efeito', jsonb_build_object('terminou', true)));
    else
      v_perg := format('%s está como ''%s'': o serviço já começou? Se você não me disser nada até %s, conto o serviço inteiro (%s, estimativa minha).',
                       v_rot, public._agenda_status_texto(v_sit ->> 'status'), v_ate, v_dias);
      v_feito := format('contei o serviço inteiro, %s (estimativa minha)', v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Não começou: conte tudo', 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Já começou: eu digo quanto falta', 'efeito', jsonb_build_object('dizer', true)),
        jsonb_build_object('n', 3, 'texto', 'Já terminou', 'efeito', jsonb_build_object('terminou', true)));
    end if;
  else
    v_tipo := 'estimativa';
    v_var := v_mot;
    v_feito := format('contei %s (estimativa minha)', v_dias);
    if v_mot = 'grande' then
      v_sug := public.os_duracao_sugerida(p_os);
      v_perg := format('%s: pelo valor do orçamento são %s diárias (%s com %s). É mais de %s diárias, então pergunto antes. Se você não me disser nada até %s, marco assim.',
                       v_rot, public._agenda_num((v_sug ->> 'diarias_realista')::numeric), v_dias,
                       case when coalesce((v_est ->> 'pessoas')::int, 1) = 1 then '1 pessoa' else (v_est ->> 'pessoas') || ' pessoas' end,
                       public._agenda_num(cf.estimativa_max_diarias), v_ate);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Marque ' || v_dias, 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo os dias', 'efeito', jsonb_build_object('dizer', true)));
    elsif v_mot = 'embutida' then
      -- o nome do serviço da linha (antes do " — ", " – ", ":" ou "("), como o dono escreveu
      v_lin := public._agenda_corta(btrim(regexp_replace(coalesce(v_est #>> '{embutida,0,nome}', ''), '( — | – |:|\().*$', '')), 60);
      v_perg := format('%s: ''%s'' pode ter peça junto. Contei tudo como mão de obra: %s. Se você não me disser nada até %s, marco assim.',
                       v_rot, v_lin, v_dias, v_ate);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Marque ' || v_dias, 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo os dias e a peça', 'efeito', jsonb_build_object('dizer', true)));
    else
      v_perg := format('%s: o orçamento não tem mão de obra separada, então não sei quantos dias leva. Se você não me disser nada até %s, marco %s.',
                       v_rot, v_ate, v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Marque ' || v_dias, 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo os dias', 'efeito', jsonb_build_object('dizer', true)));
      v_rec := 2;
    end if;
  end if;
  -- (7a correção, achado 20) acima do teto: os textos sem o prazo, e a recomendação passa à 2 (o dono diz)
  if v_semp then
    v_rec := 2;
    v_perg := case
      when v_tipo = 'estimativa' then
        format('%s: pelo valor do orçamento são %s diárias (%s com %s). É mais de %s diárias: não marco sozinho. Me diga os dias.',
               v_rot, public._agenda_num((public.os_duracao_sugerida(p_os) ->> 'diarias_realista')::numeric), v_dias,
               case when coalesce((v_est ->> 'pessoas')::int, 1) = 1 then '1 pessoa' else (v_est ->> 'pessoas') || ' pessoas' end,
               public._agenda_num(cf.estimativa_max_diarias))
      when v_var = 'parada' then
        format('%s está parado desde %s: ainda é para fazer o serviço inteiro? Pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você.',
               v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), public._agenda_num((v_est ->> 'dp')::numeric),
               public._agenda_num(cf.estimativa_max_diarias))
      when v_var = 'rastro' then
        format('%s já começou em %s: quanto falta? Pelo orçamento o serviço inteiro dá %s diárias, mais de %s: não marco sozinho, espero você dizer quanto falta.',
               v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), public._agenda_num((v_est ->> 'dp')::numeric),
               public._agenda_num(cf.estimativa_max_diarias))
      else
        format('%s está como ''%s'': o serviço já começou? Pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você.',
               v_rot, public._agenda_status_texto(v_sit ->> 'status'), public._agenda_num((v_est ->> 'dp')::numeric),
               public._agenda_num(cf.estimativa_max_diarias)) end;
  end if;
  v_chave := v_tipo || ':' || p_os || ':' || v_var;
  select v_perg || ' '
         || string_agg(format('%s) %s%s', o ->> 'n', o ->> 'texto', case when (o ->> 'n')::int = v_rec then ' (recomendo)' else '' end),
                       '; ' order by (o ->> 'n')::int) || '.'
    into v_txt
    from jsonb_array_elements(v_ops) o;
  v_base := v_base || jsonb_build_object('tipo', v_tipo, 'chave', v_chave, 'motivo', v_mot, 'variante', v_var, 'texto', v_txt,
                                         'curto', v_est ->> 'texto', 'proposta_dias', trim_scale(v_prop), 'opcoes', v_ops,
                                         'recomendacao', v_rec, 'opcao_padrao', case when v_semp then null else 1 end,
                                         'veto_ate', v_veto);
  if v_seco then
    return v_base;
  end if;

  -- o motivo mudou: a pergunta de antes da mesma OS (outra chave) sai e a nova entra
  update public.agenda_perguntas q
     set estado = 'resolvida', resolvida_motivo = 'mudou o que falta saber: perguntei de novo'
   where q.estado = 'aberta' and q.modo = v_modo and q.service_order_id = p_os and q.tipo in ('situacao', 'estimativa')
     and q.chave <> v_chave;
  v_nova := not exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo and q.estado = 'aberta');
  -- (7a correção, achado 20) acima do teto, sem prazo e sem opção padrão: o dono decide
  v_id := public._agenda_gestor_perguntar(v_tipo, v_chave, p_os, v_txt, v_ops, v_rec, v_veto,
                                          case when v_semp then null else 1 end::smallint, v_modo, p_agora);
  if v_id is null then
    return v_base || jsonb_build_object('por', 'ja_perguntei', 'modo', v_modo);
  end if;
  return v_base || jsonb_build_object('perguntou', true, 'pergunta_id', v_id, 'nova', v_nova, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_gestor_perguntas_da_os(uuid, date, timestamptz, boolean) is
  'Agenda de Produção (Fase 7a, P4; AG7-11, AG7-15): a pergunta do gestor antes de marcar uma OS — só com a classe 4 (_agenda_classe_agora) de motivo situacao, estimativa ou material, e o motivo da _agenda_gestor_estimativa em situacao (começou sem rastro, com rastro, parada), grande, embutida ou sem_base. Os textos da spec §6.3 (o que o gestor faz sem resposta e até quando: _agenda_veto_ate), as opções [{n, texto, efeito: {dias, feito} | {dizer} | {terminou} | {nao_fazer}}], a recomendação (1; no sem_base, 2) e a opção que vale sem resposta (1). Chave <tipo>:<os>:<variante>. p_seco = só devolve {os, perguntou false, tipo, chave, motivo, variante, texto, curto, proposta_dias, opcoes, recomendacao, opcao_padrao, veto_ate}; senão grava pelo modo do gestor que marca (_agenda_gestor_perguntar; desligado = nada) e resolve a aberta da mesma OS de outro motivo. {perguntou, pergunta_id, nova, modo} ou {perguntou false, por: desligado | nada_a_perguntar | ja_perguntei}. Invoker, sem grant (os passos do gestor e a limpeza da vigia a chamam). CORREÇÃO DA 7a (revisão da etapa; achado 20): quando a estimativa inteira da OS passa de estimativa_max_diarias (Giancarlo 10 diárias, Kalmar 18,3), o gestor não tem o que fazer sozinho: a pergunta sai sem prazo (veto_ate nulo) e sem opção padrão, com a recomendação "eu digo" (2) e o texto "… mais de 8 diárias: não marco sozinho" — no grande, no já começou com rastro (o "1 dia para terminar" de um serviço de 18 diárias), no começou sem rastro e no parado. Abaixo do teto, a de antes. A embutida não pergunta mais (achado 21).';

-- _agenda_gestor_equipe (de 20261031100300_agenda_fase7a_perguntas.sql)
create or replace function public._agenda_gestor_equipe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  -- a régua da spec §5.4 ("sem diária em 30 dias"); o 7b traz o parâmetro dele (equipe_inativo_dias)
  c_sem_diaria_dias constant int := 30;
  cf        public.agenda_config;
  v_modo    text;
  v_dono    uuid := public._agenda_dono(null);
  v_seg     date;
  v_chave   text;
  v_hist    text[];
  v_dito    text[];
  v_outro   text[];
  v_semente boolean;
  v_sumidos text[];
  v_partes  text[] := '{}';
  v_txt     text;
  v_id      uuid;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_equipe: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('marcar');
  if v_modo = 'desligado' then
    return jsonb_build_object('criada', false, 'motivo', 'o gestor está desligado');
  end if;
  cf := public._agenda_cfg();
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano then
    return jsonb_build_object('criada', false, 'motivo', 'a chamada da equipe é no dia do plano');
  end if;
  -- a semana que a próxima publicação monta: depois da hora do plano, a seguinte à que acabou de sair
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1)
           + case when (p_agora at time zone 'America/Sao_Paulo')::time >= cf.hora_do_plano then 14 else 7 end;
  v_chave := 'equipe_cadastro:chamada:' || v_seg;
  if exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo) then
    return jsonb_build_object('criada', false, 'motivo', 'já perguntei desta semana', 'semana', v_seg);
  end if;

  -- quem conta na semana (a grade), por pessoa: os dias e de onde eles vêm
  with g as (
    select c.payee_id, c.pessoa, array_agg(distinct extract(isodow from c.dia)::smallint) as dias,
           array_agg(distinct coalesce(c.origem, '-')) as origens
      from public.agenda_capacidade(v_seg, v_seg + 5, p_hoje) c
     where not c.eh_dono and c.meios_esperados > 0
     group by c.payee_id, c.pessoa
  ), t as (
    select g.*, g.pessoa || ' (' || regexp_replace(public._agenda_dias_semana_texto(g.dias), '^de ', '') || ')' as item,
           case when 'dono' = any (g.origens) then 'dito' when g.origens = array['historico'] then 'hist' else 'outro' end as grupo
      from g
  )
  select array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'hist'),
         array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'dito'),
         array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'outro')
    into v_hist, v_dito, v_outro
    from t;
  v_semente := coalesce(cardinality(v_hist), 0) > 0 and coalesce(cardinality(v_dito), 0) = 0
               and coalesce(cardinality(v_outro), 0) = 0;

  -- (7a correção, achado 4) quem só tem a diária cadastrada não entra na chamada: work_profiles é do PAGAMENTO, não da
  -- agenda (a correção de 30/10), e o dono já disse quem saiu (o Mickael, toda quinta, "não vem desde 18/09"). Quem é da equipe
  -- é quem está na grade (agenda_capacidade); a chamada só nasce quando a semana seria montada só com a semente do histórico.
  v_sumidos := null;

  if not v_semente and coalesce(cardinality(v_sumidos), 0) = 0 then
    return jsonb_build_object('criada', false, 'motivo', 'a equipe está dita', 'semana', v_seg);
  end if;

  if coalesce(cardinality(v_dito), 0) > 0 then
    v_partes := v_partes || (public._agenda_lista(v_dito, null) || ', como você disse');
  end if;
  if coalesce(cardinality(v_outro), 0) > 0 then
    v_partes := v_partes || public._agenda_lista(v_outro, null);
  end if;
  if coalesce(cardinality(v_hist), 0) > 0 then
    v_partes := v_partes || (public._agenda_lista(v_hist, null)
                             || case when cardinality(v_hist) = 1 then ', pelo que veio' else ', pelo que vieram' end
                             || format(' nas últimas %s semanas', cf.medicao_semanas));
  end if;
  v_txt := format('Para marcar a semana de %s ', to_char(v_seg, 'DD/MM'))
           || case when cardinality(v_partes) = 0 then 'não conto com ninguém da equipe.'
                   else 'eu conto com ' || array_to_string(v_partes, ', e com ') || '.' end
           || coalesce(' ' || array_to_string(v_sumidos, ' '), '')
           || ' Se a equipe mudou, me diga quem vem e em que dias.';
  v_id := public._agenda_gestor_perguntar('equipe_cadastro', v_chave, null, v_txt, '[]'::jsonb, null, null, null, v_modo, p_agora);
  return jsonb_build_object('criada', v_id is not null, 'pergunta_id', v_id, 'semana', v_seg, 'semente', v_semente,
                            'sumidos', coalesce(cardinality(v_sumidos), 0), 'modo', v_modo, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_gestor_equipe(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4; AG7-03): a chamada semanal da equipe — no dia_do_plano, a pergunta equipe_cadastro (chave equipe_cadastro:chamada:<segunda da semana que a próxima publicação monta>, sem prazo nem opções, pelo modo do gestor que marca; desligado = nada) quando essa semana seria montada só com a semente do histórico (agenda_capacidade: todo meio-dia esperado de origem historico) ou há alguém com a diária cadastrada vigente que nunca esteve na agenda e não tem diária há 30 dias. O texto: "Para marcar a semana de 09/11 eu conto com Roberto (seg a sex) e João (ter a sex), pelo que vieram nas últimas 8 semanas. Mickael tem cadastro de diarista mas não vem desde 18/09: não conto com ele. Se a equipe mudou, me diga quem vem e em que dias." (com a equipe declarada pelo dono: "Alex (seg a sex), como você disse"). {criada, pergunta_id, semana, semente, sumidos, modo, texto}. Invoker, sem grant. O 7b recria ESTA função ({pulado} com o modo_cadastro dele). CORREÇÃO DA 7a (revisão da etapa; achado 4): a chamada não fala mais de quem só tem a diária cadastrada (work_profiles é do pagamento, não da agenda — a correção de 30/10): o "Mickael tem cadastro de diarista mas não vem desde 18/09" sai, e a pergunta só nasce quando a semana seria montada só com a semente do histórico.';

-- _agenda_gestor_vetos (de 20261031100300_agenda_fase7a_perguntas.sql)
create or replace function public._agenda_gestor_vetos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_tipos constant text[] := array['situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado',
                                   'bem_livre', 'compre_ate', 'sinal'];
  r        record;
  v_d      jsonb;
  v_apl    int := 0;
  v_resp   int := 0;
  v_sem    int := 0;
  v_teste  int := 0;
  v_cond   int := 0;
  v_erros  int := 0;
  v_os     jsonb := '[]'::jsonb;
  v_acoes  jsonb := '[]'::jsonb;
  v_estado text;
  v_msg    text;
  v_trava  boolean := false;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_vetos: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- (7a correção, achado 13) as travas só antes da 1ª pergunta que o prazo vai aplicar (antes: em todo tique, até o fim da
  -- rodada, mesmo sem nada a aplicar, segurando o *grava* e o *desfaz* do dono)
  for r in select q.id, q.tipo, q.chave, q.service_order_id, q.opcao_padrao, q.opcao_escolhida, q.mostrada_vezes, q.mostrada_em,
                  q.veto_ate
             from public.agenda_perguntas q
            where q.estado = 'aberta' and q.modo = 'ligado' and q.veto_ate is not null and q.veto_ate < p_agora
              and q.opcao_padrao is not null and not q.critica and q.tipo = any (c_tipos)
            order by q.veto_ate, q.criada_em, q.id loop
    if r.opcao_escolhida is not null then
      v_resp := v_resp + 1;
      continue;
    end if;
    if not coalesce(r.mostrada_vezes > 0 and r.mostrada_em < r.veto_ate, false) then
      v_sem := v_sem + 1;
      continue;
    end if;
    if coalesce(public._agenda_modo_da_pergunta(r.tipo, r.chave), 'desligado') <> 'ligado' then
      v_teste := v_teste + 1;
      continue;
    end if;
    -- (7a correção, achado 13) a mesma ordem de antes (agenda_plano, depois agenda_vetos), na 1ª que aplica;
    -- _agenda_gestor_decidir trava de novo e confere a pergunta
    if not v_trava then
      perform pg_advisory_xact_lock(hashtext('agenda_plano'));
      perform pg_advisory_xact_lock(hashtext('agenda_vetos'));
      v_trava := true;
    end if;
    begin
      v_d := public._agenda_gestor_decidir(r.id, r.opcao_padrao, null, 'prazo', null, p_hoje, p_agora);
      if coalesce((v_d ->> 'ok')::boolean, false) then
        v_apl := v_apl + 1;
        if r.service_order_id is not null then
          v_os := v_os || to_jsonb(r.service_order_id);
        end if;
        if v_d ? 'acao_id' then
          v_acoes := v_acoes || jsonb_build_array(v_d -> 'acao_id');
        end if;
      else
        v_cond := v_cond + 1;
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      perform public.log_app_error('db', format('gestor da agenda, prazo da pergunta %s: %s', r.tipo, v_msg), 'agenda',
                                   'gestor:vetos', 'error',
                                   jsonb_build_object('pergunta', r.id, 'tipo', r.tipo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
    end;
  end loop;
  return jsonb_build_object('aplicadas', v_apl, 'os', v_os, 'acoes', v_acoes, 'respondidas', v_resp, 'sem_mostrar', v_sem,
                            'em_teste', v_teste, 'sem_condicao', v_cond, 'erros', v_erros);
end;
$function$;

comment on function public._agenda_gestor_vetos(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4; AG7-15): o prazo das perguntas do gestor — a aberta, modo ligado, não crítica, de um dos 10 tipos do gestor, com opcao_padrao e veto_ate < p_agora, sem resposta (opcao_escolhida nula), mostrada ao dono antes do prazo (mostrada_vezes > 0 e mostrada_em < veto_ate) e com o modo de quem a fez ligado (_agenda_modo_da_pergunta): aplica a opcao_padrao por _agenda_gestor_decidir(…, p_via prazo), cada uma no seu bloco (erro → app_error_logs gestor:vetos, e segue). A não mostrada fica aberta (sem_mostrar). Trava agenda_plano e agenda_vetos (idempotente entre a rodada do gestor e, no 7f, a comunicar, que recria ESTA função). {aplicadas, os, acoes, respondidas, sem_mostrar, em_teste, sem_condicao, erros}. Invoker, sem grant. CORREÇÃO DA 7a (revisão da etapa; achado 13): as travas agenda_plano e agenda_vetos só são pegas antes da 1ª pergunta que o prazo vai aplicar (a mesma ordem; _agenda_gestor_decidir trava de novo e confere a pergunta): o tique sem nada a aplicar não trava o *grava* e o *desfaz* do dono pela rodada inteira.';

-- _agenda_aviso_mudancas (de 20261030100300_agenda_correcao_aviso.sql)
create or replace function public._agenda_aviso_mudancas(p_hoje date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with g as (
    select x.g, x.o,
           array(select y::uuid from jsonb_array_elements_text(coalesce(x.g -> 'acao_ids', '[]'::jsonb)) y) as ids
      from jsonb_array_elements(public._agenda_mudancas(p_hoje - 6, p_hoje, true, true, null)) with ordinality x(g, o)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'grupo', g.g ->> 'grupo', 'tipo', g.g ->> 'tipo',
           'texto', public._agenda_mudanca_texto(g.g, false),
           'acao_ids', to_jsonb(g.ids),
           'os', (select coalesce(jsonb_agg(distinct a.service_order_id), '[]'::jsonb) from public.agenda_acoes a
                   where a.id = any (g.ids) and a.service_order_id is not null),
           'propostas', (select coalesce(jsonb_agg(distinct a.proposta_id), '[]'::jsonb) from public.agenda_acoes a
                          where a.id = any (g.ids) and a.proposta_id is not null))
         order by g.o), '[]'::jsonb)
    from g
   where exists (select 1 from public.agenda_acoes a
                  where a.id = any (g.ids) and a.executada and a.origem in ('motor', 'vigia')
                    -- (7a correção, achado 1) e as ações do gestor: a troca de quem falta (reparar), o corte pela estimativa
                    -- (reestimar), os dias que o prazo gravou (estimar) e a ficha que ele segurou (equipe, ficha_segurada)
                    and (a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva',
                                    'reparar', 'reestimar', 'estimar')
                         or (a.tipo = 'equipe' and a.depois ->> 'motivo' = 'ficha_segurada')));
$function$;

comment on function public._agenda_aviso_mudancas(date) is
  'Agenda de Produção (correção de 29/10, P4): o que o aviso do gestor conta — os grupos de _agenda_mudancas(p_hoje − 6, p_hoje, executada, não contada) com ação de plano da vigia ou do motor (publicar, criar, mover, cancelar, promover_reserva, soltar_reserva). [{grupo, tipo, texto (_agenda_mudanca_texto), acao_ids, os, propostas}], na ordem do *o que mudou*. CORREÇÃO DA 7a (revisão da etapa; achado 1): também as ações do gestor da vigia ou do motor — reparar (a troca de quem falta), reestimar (o corte pela estimativa), estimar (os dias que o prazo gravou) e a equipe da ficha segurada (depois.motivo ficha_segurada): o dono fica sabendo no aviso, não só no fechamento.';

-- _agenda_mudanca_texto (de 20261029100950_agenda_fase6_correcao_textos.sql)
create or replace function public._agenda_mudanca_texto(p_g jsonb, p_sombra boolean default false)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_g ->> 'tipo' = 'publicacao' then
      case when p_sombra then 'Publicaria ' else 'Publiquei ' end
      || coalesce(regexp_replace(p.textos ->> 'titulo', '^Semana', 'a semana'), 'a semana')
      || ': ' || (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
      || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
              when coalesce((p_g ->> 'desfazivel')::boolean, false) then ' *desfaz semana* volta como estava.' else '' end
    else (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
         || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
                 when coalesce((p_g ->> 'desfazivel')::boolean, false)
                   then format(' *desfaz %s* volta como estava.', p_g ->> 'nome') else '' end end
    from (select 1) um
    left join public.agenda_propostas p on p.id = nullif(p_g ->> 'proposta_id', '')::uuid;
  -- CORREÇÃO FASE 6: (C2) regressão M1: o select de cima não vale mais (a função sql devolve o resultado do último); vale
  -- este, que é ele com uma mudança só: o grupo sem nome (a ação sem OS, como o que a agenda aprendeu sozinha) não ganha o
  -- "*desfaz %s* volta como estava." — com o nome nulo a frase saía "*desfaz * volta como estava." no fechamento das 17:30 e
  -- no foco mudanças. O texto dele já diz como voltar. Com nome, byte a byte o de cima.
  select case
    when p_g ->> 'tipo' = 'publicacao' then
      case when p_sombra then 'Publicaria ' else 'Publiquei ' end
      || coalesce(regexp_replace(p.textos ->> 'titulo', '^Semana', 'a semana'), 'a semana')
      || ': ' || (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
      || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
              when coalesce((p_g ->> 'desfazivel')::boolean, false) then ' *desfaz semana* volta como estava.' else '' end
    else (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
         || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
                 when coalesce((p_g ->> 'desfazivel')::boolean, false) and nullif(btrim(p_g ->> 'nome'), '') is not null
                   then format(' *desfaz %s* volta como estava.', p_g ->> 'nome') else '' end end
    from (select 1) um
    left join public.agenda_propostas p on p.id = nullif(p_g ->> 'proposta_id', '')::uuid;
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a correção, achado 1) o select de cima não vale mais; vale este, que é ele com uma mudança só: a ação cujo texto já
  -- diz como voltar (a frase do gestor "… *desfaz Nelson* volta.", o estimar dos dias que o prazo gravou) não ganha de novo o
  -- "*desfaz Nelson* volta como estava." — com as ações do gestor no aviso (achado 1), a frase saía duas vezes na mesma linha.
  -- Sem a frase no texto, byte a byte o de cima.
  select case
    when p_g ->> 'tipo' = 'publicacao' then
      case when p_sombra then 'Publicaria ' else 'Publiquei ' end
      || coalesce(regexp_replace(p.textos ->> 'titulo', '^Semana', 'a semana'), 'a semana')
      || ': ' || (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
      || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
              when coalesce((p_g ->> 'desfazivel')::boolean, false) then ' *desfaz semana* volta como estava.' else '' end
    else (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
         || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
                 when coalesce((p_g ->> 'desfazivel')::boolean, false) and nullif(btrim(p_g ->> 'nome'), '') is not null
                      and position(format('*desfaz %s* volta', p_g ->> 'nome')
                                   in coalesce((select string_agg(x, ' ') from jsonb_array_elements_text(p_g -> 'itens') x), '')) = 0
                   then format(' *desfaz %s* volta como estava.', p_g ->> 'nome') else '' end end
    from (select 1) um
    left join public.agenda_propostas p on p.id = nullif(p_g ->> 'proposta_id', '')::uuid;
  -- FASE 7: fim
$function$;

comment on function public._agenda_mudanca_texto(jsonb, boolean) is
  'Agenda de Produção (Fase 2, P5): a frase de um grupo de _agenda_mudancas — a publicação ("Publiquei a semana de 03 a 06/11 (seg 02 é Finados): … *desfaz semana* volta como estava."; na sombra "Publicaria …") ou a ação ("<frase> *desfaz Nelson* volta como estava."), com "(já desfeito)" quando foi desfeita. CORREÇÃO FASE 6 (C2, regressão M1): o grupo sem nome (a ação sem OS, como o aprendizado) não ganha o "*desfaz <nome>* volta como estava." (com o nome nulo saía "*desfaz * volta como estava."). CORREÇÃO DA 7a (revisão da etapa; achado 1): a ação cujo texto já diz como voltar (a frase do gestor "… *desfaz Nelson* volta.") não ganha de novo o "*desfaz Nelson* volta como estava." — com as ações do gestor no aviso, a frase saía duas vezes na mesma linha. Sem a frase no texto, a de antes, byte a byte.';

-- _agenda_aviso_fora_texto (de 20261030100300_agenda_correcao_aviso.sql)
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
  'Agenda de Produção (correção de 29/10, P4): a linha curta do que ficou de fora no aviso do gestor — "Ficaram de fora 10: Rodrigo OS-00096 (só com você); Vanderlei, Flávio, Nelson e Giancarlo (material); Kalmar OS-00032, Kalmar OS-00033 e Rodrigo OS-00076 (esperando o cliente); …" (o porquê numa palavra pelo motivo da proposta; o número quando o nome se repete; até 4 nomes por porquê). Sem as OS de p_sem nem as fora da carteira. Nada = null. CORREÇÃO DA 7a (revisão da etapa; achado 6): os motivos do gestor — situacao ("falta saber se já começou") e estimativa ("falta saber quantos dias") — não caem mais em "outro motivo".';

-- _agenda_ver_gestor (de 20261031100600_agenda_fase7a_rodada.sql)
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
                                    then format(' Pode precisar de dupla (%s): diga *%s com dupla*.',
                                                public._agenda_gestor_dupla_texto(x -> 'alerta_dupla'), x ->> 'cliente')
                                    else '' end);
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
                           coalesce((select format(' Pode precisar de dupla (%s): diga *%s com dupla*.',
                                                   public._agenda_gestor_dupla_texto(d.a), public._agenda_nome_curto(cl.name))
                                       from (select public.os_duracao_sugerida(r.os) -> 'alerta_dupla' as a) d,
                                            public.service_orders so join public.clients cl on cl.id = so.client_id
                                      where so.id = r.os and jsonb_typeof(d.a) = 'object'), ''));
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
        coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                    join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id), 'serviço'),
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
                                                 'grupo', public._agenda_gestor_motivo_texto(t.motivo)) order by t.numero), '[]'::jsonb)
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
  return jsonb_build_object('ok', true, 'texto', public._agenda_gestor_juntar(v_l, cf.texto_max + 1 + char_length(v_como), v_como),
                            'dados', jsonb_build_object('modo', v_ef, 'so_propor', cf.gestor_so_propor, 'conta_de', v_sdia,
                                                        'sombra', v_s, 'fora', v_fora));
end;
$function$;

comment on function public._agenda_ver_gestor(date) is
  'Agenda de Produção (Fase 7a, P7; spec §6.2): o foco gestor de agenda_ver — (1) o estado: "O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada." / "Eu marco sozinho desde ter 03/11 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz." / "Desde sex 06/11 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta." / desligado; (2) em teste, "Eu marcaria:" pela última conta do diário (agenda_gestor_dia.sombra), um por linha ("• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*."); ligado, "Marquei nos últimos 7 dias:" (as OS com compromisso vigente pela estimativa); (3) "Antes de marcar eu perguntaria:" (teste) ou "Perguntei antes de marcar:" com o prazo ("• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim."); (4) "Fora:" agrupado pelo porquê ("esperando o cliente: Kalmar (2) e Rodrigo; …"; ligado, pela última conta de verdade do motor em 8 dias); (5) "Compras da semana:" e (6) "Se aprovar:" pelo diário (agenda_gestor_dia.compras e .orcamentos, [{texto}], de até 3 dias; o P10 e o P12 gravam); (7) "Como eu conto:" com os parâmetros. {ok, texto (≤ texto_max), dados}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa; achado 3): o "Como eu conto" entra sempre, no fim (_agenda_gestor_juntar: o corte é no meio, nunca num título sem linha embaixo, como o "Se aprovar:" vazio); as compras da semana e o "Se aprovar" mostram até 3 cada (o resto: "(e mais 3 orçamentos)", "(e mais N em *agenda compras*)").';

-- _agenda_gestor_orcamentos (de 20261031100900_agenda_fase7a_sinal_sabado.sql)
create or replace function public._agenda_gestor_orcamentos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_modo  text;
  v_sim   boolean := false;
  v_pes   int;
  v_d     jsonb;
  v_e     jsonb;
  v_dp    numeric;
  v_dias  numeric;
  v_cabe  text;
  v_txt   text;
  v_lista jsonb := '[]'::jsonb;
  v_sem   int := 0;
  r       record;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_orcamentos: sem o dia ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modo := public._agenda_gestor_modo('marcar');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor está desligado');
  end if;
  -- em teste, a estimativa e o encaixe são os do gestor (a simulação da sombra); nada é gravado no plano em nenhum modo
  if v_modo = 'sombra' and coalesce(current_setting('agenda.gestor', true), '') <> 'sombra' then
    perform set_config('agenda.gestor', 'sombra', true);
    v_sim := true;
  end if;
  -- o encaixe de um serviço novo sem gente dita usa equipe_sugerida pessoas por turno (agenda_encaixe_do_novo): as diárias da
  -- estimativa são repartidas por elas
  v_pes := greatest(cf.equipe_sugerida, 1);
  -- (7a correção, achado 5) com a regra uma_pessoa (AG7-04), o serviço novo é marcado com equipe_padrao pessoas — como o gestor
  -- o marcaria depois de aprovado (e o encaixe do novo, recriado, usa o mesmo)
  if public._agenda_gestor_regra('uma_pessoa') then
    v_pes := greatest(cf.equipe_padrao, 1);
  end if;
  for r in
    select so.id, so.service_order_number as numero, so.grand_total as total,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
     where so.status = 'draft' and so.quote_status in ('draft', 'sent') and so.merged_into_id is null
       and so.grand_total >= cf.simular_orcamento_acima
       and (so.updated_at at time zone 'America/Sao_Paulo')::date >= p_hoje - cf.simular_orcamento_dias
     order by so.grand_total desc, so.service_order_number collate "C", so.id
  loop
    v_d := public.os_duracao_sugerida(r.id);
    if not coalesce((v_d ->> 'ok')::boolean, false) or coalesce((v_d ->> 'sem_base')::boolean, false)
       or coalesce((v_d ->> 'dp_realista')::numeric, 0) <= 0 then
      v_sem := v_sem + 1;
      continue;
    end if;
    v_dp := (v_d ->> 'dp_realista')::numeric;
    v_dias := greatest(0.5, round(v_dp / v_pes * 2) / 2);
    v_e := public.agenda_encaixe_do_novo(v_dias, '[]'::jsonb, null, p_hoje);
    v_cabe := case
      when coalesce((v_e ->> 'cabe')::boolean, false) and not coalesce((v_e ->> 'acima')::boolean, false)
        then 'cabe a partir de ' || public._dia_curto((v_e ->> 'de')::date)
      when coalesce((v_e ->> 'cabe')::boolean, false)
        then 'só acima da carga de sempre, a partir de ' || public._dia_curto((v_e ->> 'de')::date)
      when v_e ->> 'motivo' = 'sem_encaixe'
        then 'não cabe até ' || public._dia_curto((v_e ->> 'horizonte')::date) || ' com a equipe de agora'
      else 'não tenho com quem simular' end;
    v_txt := format('%s (%s, R$ %s): pela estimativa, %s com %s; %s.', r.cliente, r.numero,
                    replace(to_char(round(r.total), 'FM999,999,990'), ',', '.'), public._agenda_dias(v_dias),
                    case when v_pes = 1 then '1 pessoa' else v_pes || ' pessoas' end, v_cabe)
             -- (7a correção, achado 5) acima do teto de diárias, o gestor pergunta os dias antes de marcar
             || case when v_dp > cf.estimativa_max_diarias
                     then format(' Se aprovar, pergunto os dias antes (mais de %s diárias).', public._agenda_num(cf.estimativa_max_diarias))
                     else '' end;
    v_lista := v_lista || jsonb_build_object('os', r.id, 'numero', r.numero, 'cliente', r.cliente, 'total', r.total,
                                             'dias', v_dias, 'pessoas', v_pes, 'diarias', v_dp,
                                             'cabe', coalesce((v_e ->> 'cabe')::boolean, false),
                                             'acima', coalesce((v_e ->> 'acima')::boolean, false),
                                             'cabe_de', v_e -> 'de', 'texto', v_txt);
  end loop;
  if v_sim then
    perform set_config('agenda.gestor', '', true);
  end if;
  perform public._agenda_gestor_dia_gravar(p_hoje, 'orcamentos', v_lista, p_agora);
  return jsonb_build_object('modo', v_modo, 'simulacao', v_sim, 'orcamentos', jsonb_array_length(v_lista), 'sem_base', v_sem,
                            'lista', v_lista);
end;
$function$;

comment on function public._agenda_gestor_orcamentos(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P12; spec §3 (l), §5.12 e §6.2 "Se aprovar:"): o passo diário orcamentos da rodada do gestor — os orçamentos grandes ainda em aberto (status draft, quote_status draft ou sent, sem agrupar, grand_total >= simular_orcamento_acima, mexidos nos últimos simular_orcamento_dias) com a estimativa pelas regras do gestor (os_duracao_sugerida: dp_realista) e o encaixe de um serviço novo sobre a grade de agora (agenda_encaixe_do_novo(dias, sem gente, sem presença dita, p_hoje), o P2 do lote de 30/10; nada é gravado no plano nem ocupa ninguém). Sem gente dita, o encaixe põe equipe_sugerida pessoas por turno: os dias são as diárias da estimativa repartidas por elas (meio dia em meio dia). Grava agenda_gestor_dia.orcamentos = [{os, numero, cliente, total, dias, pessoas, diarias, cabe, acima, cabe_de, texto}], do maior para o menor — o foco *agenda gestor* mostra "Se aprovar:" com cada texto: "Everton (ORÇ-00117, R$ 120.020): pela estimativa, 27,5 dias com 2 pessoas; cabe a partir de ter 17/11." (ou "só acima da carga de sempre, a partir de …", ou "não cabe até … com a equipe de agora"). O orçamento sem mão de obra separada fica de fora (sem_base). Em teste, a conta é a da sombra (a variável agenda.gestor só dentro do passo). Desligado = {pulado}. {modo, simulacao, orcamentos, sem_base, lista}. Invoker, sem grant (só a rodada do gestor o chama). CORREÇÃO DA 7a (revisão da etapa; achado 5): com a regra uma_pessoa, as diárias da estimativa são repartidas por equipe_padrao (1: "55,5 dias com 1 pessoa"), como o gestor marcaria depois de aprovado, e o encaixe do novo usa o mesmo (agenda_encaixe_do_novo recriada); acima de estimativa_max_diarias, o texto diz que ele pergunta os dias antes.';

-- _agenda_gestor_corte (de 20261031100750_agenda_fase7a_revisao.sql)
create or replace function public._agenda_gestor_corte(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_cong  date;
  v_dono  uuid;
  v_m     jsonb;
  v_pront jsonb;
  v_numero text;
  v_total int;
  v_feito numeric;
  v_n     int;
  v_k     int := 0;
  v_cut   jsonb := '[]'::jsonb;
  v_meios jsonb := '[]'::jsonb;
  v_fe    boolean := false;
  v_ult   record;
  v_itens jsonb;
  v_partes text[];
  v_txt   text;
  v_base  jsonb;
  v_val   jsonb;
  r       record;
  -- (7a correção, achado 16) a conta em pessoa-meio-dia
  v_pm    jsonb;
  v_sobra numeric;
  v_kpm   numeric := 0;
  v_npm   int;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_corte: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  select so.service_order_number into v_numero from public.service_orders so where so.id = p_os;
  v_m := public.agenda_meios_da_os(p_os, p_hoje);
  v_total := (v_m ->> 'total')::int;
  v_feito := coalesce((v_m ->> 'cumpridos')::numeric, 0) + coalesce((v_m ->> 'vigentes')::numeric, 0);
  v_base := jsonb_build_object('os', p_os, 'numero', v_numero, 'fonte', v_m ->> 'fonte', 'total', v_total, 'feitos', v_feito,
                               'cortar', 0, 'cortados', '[]'::jsonb, 'itens', '[]'::jsonb, 'texto', null);
  if not coalesce((v_m ->> 'ok')::boolean, false) or v_total is null then
    return v_base || jsonb_build_object('motivo', 'sem_dias');
  end if;
  -- (7a correção, achado 16) a sobra em pessoa-meio-dia (_agenda_gestor_pessoa_meios), não em meio-dia de calendário: o plano
  -- de 1 pessoa × 6 dias que ganhou a dupla dita (2 pessoas × 3 dias) tem o que a estimativa pede, e nada sai. v_n é o teto de
  -- meios-dias de calendário (cada um tem ao menos uma pessoa); o laço para quando as pessoas do meio-dia não cabem na sobra.
  v_pm := public._agenda_gestor_pessoa_meios(p_os, p_hoje, v_m);
  v_sobra := coalesce((v_pm ->> 'tem')::numeric - (v_pm ->> 'precisa')::numeric, 0);
  v_n := floor(v_sobra)::int;
  if v_n < 1 then
    return v_base || jsonb_build_object('sobra', greatest(v_n, 0), 'motivo', 'nada_a_cortar');
  end if;
  cf := public._agenda_cfg();
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_dono := public._agenda_dono(null);

  -- do último meio-dia para trás: sai enquanto pode sair
  for r in
    select a.dia, a.turno,
           jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                        'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado,
                                        'fixado_por', a.fixado_por, 'tipo', a.tipo)
                     order by a.presenca <> 'turno', a.payee_id) as alocs,
           bool_and(a.estado = 'publicada') as pub,
           bool_or(public._agenda_dia_avisado(a.payee_id, a.service_order_id, a.dia) is not null) as avisado,
           min(lower(a.periodo)) as ini,
           bool_or(a.presenca = 'fechamento' and a.payee_id is not distinct from v_dono) as fecha,
           min(a.tipo) as tipo
      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and a.resultado is null
     group by a.dia, a.turno
     order by a.dia desc, a.turno = 'tarde' desc
  loop
    exit when v_k >= v_n;
    exit when not r.pub or r.avisado or r.dia <= v_cong or r.ini <= p_agora;
    -- (7a correção, achado 16) o meio-dia sai inteiro só se as pessoas de turno dele cabem na sobra em pessoa-meio-dia
    v_npm := (select count(*) from jsonb_array_elements(r.alocs) x where x ->> 'presenca' = 'turno')::int;
    exit when v_kpm + v_npm > v_sobra;
    v_kpm := v_kpm + v_npm;
    v_cut := v_cut || r.alocs;
    v_meios := v_meios || jsonb_build_object('dia', r.dia, 'turno', r.turno);
    v_fe := v_fe or r.fecha;
    v_k := v_k + 1;
  end loop;
  if v_k = 0 then
    return v_base || jsonb_build_object('sobra', v_n, 'ficou', v_n, 'motivo', 'nada_pode_sair');
  end if;
  v_pront := public.os_prontidao(p_os, p_hoje);
  v_itens := jsonb_build_array(jsonb_build_object(
    'op', 'cancelar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
    'tipo', (select min(x ->> 'tipo') from jsonb_array_elements(v_cut) x), 'motivo', 'reestimada', 'violada', false,
    'alocacoes', v_cut, 'de', (select min(x ->> 'dia') from jsonb_array_elements(v_cut) x),
    'ate', (select max(x ->> 'dia') from jsonb_array_elements(v_cut) x), 'critica', null, 'decisao', null, 'aplicado', false,
    'texto', null));
  -- o fechamento do dono que saiu volta no novo último meio-dia de compromisso
  if v_fe then
    select a.dia, a.turno into v_ult
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and a.resultado is null and a.presenca = 'turno'
       and not exists (select 1 from jsonb_array_elements(v_cut) x where (x ->> 'alocacao_id')::uuid = a.id)
     order by a.dia desc, a.turno = 'tarde' desc limit 1;
    if v_ult.dia is not null
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.dia = v_ult.dia
                          and a.turno = v_ult.turno and a.presenca = 'fechamento') then
      v_itens := v_itens || jsonb_build_object(
        'op', 'criar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
        'tipo', (select min(x ->> 'tipo') from jsonb_array_elements(v_cut) x), 'reserva_de', null,
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_dono,
                       'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_dono),
                       'dia', v_ult.dia, 'turno', v_ult.turno, 'presenca', 'fechamento')),
        'de', v_ult.dia, 'ate', v_ult.dia, 'fim_antes', null, 'fim_depois', v_ult.dia, 'atraso_du', null, 'condicao_tipo', null,
        'critica', null, 'pergunta_chave', null, 'decisao', null, 'espera', false, 'interrupcoes', 0, 'meios_do_dono', 0,
        'fonte', v_m ->> 'fonte', 'dias', v_m -> 'dias', 'evento_real', false, 'fixar_dono', false, 'aviso_material', null,
        'abre', false, 'fecha', true, 'motivos', jsonb_build_array('o fechamento vai para o novo último meio-dia'),
        'texto', null, 'aplicado', false);
    end if;
  end if;
  -- "Tirei sex 13/11" (o dia inteiro) ou "Tirei qui 12/11 à tarde" (um turno só)
  v_partes := array(select case when count(*) > 1 then public._dia_curto((x ->> 'dia')::date)
                                else public._agenda_meio_texto((x ->> 'dia')::date, min(x ->> 'turno')) end
                      from jsonb_array_elements(v_meios) x group by x ->> 'dia' order by x ->> 'dia');
  v_txt := format('%s: o orçamento mudou e agora estimo %s (eram %s). Tirei %s.', public._agenda_rotulo_da_os(p_os),
                  public._agenda_dias(v_total::numeric / 2), public._agenda_num(v_feito / 2), public._agenda_lista(v_partes));
  v_val := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', '{}'::jsonb), p_hoje, p_agora, false,
                                        jsonb_build_object(p_os::text, v_pront));
  if jsonb_array_length(v_val) > 0 then
    return v_base || jsonb_build_object('sobra', v_n, 'ficou', v_n, 'motivo', 'validacao', 'violacoes', v_val);
  end if;
  return v_base || jsonb_build_object('sobra', v_n, 'cortar', v_k, 'cortados', v_meios, 'ficou', v_n - v_k,
    'itens', (select jsonb_agg(i || jsonb_build_object('texto', v_txt) order by k) from jsonb_array_elements(v_itens) with ordinality t(i, k)),
    'texto', public._agenda_corta(v_txt, 400), 'motivo', null);
end;
$function$;

comment on function public._agenda_gestor_corte(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9 item 1 e §6.4): o corte do reestimar, a conta, sem gravar — com o plano (os meios-dias feitos + os de hoje em diante) maior que agenda_meios_da_os.total, os N últimos meios-dias de compromisso saem (N = a sobra inteira), do fim para trás, parando no 1º que não pode sair (o congelado, o que começou, o fixado, o dia já dito à equipe ou ao cliente: esses ficam com o dono); o fechamento do dono que sai volta no novo último meio-dia. Validado pelas 14 regras (_agenda_validar_itens). {os, numero, fonte, total, feitos, sobra, cortar, cortados [{dia, turno}], ficou, itens (cancelar motivo reestimada; criar do fechamento), texto ("Nelson (OS-00112): o orçamento mudou e agora estimo 3 dias (eram 4). Tirei sex 13/11."), motivo?}. STABLE, invoker, sem grant. CORREÇÃO DA 7a (revisão da etapa; achado 16): a sobra é contada em pessoa-meio-dia (_agenda_gestor_pessoa_meios: o que o plano tem — os meios-dias de turno de cada pessoa, os passados pelo resultado — contra o que a estimativa pede — meios-dias × as pessoas dela), não em meio-dia de calendário: *<nome> com dupla* num serviço marcado com 1 pessoa não corta mais metade dos dias (as diárias são as mesmas; a dupla vale para a próxima marcação); o meio-dia de calendário só sai se as pessoas dele cabem na sobra.';

-- _agenda_gestor_revisao (de 20261031100750_agenda_fase7a_revisao.sql)
create or replace function public._agenda_gestor_revisao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_modo   text;
  v_sim    boolean;
  r        record;
  v_m      jsonb;
  v_c      jsonb;
  v_q      jsonb;
  v_feito  numeric;
  v_falta  uuid[] := '{}';
  v_cand   uuid[] := '{}';
  v_cortes jsonb := '[]'::jsonb;
  v_faltas jsonb := '[]'::jsonb;
  v_pergs  jsonb := '[]'::jsonb;
  v_r      jsonb := '{}'::jsonb;
  v_p      jsonb := '{}'::jsonb;
  v_os     uuid;
  v_prim   date;
  v_res    text;
  v_mot    text;
  v_it     jsonb;
  v_por    jsonb := '[]'::jsonb;
  v_fora   jsonb := '{}'::jsonb;
  v_marc   int := 0;
  v_resv   int := 0;
  v_onda   boolean := false;
  v_som    jsonb;
  v_cl     int;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_revisao: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('revisao');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado', 'modo', v_modo);
  end if;
  if not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('pulado', true, 'motivo', 'não é dia útil', 'modo', v_modo);
  end if;
  v_sim := v_modo <> 'ligado';
  if v_sim then
    -- em teste: as regras do gestor valem só aqui dentro; nada é gravado (só o diário)
    perform set_config('agenda.gestor', 'sombra', true);
  end if;
  begin
    -- (1) reestimar e (3) reavaliar, OS por OS da carteira
    for r in select k.service_order_id as os, k.numero from public.os_carteira(p_hoje) k
              order by k.numero collate "C", k.service_order_id loop
      if public._agenda_os_tem_dia(r.os, p_hoje) then
        v_m := public.agenda_meios_da_os(r.os, p_hoje);
        if v_m ->> 'fonte' = 'orcamento' and (v_m ->> 'total') is not null then
          -- (7a correção, achado 16) o que falta e o que sobra em pessoa-meio-dia (_agenda_gestor_pessoa_meios): a dupla dita
          -- depois de marcar não vira corte (nem falta, quando sai). Com 1 pessoa, os mesmos números de antes.
          v_c := public._agenda_gestor_pessoa_meios(r.os, p_hoje, v_m);
          v_feito := (v_c ->> 'tem')::numeric;
          v_m := v_m || jsonb_build_object('total', (v_c ->> 'precisa')::numeric);
          if (v_m ->> 'total')::numeric > v_feito then
            v_falta := v_falta || r.os;
            v_faltas := v_faltas || jsonb_build_object('os', r.os, 'numero', r.numero, 'total', (v_m ->> 'total')::int,
                                                       'feitos', v_feito);
          elsif v_feito - (v_m ->> 'total')::numeric >= 1 then
            if v_sim then
              v_c := public._agenda_gestor_corte(r.os, p_hoje, p_agora);
              v_cortes := v_cortes || jsonb_build_object('os', r.os, 'numero', r.numero, 'total', (v_m ->> 'total')::int,
                                                         'feitos', v_feito, 'cortaria', v_c -> 'cortar', 'motivo', v_c -> 'motivo',
                                                         'texto', v_c -> 'texto');
            else
              v_c := public._agenda_gestor_reestimar(r.os, p_hoje, p_agora, null);
              v_cortes := v_cortes || jsonb_build_object('os', r.os, 'numero', r.numero, 'total', (v_m ->> 'total')::int,
                                                         'feitos', v_feito, 'reestimado', v_c -> 'reestimado',
                                                         'cortados', v_c -> 'cortados', 'motivo', v_c -> 'motivo',
                                                         'texto', v_c -> 'texto', 'acao_ids', v_c -> 'acao_ids');
            end if;
          end if;
        end if;
      end if;
      v_q := public._agenda_gestor_perguntas_da_revisao(r.os, p_hoje, p_agora, v_sim);
      if jsonb_typeof(v_q -> 'reestimar') = 'object' then
        v_pergs := v_pergs || jsonb_build_object('os', r.os, 'numero', r.numero, 'tipo', 'reestimar',
                                                 'chave', v_q #>> '{reestimar,chave}', 'texto', v_q #>> '{reestimar,texto}',
                                                 'pergunta_id', v_q #> '{reestimar,pergunta_id}');
      end if;
      if jsonb_typeof(v_q -> 'reavaliar') = 'object' then
        v_pergs := v_pergs || jsonb_build_object('os', r.os, 'numero', r.numero, 'tipo', 'reavaliar',
                                                 'chave', v_q #>> '{reavaliar,chave}', 'texto', v_q #>> '{reavaliar,texto}',
                                                 'pergunta_id', v_q #> '{reavaliar,pergunta_id}');
      end if;
    end loop;

    -- (2) encaixar: o que está pronto e não tem dia (a classe 3 ganha a reserva no dia) e o que o plano tem a menos
    for r in select k.service_order_id as os, k.numero from public.os_carteira(p_hoje) k
              order by k.numero collate "C", k.service_order_id loop
      continue when public._agenda_vigia_ja_tentou(r.os, p_agora);
      -- (7a correção, achado 17) a OS que o dono desfez e não mudou desde então: o *desfaz* vale até ela mudar
      continue when public._agenda_gestor_desfeito(r.os, p_agora);
      if r.os = any (v_falta) then
        v_cand := v_cand || r.os;
        continue;
      end if;
      continue when public._agenda_os_tem_dia(r.os, p_hoje);
      v_cl := (public._agenda_classe_agora(r.os, p_hoje) ->> 'classe')::int;
      continue when v_cl is null or v_cl not in (1, 2, 3);
      continue when v_cl = 3 and exists (select 1 from public.agenda_alocacoes a
                                          where a.service_order_id = r.os and a.estado in ('publicada', 'fixada')
                                            and a.tipo = 'reserva' and a.dia >= p_hoje);
      v_cand := v_cand || r.os;
    end loop;
    if cardinality(v_cand) > 0 then
      if v_sim then
        v_p := public.agenda_propor('os', null, null, v_cand, '{}'::jsonb, false, 'vigia', null, p_hoje, p_agora);
      else
        v_r := public._agenda_propor_e_aplicar('os', v_cand, 'vigia', null, p_hoje, p_agora);
        v_onda := coalesce((v_r ->> 'onda')::boolean, false);
      end if;
      foreach v_os in array v_cand loop
        v_mot := null;
        v_prim := null;
        if v_sim then
          v_it := (select i from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i
                    where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = v_os
                    order by i ->> 'tipo' = 'reserva', i ->> 'de' limit 1);
          v_prim := (v_it ->> 'de')::date;
          v_res := case when v_it is null then 'fora' when v_it ->> 'tipo' = 'reserva' then 'reservada' else 'marcada' end;
          if v_it is null then
            v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_p -> 'fora', '[]'::jsonb)) f
                       where (f ->> 'os')::uuid = v_os limit 1);
          end if;
        else
          v_it := null;
          v_prim := (select min(a.dia) from public.agenda_alocacoes a
                      where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        and a.dia >= p_hoje and a.resultado is null);
          if v_prim is not null then
            v_res := 'marcada';
          elsif exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada')
                         and a.tipo = 'reserva' and a.dia >= p_hoje) then
            v_res := 'reservada';
            v_prim := (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = v_os
                         and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje);
          elsif v_onda then
            v_res := 'onda';
          else
            v_res := 'fora';
            v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_r -> 'fora', '[]'::jsonb)) f
                       where (f ->> 'os')::uuid = v_os limit 1);
          end if;
        end if;
        if v_res = 'marcada' then v_marc := v_marc + 1; elsif v_res = 'reservada' then v_resv := v_resv + 1; end if;
        if v_res = 'fora' then
          v_fora := v_fora || jsonb_build_object(coalesce(v_mot, 'sem_motivo'),
                                                 coalesce((v_fora ->> coalesce(v_mot, 'sem_motivo'))::int, 0) + 1);
        end if;
        v_por := v_por || jsonb_build_object(
          'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
          'resultado', v_res, 'motivo', v_mot, 'primeiro_dia', v_prim, 'faltava', v_os = any (v_falta),
          'texto', case when v_sim then v_it ->> 'texto' end);
      end loop;
    end if;
  exception when others then
    if v_sim then
      perform set_config('agenda.gestor', '', true);
    end if;
    raise;
  end;
  if v_sim then
    perform set_config('agenda.gestor', '', true);
    select g.sombra into v_som from public.agenda_gestor_dia g where g.dia = p_hoje;
    perform public._agenda_gestor_dia_gravar(p_hoje, 'sombra', coalesce(v_som, '{}'::jsonb) || jsonb_build_object('revisao',
              jsonb_build_object('calculado_em', p_agora, 'cortes', v_cortes, 'faltando', v_faltas, 'perguntas', v_pergs,
                                 'encaixe', v_por)), p_agora);
  end if;
  return jsonb_build_object(
    'modo', v_modo, 'simulacao', v_sim,
    'reestimar', jsonb_build_object('cortes', v_cortes, 'faltando', v_faltas,
                                    'perguntas', (select count(*) from jsonb_array_elements(v_pergs) q where q ->> 'tipo' = 'reestimar')),
    'encaixe', jsonb_build_object('candidatas', coalesce(cardinality(v_cand), 0), 'marcadas', v_marc, 'reservadas', v_resv,
                                  'onda', v_onda, 'onda_pergunta', v_r -> 'pergunta_id', 'proposta_id', coalesce(v_r -> 'proposta_id', v_p -> 'proposta_id'),
                                  'fora', v_fora, 'por_os', v_por),
    'reavaliar', (select count(*) from jsonb_array_elements(v_pergs) q where q ->> 'tipo' = 'reavaliar'),
    'perguntas', v_pergs);
end;
$function$;

comment on function public._agenda_gestor_revisao(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9, D7-3): a revisão diária, passo diário do job agenda-gestor (o 1º tique de dia útil a partir de gestor_hora_revisao; na quinta, depois da publicação). Desligado (_agenda_gestor_modo(''revisao'')) ou fora de dia útil = {pulado}. Ligado: (1) reestimar — a OS com compromisso e os dias pela estimativa do orçamento (fonte orcamento): plano maior que a conta = o corte dos últimos meios-dias (_agenda_gestor_reestimar: ação reestimar, desfazível); plano menor = entra no encaixe; os dias do dono com o orçamento mudado depois = a pergunta reestimar (com prazo; padrão: os dias do dono); (2) encaixar — as OS da carteira sem compromisso de hoje em diante nas classes 1 a 3 (a 3 sem reserva vigente) e as do plano menor, não tentadas pela vigia: _agenda_propor_e_aplicar(''os'', …, ''vigia'') — a onda vale; (3) reavaliar — o diagnóstico feito, a pergunta sem prazo. Em teste: tudo seco (agenda.gestor = ''sombra'' só aqui dentro; o motor sem gravar; o corte e as perguntas só calculados) em agenda_gestor_dia.sombra.revisao = {calculado_em, cortes, faltando, perguntas, encaixe} (o resto do objeto fica). {modo, simulacao, reestimar {cortes, faltando, perguntas}, encaixe {candidatas, marcadas, reservadas, onda, onda_pergunta, proposta_id, fora, por_os}, reavaliar, perguntas}. Invoker, sem grant. CORREÇÃO DA 7a (revisão da etapa): (achado 16) o que falta e o que sobra contra a estimativa são contados em pessoa-meio-dia (_agenda_gestor_pessoa_meios): a dupla dita depois de marcar não vira corte nem falta; (achado 17) o encaixe da revisão pula a OS que o dono desfez e não mudou desde então (_agenda_gestor_desfeito): o *desfaz* da marcação do gestor não é refeito às 16:52.';

-- _agenda_gestor_encaixe (de 20261031100700_agenda_fase7a_encaixe.sql)
create or replace function public._agenda_gestor_encaixe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_modo   text;
  v_de     timestamptz;
  v_cand   uuid[];
  v_r      jsonb := '{}'::jsonb;
  v_p      jsonb := '{}'::jsonb;
  v_os     uuid;
  v_res    text;
  v_prim   date;
  v_mot    text;
  v_q      jsonb;
  v_it     jsonb;
  v_onda   boolean := false;
  v_por    jsonb := '[]'::jsonb;
  v_fora   jsonb := '{}'::jsonb;
  v_marc   int := 0;
  v_resv   int := 0;
  v_perg   int := 0;
  v_vencid int := 0;
  v_som    jsonb;
  v_lista  jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_encaixe: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('encaixe');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado', 'modo', v_modo);
  end if;
  -- a onda aberta de uma versão do plano que já passou não vale mais (a rodada que refizer a conta pergunta de novo)
  if v_modo = 'ligado' then
    with f as (
      update public.agenda_perguntas q
         set estado = 'resolvida', resolvida_motivo = 'a agenda mudou depois da pergunta: refaço a conta'
       where q.tipo = 'onda' and q.estado = 'aberta' and q.modo = 'ligado'
         and q.versao_base is distinct from (public._agenda_cfg()).versao_plano
      returning 1)
    select count(*)::int into v_vencid from f;
  end if;

  -- a marca d'água: o "até" do último encaixe que rodou no mesmo modo (o que a sombra viu não conta como feito de verdade)
  select max((x.contagens -> 'encaixe' ->> 'ate')::timestamptz) into v_de
    from public.agenda_vigia_rodadas x
   where x.rotina = 'gestor' and x.contagens -> 'encaixe' ->> 'modo' = v_modo
     and (x.contagens -> 'encaixe' ->> 'ate')::timestamptz <= p_agora;
  v_de := coalesce(v_de, p_agora - interval '1 day') - interval '5 minutes';

  v_cand := array(
    select k.service_order_id
      from public.os_carteira(p_hoje) k
      join public.service_orders so on so.id = k.service_order_id
     where not public._agenda_os_tem_dia(k.service_order_id, p_hoje)
       and ((so.converted_to_os_at > v_de and so.converted_to_os_at <= p_agora)
            or (so.signed_at > v_de and so.signed_at <= p_agora)
            or (so.created_at > v_de and so.created_at <= p_agora)
            or exists (select 1 from public.ai_lifecycle_events e
                        where e.entity_id = so.id and e.event_type = 'status_change'
                          and e.new_value in ('open', 'approved', 'scheduled') and e.created_at > v_de and e.created_at <= p_agora)
            or exists (select 1 from public.os_planejamento pl
                        where pl.service_order_id = so.id and pl.atualizado_em > v_de and pl.atualizado_em <= p_agora)
            or exists (select 1 from public.os_material m
                        where m.service_order_id = so.id and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix')
                          and m.atualizado_em > v_de and m.atualizado_em <= p_agora)
            or exists (select 1 from public.agenda_acoes a
                        where a.service_order_id = so.id and a.tipo = 'estimar' and a.executada and a.desfeita_em is null
                          and a.criada_em > v_de and a.criada_em <= p_agora))
       and not public._agenda_vigia_ja_tentou(k.service_order_id, p_agora)
       -- (7a correção, achado 17) nem a OS que o dono desfez e não mudou desde então
       and not public._agenda_gestor_desfeito(k.service_order_id, p_agora)
     order by k.numero, k.service_order_id);

  if cardinality(v_cand) > 0 and v_modo = 'ligado' then
    v_r := public._agenda_propor_e_aplicar('os', v_cand, 'vigia', null, p_hoje, p_agora);
    v_onda := coalesce((v_r ->> 'onda')::boolean, false);
    foreach v_os in array v_cand loop
      v_prim := (select min(a.dia) from public.agenda_alocacoes a
                  where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    and a.dia >= p_hoje and a.resultado is null);
      v_mot := null;
      if v_prim is not null then
        v_res := 'marcada';
        v_marc := v_marc + 1;
      elsif exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada')
                     and a.tipo = 'reserva' and a.dia >= p_hoje) then
        v_res := 'reservada';
        v_resv := v_resv + 1;
        v_prim := (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = v_os
                     and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje);
      elsif v_onda then
        v_res := 'onda';
      else
        v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_r -> 'fora', '[]'::jsonb)) f
                   where (f ->> 'os')::uuid = v_os limit 1);
        v_q := public._agenda_gestor_perguntas_da_os(v_os, p_hoje, p_agora, false);
        if coalesce((v_q ->> 'perguntou')::boolean, false)
           or exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'ligado' and q.critica
                       and (q.service_order_id = v_os or v_os = any (q.os_ids))) then
          v_res := 'pergunta';
          v_perg := v_perg + 1;
        else
          v_res := 'fora';
        end if;
        v_fora := v_fora || jsonb_build_object(coalesce(v_mot, 'sem_motivo'),
                                               coalesce((v_fora ->> coalesce(v_mot, 'sem_motivo'))::int, 0) + 1);
      end if;
      v_por := v_por || jsonb_build_object(
        'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
        'aprovada_em', (select coalesce(so.converted_to_os_at, so.signed_at, so.created_at) from public.service_orders so where so.id = v_os),
        'resultado', v_res, 'motivo', v_mot, 'primeiro_dia', v_prim);
    end loop;
  elsif cardinality(v_cand) > 0 then
    -- em teste: as regras do gestor valem só aqui dentro; nada é gravado (só o diário)
    perform set_config('agenda.gestor', 'sombra', true);
    begin
      v_p := public.agenda_propor('os', null, null, v_cand, '{}'::jsonb, false, 'vigia', null, p_hoje, p_agora);
      foreach v_os in array v_cand loop
        v_it := (select i from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i
                  where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = v_os
                  order by i ->> 'tipo' = 'reserva', i ->> 'de' limit 1);
        v_mot := null;
        v_prim := (v_it ->> 'de')::date;
        if v_it is not null and v_it ->> 'tipo' <> 'reserva' then
          v_res := 'marcada';
          v_marc := v_marc + 1;
        elsif v_it is not null then
          v_res := 'reservada';
          v_resv := v_resv + 1;
        else
          v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_p -> 'fora', '[]'::jsonb)) f
                     where (f ->> 'os')::uuid = v_os limit 1);
          v_q := public._agenda_gestor_perguntas_da_os(v_os, p_hoje, p_agora, true);
          if v_q ? 'chave' then
            v_res := 'pergunta';
            v_perg := v_perg + 1;
          else
            v_res := 'fora';
          end if;
          v_fora := v_fora || jsonb_build_object(coalesce(v_mot, 'sem_motivo'),
                                                 coalesce((v_fora ->> coalesce(v_mot, 'sem_motivo'))::int, 0) + 1);
        end if;
        v_por := v_por || jsonb_build_object(
          'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
          'aprovada_em', (select coalesce(so.converted_to_os_at, so.signed_at, so.created_at) from public.service_orders so where so.id = v_os),
          'resultado', v_res, 'motivo', v_mot, 'primeiro_dia', v_prim,
          'texto', case when v_res = 'pergunta' then v_q ->> 'texto' else v_it ->> 'texto' end);
      end loop;
    exception when others then
      perform set_config('agenda.gestor', '', true);
      raise;
    end;
    perform set_config('agenda.gestor', '', true);
    select g.sombra into v_som from public.agenda_gestor_dia g where g.dia = p_hoje;
    v_lista := coalesce(v_som -> 'encaixe', '[]'::jsonb)
               || jsonb_build_array(jsonb_build_object('calculado_em', p_agora, 'de', v_de, 'por_os', v_por));
    v_lista := (select coalesce(jsonb_agg(e order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_lista) with ordinality t(e, o)
                 where o > jsonb_array_length(v_lista) - 10);
    perform public._agenda_gestor_dia_gravar(p_hoje, 'sombra', coalesce(v_som, '{}'::jsonb) || jsonb_build_object('encaixe', v_lista),
                                             p_agora);
  end if;

  return jsonb_build_object('modo', v_modo, 'simulacao', v_modo <> 'ligado', 'de', v_de, 'ate', p_agora,
                            'candidatas', coalesce(cardinality(v_cand), 0), 'marcadas', v_marc, 'reservadas', v_resv,
                            'perguntas', v_perg, 'onda', v_onda, 'onda_pergunta', v_r -> 'pergunta_id',
                            'ondas_vencidas', v_vencid, 'proposta_id', v_r -> 'proposta_id', 'fora', v_fora, 'por_os', v_por);
end;
$function$;

comment on function public._agenda_gestor_encaixe(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P8; spec §5.8, D7-3): o encaixe na aprovação, passo de todo tique do job agenda-gestor. Desligado (_agenda_gestor_modo(''encaixe'')) = {pulado}. Candidatas: as OS da carteira sem dia de compromisso de hoje em diante (_agenda_os_tem_dia), não tentadas pela vigia (_agenda_vigia_ja_tentou), com algo novo desde a marca d''água (o "até" do último encaixe no mesmo modo, em agenda_vigia_rodadas.contagens.encaixe; sem ele, p_agora − 1 dia; margem de 5 min): converted_to_os_at (o sinal; o agrupar, sem status_change), signed_at, created_at, status_change para open/approved/scheduled (ai_lifecycle_events), os_planejamento.atualizado_em, os_material.atualizado_em com fonte dono/fornecedor/nfe/pix, e a ação estimar (os dias do prazo vencido do passo vetos do mesmo tique). Ligado: _agenda_propor_e_aplicar(''os'', candidatas, ''vigia'') (a onda vale) e a pergunta do gestor das que ficaram de fora (_agenda_gestor_perguntas_da_os); a onda aberta de versão do plano que já passou é resolvida. Em teste: agenda.gestor = ''sombra'' só dentro do passo, agenda_propor sem gravar e as perguntas secas, acrescentados a agenda_gestor_dia.sombra.encaixe (os 10 mais novos). {modo, simulacao, de, ate, candidatas, marcadas, reservadas, perguntas, onda, onda_pergunta, ondas_vencidas, proposta_id, fora {motivo: n}, por_os [{os, numero, aprovada_em, resultado (marcada | reservada | onda | pergunta | fora), motivo, primeiro_dia}]}. Invoker, sem grant: só a rodada do gestor o chama. CORREÇÃO DA 7a (revisão da etapa; achado 17): a candidata que o dono desfez e não mudou desde então (_agenda_gestor_desfeito) fica de fora.';

-- os_duracao_sugerida (de 20261031100100_agenda_fase7a_duracao.sql)
create or replace function public.os_duracao_sugerida(p_so_id uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_total  numeric;
  v_mat    numeric;
  v_horas  numeric;
  v_mo     numeric;
  v_dp_ot  numeric;
  v_dp_re  numeric;
  v_pes    int;
  v_d_ot   numeric;
  v_d_re   numeric;
  v_sug    numeric;
  -- FASE 6: o R$ por diária do realista e de onde ele vem
  v_mo_dia   numeric;
  v_mo_fonte text;
  -- FASE 6: fim
  -- FASE 7: (7a P2) as regras do gestor da agenda na duração — o que saiu da mão de obra, a dupla dita, o aviso de dupla e o
  -- que a saída ganha (só com o portão; sem ele, nada disto é usado e a saída é a de antes)
  v_f7_fora   jsonb;
  v_f7_tot    numeric;
  v_f7_mat    numeric;
  v_f7_h      numeric;
  v_f7_dupla  text;
  v_f7_alerta jsonb;
  v_f7_pes    int;
  v_f7_extra  jsonb := '{}'::jsonb;
  -- FASE 7: fim
  -- FASE 7: (7a correção, memória da rodada; achado 10)
  v_f77_chave text;
  v_f77_memo  jsonb;
  v_f77_marca bigint;
  -- FASE 7: fim
begin
  if not exists (select 1 from public.service_orders where id = p_so_id) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  -- FASE 7: (7a correção, memória da rodada; achado 10) dentro da rodada da vigia (agenda.rodada, posto por agenda_vigiar) e com
  -- alguma regra do gestor na duração, cada OS é calculada UMA vez e lembrada enquanto a transação não gravar nada no que ela lê
  -- (_agenda_rodada_marca, a mesma da prontidão) e o portão (agenda.gestor) for o mesmo. Com o gestor ligado, a mesma OS era
  -- calculada ~20 vezes por rodada (a prontidão, a estimativa, a situação, os meios, a classe). A conta é a de sempre (a chamada
  -- de dentro, com a memória em pausa); fora da rodada ou sem as regras, nada muda.
  if p_so_id is not null and coalesce(current_setting('agenda.rodada', true), '') <> ''
     and coalesce(current_setting('agenda.rodada_dur_em', true), '') = ''
     and (public._agenda_gestor_regra('uma_pessoa') or public._agenda_gestor_regra('mo_limpa')
          or public._agenda_gestor_regra('diagnostico')) then
    v_f77_chave := p_so_id::text || ':' || coalesce(current_setting('agenda.gestor', true), '');
    v_f77_memo := public._agenda_rodada_duracao_lembrar(v_f77_chave);
    if v_f77_memo is null then
      v_f77_marca := public._agenda_rodada_marca();
      perform set_config('agenda.rodada_dur_em', 'on', true);
      v_f77_memo := public.os_duracao_sugerida(p_so_id);
      perform set_config('agenda.rodada_dur_em', '', true);
      perform public._agenda_rodada_duracao_guardar(v_f77_chave, v_f77_marca, v_f77_memo);
    end if;
    return v_f77_memo;
  end if;
  -- FASE 7: fim

  -- A mão de obra é o total das linhas de serviço menos o material de texto livre que ENTRA NA COMPRA (o mesmo
  -- predicado de compute_purchase_needs); as horas diretas são as linhas cobradas por hora.
  select coalesce(sum(s.line_total), 0),
         coalesce(sum(s.line_total) filter (
           where s.service_id is null and s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0
             and public.free_text_is_material(s.name_snapshot)), 0),
         coalesce(sum(s.quantity) filter (where s.billing_unit_snapshot = 'hour'), 0)
    into v_total, v_mat, v_horas
    from public.service_order_services s
   where s.service_order_id = p_so_id;
  -- FASE 7: (7a P2, regra mo_limpa) deslocamento, viagem, translado, visita técnica, km rodado e frete não são dias de
  -- serviço: a linha cujo nome do serviço (_agenda_nome_do_servico: o trecho antes do travessão, dos dois pontos ou do
  -- parêntese) casa mo_fora_regex sai do total, das horas e — se ela era material de texto livre — do material, para a mão de
  -- obra ficar a mesma conta sem ela. A saída ganha fora_da_mo [{linha, nome, valor, horas}] só quando tirou alguma coisa.
  if public._agenda_gestor_regra('mo_limpa') then
    select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot, 'valor', coalesce(s.line_total, 0),
                                                 'horas', case when s.billing_unit_snapshot = 'hour'
                                                               then trim_scale(coalesce(s.quantity, 0)) else 0 end)
                              order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb),
           coalesce(sum(s.line_total), 0),
           coalesce(sum(s.line_total) filter (
             where s.service_id is null and s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0
               and public.free_text_is_material(s.name_snapshot)), 0),
           coalesce(sum(s.quantity) filter (where s.billing_unit_snapshot = 'hour'), 0)
      into v_f7_fora, v_f7_tot, v_f7_mat, v_f7_h
      from public.service_order_services s
     where s.service_order_id = p_so_id
       and public._agenda_nome_do_servico(s.name_snapshot) ~ c.mo_fora_regex;
    if jsonb_array_length(v_f7_fora) > 0 then
      v_total := v_total - v_f7_tot;
      v_mat := v_mat - v_f7_mat;
      v_horas := v_horas - v_f7_h;
      v_f7_extra := v_f7_extra || jsonb_build_object('fora_da_mo', v_f7_fora);
    end if;
  end if;
  -- FASE 7: fim
  v_mo := greatest(v_total - v_mat, 0);
  -- FASE 7: (7a P2, regra diagnostico) a OS de diagnóstico (service_type ou a linha de maior valor casa "diagnost": a mesma
  -- régua de os_presenca_do_dono) leva diagnostico_dias com 1 pessoa (2 só se o dono marcou a dupla), seja qual for o valor —
  -- depois o gestor reavalia. Vale também sem mão de obra separada: o diagnóstico tem o tempo dele.
  if public._agenda_gestor_regra('diagnostico')
     and (exists (select 1 from public.service_orders so where so.id = p_so_id and so.service_type = 'diagnosis')
          or coalesce((select public._agenda_normal(s.name_snapshot) from public.service_order_services s
                        where s.service_order_id = p_so_id
                        order by s.line_total desc nulls last, s.created_at, s.id limit 1), '') ~ 'diagnost') then
    select pl.dupla_dita into v_f7_dupla from public.os_planejamento pl where pl.service_order_id = p_so_id;
    v_f7_pes := case when v_f7_dupla = 'todos' and public._agenda_gestor_regra('uma_pessoa')
                     then greatest(c.equipe_sugerida, 2) else 1 end;
    return jsonb_build_object(
      'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
      'dp_otimista', round(c.diagnostico_dias * v_f7_pes, 2), 'dp_realista', round(c.diagnostico_dias * v_f7_pes, 2),
      'pessoas', v_f7_pes, 'dias_otimista', trim_scale(c.diagnostico_dias), 'dias_realista', trim_scale(c.diagnostico_dias),
      'sugerida', trim_scale(c.diagnostico_dias),
      'diarias_otimista', trim_scale(c.diagnostico_dias * v_f7_pes), 'diarias_realista', trim_scale(c.diagnostico_dias * v_f7_pes),
      'texto', public._agenda_dias(c.diagnostico_dias) || ' de diagnóstico'
               || case when v_f7_pes = 1 then '' else format(' com %s pessoas', v_f7_pes) end
               || '; depois eu reavalio',
      'diagnostico', true,
      'pessoas_motivo', case when v_f7_pes = 1 then 'regra' else 'dupla_marcada' end) || v_f7_extra;
  end if;
  -- (mo_limpa) o que sobrou sem mão de obra nem horas depois de tirar o deslocamento é "sem base", dizendo o que saiu.
  if v_f7_extra ? 'fora_da_mo' and v_mo <= 0 and v_horas <= 0 then
    return jsonb_build_object('ok', true, 'sem_base', true, 'mo', v_mo, 'horas', v_horas,
                              'texto', 'sem base para estimar: quantos dias?') || v_f7_extra;
  end if;
  -- FASE 7: fim

  if v_mo <= 0 and v_horas <= 0 then
    return jsonb_build_object('ok', true, 'sem_base', true, 'mo', v_mo, 'horas', v_horas,
                              'texto', 'sem base para estimar: quantos dias?');
  end if;

  -- Diárias-pessoa: o otimista pelo preço da diária, o realista pelo que a HBR fatura por diária de fato.
  v_dp_ot := greatest(v_horas / c.jornada_horas, v_mo / c.mo_por_diaria_preco);
  v_dp_re := greatest(v_horas / c.jornada_horas, v_mo / c.mo_por_diaria_real);
  -- FASE 6: o realista pelo R$ por diária aprendido (em uso, com modo_aprendizado ligado e mo na lista); senão o de hoje
  -- (mo_por_diaria_real): _agenda_mo_por_diaria_real()
  v_mo_dia := public._agenda_mo_por_diaria_real();
  v_mo_fonte := case when public._agenda_aprendido('mo', 'todas') is not null then 'aprendido' else 'padrao' end;
  v_dp_re := greatest(v_horas / c.jornada_horas, v_mo / v_mo_dia);
  -- FASE 6: fim
  v_pes := case when v_dp_re <= 1 then 1 else c.equipe_sugerida end;
  -- FASE 7: (7a P2, regra uma_pessoa, AG7-04) 1 pessoa por serviço (equipe_padrao); a dupla (equipe_sugerida, nunca menos
  -- de 2) só quando o dono marcou *<nome> com dupla* (os_planejamento.dupla_dita = 'todos'; inicio/fim são do 7b, por
  -- meio-dia). O serviço de até 1 diária continua com 1 pessoa. Sem nada dito, o 1º gatilho de dupla_gatilhos (ou a 1ª nota de
  -- dupla_notas) que casar no nome do serviço de alguma linha vira o aviso alerta_dupla {motivo, nota, onde, linha, nome,
  -- trecho} — só aviso ao dono, nunca 2 pessoas sozinho (a dupla automática é o modo_dupla do 7b).
  if public._agenda_gestor_regra('uma_pessoa') then
    select pl.dupla_dita into v_f7_dupla from public.os_planejamento pl where pl.service_order_id = p_so_id;
    v_pes := case when v_f7_dupla = 'todos' then greatest(c.equipe_sugerida, 2)
                  when v_dp_re <= 1 then 1
                  else c.equipe_padrao end;
    v_f7_extra := v_f7_extra || jsonb_build_object('pessoas_motivo',
                                                   case when v_f7_dupla = 'todos' then 'dupla_marcada' else 'regra' end);
    if v_f7_dupla is null then
      select jsonb_build_object('motivo', g.e ->> 0, 'nota', g.nota, 'onde', case when not g.nota then g.e ->> 2 end,
                                'linha', s.id, 'nome', s.name_snapshot,
                                'trecho', substring(s.nome_servico from '\m(' || (g.e ->> 1) || ')'))
        into v_f7_alerta
        from (select t.e, t.o, false as nota from jsonb_array_elements(c.dupla_gatilhos) with ordinality t(e, o)
              union all
              select t.e, t.o, true from jsonb_array_elements(c.dupla_notas) with ordinality t(e, o)) g
        -- (7a correção, achado 10) o nome do serviço de cada linha calculado uma vez (antes, uma vez por gatilho)
        join (select s0.id, s0.name_snapshot, s0.line_total, s0.created_at,
                     public._agenda_nome_do_servico(s0.name_snapshot) as nome_servico
                from public.service_order_services s0 where s0.service_order_id = p_so_id offset 0) s
          on s.nome_servico ~ ('\m(' || (g.e ->> 1) || ')')
       order by g.nota, g.o, s.line_total desc nulls last, s.created_at, s.id
       limit 1;
      if v_f7_alerta is not null then
        v_f7_extra := v_f7_extra || jsonb_build_object('alerta_dupla', v_f7_alerta);
      end if;
    end if;
  end if;
  -- FASE 7: fim
  -- Dias de calendário arredondados ao meio dia; nunca menos de meio dia.
  v_d_ot := trim_scale(greatest(0.5, round(v_dp_ot / v_pes * 2) / 2));
  v_d_re := trim_scale(greatest(v_d_ot, round(v_dp_re / v_pes * 2) / 2));
  v_sug  := trim_scale(round(v_d_ot + v_d_re) / 2);
  -- FASE 7: (7a P2) com uma regra que mudou a saída (fora_da_mo, pessoas_motivo, alerta_dupla), a mesma saída de baixo (com o
  -- R$ por diária aprendido, quando em uso) mais as chaves novas; sem nada, as duas saídas de antes, byte a byte.
  if v_f7_extra <> '{}'::jsonb then
    return jsonb_build_object(
      'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
      'dp_otimista', round(v_dp_ot, 2), 'dp_realista', round(v_dp_re, 2),
      'pessoas', v_pes, 'dias_otimista', v_d_ot, 'dias_realista', v_d_re, 'sugerida', v_sug,
      'diarias_otimista', trim_scale(v_d_ot * v_pes), 'diarias_realista', trim_scale(v_d_re * v_pes),
      'texto', public._agenda_faixa_dias(v_d_ot, v_d_re)
               || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
               || ' (estimativa minha, pelo valor)')
      || case when v_mo_fonte = 'aprendido' then jsonb_build_object('mo_fonte', 'aprendido', 'mo_por_diaria', v_mo_dia)
              else '{}'::jsonb end
      || v_f7_extra;
  end if;
  -- FASE 7: fim

  -- FASE 6: com o R$ por diária aprendido em uso, a mesma saída mais mo_fonte = 'aprendido' e o valor usado (mo_por_diaria);
  -- com o padrão, a saída de antes, byte a byte (a os_prontidao e o motor a embutem: em teste nada pode mudar)
  if v_mo_fonte = 'aprendido' then
    return jsonb_build_object(
      'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
      'dp_otimista', round(v_dp_ot, 2), 'dp_realista', round(v_dp_re, 2),
      'pessoas', v_pes, 'dias_otimista', v_d_ot, 'dias_realista', v_d_re, 'sugerida', v_sug,
      'diarias_otimista', trim_scale(v_d_ot * v_pes), 'diarias_realista', trim_scale(v_d_re * v_pes),
      'texto', public._agenda_faixa_dias(v_d_ot, v_d_re)
               || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
               || ' (estimativa minha, pelo valor)',
      'mo_fonte', 'aprendido', 'mo_por_diaria', v_mo_dia);
  end if;
  -- FASE 6: fim
  return jsonb_build_object(
    'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
    'dp_otimista', round(v_dp_ot, 2), 'dp_realista', round(v_dp_re, 2),
    'pessoas', v_pes, 'dias_otimista', v_d_ot, 'dias_realista', v_d_re, 'sugerida', v_sug,
    'diarias_otimista', trim_scale(v_d_ot * v_pes), 'diarias_realista', trim_scale(v_d_re * v_pes),
    'texto', public._agenda_faixa_dias(v_d_ot, v_d_re)
             || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
             || ' (estimativa minha, pelo valor)');
end;
$function$;

comment on function public.os_duracao_sugerida(uuid) is
  'Agenda de Produção (Fase 1, P3): a duração "pelo valor" (plano §4.2 com a correção do material). mo = linhas de serviço − material de texto livre que entra na compra; horas = linhas por hora; diárias-pessoa otimista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_preco), realista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_real); 1 pessoa se o realista ≤ 1, senão equipe_sugerida; dias arredondados ao meio dia; sugerida = o meio dia mais perto da média. Sem mão de obra nem horas: {sem_base:true, texto:"sem base para estimar: quantos dias?"}. Nunca é gravada. FASE 6 (P2): o realista usa _agenda_mo_por_diaria_real() (o R$ por diária aprendido em uso, senão mo_por_diaria_real); com o aprendido em uso a saída ganha mo_fonte = aprendido e mo_por_diaria (sem ele, a saída de antes). FASE 7 (7a P2), atrás do portão _agenda_gestor_regra (falso = a saída de antes, byte a byte): mo_limpa — a linha cujo nome do serviço (_agenda_nome_do_servico) casa mo_fora_regex sai da mão de obra e das horas (fora_da_mo); uma_pessoa (AG7-04) — pessoas = equipe_padrao (até 1 diária = 1), greatest(equipe_sugerida, 2) só com dupla_dita = todos (pessoas_motivo) e, sem nada dito, alerta_dupla pelo 1º gatilho de dupla_gatilhos/dupla_notas no nome do serviço; diagnostico — a OS de diagnóstico leva diagnostico_dias com 1 pessoa (diagnostico: true, "meio dia de diagnóstico; depois eu reavalio"). CORREÇÃO DA 7a (revisão da etapa; achado 10): dentro da rodada da vigia (agenda.rodada) e com alguma regra do gestor na duração (mo_limpa, uma_pessoa, diagnostico), a duração de cada OS é calculada uma vez e lembrada (_agenda_rodada_duracao_lembrar/_guardar, chave <OS>:<agenda.gestor>, a marca de _agenda_rodada_marca) enquanto a transação não grava nada no que ela lê; e o nome do serviço de cada linha é calculado uma vez por linha (antes, uma vez por gatilho de dupla). O resultado é o mesmo, byte a byte.';

-- _agenda_rodada_marca (de 20261031100200_agenda_fase7a_prontidao.sql)
create or replace function public._agenda_rodada_marca()
 returns bigint
 language sql
 volatile
 set search_path to 'public'
as $function$
  select coalesce(sum(pg_catalog.pg_stat_get_xact_tuples_inserted(c.oid) + pg_catalog.pg_stat_get_xact_tuples_updated(c.oid)
                      + pg_catalog.pg_stat_get_xact_tuples_deleted(c.oid)), 0)::bigint
    from pg_catalog.pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
     and c.relname not in ('agenda_perguntas', 'agenda_acoes', 'agenda_propostas', 'agenda_vigia_rodadas', 'app_error_logs');
$function$;

comment on function public._agenda_rodada_marca() is
  'Agenda de Produção (correção de 29/10, P5): a marca das escritas desta transação nas tabelas de public (linhas inseridas, mudadas e apagadas, pelos contadores da própria transação; só cresce), menos as 5 que a vigia escreve e a conta da prontidão não lê (agenda_perguntas, agenda_acoes, agenda_propostas, agenda_vigia_rodadas, app_error_logs). A memória da rodada da vigia só devolve o que foi calculado com a marca de agora. FASE 7 (7a P3): com a regra situacao do gestor (a conta da prontidão lê então agenda_acoes e agenda_perguntas, pela situação da OS), a marca conta também essas duas, num número negativo (−1 − as escritas de sempre − as das duas), que nunca coincide com uma marca sem a regra; sem a regra, a de antes. CORREÇÃO DA 7a (revisão da etapa; achado 10): a marca volta a ser a de sempre (sem o termo de agenda_acoes e agenda_perguntas do 7a P3): a situação da OS (_agenda_os_situacao) não lê mais essas tabelas, e cada pergunta ou ação gravada na rodada fazia a vigia recalcular a prontidão de todas as OS (a vigia ligada 3,7 a 5 vezes mais lenta).';

-- os_prontidao (de 20261031100200_agenda_fase7a_prontidao.sql)
create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c            public.agenda_config := public._agenda_cfg();
  so           record;
  p            public.os_planejamento%rowtype;
  v_na_cart    boolean;
  v_aprov      date;
  v_pago       numeric := 0;
  v_pend       numeric := 0;
  v_ag_de      date;
  v_ag_ate     date;
  v_bem_nome   text;
  v_d_bem      date;
  v_bem_tudo   boolean := false;
  v_horizonte  date;
  v_base       date;
  v_est_sm     date;
  v_bruto      jsonb;
  v_itens      jsonb;
  v_crit       jsonb;
  v_embut      jsonb;
  v_n_itens    int;
  v_conferido  boolean;
  v_mat_estado text;
  v_dpm        date;
  v_gargalo    jsonb;
  v_confianca  text;
  v_inicio_mat date;
  v_est        date;
  v_sug        jsonb;
  v_dur        jsonb;
  v_equipe     jsonb;
  v_meios      numeric;
  v_diarias_eq numeric;
  v_dias_re    numeric;
  v_pres       jsonb;
  v_prazo      date;
  v_prazo_fnt  text;
  v_razao      numeric;
  v_r          jsonb := '[]'::jsonb;
  v_estado     text;
  v_estado_txt text;
  v_principal  jsonb;
  v_quase      boolean := false;
  v_parada     boolean := false;
  v_ult_diaria date;
  v_x          jsonb;
  v_compra     jsonb;
  v_n          int;
  v_n_falta    int := 0;
  v_n_sem      int;
  v_txt        text;
  v_cond       text;
  v_dono_padrao boolean;
  v_cc         record;
  -- FASE 2: o que o plano publicado diz da OS (spec-fase2 §6.1)
  v_plano      jsonb;
  v_ult_evid   date;
  v_tem_futuro boolean := false;
  -- FASE 2: fim
  -- CORREÇÃO FASE 6: (C1) item 1: o início pelo material pelo dia DITO (o que julga o que já está publicado)
  v_dpm_dito    date;
  v_inicio_dito date;
  -- CORREÇÃO FASE 6: fim
  -- CORREÇÃO 29/10 (P5): a memória da rodada da vigia
  v_memo        jsonb;
  v_marca       bigint;
  -- CORREÇÃO 29/10 (P5): fim
  -- FASE 7: (7a P3) as regras do gestor da agenda na prontidão: os portões do material lidos uma vez, a OS com compromisso (o
  -- "compre até" gravado), o "sem peça" e a peça embutida supostos e a estimativa do gestor (sem portão nenhum, nada disto é
  -- usado e a saída é a de antes, byte a byte)
  v_f7_valor    boolean := false;
  v_f7_padrao   boolean := false;
  v_f7_firme    boolean := false;
  v_f7_comp     boolean := false;
  v_f7_sem_peca boolean := false;
  v_f7_embut    boolean := false;
  v_f7_est      jsonb;
  v_f7_mot      text;
  v_f7_sit      jsonb;
  v_f7_txt      text;
  -- (o laço dos itens)
  v_f7_novos    jsonb;
  v_f7_i        jsonb;
  v_f7_m        public.os_material%rowtype;
  v_f7_sit_i    text;
  v_f7_prazo    int;
  v_f7_corr     int;
  v_f7_prev     date;
  v_f7_inf      boolean;
  v_f7_vu       numeric;
  v_f7_pad      boolean;
  v_f7_fok      boolean;
  v_f7_ep       int;
  v_f7_int      int;
  v_f7_grav     boolean;
  v_f7_data     date;
  v_f7_compre   date;
  v_f7_req      numeric;
  v_f7_nm       numeric;
  -- FASE 7: fim
begin
  if p_hoje is null then
    raise exception 'os_prontidao: sem o dia de hoje' using errcode = '22004';
  end if;
  -- CORREÇÃO 29/10 (P5): dentro da rodada da vigia (agenda.rodada = o dia dela, posto por agenda_vigiar), a prontidão de
  -- cada OS é calculada UMA vez e lembrada enquanto a transação não gravar nada no que ela lê (_agenda_rodada_marca).
  -- Antes, a mesma OS era recalculada em cada passo (limpeza, material, chegou, parada, duração, fila...): ~37 contas por
  -- rodada para 11 OS. O cálculo é o de sempre (a chamada de dentro, com a memória em pausa); fora da rodada, nada muda.
  if p_so_id is not null and current_setting('agenda.rodada', true) = p_hoje::text then
    v_memo := public._agenda_rodada_lembrar(p_so_id);
    if v_memo is null then
      v_marca := public._agenda_rodada_marca();
      perform set_config('agenda.rodada', 'calculando', true);
      v_memo := public.os_prontidao(p_so_id, p_hoje);
      perform set_config('agenda.rodada', p_hoje::text, true);
      perform public._agenda_rodada_guardar(p_so_id, v_marca, v_memo);
    end if;
    return v_memo;
  end if;
  -- CORREÇÃO 29/10 (P5): fim

  select o.*, cl.name as cliente_nome, vs.name as bem, vs.asset_type as bem_tipo,
         mg.service_order_number as juntado_em
    into so
    from public.service_orders o
    left join public.clients cl on cl.id = o.client_id
    left join public.vessels vs on vs.id = o.vessel_id
    left join public.service_orders mg on mg.id = o.merged_into_id
   where o.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;

  select * into p from public.os_planejamento where service_order_id = p_so_id;

  -- Carteira, aprovação, sinal e janela antiga: a MESMA conta de os_carteira (fora dela, a mesma fórmula).
  select true, k.aprovada_em, k.sinal_pago, k.sinal_pendente, k.agendada_de, k.agendada_ate
    into v_na_cart, v_aprov, v_pago, v_pend, v_ag_de, v_ag_ate
    from public.os_carteira(p_hoje) k where k.service_order_id = p_so_id;
  if not found then
    v_na_cart := false;
    v_aprov := (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date;
    select coalesce(sum(coalesce(r.paid_amount, 0)), 0),
           coalesce(sum(case when r.status in ('pending', 'partially_paid', 'overdue')
                             then greatest(r.amount - coalesce(r.paid_amount, 0), 0) else 0 end), 0)
      into v_pago, v_pend
      from public.receivables r
     where r.service_order_id = p_so_id and r.is_deposit and r.status <> 'cancelled';
    v_ag_de := (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    v_ag_ate := (coalesce(so.scheduled_end_at, so.scheduled_start_at) at time zone 'America/Sao_Paulo')::date;
  end if;

  -- O bem (barco, motorhome): 1º dia a partir de amanhã fora de bem_indisponivel; null = fora sem data de volta.
  v_bem_nome := case when public._agenda_normal(coalesce(so.bem_tipo, so.bem)) ~ 'motorhome|motor home|trailer'
                     then 'o motorhome' else 'o barco' end;
  v_horizonte := p_hoje + 7 * c.horizonte_semanas;
  v_d_bem := p_hoje + 1;
  if p.service_order_id is not null and not isempty(p.bem_indisponivel) and p.bem_indisponivel @> v_d_bem then
    select upper(r) into v_d_bem from unnest(p.bem_indisponivel) r where r @> (p_hoje + 1);
  end if;
  v_bem_tudo := v_d_bem is null or v_d_bem > v_horizonte;

  -- O início mais cedo sem olhar o material: o bem livre, o "não antes de" e o congelamento (hoje + o próximo
  -- dia útil ficam como estão).
  v_base := public.agenda_somar_du(p_hoje, c.congelamento_du + 1);
  v_est_sm := greatest(v_d_bem, p.nao_antes_de, v_base);

  -- ── Material efetivo: a conta bruta + o que foi informado em os_material ──
  v_bruto := public.os_necessidade_bruta(p_so_id);
  -- FASE 7: (7a P3) os portões do material (D7-2: o dado que falta não tira a OS da agenda): critico_por_valor (AG7-05: só o
  -- item de valor unitário >= critico_valor_min segura a data), prazo_padrao (AG7-06: sem o prazo do fornecedor, contei
  -- prazo_sem_fornecedor_du dias úteis) e compra_firme (AG7-07: a compra conta o tempo interno, compra_interna_du, e a falta com
  -- "compre até" não tira a OS do compromisso). O "compre até" GRAVADO pelo gestor (os_material.compre_ate, P10) só vale para a
  -- OS com compromisso de hoje em diante: enquanto ele não vence, a data do item não anda (o publicado não desliza).
  v_f7_valor := public._agenda_gestor_regra('critico_por_valor');
  v_f7_padrao := public._agenda_gestor_regra('prazo_padrao');
  v_f7_firme := public._agenda_gestor_regra('compra_firme');
  if v_f7_firme then
    v_f7_comp := exists (select 1 from public.agenda_alocacoes a
                          where a.service_order_id = p_so_id and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
                            and a.dia >= p_hoje);
  end if;
  -- FASE 7: fim

  with
  bruto as (
    select x.ord, x.i ->> 'origin' as origin, (x.i ->> 'sourceId')::uuid as src,
           (x.i ->> 'required')::numeric as req, coalesce((x.i ->> 'available')::numeric, 0) as disp,
           x.i ->> 'status' as st, (x.i ->> 'productId')::uuid as prod, x.i ->> 'description' as descr
      from jsonb_array_elements(coalesce(v_bruto -> 'items', '[]'::jsonb)) with ordinality x(i, ord)
     where coalesce((x.i ->> 'required')::numeric, 0) > 0
       and x.i ->> 'origin' in ('part', 'free_text', 'purchase_order')
  ),
  cand as (
    -- (1) os itens da conta bruta, com a linha do mesmo vínculo
    select 1 as grupo, b.ord::bigint as ord,
           case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end as origem,
           b.src as vinculo, b.req, b.disp, b.st, b.descr, b.prod, null::uuid as po_forn, null::date as recebido_em,
           m as l
      from bruto b
      left join public.os_material m
        on m.service_order_id = p_so_id
       and m.origem = case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end
       and b.src = case m.origem when 'peca' then m.service_order_part_id
                                 when 'texto_livre' then m.service_order_service_id
                                 else m.purchase_order_item_id end
    union all
    -- (2) item de OC de texto livre da OS que já chegou (saiu da conta bruta) — continua, na mão
    select 2, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, poi.quantity,
           'recebido', poi.description, null, po.supplier_id, po.received_date, m
      from public.purchase_order_items poi
      join public.purchase_orders po on po.id = poi.purchase_order_id
      left join public.os_material m on m.origem = 'oc' and m.purchase_order_item_id = poi.id
     where po.service_order_id = p_so_id and poi.product_id is null and poi.quantity > 0
       and po.status <> 'cancelled'
       and (po.status = 'received' or coalesce(poi.received_qty, 0) >= poi.quantity)
       -- FASE 4: a linha ligada a um item de texto livre da conta já está nele, no grupo 1 (os_necessidade_bruta, P2).
       and not exists (select 1 from bruto b where b.origin = 'free_text' and b.src = poi.service_order_service_id)
       -- FASE 4: fim
    union all
    -- (3) item de OC cancelada que tinha linha: a sincronização o devolveu a "falta" (ou o dono informou)
    select 3, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, 0,
           'cancelado', poi.description, null, po.supplier_id, null, m
      from public.os_material m
      join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
      join public.purchase_orders po on po.id = poi.purchase_order_id
     where m.service_order_id = p_so_id and m.origem = 'oc' and po.status = 'cancelled'
    union all
    -- (4) o que o dono citou e não está no orçamento (peça embutida, material novo)
    select 4, row_number() over (order by m.descricao, m.id), 'dono', m.service_order_service_id,
           m.quantidade_necessaria, 0, 'dono', m.descricao, null, null, null, m
      from public.os_material m
     where m.service_order_id = p_so_id and m.origem = 'dono'
  ),
  passo1 as (
    select k.*,
           coalesce((k.l).fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false) as informado,
           coalesce((k.l).critico, true) as critico
      from cand k
     where (k.l).situacao is distinct from 'dispensado'
  ),
  passo2 as (
    select q.*,
           case when q.grupo = 1
                then greatest(q.disp, case when q.informado then least(q.req, (q.l).quantidade_na_mao) else 0 end)
                else 0 end as disp_ef
      from passo1 q
  ),
  passo3 as (
    -- A situação efetiva. Só o fato informado muda o item; "na mão" só com a quantidade completa contra a conta de
    -- hoje; o que o dono disse para menos do que a OS pede hoje volta a faltar.
    select q.*,
           case
             when q.grupo = 2 then case when q.informado and (q.l).situacao <> 'na_mao' then (q.l).situacao else 'na_mao' end
             when q.grupo = 4 then (q.l).situacao
             when q.grupo = 3 then case when q.informado then (q.l).situacao else 'falta' end
             when q.disp_ef >= q.req then 'na_mao'
             when q.informado and (q.l).situacao in ('na_mao', 'comprado', 'a_caminho')
                  and (q.l).quantidade_necessaria < q.req then 'falta'
             when q.informado and (q.l).situacao = 'na_mao' then 'falta'
             when q.informado then (q.l).situacao
             when q.st = 'on_order' then 'a_caminho'
             else 'falta' end as sit
      from passo2 q
  ),
  passo4 as (
    -- A OC que cobre o item que o sistema vê "a caminho" (a da própria OS primeiro): previsão, data e fornecedor.
    select q.*, oc.expected_date as oc_prev, oc.criada as oc_criada, oc.po_number as oc_numero, oc.forn as oc_forn,
           pr.supplier_id as prod_forn
      from passo3 q
      left join public.products pr on pr.id = q.prod
      left join lateral (
        select v.expected_date, (v.po_criada_em at time zone 'America/Sao_Paulo')::date as criada, v.po_number,
               po.supplier_id as forn
          from public.v_oc_itens_a_caminho v
          join public.purchase_orders po on po.id = v.purchase_order_id
         where q.grupo = 1 and q.sit = 'a_caminho' and not q.informado and v.pendente > 0
           and case when q.origem = 'oc' then v.purchase_order_item_id = q.vinculo
                    -- FASE 4: o item de texto livre é coberto pela linha da OC ligada a ele (service_order_service_id, P2).
                    when q.origem = 'texto_livre' then v.service_order_service_id = q.vinculo
                    -- FASE 4: fim
                    else v.product_id = q.prod and v.conta_como_ja_pedido end
         order by (v.service_order_id is distinct from p_so_id), v.po_criada_em, v.purchase_order_item_id
         limit 1) oc on true
  ),
  passo5 as (
    select q.*,
           case
             when q.sit = 'na_mao' and q.grupo = 1 and q.disp >= q.req and not q.informado then 'estoque'
             when q.informado then (q.l).fonte
             when q.grupo = 2 then 'oc'
             when q.sit = 'a_caminho' and q.grupo = 1 then 'oc'
             else (q.l).fonte end as fonte,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_ate when q.grupo = 1 then q.oc_prev end end as prev_ate,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_fonte
                       when q.grupo = 1 and q.oc_prev is not null then 'oc' end end as prev_fonte,
           -- O informado sem data de compra conta do dia em que o dono contou (conferido_em): a estimativa não anda.
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado
                       then coalesce((q.l).comprado_em, ((q.l).conferido_em at time zone 'America/Sao_Paulo')::date)
                       when q.grupo = 1 then q.oc_criada end end as comprado_em,
           case when q.sit = 'falta' and q.informado then (q.l).compra_prevista_em end as compra_prevista_em,
           case when q.sit = 'na_mao' then
                  case when q.informado or q.grupo = 4 then (q.l).chegou_em
                       when q.grupo = 2 then coalesce((q.l).chegou_em, q.recebido_em)
                       when (q.l).situacao = 'na_mao' then (q.l).chegou_em end end as chegou_em,
           -- O fornecedor: o que o dono disse (cadastrado ou só o nome), senão o da OC, senão o do produto.
           case when q.informado and (q.l).fornecedor_id is null and (q.l).fornecedor_nome is not null then null
                else coalesce(case when q.informado then (q.l).fornecedor_id end, q.oc_forn, q.po_forn,
                              (q.l).fornecedor_id, q.prod_forn) end as forn_id,
           case when q.informado and (q.l).fornecedor_id is null then (q.l).fornecedor_nome end as forn_nome
      from passo4 q
  ),
  passo6 as (
    -- FASE 4: o prazo do fornecedor numa fonte só (_agenda_prazo_do_fornecedor: o que o dono disse, o cadastro repetido,
    -- o nome e a cidade/UF tolerante ao caractere quebrado); a classe, os dias úteis e os corridos saem dele no passo 7.
    select q.*, public._agenda_prazo_do_fornecedor(q.forn_id) as pf
    -- FASE 4: fim
      from passo5 q
    -- CORREÇÃO 29/10 (P5): o prazo do fornecedor uma vez por item. Sem esta barreira o planejador desmanchava o passo 6 nos de
    -- cima e copiava a chamada para cada uso de pf (a classe, os dias úteis, os corridos, o texto, a dúvida): ~25 contas de
    -- _agenda_prazo_do_fornecedor por item (~6 ms cada em produção). O resultado é o mesmo, byte a byte.
    offset 0
    -- CORREÇÃO 29/10 (P5): fim
  ),
  passo7 as (
    -- FASE 4: a classe e os dias úteis do fornecedor; o importado tem os dias corridos (e prazo nulo).
    select q.*, q.pf ->> 'classe' as classe, (q.pf ->> 'du')::int as prazo, (q.pf ->> 'corridos')::int as corridos
    -- FASE 4: fim
      from passo6 q
  ),
  passo8 as (
    select q.*,
           case
             when q.sit = 'na_mao' then 'A'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null and q.prev_fonte <> 'dono' then 'B'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then 'C'
             when q.sit in ('comprado', 'a_caminho') then 'D'
             -- FASE 4: o importado tem prazo (em dias corridos).
             when q.prazo is not null or q.corridos is not null then 'D'
             -- FASE 4: fim
             else 'E' end as nivel,
           case
             when q.sit = 'na_mao' then q.chegou_em
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then q.prev_ate
             -- FASE 4: a chegada pelo prazo do fornecedor (_agenda_chegada_pela_classe: dias úteis; o importado, os dias
             -- corridos levados ao dia útil).
             when q.sit in ('comprado', 'a_caminho') and (q.prazo is not null or q.corridos is not null) then
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos, coalesce(q.comprado_em, p_hoje))
             when q.sit = 'falta' and (q.prazo is not null or q.corridos is not null) then
               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos,
                                                  greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje))
             -- FASE 4: fim
           end as data,
           -- FASE 4: "compre até" pelo mesmo prazo; o importado: o início menos a folga, menos os dias corridos, no último dia
           -- útil até ali (agenda_somar_du(x + 1, -1) é o último dia útil até x).
           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo))
                when q.sit = 'falta' and q.corridos is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(public.agenda_somar_du(v_est_sm, -c.folga_material_du) - q.corridos + 1, -1) end as compre_ate,
           -- FASE 4: fim
           (select f.name from public.suppliers f where f.id = q.forn_id) as forn_cadastro
      from passo7 q
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', (q.l).id, 'linha', q.vinculo, 'origem', q.origem,
           'descricao', coalesce((q.l).descricao, q.descr), 'curto', public._agenda_linha_curta(coalesce((q.l).descricao, q.descr)),
           'nivel', q.nivel, 'situacao', q.sit, 'data', q.data,
           -- Parcial (parte já na mão, informada ou do estoque): quantas estão na mão e quantas faltam, antes do resto.
           'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                              then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                          replace(trim_scale(q.req)::text, '.', ','),
                                          case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                          replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                              else '' end
           || case
              when q.nivel = 'A' then case when q.data is not null then 'na mão desde ' || public._dia_curto(q.data) else 'na mão' end
              when q.nivel = 'B' then 'chega ' || public._dia_curto(q.data) || case q.prev_fonte
                   when 'oc' then ' (pela OC)' when 'fornecedor' then ' (o fornecedor disse)'
                   when 'nfe' then ' (pela nota)' when 'pix' then ' (pelo Pix)' else '' end
              when q.nivel = 'C' then 'chega ' || public._dia_curto(q.data) || ' (você disse)'
              when q.sit in ('comprado', 'a_caminho') then
                   coalesce('pedido em ' || to_char(q.comprado_em, 'DD/MM'), 'comprado')
                   || case when q.data is not null then ', deve chegar por volta de ' || public._dia_curto(q.data)
                           else ', sem previsão' end
              when q.nivel = 'D' then
                   case when q.compra_prevista_em is not null and q.compra_prevista_em >= p_hoje
                        then format('comprando %s, chega por volta de %s', public._dia_curto(q.compra_prevista_em),
                                    public._dia_curto(q.data))
                        else 'se comprar hoje, chega por volta de ' || public._dia_curto(q.data) end
              when q.forn_nome is not null then format('a comprar de %s, sem prazo conhecido', q.forn_nome)
              when q.forn_id is not null then format('a comprar de %s, sem cidade/UF no cadastro', public._agenda_nome_curto(q.forn_cadastro))
              else 'a comprar, sem fornecedor' end,
           'fonte', q.fonte, 'previsao_fonte', q.prev_fonte, 'trecho', (q.l).trecho, 'critico', q.critico,
           'quantidade', trim_scale(q.req), 'na_mao', trim_scale(case when q.sit = 'na_mao' then q.req else q.disp_ef end),
           'fornecedor', coalesce(q.forn_nome, public._agenda_nome_curto(q.forn_cadastro)),
           'classe', q.classe, 'prazo_du', q.prazo,
           -- FASE 4: o texto do prazo do fornecedor ("entrega local, 1 dia útil (pela cidade, chute meu)"), a dúvida do
           -- cadastro (duplicado | sem_lugar) e os dias corridos do importado.
           'prazo_texto', q.pf ->> 'texto', 'duvida', q.pf ->> 'duvida', 'corridos', q.corridos,
           -- FASE 4: fim
           'comprado_em', q.comprado_em, 'compra_prevista_em', q.compra_prevista_em,
           'compre_ate', q.compre_ate,
           'atrasado', q.sit in ('comprado', 'a_caminho') and q.data is not null and q.data < p_hoje,
           'sem_data', q.nivel = 'E' or (q.nivel = 'D' and q.data is null))
           -- FASE 6: (P3) a data provável do material (spec-fase6 §5.3), só no nível B (a previsão de quem vende: OC, nota,
           -- fornecedor, Pix) e só enquanto o dia dito não chegou: data = o dia dito + o atraso medido do fornecedor em uso
           -- (_agenda_aprendido: só com modo_aprendizado ligado e fornecedor na lista); data_dita = o dia dito (o fato). O
           -- atrasado e o sem_data continuam pelo dia dito (a "chegou?" é no dia da previsão); C, A, D e E não mudam. Sem
           -- atraso em uso, o item é o de antes, byte a byte.
           || case when q.nivel = 'B' and q.forn_id is not null and q.data > p_hoje then
                coalesce((select jsonb_build_object(
                            'data', public.agenda_somar_du(q.data, x.du), 'data_dita', q.data,
                            'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                                               then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                                           replace(trim_scale(q.req)::text, '.', ','),
                                                           case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                                           replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                                               else '' end
                                          || format('%s %s; %s costuma atrasar até %s: conto com %s',
                                                    case q.prev_fonte when 'oc' then 'a OC diz' when 'nfe' then 'a nota diz'
                                                                      when 'fornecedor' then 'o fornecedor disse'
                                                                      when 'pix' then 'pelo Pix, chega' else 'a previsão é' end,
                                                    public._dia_curto(q.data),
                                                    coalesce(public._agenda_nome_curto(q.forn_cadastro), 'o fornecedor'),
                                                    public._agenda_aprendizado_valor('fornecedor_atraso', x.du),
                                                    public._dia_curto(public.agenda_somar_du(q.data, x.du))))
                            from (select public._agenda_aprendido('fornecedor_atraso', q.forn_id::text)::int as du) x
                           where x.du > 0), '{}'::jsonb)
              else '{}'::jsonb end
           -- FASE 6: fim
           -- CORREÇÃO FASE 6: (C1) itens 2 e 8 (a contagem dupla e o fornecedor inativo): o bloco da Fase 6 logo acima não vale
           -- mais — as 3 chaves dele saem ("- array[…]" pega só ele: o "-" vem antes do "||") — e vale este, que é ele com duas
           -- mudanças: (item 2) a previsão da nota (nfe) já é "quando sai + quanto leva" (o prazo da classe ou o medido): não
           -- ganha o atraso do fornecedor por cima; (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida:
           -- o cadastro inativo pelo principal). Sem atraso em uso, nada muda: o item é o de antes, byte a byte.
           - array['data', 'data_dita', 'data_texto']
           || case when q.nivel = 'B' and q.forn_id is not null and q.data > p_hoje and q.prev_fonte is distinct from 'nfe' then
                coalesce((select jsonb_build_object(
                            'data', public.agenda_somar_du(q.data, x.du), 'data_dita', q.data,
                            'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                                               then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                                           replace(trim_scale(q.req)::text, '.', ','),
                                                           case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                                           replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                                               else '' end
                                          || format('%s %s; %s costuma atrasar até %s: conto com %s',
                                                    case q.prev_fonte when 'oc' then 'a OC diz' when 'nfe' then 'a nota diz'
                                                                      when 'fornecedor' then 'o fornecedor disse'
                                                                      when 'pix' then 'pelo Pix, chega' else 'a previsão é' end,
                                                    public._dia_curto(q.data),
                                                    coalesce(public._agenda_nome_curto(q.forn_cadastro), 'o fornecedor'),
                                                    public._agenda_aprendizado_valor('fornecedor_atraso', x.du),
                                                    public._dia_curto(public.agenda_somar_du(q.data, x.du))))
                            from (select public._agenda_aprendido('fornecedor_atraso',
                                                                 public._agenda_fornecedor_da_medida(q.forn_id)::text)::int as du) x
                           where x.du > 0), '{}'::jsonb)
              else '{}'::jsonb end
           -- CORREÇÃO FASE 6: fim
           order by q.grupo, q.ord), '[]'::jsonb)
    into v_itens
    from passo8 q;
  -- FASE 7: (7a P3) os itens pelas regras do gestor — um laço sobre os itens já montados, só com alguma das três regras e com
  -- itens (sem elas, nada aqui roda e o material é o de antes, byte a byte; em laço de expressões simples, e não numa consulta,
  -- porque a consulta com a conta por item custava o próprio planejamento a cada OS). Cada item recebe só o que muda:
  --   critico_por_valor (AG7-05): o fato do dono (fonte dono/fornecedor/nfe/pix) vence; sem ele, crítico = o valor unitário de
  --     venda (peça: unit_sale_snapshot; texto livre: unit_price_snapshot; OC: unit_cost; a linha do dono: nenhum) >=
  --     critico_valor_min; sem valor (ou zerado: ninguém preencheu — o custo da OC está zerado em linhas reais) = crítico. O item
  --     ganha separar_vespera (o miúdo: não crítico pela regra) e valor_unit.
  --   prazo_padrao (AG7-06): sem dias úteis nem corridos do fornecedor (sem fornecedor, ou sem cidade/UF no cadastro), o prazo é
  --     prazo_sem_fornecedor_du, a classe 'padrao' e o nível D: a falta ganha a chegada "se comprar" e o "compre até"; o comprado
  --     sem previsão, a chegada pelo dia da compra (passou = atrasado: "chegou?", como antes).
  --   compra_firme (AG7-07): a chegada "se comprar" parte de agenda_somar_du(hoje, compra_interna_du) e o "compre até" desconta
  --     o tempo interno; com o "compre até" gravado (P10) e a OS com compromisso, compre_ate = o gravado e a data = gravado +
  --     interno + prazo enquanto ele não venceu (vencido: comprando hoje). compra_firme: true no item em falta com "compre até"
  --     (ou com a compra combinada de chegada conhecida), abaixo de compre_ate_empurroes_max empurrões (_agenda_classe_da_os não o
  --     põe na condição compra). Com o teto de empurrões o item volta ao que era (reserva).
  if (v_f7_valor or v_f7_padrao or v_f7_firme) and jsonb_array_length(v_itens) > 0 then
    v_f7_novos := '[]'::jsonb;
    for v_f7_i in select t.e from jsonb_array_elements(v_itens) with ordinality t(e, o) order by t.o loop
      v_f7_m := null;
      if v_f7_i ->> 'id' is not null then
        select * into v_f7_m from public.os_material m where m.id = (v_f7_i ->> 'id')::uuid;
      end if;
      v_f7_sit_i := v_f7_i ->> 'situacao';
      v_f7_prazo := (v_f7_i ->> 'prazo_du')::int;
      v_f7_corr := (v_f7_i ->> 'corridos')::int;
      v_f7_prev := (v_f7_i ->> 'compra_prevista_em')::date;
      v_f7_inf := coalesce(v_f7_m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false);
      -- critico_por_valor
      v_f7_vu := null;
      if v_f7_valor and v_f7_i ->> 'origem' = 'peca' then
        select sp.unit_sale_snapshot into v_f7_vu from public.service_order_parts sp where sp.id = (v_f7_i ->> 'linha')::uuid;
      elsif v_f7_valor and v_f7_i ->> 'origem' = 'texto_livre' then
        select ss.unit_price_snapshot into v_f7_vu from public.service_order_services ss where ss.id = (v_f7_i ->> 'linha')::uuid;
      elsif v_f7_valor and v_f7_i ->> 'origem' = 'oc' then
        select pi.unit_cost into v_f7_vu from public.purchase_order_items pi where pi.id = (v_f7_i ->> 'linha')::uuid;
      end if;
      v_f7_vu := nullif(greatest(v_f7_vu, 0), 0);
      if v_f7_valor then
        v_f7_i := v_f7_i || jsonb_build_object(
          'critico', case when v_f7_inf then coalesce(v_f7_m.critico, true) when v_f7_vu is null then true
                          else v_f7_vu >= c.critico_valor_min end,
          'separar_vespera', not v_f7_inf and v_f7_vu is not null and v_f7_vu < c.critico_valor_min,
          'valor_unit', v_f7_vu);
      end if;
      -- prazo_padrao e compra_firme
      v_f7_pad := v_f7_padrao and v_f7_sit_i <> 'na_mao' and v_f7_i ->> 'nivel' in ('D', 'E') and v_f7_prazo is null and v_f7_corr is null;
      v_f7_fok := v_f7_firme and coalesce(v_f7_m.empurrada_vezes, 0) < c.compre_ate_empurroes_max;
      v_f7_ep := coalesce(v_f7_prazo, case when v_f7_pad then c.prazo_sem_fornecedor_du end);
      v_f7_int := case when v_f7_fok then c.compra_interna_du else 0 end;
      v_f7_grav := v_f7_fok and v_f7_comp and v_f7_sit_i = 'falta' and v_f7_prev is null and v_f7_m.compre_ate is not null
                   and v_f7_ep is not null;
      v_f7_data := case
        when v_f7_sit_i = 'falta' and v_f7_grav then
          case when v_f7_m.compre_ate >= p_hoje then public.agenda_somar_du(v_f7_m.compre_ate, v_f7_int + v_f7_ep)
               else public.agenda_somar_du(p_hoje, v_f7_ep) end
        when v_f7_sit_i = 'falta' and (v_f7_ep is not null or v_f7_corr is not null) then
          public._agenda_chegada_pela_classe(case when v_f7_pad then 'padrao' else v_f7_i ->> 'classe' end, v_f7_ep, v_f7_corr,
            case when v_f7_prev is null and v_f7_int > 0 then public.agenda_somar_du(p_hoje, v_f7_int)
                 else greatest(coalesce(v_f7_prev, p_hoje), p_hoje) end)
        when v_f7_sit_i in ('comprado', 'a_caminho') and v_f7_pad then
          public._agenda_chegada_pela_classe('padrao', v_f7_ep, null, coalesce((v_f7_i ->> 'comprado_em')::date, p_hoje)) end;
      v_f7_compre := case when v_f7_sit_i = 'falta' and v_f7_prev is null then
        case when v_f7_grav then v_f7_m.compre_ate
             when v_f7_ep is not null then public.agenda_somar_du(v_est_sm, -(c.folga_material_du + v_f7_ep + v_f7_int))
             when v_f7_corr is not null and v_f7_int > 0 then
               public.agenda_somar_du(public.agenda_somar_du(
                 public.agenda_somar_du(v_est_sm, -c.folga_material_du) - v_f7_corr + 1, -1), -v_f7_int)
             when v_f7_corr is not null then
               public.agenda_somar_du(public.agenda_somar_du(v_est_sm, -c.folga_material_du) - v_f7_corr + 1, -1) end end;
      if v_f7_pad or (v_f7_fok and v_f7_sit_i = 'falta' and v_f7_prev is null and (v_f7_ep is not null or v_f7_corr is not null)
                      and (v_f7_int > 0 or v_f7_grav)) then
        v_f7_req := (v_f7_i ->> 'quantidade')::numeric;
        v_f7_nm := (v_f7_i ->> 'na_mao')::numeric;
        v_f7_i := v_f7_i || jsonb_build_object(
          'nivel', 'D', 'data', v_f7_data, 'compre_ate', v_f7_compre,
          'classe', case when v_f7_pad then 'padrao' else v_f7_i ->> 'classe' end, 'prazo_du', v_f7_ep,
          'prazo_texto', case when not v_f7_pad then v_f7_i ->> 'prazo_texto'
                              when v_f7_i ->> 'fornecedor' is null
                                then 'sem fornecedor: contei ' || public._agenda_plural(c.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis')
                              else format('sem o prazo de %s: contei %s', v_f7_i ->> 'fornecedor',
                                          public._agenda_plural(c.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis')) end,
          'data_texto', case when v_f7_sit_i <> 'na_mao' and v_f7_nm > 0 and v_f7_nm < v_f7_req
                             then format('%s de %s na mão, %s %s: ', replace(trim_scale(v_f7_nm)::text, '.', ','),
                                         replace(trim_scale(v_f7_req)::text, '.', ','),
                                         case when v_f7_req - v_f7_nm = 1 then 'falta' else 'faltam' end,
                                         replace(trim_scale(v_f7_req - v_f7_nm)::text, '.', ','))
                             else '' end
                        || case
                           when v_f7_sit_i in ('comprado', 'a_caminho') then
                             coalesce('pedido em ' || to_char((v_f7_i ->> 'comprado_em')::date, 'DD/MM'), 'comprado')
                             || case when v_f7_data is not null then ', deve chegar por volta de ' || public._dia_curto(v_f7_data)
                                     else ', sem previsão' end
                           when v_f7_prev is not null and v_f7_prev >= p_hoje then
                             format('comprando %s, chega por volta de %s', public._dia_curto(v_f7_prev), public._dia_curto(v_f7_data))
                           when v_f7_grav and v_f7_m.compre_ate >= p_hoje then
                             format('se comprar até %s, chega por volta de %s', public._dia_curto(v_f7_m.compre_ate),
                                    public._dia_curto(v_f7_data))
                           when not v_f7_grav and v_f7_int > 0 and v_f7_sit_i = 'falta' and v_f7_prev is null
                                and (v_f7_ep is not null or v_f7_corr is not null) then
                             format('se comprar até %s, chega por volta de %s',
                                    public._dia_curto(public.agenda_somar_du(p_hoje, v_f7_int)), public._dia_curto(v_f7_data))
                           else 'se comprar hoje, chega por volta de ' || public._dia_curto(v_f7_data) end,
          'atrasado', v_f7_sit_i in ('comprado', 'a_caminho') and v_f7_data is not null and v_f7_data < p_hoje,
          'sem_data', v_f7_data is null);
      end if;
      if v_f7_fok and v_f7_sit_i = 'falta'
         and (v_f7_compre is not null or coalesce(v_f7_prev >= p_hoje and v_f7_data is not null, false)) then
        v_f7_i := v_f7_i || jsonb_build_object('compra_firme', true);
      end if;
      v_f7_novos := v_f7_novos || jsonb_build_array(v_f7_i);
    end loop;
    v_itens := v_f7_novos;
  end if;
  -- FASE 7: fim

  v_crit := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                       where (e ->> 'critico')::boolean), '[]'::jsonb);
  v_n_itens := jsonb_array_length(v_itens);
  v_conferido := p.material_conferido_em is not null
              or exists (select 1 from public.os_material m
                          where m.service_order_id = p_so_id and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'));

  -- "Tem peça embutida?": linha de texto livre que NÃO entra na compra e (a) vale >= peca_embutida_acima, ou (b) o
  -- classificador lê como material (a unidade não é 'unit'), ou (c) cita peça/material. Some quando o dono responde
  -- por ela (linha do dono ligada à linha) ou quando ele diz "não tem peça a comprar" depois que a linha nasceu.
  select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot,
                                               'curto', public._agenda_linha_curta(s.name_snapshot),
                                               'valor', s.line_total)
                            order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb)
    into v_embut
    from public.service_order_services s
   where s.service_order_id = p_so_id and s.service_id is null
     and not (s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0 and public.free_text_is_material(s.name_snapshot))
     and (coalesce(s.line_total, 0) >= c.peca_embutida_acima
          or public.free_text_is_material(s.name_snapshot)
          or public._agenda_normal(s.name_snapshot) ~ '\m(peca|pecas|material)\M')
     and not exists (select 1 from public.os_material m
                      where m.service_order_id = p_so_id and m.origem = 'dono' and m.service_order_service_id = s.id)
     and not (p.material_conferido_em is not null and p.material_conferido_em > s.created_at);
  -- FASE 7: (7a P3, regras sem_peca e embutida_suposta; D7-2) a OS sem nenhuma linha de material conta como "sem peça a comprar"
  -- (suposto, dito ao dono na restrição sem_peca_suposta, que não trava) — também quando a única dúvida é a peça embutida e a
  -- regra embutida_suposta conta que não tem; e a peça embutida em aberto não deixa o material "não conferido" (a pergunta dela
  -- fica, sem travar: "Contei que não; se tiver, me diga").
  v_f7_sem_peca := v_n_itens = 0 and not v_conferido and public._agenda_gestor_regra('sem_peca')
                   and (jsonb_array_length(v_embut) = 0 or public._agenda_gestor_regra('embutida_suposta'));
  if v_f7_sem_peca then
    v_conferido := true;
  end if;
  v_f7_embut := jsonb_array_length(v_embut) > 0 and public._agenda_gestor_regra('embutida_suposta');
  -- FASE 7: fim

  -- O estado do material (do mais forte ao mais fraco).
  v_mat_estado := case
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'atrasado')::boolean) then 'atrasado'
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'sem_data')::boolean) then 'sem_previsao'
    when jsonb_array_length(v_embut) > 0 or (v_n_itens = 0 and not v_conferido) then 'nao_conferido'
    when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
    else 'completo' end;
  -- FASE 7: (7a P3, regra embutida_suposta) a peça embutida suposta não segura o material: o estado é o que seria sem ela
  if v_f7_embut and v_mat_estado = 'nao_conferido' then
    v_mat_estado := case
      when v_n_itens = 0 and not v_conferido then 'nao_conferido'
      when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
      else 'completo' end;
  end if;
  -- FASE 7: fim

  -- DPM: a data mais tarde dos críticos fora de A; o início pelo material = chegada + folga_material_du, sem folga
  -- remota (revisão §7: o prazo "outro estado" já cobre o transporte).
  if v_mat_estado not in ('atrasado', 'sem_previsao') then
    select e into v_gargalo from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'nivel' <> 'A' order by (e ->> 'data')::date desc, o limit 1;
    v_dpm := (v_gargalo ->> 'data')::date;
    if v_dpm is not null then
      v_inicio_mat := public.agenda_somar_du(v_dpm, c.folga_material_du);
    end if;
    v_est := greatest(v_est_sm, v_inicio_mat);
    -- CORREÇÃO FASE 6: (C1) item 1: com a data provável em uso (algum crítico com data_dita), o início pelo material também
    -- pelo dia DITO (a chegada que o fornecedor, a OC, a nota ou o Pix disseram + folga_material_du). É por ele que
    -- _agenda_violacoes julga o que já está publicado: a data provável só encaixa o que é novo.
    if exists (select 1 from jsonb_array_elements(v_crit) e where e ? 'data_dita') then
      select max(coalesce(e ->> 'data_dita', e ->> 'data')::date) into v_dpm_dito
        from jsonb_array_elements(v_crit) e
       where e ->> 'nivel' <> 'A';
      v_inicio_dito := case when v_dpm_dito is not null then public.agenda_somar_du(v_dpm_dito, c.folga_material_du) end;
    end if;
    -- CORREÇÃO FASE 6: fim
  end if;
  v_confianca := (select e ->> 'nivel' from jsonb_array_elements(v_crit) e
                   order by case e ->> 'nivel' when 'E' then 0 when 'D' then 1 when 'C' then 2 when 'B' then 3 else 4 end
                   limit 1);

  -- ── Duração ──
  v_sug := public.os_duracao_sugerida(p_so_id);
  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  if p.dias is not null then
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                                 'eh_dono', py.kind = 'socio', 'turnos', e.turnos)
                              -- você primeiro; quem vai o dia todo antes de quem vai meio turno
                              order by py.kind = 'socio' desc, e.turnos = 'dia' desc, py.name, e.payee_id), '[]'::jsonb),
           -- Meios-dias por pessoa: o dia todo = 2 por dia; só de manhã ou só à tarde = 1 turno em cada dia que o
           -- serviço ocupa (meio dia com o João à tarde = 1 meio-dia; 1,5 dia à tarde = 2).
           coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0)
      into v_equipe, v_meios
      from public.os_planejamento_equipe e
      join public.payees py on py.id = e.payee_id
     where e.service_order_id = p_so_id;
    -- Sem equipe dita, a conta de diárias usa as pessoas da sugestão (é leitura, não vira número gravado). Na conta da
    -- equipe (a que a capacidade cobre), você só entra quando tem padrão.
    v_diarias_eq := case when jsonb_array_length(v_equipe) = 0
                         then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                         else (select coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0) / 2
                                 from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
                                where e.service_order_id = p_so_id
                                  and (py.kind <> 'socio' or v_dono_padrao)) end;
    v_dur := jsonb_build_object(
      'fonte', p.estimativa_fonte, 'dias', trim_scale(p.dias), 'equipe', v_equipe,
      'meios_dias', trim_scale(v_meios),
      'diarias', trim_scale(case when jsonb_array_length(v_equipe) = 0
                                 then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                                 else v_meios / 2 end),
      'diarias_equipe', trim_scale(v_diarias_eq),
      -- Diárias-pessoa da equipe para o backlog: o que o dono disse é um número só (otimista = realista).
      'dp_otimista', trim_scale(v_diarias_eq), 'dp_realista', trim_scale(v_diarias_eq),
      'equipe_dita', jsonb_array_length(v_equipe) > 0,
      'texto', public._agenda_dias(p.dias)
               || case when jsonb_array_length(v_equipe) > 0 then ': ' || public._agenda_lista(array(
                    select case when (x ->> 'eh_dono')::boolean then 'você' else x ->> 'nome' end
                           || case x ->> 'turnos' when 'dia' then ' (dia todo)' when 'manha' then ' (de manhã)'
                                                  else ' (à tarde)' end
                      from jsonb_array_elements(v_equipe) x), null) else '' end
               || case p.estimativa_fonte when 'aceita' then ' (você aceitou a minha estimativa)' else ' (você disse)' end,
      'sugestao', v_sug);
    v_dias_re := p.dias;
  else
    v_dur := jsonb_build_object(
      'fonte', 'sugerida',
      'dias', v_sug -> 'sugerida', 'dias_otimista', v_sug -> 'dias_otimista', 'dias_realista', v_sug -> 'dias_realista',
      'pessoas', v_sug -> 'pessoas', 'equipe', '[]'::jsonb, 'equipe_dita', false,
      'diarias_otimista', v_sug -> 'diarias_otimista', 'diarias_realista', v_sug -> 'diarias_realista',
      -- Diárias-pessoa da faixa (dias × pessoas) para o backlog: 74 = 3 a 6 (spec §6).
      'dp_otimista', v_sug -> 'diarias_otimista', 'dp_realista', v_sug -> 'diarias_realista',
      'sem_base', coalesce((v_sug ->> 'sem_base')::boolean, false),
      'texto', v_sug ->> 'texto', 'sugestao', v_sug);
    v_dias_re := (v_sug ->> 'dias_realista')::numeric;
  end if;
  -- FASE 7: (7a P3, regra estimativa, D7-1) sem os dias ditos, a estimativa do orçamento vale como dias firmes: a duração é a
  -- fonte 'orcamento' com os dias e o rótulo de _agenda_gestor_estimativa ("6 dias, 1 pessoa (estimativa minha, pelo valor do
  -- orçamento)"; a faixa e as diárias da sugestão ficam). Quando o gestor não a usa (situacao, grande, embutida, sem_base), a
  -- duração fica 'sugerida' e as restrições dizem por quê (logo abaixo). Os dias 'orcamento' GRAVADOS (a pergunta com prazo que
  -- venceu, P4) dizem "(estimativa minha)", nunca "(você disse)".
  if public._agenda_gestor_regra('estimativa') then
    if p.dias is null then
      v_f7_est := public._agenda_gestor_estimativa(p_so_id, p_hoje);
      v_f7_mot := v_f7_est ->> 'motivo';
      v_f7_sit := v_f7_est -> 'situacao';
      if coalesce((v_f7_est ->> 'usa')::boolean, false) then
        v_dur := v_dur || jsonb_build_object('fonte', 'orcamento', 'dias', v_f7_est -> 'dias', 'texto', v_f7_est ->> 'texto');
      end if;
    elsif p.estimativa_fonte = 'orcamento' then
      v_dur := v_dur || jsonb_build_object('texto', regexp_replace(v_dur ->> 'texto', ' \(você disse\)$', ' (estimativa minha)'));
    end if;
  end if;
  -- FASE 7: fim

  v_pres := public.os_presenca_do_dono(p_so_id);

  -- ── Prazo e razão crítica ──
  v_prazo := coalesce(p.precisa_ate, public.agenda_somar_du(v_aprov, c.prazo_padrao_du));
  v_prazo_fnt := case when p.precisa_ate is not null then 'dono' else 'padrão' end;
  if v_dias_re is not null and v_dias_re > 0 then
    v_razao := round(greatest(public.agenda_du_entre(p_hoje, v_prazo), 0) / v_dias_re, 2);
  end if;

  -- ── Execução: parada = em andamento sem diária ligada nos últimos parada_du úteis e sem janela futura ──
  if so.status = 'in_progress' then
    select max(ws.data) into v_ult_diaria
      from public.work_shifts ws
     where ws.data <= p_hoje and ws.tipo in ('normal', 'diaria') and coalesce(ws.fracao, 1) > 0
       and (ws.service_order_id = p_so_id
            or exists (select 1 from public.work_shift_os x where x.shift_id = ws.id and x.service_order_id = p_so_id));
    v_parada := (v_ult_diaria is null or v_ult_diaria < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false;
  end if;
  -- FASE 2: (1) a evidência de que a OS andou é a maior entre a última diária ligada, o último meio-dia do plano
  -- cumprido ou parcial e o check-in; (2) com dia no plano de hoje em diante a OS em andamento nunca é parada.
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_tem_futuro := coalesce((v_plano ->> 'proximo_dia')::date >= p_hoje, false);
  v_ult_evid := public._agenda_ultima_evidencia(p_so_id, p_hoje);
  if so.status = 'in_progress' then
    v_parada := (v_ult_evid is null or v_ult_evid < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false
                and not v_tem_futuro;
  end if;
  -- FASE 2: fim

  -- ── Restrições: {tipo, quem, texto, bloqueia, desde, compre_ate, pergunta} ──
  if so.status = 'draft' and so.quote_status = 'approved' and so.merged_into_id is null then
    v_r := v_r || jsonb_build_object('tipo', 'orcamento', 'quem', 'dono', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', 'converter em OS ou arquivar?',
      'texto', format('%s em %s e nunca virou OS: converter ou arquivar?',
                      case when so.signed_at is not null then 'assinado' else 'aprovado' end, to_char(v_aprov, 'DD/MM')));
  end if;
  if (so.quote_status = 'awaiting_deposit' and v_pago = 0) or v_pend > 0 then
    v_r := v_r || jsonb_build_object('tipo', 'sinal', 'quem', 'cliente', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_pend > 0 then 'esperando o sinal de ' || public._brl(v_pend) else 'esperando o sinal' end);
  end if;
  if so.status = 'awaiting_client' then
    v_r := v_r || jsonb_build_object('tipo', 'cliente', 'quem', 'cliente', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', null, 'texto', 'esperando o cliente');
  end if;
  if p.escopo_em_aberto is not null then
    v_r := v_r || jsonb_build_object('tipo', 'escopo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', p.escopo_em_aberto, 'texto', p.escopo_em_aberto);
  end if;
  if p.dias is null then
    v_r := v_r || jsonb_build_object('tipo', 'duracao', 'quem', 'dono', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', 'quantos dias e com quem?',
      'texto', case when coalesce((v_sug ->> 'sem_base')::boolean, false)
                    then 'quantos dias e com quem? (o orçamento não dá base para estimar)'
                    else format('quantos dias e com quem? (chute: %s, %s)',
                                public._agenda_faixa_dias((v_sug ->> 'dias_otimista')::numeric, (v_sug ->> 'dias_realista')::numeric),
                                case when (v_sug ->> 'pessoas')::int = 1 then '1 pessoa'
                                     else (v_sug ->> 'pessoas') || ' pessoas' end) end);
  end if;
  -- FASE 7: (7a P3, regras estimativa e situacao) com a estimativa em uso, "quantos dias?" não nasce (a duração já é a do
  -- orçamento); quando o gestor pergunta antes, a restrição diz o que ele faz sem resposta (o prazo é o da pergunta, P4: a conta
  -- da prontidão não lê a pergunta); a OS começada ou parada (AG7-11) ganha a restrição situacao, que trava (o texto de
  -- _agenda_os_situacao). Com a OS presa antes por orçamento, cliente ou escopo (a Kalmar, com check-in em junho, espera o
  -- cliente), o gestor não pergunta nem marca: nada disso é dito.
  if v_f7_est is not null then
    if coalesce((v_f7_est ->> 'usa')::boolean, false) then
      v_r := (select coalesce(jsonb_agg(e order by o), '[]'::jsonb)
                from jsonb_array_elements(v_r) with ordinality t(e, o) where e ->> 'tipo' <> 'duracao');
    elsif v_f7_mot in ('situacao', 'grande', 'embutida', 'sem_base')
          and not exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'cliente', 'escopo')) then
      v_f7_txt := case v_f7_mot
        when 'situacao' then
          -- (7a correção, achado 20) acima do teto de diárias, o gestor espera o dono (sem prazo)
          case when coalesce((v_f7_sit ->> 'sem_padrao')::boolean, false)
                 then format('perguntei antes de marcar: pelo orçamento são %s diárias, mais de %s, então espero você',
                             public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(c.estimativa_max_diarias))
               when v_f7_sit ->> 'tipo' = 'parada'
                 then format('perguntei se ainda é para fazer o serviço inteiro; sem resposta, conto %s',
                             public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric))
               when coalesce((v_f7_sit ->> 'rastro')::boolean, false)
                 then format('perguntei quanto falta; sem resposta, marco %s para terminar',
                             public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric))
               else format('perguntei se já começou; sem resposta, conto %s', public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric)) end
        when 'grande' then
          -- (7a correção, achado 20) acima do teto de diárias, sem prazo: o gestor espera o dono
          format('pelo valor do orçamento são %s diárias, mais de %s: perguntei antes de marcar e espero você dizer os dias',
                 public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(c.estimativa_max_diarias))
        when 'embutida' then
          format('pode ter peça junto em "%s": perguntei antes de marcar; sem resposta, marco %s',
                 v_f7_est #>> '{embutida,0,curto}', public._agenda_dias((v_f7_est ->> 'proposta_dias')::numeric))
        else
          format('o orçamento não tem mão de obra separada: perguntei quantos dias; sem resposta, marco %s',
                 public._agenda_dias((v_f7_est ->> 'proposta_dias')::numeric)) end;
      -- (7a correção, achado 24) enquanto o gestor espera a resposta (ou o prazo), a duração trava: a OS não é "pronta para
      -- começar" no painel, no *livre* e no "Amanhã" do fechamento se o gestor não a marca
      v_r := (select coalesce(jsonb_agg(case when e ->> 'tipo' = 'duracao'
                                             then e || jsonb_build_object('texto', v_f7_txt, 'bloqueia', true) else e end
                                        order by o), '[]'::jsonb)
                from jsonb_array_elements(v_r) with ordinality t(e, o));
      if v_f7_mot = 'situacao' then
        v_r := v_r || jsonb_build_object('tipo', 'situacao', 'quem', 'dono', 'bloqueia', true, 'desde', v_f7_sit -> 'desde',
          'compre_ate', null,
          'pergunta', case when v_f7_sit ->> 'tipo' = 'parada' then 'ainda é para fazer o serviço inteiro?'
                           when coalesce((v_f7_sit ->> 'rastro')::boolean, false) then 'quanto falta?'
                           else 'o serviço já começou?' end,
          'texto', v_f7_sit ->> 'texto');
      end if;
    end if;
  end if;
  -- FASE 7: fim
  -- Com peça embutida em aberto, a pergunta dela já é o "tem peça a comprar?" (mais precisa): não repete.
  if v_n_itens = 0 and not v_conferido and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'material_nao_conferido', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', 'tem peça a comprar?', 'texto', 'tem peça a comprar? (o orçamento não tem nenhuma)');
  end if;
  -- FASE 7: (7a P3, regra sem_peca) a OS sem peça a comprar (suposto): dito ao dono, sem travar
  if v_f7_sem_peca and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'sem_peca_suposta', 'quem', 'dono', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null, 'texto', 'marquei sem peça a comprar; se precisar, me diga');
  end if;
  -- FASE 7: fim
  v_n := jsonb_array_length(v_embut);
  if v_n > 0 then
    v_txt := array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' ou ')
             || case when v_n > 2 then format(' (e mais %s)', v_n - 2) else '' end;
    v_r := v_r || jsonb_build_object('tipo', 'peca_embutida', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', format('tem peça embutida em %s?', v_txt),
      'texto', format('tem peça embutida em %s?', v_txt));
  end if;
  -- FASE 7: (7a P3, regra embutida_suposta) a peça embutida em aberto não trava: "Contei que não; se tiver, me diga"
  if v_f7_embut then
    v_r := (select coalesce(jsonb_agg(case when e ->> 'tipo' = 'peca_embutida'
                                           then e || jsonb_build_object('bloqueia', false,
                                                                        'texto', format('tem peça embutida em %s? Contei que não; se tiver, me diga', v_txt))
                                           else e end order by o), '[]'::jsonb)
              from jsonb_array_elements(v_r) with ordinality t(e, o));
  end if;
  -- FASE 7: fim

  -- O que falta comprar: sem fornecedor/classe (E) pergunta "de quem e quando?"; com classe e sem compra combinada,
  -- "compre até" (programação para trás; se já passou, "comprando hoje, chega por volta de …"). A compra que o dono já
  -- combinou (dia que ainda não passou) sem prazo conhecido NÃO volta a perguntar "de quem e quando": vai à parte.
  select count(*) filter (where e ->> 'situacao' = 'falta'
                          and (((e ->> 'sem_data')::boolean and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
                               or e ->> 'compre_ate' is not null)),
         count(*) filter (where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean
                          and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
    into v_n_falta, v_n_sem
    from jsonb_array_elements(v_crit) e;
  if v_n_falta > 0 then
    select e into v_compra from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'situacao' = 'falta' and e ->> 'compre_ate' is not null
     order by (e ->> 'compre_ate')::date, o limit 1;
    v_cond := case when v_compra is null then ''
                   when (v_compra ->> 'compre_ate')::date < p_hoje then
                     format('comprando hoje, "%s" chega por volta de %s', v_compra ->> 'curto',
                            -- FASE 4: a chegada "comprando hoje" pelo mesmo prazo do fornecedor (o importado em corridos).
                            public._dia_curto(public._agenda_chegada_pela_classe(v_compra ->> 'classe', (v_compra ->> 'prazo_du')::int,
                                                                                 (v_compra ->> 'corridos')::int, p_hoje)))
                            -- FASE 4: fim
                   else format('"%s": compre até %s', v_compra ->> 'curto',
                               public._dia_curto((v_compra ->> 'compre_ate')::date)) end;
    if v_n_sem > 0 then
      v_txt := case when so.status = 'awaiting_parts' then public._agenda_itens(v_n_falta) || ' sem compra registrada'
                    else public._agenda_itens(v_n_falta) || ' a comprar: de quem e quando?' end;
      v_r := v_r || jsonb_build_object('tipo', 'sem_previsao', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate',
        'pergunta', case when so.status = 'awaiting_parts' then 'o que já está na mão e o que falta? Quando chega?'
                         else format('o material (%s) — compra quando e onde?', public._agenda_itens(v_n_falta)) end,
        'texto', v_txt || case when v_cond <> '' then ' (' || v_cond || ')' else '' end);
    else
      v_r := v_r || jsonb_build_object('tipo', 'compre_ate', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate', 'pergunta', 'compra quando?',
        'texto', public._agenda_itens(v_n_falta) || ' a comprar: ' || v_cond);
    end if;
  end if;

  -- Compra combinada ("compro terça na Casa do Eletricista") sem prazo de entrega conhecido: o que o dono já disse fica
  -- dito; a pergunta é só o que falta — quando chega (com fornecedor) ou de quem (sem).
  select count(*) as n, min((e ->> 'compra_prevista_em')::date) as de, max((e ->> 'compra_prevista_em')::date) as ate,
         bool_and(e ->> 'fornecedor' is not null) as com_forn, count(distinct e ->> 'fornecedor') as n_forn,
         min(e ->> 'fornecedor') as forn, min(e ->> 'curto') as curto
    into v_cc
    from jsonb_array_elements(v_crit) e
   where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean and (e ->> 'compra_prevista_em')::date >= p_hoje;
  if v_cc.n > 0 then
    v_txt := case when v_cc.de = v_cc.ate then public._dia_curto(v_cc.de)
                  else format('de %s a %s', public._dia_curto(v_cc.de), public._dia_curto(v_cc.ate)) end;
    v_r := v_r || jsonb_build_object('tipo', 'compra_sem_prazo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null,
      'pergunta', case when v_cc.com_forn then format('quando chega a compra de %s?', v_txt)
                       else format('de quem é a compra de %s?', v_txt) end,
      'texto', case when v_cc.n = 1 then format('"%s"', v_cc.curto) else public._agenda_itens(v_cc.n::int) end
               || ': você compra ' || v_txt
               || case when v_cc.com_forn and v_cc.n_forn = 1 then ', fornecedor ' || v_cc.forn else '' end
               || case when v_cc.com_forn then '; sem prazo de entrega conhecido: quando chega?'
                       else '; de quem? (sem o fornecedor não sei quando chega)' end);
  end if;

  -- Comprado sem previsão e sem classe: "chegou?"; previsão vencida: "venceu em dd/mm: chegou?".
  for v_x in select e from jsonb_array_elements(v_crit) with ordinality t(e, o)
              where e ->> 'situacao' in ('comprado', 'a_caminho')
                and ((e ->> 'sem_data')::boolean or (e ->> 'atrasado')::boolean)
              order by o
  loop
    if (v_x ->> 'atrasado')::boolean then
      v_r := v_r || jsonb_build_object('tipo', 'atrasado', 'quem', 'dono', 'bloqueia', true, 'desde', v_x ->> 'data',
        'compre_ate', null, 'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('a previsão de "%s" venceu em %s: chegou?', v_x ->> 'curto', to_char((v_x ->> 'data')::date, 'DD/MM')));
    else
      v_r := v_r || jsonb_build_object('tipo', 'comprado_sem_previsao', 'quem', 'dono', 'bloqueia', true,
        'desde', v_x ->> 'comprado_em', 'compre_ate', null,
        'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('"%s" (%s) chegou?', v_x ->> 'curto',
                        coalesce('pedido em ' || to_char((v_x ->> 'comprado_em')::date, 'DD/MM'), 'comprado, sem previsão')));
    end if;
  end loop;

  if v_d_bem is null or v_d_bem > p_hoje + 1 then
    v_r := v_r || jsonb_build_object('tipo', 'bem', 'quem', 'cliente', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                    else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end);
  end if;
  if p.nao_antes_de is not null and p.nao_antes_de > p_hoje then
    v_r := v_r || jsonb_build_object('tipo', 'nao_antes', 'quem', 'terceiro', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo));
  end if;
  if v_parada then
    v_r := v_r || jsonb_build_object('tipo', 'parada', 'quem', 'dono', 'bloqueia', true, 'desde', v_ult_diaria,
      'compre_ate', null, 'pergunta', 'parou?',
      'texto', case when v_ult_diaria is null then 'em andamento e sem diária lançada: parou?'
                    else format('em andamento sem diária desde %s: parou?', to_char(v_ult_diaria, 'DD/MM')) end);
  end if;

  -- Orçamento aprovado que nunca virou OS, ou sinal pendente: quem destrava é a conversão (o dono) ou o sinal (o
  -- cliente), não a compra — comprar peça de um orçamento que pode ser arquivado não é o próximo passo. As perguntas do
  -- material continuam na lista (a visão da OS e a rodada mostram), sem travar até a conversão e o sinal.
  if exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'sinal')) then
    select coalesce(jsonb_agg(case when e ->> 'tipo' in ('atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao',
                                                         'compre_ate', 'peca_embutida', 'material_nao_conferido')
                                   then jsonb_set(e, '{bloqueia}', 'false'::jsonb) else e end order by o), '[]'::jsonb)
      into v_r
      from jsonb_array_elements(v_r) with ordinality t(e, o);
  end if;

  -- A mais forte primeiro: o que trava antes do que só informa, e na ordem do bloco "travado" (spec §5.4).
  select coalesce(jsonb_agg(e order by (e ->> 'bloqueia')::boolean desc,
           array_position(array['parada', 'atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                                'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal', 'cliente',
                                'duracao', 'bem', 'nao_antes'], e ->> 'tipo'), o), '[]'::jsonb)
    into v_r
    from jsonb_array_elements(v_r) with ordinality t(e, o);
  -- FASE 7: (7a P3) as restrições novas do gestor no lugar delas: a situação e o "sem peça" logo depois da duração (a ordem de
  -- cima, com as duas; sem elas, nada muda)
  if exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('situacao', 'sem_peca_suposta')) then
    select coalesce(jsonb_agg(e order by (e ->> 'bloqueia')::boolean desc,
             array_position(array['parada', 'atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                                  'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal', 'cliente',
                                  'duracao', 'situacao', 'sem_peca_suposta', 'bem', 'nao_antes'], e ->> 'tipo'), o), '[]'::jsonb)
      into v_r
      from jsonb_array_elements(v_r) with ordinality t(e, o);
  end if;
  -- FASE 7: fim

  -- ── Estado (o 1º que valer) ──
  v_estado := case
    when p.congelada_ate is not null and p.congelada_ate >= p_hoje then 'congelada'
    when so.status in ('completed', 'invoiced') then 'concluida'
    when so.status = 'cancelled' or so.merged_into_id is not null
         or (so.status = 'draft' and coalesce(so.quote_status, 'draft') not in ('approved', 'awaiting_deposit')) then 'fora_da_carteira'
    when so.status = 'in_progress' then case when v_parada then 'parada' else 'em_execucao' end
    when coalesce(v_ag_ate, v_ag_de) >= p_hoje then 'marcada'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
    when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
    when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
    else 'pronta' end;
  -- FASE 2: (3) os estados do plano: fixada e programada vêm depois de em execução/parada e antes de marcada; com a
  -- agenda automática ligada a janela antiga é o espelho do plano, e "marcada" não vale (o estado vem das alocações).
  if v_estado not in ('congelada', 'concluida', 'fora_da_carteira', 'em_execucao', 'parada') then
    if coalesce((v_plano ->> 'fixada')::boolean, false) then
      v_estado := 'fixada';
    elsif v_tem_futuro then
      v_estado := 'programada';
    elsif v_estado = 'marcada' and c.modo_proposta = 'ligado' then
      v_estado := case
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
        when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
        when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
        else 'pronta' end;
    end if;
  end if;
  -- FASE 2: fim

  -- FASE 7: (7a correção, achado 24) a OS que o gestor pergunta antes de marcar (a situação, ou a duração que ele não estima
  -- sozinho: a restrição situacao ou duracao que trava, que só nasce com as regras do gestor) espera o dono: não é "pronta para
  -- começar" (o "Amanhã" do fechamento, o *livre* e o painel diziam "prontos: Nelson, Giancarlo" enquanto ele perguntava)
  if v_estado = 'pronta' and exists (select 1 from jsonb_array_elements(v_r) e
                                      where e ->> 'tipo' in ('situacao', 'duracao') and coalesce((e ->> 'bloqueia')::boolean, false)) then
    v_estado := 'esperando_voce';
  end if;
  -- FASE 7: fim
  if v_estado in ('concluida', 'fora_da_carteira') and (so.status in ('completed', 'invoiced', 'cancelled')
                                                         or so.merged_into_id is not null) then
    v_r := '[]'::jsonb;
  end if;

  -- A restrição do dono que mais pesa (a 1ª da lista que trava e é dele).
  select e into v_principal from jsonb_array_elements(v_r) with ordinality t(e, o)
   where (e ->> 'bloqueia')::boolean and e ->> 'quem' = 'dono' order by o limit 1;

  v_quase := v_estado = 'aguardando_material'
         and (select count(*) from jsonb_array_elements(v_r) e where (e ->> 'bloqueia')::boolean) = 1
         and v_principal ->> 'tipo' = 'material_nao_conferido';

  -- O texto do estado, para vir depois do nome do cliente ("Lenine: falta você dizer se tem peça a comprar").
  v_estado_txt := case v_estado
    -- "(rever …)" só quando o dia de rever não é o mesmo do fim da espera (é o padrão do rascunho).
    when 'congelada' then 'em espera até ' || public._dia_curto(p.congelada_ate)
                          || case when p.revisar_em is distinct from p.congelada_ate
                                  then coalesce(' (rever ' || public._dia_curto(p.revisar_em) || ')', '') else '' end
    when 'concluida' then case so.status when 'invoiced' then 'faturado' else 'concluído' end
    when 'fora_da_carteira' then public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, so.juntado_em, false)
    when 'em_execucao' then 'em andamento'
    when 'parada' then case when v_ult_diaria is null then 'em andamento e sem diária lançada'
                            else 'em andamento sem diária desde ' || to_char(v_ult_diaria, 'DD/MM') end
    when 'marcada' then case when v_ag_de is null or v_ag_de = v_ag_ate then 'marcado para ' || public._dia_curto(coalesce(v_ag_ate, v_ag_de))
                             else format('marcado de %s a %s', public._dia_curto(v_ag_de), public._dia_curto(v_ag_ate)) end
    when 'sem_sinal' then (select e ->> 'texto' from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal' limit 1)
    when 'aguardando_cliente' then case
      when so.status = 'awaiting_client' then 'esperando o cliente'
      when v_bem_tudo then case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                                else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end
      else format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo) end
    -- O orçamento parado vem antes do escopo em aberto (a ordem do bloco "travado").
    when 'esperando_voce' then case
      when so.status = 'draft' and so.quote_status = 'approved'
        then format('%s em %s e nunca virou OS', case when so.signed_at is not null then 'assinado' else 'aprovado' end,
                    to_char(v_aprov, 'DD/MM'))
      else 'falta você decidir: ' || p.escopo_em_aberto end
    when 'aguardando_material' then case v_principal ->> 'tipo'
      when 'atrasado' then 'falta você dizer se ' || replace(v_principal ->> 'pergunta', ' chegou?', '') || ' chegou (a previsão venceu)'
      when 'sem_previsao' then case when so.status = 'awaiting_parts'
                                    then format('falta você dizer o que já está na mão e o que falta (%s sem compra registrada)',
                                                public._agenda_itens(v_n_falta))
                                    else 'falta você dizer de quem e quando comprar ' || public._agenda_itens(v_n_falta) end
      when 'comprado_sem_previsao' then 'falta você dizer se ' || replace(v_principal ->> 'texto', ' chegou?', '') || ' chegou'
      when 'compra_sem_prazo' then 'falta você dizer ' || rtrim(v_principal ->> 'pergunta', '?')
      when 'peca_embutida' then 'falta você dizer se tem peça embutida em '
                                || array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' e ')
                                || case when jsonb_array_length(v_embut) > 2
                                        then format(' (e mais %s)', jsonb_array_length(v_embut) - 2) else '' end
      else 'falta você dizer se tem peça a comprar' end
    else -- pronta
      case when v_est is not null and v_est > public.agenda_somar_du(p_hoje, 1) then
             'pronto a partir de ' || public._dia_curto(v_est)
             || case when v_inicio_mat is not null and v_inicio_mat >= v_est_sm then
                  (select case
                        when e ->> 'nivel' in ('B', 'C') then format(', se "%s" chegar %s', e ->> 'curto', public._dia_curto(v_dpm))
                        when e ->> 'situacao' = 'falta' and e ->> 'compra_prevista_em' is not null
                             and (e ->> 'compra_prevista_em')::date >= p_hoje
                          then ', se a compra sair ' || public._dia_curto((e ->> 'compra_prevista_em')::date)
                        when e ->> 'situacao' = 'falta' then ', se comprar hoje'
                        else format(', se "%s" chegar por volta de %s', e ->> 'curto', public._dia_curto(v_dpm)) end
                        from jsonb_array_elements(v_crit) with ordinality t(e, o)
                       where e ->> 'nivel' <> 'A' and (e ->> 'data')::date = v_dpm order by o limit 1)
                else '' end
           else 'pronto para começar' end
  end;
  -- FASE 2: o texto dos estados do plano ("marcado de ter 03/11 a qui 05/11", "(fixado)" quando é fixo).
  if v_estado in ('fixada', 'programada') then
    v_estado_txt := case when (v_plano ->> 'proximo_dia') = (v_plano ->> 'ultimo_dia')
                         then 'marcado para ' || public._dia_curto((v_plano ->> 'proximo_dia')::date)
                         else format('marcado de %s a %s', public._dia_curto((v_plano ->> 'proximo_dia')::date),
                                     public._dia_curto((v_plano ->> 'ultimo_dia')::date)) end
                    || case when v_estado = 'fixada' then ' (fixado)' else '' end;
  end if;
  -- FASE 2: fim

  -- FASE 2: (4) a saída ganha o plano (null sem alocação) e a última evidência; ultima_diaria continua.
  return jsonb_build_object('plano', v_plano, 'ultima_evidencia', v_ult_evid) || jsonb_build_object(
  -- FASE 2: fim
    'ok', true, 'os', so.id, 'numero', so.service_order_number, 'cliente', so.cliente_nome,
    'cliente_curto', public._agenda_nome_curto(so.cliente_nome), 'unidade', so.bem,
    'eh_orcamento', so.status = 'draft', 'status', so.status, 'quote_status', so.quote_status,
    'na_carteira', v_na_cart, 'aprovada_em', v_aprov,
    'estado', v_estado, 'estado_texto', v_estado_txt, 'quase_pronta', v_quase,
    'restricoes', v_r,
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em),
    -- CORREÇÃO FASE 6: (C1) item 1: a chave material de cima, com inicio_mat_dito quando o dia dito dá outro início (só com
    -- a data provável em uso; sem ela, o material é o de antes, byte a byte). A última chave igual do objeto vale.
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em)
      || case when v_inicio_dito is not null and v_inicio_dito is distinct from v_inicio_mat
              then jsonb_build_object('inicio_mat_dito', v_inicio_dito) else '{}'::jsonb end,
    -- CORREÇÃO FASE 6: fim
    'duracao', v_dur,
    'presenca_dono', v_pres,
    'est', v_est, 'est_texto', public._dia_curto(v_est), 'est_sem_material', v_est_sm,
    'prazo_efetivo', v_prazo, 'prazo_texto', public._dia_curto(v_prazo), 'prazo_fonte', v_prazo_fnt,
    'razao_critica', v_razao,
    'marcada', case when v_ag_de is not null or v_ag_ate is not null
                    then jsonb_build_object('de', v_ag_de, 'ate', v_ag_ate) end,
    'ultima_diaria', v_ult_diaria);
end;
$function$;

comment on function public.os_prontidao(uuid, date) is
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P2: a linha de OC recebida ligada a um item de texto livre da conta conta só nele, não de novo como item da OC que já chegou; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira. Fase 6 (P3): no item de nível B, enquanto o dia dito não chegou e com o atraso do fornecedor em uso (fornecedor_atraso: _agenda_aprendido), data = a data provável (o dia dito + o atraso; é ela que move o DPM, o início pelo material e o motor), data_dita = o dia dito (o fato) e data_texto "a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11"; atrasado e sem_data continuam pelo dia dito (a "chegou?"); C, A, D e E não mudam; sem atraso em uso, o item é o de antes. CORREÇÃO FASE 6 (C1): (item 1) material.inicio_mat_dito = o início pelo material pelo dia DITO (sem o atraso do fornecedor), só quando a data provável muda o início — _agenda_violacoes julga por ele o que já está publicado; (item 2) a previsão da nota (nfe) não ganha o atraso do fornecedor (já é saída + prazo); (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida: o inativo pelo principal). Sem atraso em uso, a saída é a de antes, byte a byte. CORREÇÃO 29/10 (P5): (1) o prazo do fornecedor uma vez por item (a barreira no passo 6; antes ~25 contas por item); (2) dentro da rodada da vigia (agenda.rodada), o resultado de cada OS é lembrado (_agenda_rodada_lembrar e _agenda_rodada_guardar), enquanto a transação não grava nada no que ela lê. O resultado é o mesmo, byte a byte. FASE 7 (7a P3), atrás do portão _agenda_gestor_regra (falso = a saída de antes, byte a byte): critico_por_valor (AG7-05) — sem o fato do dono, o item é crítico só com o valor unitário de venda >= critico_valor_min (sem valor = crítico), e ganha separar_vespera e valor_unit; prazo_padrao (AG7-06) — sem prazo do fornecedor, prazo_sem_fornecedor_du dias úteis, classe padrao, nível D ("sem fornecedor: contei 7 dias úteis"; o comprado sem previsão chega pelo dia da compra); compra_firme (AG7-07) — a chegada "se comprar" e o "compre até" contam compra_interna_du; o "compre até" gravado (os_material.compre_ate) da OS com compromisso segura a data enquanto não vence; o item em falta com "compre até" (ou compra combinada com chegada) abaixo de compre_ate_empurroes_max ganha compra_firme; sem_peca — a OS sem linha de material conta como sem peça (restrição sem_peca_suposta, que não trava); embutida_suposta — a peça embutida não trava ("Contei que não; se tiver, me diga") nem deixa o material não conferido; estimativa (D7-1) — sem os dias ditos e com _agenda_gestor_estimativa em uso, a duração é a fonte orcamento e a restrição duracao não nasce; sem usar (situacao, grande, embutida, sem_base), a restrição duracao diz o que o gestor faz sem resposta; os dias orcamento gravados dizem "(estimativa minha)"; situacao (AG7-11) — a restrição situacao, que trava (o texto de _agenda_os_situacao). CORREÇÃO DA 7a (revisão da etapa), no bloco da 7a P3 e num bloco novo: (achado 20) acima de estimativa_max_diarias, a restrição duracao e a situação dizem que o gestor perguntou e espera o dono (sem "sem resposta, marco"); (achado 24) enquanto o gestor pergunta antes de marcar (situacao, grande, sem_base), a restrição duracao trava (bloqueia) e a OS que seria pronta fica esperando_voce: não aparece como pronta para começar no painel, no *livre* e no "Amanhã". Com o portão falso, a de antes, byte a byte.';

-- agenda_aviso_pecas (de 20261030100500_agenda_correcao_revisao.sql)
create or replace function public.agenda_aviso_pecas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_m     jsonb;
  v_n     int;
  v_jan   text;
  v_props uuid[];
  v_oss   uuid[];
  v_fora  jsonb;
  v_apr   jsonb;
  v_numos text[];
  v_voce  boolean;
  v_perg  jsonb;
  v_perr  text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aviso_pecas: sem o dia ou a hora' using errcode = '22023';
  end if;
  if not public._agenda_aviso_ligado() then
    return jsonb_build_object('avisar', false,
      'motivo', case when cf.modo_proposta = 'ligado' and cf.modo_vigia = 'ligado' then 'desligado' else 'modo' end);
  end if;
  v_m := public._agenda_aviso_mudancas(p_hoje);
  v_n := jsonb_array_length(v_m);
  if v_n = 0 then
    return jsonb_build_object('avisar', false, 'motivo', 'nada_mudou');
  end if;
  v_jan := public._agenda_aviso_fora_da_janela(p_agora, p_agora);
  if v_jan is not null then
    return jsonb_build_object('avisar', false, 'motivo', 'fora_da_janela', 'janela', v_jan, 'pendentes', v_n);
  end if;
  -- CORREÇÃO 29/10 (revisão): o aviso não corre com o fechamento das 17:30. O fechamento lê a agenda no começo e só
  -- registra o que mostrou depois de enfileirar; o aviso do mesmo minuto contava as mesmas mudanças no meio (duas mensagens
  -- com a mesma mudança). De segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, o aviso espera: o que
  -- estiver por contar vai no fechamento, e o resto sai no 1º aviso depois da pausa.
  if public._agenda_aviso_espera_o_fechamento(p_agora) then
    return jsonb_build_object('avisar', false, 'motivo', 'fechamento', 'pendentes', v_n);
  end if;
  -- CORREÇÃO 29/10 (revisão): fim
  if public._agenda_aviso_no_dia((p_agora at time zone 'America/Sao_Paulo')::date, null) >= cf.gestor_aviso_dia_max then
    return jsonb_build_object('avisar', false, 'motivo', 'teto', 'pendentes', v_n);
  end if;
  if not exists (select 1 from public._agenda_aviso_dono()) then
    return jsonb_build_object('avisar', false, 'motivo', 'sem_dono', 'pendentes', v_n);
  end if;

  -- o que ficou de fora: o fora das propostas das mudanças (a de cada OS pela proposta mais nova), sem as OS que mudaram
  v_props := array(select distinct x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'propostas') x);
  v_oss := array(select distinct x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'os') x);
  select coalesce(jsonb_agg(y.f order by y.ord, y.o), '[]'::jsonb) into v_fora
    from (select distinct on (coalesce(t.f ->> 'os', t.f ->> 'numero')) t.f, t.o, t.ord
            from (select f, o, dense_rank() over (order by p.criada_em desc, p.id) as ord
                    from public.agenda_propostas p
                    cross join lateral jsonb_array_elements(p.fora) with ordinality u(f, o)
                   where p.id = any (v_props)) t
           order by coalesce(t.f ->> 'os', t.f ->> 'numero'), t.ord, t.o) y;

  -- as perguntas que destravam: a rodada de aprontar, uma vez por dia. Se ela falhar, o que mudou sai do mesmo jeito e o erro
  -- volta em perguntas_erro (o passo do motor o registra em app_error_logs: nunca calado)
  if not exists (select 1 from public.agenda_dono_avisos v
                  where v.dia = p_hoje and v.com_perguntas and v.fila_id is not null and v.devolvida_em is null) then
    begin
      v_apr := public.agenda_aprontar(p_hoje);
    exception when others then
      v_perr := left(sqlstate || ': ' || sqlerrm, 300);
      v_apr := null;
    end;
    v_numos := array(select jsonb_array_elements_text(coalesce(v_apr #> '{dados,oss}', '[]'::jsonb)));
    v_voce := coalesce((v_apr #>> '{dados,voce}')::boolean, false);
    if coalesce((v_apr ->> 'ok')::boolean, false) and (cardinality(v_numos) > 0 or v_voce) then
      v_perg := jsonb_build_object(
        'texto', v_apr ->> 'texto', 'oss', to_jsonb(v_numos), 'voce', v_voce,
        'pergunta_ids', to_jsonb(array(
          select q.id from public.agenda_perguntas q
            left join public.service_orders so on so.id = q.service_order_id
           where q.estado = 'aberta' and q.modo = 'ligado'
             and ((q.tipo in ('material_conferir', 'duracao', 'chegou') and so.service_order_number = any (v_numos))
                  -- FASE 7: (7a correção, achado 15) as perguntas do gestor das OS que o texto cobre (a restrição da OS diz o que
                  -- ele faz sem resposta: "Perguntei se já começou; sem resposta, conto 4 dias"): o aviso que sai as conta como mostradas
                  or (q.tipo in ('situacao', 'estimativa') and so.service_order_number = any (v_numos))
                  -- FASE 7: fim
                  or (q.tipo = 'padrao_do_dono' and v_voce))
           order by q.criada_em, q.id)));
    end if;
    -- CORREÇÃO 29/10 (revisão): a pergunta sai uma vez por dia, no aviso ou no fechamento. Se alguma das perguntas que
    -- este texto cobre já foi mostrada hoje (no fechamento, numa conversa ou no acorde), as perguntas ficam para o 1º aviso de
    -- amanhã.
    if v_perg is not null
       and exists (select 1 from public.agenda_perguntas q
                    where q.id in (select x::uuid from jsonb_array_elements_text(v_perg -> 'pergunta_ids') x)
                      and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje) then
      v_perg := null;
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
  end if;

  return jsonb_build_object(
    'avisar', true, 'rodada', p_agora, 'dia', p_hoje, 'limite', cf.gestor_aviso_texto_max,
    'cabecalho', 'Agenda — o que eu mudei sozinho:',
    'mudancas', (select jsonb_agg(jsonb_build_object('texto', g ->> 'texto', 'acao_ids', g -> 'acao_ids') order by o)
                   from jsonb_array_elements(v_m) with ordinality t(g, o)),
    'fora', public._agenda_aviso_fora_texto(v_fora, v_oss),
    'rodape', '*agenda plano* mostra tudo.',
    'perguntas', v_perg, 'perguntas_erro', v_perr);
end;
$function$;

comment on function public.agenda_aviso_pecas(date, timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): as peças do aviso do gestor ao dono, sem gravar nada (o texto é montado em _shared/agenda/aviso-do-gestor.ts). Não avisa (avisar false + motivo): modo, desligado (gestor_aviso_dia_max 0), nada_mudou, fora_da_janela (+ pendentes: sai junto na abertura), teto (+ pendentes), sem_dono. Avisa: {rodada, dia, limite (gestor_aviso_texto_max), cabecalho, mudancas [{texto do *o que mudou*, acao_ids}] (_agenda_aviso_mudancas), fora (_agenda_aviso_fora_texto, pelas propostas das mudanças), rodape, perguntas {texto de agenda_aprontar, pergunta_ids que ele cobre, oss, voce} — uma vez por dia — ou null, perguntas_erro (a rodada de aprontar falhou: o que mudou sai do mesmo jeito; o passo do motor registra o erro)}. STABLE, definer, só o service_role. CORREÇÃO 29/10 (revisão): (1) de segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, não avisa (motivo fechamento, + pendentes): o fechamento das 17:30 conta o que estiver por contar, e o resto sai no 1º aviso depois; (2) as perguntas saem uma vez por dia: se alguma das que o texto cobre já foi mostrada hoje (fechamento, conversa, acorde), ficam para amanhã. CORREÇÃO DA 7a (revisão da etapa; achado 15): as perguntas que o texto da rodada de aprontar cobre incluem as do gestor (situacao e estimativa) das OS que ele lista — a restrição da OS diz o que o gestor faz sem resposta; com o aviso enviado, elas contam como mostradas e o prazo delas vale.';

-- agenda_fechamento_registrar (de 20261025100300_agenda_fase2_conferencia_vigia.sql)
create or replace function public.agenda_fechamento_registrar(p_hoje date, p_linhas jsonb, p_via text default 'fechamento',
                                                              p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  e      jsonb;
  v_perg int := 0;
  v_acao int := 0;
  v_n    int;
begin
  if p_via is null or p_via not in ('fechamento', 'acorde', 'conversa') then
    raise exception 'Por onde foi mostrado: "%" (fechamento, acorde ou conversa).', coalesce(p_via, '') using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_linhas, '[]'::jsonb)) <> 'array' then
    raise exception 'As linhas mostradas vêm numa lista.' using errcode = '22023';
  end if;
  for e in select x from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x loop
    if e ->> 'pergunta_id' is not null then
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = p_via
       where q.id = (e ->> 'pergunta_id')::uuid and q.estado = 'aberta';
      get diagnostics v_n = row_count;
      v_perg := v_perg + v_n;
    end if;
    -- FASE 7: (7a correção, achado 15) a linha das perguntas do gestor mostra várias: cada uma de pergunta_ids (fora a pergunta_id,
    -- já contada) ganha a mostrada
    if jsonb_typeof(e -> 'pergunta_ids') = 'array' then
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = p_via
       where q.id in (select y::uuid from jsonb_array_elements_text(e -> 'pergunta_ids') y)
         and q.id is distinct from nullif(e ->> 'pergunta_id', '')::uuid and q.estado = 'aberta';
      get diagnostics v_n = row_count;
      v_perg := v_perg + v_n;
    end if;
    -- FASE 7: fim
    if jsonb_typeof(e -> 'acao_ids') = 'array' then
      update public.agenda_acoes a set contada_em = p_agora, contada_via = p_via
       where a.id in (select y::uuid from jsonb_array_elements_text(e -> 'acao_ids') y) and a.contada_em is null;
      get diagnostics v_n = row_count;
      v_acao := v_acao + v_n;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'perguntas', v_perg, 'acoes', v_acao);
end;
$function$;

comment on function public.agenda_fechamento_registrar(date, jsonb, text, timestamptz) is
  'Agenda de Produção (Fase 2, P3): o que o fechamento (ou a conversa) mostrou da agenda — para cada linha {pergunta_id?, acao_ids?}: a pergunta aberta ganha mostrada_vezes + 1, mostrada_em e mostrada_via; as ações ainda não contadas ganham contada_em/contada_via. Chamada pelo secretário quando o fechamento saiu com as linhas da agenda em ligado. Só service_role. CORREÇÃO DA 7a (revisão da etapa; achado 15): a linha pode trazer também pergunta_ids (a linha das perguntas do gestor, que mostra várias numa só): cada pergunta aberta da lista que não é a pergunta_id ganha a mostrada.';

-- _agenda_linhas_do_fechamento (de 20261031100850_agenda_fase7a_protecoes.sql)
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
      v_f77_nl := case when v_f77_q.ate is null then 'Espero você: ' else format('Também, sem resposta até %s: ', v_f77_q.ate) end;
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
    v_out := v_out || jsonb_build_object('tipo', 'pergunta', 'texto', v_f77_l, 'perda', case when v_f77_prazo then 75 else 30 end,
      'pergunta_id', v_f77_ids ->> 0, 'pergunta_ids', v_f77_ids, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  -- FASE 7: fim
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80.';

-- agenda_textos_do_fechamento (de 20261031100600_agenda_fase7a_rodada.sql)
create or replace function public.agenda_textos_do_fechamento(p_hoje date default public._hoje_brt(), p_dia date default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_pn     jsonb;
  v_dia    date;
  v_marc   jsonb;
  v_prox   jsonb;
  v_prontos jsonb;
  v_esp    int;
  v_plano  boolean;
  v_seg    date;
  v_cauda  text;
  v_sem    text[] := '{}';
  v_l      text;
  k        int;
  c_max    constant int := 160;
  -- FASE 7: (7a P7) as vagas da agenda no fechamento
  v_f7_lin jsonb;
  v_f7_n   int;
  -- FASE 7: fim
  -- FASE 7: (7a correção, achados 15 e 18) quantas linhas ligadas perdem hoje
  v_f77_n  int;
  -- FASE 7: fim
begin
  if p_hoje is null then
    raise exception 'agenda_textos_do_fechamento: sem o dia de hoje' using errcode = '22004';
  end if;
  if c.modo_leitura = 'desligado' then
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', null, 'semana_que_vem', '[]'::jsonb,
                              'dia_do_plano', false,
                              -- FASE 2: com a leitura desligada a agenda inteira cala
                              'linhas', '[]'::jsonb);
  end if;
  v_dia := coalesce(p_dia, p_hoje + 1);
  v_pn := public._agenda_painel(p_hoje);
  v_plano := extract(isodow from p_hoje)::int = c.dia_do_plano;

  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(v_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  select count(*) into v_esp from jsonb_array_elements(v_pn -> 'oss') e where (e ->> 'dono_trava')::boolean;

  -- A cauda do "Amanhã" sem nada marcado. Se a agenda vê algo marcado no dia, não há cauda (o Secretário diz o dia).
  -- (FASE 2: em 'ligado' o marcado é o plano — _agenda_marcados.)
  v_marc := public._agenda_marcados(v_dia, v_dia, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
  if jsonb_array_length(v_marc) = 0 then
    v_cauda := 'nada marcado; '
      || case when jsonb_array_length(v_prontos) > 0 then 'prontos para começar: ' || public._agenda_nomes(v_prontos, 3)
              when (v_pn #>> '{backlog,n}')::int = 0 then 'nenhum serviço na fila'
              when v_esp > 0 then format('nenhum serviço pronto, %s esperando você', v_esp)
              else 'nenhum serviço pronto ainda' end
      || ' (*agenda*)';
  end if;

  -- Só no dia do plano (quinta): até 3 linhas da semana que vem, cada uma com até 160 caracteres.
  -- FASE 2: com a agenda automática ligada a projeção não sai: a linha "semana" do publicado (linhas) a substitui.
  if v_plano and c.modo_proposta <> 'ligado' then
    v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1) + 7;
    v_prox := public._agenda_marcados(v_seg, v_seg + 5, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
    for k in reverse 3 .. 1 loop
      v_l := 'Semana que vem (projeção): '
             || case when jsonb_array_length(v_prox) = 0 then 'nada marcado'
                     else public._agenda_plural(jsonb_array_length(v_prox), 'marcado', 'marcados') || ' ('
                          || public._agenda_lista(array(select e ->> 'nome' from jsonb_array_elements(v_prox) with ordinality t(e, o)
                                                         order by o), k) || ')' end
             || case when (v_pn #>> '{backlog,n}')::int = 0 then '; nenhum serviço na fila.'
                     else '; ' || public._agenda_plural((v_pn #>> '{backlog,n}')::int, 'serviço na fila', 'serviços na fila')
                          || ', ' || public._agenda_fila_faixa(v_pn)
                          || case when (v_pn ->> 'comprometivel')::numeric > 0
                                  then format(' (~%s por semana, %s)', public._agenda_num((v_pn ->> 'comprometivel')::numeric, 1),
                                              case when (v_pn #>> '{cap,conta_dono}')::boolean then 'contando você' else 'sem contar você' end)
                                  else '' end || '.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    for k in reverse 3 .. 1 loop
      v_l := case when jsonb_array_length(v_prontos) > 0 then 'Prontos para começar: ' || public._agenda_nomes(v_prontos, k)
                  else 'Nenhum pronto para começar' end
             || case when v_esp > 0 then '; o que falta de você está em *agenda*.'
                     when jsonb_array_length(v_prontos) > 0 then '.' else ' ainda.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    v_l := public._agenda_livre_linha(v_pn, false);
    if v_l is not null then v_sem := v_sem || v_l; end if;
    v_sem := array(select x from unnest(v_sem) x where char_length(x) <= c_max);
  end if;

  -- FASE 7: (7a P7) as vagas que a agenda tem garantidas no fechamento (spec §5.7 item 3, §7): com modo_vaga_fechamento
  -- ligado, fechamento_vagas_agenda (+1 com alguma linha ligada de decisão de perda ≥ 80 — a decisão crítica e a compra urgente —,
  -- até 2) em vagas_garantidas; em sombra, vagas_garantidas = 0 e vaga_teria = as que teria (o Secretário põe no detalhe).
  -- Desligado, a saída de antes, byte a byte. As linhas são lidas uma vez só (a mesma lista vai em linhas).
  if public._agenda_gestor_modo('vaga') <> 'desligado' then
    v_f7_lin := public._agenda_linhas_do_fechamento(p_hoje);
    v_f7_n := least(2, c.fechamento_vagas_agenda
                       + case when exists (select 1 from jsonb_array_elements(v_f7_lin) x
                                            where x ->> 'modo' = 'ligado' and x ->> 'tipo' in ('decisao', 'compras')
                                              and (x ->> 'perda')::int >= 80) then 1 else 0 end);
    -- (7a correção, achados 15 e 18) cada linha ligada que perde hoje (perda >= 75: a decisão crítica, a diária com 2 dias
    -- úteis, a compra de hoje, a mensagem ao cliente que espera *manda cliente*, as perguntas do gestor) tem a sua vaga, até 3
    v_f77_n := (select count(*) from jsonb_array_elements(v_f7_lin) x
                 where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int >= 75)::int;
    v_f7_n := least(3, greatest(v_f7_n, v_f77_n));
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                              'dia_do_plano', v_plano, 'dia', v_dia,
                              'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                          'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                              'linhas', v_f7_lin,
                              'vagas_garantidas', case when public._agenda_gestor_modo('vaga') = 'ligado' then v_f7_n else 0 end,
                              'vaga_teria', case when public._agenda_gestor_modo('vaga') = 'sombra' then v_f7_n end);
  end if;
  -- FASE 7: fim
  return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                            'dia_do_plano', v_plano, 'dia', v_dia,
                            'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                        'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                            -- FASE 2: as linhas da agenda (decisões, o dia, a semana, o que mudou, uma pergunta)
                            'linhas', public._agenda_linhas_do_fechamento(p_hoje));
end;
$function$;

comment on function public.agenda_textos_do_fechamento(date, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5): as linhas da agenda no fechamento das 17:30 — cauda_amanha (o "Amanhã" sem nada marcado: "nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)" ou "nada marcado; prontos para começar: …"; null quando a agenda vê algo marcado em p_dia — em ''ligado'', o plano), só quando isodow(p_hoje) = dia_do_plano e a agenda automática não está ligada, até 3 linhas "Semana que vem (projeção)" de até 160 caracteres, e (FASE 2) linhas [{tipo, texto, perda, pergunta_id, acao_ids, modo}] de _agenda_linhas_do_fechamento. modo_leitura desligado: nada. O Secretário decide o que publica (sombra × ligado; vagas de REGRAS.maxManha). FASE 7 (7a P7, spec §5.7 item 3 e §7): com modo_vaga_fechamento fora de desligado, a saída ganha vagas_garantidas — com ligado, fechamento_vagas_agenda (+1 com alguma linha ligada de decisão de perda ≥ 80, a decisão crítica ou a compra urgente, até 2); em sombra, 0 — e vaga_teria (em sombra, as vagas que teria: o Secretário põe no detalhe); as linhas são lidas uma vez só. Desligado, a saída de antes, byte a byte. O Secretário soma vagas_garantidas às vagas que sobram de REGRAS.maxManha. CORREÇÃO DA 7a (revisão da etapa; achados 15 e 18): cada linha ligada que perde hoje (perda ≥ 75: a decisão crítica, a diária com 2 dias úteis, a compra de hoje, a mensagem ao cliente que espera *manda cliente*, a linha das perguntas do gestor) tem a sua vaga garantida, até 3 — vagas_garantidas = least(3, greatest(a conta de antes, as linhas de perda ≥ 75)). Antes eram no máximo 2, e a mensagem ao cliente da véspera tirava a vez da pergunta da ficha de amanhã.';

-- agenda_encaixe_do_novo (de 20261030100100_agenda_correcao_livre.sql)
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
  -- FASE 7: (7a correção, achado 5) sem gente dita e com a regra uma_pessoa do gestor (AG7-04), o serviço novo vai com
  -- equipe_padrao pessoas por turno, como o gestor o marcaria (a dupla só quando o dono diz); sem a regra, a de antes
  if jsonb_array_length(v_lista) = 0 and public._agenda_gestor_regra('uma_pessoa') then
    v_dm := greatest(cf.equipe_padrao - case when v_dtm then 1 else 0 end, 0);
    v_dtd := greatest(cf.equipe_padrao - case when v_dtt then 1 else 0 end, 0);
  end if;
  -- FASE 7: fim
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
  'Agenda de Produção (correção de 29/10, P2): um serviço que ainda não existe ("2 dias, com o Roberto") no encaixe do motor (_agenda_encaixar, só leitura) sobre a grade de agora (_agenda_grade_de_agora: o marcado e o reservado ocupam), como uma OS nova entraria — compromisso (classe 2), a partir do 1º dia que a agenda ainda pode mudar, todos os inícios até o horizonte, o teto de compromisso (sem caber, acima dele, até 100%: acima = true). p_gente = a lista da agenda_simular [{payee_id, nome, eh_dono, turnos}]: o dono fica o turno dele, os outros por turno; sem ninguém, equipe_sugerida pessoas por turno. A presença do dono: p_dono (abre_e_fecha, sempre, nunca); senão o turno dele na lista; senão ele abre e fecha. O dono o turno inteiro sem os dias dele em campo o motor não marca: so_pontas = true, simula com ele só abrindo e fechando e a frase diz por quê. Meios-dias: dias × 2 (quem só vem num turno: 1 por dia). Pessoa fora da grade: motivo sem_dias. {ok, cabe, acima, so_pontas, motivo (sem_encaixe, sem_dias, sem_equipe), de, ate, dias, pessoas, pontas, horizonte, meios_por_semana[{payee_id, seg, meios}], texto ("pelo plano de agora, cabe em sex 13 e ter 17/11, com João e Roberto; você abre e fecha. É simulação: não marca nada.")}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role. CORREÇÃO DA 7a (revisão da etapa; achado 5): sem gente dita e com a regra uma_pessoa do gestor, o serviço novo vai com equipe_padrao pessoas por turno (1), como o gestor marca; sem a regra, a de antes, byte a byte.';

-- agenda_livre_de_verdade (de 20261030100500_agenda_correcao_revisao.sql)
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
  'Agenda de Produção (Fase 3, P6; REESCRITA na correção de 29/10, P2): "quando a gente fica livre de verdade?" pelo plano e pelo teto de cada pessoa — só com modo_proposta ligado (fora disso {fonte: projecao}: quem chama usa a frase da Fase 1). Para cada uma das 3 semanas a partir do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado), os meios-dias que cada pessoa ainda pega num serviço novo, a mesma conta do encaixe: o menor entre teto80 − compromisso, teto100 − compromisso − reserva e os meios-dias dela livres na grade (_agenda_grade_de_agora: o marcado e o reservado ocupam); o dono só com os dias dele em campo (sem eles, voce_fora e a frase "Você fica de fora da conta"). Depois, o que ocupa a equipe (o plano de hoje ao sábado da última semana, por OS, com quem fica o turno), o que não ocupa ninguém até destravar (a carteira fora do plano: travados, esperando o dono, parados no cliente, em espera; o pronto sem lugar; o em andamento sem dia) e como perguntar de um serviço novo. {fonte: simulacao (o sinal de "use o texto daqui" para a agenda_ver e a agenda_tela_semana), base: plano, de, ate, semanas[{seg, de, ate, rotulo, pessoas[{payee_id, nome, eh_dono, meios, celulas, teto, compromisso, reserva}], texto}], voce_fora, ocupa[{os, numero, reserva, dias, pessoas, texto}], nao_ocupam{travados, prontos, andamento, parados, em_espera}, texto (a linha da semana e da tela: "Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia."), texto_completo (a resposta do *livre*, até texto_max), ms}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role. CORREÇÃO 29/10 (revisão): na linha curta (texto), a 1ª semana pela metade sai com o rótulo do *livre* ("Livre de verdade: de qua 04 a sex 06/11, Roberto 1 dia, João nada; na semana de 09/11, …"; um dia só, "na sex 06/11"), não "na semana de 04/11". CORREÇÃO DA 7a (revisão da etapa; achado 23): com a regra teto_equipe do gestor, (1) o dono não entra na conta do livre como técnico, mesmo com os dias em campo (o motor só o põe para abrir, fechar e no diagnóstico): "Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você)."; (2) os meios-dias da equipe na semana não passam do teto da equipe-semana (teto_equipe − o compromisso da equipe nela), repartidos de quem tem mais para quem tem menos. Sem a regra, a de antes, byte a byte.';

-- _agenda_aprontar_de (de 20261024160500_agenda_fase1_leituras.sql)
create or replace function public._agenda_aprontar_de(p_pn jsonb, p_k integer)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_cand    jsonb;
  v_n       int;
  v_resto   jsonb;
  v_bul     text[];
  v_chute   boolean;
  l_cab     text;
  l_voce    text;
  l_pe      text;
begin
  -- Quem entra: a fila com algo que só o dono responde (o que trava primeiro, depois só a duração), na ordem de trabalho.
  select coalesce(jsonb_agg(e order by (e ->> 'dono_trava')::boolean desc, (e ->> 'ordem')::int), '[]'::jsonb)
    into v_cand from jsonb_array_elements(p_pn -> 'oss') e
   where (e ->> 'executavel')::boolean and jsonb_array_length(e -> 'restr_dono') > 0;
  -- FASE 7: (7a correção, achado 24) só a pergunta de fato ao dono entra (a duração ou a restrição com "pergunta"): a suposição
  -- do gestor que não pergunta (sem_peca_suposta, "marquei sem peça a comprar; se precisar, me diga") virava a linha vazia
  -- "• Lenine (OS-00074): " no aviso. A OS sem nenhuma pergunta de fato sai da lista; sem restrição sem pergunta, nada muda.
  select coalesce(jsonb_agg(f.e order by f.o), '[]'::jsonb) into v_cand
    from (select t.o,
                 t.e || jsonb_build_object('restr_dono',
                          (select coalesce(jsonb_agg(r order by ro), '[]'::jsonb)
                             from jsonb_array_elements(t.e -> 'restr_dono') with ordinality u(r, ro)
                            where r ->> 'tipo' = 'duracao' or nullif(btrim(coalesce(r ->> 'pergunta', '')), '') is not null)) as e
            from jsonb_array_elements(v_cand) with ordinality t(e, o)) f
   where jsonb_array_length(f.e -> 'restr_dono') > 0;
  -- FASE 7: fim
  v_n := jsonb_array_length(v_cand);

  -- Uma pergunta por OS: as perguntas do dono na ordem da prontidão; a duração com o chute entre parênteses.
  v_bul := array(
    select '• ' || public._agenda_rotulo(e, 'num') || ': '
           || array_to_string(array(
                select case when ro = 1 then q else public._agenda_maiuscula(q) end
                  from (select case when r ->> 'tipo' = 'duracao' then replace(r ->> 'texto', '(chute: ', '(')
                                    else r ->> 'pergunta' end as q, ro
                          from jsonb_array_elements(e -> 'restr_dono') with ordinality t2(r, ro)) z
                 order by ro), ' ')
      from jsonb_array_elements(v_cand) with ordinality t(e, o)
     where o <= p_k order by o);
  v_chute := exists (select 1 from jsonb_array_elements(v_cand) with ordinality t(e, o), jsonb_array_elements(e -> 'restr_dono') r
                      where o <= p_k and r ->> 'tipo' = 'duracao' and r ->> 'texto' like '%(chute: %');
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by o), '[]'::jsonb)
    into v_resto from jsonb_array_elements(v_cand) with ordinality t(e, o) where o > p_k;

  if not (p_pn ->> 'dono_padrao')::boolean then
    l_voce := '• Você: semana que vem fica em campo quais dias?';
  end if;
  if v_n = 0 and l_voce is null then
    return jsonb_build_object('linhas', to_jsonb(array['Não tenho nada para perguntar agora: o que dependia de você já está respondido.']),
                              'dados', jsonb_build_object('oss', '[]'::jsonb, 'resto', '[]'::jsonb, 'voce', false));
  end if;
  l_cab := case when v_n = 0 then 'Para montar a semana:'
                else 'Para montar a semana, uma resposta por OS'
                     || case when v_chute then ' (entre parênteses, o meu chute pelo valor)' else '' end || ':' end;
  l_pe := 'Pode ser um áudio só'
          || case when v_n > 0 then ', citando o nome do cliente.' else '.' end
          || case when jsonb_array_length(v_resto) > 0 then
               ' (' || public._agenda_nomes(v_resto, null, 'np')
               || case when jsonb_array_length(v_resto) = 1 then ' fica' else ' ficam' end || ' para depois.)'
             else '' end;

  return jsonb_build_object(
    'linhas', to_jsonb(array[l_cab] || v_bul || array[l_voce, l_pe]),
    'dados', jsonb_build_object(
      'oss', (select coalesce(jsonb_agg(e ->> 'numero' order by o), '[]'::jsonb)
                from jsonb_array_elements(v_cand) with ordinality t(e, o) where o <= p_k),
      'resto', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_resto) with ordinality t(e, o)),
      'voce', l_voce is not null));
end;
$function$;

comment on function public._agenda_aprontar_de(jsonb, integer) is 'Agenda de Produção (Fase 1, P4): as linhas da rodada de aprontar a partir do painel, com até p_k OS. CORREÇÃO DA 7a (revisão da etapa; achado 24): só entra a OS com alguma pergunta de fato ao dono (a duração ou uma restrição com "pergunta"), e só essas perguntas vão na linha dela: a suposição do gestor que não pergunta (sem_peca_suposta, da 7a) não vira mais a linha vazia "• Lenine (OS-00074): " no aviso. Sem restrição sem pergunta, a de antes, byte a byte.';

-- ── 3. O comentário de modo_compre_ate (achado 8) ─────────────────────────────────────────────────────────────────────
-- O de 20261031100000 dizia "sombra = grava sem cobrar"; o passo (P10) em teste não grava nada em os_material: só o diário.
comment on column public.agenda_config.modo_compre_ate is
  'Agenda de Produção (Fase 7a, AG7-07): o "compre até" contado para trás (_agenda_gestor_compre_ate). desligado = nada; sombra = em teste: a conta e a cobrança só no diário (agenda_gestor_dia.compras), nada é gravado em os_material nem perguntado (o 1º tique ligado é que grava); ligado = grava na linha de material, cobra a partir de gestor_hora_revisao e, vencido, a OS é empurrada (até compre_ate_empurroes_max).';

-- ── 4. O job agenda-gestor nos minutos ímpares (achado 12) ─────────────────────────────────────────────────────────────
-- '7,23,37,53 10-23 * * 1-6' = 07:07 a 20:53 de Brasília, de segunda a sábado: fora dos :00/:15/:30/:45 da vigia e dos minutos
-- pares do comprovantes-vigia (*/2; antes o :22 e o :52 batiam com ele). A revisão diária das 16:45 passa a rodar às 16:53. O
-- comando é o mesmo de 20261031100600. Só com a extensão pg_cron (a bancada não tem); idempotente pelo nome.
do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'agenda-gestor: sem pg_cron (bancada) — nada agendado';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'agenda-gestor') then
    perform cron.unschedule('agenda-gestor');
  end if;
  perform cron.schedule('agenda-gestor', '7,23,37,53 10-23 * * 1-6',
    $job$select set_config('statement_timeout', (select ceil(extract(epoch from c.gestor_tempo_max))::int::text || 's' from public.agenda_config c where c.id), false); select public.agenda_gestor_rodar(public._hoje_brt(), now());$job$);
  if (select count(*) from cron.job where jobname = 'agenda-gestor') <> 1 then
    raise exception 'cron agenda-gestor não ficou com exatamente 1 job';
  end if;
end
$cron$;

-- ── 5. Portas (as de antes das recriadas continuam: create or replace não mexe no grant) ─────────────────────────────────
-- As 5 novas sem grant a ninguém: só as funções da agenda as chamam (a revisão, o encaixe, o corte, o foco, a duração na rodada).
-- _agenda_gestor_juntar é lida pelo foco (invoker, com o login de quem pergunta): authenticated e service_role.
revoke all on function public._agenda_gestor_desfeito(uuid, timestamptz), public._agenda_gestor_pessoa_meios(uuid, date, jsonb),
  public._agenda_rodada_duracao_lembrar(text), public._agenda_rodada_duracao_guardar(text, bigint, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_gestor_juntar(text[], integer, text) from public, anon;
grant execute on function public._agenda_gestor_juntar(text[], integer, text) to authenticated, service_role;
