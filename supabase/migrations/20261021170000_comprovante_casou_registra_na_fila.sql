-- Comprovantes (21/10/2026, frente C): o comprovante (CMP-00001, …) que CASA com a conta a pagar em aberto deixa a
-- referência dele na proposta da fila do Extrato que saiu da fila.
--
-- O defeito (achado de 15/10/2026: comentário do T9 em supabase/tests/comprovantes_conciliacao.sql, commit e593bdc5;
-- a nota esperada está em spec-f3.md, item 2 da explicação da linha): no "sim" do dono, o
-- ramo 2 de _comprovante_linha_explicar (20261012100000:1181-1197) chama a conciliar_lancamento (a de
-- 20261002140000:710-846), que JÁ tira da fila as propostas pendentes da linha com a nota "Casada com um lançamento
-- que já existia" e sem decided_at (20261002140000:817-819). O update da F3 que vinha logo depois procurava só
-- 'pending' e por isso nunca achava nada: a fila não guardava qual CMP casou nem quando. No ensaio PGlite não
-- aparecia porque o dublê da conciliar_lancamento não mexe na fila.
--
-- O conserto muda SÓ esse ramo: antes de casar, guarda (e prende com for update) os ids das propostas pendentes da
-- linha; a conciliar_lancamento roda igual a antes; depois, ESSAS propostas ficam com "Casada com a conta do
-- CMP-NNNNN" (a nota que a F3 já queria gravar), decided_at = agora e decided_by = o dono do "sim" (p_autor, já
-- conferido como o dono admin em _comprovante_ligar/_comprovante_gravar e o mesmo autor que a conciliar_lancamento
-- grava na trilha), como nos outros caminhos que gravam decided_at (aprovar, recusar, casar pela fila do
-- finance-review). O status continua 'superseded' (a proposta sai da fila como antes); conta a pagar, pagamento,
-- linha do extrato e trilha da conciliação não mudam. A nota de
-- proposta 'superseded' não aparece em tela nenhuma (o Extrato lê só a pendente: extrato_a_tratar, extrato_da_conta,
-- useFinanceReviewQueue; os "lançados sozinhos" leem só 'approved'): o dono vê o mesmo extrato. Se o casar recusar,
-- o bloco desfaz tudo e a proposta segue pendente, como antes.
--
-- Casos passados (SELECT em produção, 21 e 22/10/2026): 2 CMPs, nenhum com ligação ao extrato; nenhuma proposta da fila
-- numa linha de CMP; 1 proposta "Casada com um lançamento que já existia" (30/09, antes dos comprovantes). Sem
-- preenchimento retroativo.
--
-- Recria a função SÓ se o corpo em produção for o de 20261012100000 (md5 do prosrc normalizado — A-Z em minúscula,
-- sem espaços — c5dc1d01b4d3dd02619f8b16d95fc54e, conferido por SELECT em 21 e 22/10/2026) ou já este (2550640a538f87e7b11380cd7b961e72, 2ª
-- aplicação); qualquer outro corpo, ou a função ausente, PARA a migration sem mudar nada. Sem dado gravado, sem cron,
-- sem tabela. Idempotente.
--
-- Versão 20261021170000 (nasceu como 20261021120000, renomeada na revisão de 22/10/2026): vem depois da última
-- aplicada em produção (20261021160000, tecnico_nao_troca_cliente_da_os — SELECT em schema_migrations, 22/10/2026).
-- Se outra migration de versão maior for aplicada antes desta, renomear de novo antes de publicar.

-- ---------------------------------------------------------------------------------------------
-- 0. A guarda do corpo, ANTES de recriar.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_md5 text;
begin
  select md5(regexp_replace(translate(p.prosrc, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\s+', '', 'g'))
    into v_md5
    from pg_proc p
   where p.oid = to_regprocedure('public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean)');
  if v_md5 is null or v_md5 not in ('c5dc1d01b4d3dd02619f8b16d95fc54e', '2550640a538f87e7b11380cd7b961e72') then
    raise exception '_comprovante_linha_explicar não é a de 20261012100000 (md5 %): confira o corpo em produção antes de recriar', coalesce(v_md5, 'ausente');
  end if;
  if to_regprocedure('public.conciliar_lancamento(text, uuid, uuid, uuid)') is null then
    raise exception 'conciliar_lancamento(text, uuid, uuid, uuid) não existe';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. _comprovante_linha_explicar: o CMP que casa deixa a referência na proposta que saiu da fila
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261012100000:1068-1262 IGUAL + v_fila no declare + no ramo 2 (casar) os ids das pendentes presos antes
-- da conciliar_lancamento e o update da F3 por esses ids (pending ou superseded) no lugar do "where status = 'pending'",
-- agora com decided_by = p_autor
create or replace function public._comprovante_linha_explicar(c public.comprovantes, p_tx uuid, p_autor uuid, p_casar boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  t record;
  v_pay record;
  v_cmp_pay record;
  v_prop record;
  v_ef jsonb := public._comprovante_efetivo(c);
  v_cat text := v_ef->>'categoria';
  v_os uuid := case when c.destino = 'os' then c.destino_os_id end;
  v_forn text := public._comprovante_fornecedor(c)->>'nome';
  v_anots uuid[];
  v_como text := 'aguardando';
  v_payable uuid;
  v_anot uuid;
  v_anot_criada boolean := false;
  v_aplicou boolean := false;
  v_proposta uuid;
  v_corr jsonb := '{}'::jsonb;
  v_msgs text[] := '{}';
  v_explicada boolean := false;
  v_pend text;
  v_aviso text;
  v_erro text;
  v_ligou_despesa boolean := false;
  v_lancado_depois boolean := false;
  v_conflito jsonb;
  v_t text;
  v_corr_r jsonb;
  v_cat_existente text;
  v_fila uuid[];
begin
  select x.id, x.transaction_date, x.counterparty_name, x.merchant_name, x.description, x.nome_pelo_comprovante
    into t from public.bank_transactions x where x.id = p_tx for update;
  if not found then
    raise exception 'A linha do extrato não existe mais.' using errcode = '22023';
  end if;
  -- as anotações deste CMP: a da F2 e as que a F3 criou/usou nas ligações
  select array_agg(distinct a) into v_anots
    from (select c.anotacao_id as a
          union all
          select (e->>'anotacao_id')::uuid from jsonb_array_elements(c.efeitos) e
           where e->>'tipo' in ('ligar_linha', 'anotar', 'anexar_anotacao') and e->>'anotacao_id' is not null) s
   where a is not null;
  v_anots := coalesce(v_anots, '{}'::uuid[]);

  select p.id, p.status into v_pay from public.payables p
   where p.bank_transaction_id = p_tx and p.status <> 'cancelled'
   order by p.divisao_id nulls first, p.created_at, p.id
   limit 1;
  select p.id, p.status, p.bank_transaction_id into v_cmp_pay from public.payables p where p.id = c.payable_id;

  if v_pay.id is not null then
    -- 1. a linha já virou lançamento
    if v_pay.id = c.payable_id
       or exists (select 1 from jsonb_array_elements(c.efeitos) e
                   where e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = p_tx::text and not e ? 'desligado_em'
                     and e->'aprovado'->>'payable_id' = v_pay.id::text) then
      -- é o lançamento do próprio CMP (anexado na F2, a conta dele que ganhou a linha, ou o que o SIM do
      -- dono aprovou: resposta 3)
      v_como := 'anexou';
      v_payable := v_pay.id;
      v_explicada := true;
    elsif v_cmp_pay.id is null or v_cmp_pay.status = 'cancelled' then
      v_payable := v_pay.id;
      if p_casar then
        -- anexa no SIM do dono (a pergunta mostrou "uso o lançamento que já existe dela"): resposta 8 —
        -- só preenche o que está vazio (OS, categoria; o "antes" fica); categoria diferente fica e avisa
        v_corr_r := public._comprovante_corrigir_lancamento(v_pay.id, v_cat, v_os, c.codigo, p_autor);
        if v_corr_r->>'mensagem' is not null then
          v_msgs := v_msgs || (v_corr_r->>'mensagem');
        end if;
        v_corr := coalesce(v_corr_r->'corrigido', '{}'::jsonb);
        if jsonb_typeof(v_corr_r->'diferente') = 'object' then
          v_cat_existente := v_corr_r->'diferente'->>'categoria';
          v_aviso := 'categoria_existente_diferente';
        end if;
        v_como := 'anexou';
      else
        -- varredura: a linha que o CMP ligou foi APROVADA pelo dono no Extrato (ou lançada por
        -- outro caminho) depois da ligação. Só adota o lançamento: a categoria e a OS que o dono
        -- escolheu ao aprovar ficam (nada é corrigido sem SIM). O "como" de antes fica (quem chama
        -- não o troca) e lancado_depois marca que o lançamento NÃO é o que existia ao ligar: o
        -- cancelamento do CMP recusa (desfaz-se pelo Extrato).
        v_como := null;
        v_lancado_depois := true;
      end if;
      if c.so_expense_id is not null then
        update public.service_order_expenses s set linked_payable_id = v_pay.id
         where s.id = c.so_expense_id and s.linked_payable_id is null;
        v_ligou_despesa := found;
      end if;
      update public.anotacoes_do_extrato a
         set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = c.codigo || ': a linha do banco já foi lançada'
       where a.id = any (v_anots) and a.status = 'aguardando';
      v_explicada := true;
    elsif v_cmp_pay.status in ('pending', 'overdue', 'partially_paid') and v_cmp_pay.bank_transaction_id is null then
      -- o CMP anexou uma conta a pagar EM ABERTO e a linha já virou OUTRO lançamento: o mesmo gasto
      -- contado duas vezes. Não liga (quem chama recusa): o dono cancela uma das duas no Financeiro.
      v_conflito := jsonb_build_object('conta_aberta_id', v_cmp_pay.id, 'lancamento_id', v_pay.id);
      v_pend := 'classificar_no_extrato';
      v_aviso := 'conta_aberta_e_linha_lancada';
    else
      -- o CMP já tem OUTRO lançamento (pago por outra linha ou no Caixa): não mexe; o dono confere no Extrato
      v_pend := 'classificar_no_extrato';
      v_aviso := 'linha_lancada_em_outro';
      v_explicada := true;
    end if;

  elsif v_cmp_pay.id is not null and v_cmp_pay.status in ('pending', 'overdue', 'partially_paid')
        and v_cmp_pay.bank_transaction_id is null then
    -- 2. o CMP tem conta a pagar em aberto (anexada pela F2): casa — só no SIM do dono
    if p_casar then
      begin
        -- (21/10/2026) as propostas da linha que estão na fila AGORA, presas até o fim da transação. A
        -- conciliar_lancamento as tira da fila com a nota dela ("Casada com um lançamento que já existia") e sem
        -- a hora; logo depois ESTAS MESMAS ganham a referência do CMP, a hora e quem decidiu (o dono do "sim", o
        -- mesmo autor da trilha da conciliação) — antes o update procurava só 'pending' e nunca achava nada. Se o
        -- casar recusar, nada daqui fica: a proposta segue na fila.
        select coalesce(array_agg(f.id), '{}'::uuid[]) into v_fila
          from (select q.id from public.finance_review_queue q
                 where q.bank_transaction_id = p_tx and q.status = 'pending'
                 for update) f;
        perform public.conciliar_lancamento('payable', c.payable_id, p_tx, p_autor);
        update public.finance_review_queue q
           set status = 'superseded', decision_note = 'Casada com a conta do ' || c.codigo, decided_at = now(), decided_by = p_autor, updated_at = now()
         where q.id = any (v_fila) and q.status in ('pending', 'superseded');
        v_como := 'casou';
        v_payable := c.payable_id;
        v_explicada := true;
      exception when others then
        get stacked diagnostics v_t = message_text;
        v_erro := left(v_t, 200);
      end;
    end if;

  else
    -- 3. a linha tem proposta pendente na fila do Extrato
    select q.id, q.kind, q.evidencia into v_prop from public.finance_review_queue q
     where q.bank_transaction_id = p_tx and q.status = 'pending'
     order by q.created_at desc, q.id
     limit 1;
    if v_prop.id is not null then
      v_proposta := v_prop.id;
      if v_prop.kind <> 'create_payable' then
        -- transferência, anomalia...: o dono decide no Extrato
        v_pend := 'classificar_no_extrato';
        v_explicada := true;
      elsif coalesce(v_prop.evidencia, '{}'::jsonb) ? 'anotacao' then
        if (v_prop.evidencia->'anotacao'->>'id')::uuid = any (v_anots) then
          v_como := 'classificou';
          v_anot := (v_prop.evidencia->'anotacao'->>'id')::uuid;
        else
          -- outra anotação (do dono, pela tela/assistente) já classificou: não passa por cima
          v_pend := 'classificar_no_extrato';
        end if;
        v_explicada := true;
      else
        -- a anotação da F2 que ainda espera, ou uma nova (documento nulo: a linha é a escolhida)
        select a.id into v_anot from public.anotacoes_do_extrato a
         where a.id = any (v_anots) and a.status = 'aguardando'
         order by a.criada_em limit 1;
        if v_anot is null then
          -- PESSOAL pago pela empresa (resposta 1): o favorecido é o sócio (o pró-labore desconta)
          insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, documento, fornecedor_id,
                                                   favorecido_id, categoria, os_id, descricao, criada_por)
          values ('debit', c.valor_confirmado, c.data_confirmada, true, null, public._comprovante_fornecedor_efetivo(c, null),
                  case when c.destino = 'pessoal' then nullif(v_ef->>'pagador_id', '')::uuid end, v_cat, v_os,
                  public._comprovante_descricao(c),
                  p_autor)
          returning id into v_anot;
          v_anot_criada := true;
        end if;
        perform public._aplicar_anotacao(v_anot, v_prop.id);
        v_aplicou := true;
        v_como := 'classificou';
        v_explicada := true;
      end if;
    end if;
    -- 4. sem proposta (cartão PENDING, ou o finance-review não rodou): a varredura tenta de novo
  end if;

  -- 5. a linha sem nome mostra a loja do CMP no Extrato (só se ainda não tem; nunca no conflito, que não liga)
  if v_erro is null and v_conflito is null and nullif(btrim(coalesce(t.counterparty_name, '')), '') is null
     and nullif(btrim(coalesce(t.merchant_name, '')), '') is null
     and public._nome_da_linha(t.counterparty_name, t.description) is null and t.nome_pelo_comprovante is null then
    update public.bank_transactions x
       set nome_pelo_comprovante = left(coalesce(v_forn, public._comprovante_tipo_no_texto(c.tipo)) || ' · ' || c.codigo, 160)
     where x.id = p_tx and x.nome_pelo_comprovante is null;
  end if;

  return jsonb_build_object(
    'tipo', 'ligar_linha', 'bank_transaction_id', p_tx, 'origem', null, 'nivel', null, 'em', now(),
    'como', v_como, 'proposta_id', v_proposta, 'anotacao_id', v_anot, 'anotacao_criada', v_anot_criada,
    'payable_id', v_payable, 'corrigido', v_corr, 'mensagens', to_jsonb(v_msgs),
    'linha', public._comprovante_linha_curta(p_tx), 'ligou_despesa', v_ligou_despesa,
    'lancado_depois', v_lancado_depois, 'categoria_existente', v_cat_existente,
    '_explicada', v_explicada, '_pendencia', v_pend, '_aviso', v_aviso, '_erro', v_erro, '_aplicou', v_aplicou,
    '_conflito', v_conflito);
end $$;

comment on function public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean) is
  'Explica a linha do extrato ligada a um CMP (anexa, casa a conta em aberto, classifica a proposta pela anotação). Ao casar (21/10/2026), a proposta que saiu da fila guarda "Casada com a conta do CMP-N", a hora e quem decidiu. Helper interno: sem grant.';

-- ---------------------------------------------------------------------------------------------
-- 2. Privilégios: helper interno, sem grant para ninguém (como em 20261011302000 e 20261012100000)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 3. Prova: a migration falha se a porta ficou aberta ou se o corpo não é o esperado.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text := 'public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean)';
  v_def text;
  v_md5 text;
begin
  if has_function_privilege('anon', v_f, 'execute') then
    raise exception '_comprovante_linha_explicar exposta para anon';
  end if;
  if has_function_privilege('authenticated', v_f, 'execute') then
    raise exception '_comprovante_linha_explicar exposta para authenticated';
  end if;
  if has_function_privilege('service_role', v_f, 'execute') then
    raise exception 'helper interno dos comprovantes alcançável pela service_role: _comprovante_linha_explicar';
  end if;
  select md5(regexp_replace(translate(p.prosrc, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\s+', '', 'g'))
    into v_md5 from pg_proc p where p.oid = v_f::regprocedure;
  if v_md5 is distinct from '2550640a538f87e7b11380cd7b961e72' then
    raise exception '_comprovante_linha_explicar não ficou com o corpo desta migration (md5 %)', coalesce(v_md5, 'ausente');
  end if;
  v_def := pg_get_functiondef(v_f::regprocedure);
  if position('q.id = any (v_fila)' in v_def) = 0 or position('for update) f' in v_def) = 0
     or position('''Casada com a conta do '' || c.codigo' in v_def) = 0 or position('decided_by = p_autor' in v_def) = 0 then
    raise exception '_comprovante_linha_explicar sem a referência do CMP (ou sem quem decidiu) na proposta que saiu da fila';
  end if;
  -- a prova de 20261012100000 continua valendo: a descrição do lançamento nasce num lugar só
  if position('_comprovante_descricao' in v_def) = 0 then
    raise exception '_comprovante_linha_explicar não usa _comprovante_descricao';
  end if;
  if position('security definer' in lower(v_def)) = 0 or position('search_path to ''''' in lower(v_def)) = 0 then
    raise exception '_comprovante_linha_explicar precisa ser security definer com search_path vazio';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261021170000', 'comprovante_casou_registra_na_fila')
on conflict do nothing;
