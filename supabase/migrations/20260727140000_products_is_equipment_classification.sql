-- Distinção EQUIPAMENTO (vende avulso, precisa foto p/ vitrine/status) × INSUMO (contado, não
-- vendido avulso). Campo aditivo e reversível (não altera preço/estoque/nome). null = revisar.
alter table public.products add column if not exists is_equipment boolean;

-- Classificação de primeira passada por nome + preço + tipo. Conservadora: só marca true/false
-- quando o sinal é forte; o ambíguo fica null para o dono revisar.
update public.products set is_equipment = (
  case
    when product_type in ('kit','composto') then true
    when lower(name) ~ '(victron|garmin|raymarine|lifek|usina|mercury|quick|fusion|simrad|lowrance|humphree|volvo penta|axiom|gpsmap|echomap|multiplus|quattro|\borion\b|smartshunt|cerbo|phoenix|blue ?smart|inversor|carregad|bateria|painel solar|fotovolt|\bmppt\b|controlador de carga|sonar|\bgps\b|chartplotter|\bbomba\b|ar[ -]?condicionado|motor de|gerador|alternador|no[ -]?break|transformador|conversor dc|c[âa]mera|antena|starlink|autopilot|piloto autom|\bflap\b|estabilizador|guincho|macerador|exaustor|purificad|geladeira|freezer|dessaliniz|\bshunt\b|disjuntor)'
      then true
    when lower(name) ~ '(bucha|parafus|arruela|\bporca\b|prego|terminal|abra[çc]ad|\bcabo\b|\bfio\b|\bfita\b|\bcola\b|silicone|veda|mangueira|\bborne\b|ilh[óo]|\bluva\b|anilha|presilha|espaguete|termorr|isolant|graxa|spray|lixa|broca|rebite|olhal|capa clip|passa[ -]?muro|condu[íi]te|fus[íi]vel|espuma|redu[çc]|ni[pp]le|uni[ãa]o|adaptador|flange|selante|conex[ãa]o)'
         and coalesce(sale_price,0) < 400
      then false
    when coalesce(sale_price,0) >= 1000 then true
    else null
  end
)
where active;
