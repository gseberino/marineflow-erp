-- Diárias: ACERTO (fechar o período ao pagar), recibo numerado e a conferência do freelancer.
--
-- Pedido do dono (06/10/2026), a partir da pesquisa de apps e projetos de controle de diárias:
--   · Fechar o período ao pagar: os dias até a data do acerto ficam TRAVADOS — o extrato/recibo
--     que o freelancer assinou não muda depois. Reabrir só pelo caminho explícito, com motivo,
--     e só o último acerto da pessoa (a sequência não fica furada).
--   · Vale/adiantamento: é o pagamento feito DENTRO do período ainda aberto. O acerto mostra os
--     vales já pagos e o que falta pagar (o saldo no fim do período) — sem marcar pagamento por
--     pagamento: quem decide é a data.
--   · Recibo numerado (nº sequencial, competência, valor) — o PDF sai da tela e do assistente.
--   · O extrato/recibo vai ao freelancer pelo WhatsApp, e o "ok"/"confere" que ele responde fica
--     guardado (mesmo padrão da confirmação do agendamento, 30/09/2026: _e_concordancia).
--
-- O acerto é uma FOTO do período (dias, trabalhado, vales, saldo) no momento em que foi fechado.
-- Os pagamentos continuam vindo do banco; não se travam (o Pix do acerto chega depois dele).

create sequence if not exists public.recibo_diarias_seq;

create table if not exists public.acertos_diarias (
  id uuid primary key default gen_random_uuid(),
  numero integer not null unique default nextval('public.recibo_diarias_seq'),
  favorecido_id uuid not null references public.payees(id),
  de date not null,
  ate date not null,
  saldo_anterior numeric(12,2) not null,
  dias numeric(8,2) not null,
  trabalhado numeric(12,2) not null,
  pago_no_periodo numeric(12,2) not null,
  valor_do_acerto numeric(12,2) not null,
  status text not null default 'fechado',
  criado_por uuid,
  criado_em timestamptz not null default now(),
  reaberto_por uuid,
  reaberto_em timestamptz,
  motivo_reabertura text,
  enviado_ao_freelancer_em timestamptz,
  telefone_enviado text,
  conferido_em timestamptz,
  conferido_texto text,
  constraint acertos_diarias_periodo check (ate >= de),
  constraint acertos_diarias_status check (status in ('fechado', 'reaberto'))
);

comment on table public.acertos_diarias is
  'Acerto de diárias (fechamento do período ao pagar): foto do período, recibo nº, dias travados até "ate". Só pelas funções fechar/reabrir.';

create index if not exists acertos_diarias_por_pessoa on public.acertos_diarias (favorecido_id, ate) where status = 'fechado';

alter sequence public.recibo_diarias_seq owned by public.acertos_diarias.numero;

alter table public.acertos_diarias enable row level security;
revoke all on public.acertos_diarias from public, anon, authenticated;
grant select on public.acertos_diarias to authenticated;
drop policy if exists acertos_diarias_ler on public.acertos_diarias;
create policy acertos_diarias_ler on public.acertos_diarias for select to authenticated
  using (public.pode_ver_folha((select auth.uid())));

-- 1. A trava: dia dentro de acerto fechado não entra, não muda e não sai.
create or replace function public._dia_em_acerto_fechado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payee uuid;
  v_nome text;
  v_acerto record;
  v_linha record;
begin
  for v_linha in
    select * from (values (case when tg_op = 'INSERT' then null else old.work_profile_id end,
                           case when tg_op = 'INSERT' then null else old.data end,
                           case when tg_op = 'INSERT' then null else old.fracao end),
                          (case when tg_op = 'DELETE' then null else new.work_profile_id end,
                           case when tg_op = 'DELETE' then null else new.data end,
                           case when tg_op = 'DELETE' then null else new.fracao end)) x(perfil, data, fracao)
     where x.perfil is not null and x.fracao is not null
  loop
    select wp.payee_id, p.name into v_payee, v_nome
      from public.work_profiles wp join public.payees p on p.id = wp.payee_id
     where wp.id = v_linha.perfil;
    select numero, de, ate into v_acerto from public.acertos_diarias
     where favorecido_id = v_payee and status = 'fechado' and v_linha.data between de and ate
     order by ate desc limit 1;
    if v_acerto.numero is not null then
      raise exception 'O dia % de % está no acerto nº % (% a %), já fechado. Para mudar, reabra o acerto em Financeiro › Diárias.',
        to_char(v_linha.data, 'DD/MM'), v_nome, lpad(v_acerto.numero::text, 4, '0'),
        to_char(v_acerto.de, 'DD/MM'), to_char(v_acerto.ate, 'DD/MM');
    end if;
  end loop;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_dia_em_acerto_fechado on public.work_shifts;
create trigger trg_dia_em_acerto_fechado
  before insert or update or delete on public.work_shifts
  for each row execute function public._dia_em_acerto_fechado();

-- 2. Fechar o acerto: do dia seguinte ao último acerto (ou do início da conta corrente) até p_ate.
create or replace function public.fechar_acerto_diarias(
  p_favorecido_id uuid,
  p_ate date default null,
  p_simular boolean default false,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_ultimo record;
  v_de date;
  v_ate date := coalesce(p_ate, public._hoje_brt());
  c jsonb;
  v_aguardando numeric;
  v_vales jsonb;
  v_id uuid;
  v_numero integer;
  v_resumo text;
begin
  if v_autor is null and not coalesce(p_simular, false) then raise exception 'Diga quem está fechando o acerto.'; end if;
  select id, name, conta_corrente_desde into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;
  if v_ate > public._hoje_brt() then raise exception 'Acerto no futuro (%): feche até hoje.', to_char(v_ate, 'DD/MM/YYYY'); end if;

  select numero, ate into v_ultimo from public.acertos_diarias
   where favorecido_id = p_favorecido_id and status = 'fechado' order by ate desc limit 1;
  v_de := coalesce(v_ultimo.ate + 1, v_fav.conta_corrente_desde,
                   (select min(l.data) from public._conta_corrente_linhas(p_favorecido_id) l), v_ate);
  if v_de > v_ate then
    raise exception 'Nada a fechar: o acerto nº % de % já vai até %.', lpad(v_ultimo.numero::text, 4, '0'), v_fav.name, to_char(v_ultimo.ate, 'DD/MM');
  end if;

  c := public.conta_corrente_freelancer(p_favorecido_id, v_de, v_ate, p_autor);
  if jsonb_array_length(c -> 'linhas') = 0 and (c ->> 'saldo_anterior')::numeric = 0 then
    raise exception 'Nenhum dia nem pagamento de % entre % e %: nada a fechar.', v_fav.name, to_char(v_de, 'DD/MM'), to_char(v_ate, 'DD/MM');
  end if;
  v_aguardando := coalesce((c ->> 'pago_aguardando_banco')::numeric, 0);
  select coalesce(jsonb_agg(jsonb_build_object('data', x ->> 'data', 'valor', (x ->> 'pago')::numeric, 'descricao', x ->> 'descricao',
                                               'aguardando', coalesce((x ->> 'aguardando')::boolean, false))), '[]'::jsonb)
    into v_vales
    from jsonb_array_elements(c -> 'linhas') x where x ->> 'tipo' = 'pagamento';

  v_resumo := v_fav.name || ' · ' || to_char(v_de, 'DD/MM') || ' a ' || to_char(v_ate, 'DD/MM')
    || ' · ' || replace(rtrim(to_char((c ->> 'dias')::numeric, 'FM9999990.99'), '.'), '.', ',')
    || ' diária(s) ' || public._brl((c ->> 'trabalhado')::numeric)
    || ' · vales ' || public._brl((c ->> 'pago')::numeric)
    || case when (c ->> 'saldo_anterior')::numeric <> 0 then ' · saldo anterior ' || public._brl((c ->> 'saldo_anterior')::numeric) else '' end
    || ' · a pagar ' || public._brl((c ->> 'saldo_final')::numeric);

  if coalesce(p_simular, false) then
    return jsonb_build_object('ok', true, 'simulacao', true, 'favorecido', v_fav.name, 'de', v_de, 'ate', v_ate,
      'saldo_anterior', (c ->> 'saldo_anterior')::numeric, 'dias', (c ->> 'dias')::numeric,
      'trabalhado', (c ->> 'trabalhado')::numeric, 'pago_no_periodo', (c ->> 'pago')::numeric,
      'valor_do_acerto', (c ->> 'saldo_final')::numeric, 'pago_aguardando_banco', v_aguardando,
      'vales', v_vales, 'resumo', v_resumo);
  end if;

  insert into public.acertos_diarias (favorecido_id, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo, valor_do_acerto, criado_por)
  values (p_favorecido_id, v_de, v_ate, (c ->> 'saldo_anterior')::numeric, (c ->> 'dias')::numeric,
          (c ->> 'trabalhado')::numeric, (c ->> 'pago')::numeric, (c ->> 'saldo_final')::numeric, v_autor)
  returning id, numero into v_id, v_numero;

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_numero, 'favorecido', v_fav.name, 'de', v_de, 'ate', v_ate,
    'valor_do_acerto', (c ->> 'saldo_final')::numeric, 'pago_aguardando_banco', v_aguardando,
    'message', 'Acerto nº ' || lpad(v_numero::text, 4, '0') || ' fechado: ' || v_resumo
      || '. Os dias até ' || to_char(v_ate, 'DD/MM') || ' ficam travados.'
      || case when v_aguardando > 0 then ' Atenção: ' || public._brl(v_aguardando) || ' dos vales são Pix lançados à mão que o banco ainda não confirmou.' else '' end);
end;
$$;

-- 3. Reabrir: só o ÚLTIMO acerto fechado da pessoa, com motivo.
create or replace function public.reabrir_acerto_diarias(p_acerto_id uuid, p_motivo text, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v record;
  v_ultimo integer;
begin
  if v_autor is null then raise exception 'Diga quem está reabrindo o acerto.'; end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then raise exception 'Diga o motivo de reabrir (fica registrado).'; end if;
  select a.*, p.name as nome into v from public.acertos_diarias a join public.payees p on p.id = a.favorecido_id
   where a.id = p_acerto_id for update of a;
  if v.id is null then raise exception 'Acerto não encontrado.'; end if;
  if v.status <> 'fechado' then raise exception 'O acerto nº % já está reaberto.', lpad(v.numero::text, 4, '0'); end if;
  select numero into v_ultimo from public.acertos_diarias
   where favorecido_id = v.favorecido_id and status = 'fechado' order by ate desc limit 1;
  if v_ultimo <> v.numero then
    raise exception 'Só o último acerto de % pode ser reaberto (o nº %). Reabra os mais novos primeiro.', v.nome, lpad(v_ultimo::text, 4, '0');
  end if;
  update public.acertos_diarias
     set status = 'reaberto', reaberto_por = v_autor, reaberto_em = now(), motivo_reabertura = btrim(p_motivo)
   where id = v.id;
  return jsonb_build_object('ok', true, 'numero', v.numero,
    'message', 'Acerto nº ' || lpad(v.numero::text, 4, '0') || ' de ' || v.nome || ' reaberto: os dias de '
      || to_char(v.de, 'DD/MM') || ' a ' || to_char(v.ate, 'DD/MM') || ' podem ser corrigidos. Feche de novo quando acertar.');
end;
$$;

-- 4. "ok", "confere", 👍 do freelancer a quem o extrato/recibo foi mandado nos últimos 7 dias.
create or replace function public.registrar_conferencia_do_freelancer(p_phone text, p_body text, p_message_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v record;
begin
  if length(v_fone) < 8 or not public._e_concordancia(p_body) then
    return jsonb_build_object('conferiu', false);
  end if;
  -- O mais recente mandado a este número e ainda sem resposta: "ok" é sobre o último que ele recebeu.
  select a.id, a.numero, p.name as nome into v
    from public.acertos_diarias a join public.payees p on p.id = a.favorecido_id
   where a.status = 'fechado' and a.conferido_em is null
     and a.enviado_ao_freelancer_em > now() - interval '7 days'
     and right(regexp_replace(coalesce(a.telefone_enviado, ''), '\D', '', 'g'), 8) = right(v_fone, 8)
   order by a.enviado_ao_freelancer_em desc limit 1;
  if v.id is null then return jsonb_build_object('conferiu', false); end if;

  update public.acertos_diarias set conferido_em = now(), conferido_texto = left(btrim(p_body), 60) where id = v.id;
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'diarias_conferido', v.nome || ' conferiu o acerto nº ' || lpad(v.numero::text, 4, '0'),
         'Respondeu "' || left(btrim(p_body), 40) || '" pelo WhatsApp.', '/v2/financial/diarias'
    from public.app_users u where u.role = 'admin' and u.active;
  return jsonb_build_object('conferiu', true, 'numero', v.numero);
end;
$$;

revoke all on function public._dia_em_acerto_fechado() from public, anon, authenticated;
revoke all on function public.fechar_acerto_diarias(uuid, date, boolean, uuid) from public, anon;
revoke all on function public.reabrir_acerto_diarias(uuid, text, uuid) from public, anon;
revoke all on function public.registrar_conferencia_do_freelancer(text, text, uuid) from public, anon, authenticated;
grant execute on function public.fechar_acerto_diarias(uuid, date, boolean, uuid) to authenticated, service_role;
grant execute on function public.reabrir_acerto_diarias(uuid, text, uuid) to authenticated, service_role;
grant execute on function public.registrar_conferencia_do_freelancer(text, text, uuid) to service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006220000', 'diarias_acerto_e_recibo')
on conflict (version) do nothing;
