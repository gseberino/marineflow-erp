-- Retorno F3 (P2): famílias, classe do bem, rótulo do título e a busca do orçamento parecido. Roda só pela bancada (grupo 5).
-- Termina em ROLLBACK. Os fixtures têm data em 2040, para não cruzar com nenhum orçamento real da janela de 18 meses de p_agora.
-- Telefones de teste 55479000093xx; frases e nomes inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Um orçamento com p_linhas linhas de serviço. Sem o texto na descrição, as linhas é que levam a palavra da família.
create or replace function pg_temp.f3p_os(p_num text, p_cliente uuid, p_unidade uuid, p_status text, p_quote text,
                                          p_em timestamptz, p_desc text, p_linhas integer, p_nome_linha text default 'Item avulso') returns uuid
language plpgsql as $f$
declare
  v_id uuid;
  i integer;
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description,
                                     created_at, updated_at, grand_total)
  values (p_num, p_cliente, p_unidade, p_status, p_quote, 'repair', p_desc, p_em, p_em, 100)
  returning id into v_id;
  for i in 1..p_linhas loop
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total)
    values (v_id, p_nome_linha || ' ' || i, 'visit', 1, 10, 10);
  end loop;
  return v_id;
end $f$;

-- A lista dos números de orçamento, na ordem devolvida pela função.
create or replace function pg_temp.f3p_numeros(p_familias text[], p_classe text, p_cliente uuid, p_unidade uuid, p_antes timestamptz,
                                               p_agora timestamptz, p_limite integer) returns text[]
language sql as $f$
  select coalesce(array_agg(x.numero order by x.ord), '{}')
    from public.retorno_parecidos(p_familias, p_classe, p_cliente, p_unidade, p_antes, p_agora, p_limite)
         with ordinality as x(os_id, numero, criada_em, mesma_unidade, mesmo_cliente, familia_igual, aprovado, linhas_n, ord);
$f$;

do $parecido$
declare
  c_agora constant timestamptz := '2040-06-01 10:00-03';
  c_antes constant timestamptz := '2040-05-30 10:00-03';
  v_cli1 uuid;
  v_cli2 uuid;
  v_cli3 uuid;
  v_un1 uuid;
  v_un1b uuid;
  v_un2 uuid;
  v_un3 uuid;
  v_a text[];
  v_r record;
  v_alvo uuid;
  v_merge uuid;
  v_f text[];
  v_j jsonb;
begin
  begin
  -- 1. _retorno_familias: 20 frases inventadas, inclusive "placas solares", "ar condicionado", "lifepo4"; manutenção e elétrica dão vazio.
  for v_r in
    select * from (values
      ('Preciso trocar as baterias da lancha', '{bateria}'),
      ('bateria de lítio', '{bateria}'),
      ('banco de lifepo4', '{bateria}'),
      ('baterias AGM', '{bateria}'),
      ('placas solares no teto', '{solar}'),
      ('usina fotovoltaica', '{solar}'),
      ('controlador mppt', '{solar}'),
      ('inversor Multiplus', '{inversor}'),
      ('um conversor de 12v', '{inversor}'),
      ('carregador de bateria', '{bateria,carregador}'),
      ('ar condicionado parou', '{ar}'),
      ('climatizador novo', '{ar}'),
      ('geladeira não gela', '{geladeira}'),
      ('antena Starlink', '{starlink}'),
      ('luminária de led', '{iluminacao}'),
      ('bomba d''água', '{agua}'),
      ('gerador parou', '{gerador}'),
      ('boiler a gás', '{aquecedor}'),
      ('radar e plotter', '{navegacao}'),
      ('GPS quebrado', '{navegacao}'),
      ('manutenção geral', '{}'),
      ('elétrica do barco', '{}')
    ) as x(frase, esperado)
  loop
    v_f := public._retorno_familias(public._retorno_busca(v_r.frase));
    if v_f is distinct from v_r.esperado::text[] then
      raise exception '1: "%" deu %, esperava %', v_r.frase, v_f, v_r.esperado;
    end if;
  end loop;
  if public._retorno_familias(null) is distinct from '{}'::text[] then
    raise exception '1b: nulo não devolveu vazio';
  end if;

  -- 2. Ordem: mesma unidade, mesmo cliente, família igual, aprovado, recente.
  insert into public.clients (type, name) values ('individual', 'Paulo Parecido Teste') returning id into v_cli1;
  insert into public.clients (type, name) values ('individual', 'Maria Parecido Teste') returning id into v_cli2;
  insert into public.clients (type, name) values ('individual', 'Lia Parecido Teste') returning id into v_cli3;
  insert into public.vessels (client_id, name, asset_type) values (v_cli1, 'Brisa Parecido', 'Lancha') returning id into v_un1;
  insert into public.vessels (client_id, name, asset_type) values (v_cli1, 'Maresia Parecido', 'Lancha') returning id into v_un1b;
  insert into public.vessels (client_id, name, asset_type) values (v_cli2, 'Vento Parecido', 'Lancha') returning id into v_un2;
  insert into public.vessels (client_id, name, asset_type) values (v_cli3, 'Motor Parecido', 'Motorhome') returning id into v_un3;

  perform pg_temp.f3p_os('ORÇ-TF3P-A', v_cli1, v_un1, 'draft', 'draft', '2040-01-10 10:00-03', 'troca de baterias', 2);
  perform pg_temp.f3p_os('ORÇ-TF3P-B', v_cli1, v_un1b, 'draft', 'approved', '2040-02-10 10:00-03', 'baterias novas', 2);
  perform pg_temp.f3p_os('ORÇ-TF3P-C', v_cli2, v_un2, 'draft', 'approved', '2040-02-11 10:00-03', 'bateria do barco', 2);
  perform pg_temp.f3p_os('ORÇ-TF3P-E', v_cli2, v_un2, 'draft', 'sent', '2040-04-01 10:00-03', 'bateria de lítio', 2);
  perform pg_temp.f3p_os('ORÇ-TF3P-D', v_cli2, v_un2, 'draft', 'approved', '2040-05-01 10:00-03', 'bateria e inversor', 2);

  v_a := pg_temp.f3p_numeros(array['bateria'], 'barco', v_cli1, v_un1, c_antes, c_agora, 20);
  if v_a is distinct from array['ORÇ-TF3P-A', 'ORÇ-TF3P-B', 'ORÇ-TF3P-C', 'ORÇ-TF3P-E', 'ORÇ-TF3P-D'] then
    raise exception '2a: ordem errada: %', v_a;
  end if;
  -- Os sinais de cada um, e o limite padrão.
  if (select count(*) from public.retorno_parecidos(array['bateria'], 'barco', v_cli1, v_un1, c_antes, c_agora)) <> 2 then
    raise exception '2b: o limite padrão não é 2';
  end if;
  select array_agg(x.mesma_unidade::text order by x.ord) into v_a
    from public.retorno_parecidos(array['bateria'], 'barco', v_cli1, v_un1, c_antes, c_agora, 20)
         with ordinality as x(os_id, numero, criada_em, mesma_unidade, mesmo_cliente, familia_igual, aprovado, linhas_n, ord);
  if v_a[1] is distinct from 'true' or v_a[2] is distinct from 'false' then
    raise exception '2c: mesma_unidade errada: %', v_a;
  end if;
  -- Sem cliente e sem unidade, nenhum sinal de "mesmo".
  if exists (select 1 from public.retorno_parecidos(array['bateria'], 'barco', null, null, c_antes, c_agora, 20)
             where mesma_unidade or mesmo_cliente) then
    raise exception '2d: sem cliente/unidade, apareceu "mesmo"';
  end if;

  -- 3. Cancelado, agrupado, sem linha, com 13 linhas e mais velho que 18 meses não aparecem; com 12 linhas aparece.
  perform pg_temp.f3p_os('ORÇ-TF3P-CANC', v_cli1, v_un1, 'cancelled', 'draft', '2040-01-11 10:00-03', 'bateria', 1);
  v_alvo := pg_temp.f3p_os('ORÇ-TF3P-DEST', v_cli2, v_un2, 'draft', 'draft', '2040-01-12 10:00-03', 'nada de família aqui', 0);
  v_merge := pg_temp.f3p_os('ORÇ-TF3P-AGRUP', v_cli1, v_un1, 'draft', 'draft', '2040-01-13 10:00-03', 'bateria', 1);
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  update public.service_orders set merged_into_id = v_alvo where id = v_merge;
  perform set_config('marineflow.agrupar_orcamentos', '', true);
  perform pg_temp.f3p_os('ORÇ-TF3P-VAZIA', v_cli1, v_un1, 'draft', 'draft', '2040-01-14 10:00-03', 'bateria', 0);
  perform pg_temp.f3p_os('ORÇ-TF3P-13', v_cli1, v_un1, 'draft', 'draft', '2040-01-15 10:00-03', 'bateria', 13);
  perform pg_temp.f3p_os('ORÇ-TF3P-VELHA', v_cli1, v_un1, 'draft', 'draft', '2038-11-01 10:00-03', 'bateria', 1);
  perform pg_temp.f3p_os('ORÇ-TF3P-12', v_cli1, v_un1, 'draft', 'draft', '2040-01-16 10:00-03', 'bateria', 12);

  v_a := pg_temp.f3p_numeros(array['bateria'], 'barco', v_cli1, v_un1, c_antes, c_agora, 40);
  if array['ORÇ-TF3P-CANC', 'ORÇ-TF3P-AGRUP', 'ORÇ-TF3P-VAZIA', 'ORÇ-TF3P-13', 'ORÇ-TF3P-VELHA'] && v_a then
    raise exception '3a: entrou quem não pode: %', v_a;
  end if;
  if not ('ORÇ-TF3P-12' = any (v_a)) then
    raise exception '3b: 12 linhas deveria entrar: %', v_a;
  end if;

  -- 4. Ninguém olha o futuro: criado depois de p_antes não aparece, nem antes de p_agora.
  perform pg_temp.f3p_os('ORÇ-TF3P-FUTURO', v_cli1, v_un1, 'draft', 'draft', '2040-05-30 12:00-03', 'bateria', 1);
  v_a := pg_temp.f3p_numeros(array['bateria'], 'barco', v_cli1, v_un1, c_antes, c_agora, 40);
  if 'ORÇ-TF3P-FUTURO' = any (v_a) then
    raise exception '4a: criado depois de p_antes apareceu: %', v_a;
  end if;
  v_a := pg_temp.f3p_numeros(array['bateria'], 'barco', v_cli1, v_un1, '2040-05-30 13:00-03', c_agora, 40);
  if not ('ORÇ-TF3P-FUTURO' = any (v_a)) then
    raise exception '4b: criado antes de p_antes deveria aparecer: %', v_a;
  end if;

  -- 5. Classe: parecido de lancha não serve a motorhome.
  perform pg_temp.f3p_os('ORÇ-TF3P-MOTOR', v_cli3, v_un3, 'draft', 'draft', '2040-02-01 10:00-03', 'bateria do motorhome', 1);
  v_a := pg_temp.f3p_numeros(array['bateria'], 'veiculo', v_cli1, v_un1, c_antes, c_agora, 40);
  if v_a is distinct from array['ORÇ-TF3P-MOTOR'] then
    raise exception '5a: classe veiculo trouxe % ', v_a;
  end if;
  if exists (select 1 from public.retorno_parecidos(array['bateria'], 'barco', v_cli3, v_un3, c_antes, c_agora, 40) p where p.numero = 'ORÇ-TF3P-MOTOR') then
    raise exception '5b: motorhome apareceu na classe barco';
  end if;
  for v_r in
    select * from (values
      ('Lancha', 'barco'), ('barco', 'barco'), ('Embarcação', 'barco'), ('Outra embarcação', 'barco'), ('Moto aquática', 'barco'),
      ('catamarã', 'barco'), ('Van', 'veiculo'), ('Ônibus', 'veiculo'), ('ducato', 'veiculo'), ('Motor Home', 'veiculo'),
      ('Outro veículo', 'veiculo'), ('Equipamento', 'outro'), ('xyz', null), ('', null), (null, null)
    ) as x(asset, esperado)
  loop
    if public._retorno_classe_do_bem(v_r.asset) is distinct from v_r.esperado then
      raise exception '5c: "%" deu %, esperava %', v_r.asset, public._retorno_classe_do_bem(v_r.asset), v_r.esperado;
    end if;
  end loop;

  -- 6. Rótulo: 1 família, 2 famílias, 3 famílias (na ordem da tabela, não na do array).
  v_j := public._retorno_familia_rotulo(array['bateria']);
  if v_j is distinct from '{"titulo": "Baterias", "do_servico": "das baterias"}'::jsonb then
    raise exception '6a: %', v_j;
  end if;
  v_j := public._retorno_familia_rotulo(array['inversor', 'bateria']);
  if v_j is distinct from '{"titulo": "Baterias e inversor", "do_servico": "das baterias e do inversor"}'::jsonb then
    raise exception '6b: %', v_j;
  end if;
  v_j := public._retorno_familia_rotulo(array['bateria', 'inversor', 'geladeira']);
  if v_j ->> 'titulo' is distinct from 'Baterias, inversor e outros' or v_j -> 'do_servico' <> 'null'::jsonb then
    raise exception '6c: %', v_j;
  end if;
  v_j := public._retorno_familia_rotulo(array['starlink']);
  if v_j ->> 'titulo' is distinct from 'Antena Starlink' or v_j ->> 'do_servico' is distinct from 'da antena Starlink' then
    raise exception '6d: %', v_j;
  end if;

  -- _retorno_os_aprovada: a definição de "praticado" da F3.
  if public._retorno_os_aprovada('cancelled', 'approved') or not public._retorno_os_aprovada('open', 'draft')
     or not public._retorno_os_aprovada('draft', 'approved') or public._retorno_os_aprovada('draft', 'draft')
     or public._retorno_os_aprovada('draft', null) then
    raise exception '7: _retorno_os_aprovada errada';
  end if;

  raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_parecido', true, '{}');
end
$parecido$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
