-- ═══════════════════════════════════════════════════════════════════════════
-- Os blocos da categoria Estrutural
--
-- Definição dada pelo dono (03/08): "trabalhar, mexer, preparar ou melhorar a
-- parte que faz parte do reforço estrutural — antepara, longarina, chassi, ou
-- qualquer peça de uma estrutura que reforça e suporta esforços mecânicos."
--
-- ACHADO AO ESCREVER: nenhum dos 4 serviços hoje marcados como `estrutural` é
-- estrutural por essa definição. São "isolação térmica de chicote" (elétrico),
-- "tomada móvel aéreo cozinha" (elétrico), "acabamento de painel em acrílico" e
-- "lentes e aros de relógios Volvo" (acabamento). O classificador leu as
-- palavras acabamento/teto/painel e concluiu estrutura — mas marcenaria e
-- acabamento não suportam esforço nenhum.
--
-- Isso importa porque estes blocos são pesados: mandam escorar antes de soltar,
-- bater na peça para ouvir o núcleo e selar cada furo. Aplicá-los a um reparo
-- de lente de relógio seria ruído, e ruído é como o técnico aprende a pular
-- bloco de segurança. Por isso a migration termina devolvendo os quatro para a
-- fila de revisão do dono, em vez de eu decidir sozinho onde eles ficam.
--
-- O QUE ORIENTOU O CONTEÚDO (prática consolidada de estrutura náutica, sem
-- inventar número):
--   · elemento estrutural é PORTANTE: enfraquecer sem escorar transfere carga
--     para onde ninguém calculou;
--   · furo em antepara ou longarina de núcleo composto deixa água entrar, e a
--     madeira apodrece por dentro enquanto a casca de fibra continua com cara
--     de nova — por isso todo furo é selado, sempre;
--   · percussão (bater e ouvir) revela núcleo solto ou podre antes de furar;
--   · antepara estanque é compartimentação: furá-la sem restaurar a vedação
--     muda o comportamento do barco em alagamento;
--   · carga concentrada em painel fino pede chapa de distribuição.
--
-- Dimensão de chapa, torque e especificação de fixação: "conferir no projeto ou
-- no manual". Nada disso foi inventado aqui.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from public.service_step_blocks where applies_to_system = 'estrutural') then
    raise notice 'A categoria estrutural já tem blocos — nada inserido.';
    return;
  end if;

  insert into public.service_step_blocks
    (block_role, applies_to_system, applies_to_verb, seq, title, detail, kind, mode,
     standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
     origin, active)
  values

  -- ── ABERTURA ─────────────────────────────────────────────────────────────
  ('abertura','estrutural',null,1,
   'Confirmar se a peça é estrutural ou só acabamento',
   'Antepara, longarina, caverna, chassi e berço suportam esforço; forro, painel e armário não. A pergunta muda tudo o que vem depois — na dúvida, tratar como estrutural.',
   'check','read_do',15,true,false,null,null,'ai',false),
  ('abertura','estrutural',null,2,
   'Bater na peça e ouvir antes de furar ou cortar',
   'Som seco e cheio é núcleo firme; som oco ou "morto" é núcleo solto, molhado ou apodrecido. A casca de fibra continua com cara de nova por cima de madeira podre — só a percussão denuncia.',
   'check','read_do',15,true,false,null,null,'ai',false),
  ('abertura','estrutural',null,3,
   'Verificar o que passa dentro, atrás e do outro lado',
   'Chicote, tubulação, linha de gás, tanque e reforço colado costumam correr rente à estrutura. Furo às cegas em antepara atinge o que não se vê — e o estrago aparece semanas depois.',
   'safety','read_do',15,true,false,null,null,'ai',false),
  ('abertura','estrutural',null,4,
   'Escorar e apoiar antes de soltar qualquer elemento portante',
   'Enfraquecer um elemento que sustenta carga joga o esforço para onde ninguém calculou. Escorar antes de cortar, nunca durante.',
   'safety','read_do',25,true,true,null,null,'ai',false),
  ('abertura','estrutural',null,5,
   'Confirmar se a peça é estanque ou divide compartimento',
   'Antepara estanque é o que segura a água num alagamento. Furá-la muda o comportamento do barco na pior hora — se for o caso, a vedação tem que ser restaurada no fechamento, e isso entra no orçamento agora.',
   'check','read_do',10,true,false,null,null,'ai',false),
  ('abertura','estrutural',null,6,
   'Fotografar a peça e a região inteira antes de mexer',
   'Estrutura é o que ninguém vê depois que o forro fecha. Estas fotos são a única memória do que havia antes.',
   'evidence','read_do',10,true,true,null,null,'ai',false),

  -- ── FECHAMENTO ───────────────────────────────────────────────────────────
  ('fechamento','estrutural',null,1,
   'Selar todo furo aberto, inclusive os de teste',
   'Furo em núcleo composto é porta de entrada de água: a madeira apodrece por dentro e ninguém percebe até a peça ceder. Selar é parte do serviço, não acabamento — inclusive o furo-piloto que não foi usado.',
   'safety','read_do',25,true,true,null,null,'ai',false),
  ('fechamento','estrutural',null,2,
   'Conferir a fixação e a distribuição de carga',
   'Carga concentrada em painel fino arranca o painel. Chapa de distribuição, arruela larga ou reforço: dimensão e especificação vêm do projeto ou do manual do equipamento — anotar o torque usado.',
   'safety','read_do',20,true,false,'torque_nm','N·m','ai',false),
  ('fechamento','estrutural',null,3,
   'Restaurar a vedação da antepara estanque, se for o caso',
   'Passagem de cabo ou tubo em antepara estanque exige passa-muro vedado. Sem isso, o compartimento deixou de ser estanque e ninguém foi avisado.',
   'safety','read_do',20,true,true,null,null,'ai',false),
  ('fechamento','estrutural',null,4,
   'Retirar escoras e carregar o esforço aos poucos',
   'Soltar as escoras devagar, observando. Se a peça acomodar, ceder ou estalar, é para parar — não para apertar mais.',
   'check','read_do',20,true,false,null,null,'ai',false),
  ('fechamento','estrutural',null,5,
   'Testar na condição real de esforço',
   'Equipamento pesado fixado: aplicar a carga e verificar. Em barco, o esforço de verdade vem do mar batendo; em motorhome, da estrada. O que não se testa parado, se descobre em movimento.',
   'check','read_do',20,true,false,null,null,'ai',false),
  ('fechamento','estrutural',null,6,
   'Fotografar o serviço concluído antes de fechar o acesso',
   'Depois que o forro fecha, só resta a foto. É ela que responde daqui a dois anos como a peça foi reforçada.',
   'evidence','read_do',10,true,true,null,null,'ai',false);

  raise notice 'Blocos de estrutural: % passos.',
    (select count(*) from public.service_step_blocks where applies_to_system = 'estrutural');
end $$;

-- ─── Os quatro que não são estruturais voltam para a fila do dono ───────────
-- Baixar a confiança é o suficiente: eles reaparecem em "Classificação a
-- conferir" com o seletor ao lado. Quem decide para onde vão é ele, não eu —
-- só o alerto de que ali não é o lugar.
update public.services set
  classification_confidence = 0.4,
  classified_by = 'ai',
  classified_at = now()
where active and service_system = 'estrutural';
