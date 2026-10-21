-- Secretário, Passo 4, P4.5 (20/10/2026): a voz única LIGADA de verdade. Com voz_unica = 'ligado' (e a manhã nova e o
-- fechamento ligado no ar), o acorde que o portão libera sai pela fila com a chave dedupe_key = 'aviso:<id do aviso>'
-- (linhaDoAcordeNaFila, supabase/functions/_shared/uma-voz/registrar.ts). Se a fila DESISTIR (WhatsApp fora até as 20h —
-- de 16 a 20/10/2026 ele ficou fora quatro dias), o aviso ficava 'acordou' para sempre: o dono nunca o viu e nenhuma
-- mensagem fixa o levava. "Nunca se perde" valia só para o guardado incluído numa mensagem fixa (fila_id).
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md §3.4 passo 5, §3.5 e §6.3 (marcas "(20/10)").
--
-- Muda UMA coisa em avisos_para_a_mensagem: antes de devolver, além de conferir os incluídos (entregue / volta a
-- guardado), confere os ACORDES dos últimos 7 dias cuja linha da fila 'aviso:<id>' terminou 'failed' ou 'cancelled':
-- voltam a 'guardado' (motivo envio_falhou, sem cartão, reaberto + 1), para ESTA mensagem (entregar_a_partir_de = agora),
-- e saem nela. A resposta ganha 'acordes_voltaram'. O resto do corpo é o de 20261016101000, byte a byte.
-- Acorde que saiu por outro caminho (o turno do assistente, o envio direto do lead do site, o cartão com PIN): quem
-- enviou chama aviso_reabrir na hora se falhou; sem linha 'aviso:<id>' na fila nada muda aqui.
--
-- Sem dado gravado, sem cron, sem chave nova (a chave voz_unica = 'ligado' é um UPDATE à parte, com o OK do dono).
-- Recria a função SÓ se o corpo em produção for o de 20261016101000 (md5 do prosrc normalizado — A-Z em minúscula, sem
-- espaços — e776a16b7f758f507447c8435ea7b070, conferido por SELECT em 20/10/2026) ou já este (2b92a612d8436937ada51642afa3156d, 2ª aplicação); qualquer
-- outro corpo, ou a função ausente, PARA a migration sem mudar nada. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 0. A guarda do corpo, ANTES de recriar.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_md5 text;
begin
  select md5(regexp_replace(translate(p.prosrc, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\s+', '', 'g'))
    into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'avisos_para_a_mensagem';
  if v_md5 is null or v_md5 not in ('e776a16b7f758f507447c8435ea7b070', '2b92a612d8436937ada51642afa3156d') then
    raise exception 'avisos_para_a_mensagem não é a de 20261016101000 (md5 %): confira o corpo em produção antes de recriar', coalesce(v_md5, 'ausente');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. avisos_para_a_mensagem: + o acorde que a fila não entregou volta a guardado e vai nesta mensagem
--    p = {phone, modo, mensagem ('manha'|'fechamento'), agora?}
-- ---------------------------------------------------------------------------------------------
create or replace function public.avisos_para_a_mensagem(p jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_phone    text := p->>'phone';
  v_modo     text := coalesce(nullif(p->>'modo', ''), 'sombra');
  v_mensagem text := p->>'mensagem';
  v_agora    timestamptz;
  v_entregues integer := 0;
  v_voltaram integer := 0;
  v_acordes_voltaram integer := 0;
  v_avisos   jsonb;
begin
  begin
    v_agora := coalesce(nullif(p->>'agora', '')::timestamptz, now());
  exception when others then
    return jsonb_build_object('ok', false, 'erro', 'agora inválido');
  end;
  if v_phone is null or v_mensagem is null or v_mensagem not in ('manha', 'fechamento') or v_modo not in ('sombra', 'ligado') then
    return jsonb_build_object('ok', false, 'erro', 'faltam phone ou mensagem (manha|fechamento)');
  end if;

  -- o que foi incluído numa mensagem que JÁ saiu: entregue
  update public.avisos_do_dono a
     set situacao = 'entregue', entregue_em = coalesce(f.sent_at, now()), atualizado_em = now()
    from public.whatsapp_send_queue f
   where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'incluido'
     and f.id = a.fila_id and f.status = 'sent';
  get diagnostics v_entregues = row_count;
  -- o que foi incluído numa mensagem que NÃO saiu (falhou, cancelada, sumiu da fila): volta a guardado
  update public.avisos_do_dono a
     set situacao = 'guardado', fila_id = null, incluido_em = null, reaberto = least(a.reaberto + 1, 50),
         motivo = 'mensagem_nao_saiu', atualizado_em = now()
   where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'incluido' and a.fila_id is not null
     and not exists (select 1 from public.whatsapp_send_queue f
                      where f.id = a.fila_id and f.status in ('pending', 'sending', 'sent'));
  get diagnostics v_voltaram = row_count;
  -- (20/10/2026, P4.5) o ACORDE que entrou na fila (chave 'aviso:<id>') e a fila desistiu: volta a guardado, para esta
  -- mensagem. 'pending'/'sending' espera (o WhatsApp ainda pode voltar antes das 20h); 'sent' fica como acordou.
  update public.avisos_do_dono a
     set situacao = 'guardado', motivo = 'envio_falhou', cartao = false, mensagem = v_mensagem,
         entregar_a_partir_de = v_agora, reaberto = least(a.reaberto + 1, 50), atualizado_em = now()
   where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'acordou'
     and a.registrado_em >= v_agora - interval '7 days'
     and exists (select 1 from public.whatsapp_send_queue f
                  where f.dedupe_key = 'aviso:' || a.id::text and f.status in ('failed', 'cancelled'));
  get diagnostics v_acordes_voltaram = row_count;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'fonte', a.fonte, 'assunto', a.assunto, 'destino', a.destino, 'motivo', a.motivo,
           'texto', a.texto, 'dados', a.dados, 'registrado_em', a.registrado_em, 'dia', a.dia,
           'mensagem', a.mensagem, 'reaberto', a.reaberto) order by a.registrado_em, a.id), '[]'::jsonb)
    into v_avisos
    from (select * from public.avisos_do_dono a
           where a.phone_normalized = v_phone and a.modo = v_modo and a.situacao = 'guardado'
             and a.entregar_a_partir_de <= v_agora
             and (a.destino in ('acorde', 'proxima_fixa')
                  or (a.destino = 'hoje' and v_mensagem = 'manha')
                  or (a.destino = 'escritorio' and v_mensagem = 'fechamento'))
           order by a.registrado_em, a.id
           limit 50) a;

  return jsonb_build_object('ok', true, 'avisos', v_avisos, 'entregues', v_entregues, 'voltaram', v_voltaram,
                            'acordes_voltaram', v_acordes_voltaram);
end $$;

comment on function public.avisos_para_a_mensagem(jsonb) is
  'Secretário (uma voz só): os avisos guardados que a mensagem fixa (manha|fechamento) deve levar agora. Antes, confere os já incluídos (fila sent = entregue; fila que não saiu = volta a guardado) e (20/10/2026) os acordes cuja fila aviso:<id> desistiu (voltam a guardado e vão nesta mensagem). Só service_role.';

revoke all on function public.avisos_para_a_mensagem(jsonb) from public, anon, authenticated;
grant execute on function public.avisos_para_a_mensagem(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se a porta ficou aberta ou se o corpo não é o esperado.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text := 'public.avisos_para_a_mensagem(jsonb)';
  v_def text;
begin
  if has_function_privilege('anon', v_f, 'execute') then
    raise exception 'avisos_para_a_mensagem exposta para anon';
  end if;
  if has_function_privilege('authenticated', v_f, 'execute') then
    raise exception 'avisos_para_a_mensagem exposta para authenticated';
  end if;
  if not has_function_privilege('service_role', v_f, 'execute') then
    raise exception 'a edge (service_role) não alcança avisos_para_a_mensagem';
  end if;
  v_def := pg_get_functiondef(v_f::regprocedure);
  if position('''aviso:'' || a.id::text' in v_def) = 0 then
    raise exception 'avisos_para_a_mensagem sem a conferência do acorde que não saiu';
  end if;
  if position('security definer' in lower(v_def)) > 0 or position('search_path to ''''' in lower(v_def)) = 0 then
    raise exception 'avisos_para_a_mensagem precisa ser security invoker com search_path vazio';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261020200000', 'avisos_acorde_que_nao_saiu')
on conflict do nothing;
