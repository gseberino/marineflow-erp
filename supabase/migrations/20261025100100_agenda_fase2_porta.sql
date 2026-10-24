-- Agenda de Produção, Fase 2 ("O gestor de agenda"), pacote P1: a porta única de status e as datas da OS.
-- Spec: scratchpad agenda-pesquisa/spec-fase2.md (§5; §3.3 d6, d14, d16). Plano: plano-final.md §4.7; revisão §9.
-- Depende de 20261025100000 (agenda_acoes, agenda_alocacoes, agenda_config.modo_proposta) e da Fase 1 (os_prontidao,
-- _agenda_cfg, _agenda_nome_curto).
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas e UM gatilho novo em service_orders, que só age com a agenda automática
-- ligada; não grava dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: hoje sete caminhos escrevem o status da OS cada um com a sua regra (a tela de agendar, o botão da R1, a
-- aprovação com PIN, o agendar e o mudar status do assistente, o check-in e a OC criada a partir da OS). Dois erros
-- conhecidos saem disso: a OC passa uma OS EM ANDAMENTO para "aguardando peças" (NOVO-agenda-10), e uma OS
-- "aguardando peças" vira "agendada" sem a peça na mão (o caso da OS-00104 em 06/10). A porta é uma função só, no
-- banco, com a regra de cada passagem; os caminhos passam a chamá-la no pacote P4.
--
-- O QUE MUDA:
--   1. os_transicionar_status(OS, para, via, motivo, autor, check_in, p_hoje, p_agora): a porta. Trava a OS, confere
--      quem pede, aplica a regra (valem em TODOS os modos: nunca regredir "em andamento"; "aguardando peças" só sai
--      com todo item crítico na mão; a OC numa OS em andamento não muda nada; com a agenda automática ligada,
--      "agendada" só com dia no plano), grava pela _agenda_escrever_os e deixa uma linha em agenda_acoes (tipo
--      status, com antes/depois e a frase ao dono). Devolve {ok, mudou, de, para, texto, acao_id}.
--   2. _agenda_escrever_os: a ÚNICA função que liga a chave agenda.porta (set_config local à transação), escreve na
--      OS e desliga. Sem grant a ninguém: só as funções security definer do banco a chamam.
--   3. _agenda_espelhar_datas(OS, p_hoje): só com modo_proposta = 'ligado', scheduled_start_at/end_at = o começo do
--      1º e o fim do último meio-dia vigente (sem reserva e sem "não cumprido"); sem nenhum, as duas nulas.
--   4. Gatilho trg_so_datas_pela_agenda (BEFORE UPDATE OF scheduled_start_at, scheduled_end_at em service_orders):
--      com modo_proposta = 'ligado', recusa mudar a data da OS fora da porta, com a frase que diz ao dono o que
--      fazer. Valor igual passa (o formulário que salva sem mexer na data continua funcionando). Fora de 'ligado'
--      não faz nada. É o 16º gatilho de service_orders e só lê agenda_config: a ordem entre eles não importa.
--   Auxiliares: _agenda_status_texto (o status em português, como o dono vê na tela), _agenda_os_tem_dia (tem
--   meio-dia vigente de hoje em diante), _agenda_falta_material (a frase do que ainda falta de material) e
--   _agenda_porta_fica (a resposta de quando nada muda).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase2_porta.sql):
--   · A tabela de regras não dizia das passagens laterais: "aguardando peças" ↔ "aguardando o cliente" e aberta ↔
--     aprovada passam sempre; "aguardando peças" → aberta/aprovada pede o material completo e "aguardando o
--     cliente" → aberta/aprovada pede o dono, a tela de agendar ou a aprovação (a mesma régua de ir para agendada:
--     sair da espera só com a espera resolvida).
--   · "Agendada → aberta/aprovada volta ao status de antes": só volta para aberta ou aprovada (o de antes, se era um
--     dos dois; senão aprovada). Voltar para "aguardando peças" depois que a peça chegou seria mentir.
--   · Nada muda, mas a resposta é a esperada (ok true, mudou false): em andamento → agendada/aberta/aprovada, a OC
--     em OS em andamento, "aguardando peças" sem a peça, o cliente que não liberou e, em 'ligado', agendada sem dia.
--     Recusa (ok false): encerrada, orçamento, concluir/cancelar/voltar a orçamento pela agenda, "parou" sem o dono
--     e o motivo, e tirar de agendada por quem não é a agenda nem o dono, ou com dia ainda no plano.
--   · O check_in_at nunca é sobrescrito, nem pela _agenda_escrever_os (coalesce no próprio update).
--   · Quem pede, sem login (service role): p_autor tem de ser admin/financeiro ativo ou técnico ativo ligado à OS
--     (a mesma régua de quem tem login); motor e vigia podem vir sem autor. Um JWT de outro papel sem login não
--     vale (o mesmo cuidado de _autor_da_agenda).
--   · A _agenda_escrever_os não lista no UPDATE a coluna que não muda: os gatilhos "AFTER UPDATE OF status" de
--     produção (estoque, ciclo de vida, comissão) só disparam quando o status muda de fato.
--   · _agenda_espelhar_datas também não tem grant (a spec só dizia isso da _agenda_escrever_os): quem tem a chave
--     das datas é só o banco.
--
-- RISCO REGISTRADO: set_config('agenda.porta', 'on', true) é alcançável por quem tem SQL direto no banco (o dono pelo
-- painel do Supabase, a service role por SQL). Pela API não: set_config está em pg_catalog, fora do schema que o
-- PostgREST expõe, e a única função de public que liga a chave (_agenda_escrever_os) não tem grant.
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum dado, nenhuma função existente; nenhum caminho do app ainda chama a porta
-- (P4). Com modo_proposta 'desligado' (hoje) ou 'sombra' o gatilho das datas não faz nada.
--
-- ORDEM DE LIGAR: depois de 20261025100000; antes de 20261025100200 (o motor chama a porta e o espelho).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase2_porta.sql (begin/rollback; cada linha da tabela de regras,
-- check-in uma vez, o gatilho nos três modos, quem pode). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261025100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261025100100_agenda_fase2_porta.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261025100100', 'agenda_fase2_porta');"
--
-- IDEMPOTENTE: create or replace function, drop trigger if exists + create trigger, revoke/grant e comment.

-- ── 0. Auxiliares ───────────────────────────────────────────────────────────────────────────────────────

-- O status em português, como a tela mostra (ROTULOS_STATUS_OS em service-order-status.ts), em minúsculas.
create or replace function public._agenda_status_texto(p_status text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_status
    when 'draft'           then 'orçamento'
    when 'open'            then 'aberta'
    when 'approved'        then 'aprovada'
    when 'scheduled'       then 'agendada'
    when 'in_progress'     then 'em andamento'
    when 'awaiting_parts'  then 'aguardando peças'
    when 'awaiting_client' then 'aguardando o cliente'
    when 'completed'       then 'concluída'
    when 'invoiced'        then 'faturada'
    when 'cancelled'       then 'cancelada'
    else coalesce(p_status, '') end;
$function$;

comment on function public._agenda_status_texto(text) is
  'Agenda de Produção (Fase 2): o status da OS em português e minúsculas, como a tela mostra ("aguardando peças", "em andamento").';

-- A OS tem meio-dia vigente (publicado ou fixado, que não é reserva nem deu "não cumprido") de hoje em diante.
create or replace function public._agenda_os_tem_dia(p_os uuid, p_hoje date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select exists (
    select 1 from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.dia >= p_hoje and a.resultado is distinct from 'nao_cumprido');
$function$;

comment on function public._agenda_os_tem_dia(uuid, date) is
  'Agenda de Produção (Fase 2): a OS tem meio-dia vigente (não reserva, sem "não cumprido") de p_hoje em diante.';

-- O que ainda falta de material, pela prontidão da Fase 1: null = completo; senão a frase (sem o ponto final).
create or replace function public._agenda_falta_material(p_os uuid, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_mat  jsonb := public.os_prontidao(p_os, p_hoje) -> 'material';
  v_item text;
begin
  if v_mat ->> 'estado' = 'completo' then
    return null;
  end if;
  select coalesce(e ->> 'curto', e ->> 'descricao') into v_item
    from jsonb_array_elements(coalesce(v_mat -> 'itens', '[]'::jsonb)) with ordinality t(e, o)
   where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A'
   order by o limit 1;
  if v_item is not null then
    return format('Ainda falta "%s" na mão', v_item);
  end if;
  if jsonb_array_length(coalesce(v_mat -> 'embutidas', '[]'::jsonb)) > 0 then
    return format('Falta você dizer se "%s" tem peça a comprar', v_mat -> 'embutidas' -> 0 ->> 'curto');
  end if;
  return 'O material desta OS ainda não foi conferido (diga se tem peça a comprar)';
end;
$function$;

comment on function public._agenda_falta_material(uuid, date) is
  'Agenda de Produção (Fase 2): null quando os_prontidao diz material completo; senão a frase do que falta: o 1º item crítico fora do nível A ("Ainda falta "Compressor 12V SS65" na mão"), a peça embutida em aberto, ou o material não conferido.';

-- A resposta da porta quando nada muda.
create or replace function public._agenda_porta_fica(p_ok boolean, p_de text, p_texto text)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select jsonb_build_object('ok', p_ok, 'mudou', false, 'de', p_de, 'para', p_de, 'texto', p_texto, 'acao_id', null);
$function$;

comment on function public._agenda_porta_fica(boolean, text, text) is
  'Agenda de Produção (Fase 2): a resposta de os_transicionar_status quando nada muda — ok true (era o esperado) ou false (recusado), com a frase ao dono.';

-- ── 1. A única escrita ──────────────────────────────────────────────────────────────────────────────────

-- Liga a chave agenda.porta, escreve na OS e desliga. A chave é local à transação: se algo falhar no meio, o
-- rollback (da transação ou do bloco) a desfaz junto. Só a coluna que muda entra no UPDATE.
create or replace function public._agenda_escrever_os(p_os uuid, p_status text, p_check_in timestamptz,
                                                      p_inicio timestamptz, p_fim timestamptz, p_espelho boolean)
 returns void
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_status text;
  v_check  timestamptz;
  v_ini    timestamptz;
  v_fim    timestamptz;
begin
  select so.status, so.check_in_at, so.scheduled_start_at, so.scheduled_end_at
    into v_status, v_check, v_ini, v_fim
    from public.service_orders so where so.id = p_os for update;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  perform set_config('agenda.porta', 'on', true);
  if p_status is not null and p_status is distinct from v_status then
    -- O início entra junto com o status: os gatilhos do status já veem o check-in.
    update public.service_orders so
       set status = p_status, check_in_at = coalesce(so.check_in_at, p_check_in)
     where so.id = p_os;
  elsif p_check_in is not null and v_check is null then
    update public.service_orders so set check_in_at = p_check_in where so.id = p_os and so.check_in_at is null;
  end if;
  if coalesce(p_espelho, false) and (p_inicio is distinct from v_ini or p_fim is distinct from v_fim) then
    update public.service_orders so set scheduled_start_at = p_inicio, scheduled_end_at = p_fim where so.id = p_os;
  end if;
  perform set_config('agenda.porta', 'off', true);
end;
$function$;

comment on function public._agenda_escrever_os(uuid, text, timestamptz, timestamptz, timestamptz, boolean) is
  'Agenda de Produção (Fase 2): a ÚNICA função que liga agenda.porta. Escreve o status (se mudou, com o check-in junto), o check-in (só se estava vazio: nunca sobrescreve) e, com p_espelho, as datas scheduled_* (nulas = a OS saiu do plano). Sem grant: só as funções security definer da agenda a chamam.';

-- ── 2. A porta ──────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.os_transicionar_status(
  p_os       uuid,
  p_para     text,
  p_via      text,
  p_motivo   text        default null,
  p_autor    uuid        default null,
  p_check_in timestamptz default null,
  p_hoje     date        default public._hoje_brt(),
  p_agora    timestamptz default now())
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
begin
  if p_via is null or p_via not in ('tela_agendar', 'aprovacao', 'assistente', 'check_in', 'oc', 'motor', 'vigia',
                                    'conferencia', 'dono', 'desfazer') then
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

  select so.id, so.service_order_number as numero, so.status, so.check_in_at, cl.name as cliente
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
    v_autor := v_uid;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') or (p_autor is null and p_via not in ('motor', 'vigia')) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    v_autor := p_autor;
  end if;
  if v_autor is not null
     and not (public.is_admin_or_financial(v_autor)
              or exists (select 1 from public.service_order_technicians t
                           join public.app_users u on u.id = t.user_id
                          where t.service_order_id = p_os and t.user_id = v_autor and u.active)) then
    raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
  end if;

  v_de   := v_os.status;
  v_nome := coalesce(public._agenda_nome_curto(v_os.cliente) || ' (' || v_os.numero || ')', v_os.numero);

  -- Encerrada e orçamento: a agenda não mexe (conclusão, faturamento, cancelamento e conversão têm caminho próprio).
  if v_de in ('completed', 'invoiced', 'cancelled') then
    return public._agenda_porta_fica(false, v_de,
      format('A %s está %s: a agenda não muda o status dela.', v_os.numero, public._agenda_status_texto(v_de)));
  end if;
  if v_de = 'draft' then
    return public._agenda_porta_fica(false, v_de, 'Isso ainda é orçamento: converta antes.');
  end if;
  if v_para in ('completed', 'invoiced', 'cancelled') then
    return public._agenda_porta_fica(false, v_de, 'Concluir é pela tela (botão Concluir da OS); cancelar é Cancelar OS.');
  end if;
  if v_para = 'draft' then
    return public._agenda_porta_fica(false, v_de, 'Uma OS não volta a ser orçamento pela agenda.');
  end if;

  -- Igual: nada a fazer — menos o início que faltava numa OS em andamento.
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
    if v_de = 'in_progress' then
      return public._agenda_porta_fica(true, v_de, 'A OS já começou: não volta para agendada.');
    end if;
    if v_de = 'awaiting_client' and p_via not in ('dono', 'tela_agendar', 'aprovacao') then
      return public._agenda_porta_fica(true, v_de, 'O cliente ainda não liberou: a OS continua aguardando o cliente.');
    end if;
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

  elsif v_para in ('awaiting_parts', 'awaiting_client') then
    if v_de = 'in_progress' then
      if p_via = 'oc' then
        return public._agenda_porta_fica(true, v_de, 'A OS segue em andamento; a compra foi registrada.');
      end if;
      if p_via <> 'dono' or v_motivo is null then
        return public._agenda_porta_fica(false, v_de,
          'A OS já começou: só volta a aguardar quando você diz que parou e por quê.');
      end if;
    end if;

  elsif v_para in ('open', 'approved') then
    if v_de = 'in_progress' then
      return public._agenda_porta_fica(true, v_de,
        format('A OS já começou: não volta para %s.', public._agenda_status_texto(v_para)));
    end if;
    if v_de = 'scheduled' then
      if p_via not in ('motor', 'vigia', 'desfazer', 'dono') then
        return public._agenda_porta_fica(false, v_de, 'A OS está agendada: para tirar da agenda, desmarque o dia.');
      end if;
      if public._agenda_os_tem_dia(p_os, p_hoje) then
        return public._agenda_porta_fica(false, v_de, 'A OS ainda tem dia no plano: tire o dia antes.');
      end if;
      -- Volta ao que era antes de agendar (aberta ou aprovada); sem registro, aprovada.
      select a.status_antes into v_antes
        from public.agenda_acoes a
       where a.service_order_id = p_os and a.tipo = 'status' and a.executada and a.status_depois = 'scheduled'
       order by a.criada_em desc, a.id desc
       limit 1;
      v_para := case when v_antes in ('open', 'approved') then v_antes else 'approved' end;
    elsif v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    elsif v_de = 'awaiting_client' and p_via not in ('dono', 'tela_agendar', 'aprovacao') then
      return public._agenda_porta_fica(true, v_de, 'O cliente ainda não liberou: a OS continua aguardando o cliente.');
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
  v_origem := case p_via
    when 'tela_agendar' then 'tela'
    when 'check_in'     then 'sistema'
    when 'oc'           then 'sistema'
    when 'desfazer'     then 'dono'
    else p_via end;

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                   status_depois, antes, depois, texto, motivo, autor, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
          jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at),
          jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
          left(v_texto, 400), left(v_motivo, 200), v_autor,
          case when v_origem in ('motor', 'vigia') then p_agora + c.desfazer_validade end)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                            'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check));
end;
$function$;

comment on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz) is
  'Agenda de Produção (Fase 2): a porta única de status da OS. Vias: tela_agendar, aprovacao, assistente, check_in, oc, motor, vigia, conferencia, dono, desfazer. Regras (todos os modos): encerrada/orçamento não mudam; concluir/cancelar não é por aqui; em andamento nunca volta (agendada/aberta/aprovada) e só volta a aguardar com "parou" do dono e o motivo (a OC: ok, nada muda); aguardando peças só sai com o material completo; aguardando o cliente só sai pelo dono, a tela de agendar ou a aprovação; agendada só volta (para o status de antes) pela agenda ou pelo dono e sem dia no plano; em modo_proposta ligado, agendada só com dia no plano. check_in_at uma vez. Toda mudança: 1 linha em agenda_acoes (tipo status; desfazível por desfazer_validade quando foi o motor/vigia). Devolve {ok, mudou, de, para, texto, acao_id, check_in_at}.';

-- ── 3. O espelho das datas ──────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_espelhar_datas(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config := public._agenda_cfg();
  v_ini timestamptz;
  v_fim timestamptz;
  v_era record;
begin
  if c.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', true, 'mudou', false, 'modo', c.modo_proposta);
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);

  select so.scheduled_start_at as inicio, so.scheduled_end_at as fim into v_era
    from public.service_orders so where so.id = p_os for update;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  select min(lower(a.periodo)), max(upper(a.periodo)) into v_ini, v_fim
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
     and a.resultado is distinct from 'nao_cumprido';

  if v_era.inicio is not distinct from v_ini and v_era.fim is not distinct from v_fim then
    return jsonb_build_object('ok', true, 'mudou', false, 'modo', c.modo_proposta, 'inicio', v_ini, 'fim', v_fim);
  end if;
  perform public._agenda_escrever_os(p_os, null, null, v_ini, v_fim, true);
  return jsonb_build_object('ok', true, 'mudou', true, 'modo', c.modo_proposta, 'inicio', v_ini, 'fim', v_fim,
                            'antes', jsonb_build_object('inicio', v_era.inicio, 'fim', v_era.fim));
end;
$function$;

comment on function public._agenda_espelhar_datas(uuid, date) is
  'Agenda de Produção (Fase 2): só com modo_proposta ligado — scheduled_start_at/end_at da OS = o começo do 1º e o fim do último meio-dia vigente (sem reserva e sem "não cumprido"); sem nenhum, nulas (a OS saiu do plano). Escreve pela _agenda_escrever_os. Fora de ligado não escreve nada. Sem grant: chamada pelas funções do motor.';

-- ── 4. O gatilho das datas ──────────────────────────────────────────────────────────────────────────────
create or replace function public._so_datas_pela_agenda()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if (new.scheduled_start_at is distinct from old.scheduled_start_at
      or new.scheduled_end_at is distinct from old.scheduled_end_at)
     and coalesce(current_setting('agenda.porta', true), '') <> 'on'
     and exists (select 1 from public.agenda_config c where c.id and c.modo_proposta = 'ligado') then
    raise exception 'Com a agenda automática ligada, a data da OS é da agenda. Para mudar, diga na conversa (por exemplo "passa o Lenine para quinta") ou use Agendar na tela da Agenda.';
  end if;
  return new;
end;
$function$;

comment on function public._so_datas_pela_agenda() is
  'Agenda de Produção (Fase 2): gatilho BEFORE UPDATE OF scheduled_start_at, scheduled_end_at em service_orders — com modo_proposta ligado, recusa mudar a data fora da porta (agenda.porta). Valor igual passa; fora de ligado, nada. security definer: lê agenda_config mesmo para quem a RLS não deixa ler (o técnico que salva a OS).';

drop trigger if exists trg_so_datas_pela_agenda on public.service_orders;
create trigger trg_so_datas_pela_agenda before update of scheduled_start_at, scheduled_end_at on public.service_orders
  for each row execute function public._so_datas_pela_agenda();

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- A porta: o painel (authenticated, com o cargo conferido dentro) e o WhatsApp/motor (service_role). Nunca anon.
revoke all on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz)
  from public, anon;
grant execute on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz)
  to authenticated, service_role;

-- As leituras auxiliares: como as da Fase 1 (authenticated e service_role).
revoke all on function public._agenda_status_texto(text), public._agenda_os_tem_dia(uuid, date),
  public._agenda_falta_material(uuid, date), public._agenda_porta_fica(boolean, text, text) from public, anon;
grant execute on function public._agenda_status_texto(text), public._agenda_os_tem_dia(uuid, date),
  public._agenda_falta_material(uuid, date), public._agenda_porta_fica(boolean, text, text) to authenticated, service_role;

-- A chave das datas: ninguém de fora (nem service_role). Só as funções security definer do banco.
revoke all on function public._agenda_escrever_os(uuid, text, timestamptz, timestamptz, timestamptz, boolean),
  public._agenda_espelhar_datas(uuid, date) from public, anon, authenticated, service_role;
revoke all on function public._so_datas_pela_agenda() from public, anon, authenticated;
