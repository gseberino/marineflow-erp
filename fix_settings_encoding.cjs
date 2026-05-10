const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

function fixString(str) {
  if (!str) return str;
  try {
    return Buffer.from(str, 'latin1').toString('utf8');
  } catch (e) {
    return str;
  }
}

function hasMojibake(str) {
  if (!str) return false;
  return str.includes('Ã') || str.includes('Â');
}

async function run() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/app_settings?select=key,value`, {
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`
    }
  });
  
  const rows = await res.json();
  let updatedCount = 0;
  
  for (const row of rows) {
    if (hasMojibake(row.value)) {
      const fixed = fixString(row.value);
      const updateRes = await fetch(`${SUPABASE_URL}/rest/v1/app_settings?key=eq.${row.key}`, {
        method: 'PATCH',
        headers: {
          'apikey': SERVICE_ROLE_KEY,
          'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal'
        },
        body: JSON.stringify({ value: fixed })
      });
      if (updateRes.ok) updatedCount++;
    }
  }
  
  console.log(`app_settings: ${updatedCount} registros corrigidos.`);
}

run().catch(console.error);
