-- Reserva de envio do WhatsApp: "já enviado" só quando o envio anterior TERMINOU.
--
-- O defeito (Diário de Bordo, 29/09/2026): a tela reenviava depois de um erro de rede e dizia
-- "Enviado" mesmo quando a primeira tentativa tinha falhado. A edge whatsapp-send reserva a
-- chave antes de chamar a Evolution, e a repetição (1 s depois) achava a chave reservada e
-- respondia "já enviado" enquanto a primeira ainda esperava a Evolution. Se a Evolution
-- falhava, a reserva era liberada, mas a tela já tinha mostrado "Enviado". E se a função
-- morria no meio (Evolution travada até o limite de tempo da edge), a chave ficava presa e
-- toda repetição dos 10 minutos seguintes ouvia "já enviado".
--
-- A reserva não tinha como dizer "terminou": provider_message_id só é gravado quando a
-- Evolution devolve id. concluido_em passa a ser o desfecho: preenchida = saiu; vazia = em
-- andamento (ou tentativa que morreu no meio). A edge só responde "já enviado" com ela
-- preenchida; vazia, espera o desfecho por alguns segundos e, sem desfecho, diz que não
-- confirmou.
--
-- As linhas que já existem ficam como concluídas (concluido_em = criado_em): é o que a edge
-- supunha delas até hoje, e nenhuma reserva antiga muda de comportamento.
--
-- Ordem de publicação: esta migration ANTES da edge whatsapp-send nova. Edge nova sem a
-- coluna leria "erro" na consulta e responderia "não confirmado" a toda chave repetida.
--
-- Aplicada por `db query -f` (sem `db push`): registra a si mesma no fim.

alter table public.whatsapp_send_idempotencia
  add column if not exists concluido_em timestamptz;

update public.whatsapp_send_idempotencia
   set concluido_em = criado_em
 where concluido_em is null;

comment on column public.whatsapp_send_idempotencia.concluido_em is
  'Quando o provedor confirmou o envio. Vazia = envio em andamento ou tentativa que morreu no meio: a edge whatsapp-send não responde "já enviado" por ela. (O receivable-reminders reserva chaves próprias e não preenche esta coluna.)';

insert into supabase_migrations.schema_migrations (version, name)
values ('20260929160000', 'whatsapp_idempotencia_concluido_em')
on conflict do nothing;
