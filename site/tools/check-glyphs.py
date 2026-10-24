"""Check Simplified-only characters, with a required failing control first.

Requires opencc-python-reimplemented. Common Traditional variants (台/臺,
里/裡, etc.) are excluded using the reverse character dictionary, not an
allowlist of particular article words.
"""
from pathlib import Path
from html.parser import HTMLParser
import argparse
import json
import opencc

ROOT = Path(__file__).resolve().parents[1]
DICT = Path(opencc.__file__).parent / 'dictionary'


def read_dictionary(name):
    return {line.split('\t')[0]: line.rstrip().split('\t')[1].split(' ')
            for line in (DICT / name).read_text().splitlines() if '\t' in line}


st = read_dictionary('STCharacters.txt')
ts = read_dictionary('TSCharacters.txt')
SIMPLIFIED_ONLY = {ch for ch, vals in st.items() if ch not in vals and ch not in ts}


class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('style', 'script'):
            self.skip += 1
        for key, value in attrs:
            if key in ('alt', 'content', 'title') and value:
                self.parts.append(value)

    def handle_endtag(self, tag):
        if tag in ('style', 'script'):
            self.skip -= 1

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def issues(text):
    return sorted(set(text) & SIMPLIFIED_ONLY)


parser = argparse.ArgumentParser()
parser.add_argument('--text')
args = parser.parse_args()
if args.text is not None:
    found = issues(args.text)
    print(json.dumps({'simplified_only': found, 'pass': not found}, ensure_ascii=False))
    raise SystemExit(1 if found else 0)

bad = '这段视频没有中文字幕，翻译失败，请下载轻量模型。'
good = '這段影片沒有中文字幕，翻譯失敗，請下載輕量模型。'
assert issues(bad), 'Detector failed to reject the Simplified control'
assert not issues(good), 'Detector rejected the Traditional control'
checks = []
for path in sorted((ROOT / 'public').rglob('*')):
    if path.suffix not in ('.html', '.txt'):
        continue
    raw = path.read_text()
    if path.suffix == '.html':
        page = Text()
        page.feed(raw)
        raw = ' '.join(page.parts)
    checks.append({'file': str(path.relative_to(ROOT)), 'simplified_only': issues(raw)})
result = {'negative_control': {'text': bad, 'detected': issues(bad), 'exit_code_expected': 1},
          'traditional_control_pass': True, 'checks': checks,
          'limitations': 'Checks Simplified-only glyphs in page text and metadata; does not decide regional wording or Traditional variant preference.'}
out = ROOT / 'editorial/evidence'
out.mkdir(parents=True, exist_ok=True)
(out / 'glyphs.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False))
raise SystemExit(1 if any(c['simplified_only'] for c in checks) else 0)
