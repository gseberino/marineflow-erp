-- Técnico não troca a embarcação/veículo de uma OS, o dono de uma embarcação/veículo, nem o nome,
-- o CPF/CNPJ ou o tipo de um cliente (decisões 14 e 15 do dono, 22/10/2026: "siga pelo recomendado").
--
-- Continua a migration 20261021160000 (técnico não troca o cliente da OS). A tela já esconde o
-- "Trocar" e trava os campos para quem não é do escritório, e os payloads do técnico não levam
-- essas colunas (lib/service-orders-source.ts). Isso é o lado do app: quem garante é o banco,
-- porque clients, vessels e service_orders aceitam UPDATE de qualquer autenticado.
--
-- Regras, para UPDATE feito por usuário ATIVO com cargo 'technician' em app_users (is_technician):
--   OS (service_orders) — estende _os_tecnico_nao_troca_cliente, mantendo as duas regras de antes:
--     1. mudar client_id é recusado (igual);
--     2. pôr embarcação/veículo de OUTRO cliente é recusado (igual; vem antes da 3 porque o aviso
--        dela — "o cliente da OS pode ter mudado: recarregue" — é o que resolve a tela velha);
--     3. NOVA: trocar (ou tirar) a embarcação/veículo de uma OS que JÁ TEM uma é recusado.
--        A primeira unidade de uma OS sem unidade continua livre. Hoje service_orders.vessel_id é
--        NOT NULL (22/10: 0 de 124 OS sem unidade), então a primeira unidade é escolhida ao CRIAR
--        a OS (INSERT, livre); a regra fica escrita para o caso de a coluna um dia aceitar nulo.
--   Embarcação/veículo (vessels) — NOVO gatilho: mudar client_id (o dono) é recusado.
--   Cliente (clients) — NOVO gatilho: mudar name, cpf_cnpj ou type (PF/PJ) é recusado. Telefone,
--     e-mail, endereço e o resto continuam livres para o técnico.
--
-- Sem sessão (auth.uid() nulo: edge functions com service_role, crons, o assistente) as regras não
-- se aplicam — o assistente tem a própria porta, nas ferramentas (ctx.userRole). Escritório (admin,
-- financial, seller) e técnico INATIVO passam. Criar (INSERT) continua livre: trocar é o que muda.
-- Os gatilhos só disparam quando a coluna está no SET (BEFORE UPDATE OF) e só recusam quando o
-- valor MUDA: o técnico que manda o mesmo nome junto com o telefone novo passa.
--
-- Conferido em 22/10/2026: clients e vessels só tinham o gatilho de updated_at (sem conflito); as
-- colunas são clients.name, clients.cpf_cnpj, clients.type e vessels.client_id; nenhuma função do
-- banco muda essas colunas (registrar_resposta_da_revisao só mexe em clients.opt_out_whatsapp).
--
-- Só esquema (funções + gatilhos); não grava nem altera dado nenhum.

-- ─── 1. OS: estende a regra do técnico para a embarcação/veículo ─────────────────────────────────
create or replace function public._os_tecnico_nao_troca_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- is_technician já existe (técnico ATIVO em app_users): uma fonte só para a regra.
  if not public.is_technician(auth.uid()) then
    return new;
  end if;

  if new.client_id is distinct from old.client_id then
    raise exception 'Só o escritório troca o cliente de uma OS.'
      using errcode = '42501',
            hint = 'Peça ao escritório para trocar o cliente desta OS.';
  end if;

  if new.vessel_id is distinct from old.vessel_id and new.vessel_id is not null
     and not exists (
       select 1 from public.vessels v
       where v.id = new.vessel_id and v.client_id is not distinct from new.client_id
     ) then
    raise exception 'A embarcação ou veículo escolhido não é do cliente desta OS.'
      using errcode = '42501',
            hint = 'O cliente da OS pode ter mudado: recarregue a OS e escolha de novo.';
  end if;

  -- 22/10/2026: a OS que já tem embarcação/veículo não troca (nem fica sem). A primeira, escolhe.
  if new.vessel_id is distinct from old.vessel_id and old.vessel_id is not null then
    raise exception 'Só o escritório troca a embarcação ou veículo de uma OS.'
      using errcode = '42501',
            hint = 'Peça ao escritório para trocar a embarcação ou veículo desta OS.';
  end if;

  return new;
end
$$;

comment on function public._os_tecnico_nao_troca_cliente() is
  'Gatilho: técnico (app_users.role = technician) não troca o client_id de uma OS existente, não põe nela embarcação/veículo de outro cliente (21/10/2026) e não troca a embarcação/veículo de uma OS que já tem uma (22/10/2026). Decisões do dono.';

-- O gatilho os_tecnico_nao_troca_cliente (before update of client_id, vessel_id) já existe e chama
-- esta função: o create or replace basta. Os revokes de novo, para a migration valer sozinha.
revoke all on function public._os_tecnico_nao_troca_cliente() from public;
revoke all on function public._os_tecnico_nao_troca_cliente() from anon;
revoke all on function public._os_tecnico_nao_troca_cliente() from authenticated;

-- ─── 2. Embarcação/veículo: técnico não troca o dono ─────────────────────────────────────────────
create or replace function public._unidade_tecnico_nao_troca_dono()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Compara antes de consultar o cargo: gravação que não muda o dono nem pergunta.
  if new.client_id is distinct from old.client_id and public.is_technician(auth.uid()) then
    raise exception 'Só o escritório troca o dono de uma embarcação ou veículo.'
      using errcode = '42501',
            hint = 'Peça ao escritório para trocar o dono deste cadastro.';
  end if;
  return new;
end
$$;

comment on function public._unidade_tecnico_nao_troca_dono() is
  'Gatilho: técnico (app_users.role = technician, ativo) não troca o client_id (dono) de uma embarcação/veículo existente. Decisão do dono, 22/10/2026.';

drop trigger if exists unidade_tecnico_nao_troca_dono on public.vessels;
create trigger unidade_tecnico_nao_troca_dono
  before update of client_id on public.vessels
  for each row
  execute function public._unidade_tecnico_nao_troca_dono();

revoke all on function public._unidade_tecnico_nao_troca_dono() from public;
revoke all on function public._unidade_tecnico_nao_troca_dono() from anon;
revoke all on function public._unidade_tecnico_nao_troca_dono() from authenticated;

-- ─── 3. Cliente: técnico não muda nome, CPF/CNPJ nem tipo ────────────────────────────────────────
create or replace function public._cliente_tecnico_nao_muda_identidade()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.name is distinct from old.name
      or new.cpf_cnpj is distinct from old.cpf_cnpj
      or new.type is distinct from old.type)
     and public.is_technician(auth.uid()) then
    raise exception 'Só o escritório muda o nome, o CPF/CNPJ ou o tipo de um cliente.'
      using errcode = '42501',
            hint = 'Telefone, e-mail e endereço o técnico continua podendo mudar; o resto, peça ao escritório.';
  end if;
  return new;
end
$$;

comment on function public._cliente_tecnico_nao_muda_identidade() is
  'Gatilho: técnico (app_users.role = technician, ativo) não muda name, cpf_cnpj nem type de um cliente existente; telefone, e-mail e endereço continuam livres. Decisão do dono, 22/10/2026.';

drop trigger if exists cliente_tecnico_nao_muda_identidade on public.clients;
create trigger cliente_tecnico_nao_muda_identidade
  before update of name, cpf_cnpj, type on public.clients
  for each row
  execute function public._cliente_tecnico_nao_muda_identidade();

-- Função de gatilho não é para ser chamada direto: ninguém executa (revogar de anon por nome —
-- revogar só de public não fecha anon neste projeto).
revoke all on function public._cliente_tecnico_nao_muda_identidade() from public;
revoke all on function public._cliente_tecnico_nao_muda_identidade() from anon;
revoke all on function public._cliente_tecnico_nao_muda_identidade() from authenticated;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261022180000', 'tecnico_cadastro_e_embarcacao')
on conflict do nothing;
