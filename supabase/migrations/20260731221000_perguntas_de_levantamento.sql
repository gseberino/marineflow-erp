-- ═══════════════════════════════════════════════════════════════════════════
-- Levantamento — os 16 conjuntos de perguntas (7 sistemas + 9 verbos)
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 3-bis
--
-- 77 perguntas escritas uma vez, cobrindo os 261 serviços por composição, no
-- lugar de 261 questionários. O compositor corta em 9 por levantamento (P16):
-- mais que isso ninguém responde em campo, então a ordem por impacto no preço
-- é o que decide quais sobrevivem.
--
-- TUDO como origin='ai' + active=false: a trava do banco
-- (service_survey_templates_ai_needs_approval) impede pergunta de IA ativa sem
-- assinatura, igual aos blocos de roteiro.
--
-- Critério de `ask_remotely` (decisão 8 do plano): só é marcada a pergunta que
-- um leigo responde com uma foto ou uma informação que ele tem à mão. Nada que
-- exija julgamento técnico — cliente respondendo errado sobre bitola ou estado
-- de mangueira é pior que não perguntar.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from public.service_survey_templates) then
    raise notice 'service_survey_templates já tem conteúdo — nada inserido.';
    return;
  end if;

  insert into public.service_survey_templates
    (service_id, applies_to_system, applies_to_verb, seq, question, help_text,
     answer_type, price_impact, ask_remotely, origin, active)
  values

  -- ══ SISTEMAS ═════════════════════════════════════════════════════════════

  -- ── Elétrico DC — o que a HBR mais faz ──────────────────────────────────
  (null,'eletrico_dc',null,1,'Qual o consumo diário e a autonomia que o cliente espera?',
   'Geladeira, ar, bomba, tomadas — e quantos dias fora da tomada. É o número que dimensiona o banco inteiro; errar aqui erra o orçamento todo.',
   'texto','alto',false,'ai',false),
  (null,'eletrico_dc',null,2,'Onde entra o banco de baterias? Há espaço, ventilação e como fixar?',
   'Medir o vão e olhar a fixação. Banco em veículo em movimento precisa de contenção mecânica.',
   'texto','alto',false,'ai',false),
  (null,'eletrico_dc',null,3,'Foto do quadro elétrico atual e do compartimento onde entra o banco',
   'Abrir a tampa e fotografar de frente, com luz. Duas fotos resolvem meia hora de perguntas.',
   'foto','alto',true,'ai',false),
  (null,'eletrico_dc',null,4,'Qual a distância entre o banco, o inversor e o quadro?',
   'Em metros. Define bitola de cabo e é o item que mais estoura orçamento de material quando é chutado.',
   'medida','alto',false,'ai',false),
  (null,'eletrico_dc',null,5,'O alternador vai carregar o banco? Qual o modelo, e já existe DC-DC?',
   null,'texto','medio',false,'ai',false),
  (null,'eletrico_dc',null,6,'Já existe painel solar, ou entra agora?',
   'Se existe: quantos, qual potência e se o controlador é MPPT.',
   'texto','medio',false,'ai',false),
  (null,'eletrico_dc',null,7,'O que existe hoje: chumbo, gel, AGM ou lítio? Qual a idade?',
   'Bateria velha de outra química muda a estratégia de troca e o que dá para reaproveitar.',
   'escolha','medio',false,'ai',false),
  (null,'eletrico_dc',null,8,'Há tomada de cais ou 110/220V disponível no local do serviço?',
   'Sem energia no local, o serviço precisa de gerador — e isso é custo.',
   'sim_nao','baixo',true,'ai',false),

  -- ── Elétrico AC — poucos serviços, o maior risco ────────────────────────
  (null,'eletrico_ac',null,1,'De onde vem o AC: cabo de cais, gerador, inversor — ou mais de um?',
   'Marcar todas as fontes. Quadro alimentado por mais de uma fonte muda o serviço e o procedimento de segurança.',
   'texto','alto',false,'ai',false),
  (null,'eletrico_ac',null,2,'Foto do quadro AC aberto e do disjuntor geral',
   'De frente e com luz, mostrando os disjuntores e as etiquetas.',
   'foto','alto',true,'ai',false),
  (null,'eletrico_ac',null,3,'Qual a potência total que vai ser ligada?',
   'Em watts ou amperes. Define condutor, disjuntor e se a fonte aguenta.',
   'numero','alto',false,'ai',false),
  (null,'eletrico_ac',null,4,'Existe dispositivo de proteção (DR) no circuito?',
   'Se não existir, é pendência a informar ao cliente antes de orçar.',
   'sim_nao','alto',false,'ai',false),
  (null,'eletrico_ac',null,5,'O aterramento existe e está acessível?',
   'Verificar continuidade no ponto. Em embarcação, aterramento errado põe corrente na água.',
   'sim_nao','medio',false,'ai',false),
  (null,'eletrico_ac',null,6,'A transferência entre fontes é automática ou manual?',
   null,'escolha','medio',false,'ai',false),

  -- ── Gás GLP — risco físico ──────────────────────────────────────────────
  (null,'gas',null,1,'Foto do cilindro, do registro e da ligação atual do aparelho',
   'O percurso inteiro, não só o aparelho.',
   'foto','alto',true,'ai',false),
  (null,'gas',null,2,'Onde fica o cilindro e como é o acesso até ele?',
   'Compartimento próprio, ventilado, com registro alcançável?',
   'texto','alto',false,'ai',false),
  (null,'gas',null,3,'A linha existente é mangueira ou tubo rígido? Qual a validade impressa?',
   'A data está impressa na peça — ler, não estimar. Mangueira vencida entra no orçamento.',
   'texto','alto',false,'ai',false),
  (null,'gas',null,4,'Qual a distância do cilindro até o aparelho?',
   'Em metros, pelo caminho real da tubulação, não em linha reta.',
   'medida','alto',false,'ai',false),
  (null,'gas',null,5,'O ambiente tem ventilação permanente na parte baixa?',
   'GLP é mais pesado que o ar e se acumula embaixo. Ventilação alta não resolve.',
   'sim_nao','alto',false,'ai',false),
  (null,'gas',null,6,'Existe detector de gás ou válvula solenoide instalados?',
   null,'sim_nao','medio',false,'ai',false),
  (null,'gas',null,7,'Quantos aparelhos vão ficar na mesma linha?',
   'Fogão, aquecedor, forno. Muda o dimensionamento da linha e do regulador.',
   'numero','medio',false,'ai',false),

  -- ── Hidráulico ──────────────────────────────────────────────────────────
  (null,'hidraulico',null,1,'Foto do ponto de água e do que está logo abaixo dele',
   'O que está embaixo importa tanto quanto o ponto: quase sempre há eletrônica ou madeira.',
   'foto','alto',true,'ai',false),
  (null,'hidraulico',null,2,'Vai precisar abrir forro, piso ou parede para passar a tubulação?',
   'É o item que mais separa um orçamento de duas horas de um de dois dias.',
   'escolha','alto',false,'ai',false),
  (null,'hidraulico',null,3,'O que existe hoje: mangueira, PEX, PVC? Qual o diâmetro?',
   null,'texto','alto',false,'ai',false),
  (null,'hidraulico',null,4,'Onde estão a bomba d''água e o registro geral?',
   'E se a bomba tem pressostato — ela liga sozinha quando a pressão cai.',
   'texto','alto',false,'ai',false),
  (null,'hidraulico',null,5,'Qual a capacidade do tanque ou caixa d''água?',
   null,'numero','medio',false,'ai',false),
  (null,'hidraulico',null,6,'Existe dreno ou esgoto no ponto?',
   null,'sim_nao','medio',false,'ai',false),

  -- ── Eletrônico / dados ──────────────────────────────────────────────────
  (null,'eletronico',null,1,'Marca e modelo do equipamento que entra',
   'Modelo exato: acessório, suporte e cabo mudam de um para outro.',
   'texto','alto',false,'ai',false),
  (null,'eletronico',null,2,'Foto do equipamento atual e do lugar onde o novo será instalado',
   null,'foto','alto',true,'ai',false),
  (null,'eletronico',null,3,'Precisa conversar com algum equipamento que já existe? Qual?',
   'Plotter, central, rede NMEA, câmera, som. Integração é o que transforma instalação simples em projeto.',
   'texto','alto',false,'ai',false),
  (null,'eletronico',null,4,'Por onde passa o cabo ou a antena? Existe caminho pronto?',
   null,'texto','alto',false,'ai',false),
  (null,'eletronico',null,5,'Qual a alimentação disponível no ponto: 12V, 24V ou 110/220V?',
   null,'escolha','medio',false,'ai',false),
  (null,'eletronico',null,6,'O equipamento depende de conta ou assinatura já contratada?',
   'Starlink, rastreador, carta náutica. Sem a conta do cliente, o equipamento não funciona depois de instalado.',
   'sim_nao','medio',true,'ai',false),

  -- ── Refrigeração ────────────────────────────────────────────────────────
  (null,'refrigeracao',null,1,'Foto do equipamento e de como ele está instalado hoje',
   'Incluir o compartimento e as aberturas de ventilação.',
   'foto','alto',true,'ai',false),
  (null,'refrigeracao',null,2,'Qual o tipo: compressor, absorção ou termoelétrico? Marca e modelo?',
   null,'texto','alto',false,'ai',false),
  (null,'refrigeracao',null,3,'O serviço vai exigir abrir o circuito de gás refrigerante?',
   'Se sim, exige habilitação e equipamento de recolhimento — muda quem executa e quanto custa.',
   'sim_nao','alto',false,'ai',false),
  (null,'refrigeracao',null,4,'Qual a alimentação disponível: 12V, 110/220V, ou os dois?',
   null,'escolha','alto',false,'ai',false),
  (null,'refrigeracao',null,5,'Há ventilação suficiente para o condensador no local?',
   'A maior parte do "não gela" é ventilação obstruída, não defeito.',
   'sim_nao','alto',false,'ai',false),
  (null,'refrigeracao',null,6,'Quais as medidas do vão onde o equipamento entra?',
   'Largura, altura e profundidade, com a folga de ventilação.',
   'medida','medio',false,'ai',false),
  (null,'refrigeracao',null,7,'Qual a temperatura que ele alcança hoje?',
   'Se o equipamento ainda funciona, medir antes dá a base de comparação.',
   'medida','baixo',false,'ai',false),

  -- ── Mecânico ────────────────────────────────────────────────────────────
  (null,'mecanico',null,1,'Foto do conjunto montado e do ponto de fixação',
   null,'foto','alto',true,'ai',false),
  (null,'mecanico',null,2,'Marca, modelo e capacidade do equipamento',
   'Guincho, plataforma, slide: capacidade em kg muda tudo.',
   'texto','alto',false,'ai',false),
  (null,'mecanico',null,3,'É acionado por energia ou manual?',
   'O que se move sozinho precisa de corte de energia e trava durante o serviço.',
   'escolha','alto',false,'ai',false),
  (null,'mecanico',null,4,'A base atual aguenta, ou vai precisar de reforço?',
   'Reforço estrutural costuma ser o dobro do serviço em si — precisa estar no orçamento.',
   'escolha','alto',false,'ai',false),
  (null,'mecanico',null,5,'Há peça quebrada que exija reposição específica?',
   'Peça de importado pode ter prazo longo — melhor descobrir antes de agendar.',
   'texto','medio',false,'ai',false),

  -- ══ VERBOS ═══════════════════════════════════════════════════════════════

  (null,null,'instalacao',1,'O equipamento já foi comprado, ou entra no orçamento?',
   'Muda o valor e a responsabilidade sobre garantia do produto.',
   'escolha','alto',true,'ai',false),
  (null,null,'instalacao',2,'O cliente já tem um lugar definido para o equipamento?',
   'Se tiver, conferir se é viável antes de orçar — mudar de lugar depois é refazer a passagem.',
   'texto','alto',false,'ai',false),
  (null,null,'instalacao',3,'Vai precisar furar, cortar ou abrir forro?',
   null,'sim_nao','alto',false,'ai',false),
  (null,null,'instalacao',4,'Foto do local onde vai ser instalado',
   null,'foto','alto',true,'ai',false),

  (null,null,'substituicao',1,'Marca, modelo e ano do que vai sair',
   null,'texto','alto',false,'ai',false),
  (null,null,'substituicao',2,'Foto da peça atual e da etiqueta com os dados técnicos',
   'A etiqueta costuma ter o que o cliente não sabe dizer.',
   'foto','alto',true,'ai',false),
  (null,null,'substituicao',3,'A peça nova tem a mesma medida e capacidade, ou muda?',
   'Se muda, o ponto de instalação provavelmente também muda.',
   'escolha','alto',false,'ai',false),
  (null,null,'substituicao',4,'O que sair fica com o cliente ou vai para descarte?',
   null,'escolha','baixo',true,'ai',false),

  (null,null,'reparo',1,'O que exatamente acontece? Descreva com as palavras do cliente',
   '"Desliga sozinho quando ligo o ar" vale mais que "defeito elétrico".',
   'texto','alto',true,'ai',false),
  (null,null,'reparo',2,'Quando começou e com que frequência acontece?',
   'Defeito intermitente muda o tempo de diagnóstico — e o preço.',
   'texto','alto',true,'ai',false),
  (null,null,'reparo',3,'Já houve tentativa de conserto antes? Por quem?',
   'Serviço mexido por terceiro esconde surpresa e costuma custar mais.',
   'texto','medio',true,'ai',false),
  (null,null,'reparo',4,'Vídeo ou foto do defeito acontecendo',
   'Se o defeito aparece só às vezes, um vídeo curto no celular economiza uma viagem.',
   'foto','medio',true,'ai',false),

  (null,null,'diagnostico',1,'O que o cliente observou, e desde quando?',
   null,'texto','alto',true,'ai',false),
  (null,null,'diagnostico',2,'Acontece sempre, ou só em alguma condição?',
   'Com o motor ligado, com carga alta, depois de algum tempo, no calor.',
   'texto','alto',true,'ai',false),
  (null,null,'diagnostico',3,'Foto do painel ou display mostrando o erro',
   null,'foto','medio',true,'ai',false),

  (null,null,'manutencao',1,'Quando foi a última manutenção, e o que foi feito?',
   null,'texto','alto',true,'ai',false),
  (null,null,'manutencao',2,'Existe manual ou histórico do equipamento?',
   'O manual traz a rotina e os valores de referência que não se deve inventar.',
   'sim_nao','medio',true,'ai',false),
  (null,null,'manutencao',3,'Quantas horas de uso ou quilometragem, se houver contador?',
   null,'numero','medio',true,'ai',false),

  (null,null,'remocao',1,'O que sai e o que fica?',
   'Combinar antes evita remover o que o cliente queria manter — e isso não tem desfazer.',
   'texto','alto',false,'ai',false),
  (null,null,'remocao',2,'O que for removido volta ao cliente ou é descarte?',
   null,'escolha','alto',true,'ai',false),
  (null,null,'remocao',3,'O lugar precisa ficar acabado — tampar furos, forrar, pintar?',
   'Acabamento depois da remoção costuma ser esquecido no orçamento.',
   'sim_nao','alto',false,'ai',false),

  (null,null,'configuracao',1,'Qual o comportamento esperado do sistema?',
   'Prioridade de fonte, autonomia, quando o gerador entra, o que não pode desligar.',
   'texto','alto',false,'ai',false),
  (null,null,'configuracao',2,'Marca e modelo de cada equipamento a parametrizar',
   null,'texto','alto',false,'ai',false),
  (null,null,'configuracao',3,'O cliente tem as senhas e contas de acesso dos equipamentos?',
   'Sem elas o serviço para no meio.',
   'sim_nao','alto',true,'ai',false),
  (null,null,'configuracao',4,'Existe a ficha técnica da bateria ou do equipamento?',
   'É de onde saem os valores de parâmetro — que não se inventa.',
   'sim_nao','alto',true,'ai',false),

  (null,null,'adequacao',1,'O que precisa mudar, e por quê?',
   'Adequação é o serviço que mais cresce durante a execução; o escopo tem que sair escrito daqui.',
   'texto','alto',false,'ai',false),
  (null,null,'adequacao',2,'Foto do que existe hoje',
   null,'foto','alto',true,'ai',false),
  (null,null,'adequacao',3,'Há laudo, vistoria ou exigência de seguradora envolvida?',
   'Muda o nível de documentação que precisa ser entregue no fim.',
   'sim_nao','medio',true,'ai',false),

  (null,null,'logistica',1,'Endereço completo e como é o acesso?',
   'Marina, box, portaria, rampa. Viagem perdida por portão fechado é custo integral.',
   'texto','alto',true,'ai',false),
  (null,null,'logistica',2,'Precisa de autorização de entrada, crachá ou aviso à portaria?',
   null,'sim_nao','alto',true,'ai',false),
  (null,null,'logistica',3,'Qual o horário permitido para trabalhar no local?',
   'Marina e condomínio costumam ter restrição de horário e de ruído.',
   'texto','medio',true,'ai',false),
  (null,null,'logistica',4,'Quem estará presente para receber, e qual o contato?',
   null,'texto','medio',true,'ai',false);

  raise notice 'Perguntas de levantamento inseridas: %',
    (select count(*) from public.service_survey_templates);
end $$;
