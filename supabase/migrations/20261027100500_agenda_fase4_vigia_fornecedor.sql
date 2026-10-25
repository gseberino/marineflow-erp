-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P5: a vigia do material e a mensagem ao
-- fornecedor — agenda_material_vigiar (a rodada do material, chamada pelo task-automations a cada 15 min, depois do
-- material e antes da rotina e da vigia), a pergunta "a entrega continua para qua 04/11?" ao fornecedor nos terços de um
-- prazo longo (mais de prazo_longo_du dias úteis), as perguntas de cadastro (fornecedor_cadastro:<fornecedor>,
-- fornecedores_prazo) e a agenda_saude com o bloco do material.
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§3.1, §3.2, §5.5, §6.2, §6.3, §6.4, d4, d10, d12, d15). Decisões do
-- dono 23/10 ("pede ao fornecedor que confirme o prazo (modelo)": automática; dinheiro e compra são críticos). Depende de
-- 20261027100000 (agenda_fornecedor_mensagens, os modos e os parâmetros do fornecedor), 100100 (o prazo do fornecedor),
-- 100300 (os passos notas e pix, a pergunta do material) e 100400 (o passo sinais, os telefones que nunca são de
-- fornecedor, as compras vivas).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (16 funções novas, 1 recriada, 2 gatilhos novos na fila; nenhuma tabela, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f4p5/montar-migration.mjs: as partes escritas à mão
-- e o corpo de agenda_saude copiado da migration MAIS NOVA que a define (20261026100300), com cada troca "-- FASE 4:"
-- conferida (uma vez só; fora dos blocos, só as 2 linhas do fim do "ok" e do fim do resultado mudam — a vírgula).
--
-- POR QUE: a compra de prazo longo (o painel do Nelson na AliExpress: 13 dias úteis) some até o dia da chegada; ninguém
-- confere no meio. A decisão de 23/10 manda o gestor perguntar ao fornecedor, sozinho, com a mensagem-modelo. É mensagem a
-- TERCEIRO: a lição de setembro (os técnicos receberam alerta à meia-noite) vale inteira — três travas, cada uma com teste.
--
-- O QUE MUDA:
--   1. agenda_material_vigiar (nova; só service_role): a rodada do material. Antes de tudo, em qualquer modo, a fila velha
--      do fornecedor (o que não saiu na janela, ou ficou na fila com modo_fornecedor fora de ligado, vira falha). Os três
--      modos desligados = {rodou: false}. Os passos, cada um no seu bloco (o que falha vai a app_error_logs, context agenda,
--      action material:<passo>, e os outros rodam): notas e pix (modo_material; P3), sinais (modo_detector; P4), terços
--      (modo_fornecedor), cadastros (modo_material) e sincronizar (modo_material ligado: as OS que a nota ou a mensagem
--      mudou nesta rodada). Uma linha em agenda_vigia_rodadas (rotina material). {rodou, modos, contagens, erros, falhas}.
--   2. _agenda_material_tercos: a linha crítica da carteira comprada ou a caminho, com o dia da compra e a previsão, de mais
--      de prazo_longo_du dias úteis entre os dois, ainda sem chegar: no 1º e no 2º terço do prazo (em dias úteis) a
--      pergunta ao fornecedor, uma vez por linha e terço, só o terço de agora (o que passou sem sair não sai atrasado).
--   3. A mensagem ao fornecedor: _agenda_fornecedor_registrar (o registro em agenda_fornecedor_mensagens, no modo de agora;
--      em sombra a chave termina em :sombra) e _agenda_fornecedor_enfileirar (a 1ª trava), na ordem: modo (sombra = fica
--      registrada); opt-out (ou o cadastro desativado); sem conversa DELE nos últimos fornecedor_conversa_dias; domingo;
--      sábado sem fornecedor_sabado; fora de [fornecedor_janela_inicio, fornecedor_janela_fim) de Brasília; o teto (por
--      fornecedor no dia e na semana ISO, e o total do dia); o telefone (o do fornecedor, nunca o do dono, da equipe nem
--      de cliente com OS; wa_test_mode = o número de teste). Senão whatsapp_send_queue com source agenda-fornecedor.
--   4. A 2ª trava: o gatilho trg_agenda_fila_do_fornecedor em whatsapp_send_queue, SÓ para source agenda-fornecedor —
--      recusa a linha sem a mensagem registrada em ligado, com outra chave, outro texto ou outro telefone, com alguma
--      tentativa fora da janela, no fim de semana ou acima do teto; a nova tentativa fora da janela vira falha; a linha não
--      muda de texto, telefone, origem nem chave depois de entrar. (A 3ª trava é o worker: _shared/agenda/janela-da-fila.ts.)
--   5. _agenda_material_cadastros: as perguntas fornecedor_cadastro:<fornecedor> (o cadastro repetido de classe diferente;
--      o fornecedor sem cidade nem UF) dos fornecedores que importam (_agenda_fornecedores_principais: os de mais contas a
--      pagar de material em 365 dias e os de compra viva) e a pergunta única fornecedores_prazo (com 3 ou mais principais
--      sem a modalidade dita), com as chaves do P1 (o *grava* do prazo do fornecedor as resolve); a limpeza delas.
--   6. agenda_saude recriada (corpo de 20261026100300) com o bloco material: os modos, a rodada, as remessas, as perguntas,
--      o detector, a mensagem ao fornecedor, a cobertura e a espera. Os 0 obrigatórios (entram no ok): linha ligada a nota
--      ou Pix sem a palavra do dono, previsão sem o original, e na mensagem ao fornecedor: nada na fila em sombra, nada fora
--      da janela, nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
--
-- O QUE NÃO MUDA: a fila das outras origens (o gatilho novo só olha source agenda-fornecedor; os de produção ficam iguais);
-- o worker manda as outras origens como sempre (provado em whatsapp-queue-worker/enviar_test.ts); a agenda_carona (o P3 já a
-- recriou com os tipos da Fase 4); a vigia e a rotina; o financeiro inteiro.
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, compra, OC ou cotação. A mensagem ao fornecedor nunca leva valor,
-- pagamento, boleto, Pix, número de OS ou orçamento, link nem o nome do cliente (_agenda_fornecedor_texto_proibido: o
-- registro recusa; a saúde conta).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase4_vigia_fornecedor.sql):
--   · "Conversou com a HBR nos últimos 90 dias" = uma mensagem DELE (recebida) com o mesmo telefone (os 8 últimos dígitos):
--     a mensagem que a própria agenda mandou não conta como conversa (senão ela se manteria "em conversa" sozinha).
--   · O telefone do fornecedor que é do dono, da equipe ou de cliente com OS (NOVO-agenda-34) nunca recebe: recusada com
--     sem_telefone, na 1ª trava e na 2ª. O cadastro desativado conta como opt-out.
--   · Só o terço de AGORA sai (o dia do terço ≤ hoje < o dia do terço seguinte; o 3º é a previsão): ligada a agenda no meio
--     de um prazo, ela não manda o 1º e o 2º no mesmo dia. Nem sai a que chegaria no dia da previsão ou depois.
--   · O horário de envio (_agenda_fornecedor_quando) pula feriado; a janela (a regra única das três travas) não olha
--     feriado: quem marca a hora nunca a põe num feriado.
--   · O texto ao fornecedor: "{ref}" do pedido é "feito em 15/10" (a spec dizia "pedido de 15/10": "Sobre o pedido de X
--     (pedido de 15/10)" repetiria a palavra); o nome da empresa é o de app_settings.company_name (produção: "HBR Marine
--     Solutions"); sem ele, "HBR Marine".
--   · A ação que conta no fechamento é tipo fornecedor, origem vigia (o "o que mudou sozinho" já lê a vigia), sem *desfaz*;
--     "Perguntei à AliExpress se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11." (a linha da OS no
--     formato das ações do P4); em sombra, executada = false com "Em teste: eu perguntaria à …".
--   · A nova tentativa recusada pela trava volta à hora de antes (a linha falha sem ficar marcada fora da janela) e a saúde
--     conta como fora da janela só o que está na fila, saindo ou saiu — o que falhou não saiu.
--   · A agenda_saude não lê a precisão do detector para quem não é administrador nem financeiro (ela lançaria 42501).
--
-- CORREÇÃO C1 DA REVISÃO DA FASE 4 (25/10/2026; a migration não estava aplicada, foi editada aqui): o passo da fila
-- (_agenda_material_fila) também falha a pergunta que ficou velha antes de sair — a linha de material sumiu, chegou,
-- saiu de comprado/a caminho, a OS saiu da carteira ou o texto de agora (_agenda_fornecedor_texto) não é o da fila — e a
-- mensagem fica recusada/desatualizada (motivo novo na lista fechada da 20261027100000). x5: a pergunta marcada para qui
-- 08:00 sairia depois que o painel chegou.
--
-- ORDEM DE LIGAR: depois de 20261027100000..100400; ANTES do deploy do task-automations (que chama agenda_material_vigiar —
-- sem ela, com os modos desligados, o passo nem chama a função) e do whatsapp-queue-worker (a 3ª trava). Com os três modos
-- desligados (a linha nasce assim), nada é gravado e nada sai.
--
-- PROVA: supabase/tests/agenda_fase4_vigia_fornecedor.sql (V0–V6, T1–T5). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261027100000..100400):
--   npx supabase db query --linked -f supabase/migrations/20261027100500_agenda_fase4_vigia_fornecedor.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027100500', 'agenda_fase4_vigia_fornecedor');"
--
-- IDEMPOTENTE: create or replace function, drop trigger if exists + create, revoke/grant e comment.


-- ── 1. A janela do fornecedor (a regra única das três travas) ───────────────────────────────────────────

-- Dia em que a mensagem ao fornecedor pode sair: segunda a sexta que são dias úteis (sem feriado); o sábado só com
-- fornecedor_sabado (e sem feriado); nunca o domingo.
create or replace function public._agenda_fornecedor_dia_de_janela(p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_dia is null then false
    when extract(isodow from p_dia) = 7 then false
    when extract(isodow from p_dia) = 6 then (public._agenda_cfg()).fornecedor_sabado and public.agenda_feriado(p_dia) is null
    else public.agenda_dia_util(p_dia) end;
$function$;

comment on function public._agenda_fornecedor_dia_de_janela(date) is
  'Agenda de Produção (Fase 4, P5): o dia pode ter mensagem ao fornecedor? Segunda a sexta úteis (agenda_dia_util: sem feriado); sábado só com agenda_config.fornecedor_sabado e sem feriado; domingo nunca.';

-- A janela de UMA tentativa de envio ao fornecedor — a regra única: o _agenda_fornecedor_enfileirar (a 1ª tentativa e
-- quantas cabem), o gatilho da fila (o INSERT e a nova tentativa), o passo "fila" e a saúde leem daqui; o worker confere o
-- mesmo na hora de mandar (whatsapp-queue-worker, _shared/agenda/janela-da-fila.ts). null = pode sair; senão o motivo:
-- domingo; fim_de_semana (sábado sem fornecedor_sabado); janela (outro dia que não o da hora marcada, ou fora de
-- [fornecedor_janela_inicio, fornecedor_janela_fim) de Brasília). O feriado não é olhado aqui: quem marca a hora
-- (_agenda_fornecedor_quando) nunca a põe num feriado.
create or replace function public._agenda_fornecedor_fora_da_janela(p_marcada timestamptz, p_quando timestamptz)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_q timestamp := p_quando at time zone 'America/Sao_Paulo';
begin
  if p_quando is null or p_marcada is null then
    return 'janela';
  end if;
  if extract(isodow from v_q) = 7 then
    return 'domingo';
  end if;
  if extract(isodow from v_q) = 6 and not cf.fornecedor_sabado then
    return 'fim_de_semana';
  end if;
  if v_q::date <> (p_marcada at time zone 'America/Sao_Paulo')::date then
    return 'janela';
  end if;
  if v_q::time >= cf.fornecedor_janela_inicio and v_q::time < cf.fornecedor_janela_fim then
    return null;
  end if;
  return 'janela';
end;
$function$;

comment on function public._agenda_fornecedor_fora_da_janela(timestamptz, timestamptz) is
  'Agenda de Produção (Fase 4, P5): a janela de uma tentativa de envio ao fornecedor, a regra única do banco (o worker tem a mesma em _shared/agenda/janela-da-fila.ts) — null = pode sair; ''domingo''; ''fim_de_semana'' (sábado sem fornecedor_sabado); ''janela'' (outro dia que não o da hora marcada, em Brasília, ou fora de [fornecedor_janela_inicio, fornecedor_janela_fim)).';

-- Quando a mensagem sai: agora, se agora está dentro da janela de um dia de janela; senão o início da janela — hoje, se
-- hoje é dia de janela e ela ainda não começou; senão o do próximo dia de janela.
create or replace function public._agenda_fornecedor_quando(p_agora timestamptz)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_l timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_d date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_i int := 0;
begin
  if p_agora is null then
    return null;
  end if;
  if public._agenda_fornecedor_dia_de_janela(v_d) and v_l::time < cf.fornecedor_janela_fim then
    if v_l::time >= cf.fornecedor_janela_inicio then
      return p_agora;
    end if;
    return (v_d + cf.fornecedor_janela_inicio) at time zone 'America/Sao_Paulo';
  end if;
  loop
    v_d := v_d + 1;
    v_i := v_i + 1;
    exit when public._agenda_fornecedor_dia_de_janela(v_d);
    if v_i > 31 then
      raise exception '_agenda_fornecedor_quando: nenhum dia de janela em 31 dias a partir de %', v_l::date using errcode = '54000';
    end if;
  end loop;
  return (v_d + cf.fornecedor_janela_inicio) at time zone 'America/Sao_Paulo';
end;
$function$;

comment on function public._agenda_fornecedor_quando(timestamptz) is
  'Agenda de Produção (Fase 4, P5): a hora de envio de uma mensagem ao fornecedor — p_agora, se está dentro da janela (fornecedor_janela_inicio a fornecedor_janela_fim, Brasília) de um dia de janela (_agenda_fornecedor_dia_de_janela: úteis; sábado só com fornecedor_sabado); senão o início da janela de hoje (se ainda não começou) ou do próximo dia de janela.';

-- ── 2. O fornecedor da mensagem: o telefone, a conversa, o teto ─────────────────────────────────────────

-- O telefone para onde a mensagem iria: 55 + DDD + número (o cadastro com 10–11 dígitos ganha o 55; com 12–13 tem de
-- começar por 55). Nunca o do dono, da equipe, de quem recebe diária nem de cliente com OS (NOVO-agenda-34: o dono e a
-- Souper/Rodrigo estão cadastrados como fornecedor): esses = null.
create or replace function public._agenda_fornecedor_telefone(p_fornecedor uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when length(x.d) in (10, 11) then '55' || x.d
              when length(x.d) in (12, 13) and x.d like '55%' then x.d end
    from (select regexp_replace(coalesce(s.phone, ''), '\D', '', 'g') as d from public.suppliers s where s.id = p_fornecedor) x
   where public._agenda_chave_telefone(x.d) is not null
     and not exists (select 1 from public._agenda_fones_que_nao_sao_fornecedor() k where k = public._agenda_chave_telefone(x.d));
$function$;

comment on function public._agenda_fornecedor_telefone(uuid) is
  'Agenda de Produção (Fase 4, P5): o telefone do fornecedor para a mensagem — 55 + DDD + número (10–11 dígitos no cadastro ganham o 55; 12–13 têm de começar por 55); null sem telefone válido ou quando os 8 últimos dígitos são do dono, da equipe, de payee ou de cliente com OS (_agenda_fones_que_nao_sao_fornecedor).';

-- O fornecedor conversou com a HBR? Uma mensagem DELE (recebida, o mesmo telefone pelos 8 últimos dígitos) nos
-- fornecedor_conversa_dias antes de p_ate. 0 = sem essa exigência. A mensagem que a agenda mandou não conta.
create or replace function public._agenda_fornecedor_conversou(p_fornecedor uuid, p_ate timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select (public._agenda_cfg()).fornecedor_conversa_dias = 0
      or exists (select 1
                   from public.suppliers s
                   join public.whatsapp_messages w
                     on public._agenda_chave_telefone(w.phone_normalized) = public._agenda_chave_telefone(s.phone)
                  where s.id = p_fornecedor and w.direction = 'inbound'
                    and w.occurred_at <= p_ate
                    and w.occurred_at > p_ate - make_interval(days => (public._agenda_cfg()).fornecedor_conversa_dias));
$function$;

comment on function public._agenda_fornecedor_conversou(uuid, timestamptz) is
  'Agenda de Produção (Fase 4, P5): o fornecedor mandou alguma mensagem (recebida, o mesmo telefone pelos 8 últimos dígitos) nos agenda_config.fornecedor_conversa_dias antes de p_ate? 0 dias = sempre true. O que a HBR (ou a agenda) mandou não conta como conversa.';

-- Quantas mensagens ao fornecedor (ou a todos: p_fornecedor null) ENTRARAM na fila com o dia de envio (Brasília) em
-- [p_de, p_ate]: a contagem única do teto. A que entrou conta em qualquer estado (saindo, enviada ou falhada); a que nunca
-- entrou (sombra, recusada antes) não conta. p_exceto = a mensagem que está entrando.
create or replace function public._agenda_fornecedor_no_periodo(p_fornecedor uuid, p_de date, p_ate date, p_exceto uuid)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  select count(*)::int
    from public.agenda_fornecedor_mensagens m
   where m.modo = 'ligado' and m.id is distinct from p_exceto
     and (p_fornecedor is null or m.fornecedor_id = p_fornecedor)
     and (m.enviar_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and (m.fila_id is not null
          or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = m.id));
$function$;

comment on function public._agenda_fornecedor_no_periodo(uuid, date, date, uuid) is
  'Agenda de Produção (Fase 4, P5): o teto contado num lugar só — as mensagens ao fornecedor (ou a todos, com p_fornecedor null) em ligado que ENTRARAM na fila (fila_id, ou a linha source agenda-fornecedor dela), com o dia de envio de Brasília em [p_de, p_ate], sem p_exceto. O _agenda_fornecedor_enfileirar e o gatilho da fila contam igual.';

-- ── 3. O texto ao fornecedor (só a mensagem-modelo) e o que ele nunca pode levar ────────────────────────

-- O que a mensagem ao fornecedor nunca leva: null = nada; senão o motivo — valor ("R$"), pagamento ("pag…", "boleto",
-- "pix"), o número de OS ou orçamento ("OS-", "ORÇ-"), link ("http", "www.") ou o 1º nome do cliente da OS (3 letras ou
-- mais, palavra inteira).
create or replace function public._agenda_fornecedor_texto_proibido(p_texto text, p_os uuid)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v     text := public._agenda_normal(p_texto);
  v_cli text;
begin
  if p_texto ~ 'R\$' then
    return 'valor';
  end if;
  if v ~ '\m(pag|boleto|pix)' then
    return 'pagamento';
  end if;
  if p_texto ~* '\m(OS|ORÇ|ORC)-' then
    return 'os';
  end if;
  if p_texto ~* '(https?:|www\.)' then
    return 'link';
  end if;
  select public._agenda_normal(public._agenda_nome_curto(cl.name)) into v_cli
    from public.service_orders so join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  if length(coalesce(v_cli, '')) >= 3 and v ~ ('\m' || v_cli || '\M') then
    return 'cliente';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_fornecedor_texto_proibido(text, uuid) is
  'Agenda de Produção (Fase 4, P5): o que a mensagem ao fornecedor nunca leva — null = nada; ''valor'' (R$), ''pagamento'' (pag…, boleto, pix), ''os'' (OS-, ORÇ-), ''link'' (http, www.) ou ''cliente'' (o 1º nome do cliente da OS, palavra inteira). O registro recusa; a saúde conta (com_valor_ou_cliente = 0).';

-- A mensagem-modelo (spec §6.4), pronta: "Olá, Carla! Aqui é o Gustavo, da HBR Marine Solutions. Sobre o pedido de
-- Painel Touch (feito em 15/10): a entrega continua prevista para qua 04/11? Obrigado!". O contato é o 1º nome de
-- suppliers.contact_name (sem ele, "Olá!"); quem fala é o dono (o payee sócio; sem ele, "Aqui é da …"); a empresa é
-- app_settings.company_name; o item, a linha curta sem as reticências; a referência, a nota ligada ("nota 51038") ou o dia
-- da compra ("feito em 15/10"). Sem valor, sem cliente, sem OS, sem link.
create or replace function public._agenda_fornecedor_texto(p_linha uuid)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  m      public.os_material%rowtype;
  v_forn uuid;
  v_cont text;
  v_dono text;
  v_emp  text;
  v_item text;
  v_num  text;
  v_ref  text;
begin
  select * into m from public.os_material where id = p_linha;
  if not found then
    return null;
  end if;
  v_forn := coalesce(m.fornecedor_id,
                     (select po.supplier_id from public.purchase_order_items poi
                        join public.purchase_orders po on po.id = poi.purchase_order_id
                       where poi.id = m.purchase_order_item_id),
                     (select r.fornecedor_id from public.material_remessas r where r.id = m.remessa_id));
  v_cont := (select public._agenda_nome_curto(nullif(btrim(s.contact_name), '')) from public.suppliers s where s.id = v_forn);
  v_dono := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = public._agenda_dono(null));
  v_emp := coalesce((select nullif(btrim(s.value), '') from public.app_settings s where s.key = 'company_name'), 'HBR Marine');
  -- a linha curta sem as reticências e sem a palavra de ligação que sobrou no corte ("Painel Touch de…" → "Painel Touch")
  v_item := regexp_replace(regexp_replace(coalesce(public._agenda_linha_curta(m.descricao), 'material'), '…$', ''),
                           '\s+(de|da|do|das|dos|e|com|para|em|no|na)$', '', 'i');
  v_num := (select nullif(btrim(r.numero), '') from public.material_remessas r where r.id = m.remessa_id);
  v_ref := case when v_num is not null then 'nota ' || v_num
                when m.comprado_em is not null then 'feito em ' || to_char(m.comprado_em, 'DD/MM') end;
  return format('Olá%s! %s Sobre o pedido de %s%s: %s Obrigado!',
                coalesce(', ' || v_cont, ''),
                case when v_dono is not null then format('Aqui é o %s, da %s.', v_dono, v_emp)
                     else format('Aqui é da %s.', v_emp) end,
                v_item, coalesce(' (' || v_ref || ')', ''),
                case when m.previsao_ate is not null
                     then format('a entrega continua prevista para %s?', public._dia_curto(m.previsao_ate))
                     else 'qual a previsão de entrega?' end);
end;
$function$;

comment on function public._agenda_fornecedor_texto(uuid) is
  'Agenda de Produção (Fase 4, P5): a mensagem-modelo ao fornecedor de uma linha de material — "Olá, Carla! Aqui é o Gustavo, da HBR Marine Solutions. Sobre o pedido de Painel Touch (feito em 15/10): a entrega continua prevista para qua 04/11? Obrigado!" (sem previsão: "qual a previsão de entrega?"; com a nota ligada: "(nota 51038)"). Contato = 1º nome de suppliers.contact_name; quem fala = o dono (_agenda_dono); a empresa = app_settings.company_name. Nunca valor, cliente, OS nem link.';

-- ── 4. O registro e a 1ª trava (o enfileirar) ───────────────────────────────────────────────────────────

-- Uma mensagem registrada: decide se vai à fila (e marca enfileirada), fica registrada (sombra) ou é recusada (o motivo).
-- A ordem é a da spec (§5.5). A janela vale para TODA tentativa: o max_attempts é cortado para a última (+5 min cada) não
-- passar do fim; o gatilho da fila (abaixo) confere tudo de novo no INSERT.
create or replace function public._agenda_fornecedor_enfileirar(p_msg uuid)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       public.agenda_fornecedor_mensagens%rowtype;
  s       public.suppliers%rowtype;
  v_existe boolean;
  v_dia   date;
  v_seg   date;
  v_fone  text;
  v_teste boolean;
  v_tent  int;
  v_fila  uuid;
  v_motivo text;
  v_det   text;
begin
  -- o teto é contado e a linha entra numa vez só, mesmo com dois tiques do motor ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext('agenda_fornecedor_fila'));
  select * into m from public.agenda_fornecedor_mensagens where id = p_msg for update;
  if not found then
    raise exception 'Não encontrei essa mensagem ao fornecedor.' using errcode = 'P0002';
  end if;
  -- já decidida (o tique seguinte não refaz)
  if m.estado <> 'registrada' then
    return jsonb_build_object('estado', m.estado, 'motivo', m.recusa_motivo, 'fila_id', m.fila_id);
  end if;
  -- 1. o modo: sombra (ou a mensagem nasceu em sombra) = só registrada
  if m.modo <> 'ligado' or cf.modo_fornecedor <> 'ligado' then
    return jsonb_build_object('estado', 'registrada', 'motivo', 'modo');
  end if;

  v_dia := (m.enviar_em at time zone 'America/Sao_Paulo')::date;
  select * into s from public.suppliers where id = m.fornecedor_id;
  v_existe := found;
  v_motivo := case
    -- 2. o fornecedor pediu para não receber (ou o dono desativou o cadastro)
    when not v_existe or coalesce(s.opt_out_whatsapp, false) or not coalesce(s.active, true) then 'opt_out'
    -- 3. só a quem conversou com a HBR (uma mensagem DELE) nos últimos fornecedor_conversa_dias
    when not public._agenda_fornecedor_conversou(m.fornecedor_id, m.enviar_em) then 'sem_conversa'
    -- 4. domingo; sábado sem fornecedor_sabado; a janela em Brasília (a regra única)
    else public._agenda_fornecedor_fora_da_janela(m.enviar_em, m.enviar_em)
  end;
  -- 5. o teto, contado como o gatilho da fila conta (_agenda_fornecedor_no_periodo): por fornecedor no dia e na semana ISO,
  -- e o total do dia
  if v_motivo is null then
    v_seg := date_trunc('week', v_dia)::date;
    if public._agenda_fornecedor_no_periodo(m.fornecedor_id, v_dia, v_dia, m.id) >= cf.fornecedor_dia_max
       or public._agenda_fornecedor_no_periodo(m.fornecedor_id, v_seg, v_seg + 6, m.id) >= cf.fornecedor_semana_max
       or public._agenda_fornecedor_no_periodo(null, v_dia, v_dia, m.id) >= cf.fornecedor_total_dia_max then
      v_motivo := 'teto';
    end if;
  end if;
  -- 6. o telefone dele (nunca o do dono, da equipe nem de cliente com OS); 7. o modo de teste do WhatsApp vai para o número
  -- de teste (o mesmo desvio da equipe e de pedir_confirmacao_do_agendamento); ligado sem número de teste = nada sai
  if v_motivo is null then
    v_fone := public._agenda_fornecedor_telefone(m.fornecedor_id);
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
    update public.agenda_fornecedor_mensagens set estado = 'recusada', recusa_motivo = v_motivo where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo);
  end if;

  -- 8. a fila: as tentativas (+5 min cada) que cabem na janela da mensagem (a regra única; a 1ª já cabe)
  v_tent := greatest(1, (select count(*)::int from generate_series(0, 2) k
                          where public._agenda_fornecedor_fora_da_janela(m.enviar_em,
                                                                          m.enviar_em + make_interval(mins => 5 * k)) is null));
  -- a trava da fila (o gatilho) recusa com 23514 o que passaria da janela ou do teto: aqui isso vira a recusa da mensagem
  -- com o motivo, sem desfazer o que veio antes na mesma transação
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for,
                                            max_attempts, dedupe_key)
    values (v_fone, m.texto, 'agenda-fornecedor', m.id, 5, m.enviar_em, v_tent, m.dedupe_key)
    on conflict do nothing
    returning id into v_fila;
  exception when sqlstate '23514' then
    get stacked diagnostics v_det = pg_exception_detail;
    v_motivo := case when v_det in ('teto', 'janela', 'domingo', 'fim_de_semana') then v_det else 'teto' end;
    update public.agenda_fornecedor_mensagens set estado = 'recusada', recusa_motivo = v_motivo where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo, 'pela_fila', true);
  end;
  if v_fila is null then
    -- a mesma chave já estava na fila (o gatilho de idempotência de produção devolve nada): é a mesma mensagem
    select q.id into v_fila from public.whatsapp_send_queue q where q.dedupe_key = m.dedupe_key;
  end if;
  update public.agenda_fornecedor_mensagens set estado = 'enfileirada', fila_id = v_fila where id = m.id;
  return jsonb_build_object('estado', 'enfileirada', 'fila_id', v_fila, 'teste', v_teste, 'tentativas', v_tent);
end;
$function$;

comment on function public._agenda_fornecedor_enfileirar(uuid) is
  'Agenda de Produção (Fase 4, P5): a 1ª trava — a decisão do envio de uma mensagem registrada ao fornecedor, na ordem: modo_fornecedor fora de ligado (ou a mensagem em sombra) = fica registrada; opt-out ou cadastro desativado = recusada/opt_out; sem mensagem DELE nos fornecedor_conversa_dias = sem_conversa; domingo, sábado sem fornecedor_sabado (fim_de_semana) e fora de [fornecedor_janela_inicio, fornecedor_janela_fim) (janela) pela _agenda_fornecedor_fora_da_janela; o teto (fornecedor_dia_max por fornecedor e dia, fornecedor_semana_max por fornecedor e semana ISO, fornecedor_total_dia_max no dia, contados pela _agenda_fornecedor_no_periodo, como o gatilho) = teto; sem telefone válido dele (ou dele = do dono, da equipe, de cliente com OS; ou wa_test_mode sem número de teste) = sem_telefone. Senão whatsapp_send_queue (source agenda-fornecedor, source_ref_id = a mensagem, o texto e a chave dela, priority 5, max_attempts = as tentativas que cabem na janela) e enfileirada; o 23514 da trava da fila vira recusada com o motivo. Idempotente. Sem grant.';

-- Registra a mensagem-modelo no modo de agora (sombra: a chave termina em :sombra) e decide o envio. Desligado = nada.
-- Uma por linha e terço e modo (a chave). O texto que leva valor, pagamento, OS, link ou o cliente é recusado (22023).
create or replace function public._agenda_fornecedor_registrar(p_fornecedor uuid, p_linha uuid, p_os uuid, p_terco integer,
                                                               p_texto text, p_enviar_em timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text;
  v_id    uuid;
  v_r     jsonb;
  v_proib text;
begin
  if cf.modo_fornecedor = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  if p_fornecedor is null or not exists (select 1 from public.suppliers s where s.id = p_fornecedor) then
    raise exception 'A mensagem ao fornecedor veio sem o fornecedor.' using errcode = '22023';
  end if;
  if p_linha is null or p_terco is null or p_terco not in (1, 2) then
    raise exception 'A mensagem ao fornecedor é de uma linha de material e de um terço do prazo (1 ou 2).' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_texto, '')), '') is null or p_enviar_em is null then
    raise exception 'A mensagem ao fornecedor veio sem texto ou sem a hora.' using errcode = '22023';
  end if;
  v_proib := public._agenda_fornecedor_texto_proibido(p_texto, p_os);
  if v_proib is not null then
    raise exception 'A mensagem ao fornecedor não pode levar %: "%".', v_proib, left(p_texto, 120) using errcode = '22023';
  end if;
  v_modo := case when cf.modo_fornecedor = 'ligado' then 'ligado' else 'sombra' end;
  insert into public.agenda_fornecedor_mensagens (fornecedor_id, os_material_id, service_order_id, tipo, terco, modo, texto,
                                                  enviar_em, dedupe_key)
  values (p_fornecedor, p_linha, p_os, 'confirmar_prazo', p_terco, v_modo, left(p_texto, 600), p_enviar_em,
          format('agenda-fornecedor:terco:%s:%s', p_linha, p_terco) || case when v_modo = 'sombra' then ':sombra' else '' end)
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe');
  end if;
  v_r := public._agenda_fornecedor_enfileirar(v_id);
  return v_r || jsonb_build_object('criada', true, 'modo', v_modo, 'id', v_id);
end;
$function$;

comment on function public._agenda_fornecedor_registrar(uuid, uuid, uuid, integer, text, timestamptz) is
  'Agenda de Produção (Fase 4, P5): grava a mensagem-modelo ao fornecedor (tipo confirmar_prazo) no modo de agora — desligado = nada; sombra = estado registrada e a chave agenda-fornecedor:terco:<linha>:<n>:sombra; ligado = a chave sem sufixo, a mesma da fila — e chama _agenda_fornecedor_enfileirar. Uma por linha, terço e modo. O texto com valor, pagamento, OS, link ou o nome do cliente é recusado (22023). Sem grant.';

-- ── 5. A 2ª trava: o gatilho da fila, só para source agenda-fornecedor ──────────────────────────────────

-- Nada com source agenda-fornecedor entra na fila sem a mensagem registrada em ligado (com a chave, o texto e o telefone
-- dela), fora da janela (nenhuma tentativa depois do fim), no fim de semana ou acima do teto; e a linha que entrou não
-- muda de texto, telefone, origem nem chave. É o que garante que um caminho novo (ou um defeito) não manda ao fornecedor
-- uma mensagem livre, à noite ou ao telefone errado.
create or replace function public._agenda_fila_do_fornecedor()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       public.agenda_fornecedor_mensagens%rowtype;
  v_local timestamp;
  v_dia   date;
  v_seg   date;
  v_fora  text;
  v_teste boolean;
  v_num   text;
begin
  if tg_op = 'UPDATE' then
    if old.source is distinct from new.source or old.message is distinct from new.message
       or old.phone_normalized is distinct from new.phone_normalized or old.source_ref_id is distinct from new.source_ref_id
       or old.dedupe_key is distinct from new.dedupe_key then
      raise exception 'A linha da fila do fornecedor não muda de texto, telefone, origem nem chave.' using errcode = '42501';
    end if;
    -- a nova tentativa que o worker marca (+5 min) fora da janela da mensagem (ou com o fornecedor fora de ligado) não
    -- sai: falha, e a hora volta à de antes (a linha não fica marcada fora da janela)
    if new.status = 'pending' and new.scheduled_for is distinct from old.scheduled_for then
      select x.* into m from public.agenda_fornecedor_mensagens x where x.id = new.source_ref_id;
      if not found or cf.modo_fornecedor <> 'ligado'
         or public._agenda_fornecedor_fora_da_janela(m.enviar_em, new.scheduled_for) is not null then
        new.status := 'failed';
        new.failed_reason := 'agenda-fornecedor: a nova tentativa passaria do fim da janela';
        new.scheduled_for := old.scheduled_for;
      end if;
    end if;
    return new;
  end if;
  select x.* into m from public.agenda_fornecedor_mensagens x where x.id = new.source_ref_id;
  if not found or m.modo <> 'ligado' or cf.modo_fornecedor <> 'ligado' then
    raise exception 'A fila do fornecedor só aceita a mensagem registrada pela agenda com modo_fornecedor ligado.' using errcode = '42501';
  end if;
  -- só a que o _agenda_fornecedor_enfileirar está decidindo agora (a recusada nunca entra; a enfileirada não entra de novo)
  if m.estado <> 'registrada' then
    raise exception 'A fila do fornecedor só aceita a mensagem que a agenda acabou de decidir mandar (esta está %).', m.estado
      using errcode = '42501';
  end if;
  if new.dedupe_key is distinct from m.dedupe_key then
    raise exception 'A fila do fornecedor só aceita a mensagem com a chave dela.' using errcode = '42501';
  end if;
  if new.message is distinct from m.texto then
    raise exception 'A fila do fornecedor só aceita o texto registrado (nunca mensagem livre).' using errcode = '42501';
  end if;
  -- o telefone: o do fornecedor da mensagem (nunca o do dono, da equipe nem de cliente com OS) ou, com wa_test_mode, o de
  -- teste
  v_teste := coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_mode'), 'false') in ('true', '"true"');
  v_num := case when v_teste
                then nullif(regexp_replace(coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_number'), ''),
                                           '\D', '', 'g'), '')
                else public._agenda_fornecedor_telefone(m.fornecedor_id) end;
  if v_num is null or new.phone_normalized is distinct from v_num then
    raise exception 'A fila do fornecedor só aceita o telefone do fornecedor da mensagem.' using errcode = '42501';
  end if;
  v_local := new.scheduled_for at time zone 'America/Sao_Paulo';
  -- cada tentativa (+5 min) dentro da janela da mensagem, pela regra única; o motivo vai no detail (quem enfileira recusa
  -- a mensagem com ele)
  select t.f into v_fora
    from (select public._agenda_fornecedor_fora_da_janela(m.enviar_em, new.scheduled_for + make_interval(mins => 5 * k)) as f
            from generate_series(0, greatest(coalesce(new.max_attempts, 3) - 1, 0)) k) t
   where t.f is not null
   limit 1;
  if v_fora is not null then
    raise exception 'Mensagem ao fornecedor fora da janela (% às %, %): %.',
      to_char(cf.fornecedor_janela_inicio, 'HH24:MI'), to_char(cf.fornecedor_janela_fim, 'HH24:MI'),
      case when cf.fornecedor_sabado then 'de segunda a sábado' else 'de segunda a sexta' end, to_char(v_local, 'DD/MM HH24:MI')
      using errcode = '23514', detail = v_fora;
  end if;
  v_dia := v_local::date;
  v_seg := date_trunc('week', v_dia)::date;
  if public._agenda_fornecedor_no_periodo(m.fornecedor_id, v_dia, v_dia, m.id) >= cf.fornecedor_dia_max
     or public._agenda_fornecedor_no_periodo(m.fornecedor_id, v_seg, v_seg + 6, m.id) >= cf.fornecedor_semana_max
     or public._agenda_fornecedor_no_periodo(null, v_dia, v_dia, m.id) >= cf.fornecedor_total_dia_max then
    raise exception 'Teto de mensagens ao fornecedor (% por dia, % por semana, % no dia a todos): não entra mais nenhuma.',
      cf.fornecedor_dia_max, cf.fornecedor_semana_max, cf.fornecedor_total_dia_max using errcode = '23514', detail = 'teto';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_fila_do_fornecedor() is
  'Agenda de Produção (Fase 4, P5): a 2ª trava — gatilho de whatsapp_send_queue só para source agenda-fornecedor. INSERT: recusa (42501) a linha sem a mensagem registrada em ligado (ou com modo_fornecedor fora de ligado), com chave ou texto diferentes dos dela, ou com telefone que não é o do fornecedor dela (_agenda_fornecedor_telefone: nunca o do dono, da equipe nem de cliente com OS; com wa_test_mode, o número de teste); recusa (23514, o motivo no detail) a linha com alguma tentativa fora da janela (_agenda_fornecedor_fora_da_janela: janela, domingo, fim_de_semana) ou acima do teto (_agenda_fornecedor_no_periodo). UPDATE: a linha não muda de texto, telefone, origem, ref nem chave (42501); a nova tentativa pendente que cairia fora da janela (ou com modo_fornecedor fora de ligado) vira failed e volta à hora de antes.';

drop trigger if exists trg_agenda_fila_do_fornecedor on public.whatsapp_send_queue;
create trigger trg_agenda_fila_do_fornecedor before insert on public.whatsapp_send_queue
  for each row when (new.source = 'agenda-fornecedor') execute function public._agenda_fila_do_fornecedor();
drop trigger if exists trg_agenda_fila_do_fornecedor_linha on public.whatsapp_send_queue;
create trigger trg_agenda_fila_do_fornecedor_linha
  before update of scheduled_for, message, phone_normalized, source, source_ref_id, dedupe_key on public.whatsapp_send_queue
  for each row when (old.source = 'agenda-fornecedor' or new.source = 'agenda-fornecedor')
  execute function public._agenda_fila_do_fornecedor();

-- ── 6. Os passos do material: a fila velha, os terços, os cadastros ─────────────────────────────────────

-- A fila velha do fornecedor (roda SEMPRE, em qualquer modo): o que não saiu dentro da janela da mensagem, ou ficou na fila
-- com modo_fornecedor fora de ligado, vira falha e a mensagem fica recusada (janela / modo). A pergunta que ficou velha
-- antes de sair (C1 da revisão: o material chegou, saiu de comprado/a caminho, mudou de previsão ou a OS saiu da carteira)
-- também falha e fica recusada (desatualizada): ninguém pergunta ao fornecedor pela peça que já chegou. O que está marcado
-- para depois e continua valendo fica. Só mexe em linha source agenda-fornecedor.
create or replace function public._agenda_material_fila(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_ids  uuid[];
  v_modo uuid[] := '{}';
  v_velh uuid[] := '{}';
begin
  if cf.modo_fornecedor <> 'ligado' then
    with x as (
      update public.whatsapp_send_queue q
         set status = 'failed', failed_reason = 'agenda-fornecedor: modo_fornecedor saiu de ligado'
       where q.source = 'agenda-fornecedor' and q.status = 'pending'
      returning q.id)
    select coalesce(array_agg(x.id), '{}') into v_modo from x;
    update public.agenda_fornecedor_mensagens m set estado = 'recusada', recusa_motivo = 'modo'
     where m.fila_id = any (v_modo) and m.estado = 'enfileirada';
  end if;
  -- A pergunta desatualizada (x5: marcada para qui 08:00, o painel chegou qua 20:00): a linha de material sumiu, chegou
  -- (chegou_em), saiu de comprado/a caminho, a OS saiu da carteira, ou o texto de agora (_agenda_fornecedor_texto: a
  -- previsão, a nota, o contato) não é mais o que está na fila.
  with x as (
    update public.whatsapp_send_queue q
       set status = 'failed', failed_reason = 'agenda-fornecedor: o material mudou antes de a pergunta sair'
      from public.agenda_fornecedor_mensagens m0
     where q.source = 'agenda-fornecedor' and q.status = 'pending' and m0.id = q.source_ref_id
       and not exists (select 1 from public.os_material l
                        where l.id = m0.os_material_id and l.chegou_em is null and l.situacao in ('comprado', 'a_caminho')
                          and l.service_order_id in (select k.service_order_id from public.os_carteira(p_hoje) k)
                          and public._agenda_fornecedor_texto(l.id) is not distinct from m0.texto)
    returning q.id)
  select coalesce(array_agg(x.id), '{}') into v_velh from x;
  update public.agenda_fornecedor_mensagens m set estado = 'recusada', recusa_motivo = 'desatualizada'
   where m.fila_id = any (v_velh) and m.estado = 'enfileirada';
  with x as (
    update public.whatsapp_send_queue q
       set status = 'failed', failed_reason = 'agenda-fornecedor: não saiu dentro da janela'
     where q.source = 'agenda-fornecedor' and q.status = 'pending' and q.scheduled_for <= p_agora
       and (not exists (select 1 from public.agenda_fornecedor_mensagens x0 where x0.id = q.source_ref_id)
            or exists (select 1 from public.agenda_fornecedor_mensagens x0
                        where x0.id = q.source_ref_id
                          and public._agenda_fornecedor_fora_da_janela(x0.enviar_em, p_agora) is not null))
    returning q.id)
  select coalesce(array_agg(x.id), '{}') into v_ids from x;
  update public.agenda_fornecedor_mensagens m set estado = 'recusada', recusa_motivo = 'janela'
   where m.fila_id = any (v_ids) and m.estado = 'enfileirada';
  return jsonb_build_object('canceladas', cardinality(v_ids) + cardinality(v_modo) + cardinality(v_velh),
                            'pelo_modo', cardinality(v_modo), 'desatualizadas', cardinality(v_velh));
end;
$function$;

comment on function public._agenda_material_fila(date, timestamptz) is
  'Agenda de Produção (Fase 4, P5), passo do material "fila" (roda sempre, até com tudo desligado): a linha source agenda-fornecedor pendente vira failed quando modo_fornecedor saiu de ligado (a mensagem fica recusada/modo), quando a pergunta ficou velha antes de sair (C1 da revisão: a linha de material sumiu, chegou, saiu de comprado/a caminho, a OS saiu da carteira ou _agenda_fornecedor_texto da linha não é mais o texto da fila; recusada/desatualizada) ou quando já devia ter saído e agora está fora da janela dela (_agenda_fornecedor_fora_da_janela; recusada/janela). O que está marcado para depois e continua valendo fica. {canceladas, pelo_modo, desatualizadas}.';

-- Os terços: a pergunta ao fornecedor no meio de um prazo longo.
create or replace function public._agenda_material_tercos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_modo   text := case cf.modo_fornecedor when 'ligado' then 'ligado' when 'sombra' then 'sombra' end;
  r        record;
  v_total  int;
  v_d1     date;
  v_d2     date;
  v_n      int;
  v_quando timestamptz;
  v_qdia   date;
  v_txt    text;
  v_res    jsonb;
  v_acao   text;
  v_item   text;
  v_quem   text;
  n_alvos  int := 0;
  n_reg    int := 0;
  n_fila   int := 0;
  n_recus  int := 0;
  n_ja     int := 0;
  n_semf   int := 0;
  n_bloq   int := 0;
  n_tarde  int := 0;
begin
  if v_modo is null then
    return jsonb_build_object('pulado', true);
  end if;
  v_quando := public._agenda_fornecedor_quando(p_agora);
  v_qdia := (v_quando at time zone 'America/Sao_Paulo')::date;
  for r in
    select m.id, m.service_order_id, m.descricao, m.comprado_em, m.previsao_ate,
           coalesce(m.fornecedor_id, po.supplier_id, rm.fornecedor_id) as forn,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente
      from public.os_carteira(p_hoje) k
      join public.os_material m on m.service_order_id = k.service_order_id
      join public.service_orders so on so.id = m.service_order_id
      left join public.clients cl on cl.id = so.client_id
      left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
      left join public.purchase_orders po on po.id = poi.purchase_order_id
      left join public.material_remessas rm on rm.id = m.remessa_id
     where m.critico and m.situacao in ('comprado', 'a_caminho') and m.comprado_em is not null and m.previsao_ate is not null
       and m.chegou_em is null and p_hoje < m.previsao_ate
       and public.agenda_du_entre(m.comprado_em, m.previsao_ate) > cf.prazo_longo_du
     order by m.previsao_ate, m.id
  loop
    -- os terços do prazo em dias úteis: o 1º no dia útil ceil(total/3) depois da compra, o 2º no ceil(2·total/3); só o de
    -- AGORA (o dia dele ≤ hoje < o dia do seguinte; o 3º é a previsão)
    v_total := public.agenda_du_entre(r.comprado_em, r.previsao_ate);
    v_d1 := public.agenda_somar_du(r.comprado_em, ceil(v_total::numeric / 3)::int);
    v_d2 := public.agenda_somar_du(r.comprado_em, ceil(2 * v_total::numeric / 3)::int);
    v_n := case when p_hoje >= v_d2 then 2 when p_hoje >= v_d1 then 1 end;
    continue when v_n is null;
    n_alvos := n_alvos + 1;
    if r.forn is null then
      n_semf := n_semf + 1;
      continue;
    end if;
    -- a que sairia no dia da previsão (ou depois) não sai: não há mais o que confirmar
    if v_qdia >= r.previsao_ate then
      n_tarde := n_tarde + 1;
      continue;
    end if;
    v_txt := public._agenda_fornecedor_texto(r.id);
    if v_txt is null or public._agenda_fornecedor_texto_proibido(v_txt, r.service_order_id) is not null then
      n_bloq := n_bloq + 1;
      continue;
    end if;
    v_res := public._agenda_fornecedor_registrar(r.forn, r.id, r.service_order_id, v_n, v_txt, v_quando);
    if not coalesce((v_res ->> 'criada')::boolean, false) then
      n_ja := n_ja + 1;
      continue;
    end if;
    n_reg := n_reg + 1;
    -- o que conta no fechamento (tipo fornecedor, origem vigia, sem *desfaz*): só o que entrou na fila (ligado) ou o que a
    -- sombra teria mandado; a recusada não aconteceu (a saúde conta os motivos)
    v_item := coalesce(public._agenda_linha_curta(r.descricao), 'material');
    v_quem := public._agenda_fornecedor_curto(r.forn);
    v_acao := case v_res ->> 'estado'
      when 'enfileirada' then
        case when v_qdia = p_hoje
             then format('Perguntei à %s se a entrega de "%s" do %s continua para %s.', v_quem, v_item, r.cliente,
                         public._dia_curto(r.previsao_ate))
             else format('Vou perguntar à %s, %s, se a entrega de "%s" do %s continua para %s.', v_quem,
                         public._dia_curto(v_qdia), v_item, r.cliente, public._dia_curto(r.previsao_ate)) end
      when 'registrada' then
        format('Em teste: eu perguntaria à %s, %s, se a entrega de "%s" do %s continua para %s.', v_quem,
               public._dia_curto(v_qdia), v_item, r.cliente, public._dia_curto(r.previsao_ate))
    end;
    if v_res ->> 'estado' = 'enfileirada' then
      n_fila := n_fila + 1;
    elsif v_res ->> 'estado' = 'recusada' then
      n_recus := n_recus + 1;
    end if;
    if v_acao is not null then
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
      values (p_agora, p_hoje, v_res ->> 'estado' = 'enfileirada', 'vigia', 'fornecedor', r.service_order_id,
              array[r.service_order_id], '{}'::jsonb,
              jsonb_build_object('mensagem_id', v_res ->> 'id', 'fila_id', v_res ->> 'fila_id', 'terco', v_n,
                                 'os_material_id', r.id, 'fornecedor_id', r.forn),
              public._agenda_corta(v_acao, 400));
    end if;
  end loop;
  return jsonb_build_object('alvos', n_alvos, 'registradas', n_reg, 'enfileiradas', n_fila, 'recusadas', n_recus,
                            'ja_existiam', n_ja, 'sem_fornecedor', n_semf, 'bloqueadas', n_bloq, 'tarde', n_tarde,
                            'modo', v_modo);
end;
$function$;

comment on function public._agenda_material_tercos(date, timestamptz) is
  'Agenda de Produção (Fase 4, P5), passo do material "terços" (modo_fornecedor): a linha crítica da carteira comprada ou a caminho, com comprado_em e previsao_ate, sem chegar, de mais de prazo_longo_du dias úteis (agenda_du_entre) — no terço de AGORA (o 1º no dia útil ceil(total/3) depois da compra, o 2º no ceil(2·total/3), até a previsão) a mensagem-modelo ao fornecedor da linha (o dela, o da OC, o da nota), uma por linha e terço, com a hora de _agenda_fornecedor_quando (nunca no dia da previsão ou depois), pelo _agenda_fornecedor_registrar (as travas). A que entrou na fila (ou a da sombra) vira a ação tipo fornecedor, origem vigia, sem *desfaz*: "Perguntei à AliExpress se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11." / "Em teste: eu perguntaria à …". {alvos, registradas, enfileiradas, recusadas, ja_existiam, sem_fornecedor, bloqueadas, tarde, modo}; desligado = {pulado}.';

-- Os fornecedores que importam: os de mais contas a pagar de material (pix_categorias) em 365 dias, até
-- fornecedores_principais_max, e todos os de compra viva (linha viva da carteira, OC aberta recente, nota a caminho).
-- Ativos. Ordem: mais contas primeiro.
create or replace function public._agenda_fornecedores_principais(p_hoje date)
 returns table (fornecedor_id uuid, contas integer, vivo boolean)
 language sql
 stable
 set search_path to 'public'
as $function$
  with c as (select x.* from public._agenda_cfg() x),
  pag as (
    select pa.supplier_id as f, count(*)::int as n
      from public.payables pa, c
     where pa.supplier_id is not null and pa.issue_date > p_hoje - 365 and pa.issue_date <= p_hoje
       and coalesce(pa.status, '') <> 'cancelled'
       and public._agenda_categoria_de_material(pa.expense_category, c.pix_categorias)  -- sem maiúscula nem acento (C2, R6)
     group by 1
  ),
  top as (
    select pag.f from pag join public.suppliers s on s.id = pag.f
     where coalesce(s.active, true)
     order by pag.n desc, pag.f
     limit (select c.fornecedores_principais_max from c)
  ),
  vivos as (
    select l.fornecedor_id as f from public._agenda_compras_vivas(p_hoje) l
    union
    select po.supplier_id from public.purchase_orders po, c
     where po.status in ('draft', 'sent', 'partial') and po.supplier_id is not null
       and po.created_at >= ((p_hoje - c.oc_viva_dias)::timestamp at time zone 'America/Sao_Paulo')
    union
    select r.fornecedor_id from public.material_remessas r where r.estado = 'a_caminho' and r.fornecedor_id is not null
  )
  select s.id, coalesce(pag.n, 0), exists (select 1 from vivos v where v.f = s.id)
    from public.suppliers s
    left join pag on pag.f = s.id
   where coalesce(s.active, true)
     and (exists (select 1 from top t where t.f = s.id) or exists (select 1 from vivos v where v.f = s.id))
   order by coalesce(pag.n, 0) desc, s.id;
$function$;

comment on function public._agenda_fornecedores_principais(date) is
  'Agenda de Produção (Fase 4, P5): os fornecedores que importam para a agenda — os de mais contas a pagar nas categorias de material (agenda_config.pix_categorias, sem maiúscula nem acento) nos últimos 365 dias, até fornecedores_principais_max, e todos os de compra viva (_agenda_compras_vivas, OC aberta dos últimos oc_viva_dias, nota a caminho); só ativos. {fornecedor_id, contas, vivo}, mais contas primeiro. As perguntas de cadastro e a pergunta dos principais leem daqui (o foco fornecedores do P6 pode ler também).';

-- As perguntas de cadastro: o cadastro repetido de classe diferente e o fornecedor sem lugar (fornecedor_cadastro:<id>),
-- e a pergunta única dos principais (fornecedores_prazo). As chaves são as do P1: o *grava* do prazo do fornecedor
-- (_agenda_aplicar_fornecedor) as resolve.
create or replace function public._agenda_material_cadastros(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c          public.agenda_config := public._agenda_cfg();
  -- a pergunta dos principais só com pelo menos 3 sem a modalidade dita (spec §3.2): com menos, as perguntas de cada
  -- cadastro bastam
  c_minimo   constant int := 3;
  v_modo     text := public._agenda_material_modo();
  r          record;
  g          record;
  v_p        jsonb;
  v_princ    uuid;
  v_ref      uuid;
  v_txt      text;
  v_lin      record;
  v_rs       record;
  v_sem      int;
  n_perg     int := 0;
  n_res      int := 0;
  n_res2     int := 0;
begin
  if v_modo is null then
    return jsonb_build_object('pulado', true);
  end if;

  -- (1) A limpeza: a pergunta de cadastro que não tem mais dúvida (o dono disse como compra, desativou o cadastro, ou o
  -- repetido saiu) se resolve; a dos principais, quando sobram menos de c_minimo sem a modalidade dita.
  with f as (
    update public.agenda_perguntas q
       set estado = 'resolvida', resolvida_motivo = 'o cadastro já não tem dúvida'
     where q.tipo = 'fornecedor_cadastro' and q.estado = 'aberta'
       and case when q.chave !~ '^fornecedor_cadastro:[0-9a-f-]{36}$' then true
                else not exists (select 1 from public.suppliers s
                                  where s.id = split_part(q.chave, ':', 2)::uuid and coalesce(s.active, true)
                                    and s.modalidade is null)
                     or (public._agenda_prazo_do_fornecedor(split_part(q.chave, ':', 2)::uuid) ->> 'duvida') is null end
    returning q.id)
  select count(*) into n_res from f;
  select count(*) into v_sem
    from public._agenda_fornecedores_principais(p_hoje) pr join public.suppliers s on s.id = pr.fornecedor_id
   where s.modalidade is null;
  if v_sem < c_minimo then
    with f as (
      update public.agenda_perguntas q
         set estado = 'resolvida', resolvida_motivo = 'você já disse como compra dos principais'
       where q.tipo = 'fornecedores_prazo' and q.estado = 'aberta'
      returning q.id)
    select count(*) into n_res2 from f;
  end if;

  -- (2) O cadastro de cada fornecedor que importa, sem a modalidade dita.
  for r in
    select pr.fornecedor_id as id
      from public._agenda_fornecedores_principais(p_hoje) pr join public.suppliers s on s.id = pr.fornecedor_id
     where s.modalidade is null
     order by pr.fornecedor_id
  loop
    v_p := public._agenda_prazo_do_fornecedor(r.id);
    if v_p ->> 'duvida' = 'sem_lugar' then
      -- a 1ª compra viva dele, para o dono saber de quem se fala
      select l.os_material_id, l.service_order_id, l.descricao, coalesce(l.cliente_curto, l.numero) as cliente into v_lin
        from public._agenda_compras_vivas(p_hoje) l
       where l.fornecedor_id = r.id
       order by l.numero collate "C", l.os_material_id
       limit 1;
      v_txt := format('O fornecedor %s está sem %s no cadastro%s. Como você compra desse fornecedor e em quantos dias chega?',
                      public._agenda_fornecedor_curto(r.id),
                      case when (select nullif(btrim(s.city), '') from public.suppliers s where s.id = r.id) is null
                           then 'cidade' else 'o estado (UF)' end,
                      case when v_lin.os_material_id is not null
                           then format(' — é o do "%s" do %s', public._agenda_linha_curta(v_lin.descricao), v_lin.cliente)
                           else '' end);
      if public._agenda_material_perguntar('fornecedor_cadastro', 'fornecedor_cadastro:' || r.id, v_lin.service_order_id,
                                           null, v_lin.os_material_id, null, v_txt, null, p_agora) then
        n_perg := n_perg + 1;
      end if;
    elsif v_p ->> 'duvida' = 'duplicado' then
      -- o grupo do cadastro repetido: a pergunta é sobre cada cadastro que não é o principal (com o principal), ou, sem
      -- principal (empate), sobre cada um com o 1º do grupo
      v_princ := (v_p ->> 'principal_id')::uuid;
      v_ref := coalesce(v_princ, (
        select min(o.id::text)::uuid from public.suppliers o
         where coalesce(o.active, true)
           and public._agenda_nome_de_grupo(coalesce(nullif(btrim(o.trade_name), ''), o.name))
               = (select public._agenda_nome_de_grupo(coalesce(nullif(btrim(x.trade_name), ''), x.name))
                    from public.suppliers x where x.id = r.id)));
      -- o cadastro de referência (o principal, ou o 1º do grupo): o lugar, o CNPJ e os produtos, para o dono reconhecer
      select public._agenda_lugar_texto(o.city, o.state) as lugar, public._agenda_lugar_texto(o.city, null) as cidade,
             length(regexp_replace(coalesce(o.cnpj_cpf, ''), '\D', '', 'g')) = 14 as cnpj14,
             (select count(*)::int from public.products pr where pr.supplier_id = o.id) as produtos
        into v_rs
        from public.suppliers o where o.id = v_ref;
      for g in
        select o.id,
               public._agenda_lugar_texto(o.city, o.state) as lugar,
               public._agenda_lugar_texto(o.city, null) as cidade,
               length(regexp_replace(coalesce(o.cnpj_cpf, ''), '\D', '', 'g')) = 14 as cnpj14,
               (select count(*)::int from public.products pr where pr.supplier_id = o.id) as produtos
          from public.suppliers o
         where coalesce(o.active, true) and o.modalidade is null and o.id <> v_ref
           and public._agenda_nome_de_grupo(coalesce(nullif(btrim(o.trade_name), ''), o.name))
               = (select public._agenda_nome_de_grupo(coalesce(nullif(btrim(x.trade_name), ''), x.name))
                    from public.suppliers x where x.id = r.id)
         order by o.id
      loop
        v_txt := format('O fornecedor %s está cadastrado mais de uma vez: %s (%s) e %s (%s). ',
                        public._agenda_fornecedor_curto(v_ref),
                        coalesce(v_rs.lugar, 'sem cidade'),
                        case when v_rs.cnpj14
                             then 'com CNPJ' || case when v_rs.produtos > 0
                                                     then ' e ' || public._agenda_plural(v_rs.produtos, 'produto', 'produtos') else '' end
                             else 'sem CNPJ' || case when v_rs.produtos > 0
                                                     then ', com ' || public._agenda_plural(v_rs.produtos, 'produto', 'produtos') else '' end end,
                        coalesce(g.lugar, 'sem cidade'),
                        case when g.cnpj14
                             then 'com CNPJ' || case when g.produtos > 0
                                                     then ' e ' || public._agenda_plural(g.produtos, 'produto', 'produtos') else '' end
                             else 'sem CNPJ' || case when g.produtos > 0
                                                     then ', com ' || public._agenda_plural(g.produtos, 'produto', 'produtos') else '' end end)
                 || case when v_princ is not null
                         then format('Para prever a chegada, conto pelo cadastro %s. %s é o mesmo fornecedor?',
                                     coalesce('de ' || v_rs.cidade, 'com CNPJ'),
                                     coalesce('O de ' || g.cidade, 'O outro'))
                         else 'Até você dizer, não conto o prazo de nenhum dos dois. São o mesmo fornecedor?' end;
        if public._agenda_material_perguntar('fornecedor_cadastro', 'fornecedor_cadastro:' || g.id, null, null, null, null,
                                             v_txt, null, p_agora) then
          n_perg := n_perg + 1;
        end if;
      end loop;
    end if;
  end loop;

  -- (3) A pergunta dos principais, uma vez: como você compra deles e em quantos dias chega (um áudio só).
  if v_sem >= c_minimo then
    if public._agenda_material_perguntar('fornecedores_prazo', 'fornecedores_prazo', null, null, null, null,
         format('Para eu prever quando chega o material, me diga como você compra dos fornecedores principais e em quantos '
                || 'dias chega de cada um (faltam %s). Pode ser um áudio só; *agenda fornecedores* mostra a lista com o meu '
                || 'chute pela cidade.', v_sem),
         null, p_agora) then
      n_perg := n_perg + 1;
    end if;
  end if;

  return jsonb_build_object('perguntas', n_perg, 'resolvidas', n_res + n_res2, 'sem_modalidade', v_sem, 'modo', v_modo);
end;
$function$;

comment on function public._agenda_material_cadastros(date, timestamptz) is
  'Agenda de Produção (Fase 4, P5), passo do material "cadastros" (modo_material): (1) a limpeza — a pergunta fornecedor_cadastro cujo fornecedor já tem a modalidade dita, foi desativado ou não tem mais dúvida, e a fornecedores_prazo com menos de 3 principais sem a modalidade, se resolvem; (2) dos fornecedores que importam (_agenda_fornecedores_principais) sem a modalidade dita: sem cidade nem UF (duvida sem_lugar) = "O fornecedor Mateus está sem cidade no cadastro — é o do "Compressor 12V de…" do Flávio. Como você compra desse fornecedor e em quantos dias chega?"; cadastro repetido de classe diferente (duvida duplicado) = uma pergunta por cadastro que não é o principal: "O fornecedor Kamell está cadastrado mais de uma vez: Vila Velha/ES (com CNPJ e 31 produtos) e Itajaí/SC (sem CNPJ). Para prever a chegada, conto pelo cadastro de Vila Velha. O de Itajaí é o mesmo fornecedor?" — chave fornecedor_cadastro:<o cadastro>, uma vez; (3) com 3 ou mais principais sem a modalidade, a pergunta única fornecedores_prazo (o áudio só, *agenda fornecedores*). Pelo _agenda_material_perguntar (o modo do material; validade material_pergunta_validade). {perguntas, resolvidas, sem_modalidade, modo}; desligado = {pulado}.';

-- ── 7. A rodada do material ─────────────────────────────────────────────────────────────────────────────

create or replace function public.agenda_material_vigiar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos  constant text[] := array['notas', 'pix', 'sinais', 'tercos', 'cadastros', 'sincronizar'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
  v_os      uuid;
  v_n       int;
  v_modos   jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora do material.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor);
  -- A fila velha do fornecedor roda SEMPRE, em qualquer modo (até desligado): o que não saiu na janela, ou ficou na fila
  -- quando o dono tirou o fornecedor de ligado, não sai mais. Só mexe em linha source agenda-fornecedor.
  begin
    v_cont := jsonb_build_object('fila', public._agenda_material_fila(p_hoje, p_agora));
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    v_erros := v_erros + 1;
    v_falhas := v_falhas || jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
    perform public.log_app_error('db', 'material da agenda, passo fila: ' || v_msg, 'agenda', 'material:fila', 'error',
                                 jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;
  if cf.modo_material = 'desligado' and cf.modo_detector = 'desligado' and cf.modo_fornecedor = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', v_modos, 'fila', v_cont -> 'fila', 'erros', v_erros, 'falhas', v_falhas);
  end if;

  foreach v_passo in array c_passos loop
    continue when v_passo in ('notas', 'pix', 'cadastros') and cf.modo_material = 'desligado';
    continue when v_passo = 'sinais' and cf.modo_detector = 'desligado';
    continue when v_passo = 'tercos' and cf.modo_fornecedor = 'desligado';
    -- só em ligado o material da OS muda (em sombra a nota e a mensagem não mexem na linha)
    continue when v_passo = 'sincronizar' and cf.modo_material <> 'ligado';
    begin
      if v_passo = 'sincronizar' then
        -- as OS que a nota importada ou a mensagem do fornecedor mudaram NESTA rodada (a ação material executada agora)
        v_n := 0;
        for v_os in
          select distinct a.service_order_id from public.agenda_acoes a
           where a.tipo = 'material' and a.executada and a.origem in ('nota', 'fornecedor') and a.dia = p_hoje
             and a.criada_em = p_agora and a.service_order_id is not null
           order by 1
        loop
          perform public.os_material_sincronizar(v_os, p_hoje);
          v_n := v_n + 1;
        end loop;
        v_r := jsonb_build_object('oss', v_n);
      else
        execute format('select public.%I($1, $2)', '_agenda_material_' || v_passo) into v_r using p_hoje, p_agora;
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('material da agenda, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'material:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'material', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modos', v_modos, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_material_vigiar(date, timestamptz) is
  'Agenda de Produção (Fase 4, P5): a rodada do material, a cada 15 min, pelo task-automations (depois do material, antes da rotina e da vigia). Antes de tudo, em qualquer modo, a fila velha do fornecedor (_agenda_material_fila). modo_material, modo_detector e modo_fornecedor desligados = {rodou: false}. Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action material:<passo>, e os outros rodam): notas e pix (modo_material: _agenda_material_notas, _agenda_material_pix), sinais (modo_detector: _agenda_material_sinais), terços (modo_fornecedor: _agenda_material_tercos, a mensagem ao fornecedor), cadastros (modo_material: _agenda_material_cadastros) e sincronizar (modo_material ligado: os_material_sincronizar das OS que a nota ou a mensagem mudaram nesta rodada). Uma linha em agenda_vigia_rodadas (rotina = material). {rodou, modos, contagens, erros, falhas}. Só service_role.';

-- ── 8. A saúde: o bloco do material ─────────────────────────────────────────────────────────────────────
-- Corpo de 20261026100300 copiado (a definição mais nova); as mudanças estão marcadas "-- FASE 4:" (fora dos blocos, só a
-- vírgula do ok e a do fim do resultado).

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
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente.';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A rodada do material: só service_role (o task-automations). Nunca anon, nunca authenticated.
revoke all on function public.agenda_material_vigiar(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_material_vigiar(date, timestamptz) to service_role;

-- As peças que mandam ao fornecedor (o registro, a 1ª trava, a 2ª trava) e os passos novos: ninguém de fora — só a rodada
-- (agenda_material_vigiar, security definer) os chama; o gatilho roda sozinho. Assim o ÚNICO caminho até a fila
-- agenda-fornecedor é a rodada, com as três travas.
revoke all on function
  public._agenda_fornecedor_registrar(uuid, uuid, uuid, integer, text, timestamptz),
  public._agenda_fornecedor_enfileirar(uuid), public._agenda_fila_do_fornecedor(),
  public._agenda_material_fila(date, timestamptz), public._agenda_material_tercos(date, timestamptz),
  public._agenda_material_cadastros(date, timestamptz),
  public._agenda_fornecedor_telefone(uuid), public._agenda_fornecedor_conversou(uuid, timestamptz),
  public._agenda_fornecedor_no_periodo(uuid, date, date, uuid)
  from public, anon, authenticated, service_role;

-- Os fornecedores que importam (leem as compras vivas, que são só do service_role): service_role.
revoke all on function public._agenda_fornecedores_principais(date) from public, anon, authenticated;
grant execute on function public._agenda_fornecedores_principais(date) to service_role;

-- As leituras e os textos (invoker, STABLE) que a agenda_saude e as leituras do P6 usam: authenticated (o painel, com a RLS
-- de quem lê) e service_role; nunca anon.
revoke all on function
  public._agenda_fornecedor_dia_de_janela(date), public._agenda_fornecedor_fora_da_janela(timestamptz, timestamptz),
  public._agenda_fornecedor_quando(timestamptz), public._agenda_fornecedor_texto_proibido(text, uuid),
  public._agenda_fornecedor_texto(uuid)
  from public, anon;
grant execute on function
  public._agenda_fornecedor_dia_de_janela(date), public._agenda_fornecedor_fora_da_janela(timestamptz, timestamptz),
  public._agenda_fornecedor_quando(timestamptz), public._agenda_fornecedor_texto_proibido(text, uuid),
  public._agenda_fornecedor_texto(uuid)
  to authenticated, service_role;

-- A recriada mantém as portas dela (create or replace não muda a ACL; repetidas aqui para a migration se bastar):
revoke all on function public.agenda_saude(date, timestamptz) from public, anon;
grant execute on function public.agenda_saude(date, timestamptz) to authenticated, service_role;
