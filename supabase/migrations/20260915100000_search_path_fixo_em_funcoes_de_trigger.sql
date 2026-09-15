-- Duas funções de trigger ainda resolviam nomes pelo search_path da sessão (advisor
-- function_search_path_mutable, 15/09/2026). Trigger roda com os privilégios de quem
-- disparou a escrita; sem search_path fixo, um schema plantado antes de public trocaria
-- o que "now()" ou "public.tabela" significam. Fixar custa nada e fecha o último aviso
-- desta família — as outras ~150 funções já vinham fixas desde 27/07.

alter function public.calc_shift_duration() set search_path = public;
alter function public.touch_updated_at() set search_path = public;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260915100000', 'search_path_fixo_em_funcoes_de_trigger')
on conflict do nothing;
