-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P5: a conversa do dono — as palavras *manda cliente [nome]*,
-- *segura cliente [nome]* e *agenda clientes*, a ferramenta cliente_avisar (prepara a mensagem-modelo e NUNCA envia), o
-- os_planejar com o que foi dito ao cliente (prometido) e como o serviço é dito a ele (servico_cliente), o foco clientes da
-- agenda_ver e a linha cliente no fechamento.
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§3.2, §5.5, §6.2, §6.4, §7, §8.3 L1–L7, §8.5). Decisões do dono 23/10 (o
-- gestor manda sozinho as mensagens-modelo; os 3 primeiros dias de cada tipo passam pelo dono; o crítico sempre pergunta;
-- o LLM nunca escreve nem calcula data para o cliente). Depende de 20261028100000 (as tabelas), 100100 (os textos e o
-- prometido), 100200 (o registro e a decisão do envio), 100300 (a decisão do dono, o risco, o cancelar) e 100400 (a
-- resposta do cliente).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (6 funções novas, 6 recriadas; nenhuma tabela, nenhum gatilho, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f5p5/montar-migration.mjs: as partes escritas à mão
-- e os corpos das recriadas copiados da migration mais nova de cada uma (conferido com grep em 27/10), com cada bloco
-- "-- FASE 5:" conferido (fora dos blocos nenhuma linha muda).
--
-- POR QUE: a agenda fala sozinha com o cliente (P1–P4), mas o dono precisa de três coisas para isso valer: dizer *manda* ou
-- *segura* à mensagem que espera por ele (os 3 primeiros dias de cada tipo), pedir uma mensagem-modelo ("avisa o Nelson que
-- a peça chegou") sem que o assistente escreva ao cliente, e contar a data que ELE disse ao cliente (NOVO-agenda-39: as
-- datas ditas só existem no áudio). E ver tudo isso num lugar só.
--
-- O QUE MUDA:
--   1. agenda_cliente_decidir_dito (nova; authenticated e service_role, confere o administrador): *manda cliente [nome]* /
--      *segura cliente [nome]* — decide as cliente_aprovar abertas pelo _agenda_cliente_decidir (1 manda, 2 segura); sem
--      nome, todas; com nome, as do cliente. *segura* também tira do caminho a que ia sair sozinha. O aviso que é decisão
--      (cliente_aviso) só pela conversa (1, 2 ou 3).
--   2. agenda_cliente_preparar (nova; mesmas portas): a ferramenta cliente_avisar — confere o tipo e os dados e registra com
--      origem dono (em ligado, sempre esperando o dono). Devolve o texto e "Para mandar: *manda cliente <nome>*".
--   3. _agenda_ver_clientes (nova; definer, confere quem vê): o foco clientes (*agenda clientes*) — esperando você, vou
--      mandar, mandei, em teste, responderam, sem resposta e não consigo mandar; com a OS, também o que foi dito e a
--      confirmação. Auxiliares: _agenda_cliente_efeito_texto e _agenda_cliente_teria_feito (textos).
--   4. _agenda_cliente_fechamento (nova; invoker): a linha tipo cliente do fechamento (perda 75 a aprovação de amanhã, até
--      600 caracteres; perda 40 o que sai sozinho amanhã, com *segura cliente*).
--   5. Recriadas, com blocos "-- FASE 5:":
--      · agenda_ver (de 20261027100600): o foco clientes, com ou sem a OS; a mensagem do foco inválido cita os 18;
--      · _agenda_linhas_do_fechamento (de 20261026100500): a linha cliente, só com modo_cliente ligado;
--      · _agenda_mudancas (de 20261027100300): o que a resposta do cliente mudou (origem cliente) entra no que mudou
--        sozinho, com as ações do replano dele no mesmo grupo (depois.replano_acoes: contadas juntas, sem frase própria);
--        o acorde da mensagem ao cliente não é mudança;
--      · agenda_rascunho_planejar e _agenda_aplicar_planejar (de 20261025100400): prometido (a data como o dono disse ao
--        cliente; conferida no trecho; firme ou faixa) e servico_cliente (3 a 40 caracteres, sem valor nem link); o *grava*
--        grava o prometido pelo _agenda_cliente_gravar_prometido (fonte dono);
--      · _agenda_rascunho_frase (de 20261027100300): a releitura "você disse ao Flávio: ter 03/11 (data firme); o serviço,
--        para o cliente: a instalação do compressor".
--
-- O QUE NÃO MUDA: o envio, as travas, a janela, o teto e a revalidação (P2); a rodada e a decisão (P3); a resposta do
-- cliente (P4); o modo (modo_cliente) e as ondas (cliente_tipos_ligados). Nenhuma palavra nem ferramenta põe nada na fila
-- sozinha: o *manda cliente* aprova e o envio continua pelas três travas.
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, cobrança ou orçamento. A ferramenta não tem tipo de cobrança, e o
-- serviço dito ao cliente recusa valor, pagamento, número de OS e link (_agenda_cliente_texto_proibido).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase5_leituras.sql e anotadas em notas-fase5.md):
--   · *manda cliente* / *segura cliente* respondem também em sombra ("As mensagens ao cliente estão em teste: nada sai
--     ainda.", a frase da §6.4); só com modo_cliente desligado a palavra segue ao modelo (status nao_achei).
--   · *segura cliente <nome>* também segura a mensagem que ia sair sozinha (a linha do fechamento a oferece para as livres de
--     amanhã); *manda cliente* só decide as que esperam o dono.
--   · cliente_avisar segue d09 em todo tipo com data firme (confirmar, véspera, acesso, material chegou, nova data): sem o
--     material "completo" (os_prontidao), não prepara e diz o que falta. "Avisa o Nelson que a peça chegou" com a peça
--     sem previsão não vira mensagem (a spec previa 1 pedida no K52; a fixture tem o painel em 11/11 e dois críticos sem
--     previsão). mudanca_no_dia não é pela ferramenta: sai sozinha quando o dia muda.
--   · A chave da mensagem preparada é a da rodada (a mesma mensagem não sai duas vezes); a que já existe é dita como está
--     ("Já está pronta, esperando você…", "Essa mensagem já vai sair sozinha…"); a recusada antes (segurada, vencida) ganha
--     uma 2ª chance com o sufixo :dono.
--   · servico_cliente até 40 caracteres (a coluna aceita 80): o serviço aparece duas vezes no aviso de atraso, que tem de
--     caber em 400 (o risco anotado pelo P1).
--   · A linha cliente do fechamento: o secretário aceita até 640 caracteres por linha (secretario-tarde-coleta.ts,
--     LINHA_DA_AGENDA_MAX), então o teto de 600 da spec cabe; acima de 600 o texto da mensagem vai cortado em 300 com
--     "(*agenda clientes* mostra inteira)".
--
-- ORDEM DE LIGAR: depois de 20261028100000 a 100400; ANTES do deploy do ai-agent e do erp-mcp (as palavras, a ferramenta
-- cliente_avisar, o os_planejar com prometido e o prompt) e do ai-daily-briefing (o tipo cliente nas linhas do fechamento).
-- Sem esta migration, o foco clientes dá 22023 na agenda_ver (a palavra responde "Não consigo ler a agenda agora") e a
-- ferramenta cliente_avisar recebe a RPC ausente (erro ao modelo; nada é enviado).
--
-- PROVA: supabase/tests/agenda_fase5_leituras.sql (L0–L8). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261028100000 a 100400):
--   npx supabase db query --linked -f supabase/migrations/20261028100500_agenda_fase5_leituras.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100500', 'agenda_fase5_leituras');"
--
-- DESFAZER: reaplicar agenda_ver de 20261027100600, _agenda_linhas_do_fechamento de 20261026100500, _agenda_mudancas e
-- _agenda_rascunho_frase de 20261027100300, agenda_rascunho_planejar e _agenda_aplicar_planejar de 20261025100400; as
-- funções novas ficam (sem o ai-agent novo, ninguém as chama).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. O foco clientes da agenda_ver (*agenda clientes*) ────────────────────────────────────────────────

-- O efeito da resposta do cliente, como o dono lê ("confirmou", "pediu outro dia, e eu replanejei", "foi para você").
create or replace function public._agenda_cliente_efeito_texto(p_efeito text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_efeito
    when 'confirmou' then 'confirmou'
    when 'ciencia' then 'ficou ciente'
    when 'replanejou' then 'pediu outro dia, e eu replanejei'
    when 'anotou_acesso' then 'disse o acesso, e eu anotei na OS'
    when 'opt_out' then 'pediu para não receber mais mensagens'
    when 'ao_dono' then 'foi para você'
    when 'ambigua' then 'não deu para saber de qual serviço (foi para você)'
    when 'nada' then 'nada a fazer'
    else 'foi para você' end;
$function$;

comment on function public._agenda_cliente_efeito_texto(text) is
  'Agenda de Produção (Fase 5, P5): o efeito da resposta do cliente (agenda_cliente_respostas.efeito) como o dono lê — "confirmou", "ficou ciente", "pediu outro dia, e eu replanejei", "disse o acesso, e eu anotei na OS", "pediu para não receber mais mensagens", "foi para você".';

-- O que a agenda teria feito com a resposta, em teste (a intenção da resposta registrada em sombra).
create or replace function public._agenda_cliente_teria_feito(p_intencao text, p_dia date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_intencao = 'confirma' then 'eu teria confirmado' || coalesce(' ' || public._dia_curto(p_dia), '')
    when p_intencao in ('remarcar', 'falta', 'data') then 'eu teria tirado o dia e replanejado'
    when p_intencao = 'acesso' then 'eu teria anotado o acesso na OS'
    when p_intencao = 'opt_out' then 'eu teria parado as mensagens a ele'
    else 'eu teria passado a você' end;
$function$;

comment on function public._agenda_cliente_teria_feito(text, date) is
  'Agenda de Produção (Fase 5, P5): o que a agenda teria feito com uma resposta do cliente em teste ("eu teria confirmado ter 03/11", "eu teria tirado o dia e replanejado", "eu teria passado a você").';

-- *agenda clientes* / agenda_ver foco clientes: as mensagens ao cliente em 6 blocos (spec §5.5), sem OS — "Esperando você"
-- (as mensagens que esperam *manda cliente*, os avisos de atraso que são decisão e as respostas que foram ao dono), "Vou
-- mandar (hoje e amanhã)", "Mandei (7 dias)", "Em teste, eu teria mandado" (a sombra), "Responderam (7 dias)", "Sem
-- resposta" e "Não consigo mandar" (sem telefone, opt-out, sem conversa, tipos ainda em teste). Com a OS, o mesmo só dela,
-- mais o que foi dito (prometido_*) e a confirmação. A mensagem vai inteira (é aqui que o dono a lê quando o fechamento
-- corta). Definer: lê a fila e as respostas; com login, só administrador e financeiro (42501).
create or replace function public._agenda_ver_clientes(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid    uuid := (select auth.uid());
  cf       public.agenda_config;
  v_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_amanha date;
  v_l      text[] := '{}';
  v_c      text[] := '{}';
  v_ef     text[] := '{}';
  v_es     text[] := '{}';
  v_t      text[];
  k        int;
  v_b      text[];
  r        record;
  x        jsonb;
  v_cab    text;
  v_n      jsonb := '{}'::jsonb;
  v_tipos  text[];
  v_prom   text;
  v_conf   timestamptz;
  c_tipos  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                    'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia'];
begin
  if p_hoje is null then
    raise exception '_agenda_ver_clientes: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('ok', true, 'texto', 'As mensagens ao cliente estão desligadas: a agenda não fala com cliente.',
                              'dados', jsonb_build_object('modo', cf.modo_cliente));
  end if;
  v_amanha := public._agenda_cliente_dia_seguinte(p_hoje);

  -- o cabeçalho (e, com a OS, o que foi dito e a confirmação)
  if p_os is not null then
    select so.service_order_number as numero, so.client_confirmed_for,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome,
           pl.prometido_tipo, pl.prometido_de, pl.prometido_ate, pl.prometido_fonte, pl.prometido_em
      into r
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.id = p_os;
    v_cab := format('Mensagens ao cliente — %s (%s)%s:', coalesce(r.nome, 'cliente'), r.numero,
                    case when cf.modo_cliente = 'sombra' then ', em teste' else '' end);
    v_prom := case
      when r.prometido_ate is null then 'O que foi dito a ele: nada ainda.'
      else format('O que foi dito a ele: %s (%s, %s%s).',
                  case when coalesce(r.prometido_de, r.prometido_ate) = r.prometido_ate then public._dia_curto(r.prometido_ate)
                       else format('de %s a %s', public._dia_curto(r.prometido_de), public._dia_curto(r.prometido_ate)) end,
                  case r.prometido_tipo when 'firme' then 'data firme' when 'faixa' then 'uma faixa' else 'condicional' end,
                  case r.prometido_fonte when 'mensagem' then 'por mensagem da agenda' when 'dono' then 'por você'
                                         else 'pela confirmação' end,
                  coalesce(' em ' || public._dia_curto((r.prometido_em at time zone 'America/Sao_Paulo')::date), '')) end;
    v_l := array[v_cab, v_prom];
    if r.client_confirmed_for is not null then
      v_l := v_l || format('Ele confirmou %s.', public._dia_curto((r.client_confirmed_for at time zone 'America/Sao_Paulo')::date));
    end if;
  else
    v_l := array[case when cf.modo_cliente = 'sombra' then 'Mensagens ao cliente (em teste: nada sai ainda):'
                      else 'Mensagens ao cliente:' end];
  end if;

  -- (1) Esperando você: a mensagem que espera *manda cliente* (inteira), o aviso de atraso que é decisão, a data dita que
  -- passou sem aviso e a resposta que foi ao dono
  -- (o "não respondeu" fica no bloco Sem resposta). A mensagem vai inteira; se o texto passar de texto_max, as da 2ª em
  -- diante encurtam (v_es) antes de qualquer linha sair.
  for r in
    select m.tipo, m.texto, m.enviar_em, m.aprovacao, q.texto as pergunta,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m
      join public.clients cl on cl.id = m.client_id
      left join public.agenda_perguntas q on q.id = m.pergunta_id
     where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    if r.aprovacao = 'critica' then
      v_ef := v_ef || format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso do ' || r.nome || ' espera você (1, 2 ou 3).'));
      v_es := v_es || format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso do ' || r.nome || ' espera você (1, 2 ou 3).'));
    else
      v_ef := v_ef || format('• %s (%s), sai %s: "%s" — *manda cliente %s* ou *segura cliente %s*', r.nome,
                             public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                             r.texto, r.nome, r.nome);
      v_es := v_es || format('• %s (%s), sai %s: "%s" — *manda cliente %s*', r.nome,
                             public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                             public._agenda_corta(regexp_replace(r.texto, 'Aqui é [^.]*\.\s*', ''), 70), r.nome);
    end if;
  end loop;
  for r in
    select q.tipo, q.texto from public.agenda_perguntas q
     where q.modo = 'ligado' and q.estado = 'aberta' and (q.expira_em is null or q.expira_em > v_agora)
       and (p_os is null or q.service_order_id = p_os)
       and ((q.tipo = 'cliente_resposta' and q.chave not like 'cliente_resposta:sem_resposta:%')
            or (q.tipo = 'cliente_aviso' and not exists (select 1 from public.agenda_cliente_mensagens m where m.pergunta_id = q.id)))
     order by q.perda_em nulls last, q.criada_em, q.id
  loop
    v_ef := v_ef || case when r.tipo = 'cliente_aviso' then '• Decisão: ' || r.texto else '• ' || r.texto end;
    v_es := v_es || case when r.tipo = 'cliente_aviso' then '• Decisão: ' || r.texto else '• ' || r.texto end;
  end loop;
  v_n := v_n || jsonb_build_object('esperando', cardinality(v_ef));

  -- (2) Vou mandar (hoje e amanhã): as livres e as aprovadas que saem até o próximo dia de janela
  v_b := '{}';
  for r in
    select m.tipo, m.estado, m.enviar_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado in ('registrada', 'enfileirada', 'aguardando_dono') and m.aprovacao in ('livre', 'aprovada')
       and (m.enviar_em at time zone 'America/Sao_Paulo')::date <= v_amanha
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_b := v_b || format('• %s: %s, %s%s', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         case when r.estado = 'enfileirada' then 'na fila, ' else '' end,
                         public._agenda_cliente_quando_texto(r.enviar_em, v_agora));
  end loop;
  v_n := v_n || jsonb_build_object('vou_mandar', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Vou mandar (hoje e amanhã):'::text || v_b;
  end if;

  -- (3) Mandei (7 dias)
  v_b := '{}';
  for r in
    select m.tipo, m.enviada_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.enviada_em is not null and m.enviada_em > v_agora - interval '7 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviada_em, m.id
  loop
    v_b := v_b || format('• %s: %s (%s às %s)', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         public._dia_curto((r.enviada_em at time zone 'America/Sao_Paulo')::date),
                         to_char(r.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI'));
  end loop;
  v_n := v_n || jsonb_build_object('mandei', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Mandei (7 dias):'::text || v_b;
  end if;

  -- (3b) Em teste: o que a agenda teria mandado (a sombra dos últimos 7 dias e a que sairia)
  v_b := '{}';
  for r in
    select m.tipo, m.enviar_em, m.estado, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'sombra' and m.criada_em > v_agora - interval '7 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_b := v_b || format('• %s: %s (%s)', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         case when r.estado = 'recusada' then 'não sairia'
                              when r.enviar_em <= v_agora
                                then format('teria saído %s às %s', public._dia_curto((r.enviar_em at time zone 'America/Sao_Paulo')::date),
                                            to_char(r.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'))
                              else 'sairia ' || public._agenda_cliente_quando_texto(r.enviar_em, v_agora) end);
  end loop;
  v_n := v_n || jsonb_build_object('em_teste', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || case when cf.modo_cliente = 'sombra' then 'Em teste, eu teria mandado:'
                       else 'Em teste, eu teria mandado:' end || v_b;
  elsif cf.modo_cliente = 'sombra' then
    v_c := v_c || 'Em teste: nada que eu teria mandado nos últimos 7 dias.'::text;
  end if;

  -- (4) Responderam (7 dias): com o efeito; em teste, o que eu teria feito
  v_b := '{}';
  for r in
    select a.tipo_msg, a.texto, a.efeito, a.intencao, a.modo, m.tipo, m.variante,
           coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_respostas a
      join public.clients cl on cl.id = a.client_id
      left join public.agenda_cliente_mensagens m on m.id = a.mensagem_id
     where a.recebida_em > v_agora - interval '7 days' and a.recebida_em <= v_agora
       and (p_os is null or a.service_order_id = p_os)
     order by a.recebida_em, a.id
  loop
    v_b := v_b || format('• %s%s respondeu %s%s: %s', case when r.modo = 'sombra' then 'Em teste: o ' else '' end, r.nome,
                         case when r.tipo_msg = 'audio' then 'por áudio'
                              when r.tipo_msg <> 'text' then 'com ' || case r.tipo_msg when 'image' then 'uma foto'
                                                                                         when 'document' then 'um documento'
                                                                                         when 'video' then 'um vídeo'
                                                                                         else 'uma mensagem' end
                              else '"' || public._agenda_corta(coalesce(r.texto, ''), 60) || '"' end,
                         case when r.tipo is not null then ' ' || public._agenda_cliente_a_mensagem(r.tipo, r.variante, r.dia) else '' end,
                         case when r.efeito = 'sombra' then public._agenda_cliente_teria_feito(r.intencao, r.dia)
                              else public._agenda_cliente_efeito_texto(r.efeito) end);
  end loop;
  v_n := v_n || jsonb_build_object('responderam', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Responderam (7 dias):'::text || v_b;
  end if;

  -- (5) Sem resposta (o M1/M3/M7/M10 que o cliente não respondeu, dos últimos 14 dias)
  v_b := '{}';
  for r in
    select m.tipo, m.enviada_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.estado = 'sem_resposta' and m.enviada_em > v_agora - interval '14 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviada_em, m.id
  loop
    v_b := v_b || format('• %s: %s, mandada %s', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         public._dia_curto((r.enviada_em at time zone 'America/Sao_Paulo')::date));
  end loop;
  v_n := v_n || jsonb_build_object('sem_resposta', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Sem resposta:'::text || v_b;
  end if;

  -- (6) Não consigo mandar: os clientes da carteira (e das OS concluídas nos últimos 30 dias) sem telefone, com opt-out ou
  -- sem conversa no último ano (d10: por ora só mando a quem já escreveu — suposição, a confirmar com você); e, em ligado, os
  -- tipos ainda em teste
  v_b := '{}';
  for r in
    select c.id,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(c.display_name, '')), ''), c.name)) as nome,
           public._agenda_cliente_telefone(c.id) is null as sem_tel,
           public._agenda_cliente_sem_mensagem(c.id) as opt_out,
           not public._agenda_cliente_conversou(c.id, v_agora) as sem_conversa
      from public.clients c
     where c.id in (select so.client_id from public.service_orders so
                     where so.merged_into_id is null and (p_os is null or so.id = p_os)
                       and (so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
                            or (so.status in ('completed', 'invoiced')
                                and coalesce(so.delivered_at, so.check_out_at) > v_agora - interval '30 days')))
     order by 2, c.id
  loop
    if r.sem_tel then
      v_b := v_b || format('%s (sem telefone no cadastro)', r.nome);
    elsif r.opt_out then
      v_b := v_b || format('%s (pediu para não receber mensagens)', r.nome);
    elsif r.sem_conversa then
      v_b := v_b || format('%s (não escreveu para a HBR no último ano; por ora só mando a quem já escreveu)', r.nome);
    end if;
  end loop;
  v_n := v_n || jsonb_build_object('nao_consigo', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || format('Não consigo mandar: %s.', public._agenda_lista(v_b, null));
  end if;
  if cf.modo_cliente = 'ligado' then
    v_tipos := array(select public._agenda_cliente_tipo_texto(t) from unnest(c_tipos) with ordinality u(t, o)
                      where t <> all (cf.cliente_tipos_ligados) order by o);
    if cardinality(v_tipos) > 0 then
      v_c := v_c || format('Ainda em teste (não saem): %s.', public._agenda_lista(v_tipos, null));
    end if;
  end if;

  -- nada a contar (em ligado): a frase logo depois do cabeçalho, antes do que não consigo mandar
  if (select coalesce(sum(e.value::int), 0) from jsonb_each_text(v_n - 'em_teste' - 'nao_consigo') e) = 0
     and cf.modo_cliente = 'ligado' then
    v_l := v_l || 'Nada esperando você, nada a mandar e nenhuma resposta nos últimos 7 dias.'::text;
  end if;
  -- as que esperam você: a 1ª sempre inteira; as outras encurtam, da última para a 2ª, só se o texto não couber
  k := cardinality(v_ef);
  loop
    v_t := v_l || case when cardinality(v_ef) > 0 then 'Esperando você:'::text || (v_ef[1:k] || v_es[k + 1:]) else '{}'::text[] end
           || v_c;
    exit when k <= 1 or char_length(array_to_string(v_t, E'\n')) <= cf.texto_max;
    k := k - 1;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_t, cf.texto_max),
                            'dados', v_n || jsonb_build_object('modo', cf.modo_cliente, 'os', p_os));
end;
$function$;

comment on function public._agenda_ver_clientes(uuid, date) is
  'Agenda de Produção (Fase 5, P5): agenda_ver foco clientes (*agenda clientes*) — as mensagens ao cliente em blocos: "Esperando você" (a mensagem que espera *manda cliente*/*segura cliente*, INTEIRA; o aviso de atraso que é decisão; a data dita que passou sem aviso; a resposta que foi ao dono), "Vou mandar (hoje e amanhã)", "Mandei (7 dias)", "Em teste, eu teria mandado" (a sombra), "Responderam (7 dias)" com o efeito (em teste: o que eu teria feito), "Sem resposta" e "Não consigo mandar" (sem telefone, opt-out, sem conversa no último ano, tipos ainda em teste). Com p_os, só dela, mais o que foi dito (prometido_*) e a confirmação. modo_cliente desligado = "As mensagens ao cliente estão desligadas". Até texto_max, cortado por linha. A hora de agora: agenda.agora (a bancada), senão now(). Definer (lê a fila e as respostas): com login, só administrador e financeiro (42501). {ok, texto, dados:{esperando, vou_mandar, mandei, em_teste, responderam, sem_resposta, nao_consigo, modo, os}}.';

-- ── 2. As linhas da mensagem ao cliente no fechamento ───────────────────────────────────────────────────

-- A linha tipo cliente do fechamento (spec §5.5), só com modo_cliente ligado (quem chama confere): perda 75 com a
-- mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira; "E mais N: *agenda clientes*
-- mostra; *manda cliente* manda todas."; passou de c_max_cliente = o texto da mensagem cortado em 300 e "(*agenda
-- clientes* mostra inteira)"); perda 40 com "Amanhã, a partir das 09:00, vou mandar: …" (as livres e aprovadas do próximo
-- dia de janela, até 3 nomes, e *segura cliente <nome>*). Os avisos críticos entram pela linha decisao; o que saiu, pela
-- linha mudancas (as ações cliente).
create or replace function public._agenda_cliente_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  -- estrutural: a linha da aprovação leva a mensagem inteira (até 400) e as palavras; o secretário aceita até 640 por
  -- linha (secretario-tarde-coleta.ts, LINHA_DA_AGENDA_MAX)
  c_max_cliente constant int := 600;
  v_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_am     date := public._agenda_cliente_dia_seguinte(p_hoje);
  v_out    jsonb := '[]'::jsonb;
  r        record;
  v_n      int := 0;
  v_txt    text;
  v_itens  text[] := '{}';
  v_nomes  text[] := '{}';
  v_ini    timestamptz;
  v_rot    text;
begin
  for r in
    select m.tipo, m.texto, m.enviar_em, q.id as pergunta_id,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m
      join public.agenda_perguntas q on q.id = m.pergunta_id
      join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
       and q.tipo = 'cliente_aprovar' and q.estado = 'aberta'
       and (m.enviar_em at time zone 'America/Sao_Paulo')::date <= v_am
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_n := v_n + 1;
    if v_n = 1 then
      v_txt := format('Mensagem para o %s (%s), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.', r.nome,
                      public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                      r.texto, r.nome, r.nome);
      if char_length(v_txt) + 80 > c_max_cliente then
        v_txt := format('Mensagem para o %s (%s), sai %s: "%s" (*agenda clientes* mostra inteira). *manda cliente %s* ou *segura cliente %s*.',
                        r.nome, public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                        public._agenda_corta(r.texto, 300), r.nome, r.nome);
      end if;
      v_out := jsonb_build_array(jsonb_build_object('tipo', 'cliente', 'texto', v_txt, 'perda', 75, 'pergunta_id', r.pergunta_id,
                                                    'acao_ids', '[]'::jsonb, 'modo', 'ligado'));
    end if;
  end loop;
  if v_n > 1 then
    v_out := jsonb_set(v_out, '{0,texto}', to_jsonb(left(v_txt || format(' E mais %s: *agenda clientes* mostra; *manda cliente* manda todas.', v_n - 1),
                                                          c_max_cliente)));
  end if;

  for r in
    select m.tipo, m.enviar_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono') and m.aprovacao in ('livre', 'aprovada')
       and (m.enviar_em at time zone 'America/Sao_Paulo')::date = v_am and v_am > p_hoje
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_ini := coalesce(v_ini, r.enviar_em);
    v_itens := v_itens || format('%s ao %s', public._agenda_cliente_o_que(r.tipo, r.dia), r.nome);
    if not r.nome = any (v_nomes) then
      v_nomes := v_nomes || r.nome;
    end if;
  end loop;
  if cardinality(v_itens) > 0 then
    v_rot := case when v_am = p_hoje + 1 then 'Amanhã' else 'Em ' || public._dia_curto(v_am) end;
    v_txt := format('%s, a partir das %s, vou mandar: %s%s. Para não mandar: *segura cliente %s*.', v_rot,
                    to_char(v_ini at time zone 'America/Sao_Paulo', 'HH24:MI'), public._agenda_lista(v_itens, 3),
                    case when cardinality(v_itens) > 3 then ' (*agenda clientes* mostra)' else '' end, v_nomes[1]);
    v_out := v_out || jsonb_build_object('tipo', 'cliente', 'texto', public._agenda_corta(v_txt, c_max_cliente), 'perda', 40,
                                         'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'ligado');
  end if;
  return v_out;
end;
$function$;

comment on function public._agenda_cliente_fechamento(date) is
  'Agenda de Produção (Fase 5, P5): as linhas tipo cliente do fechamento (só com modo_cliente ligado; quem chama, _agenda_linhas_do_fechamento, confere) — perda 75: a mensagem que espera *manda cliente* e sai até o próximo dia de janela ("Mensagem para o Nelson (aviso de atraso), sai amanhã às 09:00: "…". *manda cliente Nelson* ou *segura cliente Nelson*.", a 1ª inteira; com mais de uma, "E mais N: *agenda clientes* mostra; *manda cliente* manda todas."; acima de 600 caracteres o texto da mensagem é cortado em 300 com "(*agenda clientes* mostra inteira)"); perda 40: "Amanhã, a partir das 09:00, vou mandar: a confirmação de ter 03/11 ao Flávio e … Para não mandar: *segura cliente Flávio*." (as livres e aprovadas do próximo dia de janela, até 3). [{tipo, texto, perda, pergunta_id, acao_ids, modo}].';

-- ── 3. As palavras *manda cliente* e *segura cliente* ───────────────────────────────────────────────────

-- *manda cliente [nome]* / *segura cliente [nome]*: decide as mensagens ao cliente que esperam o dono (cliente_aprovar,
-- por _agenda_cliente_decidir: 1 manda, 2 segura). Sem nome, todas; com nome, as do cliente (o 1º nome, ou o começo do
-- nome inteiro). *segura* também tira do caminho a que ia sair sozinha (livre ou aprovada, registrada ou ainda na fila).
-- O aviso de atraso que é decisão (cliente_aviso) não se decide por aqui: "responda pela conversa (1, 2 ou 3)". Fora de
-- ligado: "As mensagens ao cliente estão em teste: nada sai ainda." (desligado: nao_achei, a palavra segue ao modelo).
create or replace function public.agenda_cliente_decidir_dito(p_autor uuid, p_acao text, p_alvo text default null,
                                                              p_canal text default 'whatsapp',
                                                              p_hoje date default public._hoje_brt(),
                                                              p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_acao   text := lower(btrim(coalesce(p_acao, '')));
  v_via    text := case when p_canal in ('whatsapp', 'painel', 'tela') then p_canal else 'whatsapp' end;
  v_alvo   text := nullif(btrim(coalesce(p_alvo, '')), '');
  v_norm   text := public._agenda_normal(p_alvo);
  v_trecho text;
  r        record;
  v_r      jsonb;
  v_msgs   uuid[] := '{}';
  v_txts   text[] := '{}';
  v_nomes  text[] := '{}';
  v_quando text[] := '{}';
  v_todos_ok boolean := true;
  v_crit   int;
  v_cli    int;
  v_lista  text;
  v_q      text;
  v_txt    text;
begin
  if v_acao not in ('manda', 'segura') then
    raise exception 'A palavra da mensagem ao cliente é *manda cliente* ou *segura cliente* (veio "%").', coalesce(p_acao, '')
      using errcode = '22023';
  end if;
  v_trecho := format('%s cliente%s', v_acao, coalesce(' ' || v_alvo, ''));
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('ok', false, 'status', 'nao_achei',
                              'texto', 'As mensagens ao cliente estão desligadas: não há nada para mandar nem segurar.');
  end if;
  if cf.modo_cliente <> 'ligado' then
    return jsonb_build_object('ok', false, 'status', 'em_teste', 'texto', 'As mensagens ao cliente estão em teste: nada sai ainda.');
  end if;
  if v_alvo is not null and (char_length(v_alvo) > 40 or v_norm = '') then
    return jsonb_build_object('ok', false, 'status', 'nao_achei',
                              'texto', format('Não achei mensagem esperando para "%s".', left(v_alvo, 40)));
  end if;

  -- as mensagens vivas em ligado do alvo: as que esperam o dono (pedida; a crítica só para dizer que é decisão) e, no
  -- *segura*, as que iam sair sozinhas
  create temp table if not exists _agenda_cliente_alvo (id uuid, pergunta_id uuid, estado text, aprovacao text,
                                                        enviar_em timestamptz, client_id uuid, nome text, completo text)
    on commit drop;
  delete from _agenda_cliente_alvo;
  insert into _agenda_cliente_alvo
  select m.id, m.pergunta_id, m.estado, m.aprovacao, m.enviar_em, m.client_id,
         public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)),
         coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)
    from public.agenda_cliente_mensagens m
    join public.clients cl on cl.id = m.client_id
   where m.modo = 'ligado'
     and ((m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica'))
          or (v_acao = 'segura' and m.estado in ('registrada', 'enfileirada', 'aguardando_dono')
              and m.aprovacao in ('livre', 'aprovada')))
     and (v_alvo is null
          or public._agenda_normal(public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))) = v_norm
          or public._agenda_normal(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) = v_norm
          or public._agenda_normal(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) like v_norm || ' %'
          or public._agenda_normal(cl.name) = v_norm or public._agenda_normal(cl.name) like v_norm || ' %');

  select count(*) filter (where a.aprovacao = 'critica'), count(distinct a.client_id) filter (where a.aprovacao <> 'critica')
    into v_crit, v_cli from _agenda_cliente_alvo a;
  if v_cli = 0 then
    if v_crit > 0 then
      return jsonb_build_object('ok', false, 'status', 'decisao',
                                'texto', 'Essa é uma decisão: responda pela conversa (opção 1, 2 ou 3).');
    end if;
    return jsonb_build_object('ok', false, 'status', case when v_alvo is null then 'nenhuma' else 'nao_achei' end,
      'texto', case when v_alvo is null then 'Não tenho mensagem ao cliente esperando você.'
                    else format('Não achei mensagem esperando para "%s".', v_alvo) end);
  end if;
  if v_alvo is not null and v_cli > 1 then
    select public._agenda_lista(array_agg(distinct a.completo order by a.completo), null) into v_lista
      from _agenda_cliente_alvo a where a.aprovacao <> 'critica';
    return jsonb_build_object('ok', false, 'status', 'ambiguo',
      'texto', format('Tem %s clientes "%s" esperando (%s): diga o sobrenome.', v_cli, v_alvo, v_lista));
  end if;

  for r in select a.* from _agenda_cliente_alvo a where a.aprovacao <> 'critica' order by a.enviar_em, a.id loop
    if v_acao = 'manda' then
      continue when r.estado <> 'aguardando_dono' or r.aprovacao <> 'pedida';
      v_r := public._agenda_cliente_decidir(r.pergunta_id, 1::smallint, v_autor, v_via, v_trecho, p_agora);
      v_q := case when v_r ->> 'estado' = 'enfileirada' then 'agora'
                  else public._agenda_cliente_quando_texto((select m.enviar_em from public.agenda_cliente_mensagens m
                                                             where m.id = r.id), p_agora) end;
      v_todos_ok := v_todos_ok and coalesce((v_r ->> 'ok')::boolean, false)
                    and coalesce(v_r ->> 'estado', '') in ('aguardando_dono', 'registrada', 'enfileirada');
    elsif r.estado = 'aguardando_dono' and r.aprovacao = 'pedida' and r.pergunta_id is not null then
      v_r := public._agenda_cliente_decidir(r.pergunta_id, 2::smallint, v_autor, v_via, v_trecho, p_agora);
      v_todos_ok := v_todos_ok and coalesce((v_r ->> 'ok')::boolean, false);
    elsif public._agenda_cliente_cancelar(r.id, 'segurada', 'o dono segurou a mensagem') then
      update public.agenda_cliente_mensagens
         set aprovacao = 'segurada', aprovada_em = p_agora,
             aprovada_por = (select u.id from public.app_users u where u.id = v_autor)
       where id = r.id;
      v_r := jsonb_build_object('ok', true, 'texto', format('Segurei a mensagem do %s: ela não sai.', r.nome));
    else
      v_r := jsonb_build_object('ok', false, 'texto', format('A mensagem do %s já está saindo: não deu para segurar.', r.nome));
      v_todos_ok := false;
    end if;
    v_msgs := v_msgs || r.id;
    v_txts := v_txts || coalesce(v_r ->> 'texto', '');
    v_quando := v_quando || coalesce(v_q, '');
    if not r.nome = any (v_nomes) then
      v_nomes := v_nomes || r.nome;
    end if;
  end loop;

  if cardinality(v_msgs) = 0 then
    -- *manda* sem nenhuma esperando o dono (só as que já iam sair sozinhas)
    return jsonb_build_object('ok', false, 'status', 'nenhuma',
      'texto', case when v_alvo is null then 'Não tenho mensagem ao cliente esperando você.'
                    else format('Não achei mensagem esperando para "%s".', v_alvo) end);
  end if;
  v_txt := case
    when cardinality(v_msgs) = 1 then v_txts[1]
    when v_acao = 'manda' and v_todos_ok and (select count(distinct q) from unnest(v_quando) q) = 1
      then format('Mandei %s: %s (saem %s).', cardinality(v_msgs), public._agenda_lista(v_nomes, null), v_quando[1])
    when v_acao = 'segura' and v_todos_ok
      then format('Segurei %s: as mensagens do %s não saem.', cardinality(v_msgs), public._agenda_lista(v_nomes, null))
    else array_to_string(v_txts, ' ') end;
  return jsonb_build_object('ok', true, 'status', 'ok', 'texto', v_txt, 'decididas', cardinality(v_msgs),
                            'mensagens', to_jsonb(v_msgs));
end;
$function$;

comment on function public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P5): as palavras *manda cliente [nome]* e *segura cliente [nome]* — decide as mensagens ao cliente em ligado que esperam o dono (cliente_aprovar, por _agenda_cliente_decidir: manda = 1, segura = 2); *segura* também tira do caminho a que ia sair sozinha (livre/aprovada, registrada ou na fila sem sair: recusada segurada, aprovacao segurada). Sem nome, todas; com nome, as do cliente pelo 1º nome ou pelo começo do nome inteiro (dois clientes = "Tem 2 clientes "Rodrigo" esperando (…): diga o sobrenome."; nenhum = "Não achei mensagem esperando para "…"."). O aviso que é decisão (cliente_aviso) não: "Essa é uma decisão: responda pela conversa (opção 1, 2 ou 3).". Textos: o de _agenda_cliente_decidir ("Mando ao Nelson amanhã às 09:00.", "Segurei a mensagem do Flávio: ela não sai."); com várias, "Mandei 2: Nelson e Flávio (saem amanhã às 09:00)." / "Segurei 2: as mensagens do Nelson e Flávio não saem.". modo_cliente sombra = "As mensagens ao cliente estão em teste: nada sai ainda."; desligado = status nao_achei (a palavra segue ao modelo). Admin pelo _autor_da_agenda. {ok, status (ok|nenhuma|nao_achei|ambiguo|decisao|em_teste), texto, decididas, mensagens}.';

-- ── 4. A ferramenta do dono: cliente_avisar (prepara, nunca envia) ──────────────────────────────────────

-- A mensagem-modelo que o dono pede ("avisa o Nelson que a peça chegou", "manda a confirmação pro Flávio"): resolve a OS,
-- confere o tipo e os dados (sem dado, diz o que falta), e registra com origem dono — em ligado, sempre esperando o dono
-- (*manda cliente <nome>*); em teste, a sombra. O texto e as datas são do banco (_agenda_cliente_texto pelo registro).
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
    return public._agenda_recusa(format('O %s não tem telefone no cadastro: não tenho como mandar.', v_nome), 'sem_telefone');
  end if;
  if coalesce((x ->> 'opt_out')::boolean, false) then
    return public._agenda_recusa(format('O %s pediu para não receber mensagens: não mando.', v_nome), 'opt_out');
  end if;

  if v_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data') then
    v_dia := (x ->> 'dia')::date;
    -- d09: material sem previsão ou não conferido nunca vira data firme (antes da data: é o que o dono precisa saber)
    if coalesce(x ->> 'material_estado', '') <> 'completo' then
      return public._agenda_recusa(format('O material do %s ainda não está todo na mão (%s): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.',
                                          v_nome, case x ->> 'material_estado' when 'previsto' then 'tem peça a caminho'
                                                                             when 'sem_previsao' then 'tem peça sem previsão de chegada'
                                                                             when 'atrasado' then 'tem peça atrasada'
                                                                             else 'o material ainda não foi conferido' end),
                                   'material');
    end if;
    if v_dia is null then
      return public._agenda_recusa(format('O %s não tem data no plano: não tenho o que %s.', v_nome,
                                          case v_tipo when 'confirmar' then 'confirmar' when 'nova_data' then 'dizer de data nova'
                                                      else 'avisar' end), 'sem_data');
    end if;
    if v_tipo in ('vespera', 'acesso') then
      if v_dia <= p_hoje then
        return public._agenda_recusa(format('O serviço do %s é hoje: a véspera já passou.', v_nome), 'passou');
      end if;
      v_alvo := greatest(p_agora, public._agenda_cliente_toque(public._agenda_cliente_vespera(v_dia)));
    end if;
  elsif v_tipo = 'pode_atrasar' then
    v_rk := public._agenda_cliente_risco(v_os, p_hoje);
    if (x #>> '{prometido,ate}') is null or v_rk is null then
      return public._agenda_recusa(format('Não há data dita ao %s: sem data dita, não há atraso a avisar. Se você disse uma data a ele, me conte ("falei pro %s que é dia 3").',
                                          v_nome, v_nome), 'sem_prometido');
    end if;
    if coalesce((v_rk ->> 'passou')::boolean, false) then
      return public._agenda_recusa(format('A data que o %s ouviu (%s) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.',
                                          v_nome, public._dia_curto((v_rk ->> 'dito_ate')::date)), 'passou');
    end if;
    if coalesce(p_firme, false) then
      -- a data firme do plano no lugar da faixa (d09: só o dono decide, e só com o plano publicado)
      if (x ->> 'dia') is null or (x ->> 'fim') is null then
        return public._agenda_recusa(format('O %s não tem o plano publicado: não tenho data firme para dizer; vai a faixa.', v_nome),
                                     'sem_plano');
      end if;
      v_var := 'remarcado';
      v_dia := (x ->> 'dia')::date;
      v_dados := jsonb_build_object('dia', x -> 'dia', 'fim', x -> 'fim', 'prometido_tipo', 'firme',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate');
    else
      if coalesce((v_rk ->> 'sem_data')::boolean, false) then
        return public._agenda_recusa(format('A peça do %s ainda não tem previsão: não tenho data nova para dizer. Com a previsão eu preparo (ou peça com a data firme do plano).',
                                            v_nome), 'sem_data');
      end if;
      if not coalesce((v_rk ->> 'risco')::boolean, false) then
        return public._agenda_recusa(format('O plano do %s ainda cabe na data que ele ouviu (%s): não há atraso a avisar.', v_nome,
                                            public._dia_curto((v_rk ->> 'dito_ate')::date)), 'sem_risco');
      end if;
      v_var := v_rk ->> 'variante';
      v_dia := (v_rk ->> 'faixa_de')::date;
      v_dados := jsonb_build_object('faixa_de', v_rk -> 'faixa_de', 'faixa_ate', v_rk -> 'faixa_ate', 'prometido_tipo', v_rk -> 'tipo',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate')
                 || case when v_var = 'peca' then jsonb_build_object('peca_de', v_rk -> 'peca', 'peca_ate', v_rk -> 'peca')
                         else '{}'::jsonb end;
    end if;
    v_valida := public._agenda_cliente_ultimo_fim((v_rk ->> 'dito_ate')::date);
  elsif v_tipo = 'andamento' then
    v_pl := public._agenda_plano_da_os(v_os, p_hoje);
    select min(a.dia) into v_ini from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.resultado in ('cumprido', 'parcial');
    if v_st <> 'in_progress' or v_ini is null or (v_pl ->> 'ultimo_dia') is null then
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
      return public._agenda_recusa(format('O serviço do %s ainda não está concluído.', v_nome), 'nao_concluida');
    end if;
    if v_tipo in ('pronto', 'pronto_lembrete')
       and exists (select 1 from public.service_orders so where so.id = v_os and so.delivered_at is not null) then
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
    return jsonb_build_object('ok', true, 'status', 'ja_existe', 'texto', v_txt, 'mensagem_id', m.id, 'estado', m.estado,
                              'modo', m.modo);
  end if;
  if v_r ->> 'estado' = 'recusada' then
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
  return jsonb_build_object('ok', true, 'status', 'preparada', 'texto', v_txt, 'mensagem_id', v_r -> 'id',
                            'estado', v_r ->> 'estado', 'modo', v_r ->> 'modo', 'enviar_em', v_r -> 'enviar_em');
end;
$function$;

comment on function public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P5): a ferramenta cliente_avisar — prepara a mensagem-modelo que o dono pede e NUNCA envia. Resolve a OS (agenda_resolver_os; o pronto, o lembrete e o pós-serviço aceitam a OS concluída fora da carteira), confere o telefone e o opt-out, o tipo e os dados (sem dado, diz o que falta: "O Nelson não tem data no plano: não tenho o que confirmar.", "Não há data dita ao Giancarlo: …", d09 — material fora de "completo" não vira data firme), e registra pelo _agenda_cliente_registrar com origem dono (em ligado, sempre pedida: "Pronto para o Nelson, sai amanhã às 09:00: "…". Para mandar: *manda cliente Nelson*."; em teste, a sombra). A chave é a da rodada (a mesma mensagem não sai duas vezes: a que já existe é dita como está; a recusada antes ganha uma 2ª chance com :dono). p_firme (só pode_atrasar): a data firme do plano (variante remarcado) no lugar da faixa, só com o plano publicado. mudanca_no_dia não é pela ferramenta (sai sozinha). modo_cliente desligado = recusa. Admin pelo _autor_da_agenda. {ok, status, texto, mensagem_id, estado, modo, enviar_em} ou a recusa {ok:false, motivo, pergunta, texto}.';

-- ── 5. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 5:") ─────────
-- agenda_ver: corpo de 20261027100600; _agenda_linhas_do_fechamento: de 20261026100500; _agenda_mudancas e
-- _agenda_rascunho_frase: de 20261027100300; agenda_rascunho_planejar e _agenda_aplicar_planejar: de 20261025100400 (as mais
-- novas, conferidas com grep em 27/10). Fora dos blocos "-- FASE 5:" nenhuma linha muda (o L8 confere). A casca não muda.

create or replace function public.agenda_ver(p_autor uuid default null, p_periodo text default null,
                                             p_pessoa text default null, p_foco text default null, p_os text default null,
                                             p_simular jsonb default null, p_simular_aprovacao boolean default false,
                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_foco    text := coalesce(nullif(btrim(lower(p_foco)), ''), 'tudo');
  v_rp      jsonb;
  v_payee   uuid;
  v_eh_dono boolean := true;
  v_de      date;
  v_ate     date;
  v_ro      jsonb;
  v_r       jsonb;
  v_pn      jsonb;
  v_rota    text;
  v_max     int;
  v_l       text[];
  k         int;
  -- FASE 2: a hora de agora (desfazer ainda vale? a decisão venceu?). now(); a bancada fixa com agenda.agora.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  -- FASE 3: o livre de verdade (a simulação do motor) e o mês da comissão
  v_lv      jsonb;
  v_mes     date;
begin
  -- FASE 5: o foco clientes (a mensagem ao cliente: _agenda_ver_clientes, com ou sem a OS; a OS concluída também) e a
  -- conferência do foco com os 18 — antes da conferência dos 17 da Fase 4, que o foco clientes não alcança.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores ou clientes)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'clientes' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    if nullif(btrim(p_os), '') is not null then
      v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
      if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
        return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                  'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                  'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
      return public._agenda_ver_clientes((v_ro ->> 'id')::uuid, p_hoje) || jsonb_build_object('rota', 'clientes_os');
    end if;
    return public._agenda_ver_clientes(null, p_hoje) || jsonb_build_object('rota', 'clientes');
  end if;
  -- FASE 5: fim
  -- FASE 2: os focos decisoes, mudancas e plano
  -- FASE 3: os focos ppc, diarias, marcos, comissao e equipe
  -- FASE 4: os focos compras e fornecedores (a conferência e a mensagem com os 17)
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras ou fornecedores)', p_foco
      using errcode = '22023';
  end if;
  -- FASE 4: fim
  if p_hoje is null then
    raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Desligada (agenda_config.modo_leitura), a agenda de produção não responde: o assistente volta à agenda de antes
  -- (my_agenda: tarefas e compromissos do dono). Quem não lê agenda_config continua recebendo erro (nunca "livre").
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                              'texto', 'A agenda de produção está desligada agora.');
  end if;

  -- Pessoa: "eu" ou o nome. Quem não existe ou é ambíguo volta a frase do resolvedor (nunca um erro cru).
  if nullif(btrim(p_pessoa), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'rota', 'pessoa', 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto',
                                'opcoes', coalesce(v_rp -> 'opcoes', '[]'::jsonb));
    end if;
    v_payee := (v_rp ->> 'payee_id')::uuid;
    v_eh_dono := coalesce((v_rp ->> 'eh_dono')::boolean, false);
  end if;

  -- Período: hoje, amanhã, semana, próxima semana ou o que o dono disse.
  -- FASE 3: a comissão lê o mês ("outubro", "mês passado"), não um período de dias.
  if v_foco = 'comissao' then
    begin
      v_mes := public._agenda_mes_dito(p_periodo, p_hoje);
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  else
    begin
      select x.de, x.ate into v_de, v_ate from public._agenda_periodo(p_periodo, p_hoje) x;
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  end if;

  if coalesce(p_simular_aprovacao, false) and nullif(btrim(p_os), '') is null then
    return jsonb_build_object('ok', false, 'rota', 'ctp',
      'texto', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).',
      'pergunta', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).');
  end if;

  if nullif(btrim(p_os), '') is not null then
    v_ro := public.agenda_resolver_os(p_os, p_hoje, coalesce(p_simular_aprovacao, false));
    if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
      return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    if coalesce(p_simular_aprovacao, false) then
      v_rota := 'ctp';
      v_r := public.agenda_ctp((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 3: os marcos da OS (dentro ou fora da carteira: a concluída e a entregue já saíram dela)
    elsif v_foco = 'marcos' then
      v_rota := 'marcos';
      v_r := public._agenda_ver_marcos((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 4: as compras e a espera de peça da OS (também fora da carteira: a concluída nos últimos 180 dias); os
    -- fornecedores não são de uma OS
    elsif v_foco = 'compras' then
      v_rota := 'compras_os';
      v_r := public._agenda_ver_compras((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_foco = 'fornecedores' then
      v_rota := 'fornecedores';
      v_r := public._agenda_ver_fornecedores(p_hoje);
    -- FASE 4: fim
    elsif v_ro ->> 'status' = 'fora_da_carteira' then
      v_rota := 'os';
      v_r := jsonb_build_object('ok', true, 'texto', v_ro ->> 'texto', 'dados', jsonb_build_object('numero', v_ro ->> 'numero'));
    elsif v_foco = 'material' then
      v_rota := 'material_os';
      v_r := public.agenda_ver_material((v_ro ->> 'id')::uuid, p_hoje);
    else
      v_rota := 'os';
      v_r := public._agenda_ver_os((v_ro ->> 'id')::uuid, p_hoje);
    end if;
  -- FASE 3: os marcos pedem a OS
  elsif v_foco = 'marcos' then
    return jsonb_build_object('ok', false, 'rota', 'marcos',
      'texto', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).',
      'pergunta', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).');
  elsif p_simular is not null and jsonb_typeof(p_simular) = 'object' then
    v_rota := 'simular';
    v_r := public.agenda_simular((p_simular ->> 'dias')::numeric, coalesce(p_simular -> 'com_quem', '[]'::jsonb),
                                 nullif(p_simular ->> 'dono', ''), p_autor, p_hoje);
  -- FASE 2: o que espera o dono, o que mudou sozinho e o plano publicado
  elsif v_foco = 'decisoes' then
    v_rota := 'decisoes';
    v_r := public._agenda_ver_decisoes(p_hoje, v_agora);
  elsif v_foco = 'mudancas' then
    v_rota := 'mudancas';
    v_r := public._agenda_ver_mudancas(p_hoje, v_agora);
  elsif v_foco = 'plano' then
    v_rota := 'plano';
    v_r := public._agenda_ver_plano(v_de, v_ate, p_hoje, v_agora);
  -- FASE 3: a semana medida, as diárias da agenda, a comissão do mês e o que a equipe respondeu
  elsif v_foco = 'ppc' then
    v_rota := 'ppc';
    v_r := public._agenda_ver_ppc(v_de, p_hoje);
  elsif v_foco = 'diarias' then
    v_rota := 'diarias';
    v_r := public._agenda_ver_diarias(v_de, v_ate, p_hoje);
  elsif v_foco = 'comissao' then
    v_rota := 'comissao';
    v_r := public._agenda_ver_comissao(v_mes, p_hoje);
  elsif v_foco = 'equipe' then
    v_rota := 'equipe';
    v_r := public._agenda_ver_equipe(p_hoje);
  -- FASE 4: o que comprar e até quando, as notas, o tempo até comprar e a pergunta ao fornecedor; como conto o prazo de
  -- cada fornecedor
  elsif v_foco = 'compras' then
    v_rota := 'compras';
    v_r := public._agenda_ver_compras(null, p_hoje);
  elsif v_foco = 'fornecedores' then
    v_rota := 'fornecedores';
    v_r := public._agenda_ver_fornecedores(p_hoje);
  -- FASE 4: fim
  elsif v_foco = 'o_que_fazer' then
    if v_payee is not null and not v_eh_dono then
      v_rota := 'dia_da_pessoa';
      v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
    else
      v_rota := 'o_que_fazer';
      v_r := public.agenda_o_que_fazer(coalesce(v_payee, public._agenda_dono(p_autor)), p_hoje);
    end if;
  elsif v_foco in ('atrasos', 'riscos') then
    v_rota := 'atrasos';
    v_r := public.agenda_atrasos(p_hoje);
  elsif v_foco = 'material' then
    v_rota := 'material';
    v_r := public.agenda_ver_material(null, p_hoje);
  elsif v_foco = 'livre' then
    v_rota := 'livre';
    v_r := public.agenda_semana(null, null, p_hoje);
    -- FASE 3: com a agenda automática ligada, o livre de verdade sai da simulação do motor (fora disso, a projeção)
    if (public._agenda_cfg()).modo_proposta = 'ligado' then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
    end if;
    v_r := jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[v_r #>> '{dados,textos,resumo}',
                                           case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto'
                                                else v_r #>> '{dados,textos,livre}' end],
                                     (select texto_max from public._agenda_cfg())),
      'dados', jsonb_build_object('fila', v_r #> '{dados,fila}', 'livre', v_r #> '{dados,livre}',
                                  'capacidade', v_r #> '{dados,capacidade}',
                                  'livre_de_verdade', coalesce(v_lv, jsonb_build_object('fonte', 'projecao'))));
  elsif v_foco = 'aprontar' then
    v_rota := 'aprontar';
    v_r := public.agenda_aprontar(p_hoje);
  elsif v_payee is not null and not v_eh_dono and (v_de is null or v_de = v_ate) then
    v_rota := 'dia_da_pessoa';
    v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
  elsif v_de is not null and v_de = v_ate then
    v_rota := 'dia';
    v_pn := public._agenda_painel(p_hoje);
    v_max := (v_pn ->> 'texto_max')::int;
    for k in reverse 5 .. 1 loop
      v_l := public._agenda_dia_de(v_pn, v_de, k);
      exit when char_length(public._agenda_juntar(v_l, null)) <= v_max;
    end loop;
    v_r := jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, v_max), 'dados', jsonb_build_object('dia', v_de));
  else
    v_rota := 'semana';
    v_r := public.agenda_semana(v_de, v_ate, p_hoje);
    -- FASE 3: com a agenda automática ligada, a frase do livre da semana é a da simulação do motor
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,livre}', '') is not null
       and position((v_r #>> '{dados,textos,livre}') in (v_r ->> 'texto')) > 0 then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(v_r ->> 'texto', v_r #>> '{dados,textos,livre}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6; Fase 5, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; FASE 5: foco clientes (com ou sem os; a OS concluída também) → as mensagens ao cliente (_agenda_ver_clientes); foco fora da lista (os 18) lança 22023. Devolve {ok, texto, dados, rota}.';

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
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*.';

create or replace function public._agenda_mudancas(p_de date, p_ate date, p_executada boolean, p_fechamento boolean,
                                                   p_agora timestamptz default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a ordem de gravação criada_em, OS, id): o que a agenda mudou sozinha (motor e vigia; fora do fechamento também o replano da conferência) com agenda_acoes.dia em [p_de, p_ate], em grupos — a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela. Fase 4, P3: também a ação material da nota importada e da mensagem do fornecedor (origens nota e fornecedor). p_executada false = o que a sombra teria feito; p_fechamento = só o não contado e não desfeito, só motor e vigia. [{grupo, tipo, proposta_id, acao_ids, itens, os, nome, numero, desfazivel, desfeita, em}]. Fase 5, P5: também o que a resposta do cliente mudou (origem cliente: fixar e cliente — o dia confirmado, o pedido de outro dia, o acesso, o opt-out), com as ações do replano dele (depois.replano_acoes) no mesmo grupo (contadas juntas, a frase só a do cliente); o acorde da mensagem ao cliente (tipo cliente, origem vigia, depois.acorde) não é mudança e não entra.';

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
  -- FASE 5: o que foi dito ao cliente e como o serviço é dito a ele
  c_serv_max constant int := 40;   -- estrutural: o serviço aparece duas vezes no aviso de atraso (que tem de caber em 400)
  v_prom   text;
  v_serv   text;
  v_dtp    jsonb;
  -- FASE 5: fim
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
  -- FASE 5: prometido (a data como o dono disse ao cliente) e servico_cliente (como o cliente chama o serviço) saem de d
  -- antes da conferência dos campos; entram no rascunho no fim (v_out), conferidos.
  v_prom := nullif(btrim(coalesce(d ->> 'prometido', '')), '');
  v_serv := nullif(btrim(regexp_replace(coalesce(d ->> 'servico_cliente', ''), '\s+', ' ', 'g')), '');
  d := d - 'prometido' - 'servico_cliente';
  -- FASE 5: fim
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

  -- FASE 5: o que o dono disse ao cliente: a data conferida no trecho e entendida pelo banco (agenda_data_dita: "dia 3" é
  -- firme; "entre 4 e 8/11" e "semana que vem" são faixa), nunca no passado; o serviço como o cliente diz (3 a c_serv_max
  -- caracteres, sem valor, pagamento, número de OS nem link).
  if v_prom is not null then
    v_dtp := public._agenda_data_conferida(v_prom, p_trecho, p_hoje, 'futuro');
    if not (v_dtp ->> 'ok')::boolean then return v_dtp; end if;
    if (v_dtp ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Que dia você disse ao cliente?', v_prom), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('prometido', jsonb_build_object(
      'tipo', case when v_dtp ->> 'de' = v_dtp ->> 'ate' then 'firme' else 'faixa' end,
      'de', v_dtp ->> 'de', 'ate', v_dtp ->> 'ate', 'dito', left(v_prom, 60)));
  end if;
  if v_serv is not null then
    if char_length(v_serv) < 3 or char_length(v_serv) > c_serv_max then
      return public._agenda_recusa(format('Diga em poucas palavras como o cliente chama o serviço (até %s letras), por exemplo "a instalação do compressor".',
                                          c_serv_max), 'servico_longo');
    end if;
    if public._agenda_cliente_texto_proibido(v_serv) is not null then
      return public._agenda_recusa('Como o cliente chama o serviço não leva valor, pagamento, número de OS nem link: diga só o serviço ("a troca das baterias").',
                                   'servico_proibido');
    end if;
    v_out := v_out || jsonb_build_object('servico_cliente', v_serv);
  end if;
  -- FASE 5: fim
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
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o que o dono disse do serviço vira RASCUNHO (nada em os_planejamento). p_dados: dias, com_quem [{pessoa, turnos dia|manha|tarde}], dono (abre_e_fecha|sempre|nunca), precisa_ate, bem_fora, bem_livre_em, nao_antes_de + nao_antes_motivo, escopo_em_aberto, escopo_decidido, congelar_ate + revisar_em, prioridade 1–3, sem_material, aceitar_sugestao, adiantavel_patio (dias que dá para adiantar no pátio sem o bem; Fase 2), limpar (espera, nao_antes, prazo, escopo, patio). OS e pessoas resolvidas no banco (ambíguo/não achado = pergunta, nada no rascunho); dias, dias no pátio e datas têm de estar no trecho; datas por agenda_data_dita. Devolve {ok, item, releitura} ou {ok:false, pergunta, opcoes}. Fase 5 (P5): prometido (a data que o cliente OUVIU, como o dono disse: "dia 3" firme, "entre 4 e 8/11" ou "semana que vem" faixa; conferida no trecho, nunca no passado) e servico_cliente (como o cliente chama o serviço, 3 a 40 caracteres, sem valor, número de OS nem link).';

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
  -- FASE 5: o prometido de antes e o gravado
  v_prom_antes jsonb;
  v_prom      jsonb;
  -- FASE 5: fim
begin
  if not exists (select 1 from public.service_orders where id = p_os) then
    raise exception 'o serviço % não existe mais', coalesce(d ->> 'numero', p_os::text) using errcode = 'P0001';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  -- FASE 5: o que o dono disse ao cliente vira o prometido (fonte dono; a 1ª promessa fica em prometido_original_ate; o
  -- histórico ganha a linha própria, pelo _agenda_cliente_gravar_prometido). Gravado antes de ler a linha: o diff abaixo é
  -- só do resto. Só o prometido na linha = nada mais a gravar.
  if jsonb_typeof(d -> 'prometido') = 'object' then
    select jsonb_build_object('tipo', pl.prometido_tipo, 'de', pl.prometido_de, 'ate', pl.prometido_ate, 'fonte', pl.prometido_fonte)
      into v_prom_antes from public.os_planejamento pl where pl.service_order_id = p_os;
    v_prom := public._agenda_cliente_gravar_prometido(p_os, d #>> '{prometido,tipo}', (d #>> '{prometido,de}')::date,
                (d #>> '{prometido,ate}')::date, 'dono', null,
                coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now()), p_trecho);
    if not (d ?| array['dias', 'equipe', 'dono', 'precisa_ate', 'bem', 'nao_antes_de', 'escopo_em_aberto', 'escopo_decidido',
                       'congelada_ate', 'prioridade', 'sem_material', 'adiantavel_patio', 'servico_cliente']) then
      return jsonb_build_object('antes', jsonb_build_object('prometido', v_prom_antes), 'depois', jsonb_build_object('prometido', v_prom));
    end if;
  end if;
  -- FASE 5: fim
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
  -- FASE 5: como o serviço é dito ao cliente
  if d ? 'servico_cliente' then
    v_new.servico_cliente := d ->> 'servico_cliente';
  end if;
  -- FASE 5: fim

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
         -- FASE 5: como o serviço é dito ao cliente
         servico_cliente = v_new.servico_cliente,
         -- FASE 5: fim
         trecho = public._agenda_corta(p_trecho, 500),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = now(), atualizado_por = p_autor
   where service_order_id = p_os;
  return jsonb_build_object('antes', v_antes, 'depois', v_depois);
end;
$function$;

comment on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): grava em os_planejamento (e os_planejamento_equipe) uma linha de rascunho planejar — só os campos ditos (Fase 2: adiantavel_patio → adiantavel_patio_dias); a equipe dita substitui a anterior. Histórico {em, autor, trecho, antes, depois} com só o que mudou (os 20 mais novos). Só pelo agenda_rascunho_gravar; só service_role. Fase 5 (P5): prometido → os_planejamento.prometido_* pelo _agenda_cliente_gravar_prometido (fonte dono; o original só na 1ª vez; linha própria no histórico); servico_cliente → os_planejamento.servico_cliente.';

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
  -- FASE 4: (P3) de onde veio o aviso ("nota 51038 da Kamell", "Pix de R$ 480,00 à Premel, seg 26/10").
  v_aviso  text;
  -- FASE 4: fim
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
    -- FASE 5: o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)") e como o serviço é dito a ele
    if jsonb_typeof(p_d -> 'prometido') = 'object' then
      v_partes := v_partes || format('você disse ao %s: %s (%s)', coalesce(nullif(p_d ->> 'curto', ''), 'cliente'),
        case when p_d #>> '{prometido,de}' = p_d #>> '{prometido,ate}' then public._dia_curto((p_d #>> '{prometido,ate}')::date)
             else format('de %s a %s', public._dia_curto((p_d #>> '{prometido,de}')::date),
                         public._dia_curto((p_d #>> '{prometido,ate}')::date)) end,
        case when p_d #>> '{prometido,tipo}' = 'firme' then 'data firme' else 'uma faixa' end);
    end if;
    if nullif(p_d ->> 'servico_cliente', '') is not null then
      v_partes := v_partes || format('o serviço, para o cliente: %s', p_d ->> 'servico_cliente');
    end if;
    -- FASE 5: fim
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
    -- FASE 4: (P3) o aviso (a nota, o Pix ou a mensagem que a agenda perguntou) diz de onde veio; o fornecedor já está nele.
    if jsonb_typeof(p_d -> 'aviso') = 'object' then
      v_aviso := p_d -> 'aviso' ->> 'curto';
      v_t := case
        when coalesce((p_d ->> 'nota_chegou')::boolean, false) then
          format('na mão desde %s (a %s entrou no estoque)', public._dia_curto((p_d ->> 'chegou_em')::date), v_aviso)
        when p_d ->> 'acao' = 'na_mao' and p_d ->> 'quantidade_na_mao' is null then
          format('na mão desde %s (%s)', case when (p_d ->> 'chegou_em')::date = v_hoje then 'hoje'
                                              else public._dia_curto((p_d ->> 'chegou_em')::date) end, v_aviso)
        when p_d ->> 'acao' = 'a_caminho' and p_d -> 'aviso' ->> 'tipo' = 'nfe' then
          'a caminho pela ' || v_aviso
          || case when p_d ->> 'previsao_ate' is null then ', sem previsão de chegada'
                  when p_d ->> 'previsao_fonte' = 'dono' then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)'
                  else ', chega por volta de ' || public._dia_curto((p_d ->> 'previsao_ate')::date) end
        when p_d ->> 'acao' = 'a_caminho' and p_d ->> 'previsao_ate' is not null and p_d ->> 'previsao_fonte' = 'fornecedor' then
          format('a caminho, chega por volta de %s (%s)', public._dia_curto((p_d ->> 'previsao_ate')::date), v_aviso)
        when p_d ->> 'acao' = 'comprado' and p_d -> 'aviso' ->> 'tipo' = 'pix' and p_d ->> 'previsao_ate' is null
             and v_aviso like 'Pix %' then
          'comprado pelo ' || v_aviso
        else coalesce(v_t || ' (' || v_aviso || ')', v_t) end;
      if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
        v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
      end if;
      return v_t;
    end if;
    -- FASE 4: fim
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

  -- FASE 4: o prazo do fornecedor chega com a frase pronta do banco (agenda_rascunho_fornecedor).
  if p_tipo = 'fornecedor' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 4: (P3) "não é material de serviço" (a nota, o Pix ou a mensagem) chega com a frase pronta (agenda_rascunho_material).
  if p_tipo = 'aviso' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento), o prazo do fornecedor (Fase 4) e o "não é de serviço" (tipo aviso, Fase 4, P3) trazem a frase pronta (dados.frase_pronta); o material com o aviso diz de onde veio ("a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10", "na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10)", "na mão desde qua 28/10 (a nota 51038 da Kamell entrou no estoque)"). Fase 5 (P5): o planejar diz o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)"; faixa: "de qua 04/11 a dom 08/11 (uma faixa)") e como o serviço é dito a ele ("o serviço, para o cliente: a instalação do compressor").';

-- ── 6. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- As palavras e a ferramenta: security definer, conferem o administrador (_autor_da_agenda); authenticated (o painel) e
-- service_role (o WhatsApp). Nunca anon.
revoke all on function
  public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz)
  from public, anon;
grant execute on function
  public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz)
  to authenticated, service_role;

-- As leituras e os textos (o foco confere quem vê antes de tudo; a linha do fechamento é invoker, com a RLS de quem lê):
-- authenticated e service_role; nunca anon.
revoke all on function
  public._agenda_ver_clientes(uuid, date), public._agenda_cliente_fechamento(date),
  public._agenda_cliente_efeito_texto(text), public._agenda_cliente_teria_feito(text, date)
  from public, anon;
grant execute on function
  public._agenda_ver_clientes(uuid, date), public._agenda_cliente_fechamento(date),
  public._agenda_cliente_efeito_texto(text), public._agenda_cliente_teria_feito(text, date)
  to authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar):
revoke all on function
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date), public._agenda_linhas_do_fechamento(date),
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz),
  public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)
  from public, anon;
grant execute on function
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date), public._agenda_linhas_do_fechamento(date),
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz),
  public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)
  to authenticated, service_role;
revoke all on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date), public._agenda_rascunho_frase(text, jsonb)
  from public, anon, authenticated;
grant execute on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date), public._agenda_rascunho_frase(text, jsonb)
  to service_role;
