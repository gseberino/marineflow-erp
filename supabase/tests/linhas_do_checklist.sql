-- linhas_do_checklist: cada item do "Mês pronto?" devolve exatamente as linhas que ele conta.
-- Run: npx supabase db query --linked -f supabase/tests/linhas_do_checklist.sql
-- Só leitura. Falha com exceção se algum item divergir ou se anon puder chamar a função.
do $$
declare
  r record;
  v_diverge text := '';
begin
  if has_function_privilege('anon', 'public.linhas_do_checklist(integer, integer, text)', 'execute') then
    raise exception 'anon não pode chamar linhas_do_checklist';
  end if;
  if not has_function_privilege('authenticated', 'public.linhas_do_checklist(integer, integer, text)', 'execute') then
    raise exception 'authenticated precisa chamar linhas_do_checklist';
  end if;
  for r in
    select m.ano, m.mes, i ->> 'chave' as chave, (i ->> 'quantidade')::int as aviso,
           jsonb_array_length(public.linhas_do_checklist(m.ano, m.mes, i ->> 'chave')) as linhas
      from (select extract(year from d)::int as ano, extract(month from d)::int as mes
              from generate_series(date_trunc('month', now()) - interval '3 months', date_trunc('month', now()), interval '1 month') d) m
      cross join lateral jsonb_array_elements(public.checklist_do_mes(m.ano, m.mes) -> 'itens') i
  loop
    -- extrato_tratado lista no máximo 200 linhas.
    if r.aviso <> r.linhas and not (r.chave = 'extrato_tratado' and r.aviso > 200 and r.linhas = 200) then
      v_diverge := v_diverge || format('%s/%s %s: aviso %s × linhas %s; ', r.mes, r.ano, r.chave, r.aviso, r.linhas);
    end if;
  end loop;
  if v_diverge <> '' then raise exception 'Divergência: %', v_diverge; end if;
end $$;
select 'ok: os itens do Mês pronto? e as linhas batem nos últimos 4 meses' as resultado;
