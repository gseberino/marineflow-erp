-- Retorno rápido ao cliente, F1 (sobe em sombra na seg 16/11/2026): o que o retorno conta ao dono e à sessão
-- coordenadora. O recibo promete uma hora ("hoje até as 10h", "hoje até as 19h", "abre a lista dele … cedo"), e
-- quem cumpre é o dono: ele só cumpre o que vê. Aqui o banco junta o que a manhã e o fechamento do Secretário
-- mostram (P14), a tabela de calibração da promessa, a lista da sombra e o próximo evento do replay (P9.3).
-- IA pensa, sistema preenche: rótulo, prazo, "venceu", contagens e ordem são do banco.
--
-- 1. retorno_resumo_do_dia(turno, agora) → jsonb (C-RESUMO; o Secretário chama pelo service_role). NUNCA devolve
--    texto do cliente: o resumo vai ao WhatsApp do dono e pode entrar no histórico do assistente (R1-12). O único
--    texto que não é do banco é o nome que o número novo DISSE depois de ouvir "Como posso te chamar?" (a coleta 2
--    'enviada'); na sombra a coleta nunca sai e o rótulo é sempre "número novo".
--    - 'manha': {modo, esperando, esperando_mais, conferir, conferir_mais}. Os casos vivos de recibo ou passagem
--      sem resposta de conteúdo, em duas classes: COM PRAZO HOJE (vencido, topo_dia até hoje ou prazo que cai
--      hoje) vêm TODOS, sem limite — é a linha que sustenta o "hoje até as 10h" da faixa noite e o "abre a lista
--      dele … cedo" do fim do dia —, primeiro os vencidos, depois por prazo; SEM PRAZO HOJE vêm até 3, por
--      abertura, e o resto conta em esperando_mais. "Para conferir" traz o que pede decisão do dono e não tem
--      recibo (PARAR por extenso, opt-out que voltou a escrever, recibo cancelado por atraso de mais de 24 h),
--      até 3, um por número e motivo (o mais recente), e o resto em conferir_mais;
--    - 'fechamento': {modo, esperando (os com prazo hoje, todos), recebidos, no_prazo, adiados (dos casos abertos
--      hoje), sem_palavra, na_queda, sombra {teria_mandado, por_papel, respondeu_antes}, alongadas (só na sexta:
--      os alongamentos dos últimos 7 dias)};
--    - outro turno: {"erro": "turno"}.
--    O item de "esperando" é {phone, rotulo, desde, prometido_ate, venceu, com_prazo_hoje} (P9.1) e, a pedido do
--    P14 (ai-daily-briefing/retorno.ts), também segundo_prazo (o X2 do adiamento: o prazo de pé), ouviu (o recibo
--    ou a saudação do caso saiu enviada ou incerta: só então o Secretário diz "prometi") e papel. As listas vazias
--    saem '[]', nunca nulas.
--    Desvios (falha fecha, levados à coordenação):
--    - o recibo da noite ainda agendado para a manhã (08:00–08:30, depois da manhã do Secretário às 07:30) já tem
--      a promessa guardada em dados.prazo pelo retorno_pegar; ela conta como "prazo hoje" e vai em prometido_ate.
--      Sem isso, o "hoje até as 10h" que o cliente vai ouvir às 08:10 cairia entre os "sem prazo" (até 3), e a
--      linha que sustenta a promessa seria cortada;
--    - "Para conferir", a janela: a spec diz "aberto nas últimas 24 h", mas o caso vive dias (desde o cartão F1-10, até o dono resolver) e o
--      _retorno_triar marca parar_largo em QUALQUER mensagem dele. No parar_largo e no opt_out vale a ÚLTIMA mensagem
--      do caso: pela 1ª, o pedido feito no 2º dia do caso nunca chegaria ao dono, e este é o único canal dele (P5,
--      regra 3). E o início da janela é o menor entre 24 h atrás e a mesma hora da manhã anterior que leu o retorno:
--      domingo e feriado não leem (secretario.ts, tipoDoDia; sábado lê), e com 24 h fixas o que entra entre sáb 07:30
--      e dom 07:30 (48 h com feriado na segunda) nunca apareceria;
--    - "Para conferir", a repetição: a spec não pede um item por número. Os casos repetidos do mesmo número e do mesmo
--      motivo viram um item (o mais recente); motivo diferente é outra decisão do dono e nunca some;
--    - sem_palavra e na_queda contam as promessas (o prazo de pé: segundo_prazo, senão prometido_ate) dos casos que
--      seguem em recibo ou passagem, que venceram desde a mesma hora do último FECHAMENTO até agora, sem resposta de
--      conteúdo até o prazo e sem o fim do dia decidido. O nível é o filtro do relógio do vigia: o caso que virou
--      'nada' depois do recibo (PARAR, vendedor, agenda, promessa do dono) calou de propósito e nunca ganha fim do
--      dia. O calendário é o da tarde do Secretário (_retorno_turno_da_tarde, espelho de turnoDaTarde), não o
--      agenda_dia_util: só o turno fechamento mostra esses números (secretario-tarde.ts), e o 1º dia útil da semana e
--      o do mês são revisão. Assim cada vencimento entra uma vez num fechamento mostrado, inclusive o das 19h (depois
--      do fechamento das 17:30) e os de sex 19h e seg 10h, que a terça conta. na_queda = as que tiveram o fim do dia
--      recusado por so_reativo (o disjuntor: o canal estava fora); sem_palavra = as outras. A meta de sem_palavra é 0;
--    - "Ninguém olha o futuro" também aqui: só casos gravados até p_agora, saídas decididas até p_agora e
--      alongamentos registrados até p_agora; a resposta de conteúdo e o fecho depois de p_agora não contam;
--    - o papel cliente_ambiguo pode ter um cadastro só (DDD diferente ou cadastro sem DDD, quem_escreve): aí
--      "(número de 1 clientes)" seria errado, e o rótulo sai "(número de cliente a confirmar)", sem nome nenhum.
--
-- 2. View retorno_calibracao: por faixa, os casos com recibo (sombra, enviada ou incerta) e prazo já decidido
--    (cumprido no prazo, ou o prazo passou): casos, no_prazo (resposta de conteúdo até o prometido, A.2),
--    pct_no_prazo, wilson_inferior (o limite inferior de 95% de Wilson: o portão da F1 pede o intervalo, R1-20),
--    mediana_ate_conteudo_min (da mensagem do cliente à resposta de conteúdo) e hora_local_p80_conteudo (nas
--    faixas de promessa no mesmo dia — manha_cedo, meio, pressa —, a menor hora em que 80% tiveram resposta de
--    conteúdo no mesmo dia; nula se nem 80% foram respondidos no dia: "a menor hora que bate 80%", B.4.1). No fim
--    da sombra a tabela vai ao dono; o que ele aprovar a sessão coordenadora grava em promessa_faixa (o
--    _retorno_prazo só aceita mais tarde). O caso cujo prazo ainda não passou e ainda sem resposta fica de fora:
--    ainda não se sabe se será cumprido.
--
-- 3. View retorno_sombra_lista: a "lista da sombra" (B.2; portão da F1), onde o dono confere precisão e público
--    errado. Uma linha por saída do retorno decidida em sombra ou enviada, fora o acorde e a fila: quando, papel,
--    rótulo, tipo, variante, texto, estado, motivo da sombra e da saída, nível e motivo do caso, o trecho da 1ª
--    mensagem do caso (140 caracteres) e o caso. TEM TEXTO DO CLIENTE: nunca sai pelo WhatsApp; só o service_role
--    lê, e a sessão coordenadora gera com ela o relatório privado do fim da sombra (seg 23/11).
--
-- 4. _retorno_proximo_evento(agora) → timestamptz (só o replay usa): o menor instante depois de agora em que o
--    relógio do retorno muda alguma coisa — enviar_em das agendadas; nos casos vivos com recibo, X − acorde_antes,
--    X − adiamento_antes, X, o X2 e o prazo de pé; resposta sem conteúdo + caso_fecha_silencio; caso 'nada' parado
--    + caso_fecha_silencio (pela hora real e pela de gravação); incertas + 10 min e + incerta_conferir_ate; e a
--    próxima 04:00 de Brasília (os passos diários do vigia).
--
-- Auxiliares internas: _retorno_rotulo(caso, agora) (a regra do rótulo, uma fonte só para o resumo e a lista da
-- sombra), _retorno_instante(texto) (o instante guardado em jsonb, ou nulo se ilegível: um dados.prazo torto
-- nunca derruba o resumo da manhã) e _retorno_dia_de_tarde(dia), _retorno_revisao_do_mes(dia) e
-- _retorno_turno_da_tarde(dia) (o espelho de _shared/secretario/turno.ts). SECURITY DEFINER com search_path (a que lê
-- tabela), revoke de public, anon e authenticated, sem grant. retorno_resumo_do_dia: SECURITY DEFINER, só o
-- service_role. As views: security_invoker, sem leitura de anon e authenticated, select só do service_role.
--
-- Sem dado: só funções e views novas; nenhuma linha muda.
-- Reverter (antes da migration do cron, 20261116101100, que não usa nada daqui): drop view
-- public.retorno_sombra_lista, public.retorno_calibracao; drop function public.retorno_resumo_do_dia(text, timestamptz),
-- public._retorno_proximo_evento(timestamptz), public._retorno_rotulo(uuid, timestamptz), public._retorno_instante(text),
-- public._retorno_turno_da_tarde(date), public._retorno_revisao_do_mes(date), public._retorno_dia_de_tarde(date).
-- Sem deploy: o Secretário trata a função ausente ou com erro como "sem retorno" (ai-daily-briefing/retorno.ts), e
-- update public.retorno_config set modo = 'desligado' deixa na manhã só quem já ouviu a promessa.

-- ── 1. O instante guardado em jsonb, ou nulo ─────────────────────────────────────────────────────────

create or replace function public._retorno_instante(p text)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
begin
  if p is null or btrim(p) = '' then
    return null;
  end if;
  return p::timestamptz;
exception when others then
  return null;   -- ilegível: quem chama trata como "sem prazo" (nunca derruba o resumo)
end;
$$;

comment on function public._retorno_instante(text) is
  'Retorno F1 (P9): o texto como timestamptz, ou nulo se vazio ou ilegível (um dados.prazo torto nunca derruba o resumo).';

revoke all on function public._retorno_instante(text) from public, anon, authenticated;

-- ── 2. O rótulo de um caso ───────────────────────────────────────────────────────────────────────────

create or replace function public._retorno_rotulo(p_abertura uuid, p_agora timestamptz default null)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_n integer;
  v_nome text;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    return 'contato';
  end if;

  if v_ab.papel in ('cliente', 'cliente_parceiro') then
    -- o nome curto do cadastro (empresa sem display_name e "Cliente Final" não têm nome: R1-22)
    return coalesce(public._retorno_nome(v_ab.client_id), 'cliente sem nome');
  end if;

  if v_ab.papel = 'cliente_ambiguo' then
    -- nunca o nome de um deles: o número de dois clientes não escolhe cliente
    v_n := greatest(coalesce(cardinality(v_ab.clientes), 0),
                    case when jsonb_typeof(v_ab.quem -> 'clientes') = 'array'
                         then jsonb_array_length(v_ab.quem -> 'clientes') else 0 end);
    return case when v_n >= 2 then '(número de ' || v_n || ' clientes)' else '(número de cliente a confirmar)' end;
  end if;

  if v_ab.papel = 'numero_novo' then
    -- o nome DITO só existe depois da coleta 2 enviada (a pessoa ouviu "Como posso te chamar?"); na sombra a
    -- coleta nunca sai, e o rótulo é sempre "número novo"
    if exists (select 1 from public.retorno_saidas s
                where s.abertura_id = v_ab.id
                  and s.tipo = 'coleta_numero_novo'
                  and s.estado = 'enviada'
                  and (p_agora is null or s.enviada_em <= p_agora)) then
      v_nome := left(nullif(btrim(v_ab.coleta ->> 'nome'), ''), 40);
    end if;
    return coalesce(v_nome, 'número novo');
  end if;

  return case v_ab.papel
    when 'contato_conhecido' then 'contato conhecido'
    when 'fornecedor' then 'fornecedor'
    else 'contato'
  end;
end;
$$;

comment on function public._retorno_rotulo(uuid, timestamptz) is
  'Retorno F1 (P9): o rótulo de um caso para o dono: cliente = nome curto do cadastro (ou "cliente sem nome"); ambíguo = "(número de N clientes)"; número novo = o nome dito só depois da coleta 2 enviada (senão "número novo"; na sombra, sempre); contato conhecido; fornecedor. Nunca texto do cliente além desse nome.';

revoke all on function public._retorno_rotulo(uuid, timestamptz) from public, anon, authenticated;

-- ── 2b. O calendário da tarde do Secretário ──────────────────────────────────────────────────────────
-- O espelho de ehDiaUtilDaTarde, diaDaRevisaoDoMes e turnoDaTarde (_shared/secretario/turno.ts). Não é o
-- agenda_dia_util: o dia que o dono marca indisponível tem tarde normal. agenda_feriado é a lista de feriadoDoDia.

create or replace function public._retorno_dia_de_tarde(p_dia date)
returns boolean
language sql
immutable
set search_path = public
as $$
  select extract(isodow from p_dia) between 1 and 5 and public.agenda_feriado(p_dia) is null;
$$;

comment on function public._retorno_dia_de_tarde(date) is
  'Retorno F1 (P9): o dia tem tarde do Secretário: segunda a sexta, sem feriado (ehDiaUtilDaTarde, _shared/secretario/turno.ts).';

revoke all on function public._retorno_dia_de_tarde(date) from public, anon, authenticated;

create or replace function public._retorno_revisao_do_mes(p_dia date)
returns date
language sql
immutable
set search_path = public
as $$
  select min(x.d)
    from (select p_dia - (extract(day from p_dia)::integer - 1) + g as d from generate_series(0, 9) as g) x
   where public._retorno_dia_de_tarde(x.d);
$$;

comment on function public._retorno_revisao_do_mes(date) is
  'Retorno F1 (P9): o 1º dia com tarde do mês de p_dia, o da revisão do mês (diaDaRevisaoDoMes, _shared/secretario/turno.ts).';

revoke all on function public._retorno_revisao_do_mes(date) from public, anon, authenticated;

create or replace function public._retorno_turno_da_tarde(p_dia date)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_revisao_semana date;
begin
  if not coalesce(public._retorno_dia_de_tarde(p_dia), false) then
    return null;
  end if;
  if p_dia = public._retorno_revisao_do_mes(p_dia) then
    return 'revisao_mes';
  end if;
  -- o 1º dia com tarde da semana que não seja o da revisão do mês dele (a semana pode cruzar dois meses)
  select min(x.d) into v_revisao_semana
    from (select p_dia - (extract(isodow from p_dia)::integer - 1) + g as d from generate_series(0, 4) as g) x
   where public._retorno_dia_de_tarde(x.d)
     and x.d <> public._retorno_revisao_do_mes(x.d);
  return case when p_dia = v_revisao_semana then 'revisao_semana' else 'fechamento' end;
end;
$$;

comment on function public._retorno_turno_da_tarde(date) is
  'Retorno F1 (P9): o turno da tarde do Secretário no dia: revisao_mes, revisao_semana, fechamento, ou nulo em sábado, domingo e feriado (turnoDaTarde, _shared/secretario/turno.ts). Só o turno fechamento mostra sem_palavra e na_queda.';

revoke all on function public._retorno_turno_da_tarde(date) from public, anon, authenticated;

-- ── 3. O resumo do dia (C-RESUMO) ────────────────────────────────────────────────────────────────────

create or replace function public.retorno_resumo_do_dia(p_turno text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_primeiras constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo'];
  c_sem_texto constant text[] := array['acorde', 'cadastro_provisorio', 'fila'];
  c_sem_prazo_max constant integer := 3;
  c_conferir_max constant integer := 3;
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_ini_hoje timestamptz;
  v_fim_hoje timestamptz;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_modo text;
  v_com jsonb;
  v_sem jsonb;
  v_sem_total integer;
  v_conferir jsonb;
  v_conferir_total integer;
  v_manha_antes date;
  v_desde_conferir timestamptz;
  v_dia_antes date;
  v_desde_venc timestamptz;
  v_recebidos integer;
  v_no_prazo integer;
  v_adiados integer;
  v_sem_palavra integer;
  v_na_queda integer;
  v_teria integer;
  v_por_papel jsonb;
  v_respondeu integer;
  v_alongadas jsonb;
begin
  if p_turno is null or p_turno not in ('manha', 'fechamento') then
    return jsonb_build_object('erro', 'turno');
  end if;
  -- Sem a linha de configuração: desligado (o Secretário mostra só quem já ouviu a promessa).
  v_modo := coalesce(v_cfg.modo, 'desligado');
  v_ini_hoje := v_hoje::timestamp at time zone c_fuso;
  v_fim_hoje := (v_hoje + 1)::timestamp at time zone c_fuso;

  -- Quem espera: os casos vivos de recibo ou passagem sem resposta de conteúdo, gravados até agora.
  with vivos as (
    select a.id, a.phone_normalized, a.papel, a.aberta_em, a.estado, a.topo_dia, a.prometido_ate, a.segundo_prazo,
           coalesce(a.segundo_prazo, a.prometido_ate) as prazo_caso,
           pend.prazo as prazo_pendente
      from public.retorno_aberturas a
      -- o recibo ainda por sair que já guardou a promessa (o da noite, que sai às 08:0x)
      left join lateral (
        select public._retorno_instante(s.dados -> 'prazo' ->> 'prometido_ate') as prazo
          from public.retorno_saidas s
         where s.abertura_id = a.id
           and s.tipo = any (c_recibos)
           and s.estado in ('agendada', 'preparada', 'enviando')
         order by s.criada_em desc, s.id
         limit 1) pend on a.prometido_ate is null
     where (a.estado in ('aberta', 'vencida') or a.fechada_em > v_agora)
       and a.nivel in ('recibo', 'passagem')
       and (a.cumprida_em is null or a.cumprida_em > v_agora)
       and a.gravada_em <= v_agora
  ), itens as (
    select v.id, v.phone_normalized, v.papel, v.aberta_em, v.topo_dia, v.segundo_prazo,
           coalesce(v.prometido_ate, v.prazo_pendente) as prometido,
           coalesce(v.prazo_caso, v.prazo_pendente) as prazo,
           (v.estado = 'vencida' or coalesce(v.prazo_caso < v_agora, false)) as venceu
      from vivos v
  ), classes as (
    select i.*,
           (i.venceu or coalesce(i.topo_dia <= v_hoje, false)) as vencido,
           (i.venceu or coalesce(i.topo_dia <= v_hoje, false)
            or coalesce((i.prazo at time zone c_fuso)::date = v_hoje, false)) as com_prazo_hoje,
           exists (select 1 from public.retorno_saidas s
                    where s.abertura_id = i.id
                      and s.tipo = any (c_primeiras)
                      and s.estado in ('enviada', 'incerta')
                      and s.decidida_em <= v_agora) as ouviu
      from itens i
  ), numerados as (
    select c.*,
           row_number() over (partition by c.com_prazo_hoje order by c.aberta_em, c.id) as n_classe,
           jsonb_build_object('phone', c.phone_normalized,
                              'rotulo', public._retorno_rotulo(c.id, v_agora),
                              'desde', c.aberta_em,
                              'prometido_ate', c.prometido,
                              'venceu', c.venceu,
                              'com_prazo_hoje', c.com_prazo_hoje,
                              'segundo_prazo', c.segundo_prazo,
                              'ouviu', c.ouviu,
                              'papel', c.papel) as item
      from classes c
  )
  select coalesce(jsonb_agg(n.item order by (not n.vencido), n.topo_dia nulls last, n.prazo nulls last, n.aberta_em, n.id)
                    filter (where n.com_prazo_hoje), '[]'::jsonb),
         coalesce(jsonb_agg(n.item order by n.aberta_em, n.id)
                    filter (where not n.com_prazo_hoje and n.n_classe <= c_sem_prazo_max), '[]'::jsonb),
         count(*) filter (where not n.com_prazo_hoje)
    into v_com, v_sem, v_sem_total
    from numerados n;

  if p_turno = 'manha' then
    -- "Para conferir" cobre desde a mesma hora da manhã anterior que leu o retorno (domingo e feriado não leem), e
    -- nunca menos de 24 h: o que entra entre as duas manhãs tem de chegar ao dono.
    select max(x.d) into v_manha_antes
      from (select v_hoje - g as d from generate_series(1, 10) as g) x
     where extract(isodow from x.d) <> 7
       and public.agenda_feriado(x.d) is null;
    v_desde_conferir := least(v_agora - interval '24 hours',
                              (coalesce(v_manha_antes, v_hoje - 1) + (v_agora at time zone c_fuso)::time) at time zone c_fuso);

    -- "Para conferir": o que pede decisão do dono e não tem recibo, um item por número e motivo (o mais recente). No
    -- parar_largo e no opt_out vale a última mensagem do caso: o pedido pode vir em qualquer mensagem dele.
    with c as (
      select a.id, a.chave, a.phone_normalized, a.motivo as motivo, a.aberta_em as desde,
             least(a.ultima_gravada_em, v_agora) as quando
        from public.retorno_aberturas a
       where a.nivel = 'nada'
         and a.motivo in ('parar_largo', 'opt_out')
         and a.gravada_em <= v_agora
         and least(a.ultima_gravada_em, v_agora) > v_desde_conferir
      union all
      select a.id, a.chave, a.phone_normalized, 'atraso_longo', a.aberta_em, s.decidida_em
        from public.retorno_saidas s
        join public.retorno_aberturas a on a.id = s.abertura_id
       where s.estado = 'cancelada'
         and s.motivo = 'atraso_longo'
         and s.tipo = any (c_primeiras)
         and s.decidida_em <= v_agora
         and s.decidida_em > v_desde_conferir
    ), um_por_motivo as (
      select distinct on (c.chave, c.motivo) c.* from c order by c.chave, c.motivo, c.quando desc, c.id
    ), numerados as (
      select u.*, row_number() over (order by u.desde, u.id) as n from um_por_motivo u
    )
    select coalesce(jsonb_agg(jsonb_build_object('phone', n.phone_normalized,
                                                 'rotulo', public._retorno_rotulo(n.id, v_agora),
                                                 'motivo', n.motivo,
                                                 'desde', n.desde) order by n.n)
                      filter (where n.n <= c_conferir_max), '[]'::jsonb),
           count(*)
      into v_conferir, v_conferir_total
      from numerados n;

    return jsonb_build_object(
      'modo', v_modo,
      'esperando', v_com || v_sem,
      'esperando_mais', greatest(v_sem_total - c_sem_prazo_max, 0),
      'conferir', v_conferir,
      'conferir_mais', greatest(v_conferir_total - c_conferir_max, 0));
  end if;

  -- Fechamento. Os casos abertos hoje (recebidos, no prazo, adiados).
  select count(*),
         count(*) filter (where a.cumprida_em is not null and a.cumprida_em <= v_agora
                                and a.prometido_ate is not null and a.cumprida_em <= a.prometido_ate),
         count(*) filter (where a.adiamento_em is not null and a.adiamento_em <= v_agora)
    into v_recebidos, v_no_prazo, v_adiados
    from public.retorno_aberturas a
   where a.nivel in ('recibo', 'passagem')
     and a.gravada_em <= v_agora
     and a.aberta_em >= v_ini_hoje
     and a.aberta_em < v_fim_hoje;

  -- As promessas que venceram sem palavra, desde a mesma hora do último fechamento (a revisão da semana e a do mês não
  -- mostram esses números: o que venceu no dia delas fica para o fechamento seguinte).
  select max(x.d) into v_dia_antes
    from (select v_hoje - g as d from generate_series(1, 10) as g) x
   where public._retorno_turno_da_tarde(x.d) = 'fechamento';
  v_desde_venc := (coalesce(v_dia_antes, v_hoje - 1) + (v_agora at time zone c_fuso)::time) at time zone c_fuso;

  select count(*) filter (where not q.queda), count(*) filter (where q.queda)
    into v_sem_palavra, v_na_queda
    from (select exists (select 1 from public.retorno_saidas f
                          where f.abertura_id = a.id
                            and f.tipo = 'fim_do_dia'
                            and f.estado = 'recusada'
                            and f.motivo = 'so_reativo'
                            and f.decidida_em <= v_agora) as queda
            from public.retorno_aberturas a
           where a.nivel in ('recibo', 'passagem')      -- o filtro do relógio do vigia: o 'nada' calou de propósito
             and a.recibo_em is not null
             and a.recibo_em <= v_agora
             and a.prometido_ate is not null
             and a.gravada_em <= v_agora
             and coalesce(a.segundo_prazo, a.prometido_ate) >= v_desde_venc
             and coalesce(a.segundo_prazo, a.prometido_ate) < v_agora
             and (a.cumprida_em is null or a.cumprida_em > coalesce(a.segundo_prazo, a.prometido_ate))
             and (a.fim_do_dia_em is null or a.fim_do_dia_em > v_agora)) q;

  -- A sombra de hoje: "eu teria mandado" (as saídas de texto em sombra), por papel, e as que o dono respondeu antes.
  select coalesce(sum(x.n), 0)::integer, coalesce(jsonb_object_agg(x.papel, x.n), '{}'::jsonb)
    into v_teria, v_por_papel
    from (select coalesce(a.papel, 'outro') as papel, count(*)::integer as n
            from public.retorno_saidas s
            left join public.retorno_aberturas a on a.id = s.abertura_id
           where s.emissor = 'retorno'
             and s.estado = 'sombra'
             and not (s.tipo = any (c_sem_texto))
             and s.decidida_em >= v_ini_hoje
             and s.decidida_em < v_fim_hoje
             and s.decidida_em <= v_agora
           group by 1) x;

  select count(*)::integer into v_respondeu
    from public.retorno_saidas s
   where s.emissor = 'retorno'
     and s.estado = 'cancelada'
     and s.motivo = 'respondida_pelo_dono'
     and not (s.tipo = any (c_sem_texto))
     and s.decidida_em >= v_ini_hoje
     and s.decidida_em < v_fim_hoje
     and s.decidida_em <= v_agora;

  -- Só na sexta: os alongamentos da semana (B.4.1).
  if extract(isodow from v_hoje) = 5 then
    select coalesce(jsonb_agg(jsonb_build_object('faixa', l.faixa, 'de', l.de, 'para', l.para,
                                                 'casos', l.casos, 'pct', l.pct) order by l.em, l.id), '[]'::jsonb)
      into v_alongadas
      from public.retorno_alongamentos l
     where l.em > v_agora - interval '7 days'
       and l.em <= v_agora;
  else
    v_alongadas := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'modo', v_modo,
    'esperando', v_com,
    'recebidos', v_recebidos,
    'no_prazo', v_no_prazo,
    'adiados', v_adiados,
    'sem_palavra', v_sem_palavra,
    'na_queda', v_na_queda,
    'sombra', jsonb_build_object('teria_mandado', v_teria, 'por_papel', v_por_papel, 'respondeu_antes', v_respondeu),
    'alongadas', v_alongadas);
end;
$$;

comment on function public.retorno_resumo_do_dia(text, timestamptz) is
  'Retorno F1 (C-RESUMO, P9): manha = {modo, esperando (com prazo hoje todos; sem prazo até 3), esperando_mais, conferir (parar_largo, opt_out, atraso_longo; até 3), conferir_mais}; fechamento = {modo, esperando (com prazo hoje, todos), recebidos, no_prazo, adiados, sem_palavra, na_queda, sombra {teria_mandado, por_papel, respondeu_antes}, alongadas (só na sexta)}; outro turno = {"erro": "turno"}. Item de esperando: phone, rotulo, desde, prometido_ate, venceu, com_prazo_hoje, segundo_prazo, ouviu, papel. Nunca devolve texto do cliente; só o que existia até p_agora.';

revoke all on function public.retorno_resumo_do_dia(text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_resumo_do_dia(text, timestamptz) to service_role;

-- ── 4. A calibração da promessa por faixa ────────────────────────────────────────────────────────────

create or replace view public.retorno_calibracao with (security_invoker = on) as
with casos as (
  select a.faixa, a.aberta_em, a.prometido_ate, a.cumprida_em,
         (a.cumprida_em is not null and a.cumprida_em <= a.prometido_ate) as no_prazo,
         -- a hora local da resposta de conteúdo no MESMO dia da mensagem; sem ela, 24:00 (não bateu no dia)
         case when a.cumprida_em is not null
                   and (a.cumprida_em at time zone 'America/Sao_Paulo')::date = (a.aberta_em at time zone 'America/Sao_Paulo')::date
              then (a.cumprida_em at time zone 'America/Sao_Paulo')::time
              else time '24:00' end as hora_no_dia
    from public.retorno_aberturas a
   where a.recibo_em is not null
     and a.prometido_ate is not null
     and a.faixa is not null
     -- o prazo já está decidido: cumprido no prazo, ou o prazo passou
     and ((a.cumprida_em is not null and a.cumprida_em <= a.prometido_ate) or a.prometido_ate <= now())
), agregado as (
  select c.faixa,
         count(*)::integer as casos,
         (count(*) filter (where c.no_prazo))::integer as no_prazo,
         percentile_cont(0.5) within group (order by extract(epoch from (c.cumprida_em - c.aberta_em)) / 60.0)
           as mediana_min,
         percentile_disc(0.8) within group (order by c.hora_no_dia) as p80
    from casos c
   group by c.faixa
)
select g.faixa,
       g.casos,
       g.no_prazo,
       round(g.no_prazo::numeric / g.casos, 4) as pct_no_prazo,
       -- Wilson, 95% (z = 1,959964): (p + z²/2n − z·√(p(1−p)/n + z²/4n²)) / (1 + z²/n), entre 0 e 1
       round(greatest(0, least(1,
         ((g.no_prazo::double precision / g.casos) + 3.841459 / (2 * g.casos)
          - 1.959964 * sqrt(greatest(0, (g.no_prazo::double precision / g.casos) * (1 - g.no_prazo::double precision / g.casos) / g.casos
                                         + 3.841459 / (4.0 * g.casos * g.casos))))
         / (1 + 3.841459 / g.casos)))::numeric, 4) as wilson_inferior,
       round(g.mediana_min::numeric, 1) as mediana_ate_conteudo_min,
       case when g.faixa in ('manha_cedo', 'meio', 'pressa') then nullif(g.p80, time '24:00') end as hora_local_p80_conteudo
  from agregado g;

comment on view public.retorno_calibracao is
  'Retorno F1 (P9, B.4.1): por faixa, os casos com recibo e prazo decidido: casos, no_prazo (conteúdo até o prometido), pct_no_prazo, wilson_inferior (95%), mediana_ate_conteudo_min e hora_local_p80_conteudo (faixas do mesmo dia). Vai ao dono no fim da sombra; o aprovado vira promessa_faixa com OK nomeado.';

revoke all on table public.retorno_calibracao from public, anon, authenticated;
grant select on table public.retorno_calibracao to service_role;

-- ── 5. A lista da sombra (tem texto do cliente: só o service_role) ───────────────────────────────────

create or replace view public.retorno_sombra_lista with (security_invoker = on) as
select s.decidida_em,
       a.papel,
       public._retorno_rotulo(s.abertura_id) as rotulo,
       s.tipo,
       s.variante,
       s.texto,
       s.estado,
       s.dados ->> 'sombra_motivo' as sombra_motivo,
       s.motivo,
       a.nivel,
       a.motivo as caso_motivo,
       left(m.body, 140) as trecho,
       s.abertura_id as caso,
       s.id as saida_id
  from public.retorno_saidas s
  left join public.retorno_aberturas a on a.id = s.abertura_id
  left join public.whatsapp_messages m on m.id = a.primeira_msg_id
 where s.emissor = 'retorno'
   and s.tipo not in ('acorde', 'fila')
   and s.estado in ('sombra', 'enviada');

comment on view public.retorno_sombra_lista is
  'Retorno F1 (P9, B.2): a lista da sombra — uma linha por saída do retorno decidida em sombra ou enviada (fora acorde e fila), com papel, rótulo, texto, motivos, nível e motivo do caso e o trecho (140 caracteres) da 1ª mensagem. Tem texto do cliente: nunca sai pelo WhatsApp; só o service_role lê.';

revoke all on table public.retorno_sombra_lista from public, anon, authenticated;
grant select on table public.retorno_sombra_lista to service_role;

-- ── 6. O próximo evento do relógio (só o replay usa) ─────────────────────────────────────────────────

create or replace function public._retorno_proximo_evento(p_agora timestamptz)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  with cfg as (
    select c.acorde_antes, c.adiamento_antes, c.caso_fecha_silencio, c.incerta_conferir_ate
      from public.retorno_config c
     where c.id
  ), vivos as (
    select a.*
      from public.retorno_aberturas a
     where a.estado in ('aberta', 'vencida')
       and a.gravada_em <= p_agora
  ), eventos as (
    -- as saídas agendadas (de casos que já existiam)
    select s.enviar_em as em
      from public.retorno_saidas s
      join public.retorno_aberturas a on a.id = s.abertura_id
     where s.estado = 'agendada'
       and a.gravada_em <= p_agora
    union all
    -- o relógio dos casos vivos com recibo e sem conteúdo: o acorde, o adiamento, X, o X2 e o prazo de pé
    select x.em
      from vivos v
      cross join cfg
      cross join lateral (values (v.prometido_ate - cfg.acorde_antes),
                                 (v.prometido_ate - cfg.adiamento_antes),
                                 (v.prometido_ate),
                                 (v.segundo_prazo),
                                 (coalesce(v.segundo_prazo, v.prometido_ate))) as x(em)
     where v.recibo_em is not null
       and v.prometido_ate is not null
       and v.cumprida_em is null
    union all
    -- respondido sem conteúdo: o fecho por silêncio
    select v.respondida_em + cfg.caso_fecha_silencio
      from vivos v
      cross join cfg
     where v.respondida_em is not null
       and v.cumprida_em is null
    union all
    -- caso 'nada' parado: pela hora real e pela de gravação
    select x.em
      from vivos v
      cross join cfg
      cross join lateral (values (v.ultima_em + cfg.caso_fecha_silencio),
                                 (v.ultima_gravada_em + cfg.caso_fecha_silencio)) as x(em)
     where v.nivel = 'nada'
    union all
    -- as incertas: a conferência na conversa (de 10 min a incerta_conferir_ate)
    select x.em
      from public.retorno_saidas s
      cross join cfg
      cross join lateral (values (s.decidida_em + interval '10 minutes'),
                                 (s.decidida_em + cfg.incerta_conferir_ate)) as x(em)
     where s.estado = 'incerta'
       and s.decidida_em <= p_agora
    union all
    -- a próxima 04:00 de Brasília (arquivar, retenção, alongamento)
    select ((((p_agora at time zone 'America/Sao_Paulo')::date
              + case when (p_agora at time zone 'America/Sao_Paulo')::time < time '04:00' then 0 else 1 end)
             + time '04:00') at time zone 'America/Sao_Paulo')
  )
  select min(e.em) from eventos e where e.em > p_agora;
$$;

comment on function public._retorno_proximo_evento(timestamptz) is
  'Retorno F1 (P9.3, só o replay): o menor instante depois de p_agora em que o relógio do retorno muda algo (agendadas, acorde, adiamento, X, X2, fecho por silêncio, caso nada parado, incertas, a próxima 04:00 de Brasília).';

revoke all on function public._retorno_proximo_evento(timestamptz) from public, anon, authenticated;
