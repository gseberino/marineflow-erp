const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  'https://zssewfqhmrlagqbfqsmb.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpzc2V3ZnFobXJsYWdxYmZxc21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1NDI0MzksImV4cCI6MjA5MTExODQzOX0.HZ7pknqpfKkKpq0yGZeolu5Tt4CII5W76WmOsTr0gSY'
);

async function fixBrokenCharacters() {
  console.log("Iniciando varredura de correção...");
  
  // Lista de correções conhecidas
  const corrections = [
    { from: 'Tubar?o', to: 'Tubarão' },
    { from: 'Can?ado', to: 'Cançado' },
    { from: 'S?o ', to: 'São ' },
    { from: 'Concei??o', to: 'Conceição' },
    { from: 'Ribeir?o', to: 'Ribeirão' },
    { from: 'Crist?v?o', to: 'Cristóvão' },
    { from: 'Jo?o', to: 'João' },
    { from: 'Ant?nio', to: 'Antônio' },
    { from: 'Jos?', to: 'José' }
  ];

  for (const item of corrections) {
    console.log(`Corrigindo ${item.from} -> ${item.to}...`);
    
    // Atualizar Clientes
    const { count: clientCount } = await supabase
      .from('clients')
      .update({ 
        full_name_or_company_name: item.to,
        city: item.to 
      })
      .or(`full_name_or_company_name.ilike.%${item.from}%,city.ilike.%${item.from}%`);

    // Atualizar Leads
    await supabase
      .from('whatsapp_leads')
      .update({ display_name: item.to })
      .ilike('display_name', `%${item.from}%`);
  }
  
  console.log("Correção finalizada!");
}

// Nota: Como não tenho a Service Key aqui para um UPDATE em massa, 
// vou sugerir que você rode esse ajuste via interface ou me forneça permissão para uma função SQL.
fixBrokenCharacters();
