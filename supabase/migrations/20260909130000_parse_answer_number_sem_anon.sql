-- NOVO-lev-31: parse_answer_number era a ÚNICA das 14 funções da frente de
-- Levantamento com EXECUTE para anon (provado com has_function_privilege em
-- 09/09/2026). Exposição real nenhuma — é um parser puro de texto —, mas a
-- higiene que a própria migration vizinha prega vale para todas: função nova
-- fecha para anônimo na mesma migration em que nasce, e esta tinha escapado.

-- Só `from anon` NÃO fecha: o EXECUTE vinha herdado do grant a PUBLIC (provado ao
-- vivo — has_function_privilege seguiu true após o primeiro revoke). O padrão da
-- casa: tirar de PUBLIC e de anon, e conceder NOMINALMENTE a quem usa.
revoke execute on function public.parse_answer_number(text) from public;
revoke execute on function public.parse_answer_number(text) from anon;
grant execute on function public.parse_answer_number(text) to authenticated, service_role;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260909130000', 'parse_answer_number_sem_anon')
on conflict (version) do nothing;
