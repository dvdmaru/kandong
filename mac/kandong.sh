#!/bin/bash
# 看懂 KanDong — Mac 啟動器（下載版雙擊「看懂.command」就是跑這支）
#
# 用法：bash mac/kandong.sh [影片檔]
#   不給影片＝開一個空視窗，把影片拖進去就開始播（也可以按 o 開檔）。
#
# 做的事：
#   1. 把介面與翻譯腳本裝進 ~/.config/kandong/mpv/（不動你原本的 ~/.config/mpv）
#      翻譯設定 script-opts/floattranslate.conf 與 kandong_settings.conf 只在第一次放範本，
#      之後你（或設定選單）改的內容不會被蓋掉。
#   2. 設定的翻譯伺服器是這台電腦（預設）時：自動開翻譯引擎，有語音辨識模型就一起開。
#      用哪個模型：設定選單選過的（kandong_settings.conf 的 model_path）優先，
#      沒選過就依記憶體自動選（12GB 以上 7B，否則 1.8B）。
#      還沒有模型或引擎開不起來也照樣開播放器：右鍵 → 設定 → 翻譯模型與伺服器 可以下載或換模型。
#      伺服器設成區網別台電腦、Ollama 等時：不開本機引擎，直接播放。
#   3. 播放器開著的時候，接設定選單的「換模型」要求（logs 資料夾的 engine-request.txt），
#      換好把結果寫進 engine-status.txt；關掉播放器時把這次開的引擎收掉。
#
# 需要：Homebrew 安裝的 mpv、llama.cpp（brew install mpv ffmpeg llama.cpp whisper-cpp）
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
PKG="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${KANDONG_CONFIG_DIR:-${HOME}/.config/kandong/mpv}"
MODELS="${KANDONG_MODELS_DIR:-${PKG}/models}"
LOGS="${KANDONG_LOG_DIR:-${HOME}/Library/Logs/KanDong}"
TPORT="${KANDONG_TRANSLATE_PORT:-8080}"
APORT="${KANDONG_ASR_PORT:-8090}"
REQ="${LOGS}/engine-request.txt"
STATUS="${LOGS}/engine-status.txt"
ENGINE_PID=""
ENGINE_MODEL=""
ENGINE_ERROR=""
ASR_PID=""
STATE="none"

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
cp "${PKG}/scripts/"*.lua "${CONFIG}/scripts/"
CONF="${CONFIG}/script-opts/floattranslate.conf"
if [ ! -f "${CONF}" ]; then
  (umask 077 && cp "${PKG}/script-opts/floattranslate.conf" "${CONF}")
fi
KCONF="${CONFIG}/script-opts/kandong_settings.conf"
if [ ! -f "${KCONF}" ]; then
  cp "${PKG}/script-opts/kandong_settings.conf" "${KCONF}"
fi
mkdir -p "${MODELS}" "${LOGS}"
rm -f "${REQ}"

# ── 2. 本機引擎 ──
port_open() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

conf_value() {  # $1 檔案  $2 key → 印出最後一行 key= 的值（沒有就空白）
  grep -E "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

write_status() {  # $1 要求 id  $2 狀態  $3 模型檔  $4 錯誤訊息（白話）
  printf 'id=%s\nstate=%s\nmodel=%s\nerror=%s\n' "$1" "$2" "$3" "${4:-}" > "${STATUS}.tmp"
  mv -f "${STATUS}.tmp" "${STATUS}"
}

auto_model() {  # 依記憶體挑內建模型；都沒有就挑 models 資料夾裡第一個 .gguf
  local ram_gb order name f
  ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  if [ "${ram_gb}" -ge 12 ]; then order="Hy-MT2-7B-Q4_K_M.gguf Hy-MT2-1.8B-Q4_K_M.gguf"
  else order="Hy-MT2-1.8B-Q4_K_M.gguf Hy-MT2-7B-Q4_K_M.gguf"; fi
  for name in ${order}; do
    if [ -f "${MODELS}/${name}" ]; then echo "${MODELS}/${name}"; return 0; fi
  done
  for f in "${MODELS}"/*.gguf; do
    case "${f}" in *mmproj*) continue ;; esac
    if [ -f "${f}" ]; then echo "${f}"; return 0; fi
  done
  return 0
}

chosen_model() {  # 設定選單選過的優先；檔案不在了就退回自動選
  local p
  p="$(conf_value "${KCONF}" model_path)"
  case "${p}" in ""|/*) ;; *) p="${MODELS}/${p}" ;; esac
  if [ -n "${p}" ] && [ -f "${p}" ]; then echo "${p}"; return 0; fi
  auto_model
}

stop_engine() {
  local _
  if [ -n "${ENGINE_PID}" ]; then
    kill "${ENGINE_PID}" 2>/dev/null || true
    for _ in $(seq 1 40); do
      kill -0 "${ENGINE_PID}" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "${ENGINE_PID}" 2>/dev/null || true
    wait "${ENGINE_PID}" 2>/dev/null || true
  fi
  ENGINE_PID=""
  ENGINE_MODEL=""
}

start_engine() {  # $1 模型檔 → 0＝就緒（失敗時 ENGINE_ERROR 是白話原因）
  local model="$1" _
  ENGINE_ERROR=""
  if ! command -v llama-server >/dev/null 2>&1; then
    ENGINE_ERROR="找不到翻譯引擎 llama-server（請在 Terminal 跑：brew install llama.cpp）"
    return 1
  fi
  if port_open "${TPORT}"; then
    ENGINE_ERROR="${TPORT} 埠被別的程式占用"
    return 1
  fi
  echo "開啟翻譯引擎（模型：$(basename "${model}")；第一次載入約 10–60 秒）"
  llama-server -m "${model}" --host 127.0.0.1 --port "${TPORT}" --alias tencent/Hy-MT2-GGUF \
    --ctx-size 4096 --parallel 1 -ngl 99 > "${LOGS}/translate-engine.log" 2>&1 &
  ENGINE_PID=$!
  for _ in $(seq 1 240); do
    if ! kill -0 "${ENGINE_PID}" 2>/dev/null; then break; fi
    if curl -sf -m 2 "http://127.0.0.1:${TPORT}/health" >/dev/null 2>&1; then
      ENGINE_MODEL="${model}"
      echo ""
      echo "翻譯引擎就緒。"
      return 0
    fi
    printf '.'
    sleep 0.5
  done
  echo ""
  stop_engine
  ENGINE_ERROR="模型載入失敗（常見原因：記憶體不夠，或模型檔不完整）"
  return 1
}

start_asr() {  # 有語音辨識模型、8090 沒人用、這次還沒開過 → 開 whisper-server
  local m="${MODELS}/ggml-large-v3-turbo-q5_0.bin"
  if [ -n "${ASR_PID}" ] || [ ! -f "${m}" ] || port_open "${APORT}"; then return 0; fi
  if ! command -v whisper-server >/dev/null 2>&1; then return 0; fi
  whisper-server -m "${m}" --host 127.0.0.1 --port "${APORT}" > "${LOGS}/asr-engine.log" 2>&1 &
  ASR_PID=$!
  echo "語音辨識引擎已啟動（沒字幕的影片會用到）。"
}

cleanup() {
  stop_engine
  if [ -n "${ASR_PID}" ]; then kill "${ASR_PID}" 2>/dev/null || true; fi
  rm -f "${STATUS}" "${STATUS}.tmp" "${REQ}"
}
trap cleanup EXIT

ENDPOINT="$(conf_value "${CONF}" endpoint)"
case "${ENDPOINT:-http://127.0.0.1:${TPORT}/}" in
  *://127.0.0.1:${TPORT}/*|*://localhost:${TPORT}/*) LOCAL_ENGINE=1 ;;
  *) LOCAL_ENGINE=0 ;;
esac

if [ "${LOCAL_ENGINE}" != "1" ]; then
  STATE="remote"
  echo "翻譯伺服器設定為 ${ENDPOINT}（不是這台電腦），不開本機引擎。"
elif [ "${KANDONG_NO_ENGINE:-0}" = "1" ]; then
  STATE="stopped"
elif port_open "${TPORT}"; then
  STATE="external"
  echo "已經有翻譯服務在 ${TPORT} 埠執行，直接使用它。"
else
  MODEL="$(chosen_model)"
  if [ -z "${MODEL}" ]; then
    echo ""
    echo "還沒有翻譯模型。播放器開啟後：按右鍵 → 設定 → 翻譯模型與伺服器，就能直接下載。"
    echo "（也可以雙擊「一鍵下載模型.command」，或自己把模型檔放進 ${MODELS}）"
    STATE="none"
  elif start_engine "${MODEL}"; then
    STATE="ready"
  else
    FIRST_ERROR="${ENGINE_ERROR}"
    # 設定選單選的模型開不起來（例如記憶體不夠）→ 清掉選擇、改用自動選的模型再試一次
    AUTO="$(auto_model)"
    if [ -n "$(conf_value "${KCONF}" model_path)" ] && [ -n "${AUTO}" ] && [ "${AUTO}" != "${MODEL}" ]; then
      echo "選擇的模型 $(basename "${MODEL}") 開不起來：${FIRST_ERROR}"
      echo "改用自動選擇的模型 $(basename "${AUTO}") 再試一次。"
      sed -i '' -e 's/^model_path=.*/model_path=/' "${KCONF}"
      if start_engine "${AUTO}"; then STATE="ready"; fi
    fi
    if [ "${STATE}" != "ready" ]; then
      STATE="failed"
      echo "翻譯引擎沒有成功啟動：${ENGINE_ERROR:-${FIRST_ERROR}}"
      echo "---- ${LOGS}/translate-engine.log 最後幾行 ----"
      tail -15 "${LOGS}/translate-engine.log" 2>/dev/null || true
      echo "播放器照樣會開：可以在右鍵 → 設定 → 翻譯模型與伺服器 換成 1.8B 輕量模型。"
    fi
  fi
fi
if [ "${LOCAL_ENGINE}" = "1" ] && [ "${KANDONG_NO_ENGINE:-0}" != "1" ]; then start_asr; fi
write_status 0 "${STATE}" "${ENGINE_MODEL}" "${ENGINE_ERROR}"

# ── 3. 接設定選單的要求 ──
handle_request() {
  local id action model prev err
  id="$(conf_value "${REQ}" id)"
  action="$(conf_value "${REQ}" action)"
  model="$(conf_value "${REQ}" model)"
  rm -f "${REQ}"
  case "${action}" in
    switch)
      if [ "${STATE}" = "external" ]; then
        write_status "${id}" external "" "${TPORT} 埠上的翻譯服務不是看懂開的"
        return 0
      fi
      if [ ! -f "${model}" ]; then
        write_status "${id}" "${STATE}" "${ENGINE_MODEL}" "找不到模型檔 ${model}"
        return 0
      fi
      prev="${ENGINE_MODEL}"
      write_status "${id}" loading "${model}" ""
      echo ""
      echo "換模型：$(basename "${model}")"
      stop_engine
      if start_engine "${model}"; then
        STATE="ready"
        write_status "${id}" ready "${ENGINE_MODEL}" ""
      else
        err="${ENGINE_ERROR}"
        if [ -n "${prev}" ] && [ "${prev}" != "${model}" ] && start_engine "${prev}"; then
          STATE="ready"
          write_status "${id}" ready "${ENGINE_MODEL}" "${err}"
        else
          STATE="failed"
          write_status "${id}" failed "" "${err}"
        fi
      fi
      ;;
    stop)
      stop_engine
      if [ "${STATE}" != "external" ]; then STATE="stopped"; fi
      write_status "${id}" "${STATE}" "" ""
      echo "已關閉本機翻譯引擎（改用其他翻譯伺服器）。"
      ;;
    asr)
      start_asr
      write_status "${id}" "${STATE}" "${ENGINE_MODEL}" ""
      ;;
    *)
      write_status "${id}" "${STATE}" "${ENGINE_MODEL}" "看不懂的要求：${action}"
      ;;
  esac
}

MPV_ARGS=(
  "--config-dir=${CONFIG}"
  "--script-opts-append=kandong_settings-models_dir=${MODELS}"
  "--script-opts-append=kandong_settings-control_dir=${LOGS}"
  "--script-opts-append=kandong_settings-engine_port=${TPORT}"
)
if [ $# -eq 0 ]; then
  MPV_ARGS+=(--idle=yes --force-window=yes)
else
  MPV_ARGS+=("$@")
fi

echo "開啟播放器。看片時這個視窗請不要關（關掉播放器後會自動收掉這次開的引擎）。"
mpv "${MPV_ARGS[@]}" &
MPV_PID=$!
while kill -0 "${MPV_PID}" 2>/dev/null; do
  if [ -f "${REQ}" ]; then handle_request; fi
  sleep 0.5
done
wait "${MPV_PID}" 2>/dev/null || true
