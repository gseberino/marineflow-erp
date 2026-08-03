-- ═══════════════════════════════════════════════════════════════════════════
-- Palavras que faltavam ao classificador
--
-- Ao testar a sugestão de sistema nas OS reais, duas ficaram sem resposta:
-- ambas de "Diagnóstico Radar". A regra conhecia "rádio" e não "radar", e as
-- duas palavras não casam entre si. O mesmo vale para plotter, NMEA e AIS —
-- vocabulário corrente de eletrônica náutica que simplesmente não estava na
-- lista.
--
-- Alterar a função NÃO reclassifica o catálogo: os 262 serviços já têm
-- `classified_at` preenchido e o UPDATE inicial só tocava em quem estava nulo.
-- O ganho é nas sugestões daqui para frente.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.classify_service_text(p_texto text)
returns jsonb
language plpgsql
immutable
set search_path = public, extensions
as $fn$
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
    when k ~ '(adequa|adapta|modifica|melhoria|upgrade|otimiza|desenvolvimento|confeccao|montagem|ajuste|realocacao|reajuste)' then 'adequacao'
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
$fn$;

revoke all on function public.classify_service_text(text) from public, anon;
grant execute on function public.classify_service_text(text) to authenticated;
