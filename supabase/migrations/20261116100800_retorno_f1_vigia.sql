-- Retorno rápido ao cliente, F1 (sobe em sombra na seg 16/11/2026): o vigia do retorno, que roda a cada
-- minuto pelo cron (P9, antes do retorno_tem_vencido), só em SQL, sem chamada de edge, e o cadastro
-- provisório do número novo. O relógio do caso (E.4) é do banco: o aviso honesto antes de vencer, o fim do
-- dia, o caso vencido, o fecho por conteúdo, silêncio ou idade.
--
-- 1. _retorno_acorde_simulado(agora) → {acordaria, motivo}: o acorde que a leva própria do acorde real faria
--    (só LÊ). Fora de 08:00–19:59 não acorda; acima do teto do dia (app_settings.voz_unica_regras.
--    acordes_por_dia, padrão 2) também não. Conta os avisos_do_dono 'acordou' do telefone do dono no dia,
--    registrados até agora (qualquer modo), mais os acordes simulados do dia que acordariam. NÃO grava em
--    avisos_do_dono: gravar em sombra misturaria com o guardado que a manhã lê. Sem dono: não acorda.
--
-- 2. retorno_vigia(agora) → jsonb com as contagens de cada passo. Cada passo roda num begin … exception
--    próprio: o que falha vai ao app_error_logs (context 'retorno', action 'vigia', com o passo) e os outros
--    seguem. Os laços por item (passos 3, 6, 7, 8 e 9) isolam também CADA item: o erro de um vai ao log (com o
--    passo e o id) e não desfaz o passo inteiro, que senão falharia igual a cada minuto e travaria todos os
--    outros itens (erro nunca trava a fila). Toda leitura de whatsapp_messages leva occurred_at <= agora, e só
--    entram casos gravados até agora (ninguém olha o futuro: o replay, P9, reproduz a ordem real). Os passos:
--     1 sem a linha de configuração ou desligado → sai;
--     2 disjuntor pela conexão, nos DOIS sentidos: a conexão fora de 'open' há 10 min liga o so_reativo
--       (motivo 'conexao'); de volta a 'open' há 10 min, desliga (o motivo 'erros' só desliga numa enviada);
--     3 áudio transcrito: a transcrição só troca o body da linha; a mensagem com audio_pendente cujo corpo
--       mudou volta a retorno_abrir (idempotente pelo hash), que tria o caso de novo (19% das recebidas são
--       áudio). Sem gatilho em whatsapp_messages (tabela quente): o passo de 1 min basta. Só conta a
--       reavaliação com ok; a linha que o retorno_abrir não reavaliou (ok = false, que desfaz tudo e deixa o
--       hash antigo, ou a mensagem ignorada) sai do filtro (audio_pendente = false) com log: senão voltaria a
--       cada minuto por 24 h. A mensagem fica sem a 2ª triagem (falha fecha: nada sai por ela);
--     4 respostas humanas (_retorno_resposta_humana): respondida_em, cumprida_em e cumprida_por; com conteúdo,
--       o caso fecha ('conteudo') e as agendadas dele são canceladas (respondida_pelo_dono);
--     5 fechar: 'silencio' (respondido sem conteúdo, SEM promessa ouvida, 4 h sem recebida); 'nada' (caso
--       nada sem mensagem de nenhum lado há 4 h; fora o da promessa do dono, que o relógio guarda até vencer
--       — desvio da spec, falha fecha); 'expirou' (3 dias úteis completos sem recebida e sem topo_dia por vir).
--       O caso com promessa ouvida nunca fecha por silêncio: só por conteúdo ou por idade;
--     6 relógio (casos abertos com recibo e promessa, sem conteúdo): o acorde de X − acorde_antes; em
--       X − adiamento_antes, o adiamento com X2 (casos com o mesmo X em fila, 1 min entre eles, nunca depois
--       de X − 1 min; R1-11) ou, sem X2, o fim do dia ali mesmo (sem 3ª promessa); em X2, com o adiamento
--       decidido, o fim do dia; o recibo decidido depois de X − adiamento_antes vai direto ao fim do dia em X;
--       a promessa do dono não ganha adiamento. O caso aberto cujo prazo final passou sem conteúdo vira
--       'vencida' (a mensagem nova vira passagem, P5). Desvio (lacuna da spec, levado à coordenação): com X2,
--       o adiamento que não vai ser ouvido (recusado pelo validador, pelo canal, por um teto ou por erro;
--       ainda agendado em X, que o retorno_pegar cancela por caso_vencido; ou que nem nasceu) dá o fim do dia
--       em X, como o recibo decidido depois de X − 30. Sem isso o caso vencia calado em X: o cliente ouviu "até
--       as 10h" e não recebia nem o adiamento nem o fim do dia, e "ninguém ouve a promessa sem o aviso
--       garantido" (§3) caía. Ficam de fora o adiamento decidido (sombra, enviada, incerta: o fim do dia é em
--       X2), o que está saindo (preparada, enviando) e o cancelado porque o dono respondeu, o caso fechou ou a
--       triagem deu nada (o fim do dia cairia pelo mesmo motivo). Pelo mesmo motivo o caso não vence enquanto o
--       adiamento dele está saindo: se ele for recusado depois de X, o fim do dia em X ainda nasce;
--     7 decide no SQL o acorde (sempre sombra nesta leva, com o _retorno_acorde_simulado) e o cadastro
--       provisório (retorno_cadastro_provisorio, executando só com o modo efetivo ligado): criaria = sombra;
--       criado = enviada; perguntar = recusada/duplicado_pergunta; nada = cancelada/sem_nome. Exceção num item
--       = recusada/erro, e o próximo segue;
--     8 incertas: só conferir, por 30 min, se a linha apareceu na conversa (enviada à chave com o mesmo texto,
--       gravada depois da decisão) → enviada. NUNCA há reenvio: o whatsapp-send só grava a conversa depois do
--       sucesso e o envio pela API não volta como eco (0 de 521). Desvio de B.5.7, escrito (dúvida 6);
--     9 presos: 'preparada' com a reserva vencida há 5 min volta a 'agendada' (nada saiu), atrás das que já
--       venceram (enviar_em = agora) e com dados.presas contando as voltas; na 2ª vez presa (a edge falhou de
--       novo no mesmo item) vira recusada/erro, com log: nada volta à frente da fila a cada ~7 min (incidente
--       de 17/08). 'enviando' presa vira 'incerta', com os efeitos no caso (pode ter saído); o efeito que falha
--       vai ao log e a saída fica incerta mesmo assim;
--    10 rebaixamento automático (E.6): o tipo sai de tipos_ligados com opt-out até 48 h depois de uma enviada
--       dele à mesma chave, reclamação até 24 h depois, ou 3 recusas do validador dele na última hora; junto
--       saem os que dependem dele (o grupo do P1.1 nunca quebra). Só conta o sinal das últimas 24 h (desvio,
--       detalhe em aberto na spec: sem janela, um opt-out antigo impediria religar o tipo para sempre);
--    11 (04:00–04:00:59 de Brasília) arquivar o cadastro provisório sem OS depois de cadastro_arquivar_apos.
--       Nunca apaga;
--    12 (mesmo minuto) retenção da coleta não convertida (J.12, 180 dias), no caso e no lead;
--    13 (mesmo minuto, só ligado) alongamento (B.4.1): a faixa com 20+ casos de recibo enviado em 30 dias e
--       menos de 80% cumpridos no prazo passa ao próximo momento (14h → 19h; 19h → 10h do próximo dia útil;
--       10h → 19h), com a linha em retorno_alongamentos. Nunca encurta. Detalhes em aberto, escolhidos para
--       não alongar duas vezes pela mesma evidência (desvio, falha fecha): só contam os casos já vencidos (o
--       prometido_ate passou) e com o recibo enviado depois do último alongamento da faixa;
--    14 devolve as contagens.
--
-- 3. retorno_cadastro_provisorio(caso, executar) → {acao: nada | perguntar | criaria | criado, …}
--    (C-CADASTRO): só o número novo com pedido de serviço e com o nome DITO depois da coleta 2 enviada (na
--    sombra a coleta nunca sai, e o nome nunca existe: R-7). Duplicado pela regra de procurarDuplicados
--    (_shared/ai/tools/clients.ts:104-130, só lida), sobre TODOS os clientes (ativos, inativos e o genérico):
--    mesmo documento (a F1 nunca coleta documento: coleta.documento, se um dia vier); senão mesmo telefone pela
--    chave de 8 dígitos (phone ou whatsapp); senão o mesmo nome sem acento (_retorno_nome_comparavel = o
--    semAcento de busca-cadastro.ts). Qualquer achado = perguntar, e NADA é criado. Sem executar = criaria.
--    Executando: o cliente provisório (origem 'retorno'), a unidade do bem DITO (o rótulo de unidade.ts que a
--    coleta guardou em coleta.tipo; o modelo sem bem dito fica sem unidade) e a linha de audit_log. NÃO grava
--    whatsapp_leads.linked_client_id: vínculo é pergunta; o telefone no cadastro já faz o quem_escreve
--    reconhecer (identificar não é vincular, B.1).
--    Desvio da spec (que diz action = 'insert'): o audit_log_action_check é LISTA FECHADA sem 'insert'
--    (20260924210000_audit_log_acoes_que_o_codigo_grava.sql), e o insert recusado (23514) faria o cadastro
--    nunca acontecer. Fica 'lead_converted' (o contato novo virou cadastro), com o que foi criado em new_value.
--    Ampliar a lista pede migration nova e o tipo AuditAction do front (src/hooks/use-audit-log.ts), fora
--    desta parte. Além do nome, exige a coleta 2 'enviada' no caso (falha fecha: nome sem a pergunta ouvida
--    nunca vira cadastro).
--
-- Funções: retorno_vigia e retorno_cadastro_provisorio são SECURITY DEFINER, só do service_role. As internas
-- (_retorno_*) são SECURITY DEFINER com search_path, revoke de public, anon e authenticated, sem grant
-- (_retorno_nome_comparavel é pura, só fixa o search_path).
--
-- Sem dado: só funções novas; nenhuma linha existente muda (o arquivamento e a retenção só agem sobre linhas
-- que o próprio retorno cria, a partir de 16/11).
-- Reverter (depois das migrations seguintes da F1, que chamam estas): drop function
-- public.retorno_vigia(timestamptz), public.retorno_cadastro_provisorio(uuid, boolean),
-- public._retorno_nome_comparavel(text), public._retorno_acorde_simulado(timestamptz).
-- Sem deploy: update public.retorno_config set modo = 'desligado' (o vigia só devolve "desligado").

-- ── 1. O acorde que haveria (só lê) ──────────────────────────────────────────────────────────────────

create or replace function public._retorno_acorde_simulado(p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_local timestamp := coalesce(p_agora, now()) at time zone 'America/Sao_Paulo';
  v_dono_fone text;
  v_limite integer;
  v_n integer;
begin
  -- A janela do acorde (aviso_registrar): 08:00–19:59.
  if v_local::time < time '08:00' or v_local::time >= time '20:00' then
    return jsonb_build_object('acordaria', false, 'motivo', 'fora_da_janela');
  end if;

  select d.phone into v_dono_fone from public._comprovante_dono() d limit 1;
  if v_dono_fone is null then
    return jsonb_build_object('acordaria', false, 'motivo', 'sem_dono');
  end if;

  begin
    v_limite := coalesce((select (s.value::jsonb ->> 'acordes_por_dia')::int
                            from public.app_settings s where s.key = 'voz_unica_regras' limit 1), 2);
  exception when others then
    v_limite := 2;   -- valor ilegível: o padrão de aviso_registrar
  end;

  select (select count(*) from public.avisos_do_dono a
           where a.phone_normalized = v_dono_fone
             and a.dia = v_local::date
             and a.situacao = 'acordou'
             and a.registrado_em <= v_agora)
       + (select count(*) from public.retorno_saidas s
           where s.tipo = 'acorde'
             and s.estado = 'sombra'
             and s.decidida_em <= v_agora
             and s.decidida_em >= (v_local::date)::timestamp at time zone c_fuso
             and coalesce((s.dados ->> 'acordaria')::boolean, false))
    into v_n;

  if v_n >= v_limite then
    return jsonb_build_object('acordaria', false, 'motivo', 'limite_do_dia', 'acordes', v_n, 'limite', v_limite);
  end if;
  return jsonb_build_object('acordaria', true, 'motivo', null, 'acordes', v_n, 'limite', v_limite);
end;
$$;

comment on function public._retorno_acorde_simulado(timestamptz) is
  'Retorno F1 (P6): {acordaria, motivo}: fora_da_janela (fora de 08:00–19:59), sem_dono, limite_do_dia (acordes do dia = avisos_do_dono acordou do dono + acordes simulados que acordariam, contra voz_unica_regras.acordes_por_dia). Só lê; nunca grava em avisos_do_dono.';

revoke all on function public._retorno_acorde_simulado(timestamptz) from public, anon, authenticated;

-- ── 2. O nome comparável (o semAcento de busca-cadastro.ts) ──────────────────────────────────────────

create or replace function public._retorno_nome_comparavel(p text)
returns text
language sql
immutable
set search_path = public
as $$
  select btrim(regexp_replace(translate(lower(coalesce(p, '')), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
                              '\s+', ' ', 'g'));
$$;

comment on function public._retorno_nome_comparavel(text) is
  'Retorno F1 (P6): minúsculas, sem acento e com espaços simples ("  JOÃO  da Silva" → "joao da silva"), o semAcento de busca-cadastro.ts.';

revoke all on function public._retorno_nome_comparavel(text) from public, anon, authenticated;

-- ── 3. O cadastro provisório (C-CADASTRO) ────────────────────────────────────────────────────────────

create or replace function public.retorno_cadastro_provisorio(p_abertura uuid, p_executar boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_nome text;
  v_nome_c text;
  v_doc text;
  v_dup jsonb;
  v_tipo text;
  v_unidade text;
  v_cliente uuid;
  v_unidade_id uuid;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_caso');
  end if;

  -- 1. Só o número novo, com pedido de serviço e com o nome dito depois da coleta 2 enviada.
  if v_ab.papel is distinct from 'numero_novo' then
    return jsonb_build_object('acao', 'nada', 'motivo', 'papel');
  end if;
  if not (v_ab.tipo_recibo is not distinct from 'recibo_numero_novo'
          or exists (select 1 from public.retorno_saidas s
                      where s.abertura_id = v_ab.id and s.tipo = 'recibo_numero_novo')) then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_pedido');
  end if;
  v_nome := nullif(btrim(v_ab.coleta ->> 'nome'), '');
  if v_nome is null
     or not exists (select 1 from public.retorno_saidas s
                     where s.abertura_id = v_ab.id and s.tipo = 'coleta_numero_novo' and s.estado = 'enviada') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_nome');
  end if;

  -- 2. Duplicado, pela regra de procurarDuplicados, sobre todos os clientes (ativos, inativos e o genérico).
  v_doc := public._doc_normalizado(v_ab.coleta ->> 'documento');
  if length(v_doc) < 11 then
    v_doc := null;
  end if;
  v_nome_c := public._retorno_nome_comparavel(v_nome);
  select coalesce(jsonb_agg(jsonb_build_object('client_id', x.id, 'nome', x.name, 'motivo', x.motivo)
                            order by x.ordem, x.name, x.id), '[]'::jsonb)
    into v_dup
    from (select c.id, c.name,
                 case when v_doc is not null and public._doc_normalizado(c.cpf_cnpj) = v_doc then 'mesmo documento'
                      when v_ab.chave in (public._agenda_chave_telefone(c.phone), public._agenda_chave_telefone(c.whatsapp))
                        then 'mesmo telefone'
                      when v_nome_c <> '' and public._retorno_nome_comparavel(c.name) = v_nome_c then 'mesmo nome'
                 end as motivo,
                 case when v_doc is not null and public._doc_normalizado(c.cpf_cnpj) = v_doc then 1
                      when v_ab.chave in (public._agenda_chave_telefone(c.phone), public._agenda_chave_telefone(c.whatsapp))
                        then 2
                      else 3
                 end as ordem
            from public.clients c) x
   where x.motivo is not null;
  if jsonb_array_length(v_dup) > 0 then
    return jsonb_build_object('acao', 'perguntar', 'duplicados', v_dup);
  end if;

  -- O bem dito, pelo rótulo de unidade.ts que a coleta guardou (o modelo sem bem dito não vira unidade).
  v_tipo := nullif(btrim(v_ab.coleta ->> 'tipo'), '');
  v_unidade := case when v_tipo is not null then coalesce(nullif(btrim(v_ab.coleta ->> 'modelo'), ''), v_tipo) end;

  -- 3. Sem executar: o que criaria.
  if not coalesce(p_executar, false) then
    return jsonb_build_object('acao', 'criaria', 'nome', v_nome,
                              'unidade', case when v_tipo is not null
                                              then jsonb_build_object('asset_type', v_tipo, 'name', v_unidade) end);
  end if;

  -- 4. Executa: cliente provisório, unidade do bem dito e o rastro. Nunca o vínculo do lead.
  insert into public.clients (type, name, whatsapp, provisorio, origem, active)
  values ('individual', v_nome, v_ab.phone_normalized, true, 'retorno', true)
  returning id into v_cliente;
  if v_tipo is not null then
    insert into public.vessels (client_id, name, asset_type, active)
    values (v_cliente, v_unidade, v_tipo, true)
    returning id into v_unidade_id;
  end if;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('clients', v_cliente, 'lead_converted', 'retorno', null,
          jsonb_build_object('provisorio', true, 'origem', 'retorno', 'caso', v_ab.id, 'vessel_id', v_unidade_id),
          'Cadastro provisório pelo retorno (caso ' || v_ab.id || ')');

  return jsonb_build_object('acao', 'criado', 'client_id', v_cliente, 'vessel_id', v_unidade_id);
end;
$$;

comment on function public.retorno_cadastro_provisorio(uuid, boolean) is
  'Retorno F1 (C-CADASTRO): {acao: nada (motivo papel|sem_pedido|sem_nome|sem_caso), perguntar (duplicados [{client_id, nome, motivo}] pela regra de procurarDuplicados, sobre todos os clientes), criaria (nome, unidade) ou criado (client_id, vessel_id)}. Só número novo com pedido e nome dito depois da coleta 2 enviada. Executando: cliente provisorio/origem retorno, unidade do bem dito e audit_log; nunca o vínculo do lead.';

revoke all on function public.retorno_cadastro_provisorio(uuid, boolean) from public, anon, authenticated;
grant execute on function public.retorno_cadastro_provisorio(uuid, boolean) to service_role;

-- ── 4. O vigia ───────────────────────────────────────────────────────────────────────────────────────

create or replace function public.retorno_vigia(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_faixas constant text[] := array['manha_cedo', 'meio', 'tarde', 'noite', 'folga', 'pressa'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_local timestamp := coalesce(p_agora, now()) at time zone 'America/Sao_Paulo';
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_diario boolean;
  v_cfg public.retorno_config;
  v_erros integer[] := '{}';
  r record;
  e record;
  v_estado text;
  v_desde timestamptz;
  v_disjuntor text;
  v_n_audio integer := 0;
  v_n_resp integer := 0;
  v_n_conteudo integer := 0;
  v_n_silencio integer := 0;
  v_n_nada integer := 0;
  v_n_expirou integer := 0;
  v_n_acorde integer := 0;
  v_n_adiamento integer := 0;
  v_n_fim integer := 0;
  v_n_vencida integer := 0;
  v_n_decididas integer := 0;
  v_n_incertas integer := 0;
  v_n_presas integer := 0;
  v_n_arquivados integer := 0;
  v_n_retencao integer := 0;
  v_n_k integer;
  v_rebaixados text[] := '{}';
  v_alongadas text[] := '{}';
  v_ids uuid[];
  v_rh jsonb;
  v_cump timestamptz;
  v_x timestamptz;
  v_x2 timestamptz;
  v_a timestamptz;
  v_fim timestamptz;
  v_quando timestamptz;
  v_fila integer;
  v_modo jsonb;
  v_cad jsonb;
  v_eco timestamptz;
  v_tirar text[];
  v_novos text[];
  v_atual jsonb;
  v_prox jsonb;
  v_hora_atual time;
  v_dias_atual integer;
  v_abrir jsonb;
  v_k_acorde integer;
  v_k_adiamento integer;
  v_k_fim integer;
begin
  -- 1. Sem a linha de configuração ou desligado: nada roda.
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('ok', true, 'rodou', false,
                              'motivo', case when v_cfg.id is null then 'sem_config' else 'desligado' end);
  end if;
  v_diario := v_local::time >= time '04:00' and v_local::time < time '04:01';

  -- 2. O disjuntor pela conexão, nos dois sentidos (todo estado diferente de 'open' é fora).
  begin
    select c.estado, c.desde into v_estado, v_desde
      from public.whatsapp_conexao_vigia c order by c.id limit 1;
    if v_estado is not null then
      if v_estado <> 'open' and v_desde <= v_agora - interval '10 minutes' and not v_cfg.so_reativo then
        update public.retorno_config c
           set so_reativo = true, so_reativo_motivo = 'conexao', so_reativo_desde = v_agora
         where c.id;
        v_disjuntor := 'ligou';
        perform public._retorno_log('disjuntor', 'retorno: so_reativo ligado pela conexão do WhatsApp', 'warn',
                                    jsonb_build_object('estado', v_estado, 'desde', v_desde));
      elsif v_cfg.so_reativo and v_cfg.so_reativo_motivo = 'conexao'
            and v_estado = 'open' and v_desde <= v_agora - interval '10 minutes' then
        update public.retorno_config c
           set so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null
         where c.id;
        v_disjuntor := 'desligou';
        perform public._retorno_log('disjuntor', 'retorno: so_reativo desligado (a conexão voltou)', 'warn',
                                    jsonb_build_object('desde', v_desde));
      end if;
    end if;
  exception when others then
    v_erros := v_erros || 2;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 2, 'sqlstate', sqlstate));
  end;

  -- 3. O áudio transcrito: o corpo mudou, a triagem roda de novo (retorno_abrir nunca levanta). Conta só a
  --    reavaliação com ok; a linha que continua com o hash antigo sai do filtro, com log (nada volta a cada
  --    minuto por 24 h).
  begin
    for r in
      select rm.whatsapp_message_id as msg, rm.consumida, md5(coalesce(w.body, '')) as hash
        from public.retorno_mensagens rm
        join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
       where rm.audio_pendente
         and rm.recebida_em > v_agora - v_cfg.audio_reavaliar_max
         and rm.recebida_em <= v_agora
         and w.occurred_at <= v_agora
         and md5(coalesce(w.body, '')) <> rm.corpo_hash
       order by rm.recebida_em, rm.whatsapp_message_id
       limit 200
    loop
      begin
        v_abrir := public.retorno_abrir(r.msg, r.consumida, v_agora);
        if coalesce((v_abrir ->> 'ok')::boolean, false) then
          v_n_audio := v_n_audio + 1;
        end if;
        -- ok = false desfaz tudo (o hash fica o antigo); a mensagem ignorada também não o regrava
        update public.retorno_mensagens rm
           set audio_pendente = false
         where rm.whatsapp_message_id = r.msg
           and rm.audio_pendente
           and rm.corpo_hash is distinct from r.hash;
        if found then
          perform public._retorno_log('vigia', 'retorno_vigia: áudio transcrito que o retorno_abrir não reavaliou', 'error',
                                      jsonb_build_object('passo', 3, 'mensagem', r.msg, 'ok', v_abrir -> 'ok',
                                                         'acao', v_abrir ->> 'acao'));
        end if;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 3, 'mensagem', r.msg, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 3;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 3, 'sqlstate', sqlstate));
  end;

  -- 4. As respostas humanas dos casos vivos; com conteúdo, o caso fecha e as agendadas dele caem.
  begin
    for r in
      select a.id, a.respondida_em
        from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida')
         and a.cumprida_em is null
         and a.gravada_em <= v_agora
       order by a.aberta_em, a.id
       for update skip locked
    loop
      v_rh := public._retorno_resposta_humana(r.id, v_agora);
      if v_rh ->> 'respondida_em' is null then
        continue;
      end if;
      v_cump := (v_rh ->> 'cumprida_em')::timestamptz;
      if r.respondida_em is null or v_cump is not null then
        update public.retorno_aberturas a
           set respondida_em = coalesce(a.respondida_em, (v_rh ->> 'respondida_em')::timestamptz),
               cumprida_em = v_cump,
               cumprida_por = case when v_cump is not null then v_rh ->> 'cumprida_por' end,
               estado = case when v_cump is not null then 'fechada' else a.estado end,
               fechada_em = case when v_cump is not null then v_agora else a.fechada_em end,
               fechada_motivo = case when v_cump is not null then 'conteudo' else a.fechada_motivo end,
               atualizada_em = now()
         where a.id = r.id;
        v_n_resp := v_n_resp + 1;
      end if;
      if v_cump is not null then
        v_n_conteudo := v_n_conteudo + 1;
        update public.retorno_saidas s
           set estado = 'cancelada', motivo = 'respondida_pelo_dono', decidida_em = v_agora, atualizada_em = now()
         where s.id in (select x.id from public.retorno_saidas x
                         where x.abertura_id = r.id and x.estado = 'agendada'
                         for update skip locked);
      end if;
    end loop;
  exception when others then
    v_erros := v_erros || 4;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 4, 'sqlstate', sqlstate));
  end;

  -- 5. Fechar: silêncio (sem promessa ouvida), nada parado e o caso que expirou. As agendadas caem.
  begin
    -- silêncio: o dono respondeu sem conteúdo, ninguém prometeu hora, e o número não escreveu mais por 4 h
    with fechar as (
      select a.id from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida')
         and a.gravada_em <= v_agora
         and a.respondida_em is not null
         and a.cumprida_em is null
         and a.prometido_ate is null
         and a.respondida_em + v_cfg.caso_fecha_silencio <= v_agora
         and not exists (select 1 from public.whatsapp_messages w
                          where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                            and w.direction = 'inbound'
                            and w.occurred_at <= v_agora
                            and w.occurred_at > a.respondida_em - interval '10 minutes'
                            and public._retorno_hora_real(w) > a.respondida_em)
       for update skip locked
    )
    update public.retorno_aberturas a
       set estado = 'fechada', fechada_em = v_agora, fechada_motivo = 'silencio', atualizada_em = now()
      from fechar f
     where a.id = f.id;
    get diagnostics v_n_silencio = row_count;

    -- nada parado: nenhuma mensagem (de nenhum lado) há 4 h; a promessa do dono fica no relógio até vencer
    with fechar as (
      select a.id from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida')
         and a.gravada_em <= v_agora
         and a.nivel = 'nada'
         and a.motivo is distinct from 'promessa_do_dono'
         and greatest(a.ultima_gravada_em,
                      coalesce((select max(w.occurred_at) from public.whatsapp_messages w
                                 where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                                   and w.direction = 'inbound' and w.occurred_at <= v_agora), a.ultima_gravada_em),
                      coalesce((select max(w.occurred_at) from public.whatsapp_messages w
                                 where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                                   and w.direction = 'outbound' and w.occurred_at <= v_agora), a.ultima_gravada_em))
             + v_cfg.caso_fecha_silencio <= v_agora
       for update skip locked
    )
    update public.retorno_aberturas a
       set estado = 'fechada', fechada_em = v_agora, fechada_motivo = 'nada', atualizada_em = now()
      from fechar f
     where a.id = f.id;
    get diagnostics v_n_nada = row_count;

    -- expirou: 3 dias úteis completos sem recebida do número, e sem a manhã de topo por vir
    with fechar as (
      select a.id from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida')
         and a.gravada_em <= v_agora
         and v_hoje > public.agenda_somar_du((a.ultima_em at time zone c_fuso)::date, v_cfg.expira_dias_uteis)
         and (a.topo_dia is null or a.topo_dia < v_hoje)
         and not exists (select 1 from public.whatsapp_messages w
                          where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                            and w.direction = 'inbound'
                            and w.occurred_at <= v_agora
                            and w.occurred_at > a.ultima_em - interval '10 minutes'
                            and public._retorno_hora_real(w) > a.ultima_em)
       for update skip locked
    )
    update public.retorno_aberturas a
       set estado = 'fechada', fechada_em = v_agora, fechada_motivo = 'expirou', atualizada_em = now()
      from fechar f
     where a.id = f.id;
    get diagnostics v_n_expirou = row_count;

    -- as agendadas dos casos fechados agora caem (a mensagem seguinte abre caso novo)
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
     where s.id in (select x.id from public.retorno_saidas x
                      join public.retorno_aberturas a on a.id = x.abertura_id
                     where x.estado = 'agendada'
                       and a.estado = 'fechada'
                       and a.fechada_em = v_agora
                       and a.fechada_motivo in ('silencio', 'nada', 'expirou')
                     for update of x skip locked);
  exception when others then
    v_erros := v_erros || 5;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 5, 'sqlstate', sqlstate));
  end;

  -- 6. O relógio dos casos abertos com recibo e promessa, sem conteúdo (E.4).
  begin
    for r in
      select a.id, a.chave, a.phone_normalized, a.client_id, a.modo, a.recibo_em, a.prometido_ate,
             a.adiamento_em, a.segundo_prazo
        from public.retorno_aberturas a
       where a.estado = 'aberta'
         and a.nivel in ('recibo', 'passagem')
         and a.recibo_em is not null
         and a.prometido_ate is not null
         and a.cumprida_em is null
         and a.recibo_em <= v_agora
         and a.prometido_fonte is distinct from 'dono'      -- a promessa do dono não ganha adiamento
       order by a.prometido_ate, a.recibo_em, a.id
    loop
      -- cada caso no seu sub-bloco: o erro de um (um X2 ou uma hora ilegível) vai ao log e os outros seguem
      begin
        v_k_acorde := 0;
        v_k_adiamento := 0;
        v_k_fim := 0;
        v_x := r.prometido_ate;
        v_x2 := public._retorno_x2(v_x);
        v_a := v_x - v_cfg.adiamento_antes;

        -- o acorde do relógio, uma hora antes de X
        if v_agora >= v_x - v_cfg.acorde_antes and v_agora < v_x then
          insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo,
                                             estado, enviar_em, dados, dedupe_key)
          values (r.id, 'acorde', 'relogio', r.chave, r.phone_normalized, r.client_id, r.modo, 'agendada',
                  v_x - v_cfg.acorde_antes, jsonb_build_object('por', 'relogio', 'x', v_x),
                  'retorno:' || r.id || ':acorde:relogio')
          on conflict (dedupe_key) do nothing;
          get diagnostics v_k_acorde = row_count;
        end if;

        -- o adiamento, com X2, em X − 30; os casos do mesmo X em fila, 1 min entre eles, nunca depois de X − 1
        if v_x2 is not null and r.recibo_em <= v_a and v_agora >= v_a and v_agora < v_x
           and not exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'retorno:' || r.id || ':adiamento') then
          select count(*) into v_fila
            from public.retorno_saidas s
            join public.retorno_aberturas b on b.id = s.abertura_id
           where s.tipo = 'adiamento' and b.prometido_ate = v_x;
          v_quando := least(v_a + make_interval(mins => v_fila), v_x - interval '1 minute');
          insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                             estado, enviar_em, dados, dedupe_key)
          values (r.id, 'adiamento', 'retorno_adiamento', 'resposta_atrasada', r.chave, r.phone_normalized, r.client_id,
                  r.modo, 'agendada', v_quando,
                  jsonb_build_object('hora', public._retorno_hora((v_x2 at time zone c_fuso)::time),
                                     'x', v_x, 'x2', v_x2, 'fila', v_fila),
                  'retorno:' || r.id || ':adiamento')
          on conflict (dedupe_key) do nothing;
          get diagnostics v_k_adiamento = row_count;
        end if;

        -- o fim do dia: sem X2, em X − 30 (sem 2ª hora); com X2 e o adiamento decidido, em X2; o recibo decidido
        -- depois de X − 30 vai direto ao fim do dia em X. Só no próprio dia. Desvio (§3): com X2, o adiamento que
        -- não vai ser ouvido (recusado; ainda agendado em X, que o retorno_pegar cancela por caso_vencido; ou que
        -- nem nasceu) também dá o fim do dia em X. Fora: o decidido (o fim do dia é em X2), o que está saindo e o
        -- cancelado porque o dono respondeu, o caso fechou ou a triagem deu nada.
        v_fim := case
          when r.recibo_em > v_a then v_x
          when v_x2 is null then v_a
          when r.adiamento_em is not null and r.segundo_prazo is not null then r.segundo_prazo
          when r.adiamento_em is null and v_agora >= v_x
               and not exists (select 1 from public.retorno_saidas s
                                where s.dedupe_key = 'retorno:' || r.id || ':adiamento'
                                  and (s.estado in ('preparada', 'enviando', 'sombra', 'enviada', 'incerta')
                                       or (s.estado = 'cancelada'
                                           and s.motivo in ('respondida_pelo_dono', 'caso_fechado', 'nivel_nada'))))
            then v_x
        end;
        if v_fim is not null and v_agora >= v_fim
           and (v_agora at time zone c_fuso)::date = (v_fim at time zone c_fuso)::date then
          insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                             estado, enviar_em, dados, dedupe_key)
          values (r.id, 'fim_do_dia', 'retorno_adiamento', 'resposta_atrasada', r.chave, r.phone_normalized, r.client_id,
                  r.modo, 'agendada', v_fim,
                  jsonb_build_object('x', v_x, 'x2', v_x2, 'dia', (v_fim at time zone c_fuso)::date),
                  'retorno:' || r.id || ':fim_do_dia')
          on conflict (dedupe_key) do nothing;
          get diagnostics v_k_fim = row_count;
        end if;

        -- só conta o que ficou gravado (o sub-bloco que falha desfaz os inserts dele)
        v_n_acorde := v_n_acorde + v_k_acorde;
        v_n_adiamento := v_n_adiamento + v_k_adiamento;
        v_n_fim := v_n_fim + v_k_fim;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 6, 'caso', r.id, 'sqlstate', sqlstate));
      end;
    end loop;

    -- o caso aberto cujo prazo final passou sem conteúdo vira vencido (inclusive o da promessa do dono); não
    -- enquanto o adiamento dele está saindo (preparada/enviando): recusado depois de X, ele ainda dá o fim do dia
    -- em X no minuto seguinte (o caso vencido sai do relógio)
    update public.retorno_aberturas a
       set estado = 'vencida', atualizada_em = now()
     where a.id in (select b.id from public.retorno_aberturas b
                     where b.estado = 'aberta'
                       and b.gravada_em <= v_agora
                       and b.prometido_ate is not null
                       and b.cumprida_em is null
                       and coalesce(b.segundo_prazo, b.prometido_ate) < v_agora
                       and not exists (select 1 from public.retorno_saidas s
                                        where s.abertura_id = b.id
                                          and s.tipo = 'adiamento'
                                          and s.estado in ('preparada', 'enviando'))
                     for update skip locked);
    get diagnostics v_n_vencida = row_count;
  exception when others then
    v_erros := v_erros || 6;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 6, 'sqlstate', sqlstate));
  end;

  -- 7. O acorde e o cadastro provisório, decididos no SQL. Exceção num item = recusada/erro, e o próximo segue.
  begin
    for r in
      select s.id, s.tipo, s.abertura_id
        from public.retorno_saidas s
       where s.estado = 'agendada'
         and s.tipo in ('acorde', 'cadastro_provisorio')
         and s.enviar_em <= v_agora
       order by s.enviar_em, s.id
       limit 100
       for update skip locked
    loop
      begin
        if not exists (select 1 from public.retorno_aberturas a where a.id = r.abertura_id and a.estado <> 'fechada') then
          update public.retorno_saidas s
             set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
           where s.id = r.id;
        elsif r.tipo = 'acorde' then
          -- nesta leva o acorde nunca é ligado: é o "eu teria acordado o Gustavo"
          update public.retorno_saidas s
             set estado = 'sombra', modo = 'sombra', decidida_em = v_agora,
                 dados = s.dados || public._retorno_acorde_simulado(v_agora), atualizada_em = now()
           where s.id = r.id;
        else
          v_modo := public._retorno_modo_efetivo(r.id, null, null, v_agora);
          v_cad := public.retorno_cadastro_provisorio(r.abertura_id, v_modo ->> 'modo' = 'ligado');
          if v_cad ->> 'acao' = 'criaria' then
            update public.retorno_saidas s
               set estado = 'sombra', modo = 'sombra', decidida_em = v_agora,
                   dados = s.dados || jsonb_build_object('cadastro', v_cad,
                                                         'sombra_motivo', coalesce(v_modo ->> 'motivo', 'modo')),
                   atualizada_em = now()
             where s.id = r.id;
          elsif v_cad ->> 'acao' = 'criado' then
            update public.retorno_saidas s
               set estado = 'enviada', modo = 'ligado', decidida_em = v_agora, enviada_em = v_agora,
                   dados = s.dados || jsonb_build_object('cadastro', v_cad), atualizada_em = now()
             where s.id = r.id;
          elsif v_cad ->> 'acao' = 'perguntar' then
            update public.retorno_saidas s
               set estado = 'recusada', motivo = 'duplicado_pergunta', decidida_em = v_agora,
                   dados = s.dados || jsonb_build_object('duplicados', v_cad -> 'duplicados'), atualizada_em = now()
             where s.id = r.id;
          else
            update public.retorno_saidas s
               set estado = 'cancelada', motivo = 'sem_nome', decidida_em = v_agora,
                   dados = s.dados || jsonb_build_object('cadastro', v_cad), atualizada_em = now()
             where s.id = r.id;
          end if;
        end if;
        v_n_decididas := v_n_decididas + 1;
      exception when others then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'erro', decidida_em = v_agora,
               dados = s.dados || jsonb_build_object('erro', jsonb_build_object('sqlstate', sqlstate,
                                                                                 'mensagem', left(sqlerrm, 200))),
               atualizada_em = now()
         where s.id = r.id;
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 7, 'saida', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 7;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 7, 'sqlstate', sqlstate));
  end;

  -- 8. As incertas: só conferir na conversa, por 30 min. Nunca há reenvio.
  begin
    for r in
      select s.id, s.chave, s.texto, s.decidida_em
        from public.retorno_saidas s
       where s.estado = 'incerta'
         and s.emissor = 'retorno'
         and s.texto is not null
         and s.decidida_em >= v_agora - v_cfg.incerta_conferir_ate
         and s.decidida_em <= v_agora - interval '10 minutes'
       for update skip locked
    loop
      begin
        select min(w.occurred_at) into v_eco
          from public.whatsapp_messages w
         where public._agenda_chave_telefone(w.phone_normalized) = r.chave
           and w.direction = 'outbound'
           and w.occurred_at >= r.decidida_em
           and w.occurred_at <= v_agora
           and w.body = r.texto;
        if v_eco is not null then
          update public.retorno_saidas s
             set estado = 'enviada', enviada_em = v_eco,
                 dados = s.dados || jsonb_build_object('conferida_na_conversa', v_agora), atualizada_em = now()
           where s.id = r.id;
          v_n_incertas := v_n_incertas + 1;
        end if;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 8, 'saida', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 8;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 8, 'sqlstate', sqlstate));
  end;

  -- 9. Os itens presos, um a um (o erro de um não desfaz os outros):
  --    - preparada (nada saiu): na 1ª vez volta a agendada, atrás das que já venceram; na 2ª, recusada/erro;
  --    - enviando vira incerta (pode ter saído), com os efeitos; o efeito que falha não desfaz a incerta.
  begin
    for r in
      select s.id, s.estado,
             case when coalesce(s.dados ->> 'presas', '') ~ '^[0-9]{1,4}$' then (s.dados ->> 'presas')::integer
                  else 0 end as presas
        from public.retorno_saidas s
       where s.estado in ('preparada', 'enviando') and s.processando_ate < v_agora - interval '5 minutes'
       order by s.processando_ate, s.id
       for update skip locked
    loop
      begin
        if r.estado = 'preparada' and r.presas >= 1 then
          -- a edge falhou duas vezes no mesmo item: nunca volta à frente da fila a cada ~7 min (17/08)
          update public.retorno_saidas s
             set estado = 'recusada', motivo = 'erro', decidida_em = v_agora, processando_ate = null,
                 dados = s.dados || jsonb_build_object('presa', v_agora, 'presas', r.presas + 1), atualizada_em = now()
           where s.id = r.id;
          perform public._retorno_log('vigia', 'retorno_vigia: saída presa de novo na reserva, recusada', 'error',
                                      jsonb_build_object('passo', 9, 'saida', r.id, 'presas', r.presas + 1));
        elsif r.estado = 'preparada' then
          update public.retorno_saidas s
             set estado = 'agendada', processando_ate = null, decidida_em = null,
                 enviar_em = greatest(s.enviar_em, v_agora),
                 dados = s.dados || jsonb_build_object('presa', v_agora, 'presas', r.presas + 1), atualizada_em = now()
           where s.id = r.id;
        else
          update public.retorno_saidas s
             set estado = 'incerta', processando_ate = null,
                 dados = s.dados || jsonb_build_object('presa', v_agora), atualizada_em = now()
           where s.id = r.id;
          begin
            perform public._retorno_aplicar_efeitos(r.id, v_agora);
          exception when others then
            perform public._retorno_log('vigia', 'retorno_vigia: efeitos da saída presa: ' || sqlerrm, 'error',
                                        jsonb_build_object('passo', 9, 'saida', r.id, 'sqlstate', sqlstate));
          end;
        end if;
        v_n_presas := v_n_presas + 1;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 9, 'saida', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 9;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 9, 'sqlstate', sqlstate));
  end;

  -- 10. O rebaixamento automático (E.6), com o grupo do P1.1. Só o sinal das últimas 24 h.
  begin
    v_cfg := public._retorno_cfg();
    if cardinality(v_cfg.tipos_ligados) > 0 then
      v_tirar := '{}';
      for e in
        -- opt-out até 48 h depois de uma enviada do tipo à mesma chave
        select s.tipo, s.id as saida, 'opt_out' as motivo
          from public.retorno_saidas s
         where s.emissor = 'retorno'
           and s.estado = 'enviada'
           and s.tipo = any (v_cfg.tipos_ligados)
           and s.enviada_em > v_agora - interval '72 hours'
           and exists (select 1 from public.whatsapp_blocked_numbers b
                        where b.tipo = 'opt_out'
                          and public._agenda_chave_telefone(b.phone_normalized) = s.chave
                          and b.created_at > s.enviada_em
                          and b.created_at <= s.enviada_em + interval '48 hours'
                          and b.created_at <= v_agora
                          and b.created_at > v_agora - interval '24 hours')
        union all
        -- reclamação até 24 h depois
        select s.tipo, s.id, 'reclamacao'
          from public.retorno_saidas s
         where s.emissor = 'retorno'
           and s.estado = 'enviada'
           and s.tipo = any (v_cfg.tipos_ligados)
           and s.enviada_em > v_agora - interval '48 hours'
           and exists (select 1 from public.whatsapp_messages w
                        where public._agenda_chave_telefone(w.phone_normalized) = s.chave
                          and w.direction = 'inbound'
                          and w.occurred_at > s.enviada_em
                          and w.occurred_at <= s.enviada_em + interval '24 hours'
                          and w.occurred_at <= v_agora
                          and w.occurred_at > v_agora - interval '24 hours'
                          and coalesce((public._retorno_sinais(w.body) ->> 'reclamacao')::boolean, false))
        union all
        -- 3 ou mais recusas do validador do tipo na última hora
        select s.tipo, (array_agg(s.id order by s.decidida_em desc))[1], 'validador'
          from public.retorno_saidas s
         where s.emissor = 'retorno'
           and s.estado = 'recusada'
           and s.motivo = 'validador'
           and s.tipo = any (v_cfg.tipos_ligados)
           and s.decidida_em > v_agora - interval '1 hour'
           and s.decidida_em <= v_agora
         group by s.tipo
        having count(*) >= 3
      loop
        v_tirar := v_tirar || e.tipo;
        perform public._retorno_log('rebaixamento', 'retorno: tipo rebaixado da lista de ligados', 'warn',
                                    jsonb_build_object('tipo', e.tipo, 'saida', e.saida, 'motivo', e.motivo));
      end loop;
      if cardinality(v_tirar) > 0 then
        -- os que dependem do tipo saem junto: sem adiamento ou fim do dia, nenhum recibo; sem o recibo de
        -- número novo, nem coleta; sem a coleta, nem cadastro
        if v_tirar && array['adiamento', 'fim_do_dia']::text[] then
          v_tirar := v_tirar || c_recibos;
        end if;
        if 'recibo_numero_novo' = any (v_tirar) then
          v_tirar := v_tirar || 'coleta_numero_novo'::text;
        end if;
        if 'coleta_numero_novo' = any (v_tirar) then
          v_tirar := v_tirar || 'cadastro_provisorio'::text;
        end if;
        v_novos := array(select t from unnest(v_cfg.tipos_ligados) with ordinality as x(t, n)
                          where not (t = any (v_tirar)) order by n);
        if v_novos is distinct from v_cfg.tipos_ligados then
          update public.retorno_config c set tipos_ligados = v_novos, atualizado_em = now() where c.id;
          v_rebaixados := array(select t from unnest(v_cfg.tipos_ligados) as t where not (t = any (v_novos)));
        end if;
      end if;
    end if;
  exception when others then
    v_erros := v_erros || 10;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 10, 'sqlstate', sqlstate));
  end;

  -- 11–13. Uma vez por dia, no minuto das 04:00 de Brasília.
  if v_diario then
    -- 11. Arquivar o cadastro provisório sem uso (nunca apaga).
    begin
      update public.clients c
         set active = false
       where c.provisorio
         and c.origem = 'retorno'
         and c.active
         and c.created_at < v_agora - v_cfg.cadastro_arquivar_apos
         and not exists (select 1 from public.service_orders o where o.client_id = c.id);
      get diagnostics v_n_arquivados = row_count;
    exception when others then
      v_erros := v_erros || 11;
      perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 11, 'sqlstate', sqlstate));
    end;

    -- 12. A retenção da coleta que não virou cadastro (J.12).
    begin
      update public.retorno_aberturas a
         set coleta = null, atualizada_em = now()
       where a.papel = 'numero_novo'
         and a.coleta is not null
         and a.aberta_em < v_agora - v_cfg.coleta_retencao
         and not exists (select 1 from public.clients c
                          where not c.generico
                            and a.chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone)));
      get diagnostics v_n_k = row_count;
      v_n_retencao := v_n_k;
      update public.whatsapp_leads l
         set coleta = null
       where l.coleta is not null
         and l.status <> 'converted'
         and l.linked_client_id is null
         and l.last_inbound_at < v_agora - v_cfg.coleta_retencao;
      get diagnostics v_n_k = row_count;
      v_n_retencao := v_n_retencao + v_n_k;
    exception when others then
      v_erros := v_erros || 12;
      perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 12, 'sqlstate', sqlstate));
    end;

    -- 13. O alongamento da promessa por faixa (B.4.1), só ligado. Nunca encurta.
    begin
      v_cfg := public._retorno_cfg();
      if v_cfg.modo = 'ligado' then
        for r in
          select a.faixa, count(*)::integer as casos,
                 count(*) filter (where a.cumprida_em is not null and a.cumprida_em <= a.prometido_ate)::integer as no_prazo
            from public.retorno_aberturas a
           where a.faixa = any (c_faixas)
             and a.prometido_ate is not null
             and a.prometido_ate <= v_agora
             and exists (select 1 from public.retorno_saidas s
                          where s.abertura_id = a.id
                            and s.tipo = any (c_recibos)
                            and s.estado = 'enviada'
                            and s.enviada_em > v_agora - v_cfg.alongar_janela
                            and s.enviada_em <= v_agora
                            and s.enviada_em > coalesce((select max(l.em) from public.retorno_alongamentos l
                                                          where l.faixa = a.faixa and l.em <= v_agora),
                                                         '-infinity'::timestamptz))
           group by a.faixa
           order by a.faixa
        loop
          if r.casos < v_cfg.alongar_minimo_casos or r.no_prazo::numeric / r.casos >= v_cfg.alongar_meta then
            continue;
          end if;
          -- a promessa atual da faixa: a calibrada, se legível; senão a da tabela do P3
          v_atual := v_cfg.promessa_faixa -> r.faixa;
          if jsonb_typeof(v_atual) is distinct from 'object'
             or coalesce(v_atual -> 'dias' not in ('0'::jsonb, '1'::jsonb), true)
             or coalesce(v_atual ->> 'hora', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
            v_atual := jsonb_build_object('dias', 0, 'hora', to_char(case
              when r.faixa = 'manha_cedo' and v_cfg.meio_dia_ligado then v_cfg.promessa_meio_dia
              when r.faixa in ('manha_cedo', 'meio', 'pressa') then v_cfg.promessa_fechamento
              else v_cfg.promessa_manha end, 'HH24:MI'));
          end if;
          v_hora_atual := (v_atual ->> 'hora')::time;
          v_dias_atual := (v_atual ->> 'dias')::integer;
          -- o próximo momento: 14h → 19h do mesmo dia; 19h → 10h do próximo dia útil; 10h → 19h do mesmo dia
          v_prox := case
            when v_hora_atual = v_cfg.promessa_meio_dia or v_hora_atual = v_cfg.promessa_manha
              then jsonb_build_object('dias', v_dias_atual, 'hora', to_char(v_cfg.promessa_fechamento, 'HH24:MI'))
            when v_hora_atual = v_cfg.promessa_fechamento and v_dias_atual = 0
              then jsonb_build_object('dias', 1, 'hora', to_char(v_cfg.promessa_manha, 'HH24:MI'))
          end;
          if v_prox is null then
            continue;      -- já no último momento que a calibração aceita
          end if;
          update public.retorno_config c
             set promessa_faixa = c.promessa_faixa || jsonb_build_object(r.faixa, v_prox), atualizado_em = now()
           where c.id
           returning * into v_cfg;
          insert into public.retorno_alongamentos (faixa, de, para, casos, pct, em)
          values (r.faixa, v_atual, v_prox, least(r.casos, 32767), round(r.no_prazo::numeric / r.casos, 4), v_agora);
          v_alongadas := v_alongadas || r.faixa;
          perform public._retorno_log('alongamento', 'retorno: promessa da faixa alongada', 'warn',
                                      jsonb_build_object('faixa', r.faixa, 'de', v_atual, 'para', v_prox,
                                                         'casos', r.casos, 'no_prazo', r.no_prazo));
        end loop;
      end if;
    exception when others then
      v_erros := v_erros || 13;
      perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 13, 'sqlstate', sqlstate));
    end;
  end if;

  -- 14. As contagens.
  return jsonb_build_object(
    'ok', cardinality(v_erros) = 0,
    'rodou', true,
    'erros', to_jsonb(v_erros),
    'disjuntor', v_disjuntor,
    'audios', v_n_audio,
    'respondidas', v_n_resp,
    'fechadas', jsonb_build_object('conteudo', v_n_conteudo, 'silencio', v_n_silencio, 'nada', v_n_nada,
                                   'expirou', v_n_expirou),
    'relogio', jsonb_build_object('acordes', v_n_acorde, 'adiamentos', v_n_adiamento, 'fins_do_dia', v_n_fim,
                                  'vencidas', v_n_vencida),
    'decididas', v_n_decididas,
    'incertas_conferidas', v_n_incertas,
    'presas', v_n_presas,
    'rebaixados', to_jsonb(v_rebaixados),
    'diario', v_diario,
    'arquivados', v_n_arquivados,
    'retencao', v_n_retencao,
    'alongadas', to_jsonb(v_alongadas));
end;
$$;

comment on function public.retorno_vigia(timestamptz) is
  'Retorno F1 (P6.2): o vigia de cada minuto, só SQL: disjuntor pela conexão (liga e desliga), áudio transcrito (triagem de novo), respostas humanas (fecha por conteúdo), fechar (silêncio sem promessa, nada parado, expirou), relógio (acorde, adiamento com X2, fim do dia, vencida), decide acorde e cadastro provisório, confere incertas (sem reenvio), solta presos, rebaixa tipos e, às 04:00, arquiva provisórios, apaga coletas velhas e alonga faixas (só ligado). Cada passo isolado: erro vai ao app_error_logs e os outros seguem. Devolve as contagens.';

revoke all on function public.retorno_vigia(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_vigia(timestamptz) to service_role;
