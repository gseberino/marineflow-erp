-- ═══════════════════════════════════════════════════════════════════════════
-- Levantamento antes de orçar — perguntas por COMPOSIÇÃO
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 3-bis (P15-P18)
--
-- Sintoma relatado pelo dono: os botões "Levantar no local" e "Pedir foto ao
-- cliente" respondem "este serviço ainda não tem perguntas de levantamento
-- cadastradas" — em QUALQUER OS. O aviso está correto:
-- service_survey_templates tem zero registros. A mecânica inteira existe
-- (gatilho, tela de uma pergunta por vez, modo local e remoto, contingência
-- por confiança); falta o conteúdo. É o mesmo padrão dos blocos de roteiro:
-- motor construído, tanque vazio.
--
-- A armadilha, que os blocos já ensinaram a evitar: service_id era NOT NULL.
-- Escrever perguntas assim significaria 261 conjuntos, um por serviço do
-- catálogo. Com pergunta por SISTEMA e por VERBO — os mesmos dois eixos que já
-- classificam o catálogo — são ~16 conjuntos, e a pergunta certa aparece por
-- composição.
--
-- Precedência igual à do roteiro: pergunta escrita para o serviço específico
-- ganha; se não houver, compõe pelos eixos.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Os eixos entram na tabela de perguntas ──────────────────────────────
alter table public.service_survey_templates
  alter column service_id drop not null;

alter table public.service_survey_templates
  add column if not exists applies_to_system text,
  add column if not exists applies_to_verb text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='survey_tpl_system_check') then
    alter table public.service_survey_templates add constraint survey_tpl_system_check
      check (applies_to_system is null or applies_to_system in
        ('eletrico_dc','eletrico_ac','gas','hidraulico','eletronico',
         'refrigeracao','mecanico','estrutural','nenhum'));
  end if;
  if not exists (select 1 from pg_constraint where conname='survey_tpl_verb_check') then
    alter table public.service_survey_templates add constraint survey_tpl_verb_check
      check (applies_to_verb is null or applies_to_verb in
        ('instalacao','substituicao','reparo','diagnostico','manutencao',
         'remocao','configuracao','adequacao','logistica'));
  end if;
  -- Uma pergunta precisa de algum alvo: serviço, sistema ou verbo.
  if not exists (select 1 from pg_constraint where conname='survey_tpl_tem_alvo') then
    alter table public.service_survey_templates add constraint survey_tpl_tem_alvo
      check (service_id is not null or applies_to_system is not null or applies_to_verb is not null);
  end if;
end $$;

create index if not exists survey_tpl_por_eixo
  on public.service_survey_templates (applies_to_system, applies_to_verb) where active;

-- ─── 2. O compositor de perguntas ───────────────────────────────────────────
-- Devolve o questionário de um serviço: as perguntas escritas para ele, ou —
-- se não houver nenhuma — as do seu sistema e do seu verbo. Ordenado por
-- impacto no preço, porque é a ordem em que se deve perguntar quando o tempo
-- do técnico acaba antes das perguntas.
create or replace function public.compose_survey_for_service(
  p_service_id uuid,
  p_mode text default 'local'
)
returns table (
  id uuid, seq integer, question text, help_text text, answer_type text,
  options jsonb, price_impact text, ask_remotely boolean, origem text)
language plpgsql stable security definer set search_path = public
as $fn$
declare v_verb text; v_sys text; v_proprias integer;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select service_verb, service_system into v_verb, v_sys
  from public.services where services.id = p_service_id;

  select count(*) into v_proprias
  from public.service_survey_templates t
  where t.service_id = p_service_id and t.active;

  return query
  select t.id, t.seq, t.question, t.help_text, t.answer_type, t.options,
         t.price_impact, t.ask_remotely,
         case when t.service_id is not null then 'serviço'
              when t.applies_to_system is not null then 'sistema'
              else 'verbo' end
  from public.service_survey_templates t
  where t.active
    and (p_mode <> 'remoto' or t.ask_remotely)
    and (
      -- Pergunta escrita para este serviço ganha e exclui as compostas.
      (v_proprias > 0 and t.service_id = p_service_id)
      or (v_proprias = 0 and (
            (t.applies_to_system is not null and t.applies_to_system = v_sys)
         or (t.applies_to_verb   is not null and t.applies_to_verb   = v_verb)))
    )
  order by case t.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
           t.seq
  limit 9;  -- teto do P16: mais que nove perguntas ninguém responde em campo
end;
$fn$;

revoke all on function public.compose_survey_for_service(uuid, text) from public, anon;
grant execute on function public.compose_survey_for_service(uuid, text) to authenticated;
