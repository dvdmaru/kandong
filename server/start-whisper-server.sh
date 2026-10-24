#!/usr/bin/env bash
# 看懂 KanDong — 語音辨識伺服器（whisper.cpp 的 whisper-server），給「沒有字幕的影片」用
#
# 用法：
#   bash server/start-whisper-server.sh               # 只給這台電腦用（127.0.0.1:8090）
#   KANDONG_LAN=1 bash server/start-whisper-server.sh # 開給區網其他電腦（0.0.0.0）
#   KANDONG_WHISPER_MODEL=base.en bash server/start-whisper-server.sh
#
# 需要：whisper-server（macOS：brew install whisper-cpp；其他平台見 whisper.cpp 官方 releases）
# 模型第一次自動下載到 ~/.cache/kandong/whisper/：
#   large-v3-turbo-q5_0  預設，約 574MB，多語言，速度／品質的甜蜜點
#   small                約 488MB，較快、品質略降
#   base.en              約 148MB，只認英文
#
# ⚠️ whisper-server 本身沒有 API key 功能（上游未實作）：區網模式＝區網內任何裝置都能送音訊來轉寫。
#    只開在信任的區網，不要轉發到公網；只在本機看片就用預設的 127.0.0.1。

set -euo pipefail

MODEL_NAME="${KANDONG_WHISPER_MODEL:-large-v3-turbo-q5_0}"
MODEL_DIR="${KANDONG_WHISPER_DIR:-${HOME}/.cache/kandong/whisper}"
MODEL_FILE="${MODEL_DIR}/ggml-${MODEL_NAME}.bin"
PORT="${KANDONG_WHISPER_PORT:-8090}"
HOST="127.0.0.1"
if [[ "${KANDONG_LAN:-0}" == "1" ]]; then
  HOST="0.0.0.0"
fi

if [[ -n "${KANDONG_WHISPER_SERVER:-}" && -x "${KANDONG_WHISPER_SERVER}" ]]; then
  SERVER_BIN="${KANDONG_WHISPER_SERVER}"
elif command -v whisper-server >/dev/null 2>&1; then
  SERVER_BIN="$(command -v whisper-server)"
else
  echo "找不到 whisper-server。macOS 請先跑：brew install whisper-cpp"
  echo "（或把執行檔路徑放進 KANDONG_WHISPER_SERVER）"
  exit 1
fi
# Apple 晶片上若拿到 Intel 版（Rosetta、沒有 Metal 加速）會慢一個數量級，先講清楚
if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] && file "${SERVER_BIN}" | grep -q 'x86_64' && ! file "${SERVER_BIN}" | grep -q 'arm64'; then
  echo "⚠️ 這個 whisper-server 是 Intel 版，在 Apple 晶片上會非常慢；建議改用 Apple 晶片版的 Homebrew（/opt/homebrew）安裝。"
fi

if [[ ! -f "${MODEL_FILE}" ]]; then
  mkdir -p "${MODEL_DIR}"
  URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL_NAME}.bin"
  echo "第一次使用：下載語音辨識模型 ggml-${MODEL_NAME}.bin（只下載一次）"
  curl -fL --progress-bar -o "${MODEL_FILE}.part" "${URL}"
  mv "${MODEL_FILE}.part" "${MODEL_FILE}"
fi

echo "啟動語音辨識伺服器（${MODEL_NAME}）於 ${HOST}:${PORT}"
if [[ "${HOST}" == "0.0.0.0" ]]; then
  LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || true)"
  echo "播放器 asr_endpoint：http://${LAN_IP:-<這台電腦的區網 IP>}:${PORT}/inference"
else
  echo "播放器 asr_endpoint：http://127.0.0.1:${PORT}/inference（設定檔預設值就是這個）"
fi
echo "要停止就按 Control-C。這個視窗請保持開著。"

exec "${SERVER_BIN}" -m "${MODEL_FILE}" --host "${HOST}" --port "${PORT}"
