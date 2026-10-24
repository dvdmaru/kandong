"""Check every external page link; large binary/model files use HEAD only."""
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from pathlib import Path
import datetime
import json
import subprocess
from urllib.parse import urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[1]
links = set()


class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'a' or tag == 'link' and attrs.get('rel') == 'stylesheet':
            url = attrs.get('href', '')
            if url.startswith('https://') and not url.startswith('https://kandong.twtools.cc'):
                links.add(url)


for page in (ROOT / 'public').rglob('*.html'):
    Links().feed(page.read_text())


def check(url):
    binary = '/resolve/' in url or '/releases/latest/download/' in url
    args = ['curl', '-sS', '-L', '--retry', '2', '--max-time', '45',
            '-o', '/dev/null', '-w', '%{http_code}\t%{url_effective}', url]
    if binary:
        args.insert(1, '-I')
    else:
        args[1:1] = ['--max-filesize', '3000000']
    process = subprocess.run(args, text=True, capture_output=True)
    parts = process.stdout.split('\t', 1)
    final = urlsplit(parts[1] if len(parts) > 1 else '')
    # CDN redirects can contain expiring signed query parameters. They aren't
    # necessary evidence and must not be persisted in review artifacts.
    final_url = urlunsplit((final.scheme, final.netloc, final.path, '', final.fragment))
    return {'url': url, 'method': 'HEAD' if binary else 'GET', 'status': int(parts[0] or '0'),
            'final_url': final_url, 'curl_exit': process.returncode,
            'error': process.stderr.strip()}


with ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(check, sorted(links)))
report = {'checkedAt': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
          'results': results, 'pass': all(200 <= r['status'] < 300 and r['curl_exit'] == 0 for r in results)}
target = ROOT / 'editorial/evidence/external-links.json'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))
raise SystemExit(0 if report['pass'] else 1)
