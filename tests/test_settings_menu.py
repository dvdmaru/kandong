#!/usr/bin/env python3
"""設定選單 scripts/kandong_settings.lua 的無頭測試（Mac／Linux，要有 mpv 0.39 以上與 curl）。

不碰真的模型與真的 uosc：
  - 假 uosc（scripts/uosc/main.lua）把收到的選單 JSON 寫進檔案，測試再讀出來看。
  - 假翻譯腳本（scripts/floattranslate.lua）把收到的通知記下來。
  - 啟動器那一側（engine-status.txt）由測試自己寫，模擬「換好了／換不成／沒人接」。
  - 下載用本機 HTTP 伺服器，模型清單用 catalog_file 換成小檔。
  - 「其他翻譯伺服器」用本機假的 OpenAI 相容伺服器。

用法：python3 tests/test_settings_menu.py   （全過 exit 0）
"""
import hashlib
import http.server
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILS = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)


def wait_for(fn, timeout=10.0, step=0.1):
    end = time.time() + timeout
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(step)
    return fn()


FAKE_UOSC = r'''
local utils = require "mp.utils"
local out = mp.get_opt("fake_uosc_out")
local n = 0
local function rec(kind, json)
    n = n + 1
    local f = io.open(out .. "/" .. kind .. ".json", "wb"); f:write(json); f:close()
    local g = io.open(out .. "/uosc.log", "ab"); g:write(kind .. "\n"); g:close()
end
mp.register_script_message("open-menu", function(j) rec("open-menu", j) end)
mp.register_script_message("update-menu", function(j) rec("update-menu", j) end)
'''

FAKE_TRANSLATOR = r'''
local out = mp.get_opt("fake_uosc_out")
local function rec(...)
    local parts = {...}
    local g = io.open(out .. "/translator.log", "ab"); g:write(table.concat(parts, "\t") .. "\n"); g:close()
end
for _, name in ipairs({"ft-engine-pause", "ft-engine-ready", "ft-server-changed"}) do
    mp.register_script_message(name, function(...) rec(name, ...) end)
end
'''


class Ipc:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(path)
        self.s.settimeout(5)
        self.buf = b""
        self.rid = 0

    def cmd(self, *args):
        self.rid += 1
        self.s.sendall((json.dumps({"command": list(args), "request_id": self.rid}) + "\n").encode())
        while True:
            while b"\n" not in self.buf:
                self.buf += self.s.recv(65536)
            line, self.buf = self.buf.split(b"\n", 1)
            msg = json.loads(line)
            if msg.get("request_id") == self.rid:
                return msg


def quiet_handler(base):
    class H(base):
        def log_message(self, *a):
            pass
    return H


def serve(handler):
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), quiet_handler(handler))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def main():
    if not shutil.which("mpv") or not shutil.which("curl"):
        print("需要 mpv 與 curl")
        return 2
    tmp = tempfile.mkdtemp(prefix="ks-test-")
    cfg = os.path.join(tmp, "cfg")
    models = os.path.join(tmp, "models")
    ctl = os.path.join(tmp, "logs")
    home = os.path.join(tmp, "home")
    out = os.path.join(tmp, "out")
    for d in (cfg + "/scripts/uosc", cfg + "/script-opts", models + "/sub", ctl, out,
              home + "/.lmstudio/models/pub/mymodel", home + "/.cache/kandong/models"):
        os.makedirs(d, exist_ok=True)
    shutil.copy(os.path.join(REPO, "scripts/kandong_settings.lua"), cfg + "/scripts/")
    shutil.copytree(os.path.join(REPO, "script-modules"), cfg + "/script-modules")
    open(cfg + "/scripts/uosc/main.lua", "w").write(FAKE_UOSC)
    open(cfg + "/scripts/floattranslate.lua", "w").write(FAKE_TRANSLATOR)
    shutil.copy(os.path.join(REPO, "script-opts/floattranslate.conf"), cfg + "/script-opts/")
    shutil.copy(os.path.join(REPO, "script-opts/kandong_settings.conf"), cfg + "/script-opts/")

    def touch(p, size=1000):
        with open(p, "wb") as f:
            f.write(b"\0" * size)
    m18 = os.path.join(models, "Hy-MT2-1.8B-Q4_K_M.gguf")
    mine = os.path.join(models, "my-own-model.gguf")
    nested = os.path.join(models, "sub", "nested.gguf")
    lms = os.path.join(home, ".lmstudio/models/pub/mymodel/lmstudio-model-Q4.gguf")
    for p in (m18, mine, nested, lms, os.path.join(models, "mmproj-vision.gguf"),
              os.path.join(home, ".lmstudio/models/pub/mymodel/mmproj-x.gguf")):
        touch(p)

    # 下載用的小檔與本機伺服器
    payload = os.urandom(3 * 1024 * 1024)
    sha = hashlib.sha256(payload).hexdigest()

    class Files(http.server.BaseHTTPRequestHandler):
        slow = False

        def do_GET(self):
            data = payload
            start = 0
            rng = self.headers.get("Range")
            if rng and rng.startswith("bytes="):
                start = int(rng[6:].split("-")[0])
                if start >= len(data):
                    self.send_response(416)
                    self.end_headers()
                    return
                self.send_response(206)
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(data) - 1, len(data)))
            else:
                self.send_response(200)
            self.send_header("Content-Length", str(len(data) - start))
            self.end_headers()
            chunk = data[start:]
            if "slow" in self.path:
                for i in range(0, len(chunk), 16384):
                    try:
                        self.wfile.write(chunk[i:i + 16384])
                    except OSError:
                        return
                    time.sleep(0.05)
            else:
                self.wfile.write(chunk)
    fsrv = serve(Files)
    base = "http://127.0.0.1:%d/" % fsrv.server_address[1]
    catalog = [
        {"file": "Hy-MT2-7B-Q4_K_M.gguf", "kind": "translate", "label": "Hy-MT2 7B（標準）", "note": "",
         "url": base + "7b", "sha": sha, "size": len(payload)},
        {"file": "Hy-MT2-1.8B-Q4_K_M.gguf", "kind": "translate", "label": "Hy-MT2 1.8B（輕量）", "note": "",
         "url": base + "18b", "sha": sha, "size": len(payload)},
        {"file": "bad-sha.gguf", "kind": "translate", "label": "壞檔測試", "note": "",
         "url": base + "bad", "sha": "0" * 64, "size": len(payload)},
        {"file": "slow.gguf", "kind": "translate", "label": "慢速測試", "note": "",
         "url": base + "slow", "sha": sha, "size": len(payload)},
        {"file": "ggml-large-v3-turbo-q5_0.bin", "kind": "asr", "label": "語音辨識模型（Whisper）", "note": "",
         "family": "whisper-large-v3-turbo", "shared": True,
         "url": base + "asr", "sha": sha, "size": len(payload)},
        {"file": "ggml-large-v3-turbo.bin", "kind": "asr", "label": "語音辨識模型（Whisper，未量化）", "note": "",
         "family": "whisper-large-v3-turbo", "shared": True, "hidden": True,
         "url": base + "asr-full", "sha": sha, "size": len(payload)},
    ]
    shared = os.path.join(home, ".cache/twtools/models")  # 與 Echoic 線下版共用的資料夾（HOME 指到測試目錄）
    cat_path = os.path.join(tmp, "catalog.json")
    json.dump(catalog, open(cat_path, "w"), ensure_ascii=False)

    # 假的 OpenAI 相容伺服器（模擬 Ollama／LM Studio）
    seen = {"auth": None, "model": None}

    class Fake(http.server.BaseHTTPRequestHandler):
        def _send(self, obj, code=200):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/v1/models":
                return self._send({"data": [{"id": "qwen2.5:7b"}, {"id": "gemma3:4b"}]})
            self._send({"error": "nope"}, 404)

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n))
            seen["auth"] = self.headers.get("Authorization")
            seen["model"] = req.get("model")
            if req.get("model") == "gemma3:4b":
                return self._send({"error": {"message": "model not loaded"}}, 500)
            self._send({"choices": [{"message": {"content": "早安。"}}]})
    osrv = serve(Fake)
    fake_ep = "http://127.0.0.1:%d/v1/chat/completions" % osrv.server_address[1]

    status = os.path.join(ctl, "engine-status.txt")
    request = os.path.join(ctl, "engine-request.txt")
    tlog = os.path.join(out, "translator.log")

    def write_status(**kv):
        with open(status, "w") as f:
            for k in ("id", "state", "model", "error"):
                f.write("%s=%s\n" % (k, kv.get(k, "")))

    def read_kv(path):
        d = {}
        try:
            for line in open(path, encoding="utf-8"):
                if "=" in line and not line.startswith("#"):
                    k, v = line.rstrip("\n").split("=", 1)
                    d[k] = v
        except FileNotFoundError:
            return None
        return d

    def tlines():
        try:
            return open(tlog, encoding="utf-8").read().splitlines()
        except FileNotFoundError:
            return []

    def menu(kind="open-menu"):
        try:
            return json.load(open(os.path.join(out, kind + ".json"), encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def titles(m):
        return [it.get("title", "") for it in m["items"]]

    write_status(id="0", state="ready", model=m18)
    sock = os.path.join(tmp, "mpv.sock")
    env = dict(os.environ, HOME=home)
    mpv = subprocess.Popen([
        "mpv", "--config-dir=" + cfg, "--idle=yes", "--vo=null", "--ao=null", "--no-terminal",
        "--input-ipc-server=" + sock, "--log-file=" + os.path.join(out, "mpv.log"),
        "--script-opts-append=fake_uosc_out=" + out,
        "--script-opts-append=kandong_settings-models_dir=" + models,
        "--script-opts-append=kandong_settings-control_dir=" + ctl,
        "--script-opts-append=kandong_settings-catalog_file=" + cat_path,
    ], env=env)
    try:
        if not wait_for(lambda: os.path.exists(sock), 10):
            print("mpv 沒開起來")
            return 1
        time.sleep(1.0)
        ipc = Ipc(sock)

        def action(*args):
            return ipc.cmd("script-message-to", "kandong_settings", "ks-action", *args)

        print("== 1. 選單內容")
        ipc.cmd("script-binding", "kandong_settings/open-settings")
        m = wait_for(menu, 5)
        check(m is not None, "按設定項目會送 open-menu 給 uosc")
        t = titles(m)
        check(t[0] == "目前：這台電腦：Hy-MT2 1.8B（輕量）", "第一行顯示目前模型：" + t[0])
        check("Hy-MT2 1.8B（輕量）" in t and "my-own-model" in t and "nested" in t, "列出 models 與子資料夾的 .gguf")
        check("lmstudio-model-Q4" in t, "列出 LM Studio 資料夾的模型")
        check(not any("mmproj" in x for x in t), "mmproj（視覺投影檔）不列")
        used = [it for it in m["items"] if it.get("active")]
        check(len(used) == 1 and used[0]["title"] == "Hy-MT2 1.8B（輕量）" and used[0]["hint"].startswith("使用中"),
              "使用中的模型有標記")
        check("下載 Hy-MT2 7B（標準）" in t and "下載 Hy-MT2 1.8B（輕量）" not in t, "已經有的模型不出現在下載清單")
        check(any(it.get("items") for it in m["items"]), "有「連到其他翻譯伺服器」子選單")
        srv = [it for it in m["items"] if it.get("items")][0]
        st_ = [x["title"] for x in srv["items"]]
        check(srv["title"] == "連到雲端 API 或其他翻譯伺服器"
              and st_[:3] == ["OpenAI（雲端 API）", "Claude（Anthropic 雲端 API）", "Gemini（Google 雲端 API）"],
              "雲端 API 三家排在子選單最前面")
        check(all("按用量付費" in x["hint"] and "字幕會送到" in x["hint"] for x in srv["items"][:3]),
              "三家都寫明按用量付費、字幕會送出去")
        check("刪除這台電腦存的 API 金鑰" in st_, "有刪除已存金鑰的選項")

        print("== 2. 換模型：啟動器換好")
        action("switch", mine)
        req = wait_for(lambda: read_kv(request), 3)
        check(req and req.get("action") == "switch" and req.get("model") == mine, "寫出換模型要求")
        check(read_kv(cfg + "/script-opts/kandong_settings.conf").get("model_path") == mine, "選擇寫進 kandong_settings.conf")
        check(wait_for(lambda: "ft-engine-pause" in tlines(), 3), "通知翻譯腳本暫停")
        os.remove(request)
        write_status(id=req["id"], state="loading", model=mine)
        time.sleep(1.0)
        check("ft-engine-ready" not in tlines(), "載入中不會提早恢復")
        write_status(id=req["id"], state="ready", model=mine)
        check(wait_for(lambda: "ft-engine-ready" in tlines(), 3), "換好後通知翻譯腳本恢復")

        print("== 3. 換模型：新模型開不起來，啟動器換回原本的")
        open(tlog, "w").close()
        action("switch", nested)
        req = wait_for(lambda: read_kv(request), 3)
        os.remove(request)
        write_status(id=req["id"], state="ready", model=mine, error="模型載入失敗（記憶體不夠）")
        check(wait_for(lambda: "ft-engine-ready" in tlines(), 3), "失敗也會恢復翻譯")
        check(wait_for(lambda: read_kv(cfg + "/script-opts/kandong_settings.conf").get("model_path") == mine, 2),
              "記住的選擇改回原本能用的模型")

        print("== 4. 換模型：沒有啟動器在接（不是用「看懂」開的）")
        open(tlog, "w").close()
        action("switch", m18)
        check(wait_for(lambda: os.path.exists(request), 2), "先寫要求檔")
        check(wait_for(lambda: not os.path.exists(request), 9), "約 5 秒沒人接就收回要求檔")
        check(wait_for(lambda: "ft-engine-ready" in tlines(), 3), "收回後恢復翻譯")
        check(read_kv(cfg + "/script-opts/kandong_settings.conf").get("model_path") == m18, "選擇仍記住（下次啟動生效）")
        write_status(id="x", state="ready", model=m18)

        print("== 5. 下載：成功、改名、不自動換（已有引擎在跑）")
        action("download", "Hy-MT2-7B-Q4_K_M.gguf")
        dest7 = os.path.join(models, "Hy-MT2-7B-Q4_K_M.gguf")
        check(wait_for(lambda: os.path.exists(dest7), 20), "下載完成並改成正式檔名")
        check(not os.path.exists(dest7 + ".part"), ".part 已清掉")
        check(open(dest7, "rb").read() == payload, "內容正確")
        time.sleep(1)
        check(not os.path.exists(request), "引擎在跑時下載完不會自動換模型")
        um = menu("update-menu")
        check(um is not None, "下載期間選單有更新（update-menu）")

        print("== 6. 下載：SHA256 不符就刪掉")
        action("download", "bad-sha.gguf")
        badp = os.path.join(models, "bad-sha.gguf")
        time.sleep(0.5)
        check(wait_for(lambda: not os.path.exists(badp + ".part") and not os.path.exists(badp), 20)
              and not os.path.exists(badp), "壞檔不留")
        time.sleep(1)

        print("== 7. 下載：續傳（已有一半的 .part）＋沒有模型在跑時自動換上")
        os.remove(m18)
        with open(m18 + ".part", "wb") as f:
            f.write(payload[: len(payload) // 2])
        old = time.time() - 120  # 上次中斷留下的 .part（兩分鐘前），不是別的程式正在寫
        os.utime(m18 + ".part", (old, old))
        write_status(id="y", state="none", model="")
        open(tlog, "w").close()
        action("download", "Hy-MT2-1.8B-Q4_K_M.gguf")
        check(wait_for(lambda: os.path.exists(m18), 20), "從一半接著下載完成")
        check(os.path.exists(m18) and open(m18, "rb").read() == payload, "續傳後內容正確")
        req = wait_for(lambda: read_kv(request), 5)
        check(req and req.get("action") == "switch" and req.get("model") == m18, "還沒有模型時，下載完自動換上")
        if req:
            os.remove(request)
            write_status(id=req["id"], state="ready", model=m18)
        wait_for(lambda: "ft-engine-ready" in tlines(), 3)

        print("== 8. 下載：停止＝留下 .part")
        action("download", "slow.gguf")
        slowp = os.path.join(models, "slow.gguf")
        check(wait_for(lambda: (os.path.getsize(slowp + ".part") if os.path.exists(slowp + ".part") else 0) > 0, 5),
              "開始寫 .part")
        action("cancel-download")
        time.sleep(1.5)
        s1 = os.path.getsize(slowp + ".part")
        time.sleep(1.0)
        check(os.path.getsize(slowp + ".part") == s1 and 0 < s1 < len(payload), "停止後不再長大、留著續傳")
        check(not os.path.exists(slowp), "沒有被當成完成")

        print("== 9. 語音辨識模型（共用模型）下載到共用資料夾 → 請啟動器開語音辨識")
        asr_shared = os.path.join(shared, "ggml-large-v3-turbo-q5_0.bin")
        action("download", "ggml-large-v3-turbo-q5_0.bin")
        req = wait_for(lambda: read_kv(request), 20)
        check(req and req.get("action") == "asr" and req.get("model") == asr_shared, "下載到共用資料夾並送出 asr 要求")
        check(os.path.exists(asr_shared) and not os.path.exists(os.path.join(models, "ggml-large-v3-turbo-q5_0.bin")),
              "共用模型不放 models、放 ~/.cache/twtools/models")
        if os.path.exists(request):
            os.remove(request)

        print("== 9b. 共用資料夾已有另一個工具下載的未量化版 → 不再提供語音辨識模型下載")
        os.remove(asr_shared)
        with open(os.path.join(shared, "ggml-large-v3-turbo.bin"), "wb") as f:
            f.write(b"\0" * 1000)
        os.remove(os.path.join(out, "open-menu.json"))
        ipc.cmd("script-binding", "kandong_settings/open-settings")
        m9 = wait_for(menu, 5)
        check(m9 and not any("語音辨識" in t for t in titles(m9)), "同家族另一顆在共用資料夾 → 下載清單沒有語音辨識模型")
        os.remove(os.path.join(shared, "ggml-large-v3-turbo.bin"))

        print("== 9c. 共用資料夾的 .part 一分鐘內有變動＝別的程式在下載 → 不重開一份")
        busy = os.path.join(shared, "ggml-large-v3-turbo-q5_0.bin.part")
        with open(busy, "wb") as f:
            f.write(b"\0" * 1000)
        action("download", "ggml-large-v3-turbo-q5_0.bin")
        time.sleep(2)
        check(os.path.getsize(busy) == 1000 and not os.path.exists(request), "沒有接手下載、沒送要求")
        log9 = open(os.path.join(out, "mpv.log"), encoding="utf-8", errors="replace").read()
        check("另一個程式正在下載這個檔" in log9, "提示使用者另一個程式正在下載")
        os.remove(busy)

        print("== 9d. 共用資料夾裡的 .gguf 也列進翻譯模型")
        sg = os.path.join(shared, "shared-translator.gguf")
        with open(sg, "wb") as f:
            f.write(b"\0" * 1000)
        os.remove(os.path.join(out, "open-menu.json"))
        ipc.cmd("script-binding", "kandong_settings/open-settings")
        m9 = wait_for(menu, 5)
        check(m9 and "shared-translator" in titles(m9), "共用資料夾的 .gguf 出現在清單")
        os.remove(sg)

        print("== 10. 連到其他翻譯伺服器（假 Ollama）")
        for f in ("open-menu.json",):
            os.remove(os.path.join(out, f))
        open(tlog, "w").close()
        action("server-preset", fake_ep)
        mm = wait_for(menu, 5)
        check(mm and titles(mm) == ["qwen2.5:7b", "gemma3:4b"], "向伺服器查到模型清單並列出")
        action("server-model", "gemma3:4b")
        time.sleep(1.5)
        fc = read_kv(cfg + "/script-opts/floattranslate.conf")
        check(fc["endpoint"] == "http://127.0.0.1:8080/v1/chat/completions", "測試翻譯失敗時設定不改")
        action("server-preset", fake_ep)
        time.sleep(1.0)
        action("server-model", "qwen2.5:7b")
        check(wait_for(lambda: read_kv(cfg + "/script-opts/floattranslate.conf")["endpoint"] == fake_ep, 5),
              "測試成功才寫進 floattranslate.conf")
        fc = read_kv(cfg + "/script-opts/floattranslate.conf")
        check(fc["model"] == "qwen2.5:7b" and fc["api_key"] == "", "模型名與 key 一起寫")
        check(any(l.startswith("ft-server-changed\t" + fake_ep + "\tqwen2.5:7b") for l in tlines()),
              "通知翻譯腳本立刻改用")
        req = wait_for(lambda: read_kv(request), 3)
        check(req and req.get("action") == "stop", "請啟動器關掉本機引擎（把記憶體還給電腦）")
        if os.path.exists(request):
            os.remove(request)
        conf_text = open(cfg + "/script-opts/floattranslate.conf", encoding="utf-8").read()
        check("target_language=Traditional Chinese as used in Taiwan" in conf_text and sum(1 for l in conf_text.splitlines() if l.startswith("endpoint=")) == 1,
              "其他設定與註解原樣保留、key 沒有重複")
        write_status(id="z", state="stopped", model="")
        if os.path.exists(os.path.join(out, "open-menu.json")):
            os.remove(os.path.join(out, "open-menu.json"))
        ipc.cmd("script-binding", "kandong_settings/open-settings")
        m = wait_for(menu, 5)
        check(m and m["items"][0]["title"].startswith("目前：外部伺服器 127.0.0.1:"), "選單顯示目前用外部伺服器")
        sub = [it for it in m["items"] if it.get("items")][0]
        check(any(x["title"] == "改回這台電腦內建的翻譯模型" for x in sub["items"]), "有「改回這台電腦」")

        print("== 11. 改回這台電腦")
        open(tlog, "w").close()
        action("server-local")
        req = wait_for(lambda: read_kv(request), 3)
        fc = read_kv(cfg + "/script-opts/floattranslate.conf")
        check(fc["endpoint"] == "http://127.0.0.1:8080/v1/chat/completions" and fc["model"] == "tencent/Hy-MT2-7B-GGUF",
              "endpoint／model 改回預設")
        check(req and req.get("action") == "switch" and req.get("model") == m18, "請啟動器開記住的模型")
        if os.path.exists(request):
            os.remove(request)
            write_status(id=req["id"], state="ready", model=m18)

        print("== 12. 開檔時還沒有模型 → 暫停翻譯並提示")
        write_status(id="w", state="none", model="")
        open(tlog, "w").close()
        ipc.cmd("loadfile", "av://lavfi:testsrc=duration=3")
        check(wait_for(lambda: "ft-engine-pause" in tlines(), 5), "通知翻譯腳本先別重試")

        print("== 13. 雲端 API 設定：狀態列講明送到哪裡、按用量付費")
        conf_path = cfg + "/script-opts/floattranslate.conf"
        keep = open(conf_path, encoding="utf-8").read()
        with open(conf_path, "a", encoding="utf-8") as f:
            f.write("endpoint=https://api.anthropic.com/v1/messages\nmodel=claude-haiku-5-5\n"
                    "provider=anthropic\nkey_ref=anthropic\n")
        if os.path.exists(os.path.join(out, "open-menu.json")):
            os.remove(os.path.join(out, "open-menu.json"))
        ipc.cmd("script-binding", "kandong_settings/open-settings")
        m13 = wait_for(menu, 5)
        check(m13 and m13["items"][0]["title"] ==
              "目前：雲端 API：Claude（模型 claude-haiku-5-5）· 字幕會送到 Claude、按用量付費",
              "狀態列：" + (m13["items"][0]["title"] if m13 else ""))
        s13 = [it for it in m13["items"] if it.get("items")][0]["items"] if m13 else []
        check(any(x.get("active") and x["title"].startswith("Claude") for x in s13), "目前用的那一家有標記")
        open(conf_path, "w", encoding="utf-8").write(keep)

        log = open(os.path.join(out, "mpv.log"), encoding="utf-8", errors="replace").read()
        errs = [l for l in log.splitlines() if "kandong_settings" in l and ("error" in l.lower() or "stack traceback" in l)]
        check(not errs, "mpv log 沒有腳本錯誤" + ("：" + errs[0] if errs else ""))
    finally:
        mpv.terminate()
        try:
            mpv.wait(5)
        except subprocess.TimeoutExpired:
            mpv.kill()
        fsrv.shutdown()
        osrv.shutdown()
    print()
    if FAILS:
        print("FAIL %d 項（暫存在 %s）" % (len(FAILS), tmp))
        return 1
    shutil.rmtree(tmp, ignore_errors=True)
    print("全部通過")
    return 0


if __name__ == "__main__":
    sys.exit(main())
