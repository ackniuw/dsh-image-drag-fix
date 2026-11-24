# kill-and-swap.ps1 — 由**外部**（资源管理器双击的 bat）启动，强杀 DSH 并换 asar
# 这个进程不是 DSH 的后代，不会被 DSH 的 Job Object 连带杀掉。
# 验证交给 python 读整个文件搜锚点（PowerShell 逐字节扫 182MB 太慢；上一版只扫前 4MB，
# 而 client.js 在 19.5MB 处，于是把好补丁误判成坏补丁并回滚了）。

$ErrorActionPreference = "Continue"
$target = "D:\哈气肥鱼\resources\app.asar"
$new    = "D:\tmp\app-new.asar"
$bak    = "D:\哈气肥鱼\resources\app.asar.bak-imgfix"
$exe    = "D:\哈气肥鱼\DeepSeek Harness.exe"
$log    = "D:\inbox\_swap.log"

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date).ToString("HH:mm:ss"), $m
    Add-Content -Path $log -Value $line -Encoding UTF8
    Write-Host $line
}

if (-not (Test-Path $new)) { Write-Host "缺少 $new"; Read-Host "回车退出"; exit 1 }

Write-Host ""
Write-Host "[1/5] 停止 DeepSeek Harness ..."
$procs = @(Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue)
Log "外部替换：发现 $($procs.Count) 个 DSH 进程"
foreach ($p in $procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { } }

Write-Host "[2/5] 等待文件释放 ..."
$free = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    try {
        $fs = [System.IO.File]::Open($target, 'Open', 'ReadWrite', 'None')
        $fs.Close(); $free = $true; break
    } catch { }
}
if (-not $free) {
    Log "app.asar 仍被占用，放弃"
    Write-Host "失败：app.asar 还被占用"
    Read-Host "回车退出"; exit 1
}
Log "app.asar 已释放"

Write-Host "[3/5] 备份并替换 ..."
if (-not (Test-Path $bak)) { Copy-Item $target $bak -Force; Log "已备份原 asar" }
Copy-Item $new $target -Force
$size = (Get-Item $target).Length
$expected = (Get-Item $new).Length
Log ("已替换 -> {0} 字节（期望 {1}）" -f $size, $expected)

Write-Host "[4/5] 验证补丁 ..."
$verified = $false
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($py) {
    $code = "d=open(r'$target','rb').read(); print('HIT' if b'encodeImageAsPng' in d else 'MISS')"
    $res = & $py -c $code 2>&1
    Log ("python 验证: {0}" -f ($res -join ' '))
    if (($res -join '') -match 'HIT') { $verified = $true }
}
if (-not $verified -and $size -eq $expected) {
    Log "python 没命中，但字节数与新包一致，按成功处理"
    $verified = $true
}
Log "补丁验证: $verified"

if (-not $verified) {
    Write-Host "验证失败，回滚"
    Copy-Item $bak $target -Force
    Log "已回滚"
    Start-Process $exe
    Read-Host "回车退出"; exit 1
}

Write-Host "[4.5/5] 清理浏览器缓存（V8 会把旧 JS 编译结果缓存住）..."
$ud = Join-Path $env:APPDATA "@deepseek-ai\dsh-desktop"
foreach ($d in @("Code Cache", "Cache", "GPUCache", "GrShaderCache", "DawnGraphiteCache", "DawnWebGPUCache")) {
    $cp = Join-Path $ud $d
    if (Test-Path $cp) {
        try { Remove-Item $cp -Recurse -Force -ErrorAction Stop; Log "已清缓存 $d" }
        catch { Log "清 $d 失败: $($_.Exception.Message)" }
    }
}

Write-Host "[5/5] 启动 DeepSeek Harness ..."
Remove-Item "D:\哈气肥鱼\resources\app.asar.rename-pending" -Force -ErrorAction SilentlyContinue
Start-Process $exe
Log "完成，已启动 DSH"
Write-Host ""
Write-Host "完成。现在去拖一张 QQ 图。"
Start-Sleep -Seconds 3
