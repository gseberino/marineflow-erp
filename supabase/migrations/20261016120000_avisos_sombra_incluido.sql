-- Secretário, Passo 4 (16/10/2026), a leitura do guardado (P4.5 base): a manhã e o fechamento em SOMBRA passam a
-- mostrar, no texto guardado (resumo_manha.texto_novo / resumo_tarde.texto), o que o portão segurou para eles. A
-- mensagem-sombra NÃO sai para o dono — então o que ela mostrou não pode virar "entregue".
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md §6.3 (marcas "(16/10)").
--
-- Muda UMA coisa em avisos_incluir_na_mensagem: no modo sombra, sem id da fila, o aviso fica 'incluido' (mostrado na
-- mensagem-sombra, incluido_em = a hora), em vez de 'entregue'. Efeito:
--   * não volta a aparecer na próxima mensagem-sombra (avisos_para_a_mensagem só devolve 'guardado');
--   * nunca é "entregue" sem uma fila 'sent' (a medida "guardado que nunca chegou" fica honesta na comparação);
--   * avisos_para_a_mensagem não o devolve a 'guardado' (isso só acontece com fila_id preenchido que não saiu).
-- O modo ligado continua exigindo o id da fila e marcando 'incluido' → 'entregue' quando a fila diz 'sent'.
--
-- Sem dado gravado: em produção (16/10/2026) ninguém chamou avisos_incluir_na_mensagem ainda (a manhã e o fechamento
-- não liam o guardado) — avisos_do_dono não tem linha 'entregue' em sombra para corrigir.
-- Recria a função SÓ se o corpo em produção for o de 20261016101000 (md5 do prosrc normalizado — A-Z em minúscula, sem
-- espaços — b4dbf45f29d2a4cff5c1553c6f740c01, conferido por SELECT em 16/10/2026) ou já este (2ª aplicação); qualquer
-- outro corpo PARA a migration sem mudar nada. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 0. A guarda do corpo, ANTES de recriar.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_md5 text;
begin
  select md5(regexp_replace(translate(p.prosrc, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\s+', '', 'g'))
    into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'avisos_incluir_na_mensagem';
  if v_md5 is null or v_md5 not in ('b4dbf45f29d2a4cff5c1553c6f740c01', 'dc5da6d6aef0259402161f10a967d975') then
    raise exception 'avisos_incluir_na_mensagem não é a de 20261016101000 (md5 %): confira o corpo em produção antes de recriar', coalesce(v_md5, 'ausente');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. avisos_incluir_na_mensagem: na sombra, sem fila = 'incluido' (mostrado na mensagem-sombra), nunca 'entregue'
--    p = {phone, modo, ids: [uuid…], fila_id (obrigatório no modo ligado), agora?}
-- ---------------------------------------------------------------------------------------------
create or replace function public.avisos_incluir_na_mensagem(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone text := p->>'phone';
  v_modo  text := coalesce(nullif(p->>'modo', ''), 'sombra');
  v_ids   uuid[];
  v_fila  uuid;
  v_agora timestamptz;
  v_n     integer := 0;
begin
  begin
    v_ids := array(select jsonb_array_elements_text(coalesce(p->'ids', '[]'::jsonb))::uuid);
    v_fila := nullif(p->>'fila_id', '')::uuid;
    v_agora := coalesce(nullif(p->>'agora', '')::timestamptz, now());
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'ids, fila_id ou agora inválido');
  end;
  if v_phone is null or v_modo not in ('sombra', 'ligado') then
    return jsonb_build_object('ok', false, 'erro', 'faltam phone ou modo');
  end if;
  if v_modo = 'ligado' and v_fila is null then
    return jsonb_build_object('ok', false, 'erro', 'no modo ligado a mensagem precisa do id da fila');
  end if;
  -- sem fila só na sombra: a mensagem-sombra não sai; o que ela mostrou fica 'incluido' (não volta a aparecer) e
  -- nunca 'entregue'. Com fila: 'incluido' até a fila dizer 'sent' (avisos_para_a_mensagem confere).
  update public.avisos_do_dono a
     set situacao = 'incluido', fila_id = v_fila, incluido_em = v_agora, atualizado_em = now()
   where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'guardado' and a.id = any (v_ids);
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'incluidos', v_n);
end $$;

comment on function public.avisos_incluir_na_mensagem(jsonb) is
  'Secretário (uma voz só): a mensagem fixa levou estes guardados — ficam ''incluido'' (com o id da fila; sem fila só na sombra, que não sai e por isso nunca vira entregue). Entregue só com a fila ''sent'' (avisos_para_a_mensagem). Só service_role.';

revoke all on function public.avisos_incluir_na_mensagem(jsonb) from public, anon, authenticated;
grant execute on function public.avisos_incluir_na_mensagem(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se a porta ficou aberta ou se o corpo não é o esperado.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text := 'public.avisos_incluir_na_mensagem(jsonb)';
  v_def text;
begin
  if has_function_privilege('anon', v_f, 'execute') then
    raise exception 'avisos_incluir_na_mensagem exposta para anon';
  end if;
  if has_function_privilege('authenticated', v_f, 'execute') then
    raise exception 'avisos_incluir_na_mensagem exposta para authenticated';
  end if;
  if not has_function_privilege('service_role', v_f, 'execute') then
    raise exception 'a edge (service_role) não alcança avisos_incluir_na_mensagem';
  end if;
  v_def := pg_get_functiondef(v_f::regprocedure);
  if position('situacao = ''entregue''' in v_def) > 0 then
    raise exception 'avisos_incluir_na_mensagem ainda marca entregue sem fila';
  end if;
  if position('security definer' in lower(v_def)) > 0 or position('search_path to ''''' in lower(v_def)) = 0 then
    raise exception 'avisos_incluir_na_mensagem precisa ser security invoker com search_path vazio';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261016120000', 'avisos_sombra_incluido')
on conflict do nothing;
