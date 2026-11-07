-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P2: as perguntas — quem pode vencer agora, a linha de cada pergunta, a ordem, o que
-- destrava, o prazo, o teto de abertas, a rodada comunicar e a volta do que ficou com o padrão.
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§5.2, §6.2, §6.3, §8.3 agenda_fase7f_perguntas.sql e o bloco R8, que vale sobre o corpo: R8.1, R8.2, R8.4, R8.5-7 a 11,
-- R8.6, R8.7, R8.8, R8.12, R8.13); nomes: fase7-registro.md §1 (7f P2); respostas do dono: fase7-padroes.md (AG7-15 o prazo; AG7-24 o teto; AG7-02 os dias do dono primeiro;
-- AG7-37 o dono conta só para abrir e fechar).
-- Depende das Fases 1 a 6, do lote de 30/10, das etapas 7a a 7d e da base da 7f (20261109100000). NÃO depende da 7e.
--
-- ═══ SÓ FUNÇÕES — OK NOMEADO ═══ (9 funções novas, 3 recriadas; nenhuma tabela, nenhuma coluna, nenhuma lista, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p2/montar-migration.mjs: cada recriada é o corpo da definição
-- MAIS NOVA (conferida a cada montagem: o montador para se outra migration a definir depois da origem), e a mudança está só nos blocos "-- FASE 7f: … -- FASE 7f: fim".
-- Tirados os blocos, o corpo é o da origem, byte a byte (o montador e o P9 de supabase/tests/agenda_fase7f_perguntas.sql conferem).
--
-- POR QUE: 22 perguntas ligadas na história, 0 respondidas, 13 nunca mostradas. Para a agenda caber no fechamento, cada pergunta precisa de uma linha curta que diga o que
-- fica sem resposta, e o silêncio do dono tem de ter um efeito previsível, escrito antes, que ele possa desfazer. Esta migration faz a regra e a linha; quem as mostra é o P3.
--
-- O QUE MUDA:
--   1. _agenda_pergunta_espera (nova): por que a pergunta não vence AGORA, ou nulo se pode vencer. É a regra única: quem vence, quem escreve o prazo e a ordem leem a mesma
--      função. veto_espera é a foto do nascimento: aqui o prometido e o dia já dito à equipe ou ao cliente são conferidos de novo (R8.5, notas do P1).
--   2. _agenda_pergunta_frases (nova): o texto de cada chave, num lugar só (o que fica sem resposta). Só diz o que está no banco: sem alocação é "conto", nunca "marquei".
--   3. _agenda_pergunta_linha (nova): a linha de uma pergunta, pelo título, o que fica e o prazo, com "Decisão N:" quando ela tem número em agenda_decisoes_abertas (R8.4, R8.7).
--      O prazo só é escrito com o prazo valendo de verdade (modo_veto ligado, sem o freio). veto_ate da saída = o prazo que está no texto; veto_diria = o que seria, só em sombra.
--   4. _agenda_destrava (nova) e _agenda_comunicar_destrava (nova): os meios-dias que a resposta põe na agenda, 1 vez por dia, nunca dentro da vigia (R8.5-6).
--   5. agenda_perguntas_em_ordem (nova): quais perguntas vêm primeiro. Ela escolhe QUAIS o bloco mostra; o número continua o de agenda_decisoes_abertas, que não muda (R8.7).
--   6. _agenda_pergunta_assumir (nova): fica com o padrão, por um caminho só para o prazo e para o teto. Efeito nada: fecha com a ação assumir, desfazível por 2 dias úteis
--      (R8.5-11). Efeito opcao: agenda_decidir com canal prazo, carimbo depois; ok = false ou erro: veto_espera = sem_padrao, a pergunta fica aberta e sem prazo (R8.5-9).
--   7. _agenda_gestor_vetos (recriada): depois do bloco do 7a, o bloco do prazo desta etapa, com a mesma ordem de travas (R8.5-8). Com o freio ou em sombra, só veto_teria_em.
--   8. _agenda_comunicar_teto (nova): acima de perguntas_abertas_max, a mais velha que pode vencer, só com efeito nada: o teto nunca muda a agenda.
--   9. agenda_comunicar_rodar (nova): a rodada, molde de agenda_gestor_rodar, com o relógio entre os passos e parou_no (R8.5-7). Sem set statement_timeout e sem o passo vetos
--      (R8.5-8). Os passos de P4 e P5 são pulados enquanto não existem. NADA a chama ainda: o passo 0e do task-automations é do P4.
--  10. agenda_decidir (recriada): aceita o canal prazo. Pelo prazo, recusa com o freio, em sombra e no que não pode vencer; o que passa propõe e aplica como as rodadas automáticas: origem
--      vigia, sem autor. Ninguém decidiu: nem a ação, nem a proposta, nem a pergunta dizem que foi o dono. Nada mais muda.
--  11. agenda_desfazer (recriada): o ramo da ação assumir, antes do caminho genérico: a pergunta volta aberta, sem prazo (R8.5-10).
--
-- O QUE NÃO MUDA: com modo_veto desligado ou em sombra, com ou sem o freio, as leituras e os textos ao dono, à equipe e ao cliente são os de antes, byte a byte: nada lê as funções
-- novas (o bloco é do P3). agenda_decisoes_abertas não é recriada. Nada escreve em agenda_disponibilidade: o padrão do dono continua o de AG7-37. Não muda agenda_resolver_os,
-- agenda_rascunho_*, os_carteira, _agenda_cliente_contexto nem o sentido de agenda_acoes.tipo.
--
-- ORDEM DE LIGAR (spec R8.14): depois de 20261109100000. Aplicar sozinha não muda nada para ninguém (modo_veto nasce desligado).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_perguntas.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261109100100_agenda_fase7f_perguntas.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261109100100', 'agenda_fase7f_perguntas');"
--
-- DESFAZER: reaplicar as definições de 20261107100400 (agenda_decidir), 20261107100870 (agenda_desfazer) e 20261031100980 (_agenda_gestor_vetos) e apagar as novas:
--   drop function if exists public.agenda_comunicar_rodar(date, timestamptz), public._agenda_comunicar_teto(date, timestamptz),
--     public._agenda_comunicar_destrava(date, timestamptz), public.agenda_perguntas_em_ordem(date, timestamptz),
--     public._agenda_pergunta_assumir(uuid, text, date, timestamptz), public._agenda_pergunta_linha(uuid, date, timestamptz),
--     public._agenda_pergunta_frases(public.agenda_perguntas, date), public._agenda_destrava(public.agenda_perguntas, date),
--     public._agenda_pergunta_espera(public.agenda_perguntas, date);
--   Ação assumir que já exista fica como registro (o tipo continua na lista).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. Quem pode vencer agora ───────────────────────────────────────────────────────────────────────
-- A regra única. veto_espera é a foto do nascimento, e aqui ela é conferida: o prometido que surgiu depois segura o efeito opcao, em qualquer OS da pergunta (só 4 de 131 OS têm linha
-- em os_planejamento, e sem linha o exists é falso, o caso comum). Só o efeito opcao: o efeito nada não muda dia nenhum (§6.3: Nelson tem faixa prometida e a estimativa dele vence).
-- O dia já dito segura do mesmo jeito: alocação de pé, de hoje em diante, em OS da pergunta, em dia que _agenda_dia_avisado diz que o cliente ou a equipe já sabem (AG7-15: o que muda dia já dito
-- espera sempre; a ficha enviada é a parte da equipe). Fora de veto_tipos hoje também segura: a lista pode mudar depois de a pergunta nascer. Opção nula ou fora das opções = sem_padrao, nunca
-- agenda_decidir(null) (R8.12-2). Quem fez a pergunta em teste segura, como no bloco do 7a: o interruptor de quem pergunta vale antes do prazo. Devolve o que segura, ou nulo: 'equipe' e 'teste'
-- só existem aqui, não são valores da coluna.
create or replace function public._agenda_pergunta_espera(p_q public.agenda_perguntas, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_op  smallint := coalesce(p_q.opcao_padrao, p_q.recomendacao);
  v_dia text;
begin
  if p_q.veto_espera is not null then
    return p_q.veto_espera;
  end if;
  if p_q.padrao_chave is null then
    return 'sem_padrao';
  end if;
  if p_q.padrao_efeito = 'opcao' then
    -- (v_op nula: a comparação dá nulo, o exists é falso, e dá sem_padrao)
    if not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_q.opcoes) = 'array' then p_q.opcoes else '[]'::jsonb end) e
                    where e ->> 'n' = v_op::text) then
      return 'sem_padrao';
    end if;
    if exists (select 1 from public.os_planejamento pl
                where pl.service_order_id = any (coalesce(p_q.os_ids, '{}') || p_q.service_order_id) and pl.prometido_tipo is not null) then
      return 'cliente';
    end if;
    select max(public._agenda_dia_avisado(a.payee_id, a.service_order_id, a.dia)) into v_dia  -- 'cliente' > 'equipe': o cliente vence, como em _agenda_criticidade
      from public.agenda_alocacoes a
     where a.service_order_id = any (coalesce(p_q.os_ids, '{}') || p_q.service_order_id) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
    if v_dia is not null then
      return case when v_dia = 'equipe' then 'equipe' else 'cliente' end;
    end if;
  end if;
  if not p_q.tipo = any ((public._agenda_cfg()).veto_tipos) then
    return 'tipo';
  end if;
  if coalesce(public._agenda_modo_da_pergunta(p_q.tipo, p_q.chave), 'desligado') <> 'ligado' then
    return 'teste';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_pergunta_espera(public.agenda_perguntas, date) is
  'Agenda de Produção (Fase 7f, P2; AG7-15): por que a pergunta não vence AGORA: veto_espera (a foto do nascimento), sem_padrao (sem chave, ou efeito opcao sem uma opção de verdade), cliente (efeito opcao com prometido em qualquer OS dela, ou com dia que o cliente já ouviu, conferidos na hora), equipe (efeito opcao com dia de ficha enviada), tipo (fora de veto_tipos hoje), teste (o modo de quem pergunta fora de ligado); nulo = pode vencer. Pergunta crítica passa pela mesma régua. A regra única: quem vence, a linha e a ordem leem esta função. STABLE, sem grant.';

-- ── 2. O que fica sem resposta, chave a chave ───────────────────────────────────────────────────────
-- O texto de cada chave mora aqui (§3.1 item 5). Só o efeito nada: o efeito opcao é "Recomendo a opção N", na linha. O título é o que ele tem de curto (R8.4): a pergunta inteira fica em
-- *agenda pendências*. O nome só entra se o título ainda não o traz: o texto real é "Nelson (OS-00070) está em andamento…". Sem alocação de pé é "conto", nunca "marquei" (R8.12-9).
-- prazo_padrao: com 1 fornecedor, o prazo dele, que pode ser o chute pela cidade; sem ele, o padrão AG7-06 só para quem não tem outro: é o que a conta faz.
create or replace function public._agenda_pergunta_frases(p_q public.agenda_perguntas, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_tit   text := public._agenda_titulo_da_pergunta(p_q.texto);
  v_sup   uuid := case when p_q.chave ~ '^fornecedor_cadastro:[0-9a-f-]{36}$' then split_part(p_q.chave, ':', 2)::uuid end;
  v_nome  text;
  v_rot   text;
  v_base  text;
  v_marc  date[];
  v_dias  numeric;
  v_pf    jsonb;
  v_prazo text;
  v_frase text;
  v_res   text := 'fica assim.';
  v_sem   text := '';
  v_fica  text := 'ficou como estava';
begin
  v_nome := case when p_q.tipo = 'padrao_do_dono' then 'Você'
                 when p_q.service_order_id is not null then
                   (select public._agenda_corta(coalesce(public._agenda_nome_curto(cl.name), so.service_order_number), 30)
                      from public.service_orders so left join public.clients cl on cl.id = so.client_id where so.id = p_q.service_order_id)
                 when v_sup is not null then public._agenda_corta(public._agenda_fornecedor_curto(v_sup), 30) end;
  v_rot := case when p_q.tipo = 'padrao_do_dono' then 'os seus dias em campo'
                when v_nome is not null then v_nome
                when p_q.tipo in ('fornecedores_prazo', 'fornecedor_cadastro') then 'os fornecedores' end;
  -- o título com o ponto final, com o nome na frente quando ele ainda não está lá
  v_base := case when v_nome is null or (p_q.tipo <> 'padrao_do_dono' and position(lower(v_nome) in lower(v_tit)) > 0) then '' else v_nome || ': ' end
            || case when v_tit ~ '[?!…]$' then v_tit else v_tit || '.' end;
  v_frase := v_base;
  if p_q.padrao_chave in ('estimativa', 'sem_peca') and p_q.padrao_efeito = 'nada' and p_q.service_order_id is not null then
    v_marc := array(select distinct a.dia from public.agenda_alocacoes a
                     where a.service_order_id = p_q.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                       and a.dia >= p_hoje order by 1);
  end if;
  case
    when p_q.padrao_efeito is distinct from 'nada' then
      null;
    when p_q.padrao_chave = 'estimativa' and p_q.service_order_id is not null then
      v_dias := (public.agenda_meios_da_os(p_q.service_order_id, p_hoje) ->> 'dias')::numeric;
      v_res := 'fica assim; se for outro número, me diga os dias.';
      v_sem := 'Se for outro número, me diga os dias.';
      if v_dias is null then
        v_fica := 'fica como está';
      elsif cardinality(v_marc) > 0 then
        v_frase := format('%s: marquei %s pela estimativa%s.', v_nome, public._agenda_dias(v_dias),
                          case when char_length(public._agenda_dias_texto(v_marc)) <= 40 then ' (' || public._agenda_dias_texto(v_marc) || ')' else '' end);
        v_fica := format('ficaram os %s pela estimativa', public._agenda_dias(v_dias));
      else
        v_frase := format('%s: conto %s pela estimativa.', v_nome, public._agenda_dias(v_dias));
        v_fica := format('continuo contando %s pela estimativa', public._agenda_dias(v_dias));
      end if;
    when p_q.padrao_chave = 'sem_peca' and p_q.service_order_id is not null then
      v_res := 'fica assim; se faltar peça, me diga qual.';
      v_sem := 'Se faltar peça, me diga qual.';
      if cardinality(v_marc) > 0 then
        v_frase := format('%s: marquei sem peça a comprar.', v_nome);
        v_fica := 'ficou sem peça a comprar';
      else
        v_frase := format('%s: conto sem peça a comprar.', v_nome);
        v_fica := 'continuo contando sem peça a comprar';
      end if;
    when p_q.padrao_chave = 'abre_e_fecha' then
      v_res := 'continuo contando você só para abrir e fechar.';
      v_sem := 'Por enquanto conto você só para abrir e fechar.';
      v_fica := 'continuo contando você só para abrir e fechar';
    when p_q.padrao_chave = 'prazo_padrao' then
      v_pf := public._agenda_prazo_do_fornecedor(v_sup);
      v_prazo := case when v_pf ->> 'corridos' is not null then public._agenda_plural((v_pf ->> 'corridos')::int, 'dia corrido', 'dias corridos')
                      else public._agenda_plural(coalesce((v_pf ->> 'du')::int, cf.prazo_sem_fornecedor_du), 'dia útil', 'dias úteis') end;
      if v_sup is not null then
        v_frase := v_base || format(' Conto %s.', v_prazo);
        v_fica := format('fiquei com %s de prazo', v_prazo);
      else
        v_frase := v_base || format(' Conto %s para quem não tem outro prazo.', v_prazo);
        v_fica := format('fiquei com %s para quem não tem outro prazo', v_prazo);
      end if;
    when p_q.padrao_chave = 'como_esta' then
      v_frase := v_base || ' Deixo como está no plano.';
      v_fica := 'deixei como está no plano';
    when p_q.padrao_chave = 'nao_chegou' then
      v_frase := v_base || ' Conto que ainda não chegou.';
      v_fica := 'conto que ainda não chegou';
    else
      null;
  end case;
  return jsonb_build_object('nome', v_nome, 'rotulo', v_rot, 'titulo', v_base, 'frase', v_frase, 'sem_resposta', v_res, 'sem_prazo', v_sem, 'fica', v_fica);
end;
$function$;

comment on function public._agenda_pergunta_frases(public.agenda_perguntas, date) is
  'Agenda de Produção (Fase 7f, P2; §3.1 item 5, §6.2, §6.3, R8.4, R8.12-9): as frases de uma pergunta: {nome, rotulo, titulo, frase, sem_resposta, sem_prazo, fica}. O texto de cada chave mora só aqui; a pergunta inteira fica em *agenda pendências*. Sem alocação de pé é "conto", nunca "marquei". STABLE, sem grant.';

-- ── 3. A linha de uma pergunta ──────────────────────────────────────────────────────────────────────
-- R8.4: título, o que fica e o prazo, no máximo 220 letras (os limites: 12 do número, 32 do nome, 91 do título e a cauda mais longa; no efeito opcao, o título cede). R8.7: o número impresso é o n de
-- agenda_decisoes_abertas, com a mesma hora: é ele que agenda_rascunho_aplicar resolve; quem não tem número não ganha "Decisão". Só escreve "Sem resposta até" com o prazo valendo:
-- em sombra e com o freio nada vence, e prometer seria afirmar o que não acontece (R8.6, R8.12-9). Assim veto_ate é sempre o prazo que está NO TEXTO, e quem registra o que mostrou grava
-- só ele: o relógio nunca começa de um prazo que o dono não leu (§3.1 item 7). veto_diria é o que seria, só em sombra. O 7a pode ter gravado um prazo que já passou sem a pergunta ter
-- sido mostrada antes dele: vale o prazo novo, como _agenda_perguntas_antes aceita.
create or replace function public._agenda_pergunta_linha(p_pergunta uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_max   constant int := 220;  -- estrutural: a linha da §6.2
  q       public.agenda_perguntas;
  v_modo  text;
  v_esp   text;
  v_n     int;
  v_fr    jsonb;
  v_op    smallint;
  v_prazo timestamptz;
  v_ate   timestamptz;
  v_diria timestamptz;
  v_sem   text;
  v_cauda text;
  v_txt   text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_pergunta_linha: sem o dia ou a hora.' using errcode = '22004';
  end if;
  select * into q from public.agenda_perguntas x where x.id = p_pergunta;
  if not found then
    raise exception '_agenda_pergunta_linha: a pergunta % não existe.', p_pergunta using errcode = 'P0002';
  end if;
  v_modo := public._agenda_fala_modo('veto');
  v_esp := public._agenda_pergunta_espera(q, p_hoje);
  v_op := coalesce(q.opcao_padrao, q.recomendacao);
  v_fr := public._agenda_pergunta_frases(q, p_hoje);
  v_n := (select (e ->> 'n')::int from jsonb_array_elements(public.agenda_decisoes_abertas(p_agora)) e where e ->> 'id' = q.id::text);
  if v_esp is null and q.estado = 'aberta' and q.modo = 'ligado' then
    v_prazo := case when q.veto_ate is null then public._agenda_veto_ate(p_agora)
                    when q.veto_ate >= p_agora or coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false) then q.veto_ate
                    else public._agenda_veto_ate(p_agora) end;
    if v_modo = 'ligado' then
      v_ate := v_prazo;
    elsif v_modo = 'sombra' then
      v_diria := v_prazo;
    end if;
  end if;
  v_sem := format('Sem resposta até %s às %s', public._dia_curto((v_ate at time zone 'America/Sao_Paulo')::date),
                  to_char(v_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
  -- o que fica sem resposta é a opção, com o que ela faz: a pergunta inteira, com as outras opções, fica em *agenda pendências*. O título cede para o que fica caber.
  if q.padrao_efeito = 'opcao' and v_esp is null then
    v_cauda := format(' Recomendo a opção %s', v_op)
               || coalesce(': ' || (select public._agenda_corta(rtrim(o ->> 'texto', ' .'), 80) from jsonb_array_elements(q.opcoes) o where o ->> 'n' = v_op::text), '') || '.'
               || case when v_ate is not null then format(' %s, fico com a opção %s.', v_sem, v_op) else '' end;
  end if;
  v_txt := case
    when v_esp = 'cliente' then (v_fr ->> 'titulo') || ' Isto espera você: mexe no dia que o cliente já sabe.'
    when v_esp = 'equipe' then (v_fr ->> 'titulo') || ' Isto espera você: mexe no dia que a equipe já sabe.'
    when q.padrao_efeito = 'opcao' and v_esp is null then
      public._agenda_corta(v_fr ->> 'titulo', c_max - char_length(v_cauda) - char_length(coalesce(format('Decisão %s: ', v_n), ''))) || v_cauda
    when v_esp is null then
      (v_fr ->> 'frase') || case when v_ate is not null then format(' %s, %s', v_sem, v_fr ->> 'sem_resposta')
                                 when v_fr ->> 'sem_prazo' <> '' then ' ' || (v_fr ->> 'sem_prazo') else '' end
    else (v_fr ->> 'titulo') end;
  return jsonb_build_object('texto', case when v_n is not null then format('Decisão %s: ', v_n) else '' end || v_txt, 'veto_ate', v_ate, 'n', v_n)
         || case when v_diria is not null then jsonb_build_object('veto_diria', v_diria) else '{}'::jsonb end;
end;
$function$;

comment on function public._agenda_pergunta_linha(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7f, P2; §5.2, §6.2, R8.4, R8.6, R8.7, R8.12-9): {texto, veto_ate, n} de uma pergunta, em até 220 letras: "Decisão N: " quando ela tem número em agenda_decisoes_abertas, o título, o que fica e o prazo. "Sem resposta até" só com o prazo valendo de verdade (modo_veto ligado, sem o freio, e pergunta que pode vencer): veto_ate é o prazo que está NO TEXTO. Em sombra, veto_ate nulo e veto_diria com o que seria. Pergunta que não existe = P0002. STABLE, sem grant.';

-- ── 4. O que a resposta destrava ────────────────────────────────────────────────────────────────────
-- Os meios-dias que a resposta põe na agenda. Só OS sem compromisso vigente: fora do plano, ou só com reserva. os_duracao_sugerida é por OS: por isso o passo é diário, nunca a vigia
-- (R8.5-6). Sem os dias realistas, a OS não conta: nulo vira 0 por caso explícito, não pelo coalesce do total (R8.12-2).
create or replace function public._agenda_destrava(p_q public.agenda_perguntas, p_hoje date)
 returns smallint
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_primeiro constant smallint := 9999;  -- estrutural: o CHECK da coluna; o resto fica abaixo dele
  v_sup   uuid;
  v_oss   uuid[];
  v_os    uuid;
  v_dias  numeric;
  v_total numeric := 0;
begin
  if p_q.tipo = any ((public._agenda_cfg()).perguntas_primeiro) then
    return c_primeiro;
  end if;
  v_oss := array(select distinct o from unnest(coalesce(p_q.os_ids, '{}') || p_q.service_order_id) o where o is not null);
  if cardinality(v_oss) = 0 and p_q.tipo in ('fornecedores_prazo', 'fornecedor_cadastro') then
    v_sup := case when p_q.chave ~ '^fornecedor_cadastro:[0-9a-f-]{36}$' then split_part(p_q.chave, ':', 2)::uuid end;
    v_oss := array(select distinct m.service_order_id
                     from public.os_carteira(p_hoje) k
                     join public.os_material m on m.service_order_id = k.service_order_id
                     join public.suppliers s on s.id = m.fornecedor_id
                    where s.modalidade is null and m.situacao = 'falta' and (v_sup is null or s.id = v_sup));
  end if;
  foreach v_os in array v_oss loop
    continue when public._agenda_os_tem_dia(v_os, p_hoje);
    v_dias := (public.os_duracao_sugerida(v_os) ->> 'dias_realista')::numeric;
    v_total := v_total + case when v_dias is null then 0 else round(v_dias * 2) + 10 end;
  end loop;
  return least(v_total, c_primeiro - 1)::smallint;
end;
$function$;

comment on function public._agenda_destrava(public.agenda_perguntas, date) is
  'Agenda de Produção (Fase 7f, P2; §5.2): quanto a resposta destrava: 9999 nos tipos de perguntas_primeiro; senão a soma, por OS sem compromisso vigente, dos meios-dias realistas + 10; sem OS, nas perguntas de fornecedor, as OS da carteira com item que falta de fornecedor sem modalidade. Nada calculável = 0. Preso em 0..9998. Lê os_duracao_sugerida por OS: quem chama é o passo diário, nunca a vigia. STABLE, sem grant.';

create or replace function public._agenda_comunicar_destrava(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_desde constant time := '07:00';  -- estrutural: o 1º tique do dia; a vigia e o gestor começam aí
  q       public.agenda_perguntas;
  v_novo  smallint;
  v_n     int := 0;
begin
  if (p_agora at time zone 'America/Sao_Paulo')::time < c_desde then
    return jsonb_build_object('pulado', true, 'motivo', 'cedo');
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x
              where x.rotina = 'comunicar' and x.p_hoje = p_hoje and x.contagens -> 'destrava' ? 'atualizadas') then
    return jsonb_build_object('pulado', true, 'motivo', 'já rodou hoje');
  end if;
  for q in select x.* from public.agenda_perguntas x where x.estado = 'aberta' and x.modo = 'ligado' order by x.criada_em, x.id loop
    v_novo := public._agenda_destrava(q, p_hoje);
    if v_novo is distinct from q.destrava then
      update public.agenda_perguntas set destrava = v_novo where id = q.id;
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('atualizadas', v_n);
end;
$function$;

comment on function public._agenda_comunicar_destrava(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P2; §5.2, R8.5-6): recalcula destrava das abertas ligadas, 1 vez por dia, no 1º tique desde as 07:00 (a rodada comunicar do dia com a chave destrava.atualizadas). {atualizadas} ou {pulado, motivo}. Sem grant.';

-- ── 5. A ordem ──────────────────────────────────────────────────────────────────────────────────────
-- §5.2. Definer: _agenda_pergunta_linha, _agenda_pergunta_espera e _agenda_padrao_da_pergunta não têm grant, e a porta está aqui dentro. Ela escolhe QUAIS perguntas aparecem; o número é o de
-- agenda_decisoes_abertas (R8.7). Crítica com perda_em nula: o case não casa, e ela segue pelos critérios de baixo (R8.12-2). Sexta: "amanhã" é o próximo dia útil, como a exceção.
create or replace function public.agenda_perguntas_em_ordem(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_papel  text;
  v_amanha date;
  v        jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_perguntas_em_ordem: sem o dia ou a hora.' using errcode = '22004';
  end if;
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role, ou quem chama de dentro, sem JWT (molde de _agenda_saude_local)
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'As perguntas da agenda são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'As perguntas da agenda são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  v_amanha := public.agenda_somar_du(p_hoje, 1);
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'tipo', o.tipo, 'os', o.service_order_id, 'ordem', o.ordem, 'destrava', o.destrava,
                                               'padrao_chave', o.padrao_chave, 'veto_espera', o.espera, 'veto_ate', o.l -> 'veto_ate', 'n', o.l -> 'n',
                                               'linha', o.l ->> 'texto')
                            || case when o.l ? 'veto_diria' then jsonb_build_object('veto_diria', o.l -> 'veto_diria') else '{}'::jsonb end
                            order by o.ordem), '[]'::jsonb)
    into v
    from (select q.id, q.tipo, q.service_order_id, q.destrava, q.padrao_chave,
                 public._agenda_pergunta_espera(q, p_hoje) as espera,
                 public._agenda_pergunta_linha(q.id, p_hoje, p_agora) as l,
                 row_number() over (order by case when q.critica and q.perda_em <= v_amanha then q.perda_em end nulls last,
                                             q.tipo = any (cf.perguntas_primeiro) desc,
                                             q.destrava desc,
                                             q.veto_ate nulls last,
                                             q.criada_em, q.id) as ordem
            from public.agenda_perguntas q
           where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo <> 'conferencia'
             and (q.expira_em is null or q.expira_em > p_agora)) o;
  return v;
end;
$function$;

comment on function public.agenda_perguntas_em_ordem(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P2; §5.2, R8.7): as abertas ligadas que valem, menos conferencia, na ordem: crítica que perde até o próximo dia útil, por perda_em; perguntas_primeiro; destrava, da maior; veto_ate, o mais cedo; criada_em, id. [{id, tipo, os, ordem, destrava, padrao_chave, veto_espera (o que segura AGORA, por _agenda_pergunta_espera), veto_ate, n, linha}]; veto_diria em sombra. A ordem escolhe QUAIS o bloco mostra; o número é o n de agenda_decisoes_abertas. Security definer, com a porta dentro: admin ou financeiro, ou service_role; o resto 42501.';

-- ── 6. Ficar com o padrão ───────────────────────────────────────────────────────────────────────────
-- O caminho único do prazo e do teto. Quem chama já tem as travas. Relê sob for update: o dono pode ter respondido, e o prometido pode ter chegado, entre a leitura da rodada e aqui.
-- Efeito nada: estado, motivo e carimbo na MESMA escrita, porque pergunta aberta com assumida_* recusa. Efeito opcao: agenda_decidir fecha e o carimbo vem depois,
-- de nulo a valor. ok = false: veto_espera = sem_padrao, que é a saída (R8.5-9): a pergunta fica aberta e sem prazo, não repete a cada 15 min, e o dono ainda responde pelo número.
-- Janela: 24 h não servem (R8.5-11): assumida às 18:00, o dono lê às 17:30 do dia seguinte, e na sexta nem isso.
-- O *desfaz <nome>* só existe com OS: agenda_acao_desfazivel acha por OS (R8.5-10). "volta" na frase impede que _agenda_mudanca_texto acrescente o "volta como estava" dela.
create or replace function public._agenda_pergunta_assumir(p_pergunta uuid, p_por text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_du_desfaz constant smallint := 2;  -- R8.11: 2 dias úteis às veto_hora
  cf       public.agenda_config := public._agenda_cfg();
  q        public.agenda_perguntas;
  v_op     smallint;
  v_fr     jsonb;
  v_quando text;
  v_r      jsonb;
  v_acao   uuid;
  v_nome   text;
  v_tem_os boolean;
  v_txt    text;
begin
  if p_por is null or p_por not in ('prazo', 'teto') then
    raise exception '_agenda_pergunta_assumir: o caminho "%" não existe.', p_por using errcode = '22023';
  end if;
  select * into q from public.agenda_perguntas x where x.id = p_pergunta for update;
  if not found or q.estado <> 'aberta' then
    return jsonb_build_object('assumida', false, 'motivo', 'fechada');
  end if;
  if public._agenda_pergunta_espera(q, p_hoje) is not null then
    return jsonb_build_object('assumida', false, 'motivo', public._agenda_pergunta_espera(q, p_hoje));
  end if;
  v_quando := case when p_por = 'prazo'
                   then format('sem resposta até %s às %s', public._dia_curto((q.veto_ate at time zone 'America/Sao_Paulo')::date),
                               to_char(q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI'))
                   else format('havia mais de %s perguntas abertas', cf.perguntas_abertas_max) end;
  if q.padrao_efeito = 'opcao' then
    v_op := coalesce(q.opcao_padrao, q.recomendacao);
    v_r := public.agenda_decidir(q.id, v_op, null, 'prazo', format('%s: fiquei com a opção %s.', upper(left(v_quando, 1)) || substr(v_quando, 2), v_op), p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      update public.agenda_perguntas set veto_espera = 'sem_padrao' where id = q.id and estado = 'aberta' and veto_espera is null;
      perform public.log_app_error('db', format('a pergunta %s não ficou com o padrão: %s', q.tipo, v_r ->> 'texto'), 'agenda',
                                   case when p_por = 'prazo' then 'gestor:vetos' else 'comunicar:teto' end, 'error',
                                   jsonb_build_object('pergunta', q.id, 'tipo', q.tipo, 'p_hoje', p_hoje, 'p_agora', p_agora));
      return jsonb_build_object('assumida', false, 'recusada', true, 'texto', v_r ->> 'texto');
    end if;
    update public.agenda_perguntas set assumida_por = p_por, assumida_em = p_agora
     where id = q.id and estado in ('respondida', 'resolvida') and assumida_por is null;
    return jsonb_build_object('assumida', true, 'acao_id', v_r -> 'acao_id', 'texto', v_r ->> 'texto');
  end if;

  v_fr := public._agenda_pergunta_frases(q, p_hoje);
  v_nome := v_fr ->> 'nome';
  v_tem_os := q.service_order_id is not null;
  v_txt := case when v_nome is not null then v_nome || ': ' || v_quando else upper(left(v_quando, 1)) || substr(v_quando, 2) end
           || case when p_por = 'prazo' then ', ' else '; ' end || (v_fr ->> 'fica') || '. '
           || case when v_tem_os then format('*desfaz %s* volta a pergunta.', v_nome) else '*desfaz* mostra a lista.' end;
  update public.agenda_perguntas
     set estado = 'resolvida', resolvida_motivo = left(format('%s: %s.', upper(left(v_quando, 1)) || substr(v_quando, 2), v_fr ->> 'fica'), 200),
         assumida_por = p_por, assumida_em = p_agora
   where id = q.id;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, critica, antes, depois, texto, desfazivel_ate)
  values (p_agora, p_hoje, true, 'vigia', 'assumir', q.service_order_id, q.os_ids, q.id, false,
          jsonb_build_object('pergunta_id', q.id, 'chave', q.chave, 'tipo', q.tipo, 'texto', q.texto, 'rotulo', v_fr ->> 'rotulo'),
          jsonb_build_object('por', p_por, 'padrao_chave', q.padrao_chave),
          left(v_txt, 400), public._agenda_veto_ate(p_agora, c_du_desfaz))
  returning id into v_acao;
  return jsonb_build_object('assumida', true, 'acao_id', v_acao, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_pergunta_assumir(uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 7f, P2; §5.2, R8.5-9 a 11): a pergunta fica com o padrão (p_por: prazo ou teto). Relê sob for update e confere _agenda_pergunta_espera. Efeito nada: resolvida, com assumida_* na mesma escrita, e a ação assumir (origem vigia, desfazível até 2 dias úteis às veto_hora). Efeito opcao: agenda_decidir com canal prazo e o carimbo depois; ok = false: veto_espera = sem_padrao e app_error_logs, sem repetir. {assumida, acao_id, texto} ou {assumida: false, motivo | recusada}. Quem chama tem as travas agenda_plano e agenda_vetos. Sem grant.';

-- ── 7. O teto ───────────────────────────────────────────────────────────────────────────────────────
-- §5.2, AG7-24. Só efeito nada: pergunta nunca mostrada pode cair aqui, e o que não muda a agenda pode fechar sem o dono ter lido o prazo; opção aplicada, não (NOVO-agenda-78). Se todas esperam, o
-- teto passa, e acima_do_teto diz quantas sobraram. Conta o que os outros leitores mostram: sem a expirada, que a limpeza da vigia fecha.
create or replace function public._agenda_comunicar_teto(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text := public._agenda_fala_modo('veto');
  q       public.agenda_perguntas;
  v_n     int;
  v_ass   int := 0;
  v_ter   int := 0;
  v_trava boolean := false;
  v_r     jsonb;
  v_est   text;
  v_msg   text;
begin
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado');
  end if;
  select count(*) into v_n from public.agenda_perguntas x
   where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora);
  if v_n <= cf.perguntas_abertas_max then
    return jsonb_build_object('assumidas', 0, 'teria', 0, 'acima_do_teto', 0);
  end if;
  for q in select x.* from public.agenda_perguntas x
            where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora)
              and x.padrao_efeito = 'nada' and x.opcao_escolhida is null and public._agenda_pergunta_espera(x, p_hoje) is null
            order by x.criada_em, x.id
            limit v_n - cf.perguntas_abertas_max loop
    if v_modo <> 'ligado' then
      update public.agenda_perguntas set veto_teria_em = p_agora where id = q.id and veto_teria_em is null;
      if found then
        v_ter := v_ter + 1;
      end if;
      continue;
    end if;
    if not v_trava then
      perform pg_advisory_xact_lock(hashtext('agenda_plano'));
      perform pg_advisory_xact_lock(hashtext('agenda_vetos'));
      v_trava := true;
    end if;
    begin
      v_r := public._agenda_pergunta_assumir(q.id, 'teto', p_hoje, p_agora);
      if coalesce((v_r ->> 'assumida')::boolean, false) then
        v_ass := v_ass + 1;
      end if;
    exception when others then
      get stacked diagnostics v_est = returned_sqlstate, v_msg = message_text;
      perform public.log_app_error('db', format('teto das perguntas, %s: %s', q.tipo, v_msg), 'agenda', 'comunicar:teto', 'error',
                                   jsonb_build_object('pergunta', q.id, 'tipo', q.tipo, 'sqlstate', v_est, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;
  return jsonb_build_object('assumidas', v_ass, 'teria', v_ter, 'acima_do_teto', v_n - v_ass - cf.perguntas_abertas_max);
end;
$function$;

comment on function public._agenda_comunicar_teto(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P2; §5.2, AG7-24): conta as abertas ligadas que valem, menos conferencia; acima de perguntas_abertas_max, a mais velha que pode vencer (por _agenda_pergunta_espera) e tem efeito nada fica com o padrão, assumida_por = teto, pelo caminho do prazo. Em sombra e com o freio, só veto_teria_em. Desligado = {pulado}. {assumidas, teria, acima_do_teto}. Sem grant.';

-- ── 8. A rodada ─────────────────────────────────────────────────────────────────────────────────────
-- R8.5-7: o molde de agenda_gestor_rodar. Sem set statement_timeout: o tempo é armado no início do comando, e o SET não corta a própria chamada. O relógio confere ENTRE os passos, com comunicar_tempo_max;
-- query_canceled para a rodada e grava parou_no. R8.5-8: sem o passo vetos, que já roda 4 vezes por hora no gestor: menos um caminho que trava o plano. Os passos de P4 e P5 são pulados
-- enquanto não existem. Domingo: nada. Com os 6 modos desligados, nada. Definer: os passos não têm grant.
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
  'Agenda de Produção (Fase 7f, P2; §5.2, R8.5-7 e 8): a rodada do que se fala ao dono, à equipe e ao cliente. Passos _agenda_comunicar_<passo>(date, timestamptz) → jsonb, na ordem destrava, teto, quinta, previsto, mudancas_equipe, convites, convites_vencidos; o que ainda não existe = {pulado}. Sem o passo vetos: o prazo é da rodada do gestor. Entre os passos confere comunicar_tempo_max: passou, para e grava parou_no. Erro de um passo → app_error_logs (comunicar:<passo>) e segue; query_canceled → registra, grava a rodada e encerra. Domingo e os 6 modos desligados = {rodou: false}. Uma rodada por vez. Uma linha em agenda_vigia_rodadas (rotina comunicar). {rodou, contagens, erros, falhas, parou_no, avisos}. Security definer, só o service_role. Quem a chama é o passo 0e do task-automations (P4).';

-- ── 9. As recriadas ─────────────────────────────────────────────────────────────────────────────────

-- _agenda_gestor_vetos (de 20261031100980_agenda_fase77a_correcao.sql)
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
  v_trava  boolean := false;
  -- FASE 7f: (7f P2) o prazo desta etapa
  v_7f_modo text;
  v_7f_q    public.agenda_perguntas;
  v_7f_r    jsonb;
  v_7f_ass  int := 0;
  v_7f_ter  int := 0;
  v_7f_rec  int := 0;
  -- FASE 7f: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_vetos: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- (7a correção, achado 13) as travas só antes da 1ª pergunta que o prazo vai aplicar (antes: em todo tique, até o fim da
  -- rodada, mesmo sem nada a aplicar, segurando o *grava* e o *desfaz* do dono)
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
    -- (7a correção, achado 13) a mesma ordem de antes (agenda_plano, depois agenda_vetos), na 1ª que aplica;
    -- _agenda_gestor_decidir trava de novo e confere a pergunta
    if not v_trava then
      perform pg_advisory_xact_lock(hashtext('agenda_plano'));
      perform pg_advisory_xact_lock(hashtext('agenda_vetos'));
      v_trava := true;
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
  -- FASE 7f: (7f P2, §5.2, R8.5-8, R8.5-9, R8.6) as abertas em ligado com o prazo vencido e mostradas antes dele, que podem vencer agora (_agenda_pergunta_espera: o prometido e o dia já dito são conferidos de novo, com a
  -- mesma régua para a crítica). O modo é o efetivo: em sombra e com *gestor, só propor*, só veto_teria_em, uma vez, e nada mais. As travas na mesma ordem do 7a, só antes da 1ª que aplica. Erro numa pergunta:
  -- registra, e veto_espera = sem_padrao, para não repetir a cada tique; a pergunta fica aberta e sem prazo. As chaves novas só quando houve algo: o tique ocioso devolve o de antes.
  v_7f_modo := public._agenda_fala_modo('veto');
  if v_7f_modo <> 'desligado' then
    for v_7f_q in select q.* from public.agenda_perguntas q
                   where q.estado = 'aberta' and q.modo = 'ligado' and q.veto_ate is not null and q.veto_ate <= p_agora and q.opcao_escolhida is null
                     and coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)
                     and public._agenda_pergunta_espera(q, p_hoje) is null
                   order by q.veto_ate, q.criada_em, q.id loop
      if v_7f_modo <> 'ligado' then
        update public.agenda_perguntas set veto_teria_em = p_agora where id = v_7f_q.id and veto_teria_em is null;
        if found then
          v_7f_ter := v_7f_ter + 1;
        end if;
        continue;
      end if;
      if not v_trava then
        perform pg_advisory_xact_lock(hashtext('agenda_plano'));
        perform pg_advisory_xact_lock(hashtext('agenda_vetos'));
        v_trava := true;
      end if;
      begin
        v_7f_r := public._agenda_pergunta_assumir(v_7f_q.id, 'prazo', p_hoje, p_agora);
        if coalesce((v_7f_r ->> 'assumida')::boolean, false) then
          v_7f_ass := v_7f_ass + 1;
        elsif coalesce((v_7f_r ->> 'recusada')::boolean, false) then
          v_7f_rec := v_7f_rec + 1;
        end if;
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_7f_rec := v_7f_rec + 1;
        perform public.log_app_error('db', format('prazo da pergunta %s: %s', v_7f_q.tipo, v_msg), 'agenda', 'gestor:vetos', 'error',
                                     jsonb_build_object('pergunta', v_7f_q.id, 'tipo', v_7f_q.tipo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
        update public.agenda_perguntas set veto_espera = 'sem_padrao' where id = v_7f_q.id and estado = 'aberta' and veto_espera is null;
      end;
    end loop;
  end if;
  if v_7f_ass + v_7f_ter + v_7f_rec > 0 then
    return jsonb_build_object('aplicadas', v_apl, 'os', v_os, 'acoes', v_acoes, 'respondidas', v_resp, 'sem_mostrar', v_sem,
                              'em_teste', v_teste, 'sem_condicao', v_cond, 'erros', v_erros,
                              'assumidas', v_7f_ass, 'teria', v_7f_ter, 'recusadas', v_7f_rec);
  end if;
  -- FASE 7f: fim
  return jsonb_build_object('aplicadas', v_apl, 'os', v_os, 'acoes', v_acoes, 'respondidas', v_resp, 'sem_mostrar', v_sem,
                            'em_teste', v_teste, 'sem_condicao', v_cond, 'erros', v_erros);
end;
$function$;

comment on function public._agenda_gestor_vetos(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4; AG7-15): o prazo das perguntas do gestor — a aberta, modo ligado, não crítica, de um dos 10 tipos do gestor, com opcao_padrao e veto_ate < p_agora, sem resposta (opcao_escolhida nula), mostrada ao dono antes do prazo (mostrada_vezes > 0 e mostrada_em < veto_ate) e com o modo de quem a fez ligado (_agenda_modo_da_pergunta): aplica a opcao_padrao por _agenda_gestor_decidir(…, p_via prazo), cada uma no seu bloco (erro → app_error_logs gestor:vetos, e segue). A não mostrada fica aberta (sem_mostrar). Trava agenda_plano e agenda_vetos (idempotente entre a rodada do gestor e, no 7f, a comunicar, que recria ESTA função). {aplicadas, os, acoes, respondidas, sem_mostrar, em_teste, sem_condicao, erros}. Invoker, sem grant. CORREÇÃO DA 7a (revisão da etapa; achado 13): as travas agenda_plano e agenda_vetos só são pegas antes da 1ª pergunta que o prazo vai aplicar (a mesma ordem; _agenda_gestor_decidir trava de novo e confere a pergunta): o tique sem nada a aplicar não trava o *grava* e o *desfaz* do dono pela rodada inteira. FASE 7f (P2; §5.2, R8.5-8, R8.5-9): depois do bloco do 7a, as abertas em ligado com veto_ate <= p_agora, mostradas antes do prazo, que podem vencer agora (_agenda_pergunta_espera), pelo modo efetivo (_agenda_fala_modo veto): em sombra e com *gestor, só propor*, só veto_teria_em, uma vez; ligado, _agenda_pergunta_assumir(prazo). Erro numa pergunta: gestor:vetos e veto_espera = sem_padrao, sem repetir. A rodada comunicar NÃO a chama: o passo vetos saiu. As chaves assumidas, teria e recusadas só quando houve algo.';

-- agenda_decidir (de 20261107100400_agenda_fase7d_combinar.sql)
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
  -- FASE 7b: (7b P3) a chamada da equipe, o contato e a pergunta dos dias do dono
  v_7b_g    jsonb;
  v_7b_txt  text;
  v_7b_nome text;
  v_7b_dias smallint[];
  v_7b_acao uuid;
  -- FASE 7b: fim
begin
  -- FASE 7f: (7f P2, §5.2) o canal prazo passa; o resto segue pela conferência de sempre, logo abaixo. Com prazo, respondida_por fica nulo e a resposta é o texto do passo.
  if p_via is distinct from 'prazo' then
  -- FASE 7f: fim
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  -- FASE 7f: (fecha o "se não é prazo")
  end if;
  -- FASE 7f: fim
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
  -- FASE 7f: (7f P2, R8.6) pelo prazo não há autor; com o freio ou em sombra nada decide, e o que não pode vencer não vence: é a última porta, sob a trava e com a pergunta relida. Quem chama já filtrou, e a
  -- recusa vira veto_espera = sem_padrao.
  if p_via = 'prazo' and (p_autor is not null or public._agenda_fala_modo('veto') <> 'ligado' or public._agenda_pergunta_espera(v_q, p_hoje) is not null) then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta espera você: nada mudou.');
  end if;
  -- FASE 7f: fim
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
  -- FASE 7d: (7d P5, §5.5, R1) as perguntas do que combinar têm o efeito delas e a regra delas (a pergunta e o modo cru, não o freio: R6.7b):
  -- _agenda_local_decidir. Vem antes do "não é de decisão": a combinar não é crítica. O tipo local é do P6.
  if v_q.tipo in ('combinar', 'local', 'acesso') then
    return public._agenda_local_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 7d: fim
  -- FASE 7b: (7b P3; R4.1-3, R4.1-6, R4.2(b)) as perguntas da equipe com opções — a chamada (1 está certo; 2 mudou: "Me diga quem
  -- saiu ou quem entrou e em que dias vem …", sem diária), o contato (1 põe na rotina, com *desfaz*; 2 grava a recusa: a linha parada,
  -- e nem a regra d14 nem a pergunta voltam) e a pergunta dos dias do dono (a opção com dias grava a semana pelo
  -- _agenda_equipe_dias_gravar, origem dono — a 2, "Fico em campo de seg a sex", cria o padrão dele —; a 1 só fica respondida). Só
  -- com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados. A chamada da 7a (sem opções) segue o caminho de antes.
  if v_q.tipo = 'dias_semana' or (v_q.tipo = 'equipe_cadastro' and jsonb_array_length(v_q.opcoes) > 0) then
    if v_q.estado <> 'aberta' then
      return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
    end if;
    if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
      return jsonb_build_object('ok', false, 'texto', 'Essa pergunta da equipe ainda está em teste: mostro como ficaria, mas não mudo nada.');
    end if;
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_7b_nome := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_q.payee_id), 'a pessoa');
    if v_q.tipo = 'dias_semana' then
      if v_opc -> 'efeito' ? 'dias' then
        v_7b_dias := array(select y::smallint from jsonb_array_elements_text(v_opc #> '{efeito,dias}') y);
        -- (correção da revisão da 7b, achados 3 e 10) a opção com dias da pergunta dos dias do dono ("Fico em campo de seg a
        -- sex") diz os dias dele de toda semana: só ela troca o padrão (o gravador prende só a semana em qualquer outra fala do dono)
        if cardinality(v_7b_dias) > 0 and v_q.payee_id is not distinct from public._agenda_dono(null) then
          perform set_config('agenda.dias_padrao_do_dono', 'sim', true);
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_g := public._agenda_equipe_dias_gravar(v_q.payee_id, v_q.dia, v_7b_dias,
                                                    coalesce((v_opc #>> '{efeito,sabado}')::boolean, false), 'dono',
                                                    'opção ' || p_opcao, p_agora, null, v_q.id, p_autor);
        -- (correção da revisão da 7b, achados 3 e 10) a variável volta a vazio logo depois
        perform set_config('agenda.dias_padrao_do_dono', '', true);
        -- (correção da revisão da 7b: fim)
        v_7b_txt := v_7b_g ->> 'texto';
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, pergunta_id, depois, texto, autor)
        values (clock_timestamp(), p_hoje, true, 'dono', 'equipe', v_q.payee_id, v_q.id,
                jsonb_build_object('motivo', 'dias_semana', 'semana', v_q.dia, 'dias', to_jsonb(v_7b_dias),
                                   'mudou', v_7b_g -> 'mudou', 'padrao_mudou', v_7b_g -> 'padrao_mudou'),
                left(v_7b_txt, 400), p_autor)
        returning id into v_7b_acao;
      else
        v_7b_txt := format('Anotei: na semana de %s fica assim.', to_char(v_q.dia, 'DD/MM'));
      end if;
      return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao);
    end if;
    if v_opc #>> '{efeito,contato}' = 'por' then
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_q.payee_id, true, 'dono', p_agora)
      on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
      v_7b_txt := format('Pus %s na rotina da equipe, como você pediu. *desfaz* tira.', v_7b_nome);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, pergunta_id, depois, texto, autor,
                                       desfazivel_ate)
      values (clock_timestamp(), p_hoje, true, 'dono', 'equipe', v_q.payee_id, v_q.id,
              jsonb_build_object('motivo', 'contato', 'payee', v_q.payee_id), left(v_7b_txt, 400), p_autor,
              p_agora + cf.desfazer_validade)
      returning id into v_7b_acao;
      return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao);
    end if;
    if v_opc #>> '{efeito,contato}' = 'nao' then
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em, parou_em, parou_motivo)
      values (v_q.payee_id, false, 'dono', p_agora, p_agora, 'você disse que não')
      on conflict (payee_id) do nothing;
      return jsonb_build_object('ok', true, 'texto', format('Anotei: %s fica fora da rotina da equipe.', v_7b_nome));
    end if;
    if v_opc #>> '{efeito,chamada}' = 'mudou' then
      return jsonb_build_object('ok', true,
        'texto', 'Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça).');
    end if;
    return jsonb_build_object('ok', true, 'texto', 'Anotei: sigo com a equipe que tenho.');
  end if;
  -- FASE 7b: fim
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
    -- FASE 7f: (7f P2, §5.2) pelo prazo ninguém decidiu: como nas rodadas automáticas, origem vigia e sem autor. Assim a ação sai no *o que mudou* e no aviso, que só contam motor e vigia, com o *desfaz*
    -- dela; não fixa o dia pelo dono nem marca a duração como aceita, o que p_via = dono faria; e nem a proposta nem a ação dizem que foi ele.
    if p_via = 'prazo' then
      v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta), true, 'vigia', null, p_hoje, p_agora);
    else
    -- FASE 7f: fim
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    -- FASE 7f: (fecha o "se é prazo")
    end if;
    -- FASE 7f: fim
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    -- FASE 7f: (7f P2, §5.2) o mesmo caminho do propor: a ação sai crítica, com a pergunta, e sem autor
    if p_via = 'prazo' then
      v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'vigia', null, p_pergunta, p_hoje, p_agora);
    else
    -- FASE 7f: fim
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    -- FASE 7f: (fecha o "se é prazo")
    end if;
    -- FASE 7f: fim
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
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista). CORREÇÃO FASE 6 (C1, regressão B2): a pergunta do aprendizado toma pg_advisory_xact_lock(hashtext(''agenda_aprender'')) antes do for update da pergunta. FASE 7 (7a P4): as perguntas do gestor da agenda (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal) vão a _agenda_gestor_decidir (o efeito e o modo delas: o do gestor); dia_avisado e dia_prometido seguem a decisão crítica de sempre; equipe_cadastro, a de antes. FASE 7b (P3; R4.1-3, R4.1-6, R4.2(b)): as perguntas da equipe com opções têm o efeito delas, com a pergunta e o modo dela (_agenda_modo_da_pergunta) ligados (senão "ainda está em teste") — equipe_cadastro chamada: 1 "Anotei: sigo com a equipe que tenho."; 2 "Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça)." (sem diária); equipe_cadastro contato: 1 põe na lista da rotina (agenda_equipe_contato recebe_rotina, incluido_por dono) com a ação equipe desfazível ("Pus Mateus na rotina da equipe, como você pediu. *desfaz* tira.", depois.motivo contato); 2 grava a recusa — a linha parada (recebe_rotina false, parou_em agora, "você disse que não"): nem a regra d14 nem a pergunta voltam; dias_semana: a opção com dias grava a semana pelo _agenda_equipe_dias_gravar (origem dono; a 2, "Fico em campo de seg a sex", cria o padrão do dono {1..5} sem frequência; a 3, "Nenhum dia", prende só a semana), com a ação equipe do dono; a 1 ("Fica assim") só fica respondida. A chamada da 7a (sem opções) e o telefone (sem opções) seguem o de antes. CORREÇÃO DA REVISÃO DA 7b (achados 3 e 10): na pergunta dias_semana do dono, a opção com dias grava com agenda.dias_padrao_do_dono = sim (só nessa chamada): ela é a única fala do dono que troca o padrão dele ("Fico em campo de seg a sex" = toda semana); a resposta diz "toda semana a partir de agora". FASE 7d (P5, §5.5, R1): os tipos combinar, local e acesso vão a _agenda_local_decidir (o efeito e a regra delas: a pergunta e o modo cru, não o freio), antes do "não é de decisão". FASE 7f (P2; §5.2): o canal prazo passa, com respondida_por nulo e a resposta = o texto do passo; recusa com autor, com modo_veto efetivo fora de ligado (*gestor, só propor*) e no que _agenda_pergunta_espera segura: {ok: false}, nada mudou. A decisão crítica pelo prazo propõe e aplica com origem vigia, sem autor: a ação sai crítica, com pergunta_id, desfazível, e não diz que foi o dono.';

-- agenda_desfazer (de 20261107100870_agenda_fase7d_correcao4.sql)
create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
  -- FASE 7: (7a P7) os ramos das ações do gestor (estimar, dupla, gestor) e quem saiu da equipe
  v_f7_pl    public.os_planejamento%rowtype;
  v_f7_txt   text;
  v_f7_acao  uuid;
  v_f7_sai   uuid[] := '{}';
  v_f7_fora  uuid[] := '{}';
  v_f7_ficam int := 0;
  v_f7_nomes text;
  -- FASE 7: fim
  -- FASE 7b: (7b P3) quem entrou na rotina da equipe sai
  v_7b_acao uuid;
  v_7b_txt  text;
  v_7b_nome text;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa da dupla
  v_7bc_ajud text;
  -- FASE 7b: fim
  -- FASE 7d: (correção G5) a entrega que o cancelar da vigia seguiu
  v_7d_marco uuid;
  v_7d_rm    jsonb;
  -- FASE 7d: fim
  -- FASE 7f: (7f P2) a pergunta que volta
  v_7f_q    public.agenda_perguntas;
  v_7f_nova uuid;
  v_7f_txt  text;
  v_7f_acao uuid;
  -- FASE 7f: fim
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3 (P4): a diária que a agenda lançou: apaga o turno que ela criou, se o acerto está aberto (_agenda_desfazer_diaria).
  if v_a.tipo = 'diaria' then
    return public._agenda_desfazer_diaria(v_a.id, p_autor, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 4: a mudança do material que o gestor fez sozinho (a previsão pela mensagem do fornecedor, a chegada pela nota
  -- importada): as linhas voltam como estavam, se ninguém mexeu nelas depois (_agenda_desfazer_material, 20261027100400).
  if v_a.tipo = 'material' then
    return public._agenda_desfazer_material(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 4: fim
  -- FASE 5: o que a resposta do cliente mudou (a confirmação, o pedido de dia, o acesso: a ação com depois.resposta_id) tem
  -- o desfazer dela (_agenda_desfazer_cliente, 20261028100400); a mensagem enviada não se desmanda; o acorde e a decisão do
  -- aviso crítico não mudaram nada na agenda.
  if v_a.origem = 'cliente' and v_a.tipo in ('fixar', 'cliente') and v_a.depois ? 'resposta_id' then
    return public._agenda_desfazer_cliente(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  if v_a.tipo = 'cliente' then
    return jsonb_build_object('ok', false,
      'texto', case when v_a.depois ? 'mensagem_id' then 'Mensagem enviada não se desmanda.'
                    else 'Isso foi um aviso para você: nada mudou na agenda para desfazer.' end);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) o que o aprendizado mudou (a troca que entrou sozinha e a decisão 1 ou 3 do dono) tem o desfazer dele: o
  -- valor de antes volta e a chave fica travada; a carga volta carga_max (_agenda_desfazer_aprendizado, 20261029100600).
  if v_a.tipo = 'aprendizado' then
    return public._agenda_desfazer_aprendizado(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7d: (7d P5, §5.5) a ação local tem o desfazer dela: as colunas de os_planejamento voltam ao antes, as linhas de os_autorizados que ela criou
  -- ganham revogado_em e o replano do "Segure o dia" volta (_agenda_desfazer_local)
  if v_a.tipo = 'local' then
    return public._agenda_desfazer_local(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 7d: fim
  -- FASE 7: (7a P7, spec R3 e §5.7) as ações do gestor que não são de alocação têm o ramo delas: estimar (os dias que o gestor
  -- gravou pelo prazo ou pela opção 1: os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação), dupla
  -- (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (*gestor, só propor* / *pode marcar*: gestor_so_propor e
  -- gestor_so_propor_em voltam). Só se nada mudou depois da ação (o que está gravado é o depois dela); senão a recusa diz o que
  -- mudou. reparar e reestimar são de alocação e seguem o caminho de sempre.
  if v_a.tipo in ('estimar', 'dupla', 'gestor') then
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', case when v_a.tipo = 'gestor' then 'Não dá mais para desfazer: passou o prazo. Diga *gestor, só propor* ou *gestor, pode marcar*.'
                      else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga.', v_nome) end);
    end if;
    if v_a.tipo = 'gestor' then
      if (select c.gestor_so_propor from public.agenda_config c where c.id)
         is distinct from (v_a.depois ->> 'gestor_so_propor')::boolean then
        return jsonb_build_object('ok', false,
          'texto', 'Não desfaço: depois disso você já mudou o gestor de novo. Diga *gestor, só propor* ou *gestor, pode marcar*.');
      end if;
      update public.agenda_config
         set gestor_so_propor = coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false),
             gestor_so_propor_em = (v_a.antes ->> 'gestor_so_propor_em')::timestamptz,
             atualizado_em = p_agora, atualizado_por = p_autor
       where id;
      v_f7_txt := case when coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false)
                       then 'Desfeito: voltei a só sugerir. *gestor, pode marcar* volta a marcar.'
                       else 'Desfeito: voltei a marcar sozinho; o que eu marcar vem no seu fechamento, com *desfaz*.' end;
    else
      select * into v_f7_pl from public.os_planejamento where service_order_id = v_os for update;
      if not found then
        return jsonb_build_object('ok', false, 'texto', format('Não achei o planejamento do %s: nada mudou.', v_nome));
      end if;
      if v_a.tipo = 'estimar' then
        if v_f7_pl.dias is distinct from (v_a.depois ->> 'dias')::numeric or v_f7_pl.estimativa_fonte is distinct from 'orcamento' then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso os dias do %s mudaram (%s). Para mudar de novo, me diga os dias.', v_nome,
                            coalesce(public._agenda_dias(v_f7_pl.dias), 'sem dias')));
        end if;
        update public.os_planejamento
           set dias = (v_a.antes ->> 'dias')::numeric, estimativa_fonte = v_a.antes ->> 'estimativa_fonte',
               estimativa_em = (v_a.antes ->> 'estimativa_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := case when v_a.antes ->> 'dias' is null
                         then format('Desfeito: o %s volta sem os dias que eu contei (%s). Me diga quantos dias são.',
                                     public._agenda_rotulo_da_os(v_os), public._agenda_dias((v_a.depois ->> 'dias')::numeric))
                         else format('Desfeito: o %s volta a %s, como estava.', public._agenda_rotulo_da_os(v_os),
                                     public._agenda_dias((v_a.antes ->> 'dias')::numeric)) end;
      else
        if v_f7_pl.dupla_dita is distinct from v_a.depois ->> 'dupla_dita'
           or v_f7_pl.dupla_meios is distinct from (v_a.depois ->> 'dupla_meios')::smallint then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso a dupla do %s mudou. Diga *%s com dupla* ou *%s sem dupla*.', v_nome, v_nome, v_nome));
        end if;
        update public.os_planejamento
           set dupla_dita = v_a.antes ->> 'dupla_dita', dupla_meios = (v_a.antes ->> 'dupla_meios')::smallint,
               dupla_motivo = v_a.antes ->> 'dupla_motivo', dupla_em = (v_a.antes ->> 'dupla_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_agora, 'autor', p_autor, 'por', 'dono', 'trecho', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := format('Desfeito: o %s volta %s.', public._agenda_rotulo_da_os(v_os),
                           case v_a.antes ->> 'dupla_dita'
                             when 'todos' then 'com dupla'
                             when 'nao' then 'sem dupla'
                             when 'inicio' then 'com dupla no início'
                             when 'fim' then 'com dupla no fim'
                             else 'ao normal: 1 pessoa, e dupla só quando você marcar' end);
      end if;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto,
                                     autor, desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
            v_a.os_ids, false, jsonb_build_object('acao', v_a.id), v_a.antes, left(v_f7_txt, 400), p_autor, v_a.id)
    returning id into v_f7_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_f7_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_f7_txt, 'acao_id', v_f7_acao, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, §5.2) a entrada na rotina da equipe — a ação equipe da regra d14 (vigia) ou do "1) Ponho" do dono (depois.motivo
  -- regra_d14 ou contato) — sai: recebe_rotina false e a linha parada ("desfeito pelo dono"); a regra não a põe de novo (a linha existe).
  if v_a.tipo = 'equipe' and v_a.depois ->> 'motivo' in ('regra_d14', 'contato') then
    v_7b_nome := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_a.payee_id), 'a pessoa');
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', format('Não dá mais para desfazer: passou o prazo. Se quiser tirar %s da rotina da equipe, me diga.', v_7b_nome));
    end if;
    update public.agenda_equipe_contato
       set recebe_rotina = false, parou_em = p_agora, parou_motivo = 'desfeito pelo dono'
     where payee_id = v_a.payee_id and parou_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'texto', format('%s já não está na rotina da equipe: nada mudou.', v_7b_nome));
    end if;
    v_7b_txt := format('Desfeito: %s sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias.', v_7b_nome);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, os_ids, critica, antes, depois, texto, autor,
                                     desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer',
            v_a.payee_id, '{}'::uuid[], false, jsonb_build_object('acao', v_a.id), jsonb_build_object('recebe_rotina', false),
            left(v_7b_txt, 400), p_autor, v_a.id)
    returning id into v_7b_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_7b_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao, 'recriadas', '[]'::jsonb,
                              'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7b: fim
  -- FASE 7f: (7f P2, §5.2, R8.5-10, R8.5-11) a pergunta que ficou com o padrão volta a esperar o dono, sem prazo: uma pergunta NOVA, igual à de antes, que nasce pelo gatilho com o padrão. A fechada fica como
  -- foi. A mesma chave: se a vigia já a abriu de novo, nada duplica, e o texto continua verdade. A validade que já passou não volta vencida. Passou a janela: a recusa diz por onde sai.
  if v_a.tipo = 'assumir' then
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false, 'texto', 'Não dá mais para reabrir a pergunta: passou o prazo. Se quiser mudar, me diga com as suas palavras.');
    end if;
    select * into v_7f_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, os_material_id, payee_id, dia, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em, expira_em)
    values (v_7f_q.tipo, v_7f_q.chave, v_7f_q.service_order_id, v_7f_q.os_ids, v_7f_q.os_material_id, v_7f_q.payee_id, v_7f_q.dia, v_7f_q.perda_em, v_7f_q.texto,
            v_7f_q.opcoes, v_7f_q.recomendacao, v_7f_q.recomendacao_texto, cf.versao_plano, v_7f_q.modo, p_agora,
            case when v_7f_q.expira_em is null or v_7f_q.expira_em > p_agora then v_7f_q.expira_em else p_agora + cf.desfazer_validade end)
    on conflict (chave, modo) where estado = 'aberta' do nothing
    returning id into v_7f_nova;
    v_7f_txt := case when v_a.antes ->> 'rotulo' is not null then format('Desfeito: a pergunta sobre %s volta a esperar você.', v_a.antes ->> 'rotulo')
                     else 'Desfeito: a pergunta volta a esperar você.' end;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, autor, desfaz_a)
    values (p_agora, p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os, v_a.os_ids, false,
            jsonb_build_object('acao', v_a.id), jsonb_build_object('pergunta_id', v_7f_nova), left(v_7f_txt, 400), p_autor, v_a.id)
    returning id into v_7f_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_7f_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_7f_txt, 'acao_id', v_7f_acao, 'pergunta_id', v_7f_nova, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7f: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    -- FASE 7b: (correção da revisão da 7b, achado 18) no serviço em que o gestor completou a dupla, a revisão encurtou o fim e outra OS
    -- ocupou o meio-dia que sobrou: a recusa (a regra de sempre: o *desfaz* nunca sobrepõe) diz como voltar — desfazer antes o que
    -- ocupou o lugar
    if v_os is not null and exists (select 1 from public.agenda_alocacoes a
                                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa') then
      v_7bc_ajud := public._agenda_lista(array(
                      select distinct public._agenda_nome_curto(py.name) from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa' order by 1));
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: o %s já está no %s %s. Com %s junto, o %s acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz %s* e depois *desfaz %s*.',
                        public._agenda_nome_curto(v_x.pessoa), coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'),
                        public._agenda_meio_texto(v_x.dia, v_x.turno), v_7bc_ajud, v_nome,
                        coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), v_nome));
    end if;
    -- FASE 7b: fim
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- FASE 7: (7a P7; fase7-padroes "medição de 30/10", item 4) o que a ação tirou e era de quem não está mais na equipe (a
  -- grade, agenda_capacidade, naquele dia) não volta: o *desfaz* restaura só o que cabe e diz o resto. Se tudo o que voltaria é
  -- de quem saiu e a ação não criou nada que ainda esteja de pé, nada muda (a recusa diz por quê): voltar o Lenine com João e
  -- Roberto, que saíram, faria a vigia remanejar de novo e mandar outro aviso com outro *desfaz*.
  select coalesce(array_agg(c.id) filter (where not g.na_grade), '{}'), coalesce(array_agg(distinct c.payee_id) filter (where not g.na_grade), '{}'),
         count(*) filter (where g.na_grade)
    into v_f7_sai, v_f7_fora, v_f7_ficam
    from public.agenda_alocacoes c
    cross join lateral (select exists (select 1 from public.agenda_capacidade(c.dia, c.dia, p_hoje) k
                                        where k.payee_id = c.payee_id) as na_grade) g
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora;
  if cardinality(v_f7_fora) > 0 then
    v_f7_nomes := public._agenda_lista(array(select public._agenda_nome_curto(py.name) from public.payees py
                                              where py.id = any (v_f7_fora) order by py.name, py.id), null);
  end if;
  if cardinality(v_f7_fora) > 0 and v_f7_ficam = 0
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')) then
    return jsonb_build_object('ok', false, 'status', 'saiu_da_equipe',
      'texto', format('Não dá para desfazer como estava: %s não %s mais na equipe, e era com %s que o %s estava. Nada mudou; ele volta à agenda com a equipe de agora.',
                      v_f7_nomes, case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                      case when cardinality(v_f7_fora) = 1 then 'ele' else 'eles' end, v_nome));
  end if;
  -- FASE 7: fim
  -- FASE 7d: (correção G5) o cancelar da vigia em OS concluída por *entreguei* é só o efeito: o *desfaz* volta a entrega junto, pelo caminho dela, senão a OS segue concluída, com o plano de volta, e o
  -- tique seguinte cancela de novo. Se ela não volta, nada volta: a recusa dela.
  if v_a.tipo = 'cancelar' and v_a.origem = 'vigia' and (select so.status from public.service_orders so where so.id = v_os) = 'completed' then
    select x.id into v_7d_marco from public.agenda_acoes x
     where x.service_order_id = v_os and x.tipo in ('entregar', 'concluir') and x.executada and x.desfeita_em is null
       and x.criada_em <= v_a.criada_em and x.desfazivel_ate >= p_agora
     order by x.tipo = 'entregar' desc, x.criada_em desc, x.id desc limit 1;
    if v_7d_marco is not null then
      v_7d_rm := public._agenda_desfazer_marco(v_7d_marco, p_autor, p_via, p_hoje, p_agora);
      if not coalesce((v_7d_rm ->> 'ok')::boolean, false) then
        return v_7d_rm;
      end if;
    end if;
    -- (correção M9) a regra única: se a OS segue concluída depois do marco, o plano NÃO volta (a vigia tiraria de novo a cada tique), e o *desfaz* diz por quê. O cancelar segue desfazível: é o 2º *desfaz* que acha a conclusão
    if (select so.status from public.service_orders so where so.id = v_os) = 'completed' then
      if v_7d_rm is null then
        return jsonb_build_object('ok', false, 'texto', format('Não dá para voltar os dias do %s: ele segue concluído. Reabra a OS primeiro.', v_nome));
      end if;
      return jsonb_build_object('ok', true, 'acao_id', v_7d_rm -> 'acao_id', 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb,
        'texto', (v_7d_rm ->> 'texto') || ' ' ||
                 case when exists (select 1 from public.agenda_acoes x
                                    where x.service_order_id = v_os and x.tipo = 'concluir' and x.executada and x.desfeita_em is null
                                      and x.criada_em <= v_a.criada_em and x.desfazivel_ate >= p_agora)
                      then format('O %s segue concluído: mande *desfaz %s* de novo para voltar a conclusão.', v_nome,
                                  (select so.service_order_number from public.service_orders so where so.id = v_os))
                      else format('O %s segue concluído: os dias só voltam reabrindo a OS.', v_nome) end);
    end if;
  end if;
  -- FASE 7d: fim
  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    -- FASE 7: (7a P7) o meio-dia de quem saiu da equipe não volta
    continue when v_x.id = any (v_f7_sai);
    -- FASE 7: fim
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa que o gestor pôs na dupla (as alocações com o motivo
  -- dupla_completa) tira só ela: o serviço continua marcado — o texto de antes dizia que ele saía da agenda
  if cardinality(v_novas) = 0 and cardinality(v_canc) > 0 and v_os is not null and public._agenda_os_tem_dia(v_os, p_hoje)
     and not exists (select 1 from public.agenda_alocacoes a where a.id = any (v_canc) and not coalesce(a.motivos ? 'dupla_completa', false)) then
    v_txt := format('Desfeito: tirei %s do %s %s; o resto do serviço fica como estava.',
                    public._agenda_lista(array(select distinct public._agenda_nome_curto(py.name)
                                                 from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                                                where a.id = any (v_canc) order by 1)),
                    public._agenda_rotulo_da_os(v_os),
                    public._agenda_meios_frase((select jsonb_agg(jsonb_build_object('dia', a.dia, 'turno', a.turno) order by a.dia, a.turno)
                                                  from public.agenda_alocacoes a where a.id = any (v_canc))));
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P7) e diz o que não voltou
  if cardinality(v_f7_fora) > 0 then
    v_txt := v_txt || format(' %s não %s mais na equipe: os dias %s não voltam.', v_f7_nomes,
                             case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                             case when cardinality(v_f7_fora) = 1 then 'dele' else 'deles' end);
  end if;
  -- FASE 7: fim
  -- FASE 7d: (correção G5) os 2 "Desfeito", na ordem em que aconteceram
  v_txt := coalesce((v_7d_rm ->> 'texto') || ' ', '') || v_txt;
  -- FASE 7d: fim
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  -- FASE 3: o replano que a ausência da equipe causou ("não vou" ou o silêncio até as 9h): desfazer também tira a ausência
  -- daquele dia (senão a vigia replanejaria de novo no tique seguinte). "Se ele estiver lá, *desfaz Vanderlei*."
  update public.agenda_disponibilidade d set substituida_em = p_agora
   where d.substituida_em is null
     and d.id in (select (e.depois ->> 'disponibilidade')::uuid from public.agenda_acoes e
                   where e.tipo = 'equipe' and e.depois ->> 'disponibilidade' is not null
                     and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text);
  -- FASE 3: fim
  -- FASE 5: o replano que o pedido de dia do cliente causou, desfeito direto (sem a ação do cliente): o pedido sai junto (o
  -- bem indisponível e o "não antes de" voltam; senão a vigia replanejaria de novo no tique seguinte) e a ação do cliente
  -- fica desfeita. Quem desfaz pela ação do cliente (_agenda_desfazer_cliente) liga agenda.desfazer_cliente e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_cliente', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'cliente' and e.origem = 'cliente' and e.executada and e.desfeita_em is null
                  and e.depois ->> 'efeito' = 'replanejou'
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_cliente_restaurar_pedido(v_x.id, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 5: fim
  -- FASE 7d: (7d P5, R6.7c-1) o replano do "Segure o dia", desfeito direto (sem a ação local): o "não antes de" volta junto, senão a vigia tiraria o
  -- dia de novo no tique seguinte; e a ação local fica desfeita. Quem desfaz pela ação local liga agenda.desfazer_local e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_local', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'local' and e.executada and e.desfeita_em is null
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_local_restaurar(v_x.id, p_autor, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 7d: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita. Fase 6 (P6): a ação aprendizado vai a _agenda_desfazer_aprendizado (o em_uso de antes volta, nulo = o padrão, e a chave fica travada por aprender_trava_dias; a da carga volta carga_max). FASE 7 (7a P7, spec R3): as ações do gestor que não são de alocação têm o ramo delas — estimar (os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação: "Desfeito: o Nelson (OS-00112) volta sem os dias que eu contei (4 dias). Me diga quantos dias são."), dupla (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (gestor_so_propor e gestor_so_propor_em voltam), cada uma só se nada mudou depois dela (senão a recusa diz o que mudou), dentro do desfazivel_ate; reparar e reestimar seguem o caminho de alocação de sempre. E (a medição de 30/10, item 4) o que a ação tirou e era de quem não está mais na equipe naquele dia (agenda_capacidade) não volta: o desfazer restaura só o que cabe e diz o resto ("… João e Roberto não estão mais na equipe: os dias deles não voltam."); se tudo o que voltaria é de quem saiu e a ação não criou nada de pé, nada muda ({ok: false, status saiu_da_equipe}). FASE 7b (P3, §5.2): a ação equipe que pôs alguém na rotina da equipe — pela regra d14 (vigia, depois.motivo regra_d14) ou pelo "1) Ponho" do dono (depois.motivo contato) — se desfaz dentro do desfazivel_ate: a linha em agenda_equipe_contato fica parada (recebe_rotina false, parou_em, "desfeito pelo dono"; a regra não a põe de novo) e "Desfeito: Rafael sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias."; já fora da rotina = nada muda. CORREÇÃO DA REVISÃO DA 7b (achado 18): desfazer a ação que só pôs a 2ª pessoa na dupla (alocações com o motivo dupla_completa) diz "Desfeito: tirei Mateus do Lenine (OS-00074) em ter 10/11 (manhã e tarde); o resto do serviço fica como estava." (não "sai da agenda"); a recusa por sobreposição no serviço com a dupla completada acrescenta "Com Mateus junto, o Lenine acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz Tânia* e depois *desfaz Lenine*.". FASE 7d (P5, §5.5, R6.7c-1): a ação local vai a _agenda_desfazer_local; o replano do "Segure o dia" desfeito direto também volta o "não antes de" (_agenda_local_restaurar) e deixa a ação local desfeita. FASE 7f (P2; §5.2, R8.5-10, R8.5-11): a ação assumir volta antes do caminho genérico: uma pergunta nova, igual à de antes, com a mesma chave, que nasce pelo gatilho com o padrão e sem prazo; a ação fica desfeita. Passou desfazivel_ate (2 dias úteis às veto_hora): a recusa manda dizer com as palavras dele.';

-- ── 10. Portas ──────────────────────────────────────────────────────────────────────────────────────
-- Sem grant a ninguém: quem as chama é definer (agenda_gestor_rodar, agenda_comunicar_rodar, agenda_perguntas_em_ordem). As recriadas mantêm as portas de antes (repetidas para a migration valer sozinha).
revoke all on function public._agenda_pergunta_espera(public.agenda_perguntas, date),
                       public._agenda_pergunta_frases(public.agenda_perguntas, date),
                       public._agenda_pergunta_linha(uuid, date, timestamptz),
                       public._agenda_pergunta_assumir(uuid, text, date, timestamptz),
                       public._agenda_destrava(public.agenda_perguntas, date),
                       public._agenda_comunicar_destrava(date, timestamptz),
                       public._agenda_comunicar_teto(date, timestamptz),
                       public._agenda_gestor_vetos(date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.agenda_perguntas_em_ordem(date, timestamptz) from public, anon;
grant execute on function public.agenda_perguntas_em_ordem(date, timestamptz) to authenticated, service_role;
revoke all on function public.agenda_comunicar_rodar(date, timestamptz),
                       public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
                       public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_comunicar_rodar(date, timestamptz),
                          public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
                          public.agenda_desfazer(uuid, uuid, text, date, timestamptz)
  to service_role;
