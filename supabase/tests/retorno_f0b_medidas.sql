-- Retorno F0b: a linha de base (retorno_medidas_base) reproduz a verificação V3 de 31/10 no mesmo
-- período (04/08 a 29/10/2026), com até 5% de diferença — o histórico só muda se mensagens forem
-- apagadas ou regravadas. Leva ~45 s (a consulta é a da V3). E ninguém de fora lê as medidas.
-- Run: npx supabase db query --linked -f supabase/tests/retorno_f0b_medidas.sql
-- Termina em ROLLBACK.
begin;

do $$
declare
  r record;
  v_alvo record;
begin
  create temp table _b on commit drop as
    select * from public.retorno_medidas_base(timestamptz '2026-08-04 00:00-03', timestamptz '2026-10-30 00:00-03')
     where not em_queda and cat not like 'x\_%';

  for v_alvo in
    select * from (values
      ('1 cliente cadastrado', 163, 179.0, 38.0),
      ('4 parceiro MP', 126, 32.0, 55.6),
      ('nucleo', 442, 39.0, 53.4),
      ('nucleo abertura pedido', 54, 126.0, 38.9)) v(gr, blocos, mediana, pct_1h)
  loop
    select count(*) as n,
           percentile_disc(0.5) within group (order by coalesce(espera_min, 1e9)) as med,
           100.0 * count(*) filter (where espera_min <= 60) / nullif(count(*), 0) as p1h
      into r
      from _b
     where case v_alvo.gr
             when 'nucleo' then nucleo
             when 'nucleo abertura pedido' then nucleo and abertura and pedido
             else grupo = v_alvo.gr end;
    if abs(r.n - v_alvo.blocos) > 0.05 * v_alvo.blocos
       or abs(r.med - v_alvo.mediana) > 0.05 * v_alvo.mediana
       or abs(r.p1h - v_alvo.pct_1h) > 5 then
      raise exception 'medidas: % deu % blocos, mediana %, % em 1 h (V3: %, %, %)',
        v_alvo.gr, r.n, round(r.med::numeric), round(r.p1h, 1), v_alvo.blocos, v_alvo.mediana, v_alvo.pct_1h;
    end if;
  end loop;

  if has_function_privilege('anon', 'public.retorno_medidas_base(timestamptz, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.retorno_medidas_base(timestamptz, timestamptz)', 'execute')
     or has_table_privilege('anon', 'public.retorno_medidas_blocos', 'select')
     or has_table_privilege('authenticated', 'public.retorno_medidas_blocos', 'select')
     or has_table_privilege('anon', 'public.retorno_medidas', 'select')
     or has_table_privilege('authenticated', 'public.retorno_medidas', 'select') then
    raise exception 'medidas abertas a anon/authenticated';
  end if;
  if not exists (select 1 from cron.job where jobname = 'retorno-medidas' and schedule = '40 5 * * *' and active) then
    raise exception 'o cron retorno-medidas não está agendado';
  end if;

  raise notice 'retorno_f0b_medidas: OK';
end $$;

rollback;
