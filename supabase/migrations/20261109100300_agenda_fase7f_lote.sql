-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P4: o lote do dono — fora do fechamento só sai a exceção, o resto espera o bloco das 17:30, e na
-- quinta sai a mensagem própria da semana (o que mudou e o que eu preciso de você para a semana que vem), mesmo sem mudança.
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§3.2, §3.3 d2/d6/d11/d12, §5.4, §6.3, §8.3 agenda_fase7f_lote.sql e o bloco R8, que vale sobre o corpo: R8.1, R8.3-6,
-- R8.5-12 a 14 e 27, R8.6, R8.7, R8.8, R8.10, R8.12, R8.13, R8.14); nomes: fase7-registro.md §1 (7f P4); notas: notas-fase7f.md, seções P1 a P3 ("Para o P4 e o P7").
-- Respostas do dono que valem aqui (respostas/<id> da página Respostas do Diário): AG7-22 "Mensagem própria às 17:00" (dono_semana_aviso = propria); AG7-15 "Sim, sem resposta fica
-- como ele propôs"; AG7-24 "Até 5"; D7 (29/10) o aviso quando a agenda monta, encaixa ou remaneja — o lote troca isso por resumo, e ligar o lote pede o "OK lote" nomeado dele.
-- Depende das Fases 1 a 6, do lote de 30/10, das etapas 7a a 7d e de 20261109100000, 20261109100100 e 20261109100200 da 7f. NÃO depende da 7e.
--
-- ═══ 1 CHECK TROCADO E FUNÇÕES — OK NOMEADO ═══ (8 funções novas, 3 recriadas, 1 delas com a assinatura nova; 1 CHECK de agenda_dono_avisos trocado; nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p4/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA
-- (conferida a cada montagem), e a mudança está só nos blocos "-- FASE 7f: … -- FASE 7f: fim". Tirados os blocos, o corpo é o da origem, byte a byte (o montador e o O6 de
-- supabase/tests/agenda_fase7f_lote.sql conferem).
--
-- POR QUE: o aviso do gestor tem em média 1.288 letras (6 avisos, de 997 a 1.713) e a rodada de aprontar vai em todos: 17 mostras de 7 perguntas em 6 avisos, uma delas em 5. Com o
-- bloco do fechamento (P3), o que pode esperar as 17:30 espera; fora dele só sai o que mexe hoje ou no próximo dia útil no que alguém já sabe. A quinta passa a ter a mensagem da semana.
--
-- O QUE MUDA:
--   1. agenda_dono_avisos: o CHECK "cardinality(acao_ids) > 0" (o nome sai de pg_constraint; em produção é agenda_dono_avisos_acao_ids_check, conferido em 08/11) vira
--      dono_aviso_conta_mudanca: o aviso conta pelo menos uma mudança, menos a mensagem da semana (chave agenda-dono:semana:<dia>), que pode ir só com perguntas.
--   2. _agenda_lote_ligado (nova): o lote vale de verdade só com modo_lote_dono E modo_bloco_agenda ligados (o bloco é quem conta o resto). Os dois sem freio (R8.6).
--   3. _agenda_lote_cota (nova): a cota do dia para a exceção: acordes_dia_max menos os acordes e os avisos de exceção já contados hoje (uma fonte só, §3.1 item 4).
--   4. _agenda_e_excecao (nova): o item (ação ou pergunta) é exceção, por _agenda_classe_da_saida (P1).
--   5. agenda_aviso_pecas (recriada): com o lote ligado, a rodada só leva a exceção, sem a rodada de aprontar (R8.5-14); a acima da cota espera o bloco, sem frase nenhuma (R8.5-27).
--   6. agenda_aviso_enfileirar (recriada, assinatura nova: p_semana boolean default false; a de 6 argumentos sai com drop, R8.5-16): a mensagem da semana (uma por dia, sem mudança
--      quando há pergunta) e a cota de novo, sob a trava. A chave diz o que é: aviso, excecao ou semana.
--   7. _agenda_lote_mudancas, _agenda_lote_fora, _agenda_lote_texto (novas): as peças da mensagem da semana — o que mudou e não foi contado, o que ficou de fora e o texto
--      inteiro (o mesmo que o montador _shared/agenda/aviso-do-gestor.ts junta quando cabe), que a sombra guarda.
--   8. _agenda_comunicar_quinta (nova): o passo quinta da rodada comunicar. Só no dia_do_plano, no 1º tique depois de dono_semana_hora, uma vez, com dono_semana_aviso = propria e o lote
--      ligado: devolve em avisos as peças, que o task-automations monta e enfileira pelo caminho do aviso (agenda-comunicar.ts). Depois que ela saiu, grava o prazo que estava no texto.
--      Em sombra, só contagens.quinta.quinta_diria, com o texto, uma vez por dia.
--   9. _agenda_comunicar_lote_guardaria (nova) e agenda_comunicar_rodar (recriada, um pré-passo): contagens.lote_guardaria — em sombra, o que o lote teria guardado do aviso desta
--      rodada; ligado, a exceção que passou da cota e espera o bloco (é dali que o P7 a conta na saúde).
--
-- O QUE NÃO MUDA: com modo_lote_dono desligado ou em sombra, e com ele ligado e modo_bloco_agenda fora de ligado, o aviso de cada rodada é o de antes, byte a byte: o texto, as ações,
-- as perguntas que conta como mostradas e o prazo. A rodada sem nada novo (v_n = 0) devolve o de antes sem ler nada desta migration. agenda_aviso_conferir, _agenda_aviso_mudancas e
-- _agenda_texto_do_acorde não são recriadas ("Já avisei o Roberto." espera a mensagem de mudança da equipe, que só nasce no P5). Não muda nada do que o retorno lê
-- (pedidos-do-retorno.md, item 13).
--
-- ORDEM DE LIGAR (spec R8.14): depois de 20261109100200 e junto do task-automations do pacote (o passo 0e). Aplicar sozinha não muda nada para ninguém (os 6 modos nascem desligados).
-- A 100300 tem ALTER TABLE em agenda_dono_avisos: aplicar com LOCK_TIMEOUT, logo depois de um tique.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_lote.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109100300
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261109100300_agenda_fase7f_lote.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261109100300', 'agenda_fase7f_lote');"
--
-- DESFAZER: reaplicar as definições de 20261031100985 (agenda_aviso_pecas) e 20261109100100 (agenda_comunicar_rodar); a de 20261030100500 (agenda_aviso_enfileirar) depois de
-- drop function public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz, boolean), com o revoke/grant de lá; o CHECK de volta (sem mensagem da semana na tabela):
--   alter table public.agenda_dono_avisos drop constraint dono_aviso_conta_mudanca,
--     add constraint agenda_dono_avisos_acao_ids_check check (cardinality(acao_ids) > 0);
--   drop function if exists public._agenda_comunicar_quinta(date, timestamptz), public._agenda_comunicar_lote_guardaria(date, timestamptz),
--     public._agenda_lote_texto(jsonb), public._agenda_lote_fora(jsonb), public._agenda_lote_mudancas(date), public._agenda_e_excecao(jsonb, date, timestamptz),
--     public._agenda_lote_cota(date), public._agenda_lote_ligado();
--
-- IDEMPOTENTE: o CHECK por nome em do $$, drop function if exists, create or replace function, revoke/grant e comment.

-- ── 1. A mensagem da semana sem mudança ─────────────────────────────────────────────────────────────
-- R8.5-12: agenda_dono_avisos.acao_ids tinha CHECK cardinality > 0 (20261030100300:121), e a quinta sai mesmo sem mudança quando há pergunta aberta. O nome do CHECK de antes é o automático
-- de uma coluna; ele sai de pg_constraint pela definição, e um nome que não bata para a migration (nada de drop calado no CHECK errado).
do $$
declare
  v_n    int;
  v_nome text;
begin
  if exists (select 1 from pg_constraint where conrelid = 'public.agenda_dono_avisos'::regclass and conname = 'dono_aviso_conta_mudanca') then
    return;
  end if;
  select count(*)::int, min(conname) into v_n, v_nome
    from pg_constraint
   where conrelid = 'public.agenda_dono_avisos'::regclass and contype = 'c'
     and pg_get_constraintdef(oid) = 'CHECK ((cardinality(acao_ids) > 0))';
  if v_n <> 1 then
    raise exception 'agenda_dono_avisos: esperava 1 CHECK "cardinality(acao_ids) > 0", achei %.', v_n;
  end if;
  execute format('alter table public.agenda_dono_avisos drop constraint %I', v_nome);
  alter table public.agenda_dono_avisos add constraint dono_aviso_conta_mudanca
    check (cardinality(acao_ids) > 0 or (dedupe_key like 'agenda-dono:semana:%' and cardinality(pergunta_ids) > 0));
end
$$;

comment on column public.agenda_dono_avisos.dedupe_key is
  'A chave da fila (a mesma rodada nunca entra duas vezes): agenda-dono:aviso:<a rodada em UTC>; (Fase 7f, P4) agenda-dono:excecao:<a rodada em UTC>, o aviso que saiu com o lote ligado (só a exceção, e conta na cota do dia), e agenda-dono:semana:<o dia>, a mensagem da quinta (uma por dia; a única que pode ir sem mudança, só com perguntas).';

-- ── 2. As peças de dentro ───────────────────────────────────────────────────────────────────────────
-- O2: sem o bloco ligado, o lote age como sombra. Guardar o que nenhum fechamento mostra seria calar o gestor. Os dois não respeitam o freio (R8.6): é forma de contar.
create or replace function public._agenda_lote_ligado()
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select public._agenda_fala_modo('lote') = 'ligado' and public._agenda_fala_modo('bloco') = 'ligado';
$function$;

comment on function public._agenda_lote_ligado() is
  'Agenda de Produção (Fase 7f, P4; §5.4, R8.6): o lote vale de verdade? _agenda_fala_modo(''lote'') e _agenda_fala_modo(''bloco'') em ligado (os dois sem freio). Fora disso, o aviso sai a cada rodada como antes e o lote só mede. STABLE, sem grant.';

-- §3.1 item 4: a exceção cabe no teto de acordes_dia_max, o mesmo que já conta os acordes (uma fonte só). Os acordes contados hoje são os de agenda_vigiar (a.dia = hoje, contada_via
-- acorde); os avisos de exceção são os que entraram na fila hoje com a chave agenda-dono:excecao (em qualquer estado, como o teto de _agenda_aviso_no_dia). Pode dar menos que zero.
create or replace function public._agenda_lote_cota(p_hoje date)
 returns integer
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf public.agenda_config := public._agenda_cfg();
begin
  if p_hoje is null then
    raise exception '_agenda_lote_cota: sem o dia.' using errcode = '22004';
  end if;
  return cf.acordes_dia_max
         - (select count(*)::int from public.agenda_acoes a where a.dia = p_hoje and a.contada_via = 'acorde')
         - (select count(*)::int from public.agenda_dono_avisos v
             where v.dia = p_hoje and v.fila_id is not null and v.dedupe_key like 'agenda-dono:excecao:%');
end;
$function$;

comment on function public._agenda_lote_cota(date) is
  'Agenda de Produção (Fase 7f, P4; §3.1 item 4, R8.5-27): quanto da cota do dia ainda cabe para a exceção — acordes_dia_max menos os acordes contados hoje (agenda_acoes.dia = hoje e contada_via acorde, a conta de agenda_vigiar) e os avisos de exceção que entraram na fila hoje (agenda_dono_avisos, chave agenda-dono:excecao). Pode ser menor que zero. STABLE, sem grant.';

-- §5.4: pelo _agenda_classe_da_saida dos ids do item, mais a ficha segurada do próximo dia útil (abaixo). O item é um grupo do *o que mudou* (acao_ids) ou uma pergunta (pergunta_id, pergunta_ids). A classe nula (sem dia) não é exceção:
-- espera o bloco, que a mostra. Item sem id nenhum e referência que não existe lançam: quem chama decide (o aviso trata a que lança como exceção, e ela sai como antes).
create or replace function public._agenda_e_excecao(p_item jsonb, p_hoje date, p_agora timestamptz)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ids  uuid[];
  v_pids uuid[];
  v_id   uuid;
  v_c    jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_e_excecao: sem o dia ou a hora.' using errcode = '22004';
  end if;
  v_ids := array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p_item -> 'acao_ids') = 'array' then p_item -> 'acao_ids' else '[]'::jsonb end) x);
  v_pids := array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p_item -> 'pergunta_ids') = 'array' then p_item -> 'pergunta_ids' else '[]'::jsonb end) x)
            || case when nullif(p_item ->> 'pergunta_id', '') is not null then array[(p_item ->> 'pergunta_id')::uuid] else '{}'::uuid[] end;
  if cardinality(v_ids) + cardinality(v_pids) = 0 then
    raise exception '_agenda_e_excecao: o item não traz ação nem pergunta.' using errcode = '22023';
  end if;
  foreach v_id in array v_ids loop
    v_c := public._agenda_classe_da_saida('acao', v_id, p_hoje, p_agora);
    if coalesce((v_c ->> 'excecao')::boolean, false) then
      return true;
    end if;
    -- A ficha que eu segurei para hoje ou o próximo dia útil ("Fale com Alex"): a pessoa não sabe que tem serviço, e só o dono pode avisar antes do dia. A classe do P1 não a
    -- conta (ninguém soube); a produção mostra que é o caso que mais pesa: 3 dos 5 avisos de 03 a 07/11 eram ela, para o dia seguinte ou o mesmo dia.
    if v_c ->> 'classe' = 'mudanca' and (v_c ->> 'dia')::date <= public.agenda_somar_du(p_hoje, 1)
       and exists (select 1 from public.agenda_acoes a where a.id = v_id and a.tipo = 'equipe' and a.depois ->> 'motivo' = 'ficha_segurada') then
      return true;
    end if;
  end loop;
  foreach v_id in array v_pids loop
    if coalesce((public._agenda_classe_da_saida('pergunta', v_id, p_hoje, p_agora) ->> 'excecao')::boolean, false) then
      return true;
    end if;
  end loop;
  return false;
end;
$function$;

comment on function public._agenda_e_excecao(jsonb, date, timestamptz) is
  'Agenda de Produção (Fase 7f, P4; §3.1 item 4, §5.4): o item ({acao_ids} de um grupo do *o que mudou*, ou {pergunta_id}/{pergunta_ids}) é exceção, pelo _agenda_classe_da_saida de cada id: o dia mais cedo até o próximo dia útil e a mudança mexe no que a equipe ou o cliente já sabem, a falta de alguém para hoje ou o próximo dia útil, ou a crítica que perde até lá; e (desta etapa) a ficha que o gestor segurou para hoje ou o próximo dia útil (equipe, ficha_segurada), que só o dono pode avisar antes do dia. Classe sem dia = não é. Item sem id = 22023; referência que não existe = P0002. STABLE, sem grant.';

-- ── 3. As peças da mensagem da semana ───────────────────────────────────────────────────────────────
-- O que mudou e não foi contado, como o aviso conta (_agenda_aviso_mudancas), com a mesma correção da OS em duas linhas que agenda_aviso_pecas faz (7a correção 2): a linha do estimar
-- não repete o *desfaz* quando a mesma OS tem marcação no mesmo texto. É a mesma expressão de agenda_aviso_pecas, aqui sem o lote: a quinta conta tudo o que esperou.
create or replace function public._agenda_lote_mudancas(p_hoje date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with m as (select public._agenda_aviso_mudancas(p_hoje) as v)
  select coalesce((select jsonb_agg(case
             when (select bool_and(a.tipo = 'estimar') from public.agenda_acoes a
                    where a.id in (select y::uuid from jsonb_array_elements_text(e -> 'acao_ids') y))
                  and exists (select 1 from jsonb_array_elements(m.v) with ordinality t2(e2, o2), public.agenda_acoes a2
                               where o2 <> o and a2.id in (select y::uuid from jsonb_array_elements_text(e2 -> 'acao_ids') y)
                                 and a2.tipo in ('publicar', 'criar', 'mover', 'promover_reserva')
                                 and (e2 -> 'os') ?| array(select jsonb_array_elements_text(e -> 'os')))
             then jsonb_set(e, '{texto}', to_jsonb(regexp_replace(e ->> 'texto', '\s*\*desfaz [^*]+\* volta( como estava)?\.\s*$', '')))
             else e end order by o)
            from jsonb_array_elements(m.v) with ordinality t(e, o)), m.v)
    from m;
$function$;

comment on function public._agenda_lote_mudancas(date) is
  'Agenda de Produção (Fase 7f, P4; §5.4): o que a mensagem da semana conta — _agenda_aviso_mudancas(p_hoje), com a correção da OS em duas linhas de agenda_aviso_pecas (a linha do estimar sem o *desfaz* quando a mesma OS tem marcação no mesmo texto). Sem o filtro do lote: a quinta conta tudo o que esperou. STABLE, sem grant.';

-- O que ficou de fora, pelas propostas das mudanças, como agenda_aviso_pecas monta (a de cada OS pela proposta mais nova), sem as OS que mudaram. Nada = null.
create or replace function public._agenda_lote_fora(p_m jsonb)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select public._agenda_aviso_fora_texto(
           (select coalesce(jsonb_agg(y.f order by y.ord, y.o), '[]'::jsonb)
              from (select distinct on (coalesce(t.f ->> 'os', t.f ->> 'numero')) t.f, t.o, t.ord
                      from (select f, o, dense_rank() over (order by p.criada_em desc, p.id) as ord
                              from public.agenda_propostas p
                              cross join lateral jsonb_array_elements(p.fora) with ordinality u(f, o)
                             where p.id = any (array(select distinct x::uuid from jsonb_array_elements(coalesce(p_m, '[]'::jsonb)) g,
                                                                                jsonb_array_elements_text(g -> 'propostas') x))) t
                     order by coalesce(t.f ->> 'os', t.f ->> 'numero'), t.ord, t.o) y),
           array(select distinct x::uuid from jsonb_array_elements(coalesce(p_m, '[]'::jsonb)) g, jsonb_array_elements_text(g -> 'os') x));
$function$;

comment on function public._agenda_lote_fora(jsonb) is
  'Agenda de Produção (Fase 7f, P4; §5.4): a linha do que ficou de fora para as mudanças p_m (os grupos de _agenda_aviso_mudancas), como agenda_aviso_pecas a monta: o fora das propostas delas, a de cada OS pela mais nova, sem as OS que mudaram (_agenda_aviso_fora_texto). Nada = null. STABLE, sem grant.';

-- O texto inteiro das peças, como o montador (_shared/agenda/aviso-do-gestor.ts, juntar) o junta quando cabe no teto: o cabeçalho, "• " + cada mudança, o de fora, o rodapé, a linha em
-- branco e as perguntas. É o que a sombra guarda (quinta_diria); o corte pelo teto é só do montador, e a sombra diz se cabe. O O4 e o teste do montador conferem o mesmo texto.
create or replace function public._agenda_lote_texto(p_pecas jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select concat_ws(E'\n', nullif(btrim(p_pecas ->> 'cabecalho'), ''),
                   (select string_agg('• ' || btrim(m ->> 'texto'), E'\n' order by o)
                      from jsonb_array_elements(case when jsonb_typeof(p_pecas -> 'mudancas') = 'array' then p_pecas -> 'mudancas' else '[]'::jsonb end) with ordinality t(m, o)
                     where nullif(btrim(m ->> 'texto'), '') is not null),
                   nullif(btrim(p_pecas ->> 'fora'), ''), nullif(btrim(p_pecas ->> 'rodape'), ''))
         || coalesce(E'\n\n' || nullif(btrim(p_pecas #>> '{perguntas,texto}'), ''), '');
$function$;

comment on function public._agenda_lote_texto(jsonb) is
  'Agenda de Produção (Fase 7f, P4; §5.4): o texto inteiro das peças do aviso (cabeçalho, "• " + cada mudança, o de fora, o rodapé, a linha em branco e as perguntas), o mesmo que _shared/agenda/aviso-do-gestor.ts junta quando cabe no teto. A sombra da quinta guarda este texto. IMMUTABLE, sem grant.';

-- ── 4. A quinta ─────────────────────────────────────────────────────────────────────────────────────
-- §5.4, R8.5-12 a 14, d12: o passo quinta de agenda_comunicar_rodar. Só no dia_do_plano, no 1º tique depois de dono_semana_hora, uma vez (a chave agenda-dono:semana:<dia>, que o bloco do
-- P3 lê para dizer "a semana que vem foi às HH:MM"), com dono_semana_aviso = propria (AG7-22) e o lote ligado de verdade. Devolve as peças em avisos, e o task-automations as monta e
-- enfileira com p_semana: a origem é agenda-dono, a fonte que a trava do "1" lê (R8.7). Sai mesmo sem mudança, com pergunta aberta (O4b). Até perguntas_abertas_max linhas, na ordem
-- de agenda_perguntas_em_ordem, com o número de agenda_decisoes_abertas dentro da linha: "Decisão N:" (R8.7). O texto cabe no teto do aviso (gestor_aviso_texto_max, R8.5-13): quem
-- corta é o montador.
-- O prazo: veto_ate da linha é o que está NO texto, nulo em sombra e com o freio (P2). agenda_aviso_conferir não é recriada (R8.1): ela conta as perguntas como mostradas quando a fila
-- manda. Depois disso, no tique seguinte, este passo grava o prazo de cada pergunta cuja linha, refeita na hora do envio, está no texto que saiu; e veto_teria_em pelo veto_diria, como o
-- registrar do P3. Só de nulo a valor: o prazo que já existia fica (_agenda_perguntas_antes).
-- Em sombra (o lote em sombra, ou ligado sem o bloco ligado): só contagens.quinta.quinta_diria, com o texto, uma vez por dia (a rodada comunicar de hoje que já disse).
create or replace function public._agenda_comunicar_quinta(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_cab_mudou constant text := 'Agenda — o que eu mudei sozinho:';
  c_cab_nada  constant text := 'Agenda — a semana que vem:';
  c_rodape    constant text := '*agenda plano* mostra tudo.';
  c_preciso   constant text := 'Para a semana que vem preciso de:';
  c_audio     constant text := 'Pode ser um áudio só, citando o nome do cliente.';
  cf      public.agenda_config := public._agenda_cfg();
  v       public.agenda_dono_avisos;
  v_lig   boolean;
  v_m     jsonb;
  v_nm    int;
  v_lin   text[] := '{}';
  v_ids   uuid[] := '{}';
  v_tot   int := 0;
  v_perg  jsonb;
  v_pecas jsonb;
  v_txt   text;
  v_l     jsonb;
  v_pr    int := 0;
  r       record;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da mensagem da semana.' using errcode = '22023';
  end if;
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano then
    return jsonb_build_object('pulado', true, 'motivo', 'dia');
  end if;
  -- d12: com 'fechamento', a semana vai no bloco da quinta (a parte semana do P3), nada aqui
  if cf.dono_semana_aviso <> 'propria' then
    return jsonb_build_object('pulado', true, 'motivo', 'fechamento');
  end if;
  if public._agenda_fala_modo('lote') = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado');
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.dono_semana_hora then
    return jsonb_build_object('pulado', true, 'motivo', 'cedo');
  end if;

  -- uma vez: a chave do dia. Saiu (a fila mandou e agenda_aviso_conferir contou as perguntas): o prazo que estava no texto.
  select * into v from public.agenda_dono_avisos x where x.dedupe_key = 'agenda-dono:semana:' || p_hoje::text;
  if found then
    if v.estado = 'enviada' then
      for r in select q.id from public.agenda_perguntas q
                where q.id = any (v.pergunta_ids) and q.estado = 'aberta' and q.veto_espera is null
                  and q.veto_ate is null and q.veto_teria_em is null and q.mostrada_em = v.enviada_em
                order by q.id loop
        v_l := public._agenda_pergunta_linha(r.id, p_hoje, v.enviar_em);
        continue when position(('· ' || (v_l ->> 'texto')) in v.texto) = 0;
        update public.agenda_perguntas q
           set veto_ate = (v_l ->> 'veto_ate')::timestamptz, veto_teria_em = (v_l ->> 'veto_diria')::timestamptz
         where q.id = r.id and q.veto_ate is null and q.veto_teria_em is null
           and (v_l ->> 'veto_ate' is not null or v_l ->> 'veto_diria' is not null);
        if found then
          v_pr := v_pr + 1;
        end if;
      end loop;
    end if;
    return jsonb_build_object('ja_saiu', true, 'estado', v.estado)
           || case when v_pr > 0 then jsonb_build_object('prazos', v_pr) else '{}'::jsonb end;
  end if;

  v_lig := public._agenda_lote_ligado();
  if not v_lig and exists (select 1 from public.agenda_vigia_rodadas x
                            where x.rotina = 'comunicar' and x.p_hoje = p_hoje and x.contagens #> '{quinta,quinta_diria}' is not null) then
    return jsonb_build_object('ja_diria', true);
  end if;

  -- o que mudou e não foi contado, e as perguntas na ordem, menos as que o dono já escolheu
  v_m := public._agenda_lote_mudancas(p_hoje);
  v_nm := jsonb_array_length(v_m);
  for r in select e, (e ->> 'id')::uuid as id
             from jsonb_array_elements(public.agenda_perguntas_em_ordem(p_hoje, p_agora)) e
             join public.agenda_perguntas q on q.id = (e ->> 'id')::uuid
            where q.opcao_escolhida is null and nullif(btrim(e ->> 'linha'), '') is not null
            order by (e ->> 'ordem')::int loop
    v_tot := v_tot + 1;
    if v_tot <= cf.perguntas_abertas_max then
      v_lin := v_lin || ('· ' || (r.e ->> 'linha'));
      v_ids := v_ids || r.id;
    end if;
  end loop;
  if v_nm = 0 and v_tot = 0 then
    return case when v_lig then jsonb_build_object('motivo', 'nada')
                else jsonb_build_object('quinta_diria', jsonb_build_object('texto', null, 'motivo', 'nada')) end;
  end if;
  if v_tot > 0 then
    v_perg := jsonb_build_object('texto', c_preciso || E'\n' || array_to_string(v_lin, E'\n')
                                          || case when v_tot > cardinality(v_lin) then E'\n' || format('(e mais %s em *agenda pendências*)', v_tot - cardinality(v_lin)) else '' end
                                          || E'\n' || c_audio,
                                 'pergunta_ids', to_jsonb(v_ids));
  end if;
  v_pecas := jsonb_build_object(
    'avisar', true, 'semana', true, 'rodada', p_agora, 'dia', p_hoje, 'limite', cf.gestor_aviso_texto_max,
    'cabecalho', case when v_nm > 0 then c_cab_mudou else c_cab_nada end,
    'mudancas', (select coalesce(jsonb_agg(jsonb_build_object('texto', g ->> 'texto', 'acao_ids', g -> 'acao_ids') order by o), '[]'::jsonb)
                   from jsonb_array_elements(v_m) with ordinality t(g, o)),
    'fora', case when v_nm > 0 then public._agenda_lote_fora(v_m) end,
    'rodape', c_rodape, 'perguntas', v_perg, 'perguntas_erro', null);
  if not v_lig then
    v_txt := public._agenda_lote_texto(v_pecas);
    return jsonb_build_object('quinta_diria', jsonb_build_object(
      'texto', v_txt, 'caracteres', char_length(v_txt), 'cabe', char_length(v_txt) <= cf.gestor_aviso_texto_max, 'mudancas', v_nm,
      'acao_ids', to_jsonb(array(select x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'acao_ids') x)),
      'perguntas', cardinality(v_ids), 'pergunta_ids', to_jsonb(v_ids), 'perguntas_abertas', v_tot));
  end if;
  return jsonb_build_object('avisos', jsonb_build_array(v_pecas), 'mudancas', v_nm, 'perguntas', cardinality(v_ids));
end;
$function$;

comment on function public._agenda_comunicar_quinta(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P4; §5.4, §6.3, R8.5-12 a 14, AG7-22): o passo quinta da rodada comunicar. Só no dia_do_plano ({pulado, motivo dia}), com dono_semana_aviso = propria ({pulado, motivo fechamento}: a semana vai no bloco), com o lote fora de desligado ({pulado, motivo desligado}) e a partir de dono_semana_hora ({pulado, motivo cedo}). Uma vez por dia, pela chave agenda-dono:semana:<dia>: a 2ª vez = {ja_saiu, estado}, e, depois que a fila mandou, grava o prazo (veto_ate) e o que seria (veto_teria_em) de cada pergunta cuja linha está no texto que saiu ({prazos}). Com o lote ligado de verdade (_agenda_lote_ligado): {avisos: [as peças, como as de agenda_aviso_pecas, com semana = true]} — o cabeçalho, o que mudou e não foi contado (_agenda_lote_mudancas), o de fora, o rodapé e "Para a semana que vem preciso de:" com até perguntas_abertas_max linhas de agenda_perguntas_em_ordem, "(e mais N em *agenda pendências*)" e "Pode ser um áudio só, citando o nome do cliente.". Sai mesmo sem mudança, com pergunta; sem nada = {motivo nada}. Em sombra: {quinta_diria: {texto, caracteres, cabe, mudancas, acao_ids, perguntas, pergunta_ids}}, uma vez por dia ({ja_diria}). Volatile, sem grant.';

-- ── 5. O que o lote guarda, para medir e para a saúde ───────────────────────────────────────────────
-- Em sombra: o aviso desta rodada (o task-automations chama a rodada comunicar com o mesmo instante da vigia e do aviso) e o que o lote teria guardado dele — as ações dos grupos que não são
-- exceção e as perguntas da rodada de aprontar (O7) — e a exceção que teria passado da cota. Com o lote ligado: quanto cabe na cota, e, sem cota, a exceção que espera o bloco (é dela
-- que o P7 conta "a exceção acima do teto" na saúde, R8.5-27). Desligado: nada (a chave não aparece). Sem aviso na rodada, em sombra, e com cota no ligado, só uma ou duas leituras.
create or replace function public._agenda_comunicar_lote_guardaria(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v        public.agenda_dono_avisos;
  v_g      jsonb;
  v_exc    boolean;
  v_gids   uuid[];
  v_leva   uuid[] := '{}';
  v_guarda uuid[] := '{}';
  v_cota   int;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_comunicar_lote_guardaria: sem o dia ou a hora.' using errcode = '22004';
  end if;
  if public._agenda_fala_modo('lote') = 'desligado' then
    return null;
  end if;
  if public._agenda_lote_ligado() then
    v_cota := public._agenda_lote_cota(p_hoje);
    if v_cota > 0 or not exists (select 1 from public.agenda_acoes a
                                  where a.dia between p_hoje - 6 and p_hoje and a.executada and a.contada_em is null and a.desfeita_em is null
                                    and a.origem in ('motor', 'vigia')) then
      return jsonb_build_object('modo', 'ligado', 'cota_livre', greatest(v_cota, 0));
    end if;
    for v_g in select g from jsonb_array_elements(public._agenda_aviso_mudancas(p_hoje)) g loop
      begin
        v_exc := public._agenda_e_excecao(v_g, p_hoje, p_agora);
      exception when others then
        v_exc := true;
      end;
      if v_exc then
        v_leva := v_leva || array(select x::uuid from jsonb_array_elements_text(v_g -> 'acao_ids') x);
      end if;
    end loop;
    return jsonb_build_object('modo', 'ligado', 'cota_livre', 0, 'acima_da_cota', cardinality(v_leva), 'acima_da_cota_ids', to_jsonb(v_leva));
  end if;

  select * into v from public.agenda_dono_avisos x where x.rodada = p_agora and x.dedupe_key like 'agenda-dono:aviso:%';
  if not found then
    return jsonb_build_object('modo', 'sombra');
  end if;
  -- os grupos do *o que mudou* que o aviso levou: o mesmo agrupamento, agora com o contado (o aviso acabou de contar)
  for v_g in select g from jsonb_array_elements(public._agenda_mudancas(p_hoje - 6, p_hoje, true, false, null)) g
              where exists (select 1 from jsonb_array_elements_text(g -> 'acao_ids') x where x::uuid = any (v.acao_ids)) loop
    v_gids := array(select x::uuid from jsonb_array_elements_text(v_g -> 'acao_ids') x where x::uuid = any (v.acao_ids));
    begin
      v_exc := public._agenda_e_excecao(jsonb_build_object('acao_ids', to_jsonb(v_gids)), p_hoje, p_agora);
    exception when others then
      v_exc := true;
    end;
    if v_exc then
      v_leva := v_leva || v_gids;
    else
      v_guarda := v_guarda || v_gids;
    end if;
  end loop;
  -- o que o aviso levou e não está em grupo nenhum: conta como levado (nada some da conta)
  v_leva := v_leva || array(select x from unnest(v.acao_ids) x where not (x = any (v_leva || v_guarda)));
  v_cota := public._agenda_lote_cota(p_hoje);
  return jsonb_build_object(
    'modo', 'sombra', 'aviso', v.id,
    'levaria', jsonb_build_object('acoes', cardinality(v_leva), 'ids', to_jsonb(v_leva)),
    'guardaria', jsonb_build_object('acoes', cardinality(v_guarda), 'ids', to_jsonb(v_guarda),
                                    'perguntas', cardinality(v.pergunta_ids), 'pergunta_ids', to_jsonb(v.pergunta_ids)),
    'acima_da_cota', case when cardinality(v_leva) > 0 and v_cota <= 0 then cardinality(v_leva) else 0 end);
end;
$function$;

comment on function public._agenda_comunicar_lote_guardaria(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P4; §5.4, R8.5-27): o que vai em contagens.lote_guardaria da rodada comunicar. Lote desligado = null. Ligado de verdade (_agenda_lote_ligado): {modo ligado, cota_livre} e, sem cota e com mudança por contar, {acima_da_cota, acima_da_cota_ids}: a exceção que espera o bloco (é dali que o P7 conta a exceção acima do teto). Em sombra (o lote em sombra, ou ligado sem o bloco ligado): {modo sombra} sem aviso nesta rodada (agenda_dono_avisos.rodada = p_agora, o instante da vigia); com ele, {aviso, levaria: {acoes, ids}, guardaria: {acoes, ids, perguntas, pergunta_ids}, acima_da_cota}. STABLE, sem grant.';

-- ── 6. As recriadas (o corpo da definição mais nova; a mudança só nos blocos "-- FASE 7f:") ──────────
-- Quem recriar de novo copia DESTA migration.

-- agenda_aviso_pecas (de 20261031100985_agenda_fase77a_correcao2.sql)
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
  -- FASE 7f: (7f P4) o lote
  v_7f_lote  boolean := false;
  v_7f_todas int;
  v_7f_leva  jsonb;
  v_7f_g     jsonb;
  v_7f_exc   boolean;
  -- FASE 7f: fim
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
  -- FASE 7f: (7f P4, §5.4, R8.5-14, R8.5-27, R8.6, R8.13) o lote. Com modo_lote_dono E modo_bloco_agenda ligados (_agenda_lote_ligado: sem o bloco, o lote age como sombra, O2), a
  -- rodada só leva a exceção (_agenda_e_excecao): o resto fica com contada_em nulo e sai no bloco do próximo fechamento, que o registra. A exceção também espera o bloco quando a cota do
  -- dia acabou (_agenda_lote_cota: acordes_dia_max menos os acordes e os avisos de exceção de hoje), sem frase nenhuma (R8.5-27). A classificação que lança não cala a mudança: ela
  -- sai, como antes. O lote não respeita o freio (R8.6). Em sombra nada disto roda, e o aviso é o de antes; o que o lote guardaria a rodada comunicar mede (contagens.lote_guardaria).
  -- Depois de v_n = 0 e das esperas de antes: a rodada sem nada (ou fora da janela, na pausa, no teto, sem o dono) não lê nada novo.
  if public._agenda_lote_ligado() then
    v_7f_lote := true;
    v_7f_todas := v_n;
    v_7f_leva := '[]'::jsonb;
    for v_7f_g in select g from jsonb_array_elements(v_m) with ordinality t(g, o) order by o loop
      begin
        v_7f_exc := public._agenda_e_excecao(v_7f_g, p_hoje, p_agora);
      exception when others then
        v_7f_exc := true;
      end;
      if v_7f_exc then
        v_7f_leva := v_7f_leva || jsonb_build_array(v_7f_g);
      end if;
    end loop;
    v_m := v_7f_leva;
    v_n := jsonb_array_length(v_m);
    if v_n = 0 then
      return jsonb_build_object('avisar', false, 'motivo', 'lote', 'pendentes', v_7f_todas);
    end if;
    if public._agenda_lote_cota(p_hoje) <= 0 then
      return jsonb_build_object('avisar', false, 'motivo', 'cota', 'pendentes', v_7f_todas, 'excecoes', v_n);
    end if;
  end if;
  -- FASE 7f: fim

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

  -- FASE 7f: (7f P4, R8.5-14, O7) com o lote, a rodada de aprontar não sai no aviso: as perguntas vão no bloco do fechamento e na mensagem da quinta, na ordem de
  -- agenda_perguntas_em_ordem. Sem o lote, a de antes (o if abre aqui e fecha no bloco de baixo, para o corpo sem os blocos seguir igual à origem).
  if not v_7f_lote then
  -- FASE 7f: fim
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
  -- FASE 7f: (7f P4) o fim do if de cima
  end if;
  -- FASE 7f: fim

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
  'Agenda de Produção (correção de 29/10, P4): as peças do aviso do gestor ao dono, sem gravar nada (o texto é montado em _shared/agenda/aviso-do-gestor.ts). Não avisa (avisar false + motivo): modo, desligado (gestor_aviso_dia_max 0), nada_mudou, fora_da_janela (+ pendentes: sai junto na abertura), teto (+ pendentes), sem_dono. Avisa: {rodada, dia, limite (gestor_aviso_texto_max), cabecalho, mudancas [{texto do *o que mudou*, acao_ids}] (_agenda_aviso_mudancas), fora (_agenda_aviso_fora_texto, pelas propostas das mudanças), rodape, perguntas {texto de agenda_aprontar, pergunta_ids que ele cobre, oss, voce} — uma vez por dia — ou null, perguntas_erro (a rodada de aprontar falhou: o que mudou sai do mesmo jeito; o passo do motor registra o erro)}. STABLE, definer, só o service_role. CORREÇÃO 29/10 (revisão): (1) de segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, não avisa (motivo fechamento, + pendentes): o fechamento das 17:30 conta o que estiver por contar, e o resto sai no 1º aviso depois; (2) as perguntas saem uma vez por dia: se alguma das que o texto cobre já foi mostrada hoje (fechamento, conversa, acorde), ficam para amanhã. CORREÇÃO DA 7a (revisão da etapa; achado 15): as perguntas que o texto da rodada de aprontar cobre incluem as do gestor (situacao e estimativa) das OS que ele lista — a restrição da OS diz o que o gestor faz sem resposta; com o aviso enviado, elas contam como mostradas e o prazo delas vale. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): (a OS em duas linhas) a linha do estimar do gestor não repete o "*desfaz <nome>* volta." quando a mesma OS tem marcação no mesmo aviso; (as perguntas vistas sem o prazo) com perguntas do gestor de prazo entre as que o aviso conta como mostradas, o texto das perguntas termina "Sem resposta até qua 04/11 às 18:00, faço o que eu disse.". Sem o gestor, a de antes. FASE 7f (P4; §5.4, R8.5-14, R8.5-27): com o lote ligado de verdade (_agenda_lote_ligado: modo_lote_dono e modo_bloco_agenda em ligado, sem freio), a rodada só leva a exceção (_agenda_e_excecao; a que lança sai, como antes) e sem a rodada de aprontar; nenhuma exceção = {avisar false, motivo lote, pendentes}; a cota do dia acabou (_agenda_lote_cota) = {avisar false, motivo cota, pendentes, excecoes}: o resto fica com contada_em nulo para o bloco do fechamento. Depois de v_n = 0 e das esperas de antes; com o lote em sombra (ou sem o bloco ligado), a de antes, byte a byte.';

-- agenda_aviso_enfileirar (de 20261030100500_agenda_correcao_revisao.sql). R8.5-16: create or replace com outra lista de argumentos cria uma SEGUNDA função, e o PostgREST não escolhe entre as duas
-- (PGRST203): a de 6 argumentos sai antes, e o revoke/grant vem de novo abaixo. O O6 reprova com 2 assinaturas.
drop function if exists public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz);
create or replace function public.agenda_aviso_enfileirar(p_texto text, p_acao_ids uuid[], p_pergunta_ids uuid[],
                                                          p_com_perguntas boolean, p_hoje date, p_agora timestamptz,
                                                          p_semana boolean default false)
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
  -- FASE 7f: (7f P4) a mensagem da semana e o lote
  v_7f_semana boolean := coalesce(p_semana, false);
  v_7f_lote   boolean := false;
  -- FASE 7f: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aviso_enfileirar: sem o dia ou a hora' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_texto, '')), '') is null or char_length(p_texto) > cf.gestor_aviso_texto_max then
    raise exception 'O aviso veio sem texto ou maior que gestor_aviso_texto_max (% letras).', cf.gestor_aviso_texto_max
      using errcode = '22023';
  end if;
  -- FASE 7f: (7f P4, R8.5-12, O4b) a mensagem da semana pode ir sem mudança, com pergunta; sem nenhuma das duas, nada a mandar (a quinta só devolve peças com uma delas). O aviso de
  -- sempre continua contando pelo menos uma mudança (o if abre aqui e fecha no bloco de baixo, para o corpo sem os blocos seguir igual à origem).
  if v_7f_semana and coalesce(cardinality(p_acao_ids), 0) = 0 and coalesce(cardinality(p_pergunta_ids), 0) = 0 then
    raise exception 'A mensagem da semana leva pelo menos uma mudança ou uma pergunta.' using errcode = '22023';
  end if;
  if not v_7f_semana then
  -- FASE 7f: fim
  if coalesce(cardinality(p_acao_ids), 0) = 0 then
    raise exception 'O aviso conta pelo menos uma mudança.' using errcode = '22023';
  end if;
  -- FASE 7f: (7f P4) o fim do if de cima
  end if;
  -- FASE 7f: fim
  -- o teto é contado e a linha entra numa vez só, mesmo com dois tiques do motor ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext('agenda_dono_aviso'));
  if not public._agenda_aviso_ligado() then
    return jsonb_build_object('enfileirou', false, 'motivo', 'modo');
  end if;
  select v.id into v_id from public.agenda_dono_avisos v where v.rodada = p_agora;
  if v_id is not null then
    return jsonb_build_object('enfileirou', false, 'motivo', 'ja_existe', 'id', v_id);
  end if;
  -- FASE 7f: (7f P4, §5.4, AG7-22) o lote e a semana, sob a trava. A semana é uma por dia (a chave agenda-dono:semana:<dia>, que o bloco da quinta lê), e só sai com o lote ligado de
  -- verdade e dono_semana_aviso = propria: o que _agenda_comunicar_quinta conferiu, de novo aqui.
  v_7f_lote := public._agenda_lote_ligado();
  if v_7f_semana then
    select v.id into v_id from public.agenda_dono_avisos v where v.dedupe_key = 'agenda-dono:semana:' || p_hoje::text;
    if v_id is not null then
      return jsonb_build_object('enfileirou', false, 'motivo', 'ja_existe', 'id', v_id);
    end if;
    if not v_7f_lote or cf.dono_semana_aviso <> 'propria' then
      return jsonb_build_object('enfileirou', false, 'motivo', 'modo');
    end if;
  end if;
  -- FASE 7f: fim
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
  -- FASE 7f: (7f P4, R8.5-27) com o lote, o aviso é o da exceção, e a exceção acima da cota do dia espera o bloco: a conta de agenda_aviso_pecas, de novo sob a trava (dois tiques ao
  -- mesmo tempo não passam juntos). A mensagem da semana não conta na cota: ela é o lote.
  if v_7f_lote and not v_7f_semana and public._agenda_lote_cota(p_hoje) <= 0 then
    return jsonb_build_object('enfileirou', false, 'motivo', 'cota');
  end if;
  -- FASE 7f: fim
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
  -- FASE 7f: (7f P4) a chave diz o que é: a semana (uma por dia) e a exceção (a que conta na cota do dia, _agenda_lote_cota)
  if v_7f_semana then
    v_chave := 'agenda-dono:semana:' || p_hoje::text;
  elsif v_7f_lote then
    v_chave := 'agenda-dono:excecao:' || to_char(p_agora at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"."US');
  end if;
  -- FASE 7f: fim
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

comment on function public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz, boolean) is
  'Agenda de Produção (correção de 29/10, P4): a 1ª trava do aviso do gestor — sob a trava, de novo: o modo (_agenda_aviso_ligado), a rodada (uma por rodada: ja_existe), a janela (_agenda_aviso_fora_da_janela: fora_da_janela), o teto (_agenda_aviso_no_dia ≥ gestor_aviso_dia_max: teto), o dono (_agenda_aviso_dono: sem_dono) e as ações ainda por contar (_agenda_aviso_mudancas: mudou) — nesses casos nada é gravado. Senão registra em agenda_dono_avisos, põe na fila (source agenda-dono, source_ref_id = o aviso, a chave agenda-dono:aviso:<rodada>, priority 1, às p_agora, as tentativas que cabem na janela) e conta as ações (contada_em p_agora, contada_via aviso: provisório até o conferir). O 23514 da trava da fila vira o aviso recusado e devolvido. Texto vazio, maior que gestor_aviso_texto_max ou sem ação = 22023. Definer, só o service_role. CORREÇÃO 29/10 (revisão): (1) o prazo do *desfaz* das ações contadas vai a p_agora + desfazer_validade já no enfileirar (nunca menos; o conferir ainda o leva à hora do envio), e o *desfaz* que o aviso promete vale desde que ele sai; (2) de segunda a sexta, de gestor_aviso_pausa_inicio a gestor_aviso_pausa_fim, não enfileira (motivo fechamento): o fechamento das 17:30 conta o que estiver por contar, sem corrida. FASE 7f (P4; §5.4, R8.5-12, R8.5-16, R8.5-27): p_semana (default false; a assinatura de 6 argumentos saiu) é a mensagem da quinta — uma por dia (a chave agenda-dono:semana:<dia>; a 2ª = ja_existe), só com o lote ligado de verdade e dono_semana_aviso = propria (senão modo), e pode ir sem mudança, com pergunta (sem as duas = 22023). Com o lote ligado, o aviso de sempre é o da exceção (a chave agenda-dono:excecao:<rodada>) e acima da cota do dia não entra (cota).';

-- agenda_comunicar_rodar (de 20261109100100_agenda_fase7f_perguntas.sql)
create or replace function public.agenda_comunicar_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos constant text[] := array['destrava', 'teto', 'quinta', 'previsto', 'mudancas_equipe', 'convites', 'convites_vencidos'];
  cf       public.agenda_config;
  v_t0     timestamptz := clock_timestamp();
  v_modos  jsonb;
  v_passo  text;
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
  v_erros  int := 0;
  v_falhas jsonb := '[]'::jsonb;
  v_parou  text;
  v_estado text;
  v_msg    text;
  -- FASE 7f: (7f P4) o pré-passo do lote
  v_7f_r   jsonb;
  -- FASE 7f: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada comunicar.' using errcode = '22023';
  end if;
  if extract(isodow from p_hoje)::int = 7 then
    return jsonb_build_object('rodou', false, 'motivo', 'domingo');
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  if not pg_try_advisory_xact_lock(hashtext('agenda_comunicar')) then
    return jsonb_build_object('rodou', false, 'ocupado', true);
  end if;
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('bloco', public._agenda_fala_modo('bloco'), 'lote', public._agenda_fala_modo('lote'), 'veto', public._agenda_fala_modo('veto'),
                                'previsto', public._agenda_fala_modo('previsto'), 'convite', public._agenda_fala_modo('convite'),
                                'camadas', public._agenda_fala_modo('camadas'));
  if not exists (select 1 from jsonb_each_text(v_modos) m where m.value <> 'desligado') then
    return jsonb_build_object('rodou', false, 'modos', v_modos);
  end if;

  -- FASE 7f: (7f P4, §5.4, R8.5-27) antes dos passos, contagens.lote_guardaria: em sombra, o que o lote teria guardado do aviso desta rodada (o task-automations chama a rodada com o
  -- instante da vigia e do aviso); ligado, a exceção acima da cota, que espera o bloco. Com o lote desligado, nada (a chave não aparece). Erro aqui não derruba a rodada: registra em
  -- comunicar:lote_guardaria, como um passo, e os passos rodam; o relógio de cada passo continua mandando.
  begin
    v_7f_r := public._agenda_comunicar_lote_guardaria(p_hoje, p_agora);
    if v_7f_r is not null then
      v_cont := v_cont || jsonb_build_object('lote_guardaria', v_7f_r);
    end if;
  exception
    when query_canceled then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', 'lote_guardaria', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('rodada comunicar, passo lote_guardaria: %s', v_msg), 'agenda', 'comunicar:lote_guardaria', 'error',
                                   jsonb_build_object('passo', 'lote_guardaria', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', 'lote_guardaria', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('rodada comunicar, passo lote_guardaria: %s', v_msg), 'agenda', 'comunicar:lote_guardaria', 'error',
                                   jsonb_build_object('passo', 'lote_guardaria', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;
  -- FASE 7f: fim
  foreach v_passo in array c_passos loop
    if clock_timestamp() - v_t0 > cf.comunicar_tempo_max then
      v_parou := v_passo;
      exit;
    end if;
    if to_regprocedure(format('public.%I(date, timestamp with time zone)', '_agenda_comunicar_' || v_passo)) is null then
      v_cont := v_cont || jsonb_build_object(v_passo, jsonb_build_object('pulado', true, 'motivo', 'ainda não existe'));
      continue;
    end if;
    begin
      execute format('select public.%I($1, $2)', '_agenda_comunicar_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception
      when query_canceled then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_parou := v_passo;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('rodada comunicar, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg), 'agenda',
                                     'comunicar:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                        'tempo_max', cf.comunicar_tempo_max::text));
        exit;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('rodada comunicar, passo %s: %s', v_passo, v_msg), 'agenda', 'comunicar:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  v_cont := v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas)
            || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia, v_cont, least(v_erros, 32767),
          greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int), 'comunicar', cf.modo_equipe, cf.modo_diaria);
  return jsonb_build_object('rodou', true, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'parou_no', v_parou,
                            'avisos', coalesce(v_cont #> '{quinta,avisos}', '[]'::jsonb));
end;
$function$;

comment on function public.agenda_comunicar_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P2; §5.2, R8.5-7 e 8): a rodada do que se fala ao dono, à equipe e ao cliente. Passos _agenda_comunicar_<passo>(date, timestamptz) → jsonb, na ordem destrava, teto, quinta, previsto, mudancas_equipe, convites, convites_vencidos; o que ainda não existe = {pulado}. Sem o passo vetos: o prazo é da rodada do gestor. Entre os passos confere comunicar_tempo_max: passou, para e grava parou_no. Erro de um passo → app_error_logs (comunicar:<passo>) e segue; query_canceled → registra, grava a rodada e encerra. Domingo e os 6 modos desligados = {rodou: false}. Uma rodada por vez. Uma linha em agenda_vigia_rodadas (rotina comunicar). {rodou, contagens, erros, falhas, parou_no, avisos}. Security definer, só o service_role. Quem a chama é o passo 0e do task-automations (P4). FASE 7f (P4; §5.4, R8.5-27): antes dos passos, contagens.lote_guardaria (_agenda_comunicar_lote_guardaria): em sombra, o que o lote teria guardado do aviso desta rodada; ligado, a exceção acima da cota. Lote desligado, sem a chave. Erro aqui = comunicar:lote_guardaria, e os passos rodam. O passo quinta agora existe (_agenda_comunicar_quinta).';

-- ── 7. Portas ───────────────────────────────────────────────────────────────────────────────────────
-- As novas: sem grant a ninguém. Quem as chama é definer (agenda_aviso_pecas, agenda_aviso_enfileirar, agenda_comunicar_rodar). As recriadas: as portas de antes, repetidas para a
-- migration valer sozinha; a de enfileirar é nova (drop + create), então o revoke/grant é obrigatório aqui.
revoke all on function public._agenda_lote_ligado(),
                       public._agenda_lote_cota(date),
                       public._agenda_e_excecao(jsonb, date, timestamptz),
                       public._agenda_lote_mudancas(date),
                       public._agenda_lote_fora(jsonb),
                       public._agenda_lote_texto(jsonb),
                       public._agenda_comunicar_quinta(date, timestamptz),
                       public._agenda_comunicar_lote_guardaria(date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.agenda_aviso_pecas(date, timestamptz),
                       public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz, boolean),
                       public.agenda_comunicar_rodar(date, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_aviso_pecas(date, timestamptz),
                          public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz, boolean),
                          public.agenda_comunicar_rodar(date, timestamptz)
  to service_role;
