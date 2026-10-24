# 看懂 KanDong — 一鍵下載模型（由「一鍵下載模型.bat」或啟動器呼叫）
# 從 Hugging Face 官方下載，存進 KanDong\models；下載可以中斷後續傳；完成後比對官方 SHA256，不符就刪掉。
# 模型清單要跟 mac/download-models.sh 一致（打包前有檢查）。
# 注意：本檔在下載包裡是 UTF-8 BOM。

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path -Parent $PSScriptRoot
$Models = Join-Path $Root 'models'
New-Item -ItemType Directory -Force -Path $Models | Out-Null

# MODELS-BEGIN（名稱｜檔名｜網址｜SHA256｜大小 bytes）
$Catalog = @(
    @{ Key = '1'; Name = '翻譯模型・標準（Hy-MT2 7B，約 4.6GB）：翻得比較好，建議記憶體 16GB 以上'
       File = 'Hy-MT2-7B-Q4_K_M.gguf'
       Url = 'https://huggingface.co/tencent/Hy-MT2-7B-GGUF/resolve/main/Hy-MT2-7B-Q4_K_M.gguf'
       Sha = '9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b'; Size = 4624648896 },
    @{ Key = '2'; Name = '翻譯模型・輕量（Hy-MT2 1.8B，約 1.1GB）：快很多，記憶體 8GB 或電腦較舊選這個'
       File = 'Hy-MT2-1.8B-Q4_K_M.gguf'
       Url = 'https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/main/Hy-MT2-1.8B-Q4_K_M.gguf'
       Sha = 'dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699'; Size = 1133080448 },
    @{ Key = '3'; Name = '語音辨識模型（Whisper large-v3-turbo，約 574MB）：只有看「沒字幕的影片」才需要'
       File = 'ggml-large-v3-turbo-q5_0.bin'
       Url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin'
       Sha = '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2'; Size = 574041195 }
)
# MODELS-END

function Get-One($m) {
    $dest = Join-Path $Models $m.File
    if (Test-Path $dest) {
        Write-Host "已經有 $($m.File)，略過。"
        return $true
    }
    $part = "$dest.part"
    try {
        $drive = Get-PSDrive -Name ((Split-Path -Qualifier $Models).TrimEnd(':'))
        if ($drive.Free -lt ($m.Size + 500MB)) {
            Write-Host ("磁碟空間不夠：需要約 {0:N1} GB，現在只剩 {1:N1} GB。" -f ($m.Size / 1GB), ($drive.Free / 1GB))
            return $false
        }
    } catch {}  # 網路磁碟等查不到剩餘空間：略過檢查
    Write-Host ''
    Write-Host "下載 $($m.File)（可以隨時關掉視窗，下次會從中斷的地方接著下載）"
    $curl = Join-Path ([Environment]::GetFolderPath('System')) 'curl.exe'
    if (Test-Path $curl) {
        & $curl -L --fail --retry 5 --retry-delay 3 -C - -o $part $m.Url
        if ($LASTEXITCODE -ne 0) { Write-Host "下載失敗（curl 代碼 $LASTEXITCODE），請檢查網路後重試。"; return $false }
    } else {
        Start-BitsTransfer -Source $m.Url -Destination $part
    }
    Write-Host '檢查檔案是否完整（大檔要等一下）…'
    $hash = (Get-FileHash -Algorithm SHA256 -Path $part).Hash.ToLower()
    if ($hash -ne $m.Sha) {
        Remove-Item $part -Force
        Write-Host '檔案檢查不符（可能下載中被改動或不完整），已刪除，請再試一次。'
        return $false
    }
    Move-Item $part $dest -Force
    Write-Host "完成：$($m.File)"
    return $true
}

$ramGB = 0
try { $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) } catch {}
Write-Host ''
Write-Host '===== 看懂：一鍵下載模型 ====='
if ($ramGB -gt 0) {
    $hint = if ($ramGB -ge 12) { '建議選 1（標準）' } else { '建議選 2（輕量）' }
    Write-Host "這台電腦記憶體約 $ramGB GB，$hint。"
}
Write-Host '模型都從 Hugging Face 官方下載，存在 KanDong\models 資料夾。'
Write-Host ''
foreach ($m in $Catalog) { Write-Host "  [$($m.Key)] $($m.Name)" }
Write-Host ''
$pick = Read-Host '輸入要下載的編號（可以一次輸入多個，例如 13），再按 Enter'
$chosen = $Catalog | Where-Object { $pick -like "*$($_.Key)*" }
if (-not $chosen) { Write-Host '沒有選到任何模型。'; exit 1 }
$ok = $true
foreach ($m in $chosen) { if (-not (Get-One $m)) { $ok = $false } }
Write-Host ''
if ($ok) { Write-Host '全部完成！現在可以雙擊「看懂」開始看片。' } else { Write-Host '有模型沒有下載成功，可以再雙擊「一鍵下載模型」重試。' }
