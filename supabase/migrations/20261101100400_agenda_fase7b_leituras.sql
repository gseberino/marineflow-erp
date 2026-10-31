-- Agenda de Produção, Fase 7, etapa 7b ("os dias de verdade de quem trabalha e a dupla pela tarefa"), pacote P5: as leituras e a saúde —
-- o bloco "Equipe" do cartão da OS (quantas pessoas, a dupla que a tarefa pede ou que você disse, a 2ª pessoa que falta no plano, a
-- dupla dita que espera, a nota do espaço apertado), a dupla no plano e a saúde dos dias da equipe e da dupla.
-- Spec: scratchpad agenda-pesquisa/spec-fase7b.md (§R4.3(g), §R4.4 "o cartão da OS", §R4.6, §R4.7 P5, §5.4, §6.4, §8.3
-- agenda_fase7b_leituras.sql); nomes: fase7-registro.md §1 e §2 (7b P5); respostas do dono: fase7-padroes.md (AG7-03 quem vem sob
-- demanda nunca sozinho; AG7-04 1 pessoa, dupla só onde a tarefa pede; AG7-08 sábado só quando precisar).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (20261031100000 .. 100985 e o dado 100990) e do 7b P1 a P4
-- (20261101100000 .. 100300: os modos da etapa, a disponibilidade, a pergunta da semana e o motor — _agenda_dupla_da_os,
-- agenda_meios_da_os com o dk, _agenda_e_novato, _agenda_e_sob_demanda, _agenda_tecnicos_da_grade).
--
-- ═══ DDL — OK NOMEADO ═══ (2 funções novas, 2 recriadas com as mesmas assinaturas e a porta de leitura de 1 da 7a;
-- nenhuma tabela, coluna, lista ou dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/p5/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem:
-- o montador para se outra migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7b: … -- FASE 7b: fim"
-- (só acréscimo: nenhuma linha de antes muda; tirados os blocos, o corpo é o da origem, byte a byte). Em agenda_saude o bloco fica
-- DENTRO do bloco do gestor da 7a (é ele que monta a saída e volta), marcado "-- FASE 7b (P5…) … -- FASE 7b (P5): fim", sem os
-- dois-pontos depois de "7b": os tiradores dos testes de antes tiram o bloco do gestor inteiro e não o leem como bloco próprio.
--
-- POR QUE: o P4 pôs a dupla por meio-dia no motor (a inferida vai com 1 pessoa quando falta a 2ª, a dita espera), mas ninguém via isso
-- fora do texto da marcação: o cartão da OS dizia só a duração e a presença do dono. E a 7b manda uma pergunta nova à equipe (os dias
-- da semana) e muda quem vai em cada meio-dia (a dupla, o novato e quem vem sob demanda nunca sozinhos, o sábado de manhã, o dono numa
-- vaga): a conferência depois do deploy (agenda_saude) precisa contar o que nunca pode acontecer.
--
-- O QUE MUDA:
--   1. Nova _agenda_dupla_no_plano(p_os, p_hoje): a dupla da OS no plano de verdade — com o dk de agenda_meios_da_os (modo_dupla fora
--      de desligado), as posições da dupla nos meios-dias de turno vigentes da OS (os ni primeiros, os nf últimos, ou todos, contando
--      os já feitos; o meio-dia que não aconteceu não conta), e os de hoje em diante com menos de 2 pessoas (o dono só conta com
--      dk_dono_conta). {fonte, ni, nf, todos, meios, faltam [{dia, turno, onde, pede, tem, reserva, travado, pessoas, desde}]}. É a
--      base do cartão e da saúde (o _agenda_dupla_faltando do P6 pode ser só o filtro desta: fonte regra, fora da reserva).
--   2. Nova _agenda_saude_equipe7b(p_hoje, p_agora): os zeros obrigatórios e os números da etapa (§5.4 e R4.3(g)).
--   3. os_plano_da_os (de 20261029100950): o bloco equipe do cartão (§6.4 e R4.4); com modo_dupla desligado (e na OS concluída,
--      faturada ou cancelada) a chave é nula e o resto do cartão é o de antes.
--   4. agenda_saude (de 20261031100600): a chave equipe_dias (_agenda_saude_equipe7b), com os zeros no ok.
--   5. _agenda_gestor_desfeito (da correção da 7a, 20261031100980; NÃO recriada: só a porta) ganha authenticated e service_role: o
--      foco *agenda gestor* da correção 2 da 7a a lê e recebia "permission denied" quando havia OS de fora (o defeito que o eval K97
--      achou; ver a porta no fim da seção 1).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7b_leituras.sql; registradas em notas-fase77b.md, P5):
--   · _agenda_dupla_no_plano é nova (a spec não a nomeava): o cartão e a saúde precisam dos meios-dias do plano com a dupla sem a 2ª
--     pessoa, e o _agenda_dupla_faltando é do P6 (a saúde do P5 conta o zero dupla_incompleta_com_gente_livre, que a spec pôs aqui).
--   · _agenda_saude_equipe7b e _agenda_dupla_no_plano têm authenticated e service_role (a spec dizia "sem grant"): agenda_saude é
--     invoker e é lida pelo painel (sem o grant, o admin logado receberia 42501, o mesmo que o P3 achou no foco equipe).
--   · O zero dupla_incompleta_com_gente_livre só conta depois de uma rodada do gestor com o passo dupla (P6) que não foi pulado e com o
--     gestor que marca ligado (contagens.dupla da rodada, sem "pulado"; o P6 deixa o resultado do passo ali): antes do P6 é sempre 0.
--   · O cartão em teste com a regra uma_pessoa diz "Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre." (a
--     §6.4, escrita antes da 7a, dizia "Hoje marco 2 pessoas.", que só vale sem a regra).
--   · Com modo_dupla desligado a chave equipe do cartão existe e é nula (a 20261029100950 monta o objeto numa expressão só; o molde da
--     Fase 6, com a linha do fator de campo nula em desligado).
--
-- ORDEM DE LIGAR: nada muda com os 5 modos da 7b desligados (como a migration nasce): o cartão não ganha o bloco, e os zeros da saúde
-- são 0. O dado 20261101100900 (P5, OK nomeado) põe os modos em sombra: o cartão mostra "Em teste: eu marcaria …".
--
-- PROVA: supabase/tests/agenda_fase7b_leituras.sql (na bancada: node scripts/bancada-agenda/rodar.mjs); depois do deploy, só leitura:
-- supabase/tests/agenda_fase7b_pos_deploy.sql.
-- APLICAR (só com o OK do dono, depois das do 7b P1 a P4): npx supabase@2.111.0 db push (ou o roteiro de publicar da etapa,
-- fila-do-dono/fase7b-oks.md).
--
-- DESFAZER: modo_dupla em desligado (o cartão volta ao de antes; os zeros da saúde ficam 0). Para tirar o código: recriar cada função
-- com o corpo da origem (o comentário de cada uma diz qual), a cópia sem os blocos "-- FASE 7b:"; e
--   drop function if exists public._agenda_saude_equipe7b(date, timestamptz), public._agenda_dupla_no_plano(uuid, date);
-- (só depois de recriar agenda_saude e os_plano_da_os sem o bloco, que as chamam).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.
-- Quem recriar depois copia DESTA migration (spec §R4.6, fim): os_plano_da_os (7d P8 `20261103100700`) e agenda_saude (7d P8).

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- A dupla da OS no plano de verdade (spec §6.4, R4.3(a), R4.3(g), R4.4): com o dk de agenda_meios_da_os (só existe com modo_dupla fora
-- de desligado, sem a equipe dita e com 1 pessoa por serviço), as posições da dupla nos meios-dias de turno vigentes da OS — os ni
-- primeiros e os nf últimos, ou todos, contando os que já foram feitos (o "não aconteceu" não conta) — e, de hoje em diante, os que
-- têm menos de 2 pessoas (o dono só conta como a 2ª pessoa com dk_dono_conta; abrir e fechar nunca contam: só o turno).
create or replace function public._agenda_dupla_no_plano(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_m     jsonb;
  v_dono  uuid := public._agenda_dono(null);
  v_ni    int;
  v_nf    int;
  v_todos boolean;
  v_conta boolean;
  v_n     int;
  v_out   jsonb := '[]'::jsonb;
  r       record;
begin
  if p_os is null or p_hoje is null then
    raise exception '_agenda_dupla_no_plano: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  v_m := public.agenda_meios_da_os(p_os, p_hoje);
  if not coalesce((v_m ->> 'ok')::boolean, false) or not v_m ? 'dk' then
    return jsonb_build_object('fonte', null, 'ni', 0, 'nf', 0, 'todos', false, 'meios', 0, 'faltam', '[]'::jsonb);
  end if;
  v_ni := coalesce((v_m #>> '{dupla,ni}')::int, 0);
  v_nf := coalesce((v_m #>> '{dupla,nf}')::int, 0);
  v_todos := coalesce((v_m #>> '{dupla,todos}')::boolean, false);
  v_conta := coalesce((v_m ->> 'dk_dono_conta')::boolean, true);
  -- os meios-dias de turno do plano da OS (vigentes; o que não aconteceu fica de fora), na ordem
  select count(*)::int into v_n
    from (select distinct a.dia, a.turno from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.presenca = 'turno'
             and a.resultado is distinct from 'nao_cumprido') x;
  for r in
    select x.dia, x.turno, x.k, x.tem, x.reserva, x.pessoas, x.desde
      from (select a.dia, a.turno, row_number() over (order by a.dia, a.turno) as k,
                   count(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono or v_conta)::int as tem,
                   bool_and(a.tipo = 'reserva') as reserva,
                   array_agg(distinct a.payee_id) as pessoas,
                   min(a.criado_em) as desde
              from public.agenda_alocacoes a
             where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.presenca = 'turno'
               and a.resultado is distinct from 'nao_cumprido'
             group by a.dia, a.turno) x
     order by x.k
  loop
    continue when r.dia < p_hoje or r.tem >= 2;
    continue when not (v_todos or r.k <= v_ni or r.k > v_n - v_nf);
    v_out := v_out || jsonb_build_object(
      'dia', r.dia, 'turno', r.turno, 'onde', case when v_todos then 'todos' when r.k <= v_ni then 'inicio' else 'fim' end,
      'pede', 2, 'tem', r.tem, 'reserva', r.reserva,
      'travado', public._agenda_dia_avisado(null, p_os, r.dia) is not null
                 or exists (select 1 from unnest(r.pessoas) q where public._agenda_dia_avisado(q, null, r.dia) is not null),
      'pessoas', to_jsonb(r.pessoas), 'desde', r.desde);
  end loop;
  return jsonb_build_object('fonte', v_m #>> '{dupla,fonte}', 'ni', v_ni, 'nf', v_nf, 'todos', v_todos, 'meios', v_n, 'faltam', v_out);
end;
$function$;

comment on function public._agenda_dupla_no_plano(uuid, date) is
  'Agenda de Produção (Fase 7b, P5; §6.4, R4.3(a)(g), R4.4): a dupla da OS no plano de verdade — com o dk de agenda_meios_da_os (modo_dupla fora de desligado, sem a equipe dita e com 1 pessoa por serviço; sem ele, faltam vazio), as posições da dupla nos meios-dias de turno vigentes da OS (os ni primeiros e os nf últimos, ou todos, contando os já feitos; o "não aconteceu" fica de fora) e, de hoje em diante, os que têm menos de 2 pessoas (o dono só conta com dk_dono_conta; abrir e fechar nunca contam). {fonte (dono|regra), ni, nf, todos, meios, faltam [{dia, turno, onde (inicio|fim|todos), pede 2, tem, reserva, travado (o dia já dito ao cliente ou à equipe: _agenda_dia_avisado), pessoas, desde (a alocação mais antiga do meio-dia)}]}. O cartão (os_plano_da_os) e a saúde (_agenda_saude_equipe7b) leem daqui. STABLE, invoker; authenticated e service_role.';

-- A saúde dos dias da equipe e da dupla (spec §5.4 e R4.3(g)): os zeros obrigatórios (entram no ok de agenda_saude) e os números.
create or replace function public._agenda_saude_equipe7b(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_dono uuid := public._agenda_dono(null);
  v_pl   jsonb := '{}'::jsonb;
  v_rd   timestamptz;
  v_sf   date;
  v_sp   date := date_trunc('week', p_hoje)::date - 7;
  v_z    jsonb;
  v_n    jsonb;
  v_per  int;
  v_res  int;
  v_ult  record;
  o      uuid;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_saude_equipe7b: sem o dia de hoje ou a hora' using errcode = '22004';
  end if;
  -- a dupla no plano de cada OS com meio-dia de turno vigente de hoje em diante (só com modo_dupla fora de desligado: sem ele, não há dk)
  if cf.modo_dupla <> 'desligado' then
    for o in select distinct a.service_order_id from public.agenda_alocacoes a
              where a.estado in ('publicada', 'fixada') and a.presenca = 'turno' and a.dia >= p_hoje
              order by 1 loop
      v_pl := v_pl || jsonb_build_object(o::text, public._agenda_dupla_no_plano(o, p_hoje));
    end loop;
  end if;
  -- a última rodada do gestor com o passo dupla (o do P6, que completa a dupla) que não foi pulado, com o gestor que marca ligado
  select max(r.p_agora) into v_rd
    from public.agenda_vigia_rodadas r
   where r.rotina = 'gestor' and r.p_agora <= p_agora and r.contagens ? 'dupla'
     and jsonb_typeof(r.contagens -> 'dupla') = 'object' and not (r.contagens -> 'dupla') ? 'pulado'
     and r.contagens #>> '{modos,marcar}' = 'ligado';

  v_z := jsonb_build_object(
    -- a pergunta dos dias à equipe que saiu fora da janela ou no domingo (enfileirada: marcada fora, ou a fila marcou ou mandou fora)
    'dias_fora_da_janela', (select count(*) from public.agenda_equipe_mensagens m
                             where m.tipo = 'dias' and m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
                               and (public._agenda_equipe_fora_da_janela('dias', m.enviar_em, m.enviar_em) is not null
                                    or exists (select 1 from public.whatsapp_send_queue q
                                                where q.source = 'agenda-equipe' and q.source_ref_id = m.id
                                                  and (public._agenda_equipe_fora_da_janela('dias', m.enviar_em, q.scheduled_for) is not null
                                                       or (q.sent_at is not null
                                                           and public._agenda_equipe_fora_da_janela('dias', m.enviar_em, q.sent_at) is not null))))),
    -- mais de uma pergunta dos dias por pessoa e semana
    'dias_duas_na_semana', (select count(*) from (select m.payee_id, date_trunc('week', m.dia) as s
                                                     from public.agenda_equipe_mensagens m
                                                    where m.tipo = 'dias' and m.modo = 'ligado' and m.estado <> 'recusada'
                                                    group by 1, 2 having count(*) > 1) t),
    -- a pessoa com mais de equipe_proativas_dia_max mensagens começadas pelo sistema num dia em que a pergunta dos dias saiu
    'dia_acima_do_teto', (select count(*) from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as d, count(*) as n
                                                   from public.agenda_equipe_mensagens m
                                                  where m.modo = 'ligado' and m.tipo <> 'resposta'
                                                    and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                                  group by 1, 2) t
                           where t.n > cf.equipe_proativas_dia_max
                             and exists (select 1 from public.agenda_equipe_mensagens d
                                          where d.payee_id = t.payee_id and d.tipo = 'dias' and d.modo = 'ligado'
                                            and d.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                            and (d.enviar_em at time zone 'America/Sao_Paulo')::date = t.d)),
    -- a ficha recusada pelo teto num dia em que a pergunta dos dias saiu para a mesma pessoa (a pergunta nunca toma a vaga da ficha)
    'ficha_recusada_por_teto_com_dias', (select count(*) from public.agenda_equipe_mensagens f
                                          where f.tipo = 'ficha' and f.modo = 'ligado' and f.estado = 'recusada' and f.recusa_motivo = 'teto'
                                            and exists (select 1 from public.agenda_equipe_mensagens d
                                                         where d.payee_id = f.payee_id and d.tipo = 'dias' and d.modo = 'ligado'
                                                           and d.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                                           and (d.enviar_em at time zone 'America/Sao_Paulo')::date
                                                               = (f.enviar_em at time zone 'America/Sao_Paulo')::date)),
    -- (R4.3(g)) a dupla DITA pelo dono com menos pessoas que o pedido num meio-dia do plano (fora da reserva), com modo_dupla ligado
    'dupla_com_uma_pessoa', case when cf.modo_dupla <> 'ligado' then 0 else
      (select count(*) from jsonb_each(v_pl) p cross join lateral jsonb_array_elements(p.value -> 'faltam') e
        where p.value ->> 'fonte' = 'dono' and not coalesce((e ->> 'reserva')::boolean, false)) end,
    -- (R4.3(g)) o meio-dia da dupla inferida sem a 2ª pessoa, de amanhã em diante e fora da zona travada, com alguém da grade (fora o
    -- dono) livre nele, que já existia na última rodada do passo dupla do gestor (P6) com modo_dupla ligado
    'dupla_incompleta_com_gente_livre', case when cf.modo_dupla <> 'ligado' or v_rd is null then 0 else
      (select count(*) from jsonb_each(v_pl) p cross join lateral jsonb_array_elements(p.value -> 'faltam') e
        where p.value ->> 'fonte' = 'regra' and not coalesce((e ->> 'reserva')::boolean, false)
          and not coalesce((e ->> 'travado')::boolean, false) and (e ->> 'dia')::date > p_hoje
          and (e ->> 'desde')::timestamptz < v_rd
          and exists (select 1 from public.agenda_capacidade((e ->> 'dia')::date, (e ->> 'dia')::date, p_hoje) k
                       where not k.eh_dono and k.situacao = 'livre' and k.turno = e ->> 'turno'
                         and not (to_jsonb(k.payee_id::text) <@ (e -> 'pessoas'))
                         and not exists (select 1 from public.agenda_alocacoes a
                                          where a.payee_id = k.payee_id and a.dia = k.dia and a.turno = k.turno
                                            and a.estado in ('publicada', 'fixada') and a.presenca = 'turno'))) end,
    -- o meio-dia do motor só com quem nunca fica sozinho (o novato; quem vem sob demanda, sem sob_demanda_sozinho), sem outra pessoa
    -- nem o dono no turno, com modo_dupla fora de desligado (a regra do motor)
    'novato_sozinho', case when cf.modo_dupla = 'desligado' or cf.novato_sozinho then 0 else
      (select count(*) from (select a.service_order_id, a.dia, a.turno,
                                    bool_and(a.payee_id is distinct from v_dono
                                             and (public._agenda_e_novato(a.payee_id, a.dia)
                                                  or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(a.payee_id, a.dia)))) as so_eles
                               from public.agenda_alocacoes a
                              where a.estado in ('publicada', 'fixada') and a.presenca = 'turno' and a.origem = 'motor' and a.dia >= p_hoje
                              group by 1, 2, 3) t
        where t.so_eles) end,
    -- (so_prazo) o sábado do motor em OS sem prazo firme (precisa_ate ou o prometido firme), com modo_sabado ligado
    'sabado_sem_prazo', case when cf.modo_sabado <> 'ligado' or cf.sabado_manha <> 'so_prazo' then 0 else
      (select count(*) from public.agenda_alocacoes a left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
        where a.estado in ('publicada', 'fixada') and a.presenca = 'turno' and a.origem = 'motor' and a.dia >= p_hoje
          and extract(isodow from a.dia) = 6 and pl.precisa_ate is null
          and not coalesce(pl.prometido_tipo = 'firme' and pl.prometido_ate is not null, false)) end,
    -- o sábado à tarde do motor (nunca: só a manhã)
    'sabado_tarde', (select count(*) from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.origem = 'motor' and a.dia >= p_hoje
                        and extract(isodow from a.dia) = 6 and a.turno = 'tarde'),
    -- o dono num meio-dia de turno do motor em que a presença dele não é o turno (sempre, ou na equipe dita), sem dono_como_tecnico
    'dono_em_vaga_sem_ok', case when cf.dono_como_tecnico then 0 else
      (select count(*) from public.agenda_alocacoes a
        where a.estado in ('publicada', 'fixada') and a.presenca = 'turno' and a.origem = 'motor' and a.dia >= p_hoje
          and a.payee_id = v_dono
          and not coalesce((public.agenda_meios_da_os(a.service_order_id, p_hoje) -> 'dono_turno' ->> a.turno)::boolean, false)) end,
    -- a resposta com os dias (ou "nenhum") que mudou algo e não deixou linha de disponibilidade com o id da pergunta
    'resposta_sem_gravar', (select count(*) from public.agenda_equipe_mensagens m
                             where m.tipo = 'dias' and m.estado = 'respondida' and m.leitura ->> 'tipo' in ('dias', 'nenhum')
                               and coalesce((m.leitura ->> 'mudou')::boolean, false)
                               and not exists (select 1 from public.agenda_disponibilidade d where d.mensagem_id = m.id)));

  -- os números: a última semana perguntada já fechada (o prazo da quinta que a planeja passou), as adiadas pelo teto, a dupla, o sábado
  -- e a semana passada por pessoa (meios-dias declarados × usados × cumpridos)
  select max(m.dia) into v_sf
    from public.agenda_equipe_mensagens m
   where m.tipo = 'dias' and m.modo = 'ligado'
     and (((m.dia - 7 + (cf.dia_do_plano - 1)) + cf.hora_do_plano) - cf.equipe_dias_fechar_antes) at time zone 'America/Sao_Paulo' <= p_agora;
  select count(*) filter (where m.estado in ('enfileirada', 'respondida', 'sem_resposta'))::int,
         count(*) filter (where m.estado = 'respondida')::int
    into v_per, v_res
    from public.agenda_equipe_mensagens m where m.tipo = 'dias' and m.modo = 'ligado' and m.dia = v_sf;
  v_n := jsonb_build_object(
    'semana_fechada', v_sf, 'perguntadas', coalesce(v_per, 0), 'respondidas', coalesce(v_res, 0),
    'resposta_pct', case when coalesce(v_per, 0) > 0 then round(100 * v_res::numeric / v_per) end,
    'adiadas_7d', (select coalesce(sum((r.contagens #>> '{perguntar,adiada}')::int), 0) from public.agenda_vigia_rodadas r
                    where r.rotina = 'equipe_semana' and r.p_agora > p_agora - interval '7 days' and r.p_agora <= p_agora),
    'dupla_esperando_ajudante', (select count(*) from jsonb_each(v_pl) p
                                  where p.value ->> 'fonte' = 'regra' and jsonb_array_length(p.value -> 'faltam') > 0),
    'duplas', (select jsonb_build_object('inferidas', count(*) filter (where x.d ->> 'fonte' = 'regra'),
                                         'ditas', count(*) filter (where x.d ->> 'fonte' = 'dono'
                                                                     and (coalesce((x.d ->> 'todos')::boolean, false)
                                                                          or coalesce((x.d ->> 'inicio')::int, 0) > 0
                                                                          or coalesce((x.d ->> 'fim')::int, 0) > 0)))
                 from (select public._agenda_dupla_da_os(k.service_order_id) as d from public.os_carteira(p_hoje) k) x),
    'sabados', jsonb_build_object(
      'usados_28d', (select count(distinct a.dia) from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.presenca = 'turno' and a.origem = 'motor'
                        and extract(isodow from a.dia) = 6 and a.dia between p_hoje - 28 and p_hoje + 7 * cf.horizonte_semanas),
      'em_teste_7d', (select count(*) from public.agenda_propostas pr
                        cross join lateral jsonb_array_elements_text(coalesce(pr.textos -> 'em_teste', '[]'::jsonb)) t(x)
                       where pr.criada_em > p_agora - interval '7 days' and pr.criada_em <= p_agora and t.x like '%sáb % de manhã%')),
    'semana_passada', jsonb_build_object('seg', v_sp, 'pessoas', coalesce((
      select jsonb_agg(jsonb_build_object('pessoa', c.pessoa, 'dono', c.eh_dono, 'declarada', trim_scale(c.decl),
                                          'usada', coalesce(u.usada, 0), 'cumprida', trim_scale(coalesce(u.cumprida, 0)))
                       order by c.eh_dono, c.pessoa)
        from (select k.payee_id, k.pessoa, bool_or(k.eh_dono) as eh_dono, sum(k.meios_esperados) as decl
                from public.agenda_capacidade(v_sp, v_sp + 5, p_hoje) k
               group by k.payee_id, k.pessoa having sum(k.meios_esperados) > 0) c
        left join (select a.payee_id, count(distinct (a.dia, a.turno))::int as usada,
                          sum(case a.resultado when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end) as cumprida
                     from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.presenca = 'turno' and a.tipo <> 'reserva'
                      and a.dia between v_sp and v_sp + 5
                    group by a.payee_id) u on u.payee_id = c.payee_id), '[]'::jsonb)));

  select max(x.p_agora) as ultima, count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24
    into v_ult from public.agenda_vigia_rodadas x where x.rotina = 'equipe_semana';
  return jsonb_build_object(
    'modos', jsonb_build_object('dias', cf.modo_dias, 'dupla', cf.modo_dupla, 'sabado', cf.modo_sabado, 'cadastro', cf.modo_cadastro,
                                'chamar', cf.modo_chamar),
    'ultima_rodada', v_ult.ultima, 'rodadas_24h', coalesce(v_ult.n24, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'equipe_semana:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', not exists (select 1 from jsonb_each(v_z) z where (z.value)::text <> '0'),
    'numeros', v_n) || v_z;
end;
$function$;

comment on function public._agenda_saude_equipe7b(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P5; §5.4, R4.3(g)): a saúde dos dias da equipe e da dupla, a chave equipe_dias de agenda_saude — {modos (dias, dupla, sabado, cadastro, chamar), ultima_rodada e rodadas_24h da semana da equipe (rotina equipe_semana), erros_24h (app_error_logs context agenda, action equipe_semana:%), zeros_ok, numeros {semana_fechada (a última semana perguntada cujo prazo passou), perguntadas, respondidas, resposta_pct, adiadas_7d (as perguntas adiadas pelo teto do dia), dupla_esperando_ajudante (as OS da dupla inferida com meio-dia sem a 2ª pessoa no plano), duplas {inferidas, ditas} (a carteira), sabados {usados_28d, em_teste_7d}, semana_passada {seg, pessoas [{pessoa, dono, declarada, usada, cumprida}] (meios-dias)}}} || os zeros obrigatórios: dias_fora_da_janela (a pergunta dos dias enfileirada fora da janela ou no domingo, também a que a fila marcou ou mandou fora), dias_duas_na_semana, dia_acima_do_teto (mais de equipe_proativas_dia_max mensagens começadas num dia em que a dos dias saiu), ficha_recusada_por_teto_com_dias, dupla_com_uma_pessoa (modo_dupla ligado: a dupla DITA com menos pessoas que o pedido num meio-dia do plano fora da reserva), dupla_incompleta_com_gente_livre (modo_dupla ligado e depois de uma rodada do gestor com o passo dupla, do P6, não pulado e com marcar ligado: o meio-dia da dupla inferida sem a 2ª pessoa, de amanhã em diante, fora da zona travada e já no plano naquela rodada, com alguém da grade fora o dono livre nele), novato_sozinho (modo_dupla fora de desligado: o meio-dia do motor só com novato ou quem vem sob demanda), sabado_sem_prazo (modo_sabado ligado e so_prazo: o sábado do motor em OS sem prazo firme), sabado_tarde, dono_em_vaga_sem_ok (sem dono_como_tecnico: o dono num meio-dia de turno do motor fora da presença dele), resposta_sem_gravar (a resposta dos dias que mudou algo sem linha de disponibilidade com o id da pergunta). STABLE, invoker; authenticated e service_role (agenda_saude, que o painel lê, a chama).';

revoke all on function public._agenda_dupla_no_plano(uuid, date) from public, anon;
grant execute on function public._agenda_dupla_no_plano(uuid, date) to authenticated, service_role;
revoke all on function public._agenda_saude_equipe7b(date, timestamptz) from public, anon;
grant execute on function public._agenda_saude_equipe7b(date, timestamptz) to authenticated, service_role;

-- (o defeito da correção 2 da 7a que o eval K97 achou) o foco *agenda gestor* — _agenda_ver_gestor, a leitura invoker de
-- 20261031100985, que agenda_ver (invoker) chama para o painel (authenticated) e o assistente (service_role) — lê
-- _agenda_gestor_desfeito para dizer "você desfez" de quem ficou de fora, e ela estava sem grant a ninguém (era só dos passos da
-- rodada, definer): sempre que uma OS ficava de fora numa montagem ligada dos últimos 8 dias, *agenda gestor* respondia
-- "permission denied for function _agenda_gestor_desfeito". Ela só lê (STABLE, invoker; a RLS de quem lê vale): passa a ter as
-- portas de leitura, authenticated e service_role; nunca anon. (Os testes da 7a que fixavam "ninguém" aceitam a leitura com esta
-- migration aplicada.)
revoke all on function public._agenda_gestor_desfeito(uuid, timestamptz) from public, anon;
grant execute on function public._agenda_gestor_desfeito(uuid, timestamptz) to authenticated, service_role;

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7b:") ─────────────────────────
-- Fora dos blocos nenhuma linha muda (o L5 de supabase/tests/agenda_fase7b_leituras.sql confere). Quem recriar de novo qualquer uma
-- delas copia DESTA migration (spec-fase7b §R4.6: o 7d P8 copia os_plano_da_os e agenda_saude daqui).

-- os_plano_da_os (de 20261029100950_agenda_fase6_correcao_textos.sql)
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
  -- FASE 7b: (7b P5) o bloco "Equipe" do cartão: o molde, a dupla da OS, a dupla no plano, quem está na grade, a classe, o "fora" da
  -- última montagem, as partes do texto
  v_7b_modo  text;
  v_7b_eq    jsonb;
  v_7b_m     jsonb;
  v_7b_d     jsonb;
  v_7b_pl    jsonb;
  v_7b_tec   text[];
  v_7b_tf    text;
  v_7b_cl    jsonb;
  v_7b_fora  jsonb;
  v_7b_pes   int;
  v_7b_txt   text;
  v_7b_esp   boolean := false;
  v_7b_fi    jsonb;
  v_7b_ff    jsonb;
  v_7b_ft    jsonb;
  v_7b_partes text[] := '{}';
  v_7b_nomes text[];
  -- FASE 7b: fim
begin
  if p_os is null or p_hoje is null then
    raise exception 'os_plano_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
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
        raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
      end if;
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
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

  -- FASE 7b: (7b P5, §5.4, §6.4, R4.3, R4.4) o bloco "Equipe" do cartão — só com modo_dupla fora de desligado e na OS que ainda vai
  -- ser feita (desligado, ou a OS concluída, faturada ou cancelada: nulo, e o resto do cartão é o de antes). Quantas pessoas o serviço
  -- pede (pessoas: as da sugestão, ou 2 na dupla o tempo todo; com a equipe dita, as que você disse), a dupla da OS (_agenda_dupla_da_os:
  -- a que a tarefa pede, suposição minha, ou a que você disse), as notas (o espaço apertado), os meios-dias do plano em que a dupla
  -- está sem a 2ª pessoa (falta, de _agenda_dupla_no_plano), a dupla dita que espera a 2ª pessoa (espera: a classe 4 dupla, ou o
  -- "fora" dupla da última montagem que citou a OS, sem compromisso dela de hoje em diante) e o texto: "1 pessoa; nos 2 primeiros
  -- meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe).", "Em dupla o tempo todo
  -- (você disse) — espero a 2ª pessoa: só Alex está na equipe.", em teste "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros
  -- meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre."
  v_7b_modo := (public._agenda_cfg()).modo_dupla;
  if v_7b_modo <> 'desligado' and so.status not in ('completed', 'invoiced', 'cancelled') then
    v_7b_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_7b_d := public._agenda_dupla_da_os(p_os);
    v_7b_pl := public._agenda_dupla_no_plano(p_os, p_hoje);
    v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
    v_7b_tf := case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias'
                    else public._agenda_tecnicos_frase(v_7b_tec) end;
    v_7b_pes := case when coalesce((v_7b_m ->> 'equipe_dita')::boolean, false)
                       then greatest(coalesce((v_7b_m #>> '{por_turno,manha,desejado}')::int, 0),
                                     coalesce((v_7b_m #>> '{por_turno,tarde,desejado}')::int, 0))
                     when coalesce((v_7b_d ->> 'todos')::boolean, false) then 2
                     else coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) end;
    v_7b_fi := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'inicio'), '[]'::jsonb);
    v_7b_ff := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'fim'), '[]'::jsonb);
    v_7b_ft := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'todos'), '[]'::jsonb);
    -- a dupla dita que espera a 2ª pessoa: a classe 4 dupla (a grade com menos técnicos do que ela pede), ou a que só passou pela régua
    -- com quem vem sob demanda e ficou no "fora" dupla da última montagem que citou a OS (R4.3(c)), sem compromisso dela de hoje em diante
    if v_7b_d ->> 'fonte' = 'dono' and not coalesce((v_7b_m ->> 'equipe_dita')::boolean, false) then
      v_7b_cl := public._agenda_classe_da_os(p, v_7b_m, p_hoje,
                   exists (select 1 from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado = 'fixada' and a.dia >= p_hoje),
                   false);
      if (v_7b_cl ->> 'classe')::int = 4 and v_7b_cl ->> 'motivo' = 'dupla' then
        v_7b_esp := true;
        v_7b_txt := rtrim(v_7b_d ->> 'texto', '.') || ' — espero a 2ª pessoa: ' || public._agenda_tecnicos_frase(v_7b_tec) || '.';
      elsif not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
                          and a.tipo <> 'reserva' and a.dia >= p_hoje) then
        select x.f into v_7b_fora
          from (select pr.criada_em, pr.id, (select f from jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                                              where f ->> 'os' = p_os::text limit 1) as f,
                       exists (select 1 from jsonb_array_elements(coalesce(pr.itens, '[]'::jsonb)) i where i ->> 'os' = p_os::text) as no_plano
                  from public.agenda_propostas pr
                 where (pr.criada_em at time zone 'America/Sao_Paulo')::date <= p_hoje) x
         where x.f is not null or x.no_plano
         order by x.criada_em desc, x.id desc limit 1;
        if v_7b_fora ->> 'motivo' = 'dupla' then
          v_7b_esp := true;
          v_7b_txt := rtrim(v_7b_d ->> 'texto', '.') || ' — espero a 2ª pessoa: '
                      || case when position('): ' in v_7b_fora ->> 'texto') > 0
                              then substr(v_7b_fora ->> 'texto', position('): ' in v_7b_fora ->> 'texto') + 3)
                              else v_7b_fora ->> 'texto' end;
        end if;
      end if;
    end if;
    if v_7b_txt is null then
      if coalesce((v_7b_m ->> 'equipe_dita')::boolean, false) then
        v_7b_nomes := array(select y.nome from (select distinct on (x ->> 'payee_id') x ->> 'payee_id' as id, x ->> 'nome' as nome
                                                 from (select jsonb_array_elements(coalesce(v_7b_m #> '{por_turno,manha,pessoas}', '[]'::jsonb)) x
                                                       union all
                                                       select jsonb_array_elements(coalesce(v_7b_m #> '{por_turno,tarde,pessoas}', '[]'::jsonb))) z
                                                order by x ->> 'payee_id') y order by y.nome);
        v_7b_txt := format('Quem vai: %s (você disse).',
                           public._agenda_lista(case when v_7b_m ->> 'presenca' = 'equipe' then array['você'] else '{}'::text[] end || v_7b_nomes));
      elsif v_7b_d ->> 'fonte' = 'dono' then
        v_7b_txt := case when jsonb_array_length(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) = 0 then v_7b_d ->> 'texto'
                         else rtrim(v_7b_d ->> 'texto', '.') || ' — falta a 2ª pessoa em '
                              || public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_pl -> 'faltam') e))
                              || ' (' || v_7b_tf || ').' end;
      elsif v_7b_modo = 'sombra' and v_7b_d ->> 'fonte' = 'regra' then
        v_7b_txt := replace(replace(v_7b_d ->> 'texto', ' — suposição minha.', ''), '1 pessoa; ', '1 pessoa, ');
        v_7b_txt := 'Em teste: eu marcaria ' || lower(left(v_7b_txt, 1)) || substr(v_7b_txt, 2) || '.'
                    || case when coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) >= 2 then ' Hoje marco 2 pessoas.'
                            else ' Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre.' end;
      elsif v_7b_modo = 'sombra' and coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) >= 2 then
        v_7b_txt := 'Em teste: eu marcaria 1 pessoa. Hoje marco 2 pessoas.';
      elsif v_7b_d ->> 'fonte' = 'regra' and jsonb_array_length(v_7b_ft) > 0 then
        v_7b_txt := format('1 pessoa; o serviço todo pede 2 (%s) — falta a 2ª pessoa em %s (%s).',
                           coalesce((select e ->> 'rotulo' from jsonb_array_elements(v_7b_d -> 'motivos') e where e ->> 'onde' = 'todos' limit 1),
                                    'o orçamento previu 2 técnicos'),
                           public._agenda_plural(jsonb_array_length(v_7b_ft), 'meio-dia', 'meios-dias'), v_7b_tf);
      elsif v_7b_d ->> 'fonte' = 'regra' and jsonb_array_length(v_7b_fi) + jsonb_array_length(v_7b_ff) > 0 then
        if jsonb_array_length(v_7b_fi) > 0 then
          v_7b_partes := v_7b_partes || format('%s (%s) %s',
            case when jsonb_array_length(v_7b_fi) = coalesce((v_7b_pl ->> 'ni')::int, 0)
                   then case when jsonb_array_length(v_7b_fi) = 1 then 'no primeiro meio-dia'
                             else format('nos %s primeiros meios-dias', jsonb_array_length(v_7b_fi)) end
                 else format('em %s dos %s primeiros meios-dias', jsonb_array_length(v_7b_fi), v_7b_pl ->> 'ni') end,
            public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_fi) e)),
            coalesce(nullif(public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'frase' from jsonb_array_elements(v_7b_d -> 'motivos') e
                                                        where e ->> 'onde' = 'inicio' order by e ->> 'motivo')), ''), 'a tarefa'));
        end if;
        if jsonb_array_length(v_7b_ff) > 0 then
          v_7b_partes := v_7b_partes || format('%s (%s) %s',
            case when jsonb_array_length(v_7b_ff) = coalesce((v_7b_pl ->> 'nf')::int, 0)
                   then case when jsonb_array_length(v_7b_ff) = 1 then 'no último meio-dia'
                             else format('nos %s últimos meios-dias', jsonb_array_length(v_7b_ff)) end
                 else format('em %s dos %s últimos meios-dias', jsonb_array_length(v_7b_ff), v_7b_pl ->> 'nf') end,
            public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_ff) e)),
            coalesce(nullif(public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'frase' from jsonb_array_elements(v_7b_d -> 'motivos') e
                                                        where e ->> 'onde' = 'fim' order by e ->> 'motivo')), ''), 'a tarefa'));
        end if;
        v_7b_txt := '1 pessoa; ' || public._agenda_lista(v_7b_partes)
                    || case when cardinality(v_7b_partes) > 1 then ' pedem 2' else ' pede 2' end || ' — falta a 2ª pessoa (' || v_7b_tf || ').';
      else
        v_7b_txt := v_7b_d ->> 'texto';
      end if;
    end if;
    v_7b_eq := jsonb_build_object(
      'pessoas', v_7b_pes,
      'dupla', jsonb_build_object('inicio', v_7b_d -> 'inicio', 'fim', v_7b_d -> 'fim', 'todos', v_7b_d -> 'todos',
                                  'fonte', v_7b_d ->> 'fonte', 'texto', v_7b_d ->> 'texto'),
      'notas', coalesce((select jsonb_agg(n ->> 'texto' order by o) from jsonb_array_elements(coalesce(v_7b_d -> 'notas', '[]'::jsonb))
                                                                   with ordinality t(n, o)), '[]'::jsonb),
      'modo', v_7b_modo,
      'falta', coalesce((select jsonb_agg(jsonb_build_object('dia', e -> 'dia', 'turno', e -> 'turno', 'onde', e -> 'onde') order by o)
                           from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb),
      'espera', v_7b_esp,
      'texto', v_7b_txt);
  end if;
  -- FASE 7b: fim
  return jsonb_build_object(
    -- FASE 5: o bloco "Cliente" do cartão (o que foi dito, a confirmação, as mensagens desta OS e o que espera você;
    -- _agenda_cliente_da_os). null sem o cliente.
    'cliente', public._agenda_cliente_da_os(p_os, p_hoje),
    -- FASE 5: fim
    -- FASE 7b: (7b P5) o bloco "Equipe" do cartão (nulo com modo_dupla desligado e na OS concluída, faturada ou cancelada)
    'equipe', v_7b_eq,
    -- FASE 7b: fim
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
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 6 (P8): duracao.campo = a linha do fator de campo da classe da OS (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).") — nula com modo_aprendizado desligado e na OS concluída, faturada ou cancelada; presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em motorhome"; nulo sem ela), e o texto "Você fica o tempo todo (pelo que medi: …)". CORREÇÃO FASE 6 (C1, item 3): com a presença guardada na 1ª publicação, o texto diz "(pelo que medi quando planejei: …)". CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501. FASE 7b (P5, §5.4, §6.4, R4.3, R4.4): o bloco equipe {pessoas (as que o serviço pede fora da dupla: as da sugestão, 2 na dupla o tempo todo, as da equipe dita), dupla {inicio, fim, todos, fonte dono|regra|nenhuma, texto} (_agenda_dupla_da_os), notas [texto] (o espaço apertado: "Atenção: casa de máquinas — confira se precisa de duas pessoas."), modo, falta [{dia, turno, onde}] (os meios-dias do plano em que a dupla está sem a 2ª pessoa, de hoje em diante: _agenda_dupla_no_plano), espera (a dupla dita que espera a 2ª pessoa: a classe 4 dupla, ou o "fora" dupla da última montagem que citou a OS, sem compromisso dela de hoje em diante), texto} — o texto: a regra "1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha."; com a 2ª pessoa faltando no plano "1 pessoa; nos 2 primeiros meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe)." (o tempo todo: "1 pessoa; o serviço todo pede 2 (o orçamento previu 2 técnicos) — falta a 2ª pessoa em 12 meios-dias (só Alex está na equipe)."); a dita "Em dupla nos 2 primeiros meios-dias (você disse)." e, esperando, "Em dupla o tempo todo (você disse) — espero a 2ª pessoa: só Alex está na equipe."; a equipe dita "Quem vai: Roberto e João (você disse)."; em teste a regra "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre." (sem a regra uma_pessoa: "Hoje marco 2 pessoas."); nada "1 pessoa.". Nulo com modo_dupla desligado e na OS concluída, faturada ou cancelada (o resto do cartão é o de antes, byte a byte).';

-- agenda_saude (de 20261031100600_agenda_fase7a_rodada.sql)
create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
  -- FASE 6: o aprendizado
  v_arod    record;
  v_apeq    int;
  v_afora   int;
  v_agrande int;
  v_aatras  int;
  v_asemcl  int;
  v_afat    int;
  v_amet    jsonb;
  v_zeros6  boolean;
  v_apr     jsonb;
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros de antes do aprendizado (para o ok sair com as janelas de agenda_config)
  v_z4_antes boolean;
  -- FASE 7: (7a P7) o gestor da agenda
  v_ges     jsonb;
  v_gz      jsonb;
  v_gzeros  boolean;
  v_gdesde  timestamptz;
  v_gmodos  jsonb;
  v_gult    record;
  v_gr      jsonb;
  -- FASE 7: fim
  -- CORREÇÃO FASE 6: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros obrigatórios de antes do aprendizado (o bloco do aprendizado os junta aos dele; o
  -- bloco da C2 depois dele refaz essa junta com as janelas de agenda_config)
  v_z4_antes := v_zeros4;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) o aprendizado (spec-fase6 §11) — o modo, a lista, a rodada, os itens e as métricas. Os "0 obrigatórios"
  -- (entram no ok pelo v_zeros4, como os das Fases 4 e 5): nada em uso com menos medidas que o mínimo; nada que a ÚLTIMA
  -- rodada gravou em uso com o modo dela fora de ligado ou o item fora da lista dela (logo depois de o dono desligar, o leitor
  -- já devolve o padrão; a linha muda na rodada seguinte); nenhuma troca grande que entrou sozinha (as ações da vigia em 7 dias
  -- contra os limites de hoje: a regra de _agenda_aprendizado_troca_cabe, que não tem porta para quem lê a saúde); nenhuma
  -- rodada atrasada (depois da 1ª, nenhuma em 26 h); nenhuma medida sem classe; nenhum fator fora de [fator_min, fator_max].
  -- Os erros de aprender:% em 24 h e as métricas não reprovam.
  select x.p_agora, x.p_hoje, x.contagens into v_arod
    from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  select count(*) into v_apeq
    from public.agenda_aprendizado a
   where a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min;
  select count(*) into v_afora
    from public.agenda_aprendizado a
   where v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
     and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
          or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false));
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '7 days'
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null and v_arod.p_agora < p_agora - interval '26 hours' then 1 else 0 end;
  select count(*) into v_asemcl from public.agenda_medidas_os m where m.classe_bem is null or m.classe_sistema is null;
  select count(*) into v_afat
    from public.agenda_aprendizado a
   where a.item = 'fator'
     and ((a.calculado is not null and a.calculado not between cf.fator_min and cf.fator_max)
          or (a.em_uso is not null and a.em_uso not between cf.fator_min and cf.fator_max));
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a group by a.item) t), '{}'::jsonb),
    'medidas', (select jsonb_build_object('total', count(*), 'validas', count(*) filter (where m.valida),
                                          'invalidas', coalesce((select jsonb_object_agg(y.motivo, y.n)
                                                                   from (select z.motivo, count(*) as n from public.agenda_medidas_os z
                                                                          where not z.valida
                                                                            and z.concluida_em > p_hoje - cf.aprender_janela_dias
                                                                          group by z.motivo) y), '{}'::jsonb))
                  from public.agenda_medidas_os m where m.concluida_em > p_hoje - cf.aprender_janela_dias),
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '30 days'),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - interval '30 days'),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida' and q.respondida_em > p_agora - interval '30 days'),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '30 days')),
    -- o erro do fator: das OS válidas concluídas depois que o fator da classe delas passou a valer, quantas ficaram dentro dele
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t),
    -- a pontualidade com o cliente antes e depois de a folga do aviso valer
    'pontualidade_folga', (select case when f.desde is not null then jsonb_build_object(
                                     'desde', f.desde,
                                     'antes_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                    where m.atraso_cliente_du is not null and m.concluida_em < f.desde),
                                     'depois_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                     where m.atraso_cliente_du is not null and m.concluida_em >= f.desde)) end
                             from (select (min(a.em_uso_desde) at time zone 'America/Sao_Paulo')::date as desde
                                     from public.agenda_aprendizado a where a.item = 'aviso_folga' and a.em_uso is not null) f),
    -- parar (§11): o item que o dono desfez 2 vezes em 4 semanas (recomendar tirá-lo da lista; a decisão é dele)
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '28 days'
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb))
    into v_amet;
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_zeros4 and v_zeros6;
  v_apr := jsonb_build_object(
    'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
    'ultima_rodada', v_arod.p_agora,
    'rodou_hoje', exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'aprender:%'
                     and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora, 'troca_grande_sem_pergunta', v_agrande,
    'rodada_atrasada', v_aatras, 'medida_sem_classe', v_asemcl, 'fator_fora_dos_limites', v_afat,
    'metricas', v_amet);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: as janelas do aprendizado na saúde vêm de agenda_config (eram números escritos aqui): a
  -- troca grande que entrou sozinha, nas ações dos últimos aprender_saude_dias (era 7 dias); a rodada atrasada, sem rodada há
  -- mais de aprender_atraso_h (era 26 h); as trocas das métricas, nos últimos aprender_parar_dias (era 30 dias; a chave
  -- trocas_30d fica com o nome); o item desfeito 2 vezes dentro de aprender_trava_dias (era 28 dias, as "4 semanas" da §11).
  -- As contas de cima não valem mais: refeitas aqui com o parâmetro (com os DEFAULTs, o mesmo resultado), e com elas os
  -- zeros, o ok e o bloco aprendizado.
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
     and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null
                        and v_arod.p_agora < p_agora - make_interval(hours => cf.aprender_atraso_h) then 1 else 0 end;
  v_amet := v_amet || jsonb_build_object(
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                      and a.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida'
                       and q.respondida_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - make_interval(days => cf.aprender_parar_dias))),
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado'
                                                     and a.desfeita_em > p_agora - make_interval(days => cf.aprender_trava_dias)
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb));
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_z4_antes and v_zeros6;
  v_apr := v_apr || jsonb_build_object('troca_grande_sem_pergunta', v_agrande, 'rodada_atrasada', v_aatras, 'metricas', v_amet);
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P7, spec §11) o bloco gestor: os modos efetivos, a última rodada (rotina gestor), os erros de gestor:% em 24 h, os
  -- zeros obrigatórios (entram no ok, salvo prazo_vencido_sem_mostrar, que só se conta: a pergunta fica aberta) e os números. Os
  -- zeros do que o gestor muda sozinho contam a partir do OK de ligar (marcar_sozinho_desde): antes dele não há o que contar.
  -- E (aviso do P6) o erro do fator só com as medidas que têm fator: a medida por estimativa é válida e não tem fator.
  v_gdesde := cf.marcar_sozinho_desde;
  v_gmodos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                 'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                 'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor, 'desde', v_gdesde);
  select max(x.p_agora) as ultima,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         coalesce(bool_or(x.p_hoje = p_hoje and x.contagens ? 'diaria'), false) as diaria_hoje,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_gult from public.agenda_vigia_rodadas x where x.rotina = 'gestor';
  v_gz := jsonb_build_object(
    -- o dia que o cliente ouviu e o dia que a equipe já sabia, mudados sem a pergunta crítica (a regra de _agenda_criticidade_da_acao)
    'zona_travada_mexida', (select count(*) from public.agenda_acoes a
                             where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                               and a.origem in ('motor', 'vigia', 'conferencia')
                               and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                               and public._agenda_criticidade_da_acao(a.id) = 'dia_prometido'),
    'dia_avisado_sem_pergunta', (select count(*) from public.agenda_acoes a
                                  where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                    and a.origem in ('motor', 'vigia', 'conferencia')
                                    and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                                    and public._agenda_criticidade_da_acao(a.id) = 'dia_avisado'),
    -- marcada pela estimativa sem a pergunta que ela pedia (grande, começada/parada, sem mão de obra, peça embutida)
    'estimativa_sem_pergunta', case when not public._agenda_gestor_regra('estimativa') then 0 else (
       select count(*) from (select distinct a.service_order_id as os from public.agenda_alocacoes a
                               left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
                              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                                and a.resultado is null and a.duracao_fonte = 'orcamento' and pl.dias is null) o
        where coalesce(public._agenda_gestor_estimativa(o.os, p_hoje) ->> 'motivo', '') in ('grande', 'situacao', 'sem_base', 'embutida')) end,
    'prazo_em_critica', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.critica and q.veto_ate is not null),
    'prazo_em_dia_prometido', (select count(*) from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.veto_ate is not null and q.tipo = 'dia_prometido'),
    -- aprovada há mais de aprovada_sem_data_min sem dia, sem reserva, sem pergunta aberta e sem o motor ter dito por que fica de
    -- fora depois da aprovação (com o encaixe na aprovação ligado: antes dele, quem encaixa é a vigia e a publicação)
    'aprovada_sem_data', case when public._agenda_gestor_modo('encaixe') <> 'ligado' then 0 else (
       select count(*) from public.os_carteira(p_hoje) k join public.service_orders so on so.id = k.service_order_id
        where coalesce(so.converted_to_os_at, so.signed_at) is not null
          and coalesce(so.converted_to_os_at, so.signed_at) < p_agora - make_interval(mins => cf.aprovada_sem_data_min)
          and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.service_order_id
                           and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
          and not exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = k.service_order_id)
          and not exists (select 1 from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                           where pr.criada_em >= coalesce(so.converted_to_os_at, so.signed_at)
                             and (f ->> 'os')::uuid = k.service_order_id)) end,
    -- sem rodada do gestor em 40 min, de 07:30 a 21:00 de dia útil, com algum modo do gestor fora de desligado
    'rodada_gestor_atrasada', case when (v_gmodos ->> 'marcar' <> 'desligado' or v_gmodos ->> 'encaixe' <> 'desligado'
                                         or v_gmodos ->> 'revisao' <> 'desligado' or v_gmodos ->> 'compre_ate' <> 'desligado')
                                        and public.agenda_dia_util(p_hoje)
                                        and (p_agora at time zone 'America/Sao_Paulo')::time between time '07:30' and time '21:00'
                                        and coalesce(v_gult.ultima < p_agora - interval '40 minutes', true) then 1 else 0 end,
    -- a mensagem ao cliente por estimativa que saiu sem o sim do dono antes de somar cliente_aprovacao_dias dias aprovados
    'cliente_estimativa_sem_aprovacao', (
       select count(*) from public.agenda_cliente_mensagens m
        where v_gdesde is not null and m.criada_em >= v_gdesde and m.base -> 'dados' ->> 'por_estimativa' = 'true'
          and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta') and m.aprovacao <> 'aprovada'
          and (select count(distinct (n.aprovada_em at time zone 'America/Sao_Paulo')::date) from public.agenda_cliente_mensagens n
                where n.tipo = m.tipo and n.base -> 'dados' ->> 'por_estimativa' = 'true' and n.aprovacao = 'aprovada'
                  and n.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias),
    -- a ficha de um dia por estimativa que saiu na janela de veto sem a pergunta ficha_estimativa mostrada (ou segurada com 2)
    'ficha_estimativa_sem_veto', (
       select count(*) from public.agenda_equipe_mensagens em
        where v_gdesde is not null and em.tipo = 'ficha' and em.modo = 'ligado'
          and em.estado in ('enfileirada', 'respondida', 'sem_resposta')
          and em.dia >= (v_gdesde at time zone 'America/Sao_Paulo')::date
          and em.dia < (v_gdesde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias
          and exists (select 1 from public.agenda_alocacoes a where a.payee_id = em.payee_id and a.dia = em.dia
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento')
          and not exists (select 1 from public.agenda_perguntas q
                           where q.chave = 'ficha_estimativa:' || em.payee_id || ':' || em.dia and q.mostrada_vezes > 0
                             and q.opcao_escolhida is distinct from 2)),
    -- a rodada que mudou o dia de mais de gestor_k_os OS de uma vez sem a pergunta onda
    'onda_aplicada_sem_pergunta', (
       select count(*) from (select a.proposta_id from public.agenda_acoes a
                               where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                 and a.origem in ('motor', 'vigia') and a.tipo = 'mover' and a.proposta_id is not null
                               group by a.proposta_id having count(distinct a.service_order_id) > cf.gestor_k_os) p
        where not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda' and q.proposta_id = p.proposta_id)),
    -- o compromisso novo sem de onde veio a duração (o gatilho _agenda_alocacao_fonte grava em toda alocação nova)
    'alocacao_sem_fonte', (select count(*) from public.agenda_alocacoes a
                            where v_gdesde is not null and a.criado_em >= v_gdesde and a.tipo <> 'reserva' and a.duracao_fonte is null),
    -- a ação do gestor feita numa rodada em que o modo dela não estava ligado (estimar: marcar; reestimar e reparar: revisao)
    'regra_em_sombra_aplicada', (
       select count(*) from public.agenda_acoes a
        where a.executada and a.origem = 'vigia' and a.tipo in ('estimar', 'reestimar', 'reparar')
          and a.criada_em > p_agora - interval '7 days'
          and coalesce((select r.contagens -> 'modos' ->> case when a.tipo = 'estimar' then 'marcar' else 'revisao' end
                          from public.agenda_vigia_rodadas r
                         where r.rotina = 'gestor' and r.p_agora <= a.criada_em
                         order by r.p_agora desc, r.rodou_em desc limit 1), 'desligado') <> 'ligado'),
    -- a pergunta com prazo vencido que o dono nunca viu antes do prazo: fica aberta (aqui só se conta; não entra no ok)
    'prazo_vencido_sem_mostrar', (select count(*) from public.agenda_perguntas q
                                   where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora
                                     and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)));
  v_gzeros := not exists (select 1 from jsonb_each(v_gz) z where z.key <> 'prazo_vencido_sem_mostrar' and (z.value)::text <> '0');
  v_ges := jsonb_build_object(
    'modos', v_gmodos, 'regras', to_jsonb(cf.marcar_regras),
    'ultima_rodada', v_gult.ultima, 'rodadas_24h', coalesce(v_gult.n24, 0), 'diaria_hoje', coalesce(v_gult.diaria_hoje, false),
    'erros_ultima_rodada', coalesce(v_gult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'gestor:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', v_gzeros,
    'numeros', jsonb_build_object(
      'os_por_estimativa', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.resultado is null and a.duracao_fonte = 'orcamento'),
      'perguntas_com_prazo', jsonb_build_object(
        'abertas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null),
        'vencidas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora),
        'respondidas_7d', (select count(*) from public.agenda_perguntas q where q.estado = 'respondida' and q.veto_ate is not null
                             and q.respondida_em > p_agora - interval '7 days'),
        'pelo_prazo_7d', (select count(*) from public.agenda_acoes a where a.tipo = 'estimar' and a.origem = 'vigia' and a.executada
                            and a.criada_em > p_agora - interval '7 days')),
      'compre_ate', jsonb_build_object(
        'gravados', (select count(*) from public.os_material m where m.compre_ate is not null),
        'cobrados', (select count(*) from public.os_material m where m.cobrado_vezes > 0),
        'empurrados', (select count(*) from public.os_material m where m.empurrada_vezes > 0)),
      'fichas_seguradas_7d', (select count(*) from public.agenda_equipe_mensagens em
                               where em.recusa_motivo = 'veto' and em.criada_em > p_agora - interval '7 days'))) || v_gz;
  v_amet := v_amet || jsonb_build_object(
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.fator is not null
                                 and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t));
  v_apr := v_apr || jsonb_build_object('metricas', v_amet);
  v_gr := jsonb_build_object(
    -- os zeros obrigatórios da execução (a Fase 3), do material e da mensagem ao fornecedor (a Fase 4) e os do gestor entram no ok
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          and v_zeros4
          and v_gzeros,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    'cliente', v_cli,
    'aprendizado', v_apr,
    'material', v_mat,
    'gestor', v_ges);
  -- FASE 7b (P5, §5.4, R4.3(g); dentro do bloco do gestor da 7a, que monta a saída e volta aqui — por isso sem os dois-pontos depois
  -- de "7b": os tiradores de antes tiram o bloco do gestor inteiro e não o leem como bloco próprio): a chave equipe_dias
  -- (_agenda_saude_equipe7b: as mensagens dias à equipe, a dupla no plano, quem nunca fica sozinho, o sábado, o dono numa vaga e a
  -- resposta gravada), com os zeros obrigatórios no ok. Sem os modos da 7b, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('equipe_dias', public._agenda_saude_equipe7b(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{equipe_dias,zeros_ok}')::boolean, true)));
  -- FASE 7b (P5): fim
  return v_gr;
  -- FASE 7: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 6: o aprendizado
    'aprendizado', v_apr,
    -- FASE 6: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias. FASE 7 (7a P7, spec §11): a chave gestor — os modos efetivos (marcar, encaixe, revisao, compre_ate, vaga, so_propor, desde), as regras, a última rodada (rotina gestor), as rodadas em 24 h, se os passos diários rodaram hoje, os erros de gestor:% em 24 h, os zeros obrigatórios (entram no ok: zona_travada_mexida e dia_avisado_sem_pergunta pela regra de _agenda_criticidade_da_acao, estimativa_sem_pergunta, prazo_em_critica, prazo_em_dia_prometido, aprovada_sem_data, rodada_gestor_atrasada, cliente_estimativa_sem_aprovacao, ficha_estimativa_sem_veto, onda_aplicada_sem_pergunta, alocacao_sem_fonte, regra_em_sombra_aplicada; os do que o gestor muda sozinho contam a partir de marcar_sozinho_desde) e prazo_vencido_sem_mostrar (só se conta: fica fora do ok), e os números (OS por estimativa, perguntas com prazo abertas/vencidas/respondidas/aplicadas pelo prazo, compre até gravados/cobrados/empurrados, fichas seguradas). E o erro do fator (métricas do aprendizado) só com as medidas que têm fator (a medida por estimativa é válida e não tem fator). FASE 7b (P5, §5.4, R4.3(g)): a chave equipe_dias (_agenda_saude_equipe7b): modos (dias, dupla, sabado, cadastro, chamar), a última rodada da semana da equipe e os erros de equipe_semana:% em 24 h, os zeros obrigatórios (entram no ok: dias_fora_da_janela, dias_duas_na_semana, dia_acima_do_teto, ficha_recusada_por_teto_com_dias, dupla_com_uma_pessoa — só a dita —, dupla_incompleta_com_gente_livre, novato_sozinho, sabado_sem_prazo, sabado_tarde, dono_em_vaga_sem_ok, resposta_sem_gravar) e os números (perguntadas × respondidas na última semana fechada e o %, adiadas pelo teto em 7 dias, a dupla inferida esperando o ajudante, duplas inferidas × ditas, sábados usados e em teste, a semana passada por pessoa: declarada × usada × cumprida). Sem os modos da 7b, os zeros são 0 e o ok é o de antes.';

-- As portas das recriadas: as de antes (os_plano_da_os: definer, authenticated e service_role; agenda_saude: invoker, authenticated e
-- service_role); nunca anon.
revoke all on function public.os_plano_da_os(uuid, date) from public, anon;
grant execute on function public.os_plano_da_os(uuid, date) to authenticated, service_role;
revoke all on function public.agenda_saude(date, timestamptz) from public, anon;
grant execute on function public.agenda_saude(date, timestamptz) to authenticated, service_role;
