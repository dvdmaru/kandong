# 看懂 KanDong — Windows 啟動器（由「看懂.bat」呼叫）
# 1) 解除下載封鎖 2) 檢查 Visual C++ 執行階段 3) 找模型 4) 開翻譯引擎並等它就緒
# 5) 有語音辨識模型就開語音辨識引擎 6) 開播放器；關掉播放器時把這次開的引擎一起關掉
# 注意：本檔在下載包裡是 UTF-8 BOM（Windows PowerShell 5.1 沒有 BOM 會用 Big5 讀，中文會壞）

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path -Parent $PSScriptRoot
$Models = Join-Path $Root 'models'
$Logs = Join-Path $Root 'logs'
$TranslatePort = 8080
$AsrPort = 8090
$Started = @()

function Pause-Exit([int]$code) {
    Write-Host ''
    Read-Host '按 Enter 關閉這個視窗' | Out-Null
    exit $code
}

function Test-Port([int]$port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(300)) { $client.EndConnect($ar); return $true }
        return $false
    } catch { return $false } finally { $client.Close() }
}

function Quote([string]$s) { return '"' + $s + '"' }

function Show-LogTail([string]$path) {
    if (Test-Path $path) {
        Write-Host "---- $path 最後幾行 ----"
        Get-Content $path -Tail 15 | ForEach-Object { Write-Host $_ }
    }
}

Write-Host '看懂 KanDong 啟動中…'

# 1) 從網路下載的 zip 解壓後，exe/dll 會帶「來自網際網路」標記，每次開都可能跳安全警告；先解除
try { Get-ChildItem -Path $Root -Recurse -Include *.exe, *.dll | Unblock-File } catch {}

# 2) 翻譯與語音辨識引擎需要微軟 Visual C++ 執行階段（多數電腦已經有）
$sys = [Environment]::GetFolderPath('System')
$missing = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') | Where-Object { -not (Test-Path (Join-Path $sys $_)) }
if ($missing) {
    Write-Host ''
    Write-Host '這台電腦缺少微軟的「Visual C++ 可轉散發套件」，翻譯引擎需要它。'
    Write-Host '即將開啟微軟官方下載頁：請下載 X64 版（vc_redist.x64.exe）安裝，裝好後再雙擊「看懂」。'
    Start-Process 'https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist'
    Pause-Exit 1
}

# 3) 找翻譯模型：記憶體 12GB 以上優先用 7B，否則優先 1.8B
$ramGB = 0
try { $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) } catch {}
$order = if ($ramGB -ge 12) { @('Hy-MT2-7B-Q4_K_M.gguf', 'Hy-MT2-1.8B-Q4_K_M.gguf') } else { @('Hy-MT2-1.8B-Q4_K_M.gguf', 'Hy-MT2-7B-Q4_K_M.gguf') }
$model = $null
foreach ($name in $order) {
    $p = Join-Path $Models $name
    if (Test-Path $p) { $model = $p; break }
}

# 設定的翻譯伺服器若不是這台電腦（例如連區網另一台），就不開本機引擎
$conf = Join-Path $Root 'portable_config\script-opts\floattranslate.conf'
$endpoint = ''
if (Test-Path $conf) {
    $line = Get-Content $conf -Encoding UTF8 | Where-Object { $_ -match '^endpoint=' } | Select-Object -Last 1
    if ($line) { $endpoint = $line.Substring(9) }
}
$localEngine = ($endpoint -eq '') -or ($endpoint -match "^https?://(127\.0\.0\.1|localhost):$TranslatePort/")

if (-not $localEngine) {
    Write-Host "翻譯伺服器設定為 $endpoint（不是這台電腦），不開本機引擎。"
} elseif (-not (Test-Port $TranslatePort)) {
    if (-not $model) {
        Write-Host ''
        Write-Host '還沒有翻譯模型。兩種方法擇一：'
        Write-Host '  A. 雙擊「一鍵下載模型」，照畫面選擇（會自動下載並檢查檔案）'
        Write-Host '  B. 自己下載模型檔，放進 KanDong\models 資料夾（下載連結在 models\把模型放這裡.txt）'
        $ans = Read-Host '現在就開始一鍵下載嗎？輸入 Y 後按 Enter（其他鍵＝不要）'
        if ($ans -match '^[Yy]') {
            & (Join-Path $PSScriptRoot 'download-models.ps1')
            Write-Host '下載完成後，請再雙擊一次「看懂」。'
        } else {
            Start-Process explorer.exe $Models
        }
        Pause-Exit 1
    }

    # 4) 開翻譯引擎（背景執行，記錄寫在 logs 資料夾）
    New-Item -ItemType Directory -Force -Path $Logs | Out-Null
    $llama = Join-Path $Root 'engine\llama\llama-server.exe'
    $llamaLog = Join-Path $Logs 'translate-engine.log'
    $args4 = @('-m', (Quote $model), '--host', '127.0.0.1', '--port', "$TranslatePort",
        '--alias', 'tencent/Hy-MT2-GGUF', '--ctx-size', '4096', '--parallel', '1', '-ngl', '99')
    Write-Host ("開啟翻譯引擎（模型：{0}；第一次載入約 10–60 秒）" -f (Split-Path -Leaf $model))
    $proc = Start-Process -FilePath $llama -ArgumentList $args4 -WindowStyle Hidden -PassThru `
        -RedirectStandardError $llamaLog -RedirectStandardOutput (Join-Path $Logs 'translate-engine-out.log')
    $Started += $proc

    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($proc.HasExited) { break }
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$TranslatePort/health" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch {}
        Write-Host -NoNewline '.'
        Start-Sleep -Milliseconds 500
    }
    Write-Host ''
    if (-not $ready) {
        Write-Host '翻譯引擎沒有成功啟動。常見原因：記憶體不夠（請改用 1.8B 輕量模型），或模型檔下載不完整。'
        Show-LogTail $llamaLog
        foreach ($p in $Started) { try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch {} }
        Pause-Exit 1
    }
    Write-Host '翻譯引擎就緒。'
} else {
    Write-Host "已經有翻譯服務在 $TranslatePort 埠執行，直接使用它。"
}

# 5) 語音辨識（只有看沒字幕的片才需要；沒下載模型就略過）
$asrModel = Join-Path $Models 'ggml-large-v3-turbo-q5_0.bin'
if ($localEngine -and (Test-Path $asrModel) -and -not (Test-Port $AsrPort)) {
    New-Item -ItemType Directory -Force -Path $Logs | Out-Null
    $whisper = Join-Path $Root 'engine\whisper\whisper-server.exe'
    $asrArgs = @('-m', (Quote $asrModel), '--host', '127.0.0.1', '--port', "$AsrPort")
    $Started += Start-Process -FilePath $whisper -ArgumentList $asrArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardError (Join-Path $Logs 'asr-engine.log') -RedirectStandardOutput (Join-Path $Logs 'asr-engine-out.log')
    Write-Host '語音辨識引擎已啟動（沒字幕的影片會用到）。'
}

# 6) 開播放器；拖到「看懂」上的影片會一起帶進來
$mpv = Join-Path $Root 'mpv.exe'
$mpvArgs = @()
if ($args.Count -gt 0) {
    foreach ($a in $args) { $mpvArgs += (Quote $a) }
} else {
    $mpvArgs = @('--idle=yes', '--force-window=yes')
}
Write-Host '開啟播放器。看片時這個視窗請不要關（關掉播放器後會自動收掉翻譯引擎）。'
$player = Start-Process -FilePath $mpv -ArgumentList $mpvArgs -PassThru
$player.WaitForExit()

foreach ($p in $Started) { try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch {} }
exit 0
