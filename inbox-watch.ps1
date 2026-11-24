# inbox-watch.ps1 — 把拖进来的任意格式图片自动转成 DSH 能收的 PNG
#
# 为什么需要它：
#   DSH 前端只认浏览器上报的 MIME（image/png|jpeg|webp|gif），没有魔数兜底。
#   从 QQ/微信/资源管理器拖进来时 file.type 可能是空的，于是直接被拒。
#   但文件只要落在磁盘上，格式对我就不是问题（read_image 用文件头嗅探，不是看后缀）。
#
# 用法：
#   pwsh -File inbox-watch.ps1                    常驻，盯 D:\inbox
#   pwsh -File inbox-watch.ps1 -Once D:\inbox     只转现存文件然后退出
#
# 输出：<Inbox>\png\*.png，转完自动在资源管理器选中最新一张（3 秒内只弹一次）

param(
    [string]$Inbox = "D:\inbox",
    [string]$OutDir = "",
    [switch]$Once,
    [int]$SettleMs = 1000
)

$ErrorActionPreference = "Continue"
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $Inbox "png" }
$Tool = Join-Path $PSScriptRoot "img2png.py"
$Log  = Join-Path $Inbox "_watch.log"

New-Item -ItemType Directory -Force -Path $Inbox  | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$RasterExt = @(".png",".jpg",".jpeg",".jpe",".jfif",".gif",".webp",".bmp",".dib",
               ".tif",".tiff",".heic",".heif",".avif",".ico",".tga",".ppm",".pgm")

function Get-Python {
    foreach ($cand in @("python","py")) {
        $c = Get-Command $cand -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

function Write-Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date).ToString("HH:mm:ss"), $msg
    Add-Content -Path $Log -Value $line -Encoding UTF8
    Write-Host $line
}

$script:lastShow = [datetime]::MinValue

function Show-Latest {
    if (((Get-Date) - $script:lastShow).TotalSeconds -lt 3) { return }
    $script:lastShow = Get-Date
    $latest = Get-ChildItem $OutDir -Filter *.png -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        try { Start-Process explorer.exe -ArgumentList "/select,`"$($latest.FullName)`"" } catch { }
    }
}

function Convert-Image([string]$path) {
    if (-not (Test-Path $path)) { return }
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($RasterExt -notcontains $ext) { return }

    # 等文件写完（句柄可独占打开即视为写完）
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        try { $fs = [System.IO.File]::Open($path,'Open','Read','None'); $fs.Close(); break }
        catch { Start-Sleep -Milliseconds 250 }
    }

    $py = Get-Python
    if (-not $py) { Write-Log "找不到 python，跳过：$path"; return }

    $out = & $py $Tool $path $OutDir 2>&1
    $ok = ($out | Where-Object { $_ -like "OK*" } | Select-Object -First 1)
    if ($ok) {
        Write-Log "已转 $(Split-Path $path -Leaf)  ->  $ok"
    } else {
        $why = ($out | Where-Object { $_ -like "FAIL*" } | Select-Object -First 1)
        Write-Log "失败 $(Split-Path $path -Leaf)  $why"
    }
}

if ($Once) {
    Get-ChildItem $Inbox -File -ErrorAction SilentlyContinue |
        Where-Object { $RasterExt -contains $_.Extension.ToLowerInvariant() } |
        ForEach-Object { Convert-Image $_.FullName }
    Show-Latest
    return
}

Write-Log "开始监听 $Inbox  ->  $OutDir"
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $Inbox
$watcher.Filter = "*.*"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

try {
    while ($true) {
        $r = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Created, 1500)
        if ($r.TimedOut) { continue }
        $p = Join-Path $Inbox $r.Name
        Start-Sleep -Milliseconds $SettleMs
        Convert-Image $p
        Show-Latest
    }
} finally {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    Write-Log "已停止监听"
}
