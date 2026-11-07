-- Retorno rápido ao cliente, F2 (P12): o que a F2 acrescenta ao Secretário.
--
-- retorno_resumo_do_dia da F1 não muda. retorno_resumo_extra devolve à parte a palavra *retorno*, os contatos sem recibo, o "Mandei
-- sozinho hoje", promovidos, rebaixados, suspensos e a semana. Nunca devolve texto do cliente.
--
-- A letra do "Mandei sozinho" é a gravada no envio: o fechamento só lê, e *errado Z* acha a mesma saída nos 3 turnos da tarde.
--
-- retorno_auditoria_lista é a amostra de 1 em auditoria_cada por tipo, mais tudo o que passou de 3 no dia. TEM a pergunta do cliente:
-- nunca sai pelo WhatsApp, só no relatório privado.
--
-- Reverter: drop view public.retorno_auditoria_lista; drop function public.retorno_resumo_extra(text, timestamptz),
-- public._retorno_fechamento_anterior(timestamptz). lerExtra trata a função ausente como "sem extra".

create or replace function public._retorno_fechamento_anterior(p_agora timestamptz)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_ponto time := (public._retorno_cfg()).ponto_fechamento;
  v_dia date := (p_agora at time zone c_fuso)::date - 1;
  v_i integer;
begin
  for v_i in 1 .. 10 loop
    exit when public._retorno_dia_de_tarde(v_dia);
    v_dia := v_dia - 1;
  end loop;
  return (v_dia + v_ponto) at time zone c_fuso;
end;
$$;

comment on function public._retorno_fechamento_anterior(timestamptz) is
  'Retorno F2 (P12): o instante do fechamento do dia de tarde anterior a p_agora.';

revoke all on function public._retorno_fechamento_anterior(timestamptz) from public, anon, authenticated;

create or replace function public.retorno_resumo_extra(p_turno text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_letras constant text[] := array['Z', 'Y', 'X', 'W', 'V'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_desde timestamptz;
  v_mandei jsonb;
  v_total integer;
  v_seg date;
  v_semana jsonb;
begin
  if v_cfg.id is null then
    return null;
  end if;
  v_desde := public._retorno_fechamento_anterior(v_agora);

  if p_turno = 'manha' then
    return jsonb_build_object('palavra', v_cfg.cartao_ligado,
      'contatos', jsonb_build_object(
        'vendedores', (select count(*) from public.retorno_aberturas a
                        where a.nivel = 'nada' and a.motivo = 'vendedor' and a.aberta_em > v_desde and a.aberta_em <= v_agora),
        'conhecidos', (select count(*) from public.retorno_aberturas a
                        where a.nivel = 'nada' and a.motivo = 'contato_conhecido' and a.aberta_em > v_desde and a.aberta_em <= v_agora)));
  end if;

  select count(*) into v_total
    from public.retorno_saidas s
   where s.tipo like 'modelo\_%' escape '\' and coalesce((s.dados ->> 'sozinho')::boolean, false)
     and s.estado in ('enviada', 'incerta') and s.decidida_em > v_desde and s.decidida_em <= v_agora;

  select coalesce(jsonb_agg(x.o order by x.ord), '[]'::jsonb) into v_mandei
    from (select l.ord, jsonb_build_object('letra', s.letra, 'rotulo', public._retorno_rotulo(s.abertura_id, v_agora),
                                           'tipo_curto', public._retorno_tipo_curto(s.tipo), 'saida_id', s.id) as o
            from public.retorno_saidas s
            join unnest(c_letras) with ordinality as l(letra, ord) on l.letra = s.letra
           where s.tipo like 'modelo\_%' escape '\' and coalesce((s.dados ->> 'sozinho')::boolean, false)
             and s.estado in ('enviada', 'incerta') and s.decidida_em > v_desde and s.decidida_em <= v_agora
           order by l.ord
           limit 3) x;

  -- Só na sexta útil, como as alongadas da F1.
  if extract(isodow from v_hoje) = 5 and public._retorno_dia_de_tarde(v_hoje) then
    v_seg := v_hoje - 4;
    select jsonb_build_object(
             'recibos', count(*) filter (where s.id is not null),
             'recibo_12min', count(*) filter (where s.id is not null and s.decidida_em - a.aberta_em <= interval '12 minutes'),
             'hora_casos', count(*) filter (where a.prometido_ate is not null and a.recibo_em is not null),
             'hora_cumprida', count(*) filter (where a.prometido_ate is not null and a.recibo_em is not null
                                                 and a.cumprida_em <= coalesce(a.segundo_prazo, a.prometido_ate)),
             'vencida_sem_aviso', count(*) filter (where a.estado = 'vencida' and a.adiamento_em is null and a.fim_do_dia_em is null),
             'insistencia', count(*) filter (where a.insistencias > 0),
             'toques', (select count(*) from public.retorno_toques t where (t.em at time zone c_fuso)::date between v_seg and v_hoje),
             'dias_uteis', (select count(*) from generate_series(v_seg, v_hoje, interval '1 day') d where public.agenda_dia_util(d::date)))
      into v_semana
      from public.retorno_aberturas a
      left join lateral (select o.id, o.decidida_em from public.retorno_saidas o
                          where o.abertura_id = a.id and o.tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo')
                            and o.estado in ('enviada', 'incerta')
                          order by o.decidida_em limit 1) s on true
     where (a.aberta_em at time zone c_fuso)::date between v_seg and v_hoje
       and a.aberta_em <= v_agora
       and a.nivel in ('recibo', 'passagem');
  end if;

  return jsonb_build_object(
    'palavra', v_cfg.cartao_ligado,
    'mandei', v_mandei,
    'mandei_mais', greatest(0, v_total - jsonb_array_length(v_mandei)),
    'promovidos', (select coalesce(jsonb_agg(public._retorno_tipo_curto(t.tipo) order by t.tipo), '[]'::jsonb)
                     from public.retorno_modelo_tipos t where t.promovido_em > v_desde and t.promovido_em <= v_agora and t.nivel = 'sozinho'),
    'rebaixados', (select coalesce(jsonb_agg(jsonb_build_object('tipo_curto', public._retorno_tipo_curto(t.tipo), 'motivo', t.rebaixado_motivo) order by t.tipo), '[]'::jsonb)
                     from public.retorno_modelo_tipos t where t.rebaixado_em > v_desde and t.rebaixado_em <= v_agora),
    'suspensos', (select coalesce(jsonb_agg(public._retorno_tipo_curto(t.tipo) order by t.tipo), '[]'::jsonb)
                    from public.retorno_modelo_tipos t
                   where t.promocao_suspensa_ate > v_agora and t.promocao_suspensa_ate - v_cfg.fadiga_suspende > v_desde),
    'semana', v_semana);
end;
$$;

comment on function public.retorno_resumo_extra(text, timestamptz) is
  'Retorno F2 (C-EXTRA): manha: palavra e contatos; fechamento: palavra, mandei (até 3, pela letra gravada), mandei_mais, promovidos, rebaixados, suspensos e a semana, só na sexta útil. Nunca devolve texto do cliente.';

revoke all on function public.retorno_resumo_extra(text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_resumo_extra(text, timestamptz) to service_role;

create or replace view public.retorno_auditoria_lista with (security_invoker = on) as
select s.enviada_em, s.tipo, s.texto, public._retorno_rotulo(s.abertura_id, null) as rotulo,
       public._retorno_pedido_do_caso(s.abertura_id, coalesce(s.enviada_em, s.decidida_em)) as trecho,
       s.dados -> 'fato' as fato, s.dados -> 'fato' ->> 'fonte' as fonte, s.dados ->> 'errado_em' as errado_em
  from public.retorno_saidas s
 where s.tipo like 'modelo\_%' escape '\'
   and coalesce((s.dados ->> 'sozinho')::boolean, false)
   and s.estado in ('enviada', 'incerta')
   and (coalesce((s.dados ->> 'auditoria')::boolean, false) or s.letra is null or s.letra in ('W', 'V'));

comment on view public.retorno_auditoria_lista is
  'Retorno F2 (P12.1): a amostra de 1 em auditoria_cada por tipo e o que passou de 3 no dia. Tem a pergunta do cliente: nunca sai pelo WhatsApp.';

revoke all on public.retorno_auditoria_lista from public, anon, authenticated;
grant select on public.retorno_auditoria_lista to service_role;
