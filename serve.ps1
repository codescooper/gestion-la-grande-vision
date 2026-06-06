# =====================================================================
#  La Grande Vision — Serveur local (http://localhost)
#  Sert l'application depuis une origine stable et securisee, ce qui
#  fiabilise la memorisation du dossier de sauvegarde automatique.
#  Aucune installation requise : PowerShell est integre a Windows.
#  Le serveur ecoute UNIQUEMENT sur 127.0.0.1 (jamais expose au reseau).
# =====================================================================

param(
  [int]$Port = 8765,
  [switch]$NoBrowser   # usage interne (tests) : ne pas ouvrir le navigateur
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appFile = 'la-grande-vision.html'
$url = "http://localhost:$Port/$appFile"

# --- Si le serveur tourne deja sur ce port, on ouvre juste le navigateur ---
$alreadyRunning = $false
try {
  $probe = New-Object System.Net.Sockets.TcpClient
  $probe.Connect('127.0.0.1', $Port)
  $alreadyRunning = $true
  $probe.Close()
} catch { }
if ($alreadyRunning) {
  if (-not $NoBrowser) { Start-Process $url }
  return
}

# --- Types MIME ---
$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.htm'  = 'text/html; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.mjs'  = 'text/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.ico'  = 'image/x-icon'
  '.webp' = 'image/webp'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
  '.ttf'  = 'font/ttf'
  '.map'  = 'application/json; charset=utf-8'
  '.txt'  = 'text/plain; charset=utf-8'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try {
  $listener.Start()
} catch {
  Write-Host "Impossible de demarrer le serveur sur le port $Port." -ForegroundColor Red
  Write-Host $_.Exception.Message
  Write-Host "Le port est peut-etre deja utilise. Fermez l'autre fenetre du serveur et reessayez."
  Start-Sleep -Seconds 8
  return
}

$rootFull = [System.IO.Path]::GetFullPath($root)

Write-Host ""
Write-Host "  La Grande Vision - serveur local actif" -ForegroundColor Cyan
Write-Host "  Application : $url"
Write-Host "  Dossier     : $root"
Write-Host ""
Write-Host "  NE FERMEZ PAS cette fenetre pendant l'utilisation de l'application." -ForegroundColor Yellow
Write-Host "  (La fermer arrete le serveur. Reduisez-la simplement.)"
Write-Host ""

if (-not $NoBrowser) { Start-Process $url }

while ($listener.IsListening) {
  try {
    $context = $listener.GetContext()
  } catch {
    break
  }
  $req  = $context.Request
  $resp = $context.Response
  try {
    if ($req.HttpMethod -ne 'GET' -and $req.HttpMethod -ne 'HEAD') {
      $resp.StatusCode = 405
      $resp.Close()
      continue
    }

    $relPath = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
    if ([string]::IsNullOrEmpty($relPath) -or $relPath -eq '/') { $relPath = "/$appFile" }

    $candidate = Join-Path $root ($relPath.TrimStart('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $fullPath  = [System.IO.Path]::GetFullPath($candidate)

    # Anti-traversal : le fichier doit rester dans le dossier de l'application
    if (-not $fullPath.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      $resp.StatusCode = 403
      $resp.Close()
      continue
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
      $resp.StatusCode = 404
      $msg = [System.Text.Encoding]::UTF8.GetBytes('404 - Fichier introuvable')
      $resp.ContentType = 'text/plain; charset=utf-8'
      $resp.ContentLength64 = $msg.Length
      $resp.OutputStream.Write($msg, 0, $msg.Length)
      $resp.Close()
      continue
    }

    $ext = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    $ct  = $mime[$ext]
    if (-not $ct) { $ct = 'application/octet-stream' }

    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    $resp.ContentType = $ct
    $resp.Headers['Cache-Control'] = 'no-cache'
    $resp.ContentLength64 = $bytes.Length
    if ($req.HttpMethod -eq 'GET') {
      $resp.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    $resp.Close()
  } catch {
    try { $resp.StatusCode = 500; $resp.Close() } catch { }
  }
}

$listener.Close()
