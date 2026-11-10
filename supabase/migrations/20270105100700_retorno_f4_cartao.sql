-- Retorno rápido ao cliente, F4 (P8): o cartão do parceiro.
-- Gerada por script (scripts/gerar_f4.cjs cartao): as tabelas e as funções novas vêm de scripts/f4_sql/p8_cartao.sql,
-- escritas à mão; retorno_dito é gerada do corpo vigente (20261123100100_retorno_f2_palavras.sql), e só os trechos marcados -- F4 são novos.
--
-- 1. parceiro_cartoes e parceiro_cartao_itens (RLS, leitura só de admin e financeiro, escrita só do service_role). Um cartão
--    vivo só; até 3 itens, cada um de uma linha de parceiro_fila (o corte vem de *parceiro 74*).
-- 2. Auxiliares: o rótulo do número, o papel e o sinal como o dono lê, a fila depois do cartão (_parceiro_fila_marcar e
--    _parceiro_fila_tirar, a tabela de caminhos de P8.1) e a impressão do item (o hash do *sim <PIN>*).
-- 3. _parceiro_cartao_texto, _parceiro_cartao_encerrar, _parceiro_cartao_fechar_se_vazio e parceiro_cartao_vivo (o caminho
--    preguiçoso da F2).
-- 4. A fila: _parceiro_fila_conferir, _parceiro_cartao_candidatos (prioridade, vezes, ultimo_em) e as letras da pergunta
--    (_parceiro_pergunta_opcoes: os proposto do parceiro e os pares do lote ainda sem linha, até 4).
-- 5. _parceiro_item_montar (a tabela "Item a item"; o item pedido é de parceiro_pedido_montar, P10) e _parceiro_item_corte.
-- 6. parceiro_cartao_abrir (*parceiro*: o lote, a fila e a pendência parceiro_executar_cartao) e parceiro_cartao_abrir_os
--    (*parceiro 74*, em qualquer modo). Só o dono abre: nenhum cron cria cartão.
-- 7. parceiro_decidir_dito (escolher, so, sem, tirar, ver, resolvido, tira_linha e sabe, sem PIN) e _parceiro_dito_resolvido.
-- 8. O *sim <PIN>*: _parceiro_item_conferir, _parceiro_item_executar e parceiro_cartao_executar (o pedido da P10 mora aqui,
--    porque só as cinco funções da máquina de estados escrevem em parceiro_pedidos.estado), parceiro_item_enviado e
--    parceiro_vigia_cartao (no parceiro_vigia, em qualquer modo).
-- 9. retorno_dito (gerada): *segura pátio* e *solta pátio* gravam retorno_config.segura_patio.
--
-- O texto do cartão pode ter trecho do parceiro: fica em parceiro_cartoes e parceiro_cartao_itens e volta na resposta da
-- RPC; ai_operator_messages só recebe o número de itens. A F4 não acrescenta palavra a retorno_toques: o toque do cartão do
-- parceiro conta em parceiro_cartao_itens.decidido_em.
--
-- Sem dado. Com parceiro_modo = 'desligado' (o padrão), *parceiro* devolve vazio sem tocar em nada; *parceiro 74* e o vigia
-- do cartão valem em qualquer modo, mas nada abre sem o dono.
-- Reverter: reaplicar retorno_dito de 20261123100100_retorno_f2_palavras.sql; update ai_operator_pending_actions set status = 'rejected' where
-- action_name = 'parceiro_executar_cartao' and status = 'pending'; drop das funções desta migration. As tabelas ficam.

-- ── 1. As tabelas do cartão do parceiro ─────────────────────────────────────────────────────────────────────────────────

create table public.parceiro_cartoes (
  id uuid primary key default gen_random_uuid(),
  gatilho text not null check (gatilho in ('puxar', 'os')),   -- só o dono abre (*parceiro* ou *parceiro 74*); o fechamento pede, não abre (P11.2)
  dia date not null,
  estado text not null check (estado in ('lista', 'vivo', 'decidido', 'caiu', 'expirou', 'falhou')),
  sessao_id uuid references public.ai_operator_sessions(id) on delete set null,
  pendencia_id uuid unique,
  pergunta_id uuid,
  hash text not null,
  texto text not null check (char_length(texto) <= 3500),   -- pode ter trecho do parceiro. Nunca vai a ai_operator_messages
  mais smallint not null default 0,
  criado_em timestamptz not null default now(),
  enviado_em timestamptz,
  expira_em timestamptz not null,
  decidido_em timestamptz,
  decidido_por text check (decidido_por in ('sim_pin', 'nao', 'painel')),
  caiu_motivo text check (caiu_motivo in ('cartao_expirou', 'cartao_caiu')),   -- gravado por _parceiro_cartao_encerrar
  dados jsonb not null default '{}' check (jsonb_typeof(dados) = 'object')
);
create unique index parceiro_cartoes_um_vivo on public.parceiro_cartoes ((true)) where estado = 'vivo';

comment on table public.parceiro_cartoes is
  'Retorno F4 (P8): o cartão do parceiro, no molde do cartão da F2 (mesma pendência, ponteiro, pergunta e *sim <PIN>*). Um vivo só. Abre só com *parceiro* ou *parceiro 74* do dono.';

create table public.parceiro_cartao_itens (
  id uuid primary key default gen_random_uuid(),
  cartao_id uuid not null references public.parceiro_cartoes(id) on delete cascade,
  n smallint not null check (n between 1 and 3),
  tipo text not null check (tipo in ('vinculo', 'painel', 'patio', 'pergunta', 'pedido', 'repassar', 'pdf_mao', 'aviso', 'retido', 'corte')),
  interessado_id uuid references public.os_interessados(id) on delete set null,
  painel_id uuid references public.parceiro_paineis(id) on delete set null,
  abertura_id uuid references public.retorno_aberturas(id) on delete set null,
  service_order_id uuid references public.service_orders(id) on delete set null,
  envio_mao_id uuid,                     -- parceiro_envios_a_mao.id (P9)
  pedido_id uuid references public.parceiro_pedidos(id) on delete set null,   -- P10
  numero_id uuid references public.parceiro_numeros(id) on delete set null,   -- item `patio`
  fila_id uuid references public.parceiro_fila(id) on delete set null,        -- de onde o item veio; `corte` não tem
  texto_mostrado text,
  opcoes jsonb not null default '[]' check (jsonb_typeof(opcoes) = 'array'),   -- [{"letra", "rotulo", "acao"}]
  retrato jsonb not null default '{}' check (jsonb_typeof(retrato) = 'object'),
  hash text not null,
  estado text not null default 'vivo' check (estado in ('vivo', 'fora', 'feito', 'caiu')),
  selecionado boolean not null default true,
  escolha text,
  decidido_em timestamptz,
  -- os seis da spec e, para o orçamento do item pedido (P10), os motivos de recusa da F3 que o preparo do parceiro herda
  caiu_motivo text check (caiu_motivo in ('respondida_pelo_dono', 'veto', 'sem_vinculo', 'fato_mudou', 'parceiro_inativo', 'caso_fechado',
                                          'orc_existe', 'item_provisorio', 'sem_cadastro', 'cliente_final', 'rascunho_sem_valor',
                                          'canal_bloqueado')),
  saida_id uuid references public.retorno_saidas(id) on delete set null,
  unique (cartao_id, n)
);
create index parceiro_cartao_itens_por_fila on public.parceiro_cartao_itens (fila_id) where fila_id is not null;

comment on table public.parceiro_cartao_itens is
  'Retorno F4 (P8): os itens do cartão do parceiro (até 3), cada um vindo de uma linha de parceiro_fila (o corte vem de *parceiro 74*). texto_mostrado e retrato podem ter trecho do parceiro: só o dono lê.';

do $rls$
declare
  v_t text;
begin
  foreach v_t in array array['parceiro_cartoes', 'parceiro_cartao_itens'] loop
    execute format('alter table public.%I enable row level security', v_t);
    execute format('drop policy if exists %I on public.%I', v_t || '_leitura', v_t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_admin_or_financial((select auth.uid())))',
                   v_t || '_leitura', v_t);
    execute format('revoke all on table public.%I from public, anon, authenticated', v_t);
    execute format('grant select on table public.%I to authenticated', v_t);
    execute format('grant all on table public.%I to service_role', v_t);
  end loop;
end
$rls$;

-- ── 2. Auxiliares de texto, fila e conferência ─────────────────────────────────────────────────────────────────────────

-- "MP (Carla)" ou "MP (comercial)" pelo número; nunca o número nem dígito.
create or replace function public._parceiro_rotulo_do_numero(p_numero uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select format('%s (%s)', pa.sigla,
                                 coalesce(nullif(btrim(left(regexp_replace(coalesce(pe.nome, ''), '[0-9]+', '', 'g'), 40)), ''), 'comercial'))
                     from public.parceiro_numeros n
                     join public.parceiro_pessoas pe on pe.id = n.pessoa_id
                     join public.parceiros pa on pa.id = pe.parceiro_id
                    where n.id = p_numero), 'parceiro');
$$;

revoke all on function public._parceiro_rotulo_do_numero(uuid) from public, anon, authenticated;

-- O papel e o sinal como o dono lê no cartão ("ela" é a parceira).
create or replace function public._parceiro_papel_texto(p_papel text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_papel
    when 'indicou' then 'ela indicou'
    when 'contratante' then 'ela contrata'
    when 'pagador' then 'ela paga'
    when 'anfitria' then 'só fica no pátio'
    else 'sem papel'
  end;
$$;

revoke all on function public._parceiro_papel_texto(text) from public, anon, authenticated;

create or replace function public._parceiro_sinal_texto(p_origem text, p_sigla text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_origem
    when 'numero_do_pedido' then format('o pedido veio pelo número da %s', p_sigla)
    when 'unidade_anterior' then format('unidade já acompanhada pela %s', p_sigla)
    when 'propria' then format('OS da própria %s', p_sigla)
    when 'carteira' then 'carteira de motorhome'
    when 'dono' then 'você pediu (*parceiro*)'
    else 'sem sinal'
  end;
$$;

revoke all on function public._parceiro_sinal_texto(text, text) from public, anon, authenticated;

-- "OS-00074 · Ducato": o número e o nome da unidade (só o dono lê o nome da unidade).
create or replace function public._parceiro_os_rotulo(p_os uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select format('%s · %s', so.service_order_number, coalesce(nullif(btrim(left(v.name, 40)), ''), 'sem unidade'))
                     from public.service_orders so
                     left join public.vessels v on v.id = so.vessel_id
                    where so.id = p_os), 'OS');
$$;

revoke all on function public._parceiro_os_rotulo(uuid) from public, anon, authenticated;

-- A linha da fila depois do cartão. p_estado 'espera' (com p_adiado opcional), 'caiu' ou 'feito'. Sem linha, nada.
create or replace function public._parceiro_fila_marcar(p_fila uuid, p_estado text, p_adiado timestamptz, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if p_fila is null then
    return;
  end if;
  if p_estado is null or p_estado not in ('espera', 'caiu', 'feito') then
    raise exception using errcode = '22023', message = '_parceiro_fila_marcar: estado fora da lista';
  end if;
  update public.parceiro_fila f
     set estado = p_estado,
         adiado_ate = case when p_estado = 'espera' then p_adiado else f.adiado_ate end,
         decidido_em = case when p_estado = 'espera' then null else coalesce(p_agora, now()) end
   where f.id = p_fila;
end;
$$;

revoke all on function public._parceiro_fila_marcar(uuid, text, timestamptz, timestamptz) from public, anon, authenticated;

-- *não N*, por tipo (tabela de caminhos de P8.1): vinculo volta com 14 dias; painel e patio caem (a validade é o dia);
-- pergunta volta sem adiar; o resto volta à 00:00 do dia seguinte. corte não tem fila.
create or replace function public._parceiro_fila_tirar(p_fila uuid, p_tipo text, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
begin
  if p_fila is null or p_tipo = 'corte' then
    return;
  end if;
  if p_tipo = 'vinculo' then
    perform public._parceiro_fila_marcar(p_fila, 'espera', v_agora + interval '14 days', v_agora);
  elsif p_tipo in ('painel', 'patio') then
    perform public._parceiro_fila_marcar(p_fila, 'caiu', null, v_agora);
  elsif p_tipo = 'pergunta' then
    perform public._parceiro_fila_marcar(p_fila, 'espera', null, v_agora);
  else
    perform public._parceiro_fila_marcar(p_fila, 'espera',
      (((v_agora at time zone c_fuso)::date + 1)::timestamp) at time zone c_fuso, v_agora);
  end if;
end;
$$;

revoke all on function public._parceiro_fila_tirar(uuid, text, timestamptz) from public, anon, authenticated;

-- A impressão do que o item afirma, para a conferência por hash no *sim <PIN>*. Uma consulta por tipo (cada uma só é
-- planejada quando o tipo chega: o item pedido lê tabelas da P10, o pdf_mao da P9).
create or replace function public._parceiro_item_impressao(p_tipo text, p_ref uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if p_tipo in ('vinculo', 'corte', 'retido', 'aviso') then
    select jsonb_build_object('s', oi.situacao, 'p', oi.papel, 'a', oi.aviso_ao_cliente, 'e', oi.aviso_em, 'i', oi.aviso_saida_id,
                              'v', oi.veto_do_cliente_em, 'r', oi.retido_em)
      into v from public.os_interessados oi where oi.id = p_ref;
  elsif p_tipo = 'painel' then
    select jsonb_build_object('e', pp.estado, 'd', pp.dia) into v from public.parceiro_paineis pp where pp.id = p_ref;
  elsif p_tipo = 'patio' then
    select jsonb_build_object('s', n.situacao) into v from public.parceiro_numeros n where n.id = p_ref;
  elsif p_tipo = 'pergunta' then
    select jsonb_build_object('e', a.estado = 'fechada', 'c', a.cumprida_em) into v from public.retorno_aberturas a where a.id = p_ref;
  elsif p_tipo = 'pedido' then
    select jsonb_build_object('e', pp.estado, 'c', pp.client_id, 'w', pp.whatsapp_informado, 'v', pp.vessel_id)
      into v from public.parceiro_pedidos pp where pp.id = p_ref;
  elsif p_tipo = 'pdf_mao' then
    select jsonb_build_object('s', e.situacao) into v from public.parceiro_envios_a_mao e where e.id = p_ref;
  elsif p_tipo = 'repassar' then
    select jsonb_build_object('t', public._parceiro_fone_do_cliente(so.client_id) is not null, 'c', so.client_id)
      into v from public.service_orders so where so.id = p_ref;
  end if;
  return md5(coalesce(p_tipo, '') || ':' || coalesce(v::text, 'nada'));
end;
$$;

revoke all on function public._parceiro_item_impressao(text, uuid, timestamptz) from public, anon, authenticated;

-- ── 3. O texto, o encerramento e o cartão vivo ─────────────────────────────────────────────────────────────────────────

create or replace function public._parceiro_cartao_texto(p_cartao uuid, p_cabeca text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_c public.parceiro_cartoes;
  v_vivos integer;
  v_primeiro smallint;
  v_corpo text;
  v_faz smallint[];
  v_rodape text;
  v_final text;
  v_lim integer;
begin
  select * into v_c from public.parceiro_cartoes c where c.id = p_cartao;
  select count(*), min(i.n) into v_vivos, v_primeiro
    from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';

  select string_agg(coalesce(i.texto_mostrado, format('%s. (item sem texto)', i.n))
                    || (case when i.escolha is not null then format(' → *%s %s*', i.n, i.escolha) else '' end),
                    E'\n' order by i.n)
    into v_corpo
    from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';

  if v_c.estado = 'vivo' then
    select array_agg(i.n order by i.n) into v_faz
      from public.parceiro_cartao_itens i
     where i.cartao_id = p_cartao and i.estado = 'vivo' and i.selecionado
       and (not coalesce((i.retrato ->> 'exige_letra')::boolean, false) or i.escolha is not null);
    if v_primeiro is null then
      v_rodape := 'Nada mais neste cartão. *parceiro* abre de novo.';
    elsif cardinality(v_faz) > 0 then
      v_rodape := format('*sim <PIN>* faz %s · *não N* tira · *ver %s* mostra',
                         case when cardinality(v_faz) = 1 then format('o %s', v_faz[1])
                              when cardinality(v_faz) = 2 then format('o %s e o %s', v_faz[1], v_faz[2])
                              else 'os 3' end, v_primeiro);
    else
      v_rodape := format('Escolha a letra (*%s C*) e mande *sim <PIN>* · *não N* tira · *ver %s* mostra', v_primeiro, v_primeiro);
    end if;
  else
    v_rodape := v_c.dados ->> 'rodape';
  end if;

  v_final := concat_ws(E'\n', coalesce(p_cabeca, format('Parceiro · %s esperando', coalesce(v_vivos, 0) + v_c.mais)), v_corpo,
                       case when v_c.mais > 0 then format('e mais %s: *parceiro*', v_c.mais) end, v_rodape);
  -- o CHECK é de 3.500: o item longo encolhe, e o resto fica no *ver N*
  if char_length(v_final) > 3500 then
    foreach v_lim in array array[900, 500, 200] loop
      select string_agg(case when char_length(coalesce(i.texto_mostrado, '')) > v_lim
                             then left(i.texto_mostrado, v_lim) || format('… *ver %s*', i.n)
                             else coalesce(i.texto_mostrado, '') end
                        || (case when i.escolha is not null then format(' → *%s %s*', i.n, i.escolha) else '' end),
                        E'\n' order by i.n)
        into v_corpo
        from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';
      v_final := concat_ws(E'\n', coalesce(p_cabeca, format('Parceiro · %s esperando', coalesce(v_vivos, 0) + v_c.mais)), v_corpo,
                           case when v_c.mais > 0 then format('e mais %s: *parceiro*', v_c.mais) end, v_rodape);
      exit when char_length(v_final) <= 3500;
    end loop;
  end if;
  return left(v_final, 3500);
end;
$$;

comment on function public._parceiro_cartao_texto(uuid, text) is
  'Retorno F4 (P8): o texto do cartão do parceiro: cabeçalho, os itens vivos com a letra escolhida, "e mais N" e o rodapé do que o *sim <PIN>* faz (item selecionado que não exige letra, ou com a letra). Nunca passa de 3.500 caracteres.';

revoke all on function public._parceiro_cartao_texto(uuid, text) from public, anon, authenticated;

-- O par de _retorno_cartao_encerrar (F2): estado e motivo; itens vivos a fora; a pendência pending com o status pedido; o
-- ponteiro da sessão, só se for o deste cartão; a pergunta; e a fila no_cartao deste cartão de volta a espera.
create or replace function public._parceiro_cartao_encerrar(p_cartao uuid, p_estado text, p_status_pendencia text, p_motivo text,
                                                            p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_c public.parceiro_cartoes;
begin
  select * into v_c from public.parceiro_cartoes c where c.id = p_cartao;
  if not found then
    return;
  end if;
  update public.parceiro_cartoes c set estado = p_estado, caiu_motivo = p_motivo where c.id = p_cartao;
  update public.parceiro_cartao_itens i set estado = 'fora' where i.cartao_id = p_cartao and i.estado = 'vivo';
  if v_c.pendencia_id is not null then
    update public.ai_operator_pending_actions p
       set status = p_status_pendencia,
           rejected_at = case when p_status_pendencia = 'rejected' then coalesce(p_agora, now()) else p.rejected_at end
     where p.id = v_c.pendencia_id and p.status = 'pending';
    update public.ai_operator_sessions s
       set metadata = s.metadata - 'pending_confirm_action_id'
     where s.id = v_c.sessao_id and s.metadata ->> 'pending_confirm_action_id' = v_c.pendencia_id::text;
  end if;
  if v_c.pergunta_id is not null then
    perform public._pergunta_fechar(v_c.pergunta_id, 'cancelada', coalesce(p_motivo, p_estado), null);
  end if;
  update public.parceiro_fila f
     set estado = 'espera', decidido_em = null
   where f.estado = 'no_cartao'
     and f.id in (select i.fila_id from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.fila_id is not null);
end;
$$;

comment on function public._parceiro_cartao_encerrar(uuid, text, text, text, timestamptz) is
  'Retorno F4 (P8): fecha o cartão do parceiro (estado e caiu_motivo), leva os itens vivos a fora, a pendência pending ao status pedido, tira o ponteiro só se for o deste cartão, fecha a pergunta (pergunta_ocupado falso) e devolve a espera a fila no_cartao deste cartão.';

revoke all on function public._parceiro_cartao_encerrar(uuid, text, text, text, timestamptz) from public, anon, authenticated;

-- O cartão vivo sem nenhum item vivo é decidido na hora (molde de _retorno_cartao_fechar_se_vazio). Devolve se fechou.
create or replace function public._parceiro_cartao_fechar_se_vazio(p_cartao uuid, p_agora timestamptz)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if p_cartao is null
     or not exists (select 1 from public.parceiro_cartoes c where c.id = p_cartao and c.estado = 'vivo')
     or exists (select 1 from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo') then
    return false;
  end if;
  perform public._parceiro_cartao_encerrar(p_cartao, 'decidido', 'rejected', null, p_agora);
  update public.parceiro_cartoes c
     set decidido_em = coalesce(c.decidido_em, p_agora), decidido_por = coalesce(c.decidido_por, 'nao')
   where c.id = p_cartao;
  return true;
end;
$$;

revoke all on function public._parceiro_cartao_fechar_se_vazio(uuid, timestamptz) from public, anon, authenticated;

-- C-VIVO do parceiro: o cartão vivo, ou nulo. Antes de responder, fecha o vivo cuja pendência acabou (rejected, expired,
-- executed, failed), e o que estava no_cartao sem ser executado volta a espera.
create or replace function public.parceiro_cartao_vivo(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_c public.parceiro_cartoes;
  v_status text;
  v_itens jsonb;
  v_letras jsonb;
begin
  select c.* into v_c from public.parceiro_cartoes c where c.estado = 'vivo' for update;
  if not found then
    return null;
  end if;
  if v_c.pendencia_id is not null then
    select p.status into v_status from public.ai_operator_pending_actions p where p.id = v_c.pendencia_id;
    if v_status in ('rejected', 'expired', 'executed', 'failed') then
      perform public._parceiro_cartao_encerrar(v_c.id, case when v_status = 'expired' then 'expirou' else 'decidido' end, v_status,
                                               case when v_status = 'expired' then 'cartao_expirou' end, v_agora);
      update public.parceiro_cartoes c
         set decidido_em = case when v_status = 'expired' then c.decidido_em else coalesce(c.decidido_em, v_agora) end,
             decidido_por = case when v_status = 'rejected' then coalesce(c.decidido_por, 'nao')
                                 when v_status = 'expired' then c.decidido_por
                                 else coalesce(c.decidido_por, 'sim_pin') end
       where c.id = v_c.id;
      return null;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('n', i.n, 'tipo', i.tipo, 'fila_id', i.fila_id) order by i.n), '[]'::jsonb),
         coalesce(jsonb_object_agg(i.n::text,
                    (select coalesce(jsonb_agg(o ->> 'letra'), '[]'::jsonb) from jsonb_array_elements(i.opcoes) o)), '{}'::jsonb)
    into v_itens, v_letras
    from public.parceiro_cartao_itens i
   where i.cartao_id = v_c.id and i.estado = 'vivo';

  return jsonb_build_object('id', v_c.id, 'estado', v_c.estado, 'pendencia_id', v_c.pendencia_id, 'itens', v_itens,
                            'letras', v_letras, 'expira_em', v_c.expira_em);
end;
$$;

comment on function public.parceiro_cartao_vivo(timestamptz) is
  'Retorno F4 (P8): o cartão vivo do parceiro {id, estado, pendencia_id, itens, letras, expira_em}, ou nulo. Fecha antes, de forma preguiçosa, o vivo cuja pendência acabou (rejected/executed/failed → decidido, expired → expirou), como retorno_cartao_vivo da F2.';

revoke all on function public.parceiro_cartao_vivo(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_cartao_vivo(timestamptz) to service_role;

-- ── 4. A fila: conferência, candidatos e as letras da pergunta ─────────────────────────────────────────────────────────

-- Tira da fila (caiu) o que venceu ou perdeu a origem. Só linhas em espera; no_cartao é do cartão vivo.
create or replace function public._parceiro_fila_conferir(p_agora timestamptz)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_n integer;
begin
  update public.parceiro_fila f
     set estado = 'caiu', decidido_em = v_agora
   where f.estado = 'espera'
     and ((f.valido_ate is not null and f.valido_ate <= v_agora)
          or (f.tipo = 'pergunta'
              and not exists (select 1 from public.retorno_aberturas a
                               where a.id = f.referencia and a.estado <> 'fechada' and a.cumprida_em is null))
          or (f.tipo = 'painel'
              and not exists (select 1 from public.parceiro_paineis pp where pp.id = f.referencia and pp.estado = 'aguardando'))
          or (f.tipo = 'pedido'
              and not exists (select 1 from public.parceiro_pedidos pp where pp.id = f.referencia and pp.estado = 'cartao'))
          or (f.tipo = 'retido'
              and not exists (select 1 from public.os_interessados oi where oi.id = f.referencia and oi.retido_em is not null))
          or (f.tipo = 'aviso' and nullif(f.dados ->> 'saida_id', '') is null
              and not exists (select 1 from public.os_interessados oi where oi.id = f.referencia and oi.aviso_em is null))
          or (f.tipo = 'aviso' and nullif(f.dados ->> 'saida_id', '') is not null
              and not exists (select 1 from public.os_interessados oi where oi.id = f.referencia and oi.aviso_saida_id is null))
          or (f.tipo = 'vinculo'
              and not exists (select 1 from public.os_interessados oi where oi.id = f.referencia and oi.situacao = 'proposto'))
          or (f.tipo = 'pdf_mao'
              and not exists (select 1 from public.parceiro_envios_a_mao e where e.id = f.referencia and e.situacao = 'perguntada'))
          or (f.tipo = 'repassar'
              and not exists (select 1 from public.os_interessados oi
                               where oi.id = nullif(f.dados ->> 'interessado_id', '')::uuid and oi.situacao = 'confirmado')));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

comment on function public._parceiro_fila_conferir(timestamptz) is
  'Retorno F4 (P8.1): marca caiu, entre as linhas em espera: vencidas; pergunta de caso fechado ou cumprido; painel fora de aguardando; pedido fora de cartao; retido sem retido_em; aviso sem saida_id com aviso_em, e com saida_id quando o vínculo ganhou aviso_saida_id; vinculo fora de proposto; pdf_mao fora de perguntada; repassar sem o vínculo confirmado. Devolve quantas.';

revoke all on function public._parceiro_fila_conferir(timestamptz) from public, anon, authenticated;

-- A ordem da fila: espera, sem adiado futuro, sem validade vencida, parceiro ativo, nunca do futuro; o vinculo só enquanto
-- proposto e com a OS na regra 8. prioridade, vezes, ultimo_em (nulo primeiro), criado_em, id. p_limite nulo = todas.
create or replace function public._parceiro_cartao_candidatos(p_agora timestamptz, p_limite integer)
returns table (fila_id uuid, tipo text, referencia uuid, prioridade smallint)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
begin
  return query
  select f.id, f.tipo, f.referencia, f.prioridade
    from public.parceiro_fila f
    join public.parceiros pa on pa.id = f.parceiro_id and pa.ativo
   where f.estado = 'espera'
     and f.criado_em <= v_agora
     and (f.adiado_ate is null or f.adiado_ate <= v_agora)
     and (f.valido_ate is null or f.valido_ate > v_agora)
     and (f.tipo <> 'vinculo'
          or exists (select 1 from public.os_interessados oi
                      where oi.id = f.referencia and oi.situacao = 'proposto'
                        and public._parceiro_os_viva(oi.service_order_id, oi.parceiro_id, v_agora)))
   order by f.prioridade, f.vezes, f.ultimo_em nulls first, f.criado_em, f.id
   limit p_limite;
end;
$$;

comment on function public._parceiro_cartao_candidatos(timestamptz, integer) is
  'Retorno F4 (P8.1): as linhas de parceiro_fila que podem ir ao cartão, na ordem prioridade, vezes, ultimo_em (nulo primeiro), criado_em, id. vinculo só enquanto proposto e com a OS na regra 8.';

revoke all on function public._parceiro_cartao_candidatos(timestamptz, integer) from public, anon, authenticated;

-- As letras da pergunta: os vínculos proposto do parceiro com a OS na regra 8 e os pares do lote ainda sem linha. Ordem
-- pelo sinal e pelo número decrescente; letra só nas 4 primeiras (A, B, C, D), e as outras vêm com letra nula (o "e mais").
-- OS com linha confirmado, recusado ou pausado daquele parceiro nunca vira letra. Nunca pelo nome.
create or replace function public._parceiro_pergunta_opcoes(p_parceiro uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_letras constant text[] := array['A', 'B', 'C', 'D'];
  v_agora timestamptz := coalesce(p_agora, now());
begin
  return (
    with a as (
      select oi.service_order_id, oi.client_id, oi.id as interessado_id, oi.origem as sinal, oi.papel as papel_proposto
        from public.os_interessados oi
       where oi.parceiro_id = p_parceiro
         and oi.situacao = 'proposto'
         and oi.papel is distinct from 'anfitria'
         and public._parceiro_os_viva(oi.service_order_id, p_parceiro, v_agora)
    ), b as (
      select c.service_order_id, c.client_id, null::uuid as interessado_id, c.sinal, c.papel_proposto
        from public.parceiro_lote_candidatos(p_parceiro, v_agora, 50) c
    ), u as (
      select * from a
      union all
      select * from b where not exists (select 1 from a where a.service_order_id = b.service_order_id)
    ), x as (
      select u.*, so.service_order_number,
             row_number() over (order by case u.sinal when 'numero_do_pedido' then 1 when 'unidade_anterior' then 2
                                                      when 'propria' then 3 when 'carteira' then 4 else 5 end,
                                         so.service_order_number collate "C" desc, u.service_order_id) as k
        from u
        join public.service_orders so on so.id = u.service_order_id
       where not exists (select 1 from public.os_interessados o2
                          where o2.service_order_id = u.service_order_id and o2.parceiro_id = p_parceiro
                            and o2.situacao in ('confirmado', 'recusado', 'pausado'))
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'letra', case when x.k <= 4 then c_letras[x.k] end,
             'service_order_id', x.service_order_id, 'client_id', x.client_id, 'interessado_id', x.interessado_id,
             'sinal', x.sinal, 'papel_proposto', x.papel_proposto,
             'rotulo', replace(public._parceiro_os_rotulo(x.service_order_id), ' · ', ' '))
           order by x.k), '[]'::jsonb)
      from x);
end;
$$;

comment on function public._parceiro_pergunta_opcoes(uuid, timestamptz) is
  'Retorno F4 (P8.1): [{letra, service_order_id, client_id, interessado_id, sinal, papel_proposto, rotulo}] da pergunta: (a) os vínculos proposto do parceiro com a OS na regra 8 e (b) parceiro_lote_candidatos ainda sem linha; ordem pelo sinal e pelo número decrescente; letra A–D só nas 4 primeiras (as demais, letra nula, são o "e mais"). OS com linha confirmado, recusado ou pausado não entra.';

revoke all on function public._parceiro_pergunta_opcoes(uuid, timestamptz) from public, anon, authenticated;

-- ── 5. A montagem do item ──────────────────────────────────────────────────────────────────────────────────────────────

-- O item de uma linha da fila: {tipo, ids da coluna do tipo, texto_mostrado, opcoes, retrato (exige_letra, ver, …),
-- selecionado, hash}. Erro sobe: quem abre o cartão pula o item e segue.
create or replace function public._parceiro_item_montar(p_fila uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_dias constant text[] := array['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_f public.parceiro_fila;
  v_pa public.parceiros;
  v_oi public.os_interessados;
  v_item jsonb;
  v_texto text;
  v_opcoes jsonb := '[]'::jsonb;
  v_retrato jsonb := '{}'::jsonb;
  v_sel boolean := true;
  v_exige boolean := false;
  v_tel boolean;
  v_base text;
  v_nome text;
  v_numero text;
  v_pp public.parceiro_paineis;
  v_saem integer;
  v_fora integer;
  v_motivo text;
  v_mudaram integer;
  v_ultimo jsonb;
  v_ver text[] := '{}'::text[];
  v_l jsonb;
  v_linha text;
  v_vessel uuid;
  v_cli uuid;
  v_k integer;
  v_linhas jsonb;
  v_pt jsonb;
  v_ab public.retorno_aberturas;
  v_m record;
  v_ops jsonb;
  v_mais integer;
  v_letras text;
  v_saida public.retorno_saidas;
  v_reg boolean;
  v_env record;
  v_num uuid;
  v_primeiro text;
  v_p14 text;
begin
  select * into v_f from public.parceiro_fila f where f.id = p_fila;
  if not found then
    raise exception using errcode = '22023', message = 'parceiro_item_montar: linha da fila desconhecida';
  end if;
  select * into v_pa from public.parceiros pa where pa.id = v_f.parceiro_id;
  v_item := jsonb_build_object('tipo', v_f.tipo, 'fila_id', v_f.id);

  if v_f.tipo = 'vinculo' then
    select * into v_oi from public.os_interessados oi where oi.id = v_f.referencia;
    if not found then
      raise exception using errcode = '22023', message = 'parceiro_item_montar: vínculo desconhecido';
    end if;
    v_tel := public._parceiro_fone_do_cliente(v_oi.client_id) is not null;
    v_base := format('%s. %s · %s', p_n, public._parceiro_os_rotulo(v_oi.service_order_id),
                     public._parceiro_sinal_texto(v_oi.origem, v_pa.sigla));
    if v_oi.papel is not null and v_oi.origem not in ('carteira', 'dono') then
      -- sinal forte: o papel proposto vale sem letra; sem telefone, a letra diz como o cliente foi avisado
      v_texto := v_base || format(' (%s)', public._parceiro_papel_texto(v_oi.papel));
      if not v_tel then
        v_texto := v_texto || format(' · sem telefone: *%1$s A* pessoalmente · *%1$s B* pela revenda', p_n);
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'A', 'rotulo', 'avisei pessoalmente', 'acao', 'pessoalmente'),
                                                  jsonb_build_object('letra', 'B', 'rotulo', 'aviso pela revenda', 'acao', 'pela_revenda'));
      end if;
      v_texto := v_texto || format(' · *%s R* recusa para sempre', p_n);
      v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'R', 'rotulo', 'recusa para sempre', 'acao', 'recusar'));
    else
      -- carteira ou *parceiro 74*: nasce desmarcado, e o *sim <PIN>* sem letra não confirma
      v_texto := v_base;
      if not v_tel then
        v_texto := v_texto || format(' · *%1$s A* ela indicou, avisei pessoalmente · *%1$s B* ela indicou, aviso pela revenda', p_n);
        v_opcoes := v_opcoes || jsonb_build_array(
          jsonb_build_object('letra', 'A', 'rotulo', 'ela indicou, avisei pessoalmente', 'acao', 'indicou_pessoalmente'),
          jsonb_build_object('letra', 'B', 'rotulo', 'ela indicou, aviso pela revenda', 'acao', 'indicou_pela_revenda'));
      end if;
      v_texto := v_texto || format(' · *%1$s C* ela indicou · *%1$s P* só fica no pátio · *%1$s R* recusa para sempre', p_n);
      v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'C', 'rotulo', 'ela indicou', 'acao', 'indicou'),
                                                jsonb_build_object('letra', 'P', 'rotulo', 'só fica no pátio', 'acao', 'anfitria'),
                                                jsonb_build_object('letra', 'R', 'rotulo', 'recusa para sempre', 'acao', 'recusar'));
      v_sel := false;
      v_exige := true;
    end if;
    v_item := v_item || jsonb_build_object('interessado_id', v_oi.id, 'service_order_id', v_oi.service_order_id);
    v_retrato := jsonb_build_object('tem_telefone', v_tel, 'origem', v_oi.origem, 'papel', v_oi.papel);

  elsif v_f.tipo = 'painel' then
    select * into v_pp from public.parceiro_paineis pp where pp.id = v_f.referencia;
    if not found then
      raise exception using errcode = '22023', message = 'parceiro_item_montar: painel desconhecido';
    end if;
    select count(*) filter (where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$'),
           count(*) filter (where l ->> 'fora_por' is not null),
           max((l ->> 'n')::integer) filter (where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$')
      into v_saem, v_fora, v_k
      from jsonb_array_elements(v_pp.linhas) l;
    select l ->> 'fora_por' into v_motivo
      from jsonb_array_elements(v_pp.linhas) l
     where l ->> 'fora_por' is not null
     group by l ->> 'fora_por'
     order by count(*) desc, l ->> 'fora_por'
     limit 1;
    select pp.linhas into v_ultimo
      from public.parceiro_paineis pp
     where pp.parceiro_id = v_pp.parceiro_id and pp.dia < v_pp.dia and pp.estado = 'enviado'
     order by pp.dia desc limit 1;
    select count(*) into v_mudaram
      from jsonb_array_elements(v_pp.linhas) l
     where l ->> 'fora_por' is null
       and not exists (select 1 from jsonb_array_elements(coalesce(v_ultimo, '[]'::jsonb)) u
                        where u ->> 'fora_por' is null
                          and u ->> 'service_order_id' = l ->> 'service_order_id'
                          and u ->> 'estado' is not distinct from l ->> 'estado'
                          and u ->> 'desde' is not distinct from l ->> 'desde');
    -- *ver N*: as linhas com o n que o dono usa no *N tira L* e no *N sabe L*
    for v_l in select l from jsonb_array_elements(v_pp.linhas) l
                where coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$' order by (l ->> 'n')::integer loop
      v_vessel := null;
      v_cli := null;
      select so.vessel_id, oi.client_id into v_vessel, v_cli
        from public.os_interessados oi join public.service_orders so on so.id = oi.service_order_id
       where oi.id = nullif(v_l ->> 'interessado_id', '')::uuid;
      begin
        -- a etapa (R1, respostas de 09/11): o dono vê a linha como ela vai à parceira
        v_linha := public._parceiro_texto('parceiro_painel', 'linha', jsonb_build_object(
                     'n', (v_l ->> 'n')::integer, 'bem', public._parceiro_bem(v_vessel), 'cliente', public._parceiro_nome_curto(v_cli),
                     'estado', v_l ->> 'estado', 'desde', v_l -> 'desde')
                     || (case when jsonb_typeof(v_l -> 'etapa') = 'string' then jsonb_build_object('etapa', v_l -> 'etapa')
                              else '{}'::jsonb end));
      exception when sqlstate '22023' or sqlstate '22P02' then
        v_linha := format('%s. (sem texto: sai do painel)', v_l ->> 'n');
      end;
      if v_l ->> 'fora_por' is not null then
        v_linha := v_linha || format(' [fora: %s]', v_l ->> 'fora_por');
      elsif v_l ->> 'retida_por' is not null then
        v_linha := v_linha || format(' [o cliente ainda não ouviu: %s · *%s sabe %s*]', v_l ->> 'retida_por', p_n, v_l ->> 'n');
      end if;
      v_ver := v_ver || v_linha;
    end loop;
    v_texto := format('%s. Pátio da %s de hoje: %s veículos, %s', p_n, v_pa.sigla, coalesce(v_saem, 0),
                      case when coalesce(v_mudaram, 0) = 0 then 'nenhum mudou'
                           when v_mudaram = 1 then '1 mudou' else v_mudaram || ' mudaram' end)
               || case when coalesce(v_fora, 0) > 0 then format(', %s fora (%s)', v_fora, replace(v_motivo, '_', ' ')) else '' end
               || format(' · *ver %1$s* mostra · *%1$s tira %2$s* tira a linha %2$s · *%1$s sabe %2$s* o cliente da linha %2$s já sabe',
                         p_n, coalesce(v_k, 1));
    v_item := v_item || jsonb_build_object('painel_id', v_pp.id);
    v_retrato := jsonb_build_object('dia', v_pp.dia, 'ver', to_jsonb(v_ver), 'sabe', '[]'::jsonb);

  elsif v_f.tipo = 'patio' then
    v_numero := public._parceiro_rotulo_do_numero(v_f.referencia);
    -- a etapa (R1, respostas de 09/11) segue com a linha quando parceiro_linhas a pôs
    v_linhas := (select coalesce(jsonb_agg(jsonb_build_object('n', (l ->> 'n')::integer, 'interessado_id', l -> 'interessado_id',
                                                              'service_order_id', l -> 'service_order_id', 'estado', l -> 'estado',
                                                              'desde', l -> 'desde')
                                           || (case when jsonb_typeof(l -> 'etapa') = 'string'
                                                    then jsonb_build_object('etapa', l -> 'etapa') else '{}'::jsonb end)
                                           order by (l ->> 'n')::integer), '[]'::jsonb)
                   from jsonb_array_elements(public.parceiro_linhas(v_f.parceiro_id, v_agora)) l
                  where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$');
    if jsonb_array_length(v_linhas) = 0 then
      v_pt := jsonb_build_object('texto', public._parceiro_texto('parceiro_patio', 'vazio', '{}'::jsonb));
    else
      v_pt := public._parceiro_painel_texto('parceiro_patio', 'direto', v_linhas, 0, v_hoje, false);
    end if;
    v_texto := format('%s. %s pediu o pátio às %s. Respondo assim: %s', p_n, v_numero,
                      to_char(coalesce(nullif(v_f.dados ->> 'pedido_em', '')::timestamptz, v_f.criado_em) at time zone c_fuso, 'HH24:MI'),
                      case when char_length(v_pt ->> 'texto') <= 600 then v_pt ->> 'texto'
                           else format('%s veículos (*ver %s* mostra o texto)', jsonb_array_length(v_linhas), p_n) end);
    v_item := v_item || jsonb_build_object('numero_id', v_f.referencia);
    v_retrato := jsonb_build_object('linhas', v_linhas, 'msg_id', v_f.dados -> 'msg_id', 'dia', v_hoje,
                                    'ver', jsonb_build_array(v_pt ->> 'texto'));

  elsif v_f.tipo = 'pergunta' then
    select * into v_ab from public.retorno_aberturas a where a.id = v_f.referencia;
    if not found then
      raise exception using errcode = '22023', message = 'parceiro_item_montar: caso desconhecido';
    end if;
    select rm.recebida_em, public._retorno_trecho(w.body, w.message_type, rm.audio_pendente, 300) as trecho
      into v_m
      from public.retorno_mensagens rm
      join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
     where rm.abertura_id = v_ab.id and rm.recebida_em <= v_agora
     order by rm.pede_resposta desc, rm.recebida_em desc, rm.whatsapp_message_id desc
     limit 1;
    v_ops := public._parceiro_pergunta_opcoes(v_f.parceiro_id, v_agora);
    select string_agg(format('*%s %s* %s', p_n, o ->> 'letra', o ->> 'rotulo'), ' · ' order by o ->> 'letra')
      into v_letras
      from jsonb_array_elements(v_ops) o where o ->> 'letra' is not null;
    select count(*) into v_mais from jsonb_array_elements(v_ops) o where o ->> 'letra' is null;
    -- _retorno_trecho já devolve o trecho entre aspas simples (ou "(foto)", "(sem texto)"): não se põe aspas de novo.
    v_texto := format('%s. %s · %s · %s', p_n, public._retorno_rotulo(v_ab.id, v_agora),
                      coalesce(c_dias[extract(dow from v_m.recebida_em at time zone c_fuso)::integer + 1] || ' '
                               || to_char(v_m.recebida_em at time zone c_fuso, 'HH24:MI'), 'sem hora'),
                      coalesce(v_m.trecho, '(sem texto)'));
    if v_letras is not null then
      v_texto := v_texto || format(' · Ligar alguma OS à %s (só andamento, sem valores)? %s', v_pa.sigla, v_letras)
                 || case when v_mais > 0 then format(' · e mais %s: *parceiro 74*', v_mais) else '' end;
      v_opcoes := (select coalesce(jsonb_agg(o || jsonb_build_object('acao', 'ligar') order by o ->> 'letra'), '[]'::jsonb)
                     from jsonb_array_elements(v_ops) o where o ->> 'letra' is not null);
    end if;
    v_texto := v_texto || format(' · *resolvido %s*', p_n);
    v_exige := true;
    v_item := v_item || jsonb_build_object('abertura_id', v_ab.id);
    v_retrato := jsonb_build_object('mais', v_mais);

  elsif v_f.tipo = 'pedido' then
    -- P10: a montagem do item pedido é de parceiro_pedido_montar (onda 7). Sem ela, o item não monta.
    v_pt := public.parceiro_pedido_montar(v_f.referencia, p_n, v_agora);
    return v_item || (v_pt - 'tipo' - 'fila_id');

  elsif v_f.tipo in ('retido', 'aviso') then
    select * into v_oi from public.os_interessados oi where oi.id = v_f.referencia;
    if not found then
      raise exception using errcode = '22023', message = 'parceiro_item_montar: vínculo desconhecido';
    end if;
    v_nome := coalesce(public._retorno_nome(v_oi.client_id), 'cliente sem nome');
    select so.service_order_number into v_numero from public.service_orders so where so.id = v_oi.service_order_id;
    if v_f.tipo = 'retido' then
      v_texto := format('%1$s. %2$s (%3$s) respondeu ao aviso da %4$s com algo que pode ser um não. *%1$s A* pode seguir · *%1$s V* o cliente não quer',
                        p_n, v_nome, v_numero, v_pa.sigla);
      v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'A', 'rotulo', 'pode seguir', 'acao', 'seguir'),
                                    jsonb_build_object('letra', 'V', 'rotulo', 'o cliente não quer', 'acao', 'veto_dono'));
    else
      v_reg := v_oi.aviso_ao_cliente in ('pessoalmente', 'pela_revenda');
      if nullif(v_f.dados ->> 'saida_id', '') is not null then
        select * into v_saida from public.retorno_saidas s where s.id = (v_f.dados ->> 'saida_id')::uuid;
      end if;
      if v_reg then
        v_texto := format('%1$s. %2$s (%3$s) ganhou telefone, e a mensagem de aviso da %4$s não saiu. *%1$s C* mandar de novo',
                          p_n, v_nome, v_numero, v_pa.sigla);
        v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'C', 'rotulo', 'mandar de novo', 'acao', 'reenviar'));
      else
        v_texto := format('%1$s. %2$s (%3$s) segue sem aviso da %4$s. *%1$s A* avisei pessoalmente · *%1$s B* pela revenda',
                          p_n, v_nome, v_numero, v_pa.sigla);
        v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'A', 'rotulo', 'avisei pessoalmente', 'acao', 'pessoalmente'),
                                      jsonb_build_object('letra', 'B', 'rotulo', 'aviso pela revenda', 'acao', 'pela_revenda'));
        if v_saida.id is not null and v_saida.estado in ('recusada', 'incerta', 'cancelada') then
          v_texto := v_texto || format(' · *%s C* mandar a mensagem de novo', p_n);
          v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'C', 'rotulo', 'mandar a mensagem de novo', 'acao', 'reenviar'));
        end if;
      end if;
      v_retrato := jsonb_build_object('saida_id', v_saida.id, 'registrado', v_reg);
    end if;
    v_exige := true;
    v_item := v_item || jsonb_build_object('interessado_id', v_oi.id, 'service_order_id', v_oi.service_order_id);
    v_retrato := v_retrato || jsonb_build_object('exige_letra', true);

  elsif v_f.tipo = 'pdf_mao' then
    select e.id, e.numero_doc, e.enviado_em, e.service_order_id into v_env
      from public.parceiro_envios_a_mao e where e.id = v_f.referencia;
    if v_env.id is null then
      raise exception using errcode = '22023', message = 'parceiro_item_montar: envio desconhecido';
    end if;
    v_texto := format('%1$s. Você mandou o %2$s à %3$s à mão em %4$s. *%1$s A* ela contrata · *%1$s B* ela paga · *%1$s C* só indicou (só anoto; nada muda para a %3$s)',
                      p_n, v_env.numero_doc, v_pa.sigla, to_char(v_env.enviado_em at time zone c_fuso, 'DD/MM'));
    v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'A', 'rotulo', 'ela contrata', 'acao', 'A'),
                                  jsonb_build_object('letra', 'B', 'rotulo', 'ela paga', 'acao', 'B'),
                                  jsonb_build_object('letra', 'C', 'rotulo', 'só indicou', 'acao', 'C'));
    v_exige := true;
    v_item := v_item || jsonb_build_object('envio_mao_id', v_env.id, 'service_order_id', v_env.service_order_id);

  elsif v_f.tipo = 'repassar' then
    select * into v_oi from public.os_interessados oi where oi.id = nullif(v_f.dados ->> 'interessado_id', '')::uuid;
    if not found or v_oi.service_order_id is distinct from v_f.referencia then
      raise exception using errcode = '22023', message = 'parceiro_item_montar: vínculo do repassar desconhecido';
    end if;
    -- o número que recebe: o 1º que recebe o resumo, com a pessoa ativa e sem pausa (como o eco)
    select nn.id into v_num
      from public.parceiro_numeros nn
      join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo and pe.pausado_em is null
     where pe.parceiro_id = v_f.parceiro_id and nn.situacao = 'confirmado' and nn.recebe_painel
     order by nn.criado_em, nn.id
     limit 1;
    if v_num is null then
      raise exception using errcode = '22023', message = 'parceiro_item_montar: sem número que recebe o resumo';
    end if;
    select so.service_order_number, so.vessel_id into v_numero, v_vessel from public.service_orders so where so.id = v_oi.service_order_id;
    v_primeiro := public._agenda_nome_curto(public._parceiro_nome_curto(v_oi.client_id));
    v_p14 := public._parceiro_texto('parceiro_repassar', 'padrao', jsonb_build_object(
               'abertura', public._parceiro_abertura(v_num, public._parceiro_nomes_do_contexto(v_f.parceiro_id, array[v_oi.client_id], null) -> 'nomes_de_outros', v_agora),
               'primeiro_nome', v_primeiro, 'bem', public._parceiro_bem(v_vessel)));
    v_texto := format('%s. %s (%s) não tem WhatsApp. Peço à %s para repassar? "%s"', p_n,
                      coalesce(public._retorno_nome(v_oi.client_id), 'cliente sem nome'), v_numero, v_pa.sigla, v_p14);
    v_item := v_item || jsonb_build_object('interessado_id', v_oi.id, 'service_order_id', v_oi.service_order_id);
    v_retrato := jsonb_build_object('numero_id', v_num, 'primeiro_nome', v_primeiro);

  else
    raise exception using errcode = '22023', message = 'parceiro_item_montar: tipo fora da fila';
  end if;

  return v_item || jsonb_build_object(
    'texto_mostrado', v_texto, 'opcoes', v_opcoes, 'retrato', v_retrato || jsonb_build_object('exige_letra', v_exige),
    'selecionado', v_sel, 'hash', public._parceiro_item_impressao(v_f.tipo, v_f.referencia, v_agora));
end;
$$;

comment on function public._parceiro_item_montar(uuid, smallint, timestamptz) is
  'Retorno F4 (P8.1): o item de uma linha da fila, pela tabela "Item a item": texto ao dono, letras ([{letra, rotulo, acao}]), retrato (exige_letra, ver, …), selecionado (falso no vínculo de carteira ou de *parceiro 74*) e hash. O item pedido é de parceiro_pedido_montar (P10). Erro sobe.';

revoke all on function public._parceiro_item_montar(uuid, smallint, timestamptz) from public, anon, authenticated;

-- O item corte (*parceiro 74* com vínculo): pausar, cortar, o veto do dono e, no pausado, retomar. Não vem da fila.
create or replace function public._parceiro_item_corte(p_interessado uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_oi public.os_interessados;
  v_pa public.parceiros;
  v_texto text;
  v_opcoes jsonb := '[]'::jsonb;
begin
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado;
  if not found then
    raise exception using errcode = '22023', message = 'parceiro_item_corte: vínculo desconhecido';
  end if;
  select * into v_pa from public.parceiros pa where pa.id = v_oi.parceiro_id;
  v_texto := format('%s. %s · ligada à %s (%s)', p_n, public._parceiro_os_rotulo(v_oi.service_order_id), v_pa.sigla,
                    case v_oi.situacao when 'confirmado' then public._parceiro_papel_texto(v_oi.papel)
                                       when 'pausado' then 'pausada'
                                       when 'proposto' then 'proposta, sem o seu sim'
                                       else 'recusada para sempre' end);
  if v_oi.situacao = 'confirmado' then
    v_texto := v_texto || format(' · *%s A* pausa', p_n);
    v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'A', 'rotulo', 'pausa', 'acao', 'pausar'));
  elsif v_oi.situacao = 'pausado' then
    v_texto := v_texto || format(' · *%s T* retoma', p_n);
    v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'T', 'rotulo', 'retoma', 'acao', 'retomar'));
  end if;
  if v_oi.situacao <> 'recusado' then
    v_texto := v_texto || format(' · *%s R* corta para sempre', p_n);
    v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'R', 'rotulo', 'corta para sempre', 'acao', 'recusar'));
  end if;
  v_texto := v_texto || format(' · *%s V* o cliente não quer', p_n);
  v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'V', 'rotulo', 'o cliente não quer', 'acao', 'veto_dono'));
  return jsonb_build_object('tipo', 'corte', 'fila_id', null, 'interessado_id', v_oi.id, 'service_order_id', v_oi.service_order_id,
                            'texto_mostrado', v_texto, 'opcoes', v_opcoes,
                            'retrato', jsonb_build_object('exige_letra', true, 'situacao', v_oi.situacao),
                            'selecionado', true, 'hash', public._parceiro_item_impressao('corte', v_oi.id, p_agora));
end;
$$;

revoke all on function public._parceiro_item_corte(uuid, smallint, timestamptz) from public, anon, authenticated;

-- ── 6. Abrir: a pendência, o *parceiro* e o *parceiro 74* ──────────────────────────────────────────────────────────────

-- O cartão em 'lista' vira vivo: sessão do dono, pendência parceiro_executar_cartao (24 h), ponteiro por merge, pergunta
-- registrada, o par da conversa só com o número de itens (nunca o texto) e a auditoria.
create or replace function public._parceiro_cartao_viver(p_cartao uuid, p_dono uuid, p_phone text, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_c public.parceiro_cartoes;
  v_n integer;
  v_sessao uuid;
  v_pend uuid;
  v_perg jsonb;
  v_texto text;
begin
  select * into v_c from public.parceiro_cartoes c where c.id = p_cartao;
  select count(*) into v_n from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';
  v_sessao := public._retorno_sessao_do_dono(p_dono, p_phone, v_agora);
  insert into public.ai_operator_pending_actions (session_id, requested_by_user_id, action_name, risk_level, risk_reason, title, summary,
                                                  payload, status, expires_at)
  values (v_sessao, p_dono, 'parceiro_executar_cartao', 'high', 'liga cliente a parceiro ou manda mensagem ao parceiro',
          'Cartão do parceiro', format('Cartão do parceiro: %s itens. Mande *parceiro* para ver.', v_n),
          jsonb_build_object('cartao_id', p_cartao), 'pending', v_c.expira_em)
  returning id into v_pend;

  update public.ai_operator_sessions s
     set metadata = coalesce(s.metadata, '{}'::jsonb)
                    || jsonb_build_object('pending_confirm_action_id', v_pend, 'pin_attempts', 0, 'pendencia_herdada', false),
         last_activity_at = v_agora
   where s.id = v_sessao;

  v_perg := public.pergunta_registrar_externa(jsonb_build_object('phone', p_phone, 'origem', 'acompanhar_conversa', 'tipo', 'confirmacao',
    'referencia_id', v_pend, 'titulo', 'Cartão do parceiro'));

  insert into public.ai_operator_messages (session_id, role, content, source) values
    (v_sessao, 'user', format('🤖 Cartão do parceiro (aviso automático): %s itens.', v_n), 'whatsapp'),
    (v_sessao, 'assistant', format('Cartão do parceiro aberto (pendência %s): %s itens. O que os parceiros e os clientes escreveram fica fora desta conversa.',
                                   v_pend, v_n), 'whatsapp');

  insert into public.ai_operator_audit (session_id, pending_action_id, actor_user_id, actor_kind, event_type, event_category, payload)
  values (v_sessao, v_pend, p_dono, 'system', 'parceiro:cartao:proposto', 'channel',
          jsonb_build_object('cartao_id', p_cartao, 'itens', v_n, 'gatilho', v_c.gatilho));

  update public.parceiro_cartoes c
     set estado = 'vivo', sessao_id = v_sessao, pendencia_id = v_pend, pergunta_id = (v_perg ->> 'id')::uuid
   where c.id = p_cartao;
  v_texto := public._parceiro_cartao_texto(p_cartao, null);
  update public.parceiro_cartoes c set texto = v_texto, hash = md5(v_texto) where c.id = p_cartao;
  return jsonb_build_object('pendencia_id', v_pend, 'pergunta_id', v_perg ->> 'id', 'texto', v_texto);
end;
$$;

revoke all on function public._parceiro_cartao_viver(uuid, uuid, text, timestamptz) from public, anon, authenticated;

-- C-CARTAO-P: *parceiro*. Só o gatilho puxar; desligado = vazio sem tocar em nada. Com cartão do parceiro vivo, reapresenta;
-- com o cartão da F2 vivo ou uma pergunta aberta, ocupado. Sem cartão: o lote (parceiro_lote_candidatos → parceiro_propor,
-- com o dono), a conferência da fila e os candidatos; até cartao_max_itens itens, o resto em "e mais N". O texto volta na
-- resposta: quem manda é a camada; o sistema nunca dispara cartão sozinho.
create or replace function public.parceiro_cartao_abrir(p_gatilho text, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_cartao uuid;
  v_texto text;
  v_dono uuid;
  v_phone text;
  v_pa record;
  v_lote jsonb;
  v_total integer;
  v_n smallint := 0;
  v_k smallint;
  r record;
  v_item jsonb;
  v_viver jsonb;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' or p_gatilho is distinct from 'puxar' then
    return jsonb_build_object('acao', 'vazio');
  end if;
  perform pg_advisory_xact_lock(hashtext('parceiro:cartao'));

  v_vivo := public.parceiro_cartao_vivo(v_agora);
  if v_vivo is not null and public._parceiro_cartao_fechar_se_vazio((v_vivo ->> 'id')::uuid, v_agora) then
    v_vivo := null;
  end if;
  if v_vivo is not null then
    v_cartao := (v_vivo ->> 'id')::uuid;
    v_texto := public._parceiro_cartao_texto(v_cartao, null);
    update public.parceiro_cartoes c set texto = v_texto where c.id = v_cartao;
    return jsonb_build_object('acao', 'reapresenta', 'cartao_id', v_cartao, 'texto', v_texto);
  end if;

  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  if v_dono is null or v_phone is null then
    return jsonb_build_object('acao', 'vazio', 'motivo', 'sem_dono');
  end if;
  if (public.retorno_cartao_vivo(v_agora) ->> 'estado') is not distinct from 'vivo'
     or coalesce((public.pergunta_ocupado(v_phone) ->> 'ocupado')::boolean, false) then
    return jsonb_build_object('acao', 'ocupado', 'texto', 'Tem um pedido aberto antes deste: responda a ele e mande *parceiro* de novo.');
  end if;

  -- O lote: o *parceiro* propõe (nunca confirma) antes de ler a fila, com o dono como autor.
  for v_pa in select pa.id from public.parceiros pa where pa.ativo order by pa.criado_em, pa.id loop
    begin
      select coalesce(jsonb_agg(jsonb_build_object('service_order_id', c.service_order_id, 'parceiro_id', v_pa.id,
                                                   'client_id', c.client_id, 'origem', c.sinal, 'papel', c.papel_proposto)), '[]'::jsonb)
        into v_lote
        from public.parceiro_lote_candidatos(v_pa.id, v_agora, 50) c;
      if jsonb_array_length(v_lote) > 0 then
        perform public.parceiro_propor(v_lote, v_dono);
      end if;
    exception when others then
      perform public._retorno_log('parceiro_cartao', 'parceiro_cartao_abrir (lote): ' || sqlerrm, 'error',
                                  jsonb_build_object('parceiro', v_pa.id, 'sqlstate', sqlstate));
    end;
  end loop;
  perform public._parceiro_fila_conferir(v_agora);

  select count(*) into v_total from public._parceiro_cartao_candidatos(v_agora, null);
  if v_total = 0 then
    return jsonb_build_object('acao', 'vazio', 'texto', 'Nada do parceiro agora.');
  end if;

  insert into public.parceiro_cartoes (gatilho, dia, estado, hash, texto, criado_em, expira_em)
  values ('puxar', (v_agora at time zone c_fuso)::date, 'lista', '', '', v_agora, v_agora + interval '24 hours')
  returning id into v_cartao;

  for r in select * from public._parceiro_cartao_candidatos(v_agora, v_cfg.cartao_max_itens) loop
    v_k := v_n + 1;
    begin
      v_item := public._parceiro_item_montar(r.fila_id, v_k, v_agora);
      insert into public.parceiro_cartao_itens (cartao_id, n, tipo, interessado_id, painel_id, abertura_id, service_order_id, envio_mao_id,
                                                pedido_id, numero_id, fila_id, texto_mostrado, opcoes, retrato, hash, selecionado)
      values (v_cartao, v_k, v_item ->> 'tipo', (v_item ->> 'interessado_id')::uuid, (v_item ->> 'painel_id')::uuid,
              (v_item ->> 'abertura_id')::uuid, (v_item ->> 'service_order_id')::uuid, (v_item ->> 'envio_mao_id')::uuid,
              (v_item ->> 'pedido_id')::uuid, (v_item ->> 'numero_id')::uuid, r.fila_id, v_item ->> 'texto_mostrado',
              coalesce(v_item -> 'opcoes', '[]'::jsonb), coalesce(v_item -> 'retrato', '{}'::jsonb), v_item ->> 'hash',
              coalesce((v_item ->> 'selecionado')::boolean, true));
      update public.parceiro_fila f set estado = 'no_cartao', vezes = f.vezes + 1, ultimo_em = v_agora where f.id = r.fila_id;
      v_n := v_k;
    exception when others then
      -- erro nunca trava a fila: o item que não monta perde a vez, e o próximo segue
      update public.parceiro_fila f set vezes = f.vezes + 1, ultimo_em = v_agora where f.id = r.fila_id;
      perform public._retorno_log('parceiro_cartao', 'parceiro_cartao_abrir (item): ' || sqlerrm, 'error',
                                  jsonb_build_object('fila', r.fila_id, 'sqlstate', sqlstate));
    end;
  end loop;
  if v_n = 0 then
    update public.parceiro_cartoes c set estado = 'falhou', texto = 'Nenhum item montou.' where c.id = v_cartao;
    return jsonb_build_object('acao', 'vazio', 'texto', 'Nada do parceiro agora.');
  end if;
  update public.parceiro_cartoes c set mais = least(greatest(v_total - v_n, 0), 32767) where c.id = v_cartao;

  v_viver := public._parceiro_cartao_viver(v_cartao, v_dono, v_phone, v_agora);
  return jsonb_build_object('acao', 'cartao', 'cartao_id', v_cartao, 'phone', v_phone, 'texto', v_viver ->> 'texto',
                            'pergunta_id', v_viver ->> 'pergunta_id');
end;
$$;

comment on function public.parceiro_cartao_abrir(text, timestamptz) is
  'Retorno F4 (C-CARTAO-P): *parceiro* (só gatilho puxar). desligado → {acao: vazio} sem tocar em nada; vivo → reapresenta; cartão da F2 vivo ou pergunta aberta → ocupado. Sem cartão: lote (parceiro_lote_candidatos → parceiro_propor, autor o dono), _parceiro_fila_conferir e _parceiro_cartao_candidatos; vazio → "Nada do parceiro agora."; senão o cartão vivo com a pendência parceiro_executar_cartao (24 h). O texto volta na resposta.';

revoke all on function public.parceiro_cartao_abrir(text, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_cartao_abrir(text, timestamptz) to service_role;

-- C-CARTAO-P: *parceiro 74* (ou *parceiro MP 74*), em qualquer parceiro_modo. A OS pelo número inteiro (74, OS-00074,
-- ORC-00107 → ORÇ-00107), nunca pelo nome. Sem vínculo com aquele parceiro: item vinculo com origem dono e as letras da
-- carteira. Com vínculo: item corte. Mesmas travas de ocupado.
create or replace function public.parceiro_cartao_abrir_os(p_sigla text, p_numero text, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_dono uuid;
  v_phone text;
  v_num text := upper(regexp_replace(btrim(coalesce(p_numero, '')), '[[:space:]]+', '', 'g'));
  v_pref text;
  v_dig bigint;
  v_os uuid;
  v_n integer;
  v_pa public.parceiros;
  v_oi public.os_interessados;
  v_prop jsonb;
  v_fila uuid;
  v_item jsonb;
  v_cartao uuid;
  v_viver jsonb;
  v_vivo jsonb;
begin
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  if p_autor is null or p_autor is distinct from v_dono then
    return jsonb_build_object('acao', 'vazio', 'motivo', 'nao_e_o_dono');
  end if;

  -- O número: só inteiro, com ou sem prefixo; ORC vira ORÇ.
  v_num := replace(v_num, 'ORC', 'ORÇ');
  if v_num ~ '^[0-9]{1,8}$' then
    v_dig := v_num::bigint;
  elsif v_num ~ '^(OS|ORÇ)-?[0-9]{1,8}$' then
    v_pref := substring(v_num from '^(OS|ORÇ)');
    v_dig := substring(v_num from '[0-9]+$')::bigint;
  else
    return jsonb_build_object('acao', 'vazio', 'texto', 'Não achei essa OS.');
  end if;
  select count(*), min(so.id::text)::uuid into v_n, v_os
    from public.service_orders so
   where so.merged_into_id is null
     and so.service_order_number ~ '^(OS|ORÇ)-[0-9]{1,8}$'
     and substring(so.service_order_number from '[0-9]+$')::bigint = v_dig
     and (v_pref is null or so.service_order_number like v_pref || '-%');
  if v_n is distinct from 1 then
    return jsonb_build_object('acao', 'vazio', 'texto', 'Não achei essa OS.');
  end if;

  -- O parceiro: pela sigla; sem ela, só com um ativo.
  if nullif(btrim(p_sigla), '') is not null then
    select * into v_pa from public.parceiros pa
     where pa.ativo and public._texto_simples(pa.sigla) = public._texto_simples(btrim(p_sigla));
    if not found then
      return jsonb_build_object('acao', 'vazio', 'texto', 'Não achei esse parceiro.');
    end if;
  else
    select count(*) into v_n from public.parceiros pa where pa.ativo;
    if v_n = 0 then
      return jsonb_build_object('acao', 'vazio', 'texto', 'Nenhum parceiro ativo.');
    elsif v_n > 1 then
      return jsonb_build_object('acao', 'vazio',
        'texto', format('Qual parceiro? *parceiro %s %s*', (select pa.sigla from public.parceiros pa where pa.ativo order by pa.criado_em, pa.id limit 1),
                        btrim(p_numero)));
    end if;
    select * into v_pa from public.parceiros pa where pa.ativo;
  end if;

  perform pg_advisory_xact_lock(hashtext('parceiro:cartao'));
  v_vivo := public.parceiro_cartao_vivo(v_agora);
  if v_vivo is not null and not public._parceiro_cartao_fechar_se_vazio((v_vivo ->> 'id')::uuid, v_agora) then
    return jsonb_build_object('acao', 'ocupado', 'texto', 'Tem um cartão do parceiro aberto: responda a ele antes (*parceiro* mostra de novo).');
  end if;
  if v_phone is null
     or (public.retorno_cartao_vivo(v_agora) ->> 'estado') is not distinct from 'vivo'
     or coalesce((public.pergunta_ocupado(v_phone) ->> 'ocupado')::boolean, false) then
    return jsonb_build_object('acao', 'ocupado', 'texto', 'Tem um pedido aberto antes deste: responda a ele e mande de novo.');
  end if;

  select * into v_oi from public.os_interessados oi
   where oi.service_order_id = v_os and oi.parceiro_id = v_pa.id
   order by (oi.papel is distinct from 'anfitria') desc, oi.proposto_em, oi.id
   limit 1;
  if found then
    v_item := public._parceiro_item_corte(v_oi.id, 1::smallint, v_agora);
  else
    v_prop := public.parceiro_propor(jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'parceiro_id', v_pa.id,
                                                                          'origem', 'dono')), v_dono);
    if jsonb_array_length(v_prop -> 'propostos') = 0 then
      return jsonb_build_object('acao', 'vazio',
        'texto', case v_prop -> 'recusados' -> 0 ->> 'motivo'
                   when 'veto' then format('O cliente dessa OS disse não à %s: não ligo.', v_pa.sigla)
                   when 'ja_decidido' then 'Essa OS já tem vínculo com esse parceiro.'
                   else 'Essa OS não está em andamento: não ligo.' end);
    end if;
    select f.id into v_fila from public.parceiro_fila f where f.chave = 'vinculo:' || (v_prop -> 'propostos' -> 0 ->> 'interessado_id');
    v_item := public._parceiro_item_montar(v_fila, 1::smallint, v_agora);
  end if;

  insert into public.parceiro_cartoes (gatilho, dia, estado, hash, texto, criado_em, expira_em)
  values ('os', (v_agora at time zone c_fuso)::date, 'lista', '', '', v_agora, v_agora + interval '24 hours')
  returning id into v_cartao;
  insert into public.parceiro_cartao_itens (cartao_id, n, tipo, interessado_id, service_order_id, fila_id, texto_mostrado, opcoes, retrato,
                                            hash, selecionado)
  values (v_cartao, 1, v_item ->> 'tipo', (v_item ->> 'interessado_id')::uuid, (v_item ->> 'service_order_id')::uuid, v_fila,
          v_item ->> 'texto_mostrado', v_item -> 'opcoes', v_item -> 'retrato', v_item ->> 'hash',
          coalesce((v_item ->> 'selecionado')::boolean, true));
  if v_fila is not null then
    update public.parceiro_fila f set estado = 'no_cartao', vezes = f.vezes + 1, ultimo_em = v_agora where f.id = v_fila;
  end if;
  v_viver := public._parceiro_cartao_viver(v_cartao, v_dono, v_phone, v_agora);
  return jsonb_build_object('acao', 'cartao', 'cartao_id', v_cartao, 'phone', v_phone, 'texto', v_viver ->> 'texto',
                            'pergunta_id', v_viver ->> 'pergunta_id');
end;
$$;

comment on function public.parceiro_cartao_abrir_os(text, text, uuid, timestamptz) is
  'Retorno F4 (C-CARTAO-P): *parceiro 74*, em qualquer parceiro_modo. Só o dono. A OS pelo número inteiro (74, OS-00074, ORC/ORÇ-00107), nunca pelo nome; mais de uma ou nenhuma → "Não achei essa OS.". Sem sigla e com mais de um parceiro ativo → "Qual parceiro? *parceiro MP 74*". Sem vínculo: parceiro_propor com origem dono e o item vinculo; com vínculo: item corte. Mesmas travas de ocupado.';

revoke all on function public.parceiro_cartao_abrir_os(text, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_cartao_abrir_os(text, text, uuid, timestamptz) to service_role;

-- ── 7. As palavras do dono no cartão (C-DITO-P) ────────────────────────────────────────────────────────────────────────

-- A letra da pergunta: (a) a linha proposto que já existe é confirmada com o papel proposto (ou indicou); (b) o par sem
-- linha é proposto pelo dono (origem dono, indicou) e confirmado. Devolve o resultado de _parceiro_confirmar.
create or replace function public._parceiro_decidir_letra_pergunta(p_item uuid, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_i public.parceiro_cartao_itens;
  v_op jsonb;
  v_int uuid;
  v_papel text;
  v_prop jsonb;
  v_pa uuid;
begin
  select * into v_i from public.parceiro_cartao_itens i where i.id = p_item;
  if not found or v_i.escolha is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_letra');
  end if;
  select o into v_op from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = v_i.escolha limit 1;
  if v_op is null or nullif(v_op ->> 'service_order_id', '') is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_letra');
  end if;
  v_int := nullif(v_op ->> 'interessado_id', '')::uuid;
  if v_int is not null then
    select oi.papel into v_papel from public.os_interessados oi where oi.id = v_int;
    return public._parceiro_confirmar(v_int, p_autor, null, p_agora, coalesce(v_papel, 'indicou'));
  end if;
  select f.parceiro_id into v_pa from public.parceiro_fila f where f.id = v_i.fila_id;
  v_prop := public.parceiro_propor(jsonb_build_array(jsonb_build_object(
              'service_order_id', v_op ->> 'service_order_id', 'parceiro_id', v_pa, 'client_id', v_op ->> 'client_id',
              'origem', 'dono', 'papel', 'indicou')), p_autor);
  v_int := nullif(v_prop -> 'propostos' -> 0 ->> 'interessado_id', '')::uuid;
  if v_int is null then
    return jsonb_build_object('ok', false, 'motivo', coalesce(v_prop -> 'recusados' -> 0 ->> 'motivo', 'nao_proposto'));
  end if;
  return public._parceiro_confirmar(v_int, p_autor, null, p_agora, 'indicou');
end;
$$;

comment on function public._parceiro_decidir_letra_pergunta(uuid, uuid, timestamptz) is
  'Retorno F4 (P8.1): a letra do item pergunta no *sim <PIN>*. Linha proposto: _parceiro_confirmar com coalesce(papel proposto, indicou); par sem linha: parceiro_propor (origem dono, indicou) e _parceiro_confirmar. Sem letra: {ok: false, motivo: sem_letra}.';

revoke all on function public._parceiro_decidir_letra_pergunta(uuid, uuid, timestamptz) from public, anon, authenticated;

-- *resolvido N*, sem PIN: só em item com caso (pergunta e pedido). Fecha o caso como dono, cancela as agendadas dele (caso_fechado),
-- item caiu/caso_fechado, fila feito, texto refeito. O pedido não é tocado (a rodada o leva a caso_fechado). Não vai a
-- retorno_toques: conta em decidido_em.
create or replace function public._parceiro_dito_resolvido(p_n integer, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_vivo jsonb;
  v_cartao uuid;
  v_item public.parceiro_cartao_itens;
  v_ab public.retorno_aberturas;
  v_rotulo text;
  v_k integer;
begin
  if p_n is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  v_vivo := public.parceiro_cartao_vivo(v_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;
  select * into v_item from public.parceiro_cartao_itens i where i.cartao_id = v_cartao and i.n = p_n and i.estado = 'vivo';
  if not found then
    return jsonb_build_object('ok', true, 'texto', format('Não há item %s neste cartão. Mande *parceiro*.', p_n));
  end if;
  if v_item.tipo not in ('pergunta', 'pedido') or v_item.abertura_id is null then
    return jsonb_build_object('ok', true, 'texto', 'Esse item não tem conversa para resolver: use a letra ou *não N*.');
  end if;

  select * into v_ab from public.retorno_aberturas a where a.id = v_item.abertura_id for update;
  v_rotulo := public._retorno_rotulo(v_ab.id, v_agora);
  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
   where s.abertura_id = v_ab.id and s.estado = 'agendada';
  get diagnostics v_k = row_count;
  update public.retorno_aberturas a
     set estado = 'fechada', fechada_em = v_agora, fechada_motivo = 'dono', atualizada_em = now()
   where a.id = v_ab.id and a.estado <> 'fechada';
  update public.parceiro_cartao_itens i set estado = 'caiu', caiu_motivo = 'caso_fechado', decidido_em = v_agora where i.id = v_item.id;
  perform public._parceiro_fila_marcar(v_item.fila_id, 'feito', null, v_agora);
  if not public._parceiro_cartao_fechar_se_vazio(v_cartao, v_agora) then
    update public.parceiro_cartoes c set texto = public._parceiro_cartao_texto(c.id, null) where c.id = v_cartao;
  end if;
  perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('estado', v_ab.estado),
    jsonb_build_object('estado', 'fechada', 'fechada_motivo', 'dono', 'abertura', v_ab.id), '*resolvido* do dono (parceiro)');
  return jsonb_build_object('ok', true,
    'texto', case when v_k = 0 then format('%s: resolvido, saiu da lista.', v_rotulo)
                  else format('%s: resolvido, saiu da lista, e cancelei o que estava agendado.', v_rotulo) end);
end;
$$;

comment on function public._parceiro_dito_resolvido(integer, uuid, timestamptz) is
  'Retorno F4 (P8.1): *resolvido N* no cartão do parceiro, sem PIN, como _retorno_dito_resolvido da F2. Só pergunta e pedido; o resto ouve "Esse item não tem conversa para resolver: use a letra ou *não N*.". Fecha o caso (dono), cancela as agendadas (caso_fechado), item caiu/caso_fechado, fila feito. Não grava retorno_toques.';

revoke all on function public._parceiro_dito_resolvido(integer, uuid, timestamptz) from public, anon, authenticated;

-- C-DITO-P: escolher, so, sem, tirar, ver, resolvido, tira_linha e sabe, com o cartão do parceiro vivo. Nunca recebe o PIN.
create or replace function public.parceiro_decidir_dito(p_comando jsonb, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cmd text := p_comando ->> 'comando';
  v_n integer;
  v_ns integer[];
  v_linha integer;
  v_letra text := upper(btrim(coalesce(p_comando ->> 'letra', '')));
  v_vivo jsonb;
  v_cartao uuid;
  v_k integer;
  v_item public.parceiro_cartao_itens;
  v_sel integer[];
  v_op jsonb;
  v_texto text;
  v_l jsonb;
  v_pp public.parceiro_paineis;
  v_x integer;
  v_y record;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  if jsonb_typeof(p_comando) is distinct from 'object' then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  begin
    v_n := (p_comando ->> 'n')::integer;
    v_linha := (p_comando ->> 'linha')::integer;
    v_ns := case when jsonb_typeof(p_comando -> 'ns') = 'array'
                 then array(select (x)::integer from jsonb_array_elements_text(p_comando -> 'ns') x) end;
  exception when others then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end;
  v_vivo := public.parceiro_cartao_vivo(v_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;

  select count(*) into v_k from public.parceiro_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  if (v_n is not null and not exists (select 1 from public.parceiro_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n and i.estado = 'vivo'))
     or (v_ns is not null and exists (select 1 from unnest(v_ns) x
                                       where not exists (select 1 from public.parceiro_cartao_itens i
                                                          where i.cartao_id = v_cartao and i.n = x and i.estado = 'vivo'))) then
    return jsonb_build_object('ok', true, 'texto', format('O cartão do parceiro tem %s itens.', v_k));
  end if;
  if v_n is not null then
    select * into v_item from public.parceiro_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n;
  end if;

  if v_cmd = 'escolher' then
    if v_n is null then
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
    end if;
    select o into v_op from jsonb_array_elements(v_item.opcoes) o where o ->> 'letra' = v_letra limit 1;
    if v_op is null then
      return jsonb_build_object('ok', true, 'texto',
        case when jsonb_array_length(v_item.opcoes) = 0 then format('O %s não tem letra: *sim <PIN>* faz ou *não %s* tira.', v_n, v_n)
             else format('O %s não tem a letra %s. Letras: %s.', v_n, v_letra,
                         (select string_agg(o ->> 'letra', ', ' order by ord) from jsonb_array_elements(v_item.opcoes) with ordinality t(o, ord))) end);
    end if;
    update public.parceiro_cartao_itens i set escolha = v_letra, selecionado = true where i.id = v_item.id;
    update public.parceiro_cartoes c set texto = public._parceiro_cartao_texto(c.id, null) where c.id = v_cartao;
    v_texto := format('Anotei *%s %s* (%s). *sim <PIN>* faz.', v_n, v_letra, v_op ->> 'rotulo');
    return jsonb_build_object('ok', true, 'precisa_pin', true, 'texto', v_texto, 'cartao_id', v_cartao);

  elsif v_cmd in ('so', 'sem') then
    if v_ns is null then
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
    end if;
    update public.parceiro_cartao_itens i
       set selecionado = case when v_cmd = 'so' then i.n = any (v_ns) else not (i.n = any (v_ns)) end
     where i.cartao_id = v_cartao and i.estado = 'vivo';
    select array_agg(i.n::integer order by i.n) into v_sel
      from public.parceiro_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.selecionado;
    update public.parceiro_cartoes c set texto = public._parceiro_cartao_texto(c.id, null) where c.id = v_cartao;
    if v_sel is null then
      return jsonb_build_object('ok', true, 'texto', 'Nada ficou selecionado. *parceiro* volta ao cartão inteiro.', 'cartao_id', v_cartao);
    end if;
    return jsonb_build_object('ok', true, 'precisa_pin', true, 'cartao_id', v_cartao,
      'texto', format('Fica %s. *sim <PIN>* faz. *parceiro* volta ao cartão inteiro.',
                      case when cardinality(v_sel) = 1 then format('o %s', v_sel[1]) else 'o ' || array_to_string(v_sel, ' e o ') end));

  elsif v_cmd = 'tirar' then
    v_ns := coalesce(v_ns, case when v_n is not null then array[v_n] end);
    if v_ns is null then
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
    end if;
    for v_y in select i.* from public.parceiro_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.n = any (v_ns) loop
      update public.parceiro_cartao_itens i set estado = 'fora', decidido_em = v_agora where i.id = v_y.id;
      perform public._parceiro_fila_tirar(v_y.fila_id, v_y.tipo, v_agora);
    end loop;
    if public._parceiro_cartao_fechar_se_vazio(v_cartao, v_agora) then
      return jsonb_build_object('ok', true, 'texto', 'Cartão do parceiro fechado: nada foi feito.');
    end if;
    update public.parceiro_cartoes c set texto = public._parceiro_cartao_texto(c.id, null) where c.id = v_cartao;
    return jsonb_build_object('ok', true, 'cartao_id', v_cartao,
      'texto', case when cardinality(v_ns) = 1 then format('Tirei o %s do cartão.', v_ns[1])
                    else format('Tirei o %s do cartão.', array_to_string(v_ns, ' e o ')) end);

  elsif v_cmd = 'ver' then
    if v_n is null then
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
    end if;
    v_texto := concat_ws(E'\n', v_item.texto_mostrado,
                         (select string_agg(x, E'\n' order by o) from jsonb_array_elements_text(
                            case when jsonb_typeof(v_item.retrato -> 'ver') = 'array' then v_item.retrato -> 'ver' else '[]'::jsonb end)
                            with ordinality t(x, o)));
    return jsonb_build_object('ok', true, 'texto', left(v_texto, 3500));

  elsif v_cmd = 'resolvido' then
    return public._parceiro_dito_resolvido(v_n, p_autor, v_agora);

  elsif v_cmd in ('tira_linha', 'sabe') then
    if v_n is null or v_linha is null then
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
    end if;
    if v_item.tipo is distinct from 'painel' then
      return jsonb_build_object('ok', true, 'texto', format('O %s não é o painel: *%s tira L* e *%s sabe L* só valem no painel.', v_n, v_n, v_n));
    end if;
    select * into v_pp from public.parceiro_paineis pp where pp.id = v_item.painel_id for update;
    select l into v_l from jsonb_array_elements(v_pp.linhas) l
     where coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$' and (l ->> 'n')::integer = v_linha limit 1;
    if v_l is null or v_l ->> 'fora_por' is not null then
      return jsonb_build_object('ok', true, 'texto', format('O painel não tem a linha %s.', v_linha));
    end if;
    if v_cmd = 'tira_linha' then
      perform public._parceiro_painel_marcar(v_pp.id, jsonb_build_array(jsonb_build_object('interessado_id', v_l ->> 'interessado_id',
                                                                                             'fora_por', 'tirada')));
      update public.parceiro_paineis pp set editado = true, impressao = public._parceiro_impressao(pp.linhas) where pp.id = v_pp.id;
      -- o item mostra o painel de novo, com o mesmo n
      select count(*) into v_x from jsonb_array_elements((select pp.linhas from public.parceiro_paineis pp where pp.id = v_pp.id)) l
       where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$';
      update public.parceiro_cartao_itens i
         set texto_mostrado = regexp_replace(i.texto_mostrado, ': [0-9]+ veículos', format(': %s veículos', v_x)),
             retrato = jsonb_set(i.retrato, '{ver}', coalesce((select jsonb_agg(case when x like v_linha || '. %' then x || ' [tirada]' else x end order by o)
                                                                 from jsonb_array_elements_text(i.retrato -> 'ver') with ordinality t(x, o)), '[]'::jsonb))
       where i.id = v_item.id;
      update public.parceiro_cartoes c set texto = public._parceiro_cartao_texto(c.id, null) where c.id = v_cartao;
      return jsonb_build_object('ok', true, 'cartao_id', v_cartao, 'texto', format('Tirei a linha %s do painel de hoje.', v_linha));
    end if;
    -- sabe: anotado agora, gravado no *sim <PIN>*
    if v_l ->> 'retida_por' is null then
      return jsonb_build_object('ok', true, 'texto', format('A linha %s não tem novidade esperando o cliente.', v_linha));
    end if;
    update public.parceiro_cartao_itens i
       set retrato = jsonb_set(i.retrato, '{sabe}',
                               (select coalesce(jsonb_agg(distinct x), '[]'::jsonb)
                                  from (select (e #>> '{}')::integer as x from jsonb_array_elements(coalesce(i.retrato -> 'sabe', '[]'::jsonb)) e
                                        union select v_linha) s)),
           selecionado = true
     where i.id = v_item.id;
    return jsonb_build_object('ok', true, 'precisa_pin', true, 'cartao_id', v_cartao,
      'texto', format('Anotado: no *sim <PIN>*, a linha %s sai como o cliente já sabe (%s).', v_linha,
                      replace(v_l ->> 'retida_por', '_', ' ')));
  end if;

  return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
end;
$$;

comment on function public.parceiro_decidir_dito(jsonb, uuid, timestamptz) is
  'Retorno F4 (C-DITO-P): as palavras do dono com o cartão do parceiro vivo: escolher (a letra tem de existir no item), so, sem, tirar (*não N*: o caminho da fila por tipo), ver, resolvido, tira_linha (*N tira L*: fora_por tirada no painel e editado) e sabe (*N sabe L*: anotado, gravado no *sim <PIN>*). Nunca recebe o PIN. Sem cartão: seguir_ao_modelo.';

revoke all on function public.parceiro_decidir_dito(jsonb, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_decidir_dito(jsonb, uuid, timestamptz) to service_role;

-- ── 8. O *sim <PIN>* ──────────────────────────────────────────────────────────────────────────────────────────────────

-- A conferência do item no *sim <PIN>* (e no vigia): os motivos específicos primeiro, depois o hash. Devolve {ok, motivo}.
create or replace function public._parceiro_item_conferir(p_item uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_i public.parceiro_cartao_itens;
  v_parceiro uuid;
  v_ref uuid;
  v_oi public.os_interessados;
  v_ab public.retorno_aberturas;
  v_pp public.parceiro_paineis;
begin
  select * into v_i from public.parceiro_cartao_itens i where i.id = p_item;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  v_ref := case v_i.tipo
    when 'painel' then v_i.painel_id when 'patio' then v_i.numero_id when 'pergunta' then v_i.abertura_id
    when 'pedido' then v_i.pedido_id when 'pdf_mao' then v_i.envio_mao_id when 'repassar' then v_i.service_order_id
    else v_i.interessado_id end;
  select f.parceiro_id into v_parceiro from public.parceiro_fila f where f.id = v_i.fila_id;
  if v_i.interessado_id is not null then
    select * into v_oi from public.os_interessados oi where oi.id = v_i.interessado_id;
    if not found then
      return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
    end if;
    v_parceiro := coalesce(v_parceiro, v_oi.parceiro_id);
  end if;
  if v_parceiro is not null and not exists (select 1 from public.parceiros pa where pa.id = v_parceiro and pa.ativo) then
    return jsonb_build_object('ok', false, 'motivo', 'parceiro_inativo');
  end if;

  if v_i.tipo in ('vinculo', 'retido', 'aviso', 'repassar')
     and public._parceiro_veto_de(v_oi.client_id, v_oi.parceiro_id, v_agora) is not null then
    return jsonb_build_object('ok', false, 'motivo', 'veto');
  end if;
  if v_i.tipo = 'vinculo' and v_oi.situacao is distinct from 'proposto' then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  if v_i.tipo = 'repassar' and (public.parceiro_os_visivel(v_oi.id, v_agora) ->> 'visivel')::boolean is not true then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  if v_i.tipo in ('pergunta', 'pedido') then
    select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;
    if v_ab.id is null or v_ab.estado = 'fechada' then
      return jsonb_build_object('ok', false, 'motivo', 'caso_fechado');
    end if;
    if v_i.tipo = 'pergunta' and v_ab.cumprida_em is not null then
      return jsonb_build_object('ok', false, 'motivo', 'respondida_pelo_dono');
    end if;
  end if;
  if v_i.tipo = 'painel' then
    select * into v_pp from public.parceiro_paineis pp where pp.id = v_i.painel_id;
    if v_pp.id is null or v_pp.estado is distinct from 'aguardando' or v_pp.dia is distinct from v_hoje
       or (v_agora at time zone c_fuso)::time >= v_cfg.painel_janela_fim then
      return jsonb_build_object('ok', false, 'motivo', 'fato_mudou');
    end if;
  end if;
  if v_i.tipo = 'patio' and (v_agora at time zone c_fuso)::time > time '21:59' then
    return jsonb_build_object('ok', false, 'motivo', 'fato_mudou');
  end if;
  if v_ref is null or public._parceiro_item_impressao(v_i.tipo, v_ref, v_agora) is distinct from v_i.hash then
    return jsonb_build_object('ok', false, 'motivo', 'fato_mudou');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public._parceiro_item_conferir(uuid, timestamptz) is
  'Retorno F4 (P8.1): o item ainda vale? Na ordem: vínculo sumido (sem_vinculo), parceiro inativo, veto do par, vínculo fora de proposto ou OS não mais visível ao repassar (sem_vinculo), caso fechado ou cumprido (caso_fechado, respondida_pelo_dono), painel fora de aguardando do dia ou depois da janela e pátio depois das 21:59 (fato_mudou), e o hash do que o item afirma (fato_mudou). {ok, motivo}.';

revoke all on function public._parceiro_item_conferir(uuid, timestamptz) from public, anon, authenticated;

-- O que o *sim <PIN>* faz em cada item (salvo pedido, que mora no parceiro_cartao_executar: só as cinco funções da máquina
-- de estados escrevem em parceiro_pedidos.estado). Devolve {r: feito|sem_letra|falhou|descartado, motivo?, frase, saida_id?}.
create or replace function public._parceiro_item_executar(p_item uuid, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_i public.parceiro_cartao_itens;
  v_op jsonb;
  v_acao text;
  v_r jsonb;
  v_sigla text;
  v_l jsonb;
  v_nova jsonb;
  v_pp public.parceiro_paineis;
  v_linhas jsonb;
  v_s uuid;
  v_modo text;
  v_int uuid;
begin
  select * into v_i from public.parceiro_cartao_itens i where i.id = p_item;
  if v_i.escolha is not null then
    select o into v_op from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = v_i.escolha limit 1;
  end if;
  v_acao := v_op ->> 'acao';
  if v_acao is null and coalesce((v_i.retrato ->> 'exige_letra')::boolean, false) then
    return jsonb_build_object('r', 'sem_letra', 'frase', format('o %s ficou: precisa da letra', v_i.n));
  end if;
  select pa.sigla into v_sigla from public.parceiros pa
   where pa.id = coalesce((select f.parceiro_id from public.parceiro_fila f where f.id = v_i.fila_id),
                          (select oi.parceiro_id from public.os_interessados oi where oi.id = v_i.interessado_id));

  if v_i.tipo = 'vinculo' then
    v_r := case
      when v_acao is null then public._parceiro_confirmar(v_i.interessado_id, p_autor, null, v_agora)
      when v_acao = 'recusar' then public.parceiro_vinculo_cortar(v_i.interessado_id, 'recusar', p_autor, v_agora)
      when v_acao in ('pessoalmente', 'pela_revenda') then public._parceiro_confirmar(v_i.interessado_id, p_autor, v_acao, v_agora)
      when v_acao = 'indicou_pessoalmente' then public._parceiro_confirmar(v_i.interessado_id, p_autor, 'pessoalmente', v_agora, 'indicou')
      when v_acao = 'indicou_pela_revenda' then public._parceiro_confirmar(v_i.interessado_id, p_autor, 'pela_revenda', v_agora, 'indicou')
      when v_acao = 'indicou' then public._parceiro_confirmar(v_i.interessado_id, p_autor, null, v_agora, 'indicou')
      when v_acao = 'anfitria' then public._parceiro_confirmar(v_i.interessado_id, p_autor, null, v_agora, 'anfitria')
    end;
    if v_r is null or not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('r', 'falhou', 'motivo', coalesce(v_r ->> 'motivo', 'erro'));
    end if;
    return jsonb_build_object('r', 'feito',
      'frase', case when v_acao = 'recusar' then format('o %s: recusado para sempre', v_i.n)
                    when v_r ->> 'papel' = 'anfitria' then format('o %s: fica só no pátio, sem aviso e sem painel', v_i.n)
                    when v_r ->> 'aviso' = 'agendado' then format('o %s: ligado à %s; o aviso ao cliente foi agendado', v_i.n, v_sigla)
                    when v_r ->> 'aviso' = 'pendente' then format('o %s: ligado à %s; o cliente segue sem aviso (volta no *parceiro*)', v_i.n, v_sigla)
                    else format('o %s: ligado à %s', v_i.n, v_sigla) end,
      'saida_id', v_r ->> 'saida_id');

  elsif v_i.tipo = 'painel' then
    select * into v_pp from public.parceiro_paineis pp where pp.id = v_i.painel_id for update;
    -- *N sabe L*: grava a palavra do dono e refaz só aquela linha, com o mesmo n
    if jsonb_typeof(v_i.retrato -> 'sabe') = 'array' and jsonb_array_length(v_i.retrato -> 'sabe') > 0 then
      for v_l in select l from jsonb_array_elements(v_pp.linhas) l
                  where l ->> 'fora_por' is null and l ->> 'retida_por' is not null
                    and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$'
                    and (l ->> 'n')::integer in (select (e #>> '{}')::integer from jsonb_array_elements(v_i.retrato -> 'sabe') e) loop
        insert into public.parceiro_cliente_sabe (service_order_id, marco, autor, em)
        values ((v_l ->> 'service_order_id')::uuid, v_l ->> 'retida_por', p_autor, v_agora)
        on conflict (service_order_id, marco) do nothing;
        v_nova := public._parceiro_linha_da_os((v_l ->> 'interessado_id')::uuid, v_agora);
        update public.parceiro_paineis pp
           set linhas = (select jsonb_agg(case when x.v ->> 'interessado_id' = v_l ->> 'interessado_id'
                                               then x.v || jsonb_build_object('estado', v_nova -> 'estado', 'desde', v_nova -> 'desde',
                                                                              'retida_por', v_nova -> 'retida_por')
                                               else x.v end order by x.o)
                           from jsonb_array_elements(pp.linhas) with ordinality x(v, o)),
               editado = true
         where pp.id = v_pp.id;
      end loop;
      update public.parceiro_paineis pp set impressao = public._parceiro_impressao(pp.linhas) where pp.id = v_pp.id;
    end if;
    update public.parceiro_paineis pp
       set estado = 'aprovado', aprovado_em = v_agora
     where pp.id = v_i.painel_id and pp.estado = 'aguardando' and pp.dia = v_hoje;
    if not found then
      return jsonb_build_object('r', 'falhou', 'motivo', 'fato_mudou');
    end if;
    return jsonb_build_object('r', 'feito',
      'frase', case when (v_agora at time zone c_fuso)::time >= v_cfg.painel_hora then format('o %s: painel aprovado; sai em seguida', v_i.n)
                    else format('o %s: painel aprovado; sai às %s', v_i.n, to_char(v_cfg.painel_hora, 'HH24:MI')) end);

  elsif v_i.tipo = 'patio' then
    if v_cfg.segura_patio then
      return jsonb_build_object('r', 'descartado', 'frase', format('o %s: *segura pátio* está ligado; não respondi', v_i.n));
    end if;
    v_linhas := coalesce(v_i.retrato -> 'linhas', '[]'::jsonb);
    if jsonb_array_length(v_linhas) = 0 then
      v_s := public.parceiro_agendar('parceiro_patio', 'vazio', v_i.numero_id, null,
               jsonb_build_object('msg_id', v_i.retrato -> 'msg_id', 'sem_linhas', true, 'dia', v_hoje, 'item_id', v_i.id),
               v_agora, 'parceiro:patio:' || coalesce(v_i.retrato ->> 'msg_id', v_i.id::text), 'resposta_imediata');
    else
      v_s := public.parceiro_agendar('parceiro_patio', 'direto', v_i.numero_id, null,
               jsonb_build_object('msg_id', v_i.retrato -> 'msg_id', 'dia', v_hoje, 'linhas', v_linhas, 'item_id', v_i.id,
                                  'os_ids', (select jsonb_agg(l -> 'service_order_id' order by (l ->> 'n')::integer) from jsonb_array_elements(v_linhas) l),
                                  'interessado_ids', (select jsonb_agg(l -> 'interessado_id' order by (l ->> 'n')::integer) from jsonb_array_elements(v_linhas) l)),
               v_agora, 'parceiro:patio:' || coalesce(v_i.retrato ->> 'msg_id', v_i.id::text), 'resposta_imediata');
    end if;
    if v_s is null then
      return jsonb_build_object('r', 'falhou', 'motivo', 'fato_mudou');
    end if;
    return jsonb_build_object('r', 'feito', 'frase', format('o %s: o pátio sai em seguida', v_i.n), 'saida_id', v_s);

  elsif v_i.tipo = 'pergunta' then
    v_r := public._parceiro_decidir_letra_pergunta(v_i.id, p_autor, v_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('r', 'falhou', 'motivo', coalesce(v_r ->> 'motivo', 'erro'));
    end if;
    return jsonb_build_object('r', 'feito', 'frase', format('o %s: ligada à %s', v_i.n, v_sigla), 'saida_id', v_r ->> 'saida_id');

  elsif v_i.tipo = 'repassar' then
    v_s := public.parceiro_agendar('parceiro_repassar', 'padrao', (v_i.retrato ->> 'numero_id')::uuid, null,
             jsonb_strip_nulls(jsonb_build_object('os_ids', jsonb_build_array(v_i.service_order_id),
                                                  'interessado_ids', jsonb_build_array(v_i.interessado_id),
                                                  'service_order_id', v_i.service_order_id,
                                                  'primeiro_nome', v_i.retrato -> 'primeiro_nome', 'item_id', v_i.id)),
             v_agora, 'parceiro:repassar:' || v_i.service_order_id || ':pronto', 'aviso');
    if v_s is null then
      return jsonb_build_object('r', 'falhou', 'motivo', 'fato_mudou');
    end if;
    select s.modo into v_modo from public.retorno_saidas s where s.id = v_s;
    return jsonb_build_object('r', 'feito', 'saida_id', v_s,
      'frase', case when v_modo = 'sombra' then format('o %s: o repassar ficou em teste (sombra)', v_i.n)
                    else format('o %s: peço à %s para repassar', v_i.n, v_sigla) end);

  elsif v_i.tipo = 'pdf_mao' then
    v_r := public.parceiro_decidir_pdf_mao(v_i.envio_mao_id, v_i.escolha, p_autor, v_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('r', 'falhou', 'motivo', coalesce(v_r ->> 'motivo', 'erro'));
    end if;
    return jsonb_build_object('r', 'feito', 'frase', format('o %s: anotado', v_i.n));

  elsif v_i.tipo = 'aviso' then
    v_r := case v_acao
      when 'pessoalmente' then public.parceiro_aviso_registrar(v_i.interessado_id, 'pessoalmente', p_autor, v_agora)
      when 'pela_revenda' then public.parceiro_aviso_registrar(v_i.interessado_id, 'pela_revenda', p_autor, v_agora)
      when 'reenviar' then public.parceiro_aviso_reenviar(v_i.interessado_id, p_autor, v_agora)
    end;
    if v_r is null or not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('r', 'falhou', 'motivo', coalesce(v_r ->> 'motivo', 'erro'));
    end if;
    return jsonb_build_object('r', 'feito', 'saida_id', v_r ->> 'saida_id',
      'frase', case when v_acao = 'reenviar' then format('o %s: a mensagem de aviso sai de novo', v_i.n)
                    else format('o %s: aviso registrado', v_i.n) end);

  elsif v_i.tipo = 'retido' then
    if v_acao = 'seguir' then
      update public.os_interessados oi set retido_em = null where oi.id = v_i.interessado_id and oi.retido_em is not null;
      if not found then
        return jsonb_build_object('r', 'falhou', 'motivo', 'fato_mudou');
      end if;
      return jsonb_build_object('r', 'feito', 'frase', format('o %s: segue', v_i.n));
    end if;
    v_r := public.parceiro_vinculo_cortar(v_i.interessado_id, 'veto_dono', p_autor, v_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('r', 'falhou', 'motivo', coalesce(v_r ->> 'motivo', 'erro'));
    end if;
    return jsonb_build_object('r', 'feito', 'frase', format('o %s: anotado que o cliente não quer; a %s não vê mais nada dele', v_i.n, v_sigla));

  elsif v_i.tipo = 'corte' then
    v_r := public.parceiro_vinculo_cortar(v_i.interessado_id,
             case v_acao when 'pausar' then 'pausar' when 'retomar' then 'retomar' when 'recusar' then 'recusar' else 'veto_dono' end,
             p_autor, v_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('r', 'falhou', 'motivo', coalesce(v_r ->> 'motivo', 'erro'));
    end if;
    return jsonb_build_object('r', 'feito',
      'frase', format('o %s: %s', v_i.n, case v_acao when 'pausar' then 'pausado' when 'retomar' then 'retomado'
                                                     when 'recusar' then 'cortado para sempre' else 'anotado que o cliente não quer' end));
  end if;
  return jsonb_build_object('r', 'falhou', 'motivo', 'erro');
end;
$$;

comment on function public._parceiro_item_executar(uuid, uuid, timestamptz) is
  'Retorno F4 (P8.1): o *sim <PIN>* de um item conferido (salvo pedido): vinculo (_parceiro_confirmar ou recusar), painel (o *sabe* gravado e aprovado), patio (parceiro_patio), pergunta (_parceiro_decidir_letra_pergunta), repassar (parceiro_repassar), pdf_mao (parceiro_decidir_pdf_mao), aviso (registrar ou reenviar), retido (seguir ou veto_dono) e corte (parceiro_vinculo_cortar). {r: feito|sem_letra|falhou|descartado, motivo, frase, saida_id}.';

revoke all on function public._parceiro_item_executar(uuid, uuid, timestamptz) from public, anon, authenticated;

-- C-EXEC-P: o *sim <PIN>* do cartão do parceiro. Só o dono. Item fora da seleção volta à fila; o que caiu na conferência sai
-- com o motivo; cada um faz o seu. O item pedido (P10) mora aqui: marca, leva o pedido a decidido, copia o número autorizado
-- (conferindo de novo que não é de outro cliente) e devolve "orcamentos"; quem cria e manda é a ferramenta (P12).
create or replace function public.parceiro_cartao_executar(p_cartao uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_c public.parceiro_cartoes;
  v_i public.parceiro_cartao_itens;
  v_conf jsonb;
  v_r jsonb;
  v_frases text[] := '{}';
  v_saidas jsonb := '[]'::jsonb;
  v_orcamentos jsonb := '[]'::jsonb;
  v_motivo text;
  v_ped public.parceiro_pedidos;
  v_op jsonb;
  v_destino text;
  v_dup boolean;
  v_chave text;
  v_feitos integer := 0;
  v_aviso text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'aviso', 'Só o dono executa o cartão do parceiro.');
  end if;
  select * into v_c from public.parceiro_cartoes c where c.id = p_cartao for update;
  if not found or v_c.estado <> 'vivo' then
    return jsonb_build_object('ok', false, 'aviso', 'Esse cartão já foi decidido.');
  end if;

  for v_i in select i.* from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo' order by i.n loop
    begin
      -- fora da seleção (so, sem): volta à fila, com vezes já somado
      if not v_i.selecionado then
        update public.parceiro_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        perform public._parceiro_fila_marcar(v_i.fila_id, 'espera', null, v_agora);
        continue;
      end if;
      v_conf := public._parceiro_item_conferir(v_i.id, v_agora);
      if not coalesce((v_conf ->> 'ok')::boolean, false) then
        v_motivo := v_conf ->> 'motivo';
        update public.parceiro_cartao_itens i set estado = 'caiu', caiu_motivo = v_motivo, decidido_em = v_agora where i.id = v_i.id;
        -- o fato que mudou volta à fila (quem confere a validade é _parceiro_fila_conferir); o resto cai
        perform public._parceiro_fila_marcar(v_i.fila_id, case when v_motivo = 'fato_mudou' then 'espera' else 'caiu' end, null, v_agora);
        v_frases := v_frases || format('o %s caiu: %s', v_i.n, case v_motivo
          when 'veto' then 'o cliente disse não ao parceiro'
          when 'respondida_pelo_dono' then 'você já respondeu'
          when 'sem_vinculo' then 'o vínculo mudou'
          when 'parceiro_inativo' then 'o parceiro foi desativado'
          when 'caso_fechado' then 'a conversa já fechou'
          else 'mudou desde que você viu; volta no próximo *parceiro*' end);
        continue;
      end if;

      if v_i.tipo = 'pedido' then
        -- P10.1, "Ordem no *sim <PIN>*", passo 1.
        select * into v_ped from public.parceiro_pedidos pp where pp.id = v_i.pedido_id for update;
        if v_i.escolha is not null then
          select o into v_op from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = v_i.escolha limit 1;
        else
          v_op := null;
        end if;
        if v_op is null then
          update public.parceiro_cartao_itens i set estado = 'fora' where i.id = v_i.id;
          perform public._parceiro_fila_marcar(v_i.fila_id, 'espera', null, v_agora);
          v_frases := v_frases || format('o %s ficou: precisa da letra', v_i.n);
          continue;
        end if;
        if v_op ->> 'acao' = 'desfazer' then
          v_r := public.parceiro_pedido_desfazer(v_ped.id, p_autor, v_agora);
          if not coalesce((v_r ->> 'ok')::boolean, false) then
            -- a letra D não vale mais (o cliente ganhou OS, o pedido saiu do cartão): o item cai e nada muda
            update public.parceiro_cartao_itens i set estado = 'caiu', caiu_motivo = 'fato_mudou', decidido_em = v_agora where i.id = v_i.id;
            perform public._parceiro_fila_marcar(v_i.fila_id, 'espera', null, v_agora);
            v_frases := v_frases || format('o %s não foi: %s', v_i.n, replace(coalesce(v_r ->> 'motivo', 'erro'), '_', ' '));
            continue;
          end if;
          update public.parceiro_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
          perform public._parceiro_fila_marcar(v_i.fila_id, 'feito', null, v_agora);
          v_frases := v_frases || format('o %s: cadastro desfeito', v_i.n);
          v_feitos := v_feitos + 1;
          continue;
        end if;
        v_destino := case when v_op ->> 'acao' = 'parceiro' then 'parceiro' else 'cliente' end;
        if v_cfg.parceiro_modo is distinct from 'ligado' or public._retorno_fora_do_horario_de_envio(v_agora)
           or (v_destino = 'parceiro' and not v_cfg.pdf_parceiro_ligado) then
          update public.parceiro_cartao_itens i set estado = 'fora' where i.id = v_i.id;
          perform public._parceiro_fila_marcar(v_i.fila_id, 'espera', null, v_agora);
          v_frases := v_frases || (case when v_cfg.parceiro_modo is distinct from 'ligado' then format('o %s: o parceiro está em teste; não criei nada', v_i.n)
                                        when v_destino = 'parceiro' and not v_cfg.pdf_parceiro_ligado then format('o %s: o PDF ao parceiro está desligado; nada saiu', v_i.n)
                                        else format('o %s: fora do horário de envio; não criei nada. Mande *parceiro* a partir das 8h', v_i.n) end);
          continue;
        end if;
        -- o número que a MP passou: confere de novo que não é de outro cliente ativo
        v_chave := public._agenda_chave_telefone(v_ped.whatsapp_informado);
        v_dup := v_chave is not null and exists (
          select 1 from public.clients c
           where c.active and c.id is distinct from v_ped.client_id
             and public._agenda_chave_telefone(coalesce(nullif(btrim(c.whatsapp), ''), c.phone)) = v_chave);
        if v_dup and v_destino = 'cliente' then
          update public.parceiro_cartao_itens i set estado = 'fora' where i.id = v_i.id;
          perform public._parceiro_fila_marcar(v_i.fila_id, 'espera', null, v_agora);
          v_frases := v_frases || format('o %s: o número que a %s passou já é de outro cliente; nada saiu', v_i.n,
                                         (select pa.sigla from public.parceiros pa where pa.id = v_ped.parceiro_id));
          continue;
        end if;
        if not v_dup and v_chave is not null and v_ped.client_id is not null then
          update public.clients c
             set whatsapp = v_ped.whatsapp_informado
           where c.id = v_ped.client_id and coalesce(btrim(c.whatsapp), '') = '';
        end if;
        update public.parceiro_pedidos pp
           set estado = 'decidido', completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = now()
         where pp.id = v_ped.id and pp.estado = 'cartao';
        v_orcamentos := v_orcamentos || jsonb_build_array(jsonb_build_object(
          'item_id', v_i.id, 'n', v_i.n, 'pedido_id', v_ped.id, 'previa_id', v_i.retrato -> 'previa_id',
          'acao', v_i.retrato ->> 'acao', 'service_order_id', v_i.retrato -> 'service_order_id',
          'numero', v_i.retrato -> 'numero', 'destino', v_destino, 'parceiro_id', v_ped.parceiro_id,
          'sem_enviar', v_destino = 'parceiro' and not v_cfg.pdf_sem_espera_ligado,
          'rotulo', public._retorno_rotulo(v_ped.abertura_id, v_agora)));
        update public.parceiro_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
        perform public._parceiro_fila_marcar(v_i.fila_id, 'feito', null, v_agora);
        v_feitos := v_feitos + 1;
        continue;
      end if;

      v_r := public._parceiro_item_executar(v_i.id, p_autor, v_agora);
      if v_r ->> 'r' = 'feito' then
        update public.parceiro_cartao_itens i
           set estado = 'feito', decidido_em = v_agora, saida_id = nullif(v_r ->> 'saida_id', '')::uuid
         where i.id = v_i.id;
        perform public._parceiro_fila_marcar(v_i.fila_id, 'feito', null, v_agora);
        if nullif(v_r ->> 'saida_id', '') is not null then
          v_saidas := v_saidas || jsonb_build_array(v_r ->> 'saida_id');
        end if;
        v_feitos := v_feitos + 1;
      elsif v_r ->> 'r' = 'sem_letra' then
        update public.parceiro_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        perform public._parceiro_fila_marcar(v_i.fila_id, 'espera', null, v_agora);
      elsif v_r ->> 'r' = 'descartado' then
        update public.parceiro_cartao_itens i set estado = 'fora', decidido_em = v_agora where i.id = v_i.id;
        perform public._parceiro_fila_marcar(v_i.fila_id, 'caiu', null, v_agora);
      else
        v_motivo := case v_r ->> 'motivo'
          when 'veto' then 'veto'
          when 'parceiro_inativo' then 'parceiro_inativo'
          when 'sem_vinculo' then 'sem_vinculo' when 'nao_proposto' then 'sem_vinculo' when 'nao_confirmado' then 'sem_vinculo'
          when 'nao_pausado' then 'sem_vinculo' when 'ja_decidido' then 'sem_vinculo'
          else 'fato_mudou' end;
        update public.parceiro_cartao_itens i set estado = 'caiu', caiu_motivo = v_motivo, decidido_em = v_agora where i.id = v_i.id;
        perform public._parceiro_fila_marcar(v_i.fila_id, case when v_motivo = 'fato_mudou' then 'espera' else 'caiu' end, null, v_agora);
        v_frases := v_frases || format('o %s não foi: %s', v_i.n, replace(coalesce(v_r ->> 'motivo', 'erro'), '_', ' '));
        continue;
      end if;
      if v_r ->> 'frase' is not null then
        v_frases := v_frases || (v_r ->> 'frase');
      end if;
    exception when others then
      -- erro nunca trava o cartão: o item volta à fila, e o próximo segue
      update public.parceiro_cartao_itens i set estado = 'fora' where i.id = v_i.id;
      perform public._parceiro_fila_marcar(v_i.fila_id, 'espera', null, v_agora);
      v_frases := v_frases || format('o %s não foi: erro', v_i.n);
      perform public._retorno_log('parceiro_cartao', 'parceiro_cartao_executar: ' || sqlerrm, 'error',
                                  jsonb_build_object('item', v_i.id, 'tipo', v_i.tipo, 'sqlstate', sqlstate));
    end;
  end loop;

  update public.parceiro_cartoes c set estado = 'decidido', decidido_em = v_agora, decidido_por = 'sim_pin' where c.id = p_cartao;
  -- a fila que ficou em no_cartao (nunca deveria) volta a espera; o ponteiro e a pergunta fecham com a pendência, que a
  -- ferramenta marca executada (como na F2), e o caminho preguiçoso de parceiro_cartao_vivo
  update public.parceiro_fila f
     set estado = 'espera', decidido_em = null
   where f.estado = 'no_cartao'
     and f.id in (select i.fila_id from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.fila_id is not null);

  v_aviso := nullif(array_to_string(v_frases, ' · '), '');
  if v_feitos = 0 and v_aviso is null then
    v_aviso := 'Nada para fazer neste cartão: escolha a letra antes do *sim*. *parceiro* abre de novo.';
  end if;
  v_aviso := concat_ws(' ', v_aviso, case when v_c.mais > 0 then format('Mais %s esperando: *parceiro*.', v_c.mais) end);
  return jsonb_build_object('ok', true, 'aviso', v_aviso, 'saidas', v_saidas, 'pdfs', '[]'::jsonb, 'orcamentos', v_orcamentos);
end;
$$;

comment on function public.parceiro_cartao_executar(uuid, uuid, timestamptz) is
  'Retorno F4 (C-EXEC-P): o *sim <PIN>* do cartão do parceiro. Só o dono. Fora da seleção → fila espera; conferência que falha → item caiu com o motivo (fato_mudou volta à fila, o resto cai); sem letra onde a letra é exigida → fila espera; feito → fila feito. O item pedido (P10): letra D desfaz; A e B levam o pedido a decidido, copiam o número autorizado (se não for de outro cliente) e entram em orcamentos. {ok, aviso, saidas, pdfs (sempre vazio), orcamentos}.';

revoke all on function public.parceiro_cartao_executar(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_cartao_executar(uuid, uuid, timestamptz) to service_role;

-- C-ITEM do parceiro: o par de retorno_item_enviado (F2) sobre parceiro_cartao_itens. ok fecha o caso do item (cumprido pelo
-- cartão) e cancela as agendadas dele; falha devolve o item a fora.
create or replace function public.parceiro_item_enviado(p_item uuid, p_ok boolean, p_wa_id text default null, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.parceiro_cartao_itens;
begin
  select * into v_i from public.parceiro_cartao_itens i where i.id = p_item for update;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  if not coalesce(p_ok, false) then
    update public.parceiro_cartao_itens i set estado = 'fora' where i.id = p_item;
    return jsonb_build_object('ok', true);
  end if;
  if v_i.abertura_id is not null then
    update public.retorno_aberturas a
       set cumprida_em = coalesce(a.cumprida_em, v_agora), cumprida_por = coalesce(a.cumprida_por, 'cartao'),
           estado = 'fechada', fechada_em = coalesce(a.fechada_em, v_agora), fechada_motivo = coalesce(a.fechada_motivo, 'conteudo'),
           atualizada_em = now()
     where a.id = v_i.abertura_id;
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
     where s.abertura_id = v_i.abertura_id and s.estado = 'agendada';
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.parceiro_item_enviado(uuid, boolean, text, timestamptz) is
  'Retorno F4 (P8): o par de retorno_item_enviado sobre parceiro_cartao_itens. ok cumpre e fecha o caso do item e cancela as agendadas; falha devolve o item a fora.';

revoke all on function public.parceiro_item_enviado(uuid, boolean, text, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_item_enviado(uuid, boolean, text, timestamptz) to service_role;

-- O passo do cartão no parceiro_vigia, a cada minuto e em qualquer parceiro_modo: o caminho preguiçoso (pendência acabada),
-- o cartão vivo vencido (expirou) e o vivo sem item vivo (caiu).
create or replace function public.parceiro_vigia_cartao(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_vivo jsonb;
  v_c public.parceiro_cartoes;
  v_acao text := 'nada';
begin
  v_vivo := public.parceiro_cartao_vivo(v_agora);
  if v_vivo is not null then
    select * into v_c from public.parceiro_cartoes c where c.id = (v_vivo ->> 'id')::uuid;
    if v_c.expira_em < v_agora then
      perform public._parceiro_cartao_encerrar(v_c.id, 'expirou', 'expired', 'cartao_expirou', v_agora);
      v_acao := 'expirou';
    elsif not exists (select 1 from public.parceiro_cartao_itens i where i.cartao_id = v_c.id and i.estado = 'vivo') then
      perform public._parceiro_cartao_encerrar(v_c.id, 'caiu', 'rejected', 'cartao_caiu', v_agora);
      v_acao := 'caiu';
    end if;
  end if;
  return jsonb_build_object('ok', true, 'rodou', true, 'acao', v_acao, 'cartao_id', v_c.id);
end;
$$;

comment on function public.parceiro_vigia_cartao(timestamptz) is
  'Retorno F4 (P8.1): no parceiro_vigia, em qualquer parceiro_modo. parceiro_cartao_vivo (o caminho preguiçoso); vivo com expira_em vencido → _parceiro_cartao_encerrar(expirou, expired, cartao_expirou); vivo sem item vivo → (caiu, rejected, cartao_caiu).';

revoke all on function public.parceiro_vigia_cartao(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_vigia_cartao(timestamptz) to service_role;

-- ── 9. Gerado do corpo vigente, com os trechos -- F4 ────────────────────────────────────────────────────────────────────

create or replace function public.retorno_dito(p_comando jsonb, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cmd text := p_comando ->> 'comando';
  v_alvo text := p_comando ->> 'alvo';
  v_cfg public.retorno_config;
  v_texto text;
  v_user text;
  v_r jsonb;
  v_ate date;
  v_ate_ts timestamptz;
  v_k integer;
  v_antes jsonb;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;

  case v_cmd
    when 'retorno' then
      v_r := public.retorno_cartao_abrir('puxar', v_agora);
      return jsonb_build_object('ok', true,
        'texto', coalesce(v_r ->> 'texto', 'Ninguém esperando agora.'),
        'cartao_id', v_r ->> 'cartao_id',
        'historico', v_r -> 'historico');

    when 'ver' then
      return public.retorno_ver_caso((p_comando ->> 'n')::integer, p_autor, v_agora);

    when 'segura' then
      if v_alvo = 'recibos' then
        update public.retorno_config set segura_recibos = true, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Segurei os recibos: quem escrever agora não recebe recibo, saudação nem coleta, nem depois que você soltar. *solta recibos* vale para as próximas mensagens.';
      elsif v_alvo = 'tudo' then
        v_ate_ts := v_agora + interval '24 hours';
        update public.retorno_config set segura_tudo_ate = v_ate_ts, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := format('Segurei tudo por 24 h, até %s às %s: nada automático do retorno sai ao cliente. *solta tudo* volta antes.',
                          public._retorno_quando((v_ate_ts at time zone c_fuso)::date, v_hoje),
                          to_char(v_ate_ts at time zone c_fuso, 'HH24:MI'));
        if not exists (select 1 from pg_proc p where p.proname = '_agenda_retorno_segurou') then
          v_texto := v_texto || ' A agenda ainda manda o que já estava aprovado: *segura cliente* segura.';
        end if;
      elsif v_alvo in ('patio', 'pátio') then
        -- F4 (P8): *segura pátio*. O *pátio* do parceiro é recusado sem resposta (segura_patio) e o recibo sai sem o pátio.
        v_alvo := 'patio';
        update public.retorno_config set segura_patio = true, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Segurei o pátio: o parceiro que mandar *pátio* não recebe a lista, e o recibo sai sem o pátio de hoje. *solta pátio* volta.';
      else
        return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
      end if;
      v_user := 'segura ' || v_alvo;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_recibos', v_cfg.segura_recibos, 'segura_tudo_ate', v_cfg.segura_tudo_ate),
        jsonb_build_object('alvo', v_alvo), '*segura* do dono');
      -- F4 (P8): o antes do pátio também fica na auditoria.
      if v_alvo = 'patio' then
        perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_patio', v_cfg.segura_patio),
          jsonb_build_object('alvo', v_alvo), '*segura pátio* do dono');
      end if;

    when 'solta' then
      if v_alvo = 'recibos' then
        update public.retorno_config set segura_recibos = false, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Recibos soltos: valem para as próximas mensagens.';
      elsif v_alvo = 'tudo' then
        update public.retorno_config
           set segura_tudo_ate = null, segura_recibos = false, atualizado_em = now(), atualizado_por = p_autor;
        update public.retorno_saidas s
           set enviar_em = v_agora, atualizada_em = now()
         where s.estado = 'agendada' and s.dados ? 'segurada';
        get diagnostics v_k = row_count;
        v_texto := case when v_k = 0 then 'Soltei: o automático volta a sair.'
                        else format('Soltei: o automático volta a sair. %s que ficaram no meio saem agora; quem escreveu há mais de 12 h fica com você.', v_k) end;
      elsif v_alvo in ('patio', 'pátio') then
        -- F4 (P8): *solta pátio*. Vale para os próximos pedidos de *pátio* e para o próximo recibo.
        v_alvo := 'patio';
        update public.retorno_config set segura_patio = false, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Pátio solto: o parceiro volta a receber a lista quando mandar *pátio*.';
      else
        return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
      end if;
      v_user := 'solta ' || v_alvo;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_recibos', v_cfg.segura_recibos, 'segura_tudo_ate', v_cfg.segura_tudo_ate),
        jsonb_build_object('alvo', v_alvo), '*solta* do dono');
      -- F4 (P8): o antes do pátio também fica na auditoria.
      if v_alvo = 'patio' then
        perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_patio', v_cfg.segura_patio),
          jsonb_build_object('alvo', v_alvo), '*solta pátio* do dono');
      end if;

    when 'fora_ate' then
      begin
        v_r := public.agenda_data_dita(p_comando ->> 'dia', v_hoje, 'futuro');
        v_ate := (v_r ->> 'ate')::date;
      exception when data_exception then
        v_ate := null;
      end;
      v_user := 'fora até ' || coalesce(p_comando ->> 'dia', '');
      if v_ate is null or v_ate < v_hoje then
        return jsonb_build_object('ok', true, 'texto', 'Não entendi o dia. Diga *fora até quarta* ou *fora até 25/11*.');
      end if;
      if v_ate = v_hoje then
        update public.retorno_config set fora_ate = null, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Anotado: você voltou, e o recibo volta ao normal.';
      else
        update public.retorno_config set fora_ate = v_ate, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := format('Anotado: até %1$s o recibo diz que você está fora e que retorna %2$s. *fora até hoje* desfaz.',
                          public._retorno_quando(v_ate, v_hoje),
                          public._retorno_quando_fala(public._retorno_quando(v_ate, v_hoje), public._retorno_hora(v_cfg.promessa_manha)));
      end if;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('fora_ate', v_cfg.fora_ate),
        jsonb_build_object('fora_ate', case when v_ate = v_hoje then null else v_ate end), '*fora até* do dono');

    when 'libera' then
      v_r := public._retorno_dito_libera(p_comando, p_autor, v_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) is false then
        return v_r;
      end if;
      perform public._retorno_toque('libera', null, null, v_agora);
      v_texto := v_r ->> 'texto';
      v_user := 'libera ' || coalesce(v_alvo, '');

    when 'errado' then
      v_r := public._retorno_dito_errado(upper(coalesce(p_comando ->> 'letra', '')), v_agora);
      v_texto := v_r ->> 'texto';
      v_user := 'errado ' || coalesce(p_comando ->> 'letra', '');

    when 'pessoal' then
      v_r := public._retorno_dito_pessoal((p_comando ->> 'n')::integer, p_autor, v_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) is false then
        return v_r;
      end if;
      v_texto := v_r ->> 'texto';
      v_user := 'pessoal';

    when 'resolvido' then
      v_r := public._retorno_dito_resolvido((p_comando ->> 'n')::integer, p_autor, v_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) is false then
        return v_r;
      end if;
      v_texto := v_r ->> 'texto';
      v_user := 'resolvido ' || coalesce(p_comando ->> 'n', '');

    when 'pessoal_desfaz' then
      v_antes := v_cfg.pessoal_ultimo;
      if v_antes is null or v_agora - (v_antes ->> 'em')::timestamptz > interval '24 hours' then
        return jsonb_build_object('ok', true, 'texto', 'Não há *pessoal* recente para desfazer.');
      end if;
      update public.whatsapp_leads l
         set lead_tipo = v_antes ->> 'lead_tipo_antes', updated_at = now()
       where l.phone_normalized = v_antes ->> 'phone';
      update public.retorno_config set pessoal_ultimo = null, atualizado_em = now(), atualizado_por = p_autor;
      perform public._retorno_auditar_palavra(p_autor, v_antes, jsonb_build_object('lead_tipo', v_antes ->> 'lead_tipo_antes'),
        '*pessoal não* do dono');
      v_texto := 'Pronto: esse número volta a receber automático.';
      v_user := 'pessoal não';

    else
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end case;

  return jsonb_build_object('ok', true, 'texto', v_texto,
    'historico', jsonb_build_object('user', v_user, 'assistant', v_texto));
end;
$$;

comment on function public.retorno_dito(jsonb, uuid, timestamptz) is
  'Retorno F2 (C-PAL) e F4 (P8): as palavras do dono sem cartão, agora com *segura pátio* e *solta pátio* (retorno_config.segura_patio). {"ok", "texto", "historico"?, "cartao_id"?, "seguir_ao_modelo"?}. Só o dono: outro autor recebe {"ok": false, "motivo": "nao_e_o_dono"}. O historico nunca leva texto do cliente.';

revoke all on function public.retorno_dito(jsonb, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_dito(jsonb, uuid, timestamptz) to service_role;
