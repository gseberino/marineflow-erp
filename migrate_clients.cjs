const fs = require('fs');

const CSV_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\clientes.csv';
const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

async function migrate() {
  console.log('Iniciando migração de clientes corrigida...');
  
  const content = fs.readFileSync(CSV_PATH, 'latin1');
  const lines = content.split('\n');
  
  const clients = [];
  
  for (let i = 1; i < lines.length; i++) {
    if (!lines[i].trim()) continue;
    
    const cols = lines[i].split(';');
    if (cols.length < 2) continue;
    
    const client = {
      type: cols[0] === 'PJ' ? 'company' : 'individual',
      full_name_or_company_name: cols[1]?.trim() || 'N/D',
      cpf_cnpj: cols[2]?.trim() || null,
      phone: cols[4]?.trim() || null,
      whatsapp: cols[5]?.trim() || null,
      email: cols[3]?.trim() || null,
      address_line_1: cols[6]?.trim() || null,
      address_line_2: null, // Garantindo que a chave exista
      city: cols[8]?.trim() || null,
      state: cols[9]?.trim() || null,
      postal_code: cols[7]?.trim() || null,
      country: 'Brasil',
      notes: cols[10]?.trim() || null,
      active: cols[11]?.includes('Ativo') ?? true
    };
    
    clients.push(client);
  }

  console.log(`Encontrados ${clients.length} clientes. Enviando para o Supabase...`);

  for (let i = 0; i < clients.length; i += 50) {
    const chunk = clients.slice(i, i + 50);
    const response = await fetch(`${SUPABASE_URL}/rest/v1/clients`, {
      method: 'POST',
      headers: {
        'apikey': SERVICE_ROLE_KEY,
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates'
      },
      body: JSON.stringify(chunk)
    });

    if (response.ok) {
      console.log(`Bloco ${Math.floor(i / 50) + 1} enviado com sucesso!`);
    } else {
      const error = await response.text();
      console.error(`Erro no bloco ${Math.floor(i / 50) + 1}:`, error);
    }
  }
  
  console.log('Migração de clientes concluída com sucesso!');
}

migrate().catch(console.error);
