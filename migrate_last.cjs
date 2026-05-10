const fs = require('fs');

const COB_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\cobranças.csv';
const PAG_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\pagaveis_2026-05-09.csv';

const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

async function migrate() {
  console.log('Finalizando migração de cobranças e pagáveis...');

  // 1. Mapas
  const clientsResp = await fetch(`${SUPABASE_URL}/rest/v1/clients?select=id,full_name_or_company_name`, {
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` }
  });
  const clientMap = {};
  (await clientsResp.json()).forEach(c => clientMap[c.full_name_or_company_name.toLowerCase().trim()] = c.id);

  const suppliersResp = await fetch(`${SUPABASE_URL}/rest/v1/suppliers?select=id,supplier_name`, {
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` }
  });
  const supplierMap = {};
  (await suppliersResp.json()).forEach(s => supplierMap[s.supplier_name.toLowerCase().trim()] = s.id);

  // 2. Cobranças
  const cobLines = fs.readFileSync(COB_PATH, 'latin1').split('\n');
  const cobData = [];
  for (let i = 1; i < cobLines.length; i++) {
    const line = cobLines[i].replace(/"/g, '').trim();
    if (!line) continue;
    const cols = line.split(','); // Cobranças parece usar vírgula pela amostra anterior
    cobData.push({
      client_id: clientMap[cols[0]?.toLowerCase()?.trim()] || null,
      description: `Cobranca ref ${cols[1]}`,
      amount: parseFloat(cols[2]) || 0,
      due_date: cols[3]?.split('/').reverse().join('-'),
      status: cols[4]?.toLowerCase() || 'pending'
    });
  }

  // 3. Pagáveis
  const pagLines = fs.readFileSync(PAG_PATH, 'latin1').split('\n');
  const pagData = [];
  for (let i = 1; i < pagLines.length; i++) {
    const line = pagLines[i].replace(/"/g, '').trim();
    if (!line) continue;
    const cols = line.split(';');
    pagData.push({
      supplier_name: cols[0],
      supplier_id: supplierMap[cols[0]?.toLowerCase()?.trim()] || null,
      description: cols[1],
      amount: parseFloat(cols[2]?.replace(',', '.')) || 0,
      due_date: cols[3]?.split('/').reverse().join('-'),
      status: cols[4]?.toLowerCase() || 'pending',
      currency: 'BRL'
    });
  }

  console.log(`Migrando ${cobData.length} Cobranças e ${pagData.length} Pagáveis...`);

  await fetch(`${SUPABASE_URL}/rest/v1/collections`, {
    method: 'POST',
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(cobData)
  });

  await fetch(`${SUPABASE_URL}/rest/v1/payables`, {
    method: 'POST',
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(pagData)
  });

  console.log('Finalizado!');
}

migrate().catch(console.error);
