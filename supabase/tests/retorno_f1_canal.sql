-- Retorno F1 (P4): canal_pode_enviar (as 12 regras, na ordem), _retorno_modo_efetivo (as 9 regras do modo do
-- caso) e retorno_saida_autorizada (a conferência do whatsapp-send), mais _retorno_parar_permitido (a única
-- exceção ao bloqueio: a confirmação do PARAR) e _retorno_janela (a janela de cada classe).
-- Datas fixas de dezembro de 2026, em Brasília (sem horário de verão): seg 07/12, ter 08/12 e qua 09/12 são dias
-- úteis; sáb 12/12, dom 13/12, seg 14/12; qui 24/12, sex 25/12 (Natal, feriado), sáb 26/12. O caso 0 confere essas
-- premissas na agenda de produção (só lida): se uma mudar, o arquivo para ali, dizendo qual.
-- A configuração do retorno é posta nos valores de nascença no começo do arranjo (sombra, nada ligado, janelas e
-- momentos padrão, sem segura_*, sem so_reativo, sem proximo_envio_em, teto 40); cada caso muda só o que precisa.
-- O teto da HBR (caso 10) conta a tabela inteira: o caso mede antes as saídas que já houver no dia e completa até 40.
-- Linhas "do futuro" (decididas ou gravadas depois de p_agora) nunca mudam o resultado: casos 10a, P6, P7, M6g, M8b.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_canal.sql
-- Termina em ROLLBACK: nada fica gravado. Telefones de teste 55479000095xx; todo arranjo (retorno_config,
-- cadastros, bloqueios, casos, saídas e a função renomeada do caso A-erro) é desfeito dentro do arquivo
-- (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Confere uma resposta de canal_pode_enviar: o contrato C-CANAL (as 3 chaves), pode, motivo e enviar_em
-- (nulo quando p_de é nulo; = p_de quando p_ate é nulo; senão em [p_de, p_ate)). Devolve 1, para somar.
create or replace function pg_temp.retorno_f1_canal_confere(p_caso text, p_r jsonb, p_pode boolean, p_motivo text,
                                                            p_de timestamptz default null, p_ate timestamptz default null)
returns integer
language plpgsql as $f$
declare
  v_em timestamptz;
begin
  if jsonb_typeof(p_r) is distinct from 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_r) k)
        is distinct from array['enviar_em', 'motivo', 'pode'] then
    raise exception '%: fora do contrato C-CANAL: %', p_caso, p_r;
  end if;
  if p_r -> 'pode' is distinct from to_jsonb(p_pode) or p_r ->> 'motivo' is distinct from p_motivo then
    raise exception '%: esperado pode = %, motivo = %; veio %', p_caso, p_pode, coalesce(p_motivo, '(nulo)'), p_r;
  end if;
  v_em := (p_r ->> 'enviar_em')::timestamptz;
  if p_de is null then
    if v_em is not null then
      raise exception '%: enviar_em deveria ser nulo: %', p_caso, p_r;
    end if;
  elsif p_ate is null then
    if v_em is distinct from p_de then
      raise exception '%: enviar_em esperado %, veio %', p_caso,
        to_char(p_de at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS'), p_r ->> 'enviar_em';
    end if;
  elsif v_em is null or v_em < p_de or v_em >= p_ate then
    raise exception '%: enviar_em fora de [%, %): %', p_caso,
      to_char(p_de at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
      to_char(p_ate at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), p_r ->> 'enviar_em';
  end if;
  return 1;
end $f$;

-- Confere uma resposta de _retorno_modo_efetivo (contrato C-MODO: as 2 chaves). Devolve 1.
create or replace function pg_temp.retorno_f1_canal_modo(p_caso text, p_r jsonb, p_modo text, p_motivo text)
returns integer
language plpgsql as $f$
begin
  if jsonb_typeof(p_r) is distinct from 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_r) k) is distinct from array['modo', 'motivo'] then
    raise exception '%: fora do contrato C-MODO: %', p_caso, p_r;
  end if;
  if p_r ->> 'modo' is distinct from p_modo or p_r ->> 'motivo' is distinct from p_motivo then
    raise exception '%: esperado modo %, motivo %; veio %', p_caso, p_modo, coalesce(p_motivo, '(nulo)'), p_r;
  end if;
  return 1;
end $f$;

-- Confere uma resposta de retorno_saida_autorizada (contrato C-AUTORIZA: as 2 chaves). Devolve 1.
create or replace function pg_temp.retorno_f1_canal_aut(p_caso text, p_r jsonb, p_pode boolean, p_motivo text)
returns integer
language plpgsql as $f$
begin
  if jsonb_typeof(p_r) is distinct from 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_r) k) is distinct from array['motivo', 'pode'] then
    raise exception '%: fora do contrato C-AUTORIZA: %', p_caso, p_r;
  end if;
  if p_r -> 'pode' is distinct from to_jsonb(p_pode) or p_r ->> 'motivo' is distinct from p_motivo then
    raise exception '%: esperado pode = %, motivo = %; veio %', p_caso, p_pode, coalesce(p_motivo, '(nulo)'), p_r;
  end if;
  return 1;
end $f$;

-- Um caso sintético do número (com a recebida que o abre), no nível pedido; devolve o id do caso.
create or replace function pg_temp.retorno_f1_canal_caso(p_fone text, p_nivel text, p_em timestamptz,
                                                        p_papel text default 'cliente')
returns uuid
language plpgsql as $f$
declare
  v_msg uuid;
  v_caso uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', p_fone, 'text', 'Teste F1 canal: preciso de um orçamento', 'received', '{"data": {}}', p_em)
    returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, ultima_msg_id,
                                        aberta_em, gravada_em, ultima_em, ultima_gravada_em, intencao, nivel, motivo,
                                        modo, passagem_em)
    values (public._agenda_chave_telefone(p_fone), p_fone, p_papel, jsonb_build_object('papel', p_papel), v_msg, v_msg,
            p_em, p_em, p_em, p_em,
            case p_nivel when 'passagem' then 'risco' when 'nada' then 'parar' else 'pedido_servico' end,
            p_nivel, case when p_nivel = 'nada' then 'parar' end,
            'sombra', case when p_nivel = 'passagem' then p_em end)
    returning id into v_caso;
  return v_caso;
end $f$;

-- Uma saída sintética do retorno (origem e classe pela tabela da seção 6.3); devolve o id.
create or replace function pg_temp.retorno_f1_canal_saida(p_caso uuid, p_fone text, p_tipo text, p_variante text,
                                                         p_estado text, p_decidida timestamptz,
                                                         p_dados jsonb default '{}', p_modo text default 'ligado',
                                                         p_processando timestamptz default null)
returns uuid
language plpgsql as $f$
declare
  v_id uuid;
begin
  insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, modo, estado,
                                     motivo, enviar_em, processando_ate, decidida_em, enviada_em, texto, dados, dedupe_key)
    values (p_caso, p_tipo, p_variante,
            case when p_tipo in ('adiamento', 'fim_do_dia') then 'retorno_adiamento'
                 when p_tipo = 'coleta_numero_novo' then 'retorno_coleta'
                 when p_tipo in ('acorde', 'cadastro_provisorio') then null
                 else 'retorno_recibo' end,
            case when p_tipo in ('adiamento', 'fim_do_dia') then 'resposta_atrasada'
                 when p_tipo in ('acorde', 'cadastro_provisorio') then null
                 else 'resposta_imediata' end,
            public._agenda_chave_telefone(p_fone), p_fone, p_modo, p_estado,
            case when p_estado in ('recusada', 'cancelada') then 'validador' end,
            coalesce(p_decidida, '2026-12-08 09:14-03'::timestamptz), p_processando, p_decidida,
            case when p_estado = 'enviada' then p_decidida end,
            case when p_tipo not in ('acorde', 'cadastro_provisorio') then 'Teste F1 canal: texto da saída.' end,
            coalesce(p_dados, '{}'::jsonb), 'teste-f1-canal:' || gen_random_uuid()::text)
    returning id into v_id;
  return v_id;
end $f$;

-- Uma linha sintética de whatsapp_blocked_numbers (spam ou opt-out), com a hora em que foi gravada.
create or replace function pg_temp.retorno_f1_canal_bloqueia(p_fone text, p_tipo text, p_em timestamptz)
returns void
language sql as $f$
  insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo, created_at)
  values (p_fone, 'Teste F1 canal', p_tipo, p_em)
$f$;

do $canal$
declare
  c_t15 constant timestamptz := '2026-12-08 15:00-03';     -- ter 08/12, dentro das duas janelas
  c_t0915 constant timestamptz := '2026-12-08 09:15-03';   -- os casos do modo efetivo
  c_t0920 constant timestamptz := '2026-12-08 09:20-03';   -- os casos da autorização
  c_livre constant text := '5547900009501';                -- número sem cadastro, sem bloqueio
  c_imediata constant text := 'resposta_imediata';
  c_atrasada constant text := 'resposta_atrasada';
  c_todos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo',
                                   'saudacao_numero_novo', 'adiamento', 'fim_do_dia', 'parar', 'cadastro_provisorio'];
  c_grupo constant text[] := array['recibo_cliente', 'adiamento', 'fim_do_dia'];
  c_grupo_parar constant text[] := array['recibo_cliente', 'adiamento', 'fim_do_dia', 'parar'];
  v_f record;
  v_nome text;
  v_cfg_antes jsonb;
  v_dono text;
  v_r jsonb;
  v_pz_0912 jsonb;
  v_pz_2300 jsonb;
  v_pz_1600 jsonb;
  v_base_real bigint;
  v_base_sim bigint;
  v_p10 uuid;
  v_k40 uuid; v_k41 uuid; v_k42 uuid; v_k43 uuid; v_k44 uuid; v_k45 uuid; v_k46 uuid; v_k47 uuid; v_k49 uuid;
  v_s40 uuid; v_s41 uuid; v_s41b uuid; v_s41p uuid; v_s42 uuid; v_s43f uuid; v_s43p uuid; v_s43k uuid;
  v_s44f uuid; v_s44c uuid; v_s44k uuid; v_s44a uuid; v_s44u uuid; v_s45f uuid; v_s46f uuid;
  v_s47c uuid; v_s48 uuid; v_s49 uuid;
  v_k50 uuid; v_k51 uuid; v_k52 uuid;
  v_s50f uuid; v_s50a uuid; v_s50c uuid; v_s51f uuid; v_s52f uuid;
  v_k uuid;
  v_a60 uuid; v_a61 uuid; v_a62 uuid; v_a63 uuid; v_a64 uuid; v_a65 uuid; v_a66 uuid; v_a67 uuid; v_a68 uuid;
  v_a69 uuid; v_a70 uuid; v_a71 uuid; v_a72 uuid; v_a73 uuid; v_a74 uuid; v_a75 uuid; v_a76 uuid;
  v_erro_forcado jsonb;
  v_chegou boolean := false;
  v_n_canal int := 0;
  v_n_parar int := 0;
  v_n_modo int := 0;
  v_n_aut int := 0;
begin
  -- ── 0. As funções, as permissões e as premissas ──────────────────────────────────────────────────────────
  foreach v_nome in array array['public.canal_pode_enviar(text, text, text, timestamptz, boolean, text)',
                                'public.retorno_saida_autorizada(uuid, text, timestamptz)',
                                'public._retorno_modo_efetivo(uuid, text, jsonb, timestamptz)',
                                'public._retorno_parar_permitido(text, timestamptz, uuid)',
                                'public._retorno_janela(text, timestamptz, text)']
  loop
    select p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config into v_f
      from pg_proc p where p.oid = to_regprocedure(v_nome);
    if not found then
      raise exception '0: % não existe', v_nome;
    end if;
    -- Todas só leem (STABLE) e leem tabelas do retorno: SECURITY DEFINER com search_path = public.
    if v_f.provolatile <> 's' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) then
      raise exception '0a: % não é STABLE + SECURITY DEFINER com search_path = public', v_nome;
    end if;
    if has_function_privilege('anon', v_nome, 'execute') or has_function_privilege('authenticated', v_nome, 'execute') then
      raise exception '0b: % aberta a anon/authenticated', v_nome;
    end if;
  end loop;
  if not has_function_privilege('service_role', 'public.canal_pode_enviar(text, text, text, timestamptz, boolean, text)', 'execute')
     or not has_function_privilege('service_role', 'public.retorno_saida_autorizada(uuid, text, timestamptz)', 'execute') then
    raise exception '0c: canal_pode_enviar ou retorno_saida_autorizada sem execute para o service_role';
  end if;
  if to_regprocedure('public._retorno_oferece_urgente(text, text)') is null
     or to_regprocedure('public._retorno_prazo(timestamptz, text, boolean, boolean)') is null then
    raise exception '0c: faltam as funções do P3 (_retorno_oferece_urgente, _retorno_prazo)';
  end if;

  if extract(isodow from date '2026-12-08') <> 2 or extract(isodow from date '2026-12-12') <> 6
     or extract(isodow from date '2026-12-13') <> 7 or extract(isodow from date '2026-12-24') <> 4
     or public.agenda_feriado('2026-12-25') is null
     or public.agenda_feriado('2026-12-08') is not null or public.agenda_feriado('2026-12-09') is not null
     or public.agenda_feriado('2026-12-12') is not null or public.agenda_feriado('2026-12-14') is not null
     or public.agenda_feriado('2026-12-24') is not null or public.agenda_feriado('2026-12-26') is not null
     or not (public.agenda_dia_util('2026-12-07') and public.agenda_dia_util('2026-12-08')
             and public.agenda_dia_util('2026-12-09')) then
    raise exception '0d: premissa do calendário mudou (07, 08 e 09/12 úteis; 25/12 feriado; 08, 09, 12, 14, 24 e 26/12 sem feriado): confira agenda_disponibilidade antes do canal';
  end if;

  -- A faixa 55479000095xx está livre: um arranjo deixado por outro arquivo da bancada mudaria as respostas.
  if exists (select 1 from public.clients c
              where public._agenda_chave_telefone(c.whatsapp) like '000095%'
                 or public._agenda_chave_telefone(c.phone) like '000095%')
     or exists (select 1 from public.suppliers s where public._agenda_chave_telefone(s.phone) like '000095%')
     or exists (select 1 from public.payees p where public._agenda_chave_telefone(p.phone) like '000095%')
     or exists (select 1 from public.app_users u
                 where public._agenda_chave_telefone(u.phone) like '000095%'
                    or public._agenda_chave_telefone(u.phone_normalized) like '000095%')
     or exists (select 1 from public.whatsapp_blocked_numbers b
                 where public._agenda_chave_telefone(b.phone_normalized) like '000095%')
     or exists (select 1 from public.whatsapp_leads l where public._agenda_chave_telefone(l.phone_normalized) like '000095%')
     or exists (select 1 from public.retorno_saidas s where s.chave like '000095%')
     or exists (select 1 from public.retorno_aberturas a where a.chave like '000095%') then
    raise exception '0e: a faixa de teste 55479000095xx já tem cadastro, bloqueio, lead, caso ou saída';
  end if;

  -- O valor de hoje da configuração: o arranjo devolve a ele.
  select to_jsonb(c) into v_cfg_antes from public.retorno_config c where c.id;
  if not found then
    raise exception '0f: retorno_config sem a linha de configuração';
  end if;

  -- O telefone do dono (o mesmo de donoDoWhatsApp); sem ele, o 1º admin ativo com telefone: o caso 4b.
  v_dono := coalesce((select d.phone from public._comprovante_dono() d limit 1),
                     (select u.phone_normalized from public.app_users u
                       where u.active and u.phone_normalized is not null order by u.created_at limit 1));
  if v_dono is null or public._agenda_chave_telefone(v_dono) is null then
    raise exception '0g: sem telefone do dono para o caso 4b';
  end if;

  begin
    -- ── Arranjo: a configuração de nascença, para o resultado não depender do valor de produção ─────────
    update public.retorno_config set
      modo = 'sombra', tipos_ligados = '{}',
      cliente_resposta_direta_inicio = '07:00', cliente_resposta_direta_fim = '22:00',
      manha_recibo = '08:00', manha_recibo_folga = '09:00', manha_espalhar = '30 minutes',
      atrasada_inicio = '08:00', atrasada_fim = '20:00', atrasada_sabado_fim = '13:00',
      ponto_manha = '07:30', ponto_meio_dia = '12:30', ponto_fechamento = '17:30',
      promessa_manha = '10:00', promessa_meio_dia = '14:00', promessa_fechamento = '19:00',
      meio_dia_ligado = false, corte_meio_dia = '11:00', corte_tarde = '15:30',
      promessa_faixa = '{}', fora_ate = null,
      respostas_dia_max = 40, proximo_envio_em = null,
      so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null,
      segura_recibos = false, segura_tudo_ate = null
    where id;

    -- Cadastros e bloqueios sintéticos do canal (9502 equipe, 9503 "Cliente Final", 9504 spam, 9505 opt-out,
    -- 9506 pessoal).
    insert into public.payees (name, phone) values ('Teste F1 canal equipe', '(47) 90000-9502');
    insert into public.clients (type, name, phone, generico)
      values ('individual', 'Teste F1 canal Cliente Final', '5547900009503', true);
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009504', 'spam', '2026-11-30 10:00-03');
    insert into public.clients (type, name, whatsapp, opt_out_whatsapp)
      values ('individual', 'Teste F1 canal opt-out', '(47) 90000-9505', true);
    insert into public.whatsapp_leads (phone_normalized, name, lead_tipo)
      values ('5547900009506', 'Teste F1 canal pessoal', 'pessoal');
    if public.quem_escreve('5547900009502') ->> 'papel' is distinct from 'equipe'
       or public.canal_bloqueado(c_livre) is not null
       or public.canal_bloqueado('5547900009503') is distinct from 'cliente_final'
       or public.canal_bloqueado('5547900009504') is distinct from 'bloqueado'
       or public.canal_bloqueado('5547900009505') is distinct from 'opt_out'
       or public.canal_bloqueado('5547900009506') is not null then
      raise exception '0h: o arranjo não deu os bloqueios esperados (livre, equipe, cliente_final, bloqueado, opt_out, pessoal)';
    end if;

    -- ── 1. Sem configuração (ou o retorno desligado) ──────────────────────────────────────────────────────
    begin
      delete from public.retorno_config;
      v_r := public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15);
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('1a', v_r, false, 'sem_config');
    update public.retorno_config set modo = 'desligado' where id;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('1b',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), false, 'sem_config');
    update public.retorno_config set modo = 'sombra' where id;

    -- ── 2. Classe que o canal não conhece (aviso, comercial e parceiro são do pedido 7) ─────────────────────
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('2a',
      public.canal_pode_enviar(c_livre, 'aviso', 'retorno_recibo', c_t15), false, 'classe_nao_suportada');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('2b',
      public.canal_pode_enviar(c_livre, null, 'retorno_recibo', c_t15), false, 'classe_nao_suportada');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('2c',
      public.canal_pode_enviar(c_livre, 'comercial', 'retorno_recibo', c_t15), false, 'classe_nao_suportada');
    -- classe ruim e sem número: a regra 2 vem antes da 3.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('2d',
      public.canal_pode_enviar(null, 'resumo_parceiro', 'retorno_recibo', c_t15), false, 'classe_nao_suportada');

    -- ── 3. Sem os 8 dígitos ───────────────────────────────────────────────────────────────────────────────
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('3a',
      public.canal_pode_enviar(null, c_imediata, 'retorno_recibo', c_t15), false, 'sem_numero');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('3b',
      public.canal_pode_enviar('1234', c_imediata, 'retorno_recibo', c_t15), false, 'sem_numero');

    -- ── 4. Equipe: o retorno nunca fala com a equipe (payee e app_users), nem fora da janela ────────────────
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('4a',
      public.canal_pode_enviar('5547900009502', c_imediata, 'retorno_recibo', c_t15), false, 'equipe');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('4b',
      public.canal_pode_enviar(v_dono, c_imediata, 'retorno_recibo', c_t15), false, 'equipe');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('4c',
      public.canal_pode_enviar('5547900009502', c_imediata, 'retorno_recibo', '2026-12-08 23:00-03'), false, 'equipe');

    -- ── 5. Bloqueio (canal_bloqueado da F0a), para qualquer tipo que não seja o parar ───────────────────────
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('5a',
      public.canal_pode_enviar('5547900009503', c_imediata, 'retorno_recibo', c_t15), false, 'cliente_final');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('5b',
      public.canal_pode_enviar('5547900009504', c_imediata, 'retorno_recibo', c_t15, false, 'recibo_cliente'), false, 'bloqueado');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('5c',
      public.canal_pode_enviar('(47) 90000-9505', c_atrasada, 'retorno_adiamento', c_t15), false, 'opt_out');

    -- ── 6. Número pessoal ─────────────────────────────────────────────────────────────────────────────────
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('6',
      public.canal_pode_enviar('5547900009506', c_imediata, 'retorno_recibo', c_t15), false, 'pessoal');

    -- ── 7. "Segura tudo" até amanhã; vencido, não segura ──────────────────────────────────────────────────
    update public.retorno_config set segura_tudo_ate = c_t15 + interval '1 day' where id;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('7a',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), false, 'segura_tudo');
    -- pessoal vem antes (6 antes de 7); a janela vem depois (7 antes de 9).
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('7b',
      public.canal_pode_enviar('5547900009506', c_imediata, 'retorno_recibo', c_t15), false, 'pessoal');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('7c',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-08 23:00-03'), false, 'segura_tudo');
    update public.retorno_config set segura_tudo_ate = c_t15 - interval '1 minute' where id;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('7d',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), true, null);
    update public.retorno_config set segura_tudo_ate = null where id;

    -- ── 8. Disjuntor so_reativo: só a resposta imediata sai ───────────────────────────────────────────────
    update public.retorno_config set so_reativo = true, so_reativo_motivo = 'conexao',
                                     so_reativo_desde = c_t15 - interval '30 minutes' where id;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('8a',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', c_t15), false, 'so_reativo');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('8b',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), true, null);
    update public.retorno_config set so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null where id;

    -- ── 9. Janelas ────────────────────────────────────────────────────────────────────────────────────────
    -- Resposta imediata (K3), todo dia 07:00–21:59: ter 21:59 pode; 22:00 espera qua 08:00–08:30.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9a',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-08 21:59-03'), true, null);
    v_r := public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-08 22:00-03');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9b', v_r, false, 'fora_da_janela',
      '2026-12-09 08:00-03', '2026-12-09 08:30-03');
    -- a manhã é exatamente a de _retorno_proxima_manha (estável por número e dia).
    if (v_r ->> 'enviar_em')::timestamptz is distinct from public._retorno_proxima_manha('2026-12-08 22:00-03', '00009501') then
      raise exception '9b: enviar_em não é o de _retorno_proxima_manha: %', v_r;
    end if;
    -- sáb 22:00 → domingo 09:00–09:30.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9c',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-12 22:00-03'), false, 'fora_da_janela',
      '2026-12-13 09:00-03', '2026-12-13 09:30-03');
    -- domingo e feriado também respondem na janela.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9d',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-13 10:00-03'), true, null);
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9e',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-25 10:00-03'), true, null);
    -- 06:59 espera a manhã do mesmo dia; 07:00 abre.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9f',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-08 06:59-03'), false, 'fora_da_janela',
      '2026-12-08 08:00-03', '2026-12-08 08:30-03');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9g',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', '2026-12-08 07:00-03'), true, null);
    -- Resposta atrasada: sáb 12:59 pode; 13:00 não (seg 14/12 08:00); domingo nunca.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9h',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-12 12:59-03'), true, null);
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9i',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-12 13:00-03'), false, 'fora_da_janela',
      '2026-12-14 08:00-03');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9j',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-13 10:00-03'), false, 'fora_da_janela',
      '2026-12-14 08:00-03');
    -- seg–sex 08:00–19:59: 07:59 espera as 08:00 do mesmo dia; 08:00 e 19:59 podem; 20:00 espera o dia seguinte.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9k',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-08 07:59-03'), false, 'fora_da_janela',
      '2026-12-08 08:00-03');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9l',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-08 08:00-03'), true, null);
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9m',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-08 19:59-03'), true, null);
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9n',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-08 20:00-03'), false, 'fora_da_janela',
      '2026-12-09 08:00-03');
    -- nunca feriado: Natal (sex 25/12) e a véspera depois das 20:00 esperam sáb 26/12 08:00.
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9o',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-25 10:00-03'), false, 'fora_da_janela',
      '2026-12-26 08:00-03');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('9p',
      public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', '2026-12-24 20:00-03'), false, 'fora_da_janela',
      '2026-12-26 08:00-03');
    -- A janela de uma classe desconhecida: fora, sem abertura.
    if public._retorno_janela('aviso', c_t15, '00009501') is distinct from '{"dentro": false, "enviar_em": null}'::jsonb
       or public._retorno_janela(c_imediata, c_t15, '00009501') is distinct from '{"dentro": true, "enviar_em": null}'::jsonb then
      raise exception '9q: _retorno_janela fora da especificação';
    end if;

    -- ── 10. Teto da HBR: 40 respostas decididas hoje ──────────────────────────────────────────────────────
    -- 10a–10c: enviadas. As saídas que já houver no dia contam: o caso completa até 39 e depois até 40.
    begin
      select count(*) into v_base_real
        from public.retorno_saidas s
       where s.classe in ('resposta_imediata', 'resposta_atrasada')
         and s.decidida_em >= '2026-12-08 00:00-03' and s.decidida_em <= c_t15
         and s.estado in ('enviada', 'incerta', 'enviando');
      if v_base_real > 39 then
        raise exception '10: premissa: já há % respostas decididas em 08/12 (o caso precisa de no máximo 39)', v_base_real;
      end if;
      insert into public.retorno_saidas (tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em,
                                         decidida_em, enviada_em, texto, dedupe_key)
      select 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '00009530', '5547900009530', 'ligado', 'enviada',
             '2026-12-08 08:00-03'::timestamptz + make_interval(mins => g),
             '2026-12-08 08:00-03'::timestamptz + make_interval(mins => g),
             '2026-12-08 08:00-03'::timestamptz + make_interval(mins => g),
             'Teste F1 canal: teto.', 'teste-f1-canal:teto:' || g
        from generate_series(1, 39 - v_base_real::int) g;
      -- Linhas que não contam: 5 decididas depois de agora (o futuro) e 5 de ontem.
      insert into public.retorno_saidas (tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em,
                                         decidida_em, enviada_em, texto, dedupe_key)
      select 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '00009530', '5547900009530', 'ligado', 'enviada',
             x.em, x.em, x.em, 'Teste F1 canal: teto.', 'teste-f1-canal:teto-fora:' || x.n
        from (select g as n, case when g <= 5 then c_t15 + make_interval(mins => g)
                                  else '2026-12-07 23:40-03'::timestamptz + make_interval(mins => g) end as em
                from generate_series(1, 10) g) x;
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10a',
        public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), true, null);
      -- a 40ª (um adiamento: as duas classes de resposta contam juntas).
      insert into public.retorno_saidas (tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em,
                                         decidida_em, enviada_em, texto, dedupe_key)
        values ('adiamento', 'retorno_adiamento', 'resposta_atrasada', '00009531', '5547900009531', 'ligado', 'enviada',
                c_t15 - interval '1 minute', c_t15 - interval '1 minute', c_t15 - interval '1 minute',
                'Teste F1 canal: teto.', 'teste-f1-canal:teto:40');
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10b',
        public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), false, 'teto_dia');
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10c',
        public.canal_pode_enviar(c_livre, c_atrasada, 'retorno_adiamento', c_t15, true), false, 'teto_dia');
      -- a 40ª incerta ou enviando também conta; recusada não.
      update public.retorno_saidas set estado = 'incerta', enviada_em = null where dedupe_key = 'teste-f1-canal:teto:40';
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10c2',
        public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), false, 'teto_dia');
      update public.retorno_saidas set estado = 'enviando' where dedupe_key = 'teste-f1-canal:teto:40';
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10c3',
        public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), false, 'teto_dia');
      update public.retorno_saidas set estado = 'recusada', motivo = 'provedor' where dedupe_key = 'teste-f1-canal:teto:40';
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10c4',
        public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), true, null);
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    -- 10d–10e: 40 em sombra (e preparada) só contam simulando.
    begin
      select count(*) filter (where s.estado in ('enviada', 'incerta', 'enviando')),
             count(*) filter (where s.estado in ('enviada', 'incerta', 'enviando', 'sombra', 'preparada'))
        into v_base_real, v_base_sim
        from public.retorno_saidas s
       where s.classe in ('resposta_imediata', 'resposta_atrasada')
         and s.decidida_em >= '2026-12-08 00:00-03' and s.decidida_em <= c_t15;
      if v_base_sim > 39 or v_base_real > 39 then
        raise exception '10: premissa: já há % respostas (% reais) decididas em 08/12', v_base_sim, v_base_real;
      end if;
      insert into public.retorno_saidas (tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em,
                                         decidida_em, texto, dedupe_key)
      select 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '00009530', '5547900009530', 'sombra',
             case when g = 1 then 'preparada' else 'sombra' end,
             '2026-12-08 08:00-03'::timestamptz + make_interval(mins => g),
             '2026-12-08 08:00-03'::timestamptz + make_interval(mins => g),
             'Teste F1 canal: teto.', 'teste-f1-canal:teto-sombra:' || g
        from generate_series(1, 40 - v_base_sim::int) g;
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10d',
        public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15, true), false, 'teto_dia');
      v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10e',
        public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15, false), true, null);
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    -- 10f: teto zero não deixa nada sair.
    update public.retorno_config set respostas_dia_max = 0 where id;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('10f',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), false, 'teto_dia');
    update public.retorno_config set respostas_dia_max = 40 where id;

    -- ── 11. Espaçamento global (proximo_envio_em); a simulação não espera ─────────────────────────────────
    update public.retorno_config set proximo_envio_em = c_t15 + interval '45 seconds' where id;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('11a',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), false, 'espacamento',
      c_t15 + interval '45 seconds');
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('11b',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15, true), true, null);
    update public.retorno_config set proximo_envio_em = c_t15 - interval '1 second' where id;
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('11c',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), true, null);
    update public.retorno_config set proximo_envio_em = null where id;

    -- ── 12. Tudo certo: pode; e os parâmetros pelo nome (o contrato C-CANAL) e pelos padrões ────────────────
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('12a',
      public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo', c_t15), true, null);
    v_n_canal := v_n_canal + pg_temp.retorno_f1_canal_confere('12b',
      public.canal_pode_enviar(p_fone => c_livre, p_classe => c_atrasada, p_origem => 'retorno_adiamento',
                               p_agora => c_t15, p_simular => false, p_tipo => 'fim_do_dia'), true, null);
    v_r := public.canal_pode_enviar(c_livre, c_imediata, 'retorno_recibo');      -- agora = now(): só o formato
    if jsonb_typeof(v_r) is distinct from 'object' or jsonb_typeof(v_r -> 'pode') is distinct from 'boolean' then
      raise exception '12c: com os padrões, fora do contrato C-CANAL: %', v_r;
    end if;

    -- ── P. A confirmação do PARAR (p_tipo 'parar'): a única exceção ao bloqueio ───────────────────────────
    -- P1. opt-out gravado há 5 min: a confirmação sai; o mesmo número em outro tipo continua bloqueado.
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009507', 'opt_out', c_t15 - interval '5 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P1a',
      public.canal_pode_enviar('5547900009507', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), true, null);
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P1b',
      public.canal_pode_enviar('5547900009507', c_imediata, 'retorno_recibo', c_t15, false, 'recibo_cliente'), false, 'bloqueado');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P1c',
      public.canal_pode_enviar('5547900009507', c_imediata, 'retorno_recibo', c_t15), false, 'bloqueado');
    -- P2. há 20 min: passou dos 15, não confirma. P3. exatamente 15 min: ainda confirma ("no máximo 15 min").
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009508', 'opt_out', c_t15 - interval '20 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P2',
      public.canal_pode_enviar('5547900009508', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), false, 'bloqueado');
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009515', 'opt_out', c_t15 - interval '15 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P3',
      public.canal_pode_enviar('5547900009515', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), true, null);
    -- P4. opt-out recente, mas a chave também está na lista de spam (outra grafia do mesmo número).
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009509', 'opt_out', c_t15 - interval '5 minutes');
    perform pg_temp.retorno_f1_canal_bloqueia('4700009509', 'spam', '2026-11-30 10:00-03');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P4',
      public.canal_pode_enviar('5547900009509', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), false, 'bloqueado');
    -- P5. parar repetido: já houve uma confirmação enviada à chave; com p_exceto = ela, a própria não conta.
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009510', 'opt_out', c_t15 - interval '5 minutes');
    v_p10 := pg_temp.retorno_f1_canal_saida(null, '5547900009510', 'parar', 'sem_nome', 'enviada', c_t15 - interval '10 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P5a',
      public.canal_pode_enviar('5547900009510', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), false, 'bloqueado');
    if public._retorno_parar_permitido('00009510', c_t15) or not public._retorno_parar_permitido('00009510', c_t15, v_p10) then
      raise exception 'P5b: p_exceto não tirou a própria saída da conta';
    end if;
    -- P6. opt-out gravado DEPOIS de agora (linha do futuro): não confirma.
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009511', 'opt_out', c_t15 + interval '5 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P6',
      public.canal_pode_enviar('5547900009511', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), false, 'bloqueado');
    -- P7. a confirmação anterior foi decidida DEPOIS de agora (linha do futuro): não conta.
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009512', 'opt_out', c_t15 - interval '5 minutes');
    perform pg_temp.retorno_f1_canal_saida(null, '5547900009512', 'parar', 'sem_nome', 'enviada', c_t15 + interval '1 minute');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P7',
      public.canal_pode_enviar('5547900009512', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), true, null);
    -- P8. o "Cliente Final" nunca recebe, nem a confirmação.
    insert into public.clients (type, name, whatsapp, generico)
      values ('individual', 'Teste F1 canal Cliente Final do PARAR', '(47) 90000-9513', true);
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009513', 'opt_out', c_t15 - interval '5 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P8',
      public.canal_pode_enviar('5547900009513', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), false, 'cliente_final');
    -- P9. sem o opt-out gravado, "não te mando mais" seria mentira: não sai (falha fecha).
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P9',
      public.canal_pode_enviar('5547900009514', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), false, 'canal');
    -- P10. uma confirmação anterior recusada não conta (só sombra, enviando, enviada e incerta).
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009516', 'opt_out', c_t15 - interval '5 minutes');
    perform pg_temp.retorno_f1_canal_saida(null, '5547900009516', 'parar', 'sem_nome', 'recusada', c_t15 - interval '10 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P10',
      public.canal_pode_enviar('5547900009516', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), true, null);
    -- P11. opt-out recente de quem também tem opt_out_whatsapp no cadastro: confirma.
    insert into public.clients (type, name, whatsapp, opt_out_whatsapp)
      values ('individual', 'Teste F1 canal opt-out do PARAR', '(47) 90000-9517', true);
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009517', 'opt_out', c_t15 - interval '5 minutes');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P11',
      public.canal_pode_enviar('5547900009517', c_imediata, 'retorno_recibo', c_t15, false, 'parar'), true, null);
    -- P12. PARAR às 22:25: a confirmação espera a manhã, e às 08:00 os 15 min já passaram (manda menos).
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009518', 'opt_out', '2026-12-08 22:25-03');
    v_r := public.canal_pode_enviar('5547900009518', c_imediata, 'retorno_recibo', '2026-12-08 22:30-03', false, 'parar');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P12a', v_r, false, 'fora_da_janela',
      '2026-12-09 08:00-03', '2026-12-09 08:30-03');
    v_n_parar := v_n_parar + pg_temp.retorno_f1_canal_confere('P12b',
      public.canal_pode_enviar('5547900009518', c_imediata, 'retorno_recibo', (v_r ->> 'enviar_em')::timestamptz, false, 'parar'),
      false, 'bloqueado');
    -- P13. chave ou hora nulas: falso.
    if public._retorno_parar_permitido(null, c_t15) or public._retorno_parar_permitido('00009507', null)
       or public._retorno_parar_permitido('9507', c_t15) then
      raise exception 'P13: chave ou hora nulas (ou chave curta) permitiram a confirmação';
    end if;

    -- ── M. _retorno_modo_efetivo (p_agora = ter 08/12 09:15) ──────────────────────────────────────────────
    -- Os prazos de verdade (P3): 09:12 → hoje 19h, sem X2; 23:00 de ontem → hoje 10h, X2 = 19h; 16:00 → amanhã 10h.
    v_pz_0912 := public._retorno_prazo('2026-12-08 09:12-03', '00009540');
    v_pz_2300 := public._retorno_prazo('2026-12-07 23:00-03', '00009542');
    v_pz_1600 := public._retorno_prazo('2026-12-08 16:00-03', '00009549');
    if v_pz_0912 ->> 'faixa' is distinct from 'manha_cedo' or v_pz_0912 ->> 'x2' is not null
       or (v_pz_0912 ->> 'prometido_ate')::timestamptz is distinct from '2026-12-08 19:00-03'::timestamptz
       or v_pz_2300 ->> 'faixa' is distinct from 'noite'
       or (v_pz_2300 ->> 'prometido_ate')::timestamptz is distinct from '2026-12-08 10:00-03'::timestamptz
       or (v_pz_2300 ->> 'x2')::timestamptz is distinct from '2026-12-08 19:00-03'::timestamptz
       or (v_pz_1600 -> 'outro_dia') is distinct from 'true'::jsonb then
      raise exception 'M0: premissa: os prazos do P3 mudaram (09:12 → 19h sem X2; 23:00 → 10h com X2 19h; 16:00 → outro dia): % % %',
        v_pz_0912, v_pz_2300, v_pz_1600;
    end if;

    -- Os casos e as saídas (as agendadas nascem em sombra, como no retorno_abrir).
    v_k40 := pg_temp.retorno_f1_canal_caso('5547900009540', 'recibo', '2026-12-08 09:12-03');
    v_s40 := pg_temp.retorno_f1_canal_saida(v_k40, '5547900009540', 'recibo_cliente', 'padrao', 'agendada', null,
                                            jsonb_build_object('prazo', v_pz_0912), 'sombra');
    v_k41 := pg_temp.retorno_f1_canal_caso('5547900009541', 'passagem', '2026-12-08 09:12-03');   -- caso com risco
    v_s41 := pg_temp.retorno_f1_canal_saida(v_k41, '5547900009541', 'recibo_cliente', 'padrao', 'agendada', null,
                                            jsonb_build_object('prazo', v_pz_0912), 'sombra');
    v_s41b := pg_temp.retorno_f1_canal_saida(v_k41, '5547900009541', 'saudacao_numero_novo', 'padrao', 'agendada', null,
                                             '{}', 'sombra');
    v_s41p := pg_temp.retorno_f1_canal_saida(v_k41, '5547900009541', 'parar', 'sem_nome', 'agendada', null, '{}', 'sombra');
    v_k42 := pg_temp.retorno_f1_canal_caso('5547900009542', 'recibo', '2026-12-07 23:00-03');
    v_s42 := pg_temp.retorno_f1_canal_saida(v_k42, '5547900009542', 'recibo_cliente', 'manha', 'agendada', null,
                                            jsonb_build_object('prazo', v_pz_2300), 'sombra');
    -- k43: o recibo foi sombra.
    v_k43 := pg_temp.retorno_f1_canal_caso('5547900009543', 'recibo', '2026-12-08 09:10-03');
    perform pg_temp.retorno_f1_canal_saida(v_k43, '5547900009543', 'recibo_cliente', 'padrao', 'sombra',
                                           '2026-12-08 09:14-03', jsonb_build_object('prazo', v_pz_0912), 'sombra');
    v_s43f := pg_temp.retorno_f1_canal_saida(v_k43, '5547900009543', 'fim_do_dia', 'com_nome', 'agendada', null, '{}', 'sombra');
    v_s43p := pg_temp.retorno_f1_canal_saida(v_k43, '5547900009543', 'parar', 'com_nome', 'agendada', null, '{}', 'sombra');
    v_s43k := pg_temp.retorno_f1_canal_saida(v_k43, '5547900009543', 'cadastro_provisorio', null, 'agendada', null, '{}', 'sombra');
    -- k44: o recibo foi enviado (o cliente ouviu).
    v_k44 := pg_temp.retorno_f1_canal_caso('5547900009544', 'recibo', '2026-12-08 09:10-03');
    perform pg_temp.retorno_f1_canal_saida(v_k44, '5547900009544', 'recibo_cliente', 'padrao', 'enviada',
                                           '2026-12-08 09:14-03', jsonb_build_object('prazo', v_pz_0912));
    v_s44f := pg_temp.retorno_f1_canal_saida(v_k44, '5547900009544', 'fim_do_dia', 'com_nome', 'agendada', null, '{}', 'sombra');
    v_s44c := pg_temp.retorno_f1_canal_saida(v_k44, '5547900009544', 'coleta_numero_novo', 'nome', 'agendada', null, '{}', 'sombra');
    v_s44k := pg_temp.retorno_f1_canal_saida(v_k44, '5547900009544', 'cadastro_provisorio', null, 'agendada', null, '{}', 'sombra');
    v_s44a := pg_temp.retorno_f1_canal_saida(v_k44, '5547900009544', 'adiamento', 'com_nome', 'agendada', null, '{}', 'sombra');
    v_s44u := pg_temp.retorno_f1_canal_saida(v_k44, '5547900009544', 'urgente', 'sem_acorde', 'agendada', null, '{}', 'sombra');
    -- k45: o recibo "enviado" foi decidido às 09:20, depois de agora (linha do futuro).
    v_k45 := pg_temp.retorno_f1_canal_caso('5547900009545', 'recibo', '2026-12-08 09:10-03');
    perform pg_temp.retorno_f1_canal_saida(v_k45, '5547900009545', 'recibo_cliente', 'padrao', 'enviada',
                                           '2026-12-08 09:20-03', jsonb_build_object('prazo', v_pz_0912));
    v_s45f := pg_temp.retorno_f1_canal_saida(v_k45, '5547900009545', 'fim_do_dia', 'com_nome', 'agendada', null, '{}', 'sombra');
    -- k46: o recibo ficou incerto (pode ter saído: o aviso honesto vale).
    v_k46 := pg_temp.retorno_f1_canal_caso('5547900009546', 'recibo', '2026-12-08 09:10-03');
    perform pg_temp.retorno_f1_canal_saida(v_k46, '5547900009546', 'recibo_cliente', 'padrao', 'incerta',
                                           '2026-12-08 09:14-03', jsonb_build_object('prazo', v_pz_0912));
    v_s46f := pg_temp.retorno_f1_canal_saida(v_k46, '5547900009546', 'fim_do_dia', 'sem_nome', 'agendada', null, '{}', 'sombra');
    -- k47: número novo; a saudação foi enviada.
    v_k47 := pg_temp.retorno_f1_canal_caso('5547900009547', 'recibo', '2026-12-08 09:00-03', 'numero_novo');
    perform pg_temp.retorno_f1_canal_saida(v_k47, '5547900009547', 'saudacao_numero_novo', 'padrao', 'enviada',
                                           '2026-12-08 09:10-03');
    v_s47c := pg_temp.retorno_f1_canal_saida(v_k47, '5547900009547', 'coleta_numero_novo', 'nome', 'agendada', null, '{}', 'sombra');
    -- s48: saída sem caso.
    v_s48 := pg_temp.retorno_f1_canal_saida(null, '5547900009548', 'recibo_cliente', 'padrao', 'agendada', null,
                                            jsonb_build_object('prazo', v_pz_0912), 'sombra');
    -- k49: recibo das 16:00 (outro dia, oferece URGENTE).
    v_k49 := pg_temp.retorno_f1_canal_caso('5547900009549', 'recibo', '2026-12-08 16:00-03');
    v_s49 := pg_temp.retorno_f1_canal_saida(v_k49, '5547900009549', 'recibo_cliente', 'outro_dia', 'agendada', null,
                                            jsonb_build_object('prazo', v_pz_1600), 'sombra');
    -- k50: o caso virou passagem DEPOIS do recibo enviado às 09:14 (o cliente insistiu, ou reclamou).
    v_k50 := pg_temp.retorno_f1_canal_caso('5547900009550', 'passagem', '2026-12-08 09:10-03');
    perform pg_temp.retorno_f1_canal_saida(v_k50, '5547900009550', 'recibo_cliente', 'padrao', 'enviada',
                                           '2026-12-08 09:14-03', jsonb_build_object('prazo', v_pz_0912));
    v_s50f := pg_temp.retorno_f1_canal_saida(v_k50, '5547900009550', 'fim_do_dia', 'com_nome', 'agendada', null, '{}', 'sombra');
    v_s50a := pg_temp.retorno_f1_canal_saida(v_k50, '5547900009550', 'adiamento', 'com_nome', 'agendada', null, '{}', 'sombra');
    v_s50c := pg_temp.retorno_f1_canal_saida(v_k50, '5547900009550', 'coleta_numero_novo', 'nome', 'agendada', null, '{}', 'sombra');
    -- k51: número novo em passagem que só ouviu a saudação (sem hora prometida); o recibo ficou em sombra.
    v_k51 := pg_temp.retorno_f1_canal_caso('5547900009551', 'passagem', '2026-12-08 09:00-03', 'numero_novo');
    perform pg_temp.retorno_f1_canal_saida(v_k51, '5547900009551', 'saudacao_numero_novo', 'padrao', 'enviada',
                                           '2026-12-08 09:10-03');
    perform pg_temp.retorno_f1_canal_saida(v_k51, '5547900009551', 'recibo_numero_novo', 'padrao', 'sombra',
                                           '2026-12-08 09:14-03', jsonb_build_object('prazo', v_pz_0912), 'sombra');
    v_s51f := pg_temp.retorno_f1_canal_saida(v_k51, '5547900009551', 'fim_do_dia', 'com_nome', 'agendada', null, '{}', 'sombra');
    -- k52: em passagem, o recibo "enviado" foi decidido às 09:20, depois de agora (linha do futuro).
    v_k52 := pg_temp.retorno_f1_canal_caso('5547900009552', 'passagem', '2026-12-08 09:10-03');
    perform pg_temp.retorno_f1_canal_saida(v_k52, '5547900009552', 'recibo_cliente', 'padrao', 'enviada',
                                           '2026-12-08 09:20-03', jsonb_build_object('prazo', v_pz_0912));
    v_s52f := pg_temp.retorno_f1_canal_saida(v_k52, '5547900009552', 'fim_do_dia', 'com_nome', 'agendada', null, '{}', 'sombra');

    -- Ligado, com todos os tipos que o check aceita (urgente e acorde ficam fora).
    update public.retorno_config set modo = 'ligado', tipos_ligados = c_todos where id;

    -- M1. O modo geral: sombra, desligado ou sem a linha → sombra/modo.
    update public.retorno_config set modo = 'sombra' where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M1a',
      public._retorno_modo_efetivo(v_s40, 'padrao', v_pz_0912, c_t0915), 'sombra', 'modo');
    update public.retorno_config set modo = 'desligado' where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M1b',
      public._retorno_modo_efetivo(v_s43p, 'com_nome', null, c_t0915), 'sombra', 'modo');
    update public.retorno_config set modo = 'ligado' where id;
    begin
      delete from public.retorno_config;
      v_r := public._retorno_modo_efetivo(v_s40, 'padrao', v_pz_0912, c_t0915);
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M1c', v_r, 'sombra', 'modo');

    -- M2. "Segura tudo" até amanhã: sombra, inclusive o parar.
    update public.retorno_config set segura_tudo_ate = c_t0915 + interval '1 day' where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M2a',
      public._retorno_modo_efetivo(v_s40, 'padrao', v_pz_0912, c_t0915), 'sombra', 'segura_tudo');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M2b',
      public._retorno_modo_efetivo(v_s43p, 'com_nome', null, c_t0915), 'sombra', 'segura_tudo');
    update public.retorno_config set segura_tudo_ate = null where id;

    -- M3. O tipo fora de tipos_ligados (o urgente nunca está na lista).
    update public.retorno_config set tipos_ligados = '{adiamento,fim_do_dia}' where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M3a',
      public._retorno_modo_efetivo(v_s40, 'padrao', v_pz_0912, c_t0915), 'sombra', 'tipo_desligado');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M3b',
      public._retorno_modo_efetivo(v_s43p, 'com_nome', null, c_t0915), 'sombra', 'tipo_desligado');
    update public.retorno_config set tipos_ligados = c_todos where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M3c',
      public._retorno_modo_efetivo(v_s44u, 'sem_acorde', null, c_t0915), 'sombra', 'tipo_desligado');

    -- M4. O modelo oferece URGENTE (outro_dia; o adiamento com_nome), e o URGENTE não liga. Sem a variante, na
    --     dúvida, também.
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M4a',
      public._retorno_modo_efetivo(v_s49, 'outro_dia', v_pz_1600, c_t0915), 'sombra', 'urgente_desligado');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M4b',
      public._retorno_modo_efetivo(v_s44a, 'com_nome', null, c_t0915), 'sombra', 'urgente_desligado');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M4c',
      public._retorno_modo_efetivo(v_s40, null, v_pz_0912, c_t0915), 'sombra', 'urgente_desligado');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M4d',
      public._retorno_modo_efetivo(v_s44a, null, null, c_t0915), 'sombra', 'urgente_desligado');

    -- M5. "Segura recibos": recibo, saudação e coleta; o parar e o fim do dia não.
    update public.retorno_config set segura_recibos = true where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M5a',
      public._retorno_modo_efetivo(v_s40, 'padrao', v_pz_0912, c_t0915), 'sombra', 'segura_recibos');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M5b',
      public._retorno_modo_efetivo(v_s41b, 'padrao', null, c_t0915), 'sombra', 'segura_recibos');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M5c',
      public._retorno_modo_efetivo(v_s44c, 'nome', null, c_t0915), 'sombra', 'segura_recibos');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M5d',
      public._retorno_modo_efetivo(v_s43p, 'com_nome', null, c_t0915), 'ligado', null);
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M5e',
      public._retorno_modo_efetivo(v_s44f, 'com_nome', null, c_t0915), 'ligado', null);
    update public.retorno_config set segura_recibos = false where id;

    -- M6. Caso com risco (passagem) sem o acorde real: o recibo e a saudação ficam em sombra.
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M6a',
      public._retorno_modo_efetivo(v_s41, 'padrao', v_pz_0912, c_t0915), 'sombra', 'passagem_sem_acorde');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M6b',
      public._retorno_modo_efetivo(v_s41b, 'padrao', null, c_t0915), 'sombra', 'passagem_sem_acorde');
    -- M6c. O caso que virou passagem DEPOIS do recibo ouvido: o fim do dia dele liga. Senão, quem ouviu "até as
    --      19h" e insistiu ficaria sem nada às 19h (§3: ninguém ouve a promessa sem o aviso).
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M6c',
      public._retorno_modo_efetivo(v_s50f, 'com_nome', null, c_t0915), 'ligado', null);
    -- M6d–M6e. Só o aviso honesto escapa: o adiamento continua preso pelo URGENTE (regra 4, antes), e a coleta,
    --          pela passagem.
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M6d',
      public._retorno_modo_efetivo(v_s50a, 'com_nome', null, c_t0915), 'sombra', 'urgente_desligado');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M6e',
      public._retorno_modo_efetivo(v_s50c, 'nome', null, c_t0915), 'sombra', 'passagem_sem_acorde');
    -- M6f–M6g. Sem o recibo ouvido até agora, o fim do dia da passagem continua preso: a saudação enviada não
    --          prometeu hora; o recibo "enviado" decidido depois de agora não conta (linha do futuro).
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M6f',
      public._retorno_modo_efetivo(v_s51f, 'com_nome', null, c_t0915), 'sombra', 'passagem_sem_acorde');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M6g',
      public._retorno_modo_efetivo(v_s52f, 'com_nome', null, c_t0915), 'sombra', 'passagem_sem_acorde');

    -- M7. Recibo das 23:00 (prometido 10h, X2 = 19h): o adiamento que viria oferece URGENTE → o caso não liga.
    --     Sem o prazo gravado (ou sem a chave x2) não dá para saber: sombra também.
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M7a',
      public._retorno_modo_efetivo(v_s42, 'manha', v_pz_2300, c_t0915), 'sombra', 'caso_sem_aviso');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M7b',
      public._retorno_modo_efetivo(v_s40, 'padrao', null, c_t0915), 'sombra', 'caso_sem_aviso');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M7c',
      public._retorno_modo_efetivo(v_s40, 'padrao', '{}', c_t0915), 'sombra', 'caso_sem_aviso');

    -- M8. O aviso só liga se o recibo (ou a saudação) do caso foi enviado ou ficou incerto, até agora.
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8a',
      public._retorno_modo_efetivo(v_s43f, 'com_nome', null, c_t0915), 'sombra', 'caso_em_sombra');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8b',
      public._retorno_modo_efetivo(v_s45f, 'com_nome', null, c_t0915), 'sombra', 'caso_em_sombra');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8c',
      public._retorno_modo_efetivo(v_s45f, 'com_nome', null, '2026-12-08 09:25-03'), 'ligado', null);
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8d',
      public._retorno_modo_efetivo(v_s43k, null, null, c_t0915), 'sombra', 'caso_em_sombra');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8e',
      public._retorno_modo_efetivo(v_s44f, 'com_nome', null, c_t0915), 'ligado', null);
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8f',
      public._retorno_modo_efetivo(v_s46f, 'sem_nome', null, c_t0915), 'ligado', null);
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8g',
      public._retorno_modo_efetivo(v_s44c, 'nome', null, c_t0915), 'ligado', null);
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8h',
      public._retorno_modo_efetivo(v_s44k, null, null, c_t0915), 'ligado', null);
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M8i',
      public._retorno_modo_efetivo(v_s47c, 'nome', null, c_t0915), 'ligado', null);

    -- M9. Recibo das 09:12 com o grupo ligado (recibo_cliente, adiamento, fim_do_dia): liga.
    update public.retorno_config set tipos_ligados = c_grupo where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M9',
      public._retorno_modo_efetivo(v_s40, 'padrao', v_pz_0912, c_t0915), 'ligado', null);

    -- M10. O parar não depende do recibo: com o recibo do caso em sombra, liga.
    update public.retorno_config set tipos_ligados = c_grupo_parar where id;
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M10a',
      public._retorno_modo_efetivo(v_s43p, 'com_nome', null, c_t0915), 'ligado', null);
    -- e só passa pelas regras 1–3: nem a passagem sem acorde o segura.
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M10b',
      public._retorno_modo_efetivo(v_s41p, 'sem_nome', null, c_t0915), 'ligado', null);

    -- M11. Na dúvida, sombra: saída que não existe; saída sem caso.
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M11a',
      public._retorno_modo_efetivo(gen_random_uuid(), 'padrao', v_pz_0912, c_t0915), 'sombra', 'sem_saida');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M11b',
      public._retorno_modo_efetivo(null, 'padrao', v_pz_0912, c_t0915), 'sombra', 'sem_saida');
    v_n_modo := v_n_modo + pg_temp.retorno_f1_canal_modo('M11c',
      public._retorno_modo_efetivo(v_s48, 'padrao', v_pz_0912, c_t0915), 'sombra', 'sem_caso');

    -- ── A. retorno_saida_autorizada (p_agora = ter 08/12 09:20; o grupo e o parar ligados) ─────────────────
    -- Cada saída enviando foi reservada às 09:19:50 até 09:22 (processando_ate), como faz o retorno_pegar.
    v_k := pg_temp.retorno_f1_canal_caso('5547900009560', 'recibo', '2026-12-08 09:12-03');
    v_a60 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009560', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 09:19:50-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 09:22-03');
    v_k := pg_temp.retorno_f1_canal_caso('5547900009561', 'recibo', '2026-12-08 09:12-03');
    v_a61 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009561', 'recibo_cliente', 'padrao', 'preparada',
                                            '2026-12-08 09:19:50-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 09:22-03');
    v_k := pg_temp.retorno_f1_canal_caso('5547900009562', 'recibo', '2026-12-08 09:12-03');
    v_a62 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009562', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 09:17-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 09:19-03');
    v_k := pg_temp.retorno_f1_canal_caso('5547900009563', 'recibo', '2026-12-08 09:12-03');
    v_a63 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009563', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 09:19:50-03', jsonb_build_object('prazo', v_pz_0912), 'sombra',
                                            '2026-12-08 09:22-03');
    -- os PARAR: dentro dos 15 min (9564), fora (9565) e repetido (9566).
    v_k := pg_temp.retorno_f1_canal_caso('5547900009564', 'nada', '2026-12-08 09:15-03');
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009564', 'opt_out', '2026-12-08 09:15-03');
    v_a64 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009564', 'parar', 'com_nome', 'enviando',
                                            '2026-12-08 09:19:50-03', '{}', 'ligado', '2026-12-08 09:22-03');
    v_k := pg_temp.retorno_f1_canal_caso('5547900009565', 'nada', '2026-12-08 09:00-03');
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009565', 'opt_out', '2026-12-08 09:00-03');
    v_a65 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009565', 'parar', 'com_nome', 'enviando',
                                            '2026-12-08 09:19:50-03', '{}', 'ligado', '2026-12-08 09:22-03');
    v_k := pg_temp.retorno_f1_canal_caso('5547900009566', 'nada', '2026-12-08 09:15-03');
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009566', 'opt_out', '2026-12-08 09:15-03');
    perform pg_temp.retorno_f1_canal_saida(null, '5547900009566', 'parar', 'com_nome', 'enviada', '2026-12-07 10:00-03');
    v_a66 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009566', 'parar', 'com_nome', 'enviando',
                                            '2026-12-08 09:19:50-03', '{}', 'ligado', '2026-12-08 09:22-03');
    -- bloqueados: spam (9567), opt-out do cadastro (9568), "Cliente Final" (9575).
    v_k := pg_temp.retorno_f1_canal_caso('5547900009567', 'recibo', '2026-12-08 09:12-03');
    perform pg_temp.retorno_f1_canal_bloqueia('5547900009567', 'spam', '2026-11-30 10:00-03');
    v_a67 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009567', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 09:19:50-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 09:22-03');
    insert into public.clients (type, name, whatsapp, opt_out_whatsapp)
      values ('individual', 'Teste F1 canal opt-out da autorização', '(47) 90000-9568', true);
    v_k := pg_temp.retorno_f1_canal_caso('5547900009568', 'recibo', '2026-12-08 09:12-03');
    v_a68 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009568', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 09:19:50-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 09:22-03');
    insert into public.clients (type, name, phone, generico)
      values ('individual', 'Teste F1 canal Cliente Final da autorização', '5547900009575', true);
    v_k := pg_temp.retorno_f1_canal_caso('5547900009575', 'recibo', '2026-12-08 09:12-03');
    v_a75 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009575', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 09:19:50-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 09:22-03');
    -- o fim do dia: com o recibo do caso em sombra (9569) e enviado (9570).
    v_k := pg_temp.retorno_f1_canal_caso('5547900009569', 'recibo', '2026-12-08 08:50-03');
    perform pg_temp.retorno_f1_canal_saida(v_k, '5547900009569', 'recibo_cliente', 'padrao', 'sombra',
                                           '2026-12-08 09:00-03', jsonb_build_object('prazo', v_pz_0912), 'sombra');
    v_a69 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009569', 'fim_do_dia', 'com_nome', 'enviando',
                                            '2026-12-08 09:19:50-03', '{}', 'ligado', '2026-12-08 09:22-03');
    v_k := pg_temp.retorno_f1_canal_caso('5547900009570', 'recibo', '2026-12-08 08:50-03');
    perform pg_temp.retorno_f1_canal_saida(v_k, '5547900009570', 'recibo_cliente', 'padrao', 'enviada',
                                           '2026-12-08 09:00-03', jsonb_build_object('prazo', v_pz_0912));
    v_a70 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009570', 'fim_do_dia', 'com_nome', 'enviando',
                                            '2026-12-08 09:19:50-03', '{}', 'ligado', '2026-12-08 09:22-03');
    -- fora da janela: recibo às 22:30 (9571); fim do dia no sábado às 13:30 (9572).
    v_k := pg_temp.retorno_f1_canal_caso('5547900009571', 'recibo', '2026-12-08 09:12-03');
    v_a71 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009571', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 22:29-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 22:32-03');
    v_k := pg_temp.retorno_f1_canal_caso('5547900009572', 'recibo', '2026-12-12 09:50-03');
    perform pg_temp.retorno_f1_canal_saida(v_k, '5547900009572', 'recibo_cliente', 'padrao', 'enviada',
                                           '2026-12-12 10:00-03', jsonb_build_object('prazo', v_pz_0912));
    v_a72 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009572', 'fim_do_dia', 'com_nome', 'enviando',
                                            '2026-12-12 13:29-03', '{}', 'ligado', '2026-12-12 13:32-03');
    -- a linha contada da fila (emissor fila) e o caso em passagem (9574).
    insert into public.retorno_saidas (emissor, fila_id, fila_source, tipo, chave, phone_normalized, modo, estado,
                                       enviar_em, decidida_em, dedupe_key)
      values ('fila', gen_random_uuid(), 'ai_monitor', 'fila', '00009573', '5547900009573', 'sombra', 'contada',
              c_t0920, c_t0920, 'teste-f1-canal:fila')
      returning id into v_a73;
    v_k := pg_temp.retorno_f1_canal_caso('5547900009574', 'passagem', '2026-12-08 09:12-03');
    v_a74 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009574', 'recibo_cliente', 'padrao', 'enviando',
                                            '2026-12-08 09:19:50-03', jsonb_build_object('prazo', v_pz_0912), 'ligado',
                                            '2026-12-08 09:22-03');
    -- o caso que virou passagem depois do recibo enviado (9576): o fim do dia dele.
    v_k := pg_temp.retorno_f1_canal_caso('5547900009576', 'passagem', '2026-12-08 08:50-03');
    perform pg_temp.retorno_f1_canal_saida(v_k, '5547900009576', 'recibo_cliente', 'padrao', 'enviada',
                                           '2026-12-08 09:00-03', jsonb_build_object('prazo', v_pz_0912));
    v_a76 := pg_temp.retorno_f1_canal_saida(v_k, '5547900009576', 'fim_do_dia', 'com_nome', 'enviando',
                                            '2026-12-08 09:19:50-03', '{}', 'ligado', '2026-12-08 09:22-03');

    update public.retorno_config set modo = 'ligado', tipos_ligados = c_grupo_parar where id;

    -- A-erro. Exceção forçada (canal_bloqueado renomeada, no meio da conferência): não manda. Fica antes da 1ª
    --         chamada da autorização; a renomeação é desfeita no fim do sub-bloco.
    begin
      alter function public.canal_bloqueado(text) rename to canal_bloqueado_f1_canal_fora;
      v_erro_forcado := public.retorno_saida_autorizada(v_a60, '5547900009560', c_t0920);
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    if to_regprocedure('public.canal_bloqueado(text)') is null then
      raise exception 'A-erro: a renomeação de canal_bloqueado não foi desfeita';
    end if;
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A-erro', v_erro_forcado, false, 'erro');

    -- A0. Tudo certo: pode (com o telefone em qualquer grafia, e pelos nomes do contrato C-AUTORIZA).
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A0a',
      public.retorno_saida_autorizada(v_a60, '5547900009560', c_t0920), true, null);
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A0b',
      public.retorno_saida_autorizada(v_a60, '(47) 90000-9560', c_t0920), true, null);
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A0c',
      public.retorno_saida_autorizada(p_saida => v_a60, p_fone => '5547900009560', p_agora => c_t0920), true, null);
    -- Não conta de novo teto nem espaçamento (já reservados pelo retorno_pegar).
    update public.retorno_config set respostas_dia_max = 0, proximo_envio_em = c_t0920 + interval '60 seconds' where id;
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A0d',
      public.retorno_saida_autorizada(v_a60, '5547900009560', c_t0920), true, null);
    update public.retorno_config set respostas_dia_max = 40, proximo_envio_em = null where id;

    -- A1. Estado errado (preparada, não enviando).
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A1',
      public.retorno_saida_autorizada(v_a61, '5547900009561', c_t0920), false, 'estado');
    -- A2. Telefone de outra chave; os mesmos 8 dígitos com outro DDD; sem telefone.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A2a',
      public.retorno_saida_autorizada(v_a60, '5547900009599', c_t0920), false, 'telefone');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A2b',
      public.retorno_saida_autorizada(v_a60, '5511900009560', c_t0920), false, 'telefone');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A2c',
      public.retorno_saida_autorizada(v_a60, null, c_t0920), false, 'telefone');
    -- A3. Tipo desligado entre a reserva e o envio.
    update public.retorno_config set tipos_ligados = '{adiamento,fim_do_dia,parar}' where id;
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A3',
      public.retorno_saida_autorizada(v_a60, '5547900009560', c_t0920), false, 'tipo_desligado');
    update public.retorno_config set tipos_ligados = c_grupo_parar where id;
    -- A4. "Segura recibos", "segura tudo" e o modo geral em sombra.
    update public.retorno_config set segura_recibos = true where id;
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A4a',
      public.retorno_saida_autorizada(v_a60, '5547900009560', c_t0920), false, 'segura_recibos');
    update public.retorno_config set segura_recibos = false, segura_tudo_ate = c_t0920 + interval '1 hour' where id;
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A4b',
      public.retorno_saida_autorizada(v_a60, '5547900009560', c_t0920), false, 'segura_tudo');
    update public.retorno_config set segura_tudo_ate = null, modo = 'sombra' where id;
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A4c',
      public.retorno_saida_autorizada(v_a60, '5547900009560', c_t0920), false, 'modo');
    update public.retorno_config set modo = 'ligado' where id;
    -- A5. PARAR dentro dos 15 min: a própria saída (enviando) não conta como repetida.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A5',
      public.retorno_saida_autorizada(v_a64, '5547900009564', c_t0920), true, null);
    -- A6. PARAR fora dos 15 min (opt-out às 09:00).
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A6',
      public.retorno_saida_autorizada(v_a65, '5547900009565', c_t0920), false, 'bloqueado');
    -- A7. PARAR repetido (já houve confirmação enviada à chave).
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A7',
      public.retorno_saida_autorizada(v_a66, '5547900009566', c_t0920), false, 'bloqueado');
    -- A8. Saída que não existe (ou nula): não manda.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A8a',
      public.retorno_saida_autorizada(gen_random_uuid(), '5547900009560', c_t0920), false, 'sem_saida');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A8b',
      public.retorno_saida_autorizada(null, '5547900009560', c_t0920), false, 'sem_saida');
    -- A9. Reserva vencida; saída que não está ligada.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A9a',
      public.retorno_saida_autorizada(v_a62, '5547900009562', c_t0920), false, 'reserva_vencida');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A9b',
      public.retorno_saida_autorizada(v_a63, '5547900009563', c_t0920), false, 'saida_em_sombra');
    -- A10. Bloqueio que apareceu (spam, opt-out do cadastro, "Cliente Final").
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A10a',
      public.retorno_saida_autorizada(v_a67, '5547900009567', c_t0920), false, 'bloqueado');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A10b',
      public.retorno_saida_autorizada(v_a68, '5547900009568', c_t0920), false, 'opt_out');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A10c',
      public.retorno_saida_autorizada(v_a75, '5547900009575', c_t0920), false, 'cliente_final');
    -- A11. O modo do caso: o fim do dia de um caso cujo recibo foi sombra não sai; com o recibo enviado, sai.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A11a',
      public.retorno_saida_autorizada(v_a69, '5547900009569', c_t0920), false, 'caso_em_sombra');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A11b',
      public.retorno_saida_autorizada(v_a70, '5547900009570', c_t0920), true, null);
    -- A12. A janela da classe, no instante do envio.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A12a',
      public.retorno_saida_autorizada(v_a71, '5547900009571', '2026-12-08 22:30-03'), false, 'fora_da_janela');
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A12b',
      public.retorno_saida_autorizada(v_a72, '5547900009572', '2026-12-12 13:30-03'), false, 'fora_da_janela');
    -- A13. A linha contada da fila não é saída do retorno.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A13',
      public.retorno_saida_autorizada(v_a73, '5547900009573', c_t0920), false, 'emissor');
    -- A14. Caso em passagem, sem o acorde real.
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A14',
      public.retorno_saida_autorizada(v_a74, '5547900009574', c_t0920), false, 'passagem_sem_acorde');
    -- A14b. O caso que virou passagem depois do recibo enviado: o fim do dia dele sai (o aviso da promessa ouvida).
    v_n_aut := v_n_aut + pg_temp.retorno_f1_canal_aut('A14b',
      public.retorno_saida_autorizada(v_a76, '5547900009576', c_t0920), true, null);

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0i: o arranjo não chegou ao fim';
  end if;
  if (select to_jsonb(c) from public.retorno_config c where c.id) is distinct from v_cfg_antes
     or exists (select 1 from public.clients where name like 'Teste F1 canal%')
     or exists (select 1 from public.payees where name like 'Teste F1 canal%')
     or exists (select 1 from public.whatsapp_blocked_numbers where reason = 'Teste F1 canal')
     or exists (select 1 from public.retorno_saidas where dedupe_key like 'teste-f1-canal:%')
     or exists (select 1 from public.retorno_aberturas where chave like '000095%')
     or to_regprocedure('public.canal_bloqueado(text)') is null then
    raise exception '0j: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_canal', true,
          jsonb_build_object('canal', v_n_canal, 'parar', v_n_parar, 'modo_efetivo', v_n_modo, 'autorizacao', v_n_aut,
                             'teto_ja_havia', v_base_real));
end
$canal$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
