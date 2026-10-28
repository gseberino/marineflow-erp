-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), correção C2 da revisão: a rodada, os textos e o miúdo. Fontes:
-- scratchpad agenda-pesquisa/revisao-fase5-correcao.md (itens 1, 3, 4, 6, 7, 8, 12, 15, 22, 23 e 24),
-- revisao-fase5-regressao.md (B3) e decisoes-correcao-fase5.md (seção C2). Depende de 20261028100000 a 100700.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (1 CHECK ampliado, 1 índice novo; 3 funções novas; 25 funções recriadas; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/c2f5/montar-migration.mjs: as partes escritas à mão
-- e os corpos das funções recriadas copiados da definição MAIS NOVA de cada uma — a 20261028100700 (C1) incluída —, com
-- cada troca "-- CORREÇÃO FASE 5:" conferida (fora dos blocos nenhuma linha muda; os blocos da C1 ficam iguais):
--   _agenda_cliente_texto                                              ← 20261028100100 (P1)
--   _agenda_cliente_texto_do_aviso, _perguntar, _registrar, _enviada, _fila ← 20261028100200 (P2)
--   _agenda_cliente_ouviu, _risco, _acorde, _material, _mudanca_no_dia, _atraso, _andamento, _pronto, _pos_servico
--                                                                      ← 20261028100300 (P3)
--   agenda_cliente_preparar, agenda_cliente_decidir_dito, _agenda_cliente_fechamento ← 20261028100500 (P5)
--   _agenda_cliente_da_os                                              ← 20261028100600 (P6)
--   _agenda_cliente_revalidar, _enfileirar, _decidir, _confirmar, _motivo_texto, agenda_resposta_do_cliente
--                                                                      ← 20261028100700 (C1)
--
-- POR QUE: a revisão achou o M10 que vai de verdade a quem só recebeu a mensagem em teste (item 1, alta), o aviso de atraso
-- aprovado depois do dia que morre calado (3), um cliente com o texto que não fecha derrubando o passo para todos (4), o
-- "precisou passar para" o mesmo dia (6), a data firme do dono que nunca sai (7), a peça sem previsão dita com data (8), o
-- "Bom dia" às 14h (12), "ao Lucenira" (15), o pós-serviço a quem não pegou o barco (22), o 2º atraso que conta o pedido do
-- cliente (23) e a OS faturada sem "ficou pronto" (24); a regressão, o cartão que monta o foco inteiro e o d10 que varre o
-- ano de mensagens (B3).
--
-- O QUE MUDA:
--   1. (item 1) _agenda_cliente_ouviu: a mensagem que só existiu em teste conta como "o cliente ouviu" só enquanto
--      modo_cliente está fora de ligado. Ligado, só o que saiu (ou o client_confirmed_for): o M10 e o M3/M7 não vão a quem
--      nunca recebeu aquele dia.
--   2. (item 3) a) _agenda_cliente_enfileirar: a livre ou aprovada cujo dia marcado passou e que ainda vale ganha a próxima
--      hora possível de agora e segue (não é mais recusada por "janela"); b) o passo atraso: o aviso de atraso de agora que
--      não saiu (recusado pelo canal ou pelo provedor), com a data ainda por vir, abre uma vez a pergunta "não saiu"
--      (cliente_resposta:nao_saiu:<mensagem>, a mesma chave da C1) e o acorde se a data é em até 1 dia útil; a linha da fila
--      que o provedor não entregou (failed) deixa a mensagem recusada com o motivo novo "entrega" (passo fila, CHECK
--      ampliado); c) _agenda_cliente_decidir diz o motivo verdadeiro (_agenda_cliente_motivo_texto).
--   3. (item 4) os passos material, mudanca_no_dia, confirmar, atraso, andamento, pronto e pos_servico: cada OS num bloco;
--      o erro de uma vai a app_error_logs (agenda / cliente:<passo>:os, por _agenda_cliente_erro_da_os) e o passo segue;
--      erros_os nas contagens.
--   4. (item 6) o M6 remarcado com o mesmo início que o cliente ouviu: a forma "fim" ("{nome}, {servico} vai precisar de
--      mais um dia: agora fica de {dia} até {fim}. …"), com o fim em base (a revalidação compara o último dia).
--   5. (item 7) a data firme que o dono manda dizer (cliente_avisar firme: firme_do_dono) não passa pelo passo do material
--      da revalidação.
--   6. (item 8) peça crítica sem previsão (com outra com previsão): a variante peca_sem_data, condicional e sem data
--      ("… ainda faltam peças {d}o serviço sem data de chegada, então {servico}, que estava {dito}, vai atrasar. …"); ao
--      sair, o prometido da OS fica nulo (_agenda_cliente_tirar_prometido): a nova data vem pelo M7.
--   7. (item 12) a saudação da véspera, do acesso e do M10 de chuva pela hora do envio ("Bom dia" antes das 12:00, "Boa
--      tarde" depois), em p_dados.saudacao.
--   8. (item 15) o texto ao dono sem artigo antes do nome (não há gênero no cadastro): as perguntas e os acordes da mensagem
--      ao cliente (_agenda_cliente_sem_artigo em _agenda_cliente_perguntar e _agenda_cliente_acorde), a ação do envio e a da
--      sombra, a decisão, o *segura cliente*, a preparada, o texto da resposta ao dono e o fechamento; o aviso crítico com o
--      serviço sem o possessivo do cliente.
--   9. (item 22) sem entrega registrada, o pós-serviço só sai se não há "ficou pronto" nem lembrete enviado sem resposta.
--  10. (item 23) o "2º atraso" conta só os avisos de atraso e as novas datas que saíram.
--  11. (item 24) a OS faturada (invoiced) vale como concluída no "ficou pronto", no lembrete, no pós-serviço e na
--      revalidação.
--  12. (B3) o índice agenda_wa_recebidas_por_chave (a chave do telefone das mensagens recebidas) serve ao d10 como ele está;
--      o cartão conta o que espera o dono direto nas tabelas, sem montar o foco inteiro.
--
-- O QUE NÃO MUDA: o envio continua só pela agenda (as três travas, o modo, as ondas, a aprovação); os textos ao cliente
-- fora dos itens 6, 8 e 12; a resposta do cliente (C1); com modo_cliente desligado, nada é registrado.
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, cobrança ou orçamento.
--
-- DECISÕES (anotadas em notas-fase5.md, parte C2):
--   · Item 1: a sombra conta pelo modo da RODADA (modo_cliente), não pelo modo que o tipo teria — a assinatura de
--     _agenda_cliente_ouviu não muda (os corpos copiados a chamam com 3 argumentos). A diferença só aparece com
--     modo_cliente ligado e o tipo ainda em teste, e aí a mensagem que deixa de ser registrada também seria só em teste:
--     nunca muda um envio de verdade.
--   · Item 3b: a pergunta é cliente_resposta (sem opções: "recomendo você ligar hoje"), não cliente_aviso — a opção 2
--     ("eu mando o aviso escrito") não serve quando o aviso não consegue sair.
--   · Item 6: "forma fim" dentro da variante remarcado (não uma variante nova): o SIM, o "ouviu" e a substituição do M1
--     continuam valendo para ela como para o remarcado.
--   · Item 8: só quando ALGUM crítico tem data e outro não (com nenhum, continua sem_data: a vigia pede a previsão). O
--     prometido nulo (o original também — o CHECK prometido_original exige o prometido): o histórico guarda o de antes.
--   · Item 15: o nome sem artigo vale nas perguntas e nos acordes (todas as da mensagem ao cliente passam por
--     _agenda_cliente_perguntar/_agenda_cliente_acorde), na ação do envio e na da sombra, na decisão, no *segura cliente*,
--     na preparada e no fechamento. Ficam com o artigo, para a Fase 6: as ações da resposta e do *desfaz*
--     (agenda_resposta_do_cliente, _agenda_cliente_confirmar_dia, _anotar_acesso, _desfazer_cliente), as recusas da
--     ferramenta cliente_avisar e o foco/cartão ("O que foi dito a ele") — cada uma pediria recriar a função só pelo texto,
--     e os pronomes ("ele", "a ele") ficam.
--   · Item 4: o foco clientes não ganhou a linha "Não consigo mandar (o texto não fecha)": o erro fica em app_error_logs
--     (a saúde conta cliente:% em 24 h).
--
-- ORDEM DE LIGAR: depois de 20261028100000 a 100700; o task-automations novo (o passo do cliente que cala sem a migration)
-- pode ir antes ou depois.
--
-- PROVA: supabase/tests/agenda_fase5_correcao_rodada.sql (C2a–C2z) e os ajustes de texto nos testes da Fase 5. Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261028100000 a 100700):
--   npx supabase db query --linked -f supabase/migrations/20261028100800_agenda_fase5_correcao_rodada.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100800', 'agenda_fase5_correcao_rodada');"
--
-- DESFAZER: reaplicar as definições de onde cada uma foi copiada (a lista acima); drop index agenda_wa_recebidas_por_chave;
-- o CHECK de recusa_motivo volta à lista sem "entrega" só se nenhuma linha a usar. As 3 funções novas ficam (sem quem as
-- chame, nada muda).
--
-- IDEMPOTENTE: drop/add constraint pelo nome, create index if not exists, create or replace function, revoke/grant e
-- comment.

-- ── 1. A estrutura: o motivo novo e o índice da conversa ────────────────────────────────────────────────

-- (item 3) A linha da fila que o provedor não entregou (o worker desiste: failed) deixa a mensagem recusada com o motivo
-- novo "entrega" (antes ela ficava enfileirada para sempre: o gatilho do envio só olha sent). A lista fechada ganha o
-- motivo (drop/add pelo nome: o CHECK nasceu na coluna, em 20261028100000).
do $$
begin
  alter table public.agenda_cliente_mensagens drop constraint if exists agenda_cliente_mensagens_recusa_motivo_check;
  alter table public.agenda_cliente_mensagens add constraint agenda_cliente_mensagens_recusa_motivo_check
    check (recusa_motivo in ('modo', 'tipo_em_teste', 'opt_out', 'sem_telefone', 'sem_conversa', 'domingo', 'feriado', 'janela',
                             'teto_dia', 'teto_semana', 'teto_total', 'intervalo', 'mesmo_tipo_24h', 'status', 'data_mudou',
                             'material', 'passou_da_data', 'desatualizada', 'segurada', 'vencida', 'texto', 'entrega'));
end
$$;

-- (regressão B3) _agenda_cliente_conversou (o d10: o cliente escreveu para a HBR no último ano?) varria todo o último ano
-- de whatsapp_messages calculando a chave do telefone em cada linha (28 ms por chamada em produção, crescendo com a base;
-- o cartão, o foco e o enfileirar a chamam). O índice de expressão com a MESMA chave (_agenda_chave_telefone, immutable)
-- das mensagens recebidas serve à consulta como ela está (nenhuma função muda por ele).
create index if not exists agenda_wa_recebidas_por_chave
  on public.whatsapp_messages (public._agenda_chave_telefone(phone_normalized), occurred_at)
  where direction = 'inbound';

comment on index public.agenda_wa_recebidas_por_chave is
  'Agenda de Produção (Fase 5, correção C2, B3): as mensagens recebidas pela chave do telefone (os 8 últimos dígitos, _agenda_chave_telefone) e a hora — o d10 (_agenda_cliente_conversou) e a conversa do cliente sem varrer a tabela.';

-- ── 2. As funções novas ─────────────────────────────────────────────────────────────────────────────────

-- (item 15) O texto ao dono sem artigo antes do nome do cliente: não há campo de gênero, e "ao Lucenira" / "o Lucenira"
-- soa errado. Com o 1º nome do cliente da OS (o mesmo das mensagens): "O Flávio respondeu" → "Flávio respondeu", "ao
-- Nelson" → "para Nelson", "do Nelson" → "de Nelson", "para o Nelson" / "aviso o Nelson" → "para Nelson" / "aviso Nelson".
-- Só o nome inteiro (palavra) do cliente daquela OS muda; o resto do texto fica igual.
create or replace function public._agenda_cliente_sem_artigo(p_texto text, p_os uuid)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_nome text;
  v_re   text;
  v      text := p_texto;
begin
  if p_texto is null or p_os is null then
    return p_texto;
  end if;
  select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) into v_nome
    from public.service_orders so join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  if coalesce(btrim(v_nome), '') = '' then
    return p_texto;
  end if;
  -- o nome como expressão regular (os caracteres especiais escapados)
  v_re := regexp_replace(v_nome, '([][\\.^$*+?(){}|-])', '\\\1', 'g');
  v := regexp_replace(v, '\mO ' || v_re || '\M', v_nome, 'g');
  v := regexp_replace(v, '\mao ' || v_re || '\M', 'para ' || v_nome, 'g');
  v := regexp_replace(v, '\mdo ' || v_re || '\M', 'de ' || v_nome, 'g');
  v := regexp_replace(v, '\mo ' || v_re || '\M', v_nome, 'g');
  return v;
end;
$function$;

comment on function public._agenda_cliente_sem_artigo(text, uuid) is
  'Agenda de Produção (Fase 5, correção C2, item 15): o texto ao dono sem artigo antes do 1º nome do cliente da OS (não há campo de gênero) — "O Flávio respondeu" → "Flávio respondeu", "ao Nelson" → "para Nelson", "do Nelson" → "de Nelson", "o Nelson" → "Nelson". Só o nome inteiro do cliente daquela OS muda. Interna (sem grant): as perguntas e os acordes da mensagem ao cliente (_agenda_cliente_perguntar, _agenda_cliente_acorde), a decisão, o envio e a sombra a chamam.';

-- (item 8) A mensagem "ainda faltam peças sem data" (o M6 peca_sem_data) não diz data: ao sair, o que o cliente tinha
-- ouvido deixa de valer — o prometido da OS fica nulo (o histórico guarda o de antes). Sem prometido, a rodada não manda
-- outro aviso de atraso nem a pergunta "a data passou sem aviso"; quando as peças chegarem, o passo material manda a nova
-- data (M7: o aviso de atraso foi enviado).
create or replace function public._agenda_cliente_tirar_prometido(p_os uuid, p_mensagem uuid, p_agora timestamptz,
                                                                  p_trecho text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  p public.os_planejamento%rowtype;
begin
  select * into p from public.os_planejamento where service_order_id = p_os for update;
  if not found or p.prometido_ate is null then
    return jsonb_build_object('tirou', false, 'motivo', 'sem_prometido');
  end if;
  update public.os_planejamento
     set prometido_tipo = null, prometido_de = null, prometido_ate = null, prometido_original_ate = null,
         prometido_em = p_agora, prometido_fonte = null, prometido_mensagem_id = p_mensagem,
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'autor', null,
           'trecho', public._agenda_corta(p_trecho, 500),
           'antes', jsonb_build_object('prometido_tipo', p.prometido_tipo, 'prometido_de', p.prometido_de,
                                       'prometido_ate', p.prometido_ate, 'prometido_original_ate', p.prometido_original_ate,
                                       'prometido_fonte', p.prometido_fonte),
           'depois', jsonb_build_object('prometido_tipo', null, 'prometido_de', null, 'prometido_ate', null,
                                        'prometido_fonte', null))),
         atualizado_em = p_agora
   where service_order_id = p_os;
  return jsonb_build_object('tirou', true, 'os', p_os, 'antes_ate', p.prometido_ate);
end;
$function$;

comment on function public._agenda_cliente_tirar_prometido(uuid, uuid, timestamptz, text) is
  'Agenda de Produção (Fase 5, correção C2, item 8): a mensagem que saiu dizendo que ainda não há data (o M6 peca_sem_data) tira o que foi dito ao cliente — os_planejamento.prometido_* (e o original) ficam nulos, o histórico guarda o de antes. Sem prometido, a rodada não avisa atraso de novo nem pergunta "passou sem aviso"; a nova data vem pelo passo material (M7). Interna (sem grant): o gatilho do envio a chama.';

-- (item 4) O erro de UMA OS num passo da rodada do cliente (o texto que não fecha, o proibido — um barco chamado "Bravo
-- 20155" faz o texto ter 5 dígitos seguidos): vai a app_error_logs (context agenda, action cliente:<passo>:os, o número
-- da OS na mensagem e no details) e o passo segue para as outras. O log agrupa o mesmo erro (occurrences), sem uma linha
-- nova a cada tique.
create or replace function public._agenda_cliente_erro_da_os(p_passo text, p_os uuid, p_estado text, p_msg text, p_hoje date)
 returns void
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
begin
  perform public.log_app_error('db',
    format('mensagem ao cliente, passo %s, %s: %s', p_passo,
           coalesce((select so.service_order_number from public.service_orders so where so.id = p_os), 'a OS ' || p_os::text),
           p_msg),
    'agenda', 'cliente:' || p_passo || ':os', 'error',
    jsonb_build_object('passo', p_passo, 'os', p_os, 'sqlstate', p_estado, 'p_hoje', p_hoje));
end;
$function$;

comment on function public._agenda_cliente_erro_da_os(text, uuid, text, text, date) is
  'Agenda de Produção (Fase 5, correção C2, item 4): registra em app_error_logs (agenda / cliente:<passo>:os) o erro de uma OS num passo da rodada do cliente — o passo segue para as outras OS. Interna (sem grant): os passos a chamam.';

-- ── 3. As funções recriadas (o corpo da definição mais nova, a 100700 incluída; as mudanças marcadas "-- CORREÇÃO
-- FASE 5:") ──
-- Fora dos blocos nenhuma linha muda (o C2z do teste confere; o C1z da correção C1 continua valendo para as que ela
-- recriou). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- _agenda_cliente_texto
create or replace function public._agenda_cliente_texto(p_tipo text, p_variante text, p_os uuid, p_dados jsonb,
                                                        p_hoje date default public._hoje_brt())
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  x        jsonb := public._agenda_cliente_contexto(p_os, p_hoje);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  v_var    text := nullif(btrim(coalesce(p_variante, '')), '');
  v_nome   text := x ->> 'nome';
  v_prim   boolean := coalesce((d ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  v_envio  date := coalesce((d ->> 'envio')::date, p_hoje);
  v_dia    date := coalesce((d ->> 'dia')::date, (x ->> 'dia')::date);
  v_fim    date := coalesce((d ->> 'fim')::date, (x ->> 'fim')::date);
  v_n      int := coalesce((d ->> 'n')::int, (x ->> 'n_dias')::int);
  v_serv   text := x ->> 'servico';
  v_art    text := x ->> 'servico_artigo';
  v_esta   text;
  v_jan    text;
  v_dito_de  date;
  v_dito_ate date;
  v_assin  text;
  v_abre   text;
  v_resto  text;
  v_falta  text;
begin
  if p_tipo is null or p_tipo not in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                      'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia') then
    raise exception using errcode = '22023', message = format('Tipo de mensagem ao cliente desconhecido: %s.', p_tipo);
  end if;
  if p_tipo = 'confirmar' then
    v_var := coalesce(v_var, case when v_prim then 'primeira' else 'seguinte' end);
  end if;
  -- CORREÇÃO FASE 5: os dados novos da correção C2 — a saudação (item 12: "Bom dia" ou "Boa tarde", da hora do envio) e a
  -- forma "fim" do aviso remarcado (item 6) — só valem onde existem
  if d ? 'saudacao' and coalesce(d ->> 'saudacao', '') not in ('Bom dia', 'Boa tarde') then
    raise exception using errcode = '22023', message = format('Saudação %s não existe na mensagem ao cliente.', d ->> 'saudacao');
  end if;
  if d ? 'forma' and (p_tipo <> 'pode_atrasar' or v_var is distinct from 'remarcado' or coalesce(d ->> 'forma', '') <> 'fim') then
    raise exception using errcode = '22023',
      message = format('A forma %s não existe na mensagem %s.', coalesce(d ->> 'forma', '(nenhuma)'), p_tipo);
  end if;
  -- (item 8) o aviso de atraso com peça crítica ainda sem data de chegada (variante peca_sem_data, d09): nenhuma data — nem
  -- a da peça, nem a nova do serviço —, só o que o cliente ouviu ("que estava para quinta (05/11)")
  if p_tipo = 'pode_atrasar' and v_var = 'peca_sem_data' then
    if v_nome is null then
      raise exception using errcode = '22023', message = 'Falta o nome do cliente para a mensagem pode_atrasar ao cliente.';
    end if;
    if d ? 'dito_de' or d ? 'dito_ate' then
      v_dito_de := (d ->> 'dito_de')::date; v_dito_ate := (d ->> 'dito_ate')::date;
    elsif d ? 'dia_dito' then
      v_dito_de := (d ->> 'dia_dito')::date; v_dito_ate := v_dito_de;
    else
      v_dito_de := (x #>> '{prometido,de}')::date; v_dito_ate := (x #>> '{prometido,ate}')::date;
    end if;
    if coalesce(v_dito_de, v_dito_ate) is null then
      raise exception using errcode = '22023', message = 'Falta o dia dito ao cliente para a mensagem pode_atrasar ao cliente.';
    end if;
    v_resto := format('quero te avisar com antecedência: ainda faltam peças %s sem data de chegada, então %s, que estava %s, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.',
                      x ->> 'do_servico', v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true));
    if v_prim then
      return format('Olá, %s! %s %s', v_nome,
                    case when x ->> 'dono' is not null then format('Aqui é o %s, da %s.', x ->> 'dono', x ->> 'empresa')
                         else format('Aqui é da %s.', x ->> 'empresa') end,
                    upper(left(v_resto, 1)) || substr(v_resto, 2));
    end if;
    return v_nome || ', ' || v_resto;
  end if;
  -- CORREÇÃO FASE 5: fim
  if (p_tipo = 'confirmar' and v_var not in ('primeira', 'seguinte', 'unico'))
     or (p_tipo = 'pode_atrasar' and coalesce(v_var, '') not in ('peca', 'execucao', 'remarcado'))
     or (p_tipo = 'andamento' and coalesce(v_var, '') not in ('primeiro_dia', 'semanal'))
     or (p_tipo = 'mudanca_no_dia' and coalesce(v_var, '') not in ('clima', 'equipe', 'geral'))
     or (p_tipo in ('vespera', 'acesso', 'material_chegou', 'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico')
         and v_var is not null) then
    raise exception using errcode = '22023', message = format('Variante %s não existe na mensagem %s.', coalesce(v_var, '(nenhuma)'), p_tipo);
  end if;

  v_jan := case d ->> 'janela' when 'manha' then 'pela manhã' when 'tarde' then 'à tarde' when 'dia' then 'o dia todo'
           else public._agenda_cliente_janela(p_os, v_dia) end;
  v_esta := case when v_art in ('os', 'as') then 'estão' else 'está' end;
  if d ? 'dito_de' or d ? 'dito_ate' then
    v_dito_de := (d ->> 'dito_de')::date; v_dito_ate := (d ->> 'dito_ate')::date;
  elsif d ? 'dia_dito' then
    v_dito_de := (d ->> 'dia_dito')::date; v_dito_ate := v_dito_de;
  else
    v_dito_de := (x #>> '{prometido,de}')::date; v_dito_ate := (x #>> '{prometido,ate}')::date;
  end if;

  -- O que cada modelo precisa (o 1º que faltar).
  v_falta := case
    when v_nome is null then 'o nome do cliente'
    when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then
      case when v_dia is null then 'o dia' when v_jan is null then 'a parte do dia (as alocações do dia)'
           when p_tipo = 'confirmar' and v_var <> 'unico' and coalesce(v_n, 0) < 1 then 'os dias de trabalho'
           when p_tipo = 'mudanca_no_dia' and coalesce(d ->> 'quando', '') not in ('hoje', 'amanhã') then 'o quando (hoje ou amanhã)'
           when p_tipo = 'pode_atrasar' and coalesce(v_dito_de, v_dito_ate) is null then 'o dia dito ao cliente' end
    when p_tipo = 'pode_atrasar' and v_var = 'peca' then
      case when coalesce((d ->> 'peca_de')::date, (d ->> 'peca_ate')::date) is null then 'a previsão da peça'
           when coalesce((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date) is null then 'a faixa nova'
           when coalesce(v_dito_de, v_dito_ate) is null then 'o dia dito ao cliente' end
    when p_tipo = 'pode_atrasar' and v_var = 'execucao' then
      case when coalesce((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date) is null then 'a faixa nova' end
    when p_tipo = 'andamento' then
      case when v_fim is null then 'o fim previsto'
           when v_var = 'semanal' and ((d ->> 'n_feitos') is null or coalesce(v_n, 0) < 1) then 'os dias feitos e o total'
           when v_var = 'primeiro_dia' and coalesce(d ->> 'quando', 'hoje') not in ('hoje', 'ontem') then 'o quando (hoje ou ontem)' end
  end;
  if v_falta is not null then
    raise exception using errcode = '22023', message = format('Falta %s para a mensagem %s ao cliente.', v_falta, p_tipo);
  end if;

  v_assin := case when x ->> 'dono' is not null then format('Aqui é o %s, da %s.', x ->> 'dono', x ->> 'empresa')
                  else format('Aqui é da %s.', x ->> 'empresa') end;

  -- O corpo e como ele abre: 'nome' ("{nome}, …"), 'bom_dia' ("Bom dia, {nome}! …"), 'bom_dia_ponto' ("Bom dia, {nome}.
  -- …"), 'boa_noticia' ("Boa notícia, {nome}: …") ou 'pronto' (o M1 primeira e seguinte, inteiros).
  case p_tipo
    when 'confirmar' then
      if v_var = 'primeira' then
        v_abre := 'pronto';
        v_resto := format('Olá, %s! %s Conseguimos encaixar %s para %s, %s, com previsão de %s de trabalho. Pode ser? Responda SIM para confirmar, ou me diga um dia melhor. A partir de agora te mando por aqui as novidades do serviço.',
                          v_nome, v_assin, v_serv, public._agenda_cliente_dia(v_dia), v_jan,
                          v_n || case when v_n = 1 then ' dia' else ' dias' end);
      elsif v_var = 'seguinte' then
        v_abre := 'pronto';
        v_resto := format('%s, conseguimos encaixar %s para %s, %s, com previsão de %s. Pode ser? Responda SIM ou me diga um dia melhor.',
                          v_nome, v_serv, public._agenda_cliente_dia(v_dia), v_jan,
                          v_n || case when v_n = 1 then ' dia' else ' dias' end);
      else
        v_abre := 'nome';
        v_resto := format('%s fica para %s, %s%s. Pode ser? Responda SIM, ou me diga se algo mudou.',
                          v_serv, public._agenda_cliente_dia(v_dia), v_jan, x ->> 'local');
      end if;
    when 'vespera' then
      v_abre := 'bom_dia';
      v_resto := format('%s chegamos %s para %s%s. Está tudo certo para recebermos? Responda SIM, ou me avise se algo mudou.',
                        public._agenda_cliente_dia_relativo(v_dia, v_envio), v_jan, v_serv, x ->> 'local');
    when 'acesso' then
      v_abre := 'bom_dia';
      v_resto := format('%s chegamos %s para %s. Para não perdermos a viagem: onde %s vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.',
                        public._agenda_cliente_dia_relativo(v_dia, v_envio), v_jan, v_serv, x ->> 'o_bem');
    when 'material_chegou' then
      v_abre := 'boa_noticia';
      v_resto := format('o material %s chegou e já foi conferido. Podemos começar %s, %s? Responda SIM, ou me diga um dia melhor.',
                        x ->> 'do_servico', public._agenda_cliente_dia(v_dia), v_jan);
    when 'pode_atrasar' then
      v_abre := 'nome';
      if v_var = 'peca' then
        v_resto := format('quero te avisar com antecedência: a peça %s ainda não chegou e agora está prevista %s. Por isso, %s, que estava %s, deve ficar %s. Te confirmo a data assim que a peça chegar. Se isso atrapalhar algum plano seu, me diga.',
                          x ->> 'do_servico',
                          public._agenda_cliente_faixa((d ->> 'peca_de')::date, (d ->> 'peca_ate')::date, true),
                          v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true),
                          public._agenda_cliente_faixa((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date, true));
      elsif v_var = 'execucao' then
        v_resto := format('%s %s levando mais tempo do que eu estimei. A nova previsão para terminar é %s. Qualquer dúvida, me chama.',
                          v_serv, v_esta, public._agenda_cliente_faixa((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date));
      else
        v_resto := format('%s, que estava %s, precisou passar para %s, %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                          v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true), public._agenda_cliente_dia(v_dia), v_jan);
        -- CORREÇÃO FASE 5: (item 6) o remarcado em que o início é o mesmo que o cliente ouviu e só o FIM mudou (a forma fim):
        -- dizer que "precisou passar para" o mesmo dia de início confunde
        if d ->> 'forma' = 'fim' then
          if v_fim is null then
            raise exception using errcode = '22023', message = 'Falta o fim novo para a mensagem pode_atrasar ao cliente.';
          end if;
          v_resto := format('%s vai precisar de mais um dia: agora fica de %s até %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                            v_serv, public._agenda_cliente_dia(v_dia), public._agenda_cliente_dia(v_fim));
        end if;
        -- CORREÇÃO FASE 5: fim
      end if;
    when 'nova_data' then
      v_abre := 'nome';
      v_resto := format('agora com data firme: %s fica para %s, %s. Desculpe pela mudança e obrigado pela paciência. Responda SIM para confirmar, ou me diga se precisa de outro dia.',
                        v_serv, public._agenda_cliente_dia(v_dia), v_jan);
    when 'andamento' then
      v_abre := 'nome';
      if v_var = 'primeiro_dia' then
        v_resto := format('começamos %s %s. Seguimos com a previsão de terminar %s.',
                          coalesce(d ->> 'quando', 'hoje'), v_serv, public._agenda_cliente_dia(v_fim));
      else
        v_resto := format('seguimos com %s: %s de %s dias feitos, previsão de terminar %s.',
                          v_serv, (d ->> 'n_feitos')::int, v_n, public._agenda_cliente_dia(v_fim));
      end if;
    when 'pronto' then
      v_abre := 'nome';
      v_resto := format('%s %s %s. Quando fica bom para combinarmos a entrega?', v_serv, v_esta,
                        case v_art when 'a' then 'concluída' when 'os' then 'concluídos' when 'as' then 'concluídas' else 'concluído' end);
    when 'pronto_lembrete' then
      v_abre := 'nome';
      v_resto := format('só para combinarmos a entrega %s: qual dia fica bom pra você?', x ->> 'do_bem');
    when 'pos_servico' then
      v_abre := 'nome';
      v_resto := format('tudo certo com %s? Já deu para usar? Se algo não estiver como esperado, me responde aqui que a gente resolve. Se preferir não receber estas mensagens, é só responder PARAR.',
                        v_serv);
    else -- mudanca_no_dia
      if v_var = 'clima' then
        v_abre := 'bom_dia_ponto';
        v_resto := format('Com a chuva de %s não dá para trabalhar %s com segurança. Podemos passar para %s, %s? Responda SIM ou me diga outro dia.',
                          d ->> 'quando', x ->> 'no_bem', public._agenda_cliente_dia(v_dia), v_jan);
      else
        v_abre := 'nome';
        v_resto := format('tive um imprevisto%s e não vamos conseguir ir %s. Desculpe o transtorno. Podemos ir %s, %s? Responda SIM ou me diga outro dia.',
                          case when v_var = 'equipe' then ' com a equipe' else '' end, d ->> 'quando',
                          public._agenda_cliente_dia(v_dia), v_jan);
      end if;
  end case;

  -- CORREÇÃO FASE 5: (item 12) a saudação pela hora em que a mensagem SAI (o registrar grava p_dados.saudacao: "Bom dia"
  -- antes do meio-dia, "Boa tarde" depois); sem ela, "Bom dia" (como as registradas antes desta correção)
  if v_abre in ('bom_dia', 'bom_dia_ponto') then
    return format('%s, %s%s %s', coalesce(nullif(d ->> 'saudacao', ''), 'Bom dia'), v_nome,
                  case when v_abre = 'bom_dia' then '!' else '.' end,
                  case when v_prim then v_assin || ' ' else '' end || v_resto);
  end if;
  -- CORREÇÃO FASE 5: fim
  return case v_abre
    when 'pronto' then v_resto
    when 'nome' then case when v_prim then format('Olá, %s! %s %s', v_nome, v_assin, upper(left(v_resto, 1)) || substr(v_resto, 2))
                          else v_nome || ', ' || v_resto end
    when 'bom_dia' then format('Bom dia, %s! %s', v_nome, case when v_prim then v_assin || ' ' else '' end || v_resto)
    when 'bom_dia_ponto' then format('Bom dia, %s. %s', v_nome, case when v_prim then v_assin || ' ' else '' end || v_resto)
    else case when v_prim then format('Olá, %s! %s Boa notícia: %s', v_nome, v_assin, v_resto)
              else format('Boa notícia, %s: %s', v_nome, v_resto) end
  end;
end;
$function$;

comment on function public._agenda_cliente_texto(text, text, uuid, jsonb, date) is
  'Agenda de Produção (Fase 5): a mensagem-modelo ao cliente (spec §6.1), pronta, com os dados do banco — tipos confirmar (M1: primeira, seguinte, unico; nula = primeira ou seguinte pelo contexto), vespera (M2), acesso (M4), material_chegou (M3), pode_atrasar (M6: peca, execucao, remarcado), nova_data (M7), andamento (M5: primeiro_dia, semanal), pronto e pronto_lembrete (M8), pos_servico (M9) e mudanca_no_dia (M10: clima, equipe, geral). p_dados = o que o passo calculou (envio, primeira, dia, fim, janela, n, n_feitos, quando, faixa_de/ate, peca_de/ate, dito_de/ate ou dia_dito); o que faltar sai do contexto (_agenda_cliente_contexto). Assinatura só na 1ª mensagem. Lança 22023 com o tipo ou a variante que não existe e quando falta um dado; nunca devolve texto pela metade. CORREÇÃO FASE 5 (C2): (item 12) p_dados.saudacao ("Bom dia" | "Boa tarde"; padrão "Bom dia") abre a véspera, o acesso e o M10 de chuva; (item 6) p_dados.forma = fim no M6 remarcado com o mesmo início ("{nome}, {servico} vai precisar de mais um dia: agora fica de {dia} até {fim}. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia."); (item 8) M6 peca_sem_data, sem data ("{nome}, quero te avisar com antecedência: ainda faltam peças {d}o serviço sem data de chegada, então {servico}, que estava {dito}, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.").';

-- _agenda_cliente_texto_do_aviso
create or replace function public._agenda_cliente_texto_do_aviso(p_motivo text, p_tipo text, p_os uuid, p_dados jsonb,
                                                                 p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  x       jsonb := public._agenda_cliente_contexto(p_os, p_hoje);
  d       jsonb := coalesce(p_dados, '{}'::jsonb);
  v_nome  text := coalesce(x ->> 'nome', 'cliente');
  v_serv  text := x ->> 'servico';
  v_de    date;
  v_ate   date;
  v_fde   date;
  v_fate  date;
  v_dito  text;
  v_faixa text;
  v_opc   constant text := ' 1) Você liga e eu não mando nada (recomendo); 2) Eu mando o aviso escrito; 3) Não aviso agora.';
begin
  if d ? 'dito_de' or d ? 'dito_ate' then
    v_de := (d ->> 'dito_de')::date; v_ate := (d ->> 'dito_ate')::date;
  elsif d ? 'dia_dito' then
    v_de := (d ->> 'dia_dito')::date; v_ate := v_de;
  else
    v_de := (x #>> '{prometido,de}')::date; v_ate := (x #>> '{prometido,ate}')::date;
  end if;
  v_fde := coalesce((d ->> 'faixa_de')::date, (d ->> 'dia')::date, (x ->> 'dia')::date);
  v_fate := coalesce((d ->> 'faixa_ate')::date, v_fde);
  v_dito := case when coalesce(v_de, v_ate) is null then 'a data dita'
                 else public._agenda_faixa_texto(coalesce(v_de, v_ate), 'manha', coalesce(v_ate, v_de), 'tarde') end;
  v_faixa := case when v_fde is null then 'sem data' else public._agenda_faixa_texto(v_fde, 'manha', v_fate, 'tarde') end;
  -- CORREÇÃO FASE 5: (item 15) ao dono, o serviço sem o possessivo do cliente ("o serviço no seu veleiro" é como o cliente
  -- ouve): o serviço como o dono disse ao cliente (servico_cliente), senão "o serviço da OS-00112"; e sem artigo antes do
  -- nome (não há gênero no cadastro): "… de Nelson", "A data que Nelson ouviu", "Nelson já recebeu"
  select coalesce(nullif(btrim(pl.servico_cliente), ''), 'o serviço da ' || so.service_order_number) into v_serv
    from public.service_orders so left join public.os_planejamento pl on pl.service_order_id = so.id
   where so.id = p_os;
  v_serv := coalesce(v_serv, 'o serviço');
  v_serv := upper(left(v_serv, 1)) || substr(v_serv, 2);
  return left(case p_motivo
    when 'segundo_atraso' then format('%s de %s vai atrasar de novo (%s → %s). É o 2º atraso: recomendo você ligar.%s',
                                      v_serv, v_nome, v_dito, v_faixa, v_opc)
    when 'atraso_longo' then format('%s de %s vai atrasar %s dias (%s → %s): recomendo você ligar.%s',
                                    v_serv, v_nome, coalesce(d ->> 'atraso_dias', '?'), v_dito, v_faixa, v_opc)
    when 'passou' then format('A data que %s ouviu (%s) passou sem aviso. Recomendo você ligar hoje.%s', v_nome, v_dito, v_opc)
    else format('%s de %s não cabe: %s já recebeu %s esta semana. Recomendo você ligar.%s',
                case when p_tipo = 'mudanca_no_dia' then 'O aviso da mudança no dia' else 'O aviso de atraso' end, v_nome, v_nome,
                case when (d ->> 'mensagens_na_semana') = '1' then '1 mensagem'
                     else coalesce(d ->> 'mensagens_na_semana', 'as') || ' mensagens' end, v_opc)
  end, 600);
  -- CORREÇÃO FASE 5: fim
  v_serv := upper(left(v_serv, 1)) || substr(v_serv, 2);
  return left(case p_motivo
    when 'segundo_atraso' then format('%s do %s vai atrasar de novo (%s → %s). É o 2º atraso: recomendo você ligar.%s',
                                      v_serv, v_nome, v_dito, v_faixa, v_opc)
    when 'atraso_longo' then format('%s do %s vai atrasar %s dias (%s → %s): recomendo você ligar.%s',
                                    v_serv, v_nome, coalesce(d ->> 'atraso_dias', '?'), v_dito, v_faixa, v_opc)
    when 'passou' then format('A data que o %s ouviu (%s) passou sem aviso. Recomendo você ligar hoje.%s', v_nome, v_dito, v_opc)
    else format('%s do %s não cabe: ele já recebeu %s esta semana. Recomendo você ligar.%s',
                case when p_tipo = 'mudanca_no_dia' then 'O aviso da mudança no dia' else 'O aviso de atraso' end, v_nome,
                case when (d ->> 'mensagens_na_semana') = '1' then '1 mensagem'
                     else coalesce(d ->> 'mensagens_na_semana', 'as') || ' mensagens' end, v_opc)
  end, 600);
end;
$function$;

comment on function public._agenda_cliente_texto_do_aviso(text, text, uuid, jsonb, date) is
  'Agenda de Produção (Fase 5, P2): o texto da pergunta crítica cliente_aviso (spec §6.2) — segundo_atraso ("… vai atrasar de novo (qui 05/11 → qui 12 a sex 13/11). É o 2º atraso: recomendo você ligar."), atraso_longo, passou e teto, sempre com as 3 opções (1 recomendada). O dito e a faixa na forma do dono (_agenda_faixa_texto). CORREÇÃO FASE 5 (C2, item 15): o serviço como o dono disse ao cliente (servico_cliente), senão "o serviço da OS-00112" — nunca o possessivo do cliente — e sem artigo antes do nome ("A instalação do compressor de Flávio vai atrasar de novo…", "A data que Nelson ouviu…", "O aviso de atraso de Nelson não cabe: Nelson já recebeu 1 mensagem esta semana…").';

-- _agenda_cliente_perguntar
create or replace function public._agenda_cliente_perguntar(p_tipo_pergunta text, p_chave text, p_os uuid, p_dia date,
                                                            p_perda date, p_texto text, p_modo text, p_agora timestamptz,
                                                            p_expira timestamptz)
 returns uuid
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  -- CORREÇÃO FASE 5: (item 15) a pergunta ao dono sem artigo antes do nome do cliente ("Mensagem para Lucenira", "Flávio
  -- respondeu…", "A data que Nelson ouviu…"): não há gênero no cadastro
  p_texto := public._agenda_cliente_sem_artigo(p_texto, p_os);
  -- CORREÇÃO FASE 5: fim
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao,
                                       recomendacao_texto, modo, criada_em, expira_em)
  values (p_tipo_pergunta, left(p_chave, 200), p_os, array[p_os], p_dia, p_perda, left(public._agenda_corta(p_texto, 600), 600),
          case when p_tipo_pergunta = 'cliente_aviso' then jsonb_build_array(
                 jsonb_build_object('n', 1, 'texto', 'Você liga e eu não mando nada', 'efeito', jsonb_build_object('mensagem', 'segura')),
                 jsonb_build_object('n', 2, 'texto', 'Eu mando o aviso escrito agora', 'efeito', jsonb_build_object('mensagem', 'manda')),
                 jsonb_build_object('n', 3, 'texto', 'Não aviso agora', 'efeito', jsonb_build_object('mensagem', 'segura')))
               else '[]'::jsonb end,
          case when p_tipo_pergunta = 'cliente_aviso' then 1 end,
          case when p_tipo_pergunta = 'cliente_aviso' then 'Recomendo você ligar: um aviso escrito agora pesa mais do que uma ligação.' end,
          p_modo, p_agora, p_expira)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  if v_id is null then
    select q.id into v_id from public.agenda_perguntas q where q.chave = left(p_chave, 200) and q.modo = p_modo and q.estado = 'aberta';
  end if;
  return v_id;
end;
$function$;

comment on function public._agenda_cliente_perguntar(text, text, uuid, date, date, text, text, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 5, P2): abre a pergunta de uma mensagem ao cliente e devolve o id — cliente_aprovar (sem opções: *manda cliente* / *segura cliente*) ou cliente_aviso (crítica: 1 você liga e eu não mando nada, recomendada; 2 eu mando o aviso escrito; 3 não aviso agora). A mesma chave aberta devolve a pergunta que já estava. Interna (sem grant). CORREÇÃO FASE 5 (C2, item 15): o texto da pergunta sai sem artigo antes do 1º nome do cliente da OS (_agenda_cliente_sem_artigo).';

-- _agenda_cliente_registrar
create or replace function public._agenda_cliente_registrar(p_tipo text, p_variante text, p_os uuid, p_dia_alvo date,
                                                            p_dados jsonb, p_alvo timestamptz, p_valida_ate timestamptz,
                                                            p_origem text, p_critica text default null,
                                                            p_agora timestamptz default now(), p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor: o que sai até o próximo entra na fila agora
  v_hoje  date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_dados jsonb := coalesce(p_dados, '{}'::jsonb) - 'primeira' - 'envio' - 'chave' - 'prometido_tipo';
  x       jsonb;
  v_cli   uuid;
  v_modo  text;
  v_chave text;
  v_id    uuid := gen_random_uuid();
  v_ja    uuid;
  v_enviar timestamptz;
  v_valida timestamptz;
  v_prim  boolean;
  v_var   text := nullif(btrim(coalesce(p_variante, '')), '');
  v_txt   text;
  v_proib text;
  v_prom  text;
  v_aprov text;
  v_estado text := 'registrada';
  v_recusa text;
  v_perg  uuid;
  v_base  jsonb;
  v_r     jsonb;
  v_acao  uuid;
  v_aut   uuid;
  -- CORREÇÃO FASE 5: (item 12) a hora do meio-dia da saudação ("Bom dia" antes, "Boa tarde" depois: é o português, não
  -- um parâmetro da agenda nem o fim do turno da manhã)
  c_meio_dia_h constant int := 12;
  -- CORREÇÃO FASE 5: fim
begin
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  if p_origem is null or p_origem not in ('rodada', 'dono', 'botao') then
    raise exception 'A mensagem ao cliente vem da rodada, do dono ou do botão (veio %).', coalesce(p_origem, 'nada') using errcode = '22023';
  end if;
  if p_critica is not null and p_critica not in ('segundo_atraso', 'atraso_longo', 'passou', 'teto') then
    raise exception 'Motivo de aviso crítico desconhecido: %.', p_critica using errcode = '22023';
  end if;
  if p_alvo is null then
    raise exception 'A mensagem ao cliente veio sem a hora.' using errcode = '22023';
  end if;
  select so.client_id into v_cli from public.service_orders so where so.id = p_os;
  if v_cli is null then
    raise exception 'A mensagem ao cliente veio sem a OS (ou a OS sem cliente).' using errcode = '22023';
  end if;
  x := public._agenda_cliente_contexto(p_os, v_hoje);

  -- o modo da linha: ligado só com modo_cliente ligado E o tipo na lista das ondas; senão em teste (a chave com :sombra)
  v_modo := case when cf.modo_cliente = 'ligado' and p_tipo = any (cf.cliente_tipos_ligados) then 'ligado' else 'sombra' end;
  v_chave := format('agenda-cliente:%s:%s:%s', p_tipo, p_os,
                    coalesce(nullif(btrim(p_dados ->> 'chave'), ''), p_dia_alvo::text,
                             to_char(p_alvo at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')))
             || case when v_modo = 'sombra' then ':sombra' else '' end;
  select m.id into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave;
  if v_ja is not null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe', 'id', v_ja);
  end if;

  -- a hora (a janela, o feriado, o intervalo) e o texto contado do dia em que ele SAI (o "Amanhã"), com a assinatura só na
  -- 1ª mensagem; o registro guarda os dois (a revalidação recalcula com eles)
  v_enviar := public._agenda_cliente_quando(hashtext(v_chave), p_alvo, p_agora);
  -- CORREÇÃO FASE 5: (item 12) a saudação dos que abrem com ela (a véspera, o acesso e a mudança no dia por chuva) segue a
  -- hora em que a mensagem SAI (Brasília): "Bom dia" antes do meio-dia, "Boa tarde" depois. Fica em p_dados (e em
  -- base.dados): a revalidação recalcula igual, e a hora que muda depois (a conversa viva) não a deixa desatualizada.
  if p_tipo in ('vespera', 'acesso', 'mudanca_no_dia') then
    v_dados := v_dados || jsonb_build_object('saudacao',
                 case when extract(hour from (v_enviar at time zone 'America/Sao_Paulo')) < c_meio_dia_h then 'Bom dia'
                      else 'Boa tarde' end);
  end if;
  -- CORREÇÃO FASE 5: fim
  v_prim := coalesce((p_dados ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  if p_tipo = 'confirmar' and v_var is null then
    v_var := case when v_prim then 'primeira' else 'seguinte' end;
  end if;
  v_txt := public._agenda_cliente_texto(p_tipo, v_var, p_os,
             v_dados || jsonb_build_object('primeira', v_prim, 'envio', (v_enviar at time zone 'America/Sao_Paulo')::date), v_hoje);
  v_proib := public._agenda_cliente_texto_proibido(v_txt);
  if v_proib is not null then
    raise exception 'A mensagem ao cliente não pode levar % (o texto: "%").', v_proib, left(v_txt, 120) using errcode = '22023';
  end if;
  -- o que a mensagem DIZ de data (vira o prometido quando sai): firme nos modelos com dia; faixa no atraso da peça e da
  -- execução (condicional, se o passo disser); nada no andamento, no pronto e no pós-serviço
  v_prom := coalesce(nullif(btrim(p_dados ->> 'prometido_tipo'), ''),
                     case when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
                               or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then 'firme'
                          when p_tipo = 'pode_atrasar' then 'faixa' end);
  if v_prom is not null and v_prom not in ('condicional', 'faixa', 'firme') then
    raise exception 'O que a mensagem diz de data é condicional, faixa ou firme (veio %).', v_prom using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 5: (item 8) o aviso "ainda faltam peças sem data" não diz data: não vira prometido (ao sair, o gatilho do
  -- envio tira o que o cliente tinha ouvido)
  if p_tipo = 'pode_atrasar' and v_var = 'peca_sem_data' then
    v_prom := null;
  end if;
  -- CORREÇÃO FASE 5: fim
  v_valida := coalesce(p_valida_ate, public._agenda_cliente_fim_da_janela((v_enviar at time zone 'America/Sao_Paulo')::date, 0));
  v_base := jsonb_build_object(
    'status', x ->> 'status',
    'dia_alvo', coalesce((p_dados ->> 'dia')::date, (x ->> 'dia')::date, p_dia_alvo),
    'fim', coalesce((p_dados ->> 'fim')::date, (x ->> 'fim')::date),
    'nivel', x ->> 'nivel_material',
    'prometido_ate', x #>> '{prometido,ate}',
    'primeira', v_prim,
    'envio', (v_enviar at time zone 'America/Sao_Paulo')::date,
    'referencia', case when x -> 'plano' is null or jsonb_typeof(x -> 'plano') = 'null' then 'agendada' else 'plano' end,
    'dados', v_dados);

  -- a aprovação (em ligado): a crítica pergunta (cliente_aviso); a do dono e a do tipo ainda não liberado pedem *manda
  -- cliente* (cliente_aprovar); a do botão já foi aprovada pelo clique; o resto sai sozinho. Em teste, sempre livre.
  if v_enviar > v_valida then
    v_aprov := 'livre';
    v_estado := 'recusada';
    v_recusa := 'vencida';
  elsif v_modo = 'sombra' then
    v_aprov := 'livre';
  elsif p_critica is not null then
    v_aprov := 'critica';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aviso',
                format('cliente_aviso:%s:%s', p_os, coalesce(p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date)),
                p_os, p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date,
                public._agenda_cliente_texto_do_aviso(p_critica, p_tipo, p_os, p_dados, v_hoje), 'ligado', p_agora, v_valida);
  elsif p_origem = 'botao' then
    v_aprov := 'aprovada';
    v_aut := (select u.id from public.app_users u where u.id = p_autor);
  elsif p_origem = 'dono' or not public._agenda_cliente_tipo_liberado(p_tipo) then
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                case when p_origem = 'dono'
                     then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_quando_texto(v_enviar, p_agora), v_txt, x ->> 'nome')
                     else format('Mensagem para o %s (%s), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_tipo_texto(p_tipo), public._agenda_cliente_quando_texto(v_enviar, p_agora),
                                 v_txt, x ->> 'nome', x ->> 'nome') end,
                'ligado', p_agora, v_valida);
  else
    v_aprov := 'livre';
  end if;

  insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de,
                                               faixa_ate, prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao,
                                               pergunta_id, aprovada_em, aprovada_por, estado, recusa_motivo, dedupe_key,
                                               criada_em)
  values (v_id, v_cli, p_os, p_tipo, v_var, p_origem, p_dia_alvo, (p_dados ->> 'faixa_de')::date,
          (p_dados ->> 'faixa_ate')::date, v_prom, v_modo, v_txt, v_base, v_enviar, v_valida, v_aprov, v_perg,
          case when v_aprov = 'aprovada' then p_agora end, v_aut, v_estado, v_recusa, v_chave, p_agora);

  -- CORREÇÃO FASE 5: (item 15) a linha da sombra sem artigo antes do nome ("Em teste: eu teria mandado para Lucenira …"; a
  -- ação não muda depois de gravada, então ela já nasce assim). O bloco de 20261028100300 logo abaixo não roda mais para a
  -- sombra (v_modo fica 'sombra_feita' só entre os dois blocos).
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado para %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
    v_modo := 'sombra_feita';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- em teste: o que a agenda teria mandado (a linha do que mudou sozinho, sem executar)
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado ao %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
  end if;

  -- CORREÇÃO FASE 5: (item 15) o modo volta a ser o da linha
  if v_modo = 'sombra_feita' then
    v_modo := 'sombra';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- o que sai até o próximo tique entra na fila agora; o de depois fica registrado e o passo "fila" o enfileira na hora
  if v_modo = 'ligado' and v_estado = 'registrada' and v_aprov in ('livre', 'aprovada') and v_enviar <= p_agora + c_tique then
    v_r := public._agenda_cliente_enfileirar(v_id, p_agora);
  end if;
  return jsonb_build_object('criada', true, 'id', v_id, 'modo', v_modo, 'estado', v_estado, 'motivo', v_recusa,
                            'aprovacao', v_aprov, 'pergunta_id', v_perg, 'enviar_em', v_enviar, 'valida_ate', v_valida,
                            'texto', v_txt)
         || coalesce(v_r, '{}'::jsonb);
end;
$function$;

comment on function public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid) is
  'Agenda de Produção (Fase 5, P2): grava a mensagem-modelo ao cliente e decide o envio — desligado = nada; o texto é o do banco (_agenda_cliente_texto, contado do dia do envio, com a assinatura só na 1ª mensagem; o proibido = 22023); o modo da linha: ligado só com modo_cliente ligado E o tipo em cliente_tipos_ligados, senão sombra (chave com :sombra, a ação "Em teste: eu teria mandado…"); a chave agenda-cliente:<tipo>:<os>:<p_dados.chave | dia_alvo | o dia do alvo> (uma só: a 2ª devolve ja_existe); enviar_em pelo _agenda_cliente_quando; valida_ate = p_valida_ate, senão o fim da janela do dia do envio (passou dela = recusada/vencida); a aprovação em ligado: p_critica (segundo_atraso, atraso_longo, passou, teto) = critica + pergunta cliente_aviso; origem dono ou tipo ainda não liberado = pedida + pergunta cliente_aprovar; botão = aprovada (aprovada_por = p_autor); senão livre. base guarda {status, dia_alvo, fim, nivel, prometido_ate, primeira, envio, referencia, dados} para a revalidação. A livre/aprovada que sai até o próximo tique vai a _agenda_cliente_enfileirar. p_dados: os do modelo (dia, fim, janela, n, faixa_de/ate, peca_de/ate, dito_de/ate, dia_dito, quando, n_feitos), primeira, prometido_tipo, chave (o sufixo da chave no lugar do dia: o lembrete e o andamento semanal), atraso_dias (o aviso crítico). Sem grant. CORREÇÃO FASE 5 (C2): (item 12) a véspera, o acesso e a mudança no dia ganham p_dados.saudacao pela hora do envio (Brasília: "Bom dia" antes das 12:00, "Boa tarde" depois), guardada em base.dados; (item 8) o M6 peca_sem_data não tem prometido_tipo; (item 15) a ação da sombra sem artigo antes do nome.';

-- _agenda_cliente_enviada
create or replace function public._agenda_cliente_enviada()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  m      public.agenda_cliente_mensagens%rowtype;
  v_em   timestamptz := coalesce(new.sent_at, now());
  v_nome text;
  v_acao uuid;
  v_ini  timestamptz;
  v_ok   boolean := false;
  v_passo text;
begin
  -- Três passos, cada um no seu bloco: o que falha vai ao log e os outros seguem (a mensagem enviada nunca deixa de ficar
  -- enviada porque o prometido ou a ação falharam).
  if new.source = 'agenda-cliente' then
    begin
      v_passo := 'a mensagem';
      select * into m from public.agenda_cliente_mensagens where id = new.source_ref_id for update;
      if found and m.estado not in ('enviada', 'respondida', 'sem_resposta') then
        -- a verdade é o envio: até a que o passo da fila tinha recusado no meio tempo (a corrida com o worker) fica enviada
        update public.agenda_cliente_mensagens
           set estado = 'enviada', enviada_em = v_em, recusa_motivo = null, fila_id = coalesce(fila_id, new.id)
         where id = m.id;
        v_ok := true;
      end if;
    exception when others then
      perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                   'cliente:enviada', 'error',
                                   jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
    end;
    -- CORREÇÃO FASE 5: (item 8) o aviso "ainda faltam peças sem data" saiu: o que o cliente tinha ouvido deixa de valer (o
    -- prometido fica nulo; a rodada não avisa atraso de novo nem diz "passou sem aviso"; a nova data vem pelo M7)
    if v_ok and m.tipo = 'pode_atrasar' and m.variante = 'peca_sem_data' then
      begin
        v_passo := 'o prometido sem data';
        perform public._agenda_cliente_tirar_prometido(m.service_order_id, m.id, v_em,
                                                       format('mensagem ao cliente (%s): %s', m.modelo, m.texto));
      exception when others then
        perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                     'cliente:enviada', 'error',
                                     jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
      end;
    end if;
    -- CORREÇÃO FASE 5: fim
    if v_ok and m.prometido_tipo is not null then
      begin
        v_passo := 'o prometido';
        perform public._agenda_cliente_prometer(m.id, v_em);
      exception when others then
        perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                     'cliente:enviada', 'error',
                                     jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
      end;
    end if;
    -- CORREÇÃO FASE 5: (item 15) a ação do envio sem artigo antes do nome ("Mandei para Lucenira que o serviço ficou
    -- pronto."; a ação não muda depois de gravada, então ela já nasce assim). O bloco de 20261028100200 logo abaixo não roda
    -- mais (v_ok fica false depois deste; nada mais o lê).
    if v_ok then
      begin
        v_passo := 'a ação';
        select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) into v_nome
          from public.clients cl where cl.id = m.client_id;
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
        values (clock_timestamp(), (v_em at time zone 'America/Sao_Paulo')::date, true, 'vigia', 'cliente',
                m.service_order_id, array[m.service_order_id], '{}'::jsonb,
                jsonb_build_object('mensagem_id', m.id, 'tipo', m.tipo, 'fila_id', new.id, 'enviada_em', v_em),
                left(format('Mandei para %s %s.', coalesce(v_nome, 'o cliente'),
                            public._agenda_cliente_o_que(m.tipo, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo))), 400))
        returning id into v_acao;
        update public.agenda_cliente_mensagens set acao_id = v_acao where id = m.id;
        -- o botão antigo pela agenda (D9): o pedido de confirmação conta de quando a mensagem SAIU
        if m.origem = 'botao' and m.tipo = 'confirmar' then
          update public.service_orders
             set client_confirmation_requested_at = v_em, client_confirmed_at = null, client_confirmed_for = null
           where id = m.service_order_id;
        end if;
      exception when others then
        perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                     'cliente:enviada', 'error',
                                     jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
      end;
      v_ok := false;
    end if;
    -- CORREÇÃO FASE 5: fim
    if v_ok then
      begin
        v_passo := 'a ação';
        select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) into v_nome
          from public.clients cl where cl.id = m.client_id;
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
        values (clock_timestamp(), (v_em at time zone 'America/Sao_Paulo')::date, true, 'vigia', 'cliente',
                m.service_order_id, array[m.service_order_id], '{}'::jsonb,
                jsonb_build_object('mensagem_id', m.id, 'tipo', m.tipo, 'fila_id', new.id, 'enviada_em', v_em),
                left(format('Mandei ao %s %s.', coalesce(v_nome, 'cliente'),
                            public._agenda_cliente_o_que(m.tipo, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo))), 400))
        returning id into v_acao;
        update public.agenda_cliente_mensagens set acao_id = v_acao where id = m.id;
        -- o botão antigo pela agenda (D9): o pedido de confirmação conta de quando a mensagem SAIU
        if m.origem = 'botao' and m.tipo = 'confirmar' then
          update public.service_orders
             set client_confirmation_requested_at = v_em, client_confirmed_at = null, client_confirmed_for = null
           where id = m.service_order_id;
        end if;
      exception when others then
        perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                     'cliente:enviada', 'error',
                                     jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
      end;
    end if;
  elsif new.source_ref_id is not null then
    -- D9: o botão antigo (agenda-confirmacao) também é data dita ao cliente
    begin
      v_passo := 'o prometido do botão';
      v_ini := coalesce(public._agenda_cliente_dia_a_confirmar(new.source_ref_id, v_em),
                        (select so.scheduled_start_at from public.service_orders so where so.id = new.source_ref_id));
      if v_ini is not null then
        perform public._agenda_cliente_prometer_confirmacao(new.source_ref_id, v_ini, v_em);
      end if;
    exception when others then
      perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                   'cliente:enviada', 'error',
                                   jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
    end;
  end if;
  return null;
end;
$function$;

comment on function public._agenda_cliente_enviada() is
  'Agenda de Produção (Fase 5, P2): gatilho AFTER UPDATE OF status de whatsapp_send_queue, só para source agenda-cliente e agenda-confirmacao, quando a linha vira sent — agenda-cliente: a mensagem fica enviada (enviada_em = sent_at), a que diz data vira o prometido da OS (_agenda_cliente_prometer), e a ação tipo cliente (origem vigia, executada, sem desfazer: "Mandei ao Nelson a confirmação de qui 05/11.") conta no fechamento; a do botão (origem botao) marca o pedido de confirmação da OS; agenda-confirmacao (o botão antigo, D9): o prometido firme do dia confirmado (_agenda_cliente_dia_a_confirmar, senão scheduled_start_at). Nunca lança: o erro vai a app_error_logs (agenda / cliente:enviada). CORREÇÃO FASE 5 (C2): (item 8) o M6 peca_sem_data enviado tira o prometido da OS (_agenda_cliente_tirar_prometido); (item 15) a ação "Mandei para Nelson …" sem artigo antes do nome.';

-- _agenda_cliente_fila
create or replace function public._agenda_cliente_fila(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor
  r       record;
  v_mot   text;
  v_res   jsonb;
  n_modo  int := 0;
  n_jan   int := 0;
  n_reval int := 0;
  n_fila  int := 0;
  n_espera int := 0;
  n_recus int := 0;
  n_venc  int := 0;
  -- CORREÇÃO FASE 5: (item 3) as que o provedor não entregou
  n_entrega int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  -- (1) e (2): as linhas pendentes
  for r in
    select q.id, q.scheduled_for, m.id as msg, m.tipo, m.enviar_em
      from public.whatsapp_send_queue q
      left join public.agenda_cliente_mensagens m on m.id = q.source_ref_id
     where q.source = 'agenda-cliente' and q.status = 'pending'
     order by q.scheduled_for, q.id
  loop
    v_mot := case
      when r.msg is null then 'janela'
      when cf.modo_cliente <> 'ligado' then 'modo'
      when not (r.tipo = any (cf.cliente_tipos_ligados)) then 'tipo_em_teste'
      when r.scheduled_for <= p_agora and public._agenda_cliente_fora_da_janela(r.enviar_em, p_agora) is not null then 'janela'
    end;
    if v_mot is not null then
      if v_mot = 'janela' then n_jan := n_jan + 1; else n_modo := n_modo + 1; end if;
    else
      v_mot := public._agenda_cliente_revalidar(r.msg, p_agora);
      if v_mot is not null then
        n_reval := n_reval + 1;
      end if;
    end if;
    if v_mot is not null then
      update public.whatsapp_send_queue
         set status = 'failed', failed_reason = 'agenda-cliente: não saiu (' || v_mot || ')'
       where id = r.id and status = 'pending';
      update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = v_mot
       where id = r.msg and estado = 'enfileirada';
    end if;
  end loop;
  -- CORREÇÃO FASE 5: (item 3) a linha que o provedor não entregou (o worker desistiu depois das tentativas: failed) não
  -- deixa a mensagem "enfileirada" para sempre (o gatilho do envio só olha sent): fica recusada com o motivo entrega — a
  -- aprovada pelo dono avisa pelo gatilho do "não saiu" (C1); o aviso de atraso, pelo passo atraso
  for r in
    select m.id from public.agenda_cliente_mensagens m
      join public.whatsapp_send_queue q on q.source = 'agenda-cliente' and q.source_ref_id = m.id
     where m.estado = 'enfileirada' and q.status = 'failed'
     order by m.enviar_em, m.id
  loop
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'entrega'
     where id = r.id and estado = 'enfileirada';
    if found then n_entrega := n_entrega + 1; end if;
  end loop;
  -- CORREÇÃO FASE 5: fim
  -- (3) o que é hora de mandar
  if cf.modo_cliente = 'ligado' then
    for r in
      select m.id from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('livre', 'aprovada')
         and m.estado in ('registrada', 'aguardando_dono') and m.enviar_em <= p_agora + c_tique
       order by m.enviar_em, m.id
    loop
      v_res := public._agenda_cliente_enfileirar(r.id, p_agora);
      case v_res ->> 'estado'
        when 'enfileirada' then n_fila := n_fila + 1;
        when 'recusada' then n_recus := n_recus + 1;
        else n_espera := n_espera + 1;
      end case;
    end loop;
  end if;
  -- (4) a validade: a que não saiu a tempo vence (a esperando o dono, com a pergunta)
  for r in
    select m.id, m.aprovacao, m.pergunta_id from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono') and m.valida_ate < p_agora
     order by m.enviar_em, m.id
  loop
    update public.agenda_cliente_mensagens
       set estado = 'recusada', recusa_motivo = 'vencida',
           aprovacao = case when r.aprovacao in ('pedida', 'critica') then 'vencida' else aprovacao end
     where id = r.id;
    if r.aprovacao in ('pedida', 'critica') and r.pergunta_id is not null then
      update public.agenda_perguntas
         set estado = 'vencida', resolvida_motivo = 'a mensagem ao cliente venceu sem a resposta do dono'
       where id = r.pergunta_id and estado = 'aberta';
    end if;
    n_venc := n_venc + 1;
  end loop;
  -- CORREÇÃO FASE 5: (item 3) a entrega que falhou nas contagens
  return jsonb_build_object('canceladas', n_modo + n_jan + n_reval, 'pelo_modo', n_modo, 'pela_janela', n_jan,
                            'revalidadas', n_reval, 'enfileiradas', n_fila, 'esperando', n_espera, 'recusadas', n_recus,
                            'vencidas', n_venc, 'entrega', n_entrega);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('canceladas', n_modo + n_jan + n_reval, 'pelo_modo', n_modo, 'pela_janela', n_jan,
                            'revalidadas', n_reval, 'enfileiradas', n_fila, 'esperando', n_espera, 'recusadas', n_recus,
                            'vencidas', n_venc);
end;
$function$;

comment on function public._agenda_cliente_fila(date, timestamptz) is
  'Agenda de Produção (Fase 5, P2), passo do cliente "fila" (roda sempre, até com tudo desligado; a rodada do P3 o chama antes de tudo): (1) a linha agenda-cliente pendente sem a mensagem, com modo_cliente ou o tipo fora de ligado, ou que já devia ter saído e agora está fora da janela dela, vira failed e a mensagem fica recusada (janela, modo, tipo_em_teste); (2) a pendente que a revalidação recusa vira failed/recusada com o motivo; (3) em ligado, a registrada (ou esperando o dono e já aprovada) livre ou aprovada com enviar_em até o próximo tique vai a _agenda_cliente_enfileirar; (4) a registrada ou esperando o dono que passou de valida_ate fica recusada/vencida (a pedida ou crítica com a aprovação vencida e a pergunta vencida). {canceladas, pelo_modo, pela_janela, revalidadas, enfileiradas, esperando, recusadas, vencidas}. CORREÇÃO FASE 5 (C2, item 3): antes do (3), a enfileirada cuja linha da fila o provedor não entregou (failed) fica recusada com o motivo entrega; a contagem entrega.';

-- _agenda_cliente_motivo_texto
create or replace function public._agenda_cliente_motivo_texto(p_motivo text)
 returns text
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf public.agenda_config := public._agenda_cfg();
begin
  return case
    when p_motivo = 'sem_conversa'
      then format('o cliente não escreveu para a HBR nos últimos %s dias, e mensagem automática a quem não escreve arrisca o número',
                  cf.cliente_conversa_dias)
    when p_motivo = 'sem_telefone' then 'o cadastro do cliente está sem telefone válido (ou o número é de alguém da HBR)'
    when p_motivo = 'opt_out' then 'o cliente pediu para não receber WhatsApp'
    when p_motivo in ('teto_dia', 'teto_semana')
      then format('o cliente já recebeu as mensagens que cabem (no máximo %s por dia e %s por semana)', cf.cliente_dia_max,
                  cf.cliente_semana_max)
    when p_motivo = 'teto_total' then format('a agenda já mandou as %s mensagens do dia aos clientes', cf.cliente_total_dia_max)
    -- o motivo mesmo_tipo_<horas> (a lista fechada de recusa_motivo); as horas vêm de cliente_mesmo_tipo_horas
    when left(p_motivo, 10) = 'mesmo_tipo'
      then format('o cliente já recebeu uma mensagem do mesmo tipo nas últimas %s horas', cf.cliente_mesmo_tipo_horas)
    when p_motivo = 'material' then 'o material ainda não está todo na mão, e a data não é firme'
    when p_motivo in ('status', 'data_mudou', 'desatualizada') then 'a OS mudou antes de a mensagem sair'
    when p_motivo = 'passou_da_data' then 'a data que o cliente ouviu já passou'
    when p_motivo in ('domingo', 'feriado', 'janela', 'vencida')
      then 'passou da hora de a mensagem servir sem ela sair (o horário de mensagens ao cliente acabou)'
    when p_motivo = 'intervalo' then 'outra mensagem a cliente estava saindo na mesma hora'
    when p_motivo in ('modo', 'tipo_em_teste') then 'as mensagens ao cliente voltaram para teste'
    when p_motivo = 'texto' then 'o texto da mensagem não fecha'
    -- CORREÇÃO FASE 5: (item 3) o provedor do WhatsApp não entregou
    when p_motivo = 'entrega' then 'o WhatsApp não conseguiu entregar a mensagem'
    -- CORREÇÃO FASE 5: fim
    else coalesce(p_motivo, 'sem motivo') end;
end;
$function$;

comment on function public._agenda_cliente_motivo_texto(text) is
  'Agenda de Produção (Fase 5, correção C1): o motivo da recusa de uma mensagem ao cliente (recusa_motivo) como o dono lê, depois de "não saiu: …" — "o cliente não escreveu para a HBR nos últimos 365 dias…", "o cliente já recebeu as mensagens que cabem (no máximo 1 por dia e 3 por semana)", "a OS mudou antes de a mensagem sair"… Os números vêm de agenda_config. Interna (sem grant). CORREÇÃO FASE 5 (C2, item 3): entrega = "o WhatsApp não conseguiu entregar a mensagem".';

-- _agenda_cliente_revalidar
create or replace function public._agenda_cliente_revalidar(p_msg uuid, p_agora timestamptz default now())
 returns text
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  m      public.agenda_cliente_mensagens%rowtype;
  so     record;
  v_hoje date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_plano jsonb;
  v_agora_dia date;
  v_nivel text;
  v_txt  text;
  v_dados jsonb;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  if not found then
    return 'desatualizada';
  end if;
  -- 1. o cliente pediu para não receber (ou o cadastro saiu)
  if public._agenda_cliente_sem_mensagem(m.client_id) then
    return 'opt_out';
  end if;
  -- CORREÇÃO FASE 5: (item 13) 1b. o d10 também na revalidação — e por isso no gatilho da fila (as duas travas) e no
  -- agenda_cliente_pode_sair (o worker): a quem não escreveu para a HBR em cliente_conversa_dias a mensagem não sai, por
  -- qualquer caminho. Sem telefone válido, o motivo verdadeiro é o telefone (como no enfileirar).
  if not public._agenda_cliente_conversou(m.client_id, p_agora) then
    return case when public._agenda_cliente_telefone(m.client_id) is null then 'sem_telefone' else 'sem_conversa' end;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 2. o status da OS
  select o.status, o.delivered_at, o.scheduled_start_at, o.scheduled_end_at into so
    from public.service_orders o where o.id = m.service_order_id;
  -- CORREÇÃO FASE 5: (item 24) a OS faturada (invoiced) logo depois de concluída vale como concluída — o resto da Fase 5
  -- já a trata assim (a resposta, o cliente_avisar): o "ficou pronto" e o pós-serviço dela saem; o aviso de atraso não
  if found and so.status = 'invoiced' then
    so.status := 'completed';
  end if;
  -- CORREÇÃO FASE 5: fim
  if not found or so.status in ('cancelled', 'draft')
     or (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         and so.status in ('awaiting_parts', 'awaiting_client', 'completed'))
     or (m.tipo = 'andamento' and so.status <> 'in_progress')
     or (m.tipo in ('pronto', 'pronto_lembrete') and (so.status <> 'completed' or so.delivered_at is not null))
     or (m.tipo = 'pos_servico' and so.status <> 'completed')
     or (m.tipo = 'pode_atrasar' and so.status = 'completed') then
    return 'status';
  end if;
  -- 3. a data: o dia de que a mensagem fala (o próximo dia do plano; sem plano no registro, o dia agendado da OS) e, nos
  -- tipos de fim (o andamento e o atraso da execução), o último dia
  v_plano := public._agenda_plano_da_os(m.service_order_id, v_hoje);
  if m.base ? 'dia_alvo'
     and (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
          or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado')) then
    v_agora_dia := case when m.base ->> 'referencia' = 'agendada'
                        then (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date
                        else (v_plano ->> 'proximo_dia')::date end;
    if v_agora_dia is distinct from (m.base ->> 'dia_alvo')::date then
      return 'data_mudou';
    end if;
  end if;
  if m.base ? 'fim' and m.base ->> 'referencia' = 'plano'
     and (m.tipo = 'andamento' or (m.tipo = 'pode_atrasar' and m.variante = 'execucao'))
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  -- CORREÇÃO FASE 5: (item 6) o remarcado em que só o fim mudou (a forma fim) diz o fim: o último dia de agora tem de ser
  -- o dele. (item 7) a data firme que o DONO mandou dizer (cliente_avisar firme: base.dados.firme_do_dono) não passa pelo
  -- passo 4 — o d09 deixa o dono trocar a faixa pela data firme do plano; os passos 1–3 e 5–7 continuam
  if m.tipo = 'pode_atrasar' and m.variante = 'remarcado' and m.base #>> '{dados,forma}' = 'fim'
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  if m.origem = 'dono' and coalesce((m.base #>> '{dados,firme_do_dono}')::boolean, false) then
    m.prometido_tipo := null;   -- só nesta cópia local: o passo 4, abaixo, não vale para ela
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 4. a data firme sem todo o material crítico na mão (d09): o pior nível dos críticos fora de A
  if m.prometido_tipo = 'firme' then
    v_nivel := public.os_prontidao(m.service_order_id, v_hoje) #>> '{material,confianca}';
    if v_nivel is not null and v_nivel <> 'A' then
      return 'material';
    end if;
  end if;
  -- 5. o aviso de atraso depois da data que o cliente ouviu (não sai: vira pergunta crítica na rodada)
  if m.tipo = 'pode_atrasar'
     and exists (select 1 from public.os_planejamento p
                  where p.service_order_id = m.service_order_id and p.prometido_ate < v_hoje) then
    return 'passou_da_data';
  end if;
  -- 6. o mesmo tipo a este cliente nas últimas cliente_mesmo_tipo_horas
  if exists (select 1 from public.agenda_cliente_mensagens x
              where x.client_id = m.client_id and x.tipo = m.tipo and x.id <> m.id and x.enviada_em is not null
                and x.enviada_em > p_agora - make_interval(hours => cf.cliente_mesmo_tipo_horas)) then
    return 'mesmo_tipo_24h';
  end if;
  -- 7. o texto de agora (os mesmos dados, a mesma 1ª mensagem, o dia do envio de agora) ≠ o registrado
  v_dados := coalesce(m.base -> 'dados', '{}'::jsonb)
             || jsonb_build_object('primeira', coalesce((m.base ->> 'primeira')::boolean, false),
                                   'envio', (m.enviar_em at time zone 'America/Sao_Paulo')::date);
  begin
    v_txt := public._agenda_cliente_texto(m.tipo, m.variante, m.service_order_id, v_dados, v_hoje);
  exception when others then
    return 'desatualizada';
  end;
  if v_txt is distinct from m.texto then
    return 'desatualizada';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_cliente_revalidar(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2): a mensagem ao cliente ainda vale em p_agora? null = sai; senão, na ordem: opt_out (_agenda_cliente_sem_mensagem); status (OS cancelada/rascunho; confirmar, véspera, acesso, material chegou, nova data e mudança no dia com a OS aguardando peça, aguardando o cliente ou concluída; andamento fora de in_progress; pronto e lembrete fora de completed ou já entregue; pós-serviço fora de completed; aviso de atraso com a OS concluída); data_mudou (o próximo dia do plano — sem plano no registro, o dia agendado da OS — ≠ base.dia_alvo; no andamento e no atraso da execução, o último dia ≠ base.fim); material (data firme com algum crítico fora de A, os_prontidao); passou_da_data (aviso de atraso com o prometido_ate antes de hoje); mesmo_tipo_24h (outra do mesmo tipo a ele enviada nas últimas cliente_mesmo_tipo_horas); desatualizada (_agenda_cliente_texto com os dados do registro, a 1ª mensagem de base e o dia do envio de agora ≠ o texto registrado, ou o modelo que não fecha mais). STABLE, definer, sem grant (o pode_sair do worker e as travas a chamam). CORREÇÃO FASE 5 (C1, item 13): depois do opt_out, sem_conversa (o d10: _agenda_cliente_conversou em p_agora; sem telefone válido, sem_telefone) — vale também no gatilho da fila e no pode_sair. CORREÇÃO FASE 5 (C2): (item 24) a OS faturada vale como concluída; (item 6) o M6 remarcado na forma fim também recusa data_mudou quando o último dia ≠ base.fim; (item 7) a data firme do dono (origem dono, base.dados.firme_do_dono) não passa pelo passo 4 (material).';

-- _agenda_cliente_enfileirar
create or replace function public._agenda_cliente_enfileirar(p_msg uuid, p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor (task-automations a cada 15 min)
  m       public.agenda_cliente_mensagens%rowtype;
  v_q     timestamptz;
  v_dia   date;
  v_seg   date;
  v_fone  text;
  v_teste boolean;
  v_tent  int;
  v_fila  uuid;
  v_motivo text;
  v_det   text;
  v_novo  timestamptz;
  v_perg  uuid;
  v_n     int;
begin
  -- o teto é contado e a linha entra numa vez só, mesmo com dois tiques ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext('agenda_cliente_fila'));
  select * into m from public.agenda_cliente_mensagens where id = p_msg for update;
  if not found then
    raise exception 'Não encontrei essa mensagem ao cliente.' using errcode = 'P0002';
  end if;
  -- já decidida (o tique seguinte não refaz)
  if m.estado not in ('registrada', 'aguardando_dono') then
    return jsonb_build_object('estado', m.estado, 'motivo', m.recusa_motivo, 'fila_id', m.fila_id);
  end if;
  -- 1. o modo e o tipo: em teste (ou com o modo fora de ligado) fica como está
  if m.modo <> 'ligado' or cf.modo_cliente <> 'ligado' then
    return jsonb_build_object('estado', m.estado, 'motivo', 'modo');
  end if;
  if not (m.tipo = any (cf.cliente_tipos_ligados)) then
    return jsonb_build_object('estado', m.estado, 'motivo', 'tipo_em_teste');
  end if;
  -- 2. a aprovação: esperando o dono fica esperando; segurada ou vencida não sai
  if m.aprovacao in ('pedida', 'critica') then
    if m.estado <> 'aguardando_dono' then
      update public.agenda_cliente_mensagens set estado = 'aguardando_dono' where id = m.id;
    end if;
    return jsonb_build_object('estado', 'aguardando_dono', 'motivo', 'aprovacao', 'pergunta_id', m.pergunta_id);
  end if;
  v_motivo := case when m.aprovacao in ('segurada', 'vencida') then m.aprovacao
                   when greatest(m.enviar_em, p_agora) > m.valida_ate then 'vencida' end;
  -- d19: o cliente (ou o dono com ele) conversando agora — a mensagem espera o próximo tique (não é recusada); se a janela
  -- do dia acabar, a próxima hora de janela, se ainda valer
  if v_motivo is null and cf.cliente_conversa_viva_min > 0
     and exists (select 1 from public.clients c
                   join public.whatsapp_messages w
                     on public._agenda_chave_telefone(w.phone_normalized)
                        in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
                  where c.id = m.client_id and w.occurred_at <= p_agora
                    and w.occurred_at > p_agora - make_interval(mins => cf.cliente_conversa_viva_min)) then
    v_novo := public._agenda_cliente_quando(hashtext(m.dedupe_key), p_agora + c_tique, p_agora, m.id);
    if v_novo > m.valida_ate then
      v_motivo := 'vencida';
    else
      update public.agenda_cliente_mensagens set enviar_em = v_novo where id = m.id;
      return jsonb_build_object('estado', m.estado, 'motivo', 'conversa_viva', 'enviar_em', v_novo);
    end if;
  end if;

  -- CORREÇÃO FASE 5: (item 3a) a mensagem livre ou aprovada cujo DIA marcado já passou (o dono aprovou depois do dia, a
  -- conversa viva a empurrou) e que ainda vale (valida_ate) não é recusada por "janela" ("outro dia que não o da hora
  -- marcada"): ganha a próxima hora possível a partir de agora (a regra única, _agenda_cliente_quando) e segue — a
  -- revalidação de agora decide (o texto com "Amanhã" fica desatualizado, que é o certo). Passou da validade = vencida;
  -- a hora nova depois do próximo tique fica registrada (o passo fila a manda na hora).
  if v_motivo is null and m.aprovacao in ('livre', 'aprovada')
     and (m.enviar_em at time zone 'America/Sao_Paulo')::date < (p_agora at time zone 'America/Sao_Paulo')::date then
    v_novo := public._agenda_cliente_quando(hashtext(m.dedupe_key), p_agora, p_agora, m.id);
    if v_novo > m.valida_ate then
      v_motivo := 'vencida';
    else
      update public.agenda_cliente_mensagens set enviar_em = v_novo where id = m.id;
      m.enviar_em := v_novo;
      if v_novo > p_agora + c_tique then
        return jsonb_build_object('estado', m.estado, 'motivo', 'remarcada', 'enviar_em', v_novo);
      end if;
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  v_q := greatest(m.enviar_em, p_agora);
  v_dia := (m.enviar_em at time zone 'America/Sao_Paulo')::date;
  if v_motivo is null then
    v_motivo := case
      -- 3. o cliente pediu para não receber
      when public._agenda_cliente_sem_mensagem(m.client_id) then 'opt_out'
      -- 4. só a quem já escreveu para a HBR (d10); sem telefone válido nenhum (ou o número é de alguém da HBR), o motivo
      -- verdadeiro é o telefone (o Lenine: sem número, ninguém "conversou")
      when not public._agenda_cliente_conversou(m.client_id, v_q)
        then case when public._agenda_cliente_telefone(m.client_id) is null then 'sem_telefone' else 'sem_conversa' end
      -- 5. a revalidação (o status, a data, o material, a data dita, o mesmo tipo, o texto)
      else public._agenda_cliente_revalidar(m.id, p_agora)
    end;
  end if;
  -- 6. domingo, feriado, a janela (a regra única): no dia marcado, agora ou na hora marcada
  if v_motivo is null then
    v_motivo := public._agenda_cliente_fora_da_janela(m.enviar_em, v_q);
  end if;
  -- 7. o teto: por cliente no dia e na semana ISO, e o total do dia (contados como o gatilho da fila conta)
  if v_motivo is null then
    v_seg := date_trunc('week', v_dia)::date;
    v_n := public._agenda_cliente_no_periodo(m.client_id, v_seg, v_seg + 6, m.id);
    v_motivo := case
      when public._agenda_cliente_no_periodo(m.client_id, v_dia, v_dia, m.id) >= cf.cliente_dia_max then 'teto_dia'
      when v_n >= cf.cliente_semana_max then 'teto_semana'
      when public._agenda_cliente_no_periodo(null, v_dia, v_dia, m.id) >= cf.cliente_total_dia_max then 'teto_total' end;
    -- d13: o aviso que não cabe no teto não fica mudo — vira pergunta crítica ao dono (recomenda ligar); a mensagem espera
    -- a decisão (a opção 2 passa de novo pelo canal: com o teto cheio, não sai)
    if v_motivo is not null and m.tipo in ('pode_atrasar', 'mudanca_no_dia') and m.aprovacao <> 'aprovada' then
      v_perg := public._agenda_cliente_perguntar('cliente_aviso',
                  format('cliente_aviso:%s:%s', m.service_order_id, coalesce(m.dia_alvo, v_dia)), m.service_order_id,
                  coalesce(m.dia_alvo, v_dia), v_dia,
                  public._agenda_cliente_texto_do_aviso('teto', m.tipo, m.service_order_id,
                    coalesce(m.base -> 'dados', '{}'::jsonb) || jsonb_build_object('mensagens_na_semana', v_n),
                    (p_agora at time zone 'America/Sao_Paulo')::date),
                  'ligado', p_agora, m.valida_ate);
      update public.agenda_cliente_mensagens
         set aprovacao = 'critica', pergunta_id = v_perg, estado = 'aguardando_dono'
       where id = m.id;
      return jsonb_build_object('estado', 'aguardando_dono', 'motivo', v_motivo, 'pergunta_id', v_perg);
    end if;
  end if;
  -- CORREÇÃO FASE 5: (item 14) o choque de intervalo REMARCA a hora (o próximo instante longe das outras, pela regra única
  -- _agenda_cliente_quando) em vez de recusar para sempre — a outra marcada pode ser uma nova tentativa (+5 min) que caiu
  -- perto, e a chave desta não volta. A que passaria da validade vence. Fica registrada: o passo fila a enfileira na hora
  -- nova. Só a trava da fila recusa por intervalo (o 8, abaixo, fica como defesa e já não acha nada).
  if v_motivo is null
     and exists (select 1 from public.whatsapp_send_queue q
                  where q.source = 'agenda-cliente' and q.status in ('pending', 'sending')
                    and q.source_ref_id is distinct from m.id
                    and q.scheduled_for > m.enviar_em - make_interval(secs => cf.cliente_intervalo_min_s)
                    and q.scheduled_for < m.enviar_em + make_interval(secs => cf.cliente_intervalo_min_s)) then
    v_novo := public._agenda_cliente_quando(hashtext(m.dedupe_key), m.enviar_em, p_agora, m.id);
    if v_novo > m.valida_ate then
      v_motivo := 'vencida';
    else
      update public.agenda_cliente_mensagens set enviar_em = v_novo where id = m.id;
      return jsonb_build_object('estado', m.estado, 'motivo', 'intervalo', 'enviar_em', v_novo);
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 8. o intervalo: outra linha agenda-cliente pendente ou saindo a menos de cliente_intervalo_min_s
  if v_motivo is null
     and exists (select 1 from public.whatsapp_send_queue q
                  where q.source = 'agenda-cliente' and q.status in ('pending', 'sending')
                    and q.source_ref_id is distinct from m.id
                    and q.scheduled_for > m.enviar_em - make_interval(secs => cf.cliente_intervalo_min_s)
                    and q.scheduled_for < m.enviar_em + make_interval(secs => cf.cliente_intervalo_min_s)) then
    v_motivo := 'intervalo';
  end if;
  -- 9. o telefone dele (nunca o do dono, da equipe nem de quem recebe diária); o modo de teste do WhatsApp vai para o
  -- número de teste (o mesmo desvio da equipe, do fornecedor e de pedir_confirmacao_do_agendamento); sem ele, nada sai
  if v_motivo is null then
    v_fone := public._agenda_cliente_telefone(m.client_id);
    v_teste := coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_mode'), 'false') in ('true', '"true"');
    if v_fone is not null and v_teste then
      v_fone := nullif(regexp_replace(coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_number'), ''),
                                      '\D', '', 'g'), '');
    end if;
    if length(coalesce(v_fone, '')) < 12 then
      v_motivo := 'sem_telefone';
    end if;
  end if;
  if v_motivo is not null then
    update public.agenda_cliente_mensagens
       set estado = 'recusada', recusa_motivo = v_motivo,
           aprovacao = case when m.aprovacao in ('pedida', 'critica') and v_motivo = 'vencida' then 'vencida' else aprovacao end
     where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo);
  end if;

  -- 10. a fila: as tentativas (+5 min) que cabem na janela da mensagem, contadas de agora (a regra única; a 1ª já cabe)
  v_tent := greatest(1, (select count(*)::int from generate_series(0, 2) k
                          where public._agenda_cliente_fora_da_janela(m.enviar_em, v_q + make_interval(mins => 5 * k)) is null));
  -- a trava da fila (o gatilho) recusa com 23514 o que passaria da janela, do teto, do intervalo ou da revalidação: aqui
  -- isso vira a recusa da mensagem com o motivo, sem desfazer o que veio antes na mesma transação
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for,
                                            max_attempts, dedupe_key)
    values (v_fone, m.texto, 'agenda-cliente', m.id, 5, m.enviar_em, v_tent, m.dedupe_key)
    on conflict do nothing
    returning id into v_fila;
  exception when sqlstate '23514' then
    get stacked diagnostics v_det = pg_exception_detail;
    v_motivo := case when v_det in ('janela', 'domingo', 'feriado', 'teto_dia', 'teto_semana', 'teto_total', 'intervalo',
                                    'opt_out', 'status', 'data_mudou', 'material', 'passou_da_data', 'mesmo_tipo_24h',
                                    'desatualizada') then v_det else 'janela' end;
    -- CORREÇÃO FASE 5: (item 13) a revalidação da trava da fila também diz sem_conversa / sem_telefone (o d10)
    if v_det in ('sem_conversa', 'sem_telefone') then
      v_motivo := v_det;
    end if;
    -- CORREÇÃO FASE 5: fim
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = v_motivo where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo, 'pela_fila', true);
  end;
  if v_fila is null then
    -- a mesma chave já estava na fila (o gatilho de idempotência de produção devolve nada): é a mesma mensagem
    select q.id into v_fila from public.whatsapp_send_queue q where q.dedupe_key = m.dedupe_key;
  end if;
  update public.agenda_cliente_mensagens set estado = 'enfileirada', fila_id = v_fila where id = m.id;
  return jsonb_build_object('estado', 'enfileirada', 'fila_id', v_fila, 'teste', v_teste, 'tentativas', v_tent,
                            'enviar_em', m.enviar_em);
end;
$function$;

comment on function public._agenda_cliente_enfileirar(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2): a 1ª trava — a decisão do envio de uma mensagem ao cliente registrada (ou esperando o dono), na ordem: modo_cliente fora de ligado ou a mensagem em teste = fica (modo); o tipo fora de cliente_tipos_ligados = fica (tipo_em_teste); aprovação pedida/crítica = aguardando_dono; segurada/vencida, ou a validade passada = recusada; d19 a conversa viva (mensagem do cliente ou ao cliente nos últimos cliente_conversa_viva_min) = espera o próximo tique (enviar_em pelo _agenda_cliente_quando; passou da validade = vencida); opt_out; sem_conversa (d10); a revalidação (_agenda_cliente_revalidar); domingo/feriado/janela; o teto (teto_dia, teto_semana na semana ISO, teto_total; d13: o aviso de atraso ou de mudança no dia que não cabe vira a pergunta crítica cliente_aviso e espera o dono); o intervalo (outra agenda-cliente pendente ou saindo a menos de cliente_intervalo_min_s); sem_telefone (_agenda_cliente_telefone; wa_test_mode = o número de teste). Senão whatsapp_send_queue (source agenda-cliente, source_ref_id = a mensagem, o texto e a chave dela, priority 5, scheduled_for = enviar_em, max_attempts = as tentativas de +5 min que cabem na janela) e enfileirada; o 23514 da trava da fila vira recusada com o motivo do detail. Idempotente. Sem grant. CORREÇÃO FASE 5 (C1): o choque de intervalo remarca enviar_em (_agenda_cliente_quando; passou da validade = vencida) e devolve {estado registrada, motivo intervalo, enviar_em} em vez de recusar (item 14); o sem_conversa/sem_telefone da trava da fila vira o motivo (item 13). CORREÇÃO FASE 5 (C2, item 3a): a livre ou aprovada com o dia de enviar_em já passado e ainda válida ganha enviar_em = _agenda_cliente_quando(agora) e segue (depois do próximo tique: {estado registrada, motivo remarcada}); passou da validade = vencida.';

-- _agenda_cliente_decidir
create or replace function public._agenda_cliente_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                          p_via text default 'whatsapp', p_trecho text default null,
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor
  q      public.agenda_perguntas%rowtype;
  m      public.agenda_cliente_mensagens%rowtype;
  v_aut  uuid := (select u.id from public.app_users u where u.id = p_autor);
  v_nome text;
  v_manda boolean;
  v_r    jsonb;
  v_txt  text;
  v_acao uuid;
begin
  select * into q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if q.tipo not in ('cliente_aprovar', 'cliente_aviso') then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de mensagem ao cliente.');
  end if;
  if q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if q.modo <> 'ligado' or cf.modo_cliente <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'As mensagens ao cliente estão em teste: nada sai ainda.');
  end if;
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_opcao is null or (q.tipo = 'cliente_aprovar' and p_opcao not in (1, 2))
     or (q.tipo = 'cliente_aviso' and p_opcao not in (1, 2, 3)) then
    return jsonb_build_object('ok', false,
      'texto', case when q.tipo = 'cliente_aprovar' then 'Essa opção não existe. As opções são: 1) manda; 2) segura.'
                    else 'Essa opção não existe. As opções são: 1) Você liga e eu não mando nada; 2) Eu mando o aviso escrito agora; 3) Não aviso agora.' end);
  end if;
  v_manda := (q.tipo = 'cliente_aprovar' and p_opcao = 1) or (q.tipo = 'cliente_aviso' and p_opcao = 2);
  select * into m from public.agenda_cliente_mensagens where pergunta_id = q.id order by criada_em desc, id limit 1 for update;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.service_orders so join public.clients cl on cl.id = so.client_id
                       where so.id = coalesce(m.service_order_id, q.service_order_id)), 'cliente');

  -- a mensagem já não espera (venceu, a revalidação tirou): a pergunta sai sem decisão, nada muda
  if m.id is not null and m.estado not in ('registrada', 'aguardando_dono') then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'a mensagem ao cliente já não estava esperando'
     where id = q.id;
    -- CORREÇÃO FASE 5: (itens 3c e 15) o motivo como o dono lê e sem artigo antes do nome
    return jsonb_build_object('ok', false, 'mensagem_id', m.id,
      'texto', format('A mensagem de %s já não está esperando (%s): nada mudou.', v_nome,
                      case when m.recusa_motivo is not null then public._agenda_cliente_motivo_texto(m.recusa_motivo)
                           else m.estado end));
    -- CORREÇÃO FASE 5: fim
    return jsonb_build_object('ok', false, 'mensagem_id', m.id,
      'texto', format('A mensagem do %s já não está esperando (%s): nada mudou.', v_nome,
                      coalesce(m.recusa_motivo, m.estado)));
  end if;

  update public.agenda_perguntas
     set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
         respondida_por = v_aut, respondida_via = p_via
   where id = q.id;

  if m.id is null then
    -- a pergunta sem mensagem (a data dita que já passou): não há aviso escrito que ainda sirva
    v_txt := case when v_manda
                  then format('Não há aviso escrito para mandar ao %s: a data que ele ouviu já passou e o aviso chegaria depois dela. Recomendo você ligar.', v_nome)
                  when p_opcao = 1 then format('Combinado: você liga para o %s; eu não mando nada.', v_nome)
                  else format('Combinado: não aviso o %s agora.', v_nome) end;
  elsif v_manda then
    update public.agenda_cliente_mensagens
       set aprovacao = 'aprovada', aprovada_em = p_agora, aprovada_por = v_aut
     where id = m.id;
    if m.enviar_em <= p_agora + c_tique then
      -- CORREÇÃO FASE 5: (item 5c) a recusa na hora da decisão já vai no texto da resposta (abaixo): o aviso de "não saiu"
      -- (_agenda_cliente_avisar_recusa) não a repete
      perform set_config('agenda.cliente_recusa_na_hora', 'on', true);
      -- CORREÇÃO FASE 5: fim
      v_r := public._agenda_cliente_enfileirar(m.id, p_agora);
      -- CORREÇÃO FASE 5: a recusa que vier depois (o passo fila, a trava, o worker) avisa
      perform set_config('agenda.cliente_recusa_na_hora', '', true);
      -- CORREÇÃO FASE 5: fim
    end if;
    v_txt := case
      when v_r is null then format('Mando ao %s %s.', v_nome, public._agenda_cliente_quando_texto(m.enviar_em, p_agora))
      when v_r ->> 'estado' = 'enfileirada' then format('Mando ao %s agora.', v_nome)
      when v_r ->> 'estado' = 'recusada' then
        format('Não mandei ao %s: %s.', v_nome, case
          when v_r ->> 'motivo' in ('teto_dia', 'teto_semana') then format('ele já recebeu as mensagens que cabem (no máximo %s por dia e %s por semana); recomendo ligar', cf.cliente_dia_max, cf.cliente_semana_max)
          when v_r ->> 'motivo' = 'teto_total' then 'as mensagens de hoje aos clientes já acabaram; sai na próxima vez que couber'
          when v_r ->> 'motivo' = 'opt_out' then 'ele pediu para não receber mensagens'
          when v_r ->> 'motivo' in ('sem_telefone', 'sem_conversa') then 'não tenho como mandar a ele (telefone ou conversa)'
          when v_r ->> 'motivo' in ('vencida', 'passou_da_data') then 'passou da hora de a mensagem servir'
          when v_r ->> 'motivo' in ('janela', 'domingo', 'feriado') then 'fora do horário de mensagens'
          else 'a OS mudou desde a mensagem (' || coalesce(v_r ->> 'motivo', 'sem motivo') || ')' end)
      else format('Mando ao %s %s.', v_nome, public._agenda_cliente_quando_texto(
                    coalesce((v_r ->> 'enviar_em')::timestamptz, m.enviar_em), p_agora)) end;
  else
    update public.agenda_cliente_mensagens
       set aprovacao = 'segurada', aprovada_em = p_agora, aprovada_por = v_aut, estado = 'recusada', recusa_motivo = 'segurada'
     where id = m.id;
    v_txt := case when q.tipo = 'cliente_aviso' and p_opcao = 1
                  then format('Combinado: você liga para o %s; eu não mando nada.', v_nome)
                  when q.tipo = 'cliente_aviso' then format('Combinado: não aviso o %s agora.', v_nome)
                  else format('Segurei a mensagem do %s: ela não sai.', v_nome) end;
  end if;

  -- CORREÇÃO FASE 5: (item 3c) a recusa na hora diz o motivo verdadeiro (_agenda_cliente_motivo_texto: "fora do horário"
  -- só quando é isso; o dia que passou já não é recusa, item 3a); (item 15) o texto ao dono não leva artigo antes do nome
  -- ("Mando para Nelson agora.", "Segurei a mensagem de Robson: ela não sai.", "Combinado: você liga para Nelson…")
  if v_manda and v_r ->> 'estado' = 'recusada' then
    v_txt := format('Não mandei para %s: %s. Recomendo ligar.', v_nome, public._agenda_cliente_motivo_texto(v_r ->> 'motivo'));
  end if;
  v_txt := public._agenda_cliente_sem_artigo(v_txt, coalesce(m.service_order_id, q.service_order_id));
  -- CORREÇÃO FASE 5: fim
  -- a decisão crítica fica na trilha (a ação crítica com a pergunta respondida)
  if q.tipo = 'cliente_aviso' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, critica,
                                     antes, depois, texto, autor)
    values (clock_timestamp(), (p_agora at time zone 'America/Sao_Paulo')::date, true, 'dono', 'cliente',
            coalesce(m.service_order_id, q.service_order_id), array[coalesce(m.service_order_id, q.service_order_id)],
            q.id, true, '{}'::jsonb,
            jsonb_build_object('mensagem_id', m.id, 'opcao', p_opcao, 'manda', v_manda),
            public._agenda_corta(v_txt, 400), v_aut)
    returning id into v_acao;
  end if;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'mensagem_id', m.id, 'manda', v_manda, 'acao_id', v_acao,
                            'estado', coalesce(v_r ->> 'estado', (select x.estado from public.agenda_cliente_mensagens x where x.id = m.id)),
                            'fila_id', v_r ->> 'fila_id');
end;
$function$;

comment on function public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz) is
  'Agenda de Produção (Fase 5, P3): a decisão do dono sobre a mensagem ao cliente (pergunta aberta, em ligado, com modo_cliente ligado; senão "As mensagens ao cliente estão em teste: nada sai ainda."). cliente_aprovar: 1 = aprovada (aprovada_em/por; à fila se é a hora — a janela, o teto e a revalidação continuam —, senão o passo fila manda no tique certo: "Mando ao Nelson amanhã às 09:00."), 2 = segurada (recusada/segurada: "Segurei a mensagem do Flávio: ela não sai."). cliente_aviso (crítica): 1 = você liga e nada sai, 2 = manda pelo canal (teto cheio = não sai e o texto diz), 3 = não aviso agora; a ação crítica (tipo cliente, origem dono) fica na trilha; a pergunta sem mensagem (a data dita que já passou) não manda nada. A mensagem que já não espera fecha a pergunta (resolvida) sem mudar nada. Chamada por agenda_decidir (e pelo *manda cliente* / *segura cliente* do P5). Interna (sem grant). CORREÇÃO FASE 5 (C1): a recusa na hora (o enfileirar dentro da decisão) já vai no texto; agenda.cliente_recusa_na_hora fica ligado só durante essa chamada, para o aviso de "não saiu" (trg_agenda_cliente_recusada) não repetir. CORREÇÃO FASE 5 (C2): (item 3c) a recusa na hora diz o motivo verdadeiro ("Não mandei para Nelson: <_agenda_cliente_motivo_texto>. Recomendo ligar."), e a que já não espera também; (item 15) os textos sem artigo antes do nome ("Mando para Nelson agora.").';

-- _agenda_cliente_ouviu
create or replace function public._agenda_cliente_ouviu(p_os uuid, p_dia date, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = p_os
                    and (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
                         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                    and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = p_dia
                    -- CORREÇÃO FASE 5: (item 1) a mensagem que só existiu em teste conta como "ouviu" só enquanto a mensagem
                    -- ao cliente inteira está em teste (modo_cliente fora de ligado): com ela ligada, só o que saiu de
                    -- verdade — o M10 (e o M3/M7) não vai de verdade a quem nunca recebeu aquele dia
                    and (m.enviada_em is not null or (public._agenda_cfg()).modo_cliente <> 'ligado')
                    -- CORREÇÃO FASE 5: fim
                    and (m.enviada_em is not null
                         or (m.modo = 'sombra' and m.enviar_em <= p_agora and m.estado = 'registrada')))
      or exists (select 1 from public.service_orders so
                  where so.id = p_os and (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = p_dia);
$function$;

comment on function public._agenda_cliente_ouviu(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o cliente ouviu esse dia? Uma mensagem com data firme (confirmar, véspera, acesso, material chegou, nova data, mudança no dia, aviso remarcado) enviada para ele — em teste, a que teria saído até p_agora —, ou client_confirmed_for nesse dia. CORREÇÃO FASE 5 (C2, item 1): a que teria saído em teste só conta com modo_cliente fora de ligado; ligado, só a enviada (ou o client_confirmed_for).';

-- _agenda_cliente_risco
create or replace function public._agenda_cliente_risco(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  p       public.os_planejamento%rowtype;
  v_status text;
  v_plano jsonb;
  v_pront jsonb;
  v_crit  jsonb;
  v_m     jsonb;
  v_conf  text;
  v_peca  date;
  v_n     int;
  v_causa text;
  v_tipo  text;
  v_var   text;
  v_de    date;
  v_ate   date;
  v_novo  date;
  v_est   boolean := false;
begin
  select * into p from public.os_planejamento where service_order_id = p_os;
  if not found or p.prometido_ate is null then
    return null;
  end if;
  select so.status into v_status from public.service_orders so where so.id = p_os;
  if v_status is null
     or v_status not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client') then
    return null;
  end if;
  v_plano := public._agenda_plano_da_os(p_os, p_hoje);
  v_pront := public.os_prontidao(p_os, p_hoje);
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_crit
    from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false) and e ->> 'nivel' <> 'A';

  if jsonb_array_length(v_crit) > 0 then
    v_causa := 'material';
    v_var := 'peca';
    v_conf := v_pront #>> '{material,confianca}';
    v_tipo := case when v_conf in ('A', 'B') then 'faixa' else 'condicional' end;
    select max((e ->> 'data')::date) into v_peca from jsonb_array_elements(v_crit) e where e ->> 'data' is not null;
    v_n := greatest(1, ceil(coalesce((v_pront #>> '{duracao,dias}')::numeric, (v_plano ->> 'dias')::numeric, 1))::int);
    if v_peca is not null then
      v_de := public.agenda_somar_du(v_peca, cf.folga_material_du);
      v_ate := public.agenda_somar_du(v_peca, cf.folga_material_du + v_n - 1);
      v_novo := v_ate;
    end if;
  elsif v_status = 'in_progress' then
    v_causa := 'execucao';
    v_var := 'execucao';
    v_tipo := 'faixa';
    v_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_est := coalesce(v_m ->> 'fonte' in ('dono', 'aceita'), false) and coalesce((v_m ->> 'total')::numeric, 0) > 0
             and coalesce((v_m ->> 'cumpridos')::numeric, 0) > cf.estouro_fator * (v_m ->> 'total')::numeric;
    v_novo := greatest(coalesce((v_plano ->> 'ultimo_dia')::date, p_hoje),
                       case when v_est then public.agenda_somar_du(p_hoje, 1) end);
    v_de := v_novo;
    v_ate := public.agenda_somar_du(v_novo, 1);
  elsif (v_plano ->> 'proximo_dia') is not null and (v_plano ->> 'ultimo_dia') is not null then
    v_causa := 'replano';
    v_var := 'remarcado';
    v_tipo := 'firme';
    v_de := (v_plano ->> 'proximo_dia')::date;
    v_ate := (v_plano ->> 'ultimo_dia')::date;
    v_novo := v_ate;
  end if;

  -- CORREÇÃO FASE 5: (item 8) peça crítica ainda SEM data de chegada (algum crítico fora de A sem previsão, com outro que
  -- tem): a variante peca_sem_data, condicional, sem data nenhuma ao cliente (d09) — a faixa dos críticos com data fica
  -- aqui, para o dono e para a chave, mas não vai ao texto. (item 6) o remarcado com o MESMO início que o cliente ouviu (só o
  -- fim mudou): forma fim. (item 23) o 2º atraso conta só os avisos de atraso e as novas datas que SAÍRAM — o dia que o
  -- próprio cliente pediu (o prometido_original menor) não é atraso
  if v_causa = 'material' and v_peca is not null
     and exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'data' is null) then
    v_var := 'peca_sem_data';
    v_tipo := 'condicional';
  end if;
  return jsonb_build_object(
    'risco', coalesce(v_novo > p.prometido_ate, v_causa = 'material' and v_novo is null),
    'causa', v_causa, 'tipo', v_tipo, 'variante', v_var,
    'forma', case when v_causa = 'replano' and v_de = coalesce(p.prometido_de, p.prometido_ate) then 'fim' end,
    'faixa_de', v_de, 'faixa_ate', v_ate, 'fim_novo', v_novo, 'peca', v_peca, 'estouro', v_est,
    'dito_de', coalesce(p.prometido_de, p.prometido_ate), 'dito_ate', p.prometido_ate,
    'atraso_dias', v_novo - p.prometido_ate, 'atraso_du', public.agenda_du_entre(p.prometido_ate, v_novo),
    'passou', p.prometido_ate < p_hoje,
    'sem_data', v_causa = 'material' and v_novo is null,
    'segundo', exists (select 1 from public.agenda_cliente_mensagens m
                        where m.service_order_id = p_os and m.tipo in ('pode_atrasar', 'nova_data')
                          and m.enviada_em is not null));
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object(
    'risco', coalesce(v_novo > p.prometido_ate, v_causa = 'material' and v_novo is null),
    'causa', v_causa, 'tipo', v_tipo, 'variante', v_var,
    'faixa_de', v_de, 'faixa_ate', v_ate, 'fim_novo', v_novo, 'peca', v_peca, 'estouro', v_est,
    'dito_de', coalesce(p.prometido_de, p.prometido_ate), 'dito_ate', p.prometido_ate,
    'atraso_dias', v_novo - p.prometido_ate, 'atraso_du', public.agenda_du_entre(p.prometido_ate, v_novo),
    'passou', p.prometido_ate < p_hoje,
    'sem_data', v_causa = 'material' and v_novo is null,
    'segundo', coalesce(p.prometido_original_ate < p.prometido_ate, false)
               or exists (select 1 from public.agenda_cliente_mensagens m
                           where m.service_order_id = p_os and m.tipo in ('pode_atrasar', 'nova_data')
                             and m.enviada_em is not null));
end;
$function$;

comment on function public._agenda_cliente_risco(uuid, date) is
  'Agenda de Produção (Fase 5, P3): a data que o cliente ouviu (os_planejamento.prometido_*) ainda vale? null sem prometido_ate ou com a OS fora das ativas. {risco, causa (material: algum crítico fora de A — a chegada mais tarde dos críticos com data + folga_material_du dias úteis + os dias da OS, tipo faixa com o pior nível em A/B, senão condicional, sem data = sem_data; execucao: em andamento, o fim do plano, ou amanhã com o estouro; replano: o plano publicado com o material na mão, firme), tipo, variante (peca, execucao, remarcado), faixa_de, faixa_ate, fim_novo, peca, dito_de, dito_ate, atraso_dias (corridos), atraso_du (dias úteis), passou (prometido_ate antes de p_hoje), sem_data, segundo (já houve aviso de atraso ou nova data enviados, ou o prometido de agora passou do original)}. risco = o fim novo depois do prometido_ate. CORREÇÃO FASE 5 (C2): (item 8) variante peca_sem_data (condicional) quando algum crítico fora de A não tem data e outro tem; (item 6) forma = fim no replano com o mesmo início que o cliente ouviu; (item 23) segundo = só um aviso de atraso ou uma nova data já ENVIADOS nesta OS.';

-- _agenda_cliente_acorde
create or replace function public._agenda_cliente_acorde(p_os uuid, p_chave text, p_texto text, p_perda date, p_hoje date,
                                                         p_pergunta uuid default null)
 returns uuid
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  -- CORREÇÃO FASE 5: (item 15) o acorde ao dono sem artigo antes do nome do cliente ("O aviso de atraso de Nelson precisa de
  -- você hoje…", "A data que Nelson ouviu…")
  p_texto := public._agenda_cliente_sem_artigo(p_texto, p_os);
  -- CORREÇÃO FASE 5: fim
  select a.id into v_id from public.agenda_acoes a
   where a.tipo = 'cliente' and a.depois ->> 'acorde_chave' = p_chave;
  if v_id is not null then
    return null;
  end if;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (clock_timestamp(), p_hoje, true, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
          jsonb_build_object('acorde', true, 'acorde_chave', p_chave, 'perda_em', p_perda, 'pergunta_id', p_pergunta),
          public._agenda_corta(p_texto, 400))
  returning id into v_id;
  return v_id;
end;
$function$;

comment on function public._agenda_cliente_acorde(uuid, text, text, date, date, uuid) is
  'Agenda de Produção (Fase 5, P3): a ação que leva um acorde da mensagem ao cliente ao dono (tipo cliente, origem vigia, executada, depois {acorde, acorde_chave, perda_em, pergunta_id}), uma por chave (a 2ª devolve null). A rodada devolve as não contadas. Interna (sem grant). CORREÇÃO FASE 5 (C2, item 15): o texto do acorde sai sem artigo antes do 1º nome do cliente da OS (_agenda_cliente_sem_artigo).';

-- _agenda_cliente_material
create or replace function public._agenda_cliente_material(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_recente_du constant int := 5;     -- spec §5.3: "ficou com todo crítico A há ≤ 5 du"
  r      record;
  v_pront jsonb;
  v_dia  date;
  v_tipo text;
  v_r    jsonb;
  n_reg  int := 0;
  n_ja   int := 0;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro
  n_erro int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  for r in
    select k.service_order_id as os, k.status, p.prometido_tipo
      from public.os_carteira(p_hoje) k
      left join public.os_planejamento p on p.service_order_id = k.service_order_id
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress')
       and exists (select 1 from public.os_material om
                    where om.service_order_id = k.service_order_id and om.critico and om.situacao = 'na_mao'
                      and om.chegou_em >= public.agenda_somar_du(p_hoje, -c_recente_du))
     order by k.numero collate "C", k.service_order_id
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:material:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    v_pront := public.os_prontidao(r.os, p_hoje);
    continue when v_pront #>> '{material,estado}' is distinct from 'completo';
    v_dia := (public._agenda_plano_da_os(r.os, p_hoje) ->> 'proximo_dia')::date;
    continue when v_dia is null or v_dia <= p_hoje;
    -- estava esperando pelo material? (o prometido nulo não pode deixar a condição nula: aí o continue não pularia)
    continue when not (
      coalesce(r.prometido_tipo in ('condicional', 'faixa'), false)
      or exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os and m.tipo = 'pode_atrasar' and m.enviada_em is not null)
      or exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = r.os and a.tipo = 'status' and a.executada and a.desfeita_em is null
                    and a.status_antes = 'awaiting_parts' and a.dia >= public.agenda_somar_du(p_hoje, -c_recente_du)));
    -- o cliente já ouviu esse dia (a confirmação, a véspera): não repete
    if public._agenda_cliente_ouviu(r.os, v_dia, p_agora) then
      n_ja := n_ja + 1;
      continue;
    end if;
    v_tipo := case when exists (select 1 from public.agenda_cliente_mensagens m
                                 where m.service_order_id = r.os and m.tipo = 'pode_atrasar' and m.enviada_em is not null)
                   then 'nova_data' else 'material_chegou' end;
    v_r := public._agenda_cliente_registrar(v_tipo, null, r.os, v_dia, '{}'::jsonb, p_agora,
             public._agenda_cliente_fim_da_janela((public._agenda_cliente_quando(0, p_agora, p_agora) at time zone 'America/Sao_Paulo')::date, 1),
             'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('material', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro nas contagens
  return jsonb_build_object('registradas', n_reg, 'ja_ouviu', n_ja, 'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('registradas', n_reg, 'ja_ouviu', n_ja);
end;
$function$;

comment on function public._agenda_cliente_material(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo material da rodada do cliente — a OS cujo material crítico ficou todo na mão há pouco e que esperava por ele: a nova data (M7) se o aviso de atraso saiu, senão o material chegou (M3); não repete o dia que o cliente já ouviu. CORREÇÃO FASE 5 (C2): (item 1) "ouviu" em ligado é só o que saiu de verdade (_agenda_cliente_ouviu); (item 4) o erro de uma OS vai a app_error_logs (agenda / cliente:material:os) e o passo segue (erros_os). Interna (sem grant).';

-- _agenda_cliente_mudanca_no_dia
create or replace function public._agenda_cliente_mudanca_no_dia(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  r      record;
  v_novo date;
  v_env  date;
  v_var  text;
  v_r    jsonb;
  v_ctx  jsonb;
  n_reg  int := 0;
  n_sem  int := 0;
  n_tarde int := 0;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro
  n_erro int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  for r in
    select x.os, x.dia,
           bool_or(x.motivo = 'clima' or x.cancelada_motivo = 'clima') as clima,
           bool_or(x.motivo = 'equipe_faltou' or x.cancelada_motivo = 'pessoa') as equipe
      from (select a.service_order_id as os, a.dia, a.motivo, a.cancelada_motivo
              from public.agenda_alocacoes a
             where a.dia in (p_hoje, p_hoje + 1) and a.tipo <> 'reserva'
               and ((a.estado = 'cancelada' and (a.cancelada_em at time zone 'America/Sao_Paulo')::date = p_hoje
                     and coalesce(a.cancelada_motivo, '') not in ('cliente', 'desfeito', 'os_saiu'))
                    or (a.resultado = 'nao_cumprido' and (a.resultado_em at time zone 'America/Sao_Paulo')::date = p_hoje
                        and coalesce(a.motivo, '') <> 'cliente_ou_bem'))) x
     where not exists (select 1 from public.agenda_alocacoes v
                        where v.service_order_id = x.os and v.dia = x.dia and v.estado in ('publicada', 'fixada')
                          and v.tipo <> 'reserva' and v.resultado is distinct from 'nao_cumprido')
       and public._agenda_cliente_ouviu(x.os, x.dia, p_agora)
     group by x.os, x.dia
     order by x.dia, x.os
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:mudanca_no_dia:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    -- o dia que a mensagem diz é contado de quando ela sai: o dia perdido já passou do envio possível = tarde demais
    v_env := (public._agenda_cliente_quando(0, p_agora, p_agora) at time zone 'America/Sao_Paulo')::date;
    if r.dia < v_env then
      n_tarde := n_tarde + 1;
      continue;
    end if;
    v_novo := (public._agenda_plano_da_os(r.os, p_hoje) ->> 'proximo_dia')::date;
    if v_novo is null or v_novo <= r.dia then
      -- a decisão está com o dono (pergunta crítica do motor, ou a OS fora do plano): nada ao cliente; o acorde
      n_sem := n_sem + 1;
      if cf.modo_cliente = 'ligado' then
        v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
        perform public._agenda_cliente_acorde(r.os, format('mudanca_no_dia:%s:%s', r.os, r.dia),
          format('O %s esperava a equipe %s: a decisão está com você; recomendo ligar.',
                 coalesce(v_ctx ->> 'nome', 'cliente'), case when r.dia = p_hoje then 'hoje' else 'amanhã' end),
          r.dia, p_hoje);
      end if;
      continue;
    end if;
    v_var := case when r.clima then 'clima' when r.equipe then 'equipe' else 'geral' end;
    v_r := public._agenda_cliente_registrar('mudanca_no_dia', v_var, r.os, v_novo,
             jsonb_build_object('quando', case when r.dia = v_env then 'hoje' else 'amanhã' end, 'chave', r.dia::text),
             p_agora, public._agenda_cliente_fim_da_janela(v_env, 0), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('mudanca_no_dia', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro nas contagens
  return jsonb_build_object('registradas', n_reg, 'sem_decisao', n_sem, 'tarde_demais', n_tarde, 'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('registradas', n_reg, 'sem_decisao', n_sem, 'tarde_demais', n_tarde);
end;
$function$;

comment on function public._agenda_cliente_mudanca_no_dia(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo mudanca_no_dia da rodada do cliente — o dia de hoje ou de amanhã que o cliente ouviu e que saiu do plano hoje (sem ser a pedido dele): o M10 com o dia novo, ou o acorde ao dono sem dia novo. CORREÇÃO FASE 5 (C2): (item 1) "ouviu" em ligado é só o que saiu de verdade — o M10 não vai a quem só teve a mensagem em teste; (item 4) o erro de uma OS vai a app_error_logs (agenda / cliente:mudanca_no_dia:os) e o passo segue (erros_os); (item 12) a saudação do M10 de chuva pela hora do envio (no registrar). Interna (sem grant).';

-- _agenda_cliente_confirmar
create or replace function public._agenda_cliente_confirmar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_perto constant interval := interval '2 days';   -- spec §5.3: "não sai se o M1 saiu há menos de 2 dias corridos"
  r       record;
  x       jsonb;
  v_d     date;
  v_m1    timestamptz;
  v_vesp  date;
  v_alvo_v timestamptz;
  v_tipo  text;
  v_r     jsonb;
  n_m1    int := 0;
  n_vesp  int := 0;
  n_unico int := 0;
  n_pula  int := 0;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro
  n_erro int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  for r in
    select k.service_order_id as os
      from public.os_carteira(p_hoje) k
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress')
     order by k.numero collate "C", k.service_order_id
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:confirmar:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    x := public._agenda_plano_da_os(r.os, p_hoje);
    v_d := (x ->> 'proximo_dia')::date;
    continue when v_d is null or v_d <= p_hoje;
    -- ainda não começou: nenhum dia antes do próximo (cumprido, parcial ou sem registro)
    continue when coalesce((x ->> 'inicio')::date, v_d) < v_d;
    continue when public.os_prontidao(r.os, p_hoje) #>> '{material,estado}' is distinct from 'completo';
    x := public._agenda_cliente_contexto(r.os, p_hoje);
    v_vesp := public._agenda_cliente_vespera(v_d);
    continue when v_vesp is null or v_vesp < p_hoje;
    v_alvo_v := public._agenda_cliente_toque(v_vesp);
    v_m1 := public._agenda_cliente_toque(public.agenda_somar_du(v_d, -cf.cliente_confirmar_du));
    if v_m1 < p_agora then
      v_m1 := public._agenda_cliente_proximo_toque(p_agora);
    end if;
    -- CORREÇÃO FASE 5: (item 20) o botão antigo já pediu a confirmação deste D (dentro de cliente_resposta_validade, sem
    -- resposta, e o dia que ele confirma é o D), ou o cliente já confirmou o D: o M1 (e o toque único da confirmação) não
    -- sai — seria a 2ª confirmação do mesmo dia. A véspera segue a regra dela.
    if exists (select 1 from public.service_orders so
                where so.id = r.os
                  and ((so.client_confirmation_requested_at > p_agora - cf.cliente_resposta_validade
                        and so.client_confirmation_requested_at <= p_agora and so.client_confirmed_at is null
                        and (public._agenda_cliente_dia_a_confirmar(r.os, p_agora) at time zone 'America/Sao_Paulo')::date = v_d)
                       or (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = v_d)) then
      v_m1 := null;
    end if;
    -- CORREÇÃO FASE 5: fim
    -- a mensagem que já propôs este D (o material chegou M3, a nova data M7, a mudança no dia M10, o aviso remarcado)
    -- substitui a confirmação; a véspera só sai se ela saiu há c_perto ou mais (abaixo)
    if exists (select 1 from public.agenda_cliente_mensagens m
                where m.service_order_id = r.os
                  and (m.tipo in ('material_chegou', 'nova_data', 'mudanca_no_dia')
                       or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                  and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = v_d and m.estado <> 'recusada') then
      if exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os
                    and (m.tipo in ('material_chegou', 'nova_data', 'mudanca_no_dia')
                         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                    and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = v_d and m.estado <> 'recusada'
                    and (m.enviada_em is null or m.enviada_em > v_alvo_v - c_perto)) then
        n_pula := n_pula + 1;
        continue;
      end if;
      v_m1 := null;
    end if;

    if v_m1 is not null and (v_m1 at time zone 'America/Sao_Paulo')::date >= v_vesp then
      -- um toque só, na véspera (que também não sai se a confirmação saiu há menos de c_perto)
      if public._agenda_cliente_ja_registra(v_vesp, p_hoje, p_agora) then
        if exists (select 1 from public.agenda_cliente_mensagens m
                    where m.service_order_id = r.os and m.tipo in ('confirmar', 'material_chegou', 'nova_data')
                      and m.enviada_em is not null and m.enviada_em > v_alvo_v - c_perto) then
          n_pula := n_pula + 1;
          continue;
        end if;
        v_tipo := case when coalesce((x ->> 'acesso_conhecido')::boolean, false) then 'confirmar' else 'acesso' end;
        v_r := public._agenda_cliente_registrar(v_tipo, case when v_tipo = 'confirmar' then 'unico' end, r.os, v_d,
                 '{}'::jsonb, v_alvo_v, public._agenda_cliente_fim_da_janela(v_vesp, 0), 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then n_unico := n_unico + 1; end if;
      end if;
      continue;
    end if;
    -- a confirmação (D-3)
    if v_m1 is not null and public._agenda_cliente_ja_registra((v_m1 at time zone 'America/Sao_Paulo')::date, p_hoje, p_agora) then
      v_r := public._agenda_cliente_registrar('confirmar', null, r.os, v_d, '{}'::jsonb, v_m1,
               public._agenda_cliente_fim_da_janela((v_m1 at time zone 'America/Sao_Paulo')::date, 0), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_m1 := n_m1 + 1; end if;
    end if;
    -- a véspera (D-1)
    if public._agenda_cliente_ja_registra(v_vesp, p_hoje, p_agora) then
      if exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os and m.tipo in ('confirmar', 'material_chegou', 'nova_data')
                    and m.enviada_em is not null and m.enviada_em > v_alvo_v - c_perto) then
        n_pula := n_pula + 1;
        continue;
      end if;
      v_tipo := case when coalesce((x ->> 'acesso_conhecido')::boolean, false) then 'vespera' else 'acesso' end;
      v_r := public._agenda_cliente_registrar(v_tipo, null, r.os, v_d, '{}'::jsonb, v_alvo_v,
               public._agenda_cliente_fim_da_janela(v_vesp, 0), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_vesp := n_vesp + 1; end if;
    end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('confirmar', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro nas contagens
  return jsonb_build_object('confirmar', n_m1, 'vespera', n_vesp, 'unico', n_unico, 'vespera_pulada', n_pula,
                            'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('confirmar', n_m1, 'vespera', n_vesp, 'unico', n_unico, 'vespera_pulada', n_pula);
end;
$function$;

comment on function public._agenda_cliente_confirmar(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo confirmar da rodada do cliente — a confirmação (M1) em D − cliente_confirmar_du dias úteis, a véspera (M2) ou o acesso (M4) no último dia de janela antes de D, ou um toque só; o M3/M7/M10/M6 remarcado do mesmo D substitui o M1. CORREÇÃO FASE 5 (C1, item 20): o M1 do D não sai quando o botão antigo já pediu a confirmação desse D (client_confirmation_requested_at dentro de cliente_resposta_validade, sem resposta, com _agenda_cliente_dia_a_confirmar no D) ou o cliente já confirmou o D (client_confirmed_for). Interna (sem grant). CORREÇÃO FASE 5 (C2, item 4): o erro de uma OS (o texto que não fecha, o proibido) vai a app_error_logs (agenda / cliente:confirmar:os) e o passo segue para as outras (erros_os).';

-- _agenda_cliente_atraso
create or replace function public._agenda_cliente_atraso(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  r       record;
  m       record;
  x       jsonb;
  v_urg   boolean;
  v_alvo  timestamptz;
  v_lim   timestamptz;
  v_crit  text;
  v_dados jsonb;
  v_r     jsonb;
  v_chave text;
  v_perg  uuid;
  v_ctx   jsonb;
  n_reg   int := 0;
  n_crit  int := 0;
  n_pass  int := 0;
  n_esp   int := 0;
  n_semd  int := 0;
  n_canc  int := 0;
  -- CORREÇÃO FASE 5: (item 3b) o aviso que não saiu; (item 4) as OS puladas por erro
  c_validade constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  n_nao_saiu int := 0;
  n_erro  int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  for r in
    select k.service_order_id as os, p.prometido_ate
      from public.os_carteira(p_hoje) k
      join public.os_planejamento p on p.service_order_id = k.service_order_id
     where p.prometido_ate is not null
     order by k.numero collate "C", k.service_order_id
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:atraso:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    x := public._agenda_cliente_risco(r.os, p_hoje);
    -- o aviso vivo que não é mais o de agora sai do caminho
    for m in
      select a.id, a.dia_alvo from public.agenda_cliente_mensagens a
       where a.service_order_id = r.os and a.tipo = 'pode_atrasar' and a.estado in ('registrada', 'aguardando_dono', 'enfileirada')
    loop
      if x is null or not coalesce((x ->> 'risco')::boolean, false) or coalesce((x ->> 'passou')::boolean, false)
         or m.dia_alvo is distinct from (x ->> 'faixa_de')::date then
        if public._agenda_cliente_cancelar(m.id, 'desatualizada', 'o risco de atraso mudou antes de a mensagem sair') then
          n_canc := n_canc + 1;
        end if;
      end if;
    end loop;
    continue when x is null or not coalesce((x ->> 'risco')::boolean, false);
    -- CORREÇÃO FASE 5: (item 3b) o aviso de atraso de agora que NÃO saiu — recusado pelo canal (sem conversa, sem telefone,
    -- opt-out, o teto, o horário, vencido, o texto) ou pelo provedor (entrega) — com a data dita ainda por vir: o dono fica
    -- sabendo para ligar (uma vez por mensagem: a mesma pergunta do "não saiu" da correção C1, que cobre a aprovada pelo
    -- dono); com a data em até 1 dia útil, o acorde. A segurada (o dono decidiu) e a desatualizada (o risco mudou) não.
    if not coalesce((x ->> 'passou')::boolean, false) and r.prometido_ate >= p_hoje then
      for m in
        select a.id, a.recusa_motivo from public.agenda_cliente_mensagens a
         where a.service_order_id = r.os and a.tipo = 'pode_atrasar' and a.modo = 'ligado' and a.estado = 'recusada'
           and a.dia_alvo is not distinct from (x ->> 'faixa_de')::date
           and a.recusa_motivo in ('sem_conversa', 'sem_telefone', 'opt_out', 'teto_dia', 'teto_semana', 'teto_total',
                                   'janela', 'domingo', 'feriado', 'vencida', 'intervalo', 'texto', 'entrega')
           and not exists (select 1 from public.agenda_perguntas q where q.chave = 'cliente_resposta:nao_saiu:' || a.id)
         order by a.criada_em, a.id
      loop
        v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
        v_perg := public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:nao_saiu:' || m.id, r.os,
                    r.prometido_ate, r.prometido_ate,
                    format('Não consegui avisar %s do atraso (%s): recomendo você ligar hoje.', coalesce(v_ctx ->> 'nome', 'o cliente'),
                           public._agenda_cliente_motivo_texto(m.recusa_motivo)),
                    'ligado', p_agora, p_agora + c_validade);
        n_nao_saiu := n_nao_saiu + 1;
        if r.prometido_ate <= public.agenda_somar_du(p_hoje, 1) then
          perform public._agenda_cliente_acorde(r.os, 'cliente_resposta:nao_saiu:' || m.id,
            format('Não consegui avisar %s do atraso (%s): recomendo você ligar hoje.', coalesce(v_ctx ->> 'nome', 'o cliente'),
                   public._agenda_cliente_motivo_texto(m.recusa_motivo)),
            r.prometido_ate, p_hoje, v_perg);
        end if;
      end loop;
    end if;
    -- CORREÇÃO FASE 5: fim
    v_lim := public._agenda_cliente_ultimo_fim(r.prometido_ate);
    v_urg := public.agenda_du_entre(p_hoje, r.prometido_ate) <= cf.cliente_atraso_na_hora_du;
    v_alvo := case when v_urg then p_agora else public._agenda_cliente_toque(public._agenda_cliente_dia_seguinte(p_hoje)) end;
    -- a data dita já passou, ou o aviso só sairia depois dela: não sai; o dono liga (pergunta crítica, uma vez)
    if coalesce((x ->> 'passou')::boolean, false) or v_lim is null
       or public._agenda_cliente_quando(0, v_alvo, p_agora) > v_lim then
      v_chave := format('cliente_aviso:%s:%s', r.os, r.prometido_ate);
      if not exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo) then
        v_perg := public._agenda_cliente_perguntar('cliente_aviso', v_chave, r.os, r.prometido_ate, p_hoje,
                    public._agenda_cliente_texto_do_aviso('passou', 'pode_atrasar', r.os, x, p_hoje), v_modo, p_agora,
                    public._agenda_cliente_fim_da_janela(p_hoje, 1));
        n_pass := n_pass + 1;
        if v_modo = 'ligado' then
          v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
          perform public._agenda_cliente_acorde(r.os, v_chave,
            format('A data que o %s ouviu (%s) passou sem aviso: recomendo você ligar hoje. A decisão está nas perguntas da agenda (1, 2 ou 3).',
                   coalesce(v_ctx ->> 'nome', 'cliente'), public._dia_curto(r.prometido_ate)),
            p_hoje, p_hoje, v_perg);
        end if;
      end if;
      continue;
    end if;
    if coalesce((x ->> 'sem_data')::boolean, false) then
      -- sem nenhuma previsão da peça não há o que dizer (a vigia já pede a previsão ao dono)
      n_semd := n_semd + 1;
      continue;
    end if;
    -- sem urgência, espera o fechamento do dia (o 1º tique a partir de cliente_hora_preparo)
    if not v_urg and v_local::time < cf.cliente_hora_preparo then
      n_esp := n_esp + 1;
      continue;
    end if;
    v_crit := case when coalesce((x ->> 'segundo')::boolean, false) then 'segundo_atraso'
                   when (x ->> 'atraso_du')::int >= cf.atraso_longo_dias then 'atraso_longo' end;
    v_dados := jsonb_build_object('faixa_de', x -> 'faixa_de', 'faixa_ate', x -> 'faixa_ate', 'prometido_tipo', x -> 'tipo',
                                  'dito_de', x -> 'dito_de', 'dito_ate', x -> 'dito_ate', 'atraso_dias', x -> 'atraso_dias')
               || case when x ->> 'variante' = 'peca' then jsonb_build_object('peca_de', x -> 'peca', 'peca_ate', x -> 'peca')
                       else '{}'::jsonb end;
    -- CORREÇÃO FASE 5: (item 6) a forma fim leva o dia e o fim novos (a revalidação compara o último dia com o fim)
    if x ->> 'forma' = 'fim' then
      v_dados := v_dados || jsonb_build_object('forma', 'fim', 'dia', x -> 'faixa_de', 'fim', x -> 'faixa_ate');
    end if;
    -- CORREÇÃO FASE 5: fim
    v_r := public._agenda_cliente_registrar('pode_atrasar', x ->> 'variante', r.os, (x ->> 'faixa_de')::date, v_dados,
             v_alvo, v_lim, 'rodada', v_crit, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then
      n_reg := n_reg + 1;
      if v_r ->> 'aprovacao' = 'critica' then
        n_crit := n_crit + 1;
        -- a crítica que perde em até 1 dia útil acorda o dono
        if v_r ->> 'modo' = 'ligado' and r.prometido_ate <= public.agenda_somar_du(p_hoje, 1) then
          v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
          perform public._agenda_cliente_acorde(r.os, 'cliente_aviso:' || (v_r ->> 'id'),
            format('O aviso de atraso do %s precisa de você hoje (%s → %s): recomendo ligar. A decisão está nas perguntas da agenda (1, 2 ou 3).',
                   coalesce(v_ctx ->> 'nome', 'cliente'), public._dia_curto(r.prometido_ate),
                   public._agenda_faixa_texto((x ->> 'faixa_de')::date, 'manha', (x ->> 'faixa_ate')::date, 'tarde')),
            r.prometido_ate, p_hoje, (v_r ->> 'pergunta_id')::uuid);
        end if;
      end if;
    end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('atraso', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- CORREÇÃO FASE 5: (itens 3b e 4) o aviso que não saiu e as OS puladas por erro nas contagens
  return jsonb_build_object('registradas', n_reg, 'criticas', n_crit, 'passou', n_pass, 'esperando_fechamento', n_esp,
                            'sem_data', n_semd, 'desatualizadas', n_canc, 'nao_saiu', n_nao_saiu, 'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('registradas', n_reg, 'criticas', n_crit, 'passou', n_pass, 'esperando_fechamento', n_esp,
                            'sem_data', n_semd, 'desatualizadas', n_canc);
end;
$function$;

comment on function public._agenda_cliente_atraso(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo atraso da rodada do cliente — a data que o cliente ouviu e que não vai se cumprir (_agenda_cliente_risco): o aviso (M6) no 1º tique a partir de cliente_hora_preparo, ou na hora com o prometido a até cliente_atraso_na_hora_du dias úteis; nunca depois da data (cliente_aviso passou); o 2º atraso e o atraso longo = pergunta crítica; o aviso vivo que não bate mais com o risco sai do caminho. CORREÇÃO FASE 5 (C2): (item 3b) o M6 de agora recusado pelo canal ou pelo provedor, com a data ainda por vir, abre uma vez cliente_resposta:nao_saiu:<mensagem> ("Não consegui avisar Nelson do atraso (<motivo>): recomendo você ligar hoje."), com o acorde se a data é em até 1 dia útil (nao_saiu); (item 6) a forma fim; (item 8) a variante peca_sem_data vem do risco; (item 4) o erro de uma OS vai a app_error_logs (agenda / cliente:atraso:os) e o passo segue (erros_os). Interna (sem grant).';

-- _agenda_cliente_andamento
create or replace function public._agenda_cliente_andamento(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_hora_tarde constant time := '18:00';    -- spec §5.3: "às 18:00 do mesmo dia (dentro da janela)"
  r       record;
  x       jsonb;
  v_ini   date;
  v_alvo  timestamptz;
  v_env   date;
  v_ult   timestamptz;
  v_r     jsonb;
  n_ini   int := 0;
  n_sem   int := 0;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro
  n_erro int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  for r in
    select k.service_order_id as os, k.status, p.prometido_ate
      from public.os_carteira(p_hoje) k
      left join public.os_planejamento p on p.service_order_id = k.service_order_id
     where k.status = 'in_progress'
     order by k.numero collate "C", k.service_order_id
  loop
    -- CORREÇÃO FASE 5: (item 4) cada OS no seu bloco: o erro de uma (o texto que não fecha, o proibido) vai a
    -- app_error_logs (agenda / cliente:andamento:os) e o passo segue para as outras
    begin
    -- CORREÇÃO FASE 5: fim
    x := public._agenda_plano_da_os(r.os, p_hoje);
    continue when x is null or (x ->> 'dias')::int < 2;
    -- o fim planejado mudou desde a data dita: é o aviso de atraso (M6/M7), não o andamento
    continue when r.prometido_ate is not null and (x ->> 'ultimo_dia')::date is distinct from r.prometido_ate;
    -- (a) o 1º dia feito
    select min(a.dia) into v_ini from public.agenda_alocacoes a
     where a.service_order_id = r.os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.resultado in ('cumprido', 'parcial');
    if v_ini is not null and v_ini >= p_hoje - 1 and v_ini <= p_hoje then
      v_alvo := case when v_ini = p_hoje then greatest(p_agora, (p_hoje + c_hora_tarde) at time zone 'America/Sao_Paulo')
                     else greatest(p_agora, public._agenda_cliente_toque(p_hoje)) end;
      v_env := (public._agenda_cliente_quando(0, v_alvo, p_agora) at time zone 'America/Sao_Paulo')::date;
      if v_env in (v_ini, v_ini + 1) then
        v_r := public._agenda_cliente_registrar('andamento', 'primeiro_dia', r.os, v_ini,
                 jsonb_build_object('quando', case when v_env = v_ini then 'hoje' else 'ontem' end, 'chave', 'inicio'),
                 v_alvo, public._agenda_cliente_fim_da_janela(v_ini, 1), 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then n_ini := n_ini + 1; end if;
      end if;
    end if;
    -- (b) o semanal
    if (x ->> 'dias')::int > cf.cliente_andamento_min_du and v_ini is not null and v_ini < p_hoje then
      select max(m.enviada_em) into v_ult from public.agenda_cliente_mensagens m
       where m.service_order_id = r.os and m.tipo = 'andamento' and m.enviada_em is not null;
      if coalesce((v_ult at time zone 'America/Sao_Paulo')::date, v_ini) + cf.cliente_andamento_intervalo_dias <= p_hoje then
        v_r := public._agenda_cliente_registrar('andamento', 'semanal', r.os, (x ->> 'ultimo_dia')::date,
                 jsonb_build_object('n_feitos', floor(coalesce((x ->> 'meios_cumpridos')::numeric, 0))::int,
                                    'chave', to_char(p_hoje, 'IYYY-"S"IW')),
                 greatest(p_agora, public._agenda_cliente_toque(p_hoje)), public._agenda_cliente_fim_da_janela(p_hoje, 1),
                 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then n_sem := n_sem + 1; end if;
      end if;
    end if;
    -- CORREÇÃO FASE 5: (item 4) o erro desta OS: registrado e pulado
    exception when others then
      perform public._agenda_cliente_erro_da_os('andamento', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
    -- CORREÇÃO FASE 5: fim
  end loop;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro nas contagens
  return jsonb_build_object('primeiro_dia', n_ini, 'semanal', n_sem, 'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('primeiro_dia', n_ini, 'semanal', n_sem);
end;
$function$;

comment on function public._agenda_cliente_andamento(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo andamento da rodada do cliente — o 1º dia feito (M5 primeiro_dia, às 18:00 ou na manhã seguinte) e o semanal da OS longa. CORREÇÃO FASE 5 (C2, item 4): o erro de uma OS vai a app_error_logs (agenda / cliente:andamento:os) e o passo segue (erros_os). Interna (sem grant).';

-- _agenda_cliente_pronto
create or replace function public._agenda_cliente_pronto(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  r      record;
  v_dia  date;
  v_alvo timestamptz;
  v_r    jsonb;
  n_pr   int := 0;
  n_lem  int := 0;
  -- CORREÇÃO FASE 5: (item 4) as OS puladas por erro
  n_erro int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  -- CORREÇÃO FASE 5: (item 24) a OS faturada (invoiced) logo depois de concluída também recebe o "ficou pronto" e o
  -- lembrete (o resto da Fase 5 já a trata como concluída); (item 4) o erro de UMA OS (o texto que não fecha) vai a
  -- app_error_logs (agenda / cliente:pronto:os) e o passo segue para as outras. O filtro do status mora na consulta de cada
  -- laço: o corpo novo vem inteiro aqui, e o de 20261028100300, abaixo, não roda mais (fica para a conferência da cópia).
  for r in
    select so.id as os, (so.check_out_at at time zone 'America/Sao_Paulo')::date as concluida
      from public.service_orders so
     where so.status in ('completed', 'invoiced') and so.delivered_at is null and so.merged_into_id is null
       and so.check_out_at is not null and so.check_out_at <= p_agora
       and (so.check_out_at at time zone 'America/Sao_Paulo')::date between p_hoje - 1 and p_hoje
     order by so.service_order_number collate "C", so.id
  loop
    begin
      v_r := public._agenda_cliente_registrar('pronto', null, r.os, r.concluida, '{}'::jsonb, p_agora,
               public._agenda_cliente_fim_da_janela(r.concluida, 1), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_pr := n_pr + 1; end if;
    exception when others then
      perform public._agenda_cliente_erro_da_os('pronto', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
  end loop;
  for r in
    select m.service_order_id as os, (m.enviada_em at time zone 'America/Sao_Paulo')::date as enviada
      from public.agenda_cliente_mensagens m
      join public.service_orders so on so.id = m.service_order_id
     where m.tipo = 'pronto' and m.estado = 'enviada' and m.resposta_id is null
       and so.status in ('completed', 'invoiced') and so.delivered_at is null
       and not exists (select 1 from public.agenda_cliente_mensagens l
                        where l.service_order_id = m.service_order_id and l.tipo = 'pronto_lembrete')
     order by m.enviada_em, m.id
  loop
    begin
      v_alvo := public._agenda_cliente_toque(r.enviada + cf.cliente_pronto_lembrete_dias);
      v_dia := (v_alvo at time zone 'America/Sao_Paulo')::date;
      continue when not public._agenda_cliente_ja_registra(v_dia, p_hoje, p_agora);
      if v_alvo < p_agora then
        v_alvo := greatest(p_agora, public._agenda_cliente_toque(p_hoje));
      end if;
      v_r := public._agenda_cliente_registrar('pronto_lembrete', null, r.os, null, jsonb_build_object('chave', '2'), v_alvo,
               public._agenda_cliente_fim_da_janela((v_alvo at time zone 'America/Sao_Paulo')::date, 1), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_lem := n_lem + 1; end if;
    exception when others then
      perform public._agenda_cliente_erro_da_os('pronto', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
  end loop;
  return jsonb_build_object('pronto', n_pr, 'lembrete', n_lem, 'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  for r in
    select so.id as os, (so.check_out_at at time zone 'America/Sao_Paulo')::date as concluida
      from public.service_orders so
     where so.status = 'completed' and so.delivered_at is null and so.merged_into_id is null
       and so.check_out_at is not null and so.check_out_at <= p_agora
       and (so.check_out_at at time zone 'America/Sao_Paulo')::date between p_hoje - 1 and p_hoje
     order by so.service_order_number collate "C", so.id
  loop
    v_r := public._agenda_cliente_registrar('pronto', null, r.os, r.concluida, '{}'::jsonb, p_agora,
             public._agenda_cliente_fim_da_janela(r.concluida, 1), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_pr := n_pr + 1; end if;
  end loop;
  for r in
    select m.service_order_id as os, (m.enviada_em at time zone 'America/Sao_Paulo')::date as enviada
      from public.agenda_cliente_mensagens m
      join public.service_orders so on so.id = m.service_order_id
     where m.tipo = 'pronto' and m.estado = 'enviada' and m.resposta_id is null
       and so.status = 'completed' and so.delivered_at is null
       and not exists (select 1 from public.agenda_cliente_mensagens l
                        where l.service_order_id = m.service_order_id and l.tipo = 'pronto_lembrete')
     order by m.enviada_em, m.id
  loop
    v_alvo := public._agenda_cliente_toque(r.enviada + cf.cliente_pronto_lembrete_dias);
    v_dia := (v_alvo at time zone 'America/Sao_Paulo')::date;
    continue when not public._agenda_cliente_ja_registra(v_dia, p_hoje, p_agora);
    if v_alvo < p_agora then
      v_alvo := greatest(p_agora, public._agenda_cliente_toque(p_hoje));
    end if;
    v_r := public._agenda_cliente_registrar('pronto_lembrete', null, r.os, null, jsonb_build_object('chave', '2'), v_alvo,
             public._agenda_cliente_fim_da_janela((v_alvo at time zone 'America/Sao_Paulo')::date, 1), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_lem := n_lem + 1; end if;
  end loop;
  return jsonb_build_object('pronto', n_pr, 'lembrete', n_lem);
end;
$function$;

comment on function public._agenda_cliente_pronto(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo pronto da rodada do cliente — o "ficou pronto" (M8) da OS concluída hoje ou ontem sem entrega, e o lembrete (M8) cliente_pronto_lembrete_dias depois do enviado sem resposta. CORREÇÃO FASE 5 (C2): (item 24) a OS faturada (invoiced) também; (item 4) o erro de uma OS vai a app_error_logs (agenda / cliente:pronto:os) e o passo segue (erros_os). O corpo de 20261028100300 fica depois do retorno, sem rodar. Interna (sem grant).';

-- _agenda_cliente_pos_servico
create or replace function public._agenda_cliente_pos_servico(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_janela_pos constant interval := interval '2 hours';   -- spec §5.3: "entre 09:00 e 11:00 de seg–sex"
  c_quieto     constant interval := interval '3 days';    -- spec §5.3: "nem com mensagem dele nos últimos 3 dias"
  r       record;
  v_alvo  date;
  v_d     date;
  v_t     timestamptz;
  v_r     jsonb;
  n_reg   int := 0;
  n_esp   int := 0;
  -- CORREÇÃO FASE 5: (item 22) a OS sem entrega com o "ficou pronto" sem resposta; (item 4) as OS puladas por erro
  n_sem_entrega int := 0;
  n_erro  int := 0;
  -- CORREÇÃO FASE 5: fim
begin
  -- CORREÇÃO FASE 5: (item 24) a OS faturada (invoiced) também recebe o pós-serviço; (item 22) sem entrega registrada
  -- (delivered_at), o pós-serviço ("Já deu para usar?") só sai se não há "ficou pronto" nem lembrete ENVIADO e sem resposta
  -- nessa OS — o cliente que ainda não respondeu para combinar a entrega não pegou o barco; (item 4) o erro de UMA OS vai a
  -- app_error_logs (agenda / cliente:pos_servico:os) e o passo segue. O filtro do status mora na consulta do laço: o corpo
  -- novo vem inteiro aqui, e o de 20261028100300, abaixo, não roda mais (fica para a conferência da cópia).
  for r in
    select so.id as os, so.client_id, so.delivered_at,
           coalesce((so.delivered_at at time zone 'America/Sao_Paulo')::date,
                    case when (so.check_out_at at time zone 'America/Sao_Paulo')::date + cf.cliente_pos_dias <= p_hoje
                         then (so.check_out_at at time zone 'America/Sao_Paulo')::date end) as base
      from public.service_orders so
     where so.status in ('completed', 'invoiced') and so.merged_into_id is null and so.check_out_at is not null
       and (so.check_out_at at time zone 'America/Sao_Paulo')::date >= p_hoje - 62
       and not exists (select 1 from public.agenda_cliente_mensagens m
                        where m.service_order_id = so.id and m.tipo = 'pos_servico')
     order by so.service_order_number collate "C", so.id
  loop
    begin
      continue when r.base is null;
      if r.delivered_at is null
         and exists (select 1 from public.agenda_cliente_mensagens x
                      where x.service_order_id = r.os and x.tipo in ('pronto', 'pronto_lembrete')
                        and x.enviada_em is not null and x.resposta_id is null) then
        n_sem_entrega := n_sem_entrega + 1;
        continue;
      end if;
      v_alvo := r.base + cf.cliente_pos_dias;
      continue when v_alvo > p_hoje;
      v_d := v_alvo;
      while not (public._agenda_cliente_dia_de_janela(v_d) and extract(isodow from v_d) <= 5) loop
        v_d := v_d + 1;
      end loop;
      continue when public._agenda_cliente_fim_da_janela(v_d, 2) < p_agora;
      if exists (select 1 from public.agenda_perguntas q
                  where q.tipo = 'cliente_resposta' and q.estado = 'aberta'
                    and q.service_order_id in (select x.id from public.service_orders x where x.client_id = r.client_id))
         or exists (select 1 from public.clients c
                      join public.whatsapp_messages w
                        on public._agenda_chave_telefone(w.phone_normalized)
                           in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
                     where c.id = r.client_id and w.direction = 'inbound' and w.occurred_at <= p_agora
                       and w.occurred_at > p_agora - c_quieto) then
        n_esp := n_esp + 1;
        continue;
      end if;
      v_d := greatest(v_d, p_hoje);
      loop
        v_t := (v_d + cf.cliente_hora_toque) at time zone 'America/Sao_Paulo';
        exit when public._agenda_cliente_dia_de_janela(v_d) and extract(isodow from v_d) <= 5 and v_t + c_janela_pos > p_agora;
        v_d := v_d + 1;
        if v_d > p_hoje + 31 then
          raise exception '_agenda_cliente_pos_servico: nenhum dia útil de janela em 31 dias' using errcode = '54000';
        end if;
      end loop;
      v_r := public._agenda_cliente_registrar('pos_servico', null, r.os, null, jsonb_build_object('chave', 'pos'),
               greatest(v_t, p_agora), public._agenda_cliente_fim_da_janela(v_d, 2), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
    exception when others then
      perform public._agenda_cliente_erro_da_os('pos_servico', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'esperando_o_cliente', n_esp, 'sem_entrega', n_sem_entrega,
                            'erros_os', n_erro);
  -- CORREÇÃO FASE 5: fim
  for r in
    select so.id as os, so.client_id,
           coalesce((so.delivered_at at time zone 'America/Sao_Paulo')::date,
                    case when (so.check_out_at at time zone 'America/Sao_Paulo')::date + cf.cliente_pos_dias <= p_hoje
                         then (so.check_out_at at time zone 'America/Sao_Paulo')::date end) as base
      from public.service_orders so
     where so.status = 'completed' and so.merged_into_id is null and so.check_out_at is not null
       and (so.check_out_at at time zone 'America/Sao_Paulo')::date >= p_hoje - 62
       and not exists (select 1 from public.agenda_cliente_mensagens m
                        where m.service_order_id = so.id and m.tipo = 'pos_servico')
     order by so.service_order_number collate "C", so.id
  loop
    continue when r.base is null;
    v_alvo := r.base + cf.cliente_pos_dias;
    continue when v_alvo > p_hoje;
    -- o dia certo: o 1º dia de janela de segunda a sexta a partir de base + cliente_pos_dias; passou do 3º dia de janela
    -- dele, não sai mais
    v_d := v_alvo;
    while not (public._agenda_cliente_dia_de_janela(v_d) and extract(isodow from v_d) <= 5) loop
      v_d := v_d + 1;
    end loop;
    continue when public._agenda_cliente_fim_da_janela(v_d, 2) < p_agora;
    -- o cliente conversando (mensagem dele nos últimos dias) ou com uma resposta esperando o dono: agora não
    if exists (select 1 from public.agenda_perguntas q
                where q.tipo = 'cliente_resposta' and q.estado = 'aberta'
                  and q.service_order_id in (select x.id from public.service_orders x where x.client_id = r.client_id))
       or exists (select 1 from public.clients c
                    join public.whatsapp_messages w
                      on public._agenda_chave_telefone(w.phone_normalized)
                         in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
                   where c.id = r.client_id and w.direction = 'inbound' and w.occurred_at <= p_agora
                     and w.occurred_at > p_agora - c_quieto) then
      n_esp := n_esp + 1;
      continue;
    end if;
    -- a hora: hoje, se é segunda a sexta de janela e ainda está entre o toque e o toque + c_janela_pos; senão o toque do
    -- próximo dia útil de janela
    v_d := greatest(v_d, p_hoje);
    loop
      v_t := (v_d + cf.cliente_hora_toque) at time zone 'America/Sao_Paulo';
      exit when public._agenda_cliente_dia_de_janela(v_d) and extract(isodow from v_d) <= 5 and v_t + c_janela_pos > p_agora;
      v_d := v_d + 1;
      if v_d > p_hoje + 31 then
        raise exception '_agenda_cliente_pos_servico: nenhum dia útil de janela em 31 dias' using errcode = '54000';
      end if;
    end loop;
    v_r := public._agenda_cliente_registrar('pos_servico', null, r.os, null, jsonb_build_object('chave', 'pos'),
             greatest(v_t, p_agora), public._agenda_cliente_fim_da_janela(v_d, 2), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'esperando_o_cliente', n_esp);
end;
$function$;

comment on function public._agenda_cliente_pos_servico(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo pos_servico da rodada do cliente — o M9 cliente_pos_dias depois da entrega (ou da conclusão, sem entrega), de segunda a sexta entre o toque e 2 h depois, uma vez por OS; espera o cliente que conversou nos últimos 3 dias ou que tem resposta aberta. CORREÇÃO FASE 5 (C2): (item 24) a OS faturada também; (item 22) sem delivered_at, só sai se não há "ficou pronto" nem lembrete enviado sem resposta nessa OS (sem_entrega); (item 4) o erro de uma OS vai a app_error_logs (agenda / cliente:pos_servico:os) e o passo segue (erros_os). O corpo de 20261028100300 fica depois do retorno, sem rodar. Interna (sem grant).';

-- agenda_cliente_preparar
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
      -- CORREÇÃO FASE 5: (item 7) a data firme que o DONO manda dizer passa pela revalidação sem o passo do material (d09:
      -- só o dono troca a faixa pela data firme do plano); (item 6) com o início igual ao que o cliente ouviu, a forma fim
      v_dados := v_dados || jsonb_build_object('firme_do_dono', true)
                 || case when v_dia = coalesce((v_rk ->> 'dito_de')::date, (v_rk ->> 'dito_ate')::date)
                         then jsonb_build_object('forma', 'fim') else '{}'::jsonb end;
      -- CORREÇÃO FASE 5: fim
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
    -- CORREÇÃO FASE 5: (item 15) sem artigo antes do nome ("Já mandei para Nelson …")
    v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
    -- CORREÇÃO FASE 5: fim
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
  -- CORREÇÃO FASE 5: (item 15) "Pronto para Vanderlei, sai agora: …" (sem artigo antes do nome)
  v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('ok', true, 'status', 'preparada', 'texto', v_txt, 'mensagem_id', v_r -> 'id',
                            'estado', v_r ->> 'estado', 'modo', v_r ->> 'modo', 'enviar_em', v_r -> 'enviar_em');
end;
$function$;

comment on function public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P5): a ferramenta cliente_avisar — prepara a mensagem-modelo que o dono pede e NUNCA envia. Resolve a OS (agenda_resolver_os; o pronto, o lembrete e o pós-serviço aceitam a OS concluída fora da carteira), confere o telefone e o opt-out, o tipo e os dados (sem dado, diz o que falta: "O Nelson não tem data no plano: não tenho o que confirmar.", "Não há data dita ao Giancarlo: …", d09 — material fora de "completo" não vira data firme), e registra pelo _agenda_cliente_registrar com origem dono (em ligado, sempre pedida: "Pronto para o Nelson, sai amanhã às 09:00: "…". Para mandar: *manda cliente Nelson*."; em teste, a sombra). A chave é a da rodada (a mesma mensagem não sai duas vezes: a que já existe é dita como está; a recusada antes ganha uma 2ª chance com :dono). p_firme (só pode_atrasar): a data firme do plano (variante remarcado) no lugar da faixa, só com o plano publicado. mudanca_no_dia não é pela ferramenta (sai sozinha). modo_cliente desligado = recusa. Admin pelo _autor_da_agenda. {ok, status, texto, mensagem_id, estado, modo, enviar_em} ou a recusa {ok:false, motivo, pergunta, texto}. CORREÇÃO FASE 5 (C2): (item 7) p_firme grava firme_do_dono em p_dados (a revalidação não aplica o passo do material a ela); (item 6) a forma fim com o mesmo início que o cliente ouviu; (item 15) o texto da preparada e o da que já existe sem artigo antes do nome.';

-- agenda_cliente_decidir_dito
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
    -- CORREÇÃO FASE 5: (item 15) o texto de cada uma sem artigo antes do nome ("Segurei a mensagem de Nelson: ela não sai."),
    -- como o da decisão (_agenda_cliente_decidir)
    v_r := jsonb_set(v_r, '{texto}', to_jsonb(coalesce(public._agenda_cliente_sem_artigo(v_r ->> 'texto',
             (select m.service_order_id from public.agenda_cliente_mensagens m where m.id = r.id)), '')));
    -- CORREÇÃO FASE 5: fim
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
  -- CORREÇÃO FASE 5: (item 15) "Segurei 2: as mensagens de Nelson e Flávio não saem."
  v_txt := replace(v_txt, ': as mensagens do ', ': as mensagens de ');
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('ok', true, 'status', 'ok', 'texto', v_txt, 'decididas', cardinality(v_msgs),
                            'mensagens', to_jsonb(v_msgs));
end;
$function$;

comment on function public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P5): as palavras *manda cliente [nome]* e *segura cliente [nome]* — decide as mensagens ao cliente em ligado que esperam o dono (cliente_aprovar, por _agenda_cliente_decidir: manda = 1, segura = 2); *segura* também tira do caminho a que ia sair sozinha (livre/aprovada, registrada ou na fila sem sair: recusada segurada, aprovacao segurada). Sem nome, todas; com nome, as do cliente pelo 1º nome ou pelo começo do nome inteiro (dois clientes = "Tem 2 clientes "Rodrigo" esperando (…): diga o sobrenome."; nenhum = "Não achei mensagem esperando para "…"."). O aviso que é decisão (cliente_aviso) não: "Essa é uma decisão: responda pela conversa (opção 1, 2 ou 3).". Textos: o de _agenda_cliente_decidir ("Mando ao Nelson amanhã às 09:00.", "Segurei a mensagem do Flávio: ela não sai."); com várias, "Mandei 2: Nelson e Flávio (saem amanhã às 09:00)." / "Segurei 2: as mensagens do Nelson e Flávio não saem.". modo_cliente sombra = "As mensagens ao cliente estão em teste: nada sai ainda."; desligado = status nao_achei (a palavra segue ao modelo). Admin pelo _autor_da_agenda. {ok, status (ok|nenhuma|nao_achei|ambiguo|decisao|em_teste), texto, decididas, mensagens}. CORREÇÃO FASE 5 (C2, item 15): os textos sem artigo antes do nome ("Segurei a mensagem de Nelson: ela não sai.", "Segurei 2: as mensagens de Nelson e Flávio não saem.").';

-- _agenda_cliente_fechamento
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
      -- CORREÇÃO FASE 5: (item 15) "Mensagem para Lucenira (…)" — sem artigo antes do nome (não há gênero no cadastro)
      v_txt := replace(v_txt, 'Mensagem para o ' || r.nome || ' (', 'Mensagem para ' || r.nome || ' (');
      -- CORREÇÃO FASE 5: fim
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
    -- CORREÇÃO FASE 5: (item 15) "a confirmação de ter 03/11 para Flávio" (sem artigo antes do nome)
    v_itens[cardinality(v_itens)] := format('%s para %s', public._agenda_cliente_o_que(r.tipo, r.dia), r.nome);
    -- CORREÇÃO FASE 5: fim
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
  'Agenda de Produção (Fase 5, P5): as linhas tipo cliente do fechamento (só com modo_cliente ligado; quem chama, _agenda_linhas_do_fechamento, confere) — perda 75: a mensagem que espera *manda cliente* e sai até o próximo dia de janela ("Mensagem para o Nelson (aviso de atraso), sai amanhã às 09:00: "…". *manda cliente Nelson* ou *segura cliente Nelson*.", a 1ª inteira; com mais de uma, "E mais N: *agenda clientes* mostra; *manda cliente* manda todas."; acima de 600 caracteres o texto da mensagem é cortado em 300 com "(*agenda clientes* mostra inteira)"); perda 40: "Amanhã, a partir das 09:00, vou mandar: a confirmação de ter 03/11 ao Flávio e … Para não mandar: *segura cliente Flávio*." (as livres e aprovadas do próximo dia de janela, até 3). [{tipo, texto, perda, pergunta_id, acao_ids, modo}]. CORREÇÃO FASE 5 (C2, item 15): sem artigo antes do nome ("Mensagem para Nelson (aviso de atraso), sai amanhã às 09:00: …"; "… a confirmação de ter 03/11 para Flávio …").';

-- agenda_resposta_do_cliente
create or replace function public.agenda_resposta_do_cliente(p_phone text, p_body text, p_message_id uuid, p_tipo_msg text,
                                                             p_intencao text, p_expressao text,
                                                             p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  c_pergunta_dias constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  -- os tipos que esperam resposta (spec §5.4); os que propõem um dia (o pedido de outro dia só vale neles)
  c_esperam constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia',
                                     'pode_atrasar', 'pronto', 'pronto_lembrete', 'pos_servico'];
  c_do_dia  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia'];
  v_hoje    date;
  v_modo    text;
  v_tipo    text;
  v_trecho  text;
  v_cli     uuid[];
  m         public.agenda_cliente_mensagens%rowtype;
  v_n       int;
  v_r       public.agenda_cliente_respostas%rowtype;
  v_rid     uuid := gen_random_uuid();
  v_int     text;
  v_expr    text;
  v_data    jsonb;
  v_nome    text;
  v_dia     date;
  v_ref     text;
  v_do_dia  boolean;
  v_efeito  text;
  v_o_que   text;
  v_texto   text;
  v_x       jsonb;
  v_acao    uuid;
  v_perg    uuid;
  v_acorde  boolean := false;
  v_de      date;
  v_ate     date;
  v_id      uuid;
  v_k       int := 0;
  v_estado  text;
  v_msg     text;
  -- CORREÇÃO FASE 5: a outra conversa (A1) e o PARAR que vale sempre (item 2)
  c_opt_out_dias constant interval := interval '30 days';   -- decisão da correção C1: o PARAR de quem recebeu da agenda em 30 dias
  v_outra   boolean := false;
  v_opt_cli uuid[];
  v_opt_msg uuid;
  v_opt_os  uuid;
  v_c       uuid;
  -- CORREÇÃO FASE 5: fim
begin
  if p_agora is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_tipo := case when p_tipo_msg in ('text', 'audio', 'image', 'document', 'video') then p_tipo_msg else 'outro' end;
  v_trecho := nullif(left(btrim(coalesce(p_body, '')), 500), '');
  if v_tipo = 'text' and v_trecho is null then
    return jsonb_build_object('consumiu', false);
  end if;
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_modo := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;

  -- quem é (o dono, a equipe e quem recebe diária nunca são cliente)
  v_cli := public._agenda_clientes_do_telefone(p_phone, p_agora);
  if cardinality(v_cli) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  -- a mesma mensagem dele de novo: nada muda
  if p_message_id is not null then
    select * into v_r from public.agenda_cliente_respostas r where r.whatsapp_message_id = p_message_id;
    if found then
      return jsonb_build_object('consumiu', v_r.modo = 'ligado', 'efeito', v_r.efeito, 'repetida', true, 'resposta_id', v_r.id);
    end if;
  end if;

  -- a que mensagem ele responde: a última da agenda mandada a ele (em teste, a que teria saído), dos tipos que esperam
  -- resposta, dentro de cliente_resposta_validade, ainda sem resposta. Sem ela, a agenda não lê: é conversa.
  select count(distinct x.service_order_id)::int into v_n
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade));
  select x.* into m
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade))
   order by coalesce(x.enviada_em, x.enviar_em) desc, x.criada_em desc, x.id
   limit 1;
  -- CORREÇÃO FASE 5: (A1 = item 11) a resposta só é da agenda quando a última mensagem que a HBR mandou a esse número é a
  -- dela: o botão antigo (o pedido de 30/09) ou o dono (ou outra rotina) falando com o cliente depois dela = a resposta é
  -- dessa outra conversa — devolve consumiu false (abaixo) e os leitores de antes (o "sim" de 30/09, a revisão) seguem.
  if m.id is not null then
    v_outra := public._agenda_cliente_outra_conversa(v_cli, p_phone, coalesce(m.enviada_em, m.enviar_em), p_agora);
  end if;
  -- (item 2) o PARAR (e os outros opt-outs) vale SEMPRE para quem recebeu mensagem da agenda nos últimos c_opt_out_dias —
  -- fora da validade, depois de outra resposta, com o número de dois clientes ou depois de outra conversa: o pós-serviço
  -- promete "é só responder PARAR". Marca o opt-out de cada cliente do número que recebeu, cancela as vivas dele, grava a
  -- resposta (efeito opt_out) e a ação; nada responde ao cliente.
  if v_modo = 'ligado' and v_tipo = 'text' and p_intencao = 'opt_out' and not public._e_concordancia(p_body)
     and (m.id is null or v_outra or v_n > 1 or cardinality(v_cli) > 1) then
    select coalesce(array_agg(distinct x.client_id), '{}'::uuid[]) into v_opt_cli
      from public.agenda_cliente_mensagens x
     where x.client_id = any (v_cli) and x.modo = 'ligado' and x.enviada_em is not null
       and x.enviada_em <= p_agora and x.enviada_em > p_agora - c_opt_out_dias;
    if cardinality(v_opt_cli) > 0 then
      select x.id, x.service_order_id into v_opt_msg, v_opt_os
        from public.agenda_cliente_mensagens x
       where x.client_id = any (v_opt_cli) and x.modo = 'ligado' and x.enviada_em is not null and x.enviada_em <= p_agora
       order by x.enviada_em desc, x.id limit 1;
      insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                   tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
      values (v_rid, v_opt_cli[1], v_opt_os, v_opt_msg, p_message_id, p_agora, v_tipo, v_trecho, 'opt_out', null, null,
              'opt_out', 'ligado')
      on conflict (whatsapp_message_id) do nothing;
      if not found then
        return jsonb_build_object('consumiu', true, 'repetida', true);
      end if;
      foreach v_c in array v_opt_cli loop
        update public.clients set opt_out_whatsapp = true where id = v_c and not coalesce(opt_out_whatsapp, false);
        for v_id in select x.id from public.agenda_cliente_mensagens x
                     where x.client_id = v_c and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                     order by x.enviar_em, x.id loop
          if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
            v_k := v_k + 1;
          end if;
        end loop;
      end loop;
      v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                            from public.clients cl where cl.id = v_opt_cli[1]), 'cliente');
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', v_opt_os, array[v_opt_os], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'canceladas', v_k,
                                 'clientes', to_jsonb(v_opt_cli), 'fora_da_mensagem', true),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
      update public.agenda_cliente_respostas set acao_id = v_acao where id = v_rid;
      return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', 'opt_out', 'intencao', 'opt_out', 'texto', v_texto,
                                'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'acao_id', v_acao, 'pergunta_id', null);
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'motivo', 'sem_mensagem');
  end if;
  -- CORREÇÃO FASE 5: (A1) a outra conversa depois da mensagem da agenda: não é resposta a ela (em teste também: a sombra
  -- não registra o que a agenda não leria)
  if v_outra then
    return jsonb_build_object('consumiu', false, 'modo', v_modo, 'motivo', 'outra_conversa', 'mensagem_id', m.id);
  end if;
  -- CORREÇÃO FASE 5: fim

  -- a intenção: o áudio e a mídia antes de tudo (nunca confirmam); o SIM curto pela regra única de 30/09; o resto como o
  -- leitor do webhook classificou (sem IA)
  v_int := case when v_tipo = 'audio' then 'audio'
                when v_tipo <> 'text' then 'outro'
                when public._e_concordancia(p_body) then 'confirma'
                when p_intencao in ('remarcar', 'falta', 'data', 'acesso', 'opt_out', 'disputa', 'negociacao', 'pergunta',
                                    'acordo', 'outro') then p_intencao
                else 'outro' end;
  v_expr := case when v_int in ('data', 'remarcar', 'falta') then nullif(left(btrim(coalesce(p_expressao, '')), 60), '') end;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  v_data := case when v_expr is not null then public._agenda_cliente_data_da_resposta(v_expr, v_hoje, v_dia) end;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  v_ref := public._agenda_cliente_a_mensagem(m.tipo, m.variante, v_dia);
  v_do_dia := m.tipo = any (c_do_dia) or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado');

  -- em teste: só registra o que faria (a intenção); nada muda e os fluxos de hoje seguem iguais
  if v_modo = 'sombra' then
    insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                 tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
    values (v_rid, m.client_id, m.service_order_id, m.id, p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr,
            (v_data ->> 'de')::date, 'sombra', 'sombra')
    on conflict (whatsapp_message_id) do nothing;
    return jsonb_build_object('consumiu', false, 'modo', 'sombra', 'efeito', 'sombra', 'intencao', v_int, 'resposta_id', v_rid);
  end if;

  -- ligado: a resposta fica registrada primeiro (uma por mensagem do WhatsApp); o efeito vem depois
  insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                               tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
  values (v_rid, m.client_id, m.service_order_id, case when v_n > 1 or cardinality(v_cli) > 1 then null else m.id end,
          p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr, (v_data ->> 'de')::date, 'nada', 'ligado')
  on conflict (whatsapp_message_id) do nothing;
  if not found then
    return jsonb_build_object('consumiu', true, 'repetida', true);
  end if;
  perform set_config('agenda.hoje', v_hoje::text, true);

  begin
    if v_n > 1 or cardinality(v_cli) > 1 then
      -- duas OS (ou dois clientes no número) esperando: não adivinha
      v_efeito := 'ambigua';
      v_texto := format('Chegou "%s" do número do %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta dele', v_n) end);
    elsif v_int = 'audio' then
      -- o áudio NUNCA confirma: vai ao dono
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu por áudio %s; a transcrição está na conversa. Não respondi nada; é com você.', v_nome, v_ref);
    elsif v_tipo <> 'text' then
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu com %s %s. Não respondi nada; é com você.', v_nome,
                        case v_tipo when 'image' then 'uma foto' when 'video' then 'um vídeo' when 'document' then 'um documento'
                                    else 'uma mensagem que não é texto' end, v_ref);
    elsif v_int = 'confirma' then
      if m.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado') then
        -- (decisão do P4) o SIM ao aviso remarcado confirma o dia novo, como o M1: o texto dele pede "Responda SIM"
        v_x := public._agenda_cliente_confirmar_dia(m.id, v_rid, v_trecho, v_hoje, p_agora);
        if coalesce((v_x ->> 'ok')::boolean, false) then
          v_efeito := 'confirmou';
          v_acao := (v_x ->> 'acao_id')::uuid;
          v_texto := v_x ->> 'texto';
        else
          v_efeito := 'ao_dono';
          v_o_que := v_x ->> 'o_que';
        end if;
      elsif m.tipo in ('vespera', 'acesso') then
        v_efeito := 'confirmou';   -- só registra (o client_confirmed_* é do SIM ao M1/M3/M7/M10)
      elsif m.tipo = 'pode_atrasar' then
        v_efeito := 'ciencia';
      elsif m.tipo in ('pronto', 'pronto_lembrete') then
        v_efeito := 'ao_dono';
        v_o_que := 'combine a entrega com ele';
      else
        v_efeito := 'nada';
      end if;
    elsif v_int = 'opt_out' then
      -- honrado calado (d8): nada mais sai a ele; o dono fica sabendo pela ação
      update public.clients set opt_out_whatsapp = true where id = m.client_id and not coalesce(opt_out_whatsapp, false);
      for v_id in select x.id from public.agenda_cliente_mensagens x
                   where x.client_id = m.client_id and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                   order by x.enviar_em, x.id loop
        if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
          v_k := v_k + 1;
        end if;
      end loop;
      v_efeito := 'opt_out';
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', m.service_order_id, array[m.service_order_id], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', m.id, 'canceladas', v_k),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
    elsif v_int in ('disputa', 'negociacao', 'acordo', 'pergunta') then
      v_efeito := 'ao_dono';
      v_acorde := v_int = 'disputa';   -- a reclamação vai na hora
      v_o_que := case v_int when 'disputa' then 'parece reclamação'
                            when 'negociacao' then 'é sobre preço ou pagamento'
                            when 'acordo' then 'parece que concorda, mas não é um SIM claro'
                            else 'é uma pergunta' end;
    elsif v_int in ('data', 'remarcar', 'falta') and not v_do_dia then
      v_efeito := 'ao_dono';
      v_o_que := case when m.tipo in ('pronto', 'pronto_lembrete') then 'falou de dia: combine a entrega com ele'
                      else 'falou de outro dia' end;
    elsif v_int in ('data', 'remarcar', 'falta') and cf.modo_proposta <> 'ligado' then
      v_efeito := 'ao_dono';
      v_o_que := 'pediu outro dia, mas a agenda automática não está ligada: remarque você';
    elsif v_int = 'data' then
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null then
        v_efeito := 'ao_dono';
        v_o_que := 'não entendi o dia que ele pediu';
      elsif v_de <= v_hoje then
        v_efeito := 'ao_dono';
        v_o_que := 'o dia que ele pediu já passou ou é hoje';
      elsif v_dia is not null and v_de = v_dia then
        v_efeito := 'ao_dono';
        v_o_que := 'falou do mesmo dia combinado';
      elsif v_dia is not null and v_de < v_dia then
        -- (decisão do P4) mais cedo que o combinado: o "não antes de" não adianta nada; é o dono que vê se dá
        v_efeito := 'ao_dono';
        v_o_que := format('pediu um dia antes do combinado (%s)', public._dia_curto(v_de));
      -- CORREÇÃO FASE 5: (item 9) o dia pedido longe demais do combinado (mais de cliente_pedido_max_du dias úteis) não
      -- remarca sozinho: é o dono que vê
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_de) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('pediu %s, mais de %s dias úteis depois do combinado: remarque você', public._dia_curto(v_de),
                          cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid,
                 case when v_dia is not null then daterange(v_dia, v_dia, '[]') end, v_de,
                 format('O %s pediu %s', v_nome,
                        case when v_ate > v_de then 'a partir de ' || public._dia_curto(v_de) else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 17) falta/remarcar com um número de dia que o banco não entendeu ("tô viajando, volto dia 20",
    -- "só depois de 20/11"): tirar só o dia combinado remarcaria para quando ele ainda está fora — vai ao dono
    elsif v_int in ('remarcar', 'falta') and v_data is null
          and public._agenda_preparar_data(coalesce(v_trecho, '')) ~ '(\mdia \d{1,2}\M|\m\d{1,2}/\d{1,2})' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou de outro dia, que eu não entendi';
    -- CORREÇÃO FASE 5: fim
    elsif v_int in ('remarcar', 'falta') then
      -- o dia recusado: o que ele disse (convertido pelo banco), senão o dia da mensagem
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null or v_ate < v_hoje then
        v_de := v_dia;
        v_ate := v_dia;
      end if;
      v_de := greatest(v_de, v_hoje);
      if v_de is null or v_ate < v_de then
        v_efeito := 'ao_dono';
        v_o_que := 'pediu outro dia';
      elsif not (v_dia between v_de and v_ate)
            and not exists (select 1 from public.agenda_alocacoes a
                             where a.service_order_id = m.service_order_id and a.estado in ('publicada', 'fixada')
                               and a.tipo <> 'reserva' and a.dia between v_de and v_ate) then
        -- (decisão do P4) o dia recusado não é dia do serviço ("não dá amanhã" no sábado, com o serviço na terça): não
        -- adivinho de qual dia ele fala
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá %s, mas não é dia do serviço',
                          case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                               else public._dia_curto(v_de) end);
      -- CORREÇÃO FASE 5: (item 9) tirar dias até longe demais do combinado ("vou viajar até 20/12") também não remarca sozinho
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_ate) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá até %s, mais de %s dias úteis depois do combinado: remarque você',
                          public._dia_curto(v_ate), cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid, daterange(v_de, v_ate, '[]'), null,
                 format('O %s pediu outro dia (%s não dá)', v_nome,
                        case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                             else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 16) o acesso com negação ("não sei onde vai estar a chave", "não tenho a chave", "ainda não
    -- sei") não é acesso dito: não vai para o campo da OS nem desliga a pergunta do acesso — vai ao dono
    elsif v_int = 'acesso' and public._agenda_normal(coalesce(v_trecho, '')) ~ '\m(nao sei|nao tenho|ainda nao)\M' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou do acesso, mas ainda não sabe (ou não tem) a chave';
    -- CORREÇÃO FASE 5: fim
    elsif v_int = 'acesso' and (v_do_dia or m.tipo = 'pode_atrasar') then
      v_x := public._agenda_cliente_anotar_acesso(m.id, v_rid, v_trecho, v_hoje, p_agora);
      v_efeito := 'anotou_acesso';
      v_acao := (v_x ->> 'acao_id')::uuid;
      v_texto := v_x ->> 'texto';
    else
      v_efeito := 'ao_dono';
      v_o_que := case when v_int = 'acesso' then 'falou do acesso' else 'não entendi o que ele quer' end;
    end if;
  exception when others then
    -- o efeito que falha não derruba o webhook: a resposta vai ao dono e o erro fica consultável
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a resposta do cliente falhou: ' || v_msg, 'agenda', 'cliente:resposta', 'error',
                                 jsonb_build_object('mensagem', m.id, 'resposta', v_rid, 'intencao', v_int, 'sqlstate', v_estado));
    v_efeito := 'ao_dono';
    v_acao := null;
    v_acorde := false;
    v_o_que := 'não consegui ler a resposta sozinho';
    v_texto := null;
  end;

  -- ao dono: a pergunta cliente_resposta (sem opções; some em 7 dias), e o acorde na hora quando é reclamação
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := coalesce(v_texto, format('O %s respondeu "%s" %s: %s. Não respondi nada; é com você.', v_nome,
                                        public._agenda_corta(coalesce(v_trecho, ''), 120), v_ref, v_o_que));
    v_perg := public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:' || v_rid, m.service_order_id, v_dia,
                                               case when v_do_dia then v_dia end, v_texto, 'ligado', p_agora,
                                               p_agora + c_pergunta_dias);
    if v_acorde then
      v_acao := public._agenda_cliente_acorde(m.service_order_id, 'cliente_resposta:' || v_rid, v_texto, v_hoje, v_hoje, v_perg);
    end if;
  end if;

  -- a mensagem respondida (antes das 48 h o "não respondeu" não a pega; depois, a pergunta dele se resolve)
  if v_efeito <> 'ambigua' then
    update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = v_rid
     where id = m.id and estado in ('enviada', 'sem_resposta');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('O %s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
  end if;
  update public.agenda_cliente_respostas
     set efeito = v_efeito, acao_id = v_acao, pergunta_id = v_perg, data_dita = coalesce((v_data ->> 'de')::date, data_dita)
   where id = v_rid;
  -- CORREÇÃO FASE 5: (item 15) o texto devolvido, quando é o da pergunta ao dono, sem artigo antes do nome ("Flávio
  -- respondeu …"), igual à pergunta; o das ações (confirmou, pediu, opt-out) fica como a ação gravada
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := public._agenda_cliente_sem_artigo(v_texto, m.service_order_id);
  end if;
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', v_efeito, 'intencao', v_int, 'texto', v_texto,
                            'resposta_id', v_rid, 'mensagem_id', m.id, 'acao_id', v_acao, 'pergunta_id', v_perg);
end;
$function$;

comment on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) is
  'Agenda de Produção (Fase 5, P4): a mensagem do cliente que chega pelo WhatsApp (o webhook chama depois da equipe e antes da confirmação de 30/09 e da conferência do recibo: o "ok" tem um dono só). modo_cliente desligado, número de ninguém (ou do dono, da equipe, de quem recebe diária), a mesma mensagem de novo ou sem mensagem da agenda esperando resposta (a última dos tipos que esperam, enviada dentro de cliente_resposta_validade e ainda sem resposta; em teste, a que teria saído) = consumiu false. Em teste: registra a resposta (efeito sombra, com a intenção) e consumiu false. Ligado, a 1ª que vale: duas OS ou dois clientes no número = ambígua (ao dono); áudio e mídia ao dono (o áudio NUNCA confirma); o SIM curto (_e_concordancia) confirma o M1/M3/M7/M10 e o M6 remarcado (_agenda_cliente_confirmar_dia: fixa o dia, com *desfaz*), registra a véspera e o acesso, é ciência no aviso de atraso, vai ao dono no "ficou pronto" e não faz nada no pós-serviço; opt-out = as vivas recusadas (opt_out) e o cadastro marcado, calado; reclamação (na hora, por acorde), negociação, acordo e pergunta ao dono; o dia pedido (data) e o recusado (remarcar, falta) — só nas mensagens que propõem um dia e com modo_proposta ligado — viram o "não antes de" e o bem indisponível com o replano (_agenda_cliente_pedido_de_dia, com *desfaz*; o dia combinado em até 1 dia útil = acorde); o dia passado, de hoje, o mesmo ou mais cedo que o combinado vai ao dono; o acesso dito vai para o campo da OS (_agenda_cliente_anotar_acesso, com *desfaz*); o resto ao dono. Ao dono = a pergunta cliente_resposta:<resposta> (some em 7 dias). A mensagem fica respondida (resposta_id) e a pergunta do "não respondeu" dela se resolve. O efeito que falha vai ao dono e a app_error_logs (cliente:resposta). {consumiu, modo, efeito, intencao, texto, resposta_id, mensagem_id, acao_id, pergunta_id}. Só service_role. CORREÇÃO FASE 5 (C1): (A1) a resposta só é da agenda quando a última mensagem da HBR ao número é a dela — o botão antigo ou outra mensagem outbound depois dela (_agenda_cliente_outra_conversa) = {consumiu:false, motivo:outra_conversa}, em teste também; (item 2) o opt-out vale para quem recebeu mensagem da agenda em 30 dias, mesmo sem mensagem esperando, depois de outra conversa ou com o número ambíguo (efeito opt_out, consumiu true); (item 16) o acesso com negação vai ao dono; (item 17) falta/remarcar com um número de dia não entendido vai ao dono; (item 9) o dia pedido ou o fim do recusado a mais de cliente_pedido_max_du dias úteis do combinado vai ao dono. CORREÇÃO FASE 5 (C2, item 15): o texto devolvido (o da pergunta cliente_resposta ao dono) sem artigo antes do nome.';

-- _agenda_cliente_da_os
create or replace function public._agenda_cliente_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  so        record;
  pl        public.os_planejamento%rowtype;
  v_tel     boolean;
  v_sem     boolean;
  v_conv    boolean;
  v_contato text;
  v_prom    jsonb;
  v_risco   jsonb;
  v_risco_t text;
  v_msgs    jsonb;
  v_total   int;
  v_esp     int;
  v_ped     int;
  v_esp_t   text;
  -- estrutura, não parâmetro: a lista curta do cartão (spec §5.6, "até 5"); o resto, *agenda clientes* mostra
  c_lista   constant int := 5;
begin
  select s.id, s.client_id, s.client_confirmed_for,
         public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(c.display_name, '')), ''), c.name)) as nome
    into so
    from public.service_orders s left join public.clients c on c.id = s.client_id
   where s.id = p_os;
  if so.id is null or so.client_id is null then
    return null;
  end if;
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;

  -- o contato (as mesmas regras do envio e do foco: o número que é de alguém da HBR conta como sem telefone)
  v_tel := public._agenda_cliente_telefone(so.client_id) is not null;
  v_sem := public._agenda_cliente_sem_mensagem(so.client_id);
  v_conv := public._agenda_cliente_conversou(so.client_id, v_agora);
  v_contato := case when not v_tel then 'sem telefone no cadastro'
                    when v_sem then 'pediu para não receber mensagens'
                    when not v_conv then 'não escreveu para a HBR no último ano; por ora só mando a quem já escreveu' end;

  -- o que foi dito ao cliente (≠ o plano) e se ainda vale
  if pl.prometido_ate is not null then
    v_risco := public._agenda_cliente_risco(p_os, p_hoje);
    if coalesce((v_risco ->> 'risco')::boolean, false) then
      v_risco_t := case
        when coalesce((v_risco ->> 'sem_data')::boolean, false)
          then 'Pode atrasar: o material ainda não tem previsão, então ainda não sei a data nova.'
        when v_risco ->> 'faixa_de' = v_risco ->> 'faixa_ate'
          then format('Pode atrasar: agora a previsão é %s.', public._dia_curto((v_risco ->> 'faixa_de')::date))
        else format('Pode atrasar: agora a previsão é de %s a %s.', public._dia_curto((v_risco ->> 'faixa_de')::date),
                    public._dia_curto((v_risco ->> 'faixa_ate')::date)) end
        || case when coalesce((v_risco ->> 'passou')::boolean, false) then ' A data que ele ouviu já passou.' else '' end;
    end if;
    v_prom := jsonb_build_object(
      'tipo', pl.prometido_tipo, 'de', coalesce(pl.prometido_de, pl.prometido_ate), 'ate', pl.prometido_ate,
      'original_ate', pl.prometido_original_ate, 'fonte', pl.prometido_fonte,
      'texto', case when coalesce(pl.prometido_de, pl.prometido_ate) = pl.prometido_ate then public._dia_curto(pl.prometido_ate)
                    else format('de %s a %s', public._dia_curto(pl.prometido_de), public._dia_curto(pl.prometido_ate)) end
               || format(' (%s, %s%s)',
                         case pl.prometido_tipo when 'firme' then 'data firme' when 'faixa' then 'uma faixa'
                                                else 'depende da peça' end,
                         case pl.prometido_fonte when 'mensagem' then 'por mensagem da agenda' when 'dono' then 'por você'
                                                 else 'pela confirmação' end,
                         coalesce(' em ' || public._dia_curto((pl.prometido_em at time zone 'America/Sao_Paulo')::date), ''))
               || case when pl.prometido_original_ate is not null and pl.prometido_original_ate <> pl.prometido_ate
                       then format('; a 1ª data dita foi %s', public._dia_curto(pl.prometido_original_ate)) else '' end,
      'risco_texto', v_risco_t);
  end if;

  -- as mensagens desta OS: as 5 mais recentes (a que vai sair primeiro, depois as que saíram), com o estado como o dono lê
  select count(*)::int into v_total from public.agenda_cliente_mensagens m where m.service_order_id = p_os;
  select coalesce(jsonb_agg(y.j order by y.quando desc, y.id desc), '[]'::jsonb) into v_msgs
    from (select m.id, coalesce(m.enviada_em, m.enviar_em) as quando,
                 jsonb_build_object(
                   'tipo', m.tipo,
                   'tipo_texto', public._agenda_maiuscula(public._agenda_cliente_tipo_texto(m.tipo)),
                   'quando_texto', case
                     -- a viva: quando sai ("agora", "amanhã às 09:00"; a do teste, só a que ainda vai sair); a que saiu
                     -- ou a do teste que teria saído: o dia e a hora
                     when m.enviada_em is null and m.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                          and (m.modo = 'ligado' or m.enviar_em > v_agora)
                       then public._agenda_cliente_quando_texto(m.enviar_em, v_agora)
                     else public._dia_curto((coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo')::date)
                          || ' às ' || to_char(coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo', 'HH24:MI') end,
                   'estado', m.estado,
                   'estado_texto', case
                     when m.modo = 'sombra' then case
                       when m.estado = 'recusada' then 'em teste: não sairia'
                       when m.enviar_em <= v_agora then 'em teste: teria saído'
                       else 'em teste: sairia' end
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'critica'
                       then 'é uma decisão sua: responda na conversa (1, 2 ou 3)'
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
                       then 'espera você'
                     when m.estado in ('registrada', 'aguardando_dono') and m.aprovacao = 'aprovada'
                       then format('você aprovou (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado in ('registrada', 'aguardando_dono')
                       then format('sai sozinha (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado = 'enfileirada' then 'na fila do WhatsApp'
                     when m.estado = 'enviada' then 'mandada'
                     when m.estado = 'sem_resposta' then 'mandada; sem resposta'
                     when m.estado = 'respondida'
                       then 'mandada; respondeu: ' || public._agenda_cliente_efeito_texto(a.efeito)
                     when m.recusa_motivo = 'segurada' then 'você segurou: não saiu'
                     else 'não saiu: ' || case
                       when m.recusa_motivo in ('modo', 'tipo_em_teste') then 'estava em teste'
                       when m.recusa_motivo = 'opt_out' then 'ele pediu para não receber mensagens'
                       when m.recusa_motivo = 'sem_telefone' then 'sem telefone no cadastro'
                       when m.recusa_motivo = 'sem_conversa' then 'ele não escreveu para a HBR no último ano'
                       when m.recusa_motivo in ('domingo', 'feriado', 'janela', 'vencida') then 'passou da hora'
                       when m.recusa_motivo in ('teto_dia', 'teto_semana', 'teto_total')
                         then 'ele já tinha recebido as mensagens que cabem'
                       -- o motivo do mesmo tipo recente vai pelo prefixo: o nome dele leva o número de horas, que a
                       -- varredura do agenda-sem-literal não deixa no corpo
                       when m.recusa_motivo = 'intervalo' or left(m.recusa_motivo, 10) = 'mesmo_tipo'
                         then 'ele tinha acabado de receber outra'
                       when m.recusa_motivo in ('status', 'data_mudou', 'material', 'desatualizada')
                         then 'o serviço mudou antes de sair'
                       when m.recusa_motivo = 'passou_da_data' then 'a data que ele ouviu já tinha passado'
                       else 'o texto não passou na conferência' end end,
                   'texto', m.texto,
                   'em_teste', m.modo = 'sombra',
                   'espera_voce', m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')) as j
            from public.agenda_cliente_mensagens m
            left join public.agenda_cliente_respostas a on a.id = m.resposta_id
           where m.service_order_id = p_os
           order by coalesce(m.enviada_em, m.enviar_em) desc, m.id desc
           limit c_lista) y;

  -- o que espera o dono: a mesma conta do foco clientes (a mensagem que espera *manda cliente*, a decisão do aviso, a
  -- resposta que foi ao dono); a palavra só em ligado (em teste ela responde que nada sai ainda)
  -- CORREÇÃO FASE 5: (regressão B3) a conta do que espera o dono direto nas tabelas — as mesmas condições do bloco
  -- "Esperando você" do foco clientes (a mensagem que espera *manda cliente* ou que é decisão; a decisão sem mensagem; a
  -- resposta que foi ao dono, sem o "não respondeu"), e desligado = 0 como o foco —, sem montar o foco inteiro (e o d10 de
  -- cada cliente) a cada abertura do cartão
  v_esp := case when cf.modo_cliente = 'desligado' then 0 else
             (select count(*)::int from public.agenda_cliente_mensagens m
               where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')
                 and m.service_order_id = p_os)
           + (select count(*)::int from public.agenda_perguntas q
               where q.modo = 'ligado' and q.estado = 'aberta' and (q.expira_em is null or q.expira_em > v_agora)
                 and q.service_order_id = p_os
                 and ((q.tipo = 'cliente_resposta' and q.chave not like 'cliente_resposta:sem_resposta:%')
                      or (q.tipo = 'cliente_aviso'
                          and not exists (select 1 from public.agenda_cliente_mensagens x where x.pergunta_id = q.id)))) end;
  if v_esp is null then
  -- CORREÇÃO FASE 5: fim
  v_esp := coalesce((public._agenda_ver_clientes(p_os, p_hoje) #>> '{dados,esperando}')::int, 0);
  -- CORREÇÃO FASE 5: o foco inteiro não roda mais (a conta acima nunca é nula)
  end if;
  -- CORREÇÃO FASE 5: fim
  select count(*)::int into v_ped from public.agenda_cliente_mensagens m
   where m.service_order_id = p_os and m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida';
  if cf.modo_cliente = 'ligado' and v_esp > 0 then
    v_esp_t := case when v_ped > 0
                    then format('%s esperando você: *manda cliente %s* manda; *segura cliente %s* segura.',
                                public._agenda_plural(v_ped, 'mensagem', 'mensagens'), so.nome, so.nome)
                    else '' end
               || case when v_esp > v_ped
                       then case when v_ped > 0 then ' ' else '' end
                            || 'Há decisão ou resposta dele esperando você: responda na conversa (*agenda clientes* mostra).'
                       else '' end;
  end if;

  return jsonb_build_object(
    'modo', cf.modo_cliente,
    'em_teste', cf.modo_cliente = 'sombra',
    'em_teste_texto', case when cf.modo_cliente = 'sombra'
                           then 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.' end,
    'nome', so.nome,
    'telefone_ok', v_tel, 'conversou', v_conv, 'opt_out', v_sem, 'contato_texto', v_contato,
    'servico', pl.servico_cliente,
    'prometido', v_prom,
    'confirmado_texto', case when so.client_confirmed_for is not null
                             then format('Ele confirmou %s.',
                                         public._dia_curto((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date)) end,
    'mensagens', v_msgs,
    'mensagens_mais', greatest(v_total - jsonb_array_length(v_msgs), 0),
    'esperando_voce', jsonb_build_object('n', v_esp, 'texto', v_esp_t));
end;
$function$;

comment on function public._agenda_cliente_da_os(uuid, date) is
  'Agenda de Produção (Fase 5, P6): a chave cliente do cartão "Plano" (os_plano_da_os) — {modo, em_teste, em_teste_texto, nome, telefone_ok, conversou, opt_out (não recebe: opt-out, inativo ou bloqueado), contato_texto ("sem telefone no cadastro" | "pediu para não receber mensagens" | "não escreveu para a HBR no último ano…" | null), servico (como o serviço é dito ao cliente), prometido {tipo, de, ate, original_ate, fonte, texto "qui 05/11 (data firme, por mensagem da agenda em qui 22/10)", risco_texto (_agenda_cliente_risco: "Pode atrasar: agora a previsão é de qui 12/11 a sex 13/11.")} | null, confirmado_texto, mensagens (as 5 mais recentes desta OS: [{tipo, tipo_texto, quando_texto, estado, estado_texto, texto, em_teste, espera_voce}]), mensagens_mais, esperando_voce {n (a conta do foco clientes, _agenda_ver_clientes), texto (só em ligado: *manda cliente <nome>* / *segura cliente <nome>*)}}. Nenhum botão de mandar: a aprovação é pela palavra. A hora de agora: agenda.agora (a bancada), senão now(). Invoker e sem grant: só os_plano_da_os a chama. null sem a OS ou sem o cliente. CORREÇÃO FASE 5 (C2, B3): esperando_voce.n é contado direto nas tabelas (as mesmas condições do bloco "Esperando você" do foco), sem chamar _agenda_ver_clientes.';

-- ── 4. Portas ───────────────────────────────────────────────────────────────────────────────────────────

-- As novas: internas (search_path fixo) — ninguém de fora, nem o service_role. Só outra função da agenda as chama.
revoke all on function
  public._agenda_cliente_sem_artigo(text, uuid),
  public._agenda_cliente_tirar_prometido(uuid, uuid, timestamptz, text),
  public._agenda_cliente_erro_da_os(text, uuid, text, text, date)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas para a migration se bastar):
-- as internas (ninguém de fora)
revoke all on function
  public._agenda_cliente_texto_do_aviso(text, text, uuid, jsonb, date),
  public._agenda_cliente_perguntar(text, text, uuid, date, date, text, text, timestamptz, timestamptz),
  public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid),
  public._agenda_cliente_enviada(), public._agenda_cliente_fila(date, timestamptz),
  public._agenda_cliente_motivo_texto(text),
  public._agenda_cliente_revalidar(uuid, timestamptz), public._agenda_cliente_enfileirar(uuid, timestamptz),
  public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz),
  public._agenda_cliente_acorde(uuid, text, text, date, date, uuid),
  public._agenda_cliente_material(date, timestamptz), public._agenda_cliente_mudanca_no_dia(date, timestamptz),
  public._agenda_cliente_confirmar(date, timestamptz), public._agenda_cliente_atraso(date, timestamptz),
  public._agenda_cliente_andamento(date, timestamptz), public._agenda_cliente_pronto(date, timestamptz),
  public._agenda_cliente_pos_servico(date, timestamptz),
  public._agenda_cliente_da_os(uuid, date)
  from public, anon, authenticated, service_role;
-- as leituras (authenticated e service_role; nunca anon)
revoke all on function
  public._agenda_cliente_texto(text, text, uuid, jsonb, date), public._agenda_cliente_ouviu(uuid, date, timestamptz),
  public._agenda_cliente_risco(uuid, date), public._agenda_cliente_fechamento(date),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
  public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz)
  from public, anon;
grant execute on function
  public._agenda_cliente_texto(text, text, uuid, jsonb, date), public._agenda_cliente_ouviu(uuid, date, timestamptz),
  public._agenda_cliente_risco(uuid, date), public._agenda_cliente_fechamento(date),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
  public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz)
  to authenticated, service_role;
-- a resposta do cliente: só o webhook (service_role)
revoke all on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) to service_role;
