-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P4: as perguntas do gestor — ele pergunta só o que falta
-- (a OS começada ou parada, a estimativa acima do teto, a peça embutida, o orçamento sem mão de obra), diz o que vai fazer e até
-- quando espera, e, sem resposta até o prazo (e só se o dono viu a pergunta antes dele), marca com o que disse.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §3.1 itens 6 a 8, §5.4, §6.3, §6.4, §8.4); nomes: fase7-registro.md §1
-- e §2; respostas do dono: fase7-padroes.md (AG7-03 a equipe; AG7-11 quanto falta; AG7-15 prazo às 18:00, depois de mostrada).
-- Depende da 20261031100000 (7a P1: as colunas veto_ate e opcao_padrao, os tipos de pergunta, o portão e o modo), da 20261031100100
-- (7a P2: a estimativa e a situação da OS) e da 20261031100200 (7a P3: a classe 4 situacao/estimativa); antes delas, das Fases 1
-- a 6 e do lote de correção de 30/10, todos em produção.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (7 funções novas e 2 recriadas; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p4/montar-migration.mjs: as 2 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* dos
-- pacotes anteriores): agenda_decidir de 20261029100900 e _agenda_vigia_limpeza de 20261030100500 (a revisão do lote; a spec
-- dizia 20261030100200, que a revisão recriou). As mudanças estão só nos blocos "-- FASE 7: … -- FASE 7: fim"; fora deles nenhuma
-- linha muda (o Q7 de supabase/tests/agenda_fase7a_perguntas.sql confere).
--
-- POR QUE: o gestor marca sozinho pela estimativa do orçamento (D7-1), mas há OS em que a estimativa sozinha erra: a que já
-- começou ou está parada (AG7-11: "quanto falta?"), a que passa de estimativa_max_diarias, a que tem peça embutida numa linha de
-- serviço e a que não tem mão de obra separada. O P3 deixou essas OS na classe 4 (situacao / estimativa); este pacote faz a
-- pergunta, com o que o gestor faria e o prazo (AG7-15), e aplica o que disse quando o prazo vence sem resposta.
--
-- O QUE MUDA:
--   1. _agenda_veto_ate(p_agora, p_du default null): o prazo — o próximo p_du (senão veto_du) dia útil às veto_hora (18:00), em
--      Brasília. De qui 29/10 16:52 = sex 30/10 18:00; de sex 30/10 = ter 03/11 (Finados). O 7b (a chamada) e o 7c usam a mesma.
--   2. _agenda_gestor_perguntar: o gravador da pergunta do gestor — uma aberta por chave e modo; a fechada não volta na mesma
--      chave; perda_em = o dia do prazo; expira_em = o prazo + desfazer_validade (7 dias sem prazo). Pergunta crítica com prazo é
--      recusada pelo CHECK veto_nao_critica.
--   3. _agenda_gestor_perguntas_da_os: a pergunta de uma OS, só quando o que a segura é o que o gestor pergunta (classe 4
--      situacao/estimativa, ou material com a situação pendente); a Kalmar e o Rodrigo-76, esperando o cliente, não ganham
--      "quanto falta?". situacao (começou sem rastro / com rastro / parada) e estimativa (grande / embutida / sem mão de obra),
--      com os textos da §6.3, o prazo e a opção que vale sem resposta (1). Seco = só devolve (a sombra e o "eu marcaria").
--   4. _agenda_gestor_gravar_dias: o único número que o gestor grava (§3.1 item 8) — os_planejamento.dias com a fonte 'orcamento',
--      o histórico e a ação estimar desfazível. Nunca sobre os dias do dono (dono/aceita).
--   5. _agenda_gestor_vetos: o passo do job a cada tique (o P7 o chama) — a pergunta aberta, ligada, não crítica, com opção padrão,
--      vencida, MOSTRADA ANTES DO PRAZO e sem resposta, com o modo de quem a fez ligado: aplica a opção padrão; a não mostrada
--      fica (conta em sem_mostrar). Trava agenda_plano e agenda_vetos (o 7f a chama também, da rodada comunicar).
--   6. _agenda_gestor_decidir: o despacho das perguntas do gestor (situacao, estimativa; os outros 8 tipos são dos pacotes
--      seguintes, que recriam esta função): 1 grava os dias; 2 "me diga os dias" (fica aberta, o prazo não vale mais); 3 "use
--      *concluiu …*" (começada) ou "não marco" (parada).
--   7. _agenda_gestor_equipe: a chamada semanal da equipe (equipe_cadastro, chave equipe_cadastro:chamada:<segunda>), no dia do
--      plano, quando a semana que vem a seguir será montada só com a semente do histórico ou há alguém com diária cadastrada que
--      nunca esteve na agenda e não vem há 30 dias (Mickael). Sem prazo, sem opções. O 7b a põe em {pulado}.
--   8. agenda_decidir (recriada): situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate
--      e sinal vão a _agenda_gestor_decidir. dia_avisado e dia_prometido seguem a decisão crítica de sempre; equipe_cadastro, a
--      de antes ("não é de decisão").
--   9. _agenda_vigia_limpeza (recriada): a pergunta situacao/estimativa aberta resolve quando o dono disse os dias ("você
--      respondeu") ou quando a pergunta que o gestor faria agora para a OS não é mais esta ("não precisa mais"); a OS que saiu da
--      carteira já era resolvida antes.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_perguntas.sql; registradas em notas-fase77a.md, P4):
--   · A OS presa por MATERIAL (o compressor do Flávio venceu: "chegou?") também é perguntada, quando a situação dela está
--     pendente: o "conto o serviço inteiro" não fica falso por causa do material (é o dono quem responde as duas), e a spec
--     espera a pergunta do Flávio (§2, §6.1, §8.3 A). As outras travas (orçamento, sinal, cliente, escopo, o bem) não.
--   · A fechada não volta na mesma chave, SALVO a que venceu sem o dono ter visto antes do prazo: sem isso, a OS ficaria na classe
--     4 sem pergunta para sempre (a pergunta nunca mostrada some pelo expira_em).
--   · A chave é <tipo>:<os>:<variante> (comecada, rastro, parada; grande, embutida, sem_base): a mesma pergunta não abre duas
--     vezes; o motivo que muda resolve a de antes ("mudou o que falta saber: perguntei de novo") e abre a nova. O número na
--     pergunta é o de quando ela nasceu (o prazo aplica o que o dono viu).
--   · A opção 2 ("eu digo os dias") deixa a pergunta aberta com opcao_escolhida = 2: o prazo não vale mais (o dono respondeu) e
--     a limpeza a resolve quando os dias chegam.
--   · Quem gravou os dias (o prazo ou o dono pela opção 1) sai da pergunta: a ação estimar tem origem vigia (prazo) ou dono, e o
--     histórico de os_planejamento usa as chaves do planejar (dias, estimativa_fonte, estimativa_em em antes/depois; em = o dia
--     em Brasília), para o _agenda_dias_no_inicio da Fase 6 ler.
--   · _agenda_veto_ate tem p_du smallint (a spec): quem passa um número escreve 3::smallint.
--   · A chamada da equipe fala da equipe declarada pelo dono (a correção de 30/10): "conto com Alex (seg a sex), como você disse".
--     O "sem diária em 30 dias" vale para quem tem a diária cadastrada e NUNCA esteve na agenda (Mickael); quem o dono tirou da
--     agenda (Roberto e João, com as linhas encerradas em 30/10) não volta toda semana na pergunta.
--
-- O QUE NÃO MUDA: nenhuma tabela, coluna, lista, dado, cron, tela ou função de borda. Ninguém chama os passos novos antes do P7
-- (a rodada do gestor) e do P8 (o encaixe); com o modo do gestor fora de ligado, as perguntas não são gravadas como de verdade e o
-- prazo não aplica nada. A decisão dos tipos de antes é a mesma (a cópia).
--
-- ORDEM DE LIGAR: depois de 20261031100200 (P3); antes de 20261031100600 (P7), que chama os passos. Aplicar sozinha não muda nada.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7a_perguntas.sql (begin/rollback; Q0 a Q7). Na bancada:
-- node scripts/bancada-agenda/rodar.mjs --ate 20261031100300
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100300_agenda_fase7a_perguntas.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100300', 'agenda_fase7a_perguntas');"
--
-- DESFAZER: recriar agenda_decidir com o corpo de 20261029100900 e _agenda_vigia_limpeza com o de 20261030100500 (a cópia sem os
-- blocos "-- FASE 7:"); as 7 funções novas podem ficar (sem quem as chame). Os dias gravados por prazo vencido (fonte
-- 'orcamento') ficam e, com o portão falso, são lidos como estimativa (só reserva): nada a limpar.
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- O prazo de uma pergunta com prazo (AG7-15; spec §5.4 e R3): o próximo p_du dia útil (nulo = veto_du) depois do dia de p_agora,
-- em Brasília, às veto_hora (18:00: o fechamento sai às 17:30 e o prazo às 17:30 venceria no minuto em que o dono lê). De qui
-- 29/10 16:52 = sex 30/10 18:00; de sex 30/10 = ter 03/11 (seg 02/11 é Finados). O 7b (a chamada, com equipe_chamada_prazo_du) e o
-- 7c (a proposta de etiquetas) usam a mesma; o 7f a lê no texto da linha da pergunta. Só lê agenda_config e o calendário.
create or replace function public._agenda_veto_ate(p_agora timestamptz, p_du smallint default null)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf   public.agenda_config;
  v_du int;
begin
  if p_agora is null then
    raise exception '_agenda_veto_ate: sem a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_du := coalesce(p_du, cf.veto_du);
  if v_du < 0 then
    raise exception '_agenda_veto_ate: % dias úteis não é prazo', v_du using errcode = '22023';
  end if;
  return (public.agenda_somar_du((p_agora at time zone 'America/Sao_Paulo')::date, v_du) + cf.veto_hora)
           at time zone 'America/Sao_Paulo';
end;
$function$;

comment on function public._agenda_veto_ate(timestamptz, smallint) is
  'Agenda de Produção (Fase 7a, P4; AG7-15): o prazo de uma pergunta — agenda_somar_du(o dia de p_agora em Brasília, coalesce(p_du, veto_du)) às veto_hora, em Brasília. A mesma régua para o gestor (7a), a chamada da equipe (7b, p_du = equipe_chamada_prazo_du) e as etiquetas (7c). STABLE, invoker.';

-- O gravador da pergunta do gestor (spec §5.4): uma aberta por chave e modo (a que já está aberta continua: o texto, o prazo e as
-- opções de quando nasceu); a fechada não volta na mesma chave — salvo a que venceu sem o dono ter visto antes do prazo (sem
-- isso, a OS ficaria fora da agenda sem pergunta para sempre). perda_em = o dia do prazo (sem prazo, o do expira_em);
-- expira_em = o prazo + desfazer_validade (sem prazo, 7 dias). Prazo em pergunta crítica: o CHECK veto_nao_critica recusa.
-- Modo fora de sombra/ligado = nada (null). Definer, sem grant: só os passos do gestor a chamam.
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
                         and (q.mostrada_vezes = 0 or (q.veto_ate is not null and q.mostrada_em >= q.veto_ate)))) then
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
  'Agenda de Produção (Fase 7a, P4): grava a pergunta do gestor em agenda_perguntas e devolve o id — uma aberta por chave e modo (devolve a aberta); a fechada não volta na mesma chave (null), salvo a vencida que o dono não viu antes do prazo; perda_em = o dia do prazo (sem prazo, o do expira_em), expira_em = p_veto_ate + desfazer_validade (sem prazo, 7 dias), veto_ate e opcao_padrao como vieram (prazo em pergunta crítica: o CHECK veto_nao_critica recusa). p_modo fora de sombra/ligado = null, nada gravado. Security definer, sem grant a ninguém (nem service_role).';

-- O único número que o gestor grava (spec §3.1 item 8 e §5.4): os dias da pergunta respondida pela opção 1 ou vencida sem resposta,
-- em os_planejamento.dias com a fonte 'orcamento' (com o portão falso, agenda_meios_da_os os lê como 'sugerida': desligar volta ao
-- de antes), o histórico com as chaves do planejar (antes/depois de dias, estimativa_fonte e estimativa_em; em = o dia em Brasília,
-- que o _agenda_dias_no_inicio da Fase 6 lê) e a ação estimar, desfazível por desfazer_validade (o ramo do *desfaz* é do P7).
-- Quem: a pergunta diz — respondida pelo dono (origem dono, o autor dele) ou resolvida pelo prazo (origem vigia, o gestor).
-- Os dias do dono vencem: com estimativa_fonte dono ou aceita, nada é gravado (null). Definer, sem grant.
create or replace function public._agenda_gestor_gravar_dias(p_os uuid, p_dias numeric, p_motivo text, p_pergunta uuid,
                                                             p_agora timestamptz)
 returns uuid
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_hoje   date;
  v_q      public.agenda_perguntas%rowtype;
  v_dono   boolean := false;
  v_autor  uuid;
  v_old    public.os_planejamento%rowtype;
  v_antes  jsonb;
  v_depois jsonb;
  v_acao   uuid;
begin
  if p_os is null or p_dias is null or p_agora is null or nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception '_agenda_gestor_gravar_dias: faltam a OS, os dias, o texto ou a hora' using errcode = '22004';
  end if;
  if p_dias <= 0 or p_dias > 60 or p_dias * 2 <> trunc(p_dias * 2) then
    raise exception '_agenda_gestor_gravar_dias: % não é uma duração (meio dia em meio dia, até 60 dias)', p_dias
      using errcode = '22023';
  end if;
  if not exists (select 1 from public.service_orders so where so.id = p_os) then
    raise exception '_agenda_gestor_gravar_dias: a OS não existe' using errcode = 'P0002';
  end if;
  cf := public._agenda_cfg();
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  if p_pergunta is not null then
    select * into v_q from public.agenda_perguntas q where q.id = p_pergunta;
    v_dono := found and v_q.estado = 'respondida';
    v_autor := case when v_dono then v_q.respondida_por end;
  end if;

  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  select * into v_old from public.os_planejamento where service_order_id = p_os for update;
  if v_old.estimativa_fonte in ('dono', 'aceita') then
    return null;
  end if;
  v_antes := jsonb_build_object('dias', v_old.dias, 'estimativa_fonte', v_old.estimativa_fonte, 'estimativa_em', v_old.estimativa_em);
  v_depois := jsonb_build_object('dias', trim_scale(p_dias), 'estimativa_fonte', 'orcamento', 'estimativa_em', p_agora);

  update public.os_planejamento
     set dias = p_dias, estimativa_fonte = 'orcamento', estimativa_em = p_agora,
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', v_hoje, 'quando', p_agora, 'autor', v_autor, 'por', case when v_dono then 'dono' else 'gestor' end,
           'motivo', left(p_motivo, 200), 'pergunta', p_pergunta, 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = p_agora, atualizado_por = v_autor
   where service_order_id = p_os;

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, antes, depois,
                                   texto, motivo, autor, desfazivel_ate)
  values (p_agora, v_hoje, true, case when v_dono then 'dono' else 'vigia' end, 'estimar', p_os, array[p_os], p_pergunta,
          v_antes, v_depois, left(public._agenda_corta(p_motivo, 400), 400),
          case when v_dono then 'você escolheu na pergunta' else 'sem resposta até o prazo' end,
          v_autor, p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return v_acao;
end;
$function$;

comment on function public._agenda_gestor_gravar_dias(uuid, numeric, text, uuid, timestamptz) is
  'Agenda de Produção (Fase 7a, P4; §3.1 item 8): grava os dias da pergunta do gestor (opção 1 do dono ou o prazo vencido) em os_planejamento — dias, estimativa_fonte orcamento, estimativa_em —, o histórico (em = o dia em Brasília, quando, autor, por dono|gestor, motivo, pergunta, antes/depois com as chaves do planejar) e a ação estimar (origem dono ou vigia, pergunta_id, antes/depois, texto = p_motivo, desfazível por desfazer_validade). Devolve o id da ação. Os dias do dono vencem: com estimativa_fonte dono ou aceita, nada é gravado (null). Security definer, sem grant a ninguém.';

-- A pergunta do gestor para uma OS (spec §5.4 e §6.3). Só quando o que segura a OS é o que o gestor pergunta: classe 4 (pela
-- _agenda_classe_agora) com motivo situacao ou estimativa — ou material, com a situação pendente (o compressor do Flávio: o
-- "chegou?" e o "já começou?" são do dono e correm juntos) —; a OS esperando orçamento, sinal, cliente ou escopo não ganha
-- pergunta (a Kalmar, com check-in em junho, espera o cliente: "sem resposta, marco 1 dia" seria falso). O motivo vem da
-- _agenda_gestor_estimativa (situacao, grande, embutida, sem_base), com a proposta dela; o prazo, de _agenda_veto_ate; a opção
-- que vale sem resposta é a 1 (no sem_base, a recomendação é a 2). Chave <tipo>:<os>:<variante>. p_seco = só devolve {tipo,
-- chave, texto, curto, …} (a sombra e o "eu marcaria"); senão grava pelo modo do gestor que marca (_agenda_gestor_modo('marcar'):
-- desligado = nada) e a pergunta de antes da mesma OS com outro motivo sai ("mudou o que falta saber: perguntei de novo").
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
  v_chave := v_tipo || ':' || p_os || ':' || v_var;
  select v_perg || ' '
         || string_agg(format('%s) %s%s', o ->> 'n', o ->> 'texto', case when (o ->> 'n')::int = v_rec then ' (recomendo)' else '' end),
                       '; ' order by (o ->> 'n')::int) || '.'
    into v_txt
    from jsonb_array_elements(v_ops) o;
  v_base := v_base || jsonb_build_object('tipo', v_tipo, 'chave', v_chave, 'motivo', v_mot, 'variante', v_var, 'texto', v_txt,
                                         'curto', v_est ->> 'texto', 'proposta_dias', trim_scale(v_prop), 'opcoes', v_ops,
                                         'recomendacao', v_rec, 'opcao_padrao', 1, 'veto_ate', v_veto);
  if v_seco then
    return v_base;
  end if;

  -- o motivo mudou: a pergunta de antes da mesma OS (outra chave) sai e a nova entra
  update public.agenda_perguntas q
     set estado = 'resolvida', resolvida_motivo = 'mudou o que falta saber: perguntei de novo'
   where q.estado = 'aberta' and q.modo = v_modo and q.service_order_id = p_os and q.tipo in ('situacao', 'estimativa')
     and q.chave <> v_chave;
  v_nova := not exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo and q.estado = 'aberta');
  v_id := public._agenda_gestor_perguntar(v_tipo, v_chave, p_os, v_txt, v_ops, v_rec, v_veto, 1::smallint, v_modo, p_agora);
  if v_id is null then
    return v_base || jsonb_build_object('por', 'ja_perguntei', 'modo', v_modo);
  end if;
  return v_base || jsonb_build_object('perguntou', true, 'pergunta_id', v_id, 'nova', v_nova, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_gestor_perguntas_da_os(uuid, date, timestamptz, boolean) is
  'Agenda de Produção (Fase 7a, P4; AG7-11, AG7-15): a pergunta do gestor antes de marcar uma OS — só com a classe 4 (_agenda_classe_agora) de motivo situacao, estimativa ou material, e o motivo da _agenda_gestor_estimativa em situacao (começou sem rastro, com rastro, parada), grande, embutida ou sem_base. Os textos da spec §6.3 (o que o gestor faz sem resposta e até quando: _agenda_veto_ate), as opções [{n, texto, efeito: {dias, feito} | {dizer} | {terminou} | {nao_fazer}}], a recomendação (1; no sem_base, 2) e a opção que vale sem resposta (1). Chave <tipo>:<os>:<variante>. p_seco = só devolve {os, perguntou false, tipo, chave, motivo, variante, texto, curto, proposta_dias, opcoes, recomendacao, opcao_padrao, veto_ate}; senão grava pelo modo do gestor que marca (_agenda_gestor_perguntar; desligado = nada) e resolve a aberta da mesma OS de outro motivo. {perguntou, pergunta_id, nova, modo} ou {perguntou false, por: desligado | nada_a_perguntar | ja_perguntei}. Invoker, sem grant (os passos do gestor e a limpeza da vigia a chamam).';

-- O despacho das perguntas do gestor (spec §5.4): agenda_decidir manda para cá os 10 tipos do gestor que não são as críticas do
-- plano; o prazo vencido (_agenda_gestor_vetos) também, com p_via 'prazo'. Os pacotes seguintes (P8 onda, P9 reestimar/reavaliar,
-- P11 ficha_estimativa, P12 sabado) recriam ESTA função; aqui só situacao e estimativa decidem. Opção 1 (efeito dias): a condição
-- ainda vale — a pergunta que o gestor faria agora para a OS é esta (_agenda_gestor_perguntas_da_os seco, a mesma chave) — e os
-- dias vão por _agenda_gestor_gravar_dias (a pergunta respondida pelo dono, ou resolvida pelo prazo "sem resposta até sex 30/10
-- 18:00: ficou como eu disse"); sem a condição, a pergunta resolve ("não precisa mais") e nada muda. Opção 2 (dizer): fica aberta,
-- com a escolha (o prazo não vale mais) — "Me diga os dias". Opção 3: "Use *concluiu Nelson*." (começou) ou "não marco"
-- (parada); nada aqui conclui nem cancela. Só com a pergunta e o modo de quem a fez ligados. Definer, sem grant.
create or replace function public._agenda_gestor_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text,
                                                         p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c_tipos constant text[] := array['situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado',
                                   'bem_livre', 'compre_ate', 'sinal'];
  v_prazo boolean := p_via = 'prazo';
  v_q     public.agenda_perguntas%rowtype;
  v_opc   jsonb;
  v_ef    jsonb;
  v_nome  text;
  v_agora jsonb;
  v_mot   text;
  v_ate   text;
  v_txt   text;
  v_acao  uuid;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela', 'prazo') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_decidir: sem o dia ou a hora' using errcode = '22004';
  end if;
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if not (v_q.tipo = any (c_tipos)) then
    raise exception '_agenda_gestor_decidir: a pergunta "%" não é do gestor da agenda', v_q.tipo using errcode = '22023';
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
    return jsonb_build_object('ok', false, 'gestor', true,
                              'texto', 'O gestor da agenda está em teste: mostro o que eu faria, mas não mudo nada.');
  end if;
  if v_q.tipo not in ('situacao', 'estimativa') then
    return jsonb_build_object('ok', false, 'gestor', true,
      'texto', case when jsonb_array_length(v_q.opcoes) = 0 then 'Essa pergunta não tem opções: me responda com as suas palavras.'
                    else 'Ainda não sei decidir essa pergunta: nada mudou.' end);
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false, 'gestor', true,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  if v_prazo and v_q.opcao_escolhida is not null then
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Você já respondeu essa pergunta: o prazo não vale mais.');
  end if;
  v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
  select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = v_q.service_order_id;

  if v_ef ? 'dias' then
    -- a condição ainda vale: a pergunta que o gestor faria agora para a OS é esta (o mesmo motivo, os dias ainda não ditos)
    v_agora := public._agenda_gestor_perguntas_da_os(v_q.service_order_id, p_hoje, p_agora, true);
    if (v_agora ->> 'chave') is distinct from v_q.chave then
      v_mot := case when exists (select 1 from public.os_planejamento pl
                                  where pl.service_order_id = v_q.service_order_id and pl.dias is not null)
                    then 'você já disse os dias' else 'não precisa mais: mudou o que falta saber' end;
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200) where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'sem_condicao', true,
                                'texto', format('Não mudei nada: %s.', v_mot));
    end if;
    v_ate := public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
             || to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
    if v_prazo then
      v_txt := format('Sem resposta sobre %s até %s: %s. *desfaz %s* volta.', v_nome, v_ate, v_ef ->> 'feito', v_nome);
      update public.agenda_perguntas
         set estado = 'resolvida', opcao_escolhida = p_opcao,
             resolvida_motivo = left(format('sem resposta até %s: ficou como eu disse', replace(v_ate, ' às ', ' ')), 200)
       where id = v_q.id;
    else
      v_txt := format('Combinado, %s: %s. *desfaz %s* volta.', v_nome, v_ef ->> 'feito', v_nome);
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
    end if;
    v_acao := public._agenda_gestor_gravar_dias(v_q.service_order_id, (v_ef ->> 'dias')::numeric, v_txt, v_q.id, p_agora);
    if v_acao is null then
      -- (não acontece: a condição acima já viu os dias do dono; se acontecer, nada fica — nem a pergunta respondida)
      raise exception '_agenda_gestor_decidir: os dias do dono já estão gravados' using errcode = 'P0001';
    end if;
    return jsonb_build_object('ok', true, 'gestor', true, 'texto', v_txt, 'acao_id', v_acao, 'os', v_q.service_order_id,
                              'dias', v_ef -> 'dias', 'via', p_via);
  end if;

  if v_prazo then
    -- (a opção que vale sem resposta é sempre a dos dias; outra não se aplica sozinha)
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não vale sem resposta: nada mudou.');
  end if;
  if v_ef ? 'dizer' then
    update public.agenda_perguntas set opcao_escolhida = p_opcao, resposta = left(p_trecho, 500) where id = v_q.id;
    return jsonb_build_object('ok', true, 'gestor', true, 'aberta', true,
                              'texto', format('Me diga os dias (ex.: ''%s 3 dias'').', v_nome));
  end if;
  if v_ef ? 'terminou' or v_ef ? 'nao_fazer' then
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = v_q.id;
    return jsonb_build_object('ok', true, 'gestor', true,
      'texto', case when v_ef ? 'terminou' then format('Use *concluiu %s*.', v_nome)
                    else format('Combinado: não marco %s. Para tirar o serviço da carteira, cancele a OS.', v_nome) end);
  end if;
  return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
end;
$function$;

comment on function public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4): o despacho das perguntas do gestor (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal), chamado por agenda_decidir (o dono) e por _agenda_gestor_vetos (p_via prazo). Só situacao e estimativa decidem aqui (os outros tipos: "não tem opções" ou "ainda não sei decidir", até os pacotes P8, P9, P11 e P12 recriarem ESTA função). Opção com efeito dias: se a pergunta que o gestor faria agora para a OS ainda é esta, grava os dias (_agenda_gestor_gravar_dias; a pergunta respondida pelo dono, ou resolvida "sem resposta até sex 30/10 18:00: ficou como eu disse"); senão resolve a pergunta e nada muda. dizer: fica aberta com a escolha (o prazo não vale mais), "Me diga os dias (ex.: ''Nelson 3 dias'')."; terminou: "Use *concluiu Nelson*."; nao_fazer: "não marco". Só com a pergunta e o modo de quem a fez ligados. Trava agenda_plano. {ok, gestor true, texto, acao_id?, aberta?, sem_condicao?}. Security definer, sem grant a ninguém.';

-- O prazo vencido (spec §5.4, R3 e AG7-15), passo do job do gestor a cada tique (o P7 o chama; o 7f também, da rodada comunicar:
-- a trava torna as duas chamadas idempotentes): as perguntas do gestor abertas, ligadas, não críticas, com opção padrão e prazo
-- passado, sem resposta (opcao_escolhida nula) e MOSTRADAS AO DONO ANTES DO PRAZO (mostrada_vezes > 0 e mostrada_em < veto_ate),
-- com o modo de quem as fez ligado: a opção padrão é aplicada por _agenda_gestor_decidir (p_via prazo), uma a uma, cada uma no
-- seu bloco (o erro vai a app_error_logs, gestor:vetos, e a próxima segue). A não mostrada antes do prazo fica (sem_mostrar). Trava
-- agenda_plano (a ordem de agenda_decidir) e agenda_vetos. {aplicadas, os, acoes, respondidas, sem_mostrar, em_teste,
-- sem_condicao, erros}; as OS vão ao encaixe do mesmo tique (P8).
create or replace function public._agenda_gestor_vetos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_tipos constant text[] := array['situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado',
                                   'bem_livre', 'compre_ate', 'sinal'];
  r        record;
  v_d      jsonb;
  v_apl    int := 0;
  v_resp   int := 0;
  v_sem    int := 0;
  v_teste  int := 0;
  v_cond   int := 0;
  v_erros  int := 0;
  v_os     jsonb := '[]'::jsonb;
  v_acoes  jsonb := '[]'::jsonb;
  v_estado text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_vetos: sem o dia ou a hora' using errcode = '22004';
  end if;
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  perform pg_advisory_xact_lock(hashtext('agenda_vetos'));
  for r in select q.id, q.tipo, q.chave, q.service_order_id, q.opcao_padrao, q.opcao_escolhida, q.mostrada_vezes, q.mostrada_em,
                  q.veto_ate
             from public.agenda_perguntas q
            where q.estado = 'aberta' and q.modo = 'ligado' and q.veto_ate is not null and q.veto_ate < p_agora
              and q.opcao_padrao is not null and not q.critica and q.tipo = any (c_tipos)
            order by q.veto_ate, q.criada_em, q.id loop
    if r.opcao_escolhida is not null then
      v_resp := v_resp + 1;
      continue;
    end if;
    if not coalesce(r.mostrada_vezes > 0 and r.mostrada_em < r.veto_ate, false) then
      v_sem := v_sem + 1;
      continue;
    end if;
    if coalesce(public._agenda_modo_da_pergunta(r.tipo, r.chave), 'desligado') <> 'ligado' then
      v_teste := v_teste + 1;
      continue;
    end if;
    begin
      v_d := public._agenda_gestor_decidir(r.id, r.opcao_padrao, null, 'prazo', null, p_hoje, p_agora);
      if coalesce((v_d ->> 'ok')::boolean, false) then
        v_apl := v_apl + 1;
        if r.service_order_id is not null then
          v_os := v_os || to_jsonb(r.service_order_id);
        end if;
        if v_d ? 'acao_id' then
          v_acoes := v_acoes || jsonb_build_array(v_d -> 'acao_id');
        end if;
      else
        v_cond := v_cond + 1;
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      perform public.log_app_error('db', format('gestor da agenda, prazo da pergunta %s: %s', r.tipo, v_msg), 'agenda',
                                   'gestor:vetos', 'error',
                                   jsonb_build_object('pergunta', r.id, 'tipo', r.tipo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
    end;
  end loop;
  return jsonb_build_object('aplicadas', v_apl, 'os', v_os, 'acoes', v_acoes, 'respondidas', v_resp, 'sem_mostrar', v_sem,
                            'em_teste', v_teste, 'sem_condicao', v_cond, 'erros', v_erros);
end;
$function$;

comment on function public._agenda_gestor_vetos(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4; AG7-15): o prazo das perguntas do gestor — a aberta, modo ligado, não crítica, de um dos 10 tipos do gestor, com opcao_padrao e veto_ate < p_agora, sem resposta (opcao_escolhida nula), mostrada ao dono antes do prazo (mostrada_vezes > 0 e mostrada_em < veto_ate) e com o modo de quem a fez ligado (_agenda_modo_da_pergunta): aplica a opcao_padrao por _agenda_gestor_decidir(…, p_via prazo), cada uma no seu bloco (erro → app_error_logs gestor:vetos, e segue). A não mostrada fica aberta (sem_mostrar). Trava agenda_plano e agenda_vetos (idempotente entre a rodada do gestor e, no 7f, a comunicar, que recria ESTA função). {aplicadas, os, acoes, respondidas, sem_mostrar, em_teste, sem_condicao, erros}. Invoker, sem grant.';

-- A chamada semanal da equipe (spec §5.4 e §6.3; AG7-03 com a correção de 30/10): no dia do plano, na rodada da revisão do gestor
-- (depois da publicação), para a semana que a próxima publicação monta, a pergunta equipe_cadastro (chave
-- equipe_cadastro:chamada:<segunda dessa semana>, uma por semana, sem prazo e sem opções) quando essa semana seria montada só com a
-- semente do histórico (agenda_capacidade: todo meio-dia esperado de origem historico) ou quando há alguém com a diária cadastrada
-- vigente que nunca esteve na agenda (nenhuma linha de agenda_disponibilidade) e não tem diária há 30 dias (Mickael). O texto diz
-- com quem o gestor conta e por quê (como você disse; pelo que vieram nas últimas medicao_semanas semanas) e quem fica de fora.
-- Pelo modo do gestor que marca (desligado = nada; sombra = gravada em sombra). O 7b recria esta função para {pulado} com o
-- modo_cadastro dele fora de desligado.
create or replace function public._agenda_gestor_equipe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  -- a régua da spec §5.4 ("sem diária em 30 dias"); o 7b traz o parâmetro dele (equipe_inativo_dias)
  c_sem_diaria_dias constant int := 30;
  cf        public.agenda_config;
  v_modo    text;
  v_dono    uuid := public._agenda_dono(null);
  v_seg     date;
  v_chave   text;
  v_hist    text[];
  v_dito    text[];
  v_outro   text[];
  v_semente boolean;
  v_sumidos text[];
  v_partes  text[] := '{}';
  v_txt     text;
  v_id      uuid;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_equipe: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('marcar');
  if v_modo = 'desligado' then
    return jsonb_build_object('criada', false, 'motivo', 'o gestor está desligado');
  end if;
  cf := public._agenda_cfg();
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano then
    return jsonb_build_object('criada', false, 'motivo', 'a chamada da equipe é no dia do plano');
  end if;
  -- a semana que a próxima publicação monta: depois da hora do plano, a seguinte à que acabou de sair
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1)
           + case when (p_agora at time zone 'America/Sao_Paulo')::time >= cf.hora_do_plano then 14 else 7 end;
  v_chave := 'equipe_cadastro:chamada:' || v_seg;
  if exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo) then
    return jsonb_build_object('criada', false, 'motivo', 'já perguntei desta semana', 'semana', v_seg);
  end if;

  -- quem conta na semana (a grade), por pessoa: os dias e de onde eles vêm
  with g as (
    select c.payee_id, c.pessoa, array_agg(distinct extract(isodow from c.dia)::smallint) as dias,
           array_agg(distinct coalesce(c.origem, '-')) as origens
      from public.agenda_capacidade(v_seg, v_seg + 5, p_hoje) c
     where not c.eh_dono and c.meios_esperados > 0
     group by c.payee_id, c.pessoa
  ), t as (
    select g.*, g.pessoa || ' (' || regexp_replace(public._agenda_dias_semana_texto(g.dias), '^de ', '') || ')' as item,
           case when 'dono' = any (g.origens) then 'dito' when g.origens = array['historico'] then 'hist' else 'outro' end as grupo
      from g
  )
  select array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'hist'),
         array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'dito'),
         array_agg(t.item order by cardinality(t.dias) desc, t.pessoa, t.payee_id) filter (where t.grupo = 'outro')
    into v_hist, v_dito, v_outro
    from t;
  v_semente := coalesce(cardinality(v_hist), 0) > 0 and coalesce(cardinality(v_dito), 0) = 0
               and coalesce(cardinality(v_outro), 0) = 0;

  -- quem tem a diária cadastrada vigente, nunca esteve na agenda e não vem há c_sem_diaria_dias dias
  select array_agg(format('%s tem cadastro de diarista mas %s: não conto com ele.', x.nome,
                          case when x.ultima is null then 'nunca veio' else 'não vem desde ' || to_char(x.ultima, 'DD/MM') end)
                   order by x.nome, x.id)
    into v_sumidos
    from (select py.id, public._agenda_nome_curto(py.name) as nome,
                 (select max(ws.data) from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
                   where w.payee_id = py.id and ws.fracao > 0) as ultima
            from public.payees py
           where py.active and py.kind in ('prestador', 'diarista', 'funcionario') and py.id is distinct from v_dono
             and exists (select 1 from public.work_profiles w
                          where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                            and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
             and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = py.id)) x
   where x.ultima is null or x.ultima <= p_hoje - c_sem_diaria_dias;

  if not v_semente and coalesce(cardinality(v_sumidos), 0) = 0 then
    return jsonb_build_object('criada', false, 'motivo', 'a equipe está dita', 'semana', v_seg);
  end if;

  if coalesce(cardinality(v_dito), 0) > 0 then
    v_partes := v_partes || (public._agenda_lista(v_dito, null) || ', como você disse');
  end if;
  if coalesce(cardinality(v_outro), 0) > 0 then
    v_partes := v_partes || public._agenda_lista(v_outro, null);
  end if;
  if coalesce(cardinality(v_hist), 0) > 0 then
    v_partes := v_partes || (public._agenda_lista(v_hist, null)
                             || case when cardinality(v_hist) = 1 then ', pelo que veio' else ', pelo que vieram' end
                             || format(' nas últimas %s semanas', cf.medicao_semanas));
  end if;
  v_txt := format('Para marcar a semana de %s ', to_char(v_seg, 'DD/MM'))
           || case when cardinality(v_partes) = 0 then 'não conto com ninguém da equipe.'
                   else 'eu conto com ' || array_to_string(v_partes, ', e com ') || '.' end
           || coalesce(' ' || array_to_string(v_sumidos, ' '), '')
           || ' Se a equipe mudou, me diga quem vem e em que dias.';
  v_id := public._agenda_gestor_perguntar('equipe_cadastro', v_chave, null, v_txt, '[]'::jsonb, null, null, null, v_modo, p_agora);
  return jsonb_build_object('criada', v_id is not null, 'pergunta_id', v_id, 'semana', v_seg, 'semente', v_semente,
                            'sumidos', coalesce(cardinality(v_sumidos), 0), 'modo', v_modo, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_gestor_equipe(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4; AG7-03): a chamada semanal da equipe — no dia_do_plano, a pergunta equipe_cadastro (chave equipe_cadastro:chamada:<segunda da semana que a próxima publicação monta>, sem prazo nem opções, pelo modo do gestor que marca; desligado = nada) quando essa semana seria montada só com a semente do histórico (agenda_capacidade: todo meio-dia esperado de origem historico) ou há alguém com a diária cadastrada vigente que nunca esteve na agenda e não tem diária há 30 dias. O texto: "Para marcar a semana de 09/11 eu conto com Roberto (seg a sex) e João (ter a sex), pelo que vieram nas últimas 8 semanas. Mickael tem cadastro de diarista mas não vem desde 18/09: não conto com ele. Se a equipe mudou, me diga quem vem e em que dias." (com a equipe declarada pelo dono: "Alex (seg a sex), como você disse"). {criada, pergunta_id, semana, semente, sumidos, modo, texto}. Invoker, sem grant. O 7b recria ESTA função ({pulado} com o modo_cadastro dele).';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7:") ──────────────────────────
-- Fora dos blocos nenhuma linha muda (o Q7 de supabase/tests/agenda_fase7a_perguntas.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration (fase7-registro.md §2: agenda_decidir no 7b P3; _agenda_vigia_limpeza, quem vier).

-- agenda_decidir (de 20261029100900_agenda_fase6_correcao_calculo.sql)
create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  -- CORREÇÃO FASE 6: (C1) regressão B2: a pergunta do aprendizado toma a trava da rodada do aprendizado ANTES de travar a
  -- pergunta (é aqui, e não em _agenda_aprendizado_decidir, que a linha da pergunta é travada primeiro); as outras não
  if exists (select 1 from public.agenda_perguntas q where q.id = p_pergunta and q.tipo = 'aprendizado') then
    perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  end if;
  -- CORREÇÃO FASE 6: fim
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  -- FASE 3: a diária (a pergunta crítica que diverge e a de ligar a OS) tem o efeito dela e o modo dela (modo_diaria):
  -- _agenda_decidir_diaria (20261026100300).
  if v_q.tipo in ('diaria', 'diaria_ligar') then
    return public._agenda_decidir_diaria(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 5: a mensagem ao cliente (cliente_aprovar, a aprovação dos primeiros dias, e cliente_aviso, a crítica do aviso de
  -- atraso) tem o efeito dela e o modo dela (modo_cliente): _agenda_cliente_decidir (20261028100300).
  if v_q.tipo in ('cliente_aprovar', 'cliente_aviso') then
    return public._agenda_cliente_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_agora);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) a pergunta do aprendizado (a troca grande de um valor medido, a carga de cada pessoa pelo plano cumprido e
  -- o planejador mais forte) tem o efeito dela e o modo dela (modo_aprendizado e aprendizado_ligados):
  -- _agenda_aprendizado_decidir (20261029100600). A opção 1 da carga é a única escrita de parâmetro (carga_max), com *desfaz*.
  if v_q.tipo = 'aprendizado' then
    return public._agenda_aprendizado_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7: (7a P4) as perguntas do gestor da agenda (situacao e estimativa decidem aqui; os outros 8 tipos, nos pacotes que os
  -- criam, que recriam _agenda_gestor_decidir) têm o efeito delas e o modo delas (o do gestor): _agenda_gestor_decidir
  -- (20261031100300). dia_avisado e dia_prometido não: são críticas do plano e seguem a decisão de sempre, abaixo; a
  -- equipe_cadastro desta etapa não tem opções ("não é de decisão").
  if v_q.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado', 'bem_livre',
                  'compre_ate', 'sinal') then
    return public._agenda_gestor_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 7: fim
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista). CORREÇÃO FASE 6 (C1, regressão B2): a pergunta do aprendizado toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do for update da pergunta. FASE 7 (7a P4): as perguntas do gestor da agenda (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal) vão a _agenda_gestor_decidir (o efeito e o modo delas: o do gestor); dia_avisado e dia_prometido seguem a decisão crítica de sempre; equipe_cadastro, a de antes.';

-- _agenda_vigia_limpeza (de 20261030100500_agenda_correcao_revisao.sql)
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
      -- FASE 7: (7a P4) a pergunta do gestor antes de marcar (situacao, estimativa): resolve quando o dono disse os dias (pelo
      -- *grava*, pela tela ou pela opção 1) ou quando a pergunta que o gestor faria agora para a OS não é mais esta — o motivo
      -- mudou ou sumiu (a OS ganhou plano, passou a esperar o cliente, o orçamento mudou). Com o gestor fora de ligado (sombra,
      -- *gestor, só propor*) ou com a pergunta em teste, o motivo não é reavaliado: só os dias ditos a resolvem.
      elsif r.tipo in ('situacao', 'estimativa') then
        if exists (select 1 from public.os_planejamento pl where pl.service_order_id = r.service_order_id and pl.dias is not null) then
          v_mot := 'você respondeu';
        elsif r.modo = 'ligado' and public._agenda_gestor_modo('marcar') = 'ligado'
              and (public._agenda_gestor_perguntas_da_os(r.service_order_id, p_hoje, p_agora, true) ->> 'chave') is distinct from r.chave then
          v_mot := 'não precisa mais';
        end if;
      -- FASE 7: fim
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

comment on function public._agenda_vigia_limpeza(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 1: propostas abertas de outra versão do plano (obsoleta, só ligado) ou vencidas (expirada), com as alocações de proposta; perguntas vencidas; perguntas cuja condição sumiu (resolvida, com o fato: chegou, voltou a andar, saiu da carteira, o dia está anotado…). Fase 4 (P4): o chegou? do fornecedor (chegou:fornecedor:<linha>:<dia>) só se resolve quando a linha chega ou sai da OS. CORREÇÃO 29/10 (P3): a pergunta aberta em sombra (feita em teste) cujo modo já está ligado (_agenda_modo_da_pergunta) fecha como resolvida, "era do teste: com a agenda ligada, vale só a pergunta de verdade" (conta em resolvidas); a ligada de mesma chave continua — a lista para de parecer ter a pergunta duas vezes. CORREÇÃO 29/10 (revisão): (1) a pergunta da reserva (duracao:<os>, material_conferir:<os>, ligado) resolve quando a OS não tem mais reserva condicionada publicada de hoje em diante ("a reserva saiu"); (2) equipe_sem_dias resolve quando _agenda_equipe_tem_dias. FASE 7 (7a P4): a pergunta do gestor situacao/estimativa aberta resolve quando a OS ganhou os dias ("você respondeu") ou, com o gestor ligado e a pergunta de verdade, quando a pergunta que ele faria agora para a OS não é mais esta (_agenda_gestor_perguntas_da_os seco: "não precisa mais"); a OS que saiu da carteira já resolvia.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- O prazo é leitura (a tela e o foco do gestor podem mostrá-lo): execute para authenticated e service_role, nunca anon. O gravador
-- da pergunta, o dos dias e o despacho escrevem (definer): sem grant a ninguém, nem service_role (agenda_decidir, a rodada do
-- gestor e a vigia, definer, os chamam). Os passos (a pergunta da OS, o prazo vencido e a chamada da equipe) são invoker e sem
-- grant, como os passos da vigia.
revoke all on function public._agenda_veto_ate(timestamptz, smallint) from public, anon;
grant execute on function public._agenda_veto_ate(timestamptz, smallint) to authenticated, service_role;
revoke all on function public._agenda_gestor_perguntar(text, text, uuid, text, jsonb, smallint, timestamptz, smallint, text, timestamptz),
  public._agenda_gestor_gravar_dias(uuid, numeric, text, uuid, timestamptz),
  public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public._agenda_gestor_perguntas_da_os(uuid, date, timestamptz, boolean),
  public._agenda_gestor_vetos(date, timestamptz),
  public._agenda_gestor_equipe(date, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) to service_role;
revoke all on function public._agenda_vigia_limpeza(date, timestamptz) from public, anon, authenticated, service_role;
