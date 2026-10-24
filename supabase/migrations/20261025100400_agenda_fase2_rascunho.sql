-- Agenda de Produção, Fase 2 ("O gestor de agenda"), pacote P4: o rascunho dos pedidos do dono — marcar, publicar ou
-- decidir, desfazer e contar o andamento da OS — e a ferramenta que simula a agenda.
-- Spec: scratchpad agenda-pesquisa/spec-fase2.md (§8; §3.1 princípio 1b, §3.3 d3, d26). Decisões 23/10 (Autonomia).
-- Depende da Fase 1 inteira (160600: o rascunho e o *grava*) e de 20261025100000..100300 (tabelas, porta, motor,
-- conferência).
--
-- ═══ DDL — OK NOMEADO ═══ (um CHECK ampliado e funções; nenhuma tabela nova, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: a Fase 1 deu ao dono um caminho de escrita pela conversa — a ferramenta deixa um RASCUNHO com a releitura
-- pronta do banco, e só o *grava* dele (comando sem IA, que o modelo não alcança) transforma em fato. Na Fase 2 o dono
-- também pede à agenda ("marca o Lenine pra quinta", "pode publicar", "pode atrasar o Vanderlei", "desfaz o Nelson",
-- "hoje o João não foi"). Nada disso pode ser executado pelo modelo: entra no mesmo rascunho, com a releitura do efeito
-- calculado agora pelo banco, e o *grava* executa pelas funções do motor (as mesmas da vigia, da tela e das palavras).
--
-- O QUE MUDA:
--   1. agenda_rascunho.tipo ganha marcar, aplicar, desfazer e andamento (o CHECK por nome é refeito).
--   2. agenda_rascunho_marcar(autor, canal, os, quando, ate, pessoa, trecho, p_hoje, p_agora): resolve a OS, as datas
--      (agenda_data_dita, ditas no trecho) e a pessoa; simula agenda_propor('os', fixar) sem gravar. Cabe → rascunho
--      marcar:<os> com a releitura ("Marco na agenda: Lenine (OS-00074), qui 29 e sex 30/10, você abre e fecha, Roberto
--      os 2 dias."). Não cabe → a pergunta ("… O primeiro dia que dá é sex 30/10. Marco nesse dia?"), nada no rascunho.
--   3. agenda_rascunho_aplicar(autor, canal, proposta, os[], decisao, opcao, trecho, …): publicar uma proposta aberta
--      ("a última" ou o nº de agenda_propostas_abertas; só as OS ditas) OU responder uma decisão crítica (o nº de
--      agenda_decisoes_abertas ou o nome da OS; a opção pelo nº ou pelo nome da OS que aceita atrasar). Sem opção dita:
--      devolve a pergunta com as opções — o banco nunca escolhe pelo dono. Chave aplicar:<proposta> / decisao:<pergunta>.
--   4. agenda_rascunho_desfazer(autor, canal, alvo, trecho, …): agenda_acao_desfazivel; ambíguo = a pergunta pronta.
--   5. agenda_rascunho_andamento(autor, canal, os, evento, dia, quem[], motivo, trecho, …): trabalhou · parcial · nao_foi
--      (o resultado do meio-dia no plano) · comecou (em andamento, com o início na manhã do dia dito) · parou (com
--      material → aguardando peças; cliente → aguardando o cliente; sai da agenda o que ainda não começou). "Concluiu" e
--      "entregou" são recusados: concluir é pela tela.
--   6. agenda_propor_dito(autor, canal, escopo, os[], fixar, tirar[], so_depois_de, acima_da_carga, simular, …): a
--      entrada da ferramenta agenda_propor (P6). Resolve as referências e chama agenda_propor; simular (padrão) não grava
--      nada; simular = false grava só a proposta ABERTA (nunca publica: publicar é o *grava* de agenda_rascunho_aplicar).
--   7. agenda_rascunho_planejar, _agenda_aplicar_planejar e _agenda_rascunho_frase recriadas com o corpo de 160600
--      (mudança marcada "-- FASE 2:"): o campo adiantavel_patio (dias, com a guarda do número no trecho; limpar 'patio')
--      → os_planejamento.adiantavel_patio_dias; a frase "dá para adiantar 1 dia no pátio". A frase dos 4 tipos novos vem
--      pronta do banco (dados.frase_pronta).
--   8. agenda_rascunho_gravar recriada (mesma assinatura): numa transação, tudo ou nada — primeiro os fatos da Fase 1,
--      depois andamento (agenda_registrar_dia; a porta), marcar (agenda_marcar_os, conferido contra a releitura),
--      aplicar/decidir (agenda_aplicar / agenda_decidir, com respondida_via = o canal) e desfazer (agenda_desfazer).
--      Qualquer recusa desfaz o lote inteiro: "Não gravei nada. A agenda mudou desde a releitura: <motivo>. Me peça de
--      novo." Com modo_proposta fora de 'ligado', o lote com um dos 4 tipos novos não grava.
--   9. agenda_decisoes_abertas(p_agora) e agenda_propostas_abertas(p_agora): a numeração que o dono usa ("a 1", "a
--      última"). agenda_ver (P5, focos decisoes e plano) tem de numerar por estas mesmas funções.
--   Auxiliar: _agenda_aplicar_pedido (o que o *grava* faz com cada linha dos tipos novos; só service_role).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase2_rascunho.sql):
--   · A chave do andamento é andamento:<os>:<dia>:<quem> (e :status para começou/parou), não andamento:<os>:<dia>: com a
--     chave da spec, "o Roberto trabalhou" e depois "o João não foi" (duas chamadas, uma por fato, como o prompt manda)
--     seriam a mesma linha e a segunda apagaria a primeira. A releitura junta as duas numa linha só (o grupo é o da OS e
--     do dia): "Hoje (ter 03/11), Vanderlei (OS-00069): Roberto trabalhou o dia todo; João não foi (equipe)."
--   · agenda_rascunho_gravar mantém a assinatura (p_autor, p_hoje): o comando *grava* (P6) e os testes e o pós-deploy da
--     Fase 1 dependem dela, e um 3º parâmetro criaria duas versões que o PostgREST não sabe escolher. A hora do *grava* é
--     now(); a bancada a fixa com set_config('agenda.agora', …, true), como já fixa agenda.hoje (ninguém liga essa chave
--     pela API: set_config está em pg_catalog, fora do que o PostgREST expõe). A validade do rascunho continua por now(),
--     como na Fase 1.
--   · marcar confere, no *grava*, que a agenda pôs a OS nos mesmos dias da releitura (o dono confirmou aqueles dias); se
--     o motor achar outro encaixe dentro do pedido, o lote não grava e o texto diz o que mudou.
--   · "parou" só com material ou cliente (é o que vira aguardando peças / aguardando o cliente pela porta); com outro
--     motivo a pergunta pede um dos dois. Sai da agenda o que ainda não começou (ação cancelar, sem desfazer: foi o dono
--     que disse) e a OS não é reencaixada na hora: volta quando a espera acaba (vigia, passo do material, ou o dono).
--   · Os textos não põem artigo antes do nome do cliente nem da pessoa (o banco não sabe se é "o" ou "a"), como o P3.
--   · A numeração das propostas e das decisões nasce aqui (agenda_propostas_abertas, agenda_decisoes_abertas), porque o
--     rascunho precisa resolver "a 1" antes de existir o agenda_ver da Fase 2 (P5).
--   · agenda_propor_dito aceita os escopos da ferramenta (semana e proxima_semana → a semana que o motor publica, a
--     seguinte à de hoje; os; replano). Revisão da Fase 2: com fixar ou só depois de, confere cada dia nas palavras do
--     dono (p_trecho, no fim da assinatura; sem ele, "Me diga com as suas palavras…") — a proposta aberta (simular =
--     false) segue para o *grava* de agenda_rascunho_aplicar, e o dia dela não pode ser um que o modelo calculou.
--   · O dia pedido antes de o material estar garantido (revisão da Fase 2, o caso da OS-00104): marcar não recusa (é a
--     decisão do dono), mas a releitura traz o aviso do material e "Marco mesmo assim?"; o *grava* é o sim.
--
-- O QUE NÃO MUDA: nenhuma tabela além do CHECK; o motor, a porta e a conferência (P1–P3); o rascunho da Fase 1 (os
-- tipos planejar, material e disponibilidade gravam exatamente como antes — agenda_fase1_rascunho.sql continua passando).
--
-- ORDEM DE LIGAR: depois de 20261025100300; vai para produção junto com o ai-agent/erp-mcp do P4 (schedule_service_order
-- em ligado chama agenda_rascunho_marcar) e do P6 (as ferramentas agenda_aplicar, agenda_desfazer,
-- os_registrar_andamento e agenda_propor).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase2_rascunho.sql (begin/rollback; nada muda antes do *grava*; o
-- *grava* aplica; correção substitui; expirado não grava; lote com um item recusado não grava nada; a decisão crítica
-- pelo *grava* sai critica = true com pergunta_id e respondida_via; concluir recusado; técnico 42501; a paridade de
-- statusAoAgendar com a porta). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261025100400
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261025100400_agenda_fase2_rascunho.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261025100400', 'agenda_fase2_rascunho');"
--
-- IDEMPOTENTE: drop constraint if exists + add constraint, create or replace function, revoke/grant e comment.

-- ── 0. Os tipos novos do rascunho ───────────────────────────────────────────────────────────────────────

alter table public.agenda_rascunho drop constraint if exists agenda_rascunho_tipo_check;
alter table public.agenda_rascunho add constraint agenda_rascunho_tipo_check
  check (tipo in ('planejar', 'material', 'disponibilidade', 'marcar', 'aplicar', 'desfazer', 'andamento'));

comment on table public.agenda_rascunho is
  'Agenda de Produção: o que o dono disse na conversa e ainda não mandou gravar. Uma linha aberta por chave (planejar:<os>, material:<linha>, disp:<pessoa>:<quando>:<turno>; Fase 2: marcar:<os>, aplicar:<proposta>, decisao:<pergunta>, desfazer:<acao>, andamento:<os>:<dia>:<quem>); a correção substitui. Só o *grava* do dono (agenda_rascunho_gravar) transforma em fato.';

-- ── 1. A numeração que o dono usa ───────────────────────────────────────────────────────────────────────

-- As decisões críticas esperando o dono, numeradas: a que perde primeiro vem antes. agenda_ver (foco decisoes) numera
-- por aqui, para "a 1" ser a mesma nas duas.
create or replace function public.agenda_decisoes_abertas(p_agora timestamptz default now())
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'n', x.n, 'id', x.id, 'tipo', x.tipo, 'os', x.service_order_id, 'os_ids', to_jsonb(x.os_ids), 'texto', x.texto,
           'opcoes', x.opcoes, 'recomendacao', x.recomendacao, 'recomendacao_texto', x.recomendacao_texto,
           'perda_em', x.perda_em, 'versao_base', x.versao_base) order by x.n), '[]'::jsonb)
    from (select q.*, row_number() over (order by q.perda_em nulls last, q.criada_em, q.id) as n
            from public.agenda_perguntas q
           where q.critica and q.estado = 'aberta' and q.modo = 'ligado'
             and (q.expira_em is null or q.expira_em > p_agora)) x;
$function$;

comment on function public.agenda_decisoes_abertas(timestamptz) is
  'Agenda de Produção (Fase 2, P4): as decisões críticas abertas (modo ligado) numeradas — n = 1 é a que perde primeiro (perda_em, depois a mais antiga). [{n, id, tipo, os, os_ids, texto, opcoes, recomendacao, recomendacao_texto, perda_em, versao_base}]. O rascunho resolve "a 1" por aqui; agenda_ver (foco decisoes) numera igual.';

-- As propostas abertas (modo ligado, dentro da validade) que o dono pode mandar publicar, numeradas: n = 1 é a última.
create or replace function public.agenda_propostas_abertas(p_agora timestamptz default now())
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'n', x.n, 'id', x.id, 'escopo', x.escopo, 'titulo', x.textos ->> 'titulo', 'criada_em', x.criada_em,
           'expira_em', x.expira_em, 'versao_base', x.versao_base,
           'os', (select coalesce(jsonb_agg(distinct i ->> 'os'), '[]'::jsonb) from jsonb_array_elements(x.itens) i))
           order by x.n), '[]'::jsonb)
    from (select p.*, row_number() over (order by p.criada_em desc, p.id) as n
            from public.agenda_propostas p
           where p.estado = 'aberta' and p.modo = 'ligado' and p.expira_em > p_agora) x;
$function$;

comment on function public.agenda_propostas_abertas(timestamptz) is
  'Agenda de Produção (Fase 2, P4): as propostas abertas (modo ligado, não vencidas) numeradas — n = 1 é a mais recente ("a última"). [{n, id, escopo, titulo, criada_em, expira_em, versao_base, os}]. O rascunho resolve "publica a 2" por aqui; agenda_ver (foco plano) numera igual.';

-- ── 2. A frase de cada linha do rascunho ────────────────────────────────────────────────────────────────
-- Corpo de 20261024160600 copiado; as mudanças estão marcadas "-- FASE 2:".

create or replace function public._agenda_rascunho_frase(p_tipo text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_t      text;
  v_forn   text := nullif(p_d ->> 'fornecedor_txt', '');
  v_hoje   date := (p_d ->> 'hoje')::date;
  v_quando text;
begin
  if p_tipo = 'planejar' then
    if nullif(p_d ->> 'escopo_decidido', '') is not null then
      v_partes := v_partes || (p_d ->> 'escopo_decidido');
    end if;
    v_t := null;
    if p_d ->> 'dias' is not null then
      v_t := public._agenda_dias((p_d ->> 'dias')::numeric)
             || case when p_d ->> 'estimativa_fonte' = 'aceita' then ' (a minha estimativa, que você aceitou)' else '' end;
    end if;
    if jsonb_array_length(coalesce(p_d -> 'equipe', '[]'::jsonb)) > 0 then
      v_t := concat_ws(' ', v_t, 'com ' || public._agenda_lista(array(
               select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                      || case e ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                 from jsonb_array_elements(p_d -> 'equipe') with ordinality t(e, o) order by o), null));
    elsif p_d ? 'equipe' and p_d ->> 'dias' is null then
      v_t := 'sem ninguém marcado para ir';
    end if;
    if v_t is not null then
      v_partes := v_partes || v_t;
    end if;
    if p_d ->> 'dono' is not null then
      v_partes := v_partes || case p_d ->> 'dono' when 'abre_e_fecha' then 'você abre e fecha'
                                                 when 'sempre' then 'você fica o tempo todo' else 'você não vai' end;
    end if;
    if p_d ->> 'precisa_ate' is not null then
      v_partes := v_partes || ('o cliente precisa até ' || public._dia_curto((p_d ->> 'precisa_ate')::date));
    elsif p_d ? 'precisa_ate' then
      v_partes := v_partes || 'o cliente não tem mais prazo'::text;
    end if;
    if p_d ? 'bem' then
      v_partes := v_partes || case p_d #>> '{bem,modo}'
        when 'livre' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' já está livre'
        when 'fora' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica fora '
                         || public._agenda_quando_texto((p_d #>> '{bem,de}')::date, (p_d #>> '{bem,ate}')::date)
        else coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica livre ' || public._dia_curto((p_d #>> '{bem,livre_em}')::date) end;
    end if;
    if p_d ->> 'nao_antes_de' is not null then
      v_partes := v_partes || ('não antes de ' || public._dia_curto((p_d ->> 'nao_antes_de')::date)
                               || case when coalesce(p_d ->> 'nao_antes_motivo', 'você disse') = 'você disse' then ''
                                       else ' (' || (p_d ->> 'nao_antes_motivo') || ')' end);
    elsif p_d ? 'nao_antes_de' then
      v_partes := v_partes || 'pode começar sem esperar data'::text;
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    elsif p_d ? 'escopo_em_aberto' and nullif(p_d ->> 'escopo_decidido', '') is null then
      v_partes := v_partes || 'nada mais a decidir no escopo'::text;
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    elsif p_d ? 'congelada_ate' then
      v_partes := v_partes || 'sai da espera'::text;
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
    end if;
    -- FASE 2: quanto dá para adiantar no pátio sem o bem (bancada: barramento, chicote).
    if p_d ? 'adiantavel_patio' then
      v_partes := v_partes || case when p_d ->> 'adiantavel_patio' is null then 'nada a adiantar no pátio'
                                   else 'dá para adiantar ' || public._agenda_dias((p_d ->> 'adiantavel_patio')::numeric) || ' no pátio' end;
    end if;
    return array_to_string(v_partes, '; ');
  end if;

  if p_tipo = 'material' then
    v_t := case p_d ->> 'acao'
      when 'na_mao' then
        case when p_d ->> 'quantidade_na_mao' is not null
             then format('%s de %s na mão', public._os_material_qtd((p_d ->> 'quantidade_na_mao')::numeric),
                         public._os_material_qtd((p_d ->> 'quantidade_necessaria')::numeric))
             when (p_d ->> 'chegou_em')::date = v_hoje then 'na mão (desde hoje)'
             else 'na mão desde ' || public._dia_curto((p_d ->> 'chegou_em')::date) end
      when 'comprado' then
        'comprado' || case when (p_d ->> 'comprado_em')::date = v_hoje then ' hoje'
                           else ' em ' || public._dia_curto((p_d ->> 'comprado_em')::date) end
        || case when p_d ->> 'previsao_ate' is not null
                then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' else '' end
      when 'a_caminho' then
        case when p_d ->> 'previsao_ate' is null then 'a caminho, sem previsão'
             when p_d ->> 'previsao_de' is not null then
               format('chega entre %s e %s (você disse)', public._dia_curto((p_d ->> 'previsao_de')::date),
                      public._dia_curto((p_d ->> 'previsao_ate')::date))
             else 'chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' end
      when 'falta' then
        case when coalesce((p_d ->> 'vou_comprar')::boolean, false) then
               case when p_d ->> 'compra_prevista_em' is null then 'você vai comprar'
                    else 'você compra ' || public._dia_curto((p_d ->> 'compra_prevista_em')::date) end
             else 'falta comprar' end
      when 'sem_previsao' then 'comprado, sem previsão de chegada'
      when 'dispensado' then 'não precisa mais (sai da lista)'
      else null end;
    if v_t is not null and v_forn is not null and p_d ->> 'acao' <> 'dispensado' then
      v_t := v_t || ', fornecedor ' || v_forn;
    end if;
    if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
      v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
    end if;
    return v_t;
  end if;

  if p_tipo = 'disponibilidade' then
    v_quando := case when (p_d ->> 'padrao')::boolean
                     then public._agenda_dias_semana_texto(array(select jsonb_array_elements_text(p_d -> 'dias_semana')::smallint))
                     else public._agenda_quando_texto((p_d ->> 'de')::date, (p_d ->> 'ate')::date) end;
    return case p_d ->> 'dito'
      when 'vem' then case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end || v_quando
      when 'nao_vem' then case when (p_d ->> 'eh_dono')::boolean then 'fora de campo ' else 'não vem ' end || v_quando
      when 'so_manha' then v_quando || ' à tarde, não'
      else v_quando || ' de manhã, não' end
      || case when coalesce((p_d ->> 'sabado_por_data')::boolean, false) then ' (sábado eu só conto por data)' else '' end;
  end if;

  -- FASE 2: os pedidos da conversa (marcar, aplicar/decidir, desfazer, andamento) chegam com a frase pronta do banco.
  if p_tipo in ('marcar', 'aplicar', 'desfazer', 'andamento') then
    return p_d ->> 'frase_pronta';
  end if;

  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento) trazem a frase pronta (dados.frase_pronta).';

-- ── 3. O planejar: o campo do pátio ──────────────────────────────────────────────────────────────────────
-- Corpo de 20261024160600 copiado; as mudanças estão marcadas "-- FASE 2:".

create or replace function public.agenda_rascunho_planejar(p_autor uuid, p_canal text, p_os text, p_dados jsonb,
                                                           p_trecho text, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  c_campos constant text[] := array['dias', 'com_quem', 'dono', 'precisa_ate', 'bem_fora', 'bem_livre_em', 'nao_antes_de',
                                    'nao_antes_motivo', 'escopo_em_aberto', 'escopo_decidido', 'congelar_ate', 'revisar_em',
                                    'prioridade', 'sem_material', 'aceitar_sugestao', 'limpar',
                                    'adiantavel_patio'];   -- FASE 2: adiantavel_patio
  -- O que o dono desfaz ("pode voltar", "tira da espera", "não tem mais data mínima", "o cliente não tem mais prazo",
  -- "o escopo está resolvido"): o campo volta a vazio.
  c_limpar constant text[] := array['espera', 'nao_antes', 'prazo', 'escopo', 'patio'];   -- FASE 2: patio
  v_limpar text[] := '{}';
  v_k      text;
  v_ro     jsonb;
  v_os     uuid;
  v_out    jsonb := '{}'::jsonb;
  v_n      numeric;
  v_sug    jsonb;
  v_x      jsonb;
  v_rp     jsonb;
  v_turnos text;
  v_equipe jsonb := '[]'::jsonb;
  v_dt     jsonb;
  v_dt2    jsonb;
  v_bem    text;
  v_txt    text;
  v_dias_os numeric;   -- FASE 2
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_planejar: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  -- A agenda desligada (agenda_config.modo_leitura) não anota: sem o *grava* ligado, o rascunho não teria saída.
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if jsonb_typeof(d) <> 'object' then
    raise exception 'agenda_rascunho_planejar: p_dados tem de ser um objeto' using errcode = '22023';
  end if;
  select k into v_k from jsonb_object_keys(d) k where k <> all (c_campos) order by k limit 1;
  if v_k is not null then
    raise exception 'agenda_rascunho_planejar: o campo "%" não existe', v_k using errcode = '22023';
  end if;
  d := jsonb_strip_nulls(d);
  if d ? 'limpar' then
    if jsonb_typeof(d -> 'limpar') <> 'array' then
      raise exception 'agenda_rascunho_planejar: limpar tem de ser uma lista (espera, nao_antes, prazo ou escopo)' using errcode = '22023';
    end if;
    v_limpar := array(select distinct x from jsonb_array_elements_text(d -> 'limpar') x order by 1);
    select x into v_k from unnest(v_limpar) x where x <> all (c_limpar) order by 1 limit 1;
    if v_k is not null then
      raise exception 'agenda_rascunho_planejar: limpar "%" não existe (espera, nao_antes, prazo ou escopo)', v_k using errcode = '22023';
    end if;
    -- Pôr e tirar a mesma coisa na mesma chamada é erro de quem chamou.
    if ('espera' = any (v_limpar) and (d ? 'congelar_ate' or d ? 'revisar_em'))
       or ('nao_antes' = any (v_limpar) and (d ? 'nao_antes_de' or d ? 'nao_antes_motivo'))
       or ('prazo' = any (v_limpar) and d ? 'precisa_ate')
       or ('escopo' = any (v_limpar) and d ? 'escopo_em_aberto')
       or ('patio' = any (v_limpar) and d ? 'adiantavel_patio') then   -- FASE 2
      raise exception 'agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada' using errcode = '22023';
    end if;
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que mudou nesse serviço.', 'sem_trecho');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;

  -- Dias: o número dito (no trecho) ou "aceito a sua estimativa" (a sugestão, com fonte 'aceita').
  if d ? 'dias' then
    begin
      v_n := (d ->> 'dias')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quantos dias? Diga em dias ou meio dia (por exemplo, "2 dias" ou "um dia e meio").', 'dias_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quantos dias.', public._agenda_dias(v_n)),
                                   'fora_do_trecho');
    end if;
    v_out := v_out || jsonb_build_object('dias', trim_scale(v_n), 'estimativa_fonte', 'dono');
  elsif coalesce((d ->> 'aceitar_sugestao')::boolean, false) then
    v_sug := public.os_duracao_sugerida(v_os);
    if coalesce((v_sug ->> 'sem_base')::boolean, false) or v_sug ->> 'sugerida' is null then
      return public._agenda_recusa('O orçamento não dá base para eu estimar: quantos dias?', 'sem_base');
    end if;
    v_out := v_out || jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'estimativa_fonte', 'aceita');
  end if;

  -- Quem vai, por turno ("dia" quando não disse).
  if d ? 'com_quem' then
    if jsonb_typeof(d -> 'com_quem') <> 'array' then
      raise exception 'agenda_rascunho_planejar: com_quem tem de ser uma lista' using errcode = '22023';
    end if;
    for v_x in select e from jsonb_array_elements(d -> 'com_quem') with ordinality t(e, o) order by o loop
      if jsonb_typeof(v_x) = 'string' then
        v_x := jsonb_build_object('pessoa', v_x #>> '{}');
      end if;
      v_turnos := coalesce(nullif(btrim(v_x ->> 'turnos'), ''), 'dia');
      if v_turnos not in ('dia', 'manha', 'tarde') then
        raise exception 'agenda_rascunho_planejar: turnos "%" inválido (dia, manha ou tarde)', v_turnos using errcode = '22023';
      end if;
      v_rp := public.agenda_resolver_pessoa(v_x ->> 'pessoa', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      v_equipe := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_equipe) with ordinality t(e, o)
                             where e ->> 'payee_id' <> v_rp ->> 'payee_id'), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
                                                          'turnos', v_turnos));
    end loop;
    v_out := v_out || jsonb_build_object('equipe', v_equipe);
  end if;

  if d ? 'dono' then
    if d ->> 'dono' not in ('abre_e_fecha', 'sempre', 'nunca') then
      raise exception 'agenda_rascunho_planejar: dono "%" inválido (abre_e_fecha, sempre ou nunca)', d ->> 'dono' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('dono', d ->> 'dono');
  end if;

  if d ? 'precisa_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'precisa_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o cliente precisa?', btrim(d ->> 'precisa_ate')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('precisa_ate', v_dt ->> 'ate');
  end if;

  -- O bem fora: "fora de 26 a 30/10", "fora até dia 3" (inclusive) ou "só fica livre dia 3" (livre nesse dia).
  if d ? 'bem_fora' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_fora', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o bem fica fora?', btrim(d ->> 'bem_fora')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('bem', jsonb_build_object(
      'modo', 'fora', 'de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date,
      'livre_em', (v_dt ->> 'ate')::date + 1));
  end if;
  if d ? 'bem_livre_em' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_livre_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('bem', case
      when (v_dt ->> 'de')::date <= p_hoje then jsonb_build_object('modo', 'livre')
      else jsonb_build_object('modo', 'livre_em', 'de', p_hoje, 'ate', (v_dt ->> 'de')::date - 1, 'livre_em', (v_dt ->> 'de')::date) end);
  end if;

  if d ? 'nao_antes_de' then
    v_dt := public._agenda_data_conferida(d ->> 'nao_antes_de', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('nao_antes_de', v_dt ->> 'de',
      'nao_antes_motivo', coalesce(left(nullif(btrim(d ->> 'nao_antes_motivo'), ''), 120), 'você disse'));
  elsif d ? 'nao_antes_motivo' then
    return public._agenda_recusa('Não antes de que dia?', 'sem_data');
  end if;

  if d ? 'escopo_em_aberto' then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', nullif(left(btrim(d ->> 'escopo_em_aberto'), 160), ''));
  end if;
  if d ? 'escopo_decidido' then
    v_out := v_out || jsonb_build_object('escopo_decidido', nullif(left(btrim(d ->> 'escopo_decidido'), 160), ''));
    if not d ? 'escopo_em_aberto' then
      -- O que o dono decidiu fecha a pergunta em aberto.
      v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
    end if;
  end if;

  if d ? 'congelar_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'congelar_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if d ? 'revisar_em' then
      v_dt2 := public._agenda_data_conferida(d ->> 'revisar_em', p_trecho, p_hoje, 'futuro');
      if not (v_dt2 ->> 'ok')::boolean then return v_dt2; end if;
    else
      v_dt2 := v_dt;   -- sem data para rever: revê no dia em que a espera acaba
    end if;
    v_out := v_out || jsonb_build_object('congelada_ate', v_dt ->> 'ate', 'revisar_em', v_dt2 ->> 'de');
  elsif d ? 'revisar_em' then
    return public._agenda_recusa('Em espera até quando?', 'sem_data');
  end if;

  if d ? 'prioridade' then
    begin
      v_n := (d ->> 'prioridade')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n not in (1, 2, 3) then
      raise exception 'agenda_rascunho_planejar: prioridade "%" inválida (1, 2 ou 3)', d ->> 'prioridade' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('prioridade', v_n::int);
  end if;

  if d ? 'sem_material' then
    v_out := v_out || jsonb_build_object('sem_material', (d ->> 'sem_material')::boolean);
  end if;

  -- FASE 2: quanto do serviço dá para adiantar no pátio sem o bem — o número tem de estar no que o dono disse e não
  -- passa dos dias do serviço (os ditos agora, ou os que já estavam).
  if d ? 'adiantavel_patio' then
    begin
      v_n := (d ->> 'adiantavel_patio')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quanto dá para adiantar no pátio? Diga em dias ou meio dia (por exemplo, "um dia").', 'patio_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quanto dá para adiantar no pátio.',
                                          public._agenda_dias(v_n)), 'fora_do_trecho');
    end if;
    v_dias_os := coalesce((v_out ->> 'dias')::numeric,
                          (select pl.dias from public.os_planejamento pl where pl.service_order_id = v_os));
    if v_dias_os is not null and v_n > v_dias_os then
      return public._agenda_recusa(format('O serviço todo é de %s: no pátio dá para adiantar no máximo isso. Quanto dá?',
                                          public._agenda_dias(v_dias_os)), 'patio_maior');
    end if;
    v_out := v_out || jsonb_build_object('adiantavel_patio', trim_scale(v_n));
  end if;

  -- O que o dono desfez: o campo vai como nulo (o *grava* grava vazio; a correção na mesma releitura também apaga).
  if 'espera' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('congelada_ate', null, 'revisar_em', null);
  end if;
  if 'nao_antes' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('nao_antes_de', null, 'nao_antes_motivo', null);
  end if;
  if 'prazo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('precisa_ate', null);
  end if;
  if 'escopo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
  end if;
  if 'patio' = any (v_limpar) then   -- FASE 2
    v_out := v_out || jsonb_build_object('adiantavel_patio', null);
  end if;

  if v_out = '{}'::jsonb then
    return public._agenda_recusa('O que mudou nesse serviço? (quantos dias, quem vai, até quando o cliente precisa…)', 'nada');
  end if;

  select case when public._agenda_normal(coalesce(vs.asset_type, vs.name)) ~ 'motorhome|motor home|trailer'
              then 'o motorhome' else 'o barco' end
    into v_bem
    from public.service_orders so left join public.vessels vs on vs.id = so.vessel_id
   where so.id = v_os;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'planejar', 'planejar:' || v_os::text, v_os,
                                          public._agenda_os_do_rascunho(v_ro) || jsonb_build_object('bem_nome', v_bem) || v_out,
                                          p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o que o dono disse do serviço vira RASCUNHO (nada em os_planejamento). p_dados: dias, com_quem [{pessoa, turnos dia|manha|tarde}], dono (abre_e_fecha|sempre|nunca), precisa_ate, bem_fora, bem_livre_em, nao_antes_de + nao_antes_motivo, escopo_em_aberto, escopo_decidido, congelar_ate + revisar_em, prioridade 1–3, sem_material, aceitar_sugestao, adiantavel_patio (dias que dá para adiantar no pátio sem o bem; Fase 2), limpar (espera, nao_antes, prazo, escopo, patio). OS e pessoas resolvidas no banco (ambíguo/não achado = pergunta, nada no rascunho); dias, dias no pátio e datas têm de estar no trecho; datas por agenda_data_dita. Devolve {ok, item, releitura} ou {ok:false, pergunta, opcoes}.';

-- ── 4. O aplicar do planejar: a coluna do pátio ─────────────────────────────────────────────────────────
-- Corpo de 20261024160600 copiado; as mudanças estão marcadas "-- FASE 2:".

create or replace function public._agenda_aplicar_planejar(p_autor uuid, p_os uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d           jsonb := coalesce(p_dados, '{}'::jsonb);
  v_old       public.os_planejamento%rowtype;
  v_new       public.os_planejamento%rowtype;
  v_eq_antes  jsonb;
  v_eq_depois jsonb;
  v_antes     jsonb := '{}'::jsonb;
  v_depois    jsonb := '{}'::jsonb;
  v_k         text;
begin
  if not exists (select 1 from public.service_orders where id = p_os) then
    raise exception 'o serviço % não existe mais', coalesce(d ->> 'numero', p_os::text) using errcode = 'P0001';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  select * into v_old from public.os_planejamento where service_order_id = p_os for update;
  v_new := v_old;

  if d ? 'dias' then
    v_new.dias := (d ->> 'dias')::numeric;
    v_new.estimativa_fonte := d ->> 'estimativa_fonte';
    v_new.estimativa_em := now();
  end if;
  if d ? 'dono' then v_new.dono_presenca := d ->> 'dono'; end if;
  if d ? 'precisa_ate' then v_new.precisa_ate := (d ->> 'precisa_ate')::date; end if;
  if d ? 'bem' then
    v_new.bem_indisponivel := case when d #>> '{bem,modo}' = 'livre' then '{}'::datemultirange
                                   else datemultirange(daterange((d #>> '{bem,de}')::date, (d #>> '{bem,livre_em}')::date, '[)')) end;
  end if;
  if d ? 'nao_antes_de' then
    v_new.nao_antes_de := (d ->> 'nao_antes_de')::date;
    v_new.nao_antes_motivo := d ->> 'nao_antes_motivo';
  end if;
  if d ? 'escopo_em_aberto' then v_new.escopo_em_aberto := d ->> 'escopo_em_aberto'; end if;
  if d ? 'escopo_decidido' then v_new.escopo_decidido := d ->> 'escopo_decidido'; end if;
  if d ? 'congelada_ate' then
    v_new.congelada_ate := (d ->> 'congelada_ate')::date;
    v_new.revisar_em := (d ->> 'revisar_em')::date;
  end if;
  if d ? 'prioridade' then v_new.prioridade_manual := (d ->> 'prioridade')::smallint; end if;
  if d ? 'sem_material' then
    v_new.material_conferido_em := case when (d ->> 'sem_material')::boolean then now() end;
  end if;
  -- FASE 2: o que dá para adiantar no pátio (null = o dono tirou).
  if d ? 'adiantavel_patio' then
    v_new.adiantavel_patio_dias := (d ->> 'adiantavel_patio')::numeric;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
    into v_eq_antes
    from public.os_planejamento_equipe e where e.service_order_id = p_os;
  if d ? 'equipe' then
    delete from public.os_planejamento_equipe where service_order_id = p_os;
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    select p_os, (e ->> 'payee_id')::uuid, e ->> 'turnos' from jsonb_array_elements(d -> 'equipe') e;
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
      into v_eq_depois
      from public.os_planejamento_equipe e where e.service_order_id = p_os;
  else
    v_eq_depois := v_eq_antes;
  end if;

  -- O histórico guarda só o que mudou: {campo: antes} e {campo: depois}.
  for v_k in select key from jsonb_each(to_jsonb(v_new) - array['historico', 'atualizado_em', 'atualizado_por', 'trecho', 'estimativa_em'])
  loop
    if to_jsonb(v_old) -> v_k is distinct from to_jsonb(v_new) -> v_k then
      v_antes := v_antes || jsonb_build_object(v_k, to_jsonb(v_old) -> v_k);
      v_depois := v_depois || jsonb_build_object(v_k, to_jsonb(v_new) -> v_k);
    end if;
  end loop;
  if v_eq_antes is distinct from v_eq_depois then
    v_antes := v_antes || jsonb_build_object('equipe', v_eq_antes);
    v_depois := v_depois || jsonb_build_object('equipe', v_eq_depois);
  end if;

  update public.os_planejamento
     set dias = v_new.dias, estimativa_fonte = v_new.estimativa_fonte, estimativa_em = v_new.estimativa_em,
         dono_presenca = v_new.dono_presenca, precisa_ate = v_new.precisa_ate, bem_indisponivel = v_new.bem_indisponivel,
         nao_antes_de = v_new.nao_antes_de, nao_antes_motivo = v_new.nao_antes_motivo,
         escopo_em_aberto = v_new.escopo_em_aberto, escopo_decidido = v_new.escopo_decidido,
         congelada_ate = v_new.congelada_ate, revisar_em = v_new.revisar_em, prioridade_manual = v_new.prioridade_manual,
         material_conferido_em = v_new.material_conferido_em,
         adiantavel_patio_dias = v_new.adiantavel_patio_dias,   -- FASE 2
         trecho = public._agenda_corta(p_trecho, 500),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = now(), atualizado_por = p_autor
   where service_order_id = p_os;
  return jsonb_build_object('antes', v_antes, 'depois', v_depois);
end;
$function$;

comment on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): grava em os_planejamento (e os_planejamento_equipe) uma linha de rascunho planejar — só os campos ditos (Fase 2: adiantavel_patio → adiantavel_patio_dias); a equipe dita substitui a anterior. Histórico {em, autor, trecho, antes, depois} com só o que mudou (os 20 mais novos). Só pelo agenda_rascunho_gravar; só service_role.';

-- ── 5. Os pedidos do dono pela conversa (só rascunho: o *grava* executa) ───────────────────────────────

-- As guardas comuns aos 4 tipos novos: o canal, a agenda ligada para a leitura (como a Fase 1) e a automática ligada
-- (fora de 'ligado' a agenda não marca nada), e as palavras do dono. null = pode seguir; senão a recusa pronta.
create or replace function public._agenda_pedido_recusa(p_canal text, p_trecho text, p_quem text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c public.agenda_config := public._agenda_cfg();
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception '%: canal "%" inválido (whatsapp ou painel)', p_quem, p_canal using errcode = '22023';
  end if;
  if c.modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if c.modo_proposta <> 'ligado' then
    return public._agenda_recusa('A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.', 'em_teste');
  end if;
  if nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que você quer na agenda.', 'sem_trecho');
  end if;
  return null;
end;
$function$;

comment on function public._agenda_pedido_recusa(text, text, text) is
  'Agenda de Produção (Fase 2, P4): as guardas dos pedidos da conversa (marcar, aplicar, desfazer, andamento) — canal whatsapp/painel (senão 22023), a agenda de produção desligada ("não anotei nada"), a automática fora de ligado ("ainda está em teste: mostro como ficaria, mas não marco nada.") e o trecho do dono. null = segue.';

-- A frase da OS que o motor encaixou, para a releitura: "Lenine (OS-00074), qui 29 e sex 30/10, você abre e fecha,
-- Roberto os 2 dias" (o item do motor sem o ponto, com a vírgula depois do nome), "(sai de …)" quando ela já tinha dia e,
-- no fim, o aviso do material quando o dia pedido vem antes dele ("— mas "Compressor" só chega por volta de …").
create or replace function public._agenda_frase_do_encaixe(p_sim jsonb, p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select regexp_replace(regexp_replace(rtrim(i ->> 'texto', '.'), ' — mas .*$', ''), '^([^:]*): ', '\1, ')
         || coalesce(' (sai de ' || nullif(public._agenda_dias_texto(array(
              select distinct (a ->> 'dia')::date
                from jsonb_array_elements(p_sim -> 'itens') c, jsonb_array_elements(c -> 'alocacoes') a
               where c ->> 'op' = 'cancelar' and (c ->> 'os')::uuid = p_os)), '') || ')', '')
         || coalesce(' — mas ' || (i ->> 'aviso_material'), '')
    from jsonb_array_elements(p_sim -> 'itens') with ordinality t(i, k)
   where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = p_os and i ->> 'tipo' <> 'reserva'
   order by k
   limit 1;
$function$;

comment on function public._agenda_frase_do_encaixe(jsonb, uuid) is
  'Agenda de Produção (Fase 2, P4): o encaixe de uma OS numa proposta do motor, em texto de releitura — "Lenine (OS-00074), qui 29 e sex 30/10, você abre e fecha, Roberto os 2 dias (sai de qua 04/11)", com o aviso do material no fim quando o dia pedido vem antes dele ("— mas "Compressor 12V SS65" só chega por volta de ter 06/10 (pronto qua 07/10)"). null = a OS não entrou.';

-- "Não cabe seg 02/11: o Roberto já está no Vanderlei. O primeiro dia que dá é sex 30/10." — quando o pedido não cabe.
create or replace function public._agenda_nao_cabe(p_sim jsonb, p_os uuid, p_de date, p_autor uuid, p_hoje date,
                                                   p_agora timestamptz, p_pergunta boolean)
 returns text
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_motivo text := (select f ->> 'texto' from jsonb_array_elements(coalesce(p_sim -> 'fora', '[]'::jsonb)) f
                     where (f ->> 'os')::uuid = p_os limit 1);
  v_s      jsonb;
  v_dia    date;
begin
  v_s := public.agenda_propor('os', null, null, array[p_os], '{}'::jsonb, false, 'dono', p_autor, p_hoje, p_agora);
  v_dia := (select min((i ->> 'de')::date) from jsonb_array_elements(v_s -> 'itens') i
             where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = p_os and i ->> 'tipo' <> 'reserva');
  if v_dia is null then
    return coalesce(public._agenda_maiuscula(regexp_replace(v_motivo, '^[^:]*: ', '')),
                    format('Não cabe %s, e não achei outro dia nas próximas semanas com a equipe de hoje.', public._dia_curto(p_de)));
  end if;
  return coalesce(rtrim(public._agenda_maiuscula(regexp_replace(v_motivo, '^[^:]*: ', '')), '.') || '.',
                  format('Não cabe %s.', public._dia_curto(p_de)))
         || format(' O primeiro dia que dá é %s.', public._dia_curto(v_dia))
         || case when p_pergunta then ' Marco nesse dia?' else '' end;
end;
$function$;

comment on function public._agenda_nao_cabe(jsonb, uuid, date, uuid, date, timestamptz, boolean) is
  'Agenda de Produção (Fase 2, P4): a frase de quando o pedido do dono não cabe — o porquê do motor e o 1º dia que dá sem o pedido (simulado, sem gravar), com "Marco nesse dia?" quando é pergunta.';

create or replace function public.agenda_rascunho_marcar(p_autor uuid, p_canal text, p_os text, p_quando text,
                                                         p_ate text default null, p_pessoa text default null,
                                                         p_trecho text default null,
                                                         p_hoje date default public._hoje_brt(),
                                                         p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_rec    jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_marcar');
  v_ro     jsonb;
  v_os     uuid;
  v_dt     jsonb;
  v_de     date;
  v_ate    date;
  v_rp     jsonb;
  v_pessoa uuid;
  v_s      jsonb;
  v_frase  text;
  v_item   jsonb;
  v_txt    text;
begin
  -- Fora de ligado a agenda não marca, mas mostra como ficaria (a simulação, sem rascunho).
  if v_rec is not null and v_rec ->> 'motivo' <> 'em_teste' then
    return v_rec;
  end if;
  if nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que você quer na agenda.', 'sem_trecho');
  end if;
  if nullif(btrim(coalesce(p_quando, '')), '') is null then
    return public._agenda_recusa('Para que dia?', 'sem_dia');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;

  v_dt := public._agenda_data_conferida(p_quando, p_trecho, p_hoje, 'futuro');
  if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
  v_de := (v_dt ->> 'de')::date;
  v_ate := (v_dt ->> 'ate')::date;
  if nullif(btrim(coalesce(p_ate, '')), '') is not null then
    v_dt := public._agenda_data_conferida(p_ate, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_ate := (v_dt ->> 'ate')::date;
  end if;
  if v_ate < v_de then
    return public._agenda_recusa(format('O período está invertido: %s.', public._agenda_quando_texto(v_ate, v_de)), 'periodo');
  end if;
  if v_ate < p_hoje then
    return public._agenda_recusa(format('"%s" já passou: para que dia?', btrim(p_quando)), 'data_passada');
  end if;
  v_de := greatest(v_de, p_hoje);

  if nullif(btrim(coalesce(p_pessoa, '')), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, v_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
        coalesce((select jsonb_agg(e ->> 'nome' order by o)
                    from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
    end if;
    v_pessoa := (v_rp ->> 'payee_id')::uuid;
  end if;

  -- O efeito, calculado agora pelo motor, sem gravar nada.
  v_s := public.agenda_propor('os', null, null, array[v_os],
           jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', v_os, 'de', v_de, 'ate', v_ate, 'pessoa', v_pessoa))),
           false, 'dono', v_autor, p_hoje, p_agora);
  v_frase := public._agenda_frase_do_encaixe(v_s, v_os);
  v_item := (select i from jsonb_array_elements(v_s -> 'itens') i
              where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = v_os and i ->> 'tipo' <> 'reserva' limit 1);

  if v_rec is not null then   -- em teste: só a simulação
    return public._agenda_recusa(
      'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada. '
      || coalesce('Ficaria assim: ' || v_frase || '.', public._agenda_nao_cabe(v_s, v_os, v_de, v_autor, p_hoje, p_agora, false)),
      'em_teste');
  end if;
  if v_frase is null then
    return public._agenda_recusa(public._agenda_nao_cabe(v_s, v_os, v_de, v_autor, p_hoje, p_agora, true), 'nao_cabe');
  end if;

  -- O dia pedido antes de o material estar garantido (o caso da OS-00104): a decisão é do dono, mas a releitura vira a
  -- pergunta — o aviso do material e "Marco mesmo assim?"; o *grava* é o sim.
  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'marcar', 'marcar:' || v_os::text, v_os,
             jsonb_build_object('grupo', 'marcar:' || v_os::text, 'rotulo_grupo', 'Marco na agenda', 'os', v_os,
                                'numero', v_ro ->> 'numero', 'curto', v_ro ->> 'cliente_curto', 'de', v_de, 'ate', v_ate,
                                'pessoa', v_pessoa, 'pessoa_nome', v_rp ->> 'nome_curto',
                                'simulado', jsonb_build_object('de', v_item ->> 'de', 'ate', v_item ->> 'ate'),
                                'aviso_material', v_item ->> 'aviso_material',
                                'frase_pronta', v_frase || case when v_item ->> 'aviso_material' is not null
                                                                then '. Marco mesmo assim?' else '' end),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto')
         || case when v_item ->> 'aviso_material' is not null
                 then jsonb_build_object('aviso_material', v_item ->> 'aviso_material',
                                         'pergunta', format('%s: %s. Marco mesmo assim? Se sim, mande *grava*.',
                                                            public._agenda_rotulo_da_os(v_os), v_item ->> 'aviso_material'))
                 else '{}'::jsonb end;
end;
$function$;

comment on function public.agenda_rascunho_marcar(uuid, text, text, text, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): "marca o Lenine pra quinta", "passa o Nelson para segunda" vira RASCUNHO (nada na agenda). OS por agenda_resolver_os, o dia (e o até) por agenda_data_dita e dito no trecho, a pessoa por agenda_resolver_pessoa; o encaixe simulado agora pelo motor (agenda_propor os + fixar, sem gravar). Cabe → rascunho marcar:<os> {os, de, ate, pessoa, simulado} com a releitura ("Marco na agenda: Lenine (OS-00074), qui 29 e sex 30/10, você abre e fecha, Roberto os 2 dias."); o dia antes de o material estar garantido entra com o aviso e a pergunta ("… — mas "Compressor 12V SS65" só chega por volta de ter 06/10 (pronto qua 07/10). Marco mesmo assim?"; o *grava* é o sim), e a resposta traz aviso_material e pergunta. Não cabe → {ok:false, pergunta "… O primeiro dia que dá é sex 30/10. Marco nesse dia?"}. Fora de modo_proposta ligado: só a simulação ("ainda está em teste… Ficaria assim: …"), nada no rascunho. O *grava* chama agenda_marcar_os (via dono).';

create or replace function public.agenda_rascunho_aplicar(p_autor uuid, p_canal text, p_proposta text default null,
                                                          p_os text[] default null, p_decisao text default null,
                                                          p_opcao text default null, p_trecho text default null,
                                                          p_hoje date default public._hoje_brt(),
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_rec    jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_aplicar');
  cf       public.agenda_config := public._agenda_cfg();
  v_lista  jsonb;
  v_q      jsonb;
  v_qs     jsonb;
  v_opc    jsonb;
  v_opcs   jsonb;
  v_ro     jsonb;
  v_n      int;
  v_ref    text;
  v_sim    jsonb;
  v_mud    text;
  v_p      public.agenda_propostas%rowtype;
  v_os     uuid[];
  v_x      text;
  v_viol   jsonb;
  v_sel    jsonb;
  v_frase  text;
  v_txt    text;
  v_ncanc  int;
begin
  if v_rec is not null then
    return v_rec;
  end if;
  if p_decisao is not null and p_proposta is not null then
    raise exception 'agenda_rascunho_aplicar: diga a proposta OU a decisão, não as duas' using errcode = '22023';
  end if;

  -- ── Responder uma decisão crítica ──
  if nullif(btrim(coalesce(p_decisao, '')), '') is not null or nullif(btrim(coalesce(p_opcao, '')), '') is not null then
    v_lista := public.agenda_decisoes_abertas(p_agora);
    if jsonb_array_length(v_lista) = 0 then
      return public._agenda_recusa('Não tenho decisão da agenda esperando você agora.', 'sem_decisao');
    end if;
    v_ref := btrim(coalesce(p_decisao, ''));
    if v_ref ~ '^\d{1,3}$' then
      select q into v_q from jsonb_array_elements(v_lista) q where (q ->> 'n')::int = v_ref::int;
      if v_q is null then
        return public._agenda_recusa(format('Não tenho a decisão %s. As que esperam você: %s.', v_ref,
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_lista) q)), 'decisao_nao_existe');
      end if;
    elsif v_ref <> '' then
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(q order by (q ->> 'n')::int), '[]'::jsonb) into v_qs
        from jsonb_array_elements(v_lista) q
       where q ->> 'os' = v_ro ->> 'id' or (q -> 'os_ids') ? (v_ro ->> 'id');
      if jsonb_array_length(v_qs) = 0 then
        return public._agenda_recusa(format('Não tenho decisão esperando você sobre %s.', v_ro ->> 'cliente_curto'), 'decisao_nao_existe');
      end if;
      if jsonb_array_length(v_qs) > 1 then
        return public._agenda_recusa(format('Qual delas? %s.',
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_qs) q)), 'decisao_ambigua');
      end if;
      v_q := v_qs -> 0;
    elsif jsonb_array_length(v_lista) = 1 then
      v_q := v_lista -> 0;
    else
      return public._agenda_recusa(format('Qual decisão? %s.',
        (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
           from jsonb_array_elements(v_lista) q)), 'decisao_ambigua');
    end if;

    -- A opção: o nº ou o nome da OS que aceita atrasar. Sem ela, a pergunta volta como está (o banco não escolhe).
    v_ref := btrim(coalesce(p_opcao, ''));
    if v_ref = '' then
      return public._agenda_recusa(rtrim(v_q ->> 'texto', ' ')
        || case when (v_q ->> 'texto') ~ '\d\)' then '' else ' ' || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; '
                                                                   order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o) end,
        'sem_opcao',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;
    if v_ref ~ '^\d{1,2}$' then
      select o into v_opc from jsonb_array_elements(v_q -> 'opcoes') o where (o ->> 'n')::int = v_ref::int;
    else
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(o order by (o ->> 'n')::int), '[]'::jsonb) into v_opcs
        from jsonb_array_elements(v_q -> 'opcoes') o where o ->> 'os' = v_ro ->> 'id';
      if jsonb_array_length(v_opcs) > 1 then
        return public._agenda_recusa(format('Qual das opções? %s',
          (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
             from jsonb_array_elements(v_opcs) o)) || '.', 'opcao_ambigua');
      end if;
      v_opc := v_opcs -> 0;
    end if;
    if v_opc is null then
      return public._agenda_recusa('Essa opção não existe. As opções são: '
        || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
              from jsonb_array_elements(v_q -> 'opcoes') o) || '.', 'opcao_nao_existe',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;

    -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
    -- volta com os dias de agora (a mesma régua do agenda_decidir).
    if (v_q ->> 'versao_base')::bigint is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
       and v_opc -> 'espera' <> '{}'::jsonb then
      v_sim := public.agenda_propor('replano', null, null, array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x),
                                    coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb), false, 'dono', v_autor, p_hoje, p_agora);
      select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                               coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
        into v_mud
        from jsonb_each(v_opc -> 'espera') e
        left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                            where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
       where x.fim is distinct from (e.value #>> '{}')::date;
      if v_mud is not null then
        return public._agenda_recusa('A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.',
                                     'decisao_mudou');
      end if;
    end if;

    v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'decisao:' || (v_q ->> 'id'),
               nullif(v_q ->> 'os', '')::uuid,
               jsonb_build_object('grupo', 'decisao:' || (v_q ->> 'id'), 'rotulo_grupo', 'Decisão', 'pergunta_id', v_q ->> 'id',
                                  'opcao', (v_opc ->> 'n')::int, 'opcao_texto', v_opc ->> 'texto',
                                  'frase_pronta', rtrim(v_opc ->> 'texto', '.')),
               p_trecho, p_hoje);
    return jsonb_build_object('ok', true, 'item', v_txt,
                              'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
  end if;

  -- ── Publicar uma proposta aberta ──
  v_lista := public.agenda_propostas_abertas(p_agora);
  if jsonb_array_length(v_lista) = 0 then
    return public._agenda_recusa('Não tenho plano montado para publicar. Peça para eu montar (por exemplo, "monta a semana que vem").',
                                 'sem_proposta');
  end if;
  v_ref := public._agenda_normal(p_proposta);
  v_n := case when v_ref in ('', 'a ultima', 'ultima', 'essa', 'esta', 'a proposta', 'proposta', 'ela', 'isso', 'a semana', 'semana')
              then 1
              when v_ref ~ '^\d{1,3}$' then v_ref::int end;
  if v_n is null then
    return public._agenda_recusa(format('Qual plano? %s.',
      (select string_agg((p ->> 'n') || ') ' || coalesce(p ->> 'titulo', 'plano'), '; ' order by (p ->> 'n')::int)
         from jsonb_array_elements(v_lista) p)), 'proposta_ambigua');
  end if;
  select pr.* into v_p from public.agenda_propostas pr
   where pr.id = (select (p ->> 'id')::uuid from jsonb_array_elements(v_lista) p where (p ->> 'n')::int = v_n);
  if not found then
    return public._agenda_recusa(format('Não tenho o plano %s montado.', v_n), 'proposta_nao_existe');
  end if;
  if v_p.versao_base <> cf.versao_plano then
    return public._agenda_recusa('A agenda mudou desde que eu montei: peça de novo que eu refaço.', 'proposta_obsoleta');
  end if;

  -- só as OS ditas ("publica só o Lenine e o Flávio"), e só se estão na proposta
  if p_os is not null and cardinality(p_os) > 0 then
    v_os := '{}';
    foreach v_x in array p_os loop
      v_ro := public.agenda_resolver_os(v_x, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      if not exists (select 1 from jsonb_array_elements(v_p.itens) i where i ->> 'os' = v_ro ->> 'id') then
        return public._agenda_recusa(format('%s não está nesse plano.', v_ro ->> 'cliente_curto'), 'os_fora_da_proposta');
      end if;
      v_os := v_os || (v_ro ->> 'id')::uuid;
    end loop;
    v_os := array(select distinct x from unnest(v_os) x order by 1);
  end if;

  v_viol := public.agenda_validar(v_p.id, v_os, p_hoje, p_agora);
  if jsonb_array_length(v_viol) > 0 then
    return public._agenda_recusa('Não dá para publicar: '
      || (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_viol) with ordinality t(e, o)), 'proposta_invalida');
  end if;
  v_sel := public._agenda_itens_escolhidos(v_p.itens, v_os, null);
  if not exists (select 1 from jsonb_array_elements(v_sel) i where i ->> 'op' = 'criar') and jsonb_array_length(v_sel) = 0 then
    return public._agenda_recusa('No plano que eu montei não há nada para publicar sem a sua decisão: veja o que a agenda precisa de você.',
                                 'so_critico');
  end if;
  v_ncanc := (select count(*) from jsonb_array_elements(v_sel) i where i ->> 'op' = 'cancelar');
  v_frase := case when v_p.escopo = 'semana'
                  then lower(left(coalesce(v_p.textos ->> 'titulo', 'a semana'), 1)) || substr(coalesce(v_p.textos ->> 'titulo', 'a semana'), 2) || ': '
                  else '' end
             || coalesce(nullif(array_to_string(array(
                  select regexp_replace(rtrim(i ->> 'texto', '.'), '^([^:]*): ', '\1, ')
                    from jsonb_array_elements(v_sel) with ordinality t(i, k)
                   where i ->> 'op' = 'criar'
                   order by (i ->> 'de')::date, i ->> 'numero' collate "C", k), '; '), ''), 'nada novo')
             || case when v_ncanc > 0 then format('; e tiro da agenda %s que não pode mais acontecer',
                                                   public._agenda_plural(v_ncanc, 'serviço', 'serviços')) else '' end;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'aplicar:' || v_p.id::text, null,
             jsonb_build_object('grupo', 'aplicar:' || v_p.id::text, 'rotulo_grupo', 'Publico na agenda', 'proposta_id', v_p.id,
                                'os_ids', to_jsonb(v_os), 'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): vira RASCUNHO (nada muda) — publicar uma proposta aberta ("pode publicar", "publica só o Lenine e o Flávio": p_proposta "a última" ou o nº de agenda_propostas_abertas, p_os as OS ditas; obsoleta, inválida ou só com crítico = recusa) ou responder uma decisão crítica (p_decisao = o nº de agenda_decisoes_abertas ou o nome da OS; p_opcao = o nº ou o nome da OS que aceita atrasar). Sem opção dita: a pergunta com as opções volta como está — o banco não escolhe. Se a agenda mudou desde a pergunta e o efeito da opção também, a pergunta volta com os dias de agora. Chave aplicar:<proposta> / decisao:<pergunta>; releitura "Publico na agenda: …" / "Decisão: …". O *grava* chama agenda_aplicar (via dono) ou agenda_decidir (respondida_via = o canal).';

create or replace function public.agenda_rascunho_desfazer(p_autor uuid, p_canal text, p_alvo text default null,
                                                           p_trecho text default null,
                                                           p_hoje date default public._hoje_brt(),
                                                           p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_rec   jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_desfazer');
  v_ref   jsonb;
  v_ids   uuid[];
  v_a     public.agenda_acoes%rowtype;
  v_quando text;
  v_frase text;
  v_txt   text;
begin
  if v_rec is not null then
    return v_rec;
  end if;
  v_ref := public.agenda_acao_desfazivel(p_alvo, p_hoje, p_agora);
  if v_ref ->> 'status' is distinct from 'ok' then
    return public._agenda_recusa(v_ref ->> 'texto', 'desfazer_' || coalesce(v_ref ->> 'status', 'nenhuma'),
      coalesce((select jsonb_agg(coalesce(e ->> 'texto', e #>> '{}') order by o)
                  from jsonb_array_elements(case when jsonb_typeof(v_ref -> 'opcoes') = 'array' then v_ref -> 'opcoes' else '[]'::jsonb end)
                       with ordinality t(e, o)), '[]'::jsonb));
  end if;
  v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_ref -> 'acao_ids', jsonb_build_array(v_ref ->> 'acao_id'))) x);
  select * into v_a from public.agenda_acoes where id = v_ids[1];
  -- o que já começou não se desfaz (a mesma régua de agenda_desfazer): melhor dizer agora do que no *grava*
  if exists (select 1 from public.agenda_acoes ac join public.agenda_alocacoes a on a.id = any (ac.alocacoes_criadas)
              where ac.id = any (v_ids) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return public._agenda_recusa(format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.',
                                        coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                                    join public.clients cl on cl.id = so.client_id where so.id = v_a.service_order_id),
                                                 'serviço')), 'ja_comecou');
  end if;
  v_quando := format('mudei %s às %s',
                     case when v_a.dia = p_hoje then 'hoje' when v_a.dia = p_hoje - 1 then 'ontem' else public._dia_curto(v_a.dia) end,
                     to_char(v_a.criada_em at time zone 'America/Sao_Paulo', 'HH24:MI'));
  v_frase := case when cardinality(v_ids) > 1
                  then format('a publicação da semana (%s; %s)', public._agenda_plural(cardinality(v_ids), 'serviço', 'serviços'), v_quando)
                  else format('%s (%s)', rtrim(v_a.texto, '.'), v_quando) end;
  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'desfazer', 'desfazer:' || v_ids[1]::text, v_a.service_order_id,
             jsonb_build_object('grupo', 'desfazer:' || v_ids[1]::text, 'rotulo_grupo', 'Desfaço', 'acao_ids', to_jsonb(v_ids),
                                'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_desfazer(uuid, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): "desfaz", "volta como estava" vira RASCUNHO (nada muda): agenda_acao_desfazivel(p_alvo) — o nome ou o número da OS, "semana", "a última" ou nada; ambíguo ou nada a desfazer = a frase pronta; o que já começou = recusa na hora. Chave desfazer:<acao>; releitura "Desfaço: Nelson (OS-00112): de … para … (mudei hoje às 14:20)." O *grava* chama agenda_desfazer (via dono) para cada ação ("semana" = todas, tudo ou nada).';

create or replace function public.agenda_rascunho_andamento(p_autor uuid, p_canal text, p_os text, p_evento text,
                                                            p_dia text default null, p_quem text[] default null,
                                                            p_motivo text default null, p_trecho text default null,
                                                            p_hoje date default public._hoje_brt(),
                                                            p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_ev      text := public._agenda_normal(p_evento);
  v_rec     jsonb;
  v_ro      jsonb;
  v_os      uuid;
  v_status  text;
  v_dia     date := p_hoje;
  v_dt      jsonb;
  v_rp      jsonb;
  v_x       text;
  v_pes     uuid[];
  v_nomes   text[] := '{}';
  v_quem    text;
  v_motivo  text;
  v_res     text;
  v_m       boolean;
  v_t       boolean;
  v_turnos  text;
  v_fora    text[];
  v_check   timestamptz;
  v_para    text;
  v_futuros date[];
  v_frase   text;
  v_chave   text;
  v_plural  boolean;
  v_txt     text;
begin
  -- Concluir e entregar não são andamento: a conclusão grava a saída e lança as cobranças, e isso é pela tela.
  if v_ev in ('concluiu', 'concluida', 'concluido', 'terminou', 'acabou', 'finalizou', 'entregou', 'entregue', 'pronto', 'pronta') then
    return public._agenda_recusa('Concluir ainda é pela tela (botão Concluir da OS): é lá que saem a saída e as cobranças.', 'concluir');
  end if;
  if v_ev not in ('trabalhou', 'parcial', 'nao foi', 'nao_foi', 'comecou', 'parou') then
    raise exception 'agenda_rascunho_andamento: evento "%" não existe (trabalhou, parcial, nao_foi, comecou ou parou)', p_evento
      using errcode = '22023';
  end if;
  v_ev := replace(v_ev, ' ', '_');
  v_rec := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_andamento');
  if v_rec is not null then
    return v_rec;
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  select so.status into v_status from public.service_orders so where so.id = v_os;

  if nullif(btrim(coalesce(p_dia, '')), '') is not null then
    v_dt := public._agenda_data_conferida(p_dia, p_trecho, p_hoje, 'passado');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'de') is distinct from (v_dt ->> 'ate') then
      return public._agenda_recusa('Diga um dia só (por exemplo "hoje", "ontem" ou "segunda").', 'um_dia');
    end if;
    v_dia := (v_dt ->> 'de')::date;
  end if;
  if v_dia > p_hoje then
    return public._agenda_recusa(public._agenda_maiuscula(public._dia_curto(v_dia)) || ' ainda não chegou: não dá para dizer como foi.',
                                 'dia_futuro');
  end if;

  if p_quem is not null and cardinality(p_quem) > 0 then
    v_pes := '{}';
    foreach v_x in array p_quem loop
      v_rp := public.agenda_resolver_pessoa(v_x, v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      continue when (v_rp ->> 'payee_id')::uuid = any (v_pes);
      v_pes := v_pes || (v_rp ->> 'payee_id')::uuid;
      v_nomes := v_nomes || case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'você' else v_rp ->> 'nome_curto' end;
    end loop;
    v_quem := public._agenda_lista(v_nomes, null);
    v_plural := cardinality(v_pes) > 1;
  end if;

  v_motivo := public._agenda_motivo_dito(p_motivo);
  if v_ev in ('parcial', 'nao_foi') and v_motivo is null then
    return public._agenda_recusa('Me diga o motivo: material, cliente, equipe, clima, imprevisto, anterior, informação, estimativa, urgência ou esqueci.',
                                 'sem_motivo');
  end if;

  if v_ev in ('trabalhou', 'parcial', 'nao_foi') then
    v_res := case v_ev when 'trabalhou' then 'cumprido' when 'parcial' then 'parcial' else 'nao_cumprido' end;
    -- o plano do dia: quem estava, e (para feito e em parte) o que já começou
    if not exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') then
      return public._agenda_recusa(format('%s não estava no plano %s. Para a diária de quem trabalhou, me diga quem e quanto.',
                                          public._agenda_rotulo_da_os(v_os), public._agenda_dia_ref(v_dia, p_hoje)), 'fora_do_plano');
    end if;
    if v_pes is not null then
      v_fora := array(select n from unnest(v_pes, v_nomes) u(p, n)
                       where not exists (select 1 from public.agenda_alocacoes a
                                          where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada')
                                            and a.tipo <> 'reserva' and a.payee_id = u.p));
      if cardinality(v_fora) > 0 then
        return public._agenda_recusa(format('Pelo plano, %s não %s no %s %s.', public._agenda_lista(v_fora, null),
                                            case when cardinality(v_fora) > 1 then 'estavam' else 'estava' end,
                                            v_ro ->> 'cliente_curto', public._agenda_dia_ref(v_dia, p_hoje)), 'pessoa_fora_do_plano');
      end if;
    end if;
    if v_res <> 'nao_cumprido'
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          and (v_pes is null or a.payee_id = any (v_pes)) and lower(a.periodo) <= p_agora) then
      return public._agenda_recusa(format('Ainda não começou nada do plano do %s %s.', v_ro ->> 'cliente_curto',
                                          public._agenda_dia_ref(v_dia, p_hoje)), 'nao_comecou');
    end if;
    select bool_or(a.turno = 'manha'), bool_or(a.turno = 'tarde') into v_m, v_t
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and (v_pes is null or a.payee_id = any (v_pes));
    v_turnos := case when v_m and v_t then ' o dia todo' when v_m then ' de manhã' when v_t then ' à tarde' else '' end;
    v_frase := case
      when v_ev = 'trabalhou' and v_quem is null then 'feito, com ' || public._agenda_quem(v_os, v_dia)
      when v_ev = 'trabalhou' then v_quem || case when v_plural then ' trabalharam' else ' trabalhou' end || v_turnos
      when v_ev = 'parcial' and v_quem is null then format('andou em parte (%s)', public._agenda_motivo_texto(v_motivo))
      when v_ev = 'parcial' then format('%s %s em parte (%s)', v_quem, case when v_plural then 'trabalharam' else 'trabalhou' end,
                                        public._agenda_motivo_texto(v_motivo))
      when v_quem is null then format('não andou (%s)', public._agenda_motivo_texto(v_motivo))
      else format('%s %s (%s)', v_quem, case when v_plural then 'não foram' else 'não foi' end, public._agenda_motivo_texto(v_motivo)) end;
    v_chave := format('andamento:%s:%s:%s', v_os, v_dia,
                      coalesce('p' || left(md5((select string_agg(x::text, ',' order by x) from unnest(v_pes) x)), 20), 'todos'));

  elsif v_ev = 'comecou' then
    if v_status = 'in_progress' then
      return public._agenda_recusa(format('%s já está em andamento.', public._agenda_rotulo_da_os(v_os)), 'ja_em_andamento');
    end if;
    if v_status not in ('open', 'approved', 'scheduled', 'awaiting_parts', 'awaiting_client') then
      return public._agenda_recusa(format('%s está %s: a agenda não muda o status dela.', public._agenda_rotulo_da_os(v_os),
                                          public._agenda_status_texto(v_status)), 'status');
    end if;
    -- o início é a manhã do dia dito (o banco deriva a hora; ninguém grava hora dita)
    v_check := lower(public.agenda_periodo(v_dia, 'manha'));
    v_frase := format('começou (início às %s)', to_char(v_check at time zone 'America/Sao_Paulo', 'HH24:MI'));
    v_chave := format('andamento:%s:%s:status', v_os, v_dia);

  else  -- parou
    if v_motivo is null or v_motivo not in ('material', 'cliente_ou_bem') then
      return public._agenda_recusa('Parou por quê? Se falta peça, diga material; se o cliente ou o barco não liberou, diga cliente.',
                                   'parou_motivo');
    end if;
    v_para := case when v_motivo = 'material' then 'awaiting_parts' else 'awaiting_client' end;
    if v_status = v_para then
      return public._agenda_recusa(format('%s já está %s.', public._agenda_rotulo_da_os(v_os), public._agenda_status_texto(v_para)),
                                   'ja_esta');
    end if;
    if v_status not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client') then
      return public._agenda_recusa(format('%s está %s: a agenda não muda o status dela.', public._agenda_rotulo_da_os(v_os),
                                          public._agenda_status_texto(v_status)), 'status');
    end if;
    v_futuros := array(select distinct a.dia from public.agenda_alocacoes a
                        where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.resultado is null
                          and lower(a.periodo) > p_agora order by 1);
    v_frase := format('parou (%s): passa a %s%s', public._agenda_motivo_texto(v_motivo), public._agenda_status_texto(v_para),
                      case when cardinality(v_futuros) > 0
                           then ' e sai da agenda ' || public._agenda_dias_texto(v_futuros) else '' end);
    v_chave := format('andamento:%s:%s:status', v_os, v_dia);
  end if;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'andamento', v_chave, v_os,
             jsonb_build_object('grupo', format('andamento:%s:%s', v_os, v_dia),
                                'rotulo_grupo', public._agenda_maiuscula(public._agenda_dia_ref(v_dia, p_hoje)) || ', '
                                                || public._agenda_rotulo_da_os(v_os),
                                'os', v_os, 'dia', v_dia, 'evento', v_ev, 'resultado', v_res, 'pessoas', to_jsonb(v_pes),
                                'nomes', to_jsonb(v_nomes), 'motivo', v_motivo, 'status_para', v_para, 'check_in', v_check,
                                'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): o que aconteceu na OS vira RASCUNHO (nada muda) — trabalhou · parcial · nao_foi (o resultado do meio-dia no plano: as pessoas ditas têm de estar no plano do dia; feito e em parte só no que já começou; parcial e não foi pedem o motivo LCI) · comecou (em andamento, com o início na manhã do dia dito) · parou (material → aguardando peças; cliente → aguardando o cliente; sai da agenda o que ainda não começou). "Concluiu"/"entregou" = recusa: concluir é pela tela. O dia por agenda_data_dita (passado, dito no trecho; sem dia = hoje). Chave andamento:<os>:<dia>:<quem> (começou/parou: :status); a releitura junta os fatos da OS no dia ("Hoje (ter 03/11), Vanderlei (OS-00069): Roberto trabalhou o dia todo; João não foi (equipe)."). O *grava* chama agenda_registrar_dia (via conversa) ou a porta (via dono).';

-- A entrada da ferramenta agenda_propor (P6): as referências do dono resolvidas pelo banco e o motor. Simular (padrão)
-- não grava nada; simular = false grava só a proposta aberta, que não vale para ninguém até o *grava* de
-- agenda_rascunho_aplicar. Revisão da Fase 2: o dia de "fixar" e de "só depois de" tem de estar nas palavras do dono
-- (p_trecho, _agenda_data_conferida), como no marcar — o modelo nunca escolhe o dia.
-- (a versão sem p_trecho sai: a nova não pode conviver com ela, o PostgREST não saberia qual chamar)
drop function if exists public.agenda_propor_dito(uuid, text, text, text[], jsonb, text[], jsonb, boolean, boolean, date, timestamptz);
create or replace function public.agenda_propor_dito(p_autor uuid, p_canal text, p_escopo text, p_os text[] default null,
                                                     p_fixar jsonb default null, p_tirar text[] default null,
                                                     p_so_depois_de jsonb default null, p_acima_da_carga boolean default false,
                                                     p_simular boolean default true,
                                                     p_hoje date default public._hoje_brt(),
                                                     p_agora timestamptz default now(),
                                                     p_trecho text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_escopo text;
  v_ids    uuid[] := '{}';
  v_tirar  uuid[] := '{}';
  v_fixar  jsonb := '[]'::jsonb;
  v_depois jsonb := '[]'::jsonb;
  v_restr  jsonb := '{}'::jsonb;
  v_ro     jsonb;
  v_rp     jsonb;
  v_x      text;
  v_e      jsonb;
  v_de     jsonb;
  v_ate    jsonb;
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_propor_dito: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora.', 'desligada');
  end if;
  -- o dia de "fixar" e de "só depois de" é conferido nas palavras do dono
  if (case when jsonb_typeof(p_fixar) = 'array' then jsonb_array_length(p_fixar) else 0 end
      + case when jsonb_typeof(p_so_depois_de) = 'array' then jsonb_array_length(p_so_depois_de) else 0 end) > 0
     and nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que você quer na agenda.', 'sem_trecho');
  end if;
  v_escopo := case lower(btrim(coalesce(p_escopo, ''))) when 'semana' then 'semana' when 'proxima_semana' then 'semana'
                                                         when 'os' then 'os' when 'replano' then 'replano' end;
  if v_escopo is null then
    raise exception 'agenda_propor_dito: escopo "%" não existe (semana, proxima_semana, os ou replano)', p_escopo using errcode = '22023';
  end if;

  -- as OS (para os/replano, as do pedido mais as que ele fixa ou adia)
  foreach v_x in array coalesce(p_os, '{}'::text[]) loop
    v_ro := public.agenda_resolver_os(v_x, p_hoje, false);
    if v_ro ->> 'status' <> 'ok' then return public._agenda_recusa_da_os(v_ro); end if;
    v_ids := v_ids || (v_ro ->> 'id')::uuid;
  end loop;
  foreach v_x in array coalesce(p_tirar, '{}'::text[]) loop
    v_ro := public.agenda_resolver_os(v_x, p_hoje, false);
    if v_ro ->> 'status' <> 'ok' then return public._agenda_recusa_da_os(v_ro); end if;
    v_tirar := v_tirar || (v_ro ->> 'id')::uuid;
  end loop;
  if p_fixar is not null and jsonb_typeof(p_fixar) <> 'array' then
    raise exception 'agenda_propor_dito: fixar tem de ser uma lista [{os, quando, ate, pessoa}]' using errcode = '22023';
  end if;
  for v_e in select e from jsonb_array_elements(coalesce(p_fixar, '[]'::jsonb)) with ordinality t(e, o) order by o loop
    v_ro := public.agenda_resolver_os(v_e ->> 'os', p_hoje, false);
    if v_ro ->> 'status' <> 'ok' then return public._agenda_recusa_da_os(v_ro); end if;
    v_de := public._agenda_data_conferida(v_e ->> 'quando', p_trecho, p_hoje, 'futuro');
    if not (v_de ->> 'ok')::boolean then return v_de; end if;
    v_ate := v_de;
    if nullif(btrim(coalesce(v_e ->> 'ate', '')), '') is not null then
      v_ate := public._agenda_data_conferida(v_e ->> 'ate', p_trecho, p_hoje, 'futuro');
      if not (v_ate ->> 'ok')::boolean then return v_ate; end if;
    end if;
    v_rp := null;
    if nullif(btrim(coalesce(v_e ->> 'pessoa', '')), '') is not null then
      v_rp := public.agenda_resolver_pessoa(v_e ->> 'pessoa', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status')); end if;
    end if;
    v_fixar := v_fixar || jsonb_build_array(jsonb_build_object('os', v_ro ->> 'id', 'de', greatest((v_de ->> 'de')::date, p_hoje),
                                                               'ate', (v_ate ->> 'ate')::date, 'pessoa', v_rp ->> 'payee_id'));
    v_ids := v_ids || (v_ro ->> 'id')::uuid;
  end loop;
  if p_so_depois_de is not null and jsonb_typeof(p_so_depois_de) <> 'array' then
    raise exception 'agenda_propor_dito: so_depois_de tem de ser uma lista [{os, quando}]' using errcode = '22023';
  end if;
  for v_e in select e from jsonb_array_elements(coalesce(p_so_depois_de, '[]'::jsonb)) with ordinality t(e, o) order by o loop
    v_ro := public.agenda_resolver_os(v_e ->> 'os', p_hoje, false);
    if v_ro ->> 'status' <> 'ok' then return public._agenda_recusa_da_os(v_ro); end if;
    v_de := public._agenda_data_conferida(v_e ->> 'quando', p_trecho, p_hoje, 'futuro');
    if not (v_de ->> 'ok')::boolean then return v_de; end if;
    v_depois := v_depois || jsonb_build_array(jsonb_build_object('os', v_ro ->> 'id', 'dia', v_de ->> 'de'));
    v_ids := v_ids || (v_ro ->> 'id')::uuid;
  end loop;
  v_ids := array(select distinct x from unnest(v_ids) x order by 1);
  if v_escopo in ('os', 'replano') and cardinality(v_ids) = 0 then
    return public._agenda_recusa('De qual serviço?', 'sem_os');
  end if;

  if jsonb_array_length(v_fixar) > 0 then v_restr := v_restr || jsonb_build_object('fixar', v_fixar); end if;
  if cardinality(v_tirar) > 0 then v_restr := v_restr || jsonb_build_object('tirar', to_jsonb(v_tirar)); end if;
  if jsonb_array_length(v_depois) > 0 then v_restr := v_restr || jsonb_build_object('so_depois_de', v_depois); end if;
  if coalesce(p_acima_da_carga, false) then v_restr := v_restr || jsonb_build_object('acima_da_carga', true); end if;

  return public.agenda_propor(v_escopo, null, null, case when v_escopo = 'semana' then null else v_ids end, v_restr,
                              not coalesce(p_simular, true), 'dono', v_autor, p_hoje, p_agora);
end;
$function$;

comment on function public.agenda_propor_dito(uuid, text, text, text[], jsonb, text[], jsonb, boolean, boolean, date, timestamptz, text) is
  'Agenda de Produção (Fase 2, P4): a entrada da ferramenta agenda_propor — escopo semana/proxima_semana (a semana que o motor publica: a seguinte à de hoje), os ou replano; as OS por agenda_resolver_os, as datas por agenda_data_dita conferidas nas palavras do dono (p_trecho, obrigatório com fixar ou só depois de: "Não achei "quinta" no que você disse"), a pessoa por agenda_resolver_pessoa (ambíguo ou não achado = a pergunta, nada calculado); chama agenda_propor (origem dono). simular (padrão true) não grava nada e o texto termina com "É simulação: não muda nada."; simular = false grava só a proposta ABERTA (nunca publica: publicar é o *grava* de agenda_rascunho_aplicar). Admin pelo _autor_da_agenda.';

-- ── 6. O que o *grava* faz com cada pedido ──────────────────────────────────────────────────────────────
-- Recusa de qualquer função do motor = exceção P0097 com a frase dela: o *grava* desfaz o lote inteiro.
create or replace function public._agenda_aplicar_pedido(p_autor uuid, p_tipo text, p_os uuid, p_dados jsonb, p_trecho text,
                                                         p_canal text, p_hoje date, p_agora timestamptz)
 returns text
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  d       jsonb := coalesce(p_dados, '{}'::jsonb);
  v_r     jsonb;
  v_os    uuid := coalesce(p_os, (d ->> 'os')::uuid);
  v_d1    date;
  v_d2    date;
  v_txts  text[] := '{}';
  v_x     text;
  v_canc  uuid[];
  v_antes jsonb;
  v_dias  date[];
  v_id    uuid;
  v_txt   text;
begin
  if p_tipo = 'marcar' then
    v_r := public.agenda_marcar_os(p_autor, v_os, (d ->> 'de')::date, (d ->> 'ate')::date, nullif(d ->> 'pessoa', '')::uuid,
                                   'dono', 'dono', p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não coube');
    end if;
    -- o dono confirmou aqueles dias: a agenda tem de ter posto a OS neles
    select min(a.dia), max(a.dia) into v_d1, v_d2
      from public.agenda_acoes ac join public.agenda_alocacoes a on a.id = any (ac.alocacoes_criadas)
     where ac.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'acoes', '[]'::jsonb)) x)
       and a.service_order_id = v_os and a.tipo <> 'reserva';
    if v_d1 is distinct from (d #>> '{simulado,de}')::date or v_d2 is distinct from (d #>> '{simulado,ate}')::date then
      raise exception using errcode = 'P0097',
        message = format('%s ficaria %s, e não %s', public._agenda_rotulo_da_os(v_os),
                         coalesce(public._agenda_dias_texto(array[v_d1, v_d2]::date[]), 'fora da agenda'),
                         public._agenda_dias_texto(array[(d #>> '{simulado,de}')::date, (d #>> '{simulado,ate}')::date]::date[]));
    end if;
    return v_r ->> 'texto';
  end if;

  if p_tipo = 'aplicar' then
    if d ? 'pergunta_id' then
      v_r := public.agenda_decidir((d ->> 'pergunta_id')::uuid, (d ->> 'opcao')::smallint, p_autor, p_canal, p_trecho, p_hoje, p_agora);
    else
      v_r := public.agenda_aplicar((d ->> 'proposta_id')::uuid,
                                   case when jsonb_typeof(d -> 'os_ids') = 'array'
                                        then array(select x::uuid from jsonb_array_elements_text(d -> 'os_ids') x) end,
                                   'dono', p_autor, null, p_hoje, p_agora);
    end if;
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    -- (o "Feito: " da decisão sobra depois do "Gravado. Agora:")
    return regexp_replace(v_r ->> 'texto', '^Feito: ', '');
  end if;

  if p_tipo = 'desfazer' then
    for v_x in select x from jsonb_array_elements_text(coalesce(d -> 'acao_ids', '[]'::jsonb)) x loop
      v_r := public.agenda_desfazer(v_x::uuid, p_autor, 'dono', p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para desfazer');
      end if;
      v_txts := v_txts || (v_r ->> 'texto');
    end loop;
    return array_to_string(v_txts, ' ');
  end if;

  if p_tipo = 'andamento' then
    if d ->> 'evento' in ('trabalhou', 'parcial', 'nao_foi') then
      v_r := public.agenda_registrar_dia(p_autor, (d ->> 'dia')::date, d ->> 'resultado', d ->> 'motivo', v_os,
                                         case when jsonb_typeof(d -> 'pessoas') = 'array'
                                              then array(select x::uuid from jsonb_array_elements_text(d -> 'pessoas') x) end,
                                         'conversa', p_trecho, p_hoje, p_agora, p_canal);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para anotar o dia');
      end if;
      return v_r ->> 'texto';
    end if;
    if d ->> 'evento' = 'comecou' then
      v_r := public.os_transicionar_status(v_os, 'in_progress', 'dono', null, p_autor, (d ->> 'check_in')::timestamptz, p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para marcar o início');
      end if;
      return v_r ->> 'texto';
    end if;
    if d ->> 'evento' = 'parou' then
      v_r := public.os_transicionar_status(v_os, d ->> 'status_para', 'dono',
                                           'parou (' || public._agenda_motivo_texto(d ->> 'motivo') || ')', p_autor, null, p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false)
         or (select so.status from public.service_orders so where so.id = v_os) <> d ->> 'status_para' then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para parar a OS');
      end if;
      -- sai da agenda o que ainda não começou (foi o dono que disse: sem desfazer)
      perform set_config('agenda.hoje', p_hoje::text, true);
      perform pg_advisory_xact_lock(hashtext('agenda_plano'));
      select coalesce(array_agg(a.id order by a.dia, a.turno = 'tarde', a.payee_id, a.id), '{}'),
             coalesce(jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno,
                                                   'presenca', a.presenca, 'tipo', a.tipo, 'estado', a.estado)
                                order by a.dia, a.turno = 'tarde', a.payee_id, a.id), '[]'::jsonb),
             coalesce(array_agg(distinct a.dia), '{}')
        into v_canc, v_antes, v_dias
        from public.agenda_alocacoes a
       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.resultado is null and lower(a.periodo) > p_agora;
      foreach v_id in array v_canc loop
        if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
          perform set_config('agenda.mexe_fixado', 'on', true);
        end if;
        update public.agenda_alocacoes
           set estado = 'cancelada', cancelada_motivo = case when d ->> 'motivo' = 'material' then 'material' else 'cliente' end
         where id = v_id;
        perform set_config('agenda.mexe_fixado', 'off', true);
      end loop;
      v_txt := v_r ->> 'texto';
      if cardinality(v_canc) > 0 then
        v_txt := v_txt || format(' Tirei da agenda %s.', public._agenda_dias_texto(v_dias));
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas,
                                         status_antes, status_depois, antes, depois, texto, motivo, autor)
        values (clock_timestamp(), p_hoje, true, 'dono', 'cancelar', v_os, array[v_os], v_canc,
                v_r ->> 'de', v_r ->> 'para', jsonb_build_object('alocacoes', v_antes),
                jsonb_build_object('alocacoes', '[]'::jsonb, 'motivo', d ->> 'motivo'),
                left(format('%s: sai da agenda %s — parou (%s).', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias),
                            public._agenda_motivo_texto(d ->> 'motivo')), 400),
                d ->> 'motivo', p_autor);
      end if;
      perform public._agenda_espelhar_datas(v_os, p_hoje);
      return v_txt;
    end if;
  end if;
  raise exception '_agenda_aplicar_pedido: tipo "%" / evento "%" desconhecido', p_tipo, d ->> 'evento' using errcode = '22023';
end;
$function$;

comment on function public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): o que o *grava* faz com uma linha de pedido — marcar → agenda_marcar_os (via dono; a agenda tem de pôr a OS nos dias da releitura); aplicar → agenda_aplicar (via dono) ou agenda_decidir (respondida_via = o canal); desfazer → agenda_desfazer de cada ação; andamento → agenda_registrar_dia (via conversa), a porta (começou: em andamento com o início da releitura; parou: aguardando, com o motivo, e sai da agenda o que não começou, ação cancelar). Qualquer recusa = exceção P0097 com a frase dela (o lote inteiro volta). Devolve a frase do que foi feito. Só pelo agenda_rascunho_gravar; só service_role.';

-- ── 7. O *grava* ─────────────────────────────────────────────────────────────────────────────────────────
-- Corpo de 20261024160600 copiado; as mudanças estão marcadas "-- FASE 2:".

create or replace function public.agenda_rascunho_gravar(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_exp     int;
  v_exp_dia date;
  v_ids     uuid[];
  v_oss_mat uuid[];
  v_r       public.agenda_rascunho%rowtype;
  v_x       uuid;
  v_n       int := 0;
  v_item    text;
  v_estado  text;
  v_msg     text;
  v_linhas  text[] := '{}';
  v_g       record;
  v_p       jsonb;
  v_nome    int;
  -- FASE 2: a hora do *grava* (now(); a bancada fixa com set_config('agenda.agora', …, true), como agenda.hoje), a
  -- config, as frases do que a agenda fez com os pedidos e o tipo de cada linha.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  cf        public.agenda_config := public._agenda_cfg();
  v_f2      text[] := '{}';
  v_f2_item text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  -- FASE 2: primeiro os fatos (Fase 1), depois o andamento, marcar, publicar/decidir e desfazer — cada grupo na ordem em
  -- que o dono falou.
  select coalesce(array_agg(r.id order by case r.tipo when 'andamento' then 1 when 'marcar' then 2 when 'aplicar' then 3
                                                      when 'desfazer' then 4 else 0 end,
                                          (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- FASE 2: com a agenda automática fora de 'ligado', o pedido à agenda não grava — e o lote é tudo ou nada.
  if cf.modo_proposta <> 'ligado'
     and exists (select 1 from public.agenda_rascunho r where r.id = any (v_ids) and r.tipo in ('marcar', 'aplicar', 'desfazer', 'andamento')) then
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'motivo', 'em_teste',
      'texto', 'Não gravei nada: a agenda automática ainda está em teste e o que você pediu mexe na agenda. Mande *descarta* e me diga de novo o resto.');
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca, UMA vez antes de entrar o lote, só o que ele realmente troca:
    --   · "vem" (seg a qui): as linhas de padrão dela (do histórico e do dono) que caem em algum desses dias; os
    --     outros dias da semana continuam como estavam;
    --   · "só de manhã", "só à tarde", "não vem" (terça): o "vem" fica; a linha indisponível do turno entra por cima
    --     (a capacidade põe o "não vem neste turno" acima do padrão "vem"). Só sai a restrição que o dono já tinha
    --     dito para os mesmos dias ("só à tarde às terças" e depois "só de manhã às terças").
    update public.agenda_disponibilidade a
       set substituida_em = now()
      from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                   array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
              from public.agenda_rascunho r
             where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
     where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
       and ((n.situacao = 'disponivel' and a.origem in ('historico', 'dono') and a.dias_semana && n.dias)
            or (n.situacao = 'indisponivel' and a.origem = 'dono' and a.situacao = 'indisponivel'
                and a.dias_semana <@ n.dias));

    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'disponibilidade' then
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
        else
          -- FASE 2: o pedido à agenda (marcar, aplicar/decidir, desfazer, andamento) pelas funções do motor.
          v_f2_item := public._agenda_aplicar_pedido(v_autor, v_r.tipo, v_r.service_order_id, v_r.dados, v_r.trecho, v_r.canal,
                                                     p_hoje, v_agora);
          if nullif(btrim(coalesce(v_f2_item, '')), '') is not null then
            v_f2 := v_f2 || v_f2_item;
          end if;
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    -- FASE 2: a agenda recusou um pedido (a proposta ficou velha, a decisão mudou, não coube, já começou…).
    if v_estado = 'P0097' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', format('Não gravei nada. A agenda mudou desde a releitura: %s. Me peça de novo.', rtrim(btrim(v_msg), '.')));
    end if;
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
      'texto', format('Não gravei nada: %s (%s). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.',
                      case when v_estado = 'P0001' then v_msg else 'o banco recusou um item' end,
                      coalesce(v_item, 'o lote')));
  end;

  -- "Gravado. Agora:" — uma linha por OS (o estado da prontidão) e por pessoa, na ordem em que o dono falou.
  for v_g in
    select r.dados ->> 'grupo' as grupo, min((r.dados ->> 'ordem')::int) as ordem,
           (array_agg(r.service_order_id order by (r.dados ->> 'ordem')::int))[1] as os,
           (array_agg(r.dados order by (r.dados ->> 'ordem')::int))[1] as d,
           string_agg(r.dados ->> 'frase', '; ' order by (r.dados ->> 'ordem')::int) as frases
      from public.agenda_rascunho r
     where r.id = any (v_ids) and r.tipo in ('planejar', 'material', 'disponibilidade')   -- FASE 2: os pedidos vêm em v_f2
     group by r.dados ->> 'grupo'
     order by 2
  loop
    if v_g.os is not null then
      v_p := public.os_prontidao(v_g.os, p_hoje);
      select count(*) into v_nome from public.os_carteira(p_hoje) k where k.cliente_curto = v_p ->> 'cliente_curto';
      v_linhas := v_linhas || ('• ' || public._agenda_rotulo(jsonb_build_object(
                                 'curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero',
                                 'eh_orc', (v_p ->> 'eh_orcamento')::boolean, 'n_nome', v_nome))
                               || ': ' || (v_p ->> 'estado_texto') || '.');
    else
      v_linhas := v_linhas || ('• ' || (v_g.d ->> 'rotulo_grupo') || ': ' || v_g.frases || '.');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava. Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo.';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- Os pedidos e a simulação: security definer, conferem o administrador (_autor_da_agenda); authenticated (painel) e
-- service_role (WhatsApp). Nunca anon. As recriadas da Fase 1 mantêm as portas de 160600 (create or replace não muda a
-- ACL); repetidas aqui para a migration valer sozinha.
revoke all on function
  public.agenda_rascunho_marcar(uuid, text, text, text, text, text, text, date, timestamptz),
  public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz),
  public.agenda_rascunho_desfazer(uuid, text, text, text, date, timestamptz),
  public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz),
  public.agenda_propor_dito(uuid, text, text, text[], jsonb, text[], jsonb, boolean, boolean, date, timestamptz, text),
  public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date), public.agenda_rascunho_gravar(uuid, date)
  from public, anon;
grant execute on function
  public.agenda_rascunho_marcar(uuid, text, text, text, text, text, text, date, timestamptz),
  public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz),
  public.agenda_rascunho_desfazer(uuid, text, text, text, date, timestamptz),
  public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz),
  public.agenda_propor_dito(uuid, text, text, text[], jsonb, text[], jsonb, boolean, boolean, date, timestamptz, text),
  public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date), public.agenda_rascunho_gravar(uuid, date)
  to authenticated, service_role;

-- A numeração (leitura, como as da Fase 1): authenticated e service_role.
revoke all on function public.agenda_decisoes_abertas(timestamptz), public.agenda_propostas_abertas(timestamptz) from public, anon;
grant execute on function public.agenda_decisoes_abertas(timestamptz), public.agenda_propostas_abertas(timestamptz)
  to authenticated, service_role;

-- As internas: só service_role (as RPCs acima as chamam como dono das funções).
revoke all on function
  public._agenda_pedido_recusa(text, text, text), public._agenda_frase_do_encaixe(jsonb, uuid),
  public._agenda_nao_cabe(jsonb, uuid, date, uuid, date, timestamptz, boolean),
  public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz),
  public._agenda_rascunho_frase(text, jsonb), public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)
  from public, anon, authenticated;
grant execute on function
  public._agenda_pedido_recusa(text, text, text), public._agenda_frase_do_encaixe(jsonb, uuid),
  public._agenda_nao_cabe(jsonb, uuid, date, uuid, date, timestamptz, boolean),
  public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz),
  public._agenda_rascunho_frase(text, jsonb), public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)
  to service_role;
