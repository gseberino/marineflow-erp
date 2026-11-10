-- Agenda de Produção, correção do NOVO-agenda-98 (10/11/2026): a mensagem ao cliente de OS concluída ("ficou pronto", o lembrete
-- e o pós-serviço) não perde mais a pergunta do OK do dono.
-- (1 função recriada; nenhuma tabela, coluna, lista fechada, dado, cron, edge function ou tela muda)
--
-- NÃO APLICADA. Este arquivo foi MONTADO por D:/IA-HBR/agenda-pesquisa/c98/montar-migration.mjs: a recriada é o corpo da
-- definição MAIS NOVA de _agenda_vigia_limpeza, a de 20261031100300_agenda_fase7a_perguntas.sql (conferido a cada montagem, pelo nome das migrations, na main e
-- nos ramos session/agenda-7e-int e session/agenda-7g, que não a recriam). A mudança está só no bloco
-- "-- CORREÇÃO 10/11 (98): … -- CORREÇÃO 10/11 (98): fim"; tirado o bloco, a definição é a da origem byte a byte (o montador
-- não grava sem isso, e o C0 de supabase/tests/agenda_correcao_98.sql confere de novo, no banco e no texto). Quem recriar
-- _agenda_vigia_limpeza depois copia DESTA migration (fase7-registro.md).
--
-- O ACHADO (NOVO-agenda-98, Fase 7d, Onda 3; é da Fase 5): o "ficou pronto" (pronto), o lembrete (pronto_lembrete) e o
-- pós-serviço (pos_servico), enquanto o tipo pede o OK do dono, nascem aguardando_dono com a pergunta cliente_aprovar. A OS já
-- saiu da carteira (concluída), e _agenda_vigia_limpeza fechava a pergunta no tique seguinte com "a OS saiu da carteira". Depois disso,
-- *manda cliente X* e *segura cliente X* respondiam "Essa pergunta já foi respondida ou resolvida.", e a mensagem ficava em
-- *agenda clientes* até vencer, sem sair. O lado era o seguro (nada saía sem o dono), mas o dono não conseguia aprovar, e o
-- texto dizia que conseguia. Em produção: a OS-00104 (a pronto de 06/11 venceu assim).
--
-- O QUE MUDA: a limpeza da vigia (passo 1 de agenda_vigiar) poupa a pergunta cliente_aprovar enquanto a mensagem dela está
-- aguardando_dono. Quando a mensagem sai dali, o caminho de sempre fecha a pergunta: *manda* e *segura*
-- (_agenda_cliente_decidir, respondida), o cancelamento (_agenda_cliente_cancelar, descartada), a validade (a limpeza e o passo
-- fila, vencida). Se uma pergunta ficar aberta com a mensagem já fora de aguardando_dono, a regra de antes volta a valer na
-- mesma limpeza: nenhuma fica órfã.
-- O QUE NÃO MUDA: nenhuma outra pergunta (o bloco só olha cliente_aprovar, e só zera o motivo); a prontidão da OS é calculada
-- e guardada no cache da limpeza como antes; a ordem, as contagens das outras e o vencimento pela validade; o motor, o aviso, o
-- fechamento e as mensagens. Peso: uma consulta por pergunta cliente_aprovar que a regra de antes fecharia (nenhuma consulta
-- nova para as outras).
--
-- Ordem de ligar: depois da 20261109101900 (a produção de 05aed8e0). Sem deploy de edge function (nenhum TS muda). Vale ao
-- entrar, em qualquer modo (a pergunta cliente_aprovar só existe com modo_cliente ligado). Aplicar com o OK nomeado do dono.
-- Prova: supabase/tests/agenda_correcao_98.sql (bancada). Roteiro: fila-do-dono/correcao-98-publicar.md.
--
-- DESFAZER: recriar _agenda_vigia_limpeza com a definição, o comment e o revoke de 20261031100300_agenda_fase7a_perguntas.sql (o mesmo texto sem o bloco). As
-- perguntas poupadas enquanto valeu fecham pela regra de antes na limpeza seguinte ("a OS saiu da carteira").
--
-- IDEMPOTENTE: create or replace function, comment e revoke.

-- _agenda_vigia_limpeza (de 20261031100300_agenda_fase7a_perguntas.sql)
create or replace function public._agenda_vigia_limpeza(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_obs   int := 0;
  v_exp   int := 0;
  v_venc  int := 0;
  v_res   int := 0;
  r       record;
  v_pront jsonb;
  v_cache jsonb := '{}'::jsonb;
  v_item  jsonb;
  v_mot   text;
  v_dono_padrao boolean;
begin
  for r in select p.id, p.versao_base, p.expira_em, p.modo from public.agenda_propostas p
            where p.estado = 'aberta' order by p.criada_em, p.id loop
    if r.modo = 'ligado' and r.versao_base < cf.versao_plano then
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'a agenda mudou' where id = r.id;
      v_obs := v_obs + 1;
    elsif r.expira_em < p_agora then
      update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou da validade' where id = r.id;
      v_exp := v_exp + 1;
    else
      continue;
    end if;
    delete from public.agenda_alocacoes where proposta_id = r.id and estado = 'proposta';
  end loop;

  update public.agenda_perguntas q set estado = 'vencida'
   where q.estado = 'aberta' and q.expira_em is not null and q.expira_em < p_agora;
  get diagnostics v_venc = row_count;
  -- CORREÇÃO 29/10 (P3): a pergunta feita em teste (modo sombra) não fica aberta quando o modo que a faz já está ligado
  -- (_agenda_modo_da_pergunta): ela nunca aparece ao dono e, com a mesma chave aberta também em ligado (o índice único é por
  -- chave e modo), a lista parecia ter a pergunta duas vezes (28/10: o cadastro do Mateus e os prazos dos fornecedores, uma
  -- das 17:45 em teste e outra das 20:15 já ligada). Fecha como resolvida, com o motivo; a de verdade continua.
  with f as (
    update public.agenda_perguntas q
       set estado = 'resolvida', resolvida_motivo = 'era do teste: com a agenda ligada, vale só a pergunta de verdade'
     where q.estado = 'aberta' and q.modo = 'sombra' and public._agenda_modo_da_pergunta(q.tipo, q.chave) = 'ligado'
    returning 1)
  select v_res + count(*)::int into v_res from f;
  -- CORREÇÃO 29/10 (P3): fim

  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  for r in select q.* from public.agenda_perguntas q where q.estado = 'aberta' order by q.criada_em, q.id loop
    v_mot := null;
    if r.tipo = 'conferencia' then
      if not exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia and a.resultado is null) then
        v_mot := case
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia) then 'o dia saiu do plano'
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia
                              and a.resultado is distinct from 'sem_registro') then 'o dia ficou sem registro'
          else 'o dia já está anotado' end;
      end if;
    elsif r.tipo = 'padrao_do_dono' then
      if v_dono_padrao then v_mot := 'você disse os dias em que fica em campo'; end if;
    elsif r.service_order_id is not null then
      v_pront := v_cache -> r.service_order_id::text;
      if v_pront is null then
        v_pront := public.os_prontidao(r.service_order_id, p_hoje);
        v_cache := v_cache || jsonb_build_object(r.service_order_id::text, v_pront);
      end if;
      if v_pront ->> 'estado' in ('concluida', 'fora_da_carteira') then
        v_mot := 'a OS saiu da carteira';
      elsif r.tipo = 'chegou' and split_part(r.chave, ':', 2) = 'fixado' then
        -- a véspera do dia marcado pelo dono (chegou:fixado:<os>:<dia>)
        if r.dia < p_hoje then
          v_mot := 'o dia passou';
        elsif not exists (select 1 from public.agenda_alocacoes a
                           where a.service_order_id = r.service_order_id and a.dia = r.dia and a.estado in ('publicada', 'fixada')
                             and a.tipo <> 'reserva' and a.fixado_por = 'dono') then
          v_mot := 'o dia saiu do plano';
        else
          v_item := public._agenda_classe_da_os(v_pront, public.agenda_meios_da_os(r.service_order_id, p_hoje), p_hoje, false, false);
          if public._agenda_aviso_do_material(v_pront,
               coalesce(v_item ->> 'condicao_tipo',
                        case when v_item ->> 'motivo' = 'material' and v_pront #>> '{material,estado}' = 'sem_previsao' then 'material' end),
               v_item ->> 'texto', r.dia) is null then
            v_mot := 'o material ficou garantido para o dia';
          end if;
        end if;
      -- FASE 4: o chegou? que a pergunta do fornecedor abriu ("Recebeu o compressor?", chegou:fornecedor:<linha>:<dia>):
      -- resolve quando a linha chega ou sai da OS; senão fica até vencer (material_pergunta_validade). Sem este bloco a
      -- regra de baixo leria "fornecedor" como o item e a resolveria no mesmo tique ("a peça saiu da OS").
      elsif r.tipo = 'chegou' and split_part(r.chave, ':', 2) = 'fornecedor' then
        select e into v_item from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
         where e ->> 'id' = split_part(r.chave, ':', 3) limit 1;
        if v_item is null then
          v_mot := 'a peça saiu da OS';
        elsif v_item ->> 'situacao' = 'na_mao' then
          v_mot := format('"%s" chegou', v_item ->> 'curto');
        end if;
      -- FASE 4: fim
      elsif r.tipo = 'chegou' then
        select e into v_item from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
         where coalesce(e ->> 'id', e ->> 'linha') = split_part(r.chave, ':', 2) limit 1;
        if v_item is null then
          v_mot := 'a peça saiu da OS';
        elsif v_item ->> 'situacao' = 'na_mao' then
          v_mot := format('"%s" chegou', v_item ->> 'curto');
        elsif not coalesce((v_item ->> 'atrasado')::boolean, false) or (v_item ->> 'data') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'a previsão mudou';
        end if;
      elsif r.tipo = 'parada' then
        if v_pront ->> 'estado' <> 'parada' then v_mot := 'a OS voltou a andar'; end if;
      elsif r.tipo = 'estouro' then
        if v_pront ->> 'status' <> 'in_progress' then
          v_mot := 'a OS não está mais em andamento';
        elsif (public.agenda_meios_da_os(r.service_order_id, p_hoje) ->> 'total') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'o combinado mudou';
        end if;
      elsif r.tipo = 'duracao' then
        if exists (select 1 from public.os_planejamento pl
                    where pl.service_order_id = r.service_order_id and pl.dias is not null
                      and pl.estimativa_fonte in ('dono', 'aceita')) then
          v_mot := 'você disse os dias';
        end if;
      elsif r.tipo = 'material_conferir' then
        if (v_pront #>> '{material,estado}') is distinct from 'nao_conferido' then v_mot := 'o material foi conferido'; end if;
      -- FASE 7: (7a P4) a pergunta do gestor antes de marcar (situacao, estimativa): resolve quando o dono disse os dias (pelo
      -- *grava*, pela tela ou pela opção 1) ou quando a pergunta que o gestor faria agora para a OS não é mais esta — o motivo
      -- mudou ou sumiu (a OS ganhou plano, passou a esperar o cliente, o orçamento mudou). Com o gestor fora de ligado (sombra,
      -- *gestor, só propor*) ou com a pergunta em teste, o motivo não é reavaliado: só os dias ditos a resolvem.
      elsif r.tipo in ('situacao', 'estimativa') then
        if exists (select 1 from public.os_planejamento pl where pl.service_order_id = r.service_order_id and pl.dias is not null) then
          v_mot := 'você respondeu';
        elsif r.modo = 'ligado' and public._agenda_gestor_modo('marcar') = 'ligado'
              and (public._agenda_gestor_perguntas_da_os(r.service_order_id, p_hoje, p_agora, true) ->> 'chave') is distinct from r.chave then
          v_mot := 'não precisa mais';
        end if;
      -- FASE 7: fim
      end if;
    end if;
    -- CORREÇÃO 29/10 (revisão): (1) a pergunta da reserva ("Lenine tem peça a comprar? Guardei lugar a partir de qui
    -- 05/11; preciso saber até qua 04/11.") não fica aberta quando a reserva saiu (cancelada, solta ou vencida): o texto diz um
    -- lugar que não existe mais, e o fechamento e o aviso a repetiam. Só a de verdade (ligado), com a chave que
    -- _agenda_vigia_duracao_material dá (duracao:<os>, material_conferir:<os>); se a OS ganhar outra reserva, a pergunta nasce de
    -- novo com os dias novos. (2) a pergunta da equipe sem dias resolve quando alguém da equipe volta a ter dias na agenda.
    if v_mot is null and r.modo = 'ligado' and r.tipo in ('duracao', 'material_conferir') and r.service_order_id is not null
       and r.chave = r.tipo || ':' || r.service_order_id
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = r.service_order_id and a.tipo = 'reserva' and a.reserva_de = 'condicionada'
                          and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje) then
      v_mot := 'a reserva saiu: o lugar que eu tinha guardado não existe mais';
    end if;
    if v_mot is null and r.tipo = 'equipe_sem_dias' and public._agenda_equipe_tem_dias(p_hoje) then
      v_mot := 'alguém da equipe voltou a ter dias na agenda';
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
    -- CORREÇÃO 10/11 (98): a pergunta do OK de uma mensagem ao cliente (cliente_aprovar, chave cliente_aprovar:<mensagem>) fica
    -- aberta enquanto a mensagem dela espera o dono (aguardando_dono). O "ficou pronto", o lembrete e o pós-serviço nascem com a OS
    -- já concluída, e a regra "a OS saiu da carteira", acima, fechava a pergunta no tique seguinte: *manda cliente* e *segura
    -- cliente* respondiam "Essa pergunta já foi respondida ou resolvida." e a mensagem vencia sem sair (NOVO-agenda-98). Quando a
    -- mensagem sai de aguardando_dono, quem a tira fecha a pergunta (_agenda_cliente_decidir: mandada ou segurada;
    -- _agenda_cliente_cancelar: recusada; a validade, acima, e o passo fila: vencida); se ainda sobrar aberta, a regra de antes
    -- volta a valer nesta mesma limpeza. Só cliente_aprovar: nenhuma outra pergunta muda, e a prontidão da OS segue calculada
    -- (e guardada) como antes.
    if v_mot is not null and r.tipo = 'cliente_aprovar'
       and exists (select 1 from public.agenda_cliente_mensagens m where m.pergunta_id = r.id and m.estado = 'aguardando_dono') then
      v_mot := null;
    end if;
    -- CORREÇÃO 10/11 (98): fim
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200) where id = r.id;
      v_res := v_res + 1;
    end if;
  end loop;
  return jsonb_build_object('obsoletas', v_obs, 'expiradas', v_exp, 'vencidas', v_venc, 'resolvidas', v_res);
end;
$function$;

comment on function public._agenda_vigia_limpeza(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 1: propostas abertas de outra versão do plano (obsoleta, só ligado) ou vencidas (expirada), com as alocações de proposta; perguntas vencidas; perguntas cuja condição sumiu (resolvida, com o fato: chegou, voltou a andar, saiu da carteira, o dia está anotado…). Fase 4 (P4): o chegou? do fornecedor (chegou:fornecedor:<linha>:<dia>) só se resolve quando a linha chega ou sai da OS. CORREÇÃO 29/10 (P3): a pergunta aberta em sombra (feita em teste) cujo modo já está ligado (_agenda_modo_da_pergunta) fecha como resolvida, "era do teste: com a agenda ligada, vale só a pergunta de verdade" (conta em resolvidas); a ligada de mesma chave continua — a lista para de parecer ter a pergunta duas vezes. CORREÇÃO 29/10 (revisão): (1) a pergunta da reserva (duracao:<os>, material_conferir:<os>, ligado) resolve quando a OS não tem mais reserva condicionada publicada de hoje em diante ("a reserva saiu"); (2) equipe_sem_dias resolve quando _agenda_equipe_tem_dias. FASE 7 (7a P4): a pergunta do gestor situacao/estimativa aberta resolve quando a OS ganhou os dias ("você respondeu") ou, com o gestor ligado e a pergunta de verdade, quando a pergunta que ele faria agora para a OS não é mais esta (_agenda_gestor_perguntas_da_os seco: "não precisa mais"); a OS que saiu da carteira já resolvia. CORREÇÃO 10/11 (98): a pergunta cliente_aprovar (o OK de uma mensagem ao cliente) fica aberta enquanto a mensagem dela espera o dono (aguardando_dono): a OS concluída ou fora da carteira não a fecha mais; quem tira a mensagem dali (mandada, segurada, cancelada ou vencida) fecha a pergunta, e a que sobrar aberta volta à regra de antes (NOVO-agenda-98).';

-- ── A porta ─────────────────────────────────────────────────────────────────────────────────────────────
-- A de antes, repetida para a migration valer sozinha (create or replace não mexe em grant): ninguém de fora, só a agenda_vigiar
-- (definer) a chama.
revoke all on function public._agenda_vigia_limpeza(date, timestamptz) from public, anon, authenticated, service_role;
