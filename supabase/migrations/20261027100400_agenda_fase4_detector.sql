-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P4: o detector da conversa do fornecedor —
-- o que o fornecedor (ou a HBR) diz no WhatsApp sobre a entrega ("Já foi coletado", "chega aqui amanhã", "5 dias úteis",
-- "Recebeu o compressor?") vira um sinal no banco; a compra já ligada e única daquele fornecedor tem a previsão atualizada
-- sozinha, com *desfaz*; o resto vira pergunta ao dono; o "Recebeu?" do fornecedor vira o "chegou?". Tudo atrás de
-- agenda_config.modo_detector, que nasce desligado (a migration de dado 20261027101000 põe em sombra) e só liga medido.
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§3.1 itens 1, 2 e 9, §3.2, §5.4, §6.2, §6.3, d3, d8, d14). Decisões do
-- dono 23/10 (gestor autônomo; o LLM nunca calcula data). Depende de 20261027100000 (material_sinais, os modos e os
-- parâmetros do detector), 100100 (o prazo do fornecedor), 100200 (a sincronização) e 100300 (a pergunta do material, o
-- aviso que lê a pergunta previsao_fornecedor e a ação material da nota).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (9 funções novas; 4 recriadas; nenhuma tabela, nenhuma lista fechada, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f4p4/montar-migration.mjs: as partes escritas à mão
-- e os corpos copiados da migration MAIS NOVA de cada função recriada, com cada troca "-- FASE 4:" conferida (uma vez só;
-- todas só ACRESCENTAM: nenhuma linha antiga sai do corpo).
--
-- POR QUE: o fornecedor avisa pelo WhatsApp e ninguém anota. No caso do compressor da OS-00104 (13/10): a HBR escreveu
-- "chega aqui amanhã se eles retirarem hoje" às 14:01, o Mateus "Já foi coletado" às 17:19 — e a OS ficou "aguardando
-- peças" sem previsão; em 20/10 o Mateus perguntou "Recebeu o compressor?" e ninguém respondeu. A previsão de qua 14/10
-- estava na conversa.
--
-- O QUE MUDA:
--   1. agenda_mensagens_de_fornecedor (nova; só service_role; o acompanhar-conversas chama a cada 15 min): as mensagens
--      das últimas detector_janela_horas dos fornecedores ELEGÍVEIS que ainda não viraram sinal, com as compras vivas de
--      cada um (rótulo sem valor). Elegível = ativo, sem opt-out, telefone de 10+ dígitos que NÃO é do dono, da equipe, de
--      payee nem de cliente com OS (NOVO-agenda-34: o dono e o Rodrigo também estão cadastrados como fornecedor), e com
--      COMPRA VIVA (linha viva da carteira, OC aberta recente, nota a caminho, pergunta do Pix aberta: NOVO-agenda-35, o
--      contador não entra). Desligado = [].
--   2. material_sinal_registrar (nova; só service_role): o sinal, uma vez por mensagem e tipo. A data sai da EXPRESSÃO dita
--      pelo banco (agenda_data_dita com o dia da mensagem em Brasília; prazo em dias úteis a partir do despacho; despacho =
--      o prazo do fornecedor). O TS só achou a expressão (_shared/ai/promessa.ts, sem IA); o modelo leve só escolheu QUAL
--      compra quando havia mais de uma (_shared/agenda/casar-fornecedor.ts).
--   3. _agenda_material_sinais (o passo "sinais" do material; o P5 o chama em agenda_material_vigiar): a chegada condicional
--      espera o despacho do fornecedor e vai junto com ele (d8); a compra já ligada e única do fornecedor recebe a previsão
--      (fonte fornecedor) com a ação material, origem fornecedor, e o *desfaz* (só com modo_detector ligado); o resto vira
--      a pergunta previsao_fornecedor (sinal:<id>) e o "Recebeu?" vira o chegou? (chegou:fornecedor:<linha>:<dia>), as duas
--      no modo do material; em sombra só o que faria. O julgamento pelo fato (certo, errado, sem como saber).
--   4. agenda_detector_precisao (nova; leitura, admin/financeiro): a precisão e o portão para ligar (pronto_para_ligar só com
--      detector_minimo_julgados casos conferidos e detector_precisao_minima de acerto; com menos, continua em teste).
--   5. _agenda_desfazer_material (nova; sem grant) e agenda_desfazer (recriada, bloco -- FASE 4:): o *desfaz* da ação
--      material — a do detector e a da nota do P3 (antes/depois = {linhas[], remessa_id}): as linhas voltam inteiras se
--      ninguém mexeu nelas depois; a da nota deixa de valer para a linha.
--   6. _os_material_previsao_original (recriada, bloco -- FASE 4:): o desfazer volta também o original da previsão que a
--      própria ação criou (exceção pela chave local agenda.desfazer_material, como a agenda.porta).
--   7. _agenda_vigia_limpeza e _agenda_vigia_chegou (recriadas da Fase 2, blocos -- FASE 4:): o chegou? que o fornecedor
--      abriu se resolve quando a linha chega (a limpeza da Fase 2 o resolveria na hora, pela chave), e a vigia não pergunta
--      de novo enquanto ele está aberto (sem duplicar, d14).
--   8. Auxiliares: _agenda_chave_telefone, _agenda_fones_que_nao_sao_fornecedor, _agenda_compras_vivas.
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, compra, OC ou cotação. A frase de dinheiro (boleto, Pix, pagamento)
-- nunca vira sinal (o parser a descarta); nenhuma mensagem sai para o fornecedor (isso é do P5, atrás de modo_fornecedor).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase4_detector.sql):
--   · A spec recriava só agenda_desfazer. Também são recriadas: _agenda_vigia_limpeza (a chave chegou:fornecedor:<linha>:
--     <dia> cairia no "a peça saiu da OS" da limpeza da Fase 2, que lê a 2ª parte da chave como o item, e a pergunta
--     morreria no mesmo tique), _agenda_vigia_chegou (sem o bloco, a vigia abriria o seu chegou? da mesma linha ao vencer a
--     previsão: dois "chegou?" do mesmo compressor) e _os_material_previsao_original (sem a exceção, o desfazer deixaria o
--     original que a ação desfeita criou — a nota do P1 previa a exceção por set_config).
--   · O chegou? do fornecedor é gravado por _agenda_material_perguntar (o molde do material, com a validade de
--     material_pergunta_validade), não por _agenda_vigia_perguntar: o modo é o do material de qualquer jeito, e a da vigia
--     não é executável pelo service_role.
--   · O que a HBR escreveu sem condição e sem compra ligada ("vou ver se chega amanhã" ao fornecedor) não vira pergunta
--     ao dono (seria perguntar a ele o que ele mesmo disse): fica descartado com o motivo. Com a compra ligada, vira a
--     previsão com fonte dono (C), como a spec.
--   · "Desfazer": a linha volta se NENHUMA coluna mudou depois (a linha toda, menos o histórico, igual ao "depois"), e não só
--     a hora da última mudança: numa transação now() se repete. A chegada pela nota desfeita tira a nota da linha
--     (remessa_id nulo): sem isso a próxima sincronização a poria na mão de novo.
--   · A previsão nova da compra ligada grava a fonte fornecedor também em os_material.fonte: com a fonte oc (a linha da OC
--     sem data), a sincronização refaria a linha do sistema e apagaria a previsão no tique seguinte.
--   · agenda_detector_precisao sem datas = os últimos 14 dias; julgados = certo + errado (o "sem como saber" fica fora da
--     conta); o sinal que foi junto com o despacho não conta duas vezes.
--
-- O QUE NÃO MUDA: detectarPromessa (a promessa do dono); a conversa e o envio do WhatsApp; a vigia da Fase 2 fora dos dois
-- blocos; o desfazer das Fases 2 e 3; o financeiro inteiro. Nenhum cron: o passo "sinais" roda pelo agenda_material_vigiar
-- (P5); a leitura e o registro, pelo acompanhar-conversas (deploy com OK).
--
-- ORDEM DE LIGAR: depois de 20261027100000..100300; ANTES do deploy do acompanhar-conversas (que chama as duas RPCs — sem
-- elas, o passo é silêncio: { pulado }). Com modo_detector desligado (a linha nasce assim), nada é lido nem gravado.
--
-- PROVA: supabase/tests/agenda_fase4_detector.sql (D0–D8; o replay da OS-00104 com a conversa real em
-- scripts/bancada-agenda/fixture-replay-fornecedor-0104.sql). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261027100000..100300):
--   npx supabase db query --linked -f supabase/migrations/20261027100400_agenda_fase4_detector.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027100400', 'agenda_fase4_detector');"
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.


-- ── 1. Quem nunca é fornecedor e quem tem compra viva ───────────────────────────────────────────────────

-- A chave do telefone: os 8 últimos dígitos (imune ao 9º dígito e ao 55/DDD), a mesma de read_supplier_messages
-- (_shared/ai/tools/quotes.ts) e da categoria "fornecedor" do acompanhar-conversas (20261006120000). Menos de 8 = null.
create or replace function public._agenda_chave_telefone(p_fone text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when length(regexp_replace(coalesce(p_fone, ''), '\D', '', 'g')) >= 8
              then right(regexp_replace(p_fone, '\D', '', 'g'), 8) end;
$function$;

comment on function public._agenda_chave_telefone(text) is
  'Agenda de Produção (Fase 4, P4): a chave de um telefone — os 8 últimos dígitos (a mesma de read_supplier_messages e da categoria fornecedor do acompanhar-conversas); menos de 8 dígitos = null.';

-- Os telefones que NUNCA são de fornecedor, mesmo cadastrados como fornecedor (NOVO-agenda-34): o dono e a equipe
-- (app_users, o telefone e o normalizado), quem recebe diária (payees) e o cliente que tem OS. 315 dos 348 fornecedores
-- com telefone de cliente são o mesmo ente (cadastro duplo): só o cliente COM OS sai, como a spec mediu.
create or replace function public._agenda_fones_que_nao_sao_fornecedor()
 returns setof text
 language sql
 stable
 set search_path to 'public'
as $function$
  select k from (
    select public._agenda_chave_telefone(u.phone_normalized) as k from public.app_users u
    union
    select public._agenda_chave_telefone(u.phone) from public.app_users u
    union
    select public._agenda_chave_telefone(p.phone) from public.payees p
    union
    select public._agenda_chave_telefone(cl.phone) from public.clients cl
     where exists (select 1 from public.service_orders so where so.client_id = cl.id)
  ) x
  where k is not null;
$function$;

comment on function public._agenda_fones_que_nao_sao_fornecedor() is
  'Agenda de Produção (Fase 4, P4): as chaves (8 últimos dígitos) dos telefones que nunca são lidos como fornecedor — o dono e a equipe (app_users.phone e phone_normalized), os payees e os clientes que têm alguma OS (NOVO-agenda-34: o dono está cadastrado como fornecedor; o Rodrigo também).';

-- As linhas de material VIVAS de cada fornecedor (falta, comprado ou a caminho, de OS da carteira): a do fornecedor da
-- linha, a da OC dele (linha origem oc) e a da nota dele (remessa_id). Uma linha por (fornecedor, linha).
create or replace function public._agenda_compras_vivas(p_hoje date)
 returns table (fornecedor_id uuid, os_material_id uuid, service_order_id uuid, numero text, cliente_curto text, descricao text,
                situacao text, comprado_em date, previsao_ate date)
 language sql
 stable
 set search_path to 'public'
as $function$
  with cart as (select k.service_order_id, k.numero, k.cliente_curto from public.os_carteira(p_hoje) k),
  donos as (
    select m.fornecedor_id as f, m.id from public.os_material m where m.fornecedor_id is not null
    union
    select po.supplier_id, m.id from public.os_material m
      join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
      join public.purchase_orders po on po.id = poi.purchase_order_id
     where po.supplier_id is not null
    union
    select r.fornecedor_id, m.id from public.os_material m
      join public.material_remessas r on r.id = m.remessa_id
     where r.fornecedor_id is not null
  )
  select d.f, m.id, m.service_order_id, cart.numero, cart.cliente_curto, m.descricao, m.situacao, m.comprado_em, m.previsao_ate
    from donos d
    join public.os_material m on m.id = d.id
    join cart on cart.service_order_id = m.service_order_id
   where m.situacao in ('falta', 'comprado', 'a_caminho');
$function$;

comment on function public._agenda_compras_vivas(date) is
  'Agenda de Produção (Fase 4, P4): as linhas de material vivas (falta, comprado, a caminho) das OS da carteira, por fornecedor — o da linha, o da OC da linha (origem oc) e o da nota ligada (remessa_id). As candidatas da mensagem do fornecedor.';

-- ── 2. O que o detector lê: as mensagens dos fornecedores com compra viva ──────────────────────────────

create or replace function public.agenda_mensagens_de_fornecedor(p_hoje date default public._hoje_brt(),
                                                                 p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  c public.agenda_config := public._agenda_cfg();
  v jsonb;
begin
  if c.modo_detector not in ('sombra', 'ligado') then
    return '[]'::jsonb;
  end if;
  with nao_sao as (
    select k from public._agenda_fones_que_nao_sao_fornecedor() k
  ),
  linhas as (
    select * from public._agenda_compras_vivas(p_hoje)
  ),
  -- Compra viva: linha viva da carteira, OC aberta e recente (oc_viva_dias), nota a caminho ou a pergunta do Pix aberta.
  vivos as (
    select distinct x.f from (
      select l.fornecedor_id as f from linhas l
      union all
      select po.supplier_id from public.purchase_orders po
       where po.status in ('draft', 'sent', 'partial') and po.supplier_id is not null
         and po.created_at >= p_agora - make_interval(days => c.oc_viva_dias)
      union all
      select r.fornecedor_id from public.material_remessas r where r.estado = 'a_caminho' and r.fornecedor_id is not null
      union all
      select (public._agenda_pix_fonte(split_part(q.chave, ':', 2), split_part(q.chave, ':', 3)::uuid) ->> 'fornecedor_id')::uuid
        from public.agenda_perguntas q
       where q.tipo = 'pix_material' and q.estado = 'aberta' and q.chave ~ '^pix:(tx|cmp):[0-9a-f-]{36}$') x
     where x.f is not null
  ),
  forn as (
    select s.id, public._agenda_chave_telefone(s.phone) as chave
      from public.suppliers s
      join vivos on vivos.f = s.id
     where coalesce(s.active, true) and not coalesce(s.opt_out_whatsapp, false)
       and length(regexp_replace(coalesce(s.phone, ''), '\D', '', 'g')) >= 10
       and not exists (select 1 from nao_sao n where n.k = public._agenda_chave_telefone(s.phone))
  ),
  msgs as (
    -- o mesmo telefone em dois fornecedores vivos: o que a mensagem já aponta (supplier_id), senão o menor id
    select distinct on (m.id) m.id, m.direction, m.body, m.occurred_at, f.id as fornecedor
      from public.whatsapp_messages m
      join forn f on f.chave = public._agenda_chave_telefone(m.phone_normalized)
     where m.occurred_at >= p_agora - make_interval(hours => c.detector_janela_horas)
       and m.occurred_at <= p_agora
       and not coalesce(m.is_broadcast, false)
       and nullif(btrim(coalesce(m.body, '')), '') is not null
       and not exists (select 1 from public.material_sinais s where s.whatsapp_message_id = m.id)
     order by m.id, (m.supplier_id is not distinct from f.id) desc, f.id
  ),
  lote as (
    select * from msgs order by occurred_at desc, id desc limit c.detector_lote_max
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'msg_id', l.id, 'fornecedor_id', l.fornecedor, 'fornecedor', public._agenda_fornecedor_curto(l.fornecedor),
           'direcao', case l.direction when 'inbound' then 'recebida' else 'enviada' end,
           'texto', left(l.body, 4000), 'em', l.occurred_at,
           'compras', coalesce((
             select jsonb_agg(jsonb_build_object('n', z.n, 'os', z.service_order_id, 'os_material_id', z.os_material_id,
                                                 'rotulo', z.rotulo, 'situacao', z.situacao, 'comprado_em', z.comprado_em,
                                                 'previsao_ate', z.previsao_ate) order by z.n)
               from (select li.*,
                            row_number() over (order by li.situacao = 'falta', li.comprado_em desc nulls last,
                                                        li.numero collate "C", li.os_material_id) as n,
                            format('%s: %s (%s)', coalesce(li.cliente_curto, li.numero), public._agenda_linha_curta(li.descricao),
                                   case when li.situacao = 'falta' then 'a comprar'
                                        when li.comprado_em is not null then 'comprado ' || to_char(li.comprado_em, 'DD/MM')
                                        else 'comprado' end) as rotulo
                       from linhas li
                      where li.fornecedor_id = l.fornecedor) z), '[]'::jsonb))
         order by l.occurred_at, l.id), '[]'::jsonb)
    into v
    from lote l;
  return v;
end;
$function$;

comment on function public.agenda_mensagens_de_fornecedor(date, timestamptz) is
  'Agenda de Produção (Fase 4, P4): as mensagens (as duas direções) das últimas detector_janela_horas dos fornecedores ELEGÍVEIS que ainda não viraram sinal, até detector_lote_max (as mais novas), em ordem de occurred_at — [{msg_id, fornecedor_id, fornecedor, direcao recebida|enviada, texto, em, compras:[{n, os, os_material_id, rotulo "Flávio: Compressor 12V de… (comprado 13/10)", situacao, comprado_em, previsao_ate}]}], sem valor. Elegível: ativo, sem opt-out, telefone com 10+ dígitos cujos 8 últimos não são do dono, da equipe, de payee nem de cliente com OS (NOVO-agenda-34), e com COMPRA VIVA — linha viva da carteira, OC aberta recente, nota a caminho ou pergunta do Pix aberta dele (NOVO-agenda-35: o contador não entra). modo_detector desligado = []. Só lê. Só service_role (o acompanhar-conversas).';

-- ── 3. O sinal: a expressão dita vira data no banco, com o dia da mensagem ──────────────────────────────

create or replace function public.material_sinal_registrar(p_msg uuid, p_fornecedor uuid, p_tipo text, p_expressao text,
                                                           p_condicional boolean, p_trecho text, p_candidatos jsonb,
                                                           p_os_material uuid, p_casou_por text, p_confianca numeric,
                                                           p_hoje date default public._hoje_brt(),
                                                           p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_m      record;
  v_dia    date;
  v_de     date;
  v_ate    date;
  v_dd     jsonb;
  v_motivo text;
  v_norm   text;
  v_nums   int[];
  v_base   date;
  v_unid   text;
  v_cand   jsonb;
  v_lin    uuid;
  v_os     uuid;
  v_casou  text;
  v_id     uuid;
  v_trecho text := btrim(coalesce(p_trecho, ''));
begin
  if c.modo_detector not in ('sombra', 'ligado') then
    return jsonb_build_object('pulado', true);
  end if;
  if p_tipo is null or p_tipo not in ('despacho', 'chegada', 'prazo', 'perguntou_chegou', 'atraso') then
    raise exception 'O tipo do sinal "%" não existe.', p_tipo using errcode = '22023';
  end if;
  if char_length(v_trecho) < 3 then
    raise exception 'O sinal precisa do trecho da mensagem.' using errcode = '22023';
  end if;
  select w.id, w.direction, w.occurred_at into v_m from public.whatsapp_messages w where w.id = p_msg;
  if not found then
    raise exception 'Não achei a mensagem %.', p_msg using errcode = 'P0002';
  end if;
  v_dia := (v_m.occurred_at at time zone 'America/Sao_Paulo')::date;

  -- As candidatas como o TS mandou, só as chaves que interessam (sem valor); a escolhida só vale se for uma delas.
  v_cand := coalesce((select jsonb_agg(jsonb_build_object('n', e -> 'n', 'os', e -> 'os', 'os_material_id', e -> 'os_material_id',
                                                          'rotulo', left(e ->> 'rotulo', 120)) order by o)
                        from jsonb_array_elements(case when jsonb_typeof(p_candidatos) = 'array' then p_candidatos
                                                       else '[]'::jsonb end) with ordinality t(e, o)
                       where o <= 20), '[]'::jsonb);
  if p_os_material is not null
     and exists (select 1 from jsonb_array_elements(v_cand) e where e ->> 'os_material_id' = p_os_material::text) then
    select m.id, m.service_order_id into v_lin, v_os from public.os_material m where m.id = p_os_material;
  end if;
  v_casou := case when p_casou_por = 'unico' and jsonb_array_length(v_cand) = 1 and v_lin is not null then 'unico'
                  when p_casou_por = 'modelo' and v_lin is not null then 'modelo'
                  else 'nenhum' end;

  -- A data pela expressão, no dia da mensagem (Brasília). O LLM nunca entra aqui.
  begin
    if p_tipo in ('chegada', 'atraso') and nullif(btrim(p_expressao), '') is not null then
      v_dd := public.agenda_data_dita(p_expressao, v_dia, 'futuro');
      v_de := (v_dd ->> 'de')::date;
      v_ate := (v_dd ->> 'ate')::date;
    elsif p_tipo = 'prazo' then
      -- "5 dias úteis", "3 a 5 dias úteis", "5 dias" (dias úteis, como a spec), "10 dias corridos". A contagem parte do
      -- despacho do mesmo fornecedor no mesmo dia, se houve; senão do dia da mensagem.
      v_norm := public._agenda_normal(p_expressao);
      v_nums := array(select x[1]::int from regexp_matches(v_norm, '(\d{1,3})', 'g') x);
      if cardinality(v_nums) = 0 then
        raise exception 'sem número' using errcode = '22007';
      end if;
      v_base := coalesce((select s.dia from public.material_sinais s
                           where s.fornecedor_id is not distinct from p_fornecedor and s.tipo = 'despacho' and s.dia = v_dia
                           order by s.ocorreu_em limit 1), v_dia);
      v_unid := case when v_norm ~ '\mcorrid' then 'dias' else 'dias úteis' end;
      v_ate := (public.agenda_data_dita(format('daqui a %s %s', (select max(x) from unnest(v_nums) x), v_unid), v_base) ->> 'ate')::date;
      v_de := (public.agenda_data_dita(format('daqui a %s %s', (select min(x) from unnest(v_nums) x), v_unid), v_base) ->> 'ate')::date;
    elsif p_tipo = 'despacho' then
      v_ate := public._agenda_chegada_estimada(p_fornecedor, v_dia);
      v_de := v_ate;
      if v_ate is null then
        v_motivo := 'não sei em quantos dias chega dele';
      end if;
    end if;
  exception when sqlstate '22007' then
    v_de := null;
    v_ate := null;
    v_motivo := 'não entendi a data';
  end;

  insert into public.material_sinais (whatsapp_message_id, fornecedor_id, direcao, ocorreu_em, dia, tipo, expressao, condicional,
                                      trecho, data_de, data_ate, candidatos, os_material_id, service_order_id, casou_por,
                                      modelo_confianca, modo, motivo)
  values (p_msg, p_fornecedor, case v_m.direction when 'inbound' then 'recebida' else 'enviada' end, v_m.occurred_at, v_dia,
          p_tipo, left(nullif(btrim(p_expressao), ''), 60), coalesce(p_condicional, false), left(v_trecho, 300),
          v_de, v_ate, v_cand, v_lin, v_os, v_casou,
          case when p_confianca is not null then least(greatest(round(p_confianca, 2), 0), 1) end,
          c.modo_detector, v_motivo)
  on conflict (whatsapp_message_id, tipo) do nothing
  returning id into v_id;
  if v_id is null then
    select s.id, s.data_de, s.data_ate into v_id, v_de, v_ate
      from public.material_sinais s where s.whatsapp_message_id = p_msg and s.tipo = p_tipo;
    return jsonb_build_object('id', v_id, 'data_de', v_de, 'data_ate', v_ate, 'novo', false);
  end if;
  return jsonb_build_object('id', v_id, 'data_de', v_de, 'data_ate', v_ate, 'novo', true);
end;
$function$;

comment on function public.material_sinal_registrar(uuid, uuid, text, text, boolean, text, jsonb, uuid, text, numeric, date, timestamptz) is
  'Agenda de Produção (Fase 4, P4): registra o que o detector achou numa mensagem do fornecedor (material_sinais, uma por mensagem e tipo; on conflict nada). A data sai da EXPRESSÃO dita, no dia da mensagem em Brasília: chegada/atraso → agenda_data_dita (faixa = data_de/data_ate); prazo ("5 dias úteis", "3 a 5 dias úteis", "5 dias" = úteis, "N dias corridos") a partir do despacho do mesmo dia; despacho → _agenda_chegada_estimada (classe desconhecida = sem data, "não sei em quantos dias chega dele"); perguntou_chegou sem data; expressão que o banco não entende = sem data, "não entendi a data". A escolhida só vale se for uma das candidatas; unico só com uma candidata. O modo é o de agora (desligado = {pulado}). {id, data_de, data_ate, novo}. Só service_role.';

-- ── 4. O passo do material "sinais": o que o gestor faz (ligado) ou faria (sombra) ──────────────────────

create or replace function public._agenda_material_sinais(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c         public.agenda_config := public._agenda_cfg();
  v_modo    text := c.modo_detector;
  v_mmodo   text := public._agenda_material_modo();
  s         public.material_sinais%rowtype;
  v_ch      public.material_sinais%rowtype;
  l         public.os_material%rowtype;
  v_tem_l   boolean;
  v_ligada  boolean;
  v_exec    boolean;
  v_de      date;
  v_ate     date;
  v_trecho  text;
  v_fonte   text;
  v_junto   uuid;
  v_forn    text;
  v_quando  text;
  v_dia_txt text;
  v_cli     text;
  v_curto   text;
  v_numero  text;
  v_acao    text;
  v_txt     text;
  v_motivo  text;
  v_faria   jsonb;
  v_opc     jsonb;
  v_lista   text[];
  v_os_ids  uuid[];
  v_perda   date;
  v_antes   jsonb;
  v_depois  jsonb;
  v_acao_id uuid;
  v_perg    uuid;
  v_j       text;
  v_lo      date;
  v_hi      date;
  v_k       int;
  n_prev    int := 0;
  n_perg    int := 0;
  n_cheg    int := 0;
  n_esp     int := 0;
  n_desc    int := 0;
  n_teste   int := 0;
  n_jul     int := 0;
  n_venc    int := 0;
begin
  if v_modo not in ('sombra', 'ligado') then
    return jsonb_build_object('pulado', true);
  end if;
  -- o dia da escrita (o gatilho do original da previsão grava previsao_original_em com ele)
  perform set_config('agenda.hoje', p_hoje::text, true);

  -- (0) O teste (sombra) que passou de 7 dias sai da fila e fica para o julgamento (spec §5.4).
  update public.material_sinais x set estado = 'descartado'
   where x.estado = 'registrado' and x.faria <> '{}'::jsonb and x.dia < p_hoje - 7;
  get diagnostics n_venc = row_count;

  -- (1) Cada sinal ainda sem decisão, na ordem em que foi dito.
  for s in select x.* from public.material_sinais x
            where x.estado = 'esperando' or (x.estado = 'registrado' and x.faria = '{}'::jsonb)
            order by x.ocorreu_em, x.id
            for update loop
    v_forn := coalesce(public._agenda_fornecedor_curto(s.fornecedor_id), 'O fornecedor');
    v_quando := public._dia_curto(s.dia) || ', ' || to_char(s.ocorreu_em at time zone 'America/Sao_Paulo', 'HH24:MI');
    v_exec := s.modo = 'ligado' and v_modo = 'ligado';
    v_junto := null;
    v_de := s.data_de;
    v_ate := s.data_ate;
    v_trecho := s.trecho;
    v_acao := null;
    v_motivo := null;
    v_txt := null;
    v_opc := '[]'::jsonb;
    v_os_ids := '{}';

    -- (a) A chegada que depende de uma condição ("chega aqui amanhã se eles retirarem hoje", d8): espera o despacho do
    -- fornecedor até o fim do dia útil seguinte; o despacho a leva junto (b); vencida sem despacho, sai.
    if s.tipo = 'chegada' and s.condicional then
      if p_hoje > public.agenda_somar_du(s.dia, 1) then
        update public.material_sinais
           set estado = 'descartado', faria = jsonb_build_object('acao', 'nada'),
               motivo = 'a condição não se confirmou: o fornecedor não avisou que despachou'
         where id = s.id;
        n_desc := n_desc + 1;
      elsif s.estado <> 'esperando' then
        update public.material_sinais
           set estado = 'esperando',
               faria = jsonb_build_object('acao', 'esperar', 'ate', public.agenda_somar_du(s.dia, 1), 'data_de', s.data_de,
                                          'data_ate', s.data_ate),
               motivo = format('espero o fornecedor confirmar o despacho até %s', public._dia_curto(public.agenda_somar_du(s.dia, 1)))
         where id = s.id;
        n_esp := n_esp + 1;
      end if;
      continue;
    end if;

    -- (b) O despacho que confirma a chegada condicional do mesmo fornecedor (dita antes, no mesmo dia útil ou no
    -- anterior): a previsão é a data da chegada, a fonte é o fornecedor e o trecho são os dois.
    if s.tipo = 'despacho' then
      select x.* into v_ch from public.material_sinais x
       where x.fornecedor_id is not distinct from s.fornecedor_id and x.tipo = 'chegada' and x.condicional
         and x.estado in ('registrado', 'esperando') and x.data_ate is not null
         and x.ocorreu_em < s.ocorreu_em and s.dia <= public.agenda_somar_du(x.dia, 1)
       order by x.ocorreu_em desc, x.id desc
       limit 1;
      if found then
        v_junto := v_ch.id;
        v_de := v_ch.data_de;
        v_ate := v_ch.data_ate;
        v_trecho := left(format('"%s" + "%s"', v_ch.trecho, s.trecho), 300);
        update public.material_sinais set data_de = v_de, data_ate = v_ate,
               os_material_id = coalesce(s.os_material_id, v_ch.os_material_id),
               service_order_id = coalesce(s.service_order_id, v_ch.service_order_id),
               casou_por = case when s.os_material_id is null then v_ch.casou_por else s.casou_por end
         where id = s.id
        returning * into s;
        update public.material_sinais
           set estado = 'descartado', faria = jsonb_build_object('acao', 'junto', 'sinal', s.id),
               motivo = format('confirmada pelo despacho (%s): a previsão vai com ele', v_quando)
         where id = v_ch.id;
      end if;
    end if;
    v_fonte := case when s.direcao = 'enviada' and v_junto is null then 'dono' else 'fornecedor' end;

    -- (c) A compra: a escolhida (a única viva do fornecedor, ou a que o modelo apontou), como está agora. Ligada = comprada
    -- ou a caminho com ESSE fornecedor (da linha, da OC dela ou da nota dela) e a mensagem não é de antes da compra.
    v_tem_l := false;
    if s.os_material_id is not null then
      select m.* into l from public.os_material m where m.id = s.os_material_id for update;
      v_tem_l := found;
    end if;
    v_ligada := v_tem_l and l.situacao in ('comprado', 'a_caminho') and l.comprado_em is not null
      and s.dia >= l.comprado_em - 1
      and (l.fornecedor_id is not distinct from s.fornecedor_id
           or exists (select 1 from public.purchase_order_items poi
                        join public.purchase_orders po on po.id = poi.purchase_order_id
                       where poi.id = l.purchase_order_item_id and po.supplier_id = s.fornecedor_id)
           or exists (select 1 from public.material_remessas r where r.id = l.remessa_id and r.fornecedor_id = s.fornecedor_id));
    if v_tem_l then
      v_cli := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                           left join public.clients cl on cl.id = so.client_id where so.id = l.service_order_id), 'serviço');
      v_curto := public._agenda_linha_curta(l.descricao);
      v_numero := (select so.service_order_number from public.service_orders so where so.id = l.service_order_id);
      v_os_ids := array[l.service_order_id];
    else
      v_os_ids := array(select distinct (e ->> 'os')::uuid from jsonb_array_elements(s.candidatos) e
                         where e ->> 'os' ~ '^[0-9a-f-]{36}$' order by 1);
    end if;
    v_dia_txt := case when v_ate is null then null
                      when v_de is not null and v_de <> v_ate then format('entre %s e %s', public._dia_curto(v_de), public._dia_curto(v_ate))
                      else public._dia_curto(v_ate) end;

    -- (d) O que fazer.
    if s.tipo = 'perguntou_chegou' then
      -- "Recebeu o compressor?": vira o "chegou?" ao dono, uma vez, sem duplicar o da vigia (Fase 2) nem o do fornecedor.
      if not v_tem_l then
        v_acao := 'nada'; v_motivo := 'não sei de qual compra ele pergunta';
      elsif l.situacao in ('na_mao', 'dispensado') then
        v_acao := 'nada'; v_motivo := 'o material já está na mão';
      elsif not v_ligada then
        v_acao := 'nada'; v_motivo := 'a compra não está ligada a ele';
      elsif exists (select 1 from public.agenda_perguntas q
                     where q.tipo = 'chegou' and q.estado = 'aberta' and q.modo = coalesce(v_mmodo, q.modo)
                       and (q.os_material_id = l.id or q.chave like 'chegou:' || l.id || ':%'
                            or q.chave like 'chegou:fornecedor:' || l.id || ':%')) then
        v_acao := 'nada'; v_motivo := 'já perguntei se chegou';
      else
        v_acao := 'chegou';
        v_txt := format('%s perguntou se chegou o "%s" do %s (%s). Chegou?', v_forn, v_curto, v_cli, public._dia_curto(s.dia));
      end if;
    elsif v_ate is null then
      if s.direcao = 'enviada' then
        v_acao := 'nada'; v_motivo := coalesce(s.motivo, 'dito pela HBR, sem data');
      else
        v_acao := 'perguntar';
      end if;
    elsif v_ligada and s.casou_por = 'unico' then
      v_acao := 'previsao';
    elsif s.direcao = 'enviada' then
      v_acao := 'nada'; v_motivo := 'dito pela HBR, sem compra ligada: não pergunto';
    else
      v_acao := 'perguntar';
    end if;

    if v_acao = 'perguntar' then
      if v_tem_l then
        v_txt := format('%s escreveu "%s" (%s). É do %s ("%s")?', v_forn, public._agenda_corta(s.trecho, 80), v_quando, v_cli, v_curto)
                 || case when v_dia_txt is null then ' Em quantos dias costuma chegar dele?'
                         else format(' Se for, chega por volta de %s.', v_dia_txt) end;
      elsif jsonb_array_length(s.candidatos) > 1 then
        select coalesce(jsonb_agg(jsonb_build_object('n', z.k, 'os', z.e -> 'os', 'os_material_id', z.e -> 'os_material_id',
                                                     'texto', z.e ->> 'rotulo') order by z.k), '[]'::jsonb)
          into v_opc
          from (select e, row_number() over (order by (e ->> 'n')::int) as k
                  from jsonb_array_elements(s.candidatos) e) z
         where z.k <= c.nfe_opcoes_max;
        v_k := jsonb_array_length(v_opc) + 1;
        v_opc := v_opc || jsonb_build_array(jsonb_build_object('n', v_k, 'os', null, 'texto', 'nenhuma delas'));
        v_lista := array(select format('%s) %s', e ->> 'n', e ->> 'texto') from jsonb_array_elements(v_opc) e
                          order by (e ->> 'n')::int);
        v_txt := format('%s escreveu "%s" (%s). É de qual compra? %s.', v_forn, public._agenda_corta(s.trecho, 80), v_quando,
                        array_to_string(v_lista, '; '))
                 || case when v_dia_txt is null then '' else format(' Se for de uma delas, chega por volta de %s.', v_dia_txt) end
                 || ' Me diga o número ou o nome.';
      else
        v_txt := format('%s escreveu "%s" (%s). É material de qual serviço?', v_forn, public._agenda_corta(s.trecho, 80), v_quando)
                 || case when v_dia_txt is null then '' else format(' Se for, chega por volta de %s.', v_dia_txt) end
                 || ' Me diga o nome.';
      end if;
    elsif v_acao = 'previsao' then
      v_txt := format('%s: "%s" chega %s — %s. *desfaz %s* volta como estava.', public._agenda_rotulo_da_os(l.service_order_id),
                      v_curto, v_dia_txt,
                      case when v_fonte = 'dono' then format('você escreveu para %s "%s"', v_forn, public._agenda_corta(s.trecho, 80))
                           else format('%s escreveu "%s"', v_forn, public._agenda_corta(s.trecho, 80)) end,
                      coalesce(v_numero, 'isso'));
    end if;
    v_faria := jsonb_build_object('acao', v_acao, 'data_de', v_de, 'data_ate', v_ate, 'fonte', v_fonte, 'texto', v_txt,
                                  'trecho', v_trecho, 'os_material_id', case when v_tem_l then l.id end, 'junto', v_junto);

    if v_acao = 'nada' then
      update public.material_sinais set estado = 'descartado', faria = v_faria, motivo = left(v_motivo, 200) where id = s.id;
      n_desc := n_desc + 1;
      continue;
    end if;

    if not v_exec then
      -- Em teste: só o que faria (o dono não vê nada; a precisão é medida pelo fato).
      update public.material_sinais
         set faria = v_faria,
             motivo = left(case v_acao
                             when 'previsao' then format('em teste: anotaria %s para "%s" do %s', v_dia_txt, v_curto, v_cli)
                             when 'chegou' then format('em teste: perguntaria se chegou o "%s" do %s', v_curto, v_cli)
                             else 'em teste: perguntaria ao dono de qual compra é' end, 200)
       where id = s.id;
      n_teste := n_teste + 1;
      continue;
    end if;

    if v_acao = 'previsao' then
      -- A compra já ligada e única do fornecedor: a previsão nova, sozinha, com *desfaz* (a ação material, origem fornecedor).
      if l.situacao = 'a_caminho' and l.previsao_ate is not distinct from v_ate
         and l.previsao_de is not distinct from (case when v_de <> v_ate then v_de end)
         and l.previsao_fonte in ('dono', 'fornecedor', 'nfe') then
        update public.material_sinais set estado = 'aplicado', faria = v_faria, motivo = 'a previsão já era essa' where id = s.id;
        continue;
      end if;
      v_antes := to_jsonb(l) - 'historico';
      update public.os_material m
         set situacao = 'a_caminho', fonte = v_fonte, previsao_de = case when v_de <> v_ate then v_de end, previsao_ate = v_ate,
             previsao_fonte = v_fonte, trecho = left(v_trecho, 300),
             evidencia = m.evidencia || jsonb_build_object('whatsapp_message_id', s.whatsapp_message_id, 'sinal_id', s.id,
                                                           'trecho', left(v_trecho, 300), 'vinculo_por', 'compra_ligada'),
             historico = public._os_material_historico(m.historico, jsonb_build_object(
                           'em', p_hoje, 'de', m.situacao, 'para', 'a_caminho', 'por', 'fornecedor',
                           'nota', format('chega %s, pela mensagem do %s', v_dia_txt, v_forn), 'trecho', left(v_trecho, 300))),
             atualizado_em = now(), atualizado_por = null
       where m.id = l.id
      returning to_jsonb(m) - 'historico' into v_depois;
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                       desfazivel_ate)
      values (p_agora, p_hoje, true, 'fornecedor', 'material', l.service_order_id, array[l.service_order_id],
              jsonb_build_object('linhas', jsonb_build_array(v_antes), 'remessa_id', l.remessa_id),
              jsonb_build_object('linhas', jsonb_build_array(v_depois), 'remessa_id', l.remessa_id, 'sinal_id', s.id),
              public._agenda_corta(v_txt, 400), p_agora + c.desfazer_validade)
      returning id into v_acao_id;
      update public.material_sinais set estado = 'aplicado', faria = v_faria, acao_id = v_acao_id, motivo = null where id = s.id;
      n_prev := n_prev + 1;
      continue;
    end if;

    -- As perguntas vão no modo do material (ligado só com modo_material ligado); desligado = não pergunto.
    if v_mmodo is null then
      update public.material_sinais set estado = 'descartado', faria = v_faria,
             motivo = 'o material está desligado: não pergunto' where id = s.id;
      n_desc := n_desc + 1;
      continue;
    end if;
    v_perda := (select min(public._agenda_inicio_previsto(o, p_hoje)) from unnest(v_os_ids) o);
    if v_acao = 'chegou' then
      perform public._agenda_material_perguntar('chegou', format('chegou:fornecedor:%s:%s', l.id, s.dia), l.service_order_id,
                                                array[l.service_order_id], l.id, v_perda, v_txt, '[]'::jsonb, p_agora);
      select q.id into v_perg from public.agenda_perguntas q
       where q.chave = format('chegou:fornecedor:%s:%s', l.id, s.dia) and q.modo = v_mmodo order by q.criada_em desc limit 1;
      n_cheg := n_cheg + 1;
    else
      perform public._agenda_material_perguntar('previsao_fornecedor', 'sinal:' || s.id,
                                                case when v_tem_l then l.service_order_id end, v_os_ids,
                                                case when v_tem_l then l.id end, v_perda, v_txt, v_opc, p_agora);
      select q.id into v_perg from public.agenda_perguntas q
       where q.chave = 'sinal:' || s.id and q.modo = v_mmodo order by q.criada_em desc limit 1;
      n_perg := n_perg + 1;
    end if;
    update public.material_sinais set estado = 'perguntado', faria = v_faria, pergunta_id = v_perg, motivo = null where id = s.id;
  end loop;

  -- (2) O julgamento pelo fato (a precisão do detector): os sinais de até 30 dias com a compra e a data, ainda sem julgamento.
  -- certo = a linha chegou na faixa ± detector_tolerancia_du, ou o dono disse uma previsão nessa faixa; errado = chegou fora
  -- dela, ou o dono ligou a mensagem a outra compra; sem como saber = 15 dias úteis depois da data, sem fato.
  for s in select x.* from public.material_sinais x
            where x.julgamento is null and x.os_material_id is not null and x.data_ate is not null and x.dia >= p_hoje - 30
              and x.faria ->> 'acao' in ('previsao', 'perguntar')
            order by x.ocorreu_em, x.id
            for update loop
    select m.* into l from public.os_material m where m.id = s.os_material_id;
    continue when not found;
    v_lo := case when c.detector_tolerancia_du = 0 then coalesce(s.data_de, s.data_ate)
                 else public.agenda_somar_du(coalesce(s.data_de, s.data_ate), -c.detector_tolerancia_du) end;
    v_hi := case when c.detector_tolerancia_du = 0 then s.data_ate
                 else public.agenda_somar_du(s.data_ate, c.detector_tolerancia_du) end;
    v_j := case
      when s.faria ->> 'os_material_id' is not null and s.faria ->> 'os_material_id' <> s.os_material_id::text then 'errado'
      when l.situacao = 'na_mao' and l.chegou_em is not null then
        case when l.chegou_em between v_lo and v_hi then 'certo' else 'errado' end
      when l.previsao_fonte = 'dono' and l.atualizado_por is not null and l.previsao_ate between v_lo and v_hi then 'certo'
      when p_hoje > public.agenda_somar_du(s.data_ate, 15) then 'sem_como_saber'
    end;
    if v_j is not null then
      update public.material_sinais set julgamento = v_j, julgado_em = p_agora, julgado_por = 'fato' where id = s.id;
      n_jul := n_jul + 1;
    end if;
  end loop;

  return jsonb_build_object('aplicados', n_prev, 'perguntados', n_perg, 'chegou', n_cheg, 'esperando', n_esp,
                            'descartados', n_desc, 'em_teste', n_teste, 'julgados', n_jul, 'vencidos', n_venc, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_material_sinais(date, timestamptz) is
  'Agenda de Produção (Fase 4, P4), passo do material "sinais" (o P5 o chama em agenda_material_vigiar): cada sinal sem decisão, na ordem dita — a chegada condicional ("chega amanhã se retirarem hoje") espera o despacho do fornecedor até o dia útil seguinte e vai junto com ele (d8: previsão = a data da chegada, fonte fornecedor, os dois trechos), vencida = descartada; a previsão da compra JÁ LIGADA e única do fornecedor (casou_por unico; comprada ou a caminho com ele, da OC dele ou da nota dele; a mensagem não é de antes da compra) é aplicada sozinha em ligado — os_material a caminho, previsão e fonte fornecedor (a HBR sem condição = dono), evidência vinculo_por compra_ligada, ação material origem fornecedor com antes/depois {linhas, remessa_id} e o *desfaz* —; o resto (sem data, mais de uma compra, linha em falta, modelo, nenhum) vira a pergunta previsao_fornecedor (sinal:<id>); o "Recebeu o compressor?" vira o "chegou?" (chegou:fornecedor:<linha>:<dia>) uma vez, sem duplicar o da vigia; o que a HBR disse sem compra ligada não pergunta. As perguntas vão no modo do material. Em sombra só o que faria (faria, motivo "em teste: …"), e o teste de mais de 7 dias sai da fila. Depois, o julgamento pelo fato (certo, errado, sem_como_saber) dos sinais de até 30 dias. {aplicados, perguntados, chegou, esperando, descartados, em_teste, julgados, vencidos, modo}; desligado = {pulado}.';

-- ── 5. A precisão do detector (o portão para ligar) ─────────────────────────────────────────────────────

create or replace function public.agenda_detector_precisao(p_de date default null, p_ate date default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c       public.agenda_config;
  v_ate   date := coalesce(p_ate, public._hoje_brt());
  v_de    date := coalesce(p_de, coalesce(p_ate, public._hoje_brt()) - 13);
  r       record;
  v_prec  numeric;
  v_pronto boolean;
  v_txt   text;
begin
  if (select auth.uid()) is not null and not public.is_admin_or_financial((select auth.uid())) then
    raise exception 'A precisão do detector é com o administrador ou o financeiro.' using errcode = '42501';
  end if;
  c := public._agenda_cfg();
  select count(*) as sinais, count(distinct s.whatsapp_message_id) as mensagens,
         count(*) filter (where s.julgamento in ('certo', 'errado')) as julgados,
         count(*) filter (where s.julgamento = 'certo') as certos,
         count(*) filter (where s.julgamento = 'errado') as errados,
         count(*) filter (where s.julgamento = 'sem_como_saber') as sem_como_saber
    into r
    from public.material_sinais s
   where s.dia between v_de and v_ate and coalesce(s.faria ->> 'acao', '') <> 'junto';
  v_prec := case when r.julgados > 0 then round(r.certos::numeric / r.julgados, 2) end;
  v_pronto := r.julgados >= c.detector_minimo_julgados and coalesce(v_prec, 0) >= c.detector_precisao_minima;
  v_txt := case when r.mensagens = 0
                then format('De %s a %s não li mensagem de fornecedor com prazo.', public._dia_curto(v_de), public._dia_curto(v_ate))
                else format('De %s a %s li %s de fornecedor com prazo: %s.', public._dia_curto(v_de), public._dia_curto(v_ate),
                            public._agenda_plural(r.mensagens::int, 'mensagem', 'mensagens'),
                            case when r.julgados = 0 then 'nenhuma deu para conferir ainda'
                                 else format('acertei %s de %s que deu para conferir', r.certos, r.julgados) end) end
           || case when v_pronto then ' Já dá para ligar, com o seu OK.'
                   else format(' Continua em teste: preciso de pelo menos %s conferidas, com %s%% de acerto.',
                               c.detector_minimo_julgados, round(c.detector_precisao_minima * 100)) end;
  return jsonb_build_object('de', v_de, 'ate', v_ate, 'sinais', r.sinais, 'mensagens', r.mensagens, 'julgados', r.julgados,
                            'certos', r.certos, 'errados', r.errados, 'sem_como_saber', r.sem_como_saber, 'precisao', v_prec,
                            'pronto_para_ligar', v_pronto, 'minimo_julgados', c.detector_minimo_julgados,
                            'precisao_minima', c.detector_precisao_minima, 'texto', v_txt);
end;
$function$;

comment on function public.agenda_detector_precisao(date, date) is
  'Agenda de Produção (Fase 4, P4): a precisão do detector de p_de a p_ate (sem as datas: os últimos 14 dias) — {sinais, mensagens, julgados (certo + errado), certos, errados, sem_como_saber, precisao, pronto_para_ligar = julgados >= detector_minimo_julgados e precisao >= detector_precisao_minima, texto "De … a … li 3 mensagens de fornecedor com prazo: acertei 2 de 2 que deu para conferir. Continua em teste: preciso de pelo menos 5 conferidas, com 70% de acerto."}. O sinal que foi junto com o despacho não conta duas vezes. Com menos casos que o mínimo, continua em teste. Invoker; só administrador ou financeiro (o técnico: 42501).';

-- ── 6. O desfazer da mudança do material (a previsão pela mensagem do fornecedor; a chegada pela nota) ───

create or replace function public._agenda_desfazer_material(p_acao uuid, p_autor uuid, p_via text, p_hoje date,
                                                            p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_a      public.agenda_acoes%rowtype;
  v_nome   text;
  e        jsonb;
  v_cur    jsonb;
  v_r      public.os_material%rowtype;
  v_nota   boolean;
  v_rem    uuid;
  v_nomes  text[] := '{}';
  v_ids    uuid[] := '{}';
  v_estado text;
  v_txt    text;
  v_acao   uuid;
begin
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found or v_a.tipo <> 'material' then
    raise exception 'Não encontrei essa mudança do material.' using errcode = 'P0002';
  end if;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_a.service_order_id), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste do material: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá mais para desfazer o material do %s: passou o prazo. Se está errado, me diga como está.', v_nome));
  end if;
  if jsonb_typeof(v_a.depois -> 'linhas') is distinct from 'array' or jsonb_array_length(v_a.depois -> 'linhas') = 0
     or jsonb_typeof(v_a.antes -> 'linhas') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança não tem o material de antes para voltar.');
  end if;
  -- Ninguém mexeu nas linhas depois da mudança (o dono, a nota, a sincronização): a linha toda, menos o histórico, é a
  -- do "depois". (A hora da última mudança sozinha não basta: na mesma transação now() se repete.)
  for e in select x from jsonb_array_elements(v_a.depois -> 'linhas') x loop
    v_cur := null;
    select to_jsonb(m) - 'historico' into v_cur from public.os_material m where m.id = (e ->> 'id')::uuid for update;
    if v_cur is distinct from e then
      return jsonb_build_object('ok', false, 'texto', 'A linha mudou depois (você ou a nota): não desfiz.');
    end if;
  end loop;

  -- A linha volta inteira como estava, o original da previsão junto (o gatilho do original deixa passar só com esta chave
  -- local). A chegada pela nota que o dono desfez: a nota deixa de valer para a linha (sem isso a próxima sincronização a
  -- poria na mão de novo).
  v_nota := v_a.origem = 'nota';
  v_rem := nullif(v_a.antes ->> 'remessa_id', '')::uuid;
  perform set_config('agenda.desfazer_material', 'on', true);
  for e in select x from jsonb_array_elements(v_a.antes -> 'linhas') x loop
    v_r := jsonb_populate_record(null::public.os_material, e);
    continue when not exists (select 1 from public.os_material m where m.id = v_r.id);
    update public.os_material m
       set descricao = v_r.descricao, quantidade_necessaria = v_r.quantidade_necessaria,
           quantidade_na_mao = v_r.quantidade_na_mao, critico = v_r.critico, situacao = v_r.situacao, fonte = v_r.fonte,
           fornecedor_id = v_r.fornecedor_id, fornecedor_nome = v_r.fornecedor_nome, compra_prevista_em = v_r.compra_prevista_em,
           comprado_em = v_r.comprado_em, comprado_fonte = v_r.comprado_fonte, previsao_de = v_r.previsao_de,
           previsao_ate = v_r.previsao_ate, previsao_original = v_r.previsao_original, previsao_fonte = v_r.previsao_fonte,
           previsao_original_fonte = v_r.previsao_original_fonte, previsao_original_em = v_r.previsao_original_em,
           chegou_em = v_r.chegou_em, trecho = v_r.trecho, evidencia = v_r.evidencia, conferido_em = v_r.conferido_em,
           remessa_id = case when v_nota then null else v_r.remessa_id end,
           historico = public._os_material_historico(m.historico, jsonb_build_object(
                         'em', p_hoje, 'de', m.situacao, 'para', v_r.situacao, 'por', 'dono', 'autor', p_autor,
                         'nota', case when v_nota then 'desfeito: a nota deixa de valer para esta linha'
                                      else 'desfeito: volta como estava' end)),
           atualizado_em = now(), atualizado_por = p_autor
     where m.id = v_r.id;
    v_ids := v_ids || v_r.id;
    v_nomes := v_nomes || public._agenda_linha_curta(v_r.descricao);
    v_estado := case v_r.situacao
                  when 'falta' then 'a comprar'
                  when 'na_mao' then 'na mão'
                  when 'dispensado' then 'dispensado'
                  when 'comprado' then case when v_r.previsao_ate is null then 'comprado, sem previsão'
                                            else 'comprado, chega ' || public._dia_curto(v_r.previsao_ate) end
                  else case when v_r.previsao_ate is null then 'a caminho, sem previsão'
                            else 'a caminho, chega ' || public._dia_curto(v_r.previsao_ate) end end;
  end loop;
  perform set_config('agenda.desfazer_material', 'off', true);

  v_txt := case when cardinality(v_nomes) = 1
                then format('Desfeito: "%s" do %s voltou a "%s", como estava.', v_nomes[1], v_nome, v_estado)
                else format('Desfeito: %s do %s voltaram como estavam.',
                            public._agenda_lista(array(select format('"%s"', x) from unnest(v_nomes) x), 3), v_nome) end
           || case when v_nota and v_rem is not null
                   then format(' A %s não conta mais para o %s.', public._agenda_remessa_nota(v_rem), v_nome) else '' end;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, autor,
                                   desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer',
          v_a.service_order_id, v_a.os_ids, jsonb_build_object('acao', v_a.id, 'tipo', 'material'),
          jsonb_build_object('linhas', to_jsonb(v_ids)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;
  -- A mensagem que deu origem: o dono disse que estava errado (conta na precisão do detector).
  update public.material_sinais s set julgamento = 'errado', julgado_em = p_agora, julgado_por = 'dono' where s.acao_id = v_a.id;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'linhas', to_jsonb(v_ids));
end;
$function$;

comment on function public._agenda_desfazer_material(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 4, P4): desfaz a ação material da agenda (a previsão pela mensagem do fornecedor, origem fornecedor; a chegada pela nota importada, origem nota) — dentro de desfazivel_ate, só se NENHUMA linha mudou depois (a linha toda, menos o histórico, igual ao "depois"; senão "A linha mudou depois (você ou a nota): não desfiz."): cada linha de antes.linhas volta inteira, o original da previsão junto (a chave local agenda.desfazer_material abre o gatilho do original); na da nota, a nota deixa de valer para a linha (remessa_id nulo: a sincronização não a põe na mão de novo). Ação desfazer ("Desfeito: "Compressor 12V de…" do Flávio voltou a "a caminho, sem previsão", como estava.") e a original desfeita; o sinal que a originou fica julgado errado pelo dono. Sem grant: só agenda_desfazer chama.';


-- ── 7. O gatilho do original da previsão: a exceção do desfazer ─────────────────────────────────────────
-- Corpo de 20261027100000 copiado; a mudança está marcada "-- FASE 4: … -- FASE 4: fim".

create or replace function public._os_material_previsao_original()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_entrada jsonb;
  v_ultima  jsonb;
begin
  -- FASE 4: o desfazer de uma mudança do material (_agenda_desfazer_material) volta a linha inteira como estava, o
  -- original da previsão junto (ele foi criado pela própria mudança que está sendo desfeita). Só com a chave local
  -- agenda.desfazer_material, que só aquela função liga (e desliga logo depois), como a agenda.porta da Fase 2.
  if tg_op = 'UPDATE' and coalesce(current_setting('agenda.desfazer_material', true), '') = 'on' then
    return new;
  end if;
  -- FASE 4: fim
  if tg_op = 'UPDATE' and old.previsao_original is not null then
    if old.situacao = 'falta' and new.situacao in ('comprado', 'a_caminho') then
      -- Compra nova depois de a linha voltar a faltar: o original de antes vai ao histórico (antes da entrada que o
      -- caminho da escrita acrescentou nesta mesma mudança, que continua sendo a última) e vale o que chegar agora.
      v_entrada := jsonb_build_object('em', public._agenda_hoje(), 'de', 'original', 'valor', old.previsao_original,
                                      'fonte', old.previsao_original_fonte);
      if new.historico -> -1 is distinct from old.historico -> -1 and jsonb_array_length(new.historico) > 0 then
        v_ultima := new.historico -> -1;
        new.historico := public._os_material_historico(
                           public._os_material_historico(new.historico - (-1), v_entrada), v_ultima);
      else
        new.historico := public._os_material_historico(new.historico, v_entrada);
      end if;
      new.previsao_original := null;
      new.previsao_original_fonte := null;
      new.previsao_original_em := null;
    else
      -- O original não muda.
      new.previsao_original := old.previsao_original;
      new.previsao_original_fonte := old.previsao_original_fonte;
      new.previsao_original_em := old.previsao_original_em;
    end if;
  end if;

  if new.previsao_original is null and new.previsao_ate is not null then
    new.previsao_original := new.previsao_ate;
    -- A previsão sem fonte é recusada pelo CHECK previsao_tem_fonte da linha: o original não pode ser ele a recusar.
    new.previsao_original_fonte := coalesce(new.previsao_fonte,
                                            case when new.fonte in ('dono', 'fornecedor', 'nfe', 'pix') then new.fonte end, 'oc');
    new.previsao_original_em := public._agenda_hoje();
  elsif new.previsao_original is not null and new.previsao_original_fonte is null then
    -- O original escrito pelo caminho das Fases 1–3, que não conhece a fonte: a da previsão; sem ela, a do fato
    -- informado; sem as duas, 'oc' (a única previsão que o sistema grava sozinho).
    new.previsao_original_fonte := coalesce(new.previsao_fonte,
                                            case when new.fonte in ('dono', 'fornecedor', 'nfe', 'pix') then new.fonte end, 'oc');
    new.previsao_original_em := coalesce(new.previsao_original_em, public._agenda_hoje());
  end if;
  return new;
end;
$function$;

comment on function public._os_material_previsao_original() is
  'Agenda de Produção (Fase 4): gatilho BEFORE INSERT/UPDATE de os_material — a 1ª previsão (previsao_ate) vira previsao_original, com a fonte e o dia (_agenda_hoje), qualquer que seja o caminho; depois disso o original não muda, salvo na compra nova (a linha estava em falta e passa a comprado/a caminho): o de antes vai ao histórico ({em, de: original, valor, fonte}) e vale o próximo. P4: o desfazer do material (_agenda_desfazer_material, com a chave local agenda.desfazer_material) volta a linha inteira, o original junto.';


-- ── 8. A vigia (Fase 2): o chegou? do fornecedor ────────────────────────────────────────────────────────
-- Corpos de 20261025100300 (as únicas que as definem) copiados; as mudanças estão marcadas "-- FASE 4:".

create or replace function public._agenda_vigia_limpeza(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_obs   int := 0;
  v_exp   int := 0;
  v_venc  int := 0;
  v_res   int := 0;
  r       record;
  v_pront jsonb;
  v_cache jsonb := '{}'::jsonb;
  v_item  jsonb;
  v_mot   text;
  v_dono_padrao boolean;
begin
  for r in select p.id, p.versao_base, p.expira_em, p.modo from public.agenda_propostas p
            where p.estado = 'aberta' order by p.criada_em, p.id loop
    if r.modo = 'ligado' and r.versao_base < cf.versao_plano then
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'a agenda mudou' where id = r.id;
      v_obs := v_obs + 1;
    elsif r.expira_em < p_agora then
      update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou da validade' where id = r.id;
      v_exp := v_exp + 1;
    else
      continue;
    end if;
    delete from public.agenda_alocacoes where proposta_id = r.id and estado = 'proposta';
  end loop;

  update public.agenda_perguntas q set estado = 'vencida'
   where q.estado = 'aberta' and q.expira_em is not null and q.expira_em < p_agora;
  get diagnostics v_venc = row_count;

  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  for r in select q.* from public.agenda_perguntas q where q.estado = 'aberta' order by q.criada_em, q.id loop
    v_mot := null;
    if r.tipo = 'conferencia' then
      if not exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia and a.resultado is null) then
        v_mot := case
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia) then 'o dia saiu do plano'
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia
                              and a.resultado is distinct from 'sem_registro') then 'o dia ficou sem registro'
          else 'o dia já está anotado' end;
      end if;
    elsif r.tipo = 'padrao_do_dono' then
      if v_dono_padrao then v_mot := 'você disse os dias em que fica em campo'; end if;
    elsif r.service_order_id is not null then
      v_pront := v_cache -> r.service_order_id::text;
      if v_pront is null then
        v_pront := public.os_prontidao(r.service_order_id, p_hoje);
        v_cache := v_cache || jsonb_build_object(r.service_order_id::text, v_pront);
      end if;
      if v_pront ->> 'estado' in ('concluida', 'fora_da_carteira') then
        v_mot := 'a OS saiu da carteira';
      elsif r.tipo = 'chegou' and split_part(r.chave, ':', 2) = 'fixado' then
        -- a véspera do dia marcado pelo dono (chegou:fixado:<os>:<dia>)
        if r.dia < p_hoje then
          v_mot := 'o dia passou';
        elsif not exists (select 1 from public.agenda_alocacoes a
                           where a.service_order_id = r.service_order_id and a.dia = r.dia and a.estado in ('publicada', 'fixada')
                             and a.tipo <> 'reserva' and a.fixado_por = 'dono') then
          v_mot := 'o dia saiu do plano';
        else
          v_item := public._agenda_classe_da_os(v_pront, public.agenda_meios_da_os(r.service_order_id, p_hoje), p_hoje, false, false);
          if public._agenda_aviso_do_material(v_pront,
               coalesce(v_item ->> 'condicao_tipo',
                        case when v_item ->> 'motivo' = 'material' and v_pront #>> '{material,estado}' = 'sem_previsao' then 'material' end),
               v_item ->> 'texto', r.dia) is null then
            v_mot := 'o material ficou garantido para o dia';
          end if;
        end if;
      -- FASE 4: o chegou? que a pergunta do fornecedor abriu ("Recebeu o compressor?", chegou:fornecedor:<linha>:<dia>):
      -- resolve quando a linha chega ou sai da OS; senão fica até vencer (material_pergunta_validade). Sem este bloco a
      -- regra de baixo leria "fornecedor" como o item e a resolveria no mesmo tique ("a peça saiu da OS").
      elsif r.tipo = 'chegou' and split_part(r.chave, ':', 2) = 'fornecedor' then
        select e into v_item from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
         where e ->> 'id' = split_part(r.chave, ':', 3) limit 1;
        if v_item is null then
          v_mot := 'a peça saiu da OS';
        elsif v_item ->> 'situacao' = 'na_mao' then
          v_mot := format('"%s" chegou', v_item ->> 'curto');
        end if;
      -- FASE 4: fim
      elsif r.tipo = 'chegou' then
        select e into v_item from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
         where coalesce(e ->> 'id', e ->> 'linha') = split_part(r.chave, ':', 2) limit 1;
        if v_item is null then
          v_mot := 'a peça saiu da OS';
        elsif v_item ->> 'situacao' = 'na_mao' then
          v_mot := format('"%s" chegou', v_item ->> 'curto');
        elsif not coalesce((v_item ->> 'atrasado')::boolean, false) or (v_item ->> 'data') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'a previsão mudou';
        end if;
      elsif r.tipo = 'parada' then
        if v_pront ->> 'estado' <> 'parada' then v_mot := 'a OS voltou a andar'; end if;
      elsif r.tipo = 'estouro' then
        if v_pront ->> 'status' <> 'in_progress' then
          v_mot := 'a OS não está mais em andamento';
        elsif (public.agenda_meios_da_os(r.service_order_id, p_hoje) ->> 'total') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'o combinado mudou';
        end if;
      elsif r.tipo = 'duracao' then
        if exists (select 1 from public.os_planejamento pl
                    where pl.service_order_id = r.service_order_id and pl.dias is not null
                      and pl.estimativa_fonte in ('dono', 'aceita')) then
          v_mot := 'você disse os dias';
        end if;
      elsif r.tipo = 'material_conferir' then
        if (v_pront #>> '{material,estado}') is distinct from 'nao_conferido' then v_mot := 'o material foi conferido'; end if;
      end if;
    end if;
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200) where id = r.id;
      v_res := v_res + 1;
    end if;
  end loop;
  return jsonb_build_object('obsoletas', v_obs, 'expiradas', v_exp, 'vencidas', v_venc, 'resolvidas', v_res);
end;
$function$;

comment on function public._agenda_vigia_limpeza(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 1: propostas abertas de outra versão do plano (obsoleta, só ligado) ou vencidas (expirada), com as alocações de proposta; perguntas vencidas; perguntas cuja condição sumiu (resolvida, com o fato: chegou, voltou a andar, saiu da carteira, o dia está anotado…). Fase 4 (P4): o chegou? do fornecedor (chegou:fornecedor:<linha>:<dia>) só se resolve quando a linha chega ou sai da OS.';

create or replace function public._agenda_vigia_chegou(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  r     record;
  v_p   jsonb;
  e     jsonb;
  v_n   int := 0;
  v_nf  int := 0;
  v_ref text;
  v_cl  jsonb;
  v_av  text;
begin
  for r in select k.service_order_id as os from public.os_carteira(p_hoje) k order by k.numero collate "C", k.service_order_id loop
    v_p := public.os_prontidao(r.os, p_hoje);
    for e in select x from jsonb_array_elements(coalesce(v_p #> '{material,itens}', '[]'::jsonb)) with ordinality t(x, o)
              where coalesce((x ->> 'critico')::boolean, true) and coalesce((x ->> 'atrasado')::boolean, false) order by o loop
      v_ref := coalesce(e ->> 'id', e ->> 'linha');
      continue when v_ref is null or e ->> 'data' is null;
      -- FASE 4: o chegou? que a pergunta do fornecedor abriu ("Recebeu o compressor?") ainda está aberto para esta linha,
      -- no modo da vigia: não pergunto de novo (d14, sem duplicar).
      continue when exists (select 1 from public.agenda_perguntas q
                             where q.tipo = 'chegou' and q.estado = 'aberta' and q.modo = cf.modo_vigia
                               and q.chave like 'chegou:fornecedor:' || v_ref || ':%');
      -- FASE 4: fim
      if public._agenda_vigia_perguntar('chegou', format('chegou:%s:%s', v_ref, e ->> 'data'), r.os, (e ->> 'id')::uuid, null,
           (v_p #>> '{plano,proximo_dia}')::date,
           format('%s: "%s" tinha previsão para %s. Chegou?', public._agenda_rotulo_da_os(r.os), e ->> 'curto',
                  public._dia_curto((e ->> 'data')::date)),
           cf.modo_vigia, p_agora) then
        v_n := v_n + 1;
      end if;
    end loop;
  end loop;
  -- O dia que o dono marcou antes de o material estar garantido (o caso da OS-00104): nada sai da agenda (a decisão é
  -- dele), mas na véspera — o dia marcado é hoje ou o próximo dia útil — a pergunta "chegou?", uma vez por OS e dia.
  for r in select a.service_order_id as os, a.dia
             from public.agenda_alocacoes a
            where a.estado in ('publicada', 'fixada') and a.fixado_por = 'dono' and a.tipo <> 'reserva' and a.resultado is null
              and a.dia between p_hoje and public.agenda_somar_du(p_hoje, 1)
            group by 1, 2 order by 2, 1 loop
    v_p := public.os_prontidao(r.os, p_hoje);
    v_cl := public._agenda_classe_da_os(v_p, public.agenda_meios_da_os(r.os, p_hoje), p_hoje, false, false);
    v_av := public._agenda_aviso_do_material(v_p,
              coalesce(v_cl ->> 'condicao_tipo',
                       case when v_cl ->> 'motivo' = 'material' and v_p #>> '{material,estado}' = 'sem_previsao' then 'material' end),
              v_cl ->> 'texto', r.dia);
    continue when v_av is null;
    if public._agenda_vigia_perguntar('chegou', format('chegou:fixado:%s:%s', r.os, r.dia), r.os, null, r.dia, r.dia,
         format('%s: você marcou %s, mas %s. Chegou?', public._agenda_rotulo_da_os(r.os), public._dia_curto(r.dia), v_av),
         cf.modo_vigia, p_agora) then
      v_nf := v_nf + 1;
    end if;
  end loop;
  return jsonb_build_object('criadas', v_n + v_nf, 'fixadas', v_nf);
end;
$function$;

comment on function public._agenda_vigia_chegou(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 9: item crítico atrasado (a previsão passou sem chegada) → pergunta chegou:<item>:<previsão>, uma vez por previsão. E o dia que o dono marcou antes de o material estar garantido (_agenda_aviso_do_material): na véspera (o dia marcado é hoje ou o próximo dia útil) → pergunta chegou:fixado:<os>:<dia> ("Flávio (OS-00104): você marcou ter 06/10, mas … Chegou?"), uma vez; nada sai da agenda. A limpeza resolve quando o dia passa, sai do plano ou o material fica garantido. Fase 4 (P4): com o chegou? do fornecedor aberto para a mesma linha (chegou:fornecedor:<linha>:<dia>), não pergunta de novo.';


-- ── 8b. O desfazer da agenda: a ação material ───────────────────────────────────────────────────────────
-- Corpo de 20261026100300 (a mais nova; os blocos -- FASE 3: ficam) copiado; a mudança está marcada "-- FASE 4:".

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
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

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
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois).';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A leitura das mensagens, o registro do sinal, o passo e as auxiliares: só service_role (o acompanhar-conversas e o
-- agenda_material_vigiar do P5). Nunca anon, nunca authenticated.
revoke all on function
  public._agenda_chave_telefone(text), public._agenda_fones_que_nao_sao_fornecedor(), public._agenda_compras_vivas(date),
  public.agenda_mensagens_de_fornecedor(date, timestamptz),
  public.material_sinal_registrar(uuid, uuid, text, text, boolean, text, jsonb, uuid, text, numeric, date, timestamptz),
  public._agenda_material_sinais(date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public._agenda_chave_telefone(text), public._agenda_fones_que_nao_sao_fornecedor(), public._agenda_compras_vivas(date),
  public.agenda_mensagens_de_fornecedor(date, timestamptz),
  public.material_sinal_registrar(uuid, uuid, text, text, boolean, text, jsonb, uuid, text, numeric, date, timestamptz),
  public._agenda_material_sinais(date, timestamptz)
  to service_role;

-- A precisão do detector: leitura do administrador ou do financeiro (confere dentro; o técnico recebe 42501).
revoke all on function public.agenda_detector_precisao(date, date) from public, anon;
grant execute on function public.agenda_detector_precisao(date, date) to authenticated, service_role;

-- O desfazer do material: sem grant (só agenda_desfazer, security definer, chama).
revoke all on function public._agenda_desfazer_material(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar):
revoke all on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) to service_role;
revoke all on function public._agenda_vigia_limpeza(date, timestamptz), public._agenda_vigia_chegou(date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._os_material_previsao_original() from public, anon, authenticated;
