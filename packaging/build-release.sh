#!/bin/bash
# 看懂 KanDong — 產生 GitHub Release 用的兩個下載檔
#
# 用法：bash packaging/build-release.sh <Windows 執行檔資料夾> [輸出資料夾]
#   <Windows 執行檔資料夾> 需含：mpv.exe、mpv.com、ffmpeg.exe、vulkan-1.dll（可選 mpv/fonts.conf）
#     mpv     ：zhongfly/mpv-winbuild（x86_64）
#     ffmpeg  ：BtbN/FFmpeg-Builds（win64-gpl）
#     vulkan-1.dll：LunarG Vulkan Runtime（x64）
#   輸出：KanDong-windows-x64.zip、KanDong-mac.zip、SHA256SUMS.txt
#
# 檔名固定不帶版本號，官網用 https://github.com/<owner>/kandong/releases/latest/download/<檔名>
# 就永遠指向最新版。版本號寫在包內的 VERSION 檔。
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "用法：bash $0 <Windows 執行檔資料夾> [輸出資料夾]"
  exit 1
fi
WIN_BIN="$(cd "$1" && pwd)"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${2:-${REPO}/dist}"
VERSION="$(cat "${REPO}/VERSION")"

for f in mpv.exe mpv.com ffmpeg.exe vulkan-1.dll; do
  [ -f "${WIN_BIN}/${f}" ] || { echo "缺 ${WIN_BIN}/${f}"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${OUT}"
rm -f "${OUT}/KanDong-windows-x64.zip" "${OUT}/KanDong-mac.zip" "${OUT}/SHA256SUMS.txt"

# 先把 uosc 抓一份（驗 SHA256）放進 ui/vendor，兩個包共用、使用者端不必再上網抓
UOSC_SHA256="$(grep '^UOSC_SHA256=' "${REPO}/ui/install-uosc.sh" | cut -d'"' -f2)"
UOSC_VERSION="$(grep '^UOSC_VERSION=' "${REPO}/ui/install-uosc.sh" | cut -d'"' -f2)"
mkdir -p "${WORK}/vendor"
curl -fsSL -o "${WORK}/vendor/uosc.zip" "https://github.com/tomasklaen/uosc/releases/download/${UOSC_VERSION}/uosc.zip"
[ "$(shasum -a 256 "${WORK}/vendor/uosc.zip" | awk '{print $1}')" = "${UOSC_SHA256}" ] || { echo "uosc.zip SHA256 不符"; exit 1; }

common_docs() {  # $1＝包根目錄
  mkdir -p "$1/licenses"
  cp "${REPO}/LICENSE" "$1/licenses/KanDong-LICENSE.txt"
  cp "${REPO}/THIRD_PARTY.md" "$1/licenses/THIRD_PARTY.md"
  cp "${REPO}/packaging/licenses/"* "$1/licenses/"
  echo "${VERSION}" > "$1/VERSION"
}

# ── Windows：portable 資料夾，解壓即用 ──
W="${WORK}/win/KanDong"
mkdir -p "${W}"
cp "${WIN_BIN}/mpv.exe" "${WIN_BIN}/mpv.com" "${WIN_BIN}/ffmpeg.exe" "${WIN_BIN}/vulkan-1.dll" "${W}/"
if [ -f "${WIN_BIN}/mpv/fonts.conf" ]; then
  mkdir -p "${W}/mpv" && cp "${WIN_BIN}/mpv/fonts.conf" "${W}/mpv/"
fi
mkdir -p "${WORK}/ui-win"
cp "${REPO}/ui/"*.conf "${REPO}/ui/uosc-zh-TW.json" "${REPO}/ui/install-uosc.sh" "${WORK}/ui-win/"
mkdir -p "${WORK}/ui-win/vendor" && cp "${WORK}/vendor/uosc.zip" "${WORK}/ui-win/vendor/"
bash "${WORK}/ui-win/install-uosc.sh" "${W}/portable_config" >/dev/null
rm -f "${W}/portable_config/scripts/uosc/bin/ziggy-darwin" "${W}/portable_config/scripts/uosc/bin/ziggy-linux"
cp "${REPO}/scripts/floattranslate.lua" "${W}/portable_config/scripts/"
cp "${REPO}/script-opts/floattranslate.conf" "${W}/portable_config/script-opts/"

# 內附引擎（固定版本、驗 SHA256）：llama.cpp b10204（與 Mac 實測同版）Vulkan 版＋whisper.cpp b5454
fetch_engine() {  # $1 url  $2 sha256  $3 解壓目錄
  curl -fsSL -o "${WORK}/engine.zip" "$1"
  [ "$(shasum -a 256 "${WORK}/engine.zip" | awk '{print $1}')" = "$2" ] || { echo "引擎 SHA256 不符：$1"; exit 1; }
  rm -rf "$3" && mkdir -p "$3" && unzip -q "${WORK}/engine.zip" -d "$3"
}
fetch_engine https://github.com/ggml-org/llama.cpp/releases/download/b10204/llama-b10204-bin-win-vulkan-x64.zip \
  6f950679d1b2c696033d1c0c59dc595793504aaad89a43f1184b782263414ddd "${WORK}/llama"
fetch_engine https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-x64.zip \
  6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb "${WORK}/whisper"
mkdir -p "${W}/engine/llama" "${W}/engine/whisper"
cp "${WORK}/llama/llama-server.exe" "${WORK}/llama/"*.dll "${W}/engine/llama/"
cp "${WORK}/whisper/Release/whisper-server.exe" "${WORK}/whisper/Release/"*.dll "${W}/engine/whisper/"

# 啟動器：.ps1 轉 UTF-8 BOM＋CRLF（Windows PowerShell 5.1 沒 BOM 會用 Big5 讀中文）；.bat 轉 CRLF
mkdir -p "${W}/scripts" "${W}/models"
for f in launch.ps1 download-models.ps1; do
  { printf '\357\273\277'; sed 's/$/\r/' "${REPO}/packaging/windows/scripts/${f}"; } > "${W}/scripts/${f}"
done
for f in 看懂.bat 一鍵下載模型.bat; do
  sed 's/$/\r/' "${REPO}/packaging/windows/${f}" > "${W}/${f}"
done
sed 's/$/\r/' "${REPO}/packaging/models-README.txt" > "${W}/models/把模型放這裡.txt"
# Windows 記事本友善：使用說明轉 CRLF
sed 's/$/\r/' "${REPO}/packaging/windows-README.txt" > "${W}/使用說明.txt"
common_docs "${W}"
python3 "${REPO}/packaging/mkzip.py" "${OUT}/KanDong-windows-x64.zip" "${WORK}/win" KanDong

# ── Mac：設定＋啟動器（mpv 用 Homebrew 裝）──
M="${WORK}/mac/KanDong"
mkdir -p "${M}/ui/vendor"
cp -R "${REPO}/scripts" "${REPO}/script-opts" "${REPO}/mac" "${REPO}/server" "${M}/"
cp "${REPO}/ui/"*.conf "${REPO}/ui/uosc-zh-TW.json" "${REPO}/ui/install-uosc.sh" "${M}/ui/"
cp "${WORK}/vendor/uosc.zip" "${M}/ui/vendor/"
cp "${REPO}/packaging/mac-README.txt" "${M}/使用說明.txt"
mkdir -p "${M}/models"
cp "${REPO}/packaging/models-README.txt" "${M}/models/把模型放這裡.txt"
cat > "${M}/看懂.command" <<'EOF'
#!/bin/bash
# 雙擊啟動看懂 KanDong（會開一個 Terminal 視窗，播放時請保持開著）
exec bash "$(cd "$(dirname "$0")" && pwd)/mac/kandong.sh" "$@"
EOF
cat > "${M}/一鍵下載模型.command" <<'EOF'
#!/bin/bash
# 雙擊下載看懂需要的模型（從 Hugging Face 官方下載到 KanDong/models，會檢查檔案是否完整）
bash "$(cd "$(dirname "$0")" && pwd)/mac/download-models.sh"
echo ""
read -r -p "按 Enter 關閉這個視窗" _
EOF
chmod +x "${M}/看懂.command" "${M}/一鍵下載模型.command" "${M}/mac/"*.sh "${M}/server/"*.sh "${M}/ui/install-uosc.sh"
common_docs "${M}"
python3 "${REPO}/packaging/mkzip.py" "${OUT}/KanDong-mac.zip" "${WORK}/mac" KanDong

(cd "${OUT}" && shasum -a 256 KanDong-windows-x64.zip KanDong-mac.zip > SHA256SUMS.txt)
echo "版本 ${VERSION}"
ls -la "${OUT}"
cat "${OUT}/SHA256SUMS.txt"
