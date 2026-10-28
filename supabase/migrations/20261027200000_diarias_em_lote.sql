-- Diárias: a semana inteira numa confirmação só, gravada de uma vez — 27/10/2026 (fase 3 da revisão de 24/10).
--
-- "Roberto: seg a qui inteiro, sex meio, sáb inteiro" virava três pendências (três "sim") e três
-- gravações soltas: em 24/10 a semana do Roberto foi cancelada no meio e o sábado nunca entrou.
-- registrar_diarias_em_lote recebe a lista de dias já resolvida pelo assistente e chama
-- registrar_diaria para cada um DENTRO da mesma transação: se um dia é recusado (acerto fechado,
-- sem diária cadastrada), nenhum entra — e a mensagem diz qual.
--
-- Só uma função nova; registrar_diaria não muda. Teste: supabase/tests/diarias_em_lote.sql.

create or replace function public.registrar_diarias_em_lote(
  p_favorecido_id uuid,
  p_dias jsonb,                 -- [{data, jornada, os_ids?, observacao?, extras?, descontos?, valor_diaria?}]
  p_origem text default 'agente',
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  d jsonb;
  r jsonb;
  v_res jsonb := '[]'::jsonb;
  v_data date;
begin
  if p_dias is null or jsonb_typeof(p_dias) <> 'array' or jsonb_array_length(p_dias) = 0 then
    raise exception 'Nenhum dia para registrar.';
  end if;
  if jsonb_array_length(p_dias) > 62 then
    raise exception 'Dias demais num pedido só (%): até 62.', jsonb_array_length(p_dias);
  end if;
  if (select count(*) <> count(distinct x ->> 'data') from jsonb_array_elements(p_dias) x) then
    raise exception 'O mesmo dia aparece duas vezes no pedido: diga cada dia uma vez só.';
  end if;

  for d in select x from jsonb_array_elements(p_dias) x order by x ->> 'data' loop
    v_data := (d ->> 'data')::date;
    begin
      r := public.registrar_diaria(
        p_favorecido_id, v_data, d ->> 'jornada',
        case when jsonb_typeof(d -> 'os_ids') = 'array' then array(select jsonb_array_elements_text(d -> 'os_ids')::uuid) end,
        d ->> 'observacao', (d ->> 'extras')::numeric, (d ->> 'descontos')::numeric, (d ->> 'valor_diaria')::numeric,
        coalesce(p_origem, 'agente'), p_autor);
    exception when others then
      raise exception 'Nada foi gravado: o dia % foi recusado (%).', to_char(v_data, 'DD/MM'), sqlerrm;
    end;
    v_res := v_res || jsonb_build_array(r);
  end loop;

  return jsonb_build_object('ok', true, 'quantos', jsonb_array_length(v_res), 'dias', v_res);
end;
$$;

revoke all on function public.registrar_diarias_em_lote(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.registrar_diarias_em_lote(uuid, jsonb, text, uuid) to authenticated, service_role;
