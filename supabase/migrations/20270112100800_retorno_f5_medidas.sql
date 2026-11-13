-- Retorno rápido ao cliente, F5 (P13): as medidas do orçamento depois do envio e o cron do vigia. Nada que mande mensagem liga.
--
-- 1. orcamento_medidas(p_desde, p_ate) (C-MED; só service_role): as contagens do período [p_desde, p_ate), lidas pela sessão
--    que coordena para os portões de 8.4 e 8.5. Só contagens: nenhum nome, telefone, documento ou texto, e nenhum corpo de
--    mensagem é lido (de whatsapp_messages saem só o id, a direção, o tipo, a hora e a chave do telefone).
--    - envios: orcamento_envios com em no período, por via, ao cliente e fora dele (Cliente Final, cliente sem telefone, envio
--      sem número, outro número), orçamentos distintos e reenvios (envio com outro anterior da mesma ordem).
--    - acompanhamentos: os de enviado_em no período (criados, ativos, parados por motivo, refeitos, encerrados por forma,
--      concluídos) e os inelegíveis: a ordem com envio no período e sem acompanhamento, pelo motivo de _orcamento_inelegivel no
--      instante do 1º envio ao cliente (sem motivo = 'elegivel').
--    - passos: os de dia no período, por tipo; os pulados por motivo; o sem_sim que nunca entrou num cartão (sem_cartao) e o
--      que entrou e ficou sem resposta (sem_resposta); o do tipo hoje em 'sozinho' que passou pelo cartão.
--    - aceites: os de mensagem no período, por estado; a sombra por resultado.seria; os dias úteis da mensagem à decisão
--      (mediana e máximo); nao_era e mostrados num cartão; sem caso; pulados_audio (o áudio recebido de número de cliente com
--      orçamento candidato, com aceite_audio desligado: o detector o pula antes de ler).
--    - portao: sem_desfecho (meta 0), parados_sem_desfecho, com_acompanhamento_ou_motivo, lembrete_depois_de_parar (meta 0),
--      aceite_sem_msg, rejeitado_sem_motivo, aceite_ate_registro.
--    - sombra.precisao_aceite e respostas_do_dono (toques nos cartões com item da F5, por dia útil do período).
--    A base dos aceites do período é a auxiliar _orcamento_medidas_aceites (só o revoke).
-- 2. O cron retorno-orcamento: orcamento_vigia a cada 5 minutos, das 07:00 às 20:55 de Brasília (10–23 UTC). Separado do
--    retorno-minuto de propósito (o comando dele lê a chave do cron em app_settings). Com as chaves da F5 desligadas (o padrão
--    da P1), o vigia só avança as marcas d'água do envio à mão e do aceite: não lê mensagem e não agenda nada.
--
-- Sem dado de cliente. Reverter: select cron.unschedule(jobid) from cron.job where jobname = 'retorno-orcamento';
-- drop function public.orcamento_medidas(timestamptz, timestamptz);

-- ── 1. As medidas (C-MED) ────────────────────────────────────────────────────────────────────────────────────────────────

-- Os aceites do período, pela hora da mensagem do cliente (sem a mensagem, a da gravação): a base das contagens de aceite e
-- de dois portões. Só ids, estados e horas.
create or replace function public._orcamento_medidas_aceites(p_desde timestamptz, p_ate timestamptz)
returns table (id uuid, estado text, seria text, abertura_id uuid, service_order_id uuid, tem_msg boolean, msg_em timestamptz,
               msg_dia date, decidido_em timestamptz, mostrado boolean)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.estado, a.resultado ->> 'seria', a.abertura_id, a.service_order_id, w.id is not null,
         coalesce(w.hora_real, w.occurred_at, a.criado_em),
         (coalesce(w.hora_real, w.occurred_at, a.criado_em) at time zone 'America/Sao_Paulo')::date,
         a.decidido_em,
         exists (select 1 from public.retorno_cartao_itens i where i.aceite_id = a.id)
    from public.orcamento_aceites a
    left join public.whatsapp_messages w on w.id = a.whatsapp_message_id
   where coalesce(w.hora_real, w.occurred_at, a.criado_em) >= p_desde
     and coalesce(w.hora_real, w.occurred_at, a.criado_em) < p_ate;
$$;

comment on function public._orcamento_medidas_aceites(timestamptz, timestamptz) is
  'Retorno F5 (P13): os aceites de [p_desde, p_ate) pela hora da mensagem do cliente (sem a mensagem em whatsapp_messages, a de criado_em): id, estado, resultado.seria, caso, ordem, se a mensagem existe, hora e dia (Brasília) da mensagem, decidido_em e se o aceite já esteve num cartão. A base de orcamento_medidas.';

revoke all on function public._orcamento_medidas_aceites(timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public.orcamento_medidas(p_desde timestamptz, p_ate timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_cadencia constant text[] := array['orc_lembrete', 'orc_vespera', 'orc_encerramento'];
  v_cfg public.retorno_config := public._retorno_cfg();
  v_parceiros uuid[];
  v_ate_dia date;
  v_envios jsonb;
  v_acomp jsonb;
  v_inel jsonb;
  v_parados jsonb;
  v_passos jsonb;
  v_aceites jsonb;
  v_estados jsonb;
  v_seria jsonb;
  v_dias jsonb;
  v_audio integer;
  v_sem_desfecho integer;
  v_parados_sem integer;
  v_com integer;
  v_enviados integer;
  v_depois integer;
  v_depois_sombra integer;
  v_sem_msg integer;
  v_rej integer;
  v_no_prazo integer;
  v_total integer;
  v_acertos integer;
  v_detectados integer;
  v_s_agenda integer;
  v_s_duvida integer;
  v_toques integer;
  v_du integer;
begin
  if p_desde is null or p_ate is null or p_desde >= p_ate then
    raise exception using errcode = '22023', message = 'orcamento_medidas: o período é [p_desde, p_ate), com p_desde antes de p_ate';
  end if;
  v_ate_dia := (p_ate at time zone c_fuso)::date;
  v_parceiros := coalesce(v_cfg.clientes_parceiros, '{}'::uuid[]);

  -- ── envios ──
  with e as (
    select e.id, e.service_order_id, e.via, e.chave, e.ao_cliente, e.em, coalesce(c.generico, false) as generico,
           public._agenda_chave_telefone(c.whatsapp) as k1, public._agenda_chave_telefone(c.phone) as k2
      from public.orcamento_envios e
      left join public.clients c on c.id = e.client_id
     where e.em >= p_desde and e.em < p_ate
  )
  select jsonb_build_object(
           'total', count(*),
           'por_via', coalesce((select jsonb_object_agg(x.via, x.n)
                                  from (select e2.via, count(*) as n from e e2 group by e2.via) x), '{}'::jsonb),
           'ao_cliente', count(*) filter (where e.ao_cliente),
           'fora', jsonb_build_object(
             'cliente_final', count(*) filter (where not e.ao_cliente and e.generico),
             'sem_telefone', count(*) filter (where not e.ao_cliente and not e.generico and e.k1 is null and e.k2 is null),
             'sem_numero', count(*) filter (where not e.ao_cliente and not e.generico and (e.k1 is not null or e.k2 is not null)
                                                  and e.chave is null),
             'outro_numero', count(*) filter (where not e.ao_cliente and not e.generico and (e.k1 is not null or e.k2 is not null)
                                                    and e.chave is not null)),
           'orcamentos', count(distinct e.service_order_id),
           'reenvios', count(*) filter (where exists (select 1 from public.orcamento_envios e0
                                                       where e0.service_order_id = e.service_order_id
                                                         and (e0.em < e.em or (e0.em = e.em and e0.id < e.id)))))
    into v_envios
    from e;

  -- ── acompanhamentos ──
  select coalesce(jsonb_object_agg(x.parou_por, x.n), '{}'::jsonb)
    into v_parados
    from (select a.parou_por, count(*) as n
            from public.orcamento_acompanhamentos a
           where a.enviado_em >= p_desde and a.enviado_em < p_ate and a.estado = 'parado'
           group by a.parou_por) x;
  -- O inelegível: a ordem com envio no período e sem acompanhamento, pelo motivo no instante do 1º envio ao cliente (sem ele,
  -- o 1º envio do período). O funil e o cadastro são os de agora: o motivo de tempo (sem_envio, sem_conversa) é o do envio.
  select coalesce(jsonb_object_agg(x.motivo, x.n), '{}'::jsonb)
    into v_inel
    from (select y.motivo, count(*) as n
            from (select coalesce(public._orcamento_inelegivel(so.id, coalesce(so.orcamento_enviado_em, f.em)), 'elegivel') as motivo
                    from (select e.service_order_id, min(e.em) as em
                            from public.orcamento_envios e
                           where e.em >= p_desde and e.em < p_ate
                           group by e.service_order_id) f
                    join public.service_orders so on so.id = f.service_order_id
                   where not exists (select 1 from public.orcamento_acompanhamentos a where a.service_order_id = so.id)) y
           group by y.motivo) x;
  select jsonb_build_object(
           'criados', count(*),
           'ativos', count(*) filter (where a.estado = 'ativo'),
           'parados', v_parados,
           'refeitos', count(*) filter (where a.refeito_em is not null),
           'encerrados', jsonb_build_object('enviado', count(*) filter (where a.encerramento = 'enviado'),
                                            'sombra', count(*) filter (where a.encerramento = 'sombra'),
                                            'sem_mensagem', count(*) filter (where a.encerramento = 'sem_mensagem')),
           'concluidos', count(*) filter (where a.estado = 'concluido'),
           'inelegiveis', v_inel)
    into v_acomp
    from public.orcamento_acompanhamentos a
   where a.enviado_em >= p_desde and a.enviado_em < p_ate;

  -- ── passos (o dia do passo, à meia-noite de Brasília, dentro do período) ──
  with p as (
    select p.id, p.tipo, p.estado, p.motivo, coalesce(t.nivel, 'desligado') as nivel,
           exists (select 1 from public.retorno_cartao_itens i where i.passo_id = p.id) as no_cartao,
           (select s.dados ->> 'por' from public.retorno_saidas s where s.id = p.saida_id) as por
      from public.orcamento_passos p
      left join public.retorno_modelo_tipos t on t.tipo = p.tipo
     where (p.dia::timestamp at time zone c_fuso) >= p_desde and (p.dia::timestamp at time zone c_fuso) < p_ate
  )
  select coalesce(jsonb_object_agg(z.tipo, z.j), '{}'::jsonb)
    into v_passos
    from (select g.tipo,
                 jsonb_build_object(
                   'total', count(*),
                   'previstos', count(*) filter (where g.estado = 'previsto'),
                   'aguarda_sim', count(*) filter (where g.estado = 'aguarda_sim'),
                   'agendados', count(*) filter (where g.estado = 'agendado'),
                   'sombra', count(*) filter (where g.estado = 'sombra'),
                   'enviados', count(*) filter (where g.estado = 'enviado'),
                   'cancelados', count(*) filter (where g.estado = 'cancelado'),
                   'pulados', coalesce((select jsonb_object_agg(m.motivo, m.n)
                                          from (select p2.motivo, count(*) as n from p p2
                                                 where p2.tipo = g.tipo and p2.estado = 'pulado'
                                                 group by p2.motivo) m), '{}'::jsonb),
                   'sem_sim', jsonb_build_object(
                     'sem_cartao', count(*) filter (where g.estado = 'pulado' and g.motivo = 'sem_sim' and not g.no_cartao),
                     'sem_resposta', count(*) filter (where g.estado = 'pulado' and g.motivo = 'sem_sim' and g.no_cartao)),
                   'sozinho_ao_cartao', count(*) filter (where g.nivel = 'sozinho'
                                                           and (g.no_cartao or g.estado = 'aguarda_sim'
                                                                or (g.estado = 'pulado' and g.motivo = 'sem_sim')
                                                                or g.por = 'sim'))) as j
            from p g
           group by g.tipo) z;

  -- ── aceites (a hora da mensagem do cliente; sem a mensagem, a da gravação) ──
  select coalesce(jsonb_object_agg(x.estado, x.n), '{}'::jsonb) into v_estados
    from (select t.estado, count(*) as n from public._orcamento_medidas_aceites(p_desde, p_ate) t group by t.estado) x;
  select coalesce(jsonb_object_agg(x.seria, x.n), '{}'::jsonb) into v_seria
    from (select coalesce(t.seria, 'sem_seria') as seria, count(*) as n
            from public._orcamento_medidas_aceites(p_desde, p_ate) t where t.estado = 'sombra' group by 1) x;
  -- Dias úteis da mensagem à decisão: os dias úteis da agenda depois do dia da mensagem, até o dia da decisão.
  select jsonb_build_object('decididos', count(*),
                            'mediana', percentile_cont(0.5) within group (order by d.du),
                            'maximo', max(d.du))
    into v_dias
    from (select (select count(*)
                    from generate_series((t.msg_dia + 1)::timestamp, ((t.decidido_em at time zone c_fuso)::date)::timestamp,
                                         interval '1 day') g(d)
                   where public.agenda_dia_util(g.d::date)) as du
            from public._orcamento_medidas_aceites(p_desde, p_ate) t
           where t.decidido_em is not null) d;
  -- O áudio que o detector pula (aceite_audio desligado): recebido de número de cliente com orçamento candidato no instante
  -- da mensagem. Só a hora, o tipo e o telefone; o corpo nunca é lido.
  if coalesce(v_cfg.aceite_audio, false) then
    v_audio := 0;
  else
    select count(*)
      into v_audio
      from public.whatsapp_messages w
     where w.direction = 'inbound'
       and w.message_type = 'audio'
       and w.occurred_at >= p_desde - interval '1 day' and w.occurred_at < p_ate + interval '1 day'
       and coalesce(w.hora_real, w.occurred_at) >= p_desde and coalesce(w.hora_real, w.occurred_at) < p_ate
       and not coalesce(w.is_broadcast, false)
       and cardinality(coalesce(public._orcamento_candidatos(
             public._orcamento_cliente_do_telefone(
               (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = w.id), w.phone_normalized),
             public._agenda_chave_telefone(w.phone_normalized), coalesce(w.hora_real, w.occurred_at), p_ate), '{}'::uuid[])) > 0;
  end if;
  select jsonb_build_object(
           'total', count(*),
           'por_estado', v_estados,
           'sombra_por_seria', v_seria,
           'dias_uteis_ate_decisao', v_dias,
           'nao_era', count(*) filter (where t.estado = 'nao_era'),
           'mostrados', count(*) filter (where t.mostrado),
           'sem_caso', count(*) filter (where t.abertura_id is null),
           'pulados_audio', v_audio)
    into v_aceites
    from public._orcamento_medidas_aceites(p_desde, p_ate) t;

  -- ── portão: sem desfecho ──
  -- O universo: a ordem com envio no período a qualquer número, fora da via historico e do envio a número confirmado de
  -- parceiro; fora o orçamento do parceiro (cliente em clientes_parceiros ou pedido por um parceiro, dúvida 4).
  with env as (
    select distinct e.service_order_id
      from public.orcamento_envios e
     where e.em >= p_desde and e.em < p_ate
       and e.via <> 'historico'
       and not (e.chave is not null
                and exists (select 1 from public.parceiro_numeros n where n.chave = e.chave and n.situacao = 'confirmado'))
  ),
  base as (
    select so.id
      from env
      join public.service_orders so on so.id = env.service_order_id
     where not (so.client_id = any (v_parceiros))
       and so.origem_parceiro_id is null
       and so.converted_to_os_at is null
       and so.merged_into_id is null
       and so.status is distinct from 'cancelled'
       and (so.quote_status in ('awaiting_deposit', 'approved')) is not true
       and not (so.quote_status = 'rejected' and so.motivo_perda is not null and so.motivo_perda <> 'sem_motivo_antigo')
       and not exists (select 1 from public.orcamento_aceites ac
                        where ac.service_order_id = so.id and ac.estado in ('com_sinal', 'sem_sinal'))
       and public._orcamento_dia_util_mais(coalesce(so.quote_validity_date, public._orcamento_ultimo_dia(so.id)), 2) < v_ate_dia
  )
  select count(*),
         count(*) filter (where exists (select 1 from public.orcamento_acompanhamentos a
                                         where a.service_order_id = b.id and a.estado = 'parado'
                                           and a.parou_por = 'cliente_escreveu'))
    into v_sem_desfecho, v_parados_sem
    from base b;

  -- ── portão: com acompanhamento ou motivo (a frase literal, informativa) ──
  with env as (
    select e.service_order_id, min(e.em) as em
      from public.orcamento_envios e
     where e.em >= p_desde and e.em < p_ate and e.ao_cliente and e.via <> 'historico'
     group by e.service_order_id
  )
  select count(*),
         count(*) filter (where exists (select 1 from public.orcamento_acompanhamentos a where a.service_order_id = so.id)
                             or so.converted_to_os_at is not null or so.merged_into_id is not null
                             or so.status = 'cancelled' or so.quote_status in ('awaiting_deposit', 'approved')
                             or (so.quote_status = 'rejected' and so.motivo_perda is not null)
                             or exists (select 1 from public.orcamento_aceites ac
                                         where ac.service_order_id = so.id and ac.estado in ('com_sinal', 'sem_sinal'))
                             or public._orcamento_inelegivel(so.id, coalesce(so.orcamento_enviado_em, env.em)) is not null)
    into v_enviados, v_com
    from env
    join public.service_orders so on so.id = env.service_order_id;

  -- ── portão: lembrete depois de parar ──
  -- A saída da cadência que saiu (ou sairia, na sombra) depois de uma recebida da chave contada da hora do envio de verdade,
  -- ou depois de o número entrar em whatsapp_blocked_numbers (PARAR, opt-out). Cruza as mensagens e os bloqueios, nunca o
  -- estado gravado do acompanhamento; da mensagem, só a hora e a chave.
  select count(*), count(*) filter (where x.estado = 'sombra')
    into v_depois, v_depois_sombra
    from (select s.estado, s.chave, coalesce(s.enviada_em, s.decidida_em) as saiu_em,
                 coalesce((select a.enviado_em from public.orcamento_acompanhamentos a
                            where a.id::text = s.dados ->> 'acompanhamento_id'),
                          (select so.orcamento_enviado_em from public.service_orders so
                            where so.id::text = s.dados ->> 'os_id')) as envio_em
            from public.retorno_saidas s
           where s.emissor = 'orcamento' and s.tipo = any (c_cadencia)
             and s.estado in ('sombra', 'enviada', 'incerta')
             and coalesce(s.enviada_em, s.decidida_em) >= p_desde and coalesce(s.enviada_em, s.decidida_em) < p_ate) x
   where exists (select 1 from public.whatsapp_messages w
                  where w.direction = 'inbound'
                    and public._agenda_chave_telefone(w.phone_normalized) = x.chave
                    and w.occurred_at > coalesce(x.envio_em, x.saiu_em) - interval '1 day'
                    and w.occurred_at <= x.saiu_em
                    and coalesce(w.hora_real, w.occurred_at) > coalesce(x.envio_em, x.saiu_em)
                    and coalesce(w.hora_real, w.occurred_at) < x.saiu_em
                    and not coalesce(w.is_broadcast, false))
      or exists (select 1 from public.whatsapp_blocked_numbers b
                  where public._agenda_chave_telefone(b.phone_normalized) = x.chave and b.created_at < x.saiu_em);

  -- ── portão: aceite sem a mensagem, rejeitado novo sem motivo ──
  select count(*) filter (where not t.tem_msg) into v_sem_msg from public._orcamento_medidas_aceites(p_desde, p_ate) t;
  -- "Novo": o gatilho da P2 carimba motivo_perda_em em toda passagem a rejected; os antigos não têm a hora.
  select count(*) into v_rej
    from public.service_orders so
   where so.quote_status = 'rejected' and so.motivo_perda is null
     and so.motivo_perda_em >= p_desde and so.motivo_perda_em < p_ate;

  -- ── portão: aceite até o registro (1 dia útil) ──
  -- Sobre todos os aceites com a mensagem há mais de 1 dia útil, menos nao_era, sombra e substituido. A favor: o registrado
  -- pelo cartão (com_sinal, sem_sinal) e o respondido com a ordem convertida, em até 1 dia útil da mensagem.
  select count(*) filter (where (t.estado in ('com_sinal', 'sem_sinal')
                                 and (t.decidido_em at time zone c_fuso)::date <= public._orcamento_dia_util_mais(t.msg_dia, 1))
                             or (t.estado = 'respondido'
                                 and exists (select 1 from public.service_orders so
                                              where so.id = t.service_order_id and so.converted_to_os_at is not null
                                                and (so.converted_to_os_at at time zone c_fuso)::date
                                                    <= public._orcamento_dia_util_mais(t.msg_dia, 1)))),
         count(*)
    into v_no_prazo, v_total
    from public._orcamento_medidas_aceites(p_desde, p_ate) t
   where t.estado not in ('nao_era', 'sombra', 'substituido')
     and public._orcamento_dia_util_mais(t.msg_dia, 1) < v_ate_dia;

  -- ── sombra: a precisão do léxico ──
  -- Acerto: o aceite em sombra que seria 'detectado' cujo orçamento foi aprovado ou convertido em até 7 dias da mensagem
  -- (converted_to_os_at, o audit_log do funil a approved ou awaiting_deposit, ou um aceite registrado).
  select count(*) filter (where t.seria = 'detectado'
                            and exists (select 1 from public.service_orders so
                                         where so.id = t.service_order_id
                                           and ((so.converted_to_os_at > t.msg_em and so.converted_to_os_at <= t.msg_em + interval '7 days')
                                                or exists (select 1 from public.audit_log l
                                                            where l.table_name = 'service_orders' and l.record_id = so.id
                                                              and l.new_value ->> 'quote_status' in ('approved', 'awaiting_deposit')
                                                              and l.changed_at > t.msg_em and l.changed_at <= t.msg_em + interval '7 days')
                                                or exists (select 1 from public.orcamento_aceites ac
                                                            where ac.service_order_id = so.id and ac.estado in ('com_sinal', 'sem_sinal')
                                                              and ac.decidido_em > t.msg_em
                                                              and ac.decidido_em <= t.msg_em + interval '7 days')))),
         count(*) filter (where t.seria = 'detectado'),
         count(*) filter (where t.seria = 'agenda'),
         count(*) filter (where t.seria = 'duvida')
    into v_acertos, v_detectados, v_s_agenda, v_s_duvida
    from public._orcamento_medidas_aceites(p_desde, p_ate) t
   where t.estado = 'sombra';

  -- ── respostas do dono: os toques nos cartões com item da F5, por dia útil do período ──
  select count(*)
    into v_toques
    from public.retorno_toques t
   where t.em >= p_desde and t.em < p_ate and t.cartao_id is not null
     and exists (select 1 from public.retorno_cartao_itens i
                  where i.cartao_id = t.cartao_id and i.tipo_item in ('aceite', 'dados_nota', 'cadencia'));
  select count(*)
    into v_du
    from generate_series(((p_desde at time zone c_fuso)::date)::timestamp, v_ate_dia::timestamp, interval '1 day') g(d)
   where (g.d::date::timestamp at time zone c_fuso) >= p_desde and (g.d::date::timestamp at time zone c_fuso) < p_ate
     and public.agenda_dia_util(g.d::date);

  return jsonb_build_object(
    'periodo', jsonb_build_object('desde', p_desde, 'ate', p_ate),
    'envios', v_envios,
    'acompanhamentos', v_acomp,
    'passos', v_passos,
    'aceites', v_aceites,
    'portao', jsonb_build_object(
      'sem_desfecho', v_sem_desfecho,
      'parados_sem_desfecho', v_parados_sem,
      'com_acompanhamento_ou_motivo', jsonb_build_object('com', v_com, 'enviados', v_enviados),
      'lembrete_depois_de_parar', v_depois,
      'lembrete_depois_de_parar_sombra', v_depois_sombra,
      'aceite_sem_msg', v_sem_msg,
      'rejeitado_sem_motivo', v_rej,
      'aceite_ate_registro', jsonb_build_object('no_prazo', v_no_prazo, 'total', v_total)),
    'sombra', jsonb_build_object(
      'precisao_aceite', jsonb_build_object('acertos', v_acertos, 'detectados', v_detectados, 'agenda', v_s_agenda,
                                            'duvida', v_s_duvida)),
    'respostas_do_dono', jsonb_build_object(
      'toques', v_toques, 'dias_uteis', v_du,
      'por_dia_util', (case when v_du > 0 then round(v_toques::numeric / v_du, 2) end)));
end;
$$;

comment on function public.orcamento_medidas(timestamptz, timestamptz) is
  'Retorno F5 (P13, C-MED): as contagens do período [p_desde, p_ate): envios (por via, ao cliente e fora, reenvios), acompanhamentos (de enviado_em no período; inelegíveis pelo motivo no instante do 1º envio), passos (de dia no período, por tipo; sem_sim sem_cartao e sem_resposta; sozinho ao cartão), aceites (de mensagem no período: por estado, sombra por seria, dias úteis até a decisão, nao_era e mostrados, sem caso, pulados_audio), portao (sem_desfecho, parados_sem_desfecho, com_acompanhamento_ou_motivo, lembrete_depois_de_parar e a parte em sombra, aceite_sem_msg, rejeitado_sem_motivo, aceite_ate_registro), sombra.precisao_aceite e respostas_do_dono. Só contagens; nenhum corpo de mensagem é lido. Período vazio ou invertido: 22023.';

revoke all on function public.orcamento_medidas(timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_medidas(timestamptz, timestamptz) to service_role;

-- ── 2. O cron do vigia ───────────────────────────────────────────────────────────────────────────────────────────────────
-- cron.schedule com o mesmo nome atualiza o job (pg_cron 1.6): reaplicar não cria outro.
select cron.schedule('retorno-orcamento', '*/5 10-23 * * *', $c$select public.orcamento_vigia(now())$c$);
