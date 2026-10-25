-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P7a: as telas — Agenda › Semana,
-- Agenda › Carteira, o cartão "Plano" da OS, as linhas da grade como a equipe (payees) e a lista rápida de status e os
-- kanbans sem as opções que a porta recusa.
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§10; §3.3 d19, d23, d24). Notas entre pacotes: notas-fase3.md ("Divisão do
-- P7" e "Decisões do coordenador depois do P3": a lista rápida e os kanbans escondem o que a porta recusa, pela MESMA regra
-- da porta — uma função só, nunca uma lista copiada na tela).
-- Depende das Fases 1 e 2 inteiras e de 20261026100000 a 20261026100500 (a porta completa de 100100, os marcos, a diária
-- de 100300, o PPC e o livre de verdade de 100500).
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas e a porta recriada; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: as três telas de celular da Fase 3 (plano §7) leem o banco pronto — o texto, a cor da carga e a idade saem
-- daqui com os limiares de agenda_config, e o TypeScript não tem número. E a lista rápida de status e os kanbans ofereciam
-- opções que a porta recusa ("Corrigir para Orçamento", "aguardando o cliente → aberta", concluir para quem não pode,
-- faturar e reabrir para quem não é administrador): o dono clicava e lia a recusa. Agora a tela pergunta à porta antes.
--
-- O QUE MUDA:
--   1. _os_porta_regra(de, para, via, gestor, técnico da OS, vendedor, com autor, com motivo, agenda ligada): a parte da
--      porta que só depende do cargo, do status de agora, do pedido, do caminho e do modo da agenda automática (que a porta e
--      a tela passam) — o tipo do pedido (conversão, conclusão, encerrada,
--      agenda), quem pode (42501 com a frase de sempre) e as passagens recusadas sem olhar dado (cancelada, faturada,
--      cancelar, concluída, orçamento sem converter, voltar a orçamento, faturar antes de concluir, "já está", a OS que já
--      começou, a agendada pela tela, o cliente que não liberou), com a frase em modelo (1 = número, 2 = nome, 3 = status de
--      agora, 4 = pedido). IMMUTABLE, sem dado. É a ÚNICA fonte dessas regras.
--   2. os_transicionar_status recriada (corpo de 20261026100100, a definição mais nova; as mudanças marcadas
--      "-- FASE 3 (P7a):"): lê _os_porta_regra no lugar das regras que estavam no corpo. O resultado é o mesmo, frase a
--      frase (as provas das Fases 2 e 3 continuam passando); o que depende de dado (o material, o dia no plano, o início que
--      falta, as cobranças, o número da conversão) continua na porta.
--   3. os_status_da_tela(OS[]): para o login, por OS, os status que a porta aceita pela tela (via 'tela') — lendo a MESMA
--      _os_porta_regra (o orçamento: a conversão e depois aprovada → o pedido, como a porta faz). A tela esconde o resto.
--      O que depende de dado não entra (a porta decide na hora e diz por quê).
--   4. As leituras das telas (admin/financeiro; senão 42501; STABLE, definer com search_path fixo):
--        · agenda_tela_semana(de, hoje, agora): a semana dia a dia — a carga por pessoa (meios-dias usados × esperados,
--          a cor pela carga_max), os blocos ("OS · cliente · bem · pessoas · dia n de N · o cliente confirmou"), a
--          reserva "a confirmar", "livre: Roberto tarde", o que o gestor mudou sozinho (com o desfazer), as decisões
--          críticas abertas, o quanto da semana passada foi cumprido e, em ligado, o livre de verdade. Em sombra: a última semana
--          montada pela sombra ("Em teste: eu montaria assim");
--        · agenda_tela_carteira(hoje): o quadro de exceções por estado (9 grupos com o número), cada cartão com a idade em
--          dias úteis e a cor (carteira_laranja_du / carteira_vermelho_du sem data), a próxima ação e quem trava;
--        · os_plano_da_os(OS, hoje): o cartão "Plano" — os 4 marcos, a duração com a fonte e a faixa, a presença do dono,
--          o material por linha com o nível A–E e o trecho, a janela do bem, prometido × planejado, planejado × realizado
--          (a diária só "lançada"/"a confirmar", nunca o valor) e as intervenções do dono;
--        · agenda_equipe_da_grade(hoje): as linhas da grade técnico × dia como a equipe da agenda (o dono e quem tem perfil
--          de diária e padrão, a regra da Fase 1), com o login para casar com a OS e a tarefa.
--   5. As escritas da tela (é a ordem exata do dono; só o administrador, pelo _autor_da_agenda):
--        · os_planejar_pela_tela(OS, dias): a duração dita pelo dono (meio em meio dia), pelo mesmo caminho do *grava*
--          (_agenda_aplicar_planejar: o histórico guarda o antes e o depois);
--        · agenda_desfazer_pela_tela(ação): agenda_desfazer (via 'tela'); a publicação da semana desfaz tudo ou nada.
--      O botão Entregue chama os_registrar_marco(OS, 'entrega', 'tela') (já existe, P2).
--
-- REVISÃO DA FASE 3 (C2, 25/10; o arquivo ainda não foi aplicado em lugar nenhum, então foi editado na origem):
--   · R2: a tela (o administrador, o financeiro, o técnico da OS) passa a OS em andamento a aguardando peças ou o cliente
--     COM o motivo (a janela "Parar a OS" pede antes de chamar a porta); sem o motivo, a porta devolve pede_motivo.
--     os_status_da_tela diz quais passagens pedem o motivo ("<id>:motivo"). Em andamento → aberta continua proibido, e a
--     frase diz o caminho certo. Agendada → aberta/aprovada pela tela: o administrador ou o financeiro, com a agenda
--     automática fora de ligado (a regra recebe o modo: p_agenda_ligada).
--   · R3: agenda_modo_da_proposta() — o modo para qualquer login (agenda_config é fechada ao técnico e ao vendedor).
--   · R6: com login, a porta recusa as vias motor, vigia, equipe e assinatura; dono e conferência só admin/financeiro.
--   · Item 5: a tela Semana relê o texto de ontem com o ajudante único _agenda_vence_no_dia (20261026100500).
--   · Item 6: a assinatura do cliente libera a OS que aguardava o cliente (antes da Fase 3 ela a punha em aprovada).
--   · "PPC" é jargão: o resumo da Semana diz "semana passada: 5 de 6 dias cumpridos".
--
-- CORREÇÕES SOBRE A SPEC:
--   · agenda_desfazer não ganha a via 'tela' por recriação: ela não confere a via (só a usa para a origem do registro,
--     que fica 'dono' — é a ordem do dono). agenda_desfazer_pela_tela passa 'tela' e confere o administrador antes.
--   · "Concluídas e não entregues" na Carteira são as concluídas PELA PORTA (ação concluir) sem a entrega: as 21 OS
--     concluídas antes da Fase 3 não têm delivered_at porque a coluna é nova, não porque não foram entregues.
--   · A carga do dia por pessoa: meios-dias usados (qualquer presença, como a grade do motor) sobre os esperados do dia
--     (a soma das frequências da agenda_capacidade, arredondada ao meio-dia inteiro); esperado zero com uso = vermelho.
--
-- RISCO REGISTRADO: o P7b (D11 na porta, NOVO-agenda-24) recria a porta de novo: copia o corpo DESTA migration.
--
-- O QUE NÃO MUDA: nenhum dado é escrito; nenhuma tabela, coluna, CHECK ou policy; as leituras das Fases 1 e 2; a régua de
-- quem pode e as frases da porta (só mudaram de lugar).
--
-- ORDEM DE LIGAR: depois de 20261026100500.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_telas.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100600
-- APLICAR (só com o OK nomeado do dono):
--   npx supabase db query --linked -f supabase/migrations/20261026100600_agenda_fase3_telas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100600', 'agenda_fase3_telas');"
--
-- IDEMPOTENTE: create or replace function; revoke/grant e comment.

-- ── 1. A regra da porta que a tela também lê ────────────────────────────────────────────────────────────

-- O tipo do pedido, quem pode e as passagens que a porta recusa sem olhar dado. {tipo, recusa (null | quem | passagem),
-- texto, fica}: recusa 'quem' = 42501 com a frase; 'passagem' = nada muda, com fica (o ok da porta: true = era o esperado,
-- false = recusado) e a frase em modelo do format (1 = o número, 2 = o nome, 3 = o status de agora, 4 = o pedido); null =
-- segue (o resto depende de dado e é da porta).
create or replace function public._os_porta_regra(p_de text, p_para text, p_via text, p_gestor boolean, p_tecnico boolean,
                                                  p_vendedor boolean, p_com_autor boolean, p_com_motivo boolean default false,
                                                  p_agenda_ligada boolean default false)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_tipo text;
  v_quem text;
begin
  v_tipo := case
    when p_de = 'draft' and p_para not in ('draft', 'cancelled')
         and p_via in ('tela', 'assistente', 'dono', 'aprovacao', 'assinatura') then 'conversao'
    when p_de not in ('draft', 'completed', 'invoiced', 'cancelled') and p_para = 'completed' then 'concluir'
    when p_de = 'completed' and p_para not in ('completed', 'cancelled')
         and ((p_para = 'invoiced' and p_via in ('tela', 'assistente', 'dono'))
              or (p_para in ('in_progress', 'awaiting_parts', 'awaiting_client') and p_via in ('tela', 'dono'))
              or p_via = 'desfazer') then 'encerrada'
    else 'agenda' end;

  -- Quem pode (a régua da Fase 3, §5.3): status de agenda = admin/financeiro, técnico da OS, vendedor pela tela; converter =
  -- admin/financeiro, vendedor (tela, assistente), a assinatura; concluir = admin/financeiro, técnico da OS, a assinatura, o
  -- gestor (equipe); faturar, reabrir e desfazer a conclusão = admin/financeiro. Sem autor (motor, vigia, equipe,
  -- assinatura), os cargos vêm falsos.
  v_quem := case
    when v_tipo = 'agenda' and p_com_autor and not (p_gestor or p_tecnico or (p_vendedor and p_via = 'tela'))
      then 'Você não pode mudar o status desta OS.'
    when v_tipo = 'conversao'
         and not (p_gestor or (p_vendedor and p_via in ('tela', 'assistente')) or (not p_com_autor and p_via = 'assinatura'))
      then 'Converter orçamento em OS é com o administrador ou o vendedor.'
    when v_tipo = 'concluir' and not (p_gestor or p_tecnico or (not p_com_autor and p_via in ('equipe', 'assinatura')))
      then 'Concluir é com o administrador ou o técnico da OS.'
    when v_tipo = 'encerrada' and not p_gestor
      then 'Faturar e reabrir são com o administrador.'
    end;
  if v_quem is not null then
    return jsonb_build_object('tipo', v_tipo, 'recusa', 'quem', 'texto', v_quem);
  end if;

  -- As passagens que não dependem de dado, na ordem da porta.
  return jsonb_build_object('tipo', v_tipo) || coalesce(case
    when p_de = 'cancelled'
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'A %1$s está cancelada: a agenda não muda o status dela.')
    when p_de = 'invoiced' and p_para = 'invoiced'
      then jsonb_build_object('recusa', 'passagem', 'fica', true, 'texto', '%2$s já está faturada.')
    when p_de = 'invoiced'
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'A %1$s está faturada: reabrir é pelo financeiro.')
    when p_para = 'cancelled'
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'Cancelar é pelo botão Cancelar OS.')
    when p_de = 'completed' and p_para = 'completed'
      then jsonb_build_object('recusa', 'passagem', 'fica', true, 'texto', '%2$s já está concluída.')
    when p_de = 'completed' and v_tipo <> 'encerrada'
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'A %1$s está concluída: a agenda não muda o status dela.')
    when p_de = 'completed'
      then null   -- faturar, reabrir ou desfazer: a porta segue
    when p_de = 'draft' and v_tipo <> 'conversao'
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'Isso ainda é orçamento: converta antes.')
    when p_de = 'draft'
      then null   -- a conversão (o número é dado); depois, a regra de aprovada → o pedido
    when p_para = 'draft'
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'Uma OS não volta a ser orçamento pela agenda.')
    when p_para = 'invoiced'
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'Fature depois de concluir.')
    when p_para = 'completed'
      then null   -- a conclusão (as cobranças são dado)
    when p_para = p_de and p_de <> 'in_progress'
      then jsonb_build_object('recusa', 'passagem', 'fica', true, 'texto', '%2$s já está %3$s.')
    when p_para = p_de
      then null   -- em andamento: o início que falta é dado
    when p_para = 'scheduled' and p_de = 'in_progress'
      then jsonb_build_object('recusa', 'passagem', 'fica', true, 'texto', 'A OS já começou: não volta para agendada.')
    -- Revisão da Fase 3 (item 6): a assinatura do cliente também libera (é o cliente dizendo que sim).
    when p_para = 'scheduled' and p_de = 'awaiting_client' and p_via not in ('dono', 'tela_agendar', 'aprovacao', 'assinatura')
      then jsonb_build_object('recusa', 'passagem', 'fica', true, 'texto', 'O cliente ainda não liberou: a OS continua aguardando o cliente.')
    when p_para in ('awaiting_parts', 'awaiting_client') and p_de = 'in_progress' and p_via = 'oc'
      then jsonb_build_object('recusa', 'passagem', 'fica', true, 'texto', 'A OS segue em andamento; a compra foi registrada.')
    -- Revisão da Fase 3 (R2): a OS que já começou volta a aguardar só com o motivo — pelo dono (a conversa, as palavras) ou
    -- pela tela (o administrador, o financeiro ou o técnico da OS; a tela abre a janela do motivo antes de chamar a porta).
    -- pede_motivo = só faltou o motivo: a tela oferece a passagem e pergunta (os_status_da_tela).
    when p_para in ('awaiting_parts', 'awaiting_client') and p_de = 'in_progress'
         and not (p_com_motivo and (p_via = 'dono' or (p_via = 'tela' and (p_gestor or p_tecnico))))
      then jsonb_build_object('recusa', 'passagem', 'fica', false,
                              'pede_motivo', not p_com_motivo and (p_via = 'dono' or (p_via = 'tela' and (p_gestor or p_tecnico))),
                              'texto', 'A OS já começou: só volta a aguardar quando você diz que parou e por quê.')
    -- Revisão da Fase 3 (R2): nunca regride; a frase diz o caminho certo.
    when p_para in ('open', 'approved') and p_de = 'in_progress'
      then jsonb_build_object('recusa', 'passagem', 'fica', true,
                              'texto', 'A OS já começou: não volta para %4$s. Se ela parou, passe para aguardando peças ou aguardando o cliente e diga o motivo.')
    -- Revisão da Fase 3 (R2): pela tela, o administrador ou o financeiro tira a OS de agendada só com a agenda automática
    -- fora de ligado (aí a data é dele; em ligado, quem marca é a agenda: desmarque o dia).
    when p_para in ('open', 'approved') and p_de = 'scheduled' and p_via not in ('motor', 'vigia', 'desfazer', 'dono')
         and not (p_via = 'tela' and p_gestor and not p_agenda_ligada)
      then jsonb_build_object('recusa', 'passagem', 'fica', false, 'texto', 'A OS está agendada: para tirar da agenda, desmarque o dia.')
    when p_para in ('open', 'approved') and p_de = 'awaiting_client' and p_via not in ('dono', 'tela_agendar', 'aprovacao', 'assinatura')
      then jsonb_build_object('recusa', 'passagem', 'fica', true, 'texto', 'O cliente ainda não liberou: a OS continua aguardando o cliente.')
    end, jsonb_build_object('recusa', null));
end;
$function$;

comment on function public._os_porta_regra(text, text, text, boolean, boolean, boolean, boolean, boolean, boolean) is
  'Agenda de Produção (Fase 3, P7a; revisão da Fase 3: R2 e item 6): a parte da porta única (os_transicionar_status) que só depende do cargo, do status de agora, do pedido, do caminho e do modo da agenda automática (p_agenda_ligada, que quem chama passa) — {tipo (conversao|concluir|encerrada|agenda), recusa (null | quem: 42501 com a frase | passagem: nada muda, com fica = o ok da porta), pede_motivo (true = só faltou o motivo: em andamento → aguardando pelo dono ou pela tela), texto (a frase; na passagem, modelo do format: 1 = número, 2 = nome, 3 = status de agora, 4 = pedido)}. Em andamento → aguardando com o motivo: pelo dono ou pela tela (admin/financeiro, técnico da OS); agendada → aberta/aprovada pela tela: admin/financeiro com a agenda fora de ligado; a assinatura libera a OS que aguardava o cliente. A porta e a tela (os_status_da_tela) leem a MESMA função: a lista rápida e os kanbans escondem o que ela recusa. IMMUTABLE, sem dado; o que depende de dado (o material, o dia no plano, o início que falta, as cobranças, o número da conversão) é da porta. Sem grant: só as funções definer a chamam.';

-- ── 2. A porta, lendo a regra (corpo de 20261026100100; as mudanças marcadas "-- FASE 3 (P7a):") ──────────

create or replace function public.os_transicionar_status(
  p_os        uuid,
  p_para      text,
  p_via       text,
  p_motivo    text        default null,
  p_autor     uuid        default null,
  p_check_in  timestamptz default null,
  p_hoje      date        default public._hoje_brt(),
  p_agora     timestamptz default now(),
  p_check_out timestamptz default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config;
  v_uid    uuid := auth.uid();
  v_papel  text;
  v_autor  uuid;
  v_os     record;
  v_de     text;
  v_para   text := p_para;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_nome   text;
  v_check  timestamptz;
  v_novo_check boolean := false;
  v_falta  text;
  v_antes  text;
  v_texto  text;
  v_origem text;
  v_acao   uuid;
  -- FASE 3: quem pode, a conversão, a conclusão e o desfazer dela.
  v_tipo      text;
  v_gestor    boolean := false;
  v_tecnico   boolean := false;
  v_vendedor  boolean := false;
  v_num_novo  text;
  v_acao_conv uuid;
  v_r         jsonb;
  v_conc      public.agenda_acoes%rowtype;
  v_saida     timestamptz;
  v_venc      jsonb;
  v_venc_cob  jsonb;
  v_com_antes uuid[];
  v_coms      uuid[];
  v_rec       jsonb;
  v_ids       uuid[];
  v_erro      text;
  v_cob       text;
  v_venc_dia  date;
  v_venc_soma numeric;
  -- FASE 3: fim
  -- FASE 3 (P7a): a regra que só depende do cargo, do status, do pedido e do caminho (_os_porta_regra).
  v_regra     jsonb;
begin
  if p_via is null or p_via not in ('tela_agendar', 'aprovacao', 'assistente', 'check_in', 'oc', 'motor', 'vigia',
                                    'conferencia', 'dono', 'desfazer',
                                    -- FASE 3: a tela (a mudança genérica de status), a assinatura do cliente e o gestor
                                    -- pela palavra do técnico.
                                    'tela', 'assinatura', 'equipe') then
    raise exception 'Caminho desconhecido para mudar o status: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_para is null or p_para not in ('draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client',
                                      'approved', 'completed', 'invoiced', 'cancelled') then
    raise exception 'Status desconhecido: "%".', coalesce(p_para, '') using errcode = '22023';
  end if;
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam a OS, o dia ou a hora para mudar o status.' using errcode = '22023';
  end if;

  perform set_config('agenda.hoje', p_hoje::text, true);
  c := public._agenda_cfg();

  select so.id, so.service_order_number as numero, so.status, so.check_in_at, cl.name as cliente,
         -- FASE 3: o que a conclusão, a entrega e a conversão leem.
         so.check_out_at, so.delivered_at, so.converted_to_os_at, so.grand_total, so.original_quote_amount
    into v_os
    from public.service_orders so
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os
     for update of so;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  -- Quem pede: com login, o próprio login; sem login (service role, o próprio banco), p_autor — motor e vigia podem
  -- vir sem. Um JWT de outro papel sem login não ganha o direito de dizer quem é.
  if v_uid is not null then
    -- FASE 3: a assinatura do cliente vem só pela service_role (submit-signature), nunca com login. Revisão da Fase 3 (R6):
    -- com login, quem chama não escolhe a via — o motor, a vigia e o gestor (equipe) também são só do banco, e o dono e a
    -- conferência, só do administrador ou do financeiro.
    if p_via in ('assinatura', 'equipe', 'motor', 'vigia')
       or (p_via in ('dono', 'conferencia') and not public.is_admin_or_financial(v_uid)) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    v_autor := v_uid;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    -- FASE 3: além do motor e da vigia, o gestor (equipe) e a assinatura do cliente vêm sem autor.
    if v_papel not in ('', 'service_role') or (p_autor is null and p_via not in ('motor', 'vigia', 'equipe', 'assinatura')) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    -- FASE 3: a assinatura é do cliente: nunca tem autor.
    v_autor := case when p_via = 'assinatura' then null else p_autor end;
  end if;

  -- FASE 3: quem pode muda com o que se pede (spec-fase3 §5.3). A régua da Fase 2 (admin/financeiro ativo ou técnico ativo
  -- da OS, com a mesma frase) continua para o status de agenda, e o vendedor ativo entra nela pela tela; converter,
  -- concluir, faturar e reabrir têm a régua e a frase delas.
  if v_autor is not null then
    v_gestor   := public.is_admin_or_financial(v_autor);
    v_tecnico  := exists (select 1 from public.service_order_technicians t
                            join public.app_users u on u.id = t.user_id
                           where t.service_order_id = p_os and t.user_id = v_autor and u.active);
    v_vendedor := exists (select 1 from public.app_users u where u.id = v_autor and u.active and u.role = 'seller');
  end if;
  -- FASE 3 (P7a): o tipo do pedido, quem pode e as passagens que não dependem de dado vêm de _os_porta_regra — a mesma
  -- função que a tela (os_status_da_tela) lê para esconder da lista rápida e dos kanbans o que a porta recusa.
  v_regra := public._os_porta_regra(v_os.status, v_para, p_via, v_gestor, v_tecnico, v_vendedor, v_autor is not null,
                                    v_motivo is not null, c.modo_proposta = 'ligado');
  v_tipo := v_regra ->> 'tipo';
  if v_regra ->> 'recusa' = 'quem' then
    raise exception '%', v_regra ->> 'texto' using errcode = '42501';
  end if;
  -- FASE 3 (P7a): fim
  -- FASE 3: a origem de cada caminho (estava depois da escrita; a conclusão e a conversão também a usam).
  v_origem := case p_via
    when 'tela_agendar' then 'tela'
    when 'check_in'     then 'sistema'
    when 'oc'           then 'sistema'
    when 'desfazer'     then 'dono'
    when 'assinatura'   then 'sistema'
    else p_via end;
  -- FASE 3: fim

  v_de   := v_os.status;
  v_nome := coalesce(public._agenda_nome_curto(v_os.cliente) || ' (' || v_os.numero || ')', v_os.numero);

  -- FASE 3 (P7a): cancelada, faturada, cancelar, concluída, orçamento sem converter, voltar a orçamento, faturar antes de
  -- concluir, "já está", a OS que já começou, a agendada pela tela e o cliente que não liberou: a frase de _os_porta_regra
  -- (1 = o número, 2 = o nome, 3 = o status de agora, 4 = o pedido).
  if v_regra ->> 'recusa' = 'passagem' then
    return public._agenda_porta_fica((v_regra ->> 'fica')::boolean, v_de,
      format(v_regra ->> 'texto', v_os.numero, v_nome, public._agenda_status_texto(v_de), public._agenda_status_texto(v_para)))
      -- Revisão da Fase 3 (R2): só faltou o motivo (em andamento → aguardando, pelo dono ou pela tela): quem chama pede.
      || case when coalesce((v_regra ->> 'pede_motivo')::boolean, false) then jsonb_build_object('pede_motivo', true)
              else '{}'::jsonb end;
  end if;
  -- FASE 3 (P7a): fim

  -- FASE 3: encerrada, faturada, cancelada e orçamento. A Fase 2 recusava tudo aqui ("concluir é pela tela"); agora a
  -- conclusão, o faturamento, a reabertura e a conversão são da porta. Cancelar continua no botão Cancelar OS.
  -- FASE 3 (P7a): cancelada, faturada, cancelar e concluída sem ser faturar/reabrir/desfazer saíram para _os_porta_regra.
  if v_de = 'completed' then

    -- O desfazer da conclusão (só de dentro do agenda_desfazer, que diz qual ação desfaz em agenda.desfaz_conclusao):
    -- volta ao status de antes, e a saída sai se foi a conclusão que a gravou.
    if p_via = 'desfazer' then
      select a.* into v_conc
        from public.agenda_acoes a
       where a.id::text = coalesce(current_setting('agenda.desfaz_conclusao', true), '')
         and a.service_order_id = p_os and a.tipo = 'concluir' and a.executada and a.desfeita_em is null;
      if not found or v_conc.status_antes is distinct from v_para then
        return public._agenda_porta_fica(false, v_de,
          'Desfazer a conclusão é pelo *desfaz* da agenda; para reabrir, use a tela da OS.');
      end if;
      perform public._agenda_escrever_conclusao(p_os, v_para, null, (v_conc.antes ->> 'check_out_at') is null, null, null);
      v_texto := format('%s: de concluída para %s (desfeito).', v_nome, public._agenda_status_texto(v_para));
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
              jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at),
              jsonb_build_object('status', v_para, 'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os),
                                 'via', p_via, 'desfaz_conclusao', v_conc.id),
              left(v_texto, 400), v_autor)
      returning id into v_acao;
      return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                                'acao_id', v_acao, 'check_in_at', v_os.check_in_at,
                                'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os));
    end if;

    if v_para = 'invoiced' then
      perform public._agenda_escrever_os(p_os, 'invoiced', null, null, null, false);
      v_texto := format('%s: faturada.', v_nome);
    else
      -- Reabrir (paridade com a tela: a saída e as cobranças ficam; o início, se faltava, como no "em andamento").
      if v_para = 'in_progress' and v_os.check_in_at is null then
        v_check := coalesce(p_check_in, p_agora);
        v_novo_check := true;
      end if;
      perform public._agenda_escrever_os(p_os, v_para, v_check, null, null, false);
      v_texto := format('Reabri o %s', v_nome)
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.status <> 'cancelled')
                then '. As cobranças da conclusão continuam; se for o caso, ajuste no financeiro.'
                else ' (agora está ' || public._agenda_status_texto(v_para) || ').' end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor)
    values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
            jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at, 'check_out_at', v_os.check_out_at),
            jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
            left(v_texto, 400), left(v_motivo, 200), v_autor)
    returning id into v_acao;
    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check),
                              'check_out_at', v_os.check_out_at);
  end if;

  if v_de = 'draft' then
    -- FASE 3 (P7a): o orçamento sem conversão saiu para _os_porta_regra.
    -- A conversão: o número troca SÓ o prefixo (ORÇ-00119 → OS-00119), converted_to_os_at e original_quote_amount uma vez;
    -- depois, na mesma chamada, a regra de aprovada → X. Se o passo X recusar, a conversão também não fica.
    v_num_novo := case when v_os.numero like 'ORÇ-%' then 'OS-' || substr(v_os.numero, 5) else v_os.numero end;
    if v_num_novo <> v_os.numero
       and exists (select 1 from public.service_orders o2 where o2.service_order_number = v_num_novo and o2.id <> p_os) then
      return public._agenda_porta_fica(false, v_de, format('Não converti: o número %s já é de outra OS.', v_num_novo));
    end if;
    begin
      perform public._agenda_escrever_conclusao(p_os, 'approved', null, false, null,
        jsonb_build_object('numero', v_num_novo, 'converted_to_os_at', coalesce(v_os.converted_to_os_at, p_agora),
                           'original_quote_amount', coalesce(v_os.original_quote_amount, nullif(v_os.grand_total, 0))));
      v_texto := format('Orçamento %s virou a %s (aprovada).', v_os.numero, v_num_novo);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], 'draft', 'approved',
              jsonb_build_object('status', 'draft', 'numero', v_os.numero, 'converted_to_os_at', v_os.converted_to_os_at),
              jsonb_build_object('status', 'approved', 'numero', v_num_novo, 'convertido', true, 'via', p_via),
              left(v_texto, 400), v_autor)
      returning id into v_acao_conv;
      if v_para = 'approved' then
        return jsonb_build_object('ok', true, 'mudou', true, 'de', 'draft', 'para', 'approved', 'texto', left(v_texto, 400),
                                  'acao_id', v_acao_conv, 'convertido', true, 'numero', v_num_novo,
                                  'numero_antes', v_os.numero, 'check_in_at', v_os.check_in_at);
      end if;
      v_r := public.os_transicionar_status(p_os, v_para, p_via, p_motivo, p_autor, p_check_in, p_hoje, p_agora, p_check_out);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = v_r::text;
      end if;
    exception when sqlstate 'P0098' then
      return sqlerrm::jsonb || jsonb_build_object('de', 'draft', 'para', 'draft', 'mudou', false);
    end;
    return v_r || jsonb_build_object('de', 'draft', 'mudou', true, 'convertido', true, 'numero', v_num_novo,
                                     'numero_antes', v_os.numero, 'acao_conversao', v_acao_conv,
                                     'acao_id', coalesce(v_r -> 'acao_id', to_jsonb(v_acao_conv)),
                                     'texto', left(v_texto || ' ' || coalesce(v_r ->> 'texto', ''), 400));
  end if;

  -- FASE 3 (P7a): voltar a orçamento e faturar antes de concluir saíram para _os_porta_regra.

  -- A conclusão (ativo → concluída): (1) a OS já está travada; (2) as cobranças ANTES do status, como a tela (o gatilho do
  -- vencimento "na entrega" roda depois e as acerta); (3) um UPDATE com o status e a saída; (4) a ação concluir com as
  -- cobranças criadas. Erro em (2) ou (3) = nada muda (a OS, as cobranças e a saída ficam como estavam) e o texto diz por quê.
  if v_para = 'completed' then
    -- O retrato do que a conclusão vai mexer, para o desfazer: os vencimentos "na entrega" que o gatilho move e as comissões
    -- que já existiam (a de vendedor nasce no gatilho).
    select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'due_date', r.due_date) order by r.id), '[]'::jsonb) into v_venc
      from public.receivables r
     where r.service_order_id = p_os and r.due_on_completion and r.status not in ('paid', 'cancelled');
    select coalesce(jsonb_agg(jsonb_build_object('id', cc.id, 'due_date', cc.due_date) order by cc.id), '[]'::jsonb) into v_venc_cob
      from public.collections cc
      join public.receivables r on r.id = cc.receivable_id
     where r.service_order_id = p_os and r.due_on_completion and cc.status = 'pending';
    v_com_antes := array(select cm.id from public.commissions cm where cm.service_order_id = p_os);
    v_saida := coalesce(v_os.check_out_at, p_check_out, p_agora);
    begin
      v_rec := public._os_criar_recebiveis_da_conclusao(p_os, p_hoje);
      perform public._agenda_escrever_conclusao(p_os, 'completed', v_saida, false, null, null);
    exception when others then
      get stacked diagnostics v_erro = message_text;
      return public._agenda_porta_fica(false, v_de, public._os_erro_da_conclusao(v_erro));
    end;
    v_ids  := coalesce(array(select (x #>> '{}')::uuid from jsonb_array_elements(v_rec -> 'criados') x), '{}');
    v_coms := array(select cm.id from public.commissions cm
                     where cm.service_order_id = p_os and not (cm.id = any (v_com_antes)) order by cm.id);

    if v_rec ->> 'motivo' in ('parcelas', 'titulo_unico') then
      v_cob := case when cardinality(v_ids) = 1 then 'Cobrança: ' else 'Cobranças: ' end
               || public._os_cobrancas_texto(v_ids, p_hoje, v_os.numero) || '.';
    elsif v_rec ->> 'motivo' = 'total_zero' then
      v_cob := 'Sem cobrança: o total da OS está zerado.';
    else
      select min(r.due_date), sum(r.amount) into v_venc_dia, v_venc_soma
        from public.receivables r
       where r.id in (select (x ->> 'id')::uuid from jsonb_array_elements(v_venc) x);
      v_cob := 'As cobranças já existiam'
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.is_deposit
                                                                 and r.status in ('paid', 'partially_paid'))
                then ' (sinal pago)' else '' end
        || case when v_venc_dia is not null
                then format('; o saldo na entrega (%s) passa a vencer %s', public._brl(v_venc_soma),
                            case when v_venc_dia = p_hoje then 'hoje' else public._dia_curto(v_venc_dia) end)
                else '' end
        || '.';
    end if;
    v_texto := format('%s: concluída — saída %s %s.', v_nome,
                      public._dia_curto((v_saida at time zone 'America/Sao_Paulo')::date),
                      to_char(v_saida at time zone 'America/Sao_Paulo', 'HH24:MI'))
               || ' ' || v_cob;

    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor, desfazivel_ate, receivable_ids)
    values (clock_timestamp(), p_hoje, true, v_origem, 'concluir', p_os, array[p_os], v_de, 'completed',
            jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at, 'vencimentos', v_venc,
                               'cobrancas_vencimento', v_venc_cob),
            jsonb_build_object('status', 'completed', 'check_out_at', v_saida, 'via', p_via, 'cobrancas', v_rec ->> 'motivo',
                               'comissoes', to_jsonb(v_coms)),
            left(v_texto, 400), left(v_motivo, 200), v_autor,
            -- o gestor (equipe) e o dono (palavra, conversa) desfazem; a tela e a assinatura reabrem pela tela.
            case when v_origem in ('equipe', 'dono') then p_agora + c.desfazer_validade end,
            v_ids)
    returning id into v_acao;

    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', 'completed', 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', v_os.check_in_at, 'check_out_at', v_saida,
                              'cobrancas', v_rec, 'cobrancas_texto', v_cob);
  end if;
  -- FASE 3: fim

  -- Igual: nada a fazer — menos o início que faltava numa OS em andamento. FASE 3 (P7a): o "já está" dos outros status
  -- sai de _os_porta_regra; aqui só chega a OS em andamento (o início que falta depende do dado).
  if v_para = v_de then
    if v_de = 'in_progress' and v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    else
      return public._agenda_porta_fica(true, v_de, format('%s já está %s.', v_nome, public._agenda_status_texto(v_de)));
    end if;
  end if;

  -- A regra de cada passagem (vale em todos os modos; a do dia no plano, só em 'ligado').
  if v_para = 'scheduled' then
    -- FASE 3 (P7a): a OS que já começou e o cliente que não liberou saíram para _os_porta_regra.
    if v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    end if;
    if c.modo_proposta = 'ligado' and not public._agenda_os_tem_dia(p_os, p_hoje) then
      return public._agenda_porta_fica(true, v_de,
        format('Sem dia no plano: a OS continua %s.', public._agenda_status_texto(v_de)));
    end if;

  elsif v_para = 'in_progress' then
    if v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    end if;

  -- FASE 3 (P7a): aguardar depois de começar (a OC, o "parou" sem o dono ou sem o motivo) saiu para _os_porta_regra.

  elsif v_para in ('open', 'approved') then
    -- FASE 3 (P7a): a OS que já começou e a agendada pela tela saíram para _os_porta_regra.
    if v_de = 'scheduled' then
      if public._agenda_os_tem_dia(p_os, p_hoje) then
        return public._agenda_porta_fica(false, v_de, 'A OS ainda tem dia no plano: tire o dia antes.');
      end if;
      -- Volta ao que era antes de agendar (aberta ou aprovada); sem registro, aprovada. Revisão da Fase 3 (R2): pela tela
      -- (o administrador ou o financeiro, com a agenda automática fora de ligado: _os_porta_regra), o status que ele
      -- escolheu.
      if p_via <> 'tela' then
        select a.status_antes into v_antes
          from public.agenda_acoes a
         where a.service_order_id = p_os and a.tipo = 'status' and a.executada and a.status_depois = 'scheduled'
         order by a.criada_em desc, a.id desc
         limit 1;
        v_para := case when v_antes in ('open', 'approved') then v_antes else 'approved' end;
      end if;
    elsif v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    -- FASE 3 (P7a): o cliente que não liberou saiu para _os_porta_regra.
    end if;
  end if;

  -- Grava (a única escrita) e registra.
  perform public._agenda_escrever_os(p_os, case when v_para <> v_de then v_para end, v_check, null, null, false);

  v_texto := case
    when v_para = v_de then format('%s: início registrado', v_nome)
    else format('%s: de %s para %s', v_nome, public._agenda_status_texto(v_de), public._agenda_status_texto(v_para)) end
    || case when v_novo_check
            then format(' (%s às %s)', public._dia_curto((v_check at time zone 'America/Sao_Paulo')::date),
                        to_char(v_check at time zone 'America/Sao_Paulo', 'HH24:MI'))
            else '' end
    || coalesce(' — ' || rtrim(v_motivo, '. '), '') || '.';
  -- FASE 3: a origem de cada caminho saiu daqui para antes das regras (a conclusão e a conversão também a usam).

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                   status_depois, antes, depois, texto, motivo, autor, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
          jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at),
          jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
          left(v_texto, 400), left(v_motivo, 200), v_autor,
          -- FASE 3: o gestor (equipe) desfaz como o motor e a vigia: é ação autônoma.
          case when v_origem in ('motor', 'vigia', 'equipe') then p_agora + c.desfazer_validade end)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                            'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check));
end;
$function$;


comment on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 2; Fase 3: conclusão, faturamento, reabertura, conversão e p_check_out; Fase 3, P7a: as regras que só dependem do cargo, do status, do pedido e do caminho moram em _os_porta_regra, a mesma função que a tela lê): a porta única de status da OS. Vias: tela, tela_agendar, aprovacao, assistente, check_in, oc, motor, vigia, equipe, conferencia, dono, assinatura, desfazer. Status de agenda (todos os modos): em andamento nunca volta (agendada/aberta/aprovada) e só volta a aguardar com o motivo, pelo dono ou pela tela (admin/financeiro, técnico da OS; sem o motivo {ok false, pede_motivo true}) (a OC: ok, nada muda); aguardando peças só sai com o material completo; aguardando o cliente só sai pelo dono, a tela de agendar, a aprovação ou a assinatura do cliente; agendada só volta (para o status de antes) pela agenda ou pelo dono e sem dia no plano, e pela tela (para o status escolhido) só o admin/financeiro com a agenda automática fora de ligado; com login, as vias motor, vigia, equipe e assinatura são recusadas (42501), e dono e conferência só valem para admin/financeiro; em modo_proposta ligado, agendada só com dia no plano; check_in_at uma vez. Fase 3: concluir (ativo → concluída) cria as cobranças da condição (_os_criar_recebiveis_da_conclusao, paridade com a tela) ANTES do status e grava a saída num UPDATE só, tudo ou nada ({ok false} com o texto); faturar só concluída; reabrir concluída (tela, dono) mantém saída e cobranças; orçamento → X (tela, assistente, dono, aprovação, assinatura) converte trocando só o prefixo do número e aplica aprovada → X na mesma chamada; cancelar é Cancelar OS. Quem pode: status de agenda = admin/financeiro, técnico da OS, vendedor pela tela; converter = admin/financeiro, vendedor (tela, assistente), assinatura; concluir = admin/financeiro, técnico da OS, assinatura, equipe; faturar/reabrir/desfazer a conclusão = admin/financeiro. Toda mudança: linha em agenda_acoes (status; concluir com receivable_ids; desfazível quando foi motor/vigia/equipe, e a conclusão pela equipe ou pelo dono). Devolve {ok, mudou, de, para, texto, acao_id, check_in_at, check_out_at; na conclusão cobrancas e cobrancas_texto; na conversão convertido, numero, numero_antes}.';

-- ── 3. O que a porta aceita pela tela (a lista rápida e os kanbans) ──────────────────────────────────────

-- Por OS, os status que a porta aceita pela tela para o login: {"<id>": ["in_progress", "completed", ...]}. A régua é a de
-- _os_porta_regra (a mesma da porta, com o modo da agenda automática); o orçamento converte e, na mesma chamada, passa por
-- aprovada → o pedido, como a porta. Revisão da Fase 3 (R2): o que a porta aceita só com o motivo (em andamento → aguardando)
-- entra na lista E em "<id>:motivo" ({"<id>:motivo": ["awaiting_parts", "awaiting_client"]}): a tela pede o motivo antes de
-- chamar a porta. O que depende de dado (material, dia no plano, cobranças) fica de fora: a porta decide na hora e diz por
-- quê. Cancelar não entra (é o botão Cancelar OS, outro caminho). OS que não existe não aparece.
create or replace function public.os_status_da_tela(p_os uuid[])
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid      uuid := auth.uid();
  v_gestor   boolean;
  v_vendedor boolean;
  r          record;
  s          text;
  v_reg      jsonb;
  v_lista    text[];
  v_motivo   text[];
  v_ligada   boolean;
  v_out      jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'O que a porta aceita é pela tela, com login.' using errcode = '42501';
  end if;
  if cardinality(coalesce(p_os, '{}'::uuid[])) > 500 then
    raise exception 'os_status_da_tela: OS demais numa chamada (%).', cardinality(p_os) using errcode = '22023';
  end if;
  v_gestor   := public.is_admin_or_financial(v_uid);
  v_vendedor := exists (select 1 from public.app_users u where u.id = v_uid and u.active and u.role = 'seller');
  v_ligada   := (public._agenda_cfg()).modo_proposta = 'ligado';
  for r in select so.id, so.status,
                  exists (select 1 from public.service_order_technicians t
                            join public.app_users u on u.id = t.user_id
                           where t.service_order_id = so.id and t.user_id = v_uid and u.active) as tecnico
             from public.service_orders so
            where so.id = any (coalesce(p_os, '{}'::uuid[])) loop
    v_lista := '{}';
    v_motivo := '{}';
    foreach s in array array['draft', 'approved', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client',
                             'completed', 'invoiced'] loop
      continue when s = r.status;
      v_reg := public._os_porta_regra(r.status, s, 'tela', v_gestor, r.tecnico, v_vendedor, true, false, v_ligada);
      if v_reg ->> 'recusa' is null and v_reg ->> 'tipo' = 'conversao' and s <> 'approved' then
        v_reg := public._os_porta_regra('approved', s, 'tela', v_gestor, r.tecnico, v_vendedor, true, false, v_ligada);
      end if;
      if v_reg ->> 'recusa' is null then
        v_lista := v_lista || s;
      elsif coalesce((v_reg ->> 'pede_motivo')::boolean, false) then
        -- Revisão da Fase 3 (R2): a porta aceita com o motivo — a tela oferece e pergunta antes.
        v_lista := v_lista || s;
        v_motivo := v_motivo || s;
      end if;
    end loop;
    v_out := v_out || jsonb_build_object(r.id::text, to_jsonb(v_lista));
    if cardinality(v_motivo) > 0 then
      v_out := v_out || jsonb_build_object(r.id::text || ':motivo', to_jsonb(v_motivo));
    end if;
  end loop;
  return v_out;
end;
$function$;

comment on function public.os_status_da_tela(uuid[]) is
  'Agenda de Produção (Fase 3, P7a; revisão da Fase 3, R2): para o login, por OS, os status que a porta aceita pela tela ({"<id>": [status]}), pela MESMA régua da porta (_os_porta_regra, via tela, com o modo da agenda automática; o orçamento converte e passa por aprovada → o pedido); os que ela aceita só com o motivo (em andamento → aguardando) também em {"<id>:motivo": [status]}: a tela abre a janela do motivo antes de chamar a porta. A lista rápida de status e os kanbans escondem o que não estiver aqui ("Corrigir para Orçamento", "aguardando o cliente → aberta", concluir para quem não pode, faturar e reabrir para quem não é administrador). O que depende de dado fica com a porta, que decide na hora. Cancelar não entra (botão Cancelar OS). Só com login; até 500 OS por chamada.';

-- Revisão da Fase 3 (R3): o modo da agenda automática para QUALQUER login. agenda_config só é lida pelo administrador e pelo
-- financeiro: para o técnico e o vendedor a leitura da tabela voltava vazia (= "desligado"), o formulário da OS deixava as
-- datas editáveis com a agenda ligada e o gatilho recusava o salvamento inteiro (as outras mudanças também se perdiam). Só
-- o modo sai daqui; sem a linha, 'desligado' (o caminho de antes).
create or replace function public.agenda_modo_da_proposta()
 returns text
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select coalesce((select c.modo_proposta from public.agenda_config c where c.id), 'desligado');
$function$;

comment on function public.agenda_modo_da_proposta() is
  'Agenda de Produção (Fase 3, revisão R3): agenda_config.modo_proposta (desligado | sombra | ligado) para qualquer login — o formulário da OS deixa as datas só leitura com a agenda ligada também para o técnico e o vendedor (a tabela é fechada para eles). Só o modo; sem a linha, desligado.';

-- ── 4. As leituras das telas ────────────────────────────────────────────────────────────────────────────

-- O que o gestor mudou sozinho de ontem para hoje, uma linha por grupo, com o que a tela precisa para o Desfazer:
-- [{acao_id, tipo, os, numero, texto, desfazivel, desfeita, desfazivel_ate, perda (cobranca | diaria | null), em}]. Os
-- grupos do motor, da vigia e da conferência vêm de _agenda_mudancas (a mesma régua do foco mudancas; a frase sem o
-- "*desfaz …*", que na tela é o botão); o que o gestor fez pela palavra do técnico (origem equipe: a conclusão, a diária, o
-- status) vem uma linha por ação. perda diz quando desfazer cancela cobrança ou apaga diária (a tela pede confirmação).
create or replace function public._agenda_tela_mudancas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  gm as (
    select g, o from jsonb_array_elements(public._agenda_mudancas(p_hoje - 1, p_hoje, true, false, p_agora)) with ordinality t(g, o)
  ),
  m1 as (
    select (gm.g ->> 'em')::timestamptz as em, gm.o as ord, jsonb_build_object(
             'acao_id', (select a.id from public.agenda_acoes a
                          where a.id in (select x::uuid from jsonb_array_elements_text(gm.g -> 'acao_ids') x)
                          order by (a.tipo = 'publicar') desc, (a.tipo <> 'status') desc, a.criada_em, a.id limit 1),
             'tipo', gm.g ->> 'tipo', 'os', gm.g ->> 'os', 'numero', gm.g ->> 'numero',
             'texto', regexp_replace(public._agenda_mudanca_texto(gm.g, false), ' \*desfaz [^*]+\* volta como estava\.$', ''),
             'desfazivel', coalesce((gm.g ->> 'desfazivel')::boolean, false),
             'desfeita', coalesce((gm.g ->> 'desfeita')::boolean, false),
             'desfazivel_ate', (select min(a.desfazivel_ate) from public.agenda_acoes a
                                 where a.id in (select x::uuid from jsonb_array_elements_text(gm.g -> 'acao_ids') x)
                                   and a.desfeita_em is null),
             'perda', (select case when bool_or(a.tipo = 'concluir' and cardinality(a.receivable_ids) > 0) then 'cobranca'
                                   when bool_or(a.tipo = 'diaria' and a.work_shift_id is not null) then 'diaria' end
                         from public.agenda_acoes a
                        where a.id in (select x::uuid from jsonb_array_elements_text(gm.g -> 'acao_ids') x)),
             'em', gm.g -> 'em') as m
      from gm
  ),
  m2 as (
    select a.criada_em as em, row_number() over (order by a.criada_em, a.service_order_id, a.id) as ord, jsonb_build_object(
             'acao_id', a.id, 'tipo', a.tipo, 'os', a.service_order_id, 'numero', so.service_order_number,
             -- revisão da Fase 3 (item 5): a ação de ontem não diz "vence hoje" (o ajudante único de 20261026100500)
             'texto', public._agenda_vence_no_dia(a.texto, a.dia, p_hoje)
                      || case when a.desfeita_em is not null then ' (já desfeito)' else '' end,
             'desfazivel', a.desfazivel_ate is not null and a.desfeita_em is null and a.desfazivel_ate >= p_agora,
             'desfeita', a.desfeita_em is not null,
             'desfazivel_ate', a.desfazivel_ate,
             'perda', case when a.tipo = 'concluir' and cardinality(a.receivable_ids) > 0 then 'cobranca'
                           when a.tipo = 'diaria' and a.work_shift_id is not null then 'diaria' end,
             'em', a.criada_em) as m
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
     where a.dia between p_hoje - 1 and p_hoje and a.executada and a.origem = 'equipe'
       and a.tipo not in ('resultado', 'desfazer', 'fixar', 'equipe')
  )
  select coalesce(jsonb_agg(x.m order by x.em, x.fonte, x.ord), '[]'::jsonb)
    from (select m1.em, 1 as fonte, m1.ord, m1.m from m1 union all select m2.em, 2, m2.ord, m2.m from m2) x;
$function$;

comment on function public._agenda_tela_mudancas(date, timestamptz) is
  'Agenda de Produção (Fase 3, P7a): o "O que eu mudei sozinho" da tela Semana — de ontem para hoje, os grupos de _agenda_mudancas (motor, vigia, conferência; a publicação da semana é um grupo) e as ações do gestor pela palavra do técnico (origem equipe), cada uma com {acao_id (o que o Desfazer manda), tipo, os, numero, texto (sem o *desfaz …*), desfazivel, desfeita, desfazivel_ate, perda (cobranca: desfazer cancela a cobrança da conclusão; diaria: apaga a diária lançada; null), em}.';

-- A semana de produção (Agenda › Semana).
create or replace function public.agenda_tela_semana(p_de date default null, p_hoje date default public._hoje_brt(),
                                                     p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_seg    date;
  v_prop   uuid;
  v_teste  boolean := cf.modo_proposta = 'sombra';
  v_dias   jsonb;
  v_comp   int;
  v_livre  numeric;
  v_ppc    numeric;
  v_sem    jsonb;
  v_den    int;
  v_lv     jsonb;
  v_titulo text;
  v_dec    jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_tela_semana: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  v_seg := coalesce(p_de, p_hoje) - (extract(isodow from coalesce(p_de, p_hoje))::int - 1);

  if cf.modo_proposta = 'desligado' then
    return jsonb_build_object('modo', cf.modo_proposta, 'em_teste', false, 'de', v_seg, 'ate', v_seg + 5,
      'titulo', 'A agenda automática está desligada: não há plano publicado.',
      'resumo', null, 'comprometido_pct', null, 'livre_diarias', null, 'ppc_anterior', null, 'livre_de_verdade', null,
      'dias', '[]'::jsonb, 'mudancas', '[]'::jsonb, 'decisoes', '[]'::jsonb, 'como_responder', null);
  end if;
  -- Em sombra nada é publicado: os blocos são os da última semana que a sombra montou para estes dias.
  if v_teste then
    select pr.id into v_prop from public.agenda_propostas pr
     where pr.modo = 'sombra' and pr.escopo = 'semana' and pr.periodo && daterange(v_seg, v_seg + 6, '[]')
     order by pr.criada_em desc, pr.id desc limit 1;
  end if;

  with
  a0 as (
    select x.* from public.agenda_alocacoes x
     where (not v_teste and x.estado in ('publicada', 'fixada'))
        or (v_prop is not null and x.estado = 'proposta' and x.proposta_id = v_prop)
  ),
  na_semana as (select distinct x.service_order_id from a0 x where x.dia between v_seg and v_seg + 6),
  -- o "dia n de N" pela OS inteira (o dia em que nada foi cumprido não conta, como em v_agenda_dia)
  dias_os as (
    select d.service_order_id, d.dia,
           (row_number() over (partition by d.service_order_id order by d.dia))::int as dia_n,
           (count(*) over (partition by d.service_order_id))::int as dias_total
      from (select x.service_order_id, x.dia from a0 x join na_semana s using (service_order_id)
             where x.tipo <> 'reserva' group by x.service_order_id, x.dia
            having bool_or(x.resultado is distinct from 'nao_cumprido')) d
  ),
  a as (select x.* from a0 x where x.dia between v_seg and v_seg + 6),
  pp as (
    select a.dia, a.service_order_id, a.payee_id,
           array_agg(distinct a.turno order by a.turno) as turnos,
           case when bool_or(a.presenca = 'turno') then 'turno'
                when bool_or(a.presenca = 'abertura') and bool_or(a.presenca = 'fechamento') then 'abre_e_fecha'
                when bool_or(a.presenca = 'abertura') then 'abertura'
                else 'fechamento' end as presenca,
           min(lower(a.periodo)) as ini
      from a group by a.dia, a.service_order_id, a.payee_id
  ),
  pe as (
    select pp.dia, pp.service_order_id,
           jsonb_agg(jsonb_build_object('payee_id', pp.payee_id, 'nome', x.j ->> 'nome',
                                        'eh_dono', coalesce((x.j ->> 'eh_dono')::boolean, false),
                                        'turnos', to_jsonb(pp.turnos), 'presenca', pp.presenca)
                     order by coalesce((x.j ->> 'eh_dono')::boolean, false) desc, pp.ini, x.j ->> 'nome', pp.payee_id) as pessoas
      from pp cross join lateral (select public._agenda_pessoa(pp.payee_id) as j) x
     group by pp.dia, pp.service_order_id
  ),
  g as (
    select a.dia, a.service_order_id,
           bool_and(a.tipo = 'reserva') as reserva,
           case when bool_and(a.tipo = 'reserva') then 'reserva' else min(a.tipo) filter (where a.tipo <> 'reserva') end as tipo,
           min(a.reserva_de) filter (where a.tipo = 'reserva') as reserva_de,
           min(a.condicao) filter (where a.tipo = 'reserva') as condicao,
           min(lower(a.periodo)) as ini,
           bool_or(a.estado = 'fixada') as fixada,
           case when coalesce(bool_and(a.resultado is null) filter (where a.tipo <> 'reserva'), true) then null
                when bool_or(a.resultado = 'cumprido') then 'cumprido'
                when bool_or(a.resultado = 'parcial') then 'parcial'
                when bool_or(a.resultado = 'sem_registro') then 'sem_registro'
                else 'nao_cumprido' end as resultado
      from a group by a.dia, a.service_order_id
  ),
  blocos as (
    select g.dia, jsonb_agg(jsonb_build_object(
             'os', g.service_order_id, 'numero', so.service_order_number, 'cliente', public._agenda_nome_curto(cl.name),
             'bem', v.name, 'local', coalesce(m.name, nullif(btrim(cl.city), '')),
             'hora', to_char(g.ini at time zone 'America/Sao_Paulo', 'HH24:MI'),
             'pessoas_texto', nullif(public._agenda_pessoas_do_dia(pe.pessoas), ''),
             'dia_n', d.dia_n, 'dias_total', d.dias_total,
             'dia_texto', case when coalesce(d.dias_total, 1) > 1 and d.dia_n is not null
                               then format('dia %s de %s', d.dia_n, d.dias_total) end,
             'confirmado_cliente', coalesce((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = g.dia, false),
             'reserva', g.reserva,
             'reserva_texto', case when g.reserva then case when g.reserva_de = 'patio' then 'Reserva no pátio, a confirmar'
                                                            else 'Reserva, a confirmar' end end,
             'condicao', g.condicao, 'tipo', g.tipo, 'fixada', g.fixada, 'resultado', g.resultado,
             'resultado_texto', case g.resultado when 'cumprido' then 'feito' when 'parcial' then 'feito em parte'
                                                 when 'sem_registro' then 'sem registro' when 'nao_cumprido' then 'não aconteceu' end)
             order by g.ini, so.service_order_number, g.service_order_id) as blocos
      from g
      join public.service_orders so on so.id = g.service_order_id
      left join public.clients cl on cl.id = so.client_id
      left join public.vessels v on v.id = so.vessel_id
      left join public.marinas m on m.id = so.marina_id
      left join pe on pe.dia = g.dia and pe.service_order_id = g.service_order_id
      left join dias_os d on d.service_order_id = g.service_order_id and d.dia = g.dia
     group by g.dia
  ),
  cap as (select k.* from public.agenda_capacidade(v_seg, v_seg + 6, p_hoje) k),
  usado as (select a.payee_id, a.dia, a.turno from a group by a.payee_id, a.dia, a.turno),
  -- por pessoa e dia: os meios-dias esperados (a soma das frequências, ao meio-dia inteiro), os usados (qualquer presença,
  -- como a grade do motor) e os livres (esperados e sem nada no plano)
  pes as (
    select k.dia, k.payee_id, k.pessoa, k.eh_dono,
           round(sum(k.meios_esperados))::int as esp,
           count(u.turno)::int as usados,
           array_remove(array_agg(case when k.situacao = 'livre' and k.meios_esperados > 0 and u.turno is null then k.turno end
                                  order by k.turno = 'tarde'), null) as livres,
           coalesce(sum(k.meios_esperados) filter (where k.situacao = 'livre' and u.turno is null), 0) as livre_esp
      from cap k
      left join usado u on u.payee_id = k.payee_id and u.dia = k.dia and u.turno = k.turno
     group by k.dia, k.payee_id, k.pessoa, k.eh_dono
  ),
  dia as (
    select d::date as dia, b.blocos from generate_series(v_seg, v_seg + 5, interval '1 day') d
      left join blocos b on b.dia = d::date
     where extract(isodow from d) between 1 and 5 or b.blocos is not null or cf.sabado_util
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'dia', dia.dia, 'rotulo', upper(public._dia_curto(dia.dia)), 'hoje', dia.dia = p_hoje,
           'feriado', public.agenda_feriado(dia.dia),
           'pessoas', coalesce((select jsonb_agg(jsonb_build_object(
                         'payee_id', x.payee_id, 'nome', x.pessoa, 'eh_dono', x.eh_dono,
                         'meios_usados', x.usados, 'meios_esperados', x.esp,
                         'pct', case when x.esp > 0 then round(100 * x.usados::numeric / x.esp)::int end,
                         'cor', case when x.esp = 0 then 'vermelho'
                                     when x.usados::numeric / x.esp <= cf.carga_max then 'verde'
                                     when x.usados <= x.esp then 'ambar'
                                     else 'vermelho' end,
                         'texto', format('%s %s/%s', x.pessoa, x.usados, x.esp))
                       order by x.eh_dono desc, x.pessoa, x.payee_id)
                  from pes x where x.dia = dia.dia and (x.esp > 0 or x.usados > 0)), '[]'::jsonb),
           'blocos', coalesce(dia.blocos, '[]'::jsonb),
           'livre_texto', (select 'livre: ' || string_agg(case when x.eh_dono then 'você' else x.pessoa end || ' '
                                    || case when cardinality(x.livres) = 2 then 'dia todo'
                                            when x.livres[1] = 'manha' then 'manhã' else 'tarde' end,
                                    ', ' order by x.eh_dono desc, x.pessoa, x.payee_id)
                             from pes x where x.dia = dia.dia and dia.dia >= p_hoje and cardinality(x.livres) > 0))
           order by dia.dia), '[]'::jsonb),
         (select round(100 * sum(x.usados)::numeric / nullif(sum(x.esp), 0))::int from pes x
           where public.agenda_dia_util(x.dia)),
         (select trim_scale(round(sum(x.livre_esp)) / 2) from pes x where x.dia >= p_hoje and public.agenda_dia_util(x.dia))
    into v_dias, v_comp, v_livre
    from dia;

  v_sem := public.agenda_ppc(v_seg - 7, p_hoje);
  v_ppc := (v_sem ->> 'ppc')::numeric;
  v_den := (v_sem ->> 'cumpridos')::int + jsonb_array_length(coalesce(v_sem -> 'nao_cumpridos', '[]'::jsonb));
  if cf.modo_proposta = 'ligado' then
    v_lv := public.agenda_livre_de_verdade(p_hoje, p_agora);
  end if;
  v_titulo := case
    when v_teste and v_prop is null then 'Em teste: ainda não montei esta semana.'
    when v_teste then 'Em teste: eu montaria assim — ' || public._agenda_titulo_da_semana(v_seg) || '.'
    else public._agenda_titulo_da_semana(v_seg) end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'pergunta_id', e ->> 'id', 'n', (e ->> 'n')::int, 'tipo', e ->> 'tipo',
           'texto', format('Decisão %s: %s', e ->> 'n',
                           case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid)
                                else e ->> 'texto' end))
           order by (e ->> 'n')::int), '[]'::jsonb)
    into v_dec
    from jsonb_array_elements(public.agenda_decisoes_abertas(p_agora)) e;

  return jsonb_build_object(
    'modo', cf.modo_proposta, 'em_teste', v_teste, 'de', v_seg, 'ate', v_seg + 5, 'titulo', v_titulo,
    'comprometido_pct', v_comp, 'livre_diarias', v_livre,
    'ppc_anterior', case when v_ppc is not null then round(100 * v_ppc)::int end,
    'resumo', concat_ws(' · ',
                case when v_comp is not null then format('comprometido %s%%', v_comp) end,
                case when v_livre is not null then 'livre ' || replace(trim_scale(v_livre)::text, '.', ',')
                                                   || case when v_livre = 1 then ' diária' else ' diárias' end end,
                -- revisão da Fase 3: sem o jargão "PPC" — "semana passada: 5 de 6 dias cumpridos" (sem dia conferido, nada)
                case when v_den > 0
                     then format('semana passada: %s de %s %s', (v_sem ->> 'cumpridos')::int,
                                 public._agenda_plural(v_den, 'dia', 'dias'),
                                 case when (v_sem ->> 'cumpridos')::int = 1 then 'cumprido' else 'cumpridos' end) end),
    'livre_de_verdade', case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto' end,
    'dias', v_dias,
    'mudancas', public._agenda_tela_mudancas(p_hoje, p_agora),
    'decisoes', v_dec,
    'como_responder', case when jsonb_array_length(v_dec) > 0
                           then 'Responda no WhatsApp: diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2").' end);
end;
$function$;

comment on function public.agenda_tela_semana(date, date, timestamptz) is
  'Agenda de Produção (Fase 3, P7a): a tela Agenda › Semana da semana ISO de p_de (sem ele, a de p_hoje), seg a sex (o sábado só com plano ou sabado_util) — {modo, em_teste, de, ate, titulo ("Semana de 03 a 06/11 (seg 02 é Finados)"; em sombra "Em teste: eu montaria assim — …", com os blocos da última semana montada pela sombra), comprometido_pct, livre_diarias, ppc_anterior, resumo ("comprometido 54% · livre 5,5 diárias · semana passada: 5 de 6 dias cumpridos"; sem dia conferido na semana passada, sem essa parte), livre_de_verdade (a simulação, só em ligado), dias:[{dia, rotulo "TER 03/11", hoje, feriado, pessoas:[{payee_id, nome, eh_dono, meios_usados, meios_esperados, pct, cor (verde ≤ carga_max, ambar ≤ 100%, vermelho acima; esperado zero com uso = vermelho), texto "Roberto 2/2"}], blocos:[{os, numero, cliente, bem, local, hora, pessoas_texto, dia_n, dias_total, dia_texto "dia 1 de 3", confirmado_cliente, reserva, reserva_texto "Reserva, a confirmar", condicao, tipo, fixada, resultado, resultado_texto}], livre_texto "livre: Roberto tarde"}], mudancas (_agenda_tela_mudancas), decisoes:[{pergunta_id, n, tipo, texto}], como_responder}. Desligado: só o título. Administrador e financeiro (com login) ou service_role; senão 42501.';

-- A carteira de produção (Agenda › Carteira): o quadro de exceções por estado.
create or replace function public.agenda_tela_carteira(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_chaves text[] := array['prontas_sem_data', 'material_com_data', 'material_sem_previsao', 'material_atrasado',
                           'aguardando_cliente', 'sem_estimativa', 'congeladas', 'em_execucao', 'concluidas_nao_entregues'];
  v_rotulos text[] := array['Prontas sem data', 'Material com data', 'Material sem previsão', 'Material atrasado',
                            'Aguardando o cliente', 'Sem estimativa', 'Congeladas', 'Em execução', 'Concluídas e não entregues'];
  k        record;
  p        jsonb;
  v_est    text;
  v_mat    text;
  v_pr     jsonb;
  v_grupo  text;
  v_desde  date;
  v_idade  int;
  v_sem_dt boolean;
  v_quem   text;
  v_prox   text;
  v_rev    date;
  v_cart   jsonb := '[]'::jsonb;
begin
  if p_hoje is null then
    raise exception 'agenda_tela_carteira: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;

  for k in select x.service_order_id, x.numero, x.cliente_curto from public.os_carteira(p_hoje) x
            where not x.eh_orcamento order by x.numero, x.service_order_id loop
    p := public.os_prontidao(k.service_order_id, p_hoje);
    v_est := p ->> 'estado';
    v_mat := p #>> '{material,estado}';
    v_grupo := case
      when v_est = 'congelada' then 'congeladas'
      when v_est in ('em_execucao', 'parada') then 'em_execucao'
      when v_est in ('aguardando_cliente', 'sem_sinal') then 'aguardando_cliente'
      when v_est = 'esperando_voce' then 'sem_estimativa'
      when v_mat = 'atrasado' then 'material_atrasado'
      when v_est = 'aguardando_material' and v_mat in ('sem_previsao', 'nao_conferido') then 'material_sem_previsao'
      when v_est = 'aguardando_material' then 'material_com_data'
      -- com dia no plano está na Semana
      when v_est in ('programada', 'fixada', 'marcada') then null
      when v_est = 'pronta' and v_mat = 'previsto' then 'material_com_data'
      when v_est = 'pronta' and p #>> '{duracao,fonte}' = 'sugerida' then 'sem_estimativa'
      when v_est = 'pronta' then 'prontas_sem_data'
      end;
    continue when v_grupo is null;

    -- a restrição que trava: a 1ª da lista (já vem pela ordem do que mais pesa); aguardando o cliente, a do cliente
    select e into v_pr from jsonb_array_elements(coalesce(p -> 'restricoes', '[]'::jsonb)) with ordinality t(e, o)
     where coalesce((e ->> 'bloqueia')::boolean, false)
     order by (v_grupo = 'aguardando_cliente' and e ->> 'quem' = 'cliente') desc, o limit 1;
    v_desde := case when v_grupo = 'em_execucao'
                    then coalesce((p ->> 'ultima_evidencia')::date, (p ->> 'aprovada_em')::date)
                    else (p ->> 'aprovada_em')::date end;
    v_idade := greatest(coalesce(public.agenda_du_entre(v_desde, p_hoje), 0), 0);
    v_sem_dt := p #>> '{plano,proximo_dia}' is null and p ->> 'marcada' is null;
    v_quem := case
      when v_grupo = 'em_execucao' then case when v_est = 'parada' then 'voce' else 'equipe' end
      when v_grupo = 'congeladas' then null
      when v_grupo = 'material_com_data' then 'fornecedor'
      when v_grupo = 'prontas_sem_data' then null
      when v_pr is not null then case v_pr ->> 'quem' when 'dono' then 'voce' when 'cliente' then 'cliente' end
      when v_grupo = 'sem_estimativa' then 'voce'
      end;
    select pl.revisar_em into v_rev from public.os_planejamento pl where pl.service_order_id = k.service_order_id;
    v_prox := case
      when v_grupo = 'congeladas' then coalesce('rever ' || public._dia_curto(v_rev), p ->> 'estado_texto')
      when v_est = 'parada' then p ->> 'estado_texto'
      when v_grupo = 'em_execucao' then 'terminar o serviço'
      when v_grupo = 'material_com_data' and p #>> '{material,gargalo}' is not null and p #>> '{material,dpm}' is not null
        then format('esperar "%s" (%s)', public._agenda_corta(p #>> '{material,gargalo}', 40),
                    public._dia_curto((p #>> '{material,dpm}')::date))
      when v_grupo = 'material_com_data' then p ->> 'estado_texto'
      when v_pr ->> 'tipo' = 'compre_ate' and v_pr ->> 'compre_ate' is not null
        then 'comprar até ' || public._dia_curto((v_pr ->> 'compre_ate')::date)
      when v_pr ->> 'tipo' = 'duracao' then 'você dizer quantos dias'
      when v_pr ->> 'tipo' = 'cliente' then 'o cliente liberar'
      when v_pr ->> 'tipo' = 'sinal' then 'o cliente pagar o sinal'
      when v_pr is not null then coalesce(v_pr ->> 'pergunta', v_pr ->> 'texto')
      when v_grupo = 'sem_estimativa' then 'você dizer quantos dias'
      when v_grupo = 'prontas_sem_data'
        then case when cf.modo_proposta = 'ligado' then 'entrar no plano da semana' else 'marcar uma data' end
      else p ->> 'estado_texto' end;
    v_cart := v_cart || jsonb_build_object(
      'os', k.service_order_id, 'numero', k.numero, 'cliente', p ->> 'cliente_curto', 'bem', p ->> 'unidade',
      'grupo', v_grupo, 'estado', p ->> 'estado_texto', 'desde', v_desde, 'idade_du', v_idade,
      'idade_texto', case when v_idade = 0 then 'desde hoje'
                          else 'há ' || public._agenda_plural(v_idade, 'dia útil', 'dias úteis') end,
      'cor', case when v_sem_dt and v_idade > cf.carteira_vermelho_du then 'vermelho'
                  when v_idade > cf.carteira_laranja_du then 'laranja' else 'normal' end,
      'proxima_acao', v_prox, 'quem_trava', v_quem,
      'quem_trava_texto', case v_quem when 'voce' then 'trava: você' when 'cliente' then 'trava: o cliente'
                                      when 'fornecedor' then 'trava: o fornecedor' when 'equipe' then 'com a equipe' end);
  end loop;

  -- As concluídas pela porta (ação concluir) e ainda não entregues. As concluídas antes da Fase 3 não entram: não ter
  -- delivered_at nelas é a coluna nova, não a entrega que faltou.
  for k in select so.id, so.service_order_number as numero, public._agenda_nome_curto(cl.name) as cliente, v.name as bem,
                  (so.check_out_at at time zone 'America/Sao_Paulo')::date as saida
             from public.service_orders so
             left join public.clients cl on cl.id = so.client_id
             left join public.vessels v on v.id = so.vessel_id
            where so.status = 'completed' and so.delivered_at is null and so.check_out_at is not null
              and exists (select 1 from public.agenda_acoes a
                           where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null)
            order by so.check_out_at, so.service_order_number loop
    v_idade := greatest(coalesce(public.agenda_du_entre(k.saida, p_hoje), 0), 0);
    v_cart := v_cart || jsonb_build_object(
      'os', k.id, 'numero', k.numero, 'cliente', k.cliente, 'bem', k.bem, 'grupo', 'concluidas_nao_entregues',
      'estado', 'concluída ' || public._dia_curto(k.saida) || ', sem a entrega', 'desde', k.saida, 'idade_du', v_idade,
      'idade_texto', case when v_idade = 0 then 'desde hoje'
                          else 'há ' || public._agenda_plural(v_idade, 'dia útil', 'dias úteis') end,
      'cor', case when v_idade > cf.carteira_laranja_du then 'laranja' else 'normal' end,
      'proxima_acao', 'entregar ao cliente', 'quem_trava', 'voce', 'quem_trava_texto', 'trava: você');
  end loop;

  return jsonb_build_object(
    'grupos', (select jsonb_agg(jsonb_build_object('chave', v_chaves[i], 'rotulo', v_rotulos[i],
                                                   'n', (select count(*) from jsonb_array_elements(v_cart) c
                                                          where c ->> 'grupo' = v_chaves[i])) order by i)
                 from generate_subscripts(v_chaves, 1) i),
    'cartoes', (select coalesce(jsonb_agg(c order by array_position(v_chaves, c ->> 'grupo'),
                                          case c ->> 'cor' when 'vermelho' then 0 when 'laranja' then 1 else 2 end,
                                          (c ->> 'idade_du')::int desc, c ->> 'numero'), '[]'::jsonb)
                  from jsonb_array_elements(v_cart) c),
    'modo', cf.modo_proposta);
end;
$function$;

comment on function public.agenda_tela_carteira(date) is
  'Agenda de Produção (Fase 3, P7a): a tela Agenda › Carteira — {grupos:[{chave, rotulo, n}] (prontas_sem_data, material_com_data, material_sem_previsao, material_atrasado, aguardando_cliente, sem_estimativa, congeladas, em_execucao, concluidas_nao_entregues, nesta ordem), cartoes:[{os, numero, cliente, bem, grupo, estado (o texto da prontidão), desde, idade_du, idade_texto "há 23 dias úteis", cor (laranja acima de carteira_laranja_du; vermelho acima de carteira_vermelho_du sem data; senão normal), proxima_acao ("comprar até ter 27/10", "o cliente liberar", "você dizer quantos dias"), quem_trava (voce|cliente|fornecedor|equipe|null), quem_trava_texto}], modo}. Fonte: a carteira (os_carteira, fora orçamento) pela os_prontidao — a OS com dia no plano fica na Semana — e as concluídas pela porta (ação concluir) sem delivered_at. Administrador e financeiro (com login) ou service_role; senão 42501.';

-- O cartão "Plano" da OS.
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
begin
  if p_os is null or p_hoje is null then
    raise exception 'os_plano_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
  end if;
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

  return jsonb_build_object(
    'os', so.id, 'numero', so.numero, 'status', so.status, 'estado', p ->> 'estado_texto',
    'marcos', public.agenda_marcos_da_os(p_os, p_hoje),
    'pode_entregar', so.status = 'completed' and so.delivered_at is null,
    'duracao', jsonb_build_object(
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
  'Agenda de Produção (Fase 3, P7a): o cartão "Plano" da OS — {os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501.';

-- As linhas da grade técnico × dia como a equipe da agenda.
create or replace function public.agenda_equipe_da_grade(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if p_hoje is null then
    raise exception 'agenda_equipe_da_grade: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('payee_id', k.payee_id, 'nome', py.name, 'nome_curto', k.pessoa, 'eh_dono', k.eh_dono,
                                        'app_user_id', py.app_user_id)
                     order by k.eh_dono desc, k.pessoa, k.payee_id)
      from (select distinct c.payee_id, c.pessoa, c.eh_dono from public.agenda_capacidade(p_hoje, p_hoje, p_hoje) c) k
      join public.payees py on py.id = k.payee_id), '[]'::jsonb);
end;
$function$;

comment on function public.agenda_equipe_da_grade(date) is
  'Agenda de Produção (Fase 3, P7a): as linhas da grade técnico × dia como a equipe da agenda (payees) — o dono e quem tem perfil de diária vigente e padrão de disponibilidade (a regra da Fase 1, agenda_capacidade): [{payee_id, nome, nome_curto, eh_dono, app_user_id}], o dono primeiro. app_user_id casa com service_order_technicians e com agenda_tasks; sem login, a linha é só da pessoa. Administrador e financeiro (com login) ou service_role; senão 42501 (a tela volta às linhas de antes).';

-- ── 5. As escritas da tela (a ordem exata do dono) ──────────────────────────────────────────────────────

-- "Corrigir dias": a duração da OS dita pelo dono, de meio em meio dia.
create or replace function public.os_planejar_pela_tela(p_os uuid, p_dias numeric, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(null);
  v_st    text;
begin
  if p_os is null or p_hoje is null then
    raise exception 'Falta a OS.' using errcode = '22023';
  end if;
  if p_dias is null or p_dias <= 0 or p_dias * 2 <> trunc(p_dias * 2) or p_dias > 60 then
    raise exception 'A duração anda de meio em meio dia (por exemplo, 2 ou 2,5), até 60 dias.' using errcode = '22023';
  end if;
  select so.status into v_st from public.service_orders so where so.id = p_os;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;
  if v_st = 'draft' then
    raise exception 'Isso ainda é orçamento: a duração vale quando virar OS.' using errcode = '22023';
  end if;
  if v_st in ('completed', 'invoiced', 'cancelled') then
    raise exception 'A OS já saiu da carteira: a duração não muda mais.' using errcode = '22023';
  end if;
  perform public._agenda_aplicar_planejar(v_autor, p_os, jsonb_build_object('dias', p_dias, 'estimativa_fonte', 'dono'),
                                          format('Pela tela da OS: %s.', public._agenda_dias(p_dias)), p_hoje);
  return jsonb_build_object('ok', true, 'dias', p_dias, 'texto', format('Duração gravada: %s.', public._agenda_dias(p_dias)));
end;
$function$;

comment on function public.os_planejar_pela_tela(uuid, numeric, date) is
  'Agenda de Produção (Fase 3, P7a): o "Corrigir dias" do cartão Plano — grava os_planejamento.dias (múltiplo de meio dia, > 0, até 60) com estimativa_fonte dono, pelo mesmo caminho do *grava* (_agenda_aplicar_planejar: estimativa_em, atualizado_por e o histórico com o antes e o depois). Recusa orçamento e OS fora da carteira (22023, com a frase). Só o administrador (_autor_da_agenda); devolve {ok, dias, texto "Duração gravada: 2 dias."}.';

-- O Desfazer da tela Semana.
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
  return jsonb_build_object('ok', true, 'mudou', true, 'acoes', to_jsonb(v_ids),
    'texto', case when cardinality(v_txts) = 1 then v_txts[1]
                  else format('Desfiz a publicação da semana (%s): %s',
                              public._agenda_plural(cardinality(v_txts), 'mudança', 'mudanças'), array_to_string(v_txts, ' ')) end);
end;
$function$;

comment on function public.agenda_desfazer_pela_tela(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 3, P7a): o Desfazer da tela Semana — agenda_desfazer(ação, o administrador, via tela) (a conclusão, a entrega e a diária têm o desfazer delas); a publicação da semana desfaz todas as ações desfazíveis dela, tudo ou nada, como o *desfaz semana*. Só o administrador (_autor_da_agenda). {ok, mudou, acoes, texto}; recusado = {ok false, texto} e nada muda.';

-- ── 6. Portas ────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function public._os_porta_regra(text, text, text, boolean, boolean, boolean, boolean, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public._os_porta_regra(text, text, text, boolean, boolean, boolean, boolean, boolean, boolean) to service_role;

revoke all on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  to authenticated, service_role;

revoke all on function public.os_status_da_tela(uuid[]) from public, anon;
grant execute on function public.os_status_da_tela(uuid[]) to authenticated, service_role;

revoke all on function public.agenda_modo_da_proposta() from public, anon;
grant execute on function public.agenda_modo_da_proposta() to authenticated, service_role;

revoke all on function public._agenda_tela_mudancas(date, timestamptz) from public, anon, authenticated;
grant execute on function public._agenda_tela_mudancas(date, timestamptz) to service_role;

revoke all on function public.agenda_tela_semana(date, date, timestamptz), public.agenda_tela_carteira(date),
  public.os_plano_da_os(uuid, date), public.agenda_equipe_da_grade(date) from public, anon;
grant execute on function public.agenda_tela_semana(date, date, timestamptz), public.agenda_tela_carteira(date),
  public.os_plano_da_os(uuid, date), public.agenda_equipe_da_grade(date) to authenticated, service_role;

revoke all on function public.os_planejar_pela_tela(uuid, numeric, date),
  public.agenda_desfazer_pela_tela(uuid, date, timestamptz) from public, anon;
grant execute on function public.os_planejar_pela_tela(uuid, numeric, date),
  public.agenda_desfazer_pela_tela(uuid, date, timestamptz) to authenticated;
