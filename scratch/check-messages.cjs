const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = "https://zssewfqhmrlagqbfqsmb.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpzc2V3ZnFobXJsYWdxYmZxc21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1NDI0MzksImV4cCI6MjA5MTExODQzOX0.HZ7pknqpfKkKpq0yGZeolu5Tt4CII5W76WmOsTr0gSY";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function checkRecentMessages() {
  const { data, error } = await supabase
    .from('whatsapp_messages')
    .select('id, created_at, phone_normalized, body, direction')
    .order('created_at', { ascending: false })
    .limit(5);
  
  if (error) {
    console.error('Error:', error);
    return;
  }

  console.log('Recent WhatsApp Messages:');
  data.forEach(m => {
    console.log(`[${m.created_at}] ${m.direction}: ${m.phone_normalized} - ${m.body?.slice(0, 50)}`);
  });
}

checkRecentMessages();
