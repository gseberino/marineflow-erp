-- Retorno rápido ao cliente, F4 (P2): identificação e abertura do parceiro.
-- Gerada por script (scripts/gerar_f4.cjs identificacao) a partir do corpo vigente das funções; só os trechos marcados
-- -- F4 são novos, e _parceiro_triar é nova (scripts/f4_sql/p2_parceiro_triar.sql), com os blocos de insistências e de
-- sinais copiados do _retorno_triar vigente sem mudança.
--
-- 1. _parceiro_triar: a triagem do caso do parceiro (regras 1 a 8 de P2.1). Grava no caso nível, motivo, tipo_recibo
--    ('recibo_parceiro' nas regras 5 a 8), intenção, sinais e insistências, e nunca passagem: o parceiro não tem relógio
--    nem acorde. As regras 5 a 8 agendam por parceiro_agendar (P5) e as 5 e 7 leem por parceiro_coleta_ler (P10): plpgsql,
--    que só compila na 1ª execução. Nada disso roda com parceiro_modo = 'desligado' (regra 1, o padrão).
-- 2. quem_escreve: o número de parceiro confirmado, de pessoa e parceiro ativos e com o mesmo DDD, dá papel 'parceiro'
--    antes da precedência do cliente, mas só quando o cliente do número é o próprio parceiro; com outro cliente no número,
--    o cliente vence.
-- 3. retorno_identificar: o parceiro com cadastro de cliente (a MP) continua com o client_id dele.
-- 4. retorno_abrir: o papel 'parceiro' abre caso, com o client_id do parceiro quando existe.
-- 5. _retorno_triar: o caso do parceiro vai ao _parceiro_triar, antes do "caso fechado não muda".
-- 6. _retorno_rotulo: "MP (Carla)" ou "MP (comercial)"; o número nunca aparece.
--
-- Sem dado. Nada muda enquanto nenhum número de parceiro estiver confirmado (a semente é da P3, com o dono).
-- Reverter: reaplicar quem_escreve (20261106100000), retorno_identificar (20261116100000), retorno_abrir e _retorno_triar
-- (20261116100600) e _retorno_rotulo (20261116101000); depois, drop function public._parceiro_triar(uuid, timestamptz).

-- ── 1. A triagem do caso do parceiro (nova) ─────────────────────────────────────────────────────────────────────────────

create or replace function public._parceiro_triar(p_abertura uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  -- mensagens que não são conversa: não dão sinal ao caso (as mesmas do _retorno_triar)
  c_fora_da_conversa constant text[] := array['robo', 'figurinha_ou_reacao', 'nao_e_conversa'];
  c_decididas constant text[] := array['sombra', 'enviada', 'incerta'];
  -- "pode executar" do plano (K8): vira recado, nunca aprovação
  c_pode_executar constant text := '^pode (executar|fazer|seguir|tocar)\y';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_ab public.retorno_aberturas;
  v_sinais jsonb;
  v_n_pede integer;
  v_n_pede_livre integer;
  v_insistencias integer;
  v_insiste_acorde uuid[];                 -- só para o bloco copiado do _retorno_triar: o parceiro nunca ganha acorde
  v_opt_out boolean;
  v_canal text;
  v_motivo text;
  v_nivel text;
  v_tipo text;
  v_intencao text;
  v_acao text;
  v_numero uuid;
  v_parceiro uuid;
  v_pessoa uuid;
  v_dados jsonb;
  v_ped public.parceiro_pedidos;
  v_tem_pedido boolean := false;
  v_p03 public.retorno_saidas;
  v_pd jsonb;
  v_mais integer;
  v_ultima timestamptz;
  v_saida_id uuid;
  r record;
begin
  -- Sem a linha de configuração ou com o retorno desligado: nada, sem mexer em nada (como _retorno_triar).
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('abertura_id', p_abertura, 'papel', null, 'nivel', 'nada', 'motivo', 'desligado',
                              'tipo_recibo', null, 'estado', null, 'modo', null, 'saida_id', null, 'acao', 'nada');
  end if;

  select * into v_ab from public.retorno_aberturas ab where ab.id = p_abertura for update;
  if not found then
    return jsonb_build_object('abertura_id', p_abertura, 'papel', null, 'nivel', 'nada', 'motivo', 'sem_caso',
                              'tipo_recibo', null, 'estado', null, 'modo', null, 'saida_id', null, 'acao', 'nada');
  end if;
  if v_ab.papel is distinct from 'parceiro' then
    raise exception using errcode = '22023', message = '_parceiro_triar: o caso não é de parceiro';
  end if;

  -- Caso fechado não muda mais: devolve como está.
  if v_ab.estado = 'fechada' then
    return jsonb_build_object('abertura_id', v_ab.id, 'papel', v_ab.papel, 'nivel', v_ab.nivel, 'motivo', v_ab.motivo,
                              'tipo_recibo', v_ab.tipo_recibo, 'estado', v_ab.estado, 'modo', v_ab.modo, 'saida_id', null,
                              'acao', 'nada');
  end if;

  -- Quem escreve, como quem_escreve gravou na abertura (C-QUEM): o número, a pessoa e o parceiro confirmados.
  v_numero := nullif(v_ab.quem ->> 'numero_id', '')::uuid;
  v_parceiro := nullif(v_ab.quem ->> 'parceiro_id', '')::uuid;
  v_pessoa := nullif(v_ab.quem ->> 'pessoa_id', '')::uuid;
  v_dados := jsonb_build_object('parceiro_id', v_parceiro, 'pessoa_id', v_pessoa, 'numero_id', v_numero,
                                'ultima_msg_id', v_ab.ultima_msg_id);

  -- ── As mensagens do caso gravadas até agora ──
  select count(*) filter (where rm.pede_resposta),
         count(*) filter (where rm.pede_resposta and not rm.consumida)
    into v_n_pede, v_n_pede_livre
    from public.retorno_mensagens rm
   where rm.abertura_id = v_ab.id
     and rm.gravada_em <= v_agora;

  -- As insistências e os sinais do caso: os mesmos blocos do _retorno_triar, copiados pelo gerador sem mudança.
  select count(*) filter (where i.insiste),
         coalesce(array_agg(i.msg order by i.ordem) filter (where i.insiste and i.n_insiste >= 2), '{}'::uuid[])
    into v_insistencias, v_insiste_acorde
    from (select p.msg, p.ordem, p.insiste,
                 sum(case when p.insiste then 1 else 0 end) over (order by p.ordem) as n_insiste
            from (select q.msg, q.ordem,
                         q.ant is not null
                         and q.recebida_em - q.ant >= v_cfg.insistencia_apos
                         and not exists (select 1 from public.whatsapp_messages o
                                          where public._agenda_chave_telefone(o.phone_normalized) = v_ab.chave
                                            and o.direction = 'outbound'
                                            and o.occurred_at <= v_agora
                                            and o.occurred_at >= q.ant
                                            and public._retorno_hora_real(o) > q.ant
                                            and public._retorno_hora_real(o) <= q.recebida_em
                                            and coalesce(o.saida_humana,
                                                         public._saida_e_humana(o.direction, o.raw_payload, o.sent_by)))
                           as insiste
                    from (select rm.whatsapp_message_id as msg, rm.recebida_em,
                                 row_number() over w as ordem,
                                 lag(rm.recebida_em) over w as ant
                            from public.retorno_mensagens rm
                           where rm.abertura_id = v_ab.id
                             and rm.pede_resposta
                             and rm.gravada_em <= v_agora
                          window w as (order by rm.recebida_em, rm.gravada_em, rm.whatsapp_message_id)) q) p) i;

  select coalesce(jsonb_object_agg(x.chave_sinal, x.valor), '{}'::jsonb)
    into v_sinais
    from (select e.key as chave_sinal,
                 case when bool_and(jsonb_typeof(e.value) = 'boolean')
                      then to_jsonb(bool_or(e.value = 'true'::jsonb))
                      else (array_agg(e.value order by rm.recebida_em, rm.gravada_em, rm.whatsapp_message_id)
                              filter (where jsonb_typeof(e.value) <> 'null'))[1]
                 end as valor
            from public.retorno_mensagens rm
            cross join lateral jsonb_each(rm.sinais) e
           where rm.abertura_id = v_ab.id
             and rm.gravada_em <= v_agora
             and coalesce(rm.pede_motivo, '') <> all (c_fora_da_conversa)
           group by e.key) x;

  -- ── As regras 1 a 4: nível nada, a 1ª que casa decide ──
  v_opt_out := exists (select 1 from public.whatsapp_blocked_numbers b
                        where b.tipo = 'opt_out'
                          and b.created_at <= v_agora
                          and public._agenda_chave_telefone(b.phone_normalized) = v_ab.chave);
  v_canal := public.canal_bloqueado(v_ab.phone_normalized);
  if v_cfg.parceiro_modo = 'desligado' then
    v_motivo := 'parceiro_f4';                                   -- 1
  elsif v_n_pede > 0 and v_n_pede_livre = 0 then
    v_motivo := 'agenda_consumiu';                               -- 2: *pátio*, *pausar*, *retomar* consumidas; sem recibo
  elsif v_n_pede = 0 then
    v_motivo := 'nao_pede_resposta';                             -- 3: robô, figurinha, agradecimento
  elsif v_canal = 'cliente_final' then
    v_motivo := 'cliente_final';                                 -- 4: o canal
  elsif v_canal = 'opt_out' or v_opt_out then
    v_motivo := 'opt_out';
  elsif v_canal is not null then
    v_motivo := 'bloqueado';
  elsif exists (select 1 from public.whatsapp_leads l
                 where l.lead_tipo = 'pessoal'
                   and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave)
        or exists (select 1 from public.parceiro_numeros n where n.id = v_numero and n.uso = 'pessoal') then
    v_motivo := 'pessoal';
  end if;

  -- ── As regras 5 a 8: recibo do parceiro (nunca passagem: o parceiro não tem relógio nem acorde) ──
  if v_motivo is null then
    v_nivel := 'recibo';
    v_tipo := 'recibo_parceiro';
    select * into v_ped from public.parceiro_pedidos pp where pp.abertura_id = v_ab.id;
    v_tem_pedido := found;
    if v_tem_pedido then
      v_acao := 'pedido';                                        -- 5: o caso já tem pedido (C13)
    elsif exists (select 1 from public.retorno_mensagens rm
                    join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
                   where rm.abertura_id = v_ab.id
                     and rm.pede_resposta
                     and not rm.consumida
                     and rm.gravada_em <= v_agora
                     and w.occurred_at <= v_agora
                     and public._texto_simples(btrim(coalesce(w.body, ''))) ~ c_pode_executar) then
      v_acao := 'recado';                                        -- 6: "pode executar" vira recado, nunca grava nada na OS
    else
      -- 7: pedido de serviço na janela DESTE caso (aberta_em), nunca nas 24 h do número.
      v_pd := public._retorno_pedido_de_servico(v_ab.chave, v_ab.aberta_em, v_agora, null);
      if coalesce((v_pd ->> 'pedido')::boolean, false) then
        v_acao := 'coleta';
      else
        v_acao := 'recibo';                                      -- 8
      end if;
    end if;
  else
    v_nivel := 'nada';
    v_tipo := null;
    v_acao := 'nada';
  end if;
  v_intencao := case when v_acao in ('pedido', 'coleta') then 'pedido_servico' else 'outro' end;

  -- O caso inteiro, a cada triagem, como o _retorno_triar: nunca prometido_ate, faixa nem passagem_em.
  update public.retorno_aberturas ab
     set nivel = v_nivel,
         motivo = v_motivo,
         tipo_recibo = v_tipo,
         sinais = v_sinais,
         intencao = v_intencao,
         insistencias = least(v_insistencias, 32767),
         atualizada_em = now()
   where ab.id = v_ab.id
   returning * into v_ab;

  if v_nivel = 'nada' then
    -- O caso que vira nada cancela as agendadas, como a F1. A saída que outra transação processa é pulada.
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'nivel_nada', decidida_em = v_agora, atualizada_em = now()
     where s.id in (select x.id from public.retorno_saidas x
                     where x.abertura_id = v_ab.id and x.estado = 'agendada' and x.tipo not in ('parar', 'acorde')
                     for update skip locked);

  elsif v_acao = 'recado' then
    -- 6. P05, e a pergunta na fila do cartão (P8.1).
    perform public.parceiro_agendar('parceiro_recado', null, v_numero, v_ab.id, v_dados,
                                    v_ab.aberta_em + v_cfg.parceiro_carencia, 'parceiro:recado:' || v_ab.id,
                                    'resposta_imediata');
    perform public._parceiro_fila_por('pergunta', v_parceiro, v_ab.id, 'pergunta:' || v_ab.id, null,
                                      jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'ultima_em', v_ab.ultima_em));

  elsif v_acao = 'coleta' then
    -- 7. O pedido (um por caso), a leitura do que a parceira disse e o P03.
    insert into public.parceiro_pedidos (abertura_id, parceiro_id, pessoa_id)
    values (v_ab.id, v_parceiro, v_pessoa)
    on conflict (abertura_id) do nothing;
    perform public.parceiro_coleta_ler(v_ab.id, v_agora);
    select * into v_ped from public.parceiro_pedidos pp where pp.abertura_id = v_ab.id;
    perform public.parceiro_agendar('parceiro_coleta', 'veiculo_nome', v_numero, v_ab.id,
                                    v_dados || jsonb_build_object('pedido_id', v_ped.id),
                                    v_ab.aberta_em + v_cfg.parceiro_carencia,
                                    'parceiro:coleta:' || v_ab.id || ':' || (v_ab.coleta_n + 1), 'resposta_imediata');

  elsif v_acao = 'pedido' then
    -- 5. O caso já tem pedido. Nunca P02.
    if v_ped.estado = 'coleta' then
      -- parceiro_coleta_ler preenche só campo nulo e grava completo_em com a hora real da mensagem que completou
      -- veículo e nome; a linha é relida depois.
      perform public.parceiro_coleta_ler(v_ab.id, v_agora);
      select * into v_ped from public.parceiro_pedidos pp where pp.id = v_ped.id;
      -- P04: com o P03 decidido, uma resposta que pede resposta recebida depois dele, o veículo lido e menos de
      -- coleta_max mensagens. Nunca antes do P03: greatest com o enviar_em dele + 1 minuto.
      if v_ped.veiculo is not null and v_ab.coleta_n < v_cfg.coleta_max then
        select * into v_p03 from public.retorno_saidas s
         where s.abertura_id = v_ab.id and s.emissor = 'parceiro' and s.tipo = 'parceiro_coleta' and s.variante = 'veiculo_nome'
         order by s.criada_em, s.id
         limit 1;
        if v_p03.estado = any (c_decididas) and v_p03.decidida_em <= v_agora then
          select rm.whatsapp_message_id as msg, rm.gravada_em into r
            from public.retorno_mensagens rm
           where rm.abertura_id = v_ab.id
             and rm.pede_resposta
             and not rm.consumida
             and rm.recebida_em > v_p03.decidida_em
             and rm.gravada_em > v_p03.decidida_em
             and rm.gravada_em <= v_agora
           order by rm.recebida_em, rm.whatsapp_message_id
           limit 1;
          if found then
            perform public.parceiro_agendar('parceiro_coleta', 'whatsapp', v_numero, v_ab.id,
                                            v_dados || jsonb_build_object('pedido_id', v_ped.id, 'mensagem', r.msg),
                                            greatest(r.gravada_em + make_interval(mins => v_cfg.carencia_min),
                                                     v_p03.enviar_em + interval '1 minute'),
                                            'parceiro:coleta:' || v_ab.id || ':' || (v_ab.coleta_n + 1), 'resposta_imediata');
          end if;
        end if;
      end if;
    end if;

    -- mais_pedidos: recalculado, nunca somado. A mensagem com pedido explícito recebida depois de completo_em (a que
    -- completou a coleta não entra: > estrito), pela fórmula de _retorno_pedido_de_servico sobre os sinais da própria linha.
    if v_ped.completo_em is not null and v_ped.estado in ('coleta', 'cadastrado', 'cartao') then
      select count(*) into v_mais
        from public.retorno_mensagens rm
       where rm.abertura_id = v_ab.id
         and rm.pede_resposta
         and rm.gravada_em <= v_agora
         and rm.recebida_em > v_ped.completo_em
         and (coalesce((rm.sinais ->> 'site')::boolean, false)
              or (coalesce((rm.sinais ->> 'servico')::boolean, false)
                  and coalesce((rm.sinais ->> 'bem')::boolean, false)
                  and coalesce((rm.sinais ->> 'pedido')::boolean, false)))
         and not coalesce((rm.sinais ->> 'vendedor')::boolean, false);
      update public.parceiro_pedidos pp
         set mais_pedidos = least(v_mais, 32767)
       where pp.id = v_ped.id
         and pp.mais_pedidos is distinct from least(v_mais, 32767)::smallint;
    end if;

    -- P15: em cadastrado ou cartao, a mensagem que pede resposta depois de completo_em, uma vez por caso.
    if v_ped.estado in ('cadastrado', 'cartao') and v_ped.completo_em is not null
       and not exists (select 1 from public.retorno_saidas s
                        where s.abertura_id = v_ab.id and s.emissor = 'parceiro'
                          and s.tipo = 'parceiro_recibo' and s.variante = 'orcamento') then
      select max(rm.gravada_em) into v_ultima
        from public.retorno_mensagens rm
       where rm.abertura_id = v_ab.id
         and rm.pede_resposta
         and not rm.consumida
         and rm.recebida_em > v_ped.completo_em
         and rm.gravada_em <= v_agora;
      if v_ultima is not null then
        perform public.parceiro_agendar('parceiro_recibo', 'orcamento', v_numero, v_ab.id,
                                        v_dados || jsonb_build_object('pedido_id', v_ped.id),
                                        v_ultima + make_interval(mins => v_cfg.carencia_min),
                                        'parceiro:recibo:' || v_ab.id || ':orcamento', 'resposta_imediata');
      end if;
    end if;

  else
    -- 8. O P02 (o bloco P11 é decidido no parceiro_pegar, P5) e a pergunta na fila do cartão.
    perform public.parceiro_agendar('parceiro_recibo', null, v_numero, v_ab.id, v_dados,
                                    v_ab.aberta_em + v_cfg.parceiro_carencia, 'parceiro:recibo:' || v_ab.id,
                                    'resposta_imediata');
    perform public._parceiro_fila_por('pergunta', v_parceiro, v_ab.id, 'pergunta:' || v_ab.id, null,
                                      jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'ultima_em', v_ab.ultima_em));
  end if;

  select s.id into v_saida_id from public.retorno_saidas s
   where s.abertura_id = v_ab.id and s.emissor = 'parceiro'
     and s.tipo in ('parceiro_recibo', 'parceiro_coleta', 'parceiro_recado')
   order by s.criada_em, s.id
   limit 1;

  return jsonb_build_object('abertura_id', v_ab.id, 'papel', v_ab.papel, 'nivel', v_nivel, 'motivo', v_motivo,
                            'tipo_recibo', v_tipo, 'estado', v_ab.estado, 'modo', v_ab.modo, 'saida_id', v_saida_id,
                            'acao', v_acao);
end;
$$;

comment on function public._parceiro_triar(uuid, timestamptz) is
  'Retorno F4 (P2): a triagem do caso do parceiro, chamada pelo _retorno_triar. Regras na ordem: 1 parceiro_modo desligado (parceiro_f4), 2 tudo consumido (agenda_consumiu), 3 nada pede resposta, 4 canal bloqueado ou pessoal; 5 pedido do caso (coleta, P04, mais_pedidos, P15), 6 "pode executar" (recado + pergunta), 7 pedido de serviço na janela do caso (coleta + P03), 8 o resto (P02 + pergunta). Grava nivel, motivo, tipo_recibo, intencao, sinais e insistencias; nunca passagem nem prometido_ate. As regras 5 a 8 agendam por parceiro_agendar (P5); 5 e 7 leem por parceiro_coleta_ler (P10).';

revoke all on function public._parceiro_triar(uuid, timestamptz) from public, anon, authenticated;

-- ── 2. Gerado do corpo vigente, com os trechos -- F4 ───────────────────────────────────────────────────────────────────

create or replace function public.quem_escreve(p_fone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_chave text := public._agenda_chave_telefone(p_fone);
  v_ddd text := public._ddd_do_telefone(p_fone);
  v_equipe boolean;
  v_identificam uuid[];
  v_ambiguos uuid[];
  v_motivo text;
  v_fornecedores uuid[];
  v_num uuid;                -- F4: o número de parceiro confirmado
  v_pessoa uuid;             -- F4: a pessoa dele
  v_parceiro uuid;           -- F4: o parceiro
  v_cliente_parceiro uuid;   -- F4: o cadastro do parceiro como cliente, quando existe
begin
  if v_chave is null then
    return jsonb_build_object('papel', 'sem_numero', 'versao', 1);
  end if;

  -- Equipe pelo mesmo telefone (8 dígitos e o mesmo DDD): um estranho com os 8 dígitos do dono não vira equipe.
  select exists (select 1 from public.app_users u
                  where u.active and (public._mesmo_telefone(p_fone, u.phone_normalized) or public._mesmo_telefone(p_fone, u.phone)))
      or exists (select 1 from public.payees p
                  where p.active and public._mesmo_telefone(p_fone, p.phone))
    into v_equipe;
  if v_equipe then
    return jsonb_build_object('papel', 'equipe', 'chave', v_chave, 'ddd', v_ddd, 'versao', 1);
  end if;

  -- Cada cliente pelo telefone que casa (o whatsapp antes do phone): com o mesmo DDD (ou sem DDD
  -- do lado de quem escreve) identifica; DDD diferente ou cadastro sem DDD fica ambíguo.
  with casam as (
    select c.id,
           public._ddd_do_telefone(case when public._agenda_chave_telefone(c.whatsapp) = v_chave then c.whatsapp else c.phone end) as ddd
      from public.clients c
     where c.active and not c.generico
       and v_chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
  )
  select coalesce(array_agg(id order by id) filter (where ddd is not null and (v_ddd is null or ddd = v_ddd)), '{}'),
         coalesce(array_agg(id order by id) filter (where ddd is null or (v_ddd is not null and ddd <> v_ddd)), '{}'),
         case
           when count(*) filter (where ddd is not null and v_ddd is not null and ddd <> v_ddd) > 0 then 'ddd_diferente'
           when count(*) filter (where ddd is null) > 0 then 'cadastro_sem_ddd'
           when count(*) > 1 then 'varios_clientes'
         end
    into v_identificam, v_ambiguos, v_motivo
    from casam;

  -- F4: pessoa de parceiro confirmada, pelo número. Vale antes da precedência do cliente só quando o cliente
  -- do número é o próprio parceiro. Com outro cliente no número, o cliente vence e a marca fica no retorno.
  select n.id, p.id, pa.id, pa.client_id into v_num, v_pessoa, v_parceiro, v_cliente_parceiro
    from public.parceiro_numeros n
    join public.parceiro_pessoas p on p.id = n.pessoa_id and p.ativo
    join public.parceiros pa on pa.id = p.parceiro_id and pa.ativo
   where n.chave = v_chave and n.situacao = 'confirmado'
     and (n.ddd is null or v_ddd is null or n.ddd = v_ddd)
   limit 1;
  if found and cardinality(v_ambiguos) = 0
     and (cardinality(v_identificam) = 0
          or (cardinality(v_identificam) = 1 and v_identificam[1] = v_cliente_parceiro)) then
    return jsonb_build_object('papel', 'parceiro', 'chave', v_chave, 'ddd', v_ddd, 'parceiro_id', v_parceiro,
                              'pessoa_id', v_pessoa, 'numero_id', v_num, 'cliente_id', v_cliente_parceiro, 'versao', 1);
  end if;

  if cardinality(v_identificam) = 1 and cardinality(v_ambiguos) = 0 then
    return jsonb_build_object('papel', 'cliente', 'chave', v_chave, 'ddd', v_ddd,
                              'cliente_id', v_identificam[1], 'clientes', to_jsonb(v_identificam), 'versao', 1);
  end if;
  if cardinality(v_identificam) + cardinality(v_ambiguos) > 0 then
    return jsonb_build_object('papel', 'cliente_ambiguo', 'chave', v_chave, 'ddd', v_ddd,
                              'clientes', to_jsonb(v_identificam || v_ambiguos), 'motivo', v_motivo, 'versao', 1);
  end if;

  -- F4: a pessoa de parceiro confirmada pelo dono entra antes da precedência do cliente (acima), não aqui.

  select coalesce(array_agg(s.id order by s.id), '{}') into v_fornecedores
    from public.suppliers s
   where s.active and public._agenda_chave_telefone(s.phone) = v_chave;
  if cardinality(v_fornecedores) > 0 then
    return jsonb_build_object('papel', 'fornecedor', 'chave', v_chave, 'ddd', v_ddd,
                              'fornecedores', to_jsonb(v_fornecedores), 'versao', 1);
  end if;

  return jsonb_build_object('papel', 'novo', 'chave', v_chave, 'ddd', v_ddd, 'versao', 1);
end;
$$;

create or replace function public.retorno_identificar(p_fone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
  q jsonb;
begin
  -- Desligada ou sem a linha: o webhook segue o ILIKE de hoje.
  if v_cfg.id is null or not v_cfg.identificacao_nova then
    return jsonb_build_object('nova', false);
  end if;

  -- Erro aqui sobe de propósito: o webhook trata a exceção caindo no caminho de hoje.
  q := public.quem_escreve(p_fone);

  -- Só o papel "cliente" (1 cadastro ativo, mesmo DDD) dá client_id. Ambíguo nunca escolhe.
  return jsonb_build_object(
    'nova', true,
    'papel', q ->> 'papel',
    -- F4: o parceiro com cadastro de cliente (a MP) também, como hoje; sem cadastro, cliente_id é nulo.
    'client_id', case when q ->> 'papel' in ('cliente', 'parceiro') then (q ->> 'cliente_id')::uuid end,
    'clientes', case when jsonb_typeof(q -> 'clientes') = 'array' then q -> 'clientes' else '[]'::jsonb end);
end;
$$;

create or replace function public.retorno_abrir(p_msg uuid, p_consumida boolean default false,
                                                p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_consome constant text[] := array['confirmou', 'ciencia', 'replanejou', 'anotou_acesso', 'opt_out'];
  c_ao_dono constant text[] := array['ao_dono', 'ambigua'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config;
  v_m public.whatsapp_messages;
  v_chave text;
  v_real timestamptz;
  v_hash text;
  v_rm public.retorno_mensagens;
  v_reav boolean := false;
  v_q jsonb;
  v_papel text;
  v_papel_caso text;
  v_lead uuid;
  v_lead_nome text;
  v_n_leads integer;
  v_s jsonb;
  v_p jsonb;
  v_pede boolean;
  v_cons_agenda boolean;
  v_ao_dono boolean;
  v_consumida boolean;
  v_ab public.retorno_aberturas;
  v_tem_caso boolean := false;
  v_clientes uuid[];
  v_caso uuid;
  v_acao text;
  v_motivo text;
  v_saida uuid;
begin
  begin
    <<passos>>
    begin
      -- 1. Sem a linha de configuração ou desligado: nada roda nem registra.
      v_cfg := public._retorno_cfg();
      if v_cfg.id is null or v_cfg.modo = 'desligado' then
        v_acao := 'ignorada';
        v_motivo := 'desligado';
        exit passos;
      end if;

      -- 2. A mensagem: só a recebida de conversa, gravada até agora.
      select * into v_m from public.whatsapp_messages w where w.id = p_msg;
      if not found then
        v_acao := 'ignorada';
        v_motivo := 'sem_mensagem';
        exit passos;
      end if;
      if v_m.occurred_at > v_agora then
        v_acao := 'ignorada';
        v_motivo := 'futura';
        exit passos;
      end if;
      v_chave := public._agenda_chave_telefone(v_m.phone_normalized);
      if v_m.direction is distinct from 'inbound' or coalesce(v_m.phone_normalized, '') ~ '@'
         or coalesce(v_m.is_broadcast, false) or v_chave is null then
        v_acao := 'ignorada';
        v_motivo := 'nao_e_conversa';
        exit passos;
      end if;

      -- 3. Uma mensagem por vez por número: a rajada nunca abre dois casos.
      perform pg_advisory_xact_lock(hashtext('retorno:' || v_chave));

      -- 4. Idempotência pelo id da mensagem; o corpo trocado (transcrição) reavalia.
      v_hash := md5(coalesce(v_m.body, ''));
      select * into v_rm from public.retorno_mensagens r where r.whatsapp_message_id = v_m.id;
      if found then
        if v_rm.corpo_hash = v_hash then
          v_acao := 'repetida';
          v_caso := v_rm.abertura_id;
          v_motivo := v_rm.pede_motivo;
          exit passos;
        end if;
        v_reav := true;
      end if;

      -- 5. Quem escreve (F0b): a equipe e o número sem os 8 dígitos nunca abrem caso.
      v_q := public.quem_escreve(v_m.phone_normalized);
      v_papel := v_q ->> 'papel';
      if v_papel is null or v_papel in ('equipe', 'sem_numero') then
        v_acao := 'ignorada';
        v_motivo := coalesce(v_papel, 'sem_papel');
        exit passos;
      end if;

      -- 6. O papel do caso.
      v_papel := case
        when v_papel = 'cliente' and (v_q ->> 'cliente_id')::uuid = any (v_cfg.clientes_parceiros) then 'cliente_parceiro'
        when v_papel = 'novo' then
          case when public._retorno_numero_novo(v_chave, v_m.occurred_at) then 'numero_novo' else 'contato_conhecido' end
        else v_papel
      end;
      if v_papel not in ('cliente', 'cliente_ambiguo', 'cliente_parceiro', 'numero_novo', 'contato_conhecido', 'fornecedor',
                         'parceiro') then   -- F4: a pessoa de parceiro confirmada (P2)
        v_acao := 'ignorada';
        v_motivo := 'papel_desconhecido';
        exit passos;
      end if;

      -- O lead do telefone (o mesmo número: 8 dígitos e o mesmo DDD). Dois leads = nenhum: nunca escolhe.
      select (array_agg(l.id order by l.id))[1], (array_agg(l.name order by l.id))[1], count(*)
        into v_lead, v_lead_nome, v_n_leads
        from public.whatsapp_leads l
       where public._mesmo_telefone(l.phone_normalized, v_m.phone_normalized);
      if v_n_leads <> 1 then
        v_lead := null;
        v_lead_nome := null;
      end if;

      -- O caso: o da própria mensagem (reavaliação) ou o caso vivo do número.
      if v_reav and v_rm.abertura_id is not null then
        select * into v_ab from public.retorno_aberturas ab where ab.id = v_rm.abertura_id for update;
        v_tem_caso := found;
      else
        select * into v_ab from public.retorno_aberturas ab
         where ab.chave = v_chave and ab.estado in ('aberta', 'vencida')
         for update;
        v_tem_caso := found;
      end if;
      v_papel_caso := case when v_tem_caso then v_ab.papel else v_papel end;

      -- 7. Sinais (o nome do lead só no número novo: é o "Consultor de Vendas" do perfil), "pede resposta" e o
      --    que a agenda fez com esta mensagem (a linha dela, gravada antes de o webhook chamar o retorno).
      v_s := public._retorno_sinais(v_m.body, case when v_papel_caso = 'numero_novo' then v_lead_nome end);
      v_p := public._retorno_pede_resposta(v_m.id);
      v_pede := coalesce((v_p ->> 'pede')::boolean, false);
      select coalesce(bool_or(r.efeito = any (c_consome)), false), coalesce(bool_or(r.efeito = any (c_ao_dono)), false)
        into v_cons_agenda, v_ao_dono
        from public.agenda_cliente_respostas r
       where r.whatsapp_message_id = v_m.id
         and r.modo = 'ligado';
      v_consumida := coalesce(p_consumida, false) or v_cons_agenda or coalesce(v_rm.consumida, false);
      v_ao_dono := v_ao_dono or coalesce(v_rm.agenda_ao_dono, false);
      v_real := public._retorno_hora_real(v_m);

      -- Reavaliação de mensagem de caso já fechado: só a linha da mensagem muda; o caso não reabre.
      if v_reav and v_tem_caso and v_ab.estado = 'fechada' then
        update public.retorno_mensagens r
           set corpo_hash = v_hash, sinais = v_s, pede_resposta = v_pede, pede_motivo = v_p ->> 'motivo',
               audio_pendente = coalesce((v_s ->> 'audio_pendente')::boolean, false),
               consumida = v_consumida, agenda_ao_dono = v_ao_dono, processada_em = now()
         where r.whatsapp_message_id = v_m.id;
        v_acao := 'reavaliada';
        v_caso := v_ab.id;
        exit passos;
      end if;

      -- 8. Abrir, estender ou só registrar.
      if not v_tem_caso then
        if not v_pede and not coalesce((v_s ->> 'parar')::boolean, false)
           and not coalesce((v_s ->> 'parar_largo')::boolean, false) then
          -- Não pede resposta e não há caso: só a linha da mensagem (a idempotência e o vigia do áudio).
          insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em,
                                                corpo_hash, sinais, pede_resposta, pede_motivo, audio_pendente,
                                                consumida, agenda_ao_dono)
          values (v_m.id, null, v_chave, v_real, v_m.occurred_at, v_hash, v_s, v_pede, v_p ->> 'motivo',
                  coalesce((v_s ->> 'audio_pendente')::boolean, false), v_consumida, v_ao_dono)
          on conflict (whatsapp_message_id) do update
            set corpo_hash = excluded.corpo_hash, sinais = excluded.sinais, pede_resposta = excluded.pede_resposta,
                pede_motivo = excluded.pede_motivo, audio_pendente = excluded.audio_pendente,
                consumida = excluded.consumida, agenda_ao_dono = excluded.agenda_ao_dono, processada_em = now();
          v_acao := case when v_reav then 'reavaliada' else 'ignorada' end;
          v_motivo := v_p ->> 'motivo';
          exit passos;
        end if;
        v_clientes := case when jsonb_typeof(v_q -> 'clientes') = 'array'
                           then array(select e::uuid from jsonb_array_elements_text(v_q -> 'clientes') as e)
                           else '{}'::uuid[] end;
        insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, clientes, lead_id,
                                              primeira_msg_id, ultima_msg_id, msgs, aberta_em, gravada_em, ultima_em,
                                              ultima_gravada_em, atraso_gravacao, nivel, motivo, modo)
        values (v_chave, v_m.phone_normalized, v_q ->> 'ddd', v_papel, v_q,
                case when v_papel in ('cliente', 'cliente_parceiro', 'parceiro') then (v_q ->> 'cliente_id')::uuid end,   -- F4
                coalesce(v_clientes, '{}'::uuid[]), v_lead, v_m.id, v_m.id, 1, v_real, v_m.occurred_at, v_real,
                v_m.occurred_at, greatest(v_m.occurred_at - v_real, interval '0'),
                'nada', 'nao_pede_resposta',          -- provisório: a triagem logo abaixo decide
                case when v_cfg.modo = 'ligado' then 'ligado' else 'sombra' end)
        returning * into v_ab;
        v_acao := case when v_reav then 'reavaliada' else 'nova' end;
      elsif v_reav and v_rm.abertura_id is not distinct from v_ab.id then
        -- A mensagem já é do caso: nada a somar, só triar de novo.
        v_acao := 'reavaliada';
      else
        -- Estende o caso. As insistências não se somam aqui: a triagem as recalcula do caso inteiro, e assim a
        -- cópia do robô revelado e o áudio transcrito que não pede saem da conta.
        update public.retorno_aberturas ab
           set ultima_msg_id = case when v_real >= ab.ultima_em then v_m.id else ab.ultima_msg_id end,
               ultima_em = greatest(ab.ultima_em, v_real),
               ultima_gravada_em = greatest(ab.ultima_gravada_em, v_m.occurred_at),
               msgs = least(ab.msgs + 1, 32767),
               atualizada_em = now()
         where ab.id = v_ab.id
         returning * into v_ab;
        v_acao := case when v_reav then 'reavaliada' else 'estendida' end;
      end if;
      v_caso := v_ab.id;

      -- 9. A linha da mensagem, com o caso, e a triagem do caso inteiro.
      insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em,
                                            corpo_hash, sinais, pede_resposta, pede_motivo, audio_pendente,
                                            consumida, agenda_ao_dono)
      values (v_m.id, v_ab.id, v_chave, v_real, v_m.occurred_at, v_hash, v_s, v_pede, v_p ->> 'motivo',
              coalesce((v_s ->> 'audio_pendente')::boolean, false), v_consumida, v_ao_dono)
      on conflict (whatsapp_message_id) do update
        set abertura_id = coalesce(retorno_mensagens.abertura_id, excluded.abertura_id),
            corpo_hash = excluded.corpo_hash, sinais = excluded.sinais, pede_resposta = excluded.pede_resposta,
            pede_motivo = excluded.pede_motivo, audio_pendente = excluded.audio_pendente,
            consumida = excluded.consumida, agenda_ao_dono = excluded.agenda_ao_dono, processada_em = now();

      -- Robô revelado: o detector da F0b viu o mesmo texto longo pela 3ª vez; as cópias anteriores deste caso
      -- eram o mesmo robô e deixam de pedir resposta. Só o texto idêntico: o resto do caso fica como está.
      -- Não roda quando o recibo do caso já saiu ou está saindo (o cliente ouviu, ou teria ouvido na sombra, a
      -- promessa): o caso viraria 'nada' e o adiamento e o fim do dia, que garantem o aviso honesto (§3), seriam
      -- cancelados aqui e pelo _retorno_checar_antes (P6). A 3ª cópia já não pede; as anteriores seguem.
      if v_p ->> 'motivo' = 'robo' and length(btrim(coalesce(v_m.body, ''))) >= 60
         and public._retorno_e_automatico(v_m.phone_normalized, v_m.body, v_m.raw_payload, v_m.occurred_at)
         and not exists (select 1 from public.retorno_saidas s
                          where s.dedupe_key = 'retorno:' || v_ab.id || ':recibo'
                            and (s.estado in ('preparada', 'enviando')
                                 or (s.estado in ('sombra', 'enviada', 'incerta') and s.decidida_em <= v_agora))) then
        update public.retorno_mensagens r
           set pede_resposta = false, pede_motivo = 'robo'
          from public.whatsapp_messages w
         where r.abertura_id = v_ab.id
           and r.whatsapp_message_id = w.id
           and r.whatsapp_message_id <> v_m.id
           and r.pede_resposta
           and w.occurred_at <= v_agora
           and btrim(lower(w.body)) = btrim(lower(v_m.body));
      end if;

      perform public._retorno_triar(v_ab.id, v_agora);
    end passos;

    -- 10. A resposta (C-ABRIR), com o estado do caso depois da triagem.
    if v_caso is not null then
      select * into v_ab from public.retorno_aberturas ab where ab.id = v_caso;
      select s.id into v_saida from public.retorno_saidas s
       where s.dedupe_key in ('retorno:' || v_caso || ':recibo', 'retorno:' || v_caso || ':saudacao')
       order by (s.dedupe_key like '%:recibo') desc limit 1;
    end if;
    return jsonb_build_object(
      'ok', true,
      'abertura_id', v_caso,
      'acao', v_acao,
      'papel', case when v_caso is not null then v_ab.papel else v_papel end,
      'nivel', case when v_caso is not null then v_ab.nivel end,
      'motivo', case when v_caso is not null then v_ab.motivo else v_motivo end,
      'saida_id', v_saida,
      'modo', case when v_caso is not null then v_ab.modo end);
  exception when others then
    -- Nunca derruba o webhook nem o vigia: o erro vai ao app_error_logs, e a próxima mensagem segue.
    perform public.log_app_error('db', 'retorno_abrir: ' || sqlerrm, 'retorno', 'abrir', 'error',
                                 jsonb_build_object('mensagem', p_msg, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'erro', left(sqlerrm, 200));
  end;
end;
$$;

create or replace function public._retorno_triar(p_abertura uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  -- mensagens que não são conversa: não dão sinal ao caso (robô, figurinha, reação, grupo)
  c_fora_da_conversa constant text[] := array['robo', 'figurinha_ou_reacao', 'nao_e_conversa'];
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_decididas constant text[] := array['sombra', 'enviada', 'incerta'];
  -- a lista de serviço de _retorno_sinais (P2, 20261116100300), para a coleta dizer as palavras achadas
  c_re_servico constant text :=
    '\y(orcamento|orcamentos|orcar|instalar|instalacao|instalacoes|trocar|troca|bateria|baterias|inversor|inversores|placa solar|placas solares|painel solar|paineis solares|energia solar|gerador|eletrica|eletrico|ar condicionado|bomba|carregador|tomada|tomadas|chicote)\y';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_ab public.retorno_aberturas;
  v_ult public.retorno_mensagens;          -- a mensagem que disparou: a última do caso até agora
  v_sinais jsonb;
  v_n_pede integer;
  v_n_pede_livre integer;
  v_n_pede_saudacao integer;
  v_tem_robo boolean;
  v_tem_vendedor boolean;
  v_tem_audio boolean;
  v_tem_parar boolean;                     -- alguma mensagem do caso é PARAR (exato)
  v_tem_parar_largo boolean;               -- alguma mensagem do caso é PARAR por extenso
  v_opt_out boolean;                       -- o opt-out da chave está gravado (até agora)
  v_insistencias integer;
  v_insiste_acorde uuid[];                 -- as mensagens da 2ª insistência em diante (ganham acorde)
  v_vencido boolean;
  v_canal text;
  v_lead_nome text;
  v_desde timestamptz;
  v_pd jsonb;
  v_pedido boolean := false;
  v_prometido timestamptz;
  v_nivel text;
  v_motivo text;
  v_tipo text;
  v_intencao text;
  v_risco boolean;
  v_passagem boolean;
  v_vencida_desde timestamptz;
  v_dono_ativo boolean;
  v_carencia interval;
  v_enviar timestamptz;
  v_recibo public.retorno_saidas;
  v_saudacao public.retorno_saidas;
  v_coleta_saida public.retorno_saidas;
  v_nome text;
  v_coleta jsonb;
  v_servicos text;
  v_tipo_bem text;
  v_modelo text;
  v_saida_id uuid;
  r record;
begin
  -- Sem a linha de configuração ou com o retorno desligado: nada (falha fecha), sem mexer em nada.
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('abertura_id', p_abertura, 'papel', null, 'nivel', 'nada', 'motivo', 'desligado',
                              'tipo_recibo', null, 'estado', null, 'modo', null, 'saida_id', null);
  end if;

  select * into v_ab from public.retorno_aberturas ab where ab.id = p_abertura for update;
  if not found then
    return jsonb_build_object('abertura_id', p_abertura, 'papel', null, 'nivel', 'nada', 'motivo', 'sem_caso',
                              'tipo_recibo', null, 'estado', null, 'modo', null, 'saida_id', null);
  end if;

  -- F4 (P2): o caso do parceiro tem triagem própria, que repete o "caso fechado não muda".
  if v_ab.papel = 'parceiro' then
    return public._parceiro_triar(p_abertura, p_agora);
  end if;

  -- Caso fechado não muda mais: devolve como está.
  if v_ab.estado = 'fechada' then
    select s.id into v_saida_id from public.retorno_saidas s
     where s.dedupe_key in ('retorno:' || v_ab.id || ':recibo', 'retorno:' || v_ab.id || ':saudacao')
     order by (s.dedupe_key like '%:recibo') desc limit 1;
    return jsonb_build_object('abertura_id', v_ab.id, 'papel', v_ab.papel, 'nivel', v_ab.nivel, 'motivo', v_ab.motivo,
                              'tipo_recibo', v_ab.tipo_recibo, 'estado', v_ab.estado, 'modo', v_ab.modo,
                              'saida_id', v_saida_id);
  end if;

  -- ── As mensagens do caso gravadas até agora ──
  select count(*) filter (where rm.pede_resposta),
         count(*) filter (where rm.pede_resposta and not rm.consumida),
         count(*) filter (where rm.pede_resposta and coalesce((rm.sinais ->> 'saudacao')::boolean, false)),
         coalesce(bool_or(rm.pede_motivo = 'robo'), false),
         coalesce(bool_or(coalesce((rm.sinais ->> 'vendedor')::boolean, false)), false),
         coalesce(bool_or(rm.audio_pendente), false),
         coalesce(bool_or(coalesce((rm.sinais ->> 'parar')::boolean, false)), false),
         coalesce(bool_or(coalesce((rm.sinais ->> 'parar_largo')::boolean, false)), false)
    into v_n_pede, v_n_pede_livre, v_n_pede_saudacao, v_tem_robo, v_tem_vendedor, v_tem_audio,
         v_tem_parar, v_tem_parar_largo
    from public.retorno_mensagens rm
   where rm.abertura_id = v_ab.id
     and rm.gravada_em <= v_agora;

  select * into v_ult from public.retorno_mensagens rm
   where rm.abertura_id = v_ab.id and rm.gravada_em <= v_agora
   order by rm.recebida_em desc, rm.gravada_em desc, rm.whatsapp_message_id desc
   limit 1;

  -- As insistências, do caso inteiro, a cada triagem (nunca somadas na chegada): o par seguido de mensagens
  -- que PEDEM resposta, a 2ª insistencia_apos ou mais depois da 1ª, sem saída humana entre as duas (só as
  -- gravadas até agora). A cópia que o robô revelado deixou de pedir e o '[audio]' transcrito que não pede
  -- saem da conta sozinhos. Ganha acorde a 2ª insistência em diante (a que leva a conta a 2, e cada nova
  -- depois dela); a mensagem que chega 1 min depois não é insistência e não ganha.
  select count(*) filter (where i.insiste),
         coalesce(array_agg(i.msg order by i.ordem) filter (where i.insiste and i.n_insiste >= 2), '{}'::uuid[])
    into v_insistencias, v_insiste_acorde
    from (select p.msg, p.ordem, p.insiste,
                 sum(case when p.insiste then 1 else 0 end) over (order by p.ordem) as n_insiste
            from (select q.msg, q.ordem,
                         q.ant is not null
                         and q.recebida_em - q.ant >= v_cfg.insistencia_apos
                         and not exists (select 1 from public.whatsapp_messages o
                                          where public._agenda_chave_telefone(o.phone_normalized) = v_ab.chave
                                            and o.direction = 'outbound'
                                            and o.occurred_at <= v_agora
                                            and o.occurred_at >= q.ant
                                            and public._retorno_hora_real(o) > q.ant
                                            and public._retorno_hora_real(o) <= q.recebida_em
                                            and coalesce(o.saida_humana,
                                                         public._saida_e_humana(o.direction, o.raw_payload, o.sent_by)))
                           as insiste
                    from (select rm.whatsapp_message_id as msg, rm.recebida_em,
                                 row_number() over w as ordem,
                                 lag(rm.recebida_em) over w as ant
                            from public.retorno_mensagens rm
                           where rm.abertura_id = v_ab.id
                             and rm.pede_resposta
                             and rm.gravada_em <= v_agora
                          window w as (order by rm.recebida_em, rm.gravada_em, rm.whatsapp_message_id)) q) p) i;

  -- O caso vencido: o vigia já o marcou, ou a promessa do dono que o relógio adotou passou sem resposta de
  -- conteúdo (o vigia marca no minuto seguinte; a mensagem que chega antes não pode ganhar recibo novo, e o
  -- relógio da promessa fica para o vigia ver).
  v_vencido := v_ab.estado = 'vencida'
               or coalesce(v_ab.prometido_fonte = 'dono' and v_ab.prometido_ate <= v_agora and v_ab.cumprida_em is null,
                           false);

  -- Os sinais do caso: OU dos booleanos e o 1º valor dos textos (bem_palavra, modelo, ano), só das
  -- mensagens de conversa.
  select coalesce(jsonb_object_agg(x.chave_sinal, x.valor), '{}'::jsonb)
    into v_sinais
    from (select e.key as chave_sinal,
                 case when bool_and(jsonb_typeof(e.value) = 'boolean')
                      then to_jsonb(bool_or(e.value = 'true'::jsonb))
                      else (array_agg(e.value order by rm.recebida_em, rm.gravada_em, rm.whatsapp_message_id)
                              filter (where jsonb_typeof(e.value) <> 'null'))[1]
                 end as valor
            from public.retorno_mensagens rm
            cross join lateral jsonb_each(rm.sinais) e
           where rm.abertura_id = v_ab.id
             and rm.gravada_em <= v_agora
             and coalesce(rm.pede_motivo, '') <> all (c_fora_da_conversa)
           group by e.key) x;
  v_risco := coalesce((v_sinais ->> 'risco')::boolean, false);

  select l.name into v_lead_nome from public.whatsapp_leads l where l.id = v_ab.lead_id;

  -- ── As regras de 'nada', na ordem: a 1ª que casa decide ──
  -- O opt-out gravado da chave: o do gatilho da F0b no PARAR exato (ou outro anterior), só o criado até agora.
  v_opt_out := exists (select 1 from public.whatsapp_blocked_numbers b
                        where b.tipo = 'opt_out'
                          and b.created_at <= v_agora
                          and public._agenda_chave_telefone(b.phone_normalized) = v_ab.chave);
  v_canal := public.canal_bloqueado(v_ab.phone_normalized);
  if v_canal = 'cliente_final' then
    v_motivo := 'cliente_final';
  elsif coalesce((v_ult.sinais ->> 'parar')::boolean, false) and v_opt_out then
    -- 2. O PARAR que disparou, com o opt-out gravado. Depois dele, a mensagem nova cai na regra 4 (opt_out:
    --    pediu para parar e voltou a escrever, vai a "Para conferir").
    v_motivo := 'parar';
  elsif v_tem_parar_largo or (v_tem_parar and not v_opt_out) then
    -- 3. O PARAR por extenso em qualquer mensagem do caso (não há opt-out para segurar a mensagem seguinte) e o
    --    PARAR exato sem opt-out gravado: a transcrição do áudio só faz UPDATE do body, que o gatilho AFTER
    --    INSERT da F0b não vê, ou o gatilho falhou. Sem o opt-out a confirmação mentiria e o pedido se perderia:
    --    vai a "Para conferir", sem resposta, e o dono decide.
    v_motivo := 'parar_largo';
  elsif v_canal = 'opt_out' or v_opt_out then
    v_motivo := 'opt_out';
  elsif v_canal is not null then
    -- A lista de spam (ou um opt-out gravado só depois de agora, no replay): na dúvida, nada.
    v_motivo := 'bloqueado';
  elsif exists (select 1 from public.whatsapp_leads l
                 where l.lead_tipo = 'pessoal'
                   and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave) then
    v_motivo := 'pessoal';
  elsif v_ab.papel = 'fornecedor' then
    v_motivo := 'fornecedor';
  elsif v_ab.papel = 'contato_conhecido' then
    v_motivo := 'contato_conhecido';
  elsif v_ab.papel = 'cliente_parceiro' then
    v_motivo := 'parceiro_f4';
  elsif v_ab.papel = 'numero_novo' and v_tem_vendedor then
    -- Cliente cadastrado nunca é vendedor (palavras.ts): a regra só vale ao número novo.
    v_motivo := 'vendedor';
  elsif v_n_pede > 0 and v_n_pede_livre = 0 then
    v_motivo := 'agenda_consumiu';
  elsif v_n_pede = 0 and v_tem_robo then
    v_motivo := 'robo';
  elsif v_n_pede = 0 then
    v_motivo := 'nao_pede_resposta';
  else
    -- 12. A promessa do dono (promessa.ts), só a criada até agora e ainda por vencer.
    select min(w.lembrar_em) into v_prometido
      from public.whatsapp_acompanhamentos w
     where w.modo = 'promessa'
       and w.status = 'ativo'
       and public._agenda_chave_telefone(w.phone_normalized) = v_ab.chave
       and w.created_at <= v_agora
       and w.lembrar_em > v_agora;
    if v_prometido is not null then
      v_motivo := 'promessa_do_dono';
    elsif v_ab.papel = 'numero_novo' then
      -- 13. O pedido de serviço nas 24 h do NÚMERO (B.2): a janela começa na hora real da 1ª recebida da chave
      --     nas 24 h antes de agora (um caso fechado por silêncio não apaga o "motorhome" dito de manhã).
      select min(public._retorno_hora_real(w)) into v_desde
        from public.whatsapp_messages w
       where public._agenda_chave_telefone(w.phone_normalized) = v_ab.chave
         and w.direction = 'inbound'
         and w.occurred_at <= v_agora
         and w.occurred_at >= v_agora - interval '24 hours'
         and public._retorno_hora_real(w) >= v_agora - interval '24 hours';
      if v_desde is not null then
        v_pd := public._retorno_pedido_de_servico(v_ab.chave, v_desde, v_agora, v_lead_nome);
      end if;
      -- O pedido achado antes não se perde quando a janela passa (o caso não regride depois do recibo).
      v_pedido := coalesce((v_pd ->> 'pedido')::boolean, false)
                  or v_ab.tipo_recibo is not distinct from 'recibo_numero_novo'
                  or exists (select 1 from public.retorno_saidas s
                              where s.abertura_id = v_ab.id and s.tipo = 'recibo_numero_novo');
      if v_pedido then
        v_tipo := 'recibo_numero_novo';
      elsif v_n_pede_saudacao = v_n_pede then
        v_tipo := 'saudacao_numero_novo';
      else
        v_motivo := 'numero_novo_sem_pedido';
      end if;
    elsif v_ab.papel = 'cliente_ambiguo' then
      v_tipo := 'recibo_ambiguo';
    else
      v_tipo := 'recibo_cliente';
    end if;
  end if;

  if v_motivo is not null then
    v_nivel := 'nada';
    v_tipo := null;
  else
    v_nivel := 'recibo';
    -- Passagem imediata (B.4: recibo + acorde).
    v_passagem := v_risco
                  or coalesce((v_sinais ->> 'reclamacao')::boolean, false)
                  or coalesce((v_sinais ->> 'quer_dono')::boolean, false)
                  or coalesce((v_sinais ->> 'lgpd')::boolean, false)
                  or v_insistencias >= 2;
    if v_vencido then
      -- Vencido desde o fim do dia (ou o prazo final; na promessa do dono, o prometido_ate dela); a mensagem nova
      -- que pede resposta vira passagem (R1-07).
      v_vencida_desde := coalesce(least(v_ab.fim_do_dia_em, coalesce(v_ab.segundo_prazo, v_ab.prometido_ate)),
                                  v_ab.recibo_em, v_ab.aberta_em);
      v_passagem := v_passagem
                    or exists (select 1 from public.retorno_mensagens rm
                                where rm.abertura_id = v_ab.id and rm.pede_resposta
                                  and rm.gravada_em > v_vencida_desde and rm.gravada_em <= v_agora);
    end if;
    if v_passagem then
      v_nivel := 'passagem';
    end if;
  end if;

  v_intencao := case
    when v_motivo in ('parar', 'parar_largo') then 'parar'
    when v_risco then 'risco'
    when coalesce((v_sinais ->> 'lgpd')::boolean, false) then 'lgpd'
    when coalesce((v_sinais ->> 'reclamacao')::boolean, false) then 'reclamacao'
    when coalesce((v_sinais ->> 'quer_dono')::boolean, false) then 'quer_dono'
    when coalesce((v_sinais ->> 'pressa')::boolean, false) or coalesce((v_sinais ->> 'urgente')::boolean, false) then 'pressa'
    when v_pedido or (v_ab.papel <> 'numero_novo' and coalesce((v_sinais ->> 'servico')::boolean, false)) then 'pedido_servico'
    when v_n_pede > 0 and v_n_pede_saudacao = v_n_pede then 'saudacao'
    else 'outro'
  end;

  update public.retorno_aberturas ab
     set nivel = v_nivel,
         motivo = v_motivo,
         tipo_recibo = v_tipo,
         sinais = v_sinais,
         intencao = v_intencao,
         insistencias = least(v_insistencias, 32767),
         passagem_em = case when v_nivel = 'passagem' then coalesce(ab.passagem_em, v_agora) else ab.passagem_em end,
         -- a promessa do dono vira o relógio; a que saiu ANTES do prazo (encerrada ou cancelada, com prometido_ate
         -- ainda por vir) num caso aberto e sem recibo sai do relógio, e o recibo assume. A que VENCEU fica: o caso
         -- está vencido (passagem, nunca recibo novo) e o vigia o marca por ela. No caso vencido também fica, para
         -- a história do que foi prometido.
         prometido_ate = case when v_motivo = 'promessa_do_dono' then v_prometido
                              when ab.prometido_fonte = 'dono' and ab.recibo_em is null and ab.estado = 'aberta'
                                   and ab.prometido_ate > v_agora then null
                              else ab.prometido_ate end,
         prometido_fonte = case when v_motivo = 'promessa_do_dono' then 'dono'
                                when ab.prometido_fonte = 'dono' and ab.recibo_em is null and ab.estado = 'aberta'
                                     and ab.prometido_ate > v_agora then null
                                else ab.prometido_fonte end,
         faixa = case when v_motivo = 'promessa_do_dono' then 'promessa_dono'
                      when ab.prometido_fonte = 'dono' and ab.recibo_em is null and ab.estado = 'aberta'
                           and ab.prometido_ate > v_agora then null
                      else ab.faixa end,
         atualizada_em = now()
   where ab.id = v_ab.id
   returning * into v_ab;

  -- ── As saídas ──
  select * into v_recibo from public.retorno_saidas s where s.dedupe_key = 'retorno:' || v_ab.id || ':recibo';
  select * into v_saudacao from public.retorno_saidas s where s.dedupe_key = 'retorno:' || v_ab.id || ':saudacao';

  if v_nivel = 'nada' then
    -- O caso que vira 'nada' cancela as agendadas (recibo, saudação, coleta, urgente, cadastro e avisos), menos
    -- a confirmação do PARAR e o acorde. A saída que o retorno_pegar está processando é pulada: ele mesmo a
    -- cancela pelo _retorno_checar_antes.
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'nivel_nada', decidida_em = v_agora, atualizada_em = now()
     where s.id in (select x.id from public.retorno_saidas x
                     where x.abertura_id = v_ab.id and x.estado = 'agendada' and x.tipo not in ('parar', 'acorde')
                     for update skip locked);

    -- A confirmação do PARAR (T27/T28): uma, só a quem pode ouvir resposta, nunca a vendedor nem a robô (C12).
    -- O motivo 'parar' já exige o opt-out gravado (regra 2): sem ele, a confirmação nunca nasce.
    if v_motivo = 'parar' and v_ab.papel in ('cliente', 'cliente_ambiguo', 'numero_novo')
       and not v_tem_vendedor and not v_tem_robo then
      insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                         estado, enviar_em, dados, dedupe_key)
      values (v_ab.id, 'parar', 'retorno_recibo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized,
              v_ab.client_id, v_ab.modo, 'agendada', v_ult.gravada_em + make_interval(mins => v_cfg.carencia_min),
              jsonb_build_object('mensagem', v_ult.whatsapp_message_id), 'retorno:' || v_ab.id || ':parar')
      on conflict (dedupe_key) do nothing;
    end if;
  else
    -- A carência adaptativa (B.8): o dono ativo (saída humana a qualquer número nos últimos 15 min, só as
    -- gravadas até agora) ganha mais tempo para responder antes do recibo.
    v_dono_ativo := exists (select 1 from public.whatsapp_messages o
                             where o.direction = 'outbound'
                               and o.occurred_at <= v_agora
                               and o.occurred_at > v_agora - make_interval(mins => v_cfg.dono_ativo_janela_min)
                               and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by)));
    v_carencia := make_interval(mins => case when v_dono_ativo then v_cfg.carencia_dono_ativo_min
                                             else v_cfg.carencia_min end);

    if v_tipo = any (c_recibos) then
      -- O pedido apareceu depois da saudação: a saudação ainda agendada é substituída pelo recibo.
      if v_saudacao.estado = 'agendada' then
        update public.retorno_saidas s
           set estado = 'cancelada', motivo = 'substituida', decidida_em = v_agora, atualizada_em = now()
         where s.id in (select x.id from public.retorno_saidas x
                         where x.id = v_saudacao.id and x.estado = 'agendada'
                         for update skip locked);
      end if;
      -- Caso vencido não ganha recibo novo (só o acorde da passagem), nem o da promessa do dono que passou.
      if not v_vencido then
        v_enviar := v_ab.ultima_gravada_em + v_carencia;
        if v_ab.papel = 'numero_novo' and v_tem_audio then
          -- Número novo que só mandou áudio espera a transcrição; o cliente identificado não (R1-29).
          v_enviar := v_ab.ultima_gravada_em + greatest(v_carencia, make_interval(mins => v_cfg.audio_espera_min));
        end if;
        insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                           estado, enviar_em, dados, dedupe_key)
        values (v_ab.id, v_tipo, 'retorno_recibo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized,
                v_ab.client_id, v_ab.modo, 'agendada', v_enviar,
                jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'risco', v_risco,
                                   'apos_saudacao', coalesce(v_saudacao.estado = any (c_decididas), false)),
                'retorno:' || v_ab.id || ':recibo')
        on conflict (dedupe_key) do nothing;
        -- A rajada: mensagem nova com o recibo ainda agendado empurra o envio (nunca adianta); o risco que
        -- apareceu depois (inclusive pela transcrição) entra nos dados (o P6 põe a linha L01).
        update public.retorno_saidas s
           set enviar_em = case when s.dados ->> 'ultima_msg_id' is distinct from v_ab.ultima_msg_id::text
                                then greatest(s.enviar_em, v_enviar) else s.enviar_em end,
               dados = s.dados || jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'risco', v_risco),
               atualizada_em = now()
         where s.id in (select x.id from public.retorno_saidas x
                         where x.dedupe_key = 'retorno:' || v_ab.id || ':recibo'
                           and x.estado = 'agendada'
                           and (x.dados ->> 'ultima_msg_id' is distinct from v_ab.ultima_msg_id::text
                                or x.dados -> 'risco' is distinct from to_jsonb(v_risco))
                         for update skip locked);
      end if;
    elsif v_tipo = 'saudacao_numero_novo' and not v_vencido then
      v_enviar := v_ab.ultima_gravada_em + make_interval(mins => v_cfg.saudacao_espera_min);
      insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                         estado, enviar_em, dados, dedupe_key)
      values (v_ab.id, 'saudacao_numero_novo', 'retorno_recibo', 'resposta_imediata', v_ab.chave,
              v_ab.phone_normalized, v_ab.client_id, v_ab.modo, 'agendada', v_enviar,
              jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id), 'retorno:' || v_ab.id || ':saudacao')
      on conflict (dedupe_key) do nothing;
      update public.retorno_saidas s
         set enviar_em = greatest(s.enviar_em, v_enviar),
             dados = s.dados || jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id),
             atualizada_em = now()
       where s.id in (select x.id from public.retorno_saidas x
                       where x.dedupe_key = 'retorno:' || v_ab.id || ':saudacao'
                         and x.estado = 'agendada'
                         and x.dados ->> 'ultima_msg_id' is distinct from v_ab.ultima_msg_id::text
                       for update skip locked);
    end if;

    -- URGENTE depois do recibo decidido (sombra, enviada ou incerta): "Anotado como urgente" (T25/T26); o P6
    -- grava o topo_dia ao compor.
    if v_recibo.estado = any (c_decididas) and v_recibo.decidida_em <= v_agora then
      select rm.whatsapp_message_id as msg, rm.gravada_em into r
        from public.retorno_mensagens rm
       where rm.abertura_id = v_ab.id
         and coalesce((rm.sinais ->> 'urgente')::boolean, false)
         and rm.recebida_em > v_recibo.decidida_em
         and rm.gravada_em <= v_agora
       order by rm.recebida_em, rm.whatsapp_message_id
       limit 1;
      if found then
        insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized,
                                           client_id, modo, estado, enviar_em, dados, dedupe_key)
        values (v_ab.id, 'urgente',
                case when v_ab.papel = 'cliente' and public._retorno_nome(v_ab.client_id) is not null
                     then 'sem_acorde' else 'sem_acorde_sem_nome' end,
                'retorno_recibo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized, v_ab.client_id, v_ab.modo,
                'agendada', r.gravada_em + make_interval(mins => v_cfg.carencia_min),
                jsonb_build_object('mensagem', r.msg), 'retorno:' || v_ab.id || ':urgente')
        on conflict (dedupe_key) do nothing;
      end if;
    end if;

    -- A 2ª mensagem da coleta (C1, R1-23): número novo, recibo com pergunta já decidido, menos de coleta_max
    -- mensagens, e uma resposta que PEDE resposta depois dele ("ok", figurinha e robô não são resposta).
    if v_ab.papel = 'numero_novo' and v_recibo.estado = any (c_decididas) and v_recibo.decidida_em <= v_agora
       and coalesce(v_recibo.variante, '') like 'pergunta%' and v_ab.coleta_n < v_cfg.coleta_max then
      select rm.whatsapp_message_id as msg, rm.gravada_em into r
        from public.retorno_mensagens rm
       where rm.abertura_id = v_ab.id
         and rm.pede_resposta
         and rm.recebida_em > v_recibo.decidida_em
         and rm.gravada_em > v_recibo.decidida_em
         and rm.gravada_em <= v_agora
       order by rm.recebida_em, rm.whatsapp_message_id
       limit 1;
      if found then
        insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized,
                                           client_id, modo, estado, enviar_em, dados, dedupe_key)
        values (v_ab.id, 'coleta_numero_novo', 'nome', 'retorno_coleta', 'resposta_imediata', v_ab.chave,
                v_ab.phone_normalized, v_ab.client_id, v_ab.modo, 'agendada',
                r.gravada_em + make_interval(mins => v_cfg.carencia_min),
                jsonb_build_object('mensagem', r.msg), 'retorno:' || v_ab.id || ':coleta')
        on conflict (dedupe_key) do nothing;
      end if;
    end if;

    -- O nome dito: só depois da coleta ENVIADA (a pessoa ouviu "Como posso te chamar?"). Na sombra a coleta
    -- nunca é enviada: o nome fica nulo e o cadastro nunca é tentado (R-7).
    v_nome := v_ab.coleta ->> 'nome';
    if v_ab.papel = 'numero_novo' and v_nome is null then
      select * into v_coleta_saida from public.retorno_saidas s where s.dedupe_key = 'retorno:' || v_ab.id || ':coleta';
      if v_coleta_saida.estado = 'enviada' and v_coleta_saida.enviada_em <= v_agora then
        select public._retorno_nome_dito(w.body) into v_nome
          from public.retorno_mensagens rm
          join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
         where rm.abertura_id = v_ab.id
           and rm.pede_resposta
           and rm.recebida_em > v_coleta_saida.enviada_em
           and rm.gravada_em <= v_agora
           and w.occurred_at <= v_agora
           and public._retorno_nome_dito(w.body) is not null
         order by rm.recebida_em, rm.whatsapp_message_id
         limit 1;
        if v_nome is not null then
          insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, client_id, modo, estado,
                                             enviar_em, dados, dedupe_key)
          values (v_ab.id, 'cadastro_provisorio', v_ab.chave, v_ab.phone_normalized, v_ab.client_id, v_ab.modo,
                  'agendada', v_agora, '{}'::jsonb, 'retorno:' || v_ab.id || ':cadastro')
          on conflict (dedupe_key) do nothing;
        end if;
      end if;
    end if;

    -- A coleta (C1): o que o número novo escreveu, literal, no formato de dados_site (lead-do-site.ts), em
    -- retorno_aberturas.coleta e em whatsapp_leads.coleta. Sem inferência: o tipo é o rótulo da palavra dita
    -- (os modelos não viram tipo); o modelo é "modelo ano" literal; o serviço, as palavras achadas.
    if v_ab.papel = 'numero_novo' and v_tipo = 'recibo_numero_novo' and coalesce((v_pd ->> 'pedido')::boolean, false) then
      select string_agg(p.palavra, ', ' order by p.primeira) into v_servicos
        from (select x.palavra, min(x.ordem) as primeira
                from (select mt.m[1] as palavra, w.ord * 1000 + mt.n as ordem
                        from jsonb_array_elements_text(v_pd -> 'msgs') with ordinality as w(id, ord)
                        join public.whatsapp_messages wm on wm.id = w.id::uuid
                        cross join lateral regexp_matches(public._retorno_busca(wm.body), c_re_servico, 'g')
                             with ordinality as mt(m, n)) x
               group by x.palavra) p;
      v_tipo_bem := case v_pd ->> 'bem_palavra'
        when 'lancha' then 'Lancha' when 'veleiro' then 'Veleiro' when 'catamara' then 'Catamarã'
        when 'jet ski' then 'Moto aquática' when 'moto aquatica' then 'Moto aquática'
        when 'barco' then 'Barco' when 'embarcacao' then 'Embarcação' when 'escuna' then 'Escuna'
        when 'traineira' then 'Traineira' when 'bote' then 'Bote'
        when 'motorhome' then 'Motorhome' when 'trailer' then 'Trailer' when 'camper' then 'Camper'
        when 'van' then 'Van' when 'onibus' then 'Ônibus' when 'caminhao' then 'Caminhão' when 'picape' then 'Picape'
        when 'automovel' then 'Automóvel' when 'carro' then 'Automóvel' when 'veiculo' then 'Veículo'
        else null   -- ducato, sprinter, iveco, daily, master, boxer: modelo, não tipo
      end;
      v_modelo := nullif(btrim(concat_ws(' ', v_pd ->> 'modelo', v_pd ->> 'ano')), '');
      v_coleta := jsonb_build_object('nome', v_nome, 'tipo', v_tipo_bem, 'modelo', v_modelo, 'local', null::text,
                                     'servico', v_servicos, 'detalhes', v_pd ->> 'pedido_literal', 'fonte', 'retorno',
                                     'ano', v_pd ->> 'ano', 'atualizado_em', v_agora);
    elsif v_nome is not null and v_ab.coleta ->> 'nome' is null then
      -- O nome chegou depois que a janela de 24 h do pedido passou: só o nome entra.
      v_coleta := coalesce(v_ab.coleta, jsonb_build_object('tipo', null::text, 'modelo', null::text, 'local', null::text,
                                                           'servico', null::text, 'detalhes', null::text,
                                                           'fonte', 'retorno', 'ano', null::text))
                  || jsonb_build_object('nome', v_nome, 'atualizado_em', v_agora);
    end if;
    if v_coleta is not null then
      update public.retorno_aberturas ab
         set coleta = v_coleta, atualizada_em = now()
       where ab.id = v_ab.id
         and (ab.coleta - 'atualizado_em') is distinct from (v_coleta - 'atualizado_em');
      update public.whatsapp_leads l
         set coleta = v_coleta
       where l.id = v_ab.lead_id
         and (l.coleta - 'atualizado_em') is distinct from (v_coleta - 'atualizado_em');
    end if;

    -- A passagem: um acorde por mensagem que a causou (risco, LGPD, reclamação, "quero falar com o Gustavo",
    -- a que pede num caso vencido, ou a 2ª insistência em diante, pela conta recalculada acima: a mensagem
    -- que só chegou depois, sem ser insistência, não ganha acorde). Se a agenda já levou essa mensagem ao
    -- dono, ela já o acordou (R1-09): o acorde nasce cancelado. O acorde é decidido no SQL pelo vigia (P6).
    if v_nivel = 'passagem' then
      for r in
        select rm.whatsapp_message_id as msg, rm.agenda_ao_dono as ao_dono,
               case when coalesce((rm.sinais ->> 'risco')::boolean, false) then 'risco'
                    when coalesce((rm.sinais ->> 'lgpd')::boolean, false) then 'lgpd'
                    when coalesce((rm.sinais ->> 'reclamacao')::boolean, false) then 'reclamacao'
                    when coalesce((rm.sinais ->> 'quer_dono')::boolean, false) then 'quer_dono'
                    when v_vencido and rm.pede_resposta and rm.gravada_em > v_vencida_desde then 'vencida'
                    else 'insistencia'
               end as por
          from public.retorno_mensagens rm
         where rm.abertura_id = v_ab.id
           and rm.gravada_em <= v_agora
           and coalesce(rm.pede_motivo, '') <> all (c_fora_da_conversa)
           and (coalesce((rm.sinais ->> 'risco')::boolean, false)
                or coalesce((rm.sinais ->> 'lgpd')::boolean, false)
                or coalesce((rm.sinais ->> 'reclamacao')::boolean, false)
                or coalesce((rm.sinais ->> 'quer_dono')::boolean, false)
                or (v_vencido and rm.pede_resposta and rm.gravada_em > v_vencida_desde)
                or rm.whatsapp_message_id = any (v_insiste_acorde))
         order by rm.recebida_em, rm.whatsapp_message_id
      loop
        insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo,
                                           estado, motivo, enviar_em, decidida_em, dados, dedupe_key)
        values (v_ab.id, 'acorde', 'passagem', v_ab.chave, v_ab.phone_normalized, v_ab.client_id, v_ab.modo,
                case when r.ao_dono then 'cancelada' else 'agendada' end,
                case when r.ao_dono then 'agenda_ja_acordou' end,
                v_agora, case when r.ao_dono then v_agora end,
                jsonb_build_object('mensagem', r.msg, 'por', r.por),
                'retorno:' || v_ab.id || ':acorde:' || r.msg)
        on conflict (dedupe_key) do nothing;
      end loop;
    end if;
  end if;

  select s.id into v_saida_id from public.retorno_saidas s
   where s.dedupe_key in ('retorno:' || v_ab.id || ':recibo', 'retorno:' || v_ab.id || ':saudacao')
   order by (s.dedupe_key like '%:recibo') desc limit 1;

  return jsonb_build_object('abertura_id', v_ab.id, 'papel', v_ab.papel, 'nivel', v_nivel, 'motivo', v_motivo,
                            'tipo_recibo', v_tipo, 'estado', v_ab.estado, 'modo', v_ab.modo, 'saida_id', v_saida_id);
end;
$$;

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

  -- F4 (P2): o caso do parceiro mostra a sigla e a pessoa ("comercial" no número compartilhado). Nunca o número: a sigla só
  -- tem letras (check) e o nome da pessoa sai sem dígito.
  if v_ab.papel = 'parceiro' then
    select format('%s (%s)', pa.sigla,
                  coalesce(nullif(btrim(left(regexp_replace(coalesce(pe.nome, ''), '[0-9]+', '', 'g'), 40)), ''), 'comercial'))
      into v_nome
      from public.parceiros pa
      left join public.parceiro_pessoas pe on pe.id = nullif(v_ab.quem ->> 'pessoa_id', '')::uuid
     where pa.id = nullif(v_ab.quem ->> 'parceiro_id', '')::uuid;
    return coalesce(v_nome, 'parceiro');
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
