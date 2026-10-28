-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P3: o fornecedor — o atraso medido das entregas, o prazo medido da
-- nota (da saída até a chegada) e a data provável do material na prontidão (só no nível B).
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§3.1, §3.2, §5.3, §5.9, §6.2, §6.3). Depende de 20261029100200.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (2 funções novas; 5 recriadas; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f6p3/montar-migration.mjs (as partes escritas à mão
-- f6p3/parte-0-cabeca.sql, parte-1-novas.sql e parte-9-portas.sql + as 5 recriadas, cada uma com o corpo da definição MAIS NOVA,
-- conferida com grep a cada montagem: fora dos blocos "-- FASE 6:" nenhuma linha muda). Edite o montador, nunca este .sql.
--
-- POR QUE: a agenda conta a chegada do material pelo que o fornecedor diz (a OC, a nota, a mensagem) e pelo prazo da classe
-- (a cidade, o nome). Quem atrasa sempre atrasa de novo, e o início da OS sai otimista. Este pacote mede cada fornecedor e,
-- com o item ligado, conta a chegada mais tarde: a data provável. O que o fornecedor disse continua sendo o fato (a
-- "chegou?" é no dia dele), e ninguém recebe mensagem nova. Nada muda com o modo de aprendizado fora de ligado ou sem
-- "fornecedor" em aprendizado_ligados: o leitor único (_agenda_aprendido) devolve nulo e vale o de hoje, byte a byte.
--
-- O QUE MUDA:
--   1. _agenda_aprender_fornecedor(hoje, agora): (a) fornecedor_atraso por fornecedor — as entregas da janela (as linhas de
--      os_material na mão com a 1ª previsão de fornecedor/OC/nota/Pix, agrupadas por fornecedor e nota, senão OC, senão
--      linha: 3 linhas da mesma nota = 1 entrega; o fornecedor = o da linha, senão o da OC, senão o da nota), o atraso de cada
--      uma = o maior agenda_du_entre(previsao_original, chegou_em) das linhas (assinado), calculado = o P80
--      (fornecedor_percentil) para cima e nunca abaixo de 0, padrão 0; (b) fornecedor_prazo por fornecedor — as notas que
--      chegaram (material_remessas: agenda_du_entre(despacho_em, chegou_em)), padrão = o prazo de hoje. Pelo gravador, nível
--      fornecedor, chave = o id do fornecedor. _agenda_atraso_do_fornecedor(fornecedor): {du, n, no_prazo, em_uso, texto}.
--   2. Recriadas (o corpo da definição mais nova + blocos "-- FASE 6:"):
--      · _agenda_prazo_do_fornecedor (de 20261027100100): depois do que o dono disse, a fonte medido (fornecedor_prazo em
--        uso): du = o medido, texto "outro estado, 6 dias úteis (medido em 5 notas)", du_classe = o de antes. O importado (dias
--        corridos) não muda;
--      · os_prontidao (de 20261027100200): no item de nível B, enquanto o dia dito não chegou e com o atraso do fornecedor em
--        uso, data = o dia dito + o atraso (a data provável: o DPM, o início pelo material e o motor), data_dita = o dia dito,
--        data_texto "a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11". atrasado e sem_data
--        continuam pelo dia dito; C, A, D e E não mudam;
--      · _agenda_compras_da_os (de 20261027100600): o item com a data provável usa o data_texto da prontidão (nunca "chega
--        <data provável> (pela nota …)", que poria a conta da agenda como palavra do fornecedor);
--      · _agenda_ver_compras (de 20261027100600): sem OS e com o aprendizado fora de desligado, as linhas do que a agenda mediu
--        de cada fornecedor ("Kamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis (em teste)." / "Correa: 4 de 5
--        entregas medidas."), na cauda, peso 1 (saem primeiro, com o detector);
--      · _agenda_aprendizado_texto (de 20261029100200): os textos do atraso e do prazo do fornecedor (spec §6.2/§6.3) antes do
--        fator (o mo e a presença do P2 ficam como estão).
--
-- QUEM LÊ O "data" DOS ITENS (conferido com grep em supabase/migrations, supabase/functions e src; a lista e o porquê de cada
-- um estão em supabase/tests/agenda_fase6_fornecedor.sql, F3):
--   · a própria os_prontidao (o DPM, o gargalo, o início pelo material, o texto "se X chegar …") e o motor por ela, o
--     _agenda_aviso_do_material ("só chega por volta de …"), agenda_ctp ("chegam por volta de …") e _agenda_cliente_risco (a
--     faixa da peça): É a data provável, de propósito — o risco do início;
--   · a "chegou?" (_agenda_vigia_chegou e a limpeza, de 20261027100400), a restrição "a previsão venceu em …: chegou?",
--     _agenda_atrasos_de e o "você ainda não me disse que chegou" de agenda_ver_material: só leem item atrasado ou com o dia
--     já chegado, e a data provável só existe enquanto o dia dito NÃO chegou — esses itens têm data = o dia dito (o fato,
--     os_material.previsao_ate ou a previsão da OC);
--   · _agenda_compras_da_os ("chega … (pela nota …)"): recriada aqui (acima); a tela (os_plano_da_os) e o TS só leem data_texto;
--   · os terços ao fornecedor (_agenda_material_tercos) leem os_material.previsao_ate direto: não mudam.
--
-- DESVIOS DA SPEC (provados em supabase/tests/agenda_fase6_fornecedor.sql):
--   · A data provável só vale enquanto o dia dito não chegou (q.data > p_hoje). No dia da previsão e depois, vale o dia dito:
--     é quando a agenda pergunta "chegou?", e as leituras que dizem "você ainda não me disse que chegou" leem o mesmo dia.
--   · data_dita só aparece quando a data provável vale (atraso em uso > 0): sem ela o item é o de antes, byte a byte (em
--     teste, todas as OS da fixture saem iguais à definição antiga).
--   · O atraso e o prazo medidos são dias úteis inteiros, para cima (ceil do P80): agenda_somar_du soma inteiros.
--   · O texto do prazo medido diz "notas" ("(medido em 5 notas)"; a spec: "entregas"): o prazo é medido pelas notas que
--     chegaram, e "entregas" é a unidade do atraso.
--   · O prazo medido não se aprende do fornecedor que o dono disse (só mede: o que ele disse vem antes) nem do importado (dias
--     corridos) nem do sem lugar (sem prazo de hoje para comparar).
--   · Os passos recebem p_agora (como no P2).
--
-- O QUE NÃO MUDA: a vigia de terços e o texto ao fornecedor (nenhuma mensagem nova a terceiros); a "chegou?"; o que o dono
-- disse (C); o foco fornecedores (o medido em uso sai dos grupos "você disse" e "meu chute": o P8 decide a linha). Nada roda
-- sozinho: a rodada é do P6 (agenda_aprender).
--
-- ORDEM DE LIGAR: depois de 20261029100200; antes de 20261029100400. Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase6_fornecedor.sql (a fixture-fase6 só na bancada; as portas e as cópias
-- em qualquer lugar). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029100300
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100300_agenda_fase6_fornecedor.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100300', 'agenda_fase6_fornecedor');"
--
-- DESFAZER: reaplicar, em ordem, as definições de 20261027100100 (_agenda_prazo_do_fornecedor), 20261027100200 (os_prontidao),
-- 20261027100600 (_agenda_compras_da_os, _agenda_ver_compras) e 20261029100200 (_agenda_aprendizado_texto); as 2 novas podem
-- ficar (ninguém de antes as chama).
--
-- IDEMPOTENTE: create or replace function; revoke/grant.

-- ── 1. As entregas de cada fornecedor: o atraso e o prazo da nota ────────────────────────────────────────
-- A entrega (spec-fase6 §5.3) = as linhas de os_material na mão (chegou_em) com a 1ª previsão de quem vende
-- (previsao_original_fonte fornecedor, oc, nfe ou pix), agrupadas por (fornecedor, a nota, senão a OC da linha, senão a
-- própria linha): várias linhas da mesma nota são uma entrega só. O fornecedor = o da linha, senão o da OC dela, senão o da
-- nota. O atraso da entrega = o MAIOR agenda_du_entre(previsao_original, chegou_em) das linhas (assinado: negativo quando
-- adiantou). O prazo da nota = agenda_du_entre(despacho_em, chegou_em) das material_remessas que chegaram.
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
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
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
  'Agenda de Produção (Fase 6, P3): o passo do fornecedor da rodada — (1) fornecedor_atraso por fornecedor: as entregas da janela (aprender_janela_dias; as linhas de os_material na mão com a 1ª previsão de fornecedor/OC/nota/Pix, agrupadas por fornecedor e nota, senão OC, senão linha: 3 linhas da mesma nota = 1 entrega; o fornecedor = o da linha, senão o da OC, senão o da nota; o atraso = o maior agenda_du_entre(previsao_original, chegou_em) das linhas, assinado), calculado = o P80 (fornecedor_percentil) arredondado para cima e nunca abaixo de 0, padrão 0, detalhe {nome, n, no_prazo, p50}; (2) fornecedor_prazo por fornecedor: as notas que chegaram (material_remessas, da saída à chegada), padrão = o prazo de hoje de _agenda_prazo_do_fornecedor (du_classe quando o medido já está em uso); o que o dono disse vem antes (só mede). Tudo pelo gravador (_agenda_aprendizado_gravar), nível fornecedor, chave = o id do fornecedor. O erro de um fornecedor vai a app_error_logs (agenda / aprender:fornecedor) e o passo segue. Nenhuma mensagem ao fornecedor. {chaves, estados, acoes, perguntas, erros}. Sem grant a ninguém.';

-- O atraso de um fornecedor como a agenda o mediu: {fornecedor_id, nome, du (o medido), n, n_min, no_prazo, em_uso (o que a
-- prontidão soma à previsão do nível B; nulo = nada), estado, texto}. Sem linha: nulo.
create or replace function public._agenda_atraso_do_fornecedor(p_forn uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select jsonb_build_object('fornecedor_id', p_forn, 'nome', a.detalhe ->> 'nome', 'du', a.calculado, 'n', a.n, 'n_min', a.n_min,
                            'no_prazo', (a.detalhe ->> 'no_prazo')::int,
                            'em_uso', public._agenda_aprendido('fornecedor_atraso', p_forn::text),
                            'estado', a.estado, 'texto', a.texto)
    from public.agenda_aprendizado a
   where p_forn is not null and a.item = 'fornecedor_atraso' and a.chave = p_forn::text;
$function$;

comment on function public._agenda_atraso_do_fornecedor(uuid) is
  'Agenda de Produção (Fase 6, P3): o atraso medido de um fornecedor — {fornecedor_id, nome, du (o medido), n, n_min, no_prazo, em_uso (o que a prontidão soma à previsão do nível B: _agenda_aprendido, só com modo_aprendizado ligado e fornecedor na lista; nulo = nada), estado, texto (a linha do foco)}. Sem medida: nulo. Leitura invoker (a RLS de quem lê vale).';

-- ── 4. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 6:") ──────────────────
-- Fora dos blocos nenhuma linha muda (o F6 do teste confere). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- _agenda_aprendizado_texto (de 20261029100200_agenda_fase6_os.sql)
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
  -- O fator de campo (spec-fase6 §6.2 e §6.3).
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
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe).';

-- _agenda_prazo_do_fornecedor (de 20261027100100_agenda_fase4_fornecedores.sql)
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
  'Agenda de Produção (Fase 4): o prazo do fornecedor numa fonte só, {classe, du, corridos, fonte, duvida, principal_id, texto}. A 1ª regra que valer: o que o dono disse (suppliers.modalidade, fonte dono) → cadastro repetido (outro ativo com o mesmo nome de grupo: o inativo vale como o ativo que ficou; dois ativos de classe diferente = só o principal, CNPJ de 14 dígitos e mais produtos + contas, tem classe, os dois com duvida duplicado) → pelo nome (marketplace, importado; fonte nome) → pela cidade/UF tolerante ao caractere quebrado (fonte cidade) → nada (duvida sem_lugar). Os dias: os do dono, senão os da classe (agenda_config.prazo_classe_du); importado em dias corridos (agenda_config.importacao_dias). texto: "entrega local, 1 dia útil (pela cidade, chute meu)". FASE 6 (P3): logo depois do que o dono disse, a fonte medido — com fornecedor_prazo em uso (_agenda_aprendido: modo_aprendizado ligado e fornecedor na lista), du = o medido das notas que chegaram (da saída até a chegada), fonte medido, texto "outro estado, 6 dias úteis (medido em 5 notas)" e du_classe = o prazo de antes; o importado não muda.';

-- os_prontidao (de 20261027100200_agenda_fase4_compras.sql)
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
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P2: a linha de OC recebida ligada a um item de texto livre da conta conta só nele, não de novo como item da OC que já chegou; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira. Fase 6 (P3): no item de nível B, enquanto o dia dito não chegou e com o atraso do fornecedor em uso (fornecedor_atraso: _agenda_aprendido), data = a data provável (o dia dito + o atraso; é ela que move o DPM, o início pelo material e o motor), data_dita = o dia dito (o fato) e data_texto "a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11"; atrasado e sem_data continuam pelo dia dito (a "chegou?"); C, A, D e E não mudam; sem atraso em uso, o item é o de antes.';

-- _agenda_compras_da_os (de 20261027100600_agenda_fase4_leituras.sql)
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
  -- FASE 6: (P3) o item com a data provável (data_dita = o que a OC/nota/fornecedor diz; data = com o atraso medido) não diz
  -- "chega <data provável> (pela nota …)", que poria a conta da agenda como palavra do fornecedor: vale o texto da
  -- prontidão, que diz os dois. Sem data provável na OS, a conta de cima vale como está.
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ? 'data_dita') then
    select array_agg(format('"%s" ', i ->> 'curto')
                     || case when i ? 'data_dita' then i ->> 'data_texto'
                             when m.remessa_id is not null and i ->> 'nivel' = 'B' and i ->> 'previsao_fonte' = 'nfe'
                             then format('chega %s (pela %s)', public._dia_curto((i ->> 'data')::date),
                                         coalesce(public._agenda_remessa_nota(m.remessa_id), 'nota'))
                             else i ->> 'data_texto' end
                     order by o) filter (where i ->> 'situacao' in ('comprado', 'a_caminho'))
      into v_vindo
      from jsonb_array_elements(v_itens) with ordinality t(i, o)
      left join public.os_material m on m.id = (i ->> 'id')::uuid
     where coalesce((i ->> 'critico')::boolean, true);
  end if;
  -- FASE 6: fim

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
  'Agenda de Produção (Fase 4, P6): o material de uma OS para o foco compras, a partir da prontidão (p_p, os itens críticos) e da linha da espera (p_esp, de agenda_espera_de_peca): os a comprar (nível D) contados, com "nada comprado desde a aprovação (…, há N dias)" quando a OS não comprou nada; o comprado/a caminho com a chegada e a fonte (a da nota diz qual: "pela nota 51038 da Kamell"); o fornecedor sem prazo um a um; os sem fornecedor contados, com "de quem e quando?"; e "Compre até … para começar …" (a restrição compre_ate). Tudo na mão e sem início: "material na mão desde …, parado há N dias úteis; começa …". null = nada a dizer. FASE 6 (P3): o item com a data provável (data_dita) usa o data_texto da prontidão ("a nota diz …; Kamell costuma atrasar até 2 dias úteis: conto com …"), nunca "chega <data provável> (pela nota …)".';

-- _agenda_ver_compras (de 20261027100600_agenda_fase4_leituras.sql)
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
  'Agenda de Produção (Fase 4, P6): agenda_ver foco compras. Sem OS, até texto_max: "Compras (sex 30/10):", uma linha por serviço da fila (sem orçamento) com material fora de A (_agenda_compras_da_os: o que falta, "nada comprado desde a aprovação", "Compre até … para começar …", o que vem e de onde, "de quem e quando?") e os de material na mão parados; "Não conto N parados no cliente."; as notas sem a palavra do dono ("Não sei de qual serviço é a nota 812 da Correa (qui 29/10): …"); o tempo até comprar (agenda_espera_de_peca); a pergunta ao fornecedor da semana (_agenda_fornecedor_frase; sombra "Ao fornecedor (em teste): eu teria perguntado …"); em sombra do detector, "Leitura das conversas (em teste): …" (agenda_detector_precisao). Com OS (também a concluída): a frase da espera (os 3 componentes), "• Material: …" e as perguntas ao fornecedor dela. Os serviços saem do fim com "• e mais N"; o resto, pela linha. Definer (lê a fila do WhatsApp e as perguntas ao fornecedor por inteiro): com login, só administrador e financeiro (senão 42501). {ok, texto, dados}. FASE 6 (P3): sem OS e com o aprendizado fora de desligado, até 3 linhas do que a agenda mediu de cada fornecedor (o atraso das entregas e o prazo da nota: a linha de agenda_aprendizado.texto), peso 1 na cauda.';

-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A leitura nova (invoker: a RLS de quem lê vale; o técnico não lê agenda_aprendizado e recebe nulo) para authenticated e
-- service_role, nunca anon.
revoke all on function public._agenda_atraso_do_fornecedor(uuid) from public, anon;
grant execute on function public._agenda_atraso_do_fornecedor(uuid) to authenticated, service_role;

-- O passo da rodada: sem grant a ninguém, nem service_role (quem chama é a rodada do P6, agenda_aprender, definer).
revoke all on function public._agenda_aprender_fornecedor(date, timestamptz) from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public._agenda_aprendizado_texto(text, text, jsonb), public._agenda_prazo_do_fornecedor(uuid),
  public.os_prontidao(uuid, date), public._agenda_compras_da_os(jsonb, jsonb, date), public._agenda_ver_compras(uuid, date)
  from public, anon;
grant execute on function public._agenda_aprendizado_texto(text, text, jsonb), public._agenda_prazo_do_fornecedor(uuid),
  public.os_prontidao(uuid, date), public._agenda_compras_da_os(jsonb, jsonb, date), public._agenda_ver_compras(uuid, date)
  to authenticated, service_role;
