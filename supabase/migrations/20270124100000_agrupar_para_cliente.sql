-- "Agrupar para o cliente" — F0 (banco). Pedido do dono 17/11/2026, decisões 18/11/2026.
--
-- O agrupar que já existe (agrupar_orcamentos / agrupar_os) FUNDE: cria um documento novo, cancela os originais e
-- move as contas. Por isso recusa OS que começou (até só com chegada no barco). Este é o OUTRO modo: um CONJUNTO
-- que só CITA os documentos ("OS-00104 + ORÇ-00140"), para o cliente ver tudo junto. Nada é cancelado, movido ou
-- renumerado; cada documento segue com a execução, o sinal, a assinatura e a nota dele.
--
-- Decisões do dono:
--   · só MESMO cliente E MESMA embarcação (barco diferente não agrupa; cobrar junto = "Fechar juntas");
--   · mistura ORÇ e OS, em qualquer situação, menos: cancelado, já fundido em outro, orçamento reprovado, cliente
--     genérico ("Cliente Final") e documento que já está em outro conjunto ativo;
--   · o conjunto NÃO ganha número nem linha em service_orders (decisão A): relatórios, agenda e financeiro não
--     contam em dobro. O nome mostrado é a junção dos números dos documentos;
--   · documento aprovado e assinado nunca é alterado (a aprovação do conjunto é a F2; aqui nada muda documento).
--
-- Por que tabelas NOVAS e não orcamento_agrupamentos: lá agrupado_id (o documento fundido) é obrigatório e as
-- leituras da tela e do assistente (use-agrupar-*, tools agrupar-*) supõem origens canceladas — misturar quebraria
-- essas leituras.
--
-- Guardas (gatilhos, valem para tela, assistente e qualquer caminho):
--   · documento num conjunto ativo não é FUNDIDO (merged_into_id) nem troca de cliente/embarcação;
--   · documento cancelado (ou apagado) sai do conjunto; conjunto com menos de 2 documentos se desfaz sozinho.

-- 1) Tabelas ---------------------------------------------------------------------------------------------------
create table if not exists public.documento_conjuntos (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id),
  vessel_id uuid references public.vessels(id),
  -- Nulo só por um instante: documento principal apagado -> o gatilho 8c promove o próximo (ou desfaz o conjunto).
  principal_id uuid references public.service_orders(id) on delete set null,
  criado_por uuid,
  criado_em timestamptz not null default now(),
  desfeito_em timestamptz,
  desfeito_por uuid,
  desfeito_motivo text,
  constraint documento_conjuntos_motivo_check
    check (desfeito_motivo is null or desfeito_motivo in ('manual', 'documento_cancelado', 'documento_apagado')),
  constraint documento_conjuntos_desfeito_coerente
    check ((desfeito_em is null) = (desfeito_motivo is null))
);
comment on table public.documento_conjuntos is
  'Agrupar para o cliente: conjunto de ORÇ/OS do mesmo cliente e embarcação apresentados juntos. Só CITA os documentos (nada é cancelado ou movido). Sem número próprio. Escrita só pelas funções agrupar_para_cliente / desfazer_conjunto e pelos gatilhos.';

create table if not exists public.documento_conjunto_itens (
  conjunto_id uuid not null references public.documento_conjuntos(id) on delete cascade,
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  ordem integer not null,
  ativo boolean not null default true,
  saiu_em timestamptz,
  primary key (conjunto_id, service_order_id)
);
comment on table public.documento_conjunto_itens is
  'Documentos de um conjunto (Agrupar para o cliente). ativo=false quando o documento saiu (cancelado) ou o conjunto foi desfeito.';

-- Um documento está em no máximo UM conjunto ativo. service_order_id é NOT NULL: o índice parcial protege.
create unique index if not exists documento_conjunto_itens_um_ativo
  on public.documento_conjunto_itens (service_order_id) where ativo;
create index if not exists documento_conjuntos_principal_idx on public.documento_conjuntos (principal_id);

alter table public.documento_conjuntos enable row level security;
alter table public.documento_conjunto_itens enable row level security;
drop policy if exists documento_conjuntos_select on public.documento_conjuntos;
drop policy if exists documento_conjunto_itens_select on public.documento_conjunto_itens;
create policy documento_conjuntos_select on public.documento_conjuntos
  for select to authenticated using ((select auth.uid()) is not null);
create policy documento_conjunto_itens_select on public.documento_conjunto_itens
  for select to authenticated using ((select auth.uid()) is not null);

revoke all on public.documento_conjuntos from public, anon, authenticated;
revoke all on public.documento_conjunto_itens from public, anon, authenticated;
grant select on public.documento_conjuntos to authenticated;
grant select on public.documento_conjunto_itens to authenticated;
grant all on public.documento_conjuntos to service_role;
grant all on public.documento_conjunto_itens to service_role;

-- 2) Nome do conjunto: "OS-00104 + ORÇ-00140" (ativos, na ordem) ---------------------------------------------------
create or replace function public._conjunto_nome(p_conjunto uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select string_agg(so.service_order_number, ' + ' order by i.ordem)
    from public.documento_conjunto_itens i
    join public.service_orders so on so.id = i.service_order_id
   where i.conjunto_id = p_conjunto and i.ativo
$$;

-- 3) Por que UM documento não entra num conjunto. Nulo = pode. -----------------------------------------------------
create or replace function public._conjunto_impedimento(p_os uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.service_orders;
  v_txt text;
begin
  select so.* into r from public.service_orders so where so.id = p_os;
  if r.id is null then
    return 'Documento não encontrado. Recarregue a tela.';
  end if;
  if r.merged_into_id is not null then
    select d.service_order_number into v_txt from public.service_orders d where d.id = r.merged_into_id;
    return format('%s já foi juntado de vez em %s: use o %s.', r.service_order_number, coalesce(v_txt, 'outro documento'),
                  coalesce(v_txt, 'documento novo'));
  end if;
  if r.status = 'cancelled' then
    return format('%s está cancelado.', r.service_order_number);
  end if;
  if r.status = 'draft' and r.quote_status = 'rejected' then
    return format('%s está como Reprovado. Volte-o para Em elaboração antes de agrupar, ou deixe-o de fora.',
                  r.service_order_number);
  end if;
  if r.client_id is null then
    return format('%s não tem cliente.', r.service_order_number);
  end if;
  v_txt := public._cliente_generico(r.client_id);
  if v_txt is not null then
    return format('%s é do cadastro genérico "%s": cadastre o cliente de verdade antes de agrupar.',
                  r.service_order_number, v_txt);
  end if;
  select public._conjunto_nome(i.conjunto_id) into v_txt
    from public.documento_conjunto_itens i where i.service_order_id = p_os and i.ativo;
  if v_txt is not null then
    return format('%s já está no conjunto %s. Desfaça aquele conjunto antes.', r.service_order_number, v_txt);
  end if;
  return null;
end $$;

-- 3b) Por que UM documento não pode ser JUNTADO DE VEZ (a fusão de hoje: agrupar_orcamentos / agrupar_os). Nulo =
--     pode, em princípio (a fusão ainda confere o que compara os documentos entre si: total, deslocamento, vínculos).
--     Serve para a tela decidir (decisão 4B do dono): só pergunta "juntar de vez ou apresentar junto" quando a fusão
--     também é possível; senão vai direto ao conjunto e diz por quê.
create or replace function public._conjunto_motivo_juntar_de_vez(p_os uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.service_orders;
  v_txt text;
begin
  select so.* into r from public.service_orders so where so.id = p_os;
  if r.id is null then
    return 'Documento não encontrado.';
  end if;
  select public._conjunto_nome(i.conjunto_id) into v_txt
    from public.documento_conjunto_itens i where i.service_order_id = p_os and i.ativo;
  if v_txt is not null then
    return format('%s está no conjunto %s.', r.service_order_number, v_txt);
  end if;
  if r.status <> 'draft' then
    return public._os_impedimento_para_agrupar(p_os);  -- a régua do agrupar_os (execução, nota, comissão…)
  end if;
  -- Orçamento: a régua do agrupar_orcamentos que depende só dele.
  if r.merged_into_id is not null then
    return format('%s já foi agrupado.', r.service_order_number);
  end if;
  if r.converted_to_os_at is not null then
    return format('%s já virou OS.', r.service_order_number);
  end if;
  if r.quote_status = 'rejected' then
    return format('%s está como Reprovado.', r.service_order_number);
  end if;
  if r.signed_at is not null or exists (select 1 from public.service_order_signatures g where g.service_order_id = p_os) then
    return format('%s já foi assinado pelo cliente.', r.service_order_number);
  end if;
  v_txt := public._cliente_generico(r.client_id);
  if v_txt is not null then
    return format('%s é do cadastro genérico "%s".', r.service_order_number, v_txt);
  end if;
  if coalesce(r.card_fee_passthrough_enabled, false) then
    return format('%s repassa a taxa do cartão ao cliente.', r.service_order_number);
  end if;
  return null;
end $$;

-- 4) Montar o conjunto (só pelas portas abaixo) ----------------------------------------------------------------------
create or replace function public._conjunto_montar(p_ids uuid[], p_principal uuid, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_principal public.service_orders;
  r public.service_orders;
  v_motivo text;
  v_conjunto uuid;
  v_ordem integer := 1;
  v_avisos text[] := '{}';
begin
  if p_autor is null then
    raise exception 'Faça login para agrupar.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar.' using errcode = '42501';
  end if;

  if p_ids is null or array_position(p_ids, null) is not null then
    raise exception 'Escolha pelo menos 2 documentos para agrupar.' using errcode = '22023';
  end if;
  select array_agg(distinct x) into v_ids from unnest(p_ids) x;
  if cardinality(v_ids) <> cardinality(p_ids) then
    raise exception 'O mesmo documento foi escolhido duas vezes.' using errcode = '22023';
  end if;
  if cardinality(v_ids) < 2 then
    raise exception 'Escolha pelo menos 2 documentos para agrupar.' using errcode = '22023';
  end if;
  if cardinality(v_ids) > 10 then
    raise exception 'Agrupe no máximo 10 documentos de uma vez.' using errcode = '22023';
  end if;
  if p_principal is not null and not (p_principal = any(v_ids)) then
    raise exception 'O documento principal precisa estar entre os escolhidos.' using errcode = '22023';
  end if;

  -- Trava os documentos (na ordem do id: duas telas ao mesmo tempo não se cruzam) e confere um por um.
  perform 1 from public.service_orders so where so.id = any(v_ids) order by so.id for update;
  if (select count(*) from public.service_orders so where so.id = any(v_ids)) <> cardinality(v_ids) then
    raise exception 'Algum documento escolhido não existe mais. Recarregue a tela.' using errcode = 'P0002';
  end if;

  -- Principal: o escolhido; senão a OS mais antiga; senão o documento mais antigo.
  select so.* into v_principal from public.service_orders so
   where so.id = any(v_ids)
   order by (so.id = p_principal) desc, (so.status <> 'draft') desc, so.created_at, so.id
   limit 1;

  for r in select so.* from public.service_orders so where so.id = any(v_ids) order by so.created_at, so.id loop
    v_motivo := public._conjunto_impedimento(r.id);
    if v_motivo is not null then
      raise exception '%', v_motivo using errcode = '22023';
    end if;
    if r.client_id is distinct from v_principal.client_id then
      raise exception 'Só dá para agrupar documentos do mesmo cliente (% é de outro cliente).', r.service_order_number
        using errcode = '22023';
    end if;
    if r.vessel_id is distinct from v_principal.vessel_id then
      raise exception 'Só dá para agrupar documentos da mesma embarcação (% é de outra).', r.service_order_number
        using errcode = '22023';
    end if;
  end loop;

  insert into public.documento_conjuntos (client_id, vessel_id, principal_id, criado_por)
  values (v_principal.client_id, v_principal.vessel_id, v_principal.id, p_autor)
  returning id into v_conjunto;

  -- Ordem: principal primeiro, depois por data de criação.
  for r in select so.* from public.service_orders so where so.id = any(v_ids)
            order by (so.id = v_principal.id) desc, so.created_at, so.id loop
    insert into public.documento_conjunto_itens (conjunto_id, service_order_id, ordem)
    values (v_conjunto, r.id, v_ordem);
    v_ordem := v_ordem + 1;
  end loop;

  if exists (select 1 from public.service_orders so where so.id = any(v_ids) and so.status in ('completed', 'invoiced')) then
    v_avisos := v_avisos || 'Há documento já concluído no conjunto: ele aparece para o cliente só como referência.'::text;
  end if;

  return jsonb_build_object(
    'ok', true,
    'conjunto_id', v_conjunto,
    'nome', public._conjunto_nome(v_conjunto),
    'avisos', to_jsonb(v_avisos),
    'conjunto', public._conjunto_ler(v_conjunto)
  );
end $$;

-- 5) Desfazer (nada a devolver: os documentos nunca mudaram) ------------------------------------------------------
create or replace function public._conjunto_desfazer(p_conjunto uuid, p_autor uuid, p_motivo text default 'manual')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_c public.documento_conjuntos;
  v_nome text;
begin
  if p_motivo = 'manual' then
    if p_autor is null then
      raise exception 'Faça login para desfazer o conjunto.' using errcode = '42501';
    end if;
    if not public.is_admin_or_financial(p_autor) then
      raise exception 'Só administrador ou financeiro pode desfazer o conjunto.' using errcode = '42501';
    end if;
  end if;
  select c.* into v_c from public.documento_conjuntos c where c.id = p_conjunto for update;
  if v_c.id is null then
    raise exception 'Conjunto não encontrado. Recarregue a tela.' using errcode = 'P0002';
  end if;
  if v_c.desfeito_em is not null then
    if p_motivo = 'manual' then
      raise exception 'Este conjunto já foi desfeito.' using errcode = '22023';
    end if;
    return jsonb_build_object('ok', true, 'conjunto_id', p_conjunto, 'ja_desfeito', true);
  end if;
  v_nome := public._conjunto_nome(p_conjunto);
  update public.documento_conjuntos
     set desfeito_em = now(), desfeito_por = p_autor, desfeito_motivo = p_motivo
   where id = p_conjunto;
  update public.documento_conjunto_itens set ativo = false, saiu_em = coalesce(saiu_em, now())
   where conjunto_id = p_conjunto and ativo;
  return jsonb_build_object('ok', true, 'conjunto_id', p_conjunto, 'nome', v_nome);
end $$;

-- 6) Leitura: o conjunto inteiro, com o dinheiro de cada documento (para a tela, o PDF e o assistente) ----------
--    recebido = soma do pago nos recebíveis vivos; sinal_a_pagar = sinal ainda em aberto; em_aberto = total vivo
--    ainda não pago. "assinado" = signed_at ou assinatura gravada (o que já foi assinado não muda — decisão do dono).
create or replace function public._conjunto_ler(p_conjunto uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id,
    'nome', public._conjunto_nome(c.id),
    'ativo', c.desfeito_em is null,
    'criado_em', c.criado_em,
    'desfeito_em', c.desfeito_em,
    'desfeito_motivo', c.desfeito_motivo,
    'client_id', c.client_id,
    'cliente', (select cl.name from public.clients cl where cl.id = c.client_id),
    'vessel_id', c.vessel_id,
    'embarcacao', (select v.name from public.vessels v where v.id = c.vessel_id),
    'principal_id', c.principal_id,
    'total_geral', coalesce((select sum(coalesce(so.grand_total, 0))
                               from public.documento_conjunto_itens i
                               join public.service_orders so on so.id = i.service_order_id
                              where i.conjunto_id = c.id and (i.ativo or c.desfeito_em is not null)), 0),
    'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'tipo', case when so.status = 'draft' then 'orcamento' else 'os' end,
               'status', so.status,
               'quote_status', so.quote_status,
               'principal', so.id = c.principal_id,
               'ativo', i.ativo,
               'assinado', (so.signed_at is not null
                            or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id)),
               'grand_total', coalesce(so.grand_total, 0),
               'recebido', coalesce((select sum(coalesce(x.paid_amount, 0)) from public.receivables x
                                      where x.service_order_id = so.id and x.status is distinct from 'cancelled'), 0),
               'sinal_a_pagar', coalesce((select sum(greatest(coalesce(x.amount, 0) - coalesce(x.paid_amount, 0), 0))
                                           from public.receivables x
                                          where x.service_order_id = so.id and coalesce(x.is_deposit, false)
                                            and x.status not in ('paid', 'cancelled')), 0),
               'em_aberto', coalesce((select sum(greatest(coalesce(x.amount, 0) - coalesce(x.paid_amount, 0), 0))
                                       from public.receivables x
                                      where x.service_order_id = so.id and x.status not in ('paid', 'cancelled')), 0)
             ) order by i.ordem)
        from public.documento_conjunto_itens i
        join public.service_orders so on so.id = i.service_order_id
       where i.conjunto_id = c.id and (i.ativo or c.desfeito_em is not null)), '[]'::jsonb)
  )
  from public.documento_conjuntos c
  where c.id = p_conjunto
$$;

-- 7) Portas públicas (autor = auth.uid() ou p_autor pelo service role, como agrupar_os) ----------------------------
create or replace function public.agrupar_para_cliente(p_ids uuid[], p_principal uuid default null, p_autor uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._conjunto_montar(p_ids, p_principal, coalesce(auth.uid(), p_autor));
end $$;

create or replace function public.desfazer_conjunto(p_conjunto uuid, p_autor uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._conjunto_desfazer(p_conjunto, coalesce(auth.uid(), p_autor), 'manual');
end $$;

-- Leitura pela tela: o conjunto ATIVO de um documento (nulo se não está em nenhum).
create or replace function public.conjunto_do_documento(p_os uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Faça login.' using errcode = '42501';
  end if;
  select i.conjunto_id into v_id from public.documento_conjunto_itens i where i.service_order_id = p_os and i.ativo;
  if v_id is null then
    return null;
  end if;
  return public._conjunto_ler(v_id);
end $$;

-- Leitura pela tela/assistente: candidatos para agrupar com um documento (mesmo cliente e embarcação), cada um
-- com o motivo de não poder (mesma frase que o agrupar levanta).
create or replace function public.documentos_para_conjunto(p_os uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.service_orders;
begin
  if auth.uid() is null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Faça login.' using errcode = '42501';
  end if;
  select so.* into r from public.service_orders so where so.id = p_os;
  if r.id is null then
    raise exception 'Documento não encontrado. Recarregue a tela.' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'documento', jsonb_build_object('id', r.id, 'numero', r.service_order_number,
                                    'tipo', case when r.status = 'draft' then 'orcamento' else 'os' end,
                                    'status', r.status,
                                    'quote_status', r.quote_status,
                                    'grand_total', coalesce(r.grand_total, 0),
                                    'criado_em', r.created_at,
                                    'motivo', public._conjunto_impedimento(r.id),
                                    'motivo_juntar', public._conjunto_motivo_juntar_de_vez(r.id)),
    'candidatos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'tipo', case when so.status = 'draft' then 'orcamento' else 'os' end,
               'status', so.status,
               'quote_status', so.quote_status,
               'grand_total', coalesce(so.grand_total, 0),
               'criado_em', so.created_at,
               'motivo', public._conjunto_impedimento(so.id),
               'motivo_juntar', public._conjunto_motivo_juntar_de_vez(so.id)
             ) order by so.created_at desc)
        from public.service_orders so
       where so.id <> r.id
         and so.client_id = r.client_id
         and so.vessel_id is not distinct from r.vessel_id
         and so.status <> 'cancelled'
         and so.merged_into_id is null
         and not (so.status = 'draft' and so.quote_status = 'rejected')), '[]'::jsonb)
  );
end $$;

comment on function public.agrupar_para_cliente(uuid[], uuid, uuid) is
  'Agrupar para o cliente: junta 2 a 10 ORÇ/OS do mesmo cliente e embarcação num conjunto que só os cita (nada é cancelado ou movido). Autor = auth.uid() ou p_autor (service role); só admin/financeiro. Devolve {ok, conjunto_id, nome, avisos, conjunto}.';
comment on function public.desfazer_conjunto(uuid, uuid) is
  'Desfaz um conjunto do Agrupar para o cliente. Os documentos não mudam (nunca mudaram). Só admin/financeiro.';
comment on function public.conjunto_do_documento(uuid) is
  'O conjunto ativo (Agrupar para o cliente) de um documento, com o dinheiro de cada um; nulo se não está em nenhum.';
comment on function public.documentos_para_conjunto(uuid) is
  'Candidatos a agrupar para o cliente com um documento (mesmo cliente e embarcação), cada um com o motivo de não poder.';

-- 8) Guardas -----------------------------------------------------------------------------------------------------
-- 8a) Documento num conjunto ativo: não é fundido nem troca de cliente/embarcação.
create or replace function public._conjunto_guarda_documento()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_nome text;
begin
  if (new.merged_into_id is distinct from old.merged_into_id and new.merged_into_id is not null)
     or new.client_id is distinct from old.client_id
     or new.vessel_id is distinct from old.vessel_id then
    select public._conjunto_nome(i.conjunto_id) into v_nome
      from public.documento_conjunto_itens i where i.service_order_id = new.id and i.ativo;
    if v_nome is not null then
      if new.merged_into_id is distinct from old.merged_into_id then
        raise exception '% está no conjunto % (Agrupar para o cliente). Desfaça o conjunto antes de juntar de vez.',
          new.service_order_number, v_nome using errcode = '22023';
      end if;
      raise exception '% está no conjunto % (Agrupar para o cliente). Desfaça o conjunto antes de trocar o cliente ou a embarcação.',
        new.service_order_number, v_nome using errcode = '22023';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_conjunto_guarda_documento on public.service_orders;
create trigger trg_conjunto_guarda_documento
  before update of merged_into_id, client_id, vessel_id on public.service_orders
  for each row execute function public._conjunto_guarda_documento();

-- 8b) Documento cancelado sai do conjunto.
create or replace function public._conjunto_documento_cancelado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.documento_conjunto_itens set ativo = false, saiu_em = now()
   where service_order_id = new.id and ativo;
  return null;
end $$;

drop trigger if exists trg_conjunto_documento_cancelado on public.service_orders;
create trigger trg_conjunto_documento_cancelado
  after update of status on public.service_orders
  for each row when (new.status = 'cancelled' and old.status is distinct from 'cancelled')
  execute function public._conjunto_documento_cancelado();

-- 8c) Conjunto que ficou com menos de 2 documentos se desfaz (documento cancelado ou apagado). Se o que saiu era o
--     principal e o conjunto continua, o próximo da ordem vira o principal.
create or replace function public._conjunto_fecha_se_sobrar_um()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conjunto uuid := case when tg_op = 'DELETE' then old.conjunto_id else new.conjunto_id end;
  v_motivo text := case when tg_op = 'DELETE' then 'documento_apagado' else 'documento_cancelado' end;
begin
  if not exists (select 1 from public.documento_conjuntos c where c.id = v_conjunto and c.desfeito_em is null) then
    return null;
  end if;
  if (select count(*) from public.documento_conjunto_itens i where i.conjunto_id = v_conjunto and i.ativo) < 2 then
    perform public._conjunto_desfazer(v_conjunto, null, v_motivo);
    return null;
  end if;
  update public.documento_conjuntos c
     set principal_id = (select i.service_order_id from public.documento_conjunto_itens i
                          where i.conjunto_id = v_conjunto and i.ativo order by i.ordem limit 1)
   where c.id = v_conjunto
     and (c.principal_id is null
          or not exists (select 1 from public.documento_conjunto_itens i
                          where i.conjunto_id = v_conjunto and i.service_order_id = c.principal_id and i.ativo));
  return null;
end $$;

drop trigger if exists trg_conjunto_fecha_upd on public.documento_conjunto_itens;
create trigger trg_conjunto_fecha_upd
  after update of ativo on public.documento_conjunto_itens
  for each row when (old.ativo and not new.ativo)
  execute function public._conjunto_fecha_se_sobrar_um();

drop trigger if exists trg_conjunto_fecha_del on public.documento_conjunto_itens;
create trigger trg_conjunto_fecha_del
  after delete on public.documento_conjunto_itens
  for each row when (old.ativo)
  execute function public._conjunto_fecha_se_sobrar_um();

-- 9) Privilégios + prova -------------------------------------------------------------------------------------------
revoke all on function public._conjunto_nome(uuid) from public, anon, authenticated;
revoke all on function public._conjunto_impedimento(uuid) from public, anon, authenticated;
revoke all on function public._conjunto_motivo_juntar_de_vez(uuid) from public, anon, authenticated;
grant execute on function public._conjunto_motivo_juntar_de_vez(uuid) to service_role;
revoke all on function public._conjunto_montar(uuid[], uuid, uuid) from public, anon, authenticated;
revoke all on function public._conjunto_desfazer(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public._conjunto_ler(uuid) from public, anon, authenticated;
revoke all on function public._conjunto_guarda_documento() from public, anon, authenticated;
revoke all on function public._conjunto_documento_cancelado() from public, anon, authenticated;
revoke all on function public._conjunto_fecha_se_sobrar_um() from public, anon, authenticated;
revoke all on function public.agrupar_para_cliente(uuid[], uuid, uuid) from public, anon;
revoke all on function public.desfazer_conjunto(uuid, uuid) from public, anon;
revoke all on function public.conjunto_do_documento(uuid) from public, anon;
revoke all on function public.documentos_para_conjunto(uuid) from public, anon;
grant execute on function public._conjunto_nome(uuid) to service_role;
grant execute on function public._conjunto_impedimento(uuid) to service_role;
grant execute on function public._conjunto_montar(uuid[], uuid, uuid) to service_role;
grant execute on function public._conjunto_desfazer(uuid, uuid, text) to service_role;
grant execute on function public._conjunto_ler(uuid) to service_role;
grant execute on function public.agrupar_para_cliente(uuid[], uuid, uuid) to authenticated, service_role;
grant execute on function public.desfazer_conjunto(uuid, uuid) to authenticated, service_role;
grant execute on function public.conjunto_do_documento(uuid) to authenticated, service_role;
grant execute on function public.documentos_para_conjunto(uuid) to authenticated, service_role;

do $$
declare
  f text;
begin
  foreach f in array array['public._conjunto_nome(uuid)', 'public._conjunto_impedimento(uuid)',
                           'public._conjunto_motivo_juntar_de_vez(uuid)',
                           'public._conjunto_montar(uuid[], uuid, uuid)', 'public._conjunto_desfazer(uuid, uuid, text)',
                           'public._conjunto_ler(uuid)', 'public._conjunto_guarda_documento()',
                           'public._conjunto_documento_cancelado()', 'public._conjunto_fecha_se_sobrar_um()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'Privilégio errado: % aberto para anon/authenticated', f;
    end if;
  end loop;
  foreach f in array array['public.agrupar_para_cliente(uuid[], uuid, uuid)', 'public.desfazer_conjunto(uuid, uuid)',
                           'public.conjunto_do_documento(uuid)', 'public.documentos_para_conjunto(uuid)'] loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'Privilégio errado na porta %', f;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.documento_conjuntos', 'select')
     or has_table_privilege('anon', 'public.documento_conjunto_itens', 'select')
     or has_table_privilege('authenticated', 'public.documento_conjuntos', 'insert')
     or has_table_privilege('authenticated', 'public.documento_conjunto_itens', 'update') then
    raise exception 'Privilégios errados nas tabelas do conjunto';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20270124100000', 'agrupar_para_cliente')
on conflict do nothing;
