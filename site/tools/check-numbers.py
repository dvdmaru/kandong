"""Turn every numeric text node from browser evidence into a source ledger."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://github.com/dvdmaru/kandong/blob/7effeb9e3da2fde611f6f068cf71198e98e6a9ff'
README = BASE + '/README.md'
data = json.loads((ROOT / 'editorial/evidence/browser.json').read_text())


def evidence(text, route):
    refs = []
    if '2026-10-24' in text:
        refs.append('本批編輯日期（Asia/Taipei）；非產品數據')
    if any(word in text for word in ['GB', 'MB', '16 GB', '1–1.5', '0.25']):
        refs.append(f'[README 模型表與實測條件]({README}#L31-L37)')
    if '12GB' in text:
        refs.append(f'[啟動器的模型選擇門檻]({BASE}/mac/kandong.sh#L70-L75)；12GB 是程式分支，非實測效能門檻')
    if '12 句' in text or 'M4' in text:
        refs.append(f'[README 唯一採用的實測]({README}#L37)；只對 Apple M4／16GB、含 12 句前文，不延伸到其他平台')
    if 'Hy-MT2' in text or '1.8B' in text or '7B' in text or 'large-v3' in text:
        refs.append(f'[README 模型名稱]({README}#L31-L37)；名稱中的數字是型號，不是新增實測')
    if 'Q4_K_M' in text:
        refs.append(f'[下載器模型完整檔名]({BASE}/mac/download-models.sh#L11-L16)')
    if 'Apache-2.0' in text:
        refs.append(f'[第三方授權]({BASE}/THIRD_PARTY.md)；2.0 為授權版本')
    if 'Windows 10' in text or '64' in text:
        refs.append(f'[README 支援平台]({README}#L24-L25)')
        if 'vc_redist' in text:
            refs.append(f'[Windows 啟動器]({BASE}/packaging/windows/scripts/launch.ps1) 的 VC++ X64 提示')
    if '0.5x' in text or '3x' in text or '1x' in text:
        refs.append(f'[README 操作與倍速]({README}#L53-L65)；按鍵／倍率，不是速度測試結果')
    if route == '/guide/' and any(w in text for w in ['編號', '選 2', '選 3', '13', 'SHA256']):
        refs.append(f'[下載器編號、複選與 SHA256]({BASE}/mac/download-models.sh#L11-L80)；13 代表選項 1 與 3，不是數量')
    if text in ('1', '2', '3') or route == '/guide/' and any(text.startswith(f'{n}. ') for n in range(3)):
        refs.append('頁面操作步驟編號；編輯排序，不是外部事實或實測')
    return list(dict.fromkeys(refs))


rows = []
for page in data['numbers']:
    for item in page['passages']:
        refs = evidence(item['text'], page['route'])
        assert refs, f'Numeric passage without source: {page["route"]} {item["text"]}'
        rows.append({'route': page['route'], **item, 'sources': refs})
result = {'passages': rows, 'count': len(rows), 'unmapped': 0,
          'scope': 'Every numeric HTML text node, including opened FAQ and HTML tutorial illustrations; images and non-visible metadata are described separately in numbers.md.'}
(ROOT / 'editorial/evidence/numbers.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
md = '''# 數字來源逐項對照

範圍：所有公開 HTML 的文字節點（含展開 FAQ、模型下載示意畫面），不是只查新文章。逐項抽取見 `evidence/browser.json`；無對照項就以非零狀態結束。型號、檔案大小、平台版本與操作編號也列出，避免跟實測混用。

| 頁面 | 數字原句 | 來源與口徑 |
| --- | --- | --- |
'''
for row in rows:
    md += '| ' + row['route'] + ' | ' + row['text'].replace('|', '\\|') + ' | ' + '<br>'.join(row['sources']) + ' |\n'
md += '''
## 非正文數字與圖片

- Article 的編輯日期與時區是本批編輯資訊（台北時間），不是已上線時間證據；draft PR 不代表已發佈。sitemap 的 lastmod 是本批修改日期。
- 首頁 SoftwareApplication 的 0.2.0 來自 repo `VERSION`；offers 的 0 元來自 README 免費定位。語系、圖片寬高和 CSS 像素是網頁屬性，不是產品實測。
- 截圖沿用 repo 自有播放器畫面。影像內的影片時間軸、字幕、選單項目是當下 UI 示範，沒有把畫面讀數引用成效能數據；沒有新增或修改播放器截圖。
- `llms.txt` 的型號、8GB／16GB 與 M4 同樣對應 README 第 31–37 行；不另創實測。
- 檢查報告中的頁面、連結、字數、像素與檔案數是本次驗收讀數，依 `evidence/` 原始紀錄，不是使用者規模或產品 benchmark。
- 本批刪除舊教學未由 README 支持的等待秒數，也刪除未有來源的固定倍速追趕門檻；保留實際程式的 12GB 自動選模型分支，並與 README 的 16GB 使用建議分開。
'''
(ROOT / 'editorial/numbers.md').write_text(md)
print(f'{len(rows)} numeric passages mapped; 0 unmapped')
