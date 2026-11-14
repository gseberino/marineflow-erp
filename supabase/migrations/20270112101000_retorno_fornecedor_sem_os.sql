-- Retorno rápido: o número de fornecedor ATIVO cujo cadastro de cliente não tem nenhuma OS não ganha recibo (13/11/2026).
-- Achado na conferência da sombra do recibo (11/11 a 13/11), antes de ligar: o ••0081 é fornecedor ativo e tem também um
-- cadastro de cliente sem OS; o quem_escreve devolve "cliente" (a precedência do cliente da F0b) e o recibo_cliente e o
-- fim_do_dia sairiam a um fornecedor. Em 13/11, 27 cadastros de cliente têm o telefone de um fornecedor ativo, todos sem OS.
-- A troca é só no passo 6 do retorno_abrir (o papel do caso): o quem_escreve, o webhook e a ficha do cliente não mudam.
-- Gerada por D:/IA-HBR/Trabalho/retorno-rapido/scripts/gerar_fornecedor_sem_os.cjs do corpo vigente em produção
-- (prosrc md5 e6107cc1f1f910155fb084c0baabf56c); create or replace mantém dono, ACL e comment.
-- Prova: supabase/tests/retorno_f1_abrir.sql, casos 2d2 (fornecedor ativo + cliente sem OS = fornecedor, sem saída) e
-- 2d3 (fornecedor ativo + cliente com OS = cliente, com recibo).
-- Reverter: reaplicar retorno_abrir de 20270105100100_retorno_f4_identificacao.sql.

CREATE OR REPLACE FUNCTION public.retorno_abrir(p_msg uuid, p_consumida boolean DEFAULT false, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        -- 13/11/2026 (fornecedor sem OS): número de fornecedor ATIVO cujo cadastro de cliente não tem nenhuma OS nem
        -- orçamento é o fornecedor (nada, sem recibo). Com OS, o cliente vence, como antes (precedência do cliente, F0b).
        when v_papel = 'cliente'
             and not exists (select 1 from public.service_orders o where o.client_id = (v_q ->> 'cliente_id')::uuid)
             and exists (select 1 from public.suppliers s where s.active and public._agenda_chave_telefone(s.phone) = v_chave)
          then 'fornecedor'
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
$function$
;
