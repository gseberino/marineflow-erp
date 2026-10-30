-- Agenda de Produção, correção de 29/10 (pacote P4): o aviso do gestor ao dono pelo WhatsApp.
-- (4 parâmetros novos em agenda_config, com os CHECKs; 2 listas fechadas ampliadas; 1 tabela nova; 2 gatilhos novos na fila;
-- 11 funções novas, 2 delas de gatilho; 1 recriada; nenhum dado muda)
--
-- NÃO APLICADA. A única função recriada, o gatilho _agenda_acoes_so_desfaz, é o corpo da definição MAIS NOVA (conferido com
-- grep em supabase/migrations, também nas 20261030* dos pacotes P1, P2 e P3, que não a recriam): 20261026100000. A mudança
-- está só no bloco "-- CORREÇÃO 29/10 (P4): … -- CORREÇÃO 29/10 (P4): fim"; fora dele nenhuma linha muda (o K de
-- supabase/tests/agenda_correcao_2910_p4.sql confere).
--
-- ═══ POR QUE ═══ (auditoria de 29/10, leitor "entrega")
--   · A publicação da semana (qui 16:30) não gerava mensagem nenhuma: _agenda_vigia_publicacao devolve só o texto, e
--     mensagem ao dono só nascia na violação que perde hoje ou amanhã (o acorde). A fila não tem nada da agenda desde 27/10.
--   · O canal pensado era a linha do fechamento das 17:30, mas a agenda só entra nas vagas que sobram dos 3 itens do
--     secretário: de 26 a 29/10 nunca sobrou. O dono nunca soube da reserva do Lenine.
--   · As perguntas que destravam o plano (o Lenine tem peça? quantos dias?) só contam como mostradas no fechamento enviado
--     ou de carona numa conversa sobre a OS: as 5 abertas têm mostrada_vezes = 0.
--   · O *desfaz semana* vale 24 h a partir da publicação: venceria antes de o dono saber que houve publicação.
--   O dono decidiu (29/10): o gestor cuida da agenda sozinho e TODO DIA; ele só quer saber o que mudou.
--
-- ═══ O QUE MUDA ═══
--   1. Parâmetros (agenda_config): gestor_aviso_inicio (09:30) e gestor_aviso_fim (19:30), a janela do aviso em Brasília
--      (de segunda a sábado; nunca no domingo); gestor_aviso_dia_max (3 por dia; 0 = não manda aviso, o fechamento continua
--      como é); gestor_aviso_texto_max (2400 letras, o teto do texto).
--   2. As listas fechadas agenda_acoes.contada_via e agenda_perguntas.mostrada_via ganham 'aviso'.
--   3. agenda_dono_avisos (nova): o registro de cada aviso (uma por rodada; o texto, as ações e as perguntas que ele leva, o
--      estado na fila, quando saiu e quando as mudanças voltaram a "por contar" porque ele não saiu). NUNCA apagado; só o
--      estado, a recusa, a fila e as horas mudam.
--   4. O aviso, em três passos que o task-automations chama a cada 15 min, logo depois da vigia (supabase/functions/
--      task-automations/agenda-aviso.ts; o texto é montado em _shared/agenda/aviso-do-gestor.ts):
--      · agenda_aviso_conferir(p_agora): o que a fila mandou passa a contar de verdade — a ação contada na hora em que
--        saiu (contada_via 'aviso'), o prazo do *desfaz* a partir dali (desfazivel_ate = a hora que saiu + desfazer_validade,
--        nunca menos do que já era) e a pergunta mostrada (mostrada_vezes + 1, mostrada_em, mostrada_via 'aviso'); o que não
--        saiu (a fila desistiu, o worker recusou fora da janela, a janela passou com a linha parada, o aviso desligou) volta
--        a "por contar" e vai no próximo aviso (ou no fechamento);
--      · agenda_aviso_pecas(p_hoje, p_agora): com a agenda automática e a vigia ligadas, o que mudou sozinho e o dono ainda
--        não soube — a publicação da semana, o encaixe, a reserva promovida ou solta, o remanejo (as ações publicar, criar,
--        mover, cancelar, promover_reserva e soltar_reserva da vigia e do motor, pelos grupos do *o que mudou*), o que ficou
--        de fora e por quê (curto, pelas propostas dessas ações) e, uma vez por dia, as perguntas que destravam (o texto da
--        rodada de aprontar, agenda_aprontar, e as perguntas abertas que ele cobre). Fora da janela, no teto do dia ou sem
--        nada novo, não avisa: o que mudou espera e sai junto na abertura da janela;
--      · agenda_aviso_enfileirar(...): a 1ª trava — confere de novo o modo, a janela, o teto, o dono e que as mudanças ainda
--        estão por contar; registra o aviso (uma por rodada: rodada única) e o põe na fila (source agenda-dono, a chave da
--        rodada, as tentativas que cabem na janela); as ações ficam contadas desde já (o fechamento das 17:30 e o aviso
--        seguinte não as repetem; se a mensagem não sair, o conferir as devolve).
--   5. A 2ª trava: o gatilho trg_agenda_fila_do_dono em whatsapp_send_queue, SÓ para source agenda-dono — recusa a linha
--      sem o aviso registrado, com outro texto, outra chave ou outro telefone que não o do dono, com alguma tentativa fora da
--      janela ou acima do teto; a nova tentativa fora da janela vira falha; a linha não muda de texto, telefone, origem nem
--      chave. (A 3ª trava é o worker: _shared/agenda/janela-da-fila.ts, a origem agenda-dono.)
--   6. _agenda_acoes_so_desfaz (de 20261026100000): a ação contada pelo aviso pode ter o desfazivel_ate ADIANTADO (nunca
--      atrasado), no mesmo update que confirma a contagem — é o "prazo do *desfaz* a partir de quando o dono soube".
--   Não muda: o fechamento das 17:30 (o aviso é o canal principal; o fechamento só deixa de repetir o que o aviso já contou,
--   pela contada_em, como já fazia com o acorde), a vigia, o motor, o acorde da perda de hoje ou amanhã e o que ele conta.
--
-- Ordem de ligar: depois das migrations das Fases 0 a 6 (todas em produção) e das 20261030100000 (P1), 100100 (P2) e 100200
-- (P3); ANTES do deploy do task-automations (que chama as 3 RPCs: sem elas o passo registra o erro e segue) e do
-- whatsapp-queue-worker (a 3ª trava; sem ele, a linha agenda-dono sai como as outras, ainda presa às 2 travas do banco).
-- Aplicar com o OK nomeado do dono. Prova: supabase/tests/agenda_correcao_2910_p4.sql (bancada).
--
-- DESFAZER: gestor_aviso_dia_max = 0 desliga o aviso na hora (o conferir devolve o que estiver na fila). Para tirar tudo:
--   update public.agenda_config set gestor_aviso_dia_max = 0;   -- e um tique do task-automations
--   drop trigger if exists trg_agenda_fila_do_dono on public.whatsapp_send_queue;
--   drop trigger if exists trg_agenda_fila_do_dono_linha on public.whatsapp_send_queue;
--   e recriar _agenda_acoes_so_desfaz com o corpo de 20261026100000. A tabela, as funções novas, os parâmetros e os
--   valores 'aviso' das listas podem ficar (ninguém os usa sem o task-automations novo).
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$, drop constraint if exists + add, create table/index if not
-- exists, create or replace function, drop trigger if exists + create, drop policy if exists + create, revoke/grant e comment.

-- ── 1. Os parâmetros novos ─────────────────────────────────────────────────────────────────────────────────────
-- A janela e o teto do aviso do gestor ao dono. Moram em agenda_config, como toda janela da agenda.
alter table public.agenda_config
  add column if not exists gestor_aviso_inicio    time     not null default '09:30',
  add column if not exists gestor_aviso_fim       time     not null default '19:30',
  add column if not exists gestor_aviso_dia_max   smallint not null default 3,
  add column if not exists gestor_aviso_texto_max integer  not null default 2400;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_gestor_aviso_inicio_check',    'check (gestor_aviso_inicio between time ''07:30'' and time ''11:00'')'),
      ('agenda_config_gestor_aviso_fim_check',       'check (gestor_aviso_fim between time ''16:45'' and time ''20:00'')'),
      ('agenda_config_gestor_aviso_dia_max_check',   'check (gestor_aviso_dia_max between 0 and 6)'),
      ('agenda_config_gestor_aviso_texto_max_check', 'check (gestor_aviso_texto_max between 600 and 4000)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.agenda_config.gestor_aviso_inicio is
  'Agenda de Produção (correção de 29/10, P4): a partir de quando (Brasília) o aviso do gestor pode sair — depois da janela da manhã (só a manhã pergunta até 09:30). O que mudou antes espera e sai junto aqui.';
comment on column public.agenda_config.gestor_aviso_fim is
  'Agenda de Produção (correção de 29/10, P4): até quando (Brasília, aberto) o aviso do gestor pode sair; toda tentativa da fila fica antes disto. Nunca de madrugada; nunca no domingo.';
comment on column public.agenda_config.gestor_aviso_dia_max is
  'Agenda de Produção (correção de 29/10, P4): quantos avisos do gestor por dia, no máximo (o que passar espera o dia seguinte). 0 = não manda aviso (o fechamento das 17:30 continua contando como antes).';
comment on column public.agenda_config.gestor_aviso_texto_max is
  'Agenda de Produção (correção de 29/10, P4): o teto do texto do aviso do gestor (letras). O montador tira primeiro o que ficou de fora, depois as perguntas, depois as últimas mudanças ("e mais N").';

-- ── 2. As listas fechadas: 'aviso' ─────────────────────────────────────────────────────────────────────────────
alter table public.agenda_acoes drop constraint if exists agenda_acoes_contada_via_check;
alter table public.agenda_acoes add constraint agenda_acoes_contada_via_check
  check (contada_via in ('fechamento', 'acorde', 'conversa', 'aviso'));
alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_mostrada_via_check;
alter table public.agenda_perguntas add constraint agenda_perguntas_mostrada_via_check
  check (mostrada_via in ('fechamento', 'acorde', 'conversa', 'aviso'));

-- ── 3. O registro do aviso ─────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_dono_avisos (
  id            uuid primary key default gen_random_uuid(),
  -- o instante da rodada (o p_agora da vigia e do aviso no mesmo tique): uma mensagem por rodada
  rodada        timestamptz not null unique,
  dia           date not null,
  texto         text not null check (char_length(texto) between 3 and 4000),
  acao_ids      uuid[] not null check (cardinality(acao_ids) > 0),
  pergunta_ids  uuid[] not null default '{}',
  com_perguntas boolean not null default false,
  telefone      text not null,
  enviar_em     timestamptz not null,
  estado        text not null default 'registrada' check (estado in ('registrada', 'enfileirada', 'enviada', 'recusada')),
  recusa_motivo text check (recusa_motivo in ('janela', 'domingo', 'modo', 'teto', 'fila')),
  fila_id       uuid,
  dedupe_key    text not null unique,
  enviada_em    timestamptz,
  devolvida_em  timestamptz,
  criada_em     timestamptz not null default now(),
  constraint dono_aviso_recusa_coerente  check ((estado = 'recusada') = (recusa_motivo is not null)),
  constraint dono_aviso_enviada_coerente check ((estado = 'enviada') = (enviada_em is not null)),
  constraint dono_aviso_devolvida_so_recusada check (devolvida_em is null or estado = 'recusada')
);

create index if not exists agenda_dono_avisos_dia on public.agenda_dono_avisos(dia, criada_em);
create index if not exists agenda_dono_avisos_abertos on public.agenda_dono_avisos(estado) where estado in ('enfileirada', 'recusada');

comment on table public.agenda_dono_avisos is
  'Agenda de Produção (correção de 29/10, P4): cada aviso do gestor ao dono pelo WhatsApp — o que a agenda mudou sozinha (publicou, encaixou, promoveu ou soltou reserva, remanejou), o que ficou de fora e as perguntas que destravam. Uma por rodada (rodada única). acao_ids: as ações que ele conta (contada_via aviso); pergunta_ids: as perguntas que ele mostra. Enviada = a fila mandou (enviada_em = sent_at). Recusada (janela, domingo, modo, teto, fila) = não saiu; devolvida_em = as ações voltaram a "por contar". NUNCA apagado; só estado, recusa_motivo, fila_id, enviada_em e devolvida_em mudam.';
comment on column public.agenda_dono_avisos.fila_id is 'whatsapp_send_queue.id (sem FK: a fila é podada).';
comment on column public.agenda_dono_avisos.dedupe_key is 'agenda-dono:aviso:<a rodada em UTC> — a chave da fila (a mesma rodada nunca entra duas vezes).';

create or replace function public._agenda_dono_avisos_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           array['estado', 'recusa_motivo', 'fila_id', 'enviada_em', 'devolvida_em'], '{}'::text[]) then
    raise exception 'O aviso registrado não muda: só o estado, a recusa, a fila e as horas.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_dono_avisos_so_muda() is
  'Agenda de Produção (correção de 29/10, P4): gatilho BEFORE UPDATE de agenda_dono_avisos — só estado, recusa_motivo, fila_id, enviada_em e devolvida_em mudam; o texto, as ações, as perguntas, o telefone e a rodada ficam como foram.';

drop trigger if exists agenda_dono_avisos_nao_apaga on public.agenda_dono_avisos;
create trigger agenda_dono_avisos_nao_apaga before delete on public.agenda_dono_avisos
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_dono_avisos_so_muda on public.agenda_dono_avisos;
create trigger agenda_dono_avisos_so_muda before update on public.agenda_dono_avisos
  for each row execute function public._agenda_dono_avisos_so_muda();

alter table public.agenda_dono_avisos enable row level security;
drop policy if exists agenda_dono_avisos_leitura on public.agenda_dono_avisos;
create policy agenda_dono_avisos_leitura on public.agenda_dono_avisos
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
revoke all on table public.agenda_dono_avisos from public, anon, authenticated;
grant select on table public.agenda_dono_avisos to authenticated;
grant all on table public.agenda_dono_avisos to service_role;

-- ── 4. As peças de dentro ──────────────────────────────────────────────────────────────────────────────────────

-- O dono no WhatsApp: o 1º administrador ativo com o assistente no WhatsApp e telefone, por created_at — a mesma regra de
-- _shared/whatsapp/dono.ts (donoDoWhatsApp), de _comprovante_dono e de lembretes-de-revisao. Sem ele, nada.
create or replace function public._agenda_aviso_dono()
 returns table (id uuid, phone text)
 language sql
 stable
 set search_path to 'public'
as $function$
  select u.id, u.phone_normalized
    from public.app_users u
   where u.role = 'admin' and u.active and u.ai_whatsapp_enabled and u.phone_normalized is not null
   order by u.created_at asc, u.id
   limit 1;
$function$;

comment on function public._agenda_aviso_dono() is
  'Agenda de Produção (correção de 29/10, P4): o dono no WhatsApp (o 1º admin ativo com ai_whatsapp_enabled e telefone, por created_at) — a regra de donoDoWhatsApp (_shared/whatsapp/dono.ts). Sem linha = ninguém para avisar.';

-- O aviso está ligado: a agenda automática e a vigia em 'ligado' e algum aviso por dia (gestor_aviso_dia_max > 0).
create or replace function public._agenda_aviso_ligado()
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce((select c.modo_proposta = 'ligado' and c.modo_vigia = 'ligado' and c.gestor_aviso_dia_max > 0
                     from public.agenda_config c where c.id), false);
$function$;

comment on function public._agenda_aviso_ligado() is
  'Agenda de Produção (correção de 29/10, P4): o aviso do gestor pode sair? modo_proposta e modo_vigia em ligado e gestor_aviso_dia_max > 0. Fora disso, nada vai à fila (e o conferir devolve o que estiver nela).';

-- A janela de UMA tentativa de envio do aviso — a regra única: o enfileirar (a 1ª tentativa e quantas cabem), o gatilho da
-- fila (o INSERT e a nova tentativa) e o conferir leem daqui; o worker confere o mesmo na hora de mandar
-- (_shared/agenda/janela-da-fila.ts, origem agenda-dono). null = pode sair; senão o motivo: domingo; janela (outro dia que não
-- o da hora marcada, em Brasília, ou fora de [gestor_aviso_inicio, gestor_aviso_fim)).
create or replace function public._agenda_aviso_fora_da_janela(p_marcada timestamptz, p_quando timestamptz)
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
  if v_q::date <> (p_marcada at time zone 'America/Sao_Paulo')::date then
    return 'janela';
  end if;
  if v_q::time >= cf.gestor_aviso_inicio and v_q::time < cf.gestor_aviso_fim then
    return null;
  end if;
  return 'janela';
end;
$function$;

comment on function public._agenda_aviso_fora_da_janela(timestamptz, timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): a janela de uma tentativa de envio do aviso do gestor, a regra única do banco (o worker tem a mesma em _shared/agenda/janela-da-fila.ts) — null = pode sair; ''domingo''; ''janela'' (outro dia que não o da hora marcada, em Brasília, ou fora de [gestor_aviso_inicio, gestor_aviso_fim)).';

-- Quantos avisos ENTRARAM na fila com o dia de envio (Brasília) p_dia: a contagem única do teto (gestor_aviso_dia_max). O que
-- entrou conta em qualquer estado (saindo, enviado ou recusado: um aviso recusado de novo e de novo não vira enxurrada).
create or replace function public._agenda_aviso_no_dia(p_dia date, p_exceto uuid)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  select count(*)::int
    from public.agenda_dono_avisos v
   where v.id is distinct from p_exceto and v.fila_id is not null
     and (v.enviar_em at time zone 'America/Sao_Paulo')::date = p_dia;
$function$;

comment on function public._agenda_aviso_no_dia(date, uuid) is
  'Agenda de Produção (correção de 29/10, P4): o teto contado num lugar só — os avisos do gestor que ENTRARAM na fila (fila_id) com o dia de envio de Brasília p_dia, sem p_exceto. O enfileirar e o gatilho da fila contam igual.';

-- O que a agenda mudou sozinha e o dono ainda não soube: os grupos do *o que mudou* (_agenda_mudancas dos últimos 7 dias,
-- só o executado, não contado e não desfeito) que têm uma ação de plano da vigia ou do motor — a publicação da semana, o
-- encaixe (criar), o remanejo (mover, cancelar), a reserva promovida ou solta. O resto (o material da nota, a resposta do
-- cliente, o aprendizado, o status sozinho) continua só no fechamento. Cada grupo com o texto do *o que mudou*
-- (_agenda_mudanca_texto: quem vai, os dias e o *desfaz*), as ações (todas do grupo: o status que acompanha conta junto), as
-- OS e as propostas das ações. O *desfaz* entra mesmo se o prazo já passou: o prazo passa a contar de quando o aviso sair.
create or replace function public._agenda_aviso_mudancas(p_hoje date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with g as (
    select x.g, x.o,
           array(select y::uuid from jsonb_array_elements_text(coalesce(x.g -> 'acao_ids', '[]'::jsonb)) y) as ids
      from jsonb_array_elements(public._agenda_mudancas(p_hoje - 6, p_hoje, true, true, null)) with ordinality x(g, o)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'grupo', g.g ->> 'grupo', 'tipo', g.g ->> 'tipo',
           'texto', public._agenda_mudanca_texto(g.g, false),
           'acao_ids', to_jsonb(g.ids),
           'os', (select coalesce(jsonb_agg(distinct a.service_order_id), '[]'::jsonb) from public.agenda_acoes a
                   where a.id = any (g.ids) and a.service_order_id is not null),
           'propostas', (select coalesce(jsonb_agg(distinct a.proposta_id), '[]'::jsonb) from public.agenda_acoes a
                          where a.id = any (g.ids) and a.proposta_id is not null))
         order by g.o), '[]'::jsonb)
    from g
   where exists (select 1 from public.agenda_acoes a
                  where a.id = any (g.ids) and a.executada and a.origem in ('motor', 'vigia')
                    and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva'));
$function$;

comment on function public._agenda_aviso_mudancas(date) is
  'Agenda de Produção (correção de 29/10, P4): o que o aviso do gestor conta — os grupos de _agenda_mudancas(p_hoje − 6, p_hoje, executada, não contada) com ação de plano da vigia ou do motor (publicar, criar, mover, cancelar, promover_reserva, soltar_reserva). [{grupo, tipo, texto (_agenda_mudanca_texto), acao_ids, os, propostas}], na ordem do *o que mudou*.';

-- "Ficaram de fora 10: Rodrigo OS-00096 (só com você); Vanderlei, Flávio, Nelson e Giancarlo (material); …" — o que ficou
-- fora das propostas das mudanças, agrupado pelo porquê numa palavra, os nomes na ordem da proposta (o número junto quando
-- o nome se repete; até 4 nomes por porquê, depois "e mais N"). Sem as OS de p_sem (as que mudaram) nem as que saíram da
-- carteira. Nada = null.
create or replace function public._agenda_aviso_fora_texto(p_fora jsonb, p_sem uuid[])
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  with f as (
    select t.o, t.e ->> 'numero' as numero,
           coalesce(public._agenda_nome_curto(t.e ->> 'cliente_curto'), t.e ->> 'numero', 'uma OS') as curto,
           case
             when t.e ->> 'motivo' in ('material', 'atrasado', 'sem_previsao', 'comprado_sem_previsao', 'compra_sem_prazo',
                                       'compre_ate', 'material_nao_conferido', 'peca_embutida') then 'material'
             when t.e ->> 'motivo' = 'cliente' then 'esperando o cliente'
             when t.e ->> 'motivo' = 'bem' then 'esperando o barco ou o veículo'
             when t.e ->> 'motivo' = 'sinal' then 'esperando o sinal'
             when t.e ->> 'motivo' = 'orcamento' then 'orçamento que não virou OS'
             when t.e ->> 'motivo' = 'escopo' then 'falta fechar o que fazer'
             when t.e ->> 'motivo' = 'duracao' then 'falta saber quantos dias'
             when t.e ->> 'motivo' = 'so_com_voce' then 'só com você'
             when t.e ->> 'motivo' = 'padrao_do_dono' then 'falta saber os seus dias em campo'
             when t.e ->> 'motivo' in ('sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'nao_cabe') then 'sem lugar na equipe'
             when t.e ->> 'motivo' in ('depois', 'nao_antes') then 'só mais para a frente'
             when t.e ->> 'motivo' = 'espera' then 'esperando a sua decisão'
             when t.e ->> 'motivo' = 'parada' then 'parou?'
             when t.e ->> 'motivo' = 'congelada' then 'em espera'
             else 'outro motivo' end as rotulo
      from jsonb_array_elements(coalesce(p_fora, '[]'::jsonb)) with ordinality t(e, o)
     where coalesce(t.e ->> 'motivo', '') not in ('fora_da_carteira', 'nao_achei')
       and not coalesce(nullif(t.e ->> 'os', '')::uuid = any (coalesce(p_sem, '{}'::uuid[])), false)
  ),
  n as (
    select f.*, case when count(*) over (partition by public._agenda_normal(f.curto)) > 1 and f.numero is not null
                          and f.curto is distinct from f.numero
                     then f.curto || ' ' || f.numero else f.curto end as nome
      from f
  ),
  g as (
    select n.rotulo, min(n.o) as o, public._agenda_lista(array_agg(n.nome order by n.o), 4) as nomes from n group by n.rotulo
  )
  select case when (select count(*) from n) = 0 then null
              when (select count(*) from n) = 1
                then format('Ficou de fora: %s.', (select g.nomes || ' (' || g.rotulo || ')' from g))
              else format('Ficaram de fora %s: %s.', (select count(*) from n),
                          (select string_agg(g.nomes || ' (' || g.rotulo || ')', '; ' order by g.o) from g)) end;
$function$;

comment on function public._agenda_aviso_fora_texto(jsonb, uuid[]) is
  'Agenda de Produção (correção de 29/10, P4): a linha curta do que ficou de fora no aviso do gestor — "Ficaram de fora 10: Rodrigo OS-00096 (só com você); Vanderlei, Flávio, Nelson e Giancarlo (material); Kalmar OS-00032, Kalmar OS-00033 e Rodrigo OS-00076 (esperando o cliente); …" (o porquê numa palavra pelo motivo da proposta; o número quando o nome se repete; até 4 nomes por porquê). Sem as OS de p_sem nem as fora da carteira. Nada = null.';

-- ── 5. As três RPCs do aviso (o task-automations, a cada 15 min, logo depois da vigia) ───────────────────────────────

-- O que o aviso diria agora, sem gravar nada. {avisar: false, motivo} quando não é para avisar: modo (a agenda automática ou a
-- vigia fora de ligado), desligado (gestor_aviso_dia_max = 0), nada_mudou, fora_da_janela (com pendentes: o que espera a
-- janela abrir), teto (pendentes), sem_dono. Senão {avisar: true, rodada, dia, limite, cabecalho, mudancas[{texto,
-- acao_ids}], fora, rodape, perguntas: {texto, pergunta_ids, oss, voce} | null}. As perguntas (o texto da rodada de aprontar)
-- vão uma vez por dia: no 1º aviso do dia que entrou na fila com elas e não foi devolvido; as pergunta_ids são as abertas em
-- ligado que esse texto cobre (a peça, os dias e o "chegou?" das OS que ele lista; os seus dias em campo, quando ele pergunta).
create or replace function public.agenda_aviso_pecas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_m     jsonb;
  v_n     int;
  v_jan   text;
  v_props uuid[];
  v_oss   uuid[];
  v_fora  jsonb;
  v_apr   jsonb;
  v_numos text[];
  v_voce  boolean;
  v_perg  jsonb;
  v_perr  text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aviso_pecas: sem o dia ou a hora' using errcode = '22023';
  end if;
  if not public._agenda_aviso_ligado() then
    return jsonb_build_object('avisar', false,
      'motivo', case when cf.modo_proposta = 'ligado' and cf.modo_vigia = 'ligado' then 'desligado' else 'modo' end);
  end if;
  v_m := public._agenda_aviso_mudancas(p_hoje);
  v_n := jsonb_array_length(v_m);
  if v_n = 0 then
    return jsonb_build_object('avisar', false, 'motivo', 'nada_mudou');
  end if;
  v_jan := public._agenda_aviso_fora_da_janela(p_agora, p_agora);
  if v_jan is not null then
    return jsonb_build_object('avisar', false, 'motivo', 'fora_da_janela', 'janela', v_jan, 'pendentes', v_n);
  end if;
  if public._agenda_aviso_no_dia((p_agora at time zone 'America/Sao_Paulo')::date, null) >= cf.gestor_aviso_dia_max then
    return jsonb_build_object('avisar', false, 'motivo', 'teto', 'pendentes', v_n);
  end if;
  if not exists (select 1 from public._agenda_aviso_dono()) then
    return jsonb_build_object('avisar', false, 'motivo', 'sem_dono', 'pendentes', v_n);
  end if;

  -- o que ficou de fora: o fora das propostas das mudanças (a de cada OS pela proposta mais nova), sem as OS que mudaram
  v_props := array(select distinct x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'propostas') x);
  v_oss := array(select distinct x::uuid from jsonb_array_elements(v_m) g, jsonb_array_elements_text(g -> 'os') x);
  select coalesce(jsonb_agg(y.f order by y.ord, y.o), '[]'::jsonb) into v_fora
    from (select distinct on (coalesce(t.f ->> 'os', t.f ->> 'numero')) t.f, t.o, t.ord
            from (select f, o, dense_rank() over (order by p.criada_em desc, p.id) as ord
                    from public.agenda_propostas p
                    cross join lateral jsonb_array_elements(p.fora) with ordinality u(f, o)
                   where p.id = any (v_props)) t
           order by coalesce(t.f ->> 'os', t.f ->> 'numero'), t.ord, t.o) y;

  -- as perguntas que destravam: a rodada de aprontar, uma vez por dia. Se ela falhar, o que mudou sai do mesmo jeito e o erro
  -- volta em perguntas_erro (o passo do motor o registra em app_error_logs: nunca calado)
  if not exists (select 1 from public.agenda_dono_avisos v
                  where v.dia = p_hoje and v.com_perguntas and v.fila_id is not null and v.devolvida_em is null) then
    begin
      v_apr := public.agenda_aprontar(p_hoje);
    exception when others then
      v_perr := left(sqlstate || ': ' || sqlerrm, 300);
      v_apr := null;
    end;
    v_numos := array(select jsonb_array_elements_text(coalesce(v_apr #> '{dados,oss}', '[]'::jsonb)));
    v_voce := coalesce((v_apr #>> '{dados,voce}')::boolean, false);
    if coalesce((v_apr ->> 'ok')::boolean, false) and (cardinality(v_numos) > 0 or v_voce) then
      v_perg := jsonb_build_object(
        'texto', v_apr ->> 'texto', 'oss', to_jsonb(v_numos), 'voce', v_voce,
        'pergunta_ids', to_jsonb(array(
          select q.id from public.agenda_perguntas q
            left join public.service_orders so on so.id = q.service_order_id
           where q.estado = 'aberta' and q.modo = 'ligado'
             and ((q.tipo in ('material_conferir', 'duracao', 'chegou') and so.service_order_number = any (v_numos))
                  or (q.tipo = 'padrao_do_dono' and v_voce))
           order by q.criada_em, q.id)));
    end if;
  end if;

  return jsonb_build_object(
    'avisar', true, 'rodada', p_agora, 'dia', p_hoje, 'limite', cf.gestor_aviso_texto_max,
    'cabecalho', 'Agenda — o que eu mudei sozinho:',
    'mudancas', (select jsonb_agg(jsonb_build_object('texto', g ->> 'texto', 'acao_ids', g -> 'acao_ids') order by o)
                   from jsonb_array_elements(v_m) with ordinality t(g, o)),
    'fora', public._agenda_aviso_fora_texto(v_fora, v_oss),
    'rodape', '*agenda plano* mostra tudo.',
    'perguntas', v_perg, 'perguntas_erro', v_perr);
end;
$function$;

comment on function public.agenda_aviso_pecas(date, timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): as peças do aviso do gestor ao dono, sem gravar nada (o texto é montado em _shared/agenda/aviso-do-gestor.ts). Não avisa (avisar false + motivo): modo, desligado (gestor_aviso_dia_max 0), nada_mudou, fora_da_janela (+ pendentes: sai junto na abertura), teto (+ pendentes), sem_dono. Avisa: {rodada, dia, limite (gestor_aviso_texto_max), cabecalho, mudancas [{texto do *o que mudou*, acao_ids}] (_agenda_aviso_mudancas), fora (_agenda_aviso_fora_texto, pelas propostas das mudanças), rodape, perguntas {texto de agenda_aprontar, pergunta_ids que ele cobre, oss, voce} — uma vez por dia — ou null, perguntas_erro (a rodada de aprontar falhou: o que mudou sai do mesmo jeito; o passo do motor registra o erro)}. STABLE, definer, só o service_role.';

-- A 1ª trava: confere de novo (sob a trava, contra dois tiques ao mesmo tempo) o modo, a rodada, a janela, o teto, o dono e
-- que as mudanças ainda estão por contar; registra o aviso e o põe na fila; as ações ficam contadas (contada_via aviso) desde
-- já — o fechamento e o aviso seguinte não as repetem; se a mensagem não sair, agenda_aviso_conferir as devolve.
-- {enfileirou, motivo?, id?, fila_id?, tentativas?, acoes?, perguntas?}. Não avisa (sem gravar nada): modo, ja_existe (a
-- mesma rodada), fora_da_janela, teto, sem_dono, mudou (alguma das ações já foi contada, desfeita ou não é mais do aviso).
create or replace function public.agenda_aviso_enfileirar(p_texto text, p_acao_ids uuid[], p_pergunta_ids uuid[],
                                                          p_com_perguntas boolean, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_jan   text;
  v_fone  text;
  v_pend  uuid[];
  v_chave text;
  v_id    uuid;
  v_fila  uuid;
  v_tent  int;
  v_det   text;
  v_n     int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_aviso_enfileirar: sem o dia ou a hora' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_texto, '')), '') is null or char_length(p_texto) > cf.gestor_aviso_texto_max then
    raise exception 'O aviso veio sem texto ou maior que gestor_aviso_texto_max (% letras).', cf.gestor_aviso_texto_max
      using errcode = '22023';
  end if;
  if coalesce(cardinality(p_acao_ids), 0) = 0 then
    raise exception 'O aviso conta pelo menos uma mudança.' using errcode = '22023';
  end if;
  -- o teto é contado e a linha entra numa vez só, mesmo com dois tiques do motor ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext('agenda_dono_aviso'));
  if not public._agenda_aviso_ligado() then
    return jsonb_build_object('enfileirou', false, 'motivo', 'modo');
  end if;
  select v.id into v_id from public.agenda_dono_avisos v where v.rodada = p_agora;
  if v_id is not null then
    return jsonb_build_object('enfileirou', false, 'motivo', 'ja_existe', 'id', v_id);
  end if;
  v_jan := public._agenda_aviso_fora_da_janela(p_agora, p_agora);
  if v_jan is not null then
    return jsonb_build_object('enfileirou', false, 'motivo', 'fora_da_janela', 'janela', v_jan);
  end if;
  if public._agenda_aviso_no_dia((p_agora at time zone 'America/Sao_Paulo')::date, null) >= cf.gestor_aviso_dia_max then
    return jsonb_build_object('enfileirou', false, 'motivo', 'teto');
  end if;
  select d.phone into v_fone from public._agenda_aviso_dono() d;
  if v_fone is null then
    return jsonb_build_object('enfileirou', false, 'motivo', 'sem_dono');
  end if;
  -- as mudanças do aviso ainda estão por contar (o fechamento ou outro aviso pode ter contado no meio)
  v_pend := array(select x::uuid from jsonb_array_elements(public._agenda_aviso_mudancas(p_hoje)) g,
                                      jsonb_array_elements_text(g -> 'acao_ids') x);
  if not (p_acao_ids <@ v_pend) then
    return jsonb_build_object('enfileirou', false, 'motivo', 'mudou');
  end if;

  v_chave := 'agenda-dono:aviso:' || to_char(p_agora at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"."US');
  insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, com_perguntas, telefone, enviar_em,
                                         dedupe_key, criada_em)
  values (p_agora, p_hoje, p_texto, p_acao_ids, coalesce(p_pergunta_ids, '{}'::uuid[]), coalesce(p_com_perguntas, false),
          v_fone, p_agora, v_chave, p_agora)
  returning id into v_id;
  -- as tentativas (+5 min) que cabem na janela (a regra única; a 1ª já cabe)
  v_tent := greatest(1, (select count(*)::int from generate_series(0, 2) k
                          where public._agenda_aviso_fora_da_janela(p_agora, p_agora + make_interval(mins => 5 * k)) is null));
  -- a trava da fila (o gatilho) recusa com 23514 o que passaria da janela ou do teto: aqui isso vira a recusa do aviso, e as
  -- mudanças continuam por contar
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for,
                                            max_attempts, dedupe_key)
    values (v_fone, p_texto, 'agenda-dono', v_id, 1, p_agora, v_tent, v_chave)
    returning id into v_fila;
  exception when sqlstate '23514' then
    get stacked diagnostics v_det = pg_exception_detail;
    update public.agenda_dono_avisos
       set estado = 'recusada', recusa_motivo = case when v_det in ('janela', 'domingo', 'modo', 'teto') then v_det else 'janela' end,
           devolvida_em = p_agora
     where id = v_id;
    return jsonb_build_object('enfileirou', false, 'motivo', 'recusada', 'id', v_id, 'pela_fila', coalesce(v_det, '?'));
  end;
  if v_fila is null then
    -- a mesma chave já estava na fila (o gatilho de idempotência de produção devolve nada): é a mesma rodada
    select q.id into v_fila from public.whatsapp_send_queue q where q.dedupe_key = v_chave;
  end if;
  update public.agenda_dono_avisos set estado = 'enfileirada', fila_id = v_fila where id = v_id;
  update public.agenda_acoes a set contada_em = p_agora, contada_via = 'aviso'
   where a.id = any (p_acao_ids) and a.contada_em is null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('enfileirou', true, 'id', v_id, 'fila_id', v_fila, 'tentativas', v_tent, 'acoes', v_n,
                            'perguntas', coalesce(cardinality(p_pergunta_ids), 0));
end;
$function$;

comment on function public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): a 1ª trava do aviso do gestor — sob a trava, de novo: o modo (_agenda_aviso_ligado), a rodada (uma por rodada: ja_existe), a janela (_agenda_aviso_fora_da_janela: fora_da_janela), o teto (_agenda_aviso_no_dia ≥ gestor_aviso_dia_max: teto), o dono (_agenda_aviso_dono: sem_dono) e as ações ainda por contar (_agenda_aviso_mudancas: mudou) — nesses casos nada é gravado. Senão registra em agenda_dono_avisos, põe na fila (source agenda-dono, source_ref_id = o aviso, a chave agenda-dono:aviso:<rodada>, priority 1, às p_agora, as tentativas que cabem na janela) e conta as ações (contada_em p_agora, contada_via aviso: provisório até o conferir). O 23514 da trava da fila vira o aviso recusado e devolvido. Texto vazio, maior que gestor_aviso_texto_max ou sem ação = 22023. Definer, só o service_role.';

-- O que a fila fez com os avisos: o que saiu passa a contar de verdade; o que não sai mais volta a "por contar".
-- {enviados, recusados, devolvidas (as ações que voltaram)}.
create or replace function public.agenda_aviso_conferir(p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  r       record;
  v_lig   boolean;
  v_mot   text;
  v_saiu  timestamptz;
  v_env   int := 0;
  v_rec   int := 0;
  v_dev   int := 0;
  v_n     int;
begin
  if p_agora is null then
    raise exception 'agenda_aviso_conferir: sem a hora' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('agenda_dono_aviso'));
  v_lig := public._agenda_aviso_ligado();

  -- (1) a fila velha: a linha que ainda espera e não sai mais (a janela dela passou, é domingo, ou o aviso desligou) falha,
  -- e o aviso fica recusado com o motivo
  for r in select q.id as fila_id, q.scheduled_for, v.id
             from public.agenda_dono_avisos v
             join public.whatsapp_send_queue q on q.id = v.fila_id
            where v.estado = 'enfileirada' and q.source = 'agenda-dono' and q.status = 'pending' and q.scheduled_for <= p_agora
            order by v.criada_em, v.id loop
    v_mot := case when not v_lig then 'modo' else public._agenda_aviso_fora_da_janela(r.scheduled_for, p_agora) end;
    continue when v_mot is null;
    update public.whatsapp_send_queue
       set status = 'failed', processing_started_at = null,
           failed_reason = 'agenda-dono: ' || case v_mot when 'modo' then 'o aviso do gestor saiu de ligado'
                                                         when 'domingo' then 'domingo, não sai'
                                                         else 'não saiu dentro da janela' end
     where id = r.fila_id;
    update public.agenda_dono_avisos set estado = 'recusada', recusa_motivo = v_mot where id = r.id and estado = 'enfileirada';
  end loop;

  -- (2) o que a fila mandou: a ação conta na hora em que saiu, o prazo do *desfaz* começa ali (nunca menos do que já era) e a
  -- pergunta conta como mostrada; o que a fila desistiu (ou a linha sumiu) fica recusado
  for r in select v.*, q.status as fila_status, q.sent_at
             from public.agenda_dono_avisos v
             left join public.whatsapp_send_queue q on q.id = v.fila_id
            where v.estado = 'enfileirada'
            order by v.criada_em, v.id loop
    if r.fila_status = 'sent' then
      v_saiu := coalesce(r.sent_at, p_agora);
      update public.agenda_acoes a
         set contada_em = v_saiu,
             desfazivel_ate = case when a.desfazivel_ate is not null and a.desfeita_em is null
                                   then greatest(a.desfazivel_ate, v_saiu + cf.desfazer_validade) else a.desfazivel_ate end
       where a.id = any (r.acao_ids) and a.contada_via = 'aviso';
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = v_saiu, mostrada_via = 'aviso'
       where q.id = any (r.pergunta_ids) and q.estado = 'aberta';
      update public.agenda_dono_avisos set estado = 'enviada', enviada_em = v_saiu where id = r.id;
      v_env := v_env + 1;
    elsif r.fila_status is null or r.fila_status = 'failed' then
      update public.agenda_dono_avisos set estado = 'recusada', recusa_motivo = 'fila' where id = r.id;
    end if;
  end loop;

  -- (3) o que não saiu (recusado aqui, pelo worker na hora de mandar ou pela trava): as ações voltam a "por contar" — só as
  -- que este aviso marcou (a mesma hora) — e vão no próximo aviso ou no fechamento
  for r in select v.* from public.agenda_dono_avisos v
            where v.estado = 'recusada' and v.devolvida_em is null
            order by v.criada_em, v.id loop
    update public.agenda_acoes a set contada_em = null, contada_via = null
     where a.id = any (r.acao_ids) and a.contada_via = 'aviso' and a.contada_em = r.enviar_em;
    get diagnostics v_n = row_count;
    update public.agenda_dono_avisos set devolvida_em = p_agora where id = r.id;
    v_rec := v_rec + 1;
    v_dev := v_dev + v_n;
  end loop;

  return jsonb_build_object('enviados', v_env, 'recusados', v_rec, 'devolvidas', v_dev);
end;
$function$;

comment on function public.agenda_aviso_conferir(timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): o que a fila fez com os avisos do gestor. (1) A linha agenda-dono pendente que não sai mais (a janela dela passou, domingo, ou o aviso desligado) vira falha e o aviso fica recusado (janela, domingo, modo). (2) A que saiu (sent): as ações contadas na hora do envio (sent_at), o desfazivel_ate de cada uma = o maior entre o de antes e sent_at + desfazer_validade (o prazo do *desfaz* a partir de quando o dono soube), as perguntas abertas mostradas (+1, mostrada_em, mostrada_via aviso), o aviso enviado; a que a fila desistiu (ou sumiu) = recusada/fila. (3) O aviso recusado (aqui, pelo worker ou pela trava) devolve as ações que marcou (contada_* nulos) uma vez (devolvida_em). {enviados, recusados, devolvidas}. Definer, só o service_role.';

-- ── 6. A 2ª trava: o gatilho da fila, só para source agenda-dono ───────────────────────────────────────────────────
-- Nada com source agenda-dono entra na fila sem o aviso registrado (com a chave, o texto e o telefone dele, que é o do dono),
-- fora da janela (nenhuma tentativa depois do fim), no domingo ou acima do teto; e a linha que entrou não muda de texto,
-- telefone, origem nem chave. É o que garante que um caminho novo (ou um defeito) não manda ao dono uma mensagem livre ou de
-- madrugada.
create or replace function public._agenda_fila_do_dono()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v      public.agenda_dono_avisos%rowtype;
  v_fone text;
  v_fora text;
begin
  if tg_op = 'UPDATE' then
    if old.source is distinct from new.source or old.message is distinct from new.message
       or old.phone_normalized is distinct from new.phone_normalized or old.source_ref_id is distinct from new.source_ref_id
       or old.dedupe_key is distinct from new.dedupe_key then
      raise exception 'A linha da fila do aviso do gestor não muda de texto, telefone, origem nem chave.' using errcode = '42501';
    end if;
    -- a nova tentativa que o worker marca (+5 min) fora da janela do aviso (ou com o aviso desligado) não sai: falha, e a
    -- hora volta à de antes (a linha não fica marcada fora da janela)
    if new.status = 'pending' and new.scheduled_for is distinct from old.scheduled_for then
      select x.* into v from public.agenda_dono_avisos x where x.id = new.source_ref_id;
      if not found or not public._agenda_aviso_ligado()
         or public._agenda_aviso_fora_da_janela(v.enviar_em, new.scheduled_for) is not null then
        new.status := 'failed';
        new.failed_reason := 'agenda-dono: a nova tentativa passaria do fim da janela';
        new.scheduled_for := old.scheduled_for;
      end if;
    end if;
    return new;
  end if;
  select x.* into v from public.agenda_dono_avisos x where x.id = new.source_ref_id;
  if not found or not public._agenda_aviso_ligado() then
    raise exception 'A fila do aviso do gestor só aceita o aviso registrado pela agenda, com o aviso ligado.' using errcode = '42501';
  end if;
  if v.estado <> 'registrada' then
    raise exception 'A fila do aviso do gestor só aceita o aviso que a agenda acabou de decidir mandar (este está %).', v.estado
      using errcode = '42501';
  end if;
  if new.dedupe_key is distinct from v.dedupe_key or new.message is distinct from v.texto then
    raise exception 'A fila do aviso do gestor só aceita o texto registrado, com a chave dele (nunca mensagem livre).'
      using errcode = '42501';
  end if;
  select d.phone into v_fone from public._agenda_aviso_dono() d;
  if v_fone is null or new.phone_normalized is distinct from v_fone or new.phone_normalized is distinct from v.telefone then
    raise exception 'A fila do aviso do gestor só aceita o telefone do dono.' using errcode = '42501';
  end if;
  -- cada tentativa (+5 min) dentro da janela do aviso, pela regra única; o motivo vai no detail (quem enfileira recusa o
  -- aviso com ele)
  select t.f into v_fora
    from (select public._agenda_aviso_fora_da_janela(v.enviar_em, new.scheduled_for + make_interval(mins => 5 * k)) as f
            from generate_series(0, greatest(coalesce(new.max_attempts, 3) - 1, 0)) k) t
   where t.f is not null
   limit 1;
  if v_fora is not null then
    raise exception 'Aviso do gestor fora da janela (% às %, de segunda a sábado): %.',
      to_char(cf.gestor_aviso_inicio, 'HH24:MI'), to_char(cf.gestor_aviso_fim, 'HH24:MI'),
      to_char(new.scheduled_for at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
      using errcode = '23514', detail = v_fora;
  end if;
  if public._agenda_aviso_no_dia((v.enviar_em at time zone 'America/Sao_Paulo')::date, v.id) >= cf.gestor_aviso_dia_max then
    raise exception 'Teto de avisos do gestor (% por dia): não entra mais nenhum hoje.', cf.gestor_aviso_dia_max
      using errcode = '23514', detail = 'teto';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_fila_do_dono() is
  'Agenda de Produção (correção de 29/10, P4): a 2ª trava — gatilho de whatsapp_send_queue só para source agenda-dono. INSERT: recusa (42501) a linha sem o aviso registrado em agenda_dono_avisos (estado registrada) ou com o aviso desligado, com chave ou texto diferentes dos dele, ou com telefone que não é o do dono (_agenda_aviso_dono, e o gravado no aviso); recusa (23514, o motivo no detail) a linha com alguma tentativa fora da janela (_agenda_aviso_fora_da_janela: janela, domingo) ou acima do teto (_agenda_aviso_no_dia). UPDATE: a linha não muda de texto, telefone, origem, ref nem chave (42501); a nova tentativa pendente que cairia fora da janela (ou com o aviso desligado) vira failed e volta à hora de antes.';

drop trigger if exists trg_agenda_fila_do_dono on public.whatsapp_send_queue;
create trigger trg_agenda_fila_do_dono before insert on public.whatsapp_send_queue
  for each row when (new.source = 'agenda-dono') execute function public._agenda_fila_do_dono();
drop trigger if exists trg_agenda_fila_do_dono_linha on public.whatsapp_send_queue;
create trigger trg_agenda_fila_do_dono_linha
  before update of scheduled_for, message, phone_normalized, source, source_ref_id, dedupe_key on public.whatsapp_send_queue
  for each row when (old.source = 'agenda-dono' or new.source = 'agenda-dono')
  execute function public._agenda_fila_do_dono();

-- ── 7. A função recriada (o corpo da definição mais nova; a mudança marcada "-- CORREÇÃO 29/10 (P4):") ─────────────────
-- Fora do bloco nenhuma linha muda (o K de supabase/tests/agenda_correcao_2910_p4.sql confere). Quem recriar de novo copia
-- DESTA migration.

-- _agenda_acoes_so_desfaz (de 20261026100000_agenda_fase3_tabelas.sql)
create or replace function public._agenda_acoes_so_desfaz()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- CORREÇÃO 29/10 (P4): o prazo do *desfaz* conta de quando o dono soube. A ação contada pelo aviso do gestor (contada_via
  -- aviso, antes e depois: o agenda_aviso_conferir confirmando a hora em que a mensagem saiu) pode ter o desfazivel_ate
  -- ADIANTADO — nunca atrasado, nunca tirado, nunca na desfeita — junto com o contada_em; nada mais muda.
  if old.desfeita_em is null and old.desfazivel_ate is not null and new.desfazivel_ate is not null
     and new.desfazivel_ate > old.desfazivel_ate
     and old.contada_via = 'aviso' and new.contada_via = 'aviso' then
    if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new), array['contada_em', 'contada_via', 'desfazivel_ate'],
             array['service_order_id', 'proposta_id', 'autor', 'desfeita_por', 'payee_id', 'work_shift_id']) then
      raise exception 'A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.';
    end if;
    return new;
  end if;
  -- CORREÇÃO 29/10 (P4): fim
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           case when old.desfeita_em is null
                then array['desfeita_em', 'desfeita_por', 'desfeita_pela', 'contada_em', 'contada_via']
                else array['contada_em', 'contada_via'] end,
           -- FASE 3: payee_id e work_shift_id são ON DELETE SET NULL (apagar a diária no Financeiro deixa a ação com a
           -- diária nula; o registro fica).
           array['service_order_id', 'proposta_id', 'autor', 'desfeita_por', 'payee_id', 'work_shift_id']) then
    raise exception 'A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_acoes_so_desfaz() is 'Agenda de Produção (Fase 2; Fase 3: payee_id e work_shift_id podem virar nulos pelo ON DELETE SET NULL): gatilho BEFORE UPDATE — só desfeita_* (uma vez) e contada_* mudam. CORREÇÃO 29/10 (P4): a ação contada pelo aviso do gestor (contada_via aviso antes e depois) pode ter o desfazivel_ate adiantado junto com o contada_em (o prazo do *desfaz* a partir de quando o dono soube); nunca atrasado nem na desfeita.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- As três RPCs do aviso: só o service_role (o task-automations).
revoke all on function
  public.agenda_aviso_pecas(date, timestamptz),
  public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz),
  public.agenda_aviso_conferir(timestamptz)
  from public, anon, authenticated;
grant execute on function
  public.agenda_aviso_pecas(date, timestamptz),
  public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz),
  public.agenda_aviso_conferir(timestamptz)
  to service_role;

-- As peças de dentro: ninguém de fora (só as funções security definer acima e o gatilho da fila as chamam).
revoke all on function
  public._agenda_aviso_dono(), public._agenda_aviso_ligado(), public._agenda_aviso_fora_da_janela(timestamptz, timestamptz),
  public._agenda_aviso_no_dia(date, uuid), public._agenda_aviso_mudancas(date), public._agenda_aviso_fora_texto(jsonb, uuid[])
  from public, anon, authenticated, service_role;

-- Funções de gatilho: sem grant a ninguém.
revoke all on function public._agenda_fila_do_dono(), public._agenda_dono_avisos_so_muda(), public._agenda_acoes_so_desfaz()
  from public, anon, authenticated;
