-- ═══════════════════════════════════════════════════════════════════════════
-- As 16 linhas de texto livre que a regra classificou com segurança
--
-- De 36 linhas soltas, 18 saíram com sistema E verbo lidos no texto da própria
-- linha (origem 'linha', a fonte forte — não o palpite tirado do contexto da
-- OS). Destas, duas ficam de fora de propósito:
--
--   · "Materiais e insumos complementares de instalação" (OS-00060)
--   · "Materiais - Reparo tubulação PVC 2\"" (OS-00061)
--
-- São MATERIAL lançado como linha de serviço — parte do achado antigo de que
-- 6 lançamentos assim inflam a receita de serviço e somem do custo de material.
-- A regra os classificou porque o texto diz "instalação" e "reparo", mas dar
-- roteiro de trabalho a uma linha de material é ensinar o técnico a marcar
-- passo que ninguém executou. Ficam sem classificação, e o problema de fundo
-- (material lançado como serviço) continua sendo do dono.
--
-- As 16 restantes são trabalho de verdade, e passam a gerar roteiro.
-- ═══════════════════════════════════════════════════════════════════════════
update public.service_order_services sos
set service_system = v.sistema,
    service_verb   = v.verbo,
    updated_at     = now()
from (values
  -- ORÇ-00064 · ORÇ-00066 · ORÇ-00068 — pacotes elétricos descritos à mão
  ('d076b3cb-9322-4502-b2d2-a425de227824'::uuid,'eletrico_dc','instalacao'),
  ('eede6dcb-f5ec-48ef-b888-4a8de410d699'::uuid,'eletrico_dc','configuracao'),
  ('0ecbfbbf-cc21-4ba2-a604-be4f10e3c46f'::uuid,'eletrico_ac','instalacao'),
  ('58815ccd-caf2-4e45-8063-7d934c8051cd'::uuid,'eletrico_dc','instalacao'),
  -- OS-00032 — instalação do gerador, decomposta em etapas
  ('f583dbb6-7734-4122-a5d9-3a4454154b45'::uuid,'hidraulico','instalacao'),
  ('16dc13f4-045d-435c-82c4-4096811d9b5b'::uuid,'hidraulico','instalacao'),
  -- OS-00060 — motorhome: carregadores, sensor de gás e rodados
  ('e73b95ba-0cd0-4113-aec7-88098a8e0f7a'::uuid,'eletrico_dc','instalacao'),
  ('476662dc-ead5-4be1-8ce2-de05a33de4d6'::uuid,'gas','instalacao'),
  ('dd8071a4-4f5e-4450-a612-3f27581fca48'::uuid,'mecanico','adequacao'),
  ('173dd3b1-56f2-4780-856e-f5cbe2fe1c4a'::uuid,'mecanico','instalacao'),
  -- OS-00061 — motorhome: vazamentos, guincho, slide-out e tubulação
  ('015d2b3e-1a92-4d36-a5d1-3c08d439f96d'::uuid,'mecanico','remocao'),
  ('3bae14af-161a-45f8-8bcb-f07da54aa88b'::uuid,'mecanico','instalacao'),
  ('8b17ab9f-e3ef-44d8-8000-a9330c3125bc'::uuid,'hidraulico','reparo'),
  ('af4400a6-13da-4996-bd8d-8166b92855d9'::uuid,'hidraulico','reparo'),
  ('c60f3963-1961-437f-b2ea-c73c0811a4c7'::uuid,'mecanico','substituicao'),
  ('1bdea929-26b5-4e27-85f8-d6a5adb8a9c0'::uuid,'hidraulico','substituicao')
) as v(id, sistema, verbo)
where sos.id = v.id
  -- Não sobrescreve o que já tiver sido decidido à mão.
  and sos.service_system is null and sos.service_verb is null;
