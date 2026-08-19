-- [F-NFSE] Os 5 últimos serviços sem código fiscal efetivo
--
-- Ficaram de fora do backfill de fiscal_verb (20260811003000) por não terem verbo
-- OPERACIONAL preenchido. Com a confirmação da contadora de 18/08/2026 ("manter tudo no
-- 14.01"), os 10 verbos fiscais resolvem para o MESMO cadastro (140101/3317102/3%) — a
-- escolha do verbo aqui não muda um centavo de imposto; apenas liga a herança. Atribuído
-- pelo nome, que é inequívoco. Guarda dupla: só linha sem verbo fiscal E sem código
-- próprio.
update public.services
   set fiscal_verb = case
         when name ilike 'Reparo%' then 'reparo'
         when name ilike 'Substituição%' then 'substituicao'
         else 'instalacao'
       end,
       updated_at = now()
 where fiscal_verb is null
   and national_tax_code is null
   and active
   and name in (
     'Instalação de Display Remoto de Equipamentos De Conversão',
     'Reparo de vazamento no box do chuveiro',
     'Serviço de instalação dos equipamentos',
     'Serviço de passagem de cabos',
     'Substituição dos conduítes corrugados porta-cabos'
   );
