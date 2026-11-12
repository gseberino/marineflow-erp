-- Retorno rápido (12/11/2026): nenhuma função do retorno/parceiro pode ter UPDATE ou DELETE sem WHERE.
-- O Supabase carrega o pg_safeupdate nas sessões do PostgREST e recusa esses comandos ("UPDATE requires a WHERE clause",
-- HTTP 400). Pelo cron e pela bancada (CLI) passam, então só este teste pega: a carona do retorno e as palavras
-- *segura*, *libera*, *fora até* e *pessoal* falhavam pelo assistente (conserto: 20261112200000_retorno_update_com_where).
-- Varre o corpo de TODAS as funções retorno*/_retorno*/parceiro*/_parceiro* do banco (o que está aplicado), sem
-- comentários de linha; cada comando vai do UPDATE/DELETE ao próximo ';'.
-- Run: npx supabase db query --linked -f supabase/tests/retorno_update_com_where.sql
-- Só leitura; termina em ROLLBACK.
begin;

do $$
declare
  v_lista text;
  v_funcoes int;
begin
  select count(*) into v_funcoes
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'retorno%' or p.proname like '\_retorno%' or p.proname like 'parceiro%' or p.proname like '\_parceiro%');
  -- 1. O teste olha alguma coisa: o retorno tem dezenas de funções no banco.
  if v_funcoes < 50 then
    raise exception '1: só % funções do retorno/parceiro no banco: o filtro do teste quebrou', v_funcoes;
  end if;

  -- 2. Nenhum UPDATE/DELETE sem WHERE.
  select string_agg(distinct f.assinatura, ', ' order by f.assinatura) into v_lista
    from (select p.oid::regprocedure::text as assinatura, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as corpo
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and (p.proname like 'retorno%' or p.proname like '\_retorno%' or p.proname like 'parceiro%' or p.proname like '\_parceiro%')) f,
         regexp_matches(f.corpo, '((?:update|delete\s+from)\s+(?:only\s+)?public\.[a-z_]+[^;]*);', 'gi') as m
   where m[1] !~* '\mwhere\M';
  if v_lista is not null then
    raise exception '2: UPDATE/DELETE sem WHERE (o PostgREST recusa): %', v_lista;
  end if;

  -- 3. A carona, o dito e a volta do pessoal continuam existindo (o conserto não as derrubou).
  if to_regprocedure('public.retorno_carona(uuid,timestamp with time zone)') is null
     or to_regprocedure('public.retorno_dito(jsonb,uuid,timestamp with time zone)') is null
     or to_regprocedure('public._retorno_dito_pessoal(integer,uuid,timestamp with time zone)') is null then
    raise exception '3: função do conserto ausente';
  end if;
end $$;

rollback;
