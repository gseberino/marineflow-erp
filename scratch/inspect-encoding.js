const { createClient } = require('@supabase/supabase-js');

// Pegar do ambiente ou usar valores diretos para o scratch
const supabase = createClient(
  'https://zssewfqhmrlagqbfqsmb.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' // Vou usar as envs reais se disponíveis
);

async function inspectEncoding() {
  // Simplificando para rodar rápido
  console.log("Inspecionando...");
  // ...
}
