-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P4b: o puxar. Às 17:30 da véspera, o que sobrou de amanhã de quem já vem puxa a próxima OS pronta.
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (§5.3 e o bloco R7, que vale sobre o corpo: R7.6, R7.7, R7.8, R7.12, R7.13); nomes: fase7-registro.md; o registro do pacote: f7e/p4b/notas.md.
-- Depende de 20261111100000 (P1) e de 20261111100300 (P4: os ganchos de p_restricoes.puxar em agenda_propor e no validador). Uma função nova, nenhuma recriada; agenda_gestor_rodar NÃO muda: o passo 'puxar' já está em c_tique
-- (20261101100500:868) e entra sozinho pelo to_regprocedure assim que _agenda_gestor_puxar(date, timestamptz) existe (R7.1).
--
-- ═══ NÃO APLICADA ═══ Existe para revisão e espera o OK (publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção). Só 1 função; nenhuma coluna, nenhuma tabela, nenhum dado.
--
-- POR QUE: a folga da semana guarda lugar para a urgência. Se ninguém usou até a véspera, o lugar se perde: quem já vem amanhã com o outro turno livre pode fazer a próxima OS pronta. Hoje isso não roda (R7.10-6): ninguém da rotina tem telefone
-- e a OS pronta sem dia não tem o acesso combinado nem o bem no pátio; quando destravar, é coisa de 1 ou 2 vezes por mês.
--
-- O QUE MUDA:
--   _agenda_gestor_puxar(date, timestamptz): o passo do job agenda-gestor. O peso (R7.8): fora de hora é 1 leitura de config; as contas da fila só depois de ter célula livre; os filtros baratos antes de os_prontidao.
--     Em teste (modo_urgencia em sombra, freio ligado ou modo_proposta em sombra): só o diário (agenda_gestor_dia.sombra.puxar), sem proposta, ação nem alocação (R7.7-1). De verdade: propõe na simulação, aceita só compromisso que comece em D, propõe de novo gravando e aplica.
--     Com puxar_max_os > 1, em teste, a simulação de cada OS seguinte vê as já puxadas na rodada (os itens delas aplicados num bloco que se desfaz), como o de verdade as lê do banco.
--     Quem pode: da equipe, tem de ter telefone que a rotina alcance (R7.7-6) e a ficha de D ainda não saiu; o dono não está na rotina (quem o alcança é o aviso do gestor e o fechamento) e conta com o dia
--     declarado (§5.3). Em ja_vem, não pode ter convite de D sem o SIM enquanto o convite estiver ligado de verdade (R7.7-8). A ponta do dono (abrir e fechar) da OS puxada em D vale mesmo com ele fora das
--     pessoas: o motor só tira o turno de quem está fora, e o validador aceita a ponta (20261111100300).
--     A OS: pronta, sem alocação vigente que não seja reserva, bem livre em D, "não antes de" até D, o que foi dito ao cliente tem de caber em D, material até D, acesso combinado em local de terceiro ou o bem no pátio (conflito 9, R7.7-2), e o dono não desfez. Fora a ficha presa na janela de veto do 7a-1.
--   Sem texto novo. A contagem contagens.puxar da rodada troca o {"pulado": true} por {"rodou": false, ...} (ninguém a lê além dos testes). Em teste e com célula livre, o diário ganha a chave puxar, que sai crua em dados.sombra do foco gestor.

create or replace function public._agenda_gestor_puxar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_modo  text;
  v_real  boolean;
  v_d     date;
  v_meq   text;
  v_conv  boolean;
  v_dono  uuid;
  v_pes   uuid[];
  v_cel   int;
  v_tst   jsonb := '[]'::jsonb;
  v_fila  jsonb := '[]'::jsonb;
  c       record;
  v_tipo  text;
  v_lugar boolean;
  v_pr    jsonb;
  v_e     jsonb;
  v_os    uuid;
  v_rs    jsonb;
  v_p     jsonb;
  v_it    jsonb;
  v_a     jsonb;
  v_ini   date;
  v_mot   text;
  v_por   jsonb := '[]'::jsonb;
  v_n     int := 0;
  v_cand  int := 0;
  v_err   int := 0;
  v_st    text;
  v_msg   text;
  v_som   jsonb;
  v_res   jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_puxar: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- o portão de custo (R7.8: fora de hora, 1 leitura de config): lê a linha já carregada; quem decide em teste ou de verdade é _agenda_margem_modo, logo abaixo
  cf := public._agenda_cfg();
  if cf.modo_urgencia = 'desligado' or cf.modo_proposta = 'desligado' then
    return jsonb_build_object('rodou', false, 'modo', 'desligado');
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.puxar_hora then
    return jsonb_build_object('rodou', false, 'cedo', true);
  end if;
  if not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('rodou', false, 'motivo', 'nao_util');
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x
              where x.rotina = 'gestor' and x.p_hoje = p_hoje and x.contagens -> 'puxar' ->> 'rodou' = 'true') then
    return jsonb_build_object('rodou', false, 'ja_rodou', true);
  end if;

  -- com o freio, _agenda_margem_modo devolve sombra: só o diário (R7.6, R7.7-1)
  v_modo := public._agenda_margem_modo('urgencia');
  v_real := v_modo = 'ligado' and cf.modo_proposta = 'ligado';
  v_d := public.agenda_somar_du(p_hoje, 1);

  begin
    -- a trava só quando grava (em teste nada fica gravado; com puxar_max_os > 1, o bloco desfeito lá embaixo a pega pelo gatilho da versão do plano só enquanto dura)
    if v_real then
      perform pg_advisory_xact_lock(hashtext('agenda_plano'));
    end if;
    -- em teste, as regras do gestor valem só aqui dentro, como no encaixe: a conta é a de quando ele estiver solto (a prontidão e o motor)
    if not v_real then
      perform set_config('agenda.gestor', 'sombra', true);
    end if;
    v_meq := public._agenda_modo_da_equipe();
    v_conv := public._agenda_fala_modo('convite') = 'ligado';
    v_dono := public._agenda_dono(null);

    -- As pessoas e as células de amanhã. ja_vem: tem turno marcado em D e o outro livre, ou é o dono com o dia declarado (7b). disponivel: também quem declarou. Da equipe, a rotina tem de alcançar a
    -- pessoa (contato, telefone: R7.7-6) e a ficha de D ainda não pode ter saído (a pessoa não saberia: a rotina só manda uma). O convite é a mesma regra da ficha (R7.7-8, _agenda_rotina_ficha, AG7-23).
    -- O dono fica fora da regra da rotina: ele não recebe ficha (quem o alcança é o aviso do gestor e o fechamento) e em produção não tem linha de contato. Exigir a rotina dele tirava toda OS que pede o dono.
    select coalesce(array_agg(distinct g.payee_id), '{}'::uuid[]), count(*)::int
      into v_pes, v_cel
      from public.agenda_grade(v_d, v_d, p_hoje) g
      join public.agenda_capacidade(v_d, v_d, p_hoje) k on k.payee_id = g.payee_id and k.dia = g.dia and k.turno = g.turno
      left join public.agenda_equipe_contato ct on ct.payee_id = g.payee_id
     where g.livre
       and (g.eh_dono
            or (ct.recebe_rotina
                and public._agenda_equipe_tem_telefone(g.payee_id)
                and not exists (select 1 from public.agenda_equipe_mensagens m
                                 where m.payee_id = g.payee_id and m.modo = v_meq
                                   and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)))))
       and (exists (select 1 from public.agenda_alocacoes a
                     where a.payee_id = g.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno')
            or ((g.eh_dono or cf.puxar_quem = 'disponivel') and k.origem in ('diarista', 'dono')))
       and not (cf.puxar_quem = 'ja_vem' and v_conv
                and exists (select 1 from public.agenda_equipe_mensagens m
                             where m.payee_id = g.payee_id and m.tipo = 'convite' and m.dia = v_d and m.modo = 'ligado'
                               and m.estado in ('enfileirada', 'sem_resposta', 'respondida')
                               and m.leitura ->> 'convite' is distinct from 'sim'));

    if v_cel > 0 then
      -- A fila: os filtros baratos primeiro; os_prontidao (a conta cara) só em quem passou (R7.8). A classe do motor não entra na ordem: a OS de classe 3 só daria reserva, e aí a simulação recusa.
      for c in
        select k.service_order_id as os, k.numero, k.sinal_pago > 0 as sinal,
               pl.acesso_ok_em, pl.entrada_em, pl.retirada_em, pl.bem_situacao, pl.prioridade_manual
          from public.os_carteira(p_hoje) k
          left join public.os_planejamento pl on pl.service_order_id = k.service_order_id
         where not exists (select 1 from public.agenda_alocacoes a
                            where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
           and coalesce(pl.nao_antes_de <= v_d, true)
           and not coalesce(pl.bem_indisponivel @> v_d, false)
           and (pl.prometido_tipo is null
                -- prometido_ate sempre existe com o tipo (o CHECK prometido_coerente); sem o início, vale o até, como a leitura da 7d
                or (pl.prometido_tipo = 'firme' and coalesce(pl.prometido_de, pl.prometido_ate) = v_d)
                or (pl.prometido_tipo in ('faixa', 'condicional') and v_d between coalesce(pl.prometido_de, pl.prometido_ate) and pl.prometido_ate))
           -- a OS que o dono desfez não volta sozinha (o molde do encaixe)
           and not public._agenda_gestor_desfeito(k.service_order_id, p_agora)
      loop
        -- Conflito 9 e R7.7-2: conta direta, porque _agenda_combinar_da_os devolve [] para a OS sem alocação firme. Sem dado = não puxa.
        v_tipo := public._agenda_local_resolvido(c.os, p_hoje) ->> 'tipo';
        v_lugar := case when v_tipo in ('marina', 'estaleiro', 'patio_parceiro', 'casa_cliente', 'outro')
                        then (c.acesso_ok_em at time zone 'America/Sao_Paulo')::date > p_hoje - cf.cliente_acesso_validade_dias
                        else v_tipo = 'patio_hbr' end;
        if v_tipo in ('patio_hbr', 'patio_parceiro') then
          -- o bem já lá (entrada até hoje, ou a situação dita) e ainda lá em D (a retirada, como a máscara do local: do dia dela em diante)
          v_lugar := v_lugar and (c.entrada_em <= p_hoje or c.bem_situacao = 'patio')
                     and coalesce(c.retirada_em > v_d, true);
        end if;
        continue when not coalesce(v_lugar, false);
        v_pr := public.os_prontidao(c.os, p_hoje);
        continue when v_pr ->> 'estado' is distinct from 'pronta';
        -- O material: o P4 não usa o EST da prontidão (ele já vem com o piso do congelado), então o início pelo material fica por aqui. greatest ignora o nulo de propósito: nulo aqui é "sem essa restrição",
        -- e o dia dito é por onde _agenda_violacoes julga o que já está publicado.
        continue when greatest((v_pr #>> '{material,inicio_mat}')::date, (v_pr #>> '{material,inicio_mat_dito}')::date) > v_d;
        v_fila := v_fila || jsonb_build_object('os', c.os, 'numero', c.numero, 'prio', c.prioridade_manual, 'razao', v_pr -> 'razao_critica',
                                               'sinal', c.sinal, 'aprovada_em', v_pr ->> 'aprovada_em');
      end loop;
      v_cand := jsonb_array_length(v_fila);

      -- Na ordem da fila do motor (agenda_propor, a ordem de v_fila), até puxar_max_os
      for v_e in
        select e from jsonb_array_elements(v_fila) e
         order by (e ->> 'prio')::int nulls last, (e ->> 'razao')::numeric nulls last, (e ->> 'sinal')::boolean desc,
                  (e ->> 'aprovada_em')::date nulls last, e ->> 'numero' collate "C", e ->> 'os'
      loop
        exit when v_n >= cf.puxar_max_os or cardinality(v_pes) = 0;
        v_os := (v_e ->> 'os')::uuid;
        v_rs := jsonb_build_object('puxar', jsonb_build_object('dia', v_d, 'pessoas', to_jsonb(v_pes), 'os', v_os), 'acima_da_carga', true);
        v_mot := null;
        v_ini := null;
        begin
          if jsonb_array_length(v_tst) = 0 then
            v_p := public.agenda_propor('os', v_d, null, array[v_os], v_rs, false, 'vigia', null, p_hoje, p_agora);
          else
            -- Em teste, as OS já puxadas nesta rodada não estão no banco, e a simulação desta não veria o que elas ocupam (o meio-dia de cada pessoa,
            -- a ponta do dono, a frente). Aqui as alocações delas ficam como o agenda_aplicar as deixaria (sai o que cancelam, a fixada com a chave,
            -- como lá; entra o que criam, vigente: o motor e a grade não separam publicada de fixada), a simulação roda e o bloco desfaz tudo, a chave
            -- também; só o resultado dela fica. De verdade, a 1ª já está gravada e a 2ª simulação a lê do banco: este bloco nunca roda (v_tst só
            -- cresce em teste), nem com puxar_max_os = 1.
            begin
              perform set_config('agenda.mexe_fixado', 'on', true);
              update public.agenda_alocacoes a set estado = 'cancelada'
                from jsonb_array_elements(v_tst) i, jsonb_array_elements(i -> 'alocacoes') x
               where i ->> 'op' = 'cancelar' and a.id = (x ->> 'alocacao_id')::uuid;
              perform set_config('agenda.mexe_fixado', 'off', true);
              insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, reserva_de)
              select (i ->> 'os')::uuid, (x ->> 'payee_id')::uuid, (x ->> 'dia')::date, x ->> 'turno', x ->> 'presenca', i ->> 'tipo', 'publicada', i ->> 'reserva_de'
                from jsonb_array_elements(v_tst) i, jsonb_array_elements(i -> 'alocacoes') x
               where i ->> 'op' = 'criar';
              v_p := public.agenda_propor('os', v_d, null, array[v_os], v_rs, false, 'vigia', null, p_hoje, p_agora);
              raise exception 'desfaz' using errcode = 'P0095';
            exception when sqlstate 'P0095' then null;
            end;
          end if;
          v_it := (select i from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i
                    where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = v_os and i ->> 'tipo' <> 'reserva' limit 1);
          v_ini := (select min((a ->> 'dia')::date) from jsonb_array_elements(v_it -> 'alocacoes') a);
          if v_it is null then
            v_mot := 'sem_compromisso';
          elsif v_ini is distinct from v_d then
            v_mot := 'nao_coube_amanha';
          -- a ficha de quem não é o dono, de OS marcada pelo orçamento, presa na janela de veto do 7a-1 (_agenda_ficha_liberada): a pessoa não ficaria sabendo
          elsif v_it ->> 'fonte' = 'orcamento'
                and v_d >= (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date
                and v_d < (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias
                and exists (select 1 from jsonb_array_elements(v_it -> 'alocacoes') a where (a ->> 'payee_id')::uuid is distinct from v_dono) then
            v_mot := 'ficha_presa';
          end if;
          if v_mot is null then
            if v_real then
              v_p := public.agenda_propor('os', v_d, null, array[v_os], v_rs, true, 'vigia', null, p_hoje, p_agora);
              v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, p_hoje, p_agora);
              if not coalesce((v_a ->> 'ok')::boolean, false) then
                v_mot := 'nao_aplicou';
                v_err := v_err + 1;
                perform public.log_app_error('db', 'gestor da agenda, puxar: a proposta não aplicou: ' || coalesce(v_a ->> 'texto', '?'), 'agenda', 'gestor:puxar', 'error',
                                             jsonb_build_object('os', v_os, 'proposta', v_p ->> 'proposta_id', 'violacoes', v_a -> 'violacoes', 'p_hoje', p_hoje, 'p_agora', p_agora));
              end if;
            else
              -- em teste a alocação não existe: os itens que o agenda_aplicar levaria (os não críticos) vão para o bloco desfeito lá em cima, que as próximas simulações leem
              v_tst := v_tst || public._agenda_itens_escolhidos(v_p -> 'itens', null, null);
            end if;
          end if;
          if v_mot is null then
            v_n := v_n + 1;
          end if;
          v_por := v_por || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'resultado', case when v_mot is null then 'puxada' else 'fora' end,
                                               'motivo', v_mot, 'primeiro_dia', v_ini);
        exception when others then
          get stacked diagnostics v_st = returned_sqlstate, v_msg = message_text;
          v_err := v_err + 1;
          perform public.log_app_error('db', format('gestor da agenda, puxar, %s: %s', v_e ->> 'numero', v_msg), 'agenda', 'gestor:puxar', 'error',
                                       jsonb_build_object('os', v_os, 'sqlstate', v_st, 'p_hoje', p_hoje, 'p_agora', p_agora));
          v_por := v_por || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'resultado', 'fora', 'motivo', 'erro', 'primeiro_dia', null);
        end;
      end loop;
    end if;

    if not v_real then
      perform set_config('agenda.gestor', '', true);
    end if;

    v_res := jsonb_build_object('rodou', true, 'modo', v_modo, 'em_teste', not v_real, 'dia', v_d, 'celulas', v_cel, 'candidatas', v_cand,
                                'puxadas', v_n, 'erros', v_err, 'por_os', v_por);
    -- em teste, o diário; sem célula nenhuma não há o que anotar: a contagem da rodada já diz
    if not v_real and v_cel > 0 then
      select g.sombra into v_som from public.agenda_gestor_dia g where g.dia = p_hoje;
      perform public._agenda_gestor_dia_gravar(p_hoje, 'sombra',
                coalesce(v_som, '{}'::jsonb) || jsonb_build_object('puxar', jsonb_build_object('calculado_em', p_agora) || (v_res - 'rodou' - 'em_teste')), p_agora);
    end if;
    return v_res;
  exception when others then
    get stacked diagnostics v_st = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', format('gestor da agenda, puxar: %s', v_msg), 'agenda', 'gestor:puxar', 'error',
                                 jsonb_build_object('sqlstate', v_st, 'p_hoje', p_hoje, 'p_agora', p_agora));
    return jsonb_build_object('rodou', true, 'erros', 1);
  end;
end;
$function$;

comment on function public._agenda_gestor_puxar(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P4b; spec §5.3, R7.7, AG7-31): o passo puxar do job agenda-gestor. A partir de puxar_hora da véspera, a folga que sobrou de amanhã (célula livre de quem já vem: da equipe, com telefone que a rotina alcance, ficha de D ainda por sair e, com o convite ligado, sem convite de D à espera do SIM; o dono, com o dia declarado, sem a rotina) puxa a próxima OS pronta da fila, até puxar_max_os, uma vez por dia útil. A ponta do dono (abrir e fechar) da OS puxada em D vale mesmo com ele fora das pessoas (o validador a aceita). Com o freio ou fora de ligado, só o diário (agenda_gestor_dia.sombra.puxar); aí, com puxar_max_os > 1, a simulação de cada OS seguinte vê as puxadas antes dela na rodada (os itens delas aplicados num bloco que se desfaz), como o de verdade as lê do banco. Erro vai a app_error_logs (agenda, gestor:puxar) e não lança. Nenhum texto novo.';

revoke all on function public._agenda_gestor_puxar(date, timestamptz) from public, anon, authenticated, service_role;
