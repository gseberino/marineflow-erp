const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = "https://zssewfqhmrlagqbfqsmb.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpzc2V3ZnFobXJsYWdxYmZxc21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1NDI0MzksImV4cCI6MjA5MTExODQzOX0.HZ7pknqpfKkKpq0yGZeolu5Tt4CII5W76WmOsTr0gSY";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function checkAuditLog() {
  const { data, error } = await supabase
    .from('audit_log')
    .select('*')
    .or('table_name.eq.whatsapp_leads,table_name.eq.whatsapp_messages,action.ilike.%whatsapp%')
    .order('changed_at', { ascending: false })
    .limit(10);
  
  if (error) {
    console.error('Error:', error);
    return;
  }

  console.log('Audit Log (WhatsApp related):');
  data.forEach(l => {
    console.log(`[${l.changed_at}] ${l.table_name} - ${l.action}: ${l.reason}`);
  });
}

checkAuditLog();
