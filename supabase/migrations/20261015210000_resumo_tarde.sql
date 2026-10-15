-- Secretário, Passo 3 (15/10/2026): o turno da tarde do resumo — o fechamento das 17:30 (seg–sex), a revisão
-- da semana (segunda), a revisão do mês (1º dia útil) e a pergunta da sexta — e a chave fechamento_formato.
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md
--
-- A tarde NÃO cria item nem letra: volta a mostrar os itens que a manhã do mesmo dia gravou
-- (resumo_manha/resumo_itens, migration 20261015200000), com a mesma letra. Por isso as ações ("B feito",
-- "tira C"), a repetição e o "volta" continuam nas mesmas linhas de resumo_itens, e esta migration não mexe
-- nelas nem nas RPCs da manhã.
--   * resumo_tarde: uma linha por dia e telefone (o turno, o texto, as letras mostradas, se foi enviada, a
--     pergunta da sexta e a resposta). Existir a linha = "já decidi hoje" (os disparos das 17:40 e 17:50 param);
--   * resumo_tarde_registrar: grava a tarde UMA vez e, quando é para enviar, enfileira NA MESMA TRANSAÇÃO
--     (gravou = está na fila; não gravou = não foi);
--   * resumo_itens_acoes: a revisão respondida de uma vez ("D semana, F tira, G 15 dias"), tudo ou nada;
--   * resumo_semana_responder: a resposta da pergunta da sexta (ajudou | pouco | atrapalhou).
--
-- GRAVA DADO — OK NOMEADO: uma chave em app_settings ('fechamento_formato' = 'desligado', bloco 4). Nasce
-- desligada: nada muda até o dono trocar para 'sombra'. Recria o gatilho _app_settings_chaves_do_dono com a
-- chave nova (só o admin muda). O corpo de antes foi conferido em produção em 15/10/2026: md5 do prosrc
-- normalizado (minúsculas, sem espaços) = 42dded24d25e3fcf4cb6a05c0f18c16e, igual ao de
-- 20261015200000_resumo_secretario.sql — e a migration confere de novo antes de recriar (bloco 4).
-- Nenhum cron aqui: o horário das 17:30 está na migration separada 20261015210100 (CRON NOVO — OK NOMEADO).
-- Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. resumo_tarde: uma por dia e telefone
-- ---------------------------------------------------------------------------------------------
create table if not exists public.resumo_tarde (
  id               uuid primary key default gen_random_uuid(),
  dia              date not null,
  phone_normalized text not null,
  app_user_id      uuid references public.app_users(id) on delete set null,
  turno            text not null,
  -- o modo da manhã do dia (as letras e os itens vêm dela)
  modo             text not null,
  -- a chave fechamento_formato na hora de montar
  formato          text not null,
  -- nulo só no dia calado (nada a dizer: nenhuma mensagem)
  texto            text,
  calado           boolean not null default false,
  enviado          boolean not null default false,
  -- as letras mostradas: [{letra, referencia, tipo, parte}] (parte: ficou | parado | antiga)
  letras           jsonb not null default '[]'::jsonb,
  -- as contagens e os números do panorama (a base da medição)
  detalhe          jsonb not null default '{}'::jsonb,
  -- a papelada contada às 17:30: o comando *escritório* prefere esta à da manhã
  escritorio       text,
  itens            smallint not null default 0,
  pergunta_semana  boolean not null default false,
  resposta_semana  text,
  respondida_em    timestamptz,
  -- o dono estava conversando quando a tarde foi montada (a medida do "espera até 20 min")
  conversa_ativa   boolean not null default false,
  -- 1 = 17:30, 2 = 17:40, 3 = 17:50
  tentativa        smallint not null default 1,
  criado_em        timestamptz not null default now(),
  constraint resumo_tarde_um_por_dia unique (dia, phone_normalized),
  constraint resumo_tarde_phone_chk check (phone_normalized ~ '^[0-9]{10,15}$'),
  constraint resumo_tarde_turno_chk check (turno in ('fechamento', 'revisao_semana', 'revisao_mes')),
  constraint resumo_tarde_modo_chk check (modo in ('sombra', 'novo')),
  constraint resumo_tarde_formato_chk check (formato in ('sombra', 'ligado')),
  constraint resumo_tarde_texto_chk check (
    (calado and texto is null) or (not calado and texto is not null and char_length(texto) between 1 and 4000)),
  -- a sombra nunca é enviada; a tarde só vai sobre letras que o dono viu (manhã nova); calado não tem o que enviar
  constraint resumo_tarde_enviado_chk check (not enviado or (formato = 'ligado' and modo = 'novo' and not calado)),
  constraint resumo_tarde_letras_chk check (jsonb_typeof(letras) = 'array' and octet_length(letras::text) <= 8192),
  constraint resumo_tarde_detalhe_chk check (jsonb_typeof(detalhe) = 'object' and octet_length(detalhe::text) <= 16384),
  constraint resumo_tarde_escritorio_chk check (escritorio is null or char_length(escritorio) <= 2000),
  constraint resumo_tarde_itens_chk check (itens between 0 and 21),
  constraint resumo_tarde_tentativa_chk check (tentativa between 1 and 3),
  constraint resumo_tarde_resposta_chk check (resposta_semana is null or resposta_semana in ('ajudou', 'pouco', 'atrapalhou')),
  constraint resumo_tarde_respondida_chk check ((resposta_semana is null) = (respondida_em is null)),
  -- só responde quem recebeu a pergunta
  constraint resumo_tarde_pergunta_chk check (resposta_semana is null or (pergunta_semana and enviado))
);

comment on table public.resumo_tarde is
  'Secretário (Passo 3, 15/10/2026): o turno da tarde de cada dia e telefone — fechamento (seg–sex), revisão da semana ou do mês — com as letras da manhã que mostrou, se foi enviado, a pergunta da sexta e a resposta. Sombra = gravado e não enviado. Só o admin lê; escrita só pelas RPCs resumo_tarde_registrar e resumo_semana_responder (service_role).';
comment on column public.resumo_tarde.calado is 'Nada a dizer no dia (nenhuma mensagem): grava para os disparos das 17:40 e 17:50 pararem e para a medição.';
comment on column public.resumo_tarde.resposta_semana is 'A pergunta da sexta ("Esta semana o resumo ajudou?"): ajudou, pouco ou atrapalhou. A medição da regra de decisão.';

create index if not exists resumo_tarde_pergunta
  on public.resumo_tarde (phone_normalized, dia) where pergunta_semana and enviado;

-- ---------------------------------------------------------------------------------------------
-- 2. RLS e privilégios (revogar de anon/authenticated POR NOME)
-- ---------------------------------------------------------------------------------------------
alter table public.resumo_tarde enable row level security;

revoke all on table public.resumo_tarde from public, anon, authenticated;
grant select on table public.resumo_tarde to authenticated;
grant all on table public.resumo_tarde to service_role;
drop policy if exists resumo_tarde_admin_le on public.resumo_tarde;
create policy resumo_tarde_admin_le on public.resumo_tarde
  for select to authenticated using (public.is_admin((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 3. resumo_tarde_registrar: a tarde do dia, uma vez só; enviar = enfileirar na mesma transação
-- ---------------------------------------------------------------------------------------------
create or replace function public.resumo_tarde_registrar(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_dia      date;
  v_phone    text := p->>'phone';
  v_turno    text := p->>'turno';
  v_modo     text := p->>'modo';
  v_formato  text := p->>'formato';
  v_calado   boolean := coalesce((p->>'calado')::boolean, false);
  v_enviado  boolean := coalesce((p->>'enviado')::boolean, false);
  v_texto    text := case when coalesce((p->>'calado')::boolean, false) then null else p->>'texto' end;
  v_id       uuid;
  v_feito    record;
  v_na_fila  integer := 0;
begin
  begin
    v_dia := (p->>'dia')::date;
  exception when others then
    v_dia := null;
  end;
  if v_dia is null or v_phone is null or v_turno is null or v_modo is null or v_formato is null
     or (not v_calado and v_texto is null) then
    return jsonb_build_object('ok', false, 'erro', 'faltam dia, phone, turno, modo, formato ou texto');
  end if;

  -- já decidido hoje (o 2º e o 3º disparo, ou dois ao mesmo tempo): devolve o que foi gravado
  select t.id, t.texto, t.turno, t.enviado, t.calado into v_feito
    from public.resumo_tarde t where t.dia = v_dia and t.phone_normalized = v_phone;
  if found then
    return jsonb_build_object('ok', true, 'novo', false, 'id', v_feito.id, 'texto', v_feito.texto, 'turno', v_feito.turno,
                              'enviado', v_feito.enviado, 'calado', v_feito.calado);
  end if;

  -- enviar só sobre a manhã NOVA do mesmo dia (as letras que o dono recebeu); o CHECK segura o resto
  if v_enviado and not exists (select 1 from public.resumo_manha m
                                where m.dia = v_dia and m.phone_normalized = v_phone and m.modo = 'novo') then
    return jsonb_build_object('ok', false, 'erro', 'manha_nao_e_nova');
  end if;

  begin
    insert into public.resumo_tarde (dia, phone_normalized, app_user_id, turno, modo, formato, texto, calado, enviado,
                                     letras, detalhe, escritorio, itens, pergunta_semana, conversa_ativa, tentativa)
    values (v_dia, v_phone, nullif(p->>'app_user_id', '')::uuid, v_turno, v_modo, v_formato, v_texto, v_calado, v_enviado,
            coalesce(p->'letras', '[]'::jsonb), coalesce(p->'detalhe', '{}'::jsonb), p->>'escritorio',
            coalesce((p->>'itens')::smallint, 0), coalesce((p->>'pergunta_semana')::boolean, false),
            coalesce((p->>'conversa_ativa')::boolean, false), coalesce((p->>'tentativa')::smallint, 1))
    returning id into v_id;
  exception when unique_violation then
    select t.id, t.texto, t.turno, t.enviado, t.calado into v_feito
      from public.resumo_tarde t where t.dia = v_dia and t.phone_normalized = v_phone;
    return jsonb_build_object('ok', true, 'novo', false, 'id', v_feito.id, 'texto', v_feito.texto, 'turno', v_feito.turno,
                              'enviado', v_feito.enviado, 'calado', v_feito.calado);
  end;

  if v_enviado then
    -- a fonte NÃO é 'ai_briefing': o ai-business-monitor lê essa para saber se a MANHÃ chegou
    insert into public.whatsapp_send_queue (phone_normalized, message, source, priority, max_attempts, dedupe_key)
    values (v_phone, v_texto, 'ai_briefing_tarde', 4,
            least(greatest(coalesce((p->>'max_attempts')::integer, 10), 1), 30),
            'secretario_tarde:' || v_dia::text || ':' || v_phone);
    get diagnostics v_na_fila = row_count;
  end if;

  return jsonb_build_object('ok', true, 'novo', true, 'id', v_id, 'texto', v_texto, 'turno', v_turno,
                            'enviado', v_enviado, 'calado', v_calado, 'na_fila', v_na_fila);
end $$;

comment on function public.resumo_tarde_registrar(jsonb) is
  'Secretário: grava a tarde do dia uma vez só (rodar de novo devolve a gravada) e, com enviado=true (só formato ligado e manhã nova), enfileira o texto na mesma transação. Só service_role.';

-- ---------------------------------------------------------------------------------------------
-- 4. GRAVA DADO — OK NOMEADO: a chave do fechamento. Nasce 'desligado'.
--    Três fontes do mesmo padrão: esta linha, o 'desligado' de _shared/secretario/turno.ts (chave
--    ausente ou inválida = desligado) e a ausência da chave.
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('fechamento_formato', 'desligado',
   'Turno da tarde do resumo (17:30 seg–sex: fechamento, revisão de segunda e do 1º dia útil do mês): desligado = nada; sombra = monta e GUARDA (resumo_tarde), sem enviar; ligado = envia ao dono, só nos dias em que a manhã foi a nova. Voltar atrás = desligado.')
on conflict (key) do nothing;

-- O gatilho de produção tem de ser o de 20261015200000 (md5 conferido em 15/10/2026) ou já este: se alguém
-- mudou o gatilho por fora, a migration para aqui em vez de apagar a regra nova.
do $$
declare
  v_md5 text;
begin
  select md5(regexp_replace(lower(p.prosrc), '\s', '', 'g')) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_app_settings_chaves_do_dono';
  if v_md5 is not null and v_md5 not in ('42dded24d25e3fcf4cb6a05c0f18c16e', '4e65302e7fcfa0998c412ff6b20366ce') then
    raise exception 'o gatilho _app_settings_chaves_do_dono não é o esperado (md5 %): confira o corpo em produção antes de recriar', v_md5;
  end if;
end $$;

-- Igual ao de 20261015200000 (conferido em produção), com a chave nova no fim.
create or replace function public._app_settings_chaves_do_dono()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and not public.is_admin(v_uid) then
    if (tg_op <> 'INSERT' and old.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo'))
       or (tg_op <> 'DELETE' and new.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo')) then
      raise exception 'Só o administrador muda o salário mínimo e a regra do pró-labore.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_fluxo')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_fluxo') then
      raise exception 'Só o administrador liga ou desliga o fluxo de comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_conversa')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_conversa') then
      raise exception 'Só o administrador liga ou desliga a conversa dos comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'resumo_formato')
       or (tg_op <> 'DELETE' and new.key = 'resumo_formato') then
      raise exception 'Só o administrador muda o formato do resumo da manhã.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'fechamento_formato')
       or (tg_op <> 'DELETE' and new.key = 'fechamento_formato') then
      raise exception 'Só o administrador liga ou desliga o fechamento da tarde.' using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists app_settings_chaves_do_dono on public.app_settings;
create trigger app_settings_chaves_do_dono
  before insert or update or delete on public.app_settings
  for each row execute function public._app_settings_chaves_do_dono();

revoke all on function public._app_settings_chaves_do_dono() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. resumo_itens_acoes: a revisão respondida de uma vez ("D semana, F tira, G 15 dias")
--    Sobre as letras de HOJE (Brasília). Tudo ou nada: letra que não existe, repetida, ação inválida ou data
--    fora de (hoje, hoje + 90] → nada é gravado. Cada ação vale para todos os itens da letra.
-- ---------------------------------------------------------------------------------------------
create or replace function public.resumo_itens_acoes(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone  text := p->>'phone';
  v_modo   text := coalesce(p->>'modo', 'novo');
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_acoes  jsonb := p->'acoes';
  v_a      jsonb;
  v_letra  text;
  v_acao   text;
  v_ate    date;
  v_resp   text;
  v_letras text[] := '{}';
  v_faltam text[] := '{}';
  v_itens  jsonb := '[]'::jsonb;
  v_item   record;
begin
  if jsonb_typeof(v_acoes) is distinct from 'array' or jsonb_array_length(v_acoes) = 0 or jsonb_array_length(v_acoes) > 21 then
    return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'acoes');
  end if;

  -- 1ª volta: confere tudo antes de gravar qualquer coisa
  for v_a in select x from jsonb_array_elements(v_acoes) as x loop
    v_letra := upper(btrim(coalesce(v_a->>'letra', '')));
    v_acao := v_a->>'acao';
    v_resp := v_a->>'resposta';
    if v_letra !~ '^[A-DF-HJ-MP-RT-Z]$' or v_acao is null or v_acao not in ('feito', 'adiado', 'nao', 'tirado')
       or (v_resp is not null and v_resp not in ('semana', '15dias')) then
      return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'acao', 'letra', v_letra);
    end if;
    if v_letra = any(v_letras) then
      return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'letra_repetida', 'letra', v_letra);
    end if;
    v_letras := v_letras || v_letra;
    if v_acao = 'adiado' then
      begin
        v_ate := (v_a->>'ate')::date;
      exception when others then
        v_ate := null;
      end;
      if v_ate is null or v_ate <= v_hoje or v_ate > v_hoje + 90 then
        return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'ate', 'letra', v_letra);
      end if;
    end if;
    if not exists (select 1 from public.resumo_itens i
                    where i.phone_normalized = v_phone and i.modo = v_modo and i.dia = v_hoje and i.letra = v_letra and i.principal) then
      v_faltam := v_faltam || v_letra;
    end if;
  end loop;
  if cardinality(v_faltam) > 0 then
    return jsonb_build_object('ok', true, 'resultado', 'nao_achei', 'letras', to_jsonb(v_faltam));
  end if;

  -- 2ª volta: grava
  for v_a in select x from jsonb_array_elements(v_acoes) as x loop
    v_letra := upper(btrim(v_a->>'letra'));
    v_acao := v_a->>'acao';
    v_ate := case when v_acao = 'adiado' then (v_a->>'ate')::date else null end;
    v_resp := v_a->>'resposta';
    update public.resumo_itens i
       set acao = v_acao, acao_em = now(), adiado_ate = v_ate,
           historico = (case when jsonb_array_length(i.historico) >= 20 then i.historico - 0 else i.historico end)
                       || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
                            'acao', v_acao, 'em', now(), 'ate', v_ate, 'via', 'lote', 'resposta', v_resp)))
     where i.phone_normalized = v_phone and i.modo = v_modo and i.dia = v_hoje and i.letra = v_letra;
    select i.nome, i.tipo into v_item
      from public.resumo_itens i
     where i.phone_normalized = v_phone and i.modo = v_modo and i.dia = v_hoje and i.letra = v_letra and i.principal
     limit 1;
    v_itens := v_itens || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'letra', v_letra, 'nome', v_item.nome, 'tipo', v_item.tipo, 'acao', v_acao, 'ate', v_ate, 'resposta', v_resp)));
  end loop;
  return jsonb_build_object('ok', true, 'resultado', 'feito', 'itens', v_itens);
end $$;

comment on function public.resumo_itens_acoes(jsonb) is
  'Secretário: várias ações do dono de uma vez sobre as letras de hoje (Brasília) — a revisão da semana respondida numa mensagem. Tudo ou nada. Só service_role.';

-- ---------------------------------------------------------------------------------------------
-- 6. resumo_semana_responder: a pergunta da sexta (a ENVIADA mais recente dos últimos 4 dias)
-- ---------------------------------------------------------------------------------------------
create or replace function public.resumo_semana_responder(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone text := p->>'phone';
  v_resp  text := p->>'resposta';
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_linha record;
begin
  if v_resp is null or v_resp not in ('ajudou', 'pouco', 'atrapalhou') then
    return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'resposta');
  end if;
  select t.id, t.dia, t.resposta_semana into v_linha
    from public.resumo_tarde t
   where t.phone_normalized = v_phone and t.pergunta_semana and t.enviado
     and t.dia between v_hoje - 4 and v_hoje
   order by t.dia desc
   limit 1;
  if not found then
    return jsonb_build_object('ok', true, 'resultado', 'sem_pergunta');
  end if;
  update public.resumo_tarde set resposta_semana = v_resp, respondida_em = now() where id = v_linha.id;
  return jsonb_build_object('ok', true, 'resultado', case when v_linha.resposta_semana is null then 'gravado' else 'trocado' end,
                            'dia', v_linha.dia, 'antes', v_linha.resposta_semana, 'resposta', v_resp);
end $$;

comment on function public.resumo_semana_responder(jsonb) is
  'Secretário: grava a resposta da pergunta da sexta (ajudou, pouco, atrapalhou) na enviada mais recente dos últimos 4 dias; responder de novo troca. Só service_role.';

revoke all on function public.resumo_tarde_registrar(jsonb) from public, anon, authenticated;
revoke all on function public.resumo_itens_acoes(jsonb) from public, anon, authenticated;
revoke all on function public.resumo_semana_responder(jsonb) from public, anon, authenticated;
grant execute on function public.resumo_tarde_registrar(jsonb) to service_role;
grant execute on function public.resumo_itens_acoes(jsonb) to service_role;
grant execute on function public.resumo_semana_responder(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_t text := 'public.resumo_tarde';
  v_rpcs text[] := array['public.resumo_tarde_registrar(jsonb)', 'public.resumo_itens_acoes(jsonb)', 'public.resumo_semana_responder(jsonb)'];
  v_def text;
begin
  if not (select relrowsecurity from pg_class where oid = v_t::regclass) then
    raise exception 'RLS desligada em %', v_t;
  end if;
  if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert')
     or has_table_privilege('anon', v_t, 'update') or has_table_privilege('anon', v_t, 'delete') then
    raise exception 'anon ainda alcança %', v_t;
  end if;
  if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
     or has_table_privilege('authenticated', v_t, 'delete') then
    raise exception 'authenticated escreve direto em %', v_t;
  end if;
  if not has_table_privilege('service_role', v_t, 'select') or not has_table_privilege('service_role', v_t, 'insert')
     or not has_table_privilege('service_role', v_t, 'update') then
    raise exception 'service_role não alcança %', v_t;
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'resumo_tarde') <> 1
     or exists (select 1 from pg_policies
                 where schemaname = 'public' and tablename = 'resumo_tarde'
                   and (roles <> array['authenticated']::name[] or cmd <> 'SELECT'
                        or policyname <> 'resumo_tarde_admin_le' or position('is_admin' in qual) = 0)) then
    raise exception 'policy de resumo_tarde diferente da prevista (ou alcançando anon/public)';
  end if;
  foreach v_f in array v_rpcs loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'função da tarde exposta para anon: %', v_f;
    end if;
    if has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função da tarde exposta para authenticated: %', v_f;
    end if;
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'resumo_tarde_enviado_chk'
                    and conrelid = 'public.resumo_tarde'::regclass) then
    raise exception 'CHECK da sombra (resumo_tarde_enviado_chk) ausente';
  end if;
  if not exists (select 1 from public.app_settings where key = 'fechamento_formato') then
    raise exception 'chave fechamento_formato não foi criada';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'app_settings_chaves_do_dono'
                    and tgrelid = 'public.app_settings'::regclass and tgenabled <> 'D') then
    raise exception 'gatilho app_settings_chaves_do_dono ausente: o financeiro mudaria fechamento_formato';
  end if;
  v_def := pg_get_functiondef('public._app_settings_chaves_do_dono()'::regprocedure);
  if position('fechamento_formato' in v_def) = 0 or position('resumo_formato' in v_def) = 0
     or position('comprovante_conversa' in v_def) = 0 or position('comprovante_fluxo' in v_def) = 0
     or position('pro_labore_pelo_salario_minimo' in v_def) = 0 then
    raise exception 'o gatilho das chaves do dono não protege todas as chaves (fechamento, resumo, comprovantes, pró-labore)';
  end if;
  if has_function_privilege('anon', 'public._app_settings_chaves_do_dono()', 'execute')
     or has_function_privilege('authenticated', 'public._app_settings_chaves_do_dono()', 'execute') then
    raise exception 'gatilho das chaves do dono exposto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261015210000', 'resumo_tarde')
on conflict do nothing;
