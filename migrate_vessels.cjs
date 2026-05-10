const fs = require('fs');

const CSV_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\embarcacoes.csv';
const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

const OWNER_MAPPING = {
  "aria": "marcelo marco bertoldi",
  "bote": "juliano acrisio",
  "brunetta": "joão paulo demitti",
  "dondoka": "celio yudi shiokawa junior",
  "donna v": "acrisio cançado lopes",
  "lady lari": "felipe antunes de lima",
  "lady vic": "gustavo seberino da silva",
  "lancha rápida": "hbr systems",
  "lancha teste auditoria": "teste auditoria claude",
  "madu i": "edson luiz rudek junior",
  "mar azul": "teste lead conversão - joão marinho",
  "nalla": "allandelon ramos",
  "test boat": "teste client",
  "teste": "360 servicos de arte em rodas ltda" // O mapeamento pode variar se houver duplicatas, mas usaremos o primeiro por enquanto
};

async function migrate() {
  console.log('Iniciando migração de embarcações com mapeamento de donos...');
  
  // 1. Buscar Clientes e Marinas
  const clientsResp = await fetch(`${SUPABASE_URL}/rest/v1/clients?select=id,full_name_or_company_name`, {
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` }
  });
  const clients = await clientsResp.json();
  const clientMap = {};
  clients.forEach(c => clientMap[c.full_name_or_company_name.toLowerCase().trim()] = c.id);

  const marinasResp = await fetch(`${SUPABASE_URL}/rest/v1/marinas?select=id,marina_name`, {
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` }
  });
  const marinas = await marinasResp.json();
  const marinaMap = {};
  marinas.forEach(m => marinaMap[m.marina_name.toLowerCase().trim()] = m.id);

  const content = fs.readFileSync(CSV_PATH, 'latin1');
  const lines = content.split('\n');
  
  const vessels = [];
  
  for (let i = 1; i < lines.length; i++) {
    if (!lines[i].trim()) continue;
    
    const cols = lines[i].split(';');
    if (cols.length < 1) continue;
    
    const boatName = cols[0]?.trim();
    const ownerNameFromMap = OWNER_MAPPING[boatName.toLowerCase()];
    const marinaName = cols[9]?.trim();
    
    const vessel = {
      boat_name: boatName || 'N/D',
      model: cols[1]?.trim() || null,
      manufacturer: cols[2]?.trim() || null,
      year: parseInt(cols[3]) || null,
      client_id: clientMap[ownerNameFromMap] || clientMap['gustavo seberino da silva'] || null, // Fallback para o seu usuário se não achar
      marina_id: marinaMap[marinaName?.toLowerCase()?.trim()] || null,
      active: true,
      asset_type: 'vessel'
    };
    
    vessels.push(vessel);
  }

  console.log(`Encontradas ${vessels.length} embarcações. Enviando para o Supabase...`);

  const response = await fetch(`${SUPABASE_URL}/rest/v1/vessels`, {
    method: 'POST',
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(vessels)
  });

  if (response.ok) {
    console.log('Embarcações migradas com sucesso!');
  } else {
    const error = await response.text();
    console.error('Erro na migração de embarcações:', error);
  }
}

migrate().catch(console.error);
