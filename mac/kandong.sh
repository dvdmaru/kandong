#!/bin/bash
# 看懂 KanDong — Mac 啟動器（下載版雙擊「看懂.command」就是跑這支）
#
# 用法：bash mac/kandong.sh [影片檔]
#   不給影片＝開一個空視窗，把影片拖進去就開始播（也可以按 o 開檔）。
#
# 做的事：
#   1. 把介面與翻譯腳本裝進 ~/.config/kandong/mpv/（不動你原本的 ~/.config/mpv）
#      翻譯設定 script-opts/floattranslate.conf 只在第一次放範本，之後你改的內容不會被蓋掉。
#   2. 設定的翻譯伺服器是這台電腦（預設）時：自動開翻譯引擎（模型在 KanDong/models），
#      有語音辨識模型就一起開；關掉播放器時把這次開的引擎收掉。
#      伺服器設成區網別台電腦時：不開本機引擎，直接播放。
#
# 需要：Homebrew 安裝的 mpv、llama.cpp（brew install mpv ffmpeg llama.cpp whisper-cpp）
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
PKG="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${KANDONG_CONFIG_DIR:-${HOME}/.config/kandong/mpv}"
MODELS="${KANDONG_MODELS_DIR:-${PKG}/models}"
LOGS="${KANDONG_LOG_DIR:-${HOME}/Library/Logs/KanDong}"
TPORT=8080
APORT=8090
STARTED=()

if ! command -v mpv >/dev/null 2>&1; then
  echo "找不到 mpv。請先安裝 Homebrew（https://brew.sh），再在 Terminal 跑："
  echo "  brew install mpv ffmpeg llama.cpp whisper-cpp"
  exit 1
fi

# 第一個參數若不是 mpv 選項，就當影片檔先檢查，找不到時講白話
if [ $# -ge 1 ] && [ "${1#-}" = "$1" ] && [ ! -e "$1" ]; then
  echo "找不到影片檔：$1"
  echo "提示：不給影片直接啟動，會開一個空視窗，把影片拖進去即可。"
  exit 1
fi

# ── 1. 裝介面與翻譯腳本 ──
mkdir -p "${CONFIG}/scripts" "${CONFIG}/script-opts"
if [ "$(cat "${CONFIG}/scripts/uosc/.kandong-version" 2>/dev/null || true)" = "5.13.0" ]; then
  cp "${PKG}/ui/uosc.conf" "${PKG}/ui/uosc-zh-TW.json" "${CONFIG}/script-opts/"
  cp "${PKG}/ui/input.conf" "${PKG}/ui/mpv.conf" "${CONFIG}/"
else
  bash "${PKG}/ui/install-uosc.sh" "${CONFIG}"
fi
cp "${PKG}/scripts/floattranslate.lua" "${CONFIG}/scripts/"
CONF="${CONFIG}/script-opts/floattranslate.conf"
if [ ! -f "${CONF}" ]; then
  (umask 077 && cp "${PKG}/script-opts/floattranslate.conf" "${CONF}")
fi

# ── 2. 本機引擎 ──
port_open() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
cleanup() {
  for pid in ${STARTED[@]+"${STARTED[@]}"}; do kill "${pid}" 2>/dev/null || true; done
}
trap cleanup EXIT

ENDPOINT="$(grep -E '^endpoint=' "${CONF}" | tail -1 | cut -d= -f2- || true)"
case "${ENDPOINT:-http://127.0.0.1:${TPORT}}" in
  *://127.0.0.1:${TPORT}/*|*://localhost:${TPORT}/*) LOCAL_ENGINE=1 ;;
  *) LOCAL_ENGINE=0 ;;
esac

if [ "${LOCAL_ENGINE}" = "1" ] && [ "${KANDONG_NO_ENGINE:-0}" != "1" ]; then
  if port_open "${TPORT}"; then
    echo "已經有翻譯服務在 ${TPORT} 埠執行，直接使用它。"
  else
    ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
    if [ "${ram_gb}" -ge 12 ]; then order="Hy-MT2-7B-Q4_K_M.gguf Hy-MT2-1.8B-Q4_K_M.gguf"
    else order="Hy-MT2-1.8B-Q4_K_M.gguf Hy-MT2-7B-Q4_K_M.gguf"; fi
    MODEL=""
    for name in ${order}; do
      if [ -f "${MODELS}/${name}" ]; then MODEL="${MODELS}/${name}"; break; fi
    done
    if [ -z "${MODEL}" ]; then
      echo ""
      echo "還沒有翻譯模型。兩種方法擇一："
      echo "  A. 雙擊「一鍵下載模型.command」，照畫面選擇（會自動下載並檢查檔案）"
      echo "  B. 自己下載模型檔，放進 ${MODELS}（下載連結在該資料夾的「把模型放這裡.txt」）"
      read -r -p "現在就開始一鍵下載嗎？輸入 y 後按 Enter（其他鍵＝不要）：" ans || ans=""
      case "${ans}" in
        y|Y) bash "${PKG}/mac/download-models.sh" || true; echo "下載完成後，請再雙擊一次「看懂.command」。" ;;
        *) open "${MODELS}" 2>/dev/null || true ;;
      esac
      exit 1
    fi
    if ! command -v llama-server >/dev/null 2>&1; then
      echo "找不到翻譯引擎 llama-server。請在 Terminal 跑：brew install llama.cpp"
      exit 1
    fi
    mkdir -p "${LOGS}"
    echo "開啟翻譯引擎（模型：$(basename "${MODEL}")；第一次載入約 10–60 秒）"
    llama-server -m "${MODEL}" --host 127.0.0.1 --port "${TPORT}" --alias tencent/Hy-MT2-GGUF \
      --ctx-size 4096 --parallel 1 -ngl 99 > "${LOGS}/translate-engine.log" 2>&1 &
    STARTED+=($!)
    ready=0
    for _ in $(seq 1 240); do
      if ! kill -0 "${STARTED[0]}" 2>/dev/null; then break; fi
      if curl -sf -m 2 "http://127.0.0.1:${TPORT}/health" >/dev/null 2>&1; then ready=1; break; fi
      printf '.'
      sleep 0.5
    done
    echo ""
    if [ "${ready}" != "1" ]; then
      echo "翻譯引擎沒有成功啟動。常見原因：記憶體不夠（請改用 1.8B 輕量模型），或模型檔不完整。"
      echo "---- ${LOGS}/translate-engine.log 最後幾行 ----"
      tail -15 "${LOGS}/translate-engine.log" 2>/dev/null || true
      exit 1
    fi
    echo "翻譯引擎就緒。"
  fi

  ASR_MODEL="${MODELS}/ggml-large-v3-turbo-q5_0.bin"
  if [ -f "${ASR_MODEL}" ] && ! port_open "${APORT}" && command -v whisper-server >/dev/null 2>&1; then
    mkdir -p "${LOGS}"
    whisper-server -m "${ASR_MODEL}" --host 127.0.0.1 --port "${APORT}" > "${LOGS}/asr-engine.log" 2>&1 &
    STARTED+=($!)
    echo "語音辨識引擎已啟動（沒字幕的影片會用到）。"
  fi
fi

echo "開啟播放器。看片時這個視窗請不要關（關掉播放器後會自動收掉這次開的引擎）。"
if [ $# -eq 0 ]; then
  mpv --config-dir="${CONFIG}" --idle=yes --force-window=yes || true
else
  mpv --config-dir="${CONFIG}" "$@" || true
fi
