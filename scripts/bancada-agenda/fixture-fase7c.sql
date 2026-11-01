-- Fixture da Fase 7c da Agenda de Produção ("quem sabe fazer o quê"), SINTÉTICO, por cima da da 7b (fixture-fase7b.sql, que carrega
-- a da 7a e o replay real de 29/10) (spec-fase7c §8.2, R5.1-6 e R5.10-5). Roda dentro do begin/rollback do teste (o rodar.mjs passa
-- este arquivo em agenda_teste.fase7c e o da 7b em agenda_teste.fase7b); o que ainda não foi carregado nesta transação é carregado
-- antes. Pode rodar de novo na mesma transação (cada parte confere se já está lá). NUNCA rodar em produção.
-- Só primeiros nomes; telefones fictícios; ids novos com o prefixo c7c00000 e as OS 97171 a 97179 (a "171 a 179" da spec: a faixa
-- 97xxx é a das fixtures da Fase 7 — 97001.. da 7a, 97101 da 7b —, livre na bancada).
--
-- Hoje é qua 04/11/2026 16:15 (a fixture não usa now(): todo teste passa p_hoje/p_agora); a janela vai de qui 05/11 a qua 18/11.
-- As duas variantes (R5.1-6):
--   · REAL — com agenda_teste.fase7b_equipe = 'real' antes de carregar: só o Alex de produção (cadastro 05/08, o padrão seg a sex de
--     origem dono desde sex 30/10, sem perfil de diária, sem telefone) e o dono, com (agenda_teste.fase7b_dono = 'campo') ou sem a
--     linha dele. Nada desta fixture entra além das linhas reais completadas (abaixo): é a carteira de produção.
--   · SINTÉTICA (a de sempre): a equipe da 7b (o Alex de produção; Mateus sob demanda, sem perfil; Rafael com perfil desde 01/09 e o
--     padrão dele; Bruno, o novato: perfil e cadastro em 20/10, 3 diárias, uma data dita pelo dono) e, só aqui:
--       - Roberto e João (que saíram em 30/10) voltam à grade com um padrão seg a sex de origem diarista (ter 03/11), com o perfil e
--         as diárias do replay (Roberto: desde 23/08, 32 diárias; João: desde 29/09, 15 diárias);
--       - Bruno passa a ter um padrão seg a sex dito por ele (origem diarista, ter 03/11): não vem mais sob demanda, continua novato
--         (o padrão não é do dono) e fica livre na qui 05/11;
--       - as OS 171 a 179 da §8.2 (uma linha de serviço cada, R$ 382 por meio-dia, os dias ditos pelo dono):
--           171 Lia   "Substituição baterias chumbo para lítio" (energizado no último dia), 6 meios-dias
--           172 Bia   "Instalação de painel solar no teto" (altura em todos), 2 meios-dias
--           173 Caio  service_type commissioning (comissionamento em todos), o dono disse presença nunca, 2 meios-dias
--           174 Duda  "Instalação de porta-fusíveis 12V" (nada), 1 meio-dia
--           175 Edu   "Instalação de inversor 220 V" (energizado no último dia), 6 meios-dias; Roberto cumpriu ter 03/11 manhã e
--                     tarde (o responsável que fez)
--           176 Fábio "Revisão do quadro elétrico", o dono disse que pede energizado em todos (exigencias_ditas) e com dupla
--                     (dupla_dita todos), 4 meios-dias
--           177 Gil   "Troca do banco de baterias" (energizado no último dia), a equipe dita "só o João", 2 meios-dias
--           178 Hugo  "Instalação de luminárias 12V" (nada), 1 meio-dia
--           179 Ivo   "Instalação de carregador e inversor" (energizado no último dia), 2 meios-dias, publicada com o João sozinho
--                     na ter 10/11 (manhã e tarde) e o dono abrindo e fechando nesse dia
-- As linhas reais da carteira (as duas variantes): o replay de 29/10 não trouxe o sistema e o verbo do catálogo de serviços (as colunas
-- de services não foram exportadas); aqui eles vão na linha (service_order_services.service_system/service_verb, só onde a linha não
-- tinha), com os valores de produção de sql/wf7c_05_carteira_linhas (coalesce da linha e do catálogo): é o que os_exigencias lê (o B6
-- fixa a tabela do §2 da spec com elas). 12 linhas: OS-00032 (o pré-comissionamento), OS-00033 (2), OS-00069 (5), OS-00074 (3) e
-- OS-00096.
-- Os interruptores de cada teste:
--   · agenda_teste.fase7c_etiquetas = 'mv' (a sintética): as etiquetas dos testes M e V da §8.2 — Roberto instala 2 vale (gestor:
--     "32 diárias desde 23/08") e altura 0 vale (dono: "o Roberto não sobe no teto"), João ajudante 2 vale (gestor: "entrou em 29/09,
--     15 diárias"), Bruno ajudante 1 vale (gestor: "começou em 20/10, 3 diárias"). Os testes R começam sem nenhuma.
--   · agenda_teste.fase7c_variante (uma por carga), as do novato (R5.1-5, R5.1-6; o esperado de _agenda_e_novato no teste B11):
--       alex_perfil            o Alex com um perfil de diária desde ontem (ter 03/11), 0 diárias → não é novato
--       alex_respondeu         o perfil de ontem e o próprio Alex respondendo os dias (o padrão do dono substituído por um de origem
--                              diarista) → não é novato
--       alex_semana            [c3-conf] o Alex declarado pelo dono só na qua 04/11 (a linha dele movida para hoje) e um perfil desde
--                              seg 02/11 → não é novato nem na segunda da grade (com a 100860, era)
--       mateus_terca           o Mateus cadastrado hoje, "o Mateus vem toda terça" (o padrão do dono) e um perfil de hoje → novato
--       mateus_terca_sem_perfil [c3-rev] o mesmo sem o perfil → na 7b não é novato nem vem sob demanda; na 7c, o papel novo
--       bruno_ajudante         o Bruno com ajudante 2 do dono → continua novato e papel novo
--       bruno_instala          o Bruno com instala 2 do dono → não é novato

do $f7c$
declare
  c_cli     constant text := 'c7c00000-0000-4000-8000-0000000001';   -- + 2 dígitos: os clientes (71 a 79)
  c_bem     constant text := 'c7c00000-0000-4000-8000-0000000002';   -- + 2 dígitos: os bens
  c_os      constant text := 'c7c00000-0000-4000-8000-000000097';    -- + 3 dígitos: as OS (o número da OS no fim: 171 a 179)
  c_pubs    constant timestamptz := timestamptz '2026-11-02 16:30-03';  -- a publicação de seg 02/11 (o plano que já existia)
  v_real    boolean := coalesce(current_setting('agenda_teste.fase7b_equipe', true), '') = 'real';
  v_var     text := coalesce(current_setting('agenda_teste.fase7c_variante', true), '');
  v_dono_u  uuid;
  v_dono    uuid;
  v_alex    uuid;
  v_roberto uuid;
  v_joao    uuid;
  v_bruno   uuid;
  v_mateus  uuid;
  v_os      uuid;
  v_r       jsonb;
  v_hoje_antes text;
  r         record;
begin
  -- ── 0. A base: a 7b (que carrega a 7a e o replay) ─────────────────────────────────────────────────────────────
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
      raise exception 'fixture-fase7c: falta a fixture da 7b (agenda_teste.fase7b; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.fase7b');
  end if;

  select id into strict v_dono_u from public.app_users where role = 'admin' and active order by id limit 1;
  v_dono := public._agenda_dono(null);
  select id into strict v_alex from public.payees where name = 'Alex' and active;

  -- ── 1. As linhas reais: o sistema e o verbo do catálogo que o replay não trouxe (wf7c_05) ───────────────────────
  update public.service_order_services sos
     set service_system = coalesce(sos.service_system, v.sistema), service_verb = coalesce(sos.service_verb, v.verbo)
    from public.service_orders so,
         (values
           ('OS-00032', 'Pré-comissionamento', 'hidraulico', 'diagnostico'),
           ('OS-00033', 'INSTALAÇÃO TÉCNICA DE PARELHA', 'mecanico', 'instalacao'),
           ('OS-00033', 'COMISSIONAMENTO E VALIDAÇÃO', null, 'projeto'),
           ('OS-00069', 'Configuração e parametrização', 'eletrico_dc', 'configuracao'),
           ('OS-00069', 'Instalação do novo sistema', 'eletrico_dc', 'instalacao'),
           ('OS-00069', 'Adequação de instalação', 'eletrico_dc', 'instalacao'),
           ('OS-00069', 'Desmontagem do sistema', 'eletrico_dc', 'remocao'),
           ('OS-00069', 'Testes e comissionamento', 'eletrico_dc', 'diagnostico'),
           ('OS-00074', 'SUBSTITUIÇÃO BATERIAS', 'eletrico_dc', 'substituicao'),
           ('OS-00074', 'SERVIÇO DE PASSAGEM', 'eletrico_dc', 'instalacao'),
           ('OS-00074', 'INSTALAÇÃO DE PORTA FUSÍVEIS', 'eletrico_dc', 'instalacao'),
           ('OS-00096', 'DIAGNÓSTICO TÉCNICO', 'eletronico', 'diagnostico')
         ) as v(num, comeca, sistema, verbo)
   where so.id = sos.service_order_id and so.service_order_number = v.num and sos.name_snapshot like v.comeca || '%'
     and (sos.service_system is null or sos.service_verb is null);

  -- ── 2. A sintética: Roberto e João de volta, o padrão do Bruno e as OS 171 a 179 ────────────────────────────────
  if not v_real and not exists (select 1 from public.service_orders where id = (c_os || '171')::uuid) then
    select id into strict v_roberto from public.payees where name = 'Roberto' and active;
    select id into strict v_joao from public.payees where name = 'João' and active;
    select id into strict v_bruno from public.payees where name = 'Bruno' and active;

    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em)
    values (v_roberto, '{1,2,3,4,5}', null, 'disponivel', 'diarista', 'Disse em 03/11 (fixture da 7c)', 'seg a sex',
            timestamptz '2026-11-03 10:00-03'),
           (v_joao, '{1,2,3,4,5}', null, 'disponivel', 'diarista', 'Disse em 03/11 (fixture da 7c)', 'seg a sex',
            timestamptz '2026-11-03 10:05-03'),
           (v_bruno, '{1,2,3,4,5}', null, 'disponivel', 'diarista', 'Disse em 03/11', 'seg a sex',
            timestamptz '2026-11-03 10:30-03');

    -- As OS
    for r in
      select * from (values
        ('171', '71', 'Lia',   'repair',        'Substituição baterias chumbo para lítio', 6, null::text),
        ('172', '72', 'Bia',   'repair',        'Instalação de painel solar no teto',      2, null),
        ('173', '73', 'Caio',  'commissioning', 'Comissionamento do sistema de energia',  2, 'nunca'),
        ('174', '74', 'Duda',  'repair',        'Instalação de porta-fusíveis 12V',        1, null),
        ('175', '75', 'Edu',   'repair',        'Instalação de inversor 220 V',            6, null),
        ('176', '76', 'Fábio', 'repair',        'Revisão do quadro elétrico',              4, null),
        ('177', '77', 'Gil',   'repair',        'Troca do banco de baterias',              2, null),
        ('178', '78', 'Hugo',  'repair',        'Instalação de luminárias 12V',            1, null),
        ('179', '79', 'Ivo',   'repair',        'Instalação de carregador e inversor',     2, null)
      ) as t(n, c, nome, tipo, linha, meios, presenca)
    loop
      v_os := (c_os || r.n)::uuid;
      insert into public.clients (id, type, name) values ((c_cli || r.c)::uuid, 'individual', r.nome);
      insert into public.vessels (id, client_id, name, asset_type) values ((c_bem || r.c)::uuid, (c_cli || r.c)::uuid, 'Motorhome', 'Motorhome');
      insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                         created_at, updated_at, converted_to_os_at)
      values (v_os, 'OS-97' || r.n, (c_cli || r.c)::uuid, (c_bem || r.c)::uuid, 'open', 'approved', r.tipo,
              timestamptz '2026-10-26 10:00-03', timestamptz '2026-10-28 10:00-03', timestamptz '2026-10-28 10:00-03');
      insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                                 unit_price_snapshot, line_total, created_at)
      values (md5('c7c:servico:' || r.n)::uuid, v_os, null, r.linha, 'unit', 1, 382 * r.meios, 382 * r.meios,
              timestamptz '2026-10-26 10:00-03');
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, atualizado_por)
      values (v_os, r.meios / 2.0, 'dono', timestamptz '2026-10-28 10:00-03', r.presenca, v_dono_u);
    end loop;

    -- 176 Fábio: o dono disse que pede energizado em todos os dias e que vai com dupla
    update public.os_planejamento
       set exigencias_ditas = '{"energizado": "todos"}', exigencias_trecho = 'no Fábio tudo é com o quadro ligado',
           dupla_dita = 'todos', dupla_motivo = 'você disse: Fábio com dupla', dupla_em = timestamptz '2026-10-28 10:05-03'
     where service_order_id = (c_os || '176')::uuid;
    -- 177 Gil: a equipe dita "só o João"
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos, criado_em)
    values ((c_os || '177')::uuid, v_joao, 'dia', timestamptz '2026-10-28 10:10-03');

    -- 175 Edu: Roberto cumpriu ter 03/11 de manhã e de tarde (o responsável que fez o 1º dia). O resultado é do dia que já chegou
    -- para quem escreve (agenda.hoje: a fixture é de qua 04/11; o relógio da bancada é de 27/10).
    v_hoje_antes := coalesce(current_setting('agenda.hoje', true), '');
    perform set_config('agenda.hoje', '2026-11-04', true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em,
                                         resultado, resultado_via)
    select md5('c7c:aloc:175:' || t.turno)::uuid, (c_os || '175')::uuid, v_roberto, date '2026-11-03', t.turno, 'turno', 'execucao',
           'publicada', 'motor', c_pubs, 'cumprido', 'conversa'
      from (values ('manha'), ('tarde')) t(turno);
    perform set_config('agenda.hoje', v_hoje_antes, true);

    -- 179 Ivo: publicada com o João sozinho na ter 10/11 (manhã e tarde), o dono abre e fecha nesse dia
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5('c7c:aloc:179:' || t.quem || ':' || t.turno)::uuid, (c_os || '179')::uuid,
           case t.quem when 'joao' then v_joao else v_dono end, date '2026-11-10', t.turno, t.presenca, 'execucao', 'publicada',
           'motor', c_pubs
      from (values ('joao', 'manha', 'turno'), ('joao', 'tarde', 'turno'), ('dono', 'manha', 'abertura'),
                   ('dono', 'tarde', 'fechamento')) t(quem, turno, presenca);
  end if;

  -- ── 3. As etiquetas dos testes M e V (só com agenda_teste.fase7c_etiquetas = 'mv', na sintética) ───────────────────
  if not v_real and coalesce(current_setting('agenda_teste.fase7c_etiquetas', true), '') = 'mv'
     and not exists (select 1 from public.agenda_etiquetas e
                      join public.payees py on py.id = e.payee_id where py.name = 'Roberto' and e.estado = 'vale') then
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, evidencia, trecho, vale_desde,
                                         criado_em, criado_por)
    select py.id, t.etiqueta, t.nivel, t.origem, 'vale', t.motivo, t.evidencia::jsonb, t.trecho, t.em::timestamptz,
           t.em::timestamptz, case when t.origem = 'dono' then v_dono_u end
      from (values
        ('Roberto', 'instala',  2::smallint, 'gestor', '32 diárias desde 23/08', '{"diarias": 32, "desde": "2026-08-23"}', null,
         '2026-11-03 16:10-03'),
        ('Roberto', 'altura',   0::smallint, 'dono',   'você disse', '{}', 'o Roberto não sobe no teto', '2026-11-03 18:00-03'),
        ('João',    'ajudante', 2::smallint, 'gestor', 'entrou em 29/09, 15 diárias', '{"diarias": 15, "desde": "2026-09-29"}', null,
         '2026-11-03 16:10-03'),
        ('Bruno',   'ajudante', 1::smallint, 'gestor', 'começou em 20/10, 3 diárias', '{"diarias": 3, "desde": "2026-10-20"}', null,
         '2026-11-03 16:10-03')
      ) as t(nome, etiqueta, nivel, origem, motivo, evidencia, trecho, em)
      join public.payees py on py.name = t.nome and py.active;
  end if;

  -- ── 4. As variantes do novato (uma por carga; R5.1-6). Cada uma confere pelo próprio efeito se já entrou ────────────
  if v_var <> '' and v_var not in ('alex_perfil', 'alex_respondeu', 'alex_semana', 'mateus_terca', 'mateus_terca_sem_perfil',
                                   'bruno_ajudante', 'bruno_instala') then
    raise exception 'fixture-fase7c: a variante % não existe', v_var;
  end if;
  if v_var in ('alex_perfil', 'alex_respondeu', 'alex_semana')
     and not exists (select 1 from public.work_profiles w where w.payee_id = v_alex) then
    insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, jornada_diaria_horas,
                                      meia_diaria_ate_horas, vigencia_inicio, vigencia_fim, created_at, updated_at)
    values (v_alex, 'diarista', 'diaria', 200, 8, 4,
            case v_var when 'alex_semana' then date '2026-11-02' else date '2026-11-03' end, null,
            timestamptz '2026-11-03 10:00-03', timestamptz '2026-11-03 10:00-03');
    if v_var = 'alex_respondeu' then
      -- o próprio Alex responde a semana (o que a resposta da equipe grava): o padrão do dono sai, entra um de origem diarista
      v_r := public._agenda_equipe_dias_gravar(v_alex, date '2026-11-09', '{1,2,3,4}'::smallint[], false, 'diarista', 'seg a qui',
                                               timestamptz '2026-11-03 17:00-03');
    end if;
    if v_var = 'alex_semana' then
      -- o dono declarou o Alex só hoje (qua 04/11), no meio da semana da grade
      update public.agenda_disponibilidade set criado_em = timestamptz '2026-11-04 10:00-03'
       where payee_id = v_alex and origem = 'dono' and dias_semana is not null;
    end if;
  end if;

  if v_var in ('mateus_terca', 'mateus_terca_sem_perfil')
     and not exists (select 1 from public.agenda_disponibilidade d where d.trecho = 'o Mateus vem toda terça') then
    begin
      select id into v_mateus from public.payees where name = 'Mateus' and active order by id limit 1;
      if v_mateus is null then
        insert into public.payees (name, kind, active, phone, created_at, updated_at)
        values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-04 08:00-03', timestamptz '2026-11-04 08:00-03')
        returning id into v_mateus;
      else
        update public.payees set created_at = timestamptz '2026-11-04 08:00-03' where id = v_mateus;
      end if;
      -- "o Mateus vem toda terça" (o padrão de origem dono que o *grava* escreve)
      insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em, criado_por)
      values (v_mateus, '{2}', null, 'disponivel', 'dono', 'Você disse que vem', 'o Mateus vem toda terça',
              timestamptz '2026-11-04 10:00-03', v_dono_u);
      if v_var = 'mateus_terca' then
        insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, jornada_diaria_horas,
                                          meia_diaria_ate_horas, vigencia_inicio, vigencia_fim, created_at, updated_at)
        values (v_mateus, 'diarista', 'diaria', 200, 8, 4, date '2026-11-04', null, timestamptz '2026-11-04 10:00-03',
                timestamptz '2026-11-04 10:00-03');
      end if;
    end;
  end if;

  if v_var in ('bruno_ajudante', 'bruno_instala') then
    select id into strict v_bruno from public.payees where name = 'Bruno' and active;
    if not exists (select 1 from public.agenda_etiquetas e where e.payee_id = v_bruno and e.origem = 'dono') then
      insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
      values (v_bruno, case v_var when 'bruno_ajudante' then 'ajudante' else 'instala' end, 2, 'dono', 'vale', 'você disse',
              case v_var when 'bruno_ajudante' then 'o Bruno é ajudante' else 'o Bruno instala sozinho' end,
              timestamptz '2026-11-04 09:00-03', timestamptz '2026-11-04 09:00-03', v_dono_u);
    end if;
  end if;
end
$f7c$;
