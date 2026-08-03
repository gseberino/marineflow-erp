-- ═══════════════════════════════════════════════════════════════════════════
-- O corpo do verbo "projeto / consultoria"
--
-- Criar o tipo de serviço sem escrever o corpo dele deixaria os sete serviços
-- de projeto sem roteiro nenhum — o mesmo buraco que a tela avisa nas
-- categorias. Então o verbo nasce com corpo, e o corpo nasce esperando
-- assinatura, como todo bloco de IA neste sistema.
--
-- Projeto não vai a campo (`is_fieldwork = false`), então não há abertura nem
-- fechamento de sistema. O que este bloco protege é outra coisa: escopo que
-- cresce, premissa que ninguém registrou e entrega que o cliente não reconhece.
-- É o equivalente, no trabalho de prancheta, do que "desligar a alimentação" é
-- no trabalho de campo.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from public.service_step_blocks where applies_to_verb = 'projeto') then
    raise notice 'O verbo projeto já tem corpo — nada inserido.';
    return;
  end if;

  insert into public.service_step_blocks
    (block_role, applies_to_system, applies_to_verb, seq, title, detail, kind, mode,
     standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
     origin, active)
  values
  ('corpo',null,'projeto',1,
   'Levantar o que existe hoje, com foto e medida',
   'Projeto feito sobre o que o cliente descreveu, e não sobre o que existe, erra na primeira visita de execução. Se não deu para ver, escrever que não viu.',
   'check','read_do',60,true,true,null,null,'ai',false),
  ('corpo',null,'projeto',2,
   'Escrever as premissas e o que fica FORA do escopo',
   'Consumo considerado, autonomia esperada, condição de uso, o que o cliente já tem. E, principalmente, o que este projeto não cobre — é a linha que evita a discussão de "achei que estava incluso".',
   'do','read_do',45,true,false,null,null,'ai',false),
  ('corpo',null,'projeto',3,
   'Dimensionar conforme o manual do fabricante e a norma aplicável',
   'Cada cálculo tem origem: ficha técnica do equipamento, manual do fabricante, norma do setor. Anotar de onde veio cada número — é o que sustenta o projeto quando alguém questiona.',
   'do','read_do',120,true,false,null,null,'ai',false),
  ('corpo',null,'projeto',4,
   'Produzir o desenho, a lista de materiais e o memorial',
   'O que a execução vai receber na mão. Lista de material com especificação suficiente para comprar sem perguntar.',
   'do','do_confirm',120,false,false,null,null,'ai',false),
  ('corpo',null,'projeto',5,
   'Revisar contra o levantamento antes de entregar',
   'Ler o projeto olhando as fotos do passo 1. É onde aparecem a medida que não fecha e o equipamento que não cabe.',
   'check','read_do',45,true,false,null,null,'ai',false),
  ('corpo',null,'projeto',6,
   'Apresentar ao cliente e registrar o aceite das premissas',
   'Projeto entregue por e-mail sem conversa volta como retrabalho. O aceite das premissas é o que separa revisão de mudança de escopo — e mudança de escopo é orçamento novo.',
   'handoff','read_do',45,true,false,null,null,'ai',false),
  ('corpo',null,'projeto',7,
   'Arquivar o projeto na OS, com a versão entregue',
   'Quem for executar daqui a três meses precisa achar a versão certa, não a penúltima.',
   'evidence','do_confirm',15,true,false,null,null,'ai',false);

  raise notice 'Corpo do verbo projeto: % passos.',
    (select count(*) from public.service_step_blocks where applies_to_verb = 'projeto');
end $$;
