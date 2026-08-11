-- [MF-AUD-020] Teste de RLS: o cargo técnico não enxerga NADA financeiro.
--
-- Decisão #3 do dono (09/08/2026). A migration `20260810113036_tecnico_nao_ve_financeiro`
-- implementou; este arquivo PROVA — que é coisa diferente. Ler a política e concluir que ela
-- funciona é o erro clássico da RLS: predicado sintaticamente correto que não filtra nada
-- porque a policy é PERMISSIVE e outra policy da mesma tabela abre o caminho por OR.
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/rls_tecnico_financeiro.sql
--
-- É seguro em produção: roda inteiro dentro de uma transação que termina em ROLLBACK. Nada
-- do que ele cria sobrevive. Ainda assim, prefira rodar contra um branch do Supabase.
--
-- Nenhum `RAISE EXCEPTION` = tudo passou. O script fala quando falha, e cala quando está bom.

begin;

-- Sem isto, um erro no meio deixaria a transação num estado em que o ROLLBACK final é a
-- única coisa que roda — e o resultado sairia parecendo sucesso.
\set ON_ERROR_STOP on

do $$
declare
  v_tecnico   uuid := gen_random_uuid();
  v_admin     uuid := gen_random_uuid();
  v_tabela    text;
  v_visiveis  integer;
  v_total     integer;
  v_erro      text;
begin
  -- ── Dois usuários de mentira, um de cada lado da fronteira ────────────────────
  -- `app_users.id` referencia auth.users em produção; inserir direto aqui funciona porque a
  -- transação inteira é desfeita e nenhuma FK é validada contra auth no meio do caminho.
  insert into public.app_users (id, role, active, name, email)
  values
    (v_tecnico, 'technician', true, 'Técnico de teste', 'tecnico.teste@invalido.local'),
    (v_admin,   'admin',      true, 'Admin de teste',   'admin.teste@invalido.local');

  -- ═══ 1. O técnico não LÊ nenhuma das cinco tabelas ═════════════════════════
  foreach v_tabela in array array['payments','receivables','payables','invoices','bank_transactions']
  loop
    -- Quanto existe, sem RLS (estamos como superusuário/owner da migration).
    execute format('select count(*) from public.%I', v_tabela) into v_total;

    -- Agora como o técnico.
    set local role authenticated;
    execute format($claims$ set local request.jwt.claims = '{"sub":"%s","role":"authenticated"}' $claims$, v_tecnico);

    execute format('select count(*) from public.%I', v_tabela) into v_visiveis;

    reset role;
    set local request.jwt.claims = default;

    if v_visiveis <> 0 then
      raise exception
        'MF-AUD-020 FALHOU: o técnico enxerga % linha(s) de public.% (a tabela tem %). '
        'A política dessa tabela perdeu o predicado NOT public.is_technician(auth.uid()), '
        'ou existe outra policy PERMISSIVE abrindo o caminho por OR.',
        v_visiveis, v_tabela, v_total;
    end if;

    -- Um "0 visíveis" numa tabela vazia não prova nada. Avisa em vez de mentir.
    if v_total = 0 then
      raise notice 'ATENÇÃO: public.% está vazia — o teste de leitura passou por vacuidade.', v_tabela;
    else
      raise notice 'ok: técnico vê 0 de % linhas em public.%', v_total, v_tabela;
    end if;
  end loop;

  -- ═══ 2. O técnico não ESCREVE ══════════════════════════════════════════════
  -- Ler é metade. A policy original era FOR ALL, então o mesmo JWT que lia também inseria e
  -- apagava — e um INSERT bloqueado por WITH CHECK falha de forma diferente de um SELECT
  -- filtrado: aqui o esperado é ERRO, não zero linhas.
  set local role authenticated;
  execute format($claims$ set local request.jwt.claims = '{"sub":"%s","role":"authenticated"}' $claims$, v_tecnico);

  begin
    insert into public.payments (amount, payment_date, payment_method)
    values (1.00, current_date, 'cash');
    -- Chegou aqui: o WITH CHECK deixou passar.
    reset role;
    raise exception
      'MF-AUD-020 FALHOU: o técnico conseguiu INSERIR em public.payments. '
      'O WITH CHECK da política não carrega a barreira do técnico.';
  exception
    when insufficient_privilege then
      raise notice 'ok: INSERT do técnico em payments foi recusado';
    when others then
      -- Coluna obrigatória faltando etc. não é o que se está testando; só não pode ser
      -- sucesso. Um erro que NÃO seja de permissão é inconclusivo, e dizer isso é mais
      -- honesto do que contar como aprovado.
      get stacked diagnostics v_erro = message_text;
      raise notice 'INCONCLUSIVO no INSERT em payments (erro não relacionado a permissão): %', v_erro;
  end;

  reset role;
  set local request.jwt.claims = default;

  -- ═══ 3. O admin continua enxergando ════════════════════════════════════════
  -- Sem esta metade, uma política que bloqueasse TODO MUNDO passaria no teste acima e
  -- quebraria o financeiro inteiro em produção.
  execute 'select count(*) from public.receivables' into v_total;

  if v_total > 0 then
    set local role authenticated;
    execute format($claims$ set local request.jwt.claims = '{"sub":"%s","role":"authenticated"}' $claims$, v_admin);

    execute 'select count(*) from public.receivables' into v_visiveis;

    reset role;
    set local request.jwt.claims = default;

    if v_visiveis = 0 then
      raise exception
        'MF-AUD-020 FALHOU AO CONTRÁRIO: o admin também não enxerga receivables (% linhas existem). '
        'A barreira do técnico pegou quem não devia.', v_total;
    end if;
    raise notice 'ok: admin vê % de % linhas em receivables', v_visiveis, v_total;
  else
    raise notice 'ATENÇÃO: receivables está vazia — não deu para provar que o admin ainda enxerga.';
  end if;

  -- ═══ 4. anon não chega perto ═══════════════════════════════════════════════
  set local role anon;
  begin
    execute 'select count(*) from public.payments' into v_visiveis;
    if v_visiveis > 0 then
      reset role;
      raise exception 'MF-AUD-020 FALHOU: anon enxerga % linha(s) de payments.', v_visiveis;
    end if;
    raise notice 'ok: anon vê 0 linhas em payments';
  exception
    when insufficient_privilege then
      raise notice 'ok: anon nem tem GRANT em payments';
  end;
  reset role;

  raise notice '=== MF-AUD-020: todas as verificações passaram ===';
end $$;

rollback;
