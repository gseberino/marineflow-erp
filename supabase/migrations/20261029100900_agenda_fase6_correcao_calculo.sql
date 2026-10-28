-- Agenda de Produção, Fase 6 ("Aprendizado"), correção C1: os cálculos e o motor (2 funções novas; 18 recriadas; 2 colunas,
-- 1 CHECK novo, 1 CHECK ampliado e 1 índice).
-- Fonte: scratchpad agenda-pesquisa/decisoes-correcao-fase6.md (seção C1), revisao-fase6-correcao.md (itens 1, 2, 3, 4, 5, 7,
-- 8, 9, 11, 13, 14 e 15) e revisao-fase6-regressao.md (B2, B3, B4 e B5). Depende de 20261029100000 .. 20261029100800 (a Fase 6
-- inteira); a C2 (20261029100950) copia daqui o que recriar de novo. A de dado 20261029101000 continua a última.
--
-- ═══ DDL — OK NOMEADO ═══ (2 colunas novas em os_planejamento, nulas, com 1 CHECK; a lista fechada de
-- agenda_medidas_os.motivo + sem_fim; 1 índice em agenda_vigia_rodadas; nenhum parâmetro novo)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/c1f6/montar-migration.mjs (as partes escritas à mão
-- parte-0-cabeca, parte-1-novas e parte-9-portas + as 18 recriadas, cada uma copiada da definição MAIS NOVA, conferida com grep
-- a cada montagem). Fora dos blocos "-- CORREÇÃO FASE 6: (C1) … -- CORREÇÃO FASE 6: fim" nenhuma linha das recriadas muda.
-- Existe para revisão e espera o OK do dono.
--
-- O QUE MUDA (cada item é um bloco marcado "(C1) item N" ou "(C1) regressão BN" nas funções):
--   · item 1 (Alta) — o publicado não cai pelo aprendizado. os_prontidao devolve material.inicio_mat_dito (o início pelo
--     material pelo dia DITO, sem o atraso medido do fornecedor), só quando a data provável muda o início; _agenda_violacoes
--     julga o que JÁ está publicado (o dia confirmado pelo cliente também) por ele. A data provável só encaixa o que é novo.
--   · item 2 — sem contagem dupla. A previsão da nota (nfe) não ganha o atraso do fornecedor (a nota já é "saída + prazo");
--     o atraso mede só as entregas com a 1ª previsão de fornecedor, OC ou Pix (a da nota fica para o prazo medido).
--   · item 3 — a presença guardada na 1ª publicação. agenda_aplicar grava os_planejamento.presenca_publicada/_motivo (só
--     quando nulas) com a presença aprendida com que a OS entra no plano; com alocação vigente, _agenda_presenca_aprendida
--     devolve a guardada (guardada: true); sem alocação nenhuma, a aprendida de agora. O cartão (os_plano_da_os) diz "(pelo
--     que medi quando planejei: …)".
--   · item 4 — a folga do aviso medida contra o PLANO. O registro do aviso de atraso (_agenda_cliente_registrar) com a folga
--     em uso guarda base.dados.faixa_ate_plano (o fim da faixa sem a folga); a medição (agenda_medir_os) mede o estouro
--     contra ele, com coalesce para as mensagens de antes. A capacidade do dono tinha o MESMO vaivém (provado no teste: com
--     0,56 em uso e o dono fazendo tudo o que o motor marcou, a rodada seguinte ia a 0,80): a semana planejada desde que a
--     capacidade entrou em uso pesa com ela (taxa × a carga que o motor usou), a de antes com carga_max. DESVIO da decisão
--     ("medir contra o esperado da semana, o você disse"): o esperado da semana conta todos os meios-dias livres dele, e a
--     semana com pouca OS (o motor marcou 2 de 10) leria como capacidade de 20% — com a fixture daria 0,30 (o piso 0,40).
--     A carga que o motor usou é o que a taxa mede de verdade; sem nada em uso, a conta é a de antes, byte a byte.
--   · item 5 (DONO decide; a recomendação aplicada, fácil de voltar) — a capacidade conta só a falta dele: o cancelado a
--     pedido do dono (cancelada_motivo 'dono') e o parcial com motivo fora de capacidade_motivos (chuva, material, cliente…)
--     saem da conta. Para voltar: tirar a linha "and not (… cancelada_motivo = 'dono')" e o "when … parcial … then 0" dos
--     dois blocks "(C1) item 5" de _agenda_aprender_capacidade (pendencias-do-dono.md).
--   · item 7 — a presença geral pede mais de uma classe: a chave todas só tem calculado com as OS da amostra de pelo menos 2
--     sistemas e mais OS que a classe fina mais larga; senão, medindo (sem a pergunta "conto com você o dia todo por padrão?"
--     tirada das mesmas OS que já entraram sozinhas na classe).
--   · item 8 — o fornecedor inativo: _agenda_fornecedor_da_medida(id) (nova; o principal pela regra do grupo de
--     _agenda_prazo_do_fornecedor); _agenda_aprender_fornecedor mede por ela e a prontidão lê o atraso por ela.
--   · item 9 — a OS sem check-out: _agenda_concluida_em(os) (nova) = o check-out, senão o 1º instante em que a porta deixou a
--     OS concluída (agenda_acoes, status_depois completed, executada, não desfeita); sem nenhum dos dois, a medida não vale
--     (motivo novo sem_fim; a lista fechada de agenda_medidas_os.motivo ganha o valor) e a data fica a já medida — tocar a OS
--     não move a conclusão. O passo do cliente deixa a sem_fim fora (não há atraso a medir). Conferido antes: a bancada não tem
--     audit_log; em produção (só SELECT, 28/10, sql/c1f6_item9_historico_status.sql) as 21 OS concluídas TÊM check-out (0 sem;
--     o "12 de 21" da revisão não vale mais) e 19 delas têm a conclusão no audit_log. O audit_log ficou de fora: é escrito pelo
--     navegador (qualquer login grava) e não existe na bancada; a porta (agenda_acoes) é do servidor.
--   · item 11 — um arredondamento só: o P80 em dias úteis da folga do aviso e do "atraso chega a" da pontualidade passa ao
--     teto, como o atraso do fornecedor (P80 2,2 → 3).
--   · item 13 — a revisão da carga e o planejador mais forte rodam no dia_do_plano ou depois dele na mesma semana ISO,
--     enquanto não houve nesta semana rodada semanal com o modo e a lista de agora (a quinta que não rodou; o dono que liga a
--     revisão na sexta). DESVIO da decisão ("quando não houve rodada semanal nesta semana"): o "depois do dia do plano" (senão
--     a revisão passaria a rodar na segunda de toda semana) e o "com o modo e a lista de agora" (o 1º item da revisão: ligar na
--     sexta não espera a quinta seguinte).
--   · item 14 — a reserva por teto da OS que precisa do dono (abre, fecha ou o turno dele), com a capacidade dele em uso abaixo
--     de carga_max, diz "não coube na sua parte da semana (56%)" (_agenda_carga_da_pessoa), e não "na carga de 80%". A reserva
--     por teto é só dos diaristas (_agenda_so_diaristas): o dono nunca está nas alocações dela, por isso o "precisa do dono"
--     vem do molde da OS (abre, fecha, dt_m, dt_t). agenda_propor (a maior função) copiada inteira; um bloco só, no laço dos
--     itens.
--   · item 15 — a vigia e a medição contam os meios-dias do mesmo jeito: com o fator aprendido em uso (ligado e fator na
--     lista), _agenda_vigia_estouro soma as diárias ligadas fora do plano (meios_fora_do_plano, a conta da medida). Fora disso a
--     vigia é a da Fase 2 (o fator é o padrão e a conta é a de sempre). Ficam diferentes, de propósito: o sem_registro (a vigia
--     conta como feito, para perguntar cedo; a medida o recusa) e o combinado (a vigia usa os dias de agora; a medida, os do
--     início).
--   · regressão B2 — a ordem das travas: agenda_decidir (na pergunta do aprendizado), _agenda_aprendizado_decidir e
--     _agenda_desfazer_aprendizado tomam pg_advisory_xact_lock(hashtext('agenda_aprender')) antes do 1º for update (a de
--     agenda_decidir é a que vale: é ela que trava a linha da pergunta primeiro).
--   · regressão B3 — a vigia do estouro lê o fator de campo só com o aprendizado ligado e fator na lista (o portão do P5); o
--     erro da cadeia nova vira o padrão e vai a app_error_logs (agenda / vigia:estouro), sem derrubar o passo 11.
--   · regressão B4 — o índice agenda_vigia_rodadas_rotina_dia (rotina, p_hoje, p_agora desc): o "já rodou hoje?", o "já houve
--     a semanal?" e a última rodada da saúde sem varrer a tabela (o EXPLAIN vai no pós-deploy).
--   · regressão B5 — a medição olha de novo só a OS concluída na janela, a medida que voltou de concluída (uma vez) e a medida
--     que mudou depois de medida (service_orders.updated_at > medida_em); não toda OS medida, todo dia, para sempre.
--
-- AS RECRIADAS (de onde cada uma vem; quem recriar de novo copia DESTA migration):
--   os_prontidao (de 20261029100300), _agenda_violacoes (de 20261026100300), _agenda_aprender_fornecedor (de 20261029100300),
--   _agenda_presenca_aprendida (de 20261029100200), agenda_aplicar (de 20261025100200), os_plano_da_os (de 20261029100800),
--   _agenda_cliente_registrar (de 20261028100800), agenda_medir_os (de 20261029100100), _agenda_aprender_medir (de
--   20261029100100), _agenda_aprender_capacidade (de 20261029100400), _agenda_aprender_presenca (de 20261029100200),
--   _agenda_aprender_cliente (de 20261029100500), agenda_aprender (de 20261029100600), agenda_propor (de 20261025100200),
--   _agenda_vigia_estouro (de 20261029100200), _agenda_aprendizado_decidir (de 20261029100600), _agenda_desfazer_aprendizado
--   (de 20261029100600), agenda_decidir (de 20261029100600).
--   Duas trocam um trecho de antes por um bloco novo sem apagar o de antes (para a cópia fora dos blocos ser a fonte): na
--   os_prontidao, o bloco da data provável da Fase 6 (P3) tem as 3 chaves dele tiradas logo depois ("- array[…]") e o novo
--   vem em seguida; em _agenda_aprender_fornecedor e _agenda_aprender_medir o laço de antes fica, mas parado (um "continue"
--   no começo; um "join … where false"), e o novo vem antes dele; em _agenda_vigia_estouro o bloco novo termina com
--   "continue" (o bloco da Fase 6 e a pergunta de antes não rodam mais). Não tirar: é a conferência da cópia.
--
-- O QUE NÃO MUDA: com o aprendizado desligado ou em teste, ou ligado sem o item na lista, tudo o que o motor, a vigia, a
-- prontidão, o cartão e a rodada do cliente leem sai como antes (os testes byte a byte de antes continuam: F3z, D6, C7, O5g);
-- muda só a medição (item 9 e B5: a OS sem conclusão e a que não mudou) e a rodada semanal (item 13). Nenhuma mensagem nova a
-- terceiros (o montador recusa escrita em fila de mensagem e em agenda_config nos blocos); nenhum parâmetro novo; nenhum texto
-- novo ao cliente. Textos novos ao dono: "(pelo que medi quando planejei: …)" no cartão e "não coube na sua parte da semana
-- (56%)" na reserva (pendencias-do-dono.md, "textos que mudaram, só para saber").
--
-- ORDEM DE LIGAR: depois de 20261029100800; antes de 20261029100950 (a C2) e de 20261029101000 (a de dado). Aplicar sozinha não
-- muda nada para ninguém enquanto o aprendizado está desligado (fora a medição, que já roda sempre, e o índice).
--
-- PROVA (depois de aplicar): os blocos "C1" de supabase/tests/agenda_fase6_fornecedor.sql, _os.sql, _cliente.sql, _dono.sql,
-- _medicao.sql, _rodada.sql e _pos_deploy.sql (a fixture-fase6 só na bancada). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100900_agenda_fase6_correcao_calculo.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100900', 'agenda_fase6_correcao_calculo');"
--
-- DESFAZER:
--   1. as funções: reaplicar, em ordem, as definições de 20261025100200 (agenda_aplicar, agenda_propor), 20261026100300
--      (_agenda_violacoes), 20261028100800 (_agenda_cliente_registrar), 20261029100100 (agenda_medir_os,
--      _agenda_aprender_medir), 20261029100200 (_agenda_presenca_aprendida, _agenda_aprender_presenca, _agenda_vigia_estouro),
--      20261029100300 (os_prontidao, _agenda_aprender_fornecedor), 20261029100400 (_agenda_aprender_capacidade),
--      20261029100500 (_agenda_aprender_cliente), 20261029100600 (agenda_aprender, _agenda_aprendizado_decidir,
--      _agenda_desfazer_aprendizado, agenda_decidir) e 20261029100800 (os_plano_da_os). As 2 novas podem ficar (ninguém de antes
--      as chama). Se a C2 (20261029100950) já estiver aplicada, desfazer a C2 primeiro.
--   2. o índice: drop index if exists public.agenda_vigia_rodadas_rotina_dia;
--   3. as colunas (só depois do passo 1; o que nelas estiver se perde, e é só o que a agenda guardou):
--      alter table public.os_planejamento drop constraint if exists presenca_publicada_coerente,
--        drop column if exists presenca_publicada, drop column if exists presenca_publicada_motivo;
--   4. a lista de agenda_medidas_os.motivo: só se "select count(*) from public.agenda_medidas_os where motivo = 'sem_fim'" der
--      0 (a medida não se apaga); então
--      alter table public.agenda_medidas_os drop constraint agenda_medidas_os_motivo_check, add constraint
--        agenda_medidas_os_motivo_check check (motivo in ('sem_inicio', 'sem_dias_no_inicio', 'dias_sugeridos', 'sem_plano',
--        'conferencia_incompleta', 'sem_diaria', 'reaberta'));
--      senão, deixar: o valor a mais não muda nada (as funções de antes nunca o gravam).
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (o da lista: só quando ainda não tem sem_fim), create index if
-- not exists, create or replace function, revoke/grant.

-- ── 1. As colunas, o CHECK e o índice novos (DDL) ─────────────────────────────────────────────────────────
-- (item 3) A presença do dono com que a OS foi publicada pela 1ª vez: agenda_aplicar grava só quando é nula (a da presença
-- aprendida em uso naquele instante); com alocação vigente, _agenda_presenca_aprendida devolve esta, e não a aprendida de
-- agora (o publicado não muda pelo aprendizado, e o resto da OS continua planejado como começou).
alter table public.os_planejamento
  add column if not exists presenca_publicada        text,
  add column if not exists presenca_publicada_motivo text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.os_planejamento'::regclass and conname = 'presenca_publicada_coerente') then
    alter table public.os_planejamento add constraint presenca_publicada_coerente
      check ((presenca_publicada is null or presenca_publicada in ('abre_e_fecha', 'sempre', 'nunca'))
             and (presenca_publicada is not null or presenca_publicada_motivo is null)
             and char_length(presenca_publicada_motivo) <= 200);
  end if;
end
$$;

comment on column public.os_planejamento.presenca_publicada is
  'Agenda de Produção (Fase 6, correção C1, item 3): a presença do dono aprendida com que a OS foi publicada pela 1ª vez (agenda_aplicar grava só quando é nula). Com alocação vigente da OS, é ela que vale no lugar da aprendida de agora (_agenda_presenca_aprendida); nula = a regra de sempre.';
comment on column public.os_planejamento.presenca_publicada_motivo is
  'Agenda de Produção (Fase 6, correção C1, item 3): o motivo da presença guardada ("você foi a 3 de 4 OS de energia em motorhome"), o que o cartão diz em "(pelo que medi quando planejei: …)".';

-- (item 9) A OS concluída sem check-out e sem o instante da conclusão na porta: a medida não vale (sem_fim). A lista fechada
-- de agenda_medidas_os.motivo ganha o valor.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.agenda_medidas_os'::regclass and conname = 'agenda_medidas_os_motivo_check'
                    and pg_get_constraintdef(oid) like '%sem_fim%') then
    alter table public.agenda_medidas_os drop constraint if exists agenda_medidas_os_motivo_check;
    alter table public.agenda_medidas_os add constraint agenda_medidas_os_motivo_check
      check (motivo in ('sem_inicio', 'sem_dias_no_inicio', 'dias_sugeridos', 'sem_plano', 'conferencia_incompleta',
                        'sem_diaria', 'reaberta', 'sem_fim'));
  end if;
end
$$;

-- (regressão B4) O "já rodou hoje?" da rodada do aprendizado (32 tiques por dia depois das 16:00), o "já houve a semanal
-- nesta semana?" (item 13) e a última rodada da saúde: por rotina e dia, sem varrer a tabela inteira.
create index if not exists agenda_vigia_rodadas_rotina_dia on public.agenda_vigia_rodadas (rotina, p_hoje, p_agora desc);

-- ── 2. As funções novas ─────────────────────────────────────────────────────────────────────────────────
-- (item 8) O fornecedor pelo qual a agenda mede e lê o atraso e o prazo: o cadastro que o dono tirou de uso (inativo) vale
-- pelo que ficou — o principal pela regra do grupo de _agenda_prazo_do_fornecedor (o único ativo com o mesmo nome de grupo,
-- senão o principal dos ativos: principal_id); o ativo, o sem grupo e o que o dono disse, por ele mesmo.
create or replace function public._agenda_fornecedor_da_medida(p_forn uuid)
 returns uuid
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when p_forn is null then null
              when coalesce((select s.active from public.suppliers s where s.id = p_forn), true) then p_forn
              else coalesce((public._agenda_prazo_do_fornecedor(p_forn) ->> 'principal_id')::uuid, p_forn) end;
$function$;

comment on function public._agenda_fornecedor_da_medida(uuid) is
  'Agenda de Produção (Fase 6, correção C1, item 8): a chave do fornecedor no aprendizado — o cadastro inativo vale pelo principal do grupo (o principal_id de _agenda_prazo_do_fornecedor, a mesma regra do prazo); o ativo, o sem grupo e o nulo, por ele mesmo. É por ela que _agenda_aprender_fornecedor mede (fornecedor_atraso e fornecedor_prazo) e que a prontidão lê o atraso. Leitura invoker.';

-- (item 9) O dia em que a OS concluiu: o check-out; sem ele, o 1º instante em que a porta a deixou concluída (agenda_acoes com
-- status_depois completed, executada e não desfeita). Nulo = sem como saber (a medida não vale: sem_fim). A última edição da
-- OS (updated_at) nunca é a conclusão: faturar, pagar ou entregar a moveria.
create or replace function public._agenda_concluida_em(p_os uuid)
 returns date
 language sql
 stable
 set search_path to 'public'
as $function$
  select (coalesce(so.check_out_at,
                   (select min(a.criada_em) from public.agenda_acoes a
                     where a.service_order_id = so.id and a.status_depois = 'completed' and a.executada
                       and a.desfeita_em is null)) at time zone 'America/Sao_Paulo')::date
    from public.service_orders so
   where so.id = p_os;
$function$;

comment on function public._agenda_concluida_em(uuid) is
  'Agenda de Produção (Fase 6, correção C1, item 9): o dia (Brasília) em que a OS concluiu — o check-out, senão o 1º instante em que a porta a deixou concluída (agenda_acoes, status_depois completed, executada, não desfeita); nulo sem nenhum dos dois. agenda_medir_os a usa no lugar de coalesce(check_out_at, updated_at) e, sem ela, a medida não vale (sem_fim). Sem grant a ninguém.';

-- ── 3. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO FASE 6: (C1)") ─────
-- Fora dos blocos nenhuma linha muda (os testes de cópia conferem tirando os blocos "-- CORREÇÃO FASE 6:"). Quem recriar de
-- novo qualquer uma delas copia DESTA migration (a C2 também).
-- os_prontidao (de 20261029100300_agenda_fase6_fornecedor.sql)
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
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P2: a linha de OC recebida ligada a um item de texto livre da conta conta só nele, não de novo como item da OC que já chegou; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira. Fase 6 (P3): no item de nível B, enquanto o dia dito não chegou e com o atraso do fornecedor em uso (fornecedor_atraso: _agenda_aprendido), data = a data provável (o dia dito + o atraso; é ela que move o DPM, o início pelo material e o motor), data_dita = o dia dito (o fato) e data_texto "a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11"; atrasado e sem_data continuam pelo dia dito (a "chegou?"); C, A, D e E não mudam; sem atraso em uso, o item é o de antes. CORREÇÃO FASE 6 (C1): (item 1) material.inicio_mat_dito = o início pelo material pelo dia DITO (sem o atraso do fornecedor), só quando a data provável muda o início — _agenda_violacoes julga por ele o que já está publicado; (item 2) a previsão da nota (nfe) não ganha o atraso do fornecedor (já é saída + prazo); (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida: o inativo pelo principal). Sem atraso em uso, a saída é a de antes, byte a byte.';

-- _agenda_violacoes (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_violacoes(p_escopo uuid[], p_cart uuid[], p_semana boolean, p_info jsonb,
                                                    p_hoje date, p_cong date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ate   date;
  v_login uuid;
  v_res   jsonb;
  -- FASE 3 (C1): a falta da equipe (NOVO-agenda-27; quem replaneja pelo "não vou" ou pelo silêncio põe
  -- agenda.replano_da_falta = on na transação)
  v_falta boolean := coalesce(current_setting('agenda.replano_da_falta', true), '') = 'on';
  -- FASE 3 (C1): fim
begin
  select max(a.dia) into v_ate
    from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
     and (a.service_order_id = any (p_escopo) or (p_semana and not (a.service_order_id = any (p_cart))));
  if v_ate is null then
    return '[]'::jsonb;
  end if;
  select py.app_user_id into v_login from public.payees py where py.id = public._agenda_dono(null);

  with
  alvo as (
    select a.*, a.dia <= p_cong as congelado
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
       and (a.service_order_id = any (p_escopo) or (p_semana and not (a.service_order_id = any (p_cart))))
  ),
  cap as (select * from public.agenda_capacidade(p_hoje, v_ate, p_hoje)),
  av as (
    select a.*,
           case
             when not (a.service_order_id = any (p_cart)) then 'os_saiu'
             when so.status = 'awaiting_client' then 'cliente'
             when (p_info -> a.service_order_id::text -> 'pront' ->> 'estado') in ('concluida', 'fora_da_carteira') then 'os_saiu'
             -- a espera que o dono pôs ("deixa parada até sexta") só tira os dias DENTRO dela; o que vem depois fica
             when (p_info -> a.service_order_id::text -> 'pront' ->> 'estado') = 'congelada' and a.dia <= pl.congelada_ate then 'espera'
             when not py.active then 'pessoa'
             when a.presenca = 'turno' and k.situacao is distinct from 'livre' then 'pessoa'
             when a.presenca <> 'turno'
                  and (k.situacao is null or k.situacao in ('indisponivel', 'feriado', 'fim_de_semana') or not public.agenda_dia_util(a.dia)
                       or exists (select 1 from public.agenda_tasks t
                                   where t.kind = 'appointment' and v_login is not null and t.assignee_user_id = v_login
                                     and t.status not in ('cancelled', 'done') and t.scheduled_start_at is not null
                                     and tstzrange(t.scheduled_start_at, coalesce(t.scheduled_end_at, t.scheduled_start_at), '[]') && a.periodo))
               then 'pessoa'
             when a.fixado_por = 'dono' then null
             when coalesce(pl.bem_indisponivel @> a.dia, false) then 'cliente'
             -- CORREÇÃO FASE 6: (C1) item 1: o que JÁ está publicado é julgado pelo início pelo material do dia DITO
             -- (os_prontidao.material.inicio_mat_dito, que só existe quando a data provável do aprendizado muda o início): o
             -- dia que só cairia pela data provável fica (o publicado só muda com evento real; o confirmado pelo cliente
             -- também). Segue a regra de baixo sem o material: o "não antes de" do cliente.
             when a.tipo <> 'reserva'
                  and coalesce(p_info -> a.service_order_id::text -> 'pront' #>> '{material,estado}', '') not in ('atrasado', 'sem_previsao')
                  and a.dia < (p_info -> a.service_order_id::text -> 'pront' #>> '{material,inicio_mat}')::date
                  and a.dia >= (p_info -> a.service_order_id::text -> 'pront' #>> '{material,inicio_mat_dito}')::date
               then case when a.dia < pl.nao_antes_de then 'cliente' end
             -- CORREÇÃO FASE 6: fim
             when a.tipo <> 'reserva'
                  and ((p_info -> a.service_order_id::text -> 'pront' #>> '{material,estado}') in ('atrasado', 'sem_previsao')
                       or a.dia < (p_info -> a.service_order_id::text -> 'pront' #>> '{material,inicio_mat}')::date) then 'material'
             when a.tipo <> 'reserva' and a.dia < pl.nao_antes_de then 'cliente'
             when a.tipo = 'reserva' and a.reserva_de = 'condicionada' and a.condicao_ate < p_hoje
                  and (public._agenda_classe_da_os(p_info -> a.service_order_id::text -> 'pront',
                                                   p_info -> a.service_order_id::text -> 'meios', p_hoje) ->> 'classe')::int not in (1, 2)
               then 'condicao_vencida'
           end as por_que
      from alvo a
      join public.service_orders so on so.id = a.service_order_id
      join public.payees py on py.id = a.payee_id
      left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
      left join cap k on k.payee_id = a.payee_id and k.dia = a.dia and k.turno = a.turno
  ),
  violadas as (select * from av where av.por_que is not null),
  -- (a espera não replaneja o depois: os dias que caem depois dela ficam como estão, e o que faltar o motor completa
  -- depois do último dia marcado, quando a espera acabar)
  os_v as (select v.service_order_id, bool_or(v.tipo <> 'reserva') as comp from violadas v where v.por_que <> 'espera' group by 1),
  mesmo_meio as (
    select av.* from av
     where av.por_que is null and av.tipo <> 'reserva' and av.fixado_por is distinct from 'dono'
       and exists (select 1 from violadas v where v.service_order_id = av.service_order_id and v.dia = av.dia
                                             and v.turno = av.turno and v.tipo <> 'reserva')
  ),
  depois as (
    select av.* from av join os_v on os_v.service_order_id = av.service_order_id and os_v.comp
     where av.por_que is null and av.tipo <> 'reserva' and av.estado = 'publicada' and av.dia > p_cong
  ),
  -- FASE 3 (C1): a falta é evento real (decisões de 23/10: hoje e amanhã congelados SALVO evento real) — o que a OS tinha
  -- publicado depois de hoje e dentro do congelado (amanhã) sai junto, para os meios-dias que sobram voltarem num bloco só
  -- (sem isso o dia de amanhã ficava e o resto ia para depois: 2 interrupções). O desfazer do replano volta tudo.
  depois_da_falta as (
    select av.* from av join os_v on os_v.service_order_id = av.service_order_id and os_v.comp
     where v_falta and av.por_que is null and av.tipo <> 'reserva' and av.estado = 'publicada'
       and av.dia > p_hoje and av.dia <= p_cong
  ),
  -- FASE 3 (C1): fim
  tudo as (
    select v.id, v.service_order_id, v.por_que, true as violada, v.congelado, v.tipo, v.estado, v.fixado_por, v.reserva_de,
           v.payee_id, v.dia, v.turno, v.presenca from violadas v
    union
    select m.id, m.service_order_id, 'replanejado', false, m.congelado, m.tipo, m.estado, m.fixado_por, m.reserva_de,
           m.payee_id, m.dia, m.turno, m.presenca from mesmo_meio m
    union
    select d.id, d.service_order_id, 'replanejado', false, d.congelado, d.tipo, d.estado, d.fixado_por, d.reserva_de,
           d.payee_id, d.dia, d.turno, d.presenca from depois d
  -- FASE 3 (C1): o que a falta solta do congelado
    union
    select f.id, f.service_order_id, 'replanejado', false, f.congelado, f.tipo, f.estado, f.fixado_por, f.reserva_de,
           f.payee_id, f.dia, f.turno, f.presenca from depois_da_falta f
  -- FASE 3 (C1): fim
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'alocacao_id', t.id, 'os', t.service_order_id, 'motivo', t.por_que, 'violada', t.violada, 'congelado', t.congelado,
           'tipo', t.tipo, 'estado', t.estado, 'fixado_por', t.fixado_por, 'reserva_de', t.reserva_de,
           'payee_id', t.payee_id, 'dia', t.dia, 'turno', t.turno, 'presenca', t.presenca)
           order by t.service_order_id, t.dia, t.turno = 'tarde', t.payee_id, t.id), '[]'::jsonb)
    into v_res
    from tudo t;
  return v_res;
end;
$function$;

comment on function public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date) is
  'Agenda de Produção (Fase 2, P2; Fase 3, revisão C1): a etapa da estabilidade — cada alocação vigente de hoje em diante, sem resultado, das OS do escopo (e, na semana, das que saíram da carteira) que não pode mais acontecer: a OS saiu da carteira, está esperando o cliente ou concluída (os_saiu/cliente); o dia dentro da espera que o dono pôs (espera: só até congelada_ate, o depois fica); a pessoa não está mais livre ou a ponta do dono ficou ocupada por compromisso com hora (pessoa); o bem fora ou o "não antes de" (cliente); o material atrasado, sem previsão ou chegando depois do dia (material); a reserva condicionada vencida sem a condição (condicao_vencida). O fixado pelo dono só pelas três primeiras (a espera é dele também). Junto vão o resto do meio-dia quebrado e os meios-dias publicados da OS depois do congelado (replanejado); com agenda.replano_da_falta = on (a falta da equipe, NOVO-agenda-27), também os publicados de depois de hoje dentro do congelado. [{alocacao_id, os, motivo, violada, congelado, tipo, estado, fixado_por, reserva_de, payee_id, dia, turno, presenca}]. CORREÇÃO FASE 6 (C1, item 1): o material julga o que já está publicado pelo início do dia DITO (material.inicio_mat_dito da prontidão, quando a data provável do aprendizado o muda): o dia que só cairia pela data provável não sai (nem o confirmado pelo cliente).';

-- _agenda_aprender_fornecedor (de 20261029100300_agenda_fase6_fornecedor.sql)
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
  'Agenda de Produção (Fase 6, P3): o passo do fornecedor da rodada — (1) fornecedor_atraso por fornecedor: as entregas da janela (aprender_janela_dias; as linhas de os_material na mão com a 1ª previsão de fornecedor/OC/nota/Pix, agrupadas por fornecedor e nota, senão OC, senão linha: 3 linhas da mesma nota = 1 entrega; o fornecedor = o da linha, senão o da OC, senão o da nota; o atraso = o maior agenda_du_entre(previsao_original, chegou_em) das linhas, assinado), calculado = o P80 (fornecedor_percentil) arredondado para cima e nunca abaixo de 0, padrão 0, detalhe {nome, n, no_prazo, p50}; (2) fornecedor_prazo por fornecedor: as notas que chegaram (material_remessas, da saída à chegada), padrão = o prazo de hoje de _agenda_prazo_do_fornecedor (du_classe quando o medido já está em uso); o que o dono disse vem antes (só mede). Tudo pelo gravador (_agenda_aprendizado_gravar), nível fornecedor, chave = o id do fornecedor. O erro de um fornecedor vai a app_error_logs (agenda / aprender:fornecedor) e o passo segue. Nenhuma mensagem ao fornecedor. {chaves, estados, acoes, perguntas, erros}. Sem grant a ninguém. CORREÇÃO FASE 6 (C1): (item 2) o atraso mede só as entregas com a 1ª previsão de fornecedor, OC ou Pix (a da nota já é saída + prazo: fica só para fornecedor_prazo); (item 8) o fornecedor é o da medida (_agenda_fornecedor_da_medida: o cadastro inativo mede pelo principal), e as entregas e as notas se juntam por ele.';

-- _agenda_presenca_aprendida (de 20261029100200_agenda_fase6_os.sql)
create or replace function public._agenda_presenca_aprendida(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_lig boolean;
  v_cl  jsonb;
  v_ch  text;
  v_val numeric;
  a     public.agenda_aprendizado;
begin
  -- Só com o modo ligado e a presença na lista. Quem não lê a config (o técnico, pela RLS) fica com a regra de hoje.
  select true into v_lig
    from public.agenda_config c
   where c.id and c.modo_aprendizado = 'ligado'
     and public._agenda_aprendizado_da_lista('presenca') = any (c.aprendizado_ligados);
  if v_lig is null then
    return null;
  end if;
  -- CORREÇÃO FASE 6: (C1) item 3: com alocação vigente (publicada ou fixada), vale a presença com que a OS foi publicada pela
  -- 1ª vez (os_planejamento.presenca_publicada, que agenda_aplicar grava), e não a aprendida de agora: o resto da OS continua
  -- planejado como começou. Sem a guardada, a regra de hoje (abaixo). Sem alocação nenhuma, a aprendida de agora.
  if exists (select 1 from public.agenda_alocacoes x where x.service_order_id = p_os and x.estado in ('publicada', 'fixada')) then
    return (select jsonb_build_object('presenca', pl.presenca_publicada, 'motivo', pl.presenca_publicada_motivo,
                                      'fonte', 'aprendida', 'chave', null, 'guardada', true)
              from public.os_planejamento pl
             where pl.service_order_id = p_os and pl.presenca_publicada is not null);
  end if;
  -- CORREÇÃO FASE 6: fim
  -- O publicado não muda pelo aprendizado: a OS com alocação publicada ou fixada fica com a regra de hoje.
  if exists (select 1 from public.agenda_alocacoes x where x.service_order_id = p_os and x.estado in ('publicada', 'fixada')) then
    return null;
  end if;
  v_cl := public._agenda_classe_de_campo(p_os);
  if v_cl is null then
    return null;
  end if;
  -- A aprendida mais fina que existir: a da classe, senão a do sistema, senão a de todas (só depois do SIM do dono).
  foreach v_ch in array array[v_cl ->> 'chave', 'sistema:' || (v_cl ->> 'sistema'), 'todas'] loop
    v_val := public._agenda_aprendido('presenca', v_ch);
    exit when v_val is not null;
  end loop;
  if coalesce(v_val, 0) < 1 then
    return null;
  end if;
  select * into a from public.agenda_aprendizado x where x.item = 'presenca' and x.chave = v_ch;
  return jsonb_build_object('presenca', 'sempre',
                            'motivo', format('você foi a %s de %s %s', coalesce(a.detalhe ->> 'k', '0'), a.n,
                                             substr(public._agenda_classe_texto_do_nivel(v_ch), 4)),
                            'fonte', 'aprendida', 'chave', v_ch);
end;
$function$;

comment on function public._agenda_presenca_aprendida(uuid) is
  'Agenda de Produção (Fase 6, P2): a presença do dono aprendida para a OS — {presenca: sempre, motivo: "você foi a 3 de 4 OS de energia em motorhome", fonte: aprendida, chave} quando a aprendida mais fina (a chave fina da classe, senão a do sistema, senão a de todas) é o dia todo; nulo com modo_aprendizado fora de ligado, presenca fora da lista, a OS com alocação publicada ou fixada (o publicado não muda) ou nada aprendido. os_presenca_do_dono a usa depois do que o dono disse e da regra d05. CORREÇÃO FASE 6 (C1, item 3): com alocação publicada ou fixada, devolve a presença guardada na 1ª publicação (os_planejamento.presenca_publicada/_motivo, com guardada: true), e não a aprendida de agora; sem a guardada, nulo (a regra de hoje).';

-- agenda_aplicar (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public.agenda_aplicar(p_proposta uuid, p_os uuid[] default null, p_via text default 'motor',
                                                 p_autor uuid default null, p_pergunta uuid default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_p      public.agenda_propostas%rowtype;
  v_cong   date;
  v_sel    jsonb;
  v_viol   jsonb;
  v_nova   jsonb;
  v_via_p  text;
  v_origem text;
  v_va     bigint;
  v_vd     bigint;
  v_os     uuid;
  v_i      jsonb;
  v_a      jsonb;
  v_criadas uuid[];
  v_canc   uuid[];
  v_estado text;
  v_fix    text;
  v_acoes  uuid[] := '{}';
  v_acao   uuid;
  v_tipo   text;
  v_txt    text;
  v_linhas text[] := '{}';
  v_status text;
  v_porta  jsonb;
  v_desf   timestamptz;
  v_n_pub  int := 0;
  v_n_can  int := 0;
  v_motivo text;
  v_atraso int;
  v_tem    boolean;
  v_desfaz boolean := false;
  v_nomes  text[] := '{}';
  v_q      record;
  v_texto  text;
  -- CORREÇÃO FASE 6: (C1) item 3: a presença aprendida de cada OS publicada pela 1ª vez
  v_pa     jsonb;
  -- CORREÇÃO FASE 6: fim
begin
  if p_via is null or p_via not in ('motor', 'vigia', 'conferencia', 'dono', 'tela', 'aprovacao') then
    raise exception 'Caminho desconhecido para aplicar: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_p from public.agenda_propostas where id = p_proposta for update;
  if not found then
    raise exception 'Não encontrei esse plano.' using errcode = 'P0002';
  end if;
  if cf.modo_proposta <> 'ligado' or v_p.modo <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  if v_p.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', case v_p.estado
      when 'aplicada' then 'Esse plano já foi publicado.' when 'expirada' then 'Esse plano venceu. Peça de novo que eu monto outro.'
      when 'obsoleta' then 'Esse plano foi trocado por outro.' else 'Esse plano foi descartado.' end);
  end if;
  if p_agora > v_p.expira_em then
    update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou da validade' where id = p_proposta;
    delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
    return jsonb_build_object('ok', false, 'texto', 'Esse plano venceu. Peça de novo que eu monto outro.');
  end if;
  if v_p.versao_base <> cf.versao_plano then
    update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'a agenda mudou' where id = p_proposta;
    delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
    -- o motor refaz com os mesmos parâmetros e aplica a nova (uma vez só por chamada)
    if p_via = 'motor' and coalesce(current_setting('agenda.reaplicando', true), '') <> 'on' then
      v_nova := public.agenda_propor(v_p.escopo, (v_p.parametros ->> 'p_de')::date, (v_p.parametros ->> 'p_ate')::date,
                  case when v_p.parametros -> 'p_os' is null or jsonb_typeof(v_p.parametros -> 'p_os') <> 'array' then null
                       else array(select x::uuid from jsonb_array_elements_text(v_p.parametros -> 'p_os') x) end,
                  coalesce(v_p.parametros -> 'p_restricoes', '{}'::jsonb), true, v_p.criada_por, v_p.autor, p_hoje, p_agora);
      perform set_config('agenda.reaplicando', 'on', true);
      v_nova := public.agenda_aplicar((v_nova ->> 'proposta_id')::uuid, p_os, p_via, p_autor, p_pergunta, p_hoje, p_agora);
      perform set_config('agenda.reaplicando', 'off', true);
      return v_nova || jsonb_build_object('refeita', true);
    end if;
    return jsonb_build_object('ok', false, 'texto', 'A agenda mudou desde que eu montei: peça de novo que eu refaço.');
  end if;
  if p_pergunta is not null and not exists (select 1 from public.agenda_perguntas q
                                             where q.id = p_pergunta and q.critica and q.estado = 'respondida'
                                               and q.opcao_escolhida is not null) then
    return jsonb_build_object('ok', false, 'texto', 'Essa decisão ainda não foi respondida: nada foi feito.');
  end if;
  v_viol := public.agenda_validar(p_proposta, p_os, p_hoje, p_agora, p_pergunta);
  if jsonb_array_length(v_viol) > 0 then
    return jsonb_build_object('ok', false, 'violacoes', v_viol,
      'texto', 'Não mudei nada: ' || (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_viol) with ordinality t(e, o)));
  end if;

  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_sel := public._agenda_itens_escolhidos(v_p.itens, p_os, p_pergunta);
  v_via_p := case p_via when 'tela' then 'tela_agendar' else p_via end;
  v_origem := p_via;
  v_va := cf.versao_plano;

  -- 1. Sai o que sai (o fixado só com a chave, e só no item autorizado).
  for v_i in select e from jsonb_array_elements(v_sel) e where e ->> 'op' = 'cancelar' loop
    for v_a in select x from jsonb_array_elements(v_i -> 'alocacoes') x loop
      if v_a ->> 'estado' = 'fixada' then perform set_config('agenda.mexe_fixado', 'on', true); end if;
      update public.agenda_alocacoes
         set estado = 'cancelada', cancelada_motivo = v_i ->> 'motivo'
       where id = (v_a ->> 'alocacao_id')::uuid and estado in ('publicada', 'fixada');
      perform set_config('agenda.mexe_fixado', 'off', true);
      v_n_can := v_n_can + 1;
    end loop;
  end loop;
  -- CORREÇÃO FASE 6: (C1) item 3: a presença do dono com que cada OS entra no plano pela 1ª vez fica guardada
  -- (os_planejamento.presenca_publicada e _motivo, só quando nulas): é a que o motor usou para montar estes meios-dias. Lida
  -- ANTES de as alocações virarem publicadas (depois, _agenda_presenca_aprendida devolveria a guardada). Só a aprendida
  -- (a regra e o que o dono disse não precisam: continuam onde estão).
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_sel) e
               where e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' order by 1 loop
    v_pa := public._agenda_presenca_aprendida(v_os);
    if v_pa is not null and not coalesce((v_pa ->> 'guardada')::boolean, false) then
      insert into public.os_planejamento (service_order_id, presenca_publicada, presenca_publicada_motivo)
      values (v_os, v_pa ->> 'presenca', v_pa ->> 'motivo')
      on conflict (service_order_id) do update
        set presenca_publicada = excluded.presenca_publicada, presenca_publicada_motivo = excluded.presenca_publicada_motivo
        where public.os_planejamento.presenca_publicada is null;
    end if;
  end loop;
  -- CORREÇÃO FASE 6: fim
  -- 2. Entra o que entra: publicada; fixada no congelado (congelamento) e no pedido do dono (dono).
  for v_i in select e from jsonb_array_elements(v_sel) e where e ->> 'op' = 'criar' loop
    for v_a in select x from jsonb_array_elements(v_i -> 'alocacoes') x loop
      v_fix := case when (v_i ->> 'fixar_dono')::boolean and p_via in ('dono', 'tela', 'aprovacao') then 'dono'
                    when (v_a ->> 'dia')::date <= v_cong then 'congelamento' end;
      v_estado := case when v_fix is null then 'publicada' else 'fixada' end;
      update public.agenda_alocacoes
         set estado = v_estado, fixado_por = v_fix
       where id = (v_a ->> 'alocacao_id')::uuid and proposta_id = p_proposta and estado = 'proposta';
      if not found then
        raise exception 'agenda_aplicar: a alocação % da proposta sumiu.', v_a ->> 'alocacao_id';
      end if;
      v_n_pub := v_n_pub + 1;
    end loop;
  end loop;
  -- o que a proposta trazia e não foi escolhido sai (nunca vigorou)
  delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
  v_vd := (public._agenda_cfg()).versao_plano;

  -- 3. Por OS tocada: o status pela porta, o espelho das datas, a duração aceita e a ação (com o desfazer).
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_sel) e order by 1 loop
    v_criadas := array(select (x ->> 'alocacao_id')::uuid
                         from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar');
    v_canc := array(select (x ->> 'alocacao_id')::uuid
                      from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                     where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar');
    select so.status into v_status from public.service_orders so where so.id = v_os;
    v_tem := public._agenda_os_tem_dia(v_os, p_hoje);
    v_porta := null;
    if v_tem and v_status in ('open', 'approved', 'awaiting_parts', 'awaiting_client')
       and exists (select 1 from jsonb_array_elements(v_sel) e
                    where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva') then
      v_porta := public.os_transicionar_status(v_os, 'scheduled', v_via_p, null, p_autor, null, p_hoje, p_agora);
    elsif not v_tem and v_status = 'scheduled' then
      v_motivo := (select e ->> 'motivo' from jsonb_array_elements(v_sel) e
                    where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' order by e ->> 'motivo' = 'material' desc limit 1);
      v_porta := public.os_transicionar_status(v_os, case when v_motivo = 'material' then 'awaiting_parts' else 'approved' end,
                   case when p_via in ('motor', 'vigia') then p_via else 'dono' end, null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
    -- a duração só sugerida que o dono pediu para marcar fica aceita
    if p_via in ('dono', 'tela', 'aprovacao') then
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_por)
      select v_os, (e ->> 'dias')::numeric, 'aceita', p_agora, p_autor
        from jsonb_array_elements(v_sel) e
       where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' and e ->> 'fonte' = 'sugerida'
         and (e ->> 'dias') is not null
       limit 1
      on conflict (service_order_id) do update
        set dias = excluded.dias, estimativa_fonte = 'aceita', estimativa_em = excluded.estimativa_em,
            atualizado_por = excluded.atualizado_por, atualizado_em = now()
        where public.os_planejamento.dias is null;
    end if;

    v_tipo := case
      when v_p.escopo = 'semana' and cardinality(v_criadas) > 0 then 'publicar'
      when cardinality(v_criadas) > 0 and cardinality(v_canc) > 0
           and not exists (select 1 from jsonb_array_elements(v_sel) e
                            where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'promovida') then 'promover_reserva'
      when cardinality(v_criadas) > 0 and cardinality(v_canc) > 0 then 'mover'
      when cardinality(v_criadas) > 0 then 'criar'
      when not exists (select 1 from jsonb_array_elements(v_sel) e
                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'condicao_vencida') then 'soltar_reserva'
      else 'cancelar' end;
    v_motivo := (select string_agg(distinct e ->> 'motivo', ', ') from jsonb_array_elements(v_sel) e
                  where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar');
    v_atraso := (select max((e ->> 'atraso_du')::int) from jsonb_array_elements(v_sel) e
                  where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar');
    v_txt := case
      when v_tipo = 'mover' then
        format('%s: de %s para %s%s.', public._agenda_rotulo_da_os(v_os),
               public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                                where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar')),
               public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                                where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
               coalesce(' — ' || (select regexp_replace(e ->> 'texto', '^.* — ', '') from jsonb_array_elements(v_sel) e
                                   where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and (e ->> 'violada')::boolean limit 1), '')
               -- o dia pedido pelo dono antes de o material estar garantido: o aviso vai junto
               || coalesce(' — mas ' || (select e ->> 'aviso_material' from jsonb_array_elements(v_sel) e
                                          where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'aviso_material' is not null
                                          limit 1), ''))
      else (select string_agg(rtrim(e ->> 'texto', '.'), '; ' order by e ->> 'op' = 'cancelar', e ->> 'de')
              from jsonb_array_elements(v_sel) e where (e ->> 'os')::uuid = v_os) || '.' end;
    v_txt := regexp_replace(v_txt, '\.\.$', '.');
    v_desf := case when p_via in ('tela', 'aprovacao') then null
                   else least(p_agora + cf.desfazer_validade,
                              coalesce((select min(lower(a.periodo)) from public.agenda_alocacoes a where a.id = any (v_criadas)),
                                       p_agora + cf.desfazer_validade)) end;
    if v_desf is not null then
      v_desfaz := true;
      v_nomes := v_nomes || coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                        join public.clients cl on cl.id = so.client_id where so.id = v_os), '');
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, pergunta_id,
                                     critica, versao_antes, versao_depois, alocacoes_criadas, alocacoes_canceladas,
                                     status_antes, status_depois, atraso_du, antes, depois, texto, motivo, autor, desfazivel_ate)
    values (clock_timestamp(), p_hoje, true, v_origem, v_tipo, v_os, array[v_os], p_proposta, p_pergunta,
            p_pergunta is not null, v_va, v_vd, v_criadas, v_canc,
            v_status, (select so.status from public.service_orders so where so.id = v_os), case when v_atraso > 0 then v_atraso end,
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar'),
                               'fim', (select min(e ->> 'fim_antes') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
                               'fim', (select max(e ->> 'fim_depois') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
                               'porta', v_porta),
            left(v_txt, 400), left(v_motivo, 200), p_autor, v_desf)
    returning id into v_acao;
    update public.agenda_alocacoes set acao_id = v_acao where id = any (v_criadas);
    v_acoes := v_acoes || v_acao;
    v_linhas := v_linhas || v_txt;
  end loop;

  update public.agenda_propostas
     set estado = 'aplicada', decidida_em = p_agora,
         decidida_via = case p_via when 'tela' then 'tela' when 'aprovacao' then 'aprovacao' when 'dono' then null else 'motor' end,
         decidida_por = p_autor,
         itens = (select coalesce(jsonb_agg(case when exists (select 1 from jsonb_array_elements(v_sel) s where s = i)
                                                 then i || '{"aplicado": true}'::jsonb else i end order by k), '[]'::jsonb)
                    from jsonb_array_elements(v_p.itens) with ordinality t(i, k))
   where id = p_proposta;

  v_texto := case
    when cardinality(v_linhas) = 0 then 'Nada a mudar na agenda.'
    when v_p.escopo = 'semana' then format('Publiquei a %s: %s',
                                            lower(left(coalesce(v_p.textos ->> 'titulo', 'Semana'), 1))
                                            || substr(coalesce(v_p.textos ->> 'titulo', 'Semana'), 2),
                                            array_to_string(v_linhas, ' '))
    else 'Mudei: ' || array_to_string(v_linhas, ' ') end
    || case when not v_desfaz then ''
            when v_p.escopo = 'semana' then ' *desfaz semana* volta como estava.'
            when cardinality(v_nomes) = 1 then format(' *desfaz %s* volta como estava.', v_nomes[1])
            else ' *desfaz* e o nome volta como estava.' end;
  return jsonb_build_object('ok', true, 'texto', v_texto, 'acoes', to_jsonb(v_acoes), 'publicadas', v_n_pub, 'canceladas', v_n_can,
                            'fora', v_p.fora, 'proposta_id', p_proposta);
end;
$function$;

comment on function public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): aplica uma proposta, só com modo_proposta ligado (fora dele: "ainda está em teste", nada muda). Trava o plano; proposta fechada, vencida (expirada) ou de outra versão do plano (obsoleta; com p_via motor, refaz com os mesmos parâmetros e aplica a nova, uma vez) não aplica. agenda_validar não vazia = recusa com a lista. Itens: os das OS de p_os (todas, sem lista), sem os críticos — esses só com p_pergunta respondida (e então toda ação sai critica = true com pergunta_id). Cancelar → cancelada (o fixado com agenda.mexe_fixado); criar → publicada, fixada no congelado (congelamento) e no pedido do dono pela tela, aprovação ou *grava* (dono); o que não foi escolhido é apagado. Por OS: a porta (agendada quando tem dia; de volta quando ficou sem nenhum, aguardando peças se foi o material), o espelho das datas, a duração só sugerida que o dono pediu fica aceita, e uma linha em agenda_acoes (publicar/criar/mover/cancelar/promover_reserva/soltar_reserva) com antes/depois, a frase e o desfazer (desfazer_validade, até o 1º meio-dia começar; não na tela nem na aprovação). Vias: motor, vigia, conferencia, dono, tela, aprovacao. CORREÇÃO FASE 6 (C1, item 3): antes de publicar, guarda em os_planejamento.presenca_publicada/_motivo (só quando nulas) a presença aprendida com que cada OS entra no plano pela 1ª vez.';

-- os_plano_da_os (de 20261029100800_agenda_fase6_leituras.sql)
create or replace function public.os_plano_da_os(p_os uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  so      record;
  p       jsonb;
  pl      public.os_planejamento%rowtype;
  v_pres  jsonb;
  v_fim   date;
  v_prec  date;
  v_folga int;
  v_dono  uuid := public._agenda_dono(null);
  -- FASE 6: (P8) a linha do que as OS parecidas levam (agenda_fator_de_campo) e a presença do dono com a aprendida
  v_campo text;
  v_pd    jsonb;
  -- FASE 6: fim
begin
  if p_os is null or p_hoje is null then
    raise exception 'os_plano_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
  end if;
  select s.id, s.service_order_number as numero, s.status, s.check_out_at, s.delivered_at into so
    from public.service_orders s where s.id = p_os;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;
  p := public.os_prontidao(p_os, p_hoje);
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;
  v_pres := p -> 'presenca_dono';
  v_fim  := (p #>> '{plano,fim_publicado}')::date;
  v_prec := pl.precisa_ate;
  v_folga := case when v_fim is not null and v_prec is not null then public.agenda_du_entre(v_fim, v_prec) end;
  -- FASE 6: (P8) (spec-fase6 §5.8) duracao.campo: a linha do fator de campo da classe desta OS ("Em teste: as OS de energia
  -- em motorhome levam até 1,7× o combinado (7 OS); …") — só com o aprendizado fora de desligado e na OS que ainda vai ser
  -- feita (a concluída, a faturada e a cancelada não têm o que perguntar). O 42501 de quem não vê o aprendizado vira nulo.
  if (public._agenda_cfg()).modo_aprendizado <> 'desligado' and so.status not in ('completed', 'invoiced', 'cancelled') then
    begin
      v_campo := public.agenda_fator_de_campo(p_os, p_hoje) ->> 'texto';
    exception when insufficient_privilege then
      v_campo := null;
    end;
  end if;
  -- presenca_dono com a aprendida (os_presenca_do_dono, fonte aprendida): o texto diz de onde veio — o de antes diria
  -- "(você disse)". A chave presenca_dono abaixo (a de antes) fica, e esta, que vem depois no mesmo objeto, vale; sem a
  -- aprendida, o texto é o de sempre.
  v_pd := jsonb_build_object(
    'valor', v_pres ->> 'presenca', 'pela_regra', coalesce(v_pres ->> 'fonte', 'regra') = 'regra',
    'aprendida', case when v_pres ->> 'fonte' = 'aprendida' then v_pres ->> 'motivo' end,
    'texto', case v_pres ->> 'presenca' when 'abre_e_fecha' then 'Você abre e fecha'
                                        when 'sempre' then 'Você fica o tempo todo'
                                        when 'nunca' then 'Você não precisa ir'
                                        else 'Sem regra' end
             || case when v_pres ->> 'fonte' = 'aprendida' then ' (pelo que medi: ' || (v_pres ->> 'motivo') || ')'
                     when coalesce(v_pres ->> 'fonte', 'regra') <> 'regra' then ' (você disse)'
                     when coalesce(v_pres ->> 'motivo', 'padrão') = 'padrão' then ' (pela regra)'
                     else ' (pela regra: ' || (v_pres ->> 'motivo') || ')' end);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C1) item 3: a presença guardada na 1ª publicação diz que é o que a agenda mediu quando planejou
  if coalesce((v_pres ->> 'guardada')::boolean, false) then
    v_pd := v_pd || jsonb_build_object('texto', replace(v_pd ->> 'texto', ' (pelo que medi: ', ' (pelo que medi quando planejei: '));
  end if;
  -- CORREÇÃO FASE 6: fim

  return jsonb_build_object(
    -- FASE 5: o bloco "Cliente" do cartão (o que foi dito, a confirmação, as mensagens desta OS e o que espera você;
    -- _agenda_cliente_da_os). null sem o cliente.
    'cliente', public._agenda_cliente_da_os(p_os, p_hoje),
    -- FASE 5: fim
    'os', so.id, 'numero', so.numero, 'status', so.status, 'estado', p ->> 'estado_texto',
    'marcos', public.agenda_marcos_da_os(p_os, p_hoje),
    'pode_entregar', so.status = 'completed' and so.delivered_at is null,
    'duracao', jsonb_build_object(
      -- FASE 6: (P8) a linha do fator de campo (nula em desligado e na OS concluída)
      'campo', v_campo,
      -- FASE 6: fim
      'dias', p #> '{duracao,dias}', 'fonte', p #>> '{duracao,fonte}',
      'fonte_texto', case p #>> '{duracao,fonte}' when 'dono' then 'você disse' when 'aceita' then 'você aceitou a minha estimativa'
                                                  else 'estimativa minha' end,
      'faixa', jsonb_build_object('otimista', p #> '{duracao,dias_otimista}', 'realista', p #> '{duracao,dias_realista}'),
      'faixa_texto', case when p #>> '{duracao,dias_otimista}' is not null
                          then 'faixa ' || public._agenda_faixa_dias((p #>> '{duracao,dias_otimista}')::numeric,
                                                                    (p #>> '{duracao,dias_realista}')::numeric) end,
      'texto', p #>> '{duracao,texto}'),
    'presenca_dono', jsonb_build_object(
      'valor', v_pres ->> 'presenca', 'pela_regra', coalesce(v_pres ->> 'fonte', 'regra') = 'regra',
      'texto', case v_pres ->> 'presenca' when 'abre_e_fecha' then 'Você abre e fecha'
                                          when 'sempre' then 'Você fica o tempo todo'
                                          when 'nunca' then 'Você não precisa ir'
                                          else 'Sem regra' end
               || case when coalesce(v_pres ->> 'fonte', 'regra') <> 'regra' then ' (você disse)'
                       when coalesce(v_pres ->> 'motivo', 'padrão') = 'padrão' then ' (pela regra)'
                       else ' (pela regra: ' || (v_pres ->> 'motivo') || ')' end),
    -- FASE 6: (P8) a presença com a aprendida (a última chave igual do objeto vale: substitui a de cima)
    'presenca_dono', v_pd,
    -- FASE 6: fim
    'material', jsonb_build_object(
      'estado', p #>> '{material,estado}',
      'itens', coalesce((select jsonb_agg(jsonb_build_object(
                  'descricao', i ->> 'descricao', 'nivel', i ->> 'nivel',
                  'nivel_texto', case i ->> 'nivel' when 'A' then 'na mão'
                                                    when 'B' then 'previsão do fornecedor'
                                                    when 'C' then 'previsão sua'
                                                    when 'D' then 'sem previsão firme'
                                                    else 'a comprar, sem prazo' end,
                  'situacao', i ->> 'situacao', 'previsao', i ->> 'data_texto', 'trecho', i ->> 'trecho',
                  'critico', coalesce((i ->> 'critico')::boolean, true), 'fornecedor', i ->> 'fornecedor')
                  order by o)
                  from jsonb_array_elements(coalesce(p #> '{material,itens}', '[]'::jsonb)) with ordinality t(i, o)), '[]'::jsonb)),
    'janela', jsonb_build_object(
      'bem_indisponivel', (select r ->> 'texto' from jsonb_array_elements(coalesce(p -> 'restricoes', '[]'::jsonb)) r
                            where r ->> 'tipo' = 'bem' limit 1),
      'nao_antes_de', pl.nao_antes_de, 'motivo', pl.nao_antes_motivo, 'precisa_ate', v_prec,
      'nao_antes_texto', case when pl.nao_antes_de is not null
                              then format('não antes de %s: %s', public._dia_curto(pl.nao_antes_de), pl.nao_antes_motivo) end,
      'precisa_ate_texto', case when v_prec is not null then 'o cliente precisa até ' || public._dia_curto(v_prec) end),
    'prometido_planejado', jsonb_build_object(
      'precisa_ate', v_prec, 'fim_publicado', v_fim, 'folga_du', v_folga,
      'texto', case
        when v_fim is not null and v_prec is not null and v_folga = 0
          then format('O plano termina %s, o dia em que o cliente precisa.', public._dia_curto(v_fim))
        when v_fim is not null and v_prec is not null and v_folga > 0
          then format('O plano termina %s; o cliente precisa até %s (%s de folga).', public._dia_curto(v_fim),
                      public._dia_curto(v_prec), public._agenda_plural(v_folga, 'dia útil', 'dias úteis'))
        when v_fim is not null and v_prec is not null
          then format('O plano termina %s, %s depois do que o cliente precisa (%s).', public._dia_curto(v_fim),
                      public._agenda_plural(-v_folga, 'dia útil', 'dias úteis'), public._dia_curto(v_prec))
        when v_fim is not null then format('O plano termina %s; o cliente não deu data.', public._dia_curto(v_fim))
        when v_prec is not null then format('O cliente precisa até %s; ainda não há plano.', public._dia_curto(v_prec))
        end),
    'planejado_realizado', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', d.dia, 'rotulo', public._agenda_maiuscula(public._dia_curto(d.dia)),
               'pessoas_texto', nullif(public._agenda_pessoas_do_dia(d.pessoas), ''),
               'dia_texto', case when coalesce(d.dias_total, 1) > 1 and d.dia_n is not null
                                 then format('dia %s de %s', d.dia_n, d.dias_total) end,
               'meios', r.meios, 'resultado', r.resultado,
               'resultado_texto', case r.resultado when 'cumprido' then 'feito' when 'parcial' then 'feito em parte'
                                                   when 'sem_registro' then 'sem registro'
                                                   when 'nao_cumprido' then 'não aconteceu'
                                                   else case when d.dia < p_hoje then 'sem conferência' else 'previsto' end end,
               'motivo_texto', public._agenda_motivo_texto(r.motivo),
               'diaria', case when r.diaristas = 0 then null
                              when r.diaristas = r.com_diaria then 'lançada'
                              when d.dia <= p_hoje then 'a confirmar' end)
             order by d.dia)
        from public.v_agenda_dia d
        cross join lateral (
          select count(distinct (a.payee_id, a.turno)) filter (where a.presenca = 'turno')::int as meios,
                 case when bool_and(a.resultado is null) then null
                      when bool_or(a.resultado = 'cumprido') then 'cumprido'
                      when bool_or(a.resultado = 'parcial') then 'parcial'
                      when bool_or(a.resultado = 'sem_registro') then 'sem_registro'
                      else 'nao_cumprido' end as resultado,
                 min(a.motivo) filter (where a.resultado in ('parcial', 'nao_cumprido')) as motivo,
                 count(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono)::int as diaristas,
                 count(distinct a.payee_id) filter (
                   where a.payee_id is distinct from v_dono
                     and (a.work_shift_id is not null
                          or exists (select 1 from public.work_shifts w join public.work_profiles wp on wp.id = w.work_profile_id
                                      where wp.payee_id = a.payee_id and w.data = a.dia and w.tipo = 'diaria'
                                        and coalesce(w.fracao, 0) > 0)))::int as com_diaria
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.dia = d.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') r
       where d.service_order_id = p_os and not d.reserva), '[]'::jsonb),
    'intervencoes', coalesce((
      select jsonb_agg(jsonb_build_object('dia', i.dia,
               'texto', format('%s: você %s (no plano: %s)', public._agenda_maiuscula(public._dia_curto(i.dia)),
                               case i.dita when 'manha' then 'foi de manhã' when 'tarde' then 'foi à tarde'
                                           when 'dia' then 'ficou o dia todo' else 'passou lá' end,
                               case i.prevista when 'nenhuma' then 'nada' when 'abertura' then 'abrir'
                                               when 'fechamento' then 'fechar' when 'abre_e_fecha' then 'abrir e fechar'
                                               else 'o turno' end))
             order by i.dia, i.criado_em)
        from public.agenda_intervencoes_do_dono i where i.service_order_id = p_os), '[]'::jsonb));
end;
$function$;

comment on function public.os_plano_da_os(uuid, date) is
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 6 (P8): duracao.campo = a linha do fator de campo da classe da OS (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).") — nula com modo_aprendizado desligado e na OS concluída, faturada ou cancelada; presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em motorhome"; nulo sem ela), e o texto "Você fica o tempo todo (pelo que medi: …)". CORREÇÃO FASE 6 (C1, item 3): com a presença guardada na 1ª publicação, o texto diz "(pelo que medi quando planejei: …)".';

-- _agenda_cliente_registrar (de 20261028100800_agenda_fase5_correcao_rodada.sql)
create or replace function public._agenda_cliente_registrar(p_tipo text, p_variante text, p_os uuid, p_dia_alvo date,
                                                            p_dados jsonb, p_alvo timestamptz, p_valida_ate timestamptz,
                                                            p_origem text, p_critica text default null,
                                                            p_agora timestamptz default now(), p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor: o que sai até o próximo entra na fila agora
  v_hoje  date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_dados jsonb := coalesce(p_dados, '{}'::jsonb) - 'primeira' - 'envio' - 'chave' - 'prometido_tipo';
  x       jsonb;
  v_cli   uuid;
  v_modo  text;
  v_chave text;
  v_id    uuid := gen_random_uuid();
  v_ja    uuid;
  v_enviar timestamptz;
  v_valida timestamptz;
  v_prim  boolean;
  v_var   text := nullif(btrim(coalesce(p_variante, '')), '');
  v_txt   text;
  v_proib text;
  v_prom  text;
  v_aprov text;
  v_estado text := 'registrada';
  v_recusa text;
  v_perg  uuid;
  v_base  jsonb;
  v_r     jsonb;
  v_acao  uuid;
  v_aut   uuid;
  -- CORREÇÃO FASE 5: (item 12) a hora do meio-dia da saudação ("Bom dia" antes, "Boa tarde" depois: é o português, não
  -- um parâmetro da agenda nem o fim do turno da manhã)
  c_meio_dia_h constant int := 12;
  -- CORREÇÃO FASE 5: fim
  -- CORREÇÃO FASE 6: (C1) item 4: a folga do aviso em uso (dias úteis)
  v_folga int;
  -- CORREÇÃO FASE 6: fim
begin
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  if p_origem is null or p_origem not in ('rodada', 'dono', 'botao') then
    raise exception 'A mensagem ao cliente vem da rodada, do dono ou do botão (veio %).', coalesce(p_origem, 'nada') using errcode = '22023';
  end if;
  if p_critica is not null and p_critica not in ('segundo_atraso', 'atraso_longo', 'passou', 'teto') then
    raise exception 'Motivo de aviso crítico desconhecido: %.', p_critica using errcode = '22023';
  end if;
  if p_alvo is null then
    raise exception 'A mensagem ao cliente veio sem a hora.' using errcode = '22023';
  end if;
  select so.client_id into v_cli from public.service_orders so where so.id = p_os;
  if v_cli is null then
    raise exception 'A mensagem ao cliente veio sem a OS (ou a OS sem cliente).' using errcode = '22023';
  end if;
  x := public._agenda_cliente_contexto(p_os, v_hoje);

  -- o modo da linha: ligado só com modo_cliente ligado E o tipo na lista das ondas; senão em teste (a chave com :sombra)
  v_modo := case when cf.modo_cliente = 'ligado' and p_tipo = any (cf.cliente_tipos_ligados) then 'ligado' else 'sombra' end;
  v_chave := format('agenda-cliente:%s:%s:%s', p_tipo, p_os,
                    coalesce(nullif(btrim(p_dados ->> 'chave'), ''), p_dia_alvo::text,
                             to_char(p_alvo at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')))
             || case when v_modo = 'sombra' then ':sombra' else '' end;
  select m.id into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave;
  if v_ja is not null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe', 'id', v_ja);
  end if;

  -- a hora (a janela, o feriado, o intervalo) e o texto contado do dia em que ele SAI (o "Amanhã"), com a assinatura só na
  -- 1ª mensagem; o registro guarda os dois (a revalidação recalcula com eles)
  v_enviar := public._agenda_cliente_quando(hashtext(v_chave), p_alvo, p_agora);
  -- CORREÇÃO FASE 5: (item 12) a saudação dos que abrem com ela (a véspera, o acesso e a mudança no dia por chuva) segue a
  -- hora em que a mensagem SAI (Brasília): "Bom dia" antes do meio-dia, "Boa tarde" depois. Fica em p_dados (e em
  -- base.dados): a revalidação recalcula igual, e a hora que muda depois (a conversa viva) não a deixa desatualizada.
  if p_tipo in ('vespera', 'acesso', 'mudanca_no_dia') then
    v_dados := v_dados || jsonb_build_object('saudacao',
                 case when extract(hour from (v_enviar at time zone 'America/Sao_Paulo')) < c_meio_dia_h then 'Bom dia'
                      else 'Boa tarde' end);
  end if;
  -- CORREÇÃO FASE 5: fim
  v_prim := coalesce((p_dados ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  if p_tipo = 'confirmar' and v_var is null then
    v_var := case when v_prim then 'primeira' else 'seguinte' end;
  end if;
  v_txt := public._agenda_cliente_texto(p_tipo, v_var, p_os,
             v_dados || jsonb_build_object('primeira', v_prim, 'envio', (v_enviar at time zone 'America/Sao_Paulo')::date), v_hoje);
  v_proib := public._agenda_cliente_texto_proibido(v_txt);
  if v_proib is not null then
    raise exception 'A mensagem ao cliente não pode levar % (o texto: "%").', v_proib, left(v_txt, 120) using errcode = '22023';
  end if;
  -- o que a mensagem DIZ de data (vira o prometido quando sai): firme nos modelos com dia; faixa no atraso da peça e da
  -- execução (condicional, se o passo disser); nada no andamento, no pronto e no pós-serviço
  v_prom := coalesce(nullif(btrim(p_dados ->> 'prometido_tipo'), ''),
                     case when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
                               or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then 'firme'
                          when p_tipo = 'pode_atrasar' then 'faixa' end);
  if v_prom is not null and v_prom not in ('condicional', 'faixa', 'firme') then
    raise exception 'O que a mensagem diz de data é condicional, faixa ou firme (veio %).', v_prom using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 5: (item 8) o aviso "ainda faltam peças sem data" não diz data: não vira prometido (ao sair, o gatilho do
  -- envio tira o que o cliente tinha ouvido)
  if p_tipo = 'pode_atrasar' and v_var = 'peca_sem_data' then
    v_prom := null;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- CORREÇÃO FASE 6: (C1) item 4: o aviso de atraso da peça e da execução com a folga do aprendizado em uso (o mesmo
  -- _agenda_aprendido('aviso_folga', 'todas') que _agenda_cliente_risco somou ao fim da faixa) guarda em base.dados o fim da
  -- faixa SEM a folga (faixa_ate_plano): é contra ele que a medição mede o estouro (senão a folga aprenderia contra ela
  -- mesma e iria de 2 a 0 e de volta). O texto e a chave não mudam.
  if p_tipo = 'pode_atrasar' and v_var in ('peca', 'execucao') and (v_dados ->> 'faixa_ate') is not null then
    v_folga := coalesce(round(public._agenda_aprendido('aviso_folga', 'todas'))::int, 0);
    if v_folga > 0 then
      v_dados := v_dados || jsonb_build_object('faixa_ate_plano',
                                               public.agenda_somar_du((v_dados ->> 'faixa_ate')::date, -v_folga));
    end if;
  end if;
  -- CORREÇÃO FASE 6: fim
  v_valida := coalesce(p_valida_ate, public._agenda_cliente_fim_da_janela((v_enviar at time zone 'America/Sao_Paulo')::date, 0));
  v_base := jsonb_build_object(
    'status', x ->> 'status',
    'dia_alvo', coalesce((p_dados ->> 'dia')::date, (x ->> 'dia')::date, p_dia_alvo),
    'fim', coalesce((p_dados ->> 'fim')::date, (x ->> 'fim')::date),
    'nivel', x ->> 'nivel_material',
    'prometido_ate', x #>> '{prometido,ate}',
    'primeira', v_prim,
    'envio', (v_enviar at time zone 'America/Sao_Paulo')::date,
    'referencia', case when x -> 'plano' is null or jsonb_typeof(x -> 'plano') = 'null' then 'agendada' else 'plano' end,
    'dados', v_dados);

  -- a aprovação (em ligado): a crítica pergunta (cliente_aviso); a do dono e a do tipo ainda não liberado pedem *manda
  -- cliente* (cliente_aprovar); a do botão já foi aprovada pelo clique; o resto sai sozinho. Em teste, sempre livre.
  if v_enviar > v_valida then
    v_aprov := 'livre';
    v_estado := 'recusada';
    v_recusa := 'vencida';
  elsif v_modo = 'sombra' then
    v_aprov := 'livre';
  elsif p_critica is not null then
    v_aprov := 'critica';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aviso',
                format('cliente_aviso:%s:%s', p_os, coalesce(p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date)),
                p_os, p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date,
                public._agenda_cliente_texto_do_aviso(p_critica, p_tipo, p_os, p_dados, v_hoje), 'ligado', p_agora, v_valida);
  elsif p_origem = 'botao' then
    v_aprov := 'aprovada';
    v_aut := (select u.id from public.app_users u where u.id = p_autor);
  elsif p_origem = 'dono' or not public._agenda_cliente_tipo_liberado(p_tipo) then
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                case when p_origem = 'dono'
                     then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_quando_texto(v_enviar, p_agora), v_txt, x ->> 'nome')
                     else format('Mensagem para o %s (%s), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_tipo_texto(p_tipo), public._agenda_cliente_quando_texto(v_enviar, p_agora),
                                 v_txt, x ->> 'nome', x ->> 'nome') end,
                'ligado', p_agora, v_valida);
  else
    v_aprov := 'livre';
  end if;

  insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de,
                                               faixa_ate, prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao,
                                               pergunta_id, aprovada_em, aprovada_por, estado, recusa_motivo, dedupe_key,
                                               criada_em)
  values (v_id, v_cli, p_os, p_tipo, v_var, p_origem, p_dia_alvo, (p_dados ->> 'faixa_de')::date,
          (p_dados ->> 'faixa_ate')::date, v_prom, v_modo, v_txt, v_base, v_enviar, v_valida, v_aprov, v_perg,
          case when v_aprov = 'aprovada' then p_agora end, v_aut, v_estado, v_recusa, v_chave, p_agora);

  -- CORREÇÃO FASE 5: (item 15) a linha da sombra sem artigo antes do nome ("Em teste: eu teria mandado para Lucenira …"; a
  -- ação não muda depois de gravada, então ela já nasce assim). O bloco de 20261028100300 logo abaixo não roda mais para a
  -- sombra (v_modo fica 'sombra_feita' só entre os dois blocos).
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado para %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
    v_modo := 'sombra_feita';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- em teste: o que a agenda teria mandado (a linha do que mudou sozinho, sem executar)
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado ao %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
  end if;

  -- CORREÇÃO FASE 5: (item 15) o modo volta a ser o da linha
  if v_modo = 'sombra_feita' then
    v_modo := 'sombra';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- o que sai até o próximo tique entra na fila agora; o de depois fica registrado e o passo "fila" o enfileira na hora
  if v_modo = 'ligado' and v_estado = 'registrada' and v_aprov in ('livre', 'aprovada') and v_enviar <= p_agora + c_tique then
    v_r := public._agenda_cliente_enfileirar(v_id, p_agora);
  end if;
  return jsonb_build_object('criada', true, 'id', v_id, 'modo', v_modo, 'estado', v_estado, 'motivo', v_recusa,
                            'aprovacao', v_aprov, 'pergunta_id', v_perg, 'enviar_em', v_enviar, 'valida_ate', v_valida,
                            'texto', v_txt)
         || coalesce(v_r, '{}'::jsonb);
end;
$function$;

comment on function public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid) is
  'Agenda de Produção (Fase 5, P2): grava a mensagem-modelo ao cliente e decide o envio — desligado = nada; o texto é o do banco (_agenda_cliente_texto, contado do dia do envio, com a assinatura só na 1ª mensagem; o proibido = 22023); o modo da linha: ligado só com modo_cliente ligado E o tipo em cliente_tipos_ligados, senão sombra (chave com :sombra, a ação "Em teste: eu teria mandado…"); a chave agenda-cliente:<tipo>:<os>:<p_dados.chave | dia_alvo | o dia do alvo> (uma só: a 2ª devolve ja_existe); enviar_em pelo _agenda_cliente_quando; valida_ate = p_valida_ate, senão o fim da janela do dia do envio (passou dela = recusada/vencida); a aprovação em ligado: p_critica (segundo_atraso, atraso_longo, passou, teto) = critica + pergunta cliente_aviso; origem dono ou tipo ainda não liberado = pedida + pergunta cliente_aprovar; botão = aprovada (aprovada_por = p_autor); senão livre. base guarda {status, dia_alvo, fim, nivel, prometido_ate, primeira, envio, referencia, dados} para a revalidação. A livre/aprovada que sai até o próximo tique vai a _agenda_cliente_enfileirar. p_dados: os do modelo (dia, fim, janela, n, faixa_de/ate, peca_de/ate, dito_de/ate, dia_dito, quando, n_feitos), primeira, prometido_tipo, chave (o sufixo da chave no lugar do dia: o lembrete e o andamento semanal), atraso_dias (o aviso crítico). Sem grant. CORREÇÃO FASE 5 (C2): (item 12) a véspera, o acesso e a mudança no dia ganham p_dados.saudacao pela hora do envio (Brasília: "Bom dia" antes das 12:00, "Boa tarde" depois), guardada em base.dados; (item 8) o M6 peca_sem_data não tem prometido_tipo; (item 15) a ação da sombra sem artigo antes do nome. CORREÇÃO FASE 6 (C1, item 4): o aviso de atraso (peca/execucao) com a folga do aprendizado em uso guarda em base.dados.faixa_ate_plano o fim da faixa sem a folga (a medição mede o estouro contra ele).';

-- agenda_medir_os (de 20261029100100_agenda_fase6_medicao.sql)
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

  -- Grava só quando muda.
  m.medida_em := now();
  v_novo := to_jsonb(m) - array['medida_em', 'versao', 'historico'];
  if m0.service_order_id is null then
    m.versao := 1;
    m.historico := '[]'::jsonb;
    insert into public.agenda_medidas_os select (m).*;
    return jsonb_build_object('ok', true, 'medida', true, 'nova', true, 'mudou', true, 'versao', 1, 'valida', m.valida,
                              'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
  end if;
  v_velho := to_jsonb(m0) - array['medida_em', 'versao', 'historico'];
  if v_novo = v_velho then
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', false, 'versao', m0.versao, 'valida', m0.valida,
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
  update public.agenda_medidas_os
     set classe_bem = m.classe_bem, classe_sistema = m.classe_sistema, concluida_em = m.concluida_em,
         entregue_em = m.entregue_em, dias_no_inicio = m.dias_no_inicio, dias_fonte = m.dias_fonte,
         meios_planejados = m.meios_planejados, meios_cumpridos = m.meios_cumpridos,
         meios_fora_do_plano = m.meios_fora_do_plano, meios_sem_registro = m.meios_sem_registro,
         diarias_ligadas = m.diarias_ligadas, so_o_dono = m.so_o_dono, mo = m.mo, fator = m.fator, valida = m.valida,
         motivo = m.motivo, prometido_primeiro_ate = m.prometido_primeiro_ate, atraso_cliente_du = m.atraso_cliente_du,
         avisos_enviados = m.avisos_enviados, aviso_faixa_ate = m.aviso_faixa_ate, aviso_estouro_du = m.aviso_estouro_du,
         medida_em = m.medida_em, versao = m0.versao + 1, historico = v_hist
   where service_order_id = p_os;
  return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', true, 'versao', m0.versao + 1,
                            'valida', m.valida, 'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
end;
$function$;

comment on function public.agenda_medir_os(uuid, date) is
  'Agenda de Produção (Fase 6): a medida da OS concluída (spec-fase6 §3.1, itens 5 e 6) em agenda_medidas_os — a classe, os dias ditos no início (senão a sugerida: não vale), os meios-dias planejados e os que aconteceram, as diárias ligadas, se é só do dono, a mão de obra, o fator (só a válida), o motivo da inválida, a 1ª promessa ao cliente contra a conclusão e o último aviso de atraso. Grava só quando muda (versao + 1 e o que mudou no histórico). A OS que voltou de concluída fica inválida (reaberta). Definer, sem grant a ninguém. CORREÇÃO FASE 6 (C1): (item 9) a conclusão é o check-out, senão o 1º instante em que a porta deixou a OS concluída (_agenda_concluida_em); sem nenhum dos dois, motivo sem_fim (não vale) e a data fica a já medida; (item 4) o fim da faixa do último aviso é o base.dados.faixa_ate_plano (sem a folga do aprendizado), quando a mensagem o tem.';

-- _agenda_aprender_medir (de 20261029100100_agenda_fase6_medicao.sql)
create or replace function public._agenda_aprender_medir(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config := public._agenda_cfg();
  r     record;
  v     jsonb;
  n_olh int := 0;
  n_med int := 0;
  n_err int := 0;
  v_val int;
  v_inv jsonb;
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 6: (C1) item 9 e regressão B5: as OS a medir de novo — a concluída dentro da janela (pela conclusão já
  -- medida, senão pelo check-out, pelo instante da conclusão na porta ou, sem nada, pela última edição), a medida que voltou
  -- de concluída (reaberta, uma vez) e a medida que mudou depois da medida (service_orders.updated_at > medida_em). A medida
  -- de fora da janela que não mudou não é olhada de novo todo dia (antes: toda OS com medida, para sempre).
  for r in
    select so.id, so.service_order_number
      from public.service_orders so
      left join public.agenda_medidas_os m on m.service_order_id = so.id
     where (so.status in ('completed', 'invoiced') and so.merged_into_id is null
            and coalesce(m.concluida_em,
                         (coalesce(so.check_out_at, (select min(a.criada_em) from public.agenda_acoes a
                                                      where a.service_order_id = so.id and a.status_depois = 'completed'
                                                        and a.executada and a.desfeita_em is null), so.updated_at)
                            at time zone 'America/Sao_Paulo')::date)
                between p_hoje - c.aprender_janela_dias and p_hoje)
        or (m.service_order_id is not null and m.motivo is distinct from 'reaberta'
            and (so.status not in ('completed', 'invoiced') or so.merged_into_id is not null))
        or (m.service_order_id is not null and so.updated_at > m.medida_em)
     order by so.id
  loop
    n_olh := n_olh + 1;
    begin
      v := public.agenda_medir_os(r.id, p_hoje);
      if coalesce((v ->> 'mudou')::boolean, false) then
        n_med := n_med + 1;
      end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, medir %s: %s', coalesce(r.service_order_number, r.id::text), sqlerrm),
                                   'agenda', 'aprender:medir', 'error',
                                   jsonb_build_object('os', r.id, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  -- CORREÇÃO FASE 6: fim
  for r in
    select so.id, so.service_order_number
      from public.service_orders so
      -- CORREÇÃO FASE 6: (C1) item 9 e regressão B5: este laço (o de antes) não olha mais nada; vale o de cima
      join (select 1 where false) as nada on true
      -- CORREÇÃO FASE 6: fim
     where (so.status in ('completed', 'invoiced') and so.merged_into_id is null
            and (coalesce(so.check_out_at, so.updated_at) at time zone 'America/Sao_Paulo')::date
                between p_hoje - c.aprender_janela_dias and p_hoje)
        or exists (select 1 from public.agenda_medidas_os m where m.service_order_id = so.id)
     order by so.id
  loop
    n_olh := n_olh + 1;
    begin
      v := public.agenda_medir_os(r.id, p_hoje);
      if coalesce((v ->> 'mudou')::boolean, false) then
        n_med := n_med + 1;
      end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, medir %s: %s', coalesce(r.service_order_number, r.id::text), sqlerrm),
                                   'agenda', 'aprender:medir', 'error',
                                   jsonb_build_object('os', r.id, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  select count(*) filter (where m.valida)::int,
         coalesce(jsonb_object_agg(m.motivo, m.n) filter (where m.motivo is not null), '{}'::jsonb)
    into v_val, v_inv
    from (select x.valida, x.motivo, count(*) over (partition by x.motivo) as n
            from public.agenda_medidas_os x
           where x.concluida_em between p_hoje - c.aprender_janela_dias and p_hoje) m;
  return jsonb_build_object('olhadas', n_olh, 'medidas', n_med, 'validas', coalesce(v_val, 0),
                            'invalidas', coalesce(v_inv, '{}'::jsonb), 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_medir(date) is
  'Agenda de Produção (Fase 6): o passo da medição da rodada — mede (agenda_medir_os) as OS concluídas nos aprender_janela_dias até p_hoje e as que têm medida (a reaberta). Só grava o que mudou. O erro de uma OS vai a app_error_logs (agenda / aprender:medir) e o passo segue. {olhadas, medidas (gravadas), validas, invalidas: {motivo: n}, erros} (as contagens das medidas da janela). Sem grant a ninguém. CORREÇÃO FASE 6 (C1): (regressão B5) mede de novo só a OS concluída na janela, a medida que voltou de concluída (uma vez) e a medida que mudou depois de medida (updated_at > medida_em) — não toda OS com medida, todo dia; (item 9) a janela pela conclusão já medida, senão pelo check-out ou pelo instante da conclusão na porta.';

-- _agenda_aprender_capacidade (de 20261029100400_agenda_fase6_dono.sql)
create or replace function public._agenda_aprender_capacidade(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_seg    date;
  v_de     date;
  v_ate    date;
  v_semanas jsonb;
  v_amostra jsonb;
  v_taxas  numeric[];
  v_n      int;
  v_taxa   numeric;
  v_calc   numeric;
  v_fora   int;
  v_disse  jsonb;
  -- CORREÇÃO FASE 6: (C1) item 4: a capacidade em uso e desde quando (a semana planejada com ela)
  v_uso    numeric;
  v_desde  date;
  v_cap    numeric;
  -- CORREÇÃO FASE 6: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  if v_dono is null then
    -- sem saber quem é o dono não há o que medir (nada é gravado)
    return jsonb_build_object('item', 'capacidade_dono', 'pulado', 'sem_dono');
  end if;
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_de := v_seg - 7 * c.capacidade_semanas;
  v_ate := v_seg - 1;

  with a as (
    select x.dia, x.turno, x.estado in ('publicada', 'fixada') as vig,
           case when x.estado = 'cancelada' then 1
                -- CORREÇÃO FASE 6: (C1) item 5 (DONO decide; recomendação aplicada): o parcial por um motivo que não é dele
                -- (fora de capacidade_motivos: chuva, material, cliente…) sai da conta, como o não cumprido. Para voltar a
                -- contar o parcial com qualquer motivo, tirar este "when".
                when x.resultado = 'parcial' and x.motivo is not null and not (x.motivo = any (c.capacidade_motivos)) then 0
                -- CORREÇÃO FASE 6: fim
                when x.resultado in ('cumprido', 'parcial') then 1
                when x.resultado = 'nao_cumprido' and x.motivo = any (c.capacidade_motivos) then 1
                else 0 end as plan,
           case when x.estado = 'cancelada' then 0
                when x.resultado = 'cumprido' then 1
                when x.resultado = 'parcial' then 0.5
                else 0 end as feito
      from public.agenda_alocacoes x
     where x.payee_id = v_dono and x.presenca = 'turno' and x.tipo <> 'reserva'
       and x.dia between v_de and v_ate
       and (x.estado in ('publicada', 'fixada')
            or (x.estado = 'cancelada' and x.publicada_em is not null and x.cancelada_motivo in ('dono', 'pessoa')))
       -- CORREÇÃO FASE 6: (C1) item 5 (DONO decide; recomendação aplicada): o cancelado a pedido do DONO (cancelada_motivo
       -- 'dono', que o motor grava quando ele pede para mudar a OS) não é falta dele e sai da conta; só o cancelado por ele
       -- não poder ('pessoa') conta. Para voltar a contar o 'dono', tirar esta linha.
       and not (x.estado = 'cancelada' and x.cancelada_motivo = 'dono')
       -- CORREÇÃO FASE 6: fim
  ),
  meio as (
    -- um por meio-dia: o vigente, se houver; senão o cancelado
    select a.dia, a.turno,
           case when bool_or(a.vig) then max(a.plan) filter (where a.vig) else max(a.plan) end as plan,
           case when bool_or(a.vig) then max(a.feito) filter (where a.vig and a.plan = 1) else 0 end as feito
      from a group by a.dia, a.turno
  ),
  sem as (
    select m.dia - (extract(isodow from m.dia)::int - 1) as semana, sum(m.plan)::int as planejados,
           coalesce(sum(m.feito) filter (where m.plan = 1), 0) as feitos
      from meio m
     group by 1
    having sum(m.plan) > 0
  )
  select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'planejados', s.planejados, 'feitos', trim_scale(s.feitos),
                                               'conta', s.planejados >= c.capacidade_meios_min)
                            order by s.semana desc), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'planejados', s.planejados, 'feitos', trim_scale(s.feitos),
                                               'taxa', round(s.feitos / s.planejados, 2))
                            order by s.semana desc) filter (where s.planejados >= c.capacidade_meios_min), '[]'::jsonb),
         array_agg(s.feitos / s.planejados) filter (where s.planejados >= c.capacidade_meios_min),
         count(*) filter (where s.planejados >= c.capacidade_meios_min)::int
    into v_semanas, v_amostra, v_taxas, v_n
    from sem s;

  v_taxa := public._agenda_percentil(v_taxas, 0.5);
  v_calc := case when v_taxa is null then null
                 else greatest(c.capacidade_dono_min, least(c.carga_max, round(v_taxa * c.carga_max, 2))) end;
  -- CORREÇÃO FASE 6: (C1) item 4 (o vaivém): a taxa de cada semana é sobre o que o motor MARCOU, e ele marca com a carga
  -- que valia; a capacidade da semana = taxa × essa carga. Com a capacidade em uso (_agenda_aprendido), as semanas
  -- planejadas desde que ela entrou (em_uso_desde) usam ela, e as de antes, carga_max. Sem isso, o dono que faz tudo o que
  -- a carga menor marcou (taxa 1) voltaria a carga_max na rodada seguinte, e dali à menor de novo. Sem nada em uso, a conta
  -- é a de antes (a mediana × carga_max), byte a byte.
  v_uso := public._agenda_aprendido('capacidade_dono', 'dono');
  select (a.em_uso_desde at time zone 'America/Sao_Paulo')::date into v_desde
    from public.agenda_aprendizado a
   where a.item = 'capacidade_dono' and a.chave = 'dono';
  if v_uso is not null and v_desde is not null and v_taxa is not null then
    select public._agenda_percentil(array_agg((s ->> 'feitos')::numeric / (s ->> 'planejados')::numeric
                                              * case when (s ->> 'semana')::date >= v_desde then least(v_uso, c.carga_max)
                                                     else c.carga_max end), 0.5)
      into v_cap
      from jsonb_array_elements(v_amostra) s;
    v_calc := greatest(c.capacidade_dono_min, least(c.carga_max, round(v_cap, 2)));
  end if;
  -- CORREÇÃO FASE 6: fim

  -- os meios-dias em que ele foi sem estar no plano (as idas ditas; uma por OS e dia; o dia todo = 2)
  select coalesce(sum(q.meios), 0)::int into v_fora
    from (select i.service_order_id, i.dia, max(case i.dita when 'dia' then 2 else 1 end) as meios
            from public.agenda_intervencoes_do_dono i
           where i.dia between v_de and v_ate and i.dita in ('manha', 'tarde', 'dia')
           group by 1, 2) q;
  -- o que ele disse da semana dele (a base: o aprendido só reduz quanto dela o motor compromete)
  select coalesce(jsonb_agg(jsonb_build_object('dias_semana', d.dias_semana, 'periodo', d.periodo::text, 'turno', d.turno,
                                               'situacao', d.situacao, 'trecho', d.trecho)
                            order by d.periodo nulls first, d.dias_semana, d.turno nulls first, d.situacao, d.criado_em, d.id),
                  '[]'::jsonb)
    into v_disse
    from public.agenda_disponibilidade d
   where d.payee_id = v_dono and d.origem = 'dono' and d.substituida_em is null
     and (d.periodo is null or d.periodo && daterange(v_de, v_ate, '[]'));

  return public._agenda_aprendizado_gravar('capacidade_dono', 'dono', 'dono', v_calc, coalesce(v_n, 0), v_amostra,
           c.carga_max,
           jsonb_build_object('janela', c.capacidade_semanas, 'de', v_de, 'ate', v_ate, 'taxa', round(v_taxa, 2),
                              'semanas', v_semanas, 'fora_do_plano', v_fora, 'voce_disse', v_disse),
           p_agora);
end;
$function$;

comment on function public._agenda_aprender_capacidade(date, timestamptz) is
  'Agenda de Produção (Fase 6, P4): o passo da capacidade do dono da rodada — nas capacidade_semanas semanas ISO completas antes de p_hoje, os meios-dias do dono no plano (presença turno, sem reserva; o vigente com o resultado, ou o cancelado por ele — dono/pessoa — quando o meio-dia não tem vigente): cumprido 1, parcial 0,5, não cumprido 0 só com o motivo em capacidade_motivos (o resto sai da conta, como o sem resultado). A semana conta com ≥ capacidade_meios_min. calculado = mediana(feitos ÷ planejados) × carga_max, preso em [capacidade_dono_min, carga_max]; padrão carga_max; item capacidade_dono, chave e nível dono; detalhe {janela, de, ate, taxa, semanas[{semana, planejados, feitos, conta}], fora_do_plano (os meios-dias das idas ditas), voce_disse (agenda_disponibilidade do dono)}. Devolve o que o gravador devolve; sem dono, {pulado: sem_dono}. Lança no erro (a rodada isola). Sem grant a ninguém. CORREÇÃO FASE 6 (C1): (item 5, decisão do dono com a recomendação aplicada) o cancelado a pedido do dono (cancelada_motivo dono) e o parcial por motivo fora de capacidade_motivos saem da conta; (item 4) com a capacidade em uso, as semanas planejadas desde em_uso_desde pesam com ela (taxa × a carga que o motor usou), as de antes com carga_max — sem o vaivém.';

-- _agenda_aprender_presenca (de 20261029100200_agenda_fase6_os.sql)
create or replace function public._agenda_aprender_presenca(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_desde date;
  r      record;
  v      jsonb;
  v_calc numeric;
  v_est  jsonb := '{}'::jsonb;
  n_ch   int := 0;
  n_acao int := 0;
  n_perg int := 0;
  n_err  int := 0;
  -- CORREÇÃO FASE 6: (C1) item 7: os sistemas e a classe fina mais larga da amostra de todas
  v_sis  int;
  v_fina int;
  -- CORREÇÃO FASE 6: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  -- Desde quando as idas do dono são registradas: a 1ª intervenção (qualquer "dita"). Antes dela não há como saber se ele foi.
  select min(i.dia) into v_desde from public.agenda_intervencoes_do_dono i where i.dia <= p_hoje;
  for r in
    with med as (
      select m.service_order_id as os, so.service_order_number as numero, m.concluida_em, m.classe_bem, m.classe_sistema,
             exists (select 1 from public.agenda_intervencoes_do_dono i
                      where i.service_order_id = m.service_order_id and i.dita in ('manha', 'tarde', 'dia')
                        and i.dia <= p_hoje) as foi
        from public.agenda_medidas_os m
        join public.service_orders so on so.id = m.service_order_id
       where m.valida and v_desde is not null
         and m.concluida_em between greatest(v_desde, p_hoje - c.aprender_janela_dias) and p_hoje),
    chaves as (
      select med.*, x.chave, x.nivel, x.ordem
        from med
        cross join lateral (values (med.classe_bem || ':' || med.classe_sistema, 'fina', 1),
                                   ('sistema:' || med.classe_sistema, 'sistema', 2),
                                   ('todas', 'todas', 3)) x(chave, nivel, ordem)),
    por_chave as (
      select ch.chave, ch.nivel, ch.ordem, count(*)::int as n, count(*) filter (where ch.foi)::int as k,
             jsonb_agg(jsonb_build_object('os', ch.os, 'numero', ch.numero, 'foi', ch.foi, 'em', ch.concluida_em)
                       order by ch.concluida_em desc, ch.os) as amostra
        from chaves ch
       group by ch.chave, ch.nivel, ch.ordem)
    select pc.chave, pc.nivel, pc.ordem, pc.n, pc.k, pc.amostra from por_chave pc
    union all
    -- a chave que já tem linha e ficou sem medida: volta a medir
    select a.chave, a.nivel, case a.nivel when 'fina' then 1 when 'sistema' then 2 else 3 end, 0, 0, '[]'::jsonb
      from public.agenda_aprendizado a
     where a.item = 'presenca' and not exists (select 1 from por_chave pc where pc.chave = a.chave)
     order by 3, 1
  loop
    n_ch := n_ch + 1;
    begin
      -- 1 = o dia todo; 0 = o abre e fecha (o padrão de hoje)
      v_calc := case when r.n = 0 then null
                     when r.k >= c.presenca_intervencoes_min and r.n >= c.presenca_n_min
                          and r.k::numeric / r.n >= c.presenca_taxa_min then 1
                     else 0 end;
      -- CORREÇÃO FASE 6: (C1) item 7: a presença geral (todas: a regra d05 inteira) só tem calculado com evidência de mais
      -- de uma classe — as OS da amostra de pelo menos 2 sistemas e mais OS que a classe fina mais larga. Senão, medindo (a
      -- pergunta "conto com você o dia todo por padrão?" não sai das mesmas OS que já entraram sozinhas na classe).
      if r.chave = 'todas' and v_calc is not null then
        select count(distinct m.classe_sistema)::int into v_sis
          from jsonb_array_elements(r.amostra) e
          join public.agenda_medidas_os m on m.service_order_id = (e ->> 'os')::uuid;
        select max(q.n)::int into v_fina
          from (select count(*) as n
                  from jsonb_array_elements(r.amostra) e
                  join public.agenda_medidas_os m on m.service_order_id = (e ->> 'os')::uuid
                 group by m.classe_bem, m.classe_sistema) q;
        if coalesce(v_sis, 0) < 2 or r.n <= coalesce(v_fina, 0) then
          v_calc := null;
        end if;
      end if;
      -- CORREÇÃO FASE 6: fim
      v := public._agenda_aprendizado_gravar('presenca', r.chave, r.nivel, v_calc, r.n, r.amostra, 0,
             jsonb_build_object('k', r.k, 'desde', v_desde), p_agora);
      v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
      if v ->> 'acao_id' is not null then n_acao := n_acao + 1; end if;
      if v ->> 'pergunta_id' is not null then n_perg := n_perg + 1; end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, presença %s: %s', r.chave, sqlerrm), 'agenda', 'aprender:presenca',
                                   'error', jsonb_build_object('chave', r.chave, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  return jsonb_build_object('desde', v_desde, 'chaves', n_ch, 'estados', v_est, 'acoes', n_acao, 'perguntas', n_perg,
                            'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_presenca(date, timestamptz) is
  'Agenda de Produção (Fase 6, P2): o passo da presença do dono da rodada — nas chaves fina e sistema (entra sozinha) e todas (sempre pergunta: é a regra d05 inteira), n = as OS com medida válida da classe concluídas desde a 1ª ida do dono registrada (a menor agenda_intervencoes_do_dono.dia; antes dela não há registro) e k = as dessas com ida dele sem estar no plano (dita manha, tarde ou dia; passou não conta). calculado = 1 (o dia todo) com k ≥ presenca_intervencoes_min, n ≥ presenca_n_min e k/n ≥ presenca_taxa_min; senão 0 (o abre e fecha, o padrão). detalhe {k, desde}. O erro de uma chave vai a app_error_logs (agenda / aprender:presenca). {desde, chaves, estados, acoes, perguntas, erros}. Sem grant a ninguém. CORREÇÃO FASE 6 (C1, item 7): a chave todas só tem calculado com as OS da amostra de pelo menos 2 sistemas e mais OS que a classe fina mais larga; senão, medindo (sem a pergunta do geral tirada de uma classe só).';

-- _agenda_aprender_cliente (de 20261029100500_agenda_fase6_cliente.sql)
create or replace function public._agenda_aprender_cliente(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c       public.agenda_config := public._agenda_cfg();
  v_de    date;
  v_n     int;
  v_ok    int;
  v_vals  numeric[];
  v_amos  jsonb;
  v_p     numeric;
  v_calc  numeric;
  v_pont  jsonb;
  v_aviso jsonb;
  n_err   int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  v_de := p_hoje - c.aprender_janela_dias;

  -- (a) A pontualidade (só medida, nunca usada): das OS concluídas com a 1ª data dita ao cliente, quantas ficaram prontas
  -- até ela (o atraso em dias úteis ≤ 0). O "atraso chega a" é o P80 do atraso de todas, ao dia útil mais próximo, nunca < 0.
  begin
    select count(*), count(*) filter (where m.atraso_cliente_du <= 0),
           array_agg(m.atraso_cliente_du::numeric),
           coalesce(jsonb_agg(jsonb_build_object('os', m.service_order_id, 'numero', so.service_order_number,
                                                 'primeiro', m.prometido_primeiro_ate, 'concluida', m.concluida_em,
                                                 'atraso_du', m.atraso_cliente_du)
                              order by m.concluida_em desc, so.service_order_number), '[]'::jsonb)
      into v_n, v_ok, v_vals, v_amos
      from public.agenda_medidas_os m
      join public.service_orders so on so.id = m.service_order_id
     where m.concluida_em between v_de and p_hoje
       and m.motivo is distinct from 'reaberta'
       -- CORREÇÃO FASE 6: (C1) item 9: sem o dia da conclusão, não há atraso a medir
       and m.motivo is distinct from 'sem_fim'
       -- CORREÇÃO FASE 6: fim
       and m.prometido_primeiro_ate is not null and m.atraso_cliente_du is not null;
    v_p := public._agenda_percentil(v_vals, c.fator_percentil);
    -- CORREÇÃO FASE 6: (C1) item 11: um arredondamento só para o P80 em dias úteis — o teto (a margem de segurança), como o
    -- atraso do fornecedor: o "atraso chega a" (round abaixo) recebe o P80 já arredondado para cima
    v_p := ceil(v_p);
    -- CORREÇÃO FASE 6: fim
    v_calc := case when v_n > 0 then round(v_ok::numeric / v_n, 2) end;
    v_pont := public._agenda_aprendizado_gravar('cliente_pontualidade', 'todas', 'todas', v_calc, v_n, v_amos, null,
                jsonb_build_object('n', v_n, 'no_prazo', v_ok,
                                   'p80_atraso_du', case when v_p is not null then greatest(0, round(v_p)) end),
                p_agora);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, pontualidade com o cliente: %s', sqlerrm), 'agenda',
                                 'aprender:cliente', 'error',
                                 jsonb_build_object('item', 'cliente_pontualidade', 'sqlstate', sqlstate, 'p_hoje', p_hoje));
    n_err := n_err + 1;
  end;

  -- (b) A folga do aviso de atraso: nas OS com aviso de atraso enviado (e com a faixa dele), quantos dias úteis o serviço
  -- terminou depois do fim da faixa; o P80, ao dia útil mais próximo, preso em [0, aviso_folga_max_du]. O padrão é 0 (a
  -- faixa do plano, sem folga).
  begin
    select count(*), count(*) filter (where m.aviso_estouro_du <= 0),
           array_agg(m.aviso_estouro_du::numeric),
           coalesce(jsonb_agg(jsonb_build_object('os', m.service_order_id, 'numero', so.service_order_number,
                                                 'faixa_ate', m.aviso_faixa_ate, 'concluida', m.concluida_em,
                                                 'avisos', m.avisos_enviados, 'estouro_du', m.aviso_estouro_du)
                              order by m.concluida_em desc, so.service_order_number), '[]'::jsonb)
      into v_n, v_ok, v_vals, v_amos
      from public.agenda_medidas_os m
      join public.service_orders so on so.id = m.service_order_id
     where m.concluida_em between v_de and p_hoje
       and m.motivo is distinct from 'reaberta'
       -- CORREÇÃO FASE 6: (C1) item 9: sem o dia da conclusão, não há estouro a medir
       and m.motivo is distinct from 'sem_fim'
       -- CORREÇÃO FASE 6: fim
       and m.avisos_enviados > 0 and m.aviso_faixa_ate is not null and m.aviso_estouro_du is not null;
    v_p := public._agenda_percentil(v_vals, c.fator_percentil);
    -- CORREÇÃO FASE 6: (C1) item 11: o teto, como o atraso do fornecedor (P80 2,2 → 3: com 2, um dos cinco avisos ainda
    -- estourava); o round abaixo recebe o P80 já arredondado para cima
    v_p := ceil(v_p);
    -- CORREÇÃO FASE 6: fim
    v_calc := case when v_p is not null then least(c.aviso_folga_max_du, greatest(0, round(v_p))) end;
    v_aviso := public._agenda_aprendizado_gravar('aviso_folga', 'todas', 'todas', v_calc, v_n, v_amos, 0,
                 jsonb_build_object('n', v_n, 'no_prazo', v_ok, 'p50', public._agenda_percentil(v_vals, 0.5),
                                    'maior', (select max(x) from unnest(v_vals) x)),
                 p_agora);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, folga do aviso ao cliente: %s', sqlerrm), 'agenda',
                                 'aprender:cliente', 'error',
                                 jsonb_build_object('item', 'aviso_folga', 'sqlstate', sqlstate, 'p_hoje', p_hoje));
    n_err := n_err + 1;
  end;

  return jsonb_build_object('pontualidade', v_pont, 'aviso_folga', v_aviso, 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_cliente(date, timestamptz) is
  'Agenda de Produção (Fase 6, P5): o passo do cliente da rodada — pelo gravador, nas medidas das OS concluídas na janela (aprender_janela_dias; sem a reaberta): cliente_pontualidade (chave todas; só medida, nunca em uso) = a fração das OS com a 1ª promessa (prometido_primeiro_ate) prontas até ela, n ≥ cliente_n_min, detalhe {n, no_prazo, p80_atraso_du}; aviso_folga (chave todas; padrão 0) = o P80 (fator_percentil) de quantos dias úteis o serviço passou do fim da faixa do último aviso de atraso enviado, ao dia útil mais próximo, preso em [0, aviso_folga_max_du], n ≥ aviso_n_min, detalhe {n, no_prazo, p50, maior}. Cada item no seu bloco (o erro vai a app_error_logs agenda / aprender:cliente). {pontualidade, aviso_folga, erros}. Sem grant a ninguém. CORREÇÃO FASE 6 (C1): (item 11) o P80 em dias úteis da folga e do "atraso chega a" da pontualidade arredonda para cima (o teto), como o atraso do fornecedor; (item 9) a medida sem o dia da conclusão (sem_fim) fica fora das duas.';

-- agenda_aprender (de 20261029100600_agenda_fase6_rodada.sql)
create or replace function public.agenda_aprender(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_medir   constant text[] := array['congelar', 'medir'];
  c_passos  constant text[] := array['fator', 'mo', 'presenca', 'fornecedor', 'capacidade', 'cliente'];
  c_semana  constant text[] := array['revisao', 'solver'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_semanal boolean;
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do aprendizado.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  cf := public._agenda_cfg();
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.aprender_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'modo', cf.modo_aprendizado, 'hora', cf.aprender_hora);
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true, 'modo', cf.modo_aprendizado);
  end if;
  v_semanal := extract(isodow from p_hoje)::int = cf.dia_do_plano;
  -- CORREÇÃO FASE 6: (C1) item 13: a revisão da carga e o planejador mais forte rodam no dia do plano OU depois dele na mesma
  -- semana ISO, enquanto não houve nesta semana rodada semanal com o modo e a lista de agora (a quinta que não rodou, ou o
  -- dono que ligou a revisão na sexta: não espera a quinta seguinte). Uma vez por semana com o mesmo modo e a mesma lista.
  v_semanal := extract(isodow from p_hoje)::int >= cf.dia_do_plano
               and not exists (select 1 from public.agenda_vigia_rodadas x
                                where x.rotina = 'aprender'
                                  and x.p_hoje >= p_hoje - (extract(isodow from p_hoje)::int - 1) and x.p_hoje < p_hoje
                                  and coalesce((x.contagens ->> 'semanal')::boolean, false)
                                  and x.contagens ->> 'modo_aprendizado' = cf.modo_aprendizado
                                  and x.contagens -> 'ligados' = to_jsonb(cf.aprendizado_ligados));
  -- CORREÇÃO FASE 6: fim

  -- (1) a medição: sempre, em qualquer modo (só escreve as tabelas da Fase 6); (2) o aprendido: fora de desligado; (3) a
  -- revisão e o planejador mais forte: fora de desligado, no dia do plano
  foreach v_passo in array c_medir
                           || case when cf.modo_aprendizado <> 'desligado' then c_passos else '{}'::text[] end
                           || case when cf.modo_aprendizado <> 'desligado' and v_semanal then c_semana else '{}'::text[] end loop
    begin
      if v_passo = any (c_medir) then
        execute format('select public.%I($1)', '_agenda_aprender_' || v_passo) into v_r using p_hoje;
      else
        execute format('select public.%I($1, $2)', '_agenda_aprender_' || v_passo) into v_r using p_hoje, p_agora;
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('aprendizado, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'aprender:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
    end;
  end loop;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modo_aprendizado', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
                                       'semanal', v_semanal, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'aprender', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
                            'semanal', v_semanal, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_aprender(date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): a rodada diária do aprendizado (spec-fase6 §5.6), pelo task-automations a cada tique — roda uma vez por dia, no 1º tique a partir de aprender_hora (antes = {rodou: false, cedo}; o 2º = {rodou: false, ja_rodou}). Passos, cada um no seu bloco (o que falha vai a app_error_logs, context agenda, action aprender:<passo>, e os outros seguem): (1) sempre, até com modo_aprendizado desligado, congelar e medir; (2) fora de desligado, fator, mo, presenca, fornecedor, capacidade e cliente (pelo gravador: em teste tudo fica sombra e nada é usado); (3) fora de desligado e no dia_do_plano, revisao (a carga pelo plano cumprido) e solver. Uma linha em agenda_vigia_rodadas (rotina aprender). {rodou, modo, ligados, semanal, contagens, erros, falhas}. Nenhuma mensagem. Só service_role. CORREÇÃO FASE 6 (C1, item 13): a revisão e o solver rodam no dia_do_plano ou depois dele na mesma semana ISO, enquanto não houve rodada semanal nesta semana com o modo e a lista de agora (semanal = isso).';

-- agenda_propor (de 20261025100200_agenda_fase2_motor.sql)
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
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%".';

-- _agenda_vigia_estouro (de 20261029100200_agenda_fase6_os.sql)
create or replace function public._agenda_vigia_estouro(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  r   record;
  v_m jsonb;
  v_n int := 0;
  v_c numeric;
  v_t numeric;
  -- FASE 6: o limiar desta OS (o fator de campo)
  v_f numeric;
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C1) item 15: os meios-dias das diárias ligadas fora do plano
  v_fora numeric;
  -- CORREÇÃO FASE 6: fim
begin
  for r in select k.service_order_id as os from public.os_carteira(p_hoje) k
            where k.status = 'in_progress' order by k.numero collate "C", k.service_order_id loop
    v_m := public.agenda_meios_da_os(r.os, p_hoje);
    continue when v_m ->> 'fonte' not in ('dono', 'aceita') or (v_m ->> 'total') is null;
    v_c := coalesce((v_m ->> 'cumpridos')::numeric, 0);
    v_t := (v_m ->> 'total')::numeric;
    -- CORREÇÃO FASE 6: (C1) regressão B3 e item 15: o fator de campo só com o aprendizado LIGADO e "fator" na lista (o portão
    -- de _agenda_cliente_risco, do P5): em desligado e em teste nem é lido, e o limiar é estouro_fator, byte a byte o da Fase
    -- 2; o erro da cadeia nova (uma expressão da classe que lança, o 42501) vira o padrão e vai a app_error_logs (agenda /
    -- vigia:estouro), sem derrubar o passo. Com o fator aprendido em uso, os meios-dias contam também as diárias ligadas fora
    -- do plano (meios_fora_do_plano, a mesma conta da medida: a medida aprendeu o fator com elas). O bloco da Fase 6 de baixo
    -- e o "continue" de antes não rodam mais (o "continue" no fim deste bloco).
    v_f := cf.estouro_fator;
    if cf.modo_aprendizado = 'ligado' and 'fator' = any (cf.aprendizado_ligados) then
      begin
        v_f := coalesce((public.agenda_fator_de_campo(r.os, p_hoje) ->> 'fator')::numeric, cf.estouro_fator);
        select coalesce(sum(greatest(1, round(x.f * 2))), 0) into v_fora
          from (select ws.data, max(ws.fracao / (select count(*) from public.work_shift_os w2 where w2.shift_id = ws.id)) as f
                  from public.work_shift_os wo
                  join public.work_shifts ws on ws.id = wo.shift_id
                  join public.work_profiles wp on wp.id = ws.work_profile_id
                  join public.payees p on p.id = wp.payee_id
                 where wo.service_order_id = r.os and ws.fracao > 0 and wp.modo_pagamento = 'diaria'
                   and p.kind is distinct from 'socio' and ws.data <= p_hoje
                   and not exists (select 1 from public.agenda_alocacoes a
                                    where a.service_order_id = r.os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                      and a.dia = ws.data)
                 group by ws.data) x;
        v_c := v_c + v_fora;
      exception when others then
        v_f := cf.estouro_fator;
        perform public.log_app_error('db', format('vigia, estouro %s: %s', r.os, sqlerrm), 'agenda', 'vigia:estouro', 'error',
                                     jsonb_build_object('os', r.os, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      end;
    end if;
    if not (v_t <= 0 or v_c <= v_f * v_t)
       and public._agenda_vigia_perguntar('estouro', format('estouro:%s:%s', r.os, v_m ->> 'total'), r.os, null, null, null,
             format('%s já teve %s de serviço e o combinado era %s. O que falta?', public._agenda_rotulo_da_os(r.os),
                    public._agenda_dias(round(v_c) / 2), public._agenda_dias(v_t / 2)),
             cf.modo_vigia, p_agora) then
      v_n := v_n + 1;
    end if;
    continue;
    -- CORREÇÃO FASE 6: fim
    -- FASE 6: o limiar é o fator de campo da classe da OS (agenda_fator_de_campo: o aprendido em uso, senão estouro_fator);
    -- o limiar de antes (logo abaixo) só roda se o fator não vier
    v_f := coalesce((public.agenda_fator_de_campo(r.os, p_hoje) ->> 'fator')::numeric, cf.estouro_fator);
    continue when v_t <= 0 or v_c <= v_f * v_t;
    if v_f is null then
    -- FASE 6: fim
    continue when v_t <= 0 or v_c <= cf.estouro_fator * v_t;
    -- FASE 6: o limiar de antes não roda mais (fica para a conferência da cópia)
    end if;
    -- FASE 6: fim
    if public._agenda_vigia_perguntar('estouro', format('estouro:%s:%s', r.os, v_m ->> 'total'), r.os, null, null, null,
         format('%s já teve %s de serviço e o combinado era %s. O que falta?', public._agenda_rotulo_da_os(r.os),
                public._agenda_dias(round(v_c) / 2), public._agenda_dias(v_t / 2)),
         cf.modo_vigia, p_agora) then
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('criadas', v_n);
end;
$function$;

comment on function public._agenda_vigia_estouro(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 11: em andamento com os dias ditos e os meios-dias feitos acima de estouro_fator × o combinado → pergunta estouro:<os>:<total> ("o que falta?"). FASE 6 (P2): o limiar é agenda_fator_de_campo(os, hoje).fator (o fator de campo aprendido em uso da classe da OS, senão estouro_fator); a chave e o texto da pergunta não mudam. CORREÇÃO FASE 6 (C1): (regressão B3) o fator de campo só é lido com o aprendizado ligado e fator na lista (fora disso, estouro_fator, byte a byte o da Fase 2); o erro dele vira o padrão e vai a app_error_logs (agenda / vigia:estouro), sem derrubar o passo; (item 15) com o fator ligado, os meios-dias contam também as diárias ligadas fora do plano (a conta da medida).';

-- _agenda_aprendizado_decidir (de 20261029100600_agenda_fase6_rodada.sql)
create or replace function public._agenda_aprendizado_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text,
                                                              p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_q      public.agenda_perguntas%rowtype;
  r0       public.agenda_aprendizado;
  r        public.agenda_aprendizado;
  v_opc    jsonb;
  v_efet   numeric;
  v_carga  numeric;
  v_d      jsonb;
  v_txt    text;
  v_acao   uuid;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 6: (C1) regressão B2: a decisão do aprendizado toma a trava da rodada do aprendizado (agenda_aprender) ANTES de travar
  -- qualquer linha: a rodada trava agenda_aprendizado e depois agenda_perguntas; a decisão, o contrário. Com a mesma trava
  -- primeiro, as duas se enfileiram (sem o 40P01 quando o dono responde durante a rodada das 16:00).
  perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  -- CORREÇÃO FASE 6: fim
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found or v_q.tipo <> 'aprendizado' then
    raise exception 'Não encontrei essa pergunta do aprendizado.' using errcode = 'P0002';
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  select * into r0 from public.agenda_aprendizado a where a.pergunta_id = v_q.id for update;
  if not found or r0.estado <> 'pergunta' then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'O medido mudou: a pergunta não vale mais.'
     where id = v_q.id and estado = 'aberta';
    return jsonb_build_object('ok', false,
      'texto', 'Essa pergunta não vale mais: o medido mudou desde ela. Se precisar, pergunto de novo.');
  end if;
  if cf.modo_aprendizado <> 'ligado' or not (public._agenda_aprendizado_da_lista(r0.item) = any (cf.aprendizado_ligados)) then
    return jsonb_build_object('ok', false,
      'texto', 'O aprendizado está em teste: não mudo nada agora. Quando ele estiver ligado, eu pergunto de novo.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;

  update public.agenda_perguntas
     set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
         respondida_por = p_autor, respondida_via = p_via
   where id = v_q.id;

  r := r0;
  v_efet := coalesce(r0.em_uso, r0.padrao);
  if p_opcao = 1 then
    r.em_uso := r0.calculado;
    r.estado := 'em_uso';
    r.em_uso_desde := p_agora;
    r.travado_ate := null;
    r.travado_valor := null;
    if r0.item = 'carga' then
      -- a carga de todos muda no parâmetro (o motor lê carga_max), e o *desfaz* a volta
      v_carga := cf.carga_max;
      v_efet := v_carga;
      if not public._agenda_aprendizado_carga(v_carga, r0.calculado, p_autor, p_agora) then
        raise exception 'A carga mudou enquanto eu decidia.' using errcode = '40001';
      end if;
    end if;
  elsif p_opcao = 2 then
    r.estado := 'travado';
    r.travado_ate := p_hoje + cf.aprender_trava_dias;
    r.travado_valor := r0.calculado;
  else
    r.em_uso := null;
    r.em_uso_desde := null;
    r.estado := 'travado';
    r.travado_ate := p_hoje + cf.aprender_trava_dias;
    r.travado_valor := r0.calculado;
  end if;

  v_d := jsonb_build_object('chave', r0.chave, 'calculado', r0.calculado, 'em_uso', r.em_uso, 'efetivo', v_efet,
                            'padrao', r0.padrao, 'volta', r0.padrao, 'n', r0.n, 'n_min', r0.n_min,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', cf.aprender_trava_dias, 'detalhe', r0.detalhe);
  v_txt := case p_opcao
             when 1 then public._agenda_aprendizado_texto(r0.item, 'acao', v_d)
             when 2 then public._agenda_aprendizado_texto(r0.item, 'fico', v_d)
             else regexp_replace(public._agenda_aprendizado_texto(r0.item, 'desfeito', v_d), '^Desfeito: ', 'Combinado: ') end;
  -- a linha do foco: na trava pela opção 3, o que vale é o padrão
  r.texto := left(public._agenda_corta(public._agenda_aprendizado_texto(r0.item, 'foco_' || r.estado,
                    v_d || case when p_opcao = 3 then jsonb_build_object('efetivo', r0.padrao) else '{}'::jsonb end), 400), 400);

  -- a ação crítica, com *desfaz* (a 1 e a 3 mudam o que vale; a 2 não muda nada; o planejador mais forte só anota)
  if p_opcao in (1, 3) and r0.item <> 'solver' then
    insert into public.agenda_acoes (dia, executada, origem, tipo, critica, pergunta_id, texto, antes, depois, desfazivel_ate,
                                     autor, criada_em)
    values (p_hoje, true, 'dono', 'aprendizado', true, v_q.id, left(public._agenda_corta(v_txt, 400), 400),
            jsonb_build_object('item', r0.item, 'chave', r0.chave, 'nivel', r0.nivel, 'em_uso', r0.em_uso, 'valor', v_efet,
                               'estado', r0.estado)
              || case when v_carga is not null then jsonb_build_object('carga_max', v_carga) else '{}'::jsonb end,
            jsonb_build_object('item', r0.item, 'chave', r0.chave, 'nivel', r0.nivel, 'em_uso', r.em_uso, 'n', r0.n,
                               'opcao', p_opcao)
              || case when v_carga is not null then jsonb_build_object('carga_max', r0.calculado) else '{}'::jsonb end,
            p_agora + cf.desfazer_validade, p_autor, p_agora)
    returning id into v_acao;
    r.acao_id := v_acao;
  end if;

  -- o histórico: em uso, estado e calculado, quando mudam (os 20 mais novos)
  foreach k in array array['em_uso', 'estado', 'calculado'] loop
    if to_jsonb(r0) -> k is distinct from to_jsonb(r) -> k then
      v_antes := v_antes || jsonb_build_object(k, to_jsonb(r0) -> k);
      v_depois := v_depois || jsonb_build_object(k, to_jsonb(r) -> k);
    end if;
  end loop;
  v_hist := r0.historico;
  if v_antes <> '{}'::jsonb then
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', v_antes, 'depois', v_depois,
                                                             'decisao', p_opcao));
    if jsonb_array_length(v_hist) > 20 then
      select jsonb_agg(x order by o) into v_hist
        from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
    end if;
  end if;
  update public.agenda_aprendizado
     set em_uso = r.em_uso, estado = r.estado, em_uso_desde = r.em_uso_desde, travado_ate = r.travado_ate,
         travado_valor = r.travado_valor, texto = r.texto, acao_id = r.acao_id, historico = v_hist
   where id = r0.id;

  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'item', r0.item, 'chave', r0.chave,
                            'estado', r.estado, 'em_uso', r.em_uso);
end;
$function$;

comment on function public._agenda_aprendizado_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): a resposta do dono à pergunta crítica aprendizado (spec-fase6 §3.2, §5.6) — só com a pergunta aberta, a linha de agenda_aprendizado nela e o item ligado (modo_aprendizado ligado e na lista; senão "O aprendizado está em teste"). 1 = o medido passa a valer (em_uso; na carga, agenda_config.carga_max muda por _agenda_aprendizado_carga) e a ação crítica aprendizado (origem dono, desfazível por desfazer_validade; o planejador mais forte só anota, sem ação); 2 = trava (travado_valor = o medido; o que vale continua); 3 = volta ao padrão (em_uso nulo) e trava, com a ação. A pergunta fica respondida. Chamada por agenda_decidir. Definer, sem grant. CORREÇÃO FASE 6 (C1, regressão B2): toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do 1º for update.';

-- _agenda_desfazer_aprendizado (de 20261029100600_agenda_fase6_rodada.sql)
create or replace function public._agenda_desfazer_aprendizado(p_acao uuid, p_autor uuid, p_via text, p_hoje date,
                                                               p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_a      public.agenda_acoes%rowtype;
  r0       public.agenda_aprendizado;
  r        public.agenda_aprendizado;
  v_volta  numeric;
  v_d      jsonb;
  v_txt    text;
  v_acao   uuid;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 6: (C1) regressão B2: o *desfaz* do aprendizado toma a trava da rodada do aprendizado (agenda_aprender) ANTES de travar
  -- qualquer linha: a rodada trava agenda_aprendizado e depois agenda_perguntas; a decisão, o contrário. Com a mesma trava
  -- primeiro, as duas se enfileiram (sem o 40P01 quando o dono responde durante a rodada das 16:00).
  perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  -- CORREÇÃO FASE 6: fim
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found or v_a.tipo <> 'aprendizado' then
    raise exception 'Não encontrei essa mudança do aprendizado.' using errcode = 'P0002';
  end if;
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste do aprendizado: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false, 'texto', 'Não dá mais para desfazer esse aprendizado: passou o prazo.');
  end if;
  select * into r0 from public.agenda_aprendizado a
   where a.item = v_a.antes ->> 'item' and a.chave = v_a.antes ->> 'chave' for update;
  if not found or r0.em_uso is distinct from (v_a.depois ->> 'em_uso')::numeric then
    return jsonb_build_object('ok', false, 'texto', 'Esse aprendizado já mudou depois dessa mudança: não há o que desfazer nela.');
  end if;
  if v_a.depois ? 'carga_max' then
    if not public._agenda_aprendizado_carga((v_a.depois ->> 'carga_max')::numeric, (v_a.antes ->> 'carga_max')::numeric,
                                            p_autor, p_agora) then
      return jsonb_build_object('ok', false,
        'texto', format('A parte da semana de cada pessoa mudou depois (hoje %s): não há o que desfazer nessa mudança.',
                        public._agenda_aprendizado_valor('carga', cf.carga_max)));
    end if;
  end if;

  r := r0;
  r.em_uso := (v_a.antes ->> 'em_uso')::numeric;
  r.em_uso_desde := case when r.em_uso is not null then p_agora end;
  r.estado := 'travado';
  r.travado_ate := p_hoje + cf.aprender_trava_dias;
  r.travado_valor := coalesce(r0.calculado, (v_a.depois ->> 'em_uso')::numeric);
  v_volta := coalesce((v_a.antes ->> 'carga_max')::numeric, r.em_uso, r0.padrao);
  v_d := jsonb_build_object('chave', r0.chave, 'calculado', r0.calculado, 'em_uso', r.em_uso, 'efetivo', v_volta,
                            'padrao', r0.padrao, 'volta', v_volta, 'n', r0.n, 'n_min', r0.n_min,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', cf.aprender_trava_dias, 'detalhe', r0.detalhe);
  v_txt := public._agenda_aprendizado_texto(r0.item, 'desfeito', v_d);
  r.texto := left(public._agenda_corta(public._agenda_aprendizado_texto(r0.item, 'foco_travado', v_d), 400), 400);

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, critica, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', false,
          jsonb_build_object('acao', v_a.id),
          jsonb_build_object('item', r0.item, 'chave', r0.chave, 'em_uso', r.em_uso, 'travado_ate', r.travado_ate)
            || case when v_a.depois ? 'carga_max' then jsonb_build_object('carga_max', v_a.antes -> 'carga_max') else '{}'::jsonb end,
          left(public._agenda_corta(v_txt, 400), 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  foreach k in array array['em_uso', 'estado', 'calculado'] loop
    if to_jsonb(r0) -> k is distinct from to_jsonb(r) -> k then
      v_antes := v_antes || jsonb_build_object(k, to_jsonb(r0) -> k);
      v_depois := v_depois || jsonb_build_object(k, to_jsonb(r) -> k);
    end if;
  end loop;
  v_hist := r0.historico;
  if v_antes <> '{}'::jsonb then
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', v_antes, 'depois', v_depois,
                                                             'desfeita', v_a.id));
    if jsonb_array_length(v_hist) > 20 then
      select jsonb_agg(x order by o) into v_hist
        from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
    end if;
  end if;
  update public.agenda_aprendizado
     set em_uso = r.em_uso, estado = r.estado, em_uso_desde = r.em_uso_desde, travado_ate = r.travado_ate,
         travado_valor = r.travado_valor, texto = r.texto, historico = v_hist
   where id = r0.id;

  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'item', r0.item, 'chave', r0.chave,
                            'em_uso', r.em_uso, 'travado_ate', r.travado_ate);
end;
$function$;

comment on function public._agenda_desfazer_aprendizado(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): o *desfaz* da ação aprendizado (spec-fase6 §5.6) — a que entrou sozinha (origem vigia) ou a da decisão 1/3 (origem dono): o em_uso de antes volta (nulo = o padrão) e a chave fica travada por aprender_trava_dias (travado_valor = o medido recusado); a da carga volta agenda_config.carga_max (só se ainda é a que a decisão gravou). Só dentro de desfazivel_ate e com a linha ainda como a ação a deixou. A ação desfazer (desfaz_a) e desfeita_* na original. Chamada por agenda_desfazer. Definer, sem grant. CORREÇÃO FASE 6 (C1, regressão B2): toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do 1º for update.';

-- agenda_decidir (de 20261029100600_agenda_fase6_rodada.sql)
create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  -- CORREÇÃO FASE 6: (C1) regressão B2: a pergunta do aprendizado toma a trava da rodada do aprendizado ANTES de travar a
  -- pergunta (é aqui, e não em _agenda_aprendizado_decidir, que a linha da pergunta é travada primeiro); as outras não
  if exists (select 1 from public.agenda_perguntas q where q.id = p_pergunta and q.tipo = 'aprendizado') then
    perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  end if;
  -- CORREÇÃO FASE 6: fim
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  -- FASE 3: a diária (a pergunta crítica que diverge e a de ligar a OS) tem o efeito dela e o modo dela (modo_diaria):
  -- _agenda_decidir_diaria (20261026100300).
  if v_q.tipo in ('diaria', 'diaria_ligar') then
    return public._agenda_decidir_diaria(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 5: a mensagem ao cliente (cliente_aprovar, a aprovação dos primeiros dias, e cliente_aviso, a crítica do aviso de
  -- atraso) tem o efeito dela e o modo dela (modo_cliente): _agenda_cliente_decidir (20261028100300).
  if v_q.tipo in ('cliente_aprovar', 'cliente_aviso') then
    return public._agenda_cliente_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_agora);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) a pergunta do aprendizado (a troca grande de um valor medido, a carga de cada pessoa pelo plano cumprido e
  -- o planejador mais forte) tem o efeito dela e o modo dela (modo_aprendizado e aprendizado_ligados):
  -- _agenda_aprendizado_decidir (20261029100600). A opção 1 da carga é a única escrita de parâmetro (carga_max), com *desfaz*.
  if v_q.tipo = 'aprendizado' then
    return public._agenda_aprendizado_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista). CORREÇÃO FASE 6 (C1, regressão B2): a pergunta do aprendizado toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do for update da pergunta.';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A nova leitura do fornecedor da medida (invoker, a RLS de quem lê vale): é lida pela prontidão, que authenticated e
-- service_role leem; nunca anon. O dia da conclusão: só de dentro da medição (definer) e da rodada; sem grant a ninguém.
revoke all on function public._agenda_fornecedor_da_medida(uuid) from public, anon;
grant execute on function public._agenda_fornecedor_da_medida(uuid) to authenticated, service_role;
revoke all on function public._agenda_concluida_em(uuid) from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public.os_prontidao(uuid, date), public._agenda_presenca_aprendida(uuid), public.os_plano_da_os(uuid, date)
  from public, anon;
grant execute on function public.os_prontidao(uuid, date), public._agenda_presenca_aprendida(uuid), public.os_plano_da_os(uuid, date)
  to authenticated, service_role;
revoke all on function public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date),
  public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz),
  public.agenda_aprender(date, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  from public, anon, authenticated;
grant execute on function public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date),
  public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz),
  public.agenda_aprender(date, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  to service_role;
revoke all on function public._agenda_aprender_fornecedor(date, timestamptz),
  public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid),
  public.agenda_medir_os(uuid, date), public._agenda_aprender_medir(date),
  public._agenda_aprender_capacidade(date, timestamptz), public._agenda_aprender_presenca(date, timestamptz),
  public._agenda_aprender_cliente(date, timestamptz), public._agenda_vigia_estouro(date, timestamptz),
  public._agenda_aprendizado_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public._agenda_desfazer_aprendizado(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated, service_role;
