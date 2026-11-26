-- Agenda de Produção — pacote 1 do assistente, A1b (24/11/2026): o orçamento parado no "aguardando sinal" não ganha dia sozinho.
--
-- Por quê (especificação: D:/IA-HBR/Trabalho/avaliacao-assistente-20261124/pacote1/spec-agenda.md, seção "A1.(b) O menor conserto"): pela
-- regra AG7-09 do dono ("marco e cobro o sinal", 20261031100900), o sinal combinado e não pago não segura a OS: com a regra sinal_cobrar,
-- _agenda_classe_da_os ignora a trava sinal e a OS vai à classe que teria sem ela. Mas "aguardando sinal" não tem idade: o ORÇ-00095,
-- parado em "aguardando sinal" desde 25/09 (48 dias em 12/11), ganhou do motor 4 meios-dias (09 e 10/12) e 6 "compre até".
--
-- O que muda:
--   1. _agenda_sinal_parado(p_pront, p_hoje), NOVA: true quando agenda_config.sinal_cobrar_max_dias não é nula, a prontidão é de ORÇAMENTO
--      (eh_orcamento: status draft) em quote_status awaiting_deposit e a última vez que quote_status VIROU awaiting_deposit foi há MAIS de
--      sinal_cobrar_max_dias dias. "Virou" = a linha de audit_log de service_orders com new_value.quote_status = awaiting_deposit e
--      previous_value.quote_status diferente disso (ou sem ele), a mais nova, na data de Brasília; sem nenhuma, aprovada_em da prontidão; sem
--      ela, hoje (idade 0). Com a chave nula (o padrão), false sem ler audit_log. A OS convertida (status <> draft) com sinal pendente nunca
--      entra: continua AG7-09. SECURITY DEFINER (audit_log tem RLS: o técnico não lê), STABLE, search_path = public; devolve só o booleano.
--      Execute para authenticated e service_role (a cadeia de _agenda_classe_da_os, que as leituras do painel executam como authenticated);
--      nunca anon nem PUBLIC (revoke de PUBLIC não fecha anon: o Supabase dá execute a anon por padrão).
--   2. _agenda_classe_da_os, recriada do corpo EM PRODUÇÃO (pacote1/agenda-prod/_agenda_classe_da_os.sql, conferido em 26/11/2026: md5 de
--      pg_get_functiondef ce9ca8f1… com CR, acd8c192… sem CR; o corpo, prosrc sem CR, 9b4134d6…, o da 20261112100700) com UMA condição a mais
--      no bloco "FASE 7: (7a P12 …)", num bloco "-- P1 AGENDA: … -- P1 AGENDA: fim" (a linha de antes em "--antes:"): a trava do sinal só é
--      ignorada quando o orçamento não está parado. Tirado o bloco (devolvida a linha "--antes:"), o corpo é o de produção, byte a byte.
--   Com a chave nula, _agenda_sinal_parado é false e a classe é a de hoje.
--
-- O que NÃO faz (de propósito): não cancela os dias que já existem (_agenda_violacoes não tira compromisso por classe; o ORÇ-00095 de hoje é do
-- dono, A1a); não mexe em marcar_regras (sinal_cobrar fica), em handle_quote_deposit_payment nem na situação do orçamento. Nenhuma tabela,
-- coluna, CHECK, modo, cron, mensagem ou edge function. Texto novo ao dono: nenhum (o orçamento parado mostra o da trava: "esperando o sinal").
--
-- A chave: agenda_config.sinal_cobrar_max_dias (20270301120000), nasce nula. Ligar (com o OK nomeado do dono):
--   update public.agenda_config set sinal_cobrar_max_dias = 15 where id;
-- Custo: um acesso a audit_log pelo índice audit_log_registro_idx (table_name, record_id, changed_at desc), só quando a trava é sinal, a regra
-- sinal_cobrar vale, a chave não é nula e a prontidão é de orçamento em awaiting_deposit.
-- Portas: create or replace não mexe na ACL nem no dono de _agenda_classe_da_os (as de 20261031100900: invoker, STABLE, execute para
-- authenticated e service_role, nunca anon nem PUBLIC).
-- IDEMPOTENTE: create or replace, revoke e grant; o comentário da classe só ganha o trecho do A1b uma vez. A bancada aplica duas vezes.
-- DESFAZER: rápido, update public.agenda_config set sinal_cobrar_max_dias = null where id; (o de hoje, sem tocar função). Completo: recriar
-- _agenda_classe_da_os do corpo de produção e drop function public._agenda_sinal_parado(jsonb, date) (pacote1/agenda-lote2/a1b/voltar.sql).

-- ── 1. A função nova ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_sinal_parado(p_pront jsonb, p_hoje date)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- o orçamento (ainda draft) esperando o sinal há mais de sinal_cobrar_max_dias: não é "combinado", a trava do sinal fica. A idade conta da
  -- última vez que quote_status virou awaiting_deposit (audit_log, índice audit_log_registro_idx; a linha que já vinha de awaiting_deposit não
  -- conta), na data de Brasília; sem esse registro, de aprovada_em da prontidão; sem ela, de hoje. A OS (convertida) com sinal pendente nunca
  -- entra aqui: continua AG7-09. Chave nula = false, sem ler audit_log; sem a linha de agenda_config, false.
  select coalesce((
    select c.sinal_cobrar_max_dias is not null
       and coalesce((p_pront ->> 'eh_orcamento')::boolean, false)
       and p_pront ->> 'quote_status' = 'awaiting_deposit'
       and p_hoje - coalesce(
             (select (max(a.changed_at) at time zone 'America/Sao_Paulo')::date
                from public.audit_log a
               where a.table_name = 'service_orders' and a.record_id = (p_pront ->> 'os')::uuid
                 and a.new_value ->> 'quote_status' = 'awaiting_deposit'
                 and a.previous_value ->> 'quote_status' is distinct from 'awaiting_deposit'),
             (p_pront ->> 'aprovada_em')::date, p_hoje) > c.sinal_cobrar_max_dias
      from public.agenda_config c
     where c.id), false)
$function$;

comment on function public._agenda_sinal_parado(jsonb, date) is
  'Agenda de Produção, pacote 1 do assistente (A1b, 24/11/2026, 20270301120100; AG7-09 com idade): o orçamento (eh_orcamento, ainda draft) em quote_status awaiting_deposit cuja última virada para awaiting_deposit (audit_log de service_orders: new_value.quote_status = awaiting_deposit e previous_value.quote_status diferente; a mais nova, na data de Brasília; sem ela, aprovada_em da prontidão; sem ela, hoje) foi há mais de agenda_config.sinal_cobrar_max_dias dias está "parado no sinal": _agenda_classe_da_os não ignora a trava do sinal para ele (a regra sinal_cobrar fica só para o sinal combinado de verdade). Chave nula (o padrão) = false, sem ler audit_log. A OS convertida com sinal pendente nunca entra (continua AG7-09). Devolve só o booleano. Security definer (audit_log tem RLS), STABLE, search_path = public; execute para authenticated e service_role (a cadeia de _agenda_classe_da_os), nunca anon nem PUBLIC.';

revoke all on function public._agenda_sinal_parado(jsonb, date) from public, anon;
grant execute on function public._agenda_sinal_parado(jsonb, date) to authenticated, service_role;

-- ── 2. _agenda_classe_da_os, recriada do corpo de produção (26/11/2026) com o bloco do A1b ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_classe_da_os(p_pront jsonb, p_meios jsonb, p_hoje date, p_tem_fixada boolean DEFAULT false, p_fora_do_horizonte boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
  -- FASE 7b: (7b P4, R4.3(b)) quantas pessoas a dupla dita pede num passo
  v_7b_n    int;
  -- FASE 7b: fim
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
  -- P1 AGENDA: (A1b, 24/11/2026; agenda_config.sinal_cobrar_max_dias) o orçamento parado no "aguardando sinal" há mais desses dias
  -- (_agenda_sinal_parado) não é sinal combinado: não ganha dia sozinho, a trava do sinal fica. A OS convertida com sinal pendente e o
  -- orçamento que virou awaiting_deposit há poucos dias continuam AG7-09. Chave nula (o padrão) = o de antes.
  if v_trava ->> 'tipo' = 'sinal' and public._agenda_gestor_regra('sinal_cobrar')
     and not public._agenda_sinal_parado(p_pront, p_hoje) then
--antes:  if v_trava ->> 'tipo' = 'sinal' and public._agenda_gestor_regra('sinal_cobrar') then
  -- P1 AGENDA: fim
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('orcamento', 'cliente', 'escopo') order by o limit 1;
  end if;
  -- FASE 7: fim
  if v_trava is not null then
    return jsonb_build_object('classe', 4, 'motivo', v_trava ->> 'tipo', 'texto', v_trava ->> 'texto');
  end if;
  -- FASE 7b: (7b P4, R4.3(b)) a dupla DITA pelo dono (fonte dono: o tempo todo, no início ou no fim — a dita no início ou no fim
  -- a correção 2 não via, o desejado dela é 1) com modo_dupla fora de desligado (o dk só existe assim): pede o maior dk dos passos que
  -- restam (o dono que conta como uma das pessoas sai da conta); com menos técnicos na grade (_agenda_tecnicos_da_grade: com quem
  -- vem sob demanda, R4.3(c)) espera o dono, classe 4 dupla — também em teste: sem isso a dita no início sairia do plano calada. A
  -- dupla inferida pela tarefa (fonte regra) nunca segura a OS: vai com 1 pessoa (o encaixe).
  if p_meios ? 'dk' and p_meios #>> '{dupla,fonte}' = 'dono' and not coalesce((p_meios ->> 'equipe_dita')::boolean, false) then
    v_7b_n := coalesce((select max(x::int) from jsonb_array_elements_text(p_meios -> 'dk') x), 0)
              - case when coalesce((p_meios ->> 'dk_dono_conta')::boolean, true)
                          and (coalesce((p_meios #>> '{dono_turno,manha}')::boolean, false)
                               or coalesce((p_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end;
    if v_7b_n >= 2 then
      v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_f72_tec) < v_7b_n then
        return jsonb_build_object('classe', 4, 'motivo', 'dupla',
          'texto', format('precisa de %s pessoas e %s: chame um ajudante e me diga os dias dele', v_7b_n,
                          public._agenda_tecnicos_frase(v_f72_tec)));
      end if;
    end if;
  end if;
  -- FASE 7b: fim
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
    -- FASE 7g: (7g P5b; §5.5, R9.4-4 pontos 1, 3, 4 e 5) o tipo de OS que espera o ok do dono (agenda_tipos_os.nivel espera_ok, gravado na OS em
    -- os_planejamento.espera_ok_desde pela rodada explicar): a OS pronta com os dias pelo orçamento (fonte orcamento) só reserva, condição ok_do_dono, até o dono
    -- dizer 1 na pergunta ok_marcacao ou o prazo dela vencer (agenda_decidir). Só aqui, depois de nada mais segurar a OS (v_cond vazio) e com fonte orcamento:
    -- antes disso, nenhuma consulta nova (R9.8). _agenda_espera_ok lê o modo cru e a linha (R9.6): com *gestor, só propor* a reserva fica. A OS vem de
    -- p_pront (os_prontidao tem a chave os). Motivo espera, que o "de fora" já diz ("esperando a sua decisão"). Com a opção 2 ("Não marca: eu digo os dias")
    -- dada desde que a OS passou a esperar, ela espera os dias do dono (classe 4 duracao), sem reservar e perguntar de novo a cada replano.
    if p_meios ->> 'fonte' = 'orcamento' and public._agenda_espera_ok((p_pront ->> 'os')::uuid) then
      if exists (select 1 from public.agenda_perguntas q
                  join public.os_planejamento pl on pl.service_order_id = q.service_order_id
                 where q.service_order_id = (p_pront ->> 'os')::uuid and q.tipo = 'ok_marcacao' and q.estado = 'respondida'
                   and q.opcao_escolhida = 2 and q.respondida_em >= pl.espera_ok_desde) then
        return jsonb_build_object('classe', 4, 'motivo', 'duracao',
                                  'texto', 'quantos dias e com quem? (você disse para eu não marcar pelo orçamento)');
      end if;
      return jsonb_build_object('classe', 3, 'motivo', 'espera', 'condicao_tipo', 'ok_do_dono', 'condicoes', jsonb_build_array('ok_do_dono'),
                                'texto', 'espero o seu ok');
    end if;
    -- FASE 7g: fim
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

-- ── 3. O comentário da recriada (o de antes + o que mudou; uma vez só) ─────────────────────────────────────────────────────────────────
do $c$
declare
  c_f constant text := 'public._agenda_classe_da_os(jsonb,jsonb,date,boolean,boolean)';
begin
  if coalesce(obj_description(to_regprocedure(c_f), 'pg_proc'), '') not like '%P1 AGENDA (A1b, 24/11/2026%' then
    execute format('comment on function %s is %L', c_f, coalesce(obj_description(to_regprocedure(c_f), 'pg_proc'), '')
      || ' P1 AGENDA (A1b, 24/11/2026, 20270301120100): com agenda_config.sinal_cobrar_max_dias preenchida, o orçamento parado no "aguardando sinal" há mais desses dias (_agenda_sinal_parado) não ganha dia sozinho: a trava do sinal volta a valer para ele (classe 4, motivo sinal, "esperando o sinal"). A OS convertida com sinal pendente continua AG7-09. Chave nula (o padrão) = o de antes.');
  end if;
end
$c$;

insert into supabase_migrations.schema_migrations (version, name) values ('20270301120100','agenda_p1_sinal_parado');
