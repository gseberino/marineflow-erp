-- Retorno rápido ao cliente, F1 (sobe em sombra na seg 16/11/2026): os sinais de texto e a triagem
-- sem IA, tudo em SQL, para o replay (P9) rodar pela CLI e a abertura do caso (P5) decidir no banco.
--
-- 1. Porte com paridade provada (o fixture único supabase/tests/retorno_f1_frases.json, lido pelos dois
--    lados: retorno_f1_sinais.sql aqui e _shared/retorno/frases_test.ts no TypeScript). O SQL repete,
--    alternativa por alternativa, as regras que já existem em TypeScript, trocando \b por \y:
--    - _retorno_busca: o semAcentoInteiro de _shared/secretario/palavras.ts (sem acento, minúsculo, só
--      letras e números; NÃO corta em 120 como o paraBusca). Diferença conhecida: o TS tira qualquer
--      acento (NFD); o translate cobre os do português e o ñ;
--    - _retorno_parece_vendedor: pareceVendedor (o nome que diz que vende, ou a apresentação/oferta);
--    - _retorno_so_agradecimento: pareceSoAgradecimento (só cumprimento, agradecimento ou emoji, ou o
--      "vou dar sequência" de quem encerra agindo);
--    - _retorno_encerrou: contatoEncerrou (_shared/whatsapp/contato-encerrou.ts): fechou com outra
--      empresa ou desistiu; pergunta DEPOIS da frase reabre;
--    - o pede_preco de _retorno_sinais: PEDE_PRECO, sobre o texto inteiro.
--    Duas diferenças de motor, que o fixture evita de propósito: o \b do JavaScript (sem a flag u) vê
--    letra acentuada como fronteira e o \y do PostgreSQL não; e o paraBusca corta em 120 caracteres (por
--    isso só os casos com pede_preco têm menos de 120).
-- 2. Regras novas, que só existem aqui (plano B.2 e B.3): serviço, bem (o unidade.ts mais "carro" e os
--    modelos), pedido (nunca decide sozinho: só vale com serviço e bem, L7), saudação, pressa ("hoje"
--    sozinho NÃO é pressa, R1-09), URGENTE, risco, "quero falar com o Gustavo", reclamação (lista
--    inicial conservadora: a sombra mede), LGPD e o PARAR por extenso (parar_largo).
--    - parar_largo são só as formas CLARAS da regra larga de reply-router.ts:31 (lida, nunca importada
--      aqui), sem "nunca mais" e sem "me tira" solto, que a F0b-5 tirou de propósito ("nunca mais
--      funcionou", "me tira uma dúvida"). Não grava opt-out: tira o recibo e vai à linha "Para conferir"
--      da manhã (P5 regra 3, P9). O "não me mand…" da regra larga ficou mais estreito ("não me manda o
--      pix ainda" não é pedido de parar): só "não me manda/mande/mandem mais|mensagem".
-- 3. _retorno_hora_real: a hora real de uma mensagem (hora_real da F0b; sem ela, o messageTimestamp do
--    raw_payload; sem ele, occurred_at), na mesma ordem de retorno_medidas_base. Toda "hora real" da
--    leva passa por aqui: as linhas de antes de 06/11 não têm hora_real.
-- 4. Triagem por mensagem, que lê a conversa SEM olhar o futuro (só linhas com occurred_at até o da
--    própria mensagem, ou até p_ate/p_antes):
--    - _retorno_pede_resposta: figurinha, reação, robô (F0b ou resposta em até 5 s ao automático),
--      PARAR, PARAR por extenso, mídia sem legenda em conversa viva, agradecimento (a saudação que abre
--      conversa pede) e "fechou com outro" não pedem resposta. Desvio da spec P2.1: o envelope de
--      álbum, localização e contato ('[conteúdo vazio]') conta como mídia sem legenda;
--    - _retorno_resposta_de_robo: a "mensagem de ausência" que responde ao recibo em segundos; vale por
--      mensagem, não marca o número. Desvio da spec P2.1: compara pelo segundo (a enviada tem hora com
--      microssegundos; a recebida, o messageTimestamp cortado no segundo);
--    - _retorno_numero_novo: "nunca houve saída HUMANA a esse número" (R1-08), pela regra única
--      _saida_e_humana (F0b);
--    - _retorno_pedido_de_servico: os sinais somados de TODAS as recebidas do número nas primeiras 24 h
--      (B.2), com pedido = (site ou (serviço e bem e pedido)) e não vendedor.
--
-- Funções internas (_retorno_*): revoke de public, anon e authenticated, sem grant (só o banco chama,
-- pelas funções SECURITY DEFINER do retorno). As de texto são IMMUTABLE e sem SECURITY DEFINER (molde
-- _e_pedido_de_parar e _saida_e_humana da F0b); as que leem whatsapp_messages são STABLE e SECURITY
-- DEFINER (molde _retorno_e_automatico). Nenhuma escreve.
--
-- Sem dado: nenhuma tabela nova, nenhuma linha muda.
-- Reverter: drop function public._retorno_pedido_de_servico(text, timestamptz, timestamptz, text),
-- public._retorno_pede_resposta(uuid), public._retorno_resposta_de_robo(uuid),
-- public._retorno_numero_novo(text, timestamptz), public._retorno_hora_real(public.whatsapp_messages),
-- public._retorno_nome_dito(text), public._retorno_sinais(text, text), public._retorno_encerrou(text),
-- public._retorno_so_agradecimento(text), public._retorno_parece_vendedor(text, text),
-- public._retorno_busca(text) (depois das migrations seguintes da F1, que chamam estas).

-- ── 1. Texto de busca ───────────────────────────────────────────────────────────────────────────────

create or replace function public._retorno_busca(p text)
returns text
language sql
immutable
set search_path = public
as $$
  select btrim(regexp_replace(regexp_replace(
           translate(lower(coalesce(p, '')), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
           '[^a-z0-9]+', ' ', 'g'), '\s+', ' ', 'g'));
$$;

comment on function public._retorno_busca(text) is
  'Retorno F1 (P2): texto de busca (sem acento, minúsculo, só letras e números, espaços juntados), o semAcentoInteiro de palavras.ts, sem o corte de 120 do paraBusca.';

revoke all on function public._retorno_busca(text) from public, anon, authenticated;

-- ── 2. Portes do TypeScript (paridade pelo fixture) ─────────────────────────────────────────────────

-- pareceVendedor (palavras.ts:99-131): VENDEDOR_NO_NOME sobre o nome; as 7 alternativas de
-- VENDEDOR_NO_TEXTO sobre o texto sem o "🎤" da transcrição. Cliente cadastrado nunca é vendedor: quem
-- chama aplica só a número sem cadastro (P5 regra 8).
create or replace function public._retorno_parece_vendedor(p_nome text, p_texto text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public._retorno_busca(p_nome)
           ~ '\y(?:consultor|consultora|consultores|consultoras|vendedor|vendedora|vendas|representante|representantes|representacoes|corretor|corretora|corretagem|consorcio|consorcios|seguros|seguradora|telecom|operadora|televendas|telemarketing|promotor|promotora)\y'
      or public._retorno_busca(regexp_replace(coalesce(p_texto, ''), '^\s*🎤\s*', ''))
           ~ ('\y(?:sou|me chamo|meu nome e|aqui e|aqui quem fala e|falo em nome)\y[a-z0-9 ]{0,60}?\y(?:consultor|consultora|vendedor|vendedora|representante|corretor|corretora|promotor|promotora|executivo de (?:contas|vendas|negocios)|executiva de (?:contas|vendas|negocios)|gerente de (?:contas|relacionamento|negocios))\y'
              || '|\yconsultor[a]? (?:empresarial|comercial|de vendas|de negocios|de credito|de seguros|de beneficios|de investimentos|financeir[oa])\y'
              || '|\y(?:time|setor|equipe|departamento) comercial d[aeo]\y'
              || '|\y(?:seu|o seu|teu|sua) (?:contrato|plano|linha|fatura) (?:com|da|de|na|no) (?:a |o )?(?:tim|vivo|claro|oi|nextel|algar|operadora)\y'
              || '|\y(?:portabilidade|consorcio|consorcios|carta de credito|credito pre ?aprovado|maquininha|reajuste automatico|plano (?:empresarial|corporativo|pos pago|de telefonia|de internet|de saude|odontologico))\y'
              || '|\yofertas? (?:para (?:voce|vc|o senhor|a senhora) )?(?:pagar menos|exclusivas?|especia(?:l|is)|imperdive(?:l|is))\y'
              || '|\y(?:para|pra) (?:voce|vc|o senhor|a senhora) pagar menos\y');
$$;

comment on function public._retorno_parece_vendedor(text, text) is
  'Retorno F1 (P2): porte de pareceVendedor (palavras.ts): o nome diz que vende ou o texto se apresenta vendendo. Paridade pelo fixture retorno_f1_frases.json.';

revoke all on function public._retorno_parece_vendedor(text, text) from public, anon, authenticated;

-- pareceSoAgradecimento (palavras.ts:77-90). SO_AGRADECIMENTO (palavras.ts:45-55) copiada na ordem do
-- Set (sem o "bom" repetido) e ENCERRA_AGINDO (palavras.ts:56-65) montada com a mesma lista. O emoji sai
-- pelas faixas de pictogramas (o TS usa \p{Extended_Pictographic}): 1F000–1FAFF (com os tons de pele),
-- 2300–23FF, 2600–27BF, 2B00–2BFF, o seletor de variação FE0F e o ZWJ 200D.
create or replace function public._retorno_so_agradecimento(p_texto text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  c_lista constant text[] := array[
    'obrigado', 'obrigada', 'obrigados', 'obrigadas', 'obg', 'brigado', 'brigada', 'valeu', 'vlw', 'agradeco', 'grato', 'grata',
    'ok', 'okay', 'okk', 'blz', 'beleza', 'show', 'top', 'otimo', 'otima', 'perfeito', 'perfeita', 'combinado', 'fechado', 'certo',
    'certinho', 'joia', 'legal', 'massa', 'maravilha', 'excelente', 'tranquilo', 'sim', 'isso', 'entendi', 'ta', 'bom', 'boa',
    'dia', 'tarde', 'noite', 'oi', 'ola', 'opa', 'abraco', 'abracos', 'abs', 'ate', 'mais', 'tudo', 'bem', 'de', 'nada',
    'gustavo', 'e', 'muito', 'demais', 'entao', 'ah', 'kkk', 'kkkk', 'rs'];
  v_bruto text := regexp_replace(coalesce(p_texto, ''), '^\s+|\s+$', '', 'g');
  v_sem_emoji text;
  v_palavras text[];
  v_lista text;
begin
  if v_bruto = '' or strpos(v_bruto, '?') > 0 then
    return false;
  end if;
  -- Áudio (transcrito ou não), foto, arquivo e mensagem vazia: o conteúdo não se lê aqui.
  if v_bruto ~ '^\s*(?:🎤|\[(?:audio|image|video|document|conteúdo vazio)\])' then
    return false;
  end if;
  v_sem_emoji := regexp_replace(v_bruto, '[\U0001F000-\U0001FAFF⌀-⏿☀-➿⬀-⯿️‍]', ' ', 'g');
  v_palavras := string_to_array(btrim(regexp_replace(
                  translate(lower(v_sem_emoji), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
                  '[^a-z]+', ' ', 'g')), ' ');
  if coalesce(cardinality(v_palavras), 0) = 0 then
    -- Só emoji (👍, 🙏): agradecimento. Só pontuação ("..."): não.
    return regexp_replace(v_sem_emoji, '^\s+|\s+$', '', 'g') <> v_bruto;
  end if;
  if v_palavras <@ c_lista then
    return true;
  end if;
  -- Encerra dizendo que ELE vai agir ("Perfeito, vou dar sequencia"). "Fico no aguardo" não entra.
  v_lista := array_to_string(c_lista, '|');
  return array_to_string(v_palavras, ' ') ~ (
    '^(?:(?:' || v_lista || ') )*(?:'
    || '(?:ja )?vou dar (?:sequencia|seguimento|andamento)(?: (?:aqui|no pedido|nisso))?'
    || '|(?:ja )?(?:estou|to|tou) dando (?:sequencia|seguimento|andamento)'
    || '|pode deixar(?: comigo)?'
    || '|(?:ja )?(?:vou providenciar|providencio|estou providenciando)'
    || '|(?:assim que (?:sair|tiver|chegar|ficar pronto) )?(?:eu )?(?:te|lhe) (?:aviso|retorno|confirmo)'
    || ')(?: (?:' || v_lista || '))*$');
end;
$$;

comment on function public._retorno_so_agradecimento(text) is
  'Retorno F1 (P2): porte de pareceSoAgradecimento (palavras.ts): só cumprimento, agradecimento, confirmação ou emoji, sem pergunta; ou o "vou dar sequência" de quem encerra agindo.';

revoke all on function public._retorno_so_agradecimento(text) from public, anon, authenticated;

-- contatoEncerrou (contato-encerrou.ts:26-57): COM_OUTRO e SEM_INTERESSE copiados, com a flag i sobre o
-- texto cru. A pergunta DEPOIS da frase reabre, olhando o 1º casamento de cada regra, como o exec do TS.
-- Nenhum casamento das duas regras contém "?", então o fim do casamento (que no PostgreSQL pode ser o mais
-- longo, e no JavaScript o do 1º caminho) não muda a resposta.
create or replace function public._retorno_encerrou(p_texto text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  c_ja_decidiu constant text :=
    '(?:fech(?:ei|amos|ou|aram|ando)|contrat(?:ei|amos|ou|aram|ando)|opt(?:ei|amos|ou|aram|ando)|escolh(?:i|emos|eu|eram|endo)|compr(?:ei|amos|ou)|resolv(?:i|emos|eu)|fiz(?:emos)?|fez)';
  c_outro constant text :=
    '(?:outr[oa]s?(?:\s+(?:empresa|oficina|pessoa|t[eé]cnico|profissional|fornecedor|firma|loja|marina|estaleiro|equipe|cara|rapaz|mo[cç]o)s?\y|(?=\s*(?:$|[.!?,;)]|e\y|mas\y|obrigad)))|concorr[eê]n(?:te|cia))';
  c_alvo constant text :=
    '(?:servi[cç]o|or[cç]amento|conserto|reparo|instala[cç][aã]o|proposta|trabalho)';
  v_t text := regexp_replace(coalesce(p_texto, ''), '^\s+|\s+$', '', 'g');
  v_re text;
  v_fim integer;
begin
  if v_t = '' then
    return false;
  end if;
  foreach v_re in array array[
    -- COM_OUTRO: já decidiu (passado ou "acabei fechando") com outro alguém.
    '\y' || c_ja_decidiu || '\s+[^.!?\n]{0,25}?\ycom\s+(?:o\s+|a\s+|uma?\s+)?' || c_outro,
    -- SEM_INTERESSE: "não tenho mais interesse", "não quero mais" (no fim ou do serviço), "desisti do orçamento".
    '\yn[aã]o\s+(?:tenho|temos)\s+mais\s+interesse\y'
      || '|\yn[aã]o\s+(?:quero|queremos|vou\s+querer|preciso|precisamos)\s+mais(?=\s*(?:$|[.!?,;)]|obrigad|valeu|n[aã]o\y|(?:d?[oa]s?|esse|essa|este|esta)\s+' || c_alvo || '))'
      || '|\ydesisti(?:mos)?\s+d[oa]\s+' || c_alvo || '\y'
  ] loop
    v_fim := regexp_instr(v_t, v_re, 1, 1, 1, 'i');
    if v_fim > 0 and strpos(substr(v_t, v_fim), '?') = 0 then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

comment on function public._retorno_encerrou(text) is
  'Retorno F1 (P2): porte de contatoEncerrou (contato-encerrou.ts): fechou com outra empresa ou desistiu do serviço; pergunta depois da frase reabre.';

revoke all on function public._retorno_encerrou(text) from public, anon, authenticated;

-- ── 3. Os sinais de uma mensagem ────────────────────────────────────────────────────────────────────

-- Todas as chaves são booleanas, menos bem_palavra, modelo e ano (texto ou nulo). b = texto de busca;
-- t = o texto cru (só para "?", o modelo literal e a marca do site).
create or replace function public._retorno_sinais(p_texto text, p_nome text default null)
returns jsonb
language sql
immutable
set search_path = public
as $$
  with e as (
    select coalesce(p_texto, '') as t,
           public._retorno_busca(p_texto) as b,
           -- serviço (B.2, com os plurais)
           '\y(orcamento|orcamentos|orcar|instalar|instalacao|instalacoes|trocar|troca|bateria|baterias|inversor|inversores|placa solar|placas solares|painel solar|paineis solares|energia solar|gerador|eletrica|eletrico|ar condicionado|bomba|carregador|tomada|tomadas|chicote)\y'::text as re_servico,
           -- bem: EMBARCACOES e VEICULOS de unidade.ts, mais "carro" e os modelos (R2 P1)
           '\y(barco|lancha|veleiro|catamara|embarcacao|jet ski|moto aquatica|escuna|traineira|bote|motorhome|motor home|trailer|camper|van|onibus|caminhao|picape|automovel|veiculo|carro|ducato|sprinter|iveco|daily|master|boxer)\y'::text as re_bem
  ), s as (
    select e.t, e.b,
           e.b ~ e.re_servico as servico,
           -- o serviço que sobra sem orcamento/orcamentos/orcar: a necessidade foi dita
           regexp_replace(e.b, '\y(orcamento|orcamentos|orcar)\y', ' ', 'g') ~ e.re_servico as servico_dito,
           e.b ~ e.re_bem as bem,
           replace((regexp_match(e.b, e.re_bem))[1], 'motor home', 'motorhome') as bem_palavra,
           (regexp_match(e.t, '\y(ducato|sprinter|iveco|daily|master|boxer)\y', 'i'))[1] as modelo,
           (regexp_match(e.b, '\y(19[5-9][0-9]|20[0-4][0-9])\y'))[1] as ano,
           -- PEDE_PRECO (palavras.ts:11-21), alternativa por alternativa, sem o corte de 120
           e.b ~ ('\y(?:'
             || 'quanto (?:custa|custaria|fica|ficaria|sai|sairia|cobra|cobram|cobraria|seria|e|vai ficar|vale)'
             || '|(?:qual|quais) (?:e |seria |sera |o |a |os |as )*(?:valor|valores|preco|precos)'
             || '|(?:passa|passe|manda|mande|envia|envie|faz|faca|ve) (?:me |pra mim |para mim )?(?:o |um |uma |a |os )?(?:orcamento|orcamentos|preco|valor|proposta|cotacao)'
             || '|(?:pode|podes|poderia|consegue|conseguiria|tem como|teria como|da pra|da para|favor|por favor) (?:me )?(?:passar|mandar|enviar|fazer|ver) (?:pra mim |para mim )?(?:o |um |uma |a |os )?(?:orcamento|orcamentos|preco|valor|proposta|cotacao)'
             || '|(?:preciso|precisava|precisamos|gostaria|queria|quero) (?:de )?(?:um |uma |o |a )?(?:orcamento|preco|valor|cotacao|proposta)'
             || '|orcar|orcamento pra|orcamento para'
             || '|(?:quero|vamos|podemos|queremos|quer) fechar'
             || ')\y') as pede_preco,
           public._e_pedido_de_parar(p_texto) as parar
      from e
  )
  select jsonb_build_object(
    'servico', s.servico,
    'servico_generico', s.servico and not s.servico_dito,
    'bem', s.bem,
    'bem_palavra', s.bem_palavra,
    'modelo', s.modelo,
    'ano', s.ano,
    'pede_preco', s.pede_preco,
    -- nunca decide sozinho: só vale com serviço e bem (L7, _retorno_pedido_de_servico)
    'pedido', s.pede_preco or s.t ~ '\?'
              or s.b ~ '\y(preciso|precisava|precisamos|quero|queria|queremos|gostaria|gostariamos|voces fazem|vcs fazem|voce faz|vc faz|fazem|consegue|conseguem|conseguiria|pode|podem|poderia|tem como|teria como|da pra|da para|orcar|orcamento|interessado|interessada|interesse)\y',
    'vendedor', public._retorno_parece_vendedor(p_nome, p_texto),
    'so_agradecimento', public._retorno_so_agradecimento(p_texto),
    'encerrou', public._retorno_encerrou(p_texto),
    'saudacao', s.b ~ '^((oi+|ola|opa|bom dia|boa tarde|boa noite|boa|tudo bem|tudo bom|e ai|eai|como vai|gustavo|amigo|amiga|pessoal|hbr) ?)+$',
    -- "hoje" sozinho não é pressa (R1-09): por isso não se usa o COM_PRESSA de palavras.ts
    'pressa', s.b ~ '\y(urgente|urgencia|emergencia|o quanto antes|o mais rapido|mais rapido possivel|ainda hoje)\y'
              or (s.b ~ '\yamanha\y' and s.b ~ '\y(retirar|buscar|pegar|viajar|viagem|embarcar|sair)\y'),
    'urgente', s.b ~ '^(e )?(muito )?urgente( (por favor|pf|pfv))?$',
    'risco', s.b ~ '\y(fumaca|fogo|pegando fogo|queimou|queimado|cheiro de queimado|agua entrando|entrando agua|entrou agua)\y',
    'quer_dono', s.b ~ '\y(falar|conversar) com (o )?(gustavo|dono|responsavel|alguem|uma pessoa|atendente|humano)\y',
    -- lista inicial [I], conservadora; a sombra mede
    'reclamacao', s.b ~ '\y(reclamacao|reclamar|absurdo|pessimo|pessima|descaso|vergonha|procon|advogado|processar|insatisfeito|insatisfeita|decepcionado|decepcionada|ninguem responde|ninguem me responde|voces nao respondem|nao me respondem|mesmo problema de novo)\y',
    'lgpd', s.b ~ '\y(lgpd|meus dados|dados pessoais|apagar meus|excluir meus|remover meus)\y',
    'parar', s.parar,
    -- só as formas claras da regra larga (reply-router.ts:31); não grava opt-out, vai ao dono
    'parar_largo', not s.parar
                   and s.b ~ '(\ypara|\ypare|\yparar) de (me )?(mandar|enviar)|nao (quero|desejo) (mais )?(receber|mensagens)|nao me mand(a|e|em) (mais|mensage|msg)|descadastr|sair da lista|remover meu (numero|contato)|me tir(a|e) (dessa|desta|da) lista',
    'site', s.t ~* 'vim pelo site da hbr systems',
    'audio_pendente', btrim(s.t) = '[audio]',
    'midia_sem_legenda', btrim(s.t) ~ '^\[(image|video|document)\]$')
  from s;
$$;

comment on function public._retorno_sinais(text, text) is
  'Retorno F1 (P2): os sinais de texto de uma mensagem (serviço, bem, pedido, vendedor, agradecimento, encerrou, saudação, pressa, URGENTE, risco, quer o dono, reclamação, LGPD, PARAR exato e por extenso, site, áudio e mídia). Sem IA; o pedido nunca decide sozinho.';

revoke all on function public._retorno_sinais(text, text) from public, anon, authenticated;

-- A resposta ao "Como posso te chamar?" (o P5 só chama depois que a coleta 2 saiu enviada). Estrita de
-- propósito: 1 ou 2 palavras, cada uma com inicial maiúscula, fora da lista de palavras comuns e sem
-- serviço, bem ou saudação. "ana" minúsculo, "Ducato 2019" e "Fica em Itajaí" dão nulo: falha fecha, e
-- o dono pergunta. Nunca usa o nome do perfil do WhatsApp.
create or replace function public._retorno_nome_dito(p_texto text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  c_comuns constant text[] := array[
    'pode', 'ser', 'sim', 'nao', 'ok', 'oi', 'ola', 'bom', 'boa', 'dia', 'tarde', 'noite', 'obrigado', 'obrigada', 'valeu',
    'fica', 'aqui', 'ai', 'alguem', 'quero', 'preciso', 'tem', 'tudo', 'bem', 'beleza', 'claro', 'certo', 'isso', 'esse',
    'essa', 'ele', 'ela', 'em', 'no', 'na', 'de', 'do', 'da', 'cliente', 'gustavo', 'hbr'];
  v_resto text;
  v_s jsonb;
begin
  v_resto := regexp_replace(coalesce(p_texto, ''), '^\s+|\s+$', '', 'g');
  v_resto := regexp_replace(v_resto,
               '^(pode me chamar de|me chama de|me chamo|meu nome é|meu nome e|aqui é o|aqui é a|sou o|sou a|sou|é o|é a)\s+',
               '', 'i');
  v_resto := regexp_replace(v_resto, '[\s.!]+$', '');
  if v_resto !~ '^[A-ZÀ-ÖØ-Þ][a-zß-öø-ÿ]{1,19}( [A-ZÀ-ÖØ-Þ][a-zß-öø-ÿ]{1,19})?$' then
    return null;
  end if;
  if string_to_array(public._retorno_busca(v_resto), ' ') && c_comuns then
    return null;
  end if;
  v_s := public._retorno_sinais(v_resto);
  if (v_s ->> 'servico')::boolean or (v_s ->> 'bem')::boolean or (v_s ->> 'saudacao')::boolean then
    return null;
  end if;
  return v_resto;
end;
$$;

comment on function public._retorno_nome_dito(text) is
  'Retorno F1 (P2): o nome dito em resposta ao "Como posso te chamar?", como foi escrito (1 ou 2 palavras com inicial maiúscula, fora das palavras comuns, sem serviço, bem ou saudação); senão nulo.';

revoke all on function public._retorno_nome_dito(text) from public, anon, authenticated;

-- ── 4. A hora real ──────────────────────────────────────────────────────────────────────────────────

-- hora_real (F0b); sem ela, o messageTimestamp numérico do webhook (10 dígitos: segundos, como em
-- retorno_medidas_base; outro formato nunca derruba); sem ele, occurred_at.
create or replace function public._retorno_hora_real(m public.whatsapp_messages)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select coalesce(
    m.hora_real,
    case when jsonb_typeof(m.raw_payload -> 'data' -> 'messageTimestamp') = 'number'
              and (m.raw_payload -> 'data' ->> 'messageTimestamp') ~ '^[0-9]{10}$'
         then to_timestamp((m.raw_payload -> 'data' ->> 'messageTimestamp')::numeric)
    end,
    m.occurred_at);
$$;

comment on function public._retorno_hora_real(public.whatsapp_messages) is
  'Retorno F1 (P2): a hora real de uma mensagem: hora_real; sem ela, o messageTimestamp do raw_payload; sem ele, occurred_at (a ordem de retorno_medidas_base).';

revoke all on function public._retorno_hora_real(public.whatsapp_messages) from public, anon, authenticated;

-- ── 5. Triagem que lê a conversa (sem olhar o futuro) ───────────────────────────────────────────────
--
-- As janelas são pela hora real; o limite em occurred_at (a hora de gravação) é o que impede olhar o
-- futuro. A margem de 10 min em occurred_at só deixa o índice por chave cortar a busca: a gravação nunca
-- vem antes do envio (occurred_at >= hora real).

-- "Nunca houve saída humana a esse número" (R1-08) antes de p_antes. Linhas antigas sem saida_humana
-- são classificadas na hora pela mesma regra (_saida_e_humana). Usa retorno_wa_enviadas_por_chave (P1).
-- Sem chave: falso (não é número novo; falha fecha). Sem p_antes: olha tudo.
create or replace function public._retorno_numero_novo(p_chave text, p_antes timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_chave is not null
     and not exists (
       select 1 from public.whatsapp_messages m
        where public._agenda_chave_telefone(m.phone_normalized) = p_chave
          and m.direction = 'outbound'
          and m.occurred_at < coalesce(p_antes, 'infinity'::timestamptz)
          and coalesce(m.saida_humana, public._saida_e_humana(m.direction, m.raw_payload, m.sent_by)));
$$;

comment on function public._retorno_numero_novo(text, timestamptz) is
  'Retorno F1 (P2, R1-08): nunca houve saída humana (_saida_e_humana) à chave antes de p_antes. Sem chave: falso.';

revoke all on function public._retorno_numero_novo(text, timestamptz) from public, anon, authenticated;

-- A recebida que chega até robo_resposta_s (5 s) depois de uma enviada AUTOMÁTICA à mesma chave (B.2:
-- "2 respostas em < 5 s"): a mensagem de ausência do WhatsApp Business ou outro robô respondendo ao
-- recibo. Vale por mensagem; nunca marca o número inteiro. Só enviadas gravadas até a recebida.
-- Compara pelo SEGUNDO (desvio da spec P2.1, revisão adversarial): os dois lados têm relógios
-- diferentes. A enviada do whatsapp-send não traz "data", então o gatilho da F0b grava hora_real = now(),
-- com microssegundos e só depois do sucesso no provedor; a recebida tem hora_real = messageTimestamp,
-- cortado no segundo. Enviada gravada às 10:00:00.700 e ausência com messageTimestamp 10:00:00 é robô.
-- Fica de fora (levado à coordenação): a resposta de robô cujo webhook grava ANTES da enviada; o limite
-- em occurred_at (ninguém olha o futuro) a exclui.
create or replace function public._retorno_resposta_de_robo(p_msg uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.whatsapp_messages;
  v_real timestamptz;
  v_janela interval;
begin
  select * into m from public.whatsapp_messages w where w.id = p_msg;
  if not found or m.direction is distinct from 'inbound' then
    return false;
  end if;
  v_real := public._retorno_hora_real(m);
  v_janela := make_interval(secs => coalesce((public._retorno_cfg()).robo_resposta_s, 5));
  return exists (
    select 1 from public.whatsapp_messages s
     where public._agenda_chave_telefone(s.phone_normalized) = public._agenda_chave_telefone(m.phone_normalized)
       and s.direction = 'outbound'
       and s.occurred_at <= m.occurred_at
       and s.occurred_at >= v_real - v_janela - interval '10 minutes'
       and not coalesce(s.saida_humana, public._saida_e_humana(s.direction, s.raw_payload, s.sent_by))
       and date_trunc('second', public._retorno_hora_real(s)) between date_trunc('second', v_real) - v_janela and v_real);
end;
$$;

comment on function public._retorno_resposta_de_robo(uuid) is
  'Retorno F1 (P2, B.2): a recebida chegou até robo_resposta_s depois de uma enviada automática à mesma chave (resposta de robô), comparando pelo segundo. Vale por mensagem.';

revoke all on function public._retorno_resposta_de_robo(uuid) from public, anon, authenticated;

-- A mensagem pede resposta? {"pede": bool, "motivo": text|null}, na ordem da spec (P2.1). PARAR e PARAR
-- por extenso não pedem (o P5 trata à parte). A conversa viva é a da agenda
-- (agenda_config.cliente_conversa_viva_min, uma fonte só; R1-30). A saudação que abre conversa pede (B.3):
-- "Boa tarde" sem nenhuma mensagem da chave nas 4 h antes.
create or replace function public._retorno_pede_resposta(p_msg uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.whatsapp_messages;
  v_s jsonb;
  v_chave text;
  v_real timestamptz;
  v_viva interval;
begin
  select * into m from public.whatsapp_messages w where w.id = p_msg;
  -- 1. Só recebida de conversa (sem grupo, sem lista de transmissão).
  if not found or m.direction is distinct from 'inbound' or coalesce(m.phone_normalized, '') ~ '@'
     or coalesce(m.is_broadcast, false) then
    return jsonb_build_object('pede', false, 'motivo', 'nao_e_conversa');
  end if;
  -- 2. Figurinha e reação.
  if m.message_type = 'sticker'
     or coalesce(m.raw_payload -> 'data' ->> 'messageType', '') in ('reactionMessage', 'stickerMessage', 'protocolMessage',
                                                                   'secretEncryptedMessage', 'placeholderMessage') then
    return jsonb_build_object('pede', false, 'motivo', 'figurinha_ou_reacao');
  end if;
  -- 3. Robô: o detector da F0b (modelo, botões, lista, interativa, texto longo repetido) e, 3b, a
  --    resposta em até 5 s a uma enviada automática.
  if public._retorno_e_automatico(m.phone_normalized, m.body, m.raw_payload, m.occurred_at)
     or public._retorno_resposta_de_robo(m.id) then
    return jsonb_build_object('pede', false, 'motivo', 'robo');
  end if;
  v_s := public._retorno_sinais(m.body);
  -- 4. PARAR (a confirmação é à parte) e, 4b, PARAR por extenso (sem resposta automática; vai ao dono).
  if (v_s ->> 'parar')::boolean then
    return jsonb_build_object('pede', false, 'motivo', 'parar');
  end if;
  if (v_s ->> 'parar_largo')::boolean then
    return jsonb_build_object('pede', false, 'motivo', 'parar_largo');
  end if;
  v_chave := public._agenda_chave_telefone(m.phone_normalized);
  v_real := public._retorno_hora_real(m);
  -- 5. Foto, vídeo ou arquivo sem legenda no meio de conversa viva (qualquer lado). O envelope de
  --    álbum, localização e contato chega como '[conteúdo vazio]' (message_type 'text') e conta como
  --    mídia sem legenda (desvio da spec P2.1, revisão adversarial): 16 dos 17 álbuns reais vieram
  --    seguidos de fotos em até 2 min, 14 em conversa viva. Fora de conversa viva o envelope segue as regras seguintes e pede
  --    resposta, como a 1ª foto pediria (por isso não entra no passo 2).
  if (v_s ->> 'midia_sem_legenda')::boolean
     or coalesce(m.raw_payload -> 'data' ->> 'messageType', '') in ('albumMessage', 'locationMessage', 'contactMessage',
                                                                   'contactsArrayMessage') then
    begin
      v_viva := make_interval(mins => coalesce((public._agenda_cfg()).cliente_conversa_viva_min, 60));
    exception when others then
      v_viva := interval '60 minutes';   -- agenda_config ausente: o valor de hoje
    end;
    if exists (select 1 from public.whatsapp_messages o
                where public._agenda_chave_telefone(o.phone_normalized) = v_chave
                  and o.id <> m.id
                  and o.occurred_at <= m.occurred_at
                  and o.occurred_at >= v_real - v_viva - interval '10 minutes'
                  and public._retorno_hora_real(o) between v_real - v_viva and v_real) then
      return jsonb_build_object('pede', false, 'motivo', 'midia_em_conversa_viva');
    end if;
  end if;
  -- 6. Só agradecimento, salvo a saudação que abre conversa (nenhuma mensagem da chave nas 4 h antes).
  if (v_s ->> 'so_agradecimento')::boolean
     and not ((v_s ->> 'saudacao')::boolean
              and not exists (select 1 from public.whatsapp_messages o
                               where public._agenda_chave_telefone(o.phone_normalized) = v_chave
                                 and o.id <> m.id
                                 and o.occurred_at <= m.occurred_at
                                 and o.occurred_at >= v_real - interval '4 hours 10 minutes'
                                 and public._retorno_hora_real(o) between v_real - interval '4 hours' and v_real)) then
    return jsonb_build_object('pede', false, 'motivo', 'agradecimento');
  end if;
  -- 7. Fechou com outro ou desistiu.
  if (v_s ->> 'encerrou')::boolean then
    return jsonb_build_object('pede', false, 'motivo', 'encerrou');
  end if;
  return jsonb_build_object('pede', true, 'motivo', null);
end;
$$;

comment on function public._retorno_pede_resposta(uuid) is
  'Retorno F1 (P2): a recebida pede resposta? {"pede", "motivo"}: nao_e_conversa, figurinha_ou_reacao, robo, parar, parar_largo, midia_em_conversa_viva (inclui o envelope de álbum, localização e contato), agradecimento, encerrou ou nulo. Só lê mensagens gravadas até a própria.';

revoke all on function public._retorno_pede_resposta(uuid) from public, anon, authenticated;

-- Os sinais somados (OU) de todas as recebidas da chave com hora real entre p_desde e
-- least(p_ate, p_desde + 24 h), gravadas até p_ate (B.2: "em qualquer mensagem do número nas primeiras
-- 24 h"). pedido = (site ou (serviço e bem e pedido)) e não vendedor. pedido_literal = a 1ª mensagem com
-- serviço, cortada em 300 caracteres (vai só para a coleta e para o dono, nunca ao cliente).
create or replace function public._retorno_pedido_de_servico(p_chave text, p_desde timestamptz, p_ate timestamptz,
                                                             p_nome text default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with msgs as (
    select m.id, m.body, m.occurred_at, public._retorno_hora_real(m) as real,
           public._retorno_sinais(m.body, p_nome) as s
      from public.whatsapp_messages m
     where public._agenda_chave_telefone(m.phone_normalized) = p_chave
       and m.direction = 'inbound'
       and m.occurred_at <= p_ate
       and m.occurred_at >= p_desde - interval '10 minutes'
       and public._retorno_hora_real(m) between p_desde and least(p_ate, p_desde + interval '24 hours')
  ), soma as (
    select coalesce(bool_or((s ->> 'servico')::boolean), false) as servico,
           coalesce(bool_and((s ->> 'servico_generico')::boolean or not (s ->> 'servico')::boolean), true) as so_generico,
           coalesce(bool_or((s ->> 'bem')::boolean), false) as bem,
           (array_agg(s ->> 'bem_palavra' order by real, occurred_at, id) filter (where s ->> 'bem_palavra' is not null))[1] as bem_palavra,
           (array_agg(s ->> 'modelo' order by real, occurred_at, id) filter (where s ->> 'modelo' is not null))[1] as modelo,
           (array_agg(s ->> 'ano' order by real, occurred_at, id) filter (where s ->> 'ano' is not null))[1] as ano,
           coalesce(bool_or((s ->> 'pedido')::boolean), false) as pedido,
           coalesce(bool_or((s ->> 'vendedor')::boolean), false) as vendedor,
           coalesce(bool_or((s ->> 'site')::boolean), false) as site,
           (array_agg(left(body, 300) order by real, occurred_at, id) filter (where (s ->> 'servico')::boolean))[1] as pedido_literal,
           coalesce(jsonb_agg(id order by real, occurred_at, id), '[]'::jsonb) as ids
      from msgs
  )
  select jsonb_build_object(
    'pedido', (soma.site or (soma.servico and soma.bem and soma.pedido)) and not soma.vendedor,
    'servico', soma.servico,
    'servico_generico', soma.servico and soma.so_generico,
    'bem', soma.bem,
    'bem_palavra', soma.bem_palavra,
    'modelo', soma.modelo,
    'ano', soma.ano,
    'vendedor', soma.vendedor,
    'site', soma.site,
    'pedido_literal', soma.pedido_literal,
    'msgs', soma.ids)
  from soma;
$$;

comment on function public._retorno_pedido_de_servico(text, timestamptz, timestamptz, text) is
  'Retorno F1 (P2, B.2): pedido de serviço nas primeiras 24 h do número: (site ou (serviço e bem e pedido)) e não vendedor, somando todas as recebidas gravadas até p_ate.';

revoke all on function public._retorno_pedido_de_servico(text, timestamptz, timestamptz, text) from public, anon, authenticated;
