-- Secretário, Passo 5 (16/10/2026): a papelada do escritório em LOTE SEMANAL, aprovado com um "sim" — e a chave
-- papelada_lote. Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-papelada.md
--
-- O lote é montado pela edge ai-daily-briefing no fechamento do último dia útil da semana (sexta 17:30) com o que
-- tem motivo medido para o "sim" (o que o dono anotou, regra dele, categoria que ele nunca troca, transferência para
-- a própria HBR, avisos só para saber), deixando de fora o que conflita (já lançado, sinal já lançado, vínculo, aviso
-- junto) e o que só ele sabe. Esta migration só guarda e confere — quem aprova continua sendo o MESMO caminho de
-- hoje (a tool aprovar_propostas_de_lancamento → finance-review approve), chamado pela tool aprovar_lote_da_papelada
-- depois do "sim <PIN>" do dono:
--   * papelada_lote: um lote por dia e telefone (os itens com a impressão de cada um, o que ficou de fora e por quê,
--     a linha da mensagem, o que foi escolhido no "sim" e o resultado item por item);
--   * papelada_lote_registrar: grava o lote do dia UMA vez (rodar de novo devolve o gravado); o lote pronto anterior
--     vira "substituido";
--   * papelada_lote_conferir: confere cada item escolhido contra a fila AGORA (ainda pendente, mesma impressão, sem
--     lançamento nem aviso novo na linha do banco). Com aplicar=true trava o lote (pronto → aplicando), tudo ou nada;
--     na SOMBRA recusa (e o CHECK também);
--   * papelada_lote_resultado: lê a fila item por item (entrou / falhou / incompleto / saiu / fora) e fecha o lote.
--
-- GRAVA DADO — OK NOMEADO: uma chave em app_settings ('papelada_lote' = 'desligado', bloco 5). Nasce desligada: nada
-- muda até o dono trocar para 'sombra'. Recria o gatilho _app_settings_chaves_do_dono com a chave nova (só o admin
-- muda). O corpo de antes foi conferido em produção em 16/10/2026 (06:45): md5 do prosrc normalizado (só A–Z em
-- minúscula, sem espaços) = e59e8bdee68ab39b9f77422ae0b378e7, igual ao de 20261016101000_avisos_do_dono.sql — e a
-- migration confere de novo ANTES de criar qualquer coisa (bloco 0). Nenhum cron, nenhuma mensagem. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 0. A guarda do gatilho das chaves, ANTES de qualquer criação (para parar sem deixar nada pela metade).
-- ---------------------------------------------------------------------------------------------
-- O gatilho tem de ser o do portão (20261016101000_avisos_do_dono, md5 e59e8bdee68ab39b9f77422ae0b378e7, o de
-- produção em 16/10/2026) ou já este (2ª aplicação). Qualquer outro PARA a migration sem apagar nada.
do $$
declare
  v_md5 text;
begin
  select md5(regexp_replace(translate(p.prosrc, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\s+', '', 'g'))
    into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_app_settings_chaves_do_dono';
  if v_md5 is null or v_md5 not in ('e59e8bdee68ab39b9f77422ae0b378e7', 'da6d81d0a1afe693948af101f9f48c35') then
    raise exception 'o gatilho _app_settings_chaves_do_dono não é o do portão (md5 %): aplique antes 20261016101000_avisos_do_dono ou confira o corpo em produção antes de recriar', coalesce(v_md5, 'ausente');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. papelada_lote: um por dia e telefone
-- ---------------------------------------------------------------------------------------------
create table if not exists public.papelada_lote (
  id                uuid primary key default gen_random_uuid(),
  -- o dia de Brasília em que o lote foi montado (a sexta)
  dia               date not null,
  phone_normalized  text not null,
  app_user_id       uuid references public.app_users(id) on delete set null,
  -- sombra = guardado para comparar, nunca aplicado; ligado = o dono viu a linha e pode aprovar
  formato           text not null,
  status            text not null default 'pronto',
  -- [{n, id, grupo, titulo, valor, categoria, codigo, motivo, impressao:{kind, valor, categoria, data, regra, vinculo}}]
  itens             jsonb not null default '[]'::jsonb,
  -- [{id, grupo, titulo, valor, codigo, motivo}]: o que ficou fora e por quê
  excecoes          jsonb not null default '[]'::jsonb,
  contagens         jsonb not null default '{}'::jsonb,
  -- a soma das despesas do lote (transferência e aviso não são gasto)
  total             numeric(14, 2) not null default 0,
  linha             text,
  valido_ate        timestamptz not null,
  -- o "sim": os ids que a conferência deixou passar, quem aprovou, a pendência do assistente
  escolhidos        jsonb,
  pendencia_id      uuid,
  aplicado_por      uuid references public.app_users(id) on delete set null,
  aplicacao_inicio  timestamptz,
  aplicado_em       timestamptz,
  -- {itens:[{id, n, situacao, motivo, payable_id?, receivable_id?}], entrou, falhou, fora, valor_entrou}
  resultado         jsonb,
  criado_em         timestamptz not null default now(),
  constraint papelada_lote_um_por_dia unique (dia, phone_normalized),
  constraint papelada_lote_formato check (formato in ('sombra', 'ligado')),
  constraint papelada_lote_status check (status in ('pronto', 'aplicando', 'aplicado', 'substituido', 'vencido')),
  -- a SOMBRA nunca é aplicada
  constraint papelada_lote_aplicar_so_ligado check (status not in ('aplicando', 'aplicado') or formato = 'ligado'),
  constraint papelada_lote_aplicado_em check ((status = 'aplicado') = (aplicado_em is not null)),
  constraint papelada_lote_quem_aplicou check (status not in ('aplicando', 'aplicado')
    or (escolhidos is not null and aplicado_por is not null and aplicacao_inicio is not null)),
  constraint papelada_lote_itens check (jsonb_typeof(itens) = 'array' and pg_column_size(itens) <= 65536),
  constraint papelada_lote_excecoes check (jsonb_typeof(excecoes) = 'array' and pg_column_size(excecoes) <= 65536),
  constraint papelada_lote_contagens check (jsonb_typeof(contagens) = 'object' and pg_column_size(contagens) <= 16384),
  constraint papelada_lote_escolhidos check (escolhidos is null or jsonb_typeof(escolhidos) = 'array'),
  constraint papelada_lote_resultado check (resultado is null or (jsonb_typeof(resultado) = 'object' and pg_column_size(resultado) <= 65536)),
  constraint papelada_lote_linha check (linha is null or char_length(linha) <= 400),
  constraint papelada_lote_total check (total >= 0)
);

comment on table public.papelada_lote is
  'Secretário (Passo 5, 16/10/2026): o lote semanal da papelada do escritório — o que está pronto para um "sim" só (com o motivo medido e a impressão de cada item), o que ficou de fora e por quê, e o resultado item por item quando o dono aprova. Sombra = guardado, nunca aplicado. Só o admin lê; escrita só pelas RPCs papelada_lote_* (service_role).';
comment on column public.papelada_lote.itens is 'Itens do lote, numerados como o dono os vê (*lote*). impressao = tipo, valor, categoria, data, regra e vínculo na montagem: no "sim", item com impressão diferente sai (ele aprovaria algo que não viu).';

create index if not exists papelada_lote_pronto
  on public.papelada_lote (phone_normalized, dia desc) where status in ('pronto', 'aplicando');

-- ---------------------------------------------------------------------------------------------
-- 2. RLS e privilégios (revogar de anon/authenticated POR NOME)
-- ---------------------------------------------------------------------------------------------
alter table public.papelada_lote enable row level security;

revoke all on table public.papelada_lote from public, anon, authenticated;
grant select on table public.papelada_lote to authenticated;
grant all on table public.papelada_lote to service_role;
drop policy if exists papelada_lote_admin_le on public.papelada_lote;
create policy papelada_lote_admin_le on public.papelada_lote
  for select to authenticated using (public.is_admin((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 3. papelada_lote_registrar: o lote do dia, uma vez só
-- ---------------------------------------------------------------------------------------------
create or replace function public.papelada_lote_registrar(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_dia      date;
  v_phone    text := nullif(p->>'phone', '');
  v_formato  text := p->>'formato';
  v_itens    jsonb := p->'itens';
  v_exc      jsonb := coalesce(p->'excecoes', '[]'::jsonb);
  v_valido   timestamptz;
  v_id       uuid;
  v_feito    record;
  v_item     jsonb;
  v_ids      text[] := array[]::text[];
begin
  begin
    v_dia := (p->>'dia')::date;
    v_valido := coalesce((p->>'valido_ate')::timestamptz, now() + interval '7 days');
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'dia ou valido_ate inválido');
  end;
  if v_dia is null or v_phone is null or v_formato is null or v_formato not in ('sombra', 'ligado') then
    return jsonb_build_object('ok', false, 'erro', 'faltam dia, phone ou formato (sombra|ligado)');
  end if;
  if v_itens is null or jsonb_typeof(v_itens) <> 'array' or jsonb_typeof(v_exc) <> 'array' then
    return jsonb_build_object('ok', false, 'erro', 'itens e excecoes têm de ser listas');
  end if;
  for v_item in select * from jsonb_array_elements(v_itens) loop
    -- coalesce em tudo: chave ausente dá nulo, e "nulo <> 'object'" não é verdade (o item passaria)
    if coalesce(jsonb_typeof(v_item), '') <> 'object'
       or coalesce(v_item->>'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(v_item->>'grupo', '') not in ('despesa', 'transferencia', 'aviso')
       or coalesce(jsonb_typeof(v_item->'n'), '') <> 'number'
       or coalesce(jsonb_typeof(v_item->'impressao'), '') <> 'object' then
      return jsonb_build_object('ok', false, 'erro', 'item do lote sem id, n, grupo ou impressão');
    end if;
    if (v_item->>'id') = any(v_ids) then
      return jsonb_build_object('ok', false, 'erro', 'item repetido no lote');
    end if;
    v_ids := v_ids || (v_item->>'id');
  end loop;

  -- já montado hoje (dois disparos da tarde): devolve o gravado
  select l.id, l.status, l.formato into v_feito
    from public.papelada_lote l where l.dia = v_dia and l.phone_normalized = v_phone;
  if found then
    return jsonb_build_object('ok', true, 'novo', false, 'id', v_feito.id, 'status', v_feito.status, 'formato', v_feito.formato);
  end if;

  begin
    insert into public.papelada_lote (dia, phone_normalized, app_user_id, formato, itens, excecoes, contagens, total, linha, valido_ate)
    values (v_dia, v_phone, nullif(p->>'app_user_id', '')::uuid, v_formato, v_itens, v_exc,
            coalesce(p->'contagens', '{}'::jsonb), greatest(coalesce((p->>'total')::numeric, 0), 0),
            left(p->>'linha', 400), v_valido)
    returning id into v_id;
  exception when unique_violation then
    select l.id, l.status, l.formato into v_feito
      from public.papelada_lote l where l.dia = v_dia and l.phone_normalized = v_phone;
    return jsonb_build_object('ok', true, 'novo', false, 'id', v_feito.id, 'status', v_feito.status, 'formato', v_feito.formato);
  end;

  -- vale só o lote mais novo: o pronto anterior do mesmo telefone sai de cena (nunca o que está aplicando)
  update public.papelada_lote set status = 'substituido'
   where phone_normalized = v_phone and status = 'pronto' and id <> v_id and dia < v_dia;

  return jsonb_build_object('ok', true, 'novo', true, 'id', v_id, 'status', 'pronto', 'formato', v_formato);
end $$;

comment on function public.papelada_lote_registrar(jsonb) is
  'Secretário (Passo 5): grava o lote semanal da papelada uma vez só (rodar de novo devolve o gravado); o lote pronto anterior do mesmo telefone vira substituido. Só service_role.';

-- ---------------------------------------------------------------------------------------------
-- 4. papelada_lote_conferir e papelada_lote_resultado: o "sim" (só com formato ligado)
-- ---------------------------------------------------------------------------------------------
create or replace function public.papelada_lote_conferir(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_lote     public.papelada_lote%rowtype;
  v_aplicar  boolean := coalesce((p->>'aplicar')::boolean, false);
  v_user     uuid;
  v_ids      text[];
  v_item     jsonb;
  v_imp      jsonb;
  v_q        record;
  v_validos  jsonb := '[]'::jsonb;
  v_fora     jsonb := '[]'::jsonb;
  v_codigo   text;
begin
  begin
    v_user := nullif(p->>'app_user_id', '')::uuid;
    if p ? 'ids' and jsonb_typeof(p->'ids') <> 'null' then
      -- lista vazia NÃO é "todos" (array_agg de nada dá nulo): é nada escolhido
      if jsonb_typeof(p->'ids') <> 'array' or jsonb_array_length(p->'ids') = 0 then
        return jsonb_build_object('ok', false, 'erro', 'nada_escolhido');
      end if;
      select array_agg(x) into v_ids from jsonb_array_elements_text(p->'ids') x;
    end if;
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'parametros_invalidos');
  end;

  if v_aplicar then
    select * into v_lote from public.papelada_lote where id = nullif(p->>'lote_id', '')::uuid for update;
  else
    select * into v_lote from public.papelada_lote where id = nullif(p->>'lote_id', '')::uuid;
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'sem_lote');
  end if;
  if v_lote.status <> 'pronto' then
    return jsonb_build_object('ok', false, 'erro', 'lote_' || v_lote.status);
  end if;
  if v_lote.valido_ate < now() then
    if v_aplicar then
      update public.papelada_lote set status = 'vencido' where id = v_lote.id;
    end if;
    return jsonb_build_object('ok', false, 'erro', 'lote_vencido');
  end if;
  if v_aplicar and v_lote.formato <> 'ligado' then
    return jsonb_build_object('ok', false, 'erro', 'sombra');
  end if;
  if v_aplicar and (v_user is null or not public.is_admin(v_user)) then
    return jsonb_build_object('ok', false, 'erro', 'so_admin');
  end if;
  -- escolhido fora do lote: nada é conferido nem gravado (tudo ou nada)
  if v_ids is not null and exists (
       select 1 from unnest(v_ids) x
        where not exists (select 1 from jsonb_array_elements(v_lote.itens) i where i->>'id' = x)) then
    return jsonb_build_object('ok', false, 'erro', 'item_fora_do_lote');
  end if;

  for v_item in select i from jsonb_array_elements(v_lote.itens) i
                 where v_ids is null or i->>'id' = any(v_ids)
                 order by (i->>'n')::int loop
    v_imp := v_item->'impressao';
    v_codigo := null;
    select q.id, q.kind, q.status, q.suggested_amount, q.suggested_category, q.suggested_date, q.applied_rule_id,
           q.vinculo_sugerido, q.bank_transaction_id
      into v_q
      from public.finance_review_queue q where q.id = (v_item->>'id')::uuid;
    if not found then
      v_codigo := 'sumiu';
    elsif v_q.status <> 'pending' then
      v_codigo := 'ja_decidido_' || v_q.status;
    elsif v_q.kind is distinct from v_imp->>'kind'
       or round(coalesce(v_q.suggested_amount, 0), 2) <> round(coalesce((v_imp->>'valor')::numeric, 0), 2)
       or v_q.suggested_category is distinct from (v_imp->>'categoria')
       or v_q.suggested_date::text is distinct from (v_imp->>'data')
       or v_q.applied_rule_id::text is distinct from (v_imp->>'regra')
       or (v_q.vinculo_sugerido is not null) <> coalesce((v_imp->>'vinculo')::boolean, false) then
      v_codigo := 'mudou';
    elsif v_q.kind in ('create_payable', 'create_receivable', 'internal_transfer') and v_q.bank_transaction_id is not null
          and (exists (select 1 from public.payables pa where pa.bank_transaction_id = v_q.bank_transaction_id and pa.status <> 'cancelled')
               or exists (select 1 from public.receivables r where r.bank_transaction_id = v_q.bank_transaction_id and r.status <> 'cancelled')) then
      v_codigo := 'ja_lancado';
    elsif v_q.kind = 'create_payable' and v_q.bank_transaction_id is not null
          and exists (select 1 from public.finance_review_queue a
                       where a.kind = 'anomaly' and a.status = 'pending' and a.related_transaction_id = v_q.bank_transaction_id) then
      v_codigo := 'aviso_novo';
    end if;
    if v_codigo is null then
      v_validos := v_validos || to_jsonb(v_item->>'id');
    else
      v_fora := v_fora || jsonb_build_object('id', v_item->>'id', 'n', (v_item->>'n')::int, 'codigo', v_codigo);
    end if;
  end loop;

  if v_aplicar then
    if jsonb_array_length(v_validos) = 0 then
      return jsonb_build_object('ok', false, 'erro', 'nada_valido', 'validos', v_validos, 'fora', v_fora);
    end if;
    update public.papelada_lote
       set status = 'aplicando', escolhidos = v_validos, aplicado_por = v_user, aplicacao_inicio = now(),
           pendencia_id = nullif(p->>'pendencia_id', '')::uuid,
           resultado = jsonb_build_object('fora_na_conferencia', v_fora)
     where id = v_lote.id;
  end if;
  return jsonb_build_object('ok', true, 'lote_id', v_lote.id, 'formato', v_lote.formato, 'validos', v_validos, 'fora', v_fora,
                            'aplicando', v_aplicar);
end $$;

comment on function public.papelada_lote_conferir(jsonb) is
  'Secretário (Passo 5): confere os itens escolhidos do lote contra a fila AGORA (pendente, mesma impressão, sem lançamento nem aviso novo na linha). aplicar=true: só formato ligado e admin, trava o lote (pronto → aplicando), tudo ou nada. Só service_role.';

create or replace function public.papelada_lote_resultado(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_lote      public.papelada_lote%rowtype;
  v_resp      jsonb := coalesce(p->'resposta', '{}'::jsonb);
  v_id        text;
  v_n         int;
  v_q         record;
  v_sit       text;
  v_motivo    text;
  v_itens     jsonb := '[]'::jsonb;
  v_entrou    int := 0;
  v_falhou    int := 0;
  v_fora      int := 0;
  v_valor     numeric := 0;
  v_f         jsonb;
  v_res       jsonb;
begin
  select * into v_lote from public.papelada_lote where id = nullif(p->>'lote_id', '')::uuid for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'sem_lote');
  end if;
  if v_lote.status = 'aplicado' then
    return jsonb_build_object('ok', true, 'ja', true) || coalesce(v_lote.resultado, '{}'::jsonb);
  end if;
  if v_lote.status <> 'aplicando' then
    return jsonb_build_object('ok', false, 'erro', 'lote_' || v_lote.status);
  end if;

  for v_id in select x from jsonb_array_elements_text(v_lote.escolhidos) x loop
    select (i->>'n')::int into v_n from jsonb_array_elements(v_lote.itens) i where i->>'id' = v_id;
    select q.status, q.kind, q.title, q.suggested_amount, q.bank_transaction_id, q.created_payable_id, q.created_receivable_id
      into v_q from public.finance_review_queue q where q.id = v_id::uuid;
    v_motivo := null;
    if not found then
      v_sit := 'falhou'; v_motivo := 'a proposta sumiu da fila';
    elsif v_q.status = 'approved' then
      v_sit := 'entrou';
      if v_q.kind = 'create_payable' then v_valor := v_valor + coalesce(v_q.suggested_amount, 0); end if;
    elsif v_q.status = 'superseded' then
      v_sit := 'saiu'; v_motivo := 'já estava lançada por outro caminho: saiu da fila';
    elsif v_q.status = 'rejected' then
      v_sit := 'falhou'; v_motivo := 'recusada no meio do caminho';
    elsif v_q.bank_transaction_id is not null
          and (exists (select 1 from public.payables pa where pa.bank_transaction_id = v_q.bank_transaction_id and pa.status <> 'cancelled')
               or exists (select 1 from public.receivables r where r.bank_transaction_id = v_q.bank_transaction_id and r.status <> 'cancelled')) then
      -- o approve não é transacional: o lançamento nasceu e a proposta não fechou
      v_sit := 'incompleto'; v_motivo := 'o lançamento foi criado, mas a linha não saiu da fila: confira no Extrato';
    else
      v_sit := 'falhou';
      -- o porquê que o servidor devolveu ("<título>: <motivo>"), quando houver
      select substr(f, char_length(v_q.title) + 3) into v_motivo
        from jsonb_array_elements_text(coalesce(v_resp->'falhas', '[]'::jsonb)) f
       where left(f, char_length(v_q.title) + 2) = v_q.title || ': ' limit 1;
      if v_motivo is null then
        v_motivo := case
          when exists (select 1 from jsonb_array_elements_text(coalesce(v_resp->'acima_do_limite', '[]'::jsonb)) f where f like left(v_q.title, 60) || '%')
            then 'acima do limite de lote'
          when exists (select 1 from jsonb_array_elements_text(coalesce(v_resp->'sem_resposta_de_os', '[]'::jsonb)) f where f = left(v_q.title, 60))
            then 'tem OS ou OC para responder'
          when exists (select 1 from jsonb_array_elements_text(coalesce(v_resp->'sem_destino', '[]'::jsonb)) f where f = left(v_q.title, 60))
            then 'serviço de terceiro: falta para onde foi'
          when exists (select 1 from jsonb_array_elements_text(coalesce(v_resp->'sem_receita', '[]'::jsonb)) f where f = left(v_q.title, 60))
            then 'entrada sem receita: é uma por uma'
          when v_resp ? 'error' then left(v_resp->>'error', 200)
          else 'não entrou'
        end;
      end if;
    end if;
    if v_sit = 'entrou' then v_entrou := v_entrou + 1; else v_falhou := v_falhou + 1; end if;
    v_itens := v_itens || jsonb_strip_nulls(jsonb_build_object(
      'id', v_id, 'n', v_n, 'situacao', v_sit, 'motivo', left(v_motivo, 200),
      'payable_id', v_q.created_payable_id, 'receivable_id', v_q.created_receivable_id));
  end loop;

  -- o que saiu na conferência (a impressão mudou, já decidido…) também vai para o relatório
  for v_f in select f from jsonb_array_elements(coalesce(v_lote.resultado->'fora_na_conferencia', '[]'::jsonb)) f loop
    v_fora := v_fora + 1;
    v_itens := v_itens || jsonb_build_object('id', v_f->>'id', 'n', (v_f->>'n')::int, 'situacao', 'fora', 'motivo', v_f->>'codigo');
  end loop;

  v_res := jsonb_build_object('itens', v_itens, 'entrou', v_entrou, 'falhou', v_falhou, 'fora', v_fora,
                              'valor_entrou', round(v_valor, 2));
  update public.papelada_lote set status = 'aplicado', aplicado_em = now(), resultado = v_res where id = v_lote.id;
  return jsonb_build_object('ok', true, 'ja', false) || v_res;
end $$;

comment on function public.papelada_lote_resultado(jsonb) is
  'Secretário (Passo 5): depois do approve de sempre, lê a fila item por item (entrou | falhou | incompleto | saiu | fora) e fecha o lote (aplicando → aplicado). Rodar de novo devolve o gravado. Só service_role.';

revoke all on function public.papelada_lote_registrar(jsonb) from public, anon, authenticated;
revoke all on function public.papelada_lote_conferir(jsonb) from public, anon, authenticated;
revoke all on function public.papelada_lote_resultado(jsonb) from public, anon, authenticated;
grant execute on function public.papelada_lote_registrar(jsonb) to service_role;
grant execute on function public.papelada_lote_conferir(jsonb) to service_role;
grant execute on function public.papelada_lote_resultado(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 5. GRAVA DADO — OK NOMEADO: a chave do lote da papelada. Nasce 'desligado'.
--    Três fontes do mesmo padrão: esta linha, o 'desligado' de _shared/papelada/texto.ts (lerFormatoDaPapelada:
--    chave ausente ou inválida = desligado) e a ausência da chave.
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('papelada_lote', 'desligado',
   'Lote semanal da papelada do escritório (secretário, Passo 5): desligado = nada; sombra = monta e GUARDA o lote na sexta (papelada_lote), mostra a linha só no texto guardado do fechamento, nunca aplica; ligado = a linha sai no fechamento da sexta e *lote* + "sim <PIN>" aprova pelo mesmo caminho da tela. Voltar atrás = desligado.')
on conflict (key) do nothing;

-- Igual ao do portão (20261016101000_avisos_do_dono), com a chave papelada_lote no fim.
create or replace function public._app_settings_chaves_do_dono()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and not public.is_admin(v_uid) then
    if (tg_op <> 'INSERT' and old.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo'))
       or (tg_op <> 'DELETE' and new.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo')) then
      raise exception 'Só o administrador muda o salário mínimo e a regra do pró-labore.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_fluxo')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_fluxo') then
      raise exception 'Só o administrador liga ou desliga o fluxo de comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_conversa')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_conversa') then
      raise exception 'Só o administrador liga ou desliga a conversa dos comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'resumo_formato')
       or (tg_op <> 'DELETE' and new.key = 'resumo_formato') then
      raise exception 'Só o administrador muda o formato do resumo da manhã.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'fechamento_formato')
       or (tg_op <> 'DELETE' and new.key = 'fechamento_formato') then
      raise exception 'Só o administrador liga ou desliga o fechamento da tarde.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key in ('voz_unica', 'voz_unica_regras'))
       or (tg_op <> 'DELETE' and new.key in ('voz_unica', 'voz_unica_regras')) then
      raise exception 'Só o administrador liga a voz única do secretário ou muda as regras dela.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'acompanhar_freio')
       or (tg_op <> 'DELETE' and new.key = 'acompanhar_freio') then
      raise exception 'Só o administrador liga ou desliga o freio do acompanhamento.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'papelada_lote')
       or (tg_op <> 'DELETE' and new.key = 'papelada_lote') then
      raise exception 'Só o administrador liga ou desliga o lote semanal da papelada.' using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists app_settings_chaves_do_dono on public.app_settings;
create trigger app_settings_chaves_do_dono
  before insert or update or delete on public.app_settings
  for each row execute function public._app_settings_chaves_do_dono();

revoke all on function public._app_settings_chaves_do_dono() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_t text := 'public.papelada_lote';
  v_f text;
  v_rpcs text[] := array['public.papelada_lote_registrar(jsonb)', 'public.papelada_lote_conferir(jsonb)',
                         'public.papelada_lote_resultado(jsonb)'];
  v_def text;
begin
  if not (select relrowsecurity from pg_class where oid = v_t::regclass) then
    raise exception 'RLS desligada em %', v_t;
  end if;
  if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert')
     or has_table_privilege('anon', v_t, 'update') or has_table_privilege('anon', v_t, 'delete') then
    raise exception 'anon ainda alcança %', v_t;
  end if;
  if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
     or has_table_privilege('authenticated', v_t, 'delete') then
    raise exception 'authenticated escreve direto em %', v_t;
  end if;
  if not has_table_privilege('service_role', v_t, 'select') or not has_table_privilege('service_role', v_t, 'insert')
     or not has_table_privilege('service_role', v_t, 'update') then
    raise exception 'service_role não alcança %', v_t;
  end if;
  -- policies: só a prevista, só TO authenticated, só SELECT, só admin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'papelada_lote') <> 1
     or exists (select 1 from pg_policies
                 where schemaname = 'public' and tablename = 'papelada_lote'
                   and (roles <> array['authenticated']::name[] or cmd <> 'SELECT'
                        or policyname <> 'papelada_lote_admin_le' or position('is_admin' in qual) = 0)) then
    raise exception 'policies de papelada_lote diferentes das previstas (ou alcançando anon/public)';
  end if;
  foreach v_f in array v_rpcs loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'função do lote exposta para anon: %', v_f;
    end if;
    if has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função do lote exposta para authenticated: %', v_f;
    end if;
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'papelada_lote_aplicar_so_ligado'
                    and conrelid = 'public.papelada_lote'::regclass and contype = 'c') then
    raise exception 'o CHECK que segura a sombra (aplicar só ligado) está ausente';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'papelada_lote_um_por_dia'
                    and conrelid = 'public.papelada_lote'::regclass and contype = 'u') then
    raise exception 'a chave única (dia, telefone) do lote está ausente';
  end if;
  if not exists (select 1 from public.app_settings where key = 'papelada_lote') then
    raise exception 'a chave papelada_lote não foi criada';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'app_settings_chaves_do_dono'
                    and tgrelid = 'public.app_settings'::regclass and tgenabled <> 'D') then
    raise exception 'gatilho app_settings_chaves_do_dono ausente: o financeiro ligaria o lote';
  end if;
  v_def := pg_get_functiondef('public._app_settings_chaves_do_dono()'::regprocedure);
  if position('papelada_lote' in v_def) = 0 or position('voz_unica_regras' in v_def) = 0
     or position('acompanhar_freio' in v_def) = 0 or position('fechamento_formato' in v_def) = 0
     or position('resumo_formato' in v_def) = 0 or position('comprovante_conversa' in v_def) = 0
     or position('comprovante_fluxo' in v_def) = 0 or position('pro_labore_pelo_salario_minimo' in v_def) = 0 then
    raise exception 'o gatilho das chaves do dono não protege todas as chaves (lote, voz única, freio, fechamento, resumo, comprovantes, pró-labore)';
  end if;
  if has_function_privilege('anon', 'public._app_settings_chaves_do_dono()', 'execute')
     or has_function_privilege('authenticated', 'public._app_settings_chaves_do_dono()', 'execute') then
    raise exception 'gatilho das chaves do dono exposto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261016130000', 'papelada_lote')
on conflict do nothing;
