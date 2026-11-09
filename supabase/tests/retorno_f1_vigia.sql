-- Retorno F1 (P6): o vigia de cada minuto (retorno_vigia) e o acorde simulado (_retorno_acorde_simulado),
-- 20261116100800_retorno_f1_vigia.sql, com as saídas decididas pelo retorno_pegar/retorno_registrar_decisao (P6.1).
--   0. as funções e as premissas: a linha de configuração, a linha da conexão, o dono, o calendário de março de
--      2027 na agenda de produção (só lida), nenhuma mensagem nos dias do arquivo e nada vivo fora dos números de
--      teste (o vigia processa o banco inteiro: o arquivo é da bancada de antes do deploy de 16/11);
--   1. C1 em sombra: recibo 09:14 prometido 19h (meio-dia desligado) → às 18:00 o acorde do relógio, às 18:30 o fim
--      do dia (sem X2 no mesmo dia) e nenhum adiamento; com o meio-dia ligado e 14h → às 13:30 o adiamento com
--      dados.hora = '19h' e às 19:00 o fim do dia; 1c (desvio, §3): o adiamento recusado pelo validador e o ainda
--      agendado em X (que o retorno_pegar cancela por caso_vencido) dão o fim do dia em X, e nada antes de X;
--   2. escalonamento: 3 casos com o mesmo X → adiamentos a X−30, X−29 e X−28; nunca depois de X−1;
--   3. resposta humana: a de conteúdo fecha o caso ('conteudo') e cancela o adiamento agendado; o "ok, já vejo"
--      só preenche respondida_em, o caso continua aberto às 16:00 e o fim do dia das 18:30 nasce e não é cancelado;
--   4. caso vencido: mensagem nova depois do fim do dia → passagem, acorde, nenhum recibo novo;
--   5. acorde simulado: o teto do dia em avisos_do_dono (o aviso de depois de agora não conta); às 20:30, fora;
--   6. incerta: com o eco na conversa → enviada; sem eco → aos 31 min continua incerta, sem saída nova nem
--      agendada de volta;
--   7. presos, um a um: preparada presa → agendada (atrás das vencidas); enviando presa → incerta, com a promessa no
--      caso; a enviando com o prazo ilegível fica incerta e o efeito vai ao log, sem desfazer o resto do passo; a
--      mesma preparada presa de novo → recusada/erro (nunca volta à fila a cada ~7 min);
--   8. rebaixamento: opt-out 1 h depois de uma enviada de recibo_cliente; 3 recusas do validador de adiamento em
--      1 h (sai o grupo dos recibos, sem violar o check); 3 do recibo_numero_novo (saem a coleta e o cadastro);
--   9. arquivar: provisório de 31 dias sem OS às 04:00 → inativo; com OS → fica; de 29 dias → fica; fora das
--      04:00 nada;
--  10. disjuntor: conexão 'close' há 15 min liga (motivo 'conexao'); 'open' há 12 min desliga; com o motivo
--      'erros', a conexão aberta não desliga;
--  11. áudio: o '[audio]' do número novo não tem saída; a reavaliação que falha (ok = false, forçada por um check
--      num sub-bloco desfeito) não conta e sai do filtro, com log; trocado o body pela transcrição, o vigia seguinte
--      tria de novo (recibo de número novo); o áudio de risco de um cliente vira passagem;
--  12. expirou: caso sem recebida há 4 dias úteis → fechada/expirou (e a agendada dele cai); com topo_dia hoje, fica;
--      12b: com expira_dias_uteis nulo (o padrão, cartão F1-10), o mesmo caso fica aberto e a agendada fica;
--  13. retenção: coleta de 181 dias sem cadastro → nula; com cadastro → fica; de 179 dias → fica; o mesmo no lead
--      (o convertido fica);
--  14. alongamento: ligado com 19 casos nada; com o 20º (15 cumpridos, 75%), em sombra nada (o portão do modo, com o
--      caso que alongaria); ligado → meio = {"dias": 1, "hora": "10:00"} e uma linha em retorno_alongamentos; a mesma
--      evidência não alonga de novo;
--  15. futuro: a resposta humana com occurred_at depois de agora não preenche respondida_em.
-- Cadastros e mensagens SINTÉTICOS de 55479000099xx, com datas de março de 2027 (Brasília, sem horário de verão):
-- seg 01/03 a sex 05/03 e seg 08/03 a sex 12/03 dias úteis; sáb 06/03, dom 07/03, sáb 13/03.
-- A conexão do WhatsApp (whatsapp_conexao_vigia, linha real) fica 'open' desde 01/01/2027 durante o arquivo, para o
-- disjuntor não ligar sozinho; o caso 10 a muda num sub-bloco próprio, desfeito na hora.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_vigia.sql
-- Termina em ROLLBACK: nada fica gravado. Todo o arranjo é desfeito dentro do arquivo (sub-bloco 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.retorno_f1_vigia_msg(p_fone text, p_corpo text, p_em timestamptz,
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

create or replace function pg_temp.retorno_f1_vigia_cliente(p_nome text, p_whatsapp text)
returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_whatsapp) returning id
$f$;

create or replace function pg_temp.retorno_f1_vigia_abre(p_caso text, p_msg uuid, p_agora timestamptz)
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

create or replace function pg_temp.retorno_f1_vigia_saida(p_caso uuid, p_sufixo text)
returns public.retorno_saidas
language sql as $f$
  select s.* from public.retorno_saidas s where s.dedupe_key = 'retorno:' || p_caso || ':' || p_sufixo
$f$;

create or replace function pg_temp.retorno_f1_vigia_le(p_id uuid)
returns public.retorno_saidas
language sql as $f$
  select s.* from public.retorno_saidas s where s.id = p_id
$f$;

create or replace function pg_temp.retorno_f1_vigia_caso(p_id uuid)
returns public.retorno_aberturas
language sql as $f$
  select a.* from public.retorno_aberturas a where a.id = p_id
$f$;

-- O vigia, que tem de rodar sem erro em nenhum passo; devolve as contagens.
create or replace function pg_temp.retorno_f1_vigia_roda(p_caso text, p_agora timestamptz)
returns jsonb
language plpgsql as $f$
declare
  v_r jsonb := public.retorno_vigia(p_agora);
begin
  if v_r -> 'ok' is distinct from 'true'::jsonb or v_r -> 'rodou' is distinct from 'true'::jsonb then
    raise exception '%: retorno_vigia com erro num passo: %', p_caso, v_r;
  end if;
  return v_r;
end $f$;

-- O retorno_pegar devolve esta saída, e a edge registraria "eu teria mandado" (sombra). Devolve o item.
create or replace function pg_temp.retorno_f1_vigia_sombra(p_caso text, p_saida uuid, p_agora timestamptz)
returns jsonb
language plpgsql as $f$
declare
  v_r jsonb := public.retorno_pegar(p_agora);
  v_d jsonb;
begin
  if jsonb_typeof(v_r) is distinct from 'object' or (v_r ->> 'saida_id')::uuid is distinct from p_saida then
    raise exception '%: o retorno_pegar não devolveu a saída esperada (%): %', p_caso, p_saida, v_r;
  end if;
  v_d := public.retorno_registrar_decisao(p_saida, 'sombra', '{"validador": {"ok": true}}', p_agora);
  if v_d is distinct from '{"ok": true, "estado": "sombra"}'::jsonb then
    raise exception '%: o registro da sombra falhou: %', p_caso, v_d;
  end if;
  return v_r;
end $f$;

-- Uma saída sintética do retorno; devolve o id.
create or replace function pg_temp.retorno_f1_vigia_sintetica(p_caso uuid, p_fone text, p_tipo text, p_estado text,
                                                             p_decidida timestamptz, p_dados jsonb default '{}'::jsonb,
                                                             p_processando timestamptz default null)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, modo, estado,
                                     motivo, enviar_em, processando_ate, decidida_em, enviada_em, texto, dados, dedupe_key)
  values (p_caso, p_tipo, case when p_tipo in ('adiamento', 'fim_do_dia') then 'sem_nome' else 'padrao' end,
          case when p_tipo in ('adiamento', 'fim_do_dia') then 'retorno_adiamento' else 'retorno_recibo' end,
          case when p_tipo in ('adiamento', 'fim_do_dia') then 'resposta_atrasada' else 'resposta_imediata' end,
          public._agenda_chave_telefone(p_fone), p_fone,
          case when p_estado in ('enviando', 'enviada', 'incerta') then 'ligado' else 'sombra' end,
          p_estado, case when p_estado in ('recusada', 'cancelada') then 'validador' end,
          coalesce(p_decidida, now()), p_processando, case when p_estado <> 'agendada' then p_decidida end,
          case when p_estado = 'enviada' then p_decidida end,
          'Teste F1 vigia: o texto que a saída teria.', coalesce(p_dados, '{}'::jsonb),
          'teste-f1-vigia:' || gen_random_uuid()::text)
  returning id
$f$;

-- Um caso sintético (sem passar pelo retorno_abrir), com a 1ª mensagem; devolve o id.
create or replace function pg_temp.retorno_f1_vigia_caso_sintetico(p_fone text, p_em timestamptz, p_papel text,
                                                                  p_estado text default 'aberta',
                                                                  p_coleta jsonb default null)
returns uuid
language plpgsql as $f$
declare
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload,
                                        hora_real, occurred_at)
  values ('inbound', p_fone, 'text', 'Teste F1 vigia: preciso de um orçamento', 'received', '{"data": {}}',
          '2027-03-01 08:00:00-03', '2027-03-01 08:00:00-03')
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, motivo, tipo_recibo, coleta, estado,
                                        fechada_em, fechada_motivo, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, p_papel, jsonb_build_object('papel', p_papel), v_msg, v_msg,
          p_em, p_em, p_em, p_em, 'recibo', null,
          case when p_papel = 'numero_novo' then 'recibo_numero_novo' else 'recibo_cliente' end, p_coleta, p_estado,
          case when p_estado = 'fechada' then now() end, case when p_estado = 'fechada' then 'expirou' end, 'sombra')
  returning id into v_id;
  return v_id;
end $f$;

-- Um caso fechado da faixa meio com o recibo ENVIADO (para o alongamento); cumprido ou não no prazo.
create or replace function pg_temp.retorno_f1_vigia_caso_meio(p_i integer, p_cumprido boolean)
returns uuid
language plpgsql as $f$
declare
  v_dia timestamptz := '2027-03-01 00:00:00-03'::timestamptz + make_interval(days => p_i % 5);
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload,
                                        hora_real, occurred_at)
  values ('inbound', '5547900009950', 'text', 'Teste F1 vigia: caso da faixa meio ' || p_i, 'received', '{"data": {}}',
          v_dia + interval '11 hours 58 minutes', v_dia + interval '11 hours 58 minutes')
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, faixa, prometido_ate,
                                        prometido_fonte, recibo_em, cumprida_em, cumprida_por, estado, fechada_em,
                                        fechada_motivo, modo)
  values ('00009950', '5547900009950', 'cliente', '{"papel": "cliente"}', v_msg, v_msg,
          v_dia + interval '11 hours 58 minutes', v_dia + interval '11 hours 58 minutes',
          v_dia + interval '11 hours 58 minutes', v_dia + interval '11 hours 58 minutes', 'recibo', 'recibo_cliente', 'meio',
          v_dia + interval '19 hours', 'fechamento', v_dia + interval '12 hours',
          case when p_cumprido then v_dia + interval '18 hours' end, case when p_cumprido then 'celular' end,
          'fechada', now(), case when p_cumprido then 'conteudo' else 'expirou' end, 'ligado')
  returning id into v_id;
  insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, modo, estado,
                                     enviar_em, decidida_em, enviada_em, texto, dedupe_key)
  values (v_id, 'recibo_cliente', 'padrao', 'retorno_recibo', 'resposta_imediata', '00009950', '5547900009950', 'ligado',
          'enviada', v_dia + interval '12 hours', v_dia + interval '12 hours', v_dia + interval '12 hours',
          'Teste F1 vigia: o recibo enviado.', 'retorno:' || v_id || ':recibo');
  return v_id;
end $f$;

-- Fim de um grupo: cancela o que sobrou dos números de teste e fecha os casos vivos deles.
create or replace function pg_temp.retorno_f1_vigia_limpa()
returns void
language sql as $f$
  update public.retorno_saidas
     set estado = 'cancelada', motivo = 'caso_fechado', processando_ate = null, atualizada_em = now()
   where chave like '000099%' and estado in ('agendada', 'preparada', 'enviando', 'incerta');
  update public.retorno_aberturas
     set estado = 'fechada', fechada_em = coalesce(fechada_em, now()), fechada_motivo = coalesce(fechada_motivo, 'expirou'),
         atualizada_em = now()
   where chave like '000099%' and estado in ('aberta', 'vencida');
$f$;

do $vigia$
declare
  c_d1 constant timestamptz := '2027-03-01 00:00:00-03';    -- seg 01/03/2027
  c_d2 constant timestamptz := '2027-03-02 00:00:00-03';
  c_d3 constant timestamptz := '2027-03-03 00:00:00-03';
  c_d4 constant timestamptz := '2027-03-04 00:00:00-03';
  c_d5 constant timestamptz := '2027-03-05 00:00:00-03';
  c_d8 constant timestamptz := '2027-03-08 00:00:00-03';
  c_d9 constant timestamptz := '2027-03-09 00:00:00-03';
  c_d10 constant timestamptz := '2027-03-10 00:00:00-03';
  c_d11 constant timestamptz := '2027-03-11 00:00:00-03';
  c_d12 constant timestamptz := '2027-03-12 00:00:00-03';
  c_d13 constant timestamptz := '2027-03-13 00:00:00-03';
  v_f record;
  v_cfg_antes jsonb;
  v_conexao_antes jsonb;
  v_dono text;
  v_limite integer;
  v_chegou boolean := false;
  v_n integer := 0;
  v_m uuid; v_m2 uuid;
  v_caso uuid; v_caso2 uuid; v_caso3 uuid;
  v_casos uuid[];
  v_v jsonb;
  v_r jsonb; v_r2 jsonb;
  v_s public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_cfg public.retorno_config;
  v_id uuid; v_id2 uuid;
  v_em timestamptz[];
  v_pz jsonb;
  v_i integer;
  v_logs integer;
  v_c uuid; v_c2 uuid; v_c3 uuid; v_ve uuid;
  v_l1 uuid; v_l2 uuid; v_l3 uuid;
  -- o caso 10 (disjuntor), guardado antes de o sub-bloco desfazer a conexão
  v_d1 public.retorno_config; v_d2 public.retorno_config; v_d3 public.retorno_config;
  v_dv1 jsonb; v_dv2 jsonb; v_dv3 jsonb;
  -- o caso 11a' (a reavaliação que falha), guardado antes de o sub-bloco desfazer o check
  v_b1 boolean;
begin
  -- ── 0. As funções e as premissas ────────────────────────────────────────────────────────────────────
  for v_f in
    select x.assinatura, x.vol, x.publica, x.definer, p.oid, p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from (values ('public.retorno_vigia(timestamptz)', 'v', true, true),
                   ('public.retorno_cadastro_provisorio(uuid, boolean)', 'v', true, true),
                   ('public._retorno_acorde_simulado(timestamptz)', 's', false, true),
                   ('public._retorno_nome_comparavel(text)', 'i', false, false)) x(assinatura, vol, publica, definer)
      left join pg_proc p on p.oid = to_regprocedure(x.assinatura)
  loop
    if v_f.oid is null then
      raise exception '0: % não existe', v_f.assinatura;
    end if;
    if v_f.provolatile <> v_f.vol or v_f.prosecdef is distinct from v_f.definer or not ('search_path=public' = any (v_f.config)) then
      raise exception '0: % fora do molde (volatilidade %, SECURITY DEFINER %, search_path = public)', v_f.assinatura, v_f.vol, v_f.definer;
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
  select to_jsonb(c) into v_conexao_antes from public.whatsapp_conexao_vigia c where c.id = 1;
  if not found then
    raise exception '0b: whatsapp_conexao_vigia sem a linha da conexão';
  end if;
  select d.phone into v_dono from public._comprovante_dono() d limit 1;
  if v_dono is null then
    raise exception '0b: _comprovante_dono() sem dono (o acorde simulado do caso 5 precisa dele)';
  end if;
  begin
    v_limite := coalesce((select (s.value::jsonb ->> 'acordes_por_dia')::int from public.app_settings s
                           where s.key = 'voz_unica_regras' limit 1), 2);
  exception when others then
    v_limite := 2;
  end;
  if v_limite < 1 or v_limite > 20 then
    raise exception '0b: voz_unica_regras.acordes_por_dia fora do que o caso 5 testa: %', v_limite;
  end if;
  if not (public.agenda_dia_util('2027-03-01') and public.agenda_dia_util('2027-03-02') and public.agenda_dia_util('2027-03-03')
          and public.agenda_dia_util('2027-03-04') and public.agenda_dia_util('2027-03-05') and public.agenda_dia_util('2027-03-08')
          and public.agenda_dia_util('2027-03-09') and public.agenda_dia_util('2027-03-10') and public.agenda_dia_util('2027-03-11')
          and public.agenda_dia_util('2027-03-12'))
     or public.agenda_dia_util('2027-03-06') or public.agenda_dia_util('2027-03-07')
     or public.agenda_somar_du('2027-03-02', 3) <> '2027-03-05' or public.agenda_somar_du('2027-03-02', 0) <> '2027-03-02' then
    raise exception '0c: o calendário de março de 2027 mudou na agenda (dia útil, feriado ou indisponibilidade do dono)';
  end if;
  if exists (select 1 from public.whatsapp_messages w
              where w.occurred_at >= c_d1 - interval '1 day' and w.occurred_at < c_d13 + interval '2 days')
     or exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000099%') then
    raise exception '0d: há mensagens gravadas em 28/02–14/03/2027 ou dos números de teste 55479000099xx';
  end if;
  if exists (select 1 from public.retorno_aberturas a where a.estado in ('aberta', 'vencida') and a.chave not like '000099%')
     or exists (select 1 from public.retorno_saidas s
                 where s.estado in ('agendada', 'preparada', 'enviando', 'incerta') and s.chave not like '000099%')
     or exists (select 1 from public.retorno_aberturas a where a.chave like '000099%')
     or exists (select 1 from public.clients c where c.provisorio)
     or exists (select 1 from public.whatsapp_leads l where l.coleta is not null)
     or exists (select 1 from public.avisos_do_dono a where a.dia between '2027-03-01' and '2027-03-13') then
    raise exception '0e: há caso vivo, saída pendente, cadastro provisório, coleta ou aviso real que o vigia trataria (o arquivo é da bancada de antes do deploy)';
  end if;
  if exists (select 1 from public.clients c
              where public._agenda_chave_telefone(c.phone) like '000099%' or public._agenda_chave_telefone(c.whatsapp) like '000099%')
     or exists (select 1 from public.suppliers s where public._agenda_chave_telefone(s.phone) like '000099%')
     or exists (select 1 from public.whatsapp_blocked_numbers b where b.phone_normalized like '55479000099%')
     or exists (select 1 from public.whatsapp_leads l where l.phone_normalized like '55479000099%') then
    raise exception '0f: há cadastro, fornecedor, bloqueio ou lead real com os números de teste 55479000099xx';
  end if;

  begin
    update public.retorno_config
       set modo = 'sombra', tipos_ligados = '{}', carencia_min = 2, carencia_dono_ativo_min = 10, dono_ativo_janela_min = 15,
           lote_linhas_por_min = 10, lote_janela_min = 3, saudacao_espera_min = 10, audio_espera_min = 3,
           audio_reavaliar_max = interval '24 hours', recibo_intervalo = interval '12 hours', coleta_max = 2,
           volta_min = interval '10 minutes', volta_max = interval '24 hours', espaco_min_s = 30, espaco_max_s = 90,
           proximo_envio_em = null, respostas_dia_max = 40, so_reativo = false, so_reativo_motivo = null,
           so_reativo_desde = null, erros_seguidos = 0, segura_recibos = false, segura_tudo_ate = null, fora_ate = null,
           meio_dia_ligado = false, promessa_faixa = '{}', adiamento_antes = interval '30 minutes',
           acorde_antes = interval '60 minutes', caso_fecha_silencio = interval '4 hours', expira_dias_uteis = 3,
           incerta_conferir_ate = interval '30 minutes', conteudo_min_caracteres = 15,
           cadastro_arquivar_apos = interval '30 days', coleta_retencao = interval '180 days',
           alongar_janela = interval '30 days', alongar_minimo_casos = 20, alongar_meta = 0.80,
           cliente_resposta_direta_inicio = '07:00', cliente_resposta_direta_fim = '22:00',
           atrasada_inicio = '08:00', atrasada_fim = '20:00', atrasada_sabado_fim = '13:00',
           ponto_manha = '07:30', ponto_meio_dia = '12:30', ponto_fechamento = '17:30',
           promessa_manha = '10:00', promessa_meio_dia = '14:00', promessa_fechamento = '19:00',
           corte_meio_dia = '11:00', corte_tarde = '15:30'
     where id;
    update public.whatsapp_conexao_vigia set estado = 'open', desde = '2027-01-01 00:00:00-03' where id = 1;

    -- ── 1. C1 em sombra ──────────────────────────────────────────────────────────────────────────────
    -- 1a. Recibo 09:14 prometido 19h (meio-dia desligado): acorde às 18:00, fim do dia às 18:30, nenhum adiamento.
    perform pg_temp.retorno_f1_vigia_cliente('Nadia Teste', '(47) 90000-9901');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009901', 'Bom dia, preciso de um orçamento para instalar placa solar no motorhome',
                                        c_d1 + interval '9 hours 12 minutes');
    v_caso := pg_temp.retorno_f1_vigia_abre('1a', v_m, c_d1 + interval '9 hours 12 minutes 5 seconds');
    perform pg_temp.retorno_f1_vigia_sombra('1a', (pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo')).id,
                                            c_d1 + interval '9 hours 14 minutes 30 seconds');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    if v_ab.prometido_ate is distinct from c_d1 + interval '19 hours' or v_ab.recibo_em is null then
      raise exception '1a: a sombra do recibo não deu a promessa das 19h: %', to_jsonb(v_ab);
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('1a', c_d1 + interval '18 hours 30 seconds');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'acorde:relogio');
    if v_s.estado is distinct from 'sombra' or v_s.dados -> 'acordaria' is distinct from 'true'::jsonb
       or v_s.enviar_em is distinct from c_d1 + interval '18 hours'
       or (pg_temp.retorno_f1_vigia_saida(v_caso, 'fim_do_dia')).id is not null then
      raise exception '1a: às 18:00 o acorde do relógio não foi decidido (ou o fim do dia nasceu cedo): % / %', to_jsonb(v_s), v_v;
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('1a', c_d1 + interval '18 hours 30 minutes');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'fim_do_dia');
    if v_s.estado is distinct from 'agendada' or v_s.enviar_em is distinct from c_d1 + interval '18 hours 30 minutes'
       or v_s.classe is distinct from 'resposta_atrasada' or v_s.dados ->> 'dia' is distinct from '2027-03-01'
       or (pg_temp.retorno_f1_vigia_saida(v_caso, 'adiamento')).id is not null then
      raise exception '1a: às 18:30 o fim do dia não nasceu (ou nasceu um adiamento sem X2): % / %', to_jsonb(v_s), v_v;
    end if;
    v_r := pg_temp.retorno_f1_vigia_sombra('1a', v_s.id, c_d1 + interval '18 hours 30 minutes 30 seconds');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    if v_r ->> 'texto' is distinct from 'Nadia, o Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele amanhã cedo.'
       or v_ab.estado is distinct from 'vencida' or v_ab.fim_do_dia_em is distinct from c_d1 + interval '18 hours 30 minutes 30 seconds'
       or v_ab.topo_dia is distinct from date '2027-03-02' then
      raise exception '1a: o fim do dia não venceu o caso (ou o texto não é o T22): % / %', v_r, to_jsonb(v_ab);
    end if;
    -- 4. Caso vencido: a mensagem nova depois do fim do dia vira passagem, com acorde, e nenhum recibo novo.
    v_m2 := pg_temp.retorno_f1_vigia_msg('5547900009901', 'Ainda preciso do orçamento, consegue ver?', c_d1 + interval '18 hours 45 minutes');
    perform pg_temp.retorno_f1_vigia_abre('4', v_m2, c_d1 + interval '18 hours 45 minutes 5 seconds');
    v_v := pg_temp.retorno_f1_vigia_roda('4', c_d1 + interval '18 hours 46 minutes');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'acorde:' || v_m2);
    if v_ab.nivel is distinct from 'passagem' or v_s.estado is distinct from 'sombra' or v_s.dados ->> 'por' is distinct from 'vencida'
       or (select count(*) from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo like 'recibo%') <> 1 then
      raise exception '4: a mensagem do caso vencido não virou passagem com acorde (ou ganhou recibo novo): % / %', to_jsonb(v_ab), to_jsonb(v_s);
    end if;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- 1b. Meio-dia ligado, prometido 14h: às 13:30 o adiamento (dados.hora = '19h'); às 19:00 o fim do dia.
    update public.retorno_config set meio_dia_ligado = true where id;
    perform pg_temp.retorno_f1_vigia_cliente('Olga Teste', '(47) 90000-9902');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009902', 'Bom dia, preciso de um orçamento para instalar placa solar no motorhome',
                                        c_d2 + interval '9 hours 12 minutes');
    v_caso := pg_temp.retorno_f1_vigia_abre('1b', v_m, c_d2 + interval '9 hours 12 minutes 5 seconds');
    perform pg_temp.retorno_f1_vigia_sombra('1b', (pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo')).id,
                                            c_d2 + interval '9 hours 14 minutes 30 seconds');
    if (pg_temp.retorno_f1_vigia_caso(v_caso)).prometido_ate is distinct from c_d2 + interval '14 hours' then
      raise exception '1b: com o meio-dia ligado o recibo das 09:14 não prometeu 14h';
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('1b', c_d2 + interval '13 hours 30 minutes');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'adiamento');
    if v_s.estado is distinct from 'agendada' or v_s.enviar_em is distinct from c_d2 + interval '13 hours 30 minutes'
       or v_s.dados ->> 'hora' is distinct from '19h' or (v_s.dados ->> 'x2')::timestamptz is distinct from c_d2 + interval '19 hours'
       or v_s.origem is distinct from 'retorno_adiamento' or v_s.classe is distinct from 'resposta_atrasada' then
      raise exception '1b: às 13:30 o adiamento não nasceu com a hora 19h: % / %', to_jsonb(v_s), v_v;
    end if;
    v_r := pg_temp.retorno_f1_vigia_sombra('1b', v_s.id, c_d2 + interval '13 hours 30 minutes 30 seconds');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    if v_r ->> 'texto' is distinct from 'Olga, o Gustavo ainda não conseguiu retornar, mas seu pedido está com ele e a resposta sai ainda hoje. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
       or v_ab.segundo_prazo is distinct from c_d2 + interval '19 hours' or v_ab.adiamento_em is null then
      raise exception '1b: o adiamento não gravou o 2º prazo (ou não é o T20): % / %', v_r, to_jsonb(v_ab);
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('1b', c_d2 + interval '18 hours 59 minutes');
    if (pg_temp.retorno_f1_vigia_saida(v_caso, 'fim_do_dia')).id is not null then
      raise exception '1b: o fim do dia nasceu antes do X2';
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('1b', c_d2 + interval '19 hours');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'fim_do_dia');
    if v_s.estado is distinct from 'agendada' or v_s.enviar_em is distinct from c_d2 + interval '19 hours'
       or (pg_temp.retorno_f1_vigia_caso(v_caso)).estado is distinct from 'aberta' then
      raise exception '1b: às 19:00 (X2) o fim do dia não nasceu: % / %', to_jsonb(v_s), v_v;
    end if;
    update public.retorno_config set meio_dia_ligado = false where id;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- 1c. O adiamento que não sai não cala o caso (desvio, §3): meio-dia ligado, prometido 14h (X2 = 19h) na qui
    --     11/03. (a) O adiamento recusado pelo validador às 13:30 e (b) o adiamento ainda agendado em X (atrasado:
    --     o retorno_pegar o cancela por caso_vencido) dão os dois o fim do dia em X (T22), e nada antes de X.
    update public.retorno_config set meio_dia_ligado = true where id;
    perform pg_temp.retorno_f1_vigia_cliente('Yara Teste', '(47) 90000-9923');
    perform pg_temp.retorno_f1_vigia_cliente('Zilda Teste', '(47) 90000-9924');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009923', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_d11 + interval '9 hours 12 minutes');
    v_caso := pg_temp.retorno_f1_vigia_abre('1c', v_m, c_d11 + interval '9 hours 12 minutes 5 seconds');
    perform pg_temp.retorno_f1_vigia_sombra('1c', (pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo')).id,
                                            c_d11 + interval '9 hours 14 minutes 30 seconds');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009924', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_d11 + interval '9 hours 13 minutes');
    v_caso2 := pg_temp.retorno_f1_vigia_abre('1c', v_m, c_d11 + interval '9 hours 13 minutes 5 seconds');
    perform pg_temp.retorno_f1_vigia_sombra('1c', (pg_temp.retorno_f1_vigia_saida(v_caso2, 'recibo')).id,
                                            c_d11 + interval '9 hours 15 minutes 30 seconds');
    if (pg_temp.retorno_f1_vigia_caso(v_caso)).prometido_ate is distinct from c_d11 + interval '14 hours'
       or (pg_temp.retorno_f1_vigia_caso(v_caso2)).prometido_ate is distinct from c_d11 + interval '14 hours' then
      raise exception '1c: com o meio-dia ligado os recibos das 09:14 não prometeram 14h';
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('1c', c_d11 + interval '13 hours 30 minutes');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'adiamento');
    v_id2 := (pg_temp.retorno_f1_vigia_saida(v_caso2, 'adiamento')).id;
    if v_s.enviar_em is distinct from c_d11 + interval '13 hours 30 minutes' or v_id2 is null then
      raise exception '1c: os adiamentos das 13:30 não nasceram: % / %', to_jsonb(v_s), v_v;
    end if;
    -- (a) o retorno_pegar devolve o adiamento das 13:30, e o validador da edge o recusa
    v_r := public.retorno_pegar(c_d11 + interval '13 hours 30 minutes 30 seconds');
    if jsonb_typeof(v_r) is distinct from 'object' or (v_r ->> 'saida_id')::uuid is distinct from v_s.id then
      raise exception '1c: o retorno_pegar não devolveu o adiamento das 13:30: %', v_r;
    end if;
    if public.retorno_registrar_decisao(v_s.id, 'recusada', '{"motivo": "validador", "regras": ["dinheiro"]}',
                                        c_d11 + interval '13 hours 30 minutes 31 seconds')
       is distinct from '{"ok": true, "estado": "recusada"}'::jsonb then
      raise exception '1c: a recusa do validador não foi registrada';
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('1c', c_d11 + interval '13 hours 45 minutes');
    if (pg_temp.retorno_f1_vigia_saida(v_caso, 'fim_do_dia')).id is not null
       or (pg_temp.retorno_f1_vigia_saida(v_caso2, 'fim_do_dia')).id is not null then
      raise exception '1c: o fim do dia nasceu antes de X: %', v_v;
    end if;
    -- em X (b continua agendado: ninguém chamou o retorno_pegar depois das 13:31)
    v_v := pg_temp.retorno_f1_vigia_roda('1c', c_d11 + interval '14 hours 30 seconds');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'fim_do_dia');
    v_id := (pg_temp.retorno_f1_vigia_saida(v_caso2, 'fim_do_dia')).id;
    if v_s.estado is distinct from 'agendada' or v_s.enviar_em is distinct from c_d11 + interval '14 hours'
       or v_s.dados ->> 'dia' is distinct from '2027-03-11' or v_id is null
       or (pg_temp.retorno_f1_vigia_le(v_id)).enviar_em is distinct from c_d11 + interval '14 hours'
       or (pg_temp.retorno_f1_vigia_caso(v_caso)).estado is distinct from 'vencida'
       or (pg_temp.retorno_f1_vigia_caso(v_caso2)).estado is distinct from 'vencida' then
      raise exception '1c: em X o adiamento que não saiu não deu o fim do dia em X: % / %', to_jsonb(v_s), v_v;
    end if;
    -- às 14:01 o adiamento atrasado cai (caso_vencido) e os dois fins do dia saem (T22)
    v_r := public.retorno_pegar(c_d11 + interval '14 hours 1 minute');
    v_r2 := public.retorno_pegar(c_d11 + interval '14 hours 1 minute');
    if (pg_temp.retorno_f1_vigia_le(v_id2)).estado is distinct from 'cancelada'
       or (pg_temp.retorno_f1_vigia_le(v_id2)).motivo is distinct from 'caso_vencido'
       or jsonb_typeof(v_r) is distinct from 'object' or jsonb_typeof(v_r2) is distinct from 'object'
       or (array[(v_r ->> 'saida_id')::uuid, (v_r2 ->> 'saida_id')::uuid] @> array[v_s.id, v_id]) is not true
       or (case when (v_r ->> 'saida_id')::uuid = v_s.id then v_r else v_r2 end) ->> 'texto'
          is distinct from 'Yara, o Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele amanhã cedo.'
       or (case when (v_r ->> 'saida_id')::uuid = v_id then v_r else v_r2 end) ->> 'texto'
          is distinct from 'Zilda, o Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele amanhã cedo.' then
      raise exception '1c: os fins do dia em X não saíram (ou o adiamento atrasado não caiu): % / % / %', v_r, v_r2,
        to_jsonb(pg_temp.retorno_f1_vigia_le(v_id2));
    end if;
    update public.retorno_config set meio_dia_ligado = false where id;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 2. Escalonamento: os casos do mesmo X saem em fila, 1 min entre eles, nunca depois de X − 1 ─────
    update public.retorno_config set meio_dia_ligado = true where id;
    v_casos := '{}';
    for v_i in 0 .. 2 loop
      perform pg_temp.retorno_f1_vigia_cliente('Teste F1 vigia 990' || (3 + v_i), '(47) 90000-990' || (3 + v_i));
      v_m := pg_temp.retorno_f1_vigia_msg('554790000990' || (3 + v_i), 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                          c_d3 + interval '9 hours' + make_interval(mins => v_i));
      v_caso := pg_temp.retorno_f1_vigia_abre('2', v_m, c_d3 + interval '9 hours 5 seconds' + make_interval(mins => v_i));
      perform pg_temp.retorno_f1_vigia_sombra('2', (pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo')).id,
                                              c_d3 + interval '9 hours 2 minutes 30 seconds' + make_interval(mins => v_i));
      v_casos := v_casos || v_caso;
    end loop;
    v_v := pg_temp.retorno_f1_vigia_roda('2', c_d3 + interval '13 hours 30 minutes');
    v_em := array(select (pg_temp.retorno_f1_vigia_saida(x.c, 'adiamento')).enviar_em
                    from unnest(v_casos) with ordinality as x(c, n) order by x.n);
    if v_em is distinct from array[c_d3 + interval '13 hours 30 minutes', c_d3 + interval '13 hours 31 minutes',
                                   c_d3 + interval '13 hours 32 minutes'] then
      raise exception '2: os adiamentos do mesmo X não saíram em fila a X−30, X−29 e X−28: %', v_em;
    end if;
    perform pg_temp.retorno_f1_vigia_limpa();
    -- Nunca depois de X − 1: com o adiamento a 2 min de X, os três ficam em X−2, X−1 e X−1.
    update public.retorno_config set adiamento_antes = interval '2 minutes' where id;
    v_casos := '{}';
    for v_i in 0 .. 2 loop
      perform pg_temp.retorno_f1_vigia_cliente('Teste F1 vigia 990' || (6 + v_i), '(47) 90000-990' || (6 + v_i));
      v_m := pg_temp.retorno_f1_vigia_msg('554790000990' || (6 + v_i), 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                          c_d4 + interval '9 hours' + make_interval(mins => v_i));
      v_caso := pg_temp.retorno_f1_vigia_abre('2', v_m, c_d4 + interval '9 hours 5 seconds' + make_interval(mins => v_i));
      perform pg_temp.retorno_f1_vigia_sombra('2', (pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo')).id,
                                              c_d4 + interval '9 hours 2 minutes 30 seconds' + make_interval(mins => v_i));
      v_casos := v_casos || v_caso;
    end loop;
    v_v := pg_temp.retorno_f1_vigia_roda('2', c_d4 + interval '13 hours 58 minutes');
    v_em := array(select (pg_temp.retorno_f1_vigia_saida(x.c, 'adiamento')).enviar_em
                    from unnest(v_casos) with ordinality as x(c, n) order by x.n);
    if v_em is distinct from array[c_d4 + interval '13 hours 58 minutes', c_d4 + interval '13 hours 59 minutes',
                                   c_d4 + interval '13 hours 59 minutes'] then
      raise exception '2: um adiamento passou de X − 1 min: %', v_em;
    end if;
    update public.retorno_config set adiamento_antes = interval '30 minutes', meio_dia_ligado = false where id;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 3. Resposta humana ───────────────────────────────────────────────────────────────────────────
    -- 3a (X = 14h, meio-dia ligado na composição) e 3b (X = 19h).
    update public.retorno_config set meio_dia_ligado = true where id;
    perform pg_temp.retorno_f1_vigia_cliente('Tania Teste', '(47) 90000-9909');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009909', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_d5 + interval '9 hours 12 minutes');
    v_caso := pg_temp.retorno_f1_vigia_abre('3a', v_m, c_d5 + interval '9 hours 12 minutes 5 seconds');
    perform pg_temp.retorno_f1_vigia_sombra('3a', (pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo')).id,
                                            c_d5 + interval '9 hours 14 minutes 30 seconds');
    update public.retorno_config set meio_dia_ligado = false where id;
    perform pg_temp.retorno_f1_vigia_cliente('Ursula Teste', '(47) 90000-9910');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009910', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_d5 + interval '9 hours 20 minutes');
    v_caso2 := pg_temp.retorno_f1_vigia_abre('3b', v_m, c_d5 + interval '9 hours 20 minutes 5 seconds');
    perform pg_temp.retorno_f1_vigia_sombra('3b', (pg_temp.retorno_f1_vigia_saida(v_caso2, 'recibo')).id,
                                            c_d5 + interval '9 hours 22 minutes 30 seconds');
    -- 3b: "ok, já vejo" às 12:00 (11 caracteres: responde, não cumpre).
    perform pg_temp.retorno_f1_vigia_msg('5547900009910', 'ok, já vejo', c_d5 + interval '12 hours', 'outbound');
    v_v := pg_temp.retorno_f1_vigia_roda('3b', c_d5 + interval '12 hours 1 minute');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso2);
    if v_ab.respondida_em is distinct from c_d5 + interval '12 hours' or v_ab.cumprida_em is not null
       or v_ab.estado is distinct from 'aberta' then
      raise exception '3b: o "ok, já vejo" não ficou só em respondida_em: %', to_jsonb(v_ab);
    end if;
    -- 3a: o adiamento agendado às 13:30; a resposta de conteúdo às 13:35 fecha o caso e o cancela.
    v_v := pg_temp.retorno_f1_vigia_roda('3a', c_d5 + interval '13 hours 30 minutes');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'adiamento');
    if v_s.estado is distinct from 'agendada' then
      raise exception '3a: o adiamento das 13:30 não nasceu: %', to_jsonb(v_s);
    end if;
    perform pg_temp.retorno_f1_vigia_msg('5547900009909', 'Oi Tania, consigo ver o seu orçamento amanhã cedo, tudo bem?',
                                         c_d5 + interval '13 hours 35 minutes', 'outbound');
    v_v := pg_temp.retorno_f1_vigia_roda('3a', c_d5 + interval '13 hours 36 minutes');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    v_s := pg_temp.retorno_f1_vigia_le(v_s.id);
    if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'conteudo'
       or v_ab.cumprida_em is distinct from c_d5 + interval '13 hours 35 minutes' or v_ab.cumprida_por is distinct from 'celular'
       or v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'respondida_pelo_dono'
       or (v_v -> 'fechadas' ->> 'conteudo')::int < 1 then
      raise exception '3a: a resposta de conteúdo não fechou o caso e cancelou o adiamento: % / % / %', to_jsonb(v_ab), to_jsonb(v_s), v_v;
    end if;
    -- 3b: às 16:00 continua aberto (promessa ouvida nunca fecha por silêncio); às 18:30 o fim do dia nasce e não cai.
    v_v := pg_temp.retorno_f1_vigia_roda('3b', c_d5 + interval '16 hours 1 minute');
    if (pg_temp.retorno_f1_vigia_caso(v_caso2)).estado is distinct from 'aberta' then
      raise exception '3b: o caso com promessa ouvida fechou por silêncio: %', to_jsonb(pg_temp.retorno_f1_vigia_caso(v_caso2));
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('3b', c_d5 + interval '18 hours 30 minutes');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso2, 'fim_do_dia');
    v_r := public.retorno_pegar(c_d5 + interval '18 hours 30 minutes 30 seconds');
    if v_s.id is null or jsonb_typeof(v_r) is distinct from 'object' or (v_r ->> 'saida_id')::uuid is distinct from v_s.id
       or (pg_temp.retorno_f1_vigia_le(v_s.id)).estado is distinct from 'preparada' then
      raise exception '3b: o fim do dia das 18:30 não nasceu ou foi cancelado pelo "ok, já vejo": % / %', to_jsonb(v_s), v_r;
    end if;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 15. Futuro: a resposta humana gravada depois de agora não preenche respondida_em ──────────────
    perform pg_temp.retorno_f1_vigia_cliente('Xenia Teste', '(47) 90000-9922');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009922', 'Bom dia, preciso de um orçamento para trocar a bateria da lancha',
                                        c_d8 + interval '11 hours');
    v_caso := pg_temp.retorno_f1_vigia_abre('15', v_m, c_d8 + interval '11 hours 5 seconds');
    perform pg_temp.retorno_f1_vigia_msg('5547900009922', 'Oi! Já te respondo sobre o orçamento', c_d8 + interval '11 hours 30 minutes',
                                         'outbound');
    v_v := pg_temp.retorno_f1_vigia_roda('15', c_d8 + interval '11 hours 20 minutes');
    if (pg_temp.retorno_f1_vigia_caso(v_caso)).respondida_em is not null then
      raise exception '15: a resposta do futuro preencheu respondida_em';
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('15', c_d8 + interval '11 hours 31 minutes');
    if (pg_temp.retorno_f1_vigia_caso(v_caso)).respondida_em is distinct from c_d8 + interval '11 hours 30 minutes' then
      raise exception '15: chegada a hora, a resposta não preencheu respondida_em';
    end if;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 12. Expirou: 4 dias úteis sem recebida (ter 02/03 → seg 08/03) ────────────────────────────────
    v_caso := pg_temp.retorno_f1_vigia_caso_sintetico('5547900009920', c_d2 + interval '10 hours', 'cliente');
    v_id := pg_temp.retorno_f1_vigia_sintetica(v_caso, '5547900009920', 'recibo_cliente', 'agendada', c_d8 + interval '11 hours');
    v_caso2 := pg_temp.retorno_f1_vigia_caso_sintetico('5547900009921', c_d2 + interval '10 hours', 'cliente');
    update public.retorno_aberturas set topo_dia = '2027-03-08' where id = v_caso2;
    v_v := pg_temp.retorno_f1_vigia_roda('12', c_d5 + interval '10 hours');
    if (pg_temp.retorno_f1_vigia_caso(v_caso)).estado is distinct from 'aberta' then
      raise exception '12: o caso expirou com só 3 dias úteis';
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('12', c_d8 + interval '10 hours');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'expirou'
       or (pg_temp.retorno_f1_vigia_le(v_id)).estado is distinct from 'cancelada'
       or (pg_temp.retorno_f1_vigia_le(v_id)).motivo is distinct from 'caso_fechado'
       or (pg_temp.retorno_f1_vigia_caso(v_caso2)).estado is distinct from 'aberta' then
      raise exception '12: expirou errado (o de 4 dias úteis fecha e cancela; o de topo_dia hoje fica): % / %', to_jsonb(v_ab), v_v;
    end if;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 12b. (cartão F1-10, 08/11) Sem prazo (expira_dias_uteis nulo, o padrão): o caso de 4 dias úteis fica ──
    update public.retorno_config set expira_dias_uteis = null where id;
    v_caso := pg_temp.retorno_f1_vigia_caso_sintetico('5547900009920', c_d2 + interval '10 hours', 'cliente');
    v_id := pg_temp.retorno_f1_vigia_sintetica(v_caso, '5547900009920', 'recibo_cliente', 'agendada', c_d8 + interval '11 hours');
    v_v := pg_temp.retorno_f1_vigia_roda('12b', c_d8 + interval '10 hours');
    if (pg_temp.retorno_f1_vigia_caso(v_caso)).estado is distinct from 'aberta'
       or (pg_temp.retorno_f1_vigia_le(v_id)).estado is distinct from 'agendada'
       or (v_v #>> '{fechadas,expirou}')::int is distinct from 0 then
      raise exception '12b: sem prazo, o caso de 4 dias úteis fechou, a agendada caiu ou o vigia contou expirado: % / %',
        to_jsonb(pg_temp.retorno_f1_vigia_caso(v_caso)), v_v;
    end if;
    update public.retorno_config set expira_dias_uteis = 3 where id;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 5. Acorde simulado: o teto do dia em avisos_do_dono; às 20:30 fora da janela ─────────────────
    v_r := public._retorno_acorde_simulado(c_d9 + interval '10 hours');
    if v_r ->> 'acordaria' is distinct from 'true' then
      raise exception '5: sem acorde no dia, o acorde simulado não acordaria: %', v_r;
    end if;
    for v_i in 1 .. v_limite - 1 loop
      insert into public.avisos_do_dono (dia, phone_normalized, modo, fonte, chave, assunto, destino, decisao, situacao, registrado_em)
      values ('2027-03-09', v_dono, 'sombra', 'teste_retorno', 'teste-f1-vigia-acorde-' || v_i, 'Teste F1 vigia: acorde do dia',
              'acorde', 'acordar', 'acordou', c_d9 + interval '9 hours');
    end loop;
    -- o último acorde do teto só foi registrado às 11:00: às 10:00 ainda não conta (ninguém olha o futuro)
    insert into public.avisos_do_dono (dia, phone_normalized, modo, fonte, chave, assunto, destino, decisao, situacao, registrado_em)
    values ('2027-03-09', v_dono, 'ligado', 'teste_retorno', 'teste-f1-vigia-acorde-ultimo', 'Teste F1 vigia: acorde do dia',
            'acorde', 'acordar', 'acordou', c_d9 + interval '11 hours');
    v_r := public._retorno_acorde_simulado(c_d9 + interval '10 hours');
    if v_r ->> 'acordaria' is distinct from 'true' then
      raise exception '5: o acorde registrado depois de agora contou no teto: %', v_r;
    end if;
    v_r := public._retorno_acorde_simulado(c_d9 + interval '11 hours 30 minutes');
    if v_r ->> 'acordaria' is distinct from 'false' or v_r ->> 'motivo' is distinct from 'limite_do_dia' then
      raise exception '5: com % acordes no dia, o acorde simulado não parou no limite_do_dia: %', v_limite, v_r;
    end if;
    v_r := public._retorno_acorde_simulado(c_d9 + interval '20 hours 30 minutes');
    if v_r is distinct from '{"acordaria": false, "motivo": "fora_da_janela"}'::jsonb then
      raise exception '5: às 20:30 o acorde simulado não ficou fora_da_janela: %', v_r;
    end if;
    delete from public.avisos_do_dono where chave like 'teste-f1-vigia-acorde-%';

    -- ── 6. Incerta: só conferir na conversa; nunca reenviar ──────────────────────────────────────────
    v_id := pg_temp.retorno_f1_vigia_sintetica(null, '5547900009911', 'recibo_cliente', 'incerta', c_d9 + interval '14 hours');
    v_id2 := pg_temp.retorno_f1_vigia_sintetica(null, '5547900009912', 'recibo_cliente', 'incerta', c_d9 + interval '14 hours');
    perform pg_temp.retorno_f1_vigia_msg('5547900009911', 'Teste F1 vigia: o texto que a saída teria.', c_d9 + interval '14 hours 1 minute',
                                         'outbound', 'text', '{"via": "retorno"}'::jsonb);
    v_v := pg_temp.retorno_f1_vigia_roda('6', c_d9 + interval '14 hours 11 minutes');
    v_s := pg_temp.retorno_f1_vigia_le(v_id);
    if v_s.estado is distinct from 'enviada' or v_s.enviada_em is distinct from c_d9 + interval '14 hours 1 minute'
       or (pg_temp.retorno_f1_vigia_le(v_id2)).estado is distinct from 'incerta' then
      raise exception '6: a incerta com eco não virou enviada (ou a sem eco mudou): % / %', to_jsonb(v_s), v_v;
    end if;
    v_v := pg_temp.retorno_f1_vigia_roda('6', c_d9 + interval '14 hours 21 minutes');
    v_v := pg_temp.retorno_f1_vigia_roda('6', c_d9 + interval '14 hours 31 minutes');
    if (pg_temp.retorno_f1_vigia_le(v_id2)).estado is distinct from 'incerta'
       or (select count(*) from public.retorno_saidas s where s.chave = '00009912') <> 1
       or exists (select 1 from public.retorno_saidas s where s.chave = '00009912' and s.estado = 'agendada') then
      raise exception '6: a incerta sem eco ganhou 2ª tentativa (ou mudou de estado)';
    end if;
    -- Depois dos 30 min nada muda: o eco que aparece às 14:35 de uma incerta das 14:00 não a confere mais.
    perform pg_temp.retorno_f1_vigia_msg('5547900009912', 'Teste F1 vigia: o texto que a saída teria.', c_d9 + interval '14 hours 35 minutes',
                                         'outbound', 'text', '{"via": "retorno"}'::jsonb);
    v_v := pg_temp.retorno_f1_vigia_roda('6', c_d9 + interval '14 hours 36 minutes');
    if (pg_temp.retorno_f1_vigia_le(v_id2)).estado is distinct from 'incerta' then
      raise exception '6: passados os 30 min, a incerta ainda foi conferida';
    end if;

    -- ── 7. Presos ────────────────────────────────────────────────────────────────────────────────────
    v_id := pg_temp.retorno_f1_vigia_sintetica(null, '5547900009913', 'recibo_cliente', 'preparada', c_d9 + interval '14 hours 50 minutes',
                                               '{}', c_d9 + interval '14 hours 52 minutes');
    perform pg_temp.retorno_f1_vigia_cliente('Vera Teste', '(47) 90000-9914');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009914', 'Preciso de orçamento para trocar a bateria da lancha', c_d9 + interval '14 hours 40 minutes');
    v_caso := pg_temp.retorno_f1_vigia_abre('7', v_m, c_d9 + interval '14 hours 40 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo');
    v_pz := public._retorno_prazo(c_d9 + interval '14 hours 42 minutes', '00009914', false, false);
    update public.retorno_saidas
       set estado = 'enviando', modo = 'ligado', texto = 'Teste F1 vigia: o texto que a saída teria.', variante = 'padrao',
           decidida_em = c_d9 + interval '14 hours 42 minutes', processando_ate = c_d9 + interval '14 hours 44 minutes',
           dados = dados || jsonb_build_object('prazo', v_pz)
     where id = v_s.id;
    -- Uma 2ª enviando presa do mesmo caso, com o prazo ilegível: o efeito falha, vai ao log, e ela fica incerta mesmo
    -- assim; o erro dela não desfaz o resto do passo (a preparada volta, a outra enviando aplica a promessa).
    v_id2 := pg_temp.retorno_f1_vigia_sintetica(v_caso, '5547900009914', 'recibo_cliente', 'enviando', c_d9 + interval '14 hours 43 minutes',
                                                '{"prazo": {"prometido_ate": "x"}}', c_d9 + interval '14 hours 45 minutes');
    v_v := pg_temp.retorno_f1_vigia_roda('7', c_d9 + interval '15 hours');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    select count(*) into v_logs from public.app_error_logs l
     where l.context = 'retorno' and l.action = 'vigia' and l.details ->> 'passo' = '9'
       and l.details ->> 'saida' = v_id2::text and l.last_seen_at = now();
    if (pg_temp.retorno_f1_vigia_le(v_id)).estado is distinct from 'agendada' or (pg_temp.retorno_f1_vigia_le(v_id)).processando_ate is not null
       or (pg_temp.retorno_f1_vigia_le(v_id)).enviar_em is distinct from c_d9 + interval '15 hours'
       or (pg_temp.retorno_f1_vigia_le(v_id)).dados ->> 'presas' is distinct from '1'
       or (pg_temp.retorno_f1_vigia_le(v_s.id)).estado is distinct from 'incerta'
       or (pg_temp.retorno_f1_vigia_le(v_id2)).estado is distinct from 'incerta'
       or v_ab.prometido_ate is distinct from c_d9 + interval '19 hours' or (v_v ->> 'presas')::int <> 3 or v_logs < 1 then
      raise exception '7: os presos não foram soltos um a um (preparada → agendada, atrás das vencidas; enviando → incerta com a promessa; o efeito ilegível só no log): % / % / logs %',
        to_jsonb(v_ab), v_v, v_logs;
    end if;
    -- A mesma preparada presa de novo (a edge falhou outra vez no mesmo item): recusada/erro, com log; nunca volta à fila.
    update public.retorno_saidas
       set estado = 'preparada', decidida_em = c_d9 + interval '15 hours 30 seconds',
           processando_ate = c_d9 + interval '15 hours 2 minutes 30 seconds'
     where id = v_id;
    v_v := pg_temp.retorno_f1_vigia_roda('7', c_d9 + interval '15 hours 8 minutes');
    v_s := pg_temp.retorno_f1_vigia_le(v_id);
    select count(*) into v_logs from public.app_error_logs l
     where l.context = 'retorno' and l.action = 'vigia' and l.details ->> 'passo' = '9'
       and l.details ->> 'saida' = v_id::text and l.last_seen_at = now();
    if v_s.estado is distinct from 'recusada' or v_s.motivo is distinct from 'erro' or v_s.processando_ate is not null
       or v_s.dados ->> 'presas' is distinct from '2' or (v_v ->> 'presas')::int <> 1 or v_logs < 1 then
      raise exception '7: a preparada presa pela 2ª vez não virou recusada/erro com log: % / % / logs %', to_jsonb(v_s), v_v, v_logs;
    end if;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 8. Rebaixamento automático, com o grupo ──────────────────────────────────────────────────────
    -- 8a. Opt-out 1 h depois de uma enviada de recibo_cliente à mesma chave: recibo_cliente sai.
    update public.retorno_config set tipos_ligados = '{recibo_cliente,adiamento,fim_do_dia}' where id;
    perform pg_temp.retorno_f1_vigia_sintetica(null, '5547900009915', 'recibo_cliente', 'enviada', c_d10 + interval '10 hours');
    insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo, created_at)
    values ('5547900009915', 'Teste F1 vigia', 'opt_out', c_d10 + interval '11 hours');
    v_v := pg_temp.retorno_f1_vigia_roda('8a', c_d10 + interval '11 hours 1 minute');
    select * into v_cfg from public.retorno_config where id;
    select count(*) into v_logs from public.app_error_logs l
     where l.context = 'retorno' and l.action = 'rebaixamento' and l.last_seen_at = now();
    if v_cfg.tipos_ligados is distinct from '{adiamento,fim_do_dia}'::text[] or v_v -> 'rebaixados' is distinct from '["recibo_cliente"]'::jsonb
       or v_logs < 1 then
      raise exception '8a: o opt-out depois da enviada não rebaixou recibo_cliente (com log): % / % / logs %', v_cfg.tipos_ligados, v_v, v_logs;
    end if;
    -- 8b. 3 recusas do validador de adiamento em 1 h: saem o adiamento e os recibo_* (o grupo); o check não quebra.
    --     O opt-out do 8a sai antes, para só a regra do validador decidir (e o grupo ser quem tira o recibo_cliente).
    delete from public.whatsapp_blocked_numbers where phone_normalized = '5547900009915';
    update public.retorno_config set tipos_ligados = '{recibo_cliente,adiamento,fim_do_dia}' where id;
    for v_i in 0 .. 2 loop
      perform pg_temp.retorno_f1_vigia_sintetica(null, '5547900009916', 'adiamento', 'recusada',
                                                 c_d10 + interval '12 hours' + make_interval(mins => 10 * v_i));
    end loop;
    v_v := pg_temp.retorno_f1_vigia_roda('8b', c_d10 + interval '12 hours 30 minutes');
    select * into v_cfg from public.retorno_config where id;
    if v_cfg.tipos_ligados is distinct from '{fim_do_dia}'::text[] then
      raise exception '8b: 3 recusas do validador de adiamento não tiraram o grupo: % / %', v_cfg.tipos_ligados, v_v;
    end if;
    -- 8c. 3 recusas do recibo de número novo: saem a coleta e o cadastro junto (adiamento e fim do dia ficam).
    update public.retorno_config
       set tipos_ligados = '{recibo_numero_novo,coleta_numero_novo,cadastro_provisorio,adiamento,fim_do_dia}' where id;
    for v_i in 0 .. 2 loop
      perform pg_temp.retorno_f1_vigia_sintetica(null, '5547900009917', 'recibo_numero_novo', 'recusada',
                                                 c_d10 + interval '13 hours' + make_interval(mins => 10 * v_i));
    end loop;
    v_v := pg_temp.retorno_f1_vigia_roda('8c', c_d10 + interval '13 hours 30 minutes');
    select * into v_cfg from public.retorno_config where id;
    if v_cfg.tipos_ligados is distinct from '{adiamento,fim_do_dia}'::text[] then
      raise exception '8c: sem o recibo de número novo, a coleta e o cadastro não saíram junto: % / %', v_cfg.tipos_ligados, v_v;
    end if;
    update public.retorno_config set tipos_ligados = '{}' where id;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 10. Disjuntor pela conexão, nos dois sentidos (num sub-bloco: a linha real da conexão volta na hora) ──
    begin
      update public.whatsapp_conexao_vigia set estado = 'close', desde = c_d10 + interval '15 hours 45 minutes' where id = 1;
      v_dv1 := public.retorno_vigia(c_d10 + interval '16 hours');
      select * into v_d1 from public.retorno_config where id;
      update public.whatsapp_conexao_vigia set estado = 'open', desde = c_d10 + interval '16 hours 5 minutes' where id = 1;
      v_dv2 := public.retorno_vigia(c_d10 + interval '16 hours 17 minutes');
      select * into v_d2 from public.retorno_config where id;
      update public.retorno_config
         set so_reativo = true, so_reativo_motivo = 'erros', so_reativo_desde = c_d10 + interval '16 hours 20 minutes' where id;
      v_dv3 := public.retorno_vigia(c_d10 + interval '16 hours 30 minutes');
      select * into v_d3 from public.retorno_config where id;
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    if not v_d1.so_reativo or v_d1.so_reativo_motivo is distinct from 'conexao'
       or v_d1.so_reativo_desde is distinct from c_d10 + interval '16 hours' or v_dv1 ->> 'disjuntor' is distinct from 'ligou' then
      raise exception '10: a conexão fechada há 15 min não ligou o so_reativo (conexao): % / %', to_jsonb(v_d1), v_dv1;
    end if;
    if v_d2.so_reativo or v_d2.so_reativo_motivo is not null or v_d2.so_reativo_desde is not null
       or v_dv2 ->> 'disjuntor' is distinct from 'desligou' then
      raise exception '10: a conexão aberta há 12 min não desligou o so_reativo: % / %', to_jsonb(v_d2), v_dv2;
    end if;
    if not v_d3.so_reativo or v_d3.so_reativo_motivo is distinct from 'erros' or v_dv3 -> 'disjuntor' <> 'null'::jsonb then
      raise exception '10: com o motivo erros, a conexão aberta desligou o so_reativo: % / %', to_jsonb(v_d3), v_dv3;
    end if;
    if (select c.estado from public.whatsapp_conexao_vigia c where c.id = 1) is distinct from 'open'
       or (select c.so_reativo from public.retorno_config c where c.id) then
      raise exception '10: o sub-bloco do disjuntor não foi desfeito';
    end if;

    -- ── 11. Áudio transcrito ─────────────────────────────────────────────────────────────────────────
    -- 11a. Número novo manda só '[audio]': caso nada/numero_novo_sem_pedido, sem saída.
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009918', '[audio]', c_d11 + interval '10 hours', 'inbound', 'audio');
    v_caso := pg_temp.retorno_f1_vigia_abre('11a', v_m, c_d11 + interval '10 hours 5 seconds');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    if v_ab.nivel is distinct from 'nada' or v_ab.motivo is distinct from 'numero_novo_sem_pedido'
       or exists (select 1 from public.retorno_saidas s where s.abertura_id = v_caso) then
      raise exception '11a: o [audio] do número novo não ficou nada/numero_novo_sem_pedido sem saída: %', to_jsonb(v_ab);
    end if;
    -- 11a'. A reavaliação que falha (retorno_abrir com ok = false; aqui um check que recusa o hash novo, num sub-bloco
    --       desfeito) não conta, tira a linha do filtro e vai ao log: nada volta a cada minuto por 24 h.
    begin
      alter table public.retorno_mensagens add constraint retorno_f1_vigia_falha
        check (corpo_hash <> md5('🎤 preciso trocar a bateria do motorhome')) not valid;
      update public.whatsapp_messages set body = '🎤 preciso trocar a bateria do motorhome' where id = v_m;
      v_dv1 := public.retorno_vigia(c_d11 + interval '10 hours 1 minute');
      select rm.audio_pendente into v_b1 from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m;
      select count(*) into v_logs from public.app_error_logs l
       where l.context = 'retorno' and l.action = 'vigia' and l.details ->> 'passo' = '3'
         and l.details ->> 'mensagem' = v_m::text and l.last_seen_at = now();
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    if v_dv1 -> 'ok' is distinct from 'true'::jsonb or (v_dv1 ->> 'audios')::int <> 0 or v_b1 is distinct from false
       or v_logs < 1 then
      raise exception '11a: a reavaliação com ok = false contou, ficou no filtro ou não foi ao log: % / % / logs %', v_dv1, v_b1, v_logs;
    end if;
    if (select rm.audio_pendente from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m) is distinct from true
       or (select w.body from public.whatsapp_messages w where w.id = v_m) is distinct from '[audio]' then
      raise exception '11a: o sub-bloco da reavaliação que falha não foi desfeito';
    end if;
    -- 11b. A transcrição troca o body: o vigia seguinte tria de novo e agenda o recibo do número novo.
    update public.whatsapp_messages set body = '🎤 preciso trocar a bateria do motorhome' where id = v_m;
    v_v := pg_temp.retorno_f1_vigia_roda('11b', c_d11 + interval '10 hours 1 minute');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso);
    v_s := pg_temp.retorno_f1_vigia_saida(v_caso, 'recibo');
    if (v_v ->> 'audios')::int < 1 or v_ab.nivel is distinct from 'recibo' or v_ab.tipo_recibo is distinct from 'recibo_numero_novo'
       or v_s.tipo is distinct from 'recibo_numero_novo' or v_s.estado is distinct from 'agendada' then
      raise exception '11b: a transcrição não reabriu a triagem com o recibo de número novo: % / % / %', to_jsonb(v_ab), to_jsonb(v_s), v_v;
    end if;
    -- 11c. O áudio de um cliente que vira "tá saindo fumaça do quadro": passagem, com risco e o acorde.
    perform pg_temp.retorno_f1_vigia_cliente('Wilma Teste', '(47) 90000-9919');
    v_m := pg_temp.retorno_f1_vigia_msg('5547900009919', '[audio]', c_d11 + interval '10 hours 10 minutes', 'inbound', 'audio');
    v_caso2 := pg_temp.retorno_f1_vigia_abre('11c', v_m, c_d11 + interval '10 hours 10 minutes 5 seconds');
    update public.whatsapp_messages set body = '🎤 tá saindo fumaça do quadro' where id = v_m;
    v_v := pg_temp.retorno_f1_vigia_roda('11c', c_d11 + interval '10 hours 11 minutes');
    v_ab := pg_temp.retorno_f1_vigia_caso(v_caso2);
    if v_ab.nivel is distinct from 'passagem' or v_ab.sinais -> 'risco' is distinct from 'true'::jsonb
       or (pg_temp.retorno_f1_vigia_saida(v_caso2, 'acorde:' || v_m)).estado is distinct from 'sombra' then
      raise exception '11c: o áudio de risco transcrito não virou passagem com acorde: %', to_jsonb(v_ab);
    end if;
    perform pg_temp.retorno_f1_vigia_limpa();

    -- ── 9, 13 e 14. Os passos diários (04:00 de Brasília) ────────────────────────────────────────────
    -- 9. Provisórios: de 31 dias sem OS, de 31 dias com OS, de 29 dias.
    insert into public.clients (type, name, whatsapp, provisorio, origem, active, created_at)
    values ('individual', 'Teste F1 vigia provisório 31', '(47) 90000-9930', true, 'retorno', true, c_d11 + interval '4 hours' - interval '31 days')
    returning id into v_c;
    insert into public.clients (type, name, whatsapp, provisorio, origem, active, created_at)
    values ('individual', 'Teste F1 vigia provisório 31 com OS', '(47) 90000-9937', true, 'retorno', true,
            c_d11 + interval '4 hours' - interval '31 days')
    returning id into v_c2;
    insert into public.vessels (client_id, name, asset_type) values (v_c2, 'Motorhome', 'Motorhome') returning id into v_ve;
    insert into public.service_orders (service_order_number, client_id, vessel_id, status)
    values ('TESTE-F1-VIGIA-9937', v_c2, v_ve, 'draft');
    insert into public.clients (type, name, whatsapp, provisorio, origem, active, created_at)
    values ('individual', 'Teste F1 vigia provisório 29', '(47) 90000-9938', true, 'retorno', true, c_d11 + interval '4 hours' - interval '29 days')
    returning id into v_c3;
    -- 13. Coletas: 181 dias sem cadastro; 181 dias com cadastro da chave; 179 dias. E os leads.
    v_caso := pg_temp.retorno_f1_vigia_caso_sintetico('5547900009931', c_d11 + interval '4 hours' - interval '181 days', 'numero_novo',
                                                     'fechada', '{"nome": null, "tipo": "Motorhome", "fonte": "retorno"}');
    v_caso2 := pg_temp.retorno_f1_vigia_caso_sintetico('5547900009932', c_d11 + interval '4 hours' - interval '181 days', 'numero_novo',
                                                      'fechada', '{"nome": null, "tipo": "Motorhome", "fonte": "retorno"}');
    perform pg_temp.retorno_f1_vigia_cliente('Teste F1 vigia cadastro da coleta', '(47) 90000-9932');
    v_caso3 := pg_temp.retorno_f1_vigia_caso_sintetico('5547900009933', c_d11 + interval '4 hours' - interval '179 days', 'numero_novo',
                                                      'fechada', '{"nome": null, "tipo": "Motorhome", "fonte": "retorno"}');
    insert into public.whatsapp_leads (phone_normalized, name, status, last_inbound_at, coleta)
    values ('5547900009934', 'Teste F1 vigia lead 181', 'pending', c_d11 + interval '4 hours' - interval '181 days', '{"nome": null}')
    returning id into v_l1;
    insert into public.whatsapp_leads (phone_normalized, name, status, last_inbound_at, coleta)
    values ('5547900009935', 'Teste F1 vigia lead 179', 'pending', c_d11 + interval '4 hours' - interval '179 days', '{"nome": null}')
    returning id into v_l2;
    insert into public.whatsapp_leads (phone_normalized, name, status, last_inbound_at, coleta)
    values ('5547900009936', 'Teste F1 vigia lead convertido', 'converted', c_d11 + interval '4 hours' - interval '181 days', '{"nome": null}')
    returning id into v_l3;
    -- 14. 19 casos da faixa meio com o recibo enviado, 14 cumpridos no prazo (73%).
    for v_i in 1 .. 19 loop
      perform pg_temp.retorno_f1_vigia_caso_meio(v_i, v_i <= 14);
    end loop;

    -- Fora do minuto das 04:00, nada diário.
    v_v := pg_temp.retorno_f1_vigia_roda('9', c_d11 + interval '3 hours 59 minutes');
    if v_v -> 'diario' is distinct from 'false'::jsonb or (select active from public.clients where id = v_c) is distinct from true then
      raise exception '9: o passo diário rodou fora das 04:00: %', v_v;
    end if;
    -- Qui 11/03 04:00:30, LIGADO: arquiva, apaga as coletas velhas e, com só 19 casos na faixa, não alonga.
    update public.retorno_config set modo = 'ligado' where id;
    v_v := pg_temp.retorno_f1_vigia_roda('9', c_d11 + interval '4 hours 30 seconds');
    if (select active from public.clients where id = v_c) is distinct from false
       or (select active from public.clients where id = v_c2) is distinct from true
       or (select active from public.clients where id = v_c3) is distinct from true
       or not exists (select 1 from public.clients where id = v_c) then
      raise exception '9: o arquivamento dos provisórios está errado (31 sem OS sai; com OS e 29 dias ficam; nunca apaga): %', v_v;
    end if;
    if (pg_temp.retorno_f1_vigia_caso(v_caso)).coleta is not null
       or (pg_temp.retorno_f1_vigia_caso(v_caso2)).coleta is null
       or (pg_temp.retorno_f1_vigia_caso(v_caso3)).coleta is null
       or (select coleta from public.whatsapp_leads where id = v_l1) is not null
       or (select coleta from public.whatsapp_leads where id = v_l2) is null
       or (select coleta from public.whatsapp_leads where id = v_l3) is null then
      raise exception '13: a retenção da coleta está errada (181 sem cadastro sai; com cadastro, 179 dias e convertido ficam): %', v_v;
    end if;
    select * into v_cfg from public.retorno_config where id;
    if v_cfg.promessa_faixa <> '{}'::jsonb or exists (select 1 from public.retorno_alongamentos) then
      raise exception '14: ligado, com 19 casos a faixa alongou: %', v_cfg.promessa_faixa;
    end if;
    -- O 20º caso (cumprido): 15 de 20 = 75% < 80%, o que alongaria ligado. Sex 12/03 04:00:30, em SOMBRA: nada (o
    -- portão do modo; sem ele, este é o caso que alongaria).
    perform pg_temp.retorno_f1_vigia_caso_meio(20, true);
    update public.retorno_config set modo = 'sombra' where id;
    v_v := pg_temp.retorno_f1_vigia_roda('14', c_d12 + interval '4 hours 30 seconds');
    select * into v_cfg from public.retorno_config where id;
    if v_cfg.promessa_faixa <> '{}'::jsonb or exists (select 1 from public.retorno_alongamentos)
       or v_v -> 'alongadas' is distinct from '[]'::jsonb then
      raise exception '14: em sombra, com 20 casos a 75%%, a faixa alongou: % / %', v_cfg.promessa_faixa, v_v;
    end if;
    -- Sáb 13/03 04:00:30, LIGADO, os mesmos 20 casos: meio passa a 10h do próximo dia útil.
    update public.retorno_config set modo = 'ligado' where id;
    v_v := pg_temp.retorno_f1_vigia_roda('14', c_d13 + interval '4 hours 30 seconds');
    select * into v_cfg from public.retorno_config where id;
    if v_cfg.promessa_faixa is distinct from '{"meio": {"dias": 1, "hora": "10:00"}}'::jsonb
       or v_v -> 'alongadas' is distinct from '["meio"]'::jsonb
       or (select count(*) from public.retorno_alongamentos) <> 1
       or not exists (select 1 from public.retorno_alongamentos l
                       where l.faixa = 'meio' and l.de = '{"dias": 0, "hora": "19:00"}'::jsonb
                         and l.para = '{"dias": 1, "hora": "10:00"}'::jsonb and l.casos = 20 and l.pct = 0.75
                         and l.em = c_d13 + interval '4 hours 30 seconds') then
      raise exception '14: 20 casos com 75%% no prazo não alongaram a faixa meio: % / %', v_cfg.promessa_faixa, v_v;
    end if;
    -- A mesma evidência não alonga de novo no dia seguinte (só os recibos depois do último alongamento contam).
    v_v := pg_temp.retorno_f1_vigia_roda('14', c_d13 + interval '1 day 4 hours 30 seconds');
    if (select count(*) from public.retorno_alongamentos) <> 1 then
      raise exception '14: a mesma evidência alongou a faixa duas vezes: %', v_v;
    end if;
    update public.retorno_config set modo = 'sombra', promessa_faixa = '{}' where id;

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0g: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.retorno_aberturas a where a.chave like '000099%')
     or exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000099%')
     or exists (select 1 from public.clients c where c.provisorio)
     or (select to_jsonb(c) from public.retorno_config c where c.id) is distinct from v_cfg_antes
     or (select to_jsonb(c) from public.whatsapp_conexao_vigia c where c.id = 1) is distinct from v_conexao_antes then
    raise exception '0h: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_vigia', true, jsonb_build_object('acordes_por_dia', v_limite));
end
$vigia$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
