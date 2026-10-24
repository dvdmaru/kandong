# 交 PR 前自檢

驗收日期：2026-10-24，台北時間。基準 `7effeb9e3da2fde611f6f068cf71198e98e6a9ff`。以下是本機待審內容的驗收，不代表正式網站已發佈、Google 已收錄或產品經過新的跨平台效能測試。

| 要求 | 結果 | 可覆查證據 |
| --- | --- | --- |
| 先查六題 SERP 再選題 | 通過；A/B/C 寫任務文，D/E 併 F FAQ，沒有推估流量 | [搜尋紀錄與取捨](serp-research.md) |
| 完整站群寫手規格 | 通過；5094 字元原文區塊逐字相同，SHA256 `dfda10b856607fe395b3ed71ed37e79f2225b1f860db78e84733731ecd751005` | [原文規格](writer-spec.md)；只比規格區塊，不含新增檔頭 |
| 字形檢查先證明能抓簡體 | 通過；簡體測試句抓到 9 個簡體專用字，實際 exit 1；繁體對照通過 | [失敗對照的實際結果](evidence/glyph-negative-control.json)、[全頁結果](evidence/glyphs.json) |
| 正式文案字形 | 通過；7 個 HTML、llms.txt、robots.txt 未發現簡體專用字 | OpenCC 字典比對；區域用語與台／臺等通用異體另外人工讀稿，不把字形檢查說成語意保證 |
| 所有公開連結 | 通過；37 個本機頁面／資源／錨點引用；22 個外部連結最終 HTTP 200 | [本機與錨點](evidence/browser.json)、[外部實連](evidence/external-links.json)；大型模型與 ZIP 用 HEAD，其餘 GET；沒有下載模型或安裝包 |
| Article 可解析 | 通過；三篇文章與 FAQ 共 4 份 Article，H1／headline、canonical／mainEntityOfPage 一致 | [瀏覽器解析](evidence/browser.json)；作者為看懂 KanDong 組織，沒有虛構個人資歷 |
| FAQ 逐字相同 | 通過；首頁、圖文教學與 FAQ 共 3 份 FAQPage、20 個問答；問題與答案均比對 DOM 實際文字 | 同一份瀏覽器紀錄。沒有 FAQ 的文章不加 FAQPage；不是把所有問句都當 FAQ |
| H1 後重點速答與導流 | 通過；三篇文章與 FAQ 均為 H1 直接接速答，每篇連圖文教學與下載 | 瀏覽器 DOM 斷言與公開 HTML |
| 手機沒有橫向超出畫面 | 通過；7 頁 × 320／390／768／1440px；scrollWidth 不超過視窗，也逐元素查邊界，沒有靠 overflow-x:hidden 蓋掉問題 | [寬度讀數](evidence/browser.json)、本目錄 evidence 下 390／1440px 全頁 PNG；人工看過 MKV 手機版及文章／支援頁截圖 |
| sitemap 與 llms.txt | 通過；XML 解析出 7 頁，均有對應 llms 說明；首頁與教學有新入口 | [sitemap](../public/sitemap.xml)、[llms.txt](../public/llms.txt) |
| 每個數字有來源 | 通過；51 段含數字文字節點逐項列出，0 段未對應 | [對照表](numbers.md)、[原始數字紀錄](evidence/numbers.json)；既有 HTML 教學示意數字也納入 |
| 每篇全文閱讀與想跳過的段落 | 已逐篇記錄實際段落、第一句與處置 | [閱讀紀錄](reader-review.md)；不是只寫「已檢查通過」 |
| 功能與限制 | 通過；人名仍可能音譯；模型選單尚未實作；PGS 走聽寫；輸出繁中 SRT 不冒稱雙語匯出 | [事實查核](fact-check.md) |
| 修改範圍 | 僅 site/ | 提交前 `git diff --name-only` 與新增檔 allowlist；未改播放器、啟動器、模型或打包程式 |

## 已發現並修正

- FAQ 多段回答初版的 JSON-LD 與 DOM 在段落交界多一個空白；修正產生器後，逐字比對已通過。
- curl 的檔案大小上限也會對 HEAD 的 Content-Length 生效，初次把大檔標頭誤報成錯誤；改成僅 GET 限制大小，再逐一重驗，所有 HEAD 回應成功。沒有把失敗硬標成通過。
- 移除既有教學中 README 沒提供的等待秒數、固定倍速追趕門檻與啟動失敗原因的機率斷言。
- 首頁的隱私說明補上預設本機的前提；人名音譯補明大模型也可能發生；字幕超前處理不再寫成開播前已翻完整部。
- 舊頁面移除遮蔽式 overflow-x:hidden，修正盒模型與圖片卡片最小寬度，再實測頁面與元素邊界。

## SEO／GEO／AEO 的效益界線

依 [Google 官方文件更新](https://developers.google.com/search/updates#june-2026)，FAQ 複合式搜尋結果已停止顯示；Google 也明示 llms.txt 不影響 Google 搜尋能見度或排名。本批保留 FAQPage 語意標記與 llms.txt 作為使用者指定的內容描述，但不宣稱它們能保證 AI 引用、點擊或收錄。Article 欄位參照 [Google 官方 Article 文件](https://developers.google.com/search/docs/appearance/structured-data/article)。

優勢：靜態 HTML 直接提供答案、操作與來源，並依輸入條件分流；無須額外前端執行才讀得到內容。風險：模型、介面與官方說明會變動；本批用固定 repo 版本連結保留當時依據，未驗證未來版本。查核信賴度高（對本批檔案與來源轉述）；搜尋流量與排名效果沒有數據，不做機率估計。

## 重跑方式

從 repo 根目錄執行。OpenCC 可裝在暫存 Python 虛擬環境；Playwright 使用已安裝的模組，以環境變數給路徑，不把工作機路徑或依賴裝進播放器。

```bash
python3 site/tools/build-pages.py
python3 site/tools/check-glyphs.py --text '这段视频没有中文字幕，翻译失败，请下载轻量模型。'
# 上一行預期 exit 1；正式文案預期 exit 0：
python3 site/tools/check-glyphs.py
python3 -m http.server 7826 --bind 127.0.0.1 --directory site/public
# 在另一個終端機：
node site/tools/check-browser.mjs
python3 site/tools/check-external-links.py
python3 site/tools/check-numbers.py
git diff --check
```

瀏覽器驗收攔下分析追蹤腳本，避免驗收瀏覽灌入 GA4；沒有把分析服務列為已做事件測試。外部連結與下載 HEAD 另以真實網路確認。沒有宣稱完成 Google Rich Results Test、Windows 實機操作或新的產品 benchmark。
