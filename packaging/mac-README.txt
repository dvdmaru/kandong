看懂 KanDong — Mac 預覽版
==========================

看懂是一個會「邊播邊翻譯字幕」的影片播放器：外語片自動在原文字幕下方加上台灣繁中譯文；
沒有字幕的片，先用語音辨識聽寫出字幕再翻譯。翻譯全部在你自己的 Mac 上跑，影片和字幕不會上傳到任何地方。

【需要】
- Apple 晶片（M1 以後）的 Mac，記憶體 16GB 建議（8GB 請用小模型）。
- Homebrew（https://brew.sh）。裝好後在 Terminal 跑一次：
    brew install mpv ffmpeg llama.cpp whisper-cpp

【預覽版的門檻：要先開翻譯伺服器】
之後的正式版會把伺服器內建進播放器；預覽版請開一個 Terminal 視窗跑（第一次會下載約 4.6GB 的模型）：
    bash ~/Downloads/KanDong/server/start-translate-server.sh
（KanDong 資料夾放在別處就換成那個路徑；記憶體 8GB 的 Mac 在指令前面加 KANDONG_MODEL=1.8b 用小模型）
只有看「沒字幕的片」才需要語音辨識伺服器，再開一個 Terminal 視窗跑：
    bash ~/Downloads/KanDong/server/start-whisper-server.sh
這兩個視窗看片時要保持開著。

【使用】
雙擊「看懂.command」→ 出現黑色視窗後，把影片拖進去就開始播。
第一次雙擊若被 macOS 擋下（「無法打開，因為它來自未識別的開發者」）：
在 Finder 對「看懂.command」按右鍵 →「打開」→ 再按一次「打開」，之後就能直接雙擊。

- 有字幕（外掛 .srt／.ass／.vtt，或 mkv 內嵌）：自動雙語顯示，而且會先把整部片的字幕翻好。
- 沒字幕：自動語音辨識，約 20–30 秒後出現雙語字幕。
- 翻好的譯文存在影片旁邊（<影片名>.ft.zh-TW.json／.srt），重看不必再翻。
- 設定檔在 ~/.config/kandong/mpv/script-opts/floattranslate.conf（伺服器在別台電腦時改 endpoint）。

【操作】
  滑鼠右鍵    選單（播放、字幕、音訊、翻譯、倍速、設定）
  滑鼠移到下方 控制列（播放、進退、倍速、字幕、音軌、翻譯開關、全螢幕）
  Ctrl+t      翻譯開／關
  ← / →       退 5 秒／進 5 秒；Shift+← / → 退 30 秒／進 30 秒
  1 – 5       倍速 0.5x／1x／1.5x／2x／3x（變速不變調）
  D / A / S   加速 10%／減速 10%／回到 1x
  ↑ / ↓       音量 ±5%
  = / -       字幕放大／縮小
  v           隱藏原文字幕（只看譯文）
  空白鍵 暫停；f 全螢幕；q 離開

【這個播放器刻意不做的事】
不下載字幕、不攔截串流、不破解 DRM（Netflix 等串流平台不支援）。

官網：https://kandong.twtools.cc
原始碼與問題回報：https://github.com/dvdmaru/kandong
授權：看懂本身是 MIT；mpv、uosc 等各有授權，見 licenses 資料夾。
