-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P2: o porquê gravado no motor — cada alocação nova guarda, na hora
-- em que nasce, o que o motor supôs (as suposições, com o detalhe daquele dia) e o degrau do reparo; cada ação que mexe no plano guarda a zona do dia tocado e o
-- degrau. Nada disso muda decisão: o motor decide igual, e o porquê só é escrito ao gravar e com modo_porque fora de desligado.
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§3.1 itens 2 a 5, §5.2, §8.3 agenda_fase7g_porque.sql e o bloco R9, que vale sobre o corpo: R9.1, R9.4-1,
-- R9.5-1 a 4 e 16, R9.8, R9.12-3, R9.12-10, R9.13); nomes: fase7-registro.md; o registro do pacote: notas-fase7g.md (seção P2).
-- Depende das Fases 1 a 6, das etapas 7a a 7d, da 7f inteira, da 7e até o P6 (a origem de agenda_propor é a 20261111100300, a 7e P4) e da base da 7g
-- (20261112100000: as colunas, o CHECK das suposições, _agenda_degrau e _agenda_zona_mais_severa).
--
-- ═══ DDL — OK NOMEADO ═══ (2 funções recriadas; 3 funções novas, 2 delas de gatilho; 2 gatilhos novos, em agenda_alocacoes e em agenda_acoes)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: a agenda marca sem guardar por quê. Ler o porquê depois ("contei 7 dias úteis de entrega do Cerbo") só é honesto se ele for gravado na hora: o
-- fornecedor pode ter sido dito depois, e a leitura de hoje diria outra coisa (§3.1 item 2).
--
-- O QUE MUDA (com modo_porque desligado, nada: os 2 blocos e os 2 gatilhos olham o modo antes de qualquer outra coisa):
--   1. _agenda_suposicoes_da_os (nova): as suposições de uma OS na hora de marcar, [{codigo, detalhe}] na ordem do §3.1 item 3, lidas do que o motor já leu
--      (a prontidão e os meios da OS, que ele passa) e de poucas leituras próprias. As fontes de cada código estão no comentário da função (R9.5-1 a 4).
--   2. agenda_propor (recriada de 20261111100300_agenda_fase7e_folga.sql:1369; md5 do corpo de antes b22c2eab30b62c5ea912a742c13956ef): o item criar ganha a chave porque = {suposicoes, degrau} só ao gravar (p_persistir) e
--      com modo_porque fora de desligado (R9.4-1, R9.8). Em simulação, nenhuma chamada nova e o item é o de antes, byte a byte. A chave suposicoes do item (o
--      texto do 7d, que o foco locais lê) não muda (R9.4-1). O insert não muda: quem grava na alocação é o gatilho do item 3. Uma falha no cálculo não derruba o
--      motor: o item fica sem porque e o erro vai para app_error_logs (explicar:porque).
--   3. _agenda_alocacoes_porque (nova, gatilho BEFORE INSERT agenda_alocacoes_porque, que roda pelo nome depois de agenda_alocacoes_criterio e
--      agenda_alocacoes_fonte): (a) com substitui_id, as suposições da substituída (e, com modo_porque ligado, o critério dela quando a nova chega sem); o
--      degrau não, porque substituir sem mudar o lugar não é reparo; (b) senão, com a proposta, o porque do item criar da alocação (pelo alocacao_id); (c) a
--      proposta do gestor (parametros.gestor: a escada, a dupla e o corte, que não passam pelo motor): as suposições da alocação mais nova da OS que tem, e o
--      degrau de parametros.gestor.degrau. Sem nada disso (o corte), fica nula: não se afirma o que não foi guardado. Os 3 escritores do gestor não são
--      recriados (R9.4-1).
--   4. _agenda_alocacoes_imutavel (recriada de 20261102100100_agenda_fase7c_motor.sql:3289; md5 do corpo de antes 112b4e2ed6640e4bb2a102d90f134b1b): suposicoes e degrau entram na tupla que a publicada, a fixada e a
--      cancelada não mudam (§5.2). duracao_fonte (da 7a) fica fora: pô-la mudaria o que vale para ela em todo modo, inclusive desligado.
--   5. _agenda_acoes_porque (nova, gatilho BEFORE INSERT agenda_acoes_porque, SECURITY DEFINER): na ação executada que cria, move, cancela, promove, solta,
--      publica, fixa, repara ou reestima (R9.5-16), a zona mais severa dos meios-dias tocados (_agenda_zona da 7f) e o degrau do antes para o depois. Ação
--      sem as alocações no antes/depois: a zona pelos ids, degrau nulo. Uma falha não derruba a ação: zona e degrau nulos e o erro em app_error_logs
--      (explicar:acao). É definer porque quem insere ação pode ser o service_role, e _agenda_zona não tem porta para ele (o molde de _agenda_perguntas_padrao, 7f P1).
--
-- O QUE NÃO MUDA: o que o motor decide, os textos, as perguntas, o que agenda_aplicar publica e as ações que ele grava (as chaves de antes); os 7 escritores de
-- alocação (agenda_propor, a escada, o corte, a dupla, o puxar, agenda_desfazer e _agenda_desfazer_cliente) não mudam o insert. Nenhuma mensagem nova. Nada lê
-- o porquê ainda (o P3 lê).
--
-- ORDEM DE LIGAR (spec R9.14): depois da 20261112100000. Aplicar sozinha não muda nada: modo_porque fica como estiver (desligado até o dado 20261112100990).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_porque.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100100_agenda_fase7g_porque.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100100', 'agenda_fase7g_porque');"
--
-- DESFAZER (na ordem):
--   drop trigger if exists agenda_acoes_porque on public.agenda_acoes;
--   drop trigger if exists agenda_alocacoes_porque on public.agenda_alocacoes;
--   drop function if exists public._agenda_acoes_porque(), public._agenda_alocacoes_porque(), public._agenda_suposicoes_da_os(uuid, jsonb, jsonb, date);
--   agenda_propor e _agenda_alocacoes_imutavel voltam pelo corpo da origem (acima). As colunas que estes gatilhos encheram ficam (são da 20261112100000).
--
-- IDEMPOTENTE: create or replace function, drop trigger if exists + create trigger, revoke/grant e comment.

-- ── 1. As suposições de uma OS na hora de marcar ─────────────────────────────────────────────────────
-- §3.1 item 3 com o R9.5: a ordem é a do quanto costuma errar (a ordem do "1 motivo" do P3). Cada código só entra com o fato que o sustenta, lido do que o motor
-- usou: p_info = {pront, meios} da OS (o v_info de agenda_propor: os_prontidao e agenda_meios_da_os de p_hoje) e p_alocs = as alocações do bloco
-- ([{payee_id, nome, dia, turno, presenca}]). Datas só de p_hoje. Sem linha em os_planejamento (o caso comum, R9.12-3), os campos dela são nulos.
create or replace function public._agenda_suposicoes_da_os(p_os uuid, p_info jsonb, p_alocs jsonb, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_pront jsonb := case when jsonb_typeof(p_info -> 'pront') = 'object' then p_info -> 'pront' else '{}'::jsonb end;
  v_meios jsonb := case when jsonb_typeof(p_info -> 'meios') = 'object' then p_info -> 'meios' else '{}'::jsonb end;
  v_mat   jsonb;
  v_res   jsonb;
  v_alocs jsonb := case when jsonb_typeof(p_alocs) = 'array' then p_alocs else '[]'::jsonb end;
  v_dono  uuid := public._agenda_dono(null);
  v_s     jsonb := '[]'::jsonb;
  v_pl    record;
  v_itens text[];
  v_du    int;
  v_n     int;
  v_lr    jsonb;
  v_bem   text;
  v_pres  jsonb;
  v_nomes text[];
begin
  v_mat := case when jsonb_typeof(v_pront #> '{material,itens}') = 'array' then v_pront #> '{material,itens}' else '[]'::jsonb end;
  v_res := case when jsonb_typeof(v_pront -> 'restricoes') = 'array' then v_pront -> 'restricoes' else '[]'::jsonb end;
  select pl.dias, pl.estimativa_fonte, pl.tempo_compra_marcado, pl.dupla_dita, pl.precisa_ate,
         coalesce(not isempty(pl.bem_indisponivel), false) as bem_fora
    into v_pl
    from public.os_planejamento pl where pl.service_order_id = p_os;

  -- prazo_padrao_peca: a peça crítica em falta cujo prazo é o padrão da empresa (a classe padrao da prontidão, regra prazo_padrao do 7a), na ordem da prontidão
  select array_agg(coalesce(nullif(btrim(e ->> 'curto'), ''), 'peça') order by o), max((e ->> 'prazo_du')::int)
    into v_itens, v_du
    from jsonb_array_elements(v_mat) with ordinality t(e, o)
   where e ->> 'situacao' = 'falta' and e ->> 'classe' = 'padrao' and coalesce((e ->> 'critico')::boolean, true);
  if cardinality(v_itens) > 0 and v_du is not null then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'prazo_padrao_peca', 'detalhe', jsonb_build_object('itens', to_jsonb(v_itens), 'du', v_du)));
  end if;

  -- quanto_falta_padrao: os dias gravados pelo gestor quando a pergunta do "quanto falta?" (a situacao do 7a, OS começada) venceu sem resposta, e é com
  -- eles que o motor marca (a fonte orcamento gravada, em uso)
  if v_meios ->> 'fonte' = 'orcamento' and v_pl.estimativa_fonte = 'orcamento' and v_pl.dias is not null
     and exists (select 1 from public.agenda_perguntas q
                  where q.id = (select x.pergunta_id from public.agenda_acoes x
                                 where x.service_order_id = p_os and x.tipo = 'estimar' and x.executada and x.desfeita_em is null
                                 order by x.criada_em desc, x.id desc limit 1)
                    and q.tipo = 'situacao' and q.estado = 'resolvida' and q.opcao_escolhida is not null) then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'quanto_falta_padrao', 'detalhe', jsonb_build_object('dias', trim_scale(v_pl.dias))));
  end if;

  -- local_suposto (R9.5-1): como o motor, só quando ele leu o local (um dos 4 modos do 7d ligado, pelo _agenda_local_modo: com o freio, em teste) e o local
  -- foi suposto (pelo pátio, pela cidade ou pelo cadastro do bem). O detalhe leva o lugar já com a preposição (texto_curto, AG7-18)
  if public._agenda_local_modo('calendario') = 'ligado' or public._agenda_local_modo('patio') = 'ligado'
     or public._agenda_local_modo('viagem') = 'ligado' or public._agenda_local_modo('mesmo_local') = 'ligado' then
    v_lr := public._agenda_local_resolvido(p_os, p_hoje);
    if coalesce((v_lr ->> 'suposicao')::boolean, false) and v_lr ->> 'fonte' in ('patio', 'cidade', 'bem')
       and nullif(btrim(v_lr ->> 'texto_curto'), '') is not null then
      v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'local_suposto', 'detalhe',
               jsonb_build_object('local', btrim(v_lr ->> 'texto_curto'), 'fonte', v_lr ->> 'fonte')
               || case when v_lr ->> 'fonte' = 'bem'
                       then jsonb_build_object('bem', case public._agenda_classe_de_campo(p_os) ->> 'bem' when 'rv' then 'motorhome' when 'barco' then 'barco'
                                                           else 'bem' end)
                       else '{}'::jsonb end));
    end if;
  end if;

  -- bem_disponivel: o barco numa semana de temporada (temporada_meses, 7d) sem nada dito sobre o uso dele (bem_indisponivel, precisa_ate): o motor sempre lê os
  -- dias em que o bem está fora, e sem eles conta o barco livre
  if public._agenda_classe_de_campo(p_os) ->> 'bem' = 'barco' and not coalesce(v_pl.bem_fora, false) and v_pl.precisa_ate is null
     and exists (select 1 from jsonb_array_elements(v_alocs) a
                  where a ->> 'dia' is not null and extract(month from (a ->> 'dia')::date)::smallint = any (cf.temporada_meses)) then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'bem_disponivel', 'detalhe', jsonb_build_object('bem', 'barco')));
  end if;

  -- disponibilidade_suposta (AG7-03): quem está no bloco sem os dias declarados para aquela semana (_agenda_dias_declarados do 7b: a semente do histórico, ou o
  -- padrão que não foi o dono quem disse = a última dita). A semana dita e o padrão do dono são declarados. O dono não entra. Na ordem do 1º meio-dia de cada um
  v_nomes := array(
    select y.nome
      from (select coalesce(nullif(btrim(a ->> 'nome'), ''),
                            (select public._agenda_nome_curto(py.name) from public.payees py where py.id = (a ->> 'payee_id')::uuid)) as nome,
                   (a ->> 'payee_id')::uuid as payee,
                   min((a ->> 'dia') || case when a ->> 'turno' = 'tarde' then '2' else '1' end) as primeiro
              from jsonb_array_elements(v_alocs) a
             where coalesce(a ->> 'presenca', 'turno') = 'turno' and a ->> 'payee_id' is not null and a ->> 'dia' is not null
               and (a ->> 'payee_id')::uuid is distinct from v_dono
             group by 1, 2) y
     where y.nome is not null
       and exists (select 1
                     from (select distinct (a ->> 'dia')::date - (extract(isodow from (a ->> 'dia')::date)::int - 1) as seg
                             from jsonb_array_elements(v_alocs) a
                            where (a ->> 'payee_id')::uuid = y.payee and a ->> 'dia' is not null) s
                     cross join lateral (select public._agenda_dias_declarados(y.payee, s.seg) as v) d
                    where d.v ->> 'fonte' = 'historico' or (d.v ->> 'fonte' = 'padrao' and d.v ->> 'origem' is distinct from 'dono'))
     order by y.primeiro, y.nome, y.payee);
  if cardinality(v_nomes) > 0 then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'disponibilidade_suposta', 'detalhe', jsonb_build_object('pessoas', to_jsonb(v_nomes))));
  end if;

  -- compra_interna_padrao: a compra em falta com "compre até" que contou o tempo interno (compra_firme da prontidão, regra do 7a), e o tempo é o parâmetro:
  -- sem o congelado na marcação (tempo_compra_marcado) e sem o número do medido no item (tempo_interno_du, que a prontidão só põe quando difere do parâmetro)
  if v_pl.tempo_compra_marcado is null
     and exists (select 1 from jsonb_array_elements(v_mat) e
                  where e ->> 'situacao' = 'falta' and coalesce((e ->> 'compra_firme')::boolean, false) and e ->> 'compre_ate' is not null
                    and not e ? 'tempo_interno_du') then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'compra_interna_padrao', 'detalhe', jsonb_build_object('du', cf.compra_interna_du)));
  end if;

  -- sinal_a_cobrar: o sinal combinado e não pago (a restrição sinal da prontidão) não segurou a data: a OS está sendo marcada assim mesmo
  if exists (select 1 from jsonb_array_elements(v_res) e where e ->> 'tipo' = 'sinal') then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'sinal_a_cobrar', 'detalhe', '{}'::jsonb));
  end if;

  -- duracao_orcamento: a duração é a estimativa pelo orçamento (fonte orcamento dos meios, D7-1), com a mão de obra que a sustenta (os_duracao_sugerida)
  if v_meios ->> 'fonte' = 'orcamento' and (v_meios ->> 'dias')::numeric > 0 then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'duracao_orcamento', 'detalhe',
             jsonb_build_object('dias', (v_meios ->> 'dias')::numeric, 'mo', nullif((public.os_duracao_sugerida(p_os) ->> 'mo')::numeric, 0))));
  end if;

  -- uma_pessoa (AG7-04): nem equipe dita nem dupla dita (os_planejamento.dupla_dita nula), e cada meio-dia do bloco com 1 pessoa só
  if not coalesce((v_meios ->> 'equipe_dita')::boolean, false) and v_pl.dupla_dita is null
     and coalesce((select max(k.n) from (select count(*) as n from jsonb_array_elements(v_alocs) a
                                          where coalesce(a ->> 'presenca', 'turno') = 'turno'
                                          group by a ->> 'dia', a ->> 'turno') k), 0) = 1 then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'uma_pessoa', 'detalhe', '{}'::jsonb));
  end if;

  -- peca_nao_segura (AG7-05): os itens que a regra do valor deixou de fora do crítico (separar_vespera da prontidão: sem o fato do dono e abaixo de
  -- critico_valor_min) e ainda não estão na mão
  select count(*)::int into v_n
    from jsonb_array_elements(v_mat) e
   where coalesce((e ->> 'separar_vespera')::boolean, false) and e ->> 'situacao' is distinct from 'na_mao';
  if v_n > 0 then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'peca_nao_segura', 'detalhe', jsonb_build_object('n', v_n, 'limiar', cf.critico_valor_min)));
  end if;

  -- sem_peca: a OS sem nenhuma linha de material, marcada como sem peça a comprar (a restrição sem_peca_suposta da prontidão, regra sem_peca do 7a)
  if exists (select 1 from jsonb_array_elements(v_res) e where e ->> 'tipo' = 'sem_peca_suposta') then
    v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'sem_peca', 'detalhe', '{}'::jsonb));
  end if;

  -- dono_abre_fecha (R9.5-2): o bloco tem a abertura ou o fechamento do dono, e a presença dele é a da regra (nada dito), a do abre e fecha
  if exists (select 1 from jsonb_array_elements(v_alocs) a where a ->> 'presenca' in ('abertura', 'fechamento')) then
    v_pres := public.os_presenca_do_dono(p_os);
    if coalesce(v_pres ->> 'fonte', 'regra') = 'regra' and v_pres ->> 'presenca' = 'abre_e_fecha' then
      v_s := v_s || jsonb_build_array(jsonb_build_object('codigo', 'dono_abre_fecha', 'detalhe', '{}'::jsonb));
    end if;
  end if;

  return v_s;
end;
$function$;

comment on function public._agenda_suposicoes_da_os(uuid, jsonb, jsonb, date) is
  'Agenda de Produção (Fase 7g, P2; §5.2, §3.1 item 3, R9.5-1 a 4): as suposições de uma OS na hora de marcar, [{codigo, detalhe}] na ordem do §3.1 item 3, só com o fato que sustenta cada uma: prazo_padrao_peca {itens, du} (a peça crítica em falta com a classe padrao da prontidão); quanto_falta_padrao {dias} (os dias gravados quando a pergunta situacao venceu sem resposta, fonte orcamento em uso); local_suposto {local, fonte, bem} (_agenda_local_resolvido.suposicao, só com um modo do local ligado, como o motor); bem_disponivel {bem} (barco em mês de temporada sem bem_indisponivel nem precisa_ate); disponibilidade_suposta {pessoas} (_agenda_dias_declarados: a semente, ou o padrão que não foi o dono quem disse; sem o dono); compra_interna_padrao {du} (compra_firme com compre até, sem tempo_compra_marcado nem tempo_interno_du); sinal_a_cobrar (a restrição sinal); duracao_orcamento {dias, mo} (fonte orcamento); uma_pessoa (sem equipe nem dupla dita, 1 pessoa por meio-dia); peca_nao_segura {n, limiar} (separar_vespera fora da mão); sem_peca (sem_peca_suposta); dono_abre_fecha (abertura ou fechamento no bloco, presença do dono pela regra). p_info = {pront, meios} da OS como o motor leu; p_alocs = as alocações do bloco. STABLE, invoker, sem porta para authenticated: só agenda_propor (definer) a chama, ao gravar.';

-- ── 2. O motor: o porquê no item que entra (recriada da 7e P4) ───────────────────────────────────────
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
  -- FASE 7: (7a P8) a zona travada: o que fica fora da conta do dia já avisado
  v_f7_fora uuid[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4) a dupla por meio-dia, o prazo firme, o sábado e as linhas em teste
  v_7b_pk     int[];
  v_7b_dk     int[];
  v_7b_tot    int;
  v_7b_prazo  date;
  v_7b_n      int;
  v_7b_semtec int;
  v_7b_tec    text[];
  v_7b_teste  text[] := '{}';
  v_7b_b      jsonb;
  v_7b_e      jsonb;
  v_7b_x      text;
  v_7b_y      text;
  v_7b_dias   date[];
  v_7b_nomes  text[];
  v_7b_z      text;
  v_7b_n2     int;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 22 e 23) o exemplo com todos os dias e a dupla dita antes de a OS ficar pronta
  v_7bc_dias date[];
  v_7bc_est  date;
  v_7bc_max  date;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2) o que a OS pede, o responsável, os motivos e os textos da 7c
  v_7c_exg   jsonb;
  v_7c_ld    jsonb;
  v_7c_lp    int;
  v_7c_mot   text[];
  v_7c_txt   text;
  v_7c_d     int;
  v_7c_le    boolean;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achado 9) a troca avisada do responsável no texto do item
  c_c9_max   constant int := 320;   -- estrutural: o item com a frase a mais (o texto da ação junta os itens da OS em até 400)
  v_c9_tr    text;
  v_c9_txt   text;
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4, R6.7b, R6.8-1) os modos da 7d (por _agenda_local_modo: ligado com *gestor, só propor* = em teste) e, por OS da fila, o local
  -- (v_7d_lr), a máscara (v_7d_lm), a viagem (v_7d_vi), o bem (v_7d_bm), a suposição do abre e fecha (v_7d_saf) e as suposições do item
  v_7d_cal   boolean;
  v_7d_pat   boolean;
  v_7d_via   boolean;
  v_7d_ml    boolean;
  v_7d_bem   boolean;
  v_7d_lr    jsonb;
  v_7d_lm    jsonb;
  v_7d_vi    jsonb;
  v_7d_bm    jsonb;
  v_7d_saf   boolean;
  v_7d_sup   text[];
  v_7d_extra int;
  v_7d_x     int;
  v_7d_os    uuid;
  -- FASE 7d: fim
  -- FASE 7d: (correção O15) o feriado do município no texto do item
  v_7d_dt  text;
  v_7d_mf  text;
  -- FASE 7d: fim
  -- FASE 7e: (7e P4, §5.3, R7.5-14, R7.7) a urgência, a carga da semana na frase do item e a OS puxada
  v_7e_ug    boolean;
  v_7e_u     jsonb;
  v_7e_urg   jsonb := '[]'::jsonb;
  v_7e_cm    numeric;
  v_7e_pux   jsonb;
  v_7e_dp    date;
  v_7e_m     text[];
  v_7e_pas   boolean;
  -- FASE 7e: fim
  -- FASE 7g: (7g P2, R9.4-1) o que a OS perdeu nesta proposta, no formato do antes, para o degrau do item
  v_7g_canc  jsonb;
  -- FASE 7g: fim
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
  -- FASE 7d: (7d P4, R6.7b) todo leitor de modo usa _agenda_local_modo, nunca cf.modo_x
  v_7d_cal := public._agenda_local_modo('calendario') = 'ligado';
  v_7d_pat := public._agenda_local_modo('patio') = 'ligado';
  v_7d_via := public._agenda_local_modo('viagem') = 'ligado';
  v_7d_ml := public._agenda_local_modo('mesmo_local') = 'ligado';
  v_7d_bem := public._agenda_local_modo('bem') = 'ligado';
  -- FASE 7d: fim
  -- FASE 7e: (7e P4, §5.3, R7.6, R7.8, R7.12-10) o portão: com a urgência fora de ligado ou com o freio, nenhuma chamada nova e nenhuma chave. Quem decide é _agenda_margem_modo. A lista de urgentes é só o motor quem faz: a que vier de fora sai (ela levaria o validador a 100%). A OS puxada (P4b) chega em puxar.
  v_7e_ug := case when cf.modo_urgencia = 'ligado' and not cf.gestor_so_propor then public._agenda_margem_modo('urgencia') = 'ligado' else false end;
  v_7e_cm := cf.carga_max;
  v_r := v_r - 'urgentes';
  v_7e_pux := v_r -> 'puxar';
  v_7e_dp := (v_7e_pux ->> 'dia')::date;
  -- FASE 7e: fim
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
  -- FASE 7e: (7e P4, §5.3 (b)) com puxar, as células do dia de quem não está em puxar.pessoas ficam sem capacidade: o turno da OS puxada só cai em quem já vem. A ponta do dono (abrir e fechar) não muda, e o validador a aceita. Sem puxar, nada muda.
  if v_7e_dp is not null then
    v_ctx := jsonb_set(v_ctx, '{cap}', (
      select jsonb_agg(case when ((t.o - 1) % n.nh) / 2 + 1 = v_7e_dp - v_ini + 1
                             and not ((v_7e_pux -> 'pessoas') ? (v_ctx -> 'pessoas' ->> ((t.o - 1) / n.nh)::int))
                            then 0 else t.x::int end order by t.o)
        from jsonb_array_elements_text(v_ctx -> 'cap') with ordinality t(x, o)
        cross join (select (v_ctx ->> 'nh')::bigint as nh) n));
  end if;
  -- FASE 7e: fim
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
    -- FASE 7d: (7d P4, §5.4 1, R6.8-1) o local no motor, só com calendario, patio, viagem ou mesmo_local ligado: em teste, nenhuma chamada. O dia que
    -- o local não recebe entra em v_bem; a entrada do bem, no EST; os dias desde a retirada, em v_bem. A viagem fora da região não tem abre e
    -- fecha; o custo dela em meios-dias entra no item da fila, lá embaixo, depois da dupla da 7b, que lê v_passos. Com modo_bem ligado, o
    -- estado do bem, para a suposição gravada.
    v_7d_lr := null;
    v_7d_lm := null;
    v_7d_vi := null;
    v_7d_bm := null;
    v_7d_saf := false;
    if v_7d_cal or v_7d_pat or v_7d_via or v_7d_ml then
      v_7d_lr := public._agenda_local_resolvido(v_os, p_hoje);
      if v_7d_cal or v_7d_pat then
        v_7d_lm := public._agenda_local_mascara(v_os, v_ini, v_fim, p_hoje, v_7d_lr);
      end if;
      if v_7d_cal then
        v_bem := v_bem || public._agenda_ints(v_7d_lm -> 'dias');
      end if;
      if v_7d_pat and (v_7d_lm ->> 'ent')::int > 0 then
        v_est := greatest(v_est, v_ini + (v_7d_lm ->> 'ent')::int - 1);
        v_estc := greatest(v_estc, v_ini + (v_7d_lm ->> 'ent')::int - 1);
      end if;
      if v_7d_pat and (v_7d_lm ->> 'sai')::int > 0 then
        v_bem := v_bem || array(select g from generate_series((v_7d_lm ->> 'sai')::int, v_fim - v_ini + 1) g);
      end if;
      if v_7d_via then
        v_7d_vi := public._agenda_viagem_da_os(v_os, p_hoje, v_7d_lr);
        if coalesce((v_7d_vi ->> 'sem_abre_fecha')::boolean, false) then
          v_7d_saf := v_abre or v_fecha;
          v_abre := false;
          v_fecha := false;
        end if;
      end if;
    end if;
    if v_7d_bem then
      v_7d_bm := public._agenda_estado_do_bem(v_os, p_hoje);
    end if;
    -- FASE 7d: fim
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
    -- FASE 7b: (7b P4, §5.3, R4.3) a entrada da fila, só com os modos da 7b: a dupla por meio-dia (dk = as pessoas dos passos que
    -- restam, os últimos v_passos do molde; dk_dono_conta; a fonte; o texto do cartão); da dupla inferida, o bloco de 1 pessoa
    -- (passos1: ligado com a duração que conserva as diárias-pessoa, a soma do dk — cada meio-dia de dupla vira dois de 1 pessoa —; em
    -- teste ou com os dias ditos pelo dono, os passos de antes), os meios-dias
    -- dela que restam no início e no fim (dupla_ni, dupla_nf; ou dupla_todos) e o nome do que a tarefa pede; o prazo firme (prazo_h =
    -- o índice da tarde de least(precisa_ate, o prometido firme) na grade); e a dupla dita que só passa pela régua dos técnicos com
    -- quem vem sob demanda (dupla_sd: sem eles, a classe daria 4; R4.3(c)).
    v_7b_dk := '{}'::int[];
    if v_meios ? 'dk' then
      v_7b_pk := public._agenda_ints(v_meios #> '{dupla,pk}');
      v_7b_tot := cardinality(v_7b_pk);
      v_7b_dk := case when v_passos > 0 then v_7b_pk[greatest(v_7b_tot - v_passos + 1, 1) : v_7b_tot] else '{}'::int[] end;
      v_e := v_e || jsonb_build_object('dk', to_jsonb(v_7b_dk), 'dk_dono_conta', v_meios -> 'dk_dono_conta',
                                       'dupla_fonte', v_meios #>> '{dupla,fonte}', 'dupla_texto', v_meios #>> '{dupla,texto}');
      if v_meios #>> '{dupla,fonte}' = 'regra' and v_passos > 0 then
        v_e := v_e || jsonb_build_object(
          'passos1', case when (v_meios #>> '{dupla,pm_estimativa}') is not null then (select sum(x)::int from unnest(v_7b_dk) x)
                          else v_passos end,
          'dupla_todos', coalesce((v_meios #>> '{dupla,todos}')::boolean, false),
          'dupla_ni', least(greatest(coalesce((v_meios #>> '{dupla,ni}')::int, 0) - (v_7b_tot - v_passos), 0), v_passos),
          'dupla_nf', least(coalesce((v_meios #>> '{dupla,nf}')::int, 0), v_passos),
          'dupla_rot_ini', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'inicio' order by m ->> 'motivo')),
          'dupla_rot_fim', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'fim' order by m ->> 'motivo')),
          'dupla_rot_todos', (select m ->> 'rotulo' from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                               where m ->> 'onde' = 'todos' limit 1));
      end if;
    end if;
    if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_meios ->> 'presenca' = 'nunca' then
      v_e := v_e || jsonb_build_object('dono_nunca', true);
    end if;
    if cf.modo_sabado <> 'desligado' or v_meios ? 'dk' then
      v_7b_prazo := least(v_pl.precisa_ate, case when v_pl.prometido_tipo = 'firme' then v_pl.prometido_ate end);
      if v_7b_prazo between v_ini and v_fim then
        v_e := v_e || jsonb_build_object('prazo_h', 2 * (v_7b_prazo - v_ini) + 2, 'prazo', v_7b_prazo);
      end if;
    end if;
    if cf.modo_dupla <> 'desligado' and v_pl.dupla_dita in ('todos', 'inicio', 'fim')
       and not coalesce((v_meios ->> 'equipe_dita')::boolean, false) and v_passos > 0 then
      v_7b_n := greatest(coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0),
                         coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
                         coalesce((select max(x) from unnest(v_7b_dk) x), 0)
                         - case when coalesce((v_meios ->> 'dk_dono_conta')::boolean, true)
                                     and (coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false)
                                          or coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end);
      if v_7b_n >= 2 then
        v_7b_semtec := coalesce(v_7b_semtec, (select count(*)::int from jsonb_array_elements(coalesce(
                         public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) x
                        where not coalesce((x ->> 'eh_dono')::boolean, false)));
        if v_7b_semtec < v_7b_n then
          v_e := v_e || jsonb_build_object('dupla_sd', true, 'dupla_n', v_7b_n,
                                           'dupla_meios_n', case when cardinality(v_7b_dk) > 0
                                                                 then (select count(*)::int from unnest(v_7b_dk) x where x >= 2)
                                                                 else v_passos end);
        end if;
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7c: (7c P2, §5.2 1) a entrada da fila ganha o que a OS pede (os_exigencias, sem IA: ext = em todos os meios-dias, exu = no
    -- último, exf 1 = pela linha, exig_texto) — em qualquer modo, porque o critério de cada alocação é gravado sempre — e, só com
    -- modo_lider ou modo_habilidade ligado, o responsável (_agenda_lider_da_os, sem as alocações que a proposta cancela): lid (a
    -- posição na grade; fora dela, 0), lid_duro (o dito ou quem fez, com modo_lider ligado e sem a palavra do dono sobre quem vai),
    -- lid_plan (o planejado: só desempata) e lid_fora (o responsável que não está na grade). Só a OS que vai ao encaixe (fora da
    -- classe 4, com passos ou o pátio) é lida. O que a OS pede só é lido com a porta de os_exigencias aberta (o service_role, sem
    -- login, ou o admin/financeiro logado): a técnica logada que marca pela tela (agenda_marcar_os, liberada a authenticated) chega
    -- aqui e receberia o 42501 dela no meio do motor; para ela, a OS "não pede ninguém em especial" (a escolha de antes; o pedido dela
    -- tem a pessoa, a palavra de quem marca, e os filtros 3 a 5 não valem de todo jeito).
    if v_7c_le is null then
      begin
        v_7c_le := case when auth.uid() is not null then public.is_admin_or_financial(auth.uid())
                        else coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') in ('', 'service_role') end;
      exception when others then
        v_7c_le := false;
      end;
    end if;
    if v_7c_le and v_classe <> 4 and (v_passos > 0 or v_pat_p > 0) then
      v_7c_exg := public.os_exigencias(v_os, p_hoje);
      v_e := v_e || jsonb_build_object('ext', coalesce((v_7c_exg ->> 'todos')::int, 0), 'exu', coalesce((v_7c_exg ->> 'ultimo')::int, 0),
                                       'exf', coalesce((v_7c_exg ->> 'fonte_texto')::int, 0), 'exig_texto', v_7c_exg ->> 'texto_curto');
      if cf.modo_lider = 'ligado' or cf.modo_habilidade = 'ligado' then
        v_7c_ld := public._agenda_lider_da_os(v_os, p_hoje, v_ign);
        if v_7c_ld is not null then
          v_7c_lp := array_position(v_pes, (v_7c_ld ->> 'payee_id')::uuid);
          v_e := v_e || jsonb_build_object('lid', coalesce(v_7c_lp, 0), 'lid_nome', v_7c_ld ->> 'nome',
                   'lid_duro', v_7c_ld ->> 'fonte' in ('dono', 'fez') and cf.modo_lider = 'ligado' and v_7c_lp is not null
                               and not (coalesce(cardinality(v_pm), 0) + coalesce(cardinality(v_pt), 0) > 0 or v_fixa > 0),
                   'lid_plan', case when v_7c_ld ->> 'fonte' = 'planejado' then coalesce(v_7c_lp, 0) else 0 end,
                   'lid_fora', v_7c_lp is null);
        end if;
      end if;
    end if;
    -- FASE 7c: fim
    -- FASE 7d: (7d P4, §5.4 2, §3.1-5, R6.8-3) a entrada da fila, só com os modos ligados (chave AUSENTE fora disso): fora_h e local_txt (a máscara),
    -- viagem, imax_os, os meios de estrada somados aos passos (depois da dupla da 7b, que corta o molde por v_passos: os meios de estrada
    -- não têm dk e pedem o desejado), local_texto e suposicoes (as da cadeia do local, da viagem e do bem, para o item da proposta)
    if v_7d_lr is not null or v_7d_bm is not null then
      v_7d_sup := '{}';
      if v_7d_lr ->> 'fonte' = 'cidade' or (v_7d_lr ->> 'fonte' = 'bem' and (v_7d_lr ->> 'suposicao')::boolean) then
        v_7d_sup := v_7d_sup || (v_7d_lr ->> 'texto');
      elsif v_7d_lr ->> 'fonte' = 'patio' and v_7d_bm is null then
        v_7d_sup := v_7d_sup || format('supus o motorhome %s', v_7d_lr ->> 'texto_curto');
      end if;
      if coalesce((v_7d_vi ->> 'suposicao')::boolean, false) and v_7d_vi ->> 'tipo' in ('bate_volta', 'pernoite') then
        v_7d_sup := v_7d_sup || public._agenda_viagem_suposicao(v_7d_lr, v_7d_vi ->> 'tipo');
      end if;
      if v_7d_saf then
        v_7d_sup := v_7d_sup || 'supus que você não vai abrir e fechar esse serviço (fora da região)'::text;
      end if;
      v_7d_sup := v_7d_sup || array(select x from jsonb_array_elements_text(coalesce(v_7d_bm -> 'suposicoes', '[]'::jsonb)) x)
                           || array(select x from jsonb_array_elements_text(coalesce(v_7d_lm -> 'notas', '[]'::jsonb)) x);
      v_e := v_e || jsonb_build_object('suposicoes', to_jsonb(v_7d_sup));
      if v_7d_lr is not null then
        v_e := v_e || jsonb_build_object('local_texto', v_7d_lr ->> 'texto', 'local_curto', v_7d_lr ->> 'texto_curto');
      end if;
      if v_7d_cal then
        v_e := v_e || jsonb_build_object('fora_h', v_7d_lm -> 'meios', 'local_txt', v_7d_lm -> 'motivos');
      end if;
      if v_7d_vi is not null then
        v_e := v_e || jsonb_build_object('viagem', v_7d_vi ->> 'tipo')
                   || case when v_7d_vi ->> 'imax_os' is not null then jsonb_build_object('imax_os', (v_7d_vi ->> 'imax_os')::int) else '{}'::jsonb end;
        v_7d_extra := public._agenda_viagem_extra(v_7d_vi ->> 'tipo', (v_7d_vi ->> 'extra_por')::int, v_passos);
        if v_7d_extra > 0 then
          v_e := v_e || jsonb_build_object('passos', v_passos + v_7d_extra)
                     || case when v_e ? 'passos1' then jsonb_build_object('passos1', (v_e ->> 'passos1')::int + public._agenda_viagem_extra(v_7d_vi ->> 'tipo', (v_7d_vi ->> 'extra_por')::int, (v_e ->> 'passos1')::int)) else '{}'::jsonb end;
        end if;
      end if;
    end if;
    -- FASE 7d: fim
    -- FASE 7e: (7e P4, §5.3 (a), R7.8) a OS urgente vai até 100% da semana (teto100, como o pedido do dono), só com passos a marcar. A chave só existe em ligado (R7.13).
    if v_7e_ug and coalesce((v_e ->> 'passos')::int, 0) > 0 then
      v_7e_u := public._agenda_os_urgente(v_os, p_hoje);
      if (v_7e_u ->> 'urgente')::boolean then
        v_e := v_e || jsonb_build_object('urgente', true, 'urgente_texto', v_7e_u ->> 'texto', 'teto100', true);
        v_7e_urg := v_7e_urg || to_jsonb(v_os);
      end if;
    end if;
    -- (§5.3 (b), R7.7-3) a OS puxada: o dia, sem o piso do congelado nem o EST da prontidão (quem chama só puxa OS pronta), mas nunca pisando na máscara do local (a entrada do bem, com o pátio ligado), no que ela já tem marcado nem no "só depois de". Passou de D, a simulação de quem chamou recusa. greatest ignora o nulo de propósito: nulo aqui é "sem essa restrição".
    if v_7e_dp is not null and v_os = (v_7e_pux ->> 'os')::uuid then
      v_e := v_e || jsonb_build_object('teto100', true, 'puxada', true, 'min_h', 2 * (v_7e_dp - v_ini) + 1,
                                       'est', greatest(v_7e_dp, (v_depois ->> v_os::text)::date, v_k.ultimo_fut,
                                                       case when v_7d_pat and (v_7d_lm ->> 'ent')::int > 0 then v_ini + (v_7d_lm ->> 'ent')::int - 1 end) - v_ini + 1);
    end if;
    -- FASE 7e: fim
    v_fila := v_fila || v_e;
  end loop;

  -- FASE 7e: (7e P4, §5.3 (a), R7.12-10) as urgentes vão ao validador e ficam em parametros.p_restricoes para a revalidação ao aplicar. Só com alguma; fora de ligado, nem a chave.
  if jsonb_array_length(v_7e_urg) > 0 then
    v_r := v_r || jsonb_build_object('urgentes', v_7e_urg);
  end if;
  -- FASE 7e: fim
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
  -- FASE 7b: (7b P4) os parâmetros do sábado (modo e política) e da dupla (modo; a espera: ligado, dupla_espera_max_du dias úteis;
  -- em teste, 0 — a dupla só entra quando não termina depois do bloco de 1 pessoa, d8), só com os modos da 7b
  if cf.modo_sabado <> 'desligado' or cf.modo_dupla <> 'desligado' then
    v_par := v_par || jsonb_build_object('sab_modo', cf.modo_sabado, 'sab_politica', cf.sabado_manha, 'dupla_modo', cf.modo_dupla,
                                         'dupla_espera', case when cf.modo_dupla = 'ligado' then cf.dupla_espera_max_du else 0 end);
  end if;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2 2) os parâmetros da 7c, sempre (o encaixe lê a presença deles como "grave o critério"): hab_modo (os
  -- filtros 3 e 4 e a ordem nova, só ligado), lid_modo (o filtro 5 e a troca avisada, só ligado), os níveis, o fechamento que cobre
  -- o último dia e a espera pelo responsável; o v_parh herda
  v_par := v_par || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'lid_modo', (cf.modo_lider = 'ligado')::int,
                                       'n', jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                                                               'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura,
                                                               'par', cf.habilidade_nivel_par),
                                       'fcobre', cf.habilidade_fechamento_cobre, 'lid_espera', cf.lider_espera_max_du);
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4 3, R6.8-3) mesmo_dia, com modo_mesmo_local ligado; troca, ligado e na temporada (o mês de p_hoje em temporada_meses, AG7-20).
  -- Chave AUSENTE fora disso: agenda_propostas.parametros e o M1 comparam
  if v_7d_ml then
    v_par := v_par || jsonb_build_object('mesmo_dia', true);
    if extract(month from p_hoje)::smallint = any (cf.temporada_meses) then
      v_par := v_par || jsonb_build_object('troca', true);
    end if;
  end if;
  -- FASE 7d: fim
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
      -- FASE 7: (7a P8, spec §3.2 e §5.8) a zona travada (a regra zona_travada): a criticidade de novo, agora sabendo o que fica
      -- fora da conta do dia já avisado — o que não pode mais acontecer, o resto do meio-dia dele e o que volta igual neste
      -- encaixe (_agenda_zona_fora; o fixado pelo dono nunca fica fora: a regra dele não muda).
      if public._agenda_gestor_regra('zona_travada') then
        v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
        v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os,
                                             v_f7_fora);
      end if;
      -- FASE 7: fim
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
  -- FASE 7c: (7c P2, §5.2 4, §6.8) o que sai pela violação habilidade (a do P3: a equipe do meio-dia não tem quem o serviço pede) diz
  -- o porquê, no lugar do "replanejado junto"
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade') then
    select coalesce(jsonb_agg(case when i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade'
                                   then i || jsonb_build_object('texto', format('%s: sai %s — a equipe do dia não tinha quem o serviço pede.',
                                          public._agenda_rotulo_da_os((i ->> 'os')::uuid),
                                          public._agenda_dias_texto(array(select (a ->> 'dia')::date from jsonb_array_elements(i -> 'alocacoes') a))))
                                   else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
  end if;
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4 3, §6.2) o que sai pela violação local diz o porquê, no lugar do "replanejado junto"
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'local') then
    select coalesce(jsonb_agg(case when i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'local'
                                   then i || jsonb_build_object('texto', format('%s: sai %s — o local não recebe a equipe nesse dia.',
                                          public._agenda_rotulo_da_os((i ->> 'os')::uuid),
                                          public._agenda_dias_texto(array(select (a ->> 'dia')::date from jsonb_array_elements(i -> 'alocacoes') a))))
                                   else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
  end if;
  -- FASE 7d: fim
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
    -- FASE 7: (7a P8) a zona travada, como no encaixe acima (o que espera a decisão de outra OS segue a de antes)
    if v_b ->> 'tipo' <> 'reserva' and not v_e ? 'fixar_de' and not coalesce((v_b ->> 'espera')::boolean, false)
       and public._agenda_gestor_regra('zona_travada') then
      v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                           v_canc_os, v_f7_fora);
    end if;
    -- FASE 7: fim
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
    -- FASE 7c: (7c P2, §5.2 3, §3.1-3) com modo_habilidade ligado, onde o dono disse quem vai (o pedido com pessoa, a equipe dita), a
    -- palavra dele vale e o item ganha o aviso, ao lado do de material ("— mas João iria sozinho, e o último dia pede quem instala
    -- sozinho com 220 V ou banco de bateria")
    if cf.modo_habilidade = 'ligado' and v_b ->> 'tipo' <> 'reserva'
       and (v_e ? 'fixar_de' or coalesce((v_info -> v_os::text -> 'meios' ->> 'equipe_dita')::boolean, false)) then
      v_aviso := nullif(concat_ws('; ', v_aviso, public._agenda_aviso_da_habilidade(v_os, public._agenda_alocs_do_bloco(v_ctx, v_b), p_hoje)), '');
    end if;
    -- FASE 7c: fim
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
    -- FASE 7d: (correção O15) o feriado do município que o bloco atravessa diz o motivo, como o nacional ("sex 20 é Consciência Negra"): "ter 20 é feriado em Balneário Camboriú".
    -- local_txt só existe com o calendário ligado: sem ele, nenhuma leitura
    if v_e ? 'local_txt' and v_b ->> 'tipo' <> 'reserva' then
      v_7d_dt := public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a));
      v_7d_mf := public._agenda_feriado_do_bloco(v_e -> 'local_txt', v_ini, v_ini_x, v_fim_x);
      if v_7d_mf is not null then
        v_txt := replace(v_txt, ': ' || v_7d_dt || ',', ': ' || case when right(v_7d_dt, 1) = ')' then left(v_7d_dt, -1) || ', ' || v_7d_mf || ')'
                                                                     else v_7d_dt || ' (' || v_7d_mf || ')' end || ',');
      end if;
    end if;
    -- FASE 7d: fim
    -- FASE 7: (7a P3, D7-1) o compromisso marcado pela estimativa do orçamento (a fonte 'orcamento' de agenda_meios_da_os, que
    -- só existe com a regra estimativa) diz isso no fim: "… com Roberto e João (estimativa minha: 6 dias)."
    if v_e ->> 'fonte' = 'orcamento' and v_b ->> 'tipo' <> 'reserva' and right(v_txt, 1) = '.' then
      v_txt := left(v_txt, -1) || format(' (estimativa minha: %s).', public._agenda_dias((v_e ->> 'dias')::numeric));
    end if;
    -- FASE 7: fim
    -- FASE 7b: (7b P4, §6.3, R4.3(a)(3)) ligado: o compromisso com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael
    -- se ofereceu), para cumprir o prazo de qua 18/11."); o bloco de 1 pessoa da dupla inferida diz em que meios-dias a tarefa pede
    -- 2 e o que fazer (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex
    -- está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."). Em teste, nada aqui (a linha "Em teste" abaixo).
    if v_b ? 'sabado' and right(v_txt, 1) = '.' then
      select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
        from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a
       where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
      v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                             from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) with ordinality t(a, o)
                                            where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                           order by y.o);
      v_txt := left(v_txt, -1) || format(' — com %s de manhã (%s %s)%s.', public._agenda_dias_texto(v_7b_dias),
                 public._agenda_lista(v_7b_nomes), case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end,
                 case when v_e ? 'prazo' then ', para cumprir o prazo de ' || public._dia_curto((v_e ->> 'prazo')::date) else '' end);
    end if;
    if v_b ? 'dupla_falta' and cf.modo_dupla = 'ligado' and jsonb_array_length(v_b -> 'dupla_falta') > 0 then
      if v_7b_tec is null then
        v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      end if;
      -- os meios-dias de cada parte: "qua 04/11, manhã e tarde", "qua 04/11 de manhã"
      select public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' in ('inicio', 'todos')) z
                group by z.d order by z.d)),
             public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'fim') z
                group by z.d order by z.d))
        into v_7b_x, v_7b_y;
      v_7b_n := (select count(*)::int from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'inicio');
      v_7b_z := case
        when coalesce((v_e ->> 'dupla_todos')::boolean, false)
          then format('O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      coalesce(v_e ->> 'dupla_rot_todos', 'o orçamento previu 2 técnicos'),
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        when v_7b_x <> '' and v_7b_y <> ''
          then format('%s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_7b_x,
                      v_e ->> 'dupla_rot_ini',
                      case when jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n = 1 then 'no último meio-dia'
                           else format('nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n) end, v_7b_y,
                      v_e ->> 'dupla_rot_fim',
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        else format('%s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                    case when v_7b_x <> '' then case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end
                         when jsonb_array_length(v_b -> 'dupla_falta') = 1 then 'No último meio-dia'
                         else format('Nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta')) end,
                    case when v_7b_x <> '' then v_7b_x else v_7b_y end,
                    case when v_7b_x <> '' then v_e ->> 'dupla_rot_ini' else v_e ->> 'dupla_rot_fim' end,
                    case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                    public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)) end;
      -- (correção da revisão da 7b, achado 23) o exemplo diz todos os dias em que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem
      -- qua 18 e qui 19/11"): quem seguisse o exemplo ao pé da letra deixava os outros meios-dias sem a 2ª pessoa
      v_7bc_dias := array(select distinct v_ini + ((f ->> 'h')::int + 1) / 2 - 1 from jsonb_array_elements(v_b -> 'dupla_falta') f order by 1);
      if cardinality(v_7bc_dias) > 1 then
        v_7b_z := replace(v_7b_z, format('(ex.: Mateus vem %s).', public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)),
                          format('(ex.: Mateus vem %s).', regexp_replace(public._agenda_dias_texto(v_7bc_dias), ' \([^()]*\)$', '')));
      end if;
      -- (correção da revisão da 7b: fim)
      -- o texto da ação (agenda_acoes.texto, até 400) junta os itens da mesma OS: com a frase da dupla, o item fica em até 320 — sem
      -- caber a frase inteira, a curta (sem os dias e sem quem está na equipe)
      if char_length(v_txt) + 1 + char_length(v_7b_z) > 320 then
        v_7b_n2 := jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n;
        v_7b_z := case
          when coalesce((v_e ->> 'dupla_todos')::boolean, false) then 'O serviço todo pede 2 pessoas: se chamar um ajudante, me diga os dias dele.'
          when v_7b_x <> '' and v_7b_y <> ''
            then format('%s e %s pedem 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'O primeiro meio-dia' else format('Os %s primeiros meios-dias', v_7b_n) end,
                        case when v_7b_n2 = 1 then 'o último' else format('os %s últimos', v_7b_n2) end)
          when v_7b_x <> ''
            then format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_e ->> 'dupla_rot_ini')
          else format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                      case when v_7b_n2 = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_n2) end, v_e ->> 'dupla_rot_fim') end;
      end if;
      v_txt := public._agenda_corta(v_txt || ' ' || v_7b_z, 320);
    end if;
    -- FASE 7b: fim
    -- FASE 7e: (7e P4, R7.5-14) a carga que vale na semana do 1º dia do bloco, com a folga ligada: é ela que entra em "não coube na carga de N%" e na troca pela frase do dono (os 2 pontos leem cf.carga_max; depois deles ninguém mais lê essa coluna). Fora de ligado, a mesma de sempre, byte a byte.
    cf.carga_max := case when v_b ->> 'reserva_de' = 'teto' and v_ctx ? 'carga_semana'
                         then coalesce((v_ctx -> 'carga_semana' ->> ((v_ctx -> 'sem' ->> (v_ini_x - v_ini))::int - 1))::numeric, v_7e_cm)
                         else v_7e_cm end;
    -- FASE 7e: fim
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
    -- FASE 7d: (7d P4, §5.4 3, §6.2, R6.8-3) o item que entra ganha local_texto, suposicoes, viagem e imax_os (só com os modos ligados: é o que o 7g mostra;
    -- nada novo é gravado fora de agenda_propostas.itens). As 2 suposições que só o bloco sabe: "juntei com Kalmar (OS-00033) no mesmo dia, na
    -- Marina Itajaí" e "evitei pôr a mesma pessoa em Balneário Camboriú e em Penha no mesmo dia (temporada)"
    if v_e ? 'suposicoes' then
      v_7d_sup := array(select x from jsonb_array_elements_text(v_e -> 'suposicoes') x);
      if v_7d_ml and coalesce((v_b ->> 'mesmo')::boolean, false) and (v_ctx -> 'loc' ->> ((v_b ->> 'i')::int - 1))::int > 0 then
        select (v_ctx -> 'oss' ->> (z.x - 1))::uuid into v_7d_os
          from (select abs((v_ctxf -> 'fr' ->> ((m.h - 1) * 4 + s.s - 1))::int) as x, m.h, s.s
                  from (select distinct 2 * d.d - k.k as h
                          from (select distinct (hh + 1) / 2 as d from unnest(public._agenda_ints(v_b -> 'h')) hh) d, generate_series(0, 1) k(k)) m,
                       generate_series(1, 4) s(s)) z
         where z.x > 0 and z.x <> (v_b ->> 'i')::int
           and (v_ctx -> 'loc' ->> (z.x - 1))::int = (v_ctx -> 'loc' ->> ((v_b ->> 'i')::int - 1))::int
         order by z.h, z.s
         limit 1;
        if found then
          v_7d_sup := v_7d_sup || format('juntei com %s no mesmo dia, %s', public._agenda_rotulo_da_os(v_7d_os),
                                         v_e ->> 'local_curto');
        end if;
      end if;
      if v_b ? 'evitou' then
        v_7d_x := (v_ctx -> 'mun' ->> ((v_b ->> 'i')::int - 1))::int;
        v_7d_sup := v_7d_sup || format('evitei pôr a mesma pessoa em %s e em %s no mesmo dia (temporada)',
                                       v_ctx -> 'mun_nomes' ->> (v_7d_x - 1), v_ctx -> 'mun_nomes' ->> ((v_b ->> 'evitou')::int - 1));
      end if;
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_build_object('suposicoes', to_jsonb(v_7d_sup))
                 || jsonb_strip_nulls(jsonb_build_object('local_texto', v_e ->> 'local_texto', 'viagem', v_e ->> 'viagem', 'imax_os', v_e -> 'imax_os')));
    end if;
    -- FASE 7d: fim
    -- FASE 7c: (7c P2, §5.2 3, §6.8) os motivos do compromisso, nesta ordem: o que a OS pede e quem vai (com modo_habilidade ligado e
    -- algum meio-dia do bloco pedindo: "pede quem instala sozinho com 220 V ou banco de bateria, no último dia: vai Roberto" — quem
    -- vai é quem tem o que o meio-dia pede, ou você no turno), a troca avisada do responsável ("troquei o responsável: Roberto não
    -- está livre até qua 11/11; segui com João") e o responsável que saiu da equipe ("Roberto, o responsável, não está na equipe
    -- agora"). A troca e o responsável fora só existem com modo_lider ou modo_habilidade ligado.
    v_7c_mot := '{}';
    if v_b ->> 'tipo' <> 'reserva' then
      if cf.modo_habilidade = 'ligado' and v_e ->> 'exig_texto' is not null then
        v_7c_txt := public._agenda_lista(array(
          select y.nome
            from (select case when t.p = (v_ctx ->> 'dono')::int then 'você' else v_ctx -> 'nomes' ->> (t.p - 1) end as nome, min(t.h) as h
                    from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr'),
                                public._agenda_ints(v_b -> 'ex')) t(p, h, pr, ex)
                   where t.pr = 0 and coalesce(t.ex, 0) <> 0
                     and (t.p = (v_ctx ->> 'dono')::int
                          or (t.ex & 9 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4))::int >= cf.habilidade_nivel_energizado)
                          or (t.ex & 2 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_comissionar)
                          or (t.ex & 8 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_diagnostico)
                          or (t.ex & 4 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 2))::int >= cf.habilidade_nivel_altura))
                   group by 1) y
           order by y.h, y.nome));
        if coalesce(v_7c_txt, '') <> '' then
          v_7c_mot := v_7c_mot || format('pede %s: vai %s', v_e ->> 'exig_texto', v_7c_txt);
        end if;
      end if;
      if coalesce((v_b ->> 'lt')::boolean, false) then
        -- o 1º dia, do início do bloco em diante, em que o responsável está livre de manhã ou de tarde na grade de antes do encaixe
        v_7c_lp := coalesce((v_e ->> 'lid')::int, 0);
        v_7c_d := null;
        if v_7c_lp > 0 then
          select min(g) into v_7c_d from generate_series(((v_b ->> 'ini')::int + 1) / 2, (v_ctx ->> 'nd')::int) g
           where ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int in (0, -(v_b ->> 'i')::int))
              or ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int in (0, -(v_b ->> 'i')::int));
        end if;
        v_7c_mot := v_7c_mot || format('troquei o responsável: %s não está livre %s; segui com %s', v_e ->> 'lid_nome',
                                       case when v_7c_d is null then format('nas próximas %s semanas', cf.horizonte_semanas)
                                            else 'até ' || public._dia_curto(v_ini + v_7c_d - 1) end,
                                       coalesce(nullif(public._agenda_lista(array(
                                         select y.nome from (select v_ctx -> 'nomes' ->> (t.p - 1) as nome, min(t.h) as h
                                                               from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'),
                                                                           public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
                                                              where t.pr = 0 and t.p <> (v_ctx ->> 'dono')::int group by 1) y
                                          order by y.h, y.nome)), ''), 'você'));
      end if;
      if coalesce((v_e ->> 'lid_fora')::boolean, false) then
        v_7c_mot := v_7c_mot || format('%s, o responsável, não está na equipe agora', v_e ->> 'lid_nome');
      end if;
    end if;
    if cardinality(v_7c_mot) > 0 then
      v_itens := jsonb_set(v_itens, '{-1,motivos}', coalesce(v_itens -> -1 -> 'motivos', '[]'::jsonb) || to_jsonb(v_7c_mot));
    end if;
    -- FASE 7c: fim
    -- FASE 7c: (7c correção, achado 9) a troca avisada do responsável também vai no TEXTO do item — o que vira a ação do "o que mudou",
    -- a linha "Mudei sozinho" do fechamento, o aviso do gestor e *agenda <OS>* —, não só nos motivos (que ninguém lia): "Edu (OS-97175):
    -- sex 06 e seg 09/11, você fecha, João os 2 dias, … — troquei o responsável: Roberto não está livre até qua 11/11; segui com João,
    -- Bruno e Alex." Sem caber em c_c9_max, a curta "— troquei o responsável (Roberto não está livre)". Só existe com modo_lider ou
    -- modo_habilidade ligado (o lt do bloco, que põe o motivo acima).
    v_c9_tr := (select x from unnest(v_7c_mot) x where x like 'troquei o responsável:%' limit 1);
    if v_c9_tr is not null and v_b ->> 'tipo' <> 'reserva' then
      v_c9_txt := rtrim(v_itens -> -1 ->> 'texto', '.') || ' — ' || v_c9_tr || '.';
      if char_length(v_c9_txt) > c_c9_max then
        v_c9_txt := rtrim(v_itens -> -1 ->> 'texto', '.') || format(' — troquei o responsável (%s não está livre).', v_e ->> 'lid_nome');
      end if;
      v_itens := jsonb_set(v_itens, '{-1,texto}', to_jsonb(public._agenda_corta(v_c9_txt, c_c9_max)));
    end if;
    -- FASE 7c: fim
    -- FASE 7b: (7b P4, §6.4) o item leva a dupla da OS (o texto do cartão e do foco), os meios-dias que pediam 2 e não têm a 2ª pessoa
    -- (dupla_falta [{dia, turno, onde}]) e o sábado usado; só com os modos da 7b
    if v_e ? 'dk' or v_b ? 'sabado' then
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_strip_nulls(jsonb_build_object(
        'dupla', v_e ->> 'dupla_texto', 'dupla_fonte', v_e ->> 'dupla_fonte',
        'dupla_falta', (select jsonb_agg(jsonb_build_object('dia', v_ini + ((f ->> 'h')::int + 1) / 2 - 1,
                                                           'turno', case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end,
                                                           'onde', f ->> 'onde') order by (f ->> 'h')::int)
                          from jsonb_array_elements(v_b -> 'dupla_falta') f),
        'sabado', case when v_b ? 'sabado' then true end)));
    end if;
    -- FASE 7b: fim
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
    -- FASE 7e: (7e P4, §5.3 (a) e (b), R7.3-4) o compromisso da OS urgente ou puxada diz por quê. Ao dono, nunca "urgente" sozinho: a frase diz o motivo, e só fala em usar a folga quando a semana passou mesmo do teto de compromisso (a soma da equipe contra o teto dela; sem o teto da equipe, a pessoa contra o teto dela). A soma é a final, com o que o dono fixou.
    if v_b ->> 'tipo' <> 'reserva' and (v_e ? 'urgente' or v_e ? 'puxada') then
      select coalesce(bool_or(case when v_ctx ? 'teto_equipe'
               then (select coalesce(sum((v_ctxf -> 'uso_c' ->> ((p.p - 1) * (v_ctx ->> 'nw')::int + x.w - 1))::int), 0)
                       from generate_series(1, (v_ctx ->> 'np')::int) p(p) where p.p <> (v_ctx ->> 'dono')::int) > (v_ctx -> 'teto_equipe' ->> (x.w - 1))::int
               else (v_ctxf -> 'uso_c' ->> ((x.pp - 1) * (v_ctx ->> 'nw')::int + x.w - 1))::int > (v_ctx -> 'teto80' ->> ((x.pp - 1) * (v_ctx ->> 'nw')::int + x.w - 1))::int end), false)
        into v_7e_pas
        from (select distinct array_position(v_pes, (a ->> 'payee_id')::uuid) as pp, ((a ->> 'dia')::date - v_ini) / 7 + 1 as w
                from jsonb_array_elements(v_itens -> -1 -> 'alocacoes') a where a ->> 'presenca' = 'turno') x;
      v_7e_m := array_remove(array[case when v_e ? 'urgente' and v_7e_pas then format('urgente: %s; usei a folga da semana', v_e ->> 'urgente_texto') end,
                                   case when v_e ? 'puxada' then 'puxada para a folga que sobrou de amanhã' end], null);
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || case when v_e ? 'urgente' then '{"urgente": true}'::jsonb else '{}'::jsonb end
                                            || jsonb_build_object('motivos', (v_itens -> -1 -> 'motivos') || to_jsonb(v_7e_m)));
    end if;
    -- FASE 7e: fim
    -- FASE 7g: (7g P2, §5.2, R9.4-1, R9.8) o porquê do item que entra, só ao gravar e com modo_porque fora de desligado (em simulação e com o modo desligado, nada
    -- roda e o item sai o de antes, byte a byte): a chave porque = {suposicoes, degrau}. As suposições (_agenda_suposicoes_da_os, os códigos do §3.1 item 3 com o
    -- detalhe da hora) só no compromisso e na reserva condicionada; o degrau (_agenda_degrau) entre o que a OS perdeu nesta proposta (v_canc, do mesmo tipo:
    -- compromisso com compromisso, reserva com reserva) e o bloco, contra o prometido ao cliente. A chave suposicoes do 7d (o texto que o foco locais lê) não muda. O
    -- insert não muda: quem grava na alocação é o gatilho agenda_alocacoes_porque, que lê este item. Uma falha aqui não derruba o motor: o item fica sem porque e o
    -- erro vai para app_error_logs (explicar:porque); query_canceled não cai aqui.
    if p_persistir and cf.modo_porque <> 'desligado' then
      begin
        v_7g_canc := coalesce((select jsonb_agg(jsonb_build_object('payee_id', c -> 'payee_id', 'dia', c -> 'dia', 'turno', c -> 'turno',
                                                                   'presenca', c -> 'presenca')
                                                order by c ->> 'dia', c ->> 'turno', c ->> 'payee_id', c ->> 'presenca')
                                 from jsonb_array_elements(v_canc) c
                                where (c ->> 'os')::uuid = v_os and (c ->> 'tipo' = 'reserva') = (v_b ->> 'tipo' = 'reserva')), '[]'::jsonb);
        v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_build_object('porque', jsonb_build_object(
          'suposicoes', case when v_b ->> 'tipo' <> 'reserva' or v_b ->> 'reserva_de' = 'condicionada'
                             then public._agenda_suposicoes_da_os(v_os, v_info -> v_os::text, v_itens -> -1 -> 'alocacoes', p_hoje)
                             else '[]'::jsonb end,
          'degrau', public._agenda_degrau(v_7g_canc, v_itens -> -1 -> 'alocacoes', (v_e ->> 'fim_antes')::date, v_fim_dep,
                                          (select pl.prometido_ate from public.os_planejamento pl where pl.service_order_id = v_os)))));
      exception when others then
        perform public.log_app_error('db', 'agenda: o porquê da marcação não foi calculado: ' || sqlerrm, 'agenda', 'explicar:porque', 'warn',
                                     jsonb_build_object('os', v_os, 'p_hoje', p_hoje, 'p_agora', p_agora, 'sqlstate', sqlstate));
      end;
    end if;
    -- FASE 7g: fim
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

  -- FASE 7c: (7c P2, §5.2 7) o "por que não cabe" lê os modos e os níveis da 7c no contexto (o que cada pessoa faz já está nele)
  v_ctx := v_ctx || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'n', v_par -> 'n',
                                       'fcobre', cf.habilidade_fechamento_cobre);
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4) o "por que não cabe" lê o pátio como o motor o deixou
  if v_rf ? 'pat_int' then
    v_ctx := v_ctx || jsonb_build_object('pat_int', v_rf -> 'pat_int');
  end if;
  -- FASE 7d: fim
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
    -- FASE 7b: (7b P4, R4.3(c)) a dupla dita que só saiu da espera da classe 4 por quem vem sob demanda (dupla_sd) e não achou bloco:
    -- vai ao "fora" com o motivo dupla (o da classe 4: o aviso, o foco e o cartão dizem "falta a 2ª pessoa"), com as datas de quem
    -- vem — nunca o "sem lugar" calado.
    if coalesce((v_e ->> 'dupla_sd')::boolean, false)
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and f ->> 'motivo' in ('sem_encaixe', 'sem_reserva')) then
      select public._agenda_lista(array_agg(format('%s só vem %s (%s)', x.nome, public._agenda_dias_texto(x.dias),
                                                  public._agenda_plural(x.n, 'meio-dia', 'meios-dias')) order by x.nome)),
             count(*)::int
        into v_7b_x, v_7b_n
        from (select k.pessoa as nome, k.payee_id, array_agg(distinct k.dia order by k.dia) as dias, count(*)::int as n
                from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
               where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje)
               group by k.pessoa, k.payee_id) x;
      v_txt := format('%s: precisa de %s pessoas em %s e %s: me diga mais dias %s ou chame outro ajudante.',
                      public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                      public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'),
                      coalesce(nullif(v_7b_x, ''), 'quem vem sob demanda não cobre'), case when v_7b_n > 1 then 'deles' else 'dele' end);
      -- (correção da revisão da 7b, achado 22) quando os dias de quem vem sob demanda são todos antes de a OS ficar pronta, o
      -- porquê é a data, não a falta de dias ("… e Mateus só vem seg 09 e qui 12/11 (4 meios-dias), antes de o serviço ficar pronto (qua
      -- 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.")
      v_7bc_est := (public.os_prontidao(v_os, p_hoje) ->> 'est')::date;
      select max(k.dia) into v_7bc_max
        from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
       where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje);
      if v_7bc_est is not null and v_7bc_max is not null and v_7bc_max < v_7bc_est and nullif(v_7b_x, '') is not null then
        v_txt := format('%s: precisa de %s pessoas em %s e %s, antes de o serviço ficar pronto (%s): me diga dias %s a partir de %s ou chame outro ajudante.',
                        public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                        public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'), v_7b_x,
                        public._dia_curto(v_7bc_est), case when v_7b_n > 1 then 'deles' else 'dele' end, public._dia_curto(v_7bc_est));
      end if;
      -- (correção da revisão da 7b: fim)
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'dupla', 'texto', v_txt);
      continue;
    end if;
    -- FASE 7b: fim
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
    -- FASE 7c: (7c P2, §5.2 5, §6.8) o fora habilidade (do encaixe: não coube com quem o serviço pede, cabia sem ele): o que ela pede
    -- e que ninguém com isso fica livre junto no horizonte; no dia que o dono pediu, o "não cabe <dia>" de sempre, com o porquê do
    -- dia ("ninguém que sobe no teto fica livre nesse dia")
    if v_tipo = 'habilidade' and v_txt is null then
      v_txt := case when v_e ? 'fixar_de'
                    then format('%s: não cabe %s: %s.', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
                    else format('%s: pede %s e ninguém com isso fica livre junto nas próximas %s semanas.', public._agenda_rotulo_da_os(v_os),
                                concat_ws(' e ', public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'ext')::int, 0), 0),
                                                                                case when coalesce((v_e ->> 'passos')::int, 0) > 1 then 'todos' end),
                                                 public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'exu')::int, 0), 0), 'ultimo')),
                                cf.horizonte_semanas) end;
    end if;
    -- FASE 7c: fim
    -- FASE 7d: (7d P4, R6.3-7, §6.2) a OS que não coube no pátio: motivo sem_encaixe (o que a linha da semana conhece) com patio_cheio e o texto próprio.
    -- Sem vagas ditas, nem nasce.
    if v_tipo = 'sem_encaixe' and v_txt is null
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and coalesce((f ->> 'patio_cheio')::boolean, false)) then
      v_7d_x := (v_ctx -> 'pat' ->> (v_x - 1))::int;
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
        'motivo', 'sem_encaixe', 'patio_cheio', true,
        'texto', format('%s: %s. Me diga se cabe mais um, ou quando outro motorhome sai.', public._agenda_rotulo_da_os(v_os),
                        public._agenda_patio_frase(v_ctx -> 'pat_nomes' ->> (v_7d_x - 1), (v_ctx -> 'pat_max' ->> (v_7d_x - 1))::int, false)));
      continue;
    end if;
    -- FASE 7d: fim
    -- FASE 7d: (correção O14) a viagem com pernoite que não coube: o motivo é a janela de dias seguidos, não "a equipe de hoje". A chave viagem só existe com o modo ligado
    if v_tipo = 'sem_encaixe' and v_txt is null and v_e ->> 'viagem' = 'pernoite' then
      v_txt := format('%s: a viagem precisa de %s seguidos com a mesma equipe, e não achei essa janela em %s semanas.', public._agenda_rotulo_da_os(v_os),
                      public._agenda_plural(ceil(coalesce((v_e ->> 'passos')::numeric, 0) / 2)::int, 'dia útil', 'dias úteis'), cf.horizonte_semanas);
    end if;
    -- FASE 7d: fim
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

  -- FASE 7b: (7b P4, §6.3, R4.3(a)4) em teste, o que a 7b faria e não fez — o sábado ("Em teste: para cumprir o prazo de Vanderlei
  -- (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu.") e a dupla de 1 pessoa ("Em teste: no Lenine eu pediria
  -- um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas."): textos.em_teste e no fim do texto.
  for v_7b_b in select e from jsonb_array_elements(coalesce(v_rf -> 'sab_teste', '[]'::jsonb)) e loop
    v_7b_e := v_ent -> (v_7b_b ->> 'i');
    select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
      from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) a
     where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
    v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                           from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) with ordinality t(a, o)
                                          where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                         order by y.o);
    v_7b_teste := v_7b_teste || case when v_7b_e ? 'prazo'
      then format('Em teste: para cumprir o prazo de %s (%s), eu usaria %s de manhã com %s, que %s.',
                  public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'), public._dia_curto((v_7b_e ->> 'prazo')::date),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end)
      else format('Em teste: %s terminaria antes com %s de manhã (%s %s).', public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end) end;
  end loop;
  if cf.modo_dupla = 'sombra' then
    for v_7b_b in select b from jsonb_array_elements(v_rf -> 'colocadas') b
                   where b ? 'dupla_falta' and jsonb_array_length(b -> 'dupla_falta') > 0 and coalesce((b ->> 'na_janela')::boolean, true)
                     and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso') loop
      v_7b_e := v_ent -> (v_7b_b ->> 'i');
      v_7b_teste := v_7b_teste || format('Em teste: no %s eu pediria um ajudante em %s: %s pede 2 pessoas.',
        public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
        public._agenda_lista(array(
          select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ' (manhã e tarde)'
                                                when bool_or(z.t = 'manha') then ' (manhã)' else ' (tarde)' end
            from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                    from jsonb_array_elements(v_7b_b -> 'dupla_falta') f) z
           group by z.d order by z.d)),
        coalesce(case when coalesce((v_7b_e ->> 'dupla_todos')::boolean, false) then v_7b_e ->> 'dupla_rot_todos' end,
                 nullif(public._agenda_lista(array_remove(array[nullif(v_7b_e ->> 'dupla_rot_ini', ''), nullif(v_7b_e ->> 'dupla_rot_fim', '')], null)), ''),
                 'a tarefa'));
    end loop;
  end if;
  if cardinality(v_7b_teste) > 0 then
    v_textos := v_textos || jsonb_build_object('em_teste', to_jsonb(v_7b_teste));
    v_texto := v_texto || E'\n' || array_to_string(v_7b_teste, E'\n');
  end if;
  -- FASE 7b: fim
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
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada, a criticidade de cada compromisso colocado é refeita com p_violadas = _agenda_zona_fora (o que não conta para o dia já avisado: a violação, o resto do meio-dia dela e o que volta igual neste encaixe; nunca o fixado pelo dono): o meio-dia de um dia já dito à equipe ou ao cliente que sairia sem ter ficado impossível, e o fim que passaria do prometido firme, viram as críticas dia_avisado e dia_prometido, com a pergunta e a recomendação de sempre. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, §6.3, R4.3): só com os modos da 7b — a entrada da fila ganha dk (as pessoas dos passos que restam), dk_dono_conta, dupla_fonte e o texto da dupla; da dupla inferida, passos1 (o bloco de 1 pessoa: ligado, a soma do dk; em teste, os passos de antes), dupla_ni/dupla_nf/dupla_todos e os nomes do que a tarefa pede; prazo_h (o índice da tarde de least(precisa_ate, o prometido firme)) e prazo; e dupla_sd na dupla dita que só passa pela régua dos técnicos com quem vem sob demanda. p_par ganha sab_modo, sab_politica, dupla_modo e dupla_espera. Ligado, o item com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael se ofereceu), para cumprir o prazo de qua 18/11.") e o bloco de 1 pessoa da dupla inferida diz em que meios-dias chamar um ajudante (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."); o item leva dupla (o texto do cartão), dupla_fonte, dupla_falta [{dia, turno, onde}] e sabado. A dupla dita com dupla_sd sem bloco vai ao fora com o motivo dupla ("Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante."), nunca sem_encaixe. Em teste, textos.em_teste e o fim do texto: "Em teste: para cumprir o prazo de Vanderlei (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu." e "Em teste: no Lenine eu pediria um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.". Sem os modos da 7b, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 22 e 23): o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa ("ex.: Mateus vem qua 18 e qui 19/11"); a dupla dita que só passou da espera por quem vem sob demanda e cujos dias livres são todos antes de a OS ficar pronta (os_prontidao.est) vai ao fora dupla com "…, antes de o serviço ficar pronto (qua 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.". FASE 7c (P2, §5.2, R5.10-12): a entrada da fila ganha ext, exu, exf e exig_texto (os_exigencias, em qualquer modo) e, com modo_lider ou modo_habilidade ligado, lid, lid_nome, lid_duro, lid_plan e lid_fora (_agenda_lider_da_os); p_par ganha hab_modo, lid_modo, n, fcobre e lid_espera (sempre: o critério de cada alocação vai no item e o gatilho agenda_alocacoes_criterio o grava). Ligado: os motivos "pede … : vai …", "troquei o responsável: … não está livre até …; segui com …" e "…, o responsável, não está na equipe agora"; o aviso de habilidade (_agenda_aviso_da_habilidade) ao lado do de material onde o dono disse quem vai; o cancelar habilidade ("a equipe do dia não tinha quem o serviço pede") e o fora habilidade ("pede … e ninguém com isso fica livre junto nas próximas 6 semanas"); o contexto do "por que não cabe" leva hab_modo, n e fcobre. Com os 3 modos fora de ligado, as pessoas, os dias, os turnos e as presenças de antes (a projeção); só o critério aparece. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 9): com a troca avisada do responsável (o lt do bloco: modo_lider ou modo_habilidade ligado), o texto do item (o da ação do "o que mudou", do fechamento e do aviso) termina " — troquei o responsável: Roberto não está livre até qua 11/11; segui com João." (até 320; sem caber, " — troquei o responsável (Roberto não está livre)."). Sem troca, o de antes. FASE 7d (P4, §5.4, R6.7b, R6.8): com calendario, patio, viagem ou mesmo_local ligado por _agenda_local_modo (com o freio, em teste), cada OS da fila lê o local (_agenda_local_resolvido; em teste, nenhuma chamada): a máscara entra em bem e em fora_h, a entrada no EST, a retirada em bem, a viagem soma os meios de estrada aos passos e tira o abre e fecha fora da região. Com as chaves só nos modos ligados, o item da fila ganha fora_h, local_txt, viagem, imax_os, local_texto e suposicoes, o item que entra ganha os 4 últimos e v_par ganha mesmo_dia e troca (temporada_meses). A saída pela violação local diz "o local não recebe a equipe nesse dia", e a OS que não coube no pátio vai ao fora com sem_encaixe, patio_cheio e o texto próprio. Com os 6 modos fora de ligado, a saída de antes, byte a byte. FASE 7e (P4): com modo_urgencia ligado de verdade, a OS urgente (_agenda_os_urgente) vai até 100% da semana, sai em p_restricoes.urgentes e o item diz o motivo quando a semana passou do teto; a frase da carga usa a carga da semana (R7.5-14); com p_restricoes.puxar, a OS puxada (P4b). Fora de ligado, a saída de antes, byte a byte. FASE 7g (P2): ao gravar (p_persistir) e com modo_porque fora de desligado, o item criar ganha porque = {suposicoes, degrau}: as suposições de _agenda_suposicoes_da_os (só no compromisso e na reserva condicionada; [] na reserva por teto e no pátio) e o degrau de _agenda_degrau entre o que a OS perdeu nesta proposta (do mesmo tipo) e o bloco, contra o prometido ao cliente. O gatilho agenda_alocacoes_porque grava o porquê nas alocações a partir do item. Falha no cálculo: o item fica sem porque e app_error_logs explicar:porque. Em simulação ou com o modo desligado, a saída de antes, byte a byte.';

-- ── 3. A alocação nova guarda o porquê (gatilho) ─────────────────────────────────────────────────────
-- R9.4-1: o porquê nasce em 7 escritores e só 1 é o motor. Um gatilho no insert cobre todos sem recriá-los. Pelo nome, roda depois de agenda_alocacoes_antes,
-- agenda_alocacoes_criterio e agenda_alocacoes_fonte (BEFORE INSERT vão em ordem alfabética): o critério e a fonte já estão na linha.
create or replace function public._agenda_alocacoes_porque()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_modo text;
  v_ant  record;
  v_it   jsonb;
  v_g    jsonb;
  v_sup  jsonb;
begin
  -- quem grava já disse o porquê: fica
  if new.suposicoes is not null or new.degrau is not null then
    return new;
  end if;
  v_modo := (public._agenda_cfg()).modo_porque;
  if coalesce(v_modo, 'desligado') = 'desligado' then
    return new;
  end if;
  -- (a) a substituição (agenda_desfazer, _agenda_desfazer_cliente): o porquê é o da substituída; o degrau não (substituir sem mudar o lugar não é reparo).
  -- O critério da substituída só com modo_porque ligado: em sombra, as colunas da 7c ficam como eram (a sombra não muda o que grava fora da 7g).
  if new.substitui_id is not null then
    select a.suposicoes, a.criterio, a.criterio_detalhe into v_ant from public.agenda_alocacoes a where a.id = new.substitui_id;
    if found then
      new.suposicoes := v_ant.suposicoes;
      if v_modo = 'ligado' and new.criterio is null
         and (v_ant.criterio is not null or coalesce(v_ant.criterio_detalhe, '{}'::jsonb) <> '{}'::jsonb) then
        new.criterio := v_ant.criterio;
        new.criterio_detalhe := coalesce(v_ant.criterio_detalhe, '{}'::jsonb);
      end if;
    end if;
    return new;
  end if;
  -- o corte: sem proposta não há de onde ler (o puxar em teste, desfeito no mesmo bloco)
  if new.proposta_id is null then
    return new;
  end if;
  -- (b) o item criar da proposta que trouxe esta alocação (pelo alocacao_id: o motor o põe lá), com a chave porque do motor
  select i into v_it
    from public.agenda_propostas p,
         jsonb_array_elements(case when jsonb_typeof(p.itens) = 'array' then p.itens else '[]'::jsonb end) i,
         jsonb_array_elements(case when jsonb_typeof(i -> 'alocacoes') = 'array' then i -> 'alocacoes' else '[]'::jsonb end) a
   where p.id = new.proposta_id and i ->> 'op' = 'criar' and i ->> 'os' = new.service_order_id::text
     and a ->> 'alocacao_id' = new.id::text
   limit 1;
  if jsonb_typeof(v_it -> 'porque') = 'object' then
    if new.presenca = 'turno' then
      v_sup := v_it #> '{porque,suposicoes}';
      -- (o que o motor grava passa sempre no CHECK; se não passasse, nula: não se afirma o que não foi guardado)
      new.suposicoes := case when jsonb_typeof(v_sup) = 'array' and public._agenda_suposicoes_validas(v_sup) then v_sup end;
      new.degrau := case when v_it #>> '{porque,degrau}' in ('pessoa', 'turno', 'dia', 'data', 'tirou') then v_it #>> '{porque,degrau}' end;
    else
      -- a abertura e o fechamento do dono levam a fonte (o gatilho da 7a), não as suposições
      new.suposicoes := '[]'::jsonb;
    end if;
    return new;
  end if;
  -- (c) a proposta do gestor sem o motor (parametros.gestor: a escada e a dupla, reparar; o corte, reestimar): as suposições são as da marcação que ela repara
  -- (a alocação mais nova da OS que tem, fora desta proposta; criado_em e id: ordem total), e o degrau é o da escada (parametros.gestor.degrau)
  select p.parametros -> 'gestor' into v_g from public.agenda_propostas p where p.id = new.proposta_id;
  if jsonb_typeof(v_g) = 'object' then
    v_sup := (select a.suposicoes from public.agenda_alocacoes a
               where a.service_order_id = new.service_order_id and a.suposicoes is not null and a.presenca = 'turno'
                 and (a.tipo = 'reserva') = (new.tipo = 'reserva') and a.proposta_id is distinct from new.proposta_id
               order by a.criado_em desc, a.id desc
               limit 1);
    if v_sup is not null then
      new.suposicoes := case when new.presenca = 'turno' then v_sup else '[]'::jsonb end;
    end if;
    if new.presenca = 'turno' then
      new.degrau := case when v_g ->> 'degrau' in ('pessoa', 'turno', 'dia', 'data', 'tirou') then v_g ->> 'degrau' end;
    end if;
  end if;
  return new;
end;
$function$;

comment on function public._agenda_alocacoes_porque() is
  'Agenda de Produção (Fase 7g, P2; §5.2, R9.4-1): gatilho BEFORE INSERT de agenda_alocacoes (depois do critério e da fonte, pelo nome) — com modo_porque fora de desligado e a alocação sem porquê: (a) com substitui_id, as suposições da substituída (com modo_porque ligado, também o critério dela quando a nova chega sem); sem degrau; (b) senão, o porque do item criar da proposta (pelo alocacao_id): no meio-dia de turno as suposições e o degrau, na abertura e no fechamento [] e sem degrau; (c) na proposta do gestor (parametros.gestor) sem porque no item, as suposições da alocação mais nova da OS que tem (fora desta proposta) e o degrau de parametros.gestor.degrau. Sem nada disso, nula. Invoker: roda como quem insere (as definer da agenda ou o service_role).';

drop trigger if exists agenda_alocacoes_porque on public.agenda_alocacoes;
create trigger agenda_alocacoes_porque before insert on public.agenda_alocacoes
  for each row execute function public._agenda_alocacoes_porque();

-- ── 4. A vigente não muda o porquê (recriada da 7c P2) ───────────────────────────────────────────────
create or replace function public._agenda_alocacoes_imutavel()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_h jsonb;
  v_mudou_o_que boolean :=
    (new.service_order_id, new.payee_id, new.dia, new.turno, new.presenca, new.tipo, new.origem,
     new.condicao, new.condicao_tipo, new.condicao_ate)
    is distinct from
    (old.service_order_id, old.payee_id, old.dia, old.turno, old.presenca, old.tipo, old.origem,
     old.condicao, old.condicao_tipo, old.condicao_ate);
begin
  -- FASE 7c: (7c P2, §5.2) o critério que decidiu a pessoa (criterio e criterio_detalhe: a medida do 7g) também não muda na
  -- publicada, na fixada nem na cancelada
  v_mudou_o_que := v_mudou_o_que or (new.criterio, new.criterio_detalhe) is distinct from (old.criterio, old.criterio_detalhe);
  -- FASE 7c: fim
  -- FASE 7g: (7g P2, §5.2, §3.1 item 2) o porquê gravado na hora (as suposições e o degrau) também não muda na publicada, na fixada nem na cancelada: a
  -- leitura de depois mostra o que valia quando o motor decidiu. Só o INSERT preenche essas 2 colunas. A fonte da duração (duracao_fonte, da 7a) fica fora:
  -- pô-la aqui mudaria o que vale para ela em todo modo, inclusive desligado.
  v_mudou_o_que := v_mudou_o_que or (new.suposicoes, new.degrau) is distinct from (old.suposicoes, old.degrau);
  -- FASE 7g: fim
  if old.estado = 'cancelada' and (v_mudou_o_que or new.estado is distinct from old.estado) then
    raise exception 'Alocação cancelada não volta nem muda: crie outra.';
  end if;
  if old.estado in ('publicada', 'fixada') and v_mudou_o_que then
    raise exception 'Alocação publicada não muda: cancele e crie outra (fica o rastro).';
  end if;

  if new.estado is distinct from old.estado then
    if old.estado = 'fixada' and new.estado = 'cancelada'
       and coalesce(current_setting('agenda.mexe_fixado', true), '') <> 'on' then
      raise exception 'Esse meio-dia está fixado: só sai com a decisão de mexer no fixado.';
    end if;
    if not ((old.estado = 'proposta' and new.estado in ('publicada', 'fixada', 'cancelada'))
            or (old.estado = 'publicada' and new.estado in ('fixada', 'cancelada'))
            or (old.estado = 'fixada' and new.estado = 'cancelada')) then
      raise exception 'Essa troca de estado não existe: % → %.', old.estado, new.estado;
    end if;
    if new.estado = 'cancelada' and coalesce(old.resultado, new.resultado) is not null then
      raise exception 'Esse meio-dia já aconteceu: corrija o resultado, não cancele.';
    end if;
  end if;

  -- Corrigir o resultado é permitido e fica no histórico (os 20 mais novos).
  if old.resultado is not null and new.resultado is distinct from old.resultado then
    v_h := old.historico || jsonb_build_array(jsonb_build_object(
             'em', now(), 'de', old.resultado, 'para', new.resultado, 'via', new.resultado_via));
    if jsonb_array_length(v_h) > 20 then
      select jsonb_agg(e order by o) into v_h
        from jsonb_array_elements(v_h) with ordinality t(e, o)
       where o > jsonb_array_length(v_h) - 20;
    end if;
    new.historico := v_h;
  end if;

  return new;
end;
$function$;

comment on function public._agenda_alocacoes_imutavel() is
  'Agenda de Produção (Fase 2): gatilho BEFORE UPDATE — publicada/fixada não muda (cancela-se e cria-se outra); proposta → publicada|fixada|cancelada, publicada → fixada|cancelada, fixada → cancelada só com agenda.mexe_fixado = on; cancelada não volta; com resultado não se cancela; correção do resultado vai para o histórico. FASE 7c (P2): criterio e criterio_detalhe entram na tupla que a publicada, a fixada e a cancelada não mudam. FASE 7g (P2): suposicoes e degrau entram na tupla que a publicada, a fixada e a cancelada não mudam (duracao_fonte, da 7a, fica como era).';

-- ── 5. A ação guarda a zona e o degrau (gatilho) ─────────────────────────────────────────────────────
-- §3.1 itens 4 e 5, §5.2 e R9.5-16. A zona é a mais severa dos meios-dias tocados (antes e depois), pela regra da 7f (_agenda_zona: o congelamento, o dia já
-- dito, a semana do cliente; não lê o freio); o degrau, o do antes para o depois. Definer: quem insere a ação pode ser o service_role, que não tem porta em
-- _agenda_zona.
create or replace function public._agenda_acoes_porque()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_a   jsonb;
  v_d   jsonb;
  v_ids uuid[];
  v_z   text[];
begin
  if not coalesce(new.executada, false) or new.zona is not null or new.degrau is not null
     or new.tipo is null or new.tipo not in ('publicar', 'criar', 'mover', 'cancelar', 'fixar', 'promover_reserva', 'soltar_reserva', 'reparar', 'reestimar') then
    return new;
  end if;
  if coalesce((public._agenda_cfg()).modo_porque, 'desligado') = 'desligado' then
    return new;
  end if;
  begin
    v_a := (select coalesce(jsonb_agg(e), '[]'::jsonb)
              from jsonb_array_elements(case when jsonb_typeof(new.antes -> 'alocacoes') = 'array' then new.antes -> 'alocacoes' else '[]'::jsonb end) e
             where jsonb_typeof(e) = 'object' and e ->> 'dia' is not null);
    v_d := (select coalesce(jsonb_agg(e), '[]'::jsonb)
              from jsonb_array_elements(case when jsonb_typeof(new.depois -> 'alocacoes') = 'array' then new.depois -> 'alocacoes' else '[]'::jsonb end) e
             where jsonb_typeof(e) = 'object' and e ->> 'dia' is not null);
    if jsonb_array_length(v_a) + jsonb_array_length(v_d) > 0 then
      v_z := array(select distinct public._agenda_zona(new.service_order_id, (e ->> 'payee_id')::uuid, (e ->> 'dia')::date, new.dia)
                     from jsonb_array_elements(v_a || v_d) e);
      new.degrau := public._agenda_degrau(v_a, v_d, (new.antes ->> 'fim')::date, (new.depois ->> 'fim')::date,
                                          (select pl.prometido_ate from public.os_planejamento pl where pl.service_order_id = new.service_order_id));
    else
      -- sem as alocações no antes/depois (outros escritores de ação): a zona pelos ids que a ação diz, degrau nulo
      v_ids := coalesce(new.alocacoes_criadas, '{}') || coalesce(new.alocacoes_canceladas, '{}')
               || array(select (x #>> '{}')::uuid
                          from jsonb_array_elements(case when jsonb_typeof(new.antes -> 'alocacoes') = 'array' then new.antes -> 'alocacoes' else '[]'::jsonb end
                                                    || case when jsonb_typeof(new.depois -> 'alocacoes') = 'array' then new.depois -> 'alocacoes' else '[]'::jsonb end) x
                         where jsonb_typeof(x) = 'string' and x #>> '{}' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
      v_z := array(select distinct public._agenda_zona(a.service_order_id, a.payee_id, a.dia, new.dia)
                     from public.agenda_alocacoes a where a.id = any (v_ids));
    end if;
    new.zona := public._agenda_zona_mais_severa(v_z);
  exception when others then
    -- a falha do cálculo não derruba a ação (query_canceled não cai aqui: a ação cai junto, e está certo)
    new.zona := null;
    new.degrau := null;
    perform public.log_app_error('db', 'agenda: a zona e o degrau da ação não foram calculados: ' || sqlerrm, 'agenda', 'explicar:acao', 'warn',
                                 jsonb_build_object('tipo', new.tipo, 'os', new.service_order_id, 'dia', new.dia, 'sqlstate', sqlstate));
  end;
  return new;
end;
$function$;

comment on function public._agenda_acoes_porque() is
  'Agenda de Produção (Fase 7g, P2; §3.1 itens 4 e 5, §5.2, R9.5-16): gatilho BEFORE INSERT de agenda_acoes — com modo_porque fora de desligado, na ação executada de tipo publicar, criar, mover, cancelar, fixar, promover_reserva, soltar_reserva, reparar ou reestimar, sem zona nem degrau: zona = a mais severa (_agenda_zona_mais_severa) de _agenda_zona(OS, pessoa, dia, o dia da ação) nos meios-dias de antes.alocacoes e depois.alocacoes; degrau = _agenda_degrau(antes.alocacoes, depois.alocacoes, antes.fim, depois.fim, o prometido da OS). Sem alocações no antes/depois: a zona pelos ids (alocacoes_criadas, alocacoes_canceladas e os ids em texto do antes/depois), degrau nulo. Falha do cálculo: zona e degrau nulos e app_error_logs explicar:acao; a ação entra. SECURITY DEFINER (quem insere pode ser o service_role, sem porta em _agenda_zona), sem porta para ninguém.';

drop trigger if exists agenda_acoes_porque on public.agenda_acoes;
create trigger agenda_acoes_porque before insert on public.agenda_acoes
  for each row execute function public._agenda_acoes_porque();

-- ── 6. As portas ─────────────────────────────────────────────────────────────────────────────────────
-- As 3 novas sem porta para public, anon nem authenticated (§3.1 item 13). _agenda_suposicoes_da_os, como as 8 peças do P1, fica com o service_role (quem a chama
-- é agenda_propor, definer, que roda como o dono). Os 2 gatilhos, sem porta para ninguém: rodam no insert. Nenhuma função sem definer com porta para authenticated
-- chama as 8 peças do P1: o gatilho das alocações roda como quem insere (definer ou service_role; authenticated não grava agenda_alocacoes nem agenda_acoes), e o
-- das ações é definer. As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui).
revoke all on function public._agenda_suposicoes_da_os(uuid, jsonb, jsonb, date) from public, anon, authenticated;
grant execute on function public._agenda_suposicoes_da_os(uuid, jsonb, jsonb, date) to service_role;
revoke all on function public._agenda_alocacoes_porque(), public._agenda_acoes_porque() from public, anon, authenticated, service_role;
revoke all on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) to service_role;
revoke all on function public._agenda_alocacoes_imutavel() from public, anon, authenticated;
