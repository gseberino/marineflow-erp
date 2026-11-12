-- Retorno rápido ao cliente, F5 (P1): a base do acompanhamento do orçamento depois do envio. Nada liga aqui.
-- Gerada por script (scripts/gerar_f5.cjs checks): o texto vem de scripts/f5_sql/p1_base.sql, escrito à mão; os checks
-- fechados do retorno (seção 6) são montados de pg_get_constraintdef de produção, com a lista vigente inteira e os valores
-- da F5 no fim, para não perder valor que outra sessão tenha posto.
--
-- 1. retorno_config ganha as chaves e as réguas da F5. Tudo nasce desligado (seção 10 da spec, "Se não responder"):
--    orcamento_modo, envio_mao_modo e aceite_modo 'desligado'; validade_envio_ligada, aceite_audio, dados_nota_ligado,
--    orcamento_segura, encerrar_marca_perdido e motivo_marca_aberto falsos. A cadência exige a validade do envio (K6).
-- 2. service_orders ganha o 1º envio ao número do cliente (hora, via, chave) e o desfecho (motivo_perda e as colunas dele).
--    O padrão de quote_validity_days passa a 7 (K6; a 3ª fonte do mesmo número, D-16).
-- 3. orcamento_envios: todo envio de orçamento, a qualquer número, reenvio inclusive (só o número do documento).
-- 4. orcamento_acompanhamentos e orcamento_passos: a cadência do K7 (lembrete, véspera, encerramento), cada passo com prazo.
-- 5. orcamento_aceites: o aceite por texto (C9). A prova é o id da mensagem do cliente, nunca o texto dela.
-- 6. Os checks fechados de retorno_saidas, retorno_cartao_itens e retorno_modelo_tipos ganham os valores da F5 (gerado); o
--    item do cartão sem caso (cadencia, aceite, dados_nota) existe só com o seu ponteiro, que o apaga junto (cascade); os 3
--    tipos da cadência entram em retorno_modelo_tipos, desligados. orc_fechado e orc_dados_nota nunca entram: como o M07 da
--    F3, só saem pela letra com *sim <PIN>*.
-- 7. RLS nas 4 tabelas: leitura só de admin e financeiro, escrita só do service_role; anon nada. O grant de anon em
--    service_orders é por coluna: as 7 colunas novas já nascem fechadas a ele.
--
-- Sem dado de cliente: só as 3 linhas de configuração dos tipos novos. DDL em service_orders e FK para whatsapp_messages: na
-- bancada só de madrugada (seção 7.4, F5_DDL_QUENTE).
-- Reverter sem deploy: update public.retorno_config set orcamento_modo = 'desligado', validade_envio_ligada = false,
-- envio_mao_modo = 'desligado', aceite_modo = 'desligado', aceite_audio = false, dados_nota_ligado = false,
-- motivo_marca_aberto = false where id; — as tabelas e colunas ficam.

-- ── 1. Configuração (uma linha, id boolean) ────────────────────────────────────────────────────────────────────────────────

alter table public.retorno_config
  add column orcamento_modo text not null default 'desligado' check (orcamento_modo in ('desligado', 'sombra', 'ligado')),
  add column validade_envio_ligada boolean not null default false,          -- K6 em todo envio (P2, P11, P12)
  add column envio_mao_modo text not null default 'desligado' check (envio_mao_modo in ('desligado', 'registrar', 'marcar')),
  add column orcamento_envio_ate timestamptz,                               -- marca d'água da detecção à mão
  add column aceite_modo text not null default 'desligado' check (aceite_modo in ('desligado', 'sombra', 'cartao')),
  add column orcamento_aceite_ate timestamptz,                              -- marca d'água da detecção do aceite
  add column aceite_audio boolean not null default false,                   -- dúvida 7: a transcrição do áudio entra no detector
  add column dados_nota_ligado boolean not null default false,
  add column orcamento_segura boolean not null default false,               -- *segura orcamentos*
  add column encerrar_marca_perdido boolean not null default false,         -- dúvida 1
  add column motivo_marca_aberto boolean not null default false,            -- dúvida 8: *motivo N X* marca perdido um orçamento aberto
  add column cadencia_hora time not null default '10:00',
  add column cadencia_inicio time not null default '09:00',
  add column cadencia_fim time not null default '17:00',
  add column cadencia_lembrete_du smallint not null default 2 check (cadencia_lembrete_du between 1 and 5),   -- K7
  add column cadencia_encerra_du smallint not null default 1 check (cadencia_encerra_du between 1 and 3),    -- K7
  add column cadencia_dono_carencia interval not null default '2 hours',    -- o que o dono manda logo depois do PDF é parte do envio
  add column cadencia_conversa interval not null default '365 days',        -- só fala com quem já escreveu
  add column aceite_janela interval not null default '30 days',             -- orçamento enviado há até isto
  add column dados_nota_janela interval not null default '7 days';
alter table public.retorno_config add constraint retorno_config_cadencia_com_validade
  check (orcamento_modo = 'desligado' or validade_envio_ligada);           -- sem K6 a véspera não faz sentido (K6: "o lembrete da véspera não liga")
alter table public.retorno_config add constraint retorno_config_janela_comercial
  check (cadencia_inicio < cadencia_hora and cadencia_hora < cadencia_fim);

-- ── 2. A ordem ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

alter table public.service_orders
  add column orcamento_enviado_em timestamptz,
  add column orcamento_enviado_via text check (orcamento_enviado_via in ('assistente', 'tela', 'cartao', 'aparelho', 'marcado', 'historico')),
  add column orcamento_enviado_chave text check (orcamento_enviado_chave ~ '^[0-9]{8}$'),
  add column motivo_perda text check (motivo_perda in ('sumiu', 'fechou_com_outro', 'desistiu', 'preco', 'prazo', 'outro', 'sem_motivo_antigo')),
  add column motivo_perda_em timestamptz,
  add column motivo_perda_por text check (motivo_perda_por in ('tela', 'assistente', 'dono', 'cadencia', 'migracao')),
  add column motivo_perda_nota text check (char_length(motivo_perda_nota) <= 200);
alter table public.service_orders alter column quote_validity_days set default 7;   -- K6; a 3ª fonte do mesmo padrão
comment on column public.service_orders.orcamento_enviado_em is
  'Retorno F5: a hora do 1º envio do orçamento ao número do cliente (no PDF do aparelho, a hora do eco). Quem marca sent pode passá-la; sem ela, o gatilho trg_orcamento_quote_status põe now(). Nunca muda depois.';
comment on column public.service_orders.motivo_perda is
  'Retorno F5 (3.4): por que o orçamento foi perdido. Obrigatório com quote_status = rejected (CHECK da migration de dado).';

-- ── 3. Os envios ───────────────────────────────────────────────────────────────────────────────────────────────────────────
--    Um por evento, a qualquer número, reenvio inclusive; só número de documento, nunca nome de arquivo.
--    Quem grava: orcamento_registrar_envio (whatsapp-send: assistente, tela, cartão), orcamento_detectar_envio (aparelho),
--    o gatilho _orcamento_envio_depois (só a via 'marcado') e a migration de dado (via 'historico'). Um escritor por via.
create table public.orcamento_envios (
  id uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  via text not null check (via in ('assistente', 'tela', 'cartao', 'aparelho', 'marcado', 'historico')),
  chave text check (chave ~ '^[0-9]{8}$'),
  ao_cliente boolean not null,
  em timestamptz not null,
  whatsapp_message_id uuid unique references public.whatsapp_messages(id) on delete set null,
  marcou boolean not null default false,          -- este evento passou o funil a sent
  criado_em timestamptz not null default now(),
  unique (service_order_id, via, em)
);
create index orcamento_envios_por_ordem on public.orcamento_envios (service_order_id, em);

-- ── 4. O acompanhamento ────────────────────────────────────────────────────────────────────────────────────────────────────
--    Um por orçamento; o reenvio com validade nova o refaz (P3.1); passo enviado nunca se repete.
create table public.orcamento_acompanhamentos (
  id uuid primary key default gen_random_uuid(),
  service_order_id uuid not null unique references public.service_orders(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  chave text not null check (chave ~ '^[0-9]{8}$'),
  enviado_em timestamptz not null,
  validade_ate date not null,
  modo text not null check (modo in ('sombra', 'ligado')),
  estado text not null default 'ativo' check (estado in ('ativo', 'parado', 'encerrado', 'concluido')),
  parou_por text check (parou_por in ('cliente_escreveu', 'encerrou', 'parar', 'dono_falou', 'segurado', 'status_mudou',
                                      'validade_mudou', 'opt_out', 'erro')),
  parou_em timestamptz,
  parou_msg_id uuid,                              -- whatsapp_messages.id que parou (só o id)
  desfecho_proposto text check (desfecho_proposto in ('sumiu', 'fechou_com_outro', 'desistiu')),
  encerramento text check (encerramento in ('enviado', 'sombra', 'sem_mensagem')),
  refeito_em timestamptz,                         -- a última vez que um reenvio com validade nova o refez
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (estado <> 'parado' or parou_por is not null),   -- 'concluido' também grava parou_por (status_mudou)
  check ((estado = 'encerrado') = (encerramento is not null))
);
create index orcamento_acompanhamentos_ativos on public.orcamento_acompanhamentos (estado) where estado in ('ativo', 'parado');

create table public.orcamento_passos (
  id uuid primary key default gen_random_uuid(),
  acompanhamento_id uuid not null references public.orcamento_acompanhamentos(id) on delete cascade,
  passo text not null check (passo in ('lembrete', 'vespera', 'encerramento')),
  tipo text not null check (tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento')),
  dia date not null,
  ate date not null,                              -- o prazo do passo (P3.1): fica à espera do sim, ou remarca, até este dia
  estado text not null default 'previsto' check (estado in ('previsto', 'aguarda_sim', 'agendado', 'sombra', 'enviado', 'pulado', 'cancelado')),
  -- motivo: a tabela de-para da P5.1 (o valor gravado é o mesmo da saída; o que o canal devolver fora dela vira 'canal')
  motivo text check (motivo in ('sem_sim', 'agenda_hoje', 'outra_voz_hoje', 'comercial_hoje', 'segurado', 'orcamento_desligado',
                                'teto_iniciadas', 'sem_conversa', 'so_reativo', 'segura_tudo', 'pessoal', 'equipe', 'opt_out',
                                'bloqueado', 'classe_nao_suportada', 'provedor', 'fora_da_janela', 'espacamento', 'texto',
                                'sem_nome', 'validador', 'canal', 'parou', 'erro', 'tirado')),
  saida_id uuid references public.retorno_saidas(id) on delete set null,
  avisado_em timestamptz,                         -- o fechamento da véspera disse "amanhã sai sozinho" (P8.1, P10.2)
  aviso_fila uuid,                                -- a linha da whatsapp_send_queue que levou esse fechamento: o passo só sai sozinho
                                                  -- com ela em 'sent' (P3.1, bloco 4). Sem FK de propósito: FK nova trava a fila (tabela quente)
  texto_aprovado text check (char_length(texto_aprovado) <= 600),   -- o texto que o dono leu no cartão e aprovou
  aprovado_em timestamptz,
  aprovado_por uuid references public.app_users(id) on delete set null,
  unique (acompanhamento_id, passo),
  check (ate >= dia),
  check (estado = 'cancelado' or ((estado = 'pulado') = (motivo is not null)))
);
create index orcamento_passos_do_dia on public.orcamento_passos (dia, estado);

-- ── 5. O aceite ────────────────────────────────────────────────────────────────────────────────────────────────────────────
create table public.orcamento_aceites (
  id uuid primary key default gen_random_uuid(),
  abertura_id uuid references public.retorno_aberturas(id) on delete set null,
  whatsapp_message_id uuid not null unique,      -- a prova: o id da mensagem do cliente (só o id)
  client_id uuid not null references public.clients(id) on delete cascade,
  chave text not null check (chave ~ '^[0-9]{8}$'),
  candidatos uuid[] not null,                    -- orçamentos enviados abertos no momento
  service_order_id uuid references public.service_orders(id) on delete set null,   -- só com 1 candidato. set null de propósito:
                                                  -- o aceite é a prova da mensagem do cliente e não some com a ordem (P1.2 nº 4b)
  sinal_lido text not null check (char_length(sinal_lido) <= 40),   -- o trecho do léxico que casou ("pode fazer")
  estado text not null check (estado in ('sombra', 'detectado', 'duvida', 'agenda', 'com_sinal', 'sem_sinal', 'nao_era', 'respondido',
                                         'substituido', 'caiu')),
  faltas_nota text[] not null default '{}',
  pedir_dados boolean not null default false,
  total_visto numeric,                            -- o retrato: grand_total quando o item foi montado
  executado_em timestamptz,                       -- *sim <PIN>* com B ou D: a conversão está com a ferramenta (P6.1, P3.1 bloco 7)
  decidido_em timestamptz,
  decidido_por uuid references public.app_users(id) on delete set null,
  resultado jsonb not null default '{}' check (jsonb_typeof(resultado) = 'object'),   -- {numero, convertido, quote_status}
  saida_fechado_id uuid references public.retorno_saidas(id) on delete set null,
  saida_dados_id uuid references public.retorno_saidas(id) on delete set null,
  dados_msg_id uuid,                              -- a resposta com CPF/CEP (só o id)
  dados_estado text check (dados_estado in ('esperando', 'lidos', 'gravados', 'nada')),
  criado_em timestamptz not null default now()
);
create index orcamento_aceites_do_caso on public.orcamento_aceites (abertura_id, estado);
create index orcamento_aceites_vivos on public.orcamento_aceites (criado_em)
  where estado in ('detectado', 'duvida', 'agenda') or dados_estado = 'lidos';     -- a lista de aceites do cartão (P7)

comment on table public.orcamento_envios is
  'Retorno F5: todo envio de orçamento, a qualquer número, reenvio inclusive (o universo do desfecho, P13). Só o número do documento, nunca o nome do arquivo. Um escritor por via.';
comment on table public.orcamento_acompanhamentos is
  'Retorno F5: a cadência do K7, um por orçamento enviado ao número do cliente. Para com qualquer mensagem do cliente, encerrou, PARAR, mensagem do dono ou *segura <número>*.';
comment on table public.orcamento_passos is
  'Retorno F5: lembrete, véspera e encerramento de cada acompanhamento, cada um com o prazo (ate) até o qual espera o *sim <PIN>*.';
comment on table public.orcamento_aceites is
  'Retorno F5 (C9): o aceite por texto do cliente. A prova é o id da mensagem (nunca o texto); só pergunta ao dono, nunca age sozinho.';

-- ── 6. Os checks do retorno ganham os valores da F5 (lista fechada; recriar com a lista inteira do vigente + os novos) ──────
--    retorno_saidas: emissor + 'orcamento'; tipo + 'orc_lembrete', 'orc_vespera', 'orc_encerramento', 'orc_fechado', 'orc_dados_nota';
--    origem + 'retorno_orcamento'; classe + 'comercial'; motivo + 'cliente_escreveu', 'encerrou', 'parar', 'dono_falou',
--    'segurado', 'status_mudou', 'validade_mudou', 'sem_conversa', 'agenda_hoje', 'outra_voz_hoje', 'comercial_hoje',
--    'sem_sim', 'orcamento_desligado', 'parceiro_cliente', 'aceite_mudou' (os do canal já estão na lista vigente).
--    retorno_cartao_itens: tipo_item + 'aceite', 'dados_nota', 'cadencia'; caiu_motivo + 'cliente_escreveu', 'orcamento_mudou', 'segurado'
--    (os outros motivos de parada vão aos valores que já existem: tabela de-para da P5.1).
--    retorno_modelo_tipos: tipo + 'orc_lembrete', 'orc_vespera', 'orc_encerramento'.

-- Gerado por scripts/gerar_f5.cjs checks, de pg_get_constraintdef de produção: a lista vigente inteira, na ordem
-- dela, e os valores da F5 no fim.

alter table public.retorno_saidas drop constraint retorno_saidas_emissor_check;
alter table public.retorno_saidas add constraint retorno_saidas_emissor_check check (emissor in (
  'retorno', 'fila', 'parceiro',
  -- F5:
  'orcamento'));

alter table public.retorno_saidas drop constraint retorno_saidas_tipo_check;
alter table public.retorno_saidas add constraint retorno_saidas_tipo_check check (tipo in (
  'recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo', 'saudacao_numero_novo', 'adiamento',
  'fim_do_dia', 'urgente', 'parar', 'cadastro_provisorio', 'acorde', 'fila', 'modelo_aguarda_peca',
  'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico', 'modelo_liberado', 'modelo_retirada_nao',
  'modelo_ver_no_local', 'parceiro_ativacao', 'parceiro_recibo', 'parceiro_coleta', 'parceiro_aviso_cliente',
  'parceiro_nao_mp_ok', 'parceiro_painel', 'parceiro_patio', 'parceiro_eco', 'parceiro_pausa', 'parceiro_repassar',
  'parceiro_recado',
  -- F5:
  'orc_lembrete', 'orc_vespera', 'orc_encerramento', 'orc_fechado', 'orc_dados_nota'));

alter table public.retorno_saidas drop constraint retorno_saidas_origem_check;
alter table public.retorno_saidas add constraint retorno_saidas_origem_check check (origem in (
  'retorno_recibo', 'retorno_coleta', 'retorno_adiamento', 'retorno_modelo', 'retorno_parceiro', 'retorno_aviso',
  -- F5:
  'retorno_orcamento'));

alter table public.retorno_saidas drop constraint retorno_saidas_classe_check;
alter table public.retorno_saidas add constraint retorno_saidas_classe_check check (classe in (
  'resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro',
  -- F5:
  'comercial'));

alter table public.retorno_saidas drop constraint retorno_saidas_motivo_check;
alter table public.retorno_saidas add constraint retorno_saidas_motivo_check check (motivo in (
  'respondida_pelo_dono', 'caso_fechado', 'caso_vencido', 'nivel_nada', 'rajada', 'lote_global',
  'aguarda_transcricao', 'fora_da_janela', 'espacamento', 'teto_numero', 'teto_dia', 'teto_coleta', 'teto_saudacao',
  'teto_volta', 'atraso_longo', 'bloqueado', 'opt_out', 'cliente_final', 'pessoal', 'equipe', 'so_reativo',
  'segura_tudo', 'segura_recibos', 'tipo_desligado', 'modo', 'urgente_desligado', 'validador', 'texto', 'canal',
  'provedor', 'reserva', 'erro', 'substituida', 'sem_config', 'classe_nao_suportada', 'sem_numero',
  'agenda_ja_acordou', 'duplicado_pergunta', 'sem_nome', 'recusaria_fila', 'guardado_no_portao', 'acorde_repetido',
  'fato_mudou', 'visita_a_combinar', 'parceiro_regra', 'veto', 'pausado', 'segura_patio', 'teto_iniciadas',
  'teto_painel', 'teto_eco', 'teto_patio', 'parceiro_desligado', 'cliente_nao_ouviu', 'numero_compartilhado',
  -- F5:
  'cliente_escreveu', 'encerrou', 'parar', 'dono_falou', 'segurado', 'status_mudou', 'validade_mudou', 'sem_conversa',
  'agenda_hoje', 'outra_voz_hoje', 'comercial_hoje', 'sem_sim', 'orcamento_desligado', 'parceiro_cliente',
  'aceite_mudou'));

alter table public.retorno_cartao_itens drop constraint retorno_cartao_itens_tipo_item_check;
alter table public.retorno_cartao_itens add constraint retorno_cartao_itens_tipo_item_check check (tipo_item in (
  'modelo', 'peca_sem_registro', 'pronto_sem_palavra', 'retirada', 'ambiguo', 'numero_novo', 'orcamento', 'adicional',
  'livre',
  -- F5:
  'aceite', 'dados_nota', 'cadencia'));

alter table public.retorno_cartao_itens drop constraint retorno_cartao_itens_caiu_motivo_check;
alter table public.retorno_cartao_itens add constraint retorno_cartao_itens_caiu_motivo_check check (caiu_motivo in (
  'respondida_pelo_dono', 'caso_fechado', 'fato_mudou', 'telefone_mudou', 'canal_bloqueado', 'item_provisorio',
  'sem_cadastro', 'contato_diferente', 'orc_existe', 'cliente_final', 'rascunho_sem_valor',
  -- F5:
  'cliente_escreveu', 'orcamento_mudou', 'segurado'));

alter table public.retorno_modelo_tipos drop constraint retorno_modelo_tipos_tipo_check;
alter table public.retorno_modelo_tipos add constraint retorno_modelo_tipos_tipo_check check (tipo in (
  'modelo_aguarda_peca', 'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico', 'modelo_liberado',
  -- F5:
  'orc_lembrete', 'orc_vespera', 'orc_encerramento'));

--    O item sem caso existe só com o seu ponteiro, e o ponteiro apaga o item junto (cascade): apagar uma ordem ou um cliente
--    (que apaga em cascata acompanhamento, passos e aceites) nunca esbarra no CHECK.
alter table public.retorno_cartao_itens
  alter column abertura_id drop not null,
  add column passo_id uuid references public.orcamento_passos(id) on delete cascade,
  add column aceite_id uuid references public.orcamento_aceites(id) on delete cascade,
  add column tirado_em timestamptz,               -- F5: o *não N* explícito num item do orçamento; *só* e *sem* o apagam (P7.1, T-DIT-3 a 5)
  add constraint retorno_cartao_itens_caso_ou_ponteiro
    check ((abertura_id is not null)
        or (tipo_item = 'cadencia' and passo_id is not null)
        or (tipo_item in ('aceite', 'dados_nota') and aceite_id is not null));
insert into public.retorno_modelo_tipos (tipo, regua) values
  ('orc_lembrete', 'dias'), ('orc_vespera', 'dias'), ('orc_encerramento', 'dias')
on conflict (tipo) do nothing;                    -- nivel = 'desligado' (padrão): ligar é o OK "ligar lembretes"

-- ── 7. Leitura só no painel de admin e financeiro; escrita só o service_role; anon nada ────────────────────────────────────

alter table public.orcamento_envios enable row level security;
alter table public.orcamento_acompanhamentos enable row level security;
alter table public.orcamento_passos enable row level security;
alter table public.orcamento_aceites enable row level security;

drop policy if exists orcamento_envios_leitura on public.orcamento_envios;
create policy orcamento_envios_leitura on public.orcamento_envios
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists orcamento_acompanhamentos_leitura on public.orcamento_acompanhamentos;
create policy orcamento_acompanhamentos_leitura on public.orcamento_acompanhamentos
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists orcamento_passos_leitura on public.orcamento_passos;
create policy orcamento_passos_leitura on public.orcamento_passos
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists orcamento_aceites_leitura on public.orcamento_aceites;
create policy orcamento_aceites_leitura on public.orcamento_aceites
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.orcamento_envios, public.orcamento_acompanhamentos, public.orcamento_passos, public.orcamento_aceites
  from public, anon, authenticated;
grant select on table public.orcamento_envios, public.orcamento_acompanhamentos, public.orcamento_passos, public.orcamento_aceites
  to authenticated;
grant all on table public.orcamento_envios, public.orcamento_acompanhamentos, public.orcamento_passos, public.orcamento_aceites
  to service_role;
