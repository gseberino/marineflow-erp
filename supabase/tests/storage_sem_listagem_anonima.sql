-- Prova: ninguém anônimo LISTA os buckets com dado de cliente
-- (migration 20260926210000_buckets_sem_listagem_anonima).
--
-- Ler a regra e concluir que ela funciona é o erro clássico da RLS: basta outra regra
-- PERMISSIVE do mesmo bucket, criada à mão no painel, para abrir o caminho por OR. Aqui a
-- prova é olhar com os olhos do anônimo — contando pela tabela e pela própria função de
-- listagem que a API do Storage chama.
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/storage_sem_listagem_anonima.sql --output json
--
-- Seguro em produção: a transação é READ ONLY e termina em ROLLBACK.
--
-- Antes da migration este arquivo FALHA (26/09/2026: o anônimo via 6 objetos em signatures e
-- 3 em whatsapp_status) — é o vermelho do teste. Depois dela, a tabela final tem que mostrar
-- ZERO nas duas colunas dos quatro buckets, e nenhum RAISE pode ter disparado.
--
-- A parte 2 olha como LOGADO, e aí o perfil importa: as regras chamam auth.uid(), que lê o
-- request.jwt.claims. Sem ele, `set role authenticated` é um logado sem ninguém dentro — e a
-- conta sai errada. Cada olhar põe um usuário nas claims com set_config(..., true), local à
-- transação, como o PostgREST faz. Nada é gravado: a transação é read only.

begin transaction read only;

do $$
declare
  v_bucket   text;
  v_total    integer;
  v_anon     integer;
  v_listagem integer;
  v_uid      uuid;
  v_dono     text;
  v_visto    integer;
  v_vazou    integer;
  v_esperado integer;
  v_sobra    text;
begin
  -- ═══ 1. O anônimo não enxerga nada nos quatro buckets ═══════════════════════════
  foreach v_bucket in array array['signatures', 'expense-receipts', 'service-order-photos', 'whatsapp_status']
  loop
    select count(*) into v_total from storage.objects where bucket_id = v_bucket;

    set local role anon;
    select count(*) into v_anon from storage.objects where bucket_id = v_bucket;
    -- A raiz da listagem: é por aqui que se descobre os ids de OS dentro de signatures.
    select count(*) into v_listagem from storage.search('', v_bucket);
    reset role;

    if v_anon <> 0 or v_listagem <> 0 then
      raise exception
        'FALHOU: o anônimo enxerga % objeto(s) e lista % item(ns) na raiz de % (o bucket tem %). '
        'Sobrou regra de SELECT para anon/public nesse bucket.',
        v_anon, v_listagem, v_bucket, v_total;
    end if;
  end loop;

  -- ═══ 2. Logado enxerga o que a tabela dona do caminho deixa — e só isso ═══════════
  --
  --   expense-receipts      expenses/<os>/  despesa   (service_order_expenses: qualquer logado)
  --                         deposits/<os>/  SINAL     (payments: só admin/financeiro) + quem subiu
  --   service-order-photos  <os>/           foto      (service_order_photos: qualquer logado)
  --                         surveys/<id>/   levantam. (service_surveys: menos vendedor externo)
  --
  -- Enxergar de MENOS também é falha: "Excluir esta foto" e "remover comprovante" apagariam ZERO
  -- objetos sem erro, e a foto do levantamento (upsert) deixaria de subir.

  -- 2a. Logado comum. Um uuid que não está em app_users é, para estas regras, exatamente o
  --     técnico ou o vendedor interno: nem admin/financeiro, nem vendedor externo, dono de nada.
  v_uid := gen_random_uuid();
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) filter (where name like 'expenses/%'), count(*) filter (where name not like 'expenses/%')
    into v_visto, v_vazou
    from storage.objects where bucket_id = 'expense-receipts';
  reset role;
  select count(*) into v_esperado from storage.objects
   where bucket_id = 'expense-receipts' and name like 'expenses/%';
  if v_vazou <> 0 then
    raise exception 'FALHOU: logado comum (técnico/vendedor) enxerga % comprovante(s) fora de expenses/ — sinal é do financeiro.', v_vazou;
  end if;
  if v_visto <> v_esperado then
    raise exception 'FALHOU: logado comum enxerga % de % comprovante(s) de despesa — "remover comprovante" vai apagar zero em silêncio.', v_visto, v_esperado;
  end if;

  set local role authenticated;
  select count(*) into v_visto from storage.objects where bucket_id = 'service-order-photos';
  reset role;
  select count(*) into v_esperado from storage.objects where bucket_id = 'service-order-photos';
  if v_visto <> v_esperado then
    raise exception 'FALHOU: logado comum enxerga % de % foto(s) — "Excluir esta foto" e o upsert do levantamento vão falhar.', v_visto, v_esperado;
  end if;

  -- 2b. Admin/financeiro: um usuário real e ativo (o cargo vem de app_users). Enxerga tudo.
  select id into v_uid from public.app_users
   where role in ('admin', 'financial') and active order by role limit 1;
  if v_uid is null then
    raise exception 'FALHOU: não há admin/financeiro ativo em app_users para conferir a leitura do sinal.';
  end if;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  foreach v_bucket in array array['expense-receipts', 'service-order-photos']
  loop
    select count(*) into v_total from storage.objects where bucket_id = v_bucket;
    set local role authenticated;
    select count(*) into v_visto from storage.objects where bucket_id = v_bucket;
    reset role;
    if v_visto <> v_total then
      raise exception 'FALHOU: admin/financeiro enxerga % de % objeto(s) de %.', v_visto, v_total, v_bucket;
    end if;
  end loop;

  -- 2c. Quem subiu um comprovante de sinal enxerga o seu (o "remover comprovante" do diálogo
  --     de sinal apaga o que o próprio usuário acabou de anexar) e nenhum alheio.
  for v_dono in
    select distinct o.owner_id from storage.objects o
     where o.bucket_id = 'expense-receipts' and o.name like 'deposits/%' and o.owner_id is not null
       and not exists (select 1 from public.app_users u
                        where u.id::text = o.owner_id and u.role in ('admin', 'financial') and u.active)
     limit 20
  loop
    perform set_config('request.jwt.claim.sub', v_dono, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_dono, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) filter (where owner_id = v_dono), count(*) filter (where owner_id is distinct from v_dono)
      into v_visto, v_vazou
      from storage.objects where bucket_id = 'expense-receipts' and name like 'deposits/%';
    reset role;
    select count(*) into v_esperado from storage.objects
     where bucket_id = 'expense-receipts' and name like 'deposits/%' and owner_id = v_dono;
    if v_visto <> v_esperado or v_vazou <> 0 then
      raise exception 'FALHOU: o dono % enxerga % de % sinal(is) seu(s) e % alheio(s).', v_dono, v_visto, v_esperado, v_vazou;
    end if;
  end loop;

  -- 2d. Vendedor externo: não enxerga foto de levantamento nem sinal alheio; o resto das fotos
  --     sim. O cargo só existe com linha em app_users — em 26/09/2026 não havia nenhum ativo, e
  --     aí a conferência cai para o texto das regras (sem gravar um usuário de teste).
  select id into v_uid from public.app_users where role = 'external_seller' and active limit 1;
  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) filter (where name like 'surveys/%'), count(*) filter (where name not like 'surveys/%')
      into v_vazou, v_visto
      from storage.objects where bucket_id = 'service-order-photos';
    reset role;
    select count(*) into v_esperado from storage.objects
     where bucket_id = 'service-order-photos' and name not like 'surveys/%';
    if v_vazou <> 0 or v_visto <> v_esperado then
      raise exception 'FALHOU: vendedor externo enxerga % foto(s) de levantamento e % de % foto(s) de OS.', v_vazou, v_visto, v_esperado;
    end if;
    set local role authenticated;
    select count(*) into v_vazou from storage.objects
     where bucket_id = 'expense-receipts' and name like 'deposits/%' and owner_id is distinct from v_uid::text;
    reset role;
    if v_vazou <> 0 then
      raise exception 'FALHOU: vendedor externo enxerga % comprovante(s) de sinal alheio(s).', v_vazou;
    end if;
  else
    raise notice 'sem vendedor externo ativo em app_users: surveys/ conferido pelo texto das regras';
    select string_agg(policyname, ', ') into v_sobra
      from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and cmd in ('SELECT', 'ALL')
       and roles && array['authenticated', 'public']::name[]
       and coalesce(qual, '') ~ '''service-order-photos'''
       and not (position('''surveys/%''' in qual) > 0 and position('is_external_seller' in qual) > 0);
    if v_sobra is not null then
      raise exception 'FALHOU: regra de leitura de service-order-photos que não esconde surveys/ do vendedor externo: %', v_sobra;
    end if;
  end if;
end $$;

-- A tabela para o relatório. Depois da migration: tudo ZERO.
set local role anon;
select current_user as papel,
       b.id as bucket,
       (select count(*) from storage.objects o where o.bucket_id = b.id) as objetos_visiveis,
       (select count(*) from storage.search('', b.id)) as itens_na_raiz_pela_listagem
  from (values ('signatures'), ('expense-receipts'), ('service-order-photos'), ('whatsapp_status')) as b(id)
 order by 2;

rollback;
