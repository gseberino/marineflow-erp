-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P3: as notas do e-mail e o Pix — a NF-e
-- que chegou por e-mail vira remessa no nível da NOTA (o despacho e a previsão), a pergunta "é material de qual serviço?",
-- a chegada pela nota importada, a pergunta "o Pix à Premel é material do Vanderlei? Já está na mão?" e a resposta do dono
-- pela conversa (material_informar com o aviso).
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§3.2, §5.3, §5.7, §6.1–6.3, d1, d2, d5, d16). Decisões do dono 23/10
-- (dinheiro e compra são críticos; vínculo sempre pergunta). Depende de 20261027100000 (material_remessas, os_material
-- .remessa_id, os modos e os parâmetros), 100100 (o prazo do fornecedor, _agenda_rascunho_frase e agenda_rascunho_gravar) e
-- 100200 (a sincronização com a chegada pela nota).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (13 funções novas; 6 recriadas, uma com assinatura nova; 1 lista fechada ampliada; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f4p3/montar-migration.mjs: as partes escritas à mão
-- e os corpos copiados da migration MAIS NOVA de cada função recriada, com cada troca "-- FASE 4:" conferida (uma vez só).
--
-- POR QUE: o dono não preenche OC. A NF-e do fornecedor chega por e-mail (16 notas em 60 dias, 0 lidas pela agenda) e o Pix
-- ao fornecedor está no extrato (86 em 60 dias, 0 ligados a OS). A data sai sozinha no nível da NOTA (despacho + o prazo do
-- fornecedor); a ligação item da nota ↔ linha da OS é SEMPRE do dono (memória "nome diferente nunca; vínculo sempre
-- pergunta"): sem resposta, nenhuma OS muda. O Pix só é LIDO para virar pergunta.
--
-- O QUE MUDA:
--   1. material_remessas_do_email (nova; só service_role; o email-imap chama depois de gravar dados_extraidos): cada NF-e
--      destinada à HBR, emitida há até remessa_dias, vira uma remessa — o fornecedor pelo CNPJ do emitente, o prazo dele
--      (sem cadastro: o do lugar do XML), o despacho (dhSaiEnt vence dhEmi), a previsão (modFrete 9 = o próprio despacho) e
--      até 40 itens. A já importada pela tela nasce chegou e, se a tela ligou a OS, ligada (é a resposta do dono).
--   2. _agenda_material_notas (o passo "notas" do material; o P5 o chama): a chegada pela nota importada (a remessa vira
--      chegou; as linhas que o dono ligou a ela ficam na mão pela sincronização, só em ligado, com a ação material de origem
--      nota e o *desfaz* — o "antes" é tirado antes de sincronizar; em sombra a ação fica executada = false e a linha
--      igual), a pergunta nfe_vincular ("Chegou por e-mail a nota 51038 da Kamell, despachada seg 26/10: deve chegar por
--      volta de sex 30/10. É material de qual serviço? 1) Nelson: …; 2) …; 3) nenhum (estoque ou escritório).") e a
--      limpeza.
--   3. _agenda_material_pix (o passo "pix"): a pergunta pix_material ("O Pix de R$ 480,00 à Premel (seg 26/10) é material
--      do Vanderlei? Já está na mão?") no máximo pix_perguntas_semana_max por semana ISO NO TOTAL e só sobre OS que começa
--      nas próximas material_inicio_dias; o CMP com destino a OS pergunta só se o material já está na mão.
--   4. agenda_rascunho_material: drop da assinatura de 11 argumentos (20261024160600) e create com p_aviso no fim (a nota,
--      o Pix ou a mensagem como o dono disse; _agenda_resolver_aviso acha a pergunta). Com o aviso: a nota já importada =
--      na mão desde a importação; a caminho sem data dita = a previsão da nota (fonte nfe); o Pix = o dia da compra
--      (comprado_fonte pix); a data dita vence (fonte dono); "tudo" com a nota = só as linhas em falta/comprado do fornecedor
--      da nota ou sem fornecedor. A situação nao_e_de_servico (sem OS e sem itens) vira uma linha de rascunho tipo aviso.
--      Grants refeitos.
--   5. _agenda_aplicar_material (o *grava* da linha): a fonte do aviso, a nota na linha (remessa_id), de onde veio a compra
--      (comprado_fonte), a evidência (vinculo_por dono), a nota ligada à OS e a pergunta respondida. _agenda_aplicar_aviso
--      (nova): o *grava* do "não é de serviço" (a nota fica sem_servico; a pergunta respondida).
--   6. _agenda_rascunho_frase: as frases do aviso ("a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10",
--      "na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10)") e o tipo aviso. agenda_rascunho_gravar: o tipo aviso.
--   7. agenda_carona: sem pergunta das Fases 2–3 da OS, a do material dela (nfe_vincular, pix_material, previsao_fornecedor).
--      _agenda_mudancas: a ação material de origem nota (e fornecedor, do P4) entra no "o que mudou" e no fechamento, como as
--      do motor e da vigia.
--   8. agenda_rascunho.tipo + aviso (lista fechada).
--
-- DINHEIRO — NADA AQUI CRIA, MUDA OU LIGA PAGAMENTO: o Pix e o comprovante são só lidos (bank_transactions,
-- finance_review_queue, payables, comprovantes: nenhum update, nenhum insert). A resposta do dono grava só comprado/na mão
-- em os_material. A nota não é importada (process-nfe-xml continua pela tela: NOVO-agenda-31) nem vira conta a pagar.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase4_notas_pix.sql):
--   · p_nota_sem_os (a spec listava dois argumentos novos) não entra: a situação nao_e_de_servico já diz "esta nota não é
--     de serviço", e um segundo argumento seria outra porta para o mesmo fato.
--   · "Não é de serviço" é uma linha de rascunho do tipo NOVO aviso (lista fechada ampliada), não de material: ela não tem OS
--     nem linha, e o *grava* sincronizaria uma OS nula; a releitura sairia com espaço duplo.
--   · As opções da pergunta da nota: a OS sem nada em comum com a nota (fornecedor, palavra) e sem início nas próximas
--     material_inicio_dias fica de fora — com 3 vagas, a 3ª seria um serviço qualquer da carteira (ORÇ-00083, ORÇ-00095,
--     OS-00076 na fixture). O dono sempre pode dizer outra ("Me diga o número ou o nome"). perda_em = o início MAIS CEDO das
--     opções (a 1ª pode não ter início: o Nelson não cabe no plano).
--   · A OS do Pix precisa de um motivo: item em falta do mesmo fornecedor, ou (Pix a fornecedor local) item sem fornecedor
--     ou de balcão/entrega local. A spec ordenava; sem o filtro, o Pix à Premel perguntaria pela OS do Cerbo da Kamell.
--   · O aviso também acha a nota sem resposta cuja pergunta venceu (7 dias): sem isso, a nota respondida depois da validade
--     ficaria sem ter como ser ligada.
--   · A chegada pela nota grava a remessa como chegou também em sombra (é o registro do fato: a tela importou); só a linha
--     da OS espera o modo ligado.
--   · _agenda_mudancas e agenda_carona também são recriadas (a spec deixava a carona para o P5): sem isso a ação da nota não
--     apareceria no fechamento e a pergunta não iria de carona.
--
-- O QUE NÃO MUDA: process-nfe-xml e a tela "Notas recebidas por e-mail" (a importação continua manual); confirm_nfe_import;
-- o financeiro inteiro; os textos das Fases 1–3; as chamadas de material_informar sem o aviso (a mesma releitura). Nenhum
-- cron: os passos notas e pix rodam pelo agenda_material_vigiar (P5).
--
-- ORDEM DE LIGAR: depois de 20261027100000..100200; ANTES do deploy de email-imap (que chama material_remessas_do_email —
-- sem ela, o leitor segue como hoje: a função ausente é silêncio), ai-agent e erp-mcp (material_informar manda p_aviso só
-- quando o dono fala de uma pergunta). Com modo_material desligado (a linha nasce assim), nada é gravado.
--
-- PROVA: supabase/tests/agenda_fase4_notas_pix.sql (N1–N9). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261027100000..100200):
--   npx supabase db query --linked -f supabase/migrations/20261027100300_agenda_fase4_notas_pix.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027100300', 'agenda_fase4_notas_pix');"
--
-- IDEMPOTENTE: create or replace function, drop function if exists (a assinatura antiga), CHECK por nome (drop if exists +
-- add), revoke/grant e comment.

-- ── 0. A lista fechada do rascunho: o tipo aviso ("não é de serviço") ───────────────────────────────────
-- "Essa nota da Correa não é de serviço" não é material de uma OS (não tem linha nem OS): é a resposta a uma pergunta da
-- agenda. Fica numa linha de rascunho própria, com a frase pronta, e o *grava* a aplica por _agenda_aplicar_aviso.
alter table public.agenda_rascunho drop constraint if exists agenda_rascunho_tipo_check;
alter table public.agenda_rascunho add constraint agenda_rascunho_tipo_check
  check (tipo in ('planejar', 'material', 'disponibilidade', 'marcar', 'aplicar', 'desfazer', 'andamento', 'fornecedor',
                  'aviso'));

-- ── 1. Auxiliares ───────────────────────────────────────────────────────────────────────────────────────

-- O modo das perguntas e do registro do material: ligado só com modo_material ligado; sombra; desligado = null (nada).
create or replace function public._agenda_material_modo()
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case c.modo_material when 'ligado' then 'ligado' when 'sombra' then 'sombra' end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_material_modo() is
  'Agenda de Produção (Fase 4, P3): o modo do que a agenda grava sobre o material (a remessa, as perguntas de nota e Pix, a chegada pela nota) — ligado (modo_material ligado), sombra, ou null (desligado: nada é gravado).';

-- O nome curto do fornecedor ("PREMEL MAT. ELETRICOS LTDA" → "Premel"), como as releituras do P1.
create or replace function public._agenda_fornecedor_curto(p_fornecedor uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select public._agenda_nome_curto(coalesce(nullif(btrim(s.display_name), ''), nullif(btrim(s.trade_name), ''), s.name))
    from public.suppliers s
   where s.id = p_fornecedor;
$function$;

comment on function public._agenda_fornecedor_curto(uuid) is
  'Agenda de Produção (Fase 4, P3): o nome curto do fornecedor (nome de exibição, fantasia ou razão social; _agenda_nome_curto): "Premel", "Kamell", "Mateus".';

-- Quem emitiu a nota, para o dono ler: o fornecedor do cadastro ("Kamell") ou o emitente com a UF e "sem cadastro".
create or replace function public._agenda_remessa_quem(p_fornecedor uuid, p_emitente text, p_uf text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(public._agenda_fornecedor_curto(p_fornecedor),
                  coalesce(public._agenda_nome_curto(p_emitente), 'emitente sem nome')
                  || ' (' || coalesce(nullif(btrim(p_uf), '') || ', ', '') || 'sem cadastro)');
$function$;

comment on function public._agenda_remessa_quem(uuid, text, text) is
  'Agenda de Produção (Fase 4, P3): o emitente da nota para o dono ler — o nome curto do fornecedor do cadastro, ou o do emitente com a UF e "sem cadastro" ("Open (SP, sem cadastro)").';

-- "a nota 51038 da Kamell" (sem número: "a nota da Kamell").
create or replace function public._agenda_remessa_nota(p_remessa uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select 'nota' || coalesce(' ' || nullif(btrim(r.numero), ''), '') || ' da '
         || public._agenda_remessa_quem(r.fornecedor_id, r.emitente, r.emitente_uf)
    from public.material_remessas r
   where r.id = p_remessa;
$function$;

comment on function public._agenda_remessa_nota(uuid) is
  'Agenda de Produção (Fase 4, P3): "nota 51038 da Kamell" (sem número: "nota da Kamell"; sem cadastro: "nota 812 da Open (SP, sem cadastro)").';

-- O Pix do extrato ou o comprovante: {tipo tx|cmp, id, valor, dia, fornecedor_id, categoria, codigo, destino_os_id, curto,
-- texto}. O fornecedor do Pix é o que a fila financeira sugeriu (a aprovada primeiro; a recusada não vale) ou o da conta a
-- pagar criada por ela — nunca pelo nome (memória do dono: nome diferente nunca identifica).
create or replace function public._agenda_pix_fonte(p_tipo text, p_id uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v jsonb;
  v_forn text;
begin
  if p_tipo = 'tx' then
    select jsonb_build_object('tipo', 'tx', 'id', bt.id, 'valor', abs(bt.amount), 'dia', bt.transaction_date,
             'fornecedor_id', coalesce(q.suggested_supplier_id, pa.supplier_id),
             'categoria', coalesce(q.suggested_category, pa.expense_category))
      into v
      from public.bank_transactions bt
      left join lateral (
        select f.* from public.finance_review_queue f
         where f.bank_transaction_id = bt.id and f.status in ('approved', 'pending')
         order by (f.status = 'approved') desc, f.created_at desc, f.id
         limit 1) q on true
      left join public.payables pa on pa.id = q.created_payable_id
     where bt.id = p_id;
  elsif p_tipo = 'cmp' then
    select jsonb_build_object('tipo', 'cmp', 'id', c.id, 'valor', c.valor, 'dia', c.data_compra, 'fornecedor_id', c.supplier_id,
             'codigo', c.codigo, 'destino_os_id', case when c.destino = 'os' then c.destino_os_id end)
      into v
      from public.comprovantes c
     where c.id = p_id;
  end if;
  if v is null then
    return null;
  end if;
  v_forn := coalesce(public._agenda_fornecedor_curto((v ->> 'fornecedor_id')::uuid), 'fornecedor sem cadastro');
  return v || case when p_tipo = 'tx' then jsonb_build_object(
      'curto', format('Pix de %s à %s, %s', public._brl((v ->> 'valor')::numeric), v_forn, public._dia_curto((v ->> 'dia')::date)),
      'texto', format('o Pix de %s à %s (%s)', public._brl((v ->> 'valor')::numeric), v_forn, public._dia_curto((v ->> 'dia')::date)))
    else jsonb_build_object(
      'curto', format('comprovante %s, %s à %s, %s', coalesce(v ->> 'codigo', 'sem número'), public._brl((v ->> 'valor')::numeric),
                      v_forn, public._dia_curto((v ->> 'dia')::date)),
      'texto', format('o comprovante %s (%s à %s, %s)', coalesce(v ->> 'codigo', 'sem número'), public._brl((v ->> 'valor')::numeric),
                      v_forn, public._dia_curto((v ->> 'dia')::date))) end;
end;
$function$;

comment on function public._agenda_pix_fonte(text, uuid) is
  'Agenda de Produção (Fase 4, P3): o Pix do extrato (tipo tx: bank_transactions, com o fornecedor e a categoria da fila financeira — a sugestão aprovada, senão a pendente; a recusada não vale — ou da conta a pagar que ela criou) ou o comprovante (tipo cmp: comprovantes, com o destino OS quando o dono disse). {tipo, id, valor, dia, fornecedor_id, categoria, codigo, destino_os_id, curto, texto}. Só lê: nada aqui cria, muda ou liga pagamento.';

-- ── 2. A NF-e do e-mail vira remessa no nível da NOTA ───────────────────────────────────────────────────

create or replace function public.material_remessas_do_email(p_email_message_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c          public.agenda_config := public._agenda_cfg();
  v_m        public.email_messages%rowtype;
  n          jsonb;
  v_chave    text;
  v_emit     date;
  v_saida    date;
  v_desp     date;
  v_cnpj     text;
  v_forn     uuid;
  v_ids      uuid[];
  v_pf       jsonb;
  v_classe   text;
  v_du       int;
  v_corr     int;
  v_prev     date;
  v_fn       record;
  v_os       uuid[];
  v_itens    jsonb;
  v_id       uuid;
  v_criadas  int := 0;
  v_ja       int := 0;
  v_ign      int := 0;
  v_sem      int := 0;
begin
  if c.modo_material = 'desligado' then
    return jsonb_build_object('pulado', true);
  end if;
  select * into v_m from public.email_messages where id = p_email_message_id;
  if not found then
    raise exception 'material_remessas_do_email: o e-mail % não existe', p_email_message_id using errcode = 'P0002';
  end if;

  for n in select e from jsonb_array_elements(case when jsonb_typeof(v_m.dados_extraidos -> 'nfes') = 'array'
                                                    then v_m.dados_extraidos -> 'nfes' else '[]'::jsonb end) e loop
    v_chave := n ->> 'chave';
    if not coalesce((n ->> 'para_empresa')::boolean, false) or coalesce(v_chave, '') !~ '^[0-9]{44}$' then
      v_ign := v_ign + 1;
      continue;
    end if;
    v_emit := coalesce(case when n ->> 'data' ~ '^\d{4}-\d{2}-\d{2}$' then (n ->> 'data')::date end,
                       (v_m.received_at at time zone 'America/Sao_Paulo')::date);
    if v_emit < p_hoje - c.remessa_dias then
      v_ign := v_ign + 1;
      continue;
    end if;
    if not (n ? 'itens') then
      v_sem := v_sem + 1;   -- extração de antes de 25/10: a remessa nasce sem itens nem saída (?remessas=1 relê antes)
    end if;
    if exists (select 1 from public.material_remessas r where r.nfe_chave = v_chave) then
      v_ja := v_ja + 1;
      continue;
    end if;

    -- O fornecedor pelo CNPJ do emitente (documento identifica): o cadastro ATIVO com os mesmos dígitos; mais de um = o
    -- principal (mais produtos + contas a pagar; empate = nenhum, e o prazo sai do lugar do XML).
    v_cnpj := upper(regexp_replace(coalesce(n ->> 'emitente_cnpj', ''), '[^0-9A-Za-z]', '', 'g'));
    v_forn := null;
    if v_cnpj <> '' then
      v_ids := array(select s.id from public.suppliers s
                      where coalesce(s.active, true)
                        and upper(regexp_replace(coalesce(s.cnpj_cpf, ''), '[^0-9A-Za-z]', '', 'g')) = v_cnpj
                      order by (select count(*) from public.products p where p.supplier_id = s.id)
                               + (select count(*) from public.payables pa where pa.supplier_id = s.id) desc, s.id);
      if cardinality(v_ids) = 1 then
        v_forn := v_ids[1];
      elsif cardinality(v_ids) > 1
            and (select count(*) from public.products p where p.supplier_id = v_ids[1])
                + (select count(*) from public.payables pa where pa.supplier_id = v_ids[1])
                > (select count(*) from public.products p where p.supplier_id = v_ids[2])
                + (select count(*) from public.payables pa where pa.supplier_id = v_ids[2]) then
        v_forn := v_ids[1];
      end if;
    end if;

    -- O prazo: o do fornecedor (o que o dono disse, o cadastro, o nome, a cidade); sem ele, o do lugar do XML.
    v_pf := public._agenda_prazo_do_fornecedor(v_forn);
    v_classe := v_pf ->> 'classe';
    v_du := (v_pf ->> 'du')::int;
    v_corr := (v_pf ->> 'corridos')::int;
    if v_classe is null then
      v_classe := public._agenda_classe_por_lugar(n ->> 'municipio', n ->> 'uf');
      v_du := (c.prazo_classe_du ->> v_classe)::int;
      v_corr := null;
    end if;
    v_saida := case when n ->> 'saida' ~ '^\d{4}-\d{2}-\d{2}$' then (n ->> 'saida')::date end;
    v_desp := coalesce(v_saida, v_emit);
    if n ->> 'mod_frete' = '9' then
      -- Sem transporte (d16): é retirada no balcão — o dia do despacho.
      v_prev := v_desp;
      v_du := 0;
    else
      v_prev := public._agenda_chegada_pela_classe(v_classe, v_du, v_corr, v_desp);
    end if;

    -- Já importada e confirmada pela tela: nasce chegou; ligada às OS que a importação disse (é a resposta do dono).
    select fn.id, fn.confirmed_at into v_fn
      from public.fiscal_notes fn where fn.nfe_key = v_chave and fn.status = 'confirmed'
     limit 1;
    v_os := '{}';
    if v_fn.id is not null then
      v_os := array(select distinct i.service_order_id from public.fiscal_note_items i
                     where i.fiscal_note_id = v_fn.id and i.service_order_id is not null order by 1);
    end if;

    v_itens := coalesce((select jsonb_agg(jsonb_build_object(
                          'n', coalesce((x.e ->> 'n')::int, x.o::int), 'descricao', left(btrim(x.e ->> 'descricao'), 120),
                          'qtd', case when x.e ->> 'qtd' ~ '^[0-9]+(\.[0-9]+)?$' then (x.e ->> 'qtd')::numeric end,
                          'un', left(nullif(btrim(x.e ->> 'un'), ''), 10)) order by x.o)
                           from jsonb_array_elements(case when jsonb_typeof(n -> 'itens') = 'array' then n -> 'itens' else '[]'::jsonb end)
                                with ordinality x(e, o)
                          where x.o <= 40 and nullif(btrim(x.e ->> 'descricao'), '') is not null), '[]'::jsonb);

    insert into public.material_remessas (
      nfe_chave, email_message_id, email_attachment_id, fornecedor_id, emitente, emitente_cnpj, emitente_uf,
      emitente_municipio, numero, valor, emitida_em, saida_em, mod_frete, classe, prazo_du, previsao_ate, itens,
      estado, vinculo, os_ids, respondida_em, fiscal_note_id, chegou_em, historico)
    values (
      v_chave, v_m.id,
      (select a.id from public.email_attachments a where a.id = case when n ->> 'anexo_id' ~ '^[0-9a-f-]{36}$'
                                                                     then (n ->> 'anexo_id')::uuid end),
      v_forn, left(nullif(btrim(n ->> 'emitente'), ''), 120),
      case when v_cnpj ~ '^[0-9A-Z]{12}[0-9]{2}$|^[0-9]{11}$' then v_cnpj end,
      case when upper(btrim(coalesce(n ->> 'uf', ''))) ~ '^[A-Z]{2}$' then upper(btrim(n ->> 'uf')) end,
      left(nullif(btrim(n ->> 'municipio'), ''), 80), left(nullif(btrim(n ->> 'numero'), ''), 20),
      case when n ->> 'valor' ~ '^-?[0-9]+(\.[0-9]+)?$' then round((n ->> 'valor')::numeric, 2) end,
      v_emit, v_saida, case when n ->> 'mod_frete' ~ '^[0-9]$' then n ->> 'mod_frete' end,
      v_classe, v_du, v_prev, v_itens,
      case when v_fn.id is not null then 'chegou' else 'a_caminho' end,
      case when cardinality(v_os) > 0 then 'ligada' else 'sem_resposta' end,
      v_os,
      case when cardinality(v_os) > 0 then coalesce(v_fn.confirmed_at, now()) end,
      v_fn.id,
      case when v_fn.id is not null then least(coalesce((v_fn.confirmed_at at time zone 'America/Sao_Paulo')::date, p_hoje), p_hoje) end,
      jsonb_build_array(jsonb_build_object('em', p_hoje, 'por', 'sistema',
        'nota', case when v_fn.id is not null then 'chegou por e-mail; já entrou no estoque' else 'chegou por e-mail' end)))
    on conflict (nfe_chave) do nothing
    returning id into v_id;
    if v_id is null then
      v_ja := v_ja + 1;
    else
      v_criadas := v_criadas + 1;
    end if;
  end loop;

  return jsonb_build_object('criadas', v_criadas, 'ja_existiam', v_ja, 'ignoradas', v_ign, 'sem_itens', v_sem);
end;
$function$;

comment on function public.material_remessas_do_email(uuid, date) is
  'Agenda de Produção (Fase 4, P3): as NF-e de um e-mail (email_messages.dados_extraidos.nfes, do leitor do email-imap) viram remessas no nível da NOTA — só as destinadas à HBR, emitidas há até remessa_dias; uma por chave (on conflict do nothing). O fornecedor pelo CNPJ do emitente (ativo; mais de um = o principal por produtos + contas); a classe e o prazo do fornecedor (_agenda_prazo_do_fornecedor), sem ele o do lugar do XML; o despacho = a saída (dhSaiEnt), senão a emissão; a previsão = despacho + prazo (modFrete 9 = o próprio despacho; prazo desconhecido = null). A já importada (fiscal_notes confirmada) nasce chegou e, com fiscal_note_items.service_order_id, ligada a essas OS (a resposta do dono na tela). NENHUMA OS muda aqui. Com modo_material desligado: {pulado}. Devolve {criadas, ja_existiam, ignoradas, sem_itens}. Só service_role.';

-- ── 3. As OS candidatas ─────────────────────────────────────────────────────────────────────────────────

-- O início previsto: o 1º entre o próximo dia do plano (inclusive reserva) e a janela antiga de hoje em diante.
create or replace function public._agenda_inicio_previsto(p_os uuid, p_hoje date)
 returns date
 language sql
 stable
 set search_path to 'public'
as $function$
  select least((x.pl ->> 'proximo_dia')::date,
               (select min((r ->> 'dia')::date) from jsonb_array_elements(coalesce(x.pl -> 'reservas', '[]'::jsonb)) r
                 where (r ->> 'dia')::date >= p_hoje),
               (select k.agendada_de from public.os_carteira(p_hoje) k
                 where k.service_order_id = p_os and k.agendada_de >= p_hoje))
    from (select public._agenda_plano_da_os(p_os, p_hoje) as pl) x;
$function$;

comment on function public._agenda_inicio_previsto(uuid, date) is
  'Agenda de Produção (Fase 4, P3): quando a OS começa — o 1º entre o próximo dia vigente do plano (_agenda_plano_da_os.proximo_dia), a 1ª reserva de hoje em diante e a janela antiga (os_carteira.agendada_de) de hoje em diante; null = sem início previsto.';

-- As OS da carteira com material CRÍTICO em falta ou comprado (os itens da prontidão), com o rótulo, o início previsto e o
-- fornecedor de cada item (o da linha de material; sem linha, o do produto da peça).
create or replace function public._agenda_material_em_falta(p_hoje date)
 returns table (service_order_id uuid, numero text, cliente_curto text, rotulo text, inicio date, itens jsonb)
 language sql
 stable
 set search_path to 'public'
as $function$
  with k as (
    select c.service_order_id, c.numero, c.cliente_curto,
           count(*) over (partition by c.cliente_curto) as n_nome
      from public.os_carteira(p_hoje) c
  ),
  x as (
    select k.*, coalesce((
             select jsonb_agg(jsonb_build_object(
                      'id', e ->> 'id', 'linha', e ->> 'linha', 'origem', e ->> 'origem', 'descricao', e ->> 'descricao',
                      'curto', e ->> 'curto', 'situacao', e ->> 'situacao', 'classe', e ->> 'classe',
                      'fornecedor_id', coalesce(
                        (select m.fornecedor_id from public.os_material m where m.id::text = e ->> 'id'),
                        (select p.supplier_id from public.service_order_parts sp join public.products p on p.id = sp.product_id
                          where e ->> 'origem' = 'peca' and sp.id::text = e ->> 'linha')))
                    order by t.o)
               from jsonb_array_elements(coalesce(public.os_prontidao(k.service_order_id, p_hoje) #> '{material,itens}', '[]'::jsonb))
                    with ordinality t(e, o)
              where coalesce((e ->> 'critico')::boolean, false) and e ->> 'situacao' in ('falta', 'comprado')), '[]'::jsonb) as itens
      from k
  )
  select x.service_order_id, x.numero, x.cliente_curto,
         public._agenda_rotulo(jsonb_build_object('curto', x.cliente_curto, 'numero', x.numero, 'n_nome', x.n_nome)),
         public._agenda_inicio_previsto(x.service_order_id, p_hoje), x.itens
    from x
   where jsonb_array_length(x.itens) > 0
   order by x.numero collate "C", x.service_order_id;
$function$;

comment on function public._agenda_material_em_falta(date) is
  'Agenda de Produção (Fase 4, P3): as OS da carteira com item CRÍTICO em falta ou comprado (os_prontidao.material.itens) — {service_order_id, numero, cliente_curto, rotulo ("Nelson"; com o número quando o nome repete na carteira), inicio (_agenda_inicio_previsto), itens [{id, linha, origem, descricao, curto, situacao, classe, fornecedor_id}]}. As candidatas das perguntas de nota e de Pix.';

-- ── 4. A pergunta do material (o molde de _agenda_vigia_perguntar, com as opções e a validade) ───────────

create or replace function public._agenda_material_perguntar(p_tipo text, p_chave text, p_os uuid, p_os_ids uuid[],
                                                             p_os_material uuid, p_perda date, p_texto text, p_opcoes jsonb,
                                                             p_agora timestamptz, p_uma_vez boolean default true)
 returns boolean
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_modo text := public._agenda_material_modo();
  v_id   uuid;
begin
  if v_modo is null then
    return false;
  end if;
  if exists (select 1 from public.agenda_perguntas q
              where q.chave = left(p_chave, 200) and q.modo = v_modo and (p_uma_vez or q.estado = 'aberta')) then
    return false;
  end if;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, os_material_id, perda_em, texto, opcoes, modo,
                                       criada_em, expira_em)
  values (p_tipo, left(p_chave, 200), p_os,
          coalesce(p_os_ids, case when p_os is null then '{}'::uuid[] else array[p_os] end),
          case when p_os_material is not null and exists (select 1 from public.os_material m where m.id = p_os_material)
               then p_os_material end,
          p_perda, left(public._agenda_corta(p_texto, 600), 600), coalesce(p_opcoes, '[]'::jsonb), v_modo, p_agora,
          p_agora + c.material_pergunta_validade)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  return v_id is not null;
end;
$function$;

comment on function public._agenda_material_perguntar(text, text, uuid, uuid[], uuid, date, text, jsonb, timestamptz, boolean) is
  'Agenda de Produção (Fase 4, P3): grava uma pergunta de material (nfe_vincular, pix_material; P4: previsao_fornecedor) — o molde de _agenda_vigia_perguntar com as opções e expira_em = agora + material_pergunta_validade (a vigia vence). Modo: ligado só com modo_material ligado, senão sombra; desligado = não grava. p_uma_vez = a chave nunca volta, em estado nenhum. true = gravou. Nunca crítica (fatos que só o dono sabe).';

-- ── 5. O passo das notas: a chegada pela nota importada, a pergunta "de qual serviço?" e a limpeza ────────

create or replace function public._agenda_material_notas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c          public.agenda_config := public._agenda_cfg();
  v_modo     text := public._agenda_material_modo();
  r          public.material_remessas%rowtype;
  v_fn       record;
  v_os       uuid;
  v_osi      uuid[];
  v_antes    jsonb;
  v_depois   jsonb;
  v_nomes    text[];
  v_txt      text;
  v_num      text;
  v_quem     text;
  v_falta    jsonb;
  v_cand     jsonb;
  v_opc      jsonb;
  v_lista    text[];
  v_perda    date;
  v_cheg     int := 0;
  v_acoes    int := 0;
  v_perg     int := 0;
  v_res      int := 0;
  v_k        int;
begin
  if v_modo is null then
    return jsonb_build_object('pulado', true);
  end if;

  -- (1) A chegada: a nota a caminho que a tela importou e confirmou. A remessa vira chegou (com a OS da importação, se o
  -- dono ligou lá); as linhas que o dono ligou a ela ficam na mão pela sincronização (em ligado), com uma ação material
  -- por OS e o *desfaz*. O "antes" é tirado ANTES de sincronizar. Em sombra: a ação fica executada = false e a linha não
  -- muda.
  for r in select x.* from public.material_remessas x
            where x.estado = 'a_caminho'
              and exists (select 1 from public.fiscal_notes fn where fn.nfe_key = x.nfe_chave and fn.status = 'confirmed')
            order by x.criada_em, x.id
            for update loop
    select fn.id, fn.confirmed_at into v_fn
      from public.fiscal_notes fn where fn.nfe_key = r.nfe_chave and fn.status = 'confirmed' limit 1;
    v_osi := array(select distinct i.service_order_id from public.fiscal_note_items i
                    where i.fiscal_note_id = v_fn.id and i.service_order_id is not null order by 1);
    update public.material_remessas x
       set estado = 'chegou', fiscal_note_id = v_fn.id,
           chegou_em = least(coalesce((v_fn.confirmed_at at time zone 'America/Sao_Paulo')::date, p_hoje), p_hoje),
           vinculo = case when x.vinculo = 'sem_resposta' and cardinality(v_osi) > 0 then 'ligada' else x.vinculo end,
           os_ids = case when x.vinculo = 'sem_resposta' and cardinality(v_osi) > 0 then v_osi else x.os_ids end,
           respondida_em = case when x.vinculo = 'sem_resposta' and cardinality(v_osi) > 0
                                then coalesce(v_fn.confirmed_at, p_agora) else x.respondida_em end,
           historico = public._os_material_historico(x.historico, jsonb_build_object('em', p_hoje, 'por', 'sistema',
                         'nota', 'entrou no estoque pela tela'))
     where x.id = r.id
    returning x.* into r;
    v_cheg := v_cheg + 1;
    v_num := coalesce(nullif(btrim(r.numero), ''), '');
    v_quem := public._agenda_remessa_quem(r.fornecedor_id, r.emitente, r.emitente_uf);

    for v_os in select distinct m.service_order_id from public.os_material m
                 where m.remessa_id = r.id and m.situacao not in ('na_mao', 'dispensado') order by 1 loop
      select coalesce(jsonb_agg(to_jsonb(m) - 'historico' order by m.id), '[]'::jsonb),
             array_agg(public._agenda_linha_curta(m.descricao) order by m.id)
        into v_antes, v_nomes
        from public.os_material m
       where m.service_order_id = v_os and m.remessa_id = r.id and m.situacao not in ('na_mao', 'dispensado');
      if v_modo = 'ligado' then
        perform public.os_material_sincronizar(v_os, p_hoje);
        select coalesce(jsonb_agg(to_jsonb(m) - 'historico' order by m.id), '[]'::jsonb) into v_depois
          from public.os_material m
         where m.id in (select (e ->> 'id')::uuid from jsonb_array_elements(v_antes) e);
        v_txt := format('%s: a %s entrou no estoque — %s %s na mão. *desfaz %s* volta como estava.',
                        public._agenda_rotulo_da_os(v_os), public._agenda_remessa_nota(r.id), public._agenda_lista(v_nomes, 3),
                        case when cardinality(v_nomes) = 1 then 'está' else 'estão' end,
                        (select so.service_order_number from public.service_orders so where so.id = v_os));
      else
        -- Em sombra a linha não muda: o "depois" é o que a sincronização faria (na mão pela nota).
        select coalesce(jsonb_agg((e || jsonb_build_object('situacao', 'na_mao', 'fonte', 'nfe',
                                                             'quantidade_na_mao', e -> 'quantidade_necessaria',
                                                             'chegou_em', r.chegou_em, 'compra_prevista_em', null))
                                  order by e ->> 'id'), '[]'::jsonb)
          into v_depois from jsonb_array_elements(v_antes) e;
        v_txt := format('%s: a %s entrou no estoque — em teste, eu marcaria %s como na mão.',
                        public._agenda_rotulo_da_os(v_os), public._agenda_remessa_nota(r.id), public._agenda_lista(v_nomes, 3));
      end if;
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                       desfazivel_ate)
      values (p_agora, p_hoje, v_modo = 'ligado', 'nota', 'material', v_os, array[v_os],
              jsonb_build_object('linhas', v_antes, 'remessa_id', r.id),
              jsonb_build_object('linhas', v_depois, 'remessa_id', r.id),
              public._agenda_corta(v_txt, 400),
              case when v_modo = 'ligado' then p_agora + c.desfazer_validade end);
      v_acoes := v_acoes + 1;
    end loop;
  end loop;

  -- (3, antes da 2) A limpeza: a pergunta de uma nota que já não está sem resposta (o dono respondeu, ou a importação
  -- ligou) se resolve.
  with f as (
    update public.agenda_perguntas q
       set estado = 'resolvida',
           resolvida_motivo = case x.vinculo when 'ligada' then 'a nota foi ligada ao serviço'
                                             when 'sem_servico' then 'você disse que não é de serviço'
                                             else 'a nota saiu' end
      from (select q2.id, r2.vinculo
              from public.agenda_perguntas q2
              left join public.material_remessas r2 on q2.chave = 'nfe:' || r2.id
             where q2.tipo = 'nfe_vincular' and q2.estado = 'aberta'
               and (r2.id is null or r2.vinculo <> 'sem_resposta')) x
     where q.id = x.id
    returning q.id)
  select count(*) into v_res from f;

  -- (2) A pergunta "é material de qual serviço?", uma vez por nota, só com OS candidata. As candidatas: as OS da carteira
  -- com item crítico em falta ou comprado que têm algo com a nota — item do mesmo fornecedor, palavra de 4+ letras em
  -- comum com um item da nota — ou começam nas próximas material_inicio_dias; em ordem: fornecedor, palavra, início mais
  -- cedo. Até nfe_opcoes_max + "nenhum (estoque ou escritório)". Nenhuma = sem pergunta (a nota aparece no foco compras).
  for r in select x.* from public.material_remessas x
            where x.vinculo = 'sem_resposta' and x.estado in ('a_caminho', 'chegou')
              and not exists (select 1 from public.agenda_perguntas q where q.chave = 'nfe:' || x.id and q.modo = v_modo)
            order by x.criada_em, x.id loop
    if v_falta is null then
      v_falta := coalesce((select jsonb_agg(to_jsonb(f) order by f.numero collate "C") from public._agenda_material_em_falta(p_hoje) f),
                          '[]'::jsonb);
    end if;
    with palavras as (
      select distinct w from jsonb_array_elements(r.itens) i,
             unnest(string_to_array(public._agenda_normal(i ->> 'descricao'), ' ')) w
       where length(w) >= 4 and w !~ '^[0-9]+$'
    ),
    os as (
      select o, (o ->> 'service_order_id')::uuid as id, (o ->> 'inicio')::date as inicio,
             exists (select 1 from jsonb_array_elements(o -> 'itens') it
                      where r.fornecedor_id is not null and it ->> 'fornecedor_id' = r.fornecedor_id::text) as s1,
             exists (select 1 from jsonb_array_elements(o -> 'itens') it,
                            unnest(string_to_array(public._agenda_normal(it ->> 'descricao'), ' ')) w
                      where w in (select p.w from palavras p)) as s2
        from jsonb_array_elements(v_falta) o
    ),
    esc as (
      select os.*, row_number() over (order by s1 desc, s2 desc, inicio nulls last, o ->> 'numero' collate "C") as n
        from os
       where s1 or s2 or (inicio is not null and inicio <= p_hoje + c.material_inicio_dias)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'n', e.n, 'os', e.id, 'inicio', e.inicio,
             'texto', (e.o ->> 'rotulo') || ': ' || (
               select coalesce((array_agg(it ->> 'curto' order by t.k))[1], '')
                      || case when count(*) > 1 then ' e mais ' || (count(*) - 1) else '' end
                 from jsonb_array_elements(e.o -> 'itens') with ordinality t(it, k)
                where case when e.s1 then it ->> 'fornecedor_id' = r.fornecedor_id::text
                           when e.s2 then exists (select 1 from unnest(string_to_array(public._agenda_normal(it ->> 'descricao'), ' ')) w
                                                   where w in (select p.w from palavras p))
                           else true end))
             order by e.n), '[]'::jsonb)
      into v_cand
      from esc e
     where e.n <= c.nfe_opcoes_max;
    continue when jsonb_array_length(v_cand) = 0;

    v_k := jsonb_array_length(v_cand) + 1;
    v_opc := v_cand || jsonb_build_array(jsonb_build_object('n', v_k, 'os', null, 'texto', 'nenhum (estoque ou escritório)'));
    v_lista := array(select format('%s) %s', e ->> 'n', e ->> 'texto') from jsonb_array_elements(v_opc) e order by (e ->> 'n')::int);
    v_perda := (select min((e ->> 'inicio')::date) from jsonb_array_elements(v_cand) e);
    v_quem := public._agenda_remessa_quem(r.fornecedor_id, r.emitente, r.emitente_uf);
    v_num := coalesce(' ' || nullif(btrim(r.numero), ''), '');
    v_txt := case
      when r.estado = 'chegou' then
        format('A nota%s da %s entrou no estoque em %s.', v_num, v_quem, public._dia_curto(r.chegou_em))
      when r.mod_frete = '9' then
        format('Chegou por e-mail a nota%s da %s, de %s, sem frete (retirada na loja).', v_num, v_quem, public._dia_curto(r.despacho_em))
      when r.previsao_ate is null then
        format('Chegou por e-mail a nota%s da %s, despachada %s (não sei em quantos dias ela chega).', v_num, v_quem,
               public._dia_curto(r.despacho_em))
      else
        format('Chegou por e-mail a nota%s da %s, despachada %s: deve chegar por volta de %s.', v_num, v_quem,
               public._dia_curto(r.despacho_em), public._dia_curto(r.previsao_ate)) end
      || ' É material de qual serviço? ' || array_to_string(v_lista, '; ') || '. Me diga o número ou o nome.';
    if public._agenda_material_perguntar('nfe_vincular', 'nfe:' || r.id, null,
         array(select (e ->> 'os')::uuid from jsonb_array_elements(v_cand) e order by (e ->> 'n')::int),
         null, v_perda, v_txt, v_opc, p_agora) then
      v_perg := v_perg + 1;
    end if;
  end loop;

  return jsonb_build_object('chegaram', v_cheg, 'acoes', v_acoes, 'perguntas', v_perg, 'resolvidas', v_res, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_material_notas(date, timestamptz) is
  'Agenda de Produção (Fase 4, P3), passo do material "notas": (1) a chegada — a remessa a caminho cuja nota a tela importou (fiscal_notes confirmada) vira chegou (ligada às OS de fiscal_note_items, se a remessa estava sem resposta); as linhas que o dono ligou a ela (remessa_id) ficam na mão pela sincronização (só em ligado), com uma ação material (origem nota) por OS, antes/depois = {linhas: [os_material sem historico], remessa_id}, o antes tirado ANTES de sincronizar, e o *desfaz* por desfazer_validade; em sombra a ação fica executada = false e a linha igual; (2) a limpeza — a pergunta nfe_vincular de nota que não está mais sem resposta se resolve; (3) a pergunta nfe_vincular (chave nfe:<remessa>, uma vez) para a nota sem resposta com OS candidata (item crítico em falta/comprado do mesmo fornecedor, com palavra em comum com a nota, ou início nas próximas material_inicio_dias; nessa ordem, depois o início), até nfe_opcoes_max + "nenhum", perda_em = o início mais cedo das opções. NUNCA liga a nota a OS: só o *grava* do dono (agenda_rascunho_material com o aviso). {chegaram, acoes, perguntas, resolvidas, modo}; desligado = {pulado}.';

-- ── 6. O passo do Pix: "o Pix de R$ X à Premel é material do Vanderlei? Já está na mão?" ─────────────────

create or replace function public._agenda_material_pix(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_modo   text := public._agenda_material_modo();
  v_feitas int;
  v_vagas  int;
  v_res    int := 0;
  v_perg   int := 0;
  v_cands  int := 0;
  x        record;
  v_fonte  jsonb;
  v_txt    text;
begin
  if v_modo is null then
    return jsonb_build_object('pulado', true);
  end if;

  -- A limpeza: a pergunta de Pix cuja OS não tem mais material crítico em falta se resolve.
  with f as (
    update public.agenda_perguntas q set estado = 'resolvida', resolvida_motivo = 'o material da OS não falta mais'
     where q.tipo = 'pix_material' and q.estado = 'aberta' and q.service_order_id is not null
       and not exists (select 1 from jsonb_array_elements(coalesce(public.os_prontidao(q.service_order_id, p_hoje) #> '{material,itens}',
                                                                   '[]'::jsonb)) e
                        where coalesce((e ->> 'critico')::boolean, false) and e ->> 'situacao' = 'falta')
    returning q.id)
  select count(*) into v_res from f;

  -- O teto: pix_perguntas_semana_max por semana ISO, no TOTAL (não por OS), no modo de agora.
  select count(*) into v_feitas from public.agenda_perguntas q
   where q.tipo = 'pix_material' and q.modo = v_modo
     and date_trunc('week', (q.criada_em at time zone 'America/Sao_Paulo')::date) = date_trunc('week', p_hoje);
  v_vagas := c.pix_perguntas_semana_max - v_feitas;
  if v_vagas <= 0 then
    return jsonb_build_object('perguntas', 0, 'resolvidas', v_res, 'teto', true, 'modo', v_modo);
  end if;

  for x in
    with os as (
      -- A OS que começa nas próximas material_inicio_dias, com item crítico em FALTA.
      select f.service_order_id as id, f.cliente_curto, f.rotulo, f.inicio, f.numero,
             (select jsonb_agg(it) from jsonb_array_elements(f.itens) it where it ->> 'situacao' = 'falta') as itens
        from public._agenda_material_em_falta(p_hoje) f
       where f.inicio between p_hoje and p_hoje + c.material_inicio_dias
    ),
    tx as (
      select 'tx'::text as tipo, bt.id
        from public.bank_transactions bt
       where bt.transaction_type = 'debit' and upper(coalesce(bt.payment_method, '')) = 'PIX'
         and bt.transaction_date between p_hoje - c.pix_janela_dias and p_hoje
         and bt.dismissed_at is null and abs(bt.amount) >= c.pix_valor_minimo
    ),
    cmp as (
      select 'cmp'::text as tipo, cm.id
        from public.comprovantes cm
       where cm.supplier_id is not null and cm.valor >= c.pix_valor_minimo
         and cm.data_compra between p_hoje - c.pix_janela_dias and p_hoje
         and cm.situacao not in ('cancelado', 'nao_comprovante', 'falhou')
    ),
    fontes as (
      select s.tipo, s.id, public._agenda_pix_fonte(s.tipo, s.id) as f from (select * from tx union all select * from cmp) s
    ),
    material as (
      -- Pix ou CMP a fornecedor de MATERIAL: a categoria sugerida é de material, ou o fornecedor tem conta de material em
      -- 365 dias, ou tem produto no cadastro. O mesmo dinheiro nas duas fontes (fornecedor, valor e dia ± 1) conta uma vez,
      -- pelo CMP.
      select fo.*, (fo.f ->> 'fornecedor_id')::uuid as forn,
             public._agenda_prazo_do_fornecedor((fo.f ->> 'fornecedor_id')::uuid) ->> 'classe' in ('balcao', 'entrega_local') as local
        from fontes fo
       where fo.f ->> 'fornecedor_id' is not null
         and (fo.tipo = 'cmp' or coalesce(fo.f ->> 'categoria', '') = any (c.pix_categorias)
              or exists (select 1 from public.payables pa where pa.supplier_id = (fo.f ->> 'fornecedor_id')::uuid
                            and pa.expense_category = any (c.pix_categorias) and pa.issue_date >= p_hoje - 365)
              or exists (select 1 from public.products p where p.supplier_id = (fo.f ->> 'fornecedor_id')::uuid))
         and not (fo.tipo = 'tx' and exists (
               select 1 from fontes o
                where o.tipo = 'cmp' and o.f ->> 'fornecedor_id' = fo.f ->> 'fornecedor_id'
                  and (o.f ->> 'valor')::numeric = (fo.f ->> 'valor')::numeric
                  and abs((o.f ->> 'dia')::date - (fo.f ->> 'dia')::date) <= 1))
         and not exists (select 1 from public.agenda_perguntas q
                          where q.chave = 'pix:' || fo.tipo || ':' || fo.id and q.modo = v_modo)
    ),
    pares as (
      -- A OS candidata (uma): o destino que o dono deu ao CMP (se ela começa logo e tem falta); senão a que tem item em
      -- falta do mesmo fornecedor, depois a que tem item sem fornecedor ou de balcão/entrega local com o Pix a um
      -- fornecedor local, depois a que começa mais cedo. Sem nada disso, não há pergunta.
      select m.tipo, m.id, m.f, m.forn, o.id as os, o.rotulo, o.inicio, o.numero,
             m.f ->> 'destino_os_id' is not null as do_dono,
             row_number() over (partition by m.tipo, m.id
                                order by exists (select 1 from jsonb_array_elements(o.itens) it where it ->> 'fornecedor_id' = m.forn::text) desc,
                                         o.inicio, o.numero collate "C") as rk
        from material m
        join os o on (m.f ->> 'destino_os_id' is not null and o.id = (m.f ->> 'destino_os_id')::uuid)
                  or (m.f ->> 'destino_os_id' is null
                      and (exists (select 1 from jsonb_array_elements(o.itens) it where it ->> 'fornecedor_id' = m.forn::text)
                           or (m.local and exists (select 1 from jsonb_array_elements(o.itens) it
                                                    where it ->> 'fornecedor_id' is null or it ->> 'classe' in ('balcao', 'entrega_local')))))
       where not exists (select 1 from public.os_material om
                          where om.service_order_id = o.id and om.fonte = 'pix' and om.fornecedor_id = m.forn
                            and om.atualizado_em >= p_agora - interval '7 days')
    )
    select * from pares where rk = 1
     order by inicio, (f ->> 'dia')::date desc, (f ->> 'valor')::numeric desc, id
  loop
    v_cands := v_cands + 1;
    continue when v_perg >= v_vagas;
    v_txt := case
      when x.do_dono then
        format('O %s (%s à %s) é do %s, você disse. O material já está na mão?', coalesce(x.f ->> 'codigo', 'comprovante'),
               public._brl((x.f ->> 'valor')::numeric), coalesce(public._agenda_fornecedor_curto(x.forn), 'fornecedor'), x.rotulo)
      else public._agenda_maiuscula(x.f ->> 'texto') || format(' é material do %s? Já está na mão?', x.rotulo) end;
    if public._agenda_material_perguntar('pix_material', 'pix:' || x.tipo || ':' || x.id, x.os, array[x.os], null, x.inicio,
                                         v_txt, '[]'::jsonb, p_agora) then
      v_perg := v_perg + 1;
    end if;
  end loop;

  return jsonb_build_object('perguntas', v_perg, 'resolvidas', v_res, 'candidatas', v_cands, 'teto', v_perg >= v_vagas,
                            'modo', v_modo);
end;
$function$;

comment on function public._agenda_material_pix(date, timestamptz) is
  'Agenda de Produção (Fase 4, P3), passo do material "pix": o Pix de saída do extrato (débito PIX, nos últimos pix_janela_dias, não dispensado, de pix_valor_minimo para cima) e o comprovante (CMP com fornecedor, fora de cancelado/nao_comprovante/falhou) a fornecedor de MATERIAL (categoria da fila financeira em pix_categorias, conta de material em 365 dias ou produto do fornecedor; o mesmo dinheiro nas duas fontes conta pelo CMP) viram a pergunta pix_material (chave pix:tx:<id> | pix:cmp:<id>, uma vez) sobre UMA OS — o destino que o dono deu ao CMP, senão a que tem item crítico em falta do mesmo fornecedor, senão (Pix a fornecedor local) a que tem item sem fornecedor ou de balcão/entrega local; só OS com início nas próximas material_inicio_dias; nada se a OS já tem linha pelo Pix desse fornecedor nos últimos 7 dias. Teto: pix_perguntas_semana_max por semana ISO, no TOTAL. Limpeza: a pergunta cuja OS não tem mais falta crítica se resolve. Só LÊ o Pix: nada aqui cria, muda ou liga pagamento; a resposta (agenda_rascunho_material com o aviso + *grava*) grava só comprado/na mão em os_material. {perguntas, resolvidas, candidatas, teto, modo}; desligado = {pulado}.';

-- ── 7. O aviso: a que pergunta (ou nota) o dono se refere ───────────────────────────────────────────────

create or replace function public._agenda_resolver_aviso(p_ref text, p_os uuid, p_modo text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_norm   text := public._agenda_normal(p_ref);
  v_tok    text[];
  v_tipo   text;
  v_num    text;
  v_cands  jsonb;
  v_sel    jsonb;
  v_x      jsonb;
  v_tk     text;
  v_casa   jsonb;
  v_lista  text[];
  v_casou  boolean := false;
  v_estranha text;
  c_vazias constant text[] := array['o', 'a', 'os', 'as', 'do', 'da', 'de', 'dos', 'das', 'e', 'um', 'uma', 'no', 'na', 'que',
                                    'esse', 'essa', 'isso', 'este', 'esta', 'isto', 'aquele', 'aquela', 'aquilo', 'ultima',
                                    'ultimo', 'nota', 'notas', 'nf', 'nfe', 'danfe', 'xml', 'fiscal', 'pix', 'comprovante', 'cmp',
                                    'transferencia', 'pagamento', 'mensagem', 'msg', 'whats', 'whatsapp', 'zap', 'conversa',
                                    'escreveu', 'falou', 'disse', 'mandou', 'enviou', 'veio', 'reais', 'real', 'r', 'pra', 'para',
                                    'com', 'pelo', 'pela', 'aviso', 'fornecedor', 'chegou', 'chegaram', 'chega', 'chegar', 'ontem',
                                    'hoje', 'amanha', 'mesma', 'mesmo', 'ainda', 'agora', 'tambem', 'aqui', 'servico',
                                    'material', 'materiais', 'peca', 'pecas', 'item', 'itens', 'tudo', 'todo', 'toda', 'foi',
                                    'era', 'sobre', 'dele', 'dela', 'nossa', 'minha', 'meu', 'compra', 'comprei', 'paguei', 'pago',
                                    'valor', 'nova', 'novo', 'qual', 'sim', 'nao', 'ja', 'ta', 'estao', 'ficou', 'dia', 'semana',
                                    'passada', 'outra', 'outro', 'coisa', 'era'];
begin
  if p_modo is null then
    return jsonb_build_object('status', 'nao_achei', 'texto', 'Não tenho nota, Pix nem mensagem de fornecedor esperando você agora.');
  end if;
  v_tok := string_to_array(v_norm, ' ');
  v_tipo := case when v_tok && array['pix', 'comprovante', 'cmp', 'transferencia', 'pagamento'] then 'pix'
                 when v_tok && array['mensagem', 'msg', 'whats', 'whatsapp', 'zap', 'conversa', 'escreveu', 'falou'] then 'sinal'
                 when v_tok && array['nota', 'notas', 'nf', 'nfe', 'danfe', 'xml', 'fiscal'] then 'nfe' end;
  -- O número de 3+ dígitos, fora o da OS ("OS-00112" vira "os 00112" na normalização).
  v_num := (regexp_match(regexp_replace(v_norm, '(^|\s)(os|orc)\s+[0-9]+', ' ', 'g'), '(?:^|\s)0*([0-9]{3,})(?:\s|$)'))[1];

  -- As candidatas: as perguntas abertas da Fase 4 no modo do material e as notas sem resposta que já não têm pergunta
  -- aberta (a pergunta venceu, ou o dono falou antes dela) e são recentes (remessa_dias).
  with q as (
    select x.id, x.tipo, x.chave, x.service_order_id, x.os_ids, x.criada_em
      from public.agenda_perguntas x
     where x.estado = 'aberta' and x.modo = p_modo and x.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor')
  ),
  todas as (
    select jsonb_build_object('pergunta_id', q.id, 'tipo', 'nfe', 'remessa_id', r.id, 'fornecedor_id', r.fornecedor_id,
             'numero', r.numero, 'emitente', r.emitente, 'dia', r.emitida_em, 'os_ids', to_jsonb(q.os_ids), 'em', q.criada_em) as e
      from q join public.material_remessas r on q.chave = 'nfe:' || r.id
     where q.tipo = 'nfe_vincular'
    union all
    select jsonb_build_object('pergunta_id', null, 'tipo', 'nfe', 'remessa_id', r.id, 'fornecedor_id', r.fornecedor_id,
             'numero', r.numero, 'emitente', r.emitente, 'dia', r.emitida_em, 'os_ids', '[]'::jsonb, 'em', r.criada_em)
      from public.material_remessas r
     where r.vinculo = 'sem_resposta' and r.estado in ('a_caminho', 'chegou')
       and r.emitida_em >= public._agenda_hoje() - c.remessa_dias
       and not exists (select 1 from q where q.chave = 'nfe:' || r.id)
    union all
    select jsonb_build_object('pergunta_id', q.id, 'tipo', 'pix', 'pix_tipo', split_part(q.chave, ':', 2),
             'pix_id', split_part(q.chave, ':', 3), 'os_ids', to_jsonb(q.os_ids), 'em', q.criada_em)
      from q where q.tipo = 'pix_material' and q.chave ~ '^pix:(tx|cmp):[0-9a-f-]{36}$'
    union all
    select jsonb_build_object('pergunta_id', q.id, 'tipo', 'sinal', 'sinal_id', s.id, 'fornecedor_id', s.fornecedor_id,
             'whatsapp_message_id', s.whatsapp_message_id, 'trecho', s.trecho, 'dia', s.dia, 'data_de', s.data_de,
             'data_ate', s.data_ate, 'os_ids', to_jsonb(q.os_ids), 'em', q.criada_em)
      from q join public.material_sinais s on q.chave = 'sinal:' || s.id
     where q.tipo = 'previsao_fornecedor'
  )
  select coalesce(jsonb_agg(t.e order by t.e ->> 'em', t.e ->> 'remessa_id', t.e ->> 'pix_id', t.e ->> 'sinal_id'), '[]'::jsonb)
    into v_cands from todas t;

  -- O Pix: valor, dia e fornecedor da fonte; o rótulo e o texto de cada uma.
  select coalesce(jsonb_agg(
           case e ->> 'tipo'
             when 'pix' then e || jsonb_build_object(
               'fornecedor_id', f ->> 'fornecedor_id', 'valor', f ->> 'valor', 'dia', f ->> 'dia', 'curto', f ->> 'curto',
               'texto', f ->> 'texto', 'rotulo', public._agenda_maiuscula(f ->> 'texto'),
               'bank_transaction_id', case when e ->> 'pix_tipo' = 'tx' then e ->> 'pix_id' end,
               'comprovante_id', case when e ->> 'pix_tipo' = 'cmp' then e ->> 'pix_id' end)
             when 'nfe' then e || jsonb_build_object(
               'curto', public._agenda_remessa_nota((e ->> 'remessa_id')::uuid),
               'texto', 'a ' || public._agenda_remessa_nota((e ->> 'remessa_id')::uuid),
               'rotulo', public._agenda_maiuscula(public._agenda_remessa_nota((e ->> 'remessa_id')::uuid)))
             else e || jsonb_build_object(
               'curto', format('o %s escreveu: "%s"', coalesce(public._agenda_fornecedor_curto((e ->> 'fornecedor_id')::uuid), 'fornecedor'),
                               public._agenda_corta(e ->> 'trecho', 80)),
               'texto', format('a mensagem do %s (%s)', coalesce(public._agenda_fornecedor_curto((e ->> 'fornecedor_id')::uuid), 'fornecedor'),
                               public._dia_curto((e ->> 'dia')::date)),
               'rotulo', format('A mensagem do %s (%s)', coalesce(public._agenda_fornecedor_curto((e ->> 'fornecedor_id')::uuid), 'fornecedor'),
                                public._dia_curto((e ->> 'dia')::date))) end
           -- as palavras que identificam cada uma: o fornecedor (nome, fantasia, exibição), o emitente e os itens da nota
           || jsonb_build_object('palavras', public._agenda_normal(concat_ws(' ',
                (select concat_ws(' ', s.name, s.trade_name, s.display_name) from public.suppliers s
                  where s.id = coalesce(pf.f ->> 'fornecedor_id', e ->> 'fornecedor_id')::uuid),
                e ->> 'emitente',
                (select string_agg(i ->> 'descricao', ' ') from public.material_remessas r, jsonb_array_elements(r.itens) i
                  where r.id = (e ->> 'remessa_id')::uuid))))
           -- a ordem: a pergunta mais antiga, depois o documento mais antigo (o número desempata)
           order by e ->> 'em', coalesce(pf.f ->> 'dia', e ->> 'dia'), e ->> 'numero', e ->> 'remessa_id', e ->> 'pix_id', e ->> 'sinal_id'),
           '[]'::jsonb)
    into v_cands
    from jsonb_array_elements(v_cands) with ordinality t(e, o)
    left join lateral (select public._agenda_pix_fonte(e ->> 'pix_tipo', (e ->> 'pix_id')::uuid) as f) pf on e ->> 'tipo' = 'pix';
  v_cands := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_cands) with ordinality t(e, o)
                        where e ->> 'tipo' <> 'pix' or e ->> 'fornecedor_id' is not null or e ->> 'valor' is not null), '[]'::jsonb);
  if jsonb_array_length(v_cands) = 0 then
    return jsonb_build_object('status', 'nao_achei', 'texto', 'Não tenho nota, Pix nem mensagem de fornecedor esperando você agora.');
  end if;
  v_sel := v_cands;

  -- 1. O tipo dito ("a nota", "o Pix", "a mensagem").
  if v_tipo is not null then
    v_sel := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_sel) with ordinality t(e, o)
                        where e ->> 'tipo' = v_tipo), '[]'::jsonb);
  end if;
  -- 2. O número: o da nota (3+ dígitos); no Pix, o valor em reais.
  if v_num is not null and jsonb_array_length(v_sel) > 0 then
    v_sel := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_sel) with ordinality t(e, o)
                        where (e ->> 'tipo' = 'nfe' and ltrim(coalesce(e ->> 'numero', ''), '0') = v_num)
                           or (e ->> 'tipo' = 'pix' and floor((e ->> 'valor')::numeric)::text = v_num)), '[]'::jsonb);
  end if;
  -- 3. As palavras ditas: a que casa o fornecedor, o emitente ou um item da nota de alguma candidata filtra; a que é do nome
  -- de um cliente da carteira ("do Nelson") não conta; qualquer outra ("a nota da Bosch"), sem nenhuma que case = não achei
  -- (nunca a nota de outro fornecedor por eliminação).
  foreach v_tk in array coalesce(v_tok, '{}'::text[]) loop
    continue when length(v_tk) < 3 or v_tk = any (c_vazias) or v_tk ~ '^[0-9]+$';
    v_casa := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_sel) with ordinality t(e, o)
                         where exists (select 1 from unnest(string_to_array(e ->> 'palavras', ' ')) w where w like v_tk || '%')),
                       '[]'::jsonb);
    if jsonb_array_length(v_casa) > 0 then
      v_sel := v_casa;
      v_casou := true;
    elsif not exists (select 1 from public.os_carteira(public._agenda_hoje()) k,
                             unnest(string_to_array(public._agenda_normal(k.cliente), ' ')) w
                       where w like v_tk || '%') then
      v_estranha := coalesce(v_estranha, v_tk);
    end if;
  end loop;
  if v_estranha is not null and not v_casou then
    v_sel := '[]'::jsonb;
  end if;
  -- 4. A OS da conversa desempata; 5. a pergunta aberta vence a nota sem pergunta.
  if jsonb_array_length(v_sel) > 1 and p_os is not null then
    v_casa := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_sel) with ordinality t(e, o)
                         where e -> 'os_ids' ? p_os::text), '[]'::jsonb);
    if jsonb_array_length(v_casa) > 0 then v_sel := v_casa; end if;
  end if;
  if jsonb_array_length(v_sel) > 1 then
    v_casa := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_sel) with ordinality t(e, o)
                         where e ->> 'pergunta_id' is not null), '[]'::jsonb);
    if jsonb_array_length(v_casa) = 1 then v_sel := v_casa; end if;
  end if;

  if jsonb_array_length(v_sel) = 1 then
    return (v_sel -> 0) || jsonb_build_object('status', 'ok');
  end if;
  if jsonb_array_length(v_sel) = 0 then
    v_lista := array(select e ->> 'texto' from jsonb_array_elements(v_cands) with ordinality t(e, o) order by o limit 3);
    return jsonb_build_object('status', 'nao_achei',
      'texto', format('Não achei "%s" no que está esperando você: %s.', btrim(coalesce(p_ref, '')), public._agenda_lista(v_lista, 3)),
      'opcoes', to_jsonb(v_lista));
  end if;
  if (select bool_and(e ->> 'tipo' = 'nfe') from jsonb_array_elements(v_sel) e) then
    v_lista := array(select regexp_replace(e ->> 'curto', '^nota ', 'a ') from jsonb_array_elements(v_sel) with ordinality t(e, o) order by o);
    return jsonb_build_object('status', 'ambiguo', 'opcoes', to_jsonb(v_lista),
      'texto', format('Qual nota: %s ou %s?', array_to_string(v_lista[1:cardinality(v_lista) - 1], ', '), v_lista[cardinality(v_lista)]));
  end if;
  v_lista := array(select e ->> 'texto' from jsonb_array_elements(v_sel) with ordinality t(e, o) order by o);
  return jsonb_build_object('status', 'ambiguo', 'opcoes', to_jsonb(v_lista),
    'texto', format('Qual: %s ou %s?', array_to_string(v_lista[1:cardinality(v_lista) - 1], ', '), v_lista[cardinality(v_lista)]));
end;
$function$;

comment on function public._agenda_resolver_aviso(text, uuid, text) is
  'Agenda de Produção (Fase 4, P3): a nota, o Pix ou a mensagem do fornecedor a que o dono se refere ("a nota da Kamell", "a nota 812", "o Pix da Premel", "a mensagem do Mateus", "isso"). Candidatas: as perguntas abertas nfe_vincular, pix_material e previsao_fornecedor no modo do material, e as notas sem resposta e sem pergunta aberta de até remessa_dias (a pergunta venceu). Filtra pelo tipo dito, pelo número (3+ dígitos: a nota; no Pix, o valor), pelas palavras que casam o fornecedor, o emitente ou um item da nota de alguma candidata (a do nome de um cliente da carteira não conta; outra sem nenhuma que case = não achei: nunca a nota de outro fornecedor por eliminação), pela OS da conversa e, no empate, a com pergunta aberta. {status ok, pergunta_id, tipo nfe|pix|sinal, remessa_id | bank_transaction_id | comprovante_id | sinal_id, fornecedor_id, curto, texto, rotulo, …} | {status ambiguo, texto "Qual nota: a 51038 da Kamell ou a 812 da Correa?", opcoes} | {status nao_achei, texto}. Modo nulo (desligado) = nao_achei.';

-- ── 8. O *grava* do "não é de serviço" ──────────────────────────────────────────────────────────────────

create or replace function public._agenda_aplicar_aviso(p_autor uuid, p_dados jsonb, p_trecho text, p_canal text, p_hoje date)
 returns text
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d   jsonb := coalesce(p_dados, '{}'::jsonb);
  v_r public.material_remessas%rowtype;
begin
  if d ->> 'remessa_id' is not null then
    select * into v_r from public.material_remessas where id = (d ->> 'remessa_id')::uuid for update;
    if not found then
      raise exception 'A nota desta linha não está mais no registro.' using errcode = 'P0001';
    end if;
    if v_r.vinculo = 'ligada' then
      raise exception 'A % já está ligada a um serviço; diga de novo de qual é', public._agenda_remessa_nota(v_r.id) using errcode = 'P0001';
    end if;
    update public.material_remessas
       set vinculo = 'sem_servico', respondida_em = coalesce(respondida_em, now()), respondida_por = coalesce(respondida_por, p_autor),
           historico = public._os_material_historico(historico, jsonb_build_object('em', p_hoje, 'por', 'dono',
                         'nota', 'não é material de serviço', 'trecho', public._agenda_corta(p_trecho, 200)))
     where id = v_r.id;
  end if;
  if d ->> 'sinal_id' is not null then
    update public.material_sinais
       set estado = 'descartado', motivo = 'o dono disse que não é material de serviço'
     where id = (d ->> 'sinal_id')::uuid and estado in ('registrado', 'esperando', 'perguntado');
  end if;
  if d ->> 'pergunta_id' is not null then
    update public.agenda_perguntas q
       set estado = 'respondida', respondida_em = now(), respondida_por = p_autor,
           respondida_via = case when p_canal in ('whatsapp', 'painel') then p_canal end,
           resposta = left(nullif(btrim(coalesce(p_trecho, '')), ''), 500),
           opcao_escolhida = (select (e ->> 'n')::smallint from jsonb_array_elements(q.opcoes) e
                               where e ? 'os' and e ->> 'os' is null limit 1)
     where q.id = (d ->> 'pergunta_id')::uuid and q.estado = 'aberta';
  end if;
  return coalesce(d ->> 'rotulo_grupo', 'O aviso') || ': não é material de serviço.';
end;
$function$;

comment on function public._agenda_aplicar_aviso(uuid, jsonb, text, text, date) is
  'Agenda de Produção (Fase 4, P3): o *grava* de "não é de serviço" (linha de rascunho tipo aviso) — a nota fica sem_servico (a já ligada recusa: "diga de novo de qual é"), a mensagem do fornecedor descartada e a pergunta respondida (a opção "nenhum" na da nota). O Pix só tem a pergunta respondida: nada de dinheiro muda. Devolve a frase do "Gravado. Agora:". Só pelo agenda_rascunho_gravar; só service_role.';

-- ── 9. A RPC do material: a assinatura nova (p_aviso) ───────────────────────────────────────────────────
-- A de 11 argumentos sai (PostgREST não fica com duas para escolher); o corpo é o de 20261024160600, com as mudanças
-- marcadas "-- FASE 4:" (só acréscimo).
drop function if exists public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date);


create or replace function public.agenda_rascunho_material(p_autor uuid, p_canal text, p_os text, p_itens text[],
                                                           p_situacao text, p_quando text default null,
                                                           p_fornecedor text default null, p_quantidade numeric default null,
                                                           p_novo boolean default false, p_trecho text default null,
                                                           p_hoje date default public._hoje_brt(),
                                                           p_aviso text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor    uuid := public._autor_da_agenda(p_autor);
  v_acao     text;
  v_ro       jsonb;
  v_os       uuid;
  v_cab      jsonb;
  v_itens    jsonb;
  v_crit     jsonb;
  v_total    int;
  v_dt       jsonb;
  v_forn     jsonb;
  v_sit      jsonb;
  v_sel      jsonb := '[]'::jsonb;
  v_item     text;
  v_tok      text[];
  v_esp      text[];
  v_cands    jsonb;
  v_n        int;
  v_x        jsonb;
  v_opc      text[];
  v_lserv    uuid;
  v_textos   text[] := '{}';
  v_dados    jsonb;
  c_vazias   constant text[] := array['o', 'a', 'os', 'as', 'do', 'da', 'de', 'dos', 'das', 'e', 'um', 'uma', 'uns', 'umas',
                                      'no', 'na', 'nos', 'nas', 'pro', 'pra', 'para', 'que', 'esse', 'essa', 'esses', 'essas',
                                      'aquele', 'aquela', 'meu', 'minha', 'ja', 'chegou', 'chegaram', 'comprei', 'ta', 'tao',
                                      'aqui'];
  c_generico constant text[] := array['peca', 'pecas', 'material', 'materiais', 'item', 'itens', 'coisa', 'coisas',
                                      'produto', 'produtos'];
  c_tudo     constant text[] := array['tudo', 'todos', 'todas', 'todo', 'toda'];
  -- FASE 4: o aviso (a nota, o Pix ou a mensagem do fornecedor que a agenda perguntou) e o que ele traz.
  v_modo_mat text := public._agenda_material_modo();
  v_av       jsonb;
  v_avd      jsonb;
  v_rem      public.material_remessas%rowtype;
  v_tudo     boolean := false;
  -- FASE 4: fim
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_material: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  -- FASE 4: "não é de serviço" (a nota, o Pix ou a mensagem que a agenda perguntou): sem OS e sem itens, uma linha de
  -- rascunho do tipo aviso (chave aviso:<a pergunta ou a nota>); só o *grava* responde (_agenda_aplicar_aviso).
  if lower(btrim(coalesce(p_situacao, ''))) = 'nao_e_de_servico' then
    if nullif(btrim(p_trecho), '') is null then
      return public._agenda_recusa('Me diga com as suas palavras o que aconteceu com o material.', 'sem_trecho');
    end if;
    if nullif(btrim(p_aviso), '') is null then
      return public._agenda_recusa('De qual nota, Pix ou mensagem? Diga como o fornecedor aparece ("a nota da Correa").', 'sem_aviso');
    end if;
    v_av := public._agenda_resolver_aviso(p_aviso, null, v_modo_mat);
    if v_av ->> 'status' <> 'ok' then
      return public._agenda_recusa(v_av ->> 'texto', 'aviso_' || (v_av ->> 'status'), coalesce(v_av -> 'opcoes', '[]'::jsonb));
    end if;
    v_avd := jsonb_build_object(
      'tipo', v_av ->> 'tipo', 'pergunta_id', v_av ->> 'pergunta_id', 'remessa_id', v_av ->> 'remessa_id',
      'bank_transaction_id', v_av ->> 'bank_transaction_id', 'comprovante_id', v_av ->> 'comprovante_id',
      'sinal_id', v_av ->> 'sinal_id', 'canal', p_canal,
      'grupo', 'aviso:' || coalesce(v_av ->> 'pergunta_id', 'nfe:' || (v_av ->> 'remessa_id')),
      'rotulo_grupo', v_av ->> 'rotulo',
      'frase_pronta', 'não é material de serviço' || case v_av ->> 'tipo'
                        when 'nfe' then ' (estoque ou escritório). Não pergunto mais dela'
                        when 'pix' then '. Não pergunto mais dele'
                        else '. Não pergunto mais dela' end);
    v_item := public._agenda_rascunho_salvar(v_autor, p_canal, 'aviso', v_avd ->> 'grupo', null, v_avd, p_trecho, p_hoje);
    return jsonb_build_object('ok', true, 'item', v_item, 'itens', jsonb_build_array(v_item),
                              'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
  end if;
  -- FASE 4: fim
  v_acao := case lower(btrim(coalesce(p_situacao, '')))
    when 'comprei' then 'comprado' when 'comprado' then 'comprado'
    when 'a_caminho' then 'a_caminho'
    when 'na_mao' then 'na_mao' when 'chegou' then 'na_mao'
    when 'vou_comprar' then 'vou_comprar' when 'falta' then 'falta' when 'sem_previsao' then 'sem_previsao'
    when 'pode_comecar_sem' then 'pode_comecar_sem' when 'dispensar' then 'dispensar' end;
  if v_acao is null then
    raise exception 'agenda_rascunho_material: situação "%" não existe (comprei, a_caminho, na_mao, vou_comprar, falta, sem_previsao, pode_comecar_sem ou dispensar)',
      p_situacao using errcode = '22023';
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que aconteceu com o material.', 'sem_trecho');
  end if;
  if not exists (select 1 from unnest(coalesce(p_itens, '{}'::text[])) i where nullif(btrim(i), '') is not null) then
    return public._agenda_recusa('Qual material? Diga o nome da peça (ou "tudo").', 'sem_item');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  v_cab := public._agenda_os_do_rascunho(v_ro);
  -- FASE 4: o aviso da OS (a nota, o Pix ou a mensagem do fornecedor que a agenda perguntou): resolvido aqui, com a OS
  -- para desempatar; ambíguo ou não achado = a pergunta, e nada entra.
  if nullif(btrim(p_aviso), '') is not null then
    v_av := public._agenda_resolver_aviso(p_aviso, v_os, v_modo_mat);
    if v_av ->> 'status' <> 'ok' then
      return public._agenda_recusa(v_av ->> 'texto', 'aviso_' || (v_av ->> 'status'), coalesce(v_av -> 'opcoes', '[]'::jsonb));
    end if;
    if v_av ->> 'remessa_id' is not null then
      select * into v_rem from public.material_remessas where id = (v_av ->> 'remessa_id')::uuid;
    end if;
    v_tudo := exists (select 1 from unnest(coalesce(p_itens, '{}'::text[])) i where public._agenda_normal(i) = any (c_tudo));
  end if;
  -- FASE 4: fim

  -- A data, conferida no que o dono disse: chegou/comprei olham para trás; chega/vou comprar, para a frente.
  if nullif(btrim(p_quando), '') is not null and v_acao in ('comprado', 'a_caminho', 'na_mao', 'vou_comprar') then
    v_dt := public._agenda_data_conferida(p_quando, p_trecho, p_hoje,
                                          case when v_acao in ('comprado', 'na_mao') then 'passado' else 'futuro' end);
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if v_acao in ('comprado', 'na_mao') and (v_dt ->> 'ate')::date > p_hoje then
      return public._agenda_recusa(format('"%s" ainda não chegou. Quando %s?', btrim(p_quando),
                                          case v_acao when 'na_mao' then 'chegou' else 'comprou' end), 'data_futura');
    end if;
    if v_acao in ('a_caminho', 'vou_comprar') and (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. %s', btrim(p_quando),
                                          case v_acao when 'a_caminho' then 'Chegou?' else 'Quando vai comprar?' end), 'data_passada');
    end if;
  end if;

  if p_quantidade is not null then
    if p_quantidade <= 0 then
      return public._agenda_recusa('Quantas peças?', 'quantidade_invalida');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, p_quantidade) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quantas.', public._os_material_qtd(p_quantidade)),
                                   'fora_do_trecho');
    end if;
  end if;

  if nullif(btrim(p_fornecedor), '') is not null then
    v_forn := public._agenda_resolver_fornecedor(p_fornecedor);
    if v_forn ->> 'status' = 'ambiguo' then
      return public._agenda_recusa(v_forn ->> 'texto', 'fornecedor_ambiguo', v_forn -> 'opcoes');
    end if;
  end if;

  -- As chaves da situação: cada situação escreve todas as suas (nula quando não vale), para a correção apagar o que a
  -- situação anterior tinha; "pode começar sem" só mexe em critico; o fornecedor só quando foi dito.
  v_sit := case v_acao
    when 'comprado' then jsonb_build_object('acao', 'comprado', 'comprado_em', coalesce((v_dt ->> 'ate')::date, p_hoje),
                                            'chegou_em', null, 'compra_prevista_em', null, 'quantidade_na_mao', null,
                                            'vou_comprar', false)
    when 'a_caminho' then jsonb_build_object('acao', 'a_caminho', 'chegou_em', null, 'compra_prevista_em', null,
                                             'quantidade_na_mao', null, 'vou_comprar', false)
                          || case when v_dt is not null then jsonb_build_object(
                               'previsao_de', case when v_dt ->> 'de' <> v_dt ->> 'ate' then v_dt ->> 'de' end,
                               'previsao_ate', v_dt ->> 'ate') else '{}'::jsonb end
    when 'na_mao' then jsonb_build_object('acao', 'na_mao', 'chegou_em', coalesce((v_dt ->> 'ate')::date, p_hoje),
                                          'compra_prevista_em', null, 'quantidade_na_mao', null, 'vou_comprar', false)
    when 'vou_comprar' then jsonb_build_object('acao', 'falta', 'vou_comprar', true, 'compra_prevista_em', v_dt ->> 'de',
                                               'comprado_em', null, 'previsao_de', null, 'previsao_ate', null,
                                               'chegou_em', null, 'quantidade_na_mao', null)
    when 'falta' then jsonb_build_object('acao', 'falta', 'vou_comprar', false, 'compra_prevista_em', null,
                                         'comprado_em', null, 'previsao_de', null, 'previsao_ate', null, 'chegou_em', null,
                                         'quantidade_na_mao', null)
    when 'sem_previsao' then jsonb_build_object('acao', 'sem_previsao', 'previsao_de', null, 'previsao_ate', null,
                                                'chegou_em', null, 'compra_prevista_em', null, 'quantidade_na_mao', null,
                                                'vou_comprar', false)
    when 'pode_comecar_sem' then jsonb_build_object('critico', false)
    else jsonb_build_object('acao', 'dispensado', 'compra_prevista_em', null, 'vou_comprar', false) end;
  if v_forn is not null then
    v_sit := v_sit || jsonb_build_object('fornecedor_id', case when v_forn ->> 'status' = 'ok' then v_forn ->> 'id' end,
                                         'fornecedor_nome', case when v_forn ->> 'status' = 'novo' then v_forn ->> 'nome' end,
                                         'fornecedor_txt', v_forn ->> 'nome');
  end if;
  -- FASE 4: o que o aviso traz (spec §5.3): a fonte; a nota que já entrou no estoque = na mão desde a importação; a caminho
  -- sem data dita = a previsão da nota (fonte nfe) ou a da mensagem do fornecedor; a nota e o Pix dizem o dia da compra
  -- (comprado_fonte nfe/pix); a data dita vence (fonte dono). A nota, o Pix e a mensagem vão na evidência pelo *grava*.
  if v_av is not null then
    v_avd := jsonb_build_object(
      'tipo', v_av ->> 'tipo', 'pergunta_id', v_av ->> 'pergunta_id', 'remessa_id', v_av ->> 'remessa_id',
      'nfe_chave', v_rem.nfe_chave, 'email_attachment_id', v_rem.email_attachment_id,
      'bank_transaction_id', v_av ->> 'bank_transaction_id', 'comprovante_id', v_av ->> 'comprovante_id',
      'sinal_id', v_av ->> 'sinal_id', 'whatsapp_message_id', v_av ->> 'whatsapp_message_id', 'curto', v_av ->> 'curto');
    v_sit := v_sit || jsonb_build_object('aviso', v_avd, 'canal', p_canal,
                                         'fonte', case v_av ->> 'tipo' when 'nfe' then 'nfe' when 'pix' then 'pix' else 'fornecedor' end,
                                         'nota_chegou', false);
    if v_av ->> 'tipo' = 'nfe' and v_rem.estado = 'chegou' and v_acao in ('comprado', 'a_caminho', 'na_mao', 'sem_previsao') then
      v_sit := v_sit || jsonb_build_object('acao', 'na_mao', 'chegou_em', v_rem.chegou_em, 'compra_prevista_em', null,
                                           'quantidade_na_mao', null, 'vou_comprar', false, 'nota_chegou', true,
                                           'comprado_em', v_rem.emitida_em, 'comprado_fonte', 'nfe');
    elsif v_av ->> 'tipo' = 'nfe' and v_acao in ('comprado', 'a_caminho', 'na_mao', 'sem_previsao') then
      if not (v_acao = 'comprado' and v_dt is not null) then
        v_sit := v_sit || jsonb_build_object('comprado_em', v_rem.emitida_em, 'comprado_fonte', 'nfe');
      end if;
      if v_acao = 'a_caminho' and v_dt is null then
        v_sit := v_sit || jsonb_build_object('previsao_de', null, 'previsao_ate', v_rem.previsao_ate,
                                             'previsao_fonte', case when v_rem.previsao_ate is not null then 'nfe' end);
      end if;
    elsif v_av ->> 'tipo' = 'pix' and v_acao in ('comprado', 'a_caminho', 'na_mao', 'sem_previsao') then
      if not (v_acao = 'comprado' and v_dt is not null) then
        v_sit := v_sit || jsonb_build_object('comprado_em', (v_av ->> 'dia')::date, 'comprado_fonte', 'pix');
      end if;
    elsif v_av ->> 'tipo' = 'sinal' and v_acao = 'a_caminho' and v_dt is null and v_av ->> 'data_ate' is not null then
      v_sit := v_sit || jsonb_build_object('previsao_de', case when v_av ->> 'data_de' <> v_av ->> 'data_ate' then v_av ->> 'data_de' end,
                                           'previsao_ate', v_av ->> 'data_ate', 'previsao_fonte', 'fornecedor');
    end if;
  end if;
  if v_dt is not null and v_acao in ('comprado', 'a_caminho') then
    v_sit := v_sit || jsonb_build_object('previsao_fonte', 'dono');
  end if;
  -- FASE 4: fim

  -- Os itens da OS como a prontidão vê (conta bruta + os_material), sem sincronizar nada.
  v_itens := coalesce(public.os_prontidao(v_os, p_hoje) #> '{material,itens}', '[]'::jsonb);
  v_crit := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                       where (e ->> 'critico')::boolean), '[]'::jsonb);
  v_total := jsonb_array_length(v_crit);

  if coalesce(p_novo, false) then
    -- Material fora do orçamento: linha nova do dono, ligada à linha de serviço em que estava embutida quando o nome
    -- casa com uma só linha de texto livre da OS.
    foreach v_item in array p_itens loop
      continue when nullif(btrim(v_item), '') is null;
      v_tok := array(select t from unnest(string_to_array(public._agenda_normal(v_item), ' ')) with ordinality u(t, o)
                      where t <> all (c_vazias) and t <> all (c_generico) order by o);
      v_lserv := null;
      if cardinality(v_tok) > 0 then
        select min(s.id::text)::uuid into v_lserv
          from public.service_order_services s
         where s.service_order_id = v_os and s.service_id is null
           and not exists (select 1 from unnest(v_tok) t
                            where not exists (select 1 from unnest(string_to_array(public._agenda_normal(s.name_snapshot), ' ')) w
                                               where w like t || '%'))
        having count(*) = 1;
      end if;
      v_sel := v_sel || jsonb_build_array(jsonb_build_object(
        'chave', 'material:novo:' || v_os::text || ':' || md5(public._agenda_normal(v_item)),
        'origem', 'dono', 'novo', true, 'vinculo', null, 'linha_id', null,
        'descricao', left(public._agenda_maiuscula(btrim(v_item)), 200), 'quantidade_necessaria', coalesce(p_quantidade, 1),
        'servico_linha', v_lserv,
        'rotulo', public._agenda_linha_curta(public._agenda_maiuscula(btrim(v_item))) || ' (fora do orçamento)'));
    end loop;
  else
    foreach v_item in array p_itens loop
      continue when nullif(btrim(v_item), '') is null;
      v_tok := array(select t from unnest(string_to_array(public._agenda_normal(v_item), ' ')) with ordinality u(t, o)
                      where t <> all (c_vazias) order by o);
      v_esp := array(select t from unnest(v_tok) with ordinality u(t, o) where t <> all (c_generico) and t <> all (c_tudo) order by o);
      if v_tok && c_tudo and cardinality(v_esp) = 0 then
        -- "tudo", "todos os itens": todos os críticos.
        v_cands := v_crit;
        if jsonb_array_length(v_cands) = 0 then
          return public._agenda_recusa(format('O serviço de %s não tem material no orçamento. Se tem peça, me diga qual (é peça nova).',
                                              v_cab ->> 'rotulo_grupo'), 'sem_material');
        end if;
      elsif cardinality(v_esp) = 0 then
        -- "a peça", "o material": a única crítica que ainda não está na mão.
        v_cands := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_crit) with ordinality t(e, o)
                              where e ->> 'nivel' <> 'A'), '[]'::jsonb);
        v_n := jsonb_array_length(v_cands);
        if v_n = 0 then
          return public._agenda_recusa(format('Não tem peça faltando no serviço de %s.', v_cab ->> 'rotulo_grupo'), 'item_nao_achei');
        end if;
        if v_n > 1 then
          v_opc := array(select public._agenda_rotulo_do_item(e ->> 'descricao', null)
                           from jsonb_array_elements(v_cands) with ordinality t(e, o) order by o);
          return public._agenda_recusa(format('Qual peça do %s: %s ou %s?', v_cab ->> 'curto',
                                              array_to_string(v_opc[1:cardinality(v_opc) - 1], ', '), v_opc[cardinality(v_opc)]),
                                       'item_ambiguo', to_jsonb(v_opc));
        end if;
      else
        -- Pelo nome: todo pedaço do que o dono disse começa uma palavra da descrição.
        v_cands := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                              where not exists (select 1 from unnest(v_esp) tk
                                                 where not exists (select 1 from unnest(string_to_array(
                                                                     public._agenda_normal(e ->> 'descricao'), ' ')) w
                                                                    where w like tk || '%'))), '[]'::jsonb);
        v_n := jsonb_array_length(v_cands);
        if v_n = 0 then
          v_opc := array(select public._agenda_rotulo_do_item(e ->> 'descricao', null)
                           from jsonb_array_elements(v_itens) with ordinality t(e, o) order by o);
          return public._agenda_recusa(format('Não achei "%s" no material de %s. %s Se é peça que não está no orçamento, me diga que é nova.',
                                              btrim(v_item), v_cab ->> 'rotulo_grupo',
                                              case when cardinality(v_opc) = 0 then 'O orçamento não tem peça.'
                                                   else 'Tem: ' || public._agenda_lista(v_opc, 6)
                                                        || case when right(public._agenda_lista(v_opc, 6), 1) = '…' then '' else '.' end end),
                                       'item_nao_achei', to_jsonb(v_opc));
        end if;
        if v_n > 1 then
          v_opc := array(select public._agenda_rotulo_do_item(e ->> 'descricao', v_esp)
                           from jsonb_array_elements(v_cands) with ordinality t(e, o) order by o);
          return public._agenda_recusa(format('Qual "%s" do %s: %s ou %s?', btrim(v_item), v_cab ->> 'curto',
                                              array_to_string(v_opc[1:cardinality(v_opc) - 1], ', '), v_opc[cardinality(v_opc)]),
                                       'item_ambiguo', to_jsonb(v_opc));
        end if;
      end if;
      for v_x in select e from jsonb_array_elements(v_cands) with ordinality t(e, o) order by o loop
        v_dados := jsonb_build_object(
          'chave', case when v_x ->> 'origem' = 'dono' then 'material:dono:' || (v_x ->> 'id')
                        else 'material:' || (v_x ->> 'origem') || ':' || (v_x ->> 'linha') end,
          'origem', v_x ->> 'origem', 'novo', false, 'vinculo', v_x ->> 'linha', 'linha_id', v_x ->> 'id',
          'descricao', v_x ->> 'descricao', 'quantidade_necessaria', (v_x ->> 'quantidade')::numeric,
          'rotulo', public._agenda_rotulo_do_item(v_x ->> 'descricao', v_esp));
        continue when exists (select 1 from jsonb_array_elements(v_sel) s where s ->> 'chave' = v_dados ->> 'chave');
        v_sel := v_sel || jsonb_build_array(v_dados);
      end loop;
    end loop;
  end if;

  -- FASE 4: "a nota da Kamell é do Nelson" com itens ["tudo"]: só as linhas da OS em falta/comprado com o fornecedor da
  -- nota ou sem fornecedor (a releitura lista; o dono corrige).
  if v_tudo and v_av ->> 'tipo' = 'nfe' then
    v_sel := coalesce((
      select jsonb_agg(s order by o)
        from jsonb_array_elements(v_sel) with ordinality t(s, o)
        cross join lateral (
          select coalesce((select m.fornecedor_id from public.os_material m where m.id::text = s ->> 'linha_id'),
                          (select p.supplier_id from public.service_order_parts sp join public.products p on p.id = sp.product_id
                            where s ->> 'origem' = 'peca' and sp.id::text = s ->> 'vinculo')) as forn) f
       where (f.forn is null or f.forn = v_rem.fornecedor_id)
         and exists (select 1 from jsonb_array_elements(v_itens) e
                      where coalesce(e ->> 'id', '') = coalesce(s ->> 'linha_id', '')
                        and e ->> 'linha' is not distinct from s ->> 'vinculo'
                        and e ->> 'situacao' in ('falta', 'comprado'))), '[]'::jsonb);
    if jsonb_array_length(v_sel) = 0 then
      return public._agenda_recusa(format('Nada do material de %s espera a %s. Diga qual peça é.', v_cab ->> 'rotulo_grupo',
                                          public._agenda_remessa_nota(v_rem.id)), 'aviso_sem_item');
    end if;
  end if;
  -- FASE 4: fim
  if v_acao = 'na_mao' and p_quantidade is not null and jsonb_array_length(v_sel) > 1 then
    return public._agenda_recusa('Me diga a quantidade de uma peça por vez.', 'quantidade_varios');
  end if;

  for v_x in select e from jsonb_array_elements(v_sel) with ordinality t(e, o) order by o loop
    v_dados := v_cab || (v_x - 'chave') || v_sit || jsonb_build_object('total_itens', v_total);
    if v_acao = 'na_mao' and p_quantidade is not null and not coalesce((v_x ->> 'novo')::boolean, false)
       and p_quantidade < (v_x ->> 'quantidade_necessaria')::numeric then
      v_dados := v_dados || jsonb_build_object('quantidade_na_mao', p_quantidade);   -- parcial: o resto continua faltando
    end if;
    v_textos := v_textos || public._agenda_rascunho_salvar(v_autor, p_canal, 'material', v_x ->> 'chave', v_os, v_dados,
                                                          p_trecho, p_hoje);
  end loop;

  return jsonb_build_object('ok', true, 'item', array_to_string(v_textos, E'\n'), 'itens', to_jsonb(v_textos),
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date, text) is
  'Agenda de Produção (Fase 1, P5; Fase 4, P3: p_aviso — a nota, o Pix ou a mensagem do fornecedor que a agenda perguntou, como o dono disse, resolvido por _agenda_resolver_aviso; ambíguo = a pergunta. Com o aviso, a fonte nfe/pix/fornecedor, a nota já importada = na mão desde a importação, a caminho sem data = a previsão da nota ou da mensagem, o dia da compra pela nota ou pelo Pix, a data dita vence; "tudo" com a nota = só as linhas em falta/comprado do fornecedor da nota ou sem fornecedor. nao_e_de_servico = sem OS nem itens, linha tipo aviso. Nada liga a nota ou o Pix antes do *grava*): o que o dono disse do material vira RASCUNHO (nada em os_material; nem a sincronização roda). Itens pelo nome contra a descrição ("compressor", "Cerbo"), "tudo" = os críticos, "a peça" = a única crítica fora da mão; ambíguo/não achado = pergunta com as opções. Situações: comprei, a_caminho (+ quando = previsão do dono, nível C), na_mao/chegou (chegou_em = a data dita ou hoje; quantidade parcial dita), vou_comprar (+ quando = compra combinada, + fornecedor), falta, sem_previsao, pode_comecar_sem (critico false), dispensar. p_novo = material fora do orçamento (origem dono). Datas e quantidade têm de estar no trecho; fornecedor resolvido (ambíguo = pergunta). Devolve {ok, item, itens, releitura}.';


-- ── 10. O *grava* da linha de material: o aviso ─────────────────────────────────────────────────────────
-- Corpo de 20261024160600 copiado; as mudanças estão marcadas "-- FASE 4:" (só acréscimo).


create or replace function public._agenda_aplicar_material(p_autor uuid, p_os uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d      jsonb := coalesce(p_dados, '{}'::jsonb);
  v_old  public.os_material%rowtype;
  v_new  public.os_material%rowtype;
  v_req  numeric;
  v_vinc uuid := (d ->> 'vinculo')::uuid;
  -- FASE 4: o aviso (a nota, o Pix ou a mensagem que a agenda perguntou) e de onde veio a compra.
  v_av     jsonb := case when jsonb_typeof(d -> 'aviso') = 'object' then d -> 'aviso' end;
  v_cfonte text;
  -- FASE 4: fim
begin
  if coalesce((d ->> 'novo')::boolean, false) then
    insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria,
                                    situacao, historico)
    values (p_os, (d ->> 'servico_linha')::uuid, 'dono', left(d ->> 'descricao', 200),
            coalesce((d ->> 'quantidade_necessaria')::numeric, 1), 'falta', '[]'::jsonb)
    returning * into v_old;
  elsif d ->> 'origem' = 'dono' then
    select * into v_old from public.os_material where id = (d ->> 'linha_id')::uuid and service_order_id = p_os for update;
    if not found then
      raise exception '"%" saiu do serviço', d ->> 'rotulo' using errcode = 'P0001';
    end if;
  else
    select m.* into v_old
      from public.os_material m
     where m.service_order_id = p_os and m.origem = d ->> 'origem'
       and v_vinc = case m.origem when 'peca' then m.service_order_part_id
                                  when 'texto_livre' then m.service_order_service_id
                                  else m.purchase_order_item_id end
     for update;
    if not found then
      -- Linha que a sincronização não cria (item de OC que já chegou): nasce aqui, pelo vínculo, se ainda for da OS.
      if not (case d ->> 'origem'
                when 'peca' then exists (select 1 from public.service_order_parts x where x.id = v_vinc and x.service_order_id = p_os)
                when 'texto_livre' then exists (select 1 from public.service_order_services x where x.id = v_vinc and x.service_order_id = p_os)
                when 'oc' then exists (select 1 from public.purchase_order_items x join public.purchase_orders po on po.id = x.purchase_order_id
                                        where x.id = v_vinc and po.service_order_id = p_os)
                else false end) then
        raise exception '"%" saiu do serviço', d ->> 'rotulo' using errcode = 'P0001';
      end if;
      insert into public.os_material (service_order_id, service_order_part_id, service_order_service_id, purchase_order_item_id,
                                      origem, descricao, quantidade_necessaria, situacao, historico)
      values (p_os,
              case when d ->> 'origem' = 'peca' then v_vinc end,
              case when d ->> 'origem' = 'texto_livre' then v_vinc end,
              case when d ->> 'origem' = 'oc' then v_vinc end,
              d ->> 'origem', left(coalesce(d ->> 'descricao', 'Material'), 200),
              coalesce((d ->> 'quantidade_necessaria')::numeric, 1), 'falta', '[]'::jsonb)
      returning * into v_old;
    end if;
  end if;

  v_new := v_old;
  v_req := v_old.quantidade_necessaria;
  if d ? 'acao' then
    v_new.fonte := 'dono';
    case d ->> 'acao'
      when 'na_mao' then
        if d ->> 'quantidade_na_mao' is not null and (d ->> 'quantidade_na_mao')::numeric < v_req then
          -- Parcial: o que chegou fica guardado e a situação continua a de antes (o resto ainda falta).
          v_new.quantidade_na_mao := (d ->> 'quantidade_na_mao')::numeric;
          if v_new.situacao in ('na_mao', 'dispensado') then
            v_new.situacao := 'falta';
            v_new.chegou_em := null;
          end if;
        else
          v_new.situacao := 'na_mao';
          v_new.quantidade_na_mao := v_req;
          v_new.chegou_em := (d ->> 'chegou_em')::date;
          v_new.compra_prevista_em := null;
        end if;
      when 'comprado' then
        v_new.situacao := 'comprado';
        v_new.comprado_em := (d ->> 'comprado_em')::date;
        v_new.chegou_em := null;
        v_new.compra_prevista_em := null;
        if d ->> 'previsao_ate' is not null then
          v_new.previsao_de := (d ->> 'previsao_de')::date;
          v_new.previsao_ate := (d ->> 'previsao_ate')::date;
          v_new.previsao_fonte := 'dono';
          v_new.previsao_original := coalesce(v_old.previsao_original, v_new.previsao_ate);
        end if;
      when 'a_caminho' then
        v_new.situacao := 'a_caminho';
        v_new.chegou_em := null;
        v_new.compra_prevista_em := null;
        -- "Tá a caminho" sem data: o pedido conta do dia em que o dono contou (ou da compra já sabida). Sem isso a
        -- chegada estimada anda para a frente todo dia e nunca vence ("chegou?" não sai).
        if d ->> 'comprado_em' is not null then
          v_new.comprado_em := (d ->> 'comprado_em')::date;
        elsif d ->> 'previsao_ate' is null then
          v_new.comprado_em := coalesce(v_old.comprado_em, p_hoje);
        end if;
        if d ->> 'previsao_ate' is not null then
          v_new.previsao_de := (d ->> 'previsao_de')::date;
          v_new.previsao_ate := (d ->> 'previsao_ate')::date;
          v_new.previsao_fonte := 'dono';
          v_new.previsao_original := coalesce(v_old.previsao_original, v_new.previsao_ate);
        end if;
      when 'sem_previsao' then
        v_new.situacao := 'comprado';
        v_new.previsao_de := null;
        v_new.previsao_ate := null;
        v_new.previsao_fonte := null;
        v_new.chegou_em := null;
        v_new.compra_prevista_em := null;
      when 'falta' then
        v_new.situacao := 'falta';
        v_new.compra_prevista_em := (d ->> 'compra_prevista_em')::date;
        v_new.comprado_em := null;
        v_new.previsao_de := null;
        v_new.previsao_ate := null;
        v_new.previsao_fonte := null;
        v_new.chegou_em := null;
      when 'dispensado' then
        v_new.situacao := 'dispensado';
        v_new.compra_prevista_em := null;
      else
        raise exception 'situação "%" desconhecida no rascunho', d ->> 'acao' using errcode = 'P0001';
    end case;
    -- FASE 4: o aviso: a fonte (nfe, pix ou fornecedor), a previsão que a nota ou o fornecedor trouxe, e o dia da compra
    -- pela nota ou pelo Pix (comprado_fonte).
    if v_av is not null then
      v_new.fonte := coalesce(d ->> 'fonte', v_new.fonte);
      if v_new.previsao_ate is not null and d ->> 'previsao_fonte' is not null then
        v_new.previsao_fonte := d ->> 'previsao_fonte';
      end if;
      if d ->> 'comprado_fonte' is not null and d ->> 'comprado_em' is not null
         and v_new.situacao in ('comprado', 'a_caminho', 'na_mao') then
        v_new.comprado_em := (d ->> 'comprado_em')::date;
        v_cfonte := d ->> 'comprado_fonte';
      end if;
    end if;
    -- FASE 4: fim
    -- Fora de "na mão" e de "dispensado", a quantidade na mão é só a parcial (a completa voltou a faltar).
    if v_new.situacao not in ('na_mao', 'dispensado') and v_new.quantidade_na_mao >= v_req then
      v_new.quantidade_na_mao := 0;
    end if;
  end if;
  if d ? 'critico' then
    v_new.critico := (d ->> 'critico')::boolean;
  end if;
  if d ? 'fornecedor_id' or d ? 'fornecedor_nome' then
    v_new.fornecedor_id := (d ->> 'fornecedor_id')::uuid;
    v_new.fornecedor_nome := left(d ->> 'fornecedor_nome', 80);
  end if;

  update public.os_material
     set situacao = v_new.situacao, fonte = v_new.fonte, quantidade_na_mao = v_new.quantidade_na_mao,
         critico = v_new.critico, fornecedor_id = v_new.fornecedor_id, fornecedor_nome = v_new.fornecedor_nome,
         compra_prevista_em = v_new.compra_prevista_em, comprado_em = v_new.comprado_em,
         previsao_de = v_new.previsao_de, previsao_ate = v_new.previsao_ate, previsao_original = v_new.previsao_original,
         previsao_fonte = v_new.previsao_fonte, chegou_em = v_new.chegou_em,
         trecho = public._agenda_corta(p_trecho, 300), conferido_em = now(),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'de', case when coalesce((d ->> 'novo')::boolean, false) then null else v_old.situacao end,
           'para', v_new.situacao, 'por', 'dono', 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 300),
           'nota', d ->> 'frase')),
         atualizado_em = now(), atualizado_por = p_autor
   where id = v_old.id;
  -- FASE 4: o aviso no *grava* (vínculo sempre pergunta: só aqui, depois do *grava* do dono): a nota na linha
  -- (remessa_id), de onde veio a compra, a evidência; a nota fica ligada à OS e a pergunta respondida; a mensagem do
  -- fornecedor, aplicada.
  if v_av is not null then
    update public.os_material m
       set remessa_id = coalesce((v_av ->> 'remessa_id')::uuid, m.remessa_id),
           comprado_fonte = case when m.comprado_em is null then null else coalesce(v_cfonte, m.comprado_fonte) end,
           evidencia = jsonb_strip_nulls(jsonb_build_object(
             'remessa_id', v_av ->> 'remessa_id', 'nfe_chave', v_av ->> 'nfe_chave',
             'email_attachment_id', v_av ->> 'email_attachment_id', 'bank_transaction_id', v_av ->> 'bank_transaction_id',
             'comprovante_id', v_av ->> 'comprovante_id', 'whatsapp_message_id', v_av ->> 'whatsapp_message_id',
             'trecho', public._agenda_corta(p_trecho, 300), 'vinculo_por', 'dono'))
     where m.id = v_old.id;
    if v_av ->> 'remessa_id' is not null then
      update public.material_remessas r
         set vinculo = 'ligada',
             os_ids = case when p_os = any (r.os_ids) then r.os_ids else r.os_ids || p_os end,
             respondida_em = coalesce(r.respondida_em, now()), respondida_por = coalesce(r.respondida_por, p_autor),
             historico = case when p_os = any (r.os_ids) then r.historico
                              else public._os_material_historico(r.historico, jsonb_build_object(
                                     'em', p_hoje, 'por', 'dono', 'os', p_os,
                                     'nota', 'ligada a ' || coalesce(public._agenda_rotulo_da_os(p_os), 'uma OS'))) end
       where r.id = (v_av ->> 'remessa_id')::uuid;
    end if;
    if v_av ->> 'sinal_id' is not null then
      update public.material_sinais s
         set estado = 'aplicado', os_material_id = v_old.id, service_order_id = p_os
       where s.id = (v_av ->> 'sinal_id')::uuid and s.estado <> 'aplicado';
    end if;
    if v_av ->> 'pergunta_id' is not null then
      update public.agenda_perguntas q
         set estado = 'respondida', respondida_em = now(), respondida_por = p_autor,
             respondida_via = case when d ->> 'canal' in ('whatsapp', 'painel') then d ->> 'canal' end,
             resposta = left(nullif(btrim(coalesce(p_trecho, '')), ''), 500),
             opcao_escolhida = (select (e ->> 'n')::smallint from jsonb_array_elements(q.opcoes) e
                                 where e ->> 'os' = p_os::text limit 1)
       where q.id = (v_av ->> 'pergunta_id')::uuid and q.estado = 'aberta';
    end if;
  end if;
  -- FASE 4: fim
  return jsonb_build_object('linha', v_old.id, 'de', v_old.situacao, 'para', v_new.situacao);
end;
$function$;

comment on function public._agenda_aplicar_material(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 4, P3: com o aviso, a fonte nfe/pix/fornecedor, a previsão da nota ou do fornecedor, o dia da compra e comprado_fonte, a nota na linha — remessa_id —, a evidência {remessa_id, nfe_chave, email_attachment_id | bank_transaction_id | comprovante_id | whatsapp_message_id, trecho, vinculo_por dono}, a nota ligada à OS, o sinal aplicado e a pergunta respondida): grava em os_material uma linha de rascunho material — acha a linha pelo vínculo (ou cria: material novo do dono, item de OC que a sincronização não cria), aplica a situação dita (fonte dono; previsão do dono com previsao_original na 1ª; na mão com a quantidade completa ou a parcial), critico e fornecedor; histórico {em, de, para, por dono, autor, trecho, nota}. Só pelo agenda_rascunho_gravar; só service_role.';


-- ── 11. A frase do rascunho: o aviso e o tipo aviso ─────────────────────────────────────────────────────
-- Corpo de 20261027100100 (P1) copiado; as mudanças estão marcadas "-- FASE 4: (P3)" (só acréscimo).


create or replace function public._agenda_rascunho_frase(p_tipo text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_t      text;
  v_forn   text := nullif(p_d ->> 'fornecedor_txt', '');
  v_hoje   date := (p_d ->> 'hoje')::date;
  v_quando text;
  -- FASE 4: (P3) de onde veio o aviso ("nota 51038 da Kamell", "Pix de R$ 480,00 à Premel, seg 26/10").
  v_aviso  text;
  -- FASE 4: fim
begin
  if p_tipo = 'planejar' then
    if nullif(p_d ->> 'escopo_decidido', '') is not null then
      v_partes := v_partes || (p_d ->> 'escopo_decidido');
    end if;
    v_t := null;
    if p_d ->> 'dias' is not null then
      v_t := public._agenda_dias((p_d ->> 'dias')::numeric)
             || case when p_d ->> 'estimativa_fonte' = 'aceita' then ' (a minha estimativa, que você aceitou)' else '' end;
    end if;
    if jsonb_array_length(coalesce(p_d -> 'equipe', '[]'::jsonb)) > 0 then
      v_t := concat_ws(' ', v_t, 'com ' || public._agenda_lista(array(
               select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                      || case e ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                 from jsonb_array_elements(p_d -> 'equipe') with ordinality t(e, o) order by o), null));
    elsif p_d ? 'equipe' and p_d ->> 'dias' is null then
      v_t := 'sem ninguém marcado para ir';
    end if;
    if v_t is not null then
      v_partes := v_partes || v_t;
    end if;
    if p_d ->> 'dono' is not null then
      v_partes := v_partes || case p_d ->> 'dono' when 'abre_e_fecha' then 'você abre e fecha'
                                                 when 'sempre' then 'você fica o tempo todo' else 'você não vai' end;
    end if;
    if p_d ->> 'precisa_ate' is not null then
      v_partes := v_partes || ('o cliente precisa até ' || public._dia_curto((p_d ->> 'precisa_ate')::date));
    elsif p_d ? 'precisa_ate' then
      v_partes := v_partes || 'o cliente não tem mais prazo'::text;
    end if;
    if p_d ? 'bem' then
      v_partes := v_partes || case p_d #>> '{bem,modo}'
        when 'livre' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' já está livre'
        when 'fora' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica fora '
                         || public._agenda_quando_texto((p_d #>> '{bem,de}')::date, (p_d #>> '{bem,ate}')::date)
        else coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica livre ' || public._dia_curto((p_d #>> '{bem,livre_em}')::date) end;
    end if;
    if p_d ->> 'nao_antes_de' is not null then
      v_partes := v_partes || ('não antes de ' || public._dia_curto((p_d ->> 'nao_antes_de')::date)
                               || case when coalesce(p_d ->> 'nao_antes_motivo', 'você disse') = 'você disse' then ''
                                       else ' (' || (p_d ->> 'nao_antes_motivo') || ')' end);
    elsif p_d ? 'nao_antes_de' then
      v_partes := v_partes || 'pode começar sem esperar data'::text;
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    elsif p_d ? 'escopo_em_aberto' and nullif(p_d ->> 'escopo_decidido', '') is null then
      v_partes := v_partes || 'nada mais a decidir no escopo'::text;
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    elsif p_d ? 'congelada_ate' then
      v_partes := v_partes || 'sai da espera'::text;
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
    end if;
    -- FASE 2: quanto dá para adiantar no pátio sem o bem (bancada: barramento, chicote).
    if p_d ? 'adiantavel_patio' then
      v_partes := v_partes || case when p_d ->> 'adiantavel_patio' is null then 'nada a adiantar no pátio'
                                   else 'dá para adiantar ' || public._agenda_dias((p_d ->> 'adiantavel_patio')::numeric) || ' no pátio' end;
    end if;
    return array_to_string(v_partes, '; ');
  end if;

  if p_tipo = 'material' then
    v_t := case p_d ->> 'acao'
      when 'na_mao' then
        case when p_d ->> 'quantidade_na_mao' is not null
             then format('%s de %s na mão', public._os_material_qtd((p_d ->> 'quantidade_na_mao')::numeric),
                         public._os_material_qtd((p_d ->> 'quantidade_necessaria')::numeric))
             when (p_d ->> 'chegou_em')::date = v_hoje then 'na mão (desde hoje)'
             else 'na mão desde ' || public._dia_curto((p_d ->> 'chegou_em')::date) end
      when 'comprado' then
        'comprado' || case when (p_d ->> 'comprado_em')::date = v_hoje then ' hoje'
                           else ' em ' || public._dia_curto((p_d ->> 'comprado_em')::date) end
        || case when p_d ->> 'previsao_ate' is not null
                then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' else '' end
      when 'a_caminho' then
        case when p_d ->> 'previsao_ate' is null then 'a caminho, sem previsão'
             when p_d ->> 'previsao_de' is not null then
               format('chega entre %s e %s (você disse)', public._dia_curto((p_d ->> 'previsao_de')::date),
                      public._dia_curto((p_d ->> 'previsao_ate')::date))
             else 'chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' end
      when 'falta' then
        case when coalesce((p_d ->> 'vou_comprar')::boolean, false) then
               case when p_d ->> 'compra_prevista_em' is null then 'você vai comprar'
                    else 'você compra ' || public._dia_curto((p_d ->> 'compra_prevista_em')::date) end
             else 'falta comprar' end
      when 'sem_previsao' then 'comprado, sem previsão de chegada'
      when 'dispensado' then 'não precisa mais (sai da lista)'
      else null end;
    -- FASE 4: (P3) o aviso (a nota, o Pix ou a mensagem que a agenda perguntou) diz de onde veio; o fornecedor já está nele.
    if jsonb_typeof(p_d -> 'aviso') = 'object' then
      v_aviso := p_d -> 'aviso' ->> 'curto';
      v_t := case
        when coalesce((p_d ->> 'nota_chegou')::boolean, false) then
          format('na mão desde %s (a %s entrou no estoque)', public._dia_curto((p_d ->> 'chegou_em')::date), v_aviso)
        when p_d ->> 'acao' = 'na_mao' and p_d ->> 'quantidade_na_mao' is null then
          format('na mão desde %s (%s)', case when (p_d ->> 'chegou_em')::date = v_hoje then 'hoje'
                                              else public._dia_curto((p_d ->> 'chegou_em')::date) end, v_aviso)
        when p_d ->> 'acao' = 'a_caminho' and p_d -> 'aviso' ->> 'tipo' = 'nfe' then
          'a caminho pela ' || v_aviso
          || case when p_d ->> 'previsao_ate' is null then ', sem previsão de chegada'
                  when p_d ->> 'previsao_fonte' = 'dono' then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)'
                  else ', chega por volta de ' || public._dia_curto((p_d ->> 'previsao_ate')::date) end
        when p_d ->> 'acao' = 'a_caminho' and p_d ->> 'previsao_ate' is not null and p_d ->> 'previsao_fonte' = 'fornecedor' then
          format('a caminho, chega por volta de %s (%s)', public._dia_curto((p_d ->> 'previsao_ate')::date), v_aviso)
        when p_d ->> 'acao' = 'comprado' and p_d -> 'aviso' ->> 'tipo' = 'pix' and p_d ->> 'previsao_ate' is null
             and v_aviso like 'Pix %' then
          'comprado pelo ' || v_aviso
        else coalesce(v_t || ' (' || v_aviso || ')', v_t) end;
      if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
        v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
      end if;
      return v_t;
    end if;
    -- FASE 4: fim
    if v_t is not null and v_forn is not null and p_d ->> 'acao' <> 'dispensado' then
      v_t := v_t || ', fornecedor ' || v_forn;
    end if;
    if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
      v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
    end if;
    return v_t;
  end if;

  if p_tipo = 'disponibilidade' then
    v_quando := case when (p_d ->> 'padrao')::boolean
                     then public._agenda_dias_semana_texto(array(select jsonb_array_elements_text(p_d -> 'dias_semana')::smallint))
                     else public._agenda_quando_texto((p_d ->> 'de')::date, (p_d ->> 'ate')::date) end;
    return case p_d ->> 'dito'
      when 'vem' then case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end || v_quando
      when 'nao_vem' then case when (p_d ->> 'eh_dono')::boolean then 'fora de campo ' else 'não vem ' end || v_quando
      when 'so_manha' then v_quando || ' à tarde, não'
      else v_quando || ' de manhã, não' end
      || case when coalesce((p_d ->> 'sabado_por_data')::boolean, false) then ' (sábado eu só conto por data)' else '' end;
  end if;

  -- FASE 2: os pedidos da conversa (marcar, aplicar/decidir, desfazer, andamento) chegam com a frase pronta do banco.
  if p_tipo in ('marcar', 'aplicar', 'desfazer', 'andamento') then
    return p_d ->> 'frase_pronta';
  end if;

  -- FASE 4: o prazo do fornecedor chega com a frase pronta do banco (agenda_rascunho_fornecedor).
  if p_tipo = 'fornecedor' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 4: (P3) "não é material de serviço" (a nota, o Pix ou a mensagem) chega com a frase pronta (agenda_rascunho_material).
  if p_tipo = 'aviso' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento), o prazo do fornecedor (Fase 4) e o "não é de serviço" (tipo aviso, Fase 4, P3) trazem a frase pronta (dados.frase_pronta); o material com o aviso diz de onde veio ("a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10", "na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10)", "na mão desde qua 28/10 (a nota 51038 da Kamell entrou no estoque)").';


-- ── 12. O *grava*: o tipo aviso ─────────────────────────────────────────────────────────────────────────
-- Corpo de 20261027100100 (P1) copiado; a mudança está marcada "-- FASE 4: (P3)" (só acréscimo).


create or replace function public.agenda_rascunho_gravar(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_exp     int;
  v_exp_dia date;
  v_ids     uuid[];
  v_oss_mat uuid[];
  v_r       public.agenda_rascunho%rowtype;
  v_x       uuid;
  v_n       int := 0;
  v_item    text;
  v_estado  text;
  v_msg     text;
  v_linhas  text[] := '{}';
  v_g       record;
  v_p       jsonb;
  v_nome    int;
  -- FASE 2: a hora do *grava* (now(); a bancada fixa com set_config('agenda.agora', …, true), como agenda.hoje), a
  -- config, as frases do que a agenda fez com os pedidos e o tipo de cada linha.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  cf        public.agenda_config := public._agenda_cfg();
  v_f2      text[] := '{}';
  v_f2_item text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  -- FASE 2: primeiro os fatos (Fase 1), depois o andamento, marcar, publicar/decidir e desfazer — cada grupo na ordem em
  -- que o dono falou.
  select coalesce(array_agg(r.id order by case r.tipo when 'andamento' then 1 when 'marcar' then 2 when 'aplicar' then 3
                                                      when 'desfazer' then 4 else 0 end,
                                          (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- FASE 2: com a agenda automática fora de 'ligado', o pedido à agenda não grava — e o lote é tudo ou nada.
  -- FASE 3: menos concluir e entregar, que valem em todos os modos (a conclusão pela porta é a correção do D7).
  if cf.modo_proposta <> 'ligado'
     and exists (select 1 from public.agenda_rascunho r where r.id = any (v_ids) and r.tipo in ('marcar', 'aplicar', 'desfazer', 'andamento')
                    and not (r.tipo = 'andamento' and r.dados ->> 'evento' in ('concluiu', 'entregou'))) then
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'motivo', 'em_teste',
      'texto', 'Não gravei nada: a agenda automática ainda está em teste e o que você pediu mexe na agenda. Mande *descarta* e me diga de novo o resto.');
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca, UMA vez antes de entrar o lote, só o que ele realmente troca:
    --   · "vem" (seg a qui): as linhas de padrão dela (do histórico e do dono) que caem em algum desses dias; os
    --     outros dias da semana continuam como estavam;
    --   · "só de manhã", "só à tarde", "não vem" (terça): o "vem" fica; a linha indisponível do turno entra por cima
    --     (a capacidade põe o "não vem neste turno" acima do padrão "vem"). Só sai a restrição que o dono já tinha
    --     dito para os mesmos dias ("só à tarde às terças" e depois "só de manhã às terças").
    update public.agenda_disponibilidade a
       set substituida_em = now()
      from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                   array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
              from public.agenda_rascunho r
             where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
     where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
       and ((n.situacao = 'disponivel' and a.origem in ('historico', 'dono') and a.dias_semana && n.dias)
            or (n.situacao = 'indisponivel' and a.origem = 'dono' and a.situacao = 'indisponivel'
                and a.dias_semana <@ n.dias));

    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'disponibilidade' then
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: o prazo do fornecedor vai ao cadastro dele; a frase entra no "Gravado. Agora:" junto dos pedidos.
        when 'fornecedor' then
          v_f2 := v_f2 || public._agenda_aplicar_fornecedor(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: fim
        -- FASE 4: (P3) "a nota da Correa não é de serviço": a nota, o Pix ou a mensagem respondidos sem OS; a frase entra junto
        -- dos pedidos.
        when 'aviso' then
          v_f2 := v_f2 || public._agenda_aplicar_aviso(v_autor, v_r.dados, v_r.trecho, v_r.canal, p_hoje);
        -- FASE 4: fim
        else
          -- FASE 2: o pedido à agenda (marcar, aplicar/decidir, desfazer, andamento) pelas funções do motor.
          v_f2_item := public._agenda_aplicar_pedido(v_autor, v_r.tipo, v_r.service_order_id, v_r.dados, v_r.trecho, v_r.canal,
                                                     p_hoje, v_agora);
          if nullif(btrim(coalesce(v_f2_item, '')), '') is not null then
            v_f2 := v_f2 || v_f2_item;
          end if;
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    -- FASE 3: a porta recusou concluir ou entregar (o período fechado no financeiro): a frase dela.
    if v_estado = 'P0096' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', 'Não gravei nada. ' || btrim(v_msg));
    end if;
    -- FASE 2: a agenda recusou um pedido (a proposta ficou velha, a decisão mudou, não coube, já começou…).
    if v_estado = 'P0097' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', format('Não gravei nada. A agenda mudou desde a releitura: %s. Me peça de novo.', rtrim(btrim(v_msg), '.')));
    end if;
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
      'texto', format('Não gravei nada: %s (%s). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.',
                      case when v_estado = 'P0001' then v_msg else 'o banco recusou um item' end,
                      coalesce(v_item, 'o lote')));
  end;

  -- "Gravado. Agora:" — uma linha por OS (o estado da prontidão) e por pessoa, na ordem em que o dono falou.
  for v_g in
    select r.dados ->> 'grupo' as grupo, min((r.dados ->> 'ordem')::int) as ordem,
           (array_agg(r.service_order_id order by (r.dados ->> 'ordem')::int))[1] as os,
           (array_agg(r.dados order by (r.dados ->> 'ordem')::int))[1] as d,
           string_agg(r.dados ->> 'frase', '; ' order by (r.dados ->> 'ordem')::int) as frases
      from public.agenda_rascunho r
     where r.id = any (v_ids) and r.tipo in ('planejar', 'material', 'disponibilidade')   -- FASE 2: os pedidos vêm em v_f2
     group by r.dados ->> 'grupo'
     order by 2
  loop
    if v_g.os is not null then
      v_p := public.os_prontidao(v_g.os, p_hoje);
      select count(*) into v_nome from public.os_carteira(p_hoje) k where k.cliente_curto = v_p ->> 'cliente_curto';
      v_linhas := v_linhas || ('• ' || public._agenda_rotulo(jsonb_build_object(
                                 'curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero',
                                 'eh_orc', (v_p ->> 'eh_orcamento')::boolean, 'n_nome', v_nome))
                               || ': ' || (v_p ->> 'estado_texto') || '.');
    else
      v_linhas := v_linhas || ('• ' || (v_g.d ->> 'rotulo_grupo') || ': ' || v_g.frases || '.');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade; Fase 4: _agenda_aplicar_fornecedor, o prazo dito de um fornecedor, que não depende do modo da agenda; Fase 4, P3: _agenda_aplicar_aviso, o "não é de serviço" da nota, do Pix ou da mensagem), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava (Fase 3: menos concluir e entregar, que gravam em todos os modos; a recusa da porta = "Não gravei nada. Não concluí: …" e o lote volta). Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo.';


-- ── 13. A carona: a pergunta do material da OS ──────────────────────────────────────────────────────────
-- Corpo de 20261026100500 copiado; a mudança está marcada "-- FASE 4:" (só acréscimo).


create or replace function public.agenda_carona(p_autor uuid, p_os text[], p_canal text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_ids uuid[] := '{}';
  v_ro  jsonb;
  v_ref text;
  v_os  uuid;
  q     record;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_carona: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'Por onde: "%" (whatsapp ou painel).', coalesce(p_canal, '') using errcode = '22023';
  end if;
  -- só com a vigia ligada (a pergunta de fato é dela) e só para o dono
  if cf.modo_vigia <> 'ligado' then
    return null;
  end if;
  if p_autor is null or not exists (select 1 from public.app_users u where u.id = p_autor and u.active and u.role = 'admin') then
    return null;
  end if;
  -- as OS como o turno citou (número, nome ou id), resolvidas aqui; ref ambígua = nada (pode ser outra OS)
  foreach v_ref in array coalesce(p_os, '{}'::text[]) loop
    continue when nullif(btrim(v_ref), '') is null;
    v_ro := public.agenda_resolver_os(left(btrim(v_ref), 80), p_hoje, false);
    if v_ro ->> 'status' = 'ambiguo' then
      return null;
    end if;
    if v_ro ->> 'status' in ('ok', 'fora_da_carteira') and not ((v_ro ->> 'id')::uuid = any (v_ids)) then
      v_ids := v_ids || (v_ro ->> 'id')::uuid;
    end if;
  end loop;
  if cardinality(v_ids) <> 1 then
    return null;
  end if;
  v_os := v_ids[1];
  -- uma carona por OS a cada carona_por_os_dias
  if exists (select 1 from public.agenda_perguntas x
              where (x.service_order_id = v_os or v_os = any (x.os_ids))
                and x.carona_em is not null and x.carona_em >= p_agora - make_interval(days => cf.carona_por_os_dias)) then
    return null;
  end if;
  select x.* into q from public.agenda_perguntas x
   where x.estado = 'aberta' and x.modo = 'ligado' and (x.service_order_id = v_os or v_os = any (x.os_ids))
     and (x.expira_em is null or x.expira_em > p_agora)
     and (x.critica or x.tipo in ('chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'concluir', 'entrega', 'diaria_ligar'))
   order by x.critica desc, x.perda_em nulls last, x.id
   limit 1;
  -- FASE 4: (P3) sem pergunta das Fases 2–3 da OS, a do material dela (a nota, o Pix, a mensagem do fornecedor), a que
  -- perde primeiro. A da nota pode citar mais de uma OS (os_ids): vai de carona em qualquer uma.
  if q.id is null then
    select x.* into q from public.agenda_perguntas x
     where x.estado = 'aberta' and x.modo = 'ligado' and (x.service_order_id = v_os or v_os = any (x.os_ids))
       and (x.expira_em is null or x.expira_em > p_agora)
       and x.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor')
     order by x.perda_em nulls last, x.criada_em, x.id
     limit 1;
  end if;
  -- FASE 4: fim
  if q.id is null then
    return null;
  end if;
  -- a que já saiu hoje no fechamento não vai de novo
  if q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje then
    return null;
  end if;
  update public.agenda_perguntas
     set carona_em = p_agora, mostrada_vezes = least(mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = 'conversa'
   where id = q.id;
  return jsonb_build_object('pergunta_id', q.id, 'os', v_os, 'tipo', q.tipo, 'texto', 'Aproveitando: ' || q.texto);
end;
$function$;

comment on function public.agenda_carona(uuid, text[], text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P6): a carona — no fim de uma resposta do assistente ao DONO (admin ativo) sobre UMA OS (p_os = as OS como o turno citou: número, nome ou id, resolvidas por agenda_resolver_os; ambígua ou mais de uma = null), uma pergunta aberta em ligado dela (crítica primeiro, depois a de perda_em mais cedo; tipos chegou, parada, estouro, duracao, material_conferir, concluir, entrega, diaria_ligar ou crítica; Fase 4, P3: sem nenhuma dessas, a do material — nfe_vincular, pix_material, previsao_fornecedor —, a de perda_em mais cedo), nunca de novo se alguma pergunta da OS teve carona nos últimos carona_por_os_dias, nem a que já saiu hoje no fechamento; só com modo_vigia ligado. Marca carona_em, mostrada_vezes + 1 e mostrada_via conversa. {pergunta_id, os, tipo, texto: "Aproveitando: <a pergunta>"} ou null. Só service_role.';


-- ── 14. O que a agenda mudou sozinha: a ação do material ────────────────────────────────────────────────
-- Corpo de 20261026100500 copiado; a mudança está marcada "-- FASE 4:" (só acréscimo).


create or replace function public._agenda_mudancas(p_de date, p_ate date, p_executada boolean, p_fechamento boolean,
                                                   p_agora timestamptz default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  b as (
    -- FASE 3 (revisão, item 5): o texto gravado noutro dia diz a data no lugar de "vence hoje" (p_ate é o hoje de quem lê:
    -- o foco mudancas, o fechamento e a tela passam p_hoje).
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           public._agenda_vence_no_dia(a.texto, a.dia, p_ate) as texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo not in ('resultado', 'desfazer', 'fixar')
       and (a.origem in ('motor', 'vigia') or (not p_fechamento and a.origem = 'conferencia'))
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 4: (P3) o material que a agenda registrou sozinha — a chegada pela nota importada (origem nota; P4: a previsão
    -- pela mensagem do fornecedor, origem fornecedor) — entra como as ações do motor e da vigia.
    union all
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           public._agenda_vence_no_dia(a.texto, a.dia, p_ate) as texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo = 'material' and a.origem in ('nota', 'fornecedor')
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 4: fim
  ),
  dono as (
    select b.*, coalesce(case when b.tipo = 'publicar' then 'p:' || b.proposta_id end, 'a:' || b.id) as grupo, false as junto
      from b where b.tipo <> 'status'
  ),
  st as (
    -- FASE 3: a mesma ordem (criada_em, OS, id) para achar o grupo
    select s.*, coalesce((select d.grupo from dono d where d.os = s.os and d.dia = s.dia order by d.em, d.os, d.id limit 1),
                         'a:' || s.id) as grupo
      from b s where s.tipo = 'status'
  ),
  todos as (
    select d.* from dono d
    union all
    select s.id, s.tipo, s.os, s.dia, s.proposta_id, s.texto, s.em, s.desfazivel, s.desfeita, s.nome, s.numero, s.grupo,
           s.grupo <> 'a:' || s.id
      from st s
  ),
  g as (
    -- FASE 3: dentro do grupo, a ordem de gravação é criada_em, OS, id (o que entra na mesma transação tem o mesmo
    -- criada_em e o id é aleatório: o G10 de agenda_fase2_leituras.sql falhava cerca de 1 vez em 15)
    select t.grupo,
           case when t.grupo like 'p:%' then 'publicacao' else 'acao' end as tipo,
           min(t.proposta_id::text) filter (where t.tipo = 'publicar') as proposta_id,
           jsonb_agg(t.id order by t.em, t.os nulls last, t.id) as acao_ids,
           coalesce(jsonb_agg(t.texto order by t.em, t.os nulls last, t.id) filter (where not t.junto), '[]'::jsonb) as itens,
           min(t.os::text) filter (where not t.junto) as os,
           min(t.nome) filter (where not t.junto) as nome,
           min(t.numero) filter (where not t.junto) as numero,
           coalesce(bool_or(t.desfazivel) filter (where not t.junto), false) as desfazivel,
           coalesce(bool_and(t.desfeita) filter (where not t.junto), false) as desfeita,
           min(t.em) as em, min(t.os::text) as desempate_os, min(t.id::text) as desempate
      from todos t
     group by t.grupo
  )
  select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'tipo', g.tipo, 'proposta_id', g.proposta_id,
                                               'acao_ids', g.acao_ids, 'itens', g.itens, 'os', g.os, 'nome', g.nome,
                                               'numero', g.numero, 'desfazivel', g.desfazivel, 'desfeita', g.desfeita,
                                               'em', g.em)
                            -- FASE 3: entre os grupos, a mesma ordem (criada_em, OS, id)
                            order by g.em, g.desempate_os nulls last, g.desempate), '[]'::jsonb)
    from g;
$function$;

comment on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a ordem de gravação criada_em, OS, id): o que a agenda mudou sozinha (motor e vigia; fora do fechamento também o replano da conferência) com agenda_acoes.dia em [p_de, p_ate], em grupos — a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela. Fase 4, P3: também a ação material da nota importada e da mensagem do fornecedor (origens nota e fornecedor). p_executada false = o que a sombra teria feito; p_fechamento = só o não contado e não desfeito, só motor e vigia. [{grupo, tipo, proposta_id, acao_ids, itens, os, nome, numero, desfazivel, desfeita, em}].';


-- ── 15. Portas ──────────────────────────────────────────────────────────────────────────────────────────
-- A RPC do material (a ferramenta material_informar; confere o cargo por _autor_da_agenda): o painel e o WhatsApp. A
-- assinatura de 11 argumentos saiu (drop acima); a nova tem os grants de novo.
revoke all on function
  public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date, text)
  from public, anon;
grant execute on function
  public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date, text)
  to authenticated, service_role;

-- As escritas e os passos (a remessa do e-mail, os passos notas e pix, a pergunta, o *grava* do aviso e da linha) e as
-- leituras internas: só service_role. Nunca anon, nunca authenticated (o técnico não lê a fila financeira).
revoke all on function
  public.material_remessas_do_email(uuid, date), public._agenda_material_notas(date, timestamptz),
  public._agenda_material_pix(date, timestamptz),
  public._agenda_material_perguntar(text, text, uuid, uuid[], uuid, date, text, jsonb, timestamptz, boolean),
  public._agenda_aplicar_aviso(uuid, jsonb, text, text, date), public._agenda_aplicar_material(uuid, uuid, jsonb, text, date),
  public._agenda_resolver_aviso(text, uuid, text), public._agenda_pix_fonte(text, uuid),
  public._agenda_material_em_falta(date), public._agenda_rascunho_frase(text, jsonb)
  from public, anon, authenticated;
grant execute on function
  public.material_remessas_do_email(uuid, date), public._agenda_material_notas(date, timestamptz),
  public._agenda_material_pix(date, timestamptz),
  public._agenda_material_perguntar(text, text, uuid, uuid[], uuid, date, text, jsonb, timestamptz, boolean),
  public._agenda_aplicar_aviso(uuid, jsonb, text, text, date), public._agenda_aplicar_material(uuid, uuid, jsonb, text, date),
  public._agenda_resolver_aviso(text, uuid, text), public._agenda_pix_fonte(text, uuid),
  public._agenda_material_em_falta(date), public._agenda_rascunho_frase(text, jsonb)
  to service_role;

-- As leituras e os textos (invoker, STABLE) que as leituras do P6 também usam: authenticated (o painel, com a RLS de quem
-- lê) e service_role; nunca anon.
revoke all on function
  public._agenda_material_modo(), public._agenda_fornecedor_curto(uuid), public._agenda_remessa_quem(uuid, text, text),
  public._agenda_remessa_nota(uuid), public._agenda_inicio_previsto(uuid, date)
  from public, anon;
grant execute on function
  public._agenda_material_modo(), public._agenda_fornecedor_curto(uuid), public._agenda_remessa_quem(uuid, text, text),
  public._agenda_remessa_nota(uuid), public._agenda_inicio_previsto(uuid, date)
  to authenticated, service_role;

-- O que mudou (leitura, invoker): como estava — authenticated (o painel) e service_role; nunca anon.
revoke all on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) from public, anon;
grant execute on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) to authenticated, service_role;

-- O *grava* e a carona: como estavam (create or replace mantém; reafirmados para a migration valer sozinha).
revoke all on function public.agenda_rascunho_gravar(uuid, date) from public, anon;
grant execute on function public.agenda_rascunho_gravar(uuid, date) to authenticated, service_role;
revoke all on function public.agenda_carona(uuid, text[], text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_carona(uuid, text[], text, date, timestamptz) to service_role;
