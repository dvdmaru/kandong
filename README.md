# 看懂 KanDong

**邊播邊翻譯字幕的影片播放器。** 外語片自動在原文字幕下方加上台灣繁中譯文；沒有字幕的片，先用語音辨識聽寫出字幕再翻譯。
翻譯用的是在你自己電腦上跑的開源模型，影片和字幕不會上傳到任何地方。

官網：<https://kandong.twtools.cc>　｜　下載：[最新版](https://github.com/dvdmaru/kandong/releases/latest)

![看懂播放畫面：上英文、下繁中](docs/screenshot-watching.png)

> **目前是預覽版。** 播放器還需要搭配一個自己開的「翻譯伺服器」（免費的 llama.cpp＋騰訊 Hy-MT2 翻譯模型）。
> 之後的正式版會把伺服器內建進播放器，下載就能用。

## 能做什麼

- **雙語字幕**：外掛字幕（.srt／.ass／.vtt）或 mkv 內嵌字幕，自動在下方加上繁中譯文；整部片的字幕會先翻好，不會一句一句等。
- **沒字幕也能看**：自動用語音辨識（whisper.cpp）聽寫，再翻譯。
- **譯文快取**：翻好的存在影片旁邊（`<影片名>.ft.zh-TW.json`／`.srt`），重看不必再翻。
- **台灣用語**：翻譯提示詞針對台灣繁中調過（口語、俚語意譯、運動術語），不是逐字直翻。
- **好操作**：右鍵選單、控制列、倍速（0.5x–3x，變速不變調）、字幕軌與音軌用滑鼠選。

## 下載與安裝

到 [Releases](https://github.com/dvdmaru/kandong/releases/latest) 下載：

| 檔案 | 平台 | 說明 |
|---|---|---|
| `KanDong-windows-x64.zip` | Windows 10／11（64 位元） | 解壓即用，內附 mpv 與 FFmpeg |
| `KanDong-mac.zip` | macOS（Apple 晶片） | 需要 Homebrew：`brew install mpv ffmpeg llama.cpp whisper-cpp` |

包裡的「使用說明.txt」有完整步驟，包含怎麼開翻譯伺服器。

## 翻譯伺服器

播放器把字幕送到一個 OpenAI 相容的 `/v1/chat/completions` 端點翻譯，預設是同一台電腦的 `http://127.0.0.1:8080`。

**Mac／Linux：**

```bash
bash server/start-translate-server.sh                 # 翻譯（第一次自動下載約 4.6GB 的 Hy-MT2 7B）
KANDONG_MODEL=1.8b bash server/start-translate-server.sh   # 記憶體吃緊時用小模型（約 1.1GB）
bash server/start-whisper-server.sh                   # 只有看沒字幕的片才需要
```

**Windows：** 從 [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases) 下載 Windows 版，在資料夾裡執行：

```
llama-server.exe -hf tencent/Hy-MT2-7B-GGUF -hff Hy-MT2-7B-Q4_K_M.gguf --port 8080 --ctx-size 4096 --parallel 1 -ngl 99
```

**伺服器放在區網另一台電腦**（例如用 Mac 跑模型、Windows 看片）：伺服器那台用 `KANDONG_LAN=1` 啟動（會強制 API key，key 存在 `~/.config/kandong/api-key`），
播放器的 `floattranslate.conf` 改 `endpoint`、`asr_endpoint` 並填 `api_key`。只開在信任的區網，不要轉發到公網。

實測速度（Apple M4／16GB，含 12 句前文）：7B 每句約 1–1.5 秒，1.8B 約 0.25 秒；有字幕的片會先翻好整部，看的時候幾乎不用等。

## 操作

| 按鍵 | 功能 |
|---|---|
| 滑鼠右鍵 | 選單：播放、字幕、音訊、翻譯、倍速、設定 |
| Ctrl+t | 翻譯開／關 |
| ← / → | 退／進 5 秒（Shift：30 秒） |
| 1 – 5 | 倍速 0.5x／1x／1.5x／2x／3x |
| D / A / S | 加速 10%／減速 10%／回到 1x |
| ↑ / ↓ | 音量 ±5% |
| = / - | 字幕放大／縮小 |
| v | 隱藏原文字幕（只看譯文） |
| 空白鍵／f／q | 暫停／全螢幕／離開 |

## 刻意不做

- 不下載字幕、不攔截串流、不破解 DRM——Netflix 等串流平台不支援。
- 不做圖形字幕（藍光 PGS 等）的文字辨識；這類片走語音辨識。

## 已知限制

- 人名常被音譯（例如 Marcus → 馬庫斯），換大模型也一樣；之後會做譯名修正。
- 「模型」選單目前只是預告，換模型要在翻譯伺服器那邊換。
- 控制列展開時，字幕不會自動往上讓位（目前把字幕固定放在稍高的位置）。

## 從原始碼執行（Mac）

```bash
brew install mpv ffmpeg llama.cpp whisper-cpp
bash server/start-translate-server.sh        # 另開一個 Terminal
bash mac/kandong.sh                          # 開空視窗，把影片拖進去
```

設定裝在 `~/.config/kandong/mpv/`，不動你原本的 mpv 設定。程式結構：

- `scripts/floattranslate.lua`：翻譯、聽寫、快取、雙語顯示（mpv Lua 腳本；`floattranslate` 是內部代號）
- `ui/`：介面（[uosc](https://github.com/tomasklaen/uosc) 設定、右鍵選單、台灣繁中介面文字）
- `server/`：翻譯與語音辨識伺服器啟動腳本
- `packaging/`：產生下載包

## 授權

看懂本身是 [MIT](LICENSE)。內附與使用的第三方元件（mpv、FFmpeg、uosc、Hy-MT2 等）見 [THIRD_PARTY.md](THIRD_PARTY.md)。
