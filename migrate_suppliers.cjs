const fs = require('fs');

const CSV_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\fornecedores.csv';
const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

async function migrate() {
  console.log('Iniciando migração de fornecedores...');
  
  const content = fs.readFileSync(CSV_PATH, 'latin1');
  const lines = content.split('\n');
  
  const suppliers = [];
  
  for (let i = 1; i < lines.length; i++) {
    if (!lines[i].trim()) continue;
    
    const cols = lines[i].split(';');
    if (cols.length < 1) continue;
    
    const supplier = {
      supplier_name: cols[0]?.trim() || 'N/D',
      trade_name: cols[1]?.trim() || null,
      cnpj_cpf: cols[2]?.trim() || null,
      contact_phone: cols[4]?.trim() || null,
      contact_email: cols[5]?.trim() || null,
      city: cols[6]?.trim() || null,
      state: cols[7]?.trim() || null,
      active: cols[9]?.includes('Ativo') ?? true,
      country: 'Brasil'
    };
    
    suppliers.push(supplier);
  }

  console.log(`Encontrados ${suppliers.length} fornecedores. Enviando para o Supabase...`);

  const response = await fetch(`${SUPABASE_URL}/rest/v1/suppliers`, {
    method: 'POST',
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(suppliers)
  });

  if (response.ok) {
    console.log('Fornecedores migrados com sucesso!');
  } else {
    const error = await response.text();
    console.error('Erro na migração de fornecedores:', error);
  }
}

migrate().catch(console.error);
