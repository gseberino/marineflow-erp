-- Agenda de Produção — Fase 7b, correção 3 (20261101100860): o R5.9 da spec da 7c ("para o fio principal") e o W3a da correção 2.
-- NÃO aplicada.
--
-- ═══ DDL — OK NOMEADO ═══ (2 funções novas e 5 recriadas com as mesmas assinaturas; nenhuma tabela, coluna, lista, job ou dado)
-- Vai DEPOIS da 20261101100850 (a correção 2) e ANTES do dado 20261101100900. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/c3/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (o montador para se outra
-- migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7b: (correção 3) … -- FASE 7b: fim (correção 3)" e, dentro de um bloco
-- da 7b de antes, "-- (correção 3) … -- (correção 3: fim)" (só acréscimo: nenhuma linha de antes muda; tirados esses blocos, o corpo é o
-- da origem, byte a byte: o montador e o C0 de supabase/tests/agenda_fase77b_correcao3.sql conferem). O fecho de cima começa por
-- "-- FASE 7b: fim": os testes de cópia de antes, que tiram todos os blocos "-- FASE 7b:", tiram este junto.
--
-- O QUE MUDA (e por quê):
--   1. O TÉCNICO DECLARADO NUNCA É NOVATO. _agenda_e_novato (de 20261101100300) marcava novato pelo perfil de diária (a 1ª vigência a
--      menos de novato_dias) e pelas diárias (< novato_diarias). Quando o dono cadastrar o perfil de diária do Alex (cadastro 05/08; o
--      padrão do dono seg a sex desde 30/10; hoje sem perfil), o Alex virava novato por 30 dias, e com modo_dupla fora de desligado (o
--      dado 100900 o põe em teste; o ligar de qua 04/11 o liga) o motor nunca deixa novato sozinho num meio-dia: sendo ele o único
--      técnico, a agenda inteira parava (na bancada, a carteira de 4 OS marcadas com o Alex passava a 0). Agora não é novato quem o dono
--      declarou técnico — _agenda_tecnico_declarado (nova): tem ou teve, VIVA OU SUBSTITUÍDA, uma linha de origem dono com dias_semana,
--      disponível ou confirmada, e o cadastro de novato_dias ou mais antes da 1ª dela. "Substituída" importa: quando o próprio Alex
--      responder os dias, _agenda_equipe_dias_gravar troca o padrão do dono por um de origem diarista. Quem não é declarado continua
--      novato como hoje (o Mateus cadastrado agora com "toda terça" dita pelo dono; o Bruno da fixture).
--   2. A ESCADA DA REVISÃO DA 7a NUNCA PÕE SOZINHO QUEM NUNCA VAI SOZINHO. _agenda_gestor_reparo (de 20261031100750, a única) punha no
--      degrau 1 "outro diarista livre no mesmo dia e turno" sem olhar o novato nem quem vem sob demanda, e _agenda_gestor_reparar grava
--      direto (o validador não confere companhia): a falta do Alex num meio-dia com o Mateus dito livre punha o Mateus sozinho. Agora,
--      com modo_dupla fora de desligado, quem nunca fica sozinho só entra no degrau 1 e no meio-dia que fica com outra pessoa que pode
--      ficar sozinha ou com o dono no turno, e nunca nos degraus 2 e 3. Só tira candidato: sem nenhum, a escada não conserta a OS (tudo
--      ou nada) e o motor replaneja. Com modo_dupla desligado, a escada de antes, byte a byte. É uma exceção deliberada ao "byte a byte
--      em teste" (como as do R4 da 7b): só tira candidato.
--   3. O PRAZO NA FORMA CURTA DA LINHA (n). _agenda_linhas_do_fechamento (de 20261101100800): o texto_curto "Agenda, equipe: a equipe da
--      agenda está certa? *agenda pendências* mostra." contava como vista a chamada (o registro conta todas as pergunta_ids), sem dizer o
--      prazo nem o que acontece sem resposta, e a chamada vencia em 3 dias úteis sem o dono ter lido o "sigo assim". Agora cada pergunta
--      que vence leva " — sem resposta até ter 10/11 às 18:00, sigo assim", com a data que o vencimento grava (a chamada contada:
--      _agenda_veto_ate do dia do registro, equipe_chamada_prazo_du; a dos dias da semana: o prazo da semana dela). A forma longa não
--      muda.
--   4. (o W3a da correção 2) COM O DONO JUNTO O TEMPO TODO, A DUPLA PELA TAREFA SE COMPLETA. O passo dupla da 7b (_agenda_gestor_dupla,
--      de 20261101100800) põe a 2ª pessoa num item só com ela, e a regra 4 das 14 conferia a presença do dono só nas alocações do item:
--      "OS-00074: falta você ter 10/11 de manhã", com o dono já no meio-dia. Com a linha dos dias do dono, a marina nova (a Kalmar
--      OS-00033 em produção) nunca ganhava o ajudante que o dono disse. _agenda_dupla_sem_falta_voce (nova) tira só essa violação, só no
--      meio-dia em que o dono já está de turno na OS; o passo dupla e agenda_validar (de 20261025100200, a única: o aplicar da proposta
--      dele, parametros.gestor.motivo = dupla_completa) a usam. As outras propostas, como antes, byte a byte.
--
-- O QUE NÃO MUDA: as Fases 1 a 6, a 7a e a 7b com a fixture e com o estado de produção, sem perfil novo, sem gente nova e com o
-- modo_dupla desligado (o C9 do teste prova); sem o dono de turno no meio-dia, o passo dupla e agenda_validar; a forma longa da linha
-- (n), o telefone e o contato.
--
-- FORA DAQUI (registrado; notas-fase77b.md, CORREÇÃO 3): (a) o dono sozinho num meio-dia de serviço em que ele só vai junto ainda conta
-- como trabalho no "tem" da revisão (o técnico tirado de um dia não volta); (b) com a 7b em teste, a faixa da dupla do 7b P4 deixa 5 dias
-- quando o orçamento cai de 6 para 4 (o texto já diz "estimo 5 dias", o que fica). Os dois são de _agenda_gestor_pessoa_meios e
-- _agenda_gestor_corte (a 100850), que esta não recria.
--
-- Quem recriar depois uma destas funções copia DESTA migration (spec-fase7b §R4.6, fim; a 7c: _agenda_e_novato, _agenda_tecnico_declarado,
-- _agenda_gestor_reparo e _agenda_linhas_do_fechamento — o R5.4 da spec da 7c).
--
-- DESFAZER: recriar cada recriada com o corpo da definição de antes (a 20261101100300 para _agenda_e_novato, a 20261031100750 para
-- _agenda_gestor_reparo, a 20261101100800 para _agenda_linhas_do_fechamento e _agenda_gestor_dupla, a 20261025100200 para
-- agenda_validar) e só então
--   drop function if exists public._agenda_tecnico_declarado(uuid, date), public._agenda_dupla_sem_falta_voce(jsonb);
-- As portas não mudam.

-- ── 1. As duas funções novas ─────────────────────────────────────────────────────────────────────────────────

-- O técnico que o dono declarou (o (a) do R5.1-5 da spec da 7c, sem a parte da etiqueta, que a 7b não tem): tem ou teve — viva OU
-- SUBSTITUÍDA — uma linha de agenda_disponibilidade de origem dono com dias_semana não vazio e disponível ou confirmada (um padrão que o
-- dono declarou), criada até p_dia, e o cadastro (payees.created_at) é de novato_dias ou mais antes da 1ª dessas linhas (a pessoa já
-- estava na casa quando o dono declarou os dias). "Substituída" importa: _agenda_equipe_dias_gravar troca os padrões "vem" vivos por um
-- de origem diarista quando o próprio técnico responde os dias. O Alex (cadastro 05/08, declarado seg a sex em 30/10: 86 dias) é; o
-- Mateus cadastrado agora com "toda terça" dita pelo dono não é (a frase grava um padrão de origem dono, mas o cadastro é do mesmo dia);
-- o Bruno da fixture (uma data dita, sem padrão) não é. O dono nunca. STABLE, invoker; authenticated e service_role (como
-- _agenda_e_novato, que a chama). A 7c P1 a recria acrescentando a etiqueta (a ajudante tira; instala do dono põe).
create or replace function public._agenda_tecnico_declarado(p_payee uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(p_payee is not null and p_dia is not null
     and p_payee is distinct from public._agenda_dono(null)
     and (select min(d.criado_em) from public.agenda_disponibilidade d
           where d.payee_id = p_payee and d.origem = 'dono' and d.dias_semana is not null and cardinality(d.dias_semana) > 0
             and d.situacao in ('disponivel', 'confirmada') and (d.criado_em at time zone 'America/Sao_Paulo')::date <= p_dia)
         >= (select py.created_at from public.payees py where py.id = p_payee)
            + make_interval(days => (public._agenda_cfg()).novato_dias), false);
$function$;

comment on function public._agenda_tecnico_declarado(uuid, date) is
  'Agenda de Produção (Fase 7b, correção 3; o R5.1-5 da spec da 7c, (a), sem a etiqueta): true para quem o dono declarou técnico — tem ou teve (viva ou substituída) uma linha de agenda_disponibilidade de origem dono com dias_semana não vazio, disponível ou confirmada, criada até p_dia, e o cadastro (payees.created_at) é de novato_dias ou mais antes da 1ª dessas linhas. O Alex (cadastro 05/08, padrão seg a sex do dono desde 30/10) é, também depois de responder os próprios dias (a linha do dono substituída por uma de origem diarista); o Mateus cadastrado agora com "toda terça" dita pelo dono não é. O dono nunca. _agenda_e_novato nunca marca quem é. STABLE, invoker. A 7c P1 a recria com a etiqueta.';

-- (W3a da correção 2) A 2ª pessoa da dupla pela tarefa no meio-dia em que o dono já está de turno: o item do passo dupla da 7b
-- (_agenda_gestor_dupla) leva só a 2ª pessoa, e a regra 4 das 14 (_agenda_validar_itens: a presença do dono conforme o molde, conferida
-- só nas alocações do item) dizia "OS-00074: falta você ter 10/11 de manhã" — o dono já está no meio-dia, no plano. Com a presença o tempo
-- todo (a marina nova, a Kalmar OS-00033 em produção) e a linha dos dias do dono, a dupla pela tarefa nunca se completava: o dono que
-- vai junto não é a 2ª pessoa (dk_dono_conta, 7b P4) e o ajudante que o dono disse nunca entrava. Tira da lista só essa violação (regra
-- 4, "falta você"), só no meio-dia em que o dono tem alocação de turno vigente (publicada ou fixada, fora da reserva) na mesma OS; as
-- outras ficam. Só o passo dupla (_agenda_gestor_dupla) e agenda_validar com a proposta dele (parametros.gestor.motivo = dupla_completa)
-- a chamam. STABLE, invoker; authenticated e service_role (agenda_validar é leitura do painel).
create or replace function public._agenda_dupla_sem_falta_voce(p_viol jsonb)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(t.e order by t.o), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_viol, '[]'::jsonb)) with ordinality t(e, o)
   where not (t.e ->> 'regra' = '4' and t.e ->> 'texto' like '%: falta você %'
              and exists (select 1 from public.agenda_alocacoes a
                           where a.service_order_id = (t.e ->> 'os')::uuid and a.dia = (t.e ->> 'dia')::date and a.turno = t.e ->> 'turno'
                             and a.payee_id = public._agenda_dono(null) and a.presenca = 'turno'
                             and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'));
$function$;

comment on function public._agenda_dupla_sem_falta_voce(jsonb) is
  'Agenda de Produção (Fase 7b, correção 3; o W3a da correção 2): as violações das 14 regras sem a da regra 4 "falta você" no meio-dia em que o dono já tem alocação de turno vigente (publicada ou fixada, fora da reserva) na mesma OS — o item da 2ª pessoa da dupla pela tarefa (_agenda_gestor_dupla) leva só ela, e o dono que vai junto o tempo todo já está no meio-dia. As outras violações ficam. Só o passo dupla e agenda_validar com a proposta dele (parametros.gestor.motivo = dupla_completa) a chamam. STABLE, invoker.';

-- ── 2. As recriadas ───────────────────────────────────────────────────────────────────────────────────────────

-- _agenda_e_novato (de 20261101100300_agenda_fase7b_motor.sql)
create or replace function public._agenda_e_novato(p_payee uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(p_payee is not null and p_dia is not null
     and p_payee is distinct from public._agenda_dono(null)
     -- FASE 7b: (correção 3) o técnico que o dono declarou nunca é novato (_agenda_tecnico_declarado: o padrão do dono, vivo
     -- ou substituído, e o cadastro de novato_dias ou mais antes dele). Sem isso, o perfil de diária do Alex (cadastro 05/08; o padrão do
     -- dono seg a sex desde 30/10), quando o dono o cadastrar, fazia dele novato por 30 dias, e com modo_dupla fora de desligado o motor
     -- nunca o deixava sozinho num meio-dia: sendo ele o único técnico, a agenda inteira parava. Quem não é declarado continua como antes.
     and not public._agenda_tecnico_declarado(p_payee, p_dia)
     -- FASE 7b: fim (correção 3)
     and exists (select 1 from public.work_profiles w
                  where w.payee_id = p_payee and w.vigencia_inicio <= p_dia and (w.vigencia_fim is null or w.vigencia_fim >= p_dia))
     and (select min(w.vigencia_inicio) from public.work_profiles w where w.payee_id = p_payee)
         > p_dia - (public._agenda_cfg()).novato_dias
     and coalesce((select sum(ws.fracao) from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
                    where w.payee_id = p_payee and ws.data <= p_dia and ws.tipo = 'diaria' and ws.fracao is not null), 0)
         < (public._agenda_cfg()).novato_diarias, false);
$function$;

comment on function public._agenda_e_novato(uuid, date) is
  'Agenda de Produção (Fase 7b, P4; spec §5.3, AG7-04/AG7-10): true para quem tem perfil de diária vigente em p_dia, a 1ª vigência há menos de novato_dias e menos de novato_diarias diárias (a soma das frações lançadas até p_dia). O dono nunca. O motor (_agenda_contexto, com modo_dupla fora de desligado) nunca o deixa sozinho num meio-dia. É a regra única do novato (o 7c a usa). STABLE, invoker. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o (a) do R5.1-5 sem a etiqueta): nunca é novato quem o dono declarou técnico (_agenda_tecnico_declarado: tem ou teve, viva ou substituída, uma linha de origem dono com dias_semana, disponível ou confirmada, e o cadastro de novato_dias ou mais antes da 1ª delas) — o perfil de diária do Alex, cadastrado depois, não o faz novato, nem depois de ele responder os próprios dias (o padrão do dono substituído por um de origem diarista). Quem não é declarado (o Mateus cadastrado agora com "toda terça", o Bruno da fixture), como antes.';

-- _agenda_gestor_reparo (de 20261031100750_agenda_fase7a_revisao.sql)
create or replace function public._agenda_gestor_reparo(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_base   constant date := date '2000-01-03';   -- uma segunda: o meio-dia vira um número (2 por dia), para comparar a ordem
  c_tentar constant int := 12;                   -- estrutural: quantos candidatos o validador confere por meio-dia violado
  cf       public.agenda_config;
  v_cong   date;
  v_dono   uuid;
  v_numero text;
  v_cli    text;
  v_rot    text;
  v_pront  jsonb;
  v_meios  jsonb;
  v_canc   jsonb;
  v_viol   jsonb;
  v_ids    uuid[];
  v_base   jsonb;
  v_ev     boolean;
  v_d1     date;
  v_d2     date;
  v_cap    jsonb;
  v_ult    date;
  v_ab     int;
  v_fe     int;
  v_int0   int;
  v_lim    int;
  v_bem    datemultirange;
  v_ok     jsonb := '[]'::jsonb;
  v_sobra  jsonb := '[]'::jsonb;
  v_canc_i jsonb;
  v_itens  jsonb;
  v_val    jsonb;
  v_v      jsonb;
  v_c      record;
  v_achou  jsonb;
  v_so     boolean;
  v_seg    date;
  v_rdias  date[];
  v_rmin   date;
  v_rmax   date;
  v_n      int;
  v_fim    date;
  v_grau   int;
  v_frases text[] := '{}';
  r        record;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_reparo: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  select so.service_order_number, coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
    into v_numero, v_cli
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  v_base := jsonb_build_object('os', p_os, 'numero', v_numero, 'reparavel', false, 'degrau', null, 'itens', '[]'::jsonb,
                               'texto', null, 'reparos', '[]'::jsonb, 'sobrou', '[]'::jsonb);
  if v_numero is null then
    return v_base || jsonb_build_object('motivo', 'sem_os');
  end if;
  cf := public._agenda_cfg();
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_dono := public._agenda_dono(null);
  v_rot := public._agenda_rotulo_da_os(p_os);
  v_pront := public.os_prontidao(p_os, p_hoje);
  v_meios := public.agenda_meios_da_os(p_os, p_hoje);
  v_canc := public._agenda_violacoes(array[p_os], array(select k.service_order_id from public.os_carteira(p_hoje) k), false,
              jsonb_build_object(p_os::text, jsonb_build_object('pront', v_pront, 'meios', v_meios)), p_hoje, v_cong);
  select coalesce(jsonb_agg(c order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id', c ->> 'alocacao_id'), '[]'::jsonb)
    into v_viol
    from jsonb_array_elements(v_canc) c
   where coalesce((c ->> 'violada')::boolean, false) and (c ->> 'os')::uuid = p_os;
  if jsonb_array_length(v_viol) = 0 then
    return v_base || jsonb_build_object('motivo', 'nada_violado');
  end if;
  if exists (select 1 from jsonb_array_elements(v_viol) c where c ->> 'motivo' <> 'pessoa') then
    return v_base || jsonb_build_object('motivo', 'outro_motivo',
             'motivos', (select jsonb_agg(distinct c ->> 'motivo') from jsonb_array_elements(v_viol) c));
  end if;
  if exists (select 1 from jsonb_array_elements(v_viol) c
              where c ->> 'tipo' = 'reserva' or coalesce(c ->> 'presenca', 'turno') <> 'turno'
                 or (c ->> 'payee_id')::uuid is not distinct from v_dono or c ->> 'fixado_por' = 'dono') then
    return v_base || jsonb_build_object('motivo', 'fora_da_escada');
  end if;

  v_ids := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_viol) c);
  v_ev := exists (select 1 from jsonb_array_elements(v_viol) c where coalesce((c ->> 'congelado')::boolean, false));
  select min((c ->> 'dia')::date), max((c ->> 'dia')::date) into v_d1, v_d2 from jsonb_array_elements(v_viol) c;
  v_d1 := v_d1 - (extract(isodow from v_d1)::int - 1);
  v_d2 := v_d2 + (7 - extract(isodow from v_d2)::int);
  select coalesce(jsonb_agg(to_jsonb(k)), '[]'::jsonb) into v_cap from public.agenda_capacidade(v_d1, v_d2, p_hoje) k;
  select pl.bem_indisponivel into v_bem from public.os_planejamento pl where pl.service_order_id = p_os;
  -- o que a OS tem de hoje em diante (o último dia; a abertura e o fechamento do dono, fora das violadas; os dias parados)
  select max(a.dia) into v_ult
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
  select min((a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end) filter (where a.presenca = 'abertura'),
         max((a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end) filter (where a.presenca = 'fechamento')
    into v_ab, v_fe
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
     and a.resultado is null and not (a.id = any (v_ids));
  v_rdias := array(select distinct a.dia from public.agenda_alocacoes a
                    where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.presenca = 'turno' and a.dia >= p_hoje and a.resultado is null order by 1);
  select count(*)::int into v_int0
    from generate_series(v_rdias[1] + 1, v_rdias[cardinality(v_rdias)] - 1, interval '1 day') g
   where cardinality(v_rdias) > 1 and public.agenda_dia_util(g::date) and not (g::date = any (v_rdias))
     and not coalesce(v_bem @> g::date, false);
  v_lim := greatest(coalesce(v_int0, 0), cf.interrupcoes_max);

  -- o cancelar (todas as violadas da OS, de uma vez: é o que sai)
  v_canc_i := jsonb_build_object(
    'op', 'cancelar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
    'tipo', (select min(c ->> 'tipo') from jsonb_array_elements(v_viol) c), 'motivo', 'pessoa', 'violada', true,
    'alocacoes', (select jsonb_agg(jsonb_build_object('alocacao_id', c -> 'alocacao_id', 'payee_id', c -> 'payee_id',
                                     'nome', (select public._agenda_nome_curto(py.name) from public.payees py
                                               where py.id = (c ->> 'payee_id')::uuid),
                                     'dia', c -> 'dia', 'turno', c -> 'turno', 'presenca', c -> 'presenca', 'estado', c -> 'estado',
                                     'fixado_por', c -> 'fixado_por')
                                   order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id')
                    from jsonb_array_elements(v_viol) c),
    'de', (select min(c ->> 'dia') from jsonb_array_elements(v_viol) c),
    'ate', (select max(c ->> 'dia') from jsonb_array_elements(v_viol) c),
    'critica', null, 'decisao', null, 'aplicado', false,
    'texto', format('%s: sai %s — quem ia não está mais livre.', v_rot,
                    public._agenda_dias_texto(array(select (c ->> 'dia')::date from jsonb_array_elements(v_viol) c))));

  for v_v in select c from jsonb_array_elements(v_viol) c
              order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id', c ->> 'alocacao_id' loop
    v_achou := null;
    -- os degraus 2 e 3 só para o meio-dia em que a OS tem só esta pessoa (sem o dono abrindo ou fechando, sem outra junto)
    v_so := not exists (select 1 from public.agenda_alocacoes a
                         where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                           and a.dia = (v_v ->> 'dia')::date and a.turno = v_v ->> 'turno'
                           and a.id <> (v_v ->> 'alocacao_id')::uuid);
    v_seg := (v_v ->> 'dia')::date - (extract(isodow from (v_v ->> 'dia')::date)::int - 1);
    -- os dias que ficam com a OS (os de turno, fora as violadas, com os consertos aceitos)
    v_rdias := array(select distinct d from (
                       select a.dia as d from public.agenda_alocacoes a
                        where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          and a.presenca = 'turno' and a.dia >= p_hoje and a.resultado is null and not (a.id = any (v_ids))
                       union all
                       select (x #>> '{para,dia}')::date from jsonb_array_elements(v_ok) x) u order by 1);
    v_rmin := v_rdias[1];
    v_rmax := v_rdias[cardinality(v_rdias)];
    v_n := 0;
    for v_c in
      with k as (
        select * from jsonb_to_recordset(v_cap) as k(payee_id uuid, pessoa text, eh_dono boolean, dia date, turno text,
                                                     situacao text, meios_esperados numeric)
         where k.situacao = 'livre' and not coalesce(k.eh_dono, false) and k.payee_id is distinct from v_dono
      ),
      alvo as (
        select 1 as grau, (v_v ->> 'dia')::date as dia, v_v ->> 'turno' as turno
        union all
        select 2, (v_v ->> 'dia')::date, case when v_v ->> 'turno' = 'manha' then 'tarde' else 'manha' end where v_so
        union all
        select 3, g::date, t.t
          from generate_series(v_seg, v_seg + 6, interval '1 day') g, unnest(array['manha', 'tarde']) t(t)
         where v_so and g::date <> (v_v ->> 'dia')::date and public.agenda_dia_util(g::date) and g::date <= v_ult
      )
      select a.grau, a.dia, a.turno, k.payee_id, public._agenda_nome_curto(k.pessoa) as nome,
             case when a.grau = 3 then
               (select count(*)::int
                  from generate_series(least(v_rmin, a.dia) + 1, greatest(v_rmax, a.dia) - 1, interval '1 day') g
                 where public.agenda_dia_util(g::date) and g::date <> a.dia and not (g::date = any (coalesce(v_rdias, '{}'::date[])))
                   and not coalesce(v_bem @> g::date, false))
             else 0 end as parado
        from alvo a
        join k on k.dia = a.dia and k.turno = a.turno
       where (a.grau > 1 or k.payee_id <> (v_v ->> 'payee_id')::uuid)
         and lower(public.agenda_periodo(a.dia, a.turno, 'turno')) > p_agora
         and (a.dia > v_cong or v_ev)
         -- a OS não tem meio-dia ali (degraus 2 e 3)
         and (a.grau = 1 or not exists (select 1 from public.agenda_alocacoes x
                                         where x.service_order_id = p_os and x.estado in ('publicada', 'fixada')
                                           and x.tipo <> 'reserva' and x.dia = a.dia and x.turno = a.turno
                                           and not (x.id = any (v_ids))))
         and (a.grau = 1 or not exists (select 1 from jsonb_array_elements(v_ok) x
                                         where x #>> '{para,dia}' = a.dia::text and x #>> '{para,turno}' = a.turno))
         -- nem antes da abertura nem depois do fechamento do dono
         and (a.grau = 1 or ((v_ab is null or (a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end > v_ab)
                             and (v_fe is null or (a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end < v_fe)))
         -- a pessoa sem outra coisa no meio-dia (fora o que sai) nem outro conserto ali
         and not exists (select 1 from public.agenda_alocacoes x
                          where x.payee_id = k.payee_id and x.estado in ('publicada', 'fixada') and not (x.id = any (v_ids))
                            and x.periodo && public.agenda_periodo(a.dia, a.turno, 'turno'))
         and not exists (select 1 from jsonb_array_elements(v_ok) x
                          where x #>> '{para,payee_id}' = k.payee_id::text and x #>> '{para,dia}' = a.dia::text
                            and x #>> '{para,turno}' = a.turno)
         -- FASE 7b: (correção 3) quem nunca fica sozinho (a regra do motor da 7b, com modo_dupla fora de desligado: o novato,
         -- com novato_sozinho falso, e quem vem sob demanda, com sob_demanda_sozinho falso) só entra no degrau 1 e só no meio-dia que fica
         -- com outra pessoa de turno da OS que pode ficar sozinha (fora as que saem) ou com o dono no turno; nunca nos degraus 2 e 3 (lá ele
         -- iria sozinho: a OS não tem meio-dia ali). Sem isso, a falta do Alex num meio-dia com o Mateus dito livre punha o Mateus sozinho
         -- (o validador não confere companhia). Só tira candidato: sem nenhum, a escada não conserta a OS (tudo ou nada) e o motor
         -- replaneja com a regra dele. Com modo_dupla desligado, ou com quem pode ficar sozinho, a escada de antes, byte a byte.
         and (cf.modo_dupla = 'desligado'
              or not ((not cf.novato_sozinho and public._agenda_e_novato(k.payee_id, a.dia))
                       or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(k.payee_id, a.dia)))
              or (a.grau = 1
                  and (exists (select 1 from public.agenda_alocacoes x
                                where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.tipo <> 'reserva'
                                  and x.dia = a.dia and x.turno = a.turno and x.presenca = 'turno' and not (x.id = any (v_ids))
                                  and (x.payee_id is not distinct from v_dono
                                       or not ((not cf.novato_sozinho and public._agenda_e_novato(x.payee_id, a.dia))
                                               or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(x.payee_id, a.dia)))))
                       or exists (select 1 from jsonb_array_elements(v_ok) y
                                   where y #>> '{para,dia}' = a.dia::text and y #>> '{para,turno}' = a.turno
                                     and not ((not cf.novato_sozinho and public._agenda_e_novato((y #>> '{para,payee_id}')::uuid, a.dia))
                                              or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda((y #>> '{para,payee_id}')::uuid, a.dia)))))))
         -- FASE 7b: fim (correção 3)
       order by a.grau, 6, abs(a.dia - (v_v ->> 'dia')::date), a.dia, a.turno = 'tarde',
                k.payee_id = (v_v ->> 'payee_id')::uuid desc,
                exists (select 1 from public.agenda_alocacoes x where x.service_order_id = p_os and x.payee_id = k.payee_id
                           and x.estado in ('publicada', 'fixada') and not (x.id = any (v_ids))) desc,
                k.meios_esperados desc, k.pessoa, k.payee_id
    loop
      continue when v_c.grau = 3 and v_c.parado > v_lim;
      v_n := v_n + 1;
      exit when v_n > c_tentar;
      v_achou := jsonb_build_object(
        'alocacao_id', v_v -> 'alocacao_id', 'degrau', case v_c.grau when 1 then 'pessoa' when 2 then 'turno' else 'dia' end,
        'tipo', v_v ->> 'tipo',
        'fonte', coalesce((select a.duracao_fonte from public.agenda_alocacoes a where a.id = (v_v ->> 'alocacao_id')::uuid),
                          v_meios ->> 'fonte'),
        'de', jsonb_build_object('payee_id', v_v -> 'payee_id',
                                 'nome', (select public._agenda_nome_curto(py.name) from public.payees py
                                           where py.id = (v_v ->> 'payee_id')::uuid),
                                 'dia', v_v -> 'dia', 'turno', v_v -> 'turno'),
        'para', jsonb_build_object('payee_id', v_c.payee_id, 'nome', v_c.nome, 'dia', v_c.dia, 'turno', v_c.turno));
      v_itens := jsonb_build_array(v_canc_i) || (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'op', 'criar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
                 'tipo', x ->> 'tipo', 'reserva_de', null,
                 'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', x #> '{para,payee_id}', 'nome', x #> '{para,nome}',
                                                                   'dia', x #> '{para,dia}', 'turno', x #> '{para,turno}',
                                                                   'presenca', 'turno')),
                 'de', x #> '{para,dia}', 'ate', x #> '{para,dia}', 'fim_antes', v_ult, 'fim_depois', null, 'atraso_du', null,
                 'condicao_tipo', null, 'critica', null, 'pergunta_chave', null, 'decisao', null, 'espera', false,
                 'interrupcoes', 0, 'meios_do_dono', 0, 'fonte', x ->> 'fonte', 'dias', v_meios -> 'dias', 'evento_real', v_ev,
                 'fixar_dono', false, 'aviso_material', null, 'abre', false, 'fecha', false,
                 'motivos', jsonb_build_array('degrau ' || (x ->> 'degrau')), 'texto', null, 'aplicado', false,
                 'degrau', x ->> 'degrau') order by o), '[]'::jsonb)
          from jsonb_array_elements(v_ok || jsonb_build_array(v_achou)) with ordinality t(x, o));
      v_val := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', '{}'::jsonb), p_hoje, p_agora, false,
                                            jsonb_build_object(p_os::text, v_pront));
      exit when jsonb_array_length(v_val) = 0;
      v_achou := null;
    end loop;
    if v_achou is null then
      v_sobra := v_sobra || (v_v -> 'alocacao_id');
    else
      v_ok := v_ok || jsonb_build_array(v_achou);
    end if;
  end loop;

  if jsonb_array_length(v_sobra) > 0 then
    return v_base || jsonb_build_object('motivo', 'sem_lugar', 'sobrou', v_sobra, 'reparos', v_ok, 'evento_real', v_ev);
  end if;

  -- o fim: o último dia que a OS fica tendo (o fim nunca passa do de antes: os degraus não vão depois do último dia)
  select max(d) into v_fim from (
    select a.dia as d from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and not (a.id = any (v_ids))
    union all
    select (x #>> '{para,dia}')::date from jsonb_array_elements(v_ok) x) u;
  v_grau := (select max(case x ->> 'degrau' when 'pessoa' then 1 when 'turno' then 2 else 3 end) from jsonb_array_elements(v_ok) x);

  -- as frases (spec §6.4): a troca de pessoa nos dois turnos do mesmo dia vira uma só
  for r in
    select min(x #>> '{de,dia}') as dia_de, x ->> 'degrau' as degrau, x #>> '{de,nome}' as de_nome, x #>> '{para,nome}' as para_nome,
           count(*) as n, min(x #>> '{de,turno}') as turno_de, min(x #>> '{para,dia}') as dia_para,
           min(x #>> '{para,turno}') as turno_para, bool_or(x #>> '{de,payee_id}' = x #>> '{para,payee_id}') as mesma
      from jsonb_array_elements(v_ok) x
     group by x ->> 'degrau', x #>> '{de,dia}', x #>> '{de,payee_id}', x #>> '{de,nome}', x #>> '{para,payee_id}', x #>> '{para,nome}',
              case when x ->> 'degrau' = 'pessoa' then '' else x #>> '{de,turno}' end
     order by min(x #>> '{de,dia}'), min(x #>> '{de,turno}') = 'tarde'
  loop
    v_frases := v_frases || case r.degrau
      when 'pessoa' then format('%s %s: troquei %s por %s (%s não vem).', v_cli,
                                case when r.n > 1 then public._dia_curto(r.dia_de::date)
                                     else public._agenda_meio_texto(r.dia_de::date, r.turno_de) end,
                                r.de_nome, r.para_nome, r.de_nome)
      when 'turno' then format('%s %s: passei a %s para a %s, com %s.', v_cli, public._dia_curto(r.dia_de::date),
                               case when r.turno_de = 'manha' then 'manhã' else 'tarde' end,
                               case when r.turno_para = 'manha' then 'manhã' else 'tarde' end, r.para_nome)
      else format('%s: passei %s para %s%s (mesma semana%s).', v_cli, public._agenda_meio_texto(r.dia_de::date, r.turno_de),
                  public._agenda_meio_texto(r.dia_para::date, r.turno_para),
                  case when r.mesma then '' else ', com ' || r.para_nome end,
                  case when v_fim = v_ult then '; o fim não muda' else '' end) end;
  end loop;

  return v_base || jsonb_build_object(
    'reparavel', true, 'motivo', null,
    'degrau', case v_grau when 1 then 'pessoa' when 2 then 'turno' else 'dia' end,
    'itens', (select jsonb_agg(case when i ->> 'op' = 'criar'
                                    then i || jsonb_build_object('fim_depois', v_fim,
                                                                 'texto', array_to_string(v_frases, ' '))
                                    else i end order by k)
                from jsonb_array_elements(v_itens) with ordinality t(i, k)),
    'texto', public._agenda_corta(array_to_string(v_frases, ' '), 400),
    'reparos', v_ok, 'fim_antes', v_ult, 'fim_depois', v_fim, 'evento_real', v_ev);
end;
$function$;

comment on function public._agenda_gestor_reparo(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §3.3 d11, §5.9, §6.4): a escada de reparo, a conta, sem gravar nada — para a OS com meio-dia de compromisso violado por pessoa (_agenda_violacoes: quem ia não está mais livre), cada meio-dia violado procura, nesta ordem, (1) pessoa: outro diarista livre no mesmo dia e turno, sem outra OS ali; (2) turno: o outro turno do mesmo dia, sem meio-dia da OS, a mesma pessoa se livre; (3) dia: outro dia útil da mesma semana ISO, depois do congelado (no congelado só com o evento real, nunca o que começou), não depois do último dia da OS, sem meio-dia dela, sem mais dias parados do que ela já tinha (ou interrupcoes_max). Cada candidato só vale com as 14 regras do motor (_agenda_validar_itens) sobre o conjunto. Degraus 2 e 3 só no meio-dia em que a OS tem só essa pessoa, nunca antes da abertura nem depois do fechamento do dono. Tudo ou nada por OS (sobrou = vai inteira ao motor). Violação de outro motivo, da reserva, do dono ou do fixado pelo dono: não é da escada. {os, numero, reparavel, motivo?, degrau, itens (o formato de agenda_propor), texto ("Lenine qua 04/11 de manhã: troquei João por Roberto (João não vem)."; "Lenine qua 04/11: passei a manhã para a tarde, com Roberto."; "Lenine: passei qua 04/11 de manhã para sex 06/11 de manhã (mesma semana; o fim não muda)."), reparos, sobrou, fim_antes, fim_depois, evento_real}. STABLE, invoker, sem grant. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o bloco (i) do R5.3-2 na versão 7b): com modo_dupla fora de desligado, quem nunca fica sozinho (o novato da 7b, com novato_sozinho falso; quem vem sob demanda, com sob_demanda_sozinho falso — _agenda_e_novato e _agenda_e_sob_demanda no dia do meio-dia) só entra no degrau 1 e só no meio-dia que fica com outra pessoa de turno da OS que pode ficar sozinha (fora as que saem; também um conserto já aceito ali) ou com o dono no turno; nunca nos degraus 2 e 3. Só tira candidato: sem nenhum, a OS não é consertada (sobrou) e vai ao motor. Com modo_dupla desligado, ou com um candidato que pode ficar sozinho, a de antes, byte a byte.';

-- _agenda_linhas_do_fechamento (de 20261101100800_agenda_fase77b_correcao.sql)
create or replace function public._agenda_linhas_do_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 480;   -- estrutural: uma linha da agenda no fechamento
  -- FASE 3: o fim do texto da conferência da vigia (é o que a linha dia troca quando tem o que contar da equipe)
  c_cauda constant text := ' Foi isso? Responda *dia feito* ou conte o que mudou.';
  v_ini   date;
  v_am1   date;
  v_am2   date;
  v_out   jsonb := '[]'::jsonb;
  q       record;
  g       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_conf  record;
  v_txts  text[];
  v_ids   jsonb;
  v_txt   text;
  v_mod   text;
  v_n     int;
  k       int;
  m       text;
  -- FASE 3
  v_eq    jsonb;
  v_base  text;
  v_dia   text;
  v_som   text;
  v_extra text;
  v_cauda text;
  v_pend  jsonb;
  v_tec   text;
  v_cob   text;
  v_ppc   jsonb;
  v_com   jsonb;
  -- FASE 7: (7a P7) a linha do gestor em teste e a das compras da semana
  v_f7_txt   text;
  v_f7_cmp   jsonb;
  v_f7_min   date;
  v_f7_urg   boolean;
  v_f7_perda int;
  -- FASE 7: fim
  -- FASE 7: (7a correção, achados 15 e 18) a linha das perguntas do gestor
  c_max_perg  constant int := 600;   -- estrutural: até 640 na coleta, como a do cliente
  v_f77_ids   jsonb;
  v_f77_txt   text;
  v_f77_prazo boolean;
  v_f77_segs  text[];
  v_f77_grupo text;
  v_f77_itens text[];
  v_f77_rest  int;
  v_f77_nl    text;
  v_f77_item  text;
  v_f77_ns    text[];
  v_f77_ni    text[];
  v_f77_l     text;
  v_f77_q     record;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) a linha (n) da equipe
  v_7b_on     boolean;
  v_7b_ids    jsonb;
  v_7b_txt    text;
  v_7b_itens  text[];
  v_7b_curtos text[];
  v_7b_rest   int;
  v_7b_perde  boolean;
  v_7b_lig    boolean;
  v_7b_item   text;
  v_7b_curto  text;
  v_7b_l      text;
  v_7b_q      record;
  -- (correção 3) o prazo de quem vence, na forma curta
  v_c3_ate    timestamptz;
  -- (correção 3: fim)
  -- FASE 7b: fim
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_ini := p_hoje - 6;
  v_am1 := public.agenda_somar_du(p_hoje, 1);
  v_am2 := public.agenda_somar_du(p_hoje, 2);

  -- (a) as decisões críticas abertas
  -- FASE 3: menos a da diária, que tem a linha dela (b2)
  for q in select x.* from public.agenda_perguntas x where x.critica and x.estado = 'aberta' and x.tipo <> 'diaria'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'decisao',
      'texto', 'Agenda, preciso de você. ' || q.texto || ' Me responda aqui.',
      'perda', case when q.perda_em is not null and q.perda_em <= v_am1 then 100
                    when q.perda_em is not null and q.perda_em <= v_am2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (a2): a diária que diverge do plano (crítica): as opções, a recomendação e as palavras que respondem.
  -- A perda: o banco não sabe quando o acerto fecha (o dono fecha quando quer); com 2 dias úteis sem resposta, 80.
  for q in select x.* from public.agenda_perguntas x where x.tipo = 'diaria' and x.estado = 'aberta'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'diaria',
      'texto', 'Diária, preciso de você: ' || public._agenda_texto_da_diaria(q.id),
      'perda', case when public.agenda_du_entre(coalesce(q.dia, q.perda_em, p_hoje), p_hoje) >= 2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (b) o que mudou sozinho (de verdade e na sombra), ainda não contado
  v_m := public._agenda_mudancas(v_ini, p_hoje, true, true, null);
  v_ms := public._agenda_mudancas(v_ini, p_hoje, false, true, null);

  -- (c) a semana publicada
  for g in select x from jsonb_array_elements(v_m) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', (g ->> 'desfazivel')::boolean, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids',
      'modo', case when cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  for g in select x from jsonb_array_elements(v_ms) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', false, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids', 'modo', 'sombra');
  end loop;

  -- (d) a conferência de hoje, com o que mudou sozinho; sem ela, o que mudou numa linha só
  select x.* into v_conf from public.agenda_perguntas x
   where x.tipo = 'conferencia' and x.estado = 'aberta' and x.dia = p_hoje
   order by (x.modo = 'ligado') desc, x.criada_em desc, x.id desc limit 1;
  -- FASE 3: o que a equipe confirmou, a diária que a agenda lançou, quem falta confirmar e o último dia da OS
  v_eq := public._agenda_dia_da_equipe(p_hoje);
  v_pend := v_eq -> 'pendentes';
  v_extra := nullif(array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'lig') x
                                          union all select x from jsonb_array_elements_text(v_eq -> 'ultimo') x), ' '), '');
  for m in select unnest(array['ligado', 'sombra']) loop
    v_txts := array(select public._agenda_mudanca_texto(x, false)
                      from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o)
                     where x ->> 'tipo' = 'acao' order by o);
    v_ids := coalesce((select jsonb_agg(y order by o, o2)
                         from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o),
                              jsonb_array_elements(x -> 'acao_ids') with ordinality u(y, o2)
                        where x ->> 'tipo' = 'acao'), '[]'::jsonb);
    v_mod := case when m = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end;
    if v_conf.id is not null and v_conf.modo = m then
      -- FASE 3: o texto do dia com a equipe. Sem nada a contar, é o da conferência, byte a byte.
      v_dia := v_conf.texto;
      if v_extra is not null or jsonb_array_length(v_pend) > 0 then
        v_base := case when right(v_conf.texto, char_length(c_cauda)) = c_cauda
                       then left(v_conf.texto, char_length(v_conf.texto) - char_length(c_cauda)) else v_conf.texto end;
        v_cauda := case
          when jsonb_array_length(v_pend) = 1
            then format(' Foi isso para o %s? *dia feito* lança a %s dele, ou conte o que mudou.', v_pend -> 0 ->> 'nome',
                        case when (v_pend -> 0 ->> 'meios')::int = 1 then 'meia diária' else 'diária' end)
          when jsonb_array_length(v_pend) > 1
            then format(' Foi isso para %s? *dia feito* lança as diárias deles, ou conte o que mudou.',
                        public._agenda_lista(array(select 'o ' || (e ->> 'nome') from jsonb_array_elements(v_pend) with ordinality t(e, o)
                                                    order by o), null))
          when (v_eq ->> 'aguardando')::int > 0 and cf.modo_diaria = 'ligado' then ' Foi isso? *dia feito* lança agora.'
          else c_cauda end;
        v_dia := v_base || coalesce(' ' || v_extra, '') || v_cauda;
      end if;
      v_ids := v_ids || (v_eq -> 'ids');
      for k in reverse cardinality(v_txts) .. 0 loop
        v_txt := v_dia
                 || case when k > 0 then ' Mudei sozinho: ' || array_to_string(v_txts[1:k], ' ')
                                         || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end
                         when cardinality(v_txts) > 0 then format(' Mudei sozinho %s: *o que mudou* mostra.',
                                                                   public._agenda_plural(cardinality(v_txts), 'coisa', 'coisas'))
                         else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', v_txt, 'perda', 70, 'pergunta_id', v_conf.id, 'acao_ids', v_ids,
        'modo', case when v_conf.modo = 'ligado' and cf.modo_vigia = 'ligado' and v_mod = 'ligado' then 'ligado' else 'sombra' end);
      -- FASE 3: o que a sombra da equipe e da diária diria, só no detalhe
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_som := v_dia || ' ' || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' ');
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_som, c_max), 'perda', 70,
                                             'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    elsif cardinality(v_txts) > 0 then
      for k in reverse cardinality(v_txts) .. 1 loop
        v_txt := 'Agenda, mudei sozinho. ' || array_to_string(v_txts[1:k], ' ')
                 || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'mudancas', 'texto', v_txt, 'perda', 40, 'pergunta_id', null, 'acao_ids', v_ids,
                                           'modo', v_mod);
    end if;
  end loop;
  -- a conferência na sombra sem nada a contar junto, ou de um modo sem mudança (o laço acima já cobriu quem teve)
  -- (nada a fazer: o laço passa pelos dois modos)

  -- FASE 3 (d1): sem a conferência aberta (todos confirmaram), o dia com o que a equipe e a diária contam numa linha
  -- própria: a diária que a agenda lançou ("*diária Roberto meia* corrige") e o último dia da OS.
  if v_conf.id is null and (v_extra is not null or jsonb_array_length(v_eq -> 'som') > 0) then
    v_base := public._agenda_texto_do_dia(p_hoje);
    if v_base is not null then
      v_cauda := case when jsonb_array_length(v_eq -> 'lancadas') > 0
                      then format(' *diária %s %s* corrige.', v_eq -> 'lancadas' -> 0 ->> 'nome',
                                  case when (v_eq -> 'lancadas' -> 0 ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end)
                      else '' end;
      if v_extra is not null then
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_base || ' ' || v_extra || v_cauda, c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', v_eq -> 'ids',
          'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
      end if;
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_out := v_out || jsonb_build_object('tipo', 'dia',
          'texto', public._agenda_corta(v_base || coalesce(' ' || v_extra, '') || ' '
                                        || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' '), c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    end if;
  end if;

  -- FASE 3 (d2): o que o gestor concluiu pela palavra do técnico (o técnico disse que terminou e era o último dia do
  -- plano), ainda não contado: a cobrança que a conclusão disse e o *desfaz* pelo número (a OS saiu da carteira).
  for q in select x.* from public.agenda_acoes x
            where x.tipo = 'concluir' and x.origem = 'equipe' and x.contada_em is null and x.desfeita_em is null
              and x.dia between v_ini and p_hoje
            order by x.criada_em, x.id loop
    v_tec := (select public._agenda_nome_curto(py.name) from public.agenda_equipe_mensagens em
                join public.payees py on py.id = em.payee_id where em.acao_id = q.id
               order by em.resposta_em desc nulls last limit 1);
    if q.executada then
      -- revisão da Fase 3 (item 5): o "vence hoje" de outro dia pelo ajudante único
      v_cob := public._agenda_vence_no_dia(regexp_replace(q.texto, '^[^—]* — saída [^.]*\.\s*', ''), q.dia, p_hoje);
      v_txt := format('Concluí o %s%s: o %s disse que terminou e era o último dia do plano.%s *desfaz %s* reabre.',
                      public._agenda_rotulo_da_os(q.service_order_id),
                      case when q.dia <> p_hoje then ' ' || public._dia_curto(q.dia) else '' end,
                      coalesce(v_tec, 'técnico'), coalesce(' ' || nullif(v_cob, q.texto), ''),
                      (select so.service_order_number from public.service_orders so where so.id = q.service_order_id));
    else
      v_txt := q.texto;
    end if;
    v_out := v_out || jsonb_build_object('tipo', 'conclusao', 'texto', public._agenda_corta(v_txt, c_max), 'perda', 45,
      'pergunta_id', null, 'acao_ids', jsonb_build_array(q.id),
      'modo', case when q.executada and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 7: (7a correção, achados 15 e 18; no lugar da linha (l) do 7a P11) (m) as perguntas do gestor que esperam o dono numa
  -- linha só: a ficha_estimativa de hoje (a ficha das 19:30 de um dia pela estimativa, que perde hoje), a situacao, a estimativa e
  -- o reestimar. Antes, cada uma disputava sozinha a vaga da pergunta de fato (e), de perda 30, e nenhuma chegava ao dono: o prazo
  -- só vale com a pergunta vista, e o gestor não marcava (Nelson, Flávio, Giancarlo e MP fora a semana inteira); a da ficha perdia
  -- para a mensagem ao cliente da véspera, e a ficha do 1º dia ficava segurada. A 1ª (a ficha; depois a de prazo mais perto) vai
  -- com o texto inteiro; as outras curtas, agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4
  -- dias; Flávio (OS-00104) 3,5 dias."; sem prazo: "Espero você: Giancarlo (OS-00130)."), até c_max_perg; o resto fica para
  -- *agenda gestor*. O fechamento que sai conta como mostradas todas as que a linha leva (pergunta_ids). Perda 75 com alguma de
  -- prazo (ela perde no prazo), 30 sem; modo = o da vigia.
  for m in select unnest(array['ligado', 'sombra']) loop
    v_f77_ids := '[]'::jsonb;
    v_f77_txt := null;
    v_f77_prazo := false;
    v_f77_segs := '{}';
    v_f77_grupo := null;
    v_f77_itens := '{}';
    v_f77_rest := 0;
    for v_f77_q in
      select x.id, x.texto, x.veto_ate, x.service_order_id, x.tipo,
             case when x.veto_ate is null then null
                  else public._dia_curto((x.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                       || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
             (select (o -> 'efeito' ->> 'dias')::numeric from jsonb_array_elements(coalesce(x.opcoes, '[]'::jsonb)) o
               where (o ->> 'n')::int = x.opcao_padrao limit 1) as dias_padrao
        from public.agenda_perguntas x
       where x.estado = 'aberta' and x.modo = m and not x.critica and x.opcao_escolhida is null
         and ((x.tipo = 'ficha_estimativa' and x.veto_ate is not null
               and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
              or (x.tipo in ('situacao', 'estimativa', 'reestimar')
                  and (x.veto_ate is null or (x.veto_ate at time zone 'America/Sao_Paulo')::date >= p_hoje)))
         and x.mostrada_vezes < cf.perguntas_vezes_max
         and not exists (select 1 from public.agenda_dono_avisos v
                          where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       order by x.tipo = 'ficha_estimativa' desc, x.veto_ate nulls last, x.criada_em, x.id
    loop
      if v_f77_txt is null then
        v_f77_txt := 'Agenda: ' || v_f77_q.texto;
        v_f77_ids := jsonb_build_array(v_f77_q.id);
        v_f77_prazo := v_f77_q.veto_ate is not null;
        continue;
      end if;
      if v_f77_rest > 0 then
        v_f77_rest := v_f77_rest + 1;
        continue;
      end if;
      -- (7a correção 2) sem prazo, o porquê junto: acima do teto de diárias o gestor não marca sozinho
      v_f77_nl := case when v_f77_q.ate is null then 'Espero você (não marco sozinho): ' else format('Também, sem resposta até %s: ', v_f77_q.ate) end;
      v_f77_item := public._agenda_rotulo_da_os(v_f77_q.service_order_id)
                    || case when v_f77_q.dias_padrao is not null then ' ' || public._agenda_dias(v_f77_q.dias_padrao) else '' end;
      if v_f77_nl is distinct from v_f77_grupo then
        v_f77_ns := v_f77_segs || case when v_f77_grupo is not null then array[v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.']
                                       else '{}'::text[] end;
        v_f77_ni := array[v_f77_item];
      else
        v_f77_ns := v_f77_segs;
        v_f77_ni := v_f77_itens || v_f77_item;
      end if;
      v_f77_l := v_f77_txt || ' ' || array_to_string(v_f77_ns || (v_f77_nl || array_to_string(v_f77_ni, '; ') || '.'), ' ');
      -- cabe com o "(e mais N em *agenda gestor*)" que pode vir depois
      if char_length(v_f77_l) > c_max_perg - 32 then
        v_f77_rest := 1;
        continue;
      end if;
      v_f77_segs := v_f77_ns;
      v_f77_grupo := v_f77_nl;
      v_f77_itens := v_f77_ni;
      v_f77_ids := v_f77_ids || to_jsonb(v_f77_q.id);
      v_f77_prazo := v_f77_prazo or v_f77_q.veto_ate is not null;
    end loop;
    continue when v_f77_txt is null;
    v_f77_l := v_f77_txt
               || case when v_f77_grupo is not null
                       then ' ' || array_to_string(v_f77_segs || (v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.'), ' ')
                       else '' end
               || case when v_f77_rest > 0 then format(' (e mais %s em *agenda gestor*)', v_f77_rest) else '' end;
    -- (7a correção 2, os achados 15/18 de novo) perda 76 com alguma de prazo: entre as linhas que perdem hoje ela ganha o desempate
    -- (antes, 75 com a mensagem ao cliente, ela perdia pelo tipo — "cliente" < "pergunta" — e saía primeiro no corte de 1.000)
    -- (7a correção 2) o objeto da linha entre parênteses: a forma curta (abaixo) entra nele, não como outro item da lista
    v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_f77_l, 'perda', case when v_f77_prazo then 76 else 30 end,
      'pergunta_id', v_f77_ids ->> 0, 'pergunta_ids', v_f77_ids, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end)
      -- (7a correção 2, o corte de 1.000 do fechamento) a mesma linha na forma curta (texto_curto), com as MESMAS perguntas: a
      -- ficha sem as opções ("… pela minha estimativa. Para segurar, me diga.") e cada uma pelo prazo e pelo que o gestor faz sem
      -- resposta ("Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; …"). O Secretário cheio (3 que ficaram, ~900
      -- caracteres) usa esta antes de tirar a linha — a inteira (~400) não cabia e as perguntas nunca eram vistas.
      || coalesce((select jsonb_build_object('texto_curto', k.t) from (select
           'Agenda: ' || concat_ws(' ',
             (select split_part(pc.texto, ' 1) Mande', 1) || ' Para segurar, me diga.' from public.agenda_perguntas pc
               where pc.id = (v_f77_ids ->> 0)::uuid and pc.tipo = 'ficha_estimativa'),
             (select string_agg(g.grupo || g.itens || '.', ' ' order by g.ord)
                from (select case when y.ate is null then 'Espero você (não marco sozinho): '
                                  else format('Sem resposta até %s, conto: ', y.ate) end as grupo,
                             string_agg(y.item, '; ' order by y.o) as itens, min(y.o) as ord
                        from (select t.o,
                                     case when pc.veto_ate is null then null
                                          else public._dia_curto((pc.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                                               || to_char(pc.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
                                     public._agenda_rotulo_da_os(pc.service_order_id)
                                     || coalesce(' ' || public._agenda_dias((select (op -> 'efeito' ->> 'dias')::numeric
                                                                               from jsonb_array_elements(coalesce(pc.opcoes, '[]'::jsonb)) op
                                                                              where (op ->> 'n')::int = pc.opcao_padrao limit 1)), '') as item
                                from jsonb_array_elements_text(v_f77_ids) with ordinality t(id, o)
                                join public.agenda_perguntas pc on pc.id = t.id::uuid
                               where pc.tipo <> 'ficha_estimativa') y
                       group by y.ate) g)) as t) k
         where char_length(k.t) < char_length(v_f77_l)), '{}'::jsonb));
  end loop;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) (n) a equipe: as perguntas abertas da equipe — a chamada (equipe_cadastro:chamada), a dos dias do
  -- dono (dias_semana), o telefone e o contato — numa linha só, nesta ordem e depois a mais antiga. Pela pergunta de fato (e), de perda
  -- 30, elas nunca entravam nas vagas (as de fornecedor estão abertas e nunca vistas desde 28/10): a chamada nunca seria vista nem
  -- venceria, e a pergunta da semana ficaria esperando por ela. A 1ª vai com o texto inteiro; as outras, curtas, até c_max_perg; o
  -- resto "(e mais N em *agenda equipe*)". pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas;
  -- a chamada vista ganha o prazo na rodada da semana). Perda 75 enquanto alguma nunca foi mostrada (o prazo só começa depois de vista)
  -- ou perde hoje (o veto_ate ou o perda_em de hoje): vaga própria entre as que perdem hoje; senão 30. Modo ligado só com a pergunta
  -- em ligado e o modo dela (o de _agenda_modo_da_pergunta: modo_dias; modo_cadastro fora de desligado, senão o do gestor) ligado.
  -- texto_curto = as mesmas perguntas só pelo nome. Só com modo_dias ou modo_cadastro fora de desligado (senão, o de antes); a (e)
  -- não as repete.
  v_7b_on := cf.modo_dias <> 'desligado' or cf.modo_cadastro <> 'desligado';
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
      for v_7b_q in
        select x.id, x.tipo, x.chave, x.texto, x.dia, x.mostrada_vezes, x.veto_ate, x.perda_em,
               coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = x.payee_id), '') as nome,
               case when x.tipo = 'dias_semana' then cf.modo_dias
                    when cf.modo_cadastro <> 'desligado' then cf.modo_cadastro
                    else public._agenda_gestor_modo('marcar') end as modo_agora
          from public.agenda_perguntas x
         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
           and x.mostrada_vezes < cf.perguntas_vezes_max
           and not exists (select 1 from public.agenda_dono_avisos v
                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
         order by case when x.chave like 'equipe_cadastro:chamada:%' then 1 when x.tipo = 'dias_semana' then 2
                       when x.chave like 'equipe_cadastro:telefone:%' then 3 else 4 end, x.criada_em, x.id
      loop
        v_7b_curto := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' then 'a equipe da agenda está certa?'
          when v_7b_q.tipo = 'dias_semana' then format('os dias da semana de %s', to_char(v_7b_q.dia, 'DD/MM'))
          when v_7b_q.chave like 'equipe_cadastro:telefone:%' then format('o telefone do %s', v_7b_q.nome)
          else format('%s na rotina da equipe?', v_7b_q.nome) end;
        if v_7b_txt is null then
          v_7b_txt := 'Agenda: ' || v_7b_q.texto;
        else
          if v_7b_rest > 0 then
            v_7b_rest := v_7b_rest + 1;
            continue;
          end if;
          v_7b_item := case
            when v_7b_q.chave like 'equipe_cadastro:telefone:%'
              then format('Também: o telefone do %s (sem ele não mando a ficha).', v_7b_q.nome)
            when v_7b_q.chave like 'equipe_cadastro:contato:%'
              then format('Também: %s tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*.', v_7b_q.nome)
            when v_7b_q.tipo = 'dias_semana'
              then format('Também: os dias da semana de %s (responda em *agenda pendências*).', to_char(v_7b_q.dia, 'DD/MM'))
            else 'Também: a chamada da equipe (responda em *agenda pendências*).' end;
          if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
            v_7b_rest := 1;
            continue;
          end if;
          v_7b_itens := v_7b_itens || v_7b_item;
        end if;
        v_7b_ids := v_7b_ids || to_jsonb(v_7b_q.id);
        -- (correção da revisão da 7b, achado 17) a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda
        -- pendências*)" não contam como mostradas: o dono não leu a pergunta (a dos dias, com a sugestão de quem chamar, contava como vista
        -- e vencia na quinta seguinte sem ele a ter lido). Elas ficam com mostrada_vezes 0 (a linha segue com perda 75) e saem inteiras no
        -- fechamento em que vierem primeiro. O telefone e o contato vão com a pergunta toda na forma curta e contam.
        if jsonb_array_length(v_7b_ids) > 1 and (v_7b_q.tipo = 'dias_semana' or v_7b_q.chave like 'equipe_cadastro:chamada:%') then
          v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
        end if;
        -- (correção da revisão da 7b: fim)
        -- (correção 3) a forma curta (texto_curto, a que o Secretário cheio usa) leva o prazo de cada pergunta que vence e o
        -- "sigo assim": o registro não sabe qual das formas saiu e conta como vistas todas as pergunta_ids (agenda_fechamento_registrar),
        -- então a chamada vista só como "a equipe da agenda está certa?" ganhava o prazo de equipe_chamada_prazo_du dias úteis sem o dono
        -- ter lido o "sigo assim". A data é a que o vencimento grava: a chamada contada aqui (a 1ª da linha; a do "Também" não conta, achado
        -- 17), com o cadastro fora de desligado, vence em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (a rodada da semana
        -- grava o veto_ate no tique seguinte; já gravado, o dele); a dos dias da semana, com modo_dias fora de desligado, vence no prazo da
        -- semana dela (o dia do plano em perda_em, hora_do_plano − equipe_dias_fechar_antes: o passo fechar de agenda_equipe_semana), vista
        -- ou não. O telefone e o contato não vencem: como antes. A forma longa não muda.
        v_c3_ate := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'desligado' and v_7b_ids ? v_7b_q.id::text
            then coalesce(v_7b_q.veto_ate,
                          public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo', cf.equipe_chamada_prazo_du))
          when v_7b_q.tipo = 'dias_semana' and cf.modo_dias <> 'desligado' and v_7b_q.perda_em is not null
            then ((v_7b_q.perda_em + cf.hora_do_plano) - cf.equipe_dias_fechar_antes) at time zone 'America/Sao_Paulo' end;
        if v_c3_ate is not null then
          v_7b_curto := v_7b_curto || format(' — sem resposta até %s às %s, sigo assim',
                                             public._dia_curto((v_c3_ate at time zone 'America/Sao_Paulo')::date),
                                             to_char(v_c3_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
        end if;
        -- (correção 3: fim)
        v_7b_curtos := v_7b_curtos || v_7b_curto;
        -- (correção da revisão da 7b, achado 7) a chamada da 7a (sem opções) é do gestor que marca, também com o cadastro da 7b
        -- em teste: a de antes, já aberta e ligada, não vira teste (o dono deixava de vê-la)
        if v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'ligado'
           and not exists (select 1 from public.agenda_perguntas p where p.id = v_7b_q.id and jsonb_array_length(p.opcoes) > 0) then
          v_7b_q.modo_agora := public._agenda_gestor_modo('marcar');
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_lig := v_7b_lig and v_7b_q.modo_agora = 'ligado';
        v_7b_perde := v_7b_perde or v_7b_q.mostrada_vezes = 0
                      or (v_7b_q.veto_ate is not null and (v_7b_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                      or v_7b_q.perda_em is not distinct from p_hoje;
      end loop;
      continue when v_7b_txt is null;
      v_7b_l := array_to_string(array[v_7b_txt] || v_7b_itens, ' ')
                || case when v_7b_rest > 0 then format(' (e mais %s em *agenda equipe*)', v_7b_rest) else '' end;
      v_7b_curto := 'Agenda, equipe: ' || array_to_string(v_7b_curtos, '; ')
                    || case when right(v_7b_curtos[cardinality(v_7b_curtos)], 1) = '?' then '' else '.' end
                    || ' *agenda pendências* mostra.';
      v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_7b_l, 'perda', case when v_7b_perde then 75 else 30 end,
        'pergunta_id', v_7b_ids ->> 0, 'pergunta_ids', v_7b_ids, 'acao_ids', '[]'::jsonb,
        'modo', case when m = 'ligado' and v_7b_lig then 'ligado' else 'sombra' end)
        || case when char_length(v_7b_curto) < char_length(v_7b_l) then jsonb_build_object('texto_curto', v_7b_curto)
                else '{}'::jsonb end);
    end loop;
  end if;
  -- FASE 7b: fim
  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max
     order by x.perda_em nulls last, x.criada_em, x.id limit 1;
    v_out := v_out || jsonb_build_object('tipo', 'pergunta',
      'texto', 'Agenda: ' || q.texto || case when v_n > 1 then format(' (e mais %s em *agenda pendências*)', v_n - 1) else '' end,
      'perda', 30, 'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (f): o PPC no último dia útil da semana (sexta; com feriado, o dia útil antes), se a semana teve compromisso
  v_ppc := public.agenda_ppc(p_hoje, p_hoje);
  if (v_ppc ->> 'ultimo_dia_util')::boolean and (v_ppc ->> 'compromissos')::int > 0 and v_ppc ->> 'linha' is not null then
    v_out := v_out || jsonb_build_object('tipo', 'ppc', 'texto', public._agenda_corta(v_ppc ->> 'linha', c_max), 'perda', 55,
      'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end if;

  -- FASE 3 (g): a comissão do mês que fechou, no 1º dia útil do mês (só a conta: nada é pago). Quem não pode ver a
  -- comissão (42501) não ganha a linha.
  if p_hoje = public.agenda_somar_du(make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1), 0) then
    begin
      v_com := public.comissao_resumo_do_mes(null, p_hoje);
    exception when sqlstate '42501' then
      v_com := null;
    end;
    if coalesce((v_com ->> 'primeiro_dia_util')::boolean, false) and nullif(v_com ->> 'linha', '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'comissao', 'texto', v_com ->> 'linha', 'perda', 20,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;

  -- FASE 7: (7a P7) (i) o "eu marcaria assim" do gestor em teste (spec §6.1): com o modo marcar em sombra, o texto_sombra do
  -- diário de hoje (a rodada do gestor das 16:52 o grava), perda 65, com o modo da vigia (o dono lê de verdade o que o gestor
  -- faria). (j) As compras da semana (agenda_gestor_dia.compras de hoje, que o P10 grava, [{texto, compre_ate, urgente}]): perda
  -- 80 com alguma compra urgente (AG7-07: o serviço começa a menos de compra_urgente_du dias úteis — vai como decisão), 65 com
  -- "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis; sem nada disso, nenhuma linha. O modo é o do compre_ate.
  if public._agenda_gestor_modo('marcar') = 'sombra' then
    select g.texto_sombra into v_f7_txt from public.agenda_gestor_dia g where g.dia = p_hoje;
    if nullif(btrim(v_f7_txt), '') is not null then
      -- (7a correção, achado 14) em teste, perda 25: abaixo de toda linha de verdade (só a comissão é menor) — a linha de teste
      -- não tira o lugar da semana publicada, da diária, da conclusão nem da pergunta que o dono precisa ver
      v_out := v_out || jsonb_build_object('tipo', 'gestor', 'texto', v_f7_txt, 'perda', 25, 'pergunta_id', null,
        'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  select g.compras into v_f7_cmp from public.agenda_gestor_dia g where g.dia = p_hoje;
  if jsonb_array_length(coalesce(v_f7_cmp, '[]'::jsonb)) > 0 then
    select min((e ->> 'compre_ate')::date), coalesce(bool_or((e ->> 'urgente')::boolean), false)
      into v_f7_min, v_f7_urg from jsonb_array_elements(v_f7_cmp) e;
    -- (7a correção, achado 19) o "compre até" de hoje (ou vencido, que comprando hoje ainda chega) é decisão de hoje: perda 80
    v_f7_perda := case when v_f7_urg or (v_f7_min is not null and v_f7_min <= p_hoje) then 80
                       when v_f7_min is not null and v_f7_min <= v_am1 then 65
                       when v_f7_min is not null and v_f7_min <= public.agenda_somar_du(p_hoje, cf.compras_aviso_du) then 45 end;
    v_f7_txt := array_to_string(array(select btrim(e ->> 'texto') from jsonb_array_elements(v_f7_cmp) with ordinality t(e, o)
                                       where nullif(btrim(e ->> 'texto'), '') is not null order by o), ' ');
    if v_f7_perda is not null and nullif(v_f7_txt, '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'compras', 'texto', public._agenda_corta('Compras: ' || v_f7_txt, c_max),
        'perda', v_f7_perda, 'pergunta_id', null, 'acao_ids', '[]'::jsonb,
        'modo', case when public._agenda_gestor_modo('compre_ate') = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  -- FASE 7: fim
  -- FASE 5: (h) a mensagem ao cliente, só com modo_cliente ligado: a que espera *manda cliente* e sai até o próximo dia de
  -- janela (perda 75; até 600 caracteres, c_max_cliente de _agenda_cliente_fechamento) e o que sai sozinho amanhã (perda 40,
  -- com *segura cliente*). As críticas (cliente_aviso) já entram pela linha decisao; o que saiu, pela linha mudancas.
  if cf.modo_cliente = 'ligado' then
    v_out := v_out || public._agenda_cliente_fechamento(p_hoje);
  end if;
  -- FASE 5: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o R5.10-7): na linha (n) da equipe, a forma curta (texto_curto, a que o Secretário cheio usa, e o registro conta as pergunta_ids da linha sem saber qual forma saiu) leva, em cada pergunta que vence, o prazo e o "sigo assim" — "Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra." —, com a data que o vencimento grava: a chamada contada na linha, com o cadastro fora de desligado, em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (ou o veto_ate já gravado); a dos dias da semana, com modo_dias fora de desligado, no prazo da semana dela (perda_em, hora_do_plano − equipe_dias_fechar_antes). O telefone e o contato não vencem: como antes. A forma longa e o resto, byte a byte.';

-- _agenda_gestor_dupla (de 20261101100800_agenda_fase77b_correcao.sql)
create or replace function public._agenda_gestor_dupla(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_marc  text := public._agenda_gestor_modo('marcar');
  v_seco  boolean;
  v_dono  uuid := public._agenda_dono(null);
  v_cong  date;
  v_os    uuid;
  v_f     jsonb;
  v_d     jsonb;
  v_pront jsonb;
  v_novas jsonb;
  v_try   jsonb;
  v_item  jsonb;
  v_val   jsonb;
  v_tipo  text;
  v_fonte text;
  v_ult   date;
  v_ondes text[];
  v_frases text[];
  v_pede  text;
  v_cli   text;
  v_txt   text;
  v_pid   uuid;
  v_its   jsonb;
  v_exp   timestamptz;
  v_a     jsonb;
  v_usado jsonb := '[]'::jsonb;
  v_feitas jsonb := '[]'::jsonb;
  v_acoes jsonb := '[]'::jsonb;
  v_fp    text;
  v_fp0   text;
  v_ditas uuid[] := '{}';
  v_semtec int;
  v_r     jsonb;
  m       jsonb;
  c       record;
  -- FASE 7b: (correção da revisão da 7b, achado 4) a revisão do dia seguinte pode cortar o fim do serviço?
  v_7bc_cort boolean;
  -- FASE 7b: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_dupla: sem o dia ou a hora' using errcode = '22004';
  end if;
  if cf.modo_dupla = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'dupla desligada');
  end if;
  if v_marc = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor desligado');
  end if;
  v_seco := cf.modo_dupla <> 'ligado' or v_marc <> 'ligado' or cf.modo_proposta <> 'ligado';
  perform set_config('agenda.hoje', p_hoje::text, true);
  if not v_seco then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- (i) a 2ª pessoa na dupla pela tarefa que foi com 1: em cada meio-dia de _agenda_dupla_faltando fora da zona travada, depois do
  -- congelado e que ainda não começou, a 1ª pessoa livre que não é o dono — primeiro quem o dono disse para aquela data, depois quem
  -- tem dias fixos —, sem outra coisa no meio-dia, validada pelas 14 regras (o teto) junto das outras já aceitas da OS. Nunca sozinha
  -- (o meio-dia já tem quem vai); nunca move o que já está.
  for v_os in select distinct a.service_order_id from public.agenda_alocacoes a
               where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno' and a.dia >= p_hoje
               order by 1 loop
    v_f := public._agenda_dupla_faltando(v_os, p_hoje);
    continue when jsonb_array_length(v_f) = 0;
    v_pront := public.os_prontidao(v_os, p_hoje);
    select min(a.tipo), min(a.duracao_fonte), max(a.dia) into v_tipo, v_fonte, v_ult
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
    -- FASE 7b: (correção da revisão da 7b, achado 4) acima da carga (sem o teto da equipe-semana) só quando a revisão do dia seguinte pode
    -- cortar o fim: o último dia do serviço depois do congelado e sem ficha à equipe nem aviso ao cliente nele (_agenda_dia_avisado de
    -- quem está nele). Senão a semana
    -- ficaria acima do teto até alguém mexer: a 2ª pessoa só entra dentro do teto (as 14 regras sem acima_da_carga).
    v_7bc_cort := v_ult > v_cong
                  and not exists (select 1 from public.agenda_alocacoes a
                                   where a.service_order_id = v_os and a.dia = v_ult and a.estado in ('publicada', 'fixada')
                                     and a.tipo <> 'reserva' and public._agenda_dia_avisado(a.payee_id, v_os, v_ult) is not null);
    -- FASE 7b: fim
    v_novas := '[]'::jsonb;
    for m in select e from jsonb_array_elements(v_f) e
              where not coalesce((e ->> 'travado')::boolean, false) and (e ->> 'dia')::date > v_cong
                and lower(public.agenda_periodo((e ->> 'dia')::date, e ->> 'turno', 'turno')) > p_agora
              order by (e ->> 'dia')::date, e ->> 'turno' loop
      for c in
        select k.payee_id, public._agenda_nome_curto(k.pessoa) as nome
          from public.agenda_capacidade((m ->> 'dia')::date, (m ->> 'dia')::date, p_hoje) k
         where k.turno = m ->> 'turno' and k.situacao = 'livre' and not k.eh_dono and k.payee_id is distinct from v_dono
           and not (to_jsonb(k.payee_id::text) <@ coalesce(m -> 'pessoas', '[]'::jsonb))
           and not exists (select 1 from public.agenda_alocacoes x
                            where x.payee_id = k.payee_id and x.estado in ('publicada', 'fixada')
                              and x.periodo && public.agenda_periodo((m ->> 'dia')::date, m ->> 'turno', 'turno'))
           and not exists (select 1 from jsonb_array_elements(v_usado) u
                            where u ->> 'payee_id' = k.payee_id::text and u ->> 'dia' = m ->> 'dia' and u ->> 'turno' = m ->> 'turno')
           and (exists (select 1 from public.agenda_disponibilidade d
                         where d.payee_id = k.payee_id and d.substituida_em is null and d.origem = 'dono' and d.periodo is not null
                           and d.periodo @> (m ->> 'dia')::date and d.situacao in ('disponivel', 'confirmada')
                           and (d.turno is null or d.turno = m ->> 'turno'))
                or not public._agenda_e_sob_demanda(k.payee_id, p_hoje))
         order by exists (select 1 from public.agenda_disponibilidade d
                           where d.payee_id = k.payee_id and d.substituida_em is null and d.origem = 'dono' and d.periodo is not null
                             and d.periodo @> (m ->> 'dia')::date and d.situacao in ('disponivel', 'confirmada')
                             and (d.turno is null or d.turno = m ->> 'turno')) desc,
                  k.pessoa, k.payee_id
      loop
        v_try := v_novas || jsonb_build_object('payee_id', c.payee_id, 'nome', c.nome, 'dia', m -> 'dia', 'turno', m -> 'turno',
                                               'presenca', 'turno');
        v_item := jsonb_build_object(
          'op', 'criar', 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
          'tipo', v_tipo, 'reserva_de', null, 'alocacoes', v_try,
          'de', (select min(e ->> 'dia') from jsonb_array_elements(v_try) e), 'ate', (select max(e ->> 'dia') from jsonb_array_elements(v_try) e),
          'fim_antes', v_ult, 'fim_depois', v_ult, 'atraso_du', null, 'condicao_tipo', null, 'critica', null, 'pergunta_chave', null,
          'decisao', null, 'espera', false, 'interrupcoes', 0, 'meios_do_dono', 0, 'fonte', v_fonte, 'dias', v_pront -> 'dias',
          'evento_real', false, 'fixar_dono', false, 'aviso_material', null, 'abre', false, 'fecha', false,
          'motivos', jsonb_build_array('dupla_completa'), 'texto', null, 'aplicado', false);
        -- acima da carga: o teto de 100% da pessoa e sem o teto da equipe-semana da 7a — o bloco de 1 pessoa já ocupa a semana do
        -- técnico, e a dupla acrescenta o que a revisão do dia seguinte corta no fim (as mesmas diárias-pessoa); sem isso, a dupla
        -- nunca se completaria na semana cheia
        v_val := public._agenda_validar_itens(jsonb_build_array(v_item),
                                              jsonb_build_object('p_restricoes', jsonb_build_object('acima_da_carga', true)), p_hoje, p_agora,
                                              false, jsonb_build_object(v_os::text, v_pront));
        -- FASE 7b: (correção da revisão da 7b, achado 4) sem o corte possível, dentro do teto
        if not v_7bc_cort then
          v_val := public._agenda_validar_itens(jsonb_build_array(v_item), jsonb_build_object('p_restricoes', '{}'::jsonb), p_hoje, p_agora,
                                                false, jsonb_build_object(v_os::text, v_pront));
        end if;
        -- FASE 7b: fim
        -- FASE 7b: (correção 3) (o W3a da correção 2) o dono que já está de turno no meio-dia (vai junto o tempo todo: a marina nova)
        -- não falta: a regra 4 confere só as alocações do item, e o item leva só a 2ª pessoa — "OS-00074: falta você ter 10/11 de manhã"
        -- segurava a dupla pela tarefa para sempre (o dono que vai junto não é a 2ª pessoa: dk_dono_conta). Só essa violação sai
        -- (_agenda_dupla_sem_falta_voce); agenda_validar faz o mesmo com a proposta deste passo, no aplicar.
        v_val := public._agenda_dupla_sem_falta_voce(v_val);
        -- FASE 7b: fim (correção 3)
        if jsonb_array_length(v_val) = 0 then
          v_novas := v_try;
          v_usado := v_usado || jsonb_build_object('payee_id', c.payee_id, 'dia', m -> 'dia', 'turno', m -> 'turno');
          exit;
        end if;
      end loop;
    end loop;
    continue when jsonb_array_length(v_novas) = 0;
    -- a frase (spec R4.4 item 4): "Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2
    -- pessoas. *desfaz Lenine* volta."
    v_d := public._agenda_dupla_da_os(v_os);
    v_ondes := array(select distinct e ->> 'onde' from jsonb_array_elements(v_f) e
                      where exists (select 1 from jsonb_array_elements(v_novas) n where n ->> 'dia' = e ->> 'dia' and n ->> 'turno' = e ->> 'turno'));
    v_frases := array(select distinct on (q ->> 'motivo') q ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) q
                       where q ->> 'onde' = any (v_ondes) and q ->> 'onde' <> 'todos' order by q ->> 'motivo');
    v_pede := case when 'todos' = any (v_ondes)
                   then format('o serviço todo pede 2 pessoas (%s)', (select q ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) q
                                                                        where q ->> 'onde' = 'todos' limit 1))
                   else format('%s %s 2 pessoas', public._agenda_lista(v_frases), case when cardinality(v_frases) > 1 then 'pedem' else 'pede' end) end;
    v_cli := coalesce(v_pront ->> 'cliente_curto', v_pront ->> 'numero');
    v_txt := format('Pus %s com %s no %s %s: %s. *desfaz %s* volta.',
                    public._agenda_lista(array(select z.n from (select n ->> 'nome' as n, min(o) as o from jsonb_array_elements(v_novas) with ordinality t(n, o)
                                                                group by 1) z order by z.o)),
                    coalesce(nullif(public._agenda_lista(array(
                      select distinct case when p::uuid is not distinct from v_dono then 'você' else public._agenda_nome_curto(py.name) end
                        from jsonb_array_elements(v_f) e cross join lateral jsonb_array_elements_text(coalesce(e -> 'pessoas', '[]'::jsonb)) p
                        join public.payees py on py.id = p::uuid
                       where exists (select 1 from jsonb_array_elements(v_novas) n where n ->> 'dia' = e ->> 'dia' and n ->> 'turno' = e ->> 'turno')
                       order by 1)), ''), 'quem vai'),
                    v_cli, public._agenda_meios_frase(v_novas), v_pede, v_cli);
    if v_seco then
      v_feitas := v_feitas || jsonb_build_object('os', v_os, 'numero', v_pront ->> 'numero', 'alocacoes', v_novas, 'texto', v_txt);
      continue;
    end if;
    -- a proposta só com as alocações novas, validada e aplicada por agenda_aplicar (o molde de _agenda_gestor_reparar): a ação
    -- reparar, desfazível; a marca dupla_completa na proposta e nas alocações
    v_its := jsonb_build_array(v_item - 'alocacoes' || jsonb_build_object(
               'alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                               from jsonb_array_elements(v_novas) with ordinality u(a, j)),
               'de', (select min(e ->> 'dia') from jsonb_array_elements(v_novas) e), 'ate', (select max(e ->> 'dia') from jsonb_array_elements(v_novas) e),
               'texto', v_txt));
    v_pid := gen_random_uuid();
    v_exp := least(p_agora + cf.proposta_validade,
                   coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', 'turno')))
                               from jsonb_array_elements(v_novas) a), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, 'replano',
            daterange((select min((e ->> 'dia')::date) from jsonb_array_elements(v_novas) e),
                      (select max((e ->> 'dia')::date) from jsonb_array_elements(v_novas) e), '[]'),
            array[v_os], cf.versao_plano, 'ligado', 'aberta', v_its, '[]'::jsonb, '{}'::jsonb,
            jsonb_build_object('titulo', 'Mudanças na agenda', 'linhas', jsonb_build_array(v_txt), 'fora', '[]'::jsonb, 'resumo', v_txt),
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', null, 'p_ate', null, 'p_os', jsonb_build_array(v_os),
                               'p_restricoes', jsonb_build_object('acima_da_carga', true), 'escopo', 'replano', 'origem', 'vigia',
                               'gestor', jsonb_build_object('tipo', 'reparar', 'motivo', 'dupla_completa',
                                                            'textos', jsonb_build_object(v_os::text, v_txt))),
            null, 'vigia', null, p_agora, v_exp);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         duracao_fonte, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, v_os, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno', 'turno', v_tipo,
           'proposta', 'motor', v_pid, v_fonte, jsonb_build_array('dupla_completa'), p_agora
      from jsonb_array_elements(v_its -> 0 -> 'alocacoes') with ordinality u(a, j)
     order by j;
    v_a := public.agenda_aplicar(v_pid, null, 'vigia', null, null, p_hoje, p_agora);
    if not coalesce((v_a ->> 'ok')::boolean, false) then
      perform public.agenda_descartar(v_pid, null, 'a dupla não passou no aplicar');
      perform public.log_app_error('db', 'agenda: a 2ª pessoa da dupla não aplicou: ' || coalesce(v_a ->> 'texto', '?'),
                                   'agenda', 'gestor:dupla', 'warn',
                                   jsonb_build_object('os', v_os, 'proposta', v_pid, 'violacoes', v_a -> 'violacoes',
                                                      'p_hoje', p_hoje, 'p_agora', p_agora));
      continue;
    end if;
    v_feitas := v_feitas || jsonb_build_object('os', v_os, 'numero', v_pront ->> 'numero', 'alocacoes', v_novas, 'texto', v_txt,
                                               'proposta_id', v_pid);
    v_acoes := v_acoes || coalesce(v_a -> 'acoes', '[]'::jsonb);
  end loop;

  -- (ii) a dupla dita (sem compromisso) que esperava a 2ª pessoa e agora a tem pela régua dos técnicos só por quem vem sob demanda (a
  -- classe não é mais a 4 dupla, mas os de dias fixos não bastam: o dupla_sd do P4, R4.3(c)): a montagem dela (_agenda_propor_e_aplicar,
  -- a vigia; a onda K vale). Só quando os dias de alguém mudaram desde o tique que fez isso por último (fp: as linhas de disponibilidade
  -- vivas) — a dita que continua sem bloco (o fora dupla do R4.3(c)) não vira uma proposta nova a cada tique.
  v_fp := md5(coalesce((select string_agg(d.id::text, ',' order by d.id) from public.agenda_disponibilidade d
                         where d.substituida_em is null and d.payee_id is distinct from v_dono), ''));
  select r.contagens #>> '{dupla,fp}' into v_fp0
    from public.agenda_vigia_rodadas r
   where r.rotina = 'gestor' and r.p_agora <= p_agora and jsonb_typeof(r.contagens -> 'dupla') = 'object' and (r.contagens -> 'dupla') ? 'fp'
   order by r.p_agora desc, r.rodou_em desc limit 1;
  if v_seco or v_fp is distinct from v_fp0 then
    v_semtec := (select count(*)::int from jsonb_array_elements(coalesce(public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) q
                  where not coalesce((q ->> 'eh_dono')::boolean, false));
    v_ditas := array(
      select z.os from (
        select k.service_order_id as os, k.numero, mm.v as m, public._agenda_classe_agora(k.service_order_id, p_hoje) as cl
          from public.os_carteira(p_hoje) k
          join public.os_planejamento pl on pl.service_order_id = k.service_order_id
          cross join lateral (select public.agenda_meios_da_os(k.service_order_id, p_hoje) as v) mm
         where pl.dupla_dita in ('todos', 'inicio', 'fim') and not public._agenda_os_tem_dia(k.service_order_id, p_hoje)) z
       where not coalesce((z.m ->> 'equipe_dita')::boolean, false)
         and not (z.cl ->> 'classe' = '4' and z.cl ->> 'motivo' = 'dupla')
         and v_semtec < greatest(coalesce((z.m #>> '{por_turno,manha,desejado}')::int, 0), coalesce((z.m #>> '{por_turno,tarde,desejado}')::int, 0),
                                 coalesce((select max(dd::int) from jsonb_array_elements_text(coalesce(z.m -> 'dk', '[]'::jsonb)) dd), 0)
                                 - case when coalesce((z.m ->> 'dk_dono_conta')::boolean, true)
                                             and (coalesce((z.m #>> '{dono_turno,manha}')::boolean, false)
                                                  or coalesce((z.m #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end)
       order by z.numero, z.os);
    if not v_seco and cardinality(v_ditas) > 0 then
      v_r := public._agenda_propor_e_aplicar('os', v_ditas, 'vigia', null, p_hoje, p_agora);
      v_acoes := v_acoes || coalesce(v_r -> 'acoes', '[]'::jsonb);
    end if;
  end if;

  if v_seco then
    return jsonb_build_object('pulado', true, 'motivo', 'em teste', 'em_teste', true,
                              'completaria', v_feitas, 'ditas', to_jsonb(v_ditas));
  end if;
  return jsonb_build_object('completadas', jsonb_array_length(v_feitas), 'os', v_feitas, 'acoes', v_acoes,
                            'ditas', to_jsonb(v_ditas),
                            'marcou', case when v_r is not null then jsonb_build_object('ok', v_r -> 'ok', 'texto', v_r -> 'texto',
                                                                                         'fora', v_r -> 'fora') end,
                            'fp', v_fp);
end;
$function$;

comment on function public._agenda_gestor_dupla(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P6; R4.4 item 4, R4.9-5): o passo de todo tique dupla da rodada do gestor (barato: só as OS com dupla). modo_dupla desligado ou o gestor que marca desligado = {pulado}. (i) A 2ª pessoa na dupla pela tarefa que foi com 1: em cada meio-dia de _agenda_dupla_faltando fora da zona travada, depois do congelado e que ainda não começou, a 1ª pessoa livre que não é o dono (primeiro quem o dono disse para aquela data, depois quem tem dias fixos), sem outra coisa no meio-dia, validada pelas 14 regras com as outras já aceitas da OS e acima da carga (o teto de 100% da pessoa, sem o teto da equipe-semana: a revisão do dia seguinte corta o que a dupla encurta); nunca sozinha, nunca move o que já está. Uma proposta por OS (escopo replano, criada_por vigia, modo ligado; parametros.gestor {tipo reparar, motivo dupla_completa, textos}) só com as alocações novas (motivos [dupla_completa]), aplicada por agenda_aplicar: a ação reparar, desfazível — "Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas. *desfaz Lenine* volta." Não passou no aplicar = descartada, app_error_logs gestor:dupla (warn). (ii) A dupla dita (sem compromisso) que esperava a 2ª pessoa e agora a tem pela régua dos técnicos só por quem vem sob demanda (a classe deixou de ser a 4 dupla, e os de dias fixos não bastam: o dupla_sd do P4): _agenda_propor_e_aplicar(os, …, vigia) — a onda K vale; só quando as linhas de disponibilidade vivas mudaram desde o tique que fez isso por último (fp na contagem da rodada). Em teste (modo_dupla ou o gestor em sombra, ou a agenda automática fora de ligado): {pulado, em_teste, completaria, ditas}, nada gravado. {completadas, os, acoes, ditas, marcou, fp}. VOLATILE, invoker, sem grant (só a rodada do gestor o chama). CORREÇÃO DA REVISÃO DA 7b (achado 4): acima da carga (o teto de 100% da pessoa, sem o teto da equipe-semana) só quando a revisão do dia seguinte pode cortar o fim — o último dia do serviço depois do congelado e sem ficha ou aviso ao cliente (_agenda_dia_avisado); senão a 2ª pessoa é validada e aplicada dentro do teto (sem acima_da_carga), e na semana cheia a dupla fica sem a 2ª pessoa (o foco e o cartão dizem). CORREÇÃO 3 DA 7b (o W3a da correção 2): a 2ª pessoa entra também no meio-dia em que o dono já está de turno (a presença o tempo todo da marina nova, com a linha dos dias do dono) — a validação tira só a regra 4 "falta você" desse meio-dia (_agenda_dupla_sem_falta_voce); antes ela segurava a dupla pela tarefa para sempre ("OS-00074: falta você ter 10/11 de manhã"). Sem o dono de turno no meio-dia, a de antes, byte a byte.';

-- agenda_validar (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public.agenda_validar(p_proposta uuid, p_os uuid[] default null, p_hoje date default public._hoje_brt(),
                                                 p_agora timestamptz default now(), p_pergunta uuid default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_p public.agenda_propostas%rowtype;
begin
  select * into v_p from public.agenda_propostas where id = p_proposta;
  if not found then
    raise exception 'Não encontrei esse plano.' using errcode = 'P0002';
  end if;
  -- FASE 7b: (correção 3) (o W3a da correção 2) a proposta do passo dupla da 7b (parametros.gestor.motivo = dupla_completa: só
  -- _agenda_gestor_dupla a cria) sem a regra 4 "falta você" no meio-dia em que o dono já está de turno na OS — a mesma régua com que o
  -- passo a montou (_agenda_dupla_sem_falta_voce); sem isso agenda_aplicar a recusava. As outras propostas, como antes, byte a byte.
  if v_p.parametros #>> '{gestor,motivo}' = 'dupla_completa' then
    return public._agenda_dupla_sem_falta_voce(
             public._agenda_validar_itens(public._agenda_itens_escolhidos(v_p.itens, p_os, p_pergunta), v_p.parametros,
                                          p_hoje, p_agora, true));
  end if;
  -- FASE 7b: fim (correção 3)
  return public._agenda_validar_itens(public._agenda_itens_escolhidos(v_p.itens, p_os, p_pergunta), v_p.parametros,
                                      p_hoje, p_agora, true);
end;
$function$;

comment on function public.agenda_validar(uuid, uuid[], date, timestamptz, uuid) is
  'Agenda de Produção (Fase 2, P2): valida o que agenda_aplicar aplicaria de uma proposta (as OS de p_os, ou todas; os não críticos e os críticos decididos por p_pergunta) pelas 14 regras duras de _agenda_validar_itens, contra o banco de agora. Lista vazia = ok. CORREÇÃO 3 DA 7b (o W3a da correção 2): a proposta do passo dupla da 7b (parametros.gestor.motivo = dupla_completa) é validada sem a regra 4 "falta você" no meio-dia em que o dono já está de turno na OS (_agenda_dupla_sem_falta_voce), a mesma régua com que o passo a montou. As outras, como antes, byte a byte.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- As duas novas: invoker; authenticated e service_role (o molde de _agenda_e_novato; agenda_validar é leitura do painel); nunca anon
-- (revogar de public E de anon). As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a
-- migration se bastar): a escada e o passo dupla para ninguém (só as funções definer da agenda os chamam); o novato, o fechamento e
-- agenda_validar com authenticated e service_role.
revoke all on function public._agenda_tecnico_declarado(uuid, date), public._agenda_dupla_sem_falta_voce(jsonb),
  public._agenda_e_novato(uuid, date), public._agenda_linhas_do_fechamento(date), public.agenda_validar(uuid, uuid[], date, timestamptz, uuid)
  from public, anon;
grant execute on function public._agenda_tecnico_declarado(uuid, date), public._agenda_dupla_sem_falta_voce(jsonb),
  public._agenda_e_novato(uuid, date), public._agenda_linhas_do_fechamento(date), public.agenda_validar(uuid, uuid[], date, timestamptz, uuid)
  to authenticated, service_role;
revoke all on function public._agenda_gestor_reparo(uuid, date, timestamptz), public._agenda_gestor_dupla(date, timestamptz)
  from public, anon, authenticated, service_role;
