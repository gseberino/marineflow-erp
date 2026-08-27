-- [FISCAL] Correção dos cadastros que rejeitaram as 1ªs NF-e reais (27/08/2026)
--
-- NF-e nº 26 (OS-00060) — Rejeição SEFAZ 778 "NCM inexistente [nItem:2]" e
-- NF-e nº 27 (OS-00075) — Rejeição SEFAZ 600 "CSOSN incompatível com Não Contribuinte
-- [nItem:3]". Auditoria item a item das duas notas revelou:
--
-- NCM INEXISTENTE/ERRADO (validados na tabela NCM vigente em 27/08/2026):
--   • Sensor de Nível de Gás: 90262000 NÃO EXISTE (9026.20 é PRESSÃO e exige desdobro).
--     Sensor de NÍVEL → 9026.10.29 (medida/controle de nível, outros).
--   • Roda de Alumínio Iveco: 87082090 é "partes de carrocerias". RODAS → 8708.70.90.
--   • Fogão de Indução 220V: 73219900 é fogão NÃO elétrico (partes). Eletrotérmico
--     doméstico → 8516.60.00.
--   • Fusível ANL/MIDI: 85364900 é RELÉ >60V. Fusíveis/corta-circuitos → 8536.10.00.
--
-- CSOSN DE REVENDA ERRADO:
--   • CSOSN 400 ("não tributada pelo Simples") em 5 produtos e 900 ("outros") em 1 —
--     resquício do default antigo (400) corrigido em 15/07 no resolvedor, mas que ficou
--     gravado como valor PRÓPRIO nesses cadastros. Revenda comum a não contribuinte no
--     Simples = CSOSN 102 (o mesmo dos demais itens autorizados).
--
-- Guardas: por id E pelo valor errado atual — se alguém já corrigiu, o UPDATE não toca.
update public.products set ncm = '90261029', updated_at = now()
 where id = 'd76cea6b-52cd-4a0d-87cd-c8342a218d7d' and ncm = '90262000';

update public.products set ncm = '87087090', updated_at = now()
 where id = 'fd3147bd-d2f2-4186-b9b1-4ea1a1e394dd' and ncm = '87082090';

update public.products set ncm = '85166000', updated_at = now()
 where id = 'a096f27b-f5e6-41f9-9f7b-c391b427ad3c' and ncm = '73219900';

update public.products set ncm = '85361000', csosn = '102', updated_at = now()
 where id = 'e3d0eca5-e797-4acb-a6d7-d9f74f07949d' and ncm = '85364900';

update public.products set csosn = '102', updated_at = now()
 where id in (
   'fbb9212a-2492-41e0-89c8-3716775c113e',  -- Cabo elétrico 16mm² (era 400)
   '5c2bbc15-9469-472f-93ac-ee1cf3c1df3f',  -- Materiais e insumos complementares (era 400)
   '7a737eed-8b48-4f91-8537-e183d009f930',  -- Conector de lâmpada de farol (era 400)
   '1812d9b5-8681-498d-a0cc-a5ea7b770dc6',  -- Conector do cabo elétrico (era 400)
   '569b61d7-e325-418f-8cda-a69816c5e497'   -- Relé de controle do farol (era 900 → Rejeição 600)
 ) and csosn in ('400', '900');
