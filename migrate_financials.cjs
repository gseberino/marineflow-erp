const fs = require('fs');

const OS_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\ordens_servico_2026-05-09.csv';
const REC_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\recebiveis_2026-05-09.csv';
const PAG_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\pagaveis_2026-05-09.csv';

const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

async function migrate() {
  console.log('Iniciando migração financeira e de OS...');

  // 1. Mapas de IDs
  const clientsResp = await fetch(`${SUPABASE_URL}/rest/v1/clients?select=id,full_name_or_company_name`, {
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` }
  });
  const clientMap = {};
  (await clientsResp.json()).forEach(c => clientMap[c.full_name_or_company_name.toLowerCase().trim()] = c.id);

  const vesselsResp = await fetch(`${SUPABASE_URL}/rest/v1/vessels?select=id,boat_name`, {
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` }
  });
  const vesselMap = {};
  (await vesselsResp.json()).forEach(v => vesselMap[v.boat_name.toLowerCase().trim()] = v.id);

  // 2. Ordens de Serviço
  const osLines = fs.readFileSync(OS_PATH, 'latin1').split('\n');
  const osData = [];
  for (let i = 1; i < osLines.length; i++) {
    const line = osLines[i].replace(/"/g, '').trim();
    if (!line) continue;
    const cols = line.split(';');
    osData.push({
      service_order_number: cols[0],
      status: cols[1],
      client_id: clientMap[cols[2]?.toLowerCase()?.trim()] || null,
      vessel_id: vesselMap[cols[3]?.toLowerCase()?.trim()] || null,
      grand_total: parseFloat(cols[4]?.replace(',', '.')) || 0
    });
  }

  // 3. Recebíveis
  const recLines = fs.readFileSync(REC_PATH, 'latin1').split('\n');
  const recData = [];
  for (let i = 1; i < recLines.length; i++) {
    const line = recLines[i].replace(/"/g, '').trim();
    if (!line) continue;
    const cols = line.split(';');
    recData.push({
      description: cols[0],
      amount: parseFloat(cols[1]?.replace(',', '.')) || 0,
      due_date: cols[2]?.split('/').reverse().join('-'), // format to YYYY-MM-DD
      status: cols[3],
      client_id: clientMap[cols[4]?.toLowerCase()?.trim()] || null,
      currency: 'BRL'
    });
  }

  console.log(`Migrando ${osData.length} OSs e ${recData.length} Recebíveis...`);

  await fetch(`${SUPABASE_URL}/rest/v1/service_orders`, {
    method: 'POST',
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(osData)
  });

  await fetch(`${SUPABASE_URL}/rest/v1/receivables`, {
    method: 'POST',
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(recData)
  });

  console.log('Migração concluída!');
}

migrate().catch(console.error);
