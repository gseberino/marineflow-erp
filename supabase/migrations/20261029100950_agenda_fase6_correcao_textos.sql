-- Agenda de Produção, Fase 6 ("Aprendizado"), correção C2: o *desfaz*, os textos, as leituras e o roteiro
-- (0 funções novas; 14 recriadas; 4 parâmetros novos em agenda_config, com 4 CHECKs).
-- Fonte: scratchpad agenda-pesquisa/decisoes-correcao-fase6.md (seção C2), revisao-fase6-correcao.md (itens 6, 10 e 12 e os
-- textos 1, 2, 5, 6 e 8) e revisao-fase6-regressao.md (M1, B1, B6, B7 e B8). Depende de 20261029100000 .. 20261029100900 (a
-- Fase 6 inteira e a C1). A de dado 20261029101000 continua a última.
--
-- ═══ DDL — OK NOMEADO ═══ (4 colunas novas em agenda_config, com DEFAULT e CHECK; nenhuma tabela, nenhum índice)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/c2f6/montar-migration.mjs (as partes escritas à mão
-- parte-0-cabeca, parte-1-novas e parte-9-portas, os blocos de c2f6/blocos + as 14 recriadas, cada uma copiada da definição
-- MAIS NOVA, conferida com grep a cada montagem). Fora dos blocos "-- CORREÇÃO FASE 6: (C2) … -- CORREÇÃO FASE 6: fim"
-- nenhuma linha das recriadas muda (os blocos da C1 ficam onde estavam). Existe para revisão e espera o OK do dono.
--
-- O QUE MUDA (cada item é um bloco marcado "(C2) item N", "(C2) texto N", "(C2) regressão BN/M1" ou "(C2) sobra":
--   · item 6 (DONO decide; a recomendação aplicada) — o *desfaz aprendizado* por item. agenda_desfazer_dito: *desfaz
--     aprendizado <coisa>* (fator, presença, valor ou diária, folga, capacidade ou carga, fornecedor, ou o nome de um
--     fornecedor) desfaz só as ações daquela coisa do instante mais novo (o mesmo lote), tudo ou nada, e cada uma trava só a
--     sua chave; *desfaz aprendizado* sozinho continua desfazendo o lote. A coisa que não é item nem fornecedor devolve
--     nao_achei; sem mudança, nenhuma (as duas seguem ao modelo pelo TS, como o *desfaz <nome>* de sempre). O "o que mudou"
--     (_agenda_mudancas, que alimenta o fechamento das 17:30, o foco mudanças e a tela) sai com UMA linha por item do mesmo
--     instante (o texto 2: o fator e a presença de várias classes juntos, a classe mais fina e "Também nas OS de … e nas …",
--     com o valor de cada classe quando não é o mesmo), as linhas sem o "*desfaz aprendizado* volta" de cada ação, e UMA vez,
--     na 1ª linha desfazível do aprendizado, "*desfaz aprendizado* volta tudo; *desfaz aprendizado <coisa>* volta só essa"
--     (com uma linha só, "*desfaz aprendizado* volta."). DESVIO da decisão ("uma vez no FIM do bloco"): a frase vai no fim da
--     1ª linha — o fechamento corta pelas últimas linhas (480 letras) e o foco pelo texto_max; no fim, a frase sumiria em toda
--     rodada com 3 trocas ou mais. A tela: o botão Desfazer da linha do aprendizado desfaz o item inteiro daquele instante
--     (agenda_desfazer_pela_tela), como a linha. Para voltar ao lote só: tirar o bloco "(C2) item 6" de agenda_desfazer_dito
--     (as linhas por item podem ficar).
--   · regressão M1 — _agenda_mudanca_texto: o grupo sem nome (a ação sem OS) não ganha o "*desfaz %s* volta como estava."
--     (saía "*desfaz * volta como estava." no fechamento e no foco mudanças).
--   · regressão B1 — agenda_acao_desfazivel: "a última" e o *desfaz* sem nome não pegam as ações do aprendizado (elas voltam
--     só pelo *desfaz aprendizado*); sem mais nada, "Não tenho outra mudança minha para desfazer agora. O que eu aprendi
--     sozinho volta com *desfaz aprendizado*."; a mudança sem OS entra na lista "Qual?" pelo próprio texto (nunca "Qual?
--     Diga…" vazio).
--   · item 10 — o corte do foco aprendizado (_agenda_ver_aprendizado): quando o foco inteiro não cabe em texto_max, sai
--     primeiro o que está em teste e medindo, depois o em uso e o travado (do último bloco para o 1º), cada bloco com "• e
--     mais N"; a pergunta aberta nunca sai por esse corte (se nem só as perguntas couberem, elas vêm primeiro e o corpo
--     encurta pelo fim). Cabendo tudo, o texto é o de antes.
--   · item 12 — os números fora do config: aprender_saude_dias (7, a troca grande que entrou sozinha na saúde),
--     aprender_atraso_h (26, a rodada atrasada), aprender_parar_dias (30, as métricas das trocas na saúde) e
--     aprender_respostas_dias (30, as respostas por áudio do foco) entram em agenda_config com o DEFAULT de antes; o "2
--     desfeitos em 4 semanas" lê aprender_trava_dias (28). Com os DEFAULTs, a saída é a mesma.
--   · texto 1 — a linha do fator (_agenda_aprendizado_texto, foco_em_uso, que vai ao cartão e ao foco): "…: uso 1,7× desde
--     qui 29/10 para perguntar o que falta (os dias do plano continuam os que você disse)."; com o valor em uso igual ao
--     padrão, "…: é o mesmo que eu já usava."; em teste, com o medido igual ao padrão, "Em teste: as OS levam até 1,5× o
--     combinado (11 OS): é o mesmo que eu já uso." (sem o "hoje seria 1,5×, e vale 1,5×").
--   · texto 2 — no item 6 (uma linha por item).
--   · texto 5 — a pergunta do R$ por diária: "…cada diária rendeu R$ 1.097 (12 OS com diária ligada; inclui as OS em que você
--     também trabalhou)…" e a opção 1 sem "(recomendo)" (_agenda_aprendizado_gravar; a recomendação da pergunta continua 1,
--     pelo CHECK critica_tem_opcoes).
--   · texto 6 — agenda_cliente_preparar: a forma fim com o fim novo que não passa do dia que o cliente ouviu diz "Não
--     preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar." (era o texto técnico do
--     22023).
--   · texto 8 — conferido, sem mudança: com a C1 (item 4) a ação da folga que desce sozinha não aparece na volta (o C8c).
--   · regressão B8 — os_plano_da_os, _agenda_ver_compras e _agenda_ver_fornecedores: sem o "sub" no JWT, só o service_role
--     (ou nenhum JWT: o banco por dentro), como agenda_fator_de_campo; o authenticated sem "sub" recebe 42501.
--   · sobra (a) da C1 — _agenda_atraso_do_fornecedor (a linha do atraso no foco compras) lê pela chave da medida
--     (_agenda_fornecedor_da_medida: o inativo pelo principal), como a medição.
--   · sobra (b) da C1 — o motivo sem_fim no fecho do foco aprendizado: "N sem a conclusão registrada" (era "N por outro
--     motivo").
--
-- AS RECRIADAS (de onde cada uma vem; quem recriar de novo copia DESTA migration):
--   agenda_desfazer_dito (de 20261029100600), agenda_acao_desfazivel (de 20261026100200), _agenda_mudancas (de
--   20261028100500), _agenda_mudanca_texto (de 20261025100500), _agenda_aprendizado_texto (de 20261029100600),
--   _agenda_aprendizado_gravar (de 20261029100100), agenda_cliente_preparar (de 20261029100700), _agenda_ver_aprendizado (de
--   20261029100800), agenda_saude (de 20261029100600), os_plano_da_os (de 20261029100900), _agenda_ver_compras (de
--   20261029100300), _agenda_ver_fornecedores (de 20261029100800), _agenda_atraso_do_fornecedor (de 20261029100300),
--   agenda_desfazer_pela_tela (de 20261026100600).
--   Três trocam um trecho de antes sem apagá-lo (para a cópia fora dos blocos ser a fonte): _agenda_mudanca_texto e
--   _agenda_atraso_do_fornecedor (sql) ganham um 2º select, que é o que vale (a função sql devolve o do último); em
--   _agenda_ver_aprendizado o bloco antes do return devolve (o return de antes não roda mais); em agenda_saude o bloco
--   depois do aprendizado refaz as contas com as janelas do config. Não tirar: é a conferência da cópia.
--
-- O QUE NÃO MUDA: com o aprendizado desligado ou em teste nada do que o motor, a vigia, a prontidão e a rodada do cliente
-- leem muda; nenhuma mensagem nova a terceiros (o montador recusa escrita em fila de mensagem e em agenda_config nos
-- blocos); nenhum texto novo ao cliente. Textos novos ao dono: os do item 6 (o *desfaz aprendizado <coisa>*, o "não
-- tenho", o "não achei", a frase uma vez), o B1 ("Não tenho outra mudança minha…"), os textos 1, 2, 5 e 6 e o rótulo do
-- sem_fim (pendencias-do-dono.md, "textos que mudaram, só para saber").
--
-- ORDEM DE LIGAR: depois de 20261029100900 (a C1); antes de 20261029101000 (a de dado). Aplicar sozinha não muda nada para
-- ninguém enquanto o aprendizado está desligado, fora o B1 (o *desfaz* sem nome que não pega o aprendizado), o B8 (o JWT sem
-- "sub") e o texto 6 (a recusa do *cliente_avisar* firme com a forma fim).
--
-- PROVA (depois de aplicar): os blocos "C2" de supabase/tests/agenda_fase6_rodada.sql, _leituras.sql, _os.sql,
-- _fornecedor.sql, _cliente.sql, _acabamento.sql e _pos_deploy.sql (a fixture-fase6 só na bancada). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100950_agenda_fase6_correcao_textos.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100950', 'agenda_fase6_correcao_textos');"
--
-- DESFAZER:
--   1. as funções: reaplicar, em ordem, as definições de 20261025100500 (_agenda_mudanca_texto), 20261026100200
--      (agenda_acao_desfazivel), 20261026100600 (agenda_desfazer_pela_tela), 20261028100500 (_agenda_mudancas),
--      20261029100100 (_agenda_aprendizado_gravar), 20261029100300 (_agenda_ver_compras, _agenda_atraso_do_fornecedor),
--      20261029100600 (agenda_desfazer_dito, _agenda_aprendizado_texto, agenda_saude), 20261029100700
--      (agenda_cliente_preparar), 20261029100800 (_agenda_ver_aprendizado, _agenda_ver_fornecedores) e 20261029100900
--      (os_plano_da_os). Os textos gravados em agenda_aprendizado.texto e agenda_acoes.texto ficam como estão até a rodada
--      seguinte (são só texto).
--   2. os parâmetros (só depois do passo 1: as funções de antes não os leem):
--      alter table public.agenda_config drop constraint if exists agenda_config_aprender_saude_dias_check,
--        drop constraint if exists agenda_config_aprender_atraso_h_check,
--        drop constraint if exists agenda_config_aprender_parar_dias_check,
--        drop constraint if exists agenda_config_aprender_respostas_dias_check,
--        drop column if exists aprender_saude_dias, drop column if exists aprender_atraso_h,
--        drop column if exists aprender_parar_dias, drop column if exists aprender_respostas_dias;
--   Se a C1 (20261029100900) também for desfeita, desfazer esta primeiro.
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$, create or replace function, revoke/grant.

-- ── 1. Os parâmetros novos (DDL) ────────────────────────────────────────────────────────────────────────
-- (item 12) As janelas do aprendizado que estavam escritas no corpo das funções passam a morar em agenda_config, com o
-- mesmo valor de antes no DEFAULT (o único lugar do número): a saúde (a troca grande que entrou sozinha, a rodada
-- atrasada, as métricas das trocas) e o foco aprendizado (as respostas de cliente por áudio). O "2 desfeitos em 4 semanas"
-- (§11, parar) lê aprender_trava_dias (28), que já existia.
alter table public.agenda_config
  add column if not exists aprender_saude_dias     smallint not null default 7,
  add column if not exists aprender_atraso_h       smallint not null default 26,
  add column if not exists aprender_parar_dias     smallint not null default 30,
  add column if not exists aprender_respostas_dias smallint not null default 30;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_aprender_saude_dias_check',     'check (aprender_saude_dias between 1 and 30)'),
      ('agenda_config_aprender_atraso_h_check',       'check (aprender_atraso_h between 25 and 72)'),
      ('agenda_config_aprender_parar_dias_check',     'check (aprender_parar_dias between 7 and 90)'),
      ('agenda_config_aprender_respostas_dias_check', 'check (aprender_respostas_dias between 7 and 90)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.agenda_config.aprender_saude_dias is
  'Agenda de Produção (Fase 6, correção C2, item 12): a saúde do aprendizado procura "troca grande que entrou sozinha" (o zero troca_grande_sem_pergunta) nas ações destes últimos dias. Era 7 escrito na função.';
comment on column public.agenda_config.aprender_atraso_h is
  'Agenda de Produção (Fase 6, correção C2, item 12): depois da 1ª rodada do aprendizado, a saúde acusa rodada_atrasada quando a última tem mais que estas horas (a rodada é uma por dia, a partir de aprender_hora). Era 26 escrito na função.';
comment on column public.agenda_config.aprender_parar_dias is
  'Agenda de Produção (Fase 6, correção C2, item 12): a janela das métricas do aprendizado na saúde (trocas_30d: as que entraram sozinhas, as perguntas, as decididas e as desfeitas — o que diz se é para parar um item, §11). Era 30 escrito na função; a chave guarda o nome.';
comment on column public.agenda_config.aprender_respostas_dias is
  'Agenda de Produção (Fase 6, correção C2, item 12): o foco aprendizado conta as respostas de cliente que foram ao dono por áudio (ou sem a agenda entender) nestes últimos dias ("… por áudio: N em 30 dias"). Era 30 escrito na função.';

-- ── 3. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO FASE 6: (C2)") ─────
-- Fora dos blocos nenhuma linha muda (os testes de cópia conferem tirando os blocos "-- CORREÇÃO FASE 6:"; os da C1 ficam
-- onde estavam). Quem recriar de novo qualquer uma delas copia DESTA migration.
-- agenda_desfazer_dito (de 20261029100600_agenda_fase6_rodada.sql)
create or replace function public.agenda_desfazer_dito(p_autor uuid, p_alvo text default null, p_canal text default 'whatsapp',
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_ref   jsonb;
  v_id    uuid;
  v_r     jsonb;
  v_txts  text[] := '{}';
  v_falha text;
  -- FASE 6: (P6) o alvo "aprendizado"
  v_aprend boolean := false;
  -- FASE 6: fim
begin
  -- CORREÇÃO FASE 6: (C2) item 6: *desfaz aprendizado <coisa>* desfaz só o que é daquela coisa — fator, presença, valor (ou
  -- diária), folga, capacidade (ou carga), fornecedor (o atraso e o prazo de todos) ou o nome de um fornecedor (os dois
  -- dele) —: das ações aprendizado ainda desfazíveis que são dela, as do instante mais novo (o mesmo lote), tudo ou nada.
  -- Cada uma trava só a sua chave (_agenda_desfazer_aprendizado); as outras do lote continuam em uso. *desfaz aprendizado*
  -- sozinho continua desfazendo o lote inteiro (abaixo). A coisa que não é item nem fornecedor = nao_achei.
  if public._agenda_normal(p_alvo) ~ '^(o )?aprendizado [a-z0-9]' then
    declare
      v_coisa text := regexp_replace(public._agenda_normal(p_alvo), '^(o )?aprendizado ', '');
      v_itens text[];
      v_ids   uuid[];
      v_de    text;
    begin
      v_itens := case v_coisa
                   when 'fator' then array['fator']
                   when 'presenca' then array['presenca']
                   when 'valor' then array['mo']
                   when 'diaria' then array['mo']
                   when 'folga' then array['aviso_folga']
                   when 'capacidade' then array['capacidade_dono', 'carga']
                   when 'carga' then array['capacidade_dono', 'carga']
                   when 'fornecedor' then array['fornecedor_atraso', 'fornecedor_prazo'] end;
      v_de := case v_coisa
                when 'fator' then 'do fator'
                when 'presenca' then 'da sua presença'
                when 'valor' then 'do valor por diária'
                when 'diaria' then 'do valor por diária'
                when 'folga' then 'da folga do aviso de atraso'
                when 'capacidade' then 'da carga da semana'
                when 'carga' then 'da carga da semana'
                when 'fornecedor' then 'dos fornecedores' end;
      if v_itens is null then
        -- o nome do fornecedor: o curto ("Kamell"), o de exibição, o fantasia ou a razão social, como o dono escreve
        select 'de ' || public._agenda_fornecedor_curto(s.id) into v_de
          from public.suppliers s
         where v_coisa in (public._agenda_normal(public._agenda_fornecedor_curto(s.id)), public._agenda_normal(s.display_name),
                           public._agenda_normal(s.trade_name), public._agenda_normal(s.name))
         order by s.active desc nulls last, s.id
         limit 1;
        if v_de is null then
          return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nao_achei',
            'texto', 'Não achei isso no que eu aprendi. Diga *desfaz aprendizado* e fator, presença, valor, folga, capacidade ou o nome do fornecedor (ou só *desfaz aprendizado*, que volta tudo).');
        end if;
      end if;
      with m as (
        select a.id, a.criada_em, a.antes
          from public.agenda_acoes a
          left join public.suppliers s on a.antes ->> 'item' in ('fornecedor_atraso', 'fornecedor_prazo')
                                      and s.id::text = a.antes ->> 'chave'
         where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
           and case when v_itens is not null then a.antes ->> 'item' = any (v_itens)
                    else s.id is not null
                         and v_coisa in (public._agenda_normal(public._agenda_fornecedor_curto(s.id)),
                                         public._agenda_normal(s.display_name), public._agenda_normal(s.trade_name),
                                         public._agenda_normal(s.name)) end)
      select array_agg(m.id order by m.antes ->> 'item', m.antes ->> 'chave', m.id) into v_ids
        from m
       where m.criada_em = (select max(x.criada_em) from m x);
      if coalesce(cardinality(v_ids), 0) = 0 then
        return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nenhuma',
          'texto', format('Não tenho mudança do aprendizado %s para desfazer agora.', v_de));
      end if;
      begin
        foreach v_id in array v_ids loop
          v_r := public.agenda_desfazer(v_id, v_autor, 'dono', p_hoje, p_agora);
          if not coalesce((v_r ->> 'ok')::boolean, false) then
            v_falha := v_r ->> 'texto';
            raise exception using errcode = 'P0098', message = 'desfazer recusado';
          end if;
          v_txts := v_txts || (v_r ->> 'texto');
        end loop;
      exception when sqlstate 'P0098' then
        return jsonb_build_object('ok', false, 'mudou', false, 'texto', v_falha);
      end;
      return jsonb_build_object('ok', true, 'mudou', true, 'acoes', to_jsonb(v_ids), 'texto', array_to_string(v_txts, ' '));
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) *desfaz aprendizado* (spec-fase6 §5.6): o último lote de ações aprendizado desfazíveis — as do mesmo
  -- instante (o que a mesma rodada ou a mesma decisão mudou: o fator muda as 4 chaves de uma vez) —, tudo ou nada. Sem
  -- nenhuma, "não tenho". Os outros alvos seguem por agenda_acao_desfazivel, como antes
  if public._agenda_normal(p_alvo) in ('aprendizado', 'o aprendizado') then
    v_aprend := true;
    select jsonb_build_object('status', 'ok',
                              'acao_id', (array_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))[1],
                              'acao_ids', jsonb_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))
      into v_ref
      from public.agenda_acoes a
     where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
       and a.criada_em = (select max(b.criada_em) from public.agenda_acoes b
                           where b.tipo = 'aprendizado' and b.executada and b.desfeita_em is null and b.desfazivel_ate >= p_agora)
    having count(*) > 0;
    v_ref := coalesce(v_ref, jsonb_build_object('status', 'nenhuma',
                                                'texto', 'Não tenho mudança do aprendizado para desfazer agora.'));
  else
  -- FASE 6: fim
  v_ref := public.agenda_acao_desfazivel(p_alvo, p_hoje, p_agora);
  -- FASE 6: (P6) o fim do "se é o aprendizado"
  end if;
  -- FASE 6: fim
  if v_ref ->> 'status' is distinct from 'ok' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', v_ref ->> 'status', 'texto', v_ref ->> 'texto',
                              'opcoes', v_ref -> 'opcoes');
  end if;
  -- "desfaz semana" são várias ações: tudo ou nada
  begin
    for v_id in select x::uuid from jsonb_array_elements_text(coalesce(v_ref -> 'acao_ids', jsonb_build_array(v_ref ->> 'acao_id'))) x loop
      v_r := public.agenda_desfazer(v_id, v_autor, 'dono', p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        v_falha := v_r ->> 'texto';
        raise exception using errcode = 'P0098', message = 'desfazer recusado';
      end if;
      v_txts := v_txts || (v_r ->> 'texto');
    end loop;
  exception when sqlstate 'P0098' then
    return jsonb_build_object('ok', false, 'mudou', false, 'texto', v_falha);
  end;
  -- FASE 6: (P6) o lote do aprendizado: os "Desfeito: …" um depois do outro (não é a publicação da semana)
  if v_aprend then
    return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids', 'texto', array_to_string(v_txts, ' '));
  end if;
  -- FASE 6: fim
  return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids',
    'texto', case when cardinality(v_txts) = 1 then v_txts[1]
                  else format('Desfiz a publicação da semana (%s): %s', public._agenda_plural(cardinality(v_txts), 'mudança', 'mudanças'),
                              array_to_string(v_txts, ' ')) end);
end;
$function$;

comment on function public.agenda_desfazer_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a palavra *desfaz* (+ o nome, o número ou "semana") — agenda_acao_desfazivel (ambíguo ou nada: a frase pronta, nada muda) + agenda_desfazer(via dono) de cada ação; "semana" é tudo ou nada. Executa direto: é a ordem exata do dono. Admin pelo _autor_da_agenda. Fase 6 (P6): o alvo "aprendizado" = o último lote de ações aprendizado desfazíveis (as do mesmo instante), tudo ou nada; o texto é o "Desfeito: …" de cada uma. CORREÇÃO FASE 6 (C2, item 6): *desfaz aprendizado <coisa>* (fator, presença, valor/diária, folga, capacidade/carga, fornecedor ou o nome de um fornecedor) desfaz só as ações daquela coisa do instante mais novo, tudo ou nada; cada uma trava só a sua chave; *desfaz aprendizado* sozinho continua o lote. A coisa desconhecida = nao_achei; sem mudança = nenhuma.';

-- agenda_acao_desfazivel (de 20261026100200_agenda_fase3_caminhos.sql)
create or replace function public.agenda_acao_desfazivel(p_ref text, p_hoje date default public._hoje_brt(),
                                                         p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref  text := btrim(coalesce(p_ref, ''));
  v_norm text := public._agenda_normal(p_ref);
  v_ids  uuid[];
  v_ro   jsonb;
  v_dia  date;
  v_prop uuid;
begin
  if v_norm in ('semana', 'a semana', 'da semana', 'semana toda', 'a semana toda') then
    select a.proposta_id into v_prop from public.agenda_acoes a
     where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo = 'publicar'
     order by a.criada_em desc, a.id desc limit 1;
    if v_prop is null then
      return jsonb_build_object('status', 'nenhuma', 'texto', 'Não tenho publicação da semana para desfazer agora.');
    end if;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.proposta_id = v_prop and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
                    order by a.criada_em, a.id);
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', 'Desfaço a publicação da semana.');
  end if;
  if v_ref <> '' and v_norm not in ('a ultima', 'ultima', 'o ultimo', 'ultimo', 'isso', 'tudo') then
    v_ro := public.agenda_resolver_os(v_ref, p_hoje);
    -- FASE 3: a OS concluída ou entregue sai da carteira, mas a conclusão e a entrega da agenda ficam desfazíveis:
    -- "desfaz OS-00074" logo depois de "concluiu Lenine" acha a OS pelo id que o resolvedor devolve fora da carteira. Sem
    -- mudança desfazível dela, a resposta é a de antes (o "desfaz" pode ser de outra ferramenta).
    if v_ro ->> 'status' <> 'ok'
       and not (v_ro ->> 'status' = 'fora_da_carteira' and v_ro ->> 'id' is not null
                and exists (select 1 from public.agenda_acoes a
                             where a.service_order_id = (v_ro ->> 'id')::uuid and a.executada and a.desfeita_em is null
                               and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer')) then
      return jsonb_build_object('status', coalesce(v_ro ->> 'status', 'nao_achei'), 'texto', v_ro ->> 'texto', 'opcoes', v_ro -> 'opcoes');
    end if;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.service_order_id = (v_ro ->> 'id')::uuid and a.executada and a.desfeita_em is null
                      and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                    order by a.criada_em desc, a.id desc limit 1);
    if cardinality(v_ids) = 0 then
      return jsonb_build_object('status', 'nenhuma',
               'texto', format('Não tenho mudança minha no %s para desfazer agora.', v_ro ->> 'cliente_curto'));
    end if;
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', (select a.texto from public.agenda_acoes a where a.id = v_ids[1]));
  end if;
  -- sem nome: a última, se pediu; senão as contadas no último fechamento/acorde; senão todas as desfazíveis
  if v_norm in ('a ultima', 'ultima', 'o ultimo', 'ultimo') then
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                    order by a.criada_em desc, a.id desc limit 1);
  else
    select max((a.contada_em at time zone 'America/Sao_Paulo')::date) into v_dia
      from public.agenda_acoes a
     where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer' and a.contada_em is not null;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                      and (v_dia is null or (a.contada_em at time zone 'America/Sao_Paulo')::date = v_dia)
                    order by a.criada_em, a.id);
  end if;
  -- CORREÇÃO FASE 6: (C2) regressão B1: "a última" e o *desfaz* sem nome não pegam o que a agenda aprendeu sozinha (tipo
  -- aprendizado): ele volta só pelo *desfaz aprendizado* (o lote) ou pelo *desfaz aprendizado <coisa>*. Antes, "a última"
  -- desfazia uma chave solta do lote (a de id maior) e a lista "Qual?" a punha sem nome. As duas listas de cima, de novo,
  -- sem ele (a mesma régua); sem mais nada, o "não tenho" diz a palavra do aprendizado.
  if exists (select 1 from public.agenda_acoes a where a.id = any (v_ids) and a.tipo = 'aprendizado') then
    if v_norm in ('a ultima', 'ultima', 'o ultimo', 'ultimo') then
      v_ids := array(select a.id from public.agenda_acoes a
                      where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
                        and a.tipo not in ('desfazer', 'aprendizado')
                      order by a.criada_em desc, a.id desc limit 1);
    else
      select max((a.contada_em at time zone 'America/Sao_Paulo')::date) into v_dia
        from public.agenda_acoes a
       where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo not in ('desfazer', 'aprendizado')
         and a.contada_em is not null;
      v_ids := array(select a.id from public.agenda_acoes a
                      where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
                        and a.tipo not in ('desfazer', 'aprendizado')
                        and (v_dia is null or (a.contada_em at time zone 'America/Sao_Paulo')::date = v_dia)
                      order by a.criada_em, a.id);
    end if;
    if cardinality(v_ids) = 0 then
      return jsonb_build_object('status', 'nenhuma',
               'texto', 'Não tenho outra mudança minha para desfazer agora. O que eu aprendi sozinho volta com *desfaz aprendizado*.');
    end if;
  end if;
  -- CORREÇÃO FASE 6: fim
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('status', 'nenhuma', 'texto', 'Não tenho mudança minha para desfazer agora.');
  end if;
  if cardinality(v_ids) = 1 then
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', (select a.texto from public.agenda_acoes a where a.id = v_ids[1]));
  end if;
  -- CORREÇÃO FASE 6: (C2) regressão B1: a mudança sem OS (sem nome de cliente) entra na lista "Qual?" pelo próprio texto;
  -- antes saía sem nada, e a lista só dela virava "Qual?  Diga…". Com todas de OS, a lista é a de baixo, byte a byte.
  if exists (select 1 from public.agenda_acoes a where a.id = any (v_ids) and a.service_order_id is null) then
    return jsonb_build_object('status', 'ambiguo', 'acao_ids', to_jsonb(v_ids),
      'texto', format('Qual? %s Diga *desfaz* e o nome.',
                      (select string_agg(coalesce(coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) || ' (' || rtrim(
                                regexp_replace(a.texto, '^[^:]*: ', ''), '.') || ')', rtrim(a.texto, '.')),
                                ' ou ' order by a.criada_em, a.id)
                         from public.agenda_acoes a
                         left join public.service_orders so on so.id = a.service_order_id
                         left join public.clients cl on cl.id = so.client_id
                        where a.id = any (v_ids)) || '?'));
  end if;
  -- CORREÇÃO FASE 6: fim
  return jsonb_build_object('status', 'ambiguo', 'acao_ids', to_jsonb(v_ids),
    'texto', format('Qual? %s Diga *desfaz* e o nome.',
                    (select string_agg(coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) || ' (' || rtrim(
                              regexp_replace(a.texto, '^[^:]*: ', ''), '.') || ')', ' ou ' order by a.criada_em, a.id)
                       from public.agenda_acoes a
                       left join public.service_orders so on so.id = a.service_order_id
                       left join public.clients cl on cl.id = so.client_id
                      where a.id = any (v_ids)) || '?'));
end;
$function$;

comment on function public.agenda_acao_desfazivel(text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): resolve o que o dono quer desfazer — o nome ou o número da OS (agenda_resolver_os: a última ação desfazível dela), "semana" (a última publicação: todas as ações dela em acao_ids), "a última", ou nada (a única desfazível contada no último fechamento ou acorde; senão a única desfazível). Fase 3: a OS fora da carteira (concluída, entregue) com mudança desfazível da agenda também vale. Mais de uma = {status ambiguo, texto "Qual? Nelson (…) ou Vanderlei (…)? Diga *desfaz* e o nome."}; nenhuma = "Não tenho mudança minha para desfazer agora.". {status ok|ambiguo|nenhuma|nao_achei, acao_id, acao_ids, texto}. CORREÇÃO FASE 6 (C2, regressão B1): "a última" e o *desfaz* sem nome não pegam as ações do aprendizado (tipo aprendizado: só pelo *desfaz aprendizado*); sem mais nada, o "não tenho" diz a palavra do aprendizado; a mudança sem OS entra na lista "Qual?" pelo próprio texto.';

-- _agenda_mudancas (de 20261028100500_agenda_fase5_leituras.sql)
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
                        and h.id = (select f.id from ap f where f.r = 1 and f.desfazivel order by f.em, f.min_id limit 1)
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
      from todos t
     group by t.grupo
  )
  select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'tipo', g.tipo, 'proposta_id', g.proposta_id,
                                               'acao_ids', g.acao_ids, 'itens', g.itens, 'os', g.os, 'nome', g.nome,
                                               'numero', g.numero, 'desfazivel', g.desfazivel, 'desfeita', g.desfeita,
                                               'em', g.em)
                            -- FASE 3: entre os grupos, a mesma ordem (criada_em, OS, id)
                            order by g.em, g.desempate_os nulls last, g.desempate), '[]'::jsonb)
    from g;
$function$;

comment on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a ordem de gravação criada_em, OS, id): o que a agenda mudou sozinha (motor e vigia; fora do fechamento também o replano da conferência) com agenda_acoes.dia em [p_de, p_ate], em grupos — a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela. Fase 4, P3: também a ação material da nota importada e da mensagem do fornecedor (origens nota e fornecedor). p_executada false = o que a sombra teria feito; p_fechamento = só o não contado e não desfeito, só motor e vigia. [{grupo, tipo, proposta_id, acao_ids, itens, os, nome, numero, desfazivel, desfeita, em}]. Fase 5, P5: também o que a resposta do cliente mudou (origem cliente: fixar e cliente — o dia confirmado, o pedido de outro dia, o acesso, o opt-out), com as ações do replano dele (depois.replano_acoes) no mesmo grupo (contadas juntas, a frase só a do cliente); o acorde da mensagem ao cliente (tipo cliente, origem vigia, depois.acorde) não é mudança e não entra. CORREÇÃO FASE 6 (C2, item 6 e texto 2): o aprendizado sai UMA linha por item do mesmo instante (o fator e a presença de várias classes juntos: a classe mais fina e "Também nas OS de …"; as outras ações no grupo, junto), sem o "*desfaz aprendizado* volta" de cada ação; na 1ª linha desfazível, uma vez, "*desfaz aprendizado* volta tudo; *desfaz aprendizado <coisa>* volta só essa".';

-- _agenda_mudanca_texto (de 20261025100500_agenda_fase2_leituras.sql)
create or replace function public._agenda_mudanca_texto(p_g jsonb, p_sombra boolean default false)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_g ->> 'tipo' = 'publicacao' then
      case when p_sombra then 'Publicaria ' else 'Publiquei ' end
      || coalesce(regexp_replace(p.textos ->> 'titulo', '^Semana', 'a semana'), 'a semana')
      || ': ' || (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
      || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
              when coalesce((p_g ->> 'desfazivel')::boolean, false) then ' *desfaz semana* volta como estava.' else '' end
    else (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
         || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
                 when coalesce((p_g ->> 'desfazivel')::boolean, false)
                   then format(' *desfaz %s* volta como estava.', p_g ->> 'nome') else '' end end
    from (select 1) um
    left join public.agenda_propostas p on p.id = nullif(p_g ->> 'proposta_id', '')::uuid;
  -- CORREÇÃO FASE 6: (C2) regressão M1: o select de cima não vale mais (a função sql devolve o resultado do último); vale
  -- este, que é ele com uma mudança só: o grupo sem nome (a ação sem OS, como o que a agenda aprendeu sozinha) não ganha o
  -- "*desfaz %s* volta como estava." — com o nome nulo a frase saía "*desfaz * volta como estava." no fechamento das 17:30 e
  -- no foco mudanças. O texto dele já diz como voltar. Com nome, byte a byte o de cima.
  select case
    when p_g ->> 'tipo' = 'publicacao' then
      case when p_sombra then 'Publicaria ' else 'Publiquei ' end
      || coalesce(regexp_replace(p.textos ->> 'titulo', '^Semana', 'a semana'), 'a semana')
      || ': ' || (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
      || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
              when coalesce((p_g ->> 'desfazivel')::boolean, false) then ' *desfaz semana* volta como estava.' else '' end
    else (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
         || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
                 when coalesce((p_g ->> 'desfazivel')::boolean, false) and nullif(btrim(p_g ->> 'nome'), '') is not null
                   then format(' *desfaz %s* volta como estava.', p_g ->> 'nome') else '' end end
    from (select 1) um
    left join public.agenda_propostas p on p.id = nullif(p_g ->> 'proposta_id', '')::uuid;
  -- CORREÇÃO FASE 6: fim
$function$;

comment on function public._agenda_mudanca_texto(jsonb, boolean) is
  'Agenda de Produção (Fase 2, P5): a frase de um grupo de _agenda_mudancas — a publicação ("Publiquei a semana de 03 a 06/11 (seg 02 é Finados): … *desfaz semana* volta como estava."; na sombra "Publicaria …") ou a ação ("<frase> *desfaz Nelson* volta como estava."), com "(já desfeito)" quando foi desfeita. CORREÇÃO FASE 6 (C2, regressão M1): o grupo sem nome (a ação sem OS, como o aprendizado) não ganha o "*desfaz <nome>* volta como estava." (com o nome nulo saía "*desfaz * volta como estava.").';

-- _agenda_aprendizado_texto (de 20261029100600_agenda_fase6_rodada.sql)
create or replace function public._agenda_aprendizado_texto(p_item text, p_momento text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nivel  text := public._agenda_classe_texto_do_nivel(p_d ->> 'chave');
  v_calc   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'calculado')::numeric);
  v_uso    text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'em_uso')::numeric);
  v_efet   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'efetivo')::numeric);
  v_padrao text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'padrao')::numeric);
  v_volta  text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'volta')::numeric);
  v_n      text := p_d ->> 'n';
  v_nmin   text := p_d ->> 'n_min';
  v_desde  text := public._dia_curto(nullif(p_d ->> 'desde', '')::date);
  v_trava  text := public._dia_curto(nullif(p_d ->> 'travado_ate', '')::date);
  v_dias   text := p_d ->> 'trava_dias';
  v_rotulo text;
begin
  -- CORREÇÃO FASE 6: (C2) texto 5: a pergunta do R$ por diária (a troca grande do valor) diz que a conta inclui as OS em
  -- que o dono também trabalhou (a mão de obra delas entra; as diárias dele não); a opção 1 sai sem o "(recomendo)" (o
  -- gravador não o põe no valor: _agenda_aprendizado_gravar). O resto do valor, como antes (abaixo).
  if p_item = 'mo' and p_momento = 'pergunta' then
    return format('Medi a mão de obra por diária: cada diária rendeu %s (%s OS com diária ligada; inclui as OS em que você também trabalhou), e hoje eu uso %s para estimar os dias pelo valor. É uma troca grande.',
                  v_calc, v_n, v_efet);
  end if;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P2) o R$ por diária (spec-fase6 §6.2 e §6.3): a mão de obra das OS com diária ligada ÷ as diárias ligadas; o
  -- padrão é mo_por_diaria_real, e o valor entra no realista de os_duracao_sugerida ("estimar os dias pelo valor")
  if p_item = 'mo' then
    return case p_momento
      when 'foco_medindo' then format('Valor por diária: %s de %s OS com diária ligada medidas; para estimar os dias pelo valor uso %s (padrão).',
                                      v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor uso %s (padrão).',
                                     v_calc, v_n, v_padrao)
      when 'foco_em_uso' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada): é o que uso para estimar os dias pelo valor desde %s.',
                                     v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada), e hoje uso %s para estimar os dias pelo valor: a troca espera a sua resposta.',
                                       v_calc, v_n, v_efet)
      when 'foco_travado' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor fico com %s até %s, como você decidiu.',
                                      v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Cada diária rendeu %s de mão de obra (%s OS): passei a estimar os dias pelo valor com %s (era %s). *desfaz aprendizado* volta.',
                              v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi a mão de obra por diária: cada diária rendeu %s (%s OS com diária ligada), e hoje eu uso %s para estimar os dias pelo valor. É uma troca grande.',
                                  v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: para estimar os dias pelo valor volto a %s por diária. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  coalesce(v_volta, v_padrao, 'o padrão'), v_dias)
      when 'fico' then format('Combinado: fico com %s por diária. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- (P2) a presença do dono (spec-fase6 §6.2 e §6.3): k = as OS da classe a que ele foi sem estar no plano (detalhe.k) e n
  -- = as OS medidas; 1 = o dia todo, 0 = o abre e fecha (o padrão). Na classe entra sozinha; em todas, sempre pergunta.
  if p_item = 'presenca' and v_nivel is not null then
    declare
      v_foi  text := format('Você foi a %s de %s %s sem estar no plano', coalesce(p_d #>> '{detalhe,k}', '0'), v_n,
                            substr(v_nivel, 4));
      v_onde text := case when p_d ->> 'chave' = 'todas' then 'por padrão' else 'nelas' end;
      v_dia  boolean := coalesce((p_d ->> 'calculado')::numeric, 0) >= 1;
      v_udia boolean := coalesce((p_d ->> 'em_uso')::numeric, 0) >= 1;
      v_edia boolean := coalesce((p_d ->> 'efetivo')::numeric, 0) >= 1;
      v_vdia boolean := coalesce((p_d ->> 'volta')::numeric, 0) >= 1;
    begin
      return case p_momento
        when 'foco_medindo' then format('%s: %s de %s OS medidas para saber se você fica o dia todo; conto com você para abrir e fechar (padrão).',
                                        public._agenda_maiuscula(v_nivel), v_n, v_nmin)
        when 'foco_sombra' then v_foi || case when v_dia then format(': em teste, eu contaria com você o dia todo %s.', v_onde)
                                              else format(': em teste, continuo contando com você só para abrir e fechar %s.', v_onde) end
        when 'foco_em_uso' then v_foi || case when v_udia then format(': conto com você o dia todo %s desde %s.', v_onde, v_desde)
                                              else format(': conto com você só para abrir e fechar %s.', v_onde) end
        when 'foco_pergunta' then v_foi || case when v_dia then ': perguntei se passo a contar com você o dia todo por padrão; espero a sua resposta.'
                                                else ': perguntei se volto a contar com você só para abrir e fechar; espero a sua resposta.' end
        when 'foco_travado' then v_foi || format('; fico com %s até %s, como você decidiu.',
                                                 case when v_edia then 'o dia todo' else 'o abre e fecha' end, v_trava)
        when 'acao' then v_foi || case when v_dia then ': passei a contar com você o dia todo nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao abre e fecha.'
                                       else ': voltei a contar com você só para abrir e fechar nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao dia todo.' end
        when 'pergunta' then v_foi || case when v_dia then '. Quer que eu conte com você o dia todo por padrão, e não só para abrir e fechar?'
                                           else '. Quer que eu volte a contar com você só para abrir e fechar por padrão?' end
        when 'opcao1' then case when v_dia then 'Sim, o dia todo (recomendo pelo medido)' else 'Sim, só abrir e fechar (recomendo pelo medido)' end
        when 'opcao2' then case when v_dia then 'Não, continuo com o abre e fecha' else 'Não, continuo com o dia todo' end
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: n%s volto a contar com você %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nivel, case when v_vdia then 'o dia todo' else 'só para abrir e fechar' end, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.',
                                case when v_edia then 'o dia todo' else 'o abre e fecha' end)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P3) o fornecedor (spec-fase6 §6.2 e §6.3): o atraso das entregas (padrão 0: a chegada no dia que o fornecedor
  -- diz) e o prazo da nota (da saída até a chegada; padrão = o prazo de hoje). O nome é o curto do cadastro (detalhe.nome),
  -- sem artigo; detalhe.no_prazo = as entregas no prazo; detalhe.dono = o prazo é o que o dono disse (só mede).
  if p_item in ('fornecedor_atraso', 'fornecedor_prazo') then
    declare
      v_nome  text := coalesce(p_d #>> '{detalhe,nome}', 'O fornecedor');
      v_np    text := coalesce(p_d #>> '{detalhe,no_prazo}', '0');
      v_dono  boolean := coalesce((p_d #>> '{detalhe,dono}')::boolean, false);
      v_cnum  numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      v_unum  numeric := coalesce((p_d ->> 'em_uso')::numeric, 0);
      v_vnum  numeric := coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0);
      -- "a chegada 2 dias úteis depois do que o fornecedor diz" / "a chegada no dia que o fornecedor diz"
      v_ccheg text := case when v_cnum > 0 then format('a chegada %s depois do que o fornecedor diz', v_calc)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_ucheg text := case when v_unum > 0 then format('a chegada %s depois do que o fornecedor diz', v_uso)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_echeg text := case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0
                           then format('a chegada %s depois do que o fornecedor diz', v_efet)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_vcheg text := case when v_vnum > 0
                           then format('a chegada %s depois do que o fornecedor diz',
                                       public._agenda_aprendizado_valor('fornecedor_atraso', v_vnum))
                           else 'a chegada no dia que o fornecedor diz' end;
    begin
      if p_item = 'fornecedor_atraso' then
        return case p_momento
          when 'foco_medindo' then format('%s: %s de %s entregas medidas.', v_nome, v_n, v_nmin)
          when 'foco_sombra' then format('%s: %s de %s entregas no prazo%s (em teste).', v_nome, v_np, v_n,
                                         case when v_cnum > 0 then '; o atraso chega a ' || v_calc else '' end)
          when 'foco_em_uso' then format('%s: %s de %s entregas no prazo%s: conto %s (desde %s).', v_nome, v_np, v_n,
                                         case when v_unum > 0 then '; o atraso chega a ' || v_uso else '' end, v_ucheg, v_desde)
          when 'foco_pergunta' then format('%s: o atraso chega a %s (%s entregas), e hoje conto %s: a troca espera a sua resposta.',
                                           v_nome, v_calc, v_n, v_echeg)
          when 'foco_travado' then format('%s: o atraso chega a %s (%s entregas); fico com %s até %s, como você decidiu.',
                                          v_nome, v_calc, v_n, v_echeg, v_trava)
          when 'acao' then case when v_cnum > 0
                                then format('%s atrasou até %s em %s entregas: passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_calc, v_n, v_ccheg)
                                else format('%s voltou a entregar no prazo (%s de %s entregas): passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_np, v_n, v_ccheg) end
          when 'pergunta' then case when v_cnum > 0
                                    then format('Medi as entregas de %s: o atraso chega a %s (%s entregas), e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_calc, v_n, v_echeg)
                                    else format('Medi as entregas de %s: %s de %s no prazo, e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_np, v_n, v_echeg) end
          when 'opcao1' then format('Passo a contar %s', v_ccheg)
          when 'opcao2' then format('Fico com %s', v_echeg)
          when 'opcao3' then 'Volto ao padrão'
          when 'desfeito' then format('Desfeito: para %s volto a contar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                      v_nome, v_vcheg, v_dias)
          when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.', v_nome, v_echeg)
        end;
      end if;
      -- o prazo da nota: da saída (despacho) até a chegada
      return case p_momento
        when 'foco_medindo' then case when v_dono
               then format('%s: você disse %s; medi %s notas da saída até a chegada (vale o que você disse).',
                           v_nome, coalesce(v_padrao, 'o prazo'), v_n)
               else format('%s: %s de %s notas medidas da saída até a chegada; conto %s (padrão).',
                           v_nome, v_n, v_nmin, coalesce(v_padrao, 'o prazo da classe')) end
        when 'foco_sombra' then format('Em teste: %s leva até %s da saída da nota até a chegada (%s notas); hoje conto %s (padrão).',
                                       v_nome, v_calc, v_n, coalesce(v_padrao, 'o prazo da classe'))
        when 'foco_em_uso' then format('%s leva até %s da saída da nota até a chegada (%s notas): é o prazo que uso desde %s.',
                                       v_nome, v_uso, v_n, v_desde)
        when 'foco_pergunta' then format('%s leva até %s da saída da nota até a chegada (%s notas), e hoje conto %s: a troca espera a sua resposta.',
                                         v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'foco_travado' then format('%s leva até %s da saída da nota até a chegada (%s notas); fico com %s até %s, como você decidiu.',
                                        v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'), v_trava)
        when 'acao' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas). Passei a contar %s no lugar de %s. *desfaz aprendizado* volta.',
                                v_nome, v_calc, v_n, v_calc, coalesce(v_efet, 'o prazo da classe'))
        when 'pergunta' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas), e hoje eu conto %s. É uma troca grande.',
                                    v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'opcao1' then format('Passo a contar %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o prazo da classe'))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: para %s volto a contar %s da saída da nota até a chegada. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nome, coalesce(v_volta, v_padrao, 'o prazo da classe'), v_dias)
        when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.',
                                v_nome, coalesce(v_efet, 'o prazo da classe'))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P4) a capacidade do dono (spec-fase6 §6.2 e §6.3): quanto dos meios-dias dele marcados no plano ele fez (a
  -- mediana das semanas: detalhe.taxa; "7 de cada 10"), nas últimas detalhe.janela semanas, e a parte da semana dele que o
  -- motor marca (o padrão é carga_max, a de todos). "Seria" no singular só em teste (o spec); "seriam" na pergunta.
  if p_item = 'capacidade_dono' then
    declare
      v_taxa numeric := (p_d #>> '{detalhe,taxa}')::numeric;
      v_dez  text := coalesce(round(v_taxa * 10)::text, '?');
      v_ult  text := case when p_d #>> '{detalhe,janela}' is null then 'Nas últimas semanas'
                          else format('Nas últimas %s semanas', p_d #>> '{detalhe,janela}') end;
      v_sems text := public._agenda_plural(coalesce((p_d ->> 'n')::int, 0), 'semana medida', 'semanas medidas');
    begin
      return case p_momento
        when 'foco_medindo' then format('A sua semana no plano: %s de %s semanas medidas; marco até %s da sua semana (padrão).',
                                        v_n, v_nmin, coalesce(v_padrao, 'a parte de todos'))
        when 'foco_sombra' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seria %s (em teste).',
                                       v_ult, v_dez, v_sems, coalesce(v_padrao, 'a parte de todos'), v_calc)
        when 'foco_em_uso' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s): marco até %s da sua semana desde %s.',
                                       v_ult, v_dez, v_sems, v_uso, v_desde)
        when 'foco_pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seriam %s: a troca espera a sua resposta.',
                                         v_ult, v_dez, v_sems, coalesce(v_efet, v_padrao), v_calc)
        when 'foco_travado' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Pelo medido seriam %s; fico com %s da sua semana até %s, como você decidiu.',
                                        v_ult, v_dez, v_sems, v_calc, coalesce(v_efet, v_padrao), v_trava)
        when 'acao' then format('%s você fez %s de cada 10 meios-dias seus do plano: passei a marcar até %s da sua semana (era %s). *desfaz aprendizado* volta.',
                                v_ult, v_dez, v_calc, coalesce(v_efet, v_padrao))
        when 'pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano. Hoje marco até %s da sua semana; pelo medido seriam %s.',
                                    v_ult, v_dez, coalesce(v_efet, v_padrao), v_calc)
        when 'opcao1' then format('Passo a marcar até %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, v_padrao))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da sua semana. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    coalesce(v_volta, v_padrao, 'a parte de todos'), v_dias)
        when 'fico' then format('Combinado: fico com %s da sua semana. Volto a perguntar se o medido mudar muito.',
                                coalesce(v_efet, v_padrao))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P5) a pontualidade com o cliente (só medida: só a linha do foco) e a folga do aviso de atraso (spec-fase6 §6.2
  -- e §6.3). A pontualidade lê detalhe.no_prazo e detalhe.p80_atraso_du; a folga é a faixa do aviso "com 2 dias úteis a mais"
  -- (0 = a faixa do plano, o padrão)
  if p_item = 'cliente_pontualidade' and p_momento like 'foco_%' then
    if p_momento = 'foco_medindo' then
      return format('Pontualidade: %s de %s OS com a 1ª data dita ao cliente medidas.', v_n, v_nmin);
    end if;
    return format('Pontualidade: %s de %s OS ficaram prontas até o dia dito primeiro ao cliente%s.',
                  coalesce(p_d #>> '{detalhe,no_prazo}', '0'), v_n,
                  case when coalesce((p_d #>> '{detalhe,p80_atraso_du}')::numeric, 0) > 0
                       then '; o atraso chega a ' || public._agenda_aprendizado_valor('aviso_folga', (p_d #>> '{detalhe,p80_atraso_du}')::numeric)
                       else '' end);
  end if;
  if p_item = 'aviso_folga' then
    declare
      v_cn numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      -- "a faixa com 2 dias úteis a mais" / "a faixa do plano", de cada valor
      v_fc text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0 then format('a faixa com %s a mais', v_calc)
                        else 'a faixa do plano' end;
      v_fu text := case when coalesce((p_d ->> 'em_uso')::numeric, 0) > 0 then format('a faixa com %s a mais', v_uso)
                        else 'a faixa do plano' end;
      v_fe text := case when coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_fv text := case when coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_terminou text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0
                              then format('o serviço terminou até %s depois do fim que eu disse', v_calc)
                              else 'o serviço terminou dentro da faixa que eu disse' end;
    begin
      return case p_momento
        when 'foco_medindo' then format('Avisos de atraso: %s de %s avisos medidos; dou %s (padrão).', v_n, v_nmin, v_fe)
        when 'foco_sombra' then format('Avisos de atraso: em %s, %s (em teste: eu daria %s).', v_n, v_terminou, v_fc)
        when 'foco_em_uso' then format('Avisos de atraso: em %s, %s: dou %s desde %s.', v_n, v_terminou, v_fu, v_desde)
        when 'foco_pergunta' then format('Avisos de atraso: em %s, %s, e hoje dou %s: a troca espera a sua resposta.',
                                         v_n, v_terminou, v_fe)
        when 'foco_travado' then format('Avisos de atraso: em %s, %s; fico com %s até %s, como você decidiu.',
                                        v_n, v_terminou, v_fe, v_trava)
        when 'acao' then format('Os avisos de atraso erraram para %s (%s avisos): passei a dar %s%s. *desfaz aprendizado* volta.',
                                case when v_cn > coalesce((p_d ->> 'efetivo')::numeric, 0) then 'menos' else 'mais' end,
                                v_n, v_fc,
                                case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0 then format(' (era %s)', v_fe) else '' end)
        when 'pergunta' then format('Medi os avisos de atraso: em %s, %s, e hoje eu dou %s. É uma troca grande.', v_n, v_terminou, v_fe)
        when 'opcao1' then format('Passo a dar %s', v_fc)
        when 'opcao2' then format('Fico com %s', v_fe)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a dar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_fv, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_fe)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P6) a carga de cada pessoa pelo plano cumprido (a revisão) e os gatilhos de um planejador mais forte (spec-fase6
  -- §6.2 e §6.3). A carga lê detalhe.mostrar (o plano cumprido das semanas que o texto diz, da mais antiga para a mais nova),
  -- detalhe.gatilho (baixo, alto ou nulo), detalhe.meta, detalhe.ppc_baixo e detalhe.ppc_alto; o planejador lê os números
  -- da semana (os_ativas, pessoas, valem, n_valem, total, limites), as semanas seguidas e a resposta da pergunta (uma vez só)
  if p_item = 'carga' then
    declare
      v_pcts  text[] := array(select public._agenda_aprendizado_valor('carga', x::numeric)
                                from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb))
                                     with ordinality t(x, o)
                               order by o);
      v_k     int := cardinality(array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb)) x));
      v_gat   text := p_d #>> '{detalhe,gatilho}';
      v_meta  text := public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,meta}')::numeric);
      v_hoje  text := coalesce(v_efet, v_padrao);
      v_cumpr text;
    begin
      v_cumpr := case when v_k = 0 then 'O plano cumprido ainda não foi medido'
                      when v_k = 1 then format('O plano foi cumprido em %s na última semana (meta %s)', v_pcts[1], v_meta)
                      else format('O plano foi cumprido em %s nas últimas %s semanas (meta %s)', public._agenda_lista(v_pcts, null),
                                  v_k, v_meta) end;
      return case p_momento
        when 'foco_medindo' then format('O plano cumprido: %s de %s semanas medidas; marco até %s da semana de cada pessoa.',
                                        v_n, v_nmin, v_padrao)
        when 'foco_sombra' then v_cumpr || '.'
                                || case when (p_d ->> 'calculado')::numeric is distinct from (p_d ->> 'padrao')::numeric
                                        then format(' Em teste: eu perguntaria se passo a marcar até %s da semana de cada pessoa (hoje %s).',
                                                    v_calc, v_padrao)
                                        else '' end
        when 'foco_em_uso' then format('%s; marco até %s da semana de cada pessoa.', v_cumpr, v_uso)
        when 'foco_pergunta' then format('%s: perguntei se passo a marcar até %s da semana de cada pessoa (hoje %s); espera a sua resposta.',
                                         v_cumpr, v_calc, v_hoje)
        when 'foco_travado' then format('%s; fico com %s até %s, como você decidiu.', v_cumpr, v_hoje, v_trava)
        when 'acao' then format('Passei a marcar até %s da semana de cada pessoa (era %s), como você decidiu. *desfaz aprendizado* volta.',
                                v_calc, v_hoje)
        when 'pergunta' then case v_gat
          when 'alto' then format('O plano foi cumprido acima de %s em %s semanas seguidas: posso estar marcando pouco.',
                                  public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_alto}')::numeric), v_k)
          else format('O plano foi cumprido abaixo de %s em %s semanas seguidas (%s). Recomendo marcar até %s da semana de cada pessoa (hoje %s).',
                      public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_baixo}')::numeric), v_k,
                      array_to_string(v_pcts, ', '), v_calc, v_hoje) end
        when 'opcao1' then format('Passo para %s', v_calc)
        when 'opcao2' then format('Fico com %s', v_hoje)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da semana de cada pessoa. Não pergunto de novo por %s dias, salvo se o plano cumprido mudar.',
                                    coalesce(v_volta, v_padrao), v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar em %s dias se o plano cumprido continuar assim.', v_hoje, v_dias)
      end;
    end;
  end if;
  if p_item = 'solver' then
    declare
      v_valem text[] := array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,valem}', '[]'::jsonb)) x);
      v_base  text := format('Gatilhos de um planejador mais forte: %s de %s (%s OS ativas, %s pessoas)',
                             coalesce(p_d #>> '{detalhe,n_valem}', '0'), coalesce(p_d #>> '{detalhe,total}', '0'),
                             coalesce(p_d #>> '{detalhe,os_ativas}', '0'), coalesce(p_d #>> '{detalhe,pessoas}', '0'));
      v_resp  text := p_d #>> '{detalhe,resposta}';
      v_ja    boolean := coalesce((p_d #>> '{detalhe,perguntado}')::boolean, false);
      v_lista text;
    begin
      v_lista := public._agenda_lista(array(
        select 'de ' || case g
                 when 'os_ativas' then format('%s OS ativas', p_d #>> '{detalhe,limites,os_ativas}')
                 when 'pessoas' then format('%s pessoas', p_d #>> '{detalhe,limites,pessoas}')
                 when 'curtas_dia' then format('%s idas curtas suas por dia útil',
                                               public._agenda_num((p_d #>> '{detalhe,limites,curtas_dia}')::numeric, 1))
                 when 'descarte' then format('%s%% dos planos que eu sugeri descartados',
                                             round(100 * (p_d #>> '{detalhe,limites,descarte}')::numeric))
               end
          from unnest(v_valem) with ordinality u(g, o) order by o), null);
      return case p_momento
        when 'foco_medindo' then format('%s; medi %s de %s semanas.', v_base, v_n, v_nmin)
        when 'foco_sombra' then v_base || '.'
                                || case when (p_d ->> 'calculado')::numeric >= 1
                                        then ' Em teste: eu avisaria que vale estudar um planejador mais forte.' else '' end
        when 'foco_pergunta' then v_base || '. Perguntei se vale estudar um planejador mais forte; espera a sua resposta.'
        when 'foco_em_uso' then v_base || case when v_resp = '1' then '. Você quis ver isso; nada muda sozinho.'
                                               when v_resp = '2' then '. Você disse "agora não"; não pergunto de novo.'
                                               when v_ja then '. Já perguntei uma vez; não pergunto de novo.'
                                               else '.' end
        when 'foco_travado' then v_base || '. Você disse "agora não"; não pergunto de novo.'
        when 'pergunta' then format('Há %s semanas a agenda passa %s: vale estudar um planejador mais forte. Nada muda sozinho.',
                                    coalesce(p_d #>> '{detalhe,semanas_seguidas}', v_n), v_lista)
        when 'opcao1' then 'Quero ver isso'
        when 'opcao2' then 'Agora não'
        when 'opcao3' then 'Volto ao padrão'
        when 'acao' then 'Combinado: anotei que você quer ver um planejador mais forte. Nada muda sozinho na agenda.'
        when 'fico' then 'Combinado: agora não. Não pergunto de novo.'
        when 'desfeito' then 'Desfeito: volto a só medir os gatilhos de um planejador mais forte.'
      end;
    end;
  end if;
  -- FASE 6: fim
  -- O fator de campo (spec-fase6 §6.2 e §6.3).
  -- CORREÇÃO FASE 6: (C2) texto 1: a linha do fator no cartão e no foco diz para que o fator serve — o limiar do "o que
  -- falta?"; os dias do plano continuam os que o dono disse (a linha fica logo abaixo de "4 dias (você disse)" e fazia crer
  -- que o plano usa 1,7 × 4) —; com o valor em uso igual ao padrão, que é o mesmo de sempre (e não "desde sex 30/10"); em
  -- teste, com o medido igual ao padrão, sem o "hoje seria 1,5×, e vale 1,5×". Os outros momentos, como antes (abaixo).
  if p_item = 'fator' and v_nivel is not null and p_momento = 'foco_em_uso' then
    if (p_d ->> 'em_uso')::numeric is not distinct from (p_d ->> 'padrao')::numeric then
      return format('%s levam até %s o combinado (%s OS): é o mesmo que eu já usava.',
                    public._agenda_maiuscula(v_nivel), v_uso, v_n);
    end if;
    return format('%s levam até %s o combinado (%s OS): uso %s desde %s para perguntar o que falta (os dias do plano continuam os que você disse).',
                  public._agenda_maiuscula(v_nivel), v_uso, v_n, v_uso, v_desde);
  end if;
  if p_item = 'fator' and v_nivel is not null and p_momento = 'foco_sombra'
     and (p_d ->> 'calculado')::numeric is not distinct from (p_d ->> 'padrao')::numeric then
    return format('Em teste: %s levam até %s o combinado (%s OS): é o mesmo que eu já uso.', v_nivel, v_calc, v_n);
  end if;
  -- CORREÇÃO FASE 6: fim
  if p_item = 'fator' and v_nivel is not null then
    return case p_momento
      when 'foco_medindo' then format('%s: %s de %s OS medidas; para perguntar o que falta, uso %s o combinado (padrão).',
                                      public._agenda_maiuscula(v_nivel), v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: %s levam até %s o combinado (%s OS); hoje seria %s, e vale %s (padrão).',
                                     v_nivel, v_calc, v_n, v_calc, v_padrao)
      when 'foco_em_uso' then format('%s levam até %s o combinado (%s OS): é o que uso desde %s.',
                                     public._agenda_maiuscula(v_nivel), v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('%s levam até %s o combinado (%s OS), e hoje uso %s: a troca espera a sua resposta.',
                                       public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet)
      when 'foco_travado' then format('%s levam até %s o combinado (%s OS); fico com %s até %s, como você decidiu.',
                                      public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Aprendi com as OS concluídas: %s levam até %s o combinado (%s OS). Passei a usar %s no lugar de %s para perguntar o que falta. *desfaz aprendizado* volta.',
                              v_nivel, v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi %s: levam até %s o combinado (%s OS), e hoje eu uso %s. É uma troca grande.',
                                  v_nivel, v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: %s voltam a %s para perguntar o que falta. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  v_nivel, v_volta, v_dias)
      when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- Os outros itens: um texto provisório, sem jargão; o pacote de cada item (P2 a P6) recria esta função com o texto da §6.
  v_rotulo := case p_item
    when 'mo' then 'O valor de mão de obra por diária'
    when 'presenca' then 'A sua presença nas OS'
    when 'fornecedor_atraso' then 'O atraso do fornecedor'
    when 'fornecedor_prazo' then 'O prazo do fornecedor'
    when 'capacidade_dono' then 'A parte da sua semana no plano'
    when 'cliente_pontualidade' then 'A pontualidade com o cliente'
    when 'aviso_folga' then 'A folga do aviso de atraso'
    when 'carga' then 'A parte da semana de cada pessoa no plano'
    when 'solver' then 'Os sinais de um planejador mais forte'
    else 'O que eu medi' end;
  return case p_momento
    when 'foco_medindo' then format('%s: %s de %s medidas; vale %s (padrão).', v_rotulo, v_n, v_nmin, coalesce(v_padrao, 'o de hoje'))
    when 'foco_sombra' then format('Em teste: %s medido é %s (%s medidas); vale %s (padrão).',
                                   lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_padrao, 'o de hoje'))
    when 'foco_em_uso' then format('%s: uso %s, pelo medido (%s medidas), desde %s.', v_rotulo, v_uso, v_n, v_desde)
    when 'foco_pergunta' then format('%s: o medido é %s (%s medidas), e hoje uso %s: a troca espera a sua resposta.',
                                     v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'foco_travado' then format('%s: o medido é %s (%s medidas); fico com %s até %s, como você decidiu.',
                                    v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'), v_trava)
    when 'acao' then format('Aprendi com o que aconteceu: %s passou a %s (era %s; %s medidas). *desfaz aprendizado* volta.',
                            lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, coalesce(v_efet, 'o padrão'), v_n)
    when 'pergunta' then format('Medi %s: %s (%s medidas), e hoje uso %s. É uma troca grande.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'opcao1' then format('Passo a usar %s', v_calc)
    when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o de agora'))
    when 'opcao3' then 'Volto ao padrão'
    when 'desfeito' then format('Desfeito: %s volta a %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), coalesce(v_volta, 'o padrão'), v_dias)
    when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', coalesce(v_efet, 'o padrão'))
  end;
end;
$function$;

comment on function public._agenda_aprendizado_texto(text, text, jsonb) is
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe). FASE 6 (P4): a capacidade do dono (capacidade_dono) tem os textos da spec §6.2/§6.3 ("Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano …"; a taxa e a janela vêm do detalhe). FASE 6 (P5): a pontualidade com o cliente (cliente_pontualidade: só a linha do foco, "Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.") e a folga do aviso de atraso (aviso_folga: "a faixa com 2 dias úteis a mais"; 0 = a faixa do plano) têm os textos da spec §6.2/§6.3. FASE 6 (P6): a carga de cada pessoa pelo plano cumprido ("O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%)."; a pergunta "abaixo de 60% em 3 semanas seguidas (…). Recomendo marcar até 70% …") e os gatilhos de um planejador mais forte ("Gatilhos de um planejador mais forte: 0 de 4 (9 OS ativas, 4 pessoas)."; a pergunta "Há 4 semanas a agenda passa de 25 OS ativas e de 6 pessoas: …") têm os textos da spec §6.2/§6.3. Todos os itens com o texto da spec. CORREÇÃO FASE 6 (C2, textos 1 e 5): o fator em uso diz "uso 1,7× desde … para perguntar o que falta (os dias do plano continuam os que você disse)", e "é o mesmo que eu já usava" com o valor do padrão; em teste, com o medido igual ao padrão, sem o "hoje seria X, e vale X"; a pergunta do R$ por diária diz que inclui as OS em que o dono também trabalhou.';

-- _agenda_aprendizado_gravar (de 20261029100100_agenda_fase6_medicao.sql)
create or replace function public._agenda_aprendizado_gravar(p_item text, p_chave text, p_nivel text, p_calculado numeric,
                                                             p_n integer, p_amostra jsonb, p_padrao numeric, p_detalhe jsonb,
                                                             p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_lista  text := public._agenda_aprendizado_da_lista(p_item);
  v_nmin   int;
  r0       public.agenda_aprendizado;
  r        public.agenda_aprendizado;
  v_efet   numeric;
  v_estado text;
  v_d      jsonb;
  v_ops    jsonb;
  v_txt    text;
  v_acao   uuid;
  v_perg   uuid;
  v_aberta boolean := false;
  v_motivo text;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
begin
  if p_item is null or p_chave is null or p_nivel is null or p_agora is null then
    raise exception 'Falta o item, a chave, o nível ou a hora.' using errcode = '22023';
  end if;
  v_nmin := case p_item
    when 'fator' then c.fator_n_min when 'mo' then c.mo_n_min when 'presenca' then c.presenca_n_min
    when 'fornecedor_atraso' then c.fornecedor_n_min when 'fornecedor_prazo' then c.fornecedor_n_min
    when 'capacidade_dono' then c.capacidade_semanas_min when 'cliente_pontualidade' then c.cliente_n_min
    when 'aviso_folga' then c.aviso_n_min when 'carga' then least(c.ppc_baixo_semanas, c.ppc_alto_semanas)
    when 'solver' then c.solver_semanas end;
  if v_nmin is null then
    raise exception 'Item de aprendizado desconhecido: %.', p_item using errcode = '22023';
  end if;

  -- A linha (nasce medindo) e a trava dela: duas rodadas não gravam a mesma chave ao mesmo tempo.
  insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, calculado_em)
  values (p_item, p_chave, p_nivel, p_padrao, v_nmin, p_agora)
  on conflict (item, chave) do nothing;
  select * into r0 from public.agenda_aprendizado where item = p_item and chave = p_chave for update;
  if r0.nivel <> p_nivel then
    raise exception 'A chave % de % é do nível %, não %.', p_chave, p_item, r0.nivel, p_nivel using errcode = '22023';
  end if;
  if r0.pergunta_id is not null then
    v_aberta := exists (select 1 from public.agenda_perguntas q where q.id = r0.pergunta_id and q.estado = 'aberta');
  end if;
  r := r0;
  r.padrao := p_padrao;
  r.calculado := p_calculado;
  r.n := coalesce(p_n, 0);
  r.n_min := v_nmin;
  r.amostra := case when jsonb_typeof(p_amostra) = 'array'
                    then coalesce((select jsonb_agg(x order by o) from jsonb_array_elements(p_amostra) with ordinality t(x, o)
                                    where o <= 60), '[]'::jsonb)
                    else '[]'::jsonb end;
  r.detalhe := case when jsonb_typeof(p_detalhe) = 'object' then p_detalhe else '{}'::jsonb end;
  r.calculado_em := p_agora;
  -- O que vale hoje: o em uso (também guardado na pergunta e na trava), senão o padrão.
  v_efet := coalesce(r0.em_uso, p_padrao);

  if p_calculado is null or r.n < v_nmin then
    -- 1. poucas medidas
    v_estado := 'medindo';
  elsif v_lista is null or c.modo_aprendizado <> 'ligado' or not (v_lista = any (c.aprendizado_ligados)) then
    -- 2. em teste (o modo, a lista; a pontualidade com o cliente é só medida)
    v_estado := 'sombra';
  elsif r0.estado = 'travado' and v_hoje <= r0.travado_ate
        and (p_calculado = r0.travado_valor
             or public._agenda_aprendizado_troca_cabe(p_item, p_nivel, r0.travado_valor, p_calculado)) then
    -- 3. o dono travou e o medido não andou mais que o limite (o item que sempre pergunta: o medido não mudou)
    v_estado := 'travado';
  elsif p_calculado = v_efet then
    -- 4. igual ao que vale
    v_estado := 'em_uso';
  elsif public._agenda_aprendizado_troca_cabe(p_item, p_nivel, v_efet, p_calculado) then
    -- 5. troca pequena: entra sozinha, com *desfaz*
    v_estado := 'em_uso';
  else
    -- 6. troca grande: pergunta
    v_estado := 'pergunta';
  end if;

  r.estado := v_estado;
  if v_estado in ('medindo', 'sombra') then
    r.em_uso := null;
    r.em_uso_desde := null;
  elsif v_estado = 'em_uso' then
    r.em_uso := p_calculado;
    r.em_uso_desde := case when r0.em_uso = p_calculado and r0.estado = 'em_uso' then coalesce(r0.em_uso_desde, p_agora)
                           else p_agora end;
  else
    -- pergunta e trava: o que vale continua valendo (nulo = o padrão)
    r.em_uso := case when r0.estado in ('em_uso', 'pergunta', 'travado') then r0.em_uso end;
  end if;
  if v_estado <> 'travado' then
    r.travado_ate := null;
    r.travado_valor := null;
  end if;

  v_d := jsonb_build_object('chave', p_chave, 'calculado', p_calculado, 'em_uso', r.em_uso, 'efetivo', v_efet,
                            'padrao', p_padrao, 'n', r.n, 'n_min', v_nmin,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', c.aprender_trava_dias, 'detalhe', r.detalhe);

  -- A pergunta aberta desta chave: fica (a mesma troca), ou sai (o medido voltou, caiu abaixo do mínimo, saiu do uso, mudou).
  if v_aberta and not (v_estado = 'pergunta' and r0.estado = 'pergunta' and r0.calculado is not distinct from p_calculado) then
    v_motivo := case
      when v_estado = 'medindo' then 'Menos medidas que o mínimo: volto a medir.'
      when v_estado = 'sombra' then 'Esse aprendizado saiu do uso (em teste).'
      when v_estado = 'pergunta' then 'O medido mudou: perguntei de novo com o número novo.'
      else 'O medido voltou para perto do que vale.' end;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = v_motivo
     where id = r0.pergunta_id and estado = 'aberta';
    v_aberta := false;
  end if;

  if v_estado = 'em_uso' and r.em_uso is distinct from v_efet then
    -- 5. a ação no "o que mudou" das 17:30, com *desfaz aprendizado*
    insert into public.agenda_acoes (dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate, criada_em)
    values (v_hoje, true, 'vigia', 'aprendizado',
            left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'acao', v_d), 400), 400),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', r0.em_uso, 'valor', v_efet,
                               'estado', r0.estado),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', p_calculado, 'n', r.n),
            p_agora + c.desfazer_validade, p_agora)
    returning id into v_acao;
    r.acao_id := v_acao;
  elsif v_estado = 'pergunta' and not v_aberta then
    -- 6. a pergunta crítica: 1 uso o medido (recomendo); 2 fico com o de agora; 3 volto ao padrão (só quando o que vale não é
    -- o padrão e o medido também não; a carga e o planejador só têm 1 e 2)
    v_ops := jsonb_build_array(
      jsonb_build_object('n', 1, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao1', v_d),
                         'efeito', jsonb_build_object('em_uso', p_calculado)),
      jsonb_build_object('n', 2, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao2', v_d),
                         'efeito', jsonb_build_object('travar', p_calculado)));
    if p_item not in ('carga', 'solver') and v_efet is distinct from p_padrao and p_calculado is distinct from p_padrao then
      v_ops := v_ops || jsonb_build_array(jsonb_build_object('n', 3, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao3', v_d),
                                                             'efeito', jsonb_build_object('em_uso', null)));
    end if;
    select public._agenda_aprendizado_texto(p_item, 'pergunta', v_d) || ' '
           || string_agg(format('%s) %s%s', o ->> 'n', o ->> 'texto',
                                case when o ->> 'n' = '1' and o ->> 'texto' !~ 'recomend' then ' (recomendo)' else '' end),
                         '; ' order by (o ->> 'n')::int) || '.'
      into v_txt
      from jsonb_array_elements(v_ops) o;
    -- CORREÇÃO FASE 6: (C2) texto 5: na troca grande do R$ por diária a opção 1 não leva o "(recomendo)" — a conta inclui a mão
    -- de obra das OS em que o dono também trabalhou, e a decisão é dele, sem empurrão. A recomendação da pergunta continua 1
    -- (o CHECK critica_tem_opcoes pede uma); só o texto muda.
    if p_item = 'mo' then
      v_txt := replace(v_txt, format('1) %s (recomendo)', v_ops -> 0 ->> 'texto'), format('1) %s', v_ops -> 0 ->> 'texto'));
    end if;
    -- CORREÇÃO FASE 6: fim
    insert into public.agenda_perguntas (tipo, chave, dia, texto, opcoes, recomendacao, modo, criada_em)
    values ('aprendizado', left(format('aprendizado:%s:%s', p_item, p_chave), 200), v_hoje,
            left(public._agenda_corta(v_txt, 600), 600), v_ops, 1, 'ligado', p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing
    returning id into v_perg;
    if v_perg is null then
      select q.id into v_perg from public.agenda_perguntas q
       where q.chave = left(format('aprendizado:%s:%s', p_item, p_chave), 200) and q.modo = 'ligado' and q.estado = 'aberta';
    end if;
    r.pergunta_id := v_perg;
  end if;

  r.texto := left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'foco_' || v_estado, v_d), 400), 400);

  -- O histórico: em uso, estado e calculado, quando mudam (os 20 mais novos).
  foreach k in array array['em_uso', 'estado', 'calculado'] loop
    if to_jsonb(r0) -> k is distinct from to_jsonb(r) -> k then
      v_antes := v_antes || jsonb_build_object(k, to_jsonb(r0) -> k);
      v_depois := v_depois || jsonb_build_object(k, to_jsonb(r) -> k);
    end if;
  end loop;
  v_hist := r0.historico;
  if v_antes <> '{}'::jsonb then
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', v_antes, 'depois', v_depois));
    if jsonb_array_length(v_hist) > 20 then
      select jsonb_agg(x order by o) into v_hist
        from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
    end if;
  end if;

  update public.agenda_aprendizado
     set padrao = r.padrao, calculado = r.calculado, em_uso = r.em_uso, n = r.n, n_min = r.n_min, amostra = r.amostra,
         detalhe = r.detalhe, estado = r.estado, texto = r.texto, calculado_em = r.calculado_em, em_uso_desde = r.em_uso_desde,
         travado_ate = r.travado_ate, travado_valor = r.travado_valor, pergunta_id = r.pergunta_id, acao_id = r.acao_id,
         historico = v_hist
   where id = r0.id;

  return jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'estado', v_estado, 'estado_antes', r0.estado,
                            'calculado', p_calculado, 'em_uso', r.em_uso, 'vale', coalesce(r.em_uso, p_padrao),
                            'acao_id', v_acao, 'pergunta_id', case when v_estado = 'pergunta' then r.pergunta_id end,
                            'texto', r.texto);
end;
$function$;

comment on function public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz) is
  'Agenda de Produção (Fase 6): o gravador único de agenda_aprendizado (spec-fase6 §5.1) — o upsert de (item, chave) e o estado, nesta ordem: 1 n < n_min → medindo; 2 modo fora de ligado, item fora de aprendizado_ligados ou só de medida → sombra; 3 travado e dentro da trava (a data e o limite de troca a partir do valor recusado) → fica; 4 o medido = o que vale → em uso; 5 troca dentro do limite (§3.2) → em uso + a ação aprendizado (origem vigia, desfazível por desfazer_validade); 6 troca grande → pergunta crítica aprendizado (chave aprendizado:<item>:<chave>, uma aberta por chave). Toda mudança de em uso, estado e calculado vai ao histórico. Definer, sem grant a ninguém. CORREÇÃO FASE 6 (C2, texto 5): na pergunta do R$ por diária a opção 1 sai sem o "(recomendo)" (a recomendação da pergunta continua 1, pelo CHECK).';

-- agenda_cliente_preparar (de 20261029100700_agenda_fase6_acabamento.sql)
create or replace function public.agenda_cliente_preparar(p_autor uuid, p_os text, p_tipo text, p_firme boolean default false,
                                                          p_trecho text default null, p_hoje date default public._hoje_brt(),
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_tipo  text := lower(btrim(coalesce(p_tipo, '')));
  v_ro    jsonb;
  v_os    uuid;
  x       jsonb;
  v_rk    jsonb;
  v_nome  text;
  v_st    text;
  v_dia   date;
  v_var   text;
  v_dados jsonb := '{}'::jsonb;
  v_alvo  timestamptz := p_agora;
  v_valida timestamptz;
  v_chave text;
  v_r     jsonb;
  m       public.agenda_cliente_mensagens%rowtype;
  v_conc  date;
  v_ini   date;
  v_pl    jsonb;
  v_txt   text;
begin
  if v_tipo not in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data', 'pronto',
                    'pronto_lembrete', 'pos_servico', 'mudanca_no_dia') then
    raise exception 'O tipo da mensagem ao cliente não existe: "%".', coalesce(p_tipo, '') using errcode = '22023';
  end if;
  if cf.modo_cliente = 'desligado' then
    return public._agenda_recusa('As mensagens ao cliente estão desligadas: não preparei nada.', 'desligada');
  end if;
  if nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que avisar ao cliente.', 'sem_trecho');
  end if;
  if v_tipo = 'mudanca_no_dia' then
    return public._agenda_recusa('O aviso de mudança no dia eu mando sozinho quando o plano muda (chuva, falta da equipe). Para outra data, me diga o novo dia do serviço.',
                                 'mudanca_no_dia');
  end if;
  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' = 'fora_da_carteira' and v_tipo in ('pronto', 'pronto_lembrete', 'pos_servico') then
    v_os := (v_ro ->> 'id')::uuid;
  elsif v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  else
    v_os := (v_ro ->> 'id')::uuid;
  end if;
  x := public._agenda_cliente_contexto(v_os, p_hoje);
  v_nome := coalesce(x ->> 'nome', 'cliente');
  v_st := x ->> 'status';
  if not coalesce((x ->> 'telefone_ok')::boolean, false) then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('%s não tem telefone no cadastro: não tenho como mandar.', v_nome), 'sem_telefone');
    -- FASE 6: fim
    return public._agenda_recusa(format('O %s não tem telefone no cadastro: não tenho como mandar.', v_nome), 'sem_telefone');
  end if;
  if coalesce((x ->> 'opt_out')::boolean, false) then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('%s pediu para não receber mensagens: não mando.', v_nome), 'opt_out');
    -- FASE 6: fim
    return public._agenda_recusa(format('O %s pediu para não receber mensagens: não mando.', v_nome), 'opt_out');
  end if;

  if v_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data') then
    v_dia := (x ->> 'dia')::date;
    -- d09: material sem previsão ou não conferido nunca vira data firme (antes da data: é o que o dono precisa saber)
    if coalesce(x ->> 'material_estado', '') <> 'completo' then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O material de %s ainda não está todo na mão (%s): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.',
                                          v_nome, case x ->> 'material_estado' when 'previsto' then 'tem peça a caminho'
                                                                             when 'sem_previsao' then 'tem peça sem previsão de chegada'
                                                                             when 'atrasado' then 'tem peça atrasada'
                                                                             else 'o material ainda não foi conferido' end),
                                   'material');
      -- FASE 6: fim
      return public._agenda_recusa(format('O material do %s ainda não está todo na mão (%s): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.',
                                          v_nome, case x ->> 'material_estado' when 'previsto' then 'tem peça a caminho'
                                                                             when 'sem_previsao' then 'tem peça sem previsão de chegada'
                                                                             when 'atrasado' then 'tem peça atrasada'
                                                                             else 'o material ainda não foi conferido' end),
                                   'material');
    end if;
    if v_dia is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('%s não tem data no plano: não tenho o que %s.', v_nome,
                                          case v_tipo when 'confirmar' then 'confirmar' when 'nova_data' then 'dizer de data nova'
                                                      else 'avisar' end), 'sem_data');
      -- FASE 6: fim
      return public._agenda_recusa(format('O %s não tem data no plano: não tenho o que %s.', v_nome,
                                          case v_tipo when 'confirmar' then 'confirmar' when 'nova_data' then 'dizer de data nova'
                                                      else 'avisar' end), 'sem_data');
    end if;
    if v_tipo in ('vespera', 'acesso') then
      if v_dia <= p_hoje then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('O serviço de %s é hoje: a véspera já passou.', v_nome), 'passou');
        -- FASE 6: fim
        return public._agenda_recusa(format('O serviço do %s é hoje: a véspera já passou.', v_nome), 'passou');
      end if;
      v_alvo := greatest(p_agora, public._agenda_cliente_toque(public._agenda_cliente_vespera(v_dia)));
    end if;
  elsif v_tipo = 'pode_atrasar' then
    v_rk := public._agenda_cliente_risco(v_os, p_hoje);
    if (x #>> '{prometido,ate}') is null or v_rk is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('Não há data dita para %s: sem data dita, não há atraso a avisar. Se você disse uma data, me conte ("falei pro %s que é dia 3").',
                                          v_nome, v_nome), 'sem_prometido');
      -- FASE 6: fim
      return public._agenda_recusa(format('Não há data dita ao %s: sem data dita, não há atraso a avisar. Se você disse uma data a ele, me conte ("falei pro %s que é dia 3").',
                                          v_nome, v_nome), 'sem_prometido');
    end if;
    if coalesce((v_rk ->> 'passou')::boolean, false) then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('A data que %s ouviu (%s) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.',
                                          v_nome, public._dia_curto((v_rk ->> 'dito_ate')::date)), 'passou');
      -- FASE 6: fim
      return public._agenda_recusa(format('A data que o %s ouviu (%s) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.',
                                          v_nome, public._dia_curto((v_rk ->> 'dito_ate')::date)), 'passou');
    end if;
    if coalesce(p_firme, false) then
      -- a data firme do plano no lugar da faixa (d09: só o dono decide, e só com o plano publicado)
      if (x ->> 'dia') is null or (x ->> 'fim') is null then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('%s não tem o plano publicado: não tenho data firme para dizer; vai a faixa.', v_nome),
                                     'sem_plano');
        -- FASE 6: fim
        return public._agenda_recusa(format('O %s não tem o plano publicado: não tenho data firme para dizer; vai a faixa.', v_nome),
                                     'sem_plano');
      end if;
      v_var := 'remarcado';
      v_dia := (x ->> 'dia')::date;
      v_dados := jsonb_build_object('dia', x -> 'dia', 'fim', x -> 'fim', 'prometido_tipo', 'firme',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate');
      -- CORREÇÃO FASE 5: (item 7) a data firme que o DONO manda dizer passa pela revalidação sem o passo do material (d09:
      -- só o dono troca a faixa pela data firme do plano); (item 6) com o início igual ao que o cliente ouviu, a forma fim
      v_dados := v_dados || jsonb_build_object('firme_do_dono', true)
                 || case when v_dia = coalesce((v_rk ->> 'dito_de')::date, (v_rk ->> 'dito_ate')::date)
                         then jsonb_build_object('forma', 'fim') else '{}'::jsonb end;
      -- CORREÇÃO FASE 5: fim
    else
      if coalesce((v_rk ->> 'sem_data')::boolean, false) then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('A peça de %s ainda não tem previsão: não tenho data nova para dizer. Com a previsão eu preparo (ou peça com a data firme do plano).',
                                            v_nome), 'sem_data');
        -- FASE 6: fim
        return public._agenda_recusa(format('A peça do %s ainda não tem previsão: não tenho data nova para dizer. Com a previsão eu preparo (ou peça com a data firme do plano).',
                                            v_nome), 'sem_data');
      end if;
      if not coalesce((v_rk ->> 'risco')::boolean, false) then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('O plano de %s ainda cabe na data dita (%s): não há atraso a avisar.', v_nome,
                                            public._dia_curto((v_rk ->> 'dito_ate')::date)), 'sem_risco');
        -- FASE 6: fim
        return public._agenda_recusa(format('O plano do %s ainda cabe na data que ele ouviu (%s): não há atraso a avisar.', v_nome,
                                            public._dia_curto((v_rk ->> 'dito_ate')::date)), 'sem_risco');
      end if;
      v_var := v_rk ->> 'variante';
      v_dia := (v_rk ->> 'faixa_de')::date;
      v_dados := jsonb_build_object('faixa_de', v_rk -> 'faixa_de', 'faixa_ate', v_rk -> 'faixa_ate', 'prometido_tipo', v_rk -> 'tipo',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate')
                 || case when v_var = 'peca' then jsonb_build_object('peca_de', v_rk -> 'peca', 'peca_ate', v_rk -> 'peca')
                         else '{}'::jsonb end;
      -- CORREÇÃO FASE 5: (item 6) o remarcado da rodada com o mesmo início: a forma fim (como o passo atraso)
      if v_rk ->> 'forma' = 'fim' then
        v_dados := v_dados || jsonb_build_object('forma', 'fim', 'dia', v_rk -> 'faixa_de', 'fim', v_rk -> 'faixa_ate');
      end if;
      -- CORREÇÃO FASE 5: fim
    end if;
    v_valida := public._agenda_cliente_ultimo_fim((v_rk ->> 'dito_ate')::date);
  elsif v_tipo = 'andamento' then
    v_pl := public._agenda_plano_da_os(v_os, p_hoje);
    select min(a.dia) into v_ini from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.resultado in ('cumprido', 'parcial');
    if v_st <> 'in_progress' or v_ini is null or (v_pl ->> 'ultimo_dia') is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s ainda não começou (ou não tem o fim no plano): não há andamento a contar.', v_nome),
                                   'sem_andamento');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s ainda não começou (ou não tem o fim no plano): não há andamento a contar.', v_nome),
                                   'sem_andamento');
    end if;
    v_var := 'semanal';
    v_dia := (v_pl ->> 'ultimo_dia')::date;
    v_dados := jsonb_build_object('n_feitos', floor(coalesce((v_pl ->> 'meios_cumpridos')::numeric, 0))::int,
                                  'chave', to_char(p_hoje, 'IYYY-"S"IW'));
  else
    -- pronto, lembrete e pós-serviço: a OS concluída
    select (so.check_out_at at time zone 'America/Sao_Paulo')::date into v_conc
      from public.service_orders so where so.id = v_os and so.status in ('completed', 'invoiced');
    if v_conc is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s ainda não está concluído.', v_nome), 'nao_concluida');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s ainda não está concluído.', v_nome), 'nao_concluida');
    end if;
    if v_tipo in ('pronto', 'pronto_lembrete')
       and exists (select 1 from public.service_orders so where so.id = v_os and so.delivered_at is not null) then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s já foi entregue.', v_nome), 'entregue');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s já foi entregue.', v_nome), 'entregue');
    end if;
    if v_tipo = 'pronto' then
      v_dia := v_conc;
    elsif v_tipo = 'pronto_lembrete' then
      v_dados := jsonb_build_object('chave', '2');
    else
      v_dados := jsonb_build_object('chave', 'pos');
    end if;
  end if;

  begin
    v_r := public._agenda_cliente_registrar(v_tipo, v_var, v_os, v_dia, v_dados, v_alvo, v_valida, 'dono', null, p_agora, v_autor);
    if v_r ->> 'motivo' = 'ja_existe' then
      select * into m from public.agenda_cliente_mensagens where id = (v_r ->> 'id')::uuid;
      if m.estado = 'recusada' then
        -- a do mesmo dia já foi recusada (segurada, vencida…): o pedido explícito do dono vale uma vez mais
        v_chave := coalesce(nullif(btrim(v_dados ->> 'chave'), ''), v_dia::text, to_char(p_agora at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'))
                   || ':dono';
        v_r := public._agenda_cliente_registrar(v_tipo, v_var, v_os, v_dia, v_dados || jsonb_build_object('chave', v_chave), v_alvo,
                                                v_valida, 'dono', null, p_agora, v_autor);
        if v_r ->> 'motivo' = 'ja_existe' then
          select * into m from public.agenda_cliente_mensagens where id = (v_r ->> 'id')::uuid;
        end if;
      end if;
    end if;
  exception when sqlstate '22023' then
    -- CORREÇÃO FASE 6: (C2) texto 6: a forma fim cujo fim novo não passa do dia que o cliente ouviu (n < 1, a recusa do P7 em
    -- _agenda_cliente_texto) diz isso ao dono em palavras, e não o texto técnico do erro
    if sqlerrm = 'Falta o fim novo depois do dia dito para a mensagem pode_atrasar ao cliente.' then
      return public._agenda_recusa('Não preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar.', 'texto');
    end if;
    -- CORREÇÃO FASE 6: fim
    return public._agenda_recusa(format('Não preparei: %s', sqlerrm), 'texto');
  end;

  if v_r ->> 'motivo' = 'ja_existe' then
    v_txt := case
      when m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
        then format('Já está pronta, esperando você (sai %s): "%s". Para mandar: *manda cliente %s*.',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto, v_nome)
      when m.estado = 'aguardando_dono' then format('Essa mensagem ao %s é uma decisão que espera você: responda pela conversa (1, 2 ou 3).', v_nome)
      when m.estado in ('registrada', 'enfileirada') and m.modo = 'ligado'
        then format('Essa mensagem já vai sair sozinha %s: "%s". Para não mandar: *segura cliente %s*.',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto, v_nome)
      when m.estado in ('registrada', 'enfileirada')
        then format('Em teste: essa mensagem já está registrada (sairia %s): "%s".',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto)
      when m.enviada_em is not null
        then format('Já mandei ao %s %s às %s: "%s".', v_nome,
                    public._dia_curto((m.enviada_em at time zone 'America/Sao_Paulo')::date),
                    to_char(m.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI'), m.texto)
      else format('Essa mensagem ao %s já foi registrada e não sai (%s).', v_nome, coalesce(m.recusa_motivo, m.estado)) end;
    -- CORREÇÃO FASE 5: (item 15) sem artigo antes do nome ("Já mandei para Nelson …")
    v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
    -- CORREÇÃO FASE 5: fim
    return jsonb_build_object('ok', true, 'status', 'ja_existe', 'texto', v_txt, 'mensagem_id', m.id, 'estado', m.estado,
                              'modo', m.modo);
  end if;
  if v_r ->> 'estado' = 'recusada' then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('Não preparei: a mensagem para %s passaria da hora de servir (sairia %s).', v_nome,
                                        public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)),
                                 coalesce(v_r ->> 'motivo', 'vencida'));
    -- FASE 6: fim
    return public._agenda_recusa(format('Não preparei: a mensagem ao %s passaria da hora de servir (sairia %s).', v_nome,
                                        public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)),
                                 coalesce(v_r ->> 'motivo', 'vencida'));
  end if;
  v_txt := case
    when v_r ->> 'modo' = 'ligado'
      then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', v_nome,
                  public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto', v_nome)
    when cf.modo_cliente = 'ligado'
      then format('Esse tipo de mensagem (%s) ainda está em teste: não sai. Eu teria preparado para o %s, para sair %s: "%s".',
                  public._agenda_cliente_tipo_texto(v_tipo), v_nome,
                  public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto')
    else format('Em teste (as mensagens ao cliente ainda não saem): eu teria preparado para o %s, para sair %s: "%s".', v_nome,
                public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto') end;
  -- CORREÇÃO FASE 5: (item 15) "Pronto para Vanderlei, sai agora: …" (sem artigo antes do nome)
  v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('ok', true, 'status', 'preparada', 'texto', v_txt, 'mensagem_id', v_r -> 'id',
                            'estado', v_r ->> 'estado', 'modo', v_r ->> 'modo', 'enviar_em', v_r -> 'enviar_em');
end;
$function$;

comment on function public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P5): a ferramenta cliente_avisar — prepara a mensagem-modelo que o dono pede e NUNCA envia. Resolve a OS (agenda_resolver_os; o pronto, o lembrete e o pós-serviço aceitam a OS concluída fora da carteira), confere o telefone e o opt-out, o tipo e os dados (sem dado, diz o que falta: "O Nelson não tem data no plano: não tenho o que confirmar.", "Não há data dita ao Giancarlo: …", d09 — material fora de "completo" não vira data firme), e registra pelo _agenda_cliente_registrar com origem dono (em ligado, sempre pedida: "Pronto para o Nelson, sai amanhã às 09:00: "…". Para mandar: *manda cliente Nelson*."; em teste, a sombra). A chave é a da rodada (a mesma mensagem não sai duas vezes: a que já existe é dita como está; a recusada antes ganha uma 2ª chance com :dono). p_firme (só pode_atrasar): a data firme do plano (variante remarcado) no lugar da faixa, só com o plano publicado. mudanca_no_dia não é pela ferramenta (sai sozinha). modo_cliente desligado = recusa. Admin pelo _autor_da_agenda. {ok, status, texto, mensagem_id, estado, modo, enviar_em} ou a recusa {ok:false, motivo, pergunta, texto}. CORREÇÃO FASE 5 (C2): (item 7) p_firme grava firme_do_dono em p_dados (a revalidação não aplica o passo do material a ela); (item 6) a forma fim com o mesmo início que o cliente ouviu; (item 15) o texto da preparada e o da que já existe sem artigo antes do nome. FASE 6 (P7, spec-fase6 §6.4): as recusas sem artigo antes do nome e sem "ele" ("Nelson não tem telefone no cadastro: …", "Não há data dita para Giancarlo: … Se você disse uma data, me conte …", "O plano de Nelson ainda cabe na data dita (qui 05/11): …"); a preparada e a que já existe passam pelo ralo (_agenda_cliente_sem_artigo, que agora tira também o "ele"). CORREÇÃO FASE 6 (C2, texto 6): a forma fim cujo fim novo não passa do dia que o cliente ouviu diz "Não preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar.", e não o texto técnico do erro.';

-- _agenda_ver_aprendizado (de 20261029100800_agenda_fase6_leituras.sql)
create or replace function public._agenda_ver_aprendizado(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_uid    uuid := auth.uid();
  v_papel  text;
  c        public.agenda_config;
  v_linhas jsonb;
  v_blocos jsonb;
  v_max    int;
  v_cab    text;
  v_corpo  text[];
  v_fecho  text[];
  v_t      text;
  k        int;
  b        record;
  v_tot    int;
  v_val    int;
  v_inv    jsonb;
  v_motivos text;
  v_audio  int;
  v_naoent int;
begin
  if p_hoje is null then
    raise exception '_agenda_ver_aprendizado: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (o mesmo de agenda_fator_de_campo).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  c := public._agenda_cfg();

  -- As linhas, na ordem de cada bloco. Desligado: nenhuma (a rodada só mede; o que ficou gravado de antes não vale).
  with a as (
    select x.item, x.chave, x.nivel, x.estado, x.n, x.n_min, x.calculado, x.em_uso, x.texto, x.detalhe ->> 'nome' as nome,
           case x.item when 'fator' then 1 when 'presenca' then 2 when 'fornecedor_atraso' then 3 when 'fornecedor_prazo' then 3
                       when 'capacidade_dono' then 4 when 'mo' then 5 when 'cliente_pontualidade' then 6 when 'aviso_folga' then 6
                       when 'carga' then 7 when 'solver' then 7 end as bloco,
           case x.item when 'fornecedor_atraso' then 1 when 'fornecedor_prazo' then 2 when 'cliente_pontualidade' then 1
                       when 'aviso_folga' then 2 when 'carga' then 1 when 'solver' then 2 else 1 end as ir,
           case x.estado when 'pergunta' then 1 when 'em_uso' then 2 when 'travado' then 3 when 'sombra' then 4 else 5 end as er,
           case x.nivel when 'fina' then 1 when 'sistema' then 2 when 'bem' then 3 when 'todas' then 4 else 5 end as nr
      from public.agenda_aprendizado x
     where c.modo_aprendizado <> 'desligado' and nullif(btrim(x.texto), '') is not null
  ),
  f as (
    select a.* from a
     where not (a.item in ('fator', 'presenca') and (
             -- a chave ainda medindo só aparece como "as OS" (todas), e só enquanto nenhuma do item chegou ao mínimo
             (a.estado = 'medindo' and (a.nivel <> 'todas' or exists (select 1 from a o where o.item = a.item and o.estado <> 'medindo')))
             -- a mais larga que repete uma mais fina do mesmo item (a mesma amostra: o mesmo n, o mesmo medido, o mesmo estado)
             or exists (select 1 from a o
                         where o.item = a.item and o.nr < a.nr and o.n = a.n and o.estado = a.estado
                           and o.calculado is not distinct from a.calculado
                           and (a.nivel = 'todas'
                                or (a.nivel = 'sistema' and o.nivel = 'fina' and split_part(o.chave, ':', 2) = split_part(a.chave, ':', 2))
                                or (a.nivel = 'bem' and o.nivel = 'fina' and split_part(o.chave, ':', 1) = split_part(a.chave, ':', 2))))))
  ),
  -- o fator sem nenhuma linha ainda (a 1ª rodada não rodou ou não há OS concluída): "As OS: 0 de 6 OS medidas; …"
  vazio as (
    select 'fator'::text as item, 'todas'::text as chave, 'todas'::text as nivel, 'medindo'::text as estado, 0 as n,
           c.fator_n_min::int as n_min, null::numeric as calculado, null::numeric as em_uso,
           public._agenda_aprendizado_texto('fator', 'foco_medindo',
             jsonb_build_object('chave', 'todas', 'n', 0, 'n_min', c.fator_n_min, 'padrao', c.estouro_fator)) as texto,
           null::text as nome, 1 as bloco, 1 as ir, 5 as er, 4 as nr
     where c.modo_aprendizado <> 'desligado' and not exists (select 1 from a where a.item = 'fator')
  ),
  t as (select * from f union all select * from vazio)
  select coalesce(jsonb_agg(jsonb_build_object(
           'bloco', t.bloco, 'item', t.item, 'chave', t.chave, 'nivel', t.nivel, 'estado', t.estado, 'n', t.n, 'n_min', t.n_min,
           'calculado', t.calculado, 'em_uso', t.em_uso, 'texto', t.texto)
           order by t.bloco, case when t.bloco in (6, 7) then t.ir else 0 end, t.er, t.nr, t.n desc, t.nome nulls last, t.ir,
                    t.chave), '[]'::jsonb)
    into v_linhas
    from t;

  -- As medidas: quantas OS concluídas foram medidas, quantas valem e por que as outras não.
  select count(*)::int, count(*) filter (where m.valida)::int into v_tot, v_val from public.agenda_medidas_os m;
  select coalesce(jsonb_object_agg(x.motivo, x.n), '{}'::jsonb),
         string_agg(case x.motivo
                      when 'sem_inicio' then format('%s sem check-in', x.n)
                      when 'sem_dias_no_inicio' then format('%s sem os dias ditos no início', x.n)
                      when 'dias_sugeridos' then format('%s com os dias só estimados por mim', x.n)
                      when 'sem_plano' then format('%s sem plano nem diária', x.n)
                      when 'conferencia_incompleta' then format('%s sem conferência completa', x.n)
                      when 'sem_diaria' then format('%s sem diária ligada', x.n)
                      when 'reaberta' then public._agenda_plural(x.n, 'reaberta', 'reabertas')
                      -- CORREÇÃO FASE 6: (C2) sobra (b) da C1: o motivo sem_fim (a OS concluída sem check-out e sem a
                      -- conclusão pela porta) tem o rótulo dele, e não "por outro motivo"
                      when 'sem_fim' then format('%s sem a conclusão registrada', x.n)
                      -- CORREÇÃO FASE 6: fim
                      else format('%s por outro motivo', x.n) end,
                    '; ' order by x.n desc, x.o)
    into v_inv, v_motivos
    from (select m.motivo, count(*)::int as n,
                 array_position(array['sem_inicio', 'sem_dias_no_inicio', 'dias_sugeridos', 'sem_plano', 'conferencia_incompleta',
                                      'sem_diaria', 'reaberta'], m.motivo) as o
            from public.agenda_medidas_os m where not m.valida group by m.motivo) x;

  -- As respostas de cliente que foram ao dono por áudio ou sem a agenda entender, nos últimos 30 dias (d8: só a contagem).
  select count(*) filter (where r.intencao = 'audio')::int, count(*) filter (where r.intencao = 'outro')::int
    into v_audio, v_naoent
    from public.agenda_cliente_respostas r
   where r.efeito = 'ao_dono' and (r.recebida_em at time zone 'America/Sao_Paulo')::date between p_hoje - 29 and p_hoje;

  v_fecho := array[
    case when v_tot = 0 then 'Medidas: nenhuma OS concluída medida ainda.'
         else format('Medidas: %s OS (%s%s).', v_tot,
                     case when v_val = v_tot and v_tot > 1 then 'todas valem' when v_val = 0 then 'nenhuma vale'
                          when v_val = 1 then '1 vale' else v_val || ' valem' end,
                     coalesce('; ' || v_motivos, '')) end,
    format('Respostas de cliente que foram a você por áudio: %s em 30 dias%s.',
           case when v_audio = 0 then 'nenhuma' else v_audio::text end,
           case when v_naoent > 0 then format('; sem eu entender: %s', v_naoent) else '' end)];

  v_cab := case c.modo_aprendizado
    when 'desligado' then 'O aprendizado está desligado: meço as OS concluídas, mas não calculo nem uso nada.'
    when 'sombra' then 'O que a agenda aprendeu com o que aconteceu (em teste: nada disto muda o plano ainda):'
    else 'O que a agenda aprendeu com o que aconteceu:' end;

  -- Os blocos: as linhas de cada um e quantas são.
  select coalesce(jsonb_agg(jsonb_build_object('bloco', x.bloco, 'nome', x.nome, 'linhas', x.linhas) order by x.bloco), '[]'::jsonb)
    into v_blocos
    from (select (l ->> 'bloco')::int as bloco,
                 (array['fator', 'presenca', 'fornecedor', 'capacidade', 'mo', 'cliente', 'revisao'])[(l ->> 'bloco')::int] as nome,
                 jsonb_agg(l - 'bloco' order by o) as linhas
            from jsonb_array_elements(v_linhas) with ordinality e(l, o)
           group by 1) x;

  -- Cabe no teto: cada bloco mostra as k primeiras e "• e mais N"; o fecho fica sempre.
  v_max := coalesce((select max(jsonb_array_length(x -> 'linhas')) from jsonb_array_elements(v_blocos) x), 0);
  for k in reverse v_max .. 0 loop
    v_corpo := array[v_cab];
    for b in select x -> 'linhas' as linhas from jsonb_array_elements(v_blocos) with ordinality e(x, o) order by o loop
      v_corpo := v_corpo
        || array(select '• ' || (l ->> 'texto') from jsonb_array_elements(b.linhas) with ordinality y(l, o)
                  where o <= greatest(k, 1) order by o)
        || case when jsonb_array_length(b.linhas) > greatest(k, 1)
                then array[format('• e mais %s', jsonb_array_length(b.linhas) - greatest(k, 1))] else '{}'::text[] end;
    end loop;
    v_t := public._agenda_juntar(v_corpo || v_fecho, null);
    exit when char_length(v_t) <= c.texto_max or k <= 1;
  end loop;
  if char_length(v_t) > c.texto_max then
    -- nem com uma linha por bloco: o corpo encurta pelo fim ("(e mais N linhas)") e o fecho fica
    v_t := public._agenda_juntar(v_corpo, greatest(c.texto_max - char_length(public._agenda_juntar(v_fecho, null)) - 1, 1))
           || E'\n' || public._agenda_juntar(v_fecho, null);
  end if;

  -- CORREÇÃO FASE 6: (C2) itens 10 e 12. (item 12) a janela das respostas por áudio é agenda_config.aprender_respostas_dias
  -- (eram os 30 dias escritos acima): a contagem e a 2ª frase do fecho, refeitas. (item 10) quando o foco inteiro não cabe em
  -- texto_max, o corte não some com as perguntas abertas: tira primeiro, de cada bloco, as linhas depois da 1ª — as em teste
  -- e medindo antes das em uso e das travadas, do último bloco para o 1º e de baixo para cima —, cada bloco com "• e mais N"
  -- no lugar do que saiu; só então a 1ª linha de cada bloco, na mesma ordem (o bloco que sai inteiro vai à conta "(e mais N
  -- linhas)" do fim do corpo). A pergunta nunca sai por este corte. Se nem só as perguntas couberem, elas vêm primeiro e o
  -- corpo encurta pelo fim (o fecho fica). Cabendo tudo, o texto é o de cima, byte a byte (com o fecho de agora). O return de
  -- baixo não roda mais.
  declare
    v_l  jsonb;
    v_nt int;
    d    int;
    v_c  text[];
    v_fe text;
  begin
    select count(*) filter (where r.intencao = 'audio')::int, count(*) filter (where r.intencao = 'outro')::int
      into v_audio, v_naoent
      from public.agenda_cliente_respostas r
     where r.efeito = 'ao_dono'
       and (r.recebida_em at time zone 'America/Sao_Paulo')::date between p_hoje - (c.aprender_respostas_dias - 1) and p_hoje;
    v_fecho[2] := format('Respostas de cliente que foram a você por áudio: %s em %s dias%s.',
                         case when v_audio = 0 then 'nenhuma' else v_audio::text end, c.aprender_respostas_dias,
                         case when v_naoent > 0 then format('; sem eu entender: %s', v_naoent) else '' end);
    -- as linhas na ordem dos blocos, com a ordem de corte (r): primeiro as que não são a 1ª do bloco, depois as 1ªs; em cada
    -- uma, as em teste e medindo antes das em uso e das travadas, do último bloco para o 1º e de baixo para cima; a pergunta
    -- fica sem r (não sai por aqui)
    select coalesce(jsonb_agg(jsonb_build_object('b', y.bo, 'o', y.lo, 'p', y.e = 'pergunta', 't', y.t,
                                                 'r', case when y.e <> 'pergunta' then y.r end) order by y.bo, y.lo), '[]'::jsonb)
      into v_l
      from (select x.bo, x.lo, x.e, x.t,
                   row_number() over (partition by x.e = 'pergunta'
                                      order by (x.lo = 1), (x.e in ('sombra', 'medindo')) desc, x.bo desc, x.lo desc) as r
              from (select eb.bo, el.lo, el.v ->> 'estado' as e, el.v ->> 'texto' as t
                      from jsonb_array_elements(v_blocos) with ordinality eb(b, bo),
                           jsonb_array_elements(eb.b -> 'linhas') with ordinality el(v, lo)) x) y;
    v_nt := (select count(*) from jsonb_array_elements(v_l) z where z ->> 'r' is not null);
    for d in 0 .. v_nt loop
      v_c := array[v_cab] || array(
        select q.t
          from (select (z ->> 'b')::int as b, 0 as k, (z ->> 'o')::int as o, '• ' || (z ->> 't') as t
                  from jsonb_array_elements(v_l) z
                 where z ->> 'r' is null or (z ->> 'r')::int > d
                union all
                -- o bloco que ficou com alguma linha: "• e mais N" no fim dele
                select g.b, 1, 0, format('• e mais %s', g.fora)
                  from (select (z ->> 'b')::int as b,
                               count(*) filter (where (z ->> 'r')::int <= d) as fora,
                               count(*) filter (where z ->> 'r' is null or (z ->> 'r')::int > d) as ficam
                          from jsonb_array_elements(v_l) z
                         group by 1) g
                 where g.fora > 0 and g.ficam > 0) q
         order by q.b, q.k, q.o)
        -- os blocos que saíram inteiros: uma conta só, no fim do corpo
        || coalesce((select array[format('(e mais %s %s)', sum(g.fora), case when sum(g.fora) = 1 then 'linha' else 'linhas' end)]
                       from (select (z ->> 'b')::int as b,
                                    count(*) filter (where (z ->> 'r')::int <= d) as fora,
                                    count(*) filter (where z ->> 'r' is null or (z ->> 'r')::int > d) as ficam
                               from jsonb_array_elements(v_l) z
                              group by 1) g
                      where g.fora > 0 and g.ficam = 0
                     having count(*) > 0), '{}'::text[]);
      v_t := public._agenda_juntar(v_c || v_fecho, null);
      exit when char_length(v_t) <= c.texto_max;
    end loop;
    if char_length(v_t) > c.texto_max then
      v_fe := public._agenda_juntar(v_fecho, null);
      v_c := array[v_cab] || array(select '• ' || (z ->> 't') from jsonb_array_elements(v_l) z
                                    where (z ->> 'p')::boolean order by (z ->> 'b')::int, (z ->> 'o')::int);
      v_t := public._agenda_juntar(v_c, greatest(c.texto_max - char_length(v_fe) - 1, 1)) || E'\n' || v_fe;
    end if;
  end;
  return jsonb_build_object('ok', true, 'texto', v_t,
    'dados', jsonb_build_object(
      'modo', c.modo_aprendizado, 'ligados', to_jsonb(c.aprendizado_ligados), 'blocos', v_blocos,
      'medidas', jsonb_build_object('total', v_tot, 'validas', v_val, 'invalidas', v_inv),
      'respostas_ao_dono', jsonb_build_object('audio', v_audio, 'nao_entendidas', v_naoent, 'dias', c.aprender_respostas_dias)));
  -- CORREÇÃO FASE 6: fim
  return jsonb_build_object('ok', true, 'texto', v_t,
    'dados', jsonb_build_object(
      'modo', c.modo_aprendizado, 'ligados', to_jsonb(c.aprendizado_ligados), 'blocos', v_blocos,
      'medidas', jsonb_build_object('total', v_tot, 'validas', v_val, 'invalidas', v_inv),
      'respostas_ao_dono', jsonb_build_object('audio', v_audio, 'nao_entendidas', v_naoent, 'dias', 30)));
end;
$function$;

comment on function public._agenda_ver_aprendizado(date) is
  'Agenda de Produção (Fase 6, P8): agenda_ver foco aprendizado (spec-fase6 §5.8 e §6.2) — o que a agenda aprendeu, em 7 blocos (fator de campo por tipo de OS, presença do dono, fornecedores, capacidade do dono, R$ por diária, cliente, revisão da carga), uma linha por item e chave com o texto que a rodada do dia gravou em agenda_aprendizado.texto (nada é calculado aqui). O fator e a presença não repetem a chave mais larga que diz o mesmo que a mais fina (o mesmo n, medido e estado) e só mostram as que ainda medem como "as OS" enquanto nenhuma chegou ao mínimo; sem nenhuma linha do fator, "As OS: 0 de 6 OS medidas; …". Fecha com "Medidas: N OS (M valem; …)" e "Respostas de cliente que foram a você por áudio: N em 30 dias[; sem eu entender: K]." (d8). Desligado: só o cabeçalho e o fecho. Até texto_max: as linhas de cada bloco saem do fim ("• e mais N"), o fecho fica. {ok, texto, dados {modo, ligados, blocos [{bloco, nome, linhas [{item, chave, nivel, estado, n, n_min, calculado, em_uso, texto}]}], medidas {total, validas, invalidas}, respostas_ao_dono {audio, nao_entendidas, dias}}}. Invoker e STABLE: com login, só administrador e financeiro (senão 42501); sem login, só o service_role. CORREÇÃO FASE 6 (C2): (item 10) quando não cabe, o corte tira primeiro as linhas em teste e medindo, depois as em uso e as travadas, e nunca a pergunta (se nem só as perguntas couberem, elas vêm primeiro); (item 12) a janela das respostas por áudio é aprender_respostas_dias; (sobra b da C1) o motivo sem_fim tem o rótulo "sem a conclusão registrada".';

-- agenda_saude (de 20261029100600_agenda_fase6_rodada.sql)
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
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias.';

-- os_plano_da_os (de 20261029100900_agenda_fase6_correcao_calculo.sql)
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

  return jsonb_build_object(
    -- FASE 5: o bloco "Cliente" do cartão (o que foi dito, a confirmação, as mensagens desta OS e o que espera você;
    -- _agenda_cliente_da_os). null sem o cliente.
    'cliente', public._agenda_cliente_da_os(p_os, p_hoje),
    -- FASE 5: fim
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
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 6 (P8): duracao.campo = a linha do fator de campo da classe da OS (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).") — nula com modo_aprendizado desligado e na OS concluída, faturada ou cancelada; presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em motorhome"; nulo sem ela), e o texto "Você fica o tempo todo (pelo que medi: …)". CORREÇÃO FASE 6 (C1, item 3): com a presença guardada na 1ª publicação, o texto diz "(pelo que medi quando planejei: …)". CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501.';

-- _agenda_ver_compras (de 20261029100300_agenda_fase6_fornecedor.sql)
create or replace function public._agenda_ver_compras(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid    uuid := (select auth.uid());
  c        public.agenda_config;
  v_pn     jsonb;
  e        jsonb;
  v_p      jsonb;
  v_esp    jsonb;
  v_ep     jsonb;
  v_linha  text;
  v_itens  text[] := '{}';
  v_cauda  text[] := '{}';
  v_prio   int[] := '{}';
  v_resto  text[];
  v_corte  int;
  v_cab    text;
  v_fora   int := 0;
  v_rem    text[];
  v_nrem   int;
  v_msgs   text[];
  v_prec   jsonb;
  v_linhas text[];
  v_n      int;
  k        int;
  v_t      text;
  v_rot    text;
  -- FASE 6: as linhas do que a agenda mediu dos fornecedores
  v_forn   text[];
  -- FASE 6: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_compras: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
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
        raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
      end if;
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
  c := public._agenda_cfg();
  v_esp := public.agenda_espera_de_peca(null, p_hoje);

  if p_os is not null then
    v_p := public.os_prontidao(p_os, p_hoje);
    if not coalesce((v_p ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
    end if;
    v_rot := public._agenda_rotulo(jsonb_build_object('curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero'), 'num');
    select x into v_ep from jsonb_array_elements(v_esp -> 'os') x where (x ->> 'service_order_id')::uuid = p_os;
    v_cab := coalesce(v_ep ->> 'texto', v_rot || ': sem material registrado para comprar.');
    -- o material que falta ou vem (o de tudo na mão já está na frase da espera)
    v_linha := public._agenda_compras_da_os(v_p, v_ep, p_hoje);
    if v_linha is not null and not coalesce((v_ep ->> 'material_na_mao')::boolean, false) then
      v_itens := v_itens || ('• Material: ' || v_linha);
    end if;
    v_msgs := array(select '• Ao fornecedor' || case when x.modo = 'sombra' then ' (em teste): ' else ': ' end
                           || public._agenda_fornecedor_frase(x.id, p_hoje) || '.'
                      from public.agenda_fornecedor_mensagens x
                     where x.service_order_id = p_os
                       and (x.enviar_em at time zone 'America/Sao_Paulo')::date between p_hoje - 6 and p_hoje + 7
                     order by x.enviar_em, x.terco, x.id
                     limit 3);
    v_linhas := array[v_cab] || v_itens || v_msgs;
    return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
      'dados', jsonb_build_object('numero', v_p ->> 'numero', 'espera', v_ep, 'material', v_p -> 'material'));
  end if;

  -- (1) os serviços da fila: o que falta e o que vem; os de material na mão parados
  v_pn := public._agenda_painel(p_hoje);
  for e in select x from jsonb_array_elements(v_pn -> 'oss') x
            where not coalesce((x ->> 'eh_orc')::boolean, false)
            order by (x ->> 'ordem')::int loop
    if not coalesce((e ->> 'executavel')::boolean, false) then
      if e ->> 'mat_estado' <> 'completo' then v_fora := v_fora + 1; end if;
      continue;
    end if;
    select x into v_ep from jsonb_array_elements(v_esp -> 'os') x where (x ->> 'service_order_id')::uuid = (e ->> 'os')::uuid;
    continue when e ->> 'mat_estado' = 'completo' and v_ep is null;
    v_linha := public._agenda_compras_da_os(e -> 'p', v_ep, p_hoje);
    continue when v_linha is null;
    v_itens := v_itens || ('• ' || public._agenda_rotulo(e, 'num') || ': ' || v_linha);
  end loop;
  v_cab := format('Compras (%s):', public._dia_curto(p_hoje));
  if cardinality(v_itens) = 0 then
    v_cab := v_cab || ' nada a comprar para os serviços da fila.';
  end if;
  -- A cauda, com o peso de cada linha para caber no teto (maior = sai por último): as notas 5, o tempo até comprar 4, a
  -- pergunta ao fornecedor 3, o parado no cliente 2, o detector 1.
  if v_fora > 0 then
    v_cauda := v_cauda || case when v_fora = 1 then 'Não conto 1 parado no cliente.'
                               else format('Não conto %s parados no cliente.', v_fora) end;
    v_prio := v_prio || 2;
  end if;

  -- (2) as notas que chegaram por e-mail sem a palavra do dono (a mais antiga primeiro; até 3)
  select array_agg(t.txt order by t.d, t.id), count(*) into v_rem, v_nrem
    from (select r.id, r.despacho_em as d,
                 public._agenda_remessa_nota(r.id) || ' (' || public._dia_curto(r.despacho_em) || ')' as txt
            from public.material_remessas r
           where r.vinculo = 'sem_resposta' and r.estado <> 'descartada') t;
  if v_nrem = 1 then
    v_cauda := v_cauda || format('Não sei de qual serviço é a %s: me diga, ou se não é de serviço.', v_rem[1]);
    v_prio := v_prio || 5;
  elsif v_nrem > 1 then
    v_cauda := v_cauda || format('Não sei de qual serviço são: %s. Me diga, ou se não são de serviço.', public._agenda_lista(v_rem, 3));
    v_prio := v_prio || 5;
  end if;

  -- (3) o tempo até comprar
  if nullif(v_esp ->> 'texto', '') is not null then
    v_cauda := v_cauda || (v_esp ->> 'texto');
    v_prio := v_prio || 4;
  end if;

  -- (4) a pergunta ao fornecedor da semana (a de 7 dias para trás até 7 para frente; até 3)
  v_msgs := array(select 'Ao fornecedor' || case when x.modo = 'sombra' then ' (em teste): ' else ': ' end
                         || public._agenda_fornecedor_frase(x.id, p_hoje) || '.'
                    from public.agenda_fornecedor_mensagens x
                   where (x.enviar_em at time zone 'America/Sao_Paulo')::date between p_hoje - 6 and p_hoje + 7
                   order by x.enviar_em, x.terco, x.id
                   limit 3);
  if cardinality(v_msgs) = 0 and c.modo_fornecedor <> 'desligado' then
    v_msgs := array['Ao fornecedor' || case when c.modo_fornecedor = 'sombra' then ' (em teste)' else '' end
                    || ': nenhuma pergunta nesta semana.'];
  end if;
  if cardinality(v_msgs) > 0 then
    v_cauda := v_cauda || v_msgs;
    v_prio := v_prio || array_fill(3, array[cardinality(v_msgs)]);
  end if;

  -- (5) o detector em teste: o que ele leu das conversas do fornecedor em 14 dias e quanto acertou
  if c.modo_detector = 'sombra' then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
    v_cauda := v_cauda || ('Leitura das conversas (em teste): '
      || case when coalesce((v_prec ->> 'mensagens')::int, 0) = 0
              then 'nenhuma mensagem de fornecedor com prazo em 14 dias.'
              else format('li %s de fornecedor com prazo em 14 dias: %s.',
                          public._agenda_plural((v_prec ->> 'mensagens')::int, 'mensagem', 'mensagens'),
                          case when coalesce((v_prec ->> 'julgados')::int, 0) = 0 then 'nenhuma deu para conferir ainda'
                               else format('acertei %s de %s que deu para conferir', v_prec ->> 'certos', v_prec ->> 'julgados') end) end
      || case when coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false) then ' Já dá para ligar, com o seu OK.' else '' end);
    v_prio := v_prio || 1;
  end if;

  -- FASE 6: (P3) (6) o que a agenda mediu das entregas de cada fornecedor (spec-fase6 §5.3): a linha do foco do aprendizado
  -- ("Kamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis (em teste)." / "Correa: 4 de 5 entregas medidas."),
  -- o atraso e o prazo da nota, os de mais medidas primeiro (até 3); peso 1 (sai primeiro, com o detector). Com o
  -- aprendizado desligado, o foco de antes, byte a byte.
  if c.modo_aprendizado <> 'desligado' then
    v_forn := array(select a.texto
                      from public.agenda_aprendizado a
                     where a.item in ('fornecedor_atraso', 'fornecedor_prazo') and a.texto is not null
                     order by a.estado = 'medindo', a.n desc, a.detalhe ->> 'nome', a.item, a.chave
                     limit 3);
    if cardinality(v_forn) > 0 then
      v_cauda := v_cauda || v_forn;
      v_prio := v_prio || array_fill(1, array[cardinality(v_forn)]);
    end if;
  end if;
  -- FASE 6: fim
  -- Cabe no teto: primeiro saem da cauda o detector e o parado no cliente; depois os serviços do fim ("• e mais N", nunca no
  -- meio de uma linha); só então, se nem assim couber, as outras linhas da cauda (a pergunta ao fornecedor, o tempo, as notas).
  v_n := cardinality(v_itens);
  <<cabe>>
  for v_corte in 0 .. 5 loop
    v_resto := array(select t.l from unnest(v_cauda, v_prio) with ordinality t(l, p, o) where t.p > v_corte order by t.o);
    for k in reverse v_n .. case when v_corte < 2 then v_n else 0 end loop
      v_linhas := array[v_cab] || v_itens[1:k]
                  || case when k < v_n then array[format('• e mais %s', v_n - k)] else '{}'::text[] end
                  || v_resto;
      v_t := public._agenda_juntar(v_linhas, null);
      exit cabe when char_length(v_t) <= c.texto_max;
    end loop;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
    'dados', jsonb_build_object('servicos', v_n, 'notas_sem_resposta', coalesce(v_nrem, 0),
                                'mediana_ate_comprar_90d', v_esp -> 'mediana_ate_comprar_90d',
                                'modos', jsonb_build_object('material', c.modo_material, 'detector', c.modo_detector,
                                                            'fornecedor', c.modo_fornecedor)));
end;
$function$;

comment on function public._agenda_ver_compras(uuid, date) is
  'Agenda de Produção (Fase 4, P6): agenda_ver foco compras. Sem OS, até texto_max: "Compras (sex 30/10):", uma linha por serviço da fila (sem orçamento) com material fora de A (_agenda_compras_da_os: o que falta, "nada comprado desde a aprovação", "Compre até … para começar …", o que vem e de onde, "de quem e quando?") e os de material na mão parados; "Não conto N parados no cliente."; as notas sem a palavra do dono ("Não sei de qual serviço é a nota 812 da Correa (qui 29/10): …"); o tempo até comprar (agenda_espera_de_peca); a pergunta ao fornecedor da semana (_agenda_fornecedor_frase; sombra "Ao fornecedor (em teste): eu teria perguntado …"); em sombra do detector, "Leitura das conversas (em teste): …" (agenda_detector_precisao). Com OS (também a concluída): a frase da espera (os 3 componentes), "• Material: …" e as perguntas ao fornecedor dela. Os serviços saem do fim com "• e mais N"; o resto, pela linha. Definer (lê a fila do WhatsApp e as perguntas ao fornecedor por inteiro): com login, só administrador e financeiro (senão 42501). {ok, texto, dados}. FASE 6 (P3): sem OS e com o aprendizado fora de desligado, até 3 linhas do que a agenda mediu de cada fornecedor (o atraso das entregas e o prazo da nota: a linha de agenda_aprendizado.texto), peso 1 na cauda. CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501.';

-- _agenda_ver_fornecedores (de 20261029100800_agenda_fase6_leituras.sql)
create or replace function public._agenda_ver_fornecedores(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid     uuid := (select auth.uid());
  c         public.agenda_config;
  c_ordem   constant text[] := array['balcao', 'entrega_local', 'distribuidor_sc_pr', 'outro_estado', 'marketplace', 'importacao'];
  r         record;
  v_id      uuid;
  v_pr      jsonb;
  v_lista   jsonb := '[]'::jsonb;
  v_vistos  uuid[] := '{}';
  v_grupos  text[] := '{}';
  v_disse   text[];
  v_chute   text[];
  v_falta   text[] := '{}';
  g         record;
  v_ex      text[];
  v_cab     text;
  v_pe      text;
  v_linhas  text[];
  v_n       int;
  k         int;
  v_t       text;
  -- FASE 6: (P8) o prazo medido em uso (fonte medido)
  v_medido  text[];
  -- FASE 6: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_fornecedores: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
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
        raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
      end if;
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
  c := public._agenda_cfg();

  for r in
    select x.id, max(x.contas) as contas
      from (select p.fornecedor_id as id, p.contas from public._agenda_fornecedores_principais(p_hoje) p
            union all
            select m.fornecedor_id, 0
              from public.os_carteira(p_hoje) k
              join public.os_material m on m.service_order_id = k.service_order_id
             where m.fornecedor_id is not null and m.situacao in ('falta', 'comprado', 'a_caminho')) x
     group by x.id
     order by max(x.contas) desc, x.id
  loop
    v_id := r.id;
    v_pr := public._agenda_prazo_do_fornecedor(v_id);
    -- o cadastro que o dono já tirou de uso vale como o que ficou
    if not coalesce((select s.active from public.suppliers s where s.id = v_id), true) and v_pr ->> 'principal_id' is not null then
      v_id := (v_pr ->> 'principal_id')::uuid;
      v_pr := public._agenda_prazo_do_fornecedor(v_id);
    end if;
    continue when v_id = any (v_vistos);
    v_vistos := v_vistos || v_id;
    v_lista := v_lista || (jsonb_build_object(
      'fornecedor_id', v_id, 'nome', public._agenda_fornecedor_curto(v_id), 'contas', r.contas,
      'lugar', (select public._agenda_lugar_texto(s.city, s.state) from public.suppliers s where s.id = v_id),
      'sem_lugar_no_cadastro', (select nullif(btrim(coalesce(s.city, '')), '') is null and nullif(btrim(coalesce(s.state, '')), '') is null
                                  from public.suppliers s where s.id = v_id),
      'grupo', (select public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name)) from public.suppliers s where s.id = v_id),
      'frase', public._agenda_classe_texto(v_pr ->> 'classe', (v_pr ->> 'du')::int, (v_pr ->> 'corridos')::int))
      || v_pr);
  end loop;

  -- o rótulo: "Premel (Itajaí/SC)"; sem lugar, só o nome
  -- Você disse e o meu chute: uma linha por frase de prazo, na ordem das classes
  select array_agg(t.l order by t.o) into v_disse
    from (select '• ' || f.frase || ': ' || public._agenda_lista(array_agg(concat(f.nome, ' (' || f.lugar || ')') order by f.contas desc, f.nome), 6) || '.' as l,
                 min(array_position(c_ordem, f.classe)) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, contas int, classe text, fonte text, frase text)
           where f.fonte = 'dono' and f.classe is not null
           group by f.frase) t;
  select array_agg(t.l order by t.o, t.l) into v_chute
    from (select '• ' || f.frase || ': ' || public._agenda_lista(array_agg(concat(f.nome, ' (' || f.lugar || ')') order by f.contas desc, f.nome), 6) || '.' as l,
                 min(array_position(c_ordem, f.classe)) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, contas int, classe text, fonte text, frase text)
           where f.fonte in ('cidade', 'nome') and f.classe is not null
           group by f.frase) t;

  -- FASE 6: (P8) o prazo medido (spec-fase6 §5.3; o risco do P3): com fornecedor_prazo em uso (_agenda_prazo_do_fornecedor,
  -- fonte medido: só com o aprendizado ligado e fornecedor na lista), o fornecedor saía de "Você disse" e de "Meu chute" e
  -- sumia do foco. Agora vai a "Medido (pelas notas que chegaram):", com o texto do prazo ("outro estado, 6 dias úteis
  -- (medido em 5 notas)").
  select array_agg(t.l order by t.o, t.l) into v_medido
    from (select '• ' || concat(f.nome, ' (' || f.lugar || ')') || ': ' || f.texto || '.' as l,
                 array_position(c_ordem, f.classe) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, classe text, fonte text, texto text)
           where f.fonte = 'medido') t;
  -- FASE 6: fim
  -- Falta você dizer: sem lugar no cadastro; o cadastro repetido (uma linha por nome, com os lugares e o que vale)
  for r in select * from jsonb_to_recordset(v_lista) f(nome text, lugar text, classe text, duvida text, grupo text,
                                                        sem_lugar_no_cadastro boolean, principal_id uuid)
            order by f.nome loop
    if r.duvida = 'duplicado' then
      continue when r.grupo = any (v_grupos);
      v_grupos := v_grupos || r.grupo;
      -- os cadastros ativos do mesmo nome (o que vale primeiro) e o lugar do que vale
      select count(*) as n,
             public._agenda_lista(array_agg(coalesce(public._agenda_lugar_texto(s.city, s.state), 'sem cidade')
                                            order by (s.id = r.principal_id) desc, s.id), 4) as lugares
        into g
        from public.suppliers s
       where coalesce(s.active, true)
         and public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name)) = r.grupo;
      v_pe := (select public._agenda_lugar_texto(p.city, p.state) from public.suppliers p where p.id = r.principal_id);
      v_falta := v_falta || case when v_pe is not null
        then format('• %s: cadastrada %s vezes (%s); conto pela de %s. É a mesma?', r.nome, g.n, g.lugares, v_pe)
        else format('• %s: cadastrada %s vezes (%s) e não sei qual vale. Qual é a certa?', r.nome, g.n, g.lugares) end;
    elsif r.classe is null then
      v_falta := v_falta || case when r.sem_lugar_no_cadastro then format('• %s: sem cidade no cadastro.', r.nome)
                                 else format('• %s: não sei onde fica (%s).', r.nome, r.lugar) end;
    end if;
  end loop;

  -- como responder: com dois nomes da lista ("a Premel eu pego no balcão", "a Toli chega em 3 dias úteis")
  v_ex := array(select f.nome from jsonb_to_recordset(v_lista) f(nome text, contas int, classe text, fonte text)
                 where f.classe is not null and coalesce(f.fonte, '') <> 'dono'
                 order by array_position(c_ordem, f.classe), f.contas desc, f.nome limit 2);
  v_pe := case when cardinality(v_ex) = 2
               then format('Pode ser um áudio só: "a %s eu pego no balcão", "a %s chega em 3 dias úteis".', v_ex[1], v_ex[2])
               else 'Pode ser um áudio só, do seu jeito: "eu pego no balcão", "chega em 3 dias úteis".' end;

  v_cab := 'Como eu conto a chegada do material dos fornecedores principais:';
  if jsonb_array_length(v_lista) = 0 then
    return jsonb_build_object('ok', true,
      'texto', 'Ainda não tenho fornecedor principal: nenhuma conta de material no último ano nem compra a caminho.',
      'dados', jsonb_build_object('fornecedores', v_lista));
  end if;
  -- Cabe no teto: o chute sai do fim ("• e mais N"), nunca o que falta você dizer.
  v_n := coalesce(cardinality(v_chute), 0);
  for k in reverse v_n .. 0 loop
    v_linhas := array[v_cab]
                || case when coalesce(cardinality(v_disse), 0) = 0 then array['Você disse: nenhum ainda.']
                        else array['Você disse:'] || v_disse end
                -- FASE 6: (P8) o prazo medido, logo depois do que o dono disse (só aparece com fornecedor_prazo em uso)
                || case when coalesce(cardinality(v_medido), 0) > 0 then array['Medido (pelas notas que chegaram):'] || v_medido
                        else '{}'::text[] end
                -- FASE 6: fim
                || case when v_n > 0 then array['Meu chute (pela cidade ou pelo nome):'] || v_chute[1:k]
                                          || case when k < v_n then array[format('• e mais %s', v_n - k)] else '{}'::text[] end
                        else '{}'::text[] end
                || case when cardinality(v_falta) > 0 then array['Falta você dizer:'] || v_falta else '{}'::text[] end
                || array[v_pe];
    v_t := public._agenda_juntar(v_linhas, null);
    exit when char_length(v_t) <= c.texto_max;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
    'dados', jsonb_build_object('fornecedores', v_lista, 'disse', coalesce(cardinality(v_disse), 0), 'chute', v_n,
                                'falta', cardinality(v_falta)));
end;
$function$;

comment on function public._agenda_ver_fornecedores(date) is
  'Agenda de Produção (Fase 4, P6): agenda_ver foco fornecedores — como a agenda conta a chegada do material dos fornecedores principais (_agenda_fornecedores_principais) e dos das linhas da carteira ainda não na mão, pela fonte única (_agenda_prazo_do_fornecedor): "Você disse:" (suppliers.modalidade; vazio: "Você disse: nenhum ainda."), "Meu chute (pela cidade ou pelo nome):" uma linha por prazo ("• entrega local, 1 dia útil: Premel (Itajaí/SC) e Souper (Itajaí/SC)"), "Falta você dizer:" (sem cidade no cadastro; cadastro repetido: "• Kamell: cadastrada 2 vezes (Vila Velha/ES e Itajaí/SC); conto pela de Vila Velha/ES. É a mesma?") e "Pode ser um áudio só: …" com dois nomes da lista. O inativo vale como o que ficou. Até texto_max (o chute sai do fim com "• e mais N"). Definer (lê os principais, que são só do service_role): com login, só administrador e financeiro (senão 42501). {ok, texto, dados:{fornecedores, disse, chute, falta}}. FASE 6 (P8): o fornecedor com o prazo medido em uso (fonte medido de _agenda_prazo_do_fornecedor) vai ao grupo "Medido (pelas notas que chegaram):" ("• Kamell (Vila Velha/ES): outro estado, 6 dias úteis (medido em 5 notas)."), logo depois de "Você disse"; antes ele sumia do foco. Sem o medido em uso, o texto é o de antes. CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501.';

-- _agenda_atraso_do_fornecedor (de 20261029100300_agenda_fase6_fornecedor.sql)
create or replace function public._agenda_atraso_do_fornecedor(p_forn uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select jsonb_build_object('fornecedor_id', p_forn, 'nome', a.detalhe ->> 'nome', 'du', a.calculado, 'n', a.n, 'n_min', a.n_min,
                            'no_prazo', (a.detalhe ->> 'no_prazo')::int,
                            'em_uso', public._agenda_aprendido('fornecedor_atraso', p_forn::text),
                            'estado', a.estado, 'texto', a.texto)
    from public.agenda_aprendizado a
   where p_forn is not null and a.item = 'fornecedor_atraso' and a.chave = p_forn::text;
  -- CORREÇÃO FASE 6: (C2) sobra (a) da C1 (item 8): o select de cima não vale mais (a função sql devolve o resultado do
  -- último); vale este, que é ele lendo pela chave da medida (_agenda_fornecedor_da_medida: o cadastro inativo pelo
  -- principal, como a medição, a prontidão e o motor) — antes, a linha do atraso no foco compras lia pelo id cru e o inativo
  -- ficava sem ela. O fornecedor_id devolvido continua o que foi pedido.
  select jsonb_build_object('fornecedor_id', p_forn, 'nome', a.detalhe ->> 'nome', 'du', a.calculado, 'n', a.n, 'n_min', a.n_min,
                            'no_prazo', (a.detalhe ->> 'no_prazo')::int,
                            'em_uso', public._agenda_aprendido('fornecedor_atraso', public._agenda_fornecedor_da_medida(p_forn)::text),
                            'estado', a.estado, 'texto', a.texto)
    from public.agenda_aprendizado a
   where p_forn is not null and a.item = 'fornecedor_atraso' and a.chave = public._agenda_fornecedor_da_medida(p_forn)::text;
  -- CORREÇÃO FASE 6: fim
$function$;

comment on function public._agenda_atraso_do_fornecedor(uuid) is
  'Agenda de Produção (Fase 6, P3): o atraso medido de um fornecedor — {fornecedor_id, nome, du (o medido), n, n_min, no_prazo, em_uso (o que a prontidão soma à previsão do nível B: _agenda_aprendido, só com modo_aprendizado ligado e fornecedor na lista; nulo = nada), estado, texto (a linha do foco)}. Sem medida: nulo. Leitura invoker (a RLS de quem lê vale). CORREÇÃO FASE 6 (C2, sobra a da C1): lê pela chave da medida (_agenda_fornecedor_da_medida: o inativo pelo principal), como a medição.';

-- agenda_desfazer_pela_tela (de 20261026100600_agenda_fase3_telas.sql)
create or replace function public.agenda_desfazer_pela_tela(p_acao uuid, p_hoje date default public._hoje_brt(),
                                                            p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(null);
  v_a     public.agenda_acoes%rowtype;
  v_ids   uuid[];
  v_id    uuid;
  v_r     jsonb;
  v_txts  text[] := '{}';
  v_falha text;
begin
  if p_acao is null or p_hoje is null or p_agora is null then
    raise exception 'Falta a mudança para desfazer.' using errcode = '22023';
  end if;
  select * into v_a from public.agenda_acoes a where a.id = p_acao;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  -- A publicação da semana são várias ações: tudo ou nada, como o *desfaz semana*.
  if v_a.tipo = 'publicar' and v_a.proposta_id is not null then
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.proposta_id = v_a.proposta_id and a.executada and a.desfeita_em is null
                      and a.desfazivel_ate >= p_agora
                    order by a.criada_em, a.id);
    if cardinality(v_ids) = 0 then
      return jsonb_build_object('ok', false, 'mudou', false, 'texto', 'A publicação da semana não dá mais para desfazer.');
    end if;
  else
    v_ids := array[p_acao];
    -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: a linha do aprendizado no "o que mudou" é uma por item (o fator e a presença de
    -- várias classes juntas, _agenda_mudancas): o botão desfaz o item inteiro daquele instante — as ações aprendizado do mesmo
    -- item e do mesmo criada_em ainda desfazíveis (o fornecedor e os outros, só a chave dele), como *desfaz aprendizado
    -- <coisa>*. A ação que já não dá para desfazer segue sozinha (a recusa é a de agenda_desfazer).
    if v_a.tipo = 'aprendizado' and v_a.executada and v_a.desfeita_em is null and v_a.desfazivel_ate >= p_agora then
      v_ids := array(select a.id from public.agenda_acoes a
                      where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
                        and a.criada_em = v_a.criada_em and a.antes ->> 'item' = v_a.antes ->> 'item'
                        and (v_a.antes ->> 'item' in ('fator', 'presenca') or a.antes ->> 'chave' = v_a.antes ->> 'chave')
                      order by a.antes ->> 'chave', a.id);
      if cardinality(v_ids) = 0 then
        v_ids := array[p_acao];
      end if;
    end if;
    -- CORREÇÃO FASE 6: fim
  end if;
  begin
    foreach v_id in array v_ids loop
      v_r := public.agenda_desfazer(v_id, v_autor, 'tela', p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        v_falha := v_r ->> 'texto';
        raise exception using errcode = 'P0098', message = 'desfazer recusado';
      end if;
      v_txts := v_txts || (v_r ->> 'texto');
    end loop;
  exception when sqlstate 'P0098' then
    return jsonb_build_object('ok', false, 'mudou', false, 'texto', coalesce(v_falha, 'Não deu para desfazer.'));
  end;
  -- CORREÇÃO FASE 6: (C2) item 6: o item do aprendizado (várias classes de uma vez) não é a publicação da semana: os "Desfeito:
  -- …" um depois do outro
  if v_a.tipo = 'aprendizado' then
    return jsonb_build_object('ok', true, 'mudou', true, 'acoes', to_jsonb(v_ids), 'texto', array_to_string(v_txts, ' '));
  end if;
  -- CORREÇÃO FASE 6: fim
  return jsonb_build_object('ok', true, 'mudou', true, 'acoes', to_jsonb(v_ids),
    'texto', case when cardinality(v_txts) = 1 then v_txts[1]
                  else format('Desfiz a publicação da semana (%s): %s',
                              public._agenda_plural(cardinality(v_txts), 'mudança', 'mudanças'), array_to_string(v_txts, ' ')) end);
end;
$function$;

comment on function public.agenda_desfazer_pela_tela(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 3, P7a): o Desfazer da tela Semana — agenda_desfazer(ação, o administrador, via tela) (a conclusão, a entrega e a diária têm o desfazer delas); a publicação da semana desfaz todas as ações desfazíveis dela, tudo ou nada, como o *desfaz semana*. Só o administrador (_autor_da_agenda). {ok, mudou, acoes, texto}; recusado = {ok false, texto} e nada muda. CORREÇÃO FASE 6 (C2, item 6): a ação aprendizado desfaz o item inteiro daquele instante (as classes do fator e da presença juntas; o fornecedor e os outros, a chave), como a linha do "o que mudou"; o texto são os "Desfeito: …" em sequência.';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- Nenhuma função nova. As recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a
-- migration valer sozinha).
-- As leituras, os textos e o *desfaz* dito (authenticated e service_role; nunca anon).
revoke all on function
  public.agenda_desfazer_dito(uuid, text, text, date, timestamptz),
  public.agenda_acao_desfazivel(text, date, timestamptz),
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz),
  public._agenda_mudanca_texto(jsonb, boolean),
  public._agenda_aprendizado_texto(text, text, jsonb),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
  public._agenda_ver_aprendizado(date),
  public.agenda_saude(date, timestamptz),
  public.os_plano_da_os(uuid, date),
  public._agenda_ver_compras(uuid, date),
  public._agenda_ver_fornecedores(date),
  public._agenda_atraso_do_fornecedor(uuid)
  from public, anon;
grant execute on function
  public.agenda_desfazer_dito(uuid, text, text, date, timestamptz),
  public.agenda_acao_desfazivel(text, date, timestamptz),
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz),
  public._agenda_mudanca_texto(jsonb, boolean),
  public._agenda_aprendizado_texto(text, text, jsonb),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
  public._agenda_ver_aprendizado(date),
  public.agenda_saude(date, timestamptz),
  public.os_plano_da_os(uuid, date),
  public._agenda_ver_compras(uuid, date),
  public._agenda_ver_fornecedores(date),
  public._agenda_atraso_do_fornecedor(uuid)
  to authenticated, service_role;
-- O gravador do aprendizado: sem grant a ninguém (só as funções da rodada, que são definer, o chamam).
revoke all on function public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz)
  from public, anon, authenticated, service_role;
-- O desfazer pela tela: só authenticated (a tela; a regra de quem pode é a de agenda_desfazer).
revoke all on function public.agenda_desfazer_pela_tela(uuid, date, timestamptz) from public, anon;
grant execute on function public.agenda_desfazer_pela_tela(uuid, date, timestamptz) to authenticated;
