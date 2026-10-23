-- Classificador: "conversão" é serviço, não material (C4).
-- Agenda de Produção, Fase 0, pacote P5 (passo 3). Spec: scratchpad agenda-pesquisa/spec-fase0.md (§2.5a).
-- Depende de 20261024150100 (sem os itens a caminho, a OS-00104 ficaria sem linha de material e pareceria
-- pronta).
--
-- ═══ DDL — OK NOMEADO ═══ (CREATE OR REPLACE de classify_service_text, mesma assinatura; não grava dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- O QUE MUDA: "conversao|converter" entra no grupo 'adequacao' dos verbos. Antes, nenhum verbo casava
-- "conversão", e free_text_is_material tratava a linha como material: a OS-00104 ("Conversão do sistema de
-- refrigeração para 12V — Refrigerador Consul CRC28FB", unidade 'unit', R$ 2.500) acusava 1 item a comprar
-- e o R16 a cobrava todo dia. "conversor" (o aparelho: "Conversor DC-DC 12/24V") NÃO casa e segue material;
-- "Kit de conversão LED" segue material porque o prefixo genérico vence o verbo.
--
-- O resto do corpo é cópia EXATA do pg_get_functiondef de produção (md5 2d6442ae78914a8aa8fb8d2fe0ef22b9,
-- 3258 caracteres, conferido em 23/10/2026 e igual a supabase/schemas/producao/05-funcoes.sql:4409-4455).
-- A única outra mudança é o comentário acima da linha.
--
-- EFEITO MEDIDO (só leitura, f08 e f21, 23/10/2026):
--   • texto livre material → serviço: 2 linhas em toda a história. A da OS-00104 (a falta cai de 1 para 0,
--     com o compressor a caminho pela 150100) e a do ORÇ-00098 ("Conversão da iluminação para LED 12V"),
--     que tem unidade 'visit' e já ficava fora da compra;
--   • as outras 3 linhas e os 2 serviços do catálogo com "conversão" já começam por "Instalação" (verbo
--     'instalacao', que vem antes): nada muda;
--   • lines_missing_system / o roteiro passam a sugerir o verbo 'adequacao' para as 2 linhas sem verbo
--     (05-funcoes.sql:7777-7780); o sistema sugerido não muda;
--   • nenhum índice nem coluna gerada usa a função (conferido em 04-indices.sql e 02-tabelas.sql).
--
-- PROVA (depois de aplicar): supabase/tests/purchase_needs_reserva_e_a_caminho.sql (free_text_is_material:
-- Conversão… = false, Conversor DC-DC… = true, Kit de conversão… = true; anon sem execute).
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 150000 e 150100):
--   npx supabase db query --linked -f supabase/migrations/20261024150200_conversao_e_servico.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024150200', 'conversao_e_servico');"

CREATE OR REPLACE FUNCTION public.classify_service_text(p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare k text; v text; s text;
begin
  k := regexp_replace(lower(unaccent(coalesce(p_texto,''))), '\s+', ' ', 'g');
  k := regexp_replace(k, '^(servico de |servico |ct - )', '');

  v := case
    when k ~ '(instala|instaca)'                              then 'instalacao'
    when k ~ '(substitui|subtitui|troca)'                     then 'substituicao'
    when k ~ '(reparo|repara|conserto|restaur|recondicion|correcao)' then 'reparo'
    when k ~ '(diagnost|analise|avalia|inspec|vistoria|teste|verifica)' then 'diagnostico'
    when k ~ '(manuten|revisao|limpeza|higieni|desincrust)'    then 'manutencao'
    when k ~ '(remocao|remover|desmontagem|retirada)'          then 'remocao'
    when k ~ '(configura|parametriz|programa|atualiza)'        then 'configuracao'
    -- conversão é trabalho (OS-00104: 'Conversão do sistema de refrigeração para 12V'); 'conversor' (o
    -- aparelho) não casa. Sem verbo, a linha caía em material e virava falta de compra (24/10/2026).
    when k ~ '(adequa|adapta|modifica|melhoria|upgrade|otimiza|desenvolvimento|confeccao|montagem|ajuste|realocacao|reajuste|conversao|converter)' then 'adequacao'
    -- projeto e consultoria vêm ANTES de logística: "assessoria de projeto" é
    -- trabalho de prancheta, não deslocamento. Sem esta linha, sete serviços
    -- caíam em logística e herdavam o roteiro de quem viaja.
    when k ~ '(projeto|assessoria|consultoria|memorial|laudo)' then 'projeto'
    when k ~ '(frete|deslocamento|visita|hora tecnica|mao de obra)' then 'logistica'
    else null end;

  s := case
    when k ~ '(gas|glp|fogao|aquecedor|boiler|cooktop)'        then 'gas'
    when k ~ '(geladeira|geleira|ar condicionado|ar-condicionado|climatiz|freezer|condicionador|evaporador|chiller)' then 'refrigeracao'
    when k ~ '(agua|hidraulic|bomba d|mangueira|registro|chuveiro|torneira|pia|esgoto|caixa d|pvc|vazamento|escapamento|waterlock|misturador|calafetacao|box)' then 'hidraulico'
    when k ~ '(220v|110v|tomada de cais|quadro ac|ats|transferencia automatica|estabilizador|shore power|gerador)' then 'eletrico_ac'
    when k ~ '(bateria|litio|lifepo|inversor|dc-dc|dc/dc|fusivel|barramento|alternador|usina|victron|mppt|solar|fotovoltaic|12v|24v|shunt|isolador galvanico|carregador|conversor|painel eletric|chave de bateria|cabo eletric|terminal|instalacao eletrica)' then 'eletrico_dc'
    -- radar/plotter/nmea/ais: vocabulário náutico que faltava. "radar" não casa
    -- com "radio", e era o caso de duas OS reais.
    when k ~ '(gps|multimidia|multimedia|radio|radar|plotter|nmea|ais|antena|starlink|camera|transducer|display|sensor|alarme|som|alto falante|subwoofer|roteador|monitor|painel de instrumento|vhf|sonda|piloto automatico)' then 'eletronico'
    when k ~ '(guincho|fechadura|amortecedor|corredica|dobradica|suporte|rodado|pneu|roda|slide|esteira|parafus|manipulo|pedaleira|plataforma|passarela)' then 'mecanico'
    when k ~ '(teto|parede|piso|isolacao termica|acabamento|movel|armario|gaveta)' then 'estrutural'
    when k ~ '(luz|led|spot|farol|iluminacao)'                 then 'eletrico_dc'
    else null end;

  return jsonb_build_object('verbo', v, 'sistema', s,
    'confianca', case when v is not null and s is not null then 0.9
                      when v is not null or s is not null then 0.5 else 0 end);
end;
$function$
;

revoke all on function public.classify_service_text(text) from public, anon;
grant execute on function public.classify_service_text(text) to authenticated, service_role;
