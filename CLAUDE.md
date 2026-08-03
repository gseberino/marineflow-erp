
## Deploy de edge function neste repo

`supabase functions deploy` usa Docker para empacotar. Quando o Docker Desktop não está
rodando, o CLI imprime "WARNING: Docker is not running" e **fica pendurado sem erro** —
parece lentidão, mas nunca termina.

Use sempre `--use-api`, que empacota no servidor e dispensa o Docker:

    npx supabase functions deploy <nome> --project-ref okurngvcodmljjicopdp --use-api

Sintoma de que o deploy não passou: `list_edge_functions` mostra a versão antiga. Vale
conferir depois de deployar — o CLI travado não devolve código de erro.
