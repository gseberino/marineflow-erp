-- Retorno F1 (P2): os sinais de texto e a triagem sem IA (20261116100300_retorno_f1_sinais.sql).
--   0. as funções: volatilidade, SECURITY DEFINER com search_path, fechadas a anon e authenticated;
--      _retorno_busca, _retorno_hora_real e o contrato de _retorno_sinais (as 23 chaves);
--   1. paridade: o fixture LITERAL (a constante c_frases, em dólar com a etiqueta "frases", que só
--      aparece ali) é o mesmo texto de retorno_f1_frases.json (frases_test.ts confere que os dois são
--      iguais; os casos têm o resultado das funções TypeScript);
--      cada chave de esperado é conferida em _retorno_sinais(texto, nome), e a falha mostra o índice
--      do caso no JSON (a partir de 0) e a chave;
--   2. B.2 de ponta a ponta (_retorno_pedido_de_servico): o pedido em qualquer mensagem das 24 h;
--   3. _retorno_numero_novo: só a saída HUMANA tira o número de "novo";
--   4. _retorno_pede_resposta: figurinha, reação, robô, PARAR, mídia em conversa viva (e o envelope de
--      álbum), agradecimento, saudação que abre conversa, "fechou com outra empresa";
--   5. _retorno_nome_dito estrito; 6. robô de 5 s (pelo segundo); 7. PARAR por extenso; 8. a linha do futuro.
-- Mensagens SINTÉTICAS de 55479000093xx, em datas futuras (dez/2026); nenhum dado real muda.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_sinais.sql
-- Termina em ROLLBACK: nada fica gravado. O arranjo inteiro é desfeito dentro do arquivo (sub-bloco que
-- termina em 'desfaz'): a bancada (P15) concatena os arquivos na mesma transação.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

do $sinais$
declare
  c_frases constant jsonb := $frases$
[
  {"texto":"Bom dia Gustavo! Ótimo 👍","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Obrigado!","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"ok","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"👍","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"🙏🙏","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Valeu, show!","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Blz","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Perfeito, combinado.","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Obrigada","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Ta bom","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Fechado 🤝","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Beleza, obrigado Gustavo","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Ah ok","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Muito obrigado!!","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"👍🏻","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Boa tarde","nome":null,"fonte":"palavras_test.ts; plano C12","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false,"saudacao":true,"servico":false,"bem":false,"pedido":false}},
  {"texto":"Obrigado, e quanto fica?","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"ok, me manda o orçamento","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"Sim, já fechei","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Ok, pode seguir","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":null,"nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"...","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Isso o segundo mas tirando o inversor","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Bom dia, consegue vir hoje?","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"pedido":true,"pressa":false}},
  {"texto":"Tudo bem?","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"saudacao":true,"pedido":true}},
  {"texto":"Obrigado, amanhã eu levo o barco","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"bem":true,"bem_palavra":"barco","servico":false,"pressa":false}},
  {"texto":"Bom dia, preciso de um orçamento","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true,"servico":true,"servico_generico":true,"pedido":true,"saudacao":false,"bem":false}},
  {"texto":"[audio]","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"audio_pendente":true,"midia_sem_legenda":false}},
  {"texto":"[image]","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"midia_sem_legenda":true,"audio_pendente":false}},
  {"texto":"🎤 Obrigado","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"O PIX pode ser feito após a expedição finalizar e passar o valor do frete","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"vou mandar o orçamento amanhã","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Pode me passar o orçamento por favor","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"Consegue me passar o valor?","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"pode mandar o orçamento","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"me manda o orçamento","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"passa o valor","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"tem como enviar a cotação?","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"por favor fazer o orçamento","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"Perfeito, vou dar sequencia","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Pode deixar comigo!","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"ok, assim que sair te aviso","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Beleza, já vou providenciar","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Certo, te retorno","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"Claro, fico no seu aguardo meu amigo","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Aguardo seu retorno","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Perfeito, vou dar sequencia. Qual o valor do frete?","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"vou dar sequencia?","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Pode deixar o barco aqui amanhã","nome":null,"fonte":"palavras_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Oii Sou a Allana, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a TIM, esta chegando ao fim, e *vai haver reajuste automático de valor*. Eu tenho aqui ofertas para voce pagar menos com mais benefícios. Posso te enviar um orçamento pra voce analisar sem compromisso?","nome":"Allana Marques","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false}},
  {"texto":"","nome":"Ketelyn Consultora empresarial","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Oii Sou a Ketelyn, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a Tim, esta chegando ao fim, e *nesse período tem um reajuste automático no valor*. Eu tenho aqui ofertas para voce pagar menos com mais benefícios. Posso te enviar um orçamento pra voce analisar sem compromisso?","nome":"Ketelyn","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false}},
  {"texto":"Sou a Allana, consultora da Vivo","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"consultora empresarial","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"identifiquei que o seu contrato com a TIM está chegando ao fim","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"vai haver reajuste automático de valor","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"tenho ofertas para você pagar menos","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Me chamo Rodrigo e sou representante da Marine Co.","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Aqui é o Paulo, do time comercial da Claro","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"temos portabilidade com bônus","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"crédito pré-aprovado para sua empresa","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"consórcio de imóveis","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"plano empresarial com 50GB","nome":"Contato","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Gustavo bom dia, tudo joia?","nome":"Jaison Consultor de Vendas Zendel","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"","nome":"Regis Takeo Mazzaro - Vendas Solmais","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"","nome":"Corretora Mar Seguros","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Você teria disponibilidade de falarmos hoje?","nome":"Josemar Santos","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Tem disponibilidade hoje pela manhã ou início da tarde pra trocar o filtro?","nome":"Paulo  Chave Digital","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Bom Dia, Gustavo. Sobre o serviço na Iveco que falamos. Esta aprovado, favor seguir com os reparos.","nome":"fabiolhdi","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"🎤 Eu entrego na rua, né? Eu tenho avan para entregar, né? Só que hoje eu não estou na cidade, né?","nome":"Cristiano","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"🎤 Marcelo tudo bem boa tarde Celso ali do motorhome eu trouxe teu carregador aqui mas não deu certo","nome":"Celso Docol","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"🎤 Ô bicho, preciso botar minha tomada aqui, cara, essa mulher vai me comer vivo hoje","nome":"Mp Motorhomes","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Plano de acao no MH do Everton Sprinter Azul Termino Caminhao","nome":"Mp Motorhomes","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"29.980.158/0001-57 - HDI SEGUROS S.A.","nome":"Financeiro MP - Milenna","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Olá! Bom dia, tudo bem? Meu nome é Manuela Michelon e falo em nome do SAC da EOS. Serei a responsável pelo seu atendimento. Como posso ajudar?","nome":"","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false}},
  {"texto":"🎤 Pode ser segunda-feira. Porque hoje eu tô em Floripa, amanhã não vou poder também, vou ter feito uns negócios ali.","nome":"flaviodaigreja","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Deu tudo certo?","nome":"Mateus Honório","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Bom dia, conseguimos ver aquele sistema hoje?","nome":"Vitor Botelho - Energia Solar","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Fechar o pedido somente do cerbo?","nome":"Ricardo Comercial Kamell","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"me manda a proposta hoje","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"quero fazer o plano de manutenção","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"qual o horário comercial de vocês?","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"sou gerente da marina e preciso de um orçamento hoje","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"pode me passar um orçamento sem compromisso?","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"sou o João, executivo da transportadora, precisamos do caminhão hoje","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"tenho seguro do barco, cobre?","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"o contrato do serviço está aprovado","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"a oferta de vocês ficou boa, vamos fechar","nome":"Cliente Final","fonte":"palavras_vendedor_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"André você demora muito pra responder e por isso acabei fechando com outra empresa. Obrigado","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"a outra é composta por:","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Tenho em análise 2 propostas","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Não trabalho mais lá faz alguns anos","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"esse nao vou ter amigo","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"vou fechar com vocês","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"não preciso mais do que 2 baterias","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"desisti de ir hoje","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"🎤 Olá, Gustavo. Vamos deixar isto da câmera para depois, porque eu preciso de fechar a solução completa hoje, ou consigo, ou com outras hipóteses que eu tenho.","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false}},
  {"texto":"Se não me responderem hoje vou fechar com outra empresa","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Vamos fechar com outra se o preço não baixar","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true}},
  {"texto":"não quero mais esperar, quando vocês vêm?","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"🎤 tem dia que eu não trago nada porque não preciso mais de peixe, se ele está cheio de peixe que nem tem para se trazer","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false}},
  {"texto":"resolvi o problema com outro cabo, mas a bomba ainda não liga","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"fiz a instalação com outra peça","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Comprei a peça com outro fornecedor, vocês instalam?","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Comprei a bateria com outro fornecedor. Vocês conseguem instalar amanhã?","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Fiz o pix com outra conta, pode conferir?","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"não preciso mais do orçamento?","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"não tenho mais interesse","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"desisti do orçamento","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"NÃO QUEREMOS MAIS, obrigado","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"Contratei com outro fornecedor","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"optamos com a concorrente","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"Já fechei com outra oficina","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"não quero mais o orçamento","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"não preciso mais do serviço, obrigado","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"não quero mais não","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"🎤 O Miguel respondeu que fechou com outro, mas eu acredito que ele pode não ter fechado ainda.","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":true,"pede_preco":false}},
  {"texto":"[conteúdo vazio]","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"🎤 Olá, Gustavo.","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"oi","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"tudo bem","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"e aí","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"alô","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"bom dia","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":true,"encerrou":false,"pede_preco":false}},
  {"texto":"pensando bem, quando vocês podem vir?","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"vocês fazem câmera também?","nome":null,"fonte":"contato-encerrou_test.ts","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false}},
  {"texto":"Bom dia, vocês fazem instalação de placa solar em motorhome?","nome":null,"fonte":"plano C1","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":true,"servico_generico":false,"bem":true,"bem_palavra":"motorhome","pedido":true,"saudacao":false,"pressa":false,"risco":false}},
  {"texto":"🎤 É uma Ducato 2019, tá aqui em Balneário.","nome":null,"fonte":"plano C1","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"bem":true,"bem_palavra":"ducato","modelo":"Ducato","ano":"2019","servico":false,"pedido":false}},
  {"texto":"Ana.","nome":null,"fonte":"plano C1","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":false,"bem":false,"saudacao":false,"pedido":false}},
  {"texto":"Gustavo, preciso trocar as baterias da lancha de novo.","nome":null,"fonte":"plano C2","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":true,"servico_generico":false,"bem":true,"bem_palavra":"lancha","pedido":true,"reclamacao":false,"saudacao":false}},
  {"texto":"Brisa","nome":null,"fonte":"plano C2","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":false,"bem":false,"pedido":false,"saudacao":false}},
  {"texto":"Gustavo, o inversor apitou e desligou.","nome":null,"fonte":"plano C7","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":true,"bem":false,"pedido":false,"risco":false,"pressa":false,"reclamacao":false}},
  {"texto":"URGENTE","nome":null,"fonte":"plano C7; spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"urgente":true,"pressa":true,"saudacao":false}},
  {"texto":"tem cheiro de queimado no quadro","nome":null,"fonte":"plano C7","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"risco":true,"urgente":false}},
  {"texto":"Olá, sou consultor da X Energia e tenho uma proposta…","nome":null,"fonte":"plano C12","esperado":{"vendedor":true,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":false,"saudacao":false}},
  {"texto":"Digite 1 para falar com o financeiro","nome":null,"fonte":"plano C12","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"quer_dono":false}},
  {"texto":"Agradecemos sua mensagem. Em breve retornaremos.","nome":null,"fonte":"plano C12","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"saudacao":false}},
  {"texto":"consegue trazer a bateria do motorhome do inversor?","nome":null,"fonte":"plano C12","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":true,"bem":true,"bem_palavra":"motorhome","pedido":true}},
  {"texto":"a bateria do carro arriou, me busca?","nome":null,"fonte":"plano C12; spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":true,"bem":true,"bem_palavra":"carro","pedido":true,"pressa":false}},
  {"texto":"carro","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"bem":true,"bem_palavra":"carro","servico":false,"pedido":false}},
  {"texto":"Ducato 2019","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"bem":true,"bem_palavra":"ducato","modelo":"Ducato","ano":"2019","servico":false}},
  {"texto":"Motor home","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"bem":true,"bem_palavra":"motorhome","modelo":null}},
  {"texto":"vocês instalam ar condicionado em van?","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"servico":true,"bem":true,"bem_palavra":"van","pedido":true}},
  {"texto":"Queria um orçamento para trocar o inversor","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":true,"servico":true,"servico_generico":false,"pedido":true}},
  {"texto":"pode me ligar?","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"pedido":true,"servico":false,"bem":false}},
  {"texto":"hoje vou passar aí","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"pressa":false,"urgente":false}},
  {"texto":"preciso pra amanhã, vou viajar","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"pressa":true,"urgente":false}},
  {"texto":"Preciso retirar o motorhome amanhã cedo","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"pressa":true,"bem":true}},
  {"texto":"É urgente, por favor","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"urgente":true,"pressa":true}},
  {"texto":"tá saindo fumaça do quadro","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"risco":true,"servico":false}},
  {"texto":"entrou água no porão da lancha","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"risco":true,"bem":true}},
  {"texto":"quero falar com o Gustavo","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"quer_dono":true}},
  {"texto":"vou falar com a minha esposa e te aviso","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"quer_dono":false}},
  {"texto":"Isso é um absurdo, ninguém responde aqui","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"reclamacao":true}},
  {"texto":"ficou ótimo o serviço, obrigado","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"reclamacao":false}},
  {"texto":"quero que apaguem meus dados pessoais","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"lgpd":true}},
  {"texto":"os dados da nota estão certos?","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"lgpd":false}},
  {"texto":"Oiii, bom dia!","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"saudacao":true}},
  {"texto":"Bom dia, tudo bem?","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"saudacao":true,"pedido":true}},
  {"texto":"[document]","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"midia_sem_legenda":true}},
  {"texto":"Olá, sou Carla e vim pelo site da HBR Systems.\nTipo: Motorhome / trailer\nModelo: Sprinter 2018\nServiço: instalação solar","nome":null,"fonte":"spec P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"site":true,"servico":true,"bem":true,"modelo":"Sprinter","ano":"2018"}},
  {"texto":"pare de me mandar mensagem","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":true,"parar":false}},
  {"texto":"não me mande mais","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":true,"parar":false}},
  {"texto":"me tira dessa lista","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":true,"parar":false}},
  {"texto":"quero sair da lista","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":true,"parar":false}},
  {"texto":"não quero mais receber mensagens desse número","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":true,"parar":false}},
  {"texto":"nunca mais funcionou o inversor","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":false,"parar":false},"estreitado":true},
  {"texto":"me tira uma dúvida","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":false,"parar":false},"estreitado":true},
  {"texto":"não me manda o pix ainda","nome":null,"fonte":"spec P2.2 teste 7; P2.3","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":false,"parar":false},"estreitado":true},
  {"texto":"PARAR","nome":null,"fonte":"spec P2.2 teste 7","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar":true,"parar_largo":false}},
  {"texto":"Não quero mais mensagens","nome":null,"fonte":"retorno_f0b_parar.sql","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar":true,"parar_largo":false}},
  {"texto":"me tire dessa lista, por favor","nome":null,"fonte":"P2: me tir(a|e) da regra do SQL","esperado":{"vendedor":false,"so_agradecimento":false,"encerrou":false,"pede_preco":false,"parar_largo":true,"parar":false},"alargado":true}
]
$frases$;
  -- ter 08/12/2026, 00:00 em Brasília: data futura, sem mensagem real
  c_d constant timestamptz := '2026-12-08 00:00:00-03';
  -- as 23 chaves do contrato, na ordem do collate "C" (o "_" vem antes das minúsculas)
  c_chaves constant text[] := array['ano', 'audio_pendente', 'bem', 'bem_palavra', 'encerrou', 'lgpd', 'midia_sem_legenda',
    'modelo', 'parar', 'parar_largo', 'pede_preco', 'pedido', 'pressa', 'quer_dono', 'reclamacao', 'risco', 'saudacao',
    'servico', 'servico_generico', 'site', 'so_agradecimento', 'urgente', 'vendedor'];
  v_f record;
  v_caso jsonb;
  v_i int;
  v_k text;
  v_esp jsonb;
  v_s jsonb;
  v_r jsonb;
  v_t text;
  v_n_casos int := 0;
  v_n_chaves int := 0;
  v_n_mensagens int := 0;
  v_chegou boolean := false;
  -- mensagens do arranjo
  v_m1 uuid; v_m2a uuid; v_m2b uuid; v_m2c uuid; v_m3a uuid; v_m3b uuid; v_m3c uuid; v_m6 uuid;
  v_pa uuid; v_pb uuid; v_pc uuid; v_pd uuid; v_pe uuid; v_pf uuid; v_pg uuid; v_ph uuid; v_pi uuid; v_pj uuid;
  v_pk uuid; v_pl uuid; v_pm uuid; v_pn uuid; v_po uuid; v_pp uuid;
  v_r1 uuid; v_r2 uuid; v_r3 uuid; v_r4 uuid; v_r5 uuid;
begin
  -- ── 0. As funções ──────────────────────────────────────────────────────────────────────────────
  for v_f in
    select x.assinatura, x.volatil, x.definer, p.oid, p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from (values
        ('public._retorno_busca(text)', 'i', false),
        ('public._retorno_parece_vendedor(text, text)', 'i', false),
        ('public._retorno_so_agradecimento(text)', 'i', false),
        ('public._retorno_encerrou(text)', 'i', false),
        ('public._retorno_sinais(text, text)', 'i', false),
        ('public._retorno_nome_dito(text)', 'i', false),
        ('public._retorno_hora_real(public.whatsapp_messages)', 'i', false),
        ('public._retorno_numero_novo(text, timestamptz)', 's', true),
        ('public._retorno_resposta_de_robo(uuid)', 's', true),
        ('public._retorno_pede_resposta(uuid)', 's', true),
        ('public._retorno_pedido_de_servico(text, timestamptz, timestamptz, text)', 's', true)
      ) x(assinatura, volatil, definer)
      left join pg_proc p on p.oid = to_regprocedure(x.assinatura)
  loop
    if v_f.oid is null then
      raise exception '0: % não existe', v_f.assinatura;
    end if;
    if v_f.provolatile <> v_f.volatil or v_f.prosecdef <> v_f.definer
       or not ('search_path=public' = any (v_f.config)) then
      raise exception '0: % não é % (definer %) com search_path = public', v_f.assinatura, v_f.volatil, v_f.definer;
    end if;
    if has_function_privilege('anon', v_f.oid, 'execute') or has_function_privilege('authenticated', v_f.oid, 'execute') then
      raise exception '0: % aberta a anon/authenticated', v_f.assinatura;
    end if;
  end loop;

  -- 0b. Texto de busca: sem acento, minúsculo, só letras e números, sem o corte de 120.
  if public._retorno_busca('  Orçamento p/ instalação — JÁ!  ') is distinct from 'orcamento p instalacao ja'
     or public._retorno_busca(null) is distinct from ''
     or public._retorno_busca('Ñandu  ÇÃO') is distinct from 'nandu cao'
     or length(public._retorno_busca(repeat('motorhome ', 30))) <> 299 then
    raise exception '0b: _retorno_busca fora da regra';
  end if;

  -- 0c. Hora real: hora_real; sem ela o messageTimestamp numérico (10 dígitos); sem ele occurred_at.
  if public._retorno_hora_real(jsonb_populate_record(null::public.whatsapp_messages,
       jsonb_build_object('hora_real', c_d + interval '9 hours', 'occurred_at', c_d + interval '12 hours',
                          'raw_payload', jsonb_build_object('data', jsonb_build_object('messageTimestamp', 1765195200)))))
       is distinct from c_d + interval '9 hours'
     or public._retorno_hora_real(jsonb_populate_record(null::public.whatsapp_messages,
       jsonb_build_object('occurred_at', c_d + interval '12 hours',
                          'raw_payload', jsonb_build_object('data', jsonb_build_object('messageTimestamp', 1765195200)))))
       is distinct from to_timestamp(1765195200)
     or public._retorno_hora_real(jsonb_populate_record(null::public.whatsapp_messages,
       jsonb_build_object('occurred_at', c_d + interval '12 hours',
                          'raw_payload', jsonb_build_object('data', jsonb_build_object('messageTimestamp', '1765195200')))))
       is distinct from c_d + interval '12 hours'
     or public._retorno_hora_real(jsonb_populate_record(null::public.whatsapp_messages,
       jsonb_build_object('occurred_at', c_d + interval '12 hours',
                          'raw_payload', '{"data": {"messageTimestamp": 1e15}}'::jsonb)))
       is distinct from c_d + interval '12 hours'
     or public._retorno_hora_real(jsonb_populate_record(null::public.whatsapp_messages,
       jsonb_build_object('occurred_at', c_d + interval '12 hours')))
       is distinct from c_d + interval '12 hours' then
    raise exception '0c: _retorno_hora_real fora da ordem hora_real → messageTimestamp → occurred_at';
  end if;

  -- 0d. O contrato de _retorno_sinais (o P5 e o replay leem estas chaves): as 23, todas booleanas menos
  --     bem_palavra, modelo e ano, e nunca nulas como booleano, nem com texto nulo.
  foreach v_t in array array['Bom dia', '', null] loop
    v_s := public._retorno_sinais(v_t);
    if (select array_agg(k order by k collate "C") from jsonb_object_keys(v_s) k) is distinct from c_chaves then
      raise exception '0d: as chaves de _retorno_sinais(%) não são as 23 do contrato: %', coalesce(v_t, 'null'), v_s;
    end if;
    if exists (select 1 from jsonb_each(v_s) j
                where j.key not in ('bem_palavra', 'modelo', 'ano') and jsonb_typeof(j.value) <> 'boolean') then
      raise exception '0d: chave booleana de _retorno_sinais(%) não é booleana: %', coalesce(v_t, 'null'), v_s;
    end if;
  end loop;

  -- ── 1. Paridade com o fixture (o mesmo de retorno_f1_frases.json) ───────────────────────────────
  if jsonb_typeof(c_frases) <> 'array' then
    raise exception '1: o fixture não é uma lista';
  end if;
  for v_caso, v_i in
    select f.value, (f.ordinality - 1)::int from jsonb_array_elements(c_frases) with ordinality f(value, ordinality)
  loop
    v_s := public._retorno_sinais(v_caso ->> 'texto', v_caso ->> 'nome');
    for v_k, v_esp in select j.key, j.value from jsonb_each(v_caso -> 'esperado') j loop
      if not (v_s ? v_k) then
        raise exception '1: caso % ("%"): a chave % não existe em _retorno_sinais', v_i,
          left(coalesce(v_caso ->> 'texto', 'null'), 60), v_k;
      end if;
      if (v_s -> v_k) is distinct from v_esp then
        raise exception '1: caso % ("%"), chave %: deu %, esperado %', v_i,
          left(coalesce(v_caso ->> 'texto', 'null'), 60), v_k, v_s -> v_k, v_esp;
      end if;
      v_n_chaves := v_n_chaves + 1;
    end loop;
    v_n_casos := v_n_casos + 1;
  end loop;
  if v_n_casos < 70 then
    raise exception '1: o fixture tem % casos (mínimo 70)', v_n_casos;
  end if;

  -- ── 5. Nome dito: estrito; na dúvida, nulo (o dono pergunta) ────────────────────────────────────
  if public._retorno_nome_dito('Ana.') is distinct from 'Ana'
     or public._retorno_nome_dito('pode me chamar de João Paulo') is distinct from 'João Paulo'
     or public._retorno_nome_dito('Meu nome é Ana Clara!') is distinct from 'Ana Clara'
     or public._retorno_nome_dito('Sou o Otávio') is distinct from 'Otávio' then
    raise exception '5: nome dito não reconhecido';
  end if;
  foreach v_t in array array['ok', 'ana', 'Ducato 2019', 'Boa tarde', 'Fica em Itajaí', 'Pode ser', 'Alguém aí', 'Motorhome',
                             'João Paulo Silva Souza', 'Gustavo', 'Bom Dia', 'Sim', '', null] loop
    if public._retorno_nome_dito(v_t) is not null then
      raise exception '5: "%" virou nome (%)', coalesce(v_t, 'null'), public._retorno_nome_dito(v_t);
    end if;
  end loop;

  -- ── 7. PARAR por extenso: só as formas claras; o PARAR exato é "parar", não "parar_largo" ───────
  foreach v_t in array array['pare de me mandar mensagem', 'não me mande mais', 'me tira dessa lista', 'quero sair da lista',
                             'não quero mais receber mensagens desse número'] loop
    v_s := public._retorno_sinais(v_t);
    if not (v_s ->> 'parar_largo')::boolean or (v_s ->> 'parar')::boolean then
      raise exception '7: "%" não deu parar_largo: %', v_t, v_s;
    end if;
  end loop;
  foreach v_t in array array['nunca mais funcionou o inversor', 'me tira uma dúvida', 'PARAR', 'não me manda o pix ainda'] loop
    if (public._retorno_sinais(v_t) ->> 'parar_largo')::boolean then
      raise exception '7: "%" deu parar_largo', v_t;
    end if;
  end loop;
  if not (public._retorno_sinais('PARAR') ->> 'parar')::boolean then
    raise exception '7: PARAR não deu parar';
  end if;

  -- ── 2, 3, 4, 6 e 8: com mensagens sintéticas, num sub-bloco desfeito no fim ─────────────────────
  begin
    -- 2. B.2 de ponta a ponta.
    -- 2a. C1 da Ana numa mensagem só (9301).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009301', 'text', 'Bom dia, vocês fazem instalação de placa solar em motorhome?', 'received',
              '{"data": {}}', c_d + interval '9 hours 12 minutes', c_d + interval '9 hours 12 minutes 2 seconds')
      returning id into v_m1;
    v_r := public._retorno_pedido_de_servico('00009301', c_d + interval '9 hours 12 minutes', c_d + interval '9 hours 13 minutes');
    if v_r -> 'pedido' is distinct from 'true'::jsonb or v_r ->> 'bem_palavra' is distinct from 'motorhome'
       or v_r -> 'servico_generico' is distinct from 'false'::jsonb
       or v_r ->> 'pedido_literal' is distinct from 'Bom dia, vocês fazem instalação de placa solar em motorhome?'
       or v_r -> 'msgs' is distinct from jsonb_build_array(v_m1) then
      raise exception '2a: C1 numa mensagem não deu pedido: %', v_r;
    end if;
    -- O nome do perfil que diz que vende derruba o pedido.
    v_r := public._retorno_pedido_de_servico('00009301', c_d + interval '9 hours 12 minutes', c_d + interval '9 hours 13 minutes',
                                             'Jaison Consultor de Vendas Zendel');
    if v_r -> 'pedido' is distinct from 'false'::jsonb or v_r -> 'vendedor' is distinct from 'true'::jsonb then
      raise exception '2a: nome de vendedor não derrubou o pedido: %', v_r;
    end if;

    -- 2b. "Boa tarde" 09:00 + "preciso trocar a bateria" 09:05 + "é pro carro" 11:00 (9302): só a partir da 3ª.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009302', 'text', 'Boa tarde', 'received', '{"data": {}}', c_d + interval '9 hours', c_d + interval '9 hours')
      returning id into v_m2a;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009302', 'text', 'preciso trocar a bateria', 'received', '{"data": {}}',
              c_d + interval '9 hours 5 minutes', c_d + interval '9 hours 5 minutes')
      returning id into v_m2b;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009302', 'text', 'é pro carro', 'received', '{"data": {}}', c_d + interval '11 hours', c_d + interval '11 hours')
      returning id into v_m2c;
    if (public._retorno_pedido_de_servico('00009302', c_d + interval '9 hours', c_d + interval '9 hours') ->> 'pedido')::boolean
       or (public._retorno_pedido_de_servico('00009302', c_d + interval '9 hours', c_d + interval '9 hours 5 minutes') ->> 'pedido')::boolean
       or (public._retorno_pedido_de_servico('00009302', c_d + interval '9 hours', c_d + interval '10 hours 59 minutes') ->> 'pedido')::boolean then
      raise exception '2b: pedido antes da 3ª mensagem (o bem ainda não foi dito)';
    end if;
    v_r := public._retorno_pedido_de_servico('00009302', c_d + interval '9 hours', c_d + interval '11 hours');
    if v_r -> 'pedido' is distinct from 'true'::jsonb or v_r ->> 'bem_palavra' is distinct from 'carro'
       or v_r ->> 'pedido_literal' is distinct from 'preciso trocar a bateria'
       or v_r -> 'msgs' is distinct from jsonb_build_array(v_m2a, v_m2b, v_m2c) then
      raise exception '2b: a 3ª mensagem não completou o pedido: %', v_r;
    end if;

    -- 2c. A 3ª 25 h depois da 1ª (9303): fora das primeiras 24 h do número.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009303', 'text', 'Boa tarde', 'received', '{"data": {}}', c_d + interval '9 hours', c_d + interval '9 hours')
      returning id into v_m3a;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009303', 'text', 'preciso trocar a bateria', 'received', '{"data": {}}',
              c_d + interval '9 hours 5 minutes', c_d + interval '9 hours 5 minutes')
      returning id into v_m3b;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009303', 'text', 'é pro carro', 'received', '{"data": {}}', c_d + interval '34 hours', c_d + interval '34 hours')
      returning id into v_m3c;
    v_r := public._retorno_pedido_de_servico('00009303', c_d + interval '9 hours', c_d + interval '34 hours');
    if v_r -> 'pedido' is distinct from 'false'::jsonb or v_r -> 'msgs' is distinct from jsonb_build_array(v_m3a, v_m3b) then
      raise exception '2c: a mensagem de 25 h depois entrou na janela de 24 h: %', v_r;
    end if;

    -- 2d. Vendedor com serviço e bem (9304): nunca é pedido.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009304', 'text',
              'Oii Sou a Allana, Consultora Empresarial da Vivo. Consigo um plano para você trocar a bateria do motorhome sem custo, posso te mandar?',
              'received', '{"data": {}}', c_d + interval '10 hours', c_d + interval '10 hours');
    v_r := public._retorno_pedido_de_servico('00009304', c_d + interval '10 hours', c_d + interval '10 hours');
    if v_r -> 'pedido' is distinct from 'false'::jsonb or v_r -> 'vendedor' is distinct from 'true'::jsonb
       or v_r -> 'servico' is distinct from 'true'::jsonb or v_r -> 'bem' is distinct from 'true'::jsonb then
      raise exception '2d: vendedor com serviço e bem virou pedido: %', v_r;
    end if;

    -- 2e. Só "pode me ligar?" (9305): pedido sem serviço nem bem não decide (L7).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009305', 'text', 'pode me ligar?', 'received', '{"data": {}}', c_d + interval '10 hours', c_d + interval '10 hours');
    v_r := public._retorno_pedido_de_servico('00009305', c_d + interval '10 hours', c_d + interval '10 hours');
    if v_r -> 'pedido' is distinct from 'false'::jsonb or v_r ->> 'pedido_literal' is not null then
      raise exception '2e: "pode me ligar?" virou pedido de serviço: %', v_r;
    end if;

    -- 2f. A mensagem do formulário do site (9306): pedido.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009306', 'text',
              E'Olá, sou Carla e vim pelo site da HBR Systems.\nTipo: Embarcação\nServiço: quero orientação',
              'received', '{"data": {}}', c_d + interval '10 hours', c_d + interval '10 hours');
    v_r := public._retorno_pedido_de_servico('00009306', c_d + interval '10 hours', c_d + interval '10 hours');
    if v_r -> 'pedido' is distinct from 'true'::jsonb or v_r -> 'site' is distinct from 'true'::jsonb then
      raise exception '2f: a mensagem do site não deu pedido: %', v_r;
    end if;

    -- 2g. Sem mensagem, sem chave ou sem p_desde: falso, com a lista vazia.
    v_r := public._retorno_pedido_de_servico('00009399', c_d, c_d + interval '1 day');
    if v_r -> 'pedido' is distinct from 'false'::jsonb or v_r -> 'msgs' is distinct from '[]'::jsonb
       or (public._retorno_pedido_de_servico(null, c_d, c_d + interval '1 day') ->> 'pedido')::boolean
       or (public._retorno_pedido_de_servico('00009301', null, c_d + interval '1 day') ->> 'pedido')::boolean then
      raise exception '2g: sem mensagem, sem chave ou sem p_desde não deu falso: %', v_r;
    end if;

    -- 8. Futuro: a mensagem de serviço gravada DEPOIS de p_ate (lote de ressincronização: hora real 09:10,
    --    gravada às 12:00) não conta; com p_ate depois da gravação, conta (9307).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009307', 'text', 'preciso trocar a bateria do motorhome', 'received', '{"data": {}}',
              c_d + interval '9 hours 10 minutes', c_d + interval '12 hours');
    if (public._retorno_pedido_de_servico('00009307', c_d + interval '9 hours', c_d + interval '10 hours') ->> 'pedido')::boolean then
      raise exception '8: _retorno_pedido_de_servico olhou o futuro (mensagem gravada depois de p_ate)';
    end if;
    if not (public._retorno_pedido_de_servico('00009307', c_d + interval '9 hours', c_d + interval '12 hours') ->> 'pedido')::boolean then
      raise exception '8: a mensagem já gravada em p_ate não contou';
    end if;

    -- 3. Número novo = nunca houve saída HUMANA a esse número.
    -- 3a. Eco do celular do dono às 08:00 (9310): falso a partir dele; antes dele, verdadeiro (o futuro não conta).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009310', 'text', 'Bom dia, tudo certo?', 'sent', '{"data": {"key": {"fromMe": true}}}',
              c_d + interval '8 hours', c_d + interval '8 hours');
    if public._retorno_numero_novo('00009310', c_d + interval '9 hours') then
      raise exception '3a: número com eco do celular ficou novo';
    end if;
    if not public._retorno_numero_novo('00009310', c_d + interval '7 hours') then
      raise exception '3a: o eco gravado depois de p_antes contou (olhou o futuro)';
    end if;
    -- 3b. Só saída automática (9311): o whatsapp-send de origem sistema sem sent_by e a do retorno: novo.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009311', 'text', 'Lembrete automático', 'sent', '{"via": "whatsapp-send", "origem": "sistema"}',
              c_d + interval '8 hours', c_d + interval '8 hours'),
             ('outbound', '5547900009311', 'text', 'Recibo automático', 'sent', '{"via": "retorno"}',
              c_d + interval '8 hours 1 minute', c_d + interval '8 hours 1 minute');
    if not public._retorno_numero_novo('00009311', c_d + interval '9 hours') then
      raise exception '3b: saída automática tirou o número de novo';
    end if;
    -- 3c. Saída pela caixa do app (raw_payload nulo, 9312): humana.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009312', 'text', 'Oi, aqui é o Gustavo', 'sent', null, c_d + interval '8 hours', c_d + interval '8 hours');
    if public._retorno_numero_novo('00009312', c_d + interval '9 hours') then
      raise exception '3c: saída pela caixa do app não contou como humana';
    end if;
    -- 3d. Linha antiga, sem saida_humana (gravada antes da F0b, 9313): classificada na hora pela mesma regra.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009313', 'text', 'Bom dia', 'sent', '{"data": {"key": {"fromMe": true}}}',
              c_d + interval '8 hours', c_d + interval '8 hours');
    update public.whatsapp_messages set saida_humana = null where phone_normalized = '5547900009313';
    if public._retorno_numero_novo('00009313', c_d + interval '9 hours') then
      raise exception '3d: linha sem saida_humana não foi classificada como humana';
    end if;
    -- 3e. Sem chave: não é número novo (falha fecha).
    if public._retorno_numero_novo(null, c_d + interval '9 hours') then
      raise exception '3e: chave nula virou número novo';
    end if;

    -- 4. Pede resposta?
    -- 4a. Figurinha (9320), pelo message_type e pelo messageType do webhook.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009320', 'sticker', '[sticker]', 'received', '{"data": {}}', c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pa;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009320', 'text', '[conteúdo vazio]', 'received', '{"data": {"messageType": "stickerMessage"}}',
              c_d + interval '10 hours 1 minute', c_d + interval '10 hours 1 minute')
      returning id into v_pb;
    -- 4b. Reação (9321).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009321', 'text', '[conteúdo vazio]', 'received', '{"data": {"messageType": "reactionMessage"}}',
              c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pc;
    if public._retorno_pede_resposta(v_pa) is distinct from '{"pede": false, "motivo": "figurinha_ou_reacao"}'::jsonb
       or public._retorno_pede_resposta(v_pb) is distinct from '{"pede": false, "motivo": "figurinha_ou_reacao"}'::jsonb
       or public._retorno_pede_resposta(v_pc) is distinct from '{"pede": false, "motivo": "figurinha_ou_reacao"}'::jsonb then
      raise exception '4a/4b: figurinha ou reação pediu resposta: % % %',
        public._retorno_pede_resposta(v_pa), public._retorno_pede_resposta(v_pb), public._retorno_pede_resposta(v_pc);
    end if;
    -- 4c. Robô: o mesmo texto longo 3 vezes em 30 dias (9322); a 3ª não pede.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009322', 'text', 'Agradecemos o seu contato! Em breve um de nossos atendentes vai responder a sua mensagem.',
              'received', '{"data": {}}', c_d - interval '2 days', c_d - interval '2 days'),
             ('inbound', '5547900009322', 'text', 'Agradecemos o seu contato! Em breve um de nossos atendentes vai responder a sua mensagem.',
              'received', '{"data": {}}', c_d - interval '1 day', c_d - interval '1 day');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009322', 'text', 'Agradecemos o seu contato! Em breve um de nossos atendentes vai responder a sua mensagem.',
              'received', '{"data": {}}', c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pd;
    if public._retorno_pede_resposta(v_pd) is distinct from '{"pede": false, "motivo": "robo"}'::jsonb then
      raise exception '4c: texto de robô repetido pediu resposta: %', public._retorno_pede_resposta(v_pd);
    end if;
    -- 4d. PARAR (9323) e PARAR por extenso (9324): não pedem (tratados à parte).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009323', 'text', 'PARAR', 'received', '{"data": {}}', c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pe;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009324', 'text', 'pare de me mandar mensagem', 'received', '{"data": {}}',
              c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pf;
    if public._retorno_pede_resposta(v_pe) is distinct from '{"pede": false, "motivo": "parar"}'::jsonb
       or public._retorno_pede_resposta(v_pf) is distinct from '{"pede": false, "motivo": "parar_largo"}'::jsonb then
      raise exception '4d: PARAR ou PARAR por extenso: % %', public._retorno_pede_resposta(v_pe), public._retorno_pede_resposta(v_pf);
    end if;
    -- 4e. Foto sem legenda 20 min depois de uma saída do dono (9325, conversa viva): não pede.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009325', 'text', 'Me manda uma foto do quadro?', 'sent', '{"data": {"key": {"fromMe": true}}}',
              c_d + interval '10 hours', c_d + interval '10 hours');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009325', 'image', '[image]', 'received', '{"data": {}}', c_d + interval '10 hours 20 minutes',
              c_d + interval '10 hours 20 minutes')
      returning id into v_pg;
    if public._retorno_pede_resposta(v_pg) is distinct from '{"pede": false, "motivo": "midia_em_conversa_viva"}'::jsonb then
      raise exception '4e: foto em conversa viva pediu resposta: %', public._retorno_pede_resposta(v_pg);
    end if;
    -- 4f. Foto sem legenda sem conversa viva (9326): pede. Uma enviada de hora real 10:10 gravada às 10:30
    --     (depois da foto) e uma recebida das 10:25 são o futuro da foto: não mudam nada.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009326', 'image', '[image]', 'received', '{"data": {}}', c_d + interval '10 hours 20 minutes',
              c_d + interval '10 hours 20 minutes')
      returning id into v_ph;
    if public._retorno_pede_resposta(v_ph) is distinct from '{"pede": true, "motivo": null}'::jsonb then
      raise exception '4f: foto sem conversa viva não pediu resposta: %', public._retorno_pede_resposta(v_ph);
    end if;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009326', 'text', 'Recebi a foto', 'sent', '{"data": {"key": {"fromMe": true}}}',
              c_d + interval '10 hours 10 minutes', c_d + interval '10 hours 30 minutes'),
             ('inbound', '5547900009326', 'text', 'é o quadro do motorhome', 'received', '{"data": {}}',
              c_d + interval '10 hours 25 minutes', c_d + interval '10 hours 25 minutes');
    if public._retorno_pede_resposta(v_ph) is distinct from '{"pede": true, "motivo": null}'::jsonb then
      raise exception '4f: linha do futuro mudou o "pede resposta" da foto: %', public._retorno_pede_resposta(v_ph);
    end if;
    -- 4g. "Obrigado!" (9327): não pede.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009327', 'text', 'Obrigado!', 'received', '{"data": {}}', c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pi;
    if public._retorno_pede_resposta(v_pi) is distinct from '{"pede": false, "motivo": "agradecimento"}'::jsonb then
      raise exception '4g: "Obrigado!" pediu resposta: %', public._retorno_pede_resposta(v_pi);
    end if;
    -- 4h. "Boa tarde" abrindo conversa (9328): pede, mesmo com uma mensagem dele gravada depois.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009328', 'text', 'Boa tarde', 'received', '{"data": {}}', c_d + interval '14 hours', c_d + interval '14 hours')
      returning id into v_pj;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009328', 'text', 'tudo bem?', 'received', '{"data": {}}', c_d + interval '14 hours 1 minute',
              c_d + interval '14 hours 1 minute');
    if public._retorno_pede_resposta(v_pj) is distinct from '{"pede": true, "motivo": null}'::jsonb then
      raise exception '4h: "Boa tarde" abrindo conversa não pediu resposta: %', public._retorno_pede_resposta(v_pj);
    end if;
    -- 4i. "Boa tarde" no meio da conversa (9329, uma mensagem dele 1 h antes): não pede.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009329', 'text', 'preciso de ajuda com o inversor', 'received', '{"data": {}}',
              c_d + interval '13 hours', c_d + interval '13 hours');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009329', 'text', 'Boa tarde', 'received', '{"data": {}}', c_d + interval '14 hours', c_d + interval '14 hours')
      returning id into v_pk;
    if public._retorno_pede_resposta(v_pk) is distinct from '{"pede": false, "motivo": "agradecimento"}'::jsonb then
      raise exception '4i: "Boa tarde" no meio da conversa pediu resposta: %', public._retorno_pede_resposta(v_pk);
    end if;
    -- 4j. "já fechei com outra empresa" (9330): não pede.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009330', 'text', 'já fechei com outra empresa', 'received', '{"data": {}}',
              c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pl;
    if public._retorno_pede_resposta(v_pl) is distinct from '{"pede": false, "motivo": "encerrou"}'::jsonb then
      raise exception '4j: "já fechei com outra empresa" pediu resposta: %', public._retorno_pede_resposta(v_pl);
    end if;
    -- 4k. Não é conversa: enviada, lista de transmissão, grupo e mensagem que não existe.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at, is_broadcast)
      values ('inbound', '5547900009331', 'text', 'Promoção de baterias!', 'received', '{"data": {}}',
              c_d + interval '10 hours', c_d + interval '10 hours', true)
      returning id into v_pm;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009332@g.us', 'text', 'Bom dia, grupo', 'received', '{"data": {}}',
              c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pn;
    if public._retorno_pede_resposta(v_pm) is distinct from '{"pede": false, "motivo": "nao_e_conversa"}'::jsonb
       or public._retorno_pede_resposta(v_pn) is distinct from '{"pede": false, "motivo": "nao_e_conversa"}'::jsonb
       or public._retorno_pede_resposta((select w.id from public.whatsapp_messages w
                                          where w.phone_normalized = '5547900009325' and w.direction = 'outbound'))
          is distinct from '{"pede": false, "motivo": "nao_e_conversa"}'::jsonb
       or public._retorno_pede_resposta(gen_random_uuid()) is distinct from '{"pede": false, "motivo": "nao_e_conversa"}'::jsonb
       or public._retorno_pede_resposta(null) is distinct from '{"pede": false, "motivo": "nao_e_conversa"}'::jsonb then
      raise exception '4k: enviada, transmissão, grupo ou mensagem inexistente não deu nao_e_conversa';
    end if;
    -- 4l. O C1 da Ana (9301) pede.
    if public._retorno_pede_resposta(v_m1) is distinct from '{"pede": true, "motivo": null}'::jsonb then
      raise exception '4l: o pedido da Ana não pediu resposta: %', public._retorno_pede_resposta(v_m1);
    end if;
    -- 4m. Envelope de álbum ('[conteúdo vazio]', messageType albumMessage) 5 min depois de uma saída do
    --     dono (9333, conversa viva): é mídia sem legenda, não pede.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009333', 'text', 'Me manda as fotos da instalação?', 'sent', '{"data": {"key": {"fromMe": true}}}',
              c_d + interval '10 hours', c_d + interval '10 hours');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009333', 'text', '[conteúdo vazio]', 'received', '{"data": {"messageType": "albumMessage"}}',
              c_d + interval '10 hours 5 minutes', c_d + interval '10 hours 5 minutes')
      returning id into v_po;
    if public._retorno_pede_resposta(v_po) is distinct from '{"pede": false, "motivo": "midia_em_conversa_viva"}'::jsonb then
      raise exception '4m: álbum em conversa viva pediu resposta: %', public._retorno_pede_resposta(v_po);
    end if;
    -- 4n. O mesmo envelope abrindo conversa (9334, nada da chave antes): pede, como a 1ª foto pediria.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009334', 'text', '[conteúdo vazio]', 'received', '{"data": {"messageType": "albumMessage"}}',
              c_d + interval '10 hours', c_d + interval '10 hours')
      returning id into v_pp;
    if public._retorno_pede_resposta(v_pp) is distinct from '{"pede": true, "motivo": null}'::jsonb then
      raise exception '4n: álbum abrindo conversa não pediu resposta: %', public._retorno_pede_resposta(v_pp);
    end if;

    -- 6. Robô de 5 s: a recebida até 5 s depois de uma enviada AUTOMÁTICA à mesma chave.
    -- 6a. Enviada {"via": "retorno"} às 10:00:00 (9340): a recebida às 10:00:03 é robô; às 10:00:09, não.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009340', 'text', 'Recibo automático', 'sent', '{"via": "retorno"}',
              c_d + interval '10 hours', c_d + interval '10 hours');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009340', 'text', 'No momento não estamos disponíveis.', 'received', '{"data": {}}',
              c_d + interval '10 hours 3 seconds', c_d + interval '10 hours 4 seconds')
      returning id into v_r1;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009340', 'text', 'Oi, pode me ajudar com a bateria?', 'received', '{"data": {}}',
              c_d + interval '10 hours 9 seconds', c_d + interval '10 hours 10 seconds')
      returning id into v_r2;
    if not public._retorno_resposta_de_robo(v_r1) or public._retorno_resposta_de_robo(v_r2) then
      raise exception '6a: robô de 5 s: 10:00:03 deu %, 10:00:09 deu %',
        public._retorno_resposta_de_robo(v_r1), public._retorno_resposta_de_robo(v_r2);
    end if;
    if public._retorno_pede_resposta(v_r1) is distinct from '{"pede": false, "motivo": "robo"}'::jsonb then
      raise exception '6a: a resposta de robô pediu resposta: %', public._retorno_pede_resposta(v_r1);
    end if;
    -- 6b. Depois de uma saída HUMANA às 10:00:00 (caixa do app, 9341): falso.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009341', 'text', 'Oi, tudo bem?', 'sent', null, c_d + interval '10 hours', c_d + interval '10 hours');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009341', 'text', 'Tudo sim!', 'received', '{"data": {}}',
              c_d + interval '10 hours 3 seconds', c_d + interval '10 hours 4 seconds')
      returning id into v_r3;
    if public._retorno_resposta_de_robo(v_r3) then
      raise exception '6b: resposta rápida a uma saída humana virou robô';
    end if;
    -- 6c. Futuro: a enviada automática de hora real 10:00:01, mas gravada às 10:00:10 (depois da recebida
    --     das 10:00:03), não conta (9342).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009342', 'text', 'Bom dia, preciso de ajuda', 'received', '{"data": {}}',
              c_d + interval '10 hours 3 seconds', c_d + interval '10 hours 4 seconds')
      returning id into v_r4;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009342', 'text', 'Recibo automático', 'sent', '{"via": "retorno"}',
              c_d + interval '10 hours 1 second', c_d + interval '10 hours 10 seconds');
    if public._retorno_resposta_de_robo(v_r4) then
      raise exception '6c: _retorno_resposta_de_robo olhou o futuro (enviada gravada depois da recebida)';
    end if;
    if public._retorno_resposta_de_robo(gen_random_uuid()) or public._retorno_resposta_de_robo(null) then
      raise exception '6d: mensagem inexistente virou robô';
    end if;
    -- 6e. Relógios diferentes, comparados pelo segundo (9343): a enviada {"via": "retorno"} tem hora real
    --     10:00:00.700 (now() do gatilho, depois do provedor); a ausência, messageTimestamp 10:00:00
    --     (cortado no segundo), gravada às 10:00:01. É robô.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('outbound', '5547900009343', 'text', 'Recibo automático', 'sent', '{"via": "retorno"}',
              c_d + interval '10 hours 0.7 seconds', c_d + interval '10 hours 0.7 seconds');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
      values ('inbound', '5547900009343', 'text', 'No momento não estamos disponíveis.', 'received', '{"data": {}}',
              c_d + interval '10 hours', c_d + interval '10 hours 1 second')
      returning id into v_r5;
    if not public._retorno_resposta_de_robo(v_r5) then
      raise exception '6e: a ausência no mesmo segundo da enviada (relógios diferentes) não virou robô';
    end if;
    if public._retorno_pede_resposta(v_r5) is distinct from '{"pede": false, "motivo": "robo"}'::jsonb then
      raise exception '6e: a resposta de robô no mesmo segundo pediu resposta: %', public._retorno_pede_resposta(v_r5);
    end if;

    select count(*) into v_n_mensagens from public.whatsapp_messages
     where phone_normalized like '55479000093%';
    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then
      raise;
    end if;
  end;
  if not v_chegou then
    raise exception '9: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.whatsapp_messages where phone_normalized like '55479000093%') then
    raise exception '9: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_sinais', true,
          jsonb_build_object('casos_do_fixture', v_n_casos, 'chaves_conferidas', v_n_chaves, 'mensagens_sinteticas', v_n_mensagens));
end
$sinais$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
