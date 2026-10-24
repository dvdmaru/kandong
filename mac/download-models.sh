#!/bin/bash
# 看懂 KanDong — 一鍵下載模型（Mac；下載版雙擊「一鍵下載模型.command」）
# 從 Hugging Face 官方下載，存進 KanDong/models；可以中斷後續傳；完成後比對官方 SHA256，不符就刪掉。
# 模型清單要跟 packaging/windows/scripts/download-models.ps1 一致（打包前有檢查）。
set -u

PKG="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="${KANDONG_MODELS_DIR:-${PKG}/models}"
mkdir -p "${MODELS}"

# MODELS-BEGIN（編號｜檔名｜網址｜SHA256｜大小 bytes｜說明）
CATALOG=(
  "1|Hy-MT2-7B-Q4_K_M.gguf|https://huggingface.co/tencent/Hy-MT2-7B-GGUF/resolve/main/Hy-MT2-7B-Q4_K_M.gguf|9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b|4624648896|翻譯模型・標準（Hy-MT2 7B，約 4.6GB）：翻得比較好，建議記憶體 16GB 以上"
  "2|Hy-MT2-1.8B-Q4_K_M.gguf|https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/main/Hy-MT2-1.8B-Q4_K_M.gguf|dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699|1133080448|翻譯模型・輕量（Hy-MT2 1.8B，約 1.1GB）：快很多，記憶體 8GB 或電腦較舊選這個"
  "3|ggml-large-v3-turbo-q5_0.bin|https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin|394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2|574041195|語音辨識模型（Whisper large-v3-turbo，約 574MB）：只有看「沒字幕的影片」才需要"
)
# MODELS-END

get_one() {  # $1＝catalog 一行
  local key file url sha size desc dest part got free_kb
  IFS='|' read -r key file url sha size desc <<< "$1"
  dest="${MODELS}/${file}"
  part="${dest}.part"
  if [ -f "${dest}" ]; then
    echo "已經有 ${file}，略過。"
    return 0
  fi
  free_kb="$(df -k "${MODELS}" | awk 'NR == 2 {print $4}')"
  if [ -n "${free_kb}" ] && [ "${free_kb}" -lt $(( size / 1024 + 512 * 1024 )) ]; then
    echo "磁碟空間不夠：${file} 需要約 $(( size / 1073741824 + 1 )) GB。"
    return 1
  fi
  echo ""
  echo "下載 ${file}（可以隨時關掉視窗，下次會從中斷的地方接著下載）"
  if ! curl -L --fail --retry 5 --retry-delay 3 -C - --progress-bar -o "${part}" "${url}"; then
    echo "下載失敗，請檢查網路後重試。"
    return 1
  fi
  echo "檢查檔案是否完整（大檔要等一下）…"
  got="$(shasum -a 256 "${part}" | awk '{print $1}')"
  if [ "${got}" != "${sha}" ]; then
    rm -f "${part}"
    echo "檔案檢查不符（可能不完整），已刪除，請再試一次。"
    return 1
  fi
  mv "${part}" "${dest}"
  echo "完成：${file}"
}

ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
echo ""
echo "===== 看懂：一鍵下載模型 ====="
if [ "${ram_gb}" -gt 0 ]; then
  if [ "${ram_gb}" -ge 12 ]; then hint="建議選 1（標準）"; else hint="建議選 2（輕量）"; fi
  echo "這台 Mac 記憶體 ${ram_gb} GB，${hint}。"
fi
echo "模型都從 Hugging Face 官方下載，存在：${MODELS}"
echo ""
for line in "${CATALOG[@]}"; do
  IFS='|' read -r key _ _ _ _ desc <<< "${line}"
  echo "  [${key}] ${desc}"
done
echo ""
read -r -p "輸入要下載的編號（可以一次輸入多個，例如 13），再按 Enter：" pick
ok=1; any=0
for line in "${CATALOG[@]}"; do
  key="${line%%|*}"
  case "${pick}" in
    *"${key}"*) any=1; get_one "${line}" || ok=0 ;;
  esac
done
echo ""
if [ "${any}" -eq 0 ]; then
  echo "沒有選到任何模型。"; exit 1
fi
if [ "${ok}" -eq 1 ]; then
  echo "全部完成！現在可以雙擊「看懂.command」開始看片。"
else
  echo "有模型沒有下載成功，可以再雙擊「一鍵下載模型.command」重試。"; exit 1
fi
