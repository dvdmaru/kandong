看懂 KanDong — Windows 預覽版
==============================

看懂是一個會「邊播邊翻譯字幕」的影片播放器：英文、日文等外語片，自動在原文字幕下方加上台灣繁中譯文；
沒有字幕的片，先用語音辨識聽寫出字幕再翻譯。翻譯全部在你自己的電腦上跑，影片和字幕不會上傳到任何地方。

【預覽版的門檻：要先開一個翻譯伺服器】
播放器本身只負責播放和顯示；翻譯要靠一個「翻譯伺服器」（免費的 llama.cpp 加上騰訊的 Hy-MT2 翻譯模型）。
之後的正式版會把伺服器內建進播放器、下載就能用；預覽版請先照下面做一次。

1. 下載 llama.cpp：https://github.com/ggml-org/llama.cpp/releases
   選檔名有 win 與 x64 的 zip（有 NVIDIA 顯示卡選 cuda 版；沒有就選 vulkan 或 cpu 版），解壓到任何資料夾。
2. 在那個資料夾的網址列打 cmd 按 Enter，開出命令提示字元，貼上這一行（第一次會下載約 4.6GB 的模型）：
     llama-server.exe -hf tencent/Hy-MT2-7B-GGUF -hff Hy-MT2-7B-Q4_K_M.gguf --port 8080 --ctx-size 4096 --parallel 1 -ngl 99
   電腦記憶體 16GB 以下或沒有獨立顯示卡，改用小模型（約 1.1GB，快很多、品質稍差）：
     llama-server.exe -hf tencent/Hy-MT2-1.8B-GGUF -hff Hy-MT2-1.8B-Q4_K_M.gguf --port 8080 --ctx-size 4096 --parallel 1 -ngl 99
   看到 "server is listening" 就好了。這個視窗看片時要保持開著。
3. （只有看「沒字幕的片」才需要）語音辨識伺服器：
   https://github.com/ggml-org/whisper.cpp/releases 下載 whisper-bin-x64.zip 解壓；
   模型到 https://huggingface.co/ggerganov/whisper.cpp/tree/main 下載 ggml-large-v3-turbo-q5_0.bin 放在同一個資料夾；
   在該資料夾開命令提示字元：
     whisper-server.exe -m ggml-large-v3-turbo-q5_0.bin --port 8090

翻譯伺服器在區網另一台電腦（例如 Mac）？改 portable_config\script-opts\floattranslate.conf 的 endpoint
（和 asr_endpoint）成那台電腦的區網 IP，伺服器有開 API key 就填 api_key=。

【使用】
- 把整個 KanDong 資料夾解壓到任何地方（桌面、D 槽都可以），把影片拖到 mpv.exe 上即可播放。
- 有字幕（外掛 .srt／.ass／.vtt，或 mkv 內嵌）：自動雙語顯示，而且會先把整部片的字幕翻好。
- 沒字幕：自動語音辨識，約 20–30 秒後出現雙語字幕。
- 翻好的譯文會存在影片旁邊（<影片名>.ft.zh-TW.json／.srt），重看不必再翻。

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

【常見問題】
- 左上角出現「翻譯伺服器連線失敗」：翻譯伺服器沒開、port 不是 8080，或 endpoint 填錯。
  伺服器開好後不用重開影片，30 秒內會自動重試。
- 沒字幕的片開 2 倍速以上，左上出現「語音辨識跟不上」：按 S 回 1x 即可。

【這個播放器刻意不做的事】
不下載字幕、不攔截串流、不破解 DRM（Netflix 等串流平台不支援）。

官網：https://kandong.twtools.cc
原始碼與問題回報：https://github.com/dvdmaru/kandong
授權：看懂本身是 MIT；內附的 mpv、FFmpeg、uosc、Vulkan Runtime 各有授權，見 licenses 資料夾。
