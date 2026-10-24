#!/bin/bash
# 看懂 KanDong — Mac 啟動器
#
# 用法：bash mac/kandong.sh [影片檔]
#   不給影片＝開一個空視窗，把影片拖進去就開始播（也可以按 o 開檔）。
#   下載版直接雙擊「看懂.command」即可，它呼叫的就是這支。
#
# 需要：mpv（brew install mpv）；看 mkv 內嵌字幕或沒字幕的片還需要 ffmpeg（brew install ffmpeg）。
# 設定裝在 ~/.config/kandong/mpv/（不動你原本的 ~/.config/mpv）。
#   - 介面設定（uosc、右鍵選單、快速鍵）每次啟動都更新成這一版的。
#   - 翻譯設定 script-opts/floattranslate.conf 只在第一次放範本，之後你改的內容不會被蓋掉。
set -euo pipefail

PKG="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${KANDONG_CONFIG_DIR:-${HOME}/.config/kandong/mpv}"

if ! command -v mpv >/dev/null 2>&1; then
  echo "找不到 mpv。請先安裝 Homebrew（https://brew.sh），再跑：brew install mpv ffmpeg"
  exit 1
fi

# 第一個參數若不是 mpv 選項，就當影片檔先檢查，找不到時講白話
if [ $# -ge 1 ] && [ "${1#-}" = "$1" ] && [ ! -e "$1" ]; then
  echo "找不到影片檔：$1"
  echo "提示：打完指令和一個空格後，把影片從 Finder 拖進 Terminal 視窗，路徑會自動填好；"
  echo "      或不給影片直接啟動，會開一個空視窗，把影片拖進去即可。"
  exit 1
fi

mkdir -p "${CONFIG}/scripts" "${CONFIG}/script-opts"
if [ "$(cat "${CONFIG}/scripts/uosc/.kandong-version" 2>/dev/null || true)" = "5.13.0" ]; then
  cp "${PKG}/ui/uosc.conf" "${PKG}/ui/uosc-zh-TW.json" "${CONFIG}/script-opts/"
  cp "${PKG}/ui/input.conf" "${PKG}/ui/mpv.conf" "${CONFIG}/"
else
  bash "${PKG}/ui/install-uosc.sh" "${CONFIG}"
fi
cp "${PKG}/scripts/floattranslate.lua" "${CONFIG}/scripts/"
if [ ! -f "${CONFIG}/script-opts/floattranslate.conf" ]; then
  (umask 077 && cp "${PKG}/script-opts/floattranslate.conf" "${CONFIG}/script-opts/floattranslate.conf")
  echo "已放好翻譯設定檔：${CONFIG}/script-opts/floattranslate.conf（伺服器不在這台電腦時改裡面的 endpoint）"
fi

if [ $# -eq 0 ]; then
  exec mpv --config-dir="${CONFIG}" --idle=yes --force-window=yes
fi
exec mpv --config-dir="${CONFIG}" "$@"
