
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!supabaseUrl || !supabaseKey) {
  console.error("Variáveis de ambiente SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY não encontradas.")
  process.exit(1)
}

const supabase = createClient(supabaseUrl, supabaseKey)

async function getDebugLog() {
  const { data, error } = await supabase
    .from('app_settings')
    .select('value')
    .eq('key', 'debug_last_webhook')
    .maybeSingle()

  if (error) {
    console.error("Erro ao buscar log:", error)
    return
  }

  if (data) {
    console.log("=== LOG DE DEBUG ENCONTRADO ===")
    console.log(JSON.stringify(JSON.parse(data.value), null, 2))
  } else {
    console.log("Nenhum log de debug encontrado na tabela app_settings.")
  }
}

getDebugLog()
