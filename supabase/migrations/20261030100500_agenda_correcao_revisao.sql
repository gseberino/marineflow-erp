-- Agenda de Produção, correção de 29/10: a revisão do lote (os achados da revisão de P1 a P5).
-- (2 parâmetros novos em agenda_config, com os CHECKs; 1 tipo novo de pergunta na lista fechada; 3 funções novas; 9
-- recriadas; nenhum dado muda)
--
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/revc/montar-migration.mjs. As 9 recriadas são o
-- corpo da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote):
-- agenda_aviso_enfileirar e agenda_aviso_pecas de 20261030100300 (P4); _agenda_linhas_do_fechamento de 20261028100500;
-- _agenda_mudancas de 20261029100950; agenda_livre_de_verdade e agenda_simular de 20261030100100 (P2);
-- _agenda_modo_da_pergunta e _agenda_vigia_limpeza de 20261030100200 (P3); agenda_vigiar de 20261030100400 (P5). As
-- mudanças estão só nos blocos "-- CORREÇÃO 29/10 (revisão): … -- CORREÇÃO 29/10 (revisão): fim". Quando um bloco troca
-- uma linha, a linha de antes fica nele como "-- antes: <a linha>" (o K de supabase/tests/agenda_correcao_2910_revisao.sql
-- a devolve no lugar e confere o resto, byte a byte).
--
-- ═══ OS ACHADOS (revisão do lote, 30/10) E O QUE MUDA ═══
--   1. (P4, média) O aviso prometia "*desfaz Vanderlei* volta como estava." de mudança com o prazo vencido, e o *desfaz*
--      era recusado até o conferir do tique seguinte (até 15 min depois do envio). agenda_aviso_enfileirar passa a levar o
--      prazo das ações que conta a p_agora + desfazer_validade (nunca menos; o conferir ainda o leva à hora do envio).
--   2. (Fase 6, baixa) O R10g de agenda_fase6_rodada.sql falhava às vezes: as linhas do aprendizado gravadas no mesmo
--      instante desempatavam pelo id aleatório, e o corte de texto_max levava uma linha diferente a cada rodada (o "e mais
--      N" do aviso também). _agenda_mudancas passa a ordenar o aprendizado numa ordem fixa (fator, presença, folga, valor,
--      capacidade, carga e, por fornecedor, o atraso e o prazo); a frase do *desfaz aprendizado* vai na 1ª delas.
--   3. (P2, baixa) A linha curta do livre dizia "na semana de 04/11" no sábado e no domingo (04/11 é quarta: é o 1º dia que
--      a agenda ainda pode mudar). agenda_livre_de_verdade usa o rótulo do *livre*: "de qua 04 a sex 06/11, …; na semana
--      de 09/11, …".
--   4. (Fase 1, baixa) "(são 1 diária de equipe)" e "(são 0,5 diárias de equipe)" na conta do serviço novo:
--      agenda_simular diz "(é 1 diária de equipe)" e "(é meia diária de equipe)".
--   5. (produção, alta) Em 29/10 às 21:11 (00:11 UTC de 30/10) o dono tirou da agenda Roberto, João e Mickael e pôs o
--      Alex todo dia útil. O Alex não tem a diária cadastrada (work_profiles), e agenda_capacidade só conta quem tem: a
--      equipe ficou sem ninguém. Às 00:15 a vigia cancelou a reserva do Lenine ("quem ia não está mais livre"), e nada
--      contou ao dono por quê; a pergunta "Lenine (OS-00074) tem peça a comprar? Guardei lugar a partir de qui 05/11"
--      continuou aberta com um lugar que não existe mais. Agora:
--      · _agenda_vigia_limpeza resolve a pergunta da reserva (duracao:<os>, material_conferir:<os>, ligado) quando a OS
--        não tem mais reserva condicionada publicada de hoje em diante;
--      · a vigia ganha um passo (agenda_vigiar → _agenda_vigia_equipe_sem_dias): com serviço esperando e ninguém da equipe
--        com dias na agenda (_agenda_equipe_tem_dias, pela mesma agenda_capacidade), pergunta uma vez por semana (tipo novo
--        equipe_sem_dias, da vigia, não crítica), dizendo pelo nome quem tem os dias mas não tem a diária cadastrada e o que
--        fazer ("Me diga o valor da diária para eu cadastrar."); a limpeza a resolve quando a equipe volta a ter dias.
--   6. (P4, média) O aviso e o fechamento das 17:30 podiam contar a mesma mudança: o fechamento lê a agenda no começo e só
--      registra o que mostrou no fim, e o aviso do mesmo minuto enfileirava no meio. De segunda a sexta, de
--      gestor_aviso_pausa_inicio (17:25) a gestor_aviso_pausa_fim (18:00), o aviso espera (motivo fechamento: as peças e a
--      1ª trava, pela regra única _agenda_aviso_espera_o_fechamento); o que estiver por contar vai no fechamento.
--   7. (P4, baixa) A mesma pergunta saía no aviso das 16:50 e de novo no fechamento das 17:30. A pergunta de fato do
--      fechamento (_agenda_linhas_do_fechamento, linha e) não repete a que um aviso de hoje levou ou está levando; e as
--      perguntas do aviso (agenda_aviso_pecas) ficam para amanhã se alguma delas já foi mostrada hoje.
--   Não muda: o que o motor decide e grava, o fechamento fora das linhas da pergunta, o worker, as travas da fila, a tela.
--
-- Ordem de ligar: depois das 20261030100000 a 20261030100400 (P1 a P5). Sem deploy de edge function (nenhum TS mudou).
-- Aplicar com o OK nomeado do dono. Prova: supabase/tests/agenda_correcao_2910_revisao.sql (bancada).
--
-- DESFAZER: recriar as 9 funções com o corpo da migration de origem de cada uma (acima) e
--   alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_tipo_check;  -- e a de 20261029100000
--   (só depois de resolver as perguntas equipe_sem_dias abertas). Os 2 parâmetros e as 3 funções novas podem ficar
--   (ninguém os usa sem as recriadas).
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$, drop constraint if exists + add, create or replace
-- function, revoke e comment.

-- ── 1. Os parâmetros novos: a pausa do aviso durante o fechamento ─────────────────────────────────────────────
-- De segunda a sexta o fechamento das 17:30 (cron 17:30, 17:40 e 17:50) lê a agenda no começo e só registra o que mostrou
-- no fim; o aviso do gestor não enfileira nesse meio tempo. Moram em agenda_config, como toda janela da agenda.
alter table public.agenda_config
  add column if not exists gestor_aviso_pausa_inicio time not null default '17:25',
  add column if not exists gestor_aviso_pausa_fim    time not null default '18:00';

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_gestor_aviso_pausa_inicio_check', 'check (gestor_aviso_pausa_inicio between time ''16:00'' and time ''18:30'')'),
      ('agenda_config_gestor_aviso_pausa_fim_check',    'check (gestor_aviso_pausa_fim between time ''17:00'' and time ''20:00'')'),
      ('agenda_config_gestor_aviso_pausa_ordem_check',  'check (gestor_aviso_pausa_fim > gestor_aviso_pausa_inicio)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.agenda_config.gestor_aviso_pausa_inicio is
  'Agenda de Produção (correção de 29/10, revisão do lote): de segunda a sexta, a partir de quando (Brasília) o aviso do gestor espera o fechamento das 17:30 (que lê a agenda no começo e registra o que mostrou no fim): nesse meio tempo nada vai à fila; o que estiver por contar vai no fechamento.';
comment on column public.agenda_config.gestor_aviso_pausa_fim is
  'Agenda de Produção (correção de 29/10, revisão do lote): até quando (Brasília, aberto) dura a pausa do aviso do gestor durante o fechamento (o último disparo do fechamento é às 17:50). Depois dela, o 1º aviso conta o que mudou e o fechamento não contou.';

-- ── 2. A lista fechada dos tipos de pergunta: equipe_sem_dias ─────────────────────────────────────────────────
-- (os 26 de 20261029100000_agenda_fase6_tabelas.sql e o novo; não é crítica: a coluna gerada critica não muda)
alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_tipo_check;
alter table public.agenda_perguntas add constraint agenda_perguntas_tipo_check
  check (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono',
                  'conferencia','chegou','parada','estouro','duracao','material_conferir','padrao_do_dono',
                  'diaria','diaria_ligar','equipe_resposta','concluir','entrega',
                  'nfe_vincular','pix_material','previsao_fornecedor','fornecedor_cadastro','fornecedores_prazo',
                  'cliente_aprovar','cliente_aviso','cliente_resposta',
                  'aprendizado','equipe_sem_dias'));

-- ── 3. A pausa do aviso (a regra única: as peças e a 1ª trava leem daqui) ─────────────────────────────────────
create or replace function public._agenda_aviso_espera_o_fechamento(p_quando timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce((select extract(isodow from p_quando at time zone 'America/Sao_Paulo')::int between 1 and 5
                          and (p_quando at time zone 'America/Sao_Paulo')::time >= c.gestor_aviso_pausa_inicio
                          and (p_quando at time zone 'America/Sao_Paulo')::time < c.gestor_aviso_pausa_fim
                     from public.agenda_config c where c.id), false);
$function$;

comment on function public._agenda_aviso_espera_o_fechamento(timestamptz) is
  'Agenda de Produção (correção de 29/10, revisão do lote): o aviso do gestor espera o fechamento das 17:30? De segunda a sexta, em Brasília, de gestor_aviso_pausa_inicio (aberto) a gestor_aviso_pausa_fim. agenda_aviso_pecas e agenda_aviso_enfileirar leem daqui (motivo fechamento). Sem a hora = false.';

-- ── 4. A equipe sem dias na agenda ────────────────────────────────────────────────────────────────────────────
-- Alguém da equipe (sem o dono) tem algum meio-dia esperado do 1º dia que a agenda ainda pode mudar até o horizonte? A régua
-- é a mesma da agenda (agenda_capacidade: quem tem a diária cadastrada vigente e os dias na agenda).
create or replace function public._agenda_equipe_tem_dias(p_hoje date)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf   public.agenda_config := public._agenda_cfg();
  v_de date;
begin
  if p_hoje is null then
    raise exception '_agenda_equipe_tem_dias: sem o dia de hoje' using errcode = '22004';
  end if;
  v_de := public.agenda_somar_du(public.agenda_somar_du(p_hoje, cf.congelamento_du), 1);
  return exists (select 1 from public.agenda_capacidade(v_de, v_de + 7 * greatest(cf.horizonte_semanas, 1), p_hoje) c
                  where not c.eh_dono and c.meios_esperados > 0);
end;
$function$;

comment on function public._agenda_equipe_tem_dias(date) is
  'Agenda de Produção (correção de 29/10, revisão do lote): alguém da equipe, sem o dono, tem meio-dia esperado (agenda_capacidade: a diária cadastrada vigente e os dias na agenda) do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado) até horizonte_semanas depois? A pergunta equipe_sem_dias nasce quando não (_agenda_vigia_equipe_sem_dias) e resolve quando sim (_agenda_vigia_limpeza).';

-- A vigia: com serviço esperando e ninguém da equipe com dias na agenda, o motor não marca nada (só cancela a reserva de quem
-- ia: "quem ia não está mais livre"), e nada contava ao dono por quê. Pergunta uma vez por semana (equipe_sem_dias:<a
-- segunda>), não crítica, perde no próximo dia do plano e vence na segunda seguinte. Quem tem os dias na agenda mas não tem
-- a diária cadastrada (sem ela, agenda_capacidade não conta a pessoa) é dito pelo nome, com o que fazer.
create or replace function public._agenda_vigia_equipe_sem_dias(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_seg   date := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_chave text;
  v_n     int;
  v_sem   text[];
  v_txt   text;
  v_perda date;
  v_saiu  boolean;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_vigia_equipe_sem_dias: sem o dia ou a hora' using errcode = '22004';
  end if;
  if cf.modo_vigia not in ('sombra', 'ligado') then
    return jsonb_build_object('criada', false, 'motivo', 'a vigia está desligada');
  end if;
  v_chave := 'equipe_sem_dias:' || v_seg;
  if exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = cf.modo_vigia) then
    return jsonb_build_object('criada', false, 'motivo', 'já perguntei nesta semana');
  end if;
  select count(*)::int into v_n from public.os_carteira(p_hoje);
  if v_n = 0 then
    return jsonb_build_object('criada', false, 'motivo', 'nenhum serviço esperando');
  end if;
  if public._agenda_equipe_tem_dias(p_hoje) then
    return jsonb_build_object('criada', false, 'motivo', 'a equipe tem dias');
  end if;
  -- quem tem os dias na agenda mas não tem a diária cadastrada vigente (a régua de agenda_capacidade)
  v_sem := array(select public._agenda_nome_curto(py.name)
                   from public.payees py
                  where py.active and py.kind in ('prestador', 'diarista', 'funcionario')
                    and exists (select 1 from public.agenda_disponibilidade d
                                 where d.payee_id = py.id and d.substituida_em is null
                                   and d.situacao in ('disponivel', 'confirmada'))
                    and not exists (select 1 from public.work_profiles w
                                     where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                                       and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
                  order by py.name, py.id);
  v_txt := case when v_n = 1 then 'Não consigo marcar o serviço que espera: ninguém da equipe tem dias na agenda.'
                else format('Não consigo marcar nenhum dos %s serviços que esperam: ninguém da equipe tem dias na agenda.', v_n) end
           || case
                when cardinality(v_sem) = 1 then
                  format(' %s tem dias na agenda, mas não tem a diária cadastrada, e sem ela não entra na conta. Me diga o valor da diária para eu cadastrar.', v_sem[1])
                when cardinality(v_sem) > 1 then
                  format(' %s têm dias na agenda, mas não têm a diária cadastrada, e sem ela não entram na conta. Me diga o valor da diária de cada um para eu cadastrar.',
                         public._agenda_lista(v_sem, 3))
                else ' Quem vem e em que dias da semana?' end;
  v_perda := v_seg + (cf.dia_do_plano - 1);
  if v_perda < p_hoje then
    v_perda := v_perda + 7;
  end if;
  v_saiu := public._agenda_vigia_perguntar('equipe_sem_dias', v_chave, null, null, null, v_perda, v_txt, cf.modo_vigia,
                                           p_agora, true);
  if v_saiu then
    update public.agenda_perguntas q set expira_em = (v_seg + 7)::timestamp at time zone 'America/Sao_Paulo'
     where q.chave = v_chave and q.modo = cf.modo_vigia and q.estado = 'aberta' and q.expira_em is null;
  end if;
  return jsonb_build_object('criada', v_saiu, 'motivo', 'ninguém da equipe tem dias', 'servicos', v_n,
                            'sem_diaria', to_jsonb(v_sem));
end;
$function$;

comment on function public._agenda_vigia_equipe_sem_dias(date, timestamptz) is
  'Agenda de Produção (correção de 29/10, revisão do lote): passo da vigia (agenda_vigiar, depois dos outros). Com serviço esperando (os_carteira) e ninguém da equipe com dias na agenda (_agenda_equipe_tem_dias), pergunta uma vez por semana (equipe_sem_dias:<a segunda>, modo_vigia, não crítica, perda_em = o próximo dia do plano, vence na segunda seguinte): "Não consigo marcar nenhum dos 11 serviços que esperam: ninguém da equipe tem dias na agenda. Alex tem dias na agenda, mas não tem a diária cadastrada, e sem ela não entra na conta. Me diga o valor da diária para eu cadastrar." (sem ninguém assim: "Quem vem e em que dias da semana?"). {criada, motivo, servicos?, sem_diaria?}. A limpeza a resolve quando a equipe volta a ter dias.';

-- ── 5. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO 29/10 (revisão):") ─────
-- Fora dos blocos nenhuma linha muda; a linha trocada fica no bloco como "-- antes: …" (o K de
-- supabase/tests/agenda_correcao_2910_revisao.sql confere). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- agenda_aviso_enfileirar (de 20261030100300_agenda_correcao_aviso.sql)
create or replace function public.agenda_aviso_enfileirar(p_texto text, p_acao_ids uuid[], p_pergunta_ids uuid[],
                                                          p_com_perguntas boolean, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_jan   text;
  v_fone  text;
  v_pend  uuid[];
  v_chave text;
  v_id    uuid;
  v_fila  uuid;
  v_tent  int;
  v_det   text;
  v_n     int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aviso_enfileirar: sem o dia ou a hora' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_texto, '')), '') is null or char_length(p_texto) > cf.gestor_aviso_texto_max then
    raise exception 'O aviso veio sem texto ou maior que gestor_aviso_texto_max (% letras).', cf.gestor_aviso_texto_max
      using errcode = '22023';
  end if;
  if coalesce(cardinality(p_acao_ids), 0) = 0 then
    raise exception 'O aviso conta pelo menos uma mudança.' using errcode = '22023';
  end if;
  -- o teto é contado e a linha entra numa vez só, mesmo com dois tiques do motor ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext('agenda_dono_aviso'));
  if not public._agenda_aviso_ligado() then
    return jsonb_build_object('enfileirou', false, 'motivo', 'modo');
  end if;
  select v.id into v_id from public.agenda_dono_avisos v where v.rodada = p_agora;
  if v_id is not null then
    return jsonb_build_object('enfileirou', false, 'motivo', 'ja_existe', 'id', v_id);
  end if;
  v_jan := public._agenda_aviso_fora_da_janela(p_agora, p_agora);
  if v_jan is not null then
    return jsonb_build_object('enfileirou', false, 'motivo', 'fora_da_janela', 'janela', v_jan);
  end if;
  -- CORREÇÃO 29/10 (revisão): a 1ª trava também espera o fechamento das 17:30 (a mesma regra das peças).
  if public._agenda_aviso_espera_o_fechamento(p_agora) then
    return jsonb_build_object('enfileirou', false, 'motivo', 'fechamento');
  end if;
  -- CORREÇÃO 29/10 (revisão): fim
  if public._agenda_aviso_no_dia((p_agora at time zone 'America/Sao_Paulo')::date, null) >= cf.gestor_aviso_dia_max then
    return jsonb_build_object('enfileirou', false, 'motivo', 'teto');
  end if;
  select d.phone into v_fone from public._agenda_aviso_dono() d;
  if v_fone is null then
    return jsonb_build_object('enfileirou', false, 'motivo', 'sem_dono');
  end if;
  -- as mudanças do aviso ainda estão por contar (o fechamento ou outro aviso pode ter contado no meio)
  v_pend := array(select x::uuid from jsonb_array_elements(public._agenda_aviso_mudancas(p_hoje)) g,
                                      jsonb_array_elements_text(g -> 'acao_ids') x);
  if not (p_acao_ids <@ v_pend) then
    return jsonb_build_object('enfileirou', false, 'motivo', 'mudou');
  end if;

  v_chave := 'agenda-dono:aviso:' || to_char(p_agora at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"."US');
  insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, com_perguntas, telefone, enviar_em,
                                         dedupe_key, criada_em)
  values (p_agora, p_hoje, p_texto, p_acao_ids, coalesce(p_pergunta_ids, '{}'::uuid[]), coalesce(p_com_perguntas, false),
          v_fone, p_agora, v_chave, p_agora)
  returning id into v_id;
  -- as tentativas (+5 min) que cabem na janela (a regra única; a 1ª já cabe)
  v_tent := greatest(1, (select count(*)::int from generate_series(0, 2) k
                          where public._agenda_aviso_fora_da_janela(p_agora, p_agora + make_interval(mins => 5 * k)) is null));
  -- a trava da fila (o gatilho) recusa com 23514 o que passaria da janela ou do teto: aqui isso vira a recusa do aviso, e as
  -- mudanças continuam por contar
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for,
                                            max_attempts, dedupe_key)
    values (v_fone, p_texto, 'agenda-dono', v_id, 1, p_agora, v_tent, v_chave)
    returning id into v_fila;
  exception when sqlstate '23514' then
    get stacked diagnostics v_det = pg_exception_detail;
    update public.agenda_dono_avisos
       set estado = 'recusada', recusa_motivo = case when v_det in ('janela', 'domingo', 'modo', 'teto') then v_det else 'janela' end,
           devolvida_em = p_agora
     where id = v_id;
    return jsonb_build_object('enfileirou', false, 'motivo', 'recusada', 'id', v_id, 'pela_fila', coalesce(v_det, '?'));
  end;
  if v_fila is null then
    -- a mesma chave já estava na fila (o gatilho de idempotência de produção devolve nada): é a mesma rodada
    select q.id into v_fila from public.whatsapp_send_queue q where q.dedupe_key = v_chave;
  end if;
  update public.agenda_dono_avisos set estado = 'enfileirada', fila_id = v_fila where id = v_id;
  update public.agenda_acoes a set contada_em = p_agora, contada_via = 'aviso'
   where a.id = any (p_acao_ids) and a.contada_em is null;
  get diagnostics v_n = row_count;
  -- CORREÇÃO 29/10 (revisão): o prazo do *desfaz* já conta de agora. O aviso promete o *desfaz* mesmo de mudança
  -- com o prazo vencido (_agenda_aviso_mudancas lê sem a hora) e só o conferir do tique seguinte o estendia: entre o envio e
  -- esse tique (até 15 min), *desfaz Vanderlei* respondia "não tenho mudança". Agora o prazo vai a p_agora + desfazer_validade
  -- já aqui (nunca menos do que era; o gatilho _agenda_acoes_so_desfaz só deixa adiantar a ação contada pelo aviso); o
  -- conferir ainda o leva à hora do envio + desfazer_validade. Se o aviso não sair, a ação volta a "por contar" e o prazo fica
  -- (o próximo aviso ou o fechamento a contam dentro dele).
  update public.agenda_acoes a
     set desfazivel_ate = p_agora + cf.desfazer_validade
   where a.id = any (p_acao_ids) and a.contada_via = 'aviso' and a.contada_em = p_agora
     and a.desfeita_em is null and a.desfazivel_ate is not null and a.desfazivel_ate < p_agora + cf.desfazer_validade;
  -- CORREÇÃO 29/10 (revisão): fim
  return jsonb_build_object('enfileirou', true, 'id', v_id, 'fila_id', v_fila, 'tentativas', v_tent, 'acoes', v_n,
                            'perguntas', coalesce(cardinality(p_pergunta_ids), 0));
end;
$function$;

comment on function public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): a 1ª trava do aviso do gestor — sob a trava, de novo: o modo (_agenda_aviso_ligado), a rodada (uma por rodada: ja_existe), a janela (_agenda_aviso_fora_da_janela: fora_da_janela), o teto (_agenda_aviso_no_dia ≥ gestor_aviso_dia_max: teto), o dono (_agenda_aviso_dono: sem_dono) e as ações ainda por contar (_agenda_aviso_mudancas: mudou) — nesses casos nada é gravado. Senão registra em agenda_dono_avisos, põe na fila (source agenda-dono, source_ref_id = o aviso, a chave agenda-dono:aviso:<rodada>, priority 1, às p_agora, as tentativas que cabem na janela) e conta as ações (contada_em p_agora, contada_via aviso: provisório até o conferir). O 23514 da trava da fila vira o aviso recusado e devolvido. Texto vazio, maior que gestor_aviso_texto_max ou sem ação = 22023. Definer, só o service_role. CORREÇÃO 29/10 (revisão): (1) o prazo do *desfaz* das ações contadas vai a p_agora + desfazer_validade já no enfileirar (nunca menos; o conferir ainda o leva à hora do envio), e o *desfaz* que o aviso promete vale desde que ele sai; (2) de segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, não enfileira (motivo fechamento): o fechamento das 17:30 conta o que estiver por contar, sem corrida.';

-- agenda_aviso_pecas (de 20261030100300_agenda_correcao_aviso.sql)
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
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aviso_pecas: sem o dia ou a hora' using errcode = '22023';
  end if;
  if not public._agenda_aviso_ligado() then
    return jsonb_build_object('avisar', false,
      'motivo', case when cf.modo_proposta = 'ligado' and cf.modo_vigia = 'ligado' then 'desligado' else 'modo' end);
  end if;
  v_m := public._agenda_aviso_mudancas(p_hoje);
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
  'Agenda de Produção (correção de 29/10, P4): as peças do aviso do gestor ao dono, sem gravar nada (o texto é montado em _shared/agenda/aviso-do-gestor.ts). Não avisa (avisar false + motivo): modo, desligado (gestor_aviso_dia_max 0), nada_mudou, fora_da_janela (+ pendentes: sai junto na abertura), teto (+ pendentes), sem_dono. Avisa: {rodada, dia, limite (gestor_aviso_texto_max), cabecalho, mudancas [{texto do *o que mudou*, acao_ids}] (_agenda_aviso_mudancas), fora (_agenda_aviso_fora_texto, pelas propostas das mudanças), rodape, perguntas {texto de agenda_aprontar, pergunta_ids que ele cobre, oss, voce} — uma vez por dia — ou null, perguntas_erro (a rodada de aprontar falhou: o que mudou sai do mesmo jeito; o passo do motor registra o erro)}. STABLE, definer, só o service_role. CORREÇÃO 29/10 (revisão): (1) de segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, não avisa (motivo fechamento, + pendentes): o fechamento das 17:30 conta o que estiver por contar, e o resto sai no 1º aviso depois; (2) as perguntas saem uma vez por dia: se alguma das que o texto cobre já foi mostrada hoje (fechamento, conversa, acorde), ficam para amanhã.';

-- _agenda_linhas_do_fechamento (de 20261028100500_agenda_fase5_leituras.sql)
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

  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia.';

-- _agenda_mudancas (de 20261029100950_agenda_fase6_correcao_textos.sql)
create or replace function public._agenda_mudancas(p_de date, p_ate date, p_executada boolean, p_fechamento boolean,
                                                   p_agora timestamptz default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: o que a agenda aprendeu sozinha (tipo aprendizado, origem motor/vigia), com a
  -- mesma régua de b (o período, executada, contada e desfeita), agrupado por ITEM do mesmo instante: o fator e a presença
  -- mudam várias classes de uma vez (um grupo só); o fornecedor e os outros, um grupo por chave. r = 1 é a linha do grupo
  -- (a classe mais fina ainda não desfeita); as outras entram nele (junto, em todos). O texto sem o "*desfaz aprendizado*
  -- volta…" da ação; palavra = a coisa do *desfaz aprendizado <coisa>* desta linha.
  ap as (
    select q.*, first_value(q.id) over w as cabeca, row_number() over w as r,
           min(q.id::text) over (partition by q.grupo) as min_id
           -- CORREÇÃO 29/10 (revisão): a ordem fixa do aprendizado (o fator, a presença, a folga, o valor, a capacidade, a
           -- carga e, por fornecedor, o atraso e o prazo). As linhas do aprendizado gravadas no mesmo instante desempatavam pelo id
           -- (aleatório): a cada rodada o corte de texto_max levava uma linha diferente (o R10g de agenda_fase6_rodada.sql falhava às
           -- vezes) e o "e mais N" do aviso do gestor também mudava.
           , case q.item when 'fator' then '1' when 'presenca' then '2' when 'aviso_folga' then '3' when 'mo' then '4'
                         when 'capacidade_dono' then '5' when 'carga' then '6'
                         when 'fornecedor_atraso' then '7:' || coalesce(q.chave, '') || ':1'
                         when 'fornecedor_prazo' then '7:' || coalesce(q.chave, '') || ':2'
                         else '9:' || coalesce(q.item, '') end as ordem
           -- CORREÇÃO 29/10 (revisão): fim
      from (select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id, a.criada_em as em,
                   a.antes ->> 'item' as item, a.antes ->> 'chave' as chave, (a.depois ->> 'em_uso')::numeric as valor,
                   regexp_replace(public._agenda_vence_no_dia(a.texto, a.dia, p_ate), '\s*\*desfaz aprendizado\* volta[^*]*$', '') as texto,
                   a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
                   a.desfeita_em is not null as desfeita,
                   concat_ws(':', a.antes ->> 'item',
                             case when a.antes ->> 'item' not in ('fator', 'presenca') then a.antes ->> 'chave' end,
                             to_char(a.criada_em at time zone 'UTC', 'YYYYMMDDHH24MISSUS')) as grupo,
                   case a.antes ->> 'nivel' when 'fina' then 1 when 'sistema' then 2 when 'bem' then 3 when 'todas' then 4 else 5 end as nr,
                   case a.antes ->> 'item'
                     when 'fator' then 'fator' when 'presenca' then 'presença' when 'mo' then 'valor'
                     when 'aviso_folga' then 'folga' when 'capacidade_dono' then 'capacidade' when 'carga' then 'carga'
                     when 'fornecedor_atraso' then public._agenda_fornecedor_curto((a.antes ->> 'chave')::uuid)
                     when 'fornecedor_prazo' then public._agenda_fornecedor_curto((a.antes ->> 'chave')::uuid) end as palavra
              from public.agenda_acoes a
             where a.dia between p_de and p_ate and a.executada = p_executada and a.tipo = 'aprendizado'
               and a.origem in ('motor', 'vigia')
               and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))) q
    window w as (partition by q.grupo order by q.desfeita, q.nr, q.chave, q.id)
  ),
  -- CORREÇÃO FASE 6: fim
  b as (
    -- FASE 3 (revisão, item 5): o texto gravado noutro dia diz a data no lugar de "vence hoje" (p_ate é o hoje de quem lê:
    -- o foco mudancas, o fechamento e a tela passam p_hoje).
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           public._agenda_vence_no_dia(a.texto, a.dia, p_ate) as texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo not in ('resultado', 'desfazer', 'fixar')
       and (a.origem in ('motor', 'vigia') or (not p_fechamento and a.origem = 'conferencia'))
       -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: o que a agenda aprendeu sozinha vem do ramo dele (ap: uma linha por item)
       and a.tipo <> 'aprendizado'
       -- CORREÇÃO FASE 6: fim
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 5: o acorde da mensagem ao cliente (tipo cliente, origem vigia, depois.acorde) é um aviso ao dono, não uma
    -- mudança; e a ação do replano que o pedido do cliente causou (depois.replano_acoes da ação dele) vai no grupo da ação
    -- do cliente (filhos), nunca sozinha — sem contar duas vezes.
       and not (a.tipo = 'cliente' and a.origem = 'vigia' and coalesce((a.depois ->> 'acorde')::boolean, false))
       and not exists (select 1 from public.agenda_acoes c
                        where c.origem = 'cliente' and c.tipo = 'cliente' and c.depois -> 'replano_acoes' ? a.id::text)
    -- FASE 5: fim
    -- FASE 4: (P3) o material que a agenda registrou sozinha — a chegada pela nota importada (origem nota; P4: a previsão
    -- pela mensagem do fornecedor, origem fornecedor) — entra como as ações do motor e da vigia.
    union all
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           public._agenda_vence_no_dia(a.texto, a.dia, p_ate) as texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo = 'material' and a.origem in ('nota', 'fornecedor')
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 4: fim
    -- FASE 5: o que a resposta do cliente mudou sozinho (origem cliente: o dia que ele confirmou, o pedido de outro dia, o
    -- acesso anotado, o opt-out) entra como as ações do motor e da vigia; o "*desfaz <nome>* volta como estava." que o
    -- texto já traz sai (a frase do grupo o põe enquanto ainda vale).
    union all
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           regexp_replace(public._agenda_vence_no_dia(a.texto, a.dia, p_ate), '\s*\*desfaz [^*]+\* volta como estava\.$', '') as texto,
           a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.origem = 'cliente' and a.tipo in ('cliente', 'fixar')
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 5: fim
    -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: o aprendizado, UMA linha por item do mesmo instante (ap, r = 1): o texto da
    -- classe mais fina e "Também nas OS de … e nas …" para as outras classes do item (com o valor de cada uma quando não é
    -- o mesmo de todas); sem o "*desfaz aprendizado* volta" de cada ação; na 1ª linha desfazível (a ordem dos grupos: em,
    -- o menor id), UMA vez, "*desfaz aprendizado* volta tudo; *desfaz aprendizado <coisa>* volta só essa" — com uma linha
    -- só, "*desfaz aprendizado* volta.". Sem nome: o "*desfaz <nome>* volta como estava." do grupo não se aplica (M1).
    -- NOTA (desvio): a frase vai no fim da 1ª linha, não da última — o fechamento (480 letras) e o foco (texto_max) cortam
    -- pelas últimas linhas, e no fim a frase sumiria em toda rodada com 3 trocas ou mais.
    union all
    select h.id, h.tipo, h.os, h.dia, h.proposta_id,
           h.texto
           || coalesce(' Também ' || nullif(public._agenda_lista(array(
                select case when o.chave = 'todas' then 'em todas as OS'
                            when o.r = 2 then 'n' || public._agenda_classe_texto_do_nivel(o.chave)
                            else 'n' || regexp_replace(public._agenda_classe_texto_do_nivel(o.chave), '^as OS ', 'as ') end
                       || case when exists (select 1 from ap v where v.grupo = h.grupo and v.valor is distinct from h.valor)
                               then ' (' || public._agenda_aprendizado_valor(o.item, o.valor) || ')' else '' end
                  from ap o
                 where o.grupo = h.grupo and o.r > 1
                 order by o.r), null), '') || '.', '')
           || case when h.desfazivel
                        -- CORREÇÃO 29/10 (revisão): a 1ª linha desfazível do aprendizado pela mesma ordem fixa.
                        -- antes: and h.id = (select f.id from ap f where f.r = 1 and f.desfazivel order by f.em, f.min_id limit 1)
                        and h.id = (select f.id from ap f where f.r = 1 and f.desfazivel order by f.em, f.ordem, f.min_id limit 1)
                        -- CORREÇÃO 29/10 (revisão): fim
                   then case when (select count(*) from ap f where f.r = 1 and f.desfazivel) > 1 and h.palavra is not null
                             then format(' *desfaz aprendizado* volta tudo; *desfaz aprendizado %s* volta só %s.', h.palavra,
                                         case when h.item in ('fornecedor_atraso', 'fornecedor_prazo')
                                              then 'o que é de ' || h.palavra else 'essa' end)
                             else ' *desfaz aprendizado* volta.' end
                   else '' end as texto,
           h.em, h.desfazivel, h.desfeita, null::text as nome, null::text as numero
      from ap h
     where h.r = 1
    -- CORREÇÃO FASE 6: fim
  ),
  -- FASE 5: as ações do replano que o pedido do cliente causou: no grupo da ação dele (contam com ela; frase só a dela)
  filhos as (
    select f.id, f.tipo, f.service_order_id as os, f.dia, f.proposta_id, f.texto, f.criada_em as em, false as desfazivel,
           f.desfeita_em is not null as desfeita, null::text as nome, null::text as numero, 'a:' || b.id as grupo
      from b
      join public.agenda_acoes c on c.id = b.id and c.origem = 'cliente' and c.tipo = 'cliente'
      cross join lateral jsonb_array_elements_text(coalesce(c.depois -> 'replano_acoes', '[]'::jsonb)) r(fid)
      join public.agenda_acoes f on f.id::text = r.fid
     where f.executada = p_executada and (not p_fechamento or (f.contada_em is null and f.desfeita_em is null))
  ),
  -- FASE 5: fim
  dono as (
    select b.*, coalesce(case when b.tipo = 'publicar' then 'p:' || b.proposta_id end, 'a:' || b.id) as grupo, false as junto
      from b where b.tipo <> 'status'
  ),
  st as (
    -- FASE 3: a mesma ordem (criada_em, OS, id) para achar o grupo
    select s.*, coalesce((select d.grupo from dono d where d.os = s.os and d.dia = s.dia order by d.em, d.os, d.id limit 1),
                         'a:' || s.id) as grupo
      from b s where s.tipo = 'status'
  ),
  todos as (
    select d.* from dono d
    union all
    select s.id, s.tipo, s.os, s.dia, s.proposta_id, s.texto, s.em, s.desfazivel, s.desfeita, s.nome, s.numero, s.grupo,
           s.grupo <> 'a:' || s.id
      from st s
    -- FASE 5: o replano pedido pelo cliente, junto da ação dele (sem frase própria)
    union all
    select f.id, f.tipo, f.os, f.dia, f.proposta_id, f.texto, f.em, f.desfazivel, f.desfeita, f.nome, f.numero, f.grupo, true
      from filhos f
    -- FASE 5: fim
    -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: as outras classes do mesmo item do aprendizado, no grupo da linha dele (contam
    -- com ela e saem com ela; sem frase própria)
    union all
    select j.id, j.tipo, j.os, j.dia, j.proposta_id, j.texto, j.em, j.desfazivel, j.desfeita, null::text, null::text,
           'a:' || j.cabeca, true
      from ap j
     where j.r > 1
    -- CORREÇÃO FASE 6: fim
  ),
  g as (
    -- FASE 3: dentro do grupo, a ordem de gravação é criada_em, OS, id (o que entra na mesma transação tem o mesmo
    -- criada_em e o id é aleatório: o G10 de agenda_fase2_leituras.sql falhava cerca de 1 vez em 15)
    select t.grupo,
           case when t.grupo like 'p:%' then 'publicacao' else 'acao' end as tipo,
           min(t.proposta_id::text) filter (where t.tipo = 'publicar') as proposta_id,
           jsonb_agg(t.id order by t.em, t.os nulls last, t.id) as acao_ids,
           coalesce(jsonb_agg(t.texto order by t.em, t.os nulls last, t.id) filter (where not t.junto), '[]'::jsonb) as itens,
           min(t.os::text) filter (where not t.junto) as os,
           min(t.nome) filter (where not t.junto) as nome,
           min(t.numero) filter (where not t.junto) as numero,
           coalesce(bool_or(t.desfazivel) filter (where not t.junto), false) as desfazivel,
           coalesce(bool_and(t.desfeita) filter (where not t.junto), false) as desfeita,
           min(t.em) as em, min(t.os::text) as desempate_os, min(t.id::text) as desempate
           -- CORREÇÃO 29/10 (revisão): a ordem fixa do grupo do aprendizado (nula nos outros).
           , min((select f.ordem from ap f where f.id = t.id)) as ordem
           -- CORREÇÃO 29/10 (revisão): fim
      from todos t
     group by t.grupo
  )
  select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'tipo', g.tipo, 'proposta_id', g.proposta_id,
                                               'acao_ids', g.acao_ids, 'itens', g.itens, 'os', g.os, 'nome', g.nome,
                                               'numero', g.numero, 'desfazivel', g.desfazivel, 'desfeita', g.desfeita,
                                               'em', g.em)
                            -- FASE 3: entre os grupos, a mesma ordem (criada_em, OS, id)
                            -- CORREÇÃO 29/10 (revisão): entre os grupos do mesmo instante sem OS, o aprendizado pela ordem fixa (antes, o id).
                            -- antes: order by g.em, g.desempate_os nulls last, g.desempate), '[]'::jsonb)
                            order by g.em, g.desempate_os nulls last, g.ordem nulls first, g.desempate), '[]'::jsonb)
                            -- CORREÇÃO 29/10 (revisão): fim
    from g;
$function$;

comment on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a ordem de gravação criada_em, OS, id): o que a agenda mudou sozinha (motor e vigia; fora do fechamento também o replano da conferência) com agenda_acoes.dia em [p_de, p_ate], em grupos — a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela. Fase 4, P3: também a ação material da nota importada e da mensagem do fornecedor (origens nota e fornecedor). p_executada false = o que a sombra teria feito; p_fechamento = só o não contado e não desfeito, só motor e vigia. [{grupo, tipo, proposta_id, acao_ids, itens, os, nome, numero, desfazivel, desfeita, em}]. Fase 5, P5: também o que a resposta do cliente mudou (origem cliente: fixar e cliente — o dia confirmado, o pedido de outro dia, o acesso, o opt-out), com as ações do replano dele (depois.replano_acoes) no mesmo grupo (contadas juntas, a frase só a do cliente); o acorde da mensagem ao cliente (tipo cliente, origem vigia, depois.acorde) não é mudança e não entra. CORREÇÃO FASE 6 (C2, item 6 e texto 2): o aprendizado sai UMA linha por item do mesmo instante (o fator e a presença de várias classes juntos: a classe mais fina e "Também nas OS de …"; as outras ações no grupo, junto), sem o "*desfaz aprendizado* volta" de cada ação; na 1ª linha desfazível, uma vez, "*desfaz aprendizado* volta tudo; *desfaz aprendizado <coisa>* volta só essa". CORREÇÃO 29/10 (revisão): as linhas do aprendizado do mesmo instante saem numa ordem fixa (fator, presença, folga, valor, capacidade, carga e, por fornecedor, o atraso e o prazo), não pelo id aleatório; a frase do *desfaz aprendizado* vai na 1ª delas.';

-- agenda_livre_de_verdade (de 20261030100100_agenda_correcao_livre.sql)
create or replace function public.agenda_livre_de_verdade(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  -- quantas semanas o livre mostra (a 1ª é a do 1º dia que a agenda ainda pode mudar) e quantas vão na linha da semana
  c_semanas  constant int := 3;
  c_na_linha constant int := 2;
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_t0     timestamptz := clock_timestamp();
  v_g      jsonb;
  v_ctx    jsonb;
  v_ini    date;
  v_de     date;
  v_minh   int;
  v_nh     int;
  v_nw     int;
  v_np     int;
  v_dono   int;
  v_padrao boolean;
  v_util   boolean[];
  v_sem    int[];
  v_cap    int[];
  v_ocup   int[];
  v_t80    int[];
  v_t100   int[];
  v_uc     int[];
  v_ur     int[];
  v_pes    uuid[];
  v_nomes  text[];
  v_seg1   date;
  v_ate    date;
  v_seg    date;
  v_d0     date;
  v_d1     date;
  v_dsem   date;
  v_w      int;
  k        int;
  v_pessoas jsonb;
  v_semanas jsonb := '[]'::jsonb;
  v_quem   text;
  v_rot    text;
  v_plano  uuid[];
  v_ocupa  jsonb;
  v_pn     jsonb;
  v_trav   jsonb;
  v_pront  jsonb;
  v_andam  jsonb;
  v_parad  int;
  v_esp    int;
  v_lin    text[];
  v_curta  text[] := '{}';
  v_txt    text;
  v_linha  text;
  -- CORREÇÃO 29/10 (revisão): a 1ª semana da linha curta foi pela metade
  v_meia   boolean := false;
  -- CORREÇÃO 29/10 (revisão): fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_livre_de_verdade: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  -- O plano só manda em 'ligado': fora disso, quem chama usa a projeção da Fase 1 (fila ÷ capacidade).
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('fonte', 'projecao', 'motivo', 'a agenda automática não está ligada');
  end if;

  -- A grade do motor de agora (o plano vigente inteiro: o marcado e o reservado).
  v_g := public._agenda_grade_de_agora(p_hoje);
  v_ctx := v_g -> 'ctx';
  v_ini := (v_g ->> 'ini')::date;
  v_de := (v_g ->> 'de')::date;
  v_minh := (v_g ->> 'min_h')::int;
  v_nh := (v_ctx ->> 'nh')::int;
  v_nw := (v_ctx ->> 'nw')::int;
  v_np := (v_ctx ->> 'np')::int;
  v_dono := coalesce((v_ctx ->> 'dono')::int, 0);
  v_padrao := coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false);
  v_util := public._agenda_bools(v_ctx -> 'util');
  v_sem := public._agenda_ints(v_ctx -> 'sem');
  v_cap := public._agenda_ints(v_ctx -> 'cap');
  v_ocup := public._agenda_ints(v_ctx -> 'ocup');
  v_t80 := public._agenda_ints(v_ctx -> 'teto80');
  v_t100 := public._agenda_ints(v_ctx -> 'teto100');
  v_uc := public._agenda_ints(v_ctx -> 'uso_c');
  v_ur := public._agenda_ints(v_ctx -> 'uso_r');
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') with ordinality t(x, o) order by o);
  v_nomes := array(select x from jsonb_array_elements_text(v_ctx -> 'nomes') with ordinality t(x, o) order by o);
  v_seg1 := v_de - (extract(isodow from v_de)::int - 1);
  v_ate := v_seg1 + 7 * (c_semanas - 1) + 5;

  -- ── As semanas: quantos meios-dias cada pessoa ainda pega (a conta do encaixe) ──
  for k in 0 .. c_semanas - 1 loop
    v_seg := v_seg1 + 7 * k;
    v_w := (v_seg - v_ini) / 7 + 1;
    exit when v_w > v_nw;
    -- o 1º e o último dia útil que contam (na 1ª semana, a partir do 1º dia que a agenda ainda pode mudar) e o 1º da semana
    select min(g::date) filter (where g::date >= v_de), max(g::date) filter (where g::date >= v_de), min(g::date)
      into v_d0, v_d1, v_dsem
      from generate_series(v_seg, v_seg + 5, interval '1 day') g
     where public.agenda_dia_util(g::date);
    continue when v_d0 is null;
    select coalesce(jsonb_agg(jsonb_build_object(
             'payee_id', v_pes[s.q], 'nome', case when s.q = v_dono then 'você' else v_nomes[s.q] end, 'eh_dono', s.q = v_dono,
             'meios', s.meios, 'celulas', s.cels, 'teto', s.t80, 'compromisso', s.uc, 'reserva', s.ur)
             order by s.meios desc, s.q), '[]'::jsonb)
      into v_pessoas
      from (select z.q, z.cels, z.t80, z.uc, z.ur, greatest(0, least(z.t80 - z.uc, z.t100 - z.uc - z.ur, z.cels)) as meios
              from (select q,
                           v_t80[(q - 1) * v_nw + v_w] as t80, v_t100[(q - 1) * v_nw + v_w] as t100,
                           v_uc[(q - 1) * v_nw + v_w] as uc, v_ur[(q - 1) * v_nw + v_w] as ur,
                           (select count(*)::int from generate_series(1, v_nh) h
                             where v_sem[(h + 1) / 2] = v_w and v_util[(h + 1) / 2] and h >= v_minh
                               and v_cap[(q - 1) * v_nh + h] = 1 and v_ocup[(q - 1) * v_nh + h] = 0) as cels
                      from generate_series(1, v_np) q
                     where q <> v_dono or v_padrao) z) s;
    v_quem := case
      when jsonb_array_length(v_pessoas) = 0 then 'ninguém da equipe tem os dias na agenda'
      when not exists (select 1 from jsonb_array_elements(v_pessoas) e where (e ->> 'meios')::int > 0) then 'ninguém livre'
      else array_to_string(array(select format('%s %s', e ->> 'nome', public._agenda_meios_texto((e ->> 'meios')::int))
                                   from jsonb_array_elements(v_pessoas) with ordinality t(e, o) order by o), ', ') end;
    -- (a 1ª semana pela metade: "De qua 04 a sex 06/11"; um dia só: "Sex 06/11")
    v_rot := case when v_d0 = v_dsem then public._agenda_titulo_da_semana(v_seg)
                  when v_d0 = v_d1 then public._agenda_maiuscula(public._dia_curto(v_d0))
                  else format('De %s a %s', case when to_char(v_d0, 'MM') = to_char(v_d1, 'MM') then public._agenda_dia_sem_mes(v_d0)
                                                 else public._dia_curto(v_d0) end, public._dia_curto(v_d1)) end;
    v_semanas := v_semanas || jsonb_build_object('seg', v_seg, 'de', v_d0, 'ate', v_d1, 'rotulo', v_rot, 'pessoas', v_pessoas,
                                                 'texto', format('• %s: %s.', v_rot, v_quem));
    if jsonb_array_length(v_semanas) <= c_na_linha then
      v_curta := v_curta || format('%s %s, %s', case when jsonb_array_length(v_semanas) = 1 then 'na semana de' else 'na de' end,
                                   to_char(v_d0, 'DD/MM'), v_quem);
    end if;
    -- CORREÇÃO 29/10 (revisão): a 1ª semana pela metade (o 1º dia que a agenda ainda pode mudar cai no meio dela) não
    -- é "a semana de 04/11" (04/11 é quarta): sai o rótulo do *livre* ("de qua 04 a sex 06/11"; um dia só, "na sex 06/11"), e a
    -- seguinte vira "na semana de 09/11".
    if jsonb_array_length(v_semanas) <= c_na_linha then
      if v_d0 <> v_dsem then
        v_curta[cardinality(v_curta)] := format('%s, %s', case when v_d0 = v_d1 then 'na ' || public._dia_curto(v_d0)
                                                               else 'de ' || substr(v_rot, 4) end, v_quem);
        v_meia := true;
      elsif v_meia and jsonb_array_length(v_semanas) = 2 then
        v_curta[cardinality(v_curta)] := format('na semana de %s, %s', to_char(v_d0, 'DD/MM'), v_quem);
      end if;
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
  end loop;

  -- ── O que ocupa a equipe: o plano de hoje ao sábado da última semana, por OS, com quem fica o turno ──
  -- (o nome como nas outras listas da agenda: o número só quando o nome se repete na carteira, "Rodrigo OS-00096")
  v_pn := public._agenda_painel(p_hoje);
  v_plano := array(select distinct a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje);
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', z.os, 'numero', z.numero, 'reserva', z.reserva, 'dias', to_jsonb(z.dias), 'pessoas', z.pessoas,
           'texto', format('%s (%s%s%s)', z.nome, case when z.reserva then 'reserva, ' else '' end, public._agenda_dias_texto(z.dias),
                           coalesce(', com ' || nullif(z.pessoas, ''), '')))
           order by z.d1, z.numero collate "C"), '[]'::jsonb)
    into v_ocupa
    from (select y.*
            from (select v.service_order_id as os, min(v.numero) as numero,
                         coalesce((select public._agenda_rotulo(e, 'np') from jsonb_array_elements(coalesce(v_pn -> 'oss', '[]'::jsonb)) e
                                    where (e ->> 'os')::uuid = v.service_order_id limit 1),
                                  min(v.cliente_curto), min(v.numero)) as nome,
                         bool_and(v.reserva) as reserva, min(v.dia) as d1, array_agg(v.dia order by v.dia) as dias,
                         (select public._agenda_lista(array_agg(p.quem order by p.dono desc, p.primeiro, p.quem), null)
                            from (select case when coalesce((x ->> 'eh_dono')::boolean, false) then 'você' else x ->> 'nome' end
                                           as quem,
                                         bool_or(coalesce((x ->> 'eh_dono')::boolean, false)) as dono, min(v2.dia) as primeiro
                                    from public.v_agenda_dia v2
                                   cross join lateral jsonb_array_elements(v2.pessoas) x
                                   where v2.service_order_id = v.service_order_id and v2.dia between p_hoje and v_ate
                                     and x ->> 'presenca' = 'turno'
                                   group by 1) p
                           where p.quem is not null) as pessoas
                    from public.v_agenda_dia v
                   where v.dia between p_hoje and v_ate
                   group by v.service_order_id) y) z;

  -- ── O que não ocupa ninguém: a carteira fora do plano ──
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int)
                    filter (where e ->> 'grupo' in ('quase', 'travado', 'esperando')), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int) filter (where e ->> 'grupo' = 'pronto'), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int)
                    filter (where e ->> 'grupo' in ('andamento', 'marcado')), '[]'::jsonb),
         count(*) filter (where e ->> 'grupo' = 'parado')::int,
         count(*) filter (where e ->> 'grupo' = 'espera')::int
    into v_trav, v_pront, v_andam, v_parad, v_esp
    from jsonb_array_elements(coalesce(v_pn -> 'oss', '[]'::jsonb)) e
   where not ((e ->> 'os')::uuid = any (v_plano));

  -- ── O texto ──
  v_lin := array['Livre de verdade (pelo plano de agora e pelos dias que cada um vem):']
           || array(select e ->> 'texto' from jsonb_array_elements(v_semanas) with ordinality t(e, o) order by o);
  if v_dono > 0 and not v_padrao then
    v_lin := v_lin || 'Você fica de fora da conta: não sei em que dias você fica em campo (é só me dizer, por exemplo, "fico em campo de segunda a sexta").'::text;
  end if;
  v_lin := v_lin || case
    when jsonb_array_length(v_ocupa) = 0 then format('Até %s, nada do plano ocupa a equipe.', public._dia_curto(v_ate))
    else 'Ocupa a equipe: '
         || public._agenda_lista(array(select e ->> 'texto' from jsonb_array_elements(v_ocupa) with ordinality t(e, o) order by o), 3)
         || case when jsonb_array_length(v_ocupa) > 3 then ' (*agenda plano* mostra tudo)' else '' end || '.' end;
  if jsonb_array_length(v_trav) > 0 or v_parad > 0 or v_esp > 0 then
    v_lin := v_lin || ('Não ocupam ninguém até destravar: '
                       || concat_ws('; ', nullif(public._agenda_nomes(v_trav, 3), ''),
                                    case when v_parad > 0 then public._agenda_plural(v_parad, 'parado no cliente', 'parados no cliente') end,
                                    case when v_esp > 0 then public._agenda_plural(v_esp, 'em espera (você pediu)', 'em espera (você pediu)') end)
                       || '.');
  end if;
  if jsonb_array_length(v_pront) > 0 then
    v_lin := v_lin || (case when jsonb_array_length(v_pront) = 1 then 'Pronto, mas ainda sem lugar no plano (não entra na conta): '
                            else 'Prontos, mas ainda sem lugar no plano (não entram na conta): ' end
                       || public._agenda_nomes(v_pront, 3) || '.');
  end if;
  if jsonb_array_length(v_andam) > 0 then
    v_lin := v_lin || ('Em andamento sem dia no plano (não entra na conta): ' || public._agenda_nomes(v_andam, 3) || '.');
  end if;
  v_lin := v_lin || 'Para um serviço novo, me diga quantos dias e com quem, que eu digo o 1º dia que cabe.'::text;
  v_txt := public._agenda_juntar(v_lin, cf.texto_max);
  v_linha := 'Livre de verdade: '
             || coalesce(nullif(array_to_string(v_curta, '; '), ''), 'não tenho os dias da equipe nas próximas semanas') || '.';

  return jsonb_build_object(
    'fonte', 'simulacao', 'base', 'plano', 'de', v_de, 'ate', v_ate, 'semanas', v_semanas,
    'voce_fora', v_dono > 0 and not v_padrao, 'ocupa', v_ocupa,
    'nao_ocupam', jsonb_build_object(
      'travados', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_trav) with ordinality t(e, o)),
      'prontos', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_pront) with ordinality t(e, o)),
      'andamento', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_andam) with ordinality t(e, o)),
      'parados', v_parad, 'em_espera', v_esp),
    'texto', v_linha, 'texto_completo', v_txt,
    'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$function$;

comment on function public.agenda_livre_de_verdade(date, timestamptz) is
  'Agenda de Produção (Fase 3, P6; REESCRITA na correção de 29/10, P2): "quando a gente fica livre de verdade?" pelo plano e pelo teto de cada pessoa — só com modo_proposta ligado (fora disso {fonte: projecao}: quem chama usa a frase da Fase 1). Para cada uma das 3 semanas a partir do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado), os meios-dias que cada pessoa ainda pega num serviço novo, a mesma conta do encaixe: o menor entre teto80 − compromisso, teto100 − compromisso − reserva e os meios-dias dela livres na grade (_agenda_grade_de_agora: o marcado e o reservado ocupam); o dono só com os dias dele em campo (sem eles, voce_fora e a frase "Você fica de fora da conta"). Depois, o que ocupa a equipe (o plano de hoje ao sábado da última semana, por OS, com quem fica o turno), o que não ocupa ninguém até destravar (a carteira fora do plano: travados, esperando o dono, parados no cliente, em espera; o pronto sem lugar; o em andamento sem dia) e como perguntar de um serviço novo. {fonte: simulacao (o sinal de "use o texto daqui" para a agenda_ver e a agenda_tela_semana), base: plano, de, ate, semanas[{seg, de, ate, rotulo, pessoas[{payee_id, nome, eh_dono, meios, celulas, teto, compromisso, reserva}], texto}], voce_fora, ocupa[{os, numero, reserva, dias, pessoas, texto}], nao_ocupam{travados, prontos, andamento, parados, em_espera}, texto (a linha da semana e da tela: "Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia."), texto_completo (a resposta do *livre*, até texto_max), ms}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role. CORREÇÃO 29/10 (revisão): na linha curta (texto), a 1ª semana pela metade sai com o rótulo do *livre* ("Livre de verdade: de qua 04 a sex 06/11, Roberto 1 dia, João nada; na semana de 09/11, …"; um dia só, "na sex 06/11"), não "na semana de 04/11".';

-- agenda_simular (de 20261030100100_agenda_correcao_livre.sql)
create or replace function public.agenda_simular(p_dias numeric, p_com_quem jsonb default '[]'::jsonb,
                                                 p_dono text default null, p_autor uuid default null,
                                                 p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn     jsonb;
  v_lista  jsonb := case when jsonb_typeof(coalesce(p_com_quem, '[]'::jsonb)) = 'array' then coalesce(p_com_quem, '[]'::jsonb)
                         else jsonb_build_array(p_com_quem) end;
  v_e      jsonb;
  v_ref    text;
  v_turnos text;
  v_rp     jsonb;
  v_gente  jsonb := '[]'::jsonb;
  v_eq     numeric := 0;
  v_com_dono boolean := false;
  v_nomes  text[];
  v_por    text[];
  v_atraso int;
  v_cdia   numeric;
  v_quem   text;
  v_conta  text;
  l1 text; l2 text;
  -- CORREÇÃO 29/10 (P2): o encaixe do motor (com a agenda automática ligada)
  v_enc    jsonb;
  -- CORREÇÃO 29/10 (P2): fim
begin
  if p_hoje is null then
    raise exception 'agenda_simular: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_dias is null or p_dias <= 0 or p_dias > 60 then
    return jsonb_build_object('ok', false, 'texto', 'Para simular, diga quantos dias o serviço leva (por exemplo, 2 dias).');
  end if;
  if p_dono is not null and p_dono not in ('abre_e_fecha', 'sempre', 'nunca') then
    raise exception 'agenda_simular: presença do dono "%" não existe (abre_e_fecha, sempre ou nunca)', p_dono using errcode = '22023';
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_cdia := (v_pn ->> 'cap_dia')::numeric;

  -- Quem vai: nomes ("eu", "Roberto") ou {pessoa, turnos}. Pessoa que não existe = a frase do resolvedor.
  for v_e in select x from jsonb_array_elements(v_lista) x loop
    v_ref := case when jsonb_typeof(v_e) = 'string' then v_e #>> '{}' else v_e ->> 'pessoa' end;
    v_turnos := coalesce(case when jsonb_typeof(v_e) = 'object' then v_e ->> 'turnos' end, 'dia');
    if v_turnos not in ('dia', 'manha', 'tarde') then
      raise exception 'agenda_simular: turno "%" não existe (dia, manha ou tarde)', v_turnos using errcode = '22023';
    end if;
    v_rp := public.agenda_resolver_pessoa(v_ref, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto');
    end if;
    if exists (select 1 from jsonb_array_elements(v_gente) g where g ->> 'payee_id' = v_rp ->> 'payee_id') then
      continue;
    end if;
    v_gente := v_gente || jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                             'eh_dono', (v_rp ->> 'eh_dono')::boolean, 'turnos', v_turnos,
                                             -- a mesma conta de os_prontidao: só um turno = 1 meio-dia por dia ocupado
                                             'diarias', trim_scale(case when v_turnos = 'dia' then p_dias * 2
                                                                        else ceil(p_dias) end / 2));
  end loop;
  v_com_dono := exists (select 1 from jsonb_array_elements(v_gente) g where (g ->> 'eh_dono')::boolean);

  -- As diárias da equipe: os meios-dias ÷ 2 de quem é equipe (o dia todo = dias × 2; só um turno = 1 por dia ocupado;
  -- você só entra quando tem padrão). Sem ninguém dito,
  -- a equipe sugerida.
  if jsonb_array_length(v_gente) = 0 then
    v_eq := p_dias * (v_pn ->> 'equipe_sugerida')::int;
    v_quem := '';
    v_conta := format('(conto %s pessoas, %s, porque você não disse com quem)', v_pn ->> 'equipe_sugerida',
                      public._agenda_plural(ceil(v_eq)::int, 'diária', 'diárias'));
    if v_eq <> trunc(v_eq) then
      v_conta := format('(conto %s pessoas, %s diárias, porque você não disse com quem)', v_pn ->> 'equipe_sugerida',
                        public._agenda_num(v_eq, 2));
    end if;
  else
    select coalesce(sum((g ->> 'diarias')::numeric) filter (where not (g ->> 'eh_dono')::boolean
                                                            or (v_pn ->> 'dono_padrao')::boolean), 0)
      into v_eq from jsonb_array_elements(v_gente) g;
    v_nomes := array(select case when (g ->> 'eh_dono')::boolean then 'você' else g ->> 'nome' end
                              || case g ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                       from jsonb_array_elements(v_gente) with ordinality t(g, o)
                      order by (g ->> 'eh_dono')::boolean desc, o);
    v_quem := ' com ' || public._agenda_lista(v_nomes, null);
    v_por := array(select format('%s %s', case when (g ->> 'eh_dono')::boolean then 'você' else g ->> 'nome' end,
                                 public._agenda_num((g ->> 'diarias')::numeric, 2))
                     from jsonb_array_elements(v_gente) with ordinality t(g, o)
                    where not (g ->> 'eh_dono')::boolean or (v_pn ->> 'dono_padrao')::boolean
                    order by (g ->> 'eh_dono')::boolean desc, o);
    v_conta := '(são ' || case when v_eq = 1 then '1 diária de equipe' else public._agenda_num(v_eq, 2) || ' diárias de equipe' end
               || case when cardinality(v_por) > 1 then ': ' || public._agenda_lista(v_por, null) else '' end
               || case when v_com_dono and not (v_pn ->> 'dono_padrao')::boolean then '; você não entra nessa conta' else '' end
               || ')';
    -- CORREÇÃO 29/10 (revisão): a concordância: "é 1 diária de equipe" e "é meia diária de equipe" (antes "são 1
    -- diária", "são 0,5 diárias").
    if v_eq = 1 then
      v_conta := '(é 1 diária' || substr(v_conta, char_length('(são 1 diária') + 1);
    elsif v_eq = 0.5 then
      v_conta := '(é meia diária' || substr(v_conta, char_length('(são 0,5 diárias') + 1);
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
    if v_eq = 0 then
      v_conta := '(é só você, e você não entra na conta da equipe)';
    end if;
  end if;
  if p_dono is not null and not v_com_dono then
    v_quem := v_quem || case p_dono when 'abre_e_fecha' then ', você abre e fecha' when 'sempre' then ', você junto o tempo todo'
                                    else ', sem você' end;
  end if;

  l1 := format('Um serviço de %s%s %s: ', public._agenda_dias(p_dias), v_quem, v_conta);
  -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, o 1º início que cabe sai do encaixe do motor sobre o plano de agora
  -- (o marcado, o reservado e o teto da semana de cada pessoa: agenda_encaixe_do_novo), não da fila ÷ ritmo da Fase 1 ("no
  -- fim da fila, começa entre …"), que contava a OS travada como se ocupasse a equipe. Nada é gravado.
  if (public._agenda_cfg()).modo_proposta = 'ligado' then
    v_enc := public.agenda_encaixe_do_novo(p_dias, v_gente, p_dono, p_hoje);
    return jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[l1 || (v_enc ->> 'texto')], (v_pn ->> 'texto_max')::int),
      'dados', jsonb_build_object('dias', p_dias, 'com_quem', v_gente, 'diarias_equipe', trim_scale(v_eq), 'encaixe', v_enc));
  end if;
  -- CORREÇÃO 29/10 (P2): fim
  if v_cdia is null or v_cdia <= 0 then
    l1 := l1 || 'não sei o ritmo da equipe (não há diárias lançadas para medir), então não sei dizer quando cabe.';
    l2 := 'É projeção: não reserva nada.';
  else
    l1 := l1 || case
      when (v_pn #>> '{backlog,n}')::int = 0 or v_pn -> 'livre' is null or jsonb_typeof(v_pn -> 'livre') = 'null' then
        'a fila está vazia, começa ' || public._dia_curto((v_pn ->> 'inicio_furando')::date) || '.'
      when v_pn #>> '{livre,ot}' = v_pn #>> '{livre,re}' then
        'no fim da fila, começa por volta de ' || public._dia_curto((v_pn #>> '{livre,ot}')::date) || '.'
      else format('no fim da fila, começa entre %s e %s.', public._dia_curto((v_pn #>> '{livre,ot}')::date),
                  public._dia_curto((v_pn #>> '{livre,re}')::date)) end;
    v_atraso := ceil(v_eq / v_cdia)::int;
    l2 := case when (v_pn #>> '{backlog,n}')::int = 0 then ''
               else format('Passando na frente de tudo, dá para começar %s, e o resto %s. ',
                           public._dia_curto((v_pn ->> 'inicio_furando')::date),
                           case when v_atraso = 0 then 'não atrasa'
                                when v_atraso = 1 then 'atrasa uns 1 dia útil'
                                else format('atrasa uns %s dias úteis', v_atraso) end) end
          || 'É projeção: não reserva nada.';
    l2 := replace(l2, 'uns 1 dia útil', '1 dia útil');
  end if;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1 || ' ' || l2], (v_pn ->> 'texto_max')::int),
    'dados', jsonb_build_object('dias', p_dias, 'com_quem', v_gente, 'diarias_equipe', trim_scale(v_eq),
                                'fila', v_pn -> 'livre', 'inicio_furando', v_pn -> 'inicio_furando', 'atraso_du', v_atraso));
end;
$function$;

comment on function public.agenda_simular(numeric, jsonb, text, uuid, date) is 'Agenda de Produção (Fase 1, P4): serviço hipotético sem orçamento ("um serviço de 2 dias, eu e o Roberto") — as diárias da equipe (meios-dias ÷ 2 de quem é equipe: o dia todo = dias × 2, só de manhã ou só à tarde = 1 por dia ocupado; o dono fora da conta enquanto não tem padrão), no fim da fila (a faixa do livre de verdade) e passando na frente (agenda_somar_du(p_hoje, congelamento_du + 1); o resto atrasa ceil(diárias ÷ capacidade diária) dias úteis). "É projeção: não reserva nada." Pessoa que não existe = {ok:false, texto do resolvedor}. CORREÇÃO 29/10 (P2): com a agenda automática ligada (modo_proposta ligado), o 1º início sai do encaixe do motor sobre o plano de agora (agenda_encaixe_do_novo: o marcado, o reservado e o teto da semana de cada pessoa; a OS travada não ocupa ninguém), no lugar de "no fim da fila…/passando na frente…": "Um serviço de 2 dias com Roberto (são 2 diárias de equipe): pelo plano de agora, cabe em seg 09 e qua 11/11, com Roberto; você abre e fecha. É simulação: não marca nada." dados.encaixe = o resultado do encaixe. Fora de ligado, a projeção de antes, byte a byte. CORREÇÃO 29/10 (revisão): a concordância da conta — "(é 1 diária de equipe)" e "(é meia diária de equipe)", não "são 1 diária" nem "são 0,5 diárias" (em ligado e fora dele).';

-- _agenda_modo_da_pergunta (de 20261030100200_agenda_correcao_motor.sql)
create or replace function public._agenda_modo_da_pergunta(p_tipo text, p_chave text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_tipo in ('nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono') then c.modo_proposta
    when p_tipo = 'chegou' and coalesce(p_chave, '') like 'chegou:fornecedor:%' then c.modo_material
    -- CORREÇÃO 29/10 (revisão): a equipe sem dias é da vigia.
    when p_tipo = 'equipe_sem_dias' then c.modo_vigia
    -- CORREÇÃO 29/10 (revisão): fim
    when p_tipo in ('conferencia', 'chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'entrega')
      then c.modo_vigia
    when p_tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
      then c.modo_material
    when p_tipo in ('diaria', 'diaria_ligar') then c.modo_diaria
    when p_tipo in ('equipe_resposta', 'concluir') then c.modo_equipe
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta') then c.modo_cliente
    when p_tipo = 'aprendizado' then c.modo_aprendizado
  end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_modo_da_pergunta(text, text) is
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia).';

-- _agenda_vigia_limpeza (de 20261030100200_agenda_correcao_motor.sql)
create or replace function public._agenda_vigia_limpeza(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_obs   int := 0;
  v_exp   int := 0;
  v_venc  int := 0;
  v_res   int := 0;
  r       record;
  v_pront jsonb;
  v_cache jsonb := '{}'::jsonb;
  v_item  jsonb;
  v_mot   text;
  v_dono_padrao boolean;
begin
  for r in select p.id, p.versao_base, p.expira_em, p.modo from public.agenda_propostas p
            where p.estado = 'aberta' order by p.criada_em, p.id loop
    if r.modo = 'ligado' and r.versao_base < cf.versao_plano then
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'a agenda mudou' where id = r.id;
      v_obs := v_obs + 1;
    elsif r.expira_em < p_agora then
      update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou da validade' where id = r.id;
      v_exp := v_exp + 1;
    else
      continue;
    end if;
    delete from public.agenda_alocacoes where proposta_id = r.id and estado = 'proposta';
  end loop;

  update public.agenda_perguntas q set estado = 'vencida'
   where q.estado = 'aberta' and q.expira_em is not null and q.expira_em < p_agora;
  get diagnostics v_venc = row_count;
  -- CORREÇÃO 29/10 (P3): a pergunta feita em teste (modo sombra) não fica aberta quando o modo que a faz já está ligado
  -- (_agenda_modo_da_pergunta): ela nunca aparece ao dono e, com a mesma chave aberta também em ligado (o índice único é por
  -- chave e modo), a lista parecia ter a pergunta duas vezes (28/10: o cadastro do Mateus e os prazos dos fornecedores, uma
  -- das 17:45 em teste e outra das 20:15 já ligada). Fecha como resolvida, com o motivo; a de verdade continua.
  with f as (
    update public.agenda_perguntas q
       set estado = 'resolvida', resolvida_motivo = 'era do teste: com a agenda ligada, vale só a pergunta de verdade'
     where q.estado = 'aberta' and q.modo = 'sombra' and public._agenda_modo_da_pergunta(q.tipo, q.chave) = 'ligado'
    returning 1)
  select v_res + count(*)::int into v_res from f;
  -- CORREÇÃO 29/10 (P3): fim

  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  for r in select q.* from public.agenda_perguntas q where q.estado = 'aberta' order by q.criada_em, q.id loop
    v_mot := null;
    if r.tipo = 'conferencia' then
      if not exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia and a.resultado is null) then
        v_mot := case
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia) then 'o dia saiu do plano'
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia
                              and a.resultado is distinct from 'sem_registro') then 'o dia ficou sem registro'
          else 'o dia já está anotado' end;
      end if;
    elsif r.tipo = 'padrao_do_dono' then
      if v_dono_padrao then v_mot := 'você disse os dias em que fica em campo'; end if;
    elsif r.service_order_id is not null then
      v_pront := v_cache -> r.service_order_id::text;
      if v_pront is null then
        v_pront := public.os_prontidao(r.service_order_id, p_hoje);
        v_cache := v_cache || jsonb_build_object(r.service_order_id::text, v_pront);
      end if;
      if v_pront ->> 'estado' in ('concluida', 'fora_da_carteira') then
        v_mot := 'a OS saiu da carteira';
      elsif r.tipo = 'chegou' and split_part(r.chave, ':', 2) = 'fixado' then
        -- a véspera do dia marcado pelo dono (chegou:fixado:<os>:<dia>)
        if r.dia < p_hoje then
          v_mot := 'o dia passou';
        elsif not exists (select 1 from public.agenda_alocacoes a
                           where a.service_order_id = r.service_order_id and a.dia = r.dia and a.estado in ('publicada', 'fixada')
                             and a.tipo <> 'reserva' and a.fixado_por = 'dono') then
          v_mot := 'o dia saiu do plano';
        else
          v_item := public._agenda_classe_da_os(v_pront, public.agenda_meios_da_os(r.service_order_id, p_hoje), p_hoje, false, false);
          if public._agenda_aviso_do_material(v_pront,
               coalesce(v_item ->> 'condicao_tipo',
                        case when v_item ->> 'motivo' = 'material' and v_pront #>> '{material,estado}' = 'sem_previsao' then 'material' end),
               v_item ->> 'texto', r.dia) is null then
            v_mot := 'o material ficou garantido para o dia';
          end if;
        end if;
      -- FASE 4: o chegou? que a pergunta do fornecedor abriu ("Recebeu o compressor?", chegou:fornecedor:<linha>:<dia>):
      -- resolve quando a linha chega ou sai da OS; senão fica até vencer (material_pergunta_validade). Sem este bloco a
      -- regra de baixo leria "fornecedor" como o item e a resolveria no mesmo tique ("a peça saiu da OS").
      elsif r.tipo = 'chegou' and split_part(r.chave, ':', 2) = 'fornecedor' then
        select e into v_item from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
         where e ->> 'id' = split_part(r.chave, ':', 3) limit 1;
        if v_item is null then
          v_mot := 'a peça saiu da OS';
        elsif v_item ->> 'situacao' = 'na_mao' then
          v_mot := format('"%s" chegou', v_item ->> 'curto');
        end if;
      -- FASE 4: fim
      elsif r.tipo = 'chegou' then
        select e into v_item from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
         where coalesce(e ->> 'id', e ->> 'linha') = split_part(r.chave, ':', 2) limit 1;
        if v_item is null then
          v_mot := 'a peça saiu da OS';
        elsif v_item ->> 'situacao' = 'na_mao' then
          v_mot := format('"%s" chegou', v_item ->> 'curto');
        elsif not coalesce((v_item ->> 'atrasado')::boolean, false) or (v_item ->> 'data') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'a previsão mudou';
        end if;
      elsif r.tipo = 'parada' then
        if v_pront ->> 'estado' <> 'parada' then v_mot := 'a OS voltou a andar'; end if;
      elsif r.tipo = 'estouro' then
        if v_pront ->> 'status' <> 'in_progress' then
          v_mot := 'a OS não está mais em andamento';
        elsif (public.agenda_meios_da_os(r.service_order_id, p_hoje) ->> 'total') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'o combinado mudou';
        end if;
      elsif r.tipo = 'duracao' then
        if exists (select 1 from public.os_planejamento pl
                    where pl.service_order_id = r.service_order_id and pl.dias is not null
                      and pl.estimativa_fonte in ('dono', 'aceita')) then
          v_mot := 'você disse os dias';
        end if;
      elsif r.tipo = 'material_conferir' then
        if (v_pront #>> '{material,estado}') is distinct from 'nao_conferido' then v_mot := 'o material foi conferido'; end if;
      end if;
    end if;
    -- CORREÇÃO 29/10 (revisão): (1) a pergunta da reserva ("Lenine tem peça a comprar? Guardei lugar a partir de qui
    -- 05/11; preciso saber até qua 04/11.") não fica aberta quando a reserva saiu (cancelada, solta ou vencida): o texto diz um
    -- lugar que não existe mais, e o fechamento e o aviso a repetiam. Só a de verdade (ligado), com a chave que
    -- _agenda_vigia_duracao_material dá (duracao:<os>, material_conferir:<os>); se a OS ganhar outra reserva, a pergunta nasce de
    -- novo com os dias novos. (2) a pergunta da equipe sem dias resolve quando alguém da equipe volta a ter dias na agenda.
    if v_mot is null and r.modo = 'ligado' and r.tipo in ('duracao', 'material_conferir') and r.service_order_id is not null
       and r.chave = r.tipo || ':' || r.service_order_id
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = r.service_order_id and a.tipo = 'reserva' and a.reserva_de = 'condicionada'
                          and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje) then
      v_mot := 'a reserva saiu: o lugar que eu tinha guardado não existe mais';
    end if;
    if v_mot is null and r.tipo = 'equipe_sem_dias' and public._agenda_equipe_tem_dias(p_hoje) then
      v_mot := 'alguém da equipe voltou a ter dias na agenda';
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200) where id = r.id;
      v_res := v_res + 1;
    end if;
  end loop;
  return jsonb_build_object('obsoletas', v_obs, 'expiradas', v_exp, 'vencidas', v_venc, 'resolvidas', v_res);
end;
$function$;

comment on function public._agenda_vigia_limpeza(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 1: propostas abertas de outra versão do plano (obsoleta, só ligado) ou vencidas (expirada), com as alocações de proposta; perguntas vencidas; perguntas cuja condição sumiu (resolvida, com o fato: chegou, voltou a andar, saiu da carteira, o dia está anotado…). Fase 4 (P4): o chegou? do fornecedor (chegou:fornecedor:<linha>:<dia>) só se resolve quando a linha chega ou sai da OS. CORREÇÃO 29/10 (P3): a pergunta aberta em sombra (feita em teste) cujo modo já está ligado (_agenda_modo_da_pergunta) fecha como resolvida, "era do teste: com a agenda ligada, vale só a pergunta de verdade" (conta em resolvidas); a ligada de mesma chave continua — a lista para de parecer ter a pergunta duas vezes. CORREÇÃO 29/10 (revisão): (1) a pergunta da reserva (duracao:<os>, material_conferir:<os>, ligado) resolve quando a OS não tem mais reserva condicionada publicada de hoje em diante ("a reserva saiu"); (2) equipe_sem_dias resolve quando _agenda_equipe_tem_dias.';

-- agenda_vigiar (de 20261030100400_agenda_correcao_desempenho.sql)
create or replace function public.agenda_vigiar(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos      constant text[] := array['limpeza', 'sem_registro', 'violacoes', 'reservas', 'material', 'dia_nao_cumprido',
                                         'publicacao', 'conferencia', 'chegou', 'parada', 'estouro', 'duracao_material',
                                         'padrao_do_dono', 'backlog', 'poda'];
  c_da_proposta constant text[] := array['sem_registro', 'violacoes', 'reservas', 'material', 'dia_nao_cumprido', 'publicacao'];
  c_da_vigia    constant text[] := array['conferencia', 'chegou', 'parada', 'estouro', 'duracao_material', 'padrao_do_dono',
                                         'backlog'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_acordes jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
  v_cota    int;
  -- CORREÇÃO 29/10 (P5): o tempo de cada passo e a memória da rodada
  v_tp      timestamptz;
  v_ms      jsonb := '{}'::jsonb;
  v_extra   jsonb;
  -- CORREÇÃO 29/10 (P5): fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da vigia.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
                              'acordes', '[]'::jsonb);
  end if;
  -- CORREÇÃO 29/10 (P5): abre a memória da rodada (a prontidão de cada OS calculada uma vez enquanto nada do que ela lê é
  -- gravado), a não ser que agenda_config.vigia_memoria esteja desligada.
  perform public._agenda_rodada_abrir(case when coalesce(cf.vigia_memoria, true) then p_hoje end);
  -- CORREÇÃO 29/10 (P5): fim

  foreach v_passo in array c_passos loop
    continue when v_passo = any (c_da_proposta) and cf.modo_proposta = 'desligado';
    continue when v_passo = any (c_da_vigia) and cf.modo_vigia = 'desligado';
    -- CORREÇÃO 29/10 (P5): o tempo do passo
    v_tp := clock_timestamp();
    -- CORREÇÃO 29/10 (P5): fim
    begin
      execute format('select public.%I($1, $2)', '_agenda_vigia_' || v_passo) into v_r using p_hoje, p_agora;
      v_acordes := v_acordes || coalesce(v_r -> 'acordes', '[]'::jsonb);
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb) - 'acordes');
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('vigia da agenda, passo %s: %s', v_passo, v_msg), 'agenda', 'vigia:' || v_passo,
                                   'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                               'p_agora', p_agora));
    end;
    -- CORREÇÃO 29/10 (P5): o tempo do passo (ms), para medir em produção qual passo pesa
    v_ms := v_ms || jsonb_build_object(v_passo, greatest(0, (extract(epoch from clock_timestamp() - v_tp) * 1000)::int));
    -- CORREÇÃO 29/10 (P5): fim
  end loop;
  -- CORREÇÃO 29/10 (revisão): mais um passo da vigia, depois dos outros: a equipe sem dias
  -- (_agenda_vigia_equipe_sem_dias). Como os outros, com a vigia fora de desligado; o erro vai para app_error_logs e a rodada
  -- segue; o tempo dele entra em contagens.ms.
  if cf.modo_vigia <> 'desligado' then
    v_tp := clock_timestamp();
    begin
      v_r := public._agenda_vigia_equipe_sem_dias(p_hoje, p_agora);
      v_cont := v_cont || jsonb_build_object('equipe_sem_dias', coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', 'equipe_sem_dias', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('vigia da agenda, passo equipe_sem_dias: %s', v_msg), 'agenda',
                                   'vigia:equipe_sem_dias', 'error',
                                   jsonb_build_object('passo', 'equipe_sem_dias', 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
    end;
    v_ms := v_ms || jsonb_build_object('equipe_sem_dias', greatest(0, (extract(epoch from clock_timestamp() - v_tp) * 1000)::int));
  end if;
  -- CORREÇÃO 29/10 (revisão): fim

  -- Os acordes: só com a vigia ligada e a ação executada; no máximo acordes_dia_max por dia; a perda mais cedo primeiro.
  if cf.modo_vigia = 'ligado' and jsonb_array_length(v_acordes) > 0 then
    v_cota := greatest(cf.acordes_dia_max - (select count(*)::int from public.agenda_acoes a
                                              where a.dia = p_hoje and a.contada_via = 'acorde'), 0);
    select coalesce(jsonb_agg(q.e order by q.ord), '[]'::jsonb) into v_acordes
      from (select e, row_number() over (order by (e ->> 'perda_em')::date nulls last, e ->> 'chave') as ord
              from jsonb_array_elements(v_acordes) e
             where exists (select 1 from public.agenda_acoes a where a.id = (e ->> 'acao_id')::uuid and a.executada)) q
     where q.ord <= v_cota;
  else
    v_acordes := '[]'::jsonb;
  end if;
  -- CORREÇÃO 29/10 (P5): fecha a memória (nada dela sobra para o resto da transação) e guarda na linha da rodada o tempo de
  -- cada passo (ms) e quantas contas a memória fez e poupou (memoria); o que a vigia devolve não muda.
  v_extra := jsonb_build_object('ms', v_ms, 'memoria', public._agenda_rodada_fechar());
  v_cont := v_cont || v_extra;
  -- CORREÇÃO 29/10 (P5): fim

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('acordes', jsonb_array_length(v_acordes), 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int));
  -- CORREÇÃO 29/10 (P5): o tempo e a memória ficam só na linha da rodada
  v_cont := v_cont - 'ms' - 'memoria';
  -- CORREÇÃO 29/10 (P5): fim

  return jsonb_build_object('rodou', true, 'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'acordes', v_acordes);
end;
$function$;

comment on function public.agenda_vigiar(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a vigia de 15 min (chamada pelo task-automations). Os dois modos desligados = {rodou: false}. Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action vigia:<passo>, e os outros rodam): 1 limpeza; 2 sem registro; 3 violações → replano e acorde; 4 reservas (promove/solta); 5 material completo (porta/encaixe); 6 dia não cumprido; 7 publicação da semana (dia_do_plano, hora_do_plano, uma vez); 8 conferência; 9 chegou?; 10 parada? (substitui a R2); 11 estouro; 12 duração/material; 13 dono sem padrão; 14 pouco serviço na fila; 15 poda. 2 a 7 seguem modo_proposta; 8 a 14, modo_vigia. Uma linha em agenda_vigia_rodadas por tique. {rodou, modos, contagens, erros, falhas, acordes:[{chave agenda:<acao>, assunto os:<os>, texto, acao_id, os, perda_em}]} — acorde só com a vigia ligada e a ação executada, até acordes_dia_max por dia. Só service_role. CORREÇÃO 29/10 (P5): a rodada abre a memória (a prontidão de cada OS calculada uma vez enquanto nada do que ela lê é gravado; agenda_config.vigia_memoria = false desliga) e a linha de agenda_vigia_rodadas guarda contagens.ms (o tempo de cada passo) e contagens.memoria (quantas prontidões a memória calculou e quantas poupou). O que a vigia devolve não muda. CORREÇÃO 29/10 (revisão): um passo a mais, depois dos outros, com a vigia fora de desligado: equipe_sem_dias (_agenda_vigia_equipe_sem_dias), com o erro em app_error_logs e o tempo em contagens.ms.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- As 3 funções novas são peças de dentro: só as chamam as funções security definer da agenda (agenda_aviso_pecas,
-- agenda_aviso_enfileirar e agenda_vigiar, que roda a limpeza e o passo novo). Ninguém de fora, nem o service_role.
revoke all on function
  public._agenda_aviso_espera_o_fechamento(timestamptz),
  public._agenda_equipe_tem_dias(date),
  public._agenda_vigia_equipe_sem_dias(date, timestamptz)
  from public, anon, authenticated, service_role;
-- As recriadas mantêm as portas que tinham (create or replace não mexe em grant).
