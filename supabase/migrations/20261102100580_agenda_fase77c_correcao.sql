-- Agenda de Produção — Fase 7c, correção da revisão (20261102100580): os achados da revisão da etapa 7c.
-- NÃO aplicada.
--
-- ═══ DDL — OK NOMEADO ═══ (10 funções recriadas com as mesmas assinaturas e as mesmas portas; nenhuma função nova, tabela, coluna,
-- lista, job ou dado)
-- Vai DEPOIS da 20261102100550 (as tarefas do dia, P8) e ANTES do dado 20261102100600. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7c/corr/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (o montador para se outra
-- migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7c: (7c correção, achado N) … -- FASE 7c: fim" e,
-- dentro de um bloco de antes (da 7b ou de um pacote da 7c), nas marcas "-- (7c correção, achado N) … -- (7c: fim)" (só acréscimo:
-- nenhuma linha de antes muda; tirados esses blocos e marcas, o corpo é o da origem, byte a byte: o montador e o K0 de
-- supabase/tests/agenda_fase77c_correcao.sql conferem). Os testes de cópia de antes, que tiram os blocos "-- FASE 7c:" e as marcas
-- "-- (7c", tiram estes junto.
--
-- O QUE MUDA (e por quê; o detalhe de cada achado em notas-fase77c.md, seção "Correção da revisão"):
--   1. (achado 7, alta) A PERGUNTA POR OS NASCE NA ORDEM EM QUE A PRODUÇÃO RODA. _agenda_habilidade_perguntas_os lia só "a última proposta
--      do motor de hoje", uma vez por dia, no passo da rodada (0b2a), que roda ANTES da vigia (0c); o gestor roda às :53. A OS que a vigia
--      ou o gestor tirava por falta de quem o serviço pede (a Vera, sex 06/11 às 16:15, depois de "o Alex não sobe no teto") nunca ganhava a
--      pergunta. Agora cada OS vale pela última proposta que a cita (alvo ou fora) dos últimos 7 dias, e agenda_habilidade roda o passo
--      também a cada tique fora da rodada (com modo_habilidade ligado): a pergunta nasce no tique seguinte.
--   2. (achado 8, alta) O FECHAMENTO CHEIO COM O CLIENTE. O Secretário (sem mudar o TS) encolhe só a linha que tem forma curta antes de tirar
--      uma; a do cliente (75, a mensagem que espera *manda cliente*) não tinha, e com ela a (o) "Etapas" e a (n) de quem faz o quê caíam (5
--      fechamentos da semana real da revisão). _agenda_linhas_do_fechamento dá a forma curta à linha do cliente quando há uma linha da 7c
--      ligada que perde hoje.
--   3. (achado 2) A (n) NÃO FICA DE FORA PARA SEMPRE. Com a compra (80) e as perguntas do gestor (76), as três não cabem nem na forma curta
--      (o P5 provou: ~1.063 letras). A (n) com uma pergunta de quem faz o quê ou das etapas nunca vista há 2 dias úteis sobe a 77 (salvo se a
--      linha que ela tiraria perde algo hoje: a ficha de amanhã ou um prazo de hoje): uma vez, e vista, volta à de sempre.
--   4. (achado 14) A CHAMADA DA 7b NÃO GASTA A VEZ DELA POR CAUSA DA 7c. Na (n), com a de quem faz o quê só como "Também" (não conta como
--      vista), a perda 75 dela fazia a chamada sair (e contar) num dia que não era o dela. Sem pergunta da 7b que perca hoje e com uma da 7c
--      que perde, as da 7b esperam o dia delas e a da 7c vai primeiro, inteira.
--   5. (achado 11) A PERGUNTA DE QUEM FAZ O QUÊ ACOMPANHA O QUE O DONO DISSE. Refeita quando o texto dela mudaria ("o Alex não sobe no
--      teto" gravado antes de ver: ela dizia "… e sobe no teto"); o exemplo não sugere o que já vale.
--   6. (achado 9) A TROCA DO RESPONSÁVEL APARECE NO "O QUE MUDOU". agenda_propor põe a troca avisada também no texto do item ("… —
--      troquei o responsável: Roberto não está livre até qua 11/11; segui com João."), que vira a ação, o fechamento e o aviso.
--   7. (achado 1) AG7-10c: SÓ O RESPONSÁVEL DA OS RESPONDE PELAS ETAPAS. _agenda_tarefas_planejar dava a vez ao "responsável da equipe" e
--      ao ajudante; agora, sem o responsável da OS no meio-dia, ninguém responde (o dono confere) — a resposta do dono, que vale sobre a spec.
--   8. (achado 10) A OS COMEÇADA ANTES DAS ETAPAS NÃO PEDE DE NOVO O QUE JÁ FEZ: os meios-dias passados sem linha de etapa saem do total que
--      as etapas repartem (o Edu não dá mais "não cabe até o prazo" falso).
--   9. (achado 12) O PRAZO VENCIDO NÃO VIRA "ATÉ QUI 10/09 NÃO CABE" (os_tarefas_da_os, a guarda da exceção).
--  10. (achado 5) EM TESTE, O DIA DA PESSOA DIZ QUE É TESTE (agenda_dia_da_pessoa: "— em teste (a equipe ainda não recebe), o que fazer: …").
--  11. (achado 16) O EXEMPLO DO FOCO *agenda quem faz* NÃO SUGERE TIRAR A PROTEÇÃO DO NOVO ("o Mateus instala sozinho" saía para quem vem
--      sob demanda).
--
-- O QUE NÃO MUDA: com os 4 modos da 7c desligados, a saída de antes, byte a byte; em teste, também (o motor, a escalação, as perguntas
-- ligadas, o fechamento que o dono lê), salvo o que já é de teste ou leitura do dono: as etapas em teste (itens 7, 8 e 9: o plano de teste,
-- as ações de teste e a linha "Etapas (em teste: …)") e o dia da pessoa em teste (item 10). As Fases 1 a 6, a 7a e a 7b; as portas; nenhum
-- texto ao cliente nem à equipe muda (a forma curta do item 2 é a linha do dono no fechamento).
--
-- Quem recriar depois uma destas funções copia DESTA migration (a regra da função mais nova; fase7-registro.md §2).
--
-- DESFAZER: recriar cada uma com o corpo da definição de antes — a 20261102100550 para _agenda_tarefas_planejar, os_tarefas_da_os,
-- agenda_dia_da_pessoa e _agenda_linhas_do_fechamento; a 20261102100400 para _agenda_habilidade_perguntas_os, agenda_habilidade,
-- _agenda_habilidade_pergunta_texto e _agenda_habilidade_propor; a 20261102100500 para _agenda_ver_habilidades; a 20261102100100 para
-- agenda_propor. As portas não mudam (create or replace mantém os grants).

-- _agenda_tarefas_planejar (de 20261102100550_agenda_fase7c_tarefas.sql)
create or replace function public._agenda_tarefas_planejar(p_os uuid, p_hoje date, p_modo text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_resto  constant numeric := 0.25;    -- estrutural (spec §16.3.6): a etapa começada pede ao menos ¼ de meio-dia
  c_resid  constant numeric := 0.001;   -- estrutural: o resíduo das frações (3 casas) não é etapa a fazer
  c_folga  constant numeric := 0.01;    -- estrutural: a sobra de um meio-dia abaixo disso não leva outra etapa
  cf       public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_n      jsonb;
  v_total  numeric;
  v_soma   numeric;
  v_ids    uuid[] := '{}';
  v_meios  numeric[] := '{}';
  v_need   numeric[] := '{}';
  v_ex     int[] := '{}';
  v_fin    boolean[] := '{}';
  v_ini    boolean[] := '{}';
  v_pend   boolean[] := '{}';
  v_pdia   date[] := '{}';
  v_ord    numeric[] := '{}';
  v_at     boolean[] := '{}';
  v_k      int;
  e        record;
  l        record;
  r        record;
  v_md     jsonb := '[]'::jsonb;
  v_hab    jsonb := '{}'::jsonb;
  v_fone   jsonb := '{}'::jsonb;
  v_dalt   int;
  v_lid    uuid;
  h        record;
  v_pes    uuid[];
  v_out    jsonb := '[]'::jsonb;
  v_itens  jsonb;
  v_cap    numeric;
  v_pos    int;
  v_f      numeric;
  v_term   boolean;
  v_fila   int[];
  v_atende boolean;
  v_mask   int;
  v_resp   uuid;
  v_prazo  date;
  v_snap   numeric;
  v_ate    int := 0;
  v_falta  numeric;
  v_futuro int := 0;
  v_faltam uuid[];
  m        jsonb;
  -- FASE 7c: (7c correção, achado 10) o total da OS e o que ela já fez antes de ter etapas neste modo
  v_c10_tot  numeric;
  v_c10_sem  numeric;
  -- FASE 7c: fim
begin
  if p_os is null or p_hoje is null or p_modo is null or p_modo not in ('sombra', 'ligado') then
    raise exception 'Faltam a OS, o dia e o modo (sombra ou ligado) para planejar as etapas.' using errcode = '22023';
  end if;
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);
  v_total := nullif((public.agenda_meios_da_os(p_os, p_hoje) ->> 'total')::numeric, 0);
  select coalesce(sum(x.horas), 0) into v_soma from public.os_tarefas x where x.service_order_id = p_os and x.estado in ('viva', 'feita');

  -- FASE 7c: (7c correção, achado 10) os meios-dias que a OS já fez ANTES de ter etapas neste modo (a OS começada antes de as etapas
  -- nascerem ou de serem ligadas) saem do total: cada etapa pede a sua parte do que FALTA. Sem isso, o Edu (3 dias ditos, 1 feito pelo
  -- Roberto sem linha de etapa) pedia os 3 dias inteiros, e o dono recebia "não cabe até o prazo" com o plano exato dos 2 que faltam.
  -- A conta é a do plano da OS (_agenda_plano_da_os, d20): cada meio-dia passado de turno, sem reserva, vigente, pelo melhor resultado
  -- (cumprido, sem registro ou passado sem resultado = 1; parcial = meio; não cumprido = 0), só os que não têm nenhuma linha de etapa
  -- neste modo (os que têm já descontam pela linha, abaixo). Sem nada a descontar, o de antes; sem sobrar nada, a conta pelas horas. O
  -- total da saída continua o da OS.
  v_c10_tot := v_total;
  if v_total is not null then
    select coalesce(sum(y.peso), 0)::numeric / 2 into v_c10_sem
      from (select a.dia, a.turno,
                   max(case when a.resultado in ('cumprido', 'sem_registro') or a.resultado is null then 2
                            when a.resultado = 'parcial' then 1 else 0 end) as peso
              from public.agenda_alocacoes a
             where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.presenca = 'turno' and a.dia < p_hoje
             group by a.dia, a.turno) y
     where not exists (select 1 from public.os_tarefas_dia d
                        where d.service_order_id = p_os and d.dia = y.dia and d.turno = y.turno and d.modo = p_modo
                          and d.estado = 'planejada');
    if v_c10_sem > 0 then
      v_total := nullif(greatest(v_total - v_c10_sem, 0), 0);
    end if;
  end if;
  -- FASE 7c: fim
  -- 1. As etapas vivas, cada uma com o que ainda pede (need), pelo que o plano congelado de antes de hoje levou.
  for e in select x.* from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' order by x.ordem, x.id loop
    v_ids := v_ids || e.id;
    v_ord := v_ord || e.ordem;
    v_ex := v_ex || e.exige::int;
    v_fin := v_fin || (e.chave = 'entrega');
    v_meios := v_meios || case when v_total is not null and v_soma > 0 then e.horas / v_soma * v_total
                               else e.horas / (cf.jornada_horas / 2) end;
    v_k := cardinality(v_ids);
    v_need := v_need || v_meios[v_k];
    v_ini := v_ini || false;
    v_pend := v_pend || false;
    v_pdia := v_pdia || null::date;
    v_at := v_at || false;
    for l in select d.* from public.os_tarefas_dia d
              where d.tarefa_id = e.id and d.modo = p_modo and d.estado = 'planejada' and d.dia < p_hoje
              order by d.dia, d.turno = 'tarde', d.posicao loop
      v_need[v_k] := v_need[v_k] - l.fracao;
      v_ini[v_k] := true;
      if l.termina then
        if l.resultado = 'pendente' then
          v_need[v_k] := cf.tarefas_pendente_meios;
          v_ini[v_k] := false;
          v_pend[v_k] := true;
          v_pdia[v_k] := l.dia;
        else
          -- feita, sem registro (R5.2-3) ou ainda sem resultado: conta como feita para o plano
          v_need[v_k] := 0;
          v_ini[v_k] := false;
          v_pend[v_k] := false;
        end if;
      end if;
    end loop;
    if v_ini[v_k] and v_need[v_k] > 0 then
      v_need[v_k] := greatest(v_need[v_k], c_resto);
    elsif v_ini[v_k] and v_need[v_k] <= 0 then
      v_need[v_k] := c_resto;
    end if;
  end loop;
  -- FASE 7c: (7c correção, achado 10) o total da saída é o da OS (o descontado só reparte o que falta entre as etapas)
  v_total := v_c10_tot;
  -- FASE 7c: fim
  v_falta := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
  v_faltam := array(select v_ids[k] from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid
                     order by case when v_pend[k] then 0 when v_ini[k] then 1 else 2 end, v_pdia[k] nulls last, v_ord[k], k);

  -- 2. Os meios-dias da OS de hoje em diante (alocação vigente de turno, sem reserva): a equipe (sem o dono), o dono no turno, na
  -- abertura e no fechamento.
  select coalesce(jsonb_agg(jsonb_build_object('dia', x.dia, 'turno', x.turno, 'equipe', to_jsonb(x.eq), 'dono_turno', x.dt,
                                               'dono_fecha', x.df, 'dono_abre', x.da) order by x.dia, x.turno = 'tarde'), '[]'::jsonb)
    into v_md
    from (select a.dia, a.turno,
                 coalesce(array_agg(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono), '{}'::uuid[]) as eq,
                 coalesce(bool_or(a.payee_id is not distinct from v_dono), false) as dt,
                 exists (select 1 from public.agenda_alocacoes b
                          where b.service_order_id = p_os and b.dia = a.dia and b.turno = a.turno and b.presenca = 'fechamento'
                            and b.payee_id is not distinct from v_dono and b.estado in ('publicada', 'fixada')) as df,
                 exists (select 1 from public.agenda_alocacoes b
                          where b.service_order_id = p_os and b.dia = a.dia and b.turno = a.turno and b.presenca = 'abertura'
                            and b.payee_id is not distinct from v_dono and b.estado in ('publicada', 'fixada')) as da
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
             and a.dia >= p_hoje
           group by a.dia, a.turno) x;

  -- As habilidades (uma leitura: as etiquetas efetivas, qualquer que seja o modo_habilidade, §16.3.5), quem recebe pelo WhatsApp e o
  -- responsável da OS.
  v_pes := array(select distinct u.x::uuid from jsonb_array_elements(v_md) d, jsonb_array_elements_text(d -> 'equipe') u(x));
  for h in select * from public.agenda_habilidades(p_hoje, v_pes || v_dono) loop
    v_hab := v_hab || jsonb_build_object(h.payee_id::text, jsonb_build_object('i', h.instala, 'c', h.comissiona, 'a', h.altura,
                                                                             'p', h.papel, 'n', h.nome));
    if h.eh_dono then
      v_dalt := h.altura;
    end if;
    v_fone := v_fone || jsonb_build_object(h.payee_id::text,
      public._agenda_equipe_tem_telefone(h.payee_id)
      and exists (select 1 from public.agenda_equipe_contato c where c.payee_id = h.payee_id and c.recebe_rotina and c.parou_em is null));
  end loop;
  v_lid := (public._agenda_lider_da_os(p_os, p_hoje) ->> 'payee_id')::uuid;
  v_prazo := (public.os_prontidao(p_os, p_hoje) ->> 'prazo_efetivo')::date;
  if v_prazo is null and jsonb_array_length(v_md) > 0 then
    v_prazo := (v_md -> -1 ->> 'dia')::date;
  end if;

  -- 3. Cada meio-dia, na ordem.
  for m in select d from jsonb_array_elements(v_md) d loop
    if v_snap is null and v_prazo is not null and (m ->> 'dia')::date > v_prazo then
      v_snap := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
    end if;
    -- o plano até o prazo: os meios-dias que ainda vão acontecer (o de hoje já congelado e todo respondido não conta mais)
    if v_prazo is not null and (m ->> 'dia')::date <= v_prazo
       and ((m ->> 'dia')::date > p_hoje
            or not exists (select 1 from public.os_tarefas_dia d
                            where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                              and d.estado = 'planejada')
            or exists (select 1 from public.os_tarefas_dia d
                        where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                          and d.estado = 'planejada' and d.termina and d.resultado is null)) then
      v_ate := v_ate + 1;
    end if;
    v_itens := '[]'::jsonb;
    if exists (select 1 from public.os_tarefas_dia d
                where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                  and d.estado = 'planejada') then
      -- congelado: entra com as linhas dele, sem refazer
      v_resp := null;
      for l in select d.* from public.os_tarefas_dia d
                where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                  and d.estado = 'planejada'
                order by d.posicao, d.id loop
        v_resp := l.responde;
        v_k := array_position(v_ids, l.tarefa_id);
        if v_k is not null then
          v_need[v_k] := v_need[v_k] - l.fracao;
          v_ini[v_k] := true;
          v_pend[v_k] := false;
          if l.termina then
            if l.resultado = 'pendente' then
              v_need[v_k] := cf.tarefas_pendente_meios;
              v_ini[v_k] := false;
              v_pend[v_k] := true;
              v_pdia[v_k] := l.dia;
            else
              v_need[v_k] := 0;
              v_ini[v_k] := false;
            end if;
          elsif v_need[v_k] <= 0 then
            v_need[v_k] := c_resto;
          end if;
        end if;
        v_itens := v_itens || jsonb_build_array(jsonb_build_object('tarefa', l.tarefa_id, 'fracao', l.fracao, 'termina', l.termina,
                                                                   'comeca', l.comeca, 'posicao', l.posicao, 'linha_id', l.id,
                                                                   'resultado', l.resultado));
      end loop;
      v_out := v_out || jsonb_build_array(m || jsonb_build_object('congelado', true, 'responde', v_resp, 'itens', v_itens,
        'equipe', coalesce((select to_jsonb(d.equipe) from public.os_tarefas_dia d
                             where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno'
                               and d.modo = p_modo and d.estado = 'planejada' order by d.posicao limit 1), m -> 'equipe')));
      continue;
    end if;

    v_futuro := v_futuro + 1;
    v_cap := 1;
    v_pos := 0;
    -- a fila deste meio-dia: a pendente (pela data, depois a ordem), a começada, as outras (pela ordem)
    v_fila := array(select k from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid
                     order by case when v_pend[k] then 0 when v_ini[k] then 1 else 2 end, v_pdia[k] nulls last, v_ord[k], k);
    foreach v_k in array v_fila loop
      -- o fechamento do dono (com habilidade_fechamento_cobre) cobre a etapa final inteira e o comissionar e o diagnóstico das outras
      -- (o que é do dono, AG7-02); o 220 V e o teto pedem quem os faz na equipe do meio-dia
      v_mask := case when (m ->> 'dono_fecha')::boolean and cf.habilidade_fechamento_cobre
                     then case when v_fin[v_k] then 0 else v_ex[v_k] & ~10 end
                     else v_ex[v_k] end;
      if v_mask = 0 then
        v_atende := true;
      else
        v_atende := public._agenda_atende(
          v_mask,
          array(select (v_hab -> u.x ->> 'i')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'c')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'a')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'p')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          (m ->> 'dono_turno')::boolean, v_dalt, v_n) is null;
      end if;
      if not v_atende then
        continue;   -- espera um meio-dia que atenda; as outras seguem
      end if;
      v_at[v_k] := true;
      continue when v_cap <= c_folga;
      v_f := least(v_need[v_k], v_cap);
      v_term := v_need[v_k] - v_f <= c_folga;
      if v_term then
        v_f := v_need[v_k];
      end if;
      v_f := least(greatest(round(v_f, 3), c_resid), 1);
      v_pos := v_pos + 1;
      v_itens := v_itens || jsonb_build_array(jsonb_build_object('tarefa', v_ids[v_k], 'fracao', v_f, 'termina', v_term,
                                                                 'comeca', not v_ini[v_k], 'posicao', v_pos, 'linha_id', null,
                                                                 'resultado', null));
      v_need[v_k] := case when v_term then 0 else v_need[v_k] - v_f end;
      v_ini[v_k] := true;
      v_pend[v_k] := false;
      v_cap := v_cap - v_f;
    end loop;

    -- quem responde pelas etapas do meio-dia (§16.3.6): o responsável da OS na equipe; senão o responsável da equipe de maior instala
    -- (o nome); senão, só com ajudante e o dono presente, o dono (nulo); senão o ajudante. Quem não recebe pelo WhatsApp (sem telefone
    -- pela régua da 7a, ou fora da rotina) não responde: vale a conferência do dono (nulo, R5.2-4).
    v_resp := null;
    if v_lid is not null and (m -> 'equipe') ? v_lid::text then
      v_resp := v_lid;
    else
      select u.x::uuid into v_resp
        from jsonb_array_elements_text(m -> 'equipe') u(x)
       where (v_hab -> u.x ->> 'p')::int = 0
       order by (v_hab -> u.x ->> 'i')::int desc, v_hab -> u.x ->> 'n', u.x limit 1;
      if v_resp is null and not ((m ->> 'dono_turno')::boolean or (m ->> 'dono_fecha')::boolean or (m ->> 'dono_abre')::boolean) then
        select u.x::uuid into v_resp from jsonb_array_elements_text(m -> 'equipe') u(x) order by v_hab -> u.x ->> 'n', u.x limit 1;
      end if;
    end if;
    -- FASE 7c: (7c correção, achado 1) AG7-10c, a resposta do dono ("Sim, o responsável da OS"; fase7-padroes, que vale sobre a
    -- spec): quem responde pelas etapas do meio-dia é só o responsável da OS (_agenda_lider_da_os, qualquer fonte) quando ele está na
    -- equipe. Sem ele, ninguém da equipe responde — nem o "responsável da equipe" de maior instala, nem o ajudante, que só recebe a
    -- lista na ficha (e o "como foi" de antes) — e vale a conferência do dono (nulo, R5.2-4). O §16.3.6, itens 2 a 4, dava a vez a eles.
    if v_resp is distinct from v_lid then
      v_resp := null;
    end if;
    -- FASE 7c: fim
    if v_resp is not null and not coalesce((v_fone ->> v_resp::text)::boolean, false) then
      v_resp := null;
    end if;
    v_out := v_out || jsonb_build_array(m || jsonb_build_object('congelado', false, 'responde', v_resp, 'itens', v_itens));
  end loop;
  if v_snap is null then
    v_snap := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
  end if;

  return jsonb_build_object(
    'os', p_os, 'modo', p_modo, 'total', v_total, 'falta', round(v_falta, 3), 'faltam', to_jsonb(v_faltam), 'meios', v_out,
    'sobra', coalesce((select jsonb_agg(jsonb_build_object('tarefa', v_ids[k], 'need', round(v_need[k], 3)) order by k)
                         from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid), '[]'::jsonb),
    'sobra_meios', round((select coalesce(sum(x), 0) from unnest(v_need) x where x > c_resid), 3),
    'sem_quem', coalesce((select jsonb_agg(v_ids[k] order by k) from generate_subscripts(v_ids, 1) k
                           where v_need[k] > c_resid and v_ex[k] <> 0 and not v_at[k] and v_futuro > 0), '[]'::jsonb),
    'prazo', v_prazo, 'sobra_no_prazo', round(v_snap, 3), 'meios_ate_prazo', v_ate);
end;
$function$;

comment on function public._agenda_tarefas_planejar(uuid, date, text) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.5, §16.3.6; R5.2-3, R5.2-4): a distribuição das etapas vivas da OS pelos meios-dias marcados (alocação vigente de turno, sem reserva) de p_hoje em diante, no modo p_modo — o que cada etapa pede em meios-dias é o peso dela sobre o total (agenda_meios_da_os.total; sem base, horas ÷ meia jornada) menos o que o plano congelado de antes de hoje levou (a começada, no mínimo 0,25; a pendente dita, tarefas_pendente_meios; a que terminou com feita, sem registro ou ainda sem resultado: nada, conta como feita para o plano). O meio-dia já congelado entra com as linhas dele; cada outro leva até 1,0, na fila pendente → começada → as outras pela ordem; a etapa de risco (exige) só vai ao meio-dia cuja equipe atende (_agenda_atende com as etiquetas efetivas; a final conta o fechamento do dono com habilidade_fechamento_cobre), e as outras seguem. Quem responde: o responsável da OS na equipe, senão o responsável da equipe de maior instala, senão (só ajudante e o dono presente) o dono (nulo), senão o ajudante; quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) não responde (nulo = o dono pela conferência). {os, modo, total, falta, meios [{dia, turno, congelado, equipe, dono_turno, dono_fecha, dono_abre, responde, itens [{tarefa, fracao, termina, comeca, posicao, linha_id, resultado}]}], sobra [{tarefa, need}], sobra_meios, sem_quem [tarefa] (a de risco que nenhum meio-dia futuro atende), prazo (o prazo efetivo; sem ele, o último dia do plano), sobra_no_prazo (o que não coube até o prazo), meios_ate_prazo}. STABLE, sem grant. CORREÇÃO DA REVISÃO DA 7c (20261102100580): (achado 1, AG7-10c) quem responde é só o responsável da OS na equipe do meio-dia; sem ele, nulo (o dono pela conferência) — nunca o responsável da equipe de maior instala nem o ajudante; (achado 10) os meios-dias que a OS fez antes de ter etapas neste modo (passados de turno, sem linha de etapa; cumprido, sem registro ou sem resultado = 1, parcial = meio) saem do total que as etapas repartem (a OS começada antes das etapas não pede de novo o que já foi feito); o total da saída continua o da OS.';

-- os_tarefas_da_os (de 20261102100550_agenda_fase7c_tarefas.sql)
create or replace function public.os_tarefas_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_uid   uuid := auth.uid();
  v_papel text;
  v_p     jsonb;
  v_et    jsonb := '[]'::jsonb;
  r       record;
  v_ult   record;
  v_est   text;
  v_qd    date;
  v_feit  text[] := '{}';
  v_falt  text[] := '{}';
  v_tot   int := 0;
  v_cab   text;
  v_nc    text;
  v_txt   text;
  v_k     int;
  v_cabe  boolean;
begin
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  cf := public._agenda_cfg();
  if p_os is null or not exists (select 1 from public.service_orders so where so.id = p_os) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  if cf.modo_tarefas = 'desligado'
     or not exists (select 1 from public.os_tarefas t where t.service_order_id = p_os and t.estado in ('viva', 'feita', 'nao_se_aplica')) then
    return jsonb_build_object('ok', true, 'modo', cf.modo_tarefas, 'etapas', '[]'::jsonb, 'feitas', 0, 'faltam', 0, 'texto', null);
  end if;
  v_p := public._agenda_tarefas_planejar(p_os, p_hoje, cf.modo_tarefas);
  for r in select t.* from public.os_tarefas t
            where t.service_order_id = p_os and t.estado in ('viva', 'feita', 'nao_se_aplica') order by t.ordem, t.id loop
    select d.resultado, d.dia, d.turno into v_ult from public.os_tarefas_dia d
     where d.tarefa_id = r.id and d.modo = cf.modo_tarefas and d.estado = 'planejada' and d.termina and d.resultado is not null
     order by d.dia desc, d.turno = 'tarde' desc, d.resultado_em desc limit 1;
    v_est := case when r.estado = 'feita' then 'feita' when r.estado = 'nao_se_aplica' then 'nao_se_aplica'
                  when v_ult.resultado = 'pendente' then 'pendente' when v_ult.resultado = 'sem_registro' then 'sem_confirmacao'
                  else 'falta' end;
    -- quando: o 1º meio-dia dela depois do último que já tem resultado (o pendente de hoje vai ao próximo)
    v_qd := (select (m ->> 'dia')::date from jsonb_array_elements(v_p -> 'meios') m, jsonb_array_elements(m -> 'itens') i
              where i ->> 'tarefa' = r.id::text
                and (v_ult.dia is null
                     or ((m ->> 'dia')::date, (m ->> 'turno') = 'tarde') > (v_ult.dia, v_ult.turno = 'tarde'))
              order by m ->> 'dia', m ->> 'turno' = 'tarde' limit 1);
    v_et := v_et || jsonb_build_array(jsonb_build_object(
      'n', jsonb_array_length(v_et) + 1, 'tarefa', r.id, 'texto', r.texto, 'estado', v_est, 'quando', v_qd, 'feita_em', r.feita_em,
      'feita_via', r.feita_via, 'pendente_vezes', r.pendente_vezes, 'pendente_desde', r.pendente_desde,
      'nova_no_escopo', r.nova_no_escopo, 'exige_texto', public._agenda_exigencia_texto(r.exige, null)));
    if v_est = 'feita' then
      v_feit := v_feit || r.texto;
      v_tot := v_tot + 1;
    elsif v_est <> 'nao_se_aplica' then
      v_tot := v_tot + 1;
      v_falt := v_falt || (r.texto || coalesce(' (' || case
        when v_est = 'pendente' then 'ficou faltando ' || public._agenda_tarefa_datas(r.pendente_desde, coalesce(r.pendente_ultimo, v_ult.dia))
                                     || coalesce('; vai ' || public._dia_curto(v_qd), '')
        when v_est = 'sem_confirmacao' then 'sem confirmação'
        when r.nova_no_escopo then 'entrou ' || public._dia_curto((r.criada_em at time zone 'America/Sao_Paulo')::date)
                                   || case when r.origem = 'dono' then ': você disse' else ': o orçamento aumentou' end
        else public._dia_curto(v_qd) end || ')', ''));
    end if;
  end loop;

  v_cabe := round(coalesce((v_p ->> 'sobra_no_prazo')::numeric, 0), 2) <= 0;
  v_cab := case when cf.modo_tarefas = 'ligado' then 'Etapas: ' else 'Etapas (em teste: a equipe ainda não recebe): ' end;
  v_nc := case when not v_cabe and v_p ->> 'prazo' is not null
               then format(' Até %s não cabe: falta cerca de %s e o plano %s.', public._dia_curto((v_p ->> 'prazo')::date),
                           public._agenda_dias(greatest(ceil((v_p ->> 'falta')::numeric), 1) / 2),
                           case when coalesce((v_p ->> 'meios_ate_prazo')::int, 0) = 0 then 'não tem mais dia até lá'
                                else 'tem ' || replace(trim_scale((v_p ->> 'meios_ate_prazo')::numeric / 2)::text, '.', ',') end) end;
  -- FASE 7c: (7c correção, achado 12) o prazo que já passou não vira "Até qui 10/09 não cabe" (a exceção tarefa:prazo, em
  -- _agenda_tarefas_excecoes, tem a mesma guarda: prazo >= hoje): com o prazo vencido, a leitura não diz nada de caber
  if (v_p ->> 'prazo')::date < p_hoje then
    v_nc := null;
    v_cabe := true;
  end if;
  -- FASE 7c: fim
  if cardinality(v_falt) = 0 then
    v_txt := v_cab || case when v_tot = 1 then 'a única feita.' else format('as %s feitas.', v_tot) end;
  else
    v_k := least(cardinality(v_falt), 3);
    loop
      v_txt := v_cab || format('%s de %s feitas', cardinality(v_feit), v_tot)
               || case when cardinality(v_feit) between 1 and 2 and v_k = least(cardinality(v_falt), 3)
                       then ' (' || public._agenda_lista(v_feit, null) || ')' else '' end
               || '. Falta: ' || array_to_string(v_falt[1:v_k], '; ')
               || case when cardinality(v_falt) > v_k then format('; e mais %s', cardinality(v_falt) - v_k) else '' end || '.'
               || coalesce(v_nc, '');
      exit when char_length(v_txt) <= 400 or v_k = 1;
      v_k := v_k - 1;
    end loop;
    v_txt := public._agenda_corta(v_txt, 400);
  end if;
  return jsonb_build_object('ok', true, 'modo', cf.modo_tarefas, 'etapas', v_et, 'feitas', cardinality(v_feit),
                            'faltam', v_tot - cardinality(v_feit), 'falta_meios', (v_p ->> 'falta')::numeric,
                            'prazo', v_p -> 'prazo', 'cabe', v_cabe, 'texto', v_txt);
end;
$function$;

comment on function public.os_tarefas_da_os(uuid, date) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.5, §16.6.8; R5.2-3): o feito × pendente da OS — {ok, modo, etapas [{n, tarefa, texto, estado (feita | falta | pendente | sem_confirmacao | nao_se_aplica), quando (o próximo dia planejado), feita_em, feita_via, pendente_vezes, pendente_desde, nova_no_escopo, exige_texto}], feitas, faltam, falta_meios, prazo, cabe, texto} — texto (≤ 400, a linha "Etapas" de _agenda_ver_os): "Etapas: 1 de 5 feitas (Diagnóstico de vazamento do sistema de água pressurizado). Falta: Conversão do sistema de refrigeração para 12V (sex 06/11); Substituição da tampa da boia (sex 06/11); Instalação do compressor e recarga de gás (entrou qua 04/11: o orçamento aumentou); e mais 1. Até sex 06/11 não cabe: falta cerca de 1,5 dia e o plano tem 1."; a pendente "(ficou faltando qua 04 e qui 05/11; vai sex 06/11)"; a sem registro "(sem confirmação)"; tudo feito "Etapas: as 4 feitas."; em teste "Etapas (em teste: a equipe ainda não recebe): …". modo_tarefas desligado ou sem etapa = texto nulo. Com login, só admin/financeiro (42501); sem login, só o service_role. STABLE; definer (a spec dizia invoker: o planejar não tem grant); authenticated e service_role. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 12): com o prazo já vencido (prazo < p_hoje), o texto não diz "Até … não cabe" e cabe = true (a guarda da exceção tarefa:prazo).';

-- agenda_dia_da_pessoa (de 20261102100550_agenda_fase7c_tarefas.sql)
create or replace function public.agenda_dia_da_pessoa(p_payee uuid, p_dia date, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  py       record;
  v_dono   boolean;
  v_nome   text;
  v_marc   jsonb;
  v_m      record;
  v_t      record;
  v_sit    text;
  v_dias   int[];
  v_dtxt   text;
  v_fonte  text;
  v_freq   numeric;
  v_nota   text;
  v_abr    constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  v_plu    constant text[] := array['às segundas', 'às terças', 'às quartas', 'às quintas', 'às sextas', 'aos sábados'];
  l1 text; l2 text;
  -- FASE 2: o plano da pessoa no dia
  v_plano  jsonb := '[]'::jsonb;
  v_itens  text[] := '{}';
  r        record;
  e        jsonb;
  v_outros text[];
  -- FASE 7c: (7c P8) o que a pessoa faz em cada OS do dia
  v_p8_tp   jsonb;
  v_p8_its  jsonb;
  v_p8_lst  text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achado 5) o "o que fazer" em teste
  c_c5_pref constant text := ' — em teste (a equipe ainda não recebe), o que fazer: ';
  v_c5_base  text;
  -- FASE 7c: fim
begin
  if p_hoje is null or p_dia is null then
    raise exception 'agenda_dia_da_pessoa: sem o dia' using errcode = '22004';
  end if;
  select p.* into py from public.payees p where p.id = p_payee;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei essa pessoa no cadastro.');
  end if;
  v_dono := py.id is not distinct from public._agenda_dono(null) or py.kind = 'socio';
  v_nome := case when v_dono then 'você' else public._agenda_nome_curto(py.name) end;

  if c.modo_proposta = 'ligado' then
    -- FASE 2: em 'ligado' o marcado da pessoa é o plano dela no dia (pelo payee, com ou sem login), com quem mais vai,
    -- e os compromissos com hora do login, se tiver.
    for r in select v.*, (select x from jsonb_array_elements(v.pessoas) x where (x ->> 'payee_id')::uuid = py.id limit 1) as eu
               from public.v_agenda_dia v
              where v.dia = p_dia
                and exists (select 1 from jsonb_array_elements(v.pessoas) x where (x ->> 'payee_id')::uuid = py.id)
              order by v.primeiro_inicio, v.numero, v.service_order_id loop
      v_outros := array(
        select case when coalesce((x ->> 'eh_dono')::boolean, false) then 'você ' else coalesce(x ->> 'nome', 'alguém da equipe') || ' ' end
               || public._agenda_parte_da_pessoa(x)
          from jsonb_array_elements(r.pessoas) with ordinality t(x, o)
         where (x ->> 'payee_id')::uuid is distinct from py.id
         order by o);
      v_itens := v_itens || (coalesce(r.cliente_curto || ' (' || r.numero || ')', r.numero) || ' '
                             || public._agenda_parte_da_pessoa(r.eu || jsonb_build_object('eh_dono', v_dono))
                             || case when r.reserva then ', reserva' else '' end
                             || coalesce(' (com ' || nullif(public._agenda_lista(v_outros, null), '') || ')', ''));
      v_plano := v_plano || jsonb_build_object('os', r.service_order_id, 'numero', r.numero, 'hora',
                                               to_char(r.primeiro_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
                                               'turnos', r.eu -> 'turnos', 'presenca', r.eu ->> 'presenca', 'reserva', r.reserva);
      -- FASE 7c: (7c P8, §16.5.5, §16.6.8; R5.2-2(a)) com modo_tarefas fora de desligado e a porta das etapas aberta, o item da OS ganha
      -- " — o que fazer: …" (o que ela faz naquela OS no dia, _agenda_tarefas_da_pessoa: 3 linhas, o item inteiro em até 200 letras; a
      -- etapa final com você: "— com você") e o plano ganha as etapas. Sem etapa: a de antes.
      if c.modo_tarefas <> 'desligado' and not r.reserva and (auth.uid() is null or public.is_admin_or_financial(auth.uid())) then
        if v_p8_tp is null then
          v_p8_tp := public._agenda_tarefas_da_pessoa(py.id, p_dia, p_hoje);
        end if;
        v_p8_its := (select jsonb_agg(i || jsonb_build_object('com', case when (i ->> 'com_dono')::boolean then 'você' end)
                                      order by (i ->> 'n')::int)
                       from jsonb_array_elements(coalesce(v_p8_tp -> 'itens', '[]'::jsonb)) i
                      where i ->> 'os' = r.service_order_id::text);
        if v_p8_its is not null then
          v_p8_lst := public._agenda_tarefas_lista_texto(v_p8_its, 3,
                        greatest(200 - char_length(v_itens[cardinality(v_itens)]) - char_length(' — o que fazer: '), 40));
          v_itens[cardinality(v_itens)] := v_itens[cardinality(v_itens)] || ' — o que fazer: ' || v_p8_lst;
          -- (7c correção, achado 5) em teste (modo_tarefas em sombra), o dono lê que é teste — como na linha "Etapas (em teste: a
          -- equipe ainda não recebe): …" da OS: ninguém recebeu a lista. A lista refeita para caber nas mesmas 200 letras.
          if c.modo_tarefas <> 'ligado' then
            v_c5_base := left(v_itens[cardinality(v_itens)], -char_length(' — o que fazer: ' || v_p8_lst));
            v_p8_lst := public._agenda_tarefas_lista_texto(v_p8_its, 3, greatest(200 - char_length(v_c5_base) - char_length(c_c5_pref), 40));
            v_itens[cardinality(v_itens)] := v_c5_base || c_c5_pref || v_p8_lst;
          end if;
          -- (7c: fim)
          v_plano := jsonb_set(v_plano, array[(jsonb_array_length(v_plano) - 1)::text],
                               (v_plano -> -1) || jsonb_build_object('etapas', v_p8_its));
        end if;
      end if;
      -- FASE 7c: fim
    end loop;
    if py.app_user_id is not null then
      for e in select x from jsonb_array_elements(public._agenda_marcados(p_dia, p_dia, p_hoje, null, py.app_user_id)) x
                where x ->> 'tipo' = 'compromisso' loop
        v_itens := v_itens || (e ->> 'texto_dia');
      end loop;
    end if;
    v_marc := v_plano;
  else
    v_marc := case when py.app_user_id is null then '[]'::jsonb
                   else public._agenda_marcados(p_dia, p_dia, p_hoje, case when v_dono then null else py.app_user_id end,
                                                py.app_user_id) end;
    v_itens := array(select x ->> 'texto_dia' from jsonb_array_elements(v_marc) with ordinality t(x, o) order by o);
  end if;

  -- A situação do dia pela grade (manhã e tarde).
  select bool_and(g.situacao = 'fim_de_semana') as fds, bool_and(g.situacao = 'feriado') as fer,
         bool_and(g.situacao = 'indisponivel') as indisp, bool_or(g.situacao = 'indisponivel') as meio_indisp,
         bool_and(g.situacao = 'sem_padrao') as sem,
         max(g.motivo) filter (where g.situacao in ('fim_de_semana', 'feriado')) as motivo_cal,
         max(g.motivo) filter (where g.situacao = 'indisponivel') as motivo_ind,
         bool_or(g.situacao = 'indisponivel' and g.turno = 'manha') as manha_ind,
         count(*) as n
    into v_t
    from public.agenda_capacidade(p_dia, p_dia, p_hoje) g
   where g.payee_id = py.id;

  -- O padrão: os dias da semana em que a pessoa costuma vir (o que está em vigor em agenda_disponibilidade).
  v_dias := array(select distinct x from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null
                     and d.situacao in ('disponivel', 'confirmada') and d.turno is null
                   order by x);

  v_sit := case
    when coalesce(v_t.n, 0) = 0 then
      case when extract(isodow from p_dia) = 7 then 'domingo'
           when extract(isodow from p_dia) = 6 and not c.sabado_util then 'sábado só quando vocês combinam'
           when public.agenda_feriado(p_dia) is not null then 'é feriado (' || public.agenda_feriado(p_dia) || ')'
           else null end
    when v_t.fds then v_t.motivo_cal
    when v_t.fer then 'é feriado (' || v_t.motivo_cal || ')'
    when v_t.indisp then case when v_dono then 'você não fica em campo' else 'não vem' end
                         || coalesce(' (' || nullif(v_t.motivo_ind, 'não vem') || ')', '')
    when v_t.meio_indisp then case when v_t.manha_ind then 'só à tarde' else 'só de manhã' end
    -- Tem padrão em outros dias e não neste: "às segundas não costuma vir" (o "não sei" fica para quem não tem padrão).
    when v_t.sem and not v_dono and cardinality(v_dias) > 0
         and not (extract(isodow from p_dia)::int = any (v_dias)) and extract(isodow from p_dia) between 1 and 6
      then v_plu[extract(isodow from p_dia)::int] || ' não costuma vir'
    when v_t.sem and not v_dono then 'não sei se vem: não há padrão de dias'
    else null end;

  -- FASE 2: o texto sai de v_itens (o plano e os compromissos em 'ligado'; o marcado de sempre fora dele)
  if cardinality(v_itens) = 0 then
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' não tem nada marcado';
  else
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' tem ' || public._agenda_lista(v_itens, 5);
  end if;
  l1 := l1 || coalesce(' — ' || v_sit, '') || '.';

  select case when bool_and(d.origem = 'historico') then format('pelas diárias das últimas %s semanas', c.medicao_semanas)
              when bool_or(d.origem = 'dono') then 'você disse'
              else 'combinado' end
    into v_fonte
    from public.agenda_disponibilidade d
   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null and d.situacao in ('disponivel', 'confirmada');
  select d.frequencia, d.nota into v_freq, v_nota
    from public.agenda_disponibilidade d
   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null and d.origem = 'historico'
     and d.dias_semana @> array[extract(isodow from p_dia)::smallint]
   order by d.criado_em desc, d.id desc limit 1;

  if cardinality(v_dias) = 0 then
    l2 := case when v_dono then 'Você ainda não disse quais dias fica em campo.'
               else 'Não sei os dias em que costuma vir: não há diárias recentes.' end;
  else
    v_dtxt := case
      when cardinality(v_dias) = 1 then 'só ' || v_plu[v_dias[1]]
      when v_dias[cardinality(v_dias)] - v_dias[1] + 1 = cardinality(v_dias) and cardinality(v_dias) >= 3 then
        format('de %s a %s', v_abr[v_dias[1]], v_abr[v_dias[cardinality(v_dias)]])
      else public._agenda_lista(array(select v_abr[x] from unnest(v_dias) x), null) end;
    l2 := case when v_dono then 'Você costuma ficar em campo ' else 'Costuma vir ' end || v_dtxt
          || ' (' || v_fonte
          || case when v_freq is not null and v_freq < 1 and v_nota ~ '[0-9]+(,[0-9]+)? de [0-9]+ '
                  then ': ' || (regexp_match(v_nota, '([0-9]+(,[0-9]+)? de [0-9]+ [^ (]+)'))[1] else '' end
          || ').';
  end if;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1 || ' ' || l2], c.texto_max),
    'dados', jsonb_build_object('pessoa', v_nome, 'dia', p_dia, 'marcados', v_marc, 'situacao', v_sit, 'dias_semana', v_dias)
             -- FASE 2: o plano da pessoa no dia
             || case when c.modo_proposta = 'ligado' then jsonb_build_object('plano', v_plano) else '{}'::jsonb end);
end;
$function$;

comment on function public.agenda_dia_da_pessoa(uuid, date, date) is
  'Agenda de Produção (Fase 1, P4; Fase 2, P5): "o que o Roberto faz amanhã?" — o marcado da pessoa no dia (fora de ''ligado'': OS em que é técnica, compromisso com hora; em ''ligado'': o plano dela pelo payee, com ou sem login, e quem mais vai — "Qua 04/11, Roberto tem Vanderlei (OS-00069) o dia todo (com você abrindo)" — e os compromissos do login), a situação pela grade (sábado só quando vocês combinam, domingo, feriado, não vem, só de manhã/à tarde, sem padrão) e o padrão de dias ("costuma vir de seg a sex (pelas diárias das últimas 8 semanas: 3 de 5 segundas)"). Sem artigo de gênero antes do nome. {ok, texto, dados}. FASE 7c (P8, §16.5.5, §16.6.8): em ligado, com modo_tarefas fora de desligado e a porta das etapas aberta, o item de cada OS ganha " — o que fazer: …" (o que a pessoa faz nela no dia: _agenda_tarefas_da_pessoa, 3 linhas, o item em até 200 letras; "— com você" na etapa final com o dono) e o plano ganha etapas. Sem etapa, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 5): em teste (modo_tarefas em sombra), o item diz " — em teste (a equipe ainda não recebe), o que fazer: …" (ninguém recebeu a lista); ligado, o de antes.';

-- _agenda_linhas_do_fechamento (de 20261102100550_agenda_fase7c_tarefas.sql)
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
  -- FASE 7c: (7c P5, R5.4 item 4) a linha (n) com as perguntas de quem faz o quê
  v_7c_on    boolean;
  v_7c_7b    boolean;
  v_7c_q     record;
  v_7c_eq    boolean;
  v_7c_marc  text;
  v_7c_exig  text;
  v_7c_ate   timestamptz;
  -- FASE 7c: fim
  -- FASE 7c: (7c P8, R5.4 item 4, R5.2-2(b)) as perguntas das etapas na linha (n) e a linha (o) das etapas
  v_p8_on     boolean;
  v_p8_q      record;
  v_p8_quem   boolean;
  v_p8_pess   record;
  v_p8_h      jsonb;
  v_p8_a      jsonb;
  v_p8_hi     jsonb;
  v_p8_ai     jsonb;
  v_p8_nomes  text[] := '{}';
  v_p8_nfone  int;
  v_p8_nrot   int;
  v_p8_hoje   jsonb := '[]'::jsonb;
  v_p8_amanha jsonb := '[]'::jsonb;
  v_p8_txt    text;
  v_p8_curto  text;
  v_p8_alta   boolean;
  v_p8_k      int;
  v_p8_g      record;
  v_p8_parte  text[];
  v_p8_dia    text;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achados 14, 8 e 2) a 7b que espera a vez dela, a forma curta do cliente e a (n) que ficou de fora
  c_c2_dias   constant int := 2;    -- estrutural: os dias úteis que a pergunta de quem faz o quê espera sem ser vista antes de subir
  c_c2_perda  constant int := 77;   -- estrutural: acima das perguntas do gestor (76), abaixo da compra e da decisão (80)
  v_c14_pula  boolean;
  v_c8_agora  timestamptz;
  v_c8_tipo   text;
  v_c8_env    timestamptz;
  v_c8_qid    uuid;
  v_c8_nome   text;
  v_c8_n      int;
  v_c8_curto  text;
  -- FASE 7c: fim
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
  -- (7c P5, R5.4 item 4, R5.10-8) o portão da linha separado por etapa: o bloco roda com a 7b (modo_dias ou modo_cadastro) OU com
  -- a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado; dentro dele, as perguntas da 7b só entram com o portão da 7b
  -- (v_7c_7b) e as de quem faz o quê só com o da 7c (v_7c_on). v_7b_on volta a ser só o da 7b logo depois do bloco: a pergunta de fato
  -- (e) exclui só os tipos que a (n) levou (sem isso, com a 7b desligada e a 7c em teste, a chamada da 7a sairia da (e), perda 30,
  -- para a (n), perda 75, e o texto do dono mudaria).
  v_7c_on := cf.modo_habilidade_propor <> 'desligado' or cf.modo_habilidade <> 'desligado';
  v_7c_7b := v_7b_on;
  v_7b_on := v_7b_on or v_7c_on;
  -- (7c: fim)
  -- (7c P8, R5.4 item 4) e com as etapas (modo_tarefas) fora de desligado: as perguntas das etapas (tarefa) só com o portão delas
  v_p8_on := cf.modo_tarefas <> 'desligado';
  v_7b_on := v_7b_on or v_p8_on;
  -- (7c: fim)
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
      -- (7c correção, achado 14) a 7b não gasta a vez dela por causa da 7c: sem nenhuma pergunta da 7b que perca hoje (nunca vista, o
      -- veto ou o prazo de hoje) e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia — a da
      -- 7c vai primeiro e inteira (conta como vista) e a chamada não é contada como mostrada num dia que não é o dela. Antes, com a de
      -- quem faz o quê só como "Também" (não conta), a perda 75 dela fazia a chamada sair e gastar as 2 vezes antes do dia em que vence,
      -- e quem faz o quê só era vista quando a chamada saía da linha. Com a 7b perdendo hoje, a de antes (a 7b primeiro). Sem a 7c, a de antes.
      v_c14_pula := v_7c_7b and (v_7c_on or v_p8_on)
        and not exists (select 1 from public.agenda_perguntas x
                         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
                           and x.mostrada_vezes < cf.perguntas_vezes_max
                           and not exists (select 1 from public.agenda_dono_avisos v
                                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                           and (x.mostrada_vezes = 0
                                or (x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                or x.perda_em is not distinct from p_hoje))
        and exists (select 1 from public.agenda_perguntas x
                     where x.estado = 'aberta' and x.modo = m and not x.critica
                       and ((v_7c_on and x.tipo = 'habilidade') or (v_p8_on and x.tipo = 'tarefa'))
                       and x.mostrada_vezes < cf.perguntas_vezes_max
                       and not exists (select 1 from public.agenda_dono_avisos v
                                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
                       and (x.mostrada_vezes = 0
                            or (x.tipo = 'habilidade'
                                and ((x.veto_ate is not null and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                     or x.perda_em is not distinct from p_hoje))
                            or (x.tipo = 'tarefa' and x.chave not like 'tarefa:quem:%' and x.perda_em is not null and x.perda_em <= v_am1)));
      -- (7c: fim)
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
        -- (7c P5) as perguntas da equipe da 7b só com o portão da 7b (o bloco pode estar rodando só pela 7c)
        continue when not v_7c_7b;
        -- (7c: fim)
        -- (7c correção, achado 14) neste dia as da 7b esperam o dia delas (acima)
        continue when v_c14_pula;
        -- (7c: fim)
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
      -- (7c P5, R5.4 item 4, R5.1-6, R5.10-7) as perguntas de quem faz o quê (habilidade), depois das da 7b: primeiro a da equipe
      -- (habilidade:equipe:…), depois as de OS (habilidade:os:…), e a mais antiga; só com o portão da 7c. A 1ª da linha vai inteira; as
      -- outras curtas, até c_max_perg ("Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)."; a de
      -- OS: "Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).").
      -- A da equipe que vai só como "Também" não conta como mostrada (sai de pergunta_ids: o achado 17 da 7b estendido) e sai inteira no
      -- fechamento em que vier primeiro; a de OS conta (vai com a pergunta toda, como o telefone e o contato). Na forma curta
      -- (texto_curto, a que o Secretário cheio usa — o registro não sabe qual forma saiu), a da equipe leva o que foi marcado e, quando é
      -- contada e vence (modo ligado), o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00,
      -- fica assim" (a data que _agenda_habilidade_vetos grava depois do registro: o veto_ate, ou _agenda_veto_ate do dia de hoje). O
      -- modo de cada uma é o de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade), que a linha não
      -- pode chamar (é só do service_role; a linha é lida pelo painel). A perda é a da (n): 75 enquanto alguma nunca foi vista inteira ou
      -- perde hoje.
      if v_7c_on then
        for v_7c_q in
          select x.id, x.tipo, x.chave, x.texto, x.modo, x.mostrada_vezes, x.veto_ate, x.perda_em,
                 coalesce(public._agenda_rotulo_da_os(x.service_order_id), '') as nome,
                 case when x.chave like 'habilidade:os:%' then cf.modo_habilidade else cf.modo_habilidade_propor end as modo_agora
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'habilidade'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'habilidade:equipe:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_7c_eq := v_7c_q.chave like 'habilidade:equipe:%';
          -- o que foi marcado (as propostas vivas da pergunta, lidas sob a RLS de agenda_etiquetas) e o que a OS pede
          v_7c_marc := case when v_7c_eq then nullif(public._agenda_lista(array(
                         select public._agenda_nome_curto(py.name) || ' ' || split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1)
                           from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
                          where e.pergunta_id = v_7c_q.id and e.estado = 'proposta'
                          order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                   public._agenda_nome_curto(py.name), e.id), null), '') end;
          v_7c_exig := case when not v_7c_eq then substring(v_7c_q.texto from ': o serviço pede (.*), e nas próximas ') end;
          v_7b_curto := case when v_7c_eq then 'quem faz o quê' || coalesce(' — marquei: ' || v_7c_marc, '')
                             else format('%s: falta %s', v_7c_q.nome, coalesce(v_7c_exig, 'quem o serviço pede')) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_7c_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := case
              when v_7c_eq then format('Também: quem faz o quê (%sresponda em *agenda pendências*).',
                                       coalesce('marquei: ' || v_7c_marc || '; ', ''))
              else format('Também: %s: falta %s; quem pode? (responda em *agenda pendências*).', v_7c_q.nome,
                          coalesce(v_7c_exig, 'quem o serviço pede')) end;
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          if jsonb_array_length(v_7b_ids) > 1 and v_7c_eq then
            v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
          end if;
          if v_7c_eq and v_7c_q.modo = 'ligado' and v_7b_ids ? v_7c_q.id::text then
            v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
            v_7b_curto := v_7b_curto || format('; sem resposta até %s às %s, fica assim',
                                               public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                               to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
          end if;
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and v_7c_q.modo_agora = 'ligado';
          v_7b_perde := v_7b_perde or v_7c_q.mostrada_vezes = 0
                        or (v_7c_q.veto_ate is not null and (v_7c_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                        or v_7c_q.perda_em is not distinct from p_hoje;
        end loop;
      end if;
      -- (7c: fim)
      -- (7c P8, R5.4 item 4, R5.2-2(c)) as perguntas das etapas (tarefa), depois das de quem faz o quê: primeiro a de quem faça a etapa de
      -- risco (tarefa:quem:<os>), depois a de prazo (tarefa:prazo:<os>), e a mais antiga; só com o portão das etapas. A 1ª da linha vai
      -- inteira; as outras curtas, até c_max_perg ("Também: Lenine: quem vai junto em "…"? (responda em *agenda pendências*)."). As duas
      -- contam como mostradas (vão com a pergunta toda, como a de OS de quem faz o quê). O modo é o de _agenda_modo_da_pergunta
      -- (modo_tarefas), que a linha não pode chamar. A de prazo cujo prazo (perda_em) é hoje ou o próximo dia útil perde hoje.
      if v_p8_on then
        for v_p8_q in
          select x.id, x.chave, x.texto, x.mostrada_vezes, x.perda_em,
                 coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = x.service_order_id),
                          public._agenda_rotulo_da_os(x.service_order_id), '') as cli
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'tarefa'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'tarefa:quem:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_p8_quem := v_p8_q.chave like 'tarefa:quem:%';
          v_7b_curto := case when v_p8_quem then format('%s: quem vai junto%s?', v_p8_q.cli,
                                                         coalesce(' em ' || substring(v_p8_q.texto from '"[^"]+"'), ''))
                             else format('%s: as etapas não cabem até %s', v_p8_q.cli, public._dia_curto(v_p8_q.perda_em)) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_p8_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := format('Também: %s (responda em *agenda pendências*).', v_7b_curto);
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_p8_q.id);
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and cf.modo_tarefas = 'ligado';
          v_7b_perde := v_7b_perde or v_p8_q.mostrada_vezes = 0
                        or (not v_p8_quem and v_p8_q.perda_em is not null and v_p8_q.perda_em <= v_am1);
        end loop;
      end if;
      -- (7c: fim)
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
  -- FASE 7c: (7c P5, R5.10-8) o portão da 7b volta a ser só o dela: a (e) exclui as perguntas da 7b só com ele (e as de quem faz o quê
  -- só com o da 7c, abaixo)
  v_7b_on := v_7c_7b;
  -- FASE 7c: fim
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
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
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
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
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

  -- FASE 7c: (7c P8, R5.2-2(b), R5.10-6, -10, -13) (o) as etapas de quem não recebe pelo WhatsApp (sem telefone pela régua da 7a,
  -- _agenda_equipe_tem_telefone — a mesma do registro —, ou fora da lista da rotina) com etapa no plano de hoje ou do próximo dia útil: o
  -- que hoje devia ficar pronto (o dono passa e confere) e o que fazer amanhã, sem números (as listas do dia e a da OS numeram
  -- diferente), até c_max, cortando por etapa inteira ("e mais N"); o texto_curto para o Secretário cheio. Perda 75 só quando amanhã é
  -- o último dia de uma OS (a cobrança da véspera) ou volta primeiro uma pendente dita; senão 70 (a etapa de risco sozinha não sobe a
  -- perda). Tipo dia, sem pergunta: nada vence por ela. Em teste, modo sombra e "Em teste: " (vai ao detalhe, nunca ao texto do dono).
  -- Só com a porta das etapas aberta (o administrador ou o financeiro logado, ou sem login).
  if cf.modo_tarefas <> 'desligado' and (auth.uid() is null or public.is_admin_or_financial(auth.uid())) then
    for v_p8_pess in
      select x.payee_id, x.nome, public._agenda_equipe_tem_telefone(x.payee_id) as fone,
             exists (select 1 from public.agenda_equipe_contato c
                      where c.payee_id = x.payee_id and c.recebe_rotina and c.parou_em is null) as rotina
        from (select distinct a.payee_id, public._agenda_nome_curto(py.name) as nome
                from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
               where a.dia in (p_hoje, v_am1) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
                 and a.payee_id is distinct from public._agenda_dono(null)) x
       order by x.nome, x.payee_id
    loop
      continue when v_p8_pess.fone and v_p8_pess.rotina;
      v_p8_h := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, p_hoje, p_hoje);
      v_p8_a := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, v_am1, p_hoje);
      -- hoje: o que terminava e ainda não tem resultado (uma vez por etapa)
      v_p8_hi := coalesce((select jsonb_agg(i order by (i ->> 'n')::int) from jsonb_array_elements(v_p8_h -> 'itens') i
                            where (i ->> 'termina')::boolean and i -> 'resultado' = 'null'::jsonb
                              and not exists (select 1 from jsonb_array_elements(v_p8_hoje) j where j ->> 'tarefa' = i ->> 'tarefa')),
                           '[]'::jsonb);
      -- amanhã: o que a pessoa faz, por OS, com o último dia e a pendente dita que volta primeiro
      v_p8_ai := coalesce((select jsonb_agg(i || jsonb_build_object('nome', v_p8_pess.nome, 'payee', v_p8_pess.payee_id,
                                  'com', case when (i ->> 'com_dono')::boolean then 'você' end,
                                  'ultimo', (v_p8_a -> 'ultimo_dia') @> jsonb_build_array(jsonb_build_object('os', i ->> 'os')),
                                  'pdita', exists (select 1 from public.os_tarefas t where t.id = (i ->> 'tarefa')::uuid
                                                      and t.estado = 'viva' and t.pendente_vezes > 0))
                                order by (i ->> 'n')::int)
                           from jsonb_array_elements(v_p8_a -> 'itens') i), '[]'::jsonb);
      -- só quem tem o que conferir hoje ou o que fazer amanhã entra no "Etapas (… não tem telefone …)"
      continue when jsonb_array_length(v_p8_hi) = 0 and jsonb_array_length(v_p8_ai) = 0;
      v_p8_nomes := v_p8_nomes || v_p8_pess.nome;
      v_p8_nfone := coalesce(v_p8_nfone, 0) + case when v_p8_pess.fone then 0 else 1 end;
      v_p8_nrot := coalesce(v_p8_nrot, 0) + case when v_p8_pess.rotina then 0 else 1 end;
      v_p8_hoje := v_p8_hoje || v_p8_hi;
      v_p8_amanha := v_p8_amanha || v_p8_ai;
    end loop;
    if jsonb_array_length(v_p8_hoje) > 0 or jsonb_array_length(v_p8_amanha) > 0 then
      v_p8_dia := case when v_am1 = p_hoje + 1 then 'Amanhã (' || public._dia_curto(v_am1) || ')'
                       else public._agenda_maiuscula(public._dia_curto(v_am1)) end;
      -- monta com até v_p8_k etapas por lista; corta por etapa inteira até caber em c_max
      v_p8_k := 5;
      loop
        v_p8_txt := format('Etapas (%s %s: quem passa e confere é você).', public._agenda_lista(v_p8_nomes, null),
                           case when v_p8_nfone = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não tem telefone' else 'não têm telefone' end
                                when v_p8_nrot = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não está na rotina da equipe' else 'não estão na rotina da equipe' end
                                else 'não recebem pelo WhatsApp' end);
        for v_p8_g in select i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_hoje) i group by i ->> 'cliente' order by 2 loop
          v_p8_txt := v_p8_txt || format(' Hoje no %s devia ficar pronto: %s.', v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, false, false));
        end loop;
        if jsonb_array_length(v_p8_hoje) > 0 then
          v_p8_txt := v_p8_txt || format(' Se faltou alguma, me diga qual (ex.: no %s falta "%s").', v_p8_hoje -> 0 ->> 'cliente',
                                         lower(left(v_p8_hoje -> 0 ->> 'texto', 1)) || substr(v_p8_hoje -> 0 ->> 'texto', 2));
        end if;
        for v_p8_g in select i ->> 'nome' as nome, i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             bool_or((i ->> 'ultimo')::boolean) as ult, jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                       order by i ->> 'nome', 3 loop
          v_p8_txt := v_p8_txt || format(' %s, %s no %s: %s.', v_p8_dia, v_p8_g.nome, v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, true, false))
                      || case when v_p8_g.ult then ' É o último dia: tem que ficar tudo pronto.' else '' end;
        end loop;
        v_p8_txt := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end || v_p8_txt;
        exit when char_length(v_p8_txt) <= c_max or v_p8_k = 1;
        v_p8_k := v_p8_k - 1;
      end loop;
      v_p8_txt := public._agenda_corta(v_p8_txt, c_max);
      -- a forma curta (o Secretário cheio)
      v_p8_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                      then format('amanhã é o último dia do %s (%s, %s)', i ->> 'cliente', i ->> 'nome',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                      else format('amanhã, %s no %s (%s)', i ->> 'nome', i ->> 'cliente',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                            from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                           order by i ->> 'nome', min((i ->> 'n')::int))
                  || case when jsonb_array_length(v_p8_hoje) > 0
                          then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
      v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                    || 'Etapas: ' || array_to_string(v_p8_parte, '; ') || '.'
                    || case when jsonb_array_length(v_p8_amanha) > 0
                            then format(' Pergunte o que o %s faz amanhã.', v_p8_amanha -> 0 ->> 'nome') else '' end;
      v_p8_alta := exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean or (i ->> 'pdita')::boolean);
      v_out := v_out || (jsonb_build_object('tipo', 'dia', 'texto', v_p8_txt, 'perda', case when v_p8_alta then 75 else 70 end,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_tarefas = 'ligado' then 'ligado' else 'sombra' end)
        || case when char_length(v_p8_curto) < char_length(v_p8_txt) then jsonb_build_object('texto_curto', v_p8_curto)
                else '{}'::jsonb end);
    end if;
  end if;
  -- FASE 7c: fim
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
  -- FASE 7c: (7c correção, achados 8 e 2) o fechamento cheio com uma linha da 7c ligada que perde hoje (a (o) "Etapas" ou a (n) com
  -- uma pergunta de quem faz o quê ou das etapas). O Secretário (textoDaTarde) encolhe só as linhas que têm forma curta antes de tirar
  -- uma, e a do cliente (75, a mensagem que espera *manda cliente*, até 600 letras) não tinha: com ela, a (o) e a (n) caíam (a semana
  -- real da revisão, 5 fechamentos com uma linha de cliente). Sem a 7c ligada (desligada ou em teste), a de antes, byte a byte.
  if exists (select 1 from jsonb_array_elements(v_out) x
              where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int >= 75
                and ((x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas%')
                     or exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                  join public.agenda_perguntas qq on qq.id = u.id::uuid
                                 where qq.tipo in ('habilidade', 'tarefa')))) then
    -- (8) a mensagem ao cliente ganha a forma curta (a coleta só a usa no fechamento enxuto, com linha garantida prestes a sair): quem,
    -- o tipo, quando sai e a palavra — "Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter
    -- 10/11 às 09:00); *agenda clientes* mostra." — com a mesma 1ª mensagem de _agenda_cliente_fechamento
    if cf.modo_cliente = 'ligado' then
      v_c8_agora := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
      select m2.tipo, m2.enviar_em, q2.id,
             public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)), count(*) over ()
        into v_c8_tipo, v_c8_env, v_c8_qid, v_c8_nome, v_c8_n
        from public.agenda_cliente_mensagens m2
        join public.agenda_perguntas q2 on q2.id = m2.pergunta_id
        join public.clients cl on cl.id = m2.client_id
       where m2.modo = 'ligado' and m2.estado = 'aguardando_dono' and m2.aprovacao = 'pedida'
         and q2.tipo = 'cliente_aprovar' and q2.estado = 'aberta'
         and (m2.enviar_em at time zone 'America/Sao_Paulo')::date <= public._agenda_cliente_dia_seguinte(p_hoje)
       order by m2.enviar_em, cl.name, m2.tipo, m2.id
       limit 1;
      if v_c8_qid is not null then
        v_c8_curto := case when v_c8_n > 1
          then format('Mensagem para %s (%s) e mais %s esperam *manda cliente* (a 1ª sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_n - 1, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora))
          else format('Mensagem para %s (%s) espera *manda cliente %s* (sai %s); *agenda clientes* mostra.', v_c8_nome,
                      public._agenda_cliente_tipo_texto(v_c8_tipo), v_c8_nome, public._agenda_cliente_quando_texto(v_c8_env, v_c8_agora)) end;
        v_out := (select coalesce(jsonb_agg(case when x ->> 'tipo' = 'cliente' and (x ->> 'perda')::int = 75
                                                  and x ->> 'pergunta_id' = v_c8_qid::text and not x ? 'texto_curto'
                                                  and char_length(v_c8_curto) < char_length(x ->> 'texto')
                                             then x || jsonb_build_object('texto_curto', v_c8_curto) else x end order by o), '[]'::jsonb)
                    from jsonb_array_elements(v_out) with ordinality t(x, o));
      end if;
    end if;
    -- (2) a (n) com uma pergunta de quem faz o quê ou das etapas, ligada, contada na linha e nunca vista há c_c2_dias dias úteis (ela
    -- perdeu c_c2_dias fechamentos: com a compra (80) e as perguntas do gestor (76), as três não cabem nem na forma curta, e a de menor
    -- perda saía todo dia — o prazo nunca corria e a proposta nunca valia) sobe a c_c2_perda: neste dia sai a de menor perda das outras
    -- (a das perguntas do gestor, ou uma de 75), uma vez, e no dia seguinte, vista, ela volta à de sempre. Não sobe se a linha que ela
    -- tiraria (perda 76 a 79) perde algo hoje: a ficha de amanhã (ficha_estimativa) ou um prazo (veto ou perda) de hoje.
    if not exists (select 1 from jsonb_array_elements(v_out) x
                    where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int between 76 and 79
                      and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                    join public.agenda_perguntas qq on qq.id = u.id::uuid
                                   where qq.tipo = 'ficha_estimativa'
                                      or (qq.veto_ate is not null and (qq.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                                      or qq.perda_em is not distinct from p_hoje)) then
      v_out := (select coalesce(jsonb_agg(case when x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 75
                                                and exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'pergunta_ids', '[]'::jsonb)) u(id)
                                                              join public.agenda_perguntas qq on qq.id = u.id::uuid
                                                             where qq.tipo in ('habilidade', 'tarefa') and qq.modo = 'ligado'
                                                               and qq.estado = 'aberta' and qq.mostrada_vezes = 0
                                                               and public.agenda_du_entre((qq.criada_em at time zone 'America/Sao_Paulo')::date,
                                                                                          p_hoje) >= c_c2_dias)
                                           then jsonb_set(x, '{perda}', to_jsonb(c_c2_perda)) else x end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_out) with ordinality t(x, o));
    end if;
  end if;
  -- FASE 7c: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o R5.10-7): na linha (n) da equipe, a forma curta (texto_curto, a que o Secretário cheio usa, e o registro conta as pergunta_ids da linha sem saber qual forma saiu) leva, em cada pergunta que vence, o prazo e o "sigo assim" — "Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra." —, com a data que o vencimento grava: a chamada contada na linha, com o cadastro fora de desligado, em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (ou o veto_ate já gravado); a dos dias da semana, com modo_dias fora de desligado, no prazo da semana dela (perda_em, hora_do_plano − equipe_dias_fechar_antes). O telefone e o contato não vencem: como antes. A forma longa e o resto, byte a byte. FASE 7c (P5, R5.4 item 4, R5.1-6, R5.10-7/-8): o portão da linha (n) passa a "a 7b (modo_dias ou modo_cadastro) OU a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado"; dentro dela, as perguntas da 7b só com o portão da 7b e, depois delas, as de quem faz o quê (habilidade: primeiro a habilidade:equipe, depois as habilidade:os) só com o da 7c, com o modo de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade). A da equipe que vai só como "Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)." fica fora de pergunta_ids (não conta como vista); a de OS ("Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).") conta. A forma curta leva o que foi marcado e, na da equipe contada e ligada, o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00, fica assim" (o veto_ate, ou _agenda_veto_ate do dia de hoje: a data que _agenda_habilidade_vetos grava depois do registro). A pergunta de fato (e) exclui as da 7b só com o portão da 7b e as de quem faz o quê só com o da 7c. Com os modos da 7c desligados, a saída de antes, byte a byte (com a 7b desligada e em teste). FASE 7c (P8, R5.4 item 4, R5.2-2(b) e (c)): com modo_tarefas fora de desligado, a linha (n) leva também as perguntas das etapas (tarefa:quem:<os>, depois tarefa:prazo:<os>; a de prazo que vence hoje ou no próximo dia útil perde hoje), só com o portão delas, e a (e) não as repete; e a linha (o) das etapas (tipo dia; até 480, sem números): a quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) com etapa hoje ou no próximo dia útil — "Etapas (Alex não tem telefone: quem passa e confere é você). Hoje no Lenine devia ficar pronto: …. Se faltou alguma, me diga qual (…). Amanhã (qui 05/11), Alex no Lenine: Terminar: …; … — com você. É o último dia: tem que ficar tudo pronto." —, texto_curto "Etapas: amanhã é o último dia do Lenine (Alex, 2 etapas); hoje, 2 para conferir. Pergunte o que o Alex faz amanhã.", perda 75 só com o último dia de uma OS amanhã ou com uma pendente dita que volta primeiro (senão 70), sem pergunta; em teste, modo sombra e "Em teste: ". Com modo_tarefas desligado, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7c (20261102100580): (achado 14) na linha (n), sem nenhuma pergunta da 7b que perca hoje e com uma de quem faz o quê ou das etapas que perde hoje, as da 7b ficam fora da linha neste dia (a da 7c vai primeiro, inteira, e conta como vista; a chamada não gasta a vez dela num dia que não é o seu); (achado 8) com uma linha da 7c ligada de perda >= 75 (a (o) "Etapas" ou a (n) com pergunta de quem faz o quê ou das etapas), a linha do cliente de perda 75 ganha a forma curta ("Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter 10/11 às 09:00); *agenda clientes* mostra."; com mais de uma, "… e mais N esperam *manda cliente* (a 1ª sai …) …"), para o Secretário cheio encolher a do cliente antes de tirar a da 7c; (achado 2) a (n) com uma pergunta de quem faz o quê ou das etapas ligada, contada, aberta e nunca vista há 2 dias úteis ou mais sobe de 75 a 77 (acima das perguntas do gestor, abaixo da compra e da decisão), salvo se uma linha de perda 76 a 79 perde algo hoje (a ficha de amanhã, um veto ou um prazo de hoje). Sem a 7c ligada, a de antes, byte a byte.';

-- _agenda_habilidade_perguntas_os (de 20261102100400_agenda_fase7c_rodada.sql)
create or replace function public._agenda_habilidade_perguntas_os(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_bits constant int[] := array[1, 2, 4, 8];
  cf     public.agenda_config := public._agenda_cfg();
  v_pid  uuid;
  v_alvo uuid[];
  v_fora jsonb;
  f      jsonb;
  v_os   uuid;
  v_ex   jsonb;
  v_pede text;
  v_bit  int;
  v_resp text;
  v_cli  text;
  v_ab   int := 0;
  v_res  int := 0;
  -- FASE 7c: (7c correção, achado 7) as propostas dos últimos dias
  c_c7_dias constant int := 7;   -- estrutural: a janela das propostas lidas (uma semana de rodadas, vigias e gestores)
  -- FASE 7c: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_habilidade_perguntas_os: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  -- a última proposta do motor de hoje (qualquer escopo)
  select x.id, x.os_alvo, x.fora into v_pid, v_alvo, v_fora
    from public.agenda_propostas x
   where (x.parametros ->> 'p_hoje')::date = p_hoje
   order by x.criada_em desc, x.id desc
   limit 1;
  -- FASE 7c: (7c correção, achado 7) cada OS pela ÚLTIMA proposta que a cita (no alvo ou no fora), das criadas nos últimos c_c7_dias
  -- dias até p_agora — não só "a última de hoje": a rodada do dia roda antes da vigia (o passo 0b2a antes do 0c) e o gestor só às :53,
  -- então a OS que a vigia ou o gestor tirava por falta de quem o serviço pede nunca ganhava a pergunta (a Vera, tirada na sex 06/11
  -- às 16:15, ficava sem pergunta na sex e na seg; ela só aparecia no *agenda gestor*). A OS cuja última citação a deixa de fora por
  -- habilidade vai ao fora (a pergunta nasce, se não houver uma aberta nem uma criada depois daquela proposta); a que a última citação
  -- põe no plano vai ao alvo (a aberta fecha: "coube"); a que ficou de fora por outro motivo, a nenhum (a aberta continua, como antes).
  with px as (
    select x.id, x.criada_em, x.os_alvo, x.fora from public.agenda_propostas x
     where x.criada_em <= p_agora and x.criada_em > p_agora - make_interval(days => c_c7_dias)
  ), cit as (
    select px.id, px.criada_em, u.os,
           (select e from jsonb_array_elements(px.fora) e where (e ->> 'os')::uuid = u.os limit 1) as e
      from px
      cross join lateral (select y as os from unnest(px.os_alvo) y
                          union
                          select (e ->> 'os')::uuid from jsonb_array_elements(px.fora) e where e ->> 'os' is not null) u
  ), ult as (
    select distinct on (cit.os) cit.* from cit order by cit.os, cit.criada_em desc, cit.id desc
  )
  select (select x.id from px x order by x.criada_em desc, x.id desc limit 1),
         coalesce((select array_agg(ult.os order by ult.os) from ult where ult.e is null), '{}'::uuid[]),
         coalesce((select jsonb_agg(ult.e order by ult.criada_em, ult.os) from ult
                    where ult.e ->> 'motivo' = 'habilidade'
                      and not exists (select 1 from public.agenda_perguntas q
                                       where q.chave = 'habilidade:os:' || ult.os and q.criada_em >= ult.criada_em)), '[]'::jsonb)
    into v_pid, v_alvo, v_fora;
  -- FASE 7c: fim
  if v_pid is null then
    return jsonb_build_object('proposta', null, 'abertas', 0, 'resolvidas', 0);
  end if;
  -- o exemplo de quem pode ser o responsável: o 1º responsável da grade (sem o dono)
  select h.nome into v_resp from public.agenda_habilidades(p_hoje) h where not h.eh_dono and h.papel = 0 order by h.nome, h.payee_id limit 1;

  for f in select e from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) e where e ->> 'motivo' = 'habilidade' loop
    v_os := (f ->> 'os')::uuid;
    continue when v_os is null
                  or exists (select 1 from public.agenda_perguntas q where q.chave = 'habilidade:os:' || v_os and q.estado = 'aberta');
    v_ex := public.os_exigencias(v_os, p_hoje);
    v_pede := concat_ws(' e ', public._agenda_exigencia_texto(nullif(coalesce((v_ex ->> 'todos')::int, 0), 0), 'todos'),
                               public._agenda_exigencia_texto(nullif(coalesce((v_ex ->> 'ultimo')::int, 0), 0), 'ultimo'));
    continue when nullif(v_pede, '') is null;
    v_bit := (select b from unnest(c_bits) b where (coalesce((v_ex ->> 'todos')::int, 0) | coalesce((v_ex ->> 'ultimo')::int, 0)) & b <> 0
               order by b limit 1);
    v_cli := coalesce(nullif(f ->> 'cliente_curto', ''), f ->> 'numero');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo, opcoes, criada_em)
    values ('habilidade', 'habilidade:os:' || v_os, v_os,
            public._agenda_corta(format('%s: o serviço pede %s, e nas próximas %s semanas não acho ninguém com isso livre. Quem pode? Me diga numa frase (ex.: %s).',
                                        v_cli, v_pede, cf.horizonte_semanas,
                                        concat_ws(' ou ', case when v_resp is not null then format('"o responsável do %s é o %s"', v_cli, v_resp) end,
                                                  format('"o %s não precisa de %s"', v_cli, public._agenda_exigencia_texto(v_bit, null)))), 600),
            'ligado', '[]'::jsonb, p_agora);
    v_ab := v_ab + 1;
  end loop;

  -- a aberta de uma OS que voltou a caber (estava na proposta e não ficou de fora) fecha
  update public.agenda_perguntas q
     set estado = 'resolvida', resolvida_motivo = 'coube: a equipe tem quem o serviço pede'
   where q.tipo = 'habilidade' and q.chave like 'habilidade:os:%' and q.estado = 'aberta'
     and q.service_order_id = any (coalesce(v_alvo, '{}'::uuid[]))
     and not exists (select 1 from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) e where (e ->> 'os')::uuid = q.service_order_id);
  get diagnostics v_res = row_count;
  return jsonb_build_object('proposta', v_pid, 'abertas', v_ab, 'resolvidas', v_res);
end;
$function$;

comment on function public._agenda_habilidade_perguntas_os(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5, §6.4): com modo_habilidade ligado — a última agenda_propostas de hoje (qualquer escopo): cada OS que ela deixou de fora com o motivo habilidade ganha UMA pergunta habilidade:os:<os> (ligada, não crítica, sem prazo): "Caio: o serviço pede quem comissiona Victron em todos os dias, e nas próximas 6 semanas não acho ninguém com isso livre. Quem pode? Me diga numa frase (ex.: "o responsável do Caio é o Alex" ou "o Caio não precisa de quem comissiona Victron")." (o exemplo do responsável: o 1º responsável da grade); a aberta de uma OS que estava na proposta e não ficou de fora fecha ("coube: a equipe tem quem o serviço pede"). {proposta, abertas, resolvidas}. Definer, sem grant. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 7): não lê só a última proposta de hoje — cada OS pela última proposta que a cita (os_alvo ou fora), das criadas nos últimos 7 dias até p_agora: a de fora por habilidade na última citação ganha a pergunta (se não houver uma aberta nem uma criada depois daquela proposta), a que a última citação põe no plano fecha a aberta ("coube"), a de fora por outro motivo fica como está. agenda_habilidade a chama também a cada tique (com modo_habilidade ligado), fora da rodada do dia.';

-- agenda_habilidade (de 20261102100400_agenda_fase7c_rodada.sql)
create or replace function public.agenda_habilidade(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos  constant text[] := array['propor', 'vetos', 'conferir', 'perguntas_os', 'medir'];
  c_medida  constant int := 30;   -- estrutural: a janela da linha das medidas do foco (spec §6.7), em dias
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_modos   jsonb;
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
  -- FASE 7c: (7c correção, achado 7) a pergunta por OS a cada tique
  v_c7_r    jsonb;
  -- FASE 7c: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada de quem faz o quê.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_habilidade'));
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('modo_habilidade', cf.modo_habilidade, 'modo_lider', cf.modo_lider,
                                'modo_habilidade_propor', cf.modo_habilidade_propor);
  -- FASE 7c: (7c correção, achado 7) com modo_habilidade ligado, a pergunta por OS também a cada tique fora da rodada do dia (antes de
  -- habilidade_hora e depois que ela rodou): a vigia (o passo 0c, depois deste) e o gestor (às :53) deixam OS de fora por falta de
  -- quem o serviço pede depois da rodada; no tique seguinte a pergunta nasce (ou fecha, quando a OS volta a caber). Idempotente; o
  -- que falha vai a log_app_error (agenda / habilidade:perguntas_os) e o tique segue. A saída é a de antes com perguntas_os.
  if cf.modo_habilidade = 'ligado'
     and ((p_agora at time zone 'America/Sao_Paulo')::time < cf.habilidade_hora
          or exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'habilidade' and x.p_hoje = p_hoje)) then
    begin
      v_c7_r := public._agenda_habilidade_perguntas_os(p_hoje, p_agora);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_c7_r := jsonb_build_object('sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('quem faz o quê, passo perguntas_os (tique): %s', v_msg), 'agenda',
                                   'habilidade:perguntas_os', 'error',
                                   jsonb_build_object('passo', 'perguntas_os', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
    return case when (p_agora at time zone 'America/Sao_Paulo')::time < cf.habilidade_hora
                then jsonb_build_object('rodou', false, 'cedo', true, 'modos', v_modos, 'hora', cf.habilidade_hora)
                else jsonb_build_object('rodou', false, 'ja_rodou', true, 'modos', v_modos) end
           || jsonb_build_object('perguntas_os', v_c7_r);
  end if;
  -- FASE 7c: fim
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.habilidade_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'modos', v_modos, 'hora', cf.habilidade_hora);
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'habilidade' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true, 'modos', v_modos);
  end if;

  -- (1) propor: com modo_habilidade_propor fora de desligado; (2) vetos: sempre (só age na pergunta ligada e já mostrada); (3)
  -- conferir: com modo_habilidade ou modo_lider em teste; (4) perguntas_os: com modo_habilidade ligado; (5) medir: sempre (só lê)
  foreach v_passo in array c_passos loop
    continue when v_passo = 'propor' and cf.modo_habilidade_propor = 'desligado';
    continue when v_passo = 'conferir' and cf.modo_habilidade <> 'sombra' and cf.modo_lider <> 'sombra';
    continue when v_passo = 'perguntas_os' and cf.modo_habilidade <> 'ligado';
    begin
      if v_passo = 'propor' then
        v_r := public._agenda_habilidade_propor(p_hoje, p_agora);
      elsif v_passo = 'vetos' then
        v_r := public._agenda_habilidade_vetos(p_hoje, p_agora);
      elsif v_passo = 'conferir' then
        v_r := public._agenda_habilidade_conferir(p_hoje, p_agora);
      elsif v_passo = 'perguntas_os' then
        v_r := public._agenda_habilidade_perguntas_os(p_hoje, p_agora);
      else
        v_r := public.agenda_habilidade_medidas(p_hoje - c_medida, p_hoje, p_hoje) - 'detalhe';
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('quem faz o quê, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'habilidade:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'habilidade', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modos', v_modos, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_habilidade(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5): a rodada de quem faz o quê (o passo 0b2a do task-automations, a cada tique; o molde de agenda_aprender) — uma vez por dia, a partir de habilidade_hora (antes: {rodou: false, cedo: true}; o 2º tique do dia: {rodou: false, ja_rodou: true}); com pg_advisory_xact_lock. Os passos, cada um no seu bloco (o que falha vai a log_app_error, context agenda, action habilidade:<passo>, e os outros seguem): propor (_agenda_habilidade_propor, com modo_habilidade_propor fora de desligado), vetos (_agenda_habilidade_vetos, sempre), conferir (_agenda_habilidade_conferir, com modo_habilidade ou modo_lider em sombra), perguntas_os (_agenda_habilidade_perguntas_os, com modo_habilidade ligado) e medir (agenda_habilidade_medidas dos últimos 30 dias, sem o detalhe; sempre). Grava agenda_vigia_rodadas (rotina habilidade; contagens com o resultado de cada passo, os 3 modos e as falhas). {rodou, modos, contagens, erros, falhas}. Nenhuma mensagem a ninguém. Definer; só service_role. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 7): com modo_habilidade ligado, fora da rodada do dia (antes de habilidade_hora e depois que ela rodou), cada tique roda _agenda_habilidade_perguntas_os (o erro vai a log_app_error, action habilidade:perguntas_os) e a saída de antes ganha perguntas_os — a OS que a vigia ou o gestor tira por falta de quem o serviço pede depois da rodada ganha a pergunta no tique seguinte.';

-- _agenda_habilidade_pergunta_texto (de 20261102100400_agenda_fase7c_rodada.sql)
create or replace function public._agenda_habilidade_pergunta_texto(p_hoje date, p_ids uuid[])
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 600;   -- estrutural: o CHECK de agenda_perguntas.texto
  v_it    text[];
  v_med   text[];
  v_cur   text[];
  v_a     text;
  v_i     text;
  v_cauda text;
  v_txt   text;
  v_lista text[];
  k       int;
  -- FASE 7c: (7c correção, achado 11) quem o exemplo cita já não sobe no teto
  v_c11_i   boolean;
  v_c11_a   boolean;
  -- FASE 7c: fim
begin
  -- cada proposta em três tamanhos: o inteiro (quem instala sozinho com o 220 V e o teto), o do texto da etiqueta e o curto (o rótulo
  -- antes dos dois-pontos: "João é ajudante"); o texto encolhe nessa ordem antes de deixar alguém para o "e mais N"
  select array_agg(x.nm || ' ' || x.longo || x.mot order by x.o), array_agg(x.nm || ' ' || x.medio || x.mot order by x.o),
         array_agg(x.nm || ' ' || split_part(x.medio, ':', 1) || x.mot order by x.o),
         (array_agg(x.nm order by x.o) filter (where x.etiqueta = 'ajudante'))[1],
         (array_agg(x.nm order by x.o) filter (where x.etiqueta = 'instala' and x.nivel >= 2))[1]
    into v_it, v_med, v_cur, v_a, v_i
    from (select e.etiqueta, e.nivel, public._agenda_nome_curto(py.name) as nm, ' (' || e.motivo || ')' as mot,
                 row_number() over (order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                             public._agenda_nome_curto(py.name), e.id) as o,
                 public._agenda_etiqueta_texto(e.etiqueta, e.nivel) as medio,
                 case when e.etiqueta = 'instala' and e.nivel >= 2
                      then public._agenda_etiqueta_texto('instala', e.nivel)
                           || case when e.nivel >= cf.habilidade_nivel_energizado and coalesce(h.altura >= cf.habilidade_nivel_altura, false)
                                     then ', também com 220 V ou banco de bateria, e sobe no teto'
                                   when e.nivel >= cf.habilidade_nivel_energizado then ', também com 220 V ou banco de bateria'
                                   when coalesce(h.altura >= cf.habilidade_nivel_altura, false) then ' e sobe no teto'
                                   else '' end
                      else public._agenda_etiqueta_texto(e.etiqueta, e.nivel) end as longo
            from public.agenda_etiquetas e
            join public.payees py on py.id = e.payee_id
            left join lateral (select hh.altura from public.agenda_habilidades(p_hoje, array[e.payee_id]) hh) h on true
           where e.id = any (coalesce(p_ids, '{}'::uuid[]))) x;
  if coalesce(cardinality(v_it), 0) = 0 then
    return null;
  end if;
  v_cauda := case when coalesce((cf.habilidade_padrao ->> 'comissiona')::int, 0) < cf.habilidade_nivel_comissionar
                  then ' Comissionar Victron fica com você.' else '' end
             || format(' Se você não responder até as %s %s, fica assim.', to_char(cf.veto_hora, 'HH24:MI'),
                       case when cf.veto_du = 0 then 'do dia em que vir esta pergunta'
                            when cf.veto_du = 1 then 'do próximo dia útil depois de ver esta pergunta'
                            else format('do %sº dia útil depois de ver esta pergunta', cf.veto_du) end)
             || format(' Para corrigir, me diga numa frase (ex.: %s).',
                       case when v_a is not null and v_i is not null
                              then format('"o %s instala sozinho" ou "o %s não sobe no teto"', v_a, v_i)
                            when v_i is not null then format('"o %s não sobe no teto" ou "o %s é ajudante"', v_i, v_i)
                            else format('"o %s instala sozinho" ou "o %s não sobe no teto"', v_a, v_a) end);
  -- FASE 7c: (7c correção, achado 11) o exemplo não sugere o que já vale: quem já não sobe no teto (a etiqueta de altura do dono, ou o
  -- padrão) sai do "não sobe no teto" — "o Alex não sobe no teto" ou "o Alex é ajudante" vira "o Alex é ajudante" (com o ajudante,
  -- "o João instala sozinho" ou "o Alex é ajudante"; só o ajudante, "o João instala sozinho"). Subindo, o de antes, byte a byte.
  select coalesce(bool_or(h.altura >= cf.habilidade_nivel_altura) filter (where nm = v_i), true),
         coalesce(bool_or(h.altura >= cf.habilidade_nivel_altura) filter (where nm = v_a), true)
    into v_c11_i, v_c11_a
    from (select public._agenda_nome_curto(py.name) as nm, e.payee_id
            from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
           where e.id = any (coalesce(p_ids, '{}'::uuid[]))) z
    cross join lateral (select hh.altura from public.agenda_habilidades(p_hoje, array[z.payee_id]) hh) h;
  if v_i is not null and not v_c11_i then
    v_cauda := replace(v_cauda, format('"o %s não sobe no teto" ou "o %s é ajudante"', v_i, v_i), format('"o %s é ajudante"', v_i));
    v_cauda := replace(v_cauda, format('"o %s não sobe no teto"', v_i), format('"o %s é ajudante"', v_i));
  elsif v_i is null and v_a is not null and not v_c11_a then
    v_cauda := replace(v_cauda, format(' ou "o %s não sobe no teto"', v_a), '');
  end if;
  -- FASE 7c: fim
  foreach v_lista slice 1 in array array[v_it, v_med] loop
    v_txt := 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: ' || array_to_string(v_lista, '; ') || '.'
             || v_cauda;
    if char_length(v_txt) <= c_max then
      return v_txt;
    end if;
  end loop;
  for k in reverse cardinality(v_cur) .. 1 loop
    v_txt := 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: ' || array_to_string(v_cur[1:k], '; ')
             || case when k < cardinality(v_cur) then format('; e mais %s (*agenda quem faz* mostra)', cardinality(v_cur) - k) else '' end
             || '.' || v_cauda;
    exit when char_length(v_txt) <= c_max;
  end loop;
  return public._agenda_corta(v_txt, c_max);
end;
$function$;

comment on function public._agenda_habilidade_pergunta_texto(date, uuid[]) is
  'Agenda de Produção (Fase 7c, P5; spec §6.4, R5.1-6): o texto da pergunta habilidade:equipe para as propostas p_ids — "Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: Alex instala sozinho, também com 220 V ou banco de bateria, e sobe no teto (você disse que ele vem todo dia útil). Comissionar Victron fica com você. Se você não responder até as 18:00 do próximo dia útil depois de ver esta pergunta, fica assim. Para corrigir, me diga numa frase (ex.: "o Alex não sobe no teto" ou "o Alex é ajudante")." Primeiro quem instala sozinho, depois o ajudante e o novo; o 220 V pelo habilidade_nivel_energizado e o teto pela altura da pessoa (etiqueta ou padrão); o comissionar com o dono enquanto o padrão não comissiona; o prazo sem data, pela veto_hora e o veto_du; em até 600 letras — encolhe primeiro sem o 220 V e o teto, depois com o rótulo curto ("João é ajudante", "Bruno é novo"), e só então deixa gente para o "e mais N (*agenda quem faz* mostra)". Sem proposta = nulo. STABLE, sem grant. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 11): o exemplo de correção não sugere o que já vale — quem o exemplo cita e já não sobe no teto (a etiqueta de altura ou o padrão) não aparece com "não sobe no teto" ("o Alex é ajudante"; com o ajudante, "o João instala sozinho" ou "o Alex é ajudante"; só o ajudante, "o João instala sozinho"). Subindo, o de antes.';

-- _agenda_habilidade_propor (de 20261102100400_agenda_fase7c_rodada.sql)
create or replace function public._agenda_habilidade_propor(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_dono  uuid := public._agenda_dono(null);
  v_extra uuid := public._agenda_pessoa_extra_id();
  v_modo  text;
  r       record;
  v_et    text;
  v_nv    smallint;
  v_mot   text;
  v_ev    jsonb;
  v_desde date;
  v_n     int;
  v_casa  int;
  v_qtas  text;
  v_dias  smallint[];
  v_pess  int := 0;
  v_novas jsonb := '[]'::jsonb;
  v_vivas uuid[];
  v_qid   uuid;
  v_qmodo text;
  v_refaz boolean;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_habilidade_propor: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  v_modo := case when cf.modo_habilidade_propor = 'ligado' then 'ligado' else 'sombra' end;

  -- A população: a grade de p_hoje a p_hoje + 13 (agenda_capacidade: quem a agenda conta; o perfil de diária é do pagamento), sem o dono,
  -- sem a pessoa a mais da 7b e sem quem vem sob demanda em todo dia em que está na grade (a ele o gestor não propõe nada: vale a 7b —
  -- nunca sozinho — até a palavra do dono, R5.1-3).
  for r in
    select py.id, public._agenda_nome_curto(py.name) as nm, py.created_at
      from (select k.payee_id, bool_and(public._agenda_e_sob_demanda(k.payee_id, k.dia)) as sob
              from (select distinct c.payee_id, c.dia
                      from public.agenda_capacidade(p_hoje, p_hoje + 13, p_hoje) c
                     where not c.eh_dono) k
             group by k.payee_id) g
      join public.payees py on py.id = g.payee_id
     where not g.sob and g.payee_id is distinct from v_dono and g.payee_id is distinct from v_extra
     order by public._agenda_nome_curto(py.name), py.id
  loop
    v_pess := v_pess + 1;
    -- (1) o dono já disse se ele instala ou é ajudante: nada (a palavra dele vale)
    continue when exists (select 1 from public.agenda_etiquetas e
                           where e.payee_id = r.id and e.origem = 'dono' and e.estado = 'vale' and e.etiqueta in ('instala', 'ajudante'));
    v_et := null;
    if public._agenda_tecnico_declarado(r.id, p_hoje) then
      -- (2) o técnico que o dono declarou (o padrão dele, vivo ou substituído, e o cadastro de novato_dias ou mais antes): instala
      -- sozinho, pelo que o dono disse dos dias
      select d.dias_semana into v_dias
        from public.agenda_disponibilidade d
       where d.payee_id = r.id and d.origem = 'dono' and d.dias_semana is not null and cardinality(d.dias_semana) > 0
         and d.situacao in ('disponivel', 'confirmada')
       order by d.criado_em desc, d.id desc
       limit 1;
      v_et := 'instala';
      v_nv := 2;
      v_mot := format('você disse que ele vem %s',
                      case when array(select distinct x from unnest(v_dias) x order by 1) = '{1,2,3,4,5}'::smallint[] then 'todo dia útil'
                           else public._agenda_dias_curtos(v_dias) end);
      v_ev := jsonb_build_object('declarado', true,
                                 'desde', (select min(d.criado_em) from public.agenda_disponibilidade d
                                            where d.payee_id = r.id and d.origem = 'dono' and d.dias_semana is not null
                                              and cardinality(d.dias_semana) > 0 and d.situacao in ('disponivel', 'confirmada')),
                                 'cadastro', r.created_at, 'dias', to_jsonb(v_dias));
    elsif exists (select 1 from public.work_profiles w
                   where w.payee_id = r.id and w.vigencia_inicio <= p_hoje and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje)) then
      -- (3) com perfil de diária vigente: o histórico (a 1ª vigência e as diárias da janela)
      v_desde := (select min(w.vigencia_inicio) from public.work_profiles w where w.payee_id = r.id);
      v_n := (select count(*)::int from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
               where w.payee_id = r.id and ws.tipo in ('normal', 'diaria')
                 and ws.data > p_hoje - cf.habilidade_janela_dias and ws.data <= p_hoje);
      v_casa := p_hoje - v_desde;
      v_qtas := case when v_n = 0 then 'ainda sem diária' when v_n = 1 then '1 diária' else v_n || ' diárias' end;
      if public._agenda_e_novato(r.id, p_hoje) then
        v_et := 'ajudante'; v_nv := 1; v_mot := format('começou em %s, %s', to_char(v_desde, 'DD/MM'), v_qtas);
      elsif v_n >= cf.habilidade_instala_diarias and v_casa >= cf.habilidade_instala_dias then
        v_et := 'instala'; v_nv := 2; v_mot := format('%s desde %s', v_qtas, to_char(v_desde, 'DD/MM'));
      else
        v_et := 'ajudante'; v_nv := 2; v_mot := format('entrou em %s, %s', to_char(v_desde, 'DD/MM'), v_qtas);
      end if;
      v_ev := jsonb_build_object('diarias', v_n, 'desde', v_desde, 'dias_de_casa', v_casa, 'janela', cf.habilidade_janela_dias);
    end if;
    -- (4) sem nada disso: nada (vale o padrão; o dia fixo sem perfil já é o papel novo de agenda_habilidades)
    continue when v_et is null;
    -- a viva do gestor já é esta (proposta ou valendo): nada
    continue when exists (select 1 from public.agenda_etiquetas e
                           where e.payee_id = r.id and e.origem = 'gestor' and e.estado in ('proposta', 'vale')
                             and e.etiqueta = v_et and e.nivel = v_nv);
    -- em teste, a proposta nunca troca o que já vale (o gatilho de exclusividade a substituiria)
    continue when v_modo = 'sombra'
                  and exists (select 1 from public.agenda_etiquetas e
                               where e.payee_id = r.id and e.estado = 'vale' and e.etiqueta in ('instala', 'ajudante'));
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, evidencia, criado_em)
    values (r.id, v_et, v_nv, 'gestor', 'proposta', v_mot, v_ev, p_agora);
    v_novas := v_novas || jsonb_build_object('payee_id', r.id, 'nome', r.nm, 'etiqueta', v_et, 'nivel', v_nv, 'motivo', v_mot);
  end loop;

  -- Uma pergunta só, com todas as propostas vivas. Refeita quando há proposta nova, quando o modo dela mudou (a de teste nunca é vista)
  -- ou quando uma proposta dela deixou de valer (o dono disse outra coisa antes de ver); sem nenhuma proposta viva, a aberta sai.
  v_vivas := array(select e.id from public.agenda_etiquetas e where e.origem = 'gestor' and e.estado = 'proposta' order by e.id);
  select q.id, q.modo into v_qid, v_qmodo
    from public.agenda_perguntas q
   where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta'
   order by q.criada_em desc, q.id desc
   limit 1;
  v_refaz := jsonb_array_length(v_novas) > 0
             or (cardinality(v_vivas) > 0
                 and (v_qid is null or v_qmodo <> v_modo
                      or exists (select 1 from public.agenda_etiquetas e where e.id = any (v_vivas) and e.pergunta_id is distinct from v_qid)
                      or exists (select 1 from public.agenda_etiquetas e where e.pergunta_id = v_qid and e.estado <> 'proposta')))
             or (cardinality(v_vivas) = 0 and v_qid is not null);
  -- FASE 7c: (7c correção, achado 11) refeita também quando o texto dela mudaria: o dono gravou "o Alex não sobe no teto" antes de ver a
  -- pergunta, e ela continuava dizendo "Alex instala sozinho, …, e sobe no teto" (o texto lê a altura de cada um, da etiqueta do dono
  -- ou do padrão, e nenhuma proposta nova, modo mudado ou proposta que deixou de valer a refazia). O prazo recomeça: ela não foi vista
  -- com o texto de agora.
  v_refaz := v_refaz
             or (v_qid is not null and cardinality(v_vivas) > 0
                 and public._agenda_habilidade_pergunta_texto(p_hoje, v_vivas)
                     is distinct from (select q.texto from public.agenda_perguntas q where q.id = v_qid));
  -- FASE 7c: fim
  if v_refaz then
    update public.agenda_perguntas q
       set estado = 'descartada',
           resolvida_motivo = case when cardinality(v_vivas) > 0 then 'a proposta mudou: perguntei de novo'
                                   else 'a proposta mudou: não sobrou nada a perguntar' end
     where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta';
    v_qid := null;
    if cardinality(v_vivas) > 0 then
      insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, criada_em)
      values ('habilidade', 'habilidade:equipe:' || p_hoje, public._agenda_habilidade_pergunta_texto(p_hoje, v_vivas), v_modo,
              '[]'::jsonb, p_agora)
      returning id into v_qid;
      update public.agenda_etiquetas set pergunta_id = v_qid where id = any (v_vivas);
    end if;
  end if;
  return jsonb_build_object('pessoas', v_pess, 'propostas', v_novas, 'vivas', cardinality(v_vivas), 'pergunta_id', v_qid,
                            'refeita', v_refaz, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_habilidade_propor(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P5; spec §5.5, R5.1-6): a proposta de quem faz o quê. População: a grade de p_hoje a p_hoje + 13 (agenda_capacidade), sem o dono, sem a pessoa a mais da 7b e sem quem vem sob demanda (_agenda_e_sob_demanda em todo dia da grade). Regras, nesta ordem: (1) com etiqueta vale do dono em instala ou ajudante → nada; (2) o técnico que o dono declarou (_agenda_tecnico_declarado) → instala 2, "você disse que ele vem todo dia útil" (os dias do padrão do dono; evidência {declarado, desde, cadastro, dias}); (3) com perfil de diária vigente — o novato da 7b (_agenda_e_novato) → ajudante 1 ("começou em 20/10, 3 diárias"), habilidade_instala_diarias ou mais diárias (as linhas normal/diaria de work_shifts na janela de habilidade_janela_dias) e habilidade_instala_dias ou mais de casa (desde a 1ª vigência) → instala 2 ("33 diárias desde 23/08"), senão ajudante 2 ("entrou em 29/09, 15 diárias"); evidência {diarias, desde, dias_de_casa, janela}; (4) senão nada. Nunca comissiona nem altura. Não repete a viva do gestor igual; em teste, não troca etiqueta que já vale. A proposta (origem gestor, estado proposta, criado_em = p_agora) substitui a do gestor de antes (o gatilho de exclusividade). UMA pergunta habilidade:equipe:<p_hoje> (ligada com modo_habilidade_propor ligado; senão em teste; perda_em nulo, sem opções; o texto de _agenda_habilidade_pergunta_texto), refeita com proposta nova, com o modo mudado ou com proposta dela que deixou de valer — a aberta de antes vira descartada ("a proposta mudou: perguntei de novo"); toda proposta viva aponta para ela. {pessoas, propostas [{payee_id, nome, etiqueta, nivel, motivo}], vivas, pergunta_id, refeita, modo}. Definer, sem grant (só a rodada agenda_habilidade a chama). CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 11): a pergunta aberta é refeita também quando o texto dela mudaria (_agenda_habilidade_pergunta_texto das propostas vivas diferente do gravado: a etiqueta de altura do dono, por exemplo) — a aberta vira descartada ("a proposta mudou: perguntei de novo") e nasce a nova; o prazo recomeça.';

-- _agenda_ver_habilidades (de 20261102100500_agenda_fase7c_leituras.sql)
create or replace function public._agenda_ver_habilidades(p_hoje date, p_agora timestamptz, p_os uuid default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_max     constant int := 1500;  -- estrutural: o teto do foco (o conteúdo até texto_max, a linha "Para corrigir" depois; R5.6)
  c_medidas constant int := 30;    -- estrutural: a janela das medidas no foco ("Nos últimos 30 dias", spec §6.7)
  c_teste   constant int := 3;     -- estrutural: quantas mudanças de teste a linha "Em teste" mostra (o resto: "e mais N")
  c_faltas  constant int := 3;     -- estrutural: quantos meios-dias sem quem o serviço pede o bloco da OS mostra (o resto: "e mais N")
  c_bits    constant jsonb := '{"energizado": 1, "comissionamento": 2, "altura": 4, "diagnostico": 8}';
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_dono    uuid := public._agenda_dono(null);
  v_n       jsonb;
  v_modo    text;
  v_pes     jsonb := '[]'::jsonb;
  v_lpes    text[] := '{}';
  v_dalt    int;
  h         record;
  e         record;
  q         record;
  r         record;
  k         record;
  v_partes  jsonb;
  v_linha   text;
  v_suf     text;
  v_grupo   text;
  v_gsuf    text;
  v_ate     timestamptz;
  v_pi      int;
  v_pc      int;
  v_pa      int;
  v_padrao  text;
  v_oss     jsonb := '[]'::jsonb;
  v_los     text[] := '{}';
  v_ex      jsonb;
  v_lid     jsonb;
  v_pede    text;
  v_cit     text;
  v_todos   int;
  v_ult     int;
  v_nome    text;
  v_teste   text[];
  v_lteste  text;
  v_m       jsonb;
  v_lmed    text;
  v_fim     text;
  v_exemplo text;
  v_cab     text;
  v_l       text[];
  v_txt     text;
  v_corte   int;
  v_max     int;
  v_mask    int;
  v_sozinho text[];
  v_junto   text[];
  v_cod     text;
  v_rot     text;
  v_cli     text;
  v_alocs   jsonb;
  v_dias    date[];
  v_fecha   boolean;
  v_faltas  text[];
  v_nf      int;
  v_resp    text;
  i         int;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (o WhatsApp do dono).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'Quem faz o quê é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'Quem faz o quê é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_ver_habilidades: p_hoje e p_agora são obrigatórios.' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);
  v_modo := case cf.modo_habilidade when 'ligado' then '(já escalo por isso)' when 'sombra' then '(em teste: ainda escalo como antes)'
                                    else '(desligado: a agenda não usa)' end;

  -- ── as pessoas: o que vale hoje (agenda_habilidades, na ordem dela: você primeiro, depois o nome; você também quando não está na
  -- grade) e, no lugar do instala/ajudante, a proposta do gestor que ainda não vale ──
  for h in
    with todos as (
      select x.* from public.agenda_habilidades(p_hoje)
             with ordinality x(payee_id, nome, eh_dono, instala, comissiona, altura, papel, fonte, texto, pos)
    )
    select t.payee_id, t.nome, t.eh_dono, t.instala, t.comissiona, t.altura, t.papel, t.fonte, t.texto, t.pos from todos t
    union all
    select x.payee_id, x.nome, x.eh_dono, x.instala, x.comissiona, x.altura, x.papel, x.fonte, x.texto, 0
      from public.agenda_habilidades(p_hoje, array[v_dono]) x
     where v_dono is not null and not exists (select 1 from todos t where t.payee_id = v_dono)
     order by 10
  loop
    v_linha := h.texto;
    if h.eh_dono then
      v_dalt := h.altura;
    else
      select e2.* into e from public.agenda_etiquetas e2
       where e2.payee_id = h.payee_id and e2.etiqueta in ('instala', 'ajudante') and e2.estado in ('proposta', 'vale')
       order by e2.criado_em desc, e2.id desc limit 1;
      if found and e.estado = 'proposta' and e.origem = 'gestor' then
        -- a proposta: [texto, de onde] da proposta e das outras etiquetas vivas (comissiona, altura); as seguidas com o mesmo
        -- "você disse" dividem o parêntese, como em agenda_habilidades
        v_partes := '[]'::jsonb;
        for e in
          select e2.* from public.agenda_etiquetas e2
           where e2.payee_id = h.payee_id and e2.estado in ('proposta', 'vale')
           order by case e2.etiqueta when 'instala' then 0 when 'ajudante' then 0 when 'comissiona' then 1 else 2 end, e2.criado_em desc, e2.id
        loop
          if e.origem = 'dono' then
            v_suf := 'você disse';
          elsif e.estado = 'vale' then
            v_suf := format('eu marquei: %s; vale desde %s', e.motivo, public._dia_curto((e.vale_desde at time zone 'America/Sao_Paulo')::date));
          else
            select x.estado, x.modo, x.veto_ate, x.mostrada_em into q from public.agenda_perguntas x where x.id = e.pergunta_id;
            if q.estado = 'aberta' and q.modo = 'ligado' then
              v_ate := coalesce(q.veto_ate, case when q.mostrada_em is not null then public._agenda_veto_ate(q.mostrada_em) end);
              v_suf := format('eu marquei: %s; %s', e.motivo,
                              coalesce('espero você até ' || public._dia_curto((v_ate at time zone 'America/Sao_Paulo')::date),
                                       'espero você ver a pergunta'));
            else
              v_suf := format('em teste, eu marcaria: %s', e.motivo);
            end if;
          end if;
          v_partes := v_partes || jsonb_build_array(jsonb_build_array(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), v_suf));
        end loop;
        v_linha := null;
        v_grupo := null;
        v_gsuf := null;
        for i in 0 .. jsonb_array_length(v_partes) - 1 loop
          if v_grupo is not null and v_gsuf = 'você disse' and v_partes -> i ->> 1 = v_gsuf then
            v_grupo := v_grupo || '; ' || (v_partes -> i ->> 0);
          else
            if v_grupo is not null then
              v_linha := concat_ws('; ', v_linha, format('%s (%s)', v_grupo, v_gsuf));
            end if;
            v_grupo := v_partes -> i ->> 0;
            v_gsuf := v_partes -> i ->> 1;
          end if;
        end loop;
        v_linha := format('%s: %s.', h.nome, concat_ws('; ', v_linha, format('%s (%s)', v_grupo, v_gsuf)));
      else
        -- o que vale: o texto de agenda_habilidades, com "vale desde" na etiqueta do gestor
        for e in
          select e2.* from public.agenda_etiquetas e2
           where e2.payee_id = h.payee_id and e2.estado = 'vale' and e2.origem = 'gestor' and e2.vale_desde is not null
        loop
          v_linha := replace(v_linha, format(' (eu marquei: %s)', e.motivo),
                             format(' (eu marquei: %s; vale desde %s)', e.motivo,
                                    public._dia_curto((e.vale_desde at time zone 'America/Sao_Paulo')::date)));
        end loop;
      end if;
    end if;
    v_pes := v_pes || jsonb_build_array(jsonb_build_object(
      'payee_id', h.payee_id, 'nome', h.nome, 'eh_dono', h.eh_dono, 'instala', h.instala, 'comissiona', h.comissiona,
      'altura', h.altura, 'papel', h.papel, 'fonte', h.fonte, 'texto', v_linha));
    v_lpes := v_lpes || ('• ' || v_linha);
  end loop;

  -- quem não tem nada marcado (o padrão da casa, AG7-10, pela mesma régua de agenda_habilidades)
  v_pi := (cf.habilidade_padrao ->> 'instala')::int;
  v_pc := (cf.habilidade_padrao ->> 'comissiona')::int;
  v_pa := (cf.habilidade_padrao ->> 'altura')::int;
  v_padrao := case when v_pi >= cf.habilidade_nivel_energizado and v_pa >= cf.habilidade_nivel_altura
                   then case when v_pc >= cf.habilidade_nivel_comissionar then 'Quem não tem nada marcado pode tudo.'
                             else 'Quem não tem nada marcado pode tudo, menos comissionar.' end
                   else format('Quem não tem nada marcado: %s.',
                               concat_ws('; ', public._agenda_etiqueta_texto('instala', v_pi::smallint),
                                         public._agenda_etiqueta_texto('comissiona', v_pc::smallint),
                                         public._agenda_etiqueta_texto('altura', v_pa::smallint))) end;

  -- o que eu teria mudado hoje em teste (as ações de teste da rodada: "Ivo, ter 10/11 à tarde (poria Roberto)")
  v_teste := array(
    select coalesce(substring(a.texto from '^Em teste \([^)]*\): ([^—]+) — ')
                    || coalesce(' (' || substring(a.texto from '(?:; |: )eu ((?:poria|mudaria|manteria) [^.]*)\.$') || ')', ''),
                    a.texto)
      from public.agenda_acoes a
     where a.tipo = 'habilidade' and not a.executada and a.dia = p_hoje
       and (p_os is null or a.service_order_id = p_os)
     order by a.criada_em, a.id);
  v_lteste := case when cardinality(v_teste) > 0
                   then 'Em teste, hoje eu teria mudado: ' || array_to_string(v_teste[1:c_teste], '; ')
                        || case when cardinality(v_teste) > c_teste then format('; e mais %s', cardinality(v_teste) - c_teste) else '' end
                        || '.' end;

  -- ── o bloco de uma OS (com p_os) ──
  if p_os is not null then
    v_rot := public._agenda_rotulo_da_os(p_os);
    v_ex := public.os_exigencias(p_os, p_hoje);
    if v_rot is null or not coalesce((v_ex ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'rota', 'habilidades', 'texto', 'Não encontrei esse serviço.');
    end if;
    v_cli := (select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                from public.service_orders so left join public.clients cl on cl.id = so.client_id where so.id = p_os);
    v_todos := coalesce((v_ex ->> 'todos')::int, 0);
    v_ult := coalesce((v_ex ->> 'ultimo')::int, 0);
    v_l := array[format('%s — quem faz o quê %s:', v_rot, v_modo)];
    -- o que pede e de onde veio (a 1ª linha de cada parte, como os_exigencias)
    v_pede := null;
    if v_todos <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'todos' and v_todos & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := format('%s (%s)', public._agenda_exigencia_texto(v_todos, null), v_cit);
    end if;
    if v_ult <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'ultimo' and v_ult & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := concat_ws(' e ', v_pede, format('%s, no último dia (%s)', public._agenda_exigencia_texto(v_ult, null), v_cit));
    end if;
    v_l := v_l || case when v_pede is null then '• Não pede ninguém em especial.' else format('• Pede %s.', v_pede) end;
    -- o plano de hoje em diante (as alocações vigentes, fora a reserva): quem vai e o fechamento do dono no último dia
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia,
                                                 'turno', a.turno, 'presenca', a.presenca) order by a.dia, a.turno, py.name), '[]'::jsonb),
           array_agg(distinct a.dia) filter (where a.presenca = 'turno')
      into v_alocs, v_dias
      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
    v_fecha := v_ult <> 0 and cf.habilidade_fechamento_cobre and cardinality(v_dias) > 0
               and exists (select 1 from public.agenda_alocacoes a
                            where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.presenca = 'fechamento'
                              and a.payee_id is not distinct from v_dono
                              and a.dia = (select max(d) from unnest(v_dias) d));
    if v_fecha then
      v_l := v_l || '• No último dia você fecha: isso cobre o que ele pede.'::text;
    end if;
    -- o que conta para ir sozinho: o de todos os dias e o do último, menos quando o fechamento do dono o cobre (a régua da avaliação do
    -- publicado, _agenda_meios_sem_quem_pede)
    v_mask := v_todos | case when v_fecha then 0 else v_ult end;
    v_lid := public._agenda_lider_da_os(p_os, p_hoje);
    v_l := v_l || case when v_lid is null then '• Sem responsável fixo.' else format('• Responsável: %s.', v_lid ->> 'texto') end;
    v_l := v_l || case when cardinality(v_dias) > 0
                       then format('• Quem vai (%s): %s.', public._agenda_dias_texto(v_dias), public._agenda_pessoas_texto(v_alocs, v_dono))
                       else '• Ainda sem dia marcado.' end;
    -- quem da equipe faz sozinho o que ela pede (a regra única) e quem precisa de alguém junto, com o porquê
    v_sozinho := '{}';
    v_junto := '{}';
    for i in 0 .. jsonb_array_length(v_pes) - 1 loop
      continue when (v_pes -> i ->> 'eh_dono')::boolean;
      v_cod := public._agenda_atende(v_mask, array[(v_pes -> i ->> 'instala')::int], array[(v_pes -> i ->> 'comissiona')::int],
                                     array[(v_pes -> i ->> 'altura')::int], array[(v_pes -> i ->> 'papel')::int], false, v_dalt, v_n);
      if v_cod is null then
        v_sozinho := v_sozinho || (v_pes -> i ->> 'nome');
      else
        v_junto := v_junto || format('%s (%s)', v_pes -> i ->> 'nome', case
          when (v_pes -> i ->> 'papel')::int = 2 then public._agenda_etiqueta_texto('ajudante', 1::smallint)
          when v_cod = 'altura' then public._agenda_etiqueta_texto('altura', (v_pes -> i ->> 'altura')::smallint)
          when v_cod in ('comissionamento', 'diagnostico') then public._agenda_etiqueta_texto('comissiona', (v_pes -> i ->> 'comissiona')::smallint)
          when (v_pes -> i ->> 'papel')::int = 1 then public._agenda_etiqueta_texto('ajudante', 2::smallint)
          else public._agenda_etiqueta_texto('instala', (v_pes -> i ->> 'instala')::smallint) end);
      end if;
    end loop;
    if v_mask = 0 then
      v_l := v_l || case when cardinality(v_junto) = 0 then '• Qualquer um da equipe vai sozinho.'
                         else format('• Qualquer um da equipe vai sozinho, menos %s.', public._agenda_lista(v_junto, null)) end;
    else
      v_resp := case when cardinality(v_sozinho) = 0
                     then 'Ninguém da equipe faz isso sozinho' || case when public._agenda_atende(v_mask, '{}', '{}', '{}', '{}', true, v_dalt, v_n) is null
                                                                       then ': fica com você no turno.' else '.' end
                     when cardinality(v_sozinho) = 1 then format('Faz sozinho o que ela pede: %s.', v_sozinho[1])
                     else format('Fazem sozinhos o que ela pede: %s.', public._agenda_lista(v_sozinho, null)) end;
      if cardinality(v_junto) > 0 then
        v_resp := v_resp || format(' %s de alguém junto: %s.', case when cardinality(v_junto) = 1 then 'Precisa' else 'Precisam' end,
                                   public._agenda_lista(v_junto, null));
      end if;
      v_l := v_l || ('• ' || v_resp);
    end if;
    -- os meios-dias marcados sem quem o serviço pede (a avaliação do publicado, com a equipe dita pelo dono)
    v_faltas := '{}';
    v_nf := 0;
    if cardinality(v_dias) > 0 then
      for r in
        select s.* from public._agenda_meios_sem_quem_pede(p_hoje, (select max(d) from unnest(v_dias) d), p_hoje, array[p_os], true) s
         order by s.dia, s.turno = 'tarde'
      loop
        v_nf := v_nf + 1;
        continue when v_nf > c_faltas;
        v_nome := public._agenda_lista(array(select public._agenda_nome_curto(py.name) from unnest(r.equipe) u(x)
                                                join public.payees py on py.id = u.x order by 1), null);
        v_faltas := v_faltas || case
          when r.falta = 'novato_sozinho' then format('• %s: %s é novo e iria %s.', public._agenda_meio_texto(r.dia, r.turno), v_nome,
                                                      case when cardinality(r.equipe) > 1 then 'sem um responsável junto' else 'sozinho' end)
          when cardinality(r.equipe) = 0 then format('• %s: só você iria, e esse dia pede %s.', public._agenda_meio_texto(r.dia, r.turno),
                                                     public._agenda_exigencia_texto((c_bits ->> r.falta)::int, null))
          else format('• %s: %s %s, e esse dia pede %s.', public._agenda_meio_texto(r.dia, r.turno), v_nome,
                      case when cardinality(r.equipe) > 1 then 'iriam sozinhos' else 'iria sozinho' end,
                      public._agenda_exigencia_texto((c_bits ->> r.falta)::int, null)) end;
      end loop;
    end if;
    if v_nf > c_faltas then
      v_faltas := v_faltas || format('• e mais %s %s sem quem o serviço pede.', v_nf - c_faltas,
                                     case when v_nf - c_faltas = 1 then 'meio-dia' else 'meios-dias' end);
    end if;
    v_l := v_l || v_faltas;
    if v_lteste is not null then
      v_l := v_l || v_lteste;
    end if;
    -- o exemplo de correção: o responsável (o 1º responsável da grade) e o que ela pede
    v_nome := (select p ->> 'nome' from jsonb_array_elements(v_pes) with ordinality t(p, o)
                where not (p ->> 'eh_dono')::boolean and (p ->> 'papel')::int = 0 order by o limit 1);
    v_fim := format('Para corrigir, me diga numa frase (ex.: %s).', concat_ws(' ou ',
               case when v_nome is not null then format('"o responsável do %s é o %s"', v_cli, v_nome) end,
               case when v_todos | v_ult <> 0
                    then format('"o %s não precisa de %s"', v_cli,
                                public._agenda_exigencia_texto(case when (v_todos | v_ult) & 1 <> 0 then 1 when (v_todos | v_ult) & 2 <> 0 then 2
                                                                    when (v_todos | v_ult) & 4 <> 0 then 4 else 8 end, null))
                    else format('"o %s pede quem sobe no teto"', v_cli) end));
    -- o conteúdo até texto_max (e nunca além do teto menos a linha final: o "Para corrigir" sempre cabe)
    v_max := least(cf.texto_max, c_max - 1 - char_length(v_fim));
    v_txt := public._agenda_gestor_juntar(v_l, v_max + 1 + char_length(v_fim), v_fim);
    return jsonb_build_object('ok', true, 'rota', 'habilidades', 'texto', public._agenda_corta(v_txt, c_max),
      'dados', jsonb_build_object(
        'pessoas', v_pes,
        'os', jsonb_build_object('os', p_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = p_os),
                                 'todos', v_todos, 'ultimo', v_ult, 'itens', v_ex -> 'itens', 'lider', v_lid, 'fechamento_cobre', coalesce(v_fecha, false),
                                 'sozinhos', to_jsonb(v_sozinho), 'com_alguem_junto', to_jsonb(v_junto), 'faltas', v_nf),
        'em_teste', to_jsonb(v_teste), 'medidas', null));
  end if;

  -- ── o que as OS da carteira pedem (as marcadas de hoje em diante primeiro, depois o número; a que não pede nada fica fora) ──
  for k in
    select c.service_order_id as os, c.numero, c.cliente_curto,
           (select min(a.dia) from public.agenda_alocacoes a
             where a.service_order_id = c.service_order_id and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje) as prox
      from public.os_carteira(p_hoje) c
     order by 4 nulls last, c.numero collate "C", c.service_order_id
  loop
    v_ex := public.os_exigencias(k.os, p_hoje);
    v_todos := coalesce((v_ex ->> 'todos')::int, 0);
    v_ult := coalesce((v_ex ->> 'ultimo')::int, 0);
    continue when v_todos = 0 and v_ult = 0;
    v_pede := null;
    if v_todos <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'todos' and v_todos & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := format('%s (%s)', public._agenda_exigencia_texto(v_todos, null), v_cit);
    end if;
    if v_ult <> 0 then
      select case i2 ->> 'fonte' when 'dito' then 'você disse' when 'tipo' then 'pelo tipo do serviço' else format('pela linha "%s"', i2 ->> 'linha') end
        into v_cit from jsonb_array_elements(v_ex -> 'itens') with ordinality t(i2, o)
       where i2 ->> 'meios' = 'ultimo' and v_ult & (c_bits ->> (i2 ->> 'exigencia'))::int <> 0 order by o limit 1;
      v_pede := concat_ws(' e ', v_pede, format('%s, no último dia (%s)', public._agenda_exigencia_texto(v_ult, null), v_cit));
    end if;
    -- o responsável, só o que o dono disse ou quem fez o 1º dia (o planejado só desempata), e só lido onde pode haver um
    v_lid := null;
    if exists (select 1 from public.os_planejamento pl where pl.service_order_id = k.os and pl.lider_payee_id is not null)
       or exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.os and a.presenca = 'turno' and a.tipo <> 'reserva'
                     and a.estado in ('publicada', 'fixada') and a.dia <= p_hoje)
       or exists (select 1 from public.work_shift_os x where x.service_order_id = k.os) then
      v_lid := public._agenda_lider_da_os(k.os, p_hoje);
      if v_lid ->> 'fonte' not in ('dono', 'fez') then
        v_lid := null;
      end if;
    end if;
    v_oss := v_oss || jsonb_build_array(jsonb_build_object('os', k.os, 'numero', k.numero, 'cliente', k.cliente_curto, 'todos', v_todos,
                                                           'ultimo', v_ult, 'pede', v_pede, 'lider', v_lid));
  end loop;
  for i in 0 .. jsonb_array_length(v_oss) - 1 loop
    -- o número junto quando o nome se repete na lista ("Kalmar (OS-00032)")
    v_nome := coalesce(v_oss -> i ->> 'cliente', v_oss -> i ->> 'numero');
    if (select count(*) from jsonb_array_elements(v_oss) x
         where public._agenda_normal(coalesce(x ->> 'cliente', x ->> 'numero')) = public._agenda_normal(v_nome)) > 1 then
      v_nome := format('%s (%s)', v_nome, v_oss -> i ->> 'numero');
    end if;
    v_los := v_los || format('• %s: %s%s.', v_nome, v_oss -> i ->> 'pede',
                             case when v_oss -> i -> 'lider' is not null and jsonb_typeof(v_oss -> i -> 'lider') = 'object'
                                  then format('; responsável: %s (%s)', v_oss -> i -> 'lider' ->> 'nome',
                                              case v_oss -> i -> 'lider' ->> 'fonte' when 'dono' then 'você disse' else 'fez o 1º dia' end)
                                  else '' end);
  end loop;

  -- as medidas dos últimos 30 dias (spec §6.7)
  v_m := public.agenda_habilidade_medidas(p_hoje - c_medidas, p_hoje, p_hoje);
  v_lmed := format('Nos últimos %s dias: %s alguém sozinho em serviço que pede outra pessoa; %s de responsável; %s em serviço que outro faria.',
                   c_medidas, public._agenda_plural(coalesce((v_m ->> 'sozinho_em_risco')::int, 0), 'vez', 'vezes'),
                   public._agenda_plural(coalesce((v_m ->> 'troca_de_lider')::int, 0), 'troca', 'trocas'),
                   public._agenda_plural(coalesce((v_m ->> 'dono_em_tarefa_de_outro')::int, 0), 'meio-dia seu', 'meios-dias seus'));

  -- o exemplo de correção: o 1º ajudante, senão o 1º novo ("o João instala sozinho"), senão o 1º responsável ("o Alex é ajudante")
  v_exemplo := (select format('o %s instala sozinho', p ->> 'nome') from jsonb_array_elements(v_pes) with ordinality t(p, o)
                 where not (p ->> 'eh_dono')::boolean and (p ->> 'papel')::int > 0 order by (p ->> 'papel')::int, o limit 1);
  -- FASE 7c: (7c correção, achado 16) "o X instala sozinho" só para o ajudante (papel 1): ao novo (o novato, quem vem sob demanda ou
  -- tem um dia fixo sem diária — nunca vai sozinho, R5.1-5 e o padrão do R5.8-3) a frase tiraria a proteção (instala 2 do dono tira o
  -- papel novo). Sem ajudante, o exemplo do responsável ("o Alex é ajudante").
  v_exemplo := (select format('o %s instala sozinho', p ->> 'nome') from jsonb_array_elements(v_pes) with ordinality t(p, o)
                 where not (p ->> 'eh_dono')::boolean and (p ->> 'papel')::int = 1 order by o limit 1);
  -- FASE 7c: fim
  v_exemplo := coalesce(v_exemplo, (select format('o %s é ajudante', p ->> 'nome') from jsonb_array_elements(v_pes) with ordinality t(p, o)
                                     where not (p ->> 'eh_dono')::boolean order by o limit 1));
  v_fim := case when v_exemplo is null then 'Para corrigir, me diga numa frase o que cada um faz.'
                else format('Para corrigir, me diga numa frase (ex.: "%s").', v_exemplo) end;

  -- o conteúdo até texto_max: primeiro saem as linhas de OS do fim ("• e mais N OS."; sem nenhuma, uma linha só: "O que as OS pedem:
  -- 21 OS pedem alguém em especial (me pergunte por uma)."), depois a linha do padrão (cada pessoa sem nada marcado já diz "(padrão)") e
  -- depois a das OS; só então o corte de sempre, do fim (_agenda_juntar). A linha "Para corrigir" vem depois (R5.6).
  v_cab := 'Quem faz o quê ' || v_modo || ':';
  v_max := least(cf.texto_max, c_max - 1 - char_length(v_fim));
  for i in 0 .. cardinality(v_los) + 2 loop
    v_corte := greatest(cardinality(v_los) - i, 0);
    v_l := array[v_cab] || v_lpes || case when i <= cardinality(v_los) then v_padrao else '' end
           || case when cardinality(v_los) = 0 or i > cardinality(v_los) + 1 then '{}'::text[]
                   when v_corte = 0
                   then array[format('O que as OS pedem: %s alguém em especial (me pergunte por uma).',
                                     public._agenda_plural(cardinality(v_los), 'OS pede', 'OS pedem'))]
                   else array['O que as OS pedem:'] || v_los[1:v_corte]
                        || case when v_corte < cardinality(v_los)
                                then array[format('• e mais %s OS.', cardinality(v_los) - v_corte)] else '{}'::text[] end end
           || coalesce(v_lteste, '') || v_lmed;
    v_txt := array_to_string(array(select x from unnest(v_l) with ordinality u(x, o) where x <> '' order by o), E'\n');
    exit when char_length(v_txt) <= v_max;
  end loop;
  if char_length(v_txt) > v_max then
    v_txt := public._agenda_juntar(v_l, v_max);
  end if;
  v_txt := public._agenda_corta(v_txt || E'\n' || v_fim, c_max);
  return jsonb_build_object('ok', true, 'rota', 'habilidades', 'texto', v_txt,
    'dados', jsonb_build_object('pessoas', v_pes, 'os', v_oss, 'em_teste', to_jsonb(v_teste), 'medidas', v_m,
                                'modo', cf.modo_habilidade, 'os_mostradas', v_corte));
end;
$function$;

comment on function public._agenda_ver_habilidades(date, timestamptz, uuid) is
  'Agenda de Produção (Fase 7c, P6; spec §5.6, §6.7; R5.6, R5.1-6): o foco habilidades de agenda_ver — quem faz o quê na equipe e o que cada OS pede, na palavra do dono. "Quem faz o quê (em teste: ainda escalo como antes):" (ligado "(já escalo por isso):"; desligado "(desligado: a agenda não usa):"); uma linha por pessoa (você primeiro; a grade de hoje a +13 e quem tem etiqueta: o texto de agenda_habilidades, com "; vale desde ter 03/11" na etiqueta do gestor e, no lugar do instala/ajudante, a proposta do gestor que ainda não vale — "Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você até ter 03/11)", "espero você ver a pergunta" antes de vista, "(em teste, eu marcaria: …)" em teste); "Quem não tem nada marcado pode tudo, menos comissionar."; "O que as OS pedem:" (as da carteira que pedem alguém em especial, as marcadas primeiro: "• Lenine: quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Substituição baterias - chumbo para litio"); responsável: Roberto (fez o 1º dia)."); "Em teste, hoje eu teria mudado: Ivo, ter 10/11 à tarde (poria Roberto)." (as ações de teste de hoje); "Nos últimos 30 dias: 0 vezes alguém sozinho em serviço que pede outra pessoa; 0 trocas de responsável; 3 meios-dias seus em serviço que outro faria." (agenda_habilidade_medidas); "Para corrigir, me diga numa frase (ex.: "o João instala sozinho")." O conteúdo até texto_max (saem as linhas de OS do fim, "• e mais N OS."), a linha "Para corrigir" depois; teto 1.500. Com p_os, só o bloco da OS: o que pede e de onde veio, o fechamento do dono que cobre o último dia, o responsável (_agenda_lider_da_os), quem vai no plano (_agenda_pessoas_texto), quem da equipe faz sozinho o que ela pede e quem precisa de alguém junto, com o porquê (_agenda_atende), os meios-dias marcados sem quem o serviço pede (_agenda_meios_sem_quem_pede, até 3) e o que eu teria mudado nela em teste. {ok, rota habilidades, texto, dados {pessoas, os, em_teste, medidas}}. Só lê. STABLE; definer (o responsável e as avaliações do publicado não têm grant), com a porta dentro (com login, só admin/financeiro: 42501; sem login, só o service_role); authenticated e service_role (agenda_ver, invoker, a chama). CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 16): o exemplo "o X instala sozinho" só para o 1º ajudante (papel 1); o novo (papel 2: o novato, quem vem sob demanda ou tem um dia fixo sem diária) nunca é o exemplo (a frase tiraria a proteção dele); sem ajudante, "o <responsável> é ajudante".';

-- agenda_propor (de 20261102100100_agenda_fase7c_motor.sql)
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
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada, a criticidade de cada compromisso colocado é refeita com p_violadas = _agenda_zona_fora (o que não conta para o dia já avisado: a violação, o resto do meio-dia dela e o que volta igual neste encaixe; nunca o fixado pelo dono): o meio-dia de um dia já dito à equipe ou ao cliente que sairia sem ter ficado impossível, e o fim que passaria do prometido firme, viram as críticas dia_avisado e dia_prometido, com a pergunta e a recomendação de sempre. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, §6.3, R4.3): só com os modos da 7b — a entrada da fila ganha dk (as pessoas dos passos que restam), dk_dono_conta, dupla_fonte e o texto da dupla; da dupla inferida, passos1 (o bloco de 1 pessoa: ligado, a soma do dk; em teste, os passos de antes), dupla_ni/dupla_nf/dupla_todos e os nomes do que a tarefa pede; prazo_h (o índice da tarde de least(precisa_ate, o prometido firme)) e prazo; e dupla_sd na dupla dita que só passa pela régua dos técnicos com quem vem sob demanda. p_par ganha sab_modo, sab_politica, dupla_modo e dupla_espera. Ligado, o item com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael se ofereceu), para cumprir o prazo de qua 18/11.") e o bloco de 1 pessoa da dupla inferida diz em que meios-dias chamar um ajudante (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."); o item leva dupla (o texto do cartão), dupla_fonte, dupla_falta [{dia, turno, onde}] e sabado. A dupla dita com dupla_sd sem bloco vai ao fora com o motivo dupla ("Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante."), nunca sem_encaixe. Em teste, textos.em_teste e o fim do texto: "Em teste: para cumprir o prazo de Vanderlei (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu." e "Em teste: no Lenine eu pediria um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.". Sem os modos da 7b, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 22 e 23): o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa ("ex.: Mateus vem qua 18 e qui 19/11"); a dupla dita que só passou da espera por quem vem sob demanda e cujos dias livres são todos antes de a OS ficar pronta (os_prontidao.est) vai ao fora dupla com "…, antes de o serviço ficar pronto (qua 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.". FASE 7c (P2, §5.2, R5.10-12): a entrada da fila ganha ext, exu, exf e exig_texto (os_exigencias, em qualquer modo) e, com modo_lider ou modo_habilidade ligado, lid, lid_nome, lid_duro, lid_plan e lid_fora (_agenda_lider_da_os); p_par ganha hab_modo, lid_modo, n, fcobre e lid_espera (sempre: o critério de cada alocação vai no item e o gatilho agenda_alocacoes_criterio o grava). Ligado: os motivos "pede … : vai …", "troquei o responsável: … não está livre até …; segui com …" e "…, o responsável, não está na equipe agora"; o aviso de habilidade (_agenda_aviso_da_habilidade) ao lado do de material onde o dono disse quem vai; o cancelar habilidade ("a equipe do dia não tinha quem o serviço pede") e o fora habilidade ("pede … e ninguém com isso fica livre junto nas próximas 6 semanas"); o contexto do "por que não cabe" leva hab_modo, n e fcobre. Com os 3 modos fora de ligado, as pessoas, os dias, os turnos e as presenças de antes (a projeção); só o critério aparece. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 9): com a troca avisada do responsável (o lt do bloco: modo_lider ou modo_habilidade ligado), o texto do item (o da ação do "o que mudou", do fechamento e do aviso) termina " — troquei o responsável: Roberto não está livre até qua 11/11; segui com João." (até 320; sem caber, " — troquei o responsável (Roberto não está livre)."). Sem troca, o de antes.';
