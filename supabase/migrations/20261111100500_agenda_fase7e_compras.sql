-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P6: as compras. O tempo que o dono leva da aprovação até comprar passa a ser medido e a entrar no "compre até", e a compra registrada conta no prazo do fornecedor.
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (§5.5 e o bloco R7, que vale sobre o corpo: R7.1, R7.2, R7.5-15, R7.5-16, R7.6, R7.8, R7.12, R7.13); nomes: fase7-registro.md; o registro do pacote: f7e/p6/notas.md.
-- Depende de 20261111100000 (P1), 20261111100100 (P2) e 20261111100300 (P4). Copiado das definições MAIS NOVAS: _agenda_aprender_fornecedor 20261029100900_agenda_fase6_correcao_calculo.sql:1203; os_prontidao 20261031100980_agenda_fase77a_correcao.sql:2044; _agenda_gestor_compra_conta 20261031100800_agenda_fase7a_compras.sql:104; _agenda_ver_gestor 20261101100850_agenda_fase77b_correcao2.sql:408; _agenda_aprendizado_texto 20261111100300_agenda_fase7e_folga.sql:3344; _agenda_prazo_do_fornecedor 20261029100300_agenda_fase6_fornecedor.sql:457; _agenda_ver_fornecedores 20261029100950_agenda_fase6_correcao_textos.sql:3032.
-- Integração P4–P6 (09/11): _agenda_aprendizado_texto vem da 20261111100300 (o P4 a recriou depois do P2, com o texto da folga da semana sem medida); copiada da 20261111100100, esta migration apagaria o bloco do P4 sem erro nenhum. Por isso, publicar esta migration leva junto o bloco de texto do P4 (o item folga_semana nessa função), e desfazer o P4 com esta aplicada exige desfazer esta antes (o DESFAZER da 20261111100300).
--
-- ═══ NÃO APLICADA ═══ Existe para revisão e espera o OK (publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção). Nenhuma coluna nem tabela nova.
--
-- POR QUE: com o P2 a rodada mede cada compra crítica (agenda_medidas_compra); falta transformar a medida em número usado. O "compre até" gravado sai de _agenda_gestor_compra_conta, e não da prontidão: as duas têm de ler o mesmo tempo interno (R7.5-15).
--
-- O QUE MUDA, só com modo_tempo_compra ligado de verdade (o freio apaga: _agenda_margem_modo) ou numa OS com tempo_compra_marcado (fora disso, a saída de antes, byte a byte):
--   1. _agenda_aprender_tempo_compra, _agenda_aprender_folga_compra e _agenda_aprender_prazo_sem_fornecedor: os passos da rodada (o P7 os liga), que gravam tempo_compra, folga_compra e prazo_sem_fornecedor com a credibilidade da §3.1-7.
--      folga_compra e prazo_sem_fornecedor ficam só medidos (R7.5-16: sem leitor nesta etapa; não existe _agenda_folga_compra_du).
--   2. os_prontidao: compra_firme conta o tempo interno da OS em vez do parâmetro; o item ganha tempo_interno_du só quando o número é diferente do parâmetro.
--   3. _agenda_gestor_compra_conta: as 3 contas do tempo interno (o compre_ate, base.interno, v_mesma) pelo mesmo número (R7.5-15).
--   4. _agenda_ver_gestor: o "entre decidir e comprar" diz o número que vale.
--   5. _agenda_aprender_fornecedor: fornecedor_prazo mede também as entregas pela compra (§5.5), com a nota da mesma entrega fora, e o atraso deixa de fora a previsão dita antes da compra. Em sombra só o detalhe.teria.
--   6. _agenda_aprendizado_texto: o texto do "Fornecedor pela compra" (achado 152), sobre o corpo da 20261111100300 (o do P4 fica como está).
--   7. _agenda_prazo_do_fornecedor e _agenda_ver_fornecedores: com fornecedor_prazo em uso medido por compra, a frase e o título do bloco "Medido" dizem o que foi medido; sem compra medida, o texto de antes.
--
-- O QUE NÃO MUDA: agenda_vigiar, agenda_cliente_vigiar e agenda_propor não são recriadas; em sombra e com o freio (também na simulação do gestor, agenda.gestor = sombra), na OS sem marcação a prontidão não faz nenhuma chamada nova (R7.8); a OS marcada lê o número da linha que já tem na mão. A chamada que continua é a de _agenda_gestor_compra_conta (passo do gestor, fora de agenda_vigiar, agenda_cliente_vigiar e agenda_propor), que com o freio devolve o parâmetro ou o marcado. Nenhuma mensagem nova ao dono, à equipe ou ao cliente: os textos novos só saem no foco e no "o que mudou", e o foco é do P7. Nada de dinheiro.
--
-- DESFAZER (na ordem):
--   cada recriada volta à versão anterior pelo corpo da origem acima; depois, drop das 3 novas:
--   drop function if exists public._agenda_aprender_tempo_compra(date, timestamptz);
--   drop function if exists public._agenda_aprender_folga_compra(date, timestamptz);
--   drop function if exists public._agenda_aprender_prazo_sem_fornecedor(date, timestamptz);

-- ── 1. Os passos da rodada ────────────────────────────────────────────────────────────────────────

-- O tempo de compra: 1 ponto = 1 OS aprovada na janela com linha válida; o tempo dela é o da linha que mais demorou (§3.2).
create or replace function public._agenda_aprender_tempo_compra(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v        jsonb;
  v_n      int;
  v_vals   numeric[];
  v_am     jsonb;
  v_p      numeric;
  v_calc   numeric;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  begin
    with por_os as (
      select m.service_order_id as os, so.service_order_number as numero, max(m.tempo_compra_du)::numeric as t, min(m.aprovada_em) as aprovada
        from public.agenda_medidas_compra m
        join public.service_orders so on so.id = m.service_order_id
       where m.valida_tempo and m.tempo_compra_du is not null
         and m.aprovada_em between p_hoje - c.aprender_janela_dias and p_hoje
       group by m.service_order_id, so.service_order_number),
    recentes as (
      select po.*, row_number() over (order by po.aprovada desc, po.os) as rn from por_os po)
    select count(*)::int, array_agg(rc.t order by rc.aprovada desc, rc.os),
           jsonb_agg(jsonb_build_object('os', rc.os, 'numero', rc.numero, 'du', rc.t, 'em', rc.aprovada) order by rc.aprovada desc, rc.os)
      into v_n, v_vals, v_am
      from recentes rc
     where rc.rn <= c.fator_amostra_max;
    v_p := public._agenda_percentil(v_vals, c.tempo_compra_percentil);
    v_calc := case when v_p is not null
                   then least(c.tempo_compra_max_du, round(public._agenda_credibilidade(v_p, v_n, c.compra_interna_du, c.credibilidade_k))) end;
    v := public._agenda_aprendizado_gravar('tempo_compra', 'todas', 'geral', v_calc, v_n, coalesce(v_am, '[]'::jsonb), c.compra_interna_du,
           jsonb_build_object('percentil', v_p, 'z', round(v_n::numeric / (v_n + c.credibilidade_k), 4), 'n', v_n), p_agora);
    return jsonb_build_object('chaves', 1, 'estados', jsonb_build_object(v ->> 'estado', 1), 'acoes', case when v ->> 'acao_id' is not null then 1 else 0 end, 'erros', 0);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, tempo de compra: %s', sqlerrm), 'agenda', 'aprender:tempo_compra', 'error', jsonb_build_object('sqlstate', sqlstate, 'p_hoje', p_hoje));
    return jsonb_build_object('chaves', 1, 'estados', '{}'::jsonb, 'acoes', 0, 'erros', 1);
  end;
end;
$function$;

comment on function public._agenda_aprender_tempo_compra(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P6; §5.5, §3.2): o passo do tempo de compra da rodada do aprendizado — por OS aprovada em aprender_janela_dias com linha valida_tempo, o maior tempo_compra_du dela (as fator_amostra_max mais recentes); calculado = o percentil tempo_compra_percentil com a credibilidade para compra_interna_du (o padrão), arredondado, até tempo_compra_max_du. Grava pelo _agenda_aprendizado_gravar (item tempo_compra, chave todas, nível geral). O erro vai a app_error_logs (aprender:tempo_compra). {chaves, estados, acoes, erros}. Invoker, sem grant (o P7 o chama).';

-- A folga da compra: 1 ponto = 1 OS com linha válida para a folga. Só medida nesta etapa (R7.5-16): o gravador deixa em teste.
create or replace function public._agenda_aprender_folga_compra(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v        jsonb;
  v_n      int;
  v_vals   numeric[];
  v_am     jsonb;
  v_prazo  int;
  v_dia    int;
  v_maior  numeric;
  v_p      numeric;
  v_calc   numeric;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  begin
    with por_os as (
      -- atraso nulo fica de fora (nem greatest(0, nulo) = 0 nem max engolindo a linha, R7.12-2); a chegada antes do contado conta 0
      select m.service_order_id as os, so.service_order_number as numero, greatest(0, max(m.atraso_chegada_du))::numeric as a,
             bool_or(m.primeiro_dia_cumprido) as comecou, max(m.chegou_em) as chegou
        from public.agenda_medidas_compra m
        join public.service_orders so on so.id = m.service_order_id
       where m.valida_folga and m.atraso_chegada_du is not null
         and m.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje
       group by m.service_order_id, so.service_order_number),
    recentes as (
      select po.*, row_number() over (order by po.chegou desc, po.os) as rn from por_os po)
    select count(*)::int, array_agg(rc.a order by rc.chegou desc, rc.os),
           jsonb_agg(jsonb_build_object('os', rc.os, 'numero', rc.numero, 'atraso', rc.a, 'em', rc.chegou) order by rc.chegou desc, rc.os),
           count(*) filter (where rc.a = 0)::int, count(*) filter (where rc.comecou is true)::int, max(rc.a)
      into v_n, v_vals, v_am, v_prazo, v_dia, v_maior
      from recentes rc
     where rc.rn <= c.fator_amostra_max;
    v_p := public._agenda_percentil(v_vals, c.folga_compra_percentil);
    v_calc := case when v_p is not null
                   then least(c.folga_compra_max_du, ceil(public._agenda_credibilidade(v_p, v_n, 0, c.credibilidade_k))) end;
    v := public._agenda_aprendizado_gravar('folga_compra', 'todas', 'geral', v_calc, v_n, coalesce(v_am, '[]'::jsonb), 0,
           jsonb_build_object('no_prazo', coalesce(v_prazo, 0), 'maior', v_maior, 'comecaram_no_dia', coalesce(v_dia, 0), 'n', v_n), p_agora);
    return jsonb_build_object('chaves', 1, 'estados', jsonb_build_object(v ->> 'estado', 1), 'acoes', case when v ->> 'acao_id' is not null then 1 else 0 end, 'erros', 0);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, folga da compra: %s', sqlerrm), 'agenda', 'aprender:folga_compra', 'error', jsonb_build_object('sqlstate', sqlstate, 'p_hoje', p_hoje));
    return jsonb_build_object('chaves', 1, 'estados', '{}'::jsonb, 'acoes', 0, 'erros', 1);
  end;
end;
$function$;

comment on function public._agenda_aprender_folga_compra(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P6; §5.5, §3.2, R7.5-16): o passo da folga da compra da rodada do aprendizado — por OS com linha valida_folga que chegou em aprender_janela_dias, o maior atraso da chegada dela contra o contado (0 para quem chegou antes; as fator_amostra_max mais recentes); calculado = o percentil folga_compra_percentil com a credibilidade para 0, para cima, até folga_compra_max_du. Detalhe {no_prazo, maior, comecaram_no_dia, n}. Sem leitor nesta etapa: o gravador nunca a põe em uso. Invoker, sem grant (o P7 o chama).';

-- A peça comprada sem fornecedor dito: 1 ponto = 1 compra (§3.2, a entrega; as linhas da mesma compra não contam várias vezes). Só medida.
create or replace function public._agenda_aprender_prazo_sem_fornecedor(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  -- o teto do item (§3.2): estrutural, como o da credibilidade; não é parâmetro do dono
  c_max    constant int := 30;
  v        jsonb;
  v_n      int;
  v_vals   numeric[];
  v_am     jsonb;
  v_p      numeric;
  v_calc   numeric;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  begin
    with entregas as (
      select m.entrega, max(m.prazo_real_du)::numeric as du, max(m.chegou_em) as chegou, min(so.service_order_number) as numero
        from public.agenda_medidas_compra m
        join public.service_orders so on so.id = m.service_order_id
       where m.valida_prazo and m.sem_fornecedor and m.prazo_real_du is not null
         and m.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje
       group by m.entrega),
    recentes as (
      select e.*, row_number() over (order by e.chegou desc, e.entrega) as rn from entregas e)
    select count(*)::int, array_agg(rc.du order by rc.chegou desc, rc.entrega),
           jsonb_agg(jsonb_build_object('entrega', rc.entrega, 'numero', rc.numero, 'du', rc.du, 'em', rc.chegou) order by rc.chegou desc, rc.entrega)
      into v_n, v_vals, v_am
      from recentes rc
     where rc.rn <= c.fator_amostra_max;
    v_p := public._agenda_percentil(v_vals, c.fornecedor_percentil);
    v_calc := case when v_p is not null then least(c_max, greatest(0, ceil(v_p))) end;
    v := public._agenda_aprendizado_gravar('prazo_sem_fornecedor', 'todas', 'geral', v_calc, v_n, coalesce(v_am, '[]'::jsonb), c.prazo_sem_fornecedor_du,
           jsonb_build_object('percentil', v_p, 'n', v_n), p_agora);
    return jsonb_build_object('chaves', 1, 'estados', jsonb_build_object(v ->> 'estado', 1), 'acoes', 0, 'erros', 0);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, peça sem fornecedor: %s', sqlerrm), 'agenda', 'aprender:prazo_sem_fornecedor', 'error', jsonb_build_object('sqlstate', sqlstate, 'p_hoje', p_hoje));
    return jsonb_build_object('chaves', 1, 'estados', '{}'::jsonb, 'acoes', 0, 'erros', 1);
  end;
end;
$function$;

comment on function public._agenda_aprender_prazo_sem_fornecedor(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P6; §5.5, §3.2): o passo da peça sem fornecedor da rodada do aprendizado — as entregas com linha valida_prazo e sem_fornecedor que chegaram em aprender_janela_dias (o maior prazo_real_du por entrega; as fator_amostra_max mais recentes); calculado = o percentil fornecedor_percentil, para cima, de 0 a 30 dias úteis; padrão prazo_sem_fornecedor_du. Só medida: o gravador nunca a põe em uso (quem muda o padrão é o dono). Invoker, sem grant (o P7 o chama).';

-- ── 2. As recriadas ───────────────────────────────────────────────────────────────────────────────

-- _agenda_aprender_fornecedor (de 20261029100900_agenda_fase6_correcao_calculo.sql:1203; md5 do corpo de antes c3ac59cf8a2166cb436d644a4276516e)
create or replace function public._agenda_aprender_fornecedor(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  r      record;
  v      jsonb;
  v_p    numeric;
  v_calc numeric;
  v_pad  numeric;
  v_pf   jsonb;
  v_dono boolean;
  v_est  jsonb := '{}'::jsonb;
  n_ch   int := 0;
  n_acao int := 0;
  n_perg int := 0;
  n_err  int := 0;
  -- FASE 7e: (7e P6, §5.5, R7.6) a entrega pela compra (agenda_medidas_compra). Pelo modo efetivo: com o freio, ligado vale como sombra (o número em uso do fornecedor não muda enquanto o freio estiver puxado)
  v_7e_modo text := public._agenda_margem_modo('tempo_compra');
  v_7e_ent  text[];
  v_7e_nc   int;
  v_7e_cv   numeric[];
  v_7e_ca   jsonb;
  v_7e_nv   numeric[];
  v_7e_na   jsonb;
  v_7e_nn   int;
  v_7e_det  jsonb;
  -- FASE 7e: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 6: (C1) itens 2 e 8: o laço de baixo (o de antes) não faz mais nada (o "continue" no começo dele); vale
  -- este, que é ele com duas mudanças — (item 2) o atraso mede só as entregas com a 1ª previsão de quem vende (fornecedor,
  -- OC ou Pix): a da nota (nfe) já é "saída + prazo" e fica só para o prazo medido (senão o prazo e o atraso contariam duas
  -- vezes o mesmo transporte); (item 8) o fornecedor é o da medida (_agenda_fornecedor_da_medida: o cadastro inativo mede
  -- pelo principal, que é por onde o prazo e o atraso são lidos), e as entregas e as notas se juntam por ele.
  for r in
    with linhas as (
      select m.id, so.service_order_number as numero, m.previsao_original, m.chegou_em,
             public._agenda_fornecedor_da_medida(coalesce(m.fornecedor_id, po.supplier_id, rm.fornecedor_id)) as forn,
             coalesce('nota:' || m.remessa_id::text, 'oc:' || poi.purchase_order_id::text, 'linha:' || m.id::text) as entrega
        from public.os_material m
        join public.service_orders so on so.id = m.service_order_id
        left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
        left join public.purchase_orders po on po.id = poi.purchase_order_id
        left join public.material_remessas rm on rm.id = m.remessa_id
       where m.situacao = 'na_mao' and m.chegou_em is not null and m.previsao_original is not null
         and m.previsao_original_fonte in ('fornecedor', 'oc', 'pix')
         -- FASE 7e: (7e P6, §5.5 (a), d6) com o modo ligado de verdade, a previsão dita antes da compra sai do atraso (não é promessa do fornecedor). Em sombra e desligado, a medida de antes, byte a byte
         and not (v_7e_modo = 'ligado' and exists (select 1 from public.agenda_medidas_compra mc
                                                    where mc.os_material_id = m.id and mc.previsao_original_em < mc.comprado_em))
         -- FASE 7e: fim
         and m.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje),
    entregas as (
      select l.forn, l.entrega, max(public.agenda_du_entre(l.previsao_original, l.chegou_em)) as atraso,
             max(l.chegou_em) as chegou, count(*)::int as linhas, min(l.numero) as numero
        from linhas l
       where l.forn is not null
       group by l.forn, l.entrega),
    atrasos as (
      select 'fornecedor_atraso'::text as item, e.forn, count(*)::int as n,
             array_agg(e.atraso::numeric order by e.chegou desc, e.entrega) as vals,
             count(*) filter (where e.atraso <= 0)::int as no_prazo,
             jsonb_agg(jsonb_build_object('entrega', e.entrega, 'numero', e.numero, 'linhas', e.linhas, 'atraso', e.atraso,
                                          'em', e.chegou) order by e.chegou desc, e.entrega) as amostra
        from entregas e
       group by e.forn),
    notas as (
      select rm.*, public._agenda_fornecedor_da_medida(rm.fornecedor_id) as forn
        from public.material_remessas rm
       where rm.estado = 'chegou' and rm.fornecedor_id is not null and rm.despacho_em is not null
         and rm.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje),
    prazos as (
      select 'fornecedor_prazo'::text as item, rm.forn, count(*)::int as n,
             array_agg(public.agenda_du_entre(rm.despacho_em, rm.chegou_em)::numeric order by rm.chegou_em desc, rm.id) as vals,
             null::int as no_prazo,
             jsonb_agg(jsonb_build_object('nota', rm.numero, 'remessa', rm.id, 'despacho', rm.despacho_em, 'em', rm.chegou_em,
                                          'du', public.agenda_du_entre(rm.despacho_em, rm.chegou_em))
                       order by rm.chegou_em desc, rm.id) as amostra
        from notas rm
       group by rm.forn)
    select x.item, x.forn, x.n, x.vals, x.no_prazo, x.amostra from atrasos x
    union all
    select y.item, y.forn, y.n, y.vals, y.no_prazo, y.amostra from prazos y
    -- FASE 7e: (7e P6, §5.5 (b)) o fornecedor que só tem compra medida e ainda não tem linha nasce pela compra (o medindo com o "teria" em sombra; em ligado, entra no n e no valor, logo abaixo). Quem já tem linha vem pelo ramo de baixo
    union all
    select 'fornecedor_prazo'::text, z.forn, 0, null::numeric[], null::int, '[]'::jsonb
      from (select distinct public._agenda_fornecedor_da_medida(mc.fornecedor_id) as forn
              from public.agenda_medidas_compra mc
             where v_7e_modo <> 'desligado' and mc.valida_prazo and mc.fornecedor_id is not null
               and mc.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje) z
     where z.forn is not null
       and not exists (select 1 from prazos y where y.forn = z.forn)
       and not exists (select 1 from public.agenda_aprendizado a where a.item = 'fornecedor_prazo' and a.chave = z.forn::text)
    -- FASE 7e: fim
    union all
    -- o fornecedor que já tem linha e ficou sem medida (saiu da janela, ou mede agora pelo principal): volta a medir
    select a.item, a.chave::uuid, 0, null::numeric[], 0, '[]'::jsonb
      from public.agenda_aprendizado a
     where a.item in ('fornecedor_atraso', 'fornecedor_prazo')
       and not exists (select 1 from atrasos x where x.item = a.item and x.forn::text = a.chave)
       and not exists (select 1 from prazos y where y.item = a.item and y.forn::text = a.chave)
     order by 1, 2
  loop
    n_ch := n_ch + 1;
    begin
      -- FASE 7e: (7e P6, §5.5 (b)) as entregas pela compra entram em fornecedor_prazo: a compra conta da compra; a nota, só do despacho, e a nota da mesma entrega sai para não contar duas vezes. O maior prazo de cada entrega (como no atraso).
      -- Com o modo ligado de verdade entram no n e nos valores (detalhe.fonte = 'compras'); em sombra só no detalhe.teria, e o calculado é o de antes. Sem compra medida: nada muda e o detalhe é o de antes, byte a byte.
      v_7e_det := '{}'::jsonb;
      if r.item = 'fornecedor_prazo' and v_7e_modo <> 'desligado' then
        select count(*)::int, array_agg(e.entrega), array_agg(e.du::numeric),
               jsonb_agg(jsonb_build_object('entrega', e.entrega, 'compra', e.comprado, 'em', e.em, 'du', e.du) order by e.em desc, e.entrega)
          into v_7e_nc, v_7e_ent, v_7e_cv, v_7e_ca
          from (select mc.entrega, max(mc.prazo_real_du)::int as du, max(mc.chegou_em) as em, min(mc.comprado_em) as comprado
                  from public.agenda_medidas_compra mc
                 where mc.valida_prazo and mc.fornecedor_id is not null and mc.prazo_real_du is not null
                   and public._agenda_fornecedor_da_medida(mc.fornecedor_id) = r.forn
                   and mc.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje
                 group by mc.entrega) e;
        if v_7e_nc > 0 then
          select coalesce(array_agg((a.x ->> 'du')::numeric order by a.o), '{}'), coalesce(jsonb_agg(a.x order by a.o), '[]'::jsonb), count(*)::int
            into v_7e_nv, v_7e_na, v_7e_nn
            from jsonb_array_elements(coalesce(r.amostra, '[]'::jsonb)) with ordinality a(x, o)
           where ('nota:' || coalesce(a.x ->> 'remessa', '')) <> all (v_7e_ent);
          if v_7e_modo = 'ligado' then
            r.n := v_7e_nc + v_7e_nn;
            r.vals := v_7e_nv || v_7e_cv;
            r.amostra := v_7e_na || v_7e_ca;
            v_7e_det := jsonb_build_object('fonte', 'compras', 'compras', v_7e_nc, 'notas', v_7e_nn);
          else
            v_7e_det := jsonb_build_object('teria', jsonb_build_object('n', v_7e_nc + v_7e_nn,
                                                                       'du', greatest(0, ceil(public._agenda_percentil(v_7e_nv || v_7e_cv, c.fornecedor_percentil)))));
          end if;
        end if;
      end if;
      -- FASE 7e: fim
      v_p := public._agenda_percentil(r.vals, c.fornecedor_percentil);
      v_dono := false;
      if r.item = 'fornecedor_atraso' then
        v_pad := 0;
        v_calc := case when v_p is not null then greatest(0, ceil(v_p)) end;
      else
        v_pf := public._agenda_prazo_do_fornecedor(r.forn);
        v_dono := v_pf ->> 'fonte' = 'dono';
        v_pad := coalesce((v_pf ->> 'du_classe')::numeric, (v_pf ->> 'du')::numeric);
        v_calc := case when v_p is not null and v_pad is not null and not v_dono then greatest(0, ceil(v_p)) end;
      end if;
      -- FASE 7e: (7e P6) com compra medida, a gravação de baixo com o detalhe a mais (a fonte ou o teria); sem compra, o caminho de baixo, byte a byte
      if v_7e_det <> '{}'::jsonb then
        v := public._agenda_aprendizado_gravar(r.item, r.forn::text, 'fornecedor', v_calc, r.n, r.amostra, v_pad,
               jsonb_build_object('nome', public._agenda_fornecedor_curto(r.forn), 'n', r.n, 'no_prazo', r.no_prazo,
                                  'p50', public._agenda_percentil(r.vals, 0.5), 'dono', v_dono) || v_7e_det, p_agora);
        v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
        if v ->> 'acao_id' is not null then n_acao := n_acao + 1; end if;
        if v ->> 'pergunta_id' is not null then n_perg := n_perg + 1; end if;
        continue;
      end if;
      -- FASE 7e: fim
      v := public._agenda_aprendizado_gravar(r.item, r.forn::text, 'fornecedor', v_calc, r.n, r.amostra, v_pad,
             jsonb_build_object('nome', public._agenda_fornecedor_curto(r.forn), 'n', r.n, 'no_prazo', r.no_prazo,
                                'p50', public._agenda_percentil(r.vals, 0.5), 'dono', v_dono), p_agora);
      v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
      if v ->> 'acao_id' is not null then n_acao := n_acao + 1; end if;
      if v ->> 'pergunta_id' is not null then n_perg := n_perg + 1; end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, %s %s: %s', r.item, r.forn, sqlerrm), 'agenda', 'aprender:fornecedor',
                                   'error', jsonb_build_object('item', r.item, 'fornecedor', r.forn, 'sqlstate', sqlstate,
                                                               'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  -- CORREÇÃO FASE 6: fim
  for r in
    with linhas as (
      select m.id, so.service_order_number as numero, m.previsao_original, m.chegou_em,
             coalesce(m.fornecedor_id, po.supplier_id, rm.fornecedor_id) as forn,
             coalesce('nota:' || m.remessa_id::text, 'oc:' || poi.purchase_order_id::text, 'linha:' || m.id::text) as entrega
        from public.os_material m
        join public.service_orders so on so.id = m.service_order_id
        left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
        left join public.purchase_orders po on po.id = poi.purchase_order_id
        left join public.material_remessas rm on rm.id = m.remessa_id
       where m.situacao = 'na_mao' and m.chegou_em is not null and m.previsao_original is not null
         and m.previsao_original_fonte in ('fornecedor', 'oc', 'nfe', 'pix')
         and m.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje),
    entregas as (
      select l.forn, l.entrega, max(public.agenda_du_entre(l.previsao_original, l.chegou_em)) as atraso,
             max(l.chegou_em) as chegou, count(*)::int as linhas, min(l.numero) as numero
        from linhas l
       where l.forn is not null
       group by l.forn, l.entrega),
    atrasos as (
      select 'fornecedor_atraso'::text as item, e.forn, count(*)::int as n,
             array_agg(e.atraso::numeric order by e.chegou desc, e.entrega) as vals,
             count(*) filter (where e.atraso <= 0)::int as no_prazo,
             jsonb_agg(jsonb_build_object('entrega', e.entrega, 'numero', e.numero, 'linhas', e.linhas, 'atraso', e.atraso,
                                          'em', e.chegou) order by e.chegou desc, e.entrega) as amostra
        from entregas e
       group by e.forn),
    prazos as (
      select 'fornecedor_prazo'::text as item, rm.fornecedor_id as forn, count(*)::int as n,
             array_agg(public.agenda_du_entre(rm.despacho_em, rm.chegou_em)::numeric order by rm.chegou_em desc, rm.id) as vals,
             null::int as no_prazo,
             jsonb_agg(jsonb_build_object('nota', rm.numero, 'remessa', rm.id, 'despacho', rm.despacho_em, 'em', rm.chegou_em,
                                          'du', public.agenda_du_entre(rm.despacho_em, rm.chegou_em))
                       order by rm.chegou_em desc, rm.id) as amostra
        from public.material_remessas rm
       where rm.estado = 'chegou' and rm.fornecedor_id is not null and rm.despacho_em is not null
         and rm.chegou_em between p_hoje - c.aprender_janela_dias and p_hoje
       group by rm.fornecedor_id)
    select x.item, x.forn, x.n, x.vals, x.no_prazo, x.amostra from atrasos x
    union all
    select y.item, y.forn, y.n, y.vals, y.no_prazo, y.amostra from prazos y
    union all
    -- o fornecedor que já tem linha e ficou sem medida (saiu da janela): volta a medir
    select a.item, a.chave::uuid, 0, null::numeric[], 0, '[]'::jsonb
      from public.agenda_aprendizado a
     where a.item in ('fornecedor_atraso', 'fornecedor_prazo')
       and not exists (select 1 from atrasos x where x.item = a.item and x.forn::text = a.chave)
       and not exists (select 1 from prazos y where y.item = a.item and y.forn::text = a.chave)
     order by 1, 2
  loop
    -- CORREÇÃO FASE 6: (C1) itens 2 e 8: o laço de antes não faz mais nada (vale o de cima)
    continue;
    -- CORREÇÃO FASE 6: fim
    n_ch := n_ch + 1;
    begin
      v_p := public._agenda_percentil(r.vals, c.fornecedor_percentil);
      v_dono := false;
      if r.item = 'fornecedor_atraso' then
        -- o padrão é chegar no dia dito (0); o atraso conta em dias úteis inteiros, para cima, e nunca adianta a chegada
        v_pad := 0;
        v_calc := case when v_p is not null then greatest(0, ceil(v_p)) end;
      else
        -- o padrão é o prazo de hoje (o do dono, o da classe pela cidade ou pelo nome; nunca o medido, que é este);
        -- o que o dono disse vem antes do medido: só mede (fica medindo); o importado (dias corridos) e o sem lugar também
        v_pf := public._agenda_prazo_do_fornecedor(r.forn);
        v_dono := v_pf ->> 'fonte' = 'dono';
        v_pad := coalesce((v_pf ->> 'du_classe')::numeric, (v_pf ->> 'du')::numeric);
        v_calc := case when v_p is not null and v_pad is not null and not v_dono then greatest(0, ceil(v_p)) end;
      end if;
      v := public._agenda_aprendizado_gravar(r.item, r.forn::text, 'fornecedor', v_calc, r.n, r.amostra, v_pad,
             jsonb_build_object('nome', public._agenda_fornecedor_curto(r.forn), 'n', r.n, 'no_prazo', r.no_prazo,
                                'p50', public._agenda_percentil(r.vals, 0.5), 'dono', v_dono), p_agora);
      v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
      if v ->> 'acao_id' is not null then n_acao := n_acao + 1; end if;
      if v ->> 'pergunta_id' is not null then n_perg := n_perg + 1; end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, %s %s: %s', r.item, r.forn, sqlerrm), 'agenda', 'aprender:fornecedor',
                                   'error', jsonb_build_object('item', r.item, 'fornecedor', r.forn, 'sqlstate', sqlstate,
                                                               'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  return jsonb_build_object('chaves', n_ch, 'estados', v_est, 'acoes', n_acao, 'perguntas', n_perg, 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_fornecedor(date, timestamptz) is
  'Agenda de Produção (Fase 6, P3): o passo do fornecedor da rodada — (1) fornecedor_atraso por fornecedor: as entregas da janela (aprender_janela_dias; as linhas de os_material na mão com a 1ª previsão de fornecedor/OC/nota/Pix, agrupadas por fornecedor e nota, senão OC, senão linha: 3 linhas da mesma nota = 1 entrega; o fornecedor = o da linha, senão o da OC, senão o da nota; o atraso = o maior agenda_du_entre(previsao_original, chegou_em) das linhas, assinado), calculado = o P80 (fornecedor_percentil) arredondado para cima e nunca abaixo de 0, padrão 0, detalhe {nome, n, no_prazo, p50}; (2) fornecedor_prazo por fornecedor: as notas que chegaram (material_remessas, da saída à chegada), padrão = o prazo de hoje de _agenda_prazo_do_fornecedor (du_classe quando o medido já está em uso); o que o dono disse vem antes (só mede). Tudo pelo gravador (_agenda_aprendizado_gravar), nível fornecedor, chave = o id do fornecedor. O erro de um fornecedor vai a app_error_logs (agenda / aprender:fornecedor) e o passo segue. Nenhuma mensagem ao fornecedor. {chaves, estados, acoes, perguntas, erros}. Sem grant a ninguém. CORREÇÃO FASE 6 (C1): (item 2) o atraso mede só as entregas com a 1ª previsão de fornecedor, OC ou Pix (a da nota já é saída + prazo: fica só para fornecedor_prazo); (item 8) o fornecedor é o da medida (_agenda_fornecedor_da_medida: o cadastro inativo mede pelo principal), e as entregas e as notas se juntam por ele. FASE 7e (P6, §5.5): com modo_tempo_compra ligado de verdade (o freio apaga), fornecedor_prazo mede também as entregas registradas em agenda_medidas_compra (o maior prazo por entrega, da compra à chegada); a nota da mesma entrega sai (detalhe.fonte = compras, compras, notas); e o atraso deixa de fora a previsão dita antes da compra. Em sombra: só detalhe.teria {n, du}, e o calculado é o de antes (e o atraso também). Desligado, ou sem compra medida: a saída de antes, byte a byte.';

-- os_prontidao (de 20261031100980_agenda_fase77a_correcao.sql:2044; md5 do corpo de antes c69862188638af46cbb0d2d9d1b1e7ea)
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
  -- FASE 7e: (7e P6, R7.5-15) o tempo interno de compra da OS (nulos = o parâmetro de sempre)
  v_7e_interno int;
  v_7e_param   int;
  -- FASE 7e: fim
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
  -- FASE 7e: (7e P6, §5.5, R7.5-15, R7.8) o tempo interno de compra de ESTA OS, na única conta que o usa (compra_firme, logo abaixo): o congelado na marcação, senão, com modo_tempo_compra ligado de verdade, o medido em uso (_agenda_tempo_interno_compra, por dentro).
  -- O portão lê o que já está na mão (a linha da config e a de planejamento: em sombra, zero chamada nova, R7.8). c é a cópia local desta função: a conta de baixo fica como está. Com o freio, fora da simulação do gestor, v_f7_firme é falsa e nada disto roda; na simulação (agenda.gestor = sombra, _agenda_gestor_regra verdadeira) a regra roda: a OS marcada usa o número dela, lido da linha, e a sem marcação fica no parâmetro sem chamar a função, que com o freio devolveria o mesmo parâmetro.
  if v_f7_firme and jsonb_array_length(v_itens) > 0 and (p.tempo_compra_marcado is not null or (c.modo_tempo_compra = 'ligado' and not c.gestor_so_propor)) then
    v_7e_param := c.compra_interna_du;
    v_7e_interno := coalesce(p.tempo_compra_marcado::int, public._agenda_tempo_interno_compra(p_so_id));
    c.compra_interna_du := v_7e_interno;
  end if;
  -- FASE 7e: fim
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
  -- FASE 7e: (7e P6, §5.5) o item em falta que contou o tempo interno leva o número, só quando ele é diferente do parâmetro (fora disso, a saída de antes, byte a byte). A folga própria não entra (R7.5-16: sem leitor nesta etapa).
  if v_7e_interno <> v_7e_param then
    select jsonb_agg(case when t.e ->> 'compra_prevista_em' is null and coalesce((t.e ->> 'compra_firme')::boolean, false)
                          then t.e || jsonb_build_object('tempo_interno_du', v_7e_interno) else t.e end order by t.o)
      into v_itens from jsonb_array_elements(v_itens) with ordinality t(e, o);
  end if;
  -- FASE 7e: fim

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
          -- (7a correção, achado 20) acima do teto de diárias, o gestor espera o dono (sem prazo)
          case when coalesce((v_f7_sit ->> 'sem_padrao')::boolean, false)
                 then format('perguntei antes de marcar: pelo orçamento são %s diárias, mais de %s, então espero você',
                             public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(c.estimativa_max_diarias))
               when v_f7_sit ->> 'tipo' = 'parada'
                 then format('perguntei se ainda é para fazer o serviço inteiro; sem resposta, conto %s',
                             public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric))
               when coalesce((v_f7_sit ->> 'rastro')::boolean, false)
                 then format('perguntei quanto falta; sem resposta, marco %s para terminar',
                             public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric))
               else format('perguntei se já começou; sem resposta, conto %s', public._agenda_dias((v_f7_sit ->> 'proposta_dias')::numeric)) end
        when 'grande' then
          -- (7a correção, achado 20) acima do teto de diárias, sem prazo: o gestor espera o dono
          format('pelo valor do orçamento são %s diárias, mais de %s: perguntei antes de marcar e espero você dizer os dias',
                 public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(c.estimativa_max_diarias))
        when 'embutida' then
          format('pode ter peça junto em "%s": perguntei antes de marcar; sem resposta, marco %s',
                 v_f7_est #>> '{embutida,0,curto}', public._agenda_dias((v_f7_est ->> 'proposta_dias')::numeric))
        else
          format('o orçamento não tem mão de obra separada: perguntei quantos dias; sem resposta, marco %s',
                 public._agenda_dias((v_f7_est ->> 'proposta_dias')::numeric)) end;
      -- (7a correção, achado 24) enquanto o gestor espera a resposta (ou o prazo), a duração trava: a OS não é "pronta para
      -- começar" no painel, no *livre* e no "Amanhã" do fechamento se o gestor não a marca
      v_r := (select coalesce(jsonb_agg(case when e ->> 'tipo' = 'duracao'
                                             then e || jsonb_build_object('texto', v_f7_txt, 'bloqueia', true) else e end
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

  -- FASE 7: (7a correção, achado 24) a OS que o gestor pergunta antes de marcar (a situação, ou a duração que ele não estima
  -- sozinho: a restrição situacao ou duracao que trava, que só nasce com as regras do gestor) espera o dono: não é "pronta para
  -- começar" (o "Amanhã" do fechamento, o *livre* e o painel diziam "prontos: Nelson, Giancarlo" enquanto ele perguntava)
  if v_estado = 'pronta' and exists (select 1 from jsonb_array_elements(v_r) e
                                      where e ->> 'tipo' in ('situacao', 'duracao') and coalesce((e ->> 'bloqueia')::boolean, false)) then
    v_estado := 'esperando_voce';
  end if;
  -- FASE 7: fim
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
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P2: a linha de OC recebida ligada a um item de texto livre da conta conta só nele, não de novo como item da OC que já chegou; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira. Fase 6 (P3): no item de nível B, enquanto o dia dito não chegou e com o atraso do fornecedor em uso (fornecedor_atraso: _agenda_aprendido), data = a data provável (o dia dito + o atraso; é ela que move o DPM, o início pelo material e o motor), data_dita = o dia dito (o fato) e data_texto "a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11"; atrasado e sem_data continuam pelo dia dito (a "chegou?"); C, A, D e E não mudam; sem atraso em uso, o item é o de antes. CORREÇÃO FASE 6 (C1): (item 1) material.inicio_mat_dito = o início pelo material pelo dia DITO (sem o atraso do fornecedor), só quando a data provável muda o início — _agenda_violacoes julga por ele o que já está publicado; (item 2) a previsão da nota (nfe) não ganha o atraso do fornecedor (já é saída + prazo); (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida: o inativo pelo principal). Sem atraso em uso, a saída é a de antes, byte a byte. CORREÇÃO 29/10 (P5): (1) o prazo do fornecedor uma vez por item (a barreira no passo 6; antes ~25 contas por item); (2) dentro da rodada da vigia (agenda.rodada), o resultado de cada OS é lembrado (_agenda_rodada_lembrar e _agenda_rodada_guardar), enquanto a transação não grava nada no que ela lê. O resultado é o mesmo, byte a byte. FASE 7 (7a P3), atrás do portão _agenda_gestor_regra (falso = a saída de antes, byte a byte): critico_por_valor (AG7-05) — sem o fato do dono, o item é crítico só com o valor unitário de venda >= critico_valor_min (sem valor = crítico), e ganha separar_vespera e valor_unit; prazo_padrao (AG7-06) — sem prazo do fornecedor, prazo_sem_fornecedor_du dias úteis, classe padrao, nível D ("sem fornecedor: contei 7 dias úteis"; o comprado sem previsão chega pelo dia da compra); compra_firme (AG7-07) — a chegada "se comprar" e o "compre até" contam compra_interna_du; o "compre até" gravado (os_material.compre_ate) da OS com compromisso segura a data enquanto não vence; o item em falta com "compre até" (ou compra combinada com chegada) abaixo de compre_ate_empurroes_max ganha compra_firme; sem_peca — a OS sem linha de material conta como sem peça (restrição sem_peca_suposta, que não trava); embutida_suposta — a peça embutida não trava ("Contei que não; se tiver, me diga") nem deixa o material não conferido; estimativa (D7-1) — sem os dias ditos e com _agenda_gestor_estimativa em uso, a duração é a fonte orcamento e a restrição duracao não nasce; sem usar (situacao, grande, embutida, sem_base), a restrição duracao diz o que o gestor faz sem resposta; os dias orcamento gravados dizem "(estimativa minha)"; situacao (AG7-11) — a restrição situacao, que trava (o texto de _agenda_os_situacao). CORREÇÃO DA 7a (revisão da etapa), no bloco da 7a P3 e num bloco novo: (achado 20) acima de estimativa_max_diarias, a restrição duracao e a situação dizem que o gestor perguntou e espera o dono (sem "sem resposta, marco"); (achado 24) enquanto o gestor pergunta antes de marcar (situacao, grande, sem_base), a restrição duracao trava (bloqueia) e a OS que seria pronta fica esperando_voce: não aparece como pronta para começar no painel, no *livre* e no "Amanhã". Com o portão falso, a de antes, byte a byte. FASE 7e (P6, §5.5, R7.5-15): com compra_firme, o tempo interno é o da OS: o congelado (tempo_compra_marcado), senão, com modo_tempo_compra ligado de verdade, o medido em uso (_agenda_tempo_interno_compra); o item em falta que contou um número diferente do parâmetro ganha tempo_interno_du. Em sombra e com o freio (também na simulação do gestor), a OS sem marcação: a saída de antes, byte a byte, sem chamada nova (R7.8). A OS marcada usa o número dela na conta de compra_firme, que com o freio só roda na simulação do gestor.';

-- _agenda_gestor_compra_conta (de 20261031100800_agenda_fase7a_compras.sql:104; md5 do corpo de antes 559c1ecb44eab4dce4bdb91d0221e34b)
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
  -- FASE 7e: (7e P6, R7.5-15) o tempo interno desta OS (o congelado, o medido em uso, o parâmetro: nunca nulo, também sem linha de planejamento) nas 3 contas de baixo: o "compre até", a base gravada e o v_mesma, para a prontidão e o gravado não discordarem nem a linha "mudar" a cada rodada.
  c.compra_interna_du := public._agenda_tempo_interno_compra(p_os);
  -- FASE 7e: fim
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
  'Agenda de Produção (Fase 7a, P10; spec §5.10, AG7-05/06/07): a conta do "compre até" de uma OS com compromisso de hoje em diante (null sem ele) — para cada item crítico em falta da os_prontidao de hoje, sem compra combinada e com prazo (fornecedor, cidade, medido, o prazo padrão sem fornecedor ou o importado em dias corridos): compre_ate = o 1º dia − folga_material_du − o prazo − compra_interna_du (o gravado vale enquanto a base não muda: muda); prazo_final = sem o tempo interno; ate = o dia que o dono ouve (o compre_ate; depois do 1º empurrão, o prazo_final: "compre hoje"); chega (comprando hoje, a chegada + a folga até o 1º dia); urgente (o 1º dia antes de compra_urgente_du dias úteis); empurrou (o gravado venceu, o 1º dia andou e a OS foi remarcada pelo material: a ação executada com o motivo material depois do gravado); empurrada_vezes e limite (compre_ate_empurroes_max). E os não críticos (separar). {os, numero, cliente, primeiro, itens, separar}. Nada gravado. STABLE, invoker, sem grant. FASE 7e (P6, R7.5-15): o tempo interno vem de _agenda_tempo_interno_compra (o congelado, o medido em uso, o parâmetro) nas 3 contas: o compre_ate, a base (interno) e o v_mesma; o mesmo número da prontidão.';

-- _agenda_ver_gestor (de 20261101100850_agenda_fase77b_correcao2.sql:408; md5 do corpo de antes 9a4f0eff1587a01a4963ac4161a64731)
create or replace function public._agenda_ver_gestor(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_ef    text := public._agenda_gestor_modo('marcar');
  v_l     text[] := '{}';
  v_desde date;
  v_sdia  date;
  v_s     jsonb;
  v_cart  uuid[];
  v_fora  jsonb := '[]'::jsonb;
  v_n     int;
  v_comp  jsonb;
  v_orc   jsonb;
  v_mo    numeric := public._agenda_mo_por_diaria_real();
  x       jsonb;
  r       record;
  -- (7a correção, achado 3) o "Como eu conto" à parte, sempre no fim
  v_como  text;
  v_k     int;
  -- FASE 7: (7a correção 2) quem a grade tem (a dupla sem a 2ª pessoa) e o fim do dia (o *desfaz* do dono)
  v_f72_tec   text[];
  v_f72_dup   text;
  v_f72_agora timestamptz;
  -- FASE 7: fim
  -- FASE 7b: (7b P6) a dupla de 1 pessoa no lugar do "Pode precisar de dupla" e o bloco "Quem chamar"
  v_7b_dupla boolean := (public._agenda_cfg()).modo_dupla <> 'desligado';
  v_7b_tf    text;
  v_7b_m     jsonb;
  v_7b_pl    jsonb;
  v_7b_d     jsonb;
  v_7b_fa    jsonb;
  v_7b_ni    int;
  v_7b_nf    int;
  v_7b_x     text;
  v_7b_y     text;
  v_7b_r1    text;
  v_7b_r2    text;
  v_7b_z     text;
  v_7b_ch    jsonb;
  v_7b_cdia  date;
  v_7b_cab   text;
  v_7b_pela  text;
  v_7b_bul   text[];
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 1, 5, 9, 11, 15 e 23) o bloco "Quem chamar" no fim que sempre entra, a dupla que é só
  -- nota e o exemplo com todos os dias. c_7bc_max é estrutural: o tamanho do bloco no fim (o resto, "(e mais N linhas)").
  c_7bc_max  constant int := 700;
  v_7bc_n    int := 0;
  v_7bc_ch   text[] := '{}';
  v_7bc_l0   text;
  v_7bc_dias text;
  v_7bc_mais int := 0;
  -- FASE 7b: fim
  -- FASE 7b: (correção 2, achado 26 da 7a) os dias do "Marquei nos últimos 7 dias" sem o turno do dono que vai junto
  v_c2_m     jsonb;
  v_c2_dono  uuid := public._agenda_dono(null);
  -- FASE 7b: fim (correção 2)
begin
  if p_hoje is null then
    raise exception '_agenda_ver_gestor: sem o dia de hoje' using errcode = '22004';
  end if;

  -- 1. o estado (uma linha)
  if cf.gestor_so_propor then
    v_l := v_l || case when cf.gestor_so_propor_em is not null
                       then format('Desde %s você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.',
                                   public._dia_curto((cf.gestor_so_propor_em at time zone 'America/Sao_Paulo')::date))
                       else 'Você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.' end;
  elsif cf.modo_marcar_sozinho = 'ligado' then
    v_l := v_l || case when cf.marcar_sozinho_desde is not null
                       then format('Eu marco sozinho desde %s e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.',
                                   public._dia_curto((cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date))
                       else 'Eu marco sozinho e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.' end;
  elsif cf.modo_marcar_sozinho = 'sombra' then
    select min(g.dia) into v_desde from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.modos ->> 'marcar' = 'sombra'
       and g.dia > coalesce((select max(h.dia) from public.agenda_gestor_dia h
                              where h.dia <= p_hoje and h.modos ->> 'marcar' is distinct from 'sombra'), date '-infinity');
    v_l := v_l || case when v_desde is not null
                       then format('O gestor está em teste desde %s: calcula o que marcaria, mas não muda nada.', public._dia_curto(v_desde))
                       else 'O gestor está em teste: calcula o que marcaria, mas não muda nada.' end;
  else
    v_l := v_l || 'O gestor da agenda está desligado: não marco nada sozinho.'::text;
  end if;

  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, o "Pode precisar de dupla" diz que falta a
  -- 2ª pessoa e o que fazer antes do *<nome> com dupla* (sem isso a palavra tirava a OS da agenda, calada)
  v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
  v_f72_dup := case when cardinality(v_f72_tec) < 2
                    then replace(format('hoje %s: para ir dupla, chame um ajudante e ', public._agenda_tecnicos_frase(v_f72_tec)), '%', '%%')
                    else '' end;
  v_f72_agora := (p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
  -- FASE 7: fim
  -- FASE 7b: (7b P6) quem a grade tem, na frase da dupla de 1 pessoa (a da marcação do P4)
  v_7b_tf := case when cardinality(v_f72_tec) >= 2 then 'ninguém mais está livre nesses meios-dias'
                  else public._agenda_tecnicos_frase(v_f72_tec) end;
  -- FASE 7b: fim
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k
                   where not public._agenda_os_tem_dia(k.service_order_id, p_hoje));

  if v_ef = 'sombra' then
    -- 2–4 em teste: a última conta do "eu marcaria assim" (o diário do gestor)
    select g.dia, g.sombra into v_sdia, v_s from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.sombra <> '{}'::jsonb order by g.dia desc limit 1;
    if v_s is null then
      v_l := v_l || 'Eu marcaria: ainda não fiz a conta (faço todo dia útil no fim da tarde).'::text;
    else
      if jsonb_array_length(coalesce(v_s -> 'itens', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(v_s -> 'reservas', '[]'::jsonb)) = 0 then
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ': nada agora.');
      else
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ':');
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'itens', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: %s, %s — %s (%s)%s.%s', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas',
                               public._agenda_dias((x ->> 'dias')::numeric),
                               case x ->> 'fonte' when 'orcamento' then 'estimativa minha' else 'você disse' end,
                               case when x ->> 'compre_ate' is not null
                                    then format('; compre até %s: %s',
                                                case when (x ->> 'compre_ate')::date <= p_hoje then 'hoje'
                                                     else public._dia_curto((x ->> 'compre_ate')::date) end,
                                                public._agenda_itens((x ->> 'itens_a_comprar')::int))
                                    else '' end,
                               case when jsonb_typeof(x -> 'alerta_dupla') = 'object'
                                    then format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                public._agenda_gestor_dupla_texto(x -> 'alerta_dupla'), x ->> 'cliente')
                                    else '' end);
          -- FASE 7b: (correção da revisão da 7b, achados 5 e 9) a linha como o 7a a deixou (o bloco do P6, logo abaixo, a troca)
          v_7bc_l0 := v_l[cardinality(v_l)];
          -- FASE 7b: fim
          -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com
          -- dupla*" do 7a sai: com a 7b, *com dupla* é "o tempo todo" e faz a OS esperar a 2ª pessoa. Em teste do gestor não há plano:
          -- a frase da dupla de 1 pessoa (R4.3(a)(3)) na forma curta, sem as datas ("Nos 2 primeiros meios-dias a troca do banco de
          -- baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga os dias dele."), pelos meios-dias do que
          -- a tarefa pede (_agenda_dupla_da_os: fora da simulação, o molde não tem o dk da regra uma_pessoa do gestor em teste)
          if v_7b_dupla and jsonb_typeof(x -> 'alerta_dupla') = 'object' then
            v_7b_m := public._agenda_dupla_da_os((x ->> 'os')::uuid);
            if v_7b_m ->> 'fonte' = 'regra' then
              v_7b_ni := coalesce((v_7b_m ->> 'inicio')::int, 0);
              v_7b_nf := coalesce((v_7b_m ->> 'fim')::int, 0);
              v_7b_x := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
              v_7b_y := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
              v_7b_z := case
                when coalesce((v_7b_m ->> 'todos')::boolean, false)
                  then format(' O serviço todo pede 2 pessoas (%s) e %s: se chamar um ajudante, me diga os dias dele.',
                              coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                         where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf)
                when v_7b_ni > 0 and v_7b_nf > 0
                  then format(' %s %s e %s %s pedem 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                when v_7b_ni > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              v_7b_tf)
                when v_7b_nf > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                else '' end;
              v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
            end if;
          end if;
          -- FASE 7b: fim
          -- FASE 7b: (correção da revisão da 7b, achado 5) com modo_dupla fora de desligado, a OS em que a dupla é só nota (o espaço
          -- confinado: _agenda_dupla_da_os sem fonte de regra nem do dono) continua com o "Pode precisar de dupla" do 7a, mas dizendo o que
          -- *com dupla* quer dizer na 7b (o tempo todo: com só um técnico, a OS espera a 2ª pessoa) e, com menos de 2 técnicos, os dias do
          -- ajudante antes da palavra.
          if v_7b_dupla and jsonb_typeof(x -> 'alerta_dupla') = 'object' and v_l[cardinality(v_l)] like '% Pode precisar de dupla (%'
             and coalesce(public._agenda_dupla_da_os((x ->> 'os')::uuid) ->> 'fonte', '') not in ('regra', 'dono') then
            v_l[cardinality(v_l)] := replace(replace(v_l[cardinality(v_l)], 'chame um ajudante e diga *', 'chame um ajudante, me diga os dias dele e diga *'),
                                             ' com dupla*.', ' com dupla* (em dupla o tempo todo).');
          end if;
          -- (achado 9) o que a 7b acrescentou à linha da 7a não tira espaço das outras linhas da 7a (o "Fora:", o "Se aprovar:")
          v_7bc_mais := v_7bc_mais + char_length(v_l[cardinality(v_l)]) - char_length(v_7bc_l0);
          -- FASE 7b: fim
        end loop;
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'reservas', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: reservaria %s, %s.', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas');
        end loop;
      end if;
      if jsonb_array_length(coalesce(v_s -> 'perguntas', '[]'::jsonb)) > 0 then
        v_l := v_l || 'Antes de marcar eu perguntaria:'::text;
        for x in select e from jsonb_array_elements(v_s -> 'perguntas') with ordinality t(e, o) order by o loop
          v_l := v_l || (format('• %s: %s', x ->> 'cliente', x ->> 'curto')
                         || case when right(x ->> 'curto', 1) in ('?', '.') then '' else '.' end);
        end loop;
      end if;
      v_fora := coalesce(v_s -> 'fora', '[]'::jsonb);
    end if;
  elsif v_ef = 'ligado' then
    -- 2. o que o gestor marcou nos últimos 7 dias: as OS com compromisso vigente pela estimativa (duracao_fonte orcamento)
    v_n := 0;
    v_l := v_l || 'Marquei nos últimos 7 dias:'::text;
    for r in select a.service_order_id as os, min(a.dia) as de, max(a.dia) as ate,
                    count(*) filter (where a.presenca = 'turno') as meios,
                    jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia,
                                                 'turno', a.turno, 'presenca', a.presenca)) as alocs
               from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento'
                and a.dia >= p_hoje and a.resultado is null
              group by a.service_order_id
             having min((a.criado_em at time zone 'America/Sao_Paulo')::date) >= p_hoje - 7
              order by min(a.dia), a.service_order_id loop
      v_n := v_n + 1;
      -- FASE 7b: (correção 2, achado 26 da 7a) os dias sem o turno do dono que vai junto com alguém (o critério de
      -- _agenda_gestor_pessoa_meios: ele só é uma das pessoas quando o molde o conta): o Lenine marcado com o Alex e você nos 6 dias
      -- dizia "Alex — 12 dias (estimativa minha)"
      v_c2_m := public.agenda_meios_da_os(r.os, p_hoje);
      if v_c2_m ? 'dono_turno'
         and not ((coalesce((v_c2_m #>> '{dono_turno,manha}')::boolean, false) or coalesce((v_c2_m #>> '{dono_turno,tarde}')::boolean, false))
                  and (coalesce((v_c2_m ->> 'equipe_dita')::boolean, true) or not public._agenda_gestor_regra('uma_pessoa')
                       or coalesce(v_c2_m ->> 'regra_motivo', '') in ('diagnóstico', 'comissionamento'))) then
        r.meios := r.meios - (select count(*) from jsonb_array_elements(r.alocs) c2a(e)
                               where c2a.e ->> 'presenca' = 'turno' and (c2a.e ->> 'payee_id')::uuid = v_c2_dono
                                 and exists (select 1 from jsonb_array_elements(r.alocs) c2b(e)
                                              where c2b.e ->> 'presenca' = 'turno' and c2b.e ->> 'dia' = c2a.e ->> 'dia'
                                                and c2b.e ->> 'turno' = c2a.e ->> 'turno' and c2b.e ->> 'payee_id' <> c2a.e ->> 'payee_id'));
      end if;
      -- FASE 7b: fim (correção 2)
      v_l := v_l || format('• %s: %s, %s — %s (estimativa minha).%s',
                           coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                       join public.clients cl on cl.id = so.client_id where so.id = r.os), 'serviço'),
                           public._agenda_gestor_faixa(r.de, r.ate), public._agenda_gestor_pessoas(r.alocs),
                           public._agenda_dias(r.meios::numeric / 2),
                           coalesce((select format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                   public._agenda_gestor_dupla_texto(d.a), public._agenda_nome_curto(cl.name))
                                       from (select public.os_duracao_sugerida(r.os) -> 'alerta_dupla' as a) d,
                                            public.service_orders so join public.clients cl on cl.id = so.client_id
                                      where so.id = r.os and jsonb_typeof(d.a) = 'object'), ''));
      -- FASE 7b: (correção da revisão da 7b, achados 11 e 23) a linha como o 7a a deixou (o bloco do P6, logo abaixo, a troca)
      v_7bc_l0 := v_l[cardinality(v_l)];
      -- FASE 7b: fim
      -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla" do 7a vira a frase da dupla
      -- de 1 pessoa (R4.3(a)(3), a da marcação do P4) com as datas do plano: os meios-dias em que a dupla pela tarefa ainda está sem a
      -- 2ª pessoa (_agenda_dupla_no_plano, fora da reserva). Com a 2ª pessoa em todos (a dupla completa), nada.
      if v_7b_dupla and v_l[cardinality(v_l)] like '% Pode precisar de dupla (%' then
        v_7b_pl := public._agenda_dupla_no_plano(r.os, p_hoje);
        v_7b_d := public._agenda_dupla_da_os(r.os);
        select coalesce(jsonb_agg(e order by (e ->> 'dia')::date, e ->> 'turno'), '[]'::jsonb) into v_7b_fa
          from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) e
         where not coalesce((e ->> 'reserva')::boolean, false) and v_7b_pl ->> 'fonte' = 'regra';
        select public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e
                          where e ->> 'onde' in ('inicio', 'todos')) z
                  group by z.d order by z.d)),
               public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim') z
                  group by z.d order by z.d))
          into v_7b_x, v_7b_y;
        v_7b_ni := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'inicio');
        v_7b_nf := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim');
        v_7b_r1 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
        v_7b_r2 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
        v_7b_z := case
          when jsonb_array_length(v_7b_fa) = 0 then ''
          when exists (select 1 from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'todos')
            then format(' O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                   where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf,
                        public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> '' and v_7b_y <> ''
            then format(' %s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> ''
            then format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          else format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                      v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date)) end;
        v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
      end if;
      -- FASE 7b: fim
      -- FASE 7b: (correção da revisão da 7b, achados 11 e 23) a dupla que é só nota (o espaço confinado) não some: o bloco do P6 tirava o
      -- "Pode precisar de dupla" e não punha nada (sem dupla pela tarefa, a frase dele fica vazia) — volta a do 7a, dizendo que *com
      -- dupla* é o tempo todo e, com menos de 2 técnicos, os dias do ajudante antes. Na dupla pela tarefa, o exemplo diz todos os dias em
      -- que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem qua 18 e qui 19/11").
      if v_7b_dupla and v_7bc_l0 like '% Pode precisar de dupla (%' then
        if coalesce(v_7b_d ->> 'fonte', '') not in ('regra', 'dono') and coalesce(v_7b_pl ->> 'fonte', '') <> 'regra' then
          v_l[cardinality(v_l)] := replace(replace(v_7bc_l0, 'chame um ajudante e diga *', 'chame um ajudante, me diga os dias dele e diga *'),
                                           ' com dupla*.', ' com dupla* (em dupla o tempo todo).');
        elsif jsonb_array_length(coalesce(v_7b_fa, '[]'::jsonb)) > 0
              and (select count(distinct e ->> 'dia') from jsonb_array_elements(v_7b_fa) e) > 1 then
          v_7bc_dias := regexp_replace(public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_fa) e order by 1)),
                                       ' \([^()]*\)$', '');
          v_l[cardinality(v_l)] := replace(v_l[cardinality(v_l)],
                                           format('(ex.: Mateus vem %s).', public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date)),
                                           format('(ex.: Mateus vem %s).', v_7bc_dias));
        end if;
      end if;
      -- (achado 9) o que a 7b acrescentou à linha da 7a não tira espaço das outras linhas da 7a (o "Fora:", o "Se aprovar:")
      v_7bc_mais := v_7bc_mais + char_length(v_l[cardinality(v_l)]) - char_length(v_7bc_l0);
      -- FASE 7b: fim
    end loop;
    if v_n = 0 then
      v_l[cardinality(v_l)] := 'Marquei nos últimos 7 dias: nada.';
    end if;
    -- 3. o que ele perguntou antes de marcar (as abertas de verdade, com o prazo)
    v_n := 0;
    for r in select q.* from public.agenda_perguntas q
                     left join public.service_orders so on so.id = q.service_order_id
              where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
              order by q.veto_ate nulls last, so.service_order_number desc nulls last, q.id loop
      if v_n = 0 then
        v_l := v_l || 'Perguntei antes de marcar:'::text;
      end if;
      v_n := v_n + 1;
      v_l := v_l || format('• %s: %s — %s',
        -- (7a correção 2) o número da OS junto quando o nome se repete nas perguntas abertas (Kalmar OS-00032 e OS-00033)
        case when (select count(*) from public.agenda_perguntas q2
                     join public.service_orders s2 on s2.id = q2.service_order_id
                     left join public.clients c2 on c2.id = s2.client_id
                    where q2.estado = 'aberta' and q2.modo = 'ligado' and q2.tipo in ('situacao', 'estimativa')
                      and public._agenda_nome_curto(c2.name) is not distinct from
                          (select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id)) > 1
             then public._agenda_rotulo_da_os(r.service_order_id)
             else coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                              join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id), 'serviço') end,
        coalesce(nullif(public._agenda_gestor_estimativa(r.service_order_id, p_hoje) ->> 'texto', ''),
                 case split_part(r.chave, ':', 3) when 'comecada' then 'já começou?' when 'rastro' then 'quanto falta?'
                                                  when 'parada' then 'ainda é para fazer?' when 'grande' then 'muitas diárias pela estimativa'
                                                  when 'embutida' then 'pode ter peça junto'
                                                  else 'não tem mão de obra separada' end),
        case when r.opcao_escolhida is not null then 'você vai me dizer os dias.'
             when r.veto_ate is not null
               then format('sem resposta até %s %s, marco assim.',
                           public._dia_curto((r.veto_ate at time zone 'America/Sao_Paulo')::date),
                           to_char(r.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI'))
             else 'espero você.' end);
    end loop;
    -- 4. quem fica de fora: o porquê da última conta do motor (a proposta de verdade mais nova que falou da OS, em 8 dias),
    -- das OS da carteira sem compromisso e sem pergunta aberta do gestor
    select coalesce(jsonb_agg(jsonb_build_object('os', t.os, 'cliente', t.cliente, 'motivo', t.motivo,
                                                 'grupo', public._agenda_gestor_motivo_texto(
                                                   -- (7a correção 2) a OS que o dono desfez: o porquê é o *desfaz*, não "sem lugar"
                                                   case when public._agenda_gestor_desfeito(t.os::uuid, v_f72_agora) then 'desfeito'
                                                        else t.motivo end)) order by t.numero), '[]'::jsonb)
      into v_fora
      from (select distinct on (f ->> 'os') f ->> 'os' as os, f ->> 'cliente_curto' as cliente, f ->> 'motivo' as motivo,
                   f ->> 'numero' as numero
              from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
             where pr.modo = 'ligado' and pr.criada_em >= ((p_hoje - 8)::timestamp at time zone 'America/Sao_Paulo')
               and f ->> 'motivo' is distinct from 'fora_da_carteira'
               and (f ->> 'os')::uuid = any (v_cart)
               and not exists (select 1 from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
                                  and q.service_order_id = (f ->> 'os')::uuid)
             order by f ->> 'os', pr.criada_em desc, pr.id desc) t;
  end if;

  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) onde o bloco "Quem chamar" começa
  v_7bc_n := coalesce(cardinality(v_l), 0);
  -- FASE 7b: fim
  -- FASE 7b: (7b P6, R4.4 "Onde aparece") o bloco "Quem chamar" (depois de "Perguntei antes de marcar"), só com modo_chamar fora de
  -- desligado: o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de
  -- …" quando não é de hoje). Em teste, "Em teste:" na frente. Só sugere: quem chama é o dono.
  if cf.modo_chamar <> 'desligado' then
    select g.dia, g.chamar into v_7b_cdia, v_7b_ch from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.chamar ? 'calculado_em' order by g.dia desc limit 1;
    v_7b_cab := case when cf.modo_chamar = 'sombra' then 'Em teste: quem chamar' else 'Quem chamar' end;
    v_7b_pela := case when v_7b_cdia is not null and v_7b_cdia <> p_hoje then format('pela conta de %s', public._dia_curto(v_7b_cdia)) end;
    if v_7b_ch is null then
      v_l := v_l || (v_7b_cab || ': ainda não fiz a conta (faço todo dia útil no fim da tarde).');
    else
      v_7b_bul := array(select u.l from unnest(string_to_array(coalesce(v_7b_ch ->> 'texto', ''), E'\n')) with ordinality u(l, o)
                         where u.l like '•%' order by u.o);
      if cardinality(v_7b_bul) = 0 then
        v_l := v_l || (v_7b_cab || coalesce(' (' || v_7b_pela || ')', '') || ': ninguém — a equipe de hoje dá conta da carteira que está pronta.');
      else
        v_l := v_l || (v_7b_cab || ' (' || concat_ws('; ', v_7b_pela, 'só sugiro; quem chama é você') || '):') || v_7b_bul;
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) o bloco "Quem chamar" sai do meio do foco: o corte (_agenda_gestor_juntar,
  -- no meio) o escondia com o texto_max de sempre — em teste ele é o único lugar da sugestão — e, em teste, ele tomava o lugar das linhas
  -- da 7a ("Fora:", "Se aprovar:"). Vai para o fim que sempre entra, logo antes do "Como eu conto" (abaixo).
  if cf.modo_chamar <> 'desligado' and coalesce(cardinality(v_l), 0) > v_7bc_n then
    v_7bc_ch := v_l[v_7bc_n + 1 : cardinality(v_l)];
    v_l := v_l[1 : v_7bc_n];
  end if;
  -- FASE 7b: fim
  -- 4. Fora: agrupado pelo porquê, os nomes (o número junto quando o nome se repete)
  if jsonb_array_length(v_fora) > 0 then
    v_l := v_l || ('Fora: ' || (
      select string_agg(g.grupo || ': ' || g.nomes, '; ' order by public._agenda_gestor_motivo_ordem(g.grupo), g.grupo)
        from (select h.grupo, public._agenda_lista(array_agg(h.nome || case when h.n > 1 then format(' (%s)', h.n) else '' end
                                                             order by h.primeiro), 4) as nomes
                from (select f ->> 'grupo' as grupo, f ->> 'cliente' as nome, count(*) as n, min(o) as primeiro
                        from jsonb_array_elements(v_fora) with ordinality t(f, o)
                       group by f ->> 'grupo', f ->> 'cliente') h
               group by h.grupo) g) || '.');
  end if;

  -- 5. as compras da semana (o diário do gestor; o P10 grava) e 6. os orçamentos que caberiam (o P12 grava): de até 3 dias
  select g.compras into v_comp from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.compras <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_comp, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Compras da semana:'::text;
    -- (7a correção, achado 3) até 3 por seção: toda seção cabe com o "Como eu conto"
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_comp) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_comp) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s em *agenda compras*)', v_k - 3);
    end if;
  end if;
  select g.orcamentos into v_orc from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.orcamentos <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_orc, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Se aprovar:'::text;
    -- (7a correção, achado 3) até 3 (os de maior valor)
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_orc) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_orc) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s %s)', v_k - 3, case when v_k - 3 = 1 then 'orçamento' else 'orçamentos' end);
    end if;
  end if;

  -- FASE 7e: (7e P6, R7.5-15) o "entre decidir e comprar" diz o número certo: com modo_tempo_compra ligado, o medido em uso (sem OS: nada de congelado; com o freio ou sem medida, o parâmetro). Em sombra, nada muda e nada é chamado.
  if cf.modo_tempo_compra = 'ligado' then
    cf.compra_interna_du := public._agenda_tempo_interno_compra(null);
  end if;
  -- FASE 7e: fim
  -- 7. como eu conto (todos os números dos parâmetros)
  -- (7a correção, achado 3) o "Como eu conto" à parte: entra sempre, no fim (_agenda_gestor_juntar)
  v_como := format('Como eu conto: estimativa pelo valor do orçamento (R$ %s de mão de obra por diária, sem deslocamento); '
                       || '%s por serviço (dupla quando você marcar); peça sem fornecedor: %s; peça abaixo de R$ %s: separar na '
                       || 'véspera; entre decidir e comprar: %s%s; pergunto antes acima de %s diárias e quando o serviço já começou.',
                       replace(to_char(round(v_mo), 'FM999,999,990'), ',', '.'),
                       case when cf.equipe_padrao = 1 then '1 pessoa' else cf.equipe_padrao || ' pessoas' end,
                       public._agenda_plural(cf.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis'),
                       replace(to_char(round(cf.critico_valor_min), 'FM999,999,990'), ',', '.'),
                       public._agenda_plural(cf.compra_interna_du, 'dia útil', 'dias úteis'),
                       case when cf.compra_urgente_du > 0
                            then format(' (com o serviço a menos de %s, a compra é para hoje)',
                                        public._agenda_plural(cf.compra_urgente_du, 'dia útil', 'dias úteis'))
                            else '' end,
                       public._agenda_num(cf.estimativa_max_diarias));

  -- (7a correção, achado 3) o conteúdo até texto_max, e o "Como eu conto" (os parâmetros, spec §6.2 item 7) depois dele: as 7 seções
  -- da spec não cabem em texto_max com ele dentro, e era ele que sumia
  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) o bloco "Quem chamar" entra no fim, junto do "Como eu conto": o conteúdo da
  -- 7a continua com o texto_max inteiro, e o bloco vem depois dele, até c_7bc_max letras (o resto "(e mais N linhas)")
  if cardinality(v_7bc_ch) > 0 then
    v_como := public._agenda_juntar(v_7bc_ch, c_7bc_max) || E'\n' || v_como;
  end if;
  -- (achado 9) e o que a 7b acrescentou às linhas da 7a (a frase da dupla de 1 pessoa, a da dupla que é só nota) não tira lugar das
  -- outras linhas da 7a: o conteúdo ganha esse tanto (nunca perde)
  cf.texto_max := cf.texto_max + greatest(v_7bc_mais, 0);
  -- FASE 7b: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_gestor_juntar(v_l, cf.texto_max + 1 + char_length(v_como), v_como),
                            'dados', jsonb_build_object('modo', v_ef, 'so_propor', cf.gestor_so_propor, 'conta_de', v_sdia,
                                                        'sombra', v_s, 'fora', v_fora));
end;
$function$;

comment on function public._agenda_ver_gestor(date) is
  'Agenda de Produção (Fase 7a, P7; spec §6.2): o foco gestor de agenda_ver — (1) o estado: "O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada." / "Eu marco sozinho desde ter 03/11 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz." / "Desde sex 06/11 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta." / desligado; (2) em teste, "Eu marcaria:" pela última conta do diário (agenda_gestor_dia.sombra), um por linha ("• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*."); ligado, "Marquei nos últimos 7 dias:" (as OS com compromisso vigente pela estimativa); (3) "Antes de marcar eu perguntaria:" (teste) ou "Perguntei antes de marcar:" com o prazo ("• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim."); (4) "Fora:" agrupado pelo porquê ("esperando o cliente: Kalmar (2) e Rodrigo; …"; ligado, pela última conta de verdade do motor em 8 dias); (5) "Compras da semana:" e (6) "Se aprovar:" pelo diário (agenda_gestor_dia.compras e .orcamentos, [{texto}], de até 3 dias; o P10 e o P12 gravam); (7) "Como eu conto:" com os parâmetros. {ok, texto (≤ texto_max), dados}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa; achado 3): o "Como eu conto" entra sempre, no fim (_agenda_gestor_juntar: o corte é no meio, nunca num título sem linha embaixo, como o "Se aprovar:" vazio); as compras da semana e o "Se aprovar" mostram até 3 cada (o resto: "(e mais 3 orçamentos)", "(e mais N em *agenda compras*)"). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): (a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, "Pode precisar de dupla (banco de baterias): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Lenine com dupla*."; (o desfaz) ligado, a OS de fora que o dono desfez vai no grupo "você desfez (me diga os dias para eu marcar de novo)", não em "sem lugar na agenda"; (o número) em "Perguntei antes de marcar", o número da OS junto quando o nome se repete ("Kalmar (OS-00032)"). FASE 7b (P6, R4.4): com modo_chamar fora de desligado, o bloco "Quem chamar" depois de "Perguntei antes de marcar" — o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de …" quando não é de hoje): "Quem chamar (só sugiro; quem chama é você):" e uma linha por sugestão, ou "Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta."; em teste, "Em teste: quem chamar …". Com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com dupla*" do 7a vira a frase da dupla de 1 pessoa (R4.3(a)(3)): ligado, com as datas do plano (_agenda_dupla_no_plano: "Nos 2 primeiros meios-dias (ter 10/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem ter 10/11)."; com a dupla completa, nada); em teste do gestor, a forma curta sem as datas. Com modo_chamar e modo_dupla desligados, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 1, 5, 9, 11, 15 e 23): o bloco "Quem chamar" vai para o fim que sempre entra, logo antes do "Como eu conto" (até 700 letras; o conteúdo da 7a continua com o texto_max inteiro) — antes ele ficava no meio e o corte o escondia, ou tomava o lugar do "Fora:" e do "Se aprovar:"; com modo_dupla fora de desligado, a OS em que a dupla é só nota (o espaço confinado) continua com o "Pode precisar de dupla (espaço apertado): … diga *Otávio com dupla* (em dupla o tempo todo)." (com menos de 2 técnicos, "chame um ajudante, me diga os dias dele e diga …"), também ligado (antes sumia); o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa. CORREÇÃO 2 DA 7b (achado 26 da revisão da 7b, que é da 7a): no "Marquei nos últimos 7 dias", os dias de cada OS não contam o turno do dono nos meios-dias em que ele vai junto com alguém (o critério de _agenda_gestor_pessoa_meios: ele só é uma das pessoas quando o molde o conta — o turno inteiro e, além disso, a equipe dita, a regra uma_pessoa desligada, o diagnóstico ou o comissionamento) — o Lenine marcado com o Alex e você nos 6 dias dizia "Alex — 12 dias (estimativa minha)"; agora "6 dias". Com o dono contado pelo molde, a de antes, byte a byte. FASE 7e (P6, R7.5-15): o "entre decidir e comprar" do "Como eu conto" sai de _agenda_tempo_interno_compra com modo_tempo_compra ligado; em sombra, o parâmetro.';

-- _agenda_aprendizado_texto (de 20261111100300_agenda_fase7e_folga.sql:3344; md5 do corpo de antes 3da677f2b336f2fd012ccb96bde4f4a0)
create or replace function public._agenda_aprendizado_texto(p_item text, p_momento text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nivel  text := public._agenda_classe_texto_do_nivel(p_d ->> 'chave');
  v_calc   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'calculado')::numeric);
  v_uso    text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'em_uso')::numeric);
  v_efet   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'efetivo')::numeric);
  v_padrao text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'padrao')::numeric);
  v_volta  text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'volta')::numeric);
  v_n      text := p_d ->> 'n';
  v_nmin   text := p_d ->> 'n_min';
  v_desde  text := public._dia_curto(nullif(p_d ->> 'desde', '')::date);
  v_trava  text := public._dia_curto(nullif(p_d ->> 'travado_ate', '')::date);
  v_dias   text := p_d ->> 'trava_dias';
  v_rotulo text;
begin
  -- FASE 7e: (7e P2, §6.2, §6.3, R7.3, R7.5-19, R7.5-20, R7.12-9) os textos dos 6 itens da margem, antes de todos (um item da margem nunca passa pelos de baixo). Sem jargão: "o do meio" é a mediana e "8 em cada 10" é o percentil 80. n = 0 diz
  -- "nenhuma ... ainda" (nunca "medi"). Promessa (AG7-32) e folga da compra (R7.5-16: sem leitor nesta etapa) só têm os textos de medindo e em teste: o gravador nunca as põe em uso. Tudo número daqui sai de p_d (o gravador).
  if p_item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor') then
    declare
      v_7e_chave text := regexp_replace(coalesce(p_d ->> 'chave', ''), '^(estimativa|dono):', '');
      v_7e_dono  boolean := coalesce(p_d ->> 'chave', '') like 'dono:%';
      v_7e_cls   text := public._agenda_classe_texto_do_nivel(v_7e_chave);
      v_7e_geral boolean := v_7e_chave = 'todas';
      v_7e_n     int := coalesce((p_d ->> 'n')::int, 0);
      v_7e_alvo  boolean := (p_d ->> 'em_uso')::numeric is not distinct from (p_d ->> 'calculado')::numeric;
      v_7e_sobe  boolean := (p_d ->> 'em_uso')::numeric > (p_d ->> 'efetivo')::numeric;
      v_7e_num   text := public._agenda_num((p_d ->> 'efetivo')::numeric, 1);
      v_7e_pnum  text := public._agenda_num((p_d ->> 'padrao')::numeric, 1);
      v_7e_lei   text;
      v_7e_guarda text;
      v_7e_resto text;
    begin
      if p_item = 'vies' then
        v_7e_lei := case when v_7e_dono then format('nos dias que você diz, as OS levam %s o que você combinou', v_calc)
                         else format('%s levam %s o que eu estimo pelo orçamento', coalesce(v_7e_cls, 'as OS'), v_calc) end;
        return case p_momento
          when 'foco_medindo' then
            case when v_7e_dono then format('Nos dias que você diz: %s; conto os seus dias como você disse.',
                                            case when v_7e_n = 0 then 'nenhuma OS medida ainda' else format('%s de %s OS medidas', v_n, v_nmin) end)
                 else format('Estimativa pelo valor: %s; marco os dias como saem do orçamento.',
                             case when v_7e_n = 0 then 'nenhuma OS medida ainda' else format('%s de %s OS medidas', v_n, v_nmin) end) end
          when 'foco_sombra' then
            case when v_7e_dono then format('Em teste: %s (%s OS medidas). Hoje conto os seus dias como você disse.', v_7e_lei, v_n)
                 when v_7e_geral then format('Em teste: %s (%s OS medidas). Hoje marco os dias como saem do orçamento.', v_7e_lei, v_n)
                 else format('Em teste: %s (%s OS medidas; junto com o geral das OS). Hoje marco os dias como saem do orçamento.', v_7e_lei, v_n) end
          when 'foco_em_uso' then
            case when v_7e_dono and v_7e_alvo then format('%s (%s OS medidas): corrijo os seus dias com %s desde %s, e digo sempre os dois números.', public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde)
                 when v_7e_dono then format('%s (%s OS medidas): corrijo os seus dias com %s desde %s e chego a %s aos poucos (até %s× por dia); digo sempre os dois números.',
                                            public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde, v_calc, public._agenda_num((p_d ->> 'passo')::numeric, 2))
                 when v_7e_alvo then format('%s (%s OS medidas): marco os dias delas com %s desde %s.', public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde)
                 else format('%s (%s OS medidas): marco com %s desde %s e chego a %s aos poucos (até %s× por dia).',
                             public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde, v_calc, public._agenda_num((p_d ->> 'passo')::numeric, 2)) end
          when 'foco_travado' then format('%s (%s OS medidas); fico com %s até %s, como você decidiu.', public._agenda_maiuscula(v_7e_lei), v_n, v_efet, v_trava)
          when 'acao' then
            case when v_7e_dono then format('Aprendi com as OS concluídas: %s (%s OS). Passei a contar os seus dias com %s (era %s), sempre dizendo os dois números, só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.',
                                            v_7e_lei, v_n, v_uso, v_efet)
                 when v_7e_alvo then format('Aprendi com as OS concluídas: %s (%s OS). Passei a marcar os dias delas com %s (era %s), só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.',
                                            v_7e_lei, v_n, v_uso, v_efet)
                 else format('Aprendi com as OS concluídas: %s (%s OS). Passei a marcar com %s (era %s) e %s até %s aos poucos, só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.',
                             v_7e_lei, v_n, v_uso, v_efet, case when v_7e_sobe then 'subo' else 'desço' end, v_calc) end
          -- R7.5-19 e 20: volta um passo só (o valor de p_d.volta, nunca o padrão de cabeça), e a OS já marcada guarda o valor que tinha
          when 'desfeito' then
            case when v_7e_dono then format('Desfeito: os seus dias voltam a %s, só nos serviços que eu ainda não marquei. Não troco de novo por %s dias, salvo se o medido mudar muito.', v_volta, v_dias)
                 else format('Desfeito: %s voltam a %s o que sai do orçamento, só nas que eu ainda não marquei. Não troco de novo por %s dias, salvo se o medido mudar muito.', coalesce(v_7e_cls, 'as OS'), v_volta, v_dias) end
        end;
      elsif p_item = 'folga_semana' then
        -- o total guardado (1 − carga_max) e a parte que não é medida (urgência e falta): o resto do padrão
        v_7e_guarda := round((1 - (p_d ->> 'carga_max')::numeric) * 100)::text || '%';
        v_7e_resto := round((1 - (p_d ->> 'carga_max')::numeric - (p_d ->> 'padrao')::numeric) * 100)::text || '%';
        -- (7e P4, R7.4, R7.9, §0-4; marca sem FASE porque está dentro do bloco do P2) sem número medido (calculado nulo). Com as semanas já no mínimo, o "N de M" da §6.2 diria "12 de 8" e não diz o que falta: aqui o que falta são as OS medidas (quem manda é o resíduo, R7.9) ou que elas mostrem variação (σ = 0). E a folga em uso que ficou sem medida volta ao padrão por passo: a linha e a ação dizem isso, e não "medi".
        if (p_d ->> 'calculado') is null then
          declare
            v_7e_res   int := coalesce((p_d #>> '{detalhe,residuos}')::int, 0);
            v_7e_rmin  int := (p_d #>> '{detalhe,residuos_min}')::int;
            v_7e_basta boolean := v_7e_n >= (p_d ->> 'n_min')::int;
            v_7e_igual boolean := (p_d ->> 'em_uso')::numeric = (p_d ->> 'padrao')::numeric;
            v_7e_falta text := case when not v_7e_basta then format('%s de %s semanas com serviço marcado medidas', v_n, v_nmin)
                                    when v_7e_res = 0 then 'nenhuma OS medida ainda'
                                    when v_7e_res < v_7e_rmin then format('%s de %s OS medidas', v_7e_res, v_7e_rmin)
                                    else format('as %s OS medidas ainda não mostraram variação', v_7e_res) end;
          begin
            if p_momento = 'foco_medindo' and v_7e_basta then
              return format('Folga da semana: as semanas já bastam (%s), mas falta saber o quanto as OS variam: %s; guardo %s da semana da equipe (%s para o serviço que passa do previsto e %s para urgência e falta).', v_n, v_7e_falta, v_7e_guarda, v_padrao, v_7e_resto);
            elsif p_momento = 'foco_em_uso' then
              return case when v_7e_igual then format('Sem medida para a folga da semana (%s): voltei a guardar os %s de sempre da semana para o serviço que passa do previsto.', v_7e_falta, v_padrao)
                          else format('Sem medida para a folga da semana (%s): guardo %s da semana para o serviço que passa do previsto desde %s e volto aos %s de sempre aos poucos.', v_7e_falta, v_uso, v_desde, v_padrao) end;
            elsif p_momento = 'foco_travado' then
              return format('Sem medida para a folga da semana (%s); fico com %s até %s, como você decidiu.', v_7e_falta, v_efet, v_trava);
            elsif p_momento = 'acao' then
              return case when v_7e_igual then format('Fiquei sem medida para a folga da semana (%s). Voltei a guardar os %s de sempre da semana para o serviço que passa do previsto (era %s). *desfaz aprendizado* volta.', v_7e_falta, v_padrao, v_efet)
                          else format('Fiquei sem medida para a folga da semana (%s). Passei a guardar %s da semana para o serviço que passa do previsto (era %s) e volto aos %s de sempre aos poucos. *desfaz aprendizado* volta.', v_7e_falta, v_uso, v_efet, v_padrao) end;
            end if;
          end;
        end if;
        -- (7e: fim)
        return case p_momento
          when 'foco_medindo' then format('Folga da semana: %s; guardo %s da semana da equipe (%s para o serviço que passa do previsto e %s para urgência e falta).',
                                          case when v_7e_n = 0 then 'nenhuma semana com serviço marcado medida ainda' else format('%s de %s semanas com serviço marcado medidas', v_n, v_nmin) end,
                                          v_7e_guarda, v_padrao, v_7e_resto)
          when 'foco_sombra' then format('Em teste: pelo quanto as OS variaram em %s semanas, %s da semana bastariam para o serviço que passa do previsto; hoje guardo %s.', v_n, v_calc, v_padrao)
          when 'foco_em_uso' then
            case when v_7e_alvo then format('Pelo quanto as OS variaram em %s semanas, guardo %s da semana para o serviço que passa do previsto desde %s (era %s).', v_n, v_uso, v_desde, v_padrao)
                 else format('Pelo quanto as OS variaram em %s semanas, guardo %s da semana para o serviço que passa do previsto desde %s e chego a %s aos poucos (era %s).', v_n, v_uso, v_desde, v_calc, v_padrao) end
          when 'foco_travado' then format('Pelo quanto as OS variaram em %s semanas, %s da semana bastariam para o serviço que passa do previsto; fico com %s até %s, como você decidiu.', v_n, v_calc, v_efet, v_trava)
          when 'acao' then format('Medi %s semanas de serviço marcado: as OS variaram %s do que eu contava. Passei a guardar %s da semana para o serviço que passa do previsto (era %s)%s. *desfaz aprendizado* volta.',
                                  v_n, case when v_7e_sobe then 'mais' else 'menos' end, v_uso, v_efet,
                                  case when (p_d #>> '{detalhe,proxima_semana}') is not null then ': ' || (p_d #>> '{detalhe,proxima_semana}') else '' end)
          when 'desfeito' then format('Desfeito: volto a guardar %s da semana para o serviço que passa do previsto. Não troco de novo por %s dias, salvo se o medido mudar muito.', v_volta, v_dias)
        end;
      elsif p_item = 'promessa' then
        -- só para o dono (AG7-32): o cliente não ouve data de pronto, e por isso não há "em uso" nem "em teste" aqui
        return case when v_7e_n = 0 then 'Prazo real: nenhuma OS medida ainda. Só para você: ao cliente não digo data de pronto.'
                    when (p_d ->> 'calculado') is null or v_7e_n < coalesce((p_d ->> 'n_min')::int, 1)
                      then format('Prazo real: %s de %s OS medidas. Só para você: ao cliente não digo data de pronto.', v_n, v_nmin)
                    else format('Prazo real: %s em cada 10 OS terminaram em até %s os dias planejados (%s OS). Com essa folga, um serviço de 5 dias acaba em até %s dias úteis. Só para você: ao cliente não digo data de pronto.',
                                round(coalesce((p_d ->> 'fator_percentil')::numeric, (p_d #>> '{detalhe,percentil}')::numeric) * 10),
                                public._agenda_aprendizado_valor('promessa', coalesce((p_d #>> '{detalhe,p80}')::numeric, (p_d ->> 'calculado')::numeric)),
                                v_n, round(5 * (p_d ->> 'calculado')::numeric)) end;
      elsif p_item = 'tempo_compra' then
        return case p_momento
          when 'foco_medindo' then format('Seu tempo para comprar: %s (da aprovação até a compra); no "compre até" conto %s (padrão).',
                                          case when v_7e_n = 0 then 'nenhuma OS medida ainda' else format('%s de %s OS medidas', v_n, v_nmin) end, v_padrao)
          when 'foco_sombra' then format('Em teste: da aprovação até a compra você levou %s (o do meio de %s OS); junto com o padrão de %s, eu contaria %s no "compre até". Hoje conto %s.',
                                         public._agenda_aprendizado_valor(p_item, (p_d #>> '{detalhe,percentil}')::numeric), v_n, v_7e_pnum, v_calc, v_7e_pnum)
          when 'foco_em_uso' then
            case when v_7e_alvo then format('Da aprovação até a compra você leva por volta de %s (%s OS medidas): é o que conto no "compre até" desde %s.', v_uso, v_n, v_desde)
                 else format('Da aprovação até a compra você leva por volta de %s (%s OS medidas): conto %s no "compre até" desde %s e chego lá aos poucos.', v_calc, v_n, v_uso, v_desde) end
          when 'foco_travado' then format('Da aprovação até a compra você leva por volta de %s (%s OS medidas); fico com %s no "compre até" até %s, como você decidiu.', v_calc, v_n, v_efet, v_trava)
          when 'acao' then format('Medi o seu tempo da aprovação até a compra (%s OS): passei a contar %s no "compre até" (era %s), só nas OS que eu ainda não marquei: o pedido de compra sai %s mais %s. *desfaz aprendizado* volta.',
                                  v_n, v_uso, v_7e_num, public._agenda_aprendizado_valor(p_item, abs((p_d ->> 'em_uso')::numeric - (p_d ->> 'efetivo')::numeric)),
                                  case when v_7e_sobe then 'cedo' else 'tarde' end)
          when 'desfeito' then format('Desfeito: volto a contar %s no "compre até", só nas OS que eu ainda não marquei. Não troco de novo por %s dias, salvo se o medido mudar muito.', v_volta, v_dias)
        end;
      elsif p_item = 'folga_compra' then
        return case when p_momento = 'foco_sombra' then
                 format('Em teste: nas OS marcadas antes da compra, a peça chegou até %s depois do que eu contava (%s OS; %s no prazo; %s começaram no dia marcado); eu daria %s a mais só a elas. Hoje não dou.',
                        public._agenda_aprendizado_valor(p_item, (p_d #>> '{detalhe,maior}')::numeric), v_n, coalesce(p_d #>> '{detalhe,no_prazo}', '0'), coalesce(p_d #>> '{detalhe,comecaram_no_dia}', '0'), v_calc)
               else format('OS marcadas antes da compra: %s; dou %s entre a chegada da peça e o 1º dia, como em todas.',
                           case when v_7e_n = 0 then 'nenhuma medida ainda' else format('%s de %s medidas', v_n, v_nmin) end,
                           public._agenda_aprendizado_valor(p_item, coalesce((p_d ->> 'folga_material_du')::numeric, 1))) end;
      else
        -- prazo_sem_fornecedor: só medida
        return case when p_momento = 'foco_sombra' then
                 format('Peças compradas sem fornecedor dito antes: chegaram em até %s depois da compra (%s compras); conto %s (o padrão é decisão sua).', v_calc, v_n, v_padrao)
               else format('Peças compradas sem fornecedor dito antes: %s; conto %s (padrão).',
                           case when v_7e_n = 0 then 'nenhuma compra medida ainda' else format('%s de %s compras medidas', v_n, v_nmin) end, v_padrao) end;
      end if;
    end;
  end if;
  -- FASE 7e: fim
  -- FASE 7e: (7e P6, §6.2, achado 152) o fornecedor pela compra (fornecedor_prazo; o gravador é _agenda_aprender_fornecedor). detalhe.teria = em sombra, o que as compras dariam (só no foco: a frase de sempre, mais o parêntese; sem nota medida, só o parêntese).
  -- detalhe.fonte = 'compras' = em ligado, a amostra tem compras: a frase não pode falar em "nota" (R7.12-9), e com nota junto diz as duas. As opções e o "fico" não falam da origem: seguem os de baixo.
  if p_item = 'fornecedor_prazo' then
    declare
      v_7e_nome text := coalesce(p_d #>> '{detalhe,nome}', 'O fornecedor');
      v_7e_n    int := coalesce((p_d ->> 'n')::int, 0);
      v_7e_tn   int := (p_d #>> '{detalhe,teria,n}')::int;
      v_7e_nc   int := coalesce((p_d #>> '{detalhe,compras}')::int, 0);
      v_7e_nn   int := coalesce((p_d #>> '{detalhe,notas}')::int, 0);
      v_7e_med  text := public._agenda_plural(v_7e_nc, 'compra', 'compras')
                        || case when v_7e_nn > 0 then ' e ' || public._agenda_plural(v_7e_nn, 'nota', 'notas') else '' end;
      v_7e_te   text;
    begin
      if p_momento like 'foco_%' and p_d #> '{detalhe,teria}' is not null then
        v_7e_te := format('em teste: com as compras registradas %s %s, até %s depois da compra',
                          case when v_7e_tn = 1 then 'seria' else 'seriam' end, public._agenda_plural(v_7e_tn, 'entrega', 'entregas'),
                          public._agenda_aprendizado_valor(p_item, (p_d #>> '{detalhe,teria,du}')::numeric));
        return case when v_7e_n = 0 then format('%s: (%s).', v_7e_nome, v_7e_te)
                    else public._agenda_aprendizado_texto(p_item, p_momento, p_d #- '{detalhe,teria}') || format(' (%s).', v_7e_te) end;
      end if;
      if p_d #>> '{detalhe,fonte}' = 'compras' and p_momento not in ('opcao1', 'opcao2', 'opcao3', 'fico') then
        return case p_momento
          when 'foco_medindo' then case when coalesce((p_d #>> '{detalhe,dono}')::boolean, false)
                 then format('%s: você disse %s; medi %s entregas da compra até a chegada (vale o que você disse).', v_7e_nome, coalesce(v_padrao, 'o prazo'), v_n)
                 else format('%s: %s de %s entregas medidas da compra até a chegada; conto %s (padrão).', v_7e_nome, v_n, v_nmin, coalesce(v_padrao, 'o prazo da classe')) end
          when 'foco_sombra' then format('Em teste: %s entrega em até %s depois da compra (%s medidas); hoje conto %s (padrão).', v_7e_nome, v_calc, v_7e_med, coalesce(v_padrao, 'o prazo da classe'))
          when 'foco_em_uso' then format('%s: entrega em até %s depois da compra (%s medidas): é o que conto desde %s.', v_7e_nome, v_uso, v_7e_med, v_desde)
          when 'foco_pergunta' then format('%s: entrega em até %s depois da compra (%s medidas), e hoje conto %s: a troca espera a sua resposta.', v_7e_nome, v_calc, v_7e_med, coalesce(v_efet, 'o prazo da classe'))
          when 'foco_travado' then format('%s: entrega em até %s depois da compra (%s medidas); fico com %s até %s, como você decidiu.', v_7e_nome, v_calc, v_7e_med, coalesce(v_efet, 'o prazo da classe'), v_trava)
          when 'acao' then format('Medi as compras de %s: da compra até a chegada levam até %s (%s medidas). Passei a contar %s no lugar de %s. *desfaz aprendizado* volta.', v_7e_nome, v_calc, v_7e_med, v_calc, coalesce(v_efet, 'o prazo da classe'))
          when 'pergunta' then format('Medi as compras de %s: da compra até a chegada levam até %s (%s medidas), e hoje eu conto %s. É uma troca grande.', v_7e_nome, v_calc, v_7e_med, coalesce(v_efet, 'o prazo da classe'))
          when 'desfeito' then format('Desfeito: para %s volto a contar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.', v_7e_nome, coalesce(v_volta, v_padrao, 'o prazo da classe'), v_dias)
        end;
      end if;
    end;
  end if;
  -- FASE 7e: fim
  -- CORREÇÃO FASE 6: (C2) texto 5: a pergunta do R$ por diária (a troca grande do valor) diz que a conta inclui as OS em
  -- que o dono também trabalhou (a mão de obra delas entra; as diárias dele não); a opção 1 sai sem o "(recomendo)" (o
  -- gravador não o põe no valor: _agenda_aprendizado_gravar). O resto do valor, como antes (abaixo).
  if p_item = 'mo' and p_momento = 'pergunta' then
    return format('Medi a mão de obra por diária: cada diária rendeu %s (%s OS com diária ligada; inclui as OS em que você também trabalhou), e hoje eu uso %s para estimar os dias pelo valor. É uma troca grande.',
                  v_calc, v_n, v_efet);
  end if;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P2) o R$ por diária (spec-fase6 §6.2 e §6.3): a mão de obra das OS com diária ligada ÷ as diárias ligadas; o
  -- padrão é mo_por_diaria_real, e o valor entra no realista de os_duracao_sugerida ("estimar os dias pelo valor")
  if p_item = 'mo' then
    return case p_momento
      when 'foco_medindo' then format('Valor por diária: %s de %s OS com diária ligada medidas; para estimar os dias pelo valor uso %s (padrão).',
                                      v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor uso %s (padrão).',
                                     v_calc, v_n, v_padrao)
      when 'foco_em_uso' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada): é o que uso para estimar os dias pelo valor desde %s.',
                                     v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada), e hoje uso %s para estimar os dias pelo valor: a troca espera a sua resposta.',
                                       v_calc, v_n, v_efet)
      when 'foco_travado' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor fico com %s até %s, como você decidiu.',
                                      v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Cada diária rendeu %s de mão de obra (%s OS): passei a estimar os dias pelo valor com %s (era %s). *desfaz aprendizado* volta.',
                              v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi a mão de obra por diária: cada diária rendeu %s (%s OS com diária ligada), e hoje eu uso %s para estimar os dias pelo valor. É uma troca grande.',
                                  v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: para estimar os dias pelo valor volto a %s por diária. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  coalesce(v_volta, v_padrao, 'o padrão'), v_dias)
      when 'fico' then format('Combinado: fico com %s por diária. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- (P2) a presença do dono (spec-fase6 §6.2 e §6.3): k = as OS da classe a que ele foi sem estar no plano (detalhe.k) e n
  -- = as OS medidas; 1 = o dia todo, 0 = o abre e fecha (o padrão). Na classe entra sozinha; em todas, sempre pergunta.
  if p_item = 'presenca' and v_nivel is not null then
    declare
      v_foi  text := format('Você foi a %s de %s %s sem estar no plano', coalesce(p_d #>> '{detalhe,k}', '0'), v_n,
                            substr(v_nivel, 4));
      v_onde text := case when p_d ->> 'chave' = 'todas' then 'por padrão' else 'nelas' end;
      v_dia  boolean := coalesce((p_d ->> 'calculado')::numeric, 0) >= 1;
      v_udia boolean := coalesce((p_d ->> 'em_uso')::numeric, 0) >= 1;
      v_edia boolean := coalesce((p_d ->> 'efetivo')::numeric, 0) >= 1;
      v_vdia boolean := coalesce((p_d ->> 'volta')::numeric, 0) >= 1;
    begin
      return case p_momento
        when 'foco_medindo' then format('%s: %s de %s OS medidas para saber se você fica o dia todo; conto com você para abrir e fechar (padrão).',
                                        public._agenda_maiuscula(v_nivel), v_n, v_nmin)
        when 'foco_sombra' then v_foi || case when v_dia then format(': em teste, eu contaria com você o dia todo %s.', v_onde)
                                              else format(': em teste, continuo contando com você só para abrir e fechar %s.', v_onde) end
        when 'foco_em_uso' then v_foi || case when v_udia then format(': conto com você o dia todo %s desde %s.', v_onde, v_desde)
                                              else format(': conto com você só para abrir e fechar %s.', v_onde) end
        when 'foco_pergunta' then v_foi || case when v_dia then ': perguntei se passo a contar com você o dia todo por padrão; espero a sua resposta.'
                                                else ': perguntei se volto a contar com você só para abrir e fechar; espero a sua resposta.' end
        when 'foco_travado' then v_foi || format('; fico com %s até %s, como você decidiu.',
                                                 case when v_edia then 'o dia todo' else 'o abre e fecha' end, v_trava)
        when 'acao' then v_foi || case when v_dia then ': passei a contar com você o dia todo nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao abre e fecha.'
                                       else ': voltei a contar com você só para abrir e fechar nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao dia todo.' end
        when 'pergunta' then v_foi || case when v_dia then '. Quer que eu conte com você o dia todo por padrão, e não só para abrir e fechar?'
                                           else '. Quer que eu volte a contar com você só para abrir e fechar por padrão?' end
        when 'opcao1' then case when v_dia then 'Sim, o dia todo (recomendo pelo medido)' else 'Sim, só abrir e fechar (recomendo pelo medido)' end
        when 'opcao2' then case when v_dia then 'Não, continuo com o abre e fecha' else 'Não, continuo com o dia todo' end
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: n%s volto a contar com você %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nivel, case when v_vdia then 'o dia todo' else 'só para abrir e fechar' end, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.',
                                case when v_edia then 'o dia todo' else 'o abre e fecha' end)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P3) o fornecedor (spec-fase6 §6.2 e §6.3): o atraso das entregas (padrão 0: a chegada no dia que o fornecedor
  -- diz) e o prazo da nota (da saída até a chegada; padrão = o prazo de hoje). O nome é o curto do cadastro (detalhe.nome),
  -- sem artigo; detalhe.no_prazo = as entregas no prazo; detalhe.dono = o prazo é o que o dono disse (só mede).
  if p_item in ('fornecedor_atraso', 'fornecedor_prazo') then
    declare
      v_nome  text := coalesce(p_d #>> '{detalhe,nome}', 'O fornecedor');
      v_np    text := coalesce(p_d #>> '{detalhe,no_prazo}', '0');
      v_dono  boolean := coalesce((p_d #>> '{detalhe,dono}')::boolean, false);
      v_cnum  numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      v_unum  numeric := coalesce((p_d ->> 'em_uso')::numeric, 0);
      v_vnum  numeric := coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0);
      -- "a chegada 2 dias úteis depois do que o fornecedor diz" / "a chegada no dia que o fornecedor diz"
      v_ccheg text := case when v_cnum > 0 then format('a chegada %s depois do que o fornecedor diz', v_calc)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_ucheg text := case when v_unum > 0 then format('a chegada %s depois do que o fornecedor diz', v_uso)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_echeg text := case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0
                           then format('a chegada %s depois do que o fornecedor diz', v_efet)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_vcheg text := case when v_vnum > 0
                           then format('a chegada %s depois do que o fornecedor diz',
                                       public._agenda_aprendizado_valor('fornecedor_atraso', v_vnum))
                           else 'a chegada no dia que o fornecedor diz' end;
    begin
      if p_item = 'fornecedor_atraso' then
        return case p_momento
          when 'foco_medindo' then format('%s: %s de %s entregas medidas.', v_nome, v_n, v_nmin)
          when 'foco_sombra' then format('%s: %s de %s entregas no prazo%s (em teste).', v_nome, v_np, v_n,
                                         case when v_cnum > 0 then '; o atraso chega a ' || v_calc else '' end)
          when 'foco_em_uso' then format('%s: %s de %s entregas no prazo%s: conto %s (desde %s).', v_nome, v_np, v_n,
                                         case when v_unum > 0 then '; o atraso chega a ' || v_uso else '' end, v_ucheg, v_desde)
          when 'foco_pergunta' then format('%s: o atraso chega a %s (%s entregas), e hoje conto %s: a troca espera a sua resposta.',
                                           v_nome, v_calc, v_n, v_echeg)
          when 'foco_travado' then format('%s: o atraso chega a %s (%s entregas); fico com %s até %s, como você decidiu.',
                                          v_nome, v_calc, v_n, v_echeg, v_trava)
          when 'acao' then case when v_cnum > 0
                                then format('%s atrasou até %s em %s entregas: passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_calc, v_n, v_ccheg)
                                else format('%s voltou a entregar no prazo (%s de %s entregas): passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_np, v_n, v_ccheg) end
          when 'pergunta' then case when v_cnum > 0
                                    then format('Medi as entregas de %s: o atraso chega a %s (%s entregas), e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_calc, v_n, v_echeg)
                                    else format('Medi as entregas de %s: %s de %s no prazo, e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_np, v_n, v_echeg) end
          when 'opcao1' then format('Passo a contar %s', v_ccheg)
          when 'opcao2' then format('Fico com %s', v_echeg)
          when 'opcao3' then 'Volto ao padrão'
          when 'desfeito' then format('Desfeito: para %s volto a contar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                      v_nome, v_vcheg, v_dias)
          when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.', v_nome, v_echeg)
        end;
      end if;
      -- o prazo da nota: da saída (despacho) até a chegada
      return case p_momento
        when 'foco_medindo' then case when v_dono
               then format('%s: você disse %s; medi %s notas da saída até a chegada (vale o que você disse).',
                           v_nome, coalesce(v_padrao, 'o prazo'), v_n)
               else format('%s: %s de %s notas medidas da saída até a chegada; conto %s (padrão).',
                           v_nome, v_n, v_nmin, coalesce(v_padrao, 'o prazo da classe')) end
        when 'foco_sombra' then format('Em teste: %s leva até %s da saída da nota até a chegada (%s notas); hoje conto %s (padrão).',
                                       v_nome, v_calc, v_n, coalesce(v_padrao, 'o prazo da classe'))
        when 'foco_em_uso' then format('%s leva até %s da saída da nota até a chegada (%s notas): é o prazo que uso desde %s.',
                                       v_nome, v_uso, v_n, v_desde)
        when 'foco_pergunta' then format('%s leva até %s da saída da nota até a chegada (%s notas), e hoje conto %s: a troca espera a sua resposta.',
                                         v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'foco_travado' then format('%s leva até %s da saída da nota até a chegada (%s notas); fico com %s até %s, como você decidiu.',
                                        v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'), v_trava)
        when 'acao' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas). Passei a contar %s no lugar de %s. *desfaz aprendizado* volta.',
                                v_nome, v_calc, v_n, v_calc, coalesce(v_efet, 'o prazo da classe'))
        when 'pergunta' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas), e hoje eu conto %s. É uma troca grande.',
                                    v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'opcao1' then format('Passo a contar %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o prazo da classe'))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: para %s volto a contar %s da saída da nota até a chegada. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nome, coalesce(v_volta, v_padrao, 'o prazo da classe'), v_dias)
        when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.',
                                v_nome, coalesce(v_efet, 'o prazo da classe'))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P4) a capacidade do dono (spec-fase6 §6.2 e §6.3): quanto dos meios-dias dele marcados no plano ele fez (a
  -- mediana das semanas: detalhe.taxa; "7 de cada 10"), nas últimas detalhe.janela semanas, e a parte da semana dele que o
  -- motor marca (o padrão é carga_max, a de todos). "Seria" no singular só em teste (o spec); "seriam" na pergunta.
  if p_item = 'capacidade_dono' then
    declare
      v_taxa numeric := (p_d #>> '{detalhe,taxa}')::numeric;
      v_dez  text := coalesce(round(v_taxa * 10)::text, '?');
      v_ult  text := case when p_d #>> '{detalhe,janela}' is null then 'Nas últimas semanas'
                          else format('Nas últimas %s semanas', p_d #>> '{detalhe,janela}') end;
      v_sems text := public._agenda_plural(coalesce((p_d ->> 'n')::int, 0), 'semana medida', 'semanas medidas');
    begin
      return case p_momento
        when 'foco_medindo' then format('A sua semana no plano: %s de %s semanas medidas; marco até %s da sua semana (padrão).',
                                        v_n, v_nmin, coalesce(v_padrao, 'a parte de todos'))
        when 'foco_sombra' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seria %s (em teste).',
                                       v_ult, v_dez, v_sems, coalesce(v_padrao, 'a parte de todos'), v_calc)
        when 'foco_em_uso' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s): marco até %s da sua semana desde %s.',
                                       v_ult, v_dez, v_sems, v_uso, v_desde)
        when 'foco_pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seriam %s: a troca espera a sua resposta.',
                                         v_ult, v_dez, v_sems, coalesce(v_efet, v_padrao), v_calc)
        when 'foco_travado' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Pelo medido seriam %s; fico com %s da sua semana até %s, como você decidiu.',
                                        v_ult, v_dez, v_sems, v_calc, coalesce(v_efet, v_padrao), v_trava)
        when 'acao' then format('%s você fez %s de cada 10 meios-dias seus do plano: passei a marcar até %s da sua semana (era %s). *desfaz aprendizado* volta.',
                                v_ult, v_dez, v_calc, coalesce(v_efet, v_padrao))
        when 'pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano. Hoje marco até %s da sua semana; pelo medido seriam %s.',
                                    v_ult, v_dez, coalesce(v_efet, v_padrao), v_calc)
        when 'opcao1' then format('Passo a marcar até %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, v_padrao))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da sua semana. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    coalesce(v_volta, v_padrao, 'a parte de todos'), v_dias)
        when 'fico' then format('Combinado: fico com %s da sua semana. Volto a perguntar se o medido mudar muito.',
                                coalesce(v_efet, v_padrao))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P5) a pontualidade com o cliente (só medida: só a linha do foco) e a folga do aviso de atraso (spec-fase6 §6.2
  -- e §6.3). A pontualidade lê detalhe.no_prazo e detalhe.p80_atraso_du; a folga é a faixa do aviso "com 2 dias úteis a mais"
  -- (0 = a faixa do plano, o padrão)
  if p_item = 'cliente_pontualidade' and p_momento like 'foco_%' then
    if p_momento = 'foco_medindo' then
      return format('Pontualidade: %s de %s OS com a 1ª data dita ao cliente medidas.', v_n, v_nmin);
    end if;
    return format('Pontualidade: %s de %s OS ficaram prontas até o dia dito primeiro ao cliente%s.',
                  coalesce(p_d #>> '{detalhe,no_prazo}', '0'), v_n,
                  case when coalesce((p_d #>> '{detalhe,p80_atraso_du}')::numeric, 0) > 0
                       then '; o atraso chega a ' || public._agenda_aprendizado_valor('aviso_folga', (p_d #>> '{detalhe,p80_atraso_du}')::numeric)
                       else '' end);
  end if;
  if p_item = 'aviso_folga' then
    declare
      v_cn numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      -- "a faixa com 2 dias úteis a mais" / "a faixa do plano", de cada valor
      v_fc text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0 then format('a faixa com %s a mais', v_calc)
                        else 'a faixa do plano' end;
      v_fu text := case when coalesce((p_d ->> 'em_uso')::numeric, 0) > 0 then format('a faixa com %s a mais', v_uso)
                        else 'a faixa do plano' end;
      v_fe text := case when coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_fv text := case when coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_terminou text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0
                              then format('o serviço terminou até %s depois do fim que eu disse', v_calc)
                              else 'o serviço terminou dentro da faixa que eu disse' end;
    begin
      return case p_momento
        when 'foco_medindo' then format('Avisos de atraso: %s de %s avisos medidos; dou %s (padrão).', v_n, v_nmin, v_fe)
        when 'foco_sombra' then format('Avisos de atraso: em %s, %s (em teste: eu daria %s).', v_n, v_terminou, v_fc)
        when 'foco_em_uso' then format('Avisos de atraso: em %s, %s: dou %s desde %s.', v_n, v_terminou, v_fu, v_desde)
        when 'foco_pergunta' then format('Avisos de atraso: em %s, %s, e hoje dou %s: a troca espera a sua resposta.',
                                         v_n, v_terminou, v_fe)
        when 'foco_travado' then format('Avisos de atraso: em %s, %s; fico com %s até %s, como você decidiu.',
                                        v_n, v_terminou, v_fe, v_trava)
        when 'acao' then format('Os avisos de atraso erraram para %s (%s avisos): passei a dar %s%s. *desfaz aprendizado* volta.',
                                case when v_cn > coalesce((p_d ->> 'efetivo')::numeric, 0) then 'menos' else 'mais' end,
                                v_n, v_fc,
                                case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0 then format(' (era %s)', v_fe) else '' end)
        when 'pergunta' then format('Medi os avisos de atraso: em %s, %s, e hoje eu dou %s. É uma troca grande.', v_n, v_terminou, v_fe)
        when 'opcao1' then format('Passo a dar %s', v_fc)
        when 'opcao2' then format('Fico com %s', v_fe)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a dar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_fv, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_fe)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P6) a carga de cada pessoa pelo plano cumprido (a revisão) e os gatilhos de um planejador mais forte (spec-fase6
  -- §6.2 e §6.3). A carga lê detalhe.mostrar (o plano cumprido das semanas que o texto diz, da mais antiga para a mais nova),
  -- detalhe.gatilho (baixo, alto ou nulo), detalhe.meta, detalhe.ppc_baixo e detalhe.ppc_alto; o planejador lê os números
  -- da semana (os_ativas, pessoas, valem, n_valem, total, limites), as semanas seguidas e a resposta da pergunta (uma vez só)
  if p_item = 'carga' then
    declare
      v_pcts  text[] := array(select public._agenda_aprendizado_valor('carga', x::numeric)
                                from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb))
                                     with ordinality t(x, o)
                               order by o);
      v_k     int := cardinality(array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb)) x));
      v_gat   text := p_d #>> '{detalhe,gatilho}';
      v_meta  text := public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,meta}')::numeric);
      v_hoje  text := coalesce(v_efet, v_padrao);
      v_cumpr text;
    begin
      v_cumpr := case when v_k = 0 then 'O plano cumprido ainda não foi medido'
                      when v_k = 1 then format('O plano foi cumprido em %s na última semana (meta %s)', v_pcts[1], v_meta)
                      else format('O plano foi cumprido em %s nas últimas %s semanas (meta %s)', public._agenda_lista(v_pcts, null),
                                  v_k, v_meta) end;
      return case p_momento
        when 'foco_medindo' then format('O plano cumprido: %s de %s semanas medidas; marco até %s da semana de cada pessoa.',
                                        v_n, v_nmin, v_padrao)
        when 'foco_sombra' then v_cumpr || '.'
                                || case when (p_d ->> 'calculado')::numeric is distinct from (p_d ->> 'padrao')::numeric
                                        then format(' Em teste: eu perguntaria se passo a marcar até %s da semana de cada pessoa (hoje %s).',
                                                    v_calc, v_padrao)
                                        else '' end
        when 'foco_em_uso' then format('%s; marco até %s da semana de cada pessoa.', v_cumpr, v_uso)
        when 'foco_pergunta' then format('%s: perguntei se passo a marcar até %s da semana de cada pessoa (hoje %s); espera a sua resposta.',
                                         v_cumpr, v_calc, v_hoje)
        when 'foco_travado' then format('%s; fico com %s até %s, como você decidiu.', v_cumpr, v_hoje, v_trava)
        when 'acao' then format('Passei a marcar até %s da semana de cada pessoa (era %s), como você decidiu. *desfaz aprendizado* volta.',
                                v_calc, v_hoje)
        when 'pergunta' then case v_gat
          when 'alto' then format('O plano foi cumprido acima de %s em %s semanas seguidas: posso estar marcando pouco.',
                                  public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_alto}')::numeric), v_k)
          else format('O plano foi cumprido abaixo de %s em %s semanas seguidas (%s). Recomendo marcar até %s da semana de cada pessoa (hoje %s).',
                      public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_baixo}')::numeric), v_k,
                      array_to_string(v_pcts, ', '), v_calc, v_hoje) end
        when 'opcao1' then format('Passo para %s', v_calc)
        when 'opcao2' then format('Fico com %s', v_hoje)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da semana de cada pessoa. Não pergunto de novo por %s dias, salvo se o plano cumprido mudar.',
                                    coalesce(v_volta, v_padrao), v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar em %s dias se o plano cumprido continuar assim.', v_hoje, v_dias)
      end;
    end;
  end if;
  if p_item = 'solver' then
    declare
      v_valem text[] := array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,valem}', '[]'::jsonb)) x);
      v_base  text := format('Gatilhos de um planejador mais forte: %s de %s (%s OS ativas, %s pessoas)',
                             coalesce(p_d #>> '{detalhe,n_valem}', '0'), coalesce(p_d #>> '{detalhe,total}', '0'),
                             coalesce(p_d #>> '{detalhe,os_ativas}', '0'), coalesce(p_d #>> '{detalhe,pessoas}', '0'));
      v_resp  text := p_d #>> '{detalhe,resposta}';
      v_ja    boolean := coalesce((p_d #>> '{detalhe,perguntado}')::boolean, false);
      v_lista text;
    begin
      v_lista := public._agenda_lista(array(
        select 'de ' || case g
                 when 'os_ativas' then format('%s OS ativas', p_d #>> '{detalhe,limites,os_ativas}')
                 when 'pessoas' then format('%s pessoas', p_d #>> '{detalhe,limites,pessoas}')
                 when 'curtas_dia' then format('%s idas curtas suas por dia útil',
                                               public._agenda_num((p_d #>> '{detalhe,limites,curtas_dia}')::numeric, 1))
                 when 'descarte' then format('%s%% dos planos que eu sugeri descartados',
                                             round(100 * (p_d #>> '{detalhe,limites,descarte}')::numeric))
               end
          from unnest(v_valem) with ordinality u(g, o) order by o), null);
      return case p_momento
        when 'foco_medindo' then format('%s; medi %s de %s semanas.', v_base, v_n, v_nmin)
        when 'foco_sombra' then v_base || '.'
                                || case when (p_d ->> 'calculado')::numeric >= 1
                                        then ' Em teste: eu avisaria que vale estudar um planejador mais forte.' else '' end
        when 'foco_pergunta' then v_base || '. Perguntei se vale estudar um planejador mais forte; espera a sua resposta.'
        when 'foco_em_uso' then v_base || case when v_resp = '1' then '. Você quis ver isso; nada muda sozinho.'
                                               when v_resp = '2' then '. Você disse "agora não"; não pergunto de novo.'
                                               when v_ja then '. Já perguntei uma vez; não pergunto de novo.'
                                               else '.' end
        when 'foco_travado' then v_base || '. Você disse "agora não"; não pergunto de novo.'
        when 'pergunta' then format('Há %s semanas a agenda passa %s: vale estudar um planejador mais forte. Nada muda sozinho.',
                                    coalesce(p_d #>> '{detalhe,semanas_seguidas}', v_n), v_lista)
        when 'opcao1' then 'Quero ver isso'
        when 'opcao2' then 'Agora não'
        when 'opcao3' then 'Volto ao padrão'
        when 'acao' then 'Combinado: anotei que você quer ver um planejador mais forte. Nada muda sozinho na agenda.'
        when 'fico' then 'Combinado: agora não. Não pergunto de novo.'
        when 'desfeito' then 'Desfeito: volto a só medir os gatilhos de um planejador mais forte.'
      end;
    end;
  end if;
  -- FASE 6: fim
  -- O fator de campo (spec-fase6 §6.2 e §6.3).
  -- CORREÇÃO FASE 6: (C2) texto 1: a linha do fator no cartão e no foco diz para que o fator serve — o limiar do "o que
  -- falta?"; os dias do plano continuam os que o dono disse (a linha fica logo abaixo de "4 dias (você disse)" e fazia crer
  -- que o plano usa 1,7 × 4) —; com o valor em uso igual ao padrão, que é o mesmo de sempre (e não "desde sex 30/10"); em
  -- teste, com o medido igual ao padrão, sem o "hoje seria 1,5×, e vale 1,5×". Os outros momentos, como antes (abaixo).
  if p_item = 'fator' and v_nivel is not null and p_momento = 'foco_em_uso' then
    if (p_d ->> 'em_uso')::numeric is not distinct from (p_d ->> 'padrao')::numeric then
      return format('%s levam até %s o combinado (%s OS): é o mesmo que eu já usava.',
                    public._agenda_maiuscula(v_nivel), v_uso, v_n);
    end if;
    return format('%s levam até %s o combinado (%s OS): uso %s desde %s para perguntar o que falta (os dias do plano continuam os que você disse).',
                  public._agenda_maiuscula(v_nivel), v_uso, v_n, v_uso, v_desde);
  end if;
  if p_item = 'fator' and v_nivel is not null and p_momento = 'foco_sombra'
     and (p_d ->> 'calculado')::numeric is not distinct from (p_d ->> 'padrao')::numeric then
    return format('Em teste: %s levam até %s o combinado (%s OS): é o mesmo que eu já uso.', v_nivel, v_calc, v_n);
  end if;
  -- CORREÇÃO FASE 6: fim
  if p_item = 'fator' and v_nivel is not null then
    return case p_momento
      when 'foco_medindo' then format('%s: %s de %s OS medidas; para perguntar o que falta, uso %s o combinado (padrão).',
                                      public._agenda_maiuscula(v_nivel), v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: %s levam até %s o combinado (%s OS); hoje seria %s, e vale %s (padrão).',
                                     v_nivel, v_calc, v_n, v_calc, v_padrao)
      when 'foco_em_uso' then format('%s levam até %s o combinado (%s OS): é o que uso desde %s.',
                                     public._agenda_maiuscula(v_nivel), v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('%s levam até %s o combinado (%s OS), e hoje uso %s: a troca espera a sua resposta.',
                                       public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet)
      when 'foco_travado' then format('%s levam até %s o combinado (%s OS); fico com %s até %s, como você decidiu.',
                                      public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Aprendi com as OS concluídas: %s levam até %s o combinado (%s OS). Passei a usar %s no lugar de %s para perguntar o que falta. *desfaz aprendizado* volta.',
                              v_nivel, v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi %s: levam até %s o combinado (%s OS), e hoje eu uso %s. É uma troca grande.',
                                  v_nivel, v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: %s voltam a %s para perguntar o que falta. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  v_nivel, v_volta, v_dias)
      when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- Os outros itens: um texto provisório, sem jargão; o pacote de cada item (P2 a P6) recria esta função com o texto da §6.
  v_rotulo := case p_item
    when 'mo' then 'O valor de mão de obra por diária'
    when 'presenca' then 'A sua presença nas OS'
    when 'fornecedor_atraso' then 'O atraso do fornecedor'
    when 'fornecedor_prazo' then 'O prazo do fornecedor'
    when 'capacidade_dono' then 'A parte da sua semana no plano'
    when 'cliente_pontualidade' then 'A pontualidade com o cliente'
    when 'aviso_folga' then 'A folga do aviso de atraso'
    when 'carga' then 'A parte da semana de cada pessoa no plano'
    when 'solver' then 'Os sinais de um planejador mais forte'
    else 'O que eu medi' end;
  return case p_momento
    when 'foco_medindo' then format('%s: %s de %s medidas; vale %s (padrão).', v_rotulo, v_n, v_nmin, coalesce(v_padrao, 'o de hoje'))
    when 'foco_sombra' then format('Em teste: %s medido é %s (%s medidas); vale %s (padrão).',
                                   lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_padrao, 'o de hoje'))
    when 'foco_em_uso' then format('%s: uso %s, pelo medido (%s medidas), desde %s.', v_rotulo, v_uso, v_n, v_desde)
    when 'foco_pergunta' then format('%s: o medido é %s (%s medidas), e hoje uso %s: a troca espera a sua resposta.',
                                     v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'foco_travado' then format('%s: o medido é %s (%s medidas); fico com %s até %s, como você decidiu.',
                                    v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'), v_trava)
    when 'acao' then format('Aprendi com o que aconteceu: %s passou a %s (era %s; %s medidas). *desfaz aprendizado* volta.',
                            lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, coalesce(v_efet, 'o padrão'), v_n)
    when 'pergunta' then format('Medi %s: %s (%s medidas), e hoje uso %s. É uma troca grande.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'opcao1' then format('Passo a usar %s', v_calc)
    when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o de agora'))
    when 'opcao3' then 'Volto ao padrão'
    when 'desfeito' then format('Desfeito: %s volta a %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), coalesce(v_volta, 'o padrão'), v_dias)
    when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', coalesce(v_efet, 'o padrão'))
  end;
end;
$function$;

comment on function public._agenda_aprendizado_texto(text, text, jsonb) is
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe). FASE 6 (P4): a capacidade do dono (capacidade_dono) tem os textos da spec §6.2/§6.3 ("Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano …"; a taxa e a janela vêm do detalhe). FASE 6 (P5): a pontualidade com o cliente (cliente_pontualidade: só a linha do foco, "Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.") e a folga do aviso de atraso (aviso_folga: "a faixa com 2 dias úteis a mais"; 0 = a faixa do plano) têm os textos da spec §6.2/§6.3. FASE 6 (P6): a carga de cada pessoa pelo plano cumprido ("O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%)."; a pergunta "abaixo de 60% em 3 semanas seguidas (…). Recomendo marcar até 70% …") e os gatilhos de um planejador mais forte ("Gatilhos de um planejador mais forte: 0 de 4 (9 OS ativas, 4 pessoas)."; a pergunta "Há 4 semanas a agenda passa de 25 OS ativas e de 6 pessoas: …") têm os textos da spec §6.2/§6.3. Todos os itens com o texto da spec. CORREÇÃO FASE 6 (C2, textos 1 e 5): o fator em uso diz "uso 1,7× desde … para perguntar o que falta (os dias do plano continuam os que você disse)", e "é o mesmo que eu já usava" com o valor do padrão; em teste, com o medido igual ao padrão, sem o "hoje seria X, e vale X"; a pergunta do R$ por diária diz que inclui as OS em que o dono também trabalhou. FASE 7e (P2): os textos da spec §6.2/§6.3 (com R7.3) para os 6 itens da margem. Nunca perguntam. O desfeito usa volta (um passo só) e diz que a OS marcada guarda o valor. FASE 7e (P4): folga_semana com calculado nulo: medindo com as semanas já bastando diz o que falta (as OS medidas ou a variação delas); em uso, travado e a ação dizem que ficou sem medida e que volta ao padrão aos poucos. FASE 7e (P6, §6.2, achado 152): fornecedor_prazo pela compra (detalhe.fonte = compras: a frase diz "depois da compra" e nunca "nota" sozinha) e, em sombra, o parêntese do detalhe.teria no foco.';

-- _agenda_prazo_do_fornecedor (de 20261029100300_agenda_fase6_fornecedor.sql:457; md5 do corpo de antes 82e9ff9a043dc182586acd751ee2a9a9)
create or replace function public._agenda_prazo_do_fornecedor(p_fornecedor uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c          public.agenda_config := public._agenda_cfg();
  s          public.suppliers%rowtype;
  v_vazio    constant jsonb := jsonb_build_object('classe', null, 'du', null, 'corridos', null, 'fonte', null,
                                                  'duvida', null, 'principal_id', null, 'texto', null);
  v_nome_g   text;
  v_grupo    jsonb := '[]'::jsonb;
  v_ativo    boolean;
  v_n        int := 0;
  v_classes  int := 0;
  v_um       uuid;
  v_princ    uuid;
  v_top      record;
  v_empate   int;
  v_duvida   text;
  v_classe   text;
  v_fonte    text;
  v_du       int;
  v_corr     int;
  -- FASE 6: o prazo medido do fornecedor (fornecedor_prazo em uso)
  v_med      numeric;
  -- FASE 6: fim
  -- FASE 7e: (7e P6, R7.12-9) de onde veio o número em uso (o detalhe de fornecedor_prazo)
  v_7e_det   jsonb;
  -- FASE 7e: fim
begin
  if p_fornecedor is null then
    return v_vazio;
  end if;
  select * into s from public.suppliers where id = p_fornecedor;
  if not found then
    return v_vazio;
  end if;
  v_ativo := coalesce(s.active, true);

  if s.modalidade is not null then
    v_classe := s.modalidade;
    v_fonte := 'dono';
  else
    v_nome_g := public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name));
    if v_nome_g <> '' then
      -- O grupo: este cadastro e os outros ATIVOS com o mesmo nome, com a classe que as regras 4–5 dariam a cada um, se
      -- tem CNPJ de 14 dígitos e o peso (produtos + contas a pagar).
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', o.id, 'ativo', coalesce(o.active, true), 'eu', o.id = s.id,
               'classe', coalesce(public._agenda_classe_pelo_nome(concat_ws(' ', o.name, o.trade_name, o.display_name)),
                                  public._agenda_classe_por_lugar(o.city, o.state)),
               'cnpj14', length(regexp_replace(coalesce(o.cnpj_cpf, ''), '\D', '', 'g')) = 14,
               'peso', (select count(*) from public.products pr where pr.supplier_id = o.id)
                       + (select count(*) from public.payables pa where pa.supplier_id = o.id))
               order by o.id), '[]'::jsonb)
        into v_grupo
        from public.suppliers o
       where (o.id = s.id or coalesce(o.active, true))
         and public._agenda_nome_de_grupo(coalesce(nullif(btrim(o.trade_name), ''), o.name)) = v_nome_g;
      select count(*), min(e ->> 'id')
        into v_n, v_um
        from jsonb_array_elements(v_grupo) e
       where not (e ->> 'eu')::boolean;
    end if;

    if v_n > 0 then
      -- Os candidatos a principal: os ativos do grupo (o próprio só quando também está ativo).
      select (e ->> 'cnpj14')::boolean as cnpj14, (e ->> 'peso')::bigint as peso, (e ->> 'id')::uuid as id into v_top
        from jsonb_array_elements(v_grupo) e
       where (e ->> 'ativo')::boolean
       order by (e ->> 'cnpj14')::boolean desc, (e ->> 'peso')::bigint desc, e ->> 'id'
       limit 1;
      select count(*) into v_empate
        from jsonb_array_elements(v_grupo) e
       where (e ->> 'ativo')::boolean and (e ->> 'cnpj14')::boolean = v_top.cnpj14 and (e ->> 'peso')::bigint = v_top.peso;
      v_princ := case when v_empate = 1 then v_top.id end;

      if not v_ativo then
        -- O cadastro que o dono já tirou de uso vale como o que ficou: o único ativo, ou o principal dos ativos.
        v_um := case when v_n = 1 then v_um else v_princ end;
        if v_um is not null then
          return public._agenda_prazo_do_fornecedor(v_um) || jsonb_build_object('principal_id', v_um);
        end if;
        return v_vazio || jsonb_build_object('duvida', 'duplicado');
      end if;

      select count(distinct coalesce(e ->> 'classe', '-')) into v_classes
        from jsonb_array_elements(v_grupo) e
       where (e ->> 'ativo')::boolean;
      if v_classes > 1 then
        if v_princ is distinct from s.id then
          return v_vazio || jsonb_build_object('duvida', 'duplicado', 'principal_id', v_princ);
        end if;
        v_duvida := 'duplicado';
      else
        v_princ := null;
      end if;
    end if;

    v_classe := public._agenda_classe_pelo_nome(concat_ws(' ', s.name, s.trade_name, s.display_name));
    if v_classe is not null then
      v_fonte := 'nome';
    else
      v_classe := public._agenda_classe_por_lugar(s.city, s.state);
      v_fonte := case when v_classe is not null then 'cidade' end;
    end if;
  end if;

  if v_classe is null then
    return v_vazio || jsonb_build_object('duvida', coalesce(v_duvida, 'sem_lugar'), 'principal_id', v_princ);
  end if;
  if v_classe = 'importacao' then
    v_corr := case when v_fonte = 'dono' then coalesce(s.prazo_dias_corridos, c.importacao_dias) else c.importacao_dias end;
  else
    v_du := case when v_fonte = 'dono' then coalesce(s.prazo_dias_uteis, (c.prazo_classe_du ->> v_classe)::int)
                 else (c.prazo_classe_du ->> v_classe)::int end;
  end if;
  -- FASE 6: (P3) o prazo medido (spec-fase6 §5.3), logo depois do que o dono disse: o de fornecedor_prazo em uso (as notas
  -- que chegaram, da saída até a chegada; _agenda_aprendido: só com modo_aprendizado ligado e fornecedor na lista). A
  -- classe fica; o importado (dias corridos) não muda; du_classe = o prazo de antes (o padrão com que a rodada compara)
  if v_fonte <> 'dono' and v_classe <> 'importacao' then
    v_med := public._agenda_aprendido('fornecedor_prazo', p_fornecedor::text);
    if v_med is not null then
      -- (7e P6, R7.12-9; marca curta porque este bloco fica dentro de um bloco da Fase 6) com compra medida (detalhe.fonte = compras, só em ligado de verdade), a frase diz o que foi medido: o n da linha soma compras e notas, e "(medido em 5 notas)" sem nota nenhuma é afirmação falsa.
      -- Fica a substring "(medido em ": _agenda_gestor_compra_conta classifica por ela. Sem compra medida, o retorno de baixo, byte a byte. Só neste ramo (fornecedor_prazo em uso), 1 leitura pela chave da linha.
      select a.detalhe into v_7e_det from public.agenda_aprendizado a where a.item = 'fornecedor_prazo' and a.chave = p_fornecedor::text;
      if v_7e_det ->> 'fonte' = 'compras' then
        return jsonb_build_object('classe', v_classe, 'du', v_med::int, 'corridos', v_corr, 'fonte', 'medido', 'duvida', v_duvida,
          'principal_id', v_princ, 'du_classe', v_du,
          'texto', public._agenda_classe_texto(v_classe, v_med::int, v_corr)
                   || format(' (medido em %s)', public._agenda_plural((v_7e_det ->> 'compras')::int, 'compra', 'compras')
                                                || case when (v_7e_det ->> 'notas')::int > 0 then ' e ' || public._agenda_plural((v_7e_det ->> 'notas')::int, 'nota', 'notas') else '' end));
      end if;
      -- (7e: fim)
      return jsonb_build_object('classe', v_classe, 'du', v_med::int, 'corridos', v_corr, 'fonte', 'medido', 'duvida', v_duvida,
        'principal_id', v_princ, 'du_classe', v_du,
        'texto', public._agenda_classe_texto(v_classe, v_med::int, v_corr)
                 || format(' (medido em %s notas)', (select a.n from public.agenda_aprendizado a
                                                      where a.item = 'fornecedor_prazo' and a.chave = p_fornecedor::text)));
    end if;
  end if;
  -- FASE 6: fim
  return jsonb_build_object('classe', v_classe, 'du', v_du, 'corridos', v_corr, 'fonte', v_fonte, 'duvida', v_duvida,
    'principal_id', v_princ,
    'texto', public._agenda_classe_texto(v_classe, v_du, v_corr)
             || case v_fonte when 'dono' then ' (você disse)' when 'cidade' then ' (pela cidade, chute meu)'
                             else ' (pelo nome)' end);
end;
$function$;

comment on function public._agenda_prazo_do_fornecedor(uuid) is
  'Agenda de Produção (Fase 4): o prazo do fornecedor numa fonte só, {classe, du, corridos, fonte, duvida, principal_id, texto}. A 1ª regra que valer: o que o dono disse (suppliers.modalidade, fonte dono) → cadastro repetido (outro ativo com o mesmo nome de grupo: o inativo vale como o ativo que ficou; dois ativos de classe diferente = só o principal, CNPJ de 14 dígitos e mais produtos + contas, tem classe, os dois com duvida duplicado) → pelo nome (marketplace, importado; fonte nome) → pela cidade/UF tolerante ao caractere quebrado (fonte cidade) → nada (duvida sem_lugar). Os dias: os do dono, senão os da classe (agenda_config.prazo_classe_du); importado em dias corridos (agenda_config.importacao_dias). texto: "entrega local, 1 dia útil (pela cidade, chute meu)". FASE 6 (P3): logo depois do que o dono disse, a fonte medido — com fornecedor_prazo em uso (_agenda_aprendido: modo_aprendizado ligado e fornecedor na lista), du = o medido das notas que chegaram (da saída até a chegada), fonte medido, texto "outro estado, 6 dias úteis (medido em 5 notas)" e du_classe = o prazo de antes; o importado não muda. FASE 7e (P6, R7.12-9): com fornecedor_prazo em uso medido por compra (detalhe.fonte = compras), o texto diz o que foi medido: "(medido em 5 compras)" ou "(medido em 3 compras e 2 notas)". Sem compra medida, o de antes.';

-- _agenda_ver_fornecedores (de 20261029100950_agenda_fase6_correcao_textos.sql:3032; md5 do corpo de antes e71ba407c805508d2914f6a173f0b572)
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
  -- FASE 6: (P8) o prazo medido em uso (fonte medido)
  v_medido  text[];
  -- FASE 6: fim
  -- FASE 7e: (7e P6, R7.12-9) o título do bloco "Medido" quando há compra medida (nulo = o de antes)
  v_7e_cab  text;
  -- FASE 7e: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_fornecedores: sem o dia de hoje' using errcode = '22004';
  end if;
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

  -- FASE 6: (P8) o prazo medido (spec-fase6 §5.3; o risco do P3): com fornecedor_prazo em uso (_agenda_prazo_do_fornecedor,
  -- fonte medido: só com o aprendizado ligado e fornecedor na lista), o fornecedor saía de "Você disse" e de "Meu chute" e
  -- sumia do foco. Agora vai a "Medido (pelas notas que chegaram):", com o texto do prazo ("outro estado, 6 dias úteis
  -- (medido em 5 notas)").
  select array_agg(t.l order by t.o, t.l) into v_medido
    from (select '• ' || concat(f.nome, ' (' || f.lugar || ')') || ': ' || f.texto || '.' as l,
                 array_position(c_ordem, f.classe) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, classe text, fonte text, texto text)
           where f.fonte = 'medido') t;
  -- FASE 6: fim
  -- FASE 7e: (7e P6, R7.12-9) o título diz de onde veio o que está no bloco: só com fornecedor em uso por compra muda ("pelas compras"; "pelas compras e notas" se algum também tem nota, ou se outro é só de nota). Sem compra, nulo, e a linha de antes, byte a byte.
  select case when bool_or(a.detalhe ->> 'fonte' = 'compras')
              then format('Medido (pelas %s que chegaram):',
                          case when bool_or(a.detalhe ->> 'fonte' is distinct from 'compras' or (a.detalhe ->> 'notas')::int > 0) then 'compras e notas' else 'compras' end) end
    into v_7e_cab
    from jsonb_to_recordset(v_lista) f(fornecedor_id uuid, fonte text)
    join public.agenda_aprendizado a on a.item = 'fornecedor_prazo' and a.chave = f.fornecedor_id::text
   where f.fonte = 'medido';
  -- FASE 7e: fim
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
                -- FASE 6: (P8) o prazo medido, logo depois do que o dono disse (só aparece com fornecedor_prazo em uso)
                || case when coalesce(cardinality(v_medido), 0) > 0 then array['Medido (pelas notas que chegaram):'] || v_medido
                        else '{}'::text[] end
                -- FASE 6: fim
                || case when v_n > 0 then array['Meu chute (pela cidade ou pelo nome):'] || v_chute[1:k]
                                          || case when k < v_n then array[format('• e mais %s', v_n - k)] else '{}'::text[] end
                        else '{}'::text[] end
                || case when cardinality(v_falta) > 0 then array['Falta você dizer:'] || v_falta else '{}'::text[] end
                || array[v_pe];
    -- FASE 7e: (7e P6, R7.12-9) dentro do laço, para o teto de texto contar com o título que vai sair
    if v_7e_cab is not null then
      v_linhas := array_replace(v_linhas, 'Medido (pelas notas que chegaram):', v_7e_cab);
    end if;
    -- FASE 7e: fim
    v_t := public._agenda_juntar(v_linhas, null);
    exit when char_length(v_t) <= c.texto_max;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
    'dados', jsonb_build_object('fornecedores', v_lista, 'disse', coalesce(cardinality(v_disse), 0), 'chute', v_n,
                                'falta', cardinality(v_falta)));
end;
$function$;

comment on function public._agenda_ver_fornecedores(date) is
  'Agenda de Produção (Fase 4, P6): agenda_ver foco fornecedores — como a agenda conta a chegada do material dos fornecedores principais (_agenda_fornecedores_principais) e dos das linhas da carteira ainda não na mão, pela fonte única (_agenda_prazo_do_fornecedor): "Você disse:" (suppliers.modalidade; vazio: "Você disse: nenhum ainda."), "Meu chute (pela cidade ou pelo nome):" uma linha por prazo ("• entrega local, 1 dia útil: Premel (Itajaí/SC) e Souper (Itajaí/SC)"), "Falta você dizer:" (sem cidade no cadastro; cadastro repetido: "• Kamell: cadastrada 2 vezes (Vila Velha/ES e Itajaí/SC); conto pela de Vila Velha/ES. É a mesma?") e "Pode ser um áudio só: …" com dois nomes da lista. O inativo vale como o que ficou. Até texto_max (o chute sai do fim com "• e mais N"). Definer (lê os principais, que são só do service_role): com login, só administrador e financeiro (senão 42501). {ok, texto, dados:{fornecedores, disse, chute, falta}}. FASE 6 (P8): o fornecedor com o prazo medido em uso (fonte medido de _agenda_prazo_do_fornecedor) vai ao grupo "Medido (pelas notas que chegaram):" ("• Kamell (Vila Velha/ES): outro estado, 6 dias úteis (medido em 5 notas)."), logo depois de "Você disse"; antes ele sumia do foco. Sem o medido em uso, o texto é o de antes. CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501. FASE 7e (P6, R7.12-9): com algum fornecedor em uso por compra, o título do bloco é "Medido (pelas compras que chegaram):" ou "Medido (pelas compras e notas que chegaram):". Sem compra medida, o de antes.';

-- ── 3. Portas ─────────────────────────────────────────────────────────────────────────────────────
-- Os 3 passos da rodada sem grant nenhum (o P7 os chama de agenda_aprender, definer; o molde é _agenda_aprender_fornecedor). As recriadas não mudam de porta.
revoke all on function public._agenda_aprender_tempo_compra(date, timestamptz), public._agenda_aprender_folga_compra(date, timestamptz),
                       public._agenda_aprender_prazo_sem_fornecedor(date, timestamptz) from public, anon, authenticated, service_role;
