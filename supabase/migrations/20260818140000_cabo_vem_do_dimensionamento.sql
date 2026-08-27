-- ═══════════════════════════════════════════════════════════════════════════
-- O cabo do orçamento passa a sair do dimensionamento, e não de uma regra fixa
--
-- ═══ O DEFEITO ORIGINAL, AINDA DE PÉ ═══
--
-- A única regra de material ATIVA em produção diz: "sempre que a distância for
-- respondida, entra Cabo flexível 35 mm², 2 m por metro medido, +15%". O
-- comprimento está certo — o positivo vai e o negativo volta. O PRODUTO é fixo:
-- 35 mm² para qualquer corrente e qualquer distância.
--
-- É exatamente o que o dono perguntou em 08/08 sobre o ORÇ-00074 — "esse 35 mm²
-- bate com a Blue Sea / ABYC?". Não batia, e continuou não batendo depois de o
-- dimensionador existir: `dc_cable_sizing` calcula a bitola e a regra de
-- material escolhe o produto, e as duas nunca se falaram.
--
-- ═══ POR QUE A ISOLAÇÃO PRECISA VIR DO PRODUTO ═══
--
-- A ampacidade depende da temperatura da isolação, e essa informação não está
-- no levantamento nem na cabeça de quem está em campo: está no cabo que a HBR
-- compra. Enquanto ela era um literal 105 °C no código (o topo da escala), o
-- sistema liberava bitola que o cabo real pode não suportar.
--
-- Só é candidato o cabo que tem AS DUAS coisas preenchidas. Cabo sem isolação
-- declarada não entra na escolha — não é possível dimensionar com ele, e
-- deixá-lo entrar seria voltar a supor.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

alter table public.products
  add column if not exists conductor_mm2 numeric check (conductor_mm2 > 0),
  add column if not exists conductor_insulation_c integer
    check (conductor_insulation_c in (75, 90, 105));

comment on column public.products.conductor_mm2 is
  'Seção do condutor, em mm². Só para cabo de potência de UM condutor vendido por
   metro — é o que permite escolher o cabo pela bitola que o dimensionamento
   apontou. Cabo multipolar, de dados ou kit deixa nulo.';

comment on column public.products.conductor_insulation_c is
  'Temperatura da isolação (75, 90 ou 105 °C), como consta na especificação do
   fabricante. NÃO preencher por dedução: é ela que decide quanta corrente o cabo
   admite, e errar para cima libera bitola que o cabo não aguenta.';

-- A bitola sai do próprio nome do produto, sem ambiguidade. A ISOLAÇÃO não sai:
-- fica nula, para ser preenchida com a especificação do fabricante na mão.
update public.products set conductor_mm2 = 16  where name = 'Cabo flexível 16 mm² - ligação Hilux/camper';
update public.products set conductor_mm2 = 16  where name = 'CABO COBRE FLEX 750V 16,0MM VM';
update public.products set conductor_mm2 = 25  where name = 'Cabo flexível 25 mm² - saída do carregador DC/DC';
update public.products set conductor_mm2 = 35  where name = 'Cabo flexível 35 mm² - ligação da fonte 120A';
update public.products set conductor_mm2 = 50  where name = 'Cabo cobre flexível 1 kV HEPR 50 mm²';
update public.products set conductor_mm2 = 70  where name = 'Cabo flexível 70 mm² - ligação do inversor';
update public.products set conductor_mm2 = 70  where name = 'Cabo elétrico 70mm² (metro)';
update public.products set conductor_mm2 = 95  where name = 'Cabo cobre flexível 1 kV HEPR 95 mm²';

-- ───────────────────────────────────────────────────────────────────────────
-- Qual cabo do catálogo atende este circuito
--
-- Percorre os candidatos do MENOR para o maior e devolve o primeiro que passa
-- nos DOIS critérios — com a ampacidade lida na linha da PRÓPRIA isolação dele,
-- não numa isolação suposta. Empate de bitola desempata pelo mais barato.
--
-- Devolve `produto: null` com o motivo quando nenhum serve. Nunca devolve o
-- "mais próximo": cabo que não atende não é aproximação, é cabo errado.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.dc_cable_product_for(
  p_amps numeric,
  p_one_way_meters numeric,
  p_volts numeric default 12,
  p_max_drop_pct numeric default 3,
  p_engine_space boolean default false,
  p_bundle_size integer default 1)
returns jsonb
language plpgsql stable security invoker set search_path = public
as $fn$
declare
  v_drop numeric; v_n integer := coalesce(p_bundle_size, 1);
  v_prod record; v_candidatos integer;
begin
  v_drop := public.dc_cable_min_mm2_by_drop(p_amps, p_one_way_meters, p_volts, p_max_drop_pct);

  if v_drop is null then
    return jsonb_build_object('produto', null, 'pronto', false,
      'motivo', 'Faltam corrente ou comprimento para dimensionar.');
  end if;

  select count(*) into v_candidatos from public.products p
  where p.active and p.conductor_mm2 is not null and p.conductor_insulation_c is not null;

  if v_candidatos = 0 then
    return jsonb_build_object('produto', null, 'pronto', false,
      'motivo', 'Nenhum cabo do catálogo tem seção E isolação declaradas. '
             || 'Sem a isolação não dá para saber quanta corrente o cabo admite.');
  end if;

  select p.id, p.name, p.conductor_mm2, p.conductor_insulation_c, p.sale_price, p.unit
    into v_prod
  from public.products p
  join public.dc_ampacity_ratings r
    on r.mm2 = p.conductor_mm2 and r.insulation_c = p.conductor_insulation_c
  where p.active
    and p.conductor_mm2 is not null
    and p.conductor_insulation_c is not null
    and p.conductor_mm2 >= v_drop
    and case
          when v_n > 1 and p_engine_space then r.amps_bundled_engine
          when v_n > 1                    then r.amps_bundled
          when p_engine_space             then r.amps_free_air_engine
          else r.amps_free_air
        end >= p_amps
  order by p.conductor_mm2, coalesce(p.sale_price, 1e9)
  limit 1;

  if v_prod.id is null then
    return jsonb_build_object('produto', null, 'pronto', false,
      'motivo', 'Nenhum cabo do catálogo atende ' || p_amps || ' A com '
             || v_drop || ' mm² de mínimo por queda de tensão, nesta condição de '
             || 'instalação. Cadastre a seção maior ou divida o circuito.');
  end if;

  return jsonb_build_object(
    'produto', jsonb_build_object(
      'id', v_prod.id, 'nome', v_prod.name, 'mm2', v_prod.conductor_mm2,
      'isolacao_c', v_prod.conductor_insulation_c,
      'preco_por_metro', v_prod.sale_price, 'unidade', v_prod.unit),
    -- Acima de três condutores a folha da norma não cobre; o cabo escolhido é
    -- piso, não resposta. Mesmo critério do dc_cable_sizing.
    'pronto', v_n <= 3,
    'mm2_por_queda_de_tensao', v_drop,
    'motivo', case when v_n > 3 then
      'São ' || v_n || ' condutores no feixe e a norma cobre até três: este cabo '
      || 'é o piso, e falta a correção adicional.' end);
end;
$fn$;

revoke all on function public.dc_cable_product_for(numeric, numeric, numeric, numeric, boolean, integer)
  from public, anon;
grant execute on function public.dc_cable_product_for(numeric, numeric, numeric, numeric, boolean, integer)
  to authenticated;

comment on function public.dc_cable_product_for(numeric, numeric, numeric, numeric, boolean, integer) is
  'O cabo do catálogo que atende este circuito pelos dois critérios da ABYC,
   lendo a ampacidade na isolação DECLARADA de cada cabo. Devolve produto nulo
   com motivo quando nenhum serve — nunca o mais próximo.';

commit;
