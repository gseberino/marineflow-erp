set local lock_timeout = '3s'; set local statement_timeout = '90s';
-- Retorno F1 (P9.3): o REPLAY em dados reais, UMA janela por execução. Roda à parte, pelo
-- montar_teste.sh replay (P15), nunca na bancada rápida; de noite (22:00–06:00, fora de 04:00–04:30), só depois do
-- pacote de 10/11 (o P1 já no banco) e antes de o retorno ir ao ar (16/11): a janela tem de ser de dias em que o
-- retorno ainda não existia (senão o retorno_abrir veria as mensagens como 'repetida'; o arquivo confere e para).
-- O script aplica antes, na mesma transação, as migrations P2–P6 e P9.1 (nunca o P7, o gatilho da fila, nem o P9.2,
-- o cron) e troca os três marcadores da janela pelo instante (texto aceito por timestamptz, sem aspas: as aspas já
-- estão aqui), por exemplo 2026-08-03 00:00:00-03:
--   INICIO  — o começo da janela que conta;
--   FIM     — o fim da janela (exclusivo): [INICIO, FIM);
--   AQUECER — o começo do aquecimento (INICIO − 1 dia): os casos e saídas do aquecimento participam, mas não contam.
--
-- 1. Travas e tempo: a 1ª linha (acima) e de novo logo depois do begin. A CLI passa pelo Cloudflare e é cortada com
--    524 perto de 100 s, e o papel postgres tem statement_timeout = 2min: com 90 s, a falha volta como erro do banco,
--    sem processo órfão segurando trava; trava que não vem em 3 s falha na hora. A configuração fica modo 'sombra',
--    tipos_ligados '{}', sem os interruptores do dia (so_reativo, fora_ate, segura_*).
-- 2. Áudio como ele chegou: a temp _corpos guarda o body real das recebidas 'audio' da janela (com o aquecimento), e
--    o body vira '[audio]' dentro da transação (o rollback desfaz; whatsapp_messages não tem gatilho de UPDATE). O
--    evento "transcrição" devolve o body real em occurred_at + 1 min (a transcrição em linha do webhook). Sem isso o
--    replay leria o texto já transcrito e superestimaria a revocação.
--    A promessa do dono como ela estava (seção 2.2 da spec): a regra 12 do _retorno_triar exige status 'ativo', que é o
--    status de HOJE, e toda promessa vencida já está encerrada ('avisado', logo depois do lembrar_em). Com a regra 12
--    morta, quem tinha promessa ganharia recibo simulado, o que incharia o "teria mandado" e os recibos perto de
--    resposta humana, dois números do portão. Por isso, dentro da transação (o rollback desfaz; a tabela não tem gatilho
--    e o índice único só vale para o modo 'acompanhar'), as promessas que valeram em algum ponto da janela voltam a
--    'ativo': o created_at e o lembrar_em delimitam a validade, e o _retorno_triar os confere contra a hora do replay.
--    A que caiu antes do prazo (pedido do dono; nenhuma até 04/11/2026) fica encerrada: não se sabe até quando valeu.
--    A contagem vai em promessas_reativadas.
-- 3. Viagem no tempo por eventos, a partir de t = AQUECER. Em cada volta: (1) devolve os bodies cuja transcrição vence
--    até t; (2) retorno_abrir(id, false, occurred_at) para as recebidas com occurred_at em (t anterior, t], em ordem;
--    (3) retorno_vigia(t); (4) retorno_pegar(t) até devolver nulo sem nada vencido, registrando cada item com
--    retorno_registrar_decisao(id, 'sombra', {"validador": null}, t); (5) o próximo t é o menor entre a próxima
--    recebida, a próxima transcrição, a próxima saída humana, _retorno_proximo_evento(t) e t + 60 min. Como toda
--    leitura respeita occurred_at <= agora, a resposta que o dono deu depois do enviar_em não cancela o recibo, e a que
--    deu antes cancela.
--    Desvio da spec (fidelidade, levado à coordenação): a spec não põe a saída humana entre os eventos. Em produção o
--    vigia roda a cada minuto e fecha o caso logo depois da resposta de conteúdo; sem esse evento, ele só veria a
--    resposta na volta seguinte, e como o retorno_abrir vem antes do vigia, a recebida que chega até 60 min depois
--    estenderia o caso já respondido e fecharia junto com ele. A pergunta nova ficaria sem recibo, e o replay
--    subestimaria o "teria mandado" e a revocação, que são medidas do portão.
--    O disjuntor pela conexão (vigia, passo 2) lê whatsapp_conexao_vigia, que é o estado de HOJE, não o da janela:
--    se ele ligar o so_reativo pela conexão, o arquivo o desliga de novo e conta em disjuntor_anulado (limitação).
-- 4. Números (para _bancada.numeros, sem texto de cliente nem telefone): casos por papel e nível; "teria mandado"
--    por papel, por tipo e por dia (útil ou não); canceladas e recusadas por motivo; acordes simulados; recibos a
--    menos de 10 min de uma resposta humana (contagem e total); por lote (r1sql/r17-lotes.sql: minutos com ≥ 5
--    linhas gravadas com mais de 2 min de atraso), os textos de volta e os textos a quem já tinha sido respondido; e
--    recibos_numero_novo = [{cid: left(md5(phone), 6), metade}] (0 = ajuste, 1 = teste) para a revocação, que o
--    script agrega com os rótulos de retorno-rapido/sql/fi; e erros_logados (o que foi ao app_error_logs nesta
--    execução, por ação/nível, sem a mensagem).
--    "Recibos" aqui = recibo_cliente, recibo_ambiguo, recibo_numero_novo e saudacao_numero_novo (a 1ª mensagem
--    automática do caso).
-- 5. Falhas na própria janela (raise exception, com a contagem e os cid/caso, nunca telefone nem texto):
--    - público errado: recibo em sombra a equipe, fornecedor ativo, robô (o caso só tinha mensagem de robô até a
--      decisão), vendedor (número novo), lead_tipo 'pessoal', contato_conhecido ou cliente_parceiro;
--    - duplicado: 2 recibos à mesma chave em menos de recibo_intervalo (12 h), de casos diferentes;
--    - ambíguo (J.3, a travessia dos 13 números compartilhados): ao número com 2 ou mais clientes ativos, recibo que
--      não seja recibo_ambiguo/padrao, ou texto com nome de cliente ({nome} preenchido), "OS-"/"ORÇ-", ou fora do
--      modelo fixo (o texto que o _retorno_texto daria com os mesmos dados);
--    - olhar o futuro: saída cancelada por respondida_pelo_dono sem resposta humana gravada até a hora da cancela.
--    Também falham os erros do próprio replay (retorno_abrir com ok = false, retorno_vigia com passo em erro,
--    retorno_registrar_decisao recusada) e a saída recusada/erro: em produção o retorno_pegar engole a exceção para a
--    fila não travar, mas no replay ela é defeito e não pode passar calada pelo portão. A recusada/texto (22023, dado
--    fora da lista fechada) é a falha fecha esperada: só conta em recusadas_por_motivo.
-- 6. A agregação das janelas (lotes ≤ 10 textos e 0 a quem já tinha sido respondido; recibos perto de resposta humana
--    ≤ 10%; revocação ≥ 80% na metade de teste) é do script (P15). A precisão (≥ 95%) o dono confere na
--    retorno_sombra_lista.
-- Limitações (vão no relatório): quem_escreve e canal_bloqueado usam os cadastros e a lista de bloqueio de hoje; a
-- transcrição é simulada em 1 min; o estado da conexão é o de hoje (o disjuntor é anulado); os leitores de
-- confirmação, conferência e revisão entram como não consumidos (p_consumida = false; a agenda é lida da tabela); o
-- PARAR anterior à F0b não tem opt-out gravado na hora (o gatilho não existia): no replay ele cai em parar_largo, e a
-- saída 'parar' (a confirmação) não aparece nos números.
-- Termina em ROLLBACK: nada fica gravado (nem os bodies trocados, nem as promessas reativadas, nem os casos, nem as
-- coletas nos leads).
begin;
set local lock_timeout = '3s';
set local statement_timeout = '90s';
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());
create temp table if not exists _corpos (id uuid primary key, corpo text, volta_em timestamptz not null,
                                         devolvido boolean not null default false);
create temp table if not exists _humanas (em timestamptz primary key);   -- as saídas humanas da janela, como eventos

-- O texto que o modelo fixo daria com os mesmos dados; nulo se o _retorno_texto recusa.
create or replace function pg_temp.retorno_f1_replay_modelo(p_tipo text, p_variante text, p_dados jsonb)
returns text
language plpgsql as $f$
begin
  return public._retorno_texto(p_tipo, p_variante, p_dados);
exception when others then
  return null;
end $f$;

do $replay$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_aquecer_txt constant text := '{{AQUECER}}';
  c_inicio_txt constant text := '{{INICIO}}';
  c_fim_txt constant text := '{{FIM}}';
  c_primeiras constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo'];
  c_sem_texto constant text[] := array['acorde', 'cadastro_provisorio', 'fila'];
  c_max_voltas constant integer := 20000;
  c_max_pegar constant integer := 500;
  v_relogio timestamptz := clock_timestamp();
  v_aquecer timestamptz;
  v_inicio timestamptz;
  v_fim timestamptz;
  v_dia_ini date;
  v_dia_fim date;
  v_cfg public.retorno_config;
  v_t timestamptz;
  v_t_antes timestamptz;
  v_prox timestamptz;
  v_m record;
  v_r jsonb;
  v_d jsonb;
  v_k integer;
  v_voltas integer := 0;
  v_recebidas integer := 0;
  v_recebidas_janela integer := 0;
  v_pegas integer := 0;
  v_audios integer := 0;
  v_devolvidos integer := 0;
  v_promessas integer := 0;
  v_n integer;
  v_disjuntor integer := 0;
  v_n_erros integer := 0;
  v_erros jsonb := '[]'::jsonb;
  v_casos jsonb;
  v_teria jsonb;
  v_canceladas jsonb;
  v_recusadas jsonb;
  v_logados jsonb;
  v_acordes jsonb;
  v_perto integer;
  v_recibos integer;
  v_lotes jsonb;
  v_rnn jsonb;
  v_publico jsonb;
  v_duplicado jsonb;
  v_ambiguo jsonb;
  v_futuro jsonb;
  v_n_falhas integer;
  v_numeros jsonb;
begin
  -- ── 0. A janela, as funções e as premissas ───────────────────────────────────────────────────────────
  if c_aquecer_txt like '{%' or c_inicio_txt like '{%' or c_fim_txt like '{%' then
    raise exception 'replay: os marcadores da janela (INICIO, FIM e AQUECER) não foram trocados: rode pelo montar_teste.sh replay';
  end if;
  v_aquecer := c_aquecer_txt::timestamptz;
  v_inicio := c_inicio_txt::timestamptz;
  v_fim := c_fim_txt::timestamptz;
  if not (v_aquecer <= v_inicio and v_inicio < v_fim) then
    raise exception 'replay: janela torta (aquecer %, início %, fim %)', v_aquecer, v_inicio, v_fim;
  end if;
  if v_fim > now() then
    raise exception 'replay: a janela termina no futuro (%); o replay é de dias que já passaram', v_fim;
  end if;
  if to_regprocedure('public.retorno_abrir(uuid, boolean, timestamptz)') is null
     or to_regprocedure('public.retorno_vigia(timestamptz)') is null
     or to_regprocedure('public.retorno_pegar(timestamptz)') is null
     or to_regprocedure('public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz)') is null
     or to_regprocedure('public.retorno_tem_vencido(timestamptz)') is null
     or to_regprocedure('public._retorno_proximo_evento(timestamptz)') is null
     or to_regprocedure('public._retorno_texto(text, text, jsonb)') is null then
    raise exception 'replay: faltam funções do retorno (o montar_teste.sh replay aplica P2–P6 e P9.1 antes deste arquivo)';
  end if;
  select * into v_cfg from public.retorno_config c where c.id;
  if not found then
    raise exception 'replay: retorno_config sem a linha de configuração (P1, pacote de 10/11)';
  end if;
  -- A janela tem de ser de antes do retorno no ar: nenhum caso, mensagem lida ou saída real até o fim dela.
  if exists (select 1 from public.retorno_aberturas a where a.gravada_em < v_fim)
     or exists (select 1 from public.retorno_mensagens rm where rm.gravada_em < v_fim)
     or exists (select 1 from public.retorno_saidas s where coalesce(s.decidida_em, s.enviar_em) < v_fim) then
    raise exception 'replay: já há casos, mensagens lidas ou saídas do retorno até o fim da janela (%); o replay só vale para dias anteriores ao retorno no ar', v_fim;
  end if;

  -- A configuração do replay: sombra, nada ligado e sem os interruptores de hoje.
  update public.retorno_config
     set modo = 'sombra', tipos_ligados = '{}', so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null,
         erros_seguidos = 0, fora_ate = null, segura_recibos = false, segura_tudo_ate = null, proximo_envio_em = null
   where id;

  -- A promessa do dono como ela estava: a que valeu em algum ponto da janela volta a 'ativo' (o rollback desfaz).
  update public.whatsapp_acompanhamentos w
     set status = 'ativo'
   where w.modo = 'promessa'
     and w.status <> 'ativo'
     and w.created_at < v_fim
     and w.lembrar_em > v_aquecer
     and w.updated_at >= w.lembrar_em;
  get diagnostics v_promessas = row_count;

  -- ── 2. O áudio como ele chegou ───────────────────────────────────────────────────────────────────────
  delete from _corpos;
  insert into _corpos (id, corpo, volta_em)
  select w.id, w.body, w.occurred_at + interval '1 minute'
    from public.whatsapp_messages w
   where w.direction = 'inbound'
     and w.message_type = 'audio'
     and w.occurred_at >= v_aquecer
     and w.occurred_at < v_fim
     and w.body is distinct from '[audio]';
  update public.whatsapp_messages w
     set body = '[audio]'
    from _corpos c
   where c.id = w.id;
  get diagnostics v_audios = row_count;

  -- ── 3. A viagem no tempo, por eventos ────────────────────────────────────────────────────────────────
  delete from _humanas;
  insert into _humanas (em)
  select distinct o.occurred_at
    from public.whatsapp_messages o
   where o.direction = 'outbound'
     and o.occurred_at >= v_aquecer
     and o.occurred_at < v_fim
     and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by));

  v_t_antes := v_aquecer - interval '1 microsecond';
  v_t := v_aquecer;
  while v_t < v_fim loop
    v_voltas := v_voltas + 1;
    if v_voltas > c_max_voltas then
      raise exception 'replay: mais de % voltas sem chegar ao fim da janela (t = %)', c_max_voltas, v_t;
    end if;

    -- (1) as transcrições que vencem até t
    update public.whatsapp_messages w
       set body = c.corpo
      from _corpos c
     where c.id = w.id
       and not c.devolvido
       and c.volta_em <= v_t;
    get diagnostics v_n = row_count;
    v_devolvidos := v_devolvidos + v_n;
    update _corpos set devolvido = true where not devolvido and volta_em <= v_t;

    -- (2) as recebidas de (t anterior, t], em ordem
    for v_m in
      select w.id, w.occurred_at
        from public.whatsapp_messages w
       where w.direction = 'inbound'
         and w.occurred_at > v_t_antes
         and w.occurred_at <= v_t
         and not coalesce(w.is_broadcast, false)
         and strpos(w.phone_normalized, '@') = 0
       order by w.occurred_at, w.id
    loop
      v_r := public.retorno_abrir(v_m.id, false, v_m.occurred_at);
      v_recebidas := v_recebidas + 1;
      if v_m.occurred_at >= v_inicio then
        v_recebidas_janela := v_recebidas_janela + 1;
      end if;
      if v_r -> 'ok' is distinct from 'true'::jsonb then
        v_n_erros := v_n_erros + 1;
        if jsonb_array_length(v_erros) < 5 then
          v_erros := v_erros || jsonb_build_array(jsonb_build_object('onde', 'abrir', 't', v_m.occurred_at,
                                                                     'erro', left(v_r ->> 'erro', 120)));
        end if;
      end if;
    end loop;

    -- (3) o vigia; o disjuntor pela conexão de HOJE não vale para a janela
    v_r := public.retorno_vigia(v_t);
    if v_r -> 'ok' is distinct from 'true'::jsonb then
      v_n_erros := v_n_erros + 1;
      if jsonb_array_length(v_erros) < 5 then
        v_erros := v_erros || jsonb_build_array(jsonb_build_object('onde', 'vigia', 't', v_t, 'passos', v_r -> 'erros'));
      end if;
    end if;
    update public.retorno_config
       set so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null
     where id and so_reativo_motivo = 'conexao';
    if found then
      v_disjuntor := v_disjuntor + 1;
    end if;

    -- (4) pegar até não sobrar nada vencido; cada item vira "eu teria mandado"
    v_k := 0;
    loop
      v_r := public.retorno_pegar(v_t);
      if v_r is null then
        exit when not public.retorno_tem_vencido(v_t);
      else
        v_pegas := v_pegas + 1;
        v_d := public.retorno_registrar_decisao((v_r ->> 'saida_id')::uuid, 'sombra', '{"validador": null}'::jsonb, v_t);
        if v_d -> 'ok' is distinct from 'true'::jsonb then
          v_n_erros := v_n_erros + 1;
          if jsonb_array_length(v_erros) < 5 then
            v_erros := v_erros || jsonb_build_array(jsonb_build_object('onde', 'decisao', 't', v_t, 'modo', v_r ->> 'modo',
                                                                       'erro', v_d ->> 'erro'));
          end if;
        end if;
      end if;
      v_k := v_k + 1;
      if v_k > c_max_pegar then
        raise exception 'replay: o retorno_pegar não esvaziou o que venceu até % em % chamadas', v_t, c_max_pegar;
      end if;
    end loop;

    -- (5) o próximo t
    v_t_antes := v_t;
    select least(
             (select min(w.occurred_at)
                from public.whatsapp_messages w
               where w.direction = 'inbound'
                 and w.occurred_at > v_t
                 and w.occurred_at < v_fim
                 and not coalesce(w.is_broadcast, false)
                 and strpos(w.phone_normalized, '@') = 0),
             (select min(c.volta_em) from _corpos c where not c.devolvido and c.volta_em > v_t),
             (select min(h.em) from _humanas h where h.em > v_t),
             public._retorno_proximo_evento(v_t),
             v_t + interval '60 minutes')
      into v_prox;
    v_t := v_prox;
  end loop;

  -- ── 4. Os números (sem texto de cliente nem telefone) ────────────────────────────────────────────────
  v_dia_ini := (v_inicio at time zone c_fuso)::date;
  v_dia_fim := ((v_fim - interval '1 microsecond') at time zone c_fuso)::date;

  -- os casos da janela (pela hora de gravação), por papel e nível
  select coalesce(jsonb_object_agg(x.papel, x.niveis), '{}'::jsonb)
    into v_casos
    from (select y.papel, jsonb_object_agg(y.nivel, y.n) as niveis
            from (select a.papel, a.nivel, count(*)::integer as n
                    from public.retorno_aberturas a
                   where a.gravada_em >= v_inicio and a.gravada_em < v_fim
                   group by 1, 2) y
           group by y.papel) x;

  -- "teria mandado": as saídas de texto em sombra decididas na janela, por papel, por tipo e por dia
  with t as (
    select s.tipo, coalesce(a.papel, 'outro') as papel, (s.decidida_em at time zone c_fuso)::date as dia
      from public.retorno_saidas s
      left join public.retorno_aberturas a on a.id = s.abertura_id
     where s.emissor = 'retorno'
       and s.estado = 'sombra'
       and not (s.tipo = any (c_sem_texto))
       and s.decidida_em >= v_inicio and s.decidida_em < v_fim
  ), dias as (
    select v_dia_ini + g as dia, public.agenda_dia_util(v_dia_ini + g) as util
      from generate_series(0, v_dia_fim - v_dia_ini) as g
  )
  select jsonb_build_object(
           'total', (select count(*) from t),
           'por_papel', (select coalesce(jsonb_object_agg(z.papel, z.n), '{}'::jsonb)
                           from (select t.papel, count(*)::integer as n from t group by 1) z),
           'por_tipo', (select coalesce(jsonb_object_agg(z.tipo, z.n), '{}'::jsonb)
                          from (select t.tipo, count(*)::integer as n from t group by 1) z),
           'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'util', d.util,
                                                                    'total', coalesce(p.total, 0),
                                                                    'por_papel', coalesce(p.por_papel, '{}'::jsonb))
                                                 order by d.dia), '[]'::jsonb)
                         from dias d
                         left join (select z.dia, sum(z.n)::integer as total, jsonb_object_agg(z.papel, z.n) as por_papel
                                      from (select t.dia, t.papel, count(*)::integer as n from t group by 1, 2) z
                                     group by z.dia) p on p.dia = d.dia),
           'dias_uteis', (select count(*) from dias where dias.util),
           'em_dia_util', (select count(*) from t join dias d on d.dia = t.dia where d.util),
           'a_cliente_em_dia_util', (select count(*) from t join dias d on d.dia = t.dia where d.util and t.papel = 'cliente'))
    into v_teria;

  -- canceladas e recusadas por motivo
  select coalesce(jsonb_object_agg(x.motivo, x.n), '{}'::jsonb)
    into v_canceladas
    from (select coalesce(s.motivo, '?') as motivo, count(*)::integer as n
            from public.retorno_saidas s
           where s.emissor = 'retorno' and s.estado = 'cancelada'
             and s.decidida_em >= v_inicio and s.decidida_em < v_fim
           group by 1) x;
  select coalesce(jsonb_object_agg(x.motivo, x.n), '{}'::jsonb)
    into v_recusadas
    from (select coalesce(s.motivo, '?') as motivo, count(*)::integer as n
            from public.retorno_saidas s
           where s.emissor = 'retorno' and s.estado = 'recusada'
             and s.decidida_em >= v_inicio and s.decidida_em < v_fim
           group by 1) x;

  -- a exceção que o retorno_pegar engole (recusada/erro) é defeito aqui, com ou sem aquecimento: vai com o sqlstate
  for v_m in
    select s.tipo, s.dados -> 'erro' ->> 'sqlstate' as sqlstate
      from public.retorno_saidas s
     where s.emissor = 'retorno' and s.estado = 'recusada' and s.motivo = 'erro'
     order by s.decidida_em, s.id
  loop
    v_n_erros := v_n_erros + 1;
    if jsonb_array_length(v_erros) < 5 then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('onde', 'saida', 'tipo', v_m.tipo, 'sqlstate', v_m.sqlstate));
    end if;
  end loop;

  -- o que foi ao app_error_logs nesta execução (o upsert por fingerprint grava last_seen_at = now()), sem a mensagem
  select coalesce(jsonb_object_agg(x.acao, x.n), '{}'::jsonb)
    into v_logados
    from (select coalesce(l.action, '?') || '/' || coalesce(l.level, '?') as acao, count(*)::integer as n
            from public.app_error_logs l
           where l.context = 'retorno'
             and l.last_seen_at >= now()
           group by 1) x;

  -- os acordes simulados ("eu teria acordado o Gustavo")
  select jsonb_build_object('total', coalesce(sum(x.n), 0),
                            'acordaria', coalesce(sum(x.acordaria), 0),
                            'por_variante', coalesce(jsonb_object_agg(x.variante, x.n), '{}'::jsonb))
    into v_acordes
    from (select coalesce(s.variante, '?') as variante, count(*)::integer as n,
                 (count(*) filter (where coalesce((s.dados ->> 'acordaria')::boolean, false)))::integer as acordaria
            from public.retorno_saidas s
           where s.emissor = 'retorno' and s.tipo = 'acorde' and s.estado = 'sombra'
             and s.decidida_em >= v_inicio and s.decidida_em < v_fim
           group by 1) x;

  -- recibos a menos de 10 min (antes ou depois, pela hora real) de uma resposta humana à chave
  select count(*) filter (where x.perto)::integer, count(*)::integer
    into v_perto, v_recibos
    from (select exists (select 1 from public.whatsapp_messages o
                          where public._agenda_chave_telefone(o.phone_normalized) = s.chave
                            and o.direction = 'outbound'
                            and o.occurred_at > s.decidida_em - interval '1 day'
                            and o.occurred_at < s.decidida_em + interval '7 days'
                            and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by))
                            and public._retorno_hora_real(o) > s.decidida_em - interval '10 minutes'
                            and public._retorno_hora_real(o) < s.decidida_em + interval '10 minutes') as perto
            from public.retorno_saidas s
           where s.emissor = 'retorno' and s.estado = 'sombra' and s.tipo = any (c_primeiras)
             and s.decidida_em >= v_inicio and s.decidida_em < v_fim) x;

  -- por lote (r17-lotes.sql: minuto com 5+ linhas gravadas com mais de 2 min de atraso): os recibos de volta dos casos
  -- tocados pelo lote (decididos até 24 h depois) e os que iriam a quem o dono já tinha respondido (pela hora real)
  with m as (
    select date_trunc('minute', w.occurred_at) as minuto
      from public.whatsapp_messages w
     where w.occurred_at >= v_inicio and w.occurred_at < v_fim
       and w.occurred_at - public._retorno_hora_real(w) > interval '2 minutes'
  ), lote as (
    select m.minuto, count(*)::integer as linhas from m group by m.minuto having count(*) >= 5
  ), voltas as (
    select l.minuto, s.id as saida, s.chave, s.decidida_em, min(rm.recebida_em) as real_min
      from lote l
      join public.retorno_mensagens rm
        on rm.gravada_em >= l.minuto and rm.gravada_em < l.minuto + interval '1 minute'
       and rm.gravada_em - rm.recebida_em > interval '2 minutes'
      join public.retorno_saidas s
        on s.abertura_id = rm.abertura_id
       and s.emissor = 'retorno' and s.estado = 'sombra' and s.tipo = any (c_primeiras)
       and s.decidida_em >= l.minuto and s.decidida_em < l.minuto + interval '24 hours'
     group by l.minuto, s.id, s.chave, s.decidida_em
  )
  select coalesce(jsonb_agg(jsonb_build_object('minuto', y.minuto, 'linhas', y.linhas, 'textos', y.textos,
                                               'ja_respondidos', y.ja) order by y.minuto), '[]'::jsonb)
    into v_lotes
    from (select l.minuto, l.linhas,
                 count(v.saida)::integer as textos,
                 (count(v.saida) filter (where exists (
                    select 1 from public.whatsapp_messages o
                     where public._agenda_chave_telefone(o.phone_normalized) = v.chave
                       and o.direction = 'outbound'
                       and o.occurred_at > v.real_min - interval '10 minutes'
                       and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by))
                       and public._retorno_hora_real(o) > v.real_min
                       and public._retorno_hora_real(o) <= v.decidida_em)))::integer as ja
            from lote l
            left join voltas v on v.minuto = l.minuto
           group by l.minuto, l.linhas) y;

  -- para a revocação: os números novos que receberiam recibo (cid e metade, nunca o telefone)
  select coalesce(jsonb_agg(x.o order by x.o ->> 'cid'), '[]'::jsonb)
    into v_rnn
    from (select distinct jsonb_build_object('cid', left(md5(s.phone_normalized), 6),
                                             'metade', (('x' || substr(md5(s.phone_normalized), 7, 1))::bit(4)::integer % 2)) as o
            from public.retorno_saidas s
           where s.emissor = 'retorno' and s.estado = 'sombra' and s.tipo = 'recibo_numero_novo'
             and s.decidida_em >= v_inicio and s.decidida_em < v_fim) x;

  -- ── 5. As falhas na própria janela ───────────────────────────────────────────────────────────────────
  -- público errado
  with r as (
    select s.id, s.abertura_id, s.phone_normalized, s.decidida_em, a.papel, a.quem, a.chave,
           public.quem_escreve(s.phone_normalized) ->> 'papel' as papel_hoje
      from public.retorno_saidas s
      join public.retorno_aberturas a on a.id = s.abertura_id
     where s.emissor = 'retorno' and s.estado = 'sombra' and s.tipo = any (c_primeiras)
       and s.decidida_em >= v_inicio and s.decidida_em < v_fim
  ), errado as (
    select r.*,
           case
             when r.papel in ('fornecedor', 'contato_conhecido', 'cliente_parceiro') then r.papel
             when r.quem ->> 'papel' = 'equipe' or r.papel_hoje = 'equipe' then 'equipe'
             when r.papel_hoje = 'fornecedor' then 'fornecedor'
             when exists (select 1 from public.whatsapp_leads l
                           where l.lead_tipo = 'pessoal'
                             and public._agenda_chave_telefone(l.phone_normalized) = r.chave) then 'pessoal'
             when r.papel = 'numero_novo'
                  and exists (select 1 from public.retorno_mensagens rm
                               where rm.abertura_id = r.abertura_id
                                 and rm.gravada_em <= r.decidida_em
                                 and coalesce((rm.sinais ->> 'vendedor')::boolean, false)) then 'vendedor'
             when exists (select 1 from public.retorno_mensagens rm
                           where rm.abertura_id = r.abertura_id
                             and rm.gravada_em <= r.decidida_em
                             and rm.pede_motivo = 'robo')
                  and not exists (select 1 from public.retorno_mensagens rm
                                   where rm.abertura_id = r.abertura_id
                                     and rm.gravada_em <= r.decidida_em
                                     and rm.pede_resposta) then 'robo'
           end as por
      from r
  )
  select coalesce(jsonb_agg(jsonb_build_object('cid', left(md5(e.phone_normalized), 6), 'caso', e.abertura_id, 'por', e.por)
                            order by e.decidida_em), '[]'::jsonb)
    into v_publico
    from errado e
   where e.por is not null;

  -- duplicado: 2 recibos à mesma chave em menos de recibo_intervalo, de casos diferentes
  select coalesce(jsonb_agg(jsonb_build_object('cid', left(md5(s2.phone_normalized), 6),
                                               'casos', jsonb_build_array(s1.abertura_id, s2.abertura_id))
                            order by s2.decidida_em), '[]'::jsonb)
    into v_duplicado
    from public.retorno_saidas s2
    join public.retorno_saidas s1
      on s1.chave = s2.chave
     and s1.id <> s2.id
     and s1.abertura_id is distinct from s2.abertura_id
     and s1.emissor = 'retorno' and s1.estado = 'sombra' and s1.tipo = any (c_primeiras)
     and (s1.decidida_em < s2.decidida_em or (s1.decidida_em = s2.decidida_em and s1.id < s2.id))
     and s2.decidida_em - s1.decidida_em < v_cfg.recibo_intervalo
   where s2.emissor = 'retorno' and s2.estado = 'sombra' and s2.tipo = any (c_primeiras)
     and s2.decidida_em >= v_inicio and s2.decidida_em < v_fim;

  -- ambíguo: ao número com 2+ clientes ativos, só o recibo_ambiguo/padrao, sem nome, sem OS e dentro do modelo
  with s as (
    select s.id, s.tipo, s.variante, s.texto, s.dados, s.phone_normalized, s.abertura_id, s.decidida_em,
           (select count(*) from public.clients c
             where c.active and not c.generico
               and s.chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))) as n_clientes
      from public.retorno_saidas s
     where s.emissor = 'retorno' and s.estado = 'sombra' and not (s.tipo = any (c_sem_texto))
       and s.decidida_em >= v_inicio and s.decidida_em < v_fim
  ), errado as (
    select s.*,
           case
             when s.tipo = any (c_primeiras) and not (s.tipo = 'recibo_ambiguo' and s.variante = 'padrao') then 'variante'
             when coalesce(s.texto, '') ~ '(OS-|ORÇ-|ORC-)' then 'os'
             when s.dados ? 'nome' then 'nome'
             when pg_temp.retorno_f1_replay_modelo(s.tipo, s.variante, s.dados) is distinct from s.texto then 'fora_do_modelo'
           end as por
      from s
     where s.n_clientes >= 2
  )
  select coalesce(jsonb_agg(jsonb_build_object('cid', left(md5(e.phone_normalized), 6), 'caso', e.abertura_id,
                                               'tipo', e.tipo, 'por', e.por) order by e.decidida_em), '[]'::jsonb)
    into v_ambiguo
    from errado e
   where e.por is not null;

  -- olhar o futuro: cancelada por respondida_pelo_dono sem resposta humana gravada até a hora da cancela
  select coalesce(jsonb_agg(jsonb_build_object('cid', left(md5(s.phone_normalized), 6), 'caso', s.abertura_id, 'tipo', s.tipo)
                            order by s.decidida_em), '[]'::jsonb)
    into v_futuro
    from public.retorno_saidas s
    join public.retorno_aberturas a on a.id = s.abertura_id
   where s.emissor = 'retorno'
     and s.estado = 'cancelada'
     and s.motivo = 'respondida_pelo_dono'
     and s.decidida_em >= v_inicio and s.decidida_em < v_fim
     and not exists (select 1 from public.whatsapp_messages o
                      where public._agenda_chave_telefone(o.phone_normalized) = a.chave
                        and o.direction = 'outbound'
                        and o.occurred_at <= s.decidida_em
                        and o.occurred_at > least(a.aberta_em, a.gravada_em) - interval '10 minutes'
                        and (public._retorno_hora_real(o) > a.aberta_em or o.occurred_at > a.gravada_em)
                        and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by))
                        and (s.tipo not in ('adiamento', 'fim_do_dia')
                             or o.message_type in ('audio', 'document')
                             or length(btrim(coalesce(o.body, ''))) > v_cfg.conteudo_min_caracteres));

  v_n_falhas := jsonb_array_length(v_publico) + jsonb_array_length(v_duplicado) + jsonb_array_length(v_ambiguo)
                + jsonb_array_length(v_futuro);

  v_numeros := jsonb_build_object(
    'janela', jsonb_build_object('aquecer', v_aquecer, 'inicio', v_inicio, 'fim', v_fim),
    'duracao_s', round(extract(epoch from (clock_timestamp() - v_relogio))::numeric, 1),
    'voltas', v_voltas,
    'recebidas', v_recebidas,
    'recebidas_janela', v_recebidas_janela,
    'audios_trocados', v_audios,
    'transcricoes_devolvidas', v_devolvidos,
    'promessas_reativadas', v_promessas,
    'saidas_decididas', v_pegas,
    'disjuntor_anulado', v_disjuntor,
    'casos', v_casos,
    'teria_mandado', v_teria,
    'canceladas_por_motivo', v_canceladas,
    'recusadas_por_motivo', v_recusadas,
    'erros_logados', v_logados,
    'acordes', v_acordes,
    'recibos_perto_de_resposta_humana', jsonb_build_object('perto', v_perto, 'total', v_recibos),
    'lotes', v_lotes,
    'recibos_numero_novo', v_rnn,
    'falhas', jsonb_build_object('publico_errado', jsonb_array_length(v_publico),
                                 'duplicado', jsonb_array_length(v_duplicado),
                                 'ambiguo', jsonb_array_length(v_ambiguo),
                                 'olhar_o_futuro', jsonb_array_length(v_futuro),
                                 'erros_do_replay', v_n_erros));

  if v_n_falhas > 0 or v_n_erros > 0 then
    raise exception 'replay: % falha(s) e % erro(s) na janela [%, %): %', v_n_falhas, v_n_erros, v_inicio, v_fim,
      left(jsonb_build_object('publico_errado', v_publico, 'duplicado', v_duplicado, 'ambiguo', v_ambiguo,
                              'olhar_o_futuro', v_futuro, 'erros', v_erros,
                              'falhas', v_numeros -> 'falhas', 'duracao_s', v_numeros -> 'duracao_s')::text, 6000);
  end if;

  insert into _bancada (arquivo, ok, numeros) values ('retorno_f1_replay', true, v_numeros);
end
$replay$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
