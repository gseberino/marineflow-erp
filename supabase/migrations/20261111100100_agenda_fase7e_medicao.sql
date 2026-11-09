-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P2: a medição — a rodada passa a medir o quanto as OS e as compras erram, e o gravador
-- anda aos poucos nos itens da margem. É o coração da etapa: sem isto os pacotes seguintes não têm o que ler.
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (§5.1, §6.2, §6.3 e o bloco R7, que vale sobre o corpo: R7.1, R7.4, R7.5-1 a 7, 9, 19, 20, 22 e 23, R7.6, R7.12, R7.13);
-- nomes: fase7-registro.md; o registro do pacote: notas-fase7e.md.
-- Depende de 20261111100000 (P1). Copiado das definições MAIS NOVAS: _agenda_aprender_congelar (20261031100500_agenda_fase7a_medicao.sql:164), agenda_medir_os (20261031100500_agenda_fase7a_medicao.sql:235), _agenda_aprendizado_valor (20261029100100_agenda_fase6_medicao.sql:581), _agenda_aprendizado_texto (20261029100950_agenda_fase6_correcao_textos.sql:674), _agenda_aprendizado_gravar (20261029100950_agenda_fase6_correcao_textos.sql:1117).
--
-- ═══ NÃO APLICADA ═══ Existe para revisão e espera o OK (publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção).
-- ESCREVE EM DADO: enche pm_reais e compra_pendente nas linhas de agenda_medidas_os que já existem (22 em produção) e põe NOT NULL e DEFAULT nas duas (obrigação do P1, R7.5-1): sem isso a linha
-- antiga recusaria o NOT NULL. Para isso desliga por um instante, dentro da transação, o gatilho agenda_medidas_os_so_muda, que só deixa mudar com versão nova (faxina sem versão).
--
-- POR QUE: a agenda erra as durações sem saber o quanto, e as medidas da Fase 6 não medem nada na equipe de hoje: toda OS do Alex cai em sem_diaria (ele não tem perfil de diária) e 13 das 22 caem em
-- sem_inicio (2 check-ins contra 11 check-outs em 90 dias). R7.4 redesenha a porta: quem prova o trabalho é o resultado do dia, e o início é o check-in OU o 1º meio-dia feito.
--
-- O QUE MUDA:
--   1. _agenda_aprender_congelar: o 2º laço (o da estimativa do início, §5.1 e R7.4): toda OS com check-in OU 1º dia de alocação vigente não reserva até hoje congela, uma vez, a estimativa bruta
--      (dp_bruto_no_inicio: horas ÷ jornada, MO ÷ R$ da config, nunca o aprendido; nula sem base e no diagnóstico, R7.5-9), as pessoas, os pessoa-meios do molde (sem o dono que vai junto, R7.4), o 1º dia
--      e o prazo planejado. A linha de os_planejamento nasce se faltar, sem tocar em atualizado_em (R7.5-22: a marca d'água do encaixe do gestor olha essa coluna). O retorno ganha estimativas_congeladas.
--      A estimativa e o molde são lidos sob a simulação do gestor (agenda.gestor = sombra): o freio não muda o número que congela uma vez.
--   2. agenda_medir_os: as 12 colunas da margem, gravadas nos 3 caminhos (insert e os 2 update; R7.5-1). pm_reais por (dia, turno, pessoa) sem o dono que vai junto; motivo_razao com a porta de R7.4.
--      motivo, valida e fator da Fase 6 NÃO mudam: o fator segue preso (achado registrado em audit/novos-achados.md).
--   3. Funções novas: _agenda_margem_tipo_os, _agenda_margem_dp_bruto e _agenda_margem_dono_e_pessoa (as réguas da medida, que não leem o freio); _agenda_material_critico (R7.5-5); _agenda_margem_em_uso
--      (R7.5-7: o leitor dos itens da margem; _agenda_aprendido NÃO é recriada); _agenda_vies_da_os e _agenda_tempo_interno_compra (R7.5-23, nascem aqui); _agenda_aprender_congelar_marcacao (o que valeu
--      quando a OS ganhou o 1º compromisso); agenda_medir_compra e _agenda_aprender_medir_compras (a tabela das compras).
--   4. _agenda_aprendizado_gravar: o ramo por passo dos itens da margem (nunca pergunta; o em uso anda até o limite por rodada e o alvo fica no calculado; a ação guarda o passo, R7.5-19). Lê o modo CRU (R7.6).
--      _agenda_aprendizado_valor e _agenda_aprendizado_texto: os números e os textos dos 6 itens (§6.2, §6.3, R7.3).
--
-- O QUE NÃO MUDA: agenda_aprender NÃO é recriada (o P7 põe medir_compras e congelar_marcacao no passo e o relógio de aprender_tempo_max): até lá as funções novas não rodam sozinhas; quem roda é o congelar e o
-- medir de sempre, que já estão na rodada. Nenhum SQL novo em agenda_vigiar, agenda_cliente_vigiar e agenda_propor. Os itens da Fase 6, no gravador e nos textos, byte a byte. Nenhuma mensagem nova a dono, equipe ou
-- cliente: nenhum item da margem sai de medindo ou em teste com os interruptores como nascem, e o gravador não é chamado por nenhum deles até o P3 em diante. Nada de dinheiro.
--
-- ORDEM DE LIGAR (spec R7.14): logo depois de 20261111100000. Aplicar sozinha muda só o que a rodada das 16:00 grava em agenda_medidas_os e os_planejamento.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7e_medicao.sql (begin/rollback). Na bancada: node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (só com o OK, pelo publicar/exec/aplicar.sh):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261111100100_agenda_fase7e_medicao.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name) values ('20261111100100', 'agenda_fase7e_medicao');"
--
-- DESFAZER (só com os interruptores desligados e nada usando):
--   alter table public.agenda_medidas_os alter column pm_reais drop not null, alter column compra_pendente drop not null, alter column pm_reais drop default, alter column compra_pendente drop default;
--   drop function if exists public._agenda_margem_tipo_os(uuid), public._agenda_margem_dp_bruto(uuid, jsonb), public._agenda_margem_dono_e_pessoa(uuid), public._agenda_material_critico(uuid),
--     public._agenda_margem_em_uso(text, text), public._agenda_vies_da_os(uuid), public._agenda_tempo_interno_compra(uuid), public._agenda_aprender_congelar_marcacao(date),
--     public.agenda_medir_compra(uuid, date), public._agenda_aprender_medir_compras(date);
--   e recriar _agenda_aprender_congelar e agenda_medir_os de 20261031100500, _agenda_aprendizado_valor de 20261029100100, _agenda_aprendizado_texto e _agenda_aprendizado_gravar de 20261029100950.
--
-- IDEMPOTENTE: create or replace, revoke/grant, comment, set not null e set default; a faxina só anda se houver linha para encher.

-- ── 1. As réguas da medida (não leem o freio: a medição roda igual com ou sem ele, R7.6) ─────────────
-- O tipo da OS na régua de os_presenca_do_dono (o service_type, ou a linha de maior valor): diagnóstico, comissionamento ou nulo. A estimativa bruta do diagnóstico não sai do valor (R7.5-9) e o dono só é uma das
-- pessoas nesses tipos ou com a equipe dita (R7.4). Não usa _agenda_gestor_regra: com o freio ela é falsa para tudo, e a medida daria diferente.
create or replace function public._agenda_margem_tipo_os(p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
           when so.service_type = 'diagnosis' or coalesce(pr.principal, '') ~ 'diagnost' then 'diagnóstico'
           when so.service_type = 'commissioning' or coalesce(pr.principal, '') ~ '(comissionament|parametriz)' then 'comissionamento'
         end
    from public.service_orders so
    left join lateral (
      select public._agenda_normal(s.name_snapshot) as principal
        from public.service_order_services s
       where s.service_order_id = so.id
       order by s.line_total desc nulls last, s.created_at, s.id
       limit 1) pr on true
   where so.id = p_os;
$function$;

comment on function public._agenda_margem_tipo_os(uuid) is
  'Agenda de Produção (Fase 7e, P2; R7.4, R7.5-9): diagnóstico, comissionamento ou nulo, pela régua de os_presenca_do_dono (service_type ou a linha de maior valor), sem ler o freio nem a presença dita. STABLE, invoker, sem grant.';

-- As diárias-pessoa da estimativa pelo valor: horas ÷ jornada ou MO ÷ R$ da config (nunca o aprendido, NOVO-agenda-7e-b). Nula sem base, no diagnóstico (R7.5-9) e quando arredonda a zero (o CHECK > 0 recusaria e derrubaria o passo).
create or replace function public._agenda_margem_dp_bruto(p_os uuid, p_sug jsonb)
 returns numeric
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
           when coalesce((p_sug ->> 'sem_base')::boolean, true) then null
           when public._agenda_margem_tipo_os(p_os) = 'diagnóstico' then null
           else nullif(round(greatest(coalesce((p_sug ->> 'horas')::numeric, 0) / c.jornada_horas,
                                      coalesce((p_sug ->> 'mo')::numeric, 0) / c.mo_por_diaria_real), 2), 0)
         end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_margem_dp_bruto(uuid, jsonb) is
  'Agenda de Produção (Fase 7e, P2; §5.1, R7.5-9): as diárias-pessoa brutas da estimativa pelo valor, de uma saída de os_duracao_sugerida: greatest(horas ÷ jornada_horas, MO ÷ mo_por_diaria_real), 2 casas. Nula sem base, no diagnóstico e quando arredonda a zero. STABLE, invoker, sem grant.';

-- O dono é uma das pessoas da OS? Só com a equipe dita ou no diagnóstico e no comissionamento (R7.4). Fora disso ele vai junto: só conta sozinho no meio-dia.
create or replace function public._agenda_margem_dono_e_pessoa(p_os uuid)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select exists (select 1 from public.os_planejamento_equipe e where e.service_order_id = p_os)
         or coalesce(public._agenda_margem_tipo_os(p_os), '') in ('diagnóstico', 'comissionamento');
$function$;

comment on function public._agenda_margem_dono_e_pessoa(uuid) is
  'Agenda de Produção (Fase 7e, P2; R7.4): o dono conta como pessoa da OS em todo meio-dia? Com a equipe dita, no diagnóstico e no comissionamento, sim; fora disso ele vai junto e só conta quando está sozinho no meio-dia (a régua do tem de _agenda_gestor_pessoa_meios, sem a regra que o freio apaga). STABLE, invoker, sem grant.';

-- A linha de material é crítica? O fato do dono vence; sem ele, o valor unitário contra critico_valor_min; sem valor, crítica (R7.5-5: a coluna critico é true em todas as linhas de produção). Sem portão de regra.
create or replace function public._agenda_material_critico(p_linha uuid)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c    public.agenda_config := public._agenda_cfg();
  m    public.os_material;
  v_vu numeric;
begin
  select * into m from public.os_material where id = p_linha;
  if not found then
    return null;
  end if;
  if coalesce(m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false) then
    return coalesce(m.critico, true);
  end if;
  if m.origem = 'peca' then
    select sp.unit_sale_snapshot into v_vu from public.service_order_parts sp where sp.id = m.service_order_part_id;
  elsif m.origem = 'texto_livre' then
    select ss.unit_price_snapshot into v_vu from public.service_order_services ss where ss.id = m.service_order_service_id;
  elsif m.origem = 'oc' then
    select pi.unit_cost into v_vu from public.purchase_order_items pi where pi.id = m.purchase_order_item_id;
  end if;
  -- nullif(greatest(…)): sem valor ou zerado ninguém preencheu (linha crítica), como em os_prontidao
  v_vu := nullif(greatest(v_vu, 0), 0);
  return case when v_vu is null then true else v_vu >= c.critico_valor_min end;
end;
$function$;

comment on function public._agenda_material_critico(uuid) is
  'Agenda de Produção (Fase 7e, P2; R7.5-5): a linha de material é crítica para a medida de compra? O fato do dono (fonte dono/fornecedor/nfe/pix) vence; sem ele, o valor unitário (unit_sale_snapshot, unit_price_snapshot, unit_cost) contra critico_valor_min; sem valor (ou zerado), crítica. É a conta de os_prontidao, sem o portão critico_por_valor (que o freio apaga). Nulo se a linha não existe. STABLE, invoker, sem grant.';

-- ── 2. O leitor dos itens da margem ──────────────────────────────────────────────────────────────────
-- R7.5-7: _agenda_aprendido fica como está (roda dezenas de vezes por tique). Quem lê a margem usa esta, que passa pelo modo efetivo (com o freio: R7.6).
create or replace function public._agenda_margem_em_uso(p_item text, p_chave text)
 returns numeric
 language sql
 stable
 set search_path to 'public'
as $function$
  select a.em_uso
    from public.agenda_aprendizado a
    join public.agenda_config c on c.id
   where a.item = p_item and a.chave = p_chave
     and a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null
     and c.modo_aprendizado = 'ligado'
     and public._agenda_margem_modo(p_item) = 'ligado'
     and not (p_item = 'vies' and p_chave like 'dono:%' and not c.vies_corrige_dono);
$function$;

comment on function public._agenda_margem_em_uso(text, text) is
  'Agenda de Produção (Fase 7e, P2; R7.5-7, R7.6): o valor em uso de um item da margem, só com modo_aprendizado ligado e o interruptor do item ligado pelo modo EFETIVO (o freio apaga); a chave dono: do viés exige vies_corrige_dono. Nulo = o padrão de hoje. STABLE, invoker; porta para authenticated e service_role (P3 e P6 a leem de funções invoker).';

create or replace function public._agenda_vies_da_os(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_fina  text := 'estimativa:' || (public._agenda_classe_de_campo(p_os) ->> 'chave');
  v_geral text := 'estimativa:todas';
  v_uso   numeric;
  v_chave text;
  a       public.agenda_aprendizado;
begin
  v_uso := public._agenda_margem_em_uso('vies', v_fina);
  v_chave := case when v_uso is not null then v_fina end;
  if v_uso is null then
    v_uso := public._agenda_margem_em_uso('vies', v_geral);
    v_chave := case when v_uso is not null then v_geral end;
  end if;
  -- o calculado que vale: a chave em uso, senão a fina, senão a geral (o "teria" mostra o que seria também em teste)
  select x.* into a
    from public.agenda_aprendizado x
   where x.item = 'vies' and x.chave in (v_fina, v_geral) and x.calculado is not null
   order by case x.chave when v_chave then 0 when v_fina then 1 else 2 end
   limit 1;
  return jsonb_build_object('chave', v_chave, 'vies_em_uso', v_uso, 'calculado', a.calculado, 'estado', a.estado, 'n', a.n, 'texto', a.texto,
                            'teria', a.calculado);
end;
$function$;

comment on function public._agenda_vies_da_os(uuid) is
  'Agenda de Produção (Fase 7e, P2; §5.2, R7.5-23): o viés da OS — {chave (a que deu o valor em uso), vies_em_uso (nulo = nada em uso = 1,00), calculado, estado, n, texto, teria (o calculado da fina, senão o do geral, mesmo em teste)}. Pela fina (estimativa:<bem>:<sistema>) e depois o geral, por _agenda_margem_em_uso. STABLE, invoker; porta para authenticated e service_role.';

create or replace function public._agenda_tempo_interno_compra(p_os uuid)
 returns integer
 language plpgsql
 stable
 set search_path to 'public'
as $function$
begin
  -- coalesce por fora (R7.12-3): 127 das 131 OS não têm linha em os_planejamento, e um "select coalesce(…) into" sem linha daria nulo
  return coalesce(
    (select pl.tempo_compra_marcado::int from public.os_planejamento pl where pl.service_order_id = p_os limit 1),
    case when public._agenda_margem_modo('tempo_compra') = 'ligado' then public._agenda_margem_em_uso('tempo_compra', 'todas')::int end,
    (public._agenda_cfg()).compra_interna_du::int);
end;
$function$;

comment on function public._agenda_tempo_interno_compra(uuid) is
  'Agenda de Produção (Fase 7e, P2; §5.5, R7.5-23, R7.12-3): os dias úteis internos de compra da OS — o congelado na marcação (tempo_compra_marcado), senão, com modo_tempo_compra ligado de verdade, o em uso, senão compra_interna_du. Nunca nulo, também em OS sem linha de os_planejamento. STABLE, invoker; porta para authenticated e service_role.';

-- ── 3. O congelar da marcação ────────────────────────────────────────────────────────────────────────
-- §5.1, R7.3-2. Roda antes de aprender; o P7 o põe na rodada. Definer, sem grant.
create or replace function public._agenda_aprender_congelar_marcacao(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  r       record;
  v       jsonb;
  v_dia   date;
  v_vies  numeric;
  n_c     int := 0;
  n_s     int := 0;
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  -- 1. A OS que tem compromisso (ou meio-dia feito) e ainda não tem o congelado: o valor que valeu desde a rodada anterior. Sem o que aprender, 1,00, o tempo interno de hoje e 0 (R7.5-16: a folga da compra não tem leitor nesta etapa).
  for r in
    select so.id as os, so.created_at as criada,
           (select min(a.publicada_em) from public.agenda_alocacoes a
             where a.service_order_id = so.id and a.tipo <> 'reserva' and a.publicada_em is not null) as prim
      from public.service_orders so
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.merged_into_id is null and pl.marcado_em is null
       and exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and (a.dia >= p_hoje or a.resultado in ('cumprido', 'parcial')))
     order by so.id
  loop
    continue when r.prim is null;
    v_dia := (r.prim at time zone 'America/Sao_Paulo')::date;
    v := public._agenda_vies_da_os(r.os);
    v_vies := coalesce((v ->> 'vies_em_uso')::numeric, 1);
    insert into public.os_planejamento as x (service_order_id, marcado_em, vies_marcado, vies_marcado_chave, tempo_compra_marcado,
                                             folga_compra_marcada, atualizado_em)
    values (r.os, v_dia, v_vies, v ->> 'chave', public._agenda_tempo_interno_compra(r.os), 0, r.criada)
    on conflict (service_order_id) do update
      set marcado_em = excluded.marcado_em, vies_marcado = excluded.vies_marcado, vies_marcado_chave = excluded.vies_marcado_chave,
          tempo_compra_marcado = excluded.tempo_compra_marcado, folga_compra_marcada = excluded.folga_compra_marcada
      where x.marcado_em is null;
    n_c := n_c + 1;
  end loop;

  -- 2. A OS que voltou à fila (nenhum compromisso vigente nem meio-dia feito): solta o congelado. A saída do dono (vies_dono_fixo) fica: sem isso se apagaria sozinha (R7.3-2).
  with x as (
    update public.os_planejamento p
       set marcado_em = null, vies_marcado = null, vies_marcado_chave = null, tempo_compra_marcado = null, folga_compra_marcada = null
     where p.marcado_em is not null and not p.vies_dono_fixo
       -- nenhuma alocação vigente não reserva: resultado só existe em vigente (CHECK resultado_so_vigente), então "nem meio-dia feito" já está aqui
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = p.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
    returning 1)
  select count(*)::int into n_s from x;
  return jsonb_build_object('congeladas', n_c, 'soltas', n_s);
end;
$function$;

comment on function public._agenda_aprender_congelar_marcacao(date) is
  'Agenda de Produção (Fase 7e, P2; §5.1, R7.3-2, R7.5-22): congela, uma vez, o que valeu quando a OS ganhou o 1º compromisso — marcado_em (o dia da 1ª publicada_em não reserva), vies_marcado e chave, tempo_compra_marcado e folga_compra_marcada (0) —, e solta o congelado da OS que voltou à fila, salvo vies_dono_fixo. A linha de os_planejamento nasce se faltar e atualizado_em não muda. {congeladas, soltas}. Definer, sem grant a ninguém.';

-- ── 4. A medida da compra ────────────────────────────────────────────────────────────────────────────
-- §5.1, R7.5-3 a 6, desvio 10 do P1: a medida pode sumir com a linha (a cascata) e fornecedor_id pode virar nulo sem versão nova; nenhum dos dois é erro.
create or replace function public.agenda_medir_compra(p_linha uuid, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  l        public.os_material;
  so       public.service_orders;
  pl       public.os_planejamento;
  rm       public.material_remessas;
  m0       public.agenda_medidas_compra;
  m        public.agenda_medidas_compra;
  v_po     uuid;
  v_forn_oc uuid;
  v_orig   timestamptz;
  v_reg    date;
  v_prim   date;
  v_base   jsonb;
  v_crit   boolean;
  v_os_ok  boolean;
  v_entra  boolean;
  v_reab   boolean;
  v_folga  int;
  v_novo   jsonb;
  v_velho  jsonb;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
begin
  if p_linha is null or p_hoje is null then
    raise exception 'Falta a linha ou o dia.' using errcode = '22023';
  end if;
  -- for key share: a linha não some no meio da conta (a cascata de quem tira a peça espera o commit). Sem a linha, não é erro: a cascata levou a medida junto.
  select * into l from public.os_material where id = p_linha for key share;
  if not found then
    return jsonb_build_object('ok', true, 'medida', false, 'motivo', 'sem_linha');
  end if;
  select * into m0 from public.agenda_medidas_compra where os_material_id = p_linha for update;
  select * into so from public.service_orders where id = l.service_order_id;
  select * into pl from public.os_planejamento where service_order_id = l.service_order_id;
  v_os_ok := so.merged_into_id is null
             and (so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client', 'completed', 'invoiced')
                  or (so.status = 'draft' and so.quote_status in ('approved', 'awaiting_deposit')));
  v_crit := public._agenda_material_critico(p_linha);
  -- fonte nula é o caso comum (19 das 20 linhas de produção): por isso "is distinct from" (R7.5-4)
  v_entra := v_crit and l.fonte is distinct from 'estoque' and v_os_ok
             and (l.situacao in ('falta', 'comprado', 'a_caminho') or l.comprado_em is not null or l.remessa_id is not null
                  -- a de balcão: foi direto à mão pelo dono (a 4ª fonte da compra; sem isto nenhuma linha "balcao" nasceria)
                  or (l.situacao = 'na_mao' and l.fonte = 'dono')
                  or l.purchase_order_item_id is not null);
  if not v_entra and m0.os_material_id is null then
    return jsonb_build_object('ok', true, 'medida', false,
                              'motivo', case when not v_crit then 'nao_critica' when not v_os_ok then 'fora_da_carteira' else 'sem_compra' end);
  end if;
  if not v_os_ok then
    -- a OS que saiu da carteira (agrupada, cancelada) fica como estava
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', false, 'versao', m0.versao, 'motivo', m0.motivo);
  end if;
  v_reab := m0.os_material_id is not null
            and exists (select 1 from public.agenda_medidas_os x where x.service_order_id = l.service_order_id and x.motivo = 'reaberta');
  if l.remessa_id is not null then
    select * into rm from public.material_remessas where id = l.remessa_id;
  end if;
  if l.purchase_order_item_id is not null then
    select pi.purchase_order_id, po.supplier_id into v_po, v_forn_oc
      from public.purchase_order_items pi join public.purchase_orders po on po.id = pi.purchase_order_id
     where pi.id = l.purchase_order_item_id;
  end if;

  m.os_material_id := l.id;
  m.service_order_id := l.service_order_id;
  m.fornecedor_id := public._agenda_fornecedor_da_medida(coalesce(l.fornecedor_id, v_forn_oc, rm.fornecedor_id));
  m.entrega := coalesce('nota:' || l.remessa_id::text, 'oc:' || v_po::text, 'linha:' || l.id::text);
  m.aprovada_em := (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date;
  v_orig := case l.origem
              when 'peca' then (select sp.created_at from public.service_order_parts sp where sp.id = l.service_order_part_id)
              when 'texto_livre' then (select ss.created_at from public.service_order_services ss where ss.id = l.service_order_service_id)
            end;
  -- greatest ignora o nulo, e aqui é o certo (R7.12-2): a linha sem peça de origem (oc, dono) vale pela aprovação
  m.precisou_em := greatest(m.aprovada_em, (v_orig at time zone 'America/Sao_Paulo')::date);

  -- A data da compra: a 1ª fonte que houver, nesta ordem
  if l.comprado_em is not null then
    m.comprado_em := l.comprado_em;
    m.comprado_fonte := coalesce(l.comprado_fonte, 'dono');
  elsif rm.emitida_em is not null then
    m.comprado_em := rm.emitida_em;
    m.comprado_fonte := 'nfe';
  else
    -- a forma real da entrada é {em, de, para, por, autor, trecho, nota}, sem "depois" (R7.5-3); em é só a data na escrita de hoje, ou a hora nas entradas com relógio
    select case when x.e ->> 'em' ~ '^\d{4}-\d{2}-\d{2}$' then (x.e ->> 'em')::date
                else ((x.e ->> 'em')::timestamptz at time zone 'America/Sao_Paulo')::date end
      into v_reg
      from jsonb_array_elements(case when jsonb_typeof(l.historico) = 'array' then l.historico else '[]'::jsonb end) with ordinality x(e, n)
     where x.e ->> 'para' in ('comprado', 'a_caminho', 'na_mao')
     order by x.n
     limit 1;
    if v_reg is not null then
      m.comprado_em := v_reg;
      m.comprado_fonte := 'registro';
    elsif l.situacao = 'na_mao' and l.fonte = 'dono' and l.chegou_em is not null then
      m.comprado_em := l.chegou_em;
      m.comprado_fonte := 'balcao';
    end if;
  end if;
  m.chegou_em := case when l.situacao = 'na_mao' then l.chegou_em end;
  m.previsao_original_em := l.previsao_original_em;

  -- O retrato da marcação, gravado uma vez: a 1ª medida com marcada_em, e ele não muda depois
  v_base := l.compre_ate_base;
  m.sem_fornecedor := coalesce(v_base ->> 'prazo_fonte' = 'padrao', m.fornecedor_id is null);
  if m0.marcada_em is not null then
    m.marcada_em := m0.marcada_em;
    m.primeiro_dia := m0.primeiro_dia;
    m.compre_ate := m0.compre_ate;
    m.chegada_contada := m0.chegada_contada;
    m.prazo_contado_du := m0.prazo_contado_du;
    m.prazo_fonte := m0.prazo_fonte;
    m.tempo_interno_du := m0.tempo_interno_du;
    m.folga_compra_du := m0.folga_compra_du;
  elsif pl.marcado_em is not null and (m.comprado_em is null or m.comprado_em > pl.marcado_em) then
    select min(a.dia) into v_prim
      from public.agenda_alocacoes a
     where a.service_order_id = l.service_order_id and a.tipo <> 'reserva' and a.publicada_em is not null
       and (a.publicada_em at time zone 'America/Sao_Paulo')::date = pl.marcado_em;
    if v_prim is not null then
      v_folga := coalesce(pl.folga_compra_marcada, 0);
      m.marcada_em := pl.marcado_em;
      m.primeiro_dia := v_prim;
      m.prazo_contado_du := (v_base ->> 'prazo')::int;
      m.prazo_fonte := v_base ->> 'prazo_fonte';
      m.tempo_interno_du := pl.tempo_compra_marcado;
      m.folga_compra_du := v_folga;
      m.chegada_contada := public.agenda_somar_du(v_prim, -(c.folga_material_du + v_folga));
      m.compre_ate := coalesce(l.compre_ate,
                               public.agenda_somar_du(v_prim, -(c.folga_material_du + v_folga + m.prazo_contado_du + m.tempo_interno_du)));
    end if;
  end if;

  -- O medido. greatest(0, nulo) daria 0 e seria uma compra falsa de 0 dias (R7.12-2)
  m.tempo_compra_du := case when m.comprado_em is null then null else greatest(0, public.agenda_du_entre(m.precisou_em, m.comprado_em)) end;
  m.prazo_real_du := public.agenda_du_entre(m.comprado_em, m.chegou_em);
  m.atraso_chegada_du := public.agenda_du_entre(m.chegada_contada, m.chegou_em);
  m.comprou_ate_o_limite := m.comprado_em <= m.compre_ate;
  m.primeiro_dia_cumprido := case when m.primeiro_dia is null then null
                                  else exists (select 1 from public.agenda_alocacoes a
                                                where a.service_order_id = l.service_order_id and a.dia = m.primeiro_dia and a.tipo <> 'reserva'
                                                  and a.resultado in ('cumprido', 'parcial')) end;

  -- Validade e o motivo (o 1º que valer). compra_antes não invalida: a previsão é de antes da compra, e por isso a linha fica fora do atraso do fornecedor (d6)
  m.valida_tempo := v_entra and not v_reab and m.comprado_em is not null and m.comprado_fonte <> 'balcao';
  m.valida_prazo := v_entra and not v_reab and m.comprado_em is not null and m.chegou_em is not null and m.comprado_fonte <> 'balcao';
  m.valida_folga := v_entra and not v_reab and m.marcada_em is not null and m.chegou_em is not null;
  m.motivo := case
    when v_reab then 'reaberta'
    when not v_crit then 'nao_critica'
    when not v_entra then 'sem_compra'
    when m.comprado_em is null then 'sem_compra'
    when m.comprado_fonte = 'balcao' then 'balcao_inferido'
    when m.chegou_em is null then 'sem_chegada'
    when m.marcada_em is null and pl.marcado_em is null then 'nao_marcada'
    when m.marcada_em is null then 'comprada_antes_de_marcar'
    when m.previsao_original_em < m.comprado_em then 'compra_antes'
  end;

  -- Grava só quando muda (o molde de agenda_medir_os)
  m.medida_em := now();
  v_novo := to_jsonb(m) - array['medida_em', 'versao', 'historico'];
  if m0.os_material_id is null then
    m.versao := 1;
    m.historico := '[]'::jsonb;
    insert into public.agenda_medidas_compra select (m).* on conflict (os_material_id) do nothing;
    return jsonb_build_object('ok', true, 'medida', true, 'nova', true, 'mudou', true, 'versao', 1, 'valida_tempo', m.valida_tempo,
                              'valida_prazo', m.valida_prazo, 'valida_folga', m.valida_folga, 'motivo', m.motivo);
  end if;
  v_velho := to_jsonb(m0) - array['medida_em', 'versao', 'historico'];
  if v_novo = v_velho then
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', false, 'versao', m0.versao, 'valida_tempo', m0.valida_tempo,
                              'valida_prazo', m0.valida_prazo, 'valida_folga', m0.valida_folga, 'motivo', m0.motivo);
  end if;
  for k in select key from jsonb_each(v_novo) loop
    if v_novo -> k is distinct from v_velho -> k then
      v_antes := v_antes || jsonb_build_object(k, v_velho -> k);
      v_depois := v_depois || jsonb_build_object(k, v_novo -> k);
    end if;
  end loop;
  v_hist := m0.historico || jsonb_build_array(jsonb_build_object('em', p_hoje, 'versao', m0.versao, 'antes', v_antes, 'depois', v_depois));
  if jsonb_array_length(v_hist) > 20 then
    select jsonb_agg(x order by o) into v_hist
      from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
  end if;
  update public.agenda_medidas_compra
     set fornecedor_id = m.fornecedor_id, sem_fornecedor = m.sem_fornecedor, entrega = m.entrega, aprovada_em = m.aprovada_em, precisou_em = m.precisou_em,
         marcada_em = m.marcada_em, primeiro_dia = m.primeiro_dia, compre_ate = m.compre_ate, chegada_contada = m.chegada_contada,
         prazo_contado_du = m.prazo_contado_du, prazo_fonte = m.prazo_fonte, tempo_interno_du = m.tempo_interno_du, folga_compra_du = m.folga_compra_du,
         comprado_em = m.comprado_em, comprado_fonte = m.comprado_fonte, chegou_em = m.chegou_em, previsao_original_em = m.previsao_original_em,
         tempo_compra_du = m.tempo_compra_du, prazo_real_du = m.prazo_real_du, atraso_chegada_du = m.atraso_chegada_du,
         comprou_ate_o_limite = m.comprou_ate_o_limite, primeiro_dia_cumprido = m.primeiro_dia_cumprido,
         valida_tempo = m.valida_tempo, valida_prazo = m.valida_prazo, valida_folga = m.valida_folga, motivo = m.motivo,
         medida_em = m.medida_em, versao = m0.versao + 1, historico = v_hist
   where os_material_id = p_linha;
  return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', true, 'versao', m0.versao + 1, 'valida_tempo', m.valida_tempo,
                            'valida_prazo', m.valida_prazo, 'valida_folga', m.valida_folga, 'motivo', m.motivo);
end;
$function$;

comment on function public.agenda_medir_compra(uuid, date) is
  'Agenda de Produção (Fase 7e, P2; §5.1, R7.5-3 a 6, R7.12-2): monta a linha de agenda_medidas_compra de uma linha de material e grava só com diferença (versão + 1 e histórico). Entra a linha crítica (_agenda_material_critico), fonte distinta de estoque, com falta/compra/remessa/OC, em OS da carteira ou concluída; a data da compra na ordem comprado_em, nota, 1ª entrada do histórico (registro, pela chave para), balcão; o retrato da marcação uma vez; o medido e a validade. A linha sumida (a cascata) devolve medida falso: não é erro. compra_antes = a previsão é de antes da compra: a linha vale, mas fora do atraso do fornecedor. {ok, medida, nova, mudou, versao, valida_tempo, valida_prazo, valida_folga, motivo}. Definer, sem grant a ninguém.';

-- O passo da rodada. O erro de uma linha vai a app_error_logs e o passo segue; a linha que sumiu no meio é só medida falso.
create or replace function public._agenda_aprender_medir_compras(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  r      record;
  v      jsonb;
  n_olh  int := 0;
  n_med  int := 0;
  n_err  int := 0;
  n_t    int := 0;
  n_p    int := 0;
  n_f    int := 0;
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  for r in
    select m.id
      from public.os_material m
      join public.service_orders so on so.id = m.service_order_id
     where so.merged_into_id is null
       and ((coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
              between p_hoje - c.aprender_janela_dias and p_hoje
            or exists (select 1 from public.agenda_medidas_compra x where x.os_material_id = m.id and m.atualizado_em > x.medida_em))
     order by m.id
  loop
    n_olh := n_olh + 1;
    begin
      v := public.agenda_medir_compra(r.id, p_hoje);
      if coalesce((v ->> 'medida')::boolean, false) then
        n_med := n_med + 1;
        n_t := n_t + case when coalesce((v ->> 'valida_tempo')::boolean, false) then 1 else 0 end;
        n_p := n_p + case when coalesce((v ->> 'valida_prazo')::boolean, false) then 1 else 0 end;
        n_f := n_f + case when coalesce((v ->> 'valida_folga')::boolean, false) then 1 else 0 end;
      end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, medir compra %s: %s', r.id, sqlerrm), 'agenda', 'aprender:medir_compras', 'error',
                                   jsonb_build_object('linha', r.id, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  return jsonb_build_object('olhadas', n_olh, 'medidas', n_med, 'validas', jsonb_build_object('tempo', n_t, 'prazo', n_p, 'folga', n_f), 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_medir_compras(date) is
  'Agenda de Produção (Fase 7e, P2; §5.1): mede, cada linha no seu bloco, as linhas das OS aprovadas nos aprender_janela_dias e as que têm medida e mudaram depois dela. O erro de uma linha vai a app_error_logs (aprender:medir_compras) e o passo segue. {olhadas, medidas, validas: {tempo, prazo, folga}, erros}. Invoker, sem grant (o passo da rodada; o P7 o chama).';

-- ── 5. O congelar e a medida da OS ───────────────────────────────────────────────────────────────────
-- de 20261031100500_agenda_fase7a_medicao.sql:164; md5 do corpo de antes 969bca0c1e8fadb82acecdf346fafb7a
create or replace function public._agenda_aprender_congelar(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c   public.agenda_config := public._agenda_cfg();
  r   record;
  v   jsonb;
  n_c int := 0;
  n_s int := 0;
  -- FASE 7: (7a P6) a fonte orcamento só com o gestor ligado de verdade (a regra estimativa e o modo marcar ligado, fora da
  -- simulação da sombra)
  v_gestor boolean := public._agenda_gestor_regra('estimativa') and public._agenda_gestor_modo('marcar') = 'ligado';
  -- FASE 7: fim
  -- FASE 7e: (7e P2, §5.1, R7.4) o 2º laço: a estimativa do início
  r7       record;
  v_7e_sug jsonb;
  v_7e_m   jsonb;
  v_7e_ini date;
  v_7e_fim date;
  v_7e_dp  numeric;
  v_7e_pm  numeric;
  v_7e_pes int;
  v_7e_conta boolean;
  v_7e_gestor text;
  n_7e     int := 0;
  -- FASE 7e: fim
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  for r in
    select so.id as os, pl.service_order_id as tem_plano, pl.dias_no_inicio
      from public.service_orders so
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.check_in_at is not null and so.merged_into_id is null
       and (so.check_in_at at time zone 'America/Sao_Paulo')::date between p_hoje - c.aprender_janela_dias and p_hoje
       and pl.dias_no_inicio is null
     order by so.check_in_at, so.id
  loop
    v := case when r.tem_plano is not null then public._agenda_dias_no_inicio(r.os) end;
    -- FASE 7: (7a P6) a fonte orcamento — a estimativa que o gestor usou (o 4º passo de _agenda_dias_no_inicio, também na OS sem
    -- linha de planejamento) ou os dias que ele gravou quando a pergunta com prazo venceu — congela uma vez, com as
    -- diárias-pessoa estimadas (dp_no_inicio; nulas nos dias gravados). A linha de planejamento nasce se faltar (os dias de
    -- agora continuam nulos: só os do início). Só com o gestor ligado de verdade; sem ele, a fonte orcamento não congela, como
    -- antes.
    if v_gestor then
      if r.tem_plano is null then
        v := public._agenda_dias_no_inicio(r.os);
      end if;
      if v ->> 'fonte' = 'orcamento' then
        insert into public.os_planejamento as x (service_order_id, dias_no_inicio, dias_no_inicio_fonte, dias_no_inicio_em,
                                                 dp_no_inicio)
        values (r.os, (v ->> 'dias')::numeric, 'orcamento', (v ->> 'em')::date, (v ->> 'dp')::numeric)
        on conflict (service_order_id) do update
          set dias_no_inicio = excluded.dias_no_inicio, dias_no_inicio_fonte = excluded.dias_no_inicio_fonte,
              dias_no_inicio_em = excluded.dias_no_inicio_em, dp_no_inicio = excluded.dp_no_inicio
          where x.dias_no_inicio is null;
        n_c := n_c + 1;
        continue;
      end if;
    end if;
    -- FASE 7: fim
    if v is null or coalesce(v ->> 'fonte', '') not in ('dono', 'aceita') then
      n_s := n_s + 1;
      continue;
    end if;
    update public.os_planejamento
       set dias_no_inicio = (v ->> 'dias')::numeric, dias_no_inicio_fonte = v ->> 'fonte',
           dias_no_inicio_em = (v ->> 'em')::date
     where service_order_id = r.os and dias_no_inicio is null;
    n_c := n_c + 1;
  end loop;
  -- FASE 7e: (7e P2, §5.1, R7.4, R7.5-9, R7.5-22) o 2º laço: toda OS que começou (check-in OU o 1º dia de alocação vigente não reserva, o menor dos dois) congela, uma vez, a estimativa do início. O 1º laço, acima, não muda. Sem base ou no
  -- diagnóstico, dp_bruto fica nulo e a data grava mesmo assim (uma vez só: a OS sai daqui). O erro de uma OS não derruba as outras nem o que o 1º laço gravou. atualizado_em nunca é tocado: a marca d'água do encaixe do gestor o lê.
  for r7 in
    select x.os, x.dia, x.criada
      from (select so.id as os, so.created_at as criada,
                   -- least ignora o nulo, e aqui é o certo: sem check-in, vale o 1º dia; sem alocação, vale o check-in
                   least((so.check_in_at at time zone 'America/Sao_Paulo')::date,
                         (select min(a.dia) from public.agenda_alocacoes a
                           where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')) as dia
              from public.service_orders so
              left join public.os_planejamento pl on pl.service_order_id = so.id
             where so.merged_into_id is null and pl.estimativa_no_inicio_em is null) x
     where x.dia between p_hoje - c.aprender_janela_dias and p_hoje
     order by x.dia, x.os
  loop
    begin
      -- A estimativa do gestor é a de sem o freio: com ele, _agenda_gestor_regra é falsa para tudo e o número que congela uma vez entraria torto no viés (MO com deslocamento, outras pessoas, outro molde). As 2 chamadas, e só elas, sob a simulação que já existe (o portão lê agenda.gestor); o valor de antes volta logo depois e, num erro, volta pelo rollback do bloco.
      v_7e_gestor := coalesce(current_setting('agenda.gestor', true), '');
      perform set_config('agenda.gestor', 'sombra', true);
      v_7e_sug := public.os_duracao_sugerida(r7.os);
      v_7e_m := public.agenda_meios_da_os(r7.os, r7.dia);
      perform set_config('agenda.gestor', v_7e_gestor, true);
      v_7e_dp := public._agenda_margem_dp_bruto(r7.os, v_7e_sug);
      v_7e_conta := public._agenda_margem_dono_e_pessoa(r7.os);
      -- os pessoa-meios do molde: o dono com o turno conta quando está sozinho no meio-dia, ou é uma das pessoas (R7.4)
      select nullif(coalesce(sum((e ->> 'desejado')::int + case when e -> 'dono' ? 'turno' and ((e ->> 'desejado')::int = 0 or v_7e_conta) then 1 else 0 end), 0), 0)
        into v_7e_pm
        from jsonb_array_elements(coalesce(v_7e_m -> 'molde', '[]'::jsonb)) e;
      v_7e_pes := case when coalesce((v_7e_m ->> 'equipe_dita')::boolean, false)
                       then (select max((e ->> 'desejado')::int + case when e -> 'dono' ? 'turno' then 1 else 0 end)
                               from jsonb_array_elements(coalesce(v_7e_m -> 'molde', '[]'::jsonb)) e)
                       else (v_7e_m ->> 'pessoas_sugeridas')::int end;
      v_7e_pes := case when v_7e_pes between 1 and 6 then v_7e_pes end;
      select min(a.dia), max(a.dia) into v_7e_ini, v_7e_fim
        from public.agenda_alocacoes a
       where a.service_order_id = r7.os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
      insert into public.os_planejamento as x (service_order_id, estimativa_no_inicio_em, dp_bruto_no_inicio, pessoas_no_inicio,
                                               pm_plano_no_inicio, inicio_plano_no_inicio, prazo_plano_no_inicio, atualizado_em)
      values (r7.os, r7.dia, v_7e_dp, v_7e_pes, v_7e_pm, v_7e_ini,
              case when v_7e_ini is not null then public.agenda_du_entre(v_7e_ini, v_7e_fim) + 1 end, r7.criada)
      on conflict (service_order_id) do update
        set estimativa_no_inicio_em = excluded.estimativa_no_inicio_em, dp_bruto_no_inicio = excluded.dp_bruto_no_inicio,
            pessoas_no_inicio = excluded.pessoas_no_inicio, pm_plano_no_inicio = excluded.pm_plano_no_inicio,
            inicio_plano_no_inicio = excluded.inicio_plano_no_inicio, prazo_plano_no_inicio = excluded.prazo_plano_no_inicio
        where x.estimativa_no_inicio_em is null;
      n_7e := n_7e + 1;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, congelar a estimativa %s: %s', r7.os, sqlerrm), 'agenda', 'aprender:congelar', 'error',
                                   jsonb_build_object('os', r7.os, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
    end;
  end loop;
  return jsonb_build_object('congeladas', n_c, 'sem_dias', n_s, 'estimativas_congeladas', n_7e);
  -- FASE 7e: fim
  return jsonb_build_object('congeladas', n_c, 'sem_dias', n_s);
end;
$function$;

comment on function public._agenda_aprender_congelar(date) is
  'Agenda de Produção (Fase 6): a rodada do aprendizado congela, uma vez, os dias ditos no início — toda OS com check-in até p_hoje (na janela aprender_janela_dias) e sem os_planejamento.dias_no_inicio recebe o de _agenda_dias_no_inicio (só fonte dono ou aceita; a sugestão do banco nunca). {congeladas, sem_dias}. Definer, sem grant a ninguém. FASE 7 (7a P6): com o gestor ligado de verdade (a regra estimativa e o modo marcar ligado, fora da simulação da sombra), congela também a fonte orcamento — a estimativa que o gestor usou no dia do check-in (o 4º passo de _agenda_dias_no_inicio, também na OS sem linha de planejamento) e os dias que ele gravou pelo prazo —, uma vez, com dp_no_inicio (as diárias-pessoa estimadas; nulas nos dias gravados); a linha de os_planejamento nasce se faltar (os dias de agora continuam nulos). Conta em congeladas. Sem o portão, a fonte orcamento não congela (sem_dias), como antes. FASE 7e (P2): o 2º laço congela, uma vez, a estimativa do início (estimativa_no_inicio_em = o menor de check-in e 1º dia de alocação vigente não reserva; dp_bruto_no_inicio, pessoas_no_inicio, pm_plano_no_inicio, inicio_plano_no_inicio, prazo_plano_no_inicio). Sem base ou no diagnóstico, dp_bruto fica nulo. A linha nasce se faltar e atualizado_em não muda. O erro de uma OS vai a app_error_logs. O retorno ganha estimativas_congeladas. A estimativa e o molde saem sob agenda.gestor = sombra (o resultado de sem o freio) e o valor anterior da variável volta logo depois; o 1º laço e v_gestor não mudam.';

-- de 20261031100500_agenda_fase7a_medicao.sql:235; md5 do corpo de antes 8c3c39686b161fe637171cffeeba949f
create or replace function public.agenda_medir_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  so      public.service_orders;
  pl      public.os_planejamento;
  m0      public.agenda_medidas_os;
  m       public.agenda_medidas_os;
  v_concl boolean;
  v_cls   jsonb;
  v_d     jsonb;
  v_sug   jsonb;
  v_dono  uuid := public._agenda_dono();
  v_aloc  int;
  v_doaloc int;
  v_meios numeric;
  v_novo  jsonb;
  v_velho jsonb;
  v_antes jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist  jsonb;
  k       text;
  -- CORREÇÃO FASE 6: (C1) itens 4 e 9: o dia da conclusão pela porta e o fim da faixa do aviso sem a folga
  v_fim   date;
  v_plano date;
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P6) os meios-dias de turno do dono na OS por estimativa (para as diárias-pessoa reais)
  v_dono_meios numeric;
  -- FASE 7: fim
  -- FASE 7e: (7e P2, §5.1, R7.4) o que a medida da margem precisa
  v_7e_ini   date;
  v_7e_pm    numeric;
  v_7e_pf    numeric;
  v_7e_dp    numeric;
  v_7e_conta boolean;
  v_7e_sug   jsonb;
  v_7e_gestor text;
  c_razao_max constant numeric := 999::numeric / 100;
  -- FASE 7e: fim
begin
  if p_os is null or p_hoje is null then
    raise exception 'Falta a OS ou o dia.' using errcode = '22023';
  end if;
  select * into so from public.service_orders where id = p_os;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'nao_achei');
  end if;
  select * into m0 from public.agenda_medidas_os where service_order_id = p_os for update;
  v_concl := so.status in ('completed', 'invoiced') and so.merged_into_id is null;
  if not v_concl and m0.service_order_id is null then
    return jsonb_build_object('ok', true, 'medida', false, 'motivo', 'nao_concluida');
  end if;
  select * into pl from public.os_planejamento where service_order_id = p_os;
  v_sug := public.os_duracao_sugerida(p_os);

  m.service_order_id := p_os;
  v_cls := public._agenda_classe_de_campo(p_os);
  m.classe_bem := v_cls ->> 'bem';
  m.classe_sistema := v_cls ->> 'sistema';
  m.concluida_em := case when v_concl then (coalesce(so.check_out_at, so.updated_at) at time zone 'America/Sao_Paulo')::date
                         else m0.concluida_em end;
  -- CORREÇÃO FASE 6: (C1) item 9: a conclusão é o check-out, senão o 1º instante em que a porta deixou a OS concluída
  -- (_agenda_concluida_em); nunca a última edição (faturar, pagar ou entregar a moveriam). Sem nenhum dos dois, a medida não
  -- vale (sem_fim, abaixo) e a data fica a que já estava medida (senão a da última edição, só para a linha ter onde ficar):
  -- tocar a OS não move a conclusão.
  if v_concl then
    v_fim := public._agenda_concluida_em(p_os);
    m.concluida_em := coalesce(v_fim, m0.concluida_em, m.concluida_em);
  end if;
  -- CORREÇÃO FASE 6: fim
  m.entregue_em := (so.delivered_at at time zone 'America/Sao_Paulo')::date;

  -- Os dias: os ditos até o check-in; senão a duração sugerida (a medida não vale).
  v_d := case when pl.dias_no_inicio is not null
              then jsonb_build_object('dias', pl.dias_no_inicio, 'fonte', pl.dias_no_inicio_fonte)
              else public._agenda_dias_no_inicio(p_os) end;
  if v_d is null and not coalesce((v_sug ->> 'sem_base')::boolean, true) and (v_sug ->> 'sugerida') is not null then
    v_d := jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'fonte', 'sugerida');
  end if;
  m.dias_no_inicio := (v_d ->> 'dias')::numeric;
  m.dias_fonte := v_d ->> 'fonte';
  m.meios_planejados := (m.dias_no_inicio * 2)::smallint;

  -- Os meios-dias que aconteceram: (dia, turno) distintos das alocações vigentes não reserva da presença "turno" até a
  -- conclusão (cumprido 1, parcial meio, o resto 0; o melhor das pessoas daquele meio-dia).
  select coalesce(sum(x.valor), 0) into v_meios
    from (select a.dia, a.turno,
                 max(case a.resultado when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end) as valor
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
             and a.presenca = 'turno' and a.dia <= m.concluida_em
           group by a.dia, a.turno) x;
  select count(*)::int,
         count(*) filter (where a.payee_id = v_dono)::int,
         count(*) filter (where a.presenca = 'turno' and (a.resultado is null or a.resultado = 'sem_registro'))::smallint
    into v_aloc, v_doaloc, m.meios_sem_registro
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
     and a.dia <= m.concluida_em;
  m.so_o_dono := v_aloc > 0 and v_aloc = v_doaloc;

  -- As diárias ligadas à OS em dia sem alocação dela (a fração daquele dia na OS: 1 = 2 meios, meia = 1).
  select coalesce(sum(greatest(1, round(x.f * 2))), 0)::smallint into m.meios_fora_do_plano
    from (select ws.data, max(ws.fracao / (select count(*) from public.work_shift_os w2 where w2.shift_id = ws.id)) as f
            from public.work_shift_os wo
            join public.work_shifts ws on ws.id = wo.shift_id
            join public.work_profiles wp on wp.id = ws.work_profile_id
            join public.payees p on p.id = wp.payee_id
           where wo.service_order_id = p_os and ws.fracao > 0 and wp.modo_pagamento = 'diaria'
             and p.kind is distinct from 'socio' and ws.data <= m.concluida_em
             and not exists (select 1 from public.agenda_alocacoes a
                              where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                and a.dia = ws.data)
           group by ws.data) x;
  m.meios_cumpridos := v_meios + m.meios_fora_do_plano;
  select coalesce(sum(v.dias), 0) into m.diarias_ligadas from public.v_dias_por_os_e_pessoa v where v.service_order_id = p_os;
  m.mo := (v_sug ->> 'mo')::numeric;

  m.motivo := case
    when not v_concl then 'reaberta'
    when so.check_in_at is null then 'sem_inicio'
    when m.dias_no_inicio is null then 'sem_dias_no_inicio'
    when m.dias_fonte = 'sugerida' then 'dias_sugeridos'
    when v_aloc = 0 and m.diarias_ligadas = 0 then 'sem_plano'
    when m.meios_sem_registro > 0 then 'conferencia_incompleta'
    when m.diarias_ligadas = 0 and not m.so_o_dono then 'sem_diaria'
  end;
  -- CORREÇÃO FASE 6: (C1) item 9: sem o dia da conclusão, a medida não vale (sem_fim) — depois do sem check-in (a OS que nem
  -- começou diz isso primeiro), antes do resto
  if v_concl and v_fim is null and m.motivo is distinct from 'sem_inicio' then
    m.motivo := 'sem_fim';
  end if;
  -- CORREÇÃO FASE 6: fim
  m.valida := m.motivo is null;
  m.fator := case when m.valida and m.meios_planejados > 0
                  then least(round(m.meios_cumpridos / m.meios_planejados, 2), 99) end;
  -- FASE 7: (7a P6) a medida contra a estimativa do gestor (dias_fonte orcamento) vale como as outras (concluída, com check-in,
  -- a conferência completa, a diária ligada ou só o dono), mas o fator dela fica à parte, em fator_orcamento: o aprendizado do
  -- fator (que lê fator) continua só com os dias do dono. Sem portão: o dado orcamento só existe se o gestor marcou pela
  -- estimativa, e tratá-lo sempre assim protege o fator aprendido (ligado em produção) quando o gestor é desligado depois. As
  -- diárias-pessoa: as estimadas no check-in (dp_no_inicio, congeladas com os dias) e as reais (dp_reais: as diárias ligadas +
  -- os meios-dias de turno do dono ÷ 2; cumprido 1, parcial meio).
  if m.dias_fonte = 'orcamento' then
    m.fator_orcamento := m.fator;
    m.fator := null;
    m.dp_no_inicio := coalesce(pl.dp_no_inicio, (v_d ->> 'dp')::numeric);
    select coalesce(sum(case a.resultado when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end), 0) into v_dono_meios
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.presenca = 'turno' and a.payee_id = v_dono and a.dia <= m.concluida_em;
    m.dp_reais := round(m.diarias_ligadas + v_dono_meios / 2, 2);
  end if;
  -- FASE 7: fim

  -- O cliente: a 1ª promessa contra a conclusão; os avisos de atraso que saíram e o fim da faixa do último.
  m.prometido_primeiro_ate := coalesce(pl.prometido_primeiro_ate, pl.prometido_original_ate);
  m.atraso_cliente_du := public.agenda_du_entre(m.prometido_primeiro_ate, m.concluida_em);
  select count(*)::smallint into m.avisos_enviados
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo in ('pode_atrasar', 'nova_data') and x.modo = 'ligado' and x.enviada_em is not null;
  select coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) into m.aviso_faixa_ate
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo = 'pode_atrasar' and x.modo = 'ligado' and x.enviada_em is not null
     and coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) is not null
   order by x.enviada_em desc, x.id desc
   limit 1;
  -- CORREÇÃO FASE 6: (C1) item 4: o fim da faixa do último aviso SEM a folga do aprendizado (base.dados.faixa_ate_plano, que o
  -- registro grava quando a folga estava em uso); a mensagem de antes da correção não tem, e vale o faixa_ate dela. Assim a
  -- folga mede o erro do PLANO, não o dela mesma.
  select (x.base #>> '{dados,faixa_ate_plano}')::date into v_plano
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo = 'pode_atrasar' and x.modo = 'ligado' and x.enviada_em is not null
     and coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) is not null
   order by x.enviada_em desc, x.id desc
   limit 1;
  m.aviso_faixa_ate := coalesce(v_plano, m.aviso_faixa_ate);
  -- CORREÇÃO FASE 6: fim
  m.aviso_estouro_du := public.agenda_du_entre(m.aviso_faixa_ate, m.concluida_em);

  -- FASE 7e: (7e P2, §5.1, §3.1-5, R7.4, R7.5-1, R7.5-9) as 12 colunas da margem. A régua é a de R7.4: sem check-in nem meio-dia feito é sem_inicio; quem prova o trabalho é o resultado do dia, e sem_diaria só vale para quem TEM
  -- perfil de diária naquele dia (Alex sem perfil = a prova é o resultado; agenda_medidas_os.motivo e valida, da Fase 6, seguem como estão). O dono que vai junto não conta (achado 26 da 7a: 12, não 24).
  v_7e_conta := public._agenda_margem_dono_e_pessoa(p_os);
  select coalesce(sum(x.valor), 0) into v_7e_pm
    from (select a.dia, a.turno, a.payee_id, max(case a.resultado when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end) as valor
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
             and a.dia <= m.concluida_em
             and (v_7e_conta or a.payee_id is distinct from v_dono
                  or not exists (select 1 from public.agenda_alocacoes b
                                  where b.service_order_id = a.service_order_id and b.dia = a.dia and b.turno = a.turno
                                    and b.payee_id is distinct from a.payee_id and b.estado in ('publicada', 'fixada')
                                    and b.tipo <> 'reserva' and b.presenca = 'turno' and b.resultado is distinct from 'nao_cumprido'))
           group by a.dia, a.turno, a.payee_id) x;
  -- A diária ligada à OS num dia em que AQUELA pessoa não tem alocação dela (a fração do dia na OS: 1 = 2 meios, meia = 1)
  select coalesce(sum(greatest(1, round(x.f * 2))), 0) into v_7e_pf
    from (select ws.data, wp.payee_id, max(ws.fracao / (select count(*) from public.work_shift_os w2 where w2.shift_id = ws.id)) as f
            from public.work_shift_os wo
            join public.work_shifts ws on ws.id = wo.shift_id
            join public.work_profiles wp on wp.id = ws.work_profile_id
            join public.payees p on p.id = wp.payee_id
           where wo.service_order_id = p_os and ws.fracao > 0 and wp.modo_pagamento = 'diaria'
             and p.kind is distinct from 'socio' and ws.data <= m.concluida_em
             and not exists (select 1 from public.agenda_alocacoes a
                              where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                and a.dia = ws.data and a.payee_id = wp.payee_id)
           group by ws.data, wp.payee_id) x;
  m.pm_reais := v_7e_pm + v_7e_pf;
  -- A sugestão da margem, sem o freio (a mesma simulação do congelar): só quando a conta precisa dela. v_sug fica como está: é dele que saem as colunas da Fase 6 (mo, os dias sugeridos)
  if pl.dp_bruto_no_inicio is null or (m.dias_fonte in ('dono', 'aceita') and pl.pm_plano_no_inicio is null and pl.pessoas_no_inicio is null) then
    v_7e_gestor := coalesce(current_setting('agenda.gestor', true), '');
    perform set_config('agenda.gestor', 'sombra', true);
    v_7e_sug := public.os_duracao_sugerida(p_os);
    perform set_config('agenda.gestor', v_7e_gestor, true);
  end if;
  -- A estimativa: a congelada no início (dp_bruto_no_inicio); sem ela, a de agora (recalculada); sem base ou no diagnóstico, nula (R7.5-9)
  if pl.dp_bruto_no_inicio is not null then
    m.pm_estimados := 2 * pl.dp_bruto_no_inicio;
    m.estimativa_origem := 'congelada';
  else
    v_7e_dp := public._agenda_margem_dp_bruto(p_os, v_7e_sug);
    if v_7e_dp is not null then
      m.pm_estimados := 2 * v_7e_dp;
      m.estimativa_origem := 'recalculada';
    end if;
  end if;
  -- O plano do dono: só com os dias ditos por ele
  if m.dias_fonte in ('dono', 'aceita') then
    m.pm_plano_dono := coalesce(pl.pm_plano_no_inicio, m.meios_planejados * coalesce(pl.pessoas_no_inicio, (v_7e_sug ->> 'pessoas')::int, 1));
  end if;
  -- O prazo: do início real à conclusão. least ignora o nulo, e aqui é o certo (sem check-in vale o 1º meio-dia feito); depois da conclusão não é prazo, e fica nulo
  m.prazo_plano_du := pl.prazo_plano_no_inicio;
  v_7e_ini := least((so.check_in_at at time zone 'America/Sao_Paulo')::date,
                    (select min(a.dia) from public.agenda_alocacoes a
                      where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        and a.resultado in ('cumprido', 'parcial') and a.dia <= m.concluida_em));
  m.prazo_real_du := case when v_7e_ini <= m.concluida_em then public.agenda_du_entre(v_7e_ini, m.concluida_em) + 1 end;
  m.vies_marcado := pl.vies_marcado;
  m.compra_pendente := exists (select 1 from public.agenda_medidas_compra x
                               where x.service_order_id = p_os and x.marcada_em is not null and (x.comprado_em is null or x.comprado_em > x.marcada_em));
  m.motivo_razao := case
    when not v_concl then 'reaberta'
    when v_7e_ini is null then 'sem_inicio'
    when v_fim is null then 'sem_fim'
    when m.pm_estimados is null and m.pm_plano_dono is null then 'sem_estimativa'
    when m.meios_sem_registro > 0 then 'conferencia_incompleta'
    when m.diarias_ligadas = 0 and not m.so_o_dono
         and exists (select 1 from public.agenda_alocacoes a
                       join public.work_profiles w on w.payee_id = a.payee_id and w.modo_pagamento = 'diaria'
                        and w.vigencia_inicio <= a.dia and (w.vigencia_fim is null or w.vigencia_fim >= a.dia)
                      where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
                        and a.dia <= m.concluida_em) then 'sem_diaria'
    when m.pm_reais = 0 then 'sem_trabalho'
  end;
  if m.motivo_razao is null then
    m.razao_estimativa := case when m.pm_estimados > 0 then least(round(m.pm_reais / m.pm_estimados, 2), c_razao_max) end;
    m.razao_dono := case when m.pm_plano_dono > 0 then least(round(m.pm_reais / m.pm_plano_dono, 2), c_razao_max) end;
    m.razao_prazo := case when m.prazo_plano_du > 0 then least(round(m.prazo_real_du::numeric / m.prazo_plano_du, 2), c_razao_max) end;
  end if;
  -- FASE 7e: fim
  -- Grava só quando muda.
  m.medida_em := now();
  v_novo := to_jsonb(m) - array['medida_em', 'versao', 'historico'];
  if m0.service_order_id is null then
    m.versao := 1;
    m.historico := '[]'::jsonb;
    insert into public.agenda_medidas_os select (m).*;
    return jsonb_build_object('ok', true, 'medida', true, 'nova', true, 'mudou', true, 'versao', 1, 'valida', m.valida,
                              -- FASE 7e: (7e P2, §5.1) o que a medida da margem disse
                              'razao_estimativa', m.razao_estimativa, 'razao_prazo', m.razao_prazo, 'motivo_razao', m.motivo_razao,
                              -- FASE 7e: fim
                              'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
  end if;
  v_velho := to_jsonb(m0) - array['medida_em', 'versao', 'historico'];
  if v_novo = v_velho then
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', false, 'versao', m0.versao, 'valida', m0.valida,
                              -- FASE 7e: (7e P2, §5.1) o que a medida da margem disse
                              'razao_estimativa', m0.razao_estimativa, 'razao_prazo', m0.razao_prazo, 'motivo_razao', m0.motivo_razao,
                              -- FASE 7e: fim
                              'motivo', m0.motivo, 'fator', m0.fator, 'chave', v_cls ->> 'chave');
  end if;
  for k in select key from jsonb_each(v_novo) loop
    if v_novo -> k is distinct from v_velho -> k then
      v_antes := v_antes || jsonb_build_object(k, v_velho -> k);
      v_depois := v_depois || jsonb_build_object(k, v_novo -> k);
    end if;
  end loop;
  v_hist := m0.historico || jsonb_build_array(jsonb_build_object('em', p_hoje, 'versao', m0.versao,
                                                                  'antes', v_antes, 'depois', v_depois));
  if jsonb_array_length(v_hist) > 20 then
    select jsonb_agg(x order by o) into v_hist
      from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
  end if;
  -- FASE 7: (7a P6) a medida por estimativa (ou que era) grava também fator_orcamento, dp_no_inicio e dp_reais: a mesma
  -- instrução de baixo com as 3 colunas (a de baixo continua para as outras, byte a byte)
  if m.dias_fonte = 'orcamento' or m0.dias_fonte = 'orcamento'
     or coalesce(m0.fator_orcamento, m0.dp_no_inicio, m0.dp_reais) is not null then
    update public.agenda_medidas_os
       set classe_bem = m.classe_bem, classe_sistema = m.classe_sistema, concluida_em = m.concluida_em,
           entregue_em = m.entregue_em, dias_no_inicio = m.dias_no_inicio, dias_fonte = m.dias_fonte,
           meios_planejados = m.meios_planejados, meios_cumpridos = m.meios_cumpridos,
           meios_fora_do_plano = m.meios_fora_do_plano, meios_sem_registro = m.meios_sem_registro,
           diarias_ligadas = m.diarias_ligadas, so_o_dono = m.so_o_dono, mo = m.mo, fator = m.fator, valida = m.valida,
           motivo = m.motivo, prometido_primeiro_ate = m.prometido_primeiro_ate, atraso_cliente_du = m.atraso_cliente_du,
           avisos_enviados = m.avisos_enviados, aviso_faixa_ate = m.aviso_faixa_ate, aviso_estouro_du = m.aviso_estouro_du,
           fator_orcamento = m.fator_orcamento, dp_no_inicio = m.dp_no_inicio, dp_reais = m.dp_reais,
           -- (7e P2, R7.5-1) as 12 colunas da margem, nos 2 update (esquecer um faz a medida andar de versão a cada rodada)
           pm_reais = m.pm_reais, pm_estimados = m.pm_estimados, estimativa_origem = m.estimativa_origem, razao_estimativa = m.razao_estimativa,
           pm_plano_dono = m.pm_plano_dono, razao_dono = m.razao_dono, prazo_plano_du = m.prazo_plano_du, prazo_real_du = m.prazo_real_du,
           razao_prazo = m.razao_prazo, vies_marcado = m.vies_marcado, compra_pendente = m.compra_pendente, motivo_razao = m.motivo_razao,
           -- (7e: fim)
           medida_em = m.medida_em, versao = m0.versao + 1, historico = v_hist
     where service_order_id = p_os;
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', true, 'versao', m0.versao + 1,
                              -- (7e P2, §5.1) o que a medida da margem disse
                              'razao_estimativa', m.razao_estimativa, 'razao_prazo', m.razao_prazo, 'motivo_razao', m.motivo_razao,
                              -- (7e: fim)
                              'valida', m.valida, 'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
  end if;
  -- FASE 7: fim
  update public.agenda_medidas_os
     set classe_bem = m.classe_bem, classe_sistema = m.classe_sistema, concluida_em = m.concluida_em,
         entregue_em = m.entregue_em, dias_no_inicio = m.dias_no_inicio, dias_fonte = m.dias_fonte,
         meios_planejados = m.meios_planejados, meios_cumpridos = m.meios_cumpridos,
         meios_fora_do_plano = m.meios_fora_do_plano, meios_sem_registro = m.meios_sem_registro,
         diarias_ligadas = m.diarias_ligadas, so_o_dono = m.so_o_dono, mo = m.mo, fator = m.fator, valida = m.valida,
         motivo = m.motivo, prometido_primeiro_ate = m.prometido_primeiro_ate, atraso_cliente_du = m.atraso_cliente_du,
         avisos_enviados = m.avisos_enviados, aviso_faixa_ate = m.aviso_faixa_ate, aviso_estouro_du = m.aviso_estouro_du,
         -- FASE 7e: (7e P2, R7.5-1) as 12 colunas da margem, nos 2 update (esquecer um faz a medida andar de versão a cada rodada)
         pm_reais = m.pm_reais, pm_estimados = m.pm_estimados, estimativa_origem = m.estimativa_origem, razao_estimativa = m.razao_estimativa,
         pm_plano_dono = m.pm_plano_dono, razao_dono = m.razao_dono, prazo_plano_du = m.prazo_plano_du, prazo_real_du = m.prazo_real_du,
         razao_prazo = m.razao_prazo, vies_marcado = m.vies_marcado, compra_pendente = m.compra_pendente, motivo_razao = m.motivo_razao,
         -- FASE 7e: fim
         medida_em = m.medida_em, versao = m0.versao + 1, historico = v_hist
   where service_order_id = p_os;
  return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', true, 'versao', m0.versao + 1,
                            -- FASE 7e: (7e P2, §5.1) o que a medida da margem disse
                            'razao_estimativa', m.razao_estimativa, 'razao_prazo', m.razao_prazo, 'motivo_razao', m.motivo_razao,
                            -- FASE 7e: fim
                            'valida', m.valida, 'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
end;
$function$;

comment on function public.agenda_medir_os(uuid, date) is
  'Agenda de Produção (Fase 6): a medida da OS concluída (spec-fase6 §3.1, itens 5 e 6) em agenda_medidas_os — a classe, os dias ditos no início (senão a sugerida: não vale), os meios-dias planejados e os que aconteceram, as diárias ligadas, se é só do dono, a mão de obra, o fator (só a válida), o motivo da inválida, a 1ª promessa ao cliente contra a conclusão e o último aviso de atraso. Grava só quando muda (versao + 1 e o que mudou no histórico). A OS que voltou de concluída fica inválida (reaberta). Definer, sem grant a ninguém. CORREÇÃO FASE 6 (C1): (item 9) a conclusão é o check-out, senão o 1º instante em que a porta deixou a OS concluída (_agenda_concluida_em); sem nenhum dos dois, motivo sem_fim (não vale) e a data fica a já medida; (item 4) o fim da faixa do último aviso é o base.dados.faixa_ate_plano (sem a folga do aprendizado), quando a mensagem o tem. FASE 7 (7a P6, sem portão): a medida contra a estimativa do gestor (dias_fonte orcamento: os dias congelados ou os de _agenda_dias_no_inicio) não é dias_sugeridos — vale com os critérios de sempre; o fator dela fica à parte (fator := nulo; fator_orcamento := os meios-dias reais ÷ (dias × 2), só na válida), e o aprendizado do fator, que lê fator, continua só com os dias do dono; dp_no_inicio (o congelado, senão o do 4º passo) e dp_reais (as diárias ligadas + os meios-dias de turno do dono ÷ 2) só na medida por estimativa. O R$ por diária aprendido passa a contar a OS por estimativa válida com diarista. As outras medidas, byte a byte as de antes. FASE 7e (P2): as 12 colunas da margem (pm_reais sem o dono que vai junto, pm_estimados com estimativa_origem, razao_estimativa, pm_plano_dono e razao_dono, prazo_plano_du, prazo_real_du e razao_prazo, vies_marcado, compra_pendente, motivo_razao) nos 3 caminhos. motivo_razao tem a régua de R7.4: sem_inicio só sem check-in E sem meio-dia feito; sem_diaria só para quem tem perfil de diária no dia. A sugestão do caminho recalculada e das pessoas sai sob agenda.gestor = sombra, separada de v_sug, que alimenta as colunas da Fase 6. motivo, valida e fator da Fase 6 não mudam.';

-- ── 6. O gravador, o valor e os textos ───────────────────────────────────────────────────────────────
-- de 20261029100100_agenda_fase6_medicao.sql:581; md5 do corpo de antes 33db86b37bcee2396355e3f2809befed
create or replace function public._agenda_aprendizado_valor(p_item text, p_v numeric)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
           when p_v is null then null
           -- FASE 7e: (7e P2, §5.1) os itens da margem: sempre 2 casas no multiplicador (1,30×, 1,00×), inteiro no percentual e nos dias úteis
           when p_item in ('vies', 'promessa') then replace(to_char(round(p_v, 2), 'FM990.00'), '.', ',') || '×'
           when p_item = 'folga_semana' then round(p_v * 100)::text || '%'
           when p_item in ('tempo_compra', 'folga_compra', 'prazo_sem_fornecedor') then
             case when p_v = 1 then '1 dia útil' else public._agenda_num(p_v, 1) || ' dias úteis' end
           -- FASE 7e: fim
           when p_item = 'fator' then public._agenda_num(p_v, 2) || '×'
           when p_item = 'mo' then 'R$ ' || translate(to_char(round(p_v), 'FM999,999,990'), ',', '.')
           when p_item in ('capacidade_dono', 'carga', 'cliente_pontualidade') then round(p_v * 100)::text || '%'
           when p_item in ('fornecedor_atraso', 'fornecedor_prazo', 'aviso_folga') then
             case when p_v = 1 then '1 dia útil' else public._agenda_num(p_v, 1) || ' dias úteis' end
           when p_item = 'presenca' then case when p_v >= 1 then 'o dia todo' else 'abre e fecha' end
           else public._agenda_num(p_v, 2)
         end;
$function$;

comment on function public._agenda_aprendizado_valor(text, numeric) is
  'Agenda de Produção (Fase 6): um valor aprendido como o dono lê — fator "1,7×"; R$ por diária "R$ 690"; capacidade, carga e pontualidade "56%"; fornecedor e aviso "2 dias úteis"; presença "o dia todo" / "abre e fecha". FASE 7e (P2): vies e promessa com 2 casas (1,30×), folga_semana em % e os itens de dias em dias úteis.';

-- de 20261029100950_agenda_fase6_correcao_textos.sql:674; md5 do corpo de antes 234b2c02d243f376f9fd04df11308a5d
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
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe). FASE 6 (P4): a capacidade do dono (capacidade_dono) tem os textos da spec §6.2/§6.3 ("Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano …"; a taxa e a janela vêm do detalhe). FASE 6 (P5): a pontualidade com o cliente (cliente_pontualidade: só a linha do foco, "Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.") e a folga do aviso de atraso (aviso_folga: "a faixa com 2 dias úteis a mais"; 0 = a faixa do plano) têm os textos da spec §6.2/§6.3. FASE 6 (P6): a carga de cada pessoa pelo plano cumprido ("O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%)."; a pergunta "abaixo de 60% em 3 semanas seguidas (…). Recomendo marcar até 70% …") e os gatilhos de um planejador mais forte ("Gatilhos de um planejador mais forte: 0 de 4 (9 OS ativas, 4 pessoas)."; a pergunta "Há 4 semanas a agenda passa de 25 OS ativas e de 6 pessoas: …") têm os textos da spec §6.2/§6.3. Todos os itens com o texto da spec. CORREÇÃO FASE 6 (C2, textos 1 e 5): o fator em uso diz "uso 1,7× desde … para perguntar o que falta (os dias do plano continuam os que você disse)", e "é o mesmo que eu já usava" com o valor do padrão; em teste, com o medido igual ao padrão, sem o "hoje seria X, e vale X"; a pergunta do R$ por diária diz que inclui as OS em que o dono também trabalhou. FASE 7e (P2): os textos da spec §6.2/§6.3 (com R7.3) para os 6 itens da margem. Nunca perguntam. O desfeito usa volta (um passo só) e diz que a OS marcada guarda o valor.';

-- de 20261029100950_agenda_fase6_correcao_textos.sql:1117; md5 do corpo de antes 18c0d8b31b9e9ae8c757b19df1ecde27
create or replace function public._agenda_aprendizado_gravar(p_item text, p_chave text, p_nivel text, p_calculado numeric,
                                                             p_n integer, p_amostra jsonb, p_padrao numeric, p_detalhe jsonb,
                                                             p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_lista  text := public._agenda_aprendizado_da_lista(p_item);
  v_nmin   int;
  r0       public.agenda_aprendizado;
  r        public.agenda_aprendizado;
  v_efet   numeric;
  v_estado text;
  v_d      jsonb;
  v_ops    jsonb;
  v_txt    text;
  v_acao   uuid;
  v_perg   uuid;
  v_aberta boolean := false;
  v_motivo text;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
  -- FASE 7e: (7e P2, §5.1, R7.6) o ramo dos itens da margem: o modo CRU (o freio não entra aqui: soltar o freio recomeçaria do padrão), o passo e o novo em uso
  v_7e_modo  text := public._agenda_margem_modo_cru(p_item);
  v_7e_passo numeric;
  v_7e_novo  numeric;
  -- FASE 7e: fim
begin
  if p_item is null or p_chave is null or p_nivel is null or p_agora is null then
    raise exception 'Falta o item, a chave, o nível ou a hora.' using errcode = '22023';
  end if;
  v_nmin := case p_item
    when 'fator' then c.fator_n_min when 'mo' then c.mo_n_min when 'presenca' then c.presenca_n_min
    when 'fornecedor_atraso' then c.fornecedor_n_min when 'fornecedor_prazo' then c.fornecedor_n_min
    when 'capacidade_dono' then c.capacidade_semanas_min when 'cliente_pontualidade' then c.cliente_n_min
    when 'aviso_folga' then c.aviso_n_min when 'carga' then least(c.ppc_baixo_semanas, c.ppc_alto_semanas)
    when 'solver' then c.solver_semanas end;
  -- FASE 7e: (7e P2, §5.1) o mínimo e o passo de cada item da margem
  if v_7e_modo is not null then
    v_nmin := case p_item when 'vies' then c.vies_n_min when 'promessa' then c.promessa_n_min when 'folga_semana' then c.folga_semanas_min
                          when 'tempo_compra' then c.tempo_compra_n_min when 'folga_compra' then c.folga_compra_n_min
                          when 'prazo_sem_fornecedor' then c.prazo_sem_fornecedor_n_min end;
    v_7e_passo := case when p_item in ('vies', 'promessa') then c.fator_troca_max when p_item = 'folga_semana' then c.folga_semana_troca_max
                       when p_item in ('tempo_compra', 'folga_compra') then c.fornecedor_troca_max_du end;
  end if;
  -- FASE 7e: fim
  if v_nmin is null then
    raise exception 'Item de aprendizado desconhecido: %.', p_item using errcode = '22023';
  end if;

  -- A linha (nasce medindo) e a trava dela: duas rodadas não gravam a mesma chave ao mesmo tempo.
  insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, calculado_em)
  values (p_item, p_chave, p_nivel, p_padrao, v_nmin, p_agora)
  on conflict (item, chave) do nothing;
  select * into r0 from public.agenda_aprendizado where item = p_item and chave = p_chave for update;
  if r0.nivel <> p_nivel then
    raise exception 'A chave % de % é do nível %, não %.', p_chave, p_item, r0.nivel, p_nivel using errcode = '22023';
  end if;
  if r0.pergunta_id is not null then
    v_aberta := exists (select 1 from public.agenda_perguntas q where q.id = r0.pergunta_id and q.estado = 'aberta');
  end if;
  r := r0;
  r.padrao := p_padrao;
  r.calculado := p_calculado;
  r.n := coalesce(p_n, 0);
  r.n_min := v_nmin;
  r.amostra := case when jsonb_typeof(p_amostra) = 'array'
                    then coalesce((select jsonb_agg(x order by o) from jsonb_array_elements(p_amostra) with ordinality t(x, o)
                                    where o <= 60), '[]'::jsonb)
                    else '[]'::jsonb end;
  r.detalhe := case when jsonb_typeof(p_detalhe) = 'object' then p_detalhe else '{}'::jsonb end;
  r.calculado_em := p_agora;
  -- O que vale hoje: o em uso (também guardado na pergunta e na trava), senão o padrão.
  v_efet := coalesce(r0.em_uso, p_padrao);

  if p_calculado is null or r.n < v_nmin then
    -- 1. poucas medidas
    v_estado := 'medindo';
  elsif v_lista is null or c.modo_aprendizado <> 'ligado' or not (v_lista = any (c.aprendizado_ligados)) then
    -- 2. em teste (o modo, a lista; a pontualidade com o cliente é só medida)
    v_estado := 'sombra';
  elsif r0.estado = 'travado' and v_hoje <= r0.travado_ate
        and (p_calculado = r0.travado_valor
             or public._agenda_aprendizado_troca_cabe(p_item, p_nivel, r0.travado_valor, p_calculado)) then
    -- 3. o dono travou e o medido não andou mais que o limite (o item que sempre pergunta: o medido não mudou)
    v_estado := 'travado';
  elsif p_calculado = v_efet then
    -- 4. igual ao que vale
    v_estado := 'em_uso';
  elsif public._agenda_aprendizado_troca_cabe(p_item, p_nivel, v_efet, p_calculado) then
    -- 5. troca pequena: entra sozinha, com *desfaz*
    v_estado := 'em_uso';
  else
    -- 6. troca grande: pergunta
    v_estado := 'pergunta';
  end if;
  -- FASE 7e: (7e P2, §5.1) os itens da margem andam por passo e nunca perguntam: a cadeia de cima só deu medindo ou sombra para eles (v_lista nula). Aqui, de medindo não sai. Em teste continua: o modo geral, o interruptor, a promessa
  -- (AG7-32: nunca em uso), a folga da compra (R7.5-16: sem leitor nesta etapa, o texto "dou 2 dias a mais" seria mentira), o que é só medida e a chave dono: sem vies_corrige_dono. Dentro da trava, se o medido não andou mais que um passo; senão, em uso.
  if v_7e_modo is not null and v_estado <> 'medindo' then
    if c.modo_aprendizado <> 'ligado' or v_7e_modo <> 'ligado' or p_item in ('promessa', 'folga_compra', 'prazo_sem_fornecedor')
       or (p_item = 'vies' and p_chave like 'dono:%' and not c.vies_corrige_dono) then
      v_estado := 'sombra';
    elsif r0.estado = 'travado' and v_hoje <= r0.travado_ate and abs(p_calculado - r0.travado_valor) <= v_7e_passo then
      v_estado := 'travado';
    else
      v_estado := 'em_uso';
    end if;
  end if;
  -- FASE 7e: fim

  r.estado := v_estado;
  if v_estado in ('medindo', 'sombra') then
    r.em_uso := null;
    r.em_uso_desde := null;
  elsif v_estado = 'em_uso' then
    r.em_uso := p_calculado;
    r.em_uso_desde := case when r0.em_uso = p_calculado and r0.estado = 'em_uso' then coalesce(r0.em_uso_desde, p_agora)
                           else p_agora end;
  else
    -- pergunta e trava: o que vale continua valendo (nulo = o padrão)
    r.em_uso := case when r0.estado in ('em_uso', 'pergunta', 'travado') then r0.em_uso end;
  end if;
  -- FASE 7e: (7e P2, §5.1) o em uso anda um passo por rodada (o calculado guarda o alvo), arredondado como o item: 2 casas no multiplicador e no percentual, inteiro nos dias (para cima na folga da compra)
  if v_7e_modo is not null and v_estado = 'em_uso' then
    v_7e_novo := v_efet + greatest(-v_7e_passo, least(v_7e_passo, p_calculado - v_efet));
    r.em_uso := case p_item when 'folga_compra' then ceil(v_7e_novo) when 'tempo_compra' then round(v_7e_novo) else round(v_7e_novo, 2) end;
    r.em_uso_desde := case when r0.em_uso = r.em_uso and r0.estado = 'em_uso' then coalesce(r0.em_uso_desde, p_agora) else p_agora end;
  end if;
  -- FASE 7e: fim
  if v_estado <> 'travado' then
    r.travado_ate := null;
    r.travado_valor := null;
  end if;

  v_d := jsonb_build_object('chave', p_chave, 'calculado', p_calculado, 'em_uso', r.em_uso, 'efetivo', v_efet,
                            'padrao', p_padrao, 'n', r.n, 'n_min', v_nmin,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', c.aprender_trava_dias, 'detalhe', r.detalhe);
  -- FASE 7e: (7e P2, §6.2) o que os textos da margem precisam e o gravador tem (o texto é IMMUTABLE e não lê a linha da config)
  if v_7e_modo is not null then
    v_d := v_d || jsonb_build_object('passo', v_7e_passo, 'carga_max', c.carga_max, 'folga_material_du', c.folga_material_du, 'fator_percentil', c.fator_percentil);
  end if;
  -- FASE 7e: fim

  -- FASE 7e: (7e P2, §5.1) se havia pergunta aberta da chave da margem (não deveria), ela sai: o item nunca pergunta
  if v_7e_modo is not null and v_aberta then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'O aprendizado agora anda aos poucos, sem pergunta.'
     where id = r0.pergunta_id and estado = 'aberta';
    v_aberta := false;
  end if;
  -- FASE 7e: fim
  -- A pergunta aberta desta chave: fica (a mesma troca), ou sai (o medido voltou, caiu abaixo do mínimo, saiu do uso, mudou).
  if v_aberta and not (v_estado = 'pergunta' and r0.estado = 'pergunta' and r0.calculado is not distinct from p_calculado) then
    v_motivo := case
      when v_estado = 'medindo' then 'Menos medidas que o mínimo: volto a medir.'
      when v_estado = 'sombra' then 'Esse aprendizado saiu do uso (em teste).'
      when v_estado = 'pergunta' then 'O medido mudou: perguntei de novo com o número novo.'
      else 'O medido voltou para perto do que vale.' end;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = v_motivo
     where id = r0.pergunta_id and estado = 'aberta';
    v_aberta := false;
  end if;

  -- FASE 7e: (7e P2, §5.1, R7.5-19) a ação do item da margem: o em uso que muda é o do passo, o alvo fica em depois.alvo e o *desfaz* volta um passo. Nenhum item da margem passa pelo ramo da pergunta
  if v_7e_modo is not null and v_estado = 'em_uso' and r.em_uso is distinct from v_efet then
    insert into public.agenda_acoes (dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate, criada_em)
    values (v_hoje, true, 'vigia', 'aprendizado',
            left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'acao', v_d), 400), 400),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', r0.em_uso, 'valor', v_efet, 'estado', r0.estado),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', r.em_uso, 'n', r.n, 'alvo', p_calculado),
            p_agora + c.desfazer_validade, p_agora)
    returning id into v_acao;
    r.acao_id := v_acao;
  elsif v_7e_modo is null then
  -- FASE 7e: fim
  if v_estado = 'em_uso' and r.em_uso is distinct from v_efet then
    -- 5. a ação no "o que mudou" das 17:30, com *desfaz aprendizado*
    insert into public.agenda_acoes (dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate, criada_em)
    values (v_hoje, true, 'vigia', 'aprendizado',
            left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'acao', v_d), 400), 400),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', r0.em_uso, 'valor', v_efet,
                               'estado', r0.estado),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', p_calculado, 'n', r.n),
            p_agora + c.desfazer_validade, p_agora)
    returning id into v_acao;
    r.acao_id := v_acao;
  elsif v_estado = 'pergunta' and not v_aberta then
    -- 6. a pergunta crítica: 1 uso o medido (recomendo); 2 fico com o de agora; 3 volto ao padrão (só quando o que vale não é
    -- o padrão e o medido também não; a carga e o planejador só têm 1 e 2)
    v_ops := jsonb_build_array(
      jsonb_build_object('n', 1, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao1', v_d),
                         'efeito', jsonb_build_object('em_uso', p_calculado)),
      jsonb_build_object('n', 2, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao2', v_d),
                         'efeito', jsonb_build_object('travar', p_calculado)));
    if p_item not in ('carga', 'solver') and v_efet is distinct from p_padrao and p_calculado is distinct from p_padrao then
      v_ops := v_ops || jsonb_build_array(jsonb_build_object('n', 3, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao3', v_d),
                                                             'efeito', jsonb_build_object('em_uso', null)));
    end if;
    select public._agenda_aprendizado_texto(p_item, 'pergunta', v_d) || ' '
           || string_agg(format('%s) %s%s', o ->> 'n', o ->> 'texto',
                                case when o ->> 'n' = '1' and o ->> 'texto' !~ 'recomend' then ' (recomendo)' else '' end),
                         '; ' order by (o ->> 'n')::int) || '.'
      into v_txt
      from jsonb_array_elements(v_ops) o;
    -- CORREÇÃO FASE 6: (C2) texto 5: na troca grande do R$ por diária a opção 1 não leva o "(recomendo)" — a conta inclui a mão
    -- de obra das OS em que o dono também trabalhou, e a decisão é dele, sem empurrão. A recomendação da pergunta continua 1
    -- (o CHECK critica_tem_opcoes pede uma); só o texto muda.
    if p_item = 'mo' then
      v_txt := replace(v_txt, format('1) %s (recomendo)', v_ops -> 0 ->> 'texto'), format('1) %s', v_ops -> 0 ->> 'texto'));
    end if;
    -- CORREÇÃO FASE 6: fim
    insert into public.agenda_perguntas (tipo, chave, dia, texto, opcoes, recomendacao, modo, criada_em)
    values ('aprendizado', left(format('aprendizado:%s:%s', p_item, p_chave), 200), v_hoje,
            left(public._agenda_corta(v_txt, 600), 600), v_ops, 1, 'ligado', p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing
    returning id into v_perg;
    if v_perg is null then
      select q.id into v_perg from public.agenda_perguntas q
       where q.chave = left(format('aprendizado:%s:%s', p_item, p_chave), 200) and q.modo = 'ligado' and q.estado = 'aberta';
    end if;
    r.pergunta_id := v_perg;
  end if;
  -- FASE 7e: (7e P2) fecha o desvio do item da margem
  end if;
  -- FASE 7e: fim

  r.texto := left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'foco_' || v_estado, v_d), 400), 400);

  -- O histórico: em uso, estado e calculado, quando mudam (os 20 mais novos).
  foreach k in array array['em_uso', 'estado', 'calculado'] loop
    if to_jsonb(r0) -> k is distinct from to_jsonb(r) -> k then
      v_antes := v_antes || jsonb_build_object(k, to_jsonb(r0) -> k);
      v_depois := v_depois || jsonb_build_object(k, to_jsonb(r) -> k);
    end if;
  end loop;
  v_hist := r0.historico;
  if v_antes <> '{}'::jsonb then
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', v_antes, 'depois', v_depois));
    if jsonb_array_length(v_hist) > 20 then
      select jsonb_agg(x order by o) into v_hist
        from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
    end if;
  end if;

  update public.agenda_aprendizado
     set padrao = r.padrao, calculado = r.calculado, em_uso = r.em_uso, n = r.n, n_min = r.n_min, amostra = r.amostra,
         detalhe = r.detalhe, estado = r.estado, texto = r.texto, calculado_em = r.calculado_em, em_uso_desde = r.em_uso_desde,
         travado_ate = r.travado_ate, travado_valor = r.travado_valor, pergunta_id = r.pergunta_id, acao_id = r.acao_id,
         historico = v_hist
   where id = r0.id;

  return jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'estado', v_estado, 'estado_antes', r0.estado,
                            'calculado', p_calculado, 'em_uso', r.em_uso, 'vale', coalesce(r.em_uso, p_padrao),
                            'acao_id', v_acao, 'pergunta_id', case when v_estado = 'pergunta' then r.pergunta_id end,
                            'texto', r.texto);
end;
$function$;

comment on function public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz) is
  'Agenda de Produção (Fase 6): o gravador único de agenda_aprendizado (spec-fase6 §5.1) — o upsert de (item, chave) e o estado, nesta ordem: 1 n < n_min → medindo; 2 modo fora de ligado, item fora de aprendizado_ligados ou só de medida → sombra; 3 travado e dentro da trava (a data e o limite de troca a partir do valor recusado) → fica; 4 o medido = o que vale → em uso; 5 troca dentro do limite (§3.2) → em uso + a ação aprendizado (origem vigia, desfazível por desfazer_validade); 6 troca grande → pergunta crítica aprendizado (chave aprendizado:<item>:<chave>, uma aberta por chave). Toda mudança de em uso, estado e calculado vai ao histórico. Definer, sem grant a ninguém. CORREÇÃO FASE 6 (C2, texto 5): na pergunta do R$ por diária a opção 1 sai sem o "(recomendo)" (a recomendação da pergunta continua 1, pelo CHECK). FASE 7e (P2): o ramo por passo dos itens da margem (vies, folga_semana, promessa, tempo_compra, folga_compra, prazo_sem_fornecedor): medindo; sombra (modo geral, interruptor CRU, promessa, folga_compra, só medida, chave dono: sem vies_corrige_dono); travado (na trava, medido a até um passo); em uso, com o em uso andando até o passo por rodada e o calculado como alvo. Nunca pergunta. A ação guarda antes.em_uso e depois.alvo. Os itens da Fase 6, como antes.';

-- ── 7. A obrigação do P1 (R7.5-1): pm_reais e compra_pendente passam a NOT NULL com DEFAULT ─────────
-- Antes do NOT NULL, as linhas que já existem precisam de valor. O gatilho agenda_medidas_os_so_muda só deixa mudar com versão nova, e aqui não há o que versionar (a coluna acabou de nascer): desliga dentro da transação e
-- religa (um erro no meio desfaz tudo, o gatilho volta sozinho). A rodada seguinte mede de verdade (e aí sim, com versão + 1).
do $$
begin
  if exists (select 1 from public.agenda_medidas_os where pm_reais is null or compra_pendente is null) then
    alter table public.agenda_medidas_os disable trigger agenda_medidas_os_so_muda;
    update public.agenda_medidas_os
       set pm_reais = coalesce(pm_reais, 0), compra_pendente = coalesce(compra_pendente, false)
     where pm_reais is null or compra_pendente is null;
    alter table public.agenda_medidas_os enable trigger agenda_medidas_os_so_muda;
  end if;
end
$$;

alter table public.agenda_medidas_os
  alter column pm_reais set default 0,
  alter column compra_pendente set default false,
  alter column pm_reais set not null,
  alter column compra_pendente set not null;

comment on column public.agenda_medidas_os.pm_reais is 'Agenda de Produção (Fase 7e): os pessoa-meios que aconteceram, por (dia, turno, pessoa): cumprido 1, parcial meio; mais as diárias ligadas em dia em que aquela pessoa não está no plano da OS. O dono que vai junto não conta (R7.4). NOT NULL desde o P2: agenda_medir_os grava em todo caminho.';
comment on column public.agenda_medidas_os.compra_pendente is 'Agenda de Produção (Fase 7e): a OS tinha compra por fazer quando ganhou o 1º compromisso (existe medida de compra com marcada_em e comprado_em nulo ou depois dela). NOT NULL desde o P2.';
comment on column public.agenda_medidas_compra.motivo is 'Por que a linha não vale: nao_critica, sem_compra, sem_chegada, balcao_inferido, nao_marcada, comprada_antes_de_marcar ou reaberta. compra_antes é a previsão original dita antes da compra: a linha vale, mas fica fora do atraso do fornecedor (d6).';

-- ── 8. Portas ────────────────────────────────────────────────────────────────────────────────────────
-- Internas da rodada e das contas dela: sem grant a ninguém, nem service_role. As recriadas mantêm a porta (create or replace não mexe na ACL): repetidas aqui as de escrita, para a migration valer sozinha.
revoke all on function
  public._agenda_margem_tipo_os(uuid),
  public._agenda_margem_dp_bruto(uuid, jsonb),
  public._agenda_margem_dono_e_pessoa(uuid),
  public._agenda_material_critico(uuid),
  public._agenda_aprender_congelar_marcacao(date),
  public.agenda_medir_compra(uuid, date),
  public._agenda_aprender_medir_compras(date),
  public._agenda_aprender_congelar(date),
  public.agenda_medir_os(uuid, date),
  public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz)
  from public, anon, authenticated, service_role;

-- As que os leitores invoker (os_prontidao, agenda_meios_da_os, os_duracao_sugerida, nos P3 e P6) chamam como o usuário logado. O molde é o de _agenda_margem_modo (P1, desvio 2). Nunca anon.
revoke all on function
  public._agenda_margem_em_uso(text, text),
  public._agenda_vies_da_os(uuid),
  public._agenda_tempo_interno_compra(uuid)
  from public, anon;
grant execute on function
  public._agenda_margem_em_uso(text, text),
  public._agenda_vies_da_os(uuid),
  public._agenda_tempo_interno_compra(uuid)
  to authenticated, service_role;
