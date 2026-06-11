<#
.SYNOPSIS
  Mantém um Cloudflare Quick Tunnel apontando para a Evolution API local e
  atualiza automaticamente o secret EVOLUTION_API_URL no Supabase sempre que
  a URL do túnel mudar (o Quick Tunnel gera uma URL nova a cada reinício).

.DESCRIPTION
  Resolve o problema do túnel efêmero sem precisar de domínio próprio:
    1. Inicia o cloudflared para http://localhost:<porta da Evolution>
    2. Captura a URL pública gerada (https://xxxx.trycloudflare.com)
    3. Atualiza o secret EVOLUTION_API_URL no projeto Supabase via CLI
    4. Mantém o túnel rodando; se cair, reinicia e repete (nova URL + update)

  Para iniciar junto com o Windows, registre como tarefa agendada (ver README).

.NOTES
  Requisitos: cloudflared.exe, Supabase CLI autenticado, Evolution rodando.
#>

# ─── Configuração (ajuste se necessário) ─────────────────────────────────────
$CloudflaredPath = "C:\cloudflared\cloudflared.exe"
$EvolutionPort   = 8081
$ProjectRef      = "okurngvcodmljjicopdp"
$LogFile         = "$env:TEMP\cloudflared-evolution.log"
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log($msg) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg"
}

if (-not (Test-Path $CloudflaredPath)) {
    Write-Log "ERRO: cloudflared não encontrado em $CloudflaredPath"
    exit 1
}

Write-Log "Iniciando supervisor do túnel Evolution (porta $EvolutionPort, projeto $ProjectRef)"

while ($true) {
    # Verifica se a Evolution está respondendo localmente antes de subir o túnel
    try {
        Invoke-WebRequest -Uri "http://localhost:$EvolutionPort/" -TimeoutSec 5 -UseBasicParsing | Out-Null
    } catch {
        Write-Log "Evolution não respondeu em localhost:$EvolutionPort. Tentando de novo em 15s..."
        Start-Sleep -Seconds 15
        continue
    }

    if (Test-Path $LogFile) { Remove-Item $LogFile -Force -ErrorAction SilentlyContinue }

    Write-Log "Subindo cloudflared..."
    $proc = Start-Process -FilePath $CloudflaredPath `
        -ArgumentList "tunnel --url http://localhost:$EvolutionPort --no-autoupdate" `
        -RedirectStandardError $LogFile -RedirectStandardOutput "$LogFile.out" `
        -NoNewWindow -PassThru

    # Aguarda a URL aparecer no log (até 40s)
    $tunnelUrl = $null
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path $LogFile) {
            $match = Select-String -Path $LogFile -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) {
                $tunnelUrl = $match.Matches[0].Value
                break
            }
        }
    }

    if (-not $tunnelUrl) {
        Write-Log "Não consegui obter a URL do túnel. Encerrando cloudflared e tentando novamente."
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 10
        continue
    }

    Write-Log "Túnel ativo: $tunnelUrl"

    # Atualiza o secret no Supabase
    Write-Log "Atualizando EVOLUTION_API_URL no Supabase..."
    & supabase secrets set "EVOLUTION_API_URL=$tunnelUrl" --project-ref $ProjectRef 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Secret atualizado com sucesso."
    } else {
        Write-Log "AVISO: falha ao atualizar o secret (verifique login do Supabase CLI)."
    }

    Write-Log "Túnel rodando. Monitorando o processo (Ctrl+C para encerrar)..."
    Wait-Process -Id $proc.Id
    Write-Log "cloudflared encerrou. Reiniciando o túnel em 5s..."
    Start-Sleep -Seconds 5
}
