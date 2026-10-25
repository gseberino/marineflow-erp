-- Prova da prontidão da Agenda de Produção, Fase 1 (pacote P3): migration 20261024160400.
-- bancada: depende de 20261024160400
--
-- Com a fixture de 23/10 (scripts/bancada-agenda/fixture-2310.sql), os números da spec §5.4/§6:
--   A  carteira: os 11 itens na ordem do número, a data de aprovação, o sinal pago e a janela antiga
--   B  duração pelo valor: as faixas das 12 OS (74 1,5–3; 69 2–3,5; 100 2–4; 104 1–2; 112 1–2; 96 meio dia, 1 pessoa;
--      ORÇ-00083 meio dia a 1 dia; ORÇ-00119 1,5–2,5; ORÇ-00095 sem base; 32 4,5–9; 33 3,5–7,5; 76 meio dia)
--   C  presença do dono: 96 sempre (diagnóstico); 74 abre e fecha; marina nova; comissionamento; o que o dono disse
--   D  estados da carteira (69/74/100/104/112/96 aguardando material; ORÇ-00083 esperando você; ORÇ-00095 sem sinal;
--      32/33/76 aguardando o cliente); "quase pronta" só 74 e 96
--   E  material: zero linhas = não conferido; peça embutida em 100 e 104; o compressor "chegou?"; o Cerbo "comprando
--      hoje chega qui 29/10"; os 4 itens da 69 "de quem e quando?"
--   F  fatos do dono e níveis: A exige a quantidade completa; "chega dia 3" do dono = C; início pelo material SEM
--      folga remota; compra combinada; compre até no futuro; o compressor chegou; peça embutida respondida; OC
--      recebida; previsão vencida; dispensado e "pode começar sem"; a sincronização não muda a leitura
--   G  estados especiais: congelada, marcada, parada / em execução, sinal pendente, bem fora do horizonte, escopo,
--      concluída, fora da carteira, prazo do cliente, OS inexistente
--   H  duração dita pelo dono (dias e quem, por turno; os meios-dias derivados; o dono fora da conta da equipe)
--   I  resolvedores: Lenine → OS-00074; Rodrigo e Kalmar ambíguos (2 opções com os números); OS-00999 não achei;
--      César + aprovar → ORÇ-00119; número ORÇ e OS iguais = ambíguo; eu → Gustavo; Roberto → Roberto
--   J  capacidade: 6,77 diárias por semana → 5,41 comprometíveis; a grade (sábado, domingo, Finados, sem padrão, o
--      Mickael fora); o padrão do dono entra na conta; exceções e recesso
-- Sempre (com ou sem a fixture):
--   K  determinismo: cada leitura 2× = o mesmo md5; nada é gravado
--   L  portas: anon sem nada; authenticated executa as leituras; nenhuma é security definer; STABLE/IMMUTABLE;
--      search_path fixo; o técnico (sem ler agenda_config) recebe erro, nunca "livre"
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261024160400
--   Em produção, só DEPOIS de aplicar 160000..160400, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase1_prontidao.sql
--   Sem a fixture (produção), A–J saem PULADO e só K e L (e as regras gerais em P) rodam. Os cenários mexem em
--   linhas só dentro de subtransações desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Acumula um resultado num jsonb (sobrevive ao "desfaz" das subtransações).
create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
create function pg_temp.pr(p_n text) returns jsonb language sql stable as $f$
  select public.os_prontidao(pg_temp.os(p_n), date '2026-10-23')
$f$;
create function pg_temp.restr(p jsonb, p_tipo text) returns jsonb language sql immutable as $f$
  select e from jsonb_array_elements(coalesce(p -> 'restricoes', '[]'::jsonb)) e where e ->> 'tipo' = p_tipo limit 1
$f$;
create function pg_temp.tipos(p jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(e ->> 'tipo', ',' order by o), '')
    from jsonb_array_elements(coalesce(p -> 'restricoes', '[]'::jsonb)) with ordinality t(e, o)
$f$;
create function pg_temp.item(p jsonb, p_linha uuid) returns jsonb language sql immutable as $f$
  select e from jsonb_array_elements(coalesce(p #> '{material,itens}', '[]'::jsonb)) e where e ->> 'linha' = p_linha::text
  limit 1
$f$;
-- A prontidão sem os ids das linhas de material (a sincronização cria a linha; o resto tem de ficar igual).
create function pg_temp.sem_ids(p jsonb) returns jsonb language sql immutable as $f$
  select jsonb_set(p, '{material,itens}',
                   coalesce((select jsonb_agg(e - 'id' order by o)
                               from jsonb_array_elements(p #> '{material,itens}') with ordinality t(e, o)), '[]'::jsonb))
$f$;

-- ── A–E, I, J: leituras sobre a fixture como ela está ───────────────────────────────────────────────────
do $leitura$
declare
  c_hoje   constant date := date '2026-10-23';
  v_fixture boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                   and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000104')
                   and exists (select 1 from public.app_users where id = 'aa000000-0000-4000-8000-000000000001');
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_res    jsonb := '[]'::jsonb;
  r        jsonb;
  x        jsonb;
  v_txt    text;
  v_txt2   text;
  v_ok     boolean;
  v_n      int;
begin
  if not v_fixture then
    insert into _resultado values ('A–J com a fixture de 23/10', true, 'PULADO: sem a fixture (produção); rodam K, L e P');
    return;
  end if;

  -- ── A. Carteira ──
  select string_agg(numero, ' ' order by ord), count(*) into v_txt, v_n
    from (select numero, row_number() over () as ord from public.os_carteira(c_hoje)) k;
  v_res := pg_temp.ok(v_res, 'A1 carteira: 11 itens, na ordem do número',
    v_n = 11 and v_txt = 'ORÇ-00083 ORÇ-00095 OS-00032 OS-00033 OS-00069 OS-00074 OS-00076 OS-00096 OS-00100 OS-00104 OS-00112',
    v_txt);
  select bool_and(case k.numero
           when 'OS-00069' then k.aprovada_em = '2026-07-29' and k.sinal_pago = 4500
           when 'OS-00074' then k.aprovada_em = '2026-08-12' and k.sinal_pago = 2280
           when 'OS-00104' then k.aprovada_em = '2026-09-23' and k.sinal_pago = 2070
                                and k.agendada_de = '2026-10-06' and k.agendada_ate = '2026-10-08'
           when 'OS-00112' then k.aprovada_em = '2026-10-06' and k.sinal_pago = 7600
           when 'OS-00096' then k.aprovada_em = '2026-10-16' and k.sinal_previsto = 0
           when 'ORÇ-00083' then k.aprovada_em = '2026-08-23' and k.eh_orcamento and k.cliente_curto = 'Robson'
           when 'ORÇ-00095' then k.quote_status = 'awaiting_deposit' and k.cliente_curto = 'MP'
           else true end)
    into v_ok from public.os_carteira(c_hoje) k;
  v_res := pg_temp.ok(v_res, 'A2 aprovação (conversão, senão assinatura), sinal pago e janela antiga da 104', v_ok);
  v_res := pg_temp.ok(v_res, 'A3 fora da carteira: ORÇ-00119 (enviado), ORÇ-00114/115 (rascunho) e OS-00050 (concluída)',
    not exists (select 1 from public.os_carteira(c_hoje) k
                 where k.numero in ('ORÇ-00119', 'ORÇ-00114', 'ORÇ-00115', 'OS-00050')));

  -- ── B. Duração pelo valor ──
  select string_agg(format('%s %s', so.service_order_number,
           case when (d ->> 'sem_base')::boolean then 'sem base'
                else format('%s-%s/%s', d ->> 'dias_otimista', d ->> 'dias_realista', d ->> 'pessoas') end),
           ' ' order by so.service_order_number collate "C")
    into v_txt
    from public.service_orders so, lateral public.os_duracao_sugerida(so.id) d
   where so.service_order_number in ('OS-00074', 'OS-00069', 'OS-00100', 'OS-00104', 'OS-00112', 'OS-00096', 'ORÇ-00083',
                                     'ORÇ-00119', 'ORÇ-00095', 'OS-00032', 'OS-00033', 'OS-00076');
  v_res := pg_temp.ok(v_res, 'B1 as faixas das 12 OS (dias otimista-realista/pessoas)',
    v_txt = 'ORÇ-00083 0.5-1/2 ORÇ-00095 sem base ORÇ-00119 1.5-2.5/2 OS-00032 4.5-9/2 OS-00033 3.5-7.5/2 '
            'OS-00069 2-3.5/2 OS-00074 1.5-3/2 OS-00076 0.5-0.5/1 OS-00096 0.5-0.5/1 OS-00100 2-4/2 OS-00104 1-2/2 OS-00112 1-2/2',
    v_txt);
  v_res := pg_temp.ok(v_res, 'B2 o texto: "1,5 a 3 dias com 2 pessoas (estimativa minha, pelo valor)" (74)',
    public.os_duracao_sugerida(pg_temp.os('74')) ->> 'texto' = '1,5 a 3 dias com 2 pessoas (estimativa minha, pelo valor)',
    public.os_duracao_sugerida(pg_temp.os('74')) ->> 'texto');
  v_res := pg_temp.ok(v_res, 'B3 o texto: "meio dia, 1 pessoa (…)" (96) e "meio dia a 1 dia com 2 pessoas (…)" (ORÇ-00083)',
    public.os_duracao_sugerida(pg_temp.os('96')) ->> 'texto' = 'meio dia, 1 pessoa (estimativa minha, pelo valor)'
    and public.os_duracao_sugerida(pg_temp.os('83')) ->> 'texto' = 'meio dia a 1 dia com 2 pessoas (estimativa minha, pelo valor)',
    public.os_duracao_sugerida(pg_temp.os('83')) ->> 'texto');
  r := public.os_duracao_sugerida(pg_temp.os('95'));
  v_res := pg_temp.ok(v_res, 'B4 ORÇ-00095 (tudo material de texto livre): sem base → pergunta',
    (r ->> 'sem_base')::boolean and r ->> 'texto' = 'sem base para estimar: quantos dias?' and (r ->> 'mo')::numeric = 0,
    r::text);
  r := public.os_duracao_sugerida(pg_temp.os('76'));
  v_res := pg_temp.ok(v_res, 'B5 76: o conector (material de texto livre que entra na compra) sai da mão de obra; 2,5 h',
    (r ->> 'mo')::numeric = 500 and (r ->> 'horas')::numeric = 2.5, r::text);
  r := public.os_duracao_sugerida(pg_temp.os('74'));
  v_res := pg_temp.ok(v_res, 'B6 74: diárias-pessoa 2,85 a 5,97; sugerida 2,5 (meio dia mais perto da média); 3 a 6 diárias',
    (r ->> 'dp_otimista')::numeric = 2.85 and (r ->> 'dp_realista')::numeric = 5.97 and (r ->> 'sugerida')::numeric = 2.5
    and (r ->> 'diarias_otimista')::numeric = 3 and (r ->> 'diarias_realista')::numeric = 6, r::text);
  v_res := pg_temp.ok(v_res, 'B7 OS inexistente: "Não encontrei"',
    public.os_duracao_sugerida('00000000-0000-4000-8000-000000000000') = '{"ok": false, "texto": "Não encontrei esse serviço."}'::jsonb);

  -- ── C. Presença do dono ──
  v_res := pg_temp.ok(v_res, 'C1 96 (visita de diagnóstico): sempre, motivo diagnóstico, pela regra',
    public.os_presenca_do_dono(pg_temp.os('96')) = '{"presenca": "sempre", "motivo": "diagnóstico", "fonte": "regra"}'::jsonb,
    public.os_presenca_do_dono(pg_temp.os('96'))::text);
  v_res := pg_temp.ok(v_res, 'C2 74 (marina com OS concluída antes): abre e fecha',
    public.os_presenca_do_dono(pg_temp.os('74')) ->> 'presenca' = 'abre_e_fecha',
    public.os_presenca_do_dono(pg_temp.os('74'))::text);
  v_res := pg_temp.ok(v_res, 'C3 104 (o diagnóstico de vazamento não é a linha principal): abre e fecha',
    public.os_presenca_do_dono(pg_temp.os('104')) ->> 'presenca' = 'abre_e_fecha');

  -- ── D. Estados da carteira ──
  select string_agg(format('%s=%s', p ->> 'numero', p ->> 'estado'), ' ' order by p ->> 'numero' collate "C"),
         string_agg(p ->> 'numero', ' ' order by p ->> 'numero' collate "C") filter (where (p ->> 'quase_pronta')::boolean)
    into v_txt, v_txt2
    from public.os_prontidao_carteira(c_hoje) p;
  v_res := pg_temp.ok(v_res, 'D1 estados: 69/74/100/104/112/96 material; ORÇ-00083 você; ORÇ-00095 sinal; 32/33/76 cliente',
    v_txt = 'ORÇ-00083=esperando_voce ORÇ-00095=sem_sinal OS-00032=aguardando_cliente OS-00033=aguardando_cliente '
            'OS-00069=aguardando_material OS-00074=aguardando_material OS-00076=aguardando_cliente '
            'OS-00096=aguardando_material OS-00100=aguardando_material OS-00104=aguardando_material '
            'OS-00112=aguardando_material',
    v_txt);
  v_res := pg_temp.ok(v_res, 'D2 "quase pronta" = só 74 e 96 (a única trava é "tem peça a comprar?", sem peça embutida)',
    v_txt2 = 'OS-00074 OS-00096', v_txt2);
  r := pg_temp.pr('83');
  v_res := pg_temp.ok(v_res, 'D3 ORÇ-00083: "assinado em 23/08 e nunca virou OS: converter ou arquivar?" (dono, trava)',
    pg_temp.restr(r, 'orcamento') ->> 'texto' = 'assinado em 23/08 e nunca virou OS: converter ou arquivar?'
    and (pg_temp.restr(r, 'orcamento') ->> 'bloqueia')::boolean and pg_temp.restr(r, 'orcamento') ->> 'quem' = 'dono'
    and r ->> 'estado_texto' = 'assinado em 23/08 e nunca virou OS',
    pg_temp.tipos(r) || ' | ' || (r ->> 'estado_texto'));
  r := pg_temp.pr('95');
  v_res := pg_temp.ok(v_res, 'D4 ORÇ-00095: sem sinal (cliente); a duração pergunta "quantos dias" sem chute',
    pg_temp.restr(r, 'sinal') ->> 'quem' = 'cliente' and r ->> 'estado_texto' = 'esperando o sinal'
    and pg_temp.restr(r, 'duracao') ->> 'texto' = 'quantos dias e com quem? (o orçamento não dá base para estimar)',
    pg_temp.tipos(r));
  r := pg_temp.pr('32');
  v_res := pg_temp.ok(v_res, 'D5 32/33/76: esperando o cliente (cliente, trava)',
    r ->> 'estado_texto' = 'esperando o cliente' and pg_temp.restr(r, 'cliente') ->> 'quem' = 'cliente'
    and pg_temp.pr('76') ->> 'estado' = 'aguardando_cliente', pg_temp.tipos(r));
  r := pg_temp.pr('74');
  v_res := pg_temp.ok(v_res, 'D6 duração não confirmada: não trava e traz o chute ("quantos dias e com quem? (chute: 1,5 a 3 dias, 2 pessoas)")',
    pg_temp.restr(r, 'duracao') ->> 'texto' = 'quantos dias e com quem? (chute: 1,5 a 3 dias, 2 pessoas)'
    and not (pg_temp.restr(r, 'duracao') ->> 'bloqueia')::boolean and r #>> '{duracao,fonte}' = 'sugerida',
    pg_temp.restr(r, 'duracao')::text);
  r := pg_temp.pr('112');
  v_res := pg_temp.ok(v_res, 'D7 prazo padrão: aprovação + 20 dias úteis (112: 06/10 → qui 05/11); razão crítica 8 ÷ 2 = 4',
    r ->> 'prazo_efetivo' = '2026-11-05' and r ->> 'prazo_fonte' = 'padrão' and (r ->> 'razao_critica')::numeric = 4,
    format('%s %s %s', r ->> 'prazo_efetivo', r ->> 'prazo_fonte', r ->> 'razao_critica'));
  select string_agg(p ->> 'numero', ' ' order by p ->> 'numero' collate "C") into v_txt
    from public.os_prontidao_carteira(c_hoje) p
   where (p ->> 'prazo_efetivo')::date < c_hoje and p ->> 'estado' not in ('aguardando_cliente', 'congelada', 'sem_sinal');
  -- A §6 lista 4 atrasados; o ORÇ-00095 também tem o prazo padrão vencido (criado 09/09 + 20 du = 07/10), mas a espera
  -- do sinal é do cliente: a leitura de atrasos (P4) tem de deixar sem_sinal de fora, como aguardando_cliente.
  v_res := pg_temp.ok(v_res, 'D8 passaram do prazo padrão: Robson ORÇ-00083, Vanderlei, Lenine e Flávio (sem os parados no cliente nem o sem sinal)',
    v_txt = 'ORÇ-00083 OS-00069 OS-00074 OS-00104'
    and pg_temp.pr('95') ->> 'prazo_efetivo' = '2026-10-07' and pg_temp.pr('95') ->> 'estado' = 'sem_sinal', v_txt);
  -- A conta da §6: o backlog executável (sem os parados no cliente, os congelados e o sem sinal) em diárias-pessoa.
  select format('%s a %s', trim_scale(sum((p #>> '{duracao,dp_otimista}')::numeric)),
                trim_scale(sum((p #>> '{duracao,dp_realista}')::numeric))), count(*)
    into v_txt, v_n
    from public.os_prontidao_carteira(c_hoje) p
   where p ->> 'estado' not in ('congelada', 'aguardando_cliente', 'sem_sinal');
  v_res := pg_temp.ok(v_res, 'D9 backlog executável da §6: 7 serviços, 16,5 a 31,5 diárias-pessoa (74 3–6, 69 4–7, 100 4–8, …)',
    v_n = 7 and v_txt = '16.5 a 31.5', format('%s serviços, %s', v_n, v_txt));

  -- ── E. Material ──
  r := pg_temp.pr('74');
  v_res := pg_temp.ok(v_res, 'E1 zero linhas de material = não conferido, nunca completo (74): "tem peça a comprar?"',
    r #>> '{material,estado}' = 'nao_conferido' and jsonb_array_length(r #> '{material,itens}') = 0
    and pg_temp.restr(r, 'material_nao_conferido') ->> 'texto' = 'tem peça a comprar? (o orçamento não tem nenhuma)'
    and r ->> 'estado_texto' = 'falta você dizer se tem peça a comprar',
    pg_temp.tipos(r));
  v_res := pg_temp.ok(v_res, 'E2 96 também: não conferido, mesmo sendo diagnóstico (uma pergunta, sem exceção)',
    pg_temp.pr('96') #>> '{material,estado}' = 'nao_conferido'
    and pg_temp.restr(pg_temp.pr('96'), 'material_nao_conferido') is not null);
  r := pg_temp.pr('100');
  select string_agg(e ->> 'curto', ' | ' order by o) into v_txt
    from jsonb_array_elements(r #> '{material,embutidas}') with ordinality t(e, o);
  v_res := pg_temp.ok(v_res, 'E3 100: peça embutida em Barramento (2.804), Realocação do banco (1.135) e Migração (classificador: material)',
    v_txt = 'Barramento e proteções… | Realocação do banco… | Migração dos circuitos…'
    and pg_temp.restr(r, 'peca_embutida') ->> 'texto'
        = 'tem peça embutida em "Barramento e proteções…" ou "Realocação do banco…" (e mais 1)?'
    and pg_temp.restr(r, 'material_nao_conferido') is null and r #>> '{material,estado}' = 'nao_conferido'
    and not (r ->> 'quase_pronta')::boolean,
    v_txt || ' | ' || pg_temp.tipos(r));
  r := pg_temp.pr('104');
  select string_agg(e ->> 'curto', ' | ' order by o) into v_txt
    from jsonb_array_elements(r #> '{material,embutidas}') with ordinality t(e, o);
  v_res := pg_temp.ok(v_res, 'E4 104: peça embutida em "Conversão do sistema…" (2.500) e "Substituição da tampa…" (cita a peça)',
    v_txt = 'Conversão do sistema… | Substituição da tampa…'
    and pg_temp.restr(r, 'peca_embutida') ->> 'texto' = 'tem peça embutida em "Conversão do sistema…" ou "Substituição da tampa…"?',
    v_txt);
  x := pg_temp.item(r, '71000000-0000-4000-8000-000000000001');
  v_res := pg_temp.ok(v_res, 'E5 104: o compressor (OC-00004, Mateus sem cidade/UF) é D sem data → "(pedido em 13/10) chegou?"',
    x ->> 'nivel' = 'D' and x ->> 'situacao' = 'a_caminho' and x ->> 'data' is null and x ->> 'comprado_em' = '2026-10-13'
    and r #>> '{material,estado}' = 'sem_previsao'
    and pg_temp.restr(r, 'comprado_sem_previsao') ->> 'texto' = '"Compressor 12V de…" (pedido em 13/10) chegou?'
    and r ->> 'estado_texto' = 'falta você dizer se "Compressor 12V de…" (pedido em 13/10) chegou'
    and pg_temp.tipos(r) = 'comprado_sem_previsao,peca_embutida,duracao',
    pg_temp.tipos(r) || ' | ' || x::text);
  r := pg_temp.pr('112');
  x := pg_temp.item(r, md5('peca:112:2')::uuid);
  v_res := pg_temp.ok(v_res, 'E6 112: o Cerbo (Kamell ES = outro estado, 4 du) compre até ter 20/10 → "comprando hoje, chega qui 29/10"',
    x ->> 'nivel' = 'D' and x ->> 'classe' = 'outro_estado' and x ->> 'data' = '2026-10-29' and x ->> 'compre_ate' = '2026-10-20'
    and x ->> 'data_texto' = 'se comprar hoje, chega por volta de qui 29/10'
    and pg_temp.restr(r, 'sem_previsao') ->> 'texto'
        = '4 itens sem compra registrada (comprando hoje, "Central de controle…" chega por volta de qui 29/10)'
    and pg_temp.restr(r, 'sem_previsao') ->> 'pergunta' = 'o que já está na mão e o que falta? Quando chega?',
    x::text);
  v_res := pg_temp.ok(v_res, 'E7 112: os outros 3 itens sem fornecedor são E; a confiança é a do pior (E)',
    (select count(*) from jsonb_array_elements(r #> '{material,itens}') e where e ->> 'nivel' = 'E') = 3
    and r #>> '{material,confianca}' = 'E' and r ->> 'est' is null and r #>> '{material,inicio_mat}' is null);
  r := pg_temp.pr('69');
  v_res := pg_temp.ok(v_res, 'E8 69: 4 peças sem estoque e sem fornecedor → "4 itens a comprar: de quem e quando?"',
    pg_temp.restr(r, 'sem_previsao') ->> 'texto' = '4 itens a comprar: de quem e quando?'
    and r ->> 'estado_texto' = 'falta você dizer de quem e quando comprar 4 itens'
    and jsonb_array_length(r #> '{material,itens}') = 4,
    pg_temp.restr(r, 'sem_previsao')::text);
  -- FASE 4 (P1): com o prazo do fornecedor numa fonte só (20261027100100), as duas Kamell ATIVAS com o mesmo nome e classe
  -- diferente são cadastro repetido: só a principal (a de Vila Velha, que tem o produto do Cerbo) tem classe; a de Itajaí
  -- fica sem classe até o dono dizer (a pergunta é do P5). Antes da Fase 4 (corte --ate), a de Itajaí era local.
  v_res := pg_temp.ok(v_res, 'E9 classes: Premel local (1 du), Kamell ES outro estado (4), Kamell SC local (Fase 4: cadastro repetido, sem classe), Mateus desconhecida',
    public._agenda_classe_do_fornecedor('dd000000-0000-4000-8000-000000000001') = 'entrega_local'
    and public._agenda_classe_do_fornecedor('dd000000-0000-4000-8000-000000000002') = 'outro_estado'
    and public._agenda_classe_do_fornecedor('dd000000-0000-4000-8000-000000000003') is not distinct from
        case when to_regprocedure('public._agenda_prazo_do_fornecedor(uuid)') is null then 'entrega_local' end
    and public._agenda_classe_do_fornecedor('dd000000-0000-4000-8000-000000000004') is null
    and public._agenda_classe_do_fornecedor(null) is null
    and public._agenda_prazo_da_classe('entrega_local') = 1 and public._agenda_prazo_da_classe('outro_estado') = 4
    and public._agenda_prazo_da_classe(null) is null);
  v_res := pg_temp.ok(v_res, 'E10 o nome curto da linha: 3 palavras + "…", maiúsculas viram minúsculas, parêntese aberto sai',
    public._agenda_linha_curta('Conversão do sistema de refrigeração para 12V — Refrigerador Consul CRC28FB') = 'Conversão do sistema…'
    and public._agenda_linha_curta('Visita técnica — diagnóstico') = 'Visita técnica — diagnóstico'
    and public._agenda_linha_curta('CENTRAL DE CONTROLE CERBO GX VICTRON') = 'Central de controle…'
    and public._agenda_linha_curta('Sikaflex 221 (selante de vedação)') = 'Sikaflex 221…'
    and public._agenda_linha_curta('Posicionamento, alinhamento, base, coxins') = 'Posicionamento, alinhamento, base…'
    and public._agenda_linha_curta(null) is null,
    public._agenda_linha_curta('Sikaflex 221 (selante de vedação)'));

  -- ── I. Resolvedores ──
  r := public.agenda_resolver_os('Lenine', c_hoje);
  v_res := pg_temp.ok(v_res, 'I1 "Lenine" → OS-00074', r ->> 'status' = 'ok' and r ->> 'numero' = 'OS-00074', r::text);
  r := public.agenda_resolver_os('o barco do Lenine', c_hoje);
  v_res := pg_temp.ok(v_res, 'I2 "o barco do Lenine" → OS-00074 (palavras vazias saem)', r ->> 'numero' = 'OS-00074', r::text);
  r := public.agenda_resolver_os('Rodrigo', c_hoje);
  v_res := pg_temp.ok(v_res, 'I3 "Rodrigo" → ambíguo, 2 opções, a pergunta pronta com os dois números',
    r ->> 'status' = 'ambiguo' and jsonb_array_length(r -> 'opcoes') = 2
    and r ->> 'texto' = 'Qual Rodrigo: OS-00076 (Substituição de conector…, esperando o cliente) ou OS-00096 (Visita técnica — diagnóstico, aprovada)?',
    r ->> 'texto');
  r := public.agenda_resolver_os('Kalmar', c_hoje);
  v_res := pg_temp.ok(v_res, 'I4 "Kalmar" → ambíguo (OS-00032 e OS-00033)',
    r ->> 'status' = 'ambiguo' and r ->> 'texto' like 'Qual Kalmar: OS-00032 (%) ou OS-00033 (%)?', r ->> 'texto');
  r := public.agenda_resolver_os('OS-00999', c_hoje);
  v_res := pg_temp.ok(v_res, 'I5 "OS-00999" → não achei',
    r = '{"status": "nao_achei", "opcoes": [], "texto": "Não encontrei a OS-00999."}'::jsonb, r::text);
  r := public.agenda_resolver_os('César', c_hoje, true);
  v_res := pg_temp.ok(v_res, 'I6 "César" para aprovar → ORÇ-00119 (o enviado; os rascunhos 114/115 ficam fora)',
    r ->> 'status' = 'ok' and r ->> 'numero' = 'ORÇ-00119' and (r ->> 'eh_orcamento')::boolean, r::text);
  r := public.agenda_resolver_os('César', c_hoje);
  v_res := pg_temp.ok(v_res, 'I7 "César" sem aprovar → não está na carteira; diz os números de fora, nunca escolhe',
    r ->> 'status' = 'nao_achei' and r ->> 'texto' like 'Não encontrei "César" entre os serviços da carteira (fora dela: %ORÇ-00119%).'
    and r ->> 'id' is null, r ->> 'texto');
  r := public.agenda_resolver_os('a OS da Maria', c_hoje);
  v_res := pg_temp.ok(v_res, 'I7b nome que não está na carteira: as palavras que buscam, como o dono falou, sem artigo antes',
    r = '{"status": "nao_achei", "opcoes": [], "texto": "Não encontrei \"Maria\" entre os serviços da carteira."}'::jsonb, r::text);
  r := public.agenda_resolver_os('ORÇ-00119', c_hoje);
  v_res := pg_temp.ok(v_res, 'I8 número fora da carteira diz o status: "O ORÇ-00119 foi enviado e espera a aprovação do cliente."',
    r ->> 'status' = 'fora_da_carteira' and r ->> 'texto' = 'O ORÇ-00119 foi enviado e espera a aprovação do cliente.',
    r::text);
  r := public.agenda_resolver_os('OS-00050', c_hoje);
  v_res := pg_temp.ok(v_res, 'I9 "OS-00050" → "A OS-00050 já foi concluída."',
    r ->> 'status' = 'fora_da_carteira' and r ->> 'texto' = 'A OS-00050 já foi concluída.', r::text);
  v_res := pg_temp.ok(v_res, 'I10 números como o localizarOrdem: "112", "00104", "orc 83", "OS-76" e o id',
    public.agenda_resolver_os('112', c_hoje) ->> 'numero' = 'OS-00112'
    and public.agenda_resolver_os('00104', c_hoje) ->> 'numero' = 'OS-00104'
    and public.agenda_resolver_os('orc 83', c_hoje) ->> 'numero' = 'ORÇ-00083'
    and public.agenda_resolver_os('OS-76', c_hoje) ->> 'numero' = 'OS-00076'
    and public.agenda_resolver_os(pg_temp.os('74')::text, c_hoje) ->> 'numero' = 'OS-00074'
    and public.agenda_resolver_os('99', c_hoje) ->> 'texto' = 'Não encontrei o ORÇ-00099 nem a OS-00099.');
  v_res := pg_temp.ok(v_res, 'I11 vazio ou só palavra vazia: pede o nome ou o número',
    public.agenda_resolver_os('', c_hoje) ->> 'status' = 'nao_achei'
    and public.agenda_resolver_os('o do', c_hoje) ->> 'status' = 'nao_achei');
  r := public.agenda_resolver_pessoa('eu', c_admin, c_hoje);
  v_res := pg_temp.ok(v_res, 'I12 "eu" → Gustavo (o sócio do login), eh_dono',
    r ->> 'status' = 'ok' and r ->> 'payee_id' = 'bb000000-0000-4000-8000-000000000001' and (r ->> 'eh_dono')::boolean, r::text);
  v_res := pg_temp.ok(v_res, 'I13 "você", "comigo" e "Gustavo" → o dono; sem login, o único sócio',
    public.agenda_resolver_pessoa('você', c_admin, c_hoje) ->> 'nome_curto' = 'Gustavo'
    and public.agenda_resolver_pessoa('comigo', c_admin, c_hoje) ->> 'nome_curto' = 'Gustavo'
    and (public.agenda_resolver_pessoa('Gustavo', c_admin, c_hoje) ->> 'eh_dono')::boolean
    and public.agenda_resolver_pessoa('eu', null, c_hoje) ->> 'nome_curto' = 'Gustavo');
  r := public.agenda_resolver_pessoa('Roberto', c_admin, c_hoje);
  v_res := pg_temp.ok(v_res, 'I14 "Roberto" → Roberto; "o João" e "joao" → João; "Pedro" → não conheço',
    r ->> 'payee_id' = 'bb000000-0000-4000-8000-000000000002' and not (r ->> 'eh_dono')::boolean
    and public.agenda_resolver_pessoa('o João', c_admin, c_hoje) ->> 'payee_id' = 'bb000000-0000-4000-8000-000000000003'
    and public.agenda_resolver_pessoa('joao', c_admin, c_hoje) ->> 'payee_id' = 'bb000000-0000-4000-8000-000000000003'
    and public.agenda_resolver_pessoa('Pedro', c_admin, c_hoje)
        = '{"status": "nao_achei", "texto": "Não conheço ninguém chamado Pedro na equipe."}'::jsonb,
    r::text);

  -- ── J. Capacidade ──
  r := public.agenda_capacidade_semanal(c_hoje);
  v_res := pg_temp.ok(v_res, 'J1 um número só: 6,77 diárias por semana × 0,80 = 5,41 comprometíveis, sem contar você',
    (r ->> 'diarias_semana')::numeric = 6.77 and (r ->> 'comprometivel')::numeric = 5.41 and not (r ->> 'conta_dono')::boolean,
    (r - 'pessoas')::text);
  v_res := pg_temp.ok(v_res, 'J2 por pessoa: Roberto 4,43 e João 2,33; o Mickael fora (sem padrão pela regra da semente)',
    (select string_agg(format('%s %s', e ->> 'nome', e ->> 'diarias_semana'), ', ' order by e ->> 'nome')
       from jsonb_array_elements(r -> 'pessoas') e) = 'João 2.33, Roberto 4.43',
    (r -> 'pessoas')::text);
  v_res := pg_temp.ok(v_res, 'J3 última diária sáb 17/10; 5 dias úteis sem lançar; o aviso',
    r ->> 'ultima_diaria' = '2026-10-17' and (r ->> 'dias_sem_lancar')::int = 5
    and r ->> 'aviso' = 'nenhuma diária foi lançada depois de sáb 17/10', (r - 'pessoas')::text);
  select count(*), count(distinct payee_id) into v_n, v_txt2 from public.agenda_capacidade('2026-10-24', '2026-10-27', c_hoje);
  v_res := pg_temp.ok(v_res, 'J4 a grade: 3 pessoas (você, Roberto, João) × 4 dias × 2 turnos; o Mickael não aparece',
    v_n = 24 and not exists (select 1 from public.agenda_capacidade('2026-10-24', '2026-10-27', c_hoje)
                              where payee_id = 'bb000000-0000-4000-8000-000000000004'),
    v_n::text);
  select string_agg(format('%s %s %s %s %s', g.pessoa, to_char(g.dia, 'DD/MM'), g.turno, g.situacao, g.meios_esperados),
                    ' | ' order by g.eh_dono desc, g.pessoa, g.dia, g.turno)
    into v_txt
    from public.agenda_capacidade('2026-10-24', '2026-10-27', c_hoje) g
   where g.turno = 'manha';
  v_res := pg_temp.ok(v_res, 'J5 sábado e domingo fora; Roberto seg 0,6 e ter 0,8333; João sem padrão na segunda; você sem padrão',
    v_txt = 'Gustavo 24/10 manha fim_de_semana 0 | Gustavo 25/10 manha fim_de_semana 0 | Gustavo 26/10 manha sem_padrao 0 | '
            'Gustavo 27/10 manha sem_padrao 0 | João 24/10 manha fim_de_semana 0 | João 25/10 manha fim_de_semana 0 | '
            'João 26/10 manha sem_padrao 0 | João 27/10 manha livre 0.5000 | Roberto 24/10 manha fim_de_semana 0 | '
            'Roberto 25/10 manha fim_de_semana 0 | Roberto 26/10 manha livre 0.6000 | Roberto 27/10 manha livre 0.8333',
    v_txt);
  v_res := pg_temp.ok(v_res, 'J6 os motivos: "sábado só quando vocês combinam", Finados, e o seu "ainda não disse"',
    (select motivo from public.agenda_capacidade('2026-10-24', '2026-10-24', c_hoje) limit 1) = 'sábado só quando vocês combinam'
    and (select bool_and(situacao = 'feriado' and motivo = 'Finados') from public.agenda_capacidade('2026-11-02', '2026-11-02', c_hoje))
    and (select motivo from public.agenda_capacidade('2026-10-26', '2026-10-26', c_hoje) where eh_dono limit 1)
        = 'você ainda não disse quais dias fica em campo');

  perform pg_temp.gravar(v_res);
end
$leitura$;

-- ── F, G, H, I (número ambíguo), J (padrão do dono): cenários, cada um desfeito na hora ─────────────────
do $cenarios$
declare
  c_hoje  constant date := date '2026-10-23';
  v_fixture boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                   and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000104');
  c_premel constant uuid := 'dd000000-0000-4000-8000-000000000001';
  c_kamell_es constant uuid := 'dd000000-0000-4000-8000-000000000002';
  c_rob   constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao  constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_dono  constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_oc4   constant uuid := '70000000-0000-4000-8000-000000000004';
  c_poi   constant uuid := '71000000-0000-4000-8000-000000000001';
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  x       jsonb;
  v_txt   text;
  v_a     text;
  v_b     text;
  v_id    uuid;
begin
  if not v_fixture then
    insert into _resultado values ('F–H cenários com a fixture de 23/10', true, 'PULADO: sem a fixture (produção)');
    return;
  end if;

  -- F1: nível A só com a quantidade completa (69, Porta Fusível MIDI: a OS pede 8).
  begin
    insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                    quantidade_na_mao, situacao, fonte, trecho)
    values (pg_temp.os('69'), md5('peca:69:2')::uuid, 'peca', 'Porta Fusível MIDI', 8, 3, 'falta', 'dono', 'chegaram 3')
    returning id into v_id;
    x := pg_temp.item(pg_temp.pr('69'), md5('peca:69:2')::uuid);
    v_res := pg_temp.ok(v_res, 'F1a 3 de 8 na mão: continua faltando (não é A) e o texto diz quantas estão na mão',
      x ->> 'nivel' <> 'A' and x ->> 'situacao' = 'falta' and (x ->> 'na_mao')::numeric = 3
      and x ->> 'data_texto' = '3 de 8 na mão, faltam 5: a comprar, sem fornecedor', x::text);
    update public.os_material set quantidade_na_mao = 8, situacao = 'na_mao', chegou_em = '2026-10-22' where id = v_id;
    x := pg_temp.item(pg_temp.pr('69'), md5('peca:69:2')::uuid);
    v_res := pg_temp.ok(v_res, 'F1b os 8 na mão: A, "na mão desde qui 22/10", fonte dono',
      x ->> 'nivel' = 'A' and x ->> 'data_texto' = 'na mão desde qui 22/10' and x ->> 'fonte' = 'dono', x::text);
    update public.service_order_parts set quantity = 10 where id = md5('peca:69:2')::uuid;
    x := pg_temp.item(pg_temp.pr('69'), md5('peca:69:2')::uuid);
    v_res := pg_temp.ok(v_res, 'F1c a OS passou a pedir 10 (sem sincronizar): o "na mão" de 8 não completa → falta',
      x ->> 'nivel' <> 'A' and x ->> 'situacao' = 'falta' and (x ->> 'quantidade')::numeric = 10, x::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F1 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F2/F3: Nelson depois da rodada — Cerbo, Orion e cabos na mão; o painel "chega dia 3" (o dono disse).
  begin
    insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                    quantidade_na_mao, situacao, fonte, chegou_em, previsao_ate, previsao_fonte, trecho)
    values (pg_temp.os('112'), md5('peca:112:1')::uuid, 'peca', 'KIT Cabos Comunicação e Energia para Lítio', 1, 1, 'na_mao', 'dono', c_hoje, null, null, 'tão aqui'),
           (pg_temp.os('112'), md5('peca:112:2')::uuid, 'peca', 'CENTRAL DE CONTROLE CERBO GX', 1, 1, 'na_mao', 'dono', c_hoje, null, null, 'tão aqui'),
           (pg_temp.os('112'), md5('peca:112:3')::uuid, 'peca', 'Orion-Tr Smart 12/12-30A Victron (USADO)', 1, 1, 'na_mao', 'dono', c_hoje, null, null, 'tão aqui'),
           (pg_temp.os('112'), md5('peca:112:4')::uuid, 'peca', 'Painel Touch de Monitoramento e Controle de Energia – HBR 7"', 1, 0, 'a_caminho', 'dono', null, '2026-11-03', 'dono', 'o painel chega dia 3');
    r := pg_temp.pr('112');
    x := pg_temp.item(r, md5('peca:112:4')::uuid);
    v_res := pg_temp.ok(v_res, 'F2 "o painel chega dia 3" (do dono) = nível C, "chega ter 03/11 (você disse)", com as palavras',
      x ->> 'nivel' = 'C' and x ->> 'data' = '2026-11-03' and x ->> 'data_texto' = 'chega ter 03/11 (você disse)'
      and x ->> 'trecho' = 'o painel chega dia 3', x::text);
    v_res := pg_temp.ok(v_res, 'F3 previsto: dpm ter 03/11, início pelo material qua 04/11 (chegada + 1 du), pronto a partir de qua 04/11',
      r #>> '{material,estado}' = 'previsto' and r #>> '{material,dpm}' = '2026-11-03'
      and r #>> '{material,inicio_mat}' = '2026-11-04' and r ->> 'est' = '2026-11-04' and r ->> 'estado' = 'pronta'
      and r ->> 'estado_texto' = 'pronto a partir de qua 04/11, se "Painel Touch de…" chegar ter 03/11'
      and r #>> '{material,confianca}' = 'C' and pg_temp.restr(r, 'sem_previsao') is null,
      format('%s | %s | %s', r #>> '{material,estado}', r ->> 'estado_texto', pg_temp.tipos(r)));
    -- Sem folga remota: o mesmo painel vindo de Vila Velha/ES (outro estado) com a data do fornecedor.
    update public.os_material set previsao_fonte = 'fornecedor', fonte = 'fornecedor', fornecedor_id = c_kamell_es
     where service_order_part_id = md5('peca:112:4')::uuid;
    r := pg_temp.pr('112');
    v_res := pg_temp.ok(v_res, 'F3b fornecedor de outro estado com data (B): início qua 04/11 — sem o +1 da folga remota',
      pg_temp.item(r, md5('peca:112:4')::uuid) ->> 'nivel' = 'B' and r #>> '{material,inicio_mat}' = '2026-11-04'
      and r ->> 'est' = '2026-11-04', r #>> '{material,inicio_mat}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F2/F3 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F4: Vanderlei — "compro na Premel terça": D pela classe, início qui 29/10, sem "compre até".
  begin
    insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                    situacao, fonte, fornecedor_id, compra_prevista_em, trecho)
    select pg_temp.os('69'), sop.id, 'peca', left(pr.name, 200), sop.quantity, 'falta', 'dono', c_premel, '2026-10-27',
           'eu compro na Premel terça'
      from public.service_order_parts sop join public.products pr on pr.id = sop.product_id
     where sop.service_order_id = pg_temp.os('69');
    r := pg_temp.pr('69');
    v_res := pg_temp.ok(v_res, 'F4 compra combinada ter 27/10 na Premel (local, 1 du): chega qua 28/10, pronto a partir de qui 29/10',
      (select bool_and(e ->> 'nivel' = 'D' and e ->> 'data' = '2026-10-28' and e ->> 'compre_ate' is null
                       and e ->> 'data_texto' = 'comprando ter 27/10, chega por volta de qua 28/10')
         from jsonb_array_elements(r #> '{material,itens}') e)
      and r ->> 'estado' = 'pronta' and r ->> 'est' = '2026-10-29'
      and r ->> 'estado_texto' = 'pronto a partir de qui 29/10, se a compra sair ter 27/10'
      and pg_temp.restr(r, 'compre_ate') is null and pg_temp.restr(r, 'sem_previsao') is null,
      format('%s | %s', r ->> 'estado_texto', pg_temp.tipos(r)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F4 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F5: compre até no futuro — 112 com "não antes de seg 16/11": o Cerbo (4 du + 1 de folga) compre até seg 09/11.
  begin
    insert into public.os_planejamento (service_order_id, nao_antes_de, nao_antes_motivo)
    values (pg_temp.os('112'), '2026-11-16', 'o barco volta da viagem');
    r := pg_temp.pr('112');
    v_res := pg_temp.ok(v_res, 'F5 programação para trás: "Central de controle…": compre até seg 09/11; "não antes de" é do terceiro e não trava',
      pg_temp.item(r, md5('peca:112:2')::uuid) ->> 'compre_ate' = '2026-11-09'
      and pg_temp.restr(r, 'sem_previsao') ->> 'texto' = '4 itens sem compra registrada ("Central de controle…": compre até seg 09/11)'
      and pg_temp.restr(r, 'nao_antes') ->> 'texto' = 'não antes de seg 16/11: o barco volta da viagem'
      and pg_temp.restr(r, 'nao_antes') ->> 'quem' = 'terceiro' and not (pg_temp.restr(r, 'nao_antes') ->> 'bloqueia')::boolean
      and r ->> 'est_sem_material' = '2026-11-16',
      pg_temp.tipos(r) || ' | ' || coalesce(pg_temp.restr(r, 'sem_previsao') ->> 'texto', '-'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F5 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F6: "o compressor do Flávio chegou dia 14": A; sobra a peça embutida.
  begin
    insert into public.os_material (service_order_id, purchase_order_item_id, origem, descricao, quantidade_necessaria,
                                    quantidade_na_mao, situacao, fonte, chegou_em, trecho)
    values (pg_temp.os('104'), c_poi, 'oc', 'Compressor 12V de geladeira SS65', 1, 1, 'na_mao', 'dono', '2026-10-14',
            'o compressor do Flávio chegou dia 14');
    r := pg_temp.pr('104');
    v_res := pg_temp.ok(v_res, 'F6 compressor na mão desde qua 14/10 (A); falta só dizer da peça embutida nas 2 linhas',
      pg_temp.item(r, c_poi) ->> 'nivel' = 'A' and pg_temp.item(r, c_poi) ->> 'data_texto' = 'na mão desde qua 14/10'
      and r #>> '{material,estado}' = 'nao_conferido' and pg_temp.restr(r, 'comprado_sem_previsao') is null
      and r ->> 'estado_texto' = 'falta você dizer se tem peça embutida em "Conversão do sistema…" e "Substituição da tampa…"',
      r ->> 'estado_texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F6 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F7: peça embutida respondida — pela linha do dono ligada à linha, e pelo "não tem peça a comprar".
  begin
    insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria,
                                    quantidade_na_mao, situacao, fonte, chegou_em, trecho)
    values (pg_temp.os('100'), md5('servico:100:3')::uuid, 'dono', 'barramento: nada a comprar', 1, 0, 'dispensado', 'dono', null,
            'no barramento não tem peça'),
           (pg_temp.os('100'), md5('servico:100:1')::uuid, 'dono', 'baterias', 1, 1, 'na_mao', 'dono', c_hoje,
            'as baterias já estão aqui');
    r := pg_temp.pr('100');
    v_res := pg_temp.ok(v_res, 'F7a respondidas Barramento e Realocação: sobra só a Migração; as baterias são A',
      jsonb_array_length(r #> '{material,embutidas}') = 1 and r #>> '{material,embutidas,0,curto}' = 'Migração dos circuitos…'
      and jsonb_array_length(r #> '{material,itens}') = 1 and r #>> '{material,itens,0,nivel}' = 'A',
      (r #> '{material,embutidas}')::text);
    insert into public.os_planejamento (service_order_id, material_conferido_em) values (pg_temp.os('100'), now());
    r := pg_temp.pr('100');
    v_res := pg_temp.ok(v_res, 'F7b "não tem (mais) peça a comprar" depois das linhas: sem pergunta, material completo, pronto',
      jsonb_array_length(r #> '{material,embutidas}') = 0 and r #>> '{material,estado}' = 'completo'
      and r ->> 'estado' = 'pronta' and r ->> 'estado_texto' = 'pronto a partir de ter 27/10'
      and pg_temp.restr(r, 'peca_embutida') is null and pg_temp.restr(r, 'material_nao_conferido') is null,
      format('%s | %s', r ->> 'estado_texto', pg_temp.tipos(r)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F7 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F8: a OC-00004 recebida — o compressor sai da conta bruta e continua na mão (sem linha nenhuma em os_material).
  begin
    update public.purchase_orders set status = 'received', received_date = '2026-10-20' where id = c_oc4;
    update public.purchase_order_items set received_qty = 1 where id = c_poi;
    r := pg_temp.pr('104');
    v_res := pg_temp.ok(v_res, 'F8 OC recebida: o compressor é A desde ter 20/10, fonte oc (a conta bruta não o lista mais)',
      pg_temp.item(r, c_poi) ->> 'nivel' = 'A' and pg_temp.item(r, c_poi) ->> 'data' = '2026-10-20'
      and pg_temp.item(r, c_poi) ->> 'fonte' = 'oc'
      and jsonb_array_length(public.os_necessidade_bruta(pg_temp.os('104')) -> 'items') = 0
      and r #>> '{material,estado}' = 'nao_conferido',
      coalesce(pg_temp.item(r, c_poi)::text, '(sem o item)'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F8 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F9: previsão vencida — o fornecedor disse 20/10 e não chegou.
  begin
    insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                    situacao, fonte, previsao_ate, previsao_fonte, comprado_em)
    values (pg_temp.os('112'), md5('peca:112:4')::uuid, 'peca', 'Painel Touch de Monitoramento e Controle de Energia – HBR 7"', 1,
            'comprado', 'fornecedor', '2026-10-20', 'fornecedor', '2026-10-14');
    r := pg_temp.pr('112');
    v_res := pg_temp.ok(v_res, 'F9 previsão do fornecedor vencida (B, ter 20/10): material atrasado, "venceu em 20/10: chegou?"',
      pg_temp.item(r, md5('peca:112:4')::uuid) ->> 'nivel' = 'B' and (pg_temp.item(r, md5('peca:112:4')::uuid) ->> 'atrasado')::boolean
      and r #>> '{material,estado}' = 'atrasado'
      and pg_temp.restr(r, 'atrasado') ->> 'texto' = 'a previsão de "Painel Touch de…" venceu em 20/10: chegou?'
      and (r -> 'restricoes' -> 0 ->> 'tipo') = 'atrasado'
      and r ->> 'estado_texto' = 'falta você dizer se "Painel Touch de…" chegou (a previsão venceu)',
      pg_temp.tipos(r) || ' | ' || (r ->> 'estado_texto'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F9 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F10: dispensado sai; "pode começar sem" (crítico = false) fica na lista e não trava.
  begin
    insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                    situacao, fonte, critico)
    select pg_temp.os('69'), sop.id, 'peca', left(pr.name, 200), sop.quantity,
           case when sop.id in (md5('peca:69:1')::uuid, md5('peca:69:2')::uuid) then 'dispensado' else 'falta' end, 'dono',
           false
      from public.service_order_parts sop join public.products pr on pr.id = sop.product_id
     where sop.service_order_id = pg_temp.os('69');
    r := pg_temp.pr('69');
    v_res := pg_temp.ok(v_res, 'F10 2 dispensados saem; 2 "pode começar sem" ficam (não críticos) e não travam: completo, pronto',
      jsonb_array_length(r #> '{material,itens}') = 2
      and (select bool_and(not (e ->> 'critico')::boolean) from jsonb_array_elements(r #> '{material,itens}') e)
      and r #>> '{material,estado}' = 'completo' and r ->> 'estado' = 'pronta' and pg_temp.restr(r, 'sem_previsao') is null,
      format('%s itens | %s | %s', jsonb_array_length(r #> '{material,itens}'), r #>> '{material,estado}', pg_temp.tipos(r)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F10 (o cenário quebrou)', false, sqlerrm);
  end;

  -- F11: a leitura não depende da sincronização — a carteira inteira igual antes e depois (tirando o id da linha).
  begin
    select md5(string_agg(pg_temp.sem_ids(p)::text, '|')) into v_a from public.os_prontidao_carteira(c_hoje) p;
    x := public.os_material_sincronizar_carteira(c_hoje);
    select md5(string_agg(pg_temp.sem_ids(p)::text, '|')) into v_b from public.os_prontidao_carteira(c_hoje) p;
    v_res := pg_temp.ok(v_res, 'F11 sincronizar o material (as linhas que o sistema copia) não muda nenhuma prontidão',
      v_a = v_b and (x ->> 'criadas')::int > 0 and jsonb_array_length(x -> 'erros') = 0, x::text);
    v_res := pg_temp.ok(v_res, 'F12 a sincronização percorre a mesma carteira (os_carteira): 11 OS',
      (x ->> 'oss')::int = 11, x::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'F11 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G1: congelada.
  begin
    insert into public.os_planejamento (service_order_id, congelada_ate, revisar_em) values (pg_temp.os('74'), '2026-10-30', '2026-10-30');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'G1 congelada até sex 30/10 (rever no mesmo dia): o 1º estado que vale, sem repetir a data',
      r ->> 'estado' = 'congelada' and r ->> 'estado_texto' = 'em espera até sex 30/10', r ->> 'estado_texto');
    update public.os_planejamento set revisar_em = '2026-10-28' where service_order_id = pg_temp.os('74');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'G1b rever antes do fim da espera: "(rever qua 28/10)"',
      r ->> 'estado_texto' = 'em espera até sex 30/10 (rever qua 28/10)', r ->> 'estado_texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G1 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G2: marcada (janela futura) — as restrições continuam listadas.
  begin
    update public.service_orders set scheduled_start_at = '2026-10-27 08:00-03', scheduled_end_at = '2026-10-28 17:00-03'
     where id = pg_temp.os('69');
    r := pg_temp.pr('69');
    v_res := pg_temp.ok(v_res, 'G2 marcada de ter 27/10 a qua 28/10, e os 4 itens a comprar continuam na lista',
      r ->> 'estado' = 'marcada' and r ->> 'estado_texto' = 'marcado de ter 27/10 a qua 28/10'
      and pg_temp.restr(r, 'sem_previsao') is not null and r -> 'marcada' = '{"de": "2026-10-27", "ate": "2026-10-28"}'::jsonb,
      r ->> 'estado_texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G2 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G3: em andamento — parada sem diária nos últimos 3 dias úteis; em execução com diária ligada.
  begin
    update public.service_orders set status = 'in_progress' where id = pg_temp.os('74');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'G3a em andamento e sem diária lançada: parada, "parou?" (dono, trava)',
      r ->> 'estado' = 'parada' and pg_temp.restr(r, 'parada') ->> 'texto' = 'em andamento e sem diária lançada: parou?'
      and r -> 'restricoes' -> 0 ->> 'tipo' = 'parada', pg_temp.tipos(r));
    update public.work_shifts set service_order_id = pg_temp.os('74')
     where work_profile_id = 'cc000000-0000-4000-8000-000000000002' and data = '2026-10-16';
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'G3b última diária sex 16/10 (antes dos 3 úteis): "sem diária desde 16/10: parou?"',
      r ->> 'estado' = 'parada' and pg_temp.restr(r, 'parada') ->> 'texto' = 'em andamento sem diária desde 16/10: parou?',
      pg_temp.restr(r, 'parada') ->> 'texto');
    insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria, origem, status, service_order_id,
                                    registrado_por, aprovado_por, aprovado_em)
    values ('cc000000-0000-4000-8000-000000000002', '2026-10-22', 'diaria', 1, 200, 'painel', 'aprovado', pg_temp.os('74'),
            'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', '2026-10-22 20:00-03');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'G3c diária de qui 22/10 ligada: em execução, sem "parou?"',
      r ->> 'estado' = 'em_execucao' and pg_temp.restr(r, 'parada') is null and r ->> 'ultima_diaria' = '2026-10-22',
      r ->> 'estado');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G3 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G4: cobrança de sinal pendente.
  begin
    insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status,
                                    paid_amount, balance_amount, is_deposit)
    select so.client_id, so.id, 'Sinal OS-00096', '2026-10-16', '2026-10-20', 125, 'pending', 0, 125, true
      from public.service_orders so where so.id = pg_temp.os('96');
    r := pg_temp.pr('96');
    v_res := pg_temp.ok(v_res, 'G4 sinal cobrado e não pago: sem sinal, "esperando o sinal de R$ 125,00" (cliente)',
      r ->> 'estado' = 'sem_sinal' and r ->> 'estado_texto' = 'esperando o sinal de R$ 125,00'
      and pg_temp.restr(r, 'sinal') ->> 'quem' = 'cliente', r ->> 'estado_texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G4 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G5: o bem fora — até ter 03/11 (não trava, empurra o início) e até o fim do ano (além do horizonte).
  begin
    insert into public.os_planejamento (service_order_id, bem_indisponivel) values (pg_temp.os('100'), '{[2026-10-24,2026-11-03)}');
    r := pg_temp.pr('100');
    v_res := pg_temp.ok(v_res, 'G5a "o motorhome só fica livre ter 03/11" (cliente, não trava); o início sem material vai para 03/11',
      pg_temp.restr(r, 'bem') ->> 'texto' = 'o motorhome só fica livre ter 03/11' and pg_temp.restr(r, 'bem') ->> 'quem' = 'cliente'
      and not (pg_temp.restr(r, 'bem') ->> 'bloqueia')::boolean and r ->> 'est_sem_material' = '2026-11-03'
      and r ->> 'estado' = 'aguardando_material',
      pg_temp.tipos(r));
    update public.os_planejamento set bem_indisponivel = '{[2026-10-24,2026-12-31)}' where service_order_id = pg_temp.os('100');
    r := pg_temp.pr('100');
    v_res := pg_temp.ok(v_res, 'G5b fora até qui 31/12 (além das 6 semanas): aguardando o cliente',
      r ->> 'estado' = 'aguardando_cliente' and r ->> 'estado_texto' = 'o motorhome só fica livre qui 31/12', r ->> 'estado_texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G5 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G6: escopo em aberto → esperando você.
  begin
    insert into public.os_planejamento (service_order_id, escopo_em_aberto) values (pg_temp.os('74'), 'tudo de uma vez ou por partes?');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'G6 escopo em aberto: esperando você, "falta você decidir: …"',
      r ->> 'estado' = 'esperando_voce' and r ->> 'estado_texto' = 'falta você decidir: tudo de uma vez ou por partes?'
      and pg_temp.restr(r, 'escopo') ->> 'quem' = 'dono', r ->> 'estado_texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G7: fora da carteira.
  r := pg_temp.pr('50');
  v_res := pg_temp.ok(v_res, 'G7a OS-00050 concluída: estado concluida, sem restrição',
    r ->> 'estado' = 'concluida' and r ->> 'estado_texto' = 'concluído' and jsonb_array_length(r -> 'restricoes') = 0
    and not (r ->> 'na_carteira')::boolean, pg_temp.tipos(r));
  r := pg_temp.pr('119');
  v_res := pg_temp.ok(v_res, 'G7b ORÇ-00119 (enviado): fora da carteira, mas com material (5 itens) e duração (1,5 a 2,5)',
    r ->> 'estado' = 'fora_da_carteira' and r ->> 'estado_texto' = 'enviado, esperando a aprovação'
    and jsonb_array_length(r #> '{material,itens}') = 5 and r #>> '{duracao,dias_otimista}' = '1.5'
    and r #>> '{duracao,dias_realista}' = '2.5', r ->> 'estado_texto');
  v_res := pg_temp.ok(v_res, 'G7c OS inexistente: "Não encontrei esse serviço."',
    public.os_prontidao('00000000-0000-4000-8000-000000000000', c_hoje) = '{"ok": false, "texto": "Não encontrei esse serviço."}'::jsonb);

  -- G8: o prazo do cliente.
  begin
    insert into public.os_planejamento (service_order_id, precisa_ate) values (pg_temp.os('112'), '2026-11-06');
    r := pg_temp.pr('112');
    v_res := pg_temp.ok(v_res, 'G8 "o cliente precisa até sex 06/11": prazo do dono; razão crítica 9 du ÷ 2 dias = 4,5',
      r ->> 'prazo_efetivo' = '2026-11-06' and r ->> 'prazo_fonte' = 'dono' and (r ->> 'razao_critica')::numeric = 4.5,
      format('%s %s %s', r ->> 'prazo_efetivo', r ->> 'prazo_fonte', r ->> 'razao_critica'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G8 (o cenário quebrou)', false, sqlerrm);
  end;

  -- G9: presença — o que o dono disse vence a regra; marina nova e comissionamento pela regra.
  begin
    insert into public.os_planejamento (service_order_id, dono_presenca) values (pg_temp.os('96'), 'nunca');
    insert into public.marinas (id, name, city, state) values ('ee000000-0000-4000-8000-0000000000aa', 'Marina Nova', 'Penha', 'SC');
    update public.service_orders set marina_id = 'ee000000-0000-4000-8000-0000000000aa' where id = pg_temp.os('69');
    update public.service_orders set service_type = 'commissioning' where id = pg_temp.os('112');
    v_res := pg_temp.ok(v_res, 'G9 o dono disse "nunca" (96); marina sem OS concluída = sempre (69); comissionamento = sempre (112)',
      public.os_presenca_do_dono(pg_temp.os('96')) = '{"presenca": "nunca", "motivo": "você disse", "fonte": "dono"}'::jsonb
      and public.os_presenca_do_dono(pg_temp.os('69')) = '{"presenca": "sempre", "motivo": "marina nova", "fonte": "regra"}'::jsonb
      and public.os_presenca_do_dono(pg_temp.os('112')) = '{"presenca": "sempre", "motivo": "comissionamento", "fonte": "regra"}'::jsonb,
      public.os_presenca_do_dono(pg_temp.os('69'))::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G9 (o cenário quebrou)', false, sqlerrm);
  end;

  -- H: duração dita pelo dono — "Lenine dois dias com o Roberto, o João ajuda à tarde" / "eu e o Roberto".
  begin
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte) values (pg_temp.os('74'), 2, 'dono');
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    values (pg_temp.os('74'), c_rob, 'dia'), (pg_temp.os('74'), c_joao, 'tarde');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'H1 2 dias, Roberto (dia) + João (tarde): 6 meios-dias = 3 diárias; sem a pergunta da duração',
      r #>> '{duracao,fonte}' = 'dono' and r #>> '{duracao,dias}' = '2' and r #>> '{duracao,meios_dias}' = '6'
      and r #>> '{duracao,diarias}' = '3' and r #>> '{duracao,texto}' = '2 dias: Roberto (dia todo) e João (à tarde) (você disse)'
      and r #>> '{duracao,dp_otimista}' = '3' and r #>> '{duracao,dp_realista}' = '3'
      and pg_temp.restr(r, 'duracao') is null,
      ((r -> 'duracao') - 'sugestao')::text);
    delete from public.os_planejamento_equipe where service_order_id = pg_temp.os('74');
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    values (pg_temp.os('74'), c_dono, 'dia'), (pg_temp.os('74'), c_rob, 'dia');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'H2 "eu e o Roberto": 4 diárias, mas só 2 da equipe (você sem padrão não entra na conta)',
      r #>> '{duracao,diarias}' = '4' and r #>> '{duracao,diarias_equipe}' = '2' and r #>> '{duracao,dp_realista}' = '2'
      and r #>> '{duracao,texto}' = '2 dias: você (dia todo) e Roberto (dia todo) (você disse)',
      ((r -> 'duracao') - 'sugestao')::text);
    delete from public.os_planejamento_equipe where service_order_id = pg_temp.os('74');
    r := pg_temp.pr('74');
    v_res := pg_temp.ok(v_res, 'H3 "são dois dias" sem dizer quem: as diárias usam as pessoas da sugestão (2 × 2 = 4)',
      r #>> '{duracao,diarias}' = '4' and not (r #>> '{duracao,equipe_dita}')::boolean,
      ((r -> 'duracao') - 'sugestao')::text);
    -- Quem vai só de manhã ou só à tarde vai a UM turno de cada dia que o serviço ocupa (meio dia à tarde = 1 meio-dia).
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (pg_temp.os('74'), c_joao, 'tarde');
    update public.os_planejamento set dias = 0.5 where service_order_id = pg_temp.os('74');
    r := pg_temp.pr('74');
    v_txt := format('%s %s %s', r #>> '{duracao,meios_dias}', r #>> '{duracao,diarias}', r #>> '{duracao,dp_realista}');
    update public.os_planejamento set dias = 1.5 where service_order_id = pg_temp.os('74');
    r := pg_temp.pr('74');
    v_txt := v_txt || format(' | %s %s', r #>> '{duracao,meios_dias}', r #>> '{duracao,diarias}');
    update public.os_planejamento set dias = 2 where service_order_id = pg_temp.os('74');
    r := pg_temp.pr('74');
    v_txt := v_txt || format(' | %s %s', r #>> '{duracao,meios_dias}', r #>> '{duracao,diarias}');
    v_res := pg_temp.ok(v_res, 'H4 só à tarde: meio dia = 1 meio-dia (0,5 diária); 1,5 dia = 2 meios-dias; 2 dias = 2 meios-dias',
      v_txt = '1 0.5 0.5 | 2 1 | 2 1', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'H (o cenário quebrou)', false, sqlerrm);
  end;

  -- I15: número que existe como ORÇ e como OS = ambíguo (o dono escolhe).
  begin
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status)
    select gen_random_uuid(), 'ORÇ-00112', so.client_id, so.vessel_id, 'draft', 'sent'
      from public.service_orders so where so.id = pg_temp.os('112');
    r := public.agenda_resolver_os('112', c_hoje);
    v_res := pg_temp.ok(v_res, 'I15 "112" com ORÇ-00112 e OS-00112: ambíguo, "Qual deles: ORÇ-00112 (…) ou OS-00112 (…)?"',
      r ->> 'status' = 'ambiguo' and r ->> 'texto' like 'Qual deles: ORÇ-00112 (%) ou OS-00112 (%)?'
      and public.agenda_resolver_os('OS-00112', c_hoje) ->> 'status' = 'ok', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'I15 (o cenário quebrou)', false, sqlerrm);
  end;

  -- I16: dois sócios sem login ligado: "eu" pergunta.
  begin
    update public.payees set app_user_id = null where id = c_dono;
    insert into public.payees (name, kind, active) values ('Ana Sócia', 'socio', true);
    r := public.agenda_resolver_pessoa('eu', null, c_hoje);
    v_res := pg_temp.ok(v_res, 'I16 dois sócios e nenhum ligado ao login: "eu" vira a pergunta "Qual sócio: …?"',
      r ->> 'status' = 'ambiguo' and r ->> 'texto' = 'Qual sócio: Ana e Gustavo?', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'I16 (o cenário quebrou)', false, sqlerrm);
  end;

  -- J7: o padrão do dono entra na conta; exceções e recesso na grade.
  begin
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, trecho)
    values (c_dono, '{1,2,3,4,5}', null, 'disponivel', 'dono', 'eu fico em campo de segunda a sexta'),
           (c_dono, '{5}', 'tarde', 'indisponivel', 'dono', 'sexta à tarde, escritório');
    r := public.agenda_capacidade_semanal(c_hoje);
    v_res := pg_temp.ok(v_res, 'J7a com o seu padrão (seg a sex, sexta à tarde não): 6,77 + 4,5 = 11,27 → 9,01 comprometíveis',
      (r ->> 'conta_dono')::boolean and (r ->> 'diarias_semana')::numeric = 11.27 and (r ->> 'comprometivel')::numeric = 9.01
      and r #>> '{pessoas,0,nome}' = 'Gustavo' and r #>> '{pessoas,0,diarias_semana}' = '4.50',
      (r - 'pessoas')::text);
    select string_agg(format('%s %s', g.turno, g.situacao), ', ' order by g.turno) into v_txt
      from public.agenda_capacidade('2026-10-30', '2026-10-30', c_hoje) g where g.eh_dono;
    v_res := pg_temp.ok(v_res, 'J7b sexta 30/10: você de manhã livre, à tarde indisponível', v_txt = 'manha livre, tarde indisponivel', v_txt);
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota)
    values (c_rob, '[2026-10-26,2026-10-27)', null, 'indisponivel', 'diarista', 'consulta médica'),
           (c_rob, '[2026-10-24,2026-10-25)', null, 'confirmada', 'dono', 'sábado combinado'),
           (null, '[2026-12-24,2027-01-01)', null, 'indisponivel', 'dono', 'recesso de fim de ano');
    select string_agg(format('%s %s %s %s', to_char(g.dia, 'DD/MM'), g.situacao, g.meios_esperados, g.motivo), ' | ' order by g.dia)
      into v_txt
      from public.agenda_capacidade('2026-10-24', '2026-10-26', c_hoje) g
     where g.payee_id = c_rob and g.turno = 'manha';
    v_res := pg_temp.ok(v_res, 'J7c Roberto: sábado combinado = livre (1); domingo fora; seg 26/10 indisponível (a exceção vence o padrão)',
      v_txt = '24/10 livre 1 sábado combinado | 25/10 fim_de_semana 0 domingo | 26/10 indisponivel 0 consulta médica', v_txt);
    v_res := pg_temp.ok(v_res, 'J7d recesso (sem pessoa): todos indisponíveis em seg 28/12',
      (select bool_and(g.situacao = 'indisponivel' and g.motivo = 'recesso de fim de ano')
         from public.agenda_capacidade('2026-12-28', '2026-12-28', c_hoje) g));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'J7 (o cenário quebrou)', false, sqlerrm);
  end;

  perform pg_temp.gravar(v_res);
end
$cenarios$;

-- ── K. Determinismo e nada gravado (com ou sem a fixture) ───────────────────────────────────────────────
do $k$
declare
  c_hoje constant date := date '2026-10-23';
  v_antes text;
  v_depois text;
  v_res jsonb := '[]'::jsonb;
  f text;
  a text;
  b text;
begin
  select format('%s/%s/%s/%s/%s', (select count(*) from public.os_material), (select count(*) from public.os_planejamento),
                (select count(*) from public.os_planejamento_equipe), (select count(*) from public.agenda_disponibilidade),
                (select count(*) from public.agenda_rascunho))
    into v_antes;
  foreach f in array array[
    'select string_agg(k::text, ''|'') from public.os_carteira(%L) k',
    'select string_agg(p::text, ''|'') from public.os_prontidao_carteira(%L) p',
    'select string_agg(public.os_duracao_sugerida(so.id)::text || public.os_presenca_do_dono(so.id)::text, ''|'' order by so.id) from public.service_orders so where %L is not null',
    'select string_agg(g::text, ''|'') from public.agenda_capacidade(%1$L::date - 7, %1$L::date + 21, %1$L) g',
    'select public.agenda_capacidade_semanal(%L)::text',
    'select string_agg(public.agenda_resolver_os(x, %L)::text, ''|'') from unnest(array[''Lenine'', ''Rodrigo'', ''112'', ''OS-00999'', ''César'']) x',
    'select string_agg(public.agenda_resolver_pessoa(x, null, %L)::text, ''|'') from unnest(array[''eu'', ''Roberto'', ''Pedro'']) x']
  loop
    execute format(f, c_hoje) into a;
    execute format(f, c_hoje) into b;
    v_res := pg_temp.ok(v_res, 'K1 2× = o mesmo md5: ' || split_part(split_part(f, 'public.', 2), '(', 1),
      md5(coalesce(a, '')) = md5(coalesce(b, '')), md5(coalesce(a, '')));
  end loop;
  select format('%s/%s/%s/%s/%s', (select count(*) from public.os_material), (select count(*) from public.os_planejamento),
                (select count(*) from public.os_planejamento_equipe), (select count(*) from public.agenda_disponibilidade),
                (select count(*) from public.agenda_rascunho))
    into v_depois;
  v_res := pg_temp.ok(v_res, 'K2 nenhuma leitura grava (os_material, os_planejamento, equipe, disponibilidade, rascunho)',
    v_antes = v_depois, v_antes || ' → ' || v_depois);
  perform pg_temp.gravar(v_res);
end
$k$;

-- ── P. Regras gerais sobre o dado que houver (produção ou fixture) ──────────────────────────────────────
insert into _resultado
select 'P1 uma prontidão por item da carteira, todas ok, estado conhecido',
       count(*) = (select count(*) from public.os_carteira(date '2026-10-23'))
       and coalesce(bool_and((p ->> 'ok')::boolean and p ->> 'estado' in ('congelada', 'concluida', 'fora_da_carteira',
             'em_execucao', 'parada', 'marcada', 'sem_sinal', 'aguardando_cliente', 'esperando_voce',
             'aguardando_material', 'pronta')), true),
       count(*)::text
  from public.os_prontidao_carteira(date '2026-10-23') p;

insert into _resultado
select 'P2 duração: sem base, ou otimista <= realista, em meios-dias, pessoas 1 ou equipe_sugerida',
       coalesce(bool_and((d ->> 'sem_base')::boolean
         or ((d ->> 'dias_otimista')::numeric <= (d ->> 'dias_realista')::numeric
             and (d ->> 'dias_otimista')::numeric * 2 = trunc((d ->> 'dias_otimista')::numeric * 2)
             and (d ->> 'dias_realista')::numeric * 2 = trunc((d ->> 'dias_realista')::numeric * 2)
             and (d ->> 'pessoas')::int in (1, (select equipe_sugerida from public.agenda_config)))), true),
       null
  from public.os_carteira(date '2026-10-23') k, lateral public.os_duracao_sugerida(k.service_order_id) d;

insert into _resultado
select 'P3 o comprometível é diárias × carga_max (um número só)',
       abs((c ->> 'comprometivel')::numeric - (c ->> 'diarias_semana')::numeric * (select carga_max from public.agenda_config)) < 0.01,
       (c - 'pessoas')::text
  from public.agenda_capacidade_semanal(date '2026-10-23') c;

insert into _resultado
select 'P4 restrições: todo tipo e "quem" conhecidos; a que trava vem antes da que só informa',
       coalesce(bool_and(e ->> 'tipo' in ('parada', 'atrasado', 'sem_previsao', 'comprado_sem_previsao', 'compre_ate',
                                          'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal',
                                          'cliente', 'duracao', 'bem', 'nao_antes')
                         and e ->> 'quem' in ('dono', 'cliente', 'fornecedor', 'terceiro', 'sistema')), true)
       and not exists (
         select 1 from public.os_prontidao_carteira(date '2026-10-23') p2,
                lateral jsonb_array_elements(p2 -> 'restricoes') with ordinality a(e1, o1),
                lateral jsonb_array_elements(p2 -> 'restricoes') with ordinality b(e2, o2)
          where o1 < o2 and not (e1 ->> 'bloqueia')::boolean and (e2 ->> 'bloqueia')::boolean),
       null
  from public.os_prontidao_carteira(date '2026-10-23') p, lateral jsonb_array_elements(p -> 'restricoes') e;

-- ── L. Portas ───────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'L1 anon não executa nenhuma função nova',
       not bool_or(has_function_privilege('anon', f, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute'))
  from unnest(array['public._agenda_dono(uuid)', 'public._agenda_linha_curta(text)', 'public._agenda_itens(integer)',
                    'public._agenda_rotulo_os(text, text, boolean, text, boolean)', 'public.os_carteira(date)',
                    'public.agenda_resolver_os(text, date, boolean)', 'public.agenda_resolver_pessoa(text, uuid, date)',
                    'public._agenda_classe_do_fornecedor(uuid)', 'public._agenda_prazo_da_classe(text)',
                    'public.os_duracao_sugerida(uuid)', 'public.os_presenca_do_dono(uuid)', 'public.os_prontidao(uuid, date)',
                    'public.os_prontidao_carteira(date)', 'public.agenda_capacidade(date, date, date)',
                    'public.agenda_capacidade_semanal(date)', 'public.os_material_sincronizar_carteira(date)']) f;

insert into _resultado
select 'L2 authenticated executa as leituras; a sincronização continua só service_role',
       bool_and(has_function_privilege('authenticated', f, 'execute') = (f <> 'public.os_material_sincronizar_carteira(date)'))
       and bool_and(has_function_privilege('service_role', f, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('authenticated', f, 'execute')
                                         <> (f <> 'public.os_material_sincronizar_carteira(date)'))
  from unnest(array['public._agenda_dono(uuid)', 'public._agenda_linha_curta(text)', 'public._agenda_itens(integer)',
                    'public._agenda_rotulo_os(text, text, boolean, text, boolean)', 'public.os_carteira(date)',
                    'public.agenda_resolver_os(text, date, boolean)', 'public.agenda_resolver_pessoa(text, uuid, date)',
                    'public._agenda_classe_do_fornecedor(uuid)', 'public._agenda_prazo_da_classe(text)',
                    'public.os_duracao_sugerida(uuid)', 'public.os_presenca_do_dono(uuid)', 'public.os_prontidao(uuid, date)',
                    'public.os_prontidao_carteira(date)', 'public.agenda_capacidade(date, date, date)',
                    'public.agenda_capacidade_semanal(date)', 'public.os_material_sincronizar_carteira(date)']) f;

insert into _resultado
select 'L3 leituras: nenhuma security definer, todas STABLE ou IMMUTABLE, search_path fixo',
       bool_and(not p.prosecdef) and bool_and(p.provolatile in ('s', 'i'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%') and count(*) = 15,
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('_agenda_dono', '_agenda_linha_curta', '_agenda_itens', '_agenda_rotulo_os', 'os_carteira',
                     'agenda_resolver_os', 'agenda_resolver_pessoa', '_agenda_classe_do_fornecedor', '_agenda_prazo_da_classe',
                     'os_duracao_sugerida', 'os_presenca_do_dono', 'os_prontidao', 'os_prontidao_carteira',
                     'agenda_capacidade', 'agenda_capacidade_semanal');

-- L4: quem não lê agenda_config (o técnico, pela RLS) recebe ERRO — nunca uma prontidão "livre" ou vazia.
do $l4$
declare
  v_msg text;
  v_os  uuid := (select k.service_order_id from public.os_carteira(date '2026-10-23') k limit 1);
begin
  if v_os is null then
    insert into _resultado values ('L4 o técnico recebe erro, nunca "livre"', true, 'PULADO: carteira vazia');
    return;
  end if;
  begin
    perform set_config('request.jwt.claim.sub', 'aa000000-0000-4000-8000-0000000000ff', true);
    perform set_config('request.jwt.claims', json_build_object('sub', 'aa000000-0000-4000-8000-0000000000ff',
                                                               'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.os_prontidao(v_os, date '2026-10-23');
    reset role;
    v_msg := null;
  exception when others then
    v_msg := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('L4 quem não lê agenda_config (técnico) recebe erro, nunca uma prontidão vazia',
    v_msg like 'A agenda está sem os parâmetros%', coalesce(v_msg, 'não deu erro'));
end
$l4$;

-- L5: o admin, pelo painel (authenticated + o login dele), lê a carteira inteira.
do $l5$
declare
  v_n int;
  v_esperado int := (select count(*) from public.os_carteira(date '2026-10-23'));
  v_admin uuid := (select u.id from public.app_users u where u.role = 'admin' and u.active order by u.created_at, u.id limit 1);
  v_msg text;
begin
  if v_admin is null then
    insert into _resultado values ('L5 o admin lê a carteira pelo painel', true, 'PULADO: sem admin ativo');
    return;
  end if;
  begin
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_n from public.os_prontidao_carteira(date '2026-10-23');
    reset role;
  exception when others then
    v_msg := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('L5 o admin (authenticated, com login) lê a prontidão da carteira inteira',
    v_msg is null and v_n = v_esperado, coalesce(v_msg, format('%s de %s', v_n, v_esperado)));
end
$l5$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
