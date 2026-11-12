-- Retorno F5 (P15): o PDF à mão da F4 com "ORÇ-" (com cedilha) no nome do arquivo. parceiro_detectar_pdf, regenerada com
-- (or[cç]|os), acha a mesma ordem em "ORÇ-", "orç-" e "Orcamento-ORÇ-" que em "ORC-", e grava o número como antes (ORC-nnnnn);
-- "OS-" continua OS-nnnnn; sem hífen continua sem número. O resto da F4 (marca d'água, destino, situações) é testado pela
-- regressão do grupo 7 (F5_REGRESSAO=7), sem mudar nenhum teste. Roda só pela bancada (grupo 8, F5_ONDA=2,
-- F5_TESTES=retorno_f5_pdf_mao_f4). Termina em ROLLBACK, e o bloco se desfaz sozinho. Só confere as próprias linhas
-- sintéticas: o número do parceiro e os ecos são inventados (55479000152xx), nomes inventados (Ana, Carla), números de
-- documento inventados (9916x). Relógio: ter 12/01/2027 10:00.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5p_os(p_cliente uuid, p_numero text, p_status text, p_quote text) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total)
  values (p_numero, p_cliente, v_v, p_status, p_quote, 'repair', '2026-10-01 10:00-03', '2026-10-01 10:00-03', 0)
  returning id into v_id;
  return v_id;
end $f$;

-- O documento que saiu do aparelho do dono (eco: data, sem via).
create or replace function pg_temp.f5p_eco(p_fone text, p_arquivo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, raw_payload, occurred_at, hora_real)
  values ('outbound', p_fone, 'document', null, 'teste-f5-pdf-mao-' || md5(p_fone || p_arquivo || p_em::text || random()::text),
          jsonb_build_object('data', jsonb_build_object('source', 'unknown', 'message',
                                                        jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo)))),
          p_em, p_em)
  returning id
$f$;

do $pdf$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_parceiro_fone constant text := '5547900015201';
  c_arquivos constant text[] := array['ORÇ-99161.pdf', 'orç-99161.pdf', 'Orcamento-ORÇ-99161.pdf', 'Orcamento_ORC-99161_Ana.pdf',
                                      'OS_OS-99160_Ana.pdf'];
  c_numeros constant text[] := array['ORC-99161', 'ORC-99161', 'ORC-99161', 'ORC-99161', 'OS-99160'];
  c_minutos constant integer[] := array[50, 45, 40, 35, 30];
  v_p uuid;
  v_carla uuid;
  v_ana uuid;
  v_orc uuid;
  v_os uuid;
  v_ordens uuid[];
  v_msgs uuid[] := '{}';
  v_i integer;
  v_e public.parceiro_envios_a_mao;
  v_r jsonb;
  v_sem_hifen uuid;
  v_sem_numero integer;
begin
  begin
  update public.retorno_config set pdf_mao_modo = 'registrar', parceiro_pdf_ate = c_t - interval '1 hour' where id;

  insert into public.parceiros (nome, sigla, tipo) values ('Revenda PDF F5 Teste', 'RPFQ', 'revenda') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento)
    values (v_carla, c_parceiro_fone, '00015201', '47', 'confirmado', c_t - interval '30 days', true);
  insert into public.clients (type, name, whatsapp) values ('individual', 'Ana PDF F5 Teste', '5547900015211') returning id into v_ana;
  v_orc := pg_temp.f5p_os(v_ana, 'ORÇ-99161', 'draft', 'draft');
  v_os := pg_temp.f5p_os(v_ana, 'OS-99160', 'open', 'approved');

  -- ── 1. Os nomes de arquivo, todos à parceira, depois da marca ──
  -- com cedilha maiúsculo; com cedilha minúsculo; o nome do "Baixar" da tela; sem cedilha (igual a antes); OS (igual a antes)
  v_ordens := array[v_orc, v_orc, v_orc, v_orc, v_os];
  for v_i in 1 .. cardinality(c_arquivos) loop
    v_msgs := v_msgs || pg_temp.f5p_eco(c_parceiro_fone, c_arquivos[v_i], c_t - make_interval(mins => c_minutos[v_i]));
  end loop;
  v_sem_hifen := pg_temp.f5p_eco(c_parceiro_fone, 'ORC99161.pdf', c_t - interval '25 minutes');
  v_r := public.parceiro_detectar_pdf(c_t);
  if (v_r ->> 'ok')::boolean is not true then
    raise exception '1a: a detecção falhou (%)', v_r;
  end if;
  for v_i in 1 .. cardinality(c_arquivos) loop
    select * into v_e from public.parceiro_envios_a_mao e where e.whatsapp_message_id = v_msgs[v_i];
    if not found then
      raise exception '1b: % não virou linha', c_arquivos[v_i];
    end if;
    if v_e.numero_doc is distinct from c_numeros[v_i] or v_e.service_order_id is distinct from v_ordens[v_i]
       or v_e.parceiro_id is distinct from v_p or v_e.situacao is distinct from 'so_registro'
       or v_e.enviado_em is distinct from c_t - make_interval(mins => c_minutos[v_i]) then
      raise exception '1c: % gravou % (ordem %, situação %), esperava %', c_arquivos[v_i], v_e.numero_doc, v_e.service_order_id,
        v_e.situacao, c_numeros[v_i];
    end if;
  end loop;
  -- Sem hífen: sem número, como antes.
  if exists (select 1 from public.parceiro_envios_a_mao e where e.whatsapp_message_id = v_sem_hifen) then
    raise exception '1d: ORC99161.pdf (sem hífen) virou linha';
  end if;
  v_sem_numero := coalesce((v_r ->> 'sem_numero')::integer, -1);
  if v_sem_numero < 1 then
    raise exception '1e: o sem hífen não foi contado em sem_numero (%)', v_r;
  end if;
  -- Só o número: nenhum nome de arquivo nas linhas da F4.
  if exists (select 1 from public.parceiro_envios_a_mao e where e.parceiro_id = v_p and row_to_json(e)::text ~* '(ana|orcamento|\.pdf|orç)') then
    raise exception '1f: o nome do arquivo foi gravado';
  end if;

  -- ── 2. O corpo no ar é o regenerado, e os grants não mudaram ──
  if (select p.prosrc ~ 'or\[cç\]\|os' from pg_proc p where p.oid = 'public.parceiro_detectar_pdf(timestamptz)'::regprocedure) is not true then
    raise exception '2a: parceiro_detectar_pdf não é a regenerada pela F5';
  end if;
  if has_function_privilege('anon', 'public.parceiro_detectar_pdf(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.parceiro_detectar_pdf(timestamptz)', 'execute')
     or not has_function_privilege('service_role', 'public.parceiro_detectar_pdf(timestamptz)', 'execute') then
    raise exception '2b: grants de parceiro_detectar_pdf mudaram';
  end if;
  if (select obj_description('public.parceiro_detectar_pdf(timestamptz)'::regprocedure, 'pg_proc') ~ 'ORC-, ORÇ- ou OS-') is not true then
    raise exception '2c: o comment de parceiro_detectar_pdf não diz ORÇ-';
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_pdf_mao_f4', true, '{}');
end
$pdf$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
