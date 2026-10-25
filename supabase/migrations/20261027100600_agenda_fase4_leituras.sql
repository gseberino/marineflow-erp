-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P6: as leituras — a espera de peça (os 3
-- componentes: da aprovação até a compra, do fornecedor, chegou e ficou parado) com o KPI "dias da aprovação até a compra",
-- e os focos compras e fornecedores da agenda_ver.
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§0 item 7, §5.6, §6.5, §7, §11 aceite 7). Decisões do dono 23/10 (o LLM
-- nunca calcula data: as datas e os textos saem do banco; "proposta" não se usa no sentido de agenda). Depende de
-- 20261027100000 (as tabelas), 100100 (o prazo do fornecedor), 100200 (a OC ligada à linha e o comprado_em da
-- sincronização), 100300 (as notas), 100400 (o detector) e 100500 (os fornecedores principais e a mensagem ao fornecedor).
--
-- ═══ LEITURAS — OK NOMEADO ═══ (1 view, 8 funções novas, 1 recriada; nenhuma tabela, nenhum dado, nenhuma escrita)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f4p6/montar-migration.mjs: as partes escritas à mão
-- e o corpo de agenda_ver copiado da migration MAIS NOVA que a define (20261026100500), com cada troca "-- FASE 4:"
-- conferida (uma vez só; fora dos blocos, só saem as 5 linhas da conferência do foco, que entram, ampliadas, num bloco).
--
-- POR QUE: o dono não sabe quanto tempo leva para comprar depois que o cliente aprova (OS-00104: 21 dias) e o material que
-- chega fica parado sem ninguém ver. A Fase 4 grava as compras, as notas e as previsões; faltava ler: "o que falta comprar
-- e até quando", "quanto tempo eu levo pra comprar" e "como você conta o prazo dos fornecedores".
--
-- O QUE MUDA:
--   1. _agenda_espera_linhas(p_hoje) e a view v_agenda_espera_de_peca (security_invoker; = a função no dia de agora): uma
--      linha por OS com material crítico (a carteira e as concluídas com saída nos últimos 180 dias) — aprovada_em (a régua
--      de os_carteira), primeira/última compra (comprado_em, senão o dia da OC da linha ou ligada a ela), última chegada,
--      início (check-in, senão o 1º meio-dia cumprido), dias_ate_comprar/du_ate_comprar, dias/du_do_fornecedor,
--      dias/du_parada, linhas e linhas_sem_compra.
--   2. agenda_espera_de_peca(p_os, p_hoje): {os:[… texto], mediana_ate_comprar_90d, texto} — a frase de cada OS ("Flávio
--      (OS-00104): aprovada ter 22/09; "Compressor 12V de…" comprado ter 13/10 (21 dias depois); chegou qua 14/10 (1 dia
--      útil depois da compra); ainda não começou: parado há 12 dias úteis com o material na mão.") e o "Tempo até comprar".
--   3. _agenda_ver_compras (foco compras): sem OS, os serviços da fila com material fora de A (o que falta, "Compre até …
--      para começar …", o que vem e de onde), as notas sem a palavra do dono, o tempo até comprar, a pergunta ao fornecedor
--      da semana (em sombra: "em teste") e o detector em teste; com OS, a espera dela e o material dela.
--   4. _agenda_ver_fornecedores (foco fornecedores): os principais com o prazo da fonte única, agrupados ("Você disse",
--      "Meu chute (pela cidade ou pelo nome)", "Falta você dizer") e a frase de como responder (um áudio só).
--   5. agenda_ver recriada (corpo de 20261026100500): os focos compras (com ou sem OS; a OS concluída também) e fornecedores;
--      a mensagem do foco que não existe cita os 17.
--   Ajudantes: _agenda_dias_depois, _agenda_espera_texto, _agenda_compras_da_os, _agenda_fornecedor_frase.
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum dado, nenhuma escrita (tudo STABLE); os focos de antes, a ferramenta e as palavras
-- de antes; o financeiro inteiro. A agenda_saude (P5) continua com a mesma mediana (a mesma régua; o L1 confere).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase4_leituras.sql):
--   · As leituras do foco compras e do foco fornecedores são security definer (como a agenda_livre_de_verdade da Fase 3):
--     leem os fornecedores principais e as compras vivas (só service_role) e a fila do WhatsApp; conferem quem vê antes de
--     tudo (com login, só administrador e financeiro: 42501). A espera de peça e a view são invoker.
--   · O "compre até" sai da restrição compre_ate da prontidão, com o dia de começar do plano (ou a janela marcada); na
--     fixture, o Vanderlei: "Compre até sex 30/10 para começar ter 03/11" (a amostra da spec dizia ter 03/11 / qui 05/11).
--   · O foco compras não lista orçamento (o material do orçamento só se compra depois de virar OS: o foco material diz
--     "converter em OS ou arquivar antes de comprar") e, como o foco material, não conta o parado no cliente.
--   · A OS de material todo na mão aparece no foco compras só parada (sem início e há 1 dia útil ou mais): "material na mão
--     desde qua 14/10, parado há 12 dias úteis; começa ter 03/11".
--   · A nota sem a palavra do dono: "Não sei de qual serviço é a nota 812 da Correa (qui 29/10): me diga, ou se não é de
--     serviço." (a amostra dizia "Nota sem serviço", que se confunde com o "não é de serviço").
--   · A pergunta ao fornecedor lê a previsão de AGORA da linha e o estado da fila ("perguntei" só com sent_at; "vou
--     perguntar" na fila; "não saiu" quando falhou; a recusada diz o motivo).
--
-- ORDEM DE LIGAR: depois de 20261027100000..100500, antes do deploy do ai-agent e do erp-mcp (as palavras *agenda compras* e
-- *agenda fornecedores*, a ferramenta agenda_ver com os focos novos e o prompt). Sem esta migration, os focos novos dão
-- 22023 na agenda_ver (a ferramenta devolve o erro ao modelo; a palavra responde "Não consegui ler a agenda agora" e registra
-- em app_error_logs).
--
-- C1 DA REVISÃO DA FASE 4 (25/10/2026): _agenda_fornecedor_frase lê o motivo novo desatualizada ("o material mudou antes de
-- a pergunta sair").
--
-- PROVA: supabase/tests/agenda_fase4_leituras.sql (L1–L6). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261027100000..100500):
--   npx supabase db query --linked -f supabase/migrations/20261027100600_agenda_fase4_leituras.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027100600', 'agenda_fase4_leituras');"
--
-- IDEMPOTENTE: create or replace (view com as mesmas colunas e funções), revoke/grant e comment.


-- ── 1. A espera de peça: as linhas, a view e o texto ───────────────────────────────────────────────────

-- Uma linha por OS com material crítico (fora o dispensado): a carteira (os_carteira) e as concluídas/faturadas com saída
-- nos últimos 180 dias. A compra de cada linha é o dia que o dono ou a sincronização gravou (os_material.comprado_em) ou,
-- sem ele, o dia de Brasília em que nasceu a OC da linha (purchase_order_item_id) ou ligada a ela (P2: service_order_part_id
-- / service_order_service_id), fora a cancelada. O início é o check-in (Brasília), senão o 1º meio-dia do plano cumprido
-- ou parcial até p_hoje. Os 3 componentes da espera: dias da aprovação até a 1ª compra (corridos e úteis), do fornecedor
-- (última compra → última chegada, só com o material todo na mão) e parado (última chegada → início, ou → p_hoje sem
-- início; nunca negativo).
create or replace function public._agenda_espera_linhas(p_hoje date)
 returns table (service_order_id uuid, numero text, cliente_curto text, status text, na_carteira boolean, aprovada_em date,
                primeira_compra date, ultima_compra date, ultima_chegada date, inicio date, material_na_mao boolean,
                dias_ate_comprar integer, du_ate_comprar integer, dias_do_fornecedor integer, du_do_fornecedor integer,
                dias_parada integer, du_parada integer, linhas integer, linhas_sem_compra integer, linha_unica text)
 language sql
 stable
 set search_path to 'public'
as $function$
  with os as (
    select k.service_order_id as id, true as na_carteira
      from public.os_carteira(p_hoje) k
    union all
    select so.id, false
      from public.service_orders so
     where so.merged_into_id is null and so.status in ('completed', 'invoiced')
       and (so.check_out_at at time zone 'America/Sao_Paulo')::date between p_hoje - 179 and p_hoje
  ),
  l as (
    select m.service_order_id, m.descricao, m.situacao, m.chegou_em,
           coalesce(m.comprado_em,
                    (select min((po.created_at at time zone 'America/Sao_Paulo')::date)
                       from public.purchase_order_items poi
                       join public.purchase_orders po on po.id = poi.purchase_order_id
                      where po.status <> 'cancelled'
                        and (poi.id = m.purchase_order_item_id
                             or (m.service_order_part_id is not null and poi.service_order_part_id = m.service_order_part_id)
                             or (m.service_order_service_id is not null
                                 and poi.service_order_service_id = m.service_order_service_id)))) as comprado
      from public.os_material m
      join os on os.id = m.service_order_id
     where m.critico and m.situacao <> 'dispensado'
  ),
  a as (
    select l.service_order_id, min(l.comprado) as primeira, max(l.comprado) as ultima, max(l.chegou_em) as chegada,
           bool_and(l.situacao = 'na_mao') as na_mao, count(*)::int as n,
           (count(*) filter (where l.comprado is null and l.situacao = 'falta'))::int as sem_compra,
           case when count(*) = 1 then min(l.descricao) end as unica
      from l
     group by l.service_order_id
  ),
  b as (
    select so.id, so.service_order_number as numero, public._agenda_nome_curto(c.name) as curto, so.status, os.na_carteira,
           (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as aprovada,
           a.primeira, a.ultima, a.chegada, a.na_mao, a.n, a.sem_compra, a.unica,
           coalesce((so.check_in_at at time zone 'America/Sao_Paulo')::date,
                    (select min(x.dia) from public.agenda_alocacoes x
                      where x.service_order_id = so.id and x.estado in ('publicada', 'fixada') and x.tipo <> 'reserva'
                        and x.resultado in ('cumprido', 'parcial') and x.dia <= p_hoje)) as inicio
      from os
      join a on a.service_order_id = os.id
      join public.service_orders so on so.id = os.id
      left join public.clients c on c.id = so.client_id
  )
  select b.id, b.numero, b.curto, b.status, b.na_carteira, b.aprovada, b.primeira, b.ultima, b.chegada, b.inicio, b.na_mao,
         b.primeira - b.aprovada,
         public.agenda_du_entre(b.aprovada, b.primeira),
         case when b.na_mao then b.chegada - b.ultima end,
         case when b.na_mao then public.agenda_du_entre(b.ultima, b.chegada) end,
         case when b.na_mao then greatest(coalesce(b.inicio, p_hoje) - b.chegada, 0) end,
         case when b.na_mao then greatest(public.agenda_du_entre(b.chegada, coalesce(b.inicio, p_hoje)), 0) end,
         b.n, b.sem_compra, b.unica
    from b
   order by b.aprovada, b.numero collate "C", b.id;
$function$;

comment on function public._agenda_espera_linhas(date) is
  'Agenda de Produção (Fase 4, P6): a espera de peça em p_hoje, uma linha por OS com material crítico (fora o dispensado) — a carteira (os_carteira) e as concluídas/faturadas com saída nos últimos 180 dias. aprovada_em = a régua de os_carteira (conversão, senão assinatura, senão criação; dia de Brasília); a compra de cada linha = os_material.comprado_em, senão o dia de Brasília da OC da linha ou ligada a ela (fora a cancelada); primeira/ultima_compra, ultima_chegada (max chegou_em), inicio (check-in, senão o 1º meio-dia do plano cumprido ou parcial até p_hoje). Os 3 componentes: dias_ate_comprar (corridos, aprovação → 1ª compra) e du_ate_comprar; dias/du_do_fornecedor (última compra → última chegada, só com o material todo na mão); dias/du_parada (última chegada → início, ou → p_hoje sem início; nunca negativo; só com o material todo na mão). linhas, linhas_sem_compra (em falta e sem compra), linha_unica (a descrição quando é uma linha só). Invoker: a RLS de quem lê vale.';

-- A view (spec §5.6) é a mesma conta no dia de agora (_agenda_hoje: o agenda.hoje da RPC que age, senão Brasília).
create or replace view public.v_agenda_espera_de_peca with (security_invoker = on) as
  select x.service_order_id, x.numero, x.cliente_curto, x.status, x.na_carteira, x.aprovada_em, x.primeira_compra,
         x.ultima_compra, x.ultima_chegada, x.inicio, x.material_na_mao, x.dias_ate_comprar, x.du_ate_comprar,
         x.dias_do_fornecedor, x.du_do_fornecedor, x.dias_parada, x.du_parada, x.linhas, x.linhas_sem_compra
    from public._agenda_espera_linhas(public._agenda_hoje()) x;

comment on view public.v_agenda_espera_de_peca is
  'Agenda de Produção (Fase 4, P6): a espera de peça por OS (carteira e concluídas nos últimos 180 dias) no dia de agora — os 3 componentes (aprovação → 1ª compra, do fornecedor, chegou e ficou parado). É _agenda_espera_linhas(_agenda_hoje()); quem precisa de um dia fixo chama agenda_espera_de_peca(p_os, p_hoje). security_invoker: a RLS de quem lê vale (o técnico não vê nada).';

-- "21 dias depois", "no dia da aprovação", "3 dias antes da aprovação".
create or replace function public._agenda_dias_depois(p_n integer, p_de text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_n is null then null
              when p_n = 0 then 'no dia ' || p_de
              when p_n < 0 then public._agenda_plural(-p_n, 'dia', 'dias') || ' antes ' || p_de
              else public._agenda_plural(p_n, 'dia', 'dias') || ' depois' end;
$function$;

comment on function public._agenda_dias_depois(integer, text) is
  'Agenda de Produção (Fase 4, P6): "21 dias depois", "no dia da aprovação", "3 dias antes da aprovação" (p_de = "da aprovação").';

-- O texto da espera de UMA OS (a linha de _agenda_espera_linhas em jsonb):
-- "Flávio (OS-00104): aprovada ter 22/09; "Compressor 12V de…" comprado ter 13/10 (21 dias depois); chegou qua 14/10 (1 dia
-- útil depois da compra); ainda não começou: parado há 12 dias úteis com o material na mão."
create or replace function public._agenda_espera_texto(p jsonb, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_quem   text := public._agenda_rotulo(jsonb_build_object('curto', p ->> 'cliente_curto', 'numero', p ->> 'numero'), 'num');
  v_n      int := (p ->> 'linhas')::int;
  v_item   text := case when v_n = 1 then format('"%s"', public._agenda_linha_curta(p ->> 'linha_unica')) else 'o material' end;
  v_aprov  date := (p ->> 'aprovada_em')::date;
  v_pri    date := (p ->> 'primeira_compra')::date;
  v_ult    date := (p ->> 'ultima_compra')::date;
  v_cheg   date := (p ->> 'ultima_chegada')::date;
  v_ini    date := (p ->> 'inicio')::date;
  v_mao    boolean := coalesce((p ->> 'material_na_mao')::boolean, false);
  v_sem    int := coalesce((p ->> 'linhas_sem_compra')::int, 0);
  v_du     int;
  v_l      text[] := array['aprovada ' || public._dia_curto(v_aprov)];
begin
  -- a compra
  if v_pri is null then
    v_l := v_l || case when v_mao then 'na mão sem compra registrada'
                       else format('nada comprado ainda (%s desde a aprovação)', public._agenda_plural(p_hoje - v_aprov, 'dia', 'dias')) end;
  elsif v_n = 1 or (v_pri = v_ult and v_sem = 0) then
    v_l := v_l || format('%s comprado %s (%s)', v_item, public._dia_curto(v_pri),
                         public._agenda_dias_depois((p ->> 'dias_ate_comprar')::int, 'da aprovação'));
  elsif v_pri = v_ult then
    v_l := v_l || format('a 1ª compra %s (%s)', public._dia_curto(v_pri),
                         public._agenda_dias_depois((p ->> 'dias_ate_comprar')::int, 'da aprovação'));
  else
    v_l := v_l || format('a 1ª compra %s (%s), a última %s', public._dia_curto(v_pri),
                         public._agenda_dias_depois((p ->> 'dias_ate_comprar')::int, 'da aprovação'), public._dia_curto(v_ult));
  end if;
  if v_pri is not null and v_sem > 0 then
    v_l[cardinality(v_l)] := v_l[cardinality(v_l)] || format(', %s', public._agenda_plural(v_sem, 'item ainda sem compra', 'itens ainda sem compra'));
  end if;
  -- a chegada (só com tudo na mão) e o parado
  if v_mao and v_cheg is not null then
    if v_ult is not null then
      v_du := (p ->> 'du_do_fornecedor')::int;
      v_l := v_l || format('%s %s (%s)', case when v_n = 1 then 'chegou' else 'o último chegou' end, public._dia_curto(v_cheg),
                           case when coalesce(v_du, 0) <= 0 then 'no mesmo dia da compra'
                                else public._agenda_plural(v_du, 'dia útil', 'dias úteis') || ' depois da compra' end);
    else
      v_l := v_l || ('na mão desde ' || public._dia_curto(v_cheg));
    end if;
    v_du := (p ->> 'du_parada')::int;
    if v_ini is not null then
      v_l := v_l || case when v_ini <= v_cheg then 'começou ' || public._dia_curto(v_ini)
                         else format('começou %s (%s depois de chegar)', public._dia_curto(v_ini),
                                     public._agenda_plural(v_du, 'dia útil', 'dias úteis')) end;
    elsif coalesce((p ->> 'na_carteira')::boolean, true) then
      v_l := v_l || case when coalesce(v_du, 0) = 0 then 'ainda não começou (o material chegou hoje)'
                         else format('ainda não começou: parado há %s com o material na mão',
                                     public._agenda_plural(v_du, 'dia útil', 'dias úteis')) end;
    end if;
  elsif v_pri is not null and v_sem = 0 then
    v_l := v_l || 'ainda não chegou tudo'::text;
  end if;
  return v_quem || ': ' || array_to_string(v_l, '; ') || '.';
end;
$function$;

comment on function public._agenda_espera_texto(jsonb, date) is
  'Agenda de Produção (Fase 4, P6): a espera de peça de uma OS numa frase — "Flávio (OS-00104): aprovada ter 22/09; "Compressor 12V de…" comprado ter 13/10 (21 dias depois); chegou qua 14/10 (1 dia útil depois da compra); ainda não começou: parado há 12 dias úteis com o material na mão." (sem compra: "nada comprado ainda (93 dias desde a aprovação)"; várias linhas: "a 1ª compra …, a última …"; com início: "começou …").';

-- A espera de peça para quem lê (agenda_ver foco compras, o painel): {os:[{… a linha, texto}], mediana_ate_comprar_90d,
-- texto}. Com p_os: só ela (texto = a frase dela). Sem: texto = "Tempo até comprar: …" das OS da carteira e a mediana.
create or replace function public.agenda_espera_de_peca(p_os uuid default null, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := (select auth.uid());
  r       record;
  v_j     jsonb;
  v_os    jsonb := '[]'::jsonb;
  v_med   numeric;
  v_itens text[] := '{}';
  v_nomes text[];
  v_nome  text;
  v_pri   boolean := true;
  v_txt   text;
begin
  if p_hoje is null then
    raise exception 'agenda_espera_de_peca: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  -- os nomes que se repetem entre as OS da carteira (a frase leva o número só para elas)
  select coalesce(array_agg(x.cliente_curto), '{}') into v_nomes
    from (select y.cliente_curto from public._agenda_espera_linhas(p_hoje) y where y.na_carteira
           group by y.cliente_curto having count(*) > 1) x;
  for r in select * from public._agenda_espera_linhas(p_hoje) x where p_os is null or x.service_order_id = p_os loop
    v_j := to_jsonb(r) - 'linha_unica';
    v_txt := public._agenda_espera_texto(to_jsonb(r), p_hoje);
    v_os := v_os || (v_j || jsonb_build_object('texto', v_txt));
    continue when not r.na_carteira or p_os is not null;
    v_nome := case when r.cliente_curto is null or r.cliente_curto = any (v_nomes)
                   then concat_ws(' ', r.cliente_curto, '(' || r.numero || ')') else r.cliente_curto end;
    if r.primeira_compra is not null then
      v_itens := v_itens || format('%s %s', v_nome,
                                   case when v_pri then public._agenda_dias_depois(r.dias_ate_comprar, 'da aprovação')
                                                        || case when r.dias_ate_comprar > 0 then ' da aprovação' else '' end
                                        else replace(public._agenda_dias_depois(r.dias_ate_comprar, 'da aprovação'), ' depois', '') end);
      v_pri := false;
    elsif not r.material_na_mao and r.status not in ('draft', 'awaiting_client') then
      -- (o orçamento e a OS parada no cliente ainda não têm por que comprar: ficam fora do "ainda não comprou")
      v_itens := v_itens || format('%s ainda não comprou (%s)', v_nome, public._agenda_plural(p_hoje - r.aprovada_em, 'dia', 'dias'));
    end if;
  end loop;
  -- a mediana da aprovação à 1ª compra das OS aprovadas nos últimos 90 dias que já compraram (a régua da agenda_saude)
  select percentile_cont(0.5) within group (order by x.dias_ate_comprar) into v_med
    from public._agenda_espera_linhas(p_hoje) x
   where x.aprovada_em between p_hoje - 90 and p_hoje and x.primeira_compra is not null;
  if p_os is not null then
    v_txt := v_os -> 0 ->> 'texto';
  elsif cardinality(v_itens) > 0 then
    v_txt := 'Tempo até comprar: ' || public._agenda_lista(v_itens, 8) || '.'
             || coalesce(format(' Mediana dos aprovados nos últimos 90 dias: %s.',
                                public._agenda_plural(round(v_med)::int, 'dia', 'dias')), '');
  end if;
  return jsonb_build_object('os', v_os, 'mediana_ate_comprar_90d', v_med, 'texto', v_txt);
end;
$function$;

comment on function public.agenda_espera_de_peca(uuid, date) is
  'Agenda de Produção (Fase 4, P6): a espera de peça — {os:[{service_order_id, numero, cliente_curto, status, na_carteira, aprovada_em, primeira_compra, ultima_compra, ultima_chegada, inicio, material_na_mao, dias_ate_comprar, du_ate_comprar, dias_do_fornecedor, du_do_fornecedor, dias_parada, du_parada, linhas, linhas_sem_compra, texto}], mediana_ate_comprar_90d (mediana dos dias corridos da aprovação à 1ª compra das OS aprovadas nos últimos 90 dias que já compraram), texto}. Com p_os: só ela, e texto = a frase dela (_agenda_espera_texto). Sem: texto = "Tempo até comprar: Flávio 21 dias depois da aprovação, Nelson 9 dias e Vanderlei ainda não comprou (93 dias). Mediana dos aprovados nos últimos 90 dias: 15 dias." (as OS da carteira — o "ainda não comprou" sem o orçamento e a OS parada no cliente; o nome que se repete leva o número). STABLE, invoker; com login, só administrador e financeiro (senão 42501).';

-- ── 2. O foco compras ──────────────────────────────────────────────────────────────────────────────────

-- O material de UMA OS para o foco compras, a partir da prontidão (os_prontidao: os itens críticos com o texto de sempre)
-- e da espera (agenda_espera_de_peca): "4 itens a comprar, nada comprado desde a aprovação (qua 29/07, há 93 dias). Compre
-- até sex 30/10 para começar ter 03/11." / ""Central de controle…" chega sex 30/10 (pela nota 51038 da Kamell); "Painel
-- Touch de…" chega qua 04/11 (você disse); 2 itens sem fornecedor: de quem e quando?". O material todo na mão e parado:
-- "material na mão desde qua 14/10, parado há 12 dias úteis; começa ter 03/11". null = nada a dizer.
create or replace function public._agenda_compras_da_os(p_p jsonb, p_esp jsonb, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_itens   jsonb := coalesce(p_p #> '{material,itens}', '[]'::jsonb);
  v_comprar text[];
  v_semf    text[];
  v_semp    text[];
  v_vindo   text[];
  v_partes  text[] := '{}';
  v_ca      date;
  v_ini     date := coalesce((p_p #>> '{plano,inicio}')::date, (p_p #>> '{marcada,de}')::date);
  v_txt     text;
  v_fim     text;
begin
  if not coalesce((p_p ->> 'ok')::boolean, false) then
    return null;
  end if;
  -- a comprar com fornecedor e prazo (níveis D): conta; sem fornecedor: conta, e a pergunta; com fornecedor sem prazo: um a
  -- um, com o texto da prontidão
  select array_agg(i ->> 'curto' order by o) filter (where i ->> 'situacao' = 'falta' and i ->> 'nivel' = 'D'),
         array_agg(i ->> 'curto' order by o) filter (where i ->> 'situacao' = 'falta' and i ->> 'nivel' = 'E'
                                                       and i ->> 'fornecedor' is null),
         array_agg(format('"%s" %s', i ->> 'curto', i ->> 'data_texto') order by o)
           filter (where i ->> 'situacao' = 'falta' and i ->> 'nivel' = 'E' and i ->> 'fornecedor' is not null),
         -- comprado ou a caminho: a chegada com a fonte; a da nota diz qual nota
         array_agg(format('"%s" ', i ->> 'curto')
                   || case when m.remessa_id is not null and i ->> 'nivel' = 'B' and i ->> 'previsao_fonte' = 'nfe'
                           then format('chega %s (pela %s)', public._dia_curto((i ->> 'data')::date),
                                       coalesce(public._agenda_remessa_nota(m.remessa_id), 'nota'))
                           else i ->> 'data_texto' end
                   order by o) filter (where i ->> 'situacao' in ('comprado', 'a_caminho'))
    into v_comprar, v_semf, v_semp, v_vindo
    from jsonb_array_elements(v_itens) with ordinality t(i, o)
    left join public.os_material m on m.id = (i ->> 'id')::uuid
   where coalesce((i ->> 'critico')::boolean, true);

  if cardinality(v_comprar) > 0 then
    v_txt := case when cardinality(v_comprar) = 1 then format('"%s" a comprar', v_comprar[1])
                  else format('%s itens a comprar', cardinality(v_comprar)) end;
    if p_esp is not null and p_esp ->> 'primeira_compra' is null then
      v_txt := v_txt || format(', nada comprado desde a aprovação (%s, há %s)', public._dia_curto((p_esp ->> 'aprovada_em')::date),
                               public._agenda_plural(p_hoje - (p_esp ->> 'aprovada_em')::date, 'dia', 'dias'));
    end if;
    v_partes := v_partes || v_txt;
  end if;
  v_partes := v_partes || coalesce(v_vindo, '{}') || coalesce(v_semp, '{}');
  if cardinality(v_semf) > 0 then
    v_partes := v_partes || case when cardinality(v_semf) = 1 then format('"%s" sem fornecedor: de quem e quando?', v_semf[1])
                                 else format('%s itens sem fornecedor: de quem e quando?', cardinality(v_semf)) end;
  end if;

  if cardinality(v_partes) = 0 then
    -- tudo na mão: só a espera (chegou e ainda não começou)
    if p_esp is not null and coalesce((p_esp ->> 'material_na_mao')::boolean, false) and p_esp ->> 'inicio' is null
       and coalesce((p_esp ->> 'du_parada')::int, 0) > 0 then
      return format('material na mão desde %s, parado há %s', public._dia_curto((p_esp ->> 'ultima_chegada')::date),
                    public._agenda_plural((p_esp ->> 'du_parada')::int, 'dia útil', 'dias úteis'))
             || coalesce('; começa ' || public._dia_curto(v_ini), '') || '.';
    end if;
    return null;
  end if;

  v_txt := array_to_string(v_partes, '; ');
  -- o "compre até" da prontidão (programação para trás): só a restrição de compre_ate, com o dia de começar
  v_ca := (select (e ->> 'compre_ate')::date from jsonb_array_elements(coalesce(p_p -> 'restricoes', '[]'::jsonb)) e
            where e ->> 'tipo' = 'compre_ate' limit 1);
  if v_ca is not null then
    v_fim := case when v_ca >= p_hoje then 'Compre até ' || public._dia_curto(v_ca) || coalesce(' para começar ' || public._dia_curto(v_ini), '')
                  else 'Já passou do dia de comprar (' || public._dia_curto(v_ca) || ')' || coalesce(' para começar ' || public._dia_curto(v_ini), '') end
             || '.';
  end if;
  return v_txt || case when right(v_txt, 1) = '?' then '' else '.' end || coalesce(' ' || v_fim, '');
end;
$function$;

comment on function public._agenda_compras_da_os(jsonb, jsonb, date) is
  'Agenda de Produção (Fase 4, P6): o material de uma OS para o foco compras, a partir da prontidão (p_p, os itens críticos) e da linha da espera (p_esp, de agenda_espera_de_peca): os a comprar (nível D) contados, com "nada comprado desde a aprovação (…, há N dias)" quando a OS não comprou nada; o comprado/a caminho com a chegada e a fonte (a da nota diz qual: "pela nota 51038 da Kamell"); o fornecedor sem prazo um a um; os sem fornecedor contados, com "de quem e quando?"; e "Compre até … para começar …" (a restrição compre_ate). Tudo na mão e sem início: "material na mão desde …, parado há N dias úteis; começa …". null = nada a dizer.';

-- A pergunta ao fornecedor (agenda_fornecedor_mensagens) para o dono ler: "eu teria perguntado à Aliexpress, qua 28/10, se a
-- entrega de "Painel Touch de…" do Nelson continua para qua 04/11" (sombra), "perguntei à …" (saiu), "vou perguntar à …"
-- (na fila), "a pergunta à … de … não saiu" (falhou), "não perguntei à …, …, se … (sem conversa com a HBR nos últimos 90
-- dias)" (recusada). A previsão é a de agora da linha; sem ela, "qual a previsão de entrega de …".
create or replace function public._agenda_fornecedor_frase(p_msg uuid, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  x      public.agenda_fornecedor_mensagens%rowtype;
  v_q    record;
  v_quem text;
  v_item text;
  v_dia  date;
  v_se   text;
  v_mot  text;
  cf     public.agenda_config := public._agenda_cfg();
begin
  select * into x from public.agenda_fornecedor_mensagens where id = p_msg;
  if not found then
    return null;
  end if;
  v_quem := coalesce(public._agenda_fornecedor_curto(x.fornecedor_id), 'o fornecedor');
  v_dia := (x.enviar_em at time zone 'America/Sao_Paulo')::date;
  select m.descricao, m.previsao_ate, coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente
    into v_q
    from public.os_material m
    left join public.service_orders so on so.id = m.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where m.id = x.os_material_id;
  v_item := coalesce(public._agenda_linha_curta(v_q.descricao), 'material');
  v_se := case when v_q.previsao_ate is not null
               then format('se a entrega de "%s" do %s continua para %s', v_item, v_q.cliente, public._dia_curto(v_q.previsao_ate))
               else format('qual a previsão de entrega de "%s" do %s', v_item, v_q.cliente) end;
  if x.estado = 'recusada' then
    v_mot := case x.recusa_motivo
      when 'teto' then 'já tinha perguntado o bastante a ele'
      when 'janela' then 'fora do horário'
      when 'fim_de_semana' then 'fim de semana'
      when 'domingo' then 'domingo'
      when 'sem_telefone' then 'sem telefone no cadastro'
      when 'opt_out' then 'ele pediu para não receber mensagem'
      when 'sem_conversa' then format('sem conversa com a HBR nos últimos %s dias', cf.fornecedor_conversa_dias)
      when 'modo' then 'a pergunta ao fornecedor foi desligada'
      -- C1 da revisão: a pergunta que ficou velha antes de sair (a peça chegou, mudou a previsão, a OS saiu da carteira)
      when 'desatualizada' then 'o material mudou antes de a pergunta sair'
      else x.recusa_motivo end;
    return format('não perguntei à %s, %s, %s (%s)', v_quem, public._dia_curto(v_dia), v_se, v_mot);
  end if;
  if x.modo = 'sombra' or x.estado = 'registrada' then
    return format('eu %s à %s, %s, %s', case when v_dia <= p_hoje then 'teria perguntado' else 'perguntaria' end,
                  v_quem, public._dia_curto(v_dia), v_se);
  end if;
  select q.status, q.sent_at into v_q from public.whatsapp_send_queue q where q.id = x.fila_id;
  if v_q.sent_at is not null then
    return format('perguntei à %s, %s, %s', v_quem,
                  public._dia_curto((v_q.sent_at at time zone 'America/Sao_Paulo')::date), v_se);
  end if;
  if v_q.status in ('failed', 'cancelled') then
    return format('a pergunta à %s de %s não saiu (%s)', v_quem, public._dia_curto(v_dia), v_se);
  end if;
  if v_dia < p_hoje then
    return format('a pergunta à %s de %s ainda não saiu (%s)', v_quem, public._dia_curto(v_dia), v_se);
  end if;
  return format('vou perguntar à %s, %s, %s', v_quem, public._dia_curto(v_dia), v_se);
end;
$function$;

comment on function public._agenda_fornecedor_frase(uuid, date) is
  'Agenda de Produção (Fase 4, P6): a pergunta ao fornecedor (uma linha de agenda_fornecedor_mensagens) para o dono ler — em teste "eu teria perguntado à Aliexpress, qua 28/10, se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11" (o dia ainda não chegou: "eu perguntaria"); ligado: "perguntei à …" (saiu, pela fila), "vou perguntar à …" (na fila, o dia não passou; passou: "ainda não saiu"), "a pergunta à … não saiu" (falhou); recusada: "não perguntei à …, …, se … (o motivo)". A previsão é a de agora da linha. Sem valor, sem OS e sem link: só o que a mensagem perguntou.';

-- O foco compras (spec §5.6). Sem OS, cinco blocos, até texto_max (os serviços saem do fim com "• e mais N"; o resto, pela
-- linha): (1) por OS da fila (a agenda executável, sem orçamento) com material fora de A — o que falta, "compre até", o que
-- está a caminho e de onde — e as de material na mão paradas; (2) as notas a caminho sem a palavra do dono; (3) o tempo até
-- comprar (agenda_espera_de_peca); (4) a pergunta ao fornecedor da semana (sombra: "em teste"); (5) o detector em teste
-- (agenda_detector_precisao). Com OS: a espera dela (os 3 componentes), o material e as perguntas ao fornecedor dela.
create or replace function public._agenda_ver_compras(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid    uuid := (select auth.uid());
  c        public.agenda_config;
  v_pn     jsonb;
  e        jsonb;
  v_p      jsonb;
  v_esp    jsonb;
  v_ep     jsonb;
  v_linha  text;
  v_itens  text[] := '{}';
  v_cauda  text[] := '{}';
  v_prio   int[] := '{}';
  v_resto  text[];
  v_corte  int;
  v_cab    text;
  v_fora   int := 0;
  v_rem    text[];
  v_nrem   int;
  v_msgs   text[];
  v_prec   jsonb;
  v_linhas text[];
  v_n      int;
  k        int;
  v_t      text;
  v_rot    text;
begin
  if p_hoje is null then
    raise exception '_agenda_ver_compras: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  c := public._agenda_cfg();
  v_esp := public.agenda_espera_de_peca(null, p_hoje);

  if p_os is not null then
    v_p := public.os_prontidao(p_os, p_hoje);
    if not coalesce((v_p ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
    end if;
    v_rot := public._agenda_rotulo(jsonb_build_object('curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero'), 'num');
    select x into v_ep from jsonb_array_elements(v_esp -> 'os') x where (x ->> 'service_order_id')::uuid = p_os;
    v_cab := coalesce(v_ep ->> 'texto', v_rot || ': sem material registrado para comprar.');
    -- o material que falta ou vem (o de tudo na mão já está na frase da espera)
    v_linha := public._agenda_compras_da_os(v_p, v_ep, p_hoje);
    if v_linha is not null and not coalesce((v_ep ->> 'material_na_mao')::boolean, false) then
      v_itens := v_itens || ('• Material: ' || v_linha);
    end if;
    v_msgs := array(select '• Ao fornecedor' || case when x.modo = 'sombra' then ' (em teste): ' else ': ' end
                           || public._agenda_fornecedor_frase(x.id, p_hoje) || '.'
                      from public.agenda_fornecedor_mensagens x
                     where x.service_order_id = p_os
                       and (x.enviar_em at time zone 'America/Sao_Paulo')::date between p_hoje - 6 and p_hoje + 7
                     order by x.enviar_em, x.terco, x.id
                     limit 3);
    v_linhas := array[v_cab] || v_itens || v_msgs;
    return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
      'dados', jsonb_build_object('numero', v_p ->> 'numero', 'espera', v_ep, 'material', v_p -> 'material'));
  end if;

  -- (1) os serviços da fila: o que falta e o que vem; os de material na mão parados
  v_pn := public._agenda_painel(p_hoje);
  for e in select x from jsonb_array_elements(v_pn -> 'oss') x
            where not coalesce((x ->> 'eh_orc')::boolean, false)
            order by (x ->> 'ordem')::int loop
    if not coalesce((e ->> 'executavel')::boolean, false) then
      if e ->> 'mat_estado' <> 'completo' then v_fora := v_fora + 1; end if;
      continue;
    end if;
    select x into v_ep from jsonb_array_elements(v_esp -> 'os') x where (x ->> 'service_order_id')::uuid = (e ->> 'os')::uuid;
    continue when e ->> 'mat_estado' = 'completo' and v_ep is null;
    v_linha := public._agenda_compras_da_os(e -> 'p', v_ep, p_hoje);
    continue when v_linha is null;
    v_itens := v_itens || ('• ' || public._agenda_rotulo(e, 'num') || ': ' || v_linha);
  end loop;
  v_cab := format('Compras (%s):', public._dia_curto(p_hoje));
  if cardinality(v_itens) = 0 then
    v_cab := v_cab || ' nada a comprar para os serviços da fila.';
  end if;
  -- A cauda, com o peso de cada linha para caber no teto (maior = sai por último): as notas 5, o tempo até comprar 4, a
  -- pergunta ao fornecedor 3, o parado no cliente 2, o detector 1.
  if v_fora > 0 then
    v_cauda := v_cauda || case when v_fora = 1 then 'Não conto 1 parado no cliente.'
                               else format('Não conto %s parados no cliente.', v_fora) end;
    v_prio := v_prio || 2;
  end if;

  -- (2) as notas que chegaram por e-mail sem a palavra do dono (a mais antiga primeiro; até 3)
  select array_agg(t.txt order by t.d, t.id), count(*) into v_rem, v_nrem
    from (select r.id, r.despacho_em as d,
                 public._agenda_remessa_nota(r.id) || ' (' || public._dia_curto(r.despacho_em) || ')' as txt
            from public.material_remessas r
           where r.vinculo = 'sem_resposta' and r.estado <> 'descartada') t;
  if v_nrem = 1 then
    v_cauda := v_cauda || format('Não sei de qual serviço é a %s: me diga, ou se não é de serviço.', v_rem[1]);
    v_prio := v_prio || 5;
  elsif v_nrem > 1 then
    v_cauda := v_cauda || format('Não sei de qual serviço são: %s. Me diga, ou se não são de serviço.', public._agenda_lista(v_rem, 3));
    v_prio := v_prio || 5;
  end if;

  -- (3) o tempo até comprar
  if nullif(v_esp ->> 'texto', '') is not null then
    v_cauda := v_cauda || (v_esp ->> 'texto');
    v_prio := v_prio || 4;
  end if;

  -- (4) a pergunta ao fornecedor da semana (a de 7 dias para trás até 7 para frente; até 3)
  v_msgs := array(select 'Ao fornecedor' || case when x.modo = 'sombra' then ' (em teste): ' else ': ' end
                         || public._agenda_fornecedor_frase(x.id, p_hoje) || '.'
                    from public.agenda_fornecedor_mensagens x
                   where (x.enviar_em at time zone 'America/Sao_Paulo')::date between p_hoje - 6 and p_hoje + 7
                   order by x.enviar_em, x.terco, x.id
                   limit 3);
  if cardinality(v_msgs) = 0 and c.modo_fornecedor <> 'desligado' then
    v_msgs := array['Ao fornecedor' || case when c.modo_fornecedor = 'sombra' then ' (em teste)' else '' end
                    || ': nenhuma pergunta nesta semana.'];
  end if;
  if cardinality(v_msgs) > 0 then
    v_cauda := v_cauda || v_msgs;
    v_prio := v_prio || array_fill(3, array[cardinality(v_msgs)]);
  end if;

  -- (5) o detector em teste: o que ele leu das conversas do fornecedor em 14 dias e quanto acertou
  if c.modo_detector = 'sombra' then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
    v_cauda := v_cauda || ('Leitura das conversas (em teste): '
      || case when coalesce((v_prec ->> 'mensagens')::int, 0) = 0
              then 'nenhuma mensagem de fornecedor com prazo em 14 dias.'
              else format('li %s de fornecedor com prazo em 14 dias: %s.',
                          public._agenda_plural((v_prec ->> 'mensagens')::int, 'mensagem', 'mensagens'),
                          case when coalesce((v_prec ->> 'julgados')::int, 0) = 0 then 'nenhuma deu para conferir ainda'
                               else format('acertei %s de %s que deu para conferir', v_prec ->> 'certos', v_prec ->> 'julgados') end) end
      || case when coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false) then ' Já dá para ligar, com o seu OK.' else '' end);
    v_prio := v_prio || 1;
  end if;

  -- Cabe no teto: primeiro saem da cauda o detector e o parado no cliente; depois os serviços do fim ("• e mais N", nunca no
  -- meio de uma linha); só então, se nem assim couber, as outras linhas da cauda (a pergunta ao fornecedor, o tempo, as notas).
  v_n := cardinality(v_itens);
  <<cabe>>
  for v_corte in 0 .. 5 loop
    v_resto := array(select t.l from unnest(v_cauda, v_prio) with ordinality t(l, p, o) where t.p > v_corte order by t.o);
    for k in reverse v_n .. case when v_corte < 2 then v_n else 0 end loop
      v_linhas := array[v_cab] || v_itens[1:k]
                  || case when k < v_n then array[format('• e mais %s', v_n - k)] else '{}'::text[] end
                  || v_resto;
      v_t := public._agenda_juntar(v_linhas, null);
      exit cabe when char_length(v_t) <= c.texto_max;
    end loop;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
    'dados', jsonb_build_object('servicos', v_n, 'notas_sem_resposta', coalesce(v_nrem, 0),
                                'mediana_ate_comprar_90d', v_esp -> 'mediana_ate_comprar_90d',
                                'modos', jsonb_build_object('material', c.modo_material, 'detector', c.modo_detector,
                                                            'fornecedor', c.modo_fornecedor)));
end;
$function$;

comment on function public._agenda_ver_compras(uuid, date) is
  'Agenda de Produção (Fase 4, P6): agenda_ver foco compras. Sem OS, até texto_max: "Compras (sex 30/10):", uma linha por serviço da fila (sem orçamento) com material fora de A (_agenda_compras_da_os: o que falta, "nada comprado desde a aprovação", "Compre até … para começar …", o que vem e de onde, "de quem e quando?") e os de material na mão parados; "Não conto N parados no cliente."; as notas sem a palavra do dono ("Não sei de qual serviço é a nota 812 da Correa (qui 29/10): …"); o tempo até comprar (agenda_espera_de_peca); a pergunta ao fornecedor da semana (_agenda_fornecedor_frase; sombra "Ao fornecedor (em teste): eu teria perguntado …"); em sombra do detector, "Leitura das conversas (em teste): …" (agenda_detector_precisao). Com OS (também a concluída): a frase da espera (os 3 componentes), "• Material: …" e as perguntas ao fornecedor dela. Os serviços saem do fim com "• e mais N"; o resto, pela linha. Definer (lê a fila do WhatsApp e as perguntas ao fornecedor por inteiro): com login, só administrador e financeiro (senão 42501). {ok, texto, dados}.';

-- ── 3. O foco fornecedores ─────────────────────────────────────────────────────────────────────────────

-- Como a agenda conta a chegada do material dos fornecedores que importam (spec §5.6): os principais
-- (_agenda_fornecedores_principais: os de mais contas de material em 365 dias, até fornecedores_principais_max, e os de compra
-- viva, OC aberta ou nota a caminho) e os das linhas da carteira que ainda não estão na mão. Cada um com o prazo da fonte
-- única (_agenda_prazo_do_fornecedor), agrupado: "Você disse" (suppliers.modalidade), "Meu chute (pela cidade ou pelo
-- nome)" e "Falta você dizer" (sem lugar no cadastro; cadastro repetido), e a frase de como responder. O cadastro inativo
-- vale como o que ficou (o principal_id dele).
create or replace function public._agenda_ver_fornecedores(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid     uuid := (select auth.uid());
  c         public.agenda_config;
  c_ordem   constant text[] := array['balcao', 'entrega_local', 'distribuidor_sc_pr', 'outro_estado', 'marketplace', 'importacao'];
  r         record;
  v_id      uuid;
  v_pr      jsonb;
  v_lista   jsonb := '[]'::jsonb;
  v_vistos  uuid[] := '{}';
  v_grupos  text[] := '{}';
  v_disse   text[];
  v_chute   text[];
  v_falta   text[] := '{}';
  g         record;
  v_ex      text[];
  v_cab     text;
  v_pe      text;
  v_linhas  text[];
  v_n       int;
  k         int;
  v_t       text;
begin
  if p_hoje is null then
    raise exception '_agenda_ver_fornecedores: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  c := public._agenda_cfg();

  for r in
    select x.id, max(x.contas) as contas
      from (select p.fornecedor_id as id, p.contas from public._agenda_fornecedores_principais(p_hoje) p
            union all
            select m.fornecedor_id, 0
              from public.os_carteira(p_hoje) k
              join public.os_material m on m.service_order_id = k.service_order_id
             where m.fornecedor_id is not null and m.situacao in ('falta', 'comprado', 'a_caminho')) x
     group by x.id
     order by max(x.contas) desc, x.id
  loop
    v_id := r.id;
    v_pr := public._agenda_prazo_do_fornecedor(v_id);
    -- o cadastro que o dono já tirou de uso vale como o que ficou
    if not coalesce((select s.active from public.suppliers s where s.id = v_id), true) and v_pr ->> 'principal_id' is not null then
      v_id := (v_pr ->> 'principal_id')::uuid;
      v_pr := public._agenda_prazo_do_fornecedor(v_id);
    end if;
    continue when v_id = any (v_vistos);
    v_vistos := v_vistos || v_id;
    v_lista := v_lista || (jsonb_build_object(
      'fornecedor_id', v_id, 'nome', public._agenda_fornecedor_curto(v_id), 'contas', r.contas,
      'lugar', (select public._agenda_lugar_texto(s.city, s.state) from public.suppliers s where s.id = v_id),
      'sem_lugar_no_cadastro', (select nullif(btrim(coalesce(s.city, '')), '') is null and nullif(btrim(coalesce(s.state, '')), '') is null
                                  from public.suppliers s where s.id = v_id),
      'grupo', (select public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name)) from public.suppliers s where s.id = v_id),
      'frase', public._agenda_classe_texto(v_pr ->> 'classe', (v_pr ->> 'du')::int, (v_pr ->> 'corridos')::int))
      || v_pr);
  end loop;

  -- o rótulo: "Premel (Itajaí/SC)"; sem lugar, só o nome
  -- Você disse e o meu chute: uma linha por frase de prazo, na ordem das classes
  select array_agg(t.l order by t.o) into v_disse
    from (select '• ' || f.frase || ': ' || public._agenda_lista(array_agg(concat(f.nome, ' (' || f.lugar || ')') order by f.contas desc, f.nome), 6) || '.' as l,
                 min(array_position(c_ordem, f.classe)) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, contas int, classe text, fonte text, frase text)
           where f.fonte = 'dono' and f.classe is not null
           group by f.frase) t;
  select array_agg(t.l order by t.o, t.l) into v_chute
    from (select '• ' || f.frase || ': ' || public._agenda_lista(array_agg(concat(f.nome, ' (' || f.lugar || ')') order by f.contas desc, f.nome), 6) || '.' as l,
                 min(array_position(c_ordem, f.classe)) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, contas int, classe text, fonte text, frase text)
           where f.fonte in ('cidade', 'nome') and f.classe is not null
           group by f.frase) t;

  -- Falta você dizer: sem lugar no cadastro; o cadastro repetido (uma linha por nome, com os lugares e o que vale)
  for r in select * from jsonb_to_recordset(v_lista) f(nome text, lugar text, classe text, duvida text, grupo text,
                                                        sem_lugar_no_cadastro boolean, principal_id uuid)
            order by f.nome loop
    if r.duvida = 'duplicado' then
      continue when r.grupo = any (v_grupos);
      v_grupos := v_grupos || r.grupo;
      -- os cadastros ativos do mesmo nome (o que vale primeiro) e o lugar do que vale
      select count(*) as n,
             public._agenda_lista(array_agg(coalesce(public._agenda_lugar_texto(s.city, s.state), 'sem cidade')
                                            order by (s.id = r.principal_id) desc, s.id), 4) as lugares
        into g
        from public.suppliers s
       where coalesce(s.active, true)
         and public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name)) = r.grupo;
      v_pe := (select public._agenda_lugar_texto(p.city, p.state) from public.suppliers p where p.id = r.principal_id);
      v_falta := v_falta || case when v_pe is not null
        then format('• %s: cadastrada %s vezes (%s); conto pela de %s. É a mesma?', r.nome, g.n, g.lugares, v_pe)
        else format('• %s: cadastrada %s vezes (%s) e não sei qual vale. Qual é a certa?', r.nome, g.n, g.lugares) end;
    elsif r.classe is null then
      v_falta := v_falta || case when r.sem_lugar_no_cadastro then format('• %s: sem cidade no cadastro.', r.nome)
                                 else format('• %s: não sei onde fica (%s).', r.nome, r.lugar) end;
    end if;
  end loop;

  -- como responder: com dois nomes da lista ("a Premel eu pego no balcão", "a Toli chega em 3 dias úteis")
  v_ex := array(select f.nome from jsonb_to_recordset(v_lista) f(nome text, contas int, classe text, fonte text)
                 where f.classe is not null and coalesce(f.fonte, '') <> 'dono'
                 order by array_position(c_ordem, f.classe), f.contas desc, f.nome limit 2);
  v_pe := case when cardinality(v_ex) = 2
               then format('Pode ser um áudio só: "a %s eu pego no balcão", "a %s chega em 3 dias úteis".', v_ex[1], v_ex[2])
               else 'Pode ser um áudio só, do seu jeito: "eu pego no balcão", "chega em 3 dias úteis".' end;

  v_cab := 'Como eu conto a chegada do material dos fornecedores principais:';
  if jsonb_array_length(v_lista) = 0 then
    return jsonb_build_object('ok', true,
      'texto', 'Ainda não tenho fornecedor principal: nenhuma conta de material no último ano nem compra a caminho.',
      'dados', jsonb_build_object('fornecedores', v_lista));
  end if;
  -- Cabe no teto: o chute sai do fim ("• e mais N"), nunca o que falta você dizer.
  v_n := coalesce(cardinality(v_chute), 0);
  for k in reverse v_n .. 0 loop
    v_linhas := array[v_cab]
                || case when coalesce(cardinality(v_disse), 0) = 0 then array['Você disse: nenhum ainda.']
                        else array['Você disse:'] || v_disse end
                || case when v_n > 0 then array['Meu chute (pela cidade ou pelo nome):'] || v_chute[1:k]
                                          || case when k < v_n then array[format('• e mais %s', v_n - k)] else '{}'::text[] end
                        else '{}'::text[] end
                || case when cardinality(v_falta) > 0 then array['Falta você dizer:'] || v_falta else '{}'::text[] end
                || array[v_pe];
    v_t := public._agenda_juntar(v_linhas, null);
    exit when char_length(v_t) <= c.texto_max;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
    'dados', jsonb_build_object('fornecedores', v_lista, 'disse', coalesce(cardinality(v_disse), 0), 'chute', v_n,
                                'falta', cardinality(v_falta)));
end;
$function$;

comment on function public._agenda_ver_fornecedores(date) is
  'Agenda de Produção (Fase 4, P6): agenda_ver foco fornecedores — como a agenda conta a chegada do material dos fornecedores principais (_agenda_fornecedores_principais) e dos das linhas da carteira ainda não na mão, pela fonte única (_agenda_prazo_do_fornecedor): "Você disse:" (suppliers.modalidade; vazio: "Você disse: nenhum ainda."), "Meu chute (pela cidade ou pelo nome):" uma linha por prazo ("• entrega local, 1 dia útil: Premel (Itajaí/SC) e Souper (Itajaí/SC)"), "Falta você dizer:" (sem cidade no cadastro; cadastro repetido: "• Kamell: cadastrada 2 vezes (Vila Velha/ES e Itajaí/SC); conto pela de Vila Velha/ES. É a mesma?") e "Pode ser um áudio só: …" com dois nomes da lista. O inativo vale como o que ficou. Até texto_max (o chute sai do fim com "• e mais N"). Definer (lê os principais, que são só do service_role): com login, só administrador e financeiro (senão 42501). {ok, texto, dados:{fornecedores, disse, chute, falta}}.';

-- ── 4. O despacho único: agenda_ver (recriada, mesma assinatura) ────────────────────────────────────────
-- Corpo de 20261026100500 copiado (a definição mais nova); as mudanças estão marcadas "-- FASE 4:" (fora dos blocos, só
-- saem as 5 linhas da conferência do foco, que entram ampliadas no 1º bloco).

create or replace function public.agenda_ver(p_autor uuid default null, p_periodo text default null,
                                             p_pessoa text default null, p_foco text default null, p_os text default null,
                                             p_simular jsonb default null, p_simular_aprovacao boolean default false,
                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_foco    text := coalesce(nullif(btrim(lower(p_foco)), ''), 'tudo');
  v_rp      jsonb;
  v_payee   uuid;
  v_eh_dono boolean := true;
  v_de      date;
  v_ate     date;
  v_ro      jsonb;
  v_r       jsonb;
  v_pn      jsonb;
  v_rota    text;
  v_max     int;
  v_l       text[];
  k         int;
  -- FASE 2: a hora de agora (desfazer ainda vale? a decisão venceu?). now(); a bancada fixa com agenda.agora.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  -- FASE 3: o livre de verdade (a simulação do motor) e o mês da comissão
  v_lv      jsonb;
  v_mes     date;
begin
  -- FASE 2: os focos decisoes, mudancas e plano
  -- FASE 3: os focos ppc, diarias, marcos, comissao e equipe
  -- FASE 4: os focos compras e fornecedores (a conferência e a mensagem com os 17)
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras ou fornecedores)', p_foco
      using errcode = '22023';
  end if;
  -- FASE 4: fim
  if p_hoje is null then
    raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Desligada (agenda_config.modo_leitura), a agenda de produção não responde: o assistente volta à agenda de antes
  -- (my_agenda: tarefas e compromissos do dono). Quem não lê agenda_config continua recebendo erro (nunca "livre").
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                              'texto', 'A agenda de produção está desligada agora.');
  end if;

  -- Pessoa: "eu" ou o nome. Quem não existe ou é ambíguo volta a frase do resolvedor (nunca um erro cru).
  if nullif(btrim(p_pessoa), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'rota', 'pessoa', 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto',
                                'opcoes', coalesce(v_rp -> 'opcoes', '[]'::jsonb));
    end if;
    v_payee := (v_rp ->> 'payee_id')::uuid;
    v_eh_dono := coalesce((v_rp ->> 'eh_dono')::boolean, false);
  end if;

  -- Período: hoje, amanhã, semana, próxima semana ou o que o dono disse.
  -- FASE 3: a comissão lê o mês ("outubro", "mês passado"), não um período de dias.
  if v_foco = 'comissao' then
    begin
      v_mes := public._agenda_mes_dito(p_periodo, p_hoje);
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  else
    begin
      select x.de, x.ate into v_de, v_ate from public._agenda_periodo(p_periodo, p_hoje) x;
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  end if;

  if coalesce(p_simular_aprovacao, false) and nullif(btrim(p_os), '') is null then
    return jsonb_build_object('ok', false, 'rota', 'ctp',
      'texto', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).',
      'pergunta', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).');
  end if;

  if nullif(btrim(p_os), '') is not null then
    v_ro := public.agenda_resolver_os(p_os, p_hoje, coalesce(p_simular_aprovacao, false));
    if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
      return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    if coalesce(p_simular_aprovacao, false) then
      v_rota := 'ctp';
      v_r := public.agenda_ctp((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 3: os marcos da OS (dentro ou fora da carteira: a concluída e a entregue já saíram dela)
    elsif v_foco = 'marcos' then
      v_rota := 'marcos';
      v_r := public._agenda_ver_marcos((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 4: as compras e a espera de peça da OS (também fora da carteira: a concluída nos últimos 180 dias); os
    -- fornecedores não são de uma OS
    elsif v_foco = 'compras' then
      v_rota := 'compras_os';
      v_r := public._agenda_ver_compras((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_foco = 'fornecedores' then
      v_rota := 'fornecedores';
      v_r := public._agenda_ver_fornecedores(p_hoje);
    -- FASE 4: fim
    elsif v_ro ->> 'status' = 'fora_da_carteira' then
      v_rota := 'os';
      v_r := jsonb_build_object('ok', true, 'texto', v_ro ->> 'texto', 'dados', jsonb_build_object('numero', v_ro ->> 'numero'));
    elsif v_foco = 'material' then
      v_rota := 'material_os';
      v_r := public.agenda_ver_material((v_ro ->> 'id')::uuid, p_hoje);
    else
      v_rota := 'os';
      v_r := public._agenda_ver_os((v_ro ->> 'id')::uuid, p_hoje);
    end if;
  -- FASE 3: os marcos pedem a OS
  elsif v_foco = 'marcos' then
    return jsonb_build_object('ok', false, 'rota', 'marcos',
      'texto', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).',
      'pergunta', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).');
  elsif p_simular is not null and jsonb_typeof(p_simular) = 'object' then
    v_rota := 'simular';
    v_r := public.agenda_simular((p_simular ->> 'dias')::numeric, coalesce(p_simular -> 'com_quem', '[]'::jsonb),
                                 nullif(p_simular ->> 'dono', ''), p_autor, p_hoje);
  -- FASE 2: o que espera o dono, o que mudou sozinho e o plano publicado
  elsif v_foco = 'decisoes' then
    v_rota := 'decisoes';
    v_r := public._agenda_ver_decisoes(p_hoje, v_agora);
  elsif v_foco = 'mudancas' then
    v_rota := 'mudancas';
    v_r := public._agenda_ver_mudancas(p_hoje, v_agora);
  elsif v_foco = 'plano' then
    v_rota := 'plano';
    v_r := public._agenda_ver_plano(v_de, v_ate, p_hoje, v_agora);
  -- FASE 3: a semana medida, as diárias da agenda, a comissão do mês e o que a equipe respondeu
  elsif v_foco = 'ppc' then
    v_rota := 'ppc';
    v_r := public._agenda_ver_ppc(v_de, p_hoje);
  elsif v_foco = 'diarias' then
    v_rota := 'diarias';
    v_r := public._agenda_ver_diarias(v_de, v_ate, p_hoje);
  elsif v_foco = 'comissao' then
    v_rota := 'comissao';
    v_r := public._agenda_ver_comissao(v_mes, p_hoje);
  elsif v_foco = 'equipe' then
    v_rota := 'equipe';
    v_r := public._agenda_ver_equipe(p_hoje);
  -- FASE 4: o que comprar e até quando, as notas, o tempo até comprar e a pergunta ao fornecedor; como conto o prazo de
  -- cada fornecedor
  elsif v_foco = 'compras' then
    v_rota := 'compras';
    v_r := public._agenda_ver_compras(null, p_hoje);
  elsif v_foco = 'fornecedores' then
    v_rota := 'fornecedores';
    v_r := public._agenda_ver_fornecedores(p_hoje);
  -- FASE 4: fim
  elsif v_foco = 'o_que_fazer' then
    if v_payee is not null and not v_eh_dono then
      v_rota := 'dia_da_pessoa';
      v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
    else
      v_rota := 'o_que_fazer';
      v_r := public.agenda_o_que_fazer(coalesce(v_payee, public._agenda_dono(p_autor)), p_hoje);
    end if;
  elsif v_foco in ('atrasos', 'riscos') then
    v_rota := 'atrasos';
    v_r := public.agenda_atrasos(p_hoje);
  elsif v_foco = 'material' then
    v_rota := 'material';
    v_r := public.agenda_ver_material(null, p_hoje);
  elsif v_foco = 'livre' then
    v_rota := 'livre';
    v_r := public.agenda_semana(null, null, p_hoje);
    -- FASE 3: com a agenda automática ligada, o livre de verdade sai da simulação do motor (fora disso, a projeção)
    if (public._agenda_cfg()).modo_proposta = 'ligado' then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
    end if;
    v_r := jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[v_r #>> '{dados,textos,resumo}',
                                           case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto'
                                                else v_r #>> '{dados,textos,livre}' end],
                                     (select texto_max from public._agenda_cfg())),
      'dados', jsonb_build_object('fila', v_r #> '{dados,fila}', 'livre', v_r #> '{dados,livre}',
                                  'capacidade', v_r #> '{dados,capacidade}',
                                  'livre_de_verdade', coalesce(v_lv, jsonb_build_object('fonte', 'projecao'))));
  elsif v_foco = 'aprontar' then
    v_rota := 'aprontar';
    v_r := public.agenda_aprontar(p_hoje);
  elsif v_payee is not null and not v_eh_dono and (v_de is null or v_de = v_ate) then
    v_rota := 'dia_da_pessoa';
    v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
  elsif v_de is not null and v_de = v_ate then
    v_rota := 'dia';
    v_pn := public._agenda_painel(p_hoje);
    v_max := (v_pn ->> 'texto_max')::int;
    for k in reverse 5 .. 1 loop
      v_l := public._agenda_dia_de(v_pn, v_de, k);
      exit when char_length(public._agenda_juntar(v_l, null)) <= v_max;
    end loop;
    v_r := jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, v_max), 'dados', jsonb_build_object('dia', v_de));
  else
    v_rota := 'semana';
    v_r := public.agenda_semana(v_de, v_ate, p_hoje);
    -- FASE 3: com a agenda automática ligada, a frase do livre da semana é a da simulação do motor
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,livre}', '') is not null
       and position((v_r #>> '{dados,textos,livre}') in (v_r ->> 'texto')) > 0 then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(v_r ->> 'texto', v_r #>> '{dados,textos,livre}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; foco fora da lista (os 17) lança 22023. Devolve {ok, texto, dados, rota}.';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A view: authenticated (o painel, com a RLS de quem lê: o técnico não vê nada) e service_role; nunca anon.
revoke all on public.v_agenda_espera_de_peca from public, anon;
grant select on public.v_agenda_espera_de_peca to authenticated, service_role;

-- As leituras e os textos (STABLE): authenticated e service_role; nunca anon. As duas definer (os focos compras e
-- fornecedores) conferem quem vê antes de tudo (com login, só administrador e financeiro: 42501); a espera de peça também.
revoke all on function
  public._agenda_espera_linhas(date), public._agenda_dias_depois(integer, text), public._agenda_espera_texto(jsonb, date),
  public.agenda_espera_de_peca(uuid, date), public._agenda_compras_da_os(jsonb, jsonb, date),
  public._agenda_fornecedor_frase(uuid, date), public._agenda_ver_compras(uuid, date), public._agenda_ver_fornecedores(date)
  from public, anon;
grant execute on function
  public._agenda_espera_linhas(date), public._agenda_dias_depois(integer, text), public._agenda_espera_texto(jsonb, date),
  public.agenda_espera_de_peca(uuid, date), public._agenda_compras_da_os(jsonb, jsonb, date),
  public._agenda_fornecedor_frase(uuid, date), public._agenda_ver_compras(uuid, date), public._agenda_ver_fornecedores(date)
  to authenticated, service_role;

-- A recriada mantém as portas dela (create or replace não muda a ACL; repetidas aqui para a migration se bastar):
revoke all on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) from public, anon;
grant execute on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) to authenticated, service_role;
