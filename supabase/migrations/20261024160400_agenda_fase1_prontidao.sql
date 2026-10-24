-- Agenda de Produção, Fase 1 ("O que eu tenho que fazer"), pacote P3: carteira, resolvedores, duração, presença,
-- prontidão e capacidade — tudo derivado no banco, com p_hoje.
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§3, §5.4, §6). Plano: plano-final.md §4.2, §4.3, §4.7; revisão §4–§7.
-- Depende de 20261024160000 (tabelas), 160100 (calendário e textos curtos), 160200 (semente) e 160300 (material).
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas de LEITURA e o create or replace de os_material_sincronizar_carteira,
-- mesma assinatura e ACL; não grava dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o dono pergunta "o que eu tenho que fazer?", "como tá a semana?", "quando fica livre?" e tem de receber a
-- verdade do banco, com quem trava cada OS. O modelo nunca calcula data, duração nem capacidade: estas funções
-- calculam, e as leituras com texto pronto (160500) só montam a frase.
--
-- O QUE MUDA (todas STABLE, security invoker, search_path fixo; nenhuma grava):
--   1. os_carteira(p_hoje): as OS ativas (STATUS_OS_ATIVAS) + orçamento aprovado ou esperando sinal, sem os
--      agrupados em outro, por número. Com a data de aprovação (conversão, senão assinatura, senão criação, no dia
--      de Brasília), o sinal previsto/pago/pendente (receivables.is_deposit) e a janela antiga (scheduled_*).
--      os_material_sincronizar_carteira (160300) passa a percorrer esta função: uma fonte só para a carteira.
--   2. agenda_resolver_os(p_ref, p_hoje, p_para_aprovar): a OS que o dono quis dizer. Número com a MESMA leitura de
--      pareceNumeroDeOS/localizarOrdem (os-referencia.ts, documentos-pdf.ts): "OS-00112", "ORÇ-00112", "orc 112",
--      "112"; número que existe como ORÇ e como OS = ambíguo. Nome (cliente ou embarcação) só DENTRO da carteira;
--      com p_para_aprovar, nos orçamentos enviados (e, se não achar, em todos os rascunhos). Ambíguo devolve a
--      pergunta pronta com os números; fora da carteira diz o status ("A OS-00050 já foi concluída.").
--   3. agenda_resolver_pessoa(p_ref, p_autor, p_hoje): "eu", "mim", "comigo", "você" e o 1º nome do sócio → o
--      sócio ligado ao login; a equipe (cadastro de diarista vigente) pelo 1º nome, sem acento.
--   4. _agenda_classe_do_fornecedor(fornecedor): marketplace pelo nome; entrega_local pelo município
--      (agenda_config.municipios_locais); distribuidor_sc_pr pela UF; outro_estado; sem cidade e sem UF = null
--      (desconhecida). _agenda_prazo_da_classe dá os dias úteis da classe (agenda_config.prazo_classe_du).
--   5. os_duracao_sugerida(OS): a faixa "pelo valor" — mão de obra líquida (sem o material de texto livre que
--      entra na compra) ÷ mo_por_diaria_preco a ÷ mo_por_diaria_real, e as horas diretas ÷ jornada_horas; 1 pessoa
--      quando o realista cabe numa diária-pessoa, senão equipe_sugerida; dias arredondados ao meio dia; o texto
--      "1,5 a 3 dias com 2 pessoas (estimativa minha, pelo valor)". Sem base → pergunta.
--   6. os_presenca_do_dono(OS): o que o dono disse, ou a regra (d05): sempre em diagnóstico, comissionamento/
--      parametrização e marina sem OS concluída antes; senão abre e fecha.
--   7. os_prontidao(OS, p_hoje): o estado da OS e as restrições com quem destrava (dono, cliente, fornecedor,
--      terceiro): o material efetivo (conta bruta + os_material) com os níveis A–E, "material não conferido",
--      "tem peça embutida?", "compre até" (programação para trás), o início mínimo (chegada + folga_material_du,
--      SEM folga remota), o prazo efetivo e a razão crítica. os_prontidao_carteira(p_hoje): a carteira inteira.
--   8. agenda_capacidade(de, ate, p_hoje): por pessoa × dia × turno (fim de semana, feriado, indisponível, sem
--      padrão, livre com os meios-dias esperados) e agenda_capacidade_semanal(p_hoje): o ÚNICO número
--      comprometível (Σ frequências × carga_max; o dono só entra com o padrão dele) e o aviso de diárias
--      faltando.
--   Auxiliares: _agenda_dono (o sócio do login, ou o único sócio), _agenda_linha_curta ("Conversão do
--   sistema…"), _agenda_rotulo_os (o status em português) e _agenda_itens ("1 item", "4 itens").
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase1_prontidao.sql):
--   · só o fato INFORMADO (fonte dono/fornecedor/nfe/pix) muda o item, como em aplicar_os_material (P2): a linha
--     que a sincronização copiou é espelho da conta bruta e, velha, esconderia uma falta. O resto vem da conta
--     bruta (estoque cobre = A; OC = a caminho, com a previsão e a data da OC).
--   · o item de OC de texto livre da OS que já foi RECEBIDO sai da conta bruta; aqui ele continua, no nível A
--     (sem isso, o compressor que chegou faria a OS-00104 "voltar" a não ter material conferido).
--   · "comprado/a caminho" do dono que vale para menos do que a OS pede hoje (a quantidade subiu) volta a falta;
--     "na mão" só é A com a quantidade completa contra a conta de HOJE, não só contra a linha.
--   · agenda_resolver_pessoa ganha p_hoje (o cadastro de diarista "vigente" precisa de uma data).
--   · "compre até" só para o que falta SEM compra combinada: com compra_prevista_em o início já sai dela
--     ("pronto a partir de qui 29/10, se a compra sair ter 27/10").
--   · OS fora da carteira (cancelada, agrupada, orçamento não aprovado) ganha o estado fora_da_carteira, com o
--     status em português; o material e a duração continuam calculados (o "se o cliente aprovar" usa).
--
-- REVISÃO DA FASE 1 (24/10, provadas nos mesmos testes):
--   · meios-dias de quem vai só de manhã ou só à tarde = 1 turno em cada dia que o serviço ocupa (ceil(dias)), não
--     dias × 1: "meio dia, o João à tarde" é 1 meio-dia (0,5 diária), não 0,25.
--   · comprado/a caminho informado sem data de compra conta do dia em que o dono contou (conferido_em): a chegada
--     estimada não anda para a frente todo dia e a previsão vence ("chegou?").
--   · compra combinada (vou comprar, dia que não passou) sem prazo de entrega conhecido não entra no "N itens a
--     comprar: de quem e quando?": vira a restrição compra_sem_prazo, que pergunta só o que falta ("quando chega a
--     compra de ter 27/10?" com fornecedor; "de quem é a compra de ter 27/10?" sem).
--   · item parcial: o texto começa por "3 de 8 na mão, faltam 5: ".
--   · orçamento aprovado e nunca convertido (ou sinal pendente): as restrições de material deixam de travar (bloqueia
--     false) até a conversão e o sinal; a principal do dono passa a ser "converter ou arquivar?".
--   · textos: "em espera até sex 30/10" sem o "(rever sex 30/10)" repetido; o "não encontrei" por nome sem artigo
--     ('Não encontrei "Maria" entre os serviços da carteira.', com as palavras que buscam, como o dono falou).
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum dado, get_os_purchase_needs, count_purchase_shortages, as leituras do
-- Secretário e da tela.
--
-- ORDEM DE LIGAR: depois de 20261024160000..160300; antes de 20261024160500 (as leituras com texto chamam estas).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase1_prontidao.sql (begin/rollback; com a fixture de 23/10 os
-- números da spec §5.4/§6; sem a fixture, só as regras gerais). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261024160400
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261024160400_agenda_fase1_prontidao.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024160400', 'agenda_fase1_prontidao');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 0. Auxiliares ───────────────────────────────────────────────────────────────────────────────────────

-- O sócio que é o dono: o ligado ao login (p_autor = app_users.id); sem login ou sem ligação, o único sócio ativo
-- ligado a algum login, senão o único sócio ativo. Mais de um sem desempate = null (quem chama pergunta).
create or replace function public._agenda_dono(p_autor uuid default null)
 returns uuid
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(
    (select p.id from public.payees p
      where p_autor is not null and p.active and p.kind = 'socio' and p.app_user_id = p_autor
      order by p.created_at, p.id limit 1),
    (select min(p.id::text)::uuid from public.payees p
      where p.active and p.kind = 'socio' and p.app_user_id is not null
     having count(*) = 1),
    (select min(p.id::text)::uuid from public.payees p
      where p.active and p.kind = 'socio'
     having count(*) = 1));
$function$;

comment on function public._agenda_dono(uuid) is
  'Agenda de Produção (Fase 1, P3): o payee sócio que é o dono — o ligado ao login (p_autor), senão o único sócio ativo com login, senão o único sócio ativo; null quando não dá para saber.';

-- "Conversão do sistema de refrigeração para 12V — Refrigerador" → "Conversão do sistema…": as 3 primeiras palavras
-- (token com letra ou número; o travessão solto não conta) e "…" quando sobra palavra. Nome todo em maiúsculas
-- vira minúsculo com a 1ª maiúscula ("CENTRAL DE CONTROLE CERBO" → "Central de controle…").
create or replace function public._agenda_linha_curta(p_nome text)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v        text := btrim(regexp_replace(coalesce(p_nome, ''), '\s+', ' ', 'g'));
  v_tok    text[];
  v_saida  text := '';
  v_pal    int := 0;
  i        int;
begin
  if v = '' then return null; end if;
  if v !~ '[a-zà-ÿ]' and v ~ '[A-ZÀ-Þ]{4}' then
    v := left(v, 1) || translate(lower(substr(v, 2)), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ', 'áàâãäéèêëíìîïóòôõöúùûüçñ');
  end if;
  v_tok := string_to_array(v, ' ');
  for i in 1 .. cardinality(v_tok) loop
    if v_pal = 3 then
      if array_to_string(v_tok[i:], ' ') ~ '[0-9A-Za-zÀ-ÿ]' then
        -- Parêntese aberto e não fechado no corte sai inteiro ("Sikaflex 221 (selante…" → "Sikaflex 221…").
        if length(v_saida) - length(replace(v_saida, '(', '')) > length(v_saida) - length(replace(v_saida, ')', '')) then
          v_saida := regexp_replace(v_saida, '\([^()]*$', '');
        end if;
        return regexp_replace(v_saida, '[[:space:],;:.(–—-]+$', '') || '…';
      end if;
      return v;
    end if;
    v_saida := case when v_saida = '' then v_tok[i] else v_saida || ' ' || v_tok[i] end;
    if v_tok[i] ~ '[0-9A-Za-zÀ-ÿ]' then v_pal := v_pal + 1; end if;
  end loop;
  return v;
end;
$function$;

comment on function public._agenda_linha_curta(text) is
  'Agenda de Produção (Fase 1, P3): o nome de uma linha encurtado nas 3 primeiras palavras + "…" ("Conversão do sistema…"); nome todo em maiúsculas vira minúsculo com a 1ª maiúscula.';

-- "1 item", "4 itens".
create or replace function public._agenda_itens(p_n integer)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select p_n::text || case when p_n = 1 then ' item' else ' itens' end;
$function$;

comment on function public._agenda_itens(integer) is 'Agenda de Produção (Fase 1, P3): "1 item", "4 itens".';

-- O status da OS em português. p_frase = false: o rótulo curto ("aprovada", "esperando o cliente"); true: a frase
-- de quem está fora da carteira ("já foi concluída", "foi enviado e espera a aprovação do cliente").
create or replace function public._agenda_rotulo_os(p_status text, p_quote_status text, p_assinado boolean,
                                                    p_juntado_em text, p_frase boolean)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_juntado_em is not null then
      case when p_status = 'draft' then 'foi juntado ao ' else 'foi juntada à ' end || p_juntado_em
    when p_status = 'draft' then case
      when p_quote_status = 'approved' then case when p_assinado then 'orçamento assinado' else 'orçamento aprovado' end
      when p_quote_status = 'awaiting_deposit' then 'esperando o sinal'
      when p_quote_status in ('sent', 'awaiting_approval') then
        case when p_frase then 'foi enviado e espera a aprovação do cliente' else 'enviado, esperando a aprovação' end
      when p_quote_status = 'rejected' then case when p_frase then 'foi recusado (ou venceu)' else 'recusado ou vencido' end
      else case when p_frase then 'ainda é rascunho (não foi enviado ao cliente)' else 'rascunho' end end
    when p_status in ('open', 'approved') then 'aprovada'
    when p_status = 'scheduled' then 'agendada'
    when p_status = 'in_progress' then 'em andamento'
    when p_status = 'awaiting_parts' then 'esperando peças'
    when p_status = 'awaiting_client' then 'esperando o cliente'
    when p_status = 'completed' then case when p_frase then 'já foi concluída' else 'concluída' end
    when p_status = 'invoiced' then case when p_frase then 'já foi faturada' else 'faturada' end
    when p_status = 'cancelled' then 'foi cancelada'
    else coalesce(p_status, '')
  end;
$function$;

comment on function public._agenda_rotulo_os(text, text, boolean, text, boolean) is
  'Agenda de Produção (Fase 1, P3): o status da OS/orçamento em português — rótulo curto (p_frase false) ou a frase de quem está fora da carteira (p_frase true).';

-- ── 1. A carteira ───────────────────────────────────────────────────────────────────────────────────────

create or replace function public.os_carteira(p_hoje date default public._hoje_brt())
 returns table (service_order_id uuid, numero text, status text, quote_status text, eh_orcamento boolean,
                cliente text, cliente_curto text, unidade text, valor numeric, aprovada_em date,
                sinal_previsto numeric, sinal_pago numeric, sinal_pendente numeric,
                agendada_de date, agendada_ate date)
 language sql
 stable
 set search_path to 'public'
as $function$
  -- p_hoje não muda o recorte (a carteira é o que está aberto agora); fica na assinatura como em toda função da
  -- agenda, para quem chama passar sempre o mesmo dia.
  select so.id, so.service_order_number, so.status, so.quote_status, so.status = 'draft',
         c.name, public._agenda_nome_curto(c.name), v.name, so.grand_total,
         (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date,
         coalesce(s.previsto, 0), coalesce(s.pago, 0), coalesce(s.pendente, 0),
         (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date,
         (coalesce(so.scheduled_end_at, so.scheduled_start_at) at time zone 'America/Sao_Paulo')::date
    from public.service_orders so
    left join public.clients c on c.id = so.client_id
    left join public.vessels v on v.id = so.vessel_id
    left join lateral (
      select sum(r.amount) as previsto,
             sum(coalesce(r.paid_amount, 0)) as pago,
             sum(case when r.status in ('pending', 'partially_paid', 'overdue')
                      then greatest(r.amount - coalesce(r.paid_amount, 0), 0) else 0 end) as pendente
        from public.receivables r
       where r.service_order_id = so.id and r.is_deposit and r.status <> 'cancelled') s on true
   where so.merged_into_id is null
     and (so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
          or (so.status = 'draft' and so.quote_status in ('approved', 'awaiting_deposit')))
   order by so.service_order_number collate "C", so.id;
$function$;

comment on function public.os_carteira(date) is
  'Agenda de Produção (Fase 1, P3): a carteira — OS ativas (STATUS_OS_ATIVAS: open, approved, scheduled, in_progress, awaiting_parts, awaiting_client) + orçamento (draft) aprovado ou esperando sinal, sem os agrupados (merged_into_id). aprovada_em = conversão, senão assinatura, senão criação (dia de Brasília); sinal previsto/pago/pendente pelas cobranças de sinal (receivables.is_deposit, sem as canceladas); agendada_de/ate = a janela antiga (scheduled_*) no dia de Brasília. Ordem: número.';

-- A sincronização do material (160300) passa a percorrer a mesma carteira (antes: o mesmo recorte, copiado).
create or replace function public.os_material_sincronizar_carteira(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_os          record;
  v_r           jsonb;
  v_oss         int := 0;
  v_criadas     int := 0;
  v_atualizadas int := 0;
  v_erros       jsonb := '[]'::jsonb;
begin
  for v_os in select k.service_order_id as id, k.numero from public.os_carteira(p_hoje) k loop
    v_oss := v_oss + 1;
    begin
      v_r := public.os_material_sincronizar(v_os.id, p_hoje);
      v_criadas := v_criadas + coalesce((v_r ->> 'criadas')::int, 0);
      v_atualizadas := v_atualizadas + coalesce((v_r ->> 'atualizadas')::int, 0);
    exception when others then
      -- Uma OS com problema não derruba as outras: o erro sai no retorno e o motor grava em app_error_logs.
      v_erros := v_erros || jsonb_build_object('os', v_os.numero, 'msg', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('oss', v_oss, 'criadas', v_criadas, 'atualizadas', v_atualizadas, 'erros', v_erros);
end;
$function$;

comment on function public.os_material_sincronizar_carteira(date) is
  'Agenda de Produção (Fase 1, P2/P3): roda os_material_sincronizar em cada OS de os_carteira(p_hoje), na ordem do número; o erro de uma OS vai para erros [{os, msg}] sem derrubar as outras. Chamada pelo task-automations a cada 15 min (passo agenda:material), só com agenda_config.modo_leitura <> desligado. Só service_role. Devolve {oss, criadas, atualizadas, erros}.';

-- ── 2. Qual OS o dono quis dizer ────────────────────────────────────────────────────────────────────────

create or replace function public.agenda_resolver_os(p_ref text, p_hoje date default public._hoje_brt(),
                                                     p_para_aprovar boolean default false)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref     text := btrim(coalesce(p_ref, ''));
  v_norm    text := public._agenda_normal(p_ref);
  v_comp    text := regexp_replace(public._agenda_normal(p_ref), '[^a-z0-9]', '', 'g');
  v_pref    text;
  v_dig     text;
  v_id      uuid;
  v_cands   text[];
  v_tokens  text[];
  v_achados jsonb;
  v_n       int;
  v_um      jsonb;
  v_nomes   text[];
  v_opcoes  text[];
  v_dito    text;
  -- Palavras que não identificam ninguém: "o barco do Lenine", "a lancha do César", "o serviço do Rodrigo".
  c_vazias  constant text[] := array['barco', 'lancha', 'veleiro', 'iate', 'motorhome', 'embarcacao', 'servico',
                                     'orcamento', 'cliente', 'ordem', 'dos', 'das', 'pro', 'pra', 'para'];
begin
  if v_ref = '' then
    return jsonb_build_object('status', 'nao_achei', 'opcoes', '[]'::jsonb,
      'texto', 'Diga qual serviço: o nome do cliente ou o número (por exemplo, OS-00112).');
  end if;

  if v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_id := v_ref::uuid;
  elsif v_comp ~ '^(orcamento|orc|os|ordem)?[0-9]{1,8}$' then
    -- A leitura de pareceNumeroDeOS + interpretarDocumento: o prefixo escrito manda; sem prefixo, ORÇ e OS.
    v_pref := case when v_comp ~ '^orc' then 'ORÇ' when v_comp ~ '^(os|ordem)' then 'OS' end;
    v_dig := regexp_replace(regexp_replace(v_comp, '[^0-9]', '', 'g'), '^0+(?=[0-9])', '');
    v_dig := case when length(v_dig) >= 5 then v_dig else lpad(v_dig, 5, '0') end;
    v_cands := case when v_pref is null then array['ORÇ-' || v_dig, 'OS-' || v_dig] else array[v_pref || '-' || v_dig] end;
  else
    v_tokens := array(
      select t from unnest(string_to_array(v_norm, ' ')) with ordinality u(t, o)
       where length(regexp_replace(t, '[^a-z]', '', 'g')) >= 3 and t <> all (c_vazias)
       order by o);
    if cardinality(v_tokens) = 0 then
      return jsonb_build_object('status', 'nao_achei', 'opcoes', '[]'::jsonb,
        'texto', format('Não entendi qual serviço é "%s". Diga o nome do cliente ou o número (por exemplo, OS-00112).', v_ref));
    end if;
  end if;

  -- Por número ou id: tudo o que existe com esse número (dentro ou fora da carteira).
  if v_tokens is null then
    select coalesce(jsonb_agg(x.o order by x.numero collate "C", x.id), '[]'::jsonb), count(*)
      into v_achados, v_n
      from (
        select so.id, so.service_order_number as numero,
               jsonb_build_object(
                 'id', so.id, 'numero', so.service_order_number, 'status', so.status,
                 'eh_orcamento', so.status = 'draft',
                 'cliente_curto', public._agenda_nome_curto(cl.name),
                 'na_carteira', k.service_order_id is not null,
                 'pode_aprovar', so.status = 'draft' and so.merged_into_id is null,
                 'rotulo', public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, mg.service_order_number, false),
                 'frase', public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, mg.service_order_number, true),
                 'servico', coalesce(public._agenda_linha_curta(regexp_replace(pr.name_snapshot,
                              '^\s*m[aã]o\s+de\s+obra\s*(t[eé]cnica)?\s*[-–—:]\s*', '', 'i')), vs.name)) as o
          from public.service_orders so
          left join public.clients cl on cl.id = so.client_id
          left join public.vessels vs on vs.id = so.vessel_id
          left join public.service_orders mg on mg.id = so.merged_into_id
          left join public.os_carteira(p_hoje) k on k.service_order_id = so.id
          left join lateral (
            select s.name_snapshot from public.service_order_services s
             where s.service_order_id = so.id
             order by s.line_total desc nulls last, s.created_at, s.id limit 1) pr on true
         where so.id = v_id or so.service_order_number = any (v_cands)
      ) x;

    if v_n = 0 then
      return jsonb_build_object('status', 'nao_achei', 'opcoes', '[]'::jsonb,
        'texto', case when v_cands is null then 'Não encontrei esse serviço.'
                      when cardinality(v_cands) = 1 then
                        format('Não encontrei %s %s.', case when v_pref = 'OS' then 'a' else 'o' end, v_cands[1])
                      else format('Não encontrei o %s nem a %s.', v_cands[1], v_cands[2]) end);
    end if;
    if v_n > 1 then
      v_opcoes := array(select format('%s (%s, %s)', e ->> 'numero', e ->> 'servico', e ->> 'rotulo')
                          from jsonb_array_elements(v_achados) e);
      return jsonb_build_object('status', 'ambiguo',
        'opcoes', (select jsonb_agg(jsonb_build_object('numero', e ->> 'numero', 'id', e ->> 'id',
                     'texto', format('%s (%s, %s)', e ->> 'numero', e ->> 'servico', e ->> 'rotulo')))
                     from jsonb_array_elements(v_achados) e),
        'texto', format('Qual deles: %s ou %s?', array_to_string(v_opcoes[1:cardinality(v_opcoes) - 1], ', '),
                        v_opcoes[cardinality(v_opcoes)]));
    end if;
    v_um := v_achados -> 0;
    if (v_um ->> 'na_carteira')::boolean or (p_para_aprovar and (v_um ->> 'pode_aprovar')::boolean) then
      return jsonb_build_object('status', 'ok', 'id', v_um ->> 'id', 'numero', v_um ->> 'numero',
        'cliente_curto', v_um ->> 'cliente_curto', 'eh_orcamento', (v_um ->> 'eh_orcamento')::boolean,
        'opcoes', '[]'::jsonb, 'texto', format('%s (%s)', v_um ->> 'cliente_curto', v_um ->> 'numero'));
    end if;
    return jsonb_build_object('status', 'fora_da_carteira', 'id', v_um ->> 'id', 'numero', v_um ->> 'numero',
      'cliente_curto', v_um ->> 'cliente_curto', 'eh_orcamento', (v_um ->> 'eh_orcamento')::boolean,
      'situacao', v_um ->> 'status', 'opcoes', '[]'::jsonb,
      'texto', format('%s %s %s.', case when (v_um ->> 'eh_orcamento')::boolean then 'O' else 'A' end,
                      v_um ->> 'numero', v_um ->> 'frase'));
  end if;

  -- Por nome: todo token de 3+ letras começa uma palavra do nome do cliente ou da embarcação. Passos: a carteira
  -- (ou, com p_para_aprovar, os orçamentos enviados → todos os rascunhos → a carteira); sem nada, fora da carteira.
  with docs as (
    select so.id, so.service_order_number as numero, so.status, so.quote_status, so.merged_into_id,
           k.service_order_id is not null as na_carteira,
           public._agenda_nome_curto(cl.name) as cliente_curto,
           string_to_array(public._agenda_normal(concat_ws(' ', cl.name, cl.display_name, vs.name)), ' ') as palavras,
           public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, mg.service_order_number, false) as rotulo,
           public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, mg.service_order_number, true) as frase,
           coalesce(public._agenda_linha_curta(regexp_replace(pr.name_snapshot,
             '^\s*m[aã]o\s+de\s+obra\s*(t[eé]cnica)?\s*[-–—:]\s*', '', 'i')), vs.name) as servico
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
      left join public.vessels vs on vs.id = so.vessel_id
      left join public.service_orders mg on mg.id = so.merged_into_id
      left join public.os_carteira(p_hoje) k on k.service_order_id = so.id
      left join lateral (
        select s.name_snapshot from public.service_order_services s
         where s.service_order_id = so.id
         order by s.line_total desc nulls last, s.created_at, s.id limit 1) pr on true
  ),
  casam as (
    select d.* from docs d
     where not exists (select 1 from unnest(v_tokens) t
                        where not exists (select 1 from unnest(d.palavras) w where w like t || '%'))
  ),
  passos as (
    select c.*, case
        when p_para_aprovar and c.status = 'draft' and c.merged_into_id is null
             and c.quote_status in ('sent', 'awaiting_approval') then 1
        when p_para_aprovar and c.status = 'draft' and c.merged_into_id is null then 2
        when c.na_carteira then 3
        else 4 end as passo
      from casam c
  ),
  melhor as (
    select p.* from passos p where p.passo = (select min(passo) from passos)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'numero', m.numero, 'eh_orcamento', m.status = 'draft', 'cliente_curto', m.cliente_curto,
           'passo', m.passo, 'situacao', m.status, 'frase', m.frase,
           'texto', format('%s (%s, %s)', m.numero, m.servico, m.rotulo))
           order by m.numero collate "C", m.id), '[]'::jsonb), count(*)
    into v_achados, v_n
    from melhor m;

  -- O nome como o dono falou, só com as palavras que buscam ("a OS da Maria" → "Maria"), sem artigo antes: o banco
  -- não sabe se é "do" ou "da".
  v_dito := coalesce(nullif(array_to_string(array(
              select w from unnest(regexp_split_to_array(v_ref, '\s+')) with ordinality u(w, o)
               where public._agenda_normal(w) = any (v_tokens) order by o), ' '), ''), v_ref);
  -- 1ª letra maiúscula sem depender do locale (a mesma regra de _agenda_maiuscula, que vem no pacote seguinte)
  v_dito := translate(upper(left(v_dito, 1)), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ') || substr(v_dito, 2);

  if v_n = 0 then
    return jsonb_build_object('status', 'nao_achei', 'opcoes', '[]'::jsonb,
      'texto', format('Não encontrei "%s" entre os serviços da carteira.', v_dito));
  end if;

  if (v_achados -> 0 ->> 'passo')::int = 4 then
    -- Só fora da carteira: diz o status (um) ou os números (vários); nunca escolhe.
    if v_n = 1 then
      v_um := v_achados -> 0;
      return jsonb_build_object('status', 'fora_da_carteira', 'id', v_um ->> 'id', 'numero', v_um ->> 'numero',
        'cliente_curto', v_um ->> 'cliente_curto', 'eh_orcamento', (v_um ->> 'eh_orcamento')::boolean,
        'situacao', v_um ->> 'situacao', 'opcoes', '[]'::jsonb,
        'texto', format('Não encontrei "%s" entre os serviços da carteira: %s %s %s.', v_dito,
                        case when (v_um ->> 'eh_orcamento')::boolean then 'o' else 'a' end,
                        v_um ->> 'numero', v_um ->> 'frase'));
    end if;
    return jsonb_build_object('status', 'nao_achei',
      'opcoes', (select jsonb_agg(jsonb_build_object('numero', e ->> 'numero', 'id', e ->> 'id', 'texto', e ->> 'texto'))
                   from jsonb_array_elements(v_achados) e),
      'texto', format('Não encontrei "%s" entre os serviços da carteira (fora dela: %s).', v_dito,
                      public._agenda_lista(array(select e ->> 'texto' from jsonb_array_elements(v_achados) e), 4)));
  end if;

  if v_n = 1 then
    v_um := v_achados -> 0;
    return jsonb_build_object('status', 'ok', 'id', v_um ->> 'id', 'numero', v_um ->> 'numero',
      'cliente_curto', v_um ->> 'cliente_curto', 'eh_orcamento', (v_um ->> 'eh_orcamento')::boolean,
      'opcoes', '[]'::jsonb, 'texto', format('%s (%s)', v_um ->> 'cliente_curto', v_um ->> 'numero'));
  end if;

  v_nomes := array(select distinct e ->> 'cliente_curto' from jsonb_array_elements(v_achados) e);
  v_opcoes := array(select e ->> 'texto' from jsonb_array_elements(v_achados) e);
  return jsonb_build_object('status', 'ambiguo',
    'opcoes', (select jsonb_agg(jsonb_build_object('numero', e ->> 'numero', 'id', e ->> 'id', 'texto', e ->> 'texto'))
                 from jsonb_array_elements(v_achados) e),
    'texto', format('Qual %s: %s ou %s?',
                    case when cardinality(v_nomes) = 1 then v_nomes[1] else 'deles' end,
                    array_to_string(v_opcoes[1:cardinality(v_opcoes) - 1], ', '), v_opcoes[cardinality(v_opcoes)]));
end;
$function$;

comment on function public.agenda_resolver_os(text, date, boolean) is
  'Agenda de Produção (Fase 1, P3): a OS que o dono quis dizer. Número com a leitura de pareceNumeroDeOS/localizarOrdem ("OS-00112", "ORÇ-00112", "orc 112", "112"; ORÇ e OS com o mesmo número = ambiguo) ou id; nome do cliente/embarcação só dentro da carteira (p_para_aprovar: orçamentos enviados, depois todos os rascunhos, depois a carteira). Devolve {status ok|ambiguo|nao_achei|fora_da_carteira, id, numero, cliente_curto, eh_orcamento, opcoes[{numero,id,texto}], texto}: ambíguo traz a pergunta pronta com os números; fora da carteira diz o status. Nunca escolhe por conta própria.';

-- ── 3. Quem o dono quis dizer ───────────────────────────────────────────────────────────────────────────

create or replace function public.agenda_resolver_pessoa(p_ref text, p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref    text := btrim(coalesce(p_ref, ''));
  v_norm   text := public._agenda_normal(p_ref);
  v_tokens text[];
  v_dono   uuid;
  v_n      int;
  v_achados jsonb;
  v_um     jsonb;
  v_opcoes text[];
  c_vazias constant text[] := array['o', 'a', 'do', 'da', 'de', 'com', 'e', 'seu', 'sua', 'sr', 'senhor', 'tecnico'];
begin
  if v_ref = '' then
    return jsonb_build_object('status', 'nao_achei', 'texto', 'Diga quem: "eu" ou o nome (por exemplo, Roberto).');
  end if;

  -- O sócio do login; sem ligação, o único sócio ativo.
  v_dono := coalesce(
    (select p.id from public.payees p
      where p_autor is not null and p.active and p.kind = 'socio' and p.app_user_id = p_autor
      order by p.created_at, p.id limit 1),
    (select min(p.id::text)::uuid from public.payees p where p.active and p.kind = 'socio' having count(*) = 1));

  if v_norm in ('eu', 'mim', 'comigo', 'voce', 'vc', 'eu mesmo', 'so eu', 'o dono', 'dono') then
    if v_dono is null then
      if exists (select 1 from public.payees p where p.active and p.kind = 'socio') then
        return jsonb_build_object('status', 'ambiguo',
          'texto', format('Qual sócio: %s?', public._agenda_lista(array(
            select public._agenda_nome_curto(p.name) from public.payees p
             where p.active and p.kind = 'socio' order by p.name, p.id), null)));
      end if;
      return jsonb_build_object('status', 'nao_achei', 'texto', 'Não achei você no cadastro de pessoas (sócio).');
    end if;
    return (select jsonb_build_object('status', 'ok', 'payee_id', p.id, 'nome_curto', public._agenda_nome_curto(p.name),
                                      'eh_dono', true, 'texto', 'você')
              from public.payees p where p.id = v_dono);
  end if;

  v_tokens := array(select t from unnest(string_to_array(v_norm, ' ')) with ordinality u(t, o)
                     where length(t) >= 2 and t <> all (c_vazias) order by o);
  if cardinality(v_tokens) = 0 then
    return jsonb_build_object('status', 'nao_achei', 'texto', format('Não conheço ninguém chamado %s na equipe.', v_ref));
  end if;

  -- A equipe (cadastro de diarista vigente em p_hoje) e os sócios, pelo nome sem acento: todo token começa uma
  -- palavra do nome. O 1º nome igual vence o "começa com" ("Rob" acha o Roberto; "Roberto" acha só os Robertos).
  with gente as (
    select p.id, p.name, p.kind = 'socio' as socio,
           string_to_array(public._agenda_normal(p.name), ' ') as palavras
      from public.payees p
     where p.active
       and (p.kind = 'socio'
            or exists (select 1 from public.work_profiles w
                        where w.payee_id = p.id and w.vigencia_inicio <= p_hoje
                          and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje)))
  ),
  casam as (
    select g.*, g.palavras[1] = v_tokens[1] as exato from gente g
     where not exists (select 1 from unnest(v_tokens) t
                        where not exists (select 1 from unnest(g.palavras) w where w like t || '%'))
  ),
  melhor as (
    select c.* from casam c where c.exato or not exists (select 1 from casam x where x.exato)
  )
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', m.id, 'nome', m.name,
                                               'nome_curto', public._agenda_nome_curto(m.name),
                                               'eh_dono', m.id is not distinct from v_dono)
                            order by m.name, m.id), '[]'::jsonb), count(*)
    into v_achados, v_n
    from melhor m;

  if v_n = 0 then
    return jsonb_build_object('status', 'nao_achei', 'texto', format('Não conheço ninguém chamado %s na equipe.', v_ref));
  end if;
  if v_n > 1 then
    v_opcoes := array(select e ->> 'nome' from jsonb_array_elements(v_achados) e);
    return jsonb_build_object('status', 'ambiguo', 'opcoes', v_achados,
      'texto', format('Qual %s: %s ou %s?', v_ref,
                      array_to_string(v_opcoes[1:cardinality(v_opcoes) - 1], ', '), v_opcoes[cardinality(v_opcoes)]));
  end if;
  v_um := v_achados -> 0;
  return jsonb_build_object('status', 'ok', 'payee_id', v_um ->> 'payee_id', 'nome_curto', v_um ->> 'nome_curto',
    'eh_dono', (v_um ->> 'eh_dono')::boolean,
    'texto', case when (v_um ->> 'eh_dono')::boolean then 'você' else v_um ->> 'nome_curto' end);
end;
$function$;

comment on function public.agenda_resolver_pessoa(text, uuid, date) is
  'Agenda de Produção (Fase 1, P3): quem o dono quis dizer. "eu", "mim", "comigo", "você" e o nome do sócio → o sócio ligado ao login (p_autor), senão o único sócio ativo; a equipe (cadastro de diarista vigente em p_hoje) pelo nome sem acento (o 1º nome igual vence o "começa com"). Devolve {status ok|ambiguo|nao_achei, payee_id, nome_curto, eh_dono, texto}.';

-- ── 4. Classe e prazo do fornecedor ─────────────────────────────────────────────────────────────────────

create or replace function public._agenda_classe_do_fornecedor(p_fornecedor uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when s.id is null then null
    when public._agenda_normal(concat_ws(' ', s.name, s.trade_name, s.display_name))
         ~ '\m(mercado ?livre|mercado ?pago|amazon|shopee|magalu|magazine luiza)\M' then 'marketplace'
    when nullif(btrim(s.city), '') is not null
         and public._agenda_normal(s.city) = any (select public._agenda_normal(m) from unnest(c.municipios_locais) m)
      then 'entrega_local'
    when public._agenda_normal(s.state) in ('sc', 'pr', 'santa catarina', 'parana') then 'distribuidor_sc_pr'
    when nullif(btrim(s.state), '') is not null then 'outro_estado'
    else null
  end
    from (select 1) um
    left join public.suppliers s on s.id = p_fornecedor
    cross join public._agenda_cfg() c;
$function$;

comment on function public._agenda_classe_do_fornecedor(uuid) is
  'Agenda de Produção (Fase 1, P3): a classe de prazo do fornecedor — marketplace (Mercado Livre/Pago, Amazon, Shopee, Magalu, pelo nome), entrega_local (cidade em agenda_config.municipios_locais), distribuidor_sc_pr (UF SC/PR), outro_estado (outra UF); sem cidade e sem UF, ou sem fornecedor = null (desconhecida).';

create or replace function public._agenda_prazo_da_classe(p_classe text)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when p_classe is null then null else (c.prazo_classe_du ->> p_classe)::int end
    from public._agenda_cfg() c;
$function$;

comment on function public._agenda_prazo_da_classe(text) is
  'Agenda de Produção (Fase 1, P3): os dias úteis típicos da classe do fornecedor (agenda_config.prazo_classe_du); null para classe desconhecida.';

-- ── 5. Duração sugerida pelo valor ──────────────────────────────────────────────────────────────────────

create or replace function public.os_duracao_sugerida(p_so_id uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_total  numeric;
  v_mat    numeric;
  v_horas  numeric;
  v_mo     numeric;
  v_dp_ot  numeric;
  v_dp_re  numeric;
  v_pes    int;
  v_d_ot   numeric;
  v_d_re   numeric;
  v_sug    numeric;
begin
  if not exists (select 1 from public.service_orders where id = p_so_id) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;

  -- A mão de obra é o total das linhas de serviço menos o material de texto livre que ENTRA NA COMPRA (o mesmo
  -- predicado de compute_purchase_needs); as horas diretas são as linhas cobradas por hora.
  select coalesce(sum(s.line_total), 0),
         coalesce(sum(s.line_total) filter (
           where s.service_id is null and s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0
             and public.free_text_is_material(s.name_snapshot)), 0),
         coalesce(sum(s.quantity) filter (where s.billing_unit_snapshot = 'hour'), 0)
    into v_total, v_mat, v_horas
    from public.service_order_services s
   where s.service_order_id = p_so_id;
  v_mo := greatest(v_total - v_mat, 0);

  if v_mo <= 0 and v_horas <= 0 then
    return jsonb_build_object('ok', true, 'sem_base', true, 'mo', v_mo, 'horas', v_horas,
                              'texto', 'sem base para estimar: quantos dias?');
  end if;

  -- Diárias-pessoa: o otimista pelo preço da diária, o realista pelo que a HBR fatura por diária de fato.
  v_dp_ot := greatest(v_horas / c.jornada_horas, v_mo / c.mo_por_diaria_preco);
  v_dp_re := greatest(v_horas / c.jornada_horas, v_mo / c.mo_por_diaria_real);
  v_pes := case when v_dp_re <= 1 then 1 else c.equipe_sugerida end;
  -- Dias de calendário arredondados ao meio dia; nunca menos de meio dia.
  v_d_ot := trim_scale(greatest(0.5, round(v_dp_ot / v_pes * 2) / 2));
  v_d_re := trim_scale(greatest(v_d_ot, round(v_dp_re / v_pes * 2) / 2));
  v_sug  := trim_scale(round(v_d_ot + v_d_re) / 2);

  return jsonb_build_object(
    'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
    'dp_otimista', round(v_dp_ot, 2), 'dp_realista', round(v_dp_re, 2),
    'pessoas', v_pes, 'dias_otimista', v_d_ot, 'dias_realista', v_d_re, 'sugerida', v_sug,
    'diarias_otimista', trim_scale(v_d_ot * v_pes), 'diarias_realista', trim_scale(v_d_re * v_pes),
    'texto', public._agenda_faixa_dias(v_d_ot, v_d_re)
             || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
             || ' (estimativa minha, pelo valor)');
end;
$function$;

comment on function public.os_duracao_sugerida(uuid) is
  'Agenda de Produção (Fase 1, P3): a duração "pelo valor" (plano §4.2 com a correção do material). mo = linhas de serviço − material de texto livre que entra na compra; horas = linhas por hora; diárias-pessoa otimista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_preco), realista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_real); 1 pessoa se o realista ≤ 1, senão equipe_sugerida; dias arredondados ao meio dia; sugerida = o meio dia mais perto da média. Sem mão de obra nem horas: {sem_base:true, texto:"sem base para estimar: quantos dias?"}. Nunca é gravada.';

-- ── 6. Presença do dono ─────────────────────────────────────────────────────────────────────────────────

create or replace function public.os_presenca_do_dono(p_so_id uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with os as (
    select so.id, so.service_type, so.marina_id, pl.dono_presenca,
           public._agenda_normal(pr.name_snapshot) as principal
      from public.service_orders so
      left join public.os_planejamento pl on pl.service_order_id = so.id
      left join lateral (
        select s.name_snapshot from public.service_order_services s
         where s.service_order_id = so.id
         order by s.line_total desc nulls last, s.created_at, s.id limit 1) pr on true
     where so.id = p_so_id
  )
  select coalesce((
    select case
      when os.dono_presenca is not null then
        jsonb_build_object('presenca', os.dono_presenca, 'motivo', 'você disse', 'fonte', 'dono')
      when os.service_type = 'diagnosis' or os.principal ~ 'diagnost' then
        jsonb_build_object('presenca', 'sempre', 'motivo', 'diagnóstico', 'fonte', 'regra')
      when os.service_type = 'commissioning' or os.principal ~ '(comissionament|parametriz)' then
        jsonb_build_object('presenca', 'sempre', 'motivo', 'comissionamento', 'fonte', 'regra')
      when os.marina_id is not null and not exists (
             select 1 from public.service_orders o
              where o.marina_id = os.marina_id and o.id <> os.id and o.status in ('completed', 'invoiced')) then
        jsonb_build_object('presenca', 'sempre', 'motivo', 'marina nova', 'fonte', 'regra')
      else jsonb_build_object('presenca', 'abre_e_fecha', 'motivo', 'padrão', 'fonte', 'regra')
    end
      from os),
    jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.'));
$function$;

comment on function public.os_presenca_do_dono(uuid) is
  'Agenda de Produção (Fase 1, P3): a presença do dono na OS (d05). os_planejamento.dono_presenca, se ele disse (fonte dono); senão a regra: sempre em diagnóstico (service_type ou a linha de maior valor), comissionamento/parametrização e marina sem OS concluída/faturada antes; senão abre_e_fecha (não ocupa o turno dele). {presenca, motivo, fonte}.';

-- ── 7. Prontidão ────────────────────────────────────────────────────────────────────────────────────────

create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c            public.agenda_config := public._agenda_cfg();
  so           record;
  p            public.os_planejamento%rowtype;
  v_na_cart    boolean;
  v_aprov      date;
  v_pago       numeric := 0;
  v_pend       numeric := 0;
  v_ag_de      date;
  v_ag_ate     date;
  v_bem_nome   text;
  v_d_bem      date;
  v_bem_tudo   boolean := false;
  v_horizonte  date;
  v_base       date;
  v_est_sm     date;
  v_bruto      jsonb;
  v_itens      jsonb;
  v_crit       jsonb;
  v_embut      jsonb;
  v_n_itens    int;
  v_conferido  boolean;
  v_mat_estado text;
  v_dpm        date;
  v_gargalo    jsonb;
  v_confianca  text;
  v_inicio_mat date;
  v_est        date;
  v_sug        jsonb;
  v_dur        jsonb;
  v_equipe     jsonb;
  v_meios      numeric;
  v_diarias_eq numeric;
  v_dias_re    numeric;
  v_pres       jsonb;
  v_prazo      date;
  v_prazo_fnt  text;
  v_razao      numeric;
  v_r          jsonb := '[]'::jsonb;
  v_estado     text;
  v_estado_txt text;
  v_principal  jsonb;
  v_quase      boolean := false;
  v_parada     boolean := false;
  v_ult_diaria date;
  v_x          jsonb;
  v_compra     jsonb;
  v_n          int;
  v_n_falta    int := 0;
  v_n_sem      int;
  v_txt        text;
  v_cond       text;
  v_dono_padrao boolean;
  v_cc         record;
begin
  if p_hoje is null then
    raise exception 'os_prontidao: sem o dia de hoje' using errcode = '22004';
  end if;

  select o.*, cl.name as cliente_nome, vs.name as bem, vs.asset_type as bem_tipo,
         mg.service_order_number as juntado_em
    into so
    from public.service_orders o
    left join public.clients cl on cl.id = o.client_id
    left join public.vessels vs on vs.id = o.vessel_id
    left join public.service_orders mg on mg.id = o.merged_into_id
   where o.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;

  select * into p from public.os_planejamento where service_order_id = p_so_id;

  -- Carteira, aprovação, sinal e janela antiga: a MESMA conta de os_carteira (fora dela, a mesma fórmula).
  select true, k.aprovada_em, k.sinal_pago, k.sinal_pendente, k.agendada_de, k.agendada_ate
    into v_na_cart, v_aprov, v_pago, v_pend, v_ag_de, v_ag_ate
    from public.os_carteira(p_hoje) k where k.service_order_id = p_so_id;
  if not found then
    v_na_cart := false;
    v_aprov := (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date;
    select coalesce(sum(coalesce(r.paid_amount, 0)), 0),
           coalesce(sum(case when r.status in ('pending', 'partially_paid', 'overdue')
                             then greatest(r.amount - coalesce(r.paid_amount, 0), 0) else 0 end), 0)
      into v_pago, v_pend
      from public.receivables r
     where r.service_order_id = p_so_id and r.is_deposit and r.status <> 'cancelled';
    v_ag_de := (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    v_ag_ate := (coalesce(so.scheduled_end_at, so.scheduled_start_at) at time zone 'America/Sao_Paulo')::date;
  end if;

  -- O bem (barco, motorhome): 1º dia a partir de amanhã fora de bem_indisponivel; null = fora sem data de volta.
  v_bem_nome := case when public._agenda_normal(coalesce(so.bem_tipo, so.bem)) ~ 'motorhome|motor home|trailer'
                     then 'o motorhome' else 'o barco' end;
  v_horizonte := p_hoje + 7 * c.horizonte_semanas;
  v_d_bem := p_hoje + 1;
  if p.service_order_id is not null and not isempty(p.bem_indisponivel) and p.bem_indisponivel @> v_d_bem then
    select upper(r) into v_d_bem from unnest(p.bem_indisponivel) r where r @> (p_hoje + 1);
  end if;
  v_bem_tudo := v_d_bem is null or v_d_bem > v_horizonte;

  -- O início mais cedo sem olhar o material: o bem livre, o "não antes de" e o congelamento (hoje + o próximo
  -- dia útil ficam como estão).
  v_base := public.agenda_somar_du(p_hoje, c.congelamento_du + 1);
  v_est_sm := greatest(v_d_bem, p.nao_antes_de, v_base);

  -- ── Material efetivo: a conta bruta + o que foi informado em os_material ──
  v_bruto := public.os_necessidade_bruta(p_so_id);

  with
  bruto as (
    select x.ord, x.i ->> 'origin' as origin, (x.i ->> 'sourceId')::uuid as src,
           (x.i ->> 'required')::numeric as req, coalesce((x.i ->> 'available')::numeric, 0) as disp,
           x.i ->> 'status' as st, (x.i ->> 'productId')::uuid as prod, x.i ->> 'description' as descr
      from jsonb_array_elements(coalesce(v_bruto -> 'items', '[]'::jsonb)) with ordinality x(i, ord)
     where coalesce((x.i ->> 'required')::numeric, 0) > 0
       and x.i ->> 'origin' in ('part', 'free_text', 'purchase_order')
  ),
  cand as (
    -- (1) os itens da conta bruta, com a linha do mesmo vínculo
    select 1 as grupo, b.ord::bigint as ord,
           case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end as origem,
           b.src as vinculo, b.req, b.disp, b.st, b.descr, b.prod, null::uuid as po_forn, null::date as recebido_em,
           m as l
      from bruto b
      left join public.os_material m
        on m.service_order_id = p_so_id
       and m.origem = case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end
       and b.src = case m.origem when 'peca' then m.service_order_part_id
                                 when 'texto_livre' then m.service_order_service_id
                                 else m.purchase_order_item_id end
    union all
    -- (2) item de OC de texto livre da OS que já chegou (saiu da conta bruta) — continua, na mão
    select 2, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, poi.quantity,
           'recebido', poi.description, null, po.supplier_id, po.received_date, m
      from public.purchase_order_items poi
      join public.purchase_orders po on po.id = poi.purchase_order_id
      left join public.os_material m on m.origem = 'oc' and m.purchase_order_item_id = poi.id
     where po.service_order_id = p_so_id and poi.product_id is null and poi.quantity > 0
       and po.status <> 'cancelled'
       and (po.status = 'received' or coalesce(poi.received_qty, 0) >= poi.quantity)
    union all
    -- (3) item de OC cancelada que tinha linha: a sincronização o devolveu a "falta" (ou o dono informou)
    select 3, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, 0,
           'cancelado', poi.description, null, po.supplier_id, null, m
      from public.os_material m
      join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
      join public.purchase_orders po on po.id = poi.purchase_order_id
     where m.service_order_id = p_so_id and m.origem = 'oc' and po.status = 'cancelled'
    union all
    -- (4) o que o dono citou e não está no orçamento (peça embutida, material novo)
    select 4, row_number() over (order by m.descricao, m.id), 'dono', m.service_order_service_id,
           m.quantidade_necessaria, 0, 'dono', m.descricao, null, null, null, m
      from public.os_material m
     where m.service_order_id = p_so_id and m.origem = 'dono'
  ),
  passo1 as (
    select k.*,
           coalesce((k.l).fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false) as informado,
           coalesce((k.l).critico, true) as critico
      from cand k
     where (k.l).situacao is distinct from 'dispensado'
  ),
  passo2 as (
    select q.*,
           case when q.grupo = 1
                then greatest(q.disp, case when q.informado then least(q.req, (q.l).quantidade_na_mao) else 0 end)
                else 0 end as disp_ef
      from passo1 q
  ),
  passo3 as (
    -- A situação efetiva. Só o fato informado muda o item; "na mão" só com a quantidade completa contra a conta de
    -- hoje; o que o dono disse para menos do que a OS pede hoje volta a faltar.
    select q.*,
           case
             when q.grupo = 2 then case when q.informado and (q.l).situacao <> 'na_mao' then (q.l).situacao else 'na_mao' end
             when q.grupo = 4 then (q.l).situacao
             when q.grupo = 3 then case when q.informado then (q.l).situacao else 'falta' end
             when q.disp_ef >= q.req then 'na_mao'
             when q.informado and (q.l).situacao in ('na_mao', 'comprado', 'a_caminho')
                  and (q.l).quantidade_necessaria < q.req then 'falta'
             when q.informado and (q.l).situacao = 'na_mao' then 'falta'
             when q.informado then (q.l).situacao
             when q.st = 'on_order' then 'a_caminho'
             else 'falta' end as sit
      from passo2 q
  ),
  passo4 as (
    -- A OC que cobre o item que o sistema vê "a caminho" (a da própria OS primeiro): previsão, data e fornecedor.
    select q.*, oc.expected_date as oc_prev, oc.criada as oc_criada, oc.po_number as oc_numero, oc.forn as oc_forn,
           pr.supplier_id as prod_forn
      from passo3 q
      left join public.products pr on pr.id = q.prod
      left join lateral (
        select v.expected_date, (v.po_criada_em at time zone 'America/Sao_Paulo')::date as criada, v.po_number,
               po.supplier_id as forn
          from public.v_oc_itens_a_caminho v
          join public.purchase_orders po on po.id = v.purchase_order_id
         where q.grupo = 1 and q.sit = 'a_caminho' and not q.informado and v.pendente > 0
           and case when q.origem = 'oc' then v.purchase_order_item_id = q.vinculo
                    else v.product_id = q.prod and v.conta_como_ja_pedido end
         order by (v.service_order_id is distinct from p_so_id), v.po_criada_em, v.purchase_order_item_id
         limit 1) oc on true
  ),
  passo5 as (
    select q.*,
           case
             when q.sit = 'na_mao' and q.grupo = 1 and q.disp >= q.req and not q.informado then 'estoque'
             when q.informado then (q.l).fonte
             when q.grupo = 2 then 'oc'
             when q.sit = 'a_caminho' and q.grupo = 1 then 'oc'
             else (q.l).fonte end as fonte,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_ate when q.grupo = 1 then q.oc_prev end end as prev_ate,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_fonte
                       when q.grupo = 1 and q.oc_prev is not null then 'oc' end end as prev_fonte,
           -- O informado sem data de compra conta do dia em que o dono contou (conferido_em): a estimativa não anda.
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado
                       then coalesce((q.l).comprado_em, ((q.l).conferido_em at time zone 'America/Sao_Paulo')::date)
                       when q.grupo = 1 then q.oc_criada end end as comprado_em,
           case when q.sit = 'falta' and q.informado then (q.l).compra_prevista_em end as compra_prevista_em,
           case when q.sit = 'na_mao' then
                  case when q.informado or q.grupo = 4 then (q.l).chegou_em
                       when q.grupo = 2 then coalesce((q.l).chegou_em, q.recebido_em)
                       when (q.l).situacao = 'na_mao' then (q.l).chegou_em end end as chegou_em,
           -- O fornecedor: o que o dono disse (cadastrado ou só o nome), senão o da OC, senão o do produto.
           case when q.informado and (q.l).fornecedor_id is null and (q.l).fornecedor_nome is not null then null
                else coalesce(case when q.informado then (q.l).fornecedor_id end, q.oc_forn, q.po_forn,
                              (q.l).fornecedor_id, q.prod_forn) end as forn_id,
           case when q.informado and (q.l).fornecedor_id is null then (q.l).fornecedor_nome end as forn_nome
      from passo4 q
  ),
  passo6 as (
    select q.*, public._agenda_classe_do_fornecedor(q.forn_id) as classe
      from passo5 q
  ),
  passo7 as (
    select q.*, public._agenda_prazo_da_classe(q.classe) as prazo
      from passo6 q
  ),
  passo8 as (
    select q.*,
           case
             when q.sit = 'na_mao' then 'A'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null and q.prev_fonte <> 'dono' then 'B'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then 'C'
             when q.sit in ('comprado', 'a_caminho') then 'D'
             when q.prazo is not null then 'D'
             else 'E' end as nivel,
           case
             when q.sit = 'na_mao' then q.chegou_em
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then q.prev_ate
             when q.sit in ('comprado', 'a_caminho') and q.prazo is not null then
               public.agenda_somar_du(coalesce(q.comprado_em, p_hoje), q.prazo)
             when q.sit = 'falta' and q.prazo is not null then
               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.
               public.agenda_somar_du(greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje), q.prazo)
           end as data,
           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo)) end as compre_ate,
           (select f.name from public.suppliers f where f.id = q.forn_id) as forn_cadastro
      from passo7 q
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', (q.l).id, 'linha', q.vinculo, 'origem', q.origem,
           'descricao', coalesce((q.l).descricao, q.descr), 'curto', public._agenda_linha_curta(coalesce((q.l).descricao, q.descr)),
           'nivel', q.nivel, 'situacao', q.sit, 'data', q.data,
           -- Parcial (parte já na mão, informada ou do estoque): quantas estão na mão e quantas faltam, antes do resto.
           'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                              then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                          replace(trim_scale(q.req)::text, '.', ','),
                                          case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                          replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                              else '' end
           || case
              when q.nivel = 'A' then case when q.data is not null then 'na mão desde ' || public._dia_curto(q.data) else 'na mão' end
              when q.nivel = 'B' then 'chega ' || public._dia_curto(q.data) || case q.prev_fonte
                   when 'oc' then ' (pela OC)' when 'fornecedor' then ' (o fornecedor disse)'
                   when 'nfe' then ' (pela nota)' when 'pix' then ' (pelo Pix)' else '' end
              when q.nivel = 'C' then 'chega ' || public._dia_curto(q.data) || ' (você disse)'
              when q.sit in ('comprado', 'a_caminho') then
                   coalesce('pedido em ' || to_char(q.comprado_em, 'DD/MM'), 'comprado')
                   || case when q.data is not null then ', deve chegar por volta de ' || public._dia_curto(q.data)
                           else ', sem previsão' end
              when q.nivel = 'D' then
                   case when q.compra_prevista_em is not null and q.compra_prevista_em >= p_hoje
                        then format('comprando %s, chega por volta de %s', public._dia_curto(q.compra_prevista_em),
                                    public._dia_curto(q.data))
                        else 'se comprar hoje, chega por volta de ' || public._dia_curto(q.data) end
              when q.forn_nome is not null then format('a comprar de %s, sem prazo conhecido', q.forn_nome)
              when q.forn_id is not null then format('a comprar de %s, sem cidade/UF no cadastro', public._agenda_nome_curto(q.forn_cadastro))
              else 'a comprar, sem fornecedor' end,
           'fonte', q.fonte, 'previsao_fonte', q.prev_fonte, 'trecho', (q.l).trecho, 'critico', q.critico,
           'quantidade', trim_scale(q.req), 'na_mao', trim_scale(case when q.sit = 'na_mao' then q.req else q.disp_ef end),
           'fornecedor', coalesce(q.forn_nome, public._agenda_nome_curto(q.forn_cadastro)),
           'classe', q.classe, 'prazo_du', q.prazo,
           'comprado_em', q.comprado_em, 'compra_prevista_em', q.compra_prevista_em,
           'compre_ate', q.compre_ate,
           'atrasado', q.sit in ('comprado', 'a_caminho') and q.data is not null and q.data < p_hoje,
           'sem_data', q.nivel = 'E' or (q.nivel = 'D' and q.data is null))
           order by q.grupo, q.ord), '[]'::jsonb)
    into v_itens
    from passo8 q;

  v_crit := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                       where (e ->> 'critico')::boolean), '[]'::jsonb);
  v_n_itens := jsonb_array_length(v_itens);
  v_conferido := p.material_conferido_em is not null
              or exists (select 1 from public.os_material m
                          where m.service_order_id = p_so_id and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'));

  -- "Tem peça embutida?": linha de texto livre que NÃO entra na compra e (a) vale >= peca_embutida_acima, ou (b) o
  -- classificador lê como material (a unidade não é 'unit'), ou (c) cita peça/material. Some quando o dono responde
  -- por ela (linha do dono ligada à linha) ou quando ele diz "não tem peça a comprar" depois que a linha nasceu.
  select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot,
                                               'curto', public._agenda_linha_curta(s.name_snapshot),
                                               'valor', s.line_total)
                            order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb)
    into v_embut
    from public.service_order_services s
   where s.service_order_id = p_so_id and s.service_id is null
     and not (s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0 and public.free_text_is_material(s.name_snapshot))
     and (coalesce(s.line_total, 0) >= c.peca_embutida_acima
          or public.free_text_is_material(s.name_snapshot)
          or public._agenda_normal(s.name_snapshot) ~ '\m(peca|pecas|material)\M')
     and not exists (select 1 from public.os_material m
                      where m.service_order_id = p_so_id and m.origem = 'dono' and m.service_order_service_id = s.id)
     and not (p.material_conferido_em is not null and p.material_conferido_em > s.created_at);

  -- O estado do material (do mais forte ao mais fraco).
  v_mat_estado := case
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'atrasado')::boolean) then 'atrasado'
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'sem_data')::boolean) then 'sem_previsao'
    when jsonb_array_length(v_embut) > 0 or (v_n_itens = 0 and not v_conferido) then 'nao_conferido'
    when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
    else 'completo' end;

  -- DPM: a data mais tarde dos críticos fora de A; o início pelo material = chegada + folga_material_du, sem folga
  -- remota (revisão §7: o prazo "outro estado" já cobre o transporte).
  if v_mat_estado not in ('atrasado', 'sem_previsao') then
    select e into v_gargalo from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'nivel' <> 'A' order by (e ->> 'data')::date desc, o limit 1;
    v_dpm := (v_gargalo ->> 'data')::date;
    if v_dpm is not null then
      v_inicio_mat := public.agenda_somar_du(v_dpm, c.folga_material_du);
    end if;
    v_est := greatest(v_est_sm, v_inicio_mat);
  end if;
  v_confianca := (select e ->> 'nivel' from jsonb_array_elements(v_crit) e
                   order by case e ->> 'nivel' when 'E' then 0 when 'D' then 1 when 'C' then 2 when 'B' then 3 else 4 end
                   limit 1);

  -- ── Duração ──
  v_sug := public.os_duracao_sugerida(p_so_id);
  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  if p.dias is not null then
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                                 'eh_dono', py.kind = 'socio', 'turnos', e.turnos)
                              -- você primeiro; quem vai o dia todo antes de quem vai meio turno
                              order by py.kind = 'socio' desc, e.turnos = 'dia' desc, py.name, e.payee_id), '[]'::jsonb),
           -- Meios-dias por pessoa: o dia todo = 2 por dia; só de manhã ou só à tarde = 1 turno em cada dia que o
           -- serviço ocupa (meio dia com o João à tarde = 1 meio-dia; 1,5 dia à tarde = 2).
           coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0)
      into v_equipe, v_meios
      from public.os_planejamento_equipe e
      join public.payees py on py.id = e.payee_id
     where e.service_order_id = p_so_id;
    -- Sem equipe dita, a conta de diárias usa as pessoas da sugestão (é leitura, não vira número gravado). Na conta da
    -- equipe (a que a capacidade cobre), você só entra quando tem padrão.
    v_diarias_eq := case when jsonb_array_length(v_equipe) = 0
                         then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                         else (select coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0) / 2
                                 from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
                                where e.service_order_id = p_so_id
                                  and (py.kind <> 'socio' or v_dono_padrao)) end;
    v_dur := jsonb_build_object(
      'fonte', p.estimativa_fonte, 'dias', trim_scale(p.dias), 'equipe', v_equipe,
      'meios_dias', trim_scale(v_meios),
      'diarias', trim_scale(case when jsonb_array_length(v_equipe) = 0
                                 then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                                 else v_meios / 2 end),
      'diarias_equipe', trim_scale(v_diarias_eq),
      -- Diárias-pessoa da equipe para o backlog: o que o dono disse é um número só (otimista = realista).
      'dp_otimista', trim_scale(v_diarias_eq), 'dp_realista', trim_scale(v_diarias_eq),
      'equipe_dita', jsonb_array_length(v_equipe) > 0,
      'texto', public._agenda_dias(p.dias)
               || case when jsonb_array_length(v_equipe) > 0 then ': ' || public._agenda_lista(array(
                    select case when (x ->> 'eh_dono')::boolean then 'você' else x ->> 'nome' end
                           || case x ->> 'turnos' when 'dia' then ' (dia todo)' when 'manha' then ' (de manhã)'
                                                  else ' (à tarde)' end
                      from jsonb_array_elements(v_equipe) x), null) else '' end
               || case p.estimativa_fonte when 'aceita' then ' (você aceitou a minha estimativa)' else ' (você disse)' end,
      'sugestao', v_sug);
    v_dias_re := p.dias;
  else
    v_dur := jsonb_build_object(
      'fonte', 'sugerida',
      'dias', v_sug -> 'sugerida', 'dias_otimista', v_sug -> 'dias_otimista', 'dias_realista', v_sug -> 'dias_realista',
      'pessoas', v_sug -> 'pessoas', 'equipe', '[]'::jsonb, 'equipe_dita', false,
      'diarias_otimista', v_sug -> 'diarias_otimista', 'diarias_realista', v_sug -> 'diarias_realista',
      -- Diárias-pessoa da faixa (dias × pessoas) para o backlog: 74 = 3 a 6 (spec §6).
      'dp_otimista', v_sug -> 'diarias_otimista', 'dp_realista', v_sug -> 'diarias_realista',
      'sem_base', coalesce((v_sug ->> 'sem_base')::boolean, false),
      'texto', v_sug ->> 'texto', 'sugestao', v_sug);
    v_dias_re := (v_sug ->> 'dias_realista')::numeric;
  end if;

  v_pres := public.os_presenca_do_dono(p_so_id);

  -- ── Prazo e razão crítica ──
  v_prazo := coalesce(p.precisa_ate, public.agenda_somar_du(v_aprov, c.prazo_padrao_du));
  v_prazo_fnt := case when p.precisa_ate is not null then 'dono' else 'padrão' end;
  if v_dias_re is not null and v_dias_re > 0 then
    v_razao := round(greatest(public.agenda_du_entre(p_hoje, v_prazo), 0) / v_dias_re, 2);
  end if;

  -- ── Execução: parada = em andamento sem diária ligada nos últimos parada_du úteis e sem janela futura ──
  if so.status = 'in_progress' then
    select max(ws.data) into v_ult_diaria
      from public.work_shifts ws
     where ws.data <= p_hoje and ws.tipo in ('normal', 'diaria') and coalesce(ws.fracao, 1) > 0
       and (ws.service_order_id = p_so_id
            or exists (select 1 from public.work_shift_os x where x.shift_id = ws.id and x.service_order_id = p_so_id));
    v_parada := (v_ult_diaria is null or v_ult_diaria < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false;
  end if;

  -- ── Restrições: {tipo, quem, texto, bloqueia, desde, compre_ate, pergunta} ──
  if so.status = 'draft' and so.quote_status = 'approved' and so.merged_into_id is null then
    v_r := v_r || jsonb_build_object('tipo', 'orcamento', 'quem', 'dono', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', 'converter em OS ou arquivar?',
      'texto', format('%s em %s e nunca virou OS: converter ou arquivar?',
                      case when so.signed_at is not null then 'assinado' else 'aprovado' end, to_char(v_aprov, 'DD/MM')));
  end if;
  if (so.quote_status = 'awaiting_deposit' and v_pago = 0) or v_pend > 0 then
    v_r := v_r || jsonb_build_object('tipo', 'sinal', 'quem', 'cliente', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_pend > 0 then 'esperando o sinal de ' || public._brl(v_pend) else 'esperando o sinal' end);
  end if;
  if so.status = 'awaiting_client' then
    v_r := v_r || jsonb_build_object('tipo', 'cliente', 'quem', 'cliente', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', null, 'texto', 'esperando o cliente');
  end if;
  if p.escopo_em_aberto is not null then
    v_r := v_r || jsonb_build_object('tipo', 'escopo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', p.escopo_em_aberto, 'texto', p.escopo_em_aberto);
  end if;
  if p.dias is null then
    v_r := v_r || jsonb_build_object('tipo', 'duracao', 'quem', 'dono', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', 'quantos dias e com quem?',
      'texto', case when coalesce((v_sug ->> 'sem_base')::boolean, false)
                    then 'quantos dias e com quem? (o orçamento não dá base para estimar)'
                    else format('quantos dias e com quem? (chute: %s, %s)',
                                public._agenda_faixa_dias((v_sug ->> 'dias_otimista')::numeric, (v_sug ->> 'dias_realista')::numeric),
                                case when (v_sug ->> 'pessoas')::int = 1 then '1 pessoa'
                                     else (v_sug ->> 'pessoas') || ' pessoas' end) end);
  end if;
  -- Com peça embutida em aberto, a pergunta dela já é o "tem peça a comprar?" (mais precisa): não repete.
  if v_n_itens = 0 and not v_conferido and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'material_nao_conferido', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', 'tem peça a comprar?', 'texto', 'tem peça a comprar? (o orçamento não tem nenhuma)');
  end if;
  v_n := jsonb_array_length(v_embut);
  if v_n > 0 then
    v_txt := array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' ou ')
             || case when v_n > 2 then format(' (e mais %s)', v_n - 2) else '' end;
    v_r := v_r || jsonb_build_object('tipo', 'peca_embutida', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', format('tem peça embutida em %s?', v_txt),
      'texto', format('tem peça embutida em %s?', v_txt));
  end if;

  -- O que falta comprar: sem fornecedor/classe (E) pergunta "de quem e quando?"; com classe e sem compra combinada,
  -- "compre até" (programação para trás; se já passou, "comprando hoje, chega por volta de …"). A compra que o dono já
  -- combinou (dia que ainda não passou) sem prazo conhecido NÃO volta a perguntar "de quem e quando": vai à parte.
  select count(*) filter (where e ->> 'situacao' = 'falta'
                          and (((e ->> 'sem_data')::boolean and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
                               or e ->> 'compre_ate' is not null)),
         count(*) filter (where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean
                          and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
    into v_n_falta, v_n_sem
    from jsonb_array_elements(v_crit) e;
  if v_n_falta > 0 then
    select e into v_compra from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'situacao' = 'falta' and e ->> 'compre_ate' is not null
     order by (e ->> 'compre_ate')::date, o limit 1;
    v_cond := case when v_compra is null then ''
                   when (v_compra ->> 'compre_ate')::date < p_hoje then
                     format('comprando hoje, "%s" chega por volta de %s', v_compra ->> 'curto',
                            public._dia_curto(public.agenda_somar_du(p_hoje, (v_compra ->> 'prazo_du')::int)))
                   else format('"%s": compre até %s', v_compra ->> 'curto',
                               public._dia_curto((v_compra ->> 'compre_ate')::date)) end;
    if v_n_sem > 0 then
      v_txt := case when so.status = 'awaiting_parts' then public._agenda_itens(v_n_falta) || ' sem compra registrada'
                    else public._agenda_itens(v_n_falta) || ' a comprar: de quem e quando?' end;
      v_r := v_r || jsonb_build_object('tipo', 'sem_previsao', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate',
        'pergunta', case when so.status = 'awaiting_parts' then 'o que já está na mão e o que falta? Quando chega?'
                         else format('o material (%s) — compra quando e onde?', public._agenda_itens(v_n_falta)) end,
        'texto', v_txt || case when v_cond <> '' then ' (' || v_cond || ')' else '' end);
    else
      v_r := v_r || jsonb_build_object('tipo', 'compre_ate', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate', 'pergunta', 'compra quando?',
        'texto', public._agenda_itens(v_n_falta) || ' a comprar: ' || v_cond);
    end if;
  end if;

  -- Compra combinada ("compro terça na Casa do Eletricista") sem prazo de entrega conhecido: o que o dono já disse fica
  -- dito; a pergunta é só o que falta — quando chega (com fornecedor) ou de quem (sem).
  select count(*) as n, min((e ->> 'compra_prevista_em')::date) as de, max((e ->> 'compra_prevista_em')::date) as ate,
         bool_and(e ->> 'fornecedor' is not null) as com_forn, count(distinct e ->> 'fornecedor') as n_forn,
         min(e ->> 'fornecedor') as forn, min(e ->> 'curto') as curto
    into v_cc
    from jsonb_array_elements(v_crit) e
   where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean and (e ->> 'compra_prevista_em')::date >= p_hoje;
  if v_cc.n > 0 then
    v_txt := case when v_cc.de = v_cc.ate then public._dia_curto(v_cc.de)
                  else format('de %s a %s', public._dia_curto(v_cc.de), public._dia_curto(v_cc.ate)) end;
    v_r := v_r || jsonb_build_object('tipo', 'compra_sem_prazo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null,
      'pergunta', case when v_cc.com_forn then format('quando chega a compra de %s?', v_txt)
                       else format('de quem é a compra de %s?', v_txt) end,
      'texto', case when v_cc.n = 1 then format('"%s"', v_cc.curto) else public._agenda_itens(v_cc.n::int) end
               || ': você compra ' || v_txt
               || case when v_cc.com_forn and v_cc.n_forn = 1 then ', fornecedor ' || v_cc.forn else '' end
               || case when v_cc.com_forn then '; sem prazo de entrega conhecido: quando chega?'
                       else '; de quem? (sem o fornecedor não sei quando chega)' end);
  end if;

  -- Comprado sem previsão e sem classe: "chegou?"; previsão vencida: "venceu em dd/mm: chegou?".
  for v_x in select e from jsonb_array_elements(v_crit) with ordinality t(e, o)
              where e ->> 'situacao' in ('comprado', 'a_caminho')
                and ((e ->> 'sem_data')::boolean or (e ->> 'atrasado')::boolean)
              order by o
  loop
    if (v_x ->> 'atrasado')::boolean then
      v_r := v_r || jsonb_build_object('tipo', 'atrasado', 'quem', 'dono', 'bloqueia', true, 'desde', v_x ->> 'data',
        'compre_ate', null, 'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('a previsão de "%s" venceu em %s: chegou?', v_x ->> 'curto', to_char((v_x ->> 'data')::date, 'DD/MM')));
    else
      v_r := v_r || jsonb_build_object('tipo', 'comprado_sem_previsao', 'quem', 'dono', 'bloqueia', true,
        'desde', v_x ->> 'comprado_em', 'compre_ate', null,
        'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('"%s" (%s) chegou?', v_x ->> 'curto',
                        coalesce('pedido em ' || to_char((v_x ->> 'comprado_em')::date, 'DD/MM'), 'comprado, sem previsão')));
    end if;
  end loop;

  if v_d_bem is null or v_d_bem > p_hoje + 1 then
    v_r := v_r || jsonb_build_object('tipo', 'bem', 'quem', 'cliente', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                    else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end);
  end if;
  if p.nao_antes_de is not null and p.nao_antes_de > p_hoje then
    v_r := v_r || jsonb_build_object('tipo', 'nao_antes', 'quem', 'terceiro', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo));
  end if;
  if v_parada then
    v_r := v_r || jsonb_build_object('tipo', 'parada', 'quem', 'dono', 'bloqueia', true, 'desde', v_ult_diaria,
      'compre_ate', null, 'pergunta', 'parou?',
      'texto', case when v_ult_diaria is null then 'em andamento e sem diária lançada: parou?'
                    else format('em andamento sem diária desde %s: parou?', to_char(v_ult_diaria, 'DD/MM')) end);
  end if;

  -- Orçamento aprovado que nunca virou OS, ou sinal pendente: quem destrava é a conversão (o dono) ou o sinal (o
  -- cliente), não a compra — comprar peça de um orçamento que pode ser arquivado não é o próximo passo. As perguntas do
  -- material continuam na lista (a visão da OS e a rodada mostram), sem travar até a conversão e o sinal.
  if exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'sinal')) then
    select coalesce(jsonb_agg(case when e ->> 'tipo' in ('atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao',
                                                         'compre_ate', 'peca_embutida', 'material_nao_conferido')
                                   then jsonb_set(e, '{bloqueia}', 'false'::jsonb) else e end order by o), '[]'::jsonb)
      into v_r
      from jsonb_array_elements(v_r) with ordinality t(e, o);
  end if;

  -- A mais forte primeiro: o que trava antes do que só informa, e na ordem do bloco "travado" (spec §5.4).
  select coalesce(jsonb_agg(e order by (e ->> 'bloqueia')::boolean desc,
           array_position(array['parada', 'atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                                'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal', 'cliente',
                                'duracao', 'bem', 'nao_antes'], e ->> 'tipo'), o), '[]'::jsonb)
    into v_r
    from jsonb_array_elements(v_r) with ordinality t(e, o);

  -- ── Estado (o 1º que valer) ──
  v_estado := case
    when p.congelada_ate is not null and p.congelada_ate >= p_hoje then 'congelada'
    when so.status in ('completed', 'invoiced') then 'concluida'
    when so.status = 'cancelled' or so.merged_into_id is not null
         or (so.status = 'draft' and coalesce(so.quote_status, 'draft') not in ('approved', 'awaiting_deposit')) then 'fora_da_carteira'
    when so.status = 'in_progress' then case when v_parada then 'parada' else 'em_execucao' end
    when coalesce(v_ag_ate, v_ag_de) >= p_hoje then 'marcada'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
    when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
    when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
    else 'pronta' end;

  if v_estado in ('concluida', 'fora_da_carteira') and (so.status in ('completed', 'invoiced', 'cancelled')
                                                         or so.merged_into_id is not null) then
    v_r := '[]'::jsonb;
  end if;

  -- A restrição do dono que mais pesa (a 1ª da lista que trava e é dele).
  select e into v_principal from jsonb_array_elements(v_r) with ordinality t(e, o)
   where (e ->> 'bloqueia')::boolean and e ->> 'quem' = 'dono' order by o limit 1;

  v_quase := v_estado = 'aguardando_material'
         and (select count(*) from jsonb_array_elements(v_r) e where (e ->> 'bloqueia')::boolean) = 1
         and v_principal ->> 'tipo' = 'material_nao_conferido';

  -- O texto do estado, para vir depois do nome do cliente ("Lenine: falta você dizer se tem peça a comprar").
  v_estado_txt := case v_estado
    -- "(rever …)" só quando o dia de rever não é o mesmo do fim da espera (é o padrão do rascunho).
    when 'congelada' then 'em espera até ' || public._dia_curto(p.congelada_ate)
                          || case when p.revisar_em is distinct from p.congelada_ate
                                  then coalesce(' (rever ' || public._dia_curto(p.revisar_em) || ')', '') else '' end
    when 'concluida' then case so.status when 'invoiced' then 'faturado' else 'concluído' end
    when 'fora_da_carteira' then public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, so.juntado_em, false)
    when 'em_execucao' then 'em andamento'
    when 'parada' then case when v_ult_diaria is null then 'em andamento e sem diária lançada'
                            else 'em andamento sem diária desde ' || to_char(v_ult_diaria, 'DD/MM') end
    when 'marcada' then case when v_ag_de is null or v_ag_de = v_ag_ate then 'marcado para ' || public._dia_curto(coalesce(v_ag_ate, v_ag_de))
                             else format('marcado de %s a %s', public._dia_curto(v_ag_de), public._dia_curto(v_ag_ate)) end
    when 'sem_sinal' then (select e ->> 'texto' from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal' limit 1)
    when 'aguardando_cliente' then case
      when so.status = 'awaiting_client' then 'esperando o cliente'
      when v_bem_tudo then case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                                else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end
      else format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo) end
    -- O orçamento parado vem antes do escopo em aberto (a ordem do bloco "travado").
    when 'esperando_voce' then case
      when so.status = 'draft' and so.quote_status = 'approved'
        then format('%s em %s e nunca virou OS', case when so.signed_at is not null then 'assinado' else 'aprovado' end,
                    to_char(v_aprov, 'DD/MM'))
      else 'falta você decidir: ' || p.escopo_em_aberto end
    when 'aguardando_material' then case v_principal ->> 'tipo'
      when 'atrasado' then 'falta você dizer se ' || replace(v_principal ->> 'pergunta', ' chegou?', '') || ' chegou (a previsão venceu)'
      when 'sem_previsao' then case when so.status = 'awaiting_parts'
                                    then format('falta você dizer o que já está na mão e o que falta (%s sem compra registrada)',
                                                public._agenda_itens(v_n_falta))
                                    else 'falta você dizer de quem e quando comprar ' || public._agenda_itens(v_n_falta) end
      when 'comprado_sem_previsao' then 'falta você dizer se ' || replace(v_principal ->> 'texto', ' chegou?', '') || ' chegou'
      when 'compra_sem_prazo' then 'falta você dizer ' || rtrim(v_principal ->> 'pergunta', '?')
      when 'peca_embutida' then 'falta você dizer se tem peça embutida em '
                                || array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' e ')
                                || case when jsonb_array_length(v_embut) > 2
                                        then format(' (e mais %s)', jsonb_array_length(v_embut) - 2) else '' end
      else 'falta você dizer se tem peça a comprar' end
    else -- pronta
      case when v_est is not null and v_est > public.agenda_somar_du(p_hoje, 1) then
             'pronto a partir de ' || public._dia_curto(v_est)
             || case when v_inicio_mat is not null and v_inicio_mat >= v_est_sm then
                  (select case
                        when e ->> 'nivel' in ('B', 'C') then format(', se "%s" chegar %s', e ->> 'curto', public._dia_curto(v_dpm))
                        when e ->> 'situacao' = 'falta' and e ->> 'compra_prevista_em' is not null
                             and (e ->> 'compra_prevista_em')::date >= p_hoje
                          then ', se a compra sair ' || public._dia_curto((e ->> 'compra_prevista_em')::date)
                        when e ->> 'situacao' = 'falta' then ', se comprar hoje'
                        else format(', se "%s" chegar por volta de %s', e ->> 'curto', public._dia_curto(v_dpm)) end
                        from jsonb_array_elements(v_crit) with ordinality t(e, o)
                       where e ->> 'nivel' <> 'A' and (e ->> 'data')::date = v_dpm order by o limit 1)
                else '' end
           else 'pronto para começar' end
  end;

  return jsonb_build_object(
    'ok', true, 'os', so.id, 'numero', so.service_order_number, 'cliente', so.cliente_nome,
    'cliente_curto', public._agenda_nome_curto(so.cliente_nome), 'unidade', so.bem,
    'eh_orcamento', so.status = 'draft', 'status', so.status, 'quote_status', so.quote_status,
    'na_carteira', v_na_cart, 'aprovada_em', v_aprov,
    'estado', v_estado, 'estado_texto', v_estado_txt, 'quase_pronta', v_quase,
    'restricoes', v_r,
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em),
    'duracao', v_dur,
    'presenca_dono', v_pres,
    'est', v_est, 'est_texto', public._dia_curto(v_est), 'est_sem_material', v_est_sm,
    'prazo_efetivo', v_prazo, 'prazo_texto', public._dia_curto(v_prazo), 'prazo_fonte', v_prazo_fnt,
    'razao_critica', v_razao,
    'marcada', case when v_ag_de is not null or v_ag_ate is not null
                    then jsonb_build_object('de', v_ag_de, 'ate', v_ag_ate) end,
    'ultima_diaria', v_ult_diaria);
end;
$function$;

comment on function public.os_prontidao(uuid, date) is
  'Agenda de Produção (Fase 1, P3): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → marcada → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Também aceita OS fora da carteira.';

create or replace function public.os_prontidao_carteira(p_hoje date default public._hoje_brt())
 returns setof jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select public.os_prontidao(k.service_order_id, p_hoje)
    from public.os_carteira(p_hoje) k
   order by k.numero collate "C", k.service_order_id;
$function$;

comment on function public.os_prontidao_carteira(date) is
  'Agenda de Produção (Fase 1, P3): os_prontidao de cada OS da carteira, na ordem da carteira — a leitura única das funções de texto.';

-- ── 8. Capacidade ───────────────────────────────────────────────────────────────────────────────────────

-- Quem conta na grade: o dono (sempre, para dizer "sem padrão") e a equipe — diarista/prestador/funcionário ativo,
-- com cadastro de diarista vigente em p_hoje e alguma linha de disponibilidade em vigor (o Mickael sai pela regra
-- da semente, não pelo nome).
create or replace function public.agenda_capacidade(p_de date, p_ate date, p_hoje date default public._hoje_brt())
 returns table (payee_id uuid, pessoa text, eh_dono boolean, dia date, turno text, situacao text,
                meios_esperados numeric, origem text, motivo text)
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  c      public.agenda_config := public._agenda_cfg();
  v_dono uuid := public._agenda_dono(null);
begin
  if p_de is null or p_ate is null or p_ate < p_de then
    raise exception 'agenda_capacidade: período inválido (% a %)', p_de, p_ate using errcode = '22023';
  end if;
  if p_ate - p_de > 400 then
    raise exception 'agenda_capacidade: período longo demais (% dias)', p_ate - p_de using errcode = '22023';
  end if;

  return query
  with
  gente as (
    select py.id, public._agenda_nome_curto(py.name) as nome, py.id is not distinct from v_dono as dono
      from public.payees py
     where py.active
       and (py.id is not distinct from v_dono
            or (py.kind in ('prestador', 'diarista', 'funcionario')
                and exists (select 1 from public.work_profiles w
                             where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                               and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
                and exists (select 1 from public.agenda_disponibilidade d
                             where d.payee_id = py.id and d.substituida_em is null)))
  ),
  grade as (
    select g.id, g.nome, g.dono, d::date as dia, extract(isodow from d)::int as dow, t.turno, t.ord
      from gente g
      cross join generate_series(p_de, p_ate, interval '1 day') d
      cross join (values ('manha', 1), ('tarde', 2)) t(turno, ord)
  ),
  regra as (
    select gr.*,
           ei.nota as ei_nota, ei.trecho as ei_trecho, ei.origem as ei_origem, ei.id as ei_id,
           ed.situacao as ed_sit, ed.nota as ed_nota, ed.origem as ed_origem, ed.id as ed_id,
           rc.nota as rc_nota, rc.id as rc_id,
           pi.nota as pi_nota, pi.origem as pi_origem, pi.id as pi_id,
           pd.nota as pd_nota, pd.origem as pd_origem, pd.frequencia as pd_freq, pd.id as pd_id,
           public.agenda_feriado(gr.dia) as feriado
      from grade gr
      left join lateral (   -- exceção da pessoa: não vem
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.periodo @> gr.dia
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = gr.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) ei on true
      left join lateral (   -- exceção da pessoa: vem (confirmada vence disponível)
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.periodo @> gr.dia
           and d.situacao in ('confirmada', 'disponivel') and (d.turno is null or d.turno = gr.turno)
         order by d.situacao = 'confirmada' desc, d.turno is not null desc, d.criado_em desc, d.id desc limit 1) ed on true
      left join lateral (   -- recesso (sem pessoa)
        select d.* from public.agenda_disponibilidade d
         where d.payee_id is null and d.substituida_em is null and d.periodo @> gr.dia
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = gr.turno)
         order by d.criado_em desc, d.id desc limit 1) rc on true
      left join lateral (   -- padrão: não vem neste turno ("sexta à tarde, escritório")
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.dias_semana @> array[gr.dow]::smallint[]
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = gr.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) pi on true
      left join lateral (   -- padrão: vem
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.dias_semana @> array[gr.dow]::smallint[]
           and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = gr.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) pd on true
  )
  select r.id, r.nome, r.dono, r.dia, r.turno,
         case
           when r.ei_id is not null then 'indisponivel'
           when r.ed_id is not null then 'livre'
           when r.rc_id is not null then 'indisponivel'
           when r.dow = 7 or (r.dow = 6 and not c.sabado_util) then 'fim_de_semana'
           when r.feriado is not null then 'feriado'
           when r.pi_id is not null then 'indisponivel'
           when r.pd_id is not null then 'livre'
           else 'sem_padrao' end,
         case
           when r.ei_id is not null then 0::numeric
           when r.ed_id is not null then 1::numeric
           when r.rc_id is not null or r.dow = 7 or (r.dow = 6 and not c.sabado_util) or r.feriado is not null
                or r.pi_id is not null then 0::numeric
           when r.pd_id is not null then case when r.pd_origem = 'historico' then coalesce(r.pd_freq, 0) else 1::numeric end
           else 0::numeric end,
         case
           when r.ei_id is not null then r.ei_origem
           when r.ed_id is not null then r.ed_origem
           when r.rc_id is not null or r.dow = 7 or (r.dow = 6 and not c.sabado_util) or r.feriado is not null then null
           when r.pi_id is not null then r.pi_origem
           when r.pd_id is not null then r.pd_origem
           else null end,
         case
           when r.ei_id is not null then coalesce(r.ei_nota, r.ei_trecho, 'não vem')
           when r.ed_id is not null then coalesce(r.ed_nota, case r.ed_sit when 'confirmada' then 'confirmado' else 'combinado' end)
           when r.rc_id is not null then coalesce(r.rc_nota, 'recesso')
           when r.dow = 7 then 'domingo'
           when r.dow = 6 and not c.sabado_util then 'sábado só quando vocês combinam'
           when r.feriado is not null then r.feriado
           when r.pi_id is not null then coalesce(r.pi_nota, 'não vem neste turno')
           when r.pd_id is not null then r.pd_nota
           when r.dono then 'você ainda não disse quais dias fica em campo'
           else 'sem padrão' end
    from regra r
   order by r.dono desc, r.nome, r.id, r.dia, r.ord;
end;
$function$;

comment on function public.agenda_capacidade(date, date, date) is
  'Agenda de Produção (Fase 1, P3): a grade por pessoa × dia × turno (manhã, tarde) — o dono e a equipe (diarista com cadastro vigente e disponibilidade em vigor). situacao: indisponivel (exceção da pessoa, recesso ou padrão "não vem neste turno"), livre (exceção "vem"/confirmada = 1 meio-dia; padrão do histórico = a frequência; padrão do dono = 1), fim_de_semana (domingo; sábado só por exceção, salvo agenda_config.sabado_util), feriado (o nome), sem_padrao. A exceção da pessoa vence o calendário; exceção indisponível > confirmada > disponível > padrão; o mais novo vence o empate.';

create or replace function public.agenda_capacidade_semanal(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  c         public.agenda_config := public._agenda_cfg();
  v_dono    uuid := public._agenda_dono(null);
  v_pessoas jsonb;
  v_total   numeric;
  v_conta_dono boolean;
  v_ultima  date;
  v_sem     int;
begin
  -- A semana típica pelo PADRÃO de cada pessoa (sem exceção nem feriado): Σ dos meios-dias esperados ÷ 2.
  with
  gente as (
    select py.id, py.name, public._agenda_nome_curto(py.name) as nome, py.id is not distinct from v_dono as dono
      from public.payees py
     where py.active
       and exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = py.id and d.substituida_em is null and d.dias_semana is not null
                      and d.situacao in ('disponivel', 'confirmada'))
       and (py.id is not distinct from v_dono
            or (py.kind in ('prestador', 'diarista', 'funcionario')
                and exists (select 1 from public.work_profiles w
                             where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                               and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))))
  ),
  semana as (
    select g.*, s.dow, t.turno
      from gente g
      cross join generate_series(1, case when c.sabado_util then 6 else 5 end) s(dow)
      cross join (values ('manha'), ('tarde')) t(turno)
  ),
  meios as (
    select s.id, s.nome, s.dono, s.name,
           case when pi.id is not null then 0
                when pd.id is not null then case when pd.origem = 'historico' then coalesce(pd.frequencia, 0) else 1 end
                else 0 end as m
      from semana s
      left join lateral (
        select d.id from public.agenda_disponibilidade d
         where d.payee_id = s.id and d.substituida_em is null and d.dias_semana @> array[s.dow]::smallint[]
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = s.turno)
         limit 1) pi on true
      left join lateral (
        select d.id, d.origem, d.frequencia from public.agenda_disponibilidade d
         where d.payee_id = s.id and d.substituida_em is null and d.dias_semana @> array[s.dow]::smallint[]
           and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = s.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) pd on true
  ),
  porpessoa as (
    select m.id, m.nome, m.dono, m.name, sum(m.m) / 2 as diarias from meios m group by m.id, m.nome, m.dono, m.name
  )
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', q.id, 'nome', q.nome, 'eh_dono', q.dono,
                                               'diarias_semana', round(q.diarias, 2))
                            order by q.dono desc, q.name, q.id), '[]'::jsonb),
         coalesce(sum(q.diarias), 0),
         coalesce(bool_or(q.dono), false)
    into v_pessoas, v_total, v_conta_dono
    from porpessoa q;

  select max(ws.data) into v_ultima
    from public.work_shifts ws
   where ws.tipo = 'diaria' and ws.fracao > 0 and ws.data <= p_hoje;
  v_sem := public.agenda_du_entre(v_ultima, p_hoje);

  return jsonb_build_object(
    'diarias_semana', round(v_total, 2),
    'comprometivel', round(v_total * c.carga_max, 2),
    'carga_max', c.carga_max,
    'conta_dono', v_conta_dono,
    'pessoas', v_pessoas,
    'ultima_diaria', v_ultima,
    'dias_sem_lancar', v_sem,
    'aviso', case when v_ultima is null then 'nenhuma diária lançada ainda'
                  when v_sem >= 2 then 'nenhuma diária foi lançada depois de ' || public._dia_curto(v_ultima) end);
end;
$function$;

comment on function public.agenda_capacidade_semanal(date) is
  'Agenda de Produção (Fase 1, P3): o ÚNICO número de capacidade — diarias_semana = Σ, por pessoa com padrão, dos meios-dias esperados da semana típica ÷ 2 (padrão do histórico = a frequência; do dono = 1; "não vem neste turno" = 0); comprometivel = diarias_semana × agenda_config.carga_max. O dono só entra quando tem padrão (conta_dono). Também: a última diária lançada, os dias úteis sem lançar e o aviso quando passam de 1.';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- Leituras: security invoker (a RLS de quem lê vale), STABLE/IMMUTABLE, sem anon. A sincronização (definer) segue
-- só para service_role.
revoke all on function
  public._agenda_dono(uuid), public._agenda_linha_curta(text), public._agenda_itens(integer),
  public._agenda_rotulo_os(text, text, boolean, text, boolean), public.os_carteira(date),
  public.agenda_resolver_os(text, date, boolean), public.agenda_resolver_pessoa(text, uuid, date),
  public._agenda_classe_do_fornecedor(uuid), public._agenda_prazo_da_classe(text), public.os_duracao_sugerida(uuid),
  public.os_presenca_do_dono(uuid), public.os_prontidao(uuid, date), public.os_prontidao_carteira(date),
  public.agenda_capacidade(date, date, date), public.agenda_capacidade_semanal(date)
  from public, anon;
grant execute on function
  public._agenda_dono(uuid), public._agenda_linha_curta(text), public._agenda_itens(integer),
  public._agenda_rotulo_os(text, text, boolean, text, boolean), public.os_carteira(date),
  public.agenda_resolver_os(text, date, boolean), public.agenda_resolver_pessoa(text, uuid, date),
  public._agenda_classe_do_fornecedor(uuid), public._agenda_prazo_da_classe(text), public.os_duracao_sugerida(uuid),
  public.os_presenca_do_dono(uuid), public.os_prontidao(uuid, date), public.os_prontidao_carteira(date),
  public.agenda_capacidade(date, date, date), public.agenda_capacidade_semanal(date)
  to authenticated, service_role;

revoke all on function public.os_material_sincronizar_carteira(date) from public, anon, authenticated;
grant execute on function public.os_material_sincronizar_carteira(date) to service_role;
