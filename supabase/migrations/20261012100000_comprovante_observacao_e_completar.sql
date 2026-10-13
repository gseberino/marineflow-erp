-- Comprovantes (12/10/2026 — spec-observacao-atomica-prefixo.md, A e B): a observação do dono guardada no
-- CMP e a correção do assistente numa transação só.
--
-- A. comprovantes.observacao (uma linha, até 200): o porquê que a tool completar_comprovante já exigia
--    quando o valor muda (e que só ia à mensagem) passa a ser GUARDADO. O dono também a escreve
--    ("corrigir obs …", "observação: …"): comprovante_comando, corrigir campo 'obs' — sobe a versão do
--    resumo (a descrição do lançamento faz parte do que o sim aprova) e repete a mesma pergunta (o passo
--    não muda). Toda saída passa por _comprovante_obs_sem_cpf (a _comprovante_sem_cpf mais o CPF colado em
--    pontuação, comum no texto livre): o resumo (_comprovante_resumo), a consulta do
--    assistente (comprovantes_consultar), os dois _INDICE do mês (comprovantes_indice_do_mes e
--    comprovantes_indice_pessoal_do_mes) e a descrição do lançamento, que agora nasce num lugar só
--    (_comprovante_descricao, usada por _comprovante_gravar e _comprovante_linha_explicar). Sem
--    observação, a descrição é byte a byte a de antes. A observação fica FORA da descrição do reembolso
--    do técnico nas Diárias (vai ao extrato e ao recibo dele; a observação é do dono).
--
-- B. comprovante_completar(jsonb): a ação completar da edge comprovantes-whatsapp chamava
--    comprovante_comando/comprovante_responder campo a campo, cada RPC uma transação — uma recusa no meio
--    deixava o CMP com metade aplicada. Agora a edge chama UMA RPC: as recusas antes de escrever e, num
--    bloco que desfaz TUDO na primeira recusa (SQLSTATE MFC02), as MESMAS comprovante_comando (categoria,
--    os, para, valor, data, forma, obs) e comprovante_responder (quem pagou, técnico, peça ou despesa,
--    como pagou, qual OS; message_id nulo; nunca o confirmar nem o mesma_compra). A trava do telefone e a
--    linha do CMP são tiradas do lado de FORA do bloco. Nada grava financeiro: só o sim do dono grava.
--
-- As cópias de corpo são as do arquivo indicado no comentário de cada uma, IGUAIS, mais só o que ele diz.
-- Não escreve dados (a coluna nasce nula; sem preenchimento retroativo). Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. A coluna
-- ---------------------------------------------------------------------------------------------
alter table public.comprovantes
  add column if not exists observacao text
    constraint comprovantes_observacao_curta check (observacao is null or char_length(observacao) between 1 and 200);

comment on column public.comprovantes.observacao is
  'A (12/10/2026): o porquê/o que o dono disse do comprovante (uma linha, até 200). Vai ao resumo, ao índice do mês e à descrição do lançamento sempre sem CPF (_comprovante_obs_sem_cpf).';

-- ---------------------------------------------------------------------------------------------
-- 2a. A observação sem CPF (revisão de 12/10/2026). _comprovante_sem_cpf foi feita para o nome do
--     fornecedor e só tira o CPF cercado de espaços; na observação, que é texto livre, o CPF costuma vir
--     colado em pontuação ("CPF 123.456.789-09.", "CPF:12345678909", "(123.456.789-09)") e passava
--     inteiro. Aqui o CPF sai onde quer que esteja (11 dígitos, com ou sem pontuação, sem outro dígito
--     encostado: CNPJ e números maiores ficam) e o resto é a _comprovante_sem_cpf de sempre. Nula = nula.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_obs_sem_cpf(p text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select public._comprovante_sem_cpf(
    regexp_replace(coalesce(p, ''), '(?<![0-9])[0-9]{3}\.?[0-9]{3}\.?[0-9]{3}-?[0-9]{2}(?![0-9])', ' ', 'g'));
$$;

comment on function public._comprovante_obs_sem_cpf(text) is
  'A observação do dono como sai do banco (resumo, consulta, índices, descrição do lançamento): sem CPF, mesmo colado em pontuação.';

-- ---------------------------------------------------------------------------------------------
-- 2b. A descrição do lançamento, num lugar só (era a mesma expressão em _comprovante_gravar e em
--     _comprovante_linha_explicar). Sem observação, byte a byte a de antes; com ela, " · Obs: …" no fim,
--     sem CPF. Cortada em 200 no total, como antes.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_descricao(c public.comprovantes)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select left(c.codigo || ' · ' || public._comprovante_tipo_no_texto(c.tipo)
              || coalesce(' · ' || (public._comprovante_fornecedor(c)->>'nome'), '')
              || coalesce(' · Obs: ' || public._comprovante_obs_sem_cpf(c.observacao), ''), 200);
$$;

comment on function public._comprovante_descricao(public.comprovantes) is
  'A descrição do lançamento do CMP ("CMP-00001 · cupom fiscal · POSTO X · Obs: …"): a da despesa da OS, da anotação, do Caixa e da linha ligada. A observação sai sem CPF.';

-- ---------------------------------------------------------------------------------------------
-- 3. comprovante_comando: o corrigir aceita o campo "obs" (a observação do dono)
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011202000:1912-2262 IGUAL + o 'obs' na lista do corrigir + o ramo 'obs' antes do end case
create or replace function public.comprovante_comando(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_cmd text;
  v_dono record;
  v_aberta record;
  c public.comprovantes;
  v_num integer;
  v_r jsonb;
  v_prox jsonb;
  v_fila integer;
  v_entraram jsonb := '[]'::jsonb;
  v_id uuid;
  v_restam integer;
  v_motivo text;
  v_canc jsonb;
  v_resolvidas text[];
  v_campo text;
  v_valor text;
  v_os jsonb;
  v_data date;
  v_alvo uuid;
  v_cmp_num integer;
  v_gravado_codigo text;
  v_corrigido jsonb;
  v_cat text;
  v_n integer;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'comprovante_comando: a entrada precisa ser um objeto' using errcode = '22023';
  end if;
  v_phone := p->>'phone';
  v_cmd := p->>'comando';
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_comando: telefone inválido' using errcode = '22023';
  end if;
  if v_cmd is null or v_cmd not in ('cmp', 'pular', 'sair', 'lote_antigo', 'cancelar', 'feito', 'corrigir') then
    raise exception 'comprovante_comando: comando desconhecido' using errcode = '22023';
  end if;
  select d.id, d.phone into v_dono from public._comprovante_dono() d;
  if not public._comprovante_conversa_ligada() or v_dono.phone is distinct from v_phone then
    return jsonb_build_object('resultado', 'desligada');
  end if;
  begin
    v_num := nullif(p->>'numero', '')::integer;
  exception when others then
    raise exception 'comprovante_comando: número malformado' using errcode = '22023';
  end;

  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  perform public._pergunta_limpar(v_phone);
  select w.id, w.referencia_id, w.dados into v_aberta from public.whatsapp_perguntas w
   where w.phone_normalized = v_phone and w.status = 'aberta' and w.origem = 'comprovante';

  if v_cmd in ('cmp', 'cancelar', 'feito') then
    select * into c from public.comprovantes x where x.numero = v_num and x.phone_normalized = v_phone;
    if not found then
      if v_cmd = 'cancelar' and char_length(regexp_replace(coalesce(p->>'motivo', ''), '[^[:alpha:]]', '', 'g')) < 3 then
        return jsonb_build_object('resultado', 'motivo_obrigatorio');
      end if;
      return jsonb_build_object('resultado', 'nao_existe');
    end if;
  end if;

  -- ── cmp N ────────────────────────────────────────────────────────────────────────────────
  if v_cmd = 'cmp' then
    if c.gravado_em is not null or c.situacao = 'cancelado'
       or not (c.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
               or (c.situacao in ('lido', 'falhou') and c.modo = 'dono' and c.fila_desde is null)) then
      return jsonb_build_object('resultado', 'cartao', 'cmp', public._comprovante_resumo(c), 'efeitos', c.efeitos);
    end if;
    if v_aberta.id is not null and v_aberta.referencia_id <> c.id then
      perform public._pergunta_fechar(v_aberta.id, 'substituida', 'cmp', null);
      perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
      -- o anterior volta à FRENTE da fila
      update public.comprovantes x
         set fila_ordem = coalesce((select min(y.fila_ordem) from public.comprovantes y
                                     where y.phone_normalized = v_phone and y.situacao = 'aguardando_vez'), now())
                          - interval '1 second'
       where x.id = v_aberta.referencia_id;
    end if;
    v_r := public._comprovante_proxima(v_phone, 'cmp', c.id, null);
    return jsonb_build_object('resultado', 'pergunta',
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end,
      'motivo', case when not coalesce((v_r->>'perguntou')::boolean, false) then v_r->>'motivo' end,
      'ocupado_por', v_r->'ocupado_por');
  end if;

  -- ── pular ────────────────────────────────────────────────────────────────────────────────
  if v_cmd = 'pular' then
    if v_aberta.id is null then
      select count(*) into v_fila from public.comprovantes x
       where x.phone_normalized = v_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
      return jsonb_build_object('resultado', 'pulado', 'codigo', null, 'pergunta', null, 'fila', v_fila);
    end if;
    perform public._pergunta_fechar(v_aberta.id, 'cancelada', 'pular', null);
    -- para o fim da fila, e o vigia só volta a ele daqui a 4 h (senão o "fica para depois" virava
    -- "Ainda falta conferir…" dois minutos depois)
    update public.comprovantes x set fila_ordem = clock_timestamp(), adiado_ate = now() + interval '4 hours'
     where x.id = v_aberta.referencia_id;
    perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
    v_r := public._comprovante_proxima(v_phone, 'pular', null, v_aberta.referencia_id);
    select count(*) into v_fila from public.comprovantes x
     where x.phone_normalized = v_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
    return jsonb_build_object('resultado', 'pulado',
      'codigo', (select x.codigo from public.comprovantes x where x.id = v_aberta.referencia_id),
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end,
      'fila', v_fila);
  end if;

  -- ── sair ─────────────────────────────────────────────────────────────────────────────────
  if v_cmd = 'sair' then
    if v_aberta.id is not null then
      perform public._pergunta_fechar(v_aberta.id, 'cancelada', 'sair', null);
      perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
    end if;
    insert into public.comprovantes_fila_do_telefone as f (phone_normalized, pausada_ate, atualizado_em)
    values (v_phone, now() + interval '12 hours', now())
    on conflict (phone_normalized) do update set pausada_ate = now() + interval '12 hours', atualizado_em = now();
    select count(*) into v_fila from public.comprovantes x
     where x.phone_normalized = v_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
    -- o primeiro da fila: o "para continuar antes: *cmp N*"
    return jsonb_build_object('resultado', 'pausado', 'fila', v_fila,
      'codigo', (select x.codigo from public.comprovantes x
                  where x.phone_normalized = v_phone and x.situacao = 'aguardando_vez'
                  order by x.fila_ordem, x.numero limit 1));
  end if;

  -- ── lote antigo ──────────────────────────────────────────────────────────────────────────
  if v_cmd = 'lote_antigo' then
    for v_id in
      select x.id from public.comprovantes x
       where x.phone_normalized = v_phone and x.dono_id = v_dono.id and x.modo = 'dono' and x.numero is not null
         and x.situacao in ('lido', 'falhou') and x.fila_desde is null and x.gravado_em is null
       order by x.recebido_em, x.numero
       limit 20
    loop
      if public._comprovante_entrar_na_fila(v_id) then
        v_entraram := v_entraram || jsonb_build_array(jsonb_build_object(
          'id', v_id, 'codigo', (select x.codigo from public.comprovantes x where x.id = v_id)));
      end if;
    end loop;
    select count(*) into v_restam from public.comprovantes x
     where x.phone_normalized = v_phone and x.dono_id = v_dono.id and x.modo = 'dono' and x.numero is not null
       and x.situacao in ('lido', 'falhou') and x.fila_desde is null and x.gravado_em is null;
    if jsonb_array_length(v_entraram) > 0 then
      v_r := public._comprovante_proxima(v_phone, 'lote_antigo', null, null);
    end if;
    return jsonb_build_object('resultado', 'lote', 'entraram', v_entraram, 'restam', v_restam,
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end);
  end if;

  -- ── cancelar cmp N motivo ────────────────────────────────────────────────────────────────
  if v_cmd = 'cancelar' then
    v_motivo := nullif(btrim(coalesce(p->>'motivo', '')), '');
    if v_motivo is null or char_length(regexp_replace(v_motivo, '[^[:alpha:]]', '', 'g')) < 3 then
      return jsonb_build_object('resultado', 'motivo_obrigatorio', 'codigo', c.codigo);
    end if;
    v_canc := public.comprovante_cancelar(c.id, left(v_motivo, 300), v_dono.id);
    if not coalesce((v_canc->>'ok')::boolean, false) then
      return jsonb_build_object('resultado', 'cancelamento_recusado', 'cancelamento', v_canc, 'pergunta', null);
    end if;
    if v_aberta.id is not null and v_aberta.referencia_id = c.id then
      v_r := public._comprovante_proxima(v_phone, 'depois_de_gravar', null, null);
    end if;
    return jsonb_build_object('resultado', 'cancelado', 'cancelamento', v_canc,
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end);
  end if;

  -- ── feito cmp N ──────────────────────────────────────────────────────────────────────────
  if v_cmd = 'feito' then
    v_resolvidas := c.pendencias;
    if cardinality(v_resolvidas) > 0 then
      update public.comprovantes x
         set pendencias = '{}',
             efeitos = x.efeitos || coalesce((select jsonb_agg(jsonb_build_object('tipo', 'pendencia_resolvida', 'qual', q, 'em', now()))
                                                from unnest(v_resolvidas) q), '[]'::jsonb)
       where x.id = c.id;
      update public.comprovantes_indice_mensal i set pendente = true, proxima_em = now(), atualizado_em = now()
       where i.mes = coalesce(c.indice_mes, date_trunc('month', coalesce(c.data_confirmada, c.data_compra, (c.recebido_em at time zone 'America/Sao_Paulo')::date))::date);
    end if;
    return jsonb_build_object('resultado', 'feito', 'codigo', c.codigo, 'resolvidas', to_jsonb(v_resolvidas));
  end if;

  -- ── corrigir <campo> ─────────────────────────────────────────────────────────────────────
  -- O alvo: o CMP dito ("corrigir cmp 124 valor 70"); senão o da pergunta aberta; senão o CMP em
  -- contexto. Logo depois de um "gravado… Próximo:", "corrigir valor 70" sem dizer o CMP é ambíguo
  -- (o gravado ou o próximo?): pergunta qual (resultado qual_cmp), nada muda.
  v_campo := p->>'campo';
  if v_campo is null or v_campo not in ('valor', 'data', 'forma', 'os', 'quem', 'para', 'categoria', 'obs') then
    raise exception 'comprovante_comando: campo do corrigir desconhecido' using errcode = '22023';
  end if;
  begin
    v_cmp_num := nullif(p->>'cmp', '')::integer;
  exception when others then
    raise exception 'comprovante_comando: número do CMP malformado' using errcode = '22023';
  end;
  if v_cmp_num is not null then
    select x.id into v_alvo from public.comprovantes x where x.numero = v_cmp_num and x.phone_normalized = v_phone;
    if v_alvo is null then
      return jsonb_build_object('resultado', 'nao_existe');
    end if;
  else
    v_alvo := v_aberta.referencia_id;
    if v_aberta.id is not null and v_aberta.dados->>'motivo' = 'depois_de_gravar' then
      select x.codigo into v_gravado_codigo
        from public.comprovantes x
       where x.phone_normalized = v_phone and x.id <> v_aberta.referencia_id and x.gravado_em > now() - interval '2 minutes'
         and x.situacao <> 'cancelado'
       order by x.gravado_em desc
       limit 1;
      if v_gravado_codigo is not null then
        return jsonb_build_object('resultado', 'qual_cmp', 'gravado', v_gravado_codigo,
                                  'aberto', (select x.codigo from public.comprovantes x where x.id = v_aberta.referencia_id));
      end if;
    end if;
  end if;
  if v_alvo is null then
    select x.id into v_alvo
      from public.comprovantes x
     where x.phone_normalized = v_phone and x.numero is not null and x.situacao <> 'cancelado'
       and (x.gravado_em > now() - interval '30 minutes' or x.ultima_pergunta_em > now() - interval '30 minutes')
     order by greatest(coalesce(x.gravado_em, '-infinity'::timestamptz), coalesce(x.ultima_pergunta_em, '-infinity'::timestamptz)) desc
     limit 1;
  end if;
  if v_alvo is null then
    return jsonb_build_object('resultado', 'sem_cmp');
  end if;
  select * into c from public.comprovantes x where x.id = v_alvo for update;
  if c.gravado_em is not null then
    return jsonb_build_object('resultado', 'ja_gravado', 'codigo', c.codigo);
  end if;
  if c.situacao = 'cancelado' then
    return jsonb_build_object('resultado', 'ja_cancelado', 'codigo', c.codigo);
  end if;
  if c.situacao in ('lido', 'falhou') and not public._comprovante_entrar_na_fila(c.id) then
    return jsonb_build_object('resultado', 'sem_cmp');
  end if;

  case v_campo
    when 'valor' then
      v_valor := p->>'valor';
      if v_valor is null or v_valor !~ '^[0-9]{1,10}\.[0-9]{2}$' or v_valor::numeric <= 0 or v_valor::numeric > 999999.99 then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'valor_invalido');
      end if;
      update public.comprovantes x set valor_confirmado = v_valor::numeric, passo = null, resumo_versao = x.resumo_versao + 1,
                                      mesma_compra_de = null, outra_compra = null
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'valor', 'valor', v_valor);
    when 'data' then
      begin
        v_data := (p->>'data')::date;
      exception when others then
        v_data := null;
      end;
      if v_data is null or v_data > (now() at time zone 'America/Sao_Paulo')::date then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'data_invalida');
      end if;
      update public.comprovantes x set data_confirmada = v_data, passo = null, resumo_versao = x.resumo_versao + 1,
                                      mesma_compra_de = null, outra_compra = null
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'data', 'valor', v_data);
    when 'forma' then
      v_valor := p->>'forma';
      if v_valor is null or v_valor not in ('pix', 'debito', 'credito', 'dinheiro', 'boleto', 'transferencia') then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'forma_invalida');
      end if;
      update public.comprovantes x
         set forma_confirmada = v_valor, passo = null, resumo_versao = x.resumo_versao + 1,
             -- quem pagou só se pergunta no dinheiro: trocar a forma refaz a pergunta
             quem_pagou = case when v_valor = 'dinheiro' or x.forma_confirmada = 'dinheiro' then null else x.quem_pagou end,
             pagador_payee_id = case when v_valor = 'dinheiro' or x.forma_confirmada = 'dinheiro' then null else x.pagador_payee_id end
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'forma', 'valor', v_valor);
    when 'os' then
      v_os := public._comprovante_os_por_numero(v_num);
      if not (v_os ? 'id') then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', v_os->>'motivo');
      end if;
      update public.comprovantes x
         set destino = 'os', destino_os_id = (v_os->>'id')::uuid,
             tipo_na_os = case when x.destino_os_id = (v_os->>'id')::uuid then x.tipo_na_os end,
             -- saiu do PESSOAL: "quem pagou" muda de sentido
             quem_pagou = case when x.destino = 'pessoal' then null else x.quem_pagou end,
             pagador_payee_id = case when x.destino = 'pessoal' then null else x.pagador_payee_id end,
             mesma_compra_de = null, outra_compra = null,
             passo = null, resumo_versao = x.resumo_versao + 1
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'os', 'valor',
                                        (select so.service_order_number from public.service_orders so where so.id = (v_os->>'id')::uuid));
    when 'quem' then
      update public.comprovantes x set quem_pagou = null, pagador_payee_id = null, passo = 'quem_pagou',
                                      resumo_versao = x.resumo_versao + 1 where x.id = c.id;
    when 'para' then
      v_valor := p->>'destino';
      if v_valor in ('estoque', 'insumo', 'empresa', 'pessoal') then
        -- "corrigir para estoque": o destino dito, sem o menu
        update public.comprovantes x set destino = v_valor, destino_os_id = null, tipo_na_os = null, passo = null,
                                        mesma_compra_de = null, outra_compra = null,
                                        quem_pagou = case when coalesce(x.destino = 'pessoal', false) <> (v_valor = 'pessoal')
                                                          then null else x.quem_pagou end,
                                        pagador_payee_id = case when coalesce(x.destino = 'pessoal', false) <> (v_valor = 'pessoal')
                                                                then null else x.pagador_payee_id end,
                                        resumo_versao = x.resumo_versao + 1 where x.id = c.id;
        v_corrigido := jsonb_build_object('campo', 'para', 'valor', v_valor);
      else
        update public.comprovantes x set destino = null, destino_os_id = null, tipo_na_os = null, passo = 'para_que',
                                        mesma_compra_de = null, outra_compra = null,
                                        resumo_versao = x.resumo_versao + 1 where x.id = c.id;
      end if;
    when 'categoria' then
      v_valor := public._comprovante_normalizar(p->>'categoria');
      if coalesce(v_valor, '') = '' then
        -- sem o nome: o menu de categorias
        update public.comprovantes x set categoria = null, passo = 'categoria', resumo_versao = x.resumo_versao + 1
         where x.id = c.id;
      else
        select (array_agg(f.name order by f.name))[1], count(*) into v_cat, v_n
          from public.financial_categories f
         where f.type = 'payable' and coalesce(f.active, false) and public._comprovante_normalizar(f.name) = v_valor;
        if v_n <> 1 then
          select (array_agg(f.name order by f.name))[1], count(*) into v_cat, v_n
            from public.financial_categories f
           where f.type = 'payable' and coalesce(f.active, false) and char_length(v_valor) >= 3
             and (' ' || public._comprovante_normalizar(f.name) || ' ') like ('% ' || v_valor || ' %');
        end if;
        if v_n <> 1 then
          return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'categoria_nao_achada');
        end if;
        update public.comprovantes x set categoria = v_cat, passo = null, resumo_versao = x.resumo_versao + 1
         where x.id = c.id;
        v_corrigido := jsonb_build_object('campo', 'categoria', 'valor', v_cat);
      end if;
    when 'obs' then
      -- a observação do dono (A, 12/10/2026): uma linha, até 200; vazia = apaga. Não muda o passo (a
      -- mesma pergunta volta); sobe a versão (a descrição do lançamento faz parte do que o sim aprova)
      v_valor := nullif(btrim(regexp_replace(coalesce(p->>'observacao', ''), '[[:space:]]+', ' ', 'g')), '');
      if char_length(v_valor) > 200 then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'obs_longa');
      end if;
      update public.comprovantes x set observacao = v_valor, resumo_versao = x.resumo_versao + 1
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'obs', 'valor', public._comprovante_obs_sem_cpf(v_valor));
  end case;

  if v_aberta.id is not null then
    if public._pergunta_fechar(v_aberta.id, 'substituida', 'corrigir', null) and v_aberta.referencia_id <> c.id then
      perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
    end if;
  end if;
  v_r := public._comprovante_proxima(v_phone, 'reabrir', c.id, null);
  return jsonb_build_object('resultado', 'pergunta', 'codigo', c.codigo, 'corrigido', v_corrigido,
    'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end,
    'motivo', case when not coalesce((v_r->>'perguntou')::boolean, false) then v_r->>'motivo' end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. CmpResumo: + "observacao" (sem CPF)
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011303000:1649-1705 IGUAL + 'observacao' logo depois de 'categoria'
create or replace function public._comprovante_resumo(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_forn jsonb := public._comprovante_fornecedor(c);
  v_ef jsonb := public._comprovante_efetivo(c);
  v_os jsonb := public._comprovante_os_info(c.destino_os_id);
  v_raiz text := public.raiz_do_cnpj_da_empresa();
begin
  return jsonb_build_object(
    'id', c.id,
    'codigo', c.codigo,
    'numero', c.numero,
    'situacao', c.situacao,
    'tipo', c.tipo,
    'valor', c.valor_confirmado::text,
    'valor_lido', c.valor::text,
    'valor_confianca', c.valor_confianca,
    'data', coalesce(c.data_confirmada, c.data_compra),
    -- de onde veio a data: lida do documento, o dia do envio (a leitura não trouxe) ou dita pelo dono
    'data_origem', case when c.data_compra is not null and coalesce(c.data_confirmada, c.data_compra) = c.data_compra then 'leitura'
                        when c.data_compra is null
                             and coalesce(c.data_confirmada, (c.recebido_em at time zone 'America/Sao_Paulo')::date)
                                 = (c.recebido_em at time zone 'America/Sao_Paulo')::date then 'envio'
                        else 'dono' end,
    -- quando chegou (o cabeçalho do CMP sem leitura diz "foto das 10h41 de 11/10")
    'recebido_em', c.recebido_em,
    'hora', c.hora_compra::text,
    'forma', c.forma_confirmada,
    'fornecedor', v_forn->>'nome',
    'fornecedor_origem', v_forn->>'origem',
    'cnpj', case when c.emitente_cnpj is not null and (v_raiz is null or left(c.emitente_cnpj, 8) <> v_raiz)
                 then c.emitente_cnpj end,
    'cnpj_confianca', c.cnpj_confianca,
    'destino', c.destino,
    'os', case when v_os is null then null
               else jsonb_build_object('id', v_os->'id', 'numero', v_os->'numero', 'barco', v_os->'barco',
                                       'cliente', v_os->'cliente', 'status', v_os->'status',
                                       'faturada', v_os->'faturada', 'assinada', v_os->'assinada',
                                       'pasta_registrada', v_os->'pasta_registrada') end,
    'tipo_na_os', c.tipo_na_os,
    -- o lançamento que já está na OS (só comprova): {"tipo","id","valor","data","descricao","categoria"|"produto"}
    -- ou {"ambiguo":n}
    'na_os', public._comprovante_lancamento_na_os(c),
    'quem_pagou', v_ef->>'quem',
    'pagador_nome', v_ef->>'pagador_nome',
    'categoria', v_ef->>'categoria',
    'observacao', public._comprovante_obs_sem_cpf(c.observacao),
    'mesma_compra', case when c.mesma_compra_de is not null
                         then (select jsonb_build_object('codigo', y.codigo) from public.comprovantes y where y.id = c.mesma_compra_de) end,
    'pendencias', to_jsonb(c.pendencias),
    'gravado_em', c.gravado_em,
    'banco', public._comprovante_banco_resumo(c));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. comprovantes_consultar (a leitura do assistente): + "observacao" (sem CPF)
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011202000:2394-2460 IGUAL + 'observacao' logo depois de 'quem_pagou'
create or replace function public.comprovantes_consultar(p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid;
  v_numero integer;
  v_situacao text;
  v_desde date;
  v_ate date;
  v_os uuid;
  v_valor numeric;
  v_itens jsonb;
  v_total integer;
  v_vazio constant jsonb := jsonb_build_object('itens', '[]'::jsonb, 'total', 0);
begin
  begin
    v_autor := coalesce((select auth.uid()), nullif(p->>'autor', '')::uuid);
    v_numero := coalesce(nullif(p->>'numero', '')::integer,
                         nullif(substring(coalesce(p->>'codigo', '') from '([0-9]+)$'), '')::integer);
    v_situacao := nullif(p->>'situacao', '');
    v_desde := nullif(p->>'desde', '')::date;
    v_ate := nullif(p->>'ate', '')::date;
    v_os := nullif(p->>'os_id', '')::uuid;
    v_valor := nullif(p->>'valor', '')::numeric;
  exception when others then
    return v_vazio;
  end;
  if v_autor is null or not public.is_admin(v_autor) then
    return v_vazio;
  end if;

  with filtrados as (
    select x.id, x.numero
      from public.comprovantes x
     where x.numero is not null and x.modo = 'dono'
       and (v_numero is null or x.numero = v_numero)
       and (v_situacao is null or x.situacao = v_situacao)
       and (v_desde is null or coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date) >= v_desde)
       and (v_ate is null or coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date) <= v_ate)
       and (v_os is null or x.destino_os_id = v_os)
       and (v_valor is null or abs(coalesce(x.valor_confirmado, x.valor) - v_valor) <= 0.01)
  )
  select (select count(*) from filtrados),
         coalesce((select jsonb_agg(jsonb_build_object(
             'codigo', f.codigo,
             'situacao', f.situacao,
             'tipo', f.tipo,
             'valor', coalesce(f.valor_confirmado, f.valor)::text,
             'data', coalesce(f.data_confirmada, f.data_compra),
             'fornecedor', public._comprovante_fornecedor(f)->>'nome',
             'destino', f.destino,
             'os_numero', (select so.service_order_number from public.service_orders so where so.id = f.destino_os_id),
             'tipo_na_os', f.tipo_na_os,
             'quem_pagou', f.quem_pagou,
             'observacao', public._comprovante_obs_sem_cpf(f.observacao),
             'forma', coalesce(f.forma_confirmada, f.forma_pagamento),
             'pendencias', to_jsonb(f.pendencias),
             'gravado_em', f.gravado_em,
             'dropbox_caminho', f.dropbox_caminho) order by f.numero desc)
            from (select y.id from filtrados y order by y.numero desc limit 20) ids
            join public.comprovantes f on f.id = ids.id), '[]'::jsonb)
    into v_total, v_itens;
  return jsonb_build_object('itens', v_itens, 'total', v_total);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. comprovantes_indice_do_mes (o _INDICE do mês): + "observacao" (sem CPF), a última coluna do CSV
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011304000:98-148 IGUAL + 'observacao' logo depois de 'pendencias'
create or replace function public.comprovantes_indice_do_mes(p_mes date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_linhas jsonb;
  i record;
begin
  if p_mes is null then
    raise exception 'comprovantes_indice_do_mes: mês obrigatório' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', x.codigo,
           'data', coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date),
           'hora', x.hora_compra::text,
           'tipo', x.tipo,
           'valor', coalesce(x.valor_confirmado, x.valor)::text,
           'fornecedor', public._comprovante_fornecedor(x)->>'nome',
           'cnpj', case when x.emitente_cnpj is not null and (v_raiz is null or left(x.emitente_cnpj, 8) <> v_raiz)
                        then x.emitente_cnpj end,
           'destino', x.destino,
           'os', so.service_order_number,
           'barco', nullif(btrim(v.name), ''),
           'na_os', case when x.destino is distinct from 'os' then null
                         when x.efeitos @> '[{"tipo": "despesa_os"}]'::jsonb then 'despesa'
                         when x.efeitos @> '[{"tipo": "anexar_despesa"}]'::jsonb or x.efeitos @> '[{"tipo": "anexar_peca"}]'::jsonb
                              or x.efeitos @> '[{"tipo": "comprovar_na_os", "motivo": "ambiguo"}]'::jsonb then 'ja_lancado'
                         else x.tipo_na_os end,
           'quem_pagou', x.quem_pagou,
           'forma', coalesce(x.forma_confirmada, x.forma_pagamento),
           'situacao', x.situacao,
           'pendencias', to_jsonb(x.pendencias),
           'observacao', public._comprovante_obs_sem_cpf(x.observacao),
           'arquivo', x.dropbox_caminho) order by x.numero), '[]'::jsonb)
    into v_linhas
    from public.comprovantes x
    left join public.service_orders so on so.id = x.destino_os_id
    left join public.vessels v on v.id = so.vessel_id
   where x.numero is not null
     and x.destino is distinct from 'pessoal'
     and coalesce(x.indice_mes,
                  date_trunc('month', coalesce(x.data_confirmada, x.data_compra,
                                               (x.recebido_em at time zone 'America/Sao_Paulo')::date))::date) = v_mes;
  select m.dropbox_id, m.caminho, m.rev into i from public.comprovantes_indice_mensal m where m.mes = v_mes;
  return jsonb_build_object('mes', to_char(v_mes, 'YYYY-MM'), 'dropbox_id', i.dropbox_id, 'caminho', i.caminho,
                            'rev', i.rev, 'linhas', v_linhas);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6b. comprovantes_indice_pessoal_do_mes (o _INDICE PESSOAL): + "observacao" (sem CPF)
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011304000:153-203 IGUAL + 'observacao' logo depois de 'pendencias'
create or replace function public.comprovantes_indice_pessoal_do_mes(p_mes date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_linhas jsonb;
  i record;
begin
  if p_mes is null then
    raise exception 'comprovantes_indice_pessoal_do_mes: mês obrigatório' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', x.codigo,
           'data', coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date),
           'hora', x.hora_compra::text,
           'tipo', x.tipo,
           'valor', coalesce(x.valor_confirmado, x.valor)::text,
           'fornecedor', public._comprovante_fornecedor(x)->>'nome',
           'cnpj', case when x.emitente_cnpj is not null and (v_raiz is null or left(x.emitente_cnpj, 8) <> v_raiz)
                        then x.emitente_cnpj end,
           'destino', x.destino,
           'os', so.service_order_number,
           'barco', nullif(btrim(v.name), ''),
           'na_os', case when x.destino is distinct from 'os' then null
                         when x.efeitos @> '[{"tipo": "despesa_os"}]'::jsonb then 'despesa'
                         when x.efeitos @> '[{"tipo": "anexar_despesa"}]'::jsonb or x.efeitos @> '[{"tipo": "anexar_peca"}]'::jsonb
                              or x.efeitos @> '[{"tipo": "comprovar_na_os", "motivo": "ambiguo"}]'::jsonb then 'ja_lancado'
                         else x.tipo_na_os end,
           'quem_pagou', x.quem_pagou,
           'forma', coalesce(x.forma_confirmada, x.forma_pagamento),
           'situacao', x.situacao,
           'pendencias', to_jsonb(x.pendencias),
           'observacao', public._comprovante_obs_sem_cpf(x.observacao),
           'arquivo', x.dropbox_caminho) order by x.numero), '[]'::jsonb)
    into v_linhas
    from public.comprovantes x
    left join public.service_orders so on so.id = x.destino_os_id
    left join public.vessels v on v.id = so.vessel_id
   where x.numero is not null
     and x.destino = 'pessoal'
     and coalesce(x.indice_mes,
                  date_trunc('month', coalesce(x.data_confirmada, x.data_compra,
                                               (x.recebido_em at time zone 'America/Sao_Paulo')::date))::date) = v_mes;
  select m.dropbox_id, m.caminho, m.rev into i from public.comprovantes_indice_pessoal m where m.mes = v_mes;
  return jsonb_build_object('mes', to_char(v_mes, 'YYYY-MM'), 'dropbox_id', i.dropbox_id, 'caminho', i.caminho,
                            'rev', i.rev, 'linhas', v_linhas);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. _comprovante_gravar: a descrição do lançamento pela _comprovante_descricao
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011303000:646-1011 IGUAL + v_desc := public._comprovante_descricao(c) no lugar da expressão de 303000:719-720 (o reembolso do técnico nas Diárias segue SEM a observação)
create or replace function public._comprovante_gravar(p_id uuid, p_autor uuid, p_plano_hash text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_plano jsonb;
  v_ef jsonb;
  e jsonb;
  v_cat text;
  v_desc text;
  v_os uuid;
  v_r jsonb;
  v_efeitos jsonb := '[]'::jsonb;
  v_msgs text[] := '{}';
  v_pend text[] := '{}';
  v_so_expense uuid;
  v_so_criada boolean := false;
  v_anotacao uuid;
  v_payable uuid;
  v_nota uuid;
  v_aguardando timestamptz;
  v_idx integer[];
  v_corr jsonb;
  v_t text;
  v_estado text;
  v_doc text;
  v_mes date;
  v_anotou boolean;
  v_so_part uuid;
  v_fav uuid;
  v_avisos_g text[] := '{}';
  v_aprovar jsonb;
  -- F3
  v_regra jsonb;
  v_av jsonb;
  v_situacao text;
  v_lig jsonb;
  v_ligada uuid;
  v_explicada boolean := false;
  v_lig_pend text;
  v_reembolso uuid;
  v_desp_reemb uuid;
  v_avisos_f3 text[] := '{}';
  v_perguntar boolean;
begin
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception '_comprovante_gravar: comprovante % não existe', p_id using errcode = '22023';
  end if;
  if c.situacao <> 'aguardando_sim' then
    raise exception 'O comprovante % não está esperando o sim.', c.codigo using errcode = '22023';
  end if;
  if p_autor is null or p_autor is distinct from c.dono_id or not public.is_admin(p_autor) then
    raise exception 'Só o dono grava o comprovante.' using errcode = '42501';
  end if;
  v_plano := public._comprovante_plano(c.id);
  if v_plano ? 'falta' then
    raise exception 'Falta responder: %.', array_to_string(array(select jsonb_array_elements_text(v_plano->'falta')), ', ')
      using errcode = '22023';
  end if;
  if md5(v_plano::text) is distinct from p_plano_hash then
    raise exception 'O resumo do % mudou desde que foi mostrado.', c.codigo using errcode = 'MFC01';
  end if;

  v_ef := public._comprovante_efetivo(c);
  v_cat := v_ef->>'categoria';
  v_os := case when c.destino = 'os' then c.destino_os_id end;
  -- PESSOAL que a empresa pagou: o favorecido é o sócio (a aprovação leva pela anotação; o pró-labore desconta)
  v_fav := case when c.destino = 'pessoal' then nullif(v_ef->>'pagador_id', '')::uuid end;
  v_desc := public._comprovante_descricao(c);
  -- F3: a avaliação do extrato que o plano mostrou (fica guardada no CMP)
  v_regra := public._comprovante_banco_regra(c);
  if v_regra is not null then
    v_av := public._comprovante_candidatos(c);
  end if;
  v_situacao := v_plano->>'situacao_final';

  for e in select value from jsonb_array_elements(v_plano->'efeitos')
  loop
    case e->>'tipo'
      -- ── OS / nota ──────────────────────────────────────────────────────────────────────
      when 'despesa_os' then
        -- custo interno da OS (não faturável, origem = o CMP): o total da OS não muda
        v_so_expense := public._comprovante_despesa_da_os(c.id, e, p_autor, v_desc);
        v_so_criada := true;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'despesa_os', 'so_expense_id', v_so_expense, 'os_id', e->'os_id', 'os_numero', e->'os_numero',
          'paid_by', e->'paid_by'));
      when 'anexar_despesa' then
        -- a despesa que já estava na OS: só comprova (nada nela muda)
        v_so_expense := (e->>'so_expense_id')::uuid;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'anexar_despesa', 'so_expense_id', v_so_expense,
                                                                       'os_numero', e->'os_numero'));
      when 'anexar_peca' then
        -- a peça que já estava na OS: só comprova (o custo é o da peça)
        v_so_part := (e->>'so_part_id')::uuid;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'anexar_peca', 'so_part_id', v_so_part,
                                                                       'os_numero', e->'os_numero', 'produto', e->'produto',
                                                                       'valor', e->'valor'));
      when 'comprovar_na_os' then
        -- só a prova da OS (peça a lançar pela tela, ou vários lançamentos iguais): nenhum custo
        v_efeitos := v_efeitos || jsonb_build_array(e);
      when 'itens_da_nota' then
        v_nota := (e->>'fiscal_note_id')::uuid;
        v_idx := public._comprovante_ligar_nota(v_nota, (e->>'os_id')::uuid);
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'itens_da_nota', 'fiscal_note_id', v_nota, 'os_id', e->'os_id', 'os_numero', e->'os_numero',
          'itens', to_jsonb(v_idx)));
      when 'aguardar_nota' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'aguardar_nota', 'os_id', e->'os_id'));
      when 'mesma_compra' then
        v_efeitos := v_efeitos || jsonb_build_array(e);

      -- ── financeiro ─────────────────────────────────────────────────────────────────────
      when 'anotar' then
        v_doc := public._comprovante_documento(c);
        v_anotou := true;
        begin
          v_r := public.anotar_transacao('saida', c.valor_confirmado, c.data_confirmada, v_doc,
                                         null, public._comprovante_fornecedor_efetivo(c, v_doc), v_fav, null, v_cat, v_os, v_desc, p_autor);
        exception when others then
          get stacked diagnostics v_t = message_text, v_estado = returned_sqlstate;
          -- o documento contradiz o cadastro (_anotacao_documento_confere): não anota; a linha do
          -- banco é classificada no Extrato. Qualquer outro erro desfaz tudo (o responder mostra).
          if v_estado = 'P0001' and v_t like 'O documento % não é o de %' then
            v_anotou := false;
          else
            raise;
          end if;
        end;
        if not v_anotou then
          v_pend := v_pend || 'classificar_no_extrato'::text;
          v_msgs := v_msgs || 'o documento do comprovante não é o do fornecedor no cadastro: não anotei (fica para classificar no Extrato)'::text;
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'anotacao_recusada'));
        elsif coalesce((v_r->>'ja_lancada')::boolean, false) and v_r->>'tipo' = 'payable' then
          -- A3: a linha do banco já virou lançamento → anexa e corrige só o que difere
          v_payable := (v_r->>'lancamento_id')::uuid;
          v_corr := public._comprovante_corrigir_lancamento(v_payable, v_cat, v_os, c.codigo, p_autor);
          if v_corr->>'mensagem' is not null then
            v_msgs := v_msgs || (v_corr->>'mensagem');
          end if;
          if jsonb_typeof(v_corr->'diferente') = 'object' then
            v_avisos_g := v_avisos_g || 'categoria_existente_diferente'::text;
          end if;
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anexar_lancamento', 'payable_id', v_payable, 'corrigido', v_corr->'corrigido', 'origem', 'anotar',
            'categoria_existente', v_corr->'diferente'->'categoria'));
        elsif coalesce((v_r->>'ok')::boolean, false) then
          -- A1 (a linha não chegou) ou A2 (estava na fila e saiu classificada; falta aprovar)
          v_anotacao := (v_r->>'id')::uuid;
          v_aguardando := now();
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anotar', 'anotacao_id', v_anotacao,
            'resultado', case when coalesce((v_r->>'aplicada')::boolean, false) then 'aplicada' else 'aguardando' end));
          if coalesce((v_r->>'falta_quem')::boolean, false) or v_r ? 'outra_contraparte'
             or coalesce((v_r->>'substituidas')::integer, 0) > 0 then
            v_msgs := v_msgs || left(v_r->>'message', 300);
          end if;
        else
          -- ambígua / gêmea / disputa / já anotada: a própria rota cancelou a anotação
          v_pend := v_pend || 'classificar_no_extrato'::text;
          v_msgs := v_msgs || left(coalesce(v_r->>'message', 'a anotação não entrou'), 300);
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'anotacao_recusada'));
        end if;
      when 'anexar_anotacao' then
        v_anotacao := (e->>'anotacao_id')::uuid;
        v_aguardando := now();
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'anexar_anotacao', 'anotacao_id', v_anotacao));
      when 'caixa' then
        v_r := public.lancar_no_caixa('saida', c.valor_confirmado, v_desc, c.data_confirmada, e->>'categoria',
                                      public._comprovante_fornecedor_efetivo(c, null), v_fav, null, v_os, 'caixa', null, p_autor);
        v_payable := (v_r->>'lancamento_id')::uuid;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'caixa', 'payable_id', v_payable));
      when 'reembolso_socio' then
        v_r := public.lancar_no_caixa('saida', c.valor_confirmado, v_desc, c.data_confirmada, e->>'categoria',
                                      public._comprovante_fornecedor_efetivo(c, null), null, null, v_os, 'socio',
                                      (e->>'socio_id')::uuid, p_autor);
        v_payable := (v_r->>'lancamento_id')::uuid;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'reembolso_socio', 'payable_id', v_payable));
      when 'anexar_lancamento' then
        -- o lançamento que já existia recebe a categoria e a OS do CMP (o "antes" fica para o cancelar)
        v_payable := (e->>'payable_id')::uuid;
        v_corr := public._comprovante_corrigir_lancamento(v_payable, e->>'categoria', v_os, c.codigo, p_autor);
        if v_corr->>'mensagem' is not null then
          v_msgs := v_msgs || (v_corr->>'mensagem');
        end if;
        if jsonb_typeof(v_corr->'diferente') = 'object' then
          v_avisos_g := v_avisos_g || 'categoria_existente_diferente'::text;
        end if;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_lancamento', 'payable_id', v_payable, 'corrigido', v_corr->'corrigido', 'origem', e->'origem',
          'categoria_existente', v_corr->'diferente'->'categoria'));
      when 'aguardar_fatura' then
        v_aguardando := now();
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'aguardar_fatura'));

      -- ── F3 ─────────────────────────────────────────────────────────────────────────────
      when 'ligar_linha' then
        -- o que já foi gravado neste sim (a conta anexada, a despesa) vale para explicar a linha
        c.payable_id := coalesce(v_payable, c.payable_id);
        c.anotacao_id := coalesce(v_anotacao, c.anotacao_id);
        c.so_expense_id := coalesce(v_so_expense, c.so_expense_id);
        v_lig := public._comprovante_linha_explicar(c, (e->>'bank_transaction_id')::uuid, p_autor, true);
        if v_lig->>'_erro' is not null or jsonb_typeof(v_lig->'_conflito') = 'object' then
          -- a baixa da conta foi recusada (mês fechado…), ou a linha já virou OUTRO lançamento com a
          -- conta do CMP em aberto (conflito): não liga; espera o banco e pergunta depois
          if v_lig->>'_erro' is not null then
            v_msgs := v_msgs || left('não dei baixa na conta a pagar: ' || (v_lig->>'_erro'), 300);
          else
            v_avisos_f3 := v_avisos_f3 || 'conta_aberta_e_linha_lancada'::text;
          end if;
          v_aguardando := now();
          v_situacao := 'aguardando_banco';
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'aguardar_banco', 'regra', v_av->>'regra', 'nivel', 'verde'));
        else
          v_ligada := (e->>'bank_transaction_id')::uuid;
          v_explicada := coalesce((v_lig->>'_explicada')::boolean, false);
          v_lig_pend := v_lig->>'_pendencia';
          v_payable := coalesce((v_lig->>'payable_id')::uuid, v_payable);
          v_anotacao := coalesce(v_anotacao, (v_lig->>'anotacao_id')::uuid);
          if v_lig_pend is not null then
            v_pend := v_pend || v_lig_pend;
          end if;
          if v_lig->>'_aviso' is not null then
            v_avisos_f3 := v_avisos_f3 || (v_lig->>'_aviso');
          end if;
          v_msgs := v_msgs || array(select jsonb_array_elements_text(coalesce(v_lig->'mensagens', '[]'::jsonb)));
          v_efeitos := v_efeitos || jsonb_build_array((v_lig - '_explicada' - '_pendencia' - '_aviso' - '_erro' - '_aplicou' - '_conflito')
                                                      || jsonb_build_object('origem', 'gravacao', 'nivel', 'verde',
                                                                            'como', coalesce(v_lig->>'como', 'classificou')));
        end if;
      when 'aguardar_banco' then
        v_aguardando := now();
        v_efeitos := v_efeitos || jsonb_build_array(e);
      when 'reembolso_tecnico' then
        insert into public.diarias_reembolsos (favorecido_id, data, valor, descricao, origem, origem_codigo, os_id, categoria, criado_por)
        values ((e->>'favorecido_id')::uuid, (e->>'data')::date, c.valor_confirmado,
                left('Reembolso ' || c.codigo || coalesce(' · ' || (public._comprovante_fornecedor(c)->>'nome'), '')
                     || case when (e->>'data')::date <> c.data_confirmada
                             then ' (compra de ' || to_char(c.data_confirmada, 'DD/MM') || ')' else '' end, 200),
                'comprovante', c.codigo, nullif(e->>'os_id', '')::uuid, left(e->>'categoria', 100), p_autor)
        returning id into v_reembolso;
        -- a despesa da OS paga pelo técnico (criada agora ou anexada) é devolvida pelas Diárias: fica
        -- "reembolsada" para a aba Financeiro › Reembolsos não cobrar o mesmo gasto outra vez (pagar
        -- por lá e depois o acerto pagava duas vezes). O cancelamento volta ao "a reembolsar".
        v_desp_reemb := null;
        if v_so_expense is not null then
          update public.service_order_expenses s
             set reimbursed = true, reimbursed_at = now()
           where s.id = v_so_expense and s.paid_by = 'technician' and not coalesce(s.reimbursed, false)
          returning s.id into v_desp_reemb;
        end if;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'reembolso_tecnico', 'reembolso_id', v_reembolso, 'favorecido_id', e->'favorecido_id',
          'favorecido_nome', e->'favorecido_nome', 'data', e->'data', 'valor', e->'valor',
          'despesa_reembolsada', v_desp_reemb));
      when 'nada' then
        if e->>'motivo' = 'nota' then
          v_nota := (e->>'fiscal_note_id')::uuid;
        end if;
        v_efeitos := v_efeitos || jsonb_build_array(e);
      when 'pendencia' then
        v_pend := v_pend || (e->>'qual');
      else
        raise exception '_comprovante_gravar: efeito desconhecido %', e->>'tipo' using errcode = '22023';
    end case;
  end loop;

  -- a despesa da OS aponta para o lançamento (criada agora, ou anexada sem lançamento)
  if v_so_expense is not null and v_payable is not null then
    update public.service_order_expenses s set linked_payable_id = v_payable
     where s.id = v_so_expense and s.linked_payable_id is null;
    if found and not v_so_criada then
      v_efeitos := (select jsonb_agg(case when x->>'tipo' = 'anexar_despesa'
                                          then x || jsonb_build_object('ligou_lancamento', v_payable) else x end
                                     order by o)
                      from jsonb_array_elements(v_efeitos) with ordinality as t(x, o));
    end if;
  end if;

  -- F3: a linha ligada e explicada não precisa mais ser classificada no Extrato
  if v_ligada is not null and v_explicada and v_lig_pend is null then
    v_pend := array_remove(v_pend, 'classificar_no_extrato');
  end if;

  -- pendências sem repetir, na ordem
  select coalesce(array_agg(q order by o), '{}') into v_pend
    from (select q, min(o) as o from unnest(v_pend) with ordinality as t(q, o) group by q) u;
  for v_t in select unnest(v_pend) loop
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'pendencia', 'qual', v_t));
  end loop;

  -- F3: a pergunta do extrato a fazer (o edge pergunta logo depois de gravar)
  v_perguntar := v_ligada is null and v_situacao = 'aguardando_banco' and v_av is not null
                 and v_av->>'nivel' in ('verde', 'azul');

  v_mes := date_trunc('month', c.data_confirmada)::date;
  update public.comprovantes x
     set situacao = v_situacao,
         bank_transaction_id = v_ligada,
         conciliacao = case when v_ligada is not null then 'verde' else v_av->>'nivel' end,
         conciliado_em = case when v_ligada is not null then now() end,
         linha_explicada_em = case when v_ligada is not null and v_explicada then now() end,
         reembolso_id = v_reembolso,
         banco_regra = v_regra->>'regra',
         banco_candidatos = coalesce(v_av->'linhas', '[]'::jsonb),
         banco_hash = v_av->>'hash',
         banco_avaliado_em = case when v_av is not null then now() end,
         banco_perguntar = v_perguntar,
         gravado_em = now(),
         gravado_por = p_autor,
         plano = v_plano,
         efeitos = v_efeitos,
         pendencias = v_pend,
         passo = null,
         quem_pagou = case when x.destino = 'pessoal' or x.mesma_compra_de is not null then x.quem_pagou else v_ef->>'quem' end,
         pagador_payee_id = coalesce(x.pagador_payee_id, nullif(v_ef->>'pagador_id', '')::uuid),
         categoria = coalesce(x.categoria, v_cat),
         so_expense_id = v_so_expense,
         so_part_id = v_so_part,
         anotacao_id = v_anotacao,
         payable_id = v_payable,
         fiscal_note_id = coalesce(v_nota, x.fiscal_note_id),
         aguardando_banco_desde = case when v_situacao = 'aguardando_banco' then coalesce(v_aguardando, now())
                                       else coalesce(v_aguardando, x.aguardando_banco_desde) end,
         indice_mes = v_mes,
         dropbox_pendente = 'mover',
         dropbox_mover_tentativas = 0,
         dropbox_mover_erro = null,
         -- +3 min: o edge move na hora; o vigia só pega se ele falhar
         dropbox_mover_proxima_em = now() + interval '3 minutes'
   where x.id = c.id;

  insert into public.comprovantes_indice_mensal as i (mes, pendente, proxima_em, atualizado_em)
  values (v_mes, true, now(), now())
  on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();

  -- resposta 3 do dono: a linha ligada neste SIM e classificada já é aprovada (o finance-review aprova a proposta)
  select * into c from public.comprovantes x where x.id = c.id;
  v_aprovar := public._comprovante_a_aprovar(c);

  -- a pasta como o dono a vê, pela MESMA regra do edge (o "gravado" diz onde o arquivo vai de fato)
  v_t := to_char(v_mes, 'YYYY-MM');
  return jsonb_build_object(
    'situacao', v_situacao,
    'efeitos', v_efeitos,
    'avisos', coalesce(v_plano->'avisos', '[]'::jsonb) || to_jsonb(v_avisos_f3) || to_jsonb(case when coalesce(v_plano->'avisos', '[]'::jsonb) ? 'categoria_existente_diferente' then '{}'::text[]
                                 else (select coalesce(array_agg(distinct a), '{}'::text[]) from unnest(v_avisos_g) a) end),
    'aprovar', case when v_aprovar is not null then jsonb_build_object('proposta_id', v_aprovar->'proposta_id') end,
    'mensagens', to_jsonb(v_msgs),
    'mes', v_t,
    'pasta', case v_plano->>'pasta'
               when 'barco' then case when public._comprovante_usa_pasta_do_barco(public._comprovante_os_info(c.destino_os_id))
                                      then (public._comprovante_os_info(c.destino_os_id)->>'barco') || '/1- DOC''s/Compras'
                                      else 'COMPROVANTES/' || left(v_t, 4) || '/' || v_t end
               when 'pessoal' then 'COMPROVANTES/PESSOAL/' || v_t
               else 'COMPROVANTES/' || left(v_t, 4) || '/' || v_t end,
    'banco', jsonb_build_object('nivel', case when v_ligada is not null then 'verde' else v_av->>'nivel' end,
                                'perguntar', v_perguntar));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. _comprovante_linha_explicar: a descrição da anotação pela _comprovante_descricao
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011302000:447-641 IGUAL + public._comprovante_descricao(c) no lugar da expressão de 302000:610 (v_forn segue no nome_pelo_comprovante)
create or replace function public._comprovante_linha_explicar(c public.comprovantes, p_tx uuid, p_autor uuid, p_casar boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  t record;
  v_pay record;
  v_cmp_pay record;
  v_prop record;
  v_ef jsonb := public._comprovante_efetivo(c);
  v_cat text := v_ef->>'categoria';
  v_os uuid := case when c.destino = 'os' then c.destino_os_id end;
  v_forn text := public._comprovante_fornecedor(c)->>'nome';
  v_anots uuid[];
  v_como text := 'aguardando';
  v_payable uuid;
  v_anot uuid;
  v_anot_criada boolean := false;
  v_aplicou boolean := false;
  v_proposta uuid;
  v_corr jsonb := '{}'::jsonb;
  v_msgs text[] := '{}';
  v_explicada boolean := false;
  v_pend text;
  v_aviso text;
  v_erro text;
  v_ligou_despesa boolean := false;
  v_lancado_depois boolean := false;
  v_conflito jsonb;
  v_t text;
  v_corr_r jsonb;
  v_cat_existente text;
begin
  select x.id, x.transaction_date, x.counterparty_name, x.merchant_name, x.description, x.nome_pelo_comprovante
    into t from public.bank_transactions x where x.id = p_tx for update;
  if not found then
    raise exception 'A linha do extrato não existe mais.' using errcode = '22023';
  end if;
  -- as anotações deste CMP: a da F2 e as que a F3 criou/usou nas ligações
  select array_agg(distinct a) into v_anots
    from (select c.anotacao_id as a
          union all
          select (e->>'anotacao_id')::uuid from jsonb_array_elements(c.efeitos) e
           where e->>'tipo' in ('ligar_linha', 'anotar', 'anexar_anotacao') and e->>'anotacao_id' is not null) s
   where a is not null;
  v_anots := coalesce(v_anots, '{}'::uuid[]);

  select p.id, p.status into v_pay from public.payables p
   where p.bank_transaction_id = p_tx and p.status <> 'cancelled'
   order by p.divisao_id nulls first, p.created_at, p.id
   limit 1;
  select p.id, p.status, p.bank_transaction_id into v_cmp_pay from public.payables p where p.id = c.payable_id;

  if v_pay.id is not null then
    -- 1. a linha já virou lançamento
    if v_pay.id = c.payable_id
       or exists (select 1 from jsonb_array_elements(c.efeitos) e
                   where e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = p_tx::text and not e ? 'desligado_em'
                     and e->'aprovado'->>'payable_id' = v_pay.id::text) then
      -- é o lançamento do próprio CMP (anexado na F2, a conta dele que ganhou a linha, ou o que o SIM do
      -- dono aprovou: resposta 3)
      v_como := 'anexou';
      v_payable := v_pay.id;
      v_explicada := true;
    elsif v_cmp_pay.id is null or v_cmp_pay.status = 'cancelled' then
      v_payable := v_pay.id;
      if p_casar then
        -- anexa no SIM do dono (a pergunta mostrou "uso o lançamento que já existe dela"): resposta 8 —
        -- só preenche o que está vazio (OS, categoria; o "antes" fica); categoria diferente fica e avisa
        v_corr_r := public._comprovante_corrigir_lancamento(v_pay.id, v_cat, v_os, c.codigo, p_autor);
        if v_corr_r->>'mensagem' is not null then
          v_msgs := v_msgs || (v_corr_r->>'mensagem');
        end if;
        v_corr := coalesce(v_corr_r->'corrigido', '{}'::jsonb);
        if jsonb_typeof(v_corr_r->'diferente') = 'object' then
          v_cat_existente := v_corr_r->'diferente'->>'categoria';
          v_aviso := 'categoria_existente_diferente';
        end if;
        v_como := 'anexou';
      else
        -- varredura: a linha que o CMP ligou foi APROVADA pelo dono no Extrato (ou lançada por
        -- outro caminho) depois da ligação. Só adota o lançamento: a categoria e a OS que o dono
        -- escolheu ao aprovar ficam (nada é corrigido sem SIM). O "como" de antes fica (quem chama
        -- não o troca) e lancado_depois marca que o lançamento NÃO é o que existia ao ligar: o
        -- cancelamento do CMP recusa (desfaz-se pelo Extrato).
        v_como := null;
        v_lancado_depois := true;
      end if;
      if c.so_expense_id is not null then
        update public.service_order_expenses s set linked_payable_id = v_pay.id
         where s.id = c.so_expense_id and s.linked_payable_id is null;
        v_ligou_despesa := found;
      end if;
      update public.anotacoes_do_extrato a
         set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = c.codigo || ': a linha do banco já foi lançada'
       where a.id = any (v_anots) and a.status = 'aguardando';
      v_explicada := true;
    elsif v_cmp_pay.status in ('pending', 'overdue', 'partially_paid') and v_cmp_pay.bank_transaction_id is null then
      -- o CMP anexou uma conta a pagar EM ABERTO e a linha já virou OUTRO lançamento: o mesmo gasto
      -- contado duas vezes. Não liga (quem chama recusa): o dono cancela uma das duas no Financeiro.
      v_conflito := jsonb_build_object('conta_aberta_id', v_cmp_pay.id, 'lancamento_id', v_pay.id);
      v_pend := 'classificar_no_extrato';
      v_aviso := 'conta_aberta_e_linha_lancada';
    else
      -- o CMP já tem OUTRO lançamento (pago por outra linha ou no Caixa): não mexe; o dono confere no Extrato
      v_pend := 'classificar_no_extrato';
      v_aviso := 'linha_lancada_em_outro';
      v_explicada := true;
    end if;

  elsif v_cmp_pay.id is not null and v_cmp_pay.status in ('pending', 'overdue', 'partially_paid')
        and v_cmp_pay.bank_transaction_id is null then
    -- 2. o CMP tem conta a pagar em aberto (anexada pela F2): casa — só no SIM do dono
    if p_casar then
      begin
        perform public.conciliar_lancamento('payable', c.payable_id, p_tx, p_autor);
        update public.finance_review_queue q
           set status = 'superseded', decision_note = 'Casada com a conta do ' || c.codigo, decided_at = now(), updated_at = now()
         where q.bank_transaction_id = p_tx and q.status = 'pending';
        v_como := 'casou';
        v_payable := c.payable_id;
        v_explicada := true;
      exception when others then
        get stacked diagnostics v_t = message_text;
        v_erro := left(v_t, 200);
      end;
    end if;

  else
    -- 3. a linha tem proposta pendente na fila do Extrato
    select q.id, q.kind, q.evidencia into v_prop from public.finance_review_queue q
     where q.bank_transaction_id = p_tx and q.status = 'pending'
     order by q.created_at desc, q.id
     limit 1;
    if v_prop.id is not null then
      v_proposta := v_prop.id;
      if v_prop.kind <> 'create_payable' then
        -- transferência, anomalia...: o dono decide no Extrato
        v_pend := 'classificar_no_extrato';
        v_explicada := true;
      elsif coalesce(v_prop.evidencia, '{}'::jsonb) ? 'anotacao' then
        if (v_prop.evidencia->'anotacao'->>'id')::uuid = any (v_anots) then
          v_como := 'classificou';
          v_anot := (v_prop.evidencia->'anotacao'->>'id')::uuid;
        else
          -- outra anotação (do dono, pela tela/assistente) já classificou: não passa por cima
          v_pend := 'classificar_no_extrato';
        end if;
        v_explicada := true;
      else
        -- a anotação da F2 que ainda espera, ou uma nova (documento nulo: a linha é a escolhida)
        select a.id into v_anot from public.anotacoes_do_extrato a
         where a.id = any (v_anots) and a.status = 'aguardando'
         order by a.criada_em limit 1;
        if v_anot is null then
          -- PESSOAL pago pela empresa (resposta 1): o favorecido é o sócio (o pró-labore desconta)
          insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, documento, fornecedor_id,
                                                   favorecido_id, categoria, os_id, descricao, criada_por)
          values ('debit', c.valor_confirmado, c.data_confirmada, true, null, public._comprovante_fornecedor_efetivo(c, null),
                  case when c.destino = 'pessoal' then nullif(v_ef->>'pagador_id', '')::uuid end, v_cat, v_os,
                  public._comprovante_descricao(c),
                  p_autor)
          returning id into v_anot;
          v_anot_criada := true;
        end if;
        perform public._aplicar_anotacao(v_anot, v_prop.id);
        v_aplicou := true;
        v_como := 'classificou';
        v_explicada := true;
      end if;
    end if;
    -- 4. sem proposta (cartão PENDING, ou o finance-review não rodou): a varredura tenta de novo
  end if;

  -- 5. a linha sem nome mostra a loja do CMP no Extrato (só se ainda não tem; nunca no conflito, que não liga)
  if v_erro is null and v_conflito is null and nullif(btrim(coalesce(t.counterparty_name, '')), '') is null
     and nullif(btrim(coalesce(t.merchant_name, '')), '') is null
     and public._nome_da_linha(t.counterparty_name, t.description) is null and t.nome_pelo_comprovante is null then
    update public.bank_transactions x
       set nome_pelo_comprovante = left(coalesce(v_forn, public._comprovante_tipo_no_texto(c.tipo)) || ' · ' || c.codigo, 160)
     where x.id = p_tx and x.nome_pelo_comprovante is null;
  end if;

  return jsonb_build_object(
    'tipo', 'ligar_linha', 'bank_transaction_id', p_tx, 'origem', null, 'nivel', null, 'em', now(),
    'como', v_como, 'proposta_id', v_proposta, 'anotacao_id', v_anot, 'anotacao_criada', v_anot_criada,
    'payable_id', v_payable, 'corrigido', v_corr, 'mensagens', to_jsonb(v_msgs),
    'linha', public._comprovante_linha_curta(p_tx), 'ligou_despesa', v_ligou_despesa,
    'lancado_depois', v_lancado_depois, 'categoria_existente', v_cat_existente,
    '_explicada', v_explicada, '_pendencia', v_pend, '_aviso', v_aviso, '_erro', v_erro, '_aplicou', v_aplicou,
    '_conflito', v_conflito);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. comprovante_completar (B): o que o dono disse em conversa, pelo assistente (tool
--    completar_comprovante → edge comprovantes-whatsapp, ação completar), numa transação só.
--    Entrada: a CorpoDoCompletar da edge, já conferida, com a categoria já traduzida pela palavra.
--    Malformada = 22023. Recusa antes de escrever = {"resultado": <motivo>, "codigo"?, "valor_lido"?}.
--    Depois, num bloco só: as correções pelo comprovante_comando (categoria, os, para, valor, data, forma,
--    obs; campo igual ao do CMP não vai) e as respostas aos passos sem comando pelo comprovante_responder
--    (no máximo 4 voltas, só a pergunta DESTE CMP, nunca o confirmar nem o mesma_compra). A primeira
--    recusa (ou corrida: gravado, cancelado, desligada…) desfaz o bloco inteiro — as correções e as
--    perguntas abertas/fechadas: a pergunta que estava aberta continua aberta — e devolve
--    "recusado" (ou o motivo da corrida) sem nada aplicado. "ok" devolve o que foi aplicado, os itens
--    (o que a edge mostra ao dono) e a última pergunta, que a edge manda. Nunca grava no financeiro.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_completar(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_dono record;
  c public.comprovantes;
  v_phone text;
  v_autor uuid;
  v_num integer;
  v_valor text;
  v_data date;
  v_os integer;
  v_destino text;
  v_tipo_na_os text;
  v_cat text;
  v_forma text;
  v_quem text;
  v_tecnico text;
  v_obs text;
  v_texto text;
  v_destino_antes text;
  v_campo text;
  v_payload jsonb;
  v_r jsonb;
  v_res text;
  v_chamou integer := 0;
  v_aplicados text[] := '{}';
  v_ja text[] := '{}';
  v_itens jsonb := '[]'::jsonb;
  v_pergunta jsonb;
  v_ocupado boolean := false;
  v_ocupado_por text;
  v_recusado jsonb;
  v_parou text;
  v_desconhecido text;
  v_passo text;
  v_interp jsonb;
  v_campo_resp text;
  v_respondidos text[] := '{}';
  v_volta integer := 0;
  v_nome text;
  v_pedidos text[];
  v_ignorados text[];
begin
  -- ── 1. a entrada (malformada = 22023, como as RPCs vizinhas; a edge já conferiu) ─────────────
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'comprovante_completar: a entrada precisa ser um objeto' using errcode = '22023';
  end if;
  v_phone := p->>'phone';
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_completar: telefone inválido' using errcode = '22023';
  end if;
  begin
    v_autor := (p->>'autor')::uuid;
    v_num := (p->>'cmp')::integer;
    v_os := nullif(p->>'os', '')::integer;
  exception when others then
    raise exception 'comprovante_completar: autor, número do CMP ou da OS malformado' using errcode = '22023';
  end;
  if v_autor is null or v_num is null or v_num not between 1 and 999999 then
    raise exception 'comprovante_completar: autor ou número do CMP malformado' using errcode = '22023';
  end if;
  if v_os is not null and v_os not between 1 and 999999 then
    raise exception 'comprovante_completar: número da OS fora da faixa' using errcode = '22023';
  end if;

  v_valor := nullif(p->>'valor', '');
  if v_valor is not null
     and (case when v_valor !~ '^[0-9]{1,10}\.[0-9]{2}$' then true
               else v_valor::numeric <= 0 or v_valor::numeric > 999999.99 end) then
    raise exception 'comprovante_completar: valor malformado' using errcode = '22023';
  end if;

  v_texto := nullif(p->>'data', '');
  if v_texto is not null then
    if v_texto !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'comprovante_completar: data ilegível' using errcode = '22023';
    end if;
    begin
      v_data := v_texto::date;
    exception when others then
      raise exception 'comprovante_completar: data ilegível' using errcode = '22023';
    end;
  end if;

  v_destino := nullif(p->>'destino', '');
  v_tipo_na_os := nullif(p->>'tipo_na_os', '');
  v_forma := nullif(p->>'forma', '');
  v_quem := nullif(p->>'quem_pagou', '');
  if (v_destino is not null and v_destino not in ('os', 'estoque', 'insumo', 'empresa', 'pessoal'))
     or (v_tipo_na_os is not null and v_tipo_na_os not in ('peca', 'despesa'))
     or (v_forma is not null and v_forma not in ('pix', 'debito', 'credito', 'dinheiro', 'boleto', 'transferencia'))
     or (v_quem is not null and v_quem not in ('empresa', 'socio', 'tecnico', 'cliente')) then
    raise exception 'comprovante_completar: valor fora da lista' using errcode = '22023';
  end if;
  -- a OS dita é o destino "os": outro destino junto não combina
  if v_os is not null then
    if v_destino is not null and v_destino <> 'os' then
      raise exception 'comprovante_completar: OS com outro destino' using errcode = '22023';
    end if;
    v_destino := 'os';
  end if;

  -- os textos: uma linha, espaços juntos (vazio = nulo)
  v_cat := nullif(btrim(regexp_replace(coalesce(p->>'categoria', ''), '[[:space:]]+', ' ', 'g')), '');
  v_tecnico := nullif(btrim(regexp_replace(coalesce(p->>'tecnico', ''), '[[:space:]]+', ' ', 'g')), '');
  v_obs := nullif(btrim(regexp_replace(coalesce(p->>'observacao', ''), '[[:space:]]+', ' ', 'g')), '');
  if char_length(v_cat) > 100 or char_length(v_tecnico) > 60 or char_length(v_obs) > 200 then
    raise exception 'comprovante_completar: texto longo demais' using errcode = '22023';
  end if;

  -- o que veio, na ordem (os "ignorados" saem daqui: uma fonte só)
  v_pedidos := array_remove(array[
    case when v_cat is not null then 'categoria' end,
    case when v_os is not null then 'os' end,
    case when v_destino in ('estoque', 'insumo', 'empresa', 'pessoal') then 'para' end,
    case when v_valor is not null then 'valor' end,
    case when v_data is not null then 'data' end,
    case when v_forma is not null then 'forma' end,
    case when v_obs is not null then 'obs' end,
    case when v_quem is not null then 'quem_pagou' end,
    case when v_tecnico is not null then 'tecnico' end,
    case when v_tipo_na_os is not null then 'tipo_na_os' end]::text[], null);

  -- ── 2. as recusas antes de escrever ────────────────────────────────────────────────────────
  if not public._comprovante_conversa_ligada() then
    return jsonb_build_object('resultado', 'desligada');
  end if;
  select d.id, d.phone into v_dono from public._comprovante_dono() d;
  if v_dono.id is distinct from v_autor or v_dono.phone is distinct from v_phone then
    return jsonb_build_object('resultado', 'nao_e_o_dono');
  end if;
  -- a trava do telefone e a linha do CMP ficam do lado de FORA do bloco: o bloco desfeito não as solta
  -- (as RPCs de dentro pegam a mesma trava de novo; a trava de transação é reentrante)
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  select * into c from public.comprovantes x where x.numero = v_num and x.phone_normalized = v_phone for update;
  if not found or c.modo is distinct from 'dono' then
    return jsonb_build_object('resultado', 'nao_existe');
  end if;
  -- cancelado antes de gravado: um CMP gravado e depois cancelado é "cancelado"
  if c.situacao = 'cancelado' then
    return jsonb_build_object('resultado', 'ja_cancelado', 'codigo', c.codigo);
  end if;
  if c.gravado_em is not null then
    return jsonb_build_object('resultado', 'ja_gravado', 'codigo', c.codigo);
  end if;
  -- ainda sendo lido (na_fila) ou fora da conversa: o reabrir, sem achar ESTE CMP, perguntaria o primeiro
  -- da fila — e o que o dono disse deste responderia o passo de outro
  if c.situacao not in ('lido', 'falhou', 'aguardando_vez', 'perguntando', 'aguardando_sim') then
    return jsonb_build_object('resultado', 'fora_da_conversa', 'codigo', c.codigo);
  end if;
  -- valor diferente do lido (e do já confirmado) exige o porquê: o do pedido ou o já guardado no CMP
  if v_valor is not null and c.valor is not null and abs(v_valor::numeric - c.valor) > 0.01
     and not (c.valor_confirmado is not null and abs(v_valor::numeric - c.valor_confirmado) <= 0.01)
     and v_obs is null and c.observacao is null then
    return jsonb_build_object('resultado', 'observacao_obrigatoria', 'codigo', c.codigo, 'valor_lido', c.valor::text);
  end if;
  if v_data is not null and v_data > (now() at time zone 'America/Sao_Paulo')::date then
    return jsonb_build_object('resultado', 'data_futura', 'codigo', c.codigo);
  end if;
  v_destino_antes := c.destino;

  -- ── 3. tudo ou nada ────────────────────────────────────────────────────────────────────────
  begin
    -- 3a. as correções pelo comando, na ordem fixa (campo igual ao do CMP não vai: nem versão nem
    --     pergunta à toa)
    foreach v_campo in array array['categoria', 'os', 'para', 'valor', 'data', 'forma', 'obs'] loop
      v_payload := null;
      case v_campo
        when 'categoria' then
          if v_cat is not null then
            if public._comprovante_normalizar(v_cat) = public._comprovante_normalizar(c.categoria) then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('categoria', v_cat);
            end if;
          end if;
        when 'os' then
          if v_os is not null then
            v_payload := jsonb_build_object('numero', v_os);
          end if;
        when 'para' then
          if v_destino in ('estoque', 'insumo', 'empresa', 'pessoal') then
            if v_destino = c.destino then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('destino', v_destino);
            end if;
          end if;
        when 'valor' then
          if v_valor is not null then
            if c.valor_confirmado is not null and abs(v_valor::numeric - c.valor_confirmado) <= 0.001 then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('valor', v_valor);
            end if;
          end if;
        when 'data' then
          if v_data is not null then
            if v_data = c.data_confirmada then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('data', to_char(v_data, 'YYYY-MM-DD'));
            end if;
          end if;
        when 'forma' then
          if v_forma is not null then
            if v_forma = c.forma_confirmada then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('forma', v_forma);
            end if;
          end if;
        when 'obs' then
          if v_obs is not null then
            if v_obs = c.observacao then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('observacao', v_obs);
            end if;
          end if;
      end case;
      continue when v_payload is null;
      v_chamou := v_chamou + 1;
      v_r := public.comprovante_comando(jsonb_build_object('phone', v_phone, 'message_id', null, 'comando', 'corrigir',
                                                           'cmp', v_num, 'campo', v_campo) || v_payload);
      v_res := v_r->>'resultado';
      if v_res = 'pergunta' then
        v_aplicados := array_append(v_aplicados, v_campo);
        v_itens := v_itens || jsonb_build_array(
          jsonb_build_object('campo', v_campo, 'valor', v_r->'corrigido'->>'valor')
          || case when v_campo = 'valor' then jsonb_build_object('lido', c.valor::text) else '{}'::jsonb end);
        -- a pergunta "não perguntou" vem como JSON null (não SQL null)
        v_pergunta := nullif(v_r->'pergunta', 'null'::jsonb);
        v_ocupado := v_pergunta is null and coalesce(v_r->>'motivo' = 'ocupado', false);
        v_ocupado_por := case when v_pergunta is null then v_r->'ocupado_por'->>'titulo' end;
      elsif v_res = 'invalida' then
        v_recusado := jsonb_build_object('campo', v_campo, 'motivo', v_r->>'motivo', 'passo', null);
        raise exception 'comprovante_completar: recusado' using errcode = 'MFC02';
      else
        -- ja_gravado, ja_cancelado, nao_existe, sem_cmp, desligada: só numa corrida com o próprio dono
        v_parou := coalesce(v_res, 'desconhecido');
        raise exception 'comprovante_completar: parou' using errcode = 'MFC02';
      end if;
    end loop;

    -- 3b. nenhuma correção (tudo igual, ou só passos sem comando): a pergunta do CMP, como o *cmp N* abre
    if v_chamou = 0 then
      v_r := public.comprovante_comando(jsonb_build_object('phone', v_phone, 'message_id', null, 'comando', 'cmp',
                                                           'numero', v_num));
      v_res := v_r->>'resultado';
      if v_res = 'pergunta' then
        v_pergunta := nullif(v_r->'pergunta', 'null'::jsonb);
        v_ocupado := v_pergunta is null and coalesce(v_r->>'motivo' = 'ocupado', false);
        v_ocupado_por := case when v_pergunta is null then v_r->'ocupado_por'->>'titulo' end;
      elsif v_res in ('nao_existe', 'desligada') then
        v_parou := v_res;
        raise exception 'comprovante_completar: parou' using errcode = 'MFC02';
      end if;
    end if;

    -- 3c. os passos sem comando: no máximo 4 voltas; só a pergunta DESTE CMP (o que o dono disse dele
    --     nunca responde o passo de outro); cada passo uma vez; nunca o confirmar nem o mesma_compra
    while v_volta < 4 loop
      v_volta := v_volta + 1;
      exit when v_pergunta is null or (v_pergunta->'cmp'->>'id') is distinct from c.id::text;
      v_passo := v_pergunta->>'passo';
      exit when v_passo = any (v_respondidos);
      v_interp := null;
      v_campo_resp := null;
      if v_passo = 'quem_pagou' and v_quem is not null then
        v_interp := jsonb_build_object('tipo', 'palavra', 'valor', v_quem);
        v_campo_resp := 'quem_pagou';
      elsif v_passo = 'qual_tecnico' and v_tecnico is not null then
        v_interp := jsonb_build_object('tipo', 'nome', 'texto', v_tecnico);
        v_campo_resp := 'tecnico';
      elsif v_passo = 'tipo_na_os' and v_tipo_na_os is not null then
        v_interp := jsonb_build_object('tipo', 'palavra', 'valor', v_tipo_na_os);
        v_campo_resp := 'tipo_na_os';
      elsif v_passo = 'como_pagou' and v_forma is not null then
        v_interp := jsonb_build_object('tipo', 'palavra', 'valor', v_forma);
        v_campo_resp := 'forma';
      elsif v_passo = 'qual_os' and v_os is not null then
        v_interp := jsonb_build_object('tipo', 'os', 'numero', v_os);
        v_campo_resp := 'os';
      end if;
      exit when v_interp is null;
      v_respondidos := array_append(v_respondidos, v_passo);
      v_r := public.comprovante_responder(jsonb_build_object('pergunta_id', v_pergunta->>'pergunta_id', 'message_id', null,
                                                             'interpretacao', v_interp, 'versao', null));
      v_res := v_r->>'resultado';
      if v_res in ('proximo', 'resumo') then
        if not (v_campo_resp = any (v_aplicados)) then
          v_aplicados := array_append(v_aplicados, v_campo_resp);
        end if;
        if v_passo = 'qual_tecnico' then
          -- o nome do técnico vai no item "quem pagou" (o que veio do pedido, ou um novo)
          v_nome := coalesce(v_r->'cmp'->>'pagador_nome', v_tecnico);
          if exists (select 1 from jsonb_array_elements(v_itens) i where i->>'campo' = 'quem_pagou') then
            select jsonb_agg(case when i->>'campo' = 'quem_pagou' then i || jsonb_build_object('nome', v_nome) else i end
                             order by o)
              into v_itens
              from jsonb_array_elements(v_itens) with ordinality as t(i, o);
          else
            v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'quem_pagou', 'valor', 'tecnico', 'nome', v_nome));
          end if;
        elsif v_passo = 'quem_pagou' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'quem_pagou', 'valor', v_quem));
        elsif v_passo = 'tipo_na_os' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'tipo_na_os', 'valor', v_tipo_na_os));
        elsif v_passo = 'como_pagou' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'forma', 'valor', v_forma));
        elsif v_passo = 'qual_os' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'os', 'valor',
                       coalesce(v_r->'cmp'->'os'->>'numero', 'OS-' || lpad(v_os::text, 5, '0'))));
        end if;
        v_pergunta := nullif(v_r->'proxima', 'null'::jsonb);
        v_ocupado := v_pergunta is null and coalesce(v_r->>'motivo' = 'ocupado', false);
        v_ocupado_por := case when v_pergunta is null then v_r->'ocupado_por'->>'titulo' end;
      elsif v_res = 'invalida' then
        v_recusado := jsonb_build_object('campo', v_campo_resp, 'motivo', v_r->>'motivo', 'passo', v_passo);
        raise exception 'comprovante_completar: recusado' using errcode = 'MFC02';
      elsif v_res = 'ignorada' then
        v_parou := case v_r->>'motivo' when 'cancelado' then 'ja_cancelado' when 'desligada' then 'desligada'
                                        else 'ja_gravado' end;
        raise exception 'comprovante_completar: parou' using errcode = 'MFC02';
      else
        -- resultado que o completar não conhece: para aqui (o que já foi feito fica)
        v_desconhecido := coalesce(v_res, 'nulo');
        exit;
      end if;
    end loop;
  exception when sqlstate 'MFC02' then
    -- o bloco foi desfeito inteiro (correções, perguntas abertas e fechadas): a pergunta de antes segue
    -- aberta. As variáveis guardam o que foi visto (só o banco volta).
    v_ignorados := array_remove(v_pedidos, v_recusado->>'campo');
    return jsonb_build_object('resultado', coalesce(v_parou, 'recusado'), 'id', c.id, 'codigo', c.codigo,
      'valor_lido', c.valor::text, 'aplicados', '[]'::jsonb, 'ja_estava', to_jsonb(v_ja),
      'ignorados', to_jsonb(v_ignorados), 'itens', '[]'::jsonb, 'recusado', v_recusado, 'pergunta', null,
      'ocupado', false, 'ocupado_por', null, 'desconhecido', null);
  end;

  -- ── 4. o que veio e não foi usado (o passo não chegou, ou parou antes) ──────────────────────
  select coalesce(array_agg(x order by o), '{}'::text[]) into v_ignorados
    from unnest(v_pedidos) with ordinality as t(x, o)
   where not (x = any (v_aplicados)) and not (x = any (v_ja));
  -- "foi para uma OS" sem dizer qual: o menu do "para quê" já lista as OS
  if v_destino = 'os' and v_os is null and v_destino_antes is distinct from 'os' then
    v_ignorados := array_append(v_ignorados, 'destino');
  end if;
  return jsonb_build_object('resultado', 'ok', 'id', c.id, 'codigo', c.codigo, 'valor_lido', c.valor::text,
    'aplicados', to_jsonb(v_aplicados), 'ja_estava', to_jsonb(v_ja), 'ignorados', to_jsonb(v_ignorados),
    'itens', v_itens, 'recusado', null, 'pergunta', v_pergunta, 'ocupado', v_ocupado,
    'ocupado_por', v_ocupado_por, 'desconhecido', v_desconhecido);
end $$;

comment on function public.comprovante_completar(jsonb) is
  'B (12/10/2026): o que o dono disse em conversa, pelo assistente (ação completar da edge), numa transação só: '
  'recusas antes de escrever; depois comprovante_comando (categoria, os, para, valor, data, forma, obs) e '
  'comprovante_responder (passos sem comando, message_id nulo) num bloco que desfaz tudo na primeira recusa '
  '(MFC02). Devolve a última pergunta para a edge mandar. Nunca grava no financeiro.';

-- ---------------------------------------------------------------------------------------------
-- 10. Privilégios (revogar POR ASSINATURA; helpers sem grant para ninguém; RPCs só service_role; a
--     leitura do assistente também authenticated, como em 20261011202000)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovante_obs_sem_cpf(text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_descricao(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_resumo(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_gravar(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function public.comprovante_comando(jsonb) from public, anon, authenticated;
revoke all on function public.comprovante_completar(jsonb) from public, anon, authenticated;
revoke all on function public.comprovantes_indice_do_mes(date) from public, anon, authenticated;
revoke all on function public.comprovantes_indice_pessoal_do_mes(date) from public, anon, authenticated;
revoke all on function public.comprovantes_consultar(jsonb) from public, anon, authenticated;
grant execute on function public.comprovante_comando(jsonb) to service_role;
grant execute on function public.comprovante_completar(jsonb) to service_role;
grant execute on function public.comprovantes_indice_do_mes(date) to service_role;
grant execute on function public.comprovantes_indice_pessoal_do_mes(date) to service_role;
-- a leitura do assistente: o painel (authenticated) e o WhatsApp (service_role); o cargo é conferido dentro
grant execute on function public.comprovantes_consultar(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 11. Prova: portas fechadas, a descrição num lugar só, o "obs" no corrigir, o completar sobre as RPCs
--     do menu e a coluna com o limite.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_rpcs text[] := array[
    'public.comprovante_comando(jsonb)',
    'public.comprovante_completar(jsonb)',
    'public.comprovantes_indice_do_mes(date)',
    'public.comprovantes_indice_pessoal_do_mes(date)'];
  v_leituras text[] := array[
    'public.comprovantes_consultar(jsonb)'];
  v_helpers text[] := array[
    'public._comprovante_obs_sem_cpf(text)',
    'public._comprovante_descricao(public.comprovantes)',
    'public._comprovante_resumo(public.comprovantes)',
    'public._comprovante_gravar(uuid, uuid, text)',
    'public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean)'];
  v_def text;
begin
  foreach v_f in array v_rpcs || v_leituras || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'função dos comprovantes exposta para anon: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função dos comprovantes exposta para authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs || v_leituras loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_leituras loop
    if not has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'o painel (authenticated) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_helpers loop
    if has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper interno dos comprovantes alcançável pela service_role: %', v_f;
    end if;
  end loop;

  -- a descrição do lançamento nasce num lugar só
  v_def := pg_get_functiondef('public._comprovante_gravar(uuid, uuid, text)'::regprocedure);
  if position('_comprovante_descricao' in v_def) = 0 then
    raise exception '_comprovante_gravar não usa _comprovante_descricao';
  end if;
  -- e a gravação continua conhecendo os efeitos da F3 (a prova de 20261011303000)
  if position('''ligar_linha''' in v_def) = 0 or position('''aguardar_banco''' in v_def) = 0
     or position('''reembolso_tecnico''' in v_def) = 0 or position('''anexar_peca''' in v_def) = 0
     or position('''comprovar_na_os''' in v_def) = 0 then
    raise exception 'a gravação não conhece ligar_linha/aguardar_banco/reembolso_tecnico/anexar_peca/comprovar_na_os';
  end if;
  if position('_comprovante_descricao' in
              pg_get_functiondef('public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean)'::regprocedure)) = 0 then
    raise exception '_comprovante_linha_explicar não usa _comprovante_descricao';
  end if;
  -- a observação sai pelo helper que tira o CPF também colado em pontuação (revisão de 12/10/2026)
  if position('_comprovante_obs_sem_cpf' in pg_get_functiondef('public._comprovante_descricao(public.comprovantes)'::regprocedure)) = 0
     or position('_comprovante_obs_sem_cpf' in pg_get_functiondef('public._comprovante_resumo(public.comprovantes)'::regprocedure)) = 0
     or position('_comprovante_obs_sem_cpf' in pg_get_functiondef('public.comprovantes_consultar(jsonb)'::regprocedure)) = 0
     or position('_comprovante_obs_sem_cpf' in pg_get_functiondef('public.comprovantes_indice_do_mes(date)'::regprocedure)) = 0
     or position('_comprovante_obs_sem_cpf' in pg_get_functiondef('public.comprovantes_indice_pessoal_do_mes(date)'::regprocedure)) = 0
     or position('_comprovante_obs_sem_cpf' in pg_get_functiondef('public.comprovante_comando(jsonb)'::regprocedure)) = 0 then
    raise exception 'uma saída da observação não passa por _comprovante_obs_sem_cpf';
  end if;
  if position('''obs''' in pg_get_functiondef('public.comprovante_comando(jsonb)'::regprocedure)) = 0 then
    raise exception 'o corrigir do comprovante_comando não conhece o campo obs';
  end if;
  v_def := pg_get_functiondef('public.comprovante_completar(jsonb)'::regprocedure);
  if position('comprovante_comando' in v_def) = 0 or position('comprovante_responder' in v_def) = 0
     or position('MFC02' in v_def) = 0 then
    raise exception 'comprovante_completar não passa pelas RPCs do menu num bloco só (MFC02)';
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.comprovantes'::regclass and conname = 'comprovantes_observacao_curta') then
    raise exception 'comprovantes.observacao sem o limite (comprovantes_observacao_curta)';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261012100000', 'comprovante_observacao_e_completar')
on conflict do nothing;
