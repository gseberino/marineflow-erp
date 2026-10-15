-- Secretário, Passo 2 (15/10/2026): a manhã nova do resumo, o registro do que foi mostrado ao dono e
-- do que ele fez com cada item, e a chave resumo_formato.
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md
--
-- A manhã nova escolhe por regras fixas (sem IA) até 3 itens que pedem o dono e guarda o resto numa
-- lista, com letras (A, B, C… — letras porque "1"/"2" já são sim/não da confirmação). O registro serve a
-- três coisas: os comandos do dono durante o dia ("A feito", "B amanhã", "tira C", "lista"), a regra de
-- repetição (2º dia só com fato novo) e as métricas (item mostrado × o que o dono fez).
--   * resumo_manha: uma linha por dia e telefone (o texto novo, o antigo — o comando *tudo* —, a
--     papelada do escritório contada na montagem);
--   * resumo_itens: cada item do dia, com a letra, o fato (impressão digital: mudou = fato novo) e a ação
--     do dono (feito, adiado, nao, tirado, ignorado);
--   * resumo_registrar / resumo_item_acao / resumo_item_voltar: as únicas escritas, só pelo servidor.
--
-- GRAVA DADO — OK NOMEADO: uma chave em app_settings ('resumo_formato' = 'antigo', bloco 4). Nasce no
-- formato de hoje: com 'antigo' nada muda (o resumo sai byte a byte igual e nada é gravado aqui).
-- Recria o gatilho _app_settings_chaves_do_dono com a chave nova (só o admin muda o formato). O corpo
-- de antes foi conferido em produção em 15/10/2026: md5 do prosrc normalizado (A-Z → minúscula, sem
-- espaços) = 06df6dda5b05f5b1112a7de9b44da69b, igual ao de 20261011200000_comprovantes_conversa_base.sql.
-- Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. resumo_manha: uma por dia e telefone
-- ---------------------------------------------------------------------------------------------
create table if not exists public.resumo_manha (
  id               uuid primary key default gen_random_uuid(),
  dia              date not null,
  phone_normalized text not null,
  app_user_id      uuid references public.app_users(id) on delete set null,
  modo             text not null,
  tipo_do_dia      text not null default 'util',
  texto_novo       text not null,
  -- o resumo de sempre, como saiu (ou sairia) no dia: é o comando *tudo*
  texto_antigo     text,
  -- a papelada contada na montagem: é o comando *escritório*
  escritorio       text,
  enviado          boolean not null default false,
  itens_manha      smallint not null default 0,
  itens_lista      smallint not null default 0,
  -- assuntos guardados que passaram das 21 letras (só contados)
  sem_letra        smallint not null default 0,
  criado_em        timestamptz not null default now(),
  constraint resumo_manha_um_por_dia unique (dia, phone_normalized),
  constraint resumo_manha_phone_chk check (phone_normalized ~ '^[0-9]{10,15}$'),
  constraint resumo_manha_modo_chk check (modo in ('sombra', 'novo')),
  constraint resumo_manha_tipo_do_dia_chk check (tipo_do_dia in ('util', 'domingo', 'feriado')),
  constraint resumo_manha_texto_novo_chk check (char_length(texto_novo) between 1 and 4000),
  constraint resumo_manha_texto_antigo_chk check (texto_antigo is null or char_length(texto_antigo) <= 20000),
  constraint resumo_manha_escritorio_chk check (escritorio is null or char_length(escritorio) <= 2000),
  constraint resumo_manha_contagens_chk check (itens_manha between 0 and 3 and itens_lista between 0 and 21 and sem_letra >= 0),
  -- a sombra nunca é enviada
  constraint resumo_manha_enviado_chk check (modo = 'novo' or not enviado)
);

comment on table public.resumo_manha is
  'Secretário (Passo 2, 15/10/2026): a manhã nova de cada dia e telefone — o texto novo, o antigo (comando tudo) e a papelada (comando escritório). Modo sombra = gravado e não enviado, para a comparação lado a lado. Só o admin lê; escrita só pela RPC resumo_registrar (service_role).';

-- ---------------------------------------------------------------------------------------------
-- 2. resumo_itens: cada item do dia e o que o dono fez
-- ---------------------------------------------------------------------------------------------
create table if not exists public.resumo_itens (
  id               uuid primary key default gen_random_uuid(),
  resumo_id        uuid not null references public.resumo_manha(id) on delete cascade,
  dia              date not null,
  phone_normalized text not null,
  modo             text not null,
  letra            text not null,
  -- o item que o dono vê com a letra; os outros do mesmo assunto (cliente/OS) vão junto, com a mesma letra
  principal        boolean not null default true,
  posicao          text not null,
  ordem            smallint not null,
  familia          text not null,
  tipo             text not null,
  secao            text not null,
  -- o que o item é (recv:<uuid>, os:<uuid>, fone:<telefone>) e de quem (cliente:<uuid>, os:<uuid>, fone:…)
  referencia       text not null,
  assunto          text not null,
  nome             text not null,
  -- o nome sem acento e minúsculo: o "volta Flávio"
  nome_busca       text not null,
  -- a impressão digital do fato (saldo+vencimento, última mensagem, status+valor…): mudou = fato novo
  fato             text not null,
  valor            numeric(14,2),
  titulo           text not null,
  recomendacao     text,
  motivo           text not null,
  -- o texto que vai ao assistente quando o dono manda só a letra (o cartão pronto, pelo caminho de sempre)
  pedido           text,
  detalhe          jsonb not null default '{}'::jsonb,
  acao             text,
  acao_em          timestamptz,
  adiado_ate       date,
  voltou_em        timestamptz,
  historico        jsonb not null default '[]'::jsonb,
  criado_em        timestamptz not null default now(),
  constraint resumo_itens_phone_chk check (phone_normalized ~ '^[0-9]{10,15}$'),
  constraint resumo_itens_modo_chk check (modo in ('sombra', 'novo')),
  -- A–Z sem N e S ("não" e "sim" da confirmação), sem E (o "É" sozinho, de "é isso", vira "e" sem
  -- acento) e sem I e O (parecem 1 e 0): 21 letras
  constraint resumo_itens_letra_chk check (letra ~ '^[A-DF-HJ-MP-RT-Z]$'),
  constraint resumo_itens_posicao_chk check (posicao in ('manha', 'lista')),
  constraint resumo_itens_ordem_chk check (ordem >= 0),
  constraint resumo_itens_familia_chk check (familia in ('cobranca', 'cliente', 'contato', 'orcamento', 'os')),
  constraint resumo_itens_tipo_chk check (tipo in (
    'cobranca_grande', 'cobranca_marco', 'cobranca_fora_do_marco', 'cobranca_antiga',
    'cliente_sem_resposta', 'cliente_recente', 'contato_pedindo_preco', 'contato_sem_cadastro', 'fornecedor',
    'orcamento_parado', 'orcamento_vencendo', 'orcamento_nao_enviado', 'orcamento_na_lista',
    'os_esperando_compra', 'os_sem_cobranca', 'os_parada')),
  constraint resumo_itens_secao_chk check (secao in ('dinheiro', 'clientes', 'obras', 'contatos')),
  constraint resumo_itens_referencia_chk check (char_length(referencia) between 3 and 120),
  constraint resumo_itens_assunto_chk check (char_length(assunto) between 3 and 120),
  constraint resumo_itens_nome_chk check (char_length(nome) between 1 and 120),
  constraint resumo_itens_nome_busca_chk check (nome_busca ~ '^[a-z0-9 ]{0,120}$'),
  constraint resumo_itens_fato_chk check (char_length(fato) between 1 and 300),
  constraint resumo_itens_titulo_chk check (char_length(titulo) between 1 and 600),
  constraint resumo_itens_recomendacao_chk check (recomendacao is null or char_length(recomendacao) <= 300),
  constraint resumo_itens_motivo_chk check (char_length(motivo) between 1 and 600),
  constraint resumo_itens_pedido_chk check (pedido is null or char_length(pedido) <= 1000),
  constraint resumo_itens_detalhe_chk check (jsonb_typeof(detalhe) = 'object' and octet_length(detalhe::text) <= 8192),
  constraint resumo_itens_historico_chk check (jsonb_typeof(historico) = 'array' and octet_length(historico::text) <= 8192),
  constraint resumo_itens_acao_chk check (acao is null or acao in ('feito', 'adiado', 'nao', 'tirado', 'ignorado')),
  constraint resumo_itens_acao_em_chk check ((acao is null) = (acao_em is null)),
  constraint resumo_itens_adiado_chk check ((acao is not distinct from 'adiado') = (adiado_ate is not null))
);

comment on table public.resumo_itens is
  'Secretário (Passo 2, 15/10/2026): cada item da manhã nova (manhã ou lista), com a letra do dia, o fato (mudou = fato novo) e o que o dono fez (feito, adiado, nao, tirado; ignorado = item de manhã sem ação até a manhã seguinte). Base dos comandos, da regra de repetição e das métricas. Só o admin lê; escrita só pelas RPCs resumo_* (service_role).';
comment on column public.resumo_itens.fato is 'Impressão digital do fato do item (ex.: saldo + vencimento + marco; hora da última mensagem). Outro valor no dia seguinte = fato novo.';
comment on column public.resumo_itens.voltou_em is 'O dono mandou "volta X": o que veio antes desta hora não conta na regra de repetição.';

create unique index if not exists resumo_itens_letra_do_dia
  on public.resumo_itens (resumo_id, letra) where principal;
create index if not exists resumo_itens_referencia
  on public.resumo_itens (phone_normalized, modo, referencia, dia);
create index if not exists resumo_itens_do_dia
  on public.resumo_itens (phone_normalized, dia, letra);
create index if not exists resumo_itens_com_acao
  on public.resumo_itens (phone_normalized, modo, acao_em) where acao is not null;
create index if not exists resumo_itens_resumo on public.resumo_itens (resumo_id);

-- ---------------------------------------------------------------------------------------------
-- 3. RLS e privilégios (revogar de anon/authenticated POR NOME)
-- ---------------------------------------------------------------------------------------------
alter table public.resumo_manha enable row level security;
alter table public.resumo_itens enable row level security;

revoke all on table public.resumo_manha from public, anon, authenticated;
grant select on table public.resumo_manha to authenticated;
grant all on table public.resumo_manha to service_role;
drop policy if exists resumo_manha_admin_le on public.resumo_manha;
create policy resumo_manha_admin_le on public.resumo_manha
  for select to authenticated using (public.is_admin((select auth.uid())));

revoke all on table public.resumo_itens from public, anon, authenticated;
grant select on table public.resumo_itens to authenticated;
grant all on table public.resumo_itens to service_role;
drop policy if exists resumo_itens_admin_le on public.resumo_itens;
create policy resumo_itens_admin_le on public.resumo_itens
  for select to authenticated using (public.is_admin((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 4. GRAVA DADO — OK NOMEADO: a chave do formato. Nasce 'antigo'.
--    Três fontes do mesmo padrão: esta linha, o 'antigo' de _shared/secretario/formato.ts (chave
--    ausente ou inválida = antigo) e a ausência da chave.
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('resumo_formato', 'antigo',
   'Resumo da manhã: antigo = o de sempre; sombra = envia o de sempre e GUARDA o novo (resumo_manha) para comparar; novo = o dono recebe o novo (até 3 itens com letra, lista e comandos) e "tudo" devolve o de sempre. Voltar atrás = antigo.')
on conflict (key) do nothing;

-- Igual ao de 20261011200000 (conferido em produção), com a chave nova no fim.
create or replace function public._app_settings_chaves_do_dono()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and not public.is_admin(v_uid) then
    if (tg_op <> 'INSERT' and old.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo'))
       or (tg_op <> 'DELETE' and new.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo')) then
      raise exception 'Só o administrador muda o salário mínimo e a regra do pró-labore.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_fluxo')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_fluxo') then
      raise exception 'Só o administrador liga ou desliga o fluxo de comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_conversa')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_conversa') then
      raise exception 'Só o administrador liga ou desliga a conversa dos comprovantes.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'resumo_formato')
       or (tg_op <> 'DELETE' and new.key = 'resumo_formato') then
      raise exception 'Só o administrador muda o formato do resumo da manhã.' using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists app_settings_chaves_do_dono on public.app_settings;
create trigger app_settings_chaves_do_dono
  before insert or update or delete on public.app_settings
  for each row execute function public._app_settings_chaves_do_dono();

revoke all on function public._app_settings_chaves_do_dono() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. resumo_registrar: o dia e os itens, uma vez só
--    Antes: os itens de manhã de dias anteriores sem nenhuma ação viram "ignorado" (métrica e repetição).
--    Já existe o dia deste telefone → devolve o texto gravado (as letras não mudam num segundo disparo).
-- ---------------------------------------------------------------------------------------------
create or replace function public.resumo_registrar(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_dia       date;
  v_phone     text := p->>'phone';
  v_modo      text := p->>'modo';
  v_id        uuid;
  v_texto     text;
  v_modo_gravado text;
  v_ignorados integer := 0;
begin
  begin
    v_dia := (p->>'dia')::date;
  exception when others then
    v_dia := null;
  end;
  if v_dia is null or v_phone is null or v_modo is null or p->>'texto_novo' is null then
    return jsonb_build_object('ok', false, 'erro', 'faltam dia, phone, modo ou texto_novo');
  end if;

  -- (o item cuja letra o dono mandou — o cartão aberto, "abriu" no histórico — não é ignorado)
  update public.resumo_itens i
     set acao = 'ignorado', acao_em = now(),
         historico = (case when jsonb_array_length(i.historico) >= 20 then i.historico - 0 else i.historico end)
                     || jsonb_build_array(jsonb_build_object('acao', 'ignorado', 'em', now()))
   where i.phone_normalized = v_phone and i.modo = v_modo and i.posicao = 'manha'
     and i.dia < v_dia and i.acao is null
     and not (i.historico @> '[{"acao": "abriu"}]'::jsonb);
  get diagnostics v_ignorados = row_count;

  select m.id, m.texto_novo, m.modo into v_id, v_texto, v_modo_gravado
    from public.resumo_manha m where m.dia = v_dia and m.phone_normalized = v_phone;
  if found then
    return jsonb_build_object('ok', true, 'novo', false, 'id', v_id, 'texto_novo', v_texto,
                              'modo', v_modo_gravado, 'ignorados', v_ignorados);
  end if;

  begin
    insert into public.resumo_manha (dia, phone_normalized, app_user_id, modo, tipo_do_dia, texto_novo, texto_antigo,
                                     escritorio, enviado, itens_manha, itens_lista, sem_letra)
    values (v_dia, v_phone, nullif(p->>'app_user_id', '')::uuid, v_modo, coalesce(p->>'tipo_do_dia', 'util'),
            p->>'texto_novo', p->>'texto_antigo', p->>'escritorio', coalesce((p->>'enviado')::boolean, false),
            coalesce((p->>'itens_manha')::smallint, 0), coalesce((p->>'itens_lista')::smallint, 0),
            coalesce((p->>'sem_letra')::smallint, 0))
    returning id into v_id;
  exception when unique_violation then
    -- dois disparos ao mesmo tempo: vale o primeiro
    select m.id, m.texto_novo, m.modo into v_id, v_texto, v_modo_gravado
      from public.resumo_manha m where m.dia = v_dia and m.phone_normalized = v_phone;
    return jsonb_build_object('ok', true, 'novo', false, 'id', v_id, 'texto_novo', v_texto,
                              'modo', v_modo_gravado, 'ignorados', v_ignorados);
  end;

  insert into public.resumo_itens (resumo_id, dia, phone_normalized, modo, letra, principal, posicao, ordem, familia, tipo,
                                   secao, referencia, assunto, nome, nome_busca, fato, valor, titulo, recomendacao, motivo,
                                   pedido, detalhe)
  select v_id, v_dia, v_phone, v_modo, x.letra, coalesce(x.principal, true), x.posicao, x.ordem, x.familia, x.tipo,
         x.secao, x.referencia, x.assunto, x.nome, coalesce(x.nome_busca, ''), x.fato, x.valor, x.titulo, x.recomendacao,
         x.motivo, x.pedido, coalesce(x.detalhe, '{}'::jsonb)
    from jsonb_to_recordset(coalesce(p->'itens', '[]'::jsonb)) as x(
      letra text, principal boolean, posicao text, ordem smallint, familia text, tipo text, secao text, referencia text,
      assunto text, nome text, nome_busca text, fato text, valor numeric, titulo text, recomendacao text, motivo text,
      pedido text, detalhe jsonb);

  return jsonb_build_object('ok', true, 'novo', true, 'id', v_id, 'texto_novo', p->>'texto_novo',
                            'modo', v_modo, 'ignorados', v_ignorados);
end $$;

comment on function public.resumo_registrar(jsonb) is
  'Secretário: grava a manhã do dia e os itens uma vez só (rodar de novo devolve o texto já gravado) e marca como ignorado o item de manhã de dias anteriores sem ação. Só service_role.';

-- ---------------------------------------------------------------------------------------------
-- 6. resumo_item_acao: "A feito", "B amanhã", "C não", "tira D" (o dia de hoje, em Brasília)
--    'abriu' = o dono mandou a letra sozinha (o cartão pronto): só entra no histórico, a ação não muda
--    (é a base da métrica "item que virou ação"; nada é aprovado aqui — o cartão espera o sim de sempre)
-- ---------------------------------------------------------------------------------------------
create or replace function public.resumo_item_acao(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone text := p->>'phone';
  v_modo  text := coalesce(p->>'modo', 'novo');
  v_letra text := upper(btrim(coalesce(p->>'letra', '')));
  v_acao  text := p->>'acao';
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ate   date;
  v_n     integer;
  v_item  record;
begin
  if v_acao is null or v_acao not in ('feito', 'adiado', 'nao', 'tirado', 'abriu') then
    return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'acao');
  end if;
  if v_acao = 'abriu' then
    update public.resumo_itens i
       set historico = (case when jsonb_array_length(i.historico) >= 20 then i.historico - 0 else i.historico end)
                       || jsonb_build_array(jsonb_build_object('acao', 'abriu', 'em', now()))
     where i.phone_normalized = v_phone and i.modo = v_modo and i.dia = v_hoje and i.letra = v_letra and i.principal;
    get diagnostics v_n = row_count;
    return jsonb_build_object('ok', true, 'resultado', case when v_n = 0 then 'nao_achei' else 'feito' end, 'acao', 'abriu', 'itens', v_n);
  end if;
  if v_acao = 'adiado' then
    begin
      v_ate := (p->>'ate')::date;
    exception when others then
      v_ate := null;
    end;
    if v_ate is null or v_ate <= v_hoje or v_ate > v_hoje + 90 then
      return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'ate');
    end if;
  end if;

  update public.resumo_itens i
     set acao = v_acao, acao_em = now(), adiado_ate = v_ate,
         historico = (case when jsonb_array_length(i.historico) >= 20 then i.historico - 0 else i.historico end)
                     || jsonb_build_array(jsonb_build_object('acao', v_acao, 'em', now(), 'ate', v_ate))
   where i.phone_normalized = v_phone and i.modo = v_modo and i.dia = v_hoje and i.letra = v_letra;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('ok', true, 'resultado', 'nao_achei', 'letra', v_letra);
  end if;

  select i.letra, i.nome, i.titulo, i.tipo, i.familia, i.posicao into v_item
    from public.resumo_itens i
   where i.phone_normalized = v_phone and i.modo = v_modo and i.dia = v_hoje and i.letra = v_letra and i.principal
   limit 1;
  return jsonb_build_object('ok', true, 'resultado', 'feito', 'acao', v_acao, 'ate', v_ate, 'itens', v_n,
    'item', jsonb_build_object('letra', v_item.letra, 'nome', v_item.nome, 'titulo', v_item.titulo,
                               'tipo', v_item.tipo, 'familia', v_item.familia, 'posicao', v_item.posicao));
end $$;

comment on function public.resumo_item_acao(jsonb) is
  'Secretário: grava a ação do dono (feito, adiado com data, nao, tirado) em todos os itens da letra do dia de hoje (Brasília); abriu (a letra sozinha) só entra no histórico do principal. Só service_role.';

-- ---------------------------------------------------------------------------------------------
-- 7. resumo_item_voltar: "volta B" (letra de hoje) ou "volta Flávio" (o assunto mais recente com ação)
-- ---------------------------------------------------------------------------------------------
create or replace function public.resumo_item_voltar(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone  text := p->>'phone';
  v_modo   text := coalesce(p->>'modo', 'novo');
  v_letra  text := upper(btrim(coalesce(p->>'letra', '')));
  v_nome   text := btrim(coalesce(p->>'nome', ''));
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_resumo uuid;
  v_alvo   text;
  v_acao   text;
  v_n      integer;
  v_item   record;
begin
  if v_letra <> '' then
    select i.resumo_id, i.letra, i.acao into v_resumo, v_alvo, v_acao
      from public.resumo_itens i
     where i.phone_normalized = v_phone and i.modo = v_modo and i.dia = v_hoje and i.letra = v_letra and i.principal
     limit 1;
    if v_resumo is null then
      return jsonb_build_object('ok', true, 'resultado', 'nao_achei', 'letra', v_letra);
    end if;
    if v_acao is null or v_acao = 'ignorado' then
      return jsonb_build_object('ok', true, 'resultado', 'sem_acao', 'letra', v_letra);
    end if;
  elsif v_nome ~ '^[a-z0-9 ]{2,40}$' then
    select i.resumo_id, i.letra, i.acao into v_resumo, v_alvo, v_acao
      from public.resumo_itens i
     where i.phone_normalized = v_phone and i.modo = v_modo and i.principal
       and i.acao in ('feito', 'adiado', 'nao', 'tirado')
       and i.acao_em >= now() - interval '30 days'
       and position(v_nome in i.nome_busca) > 0
     order by i.acao_em desc
     limit 1;
    if v_resumo is null then
      return jsonb_build_object('ok', true, 'resultado', 'nao_achei', 'nome', v_nome);
    end if;
  else
    return jsonb_build_object('ok', false, 'resultado', 'invalido', 'erro', 'alvo');
  end if;

  update public.resumo_itens i
     set acao = null, acao_em = null, adiado_ate = null, voltou_em = now(),
         historico = (case when jsonb_array_length(i.historico) >= 20 then i.historico - 0 else i.historico end)
                     || jsonb_build_array(jsonb_build_object('acao', 'volta', 'em', now(), 'antes', i.acao))
   where i.resumo_id = v_resumo and i.letra = v_alvo
     and i.acao is not null and i.acao <> 'ignorado';
  get diagnostics v_n = row_count;

  select i.letra, i.nome, i.titulo, i.tipo, i.dia into v_item
    from public.resumo_itens i where i.resumo_id = v_resumo and i.letra = v_alvo and i.principal limit 1;
  return jsonb_build_object('ok', true, 'resultado', 'voltou', 'desfeita', v_acao, 'itens', v_n,
    'item', jsonb_build_object('letra', v_item.letra, 'nome', v_item.nome, 'titulo', v_item.titulo,
                               'tipo', v_item.tipo, 'dia', v_item.dia));
end $$;

comment on function public.resumo_item_voltar(jsonb) is
  'Secretário: desfaz a última ação do dono num item (pela letra de hoje ou pelo nome, nos últimos 30 dias); o item volta a poder subir de manhã. Só service_role.';

revoke all on function public.resumo_registrar(jsonb) from public, anon, authenticated;
revoke all on function public.resumo_item_acao(jsonb) from public, anon, authenticated;
revoke all on function public.resumo_item_voltar(jsonb) from public, anon, authenticated;
grant execute on function public.resumo_registrar(jsonb) to service_role;
grant execute on function public.resumo_item_acao(jsonb) to service_role;
grant execute on function public.resumo_item_voltar(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_t text;
  v_f text;
  v_tabelas text[] := array['public.resumo_manha', 'public.resumo_itens'];
  v_rpcs text[] := array['public.resumo_registrar(jsonb)', 'public.resumo_item_acao(jsonb)', 'public.resumo_item_voltar(jsonb)'];
  v_def text;
begin
  foreach v_t in array v_tabelas loop
    if not (select relrowsecurity from pg_class where oid = v_t::regclass) then
      raise exception 'RLS desligada em %', v_t;
    end if;
    if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert')
       or has_table_privilege('anon', v_t, 'update') or has_table_privilege('anon', v_t, 'delete') then
      raise exception 'anon ainda alcança %', v_t;
    end if;
    if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
       or has_table_privilege('authenticated', v_t, 'delete') then
      raise exception 'authenticated escreve direto em %', v_t;
    end if;
    if not has_table_privilege('service_role', v_t, 'select') or not has_table_privilege('service_role', v_t, 'insert')
       or not has_table_privilege('service_role', v_t, 'update') then
      raise exception 'service_role não alcança %', v_t;
    end if;
  end loop;
  -- policies: só as duas previstas, só TO authenticated, só SELECT
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('resumo_manha', 'resumo_itens')) <> 2
     or exists (select 1 from pg_policies
                 where schemaname = 'public' and tablename in ('resumo_manha', 'resumo_itens')
                   and (roles <> array['authenticated']::name[] or cmd <> 'SELECT'
                        or policyname not in ('resumo_manha_admin_le', 'resumo_itens_admin_le')
                        or position('is_admin' in qual) = 0)) then
    raise exception 'policies do resumo diferentes das previstas (ou alcançando anon/public)';
  end if;
  foreach v_f in array v_rpcs loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'função do resumo exposta para anon: %', v_f;
    end if;
    if has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função do resumo exposta para authenticated: %', v_f;
    end if;
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'resumo_itens' and indexname = 'resumo_itens_letra_do_dia'
                    and indexdef ilike '%unique%' and indexdef ilike '%where%principal%') then
    raise exception 'índice único da letra do dia ausente';
  end if;
  if not exists (select 1 from public.app_settings where key = 'resumo_formato') then
    raise exception 'chave resumo_formato não foi criada';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'app_settings_chaves_do_dono'
                    and tgrelid = 'public.app_settings'::regclass and tgenabled <> 'D') then
    raise exception 'gatilho app_settings_chaves_do_dono ausente: o financeiro mudaria resumo_formato';
  end if;
  v_def := pg_get_functiondef('public._app_settings_chaves_do_dono()'::regprocedure);
  if position('resumo_formato' in v_def) = 0 or position('comprovante_conversa' in v_def) = 0
     or position('comprovante_fluxo' in v_def) = 0 or position('pro_labore_pelo_salario_minimo' in v_def) = 0 then
    raise exception 'o gatilho das chaves do dono não protege todas as chaves (resumo_formato, comprovantes, pró-labore)';
  end if;
  if has_function_privilege('anon', 'public._app_settings_chaves_do_dono()', 'execute')
     or has_function_privilege('authenticated', 'public._app_settings_chaves_do_dono()', 'execute') then
    raise exception 'gatilho das chaves do dono exposto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261015200000', 'resumo_secretario')
on conflict do nothing;
