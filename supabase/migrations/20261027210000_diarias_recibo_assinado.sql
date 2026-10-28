-- Diárias: o papel assinado do recibo fica anexado — 27/10/2026 (fase 4 da revisão de 24/10).
--
-- O recibo de serviços (20261027180000) é o documento que o prestador assina no papel. A prova é a
-- foto (ou o PDF) do papel assinado, guardada no bucket privado "documents" em
-- diarias/recibos/<id do acerto>/…; esta função marca o recibo como assinado e guarda o caminho.
-- Trocar o anexo é permitido (foto ruim): o caminho novo substitui o anterior, com a hora nova.
-- Teste: supabase/tests/diarias_recibo_assinado.sql.

create or replace function public.anexar_recibo_assinado(
  p_acerto_id uuid,
  p_arquivo text,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v record;
begin
  if v_autor is null then raise exception 'Diga quem está anexando o papel assinado.'; end if;
  select a.*, p.name as nome into v from public.acertos_diarias a join public.payees p on p.id = a.favorecido_id
   where a.id = p_acerto_id for update of a;
  if v.id is null then raise exception 'Recibo não encontrado.'; end if;
  if v.status <> 'fechado' then raise exception 'O recibo nº % está reaberto: emita de novo antes de anexar o papel.', lpad(v.numero::text, 4, '0'); end if;
  if v.documento is null then raise exception 'O acerto nº % é do modelo antigo, sem recibo de serviços para assinar.', lpad(v.numero::text, 4, '0'); end if;
  if p_arquivo is null or p_arquivo not like 'diarias/recibos/' || p_acerto_id::text || '/%' then
    raise exception 'Arquivo fora da pasta deste recibo.';
  end if;
  update public.acertos_diarias set assinado_em = now(), assinatura_arquivo = p_arquivo where id = v.id;
  return jsonb_build_object('ok', true, 'numero', v.numero,
    'message', 'Papel assinado anexado ao recibo nº ' || lpad(v.numero::text, 4, '0') || ' de ' || v.nome || '.');
end;
$$;

revoke all on function public.anexar_recibo_assinado(uuid, text, uuid) from public, anon;
grant execute on function public.anexar_recibo_assinado(uuid, text, uuid) to authenticated, service_role;
