-- Retorno rápido ao cliente, F2 (P5): o fato confiável do contato.
--
-- retorno_fatos_do_contato(fone, agora) é a única fonte do que o sistema pode afirmar sobre o serviço de quem escreveu. O
-- contato é resolvido aqui, por quem_escreve: nunca por argumento vindo de modelo. Número ambíguo, fornecedor, equipe ou
-- número novo não trazem OS de ninguém.
--
-- service_orders.status NÃO é fonte de "está pronto": existe lote que marcou OS concluída sem ninguém dizer nada. Pronto é a
-- palavra do dono ou da equipe em agenda_acoes. A OS concluída sem essa palavra vira "concluida_sem_palavra", e o cartão
-- pergunta ao dono.
--
-- Ninguém olha o futuro: tudo para em p_agora. Leitura que falha sobe como exceção: quem chama trata como "sem fato", nunca
-- como "não há peça".
--
-- Desvios da spec, com o motivo:
-- - a lista positiva ganhou service_orders.merged_into_id e created_at, e os_material.atualizado_em. O banco não tem completed_at:
--   a conclusão é check_out_at, preenchido nas 22 OS concluídas em 07/11 (updated_at não serve: o gatilho o reescreve a cada
--   edição). OS concluída sem check_out_at não entra: falha fecha. A data da falta sai de atualizado_em;
-- - a OS concluída sem palavra entra em "os" só com o cliente sem OS viva, e só a mais recente de até 28 dias. A spec pede o
--   fato, mas não diz qual OS; sem esse corte, todo cliente antigo teria várias OS, e o modelo nunca caberia (regra 7).
--
-- A lista positiva abaixo é conferida contra COLUNAS_INTERNAS em colunas-do-fato_test.ts. A descrição do material e a previsão
-- só vão ao dono: o modelo nunca recebe a previsão.
--
-- Reverter: drop function public.retorno_fatos_do_contato(text, timestamptz). Quem chama trata como "sem fato".

-- lista positiva: início
-- service_orders: id, service_order_number, client_id, vessel_id, status, check_in_at, check_out_at, delivered_at,
--                 liberado_retirada_em, merged_into_id, created_at
-- vessels: name, asset_type
-- os_material: id, descricao, situacao, critico, chegou_em, fonte, previsao_ate, previsao_fonte, comprado_em, atualizado_em
-- agenda_acoes: tipo, origem, executada, desfeita_em, criada_em
-- agenda_alocacoes: dia, estado, tipo, payee_id
-- agenda_disponibilidade: payee_id, situacao, periodo, substituida_em, criado_em
-- os_tarefas: texto, estado
-- os_tarefas_dia: modo, dia, estado
-- agenda_cliente_mensagens: tipo, enviada_em
-- lista positiva: fim

create or replace function public.retorno_fatos_do_contato(p_fone text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_janela_sem_palavra constant interval := '28 days';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_quem jsonb;
  v_papel text;
  v_cl uuid;
  v_oss jsonb := '[]'::jsonb;
  r record;
  v_pronto jsonb;
  v_sem_palavra jsonb;
  v_servico jsonb;
  v_chegou jsonb;
  v_aguarda jsonb;
  v_previsao jsonb;
  v_liberado jsonb;
  v_ouviu timestamptz;
  v_etapa text;
  v_conf timestamptz;
  v_faltam boolean;
  v_n integer;
  v_em date;
  v_fonte text;
  v_prev date;
  v_prev_fonte text;
  v_comprado date;
begin
  if v_cfg.id is null then
    raise exception 'retorno_fatos_do_contato: sem retorno_config' using errcode = '55000';
  end if;

  v_quem := public.quem_escreve(p_fone);
  v_papel := v_quem ->> 'papel';
  if v_papel is distinct from 'cliente' then
    return jsonb_build_object('papel', v_papel, 'ambiguo', v_papel = 'cliente_ambiguo', 'client_id', null, 'os', '[]'::jsonb);
  end if;
  v_cl := (v_quem ->> 'cliente_id')::uuid;

  for r in
    with base as (
      select so.id, so.service_order_number, so.vessel_id, so.status, so.check_in_at, so.delivered_at, so.liberado_retirada_em,
             so.check_out_at as concluida_desde,
             v.name as bem,
             k.service_order_id is not null as na_carteira,
             p.criada_em as palavra_em,
             p.origem as palavra_fonte
        from public.service_orders so
        left join public.vessels v on v.id = so.vessel_id
        left join public.os_carteira(v_hoje) k on k.service_order_id = so.id
        left join lateral (
          select a.criada_em, a.origem
            from public.agenda_acoes a
           where a.service_order_id = so.id
             and a.tipo = 'concluir'
             and a.executada
             and a.desfeita_em is null
             and a.origem in ('dono', 'equipe')
             and a.criada_em <= v_agora
           order by a.criada_em desc
           limit 1) p on true
       where so.client_id = v_cl
         and so.merged_into_id is null
         and so.created_at <= v_agora
    ), marcadas as (
      select b.*,
             (b.status in ('completed', 'invoiced') and b.palavra_em >= v_agora - v_cfg.fato_pronto_idade) as concluida_recente,
             (b.liberado_retirada_em is not null
              and b.liberado_retirada_em <= v_agora
              and b.liberado_retirada_em > v_agora - v_cfg.liberado_validade
              and b.delivered_at is null
              and (b.status in ('completed', 'invoiced') or b.na_carteira)) as liberada
        from base b
    ), vivas as (
      select m.* from marcadas m where m.na_carteira or m.concluida_recente or m.liberada
    ), sem_palavra as (
      select m.*
        from marcadas m
       where not exists (select 1 from vivas)
         and m.status in ('completed', 'invoiced')
         and m.palavra_em is null
         and m.delivered_at is null
         and m.concluida_desde > v_agora - c_janela_sem_palavra
       order by m.concluida_desde desc, m.id
       limit 1
    )
    select x.* from (select * from vivas union all select * from sem_palavra) x
    order by x.service_order_number collate "C", x.id
  loop
    v_pronto := null;
    v_sem_palavra := null;
    v_servico := null;
    v_chegou := null;
    v_aguarda := null;
    v_previsao := null;
    v_liberado := null;

    if r.palavra_em is not null and r.palavra_em >= v_agora - v_cfg.fato_pronto_idade then
      v_pronto := jsonb_build_object('valor', true, 'fonte', r.palavra_fonte, 'em', r.palavra_em,
                                     'idade_h', floor(extract(epoch from v_agora - r.palavra_em) / 3600)::integer);
    elsif r.status in ('completed', 'invoiced') and r.palavra_em is null then
      v_sem_palavra := jsonb_build_object('desde', (r.concluida_desde at time zone c_fuso)::date);
    end if;

    -- A etapa só com as tarefas ligadas: em sombra ela é conta do sistema, não fato.
    select t.texto into v_etapa
      from public.os_tarefas_dia d
      join public.os_tarefas t on t.id = d.tarefa_id
     where d.service_order_id = r.id and d.dia = v_hoje and d.modo = 'ligado' and t.estado <> 'cancelada'
     order by d.posicao nulls last, d.id
     limit 1;

    if r.check_in_at is not null and r.check_in_at <= v_agora and r.check_in_at > v_agora - v_cfg.fato_servico_idade then
      v_servico := jsonb_build_object('valor', true, 'fonte', 'check_in', 'em', r.check_in_at, 'etapa', v_etapa);
    else
      -- O "ok" do técnico grava agenda_disponibilidade: é a alocação de hoje com essa confirmação.
      select max(c.criado_em) into v_conf
        from public.agenda_alocacoes al
        join public.agenda_disponibilidade c
          on c.payee_id = al.payee_id and c.situacao = 'confirmada' and c.substituida_em is null and c.periodo @> v_hoje
       where al.service_order_id = r.id
         and al.dia = v_hoje
         and al.estado in ('publicada', 'fixada')
         and al.tipo <> 'reserva'
         and c.criado_em <= v_agora;
      if v_conf is not null then
        v_servico := jsonb_build_object('valor', true, 'fonte', 'tecnico', 'em', v_conf, 'etapa', v_etapa);
      end if;
    end if;

    select exists (select 1 from public.os_material m
                    where m.service_order_id = r.id and m.critico and m.situacao in ('falta', 'comprado', 'a_caminho'))
      into v_faltam;

    select count(*), max(m.chegou_em), (array_agg(m.fonte order by m.chegou_em desc, m.id))[1]
      into v_n, v_em, v_fonte
      from public.os_material m
     where m.service_order_id = r.id
       and m.critico
       and m.situacao = 'na_mao'
       and m.fonte in ('dono', 'nfe', 'oc', 'fornecedor')
       and m.chegou_em <= v_hoje
       and m.chegou_em >= ((v_agora - v_cfg.fato_peca_idade) at time zone c_fuso)::date;
    if v_n > 0 then
      v_chegou := jsonb_build_object('valor', true, 'fonte', v_fonte, 'em', v_em, 'linhas', v_n, 'faltam_outras', v_faltam);
    end if;

    if v_faltam then
      select jsonb_agg(jsonb_build_object('id', m.id, 'descricao', m.descricao, 'situacao', m.situacao,
                                          'desde', coalesce(m.comprado_em, (m.atualizado_em at time zone c_fuso)::date))
                       order by m.descricao, m.id),
             min(m.previsao_ate),
             (array_agg(m.previsao_fonte order by m.previsao_ate nulls last))[1],
             min(m.comprado_em)
        into v_aguarda, v_prev, v_prev_fonte, v_comprado
        from public.os_material m
       where m.service_order_id = r.id and m.critico and m.situacao in ('falta', 'comprado', 'a_caminho');
      v_aguarda := jsonb_build_object('valor', true, 'linhas', v_aguarda);
      if v_prev is not null then
        v_previsao := jsonb_build_object('ate', v_prev, 'fonte', v_prev_fonte, 'padrao', false);
      else
        v_previsao := jsonb_build_object('ate', public.agenda_somar_du(coalesce(v_comprado, v_hoje), (public._agenda_cfg()).prazo_sem_fornecedor_du),
                                         'fonte', null, 'padrao', true);
      end if;
    end if;

    if r.liberada then
      v_liberado := jsonb_build_object('em', r.liberado_retirada_em, 'vale_ate', r.liberado_retirada_em + v_cfg.liberado_validade);
    end if;

    select max(a.enviada_em) into v_ouviu
      from public.agenda_cliente_mensagens a
     where a.service_order_id = r.id
       and a.tipo in ('material_chegou', 'nova_data')
       and a.enviada_em <= v_agora;

    v_oss := v_oss || jsonb_build_array(jsonb_build_object(
      'id', r.id, 'numero', r.service_order_number, 'bem', r.bem, 'status', r.status,
      'fatos', jsonb_build_object('pronto', v_pronto, 'em_servico', v_servico, 'peca_chegou', v_chegou, 'aguarda_peca', v_aguarda,
                                  'previsao', v_previsao, 'liberado', v_liberado, 'concluida_sem_palavra', v_sem_palavra,
                                  'ouviu_material', v_ouviu)));
  end loop;

  return jsonb_build_object('papel', v_papel, 'ambiguo', false, 'client_id', v_cl, 'os', v_oss);
end;
$$;

comment on function public.retorno_fatos_do_contato(text, timestamptz) is
  'Retorno F2 (C-FATO): o fato confiável do contato, resolvido por quem_escreve. Só papel cliente traz OS. pronto = palavra do dono ou da equipe em agenda_acoes, nunca status. previsao e descricao são só do dono. Só lê; erro sobe.';

revoke all on function public.retorno_fatos_do_contato(text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_fatos_do_contato(text, timestamptz) to service_role;
