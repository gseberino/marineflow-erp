-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P10 (7a-1): o "compre até" contado para trás.
-- A OS que o gestor marca com peça a comprar fica firme (D7-2) e a compra ganha um dia para ser feita: o 1º dia do serviço menos a
-- folga, o prazo de entrega (o do fornecedor; sem fornecedor, 7 dias úteis) e o tempo de decidir a compra (1 dia útil). Esse dia
-- fica gravado na linha do material e segura o publicado: enquanto ele não vence, o serviço não anda. O gestor cobra a compra no
-- dia ("Compre até hoje: …"), de novo quando venceu e ainda chega, e com o serviço a menos de 7 dias úteis manda comprar hoje.
-- Quando ninguém compra, a vigia empurra o serviço; depois de 2 empurrões do mesmo item ele para de remarcar e o serviço volta a
-- ficar guardado até o dono dizer de quem e quando compra. A peça que estava na mão e voltou a faltar reabre o "compre até". E as
-- compras da semana, por fornecedor, vão ao fechamento das 17:30, ao foco *agenda gestor* e ao topo do foco compras.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R1, §3.2 "Compra", §3.3 d7, §5.10, §6.2 item 5, §6.3, §6.4, §8.3 E, §8.4);
-- nomes: fase7-registro.md §1 (_agenda_gestor_compre_ate, _agenda_compras_da_semana) e §2; respostas do dono: fase7-padroes.md
-- (D7-2; AG7-05 R$ 300; AG7-06 7 dias úteis; AG7-07 "uma corrida contra o tempo": 1 dia útil, urgente a menos de 7).
-- Depende da 20261031100000 (7a P1: as colunas do "compre até" em os_material, o tipo de pergunta compre_ate, o modo compre_ate, os
-- parâmetros, o diário), da 20261031100200 (7a P3: a prontidão que lê o "compre até" gravado), da 20261031100300 (7a P4: o gravador
-- das perguntas), da 20261031100600 (7a P7: a rodada, de onde esta copia, e o diário que o fechamento e o foco leem) e da
-- 20261031100750 (7a P9); antes delas, das Fases 1 a 6 e do lote de 30/10.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (3 funções novas e 4 recriadas; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p10/montar-migration.mjs: as 4 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* dos
-- pacotes anteriores): _agenda_ver_compras de 20261029100950, _agenda_aplicar_material e agenda_rascunho_gravar de 20261027100300 e
-- agenda_gestor_rodar de 20261031100600 (7a P7). As mudanças estão só nos blocos "-- FASE 7: (7a P10 … -- FASE 7: fim"; fora deles
-- nenhuma linha muda (o C6 de supabase/tests/agenda_fase7a_compras.sql confere). Com o "compre até" do gestor desligado, as quatro
-- dão o de antes, byte a byte (a peça que volta a faltar só grava os fatos novos da linha: defeito_em, o "compre até" e os
-- empurrões zerados, que só o gestor lê).
--
-- POR QUE: com a regra compra_firme (P3) a peça a comprar não tira mais a OS da agenda, mas a prontidão conta a compra a partir de
-- amanhã: sem um dia gravado, o publicado andaria um dia por dia e a OS deslizaria toda manhã (spec §3.3 d7). E ninguém dizia ao
-- dono até quando comprar (D7-2: "marca e cobra a compra com prazo").
--
-- O QUE MUDA:
--   1. _agenda_gestor_compra_conta (nova, a conta, sem gravar): para cada item crítico em falta de uma OS com compromisso, o
--      "compre até" = o 1º dia − folga − prazo − tempo interno; o último dia em que comprar ainda chega; se já empurrou o serviço;
--      se é urgente (o 1º dia a menos de compra_urgente_du dias úteis).
--   2. _agenda_gestor_compre_ate (novo passo compre_ate da rodada do gestor, em todo tique): ligado, grava o "compre até" na linha
--      quando a conta muda (com o histórico) e soma o empurrão; a partir das 16:45 de dia útil cobra o dono com uma pergunta por OS
--      — "Compre até hoje: 3 itens de Vanderlei (…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço segue em
--      qui 12/11." / "Venceu qui 29/10 o 'compre até' de 3 itens de Vanderlei. Comprando hoje ainda chega para qui 12/11." /
--      "Compre hoje: … para começar ter 10/11 (faltam menos de 7 dias úteis). …" / "Os itens de Vanderlei já empurraram o
--      serviço 2 vezes: parei de remarcar. Ele fica guardado até você me dizer de quem e quando compra." — e grava as compras da
--      semana no diário. Em teste, tudo seco: só o diário.
--   3. _agenda_compras_da_semana (nova): os itens a comprar até o fim da semana que vem (e os vencidos), por fornecedor, e o miúdo
--      a separar para o serviço que começa no próximo dia útil — a linha compras do fechamento (P7) e o foco *agenda gestor*.
--   4. _agenda_ver_compras (recriada): o foco compras ganha "Compras da semana:" no topo (ligado, a conta de agora; em teste, o
--      diário, "(em teste)").
--   5. _agenda_aplicar_material e agenda_rascunho_gravar (recriadas): a peça que estava na mão e o dono diz que falta (chegou
--      errada, com defeito, garantia) ganha defeito_em, o "compre até" reabre e os empurrões zeram; o *grava* diz "Cerbo GX de
--      Nelson voltou a faltar: o 'compre até' reabriu (comprando hoje, chega qua 11/11)."
--   6. agenda_gestor_rodar (recriada): o passo compre_ate também roda nos tiques fora dos diários (depois do encaixe).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_compras.sql e no cenário E do agenda_fase7a_replay.sql;
-- registradas em notas-fase77a.md, P10):
--   · O passo roda em TODO tique, não só no diário: a OS marcada pela revisão das 16:52 (que vem depois do compre_ate no mesmo
--     tique) ou pelo encaixe da tarde ficaria sem o "compre até" até o dia seguinte, e a vigia da madrugada a empurraria (a
--     prontidão do P3 conta a compra a partir de amanhã enquanto não há o gravado). A cobrança e o diário continuam a partir de
--     gestor_hora_revisao (16:45), em dia útil.
--   · O "compre até" gravado sempre conta o tempo interno de compra (o P3 soma compra_interna_du ao gravado que não venceu: com 0,
--     o serviço seria empurrado no mesmo dia). O "daí em diante é compre hoje" (interno 0 depois de vencido) vale no dia que o dono
--     ouve: depois do 1º empurrão, a cobrança diz o último dia em que comprar ainda chega.
--   · Uma pergunta por OS (a spec dizia a chave compre_ate:<item>:<compre_ate>; os textos da §6.3 são por OS): chave
--     compre_ate:<os>:<hoje|vencido|urgente|limite>:<dia ou vezes>.
--   · Nome sem artigo (§6): "3 itens de Vanderlei", não "do Vanderlei".
--   · agenda_rascunho_gravar e agenda_gestor_rodar são recriadas (fora da spec): o *grava* chama _agenda_aplicar_material sem ler a
--     saída (a frase chega por agenda.material_reabriu) e a rodada só tinha o compre_ate nos diários.
--   · _agenda_gestor_compra_conta é nova (fora do registro): a conta é a mesma para o passo e para as compras da semana.
--
-- ORDEM DE LIGAR (spec §10): nada liga aqui. O passo roda com modo_compre_ate (a migration de dado 20261031100990 o põe em
-- sombra; o "OK ligar a cobrança do compre até" o liga); a prontidão só lê o "compre até" gravado com a regra compra_firme do
-- gestor que marca (marcar_regras, com modo_marcar_sozinho ligado). Desfazer: o modo para sombra; *gestor, só propor*.
--
-- PROVA: supabase/tests/agenda_fase7a_compras.sql (C0–C6) e o cenário E de supabase/tests/agenda_fase7a_replay.sql, na bancada
-- (node scripts/bancada-agenda/rodar.mjs).
--
-- APLICAR (depois do OK nomeado, com as 20261031100000–100750 já aplicadas):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100800_agenda_fase7a_compras.sql
--
-- DESFAZER: reaplicar as definições de antes (as migrations de origem citadas acima, na ordem) e
--   drop function if exists public._agenda_gestor_compre_ate(date, timestamptz), public._agenda_compras_da_semana(date),
--     public._agenda_gestor_compra_conta(uuid, date);
--   (sem o passo compre_ate, a rodada do gestor o pula: "ainda não existe"; o "compre até" gravado fica nas linhas e só a regra
--   compra_firme do gestor o lê).
--
-- IDEMPOTENTE: create or replace function, comment, revoke e grant.

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────────

-- A conta do "compre até" de UMA OS com compromisso (spec §5.10; AG7-05/06/07): para cada item crítico em falta da prontidão de
-- hoje, sem compra combinada e com prazo (os dias úteis do fornecedor, o prazo padrão sem fornecedor ou os dias corridos do
-- importado), contado para trás do 1º dia de compromisso de hoje em diante:
--   compre_ate  = o 1º dia − folga_material_du − o prazo − compra_interna_du (o valor que a prontidão do P3 lê: enquanto ele não
--                 vence, a chegada é compre_ate + o tempo interno + o prazo, o 1º dia menos a folga — o publicado não desliza;
--                 vencido, a chegada é "comprando hoje");
--   o gravado vale enquanto a base (o 1º dia, a folga, o prazo e o tempo interno) não muda; mudou, a conta de agora (muda);
--   prazo_final = o 1º dia − a folga − o prazo (o último dia em que comprar ainda chega: chega = comprando hoje, a chegada mais a
--                 folga até o 1º dia);
--   ate         = o dia que o dono ouve: o compre_ate, ou, depois que o item já empurrou o serviço uma vez, o prazo_final (o tempo
--                 de decidir já passou: daí em diante é "compre hoje");
--   empurrou    = o "compre até" gravado venceu, o 1º dia andou para a frente e a OS foi remarcada pelo material (a ação
--                 executada AUTOMÁTICA — a vigia, o motor —, não desfeita, com o motivo material, depois do gravado e depois do
--                 vencimento; a decisão do dono numa pergunta crítica não conta: o 2º atraso já é dele, segundo_atraso da Fase 2);
--   limite      = os empurrões (com este) chegaram a compre_ate_empurroes_max: a prontidão deixa de contar a compra como firme;
--   urgente     = o 1º dia antes de agenda_somar_du(hoje, compra_urgente_du) (0 = nunca): "compre hoje".
-- E os itens não críticos (o miúdo, AG7-05: "separar na véspera"). Nada é gravado aqui. null = a OS sem compromisso de hoje em
-- diante (ou fora do sistema). {os, numero, cliente, primeiro, itens [...], separar [...]}. STABLE, invoker, sem grant.
create or replace function public._agenda_gestor_compra_conta(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c        public.agenda_config := public._agenda_cfg();
  v_prim   date;
  v_pr     jsonb;
  e        jsonb;
  m        public.os_material%rowtype;
  v_itens  jsonb := '[]'::jsonb;
  v_sep    jsonb := '[]'::jsonb;
  v_prazo  int;
  v_corr   int;
  v_fonte  text;
  v_conta  date;
  v_final  date;
  v_ca     date;
  v_mesma  boolean;
  v_cheg   date;
  v_acao   uuid;
  v_emp    boolean;
  v_vezes  int;
  v_urg    date;
begin
  if p_os is null or p_hoje is null then
    raise exception '_agenda_gestor_compra_conta: sem a OS ou o dia' using errcode = '22004';
  end if;
  select min(a.dia) into v_prim
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
     and a.resultado is null;
  if v_prim is null then
    return null;
  end if;
  v_pr := public.os_prontidao(p_os, p_hoje);
  if not coalesce((v_pr ->> 'ok')::boolean, false) then
    return null;
  end if;
  v_urg := case when c.compra_urgente_du > 0 then public.agenda_somar_du(p_hoje, c.compra_urgente_du) end;

  for e in select x from jsonb_array_elements(coalesce(v_pr #> '{material,itens}', '[]'::jsonb)) with ordinality t(x, o)
            order by o loop
    if not coalesce((e ->> 'critico')::boolean, true) then
      v_sep := v_sep || jsonb_build_object('linha', e ->> 'id', 'item', e ->> 'curto', 'quantidade', e -> 'quantidade',
                                           'situacao', e ->> 'situacao');
      continue;
    end if;
    continue when e ->> 'situacao' is distinct from 'falta' or e ->> 'compra_prevista_em' is not null;
    v_prazo := (e ->> 'prazo_du')::int;
    v_corr := (e ->> 'corridos')::int;
    -- sem prazo nenhum (nível E): a prontidão pergunta "de quem e quando?"; não há o que contar para trás
    continue when v_prazo is null and v_corr is null;
    m := null;
    if e ->> 'id' is not null then
      select * into m from public.os_material x where x.id = (e ->> 'id')::uuid;
    end if;
    v_fonte := case when e ->> 'classe' = 'padrao' then 'padrao'
                    when e ->> 'prazo_texto' like '%(medido em %' then 'medido'
                    when e ->> 'prazo_texto' like '%(pela cidade%' then 'cidade'
                    else 'fornecedor' end;
    v_final := case when v_prazo is not null then public.agenda_somar_du(v_prim, -(c.folga_material_du + v_prazo))
                    else public.agenda_somar_du(public.agenda_somar_du(v_prim, -c.folga_material_du) - v_corr + 1, -1) end;
    v_conta := public.agenda_somar_du(v_final, -c.compra_interna_du);
    v_mesma := m.compre_ate is not null
               and m.compre_ate_base ->> 'primeiro' = v_prim::text
               and (m.compre_ate_base ->> 'folga')::int is not distinct from c.folga_material_du::int
               and (m.compre_ate_base ->> 'prazo')::int is not distinct from v_prazo
               and (m.compre_ate_base ->> 'corridos')::int is not distinct from v_corr
               and (m.compre_ate_base ->> 'interno')::int is not distinct from c.compra_interna_du::int;
    v_ca := case when v_mesma then m.compre_ate else v_conta end;
    -- o empurrão: o gravado venceu e a OS andou pelo material depois dele
    v_emp := false;
    v_acao := null;
    if m.compre_ate is not null and not v_mesma and (m.compre_ate_base ->> 'primeiro')::date < v_prim then
      -- (a remarcação automática — a vigia, o motor —, não a decisão do dono; depois do gravado: pela hora, ou pelo dia
      -- quando a hora do gravado é a de um teste)
      select a.id into v_acao
        from public.agenda_acoes a
       where a.service_order_id = p_os and a.executada and a.desfeita_em is null and a.motivo ~ '\mmaterial\M'
         and a.origem in ('vigia', 'motor', 'conferencia', 'sistema') and a.dia > m.compre_ate
         and (a.criada_em > coalesce(m.compre_ate_em, '-infinity'::timestamptz)
              or a.dia > (m.compre_ate_em at time zone 'America/Sao_Paulo')::date)
       order by a.criada_em desc, a.id
       limit 1;
      v_emp := v_acao is not null;
    end if;
    v_vezes := coalesce(m.empurrada_vezes, 0) + case when v_emp then 1 else 0 end;
    v_cheg := public._agenda_chegada_pela_classe(e ->> 'classe', v_prazo, v_corr, p_hoje);
    v_itens := v_itens || jsonb_build_object(
      'linha', e ->> 'id', 'item', e ->> 'curto', 'descricao', e ->> 'descricao', 'quantidade', e -> 'quantidade',
      'fornecedor', e ->> 'fornecedor', 'classe', e ->> 'classe', 'prazo', v_prazo, 'corridos', v_corr, 'prazo_fonte', v_fonte,
      'compre_ate', v_ca, 'gravado', m.compre_ate, 'prazo_final', v_final,
      'ate', case when v_vezes > 0 then v_final else v_ca end,
      'base', jsonb_strip_nulls(jsonb_build_object('primeiro', v_prim, 'folga', c.folga_material_du, 'prazo', v_prazo,
                                                   'corridos', v_corr, 'prazo_fonte', v_fonte, 'interno', c.compra_interna_du)),
      'muda', m.id is not null and not v_mesma,
      'chegada_hoje', v_cheg,
      'chega', coalesce(public.agenda_somar_du(v_cheg, c.folga_material_du) <= v_prim, false),
      'urgente', coalesce(v_prim < v_urg, false),
      'empurrou', v_emp, 'acao_empurrao', v_acao, 'empurrada_vezes', v_vezes,
      'limite', v_vezes >= c.compre_ate_empurroes_max,
      'cobrado_vezes', coalesce(m.cobrado_vezes, 0));
  end loop;
  return jsonb_build_object('os', p_os, 'numero', v_pr ->> 'numero', 'cliente', v_pr ->> 'cliente_curto', 'primeiro', v_prim,
                            'itens', v_itens, 'separar', v_sep);
end;
$function$;

comment on function public._agenda_gestor_compra_conta(uuid, date) is
  'Agenda de Produção (Fase 7a, P10; spec §5.10, AG7-05/06/07): a conta do "compre até" de uma OS com compromisso de hoje em diante (null sem ele) — para cada item crítico em falta da os_prontidao de hoje, sem compra combinada e com prazo (fornecedor, cidade, medido, o prazo padrão sem fornecedor ou o importado em dias corridos): compre_ate = o 1º dia − folga_material_du − o prazo − compra_interna_du (o gravado vale enquanto a base não muda: muda); prazo_final = sem o tempo interno; ate = o dia que o dono ouve (o compre_ate; depois do 1º empurrão, o prazo_final: "compre hoje"); chega (comprando hoje, a chegada + a folga até o 1º dia); urgente (o 1º dia antes de compra_urgente_du dias úteis); empurrou (o gravado venceu, o 1º dia andou e a OS foi remarcada pelo material: a ação executada com o motivo material depois do gravado); empurrada_vezes e limite (compre_ate_empurroes_max). E os não críticos (separar). {os, numero, cliente, primeiro, itens, separar}. Nada gravado. STABLE, invoker, sem grant.';

-- As compras da semana (spec §5.10, §6.2 item 5): das OS com compromisso de hoje em diante, os itens críticos em falta com o
-- "compre até" (o dia que o dono ouve) até o fim da semana que vem — os vencidos também —, juntos por fornecedor ("Sem fornecedor
-- (contei 7 dias úteis)" quando não há; "(contei 7 dias úteis)" também com o fornecedor sem o prazo dele) e, dentro de cada um,
-- por OS: "Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje." / "Kamell: Central de controle… de
-- Nelson — compre hoje para começar ter 10/11." (o 1º dia antes de compra_urgente_du dias úteis: urgente, AG7-07); e os não
-- críticos das OS que começam no próximo dia útil: "Separar amanhã: 8 × Porta Fusível MIDI… (Vanderlei)." Os urgentes primeiro,
-- depois pelo "compre até" mais cedo; o "separar" no fim. [{texto, compre_ate, urgente, fornecedor, itens [{os, numero, cliente,
-- linha, item, quantidade, compre_ate, ate, primeiro, urgente, vencido, chega, limite}]} | {texto, compre_ate null, urgente
-- false, separar true, dia, itens}] — o formato que _agenda_linhas_do_fechamento (a linha compras) e o foco gestor (P7) leem do
-- diário. STABLE, invoker, sem grant (o passo compre_ate e _agenda_ver_compras, definer, a chamam).
create or replace function public._agenda_compras_da_semana(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c       public.agenda_config := public._agenda_cfg();
  v_fim   date;
  v_am    date;
  r       record;
  g       record;
  v_k     jsonb;
  i       jsonb;
  v_its   jsonb := '[]'::jsonb;
  v_sep   jsonb := '[]'::jsonb;
  v_out   jsonb := '[]'::jsonb;
  v_pad   text;
  v_parts text[];
begin
  if p_hoje is null then
    raise exception '_agenda_compras_da_semana: sem o dia de hoje' using errcode = '22004';
  end if;
  v_fim := date_trunc('week', p_hoje)::date + 13;
  v_am := public.agenda_somar_du(p_hoje, 1);
  v_pad := public._agenda_plural(c.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis');
  for r in select a.service_order_id as os, min(a.dia) as primeiro
             from public.agenda_alocacoes a
            where a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
            group by a.service_order_id
            order by min(a.dia), a.service_order_id loop
    v_k := public._agenda_gestor_compra_conta(r.os, p_hoje);
    continue when v_k is null;
    for i in select x from jsonb_array_elements(v_k -> 'itens') with ordinality t(x, o)
              where (x ->> 'ate')::date <= v_fim order by o loop
      v_its := v_its || (i || jsonb_build_object('os', r.os, 'numero', v_k ->> 'numero', 'cliente', v_k ->> 'cliente',
                                                 'primeiro', r.primeiro, 'vencido', (i ->> 'ate')::date < p_hoje,
                                                 'grupo', case when i ->> 'fornecedor' is null
                                                                 then format('Sem fornecedor (contei %s)', v_pad)
                                                               when i ->> 'prazo_fonte' = 'padrao'
                                                                 then format('%s (contei %s)', i ->> 'fornecedor', v_pad)
                                                               else i ->> 'fornecedor' end));
    end loop;
    -- o miúdo das OS que começam no próximo dia útil (nunca tiveram compromisso antes)
    if r.primeiro = v_am and jsonb_array_length(v_k -> 'separar') > 0
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = r.os and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
                          and a.dia < v_am) then
      v_sep := v_sep || (select jsonb_agg(s || jsonb_build_object('os', r.os, 'numero', v_k ->> 'numero', 'cliente', v_k ->> 'cliente',
                                                                 'primeiro', r.primeiro) order by o)
                           from jsonb_array_elements(v_k -> 'separar') with ordinality t(s, o));
    end if;
  end loop;

  for g in select x ->> 'grupo' as grupo, min((x ->> 'ate')::date) as ate, bool_or((x ->> 'urgente')::boolean) as urgente,
                  min(x ->> 'fornecedor') as fornecedor, jsonb_agg(x - 'grupo' order by (x ->> 'primeiro'), x ->> 'numero', x ->> 'item') as itens
             from jsonb_array_elements(v_its) x
            group by x ->> 'grupo'
            order by bool_or((x ->> 'urgente')::boolean) desc, min((x ->> 'ate')::date), x ->> 'grupo' loop
    v_parts := array(
      select format('%s de %s — %s',
                    case when count(*) = 1 then case when (min(y ->> 'quantidade'))::numeric > 1
                                                     then format('%s × %s', replace(min(y ->> 'quantidade'), '.', ','), min(y ->> 'item'))
                                                     else min(y ->> 'item') end
                         else public._agenda_itens(count(*)::int) end,
                    min(y ->> 'cliente'),
                    case when bool_or((y ->> 'urgente')::boolean)
                           then 'compre hoje para começar ' || public._dia_curto(min((y ->> 'primeiro')::date))
                         when min((y ->> 'ate')::date) <= p_hoje then 'compre até hoje'
                         else 'compre até ' || public._dia_curto(min((y ->> 'ate')::date)) end)
        from jsonb_array_elements(g.itens) y
       group by y ->> 'os'
       order by bool_or((y ->> 'urgente')::boolean) desc, min((y ->> 'ate')::date), min(y ->> 'numero'));
    v_out := v_out || jsonb_build_object(
      'texto', g.grupo || ': ' || array_to_string(v_parts, '; ') || '.',
      'compre_ate', g.ate, 'urgente', g.urgente, 'fornecedor', g.fornecedor,
      'itens', (select jsonb_agg(jsonb_build_object('os', y -> 'os', 'numero', y -> 'numero', 'cliente', y -> 'cliente',
                                                    'linha', y -> 'linha', 'item', y -> 'item', 'quantidade', y -> 'quantidade',
                                                    'compre_ate', y -> 'compre_ate', 'ate', y -> 'ate', 'primeiro', y -> 'primeiro',
                                                    'urgente', y -> 'urgente', 'vencido', y -> 'vencido', 'chega', y -> 'chega',
                                                    'limite', y -> 'limite') order by o)
                  from jsonb_array_elements(g.itens) with ordinality t(y, o)));
  end loop;

  if jsonb_array_length(v_sep) > 0 then
    v_out := v_out || jsonb_build_object(
      'texto', format('Separar %s: %s.',
                      case when v_am = p_hoje + 1 then 'amanhã' else 'para ' || public._dia_curto(v_am) end,
                      (select string_agg(format('%s (%s)',
                                                case when (s ->> 'quantidade')::numeric > 1
                                                     then format('%s × %s', replace(s ->> 'quantidade', '.', ','), s ->> 'item')
                                                     else s ->> 'item' end, s ->> 'cliente'), '; ' order by o)
                         from jsonb_array_elements(v_sep) with ordinality t(s, o))),
      'compre_ate', null, 'urgente', false, 'separar', true, 'dia', v_am,
      'itens', (select jsonb_agg(jsonb_build_object('os', s -> 'os', 'numero', s -> 'numero', 'cliente', s -> 'cliente',
                                                    'linha', s -> 'linha', 'item', s -> 'item', 'quantidade', s -> 'quantidade',
                                                    'situacao', s -> 'situacao') order by o)
                  from jsonb_array_elements(v_sep) with ordinality t(s, o)));
  end if;
  return v_out;
end;
$function$;

comment on function public._agenda_compras_da_semana(date) is
  'Agenda de Produção (Fase 7a, P10; spec §5.10, §6.2 item 5): as compras da semana — das OS com compromisso de hoje em diante (_agenda_gestor_compra_conta), os itens críticos em falta com o "compre até" (o dia que o dono ouve) até o fim da semana que vem (os vencidos também), por fornecedor ("Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje."; urgente, o 1º dia antes de compra_urgente_du dias úteis: "— compre hoje para começar ter 10/11") e os não críticos das OS que começam no próximo dia útil ("Separar amanhã: 8 × Porta Fusível MIDI… (Vanderlei)."). Os urgentes primeiro, depois pelo "compre até"; o separar no fim. [{texto, compre_ate, urgente, fornecedor, itens} | {texto, compre_ate null, urgente false, separar true, dia, itens}] — o que o passo compre_ate grava no diário (agenda_gestor_dia.compras: a linha compras do fechamento e o foco gestor) e o 7f lê. STABLE, invoker, sem grant.';

-- O passo compre_ate da rodada do gestor (spec §5.10, §3.2 "Compra", §6.3; D7-2: a peça a comprar não tira a OS da agenda, marca
-- e cobra; AG7-07: "uma corrida contra o tempo"). Roda em TODO tique (agenda_gestor_rodar, recriada aqui, o chama também fora dos
-- diários): a OS que o gestor ou a vigia acabou de marcar ganha o "compre até" gravado no tique seguinte, no mesmo dia — sem ele,
-- a prontidão conta a compra a partir de amanhã e o publicado andaria um dia por dia.
--   (1) Ligado: grava na linha de os_material o compre_ate, a base {primeiro, folga, prazo, corridos?, prazo_fonte, interno} e o
--       compre_ate_em quando a conta muda (o histórico da linha ganha a entrada); a OS remarcada pelo material depois do "compre
--       até" vencido ganha empurrada_vezes + 1 no item.
--   (2) A partir de gestor_hora_revisao, em dia útil (o 1º tique é o diário, 16:52; os seguintes refazem): a cobrança, uma
--       pergunta compre_ate por OS (sem opções, sem prazo; o modo é o do compre_ate), na ordem —
--         limite ("Os itens de Vanderlei já empurraram o serviço 2 vezes: parei de remarcar. Ele fica guardado até você me dizer
--           de quem e quando compra."; chave compre_ate:<os>:limite:<vezes>);
--         urgente, comprando hoje ainda chega e o 1º dia antes de compra_urgente_du dias úteis ("Compre hoje: … de Nelson, para
--           começar ter 10/11 (faltam menos de 7 dias úteis). …"; chave compre_ate:<os>:urgente:<1º dia>);
--         hoje ("Compre até hoje: 3 itens de Vanderlei (…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço
--           segue em qui 12/11."; chave compre_ate:<os>:hoje:<dia>);
--         vencido, comprando hoje ainda chega ("Venceu qui 29/10 o 'compre até' de 3 itens de Vanderlei. Comprando hoje ainda
--           chega para qui 12/11."; chave compre_ate:<os>:vencido:<o compre até>);
--       comprando hoje não chega mais = nada aqui (a violação de material da vigia empurra). A pergunta nova conta a cobrança nos
--       itens (cobrado_em, cobrado_vezes + 1); a aberta que não vale mais é resolvida (o limite, só quando o item deixa de faltar).
--       E o diário do dia: agenda_gestor_dia.compras = _agenda_compras_da_semana.
-- Em teste: tudo seco — as regras do gestor só aqui dentro (agenda.gestor = 'sombra'), nada em os_material nem pergunta; só o
-- diário das compras. Desligado = {pulado}. {modo, simulacao, cobranca, os, gravados, empurrados, limites, cobrancas,
-- perguntas, resolvidas, compras}. Security definer (escreve em os_material), sem grant a ninguém: só a rodada o chama.
create or replace function public._agenda_gestor_compre_ate(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c        public.agenda_config := public._agenda_cfg();
  v_modo   text;
  v_sim    boolean;
  v_cobra  boolean;
  r        record;
  v_k      jsonb;
  i        jsonb;
  v_sel    jsonb;
  v_var    text;
  v_chave  text;
  v_txt    text;
  v_n      int;
  v_lista  text;
  v_itens  text;
  v_pz     text;
  v_pmax   int;
  v_cmax   int;
  v_semf   boolean;
  v_padr   boolean;
  v_forn   text;
  v_quem   text;
  v_dia    date;
  v_prim   date;
  v_vezes  int;
  v_nova   boolean;
  v_id     uuid;
  v_ids    uuid[];
  v_chaves text[] := '{}';
  v_oss_q  uuid[] := '{}';
  v_oss    jsonb := '[]'::jsonb;
  v_pergs  jsonb := '[]'::jsonb;
  v_grav   int := 0;
  v_emp    int := 0;
  v_lim    int := 0;
  v_cob    int := 0;
  v_res    int := 0;
  v_comp   jsonb := '[]'::jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_compre_ate: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('compre_ate');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado', 'modo', v_modo);
  end if;
  v_sim := v_modo <> 'ligado';
  v_cobra := public.agenda_dia_util(p_hoje) and (p_agora at time zone 'America/Sao_Paulo')::time >= c.gestor_hora_revisao;
  if v_sim and not v_cobra then
    -- em teste nada é gravado: fora da hora da cobrança não há o que fazer
    return jsonb_build_object('modo', v_modo, 'simulacao', true, 'cobranca', false, 'os', '[]'::jsonb, 'gravados', 0,
                              'empurrados', 0, 'limites', 0, 'cobrancas', 0, 'perguntas', '[]'::jsonb, 'resolvidas', 0,
                              'compras', 0);
  end if;
  if v_sim then
    -- em teste: as regras do gestor valem só aqui dentro; nada é gravado (só o diário das compras)
    perform set_config('agenda.gestor', 'sombra', true);
  end if;
  begin
    for r in select a.service_order_id as os, so.service_order_number as numero
               from public.agenda_alocacoes a
               join public.service_orders so on so.id = a.service_order_id
              where a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
              group by a.service_order_id, so.service_order_number
              order by so.service_order_number collate "C", a.service_order_id loop
      v_k := public._agenda_gestor_compra_conta(r.os, p_hoje);
      continue when v_k is null or jsonb_array_length(v_k -> 'itens') = 0;
      v_prim := (v_k ->> 'primeiro')::date;

      -- (1) o "compre até" gravado e os empurrões (só ligado)
      if not v_sim then
        for i in select x from jsonb_array_elements(v_k -> 'itens') x
                  where x ->> 'linha' is not null and ((x ->> 'muda')::boolean or (x ->> 'empurrou')::boolean) loop
          update public.os_material m
             set compre_ate = (i ->> 'compre_ate')::date, compre_ate_base = i -> 'base', compre_ate_em = p_agora,
                 empurrada_vezes = least(20, m.empurrada_vezes + case when (i ->> 'empurrou')::boolean then 1 else 0 end),
                 historico = public._os_material_historico(m.historico, jsonb_strip_nulls(jsonb_build_object(
                   'em', p_hoje, 'por', 'gestor', 'compre_ate', i ->> 'compre_ate', 'antes', i ->> 'gravado',
                   'primeiro', v_prim, 'empurrou', case when (i ->> 'empurrou')::boolean then true end,
                   'nota', case when (i ->> 'empurrou')::boolean
                                then format('o serviço andou para %s sem a compra: %s', public._dia_curto(v_prim),
                                            public._agenda_plural((i ->> 'empurrada_vezes')::int, 'empurrão', 'empurrões'))
                                else format('compre até %s (para começar %s)', public._dia_curto((i ->> 'ate')::date),
                                            public._dia_curto(v_prim)) end)))
           where m.id = (i ->> 'linha')::uuid;
          v_grav := v_grav + case when (i ->> 'muda')::boolean then 1 else 0 end;
          v_emp := v_emp + case when (i ->> 'empurrou')::boolean then 1 else 0 end;
        end loop;
      end if;

      -- (2) a cobrança (a partir de gestor_hora_revisao, em dia útil): uma pergunta por OS
      v_sel := null;
      v_var := null;
      if v_cobra then
        if exists (select 1 from jsonb_array_elements(v_k -> 'itens') x where (x ->> 'limite')::boolean) then
          v_var := 'limite';
          v_sel := (select jsonb_agg(x order by o) from jsonb_array_elements(v_k -> 'itens') with ordinality t(x, o)
                     where (x ->> 'limite')::boolean);
        else
          v_sel := (select jsonb_agg(x order by o) from jsonb_array_elements(v_k -> 'itens') with ordinality t(x, o)
                     where (x ->> 'chega')::boolean and ((x ->> 'urgente')::boolean or (x ->> 'ate')::date <= p_hoje));
          if v_sel is not null then
            v_var := case when exists (select 1 from jsonb_array_elements(v_sel) x where (x ->> 'urgente')::boolean) then 'urgente'
                          when exists (select 1 from jsonb_array_elements(v_sel) x where (x ->> 'ate')::date < p_hoje) then 'vencido'
                          else 'hoje' end;
          end if;
        end if;
      end if;
      if v_var is not null then
        v_n := jsonb_array_length(v_sel);
        v_lista := public._agenda_lista(array(
                     select case when (x ->> 'quantidade')::numeric > 1
                                 then format('%s × %s', replace(x ->> 'quantidade', '.', ','), x ->> 'item') else x ->> 'item' end
                       from jsonb_array_elements(v_sel) with ordinality t(x, o) order by o), 3);
        v_itens := case when v_n = 1 then format('%s de %s', v_lista, v_k ->> 'cliente')
                        else format('%s itens de %s', v_n, v_k ->> 'cliente') end;
        select max((x ->> 'prazo')::int), max((x ->> 'corridos')::int), bool_or(x ->> 'fornecedor' is null),
               bool_or(x ->> 'prazo_fonte' = 'padrao'),
               case when count(distinct x ->> 'fornecedor') = 1 and bool_and(x ->> 'fornecedor' is not null)
                    then min(x ->> 'fornecedor') end
          into v_pmax, v_cmax, v_semf, v_padr, v_forn
          from jsonb_array_elements(v_sel) x;
        -- o prazo de entrega que a conta usou: os dias úteis (o maior), senão os dias corridos do importado
        v_pz := case when v_pmax is not null then public._agenda_plural(v_pmax, 'dia útil', 'dias úteis')
                     else public._agenda_plural(v_cmax, 'dia corrido', 'dias corridos') end;
        v_quem := case when v_semf then format('de quem? Contei %s de entrega.', v_pz)
                       when v_forn is not null and v_padr then format('de %s, contei %s de entrega.', v_forn, v_pz)
                       when v_forn is not null then format('de %s, %s de entrega.', v_forn, v_pz)
                       else format('%s de entrega.', v_pz) end;
        v_vezes := (select max((x ->> 'empurrada_vezes')::int) from jsonb_array_elements(v_sel) x);
        v_dia := (select min((x ->> 'ate')::date) from jsonb_array_elements(v_sel) x);
        case v_var
          when 'limite' then
            v_chave := format('compre_ate:%s:limite:%s', r.os, v_vezes);
            v_txt := case when v_n = 1
                          then format('%s já empurrou o serviço %s: parei de remarcar. Ele fica guardado até você me dizer de quem e quando compra.',
                                      v_itens, public._agenda_plural(v_vezes, 'vez', 'vezes'))
                          else format('Os itens de %s já empurraram o serviço %s: parei de remarcar. Ele fica guardado até você me dizer de quem e quando compra.',
                                      v_k ->> 'cliente', public._agenda_plural(v_vezes, 'vez', 'vezes')) end;
          when 'urgente' then
            v_chave := format('compre_ate:%s:urgente:%s', r.os, v_prim);
            v_txt := format('Compre hoje: %s%s, para começar %s (faltam menos de %s). %s',
                            v_itens, case when v_n > 1 then format(' (%s)', v_lista) else '' end, public._dia_curto(v_prim),
                            public._agenda_plural(c.compra_urgente_du, 'dia útil', 'dias úteis'),
                            upper(left(v_quem, 1)) || substr(v_quem, 2));
          when 'hoje' then
            v_chave := format('compre_ate:%s:hoje:%s', r.os, p_hoje);
            v_txt := format('Compre até hoje: %s%s — %s Comprando hoje, o serviço segue em %s.',
                            v_itens, case when v_n > 1 then format(' (%s)', v_lista) else '' end, v_quem, public._dia_curto(v_prim));
          else
            v_chave := format('compre_ate:%s:vencido:%s', r.os, v_dia);
            v_txt := format('Venceu %s o ''compre até'' de %s. Comprando hoje ainda chega para %s.',
                            public._dia_curto(v_dia), v_itens, public._dia_curto(v_prim));
        end case;
        v_ids := array(select (x ->> 'linha')::uuid from jsonb_array_elements(v_sel) x where x ->> 'linha' is not null);
        v_id := null;
        v_nova := false;
        if not v_sim then
          v_nova := not exists (select 1 from public.agenda_perguntas q
                                 where q.chave = left(v_chave, 200) and q.modo = 'ligado' and q.estado = 'aberta');
          v_id := public._agenda_gestor_perguntar('compre_ate', v_chave, r.os, v_txt, '[]'::jsonb, null, null, null, 'ligado', p_agora);
          v_nova := v_nova and v_id is not null;
          if v_id is not null then
            v_chaves := v_chaves || left(v_chave, 200);
            v_oss_q := v_oss_q || r.os;
          end if;
          if v_nova then
            update public.os_material m
               set cobrado_em = p_agora, cobrado_vezes = least(50, m.cobrado_vezes + 1)
             where m.id = any (v_ids);
            v_cob := v_cob + 1;
          end if;
        end if;
        if v_var = 'limite' then
          v_lim := v_lim + 1;
        end if;
        v_pergs := v_pergs || jsonb_build_object('os', r.os, 'numero', r.numero, 'variante', v_var, 'chave', v_chave,
                                                 'texto', v_txt, 'pergunta_id', v_id, 'nova', v_nova, 'itens', v_n);
      end if;
      v_oss := v_oss || jsonb_build_object('os', r.os, 'numero', r.numero, 'primeiro', v_prim,
                                           'itens', jsonb_array_length(v_k -> 'itens'),
                                           'compre_ate', (select min((x ->> 'ate')::date) from jsonb_array_elements(v_k -> 'itens') x),
                                           'cobranca', v_var);
    end loop;

    -- as perguntas compre_ate abertas que não valem mais (ligado, na hora da cobrança): a de outra variante ou dia da mesma OS
    -- ("mudou: perguntei de novo"), a da OS que não tem mais o que cobrar; o limite só quando nenhum item dele falta mais
    if v_cobra and not v_sim then
      update public.agenda_perguntas q
         set estado = 'resolvida',
             resolvida_motivo = case when q.service_order_id = any (v_oss_q) then 'mudou o que falta comprar: perguntei de novo'
                                     else 'não precisa mais: nada a cobrar dessa compra agora' end
       where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo = 'compre_ate'
         and not (q.chave = any (v_chaves))
         and (q.chave not like 'compre_ate:%:limite:%'
              or not exists (select 1 from public.os_material m
                              where m.service_order_id = q.service_order_id and m.situacao = 'falta'
                                and m.compra_prevista_em is null and m.empurrada_vezes >= c.compre_ate_empurroes_max));
      get diagnostics v_res = row_count;
    end if;

    -- o diário: as compras da semana
    if v_cobra then
      v_comp := public._agenda_compras_da_semana(p_hoje);
    end if;
  exception when others then
    if v_sim then
      perform set_config('agenda.gestor', '', true);
    end if;
    raise;
  end;
  if v_sim then
    perform set_config('agenda.gestor', '', true);
  end if;
  if v_cobra and (jsonb_array_length(v_comp) > 0
                  or exists (select 1 from public.agenda_gestor_dia g where g.dia = p_hoje and g.compras <> '[]'::jsonb)) then
    perform public._agenda_gestor_dia_gravar(p_hoje, 'compras', v_comp, p_agora);
  end if;
  return jsonb_build_object('modo', v_modo, 'simulacao', v_sim, 'cobranca', v_cobra, 'os', v_oss,
                            'gravados', v_grav, 'empurrados', v_emp, 'limites', v_lim, 'cobrancas', v_cob,
                            'perguntas', v_pergs, 'resolvidas', v_res, 'compras', jsonb_array_length(v_comp));
end;
$function$;

comment on function public._agenda_gestor_compre_ate(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P10; spec §5.10, §3.2, §6.3; D7-2, AG7-05/06/07): o passo compre_ate da rodada do gestor, em todo tique (a rodada recriada o chama também fora dos diários). Ligado: grava em os_material o "compre até" da conta (_agenda_gestor_compra_conta: o 1º dia − folga − prazo − compra_interna_du), a base e compre_ate_em quando a conta muda (com a entrada no histórico da linha) e soma o empurrão no item quando a OS foi remarcada pelo material depois do "compre até" vencido. A partir de gestor_hora_revisao, em dia útil, a cobrança: uma pergunta compre_ate por OS (sem opções, sem prazo), limite ("Os itens de Vanderlei já empurraram o serviço 2 vezes: parei de remarcar. …"), urgente ("Compre hoje: … para começar ter 10/11 (faltam menos de 7 dias úteis). …"), hoje ("Compre até hoje: 3 itens de Vanderlei (…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço segue em qui 12/11.") ou vencido ("Venceu qui 29/10 o ''compre até'' de 3 itens de Vanderlei. Comprando hoje ainda chega para qui 12/11."); comprando hoje sem chegar = nada (a vigia empurra); a pergunta nova conta cobrado_em/cobrado_vezes; a aberta que não vale mais, resolvida; e o diário agenda_gestor_dia.compras = _agenda_compras_da_semana. Em teste, tudo seco (as regras do gestor só dentro do passo) e só o diário. Desligado = {pulado}. Security definer, sem grant a ninguém.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7: (7a P10") ────────────────
-- Fora dos blocos nenhuma linha muda (o C6 de supabase/tests/agenda_fase7a_compras.sql confere). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (agenda_rascunho_gravar: o 7b P2, que o registro dizia copiar de 20261027100300;
-- _agenda_ver_compras, _agenda_aplicar_material e agenda_gestor_rodar: quem vier).

-- _agenda_ver_compras (de 20261029100950_agenda_fase6_correcao_textos.sql)
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
  -- FASE 6: as linhas do que a agenda mediu dos fornecedores
  v_forn   text[];
  -- FASE 6: fim
  -- FASE 7: (7a P10) as compras da semana do gestor da agenda no topo
  v_f7_modo text;
  v_f7_cs   jsonb;
  v_f7_l    text[];
  -- FASE 7: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_compras: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  -- CORREÇÃO FASE 6: (C2) regressão B8: sem o "sub" no JWT (auth.uid() nulo) só passa o service_role, ou nenhum JWT (o banco
  -- por dentro: a rodada, o fechamento, os testes) — como agenda_fator_de_campo; o authenticated sem "sub" recebe 42501 (antes
  -- o portão de cima não rodava, e ele lia tudo). Os JWT do Supabase sempre têm "sub": hoje não é explorável.
  if v_uid is null then
    declare
      v_papel text;
    begin
      begin
        v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
      exception when others then
        v_papel := 'invalido';
      end;
      if v_papel not in ('', 'service_role') then
        raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
      end if;
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
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
  -- FASE 7: (7a P10, spec §5.10 e §6.2 item 5) com o "compre até" do gestor fora de desligado, as compras da semana no topo:
  -- ligado, a conta de agora (_agenda_compras_da_semana: o que a prontidão de hoje diz); em teste, o diário do gestor (o passo
  -- compre_ate o grava, com as regras do gestor só dentro da simulação; de até 3 dias), com "(em teste)". Até 4 linhas e "• e
  -- mais N". Desligado, nada muda.
  v_f7_modo := public._agenda_gestor_modo('compre_ate');
  if v_f7_modo <> 'desligado' then
    if v_f7_modo = 'ligado' then
      v_f7_cs := public._agenda_compras_da_semana(p_hoje);
    else
      select g.compras into v_f7_cs from public.agenda_gestor_dia g
       where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.compras <> '[]'::jsonb order by g.dia desc limit 1;
    end if;
    v_f7_l := array(select '• ' || btrim(x ->> 'texto')
                      from jsonb_array_elements(coalesce(v_f7_cs, '[]'::jsonb)) with ordinality t(x, o)
                     where nullif(btrim(x ->> 'texto'), '') is not null order by o);
    if cardinality(v_f7_l) > 0 then
      v_cab := array_to_string(array['Compras da semana' || case when v_f7_modo = 'ligado' then '' else ' (em teste)' end || ':']
                               || v_f7_l[1:4]
                               || case when cardinality(v_f7_l) > 4 then array[format('• e mais %s', cardinality(v_f7_l) - 4)]
                                       else '{}'::text[] end, E'\n')
               || E'\n' || v_cab;
    end if;
  end if;
  -- FASE 7: fim
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

  -- FASE 6: (P3) (6) o que a agenda mediu das entregas de cada fornecedor (spec-fase6 §5.3): a linha do foco do aprendizado
  -- ("Kamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis (em teste)." / "Correa: 4 de 5 entregas medidas."),
  -- o atraso e o prazo da nota, os de mais medidas primeiro (até 3); peso 1 (sai primeiro, com o detector). Com o
  -- aprendizado desligado, o foco de antes, byte a byte.
  if c.modo_aprendizado <> 'desligado' then
    v_forn := array(select a.texto
                      from public.agenda_aprendizado a
                     where a.item in ('fornecedor_atraso', 'fornecedor_prazo') and a.texto is not null
                     order by a.estado = 'medindo', a.n desc, a.detalhe ->> 'nome', a.item, a.chave
                     limit 3);
    if cardinality(v_forn) > 0 then
      v_cauda := v_cauda || v_forn;
      v_prio := v_prio || array_fill(1, array[cardinality(v_forn)]);
    end if;
  end if;
  -- FASE 6: fim
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
  'Agenda de Produção (Fase 4, P6): agenda_ver foco compras. Sem OS, até texto_max: "Compras (sex 30/10):", uma linha por serviço da fila (sem orçamento) com material fora de A (_agenda_compras_da_os: o que falta, "nada comprado desde a aprovação", "Compre até … para começar …", o que vem e de onde, "de quem e quando?") e os de material na mão parados; "Não conto N parados no cliente."; as notas sem a palavra do dono ("Não sei de qual serviço é a nota 812 da Correa (qui 29/10): …"); o tempo até comprar (agenda_espera_de_peca); a pergunta ao fornecedor da semana (_agenda_fornecedor_frase; sombra "Ao fornecedor (em teste): eu teria perguntado …"); em sombra do detector, "Leitura das conversas (em teste): …" (agenda_detector_precisao). Com OS (também a concluída): a frase da espera (os 3 componentes), "• Material: …" e as perguntas ao fornecedor dela. Os serviços saem do fim com "• e mais N"; o resto, pela linha. Definer (lê a fila do WhatsApp e as perguntas ao fornecedor por inteiro): com login, só administrador e financeiro (senão 42501). {ok, texto, dados}. FASE 6 (P3): sem OS e com o aprendizado fora de desligado, até 3 linhas do que a agenda mediu de cada fornecedor (o atraso das entregas e o prazo da nota: a linha de agenda_aprendizado.texto), peso 1 na cauda. CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501. FASE 7 (7a P10, spec §5.10 e §6.2 item 5): sem OS e com o "compre até" do gestor fora de desligado, "Compras da semana:" no topo — ligado, a conta de agora (_agenda_compras_da_semana: por fornecedor, "• Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje." e o "• Separar amanhã: …"); em teste, o diário do gestor de até 3 dias (agenda_gestor_dia.compras), "Compras da semana (em teste):". Até 4 linhas e "• e mais N". Desligado, a de antes, byte a byte.';

-- _agenda_aplicar_material (de 20261027100300_agenda_fase4_notas_pix.sql)
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
  -- FASE 7: (7a P10) a peça que voltou a faltar: o "compre até" reabre
  v_f7_it   jsonb;
  v_f7_pr   jsonb;
  v_f7_cheg date;
  v_f7_txt  text;
  -- FASE 7: fim
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
  -- FASE 7: (7a P10, spec §5.10 e §6.4) a linha que estava na mão e o dono diz que falta (chegou errada, com defeito, troca em
  -- garantia; ou só parte dela ficou): defeito_em, e o "compre até" reabre — sem o gravado (a rodada do gestor o recalcula pelo
  -- 1º dia da OS) e sem os empurrões (a compra é outra). Com o "compre até" do gestor ligado, a frase vai ao *grava*
  -- (agenda_rascunho_gravar lê agenda.material_reabriu) e à saída: "Cerbo GX de Nelson voltou a faltar: o 'compre até' reabriu
  -- (comprando hoje, chega qua 11/11)." Fora desse caso, nada muda.
  if v_old.situacao = 'na_mao' and v_new.situacao = 'falta' then
    update public.os_material m
       set defeito_em = coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now()),
           compre_ate = null, compre_ate_base = null, compre_ate_em = null, empurrada_vezes = 0
     where m.id = v_old.id;
    if public._agenda_gestor_modo('compre_ate') = 'ligado' then
      v_f7_pr := public.os_prontidao(p_os, p_hoje);
      select e into v_f7_it from jsonb_array_elements(coalesce(v_f7_pr #> '{material,itens}', '[]'::jsonb)) e
       where e ->> 'id' = v_old.id::text limit 1;
      v_f7_cheg := public._agenda_chegada_pela_classe(v_f7_it ->> 'classe', (v_f7_it ->> 'prazo_du')::int,
                                                      (v_f7_it ->> 'corridos')::int, p_hoje);
      v_f7_txt := format('%s de %s voltou a faltar: o ''compre até'' reabriu%s.',
                         coalesce(v_f7_it ->> 'curto', public._agenda_linha_curta(v_old.descricao)),
                         coalesce(v_f7_pr ->> 'cliente_curto', 'o serviço'),
                         case when v_f7_cheg is not null then format(' (comprando hoje, chega %s)', public._dia_curto(v_f7_cheg))
                              else '' end);
      perform set_config('agenda.material_reabriu',
                         concat_ws(E'\n', nullif(current_setting('agenda.material_reabriu', true), ''), v_f7_txt), true);
    end if;
  end if;
  -- FASE 7: fim
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
  -- FASE 7: (7a P10) a frase da peça que voltou a faltar também na saída
  if v_f7_txt is not null then
    return jsonb_build_object('linha', v_old.id, 'de', v_old.situacao, 'para', v_new.situacao, 'texto', v_f7_txt);
  end if;
  -- FASE 7: fim
  return jsonb_build_object('linha', v_old.id, 'de', v_old.situacao, 'para', v_new.situacao);
end;
$function$;

comment on function public._agenda_aplicar_material(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 4, P3: com o aviso, a fonte nfe/pix/fornecedor, a previsão da nota ou do fornecedor, o dia da compra e comprado_fonte, a nota na linha — remessa_id —, a evidência {remessa_id, nfe_chave, email_attachment_id | bank_transaction_id | comprovante_id | whatsapp_message_id, trecho, vinculo_por dono}, a nota ligada à OS, o sinal aplicado e a pergunta respondida): grava em os_material uma linha de rascunho material — acha a linha pelo vínculo (ou cria: material novo do dono, item de OC que a sincronização não cria), aplica a situação dita (fonte dono; previsão do dono com previsao_original na 1ª; na mão com a quantidade completa ou a parcial), critico e fornecedor; histórico {em, de, para, por dono, autor, trecho, nota}. Só pelo agenda_rascunho_gravar; só service_role. FASE 7 (7a P10, spec §5.10 e §6.4): a linha que estava na mão e passa a faltar (chegou errada, com defeito, troca em garantia; ou só parte dela ficou) ganha defeito_em, o "compre até" gravado sai (a rodada do gestor o recalcula pelo 1º dia da OS) e os empurrões zeram; com o "compre até" do gestor ligado, a frase "Cerbo GX de Nelson voltou a faltar: o ''compre até'' reabriu (comprando hoje, chega qua 11/11)." vai na saída (texto) e em agenda.material_reabriu, que o *grava* (agenda_rascunho_gravar) junta ao "Gravado. Agora:". Fora desse caso, a de antes.';

-- agenda_rascunho_gravar (de 20261027100300_agenda_fase4_notas_pix.sql)
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
  -- FASE 7: (7a P10) as frases da peça que voltou a faltar (_agenda_aplicar_material as junta em agenda.material_reabriu)
  -- começam vazias neste *grava*
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim

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

  -- FASE 7: (7a P10, spec §6.4) a peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o 'compre até' reabriu
  -- (comprando hoje, chega qua 11/11).") entra no "Gravado. Agora:" junto dos pedidos — só com o "compre até" do gestor ligado
  -- (_agenda_aplicar_material só escreve a frase assim); sem isso, nada muda
  v_f2 := v_f2 || coalesce(string_to_array(nullif(current_setting('agenda.material_reabriu', true), ''), E'\n'), '{}'::text[]);
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim
  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade; Fase 4: _agenda_aplicar_fornecedor, o prazo dito de um fornecedor, que não depende do modo da agenda; Fase 4, P3: _agenda_aplicar_aviso, o "não é de serviço" da nota, do Pix ou da mensagem), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava (Fase 3: menos concluir e entregar, que gravam em todos os modos; a recusa da porta = "Não gravei nada. Não concluí: …" e o lote volta). Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo. FASE 7 (7a P10, spec §6.4): a frase da peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o ''compre até'' reabriu (comprando hoje, chega qua 11/11).", que _agenda_aplicar_material junta em agenda.material_reabriu só com o "compre até" do gestor ligado) entra no "Gravado. Agora:" junto dos pedidos; a variável começa vazia em cada *grava*. Sem ela, a de antes, byte a byte.';

-- agenda_gestor_rodar (de 20261031100600_agenda_fase7a_rodada.sql)
create or replace function public.agenda_gestor_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_tique   constant text[] := array['vetos', 'encaixe', 'bem', 'sinal', 'puxar'];
  c_diarios constant text[] := array['perguntas', 'compre_ate', 'revisao', 'fichas', 'orcamentos', 'sabado', 'equipe', 'sombra'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_modos   jsonb;
  v_diaria  boolean;
  v_passos  text[];
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_parou   text;
  v_estado  text;
  v_msg     text;
  v_acoes   int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do gestor.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  -- uma rodada por vez (o tique seguinte que chega com esta rodando não espera: sai)
  if not pg_try_advisory_xact_lock(hashtext('agenda_gestor')) then
    return jsonb_build_object('rodou', false, 'ocupado', true);
  end if;
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor);
  if v_modos ->> 'marcar' = 'desligado' and v_modos ->> 'encaixe' = 'desligado' and v_modos ->> 'revisao' = 'desligado'
     and v_modos ->> 'compre_ate' = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', v_modos);
  end if;
  -- os passos diários: no 1º tique de dia útil a partir de gestor_hora_revisao (o dia está numa rodada gestor com "diaria")
  v_diaria := public.agenda_dia_util(p_hoje)
              and (p_agora at time zone 'America/Sao_Paulo')::time >= cf.gestor_hora_revisao
              and not exists (select 1 from public.agenda_vigia_rodadas x
                               where x.rotina = 'gestor' and x.p_hoje = p_hoje and x.contagens ? 'diaria');
  v_passos := c_tique || case when v_diaria then c_diarios else '{}'::text[] end;
  -- FASE 7: (7a P10) o "compre até" também em todo tique fora dos diários (depois do encaixe), com o modo dele fora de
  -- desligado: a OS que o gestor ou a vigia acabou de marcar ganha o "compre até" gravado no mesmo dia — sem ele, a prontidão
  -- conta a compra a partir de amanhã e o publicado andaria um dia por dia. O passo só cobra e escreve o diário a partir de
  -- gestor_hora_revisao, em dia útil. Com o compre_ate desligado, nada muda.
  if not v_diaria and v_modos ->> 'compre_ate' <> 'desligado' then
    v_passos := v_passos || 'compre_ate'::text;
  end if;
  -- FASE 7: fim
  v_acoes := (select count(*) from public.agenda_acoes a where a.executada);

  foreach v_passo in array v_passos loop
    if to_regprocedure(format('public.%I(date, timestamp with time zone)', '_agenda_gestor_' || v_passo)) is null then
      v_cont := v_cont || jsonb_build_object(v_passo, jsonb_build_object('pulado', true, 'motivo', 'ainda não existe'));
      continue;
    end if;
    begin
      execute format('select public.%I($1, $2)', '_agenda_gestor_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception
      when query_canceled then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_parou := v_passo;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('gestor da agenda, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg),
                                     'agenda', 'gestor:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                        'tempo_max', cf.gestor_tempo_max::text));
        exit;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('gestor da agenda, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'gestor:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  v_acoes := (select count(*) from public.agenda_acoes a where a.executada) - v_acoes;
  -- os diários só contam como feitos se a rodada não parou no tempo (senão o tique seguinte tenta de novo)
  v_cont := v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas, 'acoes', v_acoes,
                                         'mudou', v_acoes > 0)
            || case when v_diaria and v_parou is null then jsonb_build_object('diaria', true) else '{}'::jsonb end
            || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia, v_cont, least(v_erros, 32767),
          greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int), 'gestor', cf.modo_equipe, cf.modo_diaria);
  return jsonb_build_object('rodou', true, 'modos', v_modos, 'diaria', v_diaria and v_parou is null, 'parou_no', v_parou,
                            'acoes', v_acoes, 'erros', v_erros, 'falhas', v_falhas, 'contagens', v_cont);
end;
$function$;

comment on function public.agenda_gestor_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P7; spec §3.1 item 13, §5.7): a rodada do gestor da agenda (o job agenda-gestor do pg_cron, ''7,22,37,52 10-23 * * 1-6'', com o statement_timeout de gestor_tempo_max). Passos _agenda_gestor_<passo>(date, timestamptz) → jsonb: de todo tique vetos, encaixe, bem, sinal, puxar; diários (no 1º tique de dia útil a partir de gestor_hora_revisao, uma vez: a rodada gestor do dia com "diaria") perguntas, compre_ate, revisao, fichas, orcamentos, sabado, equipe, sombra. O passo cuja função ainda não existe = {pulado}. Erro de um passo → app_error_logs (gestor:<passo>) e segue; query_canceled → registra, grava a rodada (parou_no) e encerra (os diários tentam de novo no tique seguinte). Com marcar, encaixe, revisao e compre_ate desligados = {rodou: false} (nada gravado). Uma rodada por vez (pg_try_advisory_xact_lock: a outra sai com {rodou: false, ocupado}). Uma linha em agenda_vigia_rodadas (rotina gestor) com as contagens de cada passo, os modos, as falhas, as ações executadas na rodada (acoes, mudou), os erros e a duração. O aviso ao dono do que mudou sai pelo passo agenda-aviso do task-automations no tique seguinte (ele já conta toda ação de plano executada da vigia/motor ainda não contada). Security definer, só o service_role. FASE 7 (7a P10): o passo compre_ate também roda nos tiques fora dos diários, depois dos de todo tique (o encaixe): a OS que o gestor ou a vigia acabou de marcar ganha o "compre até" gravado no mesmo dia; o passo só cobra e escreve o diário a partir de gestor_hora_revisao, em dia útil.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- A conta e as compras da semana são internas (STABLE, invoker): sem grant a ninguém (o passo e _agenda_ver_compras, definer,
-- as chamam). O passo escreve em os_material e nas perguntas: definer e sem grant a ninguém, nem service_role (só a rodada).
revoke all on function public._agenda_gestor_compra_conta(uuid, date), public._agenda_compras_da_semana(date),
  public._agenda_gestor_compre_ate(date, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public._agenda_ver_compras(uuid, date), public.agenda_rascunho_gravar(uuid, date) from public, anon;
grant execute on function public._agenda_ver_compras(uuid, date), public.agenda_rascunho_gravar(uuid, date)
  to authenticated, service_role;
revoke all on function public._agenda_aplicar_material(uuid, uuid, jsonb, text, date),
  public.agenda_gestor_rodar(date, timestamptz)
  from public, anon, authenticated;
grant execute on function public._agenda_aplicar_material(uuid, uuid, jsonb, text, date),
  public.agenda_gestor_rodar(date, timestamptz)
  to service_role;
