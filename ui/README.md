# 介面（uosc）

看懂的控制列、右鍵選單與台灣繁中介面文字，建立在 [uosc](https://github.com/tomasklaen/uosc) 5.13.0 上。

| 檔案 | 內容 |
|---|---|
| `install-uosc.sh` | 安裝 uosc（驗 SHA256）、拿掉字幕選單的「線上搜尋」、複製下列設定到 mpv 設定目錄 |
| `uosc.conf` | 控制列按鈕排列、粗時間軸、滑鼠停 2 秒淡出、台灣繁中介面 |
| `uosc-zh-TW.json` | uosc 內建 zh-HK 介面文字改成台灣字形與用詞 |
| `input.conf` | 右鍵選單（播放／字幕／音訊／翻譯／模型／倍速／設定）與快速鍵 |
| `mpv.conf` | 關掉 mpv 內建控制列、游標 2 秒隱藏、播完不關視窗、中文介面字型 |

`input.conf` 的選單由 uosc 從每行行尾的選單註解自動長出來：`>` 是下一層，`---` 是分隔線；行首是 `#` 的只出現在選單、不綁鍵。

⚠️ `mpv.conf` 設了 `keep-open=yes`（播完不關視窗）；用 `--end=N` 做無頭測試時要加 `--keep-open=no`，否則 mpv 會停在片尾不結束。
