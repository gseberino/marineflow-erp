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

begin transaction read only;

do $$
declare
  v_bucket   text;
  v_total    integer;
  v_anon     integer;
  v_listagem integer;
  v_logado   integer;
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

  -- ═══ 2. Logado continua enxergando o que o código precisa ═══════════════════════
  -- Sem isto, "Excluir esta foto" e "remover comprovante" apagariam ZERO objetos sem erro, e a
  -- foto do levantamento (upsert) deixaria de subir.
  foreach v_bucket in array array['expense-receipts', 'service-order-photos']
  loop
    select count(*) into v_total from storage.objects where bucket_id = v_bucket;

    set local role authenticated;
    select count(*) into v_logado from storage.objects where bucket_id = v_bucket;
    reset role;

    if v_logado <> v_total then
      raise exception
        'FALHOU: logado enxerga % de % objeto(s) de % — remove()/upsert da tela vão falhar em silêncio.',
        v_logado, v_total, v_bucket;
    end if;
  end loop;
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
