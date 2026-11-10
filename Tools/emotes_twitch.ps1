# Guild Union - emoticonos de Twitch (BTTV, FrankerFaceZ y 7TV) sin instalar nada
#
# Se usa con doble clic en "Tools\Emoticonos de Twitch.bat", con el juego cerrado.
#   1. Pregunta el canal (o varios, separados por comas).
#   2. Baja sus emoticonos, los convierte al formato del juego (.tga de 32x32) y los guarda en
#      Media\Twitch.
#   3. Escribe EmotePack.lua: al abrir el juego, el maestro solo tiene que pulsar "Activar pack"
#      en Configuración > Chat > Importar (no hay que copiar ni pegar nada).
#   4. Deja en el Escritorio "GuildUnion con emotes.zip" para pasárselo a los demás (las imágenes
#      tienen que estar en el ordenador de todos).
#
# Solo usa lo que trae Windows (PowerShell y System.Drawing).
param(
    [string]$Canales = "",
    [int]$Max = 150,
    [switch]$Global,
    [switch]$SinZip,
    [string]$SoloPack = ""     # (pruebas) escribe TwitchEmotes.lua desde un JSON y termina
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root = Split-Path -Parent $PSScriptRoot           # ...\Interface\AddOns\GuildUnion
$Out = Join-Path $Root "Media\Twitch"
$Manifest = Join-Path $Out "emotes.json"
$PackFile = Join-Path $Root "EmotePack.lua"
$WowPath = "Interface\AddOns\GuildUnion\Media\Twitch\"
$UA = @{ "User-Agent" = "GuildUnion-emotes" }

function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c }

function Get-Json($url) {
    return Invoke-RestMethod -Uri $url -Headers $UA -UseBasicParsing -TimeoutSec 25
}

# ---------------------------------------------------------------------------
# Lista de emoticonos de un canal: @{ code = "PePega"; url = "https://..." }
# ---------------------------------------------------------------------------
function Get-TwitchId($login) {
    # FrankerFaceZ da el número del canal sin hacer falta cuenta de Twitch
    try {
        $r = Get-Json ("https://api.frankerfacez.com/v1/room/" + $login)
        if ($r.room.twitch_id) { return [string]$r.room.twitch_id }
    } catch {}
    try {
        $t = (Invoke-WebRequest -Uri ("https://decapi.me/twitch/id/" + $login) -Headers $UA -UseBasicParsing -TimeoutSec 25).Content.Trim()
        if ($t -match '^\d+$') { return $t }
    } catch {}
    return $null
}

function Get-ChannelEmotes($login, $includeGlobal) {
    $list = New-Object System.Collections.ArrayList
    $id = Get-TwitchId $login
    if (-not $id) { Say ("  No encuentro el canal '" + $login + "' en Twitch.") "Red"; return $list }
    # 7TV
    try {
        $d = Get-Json ("https://7tv.io/v3/users/twitch/" + $id)
        foreach ($e in $d.emote_set.emotes) {
            [void]$list.Add(@{ code = $e.name; url = ("https:" + $e.data.host.url + "/2x.png") })
        }
    } catch { Say "  (7TV: el canal no tiene o no responde)" }
    # BTTV
    try {
        $d = Get-Json ("https://api.betterttv.net/3/cached/users/twitch/" + $id)
        foreach ($e in @($d.channelEmotes) + @($d.sharedEmotes)) {
            if ($e) { [void]$list.Add(@{ code = $e.code; url = ("https://cdn.betterttv.net/emote/" + $e.id + "/2x") }) }
        }
    } catch { Say "  (BTTV: el canal no tiene o no responde)" }
    if ($includeGlobal) {
        try {
            foreach ($e in (Get-Json "https://api.betterttv.net/3/cached/emotes/global")) {
                [void]$list.Add(@{ code = $e.code; url = ("https://cdn.betterttv.net/emote/" + $e.id + "/2x") })
            }
        } catch { Say "  (BTTV globales: no responde)" }
    }
    # FrankerFaceZ
    try {
        $d = Get-Json ("https://api.frankerfacez.com/v1/room/" + $login)
        foreach ($p in $d.sets.PSObject.Properties) {
            foreach ($e in $p.Value.emoticons) {
                $u = $e.urls.'2'; if (-not $u) { $u = $e.urls.'1' }; if (-not $u) { $u = $e.urls.'4' }
                if ($u) {
                    if ($u.StartsWith("//")) { $u = "https:" + $u }
                    [void]$list.Add(@{ code = $e.name; url = $u })
                }
            }
        }
    } catch { Say "  (FFZ: el canal no tiene o no responde)" }
    return $list
}

# ---------------------------------------------------------------------------
# Imagen -> .tga de 32x32 con transparencia (el formato que lee el juego)
# ---------------------------------------------------------------------------
function Save-Tga($bytes, $path) {
    Add-Type -AssemblyName System.Drawing
    $ms = New-Object System.IO.MemoryStream(, $bytes)
    $img = [System.Drawing.Image]::FromStream($ms)
    try {
        # animados: el primer fotograma (el juego no anima imágenes)
        try { $img.SelectActiveFrame([System.Drawing.Imaging.FrameDimension]::Time, 0) | Out-Null } catch {}
        $S = 32
        $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        # sin deformar: lo más grande que quepa, centrado
        $k = [Math]::Min($S / $img.Width, $S / $img.Height)
        $w = [int][Math]::Max(1, [Math]::Round($img.Width * $k)); $h = [int][Math]::Max(1, [Math]::Round($img.Height * $k))
        $g.DrawImage($img, [int](($S - $w) / 2), [int](($S - $h) / 2), $w, $h)
        $g.Dispose()
        Write-Tga $bmp $path
        $bmp.Dispose()
    } finally { $img.Dispose(); $ms.Dispose() }
}

function Write-Tga($bmp, $path) {
    $W = $bmp.Width; $H = $bmp.Height
    $data = New-Object byte[] (18 + $W * $H * 4)
    $data[2] = 2                                   # sin comprimir, color verdadero
    $data[12] = $W % 256; $data[13] = [Math]::Floor($W / 256)
    $data[14] = $H % 256; $data[15] = [Math]::Floor($H / 256)
    $data[16] = 32                                 # 32 bits
    $data[17] = 8                                  # 8 bits de transparencia, origen abajo a la izquierda
    $i = 18
    for ($y = $H - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $W; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $data[$i] = $c.B; $data[$i + 1] = $c.G; $data[$i + 2] = $c.R; $data[$i + 3] = $c.A
            $i += 4
        }
    }
    [System.IO.File]::WriteAllBytes($path, $data)
}

# ---------------------------------------------------------------------------
# EmotePack.lua: lo lee el addon al abrir el juego
# ---------------------------------------------------------------------------
function Write-Pack($entries, $channels) {
    # (el mismo formato que espera el addon: HU.EMOTE_PACK = { channel = "...", list = { {codigo, ruta}, ... } })
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("-- Guild Union - pack de emoticonos de Twitch (lo escribe Tools\Emoticonos de Twitch.bat)")
    [void]$lines.Add("local _, HU = ...")
    [void]$lines.Add("HU.EMOTE_PACK = { channel = `"" + ($channels -replace '[^A-Za-z0-9_, ]', '') + "`", list = {")
    foreach ($e in $entries) {
        [void]$lines.Add("    { `"" + $e.code + "`", `"" + ($WowPath -replace '\\', '\\') + $e.file + "`" },")
    }
    [void]$lines.Add("} }")
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PackFile, ($lines -join "`r`n") + "`r`n", $utf8)
}

if ($SoloPack -ne "") {
    $m = Get-Content $SoloPack -Raw | ConvertFrom-Json
    Write-Pack $m.emotes $m.canales
    exit 0
}

# ---------------------------------------------------------------------------
Say ""
Say "  ===  Guild Union: emoticonos de Twitch  ===" "Yellow"
Say ""
Say "  Cierra el juego antes de seguir (las imagenes nuevas solo se cargan al abrirlo)."
Say ""
if ($Canales -eq "") { $Canales = Read-Host "  Canal de Twitch (o varios separados por comas)" }
$logins = @($Canales -split '[,; ]+' | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim().ToLower() -replace '^.*twitch\.tv/', '' })
if ($logins.Count -eq 0) { Say "  No has escrito ningun canal." "Red"; exit 1 }
if (-not $Global) {
    $a = Read-Host "  Anadir tambien los globales de BTTV (PepeLaugh, monkaS...)? (s/n)"
    if ($a -match '^[sSyY]') { $Global = $true }
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
# los que ya había (de otras veces): se mantienen
$have = @{}
$order = New-Object System.Collections.ArrayList
if (Test-Path $Manifest) {
    try {
        foreach ($e in (Get-Content $Manifest -Raw | ConvertFrom-Json).emotes) {
            if ((Test-Path (Join-Path $Out ($e.file + ".tga"))) -and -not $have.ContainsKey($e.code)) {
                $have[$e.code] = $e.file; [void]$order.Add(@{ code = $e.code; file = $e.file })
            }
        }
    } catch {}
}
$prev = $order.Count
$usedFiles = @{}
foreach ($e in $order) { $usedFiles[$e.file.ToLower()] = $true }

foreach ($login in $logins) {
    Say ""
    Say ("  Canal: " + $login) "Cyan"
    $found = Get-ChannelEmotes $login $Global
    Say ("  Encontrados: " + $found.Count)
    foreach ($e in $found) {
        if ($order.Count -ge $Max) { break }
        $code = [string]$e.code
        # el addon los busca como palabras: sin espacios ni símbolos raros
        if ($code -notmatch '^[A-Za-z0-9_:()\-]{2,20}$' -or $have.ContainsKey($code)) { continue }
        $file = $code -replace '[^A-Za-z0-9_]', '_'
        $n = 2
        while ($usedFiles.ContainsKey($file.ToLower())) { $file = ($code -replace '[^A-Za-z0-9_]', '_') + "_" + $n; $n++ }
        try {
            $bytes = (Invoke-WebRequest -Uri $e.url -Headers $UA -UseBasicParsing -TimeoutSec 25).Content
            Save-Tga $bytes (Join-Path $Out ($file + ".tga"))
            $have[$code] = $file; $usedFiles[$file.ToLower()] = $true
            [void]$order.Add(@{ code = $code; file = $file })
            Write-Host ("    ok  " + $code) -ForegroundColor Green
        } catch {
            Write-Host ("    no se pudo  " + $code) -ForegroundColor DarkYellow
        }
    }
}

$added = $order.Count - $prev
$all = @($logins) -join ", "
$m = @{ canales = $all; emotes = @($order | ForEach-Object { @{ code = $_.code; file = $_.file } }) }
($m | ConvertTo-Json -Depth 4) | Set-Content -Path $Manifest -Encoding UTF8
Write-Pack $order $all

Say ""
Say ("  Nuevos: " + $added + "   Total: " + $order.Count + " (maximo " + $Max + ")") "Yellow"

if (-not $SinZip) {
    try {
        $desk = [Environment]::GetFolderPath("Desktop")
        $zip = Join-Path $desk "GuildUnion con emotes.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Compress-Archive -Path $Root -DestinationPath $zip -CompressionLevel Optimal
        Say ""
        Say ("  Para los demas: " + $zip) "Yellow"
        Say "  Pasadselo (Discord, etc.). Cada uno borra su carpeta GuildUnion y pone la de este zip."
    } catch { Say ("  No se pudo crear el zip: " + $_.Exception.Message) "Red" }
}
Say ""
Say "  Listo. Abre el juego > Configuracion > Chat > Importar > boton del pack de Twitch." "Green"
Say ""
