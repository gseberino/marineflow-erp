-- Bucket 'documents' passa a PRIVADO: o link público (/object/public/documents/...) deixa de
-- abrir para qualquer um.
--
-- Aplicar SÓ DEPOIS de o front com link assinado estar no ar e um envio real de PDF pela tela
-- ter sido conferido pelo banco (audit_log com /object/sign/documents/ e objeto apagado). Na
-- ordem inversa, o envio de PDF pela tela quebra até o front novo subir (a Evolution receberia
-- erro ao baixar o link público).
--
-- Os objetos antigos (41 PDFs de 18/06 a 24/09/2026) são apagados à parte, pela API do Storage
-- (DELETE direto em storage.objects é barrado por storage.protect_delete). Decisão do dono em
-- 26/09/2026: apagar todos — 9 nunca chegaram a ninguém e os 32 entregues o cliente já recebeu
-- como arquivo; o sistema gera o PDF de novo quando precisar.

update storage.buckets set public = false where id = 'documents';

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'documents' and public = false) then
    raise exception 'bucket documents não ficou privado';
  end if;
end $$;
