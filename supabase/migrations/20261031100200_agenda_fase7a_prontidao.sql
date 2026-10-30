-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P3: a prontidão, o material e a classe pelas regras do
-- gestor — a peça barata não segura a data, a peça sem fornecedor ganha um prazo, a compra a fazer não tira a OS do compromisso,
-- a OS sem peça e a peça embutida contam como "sem peça" (dito ao dono), a estimativa do orçamento vale como dias firmes e a OS
-- começada, grande, com peça junto ou sem mão de obra espera a pergunta do gestor.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §3.1, §5.3, §6.4); nomes: fase7-registro.md §1 e §2; respostas do dono:
-- fase7-padroes.md (D7-1 marca firme pela estimativa; D7-2 peça sem compra não tira a OS da agenda; AG7-05 só peça >= R$ 300
-- segura a data; AG7-06 peça sem fornecedor: 7 dias úteis; AG7-07 compra interna 1 dia útil; AG7-11 quanto falta).
-- Depende da 20261031100100 (7a P2: a duração, a estimativa e a situação) e da 20261031100000 (7a P1: o portão e os parâmetros).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (4 funções recriadas; nenhuma nova; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p3/montar-migration.mjs: as recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* do P1 e
-- do P2): os_prontidao e _agenda_rodada_marca de 20261030100400 (o lote P5; a spec dizia 20261029100900, que o lote recriou),
-- _agenda_classe_da_os de 20261025100200 (a única) e agenda_propor de 20261030100200 (o lote P3). As mudanças estão só nos
-- blocos "-- FASE 7: … -- FASE 7: fim"; fora deles nenhuma linha muda (o P9 de supabase/tests/agenda_fase7a_prontidao.sql
-- confere). A _agenda_rodada_marca (a marca da memória da vigia) é a exceção: uma função de uma instrução só, reescrita inteira
-- com o corpo de antes dentro do ramo de sempre (o P9 confere que ele está lá, letra a letra).
--
-- POR QUE: com a equipe de hoje (um técnico) e os dados de produção, quase nada cabe firme: todo item do orçamento é crítico
-- (o sincronizador marcou crítico tudo o que veio do orçamento em 28/10, NOVO-agenda-49), a peça sem fornecedor trava a OS de
-- vez ("de quem e quando?"), a peça a comprar manda a OS para reserva, a OS sem nenhuma peça espera o "tem peça a comprar?" e a
-- duração sem os dias ditos é só reserva. O gestor (D7-1, D7-2) marca firme com o que dá para supor e diz a suposição ao dono.
--
-- O QUE MUDA (tudo atrás do portão _agenda_gestor_regra; com o portão falso, a saída de cada função recriada é a de antes, byte a
-- byte — o P8 do teste confere com as definições de antes rodadas como pg_temp):
--   1. os_prontidao (recriada), as regras do material e da duração:
--      · critico_por_valor (AG7-05): sem o fato do dono (fonte dono/fornecedor/nfe/pix), o item é crítico só com o valor
--        unitário de VENDA >= critico_valor_min (R$ 300; peça: unit_sale_snapshot, texto livre: unit_price_snapshot, OC:
--        unit_cost; sem valor, ou zerado, = crítico). O item ganha separar_vespera (o miúdo) e valor_unit. Na carteira de
--        29/10, 4 das 19 linhas viram "separar na véspera" (porta-fusível do Vanderlei, voltímetro do Giancarlo, conector do
--        Rodrigo, Sikaflex do Robson).
--      · prazo_padrao (AG7-06): sem dias úteis nem corridos do fornecedor, prazo_sem_fornecedor_du (7), classe 'padrao', nível D
--        ("sem fornecedor: contei 7 dias úteis"). O comprado sem previsão ganha a chegada pelo dia da compra: o compressor do
--        Flávio (pedido em 13/10) "venceu em 22/10: chegou?", como antes.
--      · compra_firme (AG7-07): a chegada "se comprar" conta o tempo interno (compra_interna_du, 1 dia útil) e o "compre até"
--        também; com o "compre até" GRAVADO pelo gestor (os_material.compre_ate, o P10) e a OS com compromisso, vale o gravado e
--        a data não anda enquanto ele não vence. O item em falta com "compre até" (ou com a compra combinada de data conhecida)
--        e abaixo de compre_ate_empurroes_max empurrões ganha compra_firme: true.
--      · sem_peca: a OS sem nenhuma linha de material (e sem peça embutida em aberto) conta como "sem peça a comprar" (suposto):
--        a restrição sem_peca_suposta, que não trava, no lugar de "tem peça a comprar?".
--      · embutida_suposta: "tem peça embutida em …? Contei que não; se tiver, me diga" — não trava e não deixa o material "não
--        conferido".
--      · estimativa (D7-1): sem os dias ditos e com a estimativa em uso (_agenda_gestor_estimativa), a duração é a fonte
--        'orcamento' ("6 dias, 1 pessoa (estimativa minha, pelo valor do orçamento)") e a restrição "quantos dias?" não nasce;
--        quando o gestor pergunta antes (situacao, grande, embutida, sem_base), ela diz o que ele faz sem resposta. Os dias
--        'orcamento' gravados (a pergunta vencida, P4) dizem "(estimativa minha)" e não "(você disse)".
--      · situacao (AG7-11): a OS começada ou parada ganha a restrição situacao, que trava (o texto de _agenda_os_situacao).
--   2. _agenda_classe_da_os (recriada): a situação pendente → classe 4 situacao (também na OS em andamento sem plano e sem os
--      dias: o "quanto falta?" vem antes de marcar); a estimativa que o gestor não usa sozinho (grande, embutida, sem_base) →
--      classe 4 estimativa; o item compra_firme não entra na condição compra (a OS fica no compromisso e a compra é cobrada).
--   3. agenda_propor (recriada): o item de compromisso com a fonte 'orcamento' termina "(estimativa minha: 6 dias)."; as
--      críticas novas do P8 (dia_avisado, dia_prometido) já têm a recomendação delas (inertes até lá).
--   4. _agenda_rodada_marca (recriada; a memória da vigia, lote P5): a prontidão passa a ler, pela situação da OS, a última ação
--      da agenda e a pergunta aberta (agenda_acoes e agenda_perguntas, duas das 5 tabelas que a marca não contava). Com a regra
--      situacao, a marca conta também essas duas (num número negativo, que nunca coincide com o de sempre); sem ela, é a de
--      antes. Assim a prontidão lembrada continua certa (o G de agenda_correcao_2910_p5.sql e o P10 do teste novo provam).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_prontidao.sql; registradas em notas-fase77a.md, P3):
--   · Os textos da prontidão não dizem a hora do prazo ("até sex 30/10 18:00"): o prazo é da pergunta do P4 (agenda_perguntas)
--     e a conta da prontidão não a lê (a memória da vigia; ver o item 4). O texto diz o que o gestor faz sem resposta.
--   · A OS em andamento sem plano nem dias (classe 1) também espera o "quanto falta?" (a spec, §3.3 d6), e não só a da classe 2.
--   · A OS sem nenhuma linha de material e com a peça embutida suposta (as duas regras) também conta como "sem peça": senão ela
--     ficaria só na reserva depois de o prazo da pergunta vencer.
--   · compra_firme vale também para a compra combinada pelo dono com data de chegada conhecida (sem "compre até"): é mais firme
--     que a compra por fazer.
--   · O prazo padrão de um fornecedor conhecido sem cidade diz "sem o prazo de <fornecedor>: contei 7 dias úteis" ("sem
--     fornecedor" seria falso).
--   · O valor unitário zerado conta como sem valor (crítico): o custo de OC está zerado em linhas reais (NOVO-agenda-49), e
--     "R$ 0" não é peça miúda.
--   · Com o tempo interno, o item diz "se comprar até sex 30/10, chega por volta de qua 11/11" (e não "se comprar hoje", que
--     daria a outra data); a restrição "comprando hoje, … chega por volta de ter 10/11" continua a conta de quem compra hoje.
--   · O texto do gestor ("perguntei …; sem resposta, …") e a restrição situacao não aparecem quando o orçamento, o cliente ou
--     o escopo seguram a OS antes (a Kalmar, com check-in em junho, espera o cliente): ali o gestor não pergunta nem marca.
--
-- CUSTO (bancada, a carteira de 29/10 com a sintética, 28 OS): com o portão falso, nada (a prontidão 9,8 × 9,7 ms por OS, a
-- vigia de qui 17:00 512 × 557 ms — ruído). Com tudo ligado, a prontidão 11,3 → 19,3 ms por OS (a estimativa do P2 refaz a
-- duração e a situação) e a vigia 1.045 → 1.391 ms. Produção leva ~3,4 vezes a bancada (lote P5): medir a vigia antes do ligar.
--
-- O QUE NÃO MUDA: nenhuma tabela, coluna, lista fechada, dado, cron, tela ou função de borda. Com o portão falso (a linha de
-- agenda_config nasce com modo_marcar_sozinho = 'desligado'; em sombra, só dentro da simulação), nada muda para ninguém.
--
-- ORDEM DE LIGAR: depois de 20261031100100 (P2); antes de 20261031100300 (P4), que pergunta pelos motivos da classe 4 daqui.
-- Aplicar sozinha não muda nada (o portão é falso até o *ligar* do roteiro da §10 da spec).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7a_prontidao.sql (begin/rollback; P0 a P10). Na bancada:
-- node scripts/bancada-agenda/rodar.mjs --ate 20261031100200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100200_agenda_fase7a_prontidao.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100200', 'agenda_fase7a_prontidao');"
--
-- DESFAZER: sem migration, o portão (spec §10: *gestor, só propor*, ou modo_marcar_sozinho fora de 'ligado', ou a regra fora de
-- marcar_regras): com ele falso, a saída é a de antes. Para tirar o código: recriar os_prontidao e _agenda_rodada_marca com o
-- corpo de 20261030100400, _agenda_classe_da_os com o de 20261025100200 e agenda_propor com o de 20261030100200 (a cópia sem os
-- blocos "-- FASE 7:").
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7:") ──────────────────────────
-- Fora dos blocos nenhuma linha muda (o P9 de supabase/tests/agenda_fase7a_prontidao.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration (fase7-registro.md §2: os_prontidao no 7e P6; _agenda_classe_da_os no 7a P12;
-- agenda_propor no 7b P4).

-- os_prontidao (de 20261030100400_agenda_correcao_desempenho.sql)
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
  -- FASE 2: o que o plano publicado diz da OS (spec-fase2 §6.1)
  v_plano      jsonb;
  v_ult_evid   date;
  v_tem_futuro boolean := false;
  -- FASE 2: fim
  -- CORREÇÃO FASE 6: (C1) item 1: o início pelo material pelo dia DITO (o que julga o que já está publicado)
  v_dpm_dito    date;
  v_inicio_dito date;
  -- CORREÇÃO FASE 6: fim
  -- CORREÇÃO 29/10 (P5): a memória da rodada da vigia
  v_memo        jsonb;
  v_marca       bigint;
  -- CORREÇÃO 29/10 (P5): fim
  -- FASE 7: (7a P3) as regras do gestor da agenda na prontidão: os portões do material lidos uma vez, a OS com compromisso (o
  -- "compre até" gravado), o "sem peça" e a peça embutida supostos e a estimativa do gestor (sem portão nenhum, nada disto é
  -- usado e a saída é a de antes, byte a byte)
  v_f7_valor    boolean := false;
  v_f7_padrao   boolean := false;
  v_f7_firme    boolean := false;
  v_f7_comp     boolean := false;
  v_f7_sem_peca boolean := false;
  v_f7_embut    boolean := false;
  v_f7_est      jsonb;
  v_f7_mot      text;
  v_f7_sit      jsonb;
  v_f7_txt      text;
  -- (o laço dos itens)
  v_f7_novos    jsonb;
  v_f7_i        jsonb;
  v_f7_m        public.os_material%rowtype;
  v_f7_sit_i    text;
  v_f7_prazo    int;
  v_f7_corr     int;
  v_f7_prev     date;
  v_f7_inf      boolean;
  v_f7_vu       numeric;
  v_f7_pad      boolean;
  v_f7_fok      boolean;
  v_f7_ep       int;
  v_f7_int      int;
  v_f7_grav     boolean;
  v_f7_data     date;
  v_f7_compre   date;
  v_f7_req      numeric;
  v_f7_nm       numeric;
  -- FASE 7: fim
begin
  if p_hoje is null then
    raise exception 'os_prontidao: sem o dia de hoje' using errcode = '22004';
  end if;
  -- CORREÇÃO 29/10 (P5): dentro da rodada da vigia (agenda.rodada = o dia dela, posto por agenda_vigiar), a prontidão de
  -- cada OS é calculada UMA vez e lembrada enquanto a transação não gravar nada no que ela lê (_agenda_rodada_marca).
  -- Antes, a mesma OS era recalculada em cada passo (limpeza, material, chegou, parada, duração, fila...): ~37 contas por
  -- rodada para 11 OS. O cálculo é o de sempre (a chamada de dentro, com a memória em pausa); fora da rodada, nada muda.
  if p_so_id is not null and current_setting('agenda.rodada', true) = p_hoje::text then
    v_memo := public._agenda_rodada_lembrar(p_so_id);
    if v_memo is null then
      v_marca := public._agenda_rodada_marca();
      perform set_config('agenda.rodada', 'calculando', true);
      v_memo := public.os_prontidao(p_so_id, p_hoje);
      perform set_config('agenda.rodada', p_hoje::text, true);
      perform public._agenda_rodada_guardar(p_so_id, v_marca, v_memo);
    end if;
    return v_memo;
  end if;
  -- CORREÇÃO 29/10 (P5): fim

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
  -- FASE 7: (7a P3) os portões do material (D7-2: o dado que falta não tira a OS da agenda): critico_por_valor (AG7-05: só o
  -- item de valor unitário >= critico_valor_min segura a data), prazo_padrao (AG7-06: sem o prazo do fornecedor, contei
  -- prazo_sem_fornecedor_du dias úteis) e compra_firme (AG7-07: a compra conta o tempo interno, compra_interna_du, e a falta com
  -- "compre até" não tira a OS do compromisso). O "compre até" GRAVADO pelo gestor (os_material.compre_ate, P10) só vale para a
  -- OS com compromisso de hoje em diante: enquanto ele não vence, a data do item não anda (o publicado não desliza).
  v_f7_valor := public._agenda_gestor_regra('critico_por_valor');
  v_f7_padrao := public._agenda_gestor_regra('prazo_padrao');
  v_f7_firme := public._agenda_gestor_regra('compra_firme');
  if v_f7_firme then
    v_f7_comp := exists (select 1 from public.agenda_alocacoes a
                          where a.service_order_id = p_so_id and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
                            and a.dia >= p_hoje);
  end if;
  -- FASE 7: fim

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
       -- FASE 4: a linha ligada a um item de texto livre da conta já está nele, no grupo 1 (os_necessidade_bruta, P2).
       and not exists (select 1 from bruto b where b.origin = 'free_text' and b.src = poi.service_order_service_id)
       -- FASE 4: fim
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
                    -- FASE 4: o item de texto livre é coberto pela linha da OC ligada a ele (service_order_service_id, P2).
                    when q.origem = 'texto_livre' then v.service_order_service_id = q.vinculo
                    -- FASE 4: fim
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
    -- FASE 4: o prazo do fornecedor numa fonte só (_agenda_prazo_do_fornecedor: o que o dono disse, o cadastro repetido,
    -- o nome e a cidade/UF tolerante ao caractere quebrado); a classe, os dias úteis e os corridos saem dele no passo 7.
    select q.*, public._agenda_prazo_do_fornecedor(q.forn_id) as pf
    -- FASE 4: fim
      from passo5 q
    -- CORREÇÃO 29/10 (P5): o prazo do fornecedor uma vez por item. Sem esta barreira o planejador desmanchava o passo 6 nos de
    -- cima e copiava a chamada para cada uso de pf (a classe, os dias úteis, os corridos, o texto, a dúvida): ~25 contas de
    -- _agenda_prazo_do_fornecedor por item (~6 ms cada em produção). O resultado é o mesmo, byte a byte.
    offset 0
    -- CORREÇÃO 29/10 (P5): fim
  ),
  passo7 as (
    -- FASE 4: a classe e os dias úteis do fornecedor; o importado tem os dias corridos (e prazo nulo).
    select q.*, q.pf ->> 'classe' as classe, (q.pf ->> 'du')::int as prazo, (q.pf ->> 'corridos')::int as corridos
    -- FASE 4: fim
      from passo6 q
  ),
  passo8 as (
    select q.*,
           case
             when q.sit = 'na_mao' then 'A'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null and q.prev_fonte <> 'dono' then 'B'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then 'C'
             when q.sit in ('comprado', 'a_caminho') then 'D'
             -- FASE 4: o importado tem prazo (em dias corridos).
             when q.prazo is not null or q.corridos is not null then 'D'
             -- FASE 4: fim
             else 'E' end as nivel,
           case
             when q.sit = 'na_mao' then q.chegou_em
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then q.prev_ate
             -- FASE 4: a chegada pelo prazo do fornecedor (_agenda_chegada_pela_classe: dias úteis; o importado, os dias
             -- corridos levados ao dia útil).
             when q.sit in ('comprado', 'a_caminho') and (q.prazo is not null or q.corridos is not null) then
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos, coalesce(q.comprado_em, p_hoje))
             when q.sit = 'falta' and (q.prazo is not null or q.corridos is not null) then
               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos,
                                                  greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje))
             -- FASE 4: fim
           end as data,
           -- FASE 4: "compre até" pelo mesmo prazo; o importado: o início menos a folga, menos os dias corridos, no último dia
           -- útil até ali (agenda_somar_du(x + 1, -1) é o último dia útil até x).
           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo))
                when q.sit = 'falta' and q.corridos is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(public.agenda_somar_du(v_est_sm, -c.folga_material_du) - q.corridos + 1, -1) end as compre_ate,
           -- FASE 4: fim
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
           -- FASE 4: o texto do prazo do fornecedor ("entrega local, 1 dia útil (pela cidade, chute meu)"), a dúvida do
           -- cadastro (duplicado | sem_lugar) e os dias corridos do importado.
           'prazo_texto', q.pf ->> 'texto', 'duvida', q.pf ->> 'duvida', 'corridos', q.corridos,
           -- FASE 4: fim
           'comprado_em', q.comprado_em, 'compra_prevista_em', q.compra_prevista_em,
           'compre_ate', q.compre_ate,
           'atrasado', q.sit in ('comprado', 'a_caminho') and q.data is not null and q.data < p_hoje,
           'sem_data', q.nivel = 'E' or (q.nivel = 'D' and q.data is null))
           -- FASE 6: (P3) a data provável do material (spec-fase6 §5.3), só no nível B (a previsão de quem vende: OC, nota,
           -- fornecedor, Pix) e só enquanto o dia dito não chegou: data = o dia dito + o atraso medido do fornecedor em uso
           -- (_agenda_aprendido: só com modo_aprendizado ligado e fornecedor na lista); data_dita = o dia dito (o fato). O
           -- atrasado e o sem_data continuam pelo dia dito (a "chegou?" é no dia da previsão); C, A, D e E não mudam. Sem
           -- atraso em uso, o item é o de antes, byte a byte.
           || case when q.nivel = 'B' and q.forn_id is not null and q.data > p_hoje then
                coalesce((select jsonb_build_object(
                            'data', public.agenda_somar_du(q.data, x.du), 'data_dita', q.data,
                            'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                                               then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                                           replace(trim_scale(q.req)::text, '.', ','),
                                                           case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                                           replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                                               else '' end
                                          || format('%s %s; %s costuma atrasar até %s: conto com %s',
                                                    case q.prev_fonte when 'oc' then 'a OC diz' when 'nfe' then 'a nota diz'
                                                                      when 'fornecedor' then 'o fornecedor disse'
                                                                      when 'pix' then 'pelo Pix, chega' else 'a previsão é' end,
                                                    public._dia_curto(q.data),
                                                    coalesce(public._agenda_nome_curto(q.forn_cadastro), 'o fornecedor'),
                                                    public._agenda_aprendizado_valor('fornecedor_atraso', x.du),
                                                    public._dia_curto(public.agenda_somar_du(q.data, x.du))))
                            from (select public._agenda_aprendido('fornecedor_atraso', q.forn_id::text)::int as du) x
                           where x.du > 0), '{}'::jsonb)
              else '{}'::jsonb end
           -- FASE 6: fim
           -- CORREÇÃO FASE 6: (C1) itens 2 e 8 (a contagem dupla e o fornecedor inativo): o bloco da Fase 6 logo acima não vale
           -- mais — as 3 chaves dele saem ("- array[…]" pega só ele: o "-" vem antes do "||") — e vale este, que é ele com duas
           -- mudanças: (item 2) a previsão da nota (nfe) já é "quando sai + quanto leva" (o prazo da classe ou o medido): não
           -- ganha o atraso do fornecedor por cima; (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida:
           -- o cadastro inativo pelo principal). Sem atraso em uso, nada muda: o item é o de antes, byte a byte.
           - array['data', 'data_dita', 'data_texto']
           || case when q.nivel = 'B' and q.forn_id is not null and q.data > p_hoje and q.prev_fonte is distinct from 'nfe' then
                coalesce((select jsonb_build_object(
                            'data', public.agenda_somar_du(q.data, x.du), 'data_dita', q.data,
                            'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                                               then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                                           replace(trim_scale(q.req)::text, '.', ','),
                                                           case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                                           replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                                               else '' end
                                          || format('%s %s; %s costuma atrasar até %s: conto com %s',
                                                    case q.prev_fonte when 'oc' then 'a OC diz' when 'nfe' then 'a nota diz'
                                                                      when 'fornecedor' then 'o fornecedor disse'
                                                                      when 'pix' then 'pelo Pix, chega' else 'a previsão é' end,
                                                    public._dia_curto(q.data),
                                                    coalesce(public._agenda_nome_curto(q.forn_cadastro), 'o fornecedor'),
                                                    public._agenda_aprendizado_valor('fornecedor_atraso', x.du),
                                                    public._dia_curto(public.agenda_somar_du(q.data, x.du))))
                            from (select public._agenda_aprendido('fornecedor_atraso',
                                                                 public._agenda_fornecedor_da_medida(q.forn_id)::text)::int as du) x
                           where x.du > 0), '{}'::jsonb)
              else '{}'::jsonb end
           -- CORREÇÃO FASE 6: fim
           order by q.grupo, q.ord), '[]'::jsonb)
    into v_itens
    from passo8 q;
  -- FASE 7: (7a P3) os itens pelas regras do gestor — um laço sobre os itens já montados, só com alguma das três regras e com
  -- itens (sem elas, nada aqui roda e o material é o de antes, byte a byte; em laço de expressões simples, e não numa consulta,
  -- porque a consulta com a conta por item custava o próprio planejamento a cada OS). Cada item recebe só o que muda:
  --   critico_por_valor (AG7-05): o fato do dono (fonte dono/fornecedor/nfe/pix) vence; sem ele, crítico = o valor unitário de
  --     venda (peça: unit_sale_snapshot; texto livre: unit_price_snapshot; OC: unit_cost; a linha do dono: nenhum) >=
  --     critico_valor_min; sem valor (ou zerado: ninguém preencheu — o custo da OC está zerado em linhas reais) = crítico. O item
  --     ganha separar_vespera (o miúdo: não crítico pela regra) e valor_unit.
  --   prazo_padrao (AG7-06): sem dias úteis nem corridos do fornecedor (sem fornecedor, ou sem cidade/UF no cadastro), o prazo é
  --     prazo_sem_fornecedor_du, a classe 'padrao' e o nível D: a falta ganha a chegada "se comprar" e o "compre até"; o comprado
  --     sem previsão, a chegada pelo dia da compra (passou = atrasado: "chegou?", como antes).
  --   compra_firme (AG7-07): a chegada "se comprar" parte de agenda_somar_du(hoje, compra_interna_du) e o "compre até" desconta
  --     o tempo interno; com o "compre até" gravado (P10) e a OS com compromisso, compre_ate = o gravado e a data = gravado +
  --     interno + prazo enquanto ele não venceu (vencido: comprando hoje). compra_firme: true no item em falta com "compre até"
  --     (ou com a compra combinada de chegada conhecida), abaixo de compre_ate_empurroes_max empurrões (_agenda_classe_da_os não o
  --     põe na condição compra). Com o teto de empurrões o item volta ao que era (reserva).
  if (v_f7_valor or v_f7_padrao or v_f7_firme) and jsonb_array_length(v_itens) > 0 then
    v_f7_novos := '[]'::jsonb;
    for v_f7_i in select t.e from jsonb_array_elements(v_itens) with ordinality t(e, o) order by t.o loop
      v_f7_m := null;
      if v_f7_i ->> 'id' is not null then
        select * into v_f7_m from public.os_material m where m.id = (v_f7_i ->> 'id')::uuid;
      end if;
      v_f7_sit_i := v_f7_i ->> 'situacao';
      v_f7_prazo := (v_f7_i ->> 'prazo_du')::int;
      v_f7_corr := (v_f7_i ->> 'corridos')::int;
      v_f7_prev := (v_f7_i ->> 'compra_prevista_em')::date;
      v_f7_inf := coalesce(v_f7_m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false);
      -- critico_por_valor
      v_f7_vu := null;
      if v_f7_valor and v_f7_i ->> 'origem' = 'peca' then
        select sp.unit_sale_snapshot into v_f7_vu from public.service_order_parts sp where sp.id = (v_f7_i ->> 'linha')::uuid;
      elsif v_f7_valor and v_f7_i ->> 'origem' = 'texto_livre' then
        select ss.unit_price_snapshot into v_f7_vu from public.service_order_services ss where ss.id = (v_f7_i ->> 'linha')::uuid;
      elsif v_f7_valor and v_f7_i ->> 'origem' = 'oc' then
        select pi.unit_cost into v_f7_vu from public.purchase_order_items pi where pi.id = (v_f7_i ->> 'linha')::uuid;
      end if;
      v_f7_vu := nullif(greatest(v_f7_vu, 0), 0);
      if v_f7_valor then
        v_f7_i := v_f7_i || jsonb_build_object(
          'critico', case when v_f7_inf then coalesce(v_f7_m.critico, true) when v_f7_vu is null then true
                          else v_f7_vu >= c.critico_valor_min end,
          'separar_vespera', not v_f7_inf and v_f7_vu is not null and v_f7_vu < c.critico_valor_min,
          'valor_unit', v_f7_vu);
      end if;
      -- prazo_padrao e compra_firme
      v_f7_pad := v_f7_padrao and v_f7_sit_i <> 'na_mao' and v_f7_i ->> 'nivel' in ('D', 'E') and v_f7_prazo is null and v_f7_corr is null;
      v_f7_fok := v_f7_firme and coalesce(v_f7_m.empurrada_vezes, 0) < c.compre_ate_empurroes_max;
      v_f7_ep := coalesce(v_f7_prazo, case when v_f7_pad then c.prazo_sem_fornecedor_du end);
      v_f7_int := case when v_f7_fok then c.compra_interna_du else 0 end;
      v_f7_grav := v_f7_fok and v_f7_comp and v_f7_sit_i = 'falta' and v_f7_prev is null and v_f7_m.compre_ate is not null
                   and v_f7_ep is not null;
      v_f7_data := case
        when v_f7_sit_i = 'falta' and v_f7_grav then
          case when v_f7_m.compre_ate >= p_hoje then public.agenda_somar_du(v_f7_m.compre_ate, v_f7_int + v_f7_ep)
               else public.agenda_somar_du(p_hoje, v_f7_ep) end
        when v_f7_sit_i = 'falta' and (v_f7_ep is not null or v_f7_corr is not null) then
          public._agenda_chegada_pela_classe(case when v_f7_pad then 'padrao' else v_f7_i ->> 'classe' end, v_f7_ep, v_f7_corr,
            case when v_f7_prev is null and v_f7_int > 0 then public.agenda_somar_du(p_hoje, v_f7_int)
                 else greatest(coalesce(v_f7_prev, p_hoje), p_hoje) end)
        when v_f7_sit_i in ('comprado', 'a_caminho') and v_f7_pad then
          public._agenda_chegada_pela_classe('padrao', v_f7_ep, null, coalesce((v_f7_i ->> 'comprado_em')::date, p_hoje)) end;
      v_f7_compre := case when v_f7_sit_i = 'falta' and v_f7_prev is null then
        case when v_f7_grav then v_f7_m.compre_ate
             when v_f7_ep is not null then public.agenda_somar_du(v_est_sm, -(c.folga_material_du + v_f7_ep + v_f7_int))
             when v_f7_corr is not null and v_f7_int > 0 then
               public.agenda_somar_du(public.agenda_somar_du(
                 public.agenda_somar_du(v_est_sm, -c.folga_material_du) - v_f7_corr + 1, -1), -v_f7_int)
             when v_f7_corr is not null then
               public.agenda_somar_du(public.agenda_somar_du(v_est_sm, -c.folga_material_du) - v_f7_corr + 1, -1) end end;
      if v_f7_pad or (v_f7_fok and v_f7_sit_i = 'falta' and v_f7_prev is null and (v_f7_ep is not null or v_f7_corr is not null)
                      and (v_f7_int > 0 or v_f7_grav)) then
        v_f7_req := (v_f7_i ->> 'quantidade')::numeric;
        v_f7_nm := (v_f7_i ->> 'na_mao')::numeric;
        v_f7_i := v_f7_i || jsonb_build_object(
          'nivel', 'D', 'data', v_f7_data, 'compre_ate', v_f7_compre,
          'classe', case when v_f7_pad then 'padrao' else v_f7_i ->> 'classe' end, 'prazo_du', v_f7_ep,
          'prazo_texto', case when not v_f7_pad then v_f7_i ->> 'prazo_texto'
                              when v_f7_i ->> 'fornecedor' is null
                                then 'sem fornecedor: contei ' || public._agenda_plural(c.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis')
                              else format('sem o prazo de %s: contei %s', v_f7_i ->> 'fornecedor',
                                          public._agenda_plural(c.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis')) end,
          'data_texto', case when v_f7_sit_i <> 'na_mao' and v_f7_nm > 0 and v_f7_nm < v_f7_req
                             then format('%s de %s na mão, %s %s: ', replace(trim_scale(v_f7_nm)::text, '.', ','),
                                         replace(trim_scale(v_f7_req)::text, '.', ','),
                                         case when v_f7_req - v_f7_nm = 1 then 'falta' else 'faltam' end,
                                         replace(trim_scale(v_f7_req - v_f7_nm)::text, '.', ','))
                             else '' end
                        || case
                           when v_f7_sit_i in ('comprado', 'a_caminho') then
                             coalesce('pedido em ' || to_char((v_f7_i ->> 'comprado_em')::date, 'DD/MM'), 'comprado')
                             || case when v_f7_data is not null then ', deve chegar por volta de ' || public._dia_curto(v_f7_data)
                                     else ', sem previsão' end
                           when v_f7_prev is not null and v_f7_prev >= p_hoje then
                             format('comprando %s, chega por volta de %s', public._dia_curto(v_f7_prev), public._dia_curto(v_f7_data))
                           when v_f7_grav and v_f7_m.compre_ate >= p_hoje then
                             format('se comprar até %s, chega por volta de %s', public._dia_curto(v_f7_m.compre_ate),
                                    public._dia_curto(v_f7_data))
                           when not v_f7_grav and v_f7_int > 0 and v_f7_sit_i = 'falta' and v_f7_prev is null
                                and (v_f7_ep is not null or v_f7_corr is not null) then
                             format('se comprar até %s, chega por volta de %s',
                                    public._dia_curto(public.agenda_somar_du(p_hoje, v_f7_int)), public._dia_curto(v_f7_data))
                           else 'se comprar hoje, chega por volta de ' || public._dia_curto(v_f7_data) end,
          'atrasado', v_f7_sit_i in ('comprado', 'a_caminho') and v_f7_data is not null and v_f7_data < p_hoje,
          'sem_data', v_f7_data is null);
      end if;
      if v_f7_fok and v_f7_sit_i = 'falta'
         and (v_f7_compre is not null or coalesce(v_f7_prev >= p_hoje and v_f7_data is not null, false)) then
        v_f7_i := v_f7_i || jsonb_build_object('compra_firme', true);
      end if;
      v_f7_novos := v_f7_novos || jsonb_build_array(v_f7_i);
    end loop;
    v_itens := v_f7_novos;
  end if;
  -- FASE 7: fim

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
  -- FASE 7: (7a P3, regras sem_peca e embutida_suposta; D7-2) a OS sem nenhuma linha de material conta como "sem peça a comprar"
  -- (suposto, dito ao dono na restrição sem_peca_suposta, que não trava) — também quando a única dúvida é a peça embutida e a
  -- regra embutida_suposta conta que não tem; e a peça embutida em aberto não deixa o material "não conferido" (a pergunta dela
  -- fica, sem travar: "Contei que não; se tiver, me diga").
  v_f7_sem_peca := v_n_itens = 0 and not v_conferido and public._agenda_gestor_regra('sem_peca')
                   and (jsonb_array_length(v_embut) = 0 or public._agenda_gestor_regra('embutida_suposta'));
  if v_f7_sem_peca then
    v_conferido := true;
  end if;
  v_f7_embut := jsonb_array_length(v_embut) > 0 and public._agenda_gestor_regra('embutida_suposta');
  -- FASE 7: fim

  -- O estado do material (do mais forte ao mais fraco).
  v_mat_estado := case
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'atrasado')::boolean) then 'atrasado'
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'sem_data')::boolean) then 'sem_previsao'
    when jsonb_array_length(v_embut) > 0 or (v_n_itens = 0 and not v_conferido) then 'nao_conferido'
    when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
    else 'completo' end;
  -- FASE 7: (7a P3, regra embutida_suposta) a peça embutida suposta não segura o material: o estado é o que seria sem ela
  if v_f7_embut and v_mat_estado = 'nao_conferido' then
    v_mat_estado := case
      when v_n_itens = 0 and not v_conferido then 'nao_conferido'
      when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
      else 'completo' end;
  end if;
  -- FASE 7: fim

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
    -- CORREÇÃO FASE 6: (C1) item 1: com a data provável em uso (algum crítico com data_dita), o início pelo material também
    -- pelo dia DITO (a chegada que o fornecedor, a OC, a nota ou o Pix disseram + folga_material_du). É por ele que
    -- _agenda_violacoes julga o que já está publicado: a data provável só encaixa o que é novo.
    if exists (select 1 from jsonb_array_elements(v_crit) e where e ? 'data_dita') then
      select max(coalesce(e ->> 'data_dita', e ->> 'data')::date) into v_dpm_dito
        from jsonb_array_elements(v_crit) e
       where e ->> 'nivel' <> 'A';
      v_inicio_dito := case when v_dpm_dito is not null then public.agenda_somar_du(v_dpm_dito, c.folga_material_du) end;
    end if;
    -- CORREÇÃO FASE 6: fim
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
  -- FASE 7: (7a P3, regra estimativa, D7-1) sem os dias ditos, a estimativa do orçamento vale como dias firmes: a duração é a
  -- fonte 'orcamento' com os dias e o rótulo de _agenda_gestor_estimativa ("6 dias, 1 pessoa (estimativa minha, pelo valor do
  -- orçamento)"; a faixa e as diárias da sugestão ficam). Quando o gestor não a usa (situacao, grande, embutida, sem_base), a
  -- duração fica 'sugerida' e as restrições dizem por quê (logo abaixo). Os dias 'orcamento' GRAVADOS (a pergunta com prazo que
  -- venceu, P4) dizem "(estimativa minha)", nunca "(você disse)".
  if public._agenda_gestor_regra('estimativa') then
    if p.dias is null then
      v_f7_est := public._agenda_gestor_estimativa(p_so_id, p_hoje);
      v_f7_mot := v_f7_est ->> 'motivo';
      v_f7_sit := v_f7_est -> 'situacao';
      if coalesce((v_f7_est ->> 'usa')::boolean, false) then
        v_dur := v_dur || jsonb_build_object('fonte', 'orcamento', 'dias', v_f7_est -> 'dias', 'texto', v_f7_est ->> 'texto');
      end if;
    elsif p.estimativa_fonte = 'orcamento' then
      v_dur := v_dur || jsonb_build_object('texto', regexp_replace(v_dur ->> 'texto', ' \(você disse\)$', ' (estimativa minha)'));
    end if;
  end if;
  -- FASE 7: fim

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
  -- FASE 2: (1) a evidência de que a OS andou é a maior entre a última diária ligada, o último meio-dia do plano
  -- cumprido ou parcial e o check-in; (2) com dia no plano de hoje em diante a OS em andamento nunca é parada.
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_tem_futuro := coalesce((v_plano ->> 'proximo_dia')::date >= p_hoje, false);
  v_ult_evid := public._agenda_ultima_evidencia(p_so_id, p_hoje);
  if so.status = 'in_progress' then
    v_parada := (v_ult_evid is null or v_ult_evid < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false
                and not v_tem_futuro;
  end if;
  -- FASE 2: fim

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
  -- FASE 7: (7a P3, regras estimativa e situacao) com a estimativa em uso, "quantos dias?" não nasce (a duração já é a do
  -- orçamento); quando o gestor pergunta antes, a restrição diz o que ele faz sem resposta (o prazo é o da pergunta, P4: a conta
  -- da prontidão não lê a pergunta); a OS começada ou parada (AG7-11) ganha a restrição situacao, que trava (o texto de
  -- _agenda_os_situacao). Com a OS presa antes por orçamento, cliente ou escopo (a Kalmar, com check-in em junho, espera o
  -- cliente), o gestor não pergunta nem marca: nada disso é dito.
  if v_f7_est is not null then
    if coalesce((v_f7_est ->> 'usa')::boolean, false) then
      v_r := (select coalesce(jsonb_agg(e order by o), '[]'::jsonb)
                from jsonb_array_elements(v_r) with ordinality t(e, o) where e ->> 'tipo' <> 'duracao');
    elsif v_f7_mot in ('situacao', 'grande', 'embutida', 'sem_base')
          and not exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'cliente', 'escopo')) then
      v_f7_txt := case v_f7_mot
        when 'situacao' then
          case when v_f7_sit ->> 'tipo' = 'parada'
                 then format('perguntei se ainda é para fazer o serviço inteiro; sem resposta, conto %s',
                             public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric))
               when coalesce((v_f7_sit ->> 'rastro')::boolean, false)
                 then format('perguntei quanto falta; sem resposta, marco %s para terminar',
                             public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric))
               else format('perguntei se já começou; sem resposta, conto %s', public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric)) end
        when 'grande' then
          format('pelo valor do orçamento são %s diárias, mais de %s: perguntei antes de marcar; sem resposta, marco %s',
                 public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(c.estimativa_max_diarias),
                 public._agenda_dias((v_f7_est ->> 'proposta_dias')::numeric))
        when 'embutida' then
          format('pode ter peça junto em "%s": perguntei antes de marcar; sem resposta, marco %s',
                 v_f7_est #>> '{embutida,0,curto}', public._agenda_dias((v_f7_est ->> 'proposta_dias')::numeric))
        else
          format('o orçamento não tem mão de obra separada: perguntei quantos dias; sem resposta, marco %s',
                 public._agenda_dias((v_f7_est ->> 'proposta_dias')::numeric)) end;
      v_r := (select coalesce(jsonb_agg(case when e ->> 'tipo' = 'duracao' then e || jsonb_build_object('texto', v_f7_txt) else e end
                                        order by o), '[]'::jsonb)
                from jsonb_array_elements(v_r) with ordinality t(e, o));
      if v_f7_mot = 'situacao' then
        v_r := v_r || jsonb_build_object('tipo', 'situacao', 'quem', 'dono', 'bloqueia', true, 'desde', v_f7_sit -> 'desde',
          'compre_ate', null,
          'pergunta', case when v_f7_sit ->> 'tipo' = 'parada' then 'ainda é para fazer o serviço inteiro?'
                           when coalesce((v_f7_sit ->> 'rastro')::boolean, false) then 'quanto falta?'
                           else 'o serviço já começou?' end,
          'texto', v_f7_sit ->> 'texto');
      end if;
    end if;
  end if;
  -- FASE 7: fim
  -- Com peça embutida em aberto, a pergunta dela já é o "tem peça a comprar?" (mais precisa): não repete.
  if v_n_itens = 0 and not v_conferido and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'material_nao_conferido', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', 'tem peça a comprar?', 'texto', 'tem peça a comprar? (o orçamento não tem nenhuma)');
  end if;
  -- FASE 7: (7a P3, regra sem_peca) a OS sem peça a comprar (suposto): dito ao dono, sem travar
  if v_f7_sem_peca and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'sem_peca_suposta', 'quem', 'dono', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null, 'texto', 'marquei sem peça a comprar; se precisar, me diga');
  end if;
  -- FASE 7: fim
  v_n := jsonb_array_length(v_embut);
  if v_n > 0 then
    v_txt := array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' ou ')
             || case when v_n > 2 then format(' (e mais %s)', v_n - 2) else '' end;
    v_r := v_r || jsonb_build_object('tipo', 'peca_embutida', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', format('tem peça embutida em %s?', v_txt),
      'texto', format('tem peça embutida em %s?', v_txt));
  end if;
  -- FASE 7: (7a P3, regra embutida_suposta) a peça embutida em aberto não trava: "Contei que não; se tiver, me diga"
  if v_f7_embut then
    v_r := (select coalesce(jsonb_agg(case when e ->> 'tipo' = 'peca_embutida'
                                           then e || jsonb_build_object('bloqueia', false,
                                                                        'texto', format('tem peça embutida em %s? Contei que não; se tiver, me diga', v_txt))
                                           else e end order by o), '[]'::jsonb)
              from jsonb_array_elements(v_r) with ordinality t(e, o));
  end if;
  -- FASE 7: fim

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
                            -- FASE 4: a chegada "comprando hoje" pelo mesmo prazo do fornecedor (o importado em corridos).
                            public._dia_curto(public._agenda_chegada_pela_classe(v_compra ->> 'classe', (v_compra ->> 'prazo_du')::int,
                                                                                 (v_compra ->> 'corridos')::int, p_hoje)))
                            -- FASE 4: fim
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
  -- FASE 7: (7a P3) as restrições novas do gestor no lugar delas: a situação e o "sem peça" logo depois da duração (a ordem de
  -- cima, com as duas; sem elas, nada muda)
  if exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('situacao', 'sem_peca_suposta')) then
    select coalesce(jsonb_agg(e order by (e ->> 'bloqueia')::boolean desc,
             array_position(array['parada', 'atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                                  'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal', 'cliente',
                                  'duracao', 'situacao', 'sem_peca_suposta', 'bem', 'nao_antes'], e ->> 'tipo'), o), '[]'::jsonb)
      into v_r
      from jsonb_array_elements(v_r) with ordinality t(e, o);
  end if;
  -- FASE 7: fim

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
  -- FASE 2: (3) os estados do plano: fixada e programada vêm depois de em execução/parada e antes de marcada; com a
  -- agenda automática ligada a janela antiga é o espelho do plano, e "marcada" não vale (o estado vem das alocações).
  if v_estado not in ('congelada', 'concluida', 'fora_da_carteira', 'em_execucao', 'parada') then
    if coalesce((v_plano ->> 'fixada')::boolean, false) then
      v_estado := 'fixada';
    elsif v_tem_futuro then
      v_estado := 'programada';
    elsif v_estado = 'marcada' and c.modo_proposta = 'ligado' then
      v_estado := case
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
        when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
        when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
        else 'pronta' end;
    end if;
  end if;
  -- FASE 2: fim

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
  -- FASE 2: o texto dos estados do plano ("marcado de ter 03/11 a qui 05/11", "(fixado)" quando é fixo).
  if v_estado in ('fixada', 'programada') then
    v_estado_txt := case when (v_plano ->> 'proximo_dia') = (v_plano ->> 'ultimo_dia')
                         then 'marcado para ' || public._dia_curto((v_plano ->> 'proximo_dia')::date)
                         else format('marcado de %s a %s', public._dia_curto((v_plano ->> 'proximo_dia')::date),
                                     public._dia_curto((v_plano ->> 'ultimo_dia')::date)) end
                    || case when v_estado = 'fixada' then ' (fixado)' else '' end;
  end if;
  -- FASE 2: fim

  -- FASE 2: (4) a saída ganha o plano (null sem alocação) e a última evidência; ultima_diaria continua.
  return jsonb_build_object('plano', v_plano, 'ultima_evidencia', v_ult_evid) || jsonb_build_object(
  -- FASE 2: fim
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
    -- CORREÇÃO FASE 6: (C1) item 1: a chave material de cima, com inicio_mat_dito quando o dia dito dá outro início (só com
    -- a data provável em uso; sem ela, o material é o de antes, byte a byte). A última chave igual do objeto vale.
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em)
      || case when v_inicio_dito is not null and v_inicio_dito is distinct from v_inicio_mat
              then jsonb_build_object('inicio_mat_dito', v_inicio_dito) else '{}'::jsonb end,
    -- CORREÇÃO FASE 6: fim
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
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P2: a linha de OC recebida ligada a um item de texto livre da conta conta só nele, não de novo como item da OC que já chegou; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira. Fase 6 (P3): no item de nível B, enquanto o dia dito não chegou e com o atraso do fornecedor em uso (fornecedor_atraso: _agenda_aprendido), data = a data provável (o dia dito + o atraso; é ela que move o DPM, o início pelo material e o motor), data_dita = o dia dito (o fato) e data_texto "a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11"; atrasado e sem_data continuam pelo dia dito (a "chegou?"); C, A, D e E não mudam; sem atraso em uso, o item é o de antes. CORREÇÃO FASE 6 (C1): (item 1) material.inicio_mat_dito = o início pelo material pelo dia DITO (sem o atraso do fornecedor), só quando a data provável muda o início — _agenda_violacoes julga por ele o que já está publicado; (item 2) a previsão da nota (nfe) não ganha o atraso do fornecedor (já é saída + prazo); (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida: o inativo pelo principal). Sem atraso em uso, a saída é a de antes, byte a byte. CORREÇÃO 29/10 (P5): (1) o prazo do fornecedor uma vez por item (a barreira no passo 6; antes ~25 contas por item); (2) dentro da rodada da vigia (agenda.rodada), o resultado de cada OS é lembrado (_agenda_rodada_lembrar e _agenda_rodada_guardar), enquanto a transação não grava nada no que ela lê. O resultado é o mesmo, byte a byte. FASE 7 (7a P3), atrás do portão _agenda_gestor_regra (falso = a saída de antes, byte a byte): critico_por_valor (AG7-05) — sem o fato do dono, o item é crítico só com o valor unitário de venda >= critico_valor_min (sem valor = crítico), e ganha separar_vespera e valor_unit; prazo_padrao (AG7-06) — sem prazo do fornecedor, prazo_sem_fornecedor_du dias úteis, classe padrao, nível D ("sem fornecedor: contei 7 dias úteis"; o comprado sem previsão chega pelo dia da compra); compra_firme (AG7-07) — a chegada "se comprar" e o "compre até" contam compra_interna_du; o "compre até" gravado (os_material.compre_ate) da OS com compromisso segura a data enquanto não vence; o item em falta com "compre até" (ou compra combinada com chegada) abaixo de compre_ate_empurroes_max ganha compra_firme; sem_peca — a OS sem linha de material conta como sem peça (restrição sem_peca_suposta, que não trava); embutida_suposta — a peça embutida não trava ("Contei que não; se tiver, me diga") nem deixa o material não conferido; estimativa (D7-1) — sem os dias ditos e com _agenda_gestor_estimativa em uso, a duração é a fonte orcamento e a restrição duracao não nasce; sem usar (situacao, grande, embutida, sem_base), a restrição duracao diz o que o gestor faz sem resposta; os dias orcamento gravados dizem "(estimativa minha)"; situacao (AG7-11) — a restrição situacao, que trava (o texto de _agenda_os_situacao).';

-- _agenda_classe_da_os (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public._agenda_classe_da_os(p_pront jsonb, p_meios jsonb, p_hoje date,
                                                       p_tem_fixada boolean default false,
                                                       p_fora_do_horizonte boolean default false)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_est   text := p_pront ->> 'estado';
  v_r     jsonb := coalesce(p_pront -> 'restricoes', '[]'::jsonb);
  v_mat   text := p_pront #>> '{material,estado}';
  v_crit  jsonb;
  v_trava jsonb;
  v_cond  text[] := '{}';
  v_txt   text;
  v_mat_trava boolean;
begin
  if not coalesce((p_pront ->> 'ok')::boolean, false) then
    return jsonb_build_object('classe', 4, 'motivo', 'nao_achei', 'texto', 'não encontrei esse serviço');
  end if;
  if v_est in ('concluida', 'fora_da_carteira') then
    return jsonb_build_object('classe', 4, 'motivo', 'fora_da_carteira', 'texto', p_pront ->> 'estado_texto');
  end if;
  if v_est = 'congelada' then
    return jsonb_build_object('classe', 4, 'motivo', 'congelada', 'texto', p_pront ->> 'estado_texto');
  end if;

  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_crit
    from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
   where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A';

  -- Material que trava de vez (nem reserva): previsão vencida, ou falta sem previsão que não é compra já combinada.
  v_mat_trava := v_mat = 'atrasado'
     or (v_mat = 'sem_previsao' and exists (
           select 1 from jsonb_array_elements(v_crit) e
            where coalesce((e ->> 'sem_data')::boolean, false)
              and not (e ->> 'situacao' = 'falta' and coalesce((e ->> 'compra_prevista_em')::date >= p_hoje, false))));

  -- Em execução (ou com meio-dia fixado): compromisso primeiro, se o material deixa.
  if v_est in ('em_execucao', 'parada') or p_tem_fixada then
    if v_mat_trava then
      select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
       where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
      return jsonb_build_object('classe', 4, 'motivo', 'material',
                                'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: (7a P3, regra situacao; AG7-11, §3.3 d6) a OS em andamento sem os dias ditos e sem plano (situacao_pendente de
    -- agenda_meios_da_os, só com a regra estimativa) também espera o "quanto falta?" antes de entrar no plano: sem isso, o motor
    -- a marcaria com a estimativa inteira (só a sugerida existe)
    if p_meios ->> 'situacao_pendente' = 'true' then
      return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                                'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                    where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: fim
    return jsonb_build_object('classe', 1, 'motivo', case when p_tem_fixada then 'fixada' else 'em_execucao' end,
                              'texto', p_pront ->> 'estado_texto');
  end if;

  -- O que trava antes do material (quem destrava primeiro): orçamento, sinal, cliente, escopo; o bem ou o "não antes de"
  -- além do horizonte; depois o material que trava de vez.
  select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' in ('orcamento', 'sinal', 'cliente', 'escopo') order by o limit 1;
  if v_trava is not null then
    return jsonb_build_object('classe', 4, 'motivo', v_trava ->> 'tipo', 'texto', v_trava ->> 'texto');
  end if;
  if p_fora_do_horizonte then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('bem', 'nao_antes') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'bem', 'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  if v_mat_trava then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'material',
                              'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  -- FASE 7: (7a P3) o que o gestor não marca sem perguntar antes (as chaves de agenda_meios_da_os, que só existem com a regra
  -- estimativa): a OS começada ou parada (situacao_pendente, AG7-11) e a estimativa que ele não usa sozinho — acima de
  -- estimativa_max_diarias, com peça embutida ou sem mão de obra separada (estimativa_motivo, com a fonte ainda 'sugerida').
  -- Antes de "sem base para estimar" (que, sem a regra, continua 'duracao'); o P4 pergunta por estes dois motivos.
  if p_meios ->> 'situacao_pendente' = 'true' then
    return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
  end if;
  if p_meios ->> 'estimativa_motivo' in ('grande', 'embutida', 'sem_base') and p_meios ->> 'fonte' = 'sugerida' then
    return jsonb_build_object('classe', 4, 'motivo', 'estimativa',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'duracao' order by o limit 1),
                                                'quantos dias e com quem? (o orçamento não dá base para estimar)'));
  end if;
  -- FASE 7: fim
  if coalesce((p_meios ->> 'sem_base')::boolean, false) or (p_meios ->> 'total') is null then
    return jsonb_build_object('classe', 4, 'motivo', 'duracao',
                              'texto', 'quantos dias e com quem? (o orçamento não dá base para estimar)');
  end if;

  -- O que só deixa reservar (classe 3), do que mais trava ao que menos.
  if exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta') then
    v_cond := v_cond || 'compra'::text;
  end if;
  -- FASE 7: (7a P3, regra compra_firme; D7-2, AG7-07) a peça a comprar com "compre até" (vivo ou gravado) abaixo do teto de
  -- empurrões não segura a OS na reserva: ela fica no compromisso e a compra é cobrada (o item vem marcado compra_firme pela
  -- os_prontidao). Só sai a condição quando TODA falta de nível D é firme.
  if 'compra' = any (v_cond) and public._agenda_gestor_regra('compra_firme')
     and not exists (select 1 from jsonb_array_elements(v_crit) e
                      where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta'
                        and not coalesce((e ->> 'compra_firme')::boolean, false)) then
    v_cond := array_remove(v_cond, 'compra'::text);
  end if;
  -- FASE 7: fim
  if v_mat = 'sem_previsao'
     or exists (select 1 from jsonb_array_elements(v_crit) e
                 where e ->> 'nivel' = 'D' and e ->> 'situacao' in ('comprado', 'a_caminho')) then
    v_cond := v_cond || 'material'::text;
  end if;
  if v_mat = 'nao_conferido' then
    v_cond := v_cond || 'conferir_material'::text;
  end if;
  if p_meios ->> 'fonte' = 'sugerida' then
    v_cond := v_cond || 'duracao'::text;
  end if;
  if cardinality(v_cond) = 0 then
    return jsonb_build_object('classe', 2, 'motivo', 'pronta', 'texto', p_pront ->> 'estado_texto');
  end if;

  select e ->> 'texto' into v_txt from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' = any (case v_cond[1]
           when 'compra' then array['compre_ate', 'sem_previsao']
           when 'material' then array['compra_sem_prazo', 'comprado_sem_previsao', 'sem_previsao']
           when 'conferir_material' then array['peca_embutida', 'material_nao_conferido']
           else array['duracao'] end)
   order by o limit 1;
  return jsonb_build_object('classe', 3, 'motivo', v_cond[1], 'condicao_tipo', v_cond[1], 'condicoes', to_jsonb(v_cond),
                            'texto', coalesce(v_txt, p_pront ->> 'estado_texto'));
end;
$function$;

comment on function public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean) is
  'Agenda de Produção (Fase 2, P2): a classe da OS para o motor, pelas restrições de os_prontidao e o molde de agenda_meios_da_os — 1 = em execução/parada ou com meio-dia fixado (compromisso, primeiro); 2 = pronta: dias ditos ou aceitos, sem orçamento/sinal/cliente/escopo travando e todo crítico em A, B ou C (compromisso); 3 = o que falta é só compra (D falta, o "compre até"), material comprado sem previsão ou compra combinada sem prazo, conferir o material (zero linhas ou peça embutida) ou dias só sugeridos (só reserva condicionada; condicao_tipo na ordem compra > material > conferir_material > duracao); 4 = nunca: fora da carteira, em espera, material atrasado ou sem previsão, orçamento, sinal, cliente, escopo, o bem ou o "não antes de" além do horizonte, sem base para os dias. {classe, motivo, texto (quem trava), condicao_tipo}. FASE 7 (7a P3), com as chaves de agenda_meios_da_os que só existem com a regra estimativa: a OS começada ou parada (situacao_pendente; também a em andamento sem plano nem dias) = classe 4 situacao; a estimativa que o gestor não usa sozinho (estimativa_motivo grande, embutida ou sem_base, com a fonte sugerida) = classe 4 estimativa, antes do "sem base" (que sem a regra continua duracao); com a regra compra_firme, a falta de nível D com compra_firme (os_prontidao) não entra na condição compra (a OS fica no compromisso). Sem o portão, a de antes.';

-- agenda_propor (de 20261030100200_agenda_correcao_motor.sql)
create or replace function public.agenda_propor(
  p_escopo     text,
  p_de         date        default null,
  p_ate        date        default null,
  p_os         uuid[]      default null,
  p_restricoes jsonb       default '{}'::jsonb,
  p_persistir  boolean     default false,
  p_origem     text        default 'motor',
  p_autor      uuid        default null,
  p_hoje       date        default public._hoje_brt(),
  p_agora      timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  -- Os pesos da pontuação (plano §4.4, os do Timefold): estrutura para comparar alternativas, não parâmetro do dono.
  c_peso_atraso  constant int := 1000000;
  c_peso_mudanca constant int := 100;
  c_peso_dono    constant int := 10;
  c_peso_interr  constant int := 50;
  c_peso_fim     constant int := 1;
  -- "atrasar" leva a OS para o fim da classe: a ordem dela passa à frente de qualquer posição real da fila.
  c_fim_da_classe constant int := 1000000;
  -- quantas OS que X empurraria entram na pergunta "não cabe" (as mais próximas dela na fila)
  c_candidatas   constant int := 3;
  cf        public.agenda_config;
  v_r       jsonb := coalesce(p_restricoes, '{}'::jsonb);
  v_modo    text;
  v0        bigint;
  v_cong    date;
  v_seg     date;
  v_de      date;
  v_ate     date;
  v_hor     date;
  v_ini     date;
  v_fim     date;
  v_cart    uuid[];
  v_cartj   jsonb;
  v_escopo  uuid[];
  v_tirar   uuid[];
  v_atrasar uuid[];
  v_aceitar uuid[];
  v_acima   boolean;
  v_decisao uuid;
  v_fixar   jsonb;
  v_depois  jsonb;
  v_info    jsonb := '{}'::jsonb;
  v_canc    jsonb;
  v_ign     uuid[];
  v_fila_os uuid[];
  v_ctx     jsonb;
  v_pes     uuid[];
  v_fila    jsonb := '[]'::jsonb;
  v_ent     jsonb;
  v_par     jsonb;
  v_parh    jsonb;
  v_r0      jsonb;
  v_rf      jsonb;
  v_ctxf    jsonb;
  v_base    jsonb;
  v_sim     jsonb;
  v_minh_n  int;
  v_minh_a  int;
  v_os      uuid;
  v_i       int;
  v_e       jsonb;
  v_b       jsonb;
  v_pront   jsonb;
  v_meios   jsonb;
  v_pl      record;
  v_status  text;
  v_k       record;
  v_cl      jsonb;
  v_classe  int;
  v_fx      jsonb;
  v_fp      int;
  v_evento  boolean;
  v_passos  int;
  v_abre    boolean;
  v_fecha   boolean;
  v_dtm     boolean;
  v_dtt     boolean;
  v_fixa    int;
  v_pm      int[];
  v_pt      int[];
  v_est     date;
  v_estc    date;
  v_minh    int;
  v_bem     int[];
  v_pat_p   int;
  v_pat_b   int[];
  v_bem_tudo boolean;
  v_fora    jsonb := '[]'::jsonb;
  v_crit    jsonb := '{}'::jsonb;
  v_xnc     int[] := '{}';
  v_xoc     int[] := '{}';
  v_cands   jsonb := '{}'::jsonb;
  v_h       int[] := '{}';
  v_sem_q   int[] := '{}';
  v_tentativa int;
  v_usadas  jsonb;
  v_perg    jsonb := '[]'::jsonb;
  v_held    jsonb := '[]'::jsonb;
  v_itens   jsonb := '[]'::jsonb;
  v_opc     jsonb;
  v_rec     int;
  v_rec_txt text;
  v_txt     text;
  v_chave   text;
  v_tipo    text;
  v_fim_x   date;
  v_ini_x   date;
  v_fim_c   date;
  v_ini_c   date;
  v_x       int;
  v_c       int;
  v_cb      jsonb;
  v_xb      jsonb;
  v_canc_os uuid[];
  v_ini_antes date;
  v_fim_dep date;
  v_carga   jsonb;
  v_textos  jsonb;
  v_linhas  text[];
  v_tfora   text[];
  v_titulo  text;
  v_texto   text;
  v_pont    jsonb;
  v_viol    jsonb;
  v_pid     uuid;
  v_expira  timestamptz;
  v_dono    uuid := public._agenda_dono(null);
  v_feriados text[];
  v_q       jsonb;
  v_n       int;
  v_aviso   text;
  -- CORREÇÃO 29/10 (P3): a reserva da própria OS no encaixe do compromisso dela (res_propria) e o resumo que separa o
  -- marcado firme do reservado
  v_rp       int[];
  v_marc     text[];
  v_resv     text[];
  v_contagem text;
  -- CORREÇÃO 29/10 (P3): fim
begin
  -- ── 0. Entrada ──
  if p_escopo is null or p_escopo not in ('semana', 'os', 'replano') then
    raise exception 'Escopo desconhecido: "%" (semana, os ou replano).', coalesce(p_escopo, '') using errcode = '22023';
  end if;
  if p_origem is null or p_origem not in ('motor', 'vigia', 'dono', 'assistente', 'tela', 'aprovacao') then
    raise exception 'Origem desconhecida: "%".', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null or jsonb_typeof(v_r) <> 'object' then
    raise exception 'Faltam o dia, a hora ou as restrições do plano.' using errcode = '22023';
  end if;
  if p_escopo in ('os', 'replano') and coalesce(cardinality(p_os), 0) = 0 then
    raise exception 'Diga de que OS é o plano.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  if p_persistir then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  cf := public._agenda_cfg();
  v_modo := cf.modo_proposta;
  if p_persistir and v_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'simulacao', false, 'texto', 'A agenda automática está desligada: não monto o plano.');
  end if;
  v0 := cf.versao_plano;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- ── 1. A janela ──
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  if p_escopo = 'semana' then
    v_de := coalesce(p_de, public.agenda_somar_du(v_seg + 7, 0));
    v_ate := coalesce(p_ate, v_seg + 7 + 5);
  else
    v_de := coalesce(p_de, public.agenda_somar_du(v_cong, 1));
    v_ate := coalesce(p_ate, v_de + 7 * cf.horizonte_semanas);
  end if;
  if v_ate < v_de then
    raise exception 'O período do plano termina antes de começar (% a %).', v_de, v_ate using errcode = '22023';
  end if;
  v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, v_ate);
  v_ini := v_seg;
  v_fim := v_hor + (7 - extract(isodow from v_hor)::int);

  -- ── Restrições (ids e datas já resolvidos por quem chama) ──
  v_tirar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'tirar', '[]'::jsonb)) x);
  v_atrasar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'atrasar', '[]'::jsonb)) x);
  v_aceitar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'aceitar_atraso', '[]'::jsonb)) x);
  v_acima := coalesce((v_r ->> 'acima_da_carga')::boolean, false);
  v_decisao := nullif(v_r ->> 'decisao', '')::uuid;
  if exists (select 1 from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e
              where e ->> 'os' is null or e ->> 'de' is null) then
    raise exception 'fixar precisa da OS e do dia.' using errcode = '22023';
  end if;
  select coalesce(jsonb_object_agg(e ->> 'os', jsonb_build_object('de', e -> 'de', 'ate', coalesce(e -> 'ate', e -> 'de'),
                                                                  'pessoa', e -> 'pessoa')), '{}'::jsonb)
    into v_fixar from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e;
  select coalesce(jsonb_object_agg(e ->> 'os', e -> 'dia'), '{}'::jsonb)
    into v_depois from jsonb_array_elements(coalesce(v_r -> 'so_depois_de', '[]'::jsonb)) e;

  -- ── 2. A carteira, o escopo e o que se sabe de cada OS ──
  select coalesce(array_agg(k.service_order_id order by k.numero collate "C", k.service_order_id), '{}'::uuid[]),
         coalesce(jsonb_object_agg(k.service_order_id::text, jsonb_build_object('sinal', k.sinal_pago > 0, 'aprovada_em', k.aprovada_em)), '{}'::jsonb)
    into v_cart, v_cartj
    from public.os_carteira(p_hoje) k;
  if p_escopo = 'semana' then
    v_escopo := v_cart;
  else
    v_escopo := array(select distinct x from unnest(p_os) x order by 1);
  end if;
  for v_os in
    select x from (select unnest(v_escopo) as x
                   union
                   select a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                      and p_escopo = 'semana' and not (a.service_order_id = any (v_cart))) q
     order by 1
  loop
    v_info := v_info || jsonb_build_object(v_os::text, jsonb_build_object(
                'pront', public.os_prontidao(v_os, p_hoje), 'meios', public.agenda_meios_da_os(v_os, p_hoje)));
  end loop;

  -- ── 3. Estabilidade: o que não pode mais acontecer sai (e o pedido do dono tira o que a OS tinha) ──
  v_canc := public._agenda_violacoes(v_escopo, v_cart, p_escopo = 'semana', v_info, p_hoje, v_cong);
  v_canc := v_canc || coalesce((
    select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'os', a.service_order_id, 'motivo', 'dono', 'violada', false,
             'congelado', a.dia <= v_cong, 'tipo', a.tipo, 'estado', a.estado, 'fixado_por', a.fixado_por,
             'reserva_de', a.reserva_de, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca)
             order by a.service_order_id, a.dia, a.turno = 'tarde', a.payee_id, a.id)
      from public.agenda_alocacoes a
     where v_fixar ? a.service_order_id::text and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
       and a.resultado is null and lower(a.periodo) > p_agora
       and not exists (select 1 from jsonb_array_elements(v_canc) c where (c ->> 'alocacao_id')::uuid = a.id)), '[]'::jsonb);
  v_ign := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c);

  -- ── 4. A grade e a fila ──
  v_fila_os := array(select x from unnest(v_escopo) x where not (x = any (v_tirar)) order by 1);
  v_ctx := public._agenda_contexto(v_ini, v_fim, p_hoje, v_ign, v_fila_os);
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') x);
  -- o 1º meio-dia que dá: depois do congelado; e, para o evento real e o pedido do dono, o 1º que ainda não começou
  v_minh_n := 2 * (v_cong + 1 - v_ini) + 1;
  v_minh_a := case when lower(public.agenda_periodo(p_hoje, 'manha')) > p_agora then 2 * (p_hoje - v_ini) + 1
                   when lower(public.agenda_periodo(p_hoje, 'tarde')) > p_agora then 2 * (p_hoje - v_ini) + 2
                   else 2 * (p_hoje + 1 - v_ini) + 1 end;

  for v_os in select unnest(v_tirar) loop
    if v_os = any (v_escopo) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'tirado', 'texto', public._agenda_rotulo_da_os(v_os) || ': você tirou.');
    end if;
  end loop;

  for v_i in 1 .. coalesce(cardinality(v_fila_os), 0) loop
    v_os := v_fila_os[v_i];
    v_pront := v_info -> v_os::text -> 'pront';
    v_meios := v_info -> v_os::text -> 'meios';
    select pl.* into v_pl from public.os_planejamento pl where pl.service_order_id = v_os;
    select so.status into v_status from public.service_orders so where so.id = v_os;
    -- o que fica do plano dela (sem o que a proposta cancela)
    select count(distinct (a.dia, a.turno)) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido'), false) as algum,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as ultimo,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as ultimo_fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.estado = 'fixada' and a.dia >= p_hoje and a.resultado is null), false) as fixada,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje), false) as reserva,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de = 'patio' and a.dia >= p_hoje), false) as patio
      into v_k
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and not (a.id = any (v_ign));
    v_bem_tudo := (v_pl.bem_indisponivel is not null and not isempty(v_pl.bem_indisponivel)
                   and not exists (select 1 from generate_series(p_hoje + 1, v_hor, interval '1 day') g
                                    where not (v_pl.bem_indisponivel @> g::date)))
                  or coalesce(v_pl.nao_antes_de > v_hor, false);
    v_cl := public._agenda_classe_da_os(v_pront, v_meios, p_hoje, v_k.fixada, v_bem_tudo);
    v_classe := (v_cl ->> 'classe')::int;
    v_fx := v_fixar -> v_os::text;
    if v_fx is not null then
      if v_classe = 4 then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_cl ->> 'texto', '.')));
        continue;
      end if;
      v_classe := 1;
    end if;
    v_evento := exists (select 1 from jsonb_array_elements(v_canc) c
                         where (c ->> 'os')::uuid = v_os and (c ->> 'violada')::boolean
                           and ((c ->> 'congelado')::boolean or (v_cl ->> 'classe')::int = 1));
    v_passos := case when (v_meios ->> 'total') is null then 0
                     else ceil(greatest((v_meios ->> 'total')::numeric - coalesce((v_meios ->> 'cumpridos')::numeric, 0)
                                        - coalesce(v_k.fut, 0), 0))::int end;
    v_fecha := v_meios ->> 'presenca' = 'abre_e_fecha';
    v_abre := v_fecha and not v_k.algum and coalesce((v_meios ->> 'cumpridos')::numeric, 0) = 0 and v_status <> 'in_progress';
    v_dtm := coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false);
    v_dtt := coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false);
    v_fixa := 0;
    if v_fx is not null and v_fx ->> 'pessoa' is not null then
      v_fp := array_position(v_pes, (v_fx ->> 'pessoa')::uuid);
      if v_fp is null then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: essa pessoa não está na equipe de agora.', public._agenda_rotulo_da_os(v_os)));
        continue;
      elsif v_fp = (v_ctx ->> 'dono')::int then
        v_dtm := true; v_dtt := true; v_abre := false; v_fecha := false;
      else
        v_fixa := v_fp;
      end if;
    end if;
    v_pm := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,manha,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    v_pt := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,tarde,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    -- EST': o dia em que fica pronta, depois do congelado (o evento real e o pedido do dono podem usar o que ainda não
    -- começou), depois do "só depois de" e depois do que ela já tem marcado.
    if v_fx is not null then
      v_est := greatest((v_fx ->> 'de')::date, p_hoje);
      v_minh := v_minh_a;
    elsif v_evento then
      v_est := greatest(coalesce((v_pront #>> '{material,inicio_mat}')::date, p_hoje), v_pl.nao_antes_de, p_hoje,
                        (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_a;
    else
      v_est := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                        public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_n;
    end if;
    v_estc := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                       public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date);
    v_bem := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                    where coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    -- o pátio: o que dá para adiantar sem o bem, enquanto ele está fora (dentro da janela)
    v_pat_p := 0;
    v_pat_b := '{}';
    if v_pl.adiantavel_patio_dias is not null and not v_k.patio and v_classe in (1, 2, 3) and v_passos > 0
       and exists (select 1 from generate_series(greatest(v_de, public.agenda_somar_du(v_cong, 1)), v_ate, interval '1 day') g
                    where coalesce(v_pl.bem_indisponivel @> g::date, false)) then
      v_pat_p := (v_pl.adiantavel_patio_dias * 2)::int;
      v_pat_b := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                        where not coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    end if;
    v_e := jsonb_build_object(
      'i', v_i, 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
      'classe', v_classe, 'motivo', v_cl ->> 'motivo', 'texto', v_cl ->> 'texto', 'condicao_tipo', v_cl ->> 'condicao_tipo',
      'passos', v_passos, 'abre', v_abre, 'fecha', v_fecha, 'dt_m', v_dtm, 'dt_t', v_dtt,
      'dm', coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0), 'dtd', coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
      'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', v_fixa,
      'est', v_est - v_ini + 1, 'est_cond', v_estc - v_ini + 1, 'est_patio', public.agenda_somar_du(v_cong, 1) - v_ini + 1,
      'min_h', v_minh, 'bem', to_jsonb(v_bem), 'patio_passos', v_pat_p, 'patio_bem', to_jsonb(v_pat_b),
      'tem_reserva', v_k.reserva, 'tem_fixada', v_k.fixada, 'evento_real', v_evento, 'teto100', v_fx is not null,
      'dono_impossivel', ((v_dtm or v_dtt) and not coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false))
                         or ((v_abre or v_fecha or v_dtm or v_dtt) and coalesce((v_ctx ->> 'dono')::int, 0) = 0),
      'atrasar', v_os = any (v_atrasar), 'prio', v_pl.prioridade_manual, 'razao', v_pront -> 'razao_critica',
      'sinal', coalesce((v_cartj -> v_os::text ->> 'sinal')::boolean, false), 'aprovada_em', v_pront ->> 'aprovada_em',
      'fonte', v_meios ->> 'fonte', 'dias', v_meios -> 'dias', 'precisa', v_pl.precisa_ate,
      'fim_antes', v_pront #>> '{plano,ultimo_dia}', 'kept_max', v_k.ultimo, 'tipo_os',
      -- o tipo do meio-dia: o motivo da regra d05 (diagnóstico, comissionamento), mesmo quando o dono está na equipe
      case v_meios ->> 'regra_motivo' when 'diagnóstico' then 'diagnostico' when 'comissionamento' then 'comissionamento'
           else 'execucao' end)
      || case when v_fx is not null then jsonb_build_object('fixar_de', greatest((v_fx ->> 'de')::date, p_hoje) - v_ini + 1,
                                                            'fixar_ate', (v_fx ->> 'ate')::date - v_ini + 1)
              else '{}'::jsonb end;
    -- CORREÇÃO 29/10 (P3): a reserva DELA (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira
    -- compromisso" cancela) não conta contra ela mesma no encaixe do compromisso. O encaixe já deixava o compromisso usar a
    -- célula da própria reserva, mas o lugar até 100% da semana (teto100 − compromisso − reserva) contava a reserva dela:
    -- com o teto apertado (o João, 4 de 4 meios-dias na semana, todos na reserva do Lenine) a promoção nunca cabia. Vai na
    -- entrada da fila só quando há: res_propria = a pessoa × semana ((pessoa − 1) × nw + semana, a posição de uso_r no
    -- contexto) de cada meio-dia reservado, uma vez por alocação.
    if v_k.reserva then
      v_rp := array(select (array_position(v_pes, a.payee_id) - 1) * (v_ctx ->> 'nw')::int + (a.dia - v_ini) / 7 + 1
                      from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'
                       and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje and a.dia between v_ini and v_fim
                       and a.presenca = 'turno' and a.payee_id = any (v_pes) and not (a.id = any (v_ign))
                     order by 1);
      if cardinality(v_rp) > 0 then
        v_e := v_e || jsonb_build_object('res_propria', to_jsonb(v_rp));
      end if;
    end if;
    -- CORREÇÃO 29/10 (P3): fim
    v_fila := v_fila || v_e;
  end loop;

  -- A ordem: (classe, atrasar, prioridade do dono, razão crítica, sinal pago, aprovação, número, id).
  select coalesce(jsonb_agg(x.e || jsonb_build_object('ordem', x.rn) order by x.rn), '[]'::jsonb) into v_fila
    from (select e, row_number() over (order by (e ->> 'classe')::int, (e ->> 'atrasar')::boolean, (e ->> 'prio')::int nulls last,
                                                (e ->> 'razao')::numeric nulls last, (e ->> 'sinal')::boolean desc,
                                                (e ->> 'aprovada_em')::date nulls last, e ->> 'numero' collate "C", e ->> 'os') as rn
            from jsonb_array_elements(v_fila) e) x;
  select coalesce(jsonb_object_agg(e ->> 'i', e), '{}'::jsonb) into v_ent from jsonb_array_elements(v_fila) e;

  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', cf.inicios_tentados_du,
                              'semana', p_escopo = 'semana', 'jan_de', v_de - v_ini + 1, 'jan_ate', v_ate - v_ini + 1,
                              'acima', v_acima);
  v_parh := v_par || jsonb_build_object('semana', false);

  -- ── 5. O encaixe e a sobrecarga (o banco nunca escolhe quem atrasa) ──
  for v_tentativa in 1 .. 3 loop
    -- (quem ficou sem saída na volta anterior sai da fila: fica fora, sem encaixe)
    v_r0 := public._agenda_encaixar(v_ctx,
              (select jsonb_agg(case when (e ->> 'i')::int = any (v_sem_q) then e || '{"tirar": true}'::jsonb else e end)
                 from jsonb_array_elements(v_fila) e), v_par);
    -- o que é crítico em cada compromisso colocado
    v_crit := '{}'::jsonb;
    for v_b in select e from jsonb_array_elements(v_r0 -> 'colocadas') e where e ->> 'tipo' = 'compromisso' loop
      v_e := v_ent -> (v_b ->> 'i');
      continue when v_e ? 'fixar_de';
      v_os := (v_e ->> 'os')::uuid;
      v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
      v_fim_x := greatest(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date);
      v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
      v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                       where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os, '{}');
      if v_tipo is not null then
        v_crit := v_crit || jsonb_build_object(v_b ->> 'i', jsonb_build_object('tipo', v_tipo, 'fim', v_fim_x, 'ini', v_ini_x));
      end if;
    end loop;
    -- as críticas ainda sem decisão
    v_xnc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' = 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    v_xoc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' <> 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    -- quem X empurraria: as da classe 2 colocadas antes dela, novas e sem fixado, as mais próximas
    v_cands := '{}'::jsonb;
    foreach v_x in array v_xnc loop
      v_cands := v_cands || jsonb_build_object(v_x::text, coalesce((
        select jsonb_agg(q.i order by q.ordem desc)
          from (select (b ->> 'i')::int as i, (v_ent -> (b ->> 'i') ->> 'ordem')::int as ordem
                  from jsonb_array_elements(v_r0 -> 'colocadas') b
                 where b ->> 'tipo' = 'compromisso'
                   and (v_ent -> (b ->> 'i') ->> 'classe')::int = 2 and not (v_ent -> (b ->> 'i')) ? 'fixar_de'
                   and not (v_ent -> (b ->> 'i') ->> 'tem_fixada')::boolean and v_ent -> (b ->> 'i') ->> 'fim_antes' is null
                   and (v_ent -> (b ->> 'i') ->> 'ordem')::int < (v_ent -> v_x::text ->> 'ordem')::int
                   and not ((b ->> 'i')::int = any (v_xnc || v_xoc))
                   -- (na 2ª volta, só as que deram opção: quem não faz X caber não fica esperando a decisão)
                   and (v_usadas is null or coalesce(v_usadas -> v_x::text, '[]'::jsonb) @> to_jsonb((b ->> 'i')::int))
                 order by 2 desc limit c_candidatas) q), '[]'::jsonb));
    end loop;
    v_h := array(select distinct x from (select unnest(v_xnc || v_xoc) as x
                                          union select (j)::int from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(v) j) u
                  order by 1);
    exit when cardinality(v_h) = 0;

    -- O que é publicado sem esperar sai desta mesma rodada (as reservas foram depois de todos os compromissos, e não
    -- tomam o lugar de quem espera a decisão); quem espera fica como item crítico (X, a que não cabe, sai).
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx,
                (select coalesce(jsonb_agg(b), '[]'::jsonb) from jsonb_array_elements(v_r0 -> 'colocadas') b
                  where not ((b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')));
    -- a decisão vai encontrar a grade já com o resto publicado: as opções são simuladas sobre ela
    v_base := public._agenda_encaixar(v_ctxf,
                (select jsonb_agg(e) from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
    v_perg := '[]'::jsonb;
    v_n := cardinality(v_sem_q);
    foreach v_x in array v_xnc || v_xoc loop
      v_e := v_ent -> v_x::text;
      v_os := (v_e ->> 'os')::uuid;
      v_tipo := v_crit -> v_x::text ->> 'tipo';
      v_xb := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
      v_fim_x := case when v_xb is null then null
                      else greatest(v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date) end;
      v_opc := '[]'::jsonb;
      if v_tipo = 'nao_cabe' then
        if v_fim_x is not null then
          v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x),
                     'sem_data', false, 'atraso_du', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x), 'numero', v_e ->> 'numero',
                     'texto', format('%s atrasa: termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                     public._dia_curto((v_e ->> 'precisa')::date)),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                     'espera', jsonb_build_object(v_os::text, v_fim_x));
        end if;
        for v_c in select (j)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) j loop
          v_sim := public._agenda_encaixar(v_ctxf,
                     (select jsonb_agg(case when (e ->> 'i')::int = v_c
                                            then e || jsonb_build_object('ordem', (e ->> 'ordem')::int + c_fim_da_classe) else e end)
                        from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
          v_xb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
          v_cb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          continue when v_xb is null or v_cb is null
                     or v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1 > (v_e ->> 'precisa')::date;
          v_ini_c := v_ini + ((v_cb ->> 'ini')::int + 1) / 2 - 1;
          v_fim_c := v_ini + ((v_cb ->> 'fim')::int + 1) / 2 - 1;
          v_b := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          v_opc := v_opc || jsonb_build_object('n', jsonb_array_length(v_opc) + 1, 'os', v_ent -> v_c::text -> 'os', 'c', v_c,
                     'atraso_dito', case when v_ent -> v_c::text ->> 'precisa' is null then 0
                                         else greatest(public.agenda_du_entre((v_ent -> v_c::text ->> 'precisa')::date, v_fim_c), 0) end,
                     'sem_data', v_ent -> v_c::text ->> 'precisa' is null,
                     'atraso_du', case when v_b is null then 0
                                       else greatest(public.agenda_du_entre(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, v_fim_c), 0) end,
                     'numero', v_ent -> v_c::text ->> 'numero',
                     'texto', format('%s passa para %s (%s)', public._agenda_rotulo_da_os((v_ent -> v_c::text ->> 'os')::uuid),
                                     public._agenda_dias_texto(array(select distinct v_ini + (h - 1) / 2
                                                                       from unnest(public._agenda_ints(v_cb -> 'h')) h)),
                                     case when v_ent -> v_c::text ->> 'precisa' is null then 'sem data dita pelo cliente'
                                          else 'precisa até ' || public._dia_curto((v_ent -> v_c::text ->> 'precisa')::date) end),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('atrasar', jsonb_build_array(v_ent -> v_c::text -> 'os'))),
                     'espera', jsonb_build_object(v_os::text, v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1,
                                                  v_ent -> v_c::text ->> 'os', v_fim_c));
          exit when jsonb_array_length(v_opc) >= 4;
        end loop;
      elsif v_fim_x is not null then
        v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', 0, 'sem_data', false, 'atraso_du', 0, 'numero', v_e ->> 'numero',
                   'texto', format('Sigo: %s termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                   public._dia_curto((v_e ->> 'fim_antes')::date)),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                   'espera', jsonb_build_object(v_os::text, v_fim_x));
      end if;
      if jsonb_array_length(v_opc) = 0 then
        -- sem saída nenhuma: não é pergunta (fica fora, sem encaixe); a próxima volta refaz sem ela na espera
        v_sem_q := v_sem_q || v_x;
        continue;
      end if;
      if jsonb_array_length(v_opc) = 1 then
        v_opc := v_opc || jsonb_build_object('n', 2, 'os', v_os, 'atraso_dito', null, 'sem_data', false, 'atraso_du', null,
                   'numero', v_e ->> 'numero',
                   'texto', format('Deixo o %s fora do plano por enquanto', public._agenda_nome_curto(v_e ->> 'cliente_curto')),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('tirar', jsonb_build_array(v_os))),
                   'espera', '{}'::jsonb);
      end if;
      -- a recomendação: o menor atraso sobre datas ditas; no empate, quem não tem data dita, o menor atraso, o número
      if v_tipo = 'nao_cabe' then
        select (o ->> 'n')::int into v_rec from jsonb_array_elements(v_opc) o
         where o ->> 'atraso_dito' is not null
         order by (o ->> 'atraso_dito')::int, (o ->> 'sem_data')::boolean desc, (o ->> 'atraso_du')::int, o ->> 'numero' collate "C"
         limit 1;
        v_rec := coalesce(v_rec, 1);
        v_q := v_opc -> (v_rec - 1);
        v_rec_txt := case when (v_q ->> 'sem_data')::boolean
                            then format('o %s não tem data dita pelo cliente', public._agenda_nome_curto((select cl.name from public.service_orders so
                                          join public.clients cl on cl.id = so.client_id where so.id = (v_q ->> 'os')::uuid)))
                          when v_rec = 1 then format('é o menor atraso (%s)', public._agenda_plural((v_q ->> 'atraso_du')::int, 'dia útil', 'dias úteis'))
                          else 'é o menor atraso sobre o que o cliente pediu' end;
        v_txt := format('Não cabe tudo até %s. Qual aceita atrasar? %s. Recomendo a %s: %s.',
                        public._dia_curto((v_e ->> 'precisa')::date),
                        (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int) from jsonb_array_elements(v_opc) o),
                        v_rec, v_rec_txt);
      else
        v_rec := 1;
        v_rec_txt := case v_tipo
          when 'atraso_longo' then 'Recomendo seguir e você ligar para o cliente hoje'
          when 'segundo_atraso' then 'É o 2º atraso desta OS: recomendo seguir e você ligar para o cliente hoje'
          when 'remarcar_confirmado' then 'O cliente tinha confirmado o dia: recomendo seguir e você ligar para ele hoje'
          else 'Você tinha fixado o dia, que não dá mais: recomendo seguir no novo dia' end;
        -- FASE 7: (7a P3) a recomendação das críticas da zona travada do gestor (P8: o dia que a equipe já recebeu na ficha e o
        -- que o cliente já ouviu); inertes até lá (_agenda_criticidade ainda não dá esses tipos)
        if v_tipo = 'dia_avisado' then
          v_rec_txt := 'A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia';
        elsif v_tipo = 'dia_prometido' then
          v_rec_txt := 'É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje';
        end if;
        -- FASE 7: fim
        v_txt := format('%s só dá para terminar em %s, %s depois do que estava no plano. 1) %s; 2) %s. %s.',
                        public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                        public._agenda_plural(v_fim_x - (v_e ->> 'fim_antes')::date, 'dia', 'dias'),
                        v_opc -> 0 ->> 'texto', v_opc -> 1 ->> 'texto', v_rec_txt);
      end if;
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
      v_perg := v_perg || jsonb_build_object(
        'tipo', v_tipo, 'chave', v_chave, 'service_order_id', v_os,
        'os_ids', (select jsonb_agg(v_ent -> j::text -> 'os' order by j) from unnest(array[v_x] || coalesce(
                     array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[])) j),
        'texto', left(v_txt, 600), 'opcoes', v_opc, 'recomendacao', v_rec, 'recomendacao_texto', left(v_rec_txt, 300),
        'perda_em', (select min(v_ini + ((b ->> 'ini')::int + 1) / 2 - 1) from jsonb_array_elements(v_base -> 'colocadas') b
                      where (b ->> 'i')::int = any (array[v_x] || coalesce(
                        array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[]))),
        'x', v_x);
    end loop;
    -- quem ficou sem saída sai da espera e a conta é refeita
    continue when cardinality(v_sem_q) <> v_n;
    -- as que não fazem X caber não ficam esperando a decisão: a conta é refeita só com as que deram opção (uma vez)
    if v_usadas is null and exists (
         select 1 from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(t.v) j
          where not exists (select 1 from jsonb_array_elements(v_perg) q, jsonb_array_elements(q -> 'opcoes') o
                             where (q ->> 'x')::int = t.k::int and (o ->> 'c')::int = j::int)) then
      select coalesce(jsonb_object_agg(q ->> 'x', coalesce((select jsonb_agg((o ->> 'c')::int) from jsonb_array_elements(q -> 'opcoes') o
                                                             where o ? 'c'), '[]'::jsonb)), '{}'::jsonb)
        into v_usadas from jsonb_array_elements(v_perg) q;
      continue;
    end if;
    exit;
  end loop;
  if cardinality(v_h) = 0 then
    v_xnc := '{}';
    v_xoc := '{}';
    v_perg := '[]'::jsonb;
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx, v_rf -> 'colocadas');
    v_base := jsonb_build_object('colocadas', '[]'::jsonb);
  end if;

  -- ── 6. Os itens: o que sai, o que entra, o que espera a decisão ──
  -- (a) o que sai (a violação, o resto do meio-dia, o pedido do dono)
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', g.numero, 'cliente_curto', g.cliente_curto, 'tipo', g.tipo,
             'motivo', g.motivo, 'violada', g.violada, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: sai %s — %s.', public._agenda_rotulo_da_os(g.os), public._agenda_dias_texto(g.dias),
                             case g.motivo when 'pessoa' then 'quem ia não está mais livre' when 'material' then 'o material não chega a tempo'
                                           when 'cliente' then 'o cliente ou o bem não está liberado' when 'os_saiu' then 'a OS saiu da carteira'
                                           when 'condicao_vencida' then 'a condição da reserva venceu' when 'dono' then 'você pediu outro dia'
                                           when 'espera' then coalesce('você pôs em espera até ' || public._dia_curto(
                                             (select pl.congelada_ate from public.os_planejamento pl where pl.service_order_id = g.os)),
                                             'você pôs em espera')
                                           else 'replanejado junto' end))
             order by g.numero, g.os, g.motivo)
      from (select (c ->> 'os')::uuid as os, min(v_info -> (c ->> 'os') -> 'pront' ->> 'numero') as numero,
                   min(v_info -> (c ->> 'os') -> 'pront' ->> 'cliente_curto') as cliente_curto,
                   case when bool_and(c ->> 'tipo' = 'reserva') then 'reserva' else min(c ->> 'tipo') end as tipo,
                   c ->> 'motivo' as motivo, bool_or((c ->> 'violada')::boolean) as violada,
                   jsonb_agg(jsonb_build_object('alocacao_id', c -> 'alocacao_id', 'payee_id', c -> 'payee_id',
                               'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = (c ->> 'payee_id')::uuid),
                               'dia', c -> 'dia', 'turno', c -> 'turno', 'presenca', c -> 'presenca', 'estado', c -> 'estado',
                               'fixado_por', c -> 'fixado_por')
                             order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id') as alocs,
                   array_agg((c ->> 'dia')::date) as dias, min((c ->> 'dia')::date) as de, max((c ->> 'dia')::date) as ate
              from jsonb_array_elements(v_canc) c
             group by (c ->> 'os')::uuid, c ->> 'motivo') g), '[]'::jsonb);
  -- (b) a reserva que virou compromisso nesta proposta
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', v_ent -> g.i ->> 'numero', 'cliente_curto', v_ent -> g.i ->> 'cliente_curto',
             'tipo', 'reserva', 'motivo', 'promovida', 'violada', false, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: a reserva vira compromisso.', public._agenda_rotulo_da_os(g.os)))
             order by v_ent -> g.i ->> 'numero')
      from (select b ->> 'i' as i, (v_ent -> (b ->> 'i') ->> 'os')::uuid as os,
                   (select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                     'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado, 'fixado_por', a.fixado_por)
                                     order by a.dia, a.turno = 'tarde', a.payee_id)
                      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                     where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid and a.estado in ('publicada', 'fixada')
                       and a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje
                       and not (a.id = any (v_ign))) as alocs,
                   (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as de,
                   (select max(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as ate
              from jsonb_array_elements(v_rf -> 'colocadas') b
             where b ->> 'tipo' = 'compromisso' and coalesce((b ->> 'na_janela')::boolean, true)
               and (v_ent -> (b ->> 'i') ->> 'tem_reserva')::boolean and not ((b ->> 'i')::int = any (v_h))) g
     where g.alocs is not null), '[]'::jsonb);
  -- (c) o que entra: publicável sem esperar, ou (d) esperando a decisão (a X que não cabe sai da proposta)
  for v_b in
    select b || jsonb_build_object('espera', (b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')
      from jsonb_array_elements(v_rf -> 'colocadas') b
     where coalesce((b ->> 'na_janela')::boolean, true)
       and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso')
  loop
    v_e := v_ent -> (v_b ->> 'i');
    v_os := (v_e ->> 'os')::uuid;
    v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
    v_fim_x := v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1;
    v_fim_dep := greatest(v_fim_x, (v_e ->> 'kept_max')::date);
    v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
    v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                     where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
    v_tipo := case when v_b ->> 'tipo' = 'reserva' or v_e ? 'fixar_de' then null
                   else public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                                   v_canc_os, '{}') end;
    -- quem espera a decisão de uma X: o tipo dela e a chave da pergunta
    v_chave := null;
    if (v_b ->> 'espera')::boolean then
      select q ->> 'chave', coalesce(v_tipo, q ->> 'tipo') into v_chave, v_tipo from jsonb_array_elements(v_perg) q
       where q -> 'os_ids' @> jsonb_build_array(v_os) order by q ->> 'chave' limit 1;
    elsif v_tipo is not null and v_decisao is null and not (v_os = any (v_aceitar)) then
      -- crítico sem pergunta (não deveria acontecer: a pergunta foi feita acima); fica esperando
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
    end if;
    -- O pedido do dono num dia antes de o material estar garantido: fica (a decisão é dele), com o aviso na frase.
    v_aviso := case when v_e ? 'fixar_de' and v_b ->> 'tipo' <> 'reserva'
                    then public._agenda_aviso_do_material(v_info -> v_os::text -> 'pront', v_e ->> 'condicao_tipo', v_e ->> 'texto', v_ini_x) end;
    v_txt := case
      when v_b ->> 'tipo' = 'reserva' then
        format('%s: %s, %s%s.',
               case v_b ->> 'reserva_de' when 'patio' then 'Reserva no pátio' when 'teto' then 'Reserva (acima da carga)' else 'Reserva' end
                 || ' ' || public._agenda_rotulo_da_os(v_os),
               public._agenda_faixa_texto(v_ini_x, case when (v_b ->> 'ini')::int % 2 = 1 then 'manha' else 'tarde' end,
                                          v_fim_x, case when (v_b ->> 'fim')::int % 2 = 1 then 'manha' else 'tarde' end),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono), '')
      else
        format('%s%s: %s, %s%s.', public._agenda_rotulo_da_os(v_os),
               case v_e ->> 'tipo_os' when 'diagnostico' then ', diagnóstico' when 'comissionamento' then ', comissionamento' else '' end,
               public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date
                                                 from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a)),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono),
               coalesce(' — mas ' || v_aviso, '')) end;
    -- FASE 7: (7a P3, D7-1) o compromisso marcado pela estimativa do orçamento (a fonte 'orcamento' de agenda_meios_da_os, que
    -- só existe com a regra estimativa) diz isso no fim: "… com Roberto e João (estimativa minha: 6 dias)."
    if v_e ->> 'fonte' = 'orcamento' and v_b ->> 'tipo' <> 'reserva' and right(v_txt, 1) = '.' then
      v_txt := left(v_txt, -1) || format(' (estimativa minha: %s).', public._agenda_dias((v_e ->> 'dias')::numeric));
    end if;
    -- FASE 7: fim
    v_itens := v_itens || jsonb_build_object(
      'op', 'criar', 'os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
      'tipo', case when v_b ->> 'tipo' = 'reserva' then 'reserva' else v_e ->> 'tipo_os' end,
      'reserva_de', v_b ->> 'reserva_de', 'alocacoes', public._agenda_alocs_do_bloco(v_ctx, v_b),
      'de', v_ini_x, 'ate', v_fim_x, 'fim_antes', v_e ->> 'fim_antes', 'fim_depois', v_fim_dep,
      'atraso_du', case when v_b ->> 'tipo' <> 'reserva' and v_e ->> 'fim_antes' is not null and v_fim_dep > (v_e ->> 'fim_antes')::date
                        then public.agenda_du_entre((v_e ->> 'fim_antes')::date, v_fim_dep) end,
      'condicao_tipo', case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'condicao_tipo' end,
      'critica', v_tipo, 'pergunta_chave', v_chave, 'decisao', v_decisao, 'espera', (v_b ->> 'espera')::boolean,
      'interrupcoes', (v_b ->> 'int')::int, 'meios_do_dono', (v_b ->> 'md')::int, 'fonte', v_e ->> 'fonte', 'dias', v_e -> 'dias',
      'evento_real', (v_e ->> 'evento_real')::boolean, 'fixar_dono', v_e ? 'fixar_de', 'aviso_material', v_aviso,
      'abre', (v_e ->> 'abre')::boolean and v_b ->> 'tipo' <> 'reserva', 'fecha', (v_e ->> 'fecha')::boolean and v_b ->> 'tipo' <> 'reserva',
      'motivos', to_jsonb(array_remove(array[
         case when v_e ->> 'classe' = '1' and not v_e ? 'fixar_de' then 'em andamento ou fixada' end,
         case when v_e ? 'fixar_de' then 'você pediu' end,
         case when (v_e ->> 'evento_real')::boolean then 'replanejado por um imprevisto de hoje ou amanhã' end,
         case when v_b ->> 'tipo' <> 'reserva' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'teto' then 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%' end,
         case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'patio' then 'adiantar no pátio enquanto o bem está fora' end], null)),
      'texto', v_txt, 'aplicado', false);
    -- CORREÇÃO FASE 6: (C1) item 14: a reserva por teto da OS que precisa do dono (abre, fecha ou o turno dele), com a
    -- capacidade do dono em uso abaixo da carga de todos (_agenda_carga_da_pessoa), diz a parte da semana DELE: "não coube na
    -- sua parte da semana (56%)", e não "na carga de 80%". Sem nada em uso, o item é o de antes, byte a byte.
    if v_b ->> 'reserva_de' = 'teto'
       and (coalesce((v_e ->> 'abre')::boolean, false) or coalesce((v_e ->> 'fecha')::boolean, false)
            or coalesce((v_e ->> 'dt_m')::boolean, false) or coalesce((v_e ->> 'dt_t')::boolean, false))
       and public._agenda_carga_da_pessoa(v_dono) < cf.carga_max then
      v_itens := jsonb_set(v_itens, '{-1,motivos}',
                   (select coalesce(jsonb_agg(case when m #>> '{}' = 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%'
                                                   then to_jsonb('não coube na sua parte da semana ('
                                                                 || public._agenda_num(public._agenda_carga_da_pessoa(v_dono) * 100, 0) || '%)')
                                                   else m end order by o), '[]'::jsonb)
                      from jsonb_array_elements(v_itens -> -1 -> 'motivos') with ordinality t(m, o)));
    end if;
    -- CORREÇÃO FASE 6: fim
  end loop;

  -- A condição e a data-limite das reservas condicionadas (do 1º dia de cada uma: o "compre até" daquele início).
  select coalesce(jsonb_agg(case when i ->> 'reserva_de' = 'condicionada' then
             i || x.c || jsonb_build_object('texto', rtrim(i ->> 'texto', '.') || ' — ' || (x.c ->> 'condicao') || '.')
           else i end order by k), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(v_itens) with ordinality t(i, k)
    cross join lateral (select case when i ->> 'reserva_de' = 'condicionada'
                                    then public._agenda_condicao_da_reserva((i ->> 'os')::uuid, i ->> 'condicao_tipo', (i ->> 'de')::date,
                                                                            v_info -> (i ->> 'os') -> 'pront', p_hoje) end as c) x;

  -- ── 7. O que fica de fora, com quem trava ──
  for v_e in select e from jsonb_array_elements(v_fila) e order by (e ->> 'ordem')::int loop
    v_os := (v_e ->> 'os')::uuid;
    continue when exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'os')::uuid = v_os and i ->> 'op' = 'criar');
    v_x := (v_e ->> 'i')::int;
    v_txt := null;
    v_chave := null;
    if v_x = any (v_xnc) and exists (select 1 from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x) then
      select q ->> 'chave' into v_chave from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x;
      v_txt := format('%s: não cabe até %s — preciso de você.', public._agenda_rotulo_da_os(v_os), public._dia_curto((v_e ->> 'precisa')::date));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'nao_cabe', 'texto', v_txt, 'pergunta_chave', v_chave);
      continue;
    end if;
    if v_x = any (v_sem_q) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                 'motivo', 'sem_encaixe',
                 'texto', format('%s: sem encaixe com a equipe de hoje (nem atrasando outra OS).', public._agenda_rotulo_da_os(v_os)));
      continue;
    end if;
    if (v_e ->> 'classe')::int = 4 then
      v_txt := format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_e ->> 'texto', '.'));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', v_e ->> 'motivo', 'texto', v_txt);
      continue;
    end if;
    continue when coalesce((v_e ->> 'passos')::int, 0) <= 0;
    select f ->> 'motivo' into v_tipo from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x limit 1;
    if v_tipo is null then
      select b into v_b from jsonb_array_elements(v_rf -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso';
      if v_b is not null and not coalesce((v_b ->> 'na_janela')::boolean, true) then
        v_tipo := 'depois';
        v_txt := format('%s: começa %s%s.', public._agenda_rotulo_da_os(v_os),
                        public._dia_curto(v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1),
                        coalesce(' (' || (select r ->> 'texto' from jsonb_array_elements(v_info -> v_os::text -> 'pront' -> 'restricoes') r
                                           where r ->> 'tipo' in ('bem', 'nao_antes') limit 1) || ')', ''));
      elsif v_x = any (v_h) then
        v_tipo := 'espera';
        v_txt := format('%s: espera a sua decisão.', public._agenda_rotulo_da_os(v_os));
      end if;
    end if;
    continue when v_tipo is null;
    v_txt := coalesce(v_txt, format('%s: %s.', public._agenda_rotulo_da_os(v_os), case v_tipo
      when 'padrao_do_dono' then 'falta você dizer quais dias fica em campo'
      when 'fixar_nao_cabe' then format('não cabe %s: %s', public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                        public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
      when 'sem_reserva' then rtrim(v_e ->> 'texto', '.') || ' (sem lugar para a reserva nesta semana)'
      when 'so_com_voce' then rtrim(v_e ->> 'texto', '.') || ' (é só com você: entra quando isso estiver respondido)'
      else format('sem encaixe em %s semanas com a equipe de hoje', cf.horizonte_semanas) end));
    v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                           'motivo', v_tipo, 'texto', v_txt);
  end loop;
  -- (as que saíram da carteira e tinham plano)
  v_fora := v_fora || coalesce((
    select jsonb_agg(jsonb_build_object('os', x.os, 'numero', v_info -> x.os::text -> 'pront' ->> 'numero',
             'cliente_curto', v_info -> x.os::text -> 'pront' ->> 'cliente_curto', 'motivo', 'fora_da_carteira',
             'texto', format('%s: %s.', public._agenda_rotulo_da_os(x.os), v_info -> x.os::text -> 'pront' ->> 'estado_texto'))
             order by v_info -> x.os::text -> 'pront' ->> 'numero')
      from (select distinct (c ->> 'os')::uuid as os from jsonb_array_elements(v_canc) c where c ->> 'motivo' = 'os_saiu') x
     where not (x.os = any (v_escopo))), '[]'::jsonb);

  -- ── 8. A carga por pessoa e semana (o publicável sem esperar) ──
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object('nome', p.nome, 'semanas', p.semanas)), '{}'::jsonb) into v_carga
    from (select (v_ctx -> 'pessoas' ->> (pp - 1)) as id, (v_ctx -> 'nomes' ->> (pp - 1)) as nome,
                 jsonb_agg(jsonb_build_object(
                   'semana', v_seg + 7 * (ww - 1),
                   'esperado', (v_ctxf -> 'esperado' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto80', (v_ctxf -> 'teto80' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto100', (v_ctxf -> 'teto100' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'compromisso', (v_ctxf -> 'uso_c' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'reserva', (v_ctxf -> 'uso_r' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1))) order by ww) as semanas
            from generate_series(1, (v_ctx ->> 'np')::int) pp
            cross join generate_series((v_de - v_seg) / 7 + 1, (v_ate - v_seg) / 7 + 1) ww
           group by pp) p;

  -- ── 9. A pontuação (para comparar alternativas) ──
  select jsonb_build_object(
           'atraso_dias', coalesce(sum(greatest((i ->> 'fim_depois')::date - (v_ent -> x.ii ->> 'precisa')::date, 0))
                                     filter (where v_ent -> x.ii ->> 'precisa' is not null), 0),
           'mudancas', (select count(*) from jsonb_array_elements(v_canc) c where not (c ->> 'violada')::boolean and c ->> 'motivo' = 'replanejado'),
           'meios_do_dono', coalesce(sum((i ->> 'meios_do_dono')::int), 0),
           'interrupcoes', coalesce(sum((i ->> 'interrupcoes')::int), 0),
           'fim', coalesce(sum((i ->> 'ate')::date - v_ini), 0))
    into v_pont
    from jsonb_array_elements(v_itens) i
    cross join lateral (select (select e ->> 'i' from jsonb_array_elements(v_fila) e where e ->> 'os' = i ->> 'os') as ii) x
   where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false);
  v_pont := v_pont || jsonb_build_object('total',
    (v_pont ->> 'atraso_dias')::bigint * c_peso_atraso + (v_pont ->> 'mudancas')::bigint * c_peso_mudanca
    + (v_pont ->> 'meios_do_dono')::bigint * c_peso_dono + (v_pont ->> 'interrupcoes')::bigint * c_peso_interr
    + (v_pont ->> 'fim')::bigint * c_peso_fim);

  -- ── 10. Os textos prontos ──
  v_feriados := array(select format('%s é %s', public._agenda_dia_sem_mes(g::date), public.agenda_feriado(g::date))
                        from generate_series(v_de - (extract(isodow from v_de)::int - 1), v_ate, interval '1 day') g
                       where extract(isodow from g)::int <= 5 and public.agenda_feriado(g::date) is not null order by g);
  v_titulo := case when p_escopo = 'semana'
    then format('Semana de %s a %s', to_char(v_de, 'DD'),
                to_char(coalesce((select max(g::date) from generate_series(v_de, v_ate, interval '1 day') g
                                   where public.agenda_dia_util(g::date)), v_ate), 'DD/MM'))
         || coalesce(' (' || nullif(array_to_string(v_feriados, ', '), '') || ')', '')
    else 'Mudanças na agenda' end;
  v_linhas := array(select i ->> 'texto' || case when coalesce((i ->> 'espera')::boolean, false) then ' (espera a sua decisão)' else '' end
                      from jsonb_array_elements(v_itens) with ordinality t(i, k)
                     order by i ->> 'op' = 'cancelar', (i ->> 'de')::date, i ->> 'numero' collate "C", k);
  v_tfora := array(select f ->> 'texto' from jsonb_array_elements(v_fora) with ordinality t(f, k) order by k);
  v_textos := jsonb_build_object('titulo', v_titulo, 'linhas', to_jsonb(v_linhas), 'fora', to_jsonb(v_tfora),
    'carga', to_jsonb(array(
      select format('%s: %s de %s meios-dias de serviço na semana de %s',
                    case when p.key::uuid is not distinct from v_dono then 'Você' else p.value ->> 'nome' end,
                    s ->> 'compromisso', s ->> 'teto80', to_char((s ->> 'semana')::date, 'DD/MM'))
        from jsonb_each(v_carga) p, jsonb_array_elements(p.value -> 'semanas') s
       where (s ->> 'esperado')::numeric > 0
       order by (s ->> 'semana')::date, p.key::uuid is not distinct from v_dono desc, p.value ->> 'nome')),
    'resumo', format('%s: %s, %s.', v_titulo,
                     public._agenda_plural((select count(distinct i ->> 'os')::int from jsonb_array_elements(v_itens) i
                                             where i ->> 'op' = 'criar' and not (i ->> 'espera')::boolean), 'serviço marcado', 'serviços marcados'),
                     public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
  -- CORREÇÃO 29/10 (P3): o marcado firme e o reservado separados no resumo e no título da semana (com a agenda automática
  -- ligada). A reserva só guarda o lugar da equipe (nada está marcado até a condição dela se cumprir), e o resumo de antes
  -- contava como "serviço marcado" toda OS que entra: com só a reserva do Lenine, "1 serviço marcado". Com reserva no que
  -- entra (sem o que espera a decisão), o resumo diz quem: "1 reservado (Lenine), nada marcado firme, 10 de fora"; e o título
  -- da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme"): é ele que abre o
  -- "Publiquei a semana de …" da aplicação, do que mudou e do fechamento, que listam as OS logo depois. A OS com algum
  -- meio-dia firme conta como marcada. No resumo, o nome curto do cliente, com o número quando o nome se repete ("Kalmar
  -- OS-00032"); até 3 nomes, depois "e mais N". Sem reserva, ou fora de ligado, os dois são os de antes, byte a byte.
  if v_modo = 'ligado' then
    select coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where x.firme), '{}'::text[]),
           coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where not x.firme), '{}'::text[])
      into v_marc, v_resv
      from (select y.numero, y.de, y.firme,
                   case when count(*) over (partition by y.curto) > 1 then concat_ws(' ', y.curto, y.numero) else y.curto end as nome
              from (select min(i ->> 'numero') as numero, min((i ->> 'de')::date) as de, bool_or(i ->> 'tipo' <> 'reserva') as firme,
                           coalesce(public._agenda_nome_curto(min(i ->> 'cliente_curto')), min(i ->> 'numero')) as curto
                      from jsonb_array_elements(v_itens) i
                     where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false)
                     group by i ->> 'os') y) x;
  end if;
  if cardinality(v_resv) > 0 then
    v_contagem := case when cardinality(v_marc) > 0
                       then format('%s (%s), %s (%s)',
                                   public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                   public._agenda_lista(v_marc, 3),
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                       else format('%s (%s), nada marcado firme',
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                  end;
    v_textos := v_textos || jsonb_build_object('resumo', format('%s: %s, %s.', v_titulo, v_contagem,
                                                               public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
    if p_escopo = 'semana' then
      v_titulo := v_titulo || ' — '
                  || case when cardinality(v_marc) > 0
                          then format('%s, %s', public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                      public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                          else format('%s, nada marcado firme', public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                     end;
      v_textos := v_textos || jsonb_build_object('titulo', v_titulo);
    end if;
  end if;
  -- CORREÇÃO 29/10 (P3): fim
  v_texto := v_titulo
    || coalesce(E'\n' || nullif(array_to_string(array(select '• ' || x from unnest(v_linhas) x), E'\n'), ''), E'\nNada a mudar.')
    || coalesce(E'\nFora: ' || nullif(array_to_string(v_tfora, '; '), ''), '')
    || case when p_persistir then '' else E'\nÉ simulação: não muda nada.' end;

  -- ── 11. A validação: proposta inválida nunca sai ──
  v_viol := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', v_r), p_hoje, p_agora, false,
              (select jsonb_object_agg(k, x -> 'pront') from jsonb_each(v_info) t(k, x)));
  if jsonb_array_length(v_viol) > 0 then
    raise exception 'agenda_propor: a proposta saiu inválida (erro do motor): %', v_viol::text
      using errcode = 'P0001', detail = left(v_texto, 2000);
  end if;

  -- ── 12. Persistir ──
  if p_persistir then
    -- a aberta anterior do mesmo escopo e modo (e das mesmas OS, fora da semana) fica obsoleta; as alocações dela saem
    for v_q in
      select to_jsonb(pr) from public.agenda_propostas pr
       where pr.estado = 'aberta' and pr.escopo = p_escopo and pr.modo = v_modo
         and (p_escopo = 'semana' or pr.os_alvo && v_escopo)
       order by pr.criada_em, pr.id
    loop
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'refeita' where id = (v_q ->> 'id')::uuid;
      delete from public.agenda_alocacoes where proposta_id = (v_q ->> 'id')::uuid and estado = 'proposta';
    end loop;
    v_pid := gen_random_uuid();
    -- os ids das alocações novas entram no item (é por eles que o aplicar publica)
    select coalesce(jsonb_agg(case when i ->> 'op' = 'criar'
             then i || jsonb_build_object('alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                                                          from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)))
             else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
    v_expira := least(p_agora + cf.proposta_validade,
                      coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca')))
                                  from jsonb_array_elements(v_itens) i, jsonb_array_elements(i -> 'alocacoes') a
                                 where i ->> 'op' = 'criar'), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, p_escopo, daterange(v_de, v_ate, '[]'), v_escopo, v0, v_modo, 'aberta', v_itens, v_fora, v_carga, v_textos,
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', p_de, 'p_ate', p_ate, 'p_os', to_jsonb(p_os),
                               'p_restricoes', v_r, 'escopo', p_escopo, 'origem', p_origem, 'de', v_de, 'ate', v_ate),
            v_pont, p_origem, p_autor, p_agora, v_expira);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         reserva_de, condicao, condicao_tipo, condicao_ate, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, (i ->> 'os')::uuid, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno',
           a ->> 'presenca', i ->> 'tipo', 'proposta', case when (i ->> 'fixar_dono')::boolean then 'dono' else 'motor' end, v_pid,
           i ->> 'reserva_de', case when a ->> 'presenca' = 'turno' then i ->> 'condicao' end,
           case when a ->> 'presenca' = 'turno' then i ->> 'condicao_tipo' end,
           case when a ->> 'presenca' = 'turno' then (i ->> 'condicao_ate')::date end,
           coalesce(i -> 'motivos', '[]'::jsonb), p_agora
      from jsonb_array_elements(v_itens) with ordinality t(i, k), jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)
     where i ->> 'op' = 'criar'
     order by k, j;
    -- as perguntas críticas (a mesma pergunta não abre duas vezes; a de uma versão anterior da mesma OS sai)
    for v_q in select q from jsonb_array_elements(v_perg) q loop
      update public.agenda_perguntas p
         set estado = 'descartada', resolvida_motivo = 'a agenda mudou: a pergunta foi refeita'
       where p.estado = 'aberta' and p.modo = v_modo and p.tipo = v_q ->> 'tipo'
         and p.service_order_id = (v_q ->> 'service_order_id')::uuid and p.chave <> v_q ->> 'chave';
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao,
                                           recomendacao_texto, proposta_id, versao_base, modo, criada_em)
      values (v_q ->> 'tipo', v_q ->> 'chave', (v_q ->> 'service_order_id')::uuid,
              array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x), null, (v_q ->> 'perda_em')::date,
              v_q ->> 'texto', v_q -> 'opcoes', (v_q ->> 'recomendacao')::smallint, v_q ->> 'recomendacao_texto', v_pid, v0, v_modo, p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true, 'proposta_id', v_pid, 'versao_base', v0, 'escopo', p_escopo, 'modo', v_modo,
    'periodo', jsonb_build_object('de', v_de, 'ate', v_ate), 'simulacao', not p_persistir,
    'itens', v_itens, 'fora', v_fora, 'carga', v_carga,
    'perguntas', (select coalesce(jsonb_agg(q - 'x' order by q ->> 'chave'), '[]'::jsonb) from jsonb_array_elements(v_perg) q),
    'pontuacao', v_pont, 'textos', v_textos, 'texto', v_texto);
end;
$function$;

comment on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8.';

-- _agenda_rodada_marca (de 20261030100400_agenda_correcao_desempenho.sql): a marca da memória da vigia, que passa a contar a pergunta e a ação quando a
-- prontidão as lê (a regra situacao). O comentário dela (a de antes) dizia: "se um dia ler, o teste cai e a tabela sai desta
-- lista" — aqui a tabela sai da lista só com a regra, e o G de agenda_correcao_2910_p5.sql passa a conferir isso.
create or replace function public._agenda_rodada_marca()
 returns bigint
 language sql
 volatile
 set search_path to 'public'
as $function$
  select coalesce(sum(pg_catalog.pg_stat_get_xact_tuples_inserted(c.oid) + pg_catalog.pg_stat_get_xact_tuples_updated(c.oid)
                      + pg_catalog.pg_stat_get_xact_tuples_deleted(c.oid)), 0)::bigint
  -- FASE 7: (7a P3) com a regra situacao do gestor, a conta da prontidão lê (pela situação da OS, _agenda_os_situacao) a última
  -- ação da agenda e a pergunta aberta da OS: agenda_acoes e agenda_perguntas, duas das 5 que a marca de sempre não conta. Aí a
  -- marca conta também as duas, num número negativo (−1 − as escritas de sempre − as das duas): nunca igual a uma marca sem a
  -- regra (que é >= 0) e muda com qualquer escrita em cada uma. Sem a regra, a marca é a de antes (o termo vale 0).
         + case when public._agenda_gestor_regra('situacao')
                then -2 * coalesce(sum(pg_catalog.pg_stat_get_xact_tuples_inserted(c.oid) + pg_catalog.pg_stat_get_xact_tuples_updated(c.oid)
                                       + pg_catalog.pg_stat_get_xact_tuples_deleted(c.oid)), 0)::bigint
                     - (select coalesce(sum(pg_catalog.pg_stat_get_xact_tuples_inserted(d.oid)
                                            + pg_catalog.pg_stat_get_xact_tuples_updated(d.oid)
                                            + pg_catalog.pg_stat_get_xact_tuples_deleted(d.oid)), 0)::bigint
                          from pg_catalog.pg_class d
                         where d.relnamespace = 'public'::regnamespace and d.relkind in ('r', 'p')
                           and d.relname in ('agenda_perguntas', 'agenda_acoes'))
                     - 1
                else 0 end
  -- FASE 7: fim
    from pg_catalog.pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
     and c.relname not in ('agenda_perguntas', 'agenda_acoes', 'agenda_propostas', 'agenda_vigia_rodadas', 'app_error_logs');
$function$;

comment on function public._agenda_rodada_marca() is
  'Agenda de Produção (correção de 29/10, P5): a marca das escritas desta transação nas tabelas de public (linhas inseridas, mudadas e apagadas, pelos contadores da própria transação; só cresce), menos as 5 que a vigia escreve e a conta da prontidão não lê (agenda_perguntas, agenda_acoes, agenda_propostas, agenda_vigia_rodadas, app_error_logs). A memória da rodada da vigia só devolve o que foi calculado com a marca de agora. FASE 7 (7a P3): com a regra situacao do gestor (a conta da prontidão lê então agenda_acoes e agenda_perguntas, pela situação da OS), a marca conta também essas duas, num número negativo (−1 − as escritas de sempre − as das duas), que nunca coincide com uma marca sem a regra; sem a regra, a de antes.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- As recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a migration valer sozinha): a
-- prontidão e a classe, leituras, para quem tem login e o service_role (nunca anon); o motor, só o service_role; a marca da
-- memória da vigia, ninguém de fora (só a agenda_vigiar, definer, a chama pela prontidão).
revoke all on function public.os_prontidao(uuid, date), public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)
  from public, anon;
grant execute on function public.os_prontidao(uuid, date), public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)
  to authenticated, service_role;
revoke all on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  to service_role;
revoke all on function public._agenda_rodada_marca() from public, anon, authenticated, service_role;
