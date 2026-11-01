# 看懂 KanDong — Windows 啟動器（由「看懂.bat」呼叫）
# 1) 解除下載封鎖 2) 檢查 Visual C++ 執行階段 3) 找模型 4) 開翻譯引擎並等它就緒
# 5) 有語音辨識模型就開語音辨識引擎 6) 開播放器；播放器開著時接設定選單的「換模型」要求，
#    關掉播放器時把這次開的引擎一起關掉
# 用哪個翻譯模型：設定選單（右鍵 → 設定 → 翻譯模型與伺服器）選過的優先，沒選過就依記憶體自動選。
# 還沒有模型、或引擎開不起來，播放器照樣會開，可以在設定選單下載或換模型。
# 與設定選單之間的檔案（logs 資料夾）：engine-request.txt（選單寫、這裡讀完就刪）、engine-status.txt（這裡寫）
# 注意：本檔在下載包裡是 UTF-8 BOM（Windows PowerShell 5.1 沒有 BOM 會用 Big5 讀，中文會壞）

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path -Parent $PSScriptRoot
$Models = Join-Path $Root 'models'
$Logs = Join-Path $Root 'logs'
$Config = Join-Path $Root 'portable_config'
$TranslatePort = 8080
$AsrPort = 8090
$ReqFile = Join-Path $Logs 'engine-request.txt'
$StatusFile = Join-Path $Logs 'engine-status.txt'
$Conf = Join-Path $Config 'script-opts\floattranslate.conf'
$KConf = Join-Path $Config 'script-opts\kandong_settings.conf'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

$script:Engine = $null
$script:EngineModel = ''
$script:EngineError = ''
$script:Asr = $null
$script:State = 'none'
$script:LastRequestId = ''

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
    if (Test-Path -LiteralPath $path) {
        Write-Host "---- $path 最後幾行 ----"
        Get-Content -LiteralPath $path -Tail 15 | ForEach-Object { Write-Host $_ }
    }
}

# 設定檔（key=value）：同一個 key 有好幾行時最後一行算數（與 mpv 一致）
function Get-ConfValue([string]$path, [string]$key) {
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    $line = [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8) | Where-Object { $_.StartsWith("$key=") } | Select-Object -Last 1
    if ($line) { return $line.Substring($key.Length + 1) }
    return ''
}

function Set-ConfValue([string]$path, [string]$key, [string]$value) {
    $lines = @()
    if (Test-Path -LiteralPath $path) { $lines = @([IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith("$key=")) { $lines[$i] = "$key=$value"; $found = $true }
    }
    if (-not $found) { $lines += "$key=$value" }
    [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $Utf8NoBom)
}

# 狀態檔給播放器裡的設定選單看：先寫暫存檔再換名，選單不會讀到寫一半的內容
function Write-Status([string]$id, [string]$state, [string]$model, [string]$err) {
    $text = "id=$id`nstate=$state`nmodel=$model`nerror=$err`n"
    $tmp = "$StatusFile.tmp"
    for ($i = 0; $i -lt 10; $i++) {
        try {
            [IO.File]::WriteAllText($tmp, $text, $Utf8NoBom)
            if ([IO.File]::Exists($StatusFile)) { [IO.File]::Replace($tmp, $StatusFile, $null) }
            else { [IO.File]::Move($tmp, $StatusFile) }
            return
        } catch { Start-Sleep -Milliseconds 100 }  # 設定選單剛好在讀：等一下再換
    }
    try { [IO.File]::WriteAllText($StatusFile, $text, $Utf8NoBom) } catch {}
}

# 依記憶體挑內建模型（12GB 以上 7B，否則 1.8B）；都沒有就挑 models 裡第一個 .gguf
function Get-AutoModel {
    $ramGB = 0
    try { $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) } catch {}
    $order = if ($ramGB -ge 12) { @('Hy-MT2-7B-Q4_K_M.gguf', 'Hy-MT2-1.8B-Q4_K_M.gguf') } else { @('Hy-MT2-1.8B-Q4_K_M.gguf', 'Hy-MT2-7B-Q4_K_M.gguf') }
    foreach ($name in $order) {
        $p = Join-Path $Models $name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $any = Get-ChildItem -LiteralPath $Models -Filter '*.gguf' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'mmproj' } | Select-Object -First 1
    if ($any) { return $any.FullName }
    return ''
}

# 設定選單選過的優先；檔案不在了就退回自動選
function Get-ChosenModel {
    $p = (Get-ConfValue $KConf 'model_path').Trim().Trim('"')
    try {
        if ($p -ne '' -and -not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $Models $p }
        if ($p -ne '' -and (Test-Path -LiteralPath $p)) { return $p }
    } catch {}  # 路徑裡有不合法字元：當作沒選
    return (Get-AutoModel)
}

function Stop-Engine {
    $had = [bool]$script:Engine
    if ($script:Engine) {
        try { if (-not $script:Engine.HasExited) { Stop-Process -Id $script:Engine.Id -Force } } catch {}
        try { $script:Engine.WaitForExit(10000) | Out-Null } catch {}
    }
    $script:Engine = $null
    $script:EngineModel = ''
    if (-not $had) { return }  # 8080 上若是別人的服務，不用等它關
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Test-Port $TranslatePort)) { break }
        Start-Sleep -Milliseconds 250
    }
}

# 上次「看懂」視窗被直接按 X 關掉時，隱藏的引擎不會跟著結束；開機前把留下來的收掉
# （只收 KanDong\engine 底下的執行檔，不碰使用者自己開的其他服務）
function Stop-Leftovers {
    $engineDir = (Join-Path $Root 'engine') + '\'
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe' OR Name='whisper-server.exe'" -ErrorAction Stop
        foreach ($p in $procs) {
            if ($p.ExecutablePath -and $p.ExecutablePath.StartsWith($engineDir, [StringComparison]::OrdinalIgnoreCase)) {
                Write-Host ("收掉上次留下的引擎：{0}（PID {1}）" -f $p.Name, $p.ProcessId)
                try { Stop-Process -Id $p.ProcessId -Force } catch {}
            }
        }
    } catch {}
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Test-Port $TranslatePort)) { break }
        Start-Sleep -Milliseconds 250
    }
}

# 開翻譯引擎並等它就緒；失敗時 $script:EngineError 是白話原因
function Start-Engine([string]$model) {
    $script:EngineError = ''
    if (Test-Port $TranslatePort) {
        $script:EngineError = "${TranslatePort} 埠被別的程式占用"
        return $false
    }
    New-Item -ItemType Directory -Force -Path $Logs | Out-Null
    $llama = Join-Path $Root 'engine\llama\llama-server.exe'
    $llamaLog = Join-Path $Logs 'translate-engine.log'
    $engineArgs = @('-m', (Quote $model), '--host', '127.0.0.1', '--port', "$TranslatePort",
        '--alias', 'tencent/Hy-MT2-GGUF', '--ctx-size', '4096', '--parallel', '1', '-ngl', '99')
    Write-Host ("開啟翻譯引擎（模型：{0}；第一次載入約 10–60 秒）" -f (Split-Path -Leaf $model))
    try {
        $proc = Start-Process -FilePath $llama -ArgumentList $engineArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardError $llamaLog -RedirectStandardOutput (Join-Path $Logs 'translate-engine-out.log')
    } catch {
        $script:EngineError = '翻譯引擎開不起來（engine 資料夾的檔案不見了，或被防毒軟體擋掉）：' + $_.Exception.Message
        return $false
    }
    $script:Engine = $proc
    for ($i = 0; $i -lt 240; $i++) {
        if ($proc.HasExited) { break }
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$TranslatePort/health" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) {
                $script:EngineModel = $model
                Write-Host ''
                Write-Host '翻譯引擎就緒。'
                return $true
            }
        } catch {}
        Write-Host -NoNewline '.'
        Start-Sleep -Milliseconds 500
    }
    Write-Host ''
    Stop-Engine
    $script:EngineError = '模型載入失敗（常見原因：記憶體不夠，或模型檔不完整）'
    return $false
}

# 語音辨識：有模型、8090 沒人用、這次還沒開過才開
function Start-Asr {
    $asrModel = Join-Path $Models 'ggml-large-v3-turbo-q5_0.bin'
    if (($script:Asr -and -not $script:Asr.HasExited) -or -not (Test-Path -LiteralPath $asrModel) -or (Test-Port $AsrPort)) { return }
    New-Item -ItemType Directory -Force -Path $Logs | Out-Null
    $whisper = Join-Path $Root 'engine\whisper\whisper-server.exe'
    $asrArgs = @('-m', (Quote $asrModel), '--host', '127.0.0.1', '--port', "$AsrPort")
    try {
        $script:Asr = Start-Process -FilePath $whisper -ArgumentList $asrArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardError (Join-Path $Logs 'asr-engine.log') -RedirectStandardOutput (Join-Path $Logs 'asr-engine-out.log')
        Write-Host '語音辨識引擎已啟動（沒字幕的影片會用到）。'
    } catch {
        $script:Asr = $null
        Write-Host ('語音辨識引擎開不起來：' + $_.Exception.Message)
    }
}

function Stop-All {
    Stop-Engine
    if ($script:Asr) { try { if (-not $script:Asr.HasExited) { Stop-Process -Id $script:Asr.Id -Force } } catch {} }
    Remove-Item -LiteralPath $StatusFile, "$StatusFile.tmp", $ReqFile -Force -ErrorAction SilentlyContinue
}

# 處理設定選單的一個要求（id／action／model 三行）
function Invoke-Request {
    $claimed = "$ReqFile.processing"
    try {
        if ([IO.File]::Exists($claimed)) { [IO.File]::Delete($claimed) }
        [IO.File]::Move($ReqFile, $claimed)
    } catch { return }  # 選單剛好在寫：下一輪再處理
    $text = ''
    try { $text = [IO.File]::ReadAllText($claimed, [Text.Encoding]::UTF8) } catch {}
    try { [IO.File]::Delete($claimed) } catch {}
    $req = @{}
    foreach ($line in ($text -split "`r?`n")) {
        $i = $line.IndexOf('=')
        if ($i -gt 0) { $req[$line.Substring(0, $i)] = $line.Substring($i + 1) }
    }
    $id = [string]$req['id']
    $script:LastRequestId = $id  # 出意外時外層用它回報，選單才不會一直等
    $action = [string]$req['action']
    $model = [string]$req['model']
    if ($action -eq 'switch') {
        if ($script:State -eq 'external') {
            Write-Status $id 'external' '' "${TranslatePort} 埠上的翻譯服務不是看懂開的"
            return
        }
        if (-not (Test-Path -LiteralPath $model)) {
            Write-Status $id $script:State $script:EngineModel "找不到模型檔 $model"
            return
        }
        $prev = $script:EngineModel
        Write-Status $id 'loading' $model ''
        Write-Host ''
        Write-Host ("換模型：{0}" -f (Split-Path -Leaf $model))
        Stop-Engine
        if (Start-Engine $model) {
            $script:State = 'ready'
            Write-Status $id 'ready' $script:EngineModel ''
        } else {
            $err = $script:EngineError
            if ($prev -ne '' -and $prev -ne $model -and (Start-Engine $prev)) {
                $script:State = 'ready'
                Write-Status $id 'ready' $script:EngineModel $err
            } else {
                $script:State = 'failed'
                Write-Status $id 'failed' '' $err
            }
        }
    } elseif ($action -eq 'stop') {
        Stop-Engine
        if ($script:State -ne 'external') { $script:State = 'stopped' }
        Write-Status $id $script:State '' ''
        Write-Host '已關閉本機翻譯引擎（改用其他翻譯伺服器）。'
    } elseif ($action -eq 'asr') {
        Start-Asr
        Write-Status $id $script:State $script:EngineModel ''
    } else {
        Write-Status $id $script:State $script:EngineModel "看不懂的要求：$action"
    }
}

Write-Host '看懂 KanDong 啟動中…'

# 1) 從網路下載的 zip 解壓後，exe/dll 會帶「來自網際網路」標記，每次開都可能跳安全警告；先解除
try {
    Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $_.Extension -eq '.exe' -or $_.Extension -eq '.dll' } | Unblock-File
} catch {}

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

New-Item -ItemType Directory -Force -Path $Models, $Logs | Out-Null
Remove-Item -LiteralPath $ReqFile, "$ReqFile.processing" -Force -ErrorAction SilentlyContinue
Stop-Leftovers
if (-not (Test-Path -LiteralPath $KConf)) {
    Set-ConfValue $KConf 'model_path' ''
}

# 3)＋4) 設定的翻譯伺服器若不是這台電腦（例如連區網另一台、Ollama），就不開本機引擎
$endpoint = Get-ConfValue $Conf 'endpoint'
$localEngine = ($endpoint -eq '') -or ($endpoint -match "^https?://(127\.0\.0\.1|localhost):$TranslatePort/")

if (-not $localEngine) {
    $script:State = 'remote'
    Write-Host "翻譯伺服器設定為 $endpoint（不是這台電腦），不開本機引擎。"
} elseif (Test-Port $TranslatePort) {
    $script:State = 'external'
    Write-Host "已經有翻譯服務在 $TranslatePort 埠執行，直接使用它。"
} else {
    $model = Get-ChosenModel
    if ($model -eq '') {
        Write-Host ''
        Write-Host '還沒有翻譯模型。播放器開啟後：按右鍵 → 設定 → 翻譯模型與伺服器，就能直接下載。'
        Write-Host '（也可以雙擊「一鍵下載模型」，或自己把模型檔放進 KanDong\models 資料夾）'
        $script:State = 'none'
    } elseif (Start-Engine $model) {
        $script:State = 'ready'
    } else {
        $firstError = $script:EngineError
        # 設定選單選的模型開不起來（例如記憶體不夠）→ 清掉選擇、改用自動選的模型再試一次
        $auto = Get-AutoModel
        if ((Get-ConfValue $KConf 'model_path') -ne '' -and $auto -ne '' -and $auto -ne $model) {
            Write-Host ("選擇的模型 {0} 開不起來：{1}" -f (Split-Path -Leaf $model), $firstError)
            Write-Host ("改用自動選擇的模型 {0} 再試一次。" -f (Split-Path -Leaf $auto))
            Set-ConfValue $KConf 'model_path' ''
            if (Start-Engine $auto) { $script:State = 'ready' }
        }
        if ($script:State -ne 'ready') {
            $script:State = 'failed'
            $why = if ($script:EngineError) { $script:EngineError } else { $firstError }
            Write-Host "翻譯引擎沒有成功啟動：$why"
            Show-LogTail (Join-Path $Logs 'translate-engine.log')
            Write-Host '播放器照樣會開：可以在右鍵 → 設定 → 翻譯模型與伺服器 換成 1.8B 輕量模型。'
        }
    }
}

# 5) 語音辨識（只有看沒字幕的片才需要；沒下載模型就略過）
if ($localEngine) { Start-Asr }
Write-Status '0' $script:State $script:EngineModel $script:EngineError

# 6) 開播放器；拖到「看懂」上的影片會一起帶進來
$mpv = Join-Path $Root 'mpv.exe'
$mpvArgs = @(
    (Quote "--script-opts-append=kandong_settings-models_dir=$Models"),
    (Quote "--script-opts-append=kandong_settings-control_dir=$Logs"),
    "--script-opts-append=kandong_settings-engine_port=$TranslatePort"
)
if ($args.Count -gt 0) {
    foreach ($a in $args) { $mpvArgs += (Quote $a) }
} else {
    $mpvArgs += @('--idle=yes', '--force-window=yes')
}
Write-Host '開啟播放器。看片時這個視窗請不要關（關掉播放器後會自動收掉翻譯引擎）。'
try {
    $player = Start-Process -FilePath $mpv -ArgumentList $mpvArgs -PassThru
    while (-not $player.HasExited) {
        if (Test-Path -LiteralPath $ReqFile) {
            try { Invoke-Request } catch {
                Write-Host ("處理設定選單的要求時出錯：{0}" -f $_.Exception.Message)
                $script:State = if (Test-Port $TranslatePort) { $script:State } else { 'failed' }
                Write-Status $script:LastRequestId $script:State $script:EngineModel $_.Exception.Message
            }
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    Stop-All
}
exit 0
