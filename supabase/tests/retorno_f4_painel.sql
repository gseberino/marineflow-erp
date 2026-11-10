-- Retorno F4 (P7): o painel, o pátio, a pausa, o eco, a ativação, a releitura do veto e o vigia do parceiro. Paridade dos
-- fatos com a F2, a linha de P7.2 estado a estado (com as datas no fuso de Brasília), lista positiva de chaves, anfitriã
-- nunca citada, o eco só depois de o cliente ouvir, e o leitor de palavras externas. Roda só pela bancada (grupo 7,
-- F4_ONDA=5, F4_TESTES=retorno_f4_painel). Termina em ROLLBACK. Telefones de teste 55479000149xx a 55479000152xx; nomes
-- inventados. Relógio: qui 14/01/2027 10:00 (dia útil); painéis de seg 11 a sex 15/01/2027; 01/01/2027 é feriado.
-- Respostas do dono de 09/11 (R1, a etapa; R2, o veículo que não começou), no fim: telefones 55479000176xx e números de OS
-- OS-TF4R-01 a 11 e 21 a 29 (antes de rodar, conferir só por count(*) que não existem no banco).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());
create temp table if not exists _f4p_quebra (os uuid primary key);

create or replace function pg_temp.f4p_cliente(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

-- Uma OS com a unidade, o status e as datas dadas (no insert: os gatilhos de data só olham o update).
create or replace function pg_temp.f4p_os(p_cliente uuid, p_status text default 'open', p_check_in timestamptz default null,
                                          p_convertida timestamptz default null, p_quote text default 'approved',
                                          p_origem_parceiro uuid default null, p_bem text default 'Motorhome') returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), p_bem) returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, check_in_at, converted_to_os_at, origem_parceiro_id)
  values ('OS-TF4P-' || left(md5(p_cliente::text || clock_timestamp()::text || random()::text), 8), p_cliente, v_v, p_status,
          p_quote, 'repair', '2026-12-10 10:00-03', '2026-12-10 10:00-03', 0, p_check_in, p_convertida, p_origem_parceiro)
  returning id into v_id;
  return v_id;
end $f$;

-- O vínculo confirmado (avisado há dias, salvo aviso nulo).
create or replace function pg_temp.f4p_liga(p_os uuid, p_parceiro uuid, p_papel text default 'indicou',
                                            p_aviso_em timestamptz default '2027-01-05 10:00-03') returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, aviso_ao_cliente, aviso_em,
                                      confirmado_em)
  select so.id, p_parceiro, so.client_id, p_papel, 'confirmado', 'dono',
         case when p_aviso_em is null then 'nao_avisado' else 'mensagem' end, p_aviso_em, timestamptz '2027-01-01 10:00-03'
    from public.service_orders so where so.id = p_os
  returning id
$f$;

-- A palavra de conclusão do dono.
create or replace function pg_temp.f4p_concluir(p_os uuid, p_em timestamptz) returns void
language sql as $f$
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, texto)
  values (p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, 'dono', 'concluir', p_os, 'concluiu no teste')
$f$;

-- O cliente ouviu: a mensagem da agenda enviada.
create or replace function pg_temp.f4p_ouviu(p_os uuid, p_tipo text, p_variante text, p_em timestamptz) returns void
language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, modo, texto, enviar_em, valida_ate,
                                               aprovacao, estado, dedupe_key, enviada_em, criada_em)
  select so.client_id, so.id, p_tipo, p_variante, 'rodada', 'ligado', 'mensagem de teste (F4 painel)', p_em, p_em + interval '9 hours',
         'livre', 'enviada', 'teste-f4p:' || md5(so.id::text || p_tipo || coalesce(p_variante, '') || p_em::text), p_em, p_em
    from public.service_orders so where so.id = p_os
$f$;

-- Uma peça crítica (descrição fixa de teste: nunca pode aparecer na linha).
create or replace function pg_temp.f4p_peca(p_os uuid, p_situacao text, p_chegou date default null, p_comprado date default null,
                                            p_atualizado timestamptz default '2027-01-03 10:00-03') returns void
language sql as $f$
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte,
                                  chegou_em, comprado_em, atualizado_em)
  values (p_os, 'dono', 'compressor de teste f4p', 1, case when p_situacao = 'na_mao' then 1 else 0 end, true, p_situacao, 'dono',
          p_chegou, p_comprado, p_atualizado)
$f$;

create or replace function pg_temp.f4p_msg(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', p_fone, 'text', p_corpo, 'teste-f4-painel-' || md5(p_fone || p_corpo || p_em::text || random()::text), p_em)
  returning id
$f$;

-- O aviso por mensagem já enviado ao cliente do vínculo (o arranjo da retenção).
create or replace function pg_temp.f4p_aviso_enviado(p_interessado uuid, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em,
                                     decidida_em, enviada_em, texto, dados, dedupe_key)
  select 'parceiro', 'parceiro_aviso_cliente', 'retorno_aviso', 'aviso', public._agenda_chave_telefone(c.whatsapp), c.whatsapp,
         oi.client_id, 'ligado', 'enviada', p_em, p_em, p_em, 'aviso de teste f4 painel',
         jsonb_build_object('client_id', oi.client_id, 'parceiro_id', oi.parceiro_id, 'interessado_ids', jsonb_build_array(oi.id)),
         'parceiro:teste:painel:aviso:' || oi.id
    from public.os_interessados oi join public.clients c on c.id = oi.client_id
   where oi.id = p_interessado
  returning id into v;
  update public.os_interessados set aviso_saida_id = v, aviso_ao_cliente = 'mensagem', aviso_em = p_em where id = p_interessado;
  return v;
end $f$;

-- A linha do vínculo nas linhas do parceiro (nula se ele não está lá).
create or replace function pg_temp.f4p_linha(p_linhas jsonb, p_interessado uuid) returns jsonb
language sql as $f$
  select l from jsonb_array_elements(p_linhas) l where l ->> 'interessado_id' = p_interessado::text
$f$;

-- Confere uma linha: estado, desde, retida_por e fora_por; n só nas que saem. Nulo nunca passa calado.
create or replace function pg_temp.f4p_confere(p_rotulo text, p_l jsonb, p_estado text, p_desde text, p_retida text, p_fora text) returns void
language plpgsql as $f$
begin
  if p_l is null then
    raise exception '%: a linha não está nas linhas', p_rotulo;
  end if;
  if p_l ->> 'estado' is distinct from p_estado or p_l ->> 'desde' is distinct from p_desde
     or p_l ->> 'retida_por' is distinct from p_retida or p_l ->> 'fora_por' is distinct from p_fora
     or ((p_l ->> 'n') is null) is distinct from (p_fora is not null) then
    raise exception '%: esperado % % % %, veio %', p_rotulo, p_estado, p_desde, p_retida, p_fora, p_l;
  end if;
end $f$;

-- Roda a fila com a saída dada devida (as outras devidas caem) e devolve estado/motivo dela.
create or replace function pg_temp.f4p_pegar(p_saida uuid, p_agora timestamptz) returns text
language plpgsql as $f$
begin
  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'substituida', decidida_em = p_agora, processando_ate = null
   where s.emissor = 'parceiro' and s.estado = 'agendada' and s.id <> p_saida and s.enviar_em <= p_agora;
  update public.retorno_config set proximo_envio_em = null where id;
  perform public.parceiro_pegar(p_agora);
  return (select s.estado || '/' || coalesce(s.motivo, '') from public.retorno_saidas s where s.id = p_saida);
end $f$;

-- Tira da fila do parceiro o fato da OS (para o teste de "nunca derruba"): troca _parceiro_fato_da_os por um invólucro que
-- quebra nas OS de _f4p_quebra, e desfaz a troca.
create or replace function pg_temp.f4p_quebrar(p_ligar boolean) returns void
language plpgsql as $f$
begin
  if p_ligar then
    execute 'alter function public._parceiro_fato_da_os(uuid, timestamptz) rename to _parceiro_fato_da_os_real';
    execute $ddl$
      create function public._parceiro_fato_da_os(p_os uuid, p_agora timestamptz) returns jsonb
      language plpgsql stable as $q$
      begin
        if exists (select 1 from pg_temp._f4p_quebra q where q.os = p_os) then
          raise exception 'quebra de teste f4p';
        end if;
        return public._parceiro_fato_da_os_real(p_os, p_agora);
      end $q$
    $ddl$;
  else
    execute 'drop function public._parceiro_fato_da_os(uuid, timestamptz)';
    execute 'alter function public._parceiro_fato_da_os_real(uuid, timestamptz) rename to _parceiro_fato_da_os';
  end if;
end $f$;

-- Tira os outros parceiros do ar enquanto a rodada do painel roda para um só (e devolve).
create or replace function pg_temp.f4p_so(p_parceiro uuid, p_ids uuid[]) returns void
language sql as $f$
  update public.parceiros set ativo = (id = p_parceiro or p_parceiro is null) where id = any (p_ids)
$f$;

-- O item da F2 sem o que o parceiro nunca vê (o nome da unidade, a previsão e a descrição da peça).
create or replace function pg_temp.f4p_sem_privado(p jsonb) returns jsonb
language sql as $f$
  select (p - 'bem') || jsonb_build_object('fatos',
           ((p -> 'fatos') - 'previsao') || jsonb_build_object('aguarda_peca',
             case when jsonb_typeof(p -> 'fatos' -> 'aguarda_peca') = 'object'
                  then (p -> 'fatos' -> 'aguarda_peca') || jsonb_build_object('linhas',
                         (select jsonb_agg(l - 'descricao' order by o)
                            from jsonb_array_elements(p -> 'fatos' -> 'aguarda_peca' -> 'linhas') with ordinality t(l, o)))
                  else p -> 'fatos' -> 'aguarda_peca' end))
$f$;

-- Respostas de 09/11 (R1 e R2): a OS com o número dado, para a ordem das linhas e o texto do painel serem literais.
create or replace function pg_temp.f4p_os_n(p_cliente uuid, p_numero text, p_status text, p_check_in timestamptz default null,
                                            p_convertida timestamptz default null, p_quote text default 'approved',
                                            p_origem_parceiro uuid default null) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type) values (p_cliente, 'Unidade ' || p_numero, 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, check_in_at, converted_to_os_at, origem_parceiro_id)
  values (p_numero, p_cliente, v_v, p_status, p_quote, 'repair', '2026-12-10 10:00-03', '2026-12-10 10:00-03', 0, p_check_in,
          p_convertida, p_origem_parceiro)
  returning id into v_id;
  return v_id;
end $f$;

-- A linha como parceiro_linhas a montava antes das respostas de 09/11: as 8 chaves, nenhuma a mais.
create or replace function pg_temp.f4p_antes(p_interessado uuid, p_n integer, p_estado text, p_desde date, p_fora text) returns jsonb
language sql as $f$
  select jsonb_build_object('n', p_n, 'interessado_id', oi.id, 'service_order_id', oi.service_order_id, 'estado', p_estado,
                            'desde', p_desde, 'rotulo', so.service_order_number, 'retida_por', null, 'fora_por', p_fora)
    from public.os_interessados oi join public.service_orders so on so.id = oi.service_order_id
   where oi.id = p_interessado
$f$;

-- A ordem de parceiro_linhas: as que saem por n; as de fora pelo número da OS (collate "C") e pelo id.
create or replace function pg_temp.f4p_ordem(p_linhas jsonb[]) returns jsonb
language sql as $f$
  select jsonb_agg(l order by (l ->> 'n') is null, (l ->> 'n')::integer, l ->> 'rotulo' collate "C", l ->> 'service_order_id')
    from unnest(p_linhas) l
$f$;

-- Respostas de 09/11 (R1): a etapa do dia, como a F2 a lê (a 1ª tarefa ligada de os_tarefas_dia no dia).
create or replace function pg_temp.f4p_etapa(p_os uuid, p_texto text, p_dia date) returns void
language plpgsql as $f$
declare
  v_t uuid;
begin
  insert into public.os_tarefas (service_order_id, chave, origem, texto, fase, ordem, horas, estado, criada_em, mudou_em)
    values (p_os, 'linha:teste-f4r', 'roteiro', p_texto, 1, 1, 1, 'viva', '2027-01-10 10:00-03', '2027-01-10 10:00-03')
    returning id into v_t;
  insert into public.os_tarefas_dia (tarefa_id, service_order_id, dia, turno, modo, fracao, comeca, termina, posicao, estado,
                                     congelada_em)
    values (v_t, p_os, p_dia, 'manha', 'ligado', 1, true, true, 1, 'planejada', '2027-01-10 10:00-03');
end $f$;

-- As linhas que saem como o painel e o pátio as copiavam antes de 09/11 (n, interessado_id, service_order_id, estado, desde).
create or replace function pg_temp.f4p_copia_antes(p_linhas jsonb) returns jsonb
language sql as $f$
  select coalesce(jsonb_agg(jsonb_build_object('n', (l ->> 'n')::integer, 'interessado_id', l -> 'interessado_id',
                                               'service_order_id', l -> 'service_order_id', 'estado', l -> 'estado', 'desde', l -> 'desde')
                            order by (l ->> 'n')::integer), '[]'::jsonb)
    from jsonb_array_elements(p_linhas) l
   where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$'
$f$;

do $painel$
declare
  c_t constant timestamptz := '2027-01-14 10:00-03';        -- qui
  v_dono uuid;
  v_p uuid; v_p4 uuid; v_p5 uuid; v_pe uuid; v_pv uuid; v_pa uuid; v_px uuid;
  v_todos uuid[];
  v_carla uuid; v_milena uuid; v_rosa uuid; v_eva uuid;
  v_n1 uuid; v_n2 uuid; v_n3 uuid; v_n4 uuid; v_n5 uuid; v_ne uuid; v_nv uuid; v_na uuid; v_nx uuid;
  v_c uuid;
  v_os1 uuid; v_os2 uuid; v_os3 uuid; v_os4 uuid; v_os5 uuid; v_os6 uuid; v_os7 uuid; v_os8 uuid; v_os9 uuid; v_os10 uuid;
  v_os13 uuid; v_os14 uuid; v_os15 uuid; v_os19 uuid;
  v_i1 uuid; v_i2 uuid; v_i3 uuid; v_i4 uuid; v_i5 uuid; v_i6 uuid; v_i7 uuid; v_i8 uuid; v_i9 uuid; v_i10 uuid; v_i11 uuid;
  v_i12 uuid; v_i13 uuid; v_i14 uuid; v_i15 uuid; v_i16 uuid; v_i17 uuid; v_i18 uuid; v_i19 uuid;
  v_iq uuid; v_ir uuid; v_is uuid; v_it uuid; v_iu uuid; v_i4a uuid; v_i5a uuid; v_ix uuid;
  v_e1 uuid; v_e2 uuid; v_e3 uuid; v_e4 uuid; v_e5 uuid;
  v_eos1 uuid; v_eos2 uuid; v_eos3 uuid; v_eos4 uuid; v_eos5 uuid;
  v_ie1 uuid; v_ie2 uuid; v_ie3 uuid; v_ie4 uuid; v_ie5 uuid;
  v_linhas jsonb;
  v_l jsonb;
  v_r jsonb;
  v_f jsonb;
  v_x public.retorno_saidas;
  v_pp public.parceiro_paineis;
  v_painel uuid;
  v_s uuid;
  v_msg uuid;
  v_texto text;
  v_t text;
  v_n integer;
  v_k integer;
  v_ns integer[];
  v_antes bigint;
  v_rec record;
  v_n_fun integer := 0;
  v_pr uuid; v_nr uuid; v_ri uuid[];                         -- respostas de 09/11, R2
  v_pt uuid; v_nt uuid; v_ti uuid[] := '{}'; v_ot uuid; v_iz uuid;   -- respostas de 09/11, R1
  v_esperado jsonb;
  v_etapa60 text := rpad('Revisão geral', 60, ' da cabine');
begin
  begin
  select d.id into v_dono from public._comprovante_dono() d;
  if v_dono is null then
    raise exception '0: sem o dono (_comprovante_dono) no banco';
  end if;
  update public.retorno_config
     set modo = 'sombra', identificacao_nova = true, parceiro_modo = 'sombra', tipos_ligados = '{}', parceiro_tipos_ligados = '{}',
         proximo_envio_em = null, segura_tudo_ate = null, so_reativo = false, segura_patio = false, patio_nivel = 'cartao',
         eco_modo = 'sombra', painel_nivel = 'fechamento', carencia_min = 2, respostas_dia_max = 40, iniciadas_dia_max = 50
   where id;

  -- Arranjo: a revenda principal (RPF), com a Carla e a Milena no resumo e a Rosa (financeiro) fora dele.
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Painel F4', 'RPF', 'revenda_e_patio') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Milena', 'comercial') returning id into v_milena;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Rosa', 'financeiro') returning id into v_rosa;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_carla, '5547900014901', '00014901', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n1;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_milena, '5547900014902', '00014902', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n2;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel, uso)
    values (v_rosa, '5547900014903', '00014903', '47', 'confirmado', c_t - interval '30 days', false, 'financeiro') returning id into v_n3;

  -- As linhas da RPF, uma por estado de P7.2 (todas com aviso há dias, salvo a 18).
  v_c := pg_temp.f4p_cliente('Ana Painel', '5547900014911');                      -- L1 pronto, o cliente ouviu
  v_os1 := pg_temp.f4p_os(v_c, 'completed');
  perform pg_temp.f4p_concluir(v_os1, c_t - interval '10 hours');
  perform pg_temp.f4p_ouviu(v_os1, 'pronto', null, c_t - interval '9 hours');
  v_i1 := pg_temp.f4p_liga(v_os1, v_p);
  v_c := pg_temp.f4p_cliente('Beto Painel', '5547900014912');                     -- L2 pronto sem ouvir: cai ao andamento
  v_os2 := pg_temp.f4p_os(v_c, 'completed', null, '2027-01-08 15:00-03');
  perform pg_temp.f4p_concluir(v_os2, c_t - interval '10 hours');
  v_i2 := pg_temp.f4p_liga(v_os2, v_p);
  v_c := pg_temp.f4p_cliente('Caio Painel', '5547900014913');                     -- L3 peca_chegou
  v_os3 := pg_temp.f4p_os(v_c, 'open');
  perform pg_temp.f4p_peca(v_os3, 'na_mao', date '2027-01-12');
  perform pg_temp.f4p_ouviu(v_os3, 'material_chegou', null, '2027-01-12 15:00-03');
  v_i3 := pg_temp.f4p_liga(v_os3, v_p);
  v_c := pg_temp.f4p_cliente('Dora Painel', '5547900014914');                     -- L4 aguarda_peca, várias peças
  v_os4 := pg_temp.f4p_os(v_c, 'awaiting_parts');
  perform pg_temp.f4p_peca(v_os4, 'comprado', null, date '2027-01-05');
  perform pg_temp.f4p_peca(v_os4, 'falta', null, null, '2027-01-09 10:00-03');
  perform pg_temp.f4p_ouviu(v_os4, 'pode_atrasar', 'peca', '2027-01-10 09:00-03');
  v_i4 := pg_temp.f4p_liga(v_os4, v_p);
  v_c := pg_temp.f4p_cliente('Eli Painel', '5547900014915');                      -- L5 em_servico
  v_os5 := pg_temp.f4p_os(v_c, 'in_progress', c_t - interval '2 hours');
  v_i5 := pg_temp.f4p_liga(v_os5, v_p);
  v_c := pg_temp.f4p_cliente('Fred Painel', '5547900014916');                     -- L6 orcamento (rascunho da RPF)
  v_os6 := pg_temp.f4p_os(v_c, 'draft', null, null, 'draft', v_p);
  v_i6 := pg_temp.f4p_liga(v_os6, v_p);
  v_c := pg_temp.f4p_cliente('Gabi Painel', '5547900014917');                     -- L7 andamento só pela conversão
  v_os7 := pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03');
  v_i7 := pg_temp.f4p_liga(v_os7, v_p);
  v_c := pg_temp.f4p_cliente('Hugo Painel', '5547900014918');                     -- L8 andamento só pelo check-in, às 22:30
  v_os8 := pg_temp.f4p_os(v_c, 'open', '2027-01-10 22:30-03');
  v_i8 := pg_temp.f4p_liga(v_os8, v_p);
  v_c := pg_temp.f4p_cliente('Iara Painel', '5547900014919');                     -- L9 andamento só pela peça (ouvida, velha)
  v_os9 := pg_temp.f4p_os(v_c, 'open');
  perform pg_temp.f4p_peca(v_os9, 'na_mao', date '2027-01-02');
  perform pg_temp.f4p_ouviu(v_os9, 'material_chegou', null, '2027-01-02 12:00-03');
  v_i9 := pg_temp.f4p_liga(v_os9, v_p);
  v_c := pg_temp.f4p_cliente('Joel Painel', '5547900014920');                     -- L10 em serviço sem data
  v_os10 := pg_temp.f4p_os(v_c, 'in_progress');
  v_i10 := pg_temp.f4p_liga(v_os10, v_p);
  v_c := pg_temp.f4p_cliente('Kelly Painel', '5547900014921');                    -- L11 aprovada sem data: fora
  v_i11 := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'approved'), v_p);
  v_c := pg_temp.f4p_cliente('Lara Painel', '5547900014922');                     -- L12 data futura vale nula: fora
  v_i12 := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'approved', null, '2027-01-20 10:00-03'), v_p);
  v_c := pg_temp.f4p_cliente('Mara Painel', '5547900014923');                     -- L13 peça retida (não ouvida)
  v_os13 := pg_temp.f4p_os(v_c, 'in_progress');
  perform pg_temp.f4p_peca(v_os13, 'na_mao', date '2027-01-12');
  v_i13 := pg_temp.f4p_liga(v_os13, v_p);
  v_c := pg_temp.f4p_cliente('Nina Painel', '5547900014924');                     -- L14 só anfitriã
  v_os14 := pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03');
  perform pg_temp.f4p_ouviu(v_os14, 'pronto', null, c_t - interval '2 hours');
  v_i14 := pg_temp.f4p_liga(v_os14, v_p, 'anfitria');
  v_c := pg_temp.f4p_cliente('Otto Painel', '5547900014925');                     -- L15 concluída sem palavra: fora da regra 8
  v_os15 := pg_temp.f4p_os(v_c, 'completed', null, '2027-01-08 15:00-03');
  v_i15 := pg_temp.f4p_liga(v_os15, v_p);
  v_c := pg_temp.f4p_cliente('João Silva', '5547900014926');                      -- L16 homônimo de um vetado
  v_i16 := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03'), v_p);
  v_c := pg_temp.f4p_cliente('João Souza', '5547900014927');
  v_i17 := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03'), v_p);
  update public.os_interessados set veto_do_cliente_em = c_t - interval '3 days' where id = v_i17;
  v_c := pg_temp.f4p_cliente('Pedro Painel', '5547900014928');                    -- L18 sem aviso (só na foto de sombra)
  v_i18 := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'in_progress', c_t - interval '2 hours'), v_p, 'indicou', null);
  v_c := pg_temp.f4p_cliente('Vera Painel', '5547900014934');                     -- L19 convertida hoje de manhã
  v_os19 := pg_temp.f4p_os(v_c, 'open', null, '2027-01-14 09:00-03');
  v_i19 := pg_temp.f4p_liga(v_os19, v_p);

  -- ── 1. Paridade: _parceiro_fato_da_os igual ao item de retorno_fatos_do_contato (sem o privado), em 5 OS ──
  for v_rec in
    select * from (values (v_os1, '5547900014911'), (v_os3, '5547900014913'), (v_os4, '5547900014914'),
                          (v_os5, '5547900014915'), (v_os7, '5547900014917')) as x(os, fone)
  loop
    select e into v_f from jsonb_array_elements(public.retorno_fatos_do_contato(v_rec.fone, c_t) -> 'os') e
     where e ->> 'id' = v_rec.os::text;
    if v_f is null or public._parceiro_fato_da_os(v_rec.os, c_t) is distinct from pg_temp.f4p_sem_privado(v_f) then
      raise exception '1: paridade dos fatos da OS % (F2 %, F4 %)', v_rec.os, pg_temp.f4p_sem_privado(v_f),
        public._parceiro_fato_da_os(v_rec.os, c_t);
    end if;
  end loop;
  if public._parceiro_fato_da_os(v_os4, c_t)::text like '%compressor%' or public._parceiro_fato_da_os(v_os4, c_t) -> 'fatos' ? 'previsao' then
    raise exception '1b: o fato do parceiro trouxe descrição ou previsão';
  end if;

  -- ── 2, 9, 15, 19 e 20. Uma linha por estado, as datas de cada um e quem nunca entra ──
  v_linhas := public.parceiro_linhas(v_p, c_t);
  perform pg_temp.f4p_confere('2/L1 pronto', pg_temp.f4p_linha(v_linhas, v_i1), 'pronto', null, null, null);
  perform pg_temp.f4p_confere('2/L2 pronto sem ouvir cai', pg_temp.f4p_linha(v_linhas, v_i2), 'andamento', '2027-01-08', 'pronto', null);
  perform pg_temp.f4p_confere('2/19 L3 peca_chegou', pg_temp.f4p_linha(v_linhas, v_i3), 'peca_chegou', '2027-01-12', null, null);
  perform pg_temp.f4p_confere('2/19 L4 aguarda_peca, a maior desde', pg_temp.f4p_linha(v_linhas, v_i4), 'aguarda_peca', '2027-01-09', null, null);
  perform pg_temp.f4p_confere('2/L5 em_servico', pg_temp.f4p_linha(v_linhas, v_i5), 'em_servico', null, null, null);
  perform pg_temp.f4p_confere('2/L6 orcamento', pg_temp.f4p_linha(v_linhas, v_i6), 'orcamento', null, null, null);
  perform pg_temp.f4p_confere('19 L7 só conversão', pg_temp.f4p_linha(v_linhas, v_i7), 'andamento', '2027-01-08', null, null);
  perform pg_temp.f4p_confere('19 L8 só check-in, dia de Brasília', pg_temp.f4p_linha(v_linhas, v_i8), 'andamento', '2027-01-10', null, null);
  perform pg_temp.f4p_confere('19 L9 só chegou_em ouvida', pg_temp.f4p_linha(v_linhas, v_i9), 'andamento', '2027-01-02', null, null);
  perform pg_temp.f4p_confere('20 L10 em serviço sem data', pg_temp.f4p_linha(v_linhas, v_i10), 'andamento_sem_data', null, null, null);
  perform pg_temp.f4p_confere('20 L11 aprovada sem data fora', pg_temp.f4p_linha(v_linhas, v_i11), null, null, null, 'sem_fato');
  perform pg_temp.f4p_confere('19 L12 data futura nula', pg_temp.f4p_linha(v_linhas, v_i12), null, null, null, 'sem_fato');
  perform pg_temp.f4p_confere('19 L13 peça retida', pg_temp.f4p_linha(v_linhas, v_i13), 'andamento_sem_data', null, 'peca_chegou', null);
  perform pg_temp.f4p_confere('19 L19 hoje não é futura', pg_temp.f4p_linha(v_linhas, v_i19), 'andamento', '2027-01-14', null, null);
  if pg_temp.f4p_linha(v_linhas, v_i14) is not null then
    raise exception '9a: a anfitriã entrou na linha';
  end if;
  if pg_temp.f4p_linha(v_linhas, v_i15) is not null then
    raise exception '15c: a OS concluída fora da regra 8 entrou na linha';
  end if;
  if pg_temp.f4p_linha(v_linhas, v_i18) is not null or pg_temp.f4p_linha(v_linhas, v_i17) is not null then
    raise exception '2b: vínculo sem aviso ou vetado entrou na linha';
  end if;
  -- 22. O homônimo de um vetado fica fora (nome_ambiguo) e o painel sai com as outras
  perform pg_temp.f4p_confere('22 L16 homônimo', pg_temp.f4p_linha(v_linhas, v_i16), 'andamento', '2027-01-08', null, 'nome_ambiguo');
  -- 19. às 23:00 de hoje, a data de hoje não vira futura
  perform pg_temp.f4p_confere('19 L19 às 23:00', pg_temp.f4p_linha(public.parceiro_linhas(v_p, '2027-01-14 23:00-03'), v_i19),
                              'andamento', '2027-01-14', null, null);

  -- ── 3. Lista positiva de chaves; nada da peça, da etapa, da previsão ou de valor ──
  if exists (select 1 from jsonb_array_elements(v_linhas) l, jsonb_object_keys(l) k
              where k not in ('n', 'interessado_id', 'service_order_id', 'estado', 'desde', 'rotulo', 'retida_por', 'fora_por')) then
    raise exception '3a: a linha tem chave fora da lista positiva';
  end if;
  if v_linhas::text ~* '(compressor|previs|valor|grand_total|concluiu no teste)' then
    raise exception '3b: a linha carrega dado que nunca sai';
  end if;

  -- ── 23. Ordem: n de 1 a k só nas que saem, e o estado nunca desce ──
  select array_agg((l ->> 'n')::integer order by (l ->> 'n')::integer) into v_ns
    from jsonb_array_elements(v_linhas) l where l ->> 'fora_por' is null;
  if v_ns is distinct from array(select generate_series(1, 12)) then
    raise exception '23a: n não vai de 1 a 12 nas linhas que saem (%)', v_ns;
  end if;
  if exists (select 1 from jsonb_array_elements(v_linhas) l where l ->> 'fora_por' is not null and l ->> 'n' is not null)
     or exists (select 1
                  from jsonb_array_elements(v_linhas) a, jsonb_array_elements(v_linhas) b
                 where a ->> 'fora_por' is null and b ->> 'fora_por' is null
                   and (a ->> 'n')::integer < (b ->> 'n')::integer
                   and array_position(array['pronto', 'peca_chegou', 'aguarda_peca', 'em_servico', 'orcamento', 'andamento', 'andamento_sem_data'], a ->> 'estado')
                       > array_position(array['pronto', 'peca_chegou', 'aguarda_peca', 'em_servico', 'orcamento', 'andamento', 'andamento_sem_data'], b ->> 'estado')) then
    raise exception '23b: a ordem dos estados ou o n das linhas fora';
  end if;

  -- ── 20. Toda data do texto vem das fontes (ou do cabeçalho) ──
  v_texto := public._parceiro_painel_texto('parceiro_painel', 'padrao',
               (select jsonb_agg(jsonb_build_object('n', (l ->> 'n')::integer, 'interessado_id', l -> 'interessado_id',
                                                    'service_order_id', l -> 'service_order_id', 'estado', l -> 'estado', 'desde', l -> 'desde')
                                 order by (l ->> 'n')::integer)
                  from jsonb_array_elements(v_linhas) l where l ->> 'fora_por' is null),
               0, date '2027-01-14', false) ->> 'texto';
  for v_t in select m[1] from regexp_matches(v_texto, '([0-9]{2}/[0-9]{2})', 'g') m loop
    if v_t is distinct from '14/01'
       and not exists (select 1 from jsonb_array_elements(v_linhas) l
                        where l ->> 'fora_por' is null and to_char((l ->> 'desde')::date, 'DD/MM') = v_t) then
      raise exception '20b: o texto traz a data % que não está nas fontes', v_t;
    end if;
  end loop;
  if v_texto not like '%Motorhome de Joel P.: em serviço.%' or v_texto like '%João%' or v_texto like '%Kelly%' then
    raise exception '20c/22b: o painel com as linhas sem data (%)', v_texto;
  end if;
  -- 22. nomes_de_outros leva o homônimo, e o texto não o cita
  v_r := public._parceiro_contexto_do_validador(null, v_texto,
           jsonb_build_object('parceiro_id', v_p, 'interessado_ids',
                              (select jsonb_agg(l -> 'interessado_id') from jsonb_array_elements(v_linhas) l where l ->> 'fora_por' is null)),
           c_t);
  if not (v_r -> 'nomes_de_outros' ? 'João S.') then
    raise exception '22c: o homônimo fora não está em nomes_de_outros (%)', v_r -> 'nomes_de_outros';
  end if;

  -- 19. Peça retida com *1 sabe 2*: a palavra do dono libera a linha da peça
  insert into public.parceiro_cliente_sabe (service_order_id, marco, autor, em) values (v_os13, 'peca_chegou', v_dono, c_t - interval '1 hour');
  perform pg_temp.f4p_confere('19 L13 com o dono dizendo que sabe', pg_temp.f4p_linha(public.parceiro_linhas(v_p, c_t), v_i13),
                              'peca_chegou', '2027-01-12', null, null);

  -- ── 24. A impressão muda com estado e desde; não com n, rótulo, retida_por nem linha fora ──
  v_l := jsonb_build_array(jsonb_build_object('n', 1, 'service_order_id', v_os7, 'estado', 'andamento', 'desde', '2027-01-08', 'rotulo', 'OS-1', 'retida_por', null, 'fora_por', null),
                           jsonb_build_object('n', 2, 'service_order_id', v_os5, 'estado', 'em_servico', 'desde', null, 'rotulo', 'OS-2', 'retida_por', null, 'fora_por', null));
  v_t := public._parceiro_impressao(v_l);
  if public._parceiro_impressao(jsonb_build_array(v_l -> 1 || '{"n": 7, "rotulo": "OS-X", "retida_por": "pronto"}', v_l -> 0 || '{"n": 9}')) is distinct from v_t
     or public._parceiro_impressao(v_l || jsonb_build_array(jsonb_build_object('service_order_id', v_os9, 'estado', 'andamento', 'desde', '2027-01-02', 'fora_por', 'tirada'))) is distinct from v_t then
    raise exception '24a: a impressão mudou com n, rótulo, retida_por ou linha fora';
  end if;
  if public._parceiro_impressao(jsonb_build_array(v_l -> 0, v_l -> 1 || '{"estado": "andamento_sem_data"}')) is not distinct from v_t
     or public._parceiro_impressao(jsonb_build_array(v_l -> 0 || '{"desde": "2027-01-09"}', v_l -> 1)) is not distinct from v_t then
    raise exception '24b: a impressão não mudou com estado ou desde';
  end if;

  -- ── 16. Painel misto: a marca cliente_ouviu só com cada linha pronto ouvida ──
  v_r := public._parceiro_contexto_do_validador(null, 'texto de teste',
           jsonb_build_object('parceiro_id', v_p, 'linhas', jsonb_build_array(
             jsonb_build_object('service_order_id', v_os1, 'estado', 'pronto'),
             jsonb_build_object('service_order_id', v_os5, 'estado', 'em_servico'))), c_t);
  if (v_r -> 'marcas' ->> 'cliente_ouviu')::boolean is not true then
    raise exception '16a: a linha pronto ouvida não deu a marca';
  end if;
  v_r := public._parceiro_contexto_do_validador(null, 'texto de teste',
           jsonb_build_object('parceiro_id', v_p, 'linhas', jsonb_build_array(
             jsonb_build_object('service_order_id', v_os2, 'estado', 'pronto'),
             jsonb_build_object('service_order_id', v_os5, 'estado', 'em_servico'))), c_t);
  if (v_r -> 'marcas' ->> 'cliente_ouviu')::boolean is not false then
    raise exception '16b: a linha pronto sem ouvir levou a marca';
  end if;

  -- ── 14. A foto de sombra conta por estado, sem as condições 6 e 7, e não gera nada ──
  select count(*) into v_antes from public.retorno_saidas;
  v_r := public.parceiro_estados_sombra(v_p, c_t);
  if coalesce((v_r -> 'estados' ->> 'em_servico')::integer, 0) < 2 or (v_r ->> 'total')::integer < 14
     or (select count(*) from public.retorno_saidas) is distinct from v_antes
     or exists (select 1 from public.parceiro_paineis pp where pp.parceiro_id = v_p) then
    raise exception '14: a foto de sombra (%)', v_r;
  end if;

  -- ── 21. Nunca derruba: a OS que dá exceção sai sozinha; todas fora, nenhum painel ──
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Quebra F4', 'RQB', 'revenda') returning id into v_px;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_px, 'Xena', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_c, '5547900015201', '00015201', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_nx;
  v_c := pg_temp.f4p_cliente('Tito Painel', '5547900015211');
  v_os10 := pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03');
  v_ix := pg_temp.f4p_liga(v_os10, v_px);
  insert into pg_temp._f4p_quebra values (v_os7), (v_os10);
  perform pg_temp.f4p_quebrar(true);
  v_linhas := public.parceiro_linhas(v_p, c_t);
  perform pg_temp.f4p_confere('21a OS quebrada', pg_temp.f4p_linha(v_linhas, v_i7), null, null, null, 'erro');
  perform pg_temp.f4p_confere('21b a outra segue', pg_temp.f4p_linha(v_linhas, v_i5), 'em_servico', null, null, null);
  v_r := public.parceiro_painel_montar(v_px, date '2027-01-14', '2027-01-14 17:30-03');
  if (v_r ->> 'gravado')::boolean is not false or exists (select 1 from public.parceiro_paineis pp where pp.parceiro_id = v_px) then
    raise exception '21c: com todas as linhas fora, gravou painel (%)', v_r;
  end if;
  perform pg_temp.f4p_quebrar(false);
  delete from pg_temp._f4p_quebra;
  perform pg_temp.f4p_confere('21d a troca foi desfeita', pg_temp.f4p_linha(public.parceiro_linhas(v_p, c_t), v_i7), 'andamento', '2027-01-08', null, null);

  -- ── 7 e 12. O leitor: cliente, parceiro, equipe e desconhecido (parceiro_modo em sombra) ──
  v_c := pg_temp.f4p_cliente('Quim Painel', '5547900014929');
  v_iq := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03'), v_p);
  v_msg := pg_temp.f4p_msg('5547900014929', 'NÃO RPF', c_t);
  v_r := public.parceiro_ler_mensagem(v_msg, c_t);
  if v_r is distinct from '{"consumida": true, "acao": "veto", "motivo": null}'::jsonb
     or not exists (select 1 from public.parceiro_vetos pv where pv.client_id = v_c and pv.parceiro_id = v_p and pv.whatsapp_message_id = v_msg) then
    raise exception '7a/12a: NÃO RPF do cliente (%)', v_r;
  end if;
  v_c := pg_temp.f4p_cliente('Rita Painel', '5547900014930');
  v_ir := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03'), v_p, 'indicou', null);
  perform pg_temp.f4p_aviso_enviado(v_ir, c_t - interval '2 hours');
  v_r := public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014930', 'Não, obrigado', c_t), c_t);
  if v_r is distinct from '{"consumida": false, "acao": "retido", "motivo": null}'::jsonb
     or (select oi.retido_em from public.os_interessados oi where oi.id = v_ir) is distinct from c_t then
    raise exception '7b/12b: a resposta que pode ser um não (%)', v_r;
  end if;
  v_r := public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014930', 'rpf', c_t), c_t);
  if v_r is distinct from '{"consumida": false, "acao": "nada", "motivo": null}'::jsonb then
    raise exception '7c/12c: a sigla sozinha fez algo (%)', v_r;
  end if;
  -- o parceiro: pátio, pausar e retomar consumidas; "voltar" não é palavra
  v_r := public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014901', 'Pátio', c_t), c_t);
  if (v_r ->> 'consumida')::boolean is not true or v_r ->> 'acao' is distinct from 'patio' then
    raise exception '7d: pátio do parceiro (%)', v_r;
  end if;
  v_msg := pg_temp.f4p_msg('5547900014901', 'pausar painel', c_t + interval '1 minute');
  v_r := public.parceiro_ler_mensagem(v_msg, c_t + interval '1 minute');
  if v_r is distinct from '{"consumida": true, "acao": "pausar", "motivo": null}'::jsonb
     or (select pe.pausado_em from public.parceiro_pessoas pe where pe.id = v_carla) is distinct from c_t + interval '1 minute'
     or not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_pausa' and s.variante = 'pausar'
                     and s.dedupe_key like 'parceiro:pausa:' || v_msg || '%') then
    raise exception '7e: pausar (%)', v_r;
  end if;
  v_msg := pg_temp.f4p_msg('5547900014901', 'retomar', c_t + interval '2 minutes');
  v_r := public.parceiro_ler_mensagem(v_msg, c_t + interval '2 minutes');
  if v_r ->> 'acao' is distinct from 'retomar' or (select pe.pausado_em from public.parceiro_pessoas pe where pe.id = v_carla) is not null
     or not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_pausa' and s.variante = 'retomar'
                     and s.dedupe_key like 'parceiro:pausa:' || v_msg || '%') then
    raise exception '7f: retomar (%)', v_r;
  end if;
  if public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014901', 'voltar', c_t), c_t) is distinct from '{"consumida": false, "acao": "nada", "motivo": null}'::jsonb then
    raise exception '7g: "voltar" virou palavra do parceiro';
  end if;
  if (public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014901', 'patio ' || repeat('x', 60), c_t), c_t) ->> 'consumida')::boolean is not false then
    raise exception '7h: mensagem acima de 60 caracteres foi lida';
  end if;
  -- equipe e desconhecido: nada
  insert into public.payees (name, kind, active, phone) values ('Equipe Painel F4', 'prestador', true, '5547900014990');
  if public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014990', 'pátio', c_t), c_t) ->> 'acao' is distinct from 'nada'
     or public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014998', 'nao rpf', c_t), c_t) ->> 'acao' is distinct from 'nada' then
    raise exception '7i: equipe ou desconhecido foram lidos';
  end if;
  -- parar não é consumido aqui (segue a F0b)
  if public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014929', 'parar', c_t + interval '5 minutes'), c_t + interval '5 minutes')
     is distinct from '{"consumida": false, "acao": "nada", "motivo": null}'::jsonb then
    raise exception '7j: parar foi consumido pelo leitor do parceiro';
  end if;

  -- ── 8, 9 e 26. O pátio pedido ──
  update public.retorno_config set patio_nivel = 'direto' where id;
  for v_k in 1 .. 3 loop
    v_r := public.parceiro_patio_pedido(v_n2, pg_temp.f4p_msg('5547900014902', 'patio', c_t + make_interval(mins => v_k)), c_t + make_interval(mins => v_k));
    if v_r ->> 'acao' is distinct from 'direto' then
      raise exception '8a: pátio direto nº % (%)', v_k, v_r;
    end if;
  end loop;
  select * into v_x from public.retorno_saidas s where s.id = (v_r ->> 'saida_id')::uuid;
  if v_x.variante is distinct from 'direto' or jsonb_array_length(v_x.dados -> 'linhas') is distinct from 12
     or jsonb_array_length(v_x.dados -> 'os_ids') is distinct from 12 or jsonb_array_length(v_x.dados -> 'interessado_ids') is distinct from 12
     or v_x.dados -> 'interessado_ids' ? v_i14::text then
    raise exception '8b/9b: o pátio direto (% linhas, anfitriã %)', jsonb_array_length(v_x.dados -> 'linhas'), v_x.dados -> 'interessado_ids' ? v_i14::text;
  end if;
  v_r := public.parceiro_patio_pedido(v_n2, pg_temp.f4p_msg('5547900014902', 'patio', c_t + interval '5 minutes'), c_t + interval '5 minutes');
  if v_r ->> 'acao' is distinct from 'recusada' or v_r ->> 'motivo' is distinct from 'teto_patio'
     or pg_temp.f4p_pegar(nullif(v_r ->> 'saida_id', '')::uuid, c_t + interval '5 minutes') is distinct from 'recusada/teto_patio' then
    raise exception '8c: o 4º pátio do dia (%)', v_r;
  end if;
  v_r := public.parceiro_patio_pedido(v_n3, pg_temp.f4p_msg('5547900014903', 'patio', '2027-01-14 22:30-03'), '2027-01-14 22:30-03');
  if v_r ->> 'motivo' is distinct from 'fora_da_janela' or (v_r ->> 'consumida')::boolean is not true then
    raise exception '8d: pátio às 22:30 (%)', v_r;
  end if;
  update public.retorno_config set segura_patio = true where id;
  v_r := public.parceiro_patio_pedido(v_n3, pg_temp.f4p_msg('5547900014903', 'patio', c_t + interval '6 minutes'), c_t + interval '6 minutes');
  if v_r ->> 'motivo' is distinct from 'segura_patio' then
    raise exception '8e: pátio com segura pátio (%)', v_r;
  end if;
  update public.retorno_config set segura_patio = false, patio_nivel = 'cartao' where id;
  -- 26. em cartao: dois pedidos do mesmo número no dia dão um item; válido até 21:59; às 22:00 nada é respondido
  v_msg := pg_temp.f4p_msg('5547900014903', 'ver patio', c_t + interval '7 minutes');
  v_r := public.parceiro_patio_pedido(v_n3, v_msg, c_t + interval '7 minutes');
  v_msg := pg_temp.f4p_msg('5547900014903', 'o patio', c_t + interval '1 hour');
  v_r := public.parceiro_patio_pedido(v_n3, v_msg, c_t + interval '1 hour');
  if v_r ->> 'acao' is distinct from 'cartao'
     or (select count(*) from public.parceiro_fila f where f.tipo = 'patio' and f.referencia = v_n3) is distinct from 1::bigint
     or (select f.dados ->> 'msg_id' from public.parceiro_fila f where f.chave = 'patio:' || v_n3 || ':2027-01-14') is distinct from v_msg::text
     or (select f.valido_ate from public.parceiro_fila f where f.chave = 'patio:' || v_n3 || ':2027-01-14') is distinct from '2027-01-14 21:59-03'::timestamptz
     or exists (select 1 from public.retorno_saidas s where s.dedupe_key like 'parceiro:patio:' || v_msg || '%') then
    raise exception '8f/26a: o pátio em cartao (%)', v_r;
  end if;
  v_msg := pg_temp.f4p_msg('5547900014903', 'patio', '2027-01-14 22:00-03');
  v_r := public.parceiro_patio_pedido(v_n3, v_msg, '2027-01-14 22:00-03');
  if v_r ->> 'motivo' is distinct from 'fora_da_janela'
     or exists (select 1 from public.retorno_saidas s where s.dedupe_key like 'parceiro:patio:' || v_msg || '%' and s.estado <> 'recusada') then
    raise exception '26b: pedido às 22:00 foi respondido (%)', v_r;
  end if;
  -- sem linhas: o vazio, em cartao e em direto
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Vazia F4', 'RVZ', 'revenda') returning id into v_pv;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pv, 'Vânia', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_c, '5547900015301', '00015301', '47', 'confirmado', c_t - interval '30 days') returning id into v_nv;
  v_r := public.parceiro_patio_pedido(v_nv, pg_temp.f4p_msg('5547900015301', 'patio', c_t), c_t);
  select * into v_x from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid;
  if v_r ->> 'acao' is distinct from 'vazio' or v_x.variante is distinct from 'vazio' or (v_x.dados ->> 'sem_linhas')::boolean is not true then
    raise exception '8g: sem linhas em cartao (%)', v_r;
  end if;
  update public.retorno_config set patio_nivel = 'direto' where id;
  if public.parceiro_patio_pedido(v_nv, pg_temp.f4p_msg('5547900015301', 'patio', c_t + interval '1 minute'), c_t + interval '1 minute') ->> 'acao'
     is distinct from 'vazio' then
    raise exception '8h: sem linhas em direto';
  end if;
  update public.retorno_config set patio_nivel = 'cartao' where id;

  -- ── 10 e 17. Pausado: o painel e o eco caem, o pátio continua; eco sem o cliente ouvir cai ──
  update public.parceiro_pessoas set pausado_em = c_t - interval '1 hour' where id = v_carla;
  v_s := public.parceiro_agendar('parceiro_painel', 'padrao', v_n1, null,
           jsonb_build_object('linhas', jsonb_build_array(jsonb_build_object('n', 1, 'interessado_id', v_i5, 'service_order_id', v_os5, 'estado', 'em_servico')),
                              'os_ids', jsonb_build_array(v_os5), 'interessado_ids', jsonb_build_array(v_i5)),
           '2027-01-15 17:50-03', 'parceiro:teste:painel:p10', 'resumo_parceiro');
  if pg_temp.f4p_pegar(v_s, '2027-01-15 17:50-03') is distinct from 'recusada/pausado' then
    raise exception '10a: o painel à pessoa pausada não caiu (%)', pg_temp.f4p_pegar(v_s, '2027-01-15 17:50-03');
  end if;
  update public.retorno_config set patio_nivel = 'direto' where id;
  v_r := public.parceiro_patio_pedido(v_n1, pg_temp.f4p_msg('5547900014901', 'patio', c_t + interval '3 hours'), c_t + interval '3 hours');
  if pg_temp.f4p_pegar((v_r ->> 'saida_id')::uuid, c_t + interval '3 hours') !~ '^(preparada|enviando)/' then
    raise exception '10b: o pátio da pessoa pausada não saiu (%)', v_r;
  end if;
  update public.retorno_config set patio_nivel = 'cartao' where id;
  update public.parceiro_pessoas set pausado_em = null where id = v_carla;
  v_s := public.parceiro_agendar('parceiro_eco', 'pronto', v_n2, null,
           jsonb_build_object('os_ids', jsonb_build_array(v_os2), 'interessado_ids', jsonb_build_array(v_i2), 'service_order_id', v_os2),
           c_t, 'parceiro:teste:painel:eco17', 'aviso');
  if pg_temp.f4p_pegar(v_s, c_t) is distinct from 'recusada/cliente_nao_ouviu' then
    raise exception '17: o eco sem o cliente ouvir (%)', pg_temp.f4p_pegar(v_s, c_t);
  end if;

  -- ── 6, 9, 10 e 13. O eco ──
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Eco F4', 'REC', 'revenda') returning id into v_pe;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pe, 'Eva', 'comercial') returning id into v_eva;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_eva, '5547900015101', '00015101', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_ne;
  v_e1 := pg_temp.f4p_cliente('Ada Eco', '5547900015111');
  v_eos1 := pg_temp.f4p_os(v_e1, 'completed');
  perform pg_temp.f4p_concluir(v_eos1, c_t - interval '10 hours');
  v_ie1 := pg_temp.f4p_liga(v_eos1, v_pe);
  v_e2 := pg_temp.f4p_cliente('Bia Eco', null);
  v_eos2 := pg_temp.f4p_os(v_e2, 'completed');
  perform pg_temp.f4p_concluir(v_eos2, c_t - interval '10 hours');
  insert into public.parceiro_cliente_sabe (service_order_id, marco, autor, em) values (v_eos2, 'pronto', v_dono, c_t - interval '1 hour');
  v_ie2 := pg_temp.f4p_liga(v_eos2, v_pe);
  v_e3 := pg_temp.f4p_cliente('Cris Eco', '5547900015113');
  v_eos3 := pg_temp.f4p_os(v_e3, 'open', null, '2027-01-08 15:00-03');
  perform pg_temp.f4p_ouviu(v_eos3, 'pode_atrasar', 'peca', c_t - interval '2 hours');
  v_ie3 := pg_temp.f4p_liga(v_eos3, v_pe);
  v_e4 := pg_temp.f4p_cliente('Davi Eco', '5547900015114');
  v_eos4 := pg_temp.f4p_os(v_e4, 'open', null, '2027-01-08 15:00-03');
  perform pg_temp.f4p_ouviu(v_eos4, 'material_chegou', null, c_t - interval '3 hours');
  v_ie4 := pg_temp.f4p_liga(v_eos4, v_pe);
  v_e5 := pg_temp.f4p_cliente('Enzo Eco', '5547900015115');
  v_eos5 := pg_temp.f4p_os(v_e5, 'open', null, '2027-01-08 15:00-03');
  perform pg_temp.f4p_ouviu(v_eos5, 'pode_atrasar', 'execucao', c_t - interval '2 hours');
  perform pg_temp.f4p_ouviu(v_eos5, 'pode_atrasar', 'remarcado', c_t - interval '90 minutes');
  perform pg_temp.f4p_ouviu(v_eos5, 'nova_data', null, c_t - interval '1 hour');
  v_ie5 := pg_temp.f4p_liga(v_eos5, v_pe);
  update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = array['parceiro_eco']::text[], eco_modo = 'sombra' where id;
  -- 13. o atraso só com pode_atrasar/peca
  if public._parceiro_cliente_ouviu(v_eos3, 'atraso', c_t) is null or public._parceiro_cliente_ouviu(v_eos5, 'atraso', c_t) is not null
     or public._parceiro_cliente_ouviu(v_eos5, 'peca_chegou', c_t) is not null then
    raise exception '13a: o marco atraso';
  end if;
  perform public.parceiro_eco_rodada(c_t);
  if not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_eco' and s.variante = 'atraso'
                  and s.dedupe_key = 'parceiro:eco:' || v_eos3 || ':atraso:2027-01-14:sombra')
     or not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_eco' and s.variante = 'peca_chegou'
                     and s.dados -> 'os_ids' ->> 0 = v_eos4::text and s.dedupe_key like '%:sombra')
     or exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_eco'
                 and s.dados -> 'os_ids' ->> 0 in (v_eos1::text, v_eos2::text, v_eos5::text, v_os14::text)) then
    raise exception '6a/9c/13b: o eco em sombra (antes de ouvir, sem telefone, atraso de execução ou anfitriã)';
  end if;
  -- depois de ouvir, o eco do pronto (em sombra, pelo eco_modo); a rodada seguinte não repete
  perform pg_temp.f4p_ouviu(v_eos1, 'pronto', null, c_t - interval '1 hour');
  perform public.parceiro_eco_rodada(c_t + interval '1 minute');
  if (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_eco' and s.dados -> 'os_ids' ->> 0 = v_eos1::text
        and s.dedupe_key = 'parceiro:eco:' || v_eos1 || ':pronto:2027-01-14:sombra') is distinct from 1::bigint
     or (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_eco' and s.dados -> 'os_ids' ->> 0 in (v_eos3::text, v_eos4::text))
        is distinct from 2::bigint then
    raise exception '6b: o eco depois de ouvir, uma vez';
  end if;
  -- eco_modo ligado: as reais nascem; o 3º do dia cai em teto_eco
  update public.retorno_config set eco_modo = 'ligado' where id;
  update public.retorno_saidas set estado = 'cancelada', motivo = 'substituida', decidida_em = c_t
   where emissor = 'parceiro' and estado = 'agendada';
  perform public.parceiro_eco_rodada(c_t + interval '2 minutes');
  if (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_eco' and s.dados ->> 'parceiro_id' = v_pe::text
        and s.dedupe_key !~ ':sombra' and s.estado = 'agendada') is distinct from 3::bigint then
    raise exception '6c: as três reais do eco';
  end if;
  update public.retorno_saidas set estado = 'cancelada', motivo = 'substituida', decidida_em = c_t
   where emissor = 'parceiro' and estado = 'agendada' and dados ->> 'parceiro_id' is distinct from v_pe::text;
  for v_k in 1 .. 3 loop
    update public.retorno_config set proximo_envio_em = null where id;
    perform public.parceiro_pegar(c_t + interval '2 minutes');
  end loop;
  if (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_eco' and s.dados ->> 'parceiro_id' = v_pe::text
        and s.estado = 'enviando') is distinct from 2::bigint
     or (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_eco' and s.dados ->> 'parceiro_id' = v_pe::text
           and s.estado = 'recusada' and s.motivo = 'teto_eco') is distinct from 1::bigint then
    raise exception '6d: o teto do eco no dia';
  end if;
  -- 10. a pessoa pausada: o eco cai
  update public.parceiro_pessoas set pausado_em = c_t where id = v_eva;
  v_s := public.parceiro_agendar('parceiro_eco', 'peca_chegou', v_ne, null,
           jsonb_build_object('os_ids', jsonb_build_array(v_eos4), 'interessado_ids', jsonb_build_array(v_ie4), 'service_order_id', v_eos4),
           c_t + interval '3 minutes', 'parceiro:teste:painel:eco10', 'aviso');
  if pg_temp.f4p_pegar(v_s, c_t + interval '3 minutes') is distinct from 'recusada/pausado' then
    raise exception '10c: o eco à pessoa pausada não caiu';
  end if;
  update public.parceiro_pessoas set pausado_em = null where id = v_eva;
  update public.retorno_config set parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', eco_modo = 'sombra' where id;

  -- ── 4, 5 e 15. O painel do dia ──
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Quatro F4', 'RQT', 'revenda') returning id into v_p4;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p4, 'Quitéria', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_c, '5547900015001', '00015001', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n4;
  v_i4a := pg_temp.f4p_liga(pg_temp.f4p_os(pg_temp.f4p_cliente('Rui Painel', '5547900015011'), 'open', null, '2027-01-04 15:00-03'), v_p4);
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Cinco F4', 'RCI', 'revenda') returning id into v_p5;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p5, 'Cíntia', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_c, '5547900015401', '00015401', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n5;
  v_i5a := pg_temp.f4p_liga(pg_temp.f4p_os(pg_temp.f4p_cliente('Tom Painel', '5547900015411'), 'open', null, '2027-01-08 15:00-03'), v_p5);
  v_todos := array(select pa.id from public.parceiros pa where pa.id in (v_p, v_p4, v_p5, v_pe, v_pv, v_px));

  -- 4. sozinho e com o tipo ligado: seg aprovado (e enviado); ter sem mudança e sem saída; sex sai mesmo sem mudança;
  --    feriado, nada
  update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = array['parceiro_painel']::text[], painel_nivel = 'sozinho' where id;
  v_r := public.parceiro_painel_montar(v_p4, date '2027-01-11', '2027-01-11 17:30-03');
  if v_r ->> 'estado' is distinct from 'aprovado' or (v_r ->> 'mudou')::boolean is not true then
    raise exception '4a: o 1º painel (%)', v_r;
  end if;
  update public.parceiro_paineis set estado = 'enviado' where id = (v_r ->> 'painel_id')::uuid;
  v_r := public.parceiro_painel_montar(v_p4, date '2027-01-12', '2027-01-12 17:30-03');
  v_painel := (v_r ->> 'painel_id')::uuid;
  perform pg_temp.f4p_so(v_p4, v_todos);
  perform public.parceiro_painel_rodada('2027-01-12 17:50-03');
  perform pg_temp.f4p_so(null, v_todos);
  if v_r ->> 'estado' is distinct from 'sem_mudanca' or (v_r ->> 'mudou')::boolean is not false
     or exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_painel' and s.dados ->> 'painel_id' = v_painel::text) then
    raise exception '4b: sem mudança (%)', v_r;
  end if;
  v_r := public.parceiro_painel_montar(v_p4, date '2027-01-15', '2027-01-15 17:30-03');
  v_painel := (v_r ->> 'painel_id')::uuid;
  perform pg_temp.f4p_so(v_p4, v_todos);
  perform public.parceiro_painel_rodada('2027-01-15 17:50-03');
  perform pg_temp.f4p_so(null, v_todos);
  if v_r ->> 'estado' is distinct from 'aprovado' or (v_r ->> 'mudou')::boolean is not false
     or not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_painel' and s.dados ->> 'painel_id' = v_painel::text
                     and s.dedupe_key = 'parceiro:painel:' || v_painel || ':' || v_n4) then
    raise exception '4c: a sexta sem mudança não saiu (%)', v_r;
  end if;
  if public.parceiro_painel_montar(v_p4, date '2027-01-01', '2027-01-01 17:30-03') ->> 'motivo' is distinct from 'dia_nao_util'
     or exists (select 1 from public.parceiro_paineis pp where pp.parceiro_id = v_p4 and pp.dia = date '2027-01-01') then
    raise exception '4d: painel no feriado';
  end if;

  -- 5. fechamento: aguardando com o item na fila; sem resposta até 18:30, vencido e sem saída
  update public.retorno_config set painel_nivel = 'fechamento' where id;
  perform pg_temp.f4p_so(v_p5, v_todos);
  perform public.parceiro_painel_rodada('2027-01-13 17:30-03');
  select * into v_pp from public.parceiro_paineis pp where pp.parceiro_id = v_p5 and pp.dia = date '2027-01-13';
  if v_pp.estado is distinct from 'aguardando'
     or not exists (select 1 from public.parceiro_fila f where f.chave = 'painel:' || v_pp.id and f.tipo = 'painel'
                     and f.valido_ate = '2027-01-13 18:30-03'::timestamptz) then
    raise exception '5a: o painel aguardando (%)', v_pp.estado;
  end if;
  perform public.parceiro_painel_rodada('2027-01-13 18:00-03');
  perform public.parceiro_painel_rodada('2027-01-13 18:30-03');
  if (select pp.estado from public.parceiro_paineis pp where pp.id = v_pp.id) is distinct from 'vencido'
     or exists (select 1 from public.retorno_saidas s where s.dados ->> 'painel_id' = v_pp.id::text) then
    raise exception '5b: o aguardando não venceu ou saiu';
  end if;
  -- 15. ligado sem o tipo: sombra, sem item no cartão
  update public.retorno_config set parceiro_tipos_ligados = '{}' where id;
  v_r := public.parceiro_painel_montar(v_p5, date '2027-01-14', '2027-01-14 17:30-03');
  if v_r ->> 'estado' is distinct from 'sombra'
     or exists (select 1 from public.parceiro_fila f where f.chave = 'painel:' || (v_r ->> 'painel_id')) then
    raise exception '15a: ligado sem o tipo (%)', v_r;
  end if;
  -- 15. aprovado às 18:00: a saída é agendada e sai antes de 18:30
  update public.retorno_config set parceiro_tipos_ligados = array['parceiro_painel']::text[] where id;
  v_r := public.parceiro_painel_montar(v_p5, date '2027-01-15', '2027-01-15 17:30-03');
  update public.parceiro_paineis set estado = 'aprovado', aprovado_em = '2027-01-15 18:00-03' where id = (v_r ->> 'painel_id')::uuid;
  perform public.parceiro_painel_rodada('2027-01-15 18:00-03');
  perform pg_temp.f4p_so(null, v_todos);
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:painel:' || (v_r ->> 'painel_id') || ':' || v_n5;
  if v_r ->> 'estado' is distinct from 'aguardando' or v_x.id is null
     or pg_temp.f4p_pegar(v_x.id, '2027-01-15 18:00-03') is distinct from 'enviando/' then
    raise exception '15b: o aprovado às 18:00 não saiu (% %)', v_r, v_x.estado;
  end if;
  update public.retorno_config set parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', painel_nivel = 'fechamento' where id;

  -- ── 23. *1 tira 2*: a linha sai do texto, e o n das outras não muda ──
  v_r := public.parceiro_painel_montar(v_p, date '2027-01-14', '2027-01-14 17:30-03');
  v_painel := (v_r ->> 'painel_id')::uuid;
  select * into v_pp from public.parceiro_paineis pp where pp.id = v_painel;
  if v_r ->> 'estado' is distinct from 'sombra' then
    raise exception '23c: o painel da RPF em sombra (%)', v_r;
  end if;
  v_l := (select l from jsonb_array_elements(v_pp.linhas) l where (l ->> 'n')::integer = 2);
  perform public._parceiro_painel_marcar(v_painel, jsonb_build_array(jsonb_build_object('interessado_id', v_l ->> 'interessado_id', 'fora_por', 'tirada')));
  if (select array_agg((l ->> 'n')::integer order by (l ->> 'n')::integer) from public.parceiro_paineis pp, jsonb_array_elements(pp.linhas) l
       where pp.id = v_painel and l ->> 'n' is not null) is distinct from (select array_agg((l ->> 'n')::integer order by (l ->> 'n')::integer)
                                                                         from jsonb_array_elements(v_pp.linhas) l where l ->> 'n' is not null) then
    raise exception '23d: tirar renumerou as linhas';
  end if;
  perform public.parceiro_painel_rodada('2027-01-14 17:50-03');
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:painel:' || v_painel || ':' || v_n1 || ':sombra';
  if v_x.id is null or v_x.dados -> 'interessado_ids' ? (v_l ->> 'interessado_id')
     or jsonb_array_length(v_x.dados -> 'linhas') is distinct from (select count(*)::integer - 1 from jsonb_array_elements(v_pp.linhas) l where l ->> 'n' is not null) then
    raise exception '23e: a saída do painel levou a linha tirada';
  end if;
  if pg_temp.f4p_pegar(v_x.id, '2027-01-14 17:50-03') is distinct from 'preparada/'
     or (select s.texto from public.retorno_saidas s where s.id = v_x.id) !~ E'\n1\\. '
     or (select s.texto from public.retorno_saidas s where s.id = v_x.id) ~ E'\n12\\. ' then
    raise exception '23f: o texto do painel não renumerou de 1 a k';
  end if;

  -- ── 18. Sombra → ligado da ativação: 1 linha :sombra, depois 1 real, e não outra ──
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Ativa F4', 'RAT', 'revenda') returning id into v_pa;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pa, 'Telma', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_c, '5547900015501', '00015501', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_na;
  perform public.parceiro_ativacao_rodada(c_t);
  perform public.parceiro_ativacao_rodada(c_t + interval '1 minute');
  if (select count(*) from public.retorno_saidas s where s.dedupe_key = 'parceiro:ativacao:' || v_na || ':sombra') is distinct from 1::bigint
     or exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'parceiro:ativacao:' || v_na) then
    raise exception '18a: a ativação em sombra';
  end if;
  update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = array['parceiro_ativacao']::text[] where id;
  perform public.parceiro_ativacao_rodada(c_t + interval '2 minutes');
  perform public.parceiro_ativacao_rodada(c_t + interval '3 minutes');
  if (select count(*) from public.retorno_saidas s where s.dedupe_key = 'parceiro:ativacao:' || v_na) is distinct from 1::bigint
     or (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_ativacao' and s.dados ->> 'numero_id' = v_na::text) is distinct from 2::bigint then
    raise exception '18b: sombra → ligado da ativação';
  end if;
  begin
    perform public.parceiro_ativar(v_pa, gen_random_uuid(), c_t);
    raise exception '18c: quem não é o dono ativou';
  exception when sqlstate '42501' then
    null;
  end;
  update public.retorno_config set parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}' where id;

  -- ── 25. A releitura do veto: só a linha do veto, sem duplicar, em qualquer modo ──
  v_c := pg_temp.f4p_cliente('Tais Painel', '5547900014932');
  v_it := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03'), v_p);
  v_msg := pg_temp.f4p_msg('5547900014932', 'não rpf', '2027-01-14 16:00-03');
  perform pg_temp.f4p_msg('5547900014901', 'patio', '2027-01-14 16:00-03');
  perform pg_temp.f4p_msg('5547900014901', 'pausar', '2027-01-14 16:01-03');
  select count(*) into v_antes from public.retorno_saidas s where s.tipo in ('parceiro_patio', 'parceiro_pausa');
  v_r := public.parceiro_reler_vetos('2027-01-14 16:02-03');
  if not exists (select 1 from public.parceiro_vetos pv where pv.client_id = v_c and pv.parceiro_id = v_p and pv.whatsapp_message_id = v_msg)
     or (select pe.pausado_em from public.parceiro_pessoas pe where pe.id = v_carla) is not null
     or (select count(*) from public.retorno_saidas s where s.tipo in ('parceiro_patio', 'parceiro_pausa')) is distinct from v_antes then
    raise exception '25a: a releitura (%)', v_r;
  end if;
  select count(*) into v_antes from public.parceiro_vetos;
  perform public.parceiro_reler_vetos('2027-01-14 16:03-03');
  if (select count(*) from public.parceiro_vetos) is distinct from v_antes then
    raise exception '25b: reler de novo duplicou';
  end if;
  update public.retorno_config set parceiro_modo = 'desligado' where id;
  v_c := pg_temp.f4p_cliente('Ugo Painel', '5547900014933');
  v_iu := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03'), v_p);
  perform pg_temp.f4p_msg('5547900014933', 'nao quero a rpf', '2027-01-14 16:10-03');
  perform public.parceiro_reler_vetos('2027-01-14 16:11-03');
  if not exists (select 1 from public.parceiro_vetos pv where pv.client_id = v_c and pv.parceiro_id = v_p) then
    raise exception '25c: a releitura com parceiro_modo desligado';
  end if;

  -- ── 11. Desligado: as palavras do parceiro não são lidas; o NÃO RPF veta, consome e não responde; ao religar a OS não
  --    volta ──
  if (public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014901', 'patio', c_t), c_t) ->> 'consumida')::boolean is not false
     or (public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014901', 'pausar', c_t), c_t) ->> 'consumida')::boolean is not false
     or (public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014901', 'retomar', c_t), c_t) ->> 'consumida')::boolean is not false then
    raise exception '11a: palavra do parceiro lida com a F4 desligada';
  end if;
  v_c := pg_temp.f4p_cliente('Sara Painel', '5547900014931');
  v_is := pg_temp.f4p_liga(pg_temp.f4p_os(v_c, 'open', null, '2027-01-08 15:00-03'), v_p);
  v_r := public.parceiro_ler_mensagem(pg_temp.f4p_msg('5547900014931', 'NÃO RPF', c_t + interval '4 hours'), c_t + interval '4 hours');
  if v_r is distinct from '{"consumida": true, "acao": "veto", "motivo": null}'::jsonb
     or exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_nao_mp_ok' and s.dados ->> 'client_id' = v_c::text) then
    raise exception '11b: NÃO RPF com a F4 desligada (%)', v_r;
  end if;
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  if public.parceiro_os_visivel(v_is, c_t + interval '5 hours') ->> 'motivo' is distinct from 'veto'
     or pg_temp.f4p_linha(public.parceiro_linhas(v_p, c_t + interval '5 hours'), v_is) is not null then
    raise exception '11c: ao religar, a OS vetada voltou';
  end if;

  -- ── O vigia: desligado só relê o veto; fora dele, cada passo roda sem erro, e os de onda posterior ficam de fora ──
  update public.retorno_config set parceiro_modo = 'desligado' where id;
  v_r := public.parceiro_vigia(c_t + interval '6 hours');
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'modo' is distinct from 'desligado' or not (v_r -> 'passos' ? 'reler_vetos')
     or v_r -> 'passos' ? 'aviso' then
    raise exception 'vigia a: desligado (%)', v_r;
  end if;
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  v_r := public.parceiro_vigia(c_t + interval '6 hours');
  if (v_r ->> 'ok')::boolean is not true or jsonb_array_length(v_r -> 'erros') is distinct from 0
     or not (v_r -> 'passos' ?& array['reler_vetos', 'aviso', 'ativacao', 'painel', 'eco'])
     or (to_regprocedure('public.parceiro_vigia_cartao(timestamptz)') is null and v_r -> 'passos' ? 'cartao')
     or (to_regprocedure('public.parceiro_pedido_rodada(timestamptz)') is null and v_r -> 'passos' ? 'pedido') then
    raise exception 'vigia b: em sombra (%)', v_r;
  end if;

  -- ── Respostas de 09/11, R2 (F4-14): o veículo que não começou. Com parceiro_sem_inicio_ligado falsa (o padrão), as
  --    linhas, o painel e o pátio saem byte a byte como antes; ligada, open, approved, scheduled e awaiting_client sem data
  --    dão sem_inicio ("aguardando o início do serviço", n depois de andamento_sem_data); awaiting_parts sem data continua
  --    fora, a data vence (linha 6) e o rascunho segue a regra 8 e a linha 5. Números de OS OS-TF4R-2x; telefones 176xx ──
  update public.retorno_config set parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', patio_nivel = 'cartao', segura_patio = false
   where id;
  if (select c.parceiro_sem_inicio_ligado from public.retorno_config c where c.id) is not false then
    raise exception 'R2a: parceiro_sem_inicio_ligado não nasceu falsa';
  end if;
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Inicio F4', 'RIN', 'revenda') returning id into v_pr;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pr, 'Iolanda', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_c, '5547900017601', '00017601', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_nr;
  v_ri := array[
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Abel Inicio', '5547900017611'), 'OS-TF4R-21', 'open'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Bia Inicio', '5547900017612'), 'OS-TF4R-22', 'approved'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Ciro Inicio', '5547900017613'), 'OS-TF4R-23', 'scheduled'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Duda Inicio', '5547900017614'), 'OS-TF4R-24', 'awaiting_client'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Enzo Inicio', '5547900017615'), 'OS-TF4R-25', 'awaiting_parts'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Fabi Inicio', '5547900017616'), 'OS-TF4R-26', 'open', null,
                                      '2027-01-08 15:00-03'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Gil Inicio', '5547900017617'), 'OS-TF4R-27', 'in_progress'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Hana Inicio', '5547900017618'), 'OS-TF4R-28', 'draft', null, null,
                                      'draft'), v_pr),
    pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Ivo Inicio', '5547900017619'), 'OS-TF4R-29', 'draft', null, null,
                                      'draft', v_pr), v_pr)];

  -- Desligada: as linhas são exatamente as de antes (8 chaves, os 4 status e o awaiting_parts fora por sem_fato)
  v_esperado := pg_temp.f4p_ordem(array[
    pg_temp.f4p_antes(v_ri[9], 1, 'orcamento', null, null),
    pg_temp.f4p_antes(v_ri[6], 2, 'andamento', date '2027-01-08', null),
    pg_temp.f4p_antes(v_ri[7], 3, 'andamento_sem_data', null, null),
    pg_temp.f4p_antes(v_ri[1], null, null, null, 'sem_fato'),
    pg_temp.f4p_antes(v_ri[2], null, null, null, 'sem_fato'),
    pg_temp.f4p_antes(v_ri[3], null, null, null, 'sem_fato'),
    pg_temp.f4p_antes(v_ri[4], null, null, null, 'sem_fato'),
    pg_temp.f4p_antes(v_ri[5], null, null, null, 'sem_fato')]);
  v_linhas := public.parceiro_linhas(v_pr, c_t);
  if v_linhas is distinct from v_esperado then
    raise exception 'R2b: com a chave desligada, as linhas mudaram (veio %, esperava %)', v_linhas, v_esperado;
  end if;
  -- o painel do dia, pelo caminho real (montar, rodada e pegar), byte a byte
  v_r := public.parceiro_painel_montar(v_pr, date '2027-01-14', '2027-01-14 17:30-03');
  v_painel := (v_r ->> 'painel_id')::uuid;
  if v_r ->> 'estado' is distinct from 'sombra'
     or (select pp.linhas from public.parceiro_paineis pp where pp.id = v_painel) is distinct from v_esperado then
    raise exception 'R2c: o painel do dia com a chave desligada (%)', v_r;
  end if;
  perform pg_temp.f4p_so(v_pr, v_todos);
  perform public.parceiro_painel_rodada('2027-01-14 17:50-03');
  perform pg_temp.f4p_so(null, v_todos);
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:painel:' || v_painel || ':' || v_nr || ':sombra';
  if v_x.id is null or v_x.dados -> 'linhas' is distinct from pg_temp.f4p_copia_antes(v_esperado) then
    raise exception 'R2d: a saída do painel copiou as linhas diferente (%)', v_x.dados -> 'linhas';
  end if;
  -- (às 17:55, depois da reserva de 2 min do painel da RPF, que o item 23 preparou às 17:50)
  v_t := pg_temp.f4p_pegar(v_x.id, '2027-01-14 17:55-03');
  v_texto := (select s.texto from public.retorno_saidas s where s.id = v_x.id);
  if v_t is distinct from 'preparada/'
     or v_texto is distinct from E'Pátio HBR · qui (14/01)\n1. Motorhome de Ivo I.: orçamento pedido por vocês; com o Gustavo.\n2. Motorhome de Fabi I.: sem novidade desde 08/01.\n3. Motorhome de Gil I.: em serviço.\nPara ver de novo, mande *pátio*.\nValores e dados ficam com cada cliente.' then
    raise exception 'R2e: o painel saiu diferente com a chave desligada (% / %)', v_t, v_texto;
  end if;
  -- o pátio direto, byte a byte
  update public.retorno_config set patio_nivel = 'direto' where id;
  v_r := public.parceiro_patio_pedido(v_nr, pg_temp.f4p_msg('5547900017601', 'patio', c_t), c_t);
  select * into v_x from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid;
  if v_r ->> 'acao' is distinct from 'direto' or v_x.dados -> 'linhas' is distinct from pg_temp.f4p_copia_antes(v_esperado)
     or public._parceiro_painel_texto('parceiro_patio', 'direto', v_x.dados -> 'linhas', 0, date '2027-01-14', false) ->> 'texto'
        is distinct from E'Pátio HBR · 14/01\n1. Motorhome de Ivo I.: orçamento pedido por vocês; com o Gustavo.\n2. Motorhome de Fabi I.: sem novidade desde 08/01.\n3. Motorhome de Gil I.: em serviço.' then
    raise exception 'R2f: o pátio saiu diferente com a chave desligada (% / %)', v_r, v_x.dados -> 'linhas';
  end if;

  -- Ligada: os 4 status sem data dão sem_inicio; awaiting_parts sem data fica fora; a data vence; o rascunho de fora não entra
  update public.retorno_config set parceiro_sem_inicio_ligado = true where id;
  v_linhas := public.parceiro_linhas(v_pr, c_t);
  perform pg_temp.f4p_confere('R2g open', pg_temp.f4p_linha(v_linhas, v_ri[1]), 'sem_inicio', null, null, null);
  perform pg_temp.f4p_confere('R2g approved', pg_temp.f4p_linha(v_linhas, v_ri[2]), 'sem_inicio', null, null, null);
  perform pg_temp.f4p_confere('R2g scheduled', pg_temp.f4p_linha(v_linhas, v_ri[3]), 'sem_inicio', null, null, null);
  perform pg_temp.f4p_confere('R2g awaiting_client', pg_temp.f4p_linha(v_linhas, v_ri[4]), 'sem_inicio', null, null, null);
  perform pg_temp.f4p_confere('R2g awaiting_parts sem data', pg_temp.f4p_linha(v_linhas, v_ri[5]), null, null, null, 'sem_fato');
  perform pg_temp.f4p_confere('R2g com data, a linha 6', pg_temp.f4p_linha(v_linhas, v_ri[6]), 'andamento', '2027-01-08', null, null);
  perform pg_temp.f4p_confere('R2g in_progress', pg_temp.f4p_linha(v_linhas, v_ri[7]), 'andamento_sem_data', null, null, null);
  perform pg_temp.f4p_confere('R2g rascunho do parceiro', pg_temp.f4p_linha(v_linhas, v_ri[9]), 'orcamento', null, null, null);
  if pg_temp.f4p_linha(v_linhas, v_ri[8]) is not null then
    raise exception 'R2g: o rascunho fora da regra 8 entrou na linha';
  end if;
  if (select array_agg(l ->> 'interessado_id' order by (l ->> 'n')::integer) from jsonb_array_elements(v_linhas) l
       where l ->> 'fora_por' is null)
     is distinct from array[v_ri[9], v_ri[6], v_ri[7], v_ri[1], v_ri[2], v_ri[3], v_ri[4]]::text[] then
    raise exception 'R2h: a ordem com sem_inicio (n 8, depois de andamento_sem_data) (%)', v_linhas;
  end if;
  if exists (select 1 from jsonb_array_elements(v_linhas) l, jsonb_object_keys(l) k
              where k not in ('n', 'interessado_id', 'service_order_id', 'estado', 'desde', 'rotulo', 'retida_por', 'fora_por')) then
    raise exception 'R2h: a linha sem_inicio tem chave fora da lista positiva';
  end if;
  v_texto := public._parceiro_painel_texto('parceiro_painel', 'padrao', pg_temp.f4p_copia_antes(v_linhas), 0, date '2027-01-14', false)
             ->> 'texto';
  if v_texto is distinct from E'Pátio HBR · qui (14/01)\n1. Motorhome de Ivo I.: orçamento pedido por vocês; com o Gustavo.\n2. Motorhome de Fabi I.: sem novidade desde 08/01.\n3. Motorhome de Gil I.: em serviço.\n4. Motorhome de Abel I.: aguardando o início do serviço.\n5. Motorhome de Bia I.: aguardando o início do serviço.\n6. Motorhome de Ciro I.: aguardando o início do serviço.\n7. Motorhome de Duda I.: aguardando o início do serviço.\nPara ver de novo, mande *pátio*.' then
    raise exception 'R2i: o texto com sem_inicio (%)', v_texto;
  end if;
  v_r := public.parceiro_patio_pedido(v_nr, pg_temp.f4p_msg('5547900017601', 'patio', c_t + interval '1 minute'), c_t + interval '1 minute');
  select * into v_x from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid;
  if v_r ->> 'acao' is distinct from 'direto'
     or (select count(*) from jsonb_array_elements(v_x.dados -> 'linhas') l where l ->> 'estado' = 'sem_inicio') is distinct from 4::bigint then
    raise exception 'R2j: o pátio direto sem as linhas sem_inicio (%)', v_r;
  end if;
  v_r := public.parceiro_estados_sombra(v_pr, c_t);
  if (v_r -> 'estados' ->> 'sem_inicio')::integer is distinct from 4 or (v_r -> 'estados' ->> 'fora_sem_fato')::integer is distinct from 1
     or (v_r ->> 'total')::integer is distinct from 8 then
    raise exception 'R2k: a foto de sombra com sem_inicio (%)', v_r;
  end if;

  -- Desligada de novo: as linhas voltam a ser as de antes, e a linha sem_inicio que já estava numa saída não tem texto (22023,
  -- e o parceiro_pegar a tira com fora_por = 'texto')
  update public.retorno_config set parceiro_sem_inicio_ligado = false where id;
  if public.parceiro_linhas(v_pr, c_t) is distinct from v_esperado then
    raise exception 'R2l: desligar de novo não voltou às linhas de antes';
  end if;
  begin
    perform public._parceiro_texto('parceiro_painel', 'linha', '{"n": 4, "bem": "motorhome", "cliente": "Abel I.", "estado": "sem_inicio"}'::jsonb);
    raise exception 'R2m: a linha sem_inicio teve texto com a chave desligada';
  exception when sqlstate '22023' then
    null;
  end;
  update public.retorno_config set patio_nivel = 'cartao' where id;

  -- ── Respostas de 09/11, R1 (F4-07): a etapa na linha em_servico. Com as duas chaves desligadas (o padrão), as linhas, o
  --    painel, o pátio e o bloco P11 saem byte a byte como antes, mesmo com a etapa no fato; com parceiro_etapa_ligada, só a
  --    etapa que passa em _parceiro_etapa_ok sai, "em serviço hoje ({etapa})". Números de OS OS-TF4R-01 a 11; telefones
  --    5547900017602 e 55479000176(31 a 41) ──
  update public.retorno_config
     set parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', patio_nivel = 'cartao', segura_patio = false,
         parceiro_sem_inicio_ligado = false
   where id;
  if (select c.parceiro_etapa_ligada from public.retorno_config c where c.id) is not false then
    raise exception 'R1a: parceiro_etapa_ligada não nasceu falsa';
  end if;

  -- _parceiro_etapa_ok, regra a regra (as 4 últimas são o desvio: o validador não vê dia, pronto e avisado dentro da etapa)
  for v_rec in
    select * from (values
      ('instalação do painel solar', '{}'::text[], 'instalação do painel solar'),
      ('Instalação do painel solar', '{}', 'instalação do painel solar'),
      ('  Teste final,  ajustes e limpeza ', '{}', 'teste final, ajustes e limpeza'),
      ('Elétrica - quadro/disjuntores', '{}', 'elétrica - quadro/disjuntores'),
      (v_etapa60, '{}', 'r' || substr(v_etapa60, 2)),
      (rpad('Revisão geral', 61, ' da cabine'), '{}', null),
      ('Troca de 2 baterias', '{}', null),
      (E'Pintura\nda lateral', '{}', null),
      (E'Pintura\tda lateral', '{}', null),
      ('Revisão (geral)', '{}', null),
      ('Contato pelo @', '{}', null),
      ('Pagar R$ na entrega', '{}', null),
      ('"Revisão"', '{}', null),
      ('', '{}', null),
      ('   ', '{}', null),
      (null, '{}', null),
      ('Conferência com Zeca', array['Ana B.', 'Zeca F.'], null),
      ('Conferência com Zeca', array['Ana B.'], 'conferência com Zeca'),
      ('Ajuste pedido pelo JOÃO', array['João S.'], null),
      ('Ajuste do joão', null, null),
      ('Entrega na sexta', '{}', null),
      ('Revisão de março', '{}', null),
      ('Pronto para pintura', '{}', null),
      ('Troca com o cliente já avisado', '{}', null),
      ('Almoço ao meio-dia', '{}', null)
    ) as x(etapa, nomes, esperado)
  loop
    if public._parceiro_etapa_ok(v_rec.etapa, v_rec.nomes) is distinct from v_rec.esperado then
      raise exception 'R1b: _parceiro_etapa_ok(%, %) deu % (esperava %)', v_rec.etapa, v_rec.nomes,
        public._parceiro_etapa_ok(v_rec.etapa, v_rec.nomes), v_rec.esperado;
    end if;
  end loop;

  -- Arranjo: dez OS em serviço hoje (check-in às 08:00), cada uma com a etapa do dia; a 8ª sem tarefa (etapa nula). O Zeca é
  -- cliente da RET vetado: entra em nomes_de_outros e nunca na linha.
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Etapa F4', 'RET', 'revenda') returning id into v_pt;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pt, 'Eunice', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_c, '5547900017602', '00017602', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_nt;
  for v_rec in
    select * from (values
      (1, 'João Sales', 'Instalação do painel solar'),
      (2, 'Kauê Etapa', 'Troca de 2 baterias'),
      (3, 'Lia Etapa', rpad('Revisão geral', 61, ' da cabine')),
      (4, 'Mel Etapa', E'Pintura\nda lateral'),
      (5, 'Nico Etapa', 'Revisão (geral)'),
      (6, 'Olga Etapa', 'Conferência com Zeca'),
      (7, 'Pita Etapa', 'Ajuste pedido por Pita'),
      (8, 'Quico Etapa', null),
      (9, 'Rafa Etapa', 'Entrega na sexta'),
      (10, 'Teo Etapa', v_etapa60)
    ) as x(k, nome, etapa)
    order by x.k
  loop
    v_ot := pg_temp.f4p_os_n(pg_temp.f4p_cliente(v_rec.nome, '55479000176' || (30 + v_rec.k)), 'OS-TF4R-' || lpad(v_rec.k::text, 2, '0'),
                             'in_progress', c_t - interval '2 hours');
    if v_rec.etapa is not null then
      perform pg_temp.f4p_etapa(v_ot, v_rec.etapa, date '2027-01-14');
    end if;
    v_ti := v_ti || pg_temp.f4p_liga(v_ot, v_pt);
  end loop;
  v_iz := pg_temp.f4p_liga(pg_temp.f4p_os_n(pg_temp.f4p_cliente('Zeca Fora', '5547900017641'), 'OS-TF4R-11', 'open', null,
                                            '2027-01-08 15:00-03'), v_pt);
  update public.os_interessados set veto_do_cliente_em = c_t - interval '3 days' where id = v_iz;
  -- a etapa está no fato (a F2 já a calcula): só a chave a separa da linha
  if public._parceiro_fato_da_os((select oi.service_order_id from public.os_interessados oi where oi.id = v_ti[1]), c_t)
       -> 'fatos' -> 'em_servico' ->> 'etapa' is distinct from 'Instalação do painel solar' then
    raise exception 'R1c: a etapa não está no fato da OS';
  end if;

  -- As duas chaves desligadas: as linhas, o painel (caminho real), o pátio direto e o bloco P11 byte a byte como antes
  v_esperado := pg_temp.f4p_ordem(array(select pg_temp.f4p_antes(v_ti[k], k, 'em_servico', null, null) from generate_series(1, 10) k));
  v_linhas := public.parceiro_linhas(v_pt, c_t);
  if v_linhas is distinct from v_esperado then
    raise exception 'R1d: com as chaves desligadas, as linhas mudaram (veio %, esperava %)', v_linhas, v_esperado;
  end if;
  v_r := public.parceiro_painel_montar(v_pt, date '2027-01-14', '2027-01-14 17:30-03');
  v_painel := (v_r ->> 'painel_id')::uuid;
  if v_r ->> 'estado' is distinct from 'sombra'
     or (select pp.linhas from public.parceiro_paineis pp where pp.id = v_painel) is distinct from v_esperado then
    raise exception 'R1e: o painel do dia com as chaves desligadas (%)', v_r;
  end if;
  perform pg_temp.f4p_so(v_pt, v_todos || v_pr);
  perform public.parceiro_painel_rodada('2027-01-14 17:50-03');
  perform pg_temp.f4p_so(null, v_todos || v_pr);
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:painel:' || v_painel || ':' || v_nt || ':sombra';
  if v_x.id is null or v_x.dados -> 'linhas' is distinct from pg_temp.f4p_copia_antes(v_esperado) then
    raise exception 'R1f: a saída do painel copiou as linhas diferente (%)', v_x.dados -> 'linhas';
  end if;
  v_t := pg_temp.f4p_pegar(v_x.id, '2027-01-14 17:58-03');
  v_texto := (select s.texto from public.retorno_saidas s where s.id = v_x.id);
  if v_t is distinct from 'preparada/'
     or v_texto is distinct from E'Pátio HBR · qui (14/01)\n1. Motorhome de João S.: em serviço hoje.\n2. Motorhome de Kauê E.: em serviço hoje.\n3. Motorhome de Lia E.: em serviço hoje.\n4. Motorhome de Mel E.: em serviço hoje.\n5. Motorhome de Nico E.: em serviço hoje.\n6. Motorhome de Olga E.: em serviço hoje.\n7. Motorhome de Pita E.: em serviço hoje.\n8. Motorhome de Quico E.: em serviço hoje.\n9. Motorhome de Rafa E.: em serviço hoje.\n10. Motorhome de Teo E.: em serviço hoje.\nPara ver de novo, mande *pátio*.\nValores e dados ficam com cada cliente.' then
    raise exception 'R1g: o painel saiu diferente com as chaves desligadas (% / %)', v_t, v_texto;
  end if;
  update public.retorno_config set patio_nivel = 'direto' where id;
  v_r := public.parceiro_patio_pedido(v_nt, pg_temp.f4p_msg('5547900017602', 'patio', c_t), c_t);
  select * into v_x from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid;
  if v_r ->> 'acao' is distinct from 'direto' or v_x.dados -> 'linhas' is distinct from pg_temp.f4p_copia_antes(v_esperado)
     or public._parceiro_painel_texto('parceiro_patio', 'direto', v_x.dados -> 'linhas', 0, date '2027-01-14', false) ->> 'texto'
        is distinct from E'Pátio HBR · 14/01\n1. Motorhome de João S.: em serviço hoje.\n2. Motorhome de Kauê E.: em serviço hoje.\n3. Motorhome de Lia E.: em serviço hoje.\n4. Motorhome de Mel E.: em serviço hoje.\n5. Motorhome de Nico E.: em serviço hoje.\n6. Motorhome de Olga E.: em serviço hoje.\n7. Motorhome de Pita E.: em serviço hoje.\n8. Motorhome de Quico E.: em serviço hoje.\n9. Motorhome de Rafa E.: em serviço hoje.\n10. Motorhome de Teo E.: em serviço hoje.' then
    raise exception 'R1h: o pátio saiu diferente com as chaves desligadas (% / %)', v_r, v_x.dados -> 'linhas';
  end if;
  if public._parceiro_linhas_que_saem(v_pt, c_t) is distinct from pg_temp.f4p_copia_antes(v_esperado) then
    raise exception 'R1i: o bloco P11 mudou com as chaves desligadas';
  end if;
  if public._parceiro_texto('parceiro_painel', 'linha',
       '{"n": 1, "bem": "motorhome", "cliente": "João S.", "estado": "em_servico", "etapa": "instalação do painel solar"}'::jsonb)
     is distinct from '1. Motorhome de João S.: em serviço hoje.' then
    raise exception 'R1j: com a chave desligada, a etapa entrou no texto';
  end if;

  -- Ligada: só a 1ª (instalação) e a 10ª (60 caracteres) levam a etapa; dígito, 61 caracteres, quebra de linha, parêntese, o
  -- 1º nome de outro cliente, o do próprio cliente, a etapa nula e o dia ficam sem ela. Estado, n, desde e impressão não mudam.
  update public.retorno_config set parceiro_etapa_ligada = true where id;
  v_linhas := public.parceiro_linhas(v_pt, c_t);
  if (select jsonb_object_agg(l ->> 'n', l -> 'etapa') from jsonb_array_elements(v_linhas) l where l ? 'etapa')
     is distinct from jsonb_build_object('1', 'instalação do painel solar', '10', 'r' || substr(v_etapa60, 2)) then
    raise exception 'R1k: as etapas que saem (%)', v_linhas;
  end if;
  if (select jsonb_agg(t.l - 'etapa' order by t.o) from jsonb_array_elements(v_linhas) with ordinality t(l, o)) is distinct from v_esperado
     or public._parceiro_impressao(v_linhas) is distinct from public._parceiro_impressao(v_esperado) then
    raise exception 'R1l: a etapa mudou outra coisa na linha ou a impressão';
  end if;
  if exists (select 1 from jsonb_array_elements(v_linhas) l, jsonb_object_keys(l) k
              where k not in ('n', 'interessado_id', 'service_order_id', 'estado', 'desde', 'rotulo', 'retida_por', 'fora_por', 'etapa'))
     or exists (select 1 from jsonb_array_elements(v_linhas) l where l ? 'etapa' and l ->> 'estado' is distinct from 'em_servico') then
    raise exception 'R1m: chave fora da lista positiva, ou etapa fora de em_servico';
  end if;
  -- o painel pelo caminho real (outro painel do mesmo dia: o de antes sai da tabela), a saída e o texto com a etapa
  delete from public.parceiro_paineis where id = v_painel;
  v_r := public.parceiro_painel_montar(v_pt, date '2027-01-14', '2027-01-14 17:31-03');
  v_painel := (v_r ->> 'painel_id')::uuid;
  if (select pp.linhas from public.parceiro_paineis pp where pp.id = v_painel) is distinct from v_linhas then
    raise exception 'R1n: o painel não guardou a etapa (%)', v_r;
  end if;
  perform pg_temp.f4p_so(v_pt, v_todos || v_pr);
  perform public.parceiro_painel_rodada('2027-01-14 18:00-03');
  perform pg_temp.f4p_so(null, v_todos || v_pr);
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:painel:' || v_painel || ':' || v_nt || ':sombra';
  if v_x.id is null or v_x.dados -> 'linhas' -> 0 ->> 'etapa' is distinct from 'instalação do painel solar'
     or (select count(*) from jsonb_array_elements(v_x.dados -> 'linhas') l where l ? 'etapa') is distinct from 2::bigint then
    raise exception 'R1o: a saída do painel não levou a etapa (%)', v_x.dados -> 'linhas';
  end if;
  v_t := pg_temp.f4p_pegar(v_x.id, '2027-01-14 18:02-03');
  v_texto := (select s.texto from public.retorno_saidas s where s.id = v_x.id);
  if v_t is distinct from 'preparada/'
     or v_texto is distinct from E'Pátio HBR · qui (14/01)\n1. Motorhome de João S.: em serviço hoje (instalação do painel solar).\n2. Motorhome de Kauê E.: em serviço hoje.\n3. Motorhome de Lia E.: em serviço hoje.\n4. Motorhome de Mel E.: em serviço hoje.\n5. Motorhome de Nico E.: em serviço hoje.\n6. Motorhome de Olga E.: em serviço hoje.\n7. Motorhome de Pita E.: em serviço hoje.\n8. Motorhome de Quico E.: em serviço hoje.\n9. Motorhome de Rafa E.: em serviço hoje.\n10. Motorhome de Teo E.: em serviço hoje (revisão geral da cabine da cabine da cabine da cabine da cab).\nPara ver de novo, mande *pátio*.' then
    raise exception 'R1p: o painel com a etapa (% / %)', v_t, v_texto;
  end if;
  -- o contexto do validador do painel com a etapa: o Zeca em nomes_de_outros, o João na lista (a linha passa no validador
  -- real: validador_parceiro_test.ts)
  v_r := public._parceiro_contexto_do_validador(v_x.id, v_texto, v_x.dados, '2027-01-14 18:02-03');
  if not (v_r -> 'nomes_de_outros' ? 'Zeca F.') or not (v_r -> 'nomes_da_lista' ? 'João S.') then
    raise exception 'R1q: o contexto do validador do painel com a etapa (%)', v_r;
  end if;
  -- o pátio direto e o bloco P11 levam a etapa
  v_r := public.parceiro_patio_pedido(v_nt, pg_temp.f4p_msg('5547900017602', 'patio', c_t + interval '1 minute'), c_t + interval '1 minute');
  select * into v_x from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid;
  if v_r ->> 'acao' is distinct from 'direto' or v_x.dados -> 'linhas' -> 0 ->> 'etapa' is distinct from 'instalação do painel solar'
     or public._parceiro_painel_texto('parceiro_patio', 'direto', v_x.dados -> 'linhas', 0, date '2027-01-14', false) ->> 'texto'
        not like E'Pátio HBR · 14/01\n1. Motorhome de João S.: em serviço hoje (instalação do painel solar).\n2. Motorhome de Kauê E.: em serviço hoje.\n%' then
    raise exception 'R1r: o pátio direto sem a etapa (%)', v_r;
  end if;
  if public._parceiro_linhas_que_saem(v_pt, c_t) -> 0 ->> 'etapa' is distinct from 'instalação do painel solar' then
    raise exception 'R1s: o bloco P11 sem a etapa';
  end if;
  -- o texto: a etapa só vale em em_servico; a etapa torta nos dados dá 22023 (a linha sai com fora_por = 'texto')
  if public._parceiro_texto('parceiro_painel', 'linha',
       '{"n": 1, "bem": "motorhome", "cliente": "João S.", "estado": "pronto", "etapa": "instalação do painel solar"}'::jsonb)
     is distinct from '1. Motorhome de João S.: pronto; o cliente já foi avisado para combinar a retirada.' then
    raise exception 'R1t: a etapa entrou numa linha que não é em_servico';
  end if;
  begin
    perform public._parceiro_texto('parceiro_painel', 'linha',
      '{"n": 1, "bem": "motorhome", "cliente": "João S.", "estado": "em_servico", "etapa": "troca de 2 baterias"}'::jsonb);
    raise exception 'R1u: a etapa torta teve texto';
  exception when sqlstate '22023' then
    null;
  end;

  -- Desligada de novo: as linhas voltam às de antes, e a saída do pátio que já tinha a etapa sai sem ela
  update public.retorno_config set parceiro_etapa_ligada = false where id;
  if public.parceiro_linhas(v_pt, c_t) is distinct from v_esperado then
    raise exception 'R1v: desligar de novo não voltou às linhas de antes';
  end if;
  if public._parceiro_painel_texto('parceiro_patio', 'direto', v_x.dados -> 'linhas', 0, date '2027-01-14', false) ->> 'texto'
     not like E'Pátio HBR · 14/01\n1. Motorhome de João S.: em serviço hoje.\n2. Motorhome de Kauê E.: em serviço hoje.\n%' then
    raise exception 'R1w: a saída agendada com a etapa a levou com a chave desligada';
  end if;
  update public.retorno_config set patio_nivel = 'cartao' where id;

  -- ── A varredura do parceiro: as funções da P7 fechadas a anon e authenticated ──
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?parceiro_'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
      raise exception 'grants: % aberta a anon/authenticated', v_rec.nome;
    end if;
    if v_rec.proname !~ '^_' and not has_function_privilege('service_role', v_rec.oid, 'execute') then
      raise exception 'grants: % sem execute para o service_role', v_rec.nome;
    end if;
    if v_rec.prosecdef and not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception 'grants: % é SECURITY DEFINER sem search_path', v_rec.nome;
    end if;
  end loop;
  if to_regprocedure('public.parceiro_linhas(uuid, timestamptz)') is null
     or to_regprocedure('public.parceiro_ler_mensagem(uuid, timestamptz)') is null
     or to_regprocedure('public.parceiro_vigia(timestamptz)') is null then
    raise exception 'grants: a varredura não achou as funções da P7 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_painel', true, '{}');
end
$painel$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
