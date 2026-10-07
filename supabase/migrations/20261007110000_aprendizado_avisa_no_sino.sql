-- O assistente aprende regras sozinho — e SEMPRE avisa (07/10/2026, pedido do dono: "acho válido,
-- mas sempre registrar e notificar (aprendizado de regra registrado), assim eu consulto e verifico
-- se faz sentido").
--
-- Registrar já acontecia: a regra que o sistema percebe nasce em finance_rules com origin='ai',
-- status='proposed' (inerte até alguém aceitar) e o porquê em `reasoning`. Faltava avisar: até
-- aqui ela só aparecia para quem abrisse Extrato › Regras. Agora toda regra aprendida vira um aviso
-- no sino de quem decide (admin e financeiro), com o que foi aprendido. Gatilho por COMANDO (não
-- por linha): uma rodada que aprende 6 regras dá um aviso só, listando as 6.
create or replace function public.avisar_regra_aprendida()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
  v_lista text;
begin
  select count(*),
         string_agg(format('"%s" → %s', left(n.match_value, 40), coalesce(n.set_category, '?')), '; ' order by n.match_value)
    into v_n, v_lista
  from novas n
  where n.origin = 'ai' and n.status = 'proposed';

  if coalesce(v_n, 0) = 0 then
    return null;
  end if;

  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'regra_aprendida',
         case when v_n = 1 then 'Aprendi uma regra do Extrato' else format('Aprendi %s regras do Extrato', v_n) end,
         left(v_lista, 600) || '. Confira e aceite (ou recuse) em Extrato › Regras: até lá ela não lança nada.',
         '/v2/financial/inbox/regras'
  from public.app_users u
  where u.active and u.role in ('admin', 'financial');

  return null;
end;
$$;

revoke all on function public.avisar_regra_aprendida() from public;
revoke all on function public.avisar_regra_aprendida() from anon;
revoke all on function public.avisar_regra_aprendida() from authenticated;

drop trigger if exists trg_avisar_regra_aprendida on public.finance_rules;
create trigger trg_avisar_regra_aprendida
  after insert on public.finance_rules
  referencing new table as novas
  for each statement
  execute function public.avisar_regra_aprendida();

insert into supabase_migrations.schema_migrations (version, name)
values ('20261007110000', 'aprendizado_avisa_no_sino');
