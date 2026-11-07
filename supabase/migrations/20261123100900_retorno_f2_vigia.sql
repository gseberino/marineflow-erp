-- Retorno rápido ao cliente, F2 (P13): o vigia do cartão, a promoção dos tipos, o rebaixamento, as medidas e o cron.
--
-- retorno_vigia_cartao roda depois do retorno_vigia, a cada minuto. Cada passo no seu próprio bloco: um que falhe não derruba os
-- outros. Sem cartão vivo e sem tipo em 'sozinho', são poucas leituras por minuto. A remontagem do item, que é cara, só roda no
-- *sim* (_retorno_item_conferir).
--
-- A queda é em silêncio: é o "o cartão some". Se o dono responder depois, *sim <PIN>* recebe "já tinha sido decidido", e
-- *só 3 sim <PIN>* recebe R13.
--
-- Promoção: 3 dias com *sim <PIN>* enviados, depois sozinho, no dia seguinte. Não pede outro OK: é o combinado, e o dono já aprovou 3
-- vezes. Rebaixar é um toque (*errado*). "Mais de 20% de edição nos últimos 10" fica na promoção, porque tipo em sozinho não passa
-- mais pelo cartão.
--
-- As medidas saem da view retorno_f2_medidas, por semana. Cron: retorno_vigia primeiro, para o vigia do cartão ver o que o relógio
-- acabou de criar.
--
-- Reverter: restaurar o cron da 20261116101100; update public.retorno_modelo_tipos set nivel = 'desligado'.

create or replace function public._retorno_rebaixar(p_tipo text, p_motivo text, p_agora timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.retorno_modelo_tipos t
     set nivel = 'cartao', aprovados_dias = '{}', aprovados_usos = 0, rebaixado_em = p_agora, rebaixado_motivo = p_motivo, atualizado_em = now()
   where t.tipo = p_tipo and t.nivel = 'sozinho';
  return found;
end;
$$;

comment on function public._retorno_rebaixar(text, text, timestamptz) is
  'Retorno F2 (P13.4): o tipo em sozinho volta a cartao e perde as aprovações. Motivos: errado, queixa, opt_out, validador.';

revoke all on function public._retorno_rebaixar(text, text, timestamptz) from public, anon, authenticated;

-- Fecha o cartão que perdeu tudo ou venceu: pendência, ponteiro (só se for o dele) e pergunta.
create or replace function public._retorno_cartao_encerrar(p_cartao uuid, p_estado text, p_status_pendencia text, p_motivo text, p_agora timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c public.retorno_cartoes;
begin
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao;
  update public.retorno_cartoes c set estado = p_estado, caiu_motivo = p_motivo where c.id = p_cartao;
  update public.retorno_cartao_itens i set estado = 'fora' where i.cartao_id = p_cartao and i.estado = 'vivo';
  if v_c.pendencia_id is not null then
    update public.ai_operator_pending_actions p
       set status = p_status_pendencia, rejected_at = case when p_status_pendencia = 'rejected' then p_agora else p.rejected_at end
     where p.id = v_c.pendencia_id and p.status = 'pending';
    update public.ai_operator_sessions s
       set metadata = s.metadata - 'pending_confirm_action_id'
     where s.id = v_c.sessao_id and s.metadata ->> 'pending_confirm_action_id' = v_c.pendencia_id::text;
  end if;
  if v_c.pergunta_id is not null then
    perform public._pergunta_fechar(v_c.pergunta_id, 'cancelada', p_motivo, null);
  end if;
end;
$$;

revoke all on function public._retorno_cartao_encerrar(uuid, text, text, text, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_vigia_log(p_passo text, p_sqlstate text)
returns void
language sql
security definer
set search_path = public
as $$
  select public._retorno_log('vigia_cartao', 'retorno_vigia_cartao: passo ' || p_passo || ' falhou (' || p_sqlstate || ')', 'error',
                             jsonb_build_object('passo', p_passo, 'sqlstate', p_sqlstate));
$$;

revoke all on function public._retorno_vigia_log(text, text) from public, anon, authenticated;

create or replace function public.retorno_vigia_cartao(p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_cartao uuid;
  r record;
  v_conf jsonb;
  v_caidos integer := 0;
  v_promovidos integer := 0;
  v_rebaixados integer := 0;
  v_avisos integer := 0;
  v_dono uuid;
  v_phone text;
  v_motivo text;
  v_rotulo text;
  v_edit integer;
  v_tot integer;
begin
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('rodou', false);
  end if;
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;

  -- 1 e 2. Queda e validade.
  begin
    v_vivo := public.retorno_cartao_vivo(v_agora);
    if v_vivo ->> 'estado' = 'vivo' then
      v_cartao := (v_vivo ->> 'id')::uuid;
      if (select c.expira_em from public.retorno_cartoes c where c.id = v_cartao) < v_agora then
        perform public._retorno_cartao_encerrar(v_cartao, 'expirou', 'expired', 'cartao_expirou', v_agora);
      else
        for r in select i.id from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' loop
          v_conf := public._retorno_item_conferir(r.id, v_agora, false);
          if not (v_conf ->> 'ok')::boolean then
            update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = v_conf ->> 'motivo', decidido_em = v_agora where i.id = r.id;
            v_caidos := v_caidos + 1;
          end if;
        end loop;
        if not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo') then
          perform public._retorno_cartao_encerrar(v_cartao, 'caiu', 'rejected', 'cartao_caiu', v_agora);
        elsif v_caidos > 0 then
          update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_cartao;
        end if;
      end if;
    end if;
  exception when others then
    perform public._retorno_vigia_log('queda', sqlstate);
  end;

  -- 3. Amarração: sem cartão vivo, a sessão do dono solta o caso.
  begin
    if not exists (select 1 from public.retorno_cartoes c where c.estado = 'vivo') then
      update public.ai_operator_sessions s
         set client_id = null, vessel_id = null, service_order_id = null, metadata = s.metadata - 'retorno_amarrada'
       where s.channel = 'whatsapp' and s.external_thread_key = v_phone and s.status = 'open' and s.metadata ? 'retorno_amarrada';
    end if;
  exception when others then
    perform public._retorno_vigia_log('amarracao', sqlstate);
  end;

  -- 4. Promoção.
  begin
    for r in select t.* from public.retorno_modelo_tipos t where t.nivel = 'cartao' loop
      continue when r.promocao_suspensa_ate is not null and r.promocao_suspensa_ate > v_agora;
      if r.regua = 'dias' then
        continue when cardinality(r.aprovados_dias) < v_cfg.modelo_dias_aprovacao;
        continue when v_hoje <= (select max(d) from unnest(r.aprovados_dias) d);
      else
        continue when r.aprovados_usos < v_cfg.modelo_usos_liberado;
      end if;
      -- sem queixa nem pedido de parar desde a 1ª aprovação do período
      continue when exists (
        select 1
          from public.retorno_saidas s
          join public.retorno_mensagens m on m.chave = s.chave and m.recebida_em > s.decidida_em
                                         and m.recebida_em <= s.decidida_em + interval '24 hours'
         where s.tipo = r.tipo and s.estado = 'enviada' and s.decidida_em <= v_agora
           and coalesce((m.sinais ->> 'reclamacao')::boolean, false));
      continue when exists (
        select 1
          from public.retorno_saidas s
          join public.whatsapp_blocked_numbers b on public._agenda_chave_telefone(b.phone_normalized) = s.chave
         where s.tipo = r.tipo and s.estado = 'enviada' and b.tipo = 'opt_out'
           and b.created_at > s.decidida_em and b.created_at <= s.decidida_em + interval '48 hours');
      -- nos últimos 10 itens do tipo, editados até rebaixa_edicao_pct
      select count(*), count(*) filter (where x.texto_ditado is not null) into v_tot, v_edit
        from (select i.texto_ditado
                from public.retorno_cartao_itens i
                join public.retorno_cartoes c on c.id = i.cartao_id
               where i.modelo_tipo = r.tipo and i.estado in ('feito', 'fora')
               order by c.criado_em desc
               limit 10) x;
      continue when v_tot > 0 and v_edit::numeric / v_tot > v_cfg.rebaixa_edicao_pct;

      update public.retorno_modelo_tipos t
         set nivel = 'sozinho', promovido_em = v_agora, atualizado_em = now()
       where t.tipo = r.tipo;
      v_promovidos := v_promovidos + 1;
    end loop;
  exception when others then
    perform public._retorno_vigia_log('promocao', sqlstate);
  end;

  -- 5. Fadiga: as últimas fadiga_vezes aprovações, todas rápidas, nas últimas 24 h.
  begin
    if (select count(*) from (select t.rapido from public.retorno_toques t
                               where t.palavra = 'sim_pin' and t.em > v_agora - interval '24 hours' and t.em <= v_agora
                               order by t.em desc limit v_cfg.fadiga_vezes) x where x.rapido) >= v_cfg.fadiga_vezes then
      update public.retorno_modelo_tipos t
         set promocao_suspensa_ate = v_agora + v_cfg.fadiga_suspende, atualizado_em = now()
       where (t.promocao_suspensa_ate is null or t.promocao_suspensa_ate <= v_agora)
         and t.tipo in (select i.modelo_tipo
                          from public.retorno_toques q
                          join public.retorno_cartao_itens i on i.cartao_id = q.cartao_id
                         where q.palavra = 'sim_pin' and q.rapido and q.em > v_agora - interval '24 hours' and q.em <= v_agora
                           and i.modelo_tipo is not null);
    end if;
  exception when others then
    perform public._retorno_vigia_log('fadiga', sqlstate);
  end;

  -- 6. Rebaixamento: queixa até 24 h depois, opt-out até 48 h, ou 3 recusas do validador na última hora.
  begin
    for r in select t.tipo, t.promovido_em from public.retorno_modelo_tipos t where t.nivel = 'sozinho' loop
      v_motivo := null;
      if exists (select 1
                   from public.retorno_saidas s
                   join public.retorno_mensagens m on m.chave = s.chave and m.recebida_em > s.decidida_em
                                                  and m.recebida_em <= s.decidida_em + interval '24 hours' and m.recebida_em <= v_agora
                  where s.tipo = r.tipo and s.estado = 'enviada' and s.decidida_em > coalesce(r.promovido_em, v_agora - interval '30 days')
                    and coalesce((m.sinais ->> 'reclamacao')::boolean, false)) then
        v_motivo := 'queixa';
      elsif exists (select 1
                      from public.retorno_saidas s
                      join public.whatsapp_blocked_numbers b on public._agenda_chave_telefone(b.phone_normalized) = s.chave
                     where s.tipo = r.tipo and s.estado = 'enviada' and b.tipo = 'opt_out'
                       and s.decidida_em > coalesce(r.promovido_em, v_agora - interval '30 days')
                       and b.created_at > s.decidida_em and b.created_at <= s.decidida_em + interval '48 hours' and b.created_at <= v_agora) then
        v_motivo := 'opt_out';
      elsif (select count(*) from public.retorno_saidas s
              where s.tipo = r.tipo and s.estado = 'recusada' and s.motivo = 'validador'
                and s.decidida_em > v_agora - interval '1 hour' and s.decidida_em <= v_agora) >= 3 then
        v_motivo := 'validador';
      end if;
      if v_motivo is not null and public._retorno_rebaixar(r.tipo, v_motivo, v_agora) then
        v_rebaixados := v_rebaixados + 1;
      end if;
    end loop;
  exception when others then
    perform public._retorno_vigia_log('rebaixamento', sqlstate);
  end;

  -- 7. Saída aprovada que foi recusada: o dono vê na mensagem fixa seguinte, sem gastar acorde e sem texto do cliente.
  begin
    for r in
      select s.id, s.abertura_id, s.phone_normalized, s.motivo
        from public.retorno_saidas s
       where s.estado = 'recusada' and coalesce((s.dados ->> 'aprovada')::boolean, false) and not s.dados ? 'avisada'
    loop
      v_rotulo := public._retorno_rotulo(r.abertura_id, v_agora);
      perform public.aviso_registrar(jsonb_build_object(
        'phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
        'chave', 'retorno:recusa:' || r.id, 'assunto', 'contato:' || r.phone_normalized, 'destino', 'proxima_fixa',
        'texto', format('Não saiu a mensagem para %s: %s. Responda pelo celular.', v_rotulo,
                        case r.motivo when 'validador' then 'o texto não passou na conferência'
                                      when 'fato_mudou' then 'o fato mudou'
                                      else 'o canal recusou' end),
        'agora', v_agora));
      update public.retorno_saidas s set dados = s.dados || '{"avisada": true}'::jsonb, atualizada_em = now() where s.id = r.id;
      v_avisos := v_avisos + 1;
    end loop;
  exception when others then
    perform public._retorno_vigia_log('recusa', sqlstate);
  end;

  return jsonb_build_object('rodou', true, 'caidos', v_caidos, 'promovidos', v_promovidos, 'rebaixados', v_rebaixados, 'avisos', v_avisos);
end;
$$;

comment on function public.retorno_vigia_cartao(timestamptz) is
  'Retorno F2 (P13): queda e validade do cartão, amarração, promoção, fadiga, rebaixamento e aviso de saída aprovada recusada. Cada passo no seu bloco; erro vai ao log e o seguinte roda.';

revoke all on function public.retorno_vigia_cartao(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_vigia_cartao(timestamptz) to service_role;

-- Horas úteis de Brasília: seg–sex, 08:00–18:00, sem feriado.
create or replace function public._retorno_horas_uteis(p_ini timestamptz, p_fim timestamptz)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(extract(epoch from least(p_fim, (d + time '18:00') at time zone 'America/Sao_Paulo')
                                         - greatest(p_ini, (d + time '08:00') at time zone 'America/Sao_Paulo')) / 3600.0)
                    filter (where least(p_fim, (d + time '18:00') at time zone 'America/Sao_Paulo')
                                  > greatest(p_ini, (d + time '08:00') at time zone 'America/Sao_Paulo')), 0)::numeric
    from generate_series((p_ini at time zone 'America/Sao_Paulo')::date, (p_fim at time zone 'America/Sao_Paulo')::date, interval '1 day') g(dia)
    cross join lateral (select g.dia::date as d) x
   where extract(isodow from x.d) <= 5 and public.agenda_feriado(x.d) is null;
$$;

comment on function public._retorno_horas_uteis(timestamptz, timestamptz) is
  'Retorno F2 (P13.5): horas úteis entre dois instantes: seg–sex, 08:00–18:00 de Brasília, sem feriado.';

revoke all on function public._retorno_horas_uteis(timestamptz, timestamptz) from public, anon, authenticated;

create or replace view public.retorno_f2_medidas with (security_invoker = on) as
with semanas as (
  select distinct date_trunc('week', c.criado_em at time zone 'America/Sao_Paulo')::date as semana from public.retorno_cartoes c
  union
  select distinct date_trunc('week', t.em at time zone 'America/Sao_Paulo')::date from public.retorno_toques t
), itens as (
  select date_trunc('week', c.criado_em at time zone 'America/Sao_Paulo')::date as semana, i.abertura_id, i.estado, c.id as cartao_id,
         c.enviado_em, c.decidido_em, a.cumprida_em
    from public.retorno_cartao_itens i
    join public.retorno_cartoes c on c.id = i.cartao_id
    join public.retorno_aberturas a on a.id = i.abertura_id
), toques as (
  select x.semana, x.abertura_id, count(t.id) filter (where t.palavra <> 'ver') as n,
         array_remove(array_agg(distinct t.palavra) filter (where t.palavra <> 'ver'), null) as palavras
    from (select distinct i.semana, i.abertura_id, i.cartao_id from itens i
           where i.cumprida_em is not null or i.estado = 'feito') x
    left join public.retorno_toques t on t.cartao_id = x.cartao_id
   group by 1, 2
)
select s.semana,
       (select count(distinct i.abertura_id) from itens i where i.semana = s.semana) as casos_cartao,
       (select count(*) from toques t where t.semana = s.semana and t.n = 1) as resolvidos_1_resposta,
       (select jsonb_build_object(
                 'sim_pin', count(*) filter (where t.n = 1 and 'sim_pin' = any (t.palavras)),
                 'letra', count(*) filter (where t.n = 1 and 'letra' = any (t.palavras)),
                 'dita', count(*) filter (where t.n = 1 and 'dita' = any (t.palavras)),
                 'dois_ou_mais', count(*) filter (where t.n >= 2))
          from toques t where t.semana = s.semana) as resolvidos_detalhe,
       (select percentile_cont(0.5) within group (order by public._retorno_horas_uteis(c.enviado_em, c.decidido_em))
          from public.retorno_cartoes c
         where c.enviado_em is not null and c.decidido_em is not null
           and date_trunc('week', c.criado_em at time zone 'America/Sao_Paulo')::date = s.semana) as decisao_mediana_h,
       (select count(*)
          from public.retorno_saidas o
          join public.retorno_aberturas a on a.id = o.abertura_id
         where o.tipo like 'modelo\_%' escape '\' and o.estado = 'enviada'
           and date_trunc('week', o.enviada_em at time zone 'America/Sao_Paulo')::date = s.semana
           and public._retorno_resposta_depois(o.abertura_id, coalesce((o.dados ->> 'aprovada_em')::timestamptz, a.aberta_em), o.enviada_em) is not null)
         as envio_depois_de_resposta,
       (select count(*)
          from public.retorno_cartoes x
          join public.retorno_cartoes y on x.id < y.id
         where x.enviado_em is not null and y.enviado_em is not null and x.estado <> 'lista' and y.estado <> 'lista'
           and x.pendencia_id is not null and y.pendencia_id is not null
           and date_trunc('week', x.criado_em at time zone 'America/Sao_Paulo')::date = s.semana
           and tstzrange(x.enviado_em, coalesce(x.decidido_em, x.expira_em)) && tstzrange(y.enviado_em, coalesce(y.decidido_em, y.expira_em)))
         as dois_cartoes,
       round((select count(*) from public.retorno_toques t
               where date_trunc('week', t.em at time zone 'America/Sao_Paulo')::date = s.semana)::numeric
             / nullif((select count(*) from generate_series(s.semana, s.semana + 6, interval '1 day') d
                        where public.agenda_dia_util(d::date)), 0), 2) as toques_dia,
       (select round(100.0 * count(*) filter (where a.cumprida_em - a.aberta_em <= interval '1 hour') / nullif(count(*), 0), 1)
          from public.retorno_aberturas a
         where a.nivel in ('recibo', 'passagem') and a.papel in ('cliente', 'cliente_ambiguo', 'numero_novo')
           and date_trunc('week', a.aberta_em at time zone 'America/Sao_Paulo')::date = s.semana) as conteudo_1h_pct,
       (select count(*) from public.retorno_cartoes c
         where coalesce((c.dados ->> 'palavra_errada')::boolean, false)
           and date_trunc('week', c.criado_em at time zone 'America/Sao_Paulo')::date = s.semana) as palavras_erradas
  from semanas s;

comment on view public.retorno_f2_medidas is
  'Retorno F2 (P13.5): a medida por semana do cartão, das palavras e dos toques. O portão de saída lê daqui.';

revoke all on public.retorno_f2_medidas from public, anon, authenticated;
grant select on public.retorno_f2_medidas to service_role;

-- bancada: pular (início)
select cron.unschedule(jobid) from cron.job where jobname = 'retorno-minuto';
select cron.schedule('retorno-minuto', '* * * * *', $c$
  select public.retorno_vigia(now());
  select public.retorno_vigia_cartao(now());
  select net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/retorno-recibos',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron-secret', (select value::text from public.app_settings where key = 'cron_worker_secret' limit 1)),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000)
  where public.retorno_tem_vencido(now());
$c$);
-- bancada: pular (fim)
