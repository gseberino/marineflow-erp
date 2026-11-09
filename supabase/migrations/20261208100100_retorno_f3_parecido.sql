-- Retorno rápido ao cliente, F3 (P2): famílias, classe do bem e a busca do orçamento parecido.
--
-- 1. _retorno_familias: as famílias específicas de um texto já passado por _retorno_busca. A lista é fixa e fica só aqui.
--    Fora dela, de propósito: eletrica, diagnostico, revisao e manutencao, genéricas demais. Sem família, sem proposta.
-- 2. _retorno_familia_rotulo: o título e o {do_servico} da legenda, na ordem da tabela. Mais de 2 famílias: "A, b e outros".
-- 3. _retorno_classe_do_bem: barco, veiculo ou outro, sobre texto normalizado. Serve ao asset_type, à coleta e à bem_palavra.
--    O que não reconhece, ou nulo → nulo (o motivo sem_classe da P3 depende disso).
-- 4. _retorno_os_aprovada: a definição de "praticado" da F3, usada no parecido e no preço.
-- 5. retorno_parecidos: os orçamentos e OS anteriores da mesma classe de bem com alguma família em comum, do mais parecido ao
--    menos: mesma unidade, mesmo cliente, família igual, aprovado, mais recente. Ninguém olha o futuro: só o que existia antes de p_antes.
--
-- Reverter: drop das funções abaixo. Nenhum dado.

create or replace function public._retorno_familias(p_busca text)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(f.familia order by f.familia), '{}'::text[])
    from (values
      ('bateria',    '\y(bateria|baterias|litio|lifepo4|agm)\y'),
      ('solar',      '\y(solar|solares|fotovoltaico|fotovoltaica|fotovoltaicos|mppt|usina)\y'),
      ('inversor',   '\y(inversor|inversora|inversores|multiplus|conversor)\y'),
      ('carregador', '\y(carregador|carregadores)\y'),
      ('ar',         '\y(condicionado|climatizador)\y'),
      ('geladeira',  '\y(geladeira|frigobar|freezer|refrigerador)\y'),
      ('starlink',   '\y(starlink|antena)\y'),
      ('iluminacao', '\y(iluminacao|luminaria|luminarias|led|leds)\y'),
      ('agua',       '\y(agua|bomba|pressurizadora|hidraulico|hidraulica|vaso|sanitario)\y'),
      ('gerador',    '\y(gerador)\y'),
      ('aquecedor',  '\y(aquecedor|boiler)\y'),
      ('navegacao',  '\y(radar|plotter|gps|sonar|sonda|navegacao)\y')
    ) as f(familia, re)
   where coalesce(p_busca, '') ~ f.re;
$$;

comment on function public._retorno_familias(text) is
  'Retorno F3 (P2): as famílias específicas do texto já normalizado por _retorno_busca, ordenadas por nome. Genéricas (elétrica, revisão, manutenção) ficam de fora: sem família, sem proposta.';

revoke all on function public._retorno_familias(text) from public, anon, authenticated;

create or replace function public._retorno_familia_rotulo(p_familias text[])
returns jsonb
language sql
immutable
set search_path = public
as $$
  with tabela(familia, rotulo, do_servico, ordem) as (
    values ('bateria',    'Baterias',            'das baterias',                    1),
           ('solar',      'Energia solar',       'de energia solar',                2),
           ('inversor',   'Inversor',            'do inversor',                     3),
           ('carregador', 'Carregador',          'do carregador',                   4),
           ('ar',         'Ar-condicionado',     'do ar-condicionado',              5),
           ('geladeira',  'Geladeira',           'da geladeira',                    6),
           ('starlink',   'Antena Starlink',     'da antena Starlink',              7),
           ('iluminacao', 'Iluminação',          'da iluminação',                   8),
           ('agua',       'Parte hidráulica',    'da parte hidráulica',             9),
           ('gerador',    'Gerador',             'do gerador',                     10),
           ('aquecedor',  'Aquecedor',           'do aquecedor',                   11),
           ('navegacao',  'Navegação',           'dos equipamentos de navegação',  12)
  ), escolhidas as (
    select t.rotulo, t.do_servico, row_number() over (order by t.ordem) as n, count(*) over () as qtd
      from tabela t
     where t.familia = any (coalesce(p_familias, '{}'::text[]))
  ), pares as (
    select max(e.rotulo) filter (where e.n = 1) as r1,
           max(e.rotulo) filter (where e.n = 2) as r2,
           max(e.do_servico) filter (where e.n = 1) as s1,
           max(e.do_servico) filter (where e.n = 2) as s2,
           max(e.qtd) as qtd
      from escolhidas e
  )
  select case
           when p.qtd is null or p.qtd = 0 then jsonb_build_object('titulo', 'Orçamento', 'do_servico', null)
           when p.qtd = 1 then jsonb_build_object('titulo', p.r1, 'do_servico', p.s1)
           when p.qtd = 2 then jsonb_build_object(
             'titulo', p.r1 || ' e ' || lower(left(p.r2, 1)) || substr(p.r2, 2),
             'do_servico', p.s1 || ' e ' || p.s2)
           else jsonb_build_object(
             'titulo', p.r1 || ', ' || lower(left(p.r2, 1)) || substr(p.r2, 2) || ' e outros',
             'do_servico', null)
         end
    from pares p;
$$;

comment on function public._retorno_familia_rotulo(text[]) is
  'Retorno F3 (P2): {titulo, do_servico} das famílias, na ordem da tabela. Até 2 nomeadas; mais de 2: as 2 primeiras e " e outros", com do_servico nulo. Lista vazia: titulo "Orçamento" (retorno_previa.titulo é NOT NULL).';

revoke all on function public._retorno_familia_rotulo(text[]) from public, anon, authenticated;

create or replace function public._retorno_classe_do_bem(p_asset text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
           when x.b ~ '\y(lancha|veleiro|catamara|moto aquatica|jet ski|outra embarcacao|embarcacao|barco|escuna|traineira|bote)\y' then 'barco'
           when x.b ~ '\y(motorhome|motor home|trailer|camper|automovel|outro veiculo|veiculo|van|onibus|caminhao|picape|carro|ducato|sprinter|iveco|daily|master|boxer)\y' then 'veiculo'
           when x.b ~ '\y(equipamento)\y' then 'outro'
         end
    from (select public._retorno_busca(p_asset) as b) x;
$$;

comment on function public._retorno_classe_do_bem(text) is
  'Retorno F3 (P2): barco, veiculo, outro ou nulo, comparando sobre o texto normalizado. Serve ao asset_type, à coleta e à bem_palavra. Nome que não reconhece, ou nulo, devolve nulo.';

revoke all on function public._retorno_classe_do_bem(text) from public, anon, authenticated;

create or replace function public._retorno_os_aprovada(p_status text, p_quote_status text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_status <> 'cancelled' and (p_quote_status = 'approved' or p_status <> 'draft'), false);
$$;

comment on function public._retorno_os_aprovada(text, text) is
  'Retorno F3 (P2): a definição de "praticado" da F3: OS não cancelada que foi aprovada (status fora de draft, ou quote_status approved).';

revoke all on function public._retorno_os_aprovada(text, text) from public, anon, authenticated;

create or replace function public.retorno_parecidos(p_familias text[], p_classe text, p_cliente uuid, p_unidade uuid,
                                                    p_antes timestamptz, p_agora timestamptz, p_limite integer default 2)
returns table (os_id uuid, numero text, criada_em timestamptz, mesma_unidade boolean, mesmo_cliente boolean,
               familia_igual boolean, aprovado boolean, linhas_n integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
begin
  if coalesce(cardinality(p_familias), 0) = 0 or p_classe is null then
    return;
  end if;

  return query
  with cabecalho as (
    select so.id, so.service_order_number, so.created_at, so.client_id, so.vessel_id, so.status, so.quote_status, so.problem_description
      from public.service_orders so
      join public.vessels v on v.id = so.vessel_id
     where so.merged_into_id is null
       and so.status <> 'cancelled'
       and so.created_at >= p_agora - v_cfg.previa_idade_max
       and so.created_at < p_antes
       and public._retorno_classe_do_bem(v.asset_type) = p_classe
  ), linhas as (
    select c.id, count(*)::integer as qtd, string_agg(l.nome, ' ') as nomes
      from cabecalho c
      join lateral (
        select coalesce(pr.name, '') as nome
          from public.service_order_parts p
          left join public.products pr on pr.id = p.product_id
         where p.service_order_id = c.id
        union all
        select coalesce(s.name_snapshot, '')
          from public.service_order_services s
         where s.service_order_id = c.id
      ) l on true
     group by c.id
  ), candidatos as (
    select c.id, c.service_order_number, c.created_at, c.client_id, c.vessel_id, c.status, c.quote_status, l.qtd,
           public._retorno_familias(public._retorno_busca(coalesce(c.problem_description, '') || ' ' || coalesce(l.nomes, ''))) as fam
      from cabecalho c
      join linhas l on l.id = c.id
     where l.qtd between 1 and v_cfg.previa_max_linhas
  )
  select c.id,
         c.service_order_number,
         c.created_at,
         (p_unidade is not null and c.vessel_id = p_unidade),
         (p_cliente is not null and c.client_id = p_cliente),
         (c.fam @> p_familias and c.fam <@ p_familias),
         public._retorno_os_aprovada(c.status, c.quote_status),
         c.qtd
    from candidatos c
   where c.fam && p_familias
   order by 4 desc, 5 desc, 6 desc, 7 desc, c.created_at desc, c.id
   limit greatest(coalesce(p_limite, 2), 0);
end;
$$;

comment on function public.retorno_parecidos(text[], text, uuid, uuid, timestamptz, timestamptz, integer) is
  'Retorno F3 (P2): orçamentos e OS parecidos, anteriores a p_antes, da mesma classe de bem e com alguma família em comum: mesma unidade, mesmo cliente, família igual, aprovado, recente. Ninguém olha o futuro.';

revoke all on function public.retorno_parecidos(text[], text, uuid, uuid, timestamptz, timestamptz, integer) from public, anon, authenticated;
grant execute on function public.retorno_parecidos(text[], text, uuid, uuid, timestamptz, timestamptz, integer) to service_role;
