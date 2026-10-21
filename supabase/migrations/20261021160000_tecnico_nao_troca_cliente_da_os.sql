-- Técnico não troca o cliente de uma OS (decisão do dono, 21/10/2026).
--
-- A tela já esconde o "Trocar" do técnico e o formulário dele não manda client_id ao atualizar
-- (payloadDeAtualizacaoParaCargo). Isso é o lado do app: quem garante é o banco, porque o
-- service_orders aceita UPDATE de qualquer autenticado (authenticated_all_service_orders).
--
-- Regras, para UPDATE feito por usuário ATIVO com cargo 'technician' em app_users:
--   1. mudar client_id é recusado;
--   2. mudar vessel_id para uma embarcação/veículo de OUTRO cliente é recusado. Sem isto, a tela
--      do técnico aberta antes de o escritório trocar o cliente mandaria a embarcação do cliente
--      antigo (o formulário dele não leva client_id, mas leva vessel_id) e a OS ficaria com o
--      cliente novo e o barco do antigo. Em 21/10 nenhuma das 123 OS com embarcação estava assim.
--      Só vale quando vessel_id MUDA: OS antiga de barco que depois foi vendido continua editável.
-- Sem sessão (auth.uid() nulo: edge functions com service_role, crons, o assistente) as regras
-- não se aplicam — esses caminhos têm as próprias portas por cargo. Criar a OS (INSERT) com o
-- cliente escolhido continua livre: trocar é o que muda.
--
-- Só esquema (função + gatilho); não grava nem altera dado nenhum.

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

  return new;
end
$$;

comment on function public._os_tecnico_nao_troca_cliente() is
  'Gatilho: técnico (app_users.role = technician) não troca o client_id de uma OS existente nem põe nela embarcação/veículo de outro cliente. Decisão do dono, 21/10/2026.';

drop trigger if exists os_tecnico_nao_troca_cliente on public.service_orders;
create trigger os_tecnico_nao_troca_cliente
  before update of client_id, vessel_id on public.service_orders
  for each row
  execute function public._os_tecnico_nao_troca_cliente();

-- Função de gatilho não é para ser chamada direto: ninguém executa (revogar de anon por nome —
-- revogar só de public não fecha anon neste projeto).
revoke all on function public._os_tecnico_nao_troca_cliente() from public;
revoke all on function public._os_tecnico_nao_troca_cliente() from anon;
revoke all on function public._os_tecnico_nao_troca_cliente() from authenticated;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261021160000', 'tecnico_nao_troca_cliente_da_os')
on conflict do nothing;
