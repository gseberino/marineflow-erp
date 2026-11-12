-- Gmail antigo da HBR (hbr.boats@gmail.com) entra no e-mail do sistema (12/11/2026). Pedido do dono:
-- conectar o Gmail de antes do domínio próprio "com tudo" — busca de XML de nota, acompanhamento de
-- e-mail, assistente (WhatsApp e chat do sistema), resumo da manhã e a tela "Notas recebidas por e-mail".
--
-- Mesmo leitor das caixas da GoDaddy/Titan (edge email-imap, cron */10): imap.gmail.com:993, LOGIN
-- com SENHA DE APP do Google (16 letras; exige verificação em 2 etapas na conta). O dono cadastra a
-- senha de app no segredo EMAIL_HBRBOATS_SENHA (Supabase › Edge Functions › Secrets) — a tabela
-- guarda só o NOME do segredo, nunca a senha.
--
-- Lê a INBOX (a "Caixa de entrada" do Gmail, que inclui as abas Promoções/Social — o atalho
-- determinístico de lista/automático filtra sem gastar IA). Histórico: 90 dias, igual às outras
-- caixas, entra SEM triagem. Para trazer mais histórico depois: aumentar history_days e zerar
-- imap_last_uid/imap_uidvalidity desta caixa — a deduplicação por Message-ID evita repetir.
-- Resposta pelo assistente (só com o "sim" do dono): smtp.gmail.com:465, sem cópia por APPEND —
-- o Gmail guarda sozinho em Enviados (envioDaCaixa em _shared/email/resposta.ts).
--
-- Aplicar DEPOIS de o segredo existir (antes disso a rodada só marca a caixa com
-- "segredo não cadastrado", sem afetar as outras).

insert into public.email_accounts (address, label, active, owner_consent_at, imap_host, imap_port, secret_name, history_days)
values ('hbr.boats@gmail.com', 'Gmail HBR Boats', true, now(), 'imap.gmail.com', 993, 'EMAIL_HBRBOATS_SENHA', 90)
on conflict (address) do update
  set imap_host = excluded.imap_host, imap_port = excluded.imap_port, secret_name = excluded.secret_name,
      label = excluded.label, active = true,
      owner_consent_at = coalesce(public.email_accounts.owner_consent_at, excluded.owner_consent_at);

insert into supabase_migrations.schema_migrations (version, name)
values ('20270105110000', 'email_gmail_hbr_boats')
on conflict (version) do nothing;
