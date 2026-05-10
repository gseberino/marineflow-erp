const fs = require('fs');

const CSV_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\marinas.csv';
const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

async function migrate() {
  console.log('Iniciando migração de marinas...');
  
  const content = fs.readFileSync(CSV_PATH, 'latin1');
  const lines = content.split('\n');
  
  const marinas = [];
  
  for (let i = 1; i < lines.length; i++) {
    if (!lines[i].trim()) continue;
    
    const cols = lines[i].split(';');
    if (cols.length < 1) continue;
    
    const marina = {
      marina_name: cols[0]?.trim() || 'N/D',
      city: cols[1]?.trim() || null,
      state: cols[2]?.trim() || null,
      contact_phone: cols[3]?.trim() || null,
      contact_email: cols[4]?.trim() || null,
      active: cols[8]?.includes('Ativo') ?? true,
      country: 'Brasil'
    };
    
    marinas.push(marina);
  }

  console.log(`Encontradas ${marinas.length} marinas. Enviando para o Supabase...`);

  const response = await fetch(`${SUPABASE_URL}/rest/v1/marinas`, {
    method: 'POST',
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates'
    },
    body: JSON.stringify(marinas)
  });

  if (response.ok) {
    console.log('Marinas migradas com sucesso!');
  } else {
    const error = await response.text();
    console.error('Erro na migração de marinas:', error);
  }
}

migrate().catch(console.error);
