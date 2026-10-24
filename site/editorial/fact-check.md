# 產品與來源查核

基準為 repo `7effeb9e3da2fde611f6f068cf71198e98e6a9ff`；產品事實不沿用舊 FloatTranslate 記憶，記憶僅用來定位新 repo 與寫手規格。

| 主張 | 一手依據 | 界線與信賴度 |
| --- | --- | --- |
| A：串流平台先查提供的字幕語言 | [Netflix 官方字幕設定](https://help.netflix.com/zh-tw/node/372) | 只描述 Netflix 官方選單，不延伸宣稱所有影片都有中文。高。 |
| A/B/C：本機字幕翻譯、無字幕聽寫、PGS 不做 OCR、串流不支援 | [README](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/README.md#L12-L16)、[刻意不做](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/README.md#L67-L75) | 輸入須是有權處理的本機檔案；沒有教下載影片、字幕或繞過 DRM。高。 |
| A：公開網站加翻譯字幕涉及權利處理 | [智慧財產局案例](https://www.tipo.gov.tw/tw/copyright/692-16773.html) | 只轉述該公開網站案例，不拿它判定所有私人利用是否合法。高（對案例轉述）；其他個案不下結論。 |
| B：內嵌文字軌用 FFmpeg 提取、全文不可得時逐句備援 | [字幕腳本](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/scripts/floattranslate.lua#L854-L956) | 不是所有 MKV 都有文字軌；看得到字也可能是圖形或燒錄字幕。高。 |
| B：雙語顯示不等於重新封裝或匯出雙語 SRT | [快取與輸出](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/scripts/floattranslate.lua#L306-L336) | SRT 是翻譯欄位；原文與譯文在播放器疊顯，沒有寫成已把雙語裝回 MKV。高。 |
| B：mpv 可同時顯示兩條既有字幕 | [mpv 官方手冊](https://mpv.io/manual/stable/#subtitles) | 比較只到「既有字幕顯示／生成譯文」；不貶低、不宣稱其他播放器不能雙語。高。 |
| C：Whisper 聽寫、Hy-MT2 翻譯 | [whisper.cpp](https://github.com/ggml-org/whisper.cpp)、[騰訊模型卡](https://huggingface.co/tencent/Hy-MT2-7B-GGUF)、repo README | 不把官方模型 benchmark 移植為 KanDong 實測，不聲稱原文永遠正確。高。 |
| C：Whisper 可能產生音訊中不存在的文字，表現有語言與口音差異 | [Whisper 官方模型卡](https://github.com/openai/whisper/blob/main/model-card.md) | 未捏造 KanDong 準確率或整片處理時間。高。 |
| C：跳段可能留空，完整聽寫與輸出有條件 | [ASR 快取條件](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/scripts/floattranslate.lua#L623-L672) | 不把缺口快取說成完整字幕；不承諾固定等幾秒就有字。高。 |
| D：模型建議、大小、唯一採用的實測 | [README 模型表](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/README.md#L31-L37) | 檔案大小、記憶體建議、實測速度分開；逐數字見 `numbers.md`。高（對 README 記錄的轉述，未重新跑產品 benchmark）。 |
| E：Hy-MT2 為騰訊多語翻譯模型 | [騰訊模型卡](https://huggingface.co/tencent/Hy-MT2-7B-GGUF) | 放 FAQ 定義與分工，不做一行定義擴寫的流量文。高。 |
| F：人名音譯與模型選單尚未實作 | [README 已知限制](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/README.md#L72-L75) | 大模型仍可能音譯；譯名修正是計畫，不是已完成功能。高。 |
| F：預設本機、區網自訂端點會改變資料路徑 | [README 進階設定](https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff/README.md#L39-L51)、字幕腳本 ASR 傳送 | 不把預設隱私前提誇大成任何自訂設定都不上傳。高。 |

篇幅與風格：先有各篇判斷，再依任務安排材料；沒有達到固定篇幅的要求，因此不補使用者數、評價或虛構 benchmark。各選題的優勢與風險見 `serp-research.md`，各篇實際閱讀的摩擦段落見 `reader-review.md`。
