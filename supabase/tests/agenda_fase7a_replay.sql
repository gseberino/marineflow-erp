-- A prova com a carteira REAL de qui 29/10/2026 16:52 (spec-fase7a §8.3): os cenários A (tudo em sombra), B (a 7a-0 ligada) e D
-- (*gestor, só propor*), do pacote P7 (migration 20261031100600). O P8 acrescenta o C (o prazo vence e o encaixe marca), o P10 o
-- E (compre até) e o P11 o F (cliente). O replay (fixture-replay-2910.sql) com a presença do dono de produção no Lenine e no
-- Vanderlei (abre e fecha: o replay sozinho dá "sempre", notas do P2).
-- bancada: depende de 20261031100850
--
--   A  tudo em sombra (o estado depois da migration de dado): (1) a prontidão das 11, os meios, a classe e o motor (a semana e as
--      11) saem iguais aos de desligado (md5) — o portão é falso fora da simulação; os testes do P2, P3 e P5 provam desligado = as
--      definições de antes; (2) a rodada do gestor das 16:52 não escreve alocação, proposta, ação executada, mensagem nem fila;
--      (3) o diário: Lenine e Vanderlei marcados, Giancarlo, Nelson, Flávio e MP perguntados, 5 fora; (4) o texto do fechamento
--      (§6.1; desde o 7a P12 o sinal não segura — AG7-09 — e o MP, sem mão de obra, sai de "esperando o sinal" para a pergunta)
--   B  a 7a-0 ligada (o caminho da revisão: agenda_propor das 11 persistir + aplicar): o Lenine em compromisso de ter 03 a ter 10/11
--      (12 meios-dias, 1 pessoa por meio-dia, você abre e fecha, a reserva promovida); o Vanderlei de qui 12 a ter 24/11 (15
--      meios-dias); de fora, cada um pelo seu porquê (Giancarlo estimativa, Nelson situacao, Flávio material, Rodrigo-96 padrao_do_dono,
--      Kalmar ×2 e Rodrigo-76 cliente, Robson orcamento, MP estimativa); 0 choques; nada em qui 29 e sex 30/10; nenhuma crítica sem
--      pergunta; todas as alocações novas com duracao_fonte orcamento; o texto das ações com "(estimativa minha: …)"
--   C  (P8) B + as perguntas do gestor das 16:52, vistas no fechamento das 17:30, e a rodada do gestor de sex 30/10 18:07 (o prazo
--      vence): o passo vetos aplica as 4 (Flávio 3,5 dias, Nelson 4, Giancarlo 10 e, desde o 7a P12, o MP 1 dia; as ações estimar
--      de origem vigia) e o encaixe do MESMO tique as pega pelas ações estimar: o MP marcado a partir de sex 13/11 — e o passo
--      sinal do mesmo tique lembra o dono de cobrar o sinal dele (P12, C3) —; o Nelson marcado a partir de ter 24/11 (depois do
--      Vanderlei, pelo teto da equipe); o
--      Giancarlo sem encaixe em 6 semanas com a equipe de hoje (10 dias com 1 pessoa); o Flávio de fora pelo material (o compressor);
--      nenhuma onda (OS novas não contam); a cobertura das 6 com mão de obra e sem espera do cliente: 3 (a spec dizia 4 de 6, com
--      os números de antes do P3 e do P5: ver notas-fase77a.md, P8)
--   D  B + *gestor, só propor*: os modos efetivos voltam a sombra, a regra fecha, a rodada seguinte não aplica nada, o publicado fica
--   E  (P10) B + o passo compre_ate, dia a dia, sem ninguém comprar: qui 29/10 as 3 linhas do Vanderlei com o "compre até" qui
--      29/10 (o prazo padrão: 7 dias úteis sem fornecedor) e a pergunta "Compre até hoje: 3 itens de Vanderlei …"; sex 30/10 a vigia
--      não mexe (comprando hoje ainda chega para qui 12/11) e o gestor só cobra ("Venceu qui 29/10 …"); ter 03/11 a vigia empurra
--      (o 1º empurrão, pelo material) e o gestor cobra o último dia ("Compre até hoje: … o serviço segue em sex 13/11."); qua 04/11
--      o 2º atraso já é do dono (a pergunta crítica segundo_atraso da Fase 2): nada automático, a cobrança fecha e o empurrão não
--      conta. (A spec dizia o 1º empurrão em qua 04/11 e a reserva no 3º vencimento, com 4 e 2 dias úteis; o limite de 2
--      empurrões automáticos está no C2d de agenda_fase7a_compras.sql.)
--   F  (P11) B + a rodada do cliente de qui 29/10 17:05 (modo_cliente ligado, como produção), com o tipo confirmar já liberado
--      pela Fase 5 (3 dias aprovados de outro cliente): a confirmação do Lenine (o D-3 de ter 03/11 já passou: sai na rodada, a
--      variante primeira) fica pedida — por estimativa, sem compra pendente —, com base.dados.por_estimativa e a pergunta ao dono
--      "… o dia é pela minha estimativa …"; o Vanderlei, com compra pendente, não recebe M1 (o material incompleto: a regra da
--      Fase 5; a semana prevista é do 7f); o zero cliente_estimativa_sem_aprovacao da saúde fica 0
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há o replay: PULADO. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.modos(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id
$f$;
-- A leitura do motor e da prontidão das 11 (md5): a prontidão, os meios e a classe de cada uma, a semana e as 11 em simulação.
create function pg_temp.leitura(p_cart uuid[], p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v_s jsonb;
  v_o jsonb;
begin
  v_s := public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, p_hoje, p_agora);
  v_o := public.agenda_propor('os', null, null, p_cart, '{}'::jsonb, false, 'motor', null, p_hoje, p_agora);
  return jsonb_build_object(
    'prontidao', md5((select string_agg(public.os_prontidao(o, p_hoje)::text, '|' order by o) from unnest(p_cart) o)),
    'meios', md5((select string_agg(public.agenda_meios_da_os(o, p_hoje)::text, '|' order by o) from unnest(p_cart) o)),
    'classe', md5((select string_agg((public._agenda_classe_agora(o, p_hoje) - 'pront')::text, '|' order by o) from unnest(p_cart) o)),
    'semana', md5((v_s - 'proposta_id')::text), 'oss', md5((v_o - 'proposta_id')::text));
end $f$;
create function pg_temp.escritas() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(a.id::text || a.estado, ',' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select count(*) from public.agenda_acoes where executada),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'fila', (select count(*) from public.whatsapp_send_queue))
$f$;

do $rp$
declare
  v_res   jsonb := '[]'::jsonb;
  c_d29   constant date := date '2026-10-29';
  c_a29   constant timestamptz := timestamptz '2026-10-29 16:52-03';
  -- (7a P12: o sinal combinado e não pago não segura mais — AG7-09 —: o MP, sem mão de obra, passa de "esperando o sinal" à
  -- pergunta; o "(e mais 1)" e os 5 de fora)
  c_txt   constant text := 'Agenda em teste (nada mudou): eu marcaria assim — Lenine de ter 03 a ter 10/11, Roberto e João (6 dias, estimativa minha); Vanderlei de qui 12 a ter 24/11, Roberto e João (7,5 dias, estimativa minha; compre até hoje: 3 itens). Antes de marcar eu perguntaria: Giancarlo (10 diárias pela estimativa), Nelson (já começou?), Flávio (já começou?) (e mais 1). Continuam fora 5: esperando o cliente (3), orçamento sem virar OS, precisa de você em campo. *agenda gestor* mostra tudo.';
  v_cart  uuid[];
  v_dono  uuid;
  v_adm   uuid;
  v_len   uuid;
  v_van   uuid;
  v_l0    jsonb;
  v_l1    jsonb;
  v_e0    jsonb;
  v_s     jsonb;
  v_p     jsonb;
  v_ap    jsonb;
  v_t     text;
  v_pub   text;
  v_c     jsonb;
  v_t2    text;
  v_t3    text;
  v_n     int;
  v_n2    int;
  v_q     boolean;
  v_e     jsonb := '{}'::jsonb;
  r       jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('A, B e D (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.replay2910');
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
    v_cart := array(select k.service_order_id from public.os_carteira(c_d29) k order by k.numero);
    v_dono := public._agenda_dono(null);
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');

    -- ── A. Tudo em sombra ──
    perform pg_temp.modos('desligado');
    v_l0 := pg_temp.leitura(v_cart, c_d29, c_a29);
    perform pg_temp.modos('sombra');
    v_l1 := pg_temp.leitura(v_cart, c_d29, c_a29);
    v_res := pg_temp.ok(v_res, 'A1 em sombra, a prontidão das 11, os meios, a classe, a semana e o motor das 11 saem iguais aos de desligado (md5): fora da simulação o portão das regras é falso',
      v_l0 = v_l1 and cardinality(v_cart) = 11, v_l1::text);
    v_e0 := pg_temp.escritas();
    r := public.agenda_gestor_rodar(c_d29, c_a29);
    v_res := pg_temp.ok(v_res, 'A2 a rodada do gestor das 16:52 (os diários) não escreve alocação, proposta, ação executada, mensagem à equipe ou ao cliente, nem fila',
      (r ->> 'rodou')::boolean and (r ->> 'diaria')::boolean and pg_temp.escritas() = v_e0 and pg_temp.leitura(v_cart, c_d29, c_a29) = v_l0,
      (pg_temp.escritas())::text);
    select g.sombra, g.texto_sombra into v_s, v_t from public.agenda_gestor_dia g where g.dia = c_d29;
    v_res := pg_temp.ok(v_res, 'A3 o diário: Lenine e Vanderlei marcados (pela estimativa), Giancarlo, Nelson, Flávio e MP (o sinal não segura desde o 7a P12) perguntados, 5 fora',
      (select string_agg(e ->> 'cliente', ',' order by o) from jsonb_array_elements(v_s -> 'itens') with ordinality t(e, o)) = 'Lenine,Vanderlei'
      and (select string_agg(e ->> 'cliente', ',' order by o) from jsonb_array_elements(v_s -> 'perguntas') with ordinality t(e, o)) = 'Giancarlo,Nelson,Flávio,MP'
      and jsonb_array_length(v_s -> 'fora') = 5, left(v_s::text, 600));
    v_res := pg_temp.ok(v_res, 'A4 o texto do fechamento (spec §6.1, com os números de agora) no diário e na linha gestor das linhas do fechamento',
      v_t = c_txt and exists (select 1 from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d29)) x
                               where x ->> 'tipo' = 'gestor' and x ->> 'texto' = c_txt), v_t);

    -- ── B. A 7a-0 ligada: o caminho da revisão (as 11 pelo motor, persistir e aplicar) ──
    perform pg_temp.modos('ligado');
    v_p := public.agenda_propor('os', null, null, v_cart, '{}'::jsonb, true, 'vigia', null, c_d29, c_a29);
    v_ap := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, c_d29, c_a29);
    v_res := pg_temp.ok(v_res, 'B1 aplicada sem crítica: as duas marcadas pela estimativa e a reserva do Lenine promovida',
      (v_ap ->> 'ok')::boolean
      and not exists (select 1 from jsonb_array_elements(v_p -> 'itens') i where i ->> 'critica' is not null)
      and jsonb_array_length(v_p -> 'perguntas') = 0, left(v_ap ->> 'texto', 600));
    v_res := pg_temp.ok(v_res, 'B2 o Lenine: compromisso de ter 03 a ter 10/11, 12 meios-dias de 1 pessoa por meio-dia, você abre (ter 03) e fecha (ter 10); as 12 reservas canceladas como promovidas',
      (select min(a.dia) = date '2026-11-03' and max(a.dia) = date '2026-11-10' and count(*) = 12
         from public.agenda_alocacoes a where a.service_order_id = v_len and a.estado = 'publicada' and a.tipo <> 'reserva' and a.presenca = 'turno')
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_len and a.estado = 'publicada'
                       and a.presenca = 'turno' group by a.dia, a.turno having count(*) > 1)
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_len and a.estado = 'publicada' and a.payee_id = v_dono
                   and a.presenca = 'abertura' and a.dia = date '2026-11-03')
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_len and a.estado = 'publicada' and a.payee_id = v_dono
                   and a.presenca = 'fechamento' and a.dia = date '2026-11-10')
      and (select count(*) = 12 and bool_and(a.cancelada_motivo = 'promovida') from public.agenda_alocacoes a
            where a.service_order_id = v_len and a.tipo = 'reserva'),
      (select string_agg(format('%s %s %s', a.dia, a.turno, a.presenca), ' | ' order by a.dia, a.turno) from public.agenda_alocacoes a
        where a.service_order_id = v_len and a.estado = 'publicada'));
    v_res := pg_temp.ok(v_res, 'B3 o Vanderlei: compromisso de qui 12 a ter 24/11, 15 meios-dias de 1 pessoa por meio-dia (o prazo padrão de 7 dias úteis + 1 de compra interna)',
      (select min(a.dia) = date '2026-11-12' and max(a.dia) = date '2026-11-24' and count(*) = 15
         from public.agenda_alocacoes a where a.service_order_id = v_van and a.estado = 'publicada' and a.tipo <> 'reserva' and a.presenca = 'turno')
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_van and a.estado = 'publicada'
                       and a.presenca = 'turno' group by a.dia, a.turno having count(*) > 1), null);
    select string_agg(f ->> 'numero' || ':' || (f ->> 'motivo'), ' ' order by f ->> 'numero') into v_t
      from jsonb_array_elements(v_p -> 'fora') f;
    v_res := pg_temp.ok(v_res, 'B4 de fora, cada um pelo seu porquê: Giancarlo estimativa, Nelson situacao, Flávio material, Rodrigo-96 padrao_do_dono, Kalmar ×2 e Rodrigo-76 cliente, Robson orcamento, MP estimativa (sem mão de obra; o sinal não segura desde o 7a P12)',
      v_t = 'ORÇ-00083:orcamento ORÇ-00095:estimativa OS-00032:cliente OS-00033:cliente OS-00076:cliente OS-00096:padrao_do_dono OS-00104:material OS-00112:situacao OS-00130:estimativa',
      v_t);
    v_res := pg_temp.ok(v_res, 'B5 0 choques, nada em qui 29 e sex 30/10 (hoje e o próximo dia útil), nenhuma crítica executada sem a pergunta',
      (select count(*) from public.agenda_alocacoes a join public.agenda_alocacoes b
          on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
        where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada')) = 0
      and not exists (select 1 from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada') and a.dia in (c_d29, c_d29 + 1))
      and (public.agenda_saude(c_d29, c_a29) -> 'criticas' ->> 'sem_decisao')::int = 0, null);
    v_res := pg_temp.ok(v_res, 'B6 todas as alocações novas com duracao_fonte orcamento e o texto das ações com "(estimativa minha: …)"',
      not exists (select 1 from public.agenda_alocacoes a where a.estado = 'publicada' and a.tipo <> 'reserva'
                   and a.duracao_fonte is distinct from 'orcamento')
      and (select bool_and(x.texto like '%(estimativa minha: 6 dias)%' or x.texto like '%(estimativa minha: 7,5 dias)%' or x.tipo = 'promover_reserva')
             from public.agenda_acoes x where x.proposta_id = (v_p ->> 'proposta_id')::uuid)
      and (select count(*) from public.agenda_acoes x where x.proposta_id = (v_p ->> 'proposta_id')::uuid and x.texto like '%(estimativa minha:%') = 2,
      (select string_agg(x.tipo || ': ' || left(x.texto, 120), ' | ') from public.agenda_acoes x where x.proposta_id = (v_p ->> 'proposta_id')::uuid));

    -- ── C. O prazo vence e o encaixe do mesmo tique (P8) ──
    begin
      r := public._agenda_gestor_perguntas(c_d29, c_a29);
      -- as 3 perguntas do gestor vistas pelo dono antes do prazo (o fechamento das 17:30)
      update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_d29, '17:30'), mostrada_via = 'fechamento'
       where estado = 'aberta' and modo = 'ligado' and tipo in ('situacao', 'estimativa');
      get diagnostics v_n = row_count;
      r := public.agenda_gestor_rodar(c_d29 + 1, pg_temp.em(c_d29 + 1, '18:07'));
      v_c := r -> 'contagens';
      select string_agg(so.service_order_number || ':' || public._agenda_dias(pl.dias), ' ' order by so.service_order_number)
        into v_t from public.os_planejamento pl join public.service_orders so on so.id = pl.service_order_id
       where pl.estimativa_fonte = 'orcamento';
      select string_agg(format('%s:%s:%s', e ->> 'numero', e ->> 'resultado', coalesce(e ->> 'primeiro_dia', e ->> 'motivo', '-')), ' '
                        order by e ->> 'numero')
        into v_t2 from jsonb_array_elements(v_c -> 'encaixe' -> 'por_os') e;
      v_n2 := (select count(*) from unnest(array['OS-00074', 'OS-00069', 'OS-00130', 'OS-00112', 'OS-00104', 'OS-00096']) n
                where public._agenda_os_tem_dia(pg_temp.os(n), c_d29 + 1));
      v_q := not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda')
             and (select count(*) = 4 and bool_and(a.origem = 'vigia') from public.agenda_acoes a where a.tipo = 'estimar' and a.executada);
      -- (7a P12) o passo sinal do mesmo tique: o MP, marcado sem o sinal pago, ganha a pergunta sinal ao dono
      v_t3 := (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'sinal' and q.estado = 'aberta');
      raise exception 'desfaz C' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- (7a P12: o MP, sem o sinal travando, é a 4ª pergunta vista e o prazo dá 1 dia a ele — sem_mo_dias —; o encaixe o marca)
    v_res := pg_temp.ok(v_res, 'C1 o prazo vence (sex 30/10 18:07, as 4 perguntas vistas às 17:30): o passo vetos aplica as 4 — Flávio 3,5 dias, Nelson 4 dias, Giancarlo 10 dias, MP 1 dia (a estimativa, fonte orcamento) — com as 4 ações estimar de origem vigia',
      v_n = 4 and (v_c -> 'vetos' ->> 'aplicadas')::int = 4 and v_t = 'ORÇ-00095:1 dia OS-00104:3,5 dias OS-00112:4 dias OS-00130:10 dias' and v_q,
      coalesce(v_t, '-') || ' | ' || left(coalesce((v_c -> 'vetos')::text, '-'), 300));
    v_res := pg_temp.ok(v_res, 'C2 o encaixe do mesmo tique pega as 4 (pelas ações estimar): o Nelson marcado a partir de ter 24/11 e o MP a partir de sex 13/11; o Giancarlo sem encaixe em 6 semanas com a equipe de hoje; o Flávio de fora pelo material; nenhuma onda; com mão de obra e sem espera do cliente, 3 das 6 com data',
      v_t2 = 'ORÇ-00095:marcada:2026-11-13 OS-00104:fora:material OS-00112:marcada:2026-11-24 OS-00130:fora:sem_encaixe'
      and not (v_c -> 'encaixe' ->> 'onda')::boolean and (v_c -> 'encaixe' ->> 'candidatas')::int = 4 and v_n2 = 3
      and jsonb_array_length(v_c -> 'falhas') = 0,
      coalesce(v_t2, '-') || ' | cobertura ' || coalesce(v_n2::text, '-'));
    v_res := pg_temp.ok(v_res, 'C3 (7a P12, AG7-09 "marco e cobro o sinal") o passo sinal do mesmo tique: o MP marcado com o sinal não pago (sem recebível) ganha a pergunta ao dono, sem o valor; nada ao cliente',
      v_t3 = 'Marquei MP (ORÇ-00095) a partir de sex 13/11 e o sinal ainda não entrou: cobre quando puder. Para o cliente eu não digo nada sobre isso.'
      and (v_c -> 'sinal' ->> 'novas')::int = 1,
      coalesce(v_t3, '-') || ' | ' || coalesce((v_c -> 'sinal')::text, '-'));

    -- ── E. O "compre até" (P10): ninguém compra os 3 itens do Vanderlei ──
    begin
      r := public._agenda_gestor_compre_ate(c_d29, c_a29);
      v_e := v_e || jsonb_build_object(
        'e1_linhas', (select count(*) from public.os_material m where m.service_order_id = v_van and m.compre_ate = c_d29
                       and m.compre_ate_base ->> 'prazo_fonte' = 'padrao' and m.compre_ate_base ->> 'primeiro' = '2026-11-12'),
        'e1_texto', (select q.texto from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta'
                      and q.service_order_id = v_van));
      r := public._agenda_vigia_violacoes(c_d29 + 1, pg_temp.em(c_d29 + 1, '08:00'));
      v_e := v_e || jsonb_build_object('e2_violadas', r -> 'violadas');
      r := public._agenda_gestor_compre_ate(c_d29 + 1, pg_temp.em(c_d29 + 1, '16:52'));
      v_e := v_e || jsonb_build_object(
        'e2_texto', (select q.texto from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta'
                      and q.service_order_id = v_van),
        'e2_abertas', (select count(*) from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta'));
      r := public._agenda_vigia_violacoes(date '2026-11-03', pg_temp.em(date '2026-11-03', '08:00'));
      v_e := v_e || jsonb_build_object(
        'e3_acao', (select a.tipo || ':' || a.origem || ':' || a.motivo from public.agenda_acoes a
                     where a.service_order_id = v_van and a.dia = date '2026-11-03' and a.executada order by a.criada_em desc limit 1),
        'e3_plano', (select min(a.dia)::text from public.agenda_alocacoes a where a.service_order_id = v_van
                      and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= date '2026-11-03'));
      r := public._agenda_gestor_compre_ate(date '2026-11-03', pg_temp.em(date '2026-11-03', '16:52'));
      v_e := v_e || jsonb_build_object(
        'e3_empurrados', r -> 'empurrados',
        'e3_vezes', (select string_agg(distinct m.empurrada_vezes::text, ',') from public.os_material m
                      where m.service_order_id = v_van and m.compre_ate is not null),
        'e3_texto', (select q.texto from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta'
                      and q.service_order_id = v_van));
      r := public._agenda_vigia_violacoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '08:00'));
      r := public._agenda_gestor_compre_ate(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:52'));
      v_e := v_e || jsonb_build_object(
        'e4_critica', (select q.tipo || ':' || q.estado from public.agenda_perguntas q where q.service_order_id = v_van
                        and q.critica order by q.criada_em desc limit 1),
        'e4_compromisso', exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_van
                                   and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= date '2026-11-04'),
        'e4_abertas', (select count(*) from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta'),
        'e4_vezes', (select string_agg(distinct m.empurrada_vezes::text, ',') from public.os_material m
                      where m.service_order_id = v_van and m.compre_ate is not null));
      raise exception 'desfaz E' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'E1 qui 29/10 16:52 (o passo compre_ate ligado): as 3 linhas críticas do Vanderlei com o "compre até" qui 29/10 pelo prazo padrão (7 dias úteis sem fornecedor, + 1 de folga e 1 de compra interna, antes de qui 12/11) e a pergunta "Compre até hoje: 3 itens de Vanderlei (…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço segue em qui 12/11."',
      (v_e ->> 'e1_linhas')::int = 3
      and v_e ->> 'e1_texto' = 'Compre até hoje: 3 itens de Vanderlei (Kit Cabos/ Conectores/…, Cabos Elétricos Diversos… e Kit cabos eletricos…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço segue em qui 12/11.',
      v_e::text);
    v_res := pg_temp.ok(v_res, 'E2 sex 30/10 sem a compra: comprando hoje ainda chega para qui 12/11 — a vigia não mexe e o gestor só cobra ("Venceu qui 29/10 o ''compre até'' de 3 itens de Vanderlei. Comprando hoje ainda chega para qui 12/11."; a de ontem resolvida)',
      (v_e ->> 'e2_violadas')::int = 0 and (v_e ->> 'e2_abertas')::int = 1
      and v_e ->> 'e2_texto' = 'Venceu qui 29/10 o ''compre até'' de 3 itens de Vanderlei. Comprando hoje ainda chega para qui 12/11.',
      v_e::text);
    v_res := pg_temp.ok(v_res, 'E3 ter 03/11 sem a compra: a vigia empurra o Vanderlei para sex 13/11 pelo material (o 1º empurrão: 1 nos 3 itens) e o gestor cobra o último dia: "Compre até hoje: … Comprando hoje, o serviço segue em sex 13/11."',
      v_e ->> 'e3_acao' = 'mover:vigia:material, replanejado' and v_e ->> 'e3_plano' = '2026-11-13'
      and (v_e ->> 'e3_empurrados')::int = 3 and v_e ->> 'e3_vezes' = '1'
      and v_e ->> 'e3_texto' = 'Compre até hoje: 3 itens de Vanderlei (Kit Cabos/ Conectores/…, Cabos Elétricos Diversos… e Kit cabos eletricos…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço segue em sex 13/11.',
      v_e::text);
    v_res := pg_temp.ok(v_res, 'E4 qua 04/11 sem a compra: o 2º atraso é do dono (a pergunta crítica segundo_atraso da Fase 2, aberta) — nada automático, o Vanderlei fica sem compromisso, a cobrança fecha e o empurrão do dono não conta (continua 1)',
      v_e ->> 'e4_critica' = 'segundo_atraso:aberta' and not (v_e ->> 'e4_compromisso')::boolean
      and (v_e ->> 'e4_abertas')::int = 0 and v_e ->> 'e4_vezes' = '1', v_e::text);

    -- ── F. O cliente (P11): a confirmação por estimativa pede o sim do dono; com compra pendente, nenhum M1 ──
    begin
      -- o tipo confirmar já liberado pela Fase 5: 3 dias aprovados de outro cliente (a Kalmar), sem estimativa
      insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                   aprovacao, aprovada_em, estado, dedupe_key, enviada_em)
      select so.client_id, so.id, 'confirmar', 'rodada', 'ligado', 'mensagem de teste (F)', pg_temp.em(date '2026-09-01' + k, '10:00'),
             pg_temp.em(date '2026-09-01' + k, '11:00'), 'aprovada', pg_temp.em(date '2026-09-01' + k, '10:00'), 'enviada',
             'agenda-cliente:replay-f:' || k, pg_temp.em(date '2026-09-01' + k, '10:00')
        from generate_series(0, 2) k, public.service_orders so where so.service_order_number = 'OS-00032';
      r := public.agenda_cliente_vigiar(c_d29, pg_temp.em(c_d29, '17:05'));
      v_e := jsonb_build_object(
        'liberado', public._agenda_cliente_tipo_liberado('confirmar'),
        'lenine', (select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'variante', m.variante, 'aprovacao', m.aprovacao, 'estado', m.estado,
                                                       'dia', m.dia_alvo, 'est', m.base -> 'dados' ->> 'por_estimativa', 'pergunta', q.texto))
                     from public.agenda_cliente_mensagens m left join public.agenda_perguntas q on q.id = m.pergunta_id
                    where m.service_order_id = v_len),
        'vanderlei', (select count(*) from public.agenda_cliente_mensagens m where m.service_order_id = v_van),
        'compra', public._agenda_os_compra_pendente(v_van, c_d29) and not public._agenda_os_compra_pendente(v_len, c_d29),
        'estimativa', public._agenda_os_por_estimativa(v_len, c_d29) and public._agenda_os_por_estimativa(v_van, c_d29),
        'saude', public.agenda_saude(c_d29, pg_temp.em(c_d29, '17:20')) -> 'gestor' ->> 'cliente_estimativa_sem_aprovacao');
      raise exception 'desfaz F' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'F1 qui 29/10 17:05, o tipo confirmar já liberado pela Fase 5: a confirmação do Lenine (variante primeira, ter 03/11) fica pedida, esperando o dono — marcado pela estimativa, sem compra pendente —, com base.dados.por_estimativa e a pergunta "Mensagem para Lenine (confirmação; o dia é pela minha estimativa), sai amanhã às 09:00: …"',
      (v_e ->> 'liberado')::boolean and (v_e ->> 'estimativa')::boolean and jsonb_array_length(v_e -> 'lenine') = 1
      and v_e -> 'lenine' -> 0 ->> 'tipo' = 'confirmar' and v_e -> 'lenine' -> 0 ->> 'variante' = 'primeira'
      and v_e -> 'lenine' -> 0 ->> 'aprovacao' = 'pedida' and v_e -> 'lenine' -> 0 ->> 'estado' = 'aguardando_dono'
      and v_e -> 'lenine' -> 0 ->> 'dia' = '2026-11-03' and v_e -> 'lenine' -> 0 ->> 'est' = 'true'
      and v_e -> 'lenine' -> 0 ->> 'pergunta' like 'Mensagem para Lenine (confirmação; o dia é pela minha estimativa), sai amanhã às 09:00: "%',
      v_e::text);
    v_res := pg_temp.ok(v_res, 'F2 o Vanderlei, com compra pendente (3 itens críticos em falta), não recebe M1 nem véspera (o material incompleto: a regra da Fase 5; a semana prevista é do 7f); o zero cliente_estimativa_sem_aprovacao da saúde fica 0',
      (v_e ->> 'compra')::boolean and (v_e ->> 'vanderlei')::int = 0 and (v_e ->> 'saude')::int = 0, v_e::text);

    -- ── D. *gestor, só propor* ──
    v_pub := (select md5(string_agg(a.id::text || a.estado, ',' order by a.id)) from public.agenda_alocacoes a);
    r := public.agenda_gestor_dito(v_adm, true, c_d29, pg_temp.em(c_d29, '17:40'));
    v_res := pg_temp.ok(v_res, 'D1 *gestor, só propor*: os modos efetivos do gestor voltam a sombra (a vaga do fechamento fica) e as regras fecham',
      (r ->> 'mudou')::boolean and public._agenda_gestor_modo('marcar') = 'sombra' and public._agenda_gestor_modo('encaixe') = 'sombra'
      and public._agenda_gestor_modo('revisao') = 'sombra' and public._agenda_gestor_modo('compre_ate') = 'sombra'
      and public._agenda_gestor_modo('vaga') = 'ligado' and not public._agenda_gestor_regra('estimativa'), r::text);
    v_e0 := pg_temp.escritas();
    r := public.agenda_gestor_rodar(c_d29 + 1, pg_temp.em(c_d29 + 1, '16:52'));
    v_res := pg_temp.ok(v_res, 'D2 a rodada seguinte (sex 30/10 16:52) faz a conta em teste e não aplica nada; o publicado fica',
      (r ->> 'rodou')::boolean and r -> 'modos' ->> 'marcar' = 'sombra' and (r ->> 'acoes')::int = 0
      and pg_temp.escritas() = v_e0
      and (select md5(string_agg(a.id::text || a.estado, ',' order by a.id)) from public.agenda_alocacoes a) = v_pub
      and exists (select 1 from public.agenda_gestor_dia g where g.dia = c_d29 + 1 and g.sombra <> '{}'::jsonb), left(r::text, 400));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$rp$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
