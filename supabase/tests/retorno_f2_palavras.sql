-- Retorno F2 (P4): retorno_dito, uma linha por palavra, com relógio fixo em ter 10/11/2026 10:00 (antes de qualquer caso real).
-- Roda só pela bancada. Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000092xx; nomes inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.retorno_f2_pal_caso(p_fone text, p_papel text, p_aberta timestamptz, p_client uuid default null)
returns uuid
language plpgsql as $f$
declare
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', 'preciso falar com o Gustavo sobre a lancha', 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_client, v_msg, v_msg,
          p_aberta, p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
  values (v_msg, v_id, public._agenda_chave_telefone(p_fone), p_aberta, p_aberta, 'x', true);
  return v_id;
end $f$;

create or replace function pg_temp.retorno_f2_pal_os(p_num text, p_cliente uuid, p_barco uuid, p_status text)
returns uuid
language sql as $f$
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at,
                                     converted_to_os_at, grand_total)
  values (p_num, p_cliente, p_barco, p_status, 'approved', 'repair', timestamptz '2026-10-28 12:00-03', timestamptz '2026-10-28 12:00-03',
          timestamptz '2026-10-28 12:00-03', 100)
  returning id
$f$;

do $palavras$
declare
  c_agora constant timestamptz := '2026-11-10 10:00:00-03';   -- terça
  c_outro constant uuid := 'b1600000-0000-4000-8000-0000000009f2';
  v_dono uuid;
  v_r jsonb;
  v_t text;
  v_cfg public.retorno_config;
  v_tinha_segurou boolean;
  v_cl uuid; v_cl2 uuid; v_cl3 uuid;
  v_barco uuid;
  v_os uuid; v_os2 uuid; v_os3 uuid; v_os4 uuid;
  v_caso uuid; v_caso2 uuid;
  v_saida uuid;
  v_n integer;
  v_audit integer;
begin
  begin
    select d.id into v_dono from public._comprovante_dono() d;
    if v_dono is null then
      raise exception '0: sem dono cadastrado';
    end if;
    update public.retorno_config
       set modo = 'sombra', tipos_ligados = '{}', segura_recibos = false, segura_tudo_ate = null, fora_ate = null, pessoal_ultimo = null;
    select count(*) into v_audit from public.audit_log a where a.table_name = 'retorno_config';

    -- Autor que não é o dono.
    v_r := public.retorno_dito('{"comando": "segura", "alvo": "tudo"}', c_outro, c_agora);
    if v_r is distinct from '{"ok": false, "motivo": "nao_e_o_dono"}'::jsonb then
      raise exception '1a: outro autor passou (%)', v_r;
    end if;
    if (select c.segura_tudo_ate from public.retorno_config c) is not null then
      raise exception '1b: outro autor gravou';
    end if;
    v_r := public.retorno_dito('{"comando": "xyz"}', v_dono, c_agora);
    if not coalesce((v_r ->> 'seguir_ao_modelo')::boolean, false) then
      raise exception '1c: comando desconhecido não seguiu ao modelo (%)', v_r;
    end if;

    -- segura e solta recibos.
    v_r := public.retorno_dito('{"comando": "segura", "alvo": "recibos"}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Segurei os recibos: quem escrever agora não recebe recibo, saudação nem coleta, nem depois que você soltar. *solta recibos* vale para as próximas mensagens.' then
      raise exception '2a: R01 (%)', v_r;
    end if;
    if not (select c.segura_recibos from public.retorno_config c) then
      raise exception '2b: segura_recibos não gravou';
    end if;
    v_r := public.retorno_dito('{"comando": "solta", "alvo": "recibos"}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Recibos soltos: valem para as próximas mensagens.' or (select c.segura_recibos from public.retorno_config c) then
      raise exception '2c: R02 (%)', v_r;
    end if;

    -- segura tudo, com e sem a função da agenda.
    v_tinha_segurou := exists (select 1 from pg_proc p where p.proname = '_agenda_retorno_segurou');
    v_r := public.retorno_dito('{"comando": "segura", "alvo": "tudo"}', v_dono, c_agora);
    v_t := 'Segurei tudo por 24 h, até amanhã às 10:00: nada automático do retorno sai ao cliente. *solta tudo* volta antes.';
    if not v_tinha_segurou then
      v_t := v_t || ' A agenda ainda manda o que já estava aprovado: *segura cliente* segura.';
    end if;
    if v_r ->> 'texto' is distinct from v_t then
      raise exception '3a: R03 (%)', v_r;
    end if;
    if (select c.segura_tudo_ate from public.retorno_config c) is distinct from c_agora + interval '24 hours' then
      raise exception '3b: segura_tudo_ate errado';
    end if;
    if (public.canal_pode_enviar('5547900009201', 'resposta_imediata', 'retorno_recibo', c_agora) ->> 'motivo') is distinct from 'segura_tudo' then
      raise exception '3c: o canal não viu o segura tudo';
    end if;
    if not v_tinha_segurou then
      create function public._agenda_retorno_segurou(p_agora timestamptz) returns boolean language sql as 'select false';
      v_r := public.retorno_dito('{"comando": "segura", "alvo": "tudo"}', v_dono, c_agora);
      if v_r ->> 'texto' like '%segura cliente%' then
        raise exception '3d: R03a não sumiu com a função da agenda no ar';
      end if;
      drop function public._agenda_retorno_segurou(timestamptz);
    end if;

    -- solta tudo: sem nada no meio, e com uma saída segurada.
    v_r := public.retorno_dito('{"comando": "solta", "alvo": "tudo"}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Soltei: o automático volta a sair.' then
      raise exception '4a: R04 sem nada no meio (%)', v_r;
    end if;
    select c.* into v_cfg from public.retorno_config c;
    if v_cfg.segura_tudo_ate is not null or v_cfg.segura_recibos then
      raise exception '4b: solta tudo não limpou';
    end if;
    v_cl := (select id from (insert into public.clients (type, name, whatsapp) values ('individual', 'Zebedeu Liberato Teste', '(47) 90000-9201') returning id) x);
    v_caso := pg_temp.retorno_f2_pal_caso('5547900009201', 'cliente', c_agora - interval '1 hour', v_cl);
    insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, enviar_em, dados, dedupe_key)
    values (v_caso, 'recibo_cliente', public._agenda_chave_telefone('5547900009201'), '5547900009201', 'sombra', c_agora + interval '20 hours',
            '{"segurada": true}', 'teste-f2-pal:segurada')
    returning id into v_saida;
    v_r := public.retorno_dito('{"comando": "solta", "alvo": "tudo"}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Soltei: o automático volta a sair. 1 que ficaram no meio saem agora; quem escreveu há mais de 12 h fica com você.' then
      raise exception '4c: R04 com 1 no meio (%)', v_r;
    end if;
    if (select s.enviar_em from public.retorno_saidas s where s.id = v_saida) is distinct from c_agora then
      raise exception '4d: a saída segurada não voltou para agora';
    end if;

    -- fora até.
    v_r := public.retorno_dito('{"comando": "fora_ate", "dia": "quarta"}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Anotado: até amanhã o recibo diz que você está fora e que responde amanhã até as 10h. *fora até hoje* desfaz.' then
      raise exception '5a: R05 (%)', v_r;
    end if;
    if (select c.fora_ate from public.retorno_config c) is distinct from date '2026-11-11' then
      raise exception '5b: fora_ate errado';
    end if;
    if (public._retorno_prazo(c_agora, public._agenda_chave_telefone('5547900009299')) ->> 'faixa') is distinct from 'fora_ate' then
      raise exception '5c: _retorno_prazo não deu a faixa fora_ate';
    end if;
    v_r := public.retorno_dito('{"comando": "fora_ate", "dia": "sexta"}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Anotado: até sexta (13/11)%' then
      raise exception '5d: outro dia (%)', v_r;
    end if;
    v_r := public.retorno_dito('{"comando": "fora_ate", "dia": "hoje"}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Anotado: você voltou, e o recibo volta ao normal.' or (select c.fora_ate from public.retorno_config c) is not null then
      raise exception '5e: R06 (%)', v_r;
    end if;
    foreach v_t in array array['ontem', 'xyz'] loop
      v_r := public.retorno_dito(jsonb_build_object('comando', 'fora_ate', 'dia', v_t), v_dono, c_agora);
      if v_r ->> 'texto' is distinct from 'Não entendi o dia. Diga *fora até quarta* ou *fora até 25/11*.' then
        raise exception '5f: R07 com % (%)', v_t, v_r;
      end if;
    end loop;

    -- O audit_log das mudanças de configuração.
    select count(*) into v_n from public.audit_log a
     where a.table_name = 'retorno_config' and a.record_id = v_dono and a.changed_by = 'dono';
    if v_n - v_audit < 8 then
      raise exception '6: % linhas de audit_log, esperava ao menos 8', v_n - v_audit;
    end if;

    -- libera.
    insert into public.vessels (client_id, name, asset_type) values (v_cl, 'Brisaleve', 'Lancha') returning id into v_barco;
    v_os := pg_temp.retorno_f2_pal_os('OS-09201', v_cl, v_barco, 'in_progress');
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "zebedeu", "desfaz": false}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Liberei a retirada: Zebedeu (OS-09201). Vale por 14 dias. *libera zebedeu não* desfaz.' then
      raise exception '7a: R08 (%)', v_r;
    end if;
    if (select so.liberado_retirada_em from public.service_orders so where so.id = v_os) is distinct from c_agora
       or (select so.liberado_retirada_por from public.service_orders so where so.id = v_os) is distinct from v_dono then
      raise exception '7b: a marca não gravou';
    end if;
    if not exists (select 1 from public.audit_log a where a.table_name = 'service_orders' and a.record_id = v_os and a.changed_by = 'dono') then
      raise exception '7c: libera sem audit_log';
    end if;
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "zebedeu", "desfaz": true}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Retirada não liberada: Zebedeu (OS-09201).' then
      raise exception '7d: R09 (%)', v_r;
    end if;
    if (select so.liberado_retirada_em from public.service_orders so where so.id = v_os) is not null
       or (select so.liberado_retirada_por from public.service_orders so where so.id = v_os) is not null then
      raise exception '7e: desfaz não zerou';
    end if;
    -- só prefixo: pergunta e nada grava
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "zeb", "desfaz": false}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Você quis dizer Zebedeu (OS-09201)? Mande *libera OS-09201*.' then
      raise exception '7f: R08b (%)', v_r;
    end if;
    if (select so.liberado_retirada_em from public.service_orders so where so.id = v_os) is not null then
      raise exception '7g: prefixo gravou';
    end if;
    -- pelo número e pelo barco
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "os-09201", "desfaz": false}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Liberei a retirada: Zebedeu (OS-09201).%' then
      raise exception '7h: por número (%)', v_r;
    end if;
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "brisaleve", "desfaz": false}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Liberei a retirada: Zebedeu (OS-09201).%' then
      raise exception '7i: pelo barco (%)', v_r;
    end if;
    -- 2 clientes com o mesmo nome: ambíguo, nada gravado
    insert into public.clients (type, name) values ('individual', 'Zacarias Duplo Um') returning id into v_cl2;
    insert into public.clients (type, name) values ('individual', 'Zacarias Duplo Dois') returning id into v_cl3;
    v_os2 := pg_temp.retorno_f2_pal_os('OS-09202', v_cl2, null, 'in_progress');
    v_os3 := pg_temp.retorno_f2_pal_os('OS-09203', v_cl3, null, 'in_progress');
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "zacarias", "desfaz": false}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Qual %' then
      raise exception '7j: ambíguo (%)', v_r;
    end if;
    if exists (select 1 from public.service_orders so where so.id in (v_os2, v_os3) and so.liberado_retirada_em is not null) then
      raise exception '7k: ambíguo gravou';
    end if;
    -- OS faturada grava; cancelada recusa; alvo que não existe segue ao modelo
    update public.service_orders set status = 'invoiced' where id = v_os2;
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "os-09202", "desfaz": false}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Liberei a retirada:%' or (select so.liberado_retirada_em from public.service_orders so where so.id = v_os2) is null then
      raise exception '7l: OS faturada não gravou (%)', v_r;
    end if;
    update public.service_orders set status = 'cancelled' where id = v_os3;
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "os-09203", "desfaz": false}', v_dono, c_agora);
    if v_r ->> 'texto' like 'Liberei%' or (select so.liberado_retirada_em from public.service_orders so where so.id = v_os3) is not null then
      raise exception '7m: OS cancelada gravou (%)', v_r;
    end if;
    v_r := public.retorno_dito('{"comando": "libera", "alvo": "ninguemassim", "desfaz": false}', v_dono, c_agora);
    if not coalesce((v_r ->> 'seguir_ao_modelo')::boolean, false) then
      raise exception '7n: alvo inexistente não seguiu ao modelo (%)', v_r;
    end if;

    -- pessoal: sem lista, com vários e com um.
    v_r := public.retorno_dito('{"comando": "pessoal", "n": null}', v_dono, c_agora);
    if not coalesce((v_r ->> 'seguir_ao_modelo')::boolean, false) then
      raise exception '8a: pessoal sem lista (%)', v_r;
    end if;
    v_caso2 := pg_temp.retorno_f2_pal_caso('5547900009202', 'numero_novo', c_agora - interval '30 minutes');
    v_r := public.retorno_dito('{"comando": "retorno"}', v_dono, c_agora);
    if v_r ->> 'cartao_id' is null then
      raise exception '8b: retorno não abriu a lista (%)', v_r;
    end if;
    v_r := public.retorno_dito('{"comando": "pessoal", "n": null}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Qual? *pessoal 2*.' then
      raise exception '8c: pessoal com 2 casos (%)', v_r;
    end if;
    update public.retorno_saidas set enviar_em = c_agora + interval '1 hour', dados = '{}' where id = v_saida;
    v_r := public.retorno_dito('{"comando": "pessoal", "n": 1}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Zebedeu: anotado como pessoal. Esse número nunca mais recebe automático, e cancelei o que estava agendado. *pessoal não* desfaz.' then
      raise exception '8d: R11 (%)', v_r;
    end if;
    if not exists (select 1 from public.whatsapp_leads l where l.phone_normalized = '5547900009201' and l.status = 'discarded' and l.lead_tipo = 'pessoal') then
      raise exception '8e: não criou o lead discarded/pessoal';
    end if;
    if (public.canal_pode_enviar('5547900009201', 'resposta_imediata', 'retorno_recibo', c_agora) ->> 'motivo') is distinct from 'pessoal' then
      raise exception '8f: canal não viu o pessoal';
    end if;
    if not exists (select 1 from public.retorno_saidas s where s.id = v_saida and s.estado = 'cancelada' and s.motivo = 'pessoal') then
      raise exception '8g: a saída agendada não cancelou';
    end if;
    if not exists (select 1 from public.retorno_aberturas a where a.id = v_caso and a.estado = 'fechada' and a.fechada_motivo = 'nada') then
      raise exception '8h: o caso não fechou';
    end if;
    if not exists (select 1 from public.retorno_toques t where t.abertura_id = v_caso and t.palavra = 'pessoal') then
      raise exception '8i: sem toque';
    end if;
    -- pessoal sem número, agora com um caso só; lead já existente mantém o que era
    insert into public.whatsapp_leads (phone_normalized, status) values ('5547900009202', 'pending');
    v_r := public.retorno_dito('{"comando": "pessoal", "n": null}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'número novo: anotado como pessoal.%' then
      raise exception '8j: pessoal de um caso só (%)', v_r;
    end if;
    if not exists (select 1 from public.whatsapp_leads l where l.phone_normalized = '5547900009202' and l.status = 'pending' and l.lead_tipo = 'pessoal') then
      raise exception '8k: mudou o status do lead que já existia';
    end if;
    -- a volta
    v_r := public.retorno_dito('{"comando": "pessoal_desfaz"}', v_dono, c_agora + interval '25 hours');
    if v_r ->> 'texto' is distinct from 'Não há *pessoal* recente para desfazer.' then
      raise exception '8l: desfez depois de 24 h (%)', v_r;
    end if;
    v_r := public.retorno_dito('{"comando": "pessoal_desfaz"}', v_dono, c_agora + interval '23 hours');
    if v_r ->> 'texto' is distinct from 'Pronto: esse número volta a receber automático.' then
      raise exception '8m: R12 (%)', v_r;
    end if;
    if exists (select 1 from public.whatsapp_leads l where l.phone_normalized = '5547900009202' and l.lead_tipo is not null) then
      raise exception '8n: lead_tipo não voltou';
    end if;
    if (public.canal_pode_enviar('5547900009202', 'resposta_imediata', 'retorno_recibo', c_agora + interval '1 hour') ->> 'motivo') = 'pessoal' then
      raise exception '8o: canal seguiu vendo o pessoal';
    end if;

    -- errado sem letra.
    v_r := public.retorno_dito('{"comando": "errado", "letra": "Z"}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Não achei a letra Z no último "Mandei sozinho".' then
      raise exception '9: letra inexistente (%)', v_r;
    end if;

    -- O historico nunca leva texto do cliente.
    v_r := public.retorno_dito('{"comando": "segura", "alvo": "recibos"}', v_dono, c_agora);
    if v_r -> 'historico' ->> 'user' is distinct from 'segura recibos' or v_r -> 'historico' ->> 'assistant' is null then
      raise exception '10: historico (%)', v_r;
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_palavras', true, '{}');
end
$palavras$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
