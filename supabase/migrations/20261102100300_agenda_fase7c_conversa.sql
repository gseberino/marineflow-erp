-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê"), pacote P4: a conversa. O dono diz numa frase o que cada pessoa
-- faz ("o Roberto instala sozinho", "o João é ajudante", "o Roberto não sobe no teto"), o que uma OS pede ("o Lenine não precisa de
-- ninguém subindo no teto"), quem é o responsável dela ("no Lenine o responsável é o Roberto") ou que está certo o que a agenda
-- marcou; a ferramenta equipe_habilidade deixa a RELEITURA no rascunho, e só o *grava* do dono grava.
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§0 item 7, §3.1-1, §3.2, §3.6, §5.4, §6.3, §7, §8.3 agenda_fase7c_conversa.sql,
-- §9 P4; R5.1-1, R5.4, R5.5 item 4); nomes: fase7-registro.md §1 (agenda_rascunho_habilidade, _agenda_habilidade_frase,
-- _agenda_aplicar_habilidade) e §2 (agenda_rascunho_gravar e _agenda_rascunho_frase: 7b P2 20261101100100 → 7c P4 → 7c P8);
-- respostas do dono: fase7-padroes.md (AG7-10 "o gestor propõe pelo histórico; sem etiqueta = padrão"; AG7-03 "ajudante = nunca
-- sozinho em tarefa de risco"; AG7-15 "sem resposta fica como proposto").
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a e da 7b inteiras e da 7c P1 a P3 (20261102100000: agenda_etiquetas e os 3
-- gatilhos, as colunas exigencias_ditas/lider_* de os_planejamento, habilidade_palavras, os textos _agenda_etiqueta_texto e
-- _agenda_exigencia_texto e a lista agenda_rascunho.tipo com habilidade).
--
-- ═══ DDL — OK NOMEADO ═══ (3 funções novas e 2 recriadas com as mesmas assinaturas; nenhuma tabela, coluna, lista, gatilho, job ou dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7c/p4/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o
-- montador para se outra migration anterior a esta a definir depois da origem) — _agenda_rascunho_frase e agenda_rascunho_gravar de
-- 20261101100100_agenda_fase7b_disponibilidade.sql (a 7b P2; = o R5.4 da spec) —, e as mudanças estão só em blocos
-- "-- FASE 7c: … -- FASE 7c: fim" INSERIDOS (só acréscimo: nenhuma linha de antes é trocada). Tirados os blocos, o corpo é o da
-- origem, byte a byte (o montador e o C6 de supabase/tests/agenda_fase7c_conversa.sql conferem).
--
-- POR QUE: a 7c escala pelo que cada um sabe fazer (P1 a P3), e o que cada um faz, sem etiqueta, é o padrão (pode tudo, menos
-- comissionar). O dono é quem sabe: o Alex instala sozinho, o Mateus é ajudante, o Lenine não pede ninguém no teto, o responsável do
-- Lenine é o Roberto. Sem a conversa, o que ele diz não tem para onde ir, e a proposta do gestor pelo histórico (P5) não tem como
-- ser corrigida nem confirmada (§0 item 7: "o dono corrige numa frase").
--
-- O QUE MUDA:
--   1. agenda_rascunho_habilidade (a RPC da ferramenta equipe_habilidade): uma de 4 formas por chamada — (a) a pessoa e o que ela faz
--      (os 14 o_que_faz da §3.2 → a etiqueta e o nível); (b) a OS, a exigência (energizado, comissionamento, altura, diagnostico) e
--      os meios (todos, ultimo, nao); (c) a OS e o responsável (a pessoa, ou "ninguém"); (d) "está certo" (confirmar). A pessoa pelo
--      agenda_resolver_pessoa (o Alex é achado, R5.1-1), a OS pelo agenda_resolver_os (a carteira); ambíguo, não achado ou fora da
--      carteira = a pergunta, nada no rascunho. A guarda do trecho: o que a pessoa faz e o que a OS pede têm de estar nas palavras do
--      dono (habilidade_palavras, casada no início de palavra, a régua do P1); o nome do responsável também. Chaves hab:<pessoa>:<…>,
--      exige:<os>:<exigência>, lider:<os> e hab:confirmar (a correção substitui). Devolve {ok, item, itens, releitura}.
--   2. _agenda_habilidade_frase: a releitura de cada forma, dos dados (§6.3) — "Roberto instala sozinho"; "pede quem sobe no teto em
--      todos os dias"; "o responsável é Roberto (fica em todos os dias)"; "fica como eu marquei (Roberto instala sozinho; João é
--      ajudante)". A recriada _agenda_rascunho_frase a chama no tipo habilidade.
--   3. _agenda_aplicar_habilidade (o *grava* da linha): (a) a etiqueta do dono, que já vale (origem dono, "você disse", o trecho; o
--      gatilho de exclusividade do P1 substitui a viva da mesma etiqueta e a de instala × ajudante); (b) os_planejamento.exigencias_ditas
--      (|| {exigência: meios}) e exigencias_trecho; (c) lider_payee_id, lider_em e lider_trecho ("ninguém" põe os três nulos) — (b) e
--      (c) com o histórico {em, autor, trecho, antes, depois} do planejar; (d) as propostas da pergunta habilidade:equipe valem e a
--      pergunta fecha ("você confirmou"). Em (a), (b) e (c), com a pergunta habilidade:equipe aberta e já mostrada ao dono: as
--      propostas que o lote corrigiu viram substituídas, as outras valem, a pergunta fecha ("você corrigiu; o resto ficou como eu
--      marquei") e a frase do "Gravado. Agora:" ganha " O resto ficou como eu marquei: …".
--   4. agenda_rascunho_gravar (recriada): o tipo habilidade aplica pela função acima, em qualquer modo da agenda (como o fornecedor), e a
--      frase entra no "Gravado. Agora:" junto dos pedidos.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7c_conversa.sql; registradas em notas-fase77c.md, P4):
--   · a porta da RPC: authenticated e service_role (a spec dizia só service_role). A ferramenta chama com o cliente do canal — no
--     painel, o login do dono (authenticated); no WhatsApp, o service_role —, como as outras 6 RPCs de rascunho da agenda; quem confere
--     o cargo é o _autor_da_agenda (só o administrador). Só service_role quebraria a ferramenta no painel com 42501;
--   · a releitura de (b), (c) e (d) não repete o nome: a linha da releitura já começa pelo rótulo ("• Lenine (OS-00074): pede quem
--     sobe no teto em todos os dias."; "• Quem faz o quê: fica como eu marquei (…)."), como o "Gravado. Agora:" da §6.3 ("Lenine: pede
--     quem sobe no teto em todos os dias."), e o texto ao dono não leva artigo antes do nome (a régua da Fase 6); a spec escrevia "o
--     Lenine pede …" e "quem faz o quê fica como eu marquei (…)", que sairiam "Lenine (OS-00074): o Lenine pede …";
--   · a chave de instala e de ajudante é a mesma (hab:<pessoa>:instala): as duas se excluem, e "o João é ajudante… não, ele instala
--     sozinho" na mesma conversa troca a linha da releitura em vez de deixar as duas;
--   · do dono só se anota comissiona e altura (ele conta sempre como quem instala sozinho: §3.2, o dono é sempre responsável), e ele
--     não é o responsável fixo de uma OS (quando vai, já conta como responsável; o responsável duro do P2 pediria o dono num turno de
--     técnico, que ele nunca ocupa): os dois viram uma frase ao dono, nada no rascunho;
--   · a guarda de "quase instala" aceita também as palavras de instala ("o João quase instala sozinho" não diz "ajudante"), e a de
--     "ninguém" (o serviço sem responsável fixo) pede ninguém, nenhum, "sem responsável", "não tem responsável", "tira o responsável" ou
--     "qualquer um" no trecho;
--   · o confirmar pede, além da pergunta aberta e mostrada, ao menos uma proposta viva dela; no *grava*, a pergunta que já fechou neste
--     lote (ou pelo prazo) não muda nada, e a que foi refeita (descartada) recusa o lote ("A agenda mudou desde a releitura");
--   · as corrigidas são as do LOTE inteiro (as linhas de pessoa do mesmo *grava*): a pergunta fecha na 1ª linha que grava, e o "O resto
--     ficou como eu marquei" não cita quem outra linha do mesmo lote corrigiu. Sem nada sobrando, só "você corrigiu".
--
-- O QUE NÃO MUDA: os tipos de antes do rascunho (planejar, material, disponibilidade, fornecedor, aviso, os pedidos) e o *grava* deles,
-- byte a byte. Nenhuma mensagem à equipe nem ao cliente. A conversa grava em qualquer modo da 7c: as etiquetas, o que a OS pede e o
-- responsável só mudam a escala com modo_habilidade/modo_lider ligados (P2, P3); fora disso, são dado do dono guardado.
--
-- ORDEM DE LIGAR: nada a ligar aqui (os modos são do P1; a migration de dado 20261102100600 os põe em sombra). A ferramenta só existe
-- para o modelo com o deploy do ai-agent e do erp-mcp da 7c. PROVA: supabase/tests/agenda_fase7c_conversa.sql na bancada (node
-- scripts/bancada-agenda/rodar.mjs). APLICAR: só pelo roteiro de publicação da 7c, depois da 20261102100200 e antes da 20261102100400.
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.
--
-- DESFAZER: recriar _agenda_rascunho_frase e agenda_rascunho_gravar com o corpo de 20261101100100 (as portas não mudam) e drop das 3
-- novas (agenda_rascunho_habilidade, _agenda_aplicar_habilidade, _agenda_habilidade_frase). O rascunho aberto de tipo habilidade fica
-- sem frase: descartá-lo antes (*descarta*). Quem recriar depois uma das 2 copia DESTA migration (o 7c P8, R5.4).

-- ── 1. A releitura (spec §6.3) ─────────────────────────────────────────────────────────────────────────────────────

-- A frase de uma linha de rascunho habilidade, montada dos dados já resolvidos. (a) "Roberto instala sozinho", "você não sobe no
-- teto"; (b) "pede quem sobe no teto em todos os dias", "não pede quem sobe no teto"; (c) "o responsável é Roberto (fica em todos os
-- dias)", "fica sem responsável fixo"; (d) "fica como eu marquei (Roberto instala sozinho; João é ajudante)". A linha da releitura
-- começa pelo rótulo ("Quem faz o quê" ou a OS): a frase não repete o nome da OS.
create or replace function public._agenda_habilidade_frase(p_d jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_d ->> 'forma'
    when 'pessoa' then
      case when coalesce((p_d ->> 'eh_dono')::boolean, false) then 'você' else p_d ->> 'nome' end
      || ' ' || public._agenda_etiqueta_texto(p_d ->> 'etiqueta', (p_d ->> 'nivel')::smallint)
    when 'exige' then
      case when p_d ->> 'meios' = 'nao'
           then 'não pede ' || public._agenda_exigencia_texto((p_d ->> 'mascara')::integer, null)
           else 'pede ' || public._agenda_exigencia_texto((p_d ->> 'mascara')::integer, p_d ->> 'meios') end
    when 'lider' then
      case when p_d ->> 'lider_payee_id' is null then 'fica sem responsável fixo'
           else format('o responsável é %s (fica em todos os dias)', p_d ->> 'lider_nome') end
    when 'confirmar' then
      'fica como eu marquei'
      || coalesce(' (' || nullif(array_to_string(array(
                     select x from jsonb_array_elements_text(coalesce(p_d -> 'propostas', '[]'::jsonb)) with ordinality t(x, o)
                      order by o), '; '), '') || ')', '')
  end;
$function$;

comment on function public._agenda_habilidade_frase(jsonb) is
  'Agenda de Produção (Fase 7c, P4; spec §6.3): a releitura de uma linha de rascunho habilidade, dos dados — (a) pessoa: "Roberto instala sozinho", "João é ajudante: não vai sozinho em serviço de risco", "Roberto não sobe no teto" (o dono: "você …"); (b) exige: "pede quem sobe no teto em todos os dias", "não pede quem sobe no teto"; (c) lider: "o responsável é Roberto (fica em todos os dias)", "fica sem responsável fixo"; (d) confirmar: "fica como eu marquei (Roberto instala sozinho; João é ajudante)". A linha da releitura começa pelo rótulo ("Quem faz o quê" ou "Lenine (OS-00074)"), e a frase não repete o nome. IMMUTABLE; só service_role (como _agenda_rascunho_frase, que a chama).';

-- ── 2. A ferramenta equipe_habilidade: o que o dono disse vira rascunho (spec §5.4) ───────────────────────────────

create or replace function public.agenda_rascunho_habilidade(p_autor uuid, p_canal text, p_pessoa text default null,
                                                             p_o_que_faz text default null, p_os text default null,
                                                             p_exige text default null, p_meios text default null,
                                                             p_lider text default null, p_confirmar boolean default false,
                                                             p_trecho text default null,
                                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  c         public.agenda_config := public._agenda_cfg();
  v_pessoa  text := nullif(btrim(coalesce(p_pessoa, '')), '');
  v_faz     text := nullif(lower(btrim(coalesce(p_o_que_faz, ''))), '');
  v_os_ref  text := nullif(btrim(coalesce(p_os, '')), '');
  v_exige   text := nullif(lower(btrim(coalesce(p_exige, ''))), '');
  v_meios   text := nullif(lower(btrim(coalesce(p_meios, ''))), '');
  v_lider   text := nullif(btrim(coalesce(p_lider, '')), '');
  v_conf    boolean := coalesce(p_confirmar, false);
  v_tr      text := public._agenda_normal(p_trecho);
  v_etq     text;
  v_niv     smallint;
  v_bit     integer;
  v_pal     text;
  v_rp      jsonb;
  v_ro      jsonb;
  v_os      uuid;
  v_nome    text;
  v_dono    boolean := false;
  v_q       uuid;
  v_props   jsonb;
  v_chave   text;
  v_dados   jsonb;
  v_item    text;
  c_forma   constant text := 'Diga uma coisa por vez: o que a pessoa faz, o que a OS pede, quem é o responsável ou que está certo.';
  -- "o Lenine fica sem responsável fixo", "no Lenine não tem responsável", "qualquer um pode ir": o serviço sem responsável fixo
  c_ninguem constant text := '\m(ningu|nenhum|sem respons|nao tem respons|tira o respons|qualquer um)';
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_habilidade: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  -- O que a pessoa faz (§3.2): o_que_faz → a etiqueta e o nível.
  if v_faz is not null then
    select x.etq, x.niv into v_etq, v_niv
      from (values ('instala_com_alguem', 'instala', 1), ('instala_sozinho', 'instala', 2), ('instala_e_ensina', 'instala', 3),
                   ('novo', 'ajudante', 1), ('ajudante', 'ajudante', 2), ('quase_instala', 'ajudante', 3),
                   ('nao_comissiona', 'comissiona', 0), ('acompanha_comissionamento', 'comissiona', 1),
                   ('diagnostica', 'comissiona', 2), ('comissiona', 'comissiona', 3),
                   ('nao_sobe_no_teto', 'altura', 0), ('sobe_acompanhado', 'altura', 1), ('sobe_no_teto', 'altura', 2),
                   ('sobe_e_orienta', 'altura', 3)) x(faz, etq, niv)
     where x.faz = v_faz;
    if not found then
      raise exception 'agenda_rascunho_habilidade: o_que_faz "%" não existe (instala_com_alguem, instala_sozinho, instala_e_ensina, novo, ajudante, quase_instala, nao_comissiona, acompanha_comissionamento, diagnostica, comissiona, nao_sobe_no_teto, sobe_acompanhado, sobe_no_teto ou sobe_e_orienta)',
        p_o_que_faz using errcode = '22023';
    end if;
  end if;
  if v_exige is not null and v_exige not in ('energizado', 'comissionamento', 'altura', 'diagnostico') then
    raise exception 'agenda_rascunho_habilidade: exige "%" não existe (energizado, comissionamento, altura ou diagnostico)', p_exige
      using errcode = '22023';
  end if;
  if v_meios is not null and v_meios not in ('todos', 'ultimo', 'nao') then
    raise exception 'agenda_rascunho_habilidade: meios "%" não existe (todos, ultimo ou nao)', p_meios using errcode = '22023';
  end if;
  -- Exatamente uma das 4 formas, inteira: (a) pessoa + o_que_faz; (b) os + exige + meios; (c) os + lider; (d) confirmar.
  if (case when v_pessoa is not null or v_faz is not null then 1 else 0 end
      + case when v_exige is not null or v_meios is not null then 1 else 0 end
      + case when v_lider is not null then 1 else 0 end
      + case when v_conf then 1 else 0 end) <> 1
     or ((v_pessoa is not null or v_faz is not null) and (v_pessoa is null or v_faz is null or v_os_ref is not null))
     or ((v_exige is not null or v_meios is not null) and (v_os_ref is null or v_exige is null or v_meios is null))
     or (v_lider is not null and v_os_ref is null)
     or (v_conf and v_os_ref is not null) then
    raise exception '%', c_forma using errcode = '22023';
  end if;
  -- A agenda desligada (agenda_config.modo_leitura) não anota: sem o *grava* ligado, o rascunho não teria saída.
  if c.modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras quem faz o quê.', 'sem_trecho');
  end if;

  if v_pessoa is not null then
    -- (a) A pessoa e o que ela faz. A guarda: o que ela faz está nas palavras do dono (habilidade_palavras da etiqueta, casada no
    -- início de palavra: "o João é bom" não diz que ele instala sozinho).
    v_rp := public.agenda_resolver_pessoa(v_pessoa, v_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
        coalesce((select jsonb_agg(e ->> 'nome' order by o)
                    from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
    end if;
    v_dono := coalesce((v_rp ->> 'eh_dono')::boolean, false);
    v_nome := v_rp ->> 'nome_curto';
    -- O dono conta sempre como quem instala sozinho (habilidade_dono; o papel dele é sempre responsável): dele, só comissiona e altura.
    if v_dono and v_etq in ('instala', 'ajudante') then
      return public._agenda_recusa('Você conta sempre como quem instala sozinho: de você eu só anoto se comissiona e se sobe no teto.',
                                   'dono_instala');
    end if;
    v_pal := c.habilidade_palavras ->> v_etq;
    if not (v_tr ~ ('\m(' || v_pal || ')')
            or (v_faz = 'quase_instala' and v_tr ~ ('\m(' || (c.habilidade_palavras ->> 'instala') || ')'))) then
      return public._agenda_recusa(format('Não achei no que você disse o que %s faz; me diga de novo.',
                                          case when v_dono then 'você' else v_nome end), 'fora_do_trecho');
    end if;
    v_dados := jsonb_build_object('forma', 'pessoa', 'grupo', 'habilidade:equipe', 'rotulo_grupo', 'Quem faz o quê',
                                  'o_que_faz', v_faz, 'payee_id', v_rp ->> 'payee_id', 'nome', v_nome, 'eh_dono', v_dono,
                                  'etiqueta', v_etq, 'nivel', v_niv);
    -- instala e ajudante se excluem: a mesma chave (a correção troca a linha da releitura)
    v_chave := format('hab:%s:%s', v_rp ->> 'payee_id', case when v_etq in ('instala', 'ajudante') then 'instala' else v_etq end);

  elsif v_exige is not null then
    -- (b) O que a OS pede: a exigência e os meios (todos, ultimo; nao tira). A guarda: a exigência está nas palavras do dono.
    v_ro := public.agenda_resolver_os(v_os_ref, p_hoje, false);
    if v_ro ->> 'status' <> 'ok' then
      return public._agenda_recusa_da_os(v_ro);
    end if;
    v_os := (v_ro ->> 'id')::uuid;
    v_bit := case v_exige when 'energizado' then 1 when 'comissionamento' then 2 when 'altura' then 4 else 8 end;
    v_pal := c.habilidade_palavras ->> case v_exige when 'comissionamento' then 'comissiona' else v_exige end;
    if not v_tr ~ ('\m(' || v_pal || ')') then
      return public._agenda_recusa(format('Não achei no que você disse o que %s pede; me diga de novo.',
                                          coalesce(nullif(v_ro ->> 'cliente_curto', ''), v_ro ->> 'numero')), 'fora_do_trecho');
    end if;
    v_dados := public._agenda_os_do_rascunho(v_ro)
               || jsonb_build_object('forma', 'exige', 'exige', v_exige, 'meios', v_meios, 'mascara', v_bit);
    v_chave := format('exige:%s:%s', v_os, v_exige);

  elsif v_lider is not null then
    -- (c) O responsável da OS (ou ninguém). A guarda: o nome dito está nas palavras do dono.
    v_ro := public.agenda_resolver_os(v_os_ref, p_hoje, false);
    if v_ro ->> 'status' <> 'ok' then
      return public._agenda_recusa_da_os(v_ro);
    end if;
    v_os := (v_ro ->> 'id')::uuid;
    if public._agenda_normal(v_lider) ~ '^(ninguem|nenhum|nenhuma|ninguem fixo|nenhum fixo|sem responsavel|nenhum responsavel)$' then
      if not v_tr ~ c_ninguem then
        return public._agenda_recusa('Não achei no que você disse que o serviço fica sem responsável fixo; me diga de novo.', 'fora_do_trecho');
      end if;
      v_dados := public._agenda_os_do_rascunho(v_ro)
                 || jsonb_build_object('forma', 'lider', 'lider_payee_id', null::uuid, 'lider_nome', null::text);
    else
      if not public._agenda_trecho_tem(p_trecho, v_lider) then
        return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo.', v_lider), 'fora_do_trecho');
      end if;
      v_rp := public.agenda_resolver_pessoa(v_lider, v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      -- O dono não é o responsável fixo: quando ele vai, já conta como responsável (o responsável duro pediria o dono num turno de
      -- técnico, que ele nunca ocupa).
      if coalesce((v_rp ->> 'eh_dono')::boolean, false) then
        return public._agenda_recusa('O responsável fixo é alguém da equipe: quando você vai, já conta como responsável. Para acompanhar o serviço o tempo todo, me diga "eu fico o tempo todo".',
                                     'dono_responsavel');
      end if;
      v_dados := public._agenda_os_do_rascunho(v_ro)
                 || jsonb_build_object('forma', 'lider', 'lider_payee_id', v_rp ->> 'payee_id', 'lider_nome', v_rp ->> 'nome_curto');
    end if;
    v_chave := 'lider:' || v_os;

  else
    -- (d) "Está certo": a pergunta habilidade:equipe aberta e já mostrada ao dono, com as propostas vivas dela.
    select q.id into v_q
      from public.agenda_perguntas q
     where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta' and q.mostrada_em is not null
     order by q.criada_em desc, q.id desc
     limit 1;
    if v_q is not null then
      select jsonb_agg(public._agenda_nome_curto(py.name) || ' '
                       || split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1)
                       order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                public._agenda_nome_curto(py.name), e.id)
        into v_props
        from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
       where e.pergunta_id = v_q and e.estado = 'proposta';
    end if;
    if v_props is null then
      return public._agenda_recusa('Não tenho nada de quem faz o quê esperando você.', 'nada_esperando');
    end if;
    v_dados := jsonb_build_object('forma', 'confirmar', 'grupo', 'habilidade:equipe', 'rotulo_grupo', 'Quem faz o quê',
                                  'pergunta_id', v_q, 'propostas', v_props);
    v_chave := 'hab:confirmar';
  end if;

  v_item := public._agenda_rascunho_salvar(v_autor, p_canal, 'habilidade', v_chave, v_os, v_dados, p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_item, 'itens', jsonb_build_array(v_item),
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_habilidade(uuid, text, text, text, text, text, text, text, boolean, text, date) is
  'Agenda de Produção (Fase 7c, P4; spec §5.4, §7): a ferramenta equipe_habilidade — o que o dono disse de quem faz o quê vira RASCUNHO (nada em agenda_etiquetas nem em os_planejamento). Uma de 4 formas por chamada (senão 22023 "Diga uma coisa por vez: …"): (a) p_pessoa + p_o_que_faz (os 14 da §3.2: instala_com_alguem, instala_sozinho, instala_e_ensina, novo, ajudante, quase_instala, nao_comissiona, acompanha_comissionamento, diagnostica, comissiona, nao_sobe_no_teto, sobe_acompanhado, sobe_no_teto, sobe_e_orienta), chave hab:<pessoa>:<etiqueta> (instala e ajudante na mesma chave: se excluem); do dono, só comissiona e altura; (b) p_os + p_exige (energizado, comissionamento, altura, diagnostico) + p_meios (todos, ultimo, nao), chave exige:<os>:<exigência>; (c) p_os + p_lider (a pessoa, ou "ninguém"), chave lider:<os>; o dono não é responsável fixo; (d) p_confirmar (a pergunta habilidade:equipe aberta, já mostrada, com proposta viva), chave hab:confirmar. A pessoa por agenda_resolver_pessoa, a OS por agenda_resolver_os (ambíguo, não achado ou fora da carteira = a pergunta). A guarda do trecho: o que a pessoa faz e o que a OS pede pelas habilidade_palavras (casadas no início de palavra; quase_instala aceita também as de instala); o nome do responsável pelo _agenda_trecho_tem; "ninguém" pelas palavras ningu/nenhum/sem responsável. Com modo_leitura desligado não anota. Devolve {ok, item, itens, releitura} ou {ok:false, pergunta, opcoes}. Quem chama: só o administrador (_autor_da_agenda); authenticated (o painel) e service_role (o WhatsApp).';

-- ── 3. O *grava* da linha (spec §5.4, §6.3) ──────────────────────────────────────────────────────────────────────

create or replace function public._agenda_aplicar_habilidade(p_autor uuid, p_dados jsonb, p_trecho text, p_hoje date,
                                                             p_agora timestamptz)
 returns text
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  v_forma  text := d ->> 'forma';
  v_os     uuid := (d ->> 'os')::uuid;
  v_payee  uuid;
  v_lider  uuid := (d ->> 'lider_payee_id')::uuid;
  v_curto  text := coalesce(nullif(d ->> 'curto', ''), d ->> 'numero');
  v_old    public.os_planejamento%rowtype;
  v_novo   jsonb;
  v_frase  text;
  v_q      uuid;
  v_estado text;
  v_resto  text;
begin
  if p_agora is null then
    raise exception '_agenda_aplicar_habilidade: p_agora é obrigatório.' using errcode = '22004';
  end if;

  if v_forma = 'confirmar' then
    -- (d) As propostas da pergunta valem e a pergunta fecha. A pergunta que já fechou (neste lote, pela correção de outra linha, ou
    -- pelo prazo) não muda nada; a que o gestor refez (descartada: "a proposta mudou") recusa o lote.
    v_q := (d ->> 'pergunta_id')::uuid;
    select q.estado into v_estado from public.agenda_perguntas q where q.id = v_q for update;
    if v_estado = 'aberta' then
      update public.agenda_etiquetas set estado = 'vale', vale_desde = p_agora where pergunta_id = v_q and estado = 'proposta';
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você confirmou' where id = v_q;
    elsif v_estado is null or v_estado = 'descartada' then
      raise exception 'o que eu marquei de quem faz o quê mudou' using errcode = 'P0097';
    end if;
    return 'Quem faz o quê: ficou como eu marquei.';
  end if;

  if v_forma = 'pessoa' then
    -- (a) A etiqueta do dono, que já vale. O gatilho de exclusividade (P1) substitui a viva da mesma etiqueta (do dono ou do gestor,
    -- proposta ou vale) e a da outra de instala × ajudante.
    v_payee := (d ->> 'payee_id')::uuid;
    if v_payee is null or not exists (select 1 from public.payees p where p.id = v_payee and p.active) then
      raise exception '% não está mais no cadastro de pessoas.', coalesce(d ->> 'nome', 'A pessoa');
    end if;
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
    values (v_payee, d ->> 'etiqueta', (d ->> 'nivel')::smallint, 'dono', 'vale', 'você disse', public._agenda_corta(p_trecho, 500),
            p_agora, p_agora, p_autor);
    v_frase := case when coalesce((d ->> 'eh_dono')::boolean, false) then 'Você' else d ->> 'nome' end || ': '
               || public._agenda_etiqueta_texto(d ->> 'etiqueta', (d ->> 'nivel')::smallint) || '.';
  elsif v_forma in ('exige', 'lider') then
    -- (b) e (c): os_planejamento, com o histórico do planejar ({em, autor, trecho, antes, depois}; os 20 mais novos).
    if v_os is null or not exists (select 1 from public.service_orders where id = v_os) then
      raise exception 'o serviço % não existe mais', coalesce(d ->> 'numero', v_os::text);
    end if;
    if v_forma = 'lider' and v_lider is not null
       and not exists (select 1 from public.payees p where p.id = v_lider and p.active) then
      raise exception '% não está mais no cadastro de pessoas.', coalesce(d ->> 'lider_nome', 'O responsável');
    end if;
    insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
    select * into v_old from public.os_planejamento where service_order_id = v_os for update;
    if v_forma = 'exige' then
      v_novo := coalesce(v_old.exigencias_ditas, '{}'::jsonb) || jsonb_build_object(d ->> 'exige', d ->> 'meios');
      update public.os_planejamento
         set exigencias_ditas = v_novo, exigencias_trecho = public._agenda_corta(p_trecho, 500),
             historico = public._os_material_historico(v_old.historico, jsonb_build_object(
               'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500),
               'antes', jsonb_build_object('exigencias_ditas', v_old.exigencias_ditas),
               'depois', jsonb_build_object('exigencias_ditas', v_novo))),
             atualizado_em = now(), atualizado_por = p_autor
       where service_order_id = v_os;
      v_frase := v_curto || ': ' || public._agenda_habilidade_frase(d) || '.';
    else
      update public.os_planejamento
         set lider_payee_id = v_lider, lider_em = case when v_lider is not null then p_agora end,
             lider_trecho = case when v_lider is not null then public._agenda_corta(p_trecho, 300) end,
             historico = public._os_material_historico(v_old.historico, jsonb_build_object(
               'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500),
               'antes', jsonb_build_object('lider_payee_id', v_old.lider_payee_id),
               'depois', jsonb_build_object('lider_payee_id', v_lider))),
             atualizado_em = now(), atualizado_por = p_autor
       where service_order_id = v_os;
      v_frase := v_curto || ': ' || case when v_lider is null then 'fica sem responsável fixo'
                                         else 'o responsável é ' || (d ->> 'lider_nome') end || '.';
    end if;
  else
    raise exception '_agenda_aplicar_habilidade: forma "%" não existe', v_forma using errcode = '22023';
  end if;

  -- Em (a), (b) e (c), com a pergunta habilidade:equipe aberta e já mostrada: o dono leu o que a agenda marcou e corrigiu o que quis.
  -- As propostas dela que o lote corrigiu (as linhas de pessoa deste *grava*: as ainda abertas e as gravadas agora; instala e
  -- ajudante se excluem) viram substituídas, as outras valem e a pergunta fecha.
  select q.id into v_q
    from public.agenda_perguntas q
   where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta' and q.mostrada_em is not null
   order by q.criada_em desc, q.id desc
   limit 1
   for update;
  if v_q is not null then
    update public.agenda_etiquetas e
       set estado = 'substituida', substituida_em = p_agora
     where e.pergunta_id = v_q and e.estado = 'proposta'
       and exists (select 1 from public.agenda_rascunho r
                    where r.autor = p_autor and r.tipo = 'habilidade' and r.dados ->> 'forma' = 'pessoa'
                      and (r.estado = 'aberto' or (r.estado = 'gravado' and r.gravado_em = now()))
                      and (r.dados ->> 'payee_id')::uuid = e.payee_id
                      and (r.dados ->> 'etiqueta' = e.etiqueta
                           or (r.dados ->> 'etiqueta' in ('instala', 'ajudante') and e.etiqueta in ('instala', 'ajudante'))));
    select string_agg(public._agenda_nome_curto(py.name) || ' '
                      || split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1), '; '
                      order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                               public._agenda_nome_curto(py.name), e.id)
      into v_resto
      from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
     where e.pergunta_id = v_q and e.estado = 'proposta';
    update public.agenda_etiquetas set estado = 'vale', vale_desde = p_agora where pergunta_id = v_q and estado = 'proposta';
    update public.agenda_perguntas
       set estado = 'resolvida',
           resolvida_motivo = case when v_resto is null then 'você corrigiu' else 'você corrigiu; o resto ficou como eu marquei' end
     where id = v_q;
    if v_resto is not null then
      v_frase := v_frase || ' O resto ficou como eu marquei: ' || v_resto || '.';
    end if;
  end if;
  return v_frase;
end;
$function$;

comment on function public._agenda_aplicar_habilidade(uuid, jsonb, text, date, timestamptz) is
  'Agenda de Produção (Fase 7c, P4; spec §5.4, §6.3): grava uma linha de rascunho habilidade e devolve a frase do "Gravado. Agora:" — (a) pessoa: a etiqueta do dono em agenda_etiquetas, que já vale (origem dono, motivo "você disse", o trecho, vale_desde = a hora do *grava*, criado_por = o autor; o gatilho de exclusividade substitui a viva da mesma etiqueta e a de instala × ajudante) — "Roberto: instala sozinho."; (b) exige: os_planejamento.exigencias_ditas || {exigência: meios} e exigencias_trecho — "Lenine: pede quem sobe no teto em todos os dias."; (c) lider: lider_payee_id, lider_em e lider_trecho ("ninguém": os três nulos) — "Lenine: o responsável é Roberto." / "Lenine: fica sem responsável fixo."; (b) e (c) com o histórico {em, autor, trecho, antes, depois}; (d) confirmar: as propostas da pergunta valem e ela fecha ("você confirmou") — "Quem faz o quê: ficou como eu marquei."; a pergunta que o gestor refez recusa o lote (P0097). Em (a), (b) e (c), com a pergunta habilidade:equipe aberta e já mostrada: as propostas que o lote corrigiu viram substituídas, as outras valem, a pergunta fecha ("você corrigiu; o resto ficou como eu marquei") e a frase ganha " O resto ficou como eu marquei: João é ajudante.". Só pelo agenda_rascunho_gravar; sem grant a ninguém, nem service_role.';

-- ── 4. A releitura de cada tipo: o tipo habilidade ─────────────────────────────────────────────────────────────────

-- _agenda_rascunho_frase (de 20261101100100_agenda_fase7b_disponibilidade.sql)
create or replace function public._agenda_rascunho_frase(p_tipo text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_t      text;
  v_forn   text := nullif(p_d ->> 'fornecedor_txt', '');
  v_hoje   date := (p_d ->> 'hoje')::date;
  v_quando text;
  -- FASE 4: (P3) de onde veio o aviso ("nota 51038 da Kamell", "Pix de R$ 480,00 à Premel, seg 26/10").
  v_aviso  text;
  -- FASE 4: fim
  -- FASE 7b: (7b P2) a semana dita e as datas
  v_7b_dias smallint[];
  v_7b_fora smallint[];
  v_7b_n    int;
  -- FASE 7b: fim
begin
  if p_tipo = 'planejar' then
    if nullif(p_d ->> 'escopo_decidido', '') is not null then
      v_partes := v_partes || (p_d ->> 'escopo_decidido');
    end if;
    v_t := null;
    if p_d ->> 'dias' is not null then
      v_t := public._agenda_dias((p_d ->> 'dias')::numeric)
             || case when p_d ->> 'estimativa_fonte' = 'aceita' then ' (a minha estimativa, que você aceitou)' else '' end;
    end if;
    if jsonb_array_length(coalesce(p_d -> 'equipe', '[]'::jsonb)) > 0 then
      v_t := concat_ws(' ', v_t, 'com ' || public._agenda_lista(array(
               select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                      || case e ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                 from jsonb_array_elements(p_d -> 'equipe') with ordinality t(e, o) order by o), null));
    elsif p_d ? 'equipe' and p_d ->> 'dias' is null then
      v_t := 'sem ninguém marcado para ir';
    end if;
    if v_t is not null then
      v_partes := v_partes || v_t;
    end if;
    if p_d ->> 'dono' is not null then
      v_partes := v_partes || case p_d ->> 'dono' when 'abre_e_fecha' then 'você abre e fecha'
                                                 when 'sempre' then 'você fica o tempo todo' else 'você não vai' end;
    end if;
    if p_d ->> 'precisa_ate' is not null then
      v_partes := v_partes || ('o cliente precisa até ' || public._dia_curto((p_d ->> 'precisa_ate')::date));
    elsif p_d ? 'precisa_ate' then
      v_partes := v_partes || 'o cliente não tem mais prazo'::text;
    end if;
    if p_d ? 'bem' then
      v_partes := v_partes || case p_d #>> '{bem,modo}'
        when 'livre' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' já está livre'
        when 'fora' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica fora '
                         || public._agenda_quando_texto((p_d #>> '{bem,de}')::date, (p_d #>> '{bem,ate}')::date)
        else coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica livre ' || public._dia_curto((p_d #>> '{bem,livre_em}')::date) end;
    end if;
    if p_d ->> 'nao_antes_de' is not null then
      v_partes := v_partes || ('não antes de ' || public._dia_curto((p_d ->> 'nao_antes_de')::date)
                               || case when coalesce(p_d ->> 'nao_antes_motivo', 'você disse') = 'você disse' then ''
                                       else ' (' || (p_d ->> 'nao_antes_motivo') || ')' end);
    elsif p_d ? 'nao_antes_de' then
      v_partes := v_partes || 'pode começar sem esperar data'::text;
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    elsif p_d ? 'escopo_em_aberto' and nullif(p_d ->> 'escopo_decidido', '') is null then
      v_partes := v_partes || 'nada mais a decidir no escopo'::text;
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    elsif p_d ? 'congelada_ate' then
      v_partes := v_partes || 'sai da espera'::text;
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
    end if;
    -- FASE 2: quanto dá para adiantar no pátio sem o bem (bancada: barramento, chicote).
    if p_d ? 'adiantavel_patio' then
      v_partes := v_partes || case when p_d ->> 'adiantavel_patio' is null then 'nada a adiantar no pátio'
                                   else 'dá para adiantar ' || public._agenda_dias((p_d ->> 'adiantavel_patio')::numeric) || ' no pátio' end;
    end if;
    -- FASE 5: o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)") e como o serviço é dito a ele
    if jsonb_typeof(p_d -> 'prometido') = 'object' then
      v_partes := v_partes || format('você disse ao %s: %s (%s)', coalesce(nullif(p_d ->> 'curto', ''), 'cliente'),
        case when p_d #>> '{prometido,de}' = p_d #>> '{prometido,ate}' then public._dia_curto((p_d #>> '{prometido,ate}')::date)
             else format('de %s a %s', public._dia_curto((p_d #>> '{prometido,de}')::date),
                         public._dia_curto((p_d #>> '{prometido,ate}')::date)) end,
        case when p_d #>> '{prometido,tipo}' = 'firme' then 'data firme' else 'uma faixa' end);
    end if;
    if nullif(p_d ->> 'servico_cliente', '') is not null then
      v_partes := v_partes || format('o serviço, para o cliente: %s', p_d ->> 'servico_cliente');
    end if;
    -- FASE 5: fim
    -- FASE 7b: (7b P2, §6.6) a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros
    -- meios-dias") e, com menos técnicos do que ela pede, o aviso de que a OS espera
    if p_d ->> 'dupla' is not null then
      v_7b_n := (p_d ->> 'dupla_meios')::int;
      v_partes := v_partes || case p_d ->> 'dupla'
        when 'nao' then 'vai com 1 pessoa só'
        when 'todos' then 'vai em dupla o tempo todo'
        when 'inicio' then case when v_7b_n = 1 then 'vai em dupla no primeiro meio-dia'
                                else format('vai em dupla nos %s primeiros meios-dias', v_7b_n) end
        else case when v_7b_n = 1 then 'vai em dupla no último meio-dia'
                  else format('vai em dupla nos %s últimos meios-dias', v_7b_n) end end;
    end if;
    if nullif(p_d ->> 'dupla_aviso', '') is not null then
      return array_to_string(v_partes, '; ') || '. ' || (p_d ->> 'dupla_aviso');
    end if;
    -- FASE 7b: fim
    return array_to_string(v_partes, '; ');
  end if;

  if p_tipo = 'material' then
    v_t := case p_d ->> 'acao'
      when 'na_mao' then
        case when p_d ->> 'quantidade_na_mao' is not null
             then format('%s de %s na mão', public._os_material_qtd((p_d ->> 'quantidade_na_mao')::numeric),
                         public._os_material_qtd((p_d ->> 'quantidade_necessaria')::numeric))
             when (p_d ->> 'chegou_em')::date = v_hoje then 'na mão (desde hoje)'
             else 'na mão desde ' || public._dia_curto((p_d ->> 'chegou_em')::date) end
      when 'comprado' then
        'comprado' || case when (p_d ->> 'comprado_em')::date = v_hoje then ' hoje'
                           else ' em ' || public._dia_curto((p_d ->> 'comprado_em')::date) end
        || case when p_d ->> 'previsao_ate' is not null
                then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' else '' end
      when 'a_caminho' then
        case when p_d ->> 'previsao_ate' is null then 'a caminho, sem previsão'
             when p_d ->> 'previsao_de' is not null then
               format('chega entre %s e %s (você disse)', public._dia_curto((p_d ->> 'previsao_de')::date),
                      public._dia_curto((p_d ->> 'previsao_ate')::date))
             else 'chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' end
      when 'falta' then
        case when coalesce((p_d ->> 'vou_comprar')::boolean, false) then
               case when p_d ->> 'compra_prevista_em' is null then 'você vai comprar'
                    else 'você compra ' || public._dia_curto((p_d ->> 'compra_prevista_em')::date) end
             else 'falta comprar' end
      when 'sem_previsao' then 'comprado, sem previsão de chegada'
      when 'dispensado' then 'não precisa mais (sai da lista)'
      else null end;
    -- FASE 4: (P3) o aviso (a nota, o Pix ou a mensagem que a agenda perguntou) diz de onde veio; o fornecedor já está nele.
    if jsonb_typeof(p_d -> 'aviso') = 'object' then
      v_aviso := p_d -> 'aviso' ->> 'curto';
      v_t := case
        when coalesce((p_d ->> 'nota_chegou')::boolean, false) then
          format('na mão desde %s (a %s entrou no estoque)', public._dia_curto((p_d ->> 'chegou_em')::date), v_aviso)
        when p_d ->> 'acao' = 'na_mao' and p_d ->> 'quantidade_na_mao' is null then
          format('na mão desde %s (%s)', case when (p_d ->> 'chegou_em')::date = v_hoje then 'hoje'
                                              else public._dia_curto((p_d ->> 'chegou_em')::date) end, v_aviso)
        when p_d ->> 'acao' = 'a_caminho' and p_d -> 'aviso' ->> 'tipo' = 'nfe' then
          'a caminho pela ' || v_aviso
          || case when p_d ->> 'previsao_ate' is null then ', sem previsão de chegada'
                  when p_d ->> 'previsao_fonte' = 'dono' then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)'
                  else ', chega por volta de ' || public._dia_curto((p_d ->> 'previsao_ate')::date) end
        when p_d ->> 'acao' = 'a_caminho' and p_d ->> 'previsao_ate' is not null and p_d ->> 'previsao_fonte' = 'fornecedor' then
          format('a caminho, chega por volta de %s (%s)', public._dia_curto((p_d ->> 'previsao_ate')::date), v_aviso)
        when p_d ->> 'acao' = 'comprado' and p_d -> 'aviso' ->> 'tipo' = 'pix' and p_d ->> 'previsao_ate' is null
             and v_aviso like 'Pix %' then
          'comprado pelo ' || v_aviso
        else coalesce(v_t || ' (' || v_aviso || ')', v_t) end;
      if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
        v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
      end if;
      return v_t;
    end if;
    -- FASE 4: fim
    if v_t is not null and v_forn is not null and p_d ->> 'acao' <> 'dispensado' then
      v_t := v_t || ', fornecedor ' || v_forn;
    end if;
    if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
      v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
    end if;
    return v_t;
  end if;

  if p_tipo = 'disponibilidade' then
    -- FASE 7b: (7b P2, §6.6, R4.2(c)) quem não está na equipe (a pessoa do cadastro): a frase de sempre e o aviso de que, com
    -- *grava*, ela entra
    if coalesce((p_d ->> 'fora_da_equipe')::boolean, false) then
      return public._agenda_rascunho_frase(p_tipo, p_d - 'fora_da_equipe')
             || format('. %s ainda não está na equipe da agenda: com *grava*, ele entra %s', p_d ->> 'nome',
                       case when coalesce((p_d ->> 'padrao')::boolean, false) then 'com esses dias, toda semana'
                            when p_d ? 'semana' or p_d ? 'datas' or p_d ->> 'de' is distinct from p_d ->> 'ate' then 'só nesses dias'
                            else 'só nesse dia' end);
    end if;
    -- a semana dita ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e
    -- fecha"); o rótulo leva a semana ("Roberto, semana de 16/11")
    if p_d ? 'semana' then
      v_7b_dias := array(select jsonb_array_elements_text(coalesce(p_d -> 'dias_semana', '[]'::jsonb))::smallint);
      v_7b_fora := array(select x::smallint from generate_series(1, 5) x where not (x::smallint = any (v_7b_dias)) order by 1);
      if cardinality(v_7b_dias) = 0 and not coalesce((p_d ->> 'sabado')::boolean, false) then
        return case when (p_d ->> 'eh_dono')::boolean then 'só abre e fecha' else 'não vem' end;
      end if;
      if (p_d ->> 'eh_dono')::boolean then
        return 'fica em campo ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
               || case when cardinality(v_7b_fora) > 0 then '; nos outros dias, só abre e fecha' else '' end;
      end if;
      return 'vem ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
             || case when cardinality(v_7b_fora) > 0 then ' (e não vem ' || public._agenda_dias_curtos(v_7b_fora) || ')' else '' end;
    end if;
    -- as datas de quem vem sob demanda ("vem qua 11/11 e qui 12/11 (só nesses dias)")
    if p_d ? 'datas' then
      return case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end
             || public._agenda_lista(array(select public._dia_curto(x::date)
                                                  || case when extract(isodow from x::date)::int = 6 then ' de manhã' else '' end
                                             from jsonb_array_elements_text(p_d -> 'datas') with ordinality t(x, o) order by o), null)
             || ' (só nesses dias)';
    end if;
    -- FASE 7b: fim
    v_quando := case when (p_d ->> 'padrao')::boolean
                     then public._agenda_dias_semana_texto(array(select jsonb_array_elements_text(p_d -> 'dias_semana')::smallint))
                     else public._agenda_quando_texto((p_d ->> 'de')::date, (p_d ->> 'ate')::date) end;
    return case p_d ->> 'dito'
      when 'vem' then case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end || v_quando
      when 'nao_vem' then case when (p_d ->> 'eh_dono')::boolean then 'fora de campo ' else 'não vem ' end || v_quando
      when 'so_manha' then v_quando || ' à tarde, não'
      else v_quando || ' de manhã, não' end
      || case when coalesce((p_d ->> 'sabado_por_data')::boolean, false) then ' (sábado eu só conto por data)' else '' end;
  end if;

  -- FASE 2: os pedidos da conversa (marcar, aplicar/decidir, desfazer, andamento) chegam com a frase pronta do banco.
  if p_tipo in ('marcar', 'aplicar', 'desfazer', 'andamento') then
    return p_d ->> 'frase_pronta';
  end if;

  -- FASE 4: o prazo do fornecedor chega com a frase pronta do banco (agenda_rascunho_fornecedor).
  if p_tipo = 'fornecedor' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 4: (P3) "não é material de serviço" (a nota, o Pix ou a mensagem) chega com a frase pronta (agenda_rascunho_material).
  if p_tipo = 'aviso' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 7c: (7c P4, §5.4, §6.3) quem faz o quê, o que a OS pede e o responsável (agenda_rascunho_habilidade): a releitura sai dos
  -- dados (_agenda_habilidade_frase: "Roberto instala sozinho", "pede quem sobe no teto em todos os dias", "o responsável é Roberto
  -- (fica em todos os dias)", "fica como eu marquei (…)")
  if p_tipo = 'habilidade' then
    return public._agenda_habilidade_frase(p_d);
  end if;
  -- FASE 7c: fim
  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento), o prazo do fornecedor (Fase 4) e o "não é de serviço" (tipo aviso, Fase 4, P3) trazem a frase pronta (dados.frase_pronta); o material com o aviso diz de onde veio ("a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10", "na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10)", "na mão desde qua 28/10 (a nota 51038 da Kamell entrou no estoque)"). Fase 5 (P5): o planejar diz o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)"; faixa: "de qua 04/11 a dom 08/11 (uma faixa)") e como o serviço é dito a ele ("o serviço, para o cliente: a instalação do compressor"). Fase 7b (P2, §6.6): o planejar com a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros meios-dias", "… nos 2 últimos meios-dias"; 1 = "no primeiro meio-dia") e, com menos técnicos do que ela pede, o aviso "Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine"; a disponibilidade com a semana ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e fecha"; "não vem"; "só abre e fecha") e com as datas ("vem qua 11/11 e qui 12/11 (só nesses dias)"; o sábado "de manhã"); quem não está na equipe ganha "Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias". FASE 7c (P4, §5.4, §6.3): o tipo habilidade sai de _agenda_habilidade_frase — "Roberto instala sozinho", "pede quem sobe no teto em todos os dias", "o responsável é Roberto (fica em todos os dias)", "fica sem responsável fixo", "fica como eu marquei (Roberto instala sozinho; João é ajudante)". Os outros tipos, os de antes, byte a byte.';

-- ── 5. O *grava*: o tipo habilidade ───────────────────────────────────────────────────────────────────────────────

-- agenda_rascunho_gravar (de 20261101100100_agenda_fase7b_disponibilidade.sql)
create or replace function public.agenda_rascunho_gravar(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_exp     int;
  v_exp_dia date;
  v_ids     uuid[];
  v_oss_mat uuid[];
  v_r       public.agenda_rascunho%rowtype;
  v_x       uuid;
  v_n       int := 0;
  v_item    text;
  v_estado  text;
  v_msg     text;
  v_linhas  text[] := '{}';
  v_g       record;
  v_p       jsonb;
  v_nome    int;
  -- FASE 2: a hora do *grava* (now(); a bancada fixa com set_config('agenda.agora', …, true), como agenda.hoje), a
  -- config, as frases do que a agenda fez com os pedidos e o tipo de cada linha.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  cf        public.agenda_config := public._agenda_cfg();
  v_f2      text[] := '{}';
  v_f2_item text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));
  -- FASE 7: (7a P10) as frases da peça que voltou a faltar (_agenda_aplicar_material as junta em agenda.material_reabriu)
  -- começam vazias neste *grava*
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  -- FASE 2: primeiro os fatos (Fase 1), depois o andamento, marcar, publicar/decidir e desfazer — cada grupo na ordem em
  -- que o dono falou.
  select coalesce(array_agg(r.id order by case r.tipo when 'andamento' then 1 when 'marcar' then 2 when 'aplicar' then 3
                                                      when 'desfazer' then 4 else 0 end,
                                          (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- FASE 2: com a agenda automática fora de 'ligado', o pedido à agenda não grava — e o lote é tudo ou nada.
  -- FASE 3: menos concluir e entregar, que valem em todos os modos (a conclusão pela porta é a correção do D7).
  if cf.modo_proposta <> 'ligado'
     and exists (select 1 from public.agenda_rascunho r where r.id = any (v_ids) and r.tipo in ('marcar', 'aplicar', 'desfazer', 'andamento')
                    and not (r.tipo = 'andamento' and r.dados ->> 'evento' in ('concluiu', 'entregou'))) then
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'motivo', 'em_teste',
      'texto', 'Não gravei nada: a agenda automática ainda está em teste e o que você pediu mexe na agenda. Mande *descarta* e me diga de novo o resto.');
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca, UMA vez antes de entrar o lote, só o que ele realmente troca:
    --   · "vem" (seg a qui): as linhas de padrão dela (do histórico e do dono) que caem em algum desses dias; os
    --     outros dias da semana continuam como estavam;
    --   · "só de manhã", "só à tarde", "não vem" (terça): o "vem" fica; a linha indisponível do turno entra por cima
    --     (a capacidade põe o "não vem neste turno" acima do padrão "vem"). Só sai a restrição que o dono já tinha
    --     dito para os mesmos dias ("só à tarde às terças" e depois "só de manhã às terças").
    update public.agenda_disponibilidade a
       set substituida_em = now()
      from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                   array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
              from public.agenda_rascunho r
             where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
     where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
       and ((n.situacao = 'disponivel' and a.origem in ('historico', 'dono') and a.dias_semana && n.dias)
            or (n.situacao = 'indisponivel' and a.origem = 'dono' and a.situacao = 'indisponivel'
                and a.dias_semana <@ n.dias));

    -- FASE 7b: (7b P2; A4 = NOVO-agenda-55) com a pergunta dos dias fora de desligado (modo_dias), o padrão "vem" novo troca
    -- também o padrão que a própria pessoa (diarista) ou o assistente (agente) disse para os mesmos dias: a palavra mais nova
    -- vence. Desligado, só o histórico e o dono (o de antes).
    if cf.modo_dias <> 'desligado' then
      update public.agenda_disponibilidade a
         set substituida_em = now()
        from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                     array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
                from public.agenda_rascunho r
               where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
       where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
         and n.situacao = 'disponivel' and a.origem in ('diarista', 'agente') and a.dias_semana && n.dias;
    end if;
    -- FASE 7b: fim
    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'disponibilidade' then
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: o prazo do fornecedor vai ao cadastro dele; a frase entra no "Gravado. Agora:" junto dos pedidos.
        when 'fornecedor' then
          v_f2 := v_f2 || public._agenda_aplicar_fornecedor(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: fim
        -- FASE 4: (P3) "a nota da Correa não é de serviço": a nota, o Pix ou a mensagem respondidos sem OS; a frase entra junto
        -- dos pedidos.
        when 'aviso' then
          v_f2 := v_f2 || public._agenda_aplicar_aviso(v_autor, v_r.dados, v_r.trecho, v_r.canal, p_hoje);
        -- FASE 4: fim
        -- FASE 7c: (7c P4, §5.4) quem faz o quê, o que a OS pede e o responsável: a etiqueta do dono (agenda_etiquetas), o que a OS
        -- pede e o responsável (os_planejamento) e a pergunta habilidade:equipe; a frase entra no "Gravado. Agora:" junto dos pedidos.
        -- Como o fornecedor, grava em qualquer modo da agenda (o modo_proposta só segura os pedidos ao motor, acima).
        when 'habilidade' then
          v_f2 := v_f2 || public._agenda_aplicar_habilidade(v_autor, v_r.dados, v_r.trecho, p_hoje, v_agora);
        -- FASE 7c: fim
        else
          -- FASE 2: o pedido à agenda (marcar, aplicar/decidir, desfazer, andamento) pelas funções do motor.
          v_f2_item := public._agenda_aplicar_pedido(v_autor, v_r.tipo, v_r.service_order_id, v_r.dados, v_r.trecho, v_r.canal,
                                                     p_hoje, v_agora);
          if nullif(btrim(coalesce(v_f2_item, '')), '') is not null then
            v_f2 := v_f2 || v_f2_item;
          end if;
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    -- FASE 3: a porta recusou concluir ou entregar (o período fechado no financeiro): a frase dela.
    if v_estado = 'P0096' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', 'Não gravei nada. ' || btrim(v_msg));
    end if;
    -- FASE 2: a agenda recusou um pedido (a proposta ficou velha, a decisão mudou, não coube, já começou…).
    if v_estado = 'P0097' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', format('Não gravei nada. A agenda mudou desde a releitura: %s. Me peça de novo.', rtrim(btrim(v_msg), '.')));
    end if;
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
      'texto', format('Não gravei nada: %s (%s). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.',
                      case when v_estado = 'P0001' then v_msg else 'o banco recusou um item' end,
                      coalesce(v_item, 'o lote')));
  end;

  -- "Gravado. Agora:" — uma linha por OS (o estado da prontidão) e por pessoa, na ordem em que o dono falou.
  for v_g in
    select r.dados ->> 'grupo' as grupo, min((r.dados ->> 'ordem')::int) as ordem,
           (array_agg(r.service_order_id order by (r.dados ->> 'ordem')::int))[1] as os,
           (array_agg(r.dados order by (r.dados ->> 'ordem')::int))[1] as d,
           string_agg(r.dados ->> 'frase', '; ' order by (r.dados ->> 'ordem')::int) as frases
      from public.agenda_rascunho r
     where r.id = any (v_ids) and r.tipo in ('planejar', 'material', 'disponibilidade')   -- FASE 2: os pedidos vêm em v_f2
     group by r.dados ->> 'grupo'
     order by 2
  loop
    if v_g.os is not null then
      v_p := public.os_prontidao(v_g.os, p_hoje);
      select count(*) into v_nome from public.os_carteira(p_hoje) k where k.cliente_curto = v_p ->> 'cliente_curto';
      v_linhas := v_linhas || ('• ' || public._agenda_rotulo(jsonb_build_object(
                                 'curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero',
                                 'eh_orc', (v_p ->> 'eh_orcamento')::boolean, 'n_nome', v_nome))
                               || ': ' || (v_p ->> 'estado_texto') || '.');
    else
      v_linhas := v_linhas || ('• ' || (v_g.d ->> 'rotulo_grupo') || ': ' || v_g.frases || '.');
    end if;
  end loop;

  -- FASE 7: (7a P10, spec §6.4) a peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o 'compre até' reabriu
  -- (comprando hoje, chega qua 11/11).") entra no "Gravado. Agora:" junto dos pedidos — só com o "compre até" do gestor ligado
  -- (_agenda_aplicar_material só escreve a frase assim); sem isso, nada muda
  v_f2 := v_f2 || coalesce(string_to_array(nullif(current_setting('agenda.material_reabriu', true), ''), E'\n'), '{}'::text[]);
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim
  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade; Fase 4: _agenda_aplicar_fornecedor, o prazo dito de um fornecedor, que não depende do modo da agenda; Fase 4, P3: _agenda_aplicar_aviso, o "não é de serviço" da nota, do Pix ou da mensagem), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava (Fase 3: menos concluir e entregar, que gravam em todos os modos; a recusa da porta = "Não gravei nada. Não concluí: …" e o lote volta). Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo. FASE 7 (7a P10, spec §6.4): a frase da peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o ''compre até'' reabriu (comprando hoje, chega qua 11/11).", que _agenda_aplicar_material junta em agenda.material_reabriu só com o "compre até" do gestor ligado) entra no "Gravado. Agora:" junto dos pedidos; a variável começa vazia em cada *grava*. Sem ela, a de antes, byte a byte. Fase 7b (P2; A4 = NOVO-agenda-55): com modo_dias fora de desligado, a troca única do padrão "vem" novo pega também os padrões que a própria pessoa (diarista) ou o assistente (agente) disse para os mesmos dias — a palavra mais nova vence. Desligado, a de antes, byte a byte. FASE 7c (P4, §5.4): o tipo habilidade (quem faz o quê, o que a OS pede, o responsável e o "está certo") aplica por _agenda_aplicar_habilidade, com p_agora = a hora do *grava*, em qualquer modo da agenda (como o fornecedor); a frase entra no "Gravado. Agora:" junto dos pedidos ("Roberto: instala sozinho. O resto ficou como eu marquei: João é ajudante."). Os outros tipos, os de antes, byte a byte.';

-- ── 6. Portas ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- A RPC da ferramenta (confere o cargo por _autor_da_agenda): o painel (authenticated, o login do dono) e o WhatsApp (service_role),
-- como as outras RPCs de rascunho da agenda. A frase: só service_role (como _agenda_rascunho_frase, que a chama). O *grava* da linha:
-- ninguém (só o agenda_rascunho_gravar, definer, a chama). As 2 recriadas mantêm as portas delas (create or replace não muda a ACL).
revoke all on function public.agenda_rascunho_habilidade(uuid, text, text, text, text, text, text, text, boolean, text, date)
  from public, anon;
grant execute on function public.agenda_rascunho_habilidade(uuid, text, text, text, text, text, text, text, boolean, text, date)
  to authenticated, service_role;
revoke all on function public._agenda_habilidade_frase(jsonb) from public, anon, authenticated;
grant execute on function public._agenda_habilidade_frase(jsonb) to service_role;
revoke all on function public._agenda_aplicar_habilidade(uuid, jsonb, text, date, timestamptz)
  from public, anon, authenticated, service_role;
