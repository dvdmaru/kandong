#!/usr/bin/env bash
# 看懂 KanDong — 翻譯伺服器（llama.cpp 的 llama-server ＋ 騰訊 Hy-MT2 翻譯模型）
#
# 用法：
#   bash server/start-translate-server.sh            # 只給這台電腦用（127.0.0.1:8080，不需 key）
#   KANDONG_LAN=1 bash server/start-translate-server.sh   # 開給區網其他電腦（0.0.0.0，強制 API key）
#   KANDONG_MODEL=1.8b bash server/start-translate-server.sh  # 換小模型
#   KANDONG_PORT=8081 bash server/start-translate-server.sh
#
# 需要：llama-server（macOS：brew install llama.cpp；其他平台見 llama.cpp 官方 releases）
# 模型第一次啟動自動下載到 ~/.cache/kandong/models/，之後離線可用。
#   7b  （預設）品質較好，每句約 1–1.5 秒（Apple M4／16GB 實測），檔約 4.6GB，需 8GB 以上可用記憶體
#   1.8b         每句約 0.25 秒，檔約 1.1GB；記憶體吃緊、或要開 2 倍速以上看無字幕片時用
#
# 區網模式的 API key：第一次自動產生到 ~/.config/kandong/api-key（權限 600，不印出）。
# 播放器那台把該檔內容填進 floattranslate.conf 的 api_key=。
# key 用 --api-key-file 交給 llama-server，不放在指令參數裡（放參數的話其他使用者用 ps 看得到）。

set -euo pipefail

MODEL_SIZE="${KANDONG_MODEL:-7b}"
MODEL_DIR="${KANDONG_MODEL_DIR:-${HOME}/.cache/kandong/models}"
case "${MODEL_SIZE}" in
  7b|7B)
    MODEL_PATH="${MODEL_DIR}/Hy-MT2-7B-Q4_K_M.gguf"
    MODEL_URL="https://huggingface.co/tencent/Hy-MT2-7B-GGUF/resolve/main/Hy-MT2-7B-Q4_K_M.gguf"
    MODEL_ALIAS="tencent/Hy-MT2-7B-GGUF"
    MODEL_SIZE_HINT="約 4.6GB"
    ;;
  1.8b|1.8B)
    MODEL_PATH="${MODEL_DIR}/Hy-MT2-1.8B-Q4_K_M.gguf"
    MODEL_URL="https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/main/Hy-MT2-1.8B-Q4_K_M.gguf"
    MODEL_ALIAS="tencent/Hy-MT2-1.8B-GGUF"
    MODEL_SIZE_HINT="約 1.1GB"
    ;;
  *)
    echo "KANDONG_MODEL 只接受 7b 或 1.8b（現在是：${MODEL_SIZE}）"
    exit 1
    ;;
esac
PORT="${KANDONG_PORT:-8080}"
KEY_FILE="${KANDONG_API_KEY_FILE:-${HOME}/.config/kandong/api-key}"

if [[ -n "${KANDONG_LLAMA_SERVER:-}" && -x "${KANDONG_LLAMA_SERVER}" ]]; then
  LLAMA_SERVER="${KANDONG_LLAMA_SERVER}"
elif command -v llama-server >/dev/null 2>&1; then
  LLAMA_SERVER="$(command -v llama-server)"
else
  echo "找不到 llama-server。macOS 請先跑：brew install llama.cpp"
  echo "（或把執行檔路徑放進 KANDONG_LLAMA_SERVER）"
  exit 1
fi

# 同一個 port 只能有一個服務。已經有人佔著就講清楚是誰，不讓 llama-server 載完模型才失敗。
OCCUPANT="$(lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR == 2 {print $1, $2, $9}' || true)"
if [[ -n "${OCCUPANT}" ]]; then
  echo "Port ${PORT} 已經被佔用：${OCCUPANT}"
  echo "如果那就是翻譯伺服器，不用再開一次；否則先關掉它，或改用別的 port（例如 KANDONG_PORT=8081，播放器的 endpoint 也要跟著改）。"
  exit 1
fi

# 模型檔不在就從 Hugging Face 下載一次（放在 port 檢查之後：port 被佔就不先抓幾 GB）
if [[ ! -f "${MODEL_PATH}" ]]; then
  echo "第一次使用：下載 Hy-MT2 ${MODEL_SIZE}（${MODEL_SIZE_HINT}，只下載一次）。按 Control-C 可中止。"
  mkdir -p "${MODEL_DIR}"
  curl -fL --progress-bar -o "${MODEL_PATH}.part" "${MODEL_URL}"
  mv "${MODEL_PATH}.part" "${MODEL_PATH}"
fi

ARGS=(-m "${MODEL_PATH}" --port "${PORT}" --alias "${MODEL_ALIAS}" --ctx-size 4096 --parallel 1 -ngl 99)

if [[ "${KANDONG_LAN:-0}" == "1" ]]; then
  if [[ ! -s "${KEY_FILE}" ]]; then
    mkdir -p "$(dirname "${KEY_FILE}")"
    (umask 077 && openssl rand -hex 24 > "${KEY_FILE}")
    echo "已產生 API key：${KEY_FILE}（不印出；請自行把內容填進播放器設定的 api_key=）"
  fi
  LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || true)"
  echo "啟動翻譯伺服器（Hy-MT2 ${MODEL_SIZE}，區網模式 0.0.0.0:${PORT}，需要 API key）"
  echo "播放器 endpoint：http://${LAN_IP:-<這台電腦的區網 IP>}:${PORT}/v1/chat/completions"
  echo "⚠️ 只開在信任的家用／辦公室區網，不要轉發到公網。"
  ARGS+=(--host 0.0.0.0 --api-key-file "${KEY_FILE}")
else
  echo "啟動翻譯伺服器（Hy-MT2 ${MODEL_SIZE}，只給這台電腦用 127.0.0.1:${PORT}）"
  echo "播放器 endpoint：http://127.0.0.1:${PORT}/v1/chat/completions（設定檔預設值就是這個）"
  ARGS+=(--host 127.0.0.1)
fi
echo "模型：${MODEL_PATH}"
echo "要停止就按 Control-C。這個視窗請保持開著。"

exec "${LLAMA_SERVER}" "${ARGS[@]}"
