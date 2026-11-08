-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P7: as leituras — *agenda pendências* com o prazo de cada pergunta e o mesmo número de
-- sempre, a palavra *agenda espera <nome>* (a única saída de quem não quer o padrão: o *agenda fica* não existe) e a saúde da comunicação.
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§5.7, §6.2, §7, §8.3 agenda_fase7f_leituras.sql, §11 e o bloco R8, que vale sobre o corpo: R8.1, R8.2, R8.5-26, 28 e 29,
-- R8.6, R8.7, R8.8, R8.12, R8.13); nomes: fase7-registro.md §1 (7f P7); notas: notas-fase7f.md, seções P1 a P4 ("Para o P4 e o P7", "Para o P7 e o P8").
-- Respostas do dono que valem aqui (respostas/<id> da página Respostas do Diário, conferidas em 08/11): AG7-15 "Sim, sem resposta fica como ele propôs" (o silêncio decide;
-- mudar dia já dito ao cliente sempre espera o dono); AG7-24 "Até 5"; AG7-02 e AG7-37: a pergunta dos dias em campo continua como está (o *agenda espera* não a alcança).
-- Depende das Fases 1 a 6, do lote de 30/10, das etapas 7a a 7d e de 20261109100000 a 20261109100300 da 7f. NÃO depende da 7e.
--
-- ═══ SÓ FUNÇÕES — OK NOMEADO ═══ (2 funções novas, 3 recriadas e 1 grant; nenhuma tabela, nenhuma coluna, nenhuma lista, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p7/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA
-- (conferida a cada montagem), e a mudança está só nos blocos "-- FASE 7f: … -- FASE 7f: fim" (dentro do bloco do gestor da 7a, "-- (7f … -- (7f: fim)"). Tirados os blocos deste
-- pacote, o corpo é o da origem, byte a byte (o montador e o V0 de supabase/tests/agenda_fase7f_leituras.sql conferem).
--
-- POR QUE: o dono lê as perguntas no fechamento (P3) e na mensagem da quinta (P4) pela linha curta, com o número de agenda_decisoes_abertas. *agenda pendências* é para onde as duas
-- mandam: tem de mostrar as mesmas perguntas, com o mesmo número, o prazo de cada uma na mesma forma, e a saída de quem não quer o padrão. E a saúde precisa mostrar o que a
-- comunicação fez, para cada "OK ligar" ter o que medir antes.
--
-- O QUE MUDA:
--   1. _agenda_perguntas_antes (recriada, de 20261109100000): o prazo vai a nulo só na MESMA escrita que leva veto_espera de nulo a dono. Fora disso, nada muda no gatilho.
--   2. agenda_veto_dito (nova; só service_role): *agenda espera <nome>*. O nome pela régua do *desfaz* (a OS por agenda_resolver_os; sem OS, o fornecedor da pergunta). A 1ª pergunta
--      daquele nome, na ordem de agenda_perguntas_em_ordem, que ainda pode vencer, passa a esperar o dono: veto_espera = dono, veto_ate nulo. Nada mais a faz vencer: o prazo, o teto e o
--      registro do que foi mostrado leem _agenda_pergunta_espera primeiro. Nome que não casa = a lista das abertas com nome. A pergunta dos dias do dono (padrao_do_dono) fica de fora
--      (AG7-37). Só 'espera': *agenda fica* não existe (R8.5-28).
--   3. _agenda_ver_decisoes (recriada, de 20261107100860): o foco decisoes (*agenda pendências*). O prazo de cada pergunta, na forma curta da linha (a mesma do bloco e da quinta), só
--      onde ele vale de verdade; o número é o n de agenda_decisoes_abertas, que não é recriada nem reordenada; "Também quero saber" na ordem de agenda_perguntas_em_ordem
--      (a do bloco e da quinta), depois de quem tem opções; a conferencia, que não está nela, vem depois. Com algum prazo, a linha do *agenda espera*. Continua sem marcar nada como mostrado.
--   6. _agenda_titulo_da_pergunta (só a porta): grant a authenticated e service_role. O corte do foco a chama como invoker, e sem o grant *agenda pendências* acima das
--      1.800 letras dava "permission denied" (NOVO-agenda-121, a 7d em produção). É texto puro, imutável: o grant não abre dado. O anon continua fora.
--   4. _agenda_saude_comunicacao (nova): a saúde da comunicação — os 6 modos crus, a rodada comunicar, os zeros obrigatórios (§11: assumida sem prazo mostrado, assumida que esperava,
--      assumida de tipo que nunca vence, teto que passou sem motivo, bloco grande, exceção acima do teto) e os números: as perguntas, as exceções do dia (a acima da cota, em sombra o
--      que o lote levaria e guardaria), a quinta, o bloco nos fechamentos, as mensagens do dia por origem (aviso = agenda-dono, acorde = agenda: R8.5-29) e as falhas do lote.
--   5. agenda_saude (recriada, de 20261107100700): a chave comunicacao, com os zeros no ok; e o zero prazo_em_critica do gestor passa a ser o prazo em crítica que nunca venceria
--      (fora de veto_tipos ou com veto_espera): desde a 7f, a crítica pode ter prazo (AG7-15).
--
-- O QUE NÃO MUDA: agenda_decisoes_abertas, agenda_rascunho_aplicar, agenda_ver (o roteador) e as linhas do bloco e da quinta não são recriadas: o número de cada decisão é o de sempre.
-- Com modo_veto desligado ou em sombra, e com ele ligado com o freio (gestor_so_propor), nenhuma linha diz "Sem resposta até". O foco não marca nada como mostrado. Nada escreve em
-- agenda_disponibilidade. Não muda nada do que o retorno lê (pedidos-do-retorno.md, item 13): agenda_resolver_os só é chamada.
--
-- ORDEM DE LIGAR (spec R8.14): depois de 20261109100300 e junto do ai-agent e do erp-mcp do pacote (a palavra e o prompt). Aplicar sozinha não muda nada para ninguém: a palavra só
-- existe no TS, e sem ele agenda_veto_dito não tem chamador; antes da migration, a palavra responde que ainda não está ligada (PGRST202).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_leituras.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109100600
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261109100600_agenda_fase7f_leituras.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261109100600', 'agenda_fase7f_leituras');"
--
-- DESFAZER: reaplicar as definições de 20261109100000_agenda_fase7f_base.sql (_agenda_perguntas_antes), 20261107100860_agenda_fase7d_correcao3.sql (_agenda_ver_decisoes) e
-- 20261107100700_agenda_fase7d_leituras.sql (agenda_saude) e apagar as novas:
--   drop function if exists public.agenda_veto_dito(uuid, text, text, date, timestamptz), public._agenda_saude_comunicacao(date, timestamptz);
--   revoke execute on function public._agenda_titulo_da_pergunta(text) from authenticated, service_role;  (volta o defeito do corte, NOVO-agenda-121)
--   A pergunta que já espera o dono fica assim (veto_espera não volta a nulo): ela só deixa de vencer pelo prazo; o dono ainda responde pelo número.
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. O prazo vai a nulo só com o *agenda espera* ──────────────────────────────────────────────────
-- _agenda_perguntas_antes (de 20261109100000_agenda_fase7f_base.sql)
create or replace function public._agenda_perguntas_antes()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- (opções que não são lista: quem recusa é o CHECK da coluna)
  if jsonb_typeof(new.opcoes) = 'array' and jsonb_array_length(new.opcoes) > 0 then
    if new.recomendacao is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.recomendacao::text) then
      raise exception 'A recomendação tem de ser uma das opções da pergunta.';
    end if;
    if new.opcao_escolhida is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.opcao_escolhida::text) then
      raise exception 'Essa opção não existe nesta pergunta.';
    end if;
    -- FASE 7: a opção que vale sem resposta (AG7-15) também é uma das opções.
    if new.opcao_padrao is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.opcao_padrao::text) then
      raise exception 'A opção que vale sem resposta tem de ser uma das opções da pergunta.';
    end if;
    -- FASE 7: fim
  end if;
  if tg_op = 'UPDATE'
     and not public._agenda_so_mudou(to_jsonb(old) - 'critica', to_jsonb(new) - 'critica',
           case when old.estado = 'aberta'
                -- FASE 3: carona_em (a pergunta que foi junto de uma resposta) muda como o "mostrada".
                then array['estado', 'mostrada_vezes', 'mostrada_em', 'mostrada_via', 'respondida_em', 'respondida_por',
                           'respondida_via', 'opcao_escolhida', 'resposta', 'resolvida_motivo', 'expira_em', 'carona_em']
                     -- FASE 7: o prazo vai de nulo a um valor UMA vez, na pergunta aberta (quem mostra com o prazo escrito
                     -- grava: 7b e 7c); de um valor a outro, não (só o 7f, que recria esta função).
                     || case when old.veto_ate is null then array['veto_ate'] else '{}'::text[] end
                     -- FASE 7: fim
                     -- FASE 7f: (7f P1, §4.2, R2, R8.5-9) na aberta, o que o prazo e a ordem gravam. O prazo vai de um valor a outro só na pergunta que
                     -- nunca foi mostrada antes dele, na mesma escrita que a mostra depois dele: o dono está lendo o prazo novo, e o que ele já viu
                     -- com prazo nunca muda. veto_espera vai de nulo a dono (*agenda espera <nome>*) ou a sem_padrao (a recusa do prazo: a pergunta
                     -- fica aberta, sem prazo). padrao_*, e o veto_espera de um valor a outro, só com agenda.backfill_padrao, que só a migration liga.
                     || array['destrava', 'veto_teria_em', 'assumida_por', 'assumida_em']
                     || case when old.veto_ate is not null and new.veto_ate > old.veto_ate and new.mostrada_em > old.veto_ate
                                  and not coalesce(old.mostrada_vezes > 0 and old.mostrada_em < old.veto_ate, false)
                             then array['veto_ate'] else '{}'::text[] end
                     || case when old.veto_espera is null and new.veto_espera in ('dono', 'sem_padrao')
                             then array['veto_espera'] else '{}'::text[] end
                     || case when coalesce(current_setting('agenda.backfill_padrao', true), '') = 'on'
                             then array['padrao_chave', 'padrao_efeito', 'veto_espera'] else '{}'::text[] end
                     -- FASE 7f: fim
                     -- FASE 7f: (7f P7, §5.7) *agenda espera <nome>*: o prazo vai a nulo só na MESMA escrita que leva veto_espera de nulo a dono (agenda_veto_dito): a pergunta
                     -- passa a esperar o dono, sem prazo, e nada mais a faz vencer. Fora disso, o prazo nunca volta a nulo.
                     || case when old.veto_ate is not null and new.veto_ate is null and old.veto_espera is null and new.veto_espera = 'dono'
                             then array['veto_ate'] else '{}'::text[] end
                     -- FASE 7f: fim
                -- FASE 7f: (7f P1, §5.2) na fechada, só o carimbo de que ela ficou com o padrão, de nulo a valor: o prazo decide por agenda_decidir,
                -- que fecha a pergunta, e carimba depois. O CHECK pergunta_assumida_fechada recusa a carimbada ainda aberta.
                when old.estado in ('respondida', 'resolvida') and old.assumida_por is null then array['assumida_por', 'assumida_em']
                -- FASE 7f: fim
                else '{}'::text[] end,
           -- FASE 3: payee_id é ON DELETE SET NULL (apagar o favorecido deixa a pergunta com a pessoa nula).
           array['service_order_id', 'os_material_id', 'proposta_id', 'respondida_por', 'payee_id']) then
    if old.estado = 'aberta' then
      raise exception 'A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.';
    end if;
    raise exception 'A pergunta fechada não muda: a decisão registrada fica como foi.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_perguntas_antes() is 'Agenda de Produção (Fase 2; Fase 3: carona_em e payee_id; Fase 7a: veto_ate e opcao_padrao; Fase 7f: o padrão e o prazo): gatilho BEFORE INSERT/UPDATE — recomendação, opção escolhida e opção padrão são uma das opções; a pergunta só sai de aberta, com o que a mostra/responde/resolve (e a carona); na aberta, destrava, veto_teria_em e assumida_* mudam; veto_ate vai de nulo a um valor uma vez, e de um valor a outro só na pergunta que nunca foi mostrada antes do prazo, na mesma escrita que a mostra; veto_espera vai de nulo a dono ou sem_padrao; padrao_* só com agenda.backfill_padrao = on, que só a migration liga; fechada não muda, fora assumida_* de nulo a valor. Fase 7f (P7, §5.7): o prazo vai a nulo só na mesma escrita que leva veto_espera de nulo a dono (*agenda espera <nome>*, agenda_veto_dito).';

-- ── 2. *agenda espera <nome>* ───────────────────────────────────────────────────────────────────────
-- §5.7 com R8.5-28: só espera. A régua do alvo é a do *desfaz* (o TS já recusou letra, conectivo e palavra de outra ferramenta, até 40 letras): a OS pelo agenda_resolver_os, que
-- o retorno também lê e que aqui só é chamado (ambíguo: vale a única das OS achadas que tem pergunta aberta); sem OS, o fornecedor da pergunta pelo nome curto, o de exibição,
-- o fantasia ou a razão social. As candidatas são as de
-- agenda_perguntas_em_ordem (as abertas ligadas que valem, sem conferencia), na ordem dela; a pergunta dos dias do dono (padrao_do_dono) fica de fora (AG7-37: o caminho dela é outro).
-- A 1ª que ainda pode passar a esperar (veto_espera nula: o gatilho só a leva de nulo a dono) ganha veto_espera = dono e o prazo nulo, na mesma escrita, sob a trava da linha.
-- Com opcao_padrao (só as do gestor do 7a têm, e elas nascem com espera = tipo) o prazo fica, porque o CHECK veto_padrao_tem_prazo o exige; nenhuma das que chegam aqui tem.
-- Nenhuma que pode: a 1ª da lista diz por que já não fica com o padrão sozinha (ou que tem prazo próprio). Nome que não casa: a lista das que podem esperar (R8.12-1).
create or replace function public.agenda_veto_dito(p_autor uuid, p_acao text, p_alvo text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_autor uuid;
  v_alvo  text := btrim(coalesce(p_alvo, ''));
  v_norm  text := public._agenda_normal(p_alvo);
  v_ord   jsonb;
  v_ro    jsonb;
  v_os    uuid;
  v_ids   uuid[];
  v_cands uuid[];
  v_nomes text[];
  q       public.agenda_perguntas;
  v_nome  text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_veto_dito: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_autor := public._autor_da_agenda(p_autor);
  if p_acao is distinct from 'espera' then
    raise exception 'Não existe *agenda fica*: sem resposta, cada pergunta fica como eu disse, no prazo dela. Para uma pergunta esperar você, diga *agenda espera* e o nome.'
      using errcode = '22023';
  end if;
  v_ord := public.agenda_perguntas_em_ordem(p_hoje, p_agora);
  if v_alvo <> '' then
    v_ro := public.agenda_resolver_os(v_alvo, p_hoje);
    -- ambíguo: das OS que o resolvedor achou, a única que tem pergunta aberta aqui é a do dono; com 2 ou mais, a pergunta do resolvedor; com nenhuma, a lista
    if v_ro ->> 'status' = 'ambiguo' then
      select array_agg(distinct (c ->> 'id')::uuid) into v_cands
        from jsonb_array_elements(coalesce(v_ro -> 'opcoes', '[]'::jsonb)) c
       where exists (select 1 from jsonb_array_elements(v_ord) o join public.agenda_perguntas x on x.id = (o ->> 'id')::uuid
                      where x.tipo <> 'padrao_do_dono'
                        and (x.service_order_id = (c ->> 'id')::uuid or (c ->> 'id')::uuid = any (coalesce(x.os_ids, '{}'::uuid[]))));
      if coalesce(cardinality(v_cands), 0) > 1 then
        return jsonb_build_object('ok', false, 'mudou', false, 'status', 'ambiguo', 'texto', v_ro ->> 'texto', 'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
      v_ro := case when cardinality(v_cands) = 1 then jsonb_build_object('status', 'ok', 'id', v_cands[1]) else jsonb_build_object('status', 'nao_achei') end;
    end if;
    v_os := case when v_ro ->> 'status' in ('ok', 'fora_da_carteira') then nullif(v_ro ->> 'id', '')::uuid end;
    v_ids := array(select (o ->> 'id')::uuid
                     from jsonb_array_elements(v_ord) o
                     join public.agenda_perguntas x on x.id = (o ->> 'id')::uuid
                    where x.tipo <> 'padrao_do_dono'
                      and case when v_os is not null then x.service_order_id = v_os or v_os = any (coalesce(x.os_ids, '{}'::uuid[]))
                               else x.chave ~ '^fornecedor_cadastro:[0-9a-f-]{36}$'
                                    and exists (select 1 from public.suppliers s
                                                 where s.id = split_part(x.chave, ':', 2)::uuid
                                                   and v_norm in (public._agenda_normal(public._agenda_fornecedor_curto(s.id)), public._agenda_normal(s.display_name),
                                                                  public._agenda_normal(s.trade_name), public._agenda_normal(s.name))) end
                    order by (o ->> 'ordem')::int);
  end if;
  if coalesce(cardinality(v_ids), 0) = 0 then
    v_nomes := array(select t.n from (select public._agenda_pergunta_frases(x, p_hoje) ->> 'nome' as n, min((o ->> 'ordem')::int) as m
                                        from jsonb_array_elements(v_ord) o
                                        join public.agenda_perguntas x on x.id = (o ->> 'id')::uuid
                                       where x.tipo <> 'padrao_do_dono'
                                       group by 1) t
                      where t.n is not null order by t.m, t.n);
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nao_achei', 'nomes', to_jsonb(v_nomes),
      'texto', case when cardinality(v_nomes) = 0 then 'Não tenho pergunta aberta de cliente nem de fornecedor para esperar você agora.'
                    else format('Não achei pergunta aberta de %s. Podem esperar você: %s. Diga *agenda espera* e o nome.',
                                coalesce(nullif(v_alvo, ''), 'esse nome'), public._agenda_lista(v_nomes, null)) end);
  end if;

  select x.* into q from public.agenda_perguntas x
   where x.id = any (v_ids) and x.estado = 'aberta' and x.veto_espera is null
   order by array_position(v_ids, x.id)
   limit 1
   for update;
  if found then
    v_nome := coalesce(public._agenda_pergunta_frases(q, p_hoje) ->> 'nome', v_alvo);
    update public.agenda_perguntas
       set veto_espera = 'dono', veto_ate = case when q.opcao_padrao is null then null else q.veto_ate end
     where id = q.id and estado = 'aberta' and veto_espera is null;
    return jsonb_build_object('ok', true, 'mudou', true, 'status', 'espera', 'pergunta_id', q.id,
                              'texto', format('Combinado: a pergunta de %s espera você, sem prazo.', v_nome));
  end if;

  select x.* into q from public.agenda_perguntas x where x.id = v_ids[1];
  v_nome := coalesce(public._agenda_pergunta_frases(q, p_hoje) ->> 'nome', v_alvo);
  if q.veto_espera = 'tipo' and q.veto_ate is not null then
    return jsonb_build_object('ok', true, 'mudou', false, 'status', 'prazo_proprio', 'pergunta_id', q.id,
      'texto', format('A pergunta de %s tem prazo próprio, até %s às %s: o *agenda espera* não muda esse. Para outra escolha, responda a pergunta.',
                      v_nome, public._dia_curto((q.veto_ate at time zone 'America/Sao_Paulo')::date), to_char(q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI')));
  end if;
  return jsonb_build_object('ok', true, 'mudou', false, 'status', 'ja_espera', 'pergunta_id', q.id,
                            'texto', format('A pergunta de %s já espera você: ela não fica com o padrão sozinha.', v_nome));
end;
$function$;

comment on function public.agenda_veto_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 7f, P7; §5.7, §6.2, R8.5-28, AG7-15): *agenda espera <nome>* (p_acao = espera; *agenda fica* não existe = 22023). O nome pela régua do *desfaz*: a OS por agenda_resolver_os (ambíguo: a única das OS achadas com pergunta aberta; com 2 ou mais, a pergunta dele), sem OS o fornecedor da pergunta. Das abertas de agenda_perguntas_em_ordem com aquele nome (fora padrao_do_dono, AG7-37), a 1ª com veto_espera nula ganha veto_espera = dono e veto_ate nulo: não vence mais. {ok, mudou, status (espera | ja_espera | prazo_proprio | nao_achei | ambiguo), pergunta_id, texto}; o nome que não casa devolve a lista das que podem esperar. Vale com o freio. Security definer, o administrador por _autor_da_agenda; só service_role.';

-- ── 3. *agenda pendências* ──────────────────────────────────────────────────────────────────────────
-- _agenda_ver_decisoes (de 20261107100860_agenda_fase7d_correcao3.sql)
create or replace function public._agenda_ver_decisoes(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_dec   jsonb := public.agenda_decisoes_abertas(p_agora);
  v_l     text[] := '{}';
  v_outra text[];
  v_som   text[];
  e       jsonb;
  -- FASE 7d: (correção O8) só neste foco o teto é outro; o que os outros focos usam (cf.texto_max) não muda. dados leva todas as abertas, mesmo as cortadas
  c_7d_teto    constant int := greatest(cf.texto_max, 1800);   -- estrutural: as decisões numeradas ocupam a maior parte, e este foco existe para mostrar tudo
  v_7d_abertas jsonb;
  v_7d_txt     text;
  v_7d_fora    text[] := '{}';   -- (correção T4) os títulos do que o corte tirou
  v_7d_resto   text[];
  v_7d_ult     text;
  k            int;
  -- FASE 7d: fim
  -- FASE 7f: (7f P7) o prazo de cada pergunta e a ordem do "Também quero saber"
  v_7f_ord   jsonb;
  v_7f_prazo jsonb := '{}'::jsonb;
  v_7f_ids   text[] := '{}';
  v_7f_k     int;
  c_7f_espera constant text := 'Para uma pergunta esperar você, sem prazo: *agenda espera* e o nome.';
  c_7f_espera_dec constant text := 'Para uma esperar você, sem prazo: *agenda espera* e o nome.';
  -- FASE 7f: fim
begin
  for e in select x from jsonb_array_elements(v_dec) x loop
    -- FASE 3: a da diária com as opções, a recomendação e as palavras
    v_l := v_l || format('Decisão %s: %s', e ->> 'n',
                         case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid) else e ->> 'texto' end);
  end loop;
  -- FASE 7f: (7f P7; §5.7, R8.7, R8.12-9) a linha de cada pergunta (agenda_perguntas_em_ordem, a mesma do bloco e da quinta) diz o prazo só onde ele vale de verdade: modo_veto
  -- ligado, sem o freio, e a pergunta que pode vencer (veto_ate da linha = o prazo que está no texto). Em sombra e com o freio, nenhuma linha diz "Sem resposta até". O prazo vai na forma
  -- curta, a mesma do bloco: o trecho da linha que começa em "Sem resposta até". O número continua o n de agenda_decisoes_abertas, na ordem dela: nada aqui o recria nem o reordena.
  v_7f_ord := public.agenda_perguntas_em_ordem(p_hoje, p_agora);
  v_7f_prazo := coalesce((select jsonb_object_agg(o ->> 'id', substr(o ->> 'linha', position('Sem resposta até' in o ->> 'linha')))
                            from jsonb_array_elements(v_7f_ord) o
                           where o ->> 'veto_ate' is not null), '{}'::jsonb);
  v_l := array(select x || coalesce(' ' || (v_7f_prazo ->> (v_dec -> (o::int - 1) ->> 'id')), '') from unnest(v_l) with ordinality u(x, o) order by o);
  -- FASE 7f: fim
  v_outra := array(select q.texto from public.agenda_perguntas q
                    where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                      -- FASE 7d: (7d P5, P6, P6b) quem tem número já vem em v_dec (agenda_decisoes_abertas): pelo id, uma pergunta nunca aparece duas vezes. Quem não tem
                      -- número (sem opções, sem efeito em agenda_decidir ou com a opção já dita) segue aqui, como antes.
                      and not exists (select 1 from jsonb_array_elements(v_dec) x where x ->> 'id' = q.id::text)
                      -- FASE 7d: fim
                      and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.perda_em nulls last, q.criada_em, q.id);
  -- FASE 7d: (correção O8) as abertas sem número, com o texto: vão em dados, mesmo as cortadas (as numeradas já estão em decisoes). Quem tem opções vem primeiro: o corte tira do fim, e a nota se
  -- responde por número ("na nota, a 2"): as opções dela não podem ser as que somem. O resto, na ordem de antes.
  v_7d_abertas := coalesce((select jsonb_agg(jsonb_build_object('tipo', q.tipo, 'texto', q.texto)
                                             order by (case when jsonb_typeof(q.opcoes) = 'array' then jsonb_array_length(q.opcoes) > 0 else false end) desc,
                                                      q.perda_em nulls last, q.criada_em, q.id)
                              from public.agenda_perguntas q
                             where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                               and not exists (select 1 from jsonb_array_elements(v_dec) x where x ->> 'id' = q.id::text)
                               and (q.expira_em is null or q.expira_em > p_agora)), '[]'::jsonb);
  v_outra := array(select y ->> 'texto' from jsonb_array_elements(v_7d_abertas) with ordinality u(y, o) order by o);
  -- FASE 7d: fim
  -- FASE 7f: (7f P7; §5.2, §5.7, R8.7) "Também quero saber" na ordem de agenda_perguntas_em_ordem, a mesma do bloco e da quinta: os dias do dono primeiro (AG7-02), o que
  -- destrava mais, o prazo mais cedo, a mais velha. Antes de tudo, quem tem opções: o corte tira do fim, e as opções de quem se responde por número não podem ser as que somem (7d,
  -- correção O8). Quem não está na ordem (a conferencia, que o bloco põe no "Hoje") vem depois, na de antes. As mesmas perguntas e os mesmos textos: só a ordem muda. Em todo modo:
  -- a spec não a amarra a um (R8.7).
  select coalesce(jsonb_agg(jsonb_build_object('tipo', q.tipo, 'texto', q.texto)
                            order by (case when jsonb_typeof(q.opcoes) = 'array' then jsonb_array_length(q.opcoes) > 0 else false end) desc,
                                     w.ordem nulls last, q.perda_em nulls last, q.criada_em, q.id), '[]'::jsonb),
         coalesce(array_agg(q.id::text order by (case when jsonb_typeof(q.opcoes) = 'array' then jsonb_array_length(q.opcoes) > 0 else false end) desc,
                                                w.ordem nulls last, q.perda_em nulls last, q.criada_em, q.id), '{}')
    into v_7d_abertas, v_7f_ids
    from public.agenda_perguntas q
    left join (select (o ->> 'id')::uuid as id, (o ->> 'ordem')::int as ordem from jsonb_array_elements(v_7f_ord) o) w on w.id = q.id
   where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
     and not exists (select 1 from jsonb_array_elements(v_dec) x where x ->> 'id' = q.id::text)
     and (q.expira_em is null or q.expira_em > p_agora);
  v_outra := array(select y ->> 'texto' from jsonb_array_elements(v_7d_abertas) with ordinality u(y, o) order by o);
  -- FASE 7f: fim
  if jsonb_array_length(v_dec) > 0 then
    v_l := array[case when jsonb_array_length(v_dec) = 1 then 'Uma decisão espera você na agenda:'
                      else format('%s decisões esperam você na agenda:', jsonb_array_length(v_dec)) end]
           || v_l
           || 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.'::text;
  end if;
  -- FASE 7f: (7f P7; R8.5-28, AG7-15) com algum prazo escrito, entra a única saída de quem não quer o padrão, o *agenda espera* (o *agenda fica* não existe): no fim da linha de
  -- como responder, que perde o "Eu não escolho por você" quando alguma decisão tem prazo (ali ele deixa de ser verdade); sem decisão numerada, numa linha antes do "Também quero
  -- saber", que o corte tira do fim. Sem prazo nenhum, nada muda.
  if v_7f_prazo <> '{}'::jsonb then
    if jsonb_array_length(v_dec) > 0 then
      v_l[cardinality(v_l)] := 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2").'
                               || case when exists (select 1 from jsonb_array_elements(v_dec) x where v_7f_prazo ? (x ->> 'id')) then ''
                                       else ' Eu não escolho por você.' end || ' ' || c_7f_espera_dec;
    else
      v_l := v_l || c_7f_espera;
    end if;
  end if;
  -- FASE 7f: fim
  if cardinality(v_outra) > 0 then
    v_l := v_l || array(select 'Também quero saber: ' || x from unnest(v_outra) with ordinality u(x, o) order by o);
  end if;
  -- FASE 7f: (7f P7) o prazo curto também no "Também quero saber" (os títulos do corte, em v_outra, ficam sem ele)
  if cardinality(v_outra) > 0 and v_7f_prazo <> '{}'::jsonb then
    v_7f_k := cardinality(v_l) - cardinality(v_outra);
    v_l := v_l[1:v_7f_k] || array(select v_l[v_7f_k + o] || coalesce(' ' || (v_7f_prazo ->> v_7f_ids[o]), '') from generate_series(1, cardinality(v_outra)) o order by o);
  end if;
  -- FASE 7f: fim
  if cardinality(v_l) = 0 then
    v_som := array(select q.texto from public.agenda_perguntas q
                    where q.estado = 'aberta' and q.modo = 'sombra' and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.critica desc, q.perda_em nulls last, q.criada_em, q.id);
    if cardinality(v_som) > 0 and (cf.modo_proposta = 'sombra' or cf.modo_vigia = 'sombra') then
      v_l := array['Em teste (nada foi perguntado de verdade): eu perguntaria isto.']
             || array(select '• ' || x from unnest(v_som) with ordinality u(x, o) order by o);
    else
      v_l := array['Nada esperando você na agenda agora.'];
    end if;
  end if;
  -- FASE 7d: (correção O8, T4) o foco que mostra tudo: até c_7d_teto letras. O corte não esconde: saem as linhas inteiras do fim, as "Também quero saber", e a última linha diz quais, pelo título curto,
  -- dentro das c_7d_teto letras. Sem "Também quero saber" para tirar, o corte de sempre. O return de baixo não roda mais; fica para os tiradores das etapas anteriores.
  v_7d_txt := public._agenda_juntar(v_l, c_7d_teto);
  if char_length(array_to_string(v_l, E'\n')) > c_7d_teto and cardinality(v_outra) > 0 then
    for k in reverse cardinality(v_outra) .. 1 loop
      v_7d_fora := public._agenda_titulo_da_pergunta(v_outra[k]) || v_7d_fora;
      v_7d_resto := v_l[1:cardinality(v_l) - cardinality(v_7d_fora)];
      v_7d_ult := 'Também esperam: ' || array_to_string(v_7d_fora, '; ') || '.';
      exit when char_length(array_to_string(v_7d_resto, E'\n')) + 1 + char_length(v_7d_ult) <= c_7d_teto;
    end loop;
    -- os títulos também têm teto: com 20 perguntas de fora, a linha do fim não pode tomar o foco
    if char_length(array_to_string(v_7d_resto, E'\n')) + 1 + char_length(v_7d_ult) > c_7d_teto then
      v_7d_ult := public._agenda_corta(v_7d_ult, c_7d_teto / 2);
    end if;
    v_7d_txt := public._agenda_juntar(v_7d_resto, c_7d_teto - char_length(v_7d_ult) - 1) || E'\n' || v_7d_ult;
  end if;
  return jsonb_build_object('ok', true, 'texto', v_7d_txt,
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra), 'abertas', v_7d_abertas));
  -- FASE 7d: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra)));
end;
$function$;

comment on function public._agenda_ver_decisoes(date, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a da diária com as opções e as palavras): agenda_ver foco decisoes — as decisões críticas abertas numeradas por agenda_decisoes_abertas ("Decisão 1: <a pergunta com as opções e a recomendação>"), como responder, e o que mais a agenda quer saber (chegou?, parada?, o que falta?), uma linha cada; sem nada em ligado, o que a sombra perguntaria ("Em teste"); nada = "Nada esperando você na agenda agora.". {ok, texto, dados{decisoes, outras}}. FASE 7d (P5): a combinar vem numerada, como decisão, e sai de "Também quero saber". FASE 7d (P6): a local também vem numerada. FASE 7d (P6b): quem tem número sai de "Também quero saber" pelo id; quem não tem segue lá. Correção da 7d (O8): só neste foco, até 1.800 letras; dados.abertas leva as sem número com o texto, mesmo as cortadas; quando ainda corta (T4), saem as linhas do fim, e a última diz quais, pelo título. FASE 7f (P7; §5.7, R8.7, R8.5-28): cada pergunta diz o prazo, na forma curta da linha (agenda_perguntas_em_ordem: "Sem resposta até qua 11/11 às 18:00, …"), só onde ele vale de verdade (modo_veto ligado, sem o freio, e a pergunta que pode vencer): em sombra e com o freio, nenhuma. O número é o n de agenda_decisoes_abertas, que não muda; "Também quero saber" vai na ordem de agenda_perguntas_em_ordem (a do bloco e da quinta), depois de quem tem opções, em todo modo; quem não está nela (a conferencia) vem depois. Com algum prazo, a decisão com prazo perde o "Eu não escolho por você" e entra a linha do *agenda espera*. Não marca nada como mostrado.';

-- ── 4. A saúde da comunicação ───────────────────────────────────────────────────────────────────────
-- §11 com R8.5-27 e 29 e o que P3 e P4 deixaram. A porta de _agenda_saude_local. Os modos crus (R8.6). Os zeros entram no ok de agenda_saude:
--   assumida_sem_prazo_mostrado e assumida_que_esperava (aceite 1), assumida_tipo_proibido (aceite 2: a lista do CHECK de veto_tipos, que o V3 confere), teto_passou_sem_motivo
--   (aceite 3: acima do teto, sobrou alguma que o teto fecharia, de antes da última rodada comunicar — sem rodada, nenhuma —, com o prazo ligado de verdade), bloco_grande (aceite 4: o fechamento ligado
--   acima de texto_max com o bloco acima do mínimo; no mínimo ele pode passar, de propósito, NOVO-agenda-114) e excecao_acima_do_teto (aceite 5: a cota do dia furada).
-- Os números, só com algum modo fora de desligado (como _agenda_saude_local): as perguntas (com a idade em dias úteis e a complacência de 2 semanas), as exceções do dia (ligado: os ids
-- distintos acima da cota; sombra: o que o lote levaria e guardaria), a quinta (a hora em que saiu; em sombra, o que diria), o bloco nos fechamentos de 7 dias (resumo_tarde), as
-- mensagens do dia por origem (só contagens) e as falhas do pré-passo do lote. A equipe e o cliente (aceites 6 e 7) são dos pacotes P5 e P6, que ainda não existem.
create or replace function public._agenda_saude_comunicacao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_semana  constant int := 7;    -- estrutural: os números "na semana" (§11)
  c_quinze  constant int := 14;   -- estrutural: "desfeitas em 2 semanas" (§11, parar)
  c_lotes   constant int := 2;    -- estrutural: o alvo de §11 é 2 lotes (o fechamento e a quinta) mais acordes_dia_max
  -- estrutural: a lista do CHECK agenda_config_veto_tipos_check (20261109100000), o que nunca vence pelo prazo; o V3 confere que é a mesma
  c_nunca   constant text[] := array['diaria', 'diaria_ligar', 'nfe_vincular', 'pix_material', 'concluir', 'entrega', 'cliente_aprovar', 'cliente_aviso',
                                     'cliente_resposta', 'aprendizado', 'conferencia', 'remarcar_confirmado', 'compre_ate', 'sinal', 'tarefa', 'local',
                                     'combinar', 'acesso', 'dia_prometido', 'dia_avisado'];
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_modos   jsonb;
  v_algum   boolean;
  v_ult     timestamptz;
  v_rod24   int;
  v_abertas int;
  v_acima   int;
  v_bloco   jsonb := '{}'::jsonb;
  v_bgrande int := 0;
  v_z       jsonb;
  v_n       jsonb := '{}'::jsonb;
begin
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_saude_comunicacao: sem o dia de hoje ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('bloco', cf.modo_bloco_agenda, 'lote', cf.modo_lote_dono, 'veto', cf.modo_veto, 'previsto', cf.modo_equipe_previsto,
                                'convite', cf.modo_equipe_convite, 'camadas', cf.modo_cliente_camadas);
  v_algum := exists (select 1 from jsonb_each_text(v_modos) m where m.value <> 'desligado');
  select max(r.p_agora), count(*) filter (where r.p_agora > p_agora - interval '1 day' and r.p_agora <= p_agora)
    into v_ult, v_rod24
    from public.agenda_vigia_rodadas r
   where r.rotina = 'comunicar' and r.p_agora <= p_agora;
  -- as que contam no teto, como _agenda_comunicar_teto: ligadas, sem conferencia, que valem
  select count(*)::int into v_abertas from public.agenda_perguntas x
   where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora);
  v_acima := greatest(v_abertas - cf.perguntas_abertas_max, 0);

  -- o bloco nos fechamentos dos últimos 7 dias, pelo detalhe de resumo_tarde (P3): em sombra, bloco_seria (o texto que sairia com ele ligado); ligado, bloco_mostrou e o texto que saiu.
  -- No mínimo o bloco é o veredito e a 1ª decisão (com o "e mais N"): acima de texto_max com qualquer outra linha, ele ainda podia ceder, e isso é o bloco_grande.
  -- A tabela é a do Secretário (20261015210000); um resumo_tarde sem as colunas que o bloco lê (o da bancada da Fase 2 tem só dia, telefone e detalhe) conta como sem a tabela.
  if to_regclass('public.resumo_tarde') is not null
     and (select count(*) from pg_attribute a where a.attrelid = to_regclass('public.resumo_tarde') and a.attnum > 0 and not a.attisdropped
             and a.attname in ('dia', 'turno', 'detalhe', 'criado_em')) = 4 then
    execute $q$
      select coalesce(jsonb_build_object(
               'em_sombra', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_seria'),
               'seria_dentro', count(*) filter (where (t.detalhe #>> '{agenda,bloco_seria,caracteres}')::int <= $3),
               'seria_acima', count(*) filter (where (t.detalhe #>> '{agenda,bloco_seria,caracteres}')::int > $3),
               'seria_dentro_por_turno', coalesce((select jsonb_object_agg(z.turno, z.n) from (
                   select u.turno, count(*) as n from public.resumo_tarde u
                    where u.dia between $1 and $2 and (u.detalhe #>> '{agenda,bloco_seria,caracteres}')::int <= $3 group by u.turno) z), '{}'::jsonb),
               'ligado', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou'),
               'ligado_acima', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3),
               'ultimo', (select jsonb_build_object('dia', u.dia, 'turno', u.turno, 'modo', u.detalhe #>> '{agenda,bloco_diria,modo}',
                                                    'caracteres', coalesce((u.detalhe #>> '{agenda,bloco_seria,caracteres}')::int, (u.detalhe ->> 'caracteres')::int))
                            from public.resumo_tarde u
                           where u.dia between $1 and $2 and u.detalhe -> 'agenda' ? 'bloco_diria'
                           order by u.dia desc, u.criado_em desc limit 1)), '{}'::jsonb),
             count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3
                                and ((select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' not in ('veredito', 'decisao')) > 0
                                     or (select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' = 'decisao') > 2))::int
        from public.resumo_tarde t
       where t.dia between $1 and $2 and t.detalhe -> 'agenda' ? 'bloco_diria'
    $q$ into v_bloco, v_bgrande using p_hoje - c_semana + 1, p_hoje, cf.texto_max;
  end if;

  v_z := jsonb_build_object(
    'assumida_sem_prazo_mostrado', (select count(*) from public.agenda_perguntas q
                                     where q.assumida_por = 'prazo'
                                       and not coalesce(q.veto_ate is not null and q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)),
    'assumida_que_esperava', (select count(*) from public.agenda_perguntas q where q.assumida_por is not null and q.veto_espera is not null),
    'assumida_tipo_proibido', (select count(*) from public.agenda_perguntas q where q.assumida_por is not null and q.tipo = any (c_nunca)),
    'teto_passou_sem_motivo', case when v_acima = 0 or public._agenda_fala_modo('veto') <> 'ligado' then 0 else
       least(v_acima, (select count(*)::int from public.agenda_perguntas x
                        where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora)
                          and x.padrao_efeito = 'nada' and x.opcao_escolhida is null and x.criada_em < v_ult
                          and public._agenda_pergunta_espera(x, p_hoje) is null)) end,
    'bloco_grande', coalesce(v_bgrande, 0),
    'excecao_acima_do_teto', greatest(- public._agenda_lote_cota(p_hoje), 0));

  if v_algum then
    v_n := jsonb_build_object(
      'perguntas', (select jsonb_build_object(
                             'abertas', v_abertas, 'teto', cf.perguntas_abertas_max, 'acima_do_teto', v_acima,
                             'com_prazo', count(*) filter (where q.estado = 'aberta' and q.veto_ate is not null and q.veto_espera is null),
                             'esperam_voce', count(*) filter (where q.estado = 'aberta' and q.veto_espera = 'dono'),
                             'respondidas_semana', count(*) filter (where q.estado = 'respondida' and q.assumida_por is null
                                                                     and q.respondida_em > p_agora - make_interval(days => c_semana)),
                             'assumidas_prazo_semana', count(*) filter (where q.assumida_por = 'prazo' and q.assumida_em > p_agora - make_interval(days => c_semana)),
                             'assumidas_teto_semana', count(*) filter (where q.assumida_por = 'teto' and q.assumida_em > p_agora - make_interval(days => c_semana)),
                             'teria_semana', count(*) filter (where q.veto_teria_em > p_agora - make_interval(days => c_semana)))
                      from public.agenda_perguntas q where q.modo = 'ligado')
                   || jsonb_build_object(
                        'idade_media_du', (select round(avg((select count(*) from generate_series((x.criada_em at time zone 'America/Sao_Paulo')::date + 1, p_hoje, interval '1 day') d
                                                              where public.agenda_dia_util(d::date)))::numeric, 1)
                                             from public.agenda_perguntas x
                                            where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora)),
                        'complacencia', (select jsonb_build_object('assumidas', count(*),
                                                                   'desfeitas', count(*) filter (where exists (select 1 from public.agenda_acoes a
                                                                                                                where a.pergunta_id = q.id and a.desfeita_em is not null)))
                                           from public.agenda_perguntas q
                                          where q.assumida_por = 'prazo' and q.assumida_em > p_agora - make_interval(days => c_quinze))),
      'excecoes', jsonb_build_object(
        'hoje', (select count(*) from public.agenda_dono_avisos v where v.dia = p_hoje and v.fila_id is not null and v.dedupe_key like 'agenda-dono:excecao:%'),
        'cota_livre', greatest(public._agenda_lote_cota(p_hoje), 0),
        'acima_da_cota_hoje', (select count(distinct x) from public.agenda_vigia_rodadas r
                                 cross join lateral jsonb_array_elements_text(coalesce(r.contagens #> '{lote_guardaria,acima_da_cota_ids}', '[]'::jsonb)) x
                                where r.rotina = 'comunicar' and r.p_hoje = p_hoje),
        'em_sombra_hoje', (select jsonb_build_object('avisos', count(*),
                                                     'levaria', coalesce(sum((r.contagens #>> '{lote_guardaria,levaria,acoes}')::int), 0),
                                                     'guardaria', coalesce(sum((r.contagens #>> '{lote_guardaria,guardaria,acoes}')::int), 0),
                                                     'guardaria_perguntas', coalesce(sum((r.contagens #>> '{lote_guardaria,guardaria,perguntas}')::int), 0),
                                                     'acima_da_cota', coalesce(sum((r.contagens #>> '{lote_guardaria,acima_da_cota}')::int), 0))
                             from public.agenda_vigia_rodadas r
                            where r.rotina = 'comunicar' and r.p_hoje = p_hoje and r.contagens #> '{lote_guardaria,aviso}' is not null)),
      'quinta', jsonb_build_object(
        'saiu', (select jsonb_build_object('dia', v.dia, 'estado', v.estado, 'enviada_em', v.enviada_em,
                                           'mudancas', cardinality(v.acao_ids), 'perguntas', cardinality(v.pergunta_ids))
                   from public.agenda_dono_avisos v
                  where v.dedupe_key like 'agenda-dono:semana:%' and v.dia between p_hoje - c_semana + 1 and p_hoje
                  order by v.dia desc limit 1),
        'diria', (select jsonb_build_object('dia', r.p_hoje, 'caracteres', (r.contagens #>> '{quinta,quinta_diria,caracteres}')::int,
                                            'cabe', (r.contagens #>> '{quinta,quinta_diria,cabe}')::boolean, 'motivo', r.contagens #>> '{quinta,quinta_diria,motivo}',
                                            'mudancas', (r.contagens #>> '{quinta,quinta_diria,mudancas}')::int, 'perguntas', (r.contagens #>> '{quinta,quinta_diria,perguntas}')::int)
                    from public.agenda_vigia_rodadas r
                   where r.rotina = 'comunicar' and r.p_hoje between p_hoje - c_semana + 1 and p_hoje and r.contagens #> '{quinta,quinta_diria}' is not null
                   order by r.p_agora desc limit 1)),
      'bloco', v_bloco,
      'mensagens_hoje', (select jsonb_build_object('fechamento', count(*) filter (where f.source = 'ai_briefing_tarde'),
                                                   'aviso', count(*) filter (where f.source = 'agenda-dono'),
                                                   'acorde', count(*) filter (where f.source = 'agenda'),
                                                   'alvo', c_lotes + cf.acordes_dia_max)
                           from public.whatsapp_send_queue f
                          where f.source in ('ai_briefing_tarde', 'agenda-dono', 'agenda') and f.status not in ('failed', 'cancelled')
                            and f.created_at >= (p_hoje::timestamp at time zone 'America/Sao_Paulo')
                            and f.created_at < ((p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo')));
  end if;

  return jsonb_build_object(
    'modos', v_modos, 'freio', cf.gestor_so_propor,
    'ultima_rodada', v_ult, 'rodadas_24h', coalesce(v_rod24, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'comunicar:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'falhas_lote_guardaria_24h', (select count(*) from public.app_error_logs e
                                   where e.context = 'agenda' and e.action = 'comunicar:lote_guardaria' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', not exists (select 1 from jsonb_each(v_z) z where (z.value)::text <> '0'),
    'numeros', v_n) || v_z;
end;
$function$;

comment on function public._agenda_saude_comunicacao(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P7; §11, R8.5-27, R8.5-29, R8.6): a saúde da comunicação — {modos (os 6, crus), freio, ultima_rodada e rodadas_24h (rotina comunicar), erros_24h (comunicar:%), falhas_lote_guardaria_24h, zeros_ok, numeros} e os zeros: assumida_sem_prazo_mostrado, assumida_que_esperava, assumida_tipo_proibido, teto_passou_sem_motivo, bloco_grande, excecao_acima_do_teto. numeros só com algum modo fora de desligado: perguntas (abertas, teto, com prazo, esperam você, respondidas, assumidas por prazo e por teto, teria, idade média em dias úteis, complacência de 2 semanas), excecoes (hoje, cota livre, os ids distintos acima da cota; em sombra o que o lote levaria e guardaria), quinta (a que saiu; em sombra a que diria), bloco (resumo_tarde de 7 dias), mensagens_hoje por origem (aviso = agenda-dono, acorde = agenda; só contagens). A porta de _agenda_saude_local: administrador, financeiro ou service_role; o resto 42501.';

-- ── 5. agenda_saude com a chave comunicacao ─────────────────────────────────────────────────────────
-- agenda_saude (de 20261107100700_agenda_fase7d_leituras.sql)
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
  -- (7f P7; R2, P2b, AG7-15; dentro do bloco do gestor da 7a: por isso a marca, não o bloco) prazo_em_critica: desde a 7f a crítica pode ter prazo e vencer (AG7-15, "sem resposta
  -- fica como ele propôs"). O zero passa a ser o prazo em crítica que nunca venceria: fora de veto_tipos ou com veto_espera. Hoje, 0 críticas na história: 0 nos dois jeitos.
  v_gz := v_gz || jsonb_build_object('prazo_em_critica', (select count(*) from public.agenda_perguntas q
                                                         where q.estado = 'aberta' and q.critica and q.veto_ate is not null
                                                           and (not q.tipo = any (cf.veto_tipos) or q.veto_espera is not null)));
  -- (7f: fim)
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
  -- (7d P8; §11, R6.3-11; dentro do bloco do gestor: por isso a marca, não o bloco) a chave local (_agenda_saude_local), com os zeros obrigatórios no ok. Sem os modos da 7d, os
  -- zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('local', public._agenda_saude_local(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{local,zeros_ok}')::boolean, true)));
  -- O M11 na lista dos liberados (o recado do P6): aqui, e não na lista dos 11 lá em cima, que fica dentro do bloco da Fase 5
  if public._agenda_cliente_tipo_liberado('onde_fica') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["onde_fica"]'::jsonb);
  end if;
  -- (7d: fim)
  -- (7f P7; §11, R8.13; dentro do bloco do gestor: por isso a marca, não o bloco) a chave comunicacao (_agenda_saude_comunicacao), com os zeros obrigatórios no ok. Sem os modos
  -- da 7f e sem nada do que eles fazem, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('comunicacao', public._agenda_saude_comunicacao(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{comunicacao,zeros_ok}')::boolean, true)));
  -- (7f: fim)
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
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias. FASE 7 (7a P7, spec §11): a chave gestor — os modos efetivos (marcar, encaixe, revisao, compre_ate, vaga, so_propor, desde), as regras, a última rodada (rotina gestor), as rodadas em 24 h, se os passos diários rodaram hoje, os erros de gestor:% em 24 h, os zeros obrigatórios (entram no ok: zona_travada_mexida e dia_avisado_sem_pergunta pela regra de _agenda_criticidade_da_acao, estimativa_sem_pergunta, prazo_em_critica, prazo_em_dia_prometido, aprovada_sem_data, rodada_gestor_atrasada, cliente_estimativa_sem_aprovacao, ficha_estimativa_sem_veto, onda_aplicada_sem_pergunta, alocacao_sem_fonte, regra_em_sombra_aplicada; os do que o gestor muda sozinho contam a partir de marcar_sozinho_desde) e prazo_vencido_sem_mostrar (só se conta: fica fora do ok), e os números (OS por estimativa, perguntas com prazo abertas/vencidas/respondidas/aplicadas pelo prazo, compre até gravados/cobrados/empurrados, fichas seguradas). E o erro do fator (métricas do aprendizado) só com as medidas que têm fator (a medida por estimativa é válida e não tem fator). FASE 7b (P5, §5.4, R4.3(g)): a chave equipe_dias (_agenda_saude_equipe7b): modos (dias, dupla, sabado, cadastro, chamar), a última rodada da semana da equipe e os erros de equipe_semana:% em 24 h, os zeros obrigatórios (entram no ok: dias_fora_da_janela, dias_duas_na_semana, dia_acima_do_teto, ficha_recusada_por_teto_com_dias, dupla_com_uma_pessoa — só a dita —, dupla_incompleta_com_gente_livre, novato_sozinho, sabado_sem_prazo, sabado_tarde, dono_em_vaga_sem_ok, resposta_sem_gravar) e os números (perguntadas × respondidas na última semana fechada e o %, adiadas pelo teto em 7 dias, a dupla inferida esperando o ajudante, duplas inferidas × ditas, sábados usados e em teste, a semana passada por pessoa: declarada × usada × cumprida). Sem os modos da 7b, os zeros são 0 e o ok é o de antes. FASE 7d (P8; §11, R6.3-11): a chave local (_agenda_saude_local), com os zeros obrigatórios no ok (acesso_sem_preparo, feriado_local_marcado, patio_acima_das_vagas, viagem_quebrada, rodada_local_atrasada); onde_fica em tipos_liberados. Sem os modos da 7d, os zeros são 0 e o ok é o de antes. FASE 7f (P7; §11, R2, R8.13): a chave comunicacao (_agenda_saude_comunicacao: os modos crus, a rodada comunicar, os zeros obrigatórios no ok e os números da comunicação); e o zero prazo_em_critica do gestor passa a ser a crítica com prazo fora de veto_tipos ou com veto_espera (a crítica pode vencer, AG7-15).';

-- ── 6. As portas ────────────────────────────────────────────────────────────────────────────────────
-- agenda_veto_dito: como agenda_gestor_dito e agenda_dupla_dita (a palavra do dono vem pelo ai-agent, com service_role). _agenda_saude_comunicacao: como _agenda_saude_local.
-- As 3 recriadas mantêm as portas de antes (create or replace não muda grant).
revoke all on function public.agenda_veto_dito(uuid, text, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_veto_dito(uuid, text, text, date, timestamptz) to service_role;
revoke all on function public._agenda_saude_comunicacao(date, timestamptz) from public, anon;
grant execute on function public._agenda_saude_comunicacao(date, timestamptz) to authenticated, service_role;
-- NOVO-agenda-121: _agenda_ver_decisoes é invoker e chama _agenda_titulo_da_pergunta no corte das 1.800 letras (a linha "Também esperam: …", 7d correção 3), e a 7d a deixou sem
-- grant nem para service_role (20261107100850): acima do teto, *agenda pendências* dava "permission denied" pelo WhatsApp (service_role) e pelo painel. É uma função de texto,
-- imutável, que não lê tabela nenhuma: o grant não abre dado. O anon continua fora.
revoke all on function public._agenda_titulo_da_pergunta(text) from public, anon;
grant execute on function public._agenda_titulo_da_pergunta(text) to authenticated, service_role;
