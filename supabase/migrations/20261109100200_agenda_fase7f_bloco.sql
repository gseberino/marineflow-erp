-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P3: o bloco da agenda nos 3 turnos da tarde — o veredito, o dia, o que mudou, as decisões e as compras, com a
-- ordem de corte por dentro, e o registro do que o dono viu (a pergunta mostrada, a conferência e o prazo escrito).
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§5.3, §6.1, §8.3 agenda_fase7f_bloco.sql e o bloco R8, que vale sobre o corpo: R8.1, R8.2, R8.4, R8.5-15, R8.5-27, R8.6, R8.7, R8.8, R8.12,
-- R8.13); nomes: fase7-registro.md §1 (7f P3); notas: notas-fase7f.md, seções P1 e P2 ("Para o P3").
-- Depende das Fases 1 a 6, do lote de 30/10, das etapas 7a a 7d e de 20261109100000 e 20261109100100 da 7f. NÃO depende da 7e.
--
-- ═══ SÓ FUNÇÕES — OK NOMEADO ═══ (4 funções novas, 2 recriadas; nenhuma tabela, nenhuma coluna, nenhuma lista, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p3/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA
-- (conferida a cada montagem), e a mudança está só nos blocos "-- FASE 7f: … -- FASE 7f: fim". Tirados os blocos, o corpo é o da origem, byte a byte (o montador e o L8 de
-- supabase/tests/agenda_fase7f_bloco.sql conferem).
--
-- POR QUE: em 06/11 a agenda tinha 8 linhas e mostrou 1; em 05/11, 7 e 1; em 04/11, 4 e 0. As linhas reais têm de 253 a 449 letras e disputam as vagas de REGRAS.maxManha com o que é do
-- Secretário: uma só toma o fechamento. O bloco mostra o mesmo em forma curta, por partes, e cede por dentro antes de sair: é assim que a agenda cabe nos 3 turnos.
--
-- O QUE MUDA:
--   1. _agenda_bloco_destino (nova): a lista fechada dos tipos de _agenda_linhas_do_fechamento, cada um com o seu destino. Tipo novo sem destino vai para "outras" e o L4b reprova.
--   2. _agenda_feito_planejado (nova): os meios-dias de hoje, marcados, feitos e os que faltam dizer como foi. Só diz "feito" com resultado gravado (R8.4).
--   3. agenda_bloco_do_fechamento (nova): recebe as linhas que agenda_textos_do_fechamento já leu (p_linhas) e só lê o que as linhas não têm: o amanhã, as mudanças uma a uma, as perguntas na
--      ordem, a contagem das compras, os meios-dias de hoje e, na quinta, a hora da mensagem da semana. Cada linha do bloco diz em que nível entra e em que nível sai, e o Secretário corta
--      pelos mesmos números. Definer: as funções da 7f não têm grant, e a porta está aqui dentro.
--   4. agenda_textos_do_fechamento (recriada): as 2 saídas levam a chave bloco, quando modo_bloco_agenda não é desligado. As linhas continuam lidas uma vez só.
--   5. agenda_fechamento_registrar (recriada): cada linha pode trazer veto_ate, o prazo escrito no texto que o dono viu, e ele é gravado no MESMO update que conta a pergunta como mostrada.
--      veto_diria, o prazo que seria, vai para veto_teria_em.
--
-- O QUE NÃO MUDA: com modo_bloco_agenda desligado, nenhuma leitura nova roda. Em sombra, o texto do fechamento, das 2 revisões, as linhas, as perguntas e as mensagens são os de antes, byte
-- a byte; a chave bloco vai só ao detalhe de resumo_tarde. agenda_decisoes_abertas, _agenda_linhas_do_fechamento e _agenda_compras_da_semana não são recriadas. Não muda nada do que o retorno lê
-- (pedidos-do-retorno.md, item 13).
--
-- ORDEM DE LIGAR (spec R8.14): depois de 20261109100100 e junto do ai-daily-briefing do pacote. Aplicar sozinha não muda nada para ninguém (modo_bloco_agenda nasce desligado).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_bloco.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109100200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261109100200_agenda_fase7f_bloco.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261109100200', 'agenda_fase7f_bloco');"
--
-- DESFAZER: reaplicar as definições de 20261031100980 (agenda_textos_do_fechamento e agenda_fechamento_registrar) e apagar as novas:
--   drop function if exists public.agenda_bloco_do_fechamento(date, timestamptz, jsonb), public._agenda_feito_planejado(date),
--     public._agenda_bloco_linha(text, text, integer, integer, uuid, jsonb), public._agenda_bloco_destino(text);
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. A lista fechada ─────────────────────────────────────────────────────────────────────
-- R8.4: 5 dos tipos de _agenda_linhas_do_fechamento sumiriam calados com o bloco ligado. Cada tipo tem o seu destino aqui, e quem soma um tipo novo soma aqui: o L4b lê o corpo das 2 funções que
-- montam as linhas e reprova tipo sem destino. Nulo = tipo que esta lista não conhece: o bloco o mostra em "outras" e o diz em sem_destino, em vez de calar.
create or replace function public._agenda_bloco_destino(p_tipo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_tipo
    when 'decisao' then 'ordem'     -- as 3 vêm de agenda_perguntas_em_ordem, que escolhe quais aparecem
    when 'pergunta' then 'ordem'
    when 'diaria' then 'ordem'
    when 'cliente' then 'cliente'   -- com pergunta: decisão sem prazo; sem pergunta (o que sai amanhã): outras
    when 'comissao' then 'outras'
    when 'compras' then 'compras'
    when 'dia' then 'hoje'
    when 'ppc' then 'hoje'
    when 'mudancas' then 'mudou'
    when 'conclusao' then 'mudou'
    when 'semana' then 'semana'     -- sai com a mensagem da semana; sem ela, fica no bloco
    when 'gestor' then 'sai'        -- *agenda gestor* mostra: não coube em nenhum fechamento (R8.4)
  end;
$function$;

comment on function public._agenda_bloco_destino(text) is
  'Agenda de Produção (Fase 7f, P3; R8.4): a lista fechada dos tipos de linha do fechamento: ordem (as perguntas, por agenda_perguntas_em_ordem), cliente, outras, compras, hoje, mudou, semana, sai. Nulo = tipo que a lista não conhece. Sem grant: quem a chama é agenda_bloco_do_fechamento.';

-- ── 2. O dia de hoje ───────────────────────────────────────────────────────────────────────
-- R8.4: "Foram feitos" só com resultado gravado: em 06/11 eram 0 de 53, e a frase é sempre "falta dizer como foi". sem_registro não diz nem feito nem não feito: conta como falta. Meio-dia é a
-- alocação de presença turno: quem só abre ou fecha não é meio-dia. A cancelada hoje por pessoa, clima ou material é meio-dia marcado que não aconteceu. O motivo é o mesmo texto de
-- planejado_realizado.motivo_texto (_agenda_motivo_texto). OS sem cliente sai pelo número (só 1 caso na carteira: serviço interno).
create or replace function public._agenda_feito_planejado(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_nao_max constant int := 2;   -- estrutural: quantos não feitos a frase cita; o resto vai no "e mais N"
  v_tot int;
  v_fei numeric;
  v_pen int;
  v_nao text[];
  v_txt text;
begin
  if p_hoje is null then
    raise exception '_agenda_feito_planejado: sem o dia de hoje' using errcode = '22004';
  end if;
  with a as (
    select x.service_order_id as os, x.turno,
           case when x.estado = 'cancelada' then 'nao_cumprido' else x.resultado end as res,
           case when x.estado = 'cancelada' and x.cancelada_motivo = 'pessoa' then 'equipe_faltou'
                when x.estado = 'cancelada' then x.cancelada_motivo else x.motivo end as motivo
      from public.agenda_alocacoes x
     where x.dia = p_hoje and x.tipo <> 'reserva' and x.presenca = 'turno'
       and (x.estado in ('publicada', 'fixada')
            or (x.estado = 'cancelada' and x.cancelada_motivo in ('pessoa', 'clima', 'material')
                and (x.cancelada_em at time zone 'America/Sao_Paulo')::date = p_hoje))
  ), n as (
    select distinct a.os, a.turno, a.res, a.motivo from a where a.res in ('parcial', 'nao_cumprido')
  )
  select (select count(*)::int from a),
         (select coalesce(sum(case a.res when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end), 0) from a),
         (select count(*)::int from a where a.res is null or a.res = 'sem_registro'),
         array(select format('%s %s %s (%s)', coalesce(public._agenda_nome_curto(cl.name), so.service_order_number),
                             case n.turno when 'manha' then 'de manhã' else 'à tarde' end,
                             case n.res when 'parcial' then 'em parte' else 'não' end,
                             coalesce(public._agenda_motivo_texto(n.motivo), 'sem motivo'))
                 from n join public.service_orders so on so.id = n.os left join public.clients cl on cl.id = so.client_id
                order by n.turno = 'tarde', so.service_order_number collate "C", n.res)
    into v_tot, v_fei, v_pen, v_nao;
  v_txt := case
    when v_tot = 0 then null
    when v_pen = v_tot then format('Hoje: %s %s; falta dizer como foi (*dia feito* confirma).', public._agenda_plural(v_tot, 'meio-dia', 'meios-dias'),
                                   case when v_tot = 1 then 'marcado' else 'marcados' end)
    when v_fei = v_tot then case when v_tot = 1 then 'Hoje: o meio-dia marcado foi feito.' else format('Hoje: os %s meios-dias marcados foram feitos.', v_tot) end
    else format('Hoje: %s de %s feitos', public._agenda_num(v_fei), public._agenda_plural(v_tot, 'meio-dia', 'meios-dias'))
         || case when cardinality(v_nao) > 0 then '; ' || public._agenda_lista(v_nao, c_nao_max) else '' end
         || case when v_pen > 0 then format('; falta dizer como foi em %s (*dia feito* confirma)', v_pen) else '' end || '.' end;
  return jsonb_build_object('texto', v_txt, 'planejados', v_tot, 'feitos', v_fei, 'pendentes', v_pen);
end;
$function$;

comment on function public._agenda_feito_planejado(date) is
  'Agenda de Produção (Fase 7f, P3; §5.3, §6.1, R8.4, R8.12-2, R8.12-9): os meios-dias de hoje, sem reserva: {texto, planejados, feitos (cumprido 1, parcial 0,5), pendentes (sem resultado ou sem registro)}. Texto nulo sem plano hoje. "Feito" só com resultado gravado. Sem grant: quem a chama é agenda_bloco_do_fechamento.';

-- Uma linha do bloco: o que ela é, em que nível entra, em que nível sai e o que conta como visto. As 2 chaves de pergunta em toda linha: o registro lê as duas (R8.4).
create or replace function public._agenda_bloco_linha(p_parte text, p_texto text, p_entra integer, p_corte integer, p_pergunta uuid default null, p_acoes jsonb default '[]'::jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select jsonb_build_object('parte', p_parte, 'texto', p_texto, 'nivel_entra', p_entra, 'nivel_de_corte', p_corte, 'pergunta_id', p_pergunta,
                            'pergunta_ids', case when p_pergunta is null then '[]'::jsonb else jsonb_build_array(p_pergunta) end, 'acao_ids', p_acoes, 'veto_ate', null);
$function$;

comment on function public._agenda_bloco_linha(text, text, integer, integer, uuid, jsonb) is
  'Agenda de Produção (Fase 7f, P3; R8.4): uma linha de agenda_bloco_do_fechamento. Sem grant.';

-- ── 3. O bloco ─────────────────────────────────────────────────────────────────────────────
-- R8.4. Recebe p_linhas: as linhas que agenda_textos_do_fechamento já leu, sem reler _agenda_linhas_do_fechamento. Lê só o que elas não têm. Cada parte que lê está no seu begin … exception: a
-- que falha deixa incompleto = true, e o veredito vira a frase de falha, nunca "nada mudou" (§3.1 item 12). when others não pega query_canceled: o tempo esgotado sobe e quem lê registra.
--
-- Os níveis (§3.1 item 6). Cada linha diz em que nível entra (nivel_entra) e em que nível sai (nivel_de_corte, nulo = nunca): quem corta filtra pelo número, e nenhum texto do corte mora fora daqui.
--   0  tudo
--   1  "outras" saem; as compras viram "+N compras"
--   2  "Mudou" vira "mudei N coisas"; a semana entra nessa conta; o resto do dia (Etapas, as frases do dia, a semana medida) sai
--   3…  uma decisão a menos por nível, com "(e mais N em *agenda pendências*)", até sobrar a 1ª
--   nivel_min  só o veredito e a 1ª decisão, que nunca saem
-- nivel = o menor nível em que o bloco cabe em bloco_max_chars; chars = as letras dele nesse nível.
--
-- As perguntas vêm na ordem de agenda_perguntas_em_ordem, menos o que o dono já respondeu e o que um aviso de hoje já levou (a mesma regra das linhas). A mensagem ao cliente que espera *manda
-- cliente* perde amanhã: vai logo depois da crítica que perde amanhã, sem prazo e sem a mensagem inteira, que está em *agenda clientes* (R8.4: uma só tomaria o bloco). O número impresso é o de
-- agenda_decisoes_abertas, que vem dentro da linha (R8.7).
create or replace function public.agenda_bloco_do_fechamento(p_hoje date, p_agora timestamptz, p_linhas jsonb)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  c_nivel_compras constant int := 1;
  c_nivel_mudou   constant int := 2;
  c_linha_max     constant int := 220;  -- estrutural: a linha de decisão da §6.2
  c_dias constant text[] := array['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
  -- O que só a linha dia traz, e o Hoje não diz: o último dia da OS e a diária lançada, com a palavra que corrige. As frases vêm prontas dentro da linha: saem dela, sem reler o dia.
  c_frases_do_dia constant text :=
    '(Hoje era o último dia do .*? fecha a OS \(saída e cobranças da condição\)\.|O \S+ confirmou (?:o dia todo|meio dia) e lancei a (?:diária|meia diária) dele \(R\$ [^)]*\)\.|\*diária \S+ (?:meia|inteira)\* corrige\.)';
  cf      public.agenda_config := public._agenda_cfg();
  v_uid   uuid := auth.uid();
  v_papel text;
  v_modo  text;
  v_lin   jsonb := case when jsonb_typeof(p_linhas) = 'array' then p_linhas else '[]'::jsonb end;
  v_am    date;
  v_inc   boolean := false;
  v_semd  text[] := '{}';
  l       jsonb;
  v_des   text;
  m       text[];
  -- o que vem de p_linhas
  v_conf  jsonb;
  v_cli   jsonb;
  v_cmp   jsonb;
  v_con   jsonb := '[]'::jsonb;
  v_smn   jsonb := '[]'::jsonb;
  v_ext   text[] := '{}';
  v_out   jsonb := '[]'::jsonb;
  -- hoje
  v_fp    jsonb;
  v_hoje  text;
  -- mudou
  v_grupos jsonb := '[]'::jsonb;
  v_frases text[] := '{}';
  v_mids  jsonb := '[]'::jsonb;
  v_nmud  int := 0;
  v_mud   text;
  -- as decisões
  v_dec   jsonb := '[]'::jsonb;
  v_tot   int := 0;
  v_mos   int := 0;
  -- as compras
  v_ncmp  int := 0;
  v_cate  date;
  -- a quinta
  v_env   timestamptz;
  -- o veredito
  v_prox  date;
  v_rot   text;
  v_quem  text[];
  v_px    record;
  v_ama   text;
  v_txt   text;
  v_diz   text[] := '{}';
  v_ver   text;
  -- o bloco
  v_min   int;
  v_ls    jsonb := '[]'::jsonb;
  v_nivel int;
  v_chars int;
  i       int;
  d       jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_bloco_do_fechamento: sem o dia ou a hora.' using errcode = '22004';
  end if;
  -- Quem vê: a mesma porta de agenda_perguntas_em_ordem
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O bloco da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'O bloco da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  v_modo := public._agenda_fala_modo('bloco');
  if v_modo = 'desligado' then
    return jsonb_build_object('modo', v_modo);
  end if;

  -- As linhas ligadas, cada tipo no seu destino, sem ler nada. A em sombra é o que a agenda diria: nunca entra.
  for l in select x from jsonb_array_elements(v_lin) x where x ->> 'modo' = 'ligado' loop
    v_des := public._agenda_bloco_destino(l ->> 'tipo');
    if v_des is null then
      v_semd := v_semd || (l ->> 'tipo');
      v_des := 'outras';
    end if;
    if v_des = 'compras' then
      v_cmp := l;
    elsif v_des = 'semana' then
      v_smn := v_smn || jsonb_build_array(l);
    elsif v_des = 'mudou' and l ->> 'tipo' = 'conclusao' then
      v_con := v_con || jsonb_build_array(l);
    elsif v_des = 'cliente' and l ->> 'pergunta_id' is not null then
      v_cli := l;
    elsif v_des in ('cliente', 'outras') then
      v_out := v_out || jsonb_build_array(l);
    elsif l ->> 'tipo' = 'dia' and l ->> 'texto' like 'Etapas%' then
      v_ext := v_ext || coalesce(l ->> 'texto_curto', l ->> 'texto');
    elsif l ->> 'tipo' = 'dia' then
      -- com a conferência aberta, ela; com todos confirmados, a linha sem pergunta, que conta o dia
      v_conf := l;
    elsif l ->> 'tipo' = 'ppc' then
      -- a 1ª frase de agenda_ppc: o resto é a lista dos dias, que *agenda* mostra
      v_ext := v_ext || (rtrim(split_part(l ->> 'texto', '. ', 1), '.') || '.');
    end if;
  end loop;

  -- Hoje
  begin
    v_fp := public._agenda_feito_planejado(p_hoje);
    v_hoje := coalesce(v_fp ->> 'texto', v_conf ->> 'texto');
    if v_fp ->> 'texto' is not null and v_conf is not null then
      for m in select regexp_matches(v_conf ->> 'texto', c_frases_do_dia, 'g') loop
        v_ext := v_ext || m[1];
      end loop;
    end if;
  exception when others then
    v_inc := true;
    v_hoje := v_conf ->> 'texto';
  end;

  -- Mudou: a exceção primeiro, depois o que mexe no que a equipe ou o cliente já sabem, depois a mais antiga (§5.3). A publicação não é frase: ela é a parte semana. A conclusão vem de p_linhas.
  begin
    select coalesce(jsonb_agg(g order by o), '[]'::jsonb) into v_grupos
      from (select x.g, row_number() over (order by (x.c ->> 'excecao')::boolean desc,
                                                    ((x.c #>> '{afeta,equipe}')::boolean or (x.c #>> '{afeta,cliente}')::boolean) desc,
                                                    x.g ->> 'em', x.o) as o
              from (select g, o, public._agenda_classe_da_saida('acao', (g -> 'acao_ids' ->> 0)::uuid, p_hoje, p_agora) as c
                      from jsonb_array_elements(public._agenda_mudancas(p_hoje - 6, p_hoje, true, true, null)) with ordinality t(g, o)
                     where g ->> 'tipo' = 'acao') x) y;
    v_frases := array(select x ->> 'texto' from jsonb_array_elements(v_con) x)
                || array(select public._agenda_mudanca_texto(g, false) from jsonb_array_elements(v_grupos) with ordinality t(g, o) order by o);
    v_mids := coalesce((select jsonb_agg(i2) from (select x -> 'acao_ids' as a from jsonb_array_elements(v_con || v_grupos) x) y,
                                                  jsonb_array_elements(y.a) i2), '[]'::jsonb);
    v_nmud := cardinality(v_frases);
  exception when others then
    v_inc := true;
  end;
  -- Frase a frase, até caber no bloco: linha maior que ele nunca sairia, e a frase de uma ação vai a 400 letras. Nem 1 frase cabendo, fica só a contagem, desde o nível 0.
  for i in reverse least(v_nmud, cf.bloco_mudancas_max) .. 1 loop
    v_mud := 'Mudou: ' || array_to_string(v_frases[1:i], ' ') || case when v_nmud > i then format(' (e mais %s em *o que mudou*).', v_nmud - i) else '' end;
    exit when char_length(v_mud) <= cf.bloco_max_chars;
    v_mud := null;
  end loop;

  -- A semana: com a mensagem da quinta enviada, ela já contou (R8.4). Sem ela, a linha fica: sem isso a publicação sumiria calada e o veredito diria "nada mudou". A hora é a que saiu (R8.5-15).
  if extract(isodow from p_hoje)::int = cf.dia_do_plano then
    begin
      select v.enviada_em into v_env from public.agenda_dono_avisos v
       where v.dedupe_key = 'agenda-dono:semana:' || p_hoje::text;
    exception when others then
      v_inc := true;
    end;
    if v_env is not null then
      v_smn := '[]'::jsonb;
    end if;
  end if;
  v_nmud := v_nmud + jsonb_array_length(v_smn);

  -- As decisões
  v_am := public.agenda_somar_du(p_hoje, 1);
  begin
    select coalesce(jsonb_agg(x.e order by x.o), '[]'::jsonb) into v_dec
      from (select e, (e ->> 'ordem')::int as o
              from jsonb_array_elements(public.agenda_perguntas_em_ordem(p_hoje, p_agora)) e
              join public.agenda_perguntas q on q.id = (e ->> 'id')::uuid
             where q.opcao_escolhida is null
               and (q.critica or not exists (select 1 from public.agenda_dono_avisos v
                                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and q.id = any (v.pergunta_ids)))
               and e ->> 'id' is distinct from v_cli ->> 'pergunta_id') x;
  exception when others then
    v_inc := true;
    v_dec := '[]'::jsonb;
  end;
  if v_cli is not null then
    i := coalesce((select count(*)::int from jsonb_array_elements(v_dec) e join public.agenda_perguntas q on q.id = (e ->> 'id')::uuid
                    where q.critica and q.perda_em <= v_am), 0);
    v_dec := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_dec) with ordinality t(e, o) where o <= i), '[]'::jsonb)
             || jsonb_build_array(jsonb_build_object('id', v_cli ->> 'pergunta_id',
                  'linha', public._agenda_corta(regexp_replace(v_cli ->> 'texto', ': ".*"( \(\*agenda clientes\* mostra inteira\))?\. \*manda', '. *manda'), c_linha_max)))
             || coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_dec) with ordinality t(e, o) where o > i), '[]'::jsonb);
  end if;
  v_tot := jsonb_array_length(v_dec);
  v_mos := least(v_tot, cf.bloco_decisoes_max);

  -- As compras: o texto de p_linhas; daqui, só quantas são e o dia mais cedo, para o veredito e a forma cortada
  if v_cmp is not null then
    begin
      select count(*)::int, min((e ->> 'compre_ate')::date) into v_ncmp, v_cate
        from public.agenda_gestor_dia g, jsonb_array_elements(g.compras) e
       where g.dia = p_hoje and nullif(btrim(e ->> 'texto'), '') is not null;
    exception when others then
      v_inc := true;
    end;
    v_ncmp := greatest(v_ncmp, 1);
  end if;

  -- O veredito, por último: ele conta o que vem abaixo
  begin
    v_prox := v_am;
    v_rot := case when v_prox = p_hoje + 1 then 'Amanhã (' || public._dia_curto(v_prox) || ')'
                  else c_dias[extract(dow from v_prox)::int + 1] || ' (' || to_char(v_prox, 'DD/MM') || ')' end;
    v_quem := array(select coalesce(d2.cliente_curto, d2.unidade, d2.numero)
                           || case when d2.reserva then ' (reserva)'
                                   else coalesce(' com ' || nullif(public._agenda_lista(array(
                                          select case when coalesce((p ->> 'eh_dono')::boolean, false) then 'você' else p ->> 'nome' end
                                            from jsonb_array_elements(d2.pessoas) with ordinality t(p, o) order by o), null), ''), '') end
                      from public.v_agenda_dia d2 where d2.dia = v_prox
                     order by d2.primeiro_inicio, d2.numero, d2.service_order_id);
    if cardinality(v_quem) > 0 then
      v_ama := v_rot || ': ' || public._agenda_lista(v_quem, cf.bloco_decisoes_max) || '.';
    else
      select coalesce(d2.cliente_curto, d2.unidade, d2.numero) as nome, d2.dia into v_px
        from public.v_agenda_dia d2 where d2.dia > v_prox and not d2.reserva
       order by d2.dia, d2.primeiro_inicio, d2.numero, d2.service_order_id limit 1;
      v_ama := v_rot || ' sem serviço marcado' || case when v_px.dia is null then '' else format('; o próximo é %s, %s', v_px.nome, public._dia_curto(v_px.dia)) end || '.';
    end if;
  exception when others then
    v_inc := true;
  end;
  if v_nmud > 0 then
    v_diz := v_diz || ('mudei ' || public._agenda_plural(v_nmud, 'coisa', 'coisas'));
  end if;
  if v_tot > 0 then
    v_diz := v_diz || ('preciso de ' || public._agenda_plural(v_tot, 'resposta sua', 'respostas suas'));
  end if;
  if v_ncmp > 0 then
    v_diz := v_diz || (public._agenda_plural(v_ncmp, 'compra vence', 'compras vencem')
                       || case when v_cate is null then '' else ' até ' || public._dia_curto(v_cate) end);
  end if;
  v_ver := case
    when v_inc then 'Agenda: não consegui ler a agenda inteira agora; *agenda* mostra o que está marcado.'
    when v_env is not null and cardinality(v_diz) = 0 then
      format('Agenda: a semana que vem foi às %s; desde então nada mudou.', to_char(v_env at time zone 'America/Sao_Paulo', 'HH24:MI'))
    when cardinality(v_diz) = 0 then 'Agenda: nada mudou. ' || v_ama
    when v_nmud = 0 and v_tot = 0 then format('Agenda: nada mudou; %s. %s', v_diz[1], v_ama)
    else format('Agenda: %s. %s', public._agenda_lista(v_diz, null), v_ama) end;

  -- O bloco, na ordem do texto (§6.1)
  v_min := greatest(v_mos, 1) + c_nivel_mudou;
  v_ls := jsonb_build_array(public._agenda_bloco_linha('veredito', v_ver, 0, null));
  if v_hoje is not null then
    v_ls := v_ls || public._agenda_bloco_linha('hoje', v_hoje, 0, v_min, (v_conf ->> 'pergunta_id')::uuid,
                                                coalesce(v_conf -> 'acao_ids', '[]'::jsonb) - array(select jsonb_array_elements_text(v_mids)));
  end if;
  foreach v_txt in array v_ext loop
    v_ls := v_ls || public._agenda_bloco_linha('hoje', v_txt, 0, c_nivel_mudou);
  end loop;
  if v_mud is not null then
    v_ls := v_ls || public._agenda_bloco_linha('mudou', v_mud, 0, c_nivel_mudou, null, v_mids);
  end if;
  for l in select x from jsonb_array_elements(v_smn) x loop
    v_ls := v_ls || public._agenda_bloco_linha('semana', l ->> 'texto', 0, c_nivel_mudou, null, l -> 'acao_ids');
  end loop;
  if v_nmud > 0 then
    v_ls := v_ls || public._agenda_bloco_linha('mudou', format('Mudou: mudei %s (*o que mudou*).', public._agenda_plural(v_nmud, 'coisa', 'coisas')), case when v_mud is null then 0 else c_nivel_mudou end, v_min, null,
                                                v_mids || coalesce((select jsonb_agg(i2) from jsonb_array_elements(v_smn) x, jsonb_array_elements(x -> 'acao_ids') i2), '[]'::jsonb));
  end if;
  for i in 1 .. v_mos loop
    d := v_dec -> (i - 1);
    v_ls := v_ls || (public._agenda_bloco_linha('decisao', '· ' || (d ->> 'linha'), 0, case when i = 1 then null else v_mos - i + c_nivel_mudou + 1 end, (d ->> 'id')::uuid)
                     || jsonb_build_object('veto_ate', d -> 'veto_ate')
                     || case when d ? 'veto_diria' then jsonb_build_object('veto_diria', d -> 'veto_diria') else '{}'::jsonb end);
  end loop;
  -- "(e mais N)": uma linha por nível, cada uma com a conta daquele nível. N = o que não está à vista nele.
  for i in reverse v_mos .. 1 loop
    continue when v_tot - i = 0;
    v_ls := v_ls || public._agenda_bloco_linha('decisao', format('(e mais %s em *agenda pendências*)', v_tot - i),
                                                case when i = v_mos then 0 else v_mos - i + c_nivel_mudou end, v_mos - i + c_nivel_mudou + 1);
  end loop;
  if v_cmp is not null then
    v_ls := v_ls || public._agenda_bloco_linha('compras', v_cmp ->> 'texto', 0, c_nivel_compras, null, coalesce(v_cmp -> 'acao_ids', '[]'::jsonb));
    v_ls := v_ls || public._agenda_bloco_linha('compras', format('+%s (*agenda compras*).', public._agenda_plural(v_ncmp, 'compra', 'compras')), c_nivel_compras, v_min);
  end if;
  for l in select x from jsonb_array_elements(v_out) x loop
    v_ls := v_ls || public._agenda_bloco_linha('outras', l ->> 'texto', 0, c_nivel_compras, null, coalesce(l -> 'acao_ids', '[]'::jsonb));
  end loop;

  select x.k, x.c into v_nivel, v_chars
    from (select k, (select coalesce(sum(char_length(y ->> 'texto') + 1), 1)::int - 1 from jsonb_array_elements(v_ls) y
                      where (y ->> 'nivel_entra')::int <= k and (y ->> 'nivel_de_corte' is null or k < (y ->> 'nivel_de_corte')::int)) as c
            from generate_series(0, v_min) k) x
   order by x.c > cf.bloco_max_chars, case when x.c > cf.bloco_max_chars then -x.k else x.k end
   limit 1;
  return jsonb_build_object('modo', v_modo, 'linhas', v_ls, 'nivel', v_nivel, 'nivel_min', v_min, 'chars', v_chars, 'incompleto', v_inc,
                            'nada_mudou', not v_inc and v_nmud = 0 and v_tot = 0 and v_cmp is null)
         || case when cardinality(v_semd) > 0 then jsonb_build_object('sem_destino', to_jsonb(v_semd)) else '{}'::jsonb end;
end;
$function$;

comment on function public.agenda_bloco_do_fechamento(date, timestamptz, jsonb) is
  'Agenda de Produção (Fase 7f, P3; §5.3, §6.1, R8.4, R8.5-15, R8.7, R8.8): o bloco da agenda na tarde, a partir das linhas que agenda_textos_do_fechamento já leu (p_linhas): {modo, linhas: [{parte (veredito, hoje, mudou, semana, decisao, compras, outras), texto, pergunta_id, pergunta_ids, acao_ids, veto_ate, veto_diria, nivel_entra, nivel_de_corte (nulo = nunca sai)}], nivel (o menor em que cabe em bloco_max_chars), nivel_min (só o veredito e a 1ª decisão), chars, nada_mudou, incompleto, sem_destino}. As linhas do nível n são as de nivel_entra <= n < nivel_de_corte. Desligado: {modo}. Administrador, financeiro ou service_role; senão 42501.';

-- ── 4. A saída de agenda_textos_do_fechamento ──────────────────────────────────────────────
-- agenda_textos_do_fechamento (de 20261031100980)
create or replace function public.agenda_textos_do_fechamento(p_hoje date default public._hoje_brt(), p_dia date default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_pn     jsonb;
  v_dia    date;
  v_marc   jsonb;
  v_prox   jsonb;
  v_prontos jsonb;
  v_esp    int;
  v_plano  boolean;
  v_seg    date;
  v_cauda  text;
  v_sem    text[] := '{}';
  v_l      text;
  k        int;
  c_max    constant int := 160;
  -- FASE 7: (7a P7) as vagas da agenda no fechamento
  v_f7_lin jsonb;
  v_f7_n   int;
  -- FASE 7: fim
  -- FASE 7: (7a correção, achados 15 e 18) quantas linhas ligadas perdem hoje
  v_f77_n  int;
  -- FASE 7: fim
  -- FASE 7f: (7f P3) o bloco
  v_7f_on    boolean;
  -- FASE 7f: fim
begin
  if p_hoje is null then
    raise exception 'agenda_textos_do_fechamento: sem o dia de hoje' using errcode = '22004';
  end if;
  if c.modo_leitura = 'desligado' then
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', null, 'semana_que_vem', '[]'::jsonb,
                              'dia_do_plano', false,
                              -- FASE 2: com a leitura desligada a agenda inteira cala
                              'linhas', '[]'::jsonb);
  end if;
  v_dia := coalesce(p_dia, p_hoje + 1);
  v_pn := public._agenda_painel(p_hoje);
  v_plano := extract(isodow from p_hoje)::int = c.dia_do_plano;

  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(v_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  select count(*) into v_esp from jsonb_array_elements(v_pn -> 'oss') e where (e ->> 'dono_trava')::boolean;

  -- A cauda do "Amanhã" sem nada marcado. Se a agenda vê algo marcado no dia, não há cauda (o Secretário diz o dia).
  -- (FASE 2: em 'ligado' o marcado é o plano — _agenda_marcados.)
  v_marc := public._agenda_marcados(v_dia, v_dia, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
  if jsonb_array_length(v_marc) = 0 then
    v_cauda := 'nada marcado; '
      || case when jsonb_array_length(v_prontos) > 0 then 'prontos para começar: ' || public._agenda_nomes(v_prontos, 3)
              when (v_pn #>> '{backlog,n}')::int = 0 then 'nenhum serviço na fila'
              when v_esp > 0 then format('nenhum serviço pronto, %s esperando você', v_esp)
              else 'nenhum serviço pronto ainda' end
      || ' (*agenda*)';
  end if;

  -- Só no dia do plano (quinta): até 3 linhas da semana que vem, cada uma com até 160 caracteres.
  -- FASE 2: com a agenda automática ligada a projeção não sai: a linha "semana" do publicado (linhas) a substitui.
  if v_plano and c.modo_proposta <> 'ligado' then
    v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1) + 7;
    v_prox := public._agenda_marcados(v_seg, v_seg + 5, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
    for k in reverse 3 .. 1 loop
      v_l := 'Semana que vem (projeção): '
             || case when jsonb_array_length(v_prox) = 0 then 'nada marcado'
                     else public._agenda_plural(jsonb_array_length(v_prox), 'marcado', 'marcados') || ' ('
                          || public._agenda_lista(array(select e ->> 'nome' from jsonb_array_elements(v_prox) with ordinality t(e, o)
                                                         order by o), k) || ')' end
             || case when (v_pn #>> '{backlog,n}')::int = 0 then '; nenhum serviço na fila.'
                     else '; ' || public._agenda_plural((v_pn #>> '{backlog,n}')::int, 'serviço na fila', 'serviços na fila')
                          || ', ' || public._agenda_fila_faixa(v_pn)
                          || case when (v_pn ->> 'comprometivel')::numeric > 0
                                  then format(' (~%s por semana, %s)', public._agenda_num((v_pn ->> 'comprometivel')::numeric, 1),
                                              case when (v_pn #>> '{cap,conta_dono}')::boolean then 'contando você' else 'sem contar você' end)
                                  else '' end || '.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    for k in reverse 3 .. 1 loop
      v_l := case when jsonb_array_length(v_prontos) > 0 then 'Prontos para começar: ' || public._agenda_nomes(v_prontos, k)
                  else 'Nenhum pronto para começar' end
             || case when v_esp > 0 then '; o que falta de você está em *agenda*.'
                     when jsonb_array_length(v_prontos) > 0 then '.' else ' ainda.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    v_l := public._agenda_livre_linha(v_pn, false);
    if v_l is not null then v_sem := v_sem || v_l; end if;
    v_sem := array(select x from unnest(v_sem) x where char_length(x) <= c_max);
  end if;

  -- FASE 7f: (7f P3, R8.4, R8.8) sem bloco, nada disto lê nada, e as 2 saídas de baixo são as de antes. Com ele, as 2 saídas levam a chave, e o bloco recebe as linhas que a saída já leu:
  -- uma leitura, uma regra. A hora é a de agenda.agora, como nas linhas.
  v_7f_on := public._agenda_fala_modo('bloco') <> 'desligado';
  -- FASE 7f: fim
  -- FASE 7: (7a P7) as vagas que a agenda tem garantidas no fechamento (spec §5.7 item 3, §7): com modo_vaga_fechamento
  -- ligado, fechamento_vagas_agenda (+1 com alguma linha ligada de decisão de perda ≥ 80 — a decisão crítica e a compra urgente —,
  -- até 2) em vagas_garantidas; em sombra, vagas_garantidas = 0 e vaga_teria = as que teria (o Secretário põe no detalhe).
  -- Desligado, a saída de antes, byte a byte. As linhas são lidas uma vez só (a mesma lista vai em linhas).
  if public._agenda_gestor_modo('vaga') <> 'desligado' then
    v_f7_lin := public._agenda_linhas_do_fechamento(p_hoje);
    v_f7_n := least(2, c.fechamento_vagas_agenda
                       + case when exists (select 1 from jsonb_array_elements(v_f7_lin) x
                                            where x ->> 'modo' = 'ligado' and x ->> 'tipo' in ('decisao', 'compras')
                                              and (x ->> 'perda')::int >= 80) then 1 else 0 end);
    -- (7a correção, achados 15 e 18) cada linha ligada que perde hoje (perda >= 75: a decisão crítica, a diária com 2 dias
    -- úteis, a compra de hoje, a mensagem ao cliente que espera *manda cliente*, as perguntas do gestor) tem a sua vaga, até 3
    v_f77_n := (select count(*) from jsonb_array_elements(v_f7_lin) x
                 where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int >= 75)::int;
    v_f7_n := least(3, greatest(v_f7_n, v_f77_n));
    -- (7f P3, dentro do bloco do 7a) a saída de modo_vaga_fechamento, com a chave bloco
    if v_7f_on then
      return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                                'dia_do_plano', v_plano, 'dia', v_dia,
                                'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                              'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                                'linhas', v_f7_lin,
                                'vagas_garantidas', case when public._agenda_gestor_modo('vaga') = 'ligado' then v_f7_n else 0 end,
                                'vaga_teria', case when public._agenda_gestor_modo('vaga') = 'sombra' then v_f7_n end)
             || jsonb_build_object('bloco', public.agenda_bloco_do_fechamento(p_hoje, coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now()), v_f7_lin));
    end if;
    -- (7f: fim)
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                              'dia_do_plano', v_plano, 'dia', v_dia,
                              'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                          'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                              'linhas', v_f7_lin,
                              'vagas_garantidas', case when public._agenda_gestor_modo('vaga') = 'ligado' then v_f7_n else 0 end,
                              'vaga_teria', case when public._agenda_gestor_modo('vaga') = 'sombra' then v_f7_n end);
  end if;
  -- FASE 7: fim
  -- FASE 7f: (7f P3) a saída final, com a chave bloco
  if v_7f_on then
    v_f7_lin := public._agenda_linhas_do_fechamento(p_hoje);
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                              'dia_do_plano', v_plano, 'dia', v_dia,
                              'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                          'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                              'linhas', v_f7_lin)
           || jsonb_build_object('bloco', public.agenda_bloco_do_fechamento(p_hoje, coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now()), v_f7_lin));
  end if;
  -- FASE 7f: fim
  return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                            'dia_do_plano', v_plano, 'dia', v_dia,
                            'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                        'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                            -- FASE 2: as linhas da agenda (decisões, o dia, a semana, o que mudou, uma pergunta)
                            'linhas', public._agenda_linhas_do_fechamento(p_hoje));
end;
$function$;

comment on function public.agenda_textos_do_fechamento(date, date) is
  'Agenda de Produção (Fase 1, P4; Fase 2, P5): as linhas da agenda no fechamento das 17:30 — cauda_amanha (o "Amanhã" sem nada marcado: "nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)" ou "nada marcado; prontos para começar: …"; null quando a agenda vê algo marcado em p_dia — em ''ligado'', o plano), só quando isodow(p_hoje) = dia_do_plano e a agenda automática não está ligada, até 3 linhas "Semana que vem (projeção)" de até 160 caracteres, e (FASE 2) linhas [{tipo, texto, perda, pergunta_id, acao_ids, modo}] de _agenda_linhas_do_fechamento. modo_leitura desligado: nada. O Secretário decide o que publica (sombra × ligado; vagas de REGRAS.maxManha). FASE 7 (7a P7, spec §5.7 item 3 e §7): com modo_vaga_fechamento fora de desligado, a saída ganha vagas_garantidas — com ligado, fechamento_vagas_agenda (+1 com alguma linha ligada de decisão de perda ≥ 80, a decisão crítica ou a compra urgente, até 2); em sombra, 0 — e vaga_teria (em sombra, as vagas que teria: o Secretário põe no detalhe); as linhas são lidas uma vez só. Desligado, a saída de antes, byte a byte. O Secretário soma vagas_garantidas às vagas que sobram de REGRAS.maxManha. CORREÇÃO DA 7a (revisão da etapa; achados 15 e 18): cada linha ligada que perde hoje (perda ≥ 75: a decisão crítica, a diária com 2 dias úteis, a compra de hoje, a mensagem ao cliente que espera *manda cliente*, a linha das perguntas do gestor) tem a sua vaga garantida, até 3 — vagas_garantidas = least(3, greatest(a conta de antes, as linhas de perda ≥ 75)). Antes eram no máximo 2, e a mensagem ao cliente da véspera tirava a vez da pergunta da ficha de amanhã. FASE 7f (P3; R8.4, R8.8): com modo_bloco_agenda fora de desligado, as 2 saídas levam a chave bloco (agenda_bloco_do_fechamento, sobre as linhas já lidas); sem ele, a saída de antes, e nada novo é lido.';

-- ── 5. O registro do que saiu ──────────────────────────────────────────────────────────────
-- agenda_fechamento_registrar (de 20261031100980)
create or replace function public.agenda_fechamento_registrar(p_hoje date, p_linhas jsonb, p_via text default 'fechamento',
                                                              p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  e      jsonb;
  v_perg int := 0;
  v_acao int := 0;
  v_n    int;
begin
  if p_via is null or p_via not in ('fechamento', 'acorde', 'conversa') then
    raise exception 'Por onde foi mostrado: "%" (fechamento, acorde ou conversa).', coalesce(p_via, '') using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_linhas, '[]'::jsonb)) <> 'array' then
    raise exception 'As linhas mostradas vêm numa lista.' using errcode = '22023';
  end if;
  for e in select x from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x loop
    if e ->> 'pergunta_id' is not null then
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = p_via
             -- FASE 7f: (7f P3, §3.1 item 7, §5.3, R8.5-1) no MESMO update que a mostra: o prazo escrito no texto que o dono viu. Sem veto_ate na linha, nada muda: ele é nulo em sombra e com o
             -- freio (_agenda_pergunta_linha), e o relógio nunca começa de um prazo que ele não leu. A que espera ele não ganha prazo. De um valor a outro, só a que nunca foi mostrada antes do
             -- prazo velho (a regra de _agenda_perguntas_antes): o que ele já viu com prazo não muda. veto_diria é o prazo que seria, em sombra: só veto_teria_em, para medir, uma vez.
             , veto_ate = case when q.veto_espera is not null then q.veto_ate
                               when q.veto_ate is null then (e ->> 'veto_ate')::timestamptz
                               when q.veto_ate < p_agora and (e ->> 'veto_ate')::timestamptz > q.veto_ate
                                    and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false) then (e ->> 'veto_ate')::timestamptz
                               else q.veto_ate end
             , veto_teria_em = coalesce(q.veto_teria_em, (e ->> 'veto_diria')::timestamptz)
             -- FASE 7f: fim
       where q.id = (e ->> 'pergunta_id')::uuid and q.estado = 'aberta';
      get diagnostics v_n = row_count;
      v_perg := v_perg + v_n;
    end if;
    -- FASE 7: (7a correção, achado 15) a linha das perguntas do gestor mostra várias: cada uma de pergunta_ids (fora a pergunta_id,
    -- já contada) ganha a mostrada
    if jsonb_typeof(e -> 'pergunta_ids') = 'array' then
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = p_via
       where q.id in (select y::uuid from jsonb_array_elements_text(e -> 'pergunta_ids') y)
         and q.id is distinct from nullif(e ->> 'pergunta_id', '')::uuid and q.estado = 'aberta';
      get diagnostics v_n = row_count;
      v_perg := v_perg + v_n;
    end if;
    -- FASE 7: fim
    if jsonb_typeof(e -> 'acao_ids') = 'array' then
      update public.agenda_acoes a set contada_em = p_agora, contada_via = p_via
       where a.id in (select y::uuid from jsonb_array_elements_text(e -> 'acao_ids') y) and a.contada_em is null;
      get diagnostics v_n = row_count;
      v_acao := v_acao + v_n;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'perguntas', v_perg, 'acoes', v_acao);
end;
$function$;

comment on function public.agenda_fechamento_registrar(date, jsonb, text, timestamptz) is
  'Agenda de Produção (Fase 2, P3): o que o fechamento (ou a conversa) mostrou da agenda — para cada linha {pergunta_id?, acao_ids?}: a pergunta aberta ganha mostrada_vezes + 1, mostrada_em e mostrada_via; as ações ainda não contadas ganham contada_em/contada_via. Chamada pelo secretário quando o fechamento saiu com as linhas da agenda em ligado. Só service_role. CORREÇÃO DA 7a (revisão da etapa; achado 15): a linha pode trazer também pergunta_ids (a linha das perguntas do gestor, que mostra várias numa só): cada pergunta aberta da lista que não é a pergunta_id ganha a mostrada. FASE 7f (P3; §3.1 item 7, §5.3): a linha pode trazer veto_ate, o prazo escrito no texto, gravado no mesmo update que mostra, só na pergunta que não espera o dono, sem prazo, ou que nunca foi mostrada antes do prazo velho. veto_diria vai para veto_teria_em. Sem as 2 chaves, nada muda.';

-- ── 6. Portas ──────────────────────────────────────────────────────────────────────────────
-- Sem grant a ninguém: quem as chama é agenda_bloco_do_fechamento, definer. O bloco é lido por agenda_textos_do_fechamento, que o painel também chama: a porta dele fica aqui dentro.
revoke all on function public._agenda_bloco_destino(text), public._agenda_bloco_linha(text, text, integer, integer, uuid, jsonb), public._agenda_feito_planejado(date)
  from public, anon, authenticated, service_role;
revoke all on function public.agenda_bloco_do_fechamento(date, timestamptz, jsonb) from public, anon;
grant execute on function public.agenda_bloco_do_fechamento(date, timestamptz, jsonb) to authenticated, service_role;
