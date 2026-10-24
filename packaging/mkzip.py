"""打 zip：中文檔名帶 UTF-8 旗標（macOS 內建 zip 不帶，Windows 檔案總管解壓會變亂碼），保留可執行權限。
用法：python3 packaging/mkzip.py <輸出.zip> <來源上層目錄> <要包的資料夾名>"""
import os
import pathlib
import sys
import unicodedata
import zipfile

out, base, top = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
root = base / top
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in sorted(root.rglob('*')):
        if path.is_dir() or path.name == '.DS_Store':
            continue
        # macOS 檔案系統可能給 NFD；統一成 NFC，Windows 才顯示正常
        arc = unicodedata.normalize('NFC', str(path.relative_to(base)))
        info = zipfile.ZipInfo(arc, date_time=(2026, 10, 24, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (os.stat(path).st_mode & 0o777 | 0o100000) << 16
        info.create_system = 3  # Unix：讓解壓工具認得權限
        with open(path, 'rb') as f:
            z.writestr(info, f.read())
print(out, os.path.getsize(out))
