-- Retorno rápido ao cliente, F4 (P9): o PDF mandado à mão ao parceiro e o repassar a cliente sem WhatsApp. Nada liga aqui.
--
-- 1. parceiro_envios_a_mao: o documento que o dono mandou do aparelho a um número confirmado de parceiro, com só o número
--    do documento (ORC-nnnnn ou OS-nnnnn), nunca o nome do arquivo (que leva o nome do cliente).
-- 2. parceiro_detectar_pdf (sem LLM, sem abrir mensagem): marca d'água retorno_config.parceiro_pdf_ate. Lê só id,
--    occurred_at, phone_normalized e o fileName do raw_payload das saídas de documento que são eco do aparelho
--    (raw_payload ? 'data' e sem 'via'; o envio do sistema traz 'via'). Com pdf_mao_modo 'desligado' (o padrão), só avança
--    a marca: ao ligar, nada do passado vira pergunta. 'registrar': registrada (contratante ou pagador) ou so_registro.
--    'perguntar': registrada ou perguntada, com o item pdf_mao na fila. Nunca promete pegar todo PDF: só o nome com
--    ORC- ou OS- casa.
-- 3. parceiro_decidir_pdf_mao (só o dono): A contrata, B paga (base decisao_do_dono, por parceiro_requalificar; sem vínculo,
--    propõe e confirma); C só indicou, e nada muda para o parceiro. O rascunho sem origem ganha a origem do parceiro, com
--    audit_log; o de outro parceiro recusa (outro_parceiro).
-- 4. parceiro_repassar_rodada: 1. propõe o repassar (item repassar na fila) da OS pronta (palavra do dono ou da equipe),
--    de cliente sem telefone, vínculo visível e nome sem colisão; 2. com o tipo ligado, recria uma vez a saída real do
--    repassar aprovado em sombra, sem novo sim, enquanto a OS segue visível e pronta.
--
-- Sem dado: a tabela nova (vazia) e funções novas. Reverter: update public.retorno_config set pdf_mao_modo = 'desligado';
-- drop function das funções desta migration. A tabela fica.

-- ── 1. A tabela do PDF à mão ────────────────────────────────────────────────────────────────────────────────────────────

create table public.parceiro_envios_a_mao (
  id uuid primary key default gen_random_uuid(),
  whatsapp_message_id uuid not null unique references public.whatsapp_messages(id) on delete cascade,
  parceiro_id uuid not null references public.parceiros(id) on delete cascade,
  service_order_id uuid references public.service_orders(id) on delete set null,
  numero_doc text not null check (numero_doc ~ '^(ORC|OS)-[0-9]{3,8}$'),   -- só o número; nunca o nome do arquivo
  enviado_em timestamptz not null,
  situacao text not null default 'nova' check (situacao in ('nova', 'registrada', 'so_registro', 'perguntada', 'decidida', 'ignorada')),
  decidido_em timestamptz
);
create index parceiro_envios_a_mao_por_parceiro on public.parceiro_envios_a_mao (parceiro_id, situacao);

comment on table public.parceiro_envios_a_mao is
  'Retorno F4 (P9): o PDF que o dono mandou à mão (eco do aparelho) a um número confirmado de parceiro. Só o número do documento (ORC-/OS-), nunca o nome do arquivo. situacao: registrada (contratante ou pagador), so_registro, perguntada (item pdf_mao), decidida, ignorada (OS não achada).';

alter table public.parceiro_envios_a_mao enable row level security;
drop policy if exists parceiro_envios_a_mao_leitura on public.parceiro_envios_a_mao;
create policy parceiro_envios_a_mao_leitura on public.parceiro_envios_a_mao
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
revoke all on table public.parceiro_envios_a_mao from public, anon, authenticated;
grant select on table public.parceiro_envios_a_mao to authenticated;
grant all on table public.parceiro_envios_a_mao to service_role;

-- ── 2. A detecção ───────────────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public.parceiro_detectar_pdf(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config;
  v_ate timestamptz;
  m record;
  v_num record;
  v_casou text[];
  v_doc text;
  v_os uuid;
  v_situacao text;
  v_id uuid;
  v_lidos integer := 0;
  v_gravados integer := 0;
  v_fora integer := 0;
begin
  select * into v_cfg from public.retorno_config c where c.id for update;
  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_config');
  end if;
  v_ate := v_cfg.parceiro_pdf_ate;

  -- Desligada, ou a 1ª vez: só avança a marca (nada do passado vira pergunta). A marca nunca volta.
  if v_cfg.pdf_mao_modo = 'desligado' or v_ate is null then
    update public.retorno_config c
       set parceiro_pdf_ate = greatest(coalesce(c.parceiro_pdf_ate, v_agora), v_agora)
     where c.id;
    return jsonb_build_object('ok', true, 'modo', v_cfg.pdf_mao_modo, 'lidos', 0, 'gravados', 0,
                              'ate', greatest(coalesce(v_ate, v_agora), v_agora));
  end if;

  for m in
    select w.id, w.occurred_at, w.phone_normalized, w.raw_payload #>> '{data,message,documentMessage,fileName}' as arquivo
      from public.whatsapp_messages w
     where w.direction = 'outbound'
       and w.message_type = 'document'
       and w.raw_payload ? 'data'
       and not (w.raw_payload ? 'via')
       and w.occurred_at > v_ate
       and w.occurred_at <= v_agora
     order by w.occurred_at, w.id
  loop
    v_lidos := v_lidos + 1;
    -- O destino: um número confirmado de parceiro (a chave e o DDD, como quem_escreve).
    select nn.id, pe.parceiro_id into v_num
      from public.parceiro_numeros nn
      join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
      join public.parceiros pa on pa.id = pe.parceiro_id and pa.ativo
     where nn.chave = public._agenda_chave_telefone(m.phone_normalized)
       and nn.situacao = 'confirmado'
       and (nn.ddd is null or public._ddd_do_telefone(m.phone_normalized) is null or nn.ddd = public._ddd_do_telefone(m.phone_normalized))
     order by nn.criado_em, nn.id
     limit 1;
    if not found then
      continue;
    end if;
    -- Só o número do documento; sem número no nome, fica de fora.
    v_casou := regexp_match(lower(coalesce(m.arquivo, '')), '(?:^|[^a-z0-9])(orc|os)-([0-9]{3,8})(?:[^0-9]|$)');
    if v_casou is null then
      v_fora := v_fora + 1;
      continue;
    end if;
    v_doc := upper(v_casou[1]) || '-' || v_casou[2];
    -- ORC- do arquivo é ORÇ- no banco (slugifyForFilename tira a cedilha); OS- fica como veio. A OS é deste documento,
    -- nunca a da volta anterior.
    v_os := null;
    select so.id into v_os
      from public.service_orders so
     where so.service_order_number = (case when v_casou[1] = 'orc' then 'ORÇ-' else 'OS-' end) || v_casou[2]
       and so.merged_into_id is null
     order by so.created_at desc, so.id
     limit 1;
    if v_os is null then
      v_situacao := 'ignorada';
    elsif exists (select 1 from public.os_interessados oi
                   where oi.service_order_id = v_os and oi.parceiro_id = v_num.parceiro_id
                     and oi.situacao = 'confirmado' and oi.papel in ('contratante', 'pagador')) then
      v_situacao := 'registrada';
    elsif v_cfg.pdf_mao_modo = 'registrar' then
      v_situacao := 'so_registro';
    else
      v_situacao := 'perguntada';
    end if;
    v_id := null;
    insert into public.parceiro_envios_a_mao (whatsapp_message_id, parceiro_id, service_order_id, numero_doc, enviado_em, situacao)
    values (m.id, v_num.parceiro_id, v_os, v_doc, m.occurred_at, v_situacao)
    on conflict (whatsapp_message_id) do nothing
    returning id into v_id;
    if v_id is not null then
      v_gravados := v_gravados + 1;
      if v_situacao = 'perguntada' then
        perform public._parceiro_fila_por('pdf_mao', v_num.parceiro_id, v_id, 'pdf_mao:' || v_id, null,
                                          jsonb_build_object('service_order_id', v_os, 'numero_doc', v_doc));
      end if;
    end if;
  end loop;

  update public.retorno_config c
     set parceiro_pdf_ate = greatest(coalesce(c.parceiro_pdf_ate, v_agora), v_agora)
   where c.id;
  return jsonb_build_object('ok', true, 'modo', v_cfg.pdf_mao_modo, 'lidos', v_lidos, 'gravados', v_gravados,
                            'sem_numero', v_fora, 'ate', greatest(v_ate, v_agora));
end;
$$;

comment on function public.parceiro_detectar_pdf(timestamptz) is
  'Retorno F4 (P9.1): a detecção do PDF à mão, pela marca parceiro_pdf_ate. Saídas de documento do aparelho (raw_payload ? data, sem via) a número confirmado de parceiro, cujo nome casa ORC-/OS- com 3 a 8 dígitos: grava só o número (registrada, so_registro, perguntada com item pdf_mao, ou ignorada sem OS). pdf_mao_modo desligado (ou a 1ª vez): só avança a marca. Nunca lê o corpo.';

revoke all on function public.parceiro_detectar_pdf(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_detectar_pdf(timestamptz) to service_role;

-- ── 3. A letra do dono ──────────────────────────────────────────────────────────────────────────────────────────────────

-- A: ela contrata; B: ela paga (o papel e base decisao_do_dono, por parceiro_requalificar, com a pessoa do número que
-- recebeu; sem vínculo, parceiro_propor com origem dono e _parceiro_confirmar com o papel dito, com o aviso de sempre).
-- C: só indicou: só o envio fica decidida; o vínculo e a base não mudam. Rascunho sem origem_parceiro_id: em A ou B ganha
-- a origem deste parceiro antes do vínculo, com audit_log; com a origem de outro parceiro, nada muda. O que já saiu não é
-- desfeito, e nada passa a mandar valor a quem só indicou.
create or replace function public.parceiro_decidir_pdf_mao(p_envio uuid, p_letra text, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_letra text := upper(btrim(coalesce(p_letra, '')));
  v_e public.parceiro_envios_a_mao;
  v_so record;
  v_papel text;
  v_pessoa uuid;
  v_oi public.os_interessados;
  v_r jsonb;
  v_id uuid;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_decidir_pdf_mao: só o dono';
  end if;
  if v_letra not in ('A', 'B', 'C') then
    raise exception using errcode = '22023', message = 'parceiro_decidir_pdf_mao: letra fora da lista';
  end if;
  select * into v_e from public.parceiro_envios_a_mao e where e.id = p_envio for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_envio');
  end if;
  if v_e.situacao = 'decidida' then
    return jsonb_build_object('ok', false, 'motivo', 'ja_decidida');
  end if;
  if v_e.situacao = 'ignorada' or v_e.service_order_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_os');
  end if;

  -- C: só o registro; nada muda para o parceiro.
  if v_letra = 'C' then
    update public.parceiro_envios_a_mao e set situacao = 'decidida', decidido_em = v_agora where e.id = v_e.id;
    return jsonb_build_object('ok', true, 'letra', 'C', 'mudou', false);
  end if;

  v_papel := case v_letra when 'A' then 'contratante' else 'pagador' end;
  -- A pessoa do número que recebeu o documento (só o telefone da mensagem; nunca o corpo).
  select nn.pessoa_id into v_pessoa
    from public.whatsapp_messages w
    join public.parceiro_numeros nn on nn.chave = public._agenda_chave_telefone(w.phone_normalized)
    join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.parceiro_id = v_e.parceiro_id
   where w.id = v_e.whatsapp_message_id
   order by (nn.situacao = 'confirmado') desc, nn.criado_em, nn.id
   limit 1;

  -- O rascunho: só passa na regra 8 com a origem deste parceiro. A letra do dono é o ato que a põe.
  select so.id, so.status, so.origem_parceiro_id, so.client_id into v_so
    from public.service_orders so where so.id = v_e.service_order_id for update;
  if v_so.status = 'draft' then
    if v_so.origem_parceiro_id is not null and v_so.origem_parceiro_id is distinct from v_e.parceiro_id then
      return jsonb_build_object('ok', false, 'motivo', 'outro_parceiro',
                                'frase', 'esse orçamento está ligado a outro parceiro; nada mudou');
    end if;
    if v_so.origem_parceiro_id is null then
      update public.service_orders so set origem_parceiro_id = v_e.parceiro_id where so.id = v_so.id;
      insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
      values ('service_orders', v_so.id, 'update', 'dono', jsonb_build_object('origem_parceiro_id', null),
              jsonb_build_object('origem_parceiro_id', v_e.parceiro_id),
              'Retorno F4: o dono disse, no PDF mandado à mão, que o parceiro está no orçamento');
    end if;
  end if;

  select * into v_oi
    from public.os_interessados oi
   where oi.service_order_id = v_e.service_order_id and oi.parceiro_id = v_e.parceiro_id and oi.papel is distinct from 'anfitria'
   for update;
  if found then
    if v_oi.situacao = 'proposto' then
      v_r := public._parceiro_confirmar(v_oi.id, p_autor, null, v_agora, v_papel, v_pessoa);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        return jsonb_build_object('ok', false, 'motivo', v_r ->> 'motivo');
      end if;
    elsif v_oi.situacao is distinct from 'confirmado' then
      return jsonb_build_object('ok', false, 'motivo', 'vinculo_' || v_oi.situacao);
    end if;
    v_id := v_oi.id;
  else
    v_r := public.parceiro_propor(jsonb_build_array(jsonb_build_object(
             'service_order_id', v_e.service_order_id, 'parceiro_id', v_e.parceiro_id, 'client_id', v_so.client_id,
             'origem', 'dono', 'papel', v_papel, 'pessoa_id', v_pessoa)), p_autor);
    v_id := nullif(v_r -> 'propostos' -> 0 ->> 'interessado_id', '')::uuid;
    if v_id is null then
      return jsonb_build_object('ok', false, 'motivo', coalesce(v_r -> 'recusados' -> 0 ->> 'motivo', 'nao_proposto'));
    end if;
    v_r := public._parceiro_confirmar(v_id, p_autor, null, v_agora, v_papel, v_pessoa);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'motivo', v_r ->> 'motivo');
    end if;
  end if;

  -- O papel dito, o pacote completo e a base decisao_do_dono, com audit_log.
  v_r := public.parceiro_requalificar(v_id, v_papel, p_autor, 'decisao_do_dono', v_agora, v_pessoa);
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'motivo', v_r ->> 'motivo');
  end if;
  update public.parceiro_envios_a_mao e set situacao = 'decidida', decidido_em = v_agora where e.id = v_e.id;
  return jsonb_build_object('ok', true, 'letra', v_letra, 'interessado_id', v_id, 'papel', v_r ->> 'papel', 'base', v_r ->> 'base');
end;
$$;

comment on function public.parceiro_decidir_pdf_mao(uuid, text, uuid, timestamptz) is
  'Retorno F4 (P9.1): letra do dono no item pdf_mao. Só o dono (42501). A contratante, B pagador: parceiro_requalificar com base decisao_do_dono e a pessoa do número que recebeu; sem vínculo, parceiro_propor (origem dono) e _parceiro_confirmar com o papel. Rascunho sem origem: grava origem_parceiro_id com audit_log; de outro parceiro: {ok: false, motivo: outro_parceiro}. C: só o envio fica decidida.';

revoke all on function public.parceiro_decidir_pdf_mao(uuid, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_decidir_pdf_mao(uuid, text, uuid, timestamptz) to service_role;

-- ── 4. O repassar ───────────────────────────────────────────────────────────────────────────────────────────────────────

-- 1. Propõe: OS visível com a palavra de pronto (fatos.pronto), cliente sem telefone, nome sem colisão (P4.2, item 5: o
--    repassar nem é proposto) e sem repassar ainda: o item repassar:<os>:<parceiro> na fila, válido até o pronto vencer.
--    Uma vez por OS e parceiro: o item que caiu não volta.
-- 2. O aprovado em sombra: com parceiro_repassar ligado, cada saída de repassar com chave de sombra, sem a real, com a OS
--    ainda visível, pronta e o cliente ainda sem telefone, ganha a saída real, uma vez, sem novo sim.
create or replace function public.parceiro_repassar_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  pa record;
  r record;
  s record;
  v_f jsonb;
  v_forma text;
  v_primeiro text;
  v_nomes jsonb;
  v_os uuid;
  v_int uuid;
  v_cl uuid;
  v_propostos integer := 0;
  v_reais integer := 0;
  v_erros integer := 0;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', true, 'rodou', false);
  end if;

  -- 1. Propõe.
  for pa in select p.id from public.parceiros p where p.ativo order by p.criado_em, p.id loop
    for r in select * from public.parceiro_os_visiveis(pa.id, v_agora) loop
      begin
        if public._parceiro_fone_do_cliente(r.client_id) is not null
           or exists (select 1 from public.parceiro_fila f where f.chave = 'repassar:' || r.service_order_id || ':' || pa.id)
           or exists (select 1 from public.retorno_saidas x
                       where x.emissor = 'parceiro' and x.tipo = 'parceiro_repassar'
                         and x.dados -> 'os_ids' ->> 0 = r.service_order_id::text
                         and x.dados ->> 'parceiro_id' = pa.id::text) then
          continue;
        end if;
        v_f := public._parceiro_fato_da_os(r.service_order_id, v_agora);
        if jsonb_typeof(v_f -> 'fatos' -> 'pronto') is distinct from 'object' then
          continue;
        end if;
        v_forma := public._parceiro_nome_curto(r.client_id);
        v_primeiro := public._agenda_nome_curto(v_forma);
        v_nomes := public._parceiro_nomes_do_contexto(pa.id, array[r.client_id], null);
        if v_forma is null
           or exists (select 1 from jsonb_array_elements_text(v_nomes -> 'nomes_de_outros') o
                       where public._texto_simples(btrim(o)) in (public._texto_simples(v_forma), public._texto_simples(v_primeiro))) then
          continue;
        end if;
        perform public._parceiro_fila_por('repassar', pa.id, r.service_order_id, 'repassar:' || r.service_order_id || ':' || pa.id,
                                          (v_f -> 'fatos' -> 'pronto' ->> 'em')::timestamptz + v_cfg.fato_pronto_idade,
                                          jsonb_build_object('interessado_id', r.interessado_id, 'service_order_id', r.service_order_id));
        v_propostos := v_propostos + 1;
      exception when others then
        v_erros := v_erros + 1;
        perform public._retorno_log('parceiro_repassar', 'parceiro_repassar_rodada (propor): ' || sqlerrm, 'error',
                                    jsonb_build_object('interessado', r.interessado_id, 'sqlstate', sqlstate));
      end;
    end loop;
  end loop;

  -- 2. O aprovado em sombra, com o tipo ligado.
  if v_cfg.parceiro_modo = 'ligado' and 'parceiro_repassar' = any (v_cfg.parceiro_tipos_ligados) then
    for s in
      select x.id, x.dados
        from public.retorno_saidas x
       where x.emissor = 'parceiro'
         and x.tipo = 'parceiro_repassar'
         and x.dedupe_key ~ '^parceiro:repassar:'
         and x.dedupe_key ~ ':sombra(:|$)'
       order by x.criada_em, x.id
    loop
      begin
        v_os := nullif(s.dados -> 'os_ids' ->> 0, '')::uuid;
        v_int := nullif(s.dados -> 'interessado_ids' ->> 0, '')::uuid;
        if v_os is null or v_int is null or coalesce(s.dados ->> 'numero_id', '') !~ '^[0-9a-f-]{36}$'
           or exists (select 1 from public.retorno_saidas y where y.dedupe_key = 'parceiro:repassar:' || v_os || ':pronto')
           or (public.parceiro_os_visivel(v_int, v_agora) ->> 'visivel')::boolean is not true then
          continue;
        end if;
        v_cl := null;
        select oi.client_id into v_cl from public.os_interessados oi where oi.id = v_int and oi.service_order_id = v_os;
        if v_cl is null or public._parceiro_fone_do_cliente(v_cl) is not null then
          continue;
        end if;
        v_f := public._parceiro_fato_da_os(v_os, v_agora);
        if jsonb_typeof(v_f -> 'fatos' -> 'pronto') is distinct from 'object'
           or ((v_f -> 'fatos' -> 'pronto' ->> 'em')::timestamptz + v_cfg.fato_pronto_idade <= v_agora) is not false then
          continue;
        end if;
        perform public.parceiro_agendar('parceiro_repassar', 'padrao', (s.dados ->> 'numero_id')::uuid, null,
                                        jsonb_strip_nulls(jsonb_build_object('os_ids', jsonb_build_array(v_os),
                                                                             'interessado_ids', jsonb_build_array(v_int),
                                                                             'service_order_id', v_os,
                                                                             'primeiro_nome', s.dados -> 'primeiro_nome',
                                                                             'de_sombra', s.id)),
                                        v_agora, 'parceiro:repassar:' || v_os || ':pronto', 'aviso');
        v_reais := v_reais + 1;
      exception when others then
        v_erros := v_erros + 1;
        perform public._retorno_log('parceiro_repassar', 'parceiro_repassar_rodada (sombra): ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', s.id, 'sqlstate', sqlstate));
      end;
    end loop;
  end if;

  return jsonb_build_object('ok', v_erros = 0, 'rodou', true, 'propostos', v_propostos, 'reais', v_reais, 'erros', v_erros);
end;
$$;

comment on function public.parceiro_repassar_rodada(timestamptz) is
  'Retorno F4 (P9.1): no vigia. 1. Propõe o item repassar (repassar:<os>:<parceiro>, até fatos.pronto.em + fato_pronto_idade) para OS visível pronta, de cliente sem telefone e nome sem colisão, uma vez. 2. Com parceiro_repassar ligado, recria uma vez a saída real (parceiro:repassar:<os>:pronto) do repassar aprovado em sombra, com a OS visível, pronta e o cliente ainda sem telefone.';

revoke all on function public.parceiro_repassar_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_repassar_rodada(timestamptz) to service_role;
