const fs = require('fs');

const PROD_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\produtos (1).csv';
const SERV_PATH = 'D:\\Dowloads SSD\\EXPORTAÇÃO MARINEFLOW\\servicos.csv';
const SUPABASE_URL = 'https://vmareepfbgocyleknrgg.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtYXJlZXBmYmdvY3lsZWtucmdnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODMzMjE2MywiZXhwIjoyMDkzOTA4MTYzfQ.2fdg5zi2oWsuRedakJNOrzRy2xIiAeCnNF_E-JCH8m8';

async function migrate() {
  console.log('Iniciando migração de produtos e serviços...');
  
  // 1. Produtos
  const prodContent = fs.readFileSync(PROD_PATH, 'latin1');
  const prodLines = prodContent.split('\n');
  const products = [];
  for (let i = 1; i < prodLines.length; i++) {
    if (!prodLines[i].trim()) continue;
    const cols = prodLines[i].split(';');
    products.push({
      sku: cols[0]?.trim() || null,
      product_name: cols[1]?.trim() || 'N/D',
      category: cols[2]?.trim() || null,
      brand: cols[3]?.trim() || null,
      unit: cols[4]?.trim() || null,
      cost_price: parseFloat(cols[5]?.replace(',', '.')) || 0,
      cost_currency: cols[6]?.trim() || 'BRL',
      sale_price: parseFloat(cols[7]?.replace(',', '.')) || 0,
      sale_currency: cols[8]?.trim() || 'BRL',
      stock_quantity: parseInt(cols[9]) || 0,
      minimum_stock: parseInt(cols[10]) || 0,
      location_bin: cols[11]?.trim() || null,
      notes: cols[12]?.trim() || null,
      active: cols[13]?.includes('Ativo') ?? true
    });
  }

  // 2. Serviços
  const servContent = fs.readFileSync(SERV_PATH, 'latin1');
  const servLines = servContent.split('\n');
  const services = [];
  for (let i = 1; i < servLines.length; i++) {
    if (!servLines[i].trim()) continue;
    const cols = servLines[i].split(';');
    services.push({
      service_name: cols[0]?.trim() || 'N/D',
      category: cols[1]?.trim() || null,
      billing_unit: cols[2]?.trim() || 'visit',
      default_price: parseFloat(cols[3]?.replace(',', '.')) || 0,
      currency: cols[4]?.trim() || 'BRL',
      description: cols[5]?.trim() || null,
      active: cols[6]?.includes('Ativo') ?? true
    });
  }

  console.log(`Enviando ${products.length} produtos e ${services.length} serviços...`);

  const pResp = await fetch(`${SUPABASE_URL}/rest/v1/products`, {
    method: 'POST',
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(products)
  });
  console.log('Produtos:', pResp.ok ? 'Sucesso' : 'Erro ' + await pResp.text());

  const sResp = await fetch(`${SUPABASE_URL}/rest/v1/services`, {
    method: 'POST',
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(services)
  });
  console.log('Serviços:', sResp.ok ? 'Sucesso' : 'Erro ' + await sResp.text());
}

migrate().catch(console.error);
