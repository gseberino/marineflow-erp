const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

function fixString(str) {
  if (!str) return str;
  try {
    const fixed = Buffer.from(str, 'latin1').toString('utf8');
    // If it contains , it might be unfixable or standard UTF-8 replacement character.
    // Also, if original is purely ascii, fixed will equal str.
    return fixed;
  } catch (e) {
    return str;
  }
}

function hasMojibake(str) {
  if (!str) return false;
  return str.includes('Ã') || str.includes('Â');
}

const tablesToFix = [
  { name: 'clients', cols: ['name', 'address_line_1', 'city', 'notes'] },
  { name: 'vessels', cols: ['name', 'manufacturer', 'model', 'engine_brand'] },
  { name: 'suppliers', cols: ['name', 'notes'] },
  { name: 'marinas', cols: ['name', 'address_line_1'] },
  { name: 'products', cols: ['name', 'brand', 'category'] },
  { name: 'services', cols: ['name', 'category'] },
  { name: 'service_orders', cols: ['problem_description', 'internal_notes'] },
  { name: 'app_settings', cols: ['name'] } // Wait, app_settings doesn't have name. Let's omit.
];

async function run() {
  console.log('Iniciando correção de encoding (Mojibake)...');
  
  for (const table of tablesToFix.filter(t => t.name !== 'app_settings')) {
    const selectCols = ['id', ...table.cols].join(',');
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${table.name}?select=${selectCols}`, {
      headers: {
        'apikey': SERVICE_ROLE_KEY,
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`
      }
    });
    
    if (!res.ok) {
      console.error(`Erro ao buscar ${table.name}:`, await res.text());
      continue;
    }
    
    const rows = await res.json();
    let updatedCount = 0;
    
    for (const row of rows) {
      const updates = {};
      let changed = false;
      
      for (const col of table.cols) {
        if (hasMojibake(row[col])) {
          updates[col] = fixString(row[col]);
          changed = true;
        }
      }
      
      if (changed) {
        // Update record
        const updateRes = await fetch(`${SUPABASE_URL}/rest/v1/${table.name}?id=eq.${row.id}`, {
          method: 'PATCH',
          headers: {
            'apikey': SERVICE_ROLE_KEY,
            'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
          },
          body: JSON.stringify(updates)
        });
        
        if (updateRes.ok) {
          updatedCount++;
        } else {
          console.error(`Erro ao atualizar id ${row.id} na tabela ${table.name}:`, await updateRes.text());
        }
      }
    }
    
    console.log(`Tabela ${table.name}: ${updatedCount} registros corrigidos.`);
  }
  
  console.log('Correção finalizada!');
}

run().catch(console.error);
