# KanDong 選題前搜尋紀錄

查詢時間：2026-10-24 23:36–23:40，台北時間（Asia/Taipei）。
Repo 基準：`7effeb9e3da2fde611f6f068cf71198e98e6a9ff`。

用途：選題與搜尋意圖判讀。這是當下搜尋工具回傳的結果摘要，沒有搜尋量、點閱率或排名追蹤資料；不推算流量。第三方結果只用來辨識讀者正在找什麼，文章的產品事實只引用本 repo 與一手官方文件。

## 六個候選的判斷

| 候選 | 實際查詢 | 搜尋結果呈現的問題 | 一行能否完成任務 | 決定與理由 | 信賴度 |
| --- | --- | --- | --- | --- | --- |
| A 影片沒中文字幕的幾種合法做法比較 | `影片 沒有 中文字幕 自動 翻譯 合法 本機`；`"影片沒有中文字幕" 怎麼辦` | 混合串流平台字幕設定、瀏覽器擴充功能、雲端產字幕與本機工具；僅說「開啟自動翻譯」不能處理所有情況 | 不能。要先分辨平台影片或自己的本機檔案，再分有文字字幕、只有圖形字幕與無字幕 | 做分流比較文章。題目保留讀者問題，內容以平台原有字幕功能、已有授權文字字幕翻譯、對有權處理的音訊聽寫為路線。不要把「合法取得影片」寫成可以任意翻譯散布 | 中：查詢樣本足夠辨識意圖，但無流量資料 |
| B mkv 內嵌字幕怎麼變雙語 | `mkv 內嵌 字幕 雙語 翻譯`；`"mkv" "雙語字幕" 內嵌 翻譯` | 結果有封裝字幕、翻譯、匯出雙語 SRT、圖形字幕無法直接當文字等不同任務 | 不能。必須分清文字軌、圖形軌與燒錄在影像中的字；有兩條現成字幕和「只有原文需生成譯文」也不同 | 做操作與故障分流文章。主體是選原文文字軌、開翻譯、確認雙語顯示與影片旁的快取；圖形字幕導向語音辨識。不可宣稱所有 MKV 都能直接翻字幕 | 高：repo 能直接對應輸入類型與限制 |
| C 沒字幕的片怎麼自動產生中文字幕 | `沒字幕 影片 自動 產生 中文字幕` | 結果集中於線上產字幕、擴充功能即時字幕與本機 Whisper 流程 | 不能。單說「用 Whisper」漏掉繁中翻譯、額外模型、快取、字幕錯誤與等待原因 | 做本機聽寫教學。清楚分開語音辨識（ASR）與翻譯；不捏造準確率、整片處理時間或支援所有語言的承諾 | 高：README 有完整產品路徑 |
| D 8GB／16GB 記憶體各選哪個模型 | `8GB 16GB Hy-MT2 7B 1.8B 記憶體 模型`；`"8GB" "16GB" "Hy-MT2"` | 有模型硬體需求頁與量化檔大小列表，結果中的硬碟大小、RAM 與 VRAM 口徑不同 | 基本答案能：「8GB 選 1.8B；16GB 以上選 7B」已在 README | 併入 FAQ 的模型選擇段落。若未來獨立成文，必須回答模型檔大小不等於執行記憶體、測試硬體條件與選單尚未實作，不能只是擴寫一句答案 | 高：repo 已明列分流，沒有證據支持獨立流量文 |
| E Hy-MT2 是什麼 | `Hy-MT2 是什麼` | 結果以模型介紹、官方技術報告與模型卡為主 | 定義能：「騰訊公開的多語翻譯模型」即可回答 | 併 FAQ 的術語解釋，接到「它負責翻譯，不負責聽音訊」與人名音譯限制。不要用官方 benchmark 充作 KanDong 實測 | 高：官方 model card 可直接回答定義 |
| F 常見問題頁 | `"看懂" "KanDong" 常見問題`；`site:kandong.twtools.cc 常見問題` | 本次回傳沒有可用的 KanDong 專屬 FAQ 結果；這不等於已證明 Google 未收錄 | 多數單題能，但多題支援集合有導航價值 | 做支援頁，不列為衝點擊文章。收納 D/E、平台支援、隱私前提、人名音譯、模型選單與字幕類型限制，問題文字與 FAQPage 完全一致 | 中：只代表本次查詢觀察 |

優勢：A/B/C 分別處理選擇、內嵌文字軌、無字幕音訊，讀者任務不同；D/E 併 FAQ 可避免只有一句答案的薄頁。
風險：A 範圍容易膨脹成工具排行榜或一般法律保證；B/C 容易把「看到字幕」和「已有可擷取文字」混為一談。以明確輸入條件與產品限制收束，不做來源不明的比較與效能承諾。

## 代表搜尋結果：只供意圖分析

- A：[Chrome 自動產生翻譯字幕教學影片](https://www.youtube.com/watch?v=6i9KIitOfvw)、[YouTube 自動翻譯問題與替代方案](https://wayin.ai/zh-tw/blog/youtube-auto-translate/)：反映平台設定與無字幕影片經常混在同一查詢；不用其產品敘述作 KanDong 證據。
- B：[WatchTranslate 的內嵌字幕說明](https://watchtranslate.com/en/guides/translate-embedded-subtitles)、[字幕翻譯流程頁](https://subtitleflow.com/zh-tw/blog/translate-movie-subtitles)：反映文字軌與圖形軌，以及翻譯前後的格式問題；不用其功能與價格作比較依據。
- C：[線上中文字幕產生器](https://subanana.com/zh-TW/tools/chinese-subtitle)、[本機字幕工具](https://wavesubs.com/)：反映上傳與本機處理兩種意圖；不引用其準確率、支援數量或處理時間。
- D：[Hy-MT2 硬體需求結果](https://modelfit-eight.vercel.app/tencent-hy-mt2-7b-gguf/)、[另一份需求頁](https://llmrun.dev/model/tencent-hy-mt2-7b)：僅觀察結果有不同記憶體口徑，不採其數字。
- E：[官方 Hy-MT2 技術報告](https://arxiv.org/abs/2605.22064)、[Tencent 官方 7B GGUF 模型卡](https://huggingface.co/tencent/Hy-MT2-7B-GGUF)：定義本身已可被摘要回答。
- F：如上兩個精確查詢，本次未找到可用的 KanDong 專屬 FAQ 結果；不將這個觀察擴大為索引狀態的結論。

## 可供文章引用的一手來源

### KanDong 本身

- [README（固定本次基準）](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/README.md)：第 3–4 行定位與本機檔案；第 12–16 行字幕來源、聽寫、快取與介面；第 24–37 行平台、模型選擇與唯一可引用的實測速度；第 41–51 行自訂伺服器和區網；第 69–76 行串流、圖形字幕、人名音譯與模型選單限制。
- [字幕腳本](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/scripts/floattranslate.lua)：可補核字幕提取、ASR 分支與快取行為，不拿腳本參數冒充實測數據。
- [現有圖文教學](https://kandong.twtools.cc/guide/)與 [Releases](https://github.com/dvdmaru/kandong/releases/latest)：每篇導流連結。

### Hy-MT2

- [Tencent 官方 7B GGUF 模型卡](https://huggingface.co/tencent/Hy-MT2-7B-GGUF)。確認：多語翻譯模型、GGUF 發布與本機推論路線。
- [Tencent 官方 1.8B GGUF 模型卡](https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF)。確認：輕量模型確實存在。
- 官方卡另列不同量化版本與其結果；本批不要移植其 benchmark、手機端容量或速度到 KanDong。產品文章只用 README 的模型檔大小與測試條件。

### 語音辨識與播放器

- [whisper.cpp 官方 repo](https://github.com/ggml-org/whisper.cpp)：C/C++ 的 Whisper 實作，支援裝置本機離線執行；這支持「聽音訊轉文字」的角色說明，不支持 KanDong 準確率或速度保證。
- [mpv 官方手冊：Subtitles](https://mpv.io/manual/stable/#subtitles)：`--sid` 與 `--secondary-sid` 可以同時顯示兩條既有字幕。若比較播放器，必須承認這個能力；差異只寫 KanDong 加入翻譯／聽寫流程，不能寫「其他播放器都只能顯示一條字幕」。
- [YouTube 官方管理字幕設定（電腦）](https://support.google.com/youtube/answer/100078?hl=zh-Hant)：有字幕才有相應字幕開關。
- [YouTube 官方管理字幕設定（Android）](https://support.google.com/youtube/answer/100078?co=GENIE.Platform%3DAndroid&hl=zh-Hant)：官方明列選取語言與自動翻譯路徑；引用時標清裝置，不把 Android 操作硬套電腦。
- [YouTube 官方自動產生字幕說明](https://support.google.com/youtube/answer/6373554?hl=zh-Hant)：自動字幕可能受口音、背景雜音與多人重疊語音影響，創作者應審核修正。此為語音辨識一般限制的官方例證，不是 KanDong 測試結果。

### 「合法做法」的表述界線

- [經濟部智慧財產局：電子郵件1110902](https://www.tipo.gov.tw/tw/copyright/692-16773.html)：官方案例談公開網站嵌入影片並加入翻譯字幕，涉及重製、改作與公開傳輸，授權與合理使用須分辨。
- 本文範圍宜寫自製或已取得相應處理授權的檔案、平台提供的字幕設定；不能由「影片是合法取得」推導「翻譯檔可公開散布」，也不能把該公開網站案例硬套成所有私人使用的法律結論。

## 數字口徑提醒

只引用 README 現有內容：7B 約 4.6GB；1.8B 約 1.1GB；Whisper large-v3-turbo 約 574MB；記憶體 16GB 以上／8GB 的選擇；Apple M4／16GB、含 12 句前文、7B 每句約 1–1.5 秒、1.8B 約 0.25 秒。這些是特定環境描述，不換算成其他平台或整片耗時，不另創準確率、使用者數或評價。
