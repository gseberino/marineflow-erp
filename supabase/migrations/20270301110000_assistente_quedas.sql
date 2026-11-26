-- Histórico de quedas do assistente e do WhatsApp, e a chave do vigia do assistente (pacote 1 do assistente, V1, 25/11/2026).
--
-- NÃO APLICADA. Este arquivo existe para revisão: aplicar é do dono, com OK nomeado.
--
-- Por que existe: em 90 dias o Claude da assinatura parou de atender sete vezes com o WhatsApp de pé (login, limite da
-- semana, rede, o programa do PC parado de 07 a 08/11) e ninguém vigiava. O dono só soube reclamando. E não havia
-- histórico de queda nenhuma: whatsapp_conexao_vigia guarda uma linha só, o estado de agora.
--
-- O que cria:
--   1. public.assistente_quedas: uma linha por queda, de três tipos.
--        claude   = o programa do PC está vivo e diz que o Claude não atende (login, limite, indisponível, configuração);
--        gateway  = o programa do assistente parou de dar sinal ao banco (programa parado, PC sem rede);
--        whatsapp = a queda que o vigia da conexão já detecta (PC fora, Docker ou túnel, desconectado, travado).
--      Sem texto de mensagem, de pedido ou de erro: `detalhe` guarda só o motivo e o horário que o programa do PC publica.
--      Só o servidor lê e grava (RLS ligada, sem policy; anon e authenticated sem privilégio nenhum, provado abaixo e em
--      supabase/tests/assistente_quedas.sql).
--   2. A chave app_settings.vigia_assistente = 'sombra'.
--        desligado (ou ausente) = o vigia da conexão do WhatsApp roda exatamente como antes;
--        sombra  = grava o histórico e NÃO manda nada, nem muda texto nenhum;
--        ligado  = grava e avisa o dono, pelo portão da voz única, quando só o assistente cai. Ligar é do dono, depois de
--                  uma semana de sombra conferindo se as quedas gravadas batem com o que se sabe.
--
-- O que muda para quem usa ao aplicar: nada. Com 'sombra' só o histórico passa a ser gravado.
--
-- Como o código lê (supabase/functions/whatsapp-conexao/vigia-do-assistente.ts e _shared/ai/max/queda-do-assistente.ts):
-- chave AUSENTE = desligado, e por isso o deploy das funções pode sair antes desta migration; tabela que não existe com a
-- chave posta à mão = o erro é anotado em app_error_logs e o vigia da conexão segue como antes.
--
-- Tabela nova e vazia: não trava tabela quente. app_settings recebe um insert.
--
-- Desfazer:
--   delete from public.app_settings where key = 'vigia_assistente';
--   drop table public.assistente_quedas;
--
-- Aplicar (CLAUDE.md do repositório, regra 1). A versão é registrada pela ÚLTIMA LINHA deste arquivo, sem "on conflict":
-- versão repetida TEM de dar erro. NÃO rodar um segundo insert do registro.
--   npx supabase db query --linked -f supabase/migrations/20270301110000_assistente_quedas.sql
-- Prova (depois de aplicar, ou antes, como ensaio): supabase/tests/assistente_quedas.sql.

create table public.assistente_quedas (
  id               uuid primary key default gen_random_uuid(),
  tipo             text not null check (tipo in ('claude', 'gateway', 'whatsapp')),
  causa            text not null check (causa in ('login', 'limite', 'indisponivel', 'configuracao', 'programa_parado', 'sem_rede',
                                                  'pc_fora', 'docker_ou_tunel', 'desconectado', 'travado', 'desconhecida')),
  detalhe          text check (detalhe is null or char_length(detalhe) <= 300),
  desde            timestamptz not null,
  visto_em         timestamptz not null default now(),
  ate              timestamptz,
  fechada_por      text check (fechada_por in ('job_bom', 'batimento', 'whatsapp_voltou', 'sem_prova')),
  dono_soube       text check (dono_soube in ('aviso', 'resposta_de_falha')),
  avisado_em       timestamptz,
  avisado_por      text check (avisado_por in ('whatsapp', 'guardado', 'sino', 'limite')),
  aviso_id         uuid,
  volta_avisada_em timestamptz,
  criado_em        timestamptz not null default now()
);

comment on table public.assistente_quedas is
  'Histórico de quedas do assistente (o Claude da assinatura e o programa dele no PC) e do WhatsApp. Uma linha por queda. Gravado pelo vigia da conexão (whatsapp-conexao), conforme app_settings.vigia_assistente. Só o servidor lê e grava.';
comment on column public.assistente_quedas.tipo is
  'claude = o programa do PC diz que o Claude não atende; gateway = o programa do assistente parou de dar sinal; whatsapp = a queda da conexão do WhatsApp.';
comment on column public.assistente_quedas.detalhe is
  'O motivo e o horário de liberação que o programa do PC publica (ou o estado da conexão do WhatsApp). Nunca texto de mensagem.';
comment on column public.assistente_quedas.desde is
  'Início da queda: o último sinal do programa (gateway), a rodada em que o vigia viu o problema (claude) ou o início da queda da conexão (whatsapp).';
comment on column public.assistente_quedas.visto_em is
  'A última rodada do vigia em que o problema estava à vista. Queda do tipo claude sem prova de volta fecha 24 h depois disto.';
comment on column public.assistente_quedas.ate is
  'Fim da queda. Nulo = aberta (no máximo uma aberta por tipo).';
comment on column public.assistente_quedas.fechada_por is
  'job_bom = um pedido ao Claude foi concluído depois do início; batimento = o programa voltou a dar sinal; whatsapp_voltou = a conexão voltou; sem_prova = fechou sozinha, sem aviso de volta.';
comment on column public.assistente_quedas.dono_soube is
  'aviso = o vigia avisou; resposta_de_falha = o dono já tinha lido a causa numa resposta de falha do assistente (o vigia não avisou).';
comment on column public.assistente_quedas.avisado_por is
  'whatsapp = o portão acordou o dono; guardado = o portão guardou para a manhã ou o fechamento; sino = só o sino do sistema; limite = só o sino, porque já tinham saído 2 mensagens do vigia no dia.';
comment on column public.assistente_quedas.aviso_id is
  'avisos_do_dono.id do aviso da queda. Sem chave estrangeira: o portão reabre e resolve os avisos dele.';

-- No máximo uma queda aberta por tipo (duas rodadas do vigia ao mesmo tempo não abrem duas).
create unique index assistente_quedas_uma_aberta on public.assistente_quedas (tipo) where ate is null;
create index assistente_quedas_desde on public.assistente_quedas (desde desc);

-- Só o servidor: RLS ligada e nenhuma policy fecha para todos os outros; revogar dos três e provar (revogar de public não
-- fecha anon nem authenticated: o Supabase dá privilégio direto aos dois em toda tabela nova do schema public).
alter table public.assistente_quedas enable row level security;
revoke all on table public.assistente_quedas from public, anon, authenticated;
grant select, insert, update, delete on table public.assistente_quedas to service_role;

do $$
declare
  v_priv text;
begin
  foreach v_priv in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
    if has_table_privilege('anon', 'public.assistente_quedas', v_priv) then
      raise exception 'anon ficou com % em assistente_quedas', v_priv;
    end if;
    if has_table_privilege('authenticated', 'public.assistente_quedas', v_priv) then
      raise exception 'authenticated ficou com % em assistente_quedas', v_priv;
    end if;
  end loop;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.assistente_quedas'::regclass) then
    raise exception 'RLS desligada em assistente_quedas';
  end if;
end $$;

-- A chave nasce em sombra. Se já existir (posta à mão antes), fica como está: quem a pôs escolheu o valor.
insert into public.app_settings (key, value, description)
values ('vigia_assistente', 'sombra',
        'Vigia do assistente (V1): desligado | sombra (só grava o histórico de quedas) | ligado (avisa o dono pelo portão da voz única). Ausente = desligado.')
on conflict (key) do nothing;

insert into supabase_migrations.schema_migrations (version, name) values ('20270301110000', 'assistente_quedas');
