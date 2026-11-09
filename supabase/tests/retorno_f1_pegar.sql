-- Retorno F1 (P6): pegar e decidir as saídas (retorno_pegar, _retorno_checar_antes, retorno_registrar_decisao e
-- retorno_tem_vencido), 20261116100700_retorno_f1_pegar.sql.
--   0. as funções (volatilidade, SECURITY DEFINER com search_path, fechadas a anon e authenticated) e as premissas:
--      a linha de configuração, o calendário de janeiro de 2027 na agenda de produção (só lida), nenhuma mensagem
--      gravada nos dias do arquivo e nenhuma saída agendada fora dos números de teste (retorno_pegar pega a mais
--      antiga do banco inteiro: o arquivo é da bancada de antes do deploy de 16/11);
--   1. SKIP LOCKED na mesma sessão: duas devidas, a 1ª chamada pega e reserva uma, a 2ª a outra, a 3ª nada (a
--      prova com duas sessões só depois do deploy, seção 7.3); retorno_tem_vencido antes, durante e depois;
--   2. resposta humana antes do envio: o eco do celular cancela (respondida_pelo_dono, com respondida_em no caso);
--      o mesmo num lote (horas reais 14:00 e 14:05 gravadas no mesmo minuto); o eco do FUTURO não cancela;
--   3. rajada (recebida 30 s antes) e lote global (12 linhas no último minuto) adiam;
--   4. sombra: preparada, modo sombra, o T01 exato, o contexto do validador (datas, horas, trechos) e o
--      espaçamento global intocado;
--   5. ligado com o grupo {recibo_cliente, adiamento, fim_do_dia}: 09:42 → enviando, com o espaçamento entre +30 e
--      +90 s; 16:00 (outro dia, URGENTE) → sombra urgente_desligado; 23:00 (manhã T07, 10h com X2 = 19h) → sombra
--      caso_sem_aviso; risco → sombra passagem_sem_acorde (com a linha L01); o fim do dia de um caso cujo recibo
--      foi sombra → sombra caso_em_sombra (com o topo_dia);
--   6. janela: 22:30 → a manhã seguinte entre 08:00 e 08:30, e às 08:0x o T07; no domingo, 09:00–09:30 e o T08;
--      6b: o recibo composto na qui às 21:59 ("amanhã até as 10h") que voltou a agendada depois das 22:00 e o canal
--      levou à manhã de sex diz "hoje até as 10h" (o prazo guardado é visto do dia em que sai);
--   7. tetos: 2º recibo à chave em 12 h de outro caso; saudação + recibo do mesmo caso saem; coleta depois deles;
--      saudação 2× em 30 dias;
--   8. texto que falta: empresa sem display_name → sem_nome (T03), nunca erro; dado forçado ausente → recusada/texto;
--   9. erro num item (dados.prazo.prometido_ate = 'x') → recusada/erro com app_error_logs, e a volta seguinte devolve
--      a outra saída;
--  10. retorno_registrar_decisao: as transições válidas (preparada → sombra; preparada/enviando → recusada pelo
--      validador, provedor, canal e equipe; o motivo desconhecido vira 'erro'; enviando → enviada, incerta e
--      reagendar) e as inválidas (sombra a partir de agendada, incerta a partir de preparada); o provedor soma em
--      erros_seguidos, o canal e a equipe não; 3 incertas → so_reativo 'erros', e uma enviada o desliga; 2 incertas
--      + 1 recusada/provedor também ligam; a incerta aplica os efeitos no caso; o efeito ilegível não desfaz a
--      decisão (vai ao log, action 'decisao');
--  11. Apresentação pelo modo pretendido ligado: 1 sombra → T02; 1 enviada → T01; só cobrança automática → T02; 11d: _cliente_ja_apresentada;
--  12. desligado: nada vence e retorno_pegar devolve nulo.
-- Cadastros e mensagens SINTÉTICOS de 55479000098xx, com datas de janeiro de 2027 (Brasília, sem horário de verão):
-- seg 11/01 a sex 15/01 dias úteis, sáb 16/01, dom 17/01, seg 18/01.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_pegar.sql
-- Termina em ROLLBACK: nada fica gravado. Todo o arranjo (retorno_config, cadastros, mensagens, casos e saídas) é
-- desfeito dentro do arquivo (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Uma mensagem sintética (recebida, por padrão), com a hora real e a de gravação (igual, salvo p_gravada); o id.
-- raw_payload padrão '{"data": {}}' = a vinda do webhook (na enviada, o eco do celular: saída humana).
create or replace function pg_temp.retorno_f1_pegar_msg(p_fone text, p_corpo text, p_em timestamptz,
                                                       p_direcao text default 'inbound', p_tipo text default 'text',
                                                       p_raw jsonb default '{"data": {}}'::jsonb,
                                                       p_gravada timestamptz default null)
returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload,
                                        hora_real, occurred_at)
  values (p_direcao, p_fone, p_tipo, p_corpo, case when p_direcao = 'inbound' then 'received' else 'sent' end, p_raw,
          p_em, coalesce(p_gravada, p_em))
  returning id
$f$;

-- Um cliente sintético, pelo WhatsApp do cadastro; o id.
create or replace function pg_temp.retorno_f1_pegar_cliente(p_nome text, p_whatsapp text, p_tipo text default 'individual')
returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values (p_tipo, p_nome, p_whatsapp) returning id
$f$;

-- retorno_abrir com ok = true (senão levanta '<caso>: …'); devolve o id do caso.
create or replace function pg_temp.retorno_f1_pegar_abre(p_caso text, p_msg uuid, p_agora timestamptz)
returns uuid
language plpgsql as $f$
declare
  v_r jsonb := public.retorno_abrir(p_msg, false, p_agora);
begin
  if v_r -> 'ok' is distinct from 'true'::jsonb or v_r ->> 'abertura_id' is null then
    raise exception '%: retorno_abrir não abriu o caso: %', p_caso, v_r;
  end if;
  return (v_r ->> 'abertura_id')::uuid;
end $f$;

-- A saída de um caso pela chave ('recibo', 'saudacao', …).
create or replace function pg_temp.retorno_f1_pegar_saida(p_caso uuid, p_sufixo text)
returns public.retorno_saidas
language sql as $f$
  select s.* from public.retorno_saidas s where s.dedupe_key = 'retorno:' || p_caso || ':' || p_sufixo
$f$;

create or replace function pg_temp.retorno_f1_pegar_le(p_id uuid)
returns public.retorno_saidas
language sql as $f$
  select s.* from public.retorno_saidas s where s.id = p_id
$f$;

-- Uma saída sintética (origem e classe pela tabela da seção 6.3); devolve o id.
create or replace function pg_temp.retorno_f1_pegar_sintetica(p_caso uuid, p_fone text, p_tipo text, p_variante text,
                                                             p_estado text, p_enviar timestamptz,
                                                             p_decidida timestamptz default null,
                                                             p_dados jsonb default '{}'::jsonb,
                                                             p_processando timestamptz default null,
                                                             p_tentativa smallint default 1)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, modo, estado,
                                     motivo, enviar_em, processando_ate, decidida_em, enviada_em, texto, dados, tentativa,
                                     dedupe_key)
  values (p_caso, p_tipo, p_variante,
          case when p_tipo in ('adiamento', 'fim_do_dia') then 'retorno_adiamento'
               when p_tipo = 'coleta_numero_novo' then 'retorno_coleta'
               when p_tipo in ('acorde', 'cadastro_provisorio') then null
               else 'retorno_recibo' end,
          case when p_tipo in ('adiamento', 'fim_do_dia') then 'resposta_atrasada'
               when p_tipo in ('acorde', 'cadastro_provisorio') then null
               else 'resposta_imediata' end,
          public._agenda_chave_telefone(p_fone), p_fone,
          case when p_estado in ('enviando', 'enviada', 'incerta') then 'ligado' else 'sombra' end,
          p_estado, case when p_estado in ('recusada', 'cancelada') then 'validador' end,
          p_enviar, p_processando, p_decidida, case when p_estado = 'enviada' then p_decidida end,
          case when p_estado <> 'agendada' then 'Teste F1 pegar: o texto que a saída teria.' end,
          coalesce(p_dados, '{}'::jsonb), coalesce(p_tentativa, 1::smallint), 'teste-f1-pegar:' || gen_random_uuid()::text)
  returning id
$f$;

-- Fim de um grupo: cancela o que sobrou dos números de teste e fecha os casos vivos deles (o retorno_pegar pega a
-- saída mais antiga do banco inteiro; o grupo seguinte não pode herdar nada).
create or replace function pg_temp.retorno_f1_pegar_limpa()
returns void
language sql as $f$
  update public.retorno_saidas
     set estado = 'cancelada', motivo = 'caso_fechado', processando_ate = null, atualizada_em = now()
   where chave like '000098%' and estado in ('agendada', 'preparada', 'enviando');
  update public.retorno_aberturas
     set estado = 'fechada', fechada_em = coalesce(fechada_em, now()), fechada_motivo = coalesce(fechada_motivo, 'expirou'),
         atualizada_em = now()
   where chave like '000098%' and estado in ('aberta', 'vencida');
$f$;

-- Confere um item de retorno_pegar: o contrato C-PEGAR (as 11 chaves), o contexto C-VAL (as 9) e, se dada, a saída.
create or replace function pg_temp.retorno_f1_pegar_item(p_caso text, p_r jsonb, p_saida uuid default null)
returns integer
language plpgsql as $f$
begin
  if jsonb_typeof(p_r) is distinct from 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_r) k)
        is distinct from array['classe', 'dedupe_key', 'modo', 'origem', 'phone', 'saida_id', 'tentativa', 'texto', 'tipo',
                               'validador', 'variante'] then
    raise exception '%: fora do contrato C-PEGAR: %', p_caso, p_r;
  end if;
  if jsonb_typeof(p_r -> 'validador') is distinct from 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_r -> 'validador') k)
        is distinct from array['audiencia', 'datas_permitidas', 'horas_permitidas', 'marcas', 'nome_permitido',
                               'nomes_de_outros', 'os_permitidas', 'textos_do_cliente', 'trechos_do_modelo'] then
    raise exception '%: contexto do validador fora do contrato C-VAL: %', p_caso, p_r -> 'validador';
  end if;
  if p_r -> 'validador' ->> 'audiencia' is distinct from 'cliente' or p_r -> 'validador' -> 'os_permitidas' <> '[]'::jsonb
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_r -> 'validador' -> 'marcas') k)
        is distinct from array['cliente_ouviu', 'conferida', 'tem_proposta', 'tem_topo']
     or p_r ->> 'modo' not in ('sombra', 'ligado') or coalesce(p_r ->> 'texto', '') = ''
     or coalesce(p_r ->> 'dedupe_key', '') not like 'retorno:%' or coalesce(p_r ->> 'phone', '') !~ '^[0-9]{10,15}$' then
    raise exception '%: item torto: %', p_caso, p_r;
  end if;
  if p_saida is not null and (p_r ->> 'saida_id')::uuid is distinct from p_saida then
    raise exception '%: devolveu a saída %, esperada %', p_caso, p_r ->> 'saida_id', p_saida;
  end if;
  return 1;
end $f$;

do $pegar$
declare
  c_seg constant timestamptz := '2027-01-11 00:00:00-03';   -- seg 11/01/2027
  c_ter constant timestamptz := '2027-01-12 00:00:00-03';
  c_qua constant timestamptz := '2027-01-13 00:00:00-03';
  c_qui constant timestamptz := '2027-01-14 00:00:00-03';
  c_sex constant timestamptz := '2027-01-15 00:00:00-03';
  c_sab constant timestamptz := '2027-01-16 00:00:00-03';
  c_l01 constant text := 'Se houver fogo, fumaça ou água entrando, ligue 193 (Bombeiros).';
  v_f record;
  v_cfg_antes jsonb;
  v_chegou boolean := false;
  v_n integer := 0;
  v_c uuid;
  v_m uuid; v_m2 uuid;
  v_caso uuid; v_caso2 uuid;
  v_r jsonb; v_r2 jsonb; v_r3 jsonb;
  v_s public.retorno_saidas;
  v_s2 public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_id uuid; v_id2 uuid; v_id3 uuid; v_id4 uuid;
  v_em timestamptz;
  v_prox timestamptz;
  v_pz jsonb;
  v_cfg public.retorno_config;
  v_logs integer;
  v_i integer;
begin
  -- ── 0. As funções e as premissas ────────────────────────────────────────────────────────────────────
  for v_f in
    select x.assinatura, x.vol, x.publica, p.oid, p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from (values ('public.retorno_tem_vencido(timestamptz)', 's', true),
                   ('public.retorno_pegar(timestamptz)', 'v', true),
                   ('public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz)', 'v', true),
                   ('public._retorno_checar_antes(uuid, timestamptz)', 'v', false),
                   ('public._retorno_resposta_humana(uuid, timestamptz)', 's', false),
                   ('public._retorno_aplicar_efeitos(uuid, timestamptz)', 'v', false),
                   ('public._retorno_contexto_do_validador(uuid, text, jsonb, timestamptz)', 's', false),
                   ('public._retorno_log(text, text, text, jsonb)', 'v', false)) x(assinatura, vol, publica)
      left join pg_proc p on p.oid = to_regprocedure(x.assinatura)
  loop
    if v_f.oid is null then
      raise exception '0: % não existe', v_f.assinatura;
    end if;
    if v_f.provolatile <> v_f.vol or not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) then
      raise exception '0: % não é % + SECURITY DEFINER com search_path = public', v_f.assinatura, v_f.vol;
    end if;
    if has_function_privilege('anon', v_f.oid, 'execute') or has_function_privilege('authenticated', v_f.oid, 'execute') then
      raise exception '0: % aberta a anon/authenticated', v_f.assinatura;
    end if;
    if v_f.publica and not has_function_privilege('service_role', v_f.oid, 'execute') then
      raise exception '0: % não é do service_role', v_f.assinatura;
    end if;
  end loop;
  select to_jsonb(c) into v_cfg_antes from public.retorno_config c where c.id;
  if not found then
    raise exception '0b: retorno_config sem a linha de configuração';
  end if;
  -- O calendário que o arquivo supõe (agenda de produção, só lida).
  if not (public.agenda_dia_util('2027-01-11') and public.agenda_dia_util('2027-01-12') and public.agenda_dia_util('2027-01-13')
          and public.agenda_dia_util('2027-01-14') and public.agenda_dia_util('2027-01-15') and public.agenda_dia_util('2027-01-18'))
     or public.agenda_dia_util('2027-01-16') or public.agenda_dia_util('2027-01-17')
     or extract(isodow from date '2027-01-16') <> 6 or extract(isodow from date '2027-01-17') <> 7
     or public.agenda_feriado('2027-01-17') is not null or public.agenda_feriado('2027-01-13') is not null
     or public.agenda_somar_du('2027-01-13', 0) <> '2027-01-13' or public.agenda_somar_du('2027-01-17', 0) <> '2027-01-18' then
    raise exception '0c: o calendário de janeiro de 2027 mudou na agenda (dia útil, feriado ou indisponibilidade do dono)';
  end if;
  -- Nenhuma mensagem nos dias do arquivo (a carência olha a saída humana a QUALQUER número; o lote global, todas).
  if exists (select 1 from public.whatsapp_messages w
              where w.occurred_at >= c_seg - interval '1 day' and w.occurred_at < c_sab + interval '3 days')
     or exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000098%') then
    raise exception '0d: há mensagens gravadas em 10–18/01/2027 ou dos números de teste 55479000098xx';
  end if;
  if exists (select 1 from public.retorno_saidas s where s.estado = 'agendada' and s.chave not like '000098%')
     or exists (select 1 from public.retorno_aberturas a where a.chave like '000098%') then
    raise exception '0e: há saída agendada fora dos números de teste (o retorno_pegar a pegaria) ou caso dos números de teste';
  end if;
  if exists (select 1 from public.clients c
              where public._agenda_chave_telefone(c.phone) like '000098%' or public._agenda_chave_telefone(c.whatsapp) like '000098%')
     or exists (select 1 from public.suppliers s where public._agenda_chave_telefone(s.phone) like '000098%')
     or exists (select 1 from public.whatsapp_blocked_numbers b where b.phone_normalized like '55479000098%') then
    raise exception '0f: há cadastro, fornecedor ou bloqueio real com os números de teste 55479000098xx';
  end if;

  begin
    -- A configuração de nascença do que este arquivo usa.
    update public.retorno_config
       set modo = 'sombra', tipos_ligados = '{}', carencia_min = 2, carencia_dono_ativo_min = 10, dono_ativo_janela_min = 15,
           lote_linhas_por_min = 10, lote_janela_min = 3, saudacao_espera_min = 10, audio_espera_min = 3,
           insistencia_apos = interval '60 minutes', recibo_intervalo = interval '12 hours', coleta_max = 2,
           saudacao_intervalo = interval '30 days', apresentacao_intervalo = interval '30 days',
           volta_min = interval '10 minutes', volta_max = interval '24 hours', volta_por_volta_max = 10,
           espaco_min_s = 30, espaco_max_s = 90, proximo_envio_em = null, respostas_dia_max = 40,
           so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null, erros_seguidos = 0,
           segura_recibos = false, segura_tudo_ate = null, fora_ate = null, meio_dia_ligado = false, promessa_faixa = '{}',
           cliente_resposta_direta_inicio = '07:00', cliente_resposta_direta_fim = '22:00',
           manha_recibo = '08:00', manha_recibo_folga = '09:00', manha_espalhar = interval '30 minutes',
           atrasada_inicio = '08:00', atrasada_fim = '20:00', atrasada_sabado_fim = '13:00',
           ponto_manha = '07:30', ponto_meio_dia = '12:30', ponto_fechamento = '17:30',
           promessa_manha = '10:00', promessa_meio_dia = '14:00', promessa_fechamento = '19:00',
           corte_meio_dia = '11:00', corte_tarde = '15:30', conteudo_min_caracteres = 15
     where id;

    -- ── 1. SKIP LOCKED (na mesma sessão) ─────────────────────────────────────────────────────────────
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9801', '(47) 90000-9801');
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9802', '(47) 90000-9802');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009801', 'Preciso de orçamento para trocar a bateria da lancha', c_seg + interval '8 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('1', v_m, c_seg + interval '8 hours 5 seconds');
    v_m2 := pg_temp.retorno_f1_pegar_msg('5547900009802', 'Preciso de orçamento para instalar inversor no barco',
                                         c_seg + interval '8 hours 10 seconds');
    v_caso2 := pg_temp.retorno_f1_pegar_abre('1', v_m2, c_seg + interval '8 hours 15 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_s2 := pg_temp.retorno_f1_pegar_saida(v_caso2, 'recibo');
    if v_s.enviar_em is distinct from c_seg + interval '8 hours 2 minutes'
       or v_s2.enviar_em is distinct from c_seg + interval '8 hours 2 minutes 10 seconds' then
      raise exception '1: os recibos não nasceram com a carência de 2 min: % / %', v_s.enviar_em, v_s2.enviar_em;
    end if;
    if public.retorno_tem_vencido(c_seg + interval '8 hours 1 minute') then
      raise exception '1: retorno_tem_vencido verdadeiro antes de vencer';
    end if;
    if not public.retorno_tem_vencido(c_seg + interval '8 hours 3 minutes') then
      raise exception '1: retorno_tem_vencido falso com duas saídas vencidas';
    end if;
    v_r := public.retorno_pegar(c_seg + interval '8 hours 3 minutes');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('1', v_r, v_s.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_s.estado is distinct from 'preparada' or v_s.processando_ate is distinct from c_seg + interval '8 hours 5 minutes'
       or v_s.decidida_em is distinct from c_seg + interval '8 hours 3 minutes' or v_s.texto is distinct from v_r ->> 'texto'
       or v_r ->> 'tipo' is distinct from 'recibo_cliente' or v_r ->> 'origem' is distinct from 'retorno_recibo'
       or v_r ->> 'classe' is distinct from 'resposta_imediata' or v_r ->> 'phone' is distinct from '5547900009801'
       or v_r ->> 'dedupe_key' is distinct from 'retorno:' || v_caso || ':recibo' or (v_r ->> 'tentativa')::int <> 1 then
      raise exception '1: a 1ª chamada não reservou a saída como o contrato diz: % / %', to_jsonb(v_s), v_r;
    end if;
    v_r2 := public.retorno_pegar(c_seg + interval '8 hours 3 minutes');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('1', v_r2, v_s2.id);
    v_r3 := public.retorno_pegar(c_seg + interval '8 hours 3 minutes');
    if v_r3 is not null then
      raise exception '1: a 3ª chamada devolveu um item: %', v_r3;
    end if;
    if public.retorno_tem_vencido(c_seg + interval '8 hours 3 minutes') then
      raise exception '1: retorno_tem_vencido verdadeiro com as duas saídas reservadas';
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 2. Resposta humana antes do envio ────────────────────────────────────────────────────────────
    -- 2a. O eco do celular depois da abertura cancela, e o caso guarda respondida_em.
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9803', '(47) 90000-9803');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009803', 'Bom dia, preciso de um orçamento para a bomba do barco', c_seg + interval '9 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('2a', v_m, c_seg + interval '9 hours 5 seconds');
    perform pg_temp.retorno_f1_pegar_msg('5547900009803', 'Bom dia! Já te respondo', c_seg + interval '9 hours 1 minute', 'outbound');
    v_r := public.retorno_pegar(c_seg + interval '9 hours 2 minutes 30 seconds');
    if v_r is not null then
      raise exception '2a: com o eco do dono, ainda saiu um item: %', v_r;
    end if;
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_ab := (select a from public.retorno_aberturas a where a.id = v_caso);
    if v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'respondida_pelo_dono'
       or v_s.decidida_em is distinct from c_seg + interval '9 hours 2 minutes 30 seconds'
       or v_ab.respondida_em is distinct from c_seg + interval '9 hours 1 minute' then
      raise exception '2a: o eco do celular não cancelou o recibo (ou o caso não guardou a resposta): % / %', to_jsonb(v_s), to_jsonb(v_ab);
    end if;

    -- 2c. FUTURO: o mesmo eco gravado 1 min depois de agora não cancela (ninguém olha o futuro).
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9805', '(47) 90000-9805');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009805', 'Bom dia, preciso de um orçamento para a bomba do barco', c_seg + interval '10 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('2c', v_m, c_seg + interval '10 hours 5 seconds');
    perform pg_temp.retorno_f1_pegar_msg('5547900009805', 'Bom dia! Já te respondo', c_seg + interval '10 hours 3 minutes 30 seconds',
                                         'outbound');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_seg + interval '10 hours 2 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('2c', v_r, v_s.id);
    if (pg_temp.retorno_f1_pegar_le(v_s.id)).estado is distinct from 'preparada' then
      raise exception '2c: o eco do futuro mudou a saída';
    end if;

    -- 2b. Num lote: a pergunta (hora real 14:00) e a resposta (hora real 14:05) gravadas no mesmo minuto, 16:00.
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9804', '(47) 90000-9804');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009804', 'Boa tarde, preciso trocar o inversor da lancha', c_seg + interval '14 hours',
                                        'inbound', 'text', '{"data": {}}', c_seg + interval '16 hours 10 seconds');
    v_caso := pg_temp.retorno_f1_pegar_abre('2b', v_m, c_seg + interval '16 hours 15 seconds');
    perform pg_temp.retorno_f1_pegar_msg('5547900009804', 'Oi! Vejo isso amanhã cedo, ok?', c_seg + interval '14 hours 5 minutes',
                                         'outbound', 'text', '{"data": {}}', c_seg + interval '16 hours 20 seconds');
    v_r := public.retorno_pegar(c_seg + interval '16 hours 3 minutes');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    if v_r is not null or v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'respondida_pelo_dono' then
      raise exception '2b: a resposta do lote não cancelou o recibo: % / %', v_r, to_jsonb(v_s);
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 3. Rajada e lote global ──────────────────────────────────────────────────────────────────────
    -- 3a. Uma recebida da chave 40 s antes de agora (ainda não lida pelo webhook): adia para ela + carência.
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9806', '(47) 90000-9806');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009806', 'Preciso trocar a bateria do motorhome, consegue?', c_seg + interval '11 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('3a', v_m, c_seg + interval '11 hours 5 seconds');
    perform pg_temp.retorno_f1_pegar_msg('5547900009806', 'é um Ducato', c_seg + interval '11 hours 1 minute 50 seconds');
    v_r := public.retorno_pegar(c_seg + interval '11 hours 2 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    if v_r is not null or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em is distinct from c_seg + interval '11 hours 3 minutes 50 seconds'
       or v_s.dados -> 'adiada' ->> 'motivo' is distinct from 'rajada' then
      raise exception '3a: a rajada não adiou o recibo: % / %', v_r, to_jsonb(v_s);
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();
    -- 3b. 12 linhas gravadas no último minuto (em qualquer número): lote global, + 2 min.
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9807', '(47) 90000-9807');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009807', 'Preciso trocar a bateria do motorhome, consegue?', c_seg + interval '11 hours 30 minutes');
    v_caso := pg_temp.retorno_f1_pegar_abre('3b', v_m, c_seg + interval '11 hours 30 minutes 5 seconds');
    for v_i in 1 .. 12 loop
      perform pg_temp.retorno_f1_pegar_msg('5547900009899', 'Teste F1 pegar: linha do lote ' || v_i,
                                           c_seg + interval '11 hours 33 minutes' + make_interval(secs => v_i),
                                           'outbound', 'text', '{"via": "retorno"}'::jsonb);
    end loop;
    v_r := public.retorno_pegar(c_seg + interval '11 hours 33 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    if v_r is not null or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em is distinct from c_seg + interval '11 hours 35 minutes 30 seconds'
       or v_s.dados -> 'adiada' ->> 'motivo' is distinct from 'lote_global' then
      raise exception '3b: o lote global não adiou o recibo: % / %', v_r, to_jsonb(v_s);
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 4. Sombra: o T01 exato e o contexto do validador ─────────────────────────────────────────────
    -- A chave já teve uma saída do retorno em sombra 3 dias antes (K4 pelo modo pretendido sombra: conta) → T01.
    perform pg_temp.retorno_f1_pegar_cliente('Mariana Lopes Teste', '(47) 90000-9808');
    perform pg_temp.retorno_f1_pegar_sintetica(null, '5547900009808', 'recibo_cliente', 'padrao', 'sombra',
                                               c_ter - interval '3 days' + interval '10 hours',
                                               c_ter - interval '3 days' + interval '10 hours');
    update public.retorno_config set proximo_envio_em = '2027-01-01 00:00:00-03' where id;
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009808', 'Bom dia, preciso de um orçamento para trocar o inversor do motorhome',
                                        c_ter + interval '9 hours 12 minutes');
    v_caso := pg_temp.retorno_f1_pegar_abre('4', v_m, c_ter + interval '9 hours 12 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_ter + interval '9 hours 14 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('4', v_r, v_s.id);
    if v_r ->> 'modo' is distinct from 'sombra' or v_r ->> 'variante' is distinct from 'padrao'
       or v_r ->> 'texto' is distinct from 'Oi, Mariana! Já passei sua mensagem ao Gustavo, e ele retorna para você ainda hoje.' then
      raise exception '4: o recibo em sombra não é o T01 exato: %', v_r;
    end if;
    if v_r -> 'validador' -> 'datas_permitidas' is distinct from '["hoje"]'::jsonb
       or v_r -> 'validador' -> 'horas_permitidas' is distinct from '["19h"]'::jsonb
       or v_r -> 'validador' ->> 'nome_permitido' is distinct from 'Mariana'
       or v_r -> 'validador' -> 'nomes_de_outros' is distinct from '[]'::jsonb
       or v_r -> 'validador' -> 'trechos_do_modelo'
          is distinct from '["Oi, ", "! Já passei sua mensagem ao Gustavo, e ele retorna para você ", "."]'::jsonb
       or v_r -> 'validador' -> 'textos_do_cliente'
          is distinct from '["Bom dia, preciso de um orçamento para trocar o inversor do motorhome"]'::jsonb
       or v_r -> 'validador' -> 'marcas' is distinct from
          '{"tem_proposta": false, "tem_topo": false, "cliente_ouviu": false, "conferida": false}'::jsonb then
      raise exception '4: o contexto do validador está errado: %', v_r -> 'validador';
    end if;
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    select * into v_cfg from public.retorno_config where id;
    if v_s.estado is distinct from 'preparada' or v_s.modo is distinct from 'sombra'
       or v_s.dados ->> 'sombra_motivo' is distinct from 'modo' or v_s.dados -> 'prazo' ->> 'faixa' is distinct from 'manha_cedo'
       or v_s.processando_ate is distinct from c_ter + interval '9 hours 16 minutes 30 seconds'
       or v_cfg.proximo_envio_em is distinct from '2027-01-01 00:00:00-03'::timestamptz then
      raise exception '4: a reserva da sombra está errada (ou mexeu no espaçamento): % / %', to_jsonb(v_s), v_cfg.proximo_envio_em;
    end if;
    -- O registro da sombra (como a edge faria) aplica a promessa no caso.
    v_r2 := public.retorno_registrar_decisao(v_s.id, 'sombra', '{"validador": {"ok": true}}', c_ter + interval '9 hours 14 minutes 31 seconds');
    v_ab := (select a from public.retorno_aberturas a where a.id = v_caso);
    if v_r2 is distinct from '{"ok": true, "estado": "sombra"}'::jsonb or v_ab.recibo_em is distinct from c_ter + interval '9 hours 14 minutes 30 seconds'
       or v_ab.prometido_ate is distinct from c_ter + interval '19 hours' or v_ab.prometido_fonte is distinct from 'fechamento'
       or v_ab.faixa is distinct from 'manha_cedo' then
      raise exception '4: o registro da sombra não aplicou a promessa: % / %', v_r2, to_jsonb(v_ab);
    end if;
    update public.retorno_config set proximo_envio_em = null where id;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 5. Ligado, com o grupo do caso ───────────────────────────────────────────────────────────────
    update public.retorno_config set modo = 'ligado', tipos_ligados = '{recibo_cliente,adiamento,fim_do_dia}' where id;
    -- 5a. 09:42, promessa 19h sem X2: enviando, e o espaçamento global sorteado entre +30 e +90 s.
    perform pg_temp.retorno_f1_pegar_cliente('Carla Teste', '(47) 90000-9809');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009809', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_ter + interval '9 hours 40 minutes');
    v_caso := pg_temp.retorno_f1_pegar_abre('5a', v_m, c_ter + interval '9 hours 40 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_em := c_ter + interval '9 hours 42 minutes 30 seconds';
    v_r := public.retorno_pegar(v_em);
    v_n := v_n + pg_temp.retorno_f1_pegar_item('5a', v_r, v_s.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    select proximo_envio_em into v_prox from public.retorno_config where id;
    if v_r ->> 'modo' is distinct from 'ligado' or v_s.estado is distinct from 'enviando' or v_s.modo is distinct from 'ligado'
       or v_s.dados ? 'sombra_motivo' or v_prox is null
       or v_prox < v_em + interval '30 seconds' or v_prox > v_em + interval '90 seconds' then
      raise exception '5a: o recibo das 09:42 não saiu ligado com o espaçamento: % / % / %', v_r, to_jsonb(v_s), v_prox;
    end if;
    -- 5d. Risco: passagem sem o acorde real → sombra passagem_sem_acorde, com a linha L01.
    perform pg_temp.retorno_f1_pegar_cliente('Fabio Teste', '(47) 90000-9812');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009812', 'tá saindo fumaça do quadro do motorhome', c_ter + interval '10 hours 30 minutes');
    v_caso := pg_temp.retorno_f1_pegar_abre('5d', v_m, c_ter + interval '10 hours 30 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_ter + interval '10 hours 32 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('5d', v_r, v_s.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r ->> 'modo' is distinct from 'sombra' or v_s.dados ->> 'sombra_motivo' is distinct from 'passagem_sem_acorde'
       or right(v_r ->> 'texto', length(c_l01) + 1) is distinct from E'\n' || c_l01 then
      raise exception '5d: o caso com risco não ficou em sombra passagem_sem_acorde com a L01: % / %', v_r, to_jsonb(v_s);
    end if;
    -- 5b. 16:00 (promessa de outro dia, o recibo oferece URGENTE): sombra urgente_desligado (T05).
    perform pg_temp.retorno_f1_pegar_cliente('Daniel Teste', '(47) 90000-9810');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009810', 'Boa tarde, preciso de um orçamento para instalar o inversor no barco',
                                        c_ter + interval '15 hours 58 minutes');
    v_caso := pg_temp.retorno_f1_pegar_abre('5b', v_m, c_ter + interval '15 hours 58 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_ter + interval '16 hours 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('5b', v_r, v_s.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r ->> 'modo' is distinct from 'sombra' or v_s.dados ->> 'sombra_motivo' is distinct from 'urgente_desligado'
       or v_r ->> 'variante' is distinct from 'outro_dia_apresentacao'
       or v_r ->> 'texto' is distinct from 'Oi, Daniel! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você amanhã de manhã. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.' then
      raise exception '5b: o recibo das 16:00 não ficou em sombra urgente_desligado (T05): % / %', v_r, to_jsonb(v_s);
    end if;
    v_r2 := public.retorno_registrar_decisao(v_s.id, 'sombra', '{"validador": {"ok": true}}', c_ter + interval '16 hours 31 seconds');
    if v_r2 is distinct from '{"ok": true, "estado": "sombra"}'::jsonb then
      raise exception '5b: o registro da sombra falhou: %', v_r2;
    end if;
    -- 5e. O fim do dia de um caso cujo recibo foi sombra → sombra caso_em_sombra (T22, com o topo_dia).
    v_id := pg_temp.retorno_f1_pegar_sintetica(v_caso, '5547900009810', 'fim_do_dia', null, 'agendada', c_ter + interval '16 hours 30 minutes',
                                               null, '{"dia": "2027-01-12"}'::jsonb);
    v_r := public.retorno_pegar(c_ter + interval '16 hours 30 minutes 30 seconds');
    if jsonb_typeof(v_r) is distinct from 'object' or (v_r ->> 'saida_id')::uuid is distinct from v_id then
      raise exception '5e: o fim do dia não saiu do retorno_pegar: %', v_r;
    end if;
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    v_ab := (select a from public.retorno_aberturas a where a.id = v_caso);
    if v_r ->> 'modo' is distinct from 'sombra' or v_s.dados ->> 'sombra_motivo' is distinct from 'caso_em_sombra'
       or v_r ->> 'texto' is distinct from 'Daniel, o Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele amanhã cedo.'
       or v_ab.topo_dia is distinct from date '2027-01-13'
       or v_r -> 'validador' -> 'marcas' -> 'tem_topo' is distinct from 'true'::jsonb
       or not (v_r -> 'validador' -> 'datas_permitidas' @> '["amanhã", "hoje"]'::jsonb)
       or v_r ->> 'origem' is distinct from 'retorno_adiamento' or v_r ->> 'classe' is distinct from 'resposta_atrasada' then
      raise exception '5e: o fim do dia do caso em sombra está errado: % / % / %', v_r, to_jsonb(v_s), v_ab.topo_dia;
    end if;
    -- 5c. 23:00: fora da janela, o recibo espera a manhã com o prazo da faixa noite; às 08:0x sai o T07, em sombra
    --     caso_sem_aviso (promessa 10h com X2 = 19h: o adiamento ofereceria URGENTE). É também o caso 6 da janela.
    perform pg_temp.retorno_f1_pegar_cliente('Elisa Teste', '(47) 90000-9811');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009811', 'Boa noite, preciso de um orçamento para a bateria do motorhome',
                                        c_ter + interval '23 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('5c', v_m, c_ter + interval '23 hours 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_ter + interval '23 hours 2 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r is not null or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em < c_qua + interval '8 hours' or v_s.enviar_em >= c_qua + interval '8 hours 30 minutes'
       or v_s.dados -> 'prazo' ->> 'faixa' is distinct from 'noite'
       or (v_s.dados -> 'prazo' ->> 'prometido_ate')::timestamptz is distinct from c_qua + interval '10 hours' then
      raise exception '6: às 22:30+ o recibo não esperou a manhã seguinte (08:00–08:30) com o prazo da noite: % / %', v_r, to_jsonb(v_s);
    end if;
    v_r := public.retorno_pegar(v_s.enviar_em + interval '1 second');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('5c', v_r, v_s.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r ->> 'variante' is distinct from 'manha_apresentacao'
       or v_r ->> 'texto' is distinct from 'Bom dia, Elisa! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem de ontem à noite e já passei ao Gustavo. Ele retorna para você ainda esta manhã.'
       or v_r ->> 'modo' is distinct from 'sombra' or v_s.dados ->> 'sombra_motivo' is distinct from 'caso_sem_aviso'
       or not (v_r -> 'validador' -> 'datas_permitidas' @> '["ontem"]'::jsonb)
       or v_r -> 'validador' -> 'horas_permitidas' is distinct from '["10h"]'::jsonb then
      raise exception '5c/6: o recibo da manhã não é o T07 em sombra caso_sem_aviso: % / %', v_r, to_jsonb(v_s);
    end if;
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}', proximo_envio_em = null where id;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 6. Janela no domingo: sáb 22:30 → dom 09:00–09:30, e o T08 ("amanhã até as 10h") ─────────────
    perform pg_temp.retorno_f1_pegar_cliente('Gisele Teste', '(47) 90000-9813');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009813', 'Boa noite, preciso de um orçamento para a bateria do motorhome',
                                        c_sab + interval '22 hours 30 minutes');
    v_caso := pg_temp.retorno_f1_pegar_abre('6', v_m, c_sab + interval '22 hours 30 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_sab + interval '22 hours 32 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r is not null or v_s.enviar_em < c_sab + interval '1 day 9 hours'
       or v_s.enviar_em >= c_sab + interval '1 day 9 hours 30 minutes' then
      raise exception '6: no domingo o recibo não ficou entre 09:00 e 09:30: % / %', v_r, to_jsonb(v_s);
    end if;
    v_r := public.retorno_pegar(v_s.enviar_em + interval '1 second');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('6', v_r, v_s.id);
    if v_r ->> 'variante' is distinct from 'manha_outro_dia_apresentacao'
       or v_r ->> 'texto' is distinct from 'Bom dia, Gisele! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem de ontem à noite e já passei ao Gustavo. Ele retorna para você amanhã de manhã.' then
      raise exception '6: o recibo de domingo não é o T08: %', v_r;
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- 6b. O prazo guardado é visto do dia em que o recibo SAI. Composto na qui às 21:59 (faixa tarde: "amanhã até as
    --     10h"), o recibo volta a agendada depois das 22:00 sem ter saído (aqui a reserva da sombra que venceu e o vigia
    --     devolveu; ligado, o 503 ou o espaçamento), o canal o leva à manhã de sex com o prazo guardado, e às 08:0x ele
    --     diz "hoje até as 10h" (T02), nunca "amanhã" (T05, que o validador não pegaria).
    perform pg_temp.retorno_f1_pegar_cliente('Lucia Teste', '(47) 90000-9826');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009826', 'Boa noite, preciso de um orçamento para a bateria da lancha',
                                        c_qui + interval '21 hours 57 minutes');
    v_caso := pg_temp.retorno_f1_pegar_abre('6b', v_m, c_qui + interval '21 hours 57 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_qui + interval '21 hours 59 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('6b', v_r, v_s.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r ->> 'variante' is distinct from 'outro_dia_apresentacao' or v_s.dados -> 'prazo' ->> 'faixa' is distinct from 'tarde'
       or v_s.dados -> 'prazo' ->> 'quando' is distinct from 'amanhã'
       or (v_s.dados -> 'prazo' ->> 'prometido_ate')::timestamptz is distinct from c_sex + interval '10 hours' then
      raise exception '6b: às 21:59 o recibo não prometeu "amanhã até as 10h" (faixa tarde): % / %', v_r, to_jsonb(v_s);
    end if;
    -- a volta a agendada sem decisão (o que o passo 9 do vigia faz com a reserva vencida), já depois das 22:00
    update public.retorno_saidas
       set estado = 'agendada', processando_ate = null, decidida_em = null, enviar_em = c_qui + interval '22 hours 7 minutes'
     where id = v_s.id;
    v_r := public.retorno_pegar(c_qui + interval '22 hours 7 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r is not null or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em < c_sex + interval '8 hours' or v_s.enviar_em >= c_sex + interval '8 hours 30 minutes'
       or (v_s.dados -> 'prazo' ->> 'prometido_ate')::timestamptz is distinct from c_sex + interval '10 hours' then
      raise exception '6b: às 22:07 o canal não levou o recibo à manhã de sex com o prazo guardado: % / %', v_r, to_jsonb(v_s);
    end if;
    v_r := public.retorno_pegar(v_s.enviar_em + interval '1 second');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('6b', v_r, v_s.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    if v_r ->> 'variante' is distinct from 'padrao_apresentacao'
       or v_r ->> 'texto' is distinct from 'Oi, Lucia! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você ainda esta manhã.'
       or v_r -> 'validador' -> 'datas_permitidas' is distinct from '["hoje"]'::jsonb
       or v_r -> 'validador' -> 'horas_permitidas' is distinct from '["10h"]'::jsonb
       or v_s.dados -> 'prazo' ->> 'quando' is distinct from 'hoje' or v_s.dados -> 'prazo' ->> 'ref' is distinct from '2027-01-15'
       or v_s.dados -> 'prazo' -> 'outro_dia' is distinct from 'false'::jsonb
       or (v_s.dados -> 'prazo' ->> 'prometido_ate')::timestamptz is distinct from c_sex + interval '10 hours' then
      raise exception '6b: às 08:0x da sex o recibo guardado na qui não disse "hoje até as 10h": % / %', v_r, to_jsonb(v_s);
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 7. Tetos por número ──────────────────────────────────────────────────────────────────────────
    -- 7a. 2º recibo à mesma chave em 12 h, de OUTRO caso → teto_numero.
    perform pg_temp.retorno_f1_pegar_cliente('Helena Teste', '(47) 90000-9814');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009814', 'Preciso de um orçamento para a bomba do barco', c_qua + interval '9 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('7a', v_m, c_qua + interval '9 hours 5 seconds');
    v_r := public.retorno_pegar(c_qua + interval '9 hours 2 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('7a', v_r);
    perform public.retorno_registrar_decisao((v_r ->> 'saida_id')::uuid, 'sombra', '{"validador": {"ok": true}}',
                                             c_qua + interval '9 hours 2 minutes 31 seconds');
    update public.retorno_aberturas set estado = 'fechada', fechada_em = now(), fechada_motivo = 'expirou' where id = v_caso;
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009814', 'Esqueci: também preciso trocar a bateria da lancha', c_qua + interval '10 hours');
    v_caso2 := pg_temp.retorno_f1_pegar_abre('7a', v_m, c_qua + interval '10 hours 5 seconds');
    v_r := public.retorno_pegar(c_qua + interval '10 hours 2 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso2, 'recibo');
    if v_caso2 = v_caso or v_r is not null or v_s.estado is distinct from 'recusada' or v_s.motivo is distinct from 'teto_numero' then
      raise exception '7a: o 2º recibo à chave em 12 h não parou no teto_numero: % / %', v_r, to_jsonb(v_s);
    end if;
    -- 7b. Saudação e recibo do MESMO caso (número novo): os dois saem (o par do 1º contato).
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009815', 'Boa tarde', c_qua + interval '13 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('7b', v_m, c_qua + interval '13 hours 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'saudacao');
    v_r := public.retorno_pegar(c_qua + interval '13 hours 10 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('7b', v_r, v_s.id);
    if v_r ->> 'texto' is distinct from 'Boa tarde! Aqui é a Claudia, assistente virtual da HBR. Em que posso ajudar? Se preferir, pode mandar um áudio.'
       or v_r -> 'validador' -> 'datas_permitidas' is distinct from '[]'::jsonb then
      raise exception '7b: a saudação não é o T19: %', v_r;
    end if;
    perform public.retorno_registrar_decisao(v_s.id, 'sombra', '{"validador": {"ok": true}}', c_qua + interval '13 hours 10 minutes 31 seconds');
    v_ab := (select a from public.retorno_aberturas a where a.id = v_caso);
    if v_ab.coleta_n <> 1 or v_ab.prometido_ate is not null or v_ab.recibo_em is not null then
      raise exception '7b: a saudação não contou no 1º contato, ou prometeu hora: %', to_jsonb(v_ab);
    end if;
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009815', 'preciso instalar inversor no barco', c_qua + interval '13 hours 15 minutes');
    perform pg_temp.retorno_f1_pegar_abre('7b', v_m, c_qua + interval '13 hours 15 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_qua + interval '13 hours 17 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('7b', v_r, v_s.id);
    if v_r ->> 'variante' is distinct from 'sem_pergunta'
       or v_r ->> 'texto' is distinct from 'Boa tarde! Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, que cuida dos orçamentos, e ele retorna para você ainda hoje.' then
      raise exception '7b: o recibo depois da saudação não saiu (ou não é o T17): %', v_r;
    end if;
    perform public.retorno_registrar_decisao(v_s.id, 'sombra', '{"validador": {"ok": true}}', c_qua + interval '13 hours 17 minutes 31 seconds');
    -- 7c. A coleta depois da saudação + recibo do mesmo caso → teto_coleta (no máximo 2 no 1º contato).
    v_id := pg_temp.retorno_f1_pegar_sintetica(v_caso, '5547900009815', 'coleta_numero_novo', 'nome', 'agendada',
                                               c_qua + interval '13 hours 20 minutes');
    v_r := public.retorno_pegar(c_qua + interval '13 hours 20 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is not null or v_s.estado is distinct from 'recusada' or v_s.motivo is distinct from 'teto_coleta' then
      raise exception '7c: a 3ª mensagem automática do 1º contato não parou no teto_coleta: % / %', v_r, to_jsonb(v_s);
    end if;
    -- 7d. Saudação 2× em 30 dias (24 h depois, outro caso) → teto_saudacao.
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009816', 'Boa tarde', c_qua + interval '14 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('7d', v_m, c_qua + interval '14 hours 5 seconds');
    v_r := public.retorno_pegar(c_qua + interval '14 hours 10 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('7d', v_r);
    perform public.retorno_registrar_decisao((v_r ->> 'saida_id')::uuid, 'sombra', '{"validador": {"ok": true}}',
                                             c_qua + interval '14 hours 10 minutes 31 seconds');
    update public.retorno_aberturas set estado = 'fechada', fechada_em = now(), fechada_motivo = 'expirou' where id = v_caso;
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009816', 'Boa tarde', c_qui + interval '14 hours 30 minutes');
    v_caso2 := pg_temp.retorno_f1_pegar_abre('7d', v_m, c_qui + interval '14 hours 30 minutes 5 seconds');
    v_r := public.retorno_pegar(c_qui + interval '14 hours 40 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso2, 'saudacao');
    if v_r is not null or v_s.estado is distinct from 'recusada' or v_s.motivo is distinct from 'teto_saudacao' then
      raise exception '7d: a 2ª saudação em 30 dias não parou no teto_saudacao: % / %', v_r, to_jsonb(v_s);
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 8. Texto que falta ───────────────────────────────────────────────────────────────────────────
    -- 8a. Empresa sem display_name: variante sem_nome (T03), nunca erro.
    perform pg_temp.retorno_f1_pegar_cliente('TESTE F1 PEGAR EMPRESA LTDA', '(47) 90000-9817', 'company');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009817', 'Preciso trocar a bateria da lancha', c_qui + interval '9 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('8a', v_m, c_qui + interval '9 hours 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_r := public.retorno_pegar(c_qui + interval '9 hours 2 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('8a', v_r, v_s.id);
    if v_r ->> 'variante' is distinct from 'sem_nome' or v_r -> 'validador' -> 'nome_permitido' is distinct from 'null'::jsonb
       or v_r ->> 'texto' is distinct from 'Olá! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você ainda hoje.' then
      raise exception '8a: a empresa sem display_name não recebeu o T03: %', v_r;
    end if;
    perform public.retorno_registrar_decisao(v_s.id, 'sombra', '{"validador": {"ok": true}}', c_qui + interval '9 hours 2 minutes 31 seconds');
    -- 8b. O adiamento sem o dado da hora (forçado): recusada/texto e o erro registrado; nada levanta.
    v_id := pg_temp.retorno_f1_pegar_sintetica(v_caso, '5547900009817', 'adiamento', null, 'agendada', c_qui + interval '9 hours 30 minutes',
                                               null, jsonb_build_object('x', c_qui + interval '19 hours'));
    v_r := public.retorno_pegar(c_qui + interval '9 hours 30 minutes 30 seconds');
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    select count(*) into v_logs from public.app_error_logs l
     where l.context = 'retorno' and l.action = 'pegar' and l.details ->> 'sqlstate' = '22023' and l.last_seen_at = now();
    if v_r is not null or v_s.estado is distinct from 'recusada' or v_s.motivo is distinct from 'texto'
       or coalesce(v_s.dados ->> 'texto_erro', '') not like '%falta hora%' or v_logs < 1 then
      raise exception '8b: o dado ausente não virou recusada/texto com log: % / % / logs %', v_r, to_jsonb(v_s), v_logs;
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 9. Erro num item não trava a fila ────────────────────────────────────────────────────────────
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9818', '(47) 90000-9818');
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9819', '(47) 90000-9819');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009818', 'Preciso de orçamento para trocar a bateria da lancha', c_qui + interval '11 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('9', v_m, c_qui + interval '11 hours 5 seconds');
    v_m2 := pg_temp.retorno_f1_pegar_msg('5547900009819', 'Preciso de orçamento para instalar inversor no barco',
                                         c_qui + interval '11 hours 20 seconds');
    v_caso2 := pg_temp.retorno_f1_pegar_abre('9', v_m2, c_qui + interval '11 hours 25 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_s2 := pg_temp.retorno_f1_pegar_saida(v_caso2, 'recibo');
    update public.retorno_saidas
       set dados = dados || '{"prazo": {"prometido_ate": "x", "recibo_em": "x"}}'::jsonb
     where id = v_s.id;
    v_r := public.retorno_pegar(c_qui + interval '11 hours 3 minutes');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('9', v_r, v_s2.id);
    v_s := pg_temp.retorno_f1_pegar_le(v_s.id);
    select count(*) into v_logs from public.app_error_logs l
     where l.context = 'retorno' and l.action = 'pegar' and l.details ->> 'sqlstate' = '22007'
       and l.details ->> 'saida' = v_s.id::text and l.last_seen_at = now();
    if v_s.estado is distinct from 'recusada' or v_s.motivo is distinct from 'erro'
       or v_s.dados -> 'erro' ->> 'sqlstate' is distinct from '22007' or v_logs < 1 then
      raise exception '9: o item que derruba a composição não virou recusada/erro com log: % / logs %', to_jsonb(v_s), v_logs;
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 10. retorno_registrar_decisao ────────────────────────────────────────────────────────────────
    v_em := c_qui + interval '13 hours 30 minutes';
    -- 10a. Inválida: sombra a partir de agendada → ok = false, nada muda; saída que não existe; estado desconhecido.
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'agendada', v_em + interval '1 day');
    v_r := public.retorno_registrar_decisao(v_id, 'sombra', '{}', v_em);
    if v_r is distinct from '{"ok": false, "erro": "estado"}'::jsonb or (pg_temp.retorno_f1_pegar_le(v_id)).estado is distinct from 'agendada' then
      raise exception '10a: sombra a partir de agendada não deu {"ok": false, "erro": "estado"}: %', v_r;
    end if;
    if public.retorno_registrar_decisao(gen_random_uuid(), 'sombra', '{}', v_em) -> 'ok' is distinct from 'false'::jsonb
       or public.retorno_registrar_decisao(v_id, 'xyz', '{}', v_em) -> 'ok' is distinct from 'false'::jsonb
       or public.retorno_registrar_decisao(v_id, 'enviada', '{}', v_em) -> 'ok' is distinct from 'false'::jsonb then
      raise exception '10a: saída inexistente, estado desconhecido ou enviada a partir de agendada passaram';
    end if;
    -- 10a. Válidas: preparada → sombra; preparada → recusada/validador (com as regras); enviando → enviada.
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'preparada', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'sombra', '{"validador": {"ok": true}}', v_em);
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is distinct from '{"ok": true, "estado": "sombra"}'::jsonb or v_s.estado is distinct from 'sombra'
       or v_s.validador is distinct from '{"ok": true}'::jsonb or v_s.processando_ate is not null then
      raise exception '10a: preparada → sombra: % / %', v_r, to_jsonb(v_s);
    end if;
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'preparada', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'recusada', '{"motivo": "validador", "regras": ["dinheiro"]}', v_em);
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is distinct from '{"ok": true, "estado": "recusada"}'::jsonb or v_s.motivo is distinct from 'validador'
       or v_s.validador is distinct from '{"ok": false, "regras": ["dinheiro"]}'::jsonb then
      raise exception '10a: preparada → recusada/validador: % / %', v_r, to_jsonb(v_s);
    end if;
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'enviada', '{"validador": {"ok": true}, "provider_message_id": "wamid.TESTE", "http_status": 200}', v_em);
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is distinct from '{"ok": true, "estado": "enviada"}'::jsonb or v_s.enviada_em is distinct from v_em
       or v_s.provider_message_id is distinct from 'wamid.TESTE' or (v_s.dados -> 'envio' -> 'http_status')::int <> 200 then
      raise exception '10a: enviando → enviada: % / %', v_r, to_jsonb(v_s);
    end if;
    -- 10a. enviando → recusada pelo provedor (o 4xx do whatsapp-send): ok, motivo provedor, e soma um erro seguido.
    select c.erros_seguidos into v_i from public.retorno_config c where c.id;
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'recusada', '{"motivo": "provedor", "http_status": 422, "codigo": "numero_invalido"}', v_em);
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is distinct from '{"ok": true, "estado": "recusada"}'::jsonb or v_s.estado is distinct from 'recusada'
       or v_s.motivo is distinct from 'provedor' or v_s.processando_ate is not null
       or (v_s.dados -> 'envio' -> 'http_status')::int <> 422
       or (select c.erros_seguidos from public.retorno_config c where c.id) <> v_i + 1 then
      raise exception '10a: enviando → recusada/provedor não registrou ou não somou o erro seguido: % / % / antes %', v_r, to_jsonb(v_s), v_i;
    end if;
    -- 10a. enviando → recusada pelo canal (o portão do whatsapp-send) e preparada → recusada pela equipe: não somam erro.
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'recusada', '{"motivo": "canal", "http_status": 422, "codigo": "opt_out"}', v_em);
    v_id2 := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'preparada', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r2 := public.retorno_registrar_decisao(v_id2, 'recusada', '{"motivo": "equipe"}', v_em);
    if v_r is distinct from '{"ok": true, "estado": "recusada"}'::jsonb or (pg_temp.retorno_f1_pegar_le(v_id)).motivo is distinct from 'canal'
       or v_r2 is distinct from '{"ok": true, "estado": "recusada"}'::jsonb or (pg_temp.retorno_f1_pegar_le(v_id2)).motivo is distinct from 'equipe'
       or (select c.erros_seguidos from public.retorno_config c where c.id) <> v_i + 1 then
      raise exception '10a: recusada por canal/equipe errada (ou somou erro seguido): % / %', v_r, v_r2;
    end if;
    -- 10a. Motivo fora da lista: vira 'erro' (a saída nunca fica presa), com o motivo recebido em dados; não soma erro.
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'preparada', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'recusada', '{"motivo": "xyz"}', v_em);
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is distinct from '{"ok": true, "estado": "recusada"}'::jsonb or v_s.motivo is distinct from 'erro'
       or v_s.dados ->> 'motivo_recebido' is distinct from 'xyz'
       or (select c.erros_seguidos from public.retorno_config c where c.id) <> v_i + 1 then
      raise exception '10a: o motivo desconhecido não virou erro com motivo_recebido: % / %', v_r, to_jsonb(v_s);
    end if;
    -- 10a. Inválida: incerta a partir de preparada → {"ok": false, "erro": "estado"}, nada muda.
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'preparada', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'incerta', '{"codigo": "rede"}', v_em);
    if v_r is distinct from '{"ok": false, "erro": "estado"}'::jsonb or (pg_temp.retorno_f1_pegar_le(v_id)).estado is distinct from 'preparada'
       or (select c.erros_seguidos from public.retorno_config c where c.id) <> v_i + 1 then
      raise exception '10a: incerta a partir de preparada não deu {"ok": false, "erro": "estado"}: %', v_r;
    end if;
    -- 10a. enviando → reagendar (o 503): agendada em 2 min, tentativa 2, a MESMA chave; com 3 tentativas, recusada/reserva.
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_s2 := pg_temp.retorno_f1_pegar_le(v_id);
    v_r := public.retorno_registrar_decisao(v_id, 'reagendar', '{"http_status": 503, "codigo": "reserva_indisponivel"}', v_em);
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is distinct from '{"ok": true, "estado": "agendada"}'::jsonb or v_s.estado is distinct from 'agendada'
       or v_s.tentativa <> 2 or v_s.enviar_em is distinct from v_em + interval '2 minutes' or v_s.dedupe_key is distinct from v_s2.dedupe_key
       or v_s.decidida_em is not null or v_s.processando_ate is not null then
      raise exception '10a: enviando → reagendar: % / %', v_r, to_jsonb(v_s);
    end if;
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}',
                                               v_em + interval '2 minutes', 3::smallint);
    v_r := public.retorno_registrar_decisao(v_id, 'reagendar', '{"http_status": 503}', v_em);
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    if v_r is distinct from '{"ok": true, "estado": "recusada"}'::jsonb or v_s.motivo is distinct from 'reserva' then
      raise exception '10a: a 4ª tentativa não virou recusada/reserva: % / %', v_r, to_jsonb(v_s);
    end if;
    -- 10c. A incerta aplica os efeitos no caso (a promessa do recibo).
    perform pg_temp.retorno_f1_pegar_cliente('Teste F1 pegar 9823', '(47) 90000-9823');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009823', 'Preciso de orçamento para trocar a bateria da lancha', c_qui + interval '13 hours');
    v_caso := pg_temp.retorno_f1_pegar_abre('10c', v_m, c_qui + interval '13 hours 5 seconds');
    v_s := pg_temp.retorno_f1_pegar_saida(v_caso, 'recibo');
    v_pz := public._retorno_prazo(c_qui + interval '13 hours 2 minutes', '00009823', false, false);
    update public.retorno_saidas
       set estado = 'enviando', modo = 'ligado', texto = 'Teste F1 pegar: o texto que a saída teria.', variante = 'padrao',
           decidida_em = c_qui + interval '13 hours 2 minutes', processando_ate = c_qui + interval '13 hours 4 minutes',
           dados = dados || jsonb_build_object('prazo', v_pz)
     where id = v_s.id;
    v_r := public.retorno_registrar_decisao(v_s.id, 'incerta', '{"http_status": 500, "codigo": "erro_do_servidor"}',
                                            c_qui + interval '13 hours 2 minutes 20 seconds');
    v_ab := (select a from public.retorno_aberturas a where a.id = v_caso);
    if v_r is distinct from '{"ok": true, "estado": "incerta"}'::jsonb
       or v_ab.prometido_ate is distinct from c_qui + interval '19 hours' or v_ab.recibo_em is distinct from c_qui + interval '13 hours 2 minutes'
       or v_ab.faixa is distinct from 'meio' or v_ab.prometido_fonte is distinct from 'fechamento' then
      raise exception '10c: a incerta não aplicou os efeitos no caso: % / %', v_r, to_jsonb(v_ab);
    end if;
    -- 10d. O efeito que não se aplica (dados.prazo ilegível) não desfaz a decisão: a saída fica enviada, o caso fica como
    --      estava e o erro vai ao app_error_logs (action 'decisao'). Sem isso a saída voltava presa a cada ~7 min.
    v_id := pg_temp.retorno_f1_pegar_sintetica(v_caso, '5547900009823', 'recibo_cliente', 'padrao', 'enviando',
                                               c_qui + interval '13 hours 3 minutes', c_qui + interval '13 hours 3 minutes',
                                               '{"prazo": {"prometido_ate": "x"}}', c_qui + interval '13 hours 5 minutes');
    v_r := public.retorno_registrar_decisao(v_id, 'enviada', '{"provider_message_id": "wamid.TESTE3", "http_status": 200}',
                                            c_qui + interval '13 hours 3 minutes 20 seconds');
    v_s := pg_temp.retorno_f1_pegar_le(v_id);
    v_ab := (select a from public.retorno_aberturas a where a.id = v_caso);
    select count(*) into v_logs from public.app_error_logs l
     where l.context = 'retorno' and l.action = 'decisao' and l.details ->> 'sqlstate' = '22007'
       and l.details ->> 'saida' = v_id::text and l.last_seen_at = now();
    if v_r is distinct from '{"ok": true, "estado": "enviada"}'::jsonb or v_s.estado is distinct from 'enviada'
       or v_s.enviada_em is distinct from c_qui + interval '13 hours 3 minutes 20 seconds'
       or v_ab.prometido_ate is distinct from c_qui + interval '19 hours' or v_logs < 1 then
      raise exception '10d: o efeito ilegível desfez a decisão (ou não foi ao log): % / % / logs %', v_r, to_jsonb(v_s), v_logs;
    end if;
    -- 10b. Três incertas seguidas ligam o so_reativo ('erros'); uma enviada o desliga e zera a conta.
    update public.retorno_config set erros_seguidos = 0, so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null where id;
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_id2 := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_id3 := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_id4 := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    perform public.retorno_registrar_decisao(v_id, 'incerta', '{"codigo": "rede"}', v_em + interval '10 seconds');
    perform public.retorno_registrar_decisao(v_id2, 'incerta', '{"codigo": "rede"}', v_em + interval '20 seconds');
    select * into v_cfg from public.retorno_config where id;
    if v_cfg.so_reativo or v_cfg.erros_seguidos <> 2 then
      raise exception '10b: com 2 incertas o disjuntor já ligou (ou não contou): %', to_jsonb(v_cfg);
    end if;
    perform public.retorno_registrar_decisao(v_id3, 'incerta', '{"codigo": "rede"}', v_em + interval '30 seconds');
    select * into v_cfg from public.retorno_config where id;
    select count(*) into v_logs from public.app_error_logs l
     where l.context = 'retorno' and l.action = 'disjuntor' and l.last_seen_at = now();
    if not v_cfg.so_reativo or v_cfg.so_reativo_motivo is distinct from 'erros' or v_cfg.erros_seguidos <> 3
       or v_cfg.so_reativo_desde is distinct from v_em + interval '30 seconds' or v_logs < 1 then
      raise exception '10b: 3 incertas seguidas não ligaram o so_reativo por erros (com log): % / logs %', to_jsonb(v_cfg), v_logs;
    end if;
    perform public.retorno_registrar_decisao(v_id4, 'enviada', '{"provider_message_id": "wamid.TESTE2"}', v_em + interval '40 seconds');
    select * into v_cfg from public.retorno_config where id;
    if v_cfg.so_reativo or v_cfg.so_reativo_motivo is not null or v_cfg.so_reativo_desde is not null or v_cfg.erros_seguidos <> 0 then
      raise exception '10b: a enviada não desligou o so_reativo por erros: %', to_jsonb(v_cfg);
    end if;
    -- 10b. A recusa do provedor também é erro do envio: 2 incertas + 1 recusada/provedor ligam o so_reativo ('erros').
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_id2 := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    v_id3 := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009824', 'recibo_cliente', 'padrao', 'enviando', v_em, v_em, '{}', v_em + interval '2 minutes');
    perform public.retorno_registrar_decisao(v_id, 'incerta', '{"codigo": "rede"}', v_em + interval '50 seconds');
    perform public.retorno_registrar_decisao(v_id2, 'incerta', '{"codigo": "rede"}', v_em + interval '60 seconds');
    v_r := public.retorno_registrar_decisao(v_id3, 'recusada', '{"motivo": "provedor", "http_status": 400}', v_em + interval '70 seconds');
    select * into v_cfg from public.retorno_config where id;
    if v_r is distinct from '{"ok": true, "estado": "recusada"}'::jsonb or not v_cfg.so_reativo
       or v_cfg.so_reativo_motivo is distinct from 'erros' or v_cfg.erros_seguidos <> 3
       or v_cfg.so_reativo_desde is distinct from v_em + interval '70 seconds' then
      raise exception '10b: 2 incertas + 1 recusada/provedor não ligaram o so_reativo por erros: % / %', v_r, to_jsonb(v_cfg);
    end if;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 11. K4 pelo modo PRETENDIDO ligado ───────────────────────────────────────────────────────────
    update public.retorno_config
       set modo = 'ligado', tipos_ligados = '{recibo_cliente,adiamento,fim_do_dia}', proximo_envio_em = null,
           erros_seguidos = 0, so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null
     where id;
    -- 11a. Só uma SOMBRA do retorno em 30 dias (o cliente nunca ouviu): apresentação (T02).
    perform pg_temp.retorno_f1_pegar_cliente('Ingrid Teste', '(47) 90000-9820');
    perform pg_temp.retorno_f1_pegar_sintetica(null, '5547900009820', 'recibo_cliente', 'padrao', 'sombra',
                                               c_sex - interval '5 days', c_sex - interval '5 days');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009820', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha', c_sex + interval '9 hours');
    perform pg_temp.retorno_f1_pegar_abre('11a', v_m, c_sex + interval '9 hours 5 seconds');
    v_r := public.retorno_pegar(c_sex + interval '9 hours 2 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('11a', v_r);
    if v_r ->> 'variante' is distinct from 'padrao_apresentacao' or v_r ->> 'modo' is distinct from 'ligado'
       or v_r ->> 'texto' is distinct from 'Oi, Ingrid! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você ainda hoje.' then
      raise exception '11a: com só uma sombra nos 30 dias, o recibo ligado não se apresentou (T02): %', v_r;
    end if;
    update public.retorno_config set proximo_envio_em = null where id;
    -- 11b. Uma ENVIADA do retorno em 30 dias: o cliente já ouviu (T01).
    perform pg_temp.retorno_f1_pegar_cliente('Joana Teste', '(47) 90000-9821');
    perform pg_temp.retorno_f1_pegar_sintetica(null, '5547900009821', 'recibo_cliente', 'padrao', 'enviada',
                                               c_sex - interval '5 days', c_sex - interval '5 days');
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009821', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_sex + interval '9 hours 10 minutes');
    perform pg_temp.retorno_f1_pegar_abre('11b', v_m, c_sex + interval '9 hours 10 minutes 5 seconds');
    v_r := public.retorno_pegar(c_sex + interval '9 hours 12 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('11b', v_r);
    if v_r ->> 'variante' is distinct from 'padrao'
       or v_r ->> 'texto' is distinct from 'Oi, Joana! Já passei sua mensagem ao Gustavo, e ele retorna para você ainda hoje.' then
      raise exception '11b: com uma enviada nos 30 dias, o recibo não é o T01: %', v_r;
    end if;
    update public.retorno_config set proximo_envio_em = null where id;
    -- 11c. Só uma cobrança automática na conversa (saida_humana = false, sem retorno_saidas): apresentação (T02).
    perform pg_temp.retorno_f1_pegar_cliente('Karina Teste', '(47) 90000-9822');
    perform pg_temp.retorno_f1_pegar_msg('5547900009822', 'Teste F1 pegar: lembrete automático de pagamento.', c_sex - interval '2 days',
                                         'outbound', 'text', '{"via": "whatsapp-send", "origem": "sistema"}'::jsonb);
    if (select w.saida_humana from public.whatsapp_messages w where w.phone_normalized = '5547900009822' and w.direction = 'outbound')
       is distinct from false then
      raise exception '11c: a cobrança automática sintética não ficou saida_humana = false';
    end if;
    v_m := pg_temp.retorno_f1_pegar_msg('5547900009822', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_sex + interval '9 hours 20 minutes');
    perform pg_temp.retorno_f1_pegar_abre('11c', v_m, c_sex + interval '9 hours 20 minutes 5 seconds');
    v_r := public.retorno_pegar(c_sex + interval '9 hours 22 minutes 30 seconds');
    v_n := v_n + pg_temp.retorno_f1_pegar_item('11c', v_r);
    if v_r ->> 'variante' is distinct from 'padrao_apresentacao'
       or v_r ->> 'texto' is distinct from 'Oi, Karina! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você ainda hoje.' then
      raise exception '11c: a cobrança automática contou como apresentação já feita: %', v_r;
    end if;
    -- 11d. _cliente_ja_apresentada (VOZ-1, VOZ-6): a enviada conta; a incerta e o que passou da janela, não; a agenda conta.
    declare
      v_hoje_t date := (c_sex at time zone 'America/Sao_Paulo')::date;
      v_os_t uuid;
      v_cli_t uuid;
    begin
      if not public._cliente_ja_apresentada(null, public._agenda_chave_telefone('5547900009821'), v_hoje_t) then
        raise exception '11d: a enviada do retorno não contou como apresentação';
      end if;
      perform pg_temp.retorno_f1_pegar_sintetica(null, '5547900009826', 'recibo_cliente', 'padrao', 'incerta',
                                                 c_sex - interval '5 days', c_sex - interval '5 days');
      if public._cliente_ja_apresentada(null, public._agenda_chave_telefone('5547900009826'), v_hoje_t) then
        raise exception '11d: a incerta contou como apresentação (repetir é melhor que omitir)';
      end if;
      perform pg_temp.retorno_f1_pegar_sintetica(null, '5547900009827', 'recibo_cliente', 'padrao', 'enviada',
                                                 c_sex - interval '31 days', c_sex - interval '31 days');
      if public._cliente_ja_apresentada(null, public._agenda_chave_telefone('5547900009827'), v_hoje_t) then
        raise exception '11d: a enviada de fora da janela contou como apresentação';
      end if;
      if public._cliente_ja_apresentada(null, null, v_hoje_t)
         or public._cliente_ja_apresentada(null, public._agenda_chave_telefone('5547900009828'), v_hoje_t) then
        raise exception '11d: sem chave, ou sem nada enviado, a função disse que já se apresentou';
      end if;
      select o.id, o.client_id into v_os_t, v_cli_t
        from public.service_orders o
       where o.client_id is not null
         and not exists (select 1 from public.agenda_cliente_mensagens m where m.client_id = o.client_id and m.enviada_em is not null)
       limit 1;
      if v_os_t is not null then
        if public._cliente_ja_apresentada(v_cli_t, null, v_hoje_t) then
          raise exception '11d: cliente sem mensagem nenhuma já estava apresentado';
        end if;
        insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                     aprovacao, estado, dedupe_key, enviada_em)
        values (v_cli_t, v_os_t, 'confirmar', 'rodada', 'ligado', 'Teste 11d', c_sex - interval '2 days', c_sex,
                'livre', 'enviada', 'teste-11d-apresentacao', c_sex - interval '2 days');
        if not public._cliente_ja_apresentada(v_cli_t, null, v_hoje_t) then
          raise exception '11d: a mensagem enviada pela agenda não contou como apresentação';
        end if;
      end if;
      if has_function_privilege('anon', 'public._cliente_ja_apresentada(uuid, text, date)', 'execute')
         or has_function_privilege('authenticated', 'public._cliente_ja_apresentada(uuid, text, date)', 'execute') then
        raise exception '11d: _cliente_ja_apresentada aberta a anon ou authenticated';
      end if;
    end;
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}', proximo_envio_em = null where id;
    perform pg_temp.retorno_f1_pegar_limpa();

    -- ── 12. Desligado: nada vence e nada é pego ──────────────────────────────────────────────────────
    v_id := pg_temp.retorno_f1_pegar_sintetica(null, '5547900009825', 'recibo_cliente', 'padrao', 'agendada', c_sex + interval '12 hours');
    if not public.retorno_tem_vencido(c_sex + interval '12 hours 1 minute') then
      raise exception '12: em sombra, a saída vencida não conta para o cron';
    end if;
    update public.retorno_config set modo = 'desligado' where id;
    if public.retorno_tem_vencido(c_sex + interval '12 hours 1 minute') or public.retorno_pegar(c_sex + interval '12 hours 1 minute') is not null
       or (pg_temp.retorno_f1_pegar_le(v_id)).estado is distinct from 'agendada' then
      raise exception '12: com o retorno desligado algo venceu ou foi pego';
    end if;

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0g: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.retorno_aberturas a where a.chave like '000098%')
     or exists (select 1 from public.retorno_saidas s where s.chave like '000098%')
     or exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000098%')
     or (select to_jsonb(c) from public.retorno_config c where c.id) is distinct from v_cfg_antes then
    raise exception '0h: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_pegar', true, jsonb_build_object('itens_conferidos', v_n));
end
$pegar$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
