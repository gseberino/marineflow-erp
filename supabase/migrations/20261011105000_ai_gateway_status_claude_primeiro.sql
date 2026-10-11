-- HBR AI Gateway: o status mostra primeiro o worker do Claude (11/10/2026).
--
-- Com o HBR Doc Worker (hbr-pc-doc, só local-doc) no ar, ai_gateway_workers passa a ter dois
-- workers. A tela de Configurações lê workers[0] (AssistenteIATab.tsx) e a F1 dos comprovantes
-- não muda src/: então a ordem põe primeiro quem pode pegar claude-local (allowed_providers nulo
-- ou com claude-local), depois quem anunciou o claude-local no estado, depois o visto por último.
-- Cada worker ganha a chave 'allowed_providers'. O resto é igual à 20261003235000.
--
-- Depende da 20261011104000 (coluna allowed_providers). Não escreve dados. Idempotente.

create or replace function public.ai_gateway_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Só o administrador vê o status do gateway' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'disponivel', public.ai_claude_max_disponivel(),
    'agora', now(),
    'workers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id,
               'enabled', w.enabled,
               'last_seen_at', w.last_seen_at,
               'version', w.version,
               'providers', w.estado->'providers',
               'ativos', w.estado->'ativos',
               'maximo', w.estado->'max',
               'allowed_providers', to_jsonb(w.allowed_providers)
             ) order by (w.allowed_providers is null or 'claude-local' = any (w.allowed_providers)) desc,
                        -- coalesce: estado nulo não pode subir na frente (DESC põe nulo primeiro)
                        coalesce(w.estado->'providers' ? 'claude-local', false) desc,
                        w.last_seen_at desc nulls last)
        from public.ai_gateway_workers w), '[]'::jsonb),
    'ultimos', coalesce((
      select jsonb_agg(x order by x->>'created_at' desc)
        from (
          select jsonb_build_object(
                   'tipo', j.metadata->>'tipo',
                   'status', j.status,
                   'model_used', j.model_used,
                   'duration_ms', j.duration_ms,
                   'error_code', j.error_code,
                   'created_at', j.created_at
                 ) as x
            from public.ai_jobs j
           where j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel')
           order by j.created_at desc
           limit 8
        ) u), '[]'::jsonb)
  );
end $$;

revoke all on function public.ai_gateway_status() from public, anon, authenticated;
grant execute on function public.ai_gateway_status() to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.ai_gateway_status()', 'execute') then
    raise exception 'anon alcança o status do gateway';
  end if;
  if not has_function_privilege('authenticated', 'public.ai_gateway_status()', 'execute') then
    raise exception 'a tela de Configurações perdeu o status do gateway';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011105000', 'ai_gateway_status_claude_primeiro')
on conflict do nothing;
