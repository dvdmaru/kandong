#!/usr/bin/env python3
"""模型清單一致性檢查：同一份清單寫在四個地方，檔名／網址／SHA256／大小必須一字不差。

  scripts/kandong_settings.lua               播放器設定選單（下載）
  mac/download-models.sh                     Mac 一鍵下載
  packaging/windows/scripts/download-models.ps1  Windows 一鍵下載
  packaging/models-README.txt                models 資料夾裡的「把模型放這裡.txt」（沒有大小）

用法：python3 tests/check_catalog.py   （一致 exit 0；陽性對照：python3 tests/check_catalog.py --self-test）
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(rel):
    return open(os.path.join(REPO, rel), encoding="utf-8").read()


def block(text):
    m = re.search(r"MODELS-BEGIN(.*?)MODELS-END", text, re.S)
    if not m:
        raise SystemExit("找不到 MODELS-BEGIN／MODELS-END")
    return m.group(1)


def from_lua(text):
    out = {}
    for ent in re.findall(r"\{\s*file\s*=.*?size\s*=\s*\d+\s*\}", block(text), re.S):
        f = re.search(r'file\s*=\s*"([^"]+)"', ent).group(1)
        out[f] = (re.search(r'url\s*=\s*"([^"]+)"', ent).group(1),
                  re.search(r'sha\s*=\s*"([^"]+)"', ent).group(1),
                  int(re.search(r"size\s*=\s*(\d+)", ent).group(1)))
    return out


def from_sh(text):
    out = {}
    for line in re.findall(r'^\s*"(\d+\|[^"]+)"', block(text), re.M):
        _, f, url, sha, size, _desc = line.split("|", 5)
        out[f] = (url, sha, int(size))
    return out


def from_ps1(text):
    out = {}
    for ent in re.findall(r"@\{.*?Size\s*=\s*\d+\s*\}", block(text), re.S):
        f = re.search(r"File\s*=\s*'([^']+)'", ent).group(1)
        out[f] = (re.search(r"Url\s*=\s*'([^']+)'", ent).group(1),
                  re.search(r"Sha\s*=\s*'([^']+)'", ent).group(1),
                  int(re.search(r"Size\s*=\s*(\d+)", ent).group(1)))
    return out


def from_readme(text):
    out = {}
    for f, url, sha in re.findall(r"檔名：(\S+)\s+下載：(\S+)\s+SHA256：([0-9a-f]{64})", text):
        out[f] = (url, sha, None)
    return out


def compare(sources):
    ref_name, ref = next(iter(sources.items()))
    problems = []
    for name, cat in sources.items():
        if set(cat) != set(ref):
            problems.append("%s 的檔名清單 %s ≠ %s 的 %s" % (name, sorted(cat), ref_name, sorted(ref)))
            continue
        for f, (url, sha, size) in cat.items():
            r_url, r_sha, r_size = ref[f]
            if url != r_url:
                problems.append("%s：%s 網址不同" % (name, f))
            if sha != r_sha:
                problems.append("%s：%s SHA256 不同" % (name, f))
            if size is not None and r_size is not None and size != r_size:
                problems.append("%s：%s 大小不同" % (name, f))
    return problems


def load():
    return {
        "kandong_settings.lua": from_lua(read("scripts/kandong_settings.lua")),
        "download-models.sh": from_sh(read("mac/download-models.sh")),
        "download-models.ps1": from_ps1(read("packaging/windows/scripts/download-models.ps1")),
        "models-README.txt": from_readme(read("packaging/models-README.txt")),
    }


def main():
    sources = load()
    for name, cat in sources.items():
        print("  %-22s %d 個模型" % (name, len(cat)))
        if len(cat) < 3:
            print("FAIL：%s 解析出的模型少於 3 個（解析壞了？）" % name)
            return 1
    if "--self-test" in sys.argv:
        # 陽性對照：故意改壞一個 SHA，必須被抓到
        lua = sources["kandong_settings.lua"]
        f = next(iter(lua))
        lua[f] = (lua[f][0], "0" * 64, lua[f][2])
        caught = compare(sources)
        print("陽性對照：" + ("抓到 " + caught[0] if caught else "沒抓到（檢查器壞了）"))
        return 0 if caught else 1
    problems = compare(sources)
    for p in problems:
        print("FAIL：" + p)
    if not problems:
        print("四處模型清單一致")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
