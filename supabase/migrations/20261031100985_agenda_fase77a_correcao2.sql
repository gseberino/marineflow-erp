-- Agenda de Produção, Fase 7a ("ele marca sozinho"): a CORREÇÃO 2 — o que a 2ª revisão da etapa achou e o cético confirmou (30/10/2026).
-- (4 funções novas; 18 recriadas da definição mais nova; nenhuma tabela, coluna, lista, job ou dado muda)
--
-- NÃO APLICADA. Depende de 20261031100000 a 20261031100980 (as 14 de estrutura da 7a); vai antes do dado 20261031100990 (os modos em
-- sombra). Com os 5 modos do gestor desligados (como nascem), nada muda nas Fases 1 a 6: toda mudança está atrás de uma regra do
-- gestor (_agenda_gestor_regra), de um modo do gestor ou de dado que só a 7a grava (o "compre até", a pergunta do gestor, a dupla dita,
-- o motivo dupla). O teste supabase/tests/agenda_fase77a_correcao2.sql (Y0–Y15) prova cada uma e o "byte a byte" das de antes da 7a.
--
-- ═══ O QUE MUDA ═══ (o que a 2ª revisão achou; o nome curto é o da seção "CORREÇÃO 2 DA REVISÃO DA 7a" de notas-fase77a.md)
--   1. A linha das perguntas do gestor ganha o desempate (perda 76): no corte de 1.000 do fechamento ela saía primeiro
--      (_agenda_linhas_do_fechamento; o resto do conserto é no Secretário: secretario-tarde-texto.ts encolhe o dele antes de tirar uma
--      linha garantida). Sem prazo, "Espero você (não marco sozinho): …".
--   2. A dupla sem a 2ª pessoa: com a regra uma_pessoa, a OS que pede 2 pessoas e a grade com menos técnicos espera o dono (classe 4,
--      motivo dupla, "falta a 2ª pessoa"), a palavra *<nome> com dupla* diz quem está e o que fazer, e o foco também
--      (_agenda_classe_da_os, agenda_dupla_dita, _agenda_ver_gestor, _agenda_gestor_motivo_texto/_ordem, _agenda_aviso_fora_texto;
--      novas _agenda_tecnicos_da_grade e _agenda_tecnicos_frase). Antes a OS saía do plano calada e nunca voltava.
--   3. O *desfaz* vale até a OS mudar: a remarcação automática (a reserva da quinta da vigia, o motor) não solta mais a trava
--      (_agenda_gestor_desfeito); o foco diz "você desfez", não "sem lugar na agenda" (_agenda_ver_gestor).
--   4. A ficha prometida a quem não tem telefone: o gestor só pergunta a ficha de quem a recebe (nova _agenda_equipe_tem_telefone,
--      _agenda_gestor_fichas); a ficha segurada de quem não tem telefone diz o porquê ("Alex não tem telefone no cadastro. Fale com
--      Alex."), e a pergunta fechada "ela foi como eu disse" com a ficha recusada ganha o motivo verdadeiro (_agenda_rotina_ficha).
--   5. O dono "sempre" não é o técnico: com a regra uma_pessoa, a OS de presença sempre (marina nova, o que ele disse) leva o técnico
--      e o dono junto; diagnóstico e comissionamento continuam com ele (agenda_meios_da_os).
--   6. O "compre até" da OS que a vigia tirou do plano pelo material: o empurrão conta, a cobrança continua ("César saiu da agenda:
--      …"), as compras do fechamento a mantêm, e no teto ela volta à reserva com o "de quem e quando?" (nova _agenda_gestor_compra_saiu,
--      _agenda_compras_da_semana, _agenda_gestor_compre_ate).
--   7. Acima de 8 diárias: a pergunta sem prazo que venceu volta (o gestor pergunta de novo a cada 7 dias) e o serviço grande ganha a
--      opção "Já terminou (ou já entreguei)" (_agenda_gestor_perguntar, _agenda_gestor_perguntas_da_os).
--   8. O aviso: o prazo das perguntas do gestor que ele conta como vistas ("Sem resposta até qua 04/11 às 18:00, faço o que eu
--      disse."), a frase do gestor com ponto e sem repetir a pergunta da situação, e a mesma OS sem dois *desfaz* (agenda_aviso_pecas,
--      _agenda_aprontar_de).
--   9. A parada conta o planejamento que o dono mexeu, como o comentário da correção 1 dizia (_agenda_os_situacao).
--
-- ═══ CÓPIA ═══ Cada função recriada é a definição mais nova pelo nome do arquivo (o montador para se outra a redefinir depois):
--   · _agenda_classe_da_os (de 20261031100900_agenda_fase7a_sinal_sabado.sql)
--   · agenda_meios_da_os (de 20261031100100_agenda_fase7a_duracao.sql)
--   · agenda_dupla_dita (de 20261031100100_agenda_fase7a_duracao.sql)
--   · _agenda_gestor_fichas (de 20261031100850_agenda_fase7a_protecoes.sql)
--   · _agenda_rotina_ficha (de 20261031100850_agenda_fase7a_protecoes.sql)
--   · _agenda_gestor_desfeito (de 20261031100980_agenda_fase77a_correcao.sql)
--   · _agenda_ver_gestor (de 20261031100980_agenda_fase77a_correcao.sql)
--   · _agenda_gestor_motivo_texto (de 20261031100600_agenda_fase7a_rodada.sql)
--   · _agenda_gestor_motivo_ordem (de 20261031100600_agenda_fase7a_rodada.sql)
--   · _agenda_aviso_fora_texto (de 20261031100980_agenda_fase77a_correcao.sql)
--   · _agenda_gestor_perguntar (de 20261031100300_agenda_fase7a_perguntas.sql)
--   · _agenda_gestor_perguntas_da_os (de 20261031100980_agenda_fase77a_correcao.sql)
--   · _agenda_linhas_do_fechamento (de 20261031100980_agenda_fase77a_correcao.sql)
--   · agenda_aviso_pecas (de 20261031100980_agenda_fase77a_correcao.sql)
--   · _agenda_os_situacao (de 20261031100980_agenda_fase77a_correcao.sql)
--   · _agenda_aprontar_de (de 20261031100980_agenda_fase77a_correcao.sql)
--   · _agenda_compras_da_semana (de 20261031100800_agenda_fase7a_compras.sql)
--   · _agenda_gestor_compre_ate (de 20261031100800_agenda_fase7a_compras.sql)
-- As mudanças estão em blocos "-- FASE 7: (7a correção 2, …) … -- FASE 7: fim" ou, dentro de um bloco da 7a que já existia (nas de
-- antes da 7a) e nas nascidas na 7a, em linhas marcadas "(7a correção 2". Nas de antes da 7a, sem os blocos da Fase 7, o corpo de
-- antes da 7a, byte a byte (o Y15 confere). Quem recriar de novo qualquer uma delas copia DESTA migration. Montada por
-- scratchpad/agenda-pesquisa/f7a/rev2/corr2/montar-migration.mjs.
-- ATENÇÃO (achado da cópia): _agenda_aviso_mudancas e _agenda_aviso_fora_texto (do lote de 30/10, EM PRODUÇÃO desde 30/10) foram
-- mudadas pela 100980 no lugar, em linhas marcadas "(7a correção" (os tipos reparar, reestimar, estimar e a ficha segurada; os motivos
-- situacao e estimativa), fora de bloco "-- FASE 7:". O cabeçalho da 100980 as chama "do lote de 30/10 que só a 7a usa": não é
-- isso — elas servem o aviso de produção. Com o gestor desligado a saída é a mesma (os tipos e motivos novos só nascem com a 7a): o
-- Y14 confere contra a definição de 20261030100300 rodada como pg_temp.
--
-- APLICAR (só com o OK nomeado do dono, junto das outras da 7a, depois da 20261031100980 e antes da 20261031100990):
--   npx supabase db query --linked -f supabase/migrations/20261031100985_agenda_fase77a_correcao2.sql
--
-- DESFAZER: recriar cada função com o corpo da origem (o arquivo dito antes de cada uma) e só então apagar as 4 novas
-- (_agenda_equipe_tem_telefone, _agenda_tecnicos_da_grade, _agenda_tecnicos_frase, _agenda_gestor_compra_saiu). NUNCA reaplicar uma
-- migration da 7a mais velha depois desta (volta as definições velhas sem nada acusar): reaplicar a da origem de cada função, ou
-- esta inteira.
--
-- IDEMPOTENTE: create or replace function, comment, revoke e grant.

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- (a ficha prometida a quem não tem telefone) Quem da equipe tem para onde mandar a ficha: a MESMA régua de _agenda_equipe_registrar
-- (Fase 3, passos 6 e 7: payees.phone só com os dígitos; 10 ou 11 dígitos ganham o 55; com wa_test_mode, o número de teste; menos
-- de 12 dígitos = sem telefone). O teste agenda_fase77a_correcao2 (Y3) confere as duas réguas nos mesmos casos.
create or replace function public._agenda_equipe_tem_telefone(p_payee uuid)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_fone  text;
  v_teste boolean;
begin
  select regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') into v_fone from public.payees p where p.id = p_payee;
  if length(coalesce(v_fone, '')) in (10, 11) then
    v_fone := '55' || v_fone;
  end if;
  v_teste := coalesce((select s.value::text from public.app_settings s where s.key = 'wa_test_mode'), 'false') in ('true', '"true"');
  if v_teste then
    v_fone := nullif(regexp_replace(coalesce((select s.value::text from public.app_settings s where s.key = 'wa_test_number'), ''),
                                    '\D', '', 'g'), '');
  end if;
  return length(coalesce(v_fone, '')) >= 12;
end;
$function$;

comment on function public._agenda_equipe_tem_telefone(uuid) is
  'Agenda de Produção (Fase 7a, correção 2 da revisão): a pessoa tem para onde a ficha ir? A mesma régua do passo do telefone de _agenda_equipe_registrar (payees.phone só dígitos, 10/11 dígitos + 55; wa_test_mode = o número de teste; < 12 dígitos = não). O gestor só pergunta a ficha de quem a recebe (_agenda_gestor_fichas), e a ficha segurada de quem não tem telefone diz o porquê (_agenda_rotina_ficha). STABLE, invoker, sem grant.';

-- (a dupla sem a 2ª pessoa) Os técnicos que a agenda conta (agenda_capacidade_semanal, sem o dono), pelos nomes curtos, e a frase
-- "só Alex está na equipe" / "ninguém está na equipe da agenda" / "só Alex e Mateus estão na equipe".
create or replace function public._agenda_tecnicos_da_grade(p_hoje date)
 returns text[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(x ->> 'nome' order by o), '{}'::text[])
    from jsonb_array_elements(coalesce(public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) with ordinality t(x, o)
   where not coalesce((x ->> 'eh_dono')::boolean, false);
$function$;

comment on function public._agenda_tecnicos_da_grade(date) is
  'Agenda de Produção (Fase 7a, correção 2 da revisão): os nomes curtos de quem a agenda conta na equipe (agenda_capacidade_semanal de p_hoje), sem o dono, na ordem dela. A dupla dita com menos técnicos do que ela pede espera o dono (_agenda_classe_da_os), e a palavra *<nome> com dupla* e o foco gestor dizem quem está. STABLE, invoker; authenticated e service_role (as leituras do painel e do foco chegam aqui).';

create or replace function public._agenda_tecnicos_frase(p_tec text[])
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case coalesce(cardinality(p_tec), 0)
    when 0 then 'ninguém está na equipe da agenda'
    when 1 then 'só ' || p_tec[1] || ' está na equipe'
    else 'só ' || array_to_string(p_tec[1:cardinality(p_tec) - 1], ', ') || ' e ' || p_tec[cardinality(p_tec)] || ' estão na equipe' end;
$function$;

comment on function public._agenda_tecnicos_frase(text[]) is
  'Agenda de Produção (Fase 7a, correção 2 da revisão): "só Alex está na equipe", "só Alex e Mateus estão na equipe", "ninguém está na equipe da agenda" (os nomes de _agenda_tecnicos_da_grade). IMMUTABLE.';

-- (o "compre até" da OS que a vigia tirou do plano; D7-2, spec §3.2 "Compra" e §5.10) As OS da carteira que saíram da agenda pelo
-- material sem a compra: sem compromisso de hoje em diante, com a última retirada do plano (as alocações canceladas juntas por
-- último, fora a reserva) feita pelo material, e com algum item do "compre até" gravado em falta, sem compra combinada, cujo "compre
-- até" venceu até o dia da saída. Cada item com o que o passo do compre até precisa: o prazo da conta gravada (compre_ate_base), o
-- dia em que a peça chega para começar comprando hoje (chega_em: hoje + prazo + folga em dias úteis; o importado em dias corridos),
-- os empurrões (o desta saída já contado? contado = compre_ate_base.saiu_em é esta saída) e o teto (limite). Sem isso, o passo só via
-- OS com compromisso: a OS aprovada saía em ~38 h (o César), a cobrança era resolvida "não precisa mais" e o empurrão nunca contava.
create or replace function public._agenda_gestor_compra_saiu(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config := public._agenda_cfg();
  r     record;
  v_its jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if p_hoje is null then
    raise exception '_agenda_gestor_compra_saiu: sem o dia de hoje' using errcode = '22004';
  end if;
  for r in
    select so.id as os, so.service_order_number as numero,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente, x.saiu_em
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
      cross join lateral (select max(a.cancelada_em) as saiu_em from public.agenda_alocacoes a
                           where a.service_order_id = so.id and a.tipo <> 'reserva' and a.estado = 'cancelada') x
     where x.saiu_em is not null
       and exists (select 1 from public.os_material m
                    where m.service_order_id = so.id and m.compre_ate is not null and m.situacao = 'falta'
                      and m.compra_prevista_em is null)
       and exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = so.id and a.tipo <> 'reserva' and a.estado = 'cancelada'
                      and a.cancelada_motivo = 'material' and a.cancelada_em = x.saiu_em)
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = so.id and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
                          and a.dia >= p_hoje and a.resultado is null)
       and so.id in (select k.service_order_id from public.os_carteira(p_hoje) k)
     order by so.service_order_number collate "C", so.id
  loop
    select jsonb_agg(jsonb_build_object(
             'linha', m.id, 'item', public._agenda_corta(m.descricao, 60), 'descricao', m.descricao,
             'quantidade', trim_scale(m.quantidade_necessaria - m.quantidade_na_mao), 'fornecedor', m.fornecedor_nome,
             'prazo', (m.compre_ate_base ->> 'prazo')::int, 'corridos', (m.compre_ate_base ->> 'corridos')::int,
             'prazo_fonte', m.compre_ate_base ->> 'prazo_fonte', 'compre_ate', m.compre_ate, 'ate', m.compre_ate,
             'primeiro_antes', m.compre_ate_base ->> 'primeiro',
             'chega_em', case when m.compre_ate_base ->> 'prazo' is not null
                              then public.agenda_somar_du(p_hoje, (m.compre_ate_base ->> 'prazo')::int + c.folga_material_du)
                              when m.compre_ate_base ->> 'corridos' is not null
                              then public.agenda_somar_du(p_hoje + (m.compre_ate_base ->> 'corridos')::int, c.folga_material_du) end,
             'contado', coalesce(m.compre_ate_base -> 'saiu_em' = to_jsonb(r.saiu_em), false),
             'empurrada_vezes', m.empurrada_vezes
                                + case when coalesce(m.compre_ate_base -> 'saiu_em' = to_jsonb(r.saiu_em), false) then 0 else 1 end,
             'limite', m.empurrada_vezes + case when coalesce(m.compre_ate_base -> 'saiu_em' = to_jsonb(r.saiu_em), false) then 0 else 1 end
                       >= c.compre_ate_empurroes_max,
             'cobrado_vezes', m.cobrado_vezes, 'urgente', false, 'chega', false, 'vencido', true, 'saiu', true)
             order by m.descricao, m.id)
      into v_its
      from public.os_material m
     where m.service_order_id = r.os and m.compre_ate is not null and m.situacao = 'falta' and m.compra_prevista_em is null
       and m.compre_ate <= (r.saiu_em at time zone 'America/Sao_Paulo')::date;
    continue when v_its is null;
    v_out := v_out || jsonb_build_object('os', r.os, 'numero', r.numero, 'cliente', r.cliente, 'saiu_em', r.saiu_em,
                                         'itens', v_its);
  end loop;
  return v_out;
end;
$function$;

comment on function public._agenda_gestor_compra_saiu(date) is
  'Agenda de Produção (Fase 7a, correção 2 da revisão; D7-2, spec §3.2 "Compra" e §5.10): as OS da carteira que saíram da agenda pelo material sem a compra — sem compromisso de hoje em diante, a última retirada do plano (as canceladas juntas por último, fora a reserva) com o motivo material, e algum item com o "compre até" gravado em falta, sem compra combinada e vencido até a saída. [{os, numero, cliente, saiu_em, itens [{linha, item, quantidade, fornecedor, prazo, corridos, prazo_fonte, compre_ate, ate, primeiro_antes, chega_em (comprando hoje, o dia em que dá para começar), contado (o empurrão desta saída já contado: compre_ate_base.saiu_em), empurrada_vezes (com o desta saída), limite (compre_ate_empurroes_max), cobrado_vezes, saiu true}]}]. O passo compre_ate conta o empurrão e cobra; _agenda_compras_da_semana as mantém nas compras do fechamento. STABLE, invoker, sem grant.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "(7a correção 2") ─────────────────────

-- _agenda_classe_da_os (de 20261031100900_agenda_fase7a_sinal_sabado.sql)
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
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) quantas pessoas o meio-dia pede e quem a grade tem
  v_f72_n    int;
  v_f72_tec  text[];
  -- FASE 7: fim
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
  -- FASE 7: (7a P12, regra sinal_cobrar; AG7-09 "marco e cobro o sinal", spec §R1 e §5.12) o sinal combinado e não pago não
  -- trava: a OS segue para a classe que teria sem ele (o compromisso, se o resto estiver pronto) — nada de reserva por sinal,
  -- e condicao_tipo não ganha 'sinal' — e o gestor lembra o dono de cobrar quando ela ganha dia (_agenda_gestor_sinal). O que
  -- trava depois do sinal na mesma lista (o orçamento, o cliente, o escopo) continua travando. Sem a regra, a de antes.
  if v_trava ->> 'tipo' = 'sinal' and public._agenda_gestor_regra('sinal_cobrar') then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('orcamento', 'cliente', 'escopo') order by o limit 1;
  end if;
  -- FASE 7: fim
  if v_trava is not null then
    return jsonb_build_object('classe', 4, 'motivo', v_trava ->> 'tipo', 'texto', v_trava ->> 'texto');
  end if;
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa; AG7-04 e fase7-padroes: "o gestor SUGERE quando chamar (ex.: dupla
  -- necessária)") com a regra uma_pessoa, a OS que o dono disse que vai com dupla (um meio-dia que pede 2 pessoas em
  -- agenda_meios_da_os, sem a equipe dita) e a grade com menos técnicos do que isso espera o dono: classe 4, motivo dupla. Antes,
  -- com o Alex sozinho, o motor a tirava do plano calado ("sem lugar") e ela nunca voltava. A grade só é lida quando a OS pede 2.
  if public._agenda_gestor_regra('uma_pessoa') and not coalesce((p_meios ->> 'equipe_dita')::boolean, false) then
    v_f72_n := greatest(coalesce((p_meios #>> '{por_turno,manha,desejado}')::int, 0),
                        coalesce((p_meios #>> '{por_turno,tarde,desejado}')::int, 0));
    if v_f72_n >= 2 then
      v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_f72_tec) < v_f72_n then
        return jsonb_build_object('classe', 4, 'motivo', 'dupla',
          'texto', format('precisa de %s pessoas e %s: chame um ajudante e me diga os dias dele', v_f72_n,
                          public._agenda_tecnicos_frase(v_f72_tec)));
      end if;
    end if;
  end if;
  -- FASE 7: fim
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
  'Agenda de Produção (Fase 2, P2): a classe da OS para o motor, pelas restrições de os_prontidao e o molde de agenda_meios_da_os — 1 = em execução/parada ou com meio-dia fixado (compromisso, primeiro); 2 = pronta: dias ditos ou aceitos, sem orçamento/sinal/cliente/escopo travando e todo crítico em A, B ou C (compromisso); 3 = o que falta é só compra (D falta, o "compre até"), material comprado sem previsão ou compra combinada sem prazo, conferir o material (zero linhas ou peça embutida) ou dias só sugeridos (só reserva condicionada; condicao_tipo na ordem compra > material > conferir_material > duracao); 4 = nunca: fora da carteira, em espera, material atrasado ou sem previsão, orçamento, sinal, cliente, escopo, o bem ou o "não antes de" além do horizonte, sem base para os dias. {classe, motivo, texto (quem trava), condicao_tipo}. FASE 7 (7a P3), com as chaves de agenda_meios_da_os que só existem com a regra estimativa: a OS começada ou parada (situacao_pendente; também a em andamento sem plano nem dias) = classe 4 situacao; a estimativa que o gestor não usa sozinho (estimativa_motivo grande, embutida ou sem_base, com a fonte sugerida) = classe 4 estimativa, antes do "sem base" (que sem a regra continua duracao); com a regra compra_firme, a falta de nível D com compra_firme (os_prontidao) não entra na condição compra (a OS fica no compromisso). Sem o portão, a de antes. FASE 7 (7a P12; AG7-09 "marco e cobro o sinal"): com a regra sinal_cobrar, o sinal combinado e não pago sai da trava de antes do material e não entra em condição nenhuma (condicao_tipo não ganha sinal): a OS fica na classe que teria sem ele (o compromisso, se o resto estiver pronto); o orçamento, o cliente e o escopo continuam travando. O gestor lembra o dono de cobrar (_agenda_gestor_sinal). Sem a regra, a de antes. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a dupla sem a 2ª pessoa, AG7-04): com a regra uma_pessoa, a OS que pede 2 pessoas num meio-dia (a dupla dita, sem a equipe dita) e a grade (_agenda_tecnicos_da_grade) com menos técnicos do que isso é classe 4, motivo dupla ("precisa de 2 pessoas e só Alex está na equipe: chame um ajudante e me diga os dias dele"): espera o dono em vez de sair do plano calada. Sem a regra, a de antes, byte a byte.';

-- agenda_meios_da_os (de 20261031100100_agenda_fase7a_duracao.sql)
create or replace function public.agenda_meios_da_os(p_so_id uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  p          public.os_planejamento%rowtype;
  v_dono     uuid := public._agenda_dono(null);
  v_status   text;
  v_pres     jsonb;
  v_sug      jsonb;
  v_fonte    text;
  v_dias     numeric;
  v_total    int;
  v_plano    jsonb;
  v_cump     numeric := 0;
  v_vig      int := 0;
  v_rest     numeric;
  v_dita     boolean;
  v_dono_t   text;
  v_presenca text;
  v_motivo   text;
  v_dt_m     boolean;
  v_dt_t     boolean;
  v_pm       jsonb;
  v_pt       jsonb;
  v_dm       int;
  v_dtd      int;
  v_pessoas  int;
  v_abre     boolean;
  v_fecha    boolean;
  v_molde    jsonb := '[]'::jsonb;
  v_papel    text[];
  v_t        text;
  k          int;
  -- FASE 7: (7a P2) a estimativa do gestor e o que a saída ganha com a regra estimativa
  v_est      jsonb;
  v_f7       jsonb;
  -- FASE 7: fim
begin
  select so.status into v_status from public.service_orders so where so.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  select * into p from public.os_planejamento where service_order_id = p_so_id;
  v_pres := public.os_presenca_do_dono(p_so_id);
  v_sug := public.os_duracao_sugerida(p_so_id);

  -- Os dias: o que o dono disse (ou aceitou); sem isso, o realista da sugestão (só para reserva e simulação).
  if p.dias is not null then
    v_fonte := p.estimativa_fonte;
    v_dias := p.dias;
  else
    v_fonte := 'sugerida';
    v_dias := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null
                   else (v_sug ->> 'dias_realista')::numeric end;
  end if;
  -- FASE 7: (7a P2, regra estimativa, D7-1) sem os dias ditos, a estimativa do orçamento vale como dias firmes: fonte
  -- 'orcamento' com o realista de _agenda_gestor_estimativa (calculada na leitura; nada é gravado). Quando o gestor não usa
  -- a estimativa (começada ou parada, sem mão de obra, acima de estimativa_max_diarias, peça embutida), a fonte continua
  -- 'sugerida' e a saída diz o porquê (estimativa_motivo; situacao_pendente). Os dias de fonte 'orcamento' GRAVADOS (a
  -- pergunta com prazo que venceu) com o portão falso são lidos como 'sugerida': desligar volta ao de antes.
  if p.dias is null then
    if public._agenda_gestor_regra('estimativa') then
      v_est := public._agenda_gestor_estimativa(p_so_id, p_hoje);
      if coalesce((v_est ->> 'usa')::boolean, false) then
        v_fonte := 'orcamento';
        v_dias := (v_est ->> 'dias')::numeric;
      end if;
      v_f7 := jsonb_build_object(
        'estimativa_motivo', case when coalesce((v_est ->> 'usa')::boolean, false) then null else v_est ->> 'motivo' end,
        'situacao_pendente', coalesce(v_est ->> 'motivo' = 'situacao', false));
    end if;
  elsif p.estimativa_fonte = 'orcamento' and not public._agenda_gestor_regra('estimativa') then
    v_fonte := 'sugerida';
  end if;
  -- FASE 7: fim

  -- A equipe dita: o dono (se está nela) e os diaristas por turno ("dia" vale nos dois).
  v_dita := exists (select 1 from public.os_planejamento_equipe e where e.service_order_id = p_so_id);
  select e.turnos into v_dono_t
    from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
   where e.service_order_id = p_so_id and (e.payee_id = v_dono or py.kind = 'socio')
   order by e.payee_id is not distinct from v_dono desc, e.payee_id
   limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name))
                            order by e.turnos = 'dia' desc, py.name, e.payee_id)
                    filter (where e.turnos in ('dia', 'manha')), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name))
                            order by e.turnos = 'dia' desc, py.name, e.payee_id)
                    filter (where e.turnos in ('dia', 'tarde')), '[]'::jsonb)
    into v_pm, v_pt
    from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
   where e.service_order_id = p_so_id and e.payee_id is distinct from v_dono and py.kind <> 'socio';

  -- A presença do dono: o que ele disse → ele na equipe dita (o turno inteiro nos turnos dele) → a regra d05.
  if v_pres ->> 'fonte' = 'dono' then
    v_presenca := v_pres ->> 'presenca';
    v_motivo := 'você disse';
  elsif v_dono_t is not null then
    v_presenca := 'equipe';
    v_motivo := 'você está na equipe';
  else
    v_presenca := coalesce(v_pres ->> 'presenca', 'abre_e_fecha');
    v_motivo := v_pres ->> 'motivo';
  end if;
  v_dt_m := v_presenca = 'sempre' or (v_presenca = 'equipe' and v_dono_t in ('dia', 'manha'));
  v_dt_t := v_presenca = 'sempre' or (v_presenca = 'equipe' and v_dono_t in ('dia', 'tarde'));

  -- Quantos diaristas por turno: os ditos; sem equipe dita, as pessoas da sugestão (o dono, quando fica o turno
  -- inteiro, é uma delas).
  v_pessoas := coalesce((v_sug ->> 'pessoas')::int, 1);
  if v_dita then
    v_dm := jsonb_array_length(v_pm);
    v_dtd := jsonb_array_length(v_pt);
  else
    v_dm := greatest(v_pessoas - case when v_dt_m then 1 else 0 end, 0);
    v_dtd := greatest(v_pessoas - case when v_dt_t then 1 else 0 end, 0);
    -- FASE 7: (7a correção 2; AG7-02, AG7-04) com a regra uma_pessoa, a pessoa da estimativa é o técnico: o dono que fica o turno
    -- inteiro (a marina nova, o "sempre" que ele disse) vai junto e não é uma delas — a regra de antes ("o dono é uma das pessoas")
    -- era com 2 pessoas; com 1, o motor marcava só o dono, sem o técnico (a Kalmar OS-00033 o turno inteiro só com você, o Alex
    -- parado e o Lenine empurrado). O diagnóstico e o comissionamento continuam com ele: o trabalho é dele (AG7-10).
    if public._agenda_gestor_regra('uma_pessoa') and (v_dt_m or v_dt_t)
       and coalesce(case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                         else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                 from public.service_orders so where so.id = p_so_id) end, '') not in ('diagnóstico', 'comissionamento') then
      v_dm := v_pessoas;
      v_dtd := v_pessoas;
    end if;
    -- FASE 7: fim
  end if;

  -- O que já foi feito e o que já está marcado (d20).
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_cump := coalesce((v_plano ->> 'meios_cumpridos')::numeric, 0);
  v_vig := coalesce((v_plano ->> 'meios_vigentes')::int, 0);
  v_total := case when v_dias is null then null else (v_dias * 2)::int end;
  v_rest := case when v_total is null then null else greatest(v_total - v_cump - v_vig, 0) end;
  v_fecha := v_presenca = 'abre_e_fecha';
  v_abre := v_fecha and coalesce((v_plano ->> 'dias')::int, 0) = 0 and v_cump = 0 and v_status <> 'in_progress';

  -- O molde, como o dono disse e começando de manhã (o motor aplica o turno de verdade de cada meio-dia).
  for k in 1 .. coalesce(v_total, 0) loop
    v_t := case when k % 2 = 1 then 'manha' else 'tarde' end;
    v_papel := '{}';
    if (v_t = 'manha' and v_dt_m) or (v_t = 'tarde' and v_dt_t) then
      v_papel := array['turno'];
    else
      if k = 1 and v_fecha then v_papel := v_papel || 'abertura'::text; end if;
      if k = v_total and v_fecha then v_papel := v_papel || 'fechamento'::text; end if;
    end if;
    v_molde := v_molde || jsonb_build_object('k', k, 'turno', v_t,
      'pessoas_ditas', case when v_t = 'manha' then v_pm else v_pt end,
      'desejado', case when v_t = 'manha' then v_dm else v_dtd end,
      'dono', to_jsonb(v_papel));
  end loop;
  -- FASE 7: (7a P2) com a regra estimativa, a mesma saída de baixo mais estimativa_motivo e situacao_pendente; sem a regra, a
  -- saída de baixo, byte a byte.
  if v_f7 is not null then
    return jsonb_build_object(
      'ok', true, 'os', p_so_id, 'fonte', v_fonte, 'dias', trim_scale(v_dias), 'sem_base', v_dias is null,
      'total', v_total, 'cumpridos', trim_scale(v_cump), 'vigentes', v_vig, 'restantes', trim_scale(v_rest),
      'passos', case when v_rest is null then 0 else ceil(v_rest)::int end,
      'presenca', v_presenca, 'presenca_motivo', v_motivo, 'abre', v_abre, 'fecha', v_fecha,
      -- o motivo da regra d05 (o tipo do meio-dia: diagnóstico, comissionamento), mesmo quando o dono disse a presença
      'regra_motivo', case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                           else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                   from public.service_orders so where so.id = p_so_id) end,
      'dono_turno', jsonb_build_object('manha', v_dt_m, 'tarde', v_dt_t),
      'equipe_dita', v_dita, 'pessoas_sugeridas', case when v_dita then null else v_pessoas end,
      'por_turno', jsonb_build_object('manha', jsonb_build_object('pessoas', v_pm, 'desejado', v_dm),
                                      'tarde', jsonb_build_object('pessoas', v_pt, 'desejado', v_dtd)),
      'molde', v_molde) || v_f7;
  end if;
  -- FASE 7: fim

  return jsonb_build_object(
    'ok', true, 'os', p_so_id, 'fonte', v_fonte, 'dias', trim_scale(v_dias), 'sem_base', v_dias is null,
    'total', v_total, 'cumpridos', trim_scale(v_cump), 'vigentes', v_vig, 'restantes', trim_scale(v_rest),
    'passos', case when v_rest is null then 0 else ceil(v_rest)::int end,
    'presenca', v_presenca, 'presenca_motivo', v_motivo, 'abre', v_abre, 'fecha', v_fecha,
    -- o motivo da regra d05 (o tipo do meio-dia: diagnóstico, comissionamento), mesmo quando o dono disse a presença
    'regra_motivo', case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                         else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                 from public.service_orders so where so.id = p_so_id) end,
    'dono_turno', jsonb_build_object('manha', v_dt_m, 'tarde', v_dt_t),
    'equipe_dita', v_dita, 'pessoas_sugeridas', case when v_dita then null else v_pessoas end,
    'por_turno', jsonb_build_object('manha', jsonb_build_object('pessoas', v_pm, 'desejado', v_dm),
                                    'tarde', jsonb_build_object('pessoas', v_pt, 'desejado', v_dtd)),
    'molde', v_molde);
end;
$function$;

comment on function public.agenda_meios_da_os(uuid, date) is
  'Agenda de Produção (Fase 2, P2): o molde dos meios-dias do que o dono disse — total = dias × 2 (meio dia = 1); por turno os diaristas ditos ("dia" vale nos dois) e quantos (desejado; sem equipe dita, as pessoas da sugestão, e o dono que fica o turno inteiro é uma delas); a presença do dono: o que ele disse → ele na equipe dita (turno nos turnos dele) → a regra d05 (sempre = turno em todos; abre_e_fecha = abertura no 1º e fechamento no último); restantes = total − cumpridos (cumprido/sem registro/passado sem resultado = 1, parcial = 0,5) − os meios-dias vigentes de hoje em diante. Sem os dias ditos: fonte sugerida (dias_realista), só para reserva e simulação. {ok, fonte, dias, total, restantes, passos, presenca, abre, fecha, dono_turno, por_turno, molde[{k, turno, pessoas_ditas, desejado, dono}]}. FASE 7 (7a P2): sem os dias ditos e com a regra estimativa (_agenda_gestor_regra), a fonte é ''orcamento'' com os dias de _agenda_gestor_estimativa quando ela usa (D7-1: a estimativa do orçamento vale como dias firmes; nada é gravado), e a saída ganha estimativa_motivo (por que não usa: situacao, sem_base, grande, embutida; null quando usa) e situacao_pendente; os dias de fonte ''orcamento'' gravados com o portão falso são lidos como ''sugerida''. Sem a regra, a saída de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; AG7-02/AG7-04): com a regra uma_pessoa, o dono que fica o turno inteiro (presença sempre: a marina nova, o que ele disse) não é a pessoa da estimativa — os técnicos desejados por turno são as pessoas da sugestão, e ele vai junto; no diagnóstico e no comissionamento (dele), a de antes. Sem a regra, a de antes, byte a byte.';

-- agenda_dupla_dita (de 20261031100100_agenda_fase7a_duracao.sql)
create or replace function public.agenda_dupla_dita(p_autor uuid, p_alvo text, p_dupla boolean, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_autor  uuid;
  v_ro     jsonb;
  v_os     uuid;
  v_nome   text;
  v_old    public.os_planejamento%rowtype;
  v_novo   text;
  v_com    text;
  v_motivo text;
  v_antes  jsonb;
  v_depois jsonb;
  v_txt    text;
  v_acao   uuid;
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) quem a grade tem
  v_f72_tec text[];
  -- FASE 7: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_dupla_dita: sem o dia ou a hora' using errcode = '22004';
  end if;
  if p_dupla is null then
    raise exception 'agenda_dupla_dita: diga com ou sem dupla' using errcode = '22004';
  end if;
  v_autor := public._autor_da_agenda(p_autor);
  cf := public._agenda_cfg();
  v_ro := public.agenda_resolver_os(p_alvo, p_hoje);
  if coalesce(v_ro ->> 'status', '') <> 'ok' then
    return jsonb_build_object('ok', false, 'status', coalesce(v_ro ->> 'status', 'nao_achei'), 'texto', v_ro ->> 'texto',
                              'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  v_nome := v_ro ->> 'cliente_curto';
  v_novo := case when p_dupla then 'todos' else 'nao' end;
  v_com := case when p_dupla then 'com' else 'sem' end;

  insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
  select * into v_old from public.os_planejamento where service_order_id = v_os for update;
  if v_old.dupla_dita is not distinct from v_novo and v_old.dupla_meios is null then
    return jsonb_build_object('ok', true, 'mudou', false, 'os', v_os, 'dupla_dita', v_novo,
                              'texto', format('%s já estava %s dupla.', v_nome, v_com));
  end if;

  v_motivo := left(format('você disse: %s %s dupla', v_nome, v_com), 80);
  v_antes := jsonb_build_object('dupla_dita', v_old.dupla_dita, 'dupla_meios', v_old.dupla_meios,
                                'dupla_motivo', v_old.dupla_motivo, 'dupla_em', v_old.dupla_em);
  v_depois := jsonb_build_object('dupla_dita', v_novo, 'dupla_meios', null, 'dupla_motivo', v_motivo, 'dupla_em', p_agora);
  v_txt := case when p_dupla
                then format('%s com dupla: nas próximas vezes que eu marcar, vão %s pessoas em cada meio-dia. *desfaz %s* volta.',
                            v_nome, greatest(cf.equipe_sugerida, 2), v_nome)
                else format('%s sem dupla: volto a %s.', v_nome,
                            case when cf.equipe_padrao = 1 then '1 pessoa' else cf.equipe_padrao || ' pessoas' end) end;
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa; AG7-04 e fase7-padroes: o gestor sugere chamar alguém) com menos técnicos na
  -- grade do que a dupla pede, o texto não promete "vão 2 pessoas": diz quem está na equipe e o que fazer, e que o gestor não marca
  -- o serviço de novo sozinho até lá (a classe dupla de _agenda_classe_da_os)
  if p_dupla then
    v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
    if cardinality(v_f72_tec) < greatest(cf.equipe_sugerida, 2) then
      v_txt := format('%s com dupla: anotei, vão %s pessoas em cada meio-dia. Hoje %s: para ir dupla, chame um ajudante e me diga os dias dele. Até lá eu não marco %s de novo%s. *desfaz %s* volta.',
                      v_nome, greatest(cf.equipe_sugerida, 2), public._agenda_tecnicos_frase(v_f72_tec), v_nome,
                      case when exists (select 1 from public.agenda_alocacoes a
                                         where a.service_order_id = v_os and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')
                                           and a.dia >= p_hoje and a.resultado is null)
                           then '; o que já está marcado fica como está' else '' end, v_nome);
    end if;
  end if;
  -- FASE 7: fim

  update public.os_planejamento
     set dupla_dita = v_novo, dupla_meios = null, dupla_motivo = v_motivo, dupla_em = p_agora,
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_agora, 'autor', v_autor, 'por', 'dono', 'trecho', public._agenda_corta(format('%s %s dupla', p_alvo, v_com), 500),
           'antes', v_antes, 'depois', v_depois)),
         atualizado_em = p_agora, atualizado_por = v_autor
   where service_order_id = v_os;

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, autor, desfazivel_ate)
  values (p_agora, p_hoje, true, 'dono', 'dupla', v_os, array[v_os], v_antes, v_depois, left(public._agenda_corta(v_txt, 400), 400),
          v_motivo, v_autor, p_agora + cf.desfazer_validade)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'os', v_os, 'dupla_dita', v_novo, 'acao_id', v_acao, 'texto', v_txt);
end;
$function$;

comment on function public.agenda_dupla_dita(uuid, text, boolean, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P2; AG7-04): a palavra *<nome> com dupla* (dupla_dita = todos: greatest(equipe_sugerida, 2) pessoas em cada meio-dia nas próximas marcações) ou *<nome> sem dupla* (nao: equipe_padrao). O alvo pelo agenda_resolver_os (só a carteira; ambíguo, fora ou não achado = {ok: false, texto do resolvedor}); grava dupla_dita, dupla_meios nulo, dupla_motivo e dupla_em em os_planejamento (cria a linha se faltar), com o histórico, e a ação dupla (origem dono, desfazível por desfazer_validade). O que já estava = "já estava", sem gravar. O plano não muda na hora. Só o administrador; security definer; só service_role. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a dupla sem a 2ª pessoa): com menos técnicos na grade (_agenda_tecnicos_da_grade) do que a dupla pede, a resposta diz quem está e o que fazer ("Lenine com dupla: anotei, vão 2 pessoas em cada meio-dia. Hoje só Alex está na equipe: para ir dupla, chame um ajudante e me diga os dias dele. Até lá eu não marco Lenine de novo; o que já está marcado fica como está. *desfaz Lenine* volta."). Com a 2ª pessoa na grade, a de antes.';

-- _agenda_gestor_fichas (de 20261031100850_agenda_fase7a_protecoes.sql)
create or replace function public._agenda_gestor_fichas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_modo  text;
  v_desde date;
  v_d     date;
  v_ate   timestamptz;
  v_hora  text;
  v_quando text;
  v_dono  uuid := public._agenda_dono(null);
  p       record;
  v_os    uuid;
  v_partes text[];
  v_txt   text;
  v_id    uuid;
  v_novas int := 0;
  v_lista jsonb := '[]'::jsonb;
  v_ops   jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_fichas: sem o dia ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modo := coalesce(public._agenda_modo_da_pergunta('ficha_estimativa', null), 'desligado');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'as mensagens à equipe estão desligadas');
  end if;
  if cf.marcar_sozinho_desde is null then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor ainda não marca sozinho: sem janela da ficha');
  end if;
  if not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('pulado', true, 'motivo', 'não é dia útil');
  end if;
  v_desde := (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date;
  v_d := public.agenda_somar_du(p_hoje, 1);
  if v_d < v_desde or v_d >= v_desde + cf.ficha_veto_dias then
    return jsonb_build_object('pulado', true, 'motivo', 'fora da janela da ficha', 'dia', v_d);
  end if;
  v_ate := (p_hoje + cf.equipe_hora_ficha) at time zone 'America/Sao_Paulo';
  if p_agora >= v_ate then
    return jsonb_build_object('pulado', true, 'motivo', 'já passou a hora da ficha', 'dia', v_d);
  end if;
  v_hora := to_char(cf.equipe_hora_ficha, 'HH24:MI');
  v_quando := case when v_d = p_hoje + 1 then 'amanhã'
                   else (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from v_d)::int] end;
  v_ops := jsonb_build_array(
    jsonb_build_object('n', 1, 'texto', 'Mande', 'efeito', jsonb_build_object('mandar', true)),
    jsonb_build_object('n', 2, 'texto', 'Segure a ficha: eu não mando e você fala com ele', 'efeito', jsonb_build_object('segurar', true)));

  for p in
    select c.payee_id, public._agenda_nome_curto(py.name) as nome
      from public._agenda_contatos_com_plano(v_d) c(payee_id)
      join public.payees py on py.id = c.payee_id
     where c.payee_id is distinct from v_dono
       and exists (select 1 from public.agenda_alocacoes a
                    where a.payee_id = c.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.duracao_fonte = 'orcamento')
       -- FASE 7: (7a correção 2, a ficha prometida a quem não tem telefone) só quem tem para onde a ficha ir: sem telefone ela não sai
       -- de jeito nenhum, e a pergunta prometia "Hoje às 19:30 a ficha de amanhã vai para Alex" (e às 19:30 a fechava "ela foi como
       -- eu disse"). A ficha de quem não tem telefone fica segurada e diz o porquê (_agenda_rotina_ficha): o dono avisa de boca.
       and public._agenda_equipe_tem_telefone(c.payee_id)
       -- FASE 7: fim
       -- a ficha desse dia já foi decidida (registrada, ou de carona no "como foi hoje?"): não há o que perguntar
       and not exists (select 1 from public.agenda_equipe_mensagens m
                        where m.payee_id = c.payee_id and m.modo = 'ligado'
                          and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)))
     order by 2, 1
  loop
    -- o que a ficha diz desse dia pela estimativa: cada OS dele no dia, o turno e que dia é do plano dela
    select array_agg(format('%s, %s %s — dia %s de %s', o.cliente, public._dia_curto(v_d),
                            case when o.m and o.t then 'o dia todo' when o.m then 'de manhã' else 'à tarde' end, o.k, o.n)
                     order by o.ini, o.os),
           (array_agg(o.os order by o.ini, o.os))[1]
      into v_partes, v_os
      from (select a.service_order_id as os, min(lower(a.periodo)) as ini,
                   bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
                   coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno' and b.dia <= v_d) as k,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno') as n
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
             where a.payee_id = p.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.duracao_fonte = 'orcamento'
             group by a.service_order_id, cl.name, so.service_order_number) o;
    v_txt := format('Hoje às %s a ficha de %s vai para %s: %s, pela minha estimativa.', v_hora, v_quando, p.nome,
                    array_to_string(v_partes, '; '))
             || ' 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
    v_id := public._agenda_gestor_perguntar('ficha_estimativa', format('ficha_estimativa:%s:%s', p.payee_id, v_d), v_os, v_txt,
                                            v_ops, 1::smallint, v_ate, 1::smallint, v_modo, p_agora);
    if v_id is not null and exists (select 1 from public.agenda_perguntas q where q.id = v_id and q.criada_em = p_agora) then
      v_novas := v_novas + 1;
    end if;
    v_lista := v_lista || jsonb_build_object('pessoa', p.payee_id, 'nome', p.nome, 'pergunta_id', v_id, 'texto', v_txt);
  end loop;
  return jsonb_build_object('dia', v_d, 'prazo', v_ate, 'modo', v_modo, 'perguntas', jsonb_array_length(v_lista),
                            'novas', v_novas, 'pessoas', v_lista);
end;
$function$;

comment on function public._agenda_gestor_fichas(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P11; AG7-15, spec §5.11 e §6.3): o passo diário fichas da rodada do gestor — com o ligar do gestor (marcar_sozinho_desde) e o próximo dia útil dentro das ficha_veto_dias a partir dele, para cada pessoa da rotina (_agenda_contatos_com_plano, sem o dono) com alocação vigente nesse dia de duracao_fonte orcamento e sem a ficha do dia já decidida, a pergunta ficha_estimativa (chave ficha_estimativa:<pessoa>:<dia>; veto_ate = hoje às equipe_hora_ficha; opções 1 Mande / 2 Segure; recomendação e padrão 1): "Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele." (o dia que não é amanhã pelo nome: "a ficha de terça"). O modo é o de _agenda_modo_da_pergunta(''ficha_estimativa'') — o das mensagens à equipe; desligado, fora da janela, depois da hora da ficha ou fora de dia útil = {pulado}. {dia, prazo, modo, perguntas, novas, pessoas [{pessoa, nome, pergunta_id, texto}]}. Invoker, sem grant. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): só pergunta a ficha de quem tem para onde ela ir (_agenda_equipe_tem_telefone, a régua de _agenda_equipe_registrar): sem telefone, nenhuma pergunta — a ficha fica segurada às 19:30 e o aviso diz "não tem telefone no cadastro. Fale com Alex.".';

-- _agenda_rotina_ficha (de 20261031100850_agenda_fase7a_protecoes.sql)
create or replace function public._agenda_rotina_ficha(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date;
  v_p     uuid;
  v_f     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
  -- FASE 7: (7a P11) a ficha de um dia pela estimativa, na janela de veto
  v_f11_q   public.agenda_perguntas%rowtype;
  v_f11_m   uuid;
  v_f11_a   uuid;
  v_f11_os  uuid[];
  v_f11_cli text;
  v_f11_nom text;
  v_f72_fecha boolean := false;  -- (7a correção 2) a pergunta da ficha fecha depois do registro, com o que houve
  -- FASE 7: fim
begin
  if v_local::time < cf.equipe_hora_ficha or not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('fichas', 0);
  end if;
  v_d := public.agenda_somar_du(p_hoje, 1);
  for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo
                             and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)));
    v_f := public.agenda_equipe_ficha(v_p, v_d, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) nas primeiras ficha_veto_dias a partir do ligar do gestor, a ficha de
    -- um dia marcado pela estimativa (a alocação da pessoa no dia com duracao_fonte orcamento) só sai com a pergunta
    -- ficha_estimativa daquele dia mostrada ao dono e não segurada (_agenda_ficha_liberada). Senão ela fica registrada como
    -- recusada (veto): nada vai à fila nem conta no teto da pessoa. Se o dono não soube (não viu a pergunta a tempo, ou ela nem
    -- nasceu), o que mudou conta para ele (a ação equipe da vigia: o fechamento e o *o que mudou* do dia seguinte). A pergunta do
    -- dia fecha aqui: a hora da ficha chegou. Só com a mensagem de verdade (em teste nada sai de todo jeito).
    if v_modo = 'ligado' then
      v_f11_q := null;
      select q.* into v_f11_q from public.agenda_perguntas q
       where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
       order by q.criada_em desc, q.id desc limit 1;
      if not public._agenda_ficha_liberada(v_p, v_d, p_agora) then
        insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key,
                                                    criada_em)
        values (v_p, v_d, 'ficha', 'ligado', left(v_f ->> 'texto_ficha', 600), p_agora, 'recusada', 'veto',
                format('agenda-equipe:ficha:%s:%s', v_p, v_d), p_agora)
        returning id into v_f11_m;
        if v_f11_q.id is null or v_f11_q.opcao_escolhida is distinct from 2 then
          v_f11_os := array(select a.service_order_id from public.agenda_alocacoes a
                             where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.duracao_fonte = 'orcamento'
                             group by a.service_order_id order by min(lower(a.periodo)), a.service_order_id);
          v_f11_cli := public._agenda_lista(array(
                         select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                           from unnest(v_f11_os) with ordinality u(os, o)
                           join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                          order by u.o), null);
          v_f11_nom := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_p);
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
          values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_f11_os[1], v_f11_os, v_p,
                  jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                     -- (7a correção 2) quem não tem telefone não ganha a pergunta: o porquê é esse
                                     'por', case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p) then 'sem_telefone'
                                                 when v_f11_q.id is null then 'sem_pergunta' else 'nao_vista' end),
                  left(format('Não mandei a ficha de %s a %s (%s): o dia é pela minha estimativa e %s. Fale com %s.',
                              public._dia_curto(v_d), v_f11_nom, v_f11_cli,
                              -- (7a correção 2) sem telefone no cadastro: o gestor não pergunta a ficha (ela não sairia), e o
                              -- dono fica sabendo que tem de avisar de boca
                              case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p)
                                     then format('%s não tem telefone no cadastro', v_f11_nom)
                                   when v_f11_q.id is null then 'não consegui te perguntar antes'
                                   else 'você não viu a pergunta antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI') end,
                              v_f11_nom), 400))
          returning id into v_f11_a;
          update public.agenda_equipe_mensagens set acao_id = v_f11_a where id = v_f11_m;
        end if;
        update public.agenda_perguntas
           set estado = 'resolvida', resolvida_motivo = 'na hora da ficha você não tinha visto a pergunta: a ficha não saiu'
         where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        v_cont := v_cont || jsonb_build_object('recusada', coalesce((v_cont ->> 'recusada')::int, 0) + 1);
        continue;
      end if;
      -- (7a correção 2) a pergunta fecha logo abaixo, depois do registro: antes ela fechava aqui "ela foi como eu disse" e o
      -- registro recusava em seguida (sem telefone, teto, janela) — o dono lia que a ficha tinha ido
      v_f72_fecha := true;
    end if;
    -- FASE 7: fim
    v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', v_f ->> 'texto_ficha', p_agora);
    -- FASE 7: (7a correção 2, a ficha prometida a quem não tem telefone) a pergunta da ficha liberada fecha com o que aconteceu
    -- no registro: enfileirada = "ela foi como eu disse"; recusada (o teto, a janela, o telefone que sumiu) = o porquê
    if v_f72_fecha then
      update public.agenda_perguntas
         set estado = 'resolvida',
             resolvida_motivo = case when v_r ->> 'estado' = 'recusada'
                                     then format('na hora da ficha você não a segurou, mas ela não saiu (%s)',
                                                 case v_r ->> 'motivo' when 'sem_telefone' then 'sem telefone no cadastro'
                                                                       when 'teto' then 'o limite de mensagens do dia'
                                                                       when 'janela' then 'fora do horário de mandar'
                                                                       when 'parou' then 'a pessoa não recebe mais a rotina'
                                                                       else coalesce(v_r ->> 'motivo', 'recusada') end)
                                     else 'na hora da ficha você não a segurou: ela foi como eu disse' end
       where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
      v_f72_fecha := false;
    end if;
    -- FASE 7: fim
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('dia', v_d, 'por_estado', v_cont);
end;
$function$;

comment on function public._agenda_rotina_ficha(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a ficha da véspera (equipe_hora_ficha num dia útil) para o próximo dia útil — não vai a quem já recebeu a ficha desse dia nem a quem recebeu o "como foi hoje?" levando a ficha; o texto de agenda_equipe_ficha, pelo _agenda_equipe_registrar. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15): com a mensagem de verdade, a ficha que _agenda_ficha_liberada não solta (na janela de veto do ligar, um dia da pessoa marcado pela estimativa sem a pergunta ficha_estimativa mostrada, ou segurada com a 2) fica registrada como recusada (veto) — nada vai à fila nem conta no teto — e, se o dono não soube, a ação equipe da vigia conta no que mudou ("Não mandei a ficha de ter 03/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto."); a pergunta do dia fecha (resolvida). Fora disso, a de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): a ficha segurada de quem não tem telefone diz o porquê ("Não mandei a ficha de qui 05/11 a Alex (Lenine): o dia é pela minha estimativa e Alex não tem telefone no cadastro. Fale com Alex.", por = sem_telefone); e a pergunta da ficha que fechou "ela foi como eu disse" com a ficha recusada no registro ganha o motivo verdadeiro ("… mas ela não saiu (sem telefone no cadastro)").';

-- _agenda_gestor_desfeito (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_gestor_desfeito(p_os uuid, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  with u as (
    select max(d.criada_em) as em
      from public.agenda_acoes a
      join public.agenda_acoes d on d.id = a.desfeita_pela
     where (a.service_order_id = p_os or p_os = any (a.os_ids))
       and a.executada and a.origem in ('motor', 'vigia')
       and a.tipo in ('publicar', 'criar', 'mover', 'promover_reserva', 'reparar', 'reestimar', 'estimar')
       and d.origem not in ('motor', 'vigia') and d.criada_em <= p_agora
  )
  select coalesce(
           u.em is not null
           and not exists (select 1 from public.agenda_acoes a
                            where (a.service_order_id = p_os or p_os = any (a.os_ids)) and a.executada and a.desfeita_em is null
                              and a.tipo in ('publicar', 'criar', 'mover', 'promover_reserva', 'reparar', 'reestimar', 'estimar', 'fixar')
                              -- FASE 7: (7a correção 2, achado 17 de novo) a remarcação automática (a reserva da proposta de quinta da
                              -- vigia, o motor, o próprio gestor) não solta a trava: era ela que trazia de volta o que o dono desfez
                              -- (a reserva de qui 16:30 soltava, e a revisão de sex 16:53 remarcava firme). Só o dono, o cliente ou a
                              -- OS que mudou
                              and a.origem not in ('motor', 'vigia')
                              -- FASE 7: fim
                              and a.criada_em > u.em and a.criada_em <= p_agora)
           and not exists (select 1 from public.service_orders so
                            where so.id = p_os
                              and ((so.converted_to_os_at > u.em + interval '5 minutes' and so.converted_to_os_at <= p_agora)
                                   or (so.signed_at > u.em + interval '5 minutes' and so.signed_at <= p_agora)))
           and not exists (select 1 from public.ai_lifecycle_events e
                            where e.entity_id = p_os and e.event_type = 'status_change'
                              and e.new_value in ('open', 'approved', 'scheduled')
                              and e.created_at > u.em + interval '5 minutes' and e.created_at <= p_agora)
           and not exists (select 1 from public.os_planejamento pl
                            where pl.service_order_id = p_os and pl.atualizado_em > u.em + interval '5 minutes'
                              and pl.atualizado_em <= p_agora)
           and not exists (select 1 from public.os_material m
                            where m.service_order_id = p_os and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix')
                              and m.atualizado_em > u.em and m.atualizado_em <= p_agora),
           false)
    from u;
$function$;

comment on function public._agenda_gestor_desfeito(uuid, timestamptz) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 17): true quando a última marcação automática da OS (publicar, criar, mover, promover_reserva, reparar, reestimar ou estimar da vigia ou do motor) foi desfeita por quem não é o motor (o *desfaz* do dono) e nada de novo aconteceu nela depois — nenhuma ação de plano que ainda valha, nem a conversão, a assinatura, o status aberta/aprovada/agendada, o planejamento (fora dos 5 minutos do *desfaz*, que volta o status e o planejamento na hora) ou o material do dono, do fornecedor, da nota ou do Pix. A revisão diária e o encaixe na aprovação do gestor pulam essa OS: o *desfaz* do dono vale até a OS mudar. STABLE, invoker, sem grant (os passos do gestor a leem). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; achado 17 de novo): a ação de plano que solta a trava é só a do dono, do cliente ou de quem não é a vigia nem o motor — a remarcação automática (a reserva da proposta de quinta, a revisão) não solta: o *desfaz* do dono vale até a OS mudar.';

-- _agenda_ver_gestor (de 20261031100980_agenda_fase77a_correcao.sql)
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
  return jsonb_build_object('ok', true, 'texto', public._agenda_gestor_juntar(v_l, cf.texto_max + 1 + char_length(v_como), v_como),
                            'dados', jsonb_build_object('modo', v_ef, 'so_propor', cf.gestor_so_propor, 'conta_de', v_sdia,
                                                        'sombra', v_s, 'fora', v_fora));
end;
$function$;

comment on function public._agenda_ver_gestor(date) is
  'Agenda de Produção (Fase 7a, P7; spec §6.2): o foco gestor de agenda_ver — (1) o estado: "O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada." / "Eu marco sozinho desde ter 03/11 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz." / "Desde sex 06/11 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta." / desligado; (2) em teste, "Eu marcaria:" pela última conta do diário (agenda_gestor_dia.sombra), um por linha ("• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*."); ligado, "Marquei nos últimos 7 dias:" (as OS com compromisso vigente pela estimativa); (3) "Antes de marcar eu perguntaria:" (teste) ou "Perguntei antes de marcar:" com o prazo ("• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim."); (4) "Fora:" agrupado pelo porquê ("esperando o cliente: Kalmar (2) e Rodrigo; …"; ligado, pela última conta de verdade do motor em 8 dias); (5) "Compras da semana:" e (6) "Se aprovar:" pelo diário (agenda_gestor_dia.compras e .orcamentos, [{texto}], de até 3 dias; o P10 e o P12 gravam); (7) "Como eu conto:" com os parâmetros. {ok, texto (≤ texto_max), dados}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa; achado 3): o "Como eu conto" entra sempre, no fim (_agenda_gestor_juntar: o corte é no meio, nunca num título sem linha embaixo, como o "Se aprovar:" vazio); as compras da semana e o "Se aprovar" mostram até 3 cada (o resto: "(e mais 3 orçamentos)", "(e mais N em *agenda compras*)"). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): (a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, "Pode precisar de dupla (banco de baterias): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Lenine com dupla*."; (o desfaz) ligado, a OS de fora que o dono desfez vai no grupo "você desfez (me diga os dias para eu marcar de novo)", não em "sem lugar na agenda"; (o número) em "Perguntei antes de marcar", o número da OS junto quando o nome se repete ("Kalmar (OS-00032)").';

-- _agenda_gestor_motivo_texto (de 20261031100600_agenda_fase7a_rodada.sql)
create or replace function public._agenda_gestor_motivo_texto(p_motivo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_motivo = 'cliente' then 'esperando o cliente'
    when p_motivo = 'orcamento' then 'orçamento sem virar OS'
    when p_motivo = 'sinal' then 'esperando o sinal'
    when p_motivo in ('padrao_do_dono', 'so_com_voce', 'dono') then 'precisa de você em campo'
    when p_motivo in ('material', 'compra', 'compre_ate', 'sem_previsao', 'conferir_material', 'material_nao_conferido') then 'material'
    when p_motivo = 'escopo' then 'escopo em aberto'
    when p_motivo = 'bem' then 'esperando o barco ou o motorhome'
    when p_motivo in ('espera', 'nao_cabe') then 'esperando a sua decisão'
    when p_motivo in ('situacao', 'estimativa', 'duracao') then 'falta saber os dias'
    -- FASE 7: (7a correção 2) a dupla sem a 2ª pessoa e o *desfaz* do dono (os dois saíam "sem lugar na agenda")
    when p_motivo = 'dupla' then 'falta a 2ª pessoa'
    when p_motivo = 'desfeito' then 'você desfez (me diga os dias para eu marcar de novo)'
    -- FASE 7: fim
    when p_motivo in ('sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'depois', 'fixar_recusado') then 'sem lugar na agenda'
    else 'outro motivo'
  end;
$function$;

comment on function public._agenda_gestor_motivo_texto(text) is
  'Agenda de Produção (Fase 7a, P7): o porquê de uma OS de fora numa palavra só, para o dono — cliente "esperando o cliente", orcamento "orçamento sem virar OS", sinal "esperando o sinal", padrao_do_dono/so_com_voce/dono "precisa de você em campo", o material "material", escopo, bem, a decisão crítica, os dias que faltam saber, sem lugar; o resto "outro motivo". IMMUTABLE. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): dupla "falta a 2ª pessoa"; desfeito "você desfez (me diga os dias para eu marcar de novo)".';

-- _agenda_gestor_motivo_ordem (de 20261031100600_agenda_fase7a_rodada.sql)
create or replace function public._agenda_gestor_motivo_ordem(p_texto text)
 returns int
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(array_position(array['esperando o cliente', 'orçamento sem virar OS', 'esperando o sinal', 'precisa de você em campo',
                                       'material', 'escopo em aberto', 'esperando o barco ou o motorhome', 'esperando a sua decisão',
                                       -- (7a correção 2) os dois grupos novos, antes de "sem lugar na agenda"
                                       'falta saber os dias', 'falta a 2ª pessoa', 'você desfez (me diga os dias para eu marcar de novo)',
                                       'sem lugar na agenda', 'outro motivo'], p_texto), 99);
$function$;

comment on function public._agenda_gestor_motivo_ordem(text) is
  'Agenda de Produção (Fase 7a, P7): a ordem dos grupos de fora (a de _agenda_gestor_motivo_texto: do que mais segura para o que menos). IMMUTABLE. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): "falta a 2ª pessoa" e "você desfez (…)" depois de "falta saber os dias".';

-- _agenda_aviso_fora_texto (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_aviso_fora_texto(p_fora jsonb, p_sem uuid[])
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  with f as (
    select t.o, t.e ->> 'numero' as numero,
           coalesce(public._agenda_nome_curto(t.e ->> 'cliente_curto'), t.e ->> 'numero', 'uma OS') as curto,
           case
             when t.e ->> 'motivo' in ('material', 'atrasado', 'sem_previsao', 'comprado_sem_previsao', 'compra_sem_prazo',
                                       'compre_ate', 'material_nao_conferido', 'peca_embutida') then 'material'
             when t.e ->> 'motivo' = 'cliente' then 'esperando o cliente'
             when t.e ->> 'motivo' = 'bem' then 'esperando o barco ou o veículo'
             when t.e ->> 'motivo' = 'sinal' then 'esperando o sinal'
             when t.e ->> 'motivo' = 'orcamento' then 'orçamento que não virou OS'
             when t.e ->> 'motivo' = 'escopo' then 'falta fechar o que fazer'
             when t.e ->> 'motivo' = 'duracao' then 'falta saber quantos dias'
             -- (7a correção, achado 6) os motivos do gestor que pergunta antes de marcar
             when t.e ->> 'motivo' = 'situacao' then 'falta saber se já começou'
             when t.e ->> 'motivo' = 'estimativa' then 'falta saber quantos dias'
             when t.e ->> 'motivo' = 'so_com_voce' then 'só com você'
             when t.e ->> 'motivo' = 'padrao_do_dono' then 'falta saber os seus dias em campo'
             -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) o motivo do gestor que espera a 2ª pessoa (só com a regra uma_pessoa)
             when t.e ->> 'motivo' = 'dupla' then 'falta a 2ª pessoa'
             -- FASE 7: fim
             when t.e ->> 'motivo' in ('sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'nao_cabe') then 'sem lugar na equipe'
             when t.e ->> 'motivo' in ('depois', 'nao_antes') then 'só mais para a frente'
             when t.e ->> 'motivo' = 'espera' then 'esperando a sua decisão'
             when t.e ->> 'motivo' = 'parada' then 'parou?'
             when t.e ->> 'motivo' = 'congelada' then 'em espera'
             else 'outro motivo' end as rotulo
      from jsonb_array_elements(coalesce(p_fora, '[]'::jsonb)) with ordinality t(e, o)
     where coalesce(t.e ->> 'motivo', '') not in ('fora_da_carteira', 'nao_achei')
       and not coalesce(nullif(t.e ->> 'os', '')::uuid = any (coalesce(p_sem, '{}'::uuid[])), false)
  ),
  n as (
    select f.*, case when count(*) over (partition by public._agenda_normal(f.curto)) > 1 and f.numero is not null
                          and f.curto is distinct from f.numero
                     then f.curto || ' ' || f.numero else f.curto end as nome
      from f
  ),
  g as (
    select n.rotulo, min(n.o) as o, public._agenda_lista(array_agg(n.nome order by n.o), 4) as nomes from n group by n.rotulo
  )
  select case when (select count(*) from n) = 0 then null
              when (select count(*) from n) = 1
                then format('Ficou de fora: %s.', (select g.nomes || ' (' || g.rotulo || ')' from g))
              else format('Ficaram de fora %s: %s.', (select count(*) from n),
                          (select string_agg(g.nomes || ' (' || g.rotulo || ')', '; ' order by g.o) from g)) end;
$function$;

comment on function public._agenda_aviso_fora_texto(jsonb, uuid[]) is
  'Agenda de Produção (correção de 29/10, P4): a linha curta do que ficou de fora no aviso do gestor — "Ficaram de fora 10: Rodrigo OS-00096 (só com você); Vanderlei, Flávio, Nelson e Giancarlo (material); Kalmar OS-00032, Kalmar OS-00033 e Rodrigo OS-00076 (esperando o cliente); …" (o porquê numa palavra pelo motivo da proposta; o número quando o nome se repete; até 4 nomes por porquê). Sem as OS de p_sem nem as fora da carteira. Nada = null. CORREÇÃO DA 7a (revisão da etapa; achado 6): os motivos do gestor — situacao ("falta saber se já começou") e estimativa ("falta saber quantos dias") — não caem mais em "outro motivo". CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): o motivo dupla (a classe 4 da dupla sem a 2ª pessoa, só com a regra uma_pessoa) diz "falta a 2ª pessoa". Com o gestor desligado o motivo não nasce: a saída é a de antes.';

-- _agenda_gestor_perguntar (de 20261031100300_agenda_fase7a_perguntas.sql)
create or replace function public._agenda_gestor_perguntar(p_tipo text, p_chave text, p_os uuid, p_texto text, p_opcoes jsonb,
                                                           p_rec smallint, p_veto_ate timestamptz, p_opcao_padrao smallint,
                                                           p_modo text, p_agora timestamptz)
 returns uuid
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_chave text := left(p_chave, 200);
  v_ate   timestamptz;
  v_id    uuid;
begin
  if p_tipo is null or p_chave is null or nullif(btrim(coalesce(p_texto, '')), '') is null or p_agora is null then
    raise exception '_agenda_gestor_perguntar: faltam o tipo, a chave, o texto ou a hora' using errcode = '22004';
  end if;
  if p_modo is null or p_modo not in ('sombra', 'ligado') then
    return null;
  end if;
  select q.id into v_id from public.agenda_perguntas q where q.chave = v_chave and q.modo = p_modo and q.estado = 'aberta';
  if v_id is not null then
    return v_id;
  end if;
  if exists (select 1 from public.agenda_perguntas q
              where q.chave = v_chave and q.modo = p_modo
                and not (q.estado = 'vencida'
                         and (q.mostrada_vezes = 0 or (q.veto_ate is not null and q.mostrada_em >= q.veto_ate)
                              -- FASE 7: (7a correção 2, achado 20 de novo) a pergunta sem prazo (acima do teto de diárias, a cobrança
                              -- da compra) que venceu sem resposta volta: o gestor pergunta de novo, não esquece a OS (o Giancarlo e a
                              -- Kalmar ficavam sem data e sem pergunta para sempre)
                              or q.veto_ate is null
                              -- FASE 7: fim
                              ))) then
    return null;
  end if;
  cf := public._agenda_cfg();
  v_ate := coalesce(p_veto_ate, p_agora + interval '7 days');
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo,
                                       criada_em, expira_em, veto_ate, opcao_padrao)
  values (p_tipo, v_chave, p_os, case when p_os is null then '{}'::uuid[] else array[p_os] end,
          (v_ate at time zone 'America/Sao_Paulo')::date, left(public._agenda_corta(p_texto, 600), 600),
          coalesce(p_opcoes, '[]'::jsonb), p_rec, p_modo, p_agora,
          case when p_veto_ate is null then v_ate else p_veto_ate + cf.desfazer_validade end, p_veto_ate, p_opcao_padrao)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  if v_id is null then
    select q.id into v_id from public.agenda_perguntas q where q.chave = v_chave and q.modo = p_modo and q.estado = 'aberta';
  end if;
  return v_id;
end;
$function$;

comment on function public._agenda_gestor_perguntar(text, text, uuid, text, jsonb, smallint, timestamptz, smallint, text, timestamptz) is
  'Agenda de Produção (Fase 7a, P4): grava a pergunta do gestor em agenda_perguntas e devolve o id — uma aberta por chave e modo (devolve a aberta); a fechada não volta na mesma chave (null), salvo a vencida que o dono não viu antes do prazo; perda_em = o dia do prazo (sem prazo, o do expira_em), expira_em = p_veto_ate + desfazer_validade (sem prazo, 7 dias), veto_ate e opcao_padrao como vieram (prazo em pergunta crítica: o CHECK veto_nao_critica recusa). p_modo fora de sombra/ligado = null, nada gravado. Security definer, sem grant a ninguém (nem service_role). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; achado 20 de novo): a pergunta sem prazo que venceu sem resposta também volta na mesma chave (o gestor pergunta de novo a cada expira_em, 7 dias): acima do teto de diárias, a OS não fica sem data e sem pergunta para sempre.';

-- _agenda_gestor_perguntas_da_os (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_gestor_perguntas_da_os(p_os uuid, p_hoje date, p_agora timestamptz, p_seco boolean)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_seco  boolean := coalesce(p_seco, false);
  v_base  jsonb;
  v_modo  text;
  v_cl    jsonb;
  v_est   jsonb;
  v_sit   jsonb;
  v_sug   jsonb;
  v_mot   text;
  v_var   text;
  v_tipo  text;
  v_chave text;
  v_prop  numeric;
  v_dias  text;
  v_veto  timestamptz;
  v_ate   text;
  v_rot   text;
  v_lin   text;
  v_perg  text;
  v_feito text;
  v_ops   jsonb;
  v_rec   smallint := 1;
  v_txt   text;
  v_nova  boolean;
  v_id    uuid;
  -- (7a correção, achado 20) acima do teto de diárias: sem prazo e sem o que fazer sozinho
  v_semp  boolean := false;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_perguntas_da_os: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  v_base := jsonb_build_object('os', p_os, 'perguntou', false);
  if not v_seco then
    v_modo := public._agenda_gestor_modo('marcar');
    if v_modo = 'desligado' then
      return v_base || jsonb_build_object('por', 'desligado');
    end if;
  end if;
  v_cl := public._agenda_classe_agora(p_os, p_hoje) - 'pront';
  if coalesce((v_cl ->> 'classe')::int, 0) <> 4 or coalesce(v_cl ->> 'motivo', '') not in ('situacao', 'estimativa', 'material') then
    return v_base || jsonb_build_object('por', 'nada_a_perguntar', 'classe', v_cl -> 'classe', 'classe_motivo', v_cl -> 'motivo');
  end if;
  v_est := public._agenda_gestor_estimativa(p_os, p_hoje);
  v_mot := v_est ->> 'motivo';
  if coalesce(v_mot, '') not in ('situacao', 'grande', 'embutida', 'sem_base') then
    return v_base || jsonb_build_object('por', 'nada_a_perguntar', 'classe', v_cl -> 'classe', 'classe_motivo', v_cl -> 'motivo',
                                        'estimativa', v_mot);
  end if;

  cf := public._agenda_cfg();
  v_prop := (v_est ->> 'proposta_dias')::numeric;
  v_dias := public._agenda_dias(v_prop);
  v_veto := public._agenda_veto_ate(p_agora);
  v_ate := public._dia_curto((v_veto at time zone 'America/Sao_Paulo')::date) || ' às '
           || to_char(v_veto at time zone 'America/Sao_Paulo', 'HH24:MI');
  v_rot := public._agenda_rotulo_da_os(p_os);
  -- (7a correção, achado 20) a estimativa inteira passa de estimativa_max_diarias (Giancarlo 10 diárias, Kalmar 18,3): o gestor
  -- não tem o que fazer sozinho — nem "marco os dias inteiros", nem "1 dia para terminar" um serviço de 18 diárias. A pergunta
  -- sai sem prazo e sem opção padrão: o dono decide (a recomendação é "eu digo").
  v_semp := coalesce((v_est ->> 'dp')::numeric > cf.estimativa_max_diarias, false);
  if v_semp then
    v_veto := null;
  end if;

  if v_mot = 'situacao' then
    v_tipo := 'situacao';
    v_sit := v_est -> 'situacao';
    v_var := case when v_sit ->> 'tipo' = 'parada' then 'parada'
                  when coalesce((v_sit ->> 'rastro')::boolean, false) then 'rastro'
                  else 'comecada' end;
    if v_var = 'parada' then
      v_perg := format('%s está parado desde %s: ainda é para fazer o serviço inteiro? Se você não me disser nada até %s, conto o serviço inteiro (%s, estimativa minha).',
                       v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), v_ate, v_dias);
      v_feito := format('contei o serviço inteiro, %s (estimativa minha)', v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Sim, inteiro', 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo o que falta', 'efeito', jsonb_build_object('dizer', true)),
        jsonb_build_object('n', 3, 'texto', 'Não é mais para fazer', 'efeito', jsonb_build_object('nao_fazer', true)));
    elsif v_var = 'rastro' then
      v_perg := format('%s já começou em %s: quanto falta? Se você não me disser nada até %s, marco %s para terminar.',
                       v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), v_ate, v_dias);
      v_feito := format('contei %s para terminar (estimativa minha)', v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', upper(left(v_dias, 1)) || substr(v_dias, 2),
                           'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo quanto falta', 'efeito', jsonb_build_object('dizer', true)),
        jsonb_build_object('n', 3, 'texto', 'Já terminou', 'efeito', jsonb_build_object('terminou', true)));
    else
      v_perg := format('%s está como ''%s'': o serviço já começou? Se você não me disser nada até %s, conto o serviço inteiro (%s, estimativa minha).',
                       v_rot, public._agenda_status_texto(v_sit ->> 'status'), v_ate, v_dias);
      v_feito := format('contei o serviço inteiro, %s (estimativa minha)', v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Não começou: conte tudo', 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Já começou: eu digo quanto falta', 'efeito', jsonb_build_object('dizer', true)),
        jsonb_build_object('n', 3, 'texto', 'Já terminou', 'efeito', jsonb_build_object('terminou', true)));
    end if;
  else
    v_tipo := 'estimativa';
    v_var := v_mot;
    v_feito := format('contei %s (estimativa minha)', v_dias);
    if v_mot = 'grande' then
      v_sug := public.os_duracao_sugerida(p_os);
      v_perg := format('%s: pelo valor do orçamento são %s diárias (%s com %s). É mais de %s diárias, então pergunto antes. Se você não me disser nada até %s, marco assim.',
                       v_rot, public._agenda_num((v_sug ->> 'diarias_realista')::numeric), v_dias,
                       case when coalesce((v_est ->> 'pessoas')::int, 1) = 1 then '1 pessoa' else (v_est ->> 'pessoas') || ' pessoas' end,
                       public._agenda_num(cf.estimativa_max_diarias), v_ate);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Marque ' || v_dias, 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo os dias', 'efeito', jsonb_build_object('dizer', true)));
    elsif v_mot = 'embutida' then
      -- o nome do serviço da linha (antes do " — ", " – ", ":" ou "("), como o dono escreveu
      v_lin := public._agenda_corta(btrim(regexp_replace(coalesce(v_est #>> '{embutida,0,nome}', ''), '( — | – |:|\().*$', '')), 60);
      v_perg := format('%s: ''%s'' pode ter peça junto. Contei tudo como mão de obra: %s. Se você não me disser nada até %s, marco assim.',
                       v_rot, v_lin, v_dias, v_ate);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Marque ' || v_dias, 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo os dias e a peça', 'efeito', jsonb_build_object('dizer', true)));
    else
      v_perg := format('%s: o orçamento não tem mão de obra separada, então não sei quantos dias leva. Se você não me disser nada até %s, marco %s.',
                       v_rot, v_ate, v_dias);
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', 'Marque ' || v_dias, 'efeito', jsonb_build_object('dias', trim_scale(v_prop), 'feito', v_feito)),
        jsonb_build_object('n', 2, 'texto', 'Eu digo os dias', 'efeito', jsonb_build_object('dizer', true)));
      v_rec := 2;
    end if;
  end if;
  -- (7a correção, achado 20) acima do teto: os textos sem o prazo, e a recomendação passa à 2 (o dono diz)
  if v_semp then
    v_rec := 2;
    -- FASE 7: (7a correção 2, achado 20 de novo) o serviço grande que já terminou (o Giancarlo, entregue — AG7-11): a opção existe
    if v_tipo = 'estimativa' then
      v_ops := v_ops || jsonb_build_array(jsonb_build_object('n', 3, 'texto', 'Já terminou (ou já entreguei)',
                                                             'efeito', jsonb_build_object('terminou', true)));
    end if;
    -- FASE 7: fim
    v_perg := case
      when v_tipo = 'estimativa' then
        format('%s: pelo valor do orçamento são %s diárias (%s com %s). É mais de %s diárias: não marco sozinho. Me diga os dias.',
               v_rot, public._agenda_num((public.os_duracao_sugerida(p_os) ->> 'diarias_realista')::numeric), v_dias,
               case when coalesce((v_est ->> 'pessoas')::int, 1) = 1 then '1 pessoa' else (v_est ->> 'pessoas') || ' pessoas' end,
               public._agenda_num(cf.estimativa_max_diarias))
      when v_var = 'parada' then
        format('%s está parado desde %s: ainda é para fazer o serviço inteiro? Pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você.',
               v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), public._agenda_num((v_est ->> 'dp')::numeric),
               public._agenda_num(cf.estimativa_max_diarias))
      when v_var = 'rastro' then
        format('%s já começou em %s: quanto falta? Pelo orçamento o serviço inteiro dá %s diárias, mais de %s: não marco sozinho, espero você dizer quanto falta.',
               v_rot, to_char((v_sit ->> 'desde')::date, 'DD/MM'), public._agenda_num((v_est ->> 'dp')::numeric),
               public._agenda_num(cf.estimativa_max_diarias))
      else
        format('%s está como ''%s'': o serviço já começou? Pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você.',
               v_rot, public._agenda_status_texto(v_sit ->> 'status'), public._agenda_num((v_est ->> 'dp')::numeric),
               public._agenda_num(cf.estimativa_max_diarias)) end;
  end if;
  v_chave := v_tipo || ':' || p_os || ':' || v_var;
  select v_perg || ' '
         || string_agg(format('%s) %s%s', o ->> 'n', o ->> 'texto', case when (o ->> 'n')::int = v_rec then ' (recomendo)' else '' end),
                       '; ' order by (o ->> 'n')::int) || '.'
    into v_txt
    from jsonb_array_elements(v_ops) o;
  v_base := v_base || jsonb_build_object('tipo', v_tipo, 'chave', v_chave, 'motivo', v_mot, 'variante', v_var, 'texto', v_txt,
                                         'curto', v_est ->> 'texto', 'proposta_dias', trim_scale(v_prop), 'opcoes', v_ops,
                                         'recomendacao', v_rec, 'opcao_padrao', case when v_semp then null else 1 end,
                                         'veto_ate', v_veto);
  if v_seco then
    return v_base;
  end if;

  -- o motivo mudou: a pergunta de antes da mesma OS (outra chave) sai e a nova entra
  update public.agenda_perguntas q
     set estado = 'resolvida', resolvida_motivo = 'mudou o que falta saber: perguntei de novo'
   where q.estado = 'aberta' and q.modo = v_modo and q.service_order_id = p_os and q.tipo in ('situacao', 'estimativa')
     and q.chave <> v_chave;
  v_nova := not exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo and q.estado = 'aberta');
  -- (7a correção, achado 20) acima do teto, sem prazo e sem opção padrão: o dono decide
  v_id := public._agenda_gestor_perguntar(v_tipo, v_chave, p_os, v_txt, v_ops, v_rec, v_veto,
                                          case when v_semp then null else 1 end::smallint, v_modo, p_agora);
  if v_id is null then
    return v_base || jsonb_build_object('por', 'ja_perguntei', 'modo', v_modo);
  end if;
  return v_base || jsonb_build_object('perguntou', true, 'pergunta_id', v_id, 'nova', v_nova, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_gestor_perguntas_da_os(uuid, date, timestamptz, boolean) is
  'Agenda de Produção (Fase 7a, P4; AG7-11, AG7-15): a pergunta do gestor antes de marcar uma OS — só com a classe 4 (_agenda_classe_agora) de motivo situacao, estimativa ou material, e o motivo da _agenda_gestor_estimativa em situacao (começou sem rastro, com rastro, parada), grande, embutida ou sem_base. Os textos da spec §6.3 (o que o gestor faz sem resposta e até quando: _agenda_veto_ate), as opções [{n, texto, efeito: {dias, feito} | {dizer} | {terminou} | {nao_fazer}}], a recomendação (1; no sem_base, 2) e a opção que vale sem resposta (1). Chave <tipo>:<os>:<variante>. p_seco = só devolve {os, perguntou false, tipo, chave, motivo, variante, texto, curto, proposta_dias, opcoes, recomendacao, opcao_padrao, veto_ate}; senão grava pelo modo do gestor que marca (_agenda_gestor_perguntar; desligado = nada) e resolve a aberta da mesma OS de outro motivo. {perguntou, pergunta_id, nova, modo} ou {perguntou false, por: desligado | nada_a_perguntar | ja_perguntei}. Invoker, sem grant (os passos do gestor e a limpeza da vigia a chamam). CORREÇÃO DA 7a (revisão da etapa; achado 20): quando a estimativa inteira da OS passa de estimativa_max_diarias (Giancarlo 10 diárias, Kalmar 18,3), o gestor não tem o que fazer sozinho: a pergunta sai sem prazo (veto_ate nulo) e sem opção padrão, com a recomendação "eu digo" (2) e o texto "… mais de 8 diárias: não marco sozinho" — no grande, no já começou com rastro (o "1 dia para terminar" de um serviço de 18 diárias), no começou sem rastro e no parado. Abaixo do teto, a de antes. A embutida não pergunta mais (achado 21). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; achado 20 de novo): acima do teto, a pergunta do serviço grande ganha a 3ª opção "Já terminou (ou já entreguei)" (efeito terminou: "Use *concluiu Giancarlo*.") — o Giancarlo foi entregue (AG7-11) e a pergunta só oferecia os dias.';

-- _agenda_linhas_do_fechamento (de 20261031100980_agenda_fase77a_correcao.sql)
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha.';

-- agenda_aviso_pecas (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public.agenda_aviso_pecas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_m     jsonb;
  v_n     int;
  v_jan   text;
  v_props uuid[];
  v_oss   uuid[];
  v_fora  jsonb;
  v_apr   jsonb;
  v_numos text[];
  v_voce  boolean;
  v_perg  jsonb;
  v_perr  text;
  -- FASE 7: (7a correção 2) o prazo das perguntas do gestor que o aviso conta como vistas
  v_f72_ate timestamptz;
  -- FASE 7: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aviso_pecas: sem o dia ou a hora' using errcode = '22023';
  end if;
  if not public._agenda_aviso_ligado() then
    return jsonb_build_object('avisar', false,
      'motivo', case when cf.modo_proposta = 'ligado' and cf.modo_vigia = 'ligado' then 'desligado' else 'modo' end);
  end if;
  v_m := public._agenda_aviso_mudancas(p_hoje);
  -- FASE 7: (7a correção 2, a OS em duas linhas) o estimar do gestor (os dias que o prazo gravou) e a marcação da mesma OS no mesmo
  -- aviso: a linha do estimar não repete o "*desfaz <nome>* volta." — o dono lia o mesmo serviço com dois *desfaz* (Vanderlei,
  -- Nelson e MP no aviso das 18:15). Sem o estimar, nada muda.
  v_m := coalesce((select jsonb_agg(case
             when (select bool_and(a.tipo = 'estimar') from public.agenda_acoes a
                    where a.id in (select y::uuid from jsonb_array_elements_text(e -> 'acao_ids') y))
                  and exists (select 1 from jsonb_array_elements(v_m) with ordinality t2(e2, o2), public.agenda_acoes a2
                               where o2 <> o and a2.id in (select y::uuid from jsonb_array_elements_text(e2 -> 'acao_ids') y)
                                 and a2.tipo in ('publicar', 'criar', 'mover', 'promover_reserva')
                                 and (e2 -> 'os') ?| array(select jsonb_array_elements_text(e -> 'os')))
             then jsonb_set(e, '{texto}', to_jsonb(regexp_replace(e ->> 'texto', '\s*\*desfaz [^*]+\* volta( como estava)?\.\s*$', '')))
             else e end order by o)
            from jsonb_array_elements(v_m) with ordinality t(e, o)), v_m);
  -- FASE 7: fim
  v_n := jsonb_array_length(v_m);
  if v_n = 0 then
    return jsonb_build_object('avisar', false, 'motivo', 'nada_mudou');
  end if;
  v_jan := public._agenda_aviso_fora_da_janela(p_agora, p_agora);
  if v_jan is not null then
    return jsonb_build_object('avisar', false, 'motivo', 'fora_da_janela', 'janela', v_jan, 'pendentes', v_n);
  end if;
  -- CORREÇÃO 29/10 (revisão): o aviso não corre com o fechamento das 17:30. O fechamento lê a agenda no começo e só
  -- registra o que mostrou depois de enfileirar; o aviso do mesmo minuto contava as mesmas mudanças no meio (duas mensagens
  -- com a mesma mudança). De segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, o aviso espera: o que
  -- estiver por contar vai no fechamento, e o resto sai no 1º aviso depois da pausa.
  if public._agenda_aviso_espera_o_fechamento(p_agora) then
    return jsonb_build_object('avisar', false, 'motivo', 'fechamento', 'pendentes', v_n);
  end if;
  -- CORREÇÃO 29/10 (revisão): fim
  if public._agenda_aviso_no_dia((p_agora at time zone 'America/Sao_Paulo')::date, null) >= cf.gestor_aviso_dia_max then
    return jsonb_build_object('avisar', false, 'motivo', 'teto', 'pendentes', v_n);
  end if;
  if not exists (select 1 from public._agenda_aviso_dono()) then
    return jsonb_build_object('avisar', false, 'motivo', 'sem_dono', 'pendentes', v_n);
  end if;

  -- o que ficou de fora: o fora das propostas das mudanças (a de cada OS pela proposta mais nova), sem as OS que mudaram
  v_props := array(select distinct x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'propostas') x);
  v_oss := array(select distinct x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'os') x);
  select coalesce(jsonb_agg(y.f order by y.ord, y.o), '[]'::jsonb) into v_fora
    from (select distinct on (coalesce(t.f ->> 'os', t.f ->> 'numero')) t.f, t.o, t.ord
            from (select f, o, dense_rank() over (order by p.criada_em desc, p.id) as ord
                    from public.agenda_propostas p
                    cross join lateral jsonb_array_elements(p.fora) with ordinality u(f, o)
                   where p.id = any (v_props)) t
           order by coalesce(t.f ->> 'os', t.f ->> 'numero'), t.ord, t.o) y;

  -- as perguntas que destravam: a rodada de aprontar, uma vez por dia. Se ela falhar, o que mudou sai do mesmo jeito e o erro
  -- volta em perguntas_erro (o passo do motor o registra em app_error_logs: nunca calado)
  if not exists (select 1 from public.agenda_dono_avisos v
                  where v.dia = p_hoje and v.com_perguntas and v.fila_id is not null and v.devolvida_em is null) then
    begin
      v_apr := public.agenda_aprontar(p_hoje);
    exception when others then
      v_perr := left(sqlstate || ': ' || sqlerrm, 300);
      v_apr := null;
    end;
    v_numos := array(select jsonb_array_elements_text(coalesce(v_apr #> '{dados,oss}', '[]'::jsonb)));
    v_voce := coalesce((v_apr #>> '{dados,voce}')::boolean, false);
    if coalesce((v_apr ->> 'ok')::boolean, false) and (cardinality(v_numos) > 0 or v_voce) then
      v_perg := jsonb_build_object(
        'texto', v_apr ->> 'texto', 'oss', to_jsonb(v_numos), 'voce', v_voce,
        'pergunta_ids', to_jsonb(array(
          select q.id from public.agenda_perguntas q
            left join public.service_orders so on so.id = q.service_order_id
           where q.estado = 'aberta' and q.modo = 'ligado'
             and ((q.tipo in ('material_conferir', 'duracao', 'chegou') and so.service_order_number = any (v_numos))
                  -- FASE 7: (7a correção, achado 15) as perguntas do gestor das OS que o texto cobre (a restrição da OS diz o que
                  -- ele faz sem resposta: "Perguntei se já começou; sem resposta, conto 4 dias"): o aviso que sai as conta como mostradas
                  or (q.tipo in ('situacao', 'estimativa') and so.service_order_number = any (v_numos))
                  -- FASE 7: fim
                  or (q.tipo = 'padrao_do_dono' and v_voce))
           order by q.criada_em, q.id)));
    end if;
    -- CORREÇÃO 29/10 (revisão): a pergunta sai uma vez por dia, no aviso ou no fechamento. Se alguma das perguntas que
    -- este texto cobre já foi mostrada hoje (no fechamento, numa conversa ou no acorde), as perguntas ficam para o 1º aviso de
    -- amanhã.
    if v_perg is not null
       and exists (select 1 from public.agenda_perguntas q
                    where q.id in (select x::uuid from jsonb_array_elements_text(v_perg -> 'pergunta_ids') x)
                      and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje) then
      v_perg := null;
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
  end if;

  -- FASE 7: (7a correção 2, as perguntas vistas sem o prazo) as perguntas do gestor que este aviso conta como mostradas (situacao,
  -- estimativa) têm prazo: o texto diz até quando — antes o aviso das 17:00 as contava como vistas sem a data, e o dono só lia o
  -- "até qua 04/11 18:00" no fechamento do próprio dia do prazo (AG7-15: pergunta com proposta E prazo)
  if v_perg is not null then
    select min(q.veto_ate) into v_f72_ate from public.agenda_perguntas q
     where q.id in (select x::uuid from jsonb_array_elements_text(v_perg -> 'pergunta_ids') x)
       and q.tipo in ('situacao', 'estimativa') and q.veto_ate is not null and q.opcao_escolhida is null;
    if v_f72_ate is not null then
      v_perg := jsonb_set(v_perg, '{texto}', to_jsonb(rtrim(v_perg ->> 'texto') || format(' Sem resposta até %s às %s, faço o que eu disse.',
                  public._dia_curto((v_f72_ate at time zone 'America/Sao_Paulo')::date),
                  to_char(v_f72_ate at time zone 'America/Sao_Paulo', 'HH24:MI'))));
    end if;
  end if;
  -- FASE 7: fim
  return jsonb_build_object(
    'avisar', true, 'rodada', p_agora, 'dia', p_hoje, 'limite', cf.gestor_aviso_texto_max,
    'cabecalho', 'Agenda — o que eu mudei sozinho:',
    'mudancas', (select jsonb_agg(jsonb_build_object('texto', g ->> 'texto', 'acao_ids', g -> 'acao_ids') order by o)
                   from jsonb_array_elements(v_m) with ordinality t(g, o)),
    'fora', public._agenda_aviso_fora_texto(v_fora, v_oss),
    'rodape', '*agenda plano* mostra tudo.',
    'perguntas', v_perg, 'perguntas_erro', v_perr);
end;
$function$;

comment on function public.agenda_aviso_pecas(date, timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): as peças do aviso do gestor ao dono, sem gravar nada (o texto é montado em _shared/agenda/aviso-do-gestor.ts). Não avisa (avisar false + motivo): modo, desligado (gestor_aviso_dia_max 0), nada_mudou, fora_da_janela (+ pendentes: sai junto na abertura), teto (+ pendentes), sem_dono. Avisa: {rodada, dia, limite (gestor_aviso_texto_max), cabecalho, mudancas [{texto do *o que mudou*, acao_ids}] (_agenda_aviso_mudancas), fora (_agenda_aviso_fora_texto, pelas propostas das mudanças), rodape, perguntas {texto de agenda_aprontar, pergunta_ids que ele cobre, oss, voce} — uma vez por dia — ou null, perguntas_erro (a rodada de aprontar falhou: o que mudou sai do mesmo jeito; o passo do motor registra o erro)}. STABLE, definer, só o service_role. CORREÇÃO 29/10 (revisão): (1) de segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, não avisa (motivo fechamento, + pendentes): o fechamento das 17:30 conta o que estiver por contar, e o resto sai no 1º aviso depois; (2) as perguntas saem uma vez por dia: se alguma das que o texto cobre já foi mostrada hoje (fechamento, conversa, acorde), ficam para amanhã. CORREÇÃO DA 7a (revisão da etapa; achado 15): as perguntas que o texto da rodada de aprontar cobre incluem as do gestor (situacao e estimativa) das OS que ele lista — a restrição da OS diz o que o gestor faz sem resposta; com o aviso enviado, elas contam como mostradas e o prazo delas vale. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): (a OS em duas linhas) a linha do estimar do gestor não repete o "*desfaz <nome>* volta." quando a mesma OS tem marcação no mesmo aviso; (as perguntas vistas sem o prazo) com perguntas do gestor de prazo entre as que o aviso conta como mostradas, o texto das perguntas termina "Sem resposta até qua 04/11 às 18:00, faço o que eu disse.". Sem o gestor, a de antes.';

-- _agenda_os_situacao (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_os_situacao(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  so       record;
  v_tipo   text;
  v_rastro boolean;
  v_desde  date;
  v_diaria date;
  v_ult    timestamptz;
  v_prop   numeric;
  v_sug    jsonb;
  v_est    numeric;
  v_pid    uuid;
  v_txt    text;
  v_curto  text;
  v_nada   constant jsonb := jsonb_build_object('pendente', false);
  -- (7a correção, achado 20) a estimativa inteira passa do teto de diárias: o gestor não tem o que fazer sozinho
  v_semp   boolean := false;
begin
  if p_hoje is null then
    raise exception '_agenda_os_situacao: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_os is null or not public._agenda_gestor_regra('situacao') then
    return v_nada;
  end if;
  select o.id, o.status, o.check_in_at, o.converted_to_os_at, o.signed_at, o.updated_at
    into so from public.service_orders o where o.id = p_os;
  if not found then
    return v_nada;
  end if;
  if exists (select 1 from public.os_planejamento pl where pl.service_order_id = p_os and pl.dias is not null)
     or exists (select 1 from public.agenda_alocacoes a
                 where a.service_order_id = p_os and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')) then
    return v_nada;
  end if;
  cf := public._agenda_cfg();

  select min(v.primeiro_dia) into v_diaria
    from public.v_dias_por_os_e_pessoa v
   where v.service_order_id = p_os and v.dias > 0 and v.primeiro_dia <= p_hoje;
  v_rastro := so.check_in_at is not null or so.status = 'in_progress' or v_diaria is not null;
  -- (7a correção, achados 2, 11 e 22) a OS que a própria agenda pôs em aguardando peças ao tirá-la do plano pelo material
  -- (agenda_aplicar: sem dia, com o cancelamento pelo material) não é "começada": sem check-in nem diária ligada e com a última
  -- retirada do plano (as alocações canceladas juntas por último, fora a reserva) feita pelo material — alguma delas com o motivo
  -- material: a remarcação cancela as violadas pelo material e as outras como replanejadas, no mesmo instante —, ela não pende:
  -- volta à reserva pelo material, com o "de quem e quando?" (spec §3.2, Compra). O "aguardando peças" posto pelo dono (Nelson,
  -- Flávio: NOVO-agenda-50) continua perguntando.
  if so.status = 'awaiting_parts' and not v_rastro
     and exists (select 1 from public.agenda_alocacoes a
                  where a.service_order_id = p_os and a.tipo <> 'reserva' and a.estado = 'cancelada' and a.cancelada_motivo = 'material'
                    and a.cancelada_em = (select max(b.cancelada_em) from public.agenda_alocacoes b
                                           where b.service_order_id = p_os and b.tipo <> 'reserva' and b.estado = 'cancelada')) then
    return v_nada;
  end if;

  if so.check_in_at is not null or so.status in ('in_progress', 'awaiting_parts') then
    v_tipo := 'comecada';
    -- desde quando: o check-in ou a 1ª diária ligada; sem eles, o dia em que a OS entrou no status de agora (senão a
    -- última atualização)
    v_desde := least((so.check_in_at at time zone 'America/Sao_Paulo')::date, v_diaria);
    if v_desde is null then
      select (max(e.created_at) at time zone 'America/Sao_Paulo')::date into v_desde
        from public.ai_lifecycle_events e
       where e.entity_id = p_os and e.event_type = 'status_change' and e.new_value = so.status;
      v_desde := coalesce(v_desde, (so.updated_at at time zone 'America/Sao_Paulo')::date);
    end if;
  elsif so.status in ('open', 'approved', 'scheduled') then
    v_ult := greatest(so.converted_to_os_at, so.signed_at, so.updated_at,
                      (select max(e.created_at) from public.ai_lifecycle_events e where e.entity_id = p_os),
                      -- (7a correção, achado 10) a última mexida da agenda na OS pelas alocações (criar, mover, cancelar, promover,
                      -- soltar), não pelas ações: a conta da prontidão não lê agenda_acoes, e a memória da vigia volta à marca de sempre
                      (select max(greatest(a.criado_em, a.cancelada_em)) from public.agenda_alocacoes a where a.service_order_id = p_os));
    -- FASE 7: (7a correção 2) o planejamento que o dono mexeu (os dias, a dupla, a presença: atualizado_por preenchido) também é
    -- mexida — o comentário da correção 1 já dizia "pelas alocações e pelo planejamento", e o código só lia as alocações: o
    -- *Lenine com dupla* numa OS parada não reiniciava a conta e ela ganhava o "ainda é para fazer o serviço inteiro?"
    v_ult := greatest(v_ult, (select pl.atualizado_em from public.os_planejamento pl
                               where pl.service_order_id = p_os and pl.atualizado_por is not null));
    -- FASE 7: fim
    if v_ult is null or (v_ult at time zone 'America/Sao_Paulo')::date >= p_hoje - cf.situacao_dias then
      return v_nada;
    end if;
    v_tipo := 'parada';
    v_desde := (v_ult at time zone 'America/Sao_Paulo')::date;
  else
    return v_nada;
  end if;

  -- a estimativa inteira (com as regras da duração); o "quanto falta" nunca passa dela
  v_sug := public.os_duracao_sugerida(p_os);
  v_est := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null else (v_sug ->> 'dias_realista')::numeric end;
  if v_tipo = 'comecada' and v_rastro then
    v_prop := least(cf.quanto_falta_dias, coalesce(v_est, cf.quanto_falta_dias));
  else
    v_prop := coalesce(v_est, cf.sem_mo_dias);
  end if;
  -- (7a correção, achado 10) a pergunta aberta da OS não é lida aqui: a conta da prontidão (que chama esta função pela
  -- estimativa) não lê as perguntas nem as ações da agenda, e a memória da vigia volta à marca de sempre
  v_semp := coalesce((v_sug ->> 'dp_realista')::numeric > cf.estimativa_max_diarias, false);

  v_curto := case when v_tipo = 'parada' then 'parado desde ' || to_char(v_desde, 'DD/MM') else 'já começou?' end;
  v_txt := case
    -- (7a correção, achado 20) acima de estimativa_max_diarias o gestor não marca sozinho: espera o dono
    when v_semp and v_tipo = 'parada' then
      format('falta você dizer se ainda é para fazer o serviço inteiro (parado desde %s); pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você',
             to_char(v_desde, 'DD/MM'), public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(cf.estimativa_max_diarias))
    when v_semp and v_rastro then
      format('falta você dizer quanto falta (começou em %s); pelo orçamento o serviço inteiro dá %s diárias, mais de %s: não marco sozinho, espero você',
             to_char(v_desde, 'DD/MM'), public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(cf.estimativa_max_diarias))
    when v_semp then
      format('falta você dizer se o serviço já começou (está como "%s", sem check-in nem diária ligada); pelo orçamento são %s diárias, mais de %s: não marco sozinho, espero você',
             public._agenda_status_texto(so.status), public._agenda_num((v_sug ->> 'diarias_realista')::numeric), public._agenda_num(cf.estimativa_max_diarias))
    when v_tipo = 'parada' then
      format('falta você dizer se ainda é para fazer o serviço inteiro (parado desde %s); sem resposta, conto o serviço inteiro (%s, estimativa minha)',
             to_char(v_desde, 'DD/MM'), public._agenda_dias(v_prop))
    when v_rastro then
      format('falta você dizer quanto falta (começou em %s); sem resposta, marco %s para terminar',
             to_char(v_desde, 'DD/MM'), public._agenda_dias(v_prop))
    else
      format('falta você dizer se o serviço já começou (está como "%s", sem check-in nem diária ligada); sem resposta, conto o serviço inteiro (%s, estimativa minha)',
             public._agenda_status_texto(so.status), public._agenda_dias(v_prop))
  end;
  return jsonb_build_object('pendente', true, 'tipo', v_tipo, 'rastro', v_rastro, 'desde', v_desde,
                            'proposta_dias', trim_scale(v_prop), 'sem_padrao', v_semp, 'status', so.status,
                            'curto', v_curto, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_os_situacao(uuid, date) is
  'Agenda de Produção (Fase 7a, P2; AG7-11): a OS que começou ou parou, antes de o gestor contar a estimativa cheia. Só com o portão situacao, sem os_planejamento.dias e sem alocação de compromisso vigente. comecada = check-in ou status in_progress/awaiting_parts; parada = open/approved/scheduled sem atividade (conversão, assinatura, updated_at, ai_lifecycle_events, agenda_acoes) há mais de situacao_dias. rastro = check-in, in_progress ou diária ligada. proposta_dias = quanto_falta_dias com rastro (nunca mais que a estimativa inteira), senão os dias da estimativa (sem base: sem_mo_dias). {pendente, tipo, rastro, desde, proposta_dias, pergunta_id (a pergunta situacao aberta), status, curto (a linha curta do "eu perguntaria"), texto (a restrição ao dono)}; senão {pendente: false}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa): (achados 2, 11 e 22) a OS em aguardando peças sem check-in nem diária ligada cuja última alocação cancelada (fora a reserva) saiu pelo material — a própria agenda (agenda_aplicar) a pôs em aguardando peças ao tirá-la do plano — não é "começada": não pende (volta à reserva pelo material, com o "de quem e quando?", spec §3.2); (achado 10) a parada conta a última mexida da agenda pelas alocações e pelo planejamento, não por agenda_acoes, e a saída não traz mais pergunta_id: a conta da prontidão não lê agenda_acoes nem agenda_perguntas, e a memória da vigia volta à marca de sempre; (achado 20) com a estimativa inteira acima de estimativa_max_diarias (sem_padrao), o texto diz que o gestor não marca sozinho e espera o dono. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): a parada conta também o planejamento que o dono mexeu (os_planejamento.atualizado_em com atualizado_por preenchido: os dias, a dupla, a presença), como o comentário da correção 1 dizia.';

-- _agenda_aprontar_de (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_aprontar_de(p_pn jsonb, p_k integer)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_cand    jsonb;
  v_n       int;
  v_resto   jsonb;
  v_bul     text[];
  v_chute   boolean;
  l_cab     text;
  l_voce    text;
  l_pe      text;
begin
  -- Quem entra: a fila com algo que só o dono responde (o que trava primeiro, depois só a duração), na ordem de trabalho.
  select coalesce(jsonb_agg(e order by (e ->> 'dono_trava')::boolean desc, (e ->> 'ordem')::int), '[]'::jsonb)
    into v_cand from jsonb_array_elements(p_pn -> 'oss') e
   where (e ->> 'executavel')::boolean and jsonb_array_length(e -> 'restr_dono') > 0;
  -- FASE 7: (7a correção, achado 24) só a pergunta de fato ao dono entra (a duração ou a restrição com "pergunta"): a suposição
  -- do gestor que não pergunta (sem_peca_suposta, "marquei sem peça a comprar; se precisar, me diga") virava a linha vazia
  -- "• Lenine (OS-00074): " no aviso. A OS sem nenhuma pergunta de fato sai da lista; sem restrição sem pergunta, nada muda.
  select coalesce(jsonb_agg(f.e order by f.o), '[]'::jsonb) into v_cand
    from (select t.o,
                 t.e || jsonb_build_object('restr_dono',
                          (select coalesce(jsonb_agg(
                                    -- (7a correção 2, o texto colado) a frase do gestor termina com ponto: "… conto 4 dias. Compra
                                    -- quando?", não "… conto 4 dias Compra quando?"
                                    case when r ->> 'tipo' = 'duracao' and public._agenda_gestor_regra('estimativa')
                                              and coalesce(r ->> 'texto', '') !~ '[.?!)]\s*$'
                                         then r || jsonb_build_object('texto', rtrim(r ->> 'texto') || '.') else r end
                                    order by ro), '[]'::jsonb)
                             from jsonb_array_elements(t.e -> 'restr_dono') with ordinality u(r, ro)
                            where (r ->> 'tipo' = 'duracao' or nullif(btrim(coalesce(r ->> 'pergunta', '')), '') is not null)
                              -- (7a correção 2, o texto repetido) a pergunta da situação não vem depois da frase do gestor que já a
                              -- diz ("Perguntei se já começou; sem resposta, conto 4 dias." sem o "O serviço já começou?")
                              and not (r ->> 'tipo' = 'situacao'
                                       and exists (select 1 from jsonb_array_elements(t.e -> 'restr_dono') d
                                                    where d ->> 'tipo' = 'duracao' and d ->> 'texto' ~ '^perguntei (se|quanto)')))) as e
            from jsonb_array_elements(v_cand) with ordinality t(e, o)) f
   where jsonb_array_length(f.e -> 'restr_dono') > 0;
  -- FASE 7: fim
  v_n := jsonb_array_length(v_cand);

  -- Uma pergunta por OS: as perguntas do dono na ordem da prontidão; a duração com o chute entre parênteses.
  v_bul := array(
    select '• ' || public._agenda_rotulo(e, 'num') || ': '
           || array_to_string(array(
                select case when ro = 1 then q else public._agenda_maiuscula(q) end
                  from (select case when r ->> 'tipo' = 'duracao' then replace(r ->> 'texto', '(chute: ', '(')
                                    else r ->> 'pergunta' end as q, ro
                          from jsonb_array_elements(e -> 'restr_dono') with ordinality t2(r, ro)) z
                 order by ro), ' ')
      from jsonb_array_elements(v_cand) with ordinality t(e, o)
     where o <= p_k order by o);
  v_chute := exists (select 1 from jsonb_array_elements(v_cand) with ordinality t(e, o), jsonb_array_elements(e -> 'restr_dono') r
                      where o <= p_k and r ->> 'tipo' = 'duracao' and r ->> 'texto' like '%(chute: %');
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by o), '[]'::jsonb)
    into v_resto from jsonb_array_elements(v_cand) with ordinality t(e, o) where o > p_k;

  if not (p_pn ->> 'dono_padrao')::boolean then
    l_voce := '• Você: semana que vem fica em campo quais dias?';
  end if;
  if v_n = 0 and l_voce is null then
    return jsonb_build_object('linhas', to_jsonb(array['Não tenho nada para perguntar agora: o que dependia de você já está respondido.']),
                              'dados', jsonb_build_object('oss', '[]'::jsonb, 'resto', '[]'::jsonb, 'voce', false));
  end if;
  l_cab := case when v_n = 0 then 'Para montar a semana:'
                else 'Para montar a semana, uma resposta por OS'
                     || case when v_chute then ' (entre parênteses, o meu chute pelo valor)' else '' end || ':' end;
  l_pe := 'Pode ser um áudio só'
          || case when v_n > 0 then ', citando o nome do cliente.' else '.' end
          || case when jsonb_array_length(v_resto) > 0 then
               ' (' || public._agenda_nomes(v_resto, null, 'np')
               || case when jsonb_array_length(v_resto) = 1 then ' fica' else ' ficam' end || ' para depois.)'
             else '' end;

  return jsonb_build_object(
    'linhas', to_jsonb(array[l_cab] || v_bul || array[l_voce, l_pe]),
    'dados', jsonb_build_object(
      'oss', (select coalesce(jsonb_agg(e ->> 'numero' order by o), '[]'::jsonb)
                from jsonb_array_elements(v_cand) with ordinality t(e, o) where o <= p_k),
      'resto', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_resto) with ordinality t(e, o)),
      'voce', l_voce is not null));
end;
$function$;

comment on function public._agenda_aprontar_de(jsonb, integer) is 'Agenda de Produção (Fase 1, P4): as linhas da rodada de aprontar a partir do painel, com até p_k OS. CORREÇÃO DA 7a (revisão da etapa; achado 24): só entra a OS com alguma pergunta de fato ao dono (a duração ou uma restrição com "pergunta"), e só essas perguntas vão na linha dela: a suposição do gestor que não pergunta (sem_peca_suposta, da 7a) não vira mais a linha vazia "• Lenine (OS-00074): " no aviso. Sem restrição sem pergunta, a de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; o texto colado): com a regra estimativa, a frase do gestor na duração termina com ponto, e a pergunta da situação ("o serviço já começou?") não vem depois da frase que já a diz ("Perguntei se já começou; sem resposta, conto 4 dias."). Sem a regra, a de antes, byte a byte.';

-- _agenda_compras_da_semana (de 20261031100800_agenda_fase7a_compras.sql)
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
  -- FASE 7: (7a correção 2) as OS que saíram da agenda pelo material sem a compra
  v_f72_s jsonb;
  -- FASE 7: fim
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

  -- FASE 7: (7a correção 2, o compre até da OS que saiu; D7-2) a OS que a vigia tirou do plano pelo material sem a compra
  -- (_agenda_gestor_compra_saiu) continua nas compras, vencida — "… 4 itens de César — saiu da agenda: comprando hoje, chega para
  -- começar seg 16/11." (a linha compras do fechamento vai como decisão, perda 80). Antes ela sumia com a OS.
  for v_f72_s in select x from jsonb_array_elements(public._agenda_gestor_compra_saiu(p_hoje)) x loop
    for i in select y from jsonb_array_elements(v_f72_s -> 'itens') y loop
      v_its := v_its || (i || jsonb_build_object('os', v_f72_s -> 'os', 'numero', v_f72_s ->> 'numero', 'cliente', v_f72_s ->> 'cliente',
                                                 'primeiro', null,
                                                 'grupo', case when i ->> 'fornecedor' is null
                                                                 then format('Sem fornecedor (contei %s)', v_pad)
                                                               when i ->> 'prazo_fonte' = 'padrao'
                                                                 then format('%s (contei %s)', i ->> 'fornecedor', v_pad)
                                                               else i ->> 'fornecedor' end));
    end loop;
  end loop;
  -- FASE 7: fim
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
                    case -- (7a correção 2) a OS que saiu da agenda pelo material sem a compra
                         when bool_or(coalesce((y ->> 'saiu')::boolean, false))
                           then 'saiu da agenda: comprando hoje, chega para começar ' || public._dia_curto(min((y ->> 'chega_em')::date))
                         when bool_or((y ->> 'urgente')::boolean)
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
  'Agenda de Produção (Fase 7a, P10; spec §5.10, §6.2 item 5): as compras da semana — das OS com compromisso de hoje em diante (_agenda_gestor_compra_conta), os itens críticos em falta com o "compre até" (o dia que o dono ouve) até o fim da semana que vem (os vencidos também), por fornecedor ("Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje."; urgente, o 1º dia antes de compra_urgente_du dias úteis: "— compre hoje para começar ter 10/11") e os não críticos das OS que começam no próximo dia útil ("Separar amanhã: 8 × Porta Fusível MIDI… (Vanderlei)."). Os urgentes primeiro, depois pelo "compre até"; o separar no fim. [{texto, compre_ate, urgente, fornecedor, itens} | {texto, compre_ate null, urgente false, separar true, dia, itens}] — o que o passo compre_ate grava no diário (agenda_gestor_dia.compras: a linha compras do fechamento e o foco gestor) e o 7f lê. STABLE, invoker, sem grant. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; o compre até da OS que saiu, D7-2): a OS que saiu da agenda pelo material sem a compra (_agenda_gestor_compra_saiu) continua nas compras, vencida ("Sem fornecedor (contei 7 dias úteis): 4 itens de César — saiu da agenda: comprando hoje, chega para começar seg 16/11."), com o item marcado saiu. Sem OS assim, a de antes.';

-- _agenda_gestor_compre_ate (de 20261031100800_agenda_fase7a_compras.sql)
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
  -- FASE 7: (7a correção 2) as OS que saíram da agenda pelo material sem a compra
  v_f72_s   jsonb;
  v_f72_n   int;
  v_f72_lin uuid[];
  -- FASE 7: fim
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

    -- FASE 7: (7a correção 2, o compre até da OS que saiu; D7-2, spec §3.2 "Compra" e §5.10) a OS que a vigia tirou do plano pelo
    -- material com o "compre até" vencido e a peça sem compra (_agenda_gestor_compra_saiu): (1) o empurrão conta uma vez por saída
    -- (empurrada_vezes + 1, a saída anotada em compre_ate_base.saiu_em; compre_ate_em = agora, para a remarcação de depois não o
    -- contar de novo); (2) na hora da cobrança, a pergunta continua — "César (OS-00119) saiu da agenda: …" ou, no teto, o "parei
    -- de remarcar" — e a pergunta aberta dela não é resolvida "não precisa mais". No teto, a prontidão tira o compra_firme e a OS
    -- volta à reserva com o "de quem e quando?". Só ligado (em teste nada é gravado: não há OS assim).
    if not v_sim then
      for v_f72_s in select x from jsonb_array_elements(public._agenda_gestor_compra_saiu(p_hoje)) x loop
        v_f72_lin := array(select (y ->> 'linha')::uuid from jsonb_array_elements(v_f72_s -> 'itens') y
                            where not (y ->> 'contado')::boolean);
        if cardinality(v_f72_lin) > 0 then
          update public.os_material m
             set empurrada_vezes = least(20, m.empurrada_vezes + 1),
                 compre_ate_base = m.compre_ate_base || jsonb_build_object('saiu_em', v_f72_s -> 'saiu_em'),
                 compre_ate_em = p_agora,
                 historico = public._os_material_historico(m.historico, jsonb_strip_nulls(jsonb_build_object(
                   'em', p_hoje, 'por', 'gestor', 'compre_ate', m.compre_ate, 'empurrou', true,
                   'nota', format('o serviço saiu da agenda sem a compra: %s',
                                  public._agenda_plural(m.empurrada_vezes + 1, 'empurrão', 'empurrões')))))
           where m.id = any (v_f72_lin);
          get diagnostics v_f72_n = row_count;
          v_emp := v_emp + v_f72_n;
        end if;
        if v_cobra then
          v_n := jsonb_array_length(v_f72_s -> 'itens');
          v_lista := public._agenda_lista(array(
                       select case when (x ->> 'quantidade')::numeric > 1
                                   then format('%s × %s', replace(x ->> 'quantidade', '.', ','), x ->> 'item') else x ->> 'item' end
                         from jsonb_array_elements(v_f72_s -> 'itens') with ordinality t(x, o) order by o), 3);
          v_itens := case when v_n = 1 then v_lista else format('%s itens', v_n) end;
          v_vezes := (select max((x ->> 'empurrada_vezes')::int) from jsonb_array_elements(v_f72_s -> 'itens') x);
          v_dia := (select max((x ->> 'chega_em')::date) from jsonb_array_elements(v_f72_s -> 'itens') x);
          if exists (select 1 from jsonb_array_elements(v_f72_s -> 'itens') x where (x ->> 'limite')::boolean) then
            v_var := 'limite';
            v_chave := format('compre_ate:%s:limite:%s', v_f72_s ->> 'os', v_vezes);
            v_txt := format('Os itens de %s já empurraram o serviço %s: parei de remarcar. Ele fica guardado até você me dizer de quem e quando compra.',
                            v_f72_s ->> 'cliente', public._agenda_plural(v_vezes, 'vez', 'vezes'));
          else
            v_var := 'saiu';
            v_chave := format('compre_ate:%s:saiu:%s', v_f72_s ->> 'os', ((v_f72_s ->> 'saiu_em')::timestamptz at time zone 'America/Sao_Paulo')::date);
            v_txt := format('%s saiu da agenda: o ''compre até'' de %s venceu %s e a peça não chegaria a tempo.%s Quando comprar, me diga o dia que chega e eu marco de novo.',
                            public._agenda_rotulo_da_os((v_f72_s ->> 'os')::uuid), v_itens,
                            public._dia_curto((select min((x ->> 'compre_ate')::date) from jsonb_array_elements(v_f72_s -> 'itens') x)),
                            case when v_dia is not null then format(' Comprando hoje, chega para começar %s.', public._dia_curto(v_dia))
                                 else '' end);
          end if;
          v_ids := array(select (x ->> 'linha')::uuid from jsonb_array_elements(v_f72_s -> 'itens') x);
          v_nova := not exists (select 1 from public.agenda_perguntas q
                                 where q.chave = left(v_chave, 200) and q.modo = 'ligado' and q.estado = 'aberta');
          v_id := public._agenda_gestor_perguntar('compre_ate', v_chave, (v_f72_s ->> 'os')::uuid, v_txt, '[]'::jsonb, null, null, null,
                                                  'ligado', p_agora);
          v_nova := v_nova and v_id is not null;
          if v_id is not null then
            v_chaves := v_chaves || left(v_chave, 200);
            v_oss_q := v_oss_q || (v_f72_s ->> 'os')::uuid;
          end if;
          if v_nova then
            update public.os_material m
               set cobrado_em = p_agora, cobrado_vezes = least(50, m.cobrado_vezes + 1)
             where m.id = any (v_ids);
            v_cob := v_cob + 1;
          end if;
          if v_var = 'limite' then
            v_lim := v_lim + 1;
          end if;
          v_pergs := v_pergs || jsonb_build_object('os', v_f72_s -> 'os', 'numero', v_f72_s ->> 'numero', 'variante', v_var,
                                                   'chave', v_chave, 'texto', v_txt, 'pergunta_id', v_id, 'nova', v_nova,
                                                   'itens', v_n);
        end if;
        v_oss := v_oss || jsonb_build_object('os', v_f72_s -> 'os', 'numero', v_f72_s ->> 'numero', 'primeiro', null,
                                             'itens', jsonb_array_length(v_f72_s -> 'itens'), 'saiu', true,
                                             'compre_ate', (select min((x ->> 'compre_ate')::date) from jsonb_array_elements(v_f72_s -> 'itens') x),
                                             'cobranca', case when v_cobra then v_var end);
      end loop;
    end if;
    -- FASE 7: fim
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
  'Agenda de Produção (Fase 7a, P10; spec §5.10, §3.2, §6.3; D7-2, AG7-05/06/07): o passo compre_ate da rodada do gestor, em todo tique (a rodada recriada o chama também fora dos diários). Ligado: grava em os_material o "compre até" da conta (_agenda_gestor_compra_conta: o 1º dia − folga − prazo − compra_interna_du), a base e compre_ate_em quando a conta muda (com a entrada no histórico da linha) e soma o empurrão no item quando a OS foi remarcada pelo material depois do "compre até" vencido. A partir de gestor_hora_revisao, em dia útil, a cobrança: uma pergunta compre_ate por OS (sem opções, sem prazo), limite ("Os itens de Vanderlei já empurraram o serviço 2 vezes: parei de remarcar. …"), urgente ("Compre hoje: … para começar ter 10/11 (faltam menos de 7 dias úteis). …"), hoje ("Compre até hoje: 3 itens de Vanderlei (…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço segue em qui 12/11.") ou vencido ("Venceu qui 29/10 o ''compre até'' de 3 itens de Vanderlei. Comprando hoje ainda chega para qui 12/11."); comprando hoje sem chegar = nada (a vigia empurra); a pergunta nova conta cobrado_em/cobrado_vezes; a aberta que não vale mais, resolvida; e o diário agenda_gestor_dia.compras = _agenda_compras_da_semana. Em teste, tudo seco (as regras do gestor só dentro do passo) e só o diário. Desligado = {pulado}. Security definer, sem grant a ninguém. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; o compre até da OS que saiu — D7-2, spec §3.2 "Compra" e §5.10): ligado, a OS que a vigia tirou do plano pelo material com o "compre até" vencido e a peça sem compra (_agenda_gestor_compra_saiu) não some do passo — o empurrão conta uma vez por saída (empurrada_vezes + 1; compre_ate_base.saiu_em; compre_ate_em = agora) e, na hora da cobrança, a pergunta compre_ate continua: saiu ("César (OS-00119) saiu da agenda: o ''compre até'' de 4 itens venceu qua 04/11 e a peça não chegaria a tempo. Comprando hoje, chega para começar seg 16/11. Quando comprar, me diga o dia que chega e eu marco de novo.", chave compre_ate:<os>:saiu:<dia da saída>) ou, no teto de empurrões, o limite de sempre — e não é resolvida "não precisa mais". No teto, a prontidão tira o compra_firme e a OS volta à reserva com o "de quem e quando?".';

-- ── 3. Portas (as de antes das recriadas continuam: create or replace não mexe no grant) ─────────────────────────────
-- _agenda_equipe_tem_telefone e _agenda_gestor_compra_saiu: só as funções da agenda as chamam (as fichas, a rotina da ficha, o compre
-- até e as compras da semana): sem grant a ninguém. _agenda_tecnicos_da_grade e _agenda_tecnicos_frase são lidas pela classe da OS e
-- pelo foco (invoker, com o login de quem pergunta no painel): authenticated e service_role, nunca anon.
revoke all on function public._agenda_equipe_tem_telefone(uuid), public._agenda_gestor_compra_saiu(date)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_tecnicos_da_grade(date), public._agenda_tecnicos_frase(text[]) from public, anon;
grant execute on function public._agenda_tecnicos_da_grade(date), public._agenda_tecnicos_frase(text[]) to authenticated, service_role;
