-- Agenda de Produção, Fase 6 (P7): o acabamento da Fase 5 — os textos (spec-fase6 §5.7, §6.1 e §6.4).
-- (0 funções novas; 12 recriadas; nenhuma tabela, coluna, CHECK nem parâmetro novo)
--
-- NÃO APLICADA. Montada por scratchpad/agenda-pesquisa/f6p7/montar-migration.mjs (nunca editar este .sql: edite as partes ou o
-- montador). Cada função recriada é o corpo da definição MAIS NOVA (conferido com grep a cada montagem), com as mudanças só
-- em blocos "-- FASE 6: (P7) … -- FASE 6: fim"; fora deles nenhuma linha muda (o A4 do teste agenda_fase6_acabamento.sql
-- confere). Quem recriar de novo qualquer uma delas copia DESTA migration.
--
-- O que muda:
--   1. Ao dono, o nome do cliente sem artigo nem possessivo antes ("Flávio confirmou ter 03/11.", "O plano de Nelson ainda
--      cabe…", "Não há data dita para Giancarlo…") e sem "ele"/"a ele" ("não mando mais nada", "a data dita", "o dia
--      pedido", "não entendi o pedido", "só o cliente pode pedir para voltar", "Quando a resposta for SIM", "O que foi dito ao
--      cliente: …"). O ralo é _agenda_cliente_sem_artigo (C2): ela passa a trocar também as frases com o pronome (a tabela
--      fixa do bloco FASE 6 dela), então todo texto que já passava por ela (as perguntas, os acordes, a decisão, o *manda* e
--      o *segura cliente*, a preparada, a resposta que vai ao dono) sai certo sem recriar quem a chama. Os textos que não
--      passavam por ela (as ações da resposta e do *desfaz*, as recusas de cliente_avisar, o foco clientes, o cartão, o que
--      eu teria feito em teste e o botão "Pedir confirmação") ganham o texto novo no bloco.
--   2. Ao cliente (os únicos dois textos ao cliente que mudam; vão à lista do dono para aprovar antes de ligar):
--      · o M6 remarcado na forma "fim" diz quantos dias o fim andou — n = agenda_du_entre(dito_ate, fim): "Vanderlei, o
--        serviço no Mar Azul vai terminar um dia depois do previsto: agora fica de terça (03/11) até quinta (05/11). Desculpe
--        pela mudança. Pode ser? Responda SIM ou me diga outro dia." (n ≥ 2: "… vai terminar 3 dias depois do previsto: …");
--        o fim que não passa do dia dito (n < 1) não vira texto (22023, como todo dado que falta);
--      · o M6 "peça sem data" sem a repetição: "Nelson, quero te avisar com antecedência: ainda faltam peças sem data de
--        chegada, então o serviço no seu veleiro, que estava para quinta (05/11), vai atrasar. Te digo a nova data assim que
--        elas chegarem. Se isso atrapalhar algum plano seu, me diga."
--   A faixa, as datas, a chave, o modo, o teto, a janela e a fila não mudam. Nenhuma mensagem nova a terceiros.
--
-- O RISCO (spec-fase6 §9, P7): a revalidação refaz o texto com os dados do registro e compara com o texto registrado. Um M6
-- remarcado na forma fim ou um M6 "peça sem data" REGISTRADO E NÃO ENVIADO antes desta migration sai recusado como
-- "desatualizada" (o texto de agora é o novo). A regra não muda. Saída segura: aplicar com modo_cliente fora de ligado (em
-- sombra nada sai, e a recusa da sombra não pesa), ou conferir antes que não há nenhum vivo
--   select count(*) from agenda_cliente_mensagens
--    where tipo = 'pode_atrasar' and modo = 'ligado' and estado in ('registrada', 'aguardando_dono', 'enfileirada')
--      and (variante = 'peca_sem_data' or base #>> '{dados,forma}' = 'fim');
-- (= 0 → aplicar), ou aceitar perder esse aviso: a chave do mesmo dia (agenda-cliente:pode_atrasar:<os>:<faixa_de>) impede
-- o novo registro, e a recusa "desatualizada" não abre o "não consegui avisar" ao dono (C2, item 3b). Só volta a avisar
-- quando o risco mudar de faixa.
--
-- O risco que já existia (C2) e continua: _agenda_cliente_sem_artigo troca o 1º nome do cliente daquela OS depois de "O ",
-- "ao ", "do " e "o "; um nome igual a uma palavra comum perderia o artigo onde não devia. Os textos novos dos blocos foram
-- escritos já sem o artigo (não dependem da troca), e a tabela dos pronomes não usa o nome.
--
-- DESFAZER: recriar cada função com o corpo da migration de onde ela foi copiada (a linha "-- <nome> (de <arquivo>)" acima de
-- cada uma), ou seja, rodar de novo só aquela definição; nenhum dado muda nesta migration.

-- ── 1. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 6: (P7)") ───────────────
-- Fora dos blocos nenhuma linha muda (o A4 do teste confere). Quem recriar de novo qualquer uma delas copia DESTA migration.
-- _agenda_cliente_sem_artigo (de 20261028100800_agenda_fase5_correcao_rodada.sql)
create or replace function public._agenda_cliente_sem_artigo(p_texto text, p_os uuid)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_nome text;
  v_re   text;
  v      text := p_texto;
begin
  -- FASE 6: (P7) o texto ao dono também sem "ele"/"a ele" (spec-fase6 §6.4): as frases dos textos da Fase 5 que falam do
  -- cliente pelo pronome trocam, uma a uma, pela tabela fixa abaixo ("não mando mais nada a ele" → "não mando mais nada",
  -- "a data que ele ouviu" → "a data dita", "não entendi o que ele quer" → "não entendi o pedido"…). A troca não usa o
  -- nome (vale também sem a OS), e o texto do cliente citado entre aspas não tem nenhuma destas frases.
  declare
    v_par record;
  begin
    for v_par in
      select t.de, t.para from (values
        (1, 'não mando mais nada a ele', 'não mando mais nada'),
        (2, 'não tenho como mandar a ele', 'não tenho como mandar'),
        (3, 'eu teria parado as mensagens a ele', 'eu teria parado as mensagens'),
        (4, 'Se você disse uma data a ele, me conte', 'Se você disse uma data, me conte'),
        (5, 'O que foi dito a ele', 'O que foi dito ao cliente'),
        (6, 'A data que ele ouviu', 'A data dita'),
        (7, 'a data que ele ouviu', 'a data dita'),
        (8, 'o dia que ele pediu', 'o dia pedido'),
        (9, 'não entendi o que ele quer', 'não entendi o pedido'),
        (10, 'só ele pode pedir para voltar', 'só o cliente pode pedir para voltar'),
        (11, 'Quando ele responder SIM', 'Quando a resposta for SIM'),
        (12, 'combine a entrega com ele', 'combine a entrega com o cliente'),
        (13, 'ele já recebeu as mensagens que cabem', 'o cliente já recebeu as mensagens que cabem'),
        (14, 'ele já tinha recebido as mensagens que cabem', 'o cliente já tinha recebido as mensagens que cabem'),
        (15, 'ele pediu para não receber mensagens', 'o cliente pediu para não receber mensagens'),
        (16, 'ele não escreveu para a HBR', 'o cliente não escreveu para a HBR'),
        (17, 'ele tinha acabado de receber outra', 'o cliente tinha acabado de receber outra'),
        (18, 'resposta dele', 'resposta do cliente'),
        (19, 'Ele confirmou', 'O cliente confirmou')
      ) t(n, de, para) order by t.n
    loop
      p_texto := replace(p_texto, v_par.de, v_par.para);
    end loop;
  end;
  v := p_texto;
  -- FASE 6: fim
  if p_texto is null or p_os is null then
    return p_texto;
  end if;
  select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) into v_nome
    from public.service_orders so join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  if coalesce(btrim(v_nome), '') = '' then
    return p_texto;
  end if;
  -- o nome como expressão regular (os caracteres especiais escapados)
  v_re := regexp_replace(v_nome, '([][\\.^$*+?(){}|-])', '\\\1', 'g');
  v := regexp_replace(v, '\mO ' || v_re || '\M', v_nome, 'g');
  v := regexp_replace(v, '\mao ' || v_re || '\M', 'para ' || v_nome, 'g');
  v := regexp_replace(v, '\mdo ' || v_re || '\M', 'de ' || v_nome, 'g');
  v := regexp_replace(v, '\mo ' || v_re || '\M', v_nome, 'g');
  return v;
end;
$function$;

comment on function public._agenda_cliente_sem_artigo(text, uuid) is
  'Agenda de Produção (Fase 5, correção C2, item 15): o texto ao dono sem artigo antes do 1º nome do cliente da OS (não há campo de gênero) — "O Flávio respondeu" → "Flávio respondeu", "ao Nelson" → "para Nelson", "do Nelson" → "de Nelson", "o Nelson" → "Nelson". Só o nome inteiro do cliente daquela OS muda. Interna (sem grant): as perguntas e os acordes da mensagem ao cliente (_agenda_cliente_perguntar, _agenda_cliente_acorde), a decisão, o envio e a sombra a chamam. FASE 6 (P7): também sem "ele"/"a ele" — a tabela fixa das frases da Fase 5 (spec-fase6 §6.4: "não mando mais nada a ele" → "não mando mais nada", "a data que ele ouviu" → "a data dita", "o dia que ele pediu" → "o dia pedido", "não entendi o que ele quer" → "não entendi o pedido", "só ele pode pedir para voltar" → "só o cliente pode pedir para voltar", "Quando ele responder SIM" → "Quando a resposta for SIM", "O que foi dito a ele" → "O que foi dito ao cliente", "Ele confirmou" → "O cliente confirmou"…), sem depender do nome nem da OS.';

-- _agenda_cliente_texto (de 20261028100800_agenda_fase5_correcao_rodada.sql)
create or replace function public._agenda_cliente_texto(p_tipo text, p_variante text, p_os uuid, p_dados jsonb,
                                                        p_hoje date default public._hoje_brt())
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  x        jsonb := public._agenda_cliente_contexto(p_os, p_hoje);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  v_var    text := nullif(btrim(coalesce(p_variante, '')), '');
  v_nome   text := x ->> 'nome';
  v_prim   boolean := coalesce((d ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  v_envio  date := coalesce((d ->> 'envio')::date, p_hoje);
  v_dia    date := coalesce((d ->> 'dia')::date, (x ->> 'dia')::date);
  v_fim    date := coalesce((d ->> 'fim')::date, (x ->> 'fim')::date);
  v_n      int := coalesce((d ->> 'n')::int, (x ->> 'n_dias')::int);
  v_serv   text := x ->> 'servico';
  v_art    text := x ->> 'servico_artigo';
  v_esta   text;
  v_jan    text;
  v_dito_de  date;
  v_dito_ate date;
  v_assin  text;
  v_abre   text;
  v_resto  text;
  v_falta  text;
begin
  if p_tipo is null or p_tipo not in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                      'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia') then
    raise exception using errcode = '22023', message = format('Tipo de mensagem ao cliente desconhecido: %s.', p_tipo);
  end if;
  if p_tipo = 'confirmar' then
    v_var := coalesce(v_var, case when v_prim then 'primeira' else 'seguinte' end);
  end if;
  -- CORREÇÃO FASE 5: os dados novos da correção C2 — a saudação (item 12: "Bom dia" ou "Boa tarde", da hora do envio) e a
  -- forma "fim" do aviso remarcado (item 6) — só valem onde existem
  if d ? 'saudacao' and coalesce(d ->> 'saudacao', '') not in ('Bom dia', 'Boa tarde') then
    raise exception using errcode = '22023', message = format('Saudação %s não existe na mensagem ao cliente.', d ->> 'saudacao');
  end if;
  if d ? 'forma' and (p_tipo <> 'pode_atrasar' or v_var is distinct from 'remarcado' or coalesce(d ->> 'forma', '') <> 'fim') then
    raise exception using errcode = '22023',
      message = format('A forma %s não existe na mensagem %s.', coalesce(d ->> 'forma', '(nenhuma)'), p_tipo);
  end if;
  -- (item 8) o aviso de atraso com peça crítica ainda sem data de chegada (variante peca_sem_data, d09): nenhuma data — nem
  -- a da peça, nem a nova do serviço —, só o que o cliente ouviu ("que estava para quinta (05/11)")
  if p_tipo = 'pode_atrasar' and v_var = 'peca_sem_data' then
    if v_nome is null then
      raise exception using errcode = '22023', message = 'Falta o nome do cliente para a mensagem pode_atrasar ao cliente.';
    end if;
    if d ? 'dito_de' or d ? 'dito_ate' then
      v_dito_de := (d ->> 'dito_de')::date; v_dito_ate := (d ->> 'dito_ate')::date;
    elsif d ? 'dia_dito' then
      v_dito_de := (d ->> 'dia_dito')::date; v_dito_ate := v_dito_de;
    else
      v_dito_de := (x #>> '{prometido,de}')::date; v_dito_ate := (x #>> '{prometido,ate}')::date;
    end if;
    if coalesce(v_dito_de, v_dito_ate) is null then
      raise exception using errcode = '22023', message = 'Falta o dia dito ao cliente para a mensagem pode_atrasar ao cliente.';
    end if;
    v_resto := format('quero te avisar com antecedência: ainda faltam peças %s sem data de chegada, então %s, que estava %s, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.',
                      x ->> 'do_servico', v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true));
    -- FASE 6: (P7) sem a repetição (spec-fase6 §6.1): o serviço já vem logo depois ("ainda faltam peças sem data de chegada,
    -- então o serviço no seu veleiro, …"). Texto novo ao cliente: vai à lista do dono para aprovar antes de ligar
    v_resto := format('quero te avisar com antecedência: ainda faltam peças sem data de chegada, então %s, que estava %s, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.',
                      v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true));
    -- FASE 6: fim
    if v_prim then
      return format('Olá, %s! %s %s', v_nome,
                    case when x ->> 'dono' is not null then format('Aqui é o %s, da %s.', x ->> 'dono', x ->> 'empresa')
                         else format('Aqui é da %s.', x ->> 'empresa') end,
                    upper(left(v_resto, 1)) || substr(v_resto, 2));
    end if;
    return v_nome || ', ' || v_resto;
  end if;
  -- CORREÇÃO FASE 5: fim
  if (p_tipo = 'confirmar' and v_var not in ('primeira', 'seguinte', 'unico'))
     or (p_tipo = 'pode_atrasar' and coalesce(v_var, '') not in ('peca', 'execucao', 'remarcado'))
     or (p_tipo = 'andamento' and coalesce(v_var, '') not in ('primeiro_dia', 'semanal'))
     or (p_tipo = 'mudanca_no_dia' and coalesce(v_var, '') not in ('clima', 'equipe', 'geral'))
     or (p_tipo in ('vespera', 'acesso', 'material_chegou', 'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico')
         and v_var is not null) then
    raise exception using errcode = '22023', message = format('Variante %s não existe na mensagem %s.', coalesce(v_var, '(nenhuma)'), p_tipo);
  end if;

  v_jan := case d ->> 'janela' when 'manha' then 'pela manhã' when 'tarde' then 'à tarde' when 'dia' then 'o dia todo'
           else public._agenda_cliente_janela(p_os, v_dia) end;
  v_esta := case when v_art in ('os', 'as') then 'estão' else 'está' end;
  if d ? 'dito_de' or d ? 'dito_ate' then
    v_dito_de := (d ->> 'dito_de')::date; v_dito_ate := (d ->> 'dito_ate')::date;
  elsif d ? 'dia_dito' then
    v_dito_de := (d ->> 'dia_dito')::date; v_dito_ate := v_dito_de;
  else
    v_dito_de := (x #>> '{prometido,de}')::date; v_dito_ate := (x #>> '{prometido,ate}')::date;
  end if;

  -- O que cada modelo precisa (o 1º que faltar).
  v_falta := case
    when v_nome is null then 'o nome do cliente'
    when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then
      case when v_dia is null then 'o dia' when v_jan is null then 'a parte do dia (as alocações do dia)'
           when p_tipo = 'confirmar' and v_var <> 'unico' and coalesce(v_n, 0) < 1 then 'os dias de trabalho'
           when p_tipo = 'mudanca_no_dia' and coalesce(d ->> 'quando', '') not in ('hoje', 'amanhã') then 'o quando (hoje ou amanhã)'
           when p_tipo = 'pode_atrasar' and coalesce(v_dito_de, v_dito_ate) is null then 'o dia dito ao cliente' end
    when p_tipo = 'pode_atrasar' and v_var = 'peca' then
      case when coalesce((d ->> 'peca_de')::date, (d ->> 'peca_ate')::date) is null then 'a previsão da peça'
           when coalesce((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date) is null then 'a faixa nova'
           when coalesce(v_dito_de, v_dito_ate) is null then 'o dia dito ao cliente' end
    when p_tipo = 'pode_atrasar' and v_var = 'execucao' then
      case when coalesce((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date) is null then 'a faixa nova' end
    when p_tipo = 'andamento' then
      case when v_fim is null then 'o fim previsto'
           when v_var = 'semanal' and ((d ->> 'n_feitos') is null or coalesce(v_n, 0) < 1) then 'os dias feitos e o total'
           when v_var = 'primeiro_dia' and coalesce(d ->> 'quando', 'hoje') not in ('hoje', 'ontem') then 'o quando (hoje ou ontem)' end
  end;
  if v_falta is not null then
    raise exception using errcode = '22023', message = format('Falta %s para a mensagem %s ao cliente.', v_falta, p_tipo);
  end if;

  v_assin := case when x ->> 'dono' is not null then format('Aqui é o %s, da %s.', x ->> 'dono', x ->> 'empresa')
                  else format('Aqui é da %s.', x ->> 'empresa') end;

  -- O corpo e como ele abre: 'nome' ("{nome}, …"), 'bom_dia' ("Bom dia, {nome}! …"), 'bom_dia_ponto' ("Bom dia, {nome}.
  -- …"), 'boa_noticia' ("Boa notícia, {nome}: …") ou 'pronto' (o M1 primeira e seguinte, inteiros).
  case p_tipo
    when 'confirmar' then
      if v_var = 'primeira' then
        v_abre := 'pronto';
        v_resto := format('Olá, %s! %s Conseguimos encaixar %s para %s, %s, com previsão de %s de trabalho. Pode ser? Responda SIM para confirmar, ou me diga um dia melhor. A partir de agora te mando por aqui as novidades do serviço.',
                          v_nome, v_assin, v_serv, public._agenda_cliente_dia(v_dia), v_jan,
                          v_n || case when v_n = 1 then ' dia' else ' dias' end);
      elsif v_var = 'seguinte' then
        v_abre := 'pronto';
        v_resto := format('%s, conseguimos encaixar %s para %s, %s, com previsão de %s. Pode ser? Responda SIM ou me diga um dia melhor.',
                          v_nome, v_serv, public._agenda_cliente_dia(v_dia), v_jan,
                          v_n || case when v_n = 1 then ' dia' else ' dias' end);
      else
        v_abre := 'nome';
        v_resto := format('%s fica para %s, %s%s. Pode ser? Responda SIM, ou me diga se algo mudou.',
                          v_serv, public._agenda_cliente_dia(v_dia), v_jan, x ->> 'local');
      end if;
    when 'vespera' then
      v_abre := 'bom_dia';
      v_resto := format('%s chegamos %s para %s%s. Está tudo certo para recebermos? Responda SIM, ou me avise se algo mudou.',
                        public._agenda_cliente_dia_relativo(v_dia, v_envio), v_jan, v_serv, x ->> 'local');
    when 'acesso' then
      v_abre := 'bom_dia';
      v_resto := format('%s chegamos %s para %s. Para não perdermos a viagem: onde %s vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.',
                        public._agenda_cliente_dia_relativo(v_dia, v_envio), v_jan, v_serv, x ->> 'o_bem');
    when 'material_chegou' then
      v_abre := 'boa_noticia';
      v_resto := format('o material %s chegou e já foi conferido. Podemos começar %s, %s? Responda SIM, ou me diga um dia melhor.',
                        x ->> 'do_servico', public._agenda_cliente_dia(v_dia), v_jan);
    when 'pode_atrasar' then
      v_abre := 'nome';
      if v_var = 'peca' then
        v_resto := format('quero te avisar com antecedência: a peça %s ainda não chegou e agora está prevista %s. Por isso, %s, que estava %s, deve ficar %s. Te confirmo a data assim que a peça chegar. Se isso atrapalhar algum plano seu, me diga.',
                          x ->> 'do_servico',
                          public._agenda_cliente_faixa((d ->> 'peca_de')::date, (d ->> 'peca_ate')::date, true),
                          v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true),
                          public._agenda_cliente_faixa((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date, true));
      elsif v_var = 'execucao' then
        v_resto := format('%s %s levando mais tempo do que eu estimei. A nova previsão para terminar é %s. Qualquer dúvida, me chama.',
                          v_serv, v_esta, public._agenda_cliente_faixa((d ->> 'faixa_de')::date, (d ->> 'faixa_ate')::date));
      else
        v_resto := format('%s, que estava %s, precisou passar para %s, %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                          v_serv, public._agenda_cliente_faixa(v_dito_de, v_dito_ate, true), public._agenda_cliente_dia(v_dia), v_jan);
        -- CORREÇÃO FASE 5: (item 6) o remarcado em que o início é o mesmo que o cliente ouviu e só o FIM mudou (a forma fim):
        -- dizer que "precisou passar para" o mesmo dia de início confunde
        if d ->> 'forma' = 'fim' then
          if v_fim is null then
            raise exception using errcode = '22023', message = 'Falta o fim novo para a mensagem pode_atrasar ao cliente.';
          end if;
          v_resto := format('%s vai precisar de mais um dia: agora fica de %s até %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                            v_serv, public._agenda_cliente_dia(v_dia), public._agenda_cliente_dia(v_fim));
          -- FASE 6: (P7) o número certo de dias (spec-fase6 §6.1): n = os dias úteis entre o último dia que o cliente ouviu e o
          -- fim novo (agenda_du_entre); "um dia depois do previsto" com n = 1, "{n} dias depois do previsto" com n ≥ 2. O fim
          -- que não passa do dia dito não vira texto (como todo dado que falta). Texto novo ao cliente: vai à lista do dono
          declare
            v_du int := public.agenda_du_entre(coalesce(v_dito_ate, v_dito_de), v_fim);
          begin
            if coalesce(v_du, 0) < 1 then
              raise exception using errcode = '22023',
                message = 'Falta o fim novo depois do dia dito para a mensagem pode_atrasar ao cliente.';
            end if;
            v_resto := format('%s vai terminar %s depois do previsto: agora fica de %s até %s. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.',
                              v_serv, case when v_du = 1 then 'um dia' else v_du || ' dias' end,
                              public._agenda_cliente_dia(v_dia), public._agenda_cliente_dia(v_fim));
          end;
          -- FASE 6: fim
        end if;
        -- CORREÇÃO FASE 5: fim
      end if;
    when 'nova_data' then
      v_abre := 'nome';
      v_resto := format('agora com data firme: %s fica para %s, %s. Desculpe pela mudança e obrigado pela paciência. Responda SIM para confirmar, ou me diga se precisa de outro dia.',
                        v_serv, public._agenda_cliente_dia(v_dia), v_jan);
    when 'andamento' then
      v_abre := 'nome';
      if v_var = 'primeiro_dia' then
        v_resto := format('começamos %s %s. Seguimos com a previsão de terminar %s.',
                          coalesce(d ->> 'quando', 'hoje'), v_serv, public._agenda_cliente_dia(v_fim));
      else
        v_resto := format('seguimos com %s: %s de %s dias feitos, previsão de terminar %s.',
                          v_serv, (d ->> 'n_feitos')::int, v_n, public._agenda_cliente_dia(v_fim));
      end if;
    when 'pronto' then
      v_abre := 'nome';
      v_resto := format('%s %s %s. Quando fica bom para combinarmos a entrega?', v_serv, v_esta,
                        case v_art when 'a' then 'concluída' when 'os' then 'concluídos' when 'as' then 'concluídas' else 'concluído' end);
    when 'pronto_lembrete' then
      v_abre := 'nome';
      v_resto := format('só para combinarmos a entrega %s: qual dia fica bom pra você?', x ->> 'do_bem');
    when 'pos_servico' then
      v_abre := 'nome';
      v_resto := format('tudo certo com %s? Já deu para usar? Se algo não estiver como esperado, me responde aqui que a gente resolve. Se preferir não receber estas mensagens, é só responder PARAR.',
                        v_serv);
    else -- mudanca_no_dia
      if v_var = 'clima' then
        v_abre := 'bom_dia_ponto';
        v_resto := format('Com a chuva de %s não dá para trabalhar %s com segurança. Podemos passar para %s, %s? Responda SIM ou me diga outro dia.',
                          d ->> 'quando', x ->> 'no_bem', public._agenda_cliente_dia(v_dia), v_jan);
      else
        v_abre := 'nome';
        v_resto := format('tive um imprevisto%s e não vamos conseguir ir %s. Desculpe o transtorno. Podemos ir %s, %s? Responda SIM ou me diga outro dia.',
                          case when v_var = 'equipe' then ' com a equipe' else '' end, d ->> 'quando',
                          public._agenda_cliente_dia(v_dia), v_jan);
      end if;
  end case;

  -- CORREÇÃO FASE 5: (item 12) a saudação pela hora em que a mensagem SAI (o registrar grava p_dados.saudacao: "Bom dia"
  -- antes do meio-dia, "Boa tarde" depois); sem ela, "Bom dia" (como as registradas antes desta correção)
  if v_abre in ('bom_dia', 'bom_dia_ponto') then
    return format('%s, %s%s %s', coalesce(nullif(d ->> 'saudacao', ''), 'Bom dia'), v_nome,
                  case when v_abre = 'bom_dia' then '!' else '.' end,
                  case when v_prim then v_assin || ' ' else '' end || v_resto);
  end if;
  -- CORREÇÃO FASE 5: fim
  return case v_abre
    when 'pronto' then v_resto
    when 'nome' then case when v_prim then format('Olá, %s! %s %s', v_nome, v_assin, upper(left(v_resto, 1)) || substr(v_resto, 2))
                          else v_nome || ', ' || v_resto end
    when 'bom_dia' then format('Bom dia, %s! %s', v_nome, case when v_prim then v_assin || ' ' else '' end || v_resto)
    when 'bom_dia_ponto' then format('Bom dia, %s. %s', v_nome, case when v_prim then v_assin || ' ' else '' end || v_resto)
    else case when v_prim then format('Olá, %s! %s Boa notícia: %s', v_nome, v_assin, v_resto)
              else format('Boa notícia, %s: %s', v_nome, v_resto) end
  end;
end;
$function$;

comment on function public._agenda_cliente_texto(text, text, uuid, jsonb, date) is
  'Agenda de Produção (Fase 5): a mensagem-modelo ao cliente (spec §6.1), pronta, com os dados do banco — tipos confirmar (M1: primeira, seguinte, unico; nula = primeira ou seguinte pelo contexto), vespera (M2), acesso (M4), material_chegou (M3), pode_atrasar (M6: peca, execucao, remarcado), nova_data (M7), andamento (M5: primeiro_dia, semanal), pronto e pronto_lembrete (M8), pos_servico (M9) e mudanca_no_dia (M10: clima, equipe, geral). p_dados = o que o passo calculou (envio, primeira, dia, fim, janela, n, n_feitos, quando, faixa_de/ate, peca_de/ate, dito_de/ate ou dia_dito); o que faltar sai do contexto (_agenda_cliente_contexto). Assinatura só na 1ª mensagem. Lança 22023 com o tipo ou a variante que não existe e quando falta um dado; nunca devolve texto pela metade. CORREÇÃO FASE 5 (C2): (item 12) p_dados.saudacao ("Bom dia" | "Boa tarde"; padrão "Bom dia") abre a véspera, o acesso e o M10 de chuva; (item 6) p_dados.forma = fim no M6 remarcado com o mesmo início ("{nome}, {servico} vai precisar de mais um dia: agora fica de {dia} até {fim}. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia."); (item 8) M6 peca_sem_data, sem data ("{nome}, quero te avisar com antecedência: ainda faltam peças {d}o serviço sem data de chegada, então {servico}, que estava {dito}, vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga."). FASE 6 (P7, spec-fase6 §6.1): a forma fim diz quantos dias o fim andou ("{nome}, {servico} vai terminar um dia depois do previsto: agora fica de {dia} até {fim}. …"; n ≥ 2: "… vai terminar {n} dias depois do previsto: …"; n = agenda_du_entre(dito_ate, fim); n < 1 = 22023); a peça sem data sem a repetição ("{nome}, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então {servico}, que estava {dito}, vai atrasar. …"). Os dois textos novos ao cliente esperam o OK do dono antes de ligar.';

-- agenda_cliente_preparar (de 20261028100800_agenda_fase5_correcao_rodada.sql)
create or replace function public.agenda_cliente_preparar(p_autor uuid, p_os text, p_tipo text, p_firme boolean default false,
                                                          p_trecho text default null, p_hoje date default public._hoje_brt(),
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_tipo  text := lower(btrim(coalesce(p_tipo, '')));
  v_ro    jsonb;
  v_os    uuid;
  x       jsonb;
  v_rk    jsonb;
  v_nome  text;
  v_st    text;
  v_dia   date;
  v_var   text;
  v_dados jsonb := '{}'::jsonb;
  v_alvo  timestamptz := p_agora;
  v_valida timestamptz;
  v_chave text;
  v_r     jsonb;
  m       public.agenda_cliente_mensagens%rowtype;
  v_conc  date;
  v_ini   date;
  v_pl    jsonb;
  v_txt   text;
begin
  if v_tipo not in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data', 'pronto',
                    'pronto_lembrete', 'pos_servico', 'mudanca_no_dia') then
    raise exception 'O tipo da mensagem ao cliente não existe: "%".', coalesce(p_tipo, '') using errcode = '22023';
  end if;
  if cf.modo_cliente = 'desligado' then
    return public._agenda_recusa('As mensagens ao cliente estão desligadas: não preparei nada.', 'desligada');
  end if;
  if nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que avisar ao cliente.', 'sem_trecho');
  end if;
  if v_tipo = 'mudanca_no_dia' then
    return public._agenda_recusa('O aviso de mudança no dia eu mando sozinho quando o plano muda (chuva, falta da equipe). Para outra data, me diga o novo dia do serviço.',
                                 'mudanca_no_dia');
  end if;
  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' = 'fora_da_carteira' and v_tipo in ('pronto', 'pronto_lembrete', 'pos_servico') then
    v_os := (v_ro ->> 'id')::uuid;
  elsif v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  else
    v_os := (v_ro ->> 'id')::uuid;
  end if;
  x := public._agenda_cliente_contexto(v_os, p_hoje);
  v_nome := coalesce(x ->> 'nome', 'cliente');
  v_st := x ->> 'status';
  if not coalesce((x ->> 'telefone_ok')::boolean, false) then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('%s não tem telefone no cadastro: não tenho como mandar.', v_nome), 'sem_telefone');
    -- FASE 6: fim
    return public._agenda_recusa(format('O %s não tem telefone no cadastro: não tenho como mandar.', v_nome), 'sem_telefone');
  end if;
  if coalesce((x ->> 'opt_out')::boolean, false) then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('%s pediu para não receber mensagens: não mando.', v_nome), 'opt_out');
    -- FASE 6: fim
    return public._agenda_recusa(format('O %s pediu para não receber mensagens: não mando.', v_nome), 'opt_out');
  end if;

  if v_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data') then
    v_dia := (x ->> 'dia')::date;
    -- d09: material sem previsão ou não conferido nunca vira data firme (antes da data: é o que o dono precisa saber)
    if coalesce(x ->> 'material_estado', '') <> 'completo' then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O material de %s ainda não está todo na mão (%s): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.',
                                          v_nome, case x ->> 'material_estado' when 'previsto' then 'tem peça a caminho'
                                                                             when 'sem_previsao' then 'tem peça sem previsão de chegada'
                                                                             when 'atrasado' then 'tem peça atrasada'
                                                                             else 'o material ainda não foi conferido' end),
                                   'material');
      -- FASE 6: fim
      return public._agenda_recusa(format('O material do %s ainda não está todo na mão (%s): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.',
                                          v_nome, case x ->> 'material_estado' when 'previsto' then 'tem peça a caminho'
                                                                             when 'sem_previsao' then 'tem peça sem previsão de chegada'
                                                                             when 'atrasado' then 'tem peça atrasada'
                                                                             else 'o material ainda não foi conferido' end),
                                   'material');
    end if;
    if v_dia is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('%s não tem data no plano: não tenho o que %s.', v_nome,
                                          case v_tipo when 'confirmar' then 'confirmar' when 'nova_data' then 'dizer de data nova'
                                                      else 'avisar' end), 'sem_data');
      -- FASE 6: fim
      return public._agenda_recusa(format('O %s não tem data no plano: não tenho o que %s.', v_nome,
                                          case v_tipo when 'confirmar' then 'confirmar' when 'nova_data' then 'dizer de data nova'
                                                      else 'avisar' end), 'sem_data');
    end if;
    if v_tipo in ('vespera', 'acesso') then
      if v_dia <= p_hoje then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('O serviço de %s é hoje: a véspera já passou.', v_nome), 'passou');
        -- FASE 6: fim
        return public._agenda_recusa(format('O serviço do %s é hoje: a véspera já passou.', v_nome), 'passou');
      end if;
      v_alvo := greatest(p_agora, public._agenda_cliente_toque(public._agenda_cliente_vespera(v_dia)));
    end if;
  elsif v_tipo = 'pode_atrasar' then
    v_rk := public._agenda_cliente_risco(v_os, p_hoje);
    if (x #>> '{prometido,ate}') is null or v_rk is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('Não há data dita para %s: sem data dita, não há atraso a avisar. Se você disse uma data, me conte ("falei pro %s que é dia 3").',
                                          v_nome, v_nome), 'sem_prometido');
      -- FASE 6: fim
      return public._agenda_recusa(format('Não há data dita ao %s: sem data dita, não há atraso a avisar. Se você disse uma data a ele, me conte ("falei pro %s que é dia 3").',
                                          v_nome, v_nome), 'sem_prometido');
    end if;
    if coalesce((v_rk ->> 'passou')::boolean, false) then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('A data que %s ouviu (%s) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.',
                                          v_nome, public._dia_curto((v_rk ->> 'dito_ate')::date)), 'passou');
      -- FASE 6: fim
      return public._agenda_recusa(format('A data que o %s ouviu (%s) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.',
                                          v_nome, public._dia_curto((v_rk ->> 'dito_ate')::date)), 'passou');
    end if;
    if coalesce(p_firme, false) then
      -- a data firme do plano no lugar da faixa (d09: só o dono decide, e só com o plano publicado)
      if (x ->> 'dia') is null or (x ->> 'fim') is null then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('%s não tem o plano publicado: não tenho data firme para dizer; vai a faixa.', v_nome),
                                     'sem_plano');
        -- FASE 6: fim
        return public._agenda_recusa(format('O %s não tem o plano publicado: não tenho data firme para dizer; vai a faixa.', v_nome),
                                     'sem_plano');
      end if;
      v_var := 'remarcado';
      v_dia := (x ->> 'dia')::date;
      v_dados := jsonb_build_object('dia', x -> 'dia', 'fim', x -> 'fim', 'prometido_tipo', 'firme',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate');
      -- CORREÇÃO FASE 5: (item 7) a data firme que o DONO manda dizer passa pela revalidação sem o passo do material (d09:
      -- só o dono troca a faixa pela data firme do plano); (item 6) com o início igual ao que o cliente ouviu, a forma fim
      v_dados := v_dados || jsonb_build_object('firme_do_dono', true)
                 || case when v_dia = coalesce((v_rk ->> 'dito_de')::date, (v_rk ->> 'dito_ate')::date)
                         then jsonb_build_object('forma', 'fim') else '{}'::jsonb end;
      -- CORREÇÃO FASE 5: fim
    else
      if coalesce((v_rk ->> 'sem_data')::boolean, false) then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('A peça de %s ainda não tem previsão: não tenho data nova para dizer. Com a previsão eu preparo (ou peça com a data firme do plano).',
                                            v_nome), 'sem_data');
        -- FASE 6: fim
        return public._agenda_recusa(format('A peça do %s ainda não tem previsão: não tenho data nova para dizer. Com a previsão eu preparo (ou peça com a data firme do plano).',
                                            v_nome), 'sem_data');
      end if;
      if not coalesce((v_rk ->> 'risco')::boolean, false) then
        -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
        return public._agenda_recusa(format('O plano de %s ainda cabe na data dita (%s): não há atraso a avisar.', v_nome,
                                            public._dia_curto((v_rk ->> 'dito_ate')::date)), 'sem_risco');
        -- FASE 6: fim
        return public._agenda_recusa(format('O plano do %s ainda cabe na data que ele ouviu (%s): não há atraso a avisar.', v_nome,
                                            public._dia_curto((v_rk ->> 'dito_ate')::date)), 'sem_risco');
      end if;
      v_var := v_rk ->> 'variante';
      v_dia := (v_rk ->> 'faixa_de')::date;
      v_dados := jsonb_build_object('faixa_de', v_rk -> 'faixa_de', 'faixa_ate', v_rk -> 'faixa_ate', 'prometido_tipo', v_rk -> 'tipo',
                                    'dito_de', v_rk -> 'dito_de', 'dito_ate', v_rk -> 'dito_ate')
                 || case when v_var = 'peca' then jsonb_build_object('peca_de', v_rk -> 'peca', 'peca_ate', v_rk -> 'peca')
                         else '{}'::jsonb end;
      -- CORREÇÃO FASE 5: (item 6) o remarcado da rodada com o mesmo início: a forma fim (como o passo atraso)
      if v_rk ->> 'forma' = 'fim' then
        v_dados := v_dados || jsonb_build_object('forma', 'fim', 'dia', v_rk -> 'faixa_de', 'fim', v_rk -> 'faixa_ate');
      end if;
      -- CORREÇÃO FASE 5: fim
    end if;
    v_valida := public._agenda_cliente_ultimo_fim((v_rk ->> 'dito_ate')::date);
  elsif v_tipo = 'andamento' then
    v_pl := public._agenda_plano_da_os(v_os, p_hoje);
    select min(a.dia) into v_ini from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.resultado in ('cumprido', 'parcial');
    if v_st <> 'in_progress' or v_ini is null or (v_pl ->> 'ultimo_dia') is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s ainda não começou (ou não tem o fim no plano): não há andamento a contar.', v_nome),
                                   'sem_andamento');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s ainda não começou (ou não tem o fim no plano): não há andamento a contar.', v_nome),
                                   'sem_andamento');
    end if;
    v_var := 'semanal';
    v_dia := (v_pl ->> 'ultimo_dia')::date;
    v_dados := jsonb_build_object('n_feitos', floor(coalesce((v_pl ->> 'meios_cumpridos')::numeric, 0))::int,
                                  'chave', to_char(p_hoje, 'IYYY-"S"IW'));
  else
    -- pronto, lembrete e pós-serviço: a OS concluída
    select (so.check_out_at at time zone 'America/Sao_Paulo')::date into v_conc
      from public.service_orders so where so.id = v_os and so.status in ('completed', 'invoiced');
    if v_conc is null then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s ainda não está concluído.', v_nome), 'nao_concluida');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s ainda não está concluído.', v_nome), 'nao_concluida');
    end if;
    if v_tipo in ('pronto', 'pronto_lembrete')
       and exists (select 1 from public.service_orders so where so.id = v_os and so.delivered_at is not null) then
      -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
      return public._agenda_recusa(format('O serviço de %s já foi entregue.', v_nome), 'entregue');
      -- FASE 6: fim
      return public._agenda_recusa(format('O serviço do %s já foi entregue.', v_nome), 'entregue');
    end if;
    if v_tipo = 'pronto' then
      v_dia := v_conc;
    elsif v_tipo = 'pronto_lembrete' then
      v_dados := jsonb_build_object('chave', '2');
    else
      v_dados := jsonb_build_object('chave', 'pos');
    end if;
  end if;

  begin
    v_r := public._agenda_cliente_registrar(v_tipo, v_var, v_os, v_dia, v_dados, v_alvo, v_valida, 'dono', null, p_agora, v_autor);
    if v_r ->> 'motivo' = 'ja_existe' then
      select * into m from public.agenda_cliente_mensagens where id = (v_r ->> 'id')::uuid;
      if m.estado = 'recusada' then
        -- a do mesmo dia já foi recusada (segurada, vencida…): o pedido explícito do dono vale uma vez mais
        v_chave := coalesce(nullif(btrim(v_dados ->> 'chave'), ''), v_dia::text, to_char(p_agora at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'))
                   || ':dono';
        v_r := public._agenda_cliente_registrar(v_tipo, v_var, v_os, v_dia, v_dados || jsonb_build_object('chave', v_chave), v_alvo,
                                                v_valida, 'dono', null, p_agora, v_autor);
        if v_r ->> 'motivo' = 'ja_existe' then
          select * into m from public.agenda_cliente_mensagens where id = (v_r ->> 'id')::uuid;
        end if;
      end if;
    end if;
  exception when sqlstate '22023' then
    return public._agenda_recusa(format('Não preparei: %s', sqlerrm), 'texto');
  end;

  if v_r ->> 'motivo' = 'ja_existe' then
    v_txt := case
      when m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
        then format('Já está pronta, esperando você (sai %s): "%s". Para mandar: *manda cliente %s*.',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto, v_nome)
      when m.estado = 'aguardando_dono' then format('Essa mensagem ao %s é uma decisão que espera você: responda pela conversa (1, 2 ou 3).', v_nome)
      when m.estado in ('registrada', 'enfileirada') and m.modo = 'ligado'
        then format('Essa mensagem já vai sair sozinha %s: "%s". Para não mandar: *segura cliente %s*.',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto, v_nome)
      when m.estado in ('registrada', 'enfileirada')
        then format('Em teste: essa mensagem já está registrada (sairia %s): "%s".',
                    public._agenda_cliente_quando_texto(m.enviar_em, p_agora), m.texto)
      when m.enviada_em is not null
        then format('Já mandei ao %s %s às %s: "%s".', v_nome,
                    public._dia_curto((m.enviada_em at time zone 'America/Sao_Paulo')::date),
                    to_char(m.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI'), m.texto)
      else format('Essa mensagem ao %s já foi registrada e não sai (%s).', v_nome, coalesce(m.recusa_motivo, m.estado)) end;
    -- CORREÇÃO FASE 5: (item 15) sem artigo antes do nome ("Já mandei para Nelson …")
    v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
    -- CORREÇÃO FASE 5: fim
    return jsonb_build_object('ok', true, 'status', 'ja_existe', 'texto', v_txt, 'mensagem_id', m.id, 'estado', m.estado,
                              'modo', m.modo);
  end if;
  if v_r ->> 'estado' = 'recusada' then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4): a recusa de antes, logo abaixo, não roda mais
    return public._agenda_recusa(format('Não preparei: a mensagem para %s passaria da hora de servir (sairia %s).', v_nome,
                                        public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)),
                                 coalesce(v_r ->> 'motivo', 'vencida'));
    -- FASE 6: fim
    return public._agenda_recusa(format('Não preparei: a mensagem ao %s passaria da hora de servir (sairia %s).', v_nome,
                                        public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)),
                                 coalesce(v_r ->> 'motivo', 'vencida'));
  end if;
  v_txt := case
    when v_r ->> 'modo' = 'ligado'
      then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', v_nome,
                  public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto', v_nome)
    when cf.modo_cliente = 'ligado'
      then format('Esse tipo de mensagem (%s) ainda está em teste: não sai. Eu teria preparado para o %s, para sair %s: "%s".',
                  public._agenda_cliente_tipo_texto(v_tipo), v_nome,
                  public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto')
    else format('Em teste (as mensagens ao cliente ainda não saem): eu teria preparado para o %s, para sair %s: "%s".', v_nome,
                public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_r ->> 'texto') end;
  -- CORREÇÃO FASE 5: (item 15) "Pronto para Vanderlei, sai agora: …" (sem artigo antes do nome)
  v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('ok', true, 'status', 'preparada', 'texto', v_txt, 'mensagem_id', v_r -> 'id',
                            'estado', v_r ->> 'estado', 'modo', v_r ->> 'modo', 'enviar_em', v_r -> 'enviar_em');
end;
$function$;

comment on function public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P5): a ferramenta cliente_avisar — prepara a mensagem-modelo que o dono pede e NUNCA envia. Resolve a OS (agenda_resolver_os; o pronto, o lembrete e o pós-serviço aceitam a OS concluída fora da carteira), confere o telefone e o opt-out, o tipo e os dados (sem dado, diz o que falta: "O Nelson não tem data no plano: não tenho o que confirmar.", "Não há data dita ao Giancarlo: …", d09 — material fora de "completo" não vira data firme), e registra pelo _agenda_cliente_registrar com origem dono (em ligado, sempre pedida: "Pronto para o Nelson, sai amanhã às 09:00: "…". Para mandar: *manda cliente Nelson*."; em teste, a sombra). A chave é a da rodada (a mesma mensagem não sai duas vezes: a que já existe é dita como está; a recusada antes ganha uma 2ª chance com :dono). p_firme (só pode_atrasar): a data firme do plano (variante remarcado) no lugar da faixa, só com o plano publicado. mudanca_no_dia não é pela ferramenta (sai sozinha). modo_cliente desligado = recusa. Admin pelo _autor_da_agenda. {ok, status, texto, mensagem_id, estado, modo, enviar_em} ou a recusa {ok:false, motivo, pergunta, texto}. CORREÇÃO FASE 5 (C2): (item 7) p_firme grava firme_do_dono em p_dados (a revalidação não aplica o passo do material a ela); (item 6) a forma fim com o mesmo início que o cliente ouviu; (item 15) o texto da preparada e o da que já existe sem artigo antes do nome. FASE 6 (P7, spec-fase6 §6.4): as recusas sem artigo antes do nome e sem "ele" ("Nelson não tem telefone no cadastro: …", "Não há data dita para Giancarlo: … Se você disse uma data, me conte …", "O plano de Nelson ainda cabe na data dita (qui 05/11): …"); a preparada e a que já existe passam pelo ralo (_agenda_cliente_sem_artigo, que agora tira também o "ele").';

-- agenda_resposta_do_cliente (de 20261028100800_agenda_fase5_correcao_rodada.sql)
create or replace function public.agenda_resposta_do_cliente(p_phone text, p_body text, p_message_id uuid, p_tipo_msg text,
                                                             p_intencao text, p_expressao text,
                                                             p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  c_pergunta_dias constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  -- os tipos que esperam resposta (spec §5.4); os que propõem um dia (o pedido de outro dia só vale neles)
  c_esperam constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia',
                                     'pode_atrasar', 'pronto', 'pronto_lembrete', 'pos_servico'];
  c_do_dia  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia'];
  v_hoje    date;
  v_modo    text;
  v_tipo    text;
  v_trecho  text;
  v_cli     uuid[];
  m         public.agenda_cliente_mensagens%rowtype;
  v_n       int;
  v_r       public.agenda_cliente_respostas%rowtype;
  v_rid     uuid := gen_random_uuid();
  v_int     text;
  v_expr    text;
  v_data    jsonb;
  v_nome    text;
  v_dia     date;
  v_ref     text;
  v_do_dia  boolean;
  v_efeito  text;
  v_o_que   text;
  v_texto   text;
  v_x       jsonb;
  v_acao    uuid;
  v_perg    uuid;
  v_acorde  boolean := false;
  v_de      date;
  v_ate     date;
  v_id      uuid;
  v_k       int := 0;
  v_estado  text;
  v_msg     text;
  -- CORREÇÃO FASE 5: a outra conversa (A1) e o PARAR que vale sempre (item 2)
  c_opt_out_dias constant interval := interval '30 days';   -- decisão da correção C1: o PARAR de quem recebeu da agenda em 30 dias
  v_outra   boolean := false;
  v_opt_cli uuid[];
  v_opt_msg uuid;
  v_opt_os  uuid;
  v_c       uuid;
  -- CORREÇÃO FASE 5: fim
begin
  if p_agora is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_tipo := case when p_tipo_msg in ('text', 'audio', 'image', 'document', 'video') then p_tipo_msg else 'outro' end;
  v_trecho := nullif(left(btrim(coalesce(p_body, '')), 500), '');
  if v_tipo = 'text' and v_trecho is null then
    return jsonb_build_object('consumiu', false);
  end if;
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_modo := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;

  -- quem é (o dono, a equipe e quem recebe diária nunca são cliente)
  v_cli := public._agenda_clientes_do_telefone(p_phone, p_agora);
  if cardinality(v_cli) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  -- a mesma mensagem dele de novo: nada muda
  if p_message_id is not null then
    select * into v_r from public.agenda_cliente_respostas r where r.whatsapp_message_id = p_message_id;
    if found then
      return jsonb_build_object('consumiu', v_r.modo = 'ligado', 'efeito', v_r.efeito, 'repetida', true, 'resposta_id', v_r.id);
    end if;
  end if;

  -- a que mensagem ele responde: a última da agenda mandada a ele (em teste, a que teria saído), dos tipos que esperam
  -- resposta, dentro de cliente_resposta_validade, ainda sem resposta. Sem ela, a agenda não lê: é conversa.
  select count(distinct x.service_order_id)::int into v_n
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade));
  select x.* into m
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade))
   order by coalesce(x.enviada_em, x.enviar_em) desc, x.criada_em desc, x.id
   limit 1;
  -- CORREÇÃO FASE 5: (A1 = item 11) a resposta só é da agenda quando a última mensagem que a HBR mandou a esse número é a
  -- dela: o botão antigo (o pedido de 30/09) ou o dono (ou outra rotina) falando com o cliente depois dela = a resposta é
  -- dessa outra conversa — devolve consumiu false (abaixo) e os leitores de antes (o "sim" de 30/09, a revisão) seguem.
  if m.id is not null then
    v_outra := public._agenda_cliente_outra_conversa(v_cli, p_phone, coalesce(m.enviada_em, m.enviar_em), p_agora);
  end if;
  -- (item 2) o PARAR (e os outros opt-outs) vale SEMPRE para quem recebeu mensagem da agenda nos últimos c_opt_out_dias —
  -- fora da validade, depois de outra resposta, com o número de dois clientes ou depois de outra conversa: o pós-serviço
  -- promete "é só responder PARAR". Marca o opt-out de cada cliente do número que recebeu, cancela as vivas dele, grava a
  -- resposta (efeito opt_out) e a ação; nada responde ao cliente.
  if v_modo = 'ligado' and v_tipo = 'text' and p_intencao = 'opt_out' and not public._e_concordancia(p_body)
     and (m.id is null or v_outra or v_n > 1 or cardinality(v_cli) > 1) then
    select coalesce(array_agg(distinct x.client_id), '{}'::uuid[]) into v_opt_cli
      from public.agenda_cliente_mensagens x
     where x.client_id = any (v_cli) and x.modo = 'ligado' and x.enviada_em is not null
       and x.enviada_em <= p_agora and x.enviada_em > p_agora - c_opt_out_dias;
    if cardinality(v_opt_cli) > 0 then
      select x.id, x.service_order_id into v_opt_msg, v_opt_os
        from public.agenda_cliente_mensagens x
       where x.client_id = any (v_opt_cli) and x.modo = 'ligado' and x.enviada_em is not null and x.enviada_em <= p_agora
       order by x.enviada_em desc, x.id limit 1;
      insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                   tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
      values (v_rid, v_opt_cli[1], v_opt_os, v_opt_msg, p_message_id, p_agora, v_tipo, v_trecho, 'opt_out', null, null,
              'opt_out', 'ligado')
      on conflict (whatsapp_message_id) do nothing;
      if not found then
        return jsonb_build_object('consumiu', true, 'repetida', true);
      end if;
      foreach v_c in array v_opt_cli loop
        update public.clients set opt_out_whatsapp = true where id = v_c and not coalesce(opt_out_whatsapp, false);
        for v_id in select x.id from public.agenda_cliente_mensagens x
                     where x.client_id = v_c and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                     order by x.enviar_em, x.id loop
          if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
            v_k := v_k + 1;
          end if;
        end loop;
      end loop;
      v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                            from public.clients cl where cl.id = v_opt_cli[1]), 'cliente');
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      -- FASE 6: (P7) a ação do opt-out sem artigo antes do nome e sem "a ele" (spec-fase6 §6.4)
      v_texto := format('%s pediu para não receber mais mensagens: não mando mais nada.', v_nome);
      -- FASE 6: fim
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', v_opt_os, array[v_opt_os], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'canceladas', v_k,
                                 'clientes', to_jsonb(v_opt_cli), 'fora_da_mensagem', true),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
      update public.agenda_cliente_respostas set acao_id = v_acao where id = v_rid;
      return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', 'opt_out', 'intencao', 'opt_out', 'texto', v_texto,
                                'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'acao_id', v_acao, 'pergunta_id', null);
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'motivo', 'sem_mensagem');
  end if;
  -- CORREÇÃO FASE 5: (A1) a outra conversa depois da mensagem da agenda: não é resposta a ela (em teste também: a sombra
  -- não registra o que a agenda não leria)
  if v_outra then
    return jsonb_build_object('consumiu', false, 'modo', v_modo, 'motivo', 'outra_conversa', 'mensagem_id', m.id);
  end if;
  -- CORREÇÃO FASE 5: fim

  -- a intenção: o áudio e a mídia antes de tudo (nunca confirmam); o SIM curto pela regra única de 30/09; o resto como o
  -- leitor do webhook classificou (sem IA)
  v_int := case when v_tipo = 'audio' then 'audio'
                when v_tipo <> 'text' then 'outro'
                when public._e_concordancia(p_body) then 'confirma'
                when p_intencao in ('remarcar', 'falta', 'data', 'acesso', 'opt_out', 'disputa', 'negociacao', 'pergunta',
                                    'acordo', 'outro') then p_intencao
                else 'outro' end;
  v_expr := case when v_int in ('data', 'remarcar', 'falta') then nullif(left(btrim(coalesce(p_expressao, '')), 60), '') end;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  v_data := case when v_expr is not null then public._agenda_cliente_data_da_resposta(v_expr, v_hoje, v_dia) end;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  v_ref := public._agenda_cliente_a_mensagem(m.tipo, m.variante, v_dia);
  v_do_dia := m.tipo = any (c_do_dia) or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado');

  -- em teste: só registra o que faria (a intenção); nada muda e os fluxos de hoje seguem iguais
  if v_modo = 'sombra' then
    insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                 tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
    values (v_rid, m.client_id, m.service_order_id, m.id, p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr,
            (v_data ->> 'de')::date, 'sombra', 'sombra')
    on conflict (whatsapp_message_id) do nothing;
    return jsonb_build_object('consumiu', false, 'modo', 'sombra', 'efeito', 'sombra', 'intencao', v_int, 'resposta_id', v_rid);
  end if;

  -- ligado: a resposta fica registrada primeiro (uma por mensagem do WhatsApp); o efeito vem depois
  insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                               tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
  values (v_rid, m.client_id, m.service_order_id, case when v_n > 1 or cardinality(v_cli) > 1 then null else m.id end,
          p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr, (v_data ->> 'de')::date, 'nada', 'ligado')
  on conflict (whatsapp_message_id) do nothing;
  if not found then
    return jsonb_build_object('consumiu', true, 'repetida', true);
  end if;
  perform set_config('agenda.hoje', v_hoje::text, true);

  begin
    if v_n > 1 or cardinality(v_cli) > 1 then
      -- duas OS (ou dois clientes no número) esperando: não adivinha
      v_efeito := 'ambigua';
      v_texto := format('Chegou "%s" do número do %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta dele', v_n) end);
      -- FASE 6: (P7) sem artigo antes do nome e sem "dele" (spec-fase6 §6.4), escrito já assim: com dois clientes no número, a
      -- OS da mensagem pode ser do outro, e o ralo (que troca só o 1º nome do cliente da OS) não acharia este
      v_texto := format('Chegou "%s" do número de %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta do cliente', v_n) end);
      -- FASE 6: fim
    elsif v_int = 'audio' then
      -- o áudio NUNCA confirma: vai ao dono
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu por áudio %s; a transcrição está na conversa. Não respondi nada; é com você.', v_nome, v_ref);
    elsif v_tipo <> 'text' then
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu com %s %s. Não respondi nada; é com você.', v_nome,
                        case v_tipo when 'image' then 'uma foto' when 'video' then 'um vídeo' when 'document' then 'um documento'
                                    else 'uma mensagem que não é texto' end, v_ref);
    elsif v_int = 'confirma' then
      if m.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado') then
        -- (decisão do P4) o SIM ao aviso remarcado confirma o dia novo, como o M1: o texto dele pede "Responda SIM"
        v_x := public._agenda_cliente_confirmar_dia(m.id, v_rid, v_trecho, v_hoje, p_agora);
        if coalesce((v_x ->> 'ok')::boolean, false) then
          v_efeito := 'confirmou';
          v_acao := (v_x ->> 'acao_id')::uuid;
          v_texto := v_x ->> 'texto';
        else
          v_efeito := 'ao_dono';
          v_o_que := v_x ->> 'o_que';
        end if;
      elsif m.tipo in ('vespera', 'acesso') then
        v_efeito := 'confirmou';   -- só registra (o client_confirmed_* é do SIM ao M1/M3/M7/M10)
      elsif m.tipo = 'pode_atrasar' then
        v_efeito := 'ciencia';
      elsif m.tipo in ('pronto', 'pronto_lembrete') then
        v_efeito := 'ao_dono';
        v_o_que := 'combine a entrega com ele';
      else
        v_efeito := 'nada';
      end if;
    elsif v_int = 'opt_out' then
      -- honrado calado (d8): nada mais sai a ele; o dono fica sabendo pela ação
      update public.clients set opt_out_whatsapp = true where id = m.client_id and not coalesce(opt_out_whatsapp, false);
      for v_id in select x.id from public.agenda_cliente_mensagens x
                   where x.client_id = m.client_id and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                   order by x.enviar_em, x.id loop
        if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
          v_k := v_k + 1;
        end if;
      end loop;
      v_efeito := 'opt_out';
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      -- FASE 6: (P7) a ação do opt-out sem artigo antes do nome e sem "a ele" (spec-fase6 §6.4)
      v_texto := format('%s pediu para não receber mais mensagens: não mando mais nada.', v_nome);
      -- FASE 6: fim
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', m.service_order_id, array[m.service_order_id], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', m.id, 'canceladas', v_k),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
    elsif v_int in ('disputa', 'negociacao', 'acordo', 'pergunta') then
      v_efeito := 'ao_dono';
      v_acorde := v_int = 'disputa';   -- a reclamação vai na hora
      v_o_que := case v_int when 'disputa' then 'parece reclamação'
                            when 'negociacao' then 'é sobre preço ou pagamento'
                            when 'acordo' then 'parece que concorda, mas não é um SIM claro'
                            else 'é uma pergunta' end;
    elsif v_int in ('data', 'remarcar', 'falta') and not v_do_dia then
      v_efeito := 'ao_dono';
      v_o_que := case when m.tipo in ('pronto', 'pronto_lembrete') then 'falou de dia: combine a entrega com ele'
                      else 'falou de outro dia' end;
    elsif v_int in ('data', 'remarcar', 'falta') and cf.modo_proposta <> 'ligado' then
      v_efeito := 'ao_dono';
      v_o_que := 'pediu outro dia, mas a agenda automática não está ligada: remarque você';
    elsif v_int = 'data' then
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null then
        v_efeito := 'ao_dono';
        v_o_que := 'não entendi o dia que ele pediu';
      elsif v_de <= v_hoje then
        v_efeito := 'ao_dono';
        v_o_que := 'o dia que ele pediu já passou ou é hoje';
      elsif v_dia is not null and v_de = v_dia then
        v_efeito := 'ao_dono';
        v_o_que := 'falou do mesmo dia combinado';
      elsif v_dia is not null and v_de < v_dia then
        -- (decisão do P4) mais cedo que o combinado: o "não antes de" não adianta nada; é o dono que vê se dá
        v_efeito := 'ao_dono';
        v_o_que := format('pediu um dia antes do combinado (%s)', public._dia_curto(v_de));
      -- CORREÇÃO FASE 5: (item 9) o dia pedido longe demais do combinado (mais de cliente_pedido_max_du dias úteis) não
      -- remarca sozinho: é o dono que vê
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_de) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('pediu %s, mais de %s dias úteis depois do combinado: remarque você', public._dia_curto(v_de),
                          cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid,
                 case when v_dia is not null then daterange(v_dia, v_dia, '[]') end, v_de,
                 format('O %s pediu %s', v_nome,
                        case when v_ate > v_de then 'a partir de ' || public._dia_curto(v_de) else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 17) falta/remarcar com um número de dia que o banco não entendeu ("tô viajando, volto dia 20",
    -- "só depois de 20/11"): tirar só o dia combinado remarcaria para quando ele ainda está fora — vai ao dono
    elsif v_int in ('remarcar', 'falta') and v_data is null
          and public._agenda_preparar_data(coalesce(v_trecho, '')) ~ '(\mdia \d{1,2}\M|\m\d{1,2}/\d{1,2})' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou de outro dia, que eu não entendi';
    -- CORREÇÃO FASE 5: fim
    elsif v_int in ('remarcar', 'falta') then
      -- o dia recusado: o que ele disse (convertido pelo banco), senão o dia da mensagem
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null or v_ate < v_hoje then
        v_de := v_dia;
        v_ate := v_dia;
      end if;
      v_de := greatest(v_de, v_hoje);
      if v_de is null or v_ate < v_de then
        v_efeito := 'ao_dono';
        v_o_que := 'pediu outro dia';
      elsif not (v_dia between v_de and v_ate)
            and not exists (select 1 from public.agenda_alocacoes a
                             where a.service_order_id = m.service_order_id and a.estado in ('publicada', 'fixada')
                               and a.tipo <> 'reserva' and a.dia between v_de and v_ate) then
        -- (decisão do P4) o dia recusado não é dia do serviço ("não dá amanhã" no sábado, com o serviço na terça): não
        -- adivinho de qual dia ele fala
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá %s, mas não é dia do serviço',
                          case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                               else public._dia_curto(v_de) end);
      -- CORREÇÃO FASE 5: (item 9) tirar dias até longe demais do combinado ("vou viajar até 20/12") também não remarca sozinho
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_ate) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá até %s, mais de %s dias úteis depois do combinado: remarque você',
                          public._dia_curto(v_ate), cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid, daterange(v_de, v_ate, '[]'), null,
                 format('O %s pediu outro dia (%s não dá)', v_nome,
                        case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                             else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 16) o acesso com negação ("não sei onde vai estar a chave", "não tenho a chave", "ainda não
    -- sei") não é acesso dito: não vai para o campo da OS nem desliga a pergunta do acesso — vai ao dono
    elsif v_int = 'acesso' and public._agenda_normal(coalesce(v_trecho, '')) ~ '\m(nao sei|nao tenho|ainda nao)\M' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou do acesso, mas ainda não sabe (ou não tem) a chave';
    -- CORREÇÃO FASE 5: fim
    elsif v_int = 'acesso' and (v_do_dia or m.tipo = 'pode_atrasar') then
      v_x := public._agenda_cliente_anotar_acesso(m.id, v_rid, v_trecho, v_hoje, p_agora);
      v_efeito := 'anotou_acesso';
      v_acao := (v_x ->> 'acao_id')::uuid;
      v_texto := v_x ->> 'texto';
    else
      v_efeito := 'ao_dono';
      v_o_que := case when v_int = 'acesso' then 'falou do acesso' else 'não entendi o que ele quer' end;
    end if;
  exception when others then
    -- o efeito que falha não derruba o webhook: a resposta vai ao dono e o erro fica consultável
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a resposta do cliente falhou: ' || v_msg, 'agenda', 'cliente:resposta', 'error',
                                 jsonb_build_object('mensagem', m.id, 'resposta', v_rid, 'intencao', v_int, 'sqlstate', v_estado));
    v_efeito := 'ao_dono';
    v_acao := null;
    v_acorde := false;
    v_o_que := 'não consegui ler a resposta sozinho';
    v_texto := null;
  end;

  -- ao dono: a pergunta cliente_resposta (sem opções; some em 7 dias), e o acorde na hora quando é reclamação
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := coalesce(v_texto, format('O %s respondeu "%s" %s: %s. Não respondi nada; é com você.', v_nome,
                                        public._agenda_corta(coalesce(v_trecho, ''), 120), v_ref, v_o_que));
    v_perg := public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:' || v_rid, m.service_order_id, v_dia,
                                               case when v_do_dia then v_dia end, v_texto, 'ligado', p_agora,
                                               p_agora + c_pergunta_dias);
    if v_acorde then
      v_acao := public._agenda_cliente_acorde(m.service_order_id, 'cliente_resposta:' || v_rid, v_texto, v_hoje, v_hoje, v_perg);
    end if;
  end if;

  -- a mensagem respondida (antes das 48 h o "não respondeu" não a pega; depois, a pergunta dele se resolve)
  if v_efeito <> 'ambigua' then
    update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = v_rid
     where id = m.id and estado in ('enviada', 'sem_resposta');
    -- FASE 6: (P7) o motivo sem artigo antes do nome; o update de antes, logo abaixo, não acha mais a pergunta aberta
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('%s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
    -- FASE 6: fim
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('O %s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
  end if;
  update public.agenda_cliente_respostas
     set efeito = v_efeito, acao_id = v_acao, pergunta_id = v_perg, data_dita = coalesce((v_data ->> 'de')::date, data_dita)
   where id = v_rid;
  -- CORREÇÃO FASE 5: (item 15) o texto devolvido, quando é o da pergunta ao dono, sem artigo antes do nome ("Flávio
  -- respondeu …"), igual à pergunta; o das ações (confirmou, pediu, opt-out) fica como a ação gravada
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := public._agenda_cliente_sem_artigo(v_texto, m.service_order_id);
  end if;
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', v_efeito, 'intencao', v_int, 'texto', v_texto,
                            'resposta_id', v_rid, 'mensagem_id', m.id, 'acao_id', v_acao, 'pergunta_id', v_perg);
end;
$function$;

comment on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) is
  'Agenda de Produção (Fase 5, P4): a mensagem do cliente que chega pelo WhatsApp (o webhook chama depois da equipe e antes da confirmação de 30/09 e da conferência do recibo: o "ok" tem um dono só). modo_cliente desligado, número de ninguém (ou do dono, da equipe, de quem recebe diária), a mesma mensagem de novo ou sem mensagem da agenda esperando resposta (a última dos tipos que esperam, enviada dentro de cliente_resposta_validade e ainda sem resposta; em teste, a que teria saído) = consumiu false. Em teste: registra a resposta (efeito sombra, com a intenção) e consumiu false. Ligado, a 1ª que vale: duas OS ou dois clientes no número = ambígua (ao dono); áudio e mídia ao dono (o áudio NUNCA confirma); o SIM curto (_e_concordancia) confirma o M1/M3/M7/M10 e o M6 remarcado (_agenda_cliente_confirmar_dia: fixa o dia, com *desfaz*), registra a véspera e o acesso, é ciência no aviso de atraso, vai ao dono no "ficou pronto" e não faz nada no pós-serviço; opt-out = as vivas recusadas (opt_out) e o cadastro marcado, calado; reclamação (na hora, por acorde), negociação, acordo e pergunta ao dono; o dia pedido (data) e o recusado (remarcar, falta) — só nas mensagens que propõem um dia e com modo_proposta ligado — viram o "não antes de" e o bem indisponível com o replano (_agenda_cliente_pedido_de_dia, com *desfaz*; o dia combinado em até 1 dia útil = acorde); o dia passado, de hoje, o mesmo ou mais cedo que o combinado vai ao dono; o acesso dito vai para o campo da OS (_agenda_cliente_anotar_acesso, com *desfaz*); o resto ao dono. Ao dono = a pergunta cliente_resposta:<resposta> (some em 7 dias). A mensagem fica respondida (resposta_id) e a pergunta do "não respondeu" dela se resolve. O efeito que falha vai ao dono e a app_error_logs (cliente:resposta). {consumiu, modo, efeito, intencao, texto, resposta_id, mensagem_id, acao_id, pergunta_id}. Só service_role. CORREÇÃO FASE 5 (C1): (A1) a resposta só é da agenda quando a última mensagem da HBR ao número é a dela — o botão antigo ou outra mensagem outbound depois dela (_agenda_cliente_outra_conversa) = {consumiu:false, motivo:outra_conversa}, em teste também; (item 2) o opt-out vale para quem recebeu mensagem da agenda em 30 dias, mesmo sem mensagem esperando, depois de outra conversa ou com o número ambíguo (efeito opt_out, consumiu true); (item 16) o acesso com negação vai ao dono; (item 17) falta/remarcar com um número de dia não entendido vai ao dono; (item 9) o dia pedido ou o fim do recusado a mais de cliente_pedido_max_du dias úteis do combinado vai ao dono. CORREÇÃO FASE 5 (C2, item 15): o texto devolvido (o da pergunta cliente_resposta ao dono) sem artigo antes do nome. FASE 6 (P7, spec-fase6 §6.4): a ação do opt-out sem artigo e sem "a ele" ("Nelson pediu para não receber mais mensagens: não mando mais nada."), a ambígua escrita já sem artigo ("Chegou "ok" do número de Kalmar, mas há 2 serviços esperando resposta do cliente: …"), o motivo da pergunta do "não respondeu" ("Nelson respondeu."); a pergunta ao dono sai sem "ele" pelo ralo ("não entendi o pedido", "o dia pedido já passou ou é hoje", "combine a entrega com o cliente"); as ações do SIM, do dia pedido e do acesso vêm sem artigo das funções delas.';

-- _agenda_cliente_da_os (de 20261028100800_agenda_fase5_correcao_rodada.sql)
create or replace function public._agenda_cliente_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  so        record;
  pl        public.os_planejamento%rowtype;
  v_tel     boolean;
  v_sem     boolean;
  v_conv    boolean;
  v_contato text;
  v_prom    jsonb;
  v_risco   jsonb;
  v_risco_t text;
  v_msgs    jsonb;
  v_total   int;
  v_esp     int;
  v_ped     int;
  v_esp_t   text;
  -- estrutura, não parâmetro: a lista curta do cartão (spec §5.6, "até 5"); o resto, *agenda clientes* mostra
  c_lista   constant int := 5;
begin
  select s.id, s.client_id, s.client_confirmed_for,
         public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(c.display_name, '')), ''), c.name)) as nome
    into so
    from public.service_orders s left join public.clients c on c.id = s.client_id
   where s.id = p_os;
  if so.id is null or so.client_id is null then
    return null;
  end if;
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;

  -- o contato (as mesmas regras do envio e do foco: o número que é de alguém da HBR conta como sem telefone)
  v_tel := public._agenda_cliente_telefone(so.client_id) is not null;
  v_sem := public._agenda_cliente_sem_mensagem(so.client_id);
  v_conv := public._agenda_cliente_conversou(so.client_id, v_agora);
  v_contato := case when not v_tel then 'sem telefone no cadastro'
                    when v_sem then 'pediu para não receber mensagens'
                    when not v_conv then 'não escreveu para a HBR no último ano; por ora só mando a quem já escreveu' end;

  -- o que foi dito ao cliente (≠ o plano) e se ainda vale
  if pl.prometido_ate is not null then
    v_risco := public._agenda_cliente_risco(p_os, p_hoje);
    if coalesce((v_risco ->> 'risco')::boolean, false) then
      v_risco_t := case
        when coalesce((v_risco ->> 'sem_data')::boolean, false)
          then 'Pode atrasar: o material ainda não tem previsão, então ainda não sei a data nova.'
        when v_risco ->> 'faixa_de' = v_risco ->> 'faixa_ate'
          then format('Pode atrasar: agora a previsão é %s.', public._dia_curto((v_risco ->> 'faixa_de')::date))
        else format('Pode atrasar: agora a previsão é de %s a %s.', public._dia_curto((v_risco ->> 'faixa_de')::date),
                    public._dia_curto((v_risco ->> 'faixa_ate')::date)) end
        || case when coalesce((v_risco ->> 'passou')::boolean, false) then ' A data que ele ouviu já passou.' else '' end;
      -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4): " A data dita já passou." (pelo ralo do texto ao dono)
      v_risco_t := public._agenda_cliente_sem_artigo(v_risco_t, p_os);
      -- FASE 6: fim
    end if;
    v_prom := jsonb_build_object(
      'tipo', pl.prometido_tipo, 'de', coalesce(pl.prometido_de, pl.prometido_ate), 'ate', pl.prometido_ate,
      'original_ate', pl.prometido_original_ate, 'fonte', pl.prometido_fonte,
      'texto', case when coalesce(pl.prometido_de, pl.prometido_ate) = pl.prometido_ate then public._dia_curto(pl.prometido_ate)
                    else format('de %s a %s', public._dia_curto(pl.prometido_de), public._dia_curto(pl.prometido_ate)) end
               || format(' (%s, %s%s)',
                         case pl.prometido_tipo when 'firme' then 'data firme' when 'faixa' then 'uma faixa'
                                                else 'depende da peça' end,
                         case pl.prometido_fonte when 'mensagem' then 'por mensagem da agenda' when 'dono' then 'por você'
                                                 else 'pela confirmação' end,
                         coalesce(' em ' || public._dia_curto((pl.prometido_em at time zone 'America/Sao_Paulo')::date), ''))
               || case when pl.prometido_original_ate is not null and pl.prometido_original_ate <> pl.prometido_ate
                       then format('; a 1ª data dita foi %s', public._dia_curto(pl.prometido_original_ate)) else '' end,
      'risco_texto', v_risco_t);
  end if;

  -- as mensagens desta OS: as 5 mais recentes (a que vai sair primeiro, depois as que saíram), com o estado como o dono lê
  select count(*)::int into v_total from public.agenda_cliente_mensagens m where m.service_order_id = p_os;
  select coalesce(jsonb_agg(y.j order by y.quando desc, y.id desc), '[]'::jsonb) into v_msgs
    from (select m.id, coalesce(m.enviada_em, m.enviar_em) as quando,
                 jsonb_build_object(
                   'tipo', m.tipo,
                   'tipo_texto', public._agenda_maiuscula(public._agenda_cliente_tipo_texto(m.tipo)),
                   'quando_texto', case
                     -- a viva: quando sai ("agora", "amanhã às 09:00"; a do teste, só a que ainda vai sair); a que saiu
                     -- ou a do teste que teria saído: o dia e a hora
                     when m.enviada_em is null and m.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                          and (m.modo = 'ligado' or m.enviar_em > v_agora)
                       then public._agenda_cliente_quando_texto(m.enviar_em, v_agora)
                     else public._dia_curto((coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo')::date)
                          || ' às ' || to_char(coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo', 'HH24:MI') end,
                   'estado', m.estado,
                   'estado_texto', case
                     when m.modo = 'sombra' then case
                       when m.estado = 'recusada' then 'em teste: não sairia'
                       when m.enviar_em <= v_agora then 'em teste: teria saído'
                       else 'em teste: sairia' end
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'critica'
                       then 'é uma decisão sua: responda na conversa (1, 2 ou 3)'
                     when m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
                       then 'espera você'
                     when m.estado in ('registrada', 'aguardando_dono') and m.aprovacao = 'aprovada'
                       then format('você aprovou (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado in ('registrada', 'aguardando_dono')
                       then format('sai sozinha (para não mandar: *segura cliente %s*)', so.nome)
                     when m.estado = 'enfileirada' then 'na fila do WhatsApp'
                     when m.estado = 'enviada' then 'mandada'
                     when m.estado = 'sem_resposta' then 'mandada; sem resposta'
                     when m.estado = 'respondida'
                       then 'mandada; respondeu: ' || public._agenda_cliente_efeito_texto(a.efeito)
                     when m.recusa_motivo = 'segurada' then 'você segurou: não saiu'
                     else 'não saiu: ' || case
                       when m.recusa_motivo in ('modo', 'tipo_em_teste') then 'estava em teste'
                       when m.recusa_motivo = 'opt_out' then 'ele pediu para não receber mensagens'
                       when m.recusa_motivo = 'sem_telefone' then 'sem telefone no cadastro'
                       when m.recusa_motivo = 'sem_conversa' then 'ele não escreveu para a HBR no último ano'
                       when m.recusa_motivo in ('domingo', 'feriado', 'janela', 'vencida') then 'passou da hora'
                       when m.recusa_motivo in ('teto_dia', 'teto_semana', 'teto_total')
                         then 'ele já tinha recebido as mensagens que cabem'
                       -- o motivo do mesmo tipo recente vai pelo prefixo: o nome dele leva o número de horas, que a
                       -- varredura do agenda-sem-literal não deixa no corpo
                       when m.recusa_motivo = 'intervalo' or left(m.recusa_motivo, 10) = 'mesmo_tipo'
                         then 'ele tinha acabado de receber outra'
                       when m.recusa_motivo in ('status', 'data_mudou', 'material', 'desatualizada')
                         then 'o serviço mudou antes de sair'
                       when m.recusa_motivo = 'passou_da_data' then 'a data que ele ouviu já tinha passado'
                       else 'o texto não passou na conferência' end end,
                   'texto', m.texto,
                   'em_teste', m.modo = 'sombra',
                   'espera_voce', m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')) as j
            from public.agenda_cliente_mensagens m
            left join public.agenda_cliente_respostas a on a.id = m.resposta_id
           where m.service_order_id = p_os
           order by coalesce(m.enviada_em, m.enviar_em) desc, m.id desc
           limit c_lista) y;
  -- FASE 6: (P7) o estado de cada mensagem como o dono lê, sem "ele" ("não saiu: o cliente pediu para não receber
  -- mensagens", "não saiu: a data dita já tinha passado"), pelo ralo do texto ao dono
  select coalesce(jsonb_agg(case when t.e ->> 'estado_texto' is null then t.e
                                 else jsonb_set(t.e, '{estado_texto}',
                                                to_jsonb(public._agenda_cliente_sem_artigo(t.e ->> 'estado_texto', p_os))) end
                            order by t.o), '[]'::jsonb)
    into v_msgs
    from jsonb_array_elements(v_msgs) with ordinality t(e, o);
  -- FASE 6: fim

  -- o que espera o dono: a mesma conta do foco clientes (a mensagem que espera *manda cliente*, a decisão do aviso, a
  -- resposta que foi ao dono); a palavra só em ligado (em teste ela responde que nada sai ainda)
  -- CORREÇÃO FASE 5: (regressão B3) a conta do que espera o dono direto nas tabelas — as mesmas condições do bloco
  -- "Esperando você" do foco clientes (a mensagem que espera *manda cliente* ou que é decisão; a decisão sem mensagem; a
  -- resposta que foi ao dono, sem o "não respondeu"), e desligado = 0 como o foco —, sem montar o foco inteiro (e o d10 de
  -- cada cliente) a cada abertura do cartão
  v_esp := case when cf.modo_cliente = 'desligado' then 0 else
             (select count(*)::int from public.agenda_cliente_mensagens m
               where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')
                 and m.service_order_id = p_os)
           + (select count(*)::int from public.agenda_perguntas q
               where q.modo = 'ligado' and q.estado = 'aberta' and (q.expira_em is null or q.expira_em > v_agora)
                 and q.service_order_id = p_os
                 and ((q.tipo = 'cliente_resposta' and q.chave not like 'cliente_resposta:sem_resposta:%')
                      or (q.tipo = 'cliente_aviso'
                          and not exists (select 1 from public.agenda_cliente_mensagens x where x.pergunta_id = q.id)))) end;
  if v_esp is null then
  -- CORREÇÃO FASE 5: fim
  v_esp := coalesce((public._agenda_ver_clientes(p_os, p_hoje) #>> '{dados,esperando}')::int, 0);
  -- CORREÇÃO FASE 5: o foco inteiro não roda mais (a conta acima nunca é nula)
  end if;
  -- CORREÇÃO FASE 5: fim
  select count(*)::int into v_ped from public.agenda_cliente_mensagens m
   where m.service_order_id = p_os and m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida';
  if cf.modo_cliente = 'ligado' and v_esp > 0 then
    v_esp_t := case when v_ped > 0
                    then format('%s esperando você: *manda cliente %s* manda; *segura cliente %s* segura.',
                                public._agenda_plural(v_ped, 'mensagem', 'mensagens'), so.nome, so.nome)
                    else '' end
               || case when v_esp > v_ped
                       then case when v_ped > 0 then ' ' else '' end
                            || 'Há decisão ou resposta dele esperando você: responda na conversa (*agenda clientes* mostra).'
                       else '' end;
  end if;

  -- FASE 6: (P7) o cartão sem "ele" (spec-fase6 §6.4): "O cliente confirmou qui 05/11." e "Há decisão ou resposta do cliente
  -- esperando você …"; o retorno de antes, logo abaixo, não roda mais
  return jsonb_build_object(
    'modo', cf.modo_cliente,
    'em_teste', cf.modo_cliente = 'sombra',
    'em_teste_texto', case when cf.modo_cliente = 'sombra'
                           then 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.' end,
    'nome', so.nome,
    'telefone_ok', v_tel, 'conversou', v_conv, 'opt_out', v_sem, 'contato_texto', v_contato,
    'servico', pl.servico_cliente,
    'prometido', v_prom,
    'confirmado_texto', case when so.client_confirmed_for is not null
                             then format('O cliente confirmou %s.',
                                         public._dia_curto((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date)) end,
    'mensagens', v_msgs,
    'mensagens_mais', greatest(v_total - jsonb_array_length(v_msgs), 0),
    'esperando_voce', jsonb_build_object('n', v_esp, 'texto', public._agenda_cliente_sem_artigo(v_esp_t, p_os)));
  -- FASE 6: fim
  return jsonb_build_object(
    'modo', cf.modo_cliente,
    'em_teste', cf.modo_cliente = 'sombra',
    'em_teste_texto', case when cf.modo_cliente = 'sombra'
                           then 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.' end,
    'nome', so.nome,
    'telefone_ok', v_tel, 'conversou', v_conv, 'opt_out', v_sem, 'contato_texto', v_contato,
    'servico', pl.servico_cliente,
    'prometido', v_prom,
    'confirmado_texto', case when so.client_confirmed_for is not null
                             then format('Ele confirmou %s.',
                                         public._dia_curto((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date)) end,
    'mensagens', v_msgs,
    'mensagens_mais', greatest(v_total - jsonb_array_length(v_msgs), 0),
    'esperando_voce', jsonb_build_object('n', v_esp, 'texto', v_esp_t));
end;
$function$;

comment on function public._agenda_cliente_da_os(uuid, date) is
  'Agenda de Produção (Fase 5, P6): a chave cliente do cartão "Plano" (os_plano_da_os) — {modo, em_teste, em_teste_texto, nome, telefone_ok, conversou, opt_out (não recebe: opt-out, inativo ou bloqueado), contato_texto ("sem telefone no cadastro" | "pediu para não receber mensagens" | "não escreveu para a HBR no último ano…" | null), servico (como o serviço é dito ao cliente), prometido {tipo, de, ate, original_ate, fonte, texto "qui 05/11 (data firme, por mensagem da agenda em qui 22/10)", risco_texto (_agenda_cliente_risco: "Pode atrasar: agora a previsão é de qui 12/11 a sex 13/11.")} | null, confirmado_texto, mensagens (as 5 mais recentes desta OS: [{tipo, tipo_texto, quando_texto, estado, estado_texto, texto, em_teste, espera_voce}]), mensagens_mais, esperando_voce {n (a conta do foco clientes, _agenda_ver_clientes), texto (só em ligado: *manda cliente <nome>* / *segura cliente <nome>*)}}. Nenhum botão de mandar: a aprovação é pela palavra. A hora de agora: agenda.agora (a bancada), senão now(). Invoker e sem grant: só os_plano_da_os a chama. null sem a OS ou sem o cliente. CORREÇÃO FASE 5 (C2, B3): esperando_voce.n é contado direto nas tabelas (as mesmas condições do bloco "Esperando você" do foco), sem chamar _agenda_ver_clientes. FASE 6 (P7, spec-fase6 §6.4): sem "ele" — " A data dita já passou.", "O cliente confirmou qui 05/11.", "Há decisão ou resposta do cliente esperando você …" e o estado de cada mensagem ("não saiu: o cliente pediu para não receber mensagens").';

-- _agenda_cliente_confirmar_dia (de 20261028100400_agenda_fase5_respostas.sql)
create or replace function public._agenda_cliente_confirmar_dia(p_msg uuid, p_resposta uuid, p_trecho text, p_hoje date,
                                                                p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  m      public.agenda_cliente_mensagens%rowtype;
  v_dia  date;
  v_ini  timestamptz;
  v_so   record;
  v_fix  uuid[];
  v_nome text;
  v_acao uuid;
  v_txt  text;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  select min(lower(a.periodo)) into v_ini
    from public.agenda_alocacoes a
   where a.service_order_id = m.service_order_id and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
  if v_ini is null then
    return jsonb_build_object('ok', false, 'o_que',
      format('confirmou, mas esse dia (%s) não está mais no plano: confira', coalesce(public._dia_curto(v_dia), 'sem dia')));
  end if;
  select so.client_confirmed_at, so.client_confirmed_for, cl.name, cl.display_name into v_so
    from public.service_orders so join public.clients cl on cl.id = so.client_id
   where so.id = m.service_order_id for update of so;
  v_nome := coalesce(public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(v_so.display_name, '')), ''), v_so.name)), 'cliente');
  with x as (
    update public.agenda_alocacoes a set estado = 'fixada', fixado_por = 'cliente_confirmou'
     where a.service_order_id = m.service_order_id and a.dia = v_dia and a.estado = 'publicada' and a.tipo <> 'reserva'
    returning a.id)
  select coalesce(array_agg(x.id order by x.id), '{}'::uuid[]) into v_fix from x;
  update public.service_orders set client_confirmed_at = p_agora, client_confirmed_for = v_ini where id = m.service_order_id;
  v_txt := format('O %s confirmou %s.', v_nome, public._dia_curto(v_dia));
  -- FASE 6: (P7) sem artigo antes do nome (spec-fase6 §6.4): "Flávio confirmou ter 03/11."
  v_txt := format('%s confirmou %s.', v_nome, public._dia_curto(v_dia));
  -- FASE 6: fim
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'fixar', m.service_order_id, array[m.service_order_id],
          jsonb_build_object('alocacoes', to_jsonb(v_fix), 'estado', 'publicada',
                             'client_confirmed_at', v_so.client_confirmed_at, 'client_confirmed_for', v_so.client_confirmed_for),
          jsonb_build_object('efeito', 'confirmou', 'resposta_id', p_resposta, 'mensagem_id', m.id, 'dia', v_dia,
                             'alocacoes', to_jsonb(v_fix), 'estado', 'fixada', 'fixado_por', 'cliente_confirmou',
                             'client_confirmed_at', p_agora, 'client_confirmed_for', v_ini, 'trecho', public._agenda_corta(p_trecho, 200)),
          v_txt, 'o cliente confirmou', p_agora + cf.desfazer_validade)
  returning id into v_acao;
  -- o sino, como o "sim" do botão de 30/09
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'agendamento_confirmado', v_nome || ' confirmou o atendimento',
         public._dia_curto(v_dia) || ' — respondeu "' || left(btrim(coalesce(p_trecho, '')), 40) || '" pelo WhatsApp.',
         '/v2/service-orders/' || m.service_order_id
    from public.app_users u where u.role = 'admin' and u.active;
  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'texto', v_txt, 'fixadas', cardinality(v_fix));
end;
$function$;

comment on function public._agenda_cliente_confirmar_dia(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o SIM do cliente à mensagem que propôs o dia (o dia_alvo da base) — client_confirmed_at = agora e client_confirmed_for = o início do 1º meio-dia vigente do dia; as alocações publicadas do dia viram fixada (cliente_confirmou); a ação fixar (origem cliente, antes/depois, desfazivel_ate = agora + desfazer_validade) "O Flávio confirmou ter 03/11." e o sino dos administradores. Sem meio-dia vigente no dia: {ok: false, o_que} e nada muda. Interna (sem grant). FASE 6 (P7, spec-fase6 §6.4): a ação sem artigo antes do nome ("Flávio confirmou ter 03/11.").';

-- _agenda_cliente_anotar_acesso (de 20261028100400_agenda_fase5_respostas.sql)
create or replace function public._agenda_cliente_anotar_acesso(p_msg uuid, p_resposta uuid, p_trecho text, p_hoje date,
                                                                p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       public.agenda_cliente_mensagens%rowtype;
  v_antes text;
  v_dep   text;
  v_linha text;
  v_ok    timestamptz;
  v_nome  text;
  v_txt   text;
  v_acao  uuid;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  select so.site_access into v_antes from public.service_orders so where so.id = m.service_order_id for update;
  v_linha := format('Cliente (%s): %s', to_char(p_hoje, 'DD/MM'), left(btrim(coalesce(p_trecho, '')), 300));
  v_dep := case when coalesce(v_antes, '') = '' then v_linha else v_antes || E'\n' || v_linha end;
  update public.service_orders set site_access = v_dep where id = m.service_order_id;
  insert into public.os_planejamento (service_order_id) values (m.service_order_id) on conflict (service_order_id) do nothing;
  select pl.acesso_ok_em into v_ok from public.os_planejamento pl where pl.service_order_id = m.service_order_id for update;
  update public.os_planejamento set acesso_ok_em = p_agora, atualizado_em = p_agora where service_order_id = m.service_order_id;
  v_txt := format('Anotei o acesso que o %s disse: "%s".', v_nome, public._agenda_corta(btrim(coalesce(p_trecho, '')), 200));
  -- FASE 6: (P7) sem artigo antes do nome (spec-fase6 §6.4); o que o cliente disse, entre aspas, fica como ele escreveu
  v_txt := format('Anotei o acesso que %s disse: "%s".', v_nome, public._agenda_corta(btrim(coalesce(p_trecho, '')), 200));
  -- FASE 6: fim
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'cliente', m.service_order_id, array[m.service_order_id],
          jsonb_build_object('site_access', v_antes, 'acesso_ok_em', v_ok),
          jsonb_build_object('efeito', 'anotou_acesso', 'resposta_id', p_resposta, 'mensagem_id', m.id,
                             'site_access', v_dep, 'acesso_ok_em', p_agora, 'linha', v_linha),
          public._agenda_corta(v_txt, 400), 'o cliente disse o acesso', p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'texto', public._agenda_corta(v_txt, 400));
end;
$function$;

comment on function public._agenda_cliente_anotar_acesso(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o acesso dito pelo cliente — uma linha nova no fim de service_orders.site_access ("Cliente (31/10): <até 300>"; o que havia fica igual, byte a byte), os_planejamento.acesso_ok_em = agora (a véspera deixa de perguntar por cliente_acesso_validade_dias) e a ação cliente (origem cliente; antes/depois do campo) "Anotei o acesso que o Flávio disse: …", com desfazivel_ate. O gatilho das datas não se mexe (site_access não é data). Interna (sem grant). FASE 6 (P7, spec-fase6 §6.4): a ação sem artigo antes do nome ("Anotei o acesso que Nelson disse: "…".").';

-- _agenda_cliente_pedido_de_dia (de 20261028100400_agenda_fase5_respostas.sql)
create or replace function public._agenda_cliente_pedido_de_dia(p_msg uuid, p_resposta uuid, p_tirar daterange, p_nao_antes date,
                                                                p_pedido text, p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  m        public.agenda_cliente_mensagens%rowtype;
  p        public.os_planejamento%rowtype;
  v_os     uuid;
  v_dia    date;
  v_nome   text;
  v_add    datemultirange;
  v_tirado datemultirange;
  v_nao    date;
  v_motivo text;
  v_rep    jsonb;
  v_novo   date;
  v_crit   boolean;
  v_acorde boolean;
  v_txt    text;
  v_acao   uuid;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_os := m.service_order_id;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
  select * into p from public.os_planejamento where service_order_id = v_os for update;
  v_add := case when p_tirar is null or isempty(p_tirar) then '{}'::datemultirange else datemultirange(p_tirar) end;
  v_tirado := v_add - p.bem_indisponivel;
  v_nao := case when p_nao_antes is not null and (p.nao_antes_de is null or p_nao_antes > p.nao_antes_de) then p_nao_antes
                else p.nao_antes_de end;
  v_motivo := case when v_nao is distinct from p.nao_antes_de then 'o cliente pediu' else p.nao_antes_motivo end;
  update public.os_planejamento
     set bem_indisponivel = p.bem_indisponivel + v_add, nao_antes_de = v_nao, nao_antes_motivo = v_motivo,
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', p_hoje, 'autor', null, 'trecho', public._agenda_corta(p_trecho, 500),
           'antes', jsonb_build_object('bem_indisponivel', p.bem_indisponivel::text, 'nao_antes_de', p.nao_antes_de),
           'depois', jsonb_build_object('bem_indisponivel', (p.bem_indisponivel + v_add)::text, 'nao_antes_de', v_nao))),
         atualizado_em = p_agora
   where service_order_id = v_os;
  v_rep := public.agenda_replanejar(array[v_os], 'o cliente pediu outro dia', 'vigia', p_hoje, p_agora, null);
  v_novo := (public._agenda_plano_da_os(v_os, p_hoje) ->> 'proximo_dia')::date;
  v_crit := jsonb_array_length(coalesce(v_rep -> 'perguntas', '[]'::jsonb)) > 0;
  -- "O Flávio pediu sex 06/11: remarquei para seg 09/11, o 1º dia que coube." / "O Flávio pediu outro dia (ter 03/11 não
  -- dá): tirei o dia e remarquei para qui 05/11." / "…: tirei o dia; a decisão ficou com você." (spec §6.3)
  v_txt := p_pedido || ': '
           || case when p_nao_antes is not null
                   then case when not v_crit and v_novo is not null
                             then 'remarquei para ' || public._dia_curto(v_novo)
                                  || case when v_novo > p_nao_antes then ', o 1º dia que coube' else '' end || '.'
                             else 'anotei; a decisão ficou com você.' end
                   else case when not v_crit and v_novo is not null
                             then 'tirei o dia e remarquei para ' || public._dia_curto(v_novo) || '.'
                             else 'tirei o dia; a decisão ficou com você.' end end
           || format(' *desfaz %s* volta como estava.', v_nome);
  -- FASE 6: (P7) sem artigo antes do nome (spec-fase6 §6.4): o pedido vem da resposta como "O Flávio pediu …" e sai
  -- "Flávio pediu outro dia (ter 03/11 não dá): …" (pelo ralo do texto ao dono; nada do cliente citado entra aqui)
  v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
  -- FASE 6: fim
  -- o dia que a equipe esperava ir é hoje ou o próximo dia útil: o dono fica sabendo na hora (acorde)
  v_acorde := v_dia is not null and v_dia <= public.agenda_somar_du(p_hoje, 1);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'cliente', v_os, array[v_os],
          jsonb_build_object('bem_indisponivel', p.bem_indisponivel::text, 'nao_antes_de', p.nao_antes_de,
                             'nao_antes_motivo', p.nao_antes_motivo),
          jsonb_build_object('efeito', 'replanejou', 'resposta_id', p_resposta, 'mensagem_id', m.id, 'dia', v_dia,
                             'tirado', v_tirado::text, 'nao_antes_de', v_nao, 'nao_antes_motivo', v_motivo,
                             'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb), 'critica', v_crit, 'novo_dia', v_novo,
                             'acorde', v_acorde, 'acorde_chave', 'cliente_resposta:' || p_resposta, 'perda_em', v_dia),
          public._agenda_corta(v_txt, 400), 'o cliente pediu outro dia', p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'texto', public._agenda_corta(v_txt, 400), 'novo_dia', v_novo,
                            'critica', v_crit, 'acorde', v_acorde, 'replano', v_rep -> 'texto');
end;
$function$;

comment on function public._agenda_cliente_pedido_de_dia(uuid, uuid, daterange, date, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o pedido de dia do cliente — os_planejamento.bem_indisponivel + p_tirar (os dias recusados), nao_antes_de = p_nao_antes (o maior dos dois; motivo "o cliente pediu"), o histórico, e agenda_replanejar (vigia; a criticidade da Fase 2 vale). A ação cliente (origem cliente; antes = o planejamento, depois = {efeito replanejou, tirado, nao_antes_de, replano_acoes, critica, novo_dia, acorde}) "O Flávio pediu outro dia (ter 03/11 não dá): tirei o dia e remarquei para qui 05/11. *desfaz Flávio* volta como estava.", com desfazivel_ate; o dia combinado em até 1 dia útil = acorde (depois.acorde). Interna (sem grant). FASE 6 (P7, spec-fase6 §6.4): a ação sem artigo antes do nome ("Flávio pediu outro dia (ter 03/11 não dá): tirei o dia e remarquei para qui 05/11. …"), pelo ralo _agenda_cliente_sem_artigo.';

-- _agenda_desfazer_cliente (de 20261028100400_agenda_fase5_respostas.sql)
create or replace function public._agenda_desfazer_cliente(p_acao uuid, p_autor uuid, p_via text, p_hoje date,
                                                           p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_a     public.agenda_acoes%rowtype;
  v_os    uuid;
  v_nome  text;
  v_ef    text;
  v_x     record;
  v_id    uuid;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_r     jsonb;
  v_falha boolean := false;
  v_n     int := 0;
  v_sa    text;
  v_novo  date;
  v_txt   text;
  v_acao  uuid;
begin
  select * into v_a from public.agenda_acoes where id = p_acao;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.service_orders so join public.clients cl on cl.id = so.client_id where so.id = v_os), 'cliente');
  v_ef := v_a.depois ->> 'efeito';
  if v_ef = 'opt_out' then
    -- FASE 6: (P7) sem artigo antes do nome e sem "ele" (spec-fase6 §6.4); o retorno de antes, logo abaixo, não roda mais
    return jsonb_build_object('ok', false,
      'texto', format('O pedido de %s para não receber mensagens não se desfaz por aqui: só o cliente pode pedir para voltar.', v_nome));
    -- FASE 6: fim
    return jsonb_build_object('ok', false,
      'texto', format('O pedido do %s para não receber mensagens não se desfaz por aqui: só ele pode pedir para voltar.', v_nome));
  end if;
  if v_ef is null or v_ef not in ('confirmou', 'replanejou', 'anotou_acesso') or v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa resposta do cliente não mudou nada para desfazer.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    -- FASE 6: (P7) sem artigo antes do nome (spec-fase6 §6.4); o retorno de antes, logo abaixo, não roda mais
    return jsonb_build_object('ok', false,
      'texto', format('Não dá mais para desfazer o que %s respondeu: passou o prazo. Se quiser mudar, me diga o dia.', v_nome));
    -- FASE 6: fim
    return jsonb_build_object('ok', false,
      'texto', format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome));
  end if;

  if v_ef = 'confirmou' then
    if exists (select 1 from public.agenda_alocacoes a
                where a.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_a.depois -> 'alocacoes', '[]'::jsonb)) x)
                  and a.estado = 'fixada' and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
      -- FASE 6: (P7) sem artigo antes do nome (spec-fase6 §6.4); o retorno de antes, logo abaixo, não roda mais
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: já começou o dia que %s confirmou.', v_nome));
      -- FASE 6: fim
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: já começou o dia que o %s confirmou.', v_nome));
    end if;
    for v_x in select a.* from public.agenda_alocacoes a
                where a.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_a.depois -> 'alocacoes', '[]'::jsonb)) x)
                  and a.estado = 'fixada' and a.fixado_por = 'cliente_confirmou'
                order by a.dia, a.turno = 'tarde', a.payee_id, a.id loop
      perform set_config('agenda.mexe_fixado', 'on', true);
      update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_x.id;
      perform set_config('agenda.mexe_fixado', 'off', true);
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                           fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
      values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo, 'publicada', v_x.origem, v_x.id,
              null, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
      returning id into v_id;
      v_novas := v_novas || v_id;
      v_canc := v_canc || v_x.id;
    end loop;
    update public.service_orders
       set client_confirmed_at = (v_a.antes ->> 'client_confirmed_at')::timestamptz,
           client_confirmed_for = (v_a.antes ->> 'client_confirmed_for')::timestamptz
     where id = v_os and client_confirmed_for is not distinct from (v_a.depois ->> 'client_confirmed_for')::timestamptz;
    v_txt := format('Desfeito: a confirmação do %s (%s) sai; o dia continua no plano, sem fixar.', v_nome,
                    coalesce(public._dia_curto((v_a.depois ->> 'dia')::date), 'o dia'));
  elsif v_ef = 'replanejou' then
    perform public._agenda_cliente_restaurar_pedido(v_a.id, p_agora);
    -- o replano que o pedido causou volta (cada ação dele, pelo desfazer de sempre); o que não voltar é replanejado
    perform set_config('agenda.desfazer_cliente', 'on', true);
    for v_id in select x::uuid from jsonb_array_elements_text(coalesce(v_a.depois -> 'replano_acoes', '[]'::jsonb)) x loop
      if exists (select 1 from public.agenda_acoes e where e.id = v_id and e.executada and e.desfeita_em is null) then
        v_r := public.agenda_desfazer(v_id, p_autor, p_via, p_hoje, p_agora);
        if coalesce((v_r ->> 'ok')::boolean, false) then
          v_n := v_n + 1;
        else
          v_falha := true;
        end if;
      end if;
    end loop;
    perform set_config('agenda.desfazer_cliente', '', true);
    if v_falha or v_n = 0 then
      perform public.agenda_replanejar(array[v_os], 'desfeito o pedido do cliente', 'vigia', p_hoje, p_agora, p_autor);
    end if;
    v_novo := (public._agenda_plano_da_os(v_os, p_hoje) ->> 'proximo_dia')::date;
    v_txt := format('Desfeito: o pedido do %s sai; %s.', v_nome,
                    case when v_novo is not null then 'o serviço fica para ' || public._dia_curto(v_novo)
                         else 'o serviço fica sem dia no plano por enquanto' end);
  else
    select so.site_access into v_sa from public.service_orders so where so.id = v_os for update;
    if v_sa is distinct from (v_a.depois ->> 'site_access') then
      return jsonb_build_object('ok', false, 'texto', 'O acesso da OS mudou depois; confira na tela.');
    end if;
    update public.service_orders set site_access = v_a.antes ->> 'site_access' where id = v_os;
    update public.os_planejamento set acesso_ok_em = (v_a.antes ->> 'acesso_ok_em')::timestamptz, atualizado_em = p_agora
     where service_order_id = v_os and acesso_ok_em is not distinct from (v_a.depois ->> 'acesso_ok_em')::timestamptz;
    v_txt := format('Desfeito: o acesso que o %s disse saiu da OS.', v_nome);
  end if;
  -- FASE 6: (P7) o "Desfeito: …" sem artigo antes do nome (spec-fase6 §6.4): "Desfeito: a confirmação de Flávio …",
  -- "Desfeito: o pedido de Flávio sai; …", "Desfeito: o acesso que Nelson disse saiu da OS." (pelo ralo do texto ao dono)
  v_txt := public._agenda_cliente_sem_artigo(v_txt, v_os);
  -- FASE 6: fim

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, versao_depois,
                                   alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas), 'efeito', v_ef),
          public._agenda_corta(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;
  return jsonb_build_object('ok', true, 'texto', public._agenda_corta(v_txt, 400), 'acao_id', v_acao,
                            'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public._agenda_desfazer_cliente(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o *desfaz* do que a resposta do cliente mudou (ação com depois.resposta_id; agenda_desfazer a chama, com o plano travado). confirmou: as alocações que ela fixou (ainda fixadas por cliente_confirmou e sem começar) voltam a publicada — cancela-se a fixada (agenda.mexe_fixado) e cria-se a publicada igual (substitui_id) — e client_confirmed_* volta ao antes se ainda é o dela. replanejou: o planejamento volta (_agenda_cliente_restaurar_pedido), as ações do replano são desfeitas (agenda_desfazer, com agenda.desfazer_cliente ligado para o bloco do fim não repetir) e, se alguma não voltar, a OS é replanejada. anotou_acesso: site_access e acesso_ok_em voltam, só se o campo ainda é o que ela escreveu ("O acesso da OS mudou depois; confira na tela."). opt_out e o que não mudou nada: recusa. A ação desfazer (desfaz_a) e desfeita_* na original. Interna (sem grant). FASE 6 (P7, spec-fase6 §6.4): sem artigo antes do nome e sem "ele" ("Desfeito: a confirmação de Flávio (ter 03/11) sai; …", "Desfeito: o acesso que Nelson disse saiu da OS.", "… só o cliente pode pedir para voltar.").';

-- _agenda_ver_clientes (de 20261028100500_agenda_fase5_leituras.sql)
create or replace function public._agenda_ver_clientes(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid    uuid := (select auth.uid());
  cf       public.agenda_config;
  v_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_amanha date;
  v_l      text[] := '{}';
  v_c      text[] := '{}';
  v_ef     text[] := '{}';
  v_es     text[] := '{}';
  v_t      text[];
  k        int;
  v_b      text[];
  r        record;
  x        jsonb;
  v_cab    text;
  v_n      jsonb := '{}'::jsonb;
  v_tipos  text[];
  v_prom   text;
  v_conf   timestamptz;
  c_tipos  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                    'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia'];
begin
  if p_hoje is null then
    raise exception '_agenda_ver_clientes: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('ok', true, 'texto', 'As mensagens ao cliente estão desligadas: a agenda não fala com cliente.',
                              'dados', jsonb_build_object('modo', cf.modo_cliente));
  end if;
  v_amanha := public._agenda_cliente_dia_seguinte(p_hoje);

  -- o cabeçalho (e, com a OS, o que foi dito e a confirmação)
  if p_os is not null then
    select so.service_order_number as numero, so.client_confirmed_for,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome,
           pl.prometido_tipo, pl.prometido_de, pl.prometido_ate, pl.prometido_fonte, pl.prometido_em
      into r
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.id = p_os;
    v_cab := format('Mensagens ao cliente — %s (%s)%s:', coalesce(r.nome, 'cliente'), r.numero,
                    case when cf.modo_cliente = 'sombra' then ', em teste' else '' end);
    v_prom := case
      when r.prometido_ate is null then 'O que foi dito a ele: nada ainda.'
      else format('O que foi dito a ele: %s (%s, %s%s).',
                  case when coalesce(r.prometido_de, r.prometido_ate) = r.prometido_ate then public._dia_curto(r.prometido_ate)
                       else format('de %s a %s', public._dia_curto(r.prometido_de), public._dia_curto(r.prometido_ate)) end,
                  case r.prometido_tipo when 'firme' then 'data firme' when 'faixa' then 'uma faixa' else 'condicional' end,
                  case r.prometido_fonte when 'mensagem' then 'por mensagem da agenda' when 'dono' then 'por você'
                                         else 'pela confirmação' end,
                  coalesce(' em ' || public._dia_curto((r.prometido_em at time zone 'America/Sao_Paulo')::date), '')) end;
    -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4): "O que foi dito ao cliente: …" (pelo ralo do texto ao dono)
    v_prom := public._agenda_cliente_sem_artigo(v_prom, p_os);
    -- FASE 6: fim
    v_l := array[v_cab, v_prom];
    if r.client_confirmed_for is not null then
      v_l := v_l || format('Ele confirmou %s.', public._dia_curto((r.client_confirmed_for at time zone 'America/Sao_Paulo')::date));
      -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4)
      v_l[cardinality(v_l)] := format('O cliente confirmou %s.',
                                      public._dia_curto((r.client_confirmed_for at time zone 'America/Sao_Paulo')::date));
      -- FASE 6: fim
    end if;
  else
    v_l := array[case when cf.modo_cliente = 'sombra' then 'Mensagens ao cliente (em teste: nada sai ainda):'
                      else 'Mensagens ao cliente:' end];
  end if;

  -- (1) Esperando você: a mensagem que espera *manda cliente* (inteira), o aviso de atraso que é decisão, a data dita que
  -- passou sem aviso e a resposta que foi ao dono
  -- (o "não respondeu" fica no bloco Sem resposta). A mensagem vai inteira; se o texto passar de texto_max, as da 2ª em
  -- diante encurtam (v_es) antes de qualquer linha sair.
  for r in
    select m.tipo, m.texto, m.enviar_em, m.aprovacao, q.texto as pergunta,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m
      join public.clients cl on cl.id = m.client_id
      left join public.agenda_perguntas q on q.id = m.pergunta_id
     where m.modo = 'ligado' and m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    if r.aprovacao = 'critica' then
      v_ef := v_ef || format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso do ' || r.nome || ' espera você (1, 2 ou 3).'));
      v_es := v_es || format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso do ' || r.nome || ' espera você (1, 2 ou 3).'));
      -- FASE 6: (P7) sem artigo antes do nome (o texto de quando a pergunta já não existe)
      v_ef[cardinality(v_ef)] := format('• Decisão: %s', coalesce(r.pergunta, 'o aviso de atraso de ' || r.nome || ' espera você (1, 2 ou 3).'));
      v_es[cardinality(v_es)] := v_ef[cardinality(v_ef)];
      -- FASE 6: fim
    else
      v_ef := v_ef || format('• %s (%s), sai %s: "%s" — *manda cliente %s* ou *segura cliente %s*', r.nome,
                             public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                             r.texto, r.nome, r.nome);
      v_es := v_es || format('• %s (%s), sai %s: "%s" — *manda cliente %s*', r.nome,
                             public._agenda_cliente_tipo_texto(r.tipo), public._agenda_cliente_quando_texto(r.enviar_em, v_agora),
                             public._agenda_corta(regexp_replace(r.texto, 'Aqui é [^.]*\.\s*', ''), 70), r.nome);
    end if;
  end loop;
  for r in
    select q.tipo, q.texto from public.agenda_perguntas q
     where q.modo = 'ligado' and q.estado = 'aberta' and (q.expira_em is null or q.expira_em > v_agora)
       and (p_os is null or q.service_order_id = p_os)
       and ((q.tipo = 'cliente_resposta' and q.chave not like 'cliente_resposta:sem_resposta:%')
            or (q.tipo = 'cliente_aviso' and not exists (select 1 from public.agenda_cliente_mensagens m where m.pergunta_id = q.id)))
     order by q.perda_em nulls last, q.criada_em, q.id
  loop
    v_ef := v_ef || case when r.tipo = 'cliente_aviso' then '• Decisão: ' || r.texto else '• ' || r.texto end;
    v_es := v_es || case when r.tipo = 'cliente_aviso' then '• Decisão: ' || r.texto else '• ' || r.texto end;
  end loop;
  v_n := v_n || jsonb_build_object('esperando', cardinality(v_ef));

  -- (2) Vou mandar (hoje e amanhã): as livres e as aprovadas que saem até o próximo dia de janela
  v_b := '{}';
  for r in
    select m.tipo, m.estado, m.enviar_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado in ('registrada', 'enfileirada', 'aguardando_dono') and m.aprovacao in ('livre', 'aprovada')
       and (m.enviar_em at time zone 'America/Sao_Paulo')::date <= v_amanha
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_b := v_b || format('• %s: %s, %s%s', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         case when r.estado = 'enfileirada' then 'na fila, ' else '' end,
                         public._agenda_cliente_quando_texto(r.enviar_em, v_agora));
  end loop;
  v_n := v_n || jsonb_build_object('vou_mandar', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Vou mandar (hoje e amanhã):'::text || v_b;
  end if;

  -- (3) Mandei (7 dias)
  v_b := '{}';
  for r in
    select m.tipo, m.enviada_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.enviada_em is not null and m.enviada_em > v_agora - interval '7 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviada_em, m.id
  loop
    v_b := v_b || format('• %s: %s (%s às %s)', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         public._dia_curto((r.enviada_em at time zone 'America/Sao_Paulo')::date),
                         to_char(r.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI'));
  end loop;
  v_n := v_n || jsonb_build_object('mandei', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Mandei (7 dias):'::text || v_b;
  end if;

  -- (3b) Em teste: o que a agenda teria mandado (a sombra dos últimos 7 dias e a que sairia)
  v_b := '{}';
  for r in
    select m.tipo, m.enviar_em, m.estado, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.modo = 'sombra' and m.criada_em > v_agora - interval '7 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviar_em, cl.name, m.tipo, m.id
  loop
    v_b := v_b || format('• %s: %s (%s)', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         case when r.estado = 'recusada' then 'não sairia'
                              when r.enviar_em <= v_agora
                                then format('teria saído %s às %s', public._dia_curto((r.enviar_em at time zone 'America/Sao_Paulo')::date),
                                            to_char(r.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'))
                              else 'sairia ' || public._agenda_cliente_quando_texto(r.enviar_em, v_agora) end);
  end loop;
  v_n := v_n || jsonb_build_object('em_teste', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || case when cf.modo_cliente = 'sombra' then 'Em teste, eu teria mandado:'
                       else 'Em teste, eu teria mandado:' end || v_b;
  elsif cf.modo_cliente = 'sombra' then
    v_c := v_c || 'Em teste: nada que eu teria mandado nos últimos 7 dias.'::text;
  end if;

  -- (4) Responderam (7 dias): com o efeito; em teste, o que eu teria feito
  v_b := '{}';
  for r in
    select a.tipo_msg, a.texto, a.efeito, a.intencao, a.modo, m.tipo, m.variante,
           coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_respostas a
      join public.clients cl on cl.id = a.client_id
      left join public.agenda_cliente_mensagens m on m.id = a.mensagem_id
     where a.recebida_em > v_agora - interval '7 days' and a.recebida_em <= v_agora
       and (p_os is null or a.service_order_id = p_os)
     order by a.recebida_em, a.id
  loop
    v_b := v_b || format('• %s%s respondeu %s%s: %s', case when r.modo = 'sombra' then 'Em teste: o ' else '' end, r.nome,
                         case when r.tipo_msg = 'audio' then 'por áudio'
                              when r.tipo_msg <> 'text' then 'com ' || case r.tipo_msg when 'image' then 'uma foto'
                                                                                         when 'document' then 'um documento'
                                                                                         when 'video' then 'um vídeo'
                                                                                         else 'uma mensagem' end
                              else '"' || public._agenda_corta(coalesce(r.texto, ''), 60) || '"' end,
                         case when r.tipo is not null then ' ' || public._agenda_cliente_a_mensagem(r.tipo, r.variante, r.dia) else '' end,
                         case when r.efeito = 'sombra' then public._agenda_cliente_teria_feito(r.intencao, r.dia)
                              else public._agenda_cliente_efeito_texto(r.efeito) end);
    -- FASE 6: (P7) sem artigo antes do nome: "• Em teste: Nelson respondeu …"
    v_b[cardinality(v_b)] := replace(v_b[cardinality(v_b)], '• Em teste: o ' || r.nome || ' respondeu ',
                                     '• Em teste: ' || r.nome || ' respondeu ');
    -- FASE 6: fim
  end loop;
  v_n := v_n || jsonb_build_object('responderam', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Responderam (7 dias):'::text || v_b;
  end if;

  -- (5) Sem resposta (o M1/M3/M7/M10 que o cliente não respondeu, dos últimos 14 dias)
  v_b := '{}';
  for r in
    select m.tipo, m.enviada_em, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) as dia,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) as nome
      from public.agenda_cliente_mensagens m join public.clients cl on cl.id = m.client_id
     where m.estado = 'sem_resposta' and m.enviada_em > v_agora - interval '14 days'
       and (p_os is null or m.service_order_id = p_os)
     order by m.enviada_em, m.id
  loop
    v_b := v_b || format('• %s: %s, mandada %s', r.nome, public._agenda_cliente_o_que(r.tipo, r.dia),
                         public._dia_curto((r.enviada_em at time zone 'America/Sao_Paulo')::date));
  end loop;
  v_n := v_n || jsonb_build_object('sem_resposta', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || 'Sem resposta:'::text || v_b;
  end if;

  -- (6) Não consigo mandar: os clientes da carteira (e das OS concluídas nos últimos 30 dias) sem telefone, com opt-out ou
  -- sem conversa no último ano (d10: por ora só mando a quem já escreveu — suposição, a confirmar com você); e, em ligado, os
  -- tipos ainda em teste
  v_b := '{}';
  for r in
    select c.id,
           public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(c.display_name, '')), ''), c.name)) as nome,
           public._agenda_cliente_telefone(c.id) is null as sem_tel,
           public._agenda_cliente_sem_mensagem(c.id) as opt_out,
           not public._agenda_cliente_conversou(c.id, v_agora) as sem_conversa
      from public.clients c
     where c.id in (select so.client_id from public.service_orders so
                     where so.merged_into_id is null and (p_os is null or so.id = p_os)
                       and (so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
                            or (so.status in ('completed', 'invoiced')
                                and coalesce(so.delivered_at, so.check_out_at) > v_agora - interval '30 days')))
     order by 2, c.id
  loop
    if r.sem_tel then
      v_b := v_b || format('%s (sem telefone no cadastro)', r.nome);
    elsif r.opt_out then
      v_b := v_b || format('%s (pediu para não receber mensagens)', r.nome);
    elsif r.sem_conversa then
      v_b := v_b || format('%s (não escreveu para a HBR no último ano; por ora só mando a quem já escreveu)', r.nome);
    end if;
  end loop;
  v_n := v_n || jsonb_build_object('nao_consigo', cardinality(v_b));
  if cardinality(v_b) > 0 then
    v_c := v_c || format('Não consigo mandar: %s.', public._agenda_lista(v_b, null));
  end if;
  if cf.modo_cliente = 'ligado' then
    v_tipos := array(select public._agenda_cliente_tipo_texto(t) from unnest(c_tipos) with ordinality u(t, o)
                      where t <> all (cf.cliente_tipos_ligados) order by o);
    if cardinality(v_tipos) > 0 then
      v_c := v_c || format('Ainda em teste (não saem): %s.', public._agenda_lista(v_tipos, null));
    end if;
  end if;

  -- nada a contar (em ligado): a frase logo depois do cabeçalho, antes do que não consigo mandar
  if (select coalesce(sum(e.value::int), 0) from jsonb_each_text(v_n - 'em_teste' - 'nao_consigo') e) = 0
     and cf.modo_cliente = 'ligado' then
    v_l := v_l || 'Nada esperando você, nada a mandar e nenhuma resposta nos últimos 7 dias.'::text;
  end if;
  -- as que esperam você: a 1ª sempre inteira; as outras encurtam, da última para a 2ª, só se o texto não couber
  k := cardinality(v_ef);
  loop
    v_t := v_l || case when cardinality(v_ef) > 0 then 'Esperando você:'::text || (v_ef[1:k] || v_es[k + 1:]) else '{}'::text[] end
           || v_c;
    exit when k <= 1 or char_length(array_to_string(v_t, E'\n')) <= cf.texto_max;
    k := k - 1;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_t, cf.texto_max),
                            'dados', v_n || jsonb_build_object('modo', cf.modo_cliente, 'os', p_os));
end;
$function$;

comment on function public._agenda_ver_clientes(uuid, date) is
  'Agenda de Produção (Fase 5, P5): agenda_ver foco clientes (*agenda clientes*) — as mensagens ao cliente em blocos: "Esperando você" (a mensagem que espera *manda cliente*/*segura cliente*, INTEIRA; o aviso de atraso que é decisão; a data dita que passou sem aviso; a resposta que foi ao dono), "Vou mandar (hoje e amanhã)", "Mandei (7 dias)", "Em teste, eu teria mandado" (a sombra), "Responderam (7 dias)" com o efeito (em teste: o que eu teria feito), "Sem resposta" e "Não consigo mandar" (sem telefone, opt-out, sem conversa no último ano, tipos ainda em teste). Com p_os, só dela, mais o que foi dito (prometido_*) e a confirmação. modo_cliente desligado = "As mensagens ao cliente estão desligadas". Até texto_max, cortado por linha. A hora de agora: agenda.agora (a bancada), senão now(). Definer (lê a fila e as respostas): com login, só administrador e financeiro (42501). {ok, texto, dados:{esperando, vou_mandar, mandei, em_teste, responderam, sem_resposta, nao_consigo, modo, os}}. FASE 6 (P7, spec-fase6 §6.4): sem artigo antes do nome e sem "ele" ("O que foi dito ao cliente: …", "O cliente confirmou …", "• Em teste: Nelson respondeu …", "o aviso de atraso de Nelson espera você …").';

-- _agenda_cliente_teria_feito (de 20261028100500_agenda_fase5_leituras.sql)
create or replace function public._agenda_cliente_teria_feito(p_intencao text, p_dia date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_intencao = 'confirma' then 'eu teria confirmado' || coalesce(' ' || public._dia_curto(p_dia), '')
    when p_intencao in ('remarcar', 'falta', 'data') then 'eu teria tirado o dia e replanejado'
    when p_intencao = 'acesso' then 'eu teria anotado o acesso na OS'
    -- FASE 6: (P7) sem "a ele" (spec-fase6 §6.4); o "when" de antes, logo abaixo, não é mais alcançado
    when p_intencao = 'opt_out' then 'eu teria parado as mensagens'
    -- FASE 6: fim
    when p_intencao = 'opt_out' then 'eu teria parado as mensagens a ele'
    else 'eu teria passado a você' end;
$function$;

comment on function public._agenda_cliente_teria_feito(text, date) is
  'Agenda de Produção (Fase 5, P5): o que a agenda teria feito com uma resposta do cliente em teste ("eu teria confirmado ter 03/11", "eu teria tirado o dia e replanejado", "eu teria passado a você"). FASE 6 (P7, spec-fase6 §6.4): "eu teria parado as mensagens" (sem "a ele").';

-- _pedir_confirmacao (de 20261028100700_agenda_fase5_correcao_resposta.sql)
create or replace function public._pedir_confirmacao(p_os uuid, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_os record;
  v_fone text;
  v_teste boolean;
  v_fone_teste text;
  v_destino text;
  v_nome text;
  v_quando text;
  v_msg text;
  -- FASE 5: o plano (D9) e a mensagem pela agenda
  v_cf public.agenda_config;
  v_hoje date;
  v_dia date;
  v_fim date;
  v_r jsonb;
  v_motivo text;
  v_quem text;
  v_dados jsonb;
  -- FASE 5: fim
  -- CORREÇÃO FASE 5: a conferência no clique (item 5a / M1), a mensagem que a agenda já tem (item 5b) e a janela do caminho
  -- antigo (item 19)
  v_cli   uuid;
  v_dia_q date;
  v_chave text;
  v_ja    public.agenda_cliente_mensagens%rowtype;
  v_sai_em timestamptz;
  v_dia_e date;
  v_seg   date;
  v_pre   text;
  v_d     jsonb;
  v_prox  date;
  -- CORREÇÃO FASE 5: fim
begin
  if v_autor is not null and not exists (
    select 1 from public.app_users u where u.id = v_autor and u.active and u.role in ('admin', 'financial', 'seller')) then
    raise exception 'Sem permissão para falar com o cliente pelo WhatsApp.' using errcode = '42501';
  end if;

  select s.id, s.service_order_number, s.status, s.scheduled_start_at,
         c.name as cliente, c.phone, c.whatsapp, c.opt_out_whatsapp, v.name as barco
    into v_os
    from public.service_orders s
    left join public.clients c on c.id = s.client_id
    left join public.vessels v on v.id = s.vessel_id
   where s.id = p_os;
  if v_os.id is null then raise exception 'OS não encontrada.'; end if;
  -- FASE 5: D9 — com o plano ligado (modo_proposta), vale o próximo dia vigente do plano, de amanhã em diante, com a OS
  -- aberta, aprovada, agendada ou em andamento (o espelho scheduled_* fica para trás numa OS em andamento); aguardando peça
  -- ou o cliente, não. Sem o plano ligado, a regra de 30/09 (agendada e no futuro).
  v_cf := public._agenda_cfg();
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  if v_cf.modo_proposta = 'ligado' then
    if v_os.status in ('awaiting_parts', 'awaiting_client') then
      raise exception 'A OS espera peça (ou o cliente): confirmar o dia agora seria prometer o que não depende de nós.';
    end if;
    v_dia := (public._agenda_plano_da_os(p_os, v_hoje) ->> 'proximo_dia')::date;
    if v_os.status not in ('open', 'approved', 'scheduled', 'in_progress') or v_dia is null or v_dia <= v_hoje then
      raise exception 'A OS % não tem dia marcado no plano de amanhã em diante.', v_os.service_order_number;
    end if;
    v_os.scheduled_start_at := (select min(lower(a.periodo)) from public.agenda_alocacoes a
                                 where a.service_order_id = p_os and a.dia = v_dia and a.estado in ('publicada', 'fixada')
                                   and a.tipo <> 'reserva');
  else
  -- FASE 5: fim
  if v_os.status <> 'scheduled' or v_os.scheduled_start_at is null then
    raise exception 'A OS % não está agendada.', v_os.service_order_number;
  end if;
  if v_os.scheduled_start_at < p_agora then
    raise exception 'O atendimento da OS % já passou.', v_os.service_order_number;
  end if;
  -- FASE 5: o fim do "senão" (a regra de 30/09)
  end if;
  -- FASE 5: fim
  if coalesce(v_os.opt_out_whatsapp, false) then
    raise exception 'Este cliente pediu para não receber WhatsApp: confirme por telefone.';
  end if;
  v_fone := regexp_replace(coalesce(nullif(v_os.whatsapp, ''), v_os.phone, ''), '\D', '', 'g');
  if length(v_fone) < 10 then raise exception 'Cliente sem telefone cadastrado.'; end if;
  if length(v_fone) in (10, 11) then v_fone := '55' || v_fone; end if;

  v_teste := coalesce((select value::text from public.app_settings where key = 'wa_test_mode'), 'false') in ('true', '"true"');
  v_fone_teste := regexp_replace(coalesce((select value::text from public.app_settings where key = 'wa_test_number'), ''), '\D', '', 'g');
  if v_teste and v_fone_teste = '' then raise exception 'Modo de teste ligado sem número de teste configurado.'; end if;
  v_destino := case when v_teste then v_fone_teste else v_fone end;
  -- FASE 5: com modo_cliente ligado e a confirmação ligada (cliente_tipos_ligados), a mensagem é a da agenda — o M1 pelo
  -- botão, já aprovado (o dono clicou) — e passa pela janela, pelo feriado, pelo teto, pelo intervalo e pela revalidação:
  -- sai na hora que a janela deixa, e o pedido de confirmação conta de quando ela SAI (o gatilho do envio). Fora disso (o
  -- modo em teste, ou a confirmação ainda não ligada), como antes.
  if v_cf.modo_cliente = 'ligado' and 'confirmar' = any (v_cf.cliente_tipos_ligados) then
    v_quem := coalesce(public._agenda_nome_curto(v_os.cliente), 'o cliente');
    v_dados := '{}'::jsonb;
    if v_cf.modo_proposta <> 'ligado' then
      -- sem o plano, o dia, o turno e os dias de trabalho saem do agendamento da OS
      v_dia := (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
      v_fim := greatest(v_dia, coalesce((select (so.scheduled_end_at at time zone 'America/Sao_Paulo')::date
                                           from public.service_orders so where so.id = p_os), v_dia));
      v_dados := jsonb_build_object('dia', v_dia, 'fim', v_fim,
        'janela', case when (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::time < v_cf.tarde_inicio
                       then 'manha' else 'tarde' end,
        'n', greatest(1, (select count(*)::int from generate_series(v_dia, v_fim, interval '1 day') g
                           where public.agenda_dia_util(g::date))));
    end if;
    -- CORREÇÃO FASE 5: (item 5 / M1) antes de registrar. (b) A confirmação deste dia que a agenda já tem — a de um clique
    -- antes (a chave <dia>:botao) ou a da rodada — não responde "já está com a agenda": já mandada, diz quando; na fila ou
    -- indo sair sozinha, diz quando sai; esperando o dono (pedida), o clique a APROVA; recusada, o clique registra uma 2ª pelo
    -- botão (a chave <dia>:botao), se o motivo já não vale; a 2ª pelo botão também recusada diz o porquê. (a) O que não
    -- depende da hora — o opt-out, a conversa (d10), o telefone e o teto do dia em que a mensagem sairia — vira o erro do
    -- clique com os mesmos textos da recusa abaixo, dentro ou fora do horário de mensagens (fora dele, a mensagem sairia na
    -- manhã seguinte e o enfileirar a recusaria calado).
    select so.client_id into v_cli from public.service_orders so where so.id = p_os;
    v_dia_q := (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    v_chave := format('agenda-cliente:confirmar:%s:%s', p_os, v_dia_q);
    select m.* into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave || ':botao';
    if v_ja.id is null then
      select m.* into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave;
    end if;
    if v_ja.id is not null and v_ja.estado in ('enviada', 'respondida', 'sem_resposta') then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'nada_feito', true,
        'message', format('Já mandei a confirmação de %s para %s (%s às %s).', public._dia_curto(v_dia_q), v_quem,
                          public._dia_curto((v_ja.enviada_em at time zone 'America/Sao_Paulo')::date),
                          to_char(v_ja.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI')));
    end if;
    if v_ja.id is not null and v_ja.estado = 'enfileirada' then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'nada_feito', true,
        'message', format('A confirmação de %s para %s já está na fila: sai agora.', public._dia_curto(v_dia_q), v_quem));
    end if;
    if v_ja.id is not null and v_ja.estado in ('registrada', 'aguardando_dono') and v_ja.aprovacao in ('livre', 'aprovada') then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'nada_feito', true,
        'message', format('A confirmação de %s para %s já vai sair sozinha: sai %s.', public._dia_curto(v_dia_q), v_quem,
                          public._agenda_cliente_quando_texto(v_ja.enviar_em, p_agora)));
    end if;
    if v_ja.id is not null and v_ja.estado = 'recusada' and v_ja.dedupe_key = v_chave || ':botao' then
      raise exception '%', format('A confirmação de %s já foi pedida pelo botão e não saiu: %s. Confirme com %s por telefone.',
                                  public._dia_curto(v_dia_q), public._agenda_cliente_motivo_texto(v_ja.recusa_motivo), v_quem);
    end if;
    if v_ja.id is not null and v_ja.estado = 'recusada' then
      -- a da rodada recusada (segurada, vencida, a OS que mudou…): o clique do dono pede de novo, pelo botão
      v_dados := v_dados || jsonb_build_object('chave', v_dia_q || ':botao');
      v_chave := v_chave || ':botao';
    end if;
    v_sai_em := case when v_ja.id is not null and v_ja.estado = 'aguardando_dono' then greatest(v_ja.enviar_em, p_agora)
                     else public._agenda_cliente_quando(hashtext(v_chave), p_agora, p_agora) end;
    v_dia_e := (v_sai_em at time zone 'America/Sao_Paulo')::date;
    v_seg := date_trunc('week', v_dia_e)::date;
    v_pre := case
      when public._agenda_cliente_sem_mensagem(v_cli) then 'opt_out'
      when not public._agenda_cliente_conversou(v_cli, v_sai_em)
        then case when public._agenda_cliente_telefone(v_cli) is null then 'sem_telefone' else 'sem_conversa' end
      when public._agenda_cliente_telefone(v_cli) is null then 'sem_telefone'
      when public._agenda_cliente_no_periodo(v_cli, v_dia_e, v_dia_e, v_ja.id) >= v_cf.cliente_dia_max then 'teto_dia'
      when public._agenda_cliente_no_periodo(v_cli, v_seg, v_seg + 6, v_ja.id) >= v_cf.cliente_semana_max then 'teto_semana'
      when public._agenda_cliente_no_periodo(null, v_dia_e, v_dia_e, v_ja.id) >= v_cf.cliente_total_dia_max then 'teto_total'
    end;
    if v_pre is null and v_ja.id is not null and v_ja.estado = 'aguardando_dono' then
      if v_ja.aprovacao <> 'pedida' or v_ja.pergunta_id is null then
        raise exception '%', format('A confirmação de %s para %s espera a sua decisão na conversa (opção 1, 2 ou 3).',
                                    public._dia_curto(v_dia_q), v_quem);
      end if;
      -- esperando o dono: o clique é o *manda cliente* dela (a janela, o teto e a revalidação continuam valendo)
      v_d := public._agenda_cliente_decidir(v_ja.pergunta_id, 1::smallint, v_autor, 'tela', 'Pedir confirmação (o botão)', p_agora);
      if not coalesce((v_d ->> 'ok')::boolean, false) or v_d ->> 'estado' = 'recusada' then
        raise exception '%', coalesce(v_d ->> 'texto', 'Não deu para aprovar a confirmação agora.');
      end if;
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'aprovou', true,
                                'mensagem', v_ja.texto, 'enviar_em', v_ja.enviar_em, 'message', v_d ->> 'texto');
    end if;
    if v_pre is not null then
      v_r := jsonb_build_object('criada', true, 'estado', 'recusada', 'motivo', v_pre);
    else
    -- CORREÇÃO FASE 5: fim
    begin
      v_r := public._agenda_cliente_registrar('confirmar', null, p_os,
               (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date, v_dados, p_agora, null, 'botao', null, p_agora,
               v_autor);
    exception when sqlstate '22023' then
      raise exception 'Não deu para montar a mensagem ao cliente: %', sqlerrm;
    end;
    -- CORREÇÃO FASE 5: o fim do "senão" da conferência no clique
    end if;
    -- CORREÇÃO FASE 5: fim
    if not coalesce((v_r ->> 'criada')::boolean, false) then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_r ->> 'id',
        'message', format('A confirmação de %s com %s já está com a agenda.', public._dia_curto(
                            (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date), v_quem));
    end if;
    v_motivo := v_r ->> 'motivo';
    if v_r ->> 'estado' = 'recusada' then
      raise exception '%', case
        when v_motivo = 'sem_conversa' then format('%s não escreveu para a HBR nos últimos %s dias: mensagem automática a quem não escreve arrisca o número. Confirme por telefone.',
                                                    v_quem, v_cf.cliente_conversa_dias)
        when v_motivo in ('teto_dia', 'teto_semana') then format('%s já recebeu as mensagens que cabem (no máximo %s por dia e %s por semana): confirme por telefone.',
                                                                  v_quem, v_cf.cliente_dia_max, v_cf.cliente_semana_max)
        when v_motivo = 'teto_total' then format('A agenda já mandou as %s mensagens de hoje aos clientes: confirme por telefone.',
                                                 v_cf.cliente_total_dia_max)
        when v_motivo = 'material' then format('O material da OS %s ainda não está todo na mão: a data ainda não é firme para confirmar.',
                                               v_os.service_order_number)
        when v_motivo = 'mesmo_tipo_24h' then format('%s já recebeu uma confirmação nas últimas %s horas.', v_quem,
                                                     v_cf.cliente_mesmo_tipo_horas)
        when v_motivo = 'opt_out' then 'Este cliente pediu para não receber WhatsApp: confirme por telefone.'
        when v_motivo = 'sem_telefone' then 'Cliente sem telefone válido para a mensagem (ou o número é de alguém da HBR).'
        when v_motivo in ('status', 'data_mudou', 'desatualizada')
          then format('A OS %s mudou enquanto eu montava a mensagem: confira o plano e peça de novo.', v_os.service_order_number)
        else format('Não deu para pedir a confirmação agora (%s).', coalesce(v_motivo, v_r ->> 'estado')) end;
    end if;
    return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'mensagem', v_r ->> 'texto', 'id', v_r ->> 'id',
      'enviar_em', v_r ->> 'enviar_em',
      'message', case
        when v_motivo = 'conversa_viva'
          then format('Pedido de confirmação a %s registrado: sai %s (%s está conversando agora; espero a conversa acabar).',
                      v_quem, public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_quem)
        when (v_r ->> 'enviar_em')::timestamptz <= p_agora + interval '15 minutes'
          then case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4); o "else" de antes, logo abaixo, não é mais alcançado
                    when true then format('Pedido de confirmação na fila para %s. Quando a resposta for SIM, a OS fica confirmada.', v_quem)
                    -- FASE 6: fim
                    else format('Pedido de confirmação na fila para %s. Quando ele responder SIM, a OS fica confirmada.', v_quem) end
        else format('Pedido de confirmação a %s registrado: sai %s (fora do horário de mensagens agora).', v_quem,
                    public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)) end);
  end if;
  -- FASE 5: fim

  -- CORREÇÃO FASE 5: (item 19) o caminho antigo (a mensagem ao cliente em teste, ou a confirmação ainda fora das ondas)
  -- também só sai no horário de mensagens ao cliente — a mesma regra das três travas da agenda: fora dele, o clique dá o
  -- erro e nada vai à fila. Com modo_cliente desligado (antes da Fase 5), como em 30/09.
  if v_cf.modo_cliente <> 'desligado' and public._agenda_cliente_fora_da_janela(p_agora, p_agora) is not null then
    v_prox := (public._agenda_cliente_quando(0, p_agora, p_agora) at time zone 'America/Sao_Paulo')::date;
    raise exception '%', format('Fora do horário de mensagens ao cliente: peça %s a partir das %s.',
                                case when v_prox = v_hoje then 'hoje' when v_prox = v_hoje + 1 then 'amanhã'
                                     else public._dia_curto(v_prox) end,
                                to_char(v_cf.cliente_janela_inicio, 'HH24:MI'));
  end if;
  -- CORREÇÃO FASE 5: fim
  v_nome := coalesce(nullif(split_part(btrim(coalesce(v_os.cliente, '')), ' ', 1), ''), '');
  v_quando := (array['domingo','segunda','terça','quarta','quinta','sexta','sábado'])[extract(dow from v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::int + 1]
    || ' (' || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM') || ') às '
    || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'HH24"h"MI');
  v_msg := 'Olá' || case when v_nome <> '' then ', ' || initcap(v_nome) else '' end || '! Aqui é da HBR Marine. '
    || 'Confirmando o atendimento' || coalesce(' no ' || nullif(v_os.barco, ''), '') || ' ' || v_quando || '. '
    || 'Pode responder SIM para confirmar? Se precisar remarcar, é só avisar por aqui. 👍';

  insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority)
  values (v_destino, v_msg, 'agenda-confirmacao', v_os.id, 3);

  update public.service_orders
     set client_confirmation_requested_at = p_agora, client_confirmed_at = null, client_confirmed_for = null
   where id = v_os.id;

  return jsonb_build_object('ok', true, 'teste', v_teste, 'mensagem', v_msg,
    'message', case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    -- FASE 6: (P7) sem "ele" (spec-fase6 §6.4); o "else" de antes, logo abaixo, não é mais alcançado
                    when true then 'Pedido de confirmação enviado a ' || coalesce(v_os.cliente, 'o cliente') || '. Quando a resposta for SIM, a OS fica confirmada.'
                    -- FASE 6: fim
                    else 'Pedido de confirmação enviado a ' || coalesce(v_os.cliente, 'o cliente') || '. Quando ele responder SIM, a OS fica confirmada.' end);
end;
$$;

comment on function public._pedir_confirmacao(uuid, uuid, timestamptz) is
  'O botão "Pedir confirmação" (Fase 5, correção C1): o corpo de pedir_confirmacao_do_agendamento (20261028100200) com a hora em p_agora (a casca passa now(); o teste, a hora fixa). Pela agenda (modo_cliente ligado e confirmar nas ondas): a confirmação do mesmo dia que a agenda já tem não fica "já está com a agenda" — mandada ("Já mandei a confirmação de qua 04/11 para Flávio (sex 30/10 às 10:00)."), na fila ou indo sair sozinha (diz quando), esperando o dono (o clique a aprova pelo _agenda_cliente_decidir), recusada (uma 2ª pelo botão, chave <dia>:botao; a 2ª recusada diz o porquê); no clique, o opt-out, a conversa (d10), o telefone e o teto do dia do envio viram o erro com o texto da recusa, dentro ou fora do horário. O caminho antigo, com modo_cliente fora de desligado, recusa fora do horário de mensagens ao cliente ("Fora do horário de mensagens ao cliente: peça amanhã a partir das 08:00."). Interna (sem grant): só a casca a chama. FASE 6 (P7, spec-fase6 §6.4): "Quando a resposta for SIM, a OS fica confirmada." (sem "ele"), pela agenda e pelo caminho antigo.';

-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- Nenhuma função nova. As recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a
-- migration valer sozinha), cada uma como na migration de onde foi copiada.
-- As internas (ninguém de fora, nem o service_role): o ralo do texto ao dono, o cartão, os efeitos da resposta, o *desfaz*
-- do cliente e o corpo do botão.
revoke all on function
  public._agenda_cliente_sem_artigo(text, uuid),
  public._agenda_cliente_da_os(uuid, date),
  public._agenda_cliente_confirmar_dia(uuid, uuid, text, date, timestamptz),
  public._agenda_cliente_pedido_de_dia(uuid, uuid, daterange, date, text, text, date, timestamptz),
  public._agenda_cliente_anotar_acesso(uuid, uuid, text, date, timestamptz),
  public._agenda_desfazer_cliente(uuid, uuid, text, date, timestamptz),
  public._pedir_confirmacao(uuid, uuid, timestamptz)
  from public, anon, authenticated, service_role;
-- As leituras e os textos (authenticated e service_role; nunca anon).
revoke all on function
  public._agenda_cliente_texto(text, text, uuid, jsonb, date),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
  public._agenda_ver_clientes(uuid, date),
  public._agenda_cliente_teria_feito(text, date)
  from public, anon;
grant execute on function
  public._agenda_cliente_texto(text, text, uuid, jsonb, date),
  public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz),
  public._agenda_ver_clientes(uuid, date),
  public._agenda_cliente_teria_feito(text, date)
  to authenticated, service_role;
-- A resposta do cliente: só o webhook (service_role).
revoke all on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) to service_role;
