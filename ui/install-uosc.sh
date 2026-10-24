#!/bin/bash
# 把 uosc（固定版本）＋看懂的介面設定裝進一個 mpv 設定目錄。
#
# 用法：bash ui/install-uosc.sh <mpv 設定目錄>
#   mac/kandong.sh 會自動呼叫；打包腳本 packaging/build-release.sh 也用它產生 Windows 版的 portable_config。
#   下載包內附 uosc.zip（ui/vendor/uosc.zip）時直接用它、不上網；不論來源都驗 SHA256。
#
# 對 uosc 的唯一修改：拿掉字幕選單的「線上搜尋」按鈕（會去 OpenSubtitles 下載字幕，
# 違反本專案「不下載字幕」的邊界）。uosc 是 LGPL-2.1，允許修改。
set -euo pipefail

UOSC_VERSION="5.13.0"
UOSC_URL="https://github.com/tomasklaen/uosc/releases/download/${UOSC_VERSION}/uosc.zip"
UOSC_SHA256="4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882"

if [ $# -ne 1 ]; then
  echo "用法：bash $0 <mpv 設定目錄>"
  exit 1
fi
DEST="$1"
UI_DIR="$(cd "$(dirname "$0")" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

if [ -f "${UI_DIR}/vendor/uosc.zip" ]; then
  cp "${UI_DIR}/vendor/uosc.zip" "${WORK}/uosc.zip"
else
  echo "下載 uosc ${UOSC_VERSION}…"
  curl -fsSL -o "${WORK}/uosc.zip" "${UOSC_URL}"
fi
GOT="$(shasum -a 256 "${WORK}/uosc.zip" | awk '{print $1}')"
if [ "${GOT}" != "${UOSC_SHA256}" ]; then
  echo "uosc.zip 的 SHA256 不符（拿到 ${GOT}），停止安裝。"
  exit 1
fi
unzip -q "${WORK}/uosc.zip" -d "${WORK}/x"

# 拿掉字幕選單的「線上搜尋」（download_command 那一行），並確認真的拿掉了
MAIN="${WORK}/x/scripts/uosc/main.lua"
grep -q "download_command = 'script-binding uosc/download-subtitles'," "${MAIN}" || {
  echo "uosc main.lua 找不到預期的 download_command 行（版本變了？），停止安裝。"
  exit 1
}
sed -i.orig "/download_command = 'script-binding uosc\/download-subtitles',/d" "${MAIN}"
rm -f "${MAIN}.orig"
if grep -q "download_command = " "${MAIN}"; then
  echo "拿掉 download_command 失敗，停止安裝。"
  exit 1
fi

mkdir -p "${DEST}/scripts" "${DEST}/fonts" "${DEST}/script-opts"
rm -rf "${DEST}/scripts/uosc"
cp -R "${WORK}/x/scripts/uosc" "${DEST}/scripts/uosc"
cp "${WORK}/x/fonts/"* "${DEST}/fonts/"
cp "${UI_DIR}/uosc.conf" "${UI_DIR}/uosc-zh-TW.json" "${DEST}/script-opts/"
cp "${UI_DIR}/input.conf" "${UI_DIR}/mpv.conf" "${DEST}/"
echo "${UOSC_VERSION}" > "${DEST}/scripts/uosc/.kandong-version"

echo "已裝好介面：uosc ${UOSC_VERSION}（已拿掉線上搜尋字幕）"
