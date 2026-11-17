-- Agenda de Produção: as perguntas com prazo voltam ao fechamento das 17:30 (17/11/2026, "perguntas com prazo não chegam ao dono", FASE 1 do plano
-- agenda-pesquisa/perguntas-com-prazo-1711/PLANO.md, com as respostas do dono 1A e 2A).
-- (2 funções recriadas da definição de produção: agenda_bloco_do_fechamento e _agenda_saude_comunicacao; nenhuma tabela, coluna, lista, job ou dado muda)
--
-- NÃO APLICADA. Existe para revisão e espera o OK na hora de aplicar.
-- ANTES DE APLICAR, uma escolha do dono (a revisão achou que a resposta 2A não a cobre): a linha do gestor ocupa 1 das bloco_decisoes_max vagas (como está aqui: o bloco
--   não cresce, e uma decisão da ordem sai da vista) ou não ocupa (o bloco ganha 1 linha). A outra opção é trocar a condição de v_ges_pos ("as vagas e a conta") e os casos
--   P2m, P2p, P2q e P2s de supabase/tests/agenda_prazo_no_bloco.sql (a troca pronta: agenda-pesquisa/perguntas-com-prazo-1711/rev3/impl/variante-nao-ocupa.patch).
--
-- ═══ POR QUÊ ═══
--   Em 14/11 09:58 o bloco da agenda (7f, R8.4) foi ligado no fechamento das 17:30. No bloco, toda linha tipo pergunta tem destino 'ordem' (_agenda_bloco_destino) e o laço
--   de entrada de agenda_bloco_do_fechamento não tem ramo para 'ordem': a linha (m) das perguntas do gestor (perda 76, da 7a correção 2, achados 15/18) era descartada.
--   As decisões passaram a vir só de agenda_perguntas_em_ordem, que põe as perguntas de prazo por último (nascem com destrava 0), e entram no máximo 3: a situacao, a
--   estimativa, o reestimar e a ficha_estimativa do dia não chegavam ao dono. Sem ser mostrada antes do prazo, a pergunta não é decidida (_agenda_gestor_vetos): caduca e
--   renasce dias depois — a decisão para em silêncio. Em 17/11: 22 abertas ligadas, 0 vistas; das 14 criadas desde 14/11, só 1 chegou ao dono.
--
-- ═══ O QUE MUDA ═══ (cada mudança num bloco "-- PRAZO NO BLOCO: (…) … -- PRAZO NO BLOCO: fim")
--   No bloco (agenda_bloco_do_fechamento):
--   1. A linha (m) — tipo pergunta, ligada, perda 76, com pergunta_ids — vira uma decisão do bloco (1A). As outras linhas pergunta (a (n) da equipe, perda 75/77; a (m) sem
--      prazo e a pergunta de fato, perda 30) continuam descartadas: a (n) é a F1b, com OK à parte.
--   2. Com ela no bloco, saem da ordem as perguntas que ela leva e TODA aberta ligada de situacao, estimativa, reestimar e ficha_estimativa com veto_ate (o acordo de antes do
--      bloco: pela ordem elas sairiam só com o título, sem "Sem resposta até …", e o prazo as decidiria sem o dono ter lido a data). As que saem da ordem e ela não
--      escreve não entram em nenhum "(e mais N …)" do bloco: o veredito as conta, e elas ficam em *agenda pendências* (que lista os 4 tipos abertos) e *agenda gestor*.
--      Só a forma inteira avisa a sobra da linha ("(e mais N em *agenda gestor*)", do texto da (m)); a curta não tem esse aviso.
--   3. Ela entra logo depois das críticas que perdem até amanhã e antes da mensagem ao cliente (2A: o prazo 1º, o cliente 2º). Ela e a do cliente nunca saem (nivel_de_corte
--      nulo); as outras seguem a regra de hoje (a 1ª nunca sai; das outras, a última sai primeiro, uma por nível a partir do 3). Ela ocupa 1 das bloco_decisoes_max vagas,
--      como qualquer decisão — o bloco não cresce —, e só passa das vagas quando a ordem a deixaria de fora (críticas demais antes dela). O veredito conta as perguntas que
--      ela cobre ("preciso de N respostas suas", o mesmo número de antes); o "(e mais N em *agenda pendências*)" conta só as da ordem.
--   4. A forma inteira (o texto da linha, sem o "Agenda: ") sai no nível 2; a curta (texto_curto, quando é menor) entra no nível 2 — o mesmo entra/corte do Mudou. Sem a curta, a
--      inteira nunca sai.
--   5. pergunta_ids de cada forma = as perguntas que ela ESCREVE: a inteira, todas as da linha; a curta, a 1ª e as que não são ficha_estimativa (ela só traz a 1ª ficha). O
--      Secretário (ai-daily-briefing) registra as linhas do nível que saiu (linhasDoBloco → agenda_fechamento_guardar): conta como mostradas só as daquela forma. A 2ª ficha
--      em diante, sem aparecer, não conta, e a rotina das 19:30 a segura como hoje.
--   6. Parte 'decisao'; veto_ate da linha nulo (os 4 tipos esperam pelo tipo — veto_espera 'tipo' — e o prazo deles já está gravado; quem decide é _agenda_gestor_vetos, com
--      a pergunta mostrada antes do prazo).
--   Na saúde (_agenda_saude_comunicacao; achado da revisão da F1):
--   7. O zero bloco_grande (um dos zeros do ok de agenda_saude, aceite 4 da 7f) contava o fechamento acima de texto_max com mais de 2 linhas de decisão. A tolerância é
--      "as fixas + 1": no nivel_min só ficam as decisões que nunca saem (o "(e mais N)" sai nele), e o +1 é o nível logo acima, que ainda tem o "(e mais N)"; antes, 1
--      fixa (a 1ª). Com a linha do gestor, o mínimo pode ter 3 decisões que nunca saem (a 1ª, a do gestor e a do cliente), e o fechamento que já estava no mínimo contaria
--      como bloco grande — o ok cairia sem motivo. Agora, com a do gestor no fechamento, a tolerância de 2 ganha +1 quando a 1ª decisão é uma crítica (sempre numerada,
--      "Decisão N:"; sem crítica, a 1ª é a do gestor) e +1 com a do cliente à vista. As marcas presas às linhas certas (revisão 3): a do gestor está no fechamento quando a
--      (m) ligada de perda 76 está em detalhe.agenda.linhas_diria e uma decisão à vista é a forma inteira dela ou a curta (que começa pelo trecho da ficha antes de
--      " 1) Mande" e " Para segurar, me diga.", ou por "Sem resposta até …, conto: "); a do cliente conta quando a linha cliente ligada de linhas_diria, escrita como o
--      bloco a escreve, é igual a uma decisão à vista (uma cliente_aprovar da ordem, "Mensagem para …" que pode sair, não conta). Sem a do gestor à vista, a conta de
--      antes, byte a byte — também nos fechamentos de antes de aplicar, que a janela de 7 dias ainda lê.
--
-- ═══ O QUE NÃO MUDA ═══ Sem a linha (m) ligada de perda 76 — o bloco desligado ou em sombra, a vigia em sombra, nenhuma pergunta de prazo — a saída do bloco é a de antes,
--   byte a byte, e a saúde também. Não muda _agenda_linhas_do_fechamento (as linhas são as mesmas), agenda_textos_do_fechamento, o registro, a ordem, agenda_saude nem o TS
--   do Secretário (ele já lê pergunta_ids das linhas do bloco do nível que saiu e já grava linhas_diria e bloco_mostrou no detalhe: não precisa publicar edge function).
--
-- ═══ CÓPIA ═══ agenda_bloco_do_fechamento é a de 20261109100200_agenda_fase7f_bloco.sql (a única migration que a define), que é a de produção em 17/11 (md5 do corpo
--   69b35d93a6031f5b40a94e9b1aec94f9). _agenda_saude_comunicacao é a de 20261109101200_agenda_fase7f_mudou.sql (a mais recente que a define), que é a de produção em 17/11
--   (md5 do corpo 6288e345b16e1692b39dd8032ec304ea; o comentário também). Tirados os blocos "-- PRAZO NO BLOCO:", cada corpo é o dela, byte a byte
--   (supabase/tests/agenda_prazo_no_bloco.sql, P0). Montada por agenda-pesquisa/perguntas-com-prazo-1711/rev3/impl/montar.mjs. Quem recriar de novo copia DESTA.
--
-- ═══ ORDEM DE LIGAR ═══ Sozinha: nada de dado nem de modo muda; vale na próxima tarde depois de aplicada. Não depende de edge function. O dono aceitou (2A) a tarde passar de
--   1.000 e cair no enxuto (o Secretário tira fornecedores, escritório e "Sem resposta desde hoje" antes de cortar a agenda).
--
-- PROVA: supabase/tests/agenda_prazo_no_bloco.sql (begin/rollback; na bancada: node scripts/bancada-agenda/rodar.mjs). As cópias antigas da saúde tiram os blocos do prazo
--   no bloco: agenda_fase7f_final.sql (K9a) e agenda_fase7f_pos_deploy_final.sql (F2).
--
-- APLICAR (só com o OK na hora). Do repo PRINCIPAL (D:/HBR-Storage-Redirects/Documents-Claude-Code/marineflow-erp), que é o linkado — o worktree não tem
--   supabase/.temp/project-ref —, depois do merge deste branch (o arquivo tem de estar naquele checkout):
--   PONTA=<hash de main com o merge> D:/IA-HBR/agenda-pesquisa/publicar/exec/aplicar.sh 20270122100000_agenda_prazo_no_bloco
--   (o script entra no repo principal, confere que a versão não está registrada, aplica com "db query --linked -f supabase/migrations/<arquivo>" e registra a versão
--   com o insert como argumento posicional de "db query --linked"; para na 1ª falha e escreve em publicar/exec/aplicar.log). À mão, o mesmo, do repo principal:
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20270122100000_agenda_prazo_no_bloco.sql
--   npx supabase@2.111.0 db query --linked "insert into supabase_migrations.schema_migrations (version, name) values ('20270122100000', 'agenda_prazo_no_bloco');"
--   (o CLI 2.111.0 não tem -e: o SQL vai como argumento posicional). O roteiro conferido, num commit só e com a fumaça antes e depois:
--   agenda-pesquisa/perguntas-com-prazo-1711/rev2/aplicar/APLICAR.md (aplicar.sql = esta migration entre begin/commit, com o registro da versão dentro).
--
-- DESFAZER: reaplicar a definição, o comentário e os grants de agenda_bloco_do_fechamento de 20261109100200_agenda_fase7f_bloco.sql (a seção "3. O bloco" dela, do
--   create or replace function public.agenda_bloco_do_fechamento ao comment on function) e os de _agenda_saude_comunicacao de 20261109101200_agenda_fase7f_mudou.sql (a
--   seção "5. A saúde da comunicação", do create or replace function ao comment on function; os grants na seção "6. Portas": revoke from public, anon; grant execute to
--   authenticated, service_role), e apagar a versão 20270122100000 de supabase_migrations.schema_migrations.
--
-- IDEMPOTENTE: create or replace function, comment e revoke/grant.

-- ── O bloco ───────────────────────────────────────────────────────────────────────────────
-- A mesma de 20261109100200 (o comentário de lá vale: os níveis, a ordem das partes, a porta), com a linha das perguntas do gestor com prazo como decisão.
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
  -- PRAZO NO BLOCO: (17/11/2026) a linha das perguntas do gestor que esperam o dono e vencem num prazo: a (m) de _agenda_linhas_do_fechamento
  v_ges     jsonb;                 -- a linha (m), ligada, de perda 76 e com pergunta_ids
  v_ges_ids jsonb;                 -- as perguntas que a forma inteira escreve (as pergunta_ids da linha)
  v_ges_cur text;                  -- a forma curta (texto_curto), só quando é menor que a inteira
  v_ges_cid jsonb;                 -- as perguntas que a forma curta escreve: a 1ª e as que não são ficha_estimativa
  v_ges_n   int := 0;              -- as perguntas que a linha cobre e saem da ordem: o veredito as conta, como antes
  v_ges_ord int := 0;              -- as decisões da ordem que ficam, com a do cliente: o "(e mais N em *agenda pendências*)" conta só estas
  v_ges_pos jsonb := '[]'::jsonb;  -- as decisões à vista, na ordem: {d, fixa}; fixa = nunca sai (a 1ª, a do gestor e a do cliente)
  v_ges_r   int := 0;              -- as à vista que podem sair, uma por nível
  v_ges_fix int := 0;              -- as fixas que vêm da ordem (a 1ª, quando não é a do gestor, e a do cliente)
  v_ges_k   int := 0;
  -- PRAZO NO BLOCO: fim
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
    -- PRAZO NO BLOCO: (17/11/2026, 1A) a linha (m) das perguntas do gestor com prazo (perda 76: a ficha_estimativa de hoje, situacao, estimativa e reestimar) não é
    -- mais descartada como as outras linhas pergunta (destino ordem): ela vira uma decisão do bloco, abaixo. As outras linhas pergunta (a (n) da equipe, perda 75 ou 77;
    -- a (m) sem prazo e a pergunta de fato, perda 30) continuam descartadas, como antes.
    if v_ges is null and l ->> 'tipo' = 'pergunta' and l -> 'perda' = '76'::jsonb
       and jsonb_typeof(l -> 'pergunta_ids') = 'array' and jsonb_array_length(l -> 'pergunta_ids') > 0 then
      v_ges := l;
      continue;
    end if;
    -- PRAZO NO BLOCO: fim
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
  -- PRAZO NO BLOCO: (o acordo de antes do bloco: 7a correção, achado 15) com a linha do gestor no bloco, saem da ordem as perguntas que ela leva e TODA aberta ligada
  -- de situacao, estimativa, reestimar e ficha_estimativa com prazo, não só as da linha: pela ordem elas sairiam só com o título, sem o "Sem resposta até …", e o
  -- prazo as decidiria sem o dono ter lido a data. As que saem da ordem e a linha não escreve não entram em nenhum "(e mais N …)" do bloco: o veredito as conta, e
  -- elas ficam em *agenda pendências* (que lista os 4 tipos abertos) e *agenda gestor*; só a forma inteira avisa a sobra da linha ("(e mais N em *agenda gestor*)",
  -- do texto da (m)), a curta não. A forma curta escreve a 1ª pergunta (a ficha, quando há) e as que não são ficha_estimativa: a 2ª ficha em diante não aparece
  -- nela e não conta como mostrada (a rotina das 19:30 a segura, como antes). Falha aqui:
  -- incompleto, e o bloco de antes, sem a linha do gestor.
  if v_ges is not null then
    begin
      v_ges_ids := v_ges -> 'pergunta_ids';
      v_ges_cur := case when char_length(btrim(coalesce(v_ges ->> 'texto_curto', ''))) > 0
                         and char_length(v_ges ->> 'texto_curto') < char_length(v_ges ->> 'texto') then v_ges ->> 'texto_curto' end;
      v_ges_cid := coalesce((select jsonb_agg(u.id order by u.o) from jsonb_array_elements_text(v_ges_ids) with ordinality u(id, o)
                               left join public.agenda_perguntas q on q.id = u.id::uuid
                              where u.o = 1 or q.tipo is distinct from 'ficha_estimativa'), '[]'::jsonb);
      select count(*)::int into v_ges_n
        from (select e ->> 'id' as id from jsonb_array_elements(v_dec) e
               where e ->> 'id' in (select jsonb_array_elements_text(v_ges_ids))
                  or exists (select 1 from public.agenda_perguntas q
                              where q.id = (e ->> 'id')::uuid and q.estado = 'aberta' and q.modo = 'ligado' and q.veto_ate is not null
                                and q.tipo in ('situacao', 'estimativa', 'reestimar', 'ficha_estimativa'))
              union
              select jsonb_array_elements_text(v_ges_ids)) u;
      v_dec := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_dec) with ordinality t(e, o)
                          where not (e ->> 'id' in (select jsonb_array_elements_text(v_ges_ids))
                                     or exists (select 1 from public.agenda_perguntas q
                                                 where q.id = (e ->> 'id')::uuid and q.estado = 'aberta' and q.modo = 'ligado' and q.veto_ate is not null
                                                   and q.tipo in ('situacao', 'estimativa', 'reestimar', 'ficha_estimativa')))), '[]'::jsonb);
    exception when others then
      v_inc := true;
      v_ges := null;
    end;
  end if;
  -- PRAZO NO BLOCO: fim
  if v_cli is not null then
    i := coalesce((select count(*)::int from jsonb_array_elements(v_dec) e join public.agenda_perguntas q on q.id = (e ->> 'id')::uuid
                    where q.critica and q.perda_em <= v_am), 0);
    v_dec := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_dec) with ordinality t(e, o) where o <= i), '[]'::jsonb)
             || jsonb_build_array(jsonb_build_object('id', v_cli ->> 'pergunta_id',
                  'linha', public._agenda_corta(regexp_replace(v_cli ->> 'texto', ': ".*"( \(\*agenda clientes\* mostra inteira\))?\. \*manda', '. *manda'), c_linha_max)))
             || coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_dec) with ordinality t(e, o) where o > i), '[]'::jsonb);
  end if;
  -- PRAZO NO BLOCO: (2A) a linha do gestor entra como decisão logo depois das críticas que perdem até amanhã e antes da mensagem ao cliente: o prazo 1º, o cliente 2º
  if v_ges is not null then
    v_ges_ord := jsonb_array_length(v_dec);
    i := coalesce((select count(*)::int from jsonb_array_elements(v_dec) e join public.agenda_perguntas q on q.id = (e ->> 'id')::uuid
                    where q.critica and q.perda_em <= v_am), 0);
    v_dec := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_dec) with ordinality t(e, o) where o <= i), '[]'::jsonb)
             || jsonb_build_array(jsonb_build_object('id', v_ges ->> 'pergunta_id', 'gestor', true))
             || coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_dec) with ordinality t(e, o) where o > i), '[]'::jsonb);
  end if;
  -- PRAZO NO BLOCO: fim
  v_tot := jsonb_array_length(v_dec);
  v_mos := least(v_tot, cf.bloco_decisoes_max);
  -- PRAZO NO BLOCO: (as vagas e a conta) a linha do gestor ocupa 1 das bloco_decisoes_max vagas, como qualquer decisão: o bloco não cresce. Ela e a do cliente nunca
  -- saem (2A): se a ordem as deixasse fora das vagas (críticas demais antes delas), elas entram assim mesmo, além das vagas. O veredito conta as perguntas que a linha
  -- cobre, como contava quando elas vinham pela ordem; o "(e mais N em *agenda pendências*)" conta só as da ordem (as que a linha não escreve ficam em *agenda
  -- pendências* e *agenda gestor*; só a forma inteira avisa a sobra dela, "(e mais N em *agenda gestor*)").
  if v_ges is not null then
    v_tot := v_ges_ord + v_ges_n;
    select coalesce(jsonb_agg(jsonb_build_object('d', e, 'fixa', o = 1 or (e ? 'gestor') or (e ->> 'id') is not distinct from (v_cli ->> 'pergunta_id')) order by o), '[]'::jsonb)
      into v_ges_pos
      from jsonb_array_elements(v_dec) with ordinality t(e, o)
     where o <= cf.bloco_decisoes_max or (e ? 'gestor') or (e ->> 'id') is not distinct from (v_cli ->> 'pergunta_id');
    v_mos := jsonb_array_length(v_ges_pos);
    v_ges_r := (select count(*)::int from jsonb_array_elements(v_ges_pos) x where not (x ->> 'fixa')::boolean);
    v_ges_fix := (select count(*)::int from jsonb_array_elements(v_ges_pos) x where (x ->> 'fixa')::boolean and not ((x -> 'd') ? 'gestor'));
  end if;
  -- PRAZO NO BLOCO: fim

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
  -- PRAZO NO BLOCO: (os níveis) com a linha do gestor, o último nível é o das que nunca saem: o veredito, a 1ª decisão, a do gestor e a do cliente. Uma a menos por nível
  -- só entre as outras, a partir do 3, como hoje.
  if v_ges is not null then
    v_min := v_ges_r + c_nivel_mudou + 1;
  end if;
  -- PRAZO NO BLOCO: fim
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
  -- PRAZO NO BLOCO: (as linhas de decisão com a do gestor) a dela, no lugar dela na ordem: a forma inteira (o texto da linha, sem o "Agenda: ") até o nível 2 e a curta
  -- (texto_curto) a partir dele — o mesmo entra/corte do Mudou —; sem a curta, a inteira nunca sai. Cada forma leva em pergunta_ids só as perguntas que ela escreve: o
  -- Secretário registra as linhas do nível que saiu, e o registro conta como mostradas só essas. veto_ate nulo: os 4 tipos esperam pelo tipo (veto_espera) e o prazo
  -- deles já está gravado (quem decide é _agenda_gestor_vetos, com a pergunta mostrada antes do prazo). As outras, como hoje: as fixas nunca saem e, das que sobram, a
  -- última sai primeiro, uma por nível a partir do 3, com "(e mais N em *agenda pendências*)".
  if v_ges is not null then
    for i in 1 .. v_mos loop
      d := v_ges_pos -> (i - 1) -> 'd';
      if d ? 'gestor' then
        v_ls := v_ls || (public._agenda_bloco_linha('decisao', '· ' || regexp_replace(v_ges ->> 'texto', '^Agenda: ', ''), 0,
                                                     case when v_ges_cur is not null then c_nivel_mudou end, (v_ges ->> 'pergunta_id')::uuid)
                         || jsonb_build_object('pergunta_ids', v_ges_ids));
        if v_ges_cur is not null then
          v_ls := v_ls || (public._agenda_bloco_linha('decisao', '· ' || regexp_replace(v_ges_cur, '^Agenda: ', ''), c_nivel_mudou, null, (v_ges ->> 'pergunta_id')::uuid)
                           || jsonb_build_object('pergunta_ids', v_ges_cid));
        end if;
        continue;
      end if;
      if not (v_ges_pos -> (i - 1) ->> 'fixa')::boolean then
        v_ges_k := v_ges_k + 1;
      end if;
      v_ls := v_ls || (public._agenda_bloco_linha('decisao', '· ' || (d ->> 'linha'), 0,
                                                   case when (v_ges_pos -> (i - 1) ->> 'fixa')::boolean then null else v_ges_r - v_ges_k + c_nivel_mudou + 1 end,
                                                   (d ->> 'id')::uuid)
                       || jsonb_build_object('veto_ate', d -> 'veto_ate')
                       || case when d ? 'veto_diria' then jsonb_build_object('veto_diria', d -> 'veto_diria') else '{}'::jsonb end);
    end loop;
    -- "(e mais N)": uma linha por nível, de todas as que podem sair à vista a nenhuma. N = as da ordem fora da vista naquele nível.
    for i in reverse v_ges_r .. 0 loop
      continue when v_ges_ord - v_ges_fix - i = 0;
      v_ls := v_ls || public._agenda_bloco_linha('decisao', format('(e mais %s em *agenda pendências*)', v_ges_ord - v_ges_fix - i),
                                                  case when i = v_ges_r then 0 else v_ges_r - i + c_nivel_mudou end, v_ges_r - i + c_nivel_mudou + 1);
    end loop;
  else
  -- PRAZO NO BLOCO: fim
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
  -- PRAZO NO BLOCO: (fecha o "se" da linha do gestor: sem ela, as 2 voltas acima, as de hoje, byte a byte)
  end if;
  -- PRAZO NO BLOCO: fim
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
  'Agenda de Produção (Fase 7f, P3; §5.3, §6.1, R8.4, R8.5-15, R8.7, R8.8): o bloco da agenda na tarde, a partir das linhas que agenda_textos_do_fechamento já leu (p_linhas): {modo, linhas: [{parte (veredito, hoje, mudou, semana, decisao, compras, outras), texto, pergunta_id, pergunta_ids, acao_ids, veto_ate, veto_diria, nivel_entra, nivel_de_corte (nulo = nunca sai)}], nivel (o menor em que cabe em bloco_max_chars), nivel_min (só o veredito e a 1ª decisão), chars, nada_mudou, incompleto, sem_destino}. As linhas do nível n são as de nivel_entra <= n < nivel_de_corte. Desligado: {modo}. Administrador, financeiro ou service_role; senão 42501. PRAZO NO BLOCO (17/11/2026, 20270122100000; plano perguntas-com-prazo-1711, F1, respostas do dono 1A e 2A): a linha (m) de _agenda_linhas_do_fechamento (tipo pergunta, ligada, perda 76, com pergunta_ids: a ficha_estimativa de hoje, situacao, estimativa e reestimar com prazo), antes descartada pelo destino ordem, vira decisão: logo depois das críticas que perdem até amanhã e antes da mensagem ao cliente, as duas nunca cortadas (nivel_de_corte nulo); ocupa 1 das bloco_decisoes_max vagas e só passa delas quando a ordem a deixaria de fora. Forma inteira (sem o "Agenda: ") até o nível 2, a curta (texto_curto) a partir dele; cada forma leva em pergunta_ids só as perguntas que escreve (a curta: a 1ª e as que não são ficha_estimativa). Com ela, saem da ordem as dela e toda aberta ligada de situacao, estimativa, reestimar e ficha_estimativa com veto_ate. veto_ate da linha nulo. O veredito conta as perguntas que ela cobre; "(e mais N em *agenda pendências*)" só as da ordem; nivel_min = o veredito e as que nunca saem. Sem a linha, a saída de antes, byte a byte.';

revoke all on function public.agenda_bloco_do_fechamento(date, timestamptz, jsonb) from public, anon;
grant execute on function public.agenda_bloco_do_fechamento(date, timestamptz, jsonb) to authenticated, service_role;

-- ── A saúde da comunicação ───────────────────────────────────────────────────────────────
-- A mesma de 20261109101200 (o comentário de lá vale), com o bloco_grande que não conta o bloco no mínimo dele com a linha do gestor.
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
    -- PRAZO NO BLOCO: (17/11/2026, 20270122100000; revisão da F1) o mínimo do bloco com a linha das perguntas do gestor. Com ela no bloco, as que nunca saem são a 1ª
    -- decisão, a do gestor e a do cliente (2A): no mínimo ele pode ter 3 decisões, e acima de texto_max já não tem o que ceder — isso não é bloco grande. A conta de cima
    -- vale, com a tolerância "as fixas + 1": no nivel_min só ficam as que nunca saem — o "(e mais N)" sai nele (o corte dele é o nivel_min; o "com o e mais N" do
    -- comentário de cima não vale para o mínimo) — e o +1 é o nível logo acima, que ainda tem o "(e mais N)". Antes, 1 fixa: 2. Com a do gestor no fechamento, +1
    -- quando a 1ª é uma crítica (sempre numerada, "Decisão N:"; sem crítica, a 1ª é a do gestor) e +1 com a do cliente à vista. (revisão 3) As marcas presas às linhas
    -- certas, com os espaços juntados como o Secretário os junta (blocoDaAgenda e linhasDaAgenda, secretario-tarde-coleta.ts):
    --   a do gestor: a (m) ligada de perda 76 está em linhas_diria e uma decisão à vista é a forma inteira dela ('· ' e o texto sem o "Agenda: ", igual) ou a curta.
    --   linhas_diria não grava a curta; _agenda_linhas_do_fechamento a monta das mesmas perguntas: com a ficha em 1º, ela começa pelo trecho do texto da ficha antes de
    --   " 1) Mande" (o mesmo começo da inteira) e " Para segurar, me diga."; sem a ficha, a 1ª tem prazo (perda 76: a ordem é ficha, prazo, sem prazo) e a curta começa
    --   por "Sem resposta até <dia hora>, conto: ". Nenhuma linha da ordem nem a do cliente começa assim (as 4 da ordem saem numeradas);
    --   a do cliente (v_cli, fixa): a linha cliente ligada de linhas_diria, escrita como o bloco a escreve ('· ' e _agenda_corta do texto sem a mensagem, 220), é igual
    --   a uma decisão à vista — uma cliente_aprovar da ordem ("Mensagem para …", que pode sair) não casa.
    -- Sem a do gestor à vista, a tolerância é a de antes (2) e a conta sai a mesma, também nos fechamentos de antes de aplicar (a janela de 7 dias ainda os lê).
    execute $q$
      select count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3
                                and ((select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' not in ('veredito', 'decisao')) > 0
                                     or (select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' = 'decisao')
                                        > 2 + case when exists (select 1
                                                                  from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l,
                                                                       jsonb_array_elements(case when jsonb_typeof(t.detalhe #> '{agenda,linhas_diria}') = 'array'
                                                                                                 then t.detalhe #> '{agenda,linhas_diria}' else '[]'::jsonb end) x,
                                                                       lateral (select btrim(regexp_replace(l ->> 'texto', '\s+', ' ', 'g')) as v,
                                                                                       '· ' || regexp_replace(btrim(regexp_replace(x ->> 'texto', '\s+', ' ', 'g')), '^Agenda: ', '') as i) z
                                                                 where l ->> 'parte' = 'decisao' and x ->> 'tipo' = 'pergunta' and x ->> 'perda' = '76' and x ->> 'modo' = 'ligado'
                                                                   and (z.v = z.i
                                                                        or starts_with(z.v, split_part(z.i, ' 1) Mande', 1) || ' Para segurar, me diga.')
                                                                        or z.v ~ '^· Sem resposta até [^,]+, conto: '))
                                                    then coalesce((select case when l ->> 'texto' ~ '^· Decisão [0-9]+: ' then 1 else 0 end
                                                                     from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') with ordinality u(l, o)
                                                                    where l ->> 'parte' = 'decisao' order by o limit 1), 0)
                                                         + case when exists (select 1
                                                                               from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l,
                                                                                    jsonb_array_elements(case when jsonb_typeof(t.detalhe #> '{agenda,linhas_diria}') = 'array'
                                                                                                              then t.detalhe #> '{agenda,linhas_diria}' else '[]'::jsonb end) x
                                                                              where l ->> 'parte' = 'decisao' and x ->> 'tipo' = 'cliente' and x ->> 'modo' = 'ligado'
                                                                                and btrim(regexp_replace(l ->> 'texto', '\s+', ' ', 'g'))
                                                                                    = btrim(regexp_replace('· ' || public._agenda_corta(regexp_replace(x ->> 'texto',
                                                                                        ': ".*"( \(\*agenda clientes\* mostra inteira\))?\. \*manda', '. *manda'), 220), '\s+', ' ', 'g')))
                                                                then 1 else 0 end
                                                    else 0 end))::int
        from public.resumo_tarde t
       where t.dia between $1 and $2 and t.detalhe -> 'agenda' ? 'bloco_diria'
    $q$ into v_bgrande using p_hoje - c_semana + 1, p_hoje, cf.texto_max;
    -- PRAZO NO BLOCO: fim
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
  -- FASE 7f: (7f P9, §11 aceites 6 e 7; NOVO-agenda-131 e 138) os zeros da equipe e do cliente, que entram no zeros_ok (e por ele no ok de agenda_saude). Só o que
  -- a 7f manda de verdade (ligado): em teste nada conta. Hoje 0 em produção (sql/wf7f9_zeros, dom 08/11). A equipe: o previsto, a mudança e o convite fora da janela
  -- ou no domingo; o dia com mais que equipe_proativas_dia_max mensagens de quem recebeu alguma da 7f; a ficha do dia com convite sem o SIM antes dela (AG7-23); mais
  -- de uma mudança das 19:30 por pessoa e dia. O cliente: o dia exato (o M1 e o M3 marcados pela estimativa) antes de cliente_dia_exato_du dias úteis do dia, ao
  -- cliente que ouviu a semana daquele dia; a semana que mudou enviada sem o *manda cliente*; a semana como dia ouvido (firme)
  v_z := v_z || jsonb_build_object(
    'equipe_fora_da_janela', (select count(*) from public.agenda_equipe_mensagens e
                               where e.tipo in ('previsto', 'mudanca', 'convite') and e.modo = 'ligado' and e.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                 and (extract(isodow from e.enviar_em at time zone 'America/Sao_Paulo') = 7
                                      or (e.enviar_em at time zone 'America/Sao_Paulo')::time < cf.equipe_janela_inicio
                                      or (e.enviar_em at time zone 'America/Sao_Paulo')::time > cf.equipe_janela_fim)),
    'equipe_acima_do_teto', (select count(*) from (select e.payee_id from public.agenda_equipe_mensagens e
                                                    where e.modo = 'ligado' and e.tipo <> 'resposta' and e.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                                    group by e.payee_id, (e.enviar_em at time zone 'America/Sao_Paulo')::date
                                                   having count(*) > cf.equipe_proativas_dia_max and bool_or(e.tipo in ('previsto', 'mudanca', 'convite'))) g),
    'ficha_sem_sim', (select count(*) from public.agenda_equipe_mensagens f
                       where f.tipo = 'ficha' and f.modo = 'ligado' and f.estado in ('enfileirada', 'respondida', 'sem_resposta')
                         and exists (select 1 from public.agenda_equipe_mensagens c
                                      where c.tipo = 'convite' and c.modo = 'ligado' and c.payee_id = f.payee_id and c.dia = f.dia and c.estado <> 'recusada'
                                        and c.criada_em <= f.enviar_em
                                        and not coalesce(c.leitura ->> 'convite' = 'sim' and c.resposta_em <= f.enviar_em, false))),
    'mudanca_19h_repetida', (select count(*) from (select 1 from public.agenda_equipe_mensagens e
                                                    where e.tipo = 'mudanca' and e.modo = 'ligado' and e.dedupe_key like '%:19h' and e.estado <> 'recusada'
                                                    group by e.payee_id, (e.enviar_em at time zone 'America/Sao_Paulo')::date having count(*) > 1) g),
    'dia_exato_cedo', (select count(*) from public.agenda_cliente_mensagens m
                        where m.tipo in ('confirmar', 'material_chegou') and m.modo = 'ligado' and m.enviada_em is not null and m.dia_alvo is not null
                          and coalesce((m.base #>> '{dados,por_estimativa}')::boolean, false)
                          and exists (select 1 from public.agenda_cliente_mensagens s
                                       where s.service_order_id = m.service_order_id and s.tipo = 'semana' and s.modo = 'ligado' and s.enviada_em is not null
                                         and s.enviada_em < m.enviada_em and m.dia_alvo between s.faixa_de and s.faixa_ate)
                          and (m.enviada_em at time zone 'America/Sao_Paulo')::date < public.agenda_somar_du(m.dia_alvo, - cf.cliente_dia_exato_du)),
    'promessa_mudou_sem_dono', (select count(*) from public.agenda_cliente_mensagens m
                                 where m.tipo = 'semana' and m.variante = 'mudou' and m.enviada_em is not null and m.aprovacao is distinct from 'aprovada'),
    'semana_como_dia_ouvido', (select count(*) from public.agenda_cliente_mensagens m where m.tipo = 'semana' and m.prometido_tipo = 'firme')
                              + (select count(*) from public.os_planejamento p join public.agenda_cliente_mensagens m on m.id = p.prometido_mensagem_id
                                  where m.tipo = 'semana' and p.prometido_tipo = 'firme'));
  -- FASE 7f: fim

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

  -- FASE 7f: (7f P9, §11 "Métricas": equipe e cliente, por semana) os números, como os de antes, só com o modo deles fora de desligado. Em teste conta o que foi
  -- registrado (em_teste); de verdade, o que saiu e o que voltou. Só contagens
  if cf.modo_equipe_previsto <> 'desligado' or cf.modo_equipe_convite <> 'desligado' then
    v_n := v_n || jsonb_build_object('equipe', (
      select jsonb_build_object(
               'previstos', count(*) filter (where e.tipo = 'previsto' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'mudancas', count(*) filter (where e.tipo = 'mudanca' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'mudancas_19h', count(*) filter (where e.tipo = 'mudanca' and e.modo = 'ligado' and e.estado <> 'recusada' and e.dedupe_key like '%:19h'),
               'convites', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'convites_sim', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.leitura ->> 'convite' = 'sim'),
               'convites_nao', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.leitura ->> 'convite' = 'nao'),
               'convites_sem_resposta', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.estado = 'sem_resposta'),
               'recusadas', count(*) filter (where e.modo = 'ligado' and e.estado = 'recusada'),
               'em_teste', count(*) filter (where e.modo = 'sombra'),
               'nao_depois_de_mudanca', (select count(*) from public.agenda_disponibilidade d
                                          where d.origem = 'diarista' and d.situacao = 'indisponivel' and d.substituida_em is null
                                            and d.criado_em > p_agora - make_interval(days => c_semana)
                                            and exists (select 1 from public.agenda_equipe_mensagens x
                                                         where x.payee_id = d.payee_id and x.tipo in ('mudanca', 'convite') and x.modo = 'ligado'
                                                           and x.estado <> 'recusada' and x.criada_em < d.criado_em
                                                           and (d.periodo @> x.dia or exists (select 1 from unnest(coalesce(x.dias, '{}'::date[])) u(dia) where d.periodo @> u.dia)))))
        from public.agenda_equipe_mensagens e
       where e.tipo in ('previsto', 'mudanca', 'convite') and e.criada_em > p_agora - make_interval(days => c_semana)));
  end if;
  if cf.modo_cliente_camadas <> 'desligado' then
    v_n := v_n || jsonb_build_object('cliente', (
      select jsonb_build_object(
               'semanas', jsonb_build_object(
                 'registradas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'ligado'),
                 'enviadas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'ligado' and m.enviada_em is not null),
                 'seguradas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.aprovacao = 'segurada'),
                 'vencidas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.aprovacao = 'vencida'),
                 'em_teste', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'sombra')),
               'semana_mudou', jsonb_build_object(
                 'registradas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.modo = 'ligado'),
                 'mandadas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'aprovada'),
                 'seguradas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'segurada'),
                 'vencidas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'vencida'),
                 'enviadas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.enviada_em is not null),
                 'em_teste', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.modo = 'sombra')),
               'mudancas_ao_cliente', count(*) filter (where m.modo = 'ligado' and m.enviada_em is not null
                                                         and (m.tipo in ('pode_atrasar', 'nova_data', 'mudanca_no_dia') or (m.tipo = 'semana' and m.variante = 'mudou'))))
        from public.agenda_cliente_mensagens m
       where m.criada_em > p_agora - make_interval(days => c_semana)));
  end if;
  -- FASE 7f: fim
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
  'Agenda de Produção (Fase 7f, P7; §11, R8.5-27, R8.5-29, R8.6): a saúde da comunicação — {modos (os 6, crus), freio, ultima_rodada e rodadas_24h (rotina comunicar), erros_24h (comunicar:%), falhas_lote_guardaria_24h, zeros_ok, numeros} e os zeros: assumida_sem_prazo_mostrado, assumida_que_esperava, assumida_tipo_proibido, teto_passou_sem_motivo, bloco_grande, excecao_acima_do_teto. numeros só com algum modo fora de desligado: perguntas (abertas, teto, com prazo, esperam você, respondidas, assumidas por prazo e por teto, teria, idade média em dias úteis, complacência de 2 semanas), excecoes (hoje, cota livre, os ids distintos acima da cota; em sombra o que o lote levaria e guardaria), quinta (a que saiu; em sombra a que diria), bloco (resumo_tarde de 7 dias), mensagens_hoje por origem (aviso = agenda-dono, acorde = agenda; só contagens). A porta de _agenda_saude_local: administrador, financeiro ou service_role; o resto 42501. FASE 7f (P9): os zeros da equipe (equipe_fora_da_janela, equipe_acima_do_teto, ficha_sem_sim, mudanca_19h_repetida; aceite 6) e do cliente (dia_exato_cedo, promessa_mudou_sem_dono, semana_como_dia_ouvido; aceite 7), só do que a 7f manda de verdade, no zeros_ok; numeros.equipe (com o previsto ou o convite fora de desligado: previstos, mudanças, convites com SIM, NÃO e sem resposta, recusadas, em teste, "não vou" depois de mudança ou convite, na semana) e numeros.cliente (com as camadas fora de desligado: as semanas registradas, enviadas, seguradas, vencidas e em teste, a semana que mudou mandada, segurada, vencida e enviada, e as mudanças que chegaram ao cliente, na semana). PRAZO NO BLOCO (17/11/2026, 20270122100000; plano perguntas-com-prazo-1711, F1, revisão): bloco_grande não conta o fechamento que está no mínimo do bloco com a linha das perguntas do gestor: no mínimo ficam a 1ª decisão, a do gestor e a do cliente. A tolerância é as fixas + 1 (no nivel_min só ficam as decisões que nunca saem, sem o "(e mais N)"; o +1 é o nível logo acima, com ele): a de antes, 2 (a 1ª e mais 1), ganha +1 com a 1ª numerada (uma crítica antes da do gestor) e +1 com a do cliente à vista. A do gestor está no fechamento quando a (m) ligada de perda 76 está em detalhe.agenda.linhas_diria e uma decisão à vista é a forma inteira dela (o texto sem o "Agenda: ", com os espaços juntados) ou a curta (que começa pelo trecho da ficha antes de " 1) Mande" e " Para segurar, me diga.", ou por "Sem resposta até …, conto: "); a do cliente, quando a linha cliente ligada de linhas_diria, escrita como o bloco a escreve (_agenda_corta, 220), é igual a uma decisão à vista (uma cliente_aprovar da ordem não conta). Sem a do gestor à vista, a conta de antes.';

revoke all on function public._agenda_saude_comunicacao(date, timestamptz) from public, anon;
grant execute on function public._agenda_saude_comunicacao(date, timestamptz) to authenticated, service_role;
