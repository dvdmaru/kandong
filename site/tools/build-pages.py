"""Build the static editorial pages; no player or deployment code is involved."""
from pathlib import Path
import html
import json

PUBLIC = Path(__file__).resolve().parents[1] / 'public'
BASE = 'https://kandong.twtools.cc'
DATE = '2026-10-24'
STAMP = DATE + 'T23:45:00+08:00'
REV = '7effeb9e3da2fde611f6f068cf71198e98e6a9ff'
REPO = f'https://github.com/dvdmaru/kandong/blob/{REV}'
README = REPO + '/README.md'
DOWNLOAD = 'https://github.com/dvdmaru/kandong/releases/latest'


def link(url, label):
    return f'<a href="{html.escape(url, quote=True)}">{label}</a>'


def sources(items):
    return '<section class="sources"><h2>來源與適用範圍</h2><ul>' + ''.join(
        f'<li>{link(url, label)}</li>' for url, label in items
    ) + '</ul><p>看懂功能以本次連結的 README 與原始碼版本為準；新版介面與行為可能調整。</p></section>'


PAGES = [
    {
        'slug': 'no-chinese-subtitles',
        'tag': '還不確定是哪種',
        'tone': 'sun',
        'title': '影片沒中文字幕怎麼辦？先分清串流、有字幕與沒字幕',
        'description': '串流平台先找平台提供的字幕；自己的影片檔有英文字幕就直接翻成繁中，完全沒字幕才需要先聽寫。看懂不支援 Netflix 等串流，也不做圖形字幕 OCR。',
        'answer': '影片沒中文字幕，先看影片在哪裡：串流平台用平台提供的字幕選項；有權處理的本機檔案，有文字字幕就翻譯，沒字幕就先語音辨識再翻譯。看懂 KanDong 處理本機影片檔，不支援 Netflix 等串流平台。',
        'body': f'''
<p>畫面明明有英文，播放器卻找不到中文字幕。先別急著換工具：英文可能是可選的字幕軌，也可能已經印在影像上。看起來相同，能用的做法差很多。</p>
<h2 id="choose">先看影片在哪裡，再決定要翻字還是聽聲音</h2>
<div class="options">
<section><h3>正在串流平台上看</h3><p>先開平台的音訊與字幕選單。若影片提供你要的字幕，直接選就能看，不必另外跑模型。</p><p><strong>好處：</strong>沿用平台播放流程。<strong>限制：</strong>只能選平台提供的語言；看懂不攔截串流，也不破解數位版權管理（DRM）。</p></section>
<section><h3>自己的影片檔已有原文文字字幕</h3><p>有權處理的影片與字幕，可以交給看懂翻譯。外掛 SRT、ASS、WebVTT，以及 MKV 內嵌文字字幕都在支援範圍內。</p><p><strong>好處：</strong>沿用字幕已有的文字與時間軸。<strong>限制：</strong>原文字幕若漏句或時間不對，翻譯不會把原始問題一起修好。</p></section>
<section><h3>檔案沒字幕，或只有圖形字幕</h3><p>先用語音辨識（ASR）聽寫原文，再把原文翻成繁中。看懂使用 whisper.cpp 做聽寫，Hy-MT2 做翻譯。</p><p><strong>好處：</strong>不必先有文字字幕。<strong>限制：</strong>多一道聽寫；聽錯的原文會連帶影響譯文。看懂不做圖形字幕的文字辨識（OCR）。</p></section>
</div>
<h2 id="streaming">平台有字幕選單，也不代表每部片都有中文</h2>
<p>以 Netflix 為例，{link('https://help.netflix.com/zh-tw/node/372', '官方說明')}是從播放畫面的「音訊和字幕」選擇該片提供的語言。選單裡沒有中文，就不能靠看懂替串流畫面加上翻譯。</p>
<p>這時若仍想在平台觀看，先查平台對該片的字幕支援。若手邊另有自製或取得相應處理授權的本機檔案，才走下面的本機流程。</p>
<h2 id="text">檔案已有英文字幕，就不必重新聽寫</h2>
<p>把影片拖進看懂，選好原文字幕軌，開啟翻譯。原文保留在畫面上，繁中譯文加在下方；能取得字幕全文時，程式會超前預譯，翻好的內容快取在影片旁。</p>
<p>MKV 是檔案封裝格式，副檔名本身不能告訴你字幕是哪一種。先在字幕選單確認：有可讀取的文字軌，才走直接翻譯；只有圖形字幕，則改從音訊聽寫。操作可接著看 {link('/articles/mkv-bilingual-subtitles/', 'MKV 內嵌字幕變雙語教學')}。</p>
<h2 id="audio">完全沒字幕，要先讓聲音變成文字</h2>
<p>只有翻譯模型還不夠。你也需要語音辨識模型，讓看懂先取得對白文字，再翻成中文字幕。具體安裝與排查步驟在{link('/articles/auto-chinese-subtitles/', '無字幕影片產生中文字幕教學')}。</p>
<p>如果只是燒錄在影像上的字，畫面上看得到，字幕選單卻沒有可用文字軌，看懂也不會去讀影像裡的字。走聽寫時，生成的字幕跟著聲音走，不會保留畫面上原有字幕的排版。</p>
<h2 id="rights">能翻譯，不代表能把譯文公開散布</h2>
<p>本文的本機流程以自製或已取得相應處理授權的影片、字幕為前提。{link('https://www.tipo.gov.tw/tw/copyright/692-16773.html', '智慧財產局的公開網站加譯字幕案例')}指出，加入翻譯字幕可能涉及重製、改作及公開傳輸，須分辨授權與合理使用。該案例不能直接當成所有私人使用情況的結論。</p>
<p>想選最省事的做法，就先找現成可用的字幕選項。已有原文文字字幕，直接翻譯；缺少文字字幕，才多做聽寫。工具的選擇跟著素材走。</p>
''' + sources([(README, '看懂 README：字幕來源、聽寫、串流與圖形字幕限制')]),
    },
    {
        'slug': 'mkv-bilingual-subtitles',
        'tag': '檔案裡有原文字幕',
        'tone': 'rose',
        'title': 'MKV 內嵌字幕怎麼變雙語？文字軌直接翻，圖形軌改聽寫',
        'description': '看懂可翻譯 MKV 內嵌文字字幕，保留原文並加上繁中譯文。先選對字幕軌，再排查圖形字幕、燒錄字幕、翻譯開關與快取的差異。',
        'answer': 'MKV 內嵌的是原文文字字幕時，用看懂選好字幕軌並開啟翻譯，就能保留原文、在下方顯示繁中譯文。若內嵌的是 PGS 等圖形字幕，看懂會改走語音辨識再翻譯，不會直接辨識字幕圖片。',
        'body': f'''
<p>影片裡有英文字幕，卻翻不出中文，問題可能出在字幕的形態。MKV 能裝文字，也能裝圖片；播放器能顯示圖片，不代表翻譯模型拿得到文字。</p>
<h2 id="track">先選原文字幕軌，別只看副檔名</h2>
<p>以下操作適用自製或已取得相應處理授權的本機影片。第一次使用先照{link('/guide/', '圖文教學')}完成播放器與翻譯模型的準備，再用「看懂」啟動，把 MKV 檔拖進播放器。</p>
<ol><li>按滑鼠右鍵，打開字幕選單，選擇要翻譯的原文字幕軌。</li><li>確認原文字幕出現。如果原文一直沒出現，先處理字幕選軌，不必反覆重開翻譯。</li><li>開檔後翻譯會自動開始，確認原文下方出現繁中譯文。如果剛才按過 <kbd>Ctrl+t</kbd> 把翻譯關掉，再按一次就會打開。</li></ol>
<figure><img src="/img/menu-subtitles.jpg" alt="看懂播放器的字幕子選單，可選擇字幕軌" width="1024" loading="lazy"><figcaption>看懂現有介面的字幕選單畫面；字幕軌內容依影片而異。</figcaption></figure>
<h2 id="type">看得到字，仍可能沒有可讀取的文字字幕</h2>
<div class="options"><section><h3>內嵌文字字幕</h3><p>看懂透過 FFmpeg 讀出文字字幕，接到翻譯流程。程式能取得全文時會超前預譯；目前播放到的句子會優先處理。</p></section>
<section><h3>PGS 等圖形字幕</h3><p>字幕內容是一張張圖片。看懂不做 OCR，改用音訊聽寫取得對白。這條路需要另外準備語音辨識模型。</p></section>
<section><h3>字幕燒錄在影像裡</h3><p>字是影片畫面的一部分，沒有獨立字幕軌可選。看懂的無字幕流程會從聲音聽寫，無法把畫面上的文字抽成原文字幕。</p></section></div>
<p>內嵌文字軌若無法讀取全文，程式也可能退回逐句翻譯；畫面出現相關訊息時，不要把它誤認成整部字幕已經翻完。沒有可用文字時，接著看{link('/articles/auto-chinese-subtitles/', '無字幕聽寫流程')}。</p>
<h2 id="cache">雙語是播放時的顯示，沒有重新封裝原本的 MKV</h2>
<p>看懂把原文字幕留在畫面上，再疊上繁中譯文。譯文快取存成影片旁的 <code>&lt;影片名&gt;.ft.zh-TW.json</code>；完整翻譯完成後，還會輸出 <code>.ft.zh-TW.srt</code>。原本的 MKV 不會因此新增一條內嵌字幕軌。</p>
<p>輸出的 SRT 只有繁中譯文，沒有原文。換到其他播放器時，要同時看原文，得另外載入原文字幕。</p>
<p>{link('https://mpv.io/manual/stable/#subtitles', 'mpv 官方手冊')}本來就提供主、次字幕軌選擇，可以同時顯示兩條既有字幕。看懂加入的是把原文翻成繁中、管理快取的流程；已有現成雙語字幕的人，需求可能只是選好字幕軌。</p>
<h2 id="trouble">只有原文沒有中文，先查開關與啟動方式</h2>
<ul><li><strong>翻譯被關掉：</strong>確認 <kbd>Ctrl+t</kbd> 的切換狀態。</li><li><strong>翻譯服務連不上：</strong>用「看懂」啟動器開啟，讓它先準備翻譯引擎；不要直接開播放器執行檔。</li><li><strong>只有圖形字幕：</strong>確認語音辨識模型也已備妥。</li><li><strong>中文出現，但人名和預期不同：</strong>Hy-MT2 常把人名音譯，例如 Marcus 變成「馬庫斯」，換大模型仍可能發生。</li></ul>
<p>先把輸入分清楚，排查就有方向：文字軌查翻譯，圖形軌查聽寫；想把字幕重新包進 MKV，則超出看懂目前的播放與快取流程。</p>
''' + sources([(README, '看懂 README：字幕、快取、快捷鍵與人名限制'), (REPO + '/scripts/floattranslate.lua', '字幕腳本：選軌、內嵌字幕提取、逐句備援與快取輸出'), ('https://mpv.io/manual/stable/#subtitles', 'mpv 官方手冊：字幕選擇')]),
    },
    {
        'slug': 'auto-chinese-subtitles',
        'tag': '完全沒字幕',
        'tone': 'mint',
        'title': '沒字幕的影片怎麼自動產生中文字幕？先聽寫，再翻繁中',
        'description': '沒字幕的影片要先用 Whisper 把對白聽寫成原文，再用 Hy-MT2 翻成繁中；除了翻譯模型，還要多下載約 574MB 的語音辨識模型。',
        'answer': '沒字幕的本機影片，要先用語音辨識把對白轉成原文，再翻成中文字幕。看懂用 whisper.cpp 聽寫、Hy-MT2 翻譯；除了翻譯模型，還要準備 Whisper large-v3-turbo 語音辨識模型。',
        'body': f'''
<p>播放器已經能翻譯，為什麼碰到沒字幕的影片卻沒反應？翻譯模型要先拿到文字；影片只有聲音時，還差一個把聲音變成文字的步驟。</p>
<h2 id="roles">Whisper 負責聽，Hy-MT2 負責翻</h2>
<p>看懂先把音訊交給 whisper.cpp，產生原文與時間軸，再把原文交給 Hy-MT2，顯示原文與繁中譯文。原文聽錯，譯文也可能跟著錯，所以遇到怪句時，先對照原文那一行。</p>
<p>{link('https://github.com/ggml-org/whisper.cpp', 'whisper.cpp')} 是 Whisper 的本機執行實作。這個分工也表示：只有 Hy-MT2 模型，不能直接把一段聲音翻成中文字幕。</p>
<h2 id="prepare">翻譯模型之外，還要準備語音辨識模型</h2>
<p>先依{link('/guide/', '圖文教學')}下載並解壓看懂。使用「一鍵下載模型」準備翻譯模型後，再選語音辨識模型；這裡下載的是模型，不是影片或字幕。</p>
<div class="options"><section><h3>翻譯模型</h3><p>README 建議記憶體 8GB 或較舊的電腦用 Hy-MT2 1.8B，16GB 以上用 7B。模型檔約為 1.1GB 與 4.6GB；檔案大小不等於執行時只需要同樣多的記憶體。</p></section>
<section><h3>語音辨識模型</h3><p>Whisper large-v3-turbo 約 574MB。原本已有可用文字字幕的影片不需要這一步；無字幕或只有圖形字幕時才需要。</p></section></div>
<p>Mac 版適用 Apple 晶片，還要完成圖文教學中的 Homebrew 工具安裝。兩個翻譯模型都放進資料夾時，啟動器會依記憶體選擇；目前「模型」選單仍是預告，不能靠選單直接切換。</p>
<h2 id="play">用「看懂」啟動，讓聽寫先累積字幕</h2>
<ol><li>準備一個自製或已取得相應處理授權、含對白的影片檔。</li><li>雙擊「看懂」，Mac 則用「看懂.command」。讓啟動器準備引擎，再把影片拖進播放器。</li><li>先用正常速度播放，等聽寫與翻譯產生內容，再確認原文和繁中是否都出現。聽寫是分段處理，不是開檔就瞬間取得整部字幕。</li></ol>
<p>若畫面顯示「語音辨識跟不上」，先按 <kbd>S</kbd> 回到正常速度。跳轉或播放超過處理進度時，尚未完成的區段可能沒有字幕；不能把字幕空白直接判成那一段沒有對白。</p>
<h2 id="errors">字幕不對，先分辨是聽錯還是翻錯</h2>
<ul><li><strong>原文就不對：</strong>先回聽音訊。{link('https://github.com/openai/whisper/blob/main/model-card.md', 'Whisper 官方模型卡')}列出語言、口音與使用情況造成的表現差異，也提醒可能產生音訊中不存在的文字。</li><li><strong>原文對、中文不對：</strong>再看翻譯；機器翻譯仍會出錯。</li><li><strong>人名變成中文譯音：</strong>這是看懂已知限制，換大模型也不保證保留原名。</li><li><strong>一直沒有字幕：</strong>確認語音辨識模型已備妥，並查看畫面訊息與啟動記錄，接著查{link('/faq/', '常見問題')}。</li></ul>
<h2 id="save">完整聽寫會留在影片旁，跳過的區段不冒充完成</h2>
<p>完整轉寫可存成影片旁的 <code>&lt;影片名&gt;.ft.asr.srt</code>，下次開啟時當成已有字幕處理。翻好的繁中另有 <code>.ft.zh-TW.json</code> 快取，完整翻譯後才輸出繁中 SRT。</p>
<p>如果播放過程曾跳過尚未轉寫的區段，程式不會把有缺口的轉寫存成完整字幕。想重看同一段，先讓聽寫補上文字；重要內容則回到聲音與原文核對。</p>
<p>無字幕影片能不能順利看懂，關鍵是先把原文聽對。保留原文與繁中一起看，才有機會發現錯誤發生在哪一步。</p>
''' + sources([(README, '看懂 README：模型大小、記憶體建議、平台與已知限制'), (REPO + '/scripts/floattranslate.lua', '字幕腳本：分段聽寫、跳段與快取條件'), ('https://github.com/ggml-org/whisper.cpp', 'whisper.cpp 官方專案'), ('https://github.com/openai/whisper/blob/main/model-card.md', 'Whisper 官方模型卡：限制')]),
    },
]

FAQ = [
    ('models', '8GB／16GB 記憶體，各選哪個模型？', f'''<p>依 README 建議：8GB 或較舊的電腦選 Hy-MT2 1.8B 輕量模型，16GB 以上選 7B 標準模型。模型檔分別約 1.1GB、4.6GB；這是檔案大小，不是整套程式的記憶體用量。</p><p>README 的實測條件是 Apple M4／16GB、含 12 句前文：7B 每句約 1–1.5 秒，1.8B 約 0.25 秒。這些結果不能推算成其他硬體或整部影片的處理時間。</p><p>要先減輕負擔，可從輕量模型開始；想用標準模型，仍需看其他程式占用的記憶體。{link(README, '查看 README 的模型與實測說明')}。</p>'''),
    ('hy-mt2', 'Hy-MT2 是什麼？能直接聽影片嗎？', f'''<p>Hy-MT2 是騰訊（Tencent）公開的多語翻譯模型。看懂用它把原文字幕翻成台灣繁中；聽音訊轉文字則由 whisper.cpp 負責。沒字幕的影片需要兩種模型，不能只準備翻譯模型。</p><p>{link('https://huggingface.co/tencent/Hy-MT2-7B-GGUF', '騰訊官方標準模型卡')}、{link('https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF', '輕量模型卡')}。</p>'''),
    ('switch', '為什麼按「模型」選單不能切換？', '<p>目前「模型」選單只是預告。換模型要調整 models 資料夾裡的模型檔；兩個翻譯模型都在時，啟動器會依記憶體自動挑選。若要固定用輕量模型，先把標準模型移出 models，關閉後再重新啟動看懂。</p>'),
    ('names', '人名會保留原文嗎？換大模型能解決嗎？', '<p>不保證。Hy-MT2 常把人名音譯，例如 Marcus 變成「馬庫斯」；換大模型也可能發生。譯名修正還在規劃中。</p>'),
    ('platforms', '支援哪些電腦？可以看 Netflix 嗎？', '<p>下載包提供 Windows 10／11（64 位元）與 macOS Apple 晶片版；Mac 需要先裝 Homebrew 工具。看懂只處理本機影片檔，不支援 Netflix 等串流平台，不攔截串流，也不破解 DRM。</p>'),
    ('privacy', '影片和字幕會上傳嗎？需要一直連網嗎？', '<p>預設本機設定下，翻譯與語音辨識在自己的電腦執行，影片和字幕不會送到雲端翻譯服務；取得軟體、工具和模型仍需要網路。進階設定若把伺服器指向區網另一台電腦，字幕或聽寫用音訊就會送到那台電腦處理，因此本機處理的前提也會改變。</p>'),
    ('bitmap', '影片看得到字幕，為什麼還要語音辨識模型？', f'<p>看得到的字可能是 PGS 等圖形字幕，或已燒錄在影像中。看懂不做 OCR；沒有可用文字軌時，改從聲音聽寫再翻譯。先看 {link("/articles/mkv-bilingual-subtitles/", "MKV 字幕類型的分辨方式")}。</p>'),
    ('connection', '出現「翻譯伺服器連線失敗」怎麼辦？', '<p>先確認是用「看懂」啟動器開啟，而非直接開播放器執行檔。啟動器會先準備翻譯引擎；若仍失敗，再查模型檔、啟動畫面與 logs 記錄。</p>'),
    ('speed', '語音辨識跟不上，字幕一直空白怎麼辦？', f'<p>先按 S 回到正常播放速度，確認 Whisper 語音辨識模型已備妥，再讓聽寫繼續。播放超過處理進度或跳轉到未處理段落時可能空白；完整步驟見{link("/articles/auto-chinese-subtitles/", "沒字幕影片聽寫教學")}。</p>'),
    ('cache', '翻好的字幕在哪裡？是雙語 SRT 嗎？', '<p>繁中快取在影片旁的 &lt;影片名&gt;.ft.zh-TW.json，完整翻譯後才輸出 .ft.zh-TW.srt；完整聽寫另可存成 .ft.asr.srt。這份 SRT 只有繁中譯文；原文與譯文一起出現的雙語畫面，是播放時在看懂裡疊出來的。</p>'),
]


def plain(fragment):
    from html.parser import HTMLParser

    class Text(HTMLParser):
        def __init__(self):
            super().__init__()
            self.parts = []

        def handle_data(self, data):
            self.parts.append(data)

    parser = Text()
    parser.feed(fragment)
    return ' '.join(''.join(parser.parts).split())


GA = 'G-R9KBKJFEH1'
FAVICON = ("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' "
           "fill='%237c4241'/%3E%3Ctext x='16' y='23' font-size='19' text-anchor='middle' fill='%23fff8f2' font-family='serif' "
           "font-weight='900'%3E懂%3C/text%3E%3C/svg%3E")
FONTS = ('https://fonts.googleapis.com/css2?family=Noto+Sans+TC:wght@400;500;700;900'
         '&family=Noto+Serif+TC:wght@900&family=JetBrains+Mono:wght@500&display=swap')
NAV = [('/guide/', '圖文教學'), ('/articles/', '字幕指南'), ('/faq/', '常見問題')]

# Same header, footer, fonts and analytics as the landing page and visual tutorial.
FAQ_GROUPS = [
    ('g-models', '選模型', 'sun', ['models', 'hy-mt2', 'switch']),
    ('g-platform', '支援與隱私', 'rose', ['platforms', 'privacy']),
    ('g-trouble', '字幕沒出現', 'mint', ['bitmap', 'connection', 'speed']),
    ('g-result', '翻譯結果', 'paper', ['names', 'cache']),
]
FAQ_BY_ID = {i: (i, q, a) for i, q, a in FAQ}
assert sorted(FAQ_BY_ID) == sorted(i for g in FAQ_GROUPS for i in g[3]), 'every FAQ item belongs to one group'
FAQ_ORDERED = [FAQ_BY_ID[i] for g in FAQ_GROUPS for i in g[3]]


def button(url, label, light=False):
    return f'<a class="button{" light" if light else ""}" href="{html.escape(url, quote=True)}">{label}</a>'


def band(title, text, buttons):
    return (f'<aside class="band"><div class="band-text"><h2>{title}</h2><p>{text}</p></div>'
            f'<div class="actions">{"".join(buttons)}</div></aside>')


def render(path, title, description, answer, body, article=False, faq=None, heading=None,
           eyebrow='', width='article', after=''):
    url = BASE + path
    schemas = []
    if article:
        schemas.append({'@type': 'Article', '@id': url + '#article', 'headline': title,
                        'description': description, 'inLanguage': 'zh-TW',
                        'datePublished': STAMP, 'dateModified': STAMP,
                        'author': {'@type': 'Organization', 'name': '看懂 KanDong', 'url': BASE + '/'},
                        'publisher': {'@type': 'Organization', 'name': '看懂 KanDong', 'url': BASE + '/'},
                        'mainEntityOfPage': url, 'image': [BASE + '/img/watching.jpg'],
                        'isAccessibleForFree': True})
    if faq:
        schemas.append({'@type': 'FAQPage', '@id': url + '#faq', 'mainEntity': [
            {'@type': 'Question', 'name': q, 'acceptedAnswer': {'@type': 'Answer', 'text': plain(a)}}
            for _, q, a in faq]})
    structured = '\n<script type="application/ld+json">' + json.dumps(
        {'@context': 'https://schema.org', '@graph': schemas}, ensure_ascii=False
    ) + '</script>' if schemas else ''
    if heading:
        assert plain(heading) == title or not article, 'Article headline must equal the visible h1'
    current = ' aria-current="page"'
    nav = ''.join(f'<a href="{href}"{current if path.startswith(href) else ""}>{label}</a>' for href, label in NAV)
    document = f'''<!doctype html>
<html lang="zh-Hant-TW"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}｜看懂 KanDong</title>
<meta name="description" content="{html.escape(description, quote=True)}">
<link rel="canonical" href="{url}">
<meta property="og:type" content="{'article' if article else 'website'}">
<meta property="og:title" content="{html.escape(title, quote=True)}">
<meta property="og:description" content="{html.escape(description, quote=True)}">
<meta property="og:url" content="{url}"><meta property="og:site_name" content="看懂 KanDong">
<meta property="og:image" content="{BASE}/img/og.png"><meta property="og:locale" content="zh_TW">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="{FAVICON}">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="{html.escape(FONTS, quote=True)}">
<link rel="stylesheet" href="/reading.css">
<script async src="https://www.googletagmanager.com/gtag/js?id={GA}"></script>
<script>
window.dataLayer = window.dataLayer || [];
function gtag(){{dataLayer.push(arguments);}}
gtag('js', new Date());
gtag('config', '{GA}');
</script>{structured}
</head><body>
<a class="skip" href="#main">跳到內容</a>
<header class="site-header"><div class="bar">
<a class="logo" href="/" aria-label="看懂 KanDong 首頁"><span class="logo-mark" aria-hidden="true">懂</span><span class="logo-word">看懂</span></a>
<nav class="site-nav" aria-label="主選單">{nav}<a class="pill" href="/#download">免費下載</a></nav>
</div></header>
<main id="main"><article class="{width}">
<p class="eyebrow">{eyebrow}</p>
<h1>{heading or html.escape(title)}</h1>
<div class="quick-answer"><span class="label">重點速答</span><p>{answer}</p></div>
{body}
{after}
</article></main>
<footer class="site-footer"><div class="bar">
<span>看懂 KanDong・<a href="https://twtools.cc/">TWTools</a> 家族作品</span>
<span><a href="https://github.com/dvdmaru/kandong">原始碼</a>・MIT 授權</span>
</div></footer>
</body></html>
'''
    target = PUBLIC / path.strip('/') / 'index.html'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(document)


ARTICLE_EYEBROW = f'<a href="/articles/">字幕指南</a>　／　<time datetime="{DATE}">{DATE}</time>'
for n, page in enumerate(PAGES):
    related = '<nav class="related" aria-label="其他字幕指南">' + ''.join(
        f'<a href="/articles/{p["slug"]}/"><small>{"下一篇" if k == 0 else "也可以看"}・{p["tag"]}</small><strong>{p["title"]}</strong></a>'
        for k, p in enumerate(PAGES[n + 1:] + PAGES[:n])) + '</nav>'
    cta = band('準備好自己的影片檔，再開始', '先照圖文教學完成設定，再挑適合字幕來源的流程。',
               [button('/guide/', '看圖文教學'), button(DOWNLOAD, '下載最新版', light=True)])
    render('/articles/' + page['slug'] + '/', page['title'], page['description'], page['answer'], page['body'],
           article=True, eyebrow=ARTICLE_EYEBROW, after=cta + related)

faq_body = '<p class="lead">先找眼前卡住的問題。模型選擇與名稱說明放在一起，安裝畫面則留在圖文教學。</p>'
faq_body += '<nav class="chips" aria-label="問題分類">' + ''.join(
    f'<a class="tone-{tone}" href="#{gid}">{label}</a>' for gid, label, tone, _ in FAQ_GROUPS) + '</nav>'
for gid, label, tone, ids in FAQ_GROUPS:
    faq_body += (f'<section class="faq-group tone-{tone}" id="{gid}"><h2><span class="dot" aria-hidden="true"></span>{label}</h2>'
                 '<div class="faq-list">' + ''.join(
                     f'<section class="faq-item" id="{i}"><h3>{q}</h3><div class="faq-answer">{a}</div></section>'
                     for i, q, a in (FAQ_BY_ID[x] for x in ids)) + '</div></section>')
faq_after = band('還是不行？', '到 GitHub Issues 開一則，附上作業系統、影片格式、畫面上的訊息，和 logs 資料夾裡的記錄。',
                 [button('https://github.com/dvdmaru/kandong/issues', '開 Issue'), button('/guide/', '圖文教學', light=True),
                  button(DOWNLOAD, '下載最新版', light=True)])
faq_after += sources([(README, '看懂 README：模型、平台、進階連線與限制'), (REPO + '/mac/kandong.sh', 'Mac 啟動器：模型檔選擇'), (REPO + '/scripts/floattranslate.lua', '字幕腳本：傳送音訊、翻譯與快取條件')])
render('/faq/', '看懂常見問題：模型怎麼選、字幕沒出現與人名音譯',
       '8GB／16GB 模型選擇、Hy-MT2 與 Whisper 分工、切換模型、平台支援、隱私設定和字幕排查。',
       '選模型先看記憶體；沒字幕的片還需要語音辨識模型。看懂處理本機影片，常見卡關包括選錯字幕類型、引擎未啟動，以及人名被音譯。',
       faq_body, article=True, faq=FAQ_ORDERED, width='medium', eyebrow='常見問題',
       heading='看懂<span class="hl">常見問題</span>：模型怎麼選、字幕沒出現與人名音譯', after=faq_after)

cards = '<h2>你的影片是哪一種？</h2><div class="cards">' + ''.join(
    f'<a class="card tone-{p["tone"]}" href="/articles/{p["slug"]}/"><span class="card-top"><span class="num" aria-hidden="true">{n}</span>'
    f'<span class="tag">{p["tag"]}</span></span><h3>{p["title"]}</h3><p>{p["description"]}</p><span class="more">讀這篇 →</span></a>'
    for n, p in enumerate(PAGES, 1)) + '</div>'
render('/articles/', '字幕指南：從沒有中文字幕，到看懂外語影片',
       '依影片來源找做法：串流字幕選項、MKV 內嵌文字字幕翻譯，以及無字幕影片聽寫。模型與故障排查另見常見問題。',
       '串流平台先找平台字幕；本機檔案已有文字字幕就翻譯，沒有文字才聽寫。依手邊影片的情況選一篇，模型選擇與故障排查可直接查常見問題。',
       cards, width='wide', eyebrow='字幕指南', heading='從沒有中文字幕，到<span class="hl">看懂</span>外語影片',
       after=band('選模型、卡關排查', '8GB／16GB 該選哪個模型、字幕沒出現、人名被音譯，都整理在常見問題。',
                  [button('/faq/#models', '看常見問題'), button('/guide/', '圖文教學', light=True)]))

routes = ['/', '/guide/', '/articles/'] + ['/articles/' + p['slug'] + '/' for p in PAGES] + ['/faq/']
(PUBLIC / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{BASE}{r}</loc><lastmod>{DATE}</lastmod></url>\n' for r in routes) + '</urlset>\n')
(PUBLIC / 'llms.txt').write_text(f'''# 看懂 KanDong

> 免費開源的本機影片播放器；翻譯文字字幕，或先聽寫無字幕音訊再翻成台灣繁中。預設由使用者自己的電腦處理。不提供影片、不下載字幕，不支援串流或破解 DRM。人名可能音譯。

## 產品與開始使用
- [首頁與下載]({BASE}/)：產品能做什麼、Windows／Mac 下載與基本限制。
- [圖文教學]({BASE}/guide/)：下載解壓、準備模型與啟動步驟；安裝畫面含示意圖。
- [字幕指南]({BASE}/articles/)：依字幕來源選擇處理流程。

## 影片與字幕問題
''' + ''.join(f'- [{p["title"]}]({BASE}/articles/{p["slug"]}/)：{p["description"]}\n' for p in PAGES) + f'''
## 使用支援
- [常見問題]({BASE}/faq/)：8GB／16GB 模型建議、Hy-MT2 與 Whisper 分工、人名音譯、模型選單尚未實作、連線、快取與本機處理的前提。
- [原始碼與 README](https://github.com/dvdmaru/kandong)：功能、唯一引用的產品實測條件與已知限制。
- [最新版]({DOWNLOAD})：取得播放器下載包。

## 引用範圍
產品實測只見 README 的 Apple M4／16GB 條件；不推算其他硬體速度、準確率或整片處理時間。模型檔案大小不是執行記憶體需求。字幕產生與翻譯不代表取得公開散布授權。
''')

# Keep the existing landing page and visual tutorial discoverable. FAQ markup
# is derived from their actual displayed questions and answers.
import re
for legacy in ['index.html', 'guide/index.html']:
    target = PUBLIC / legacy
    content = target.read_text()
    content = content.replace('html,body{margin:0;background:#fff8f2;overflow-x:hidden}',
                              '*{box-sizing:border-box}html,body{margin:0;background:#fff8f2}')
    content = content.replace('minmax(300px, 1fr)', 'minmax(min(100%, 300px), 1fr)')
    marker = '      <nav style="display: flex; gap: 20px; font-size: 15px; flex-wrap: wrap; align-items: center">'
    additions = '\n        <a href="/articles/" style="color: #5a4845; text-decoration: none">字幕指南</a>\n        <a href="/faq/" style="color: #5a4845; text-decoration: none">完整 FAQ</a>'
    if 'href="/articles/"' not in content:
        content = content.replace(marker, marker + additions)
    content = content.replace('（第一次 10–60 秒）', '（載入時間依電腦而異）')
    content = content.replace('約 20–30 秒後出現第一段字幕；', '聽寫與翻譯完成後才會出現字幕；')
    content = content.replace('開 2 倍速以上若出現', '若出現')
    content = content.replace('一般對話、口語大多自然；人名常被音譯（例如 Marcus 變成「馬庫斯」），之後會改進。',
                              '人名常被音譯（例如 Marcus 變成「馬庫斯」），換大模型也可能發生；譯名修正仍在計畫中。')
    content = content.replace('不會。翻譯和語音辨識都在你自己的電腦上跑，播放器不連任何雲端服務。只有第一次下載模型時會連到 Hugging Face。',
                              '預設本機設定下，翻譯和語音辨識在自己的電腦執行，影片和字幕不送到雲端翻譯服務。取得軟體、工具與模型仍需要網路；若自行設定區網伺服器，資料會送到指定電腦。')
    content = content.replace('實測 Apple M4／16GB 每句約 1–1.5 秒', 'README 實測 Apple M4／16GB、含 12 句前文，7B 每句約 1–1.5 秒')
    content = content.replace('整部片先翻好，看的時候不用等。', '能讀取全文時會超前預譯，已翻好的句子會快取。')
    content = content.replace('有字幕的片會先翻好整部。', '有字幕的片會超前預譯。')
    content = content.replace('沒有花錢買數位簽章，所以 Windows 不認得它。', '目前沒有數位簽章，因此可能出現這個提示。')
    content = content.replace('就好，之後不會再問。', '；是否再次提示依系統狀態而異。')
    content = content.replace('多半是記憶體不夠：改用輕量模型（一鍵下載選 2）。', '先查記憶體與模型檔是否完整；可改用輕量模型（一鍵下載選 2）。')
    content = content.replace('選單目前只是預告', '選單目前只是預告')
    # Idempotent regeneration after a wording correction.
    content = re.sub(r'\n<!-- editorial-faq:start -->.*?<!-- editorial-faq:end -->\n?', '', content, flags=re.S)
    entries = []
    for block in re.findall(r'<details\b[^>]*>(.*?)</details>', content, re.S):
        question = re.search(r'<summary\b[^>]*>(.*?)</summary>', block, re.S)
        if question:
            answer = block[question.end():]
            entries.append({'@type': 'Question', 'name': plain(question.group(1)),
                            'acceptedAnswer': {'@type': 'Answer', 'text': plain(answer)}})
    if entries:
        schema = json.dumps({'@context': 'https://schema.org', '@type': 'FAQPage', 'mainEntity': entries}, ensure_ascii=False)
        content = content.replace('</head>', '\n<!-- editorial-faq:start -->\n<script type="application/ld+json">' + schema + '</script>\n<!-- editorial-faq:end -->\n</head>')
    target.write_text(content)
print('Built 3 articles, FAQ, article index, sitemap and llms.txt')
