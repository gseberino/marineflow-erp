-- Prova das leituras com texto pronto da Agenda de Produção, Fase 1 (pacote P4): migration 20261024160500.
-- bancada: depende de 20261024160500
--
-- Com a fixture de 23/10 (scripts/bancada-agenda/fixture-2310.sql), os textos da spec §6 BYTE A BYTE — o texto é
-- contrato: qualquer mudança de redação quebra aqui de propósito. As diferenças conscientes da §6 estão no cabeçalho
-- da migration (nome do item pela prontidão, sem artigo de gênero, listas com "e", "Quantos dias e com quem?").
--   A  os textos: semana (19–24/10), o que eu tenho que fazer, atrasados, a rodada, Roberto amanhã (sáb 24/10), a
--      simulação "2 dias, eu e o Roberto", o "se o César aprovar", o fechamento de qui 22/10 e o de sex 23/10, o dia
--      (hoje), o material (sem OS e do Nelson), a visão da OS do Nelson; e o despacho agenda_ver devolvendo os mesmos
--   B  as regras dos textos: 5 blocos na ordem; um número de capacidade só; sem palavra de sistema; a semana do
--      fechamento só no dia do plano; desligado = nada; referência que não existe = "Não encontrei" (sem OS nem data)
--   C  cenários (desfeitos na hora): o que o dono disse (pronto a partir de, "você disse em", "você ainda não me disse
--      que chegou", previsão vencida); OS marcada e compromisso; "Outras pendências" = a regra de my_agenda nas bordas
--      do dia; o dono com padrão ("contando você", sem a pergunta "Você:"); em espera e em andamento parado; sem
--      diárias; carteira vazia; o corte em texto_max = 400 (por item, nunca no meio da linha)
-- Sempre (com ou sem a fixture):
--   K  determinismo: cada leitura 2× = o mesmo md5; nada é gravado
--   L  portas: anon sem nada; authenticated executa; nenhuma security definer; STABLE/IMMUTABLE; search_path fixo;
--      foco inválido lança 22023; o técnico (sem ler agenda_config) recebe erro, nunca "livre"; o admin pelo painel lê
--   P  regras gerais sobre o dado que houver: todo texto ≤ texto_max, os 5 blocos na ordem
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261024160500
--   Em produção, só DEPOIS de aplicar 160000..160500, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase1_leituras.sql
--   Sem a fixture (produção), A–C saem PULADO e só K, L e P rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- Onde dois textos se separam (para o detalhe de quem reprova).
create function pg_temp.dif(a text, b text) returns text language plpgsql immutable as $f$
declare i int := 1;
begin
  if a is not distinct from b then return null; end if;
  if a is null or b is null then return format('obtido: %s', coalesce(a, 'NULL')); end if;
  while i <= least(length(a), length(b)) and substr(a, i, 1) = substr(b, i, 1) loop i := i + 1; end loop;
  return format('difere no caractere %s: obtido «%s» × esperado «%s»', i,
                substr(a, greatest(i - 30, 1), 80), substr(b, greatest(i - 30, 1), 80));
end
$f$;
-- O texto esperado sem \r (o arquivo pode vir com CRLF).
create function pg_temp.t(p text) returns text language sql immutable as $f$ select replace(p, E'\r', '') $f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_obtido text, p_esperado text) returns jsonb
language sql immutable as $f$
  select pg_temp.ok(p_res, p_nome, p_obtido = pg_temp.t(p_esperado), pg_temp.dif(p_obtido, pg_temp.t(p_esperado)))
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
-- Todos os textos da agenda num dia (para as regras que valem em todos).
create function pg_temp.todos(p_hoje date, p_autor uuid) returns table (nome text, texto text) language sql stable as $f$
  select 'semana', public.agenda_semana(null, null, p_hoje) ->> 'texto'
  union all select 'proxima', public.agenda_semana(p_hoje - (extract(isodow from p_hoje)::int - 1) + 7,
                                                    p_hoje - (extract(isodow from p_hoje)::int - 1) + 12, p_hoje) ->> 'texto'
  union all select 'o_que_fazer', public.agenda_o_que_fazer(null, p_hoje) ->> 'texto'
  union all select 'atrasos', public.agenda_atrasos(p_hoje) ->> 'texto'
  union all select 'aprontar', public.agenda_aprontar(p_hoje) ->> 'texto'
  union all select 'material', public.agenda_ver_material(null, p_hoje) ->> 'texto'
  union all select 'material_os:' || k.numero, public.agenda_ver_material(k.service_order_id, p_hoje) ->> 'texto'
    from public.os_carteira(p_hoje) k
  union all select 'os:' || k.numero, public.agenda_ver(p_autor, null, null, null, k.numero, null, false, p_hoje) ->> 'texto'
    from public.os_carteira(p_hoje) k
  union all select 'ctp:' || k.numero, public.agenda_ctp(k.service_order_id, p_hoje) ->> 'texto'
    from public.os_carteira(p_hoje) k
  union all select 'dia:' || py.name, public.agenda_dia_da_pessoa(py.id, p_hoje + 1, p_hoje) ->> 'texto'
    from public.payees py where py.active
  union all select 'simular', public.agenda_simular(2, '[]'::jsonb, null, p_autor, p_hoje) ->> 'texto'
  union all select 'hoje', public.agenda_ver(p_autor, 'hoje', null, null, null, null, false, p_hoje) ->> 'texto'
  union all select 'livre', public.agenda_ver(p_autor, null, null, 'livre', null, null, false, p_hoje) ->> 'texto'
  union all select 'fechamento:' || coalesce(x, ''), x
    from jsonb_array_elements_text(coalesce(public.agenda_textos_do_fechamento(p_hoje, null) -> 'semana_que_vem', '[]'::jsonb)) x
$f$;

-- ── A. Os textos da spec §6, byte a byte ────────────────────────────────────────────────────────────────
do $a$
declare
  c_hoje  constant date := date '2026-10-23';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_rob   constant uuid := 'bb000000-0000-4000-8000-000000000002';
  v_fixture boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                   and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000104')
                   and exists (select 1 from public.app_users where id = 'aa000000-0000-4000-8000-000000000001');
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  f       jsonb;
  v_sem   text;
  v_oqf   text;
  v_atr   text;
  v_apr   text;
  v_rob   text;
  v_sim   text;
  v_ctp   text;
begin
  if not v_fixture then
    insert into _resultado values ('A–C com a fixture de 23/10', true, 'PULADO: sem a fixture (produção); rodam K, L e P');
    return;
  end if;

  v_sem := $e$Esta semana (seg 19/10 a sáb 24/10) não tem nada marcado, e nenhuma diária foi lançada depois de sáb 17/10: não sei o que a equipe fez de seg 19/10 até hoje.
Livre ela não está: há 7 serviços aprovados, uns 17 a 32 dias de equipe — de 3 a 6 semanas no ritmo de ~5,4 diárias de equipe por semana (o que vocês lançaram, com folga), sem contar você.
Prontos para começar: nenhum. Quase: Lenine e Rodrigo (OS-00096), se não tiverem peça a comprar.
Travados por material: Vanderlei (4 itens a comprar), Flávio (compressor chegou?), Nelson (4 itens sem compra registrada) e Giancarlo (tem peça embutida?).
Esperando você: Robson ORÇ-00083 (assinado em 23/08, nunca virou OS).
Parados no cliente: Kalmar ×2, Rodrigo (OS-00076) e MP ORÇ-00095 (sinal).
Livre de verdade: no melhor caso a partir de qua 18/11; no realista, só a partir de qua 09/12 — se as compras saírem e nada novo entrar.
Quer que eu pergunte o que falta para montar a semana que vem? Uma resposta por OS; dá para responder num áudio.$e$;
  r := public.agenda_semana(date '2026-10-19', date '2026-10-24', c_hoje);
  v_res := pg_temp.igual(v_res, 'A1 "como tá a semana?" (19–24/10): o texto da §6', r ->> 'texto', v_sem);
  v_res := pg_temp.ok(v_res, 'A1b semana: fila 16,5 a 31,5 diárias-pessoa, 7 serviços, livre qua 18/11 e qua 09/12 (n = 16 e 30 úteis)',
    r #>> '{dados,fila,dp_ot}' = '16.5' and r #>> '{dados,fila,dp_re}' = '31.5' and r #>> '{dados,fila,n}' = '7'
    and r #>> '{dados,livre,ot}' = '2026-11-18' and r #>> '{dados,livre,re}' = '2026-12-09'
    and r #>> '{dados,livre,n_ot}' = '16' and r #>> '{dados,livre,n_re}' = '30' and r #>> '{dados,capacidade}' = '5.41',
    ((r -> 'dados') - 'textos' - 'marcados')::text);
  v_res := pg_temp.ok(v_res, 'A1c semana: as partes reaproveitáveis em dados.textos (resumo, prontos, travados, esperando, parados, livre, oferta)',
    r #>> '{dados,textos,resumo}' = split_part(pg_temp.t(v_sem), E'\n', 2)
    and r #>> '{dados,textos,prontos}' = split_part(pg_temp.t(v_sem), E'\n', 3)
    and r #>> '{dados,textos,travados}' = split_part(pg_temp.t(v_sem), E'\n', 4)
    and r #>> '{dados,textos,esperando}' = split_part(pg_temp.t(v_sem), E'\n', 5)
    and r #>> '{dados,textos,parados}' = split_part(pg_temp.t(v_sem), E'\n', 6)
    and r #>> '{dados,textos,livre}' = split_part(pg_temp.t(v_sem), E'\n', 7)
    and r #>> '{dados,textos,oferta}' = split_part(pg_temp.t(v_sem), E'\n', 8),
    (r #> '{dados,textos}')::text);

  v_oqf := $e$Hoje (sex 23/10): nada marcado.
Travado esperando você: Vanderlei — 4 itens a comprar: de quem e quando?; Lenine — tem peça a comprar?; Flávio — "Compressor 12V de…" (pedido em 13/10) chegou?; Nelson — 4 itens sem compra registrada (comprando hoje, "Central de controle…" chega por volta de qui 29/10); Giancarlo — tem peça embutida em "Barramento e proteções…" ou "Realocação do banco…" (e mais 1)?; e mais 2.
Prontos sem data: nenhum. Nada marcado nos próximos 7 dias.
Em risco: 4 passaram do prazo padrão (Vanderlei, Lenine, Robson ORÇ-00083 e Flávio) — *atrasado* para ver.
Outras pendências: 1 tarefa atrasada e 3 de hoje; a receber hoje: nada; a pagar hoje: 1 conta, R$ 312,40.
Quer que eu pergunte o que falta, uma resposta por OS? Dá para responder num áudio.$e$;
  r := public.agenda_o_que_fazer(null, c_hoje);
  v_res := pg_temp.igual(v_res, 'A2 "o que eu tenho que fazer hoje?": os 5 blocos da §6', r ->> 'texto', v_oqf);
  v_res := pg_temp.ok(v_res, 'A2b bloco 2 na ordem de trabalho: sinal pago (69, 74, 104, 112, 100) → orçamento (ORÇ-00083) → resto (96)',
    (select string_agg(e ->> 'numero', ' ' order by o) from jsonb_array_elements(r #> '{dados,travados}') with ordinality t(e, o))
      = 'OS-00069 OS-00074 OS-00104 OS-00112 OS-00100 ORÇ-00083 OS-00096',
    (r #> '{dados,travados}')::text);

  v_atr := $e$Passaram do prazo (20 dias úteis desde a aprovação — o meu padrão, porque nenhum cliente disse quando precisa): Vanderlei (aprovada em 29/07), Lenine (12/08), Robson ORÇ-00083 (assinado em 23/08) e Flávio (23/09; a data marcada de 06/10 a 08/10 também passou).
Nenhuma previsão de material vencida.
Se algum cliente disse quando precisa, me fala que eu guardo.$e$;
  r := public.agenda_atrasos(c_hoje);
  v_res := pg_temp.igual(v_res, 'A3 "o que está atrasado?": o texto da §6 (o ORÇ-00095 esperando o sinal fica de fora)', r ->> 'texto', v_atr);
  v_res := pg_temp.ok(v_res, 'A3b atrasos: 4 atrasadas, nenhuma em risco, nenhum material vencido, a data marcada da OS-00104',
    (select string_agg(e ->> 'numero', ' ' order by o) from jsonb_array_elements(r #> '{dados,atrasadas}') with ordinality t(e, o))
      = 'OS-00069 OS-00074 ORÇ-00083 OS-00104'
    and jsonb_array_length(r #> '{dados,em_risco}') = 0 and jsonb_array_length(r #> '{dados,material_vencido}') = 0
    and r #> '{dados,data_marcada_vencida}' = '["OS-00104"]'::jsonb,
    (r -> 'dados')::text);

  v_apr := $e$Para montar a semana, uma resposta por OS (entre parênteses, o meu chute pelo valor):
• Vanderlei (OS-00069): o material (4 itens) — compra quando e onde? Quantos dias e com quem? (2 a 3,5 dias, 2 pessoas)
• Lenine (OS-00074): tem peça a comprar? Quantos dias e com quem? (1,5 a 3 dias, 2 pessoas)
• Flávio (OS-00104): "Compressor 12V de…" chegou? Tem peça embutida em "Conversão do sistema…" ou "Substituição da tampa…"? Quantos dias e com quem? (1 a 2 dias, 2 pessoas)
• Nelson (OS-00112): o que já está na mão e o que falta? Quando chega? Quantos dias e com quem? (1 a 2 dias, 2 pessoas)
• Giancarlo (OS-00100): tem peça embutida em "Barramento e proteções…" ou "Realocação do banco…" (e mais 1)? Quantos dias e com quem? (2 a 4 dias, 2 pessoas)
• Você: semana que vem fica em campo quais dias?
Pode ser um áudio só, citando o nome do cliente. (Robson ORÇ-00083 e Rodrigo OS-00096 ficam para depois.)$e$;
  r := public.agenda_aprontar(c_hoje);
  v_res := pg_temp.igual(v_res, 'A4 a rodada de aprontar: até 5 OS, o chute do banco entre parênteses, "Você:", o que fica para depois',
    r ->> 'texto', v_apr);

  v_rob := $e$Amanhã (sáb 24/10), Roberto não tem nada marcado — sábado só quando vocês combinam. Costuma vir de seg a sex (pelas diárias das últimas 8 semanas).$e$;
  r := public.agenda_dia_da_pessoa(c_rob, date '2026-10-24', c_hoje);
  v_res := pg_temp.igual(v_res, 'A5 "o que o Roberto faz amanhã?" (sáb 24/10)', r ->> 'texto', v_rob);
  r := public.agenda_dia_da_pessoa(c_rob, date '2026-10-26', c_hoje);
  v_res := pg_temp.igual(v_res, 'A5b "e o Roberto, segunda?" (3 de 5 segundas)', r ->> 'texto',
    $e$Seg 26/10, Roberto não tem nada marcado. Costuma vir de seg a sex (pelas diárias das últimas 8 semanas: 3 de 5 segundas).$e$);
  r := public.agenda_dia_da_pessoa('bb000000-0000-4000-8000-000000000003', date '2026-10-27', c_hoje);
  v_res := pg_temp.igual(v_res, 'A5c João na terça (1,5 de 3; de ter a sex)', r ->> 'texto',
    $e$Ter 27/10, João não tem nada marcado. Costuma vir de ter a sex (pelas diárias das últimas 8 semanas: 1,5 de 3 terças).$e$);
  r := public.agenda_dia_da_pessoa('bb000000-0000-4000-8000-000000000003', date '2026-10-26', c_hoje);
  v_res := pg_temp.igual(v_res, 'A5d João na segunda (tem padrão, mas não às segundas): "às segundas não costuma vir", sem o "não sei"',
    r ->> 'texto',
    $e$Seg 26/10, João não tem nada marcado — às segundas não costuma vir. Costuma vir de ter a sex (pelas diárias das últimas 8 semanas).$e$);

  v_sim := $e$Um serviço de 2 dias com você e Roberto (são 2 diárias de equipe; você não entra nessa conta): no fim da fila, começa entre qua 18/11 e qua 09/12. Passando na frente de tudo, dá para começar ter 27/10, e o resto atrasa uns 2 dias úteis. É projeção: não reserva nada.$e$;
  r := public.agenda_simular(2, '["eu", "Roberto"]'::jsonb, null, c_admin, c_hoje);
  v_res := pg_temp.igual(v_res, 'A6 "um serviço de 2 dias, eu e o Roberto": fila em faixa e furando a fila (ter 27/10; ~2 du)', r ->> 'texto', v_sim);
  v_res := pg_temp.ok(v_res, 'A6b simulação: 2 diárias da equipe, atraso de 2 úteis, começo furando = agenda_somar_du(hoje, congelamento + 1)',
    r #>> '{dados,diarias_equipe}' = '2' and r #>> '{dados,atraso_du}' = '2' and r #>> '{dados,inicio_furando}' = '2026-10-27',
    (r -> 'dados')::text);

  v_ctp := $e$ORÇ-00119 (César), se o cliente aprovar hoje: 1,5 a 2,5 dias com 2 pessoas (estimativa minha, pelo valor) e 5 itens a comprar (de quem?). Pela fila de hoje, começa entre qua 18/11 e qua 09/12 (sem contar você), e só depois que as peças chegarem.
Para o cliente: "a partir de 18/11, uns 3 dias de serviço; confirmo a data quando as peças chegarem". É projeção: não reserva nada.$e$;
  r := public.agenda_ctp(pg_temp.os('119'), c_hoje);
  v_res := pg_temp.igual(v_res, 'A7 "se o César aprovar hoje, quando dá?" (ORÇ-00119): frase ao cliente condicional (d09)', r ->> 'texto', v_ctp);

  f := public.agenda_textos_do_fechamento(date '2026-10-22', date '2026-10-23');
  v_res := pg_temp.igual(v_res, 'A8 fechamento de qui 22/10: a cauda do "Amanhã"', f ->> 'cauda_amanha',
    $e$nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)$e$);
  v_res := pg_temp.igual(v_res, 'A8b fechamento de qui 22/10 (dia do plano): as 3 linhas da semana que vem',
    (select string_agg(x, E'\n' order by o) from jsonb_array_elements_text(f -> 'semana_que_vem') with ordinality t(x, o)),
    $e$Semana que vem (projeção): nada marcado; 7 serviços na fila, uns 17 a 32 dias de equipe (~5,4 por semana, sem contar você).
Nenhum pronto para começar; o que falta de você está em *agenda*.
Livre de verdade: no melhor caso a partir de ter 17/11; no realista, só a partir de ter 08/12.$e$);
  v_res := pg_temp.ok(v_res, 'A8c fechamento: modo sombra (como nasce), dia do plano, cada linha ≤ 160 caracteres',
    f ->> 'modo' = 'sombra' and (f ->> 'dia_do_plano')::boolean
    and not exists (select 1 from jsonb_array_elements_text(f -> 'semana_que_vem') x where char_length(x) > 160),
    f::text);
  f := public.agenda_textos_do_fechamento(c_hoje, date '2026-10-24');
  v_res := pg_temp.ok(v_res, 'A9 fechamento de sex 23/10: a mesma cauda e NENHUMA linha da semana (não é o dia do plano)',
    f ->> 'cauda_amanha' = 'nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)'
    and not (f ->> 'dia_do_plano')::boolean and f -> 'semana_que_vem' = '[]'::jsonb, f::text);

  -- O despacho único devolve os mesmos textos (a ferramenta e os comandos não escrevem frase).
  v_res := pg_temp.igual(v_res, 'A10a agenda_ver(foco o_que_fazer) = o texto do "o que fazer"',
    public.agenda_ver(c_admin, null, null, 'o_que_fazer', null, null, false, c_hoje) ->> 'texto', v_oqf);
  v_res := pg_temp.igual(v_res, 'A10b agenda_ver(pessoa "eu", foco o_que_fazer) = o mesmo',
    public.agenda_ver(c_admin, null, 'eu', 'o_que_fazer', null, null, false, c_hoje) ->> 'texto', v_oqf);
  v_res := pg_temp.igual(v_res, 'A10c agenda_ver(período semana) = a semana', public.agenda_ver(c_admin, 'semana', null, null, null, null, false, c_hoje) ->> 'texto', v_sem);
  v_res := pg_temp.igual(v_res, 'A10d agenda_ver(sem nada) = a semana', public.agenda_ver(c_admin, null, null, null, null, null, false, c_hoje) ->> 'texto', v_sem);
  v_res := pg_temp.igual(v_res, 'A10e agenda_ver(foco atrasos) = os atrasados', public.agenda_ver(c_admin, null, null, 'atrasos', null, null, false, c_hoje) ->> 'texto', v_atr);
  v_res := pg_temp.igual(v_res, 'A10f agenda_ver(foco riscos) = os atrasados', public.agenda_ver(c_admin, null, null, 'riscos', null, null, false, c_hoje) ->> 'texto', v_atr);
  v_res := pg_temp.igual(v_res, 'A10g agenda_ver(foco aprontar) = a rodada', public.agenda_ver(c_admin, null, null, 'aprontar', null, null, false, c_hoje) ->> 'texto', v_apr);
  v_res := pg_temp.igual(v_res, 'A10h agenda_ver(pessoa Roberto, amanhã) = o dia dele',
    public.agenda_ver(c_admin, 'amanha', 'Roberto', null, null, null, false, c_hoje) ->> 'texto', v_rob);
  v_res := pg_temp.igual(v_res, 'A10i agenda_ver(simular {2 dias, [eu, Roberto]}) = a simulação',
    public.agenda_ver(c_admin, null, null, null, null, '{"dias": 2, "com_quem": ["eu", "Roberto"]}'::jsonb, false, c_hoje) ->> 'texto', v_sim);
  v_res := pg_temp.igual(v_res, 'A10j agenda_ver(os "César", simular_aprovacao) = o CTP do ORÇ-00119',
    public.agenda_ver(c_admin, null, null, null, 'César', null, true, c_hoje) ->> 'texto', v_ctp);
  v_res := pg_temp.igual(v_res, 'A10k agenda_ver(os "o do Palazzo", simular_aprovacao) = o mesmo',
    public.agenda_ver(c_admin, null, null, null, 'o do Palazzo', null, true, c_hoje) ->> 'texto', v_ctp);
  v_res := pg_temp.igual(v_res, 'A10l agenda_ver(foco livre) = o resumo e o livre da semana',
    public.agenda_ver(c_admin, null, null, 'livre', null, null, false, c_hoje) ->> 'texto',
    split_part(pg_temp.t(v_sem), E'\n', 2) || E'\n' || split_part(pg_temp.t(v_sem), E'\n', 7));
  v_res := pg_temp.igual(v_res, 'A10m agenda_ver(pessoa Roberto, "segunda") = o dia dele na seg 26/10',
    public.agenda_ver(c_admin, 'segunda', 'Roberto', null, null, null, false, c_hoje) ->> 'texto',
    $e$Seg 26/10, Roberto não tem nada marcado. Costuma vir de seg a sex (pelas diárias das últimas 8 semanas: 3 de 5 segundas).$e$);
  v_res := pg_temp.ok(v_res, 'A10n agenda_ver diz a rota de cada pedido',
    public.agenda_ver(c_admin, null, null, 'o_que_fazer', null, null, false, c_hoje) ->> 'rota' = 'o_que_fazer'
    and public.agenda_ver(c_admin, 'amanha', 'Roberto', null, null, null, false, c_hoje) ->> 'rota' = 'dia_da_pessoa'
    and public.agenda_ver(c_admin, null, 'Roberto', 'o_que_fazer', null, null, false, c_hoje) ->> 'rota' = 'dia_da_pessoa'
    and public.agenda_ver(c_admin, null, null, null, 'César', null, true, c_hoje) ->> 'rota' = 'ctp'
    and public.agenda_ver(c_admin, null, null, 'material', 'Nelson', null, false, c_hoje) ->> 'rota' = 'material_os'
    and public.agenda_ver(c_admin, null, null, 'material', null, null, false, c_hoje) ->> 'rota' = 'material'
    and public.agenda_ver(c_admin, 'hoje', null, null, null, null, false, c_hoje) ->> 'rota' = 'dia'
    and public.agenda_ver(c_admin, '26/10 a 30/10', null, null, null, null, false, c_hoje) ->> 'rota' = 'semana',
    null);

  -- O dia do dono (hoje/amanhã sem pessoa): o marcado + o bloco 2 resumido.
  v_res := pg_temp.igual(v_res, 'A11 agenda_ver(hoje): o dia e o "travado esperando você" resumido',
    public.agenda_ver(c_admin, 'hoje', null, null, null, null, false, c_hoje) ->> 'texto',
    $e$Hoje (sex 23/10): nada marcado.
Travado esperando você: Vanderlei, Lenine, Flávio, Nelson, Giancarlo e mais 2 (o que falta em cada um: *o que eu tenho que fazer*).$e$);

  -- O material: sem OS (uma linha por serviço) e de uma OS (cada item, a situação e o início).
  v_res := pg_temp.igual(v_res, 'A12 material sem OS: uma linha por serviço da fila, os parados no cliente contados à parte',
    public.agenda_ver_material(null, c_hoje) ->> 'texto',
    $e$Material pendente (7 serviços):
• Vanderlei (OS-00069): 4 itens a comprar: de quem e quando?
• Lenine (OS-00074): tem peça a comprar? (o orçamento não tem nenhuma)
• Flávio (OS-00104): "Compressor 12V de…" (pedido em 13/10) chegou?
• Nelson (OS-00112): 4 itens sem compra registrada (comprando hoje, "Central de controle…" chega por volta de qui 29/10)
• Giancarlo (OS-00100): tem peça embutida em "Barramento e proteções…" ou "Realocação do banco…" (e mais 1)?
• Robson (ORÇ-00083): 2 itens a comprar: de quem e quando?
• Rodrigo (OS-00096): tem peça a comprar? (o orçamento não tem nenhuma)
Não conto 4 parados no cliente.$e$);
  v_res := pg_temp.igual(v_res, 'A12b material do Nelson (OS-00112): cada item, o Cerbo "se comprar hoje", o início',
    public.agenda_ver(c_admin, null, null, 'material', 'Nelson', null, false, c_hoje) ->> 'texto',
    $e$Nelson (OS-00112) — material:
• KIT Cabos Comunicação e Energia para Lítio — a comprar, sem fornecedor
• Central de controle cerbo gx victron energy… — se comprar hoje, chega por volta de qui 29/10
• Orion-Tr Smart 12/12-30A Victron (USADO) — a comprar, sem fornecedor
• Painel Touch de Monitoramento e Controle de… — a comprar, sem fornecedor
Ainda não dá para dizer quando começa: 3 itens sem previsão.$e$);

  -- A visão de uma OS e o CTP de uma OS já aprovada.
  v_res := pg_temp.igual(v_res, 'A13 agenda_ver(os "Nelson"): estado, duração, presença, material e prazo',
    public.agenda_ver(c_admin, null, null, null, 'Nelson', null, false, c_hoje) ->> 'texto',
    $e$Nelson (OS-00112): falta você dizer o que já está na mão e o que falta (4 itens sem compra registrada).
Duração: 1 a 2 dias com 2 pessoas (estimativa minha, pelo valor).
Presença: você abre e fecha (não fica o dia todo).
Material: 4 itens sem compra registrada (comprando hoje, "Central de controle…" chega por volta de qui 29/10).
Prazo: qui 05/11 (o meu padrão: 20 dias úteis desde a aprovação).$e$);
  v_res := pg_temp.igual(v_res, 'A13b agenda_ver(os "Robson"): o que trava, quando há mais de uma coisa',
    public.agenda_ver(c_admin, null, null, null, 'Robson', null, false, c_hoje) ->> 'texto',
    $e$Robson (ORÇ-00083): assinado em 23/08 e nunca virou OS.
O que trava: 2 itens a comprar: de quem e quando?; assinado em 23/08 e nunca virou OS: converter ou arquivar?
Duração: meio dia a 1 dia com 2 pessoas (estimativa minha, pelo valor).
Presença: você abre e fecha (não fica o dia todo).
Material: 2 itens a comprar: de quem e quando?
Prazo: passou em seg 21/09 (o meu padrão: 20 dias úteis desde a aprovação).$e$);
  v_res := pg_temp.igual(v_res, 'A13c "se o Nelson aprovar" com a OS já aprovada: diz o estado, sem projeção',
    public.agenda_ver(c_admin, null, null, null, 'Nelson', null, true, c_hoje) ->> 'texto',
    $e$OS-00112 (Nelson) já está aprovada: falta você dizer o que já está na mão e o que falta (4 itens sem compra registrada).$e$);
  v_res := pg_temp.igual(v_res, 'A13d agenda_ver(os "OS-00050"), fora da carteira: o status em português',
    public.agenda_ver(c_admin, null, null, null, 'OS-00050', null, false, c_hoje) ->> 'texto', $e$A OS-00050 já foi concluída.$e$);

  perform pg_temp.gravar(v_res);
end
$a$;

-- ── B. As regras dos textos (fixture) ───────────────────────────────────────────────────────────────────
do $b$
declare
  c_hoje  constant date := date '2026-10-23';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_fixture boolean := exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000104')
                   and exists (select 1 from public.app_users where id = 'aa000000-0000-4000-8000-000000000001');
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  v_t   text;
  v_txt text;
  v_ok  boolean;
  v_msg text;
  v_st  text;
begin
  if not v_fixture then
    insert into _resultado values ('B regras dos textos com a fixture', true, 'PULADO: sem a fixture (produção)');
    return;
  end if;

  v_t := public.agenda_o_que_fazer(null, c_hoje) ->> 'texto';
  v_res := pg_temp.ok(v_res, 'B1 os 5 blocos, cada um uma vez, na ordem: Hoje · Travado · Prontos sem data · Em risco · Outras pendências',
    strpos(v_t, 'Hoje (') = 1
    and strpos(v_t, E'\nTravado esperando você: ') > strpos(v_t, 'Hoje (')
    and strpos(v_t, E'\nProntos sem data: ') > strpos(v_t, E'\nTravado esperando você: ')
    and strpos(v_t, E'\nEm risco: ') > strpos(v_t, E'\nProntos sem data: ')
    and strpos(v_t, E'\nOutras pendências: ') > strpos(v_t, E'\nEm risco: ')
    and (select count(*) from regexp_matches(v_t, '(^|\n)(Hoje \(|Travado esperando você: |Prontos sem data: |Em risco: |Outras pendências: )', 'g')) = 5,
    v_t);

  -- Um número de capacidade por resposta: o comprometível (5,4), nunca a soma crua (6,77) ao lado.
  v_t := public.agenda_semana(null, null, c_hoje) ->> 'texto';
  v_res := pg_temp.ok(v_res, 'B2 a semana tem UM número de capacidade (~5,4), sem 6,77/6,8',
    (select count(*) from regexp_matches(v_t, '~', 'g')) = 1 and strpos(v_t, '~5,4 ') > 0
    and strpos(v_t, '6,77') = 0 and strpos(v_t, '6,8') = 0 and strpos(v_t, 'sem contar você') > 0, null);

  -- Sem palavra de sistema nem inglês em nenhum texto do dia. ("Outras pendências" é o nome do bloco na §6; o que não
  -- pode é a pendência do sistema, no singular.)
  select string_agg(x.nome || ': ' || coalesce(substring(x.texto from '(?i)(ferramenta|registro|n[ií]vel|status|backlog|\mnull\M|\mtrue\M|\mfalse\M|\mpendência\M|\mtool\M|\mOK\M|uuid|jsonb|_[a-z]+_)'), '?'), ' | ')
    into v_txt
    from pg_temp.todos(c_hoje, c_admin) x
   where x.texto ~* '(ferramenta|registro|n[ií]vel|status|backlog|\mnull\M|\mtrue\M|\mfalse\M|\mpendência\M|\mtool\M|uuid|jsonb|_[a-z]+_)'
      or x.texto ~ '\mOK\M';
  v_res := pg_temp.ok(v_res, 'B3 nenhum texto do dia tem palavra de sistema (ferramenta, registro, nível, status, backlog, null, pendência…)',
    v_txt is null, v_txt);

  select string_agg(x.nome || '=' || char_length(x.texto), ', ') filter (where x.texto is null or char_length(x.texto) > c.texto_max)
    into v_txt
    from pg_temp.todos(c_hoje, c_admin) x, public.agenda_config c;
  v_res := pg_temp.ok(v_res, 'B4 todo texto do dia existe e cabe em texto_max', v_txt is null, v_txt);

  -- A semana do fechamento só no dia do plano (quinta); com o dia do plano na sexta, ela sai na sexta.
  v_res := pg_temp.ok(v_res, 'B5 a semana que vem no fechamento só na quinta (3 linhas em 22/10, nenhuma em 23/10)',
    jsonb_array_length(public.agenda_textos_do_fechamento(date '2026-10-22', null) -> 'semana_que_vem') = 3
    and jsonb_array_length(public.agenda_textos_do_fechamento(c_hoje, null) -> 'semana_que_vem') = 0, null);
  begin
    update public.agenda_config set dia_do_plano = 5;
    v_ok := jsonb_array_length(public.agenda_textos_do_fechamento(c_hoje, null) -> 'semana_que_vem') = 3
        and jsonb_array_length(public.agenda_textos_do_fechamento(date '2026-10-22', null) -> 'semana_que_vem') = 0;
    v_res := pg_temp.ok(v_res, 'B5b dia_do_plano = 5: a semana sai na sexta e não na quinta (o parâmetro manda)', v_ok, null);
    update public.agenda_config set modo_leitura = 'desligado';
    r := public.agenda_textos_do_fechamento(c_hoje, null);
    v_res := pg_temp.ok(v_res, 'B6 modo_leitura desligado: o fechamento não recebe nada da agenda',
      r ->> 'modo' = 'desligado' and r ->> 'cauda_amanha' is null and r -> 'semana_que_vem' = '[]'::jsonb, r::text);
    update public.agenda_config set modo_leitura = 'ligado';
    r := public.agenda_textos_do_fechamento(date '2026-10-22', null);
    v_res := pg_temp.ok(v_res, 'B6b ligado: o mesmo texto da sombra, com o modo dito', r ->> 'modo' = 'ligado'
      and r ->> 'cauda_amanha' = 'nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'B5b/B6 (o cenário quebrou)', false, sqlerrm);
  end;

  -- Referência que não existe: "Não encontrei …", sem OS nem data inventadas; nunca erro cru.
  r := public.agenda_ver(c_admin, null, null, null, 'OS-00999', null, false, c_hoje);
  v_res := pg_temp.ok(v_res, 'B7 "como está a OS-00999?": ok false, "Não encontrei a OS-00999.", nenhuma outra OS nem data',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não encontrei a OS-00999.'
    and not exists (select 1 from regexp_matches(r ->> 'texto', '(?:OS|ORÇ)-[0-9]+', 'g') m where m[1] <> 'OS-00999')
    and (r ->> 'texto') !~ '[0-9]{2}/[0-9]{2}', r::text);
  r := public.agenda_ver(c_admin, null, null, null, 'Rodrigo', null, false, c_hoje);
  v_res := pg_temp.ok(v_res, 'B7b "Rodrigo" é ambíguo: a pergunta com os dois números, nada escolhido',
    not (r ->> 'ok')::boolean and r ->> 'pergunta' like 'Qual Rodrigo: OS-00076 % ou OS-00096 %?'
    and jsonb_array_length(r -> 'opcoes') = 2, r ->> 'texto');
  r := public.agenda_ver(c_admin, null, 'Pedro', null, null, null, false, c_hoje);
  v_res := pg_temp.ok(v_res, 'B7c pessoa que não existe: a frase do resolvedor, ok false',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não conheço ninguém chamado Pedro na equipe.', r::text);
  r := public.agenda_ver(c_admin, 'xyz', null, null, null, null, false, c_hoje);
  v_res := pg_temp.ok(v_res, 'B7d período que não dá para entender: a frase da data, ok false (nunca erro cru)',
    not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não entendi a data "xyz".%', r::text);
  r := public.agenda_ver(c_admin, null, null, null, null, '{"dias": 2, "com_quem": ["Pedro"]}'::jsonb, false, c_hoje);
  v_res := pg_temp.ok(v_res, 'B7e simulação com pessoa que não existe: a frase do resolvedor, ok false',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não conheço ninguém chamado Pedro na equipe.', r::text);
  r := public.agenda_ver(c_admin, null, null, null, null, '{"dias": 0}'::jsonb, false, c_hoje);
  v_res := pg_temp.ok(v_res, 'B7f simulação sem dias: pede os dias, ok false', not (r ->> 'ok')::boolean
    and r ->> 'texto' = 'Para simular, diga quantos dias o serviço leva (por exemplo, 2 dias).', r::text);
  r := public.agenda_ver(c_admin, null, null, null, null, null, true, c_hoje);
  v_res := pg_temp.ok(v_res, 'B7g "se aprovar" sem dizer qual: pede o orçamento, ok false', not (r ->> 'ok')::boolean
    and r ->> 'texto' like 'Diga qual orçamento%', r::text);
  r := public.agenda_ctp('05000000-0000-4000-8000-000000000999', c_hoje);
  v_res := pg_temp.ok(v_res, 'B7h CTP, material, visão e dia de id que não existe: "Não encontrei", ok false',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não encontrei esse serviço.'
    and not (public.agenda_ver_material('05000000-0000-4000-8000-000000000999', c_hoje) ->> 'ok')::boolean
    and not (public.agenda_dia_da_pessoa('05000000-0000-4000-8000-000000000999', c_hoje, c_hoje) ->> 'ok')::boolean, r::text);

  -- Foco fora da lista é erro de quem chamou: lança.
  begin
    perform public.agenda_ver(c_admin, null, null, 'semana', null, null, false, c_hoje);
    v_st := 'não lançou';
  exception when others then
    get stacked diagnostics v_st = returned_sqlstate, v_msg = message_text;
  end;
  v_res := pg_temp.ok(v_res, 'B8 agenda_ver com foco fora da lista lança 22023', v_st = '22023', coalesce(v_msg, v_st));

  perform pg_temp.gravar(v_res);
end
$b$;

-- ── C. Cenários (cada um desfeito na hora) ──────────────────────────────────────────────────────────────
do $c$
declare
  c_hoje  constant date := date '2026-10-23';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_rob_u constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_rob   constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_gus   constant uuid := 'bb000000-0000-4000-8000-000000000001';
  v_fixture boolean := exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000104')
                   and exists (select 1 from public.app_users where id = 'aa000000-0000-4000-8000-000000000001');
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  v_t    text;
  v_full text;
  v_ok   boolean;
  v_atr  int;
  v_hj   int;
  v_txt  text;
begin
  if not v_fixture then
    insert into _resultado values ('C cenários com a fixture', true, 'PULADO: sem a fixture (produção)');
    return;
  end if;

  -- C1: o que o dono disse do Nelson (3 itens na mão, o painel chega dia 3) e do compressor do Flávio.
  begin
    insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                    quantidade_na_mao, situacao, fonte, chegou_em, previsao_ate, previsao_fonte, trecho, atualizado_em)
    values (pg_temp.os('112'), md5('peca:112:1')::uuid, 'peca', 'KIT Cabos Comunicação e Energia para Lítio', 1, 1, 'na_mao', 'dono', c_hoje, null, null, 'tão aqui', '2026-10-23 10:00-03'),
           (pg_temp.os('112'), md5('peca:112:2')::uuid, 'peca', 'CENTRAL DE CONTROLE CERBO GX', 1, 1, 'na_mao', 'dono', c_hoje, null, null, 'tão aqui', '2026-10-23 10:00-03'),
           (pg_temp.os('112'), md5('peca:112:3')::uuid, 'peca', 'Orion-Tr Smart 12/12-30A Victron (USADO)', 1, 1, 'na_mao', 'dono', c_hoje, null, null, 'tão aqui', '2026-10-23 10:00-03'),
           (pg_temp.os('112'), md5('peca:112:4')::uuid, 'peca', 'Painel Touch de Monitoramento e Controle de Energia – HBR 7"', 1, 0, 'a_caminho', 'dono', null, '2026-11-03', 'dono', 'o painel chega dia 3', '2026-10-23 10:00-03');
    insert into public.os_material (service_order_id, purchase_order_item_id, origem, descricao, quantidade_necessaria,
                                    quantidade_na_mao, situacao, fonte, chegou_em, trecho)
    values (pg_temp.os('104'), '71000000-0000-4000-8000-000000000001', 'oc', 'Compressor 12V de geladeira SS65', 1, 1, 'na_mao', 'dono',
            '2026-10-14', 'o compressor do Flávio chegou dia 14');
    v_res := pg_temp.igual(v_res, 'C1a material do Nelson: "você disse em 23/10" com as palavras dele; o início qua 04/11',
      public.agenda_ver_material(pg_temp.os('112'), c_hoje) ->> 'texto',
      $e$Nelson (OS-00112) — material:
• KIT Cabos Comunicação e Energia para Lítio — na mão desde sex 23/10 — você disse em 23/10: "tão aqui"
• Central de controle cerbo gx — na mão desde sex 23/10 — você disse em 23/10: "tão aqui"
• Orion-Tr Smart 12/12-30A Victron (USADO) — na mão desde sex 23/10 — você disse em 23/10: "tão aqui"
• Painel Touch de Monitoramento e Controle de… — chega ter 03/11 — você disse em 23/10: "o painel chega dia 3"
Pelo material, começa a partir de qua 04/11 (1 dia útil depois de o último chegar).$e$);
    v_t := public.agenda_semana(null, null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C1b semana: Nelson pronto a partir de qua 04/11; o Flávio passa a "tem peça embutida?"',
      split_part(v_t, E'\n', 3) = 'Prontos para começar: Nelson (a partir de qua 04/11). Quase: Lenine e Rodrigo (OS-00096), se não tiverem peça a comprar.'
      and split_part(v_t, E'\n', 4) = 'Travados por material: Vanderlei (4 itens a comprar), Flávio (tem peça embutida?) e Giancarlo (tem peça embutida?).',
      v_t);
    v_res := pg_temp.igual(v_res, 'C1c em 05/11 a previsão do dono venceu: "você ainda não me disse que chegou"',
      split_part(public.agenda_ver_material(pg_temp.os('112'), date '2026-11-05') ->> 'texto', E'\n', 5),
      $e$• Painel Touch de Monitoramento e Controle de… — chega ter 03/11 — você disse em 23/10: "o painel chega dia 3"; você ainda não me disse que chegou$e$);
    v_t := public.agenda_atrasos(date '2026-11-05') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C1d atrasos de 05/11: a previsão vencida do painel e o Nelson em risco (prazo qui 05/11)',
      strpos(v_t, 'Previsão de material vencida: Nelson ("Painel Touch de…", era ter 03/11).') > 0
      and strpos(v_t, 'Pode passar do prazo, no ritmo que eu estimo: Nelson (prazo qui 05/11).') > 0, v_t);
    v_res := pg_temp.ok(v_res, 'C1e até a data prevista, nada de cobrar: em 23/10 o painel não tem "ainda não me disse"',
      strpos(public.agenda_ver_material(pg_temp.os('112'), c_hoje) ->> 'texto', 'ainda não me disse') = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C1 (o cenário quebrou)', false, sqlerrm);
  end;

  -- C2: a OS-00074 marcada ter 27/10 08:00 a qua 28/10 com o Roberto; um compromisso do dono hoje às 14:00.
  begin
    update public.service_orders set scheduled_start_at = '2026-10-27 08:00-03', scheduled_end_at = '2026-10-28 17:00-03'
     where id = pg_temp.os('74');
    insert into public.service_order_technicians (service_order_id, user_id) values (pg_temp.os('74'), c_rob_u);
    insert into public.agenda_tasks (title, assignee_user_id, status, kind, scheduled_start_at, scheduled_end_at)
    values ('Reunião na marina com o síndico', c_admin, 'pending', 'appointment', '2026-10-23 14:00-03', '2026-10-23 15:00-03');
    v_t := public.agenda_ver(c_admin, 'proxima_semana', null, null, null, null, false, c_hoje) ->> 'texto';
    v_res := pg_temp.igual(v_res, 'C2a semana que vem: o marcado em faixa de dias e o aviso das diárias em frase própria',
      split_part(v_t, E'\n', 1),
      $e$A semana que vem (seg 26/10 a sáb 31/10): Lenine de ter 27/10 a qua 28/10. Nenhuma diária foi lançada depois de sáb 17/10: não sei o que a equipe fez de seg 19/10 até hoje.$e$);
    v_t := public.agenda_o_que_fazer(null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C2b o que fazer: o compromisso de hoje no bloco 1, o Lenine nos próximos 7 dias, a tarefa com hora conta como de hoje',
      split_part(v_t, E'\n', 1) = 'Hoje (sex 23/10): Reunião na marina com o síndico às 14:00.'
      and split_part(v_t, E'\n', 3) = 'Prontos sem data: nenhum. Próximos 7 dias: Lenine de ter 27/10 a qua 28/10.'
      and strpos(v_t, 'Outras pendências: 1 tarefa atrasada e 4 de hoje;') > 0, v_t);
    v_res := pg_temp.igual(v_res, 'C2c Roberto na terça: a OS em que ele é técnico, com a hora',
      public.agenda_dia_da_pessoa(c_rob, date '2026-10-27', c_hoje) ->> 'texto',
      $e$Ter 27/10, Roberto tem Lenine às 08:00 (até qua 28/10). Costuma vir de seg a sex (pelas diárias das últimas 8 semanas: 5 de 6 terças).$e$);
    v_res := pg_temp.igual(v_res, 'C2d Roberto na quarta: o último dia da OS',
      public.agenda_dia_da_pessoa(c_rob, date '2026-10-28', c_hoje) ->> 'texto',
      $e$Qua 28/10, Roberto tem Lenine (último dia). Costuma vir de seg a sex (pelas diárias das últimas 8 semanas).$e$);
    r := public.agenda_textos_do_fechamento(date '2026-10-22', date '2026-10-23');
    v_res := pg_temp.ok(v_res, 'C2e fechamento: com algo marcado amanhã a agenda não manda cauda; a semana diz "1 marcado (Lenine)"',
      r ->> 'cauda_amanha' is null
      and r -> 'semana_que_vem' ->> 0 = 'Semana que vem (projeção): 1 marcado (Lenine); 7 serviços na fila, uns 17 a 32 dias de equipe (~5,4 por semana, sem contar você).',
      r::text);
    v_res := pg_temp.ok(v_res, 'C2f a OS marcada sai da quase (é marcada) e a semana atual não a mostra (é da semana que vem)',
      strpos(public.agenda_semana(null, null, c_hoje) ->> 'texto', 'Quase: Rodrigo (OS-00096), se não tiver peça a comprar.') > 0,
      public.agenda_semana(null, null, c_hoje) ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C2 (o cenário quebrou)', false, sqlerrm);
  end;

  -- C3: "Outras pendências" = a regra de my_agenda (agenda.ts: status pending/in_progress do login; âncora due_at,
  -- senão scheduled_start_at; atrasada < 03:00Z do dia, de hoje em [03:00Z, 03:00Z do dia seguinte); a receber e a
  -- pagar pending/partially_paid vencendo hoje, valor = saldo ?? valor), nas bordas do dia de Brasília.
  begin
    insert into public.agenda_tasks (title, assignee_user_id, status, kind, due_at, scheduled_start_at) values
      ('borda: 22/10 23:59', c_admin, 'pending', 'task', '2026-10-22 23:59-03', null),           -- atrasada
      ('borda: 23/10 00:00', c_admin, 'pending', 'task', '2026-10-23 00:00-03', null),           -- de hoje
      ('só a hora: 23/10 23:30', c_admin, 'in_progress', 'task', null, '2026-10-23 23:30-03'),   -- de hoje
      ('feita ontem', c_admin, 'done', 'task', '2026-10-22 10:00-03', null),                    -- fora
      ('sem data', c_admin, 'pending', 'task', null, null),                                      -- fora
      ('de outra pessoa', c_rob_u, 'pending', 'task', '2026-10-23 10:00-03', null),              -- fora
      ('cancelada', c_admin, 'cancelled', 'task', '2026-10-23 10:00-03', null),                  -- fora
      ('amanhã 00:00', c_admin, 'pending', 'task', '2026-10-24 00:00-03', null);                 -- fora
    insert into public.receivables (client_id, description, issue_date, due_date, amount, status, paid_amount, balance_amount) values
      ('c1000000-0000-4000-8000-000000000001', 'r1', '2026-10-01', c_hoje, 500, 'pending', 0, 500),
      ('c1000000-0000-4000-8000-000000000001', 'r2', '2026-10-01', c_hoje, 300, 'partially_paid', 100, 200),
      ('c1000000-0000-4000-8000-000000000001', 'r3', '2026-10-01', c_hoje, 900, 'paid', 900, 0),
      ('c1000000-0000-4000-8000-000000000001', 'r4', '2026-10-01', c_hoje, 900, 'overdue', 0, 900),
      ('c1000000-0000-4000-8000-000000000001', 'r5', '2026-10-01', c_hoje + 1, 900, 'pending', 0, 900),
      ('c1000000-0000-4000-8000-000000000001', 'r6', '2026-10-01', c_hoje, 80, 'pending', 0, null);
    insert into public.payables (description, issue_date, due_date, amount, status, paid_amount, balance_amount) values
      ('p2', '2026-10-01', c_hoje, 100, 'partially_paid', 12.40, 87.60),
      ('p3', '2026-10-01', c_hoje, 999, 'cancelled', 0, 999);
    -- A regra escrita de novo, à parte, com os instantes do dia em UTC (como o TS compara).
    select count(*) filter (where coalesce(t.due_at, t.scheduled_start_at) < timestamptz '2026-10-23 03:00:00+00'),
           count(*) filter (where coalesce(t.due_at, t.scheduled_start_at) >= timestamptz '2026-10-23 03:00:00+00'
                              and coalesce(t.due_at, t.scheduled_start_at) < timestamptz '2026-10-24 03:00:00+00')
      into v_atr, v_hj
      from public.agenda_tasks t where t.assignee_user_id = c_admin and t.status in ('pending', 'in_progress');
    r := public.agenda_o_que_fazer(null, c_hoje);
    v_res := pg_temp.ok(v_res, 'C3a tarefas: as contagens são as da regra de my_agenda (2 atrasadas, 5 de hoje) nas bordas do dia',
      v_atr = 2 and v_hj = 5 and r #>> '{dados,outras,tarefas_atrasadas}' = v_atr::text
      and r #>> '{dados,outras,tarefas_de_hoje}' = v_hj::text, (r #> '{dados,outras}')::text);
    v_res := pg_temp.ok(v_res, 'C3b a receber: pending/partially_paid de hoje, saldo ou valor (500 + 200 + 80); a pagar: 312,40 + 87,60',
      r #>> '{dados,outras,a_receber,n}' = '3' and (r #>> '{dados,outras,a_receber,total}')::numeric = 780
      and r #>> '{dados,outras,a_pagar,n}' = '2' and (r #>> '{dados,outras,a_pagar,total}')::numeric = 400,
      (r #> '{dados,outras}')::text);
    v_res := pg_temp.igual(v_res, 'C3c o 5º bloco com essas contas',
      split_part(r ->> 'texto', E'\n', 5),
      $e$Outras pendências: 2 tarefas atrasadas e 5 de hoje; a receber hoje: 3 cobranças, R$ 780,00; a pagar hoje: 2 contas, R$ 400,00.$e$);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C3 (o cenário quebrou)', false, sqlerrm);
  end;

  -- C4: o dono disse o padrão dele (seg a sex; sexta à tarde, não): entra na capacidade e a rodada não pergunta mais.
  begin
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values (c_gus, '{1,2,3,4,5}', 'disponivel', 'dono');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem) values (c_gus, '{5}', 'tarde', 'indisponivel', 'dono');
    v_t := public.agenda_semana(null, null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C4a com o padrão do dono: "~9 diárias… (o que vocês lançaram e o que você disse, com folga), contando você"',
      strpos(v_t, 'no ritmo de ~9 diárias de equipe por semana (o que vocês lançaram e o que você disse, com folga), contando você.') > 0
      and strpos(v_t, 'sem contar você') = 0, split_part(v_t, E'\n', 2));
    v_t := public.agenda_aprontar(c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C4b a rodada não pergunta mais "Você: … quais dias?"', strpos(v_t, '• Você:') = 0, v_t);
    v_res := pg_temp.igual(v_res, 'C4c o dia do dono na sexta: só de manhã (você disse)',
      public.agenda_dia_da_pessoa(c_gus, date '2026-10-30', c_hoje) ->> 'texto',
      $e$Sex 30/10, você não tem nada marcado — só de manhã. Você costuma ficar em campo de seg a sex (você disse).$e$);
    v_res := pg_temp.igual(v_res, 'C4d simulação com o João à tarde e você (com padrão, você entra na conta)',
      public.agenda_simular(1.5, '[{"pessoa": "João", "turnos": "tarde"}, "eu"]'::jsonb, null, c_admin, c_hoje) ->> 'texto',
      $e$Um serviço de 1,5 dia com você e João (à tarde) (são 2,5 diárias de equipe: você 1,5 e João 1): no fim da fila, começa entre ter 10/11 e seg 23/11. Passando na frente de tudo, dá para começar ter 27/10, e o resto atrasa uns 2 dias úteis. É projeção: não reserva nada.$e$);
    -- Só à tarde = um turno em cada dia ocupado: meio dia com o João à tarde é meio dia dele (0,5 diária), não 0,25.
    v_t := public.agenda_simular(0.5, '[{"pessoa": "João", "turnos": "tarde"}]'::jsonb, null, c_admin, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C4e simulação de meio dia com o João à tarde: 0,5 diária de equipe (era 0,25)',
      v_t like 'Um serviço de meio dia com João (à tarde) (são 0,5 diárias de equipe): %', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C4 (o cenário quebrou)', false, sqlerrm);
  end;

  -- C5: o Lenine em espera (você pediu) e o Vanderlei em andamento sem diária desde sáb 17/10.
  begin
    insert into public.os_planejamento (service_order_id, congelada_ate, revisar_em) values (pg_temp.os('74'), '2026-10-30', '2026-10-28');
    update public.service_orders set status = 'in_progress' where id = pg_temp.os('69');
    update public.work_shifts set service_order_id = pg_temp.os('69')
     where data = '2026-10-17' and work_profile_id = 'cc000000-0000-4000-8000-000000000002';
    v_t := public.agenda_semana(null, null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C5a semana: "Em andamento: Vanderlei (sem diária desde 17/10)" e "Em espera (você pediu): Lenine (até sex 30/10)"',
      strpos(v_t, E'\nEm andamento: Vanderlei (sem diária desde 17/10).\n') > 0
      and strpos(v_t, E'\nEm espera (você pediu): Lenine (até sex 30/10).\n') > 0
      and char_length(v_t) <= (select texto_max from public.agenda_config), v_t);
    v_t := public.agenda_o_que_fazer(null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C5b o que fazer: o andamento parado é a 1ª coisa do Vanderlei ("parou?"); o Lenine em espera sai do bloco 2',
      strpos(v_t, 'Travado esperando você: Vanderlei — em andamento sem diária desde 17/10: parou?; ') > 0
      and strpos(v_t, 'Lenine —') = 0, v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C5 (o cenário quebrou)', false, sqlerrm);
  end;

  -- C6: sem diária nenhuma, não há ritmo: a fila diz o tamanho e não inventa data.
  begin
    delete from public.work_shifts;
    delete from public.agenda_disponibilidade;
    v_t := public.agenda_semana(null, null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C6a sem diárias: "não sei o ritmo da equipe", sem "Livre de verdade" nem semanas',
      strpos(v_t, 'Livre ela não está: há 7 serviços aprovados, uns 17 a 32 dias de equipe — não sei o ritmo da equipe: não há diárias lançadas para medir.') > 0
      and strpos(v_t, 'Livre de verdade') = 0 and strpos(v_t, 'semana') > 0 and v_t !~ '[0-9]+ a [0-9]+ semanas', v_t);
    v_t := public.agenda_simular(2, '["Roberto"]'::jsonb, null, null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C6b simulação sem ritmo: não diz quando cabe', v_t !~ '[0-9]{2}/[0-9]{2}'
      and strpos(v_t, 'não sei dizer quando cabe') > 0, v_t);
    v_t := public.agenda_ctp(pg_temp.os('119'), c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C6c CTP sem ritmo: a duração e as compras, sem data e sem frase ao cliente',
      v_t !~ '[0-9]{2}/[0-9]{2}' and strpos(v_t, 'Para o cliente') = 0 and strpos(v_t, 'não sei o ritmo da equipe') > 0, v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C6 (o cenário quebrou)', false, sqlerrm);
  end;

  -- C7: carteira vazia: nada inventado.
  begin
    delete from public.service_order_parts; delete from public.service_order_services; delete from public.purchase_order_items;
    delete from public.purchase_orders; delete from public.receivables; delete from public.service_order_technicians;
    delete from public.service_orders;
    v_t := public.agenda_semana(null, null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C7a carteira vazia: "Não há serviço aprovado esperando na fila." e "Livre de verdade: a partir de ter 27/10."',
      strpos(v_t, E'\nNão há serviço aprovado esperando na fila.\n') > 0 and strpos(v_t, E'\nLivre de verdade: a partir de ter 27/10.') > 0, v_t);
    v_res := pg_temp.ok(v_res, 'C7b vazia: nada atrasado; nenhum material pendente; o bloco 2 "nada"',
      public.agenda_atrasos(c_hoje) ->> 'texto' = 'Nada atrasado: nenhum serviço passou do prazo e nenhuma previsão de material venceu.'
      and public.agenda_ver_material(null, c_hoje) ->> 'texto' = 'Nenhum serviço da fila com material pendente.'
      and strpos(public.agenda_o_que_fazer(null, c_hoje) ->> 'texto', E'\nTravado esperando você: nada.\n') > 0, null);
    r := public.agenda_textos_do_fechamento(date '2026-10-22', null);
    v_res := pg_temp.ok(v_res, 'C7c vazia: a cauda do fechamento diz "nenhum serviço na fila"',
      r ->> 'cauda_amanha' = 'nada marcado; nenhum serviço na fila (*agenda*)', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C7 (o cenário quebrou)', false, sqlerrm);
  end;

  -- C8: o corte em texto_max = 400 — por item ("e mais N") e por linha inteira, nunca no meio de uma linha.
  begin
    update public.agenda_config set texto_max = 3000;
    create temp table _cheio on commit drop as select x.nome, x.texto from pg_temp.todos(c_hoje, c_admin) x;
    update public.agenda_config set texto_max = 400;
    select string_agg(x.nome, ', ')
      into v_txt
      from pg_temp.todos(c_hoje, c_admin) x
      join _cheio ch on ch.nome = x.nome
     where char_length(x.texto) > 400
        or exists (select 1 from unnest(string_to_array(x.texto, E'\n')) l
                    where l not in (select unnest(string_to_array(ch.texto, E'\n')))
                      and l !~ 'e mais [0-9]+' and l !~ '^\(e mais [0-9]+ linhas?\)$'
                      -- o rodapé da rodada lista o que ficou para depois: com menos OS na rodada, a lista cresce
                      and l !~ 'para depois\.\)$');
    v_res := pg_temp.ok(v_res, 'C8a texto_max 400: todo texto cabe; toda linha é inteira do texto cheio, traz "e mais N" ou é o "para depois"',
      v_txt is null, v_txt);
    v_t := public.agenda_o_que_fazer(null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C8b o corte começa pela lista mais longa (o bloco 2), que fica com "e mais N"; os 5 blocos continuam',
      strpos(v_t, 'Travado esperando você: Vanderlei — 4 itens a comprar: de quem e quando?; e mais 6.') > 0
      and strpos(v_t, E'\nOutras pendências: ') > 0, v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C8 (o cenário quebrou)', false, sqlerrm);
  end;

  perform pg_temp.gravar(v_res);
end
$c$;

-- ── K. Determinismo e nada gravado (com ou sem a fixture) ───────────────────────────────────────────────
do $k$
declare
  c_hoje constant date := date '2026-10-23';
  v_admin uuid := (select u.id from public.app_users u where u.role = 'admin' and u.active order by u.created_at, u.id limit 1);
  v_antes text;
  v_depois text;
  v_res jsonb := '[]'::jsonb;
  f text;
  a text;
  b text;
begin
  select format('%s/%s/%s/%s/%s/%s', (select count(*) from public.os_material), (select count(*) from public.os_planejamento),
                (select count(*) from public.os_planejamento_equipe), (select count(*) from public.agenda_disponibilidade),
                (select count(*) from public.agenda_rascunho), (select count(*) from public.agenda_tasks))
    into v_antes;
  foreach f in array array[
    'select public.agenda_semana(null, null, %L)::text',
    'select public.agenda_o_que_fazer(null, %L)::text',
    'select public.agenda_atrasos(%L)::text',
    'select public.agenda_aprontar(%L)::text',
    'select public.agenda_ver_material(null, %L)::text',
    'select string_agg(public.agenda_ver_material(k.service_order_id, %1$L)::text, ''|'' order by k.numero) from public.os_carteira(%1$L) k',
    'select string_agg(public.agenda_ctp(k.service_order_id, %1$L)::text, ''|'' order by k.numero) from public.os_carteira(%1$L) k',
    'select string_agg(public.agenda_dia_da_pessoa(p.id, %1$L::date + 1, %1$L)::text, ''|'' order by p.id) from public.payees p',
    'select public.agenda_simular(2, ''["Roberto"]''::jsonb, null, null, %L)::text',
    'select public.agenda_textos_do_fechamento(%L::date - 1, null)::text',
    'select public.agenda_ver(null, null, null, ''o_que_fazer'', null, null, false, %L)::text']
  loop
    execute format(f, c_hoje) into a;
    execute format(f, c_hoje) into b;
    v_res := pg_temp.ok(v_res, 'K1 2× = o mesmo md5: ' || split_part(split_part(f, 'public.', 2), '(', 1),
      a is not null and md5(a) = md5(b), md5(coalesce(a, '')));
  end loop;
  select format('%s/%s/%s/%s/%s/%s', (select count(*) from public.os_material), (select count(*) from public.os_planejamento),
                (select count(*) from public.os_planejamento_equipe), (select count(*) from public.agenda_disponibilidade),
                (select count(*) from public.agenda_rascunho), (select count(*) from public.agenda_tasks))
    into v_depois;
  v_res := pg_temp.ok(v_res, 'K2 nenhuma leitura grava (material, planejamento, equipe, disponibilidade, rascunho, tarefas)',
    v_antes = v_depois, v_antes || ' → ' || v_depois);
  perform pg_temp.gravar(v_res);
end
$k$;

-- ── P. Regras gerais sobre o dado que houver (produção ou fixture) ──────────────────────────────────────
insert into _resultado
select 'P1 "o que eu tenho que fazer": texto não vazio, ≤ texto_max, os 5 blocos na ordem',
       r ->> 'texto' is not null and char_length(r ->> 'texto') <= c.texto_max
       and strpos(r ->> 'texto', 'Hoje (') = 1
       and strpos(r ->> 'texto', E'\nTravado esperando você: ') > 0
       and strpos(r ->> 'texto', E'\nProntos sem data: ') > strpos(r ->> 'texto', E'\nTravado esperando você: ')
       and strpos(r ->> 'texto', E'\nEm risco: ') > strpos(r ->> 'texto', E'\nProntos sem data: ')
       and strpos(r ->> 'texto', E'\nOutras pendências: ') > strpos(r ->> 'texto', E'\nEm risco: '),
       left(r ->> 'texto', 200)
  from public.agenda_config c, lateral public.agenda_o_que_fazer(null, public._hoje_brt()) r
 where public._agenda_dono(null) is not null;

insert into _resultado
select 'P2 semana, atrasos, rodada, material e fechamento: ok, texto ≤ texto_max, nunca vazio',
       bool_and(x.t is not null and x.t <> '' and char_length(x.t) <= c.texto_max), string_agg(x.n || '=' || coalesce(char_length(x.t), -1), ', ')
  from public.agenda_config c,
       lateral (select 'semana' n, public.agenda_semana(null, null, public._hoje_brt()) ->> 'texto' t
                union all select 'atrasos', public.agenda_atrasos(public._hoje_brt()) ->> 'texto'
                union all select 'aprontar', public.agenda_aprontar(public._hoje_brt()) ->> 'texto'
                union all select 'material', public.agenda_ver_material(null, public._hoje_brt()) ->> 'texto'
                union all select 'fechamento', coalesce(public.agenda_textos_do_fechamento(public._hoje_brt(), null) ->> 'modo', '')) x;

insert into _resultado
select 'P3 a fila do painel bate com a prontidão (executável = sem espera, sem cliente, sem sinal)',
       (p #>> '{backlog,n}')::int = (select count(*) from public.os_prontidao_carteira(public._hoje_brt()) x
                                      where x ->> 'estado' not in ('congelada', 'aguardando_cliente', 'sem_sinal')),
       (p -> 'backlog')::text
  from public._agenda_painel(public._hoje_brt()) p;

-- ── L. Portas ───────────────────────────────────────────────────────────────────────────────────────────
create temp table _funcoes_p4 (f text) on commit drop;
insert into _funcoes_p4 values
  ('public._agenda_maiuscula(text)'), ('public._agenda_num(numeric, integer)'), ('public._agenda_plural(integer, text, text)'),
  ('public._agenda_corta(text, integer)'), ('public._agenda_dia_rotulo(date, date)'), ('public._agenda_periodo_rotulo(date, date, date)'),
  ('public._agenda_periodo(text, date)'), ('public._agenda_rotulo(jsonb, text)'), ('public._agenda_nomes(jsonb, integer, text)'),
  ('public._agenda_restricao_curta(jsonb)'), ('public._agenda_juntar(text[], integer)'),
  ('public._agenda_marcados(date, date, date, uuid, uuid)'), ('public._agenda_painel(date)'), ('public._agenda_lista_de(jsonb, text, text)'),
  ('public._agenda_fila_faixa(jsonb)'), ('public._agenda_resumo(jsonb, boolean)'), ('public._agenda_livre_linha(jsonb, boolean)'),
  ('public._agenda_lim(jsonb, text)'), ('public._agenda_encolher(jsonb, jsonb)'), ('public._agenda_linhas(jsonb)'),
  ('public._agenda_semana_de(jsonb, date, date, jsonb, jsonb)'), ('public.agenda_semana(date, date, date)'),
  ('public._agenda_outras(uuid, date)'), ('public._agenda_o_que_fazer_de(jsonb, jsonb, jsonb, jsonb, jsonb)'),
  ('public.agenda_o_que_fazer(uuid, date)'), ('public._agenda_atrasos_de(jsonb, integer)'), ('public.agenda_atrasos(date)'),
  ('public._agenda_material_resumo(jsonb)'), ('public.agenda_ver_material(uuid, date)'),
  ('public.agenda_dia_da_pessoa(uuid, date, date)'), ('public._agenda_aprontar_de(jsonb, integer)'), ('public.agenda_aprontar(date)'),
  ('public.agenda_simular(numeric, jsonb, text, uuid, date)'), ('public.agenda_ctp(uuid, date)'),
  ('public.agenda_textos_do_fechamento(date, date)'), ('public._agenda_dia_de(jsonb, date, integer)'),
  ('public._agenda_ver_os(uuid, date)'), ('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)');

insert into _resultado
select 'L1 anon não executa nenhuma função nova',
       not bool_or(has_function_privilege('anon', f, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute'))
  from _funcoes_p4;

insert into _resultado
select 'L2 authenticated (o painel) e service_role (WhatsApp, fechamento) executam todas',
       bool_and(has_function_privilege('authenticated', f, 'execute') and has_function_privilege('service_role', f, 'execute')),
       string_agg(f, ', ') filter (where not has_function_privilege('authenticated', f, 'execute')
                                      or not has_function_privilege('service_role', f, 'execute'))
  from _funcoes_p4;

insert into _resultado
select 'L3 nenhuma security definer, todas STABLE ou IMMUTABLE, search_path fixo (38 funções)',
       bool_and(not p.prosecdef) and bool_and(p.provolatile in ('s', 'i'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%') and count(*) = 38,
       count(*)::text || ' | ' || coalesce(string_agg(p.oid::regprocedure::text || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ')
                                    filter (where p.prosecdef or p.provolatile not in ('s', 'i')
                                               or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%'), '')
  from pg_proc p
 where p.oid in (select f::regprocedure::oid from _funcoes_p4);

-- L4: quem não lê agenda_config (o técnico, pela RLS) recebe ERRO — nunca uma agenda "livre" ou vazia.
do $l4$
declare
  v_msg text;
  v_r   jsonb;
begin
  begin
    perform set_config('request.jwt.claim.sub', 'aa000000-0000-4000-8000-0000000000ff', true);
    perform set_config('request.jwt.claims', json_build_object('sub', 'aa000000-0000-4000-8000-0000000000ff',
                                                               'role', 'authenticated')::text, true);
    set local role authenticated;
    v_r := public.agenda_ver(null, null, null, 'o_que_fazer', null, null, false, date '2026-10-23');
    reset role;
    v_msg := null;
  exception when others then
    v_msg := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('L4 quem não lê agenda_config (técnico) recebe erro, nunca uma agenda vazia',
    v_msg like 'A agenda está sem os parâmetros%', coalesce(v_msg, 'não deu erro: ' || left(v_r ->> 'texto', 120)));
end
$l4$;

-- L5: o admin, pelo painel (authenticated + o login dele), lê o mesmo texto que o WhatsApp (service role).
do $l5$
declare
  v_admin uuid := (select u.id from public.app_users u where u.role = 'admin' and u.active order by u.created_at, u.id limit 1);
  v_msg   text;
  v_painel text;
  v_zap   text := public.agenda_ver(null, null, null, 'o_que_fazer', null, null, false, date '2026-10-23') ->> 'texto';
begin
  if v_admin is null then
    insert into _resultado values ('L5 o admin lê a agenda pelo painel', true, 'PULADO: sem admin ativo');
    return;
  end if;
  begin
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_painel := public.agenda_ver(v_admin, null, null, 'o_que_fazer', null, null, false, date '2026-10-23') ->> 'texto';
    reset role;
  exception when others then
    v_msg := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('L5 o admin pelo painel (authenticated, com login) lê o mesmo "o que fazer" do WhatsApp',
    v_msg is null and v_painel = v_zap, coalesce(v_msg, pg_temp.dif(v_painel, v_zap)));
end
$l5$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
