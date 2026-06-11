# Túnel estável para a Evolution API (Cloudflare Quick Tunnel + auto-update)

A Evolution roda localmente em `http://localhost:8081`. As Edge Functions do
Supabase (na nuvem) precisam alcançá-la para **enviar** mensagens, então usamos
um túnel Cloudflare. O Quick Tunnel é gratuito e não exige domínio, mas gera uma
**URL nova a cada reinício**.

O script [`start-evolution-tunnel.ps1`](./start-evolution-tunnel.ps1) resolve isso:
mantém o túnel no ar e, sempre que a URL muda, atualiza sozinho o secret
`EVOLUTION_API_URL` no Supabase. Assim o envio continua funcionando após reinícios.

> **Nota:** o **recebimento** de mensagens NÃO depende deste túnel — a Evolution
> envia os webhooks direto para a URL pública fixa do Supabase. O túnel é usado
> apenas no sentido Supabase → Evolution (envio, checagem de número, etc.).

## Uso manual

```powershell
# Deixe esta janela aberta enquanto quiser o túnel ativo
powershell -ExecutionPolicy Bypass -File "D:\PC\marineflow-erp\infra\evolution\start-evolution-tunnel.ps1"
```

## Iniciar automaticamente com o Windows (recomendado)

Registra uma tarefa que sobe o túnel no logon do usuário, em segundo plano:

```powershell
$script = "D:\PC\marineflow-erp\infra\evolution\start-evolution-tunnel.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
  -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName "EvolutionTunnel" -Action $action -Trigger $trigger `
  -Settings $settings -Description "Cloudflare tunnel + auto-update EVOLUTION_API_URL"
```

Iniciar agora sem reiniciar:
```powershell
Start-ScheduledTask -TaskName "EvolutionTunnel"
```

Ver estado / parar / remover:
```powershell
Get-ScheduledTask -TaskName "EvolutionTunnel"
Stop-ScheduledTask  -TaskName "EvolutionTunnel"
Unregister-ScheduledTask -TaskName "EvolutionTunnel" -Confirm:$false
```

## Pré-requisitos

- `cloudflared.exe` em `C:\cloudflared\cloudflared.exe`
- Supabase CLI autenticado (o mesmo usado em `supabase secrets set`)
- Containers da Evolution rodando (`docker ps --filter name=evolution`)

## Solução definitiva (futuro)

Para uma URL **fixa de verdade** (sem depender de auto-update), migre para:
- **Cloudflare Named Tunnel** com um domínio próprio adicionado ao Cloudflare, ou
- **VPS** hospedando a Evolution com domínio + TLS (ver `decisao-topologia.md`).

Enquanto não houver domínio, o auto-update acima é a melhor opção de custo zero.
