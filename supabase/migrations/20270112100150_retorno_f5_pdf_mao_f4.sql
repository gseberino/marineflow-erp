-- Retorno rápido ao cliente, F5 (P15): o conserto do PDF à mão da F4 — o "orç-" (com cedilha) no nome do arquivo. Nada liga
-- aqui.
-- Gerada por script (scripts/gerar_f5.cjs pdf_mao): parceiro_detectar_pdf vem do corpo vigente (o do banco, achado pelo md5
-- do prosrc entre as migrations do worktree; hoje o de 20270105100800_retorno_f4_mao.sql), e só os trechos marcados -- F5 são
-- novos (T-PDF-1 a T-PDF-3).
--
-- O regex da F4, (orc|os)-([0-9]{3,8}) sobre lower(fileName), não casa "orç-": 12 dos 28 PDFs de orçamento que saíram do
-- aparelho em 180 dias têm ORÇ- no nome (o "Baixar" da tela e o PDF do assistente). Com o PDF à mão da F4 ligado, esses envios
-- ficariam "sem número" e o vínculo com a parceira não seria perguntado. Agora (or[cç]|os): "orç-" é o mesmo documento que
-- "orc-", a ordem achada é a ORÇ-nnnnn, e o número gravado fica ORC-nnnnn, como antes (o CHECK de numero_doc não muda). Nada
-- mais muda: marca d'água, destino, situações e modos são os da F4.
--
-- Sem dado. Hoje pdf_mao_modo = 'desligado' e parceiro_envios_a_mao tem 0 linhas: o buraco não fez estrago.
-- Reverter: reaplicar a definição de parceiro_detectar_pdf de 20270105100800_retorno_f4_mao.sql (e o comment dela).

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
    v_casou := regexp_match(lower(coalesce(m.arquivo, '')), '(?:^|[^a-z0-9])(or[cç]|os)-([0-9]{3,8})(?:[^0-9]|$)');
    if v_casou is null then
      v_fora := v_fora + 1;
      continue;
    end if;
    -- F5 (P15): "orç-" (com cedilha) é o mesmo documento que "orc-"; o número gravado fica ORC-nnnnn, como antes.
    v_doc := (case when v_casou[1] = 'os' then 'OS' else 'ORC' end) || '-' || v_casou[2];
    -- ORC- do arquivo é ORÇ- no banco (slugifyForFilename tira a cedilha); OS- fica como veio. A OS é deste documento,
    -- nunca a da volta anterior.
    v_os := null;
    select so.id into v_os
      from public.service_orders so
     where so.service_order_number = (case when v_casou[1] in ('orc', 'orç') then 'ORÇ-' else 'OS-' end) || v_casou[2]
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
  'Retorno F4 (P9.1) e F5 (P15): a detecção do PDF à mão, pela marca parceiro_pdf_ate. Saídas de documento do aparelho (raw_payload ? data, sem via) a número confirmado de parceiro, cujo nome casa ORC-, ORÇ- ou OS- com 3 a 8 dígitos: grava só o número (ORC-nnnnn ou OS-nnnnn; registrada, so_registro, perguntada com item pdf_mao, ou ignorada sem OS). pdf_mao_modo desligado (ou a 1ª vez): só avança a marca. Nunca lê o corpo.';

revoke all on function public.parceiro_detectar_pdf(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_detectar_pdf(timestamptz) to service_role;
