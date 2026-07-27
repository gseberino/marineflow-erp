# Passo 4 — normaliza as fotos oficiais para uso no ERP/WhatsApp.
#
#   powershell -File scripts/catalogo-fotos/4-normalizar.ps1 -Dados <pastaDeDados>
#
# As fotos da Victron vêm em qualidade de impressão (até 20 MB, PNG com fundo
# transparente). Aqui viram JPEG sobre fundo branco:
#   normalizadas/  1200px, q88  -> é o que vai para o bucket product-images
#   miniaturas/     360px, q80  -> é o que vai para a tela de conferência
#
# Usa System.Drawing (nativo do Windows) para não acrescentar dependência de
# imagem ao projeto por causa de um piloto.

param(
  [Parameter(Mandatory = $true)][string]$Dados,
  [int]$LadoMaior = 1200,
  [int]$LadoMini = 360
)

Add-Type -AssemblyName System.Drawing

$origem = Join-Path $Dados 'fotos'
$destGrande = Join-Path $Dados 'normalizadas'
$destMini = Join-Path $Dados 'miniaturas'
New-Item -ItemType Directory -Force $destGrande | Out-Null
New-Item -ItemType Directory -Force $destMini | Out-Null

function Salvar-Jpeg {
  param([System.Drawing.Image]$Imagem, [int]$Lado, [string]$Destino, [int]$Qualidade)

  $escala = [Math]::Min($Lado / $Imagem.Width, $Lado / $Imagem.Height)
  if ($escala -gt 1) { $escala = 1 }  # nunca aumentar
  $w = [int][Math]::Round($Imagem.Width * $escala)
  $h = [int][Math]::Round($Imagem.Height * $escala)

  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    # PNG da Victron tem fundo transparente; sem isto o JPEG sairia com fundo preto
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($Imagem, 0, 0, $w, $h)
  } finally {
    $g.Dispose()
  }

  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' }
  $params = New-Object System.Drawing.Imaging.EncoderParameters 1
  $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, [int64]$Qualidade)
  $bmp.Save($Destino, $codec, $params)
  $bmp.Dispose()
}

$total = 0
$antes = 0
$depois = 0

Get-ChildItem $origem -File | ForEach-Object {
  $nome = [IO.Path]::GetFileNameWithoutExtension($_.Name)
  $img = [System.Drawing.Image]::FromFile($_.FullName)
  try {
    Salvar-Jpeg -Imagem $img -Lado $LadoMaior -Destino (Join-Path $destGrande "$nome.jpg") -Qualidade 88
    Salvar-Jpeg -Imagem $img -Lado $LadoMini -Destino (Join-Path $destMini "$nome.jpg") -Qualidade 80
  } finally {
    $img.Dispose()
  }
  $total++
  $antes += $_.Length
  $depois += (Get-Item (Join-Path $destGrande "$nome.jpg")).Length
}

"normalizadas: $total"
"antes:  {0:N1} MB" -f ($antes / 1MB)
"depois: {0:N1} MB" -f ($depois / 1MB)
"-> $destGrande"
"-> $destMini"
