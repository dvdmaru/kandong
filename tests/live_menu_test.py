#!/usr/bin/env python3
"""設定選單的雲端 API 流程真機測試（Mac；會打真的 Claude API 幾次、借用剪貼簿，測完放回原本內容）。

右鍵 → 設定 → 連到雲端 API → Claude：剪貼簿不是金鑰時提示先複製 → 複製金鑰後列出模型、推薦排第一 →
選模型試翻成功才存（設定檔只記 key_ref、金鑰進鑰匙圈）→ 第二次沿用已存的 → 刪除金鑰改回本機。
全程檢查金鑰不在設定檔、不在腳本間訊息、不在 mpv 除錯紀錄。

  python3 tests/live_menu_test.py      # 金鑰讀 ~/.config/anthropic/key（或 KANDONG_TEST_KEY_FILE_ANTHROPIC）
"""
import json, os, shutil, socket, subprocess, sys, tempfile, time
TESTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TESTS)
import test_settings_menu as T  # 沿用假 uosc／假翻譯腳本／Ipc

REPO = os.path.dirname(TESTS)
raw = open(os.environ.get("KANDONG_TEST_KEY_FILE_ANTHROPIC", os.path.expanduser("~/.config/anthropic/key"))).read().strip()
key = raw.split("=", 1)[1].strip() if raw.split("=")[0].isupper() and "=" in raw[:40] else raw

def read_kv(path):
    d = {}
    if not os.path.exists(path):
        return d
    for l in open(path, encoding="utf-8"):
        l = l.rstrip("\r\n")
        if "=" in l and not l.startswith("#"):
            k, v = l.split("=", 1)
            d[k] = v
    return d
T.read_kv = read_kv

tmp = tempfile.mkdtemp(prefix="kd-menu-")
cfg, out, ctl = tmp + "/cfg", tmp + "/out", tmp + "/logs"
for d in (cfg + "/scripts/uosc", cfg + "/script-opts", out, ctl):
    os.makedirs(d)
shutil.copy(REPO + "/scripts/kandong_settings.lua", cfg + "/scripts/")
shutil.copytree(REPO + "/script-modules", cfg + "/script-modules")
open(cfg + "/scripts/uosc/main.lua", "w").write(T.FAKE_UOSC)
open(cfg + "/scripts/floattranslate.lua", "w").write(T.FAKE_TRANSLATOR)
shutil.copy(REPO + "/script-opts/floattranslate.conf", cfg + "/script-opts/")
shutil.copy(REPO + "/script-opts/kandong_settings.conf", cfg + "/script-opts/")
sock = tmp + "/mpv.sock"
mpv = subprocess.Popen(["mpv", "--config-dir=" + cfg, "--idle=yes", "--vo=null", "--ao=null", "--no-terminal",
                        "--force-window=no", "--input-ipc-server=" + sock, "--log-file=" + out + "/mpv.log",
                        "--script-opts=fake_uosc_out=" + out + ",kandong_settings-control_dir=" + ctl])
ok = []
def check(c, what):
    print(("  ok   " if c else "  FAIL ") + what); ok.append(bool(c))
saved_clip = subprocess.run(["pbpaste"], capture_output=True).stdout
try:
    T.wait_for(lambda: os.path.exists(sock), 5)
    ipc = T.Ipc(sock)
    time.sleep(1)
    ipc.cmd("script-binding", "kandong_settings/open-settings")
    m = T.wait_for(lambda: os.path.exists(out + "/open-menu.json") and json.load(open(out + "/open-menu.json")), 5)
    sub = [it for it in m["items"] if it.get("items")][0]
    names = [x["title"] for x in sub["items"]]
    check(sub["title"] == "連到雲端 API 或其他翻譯伺服器", "子選單標題")
    check(names[:3] == ["OpenAI（雲端 API）", "Claude（Anthropic 雲端 API）", "Gemini（Google 雲端 API）"], "三家排最前面：" + str(names[:3]))
    check("刪除這台電腦存的 API 金鑰" in names, "有刪除金鑰的選項")
    os.remove(out + "/open-menu.json")
    subprocess.run(["pbcopy"], input=b"hello, not a key")
    ipc.cmd("script-message-to", "kandong_settings", "ks-action", "server-cloud", "anthropic")
    time.sleep(1.5)
    log = open(out + "/mpv.log", encoding="utf-8", errors="replace").read()
    check("先到 console.anthropic.com 複製 API 金鑰" in log, "剪貼簿不是金鑰、也沒存過 → 提示先去複製")
    ipc.cmd("keypress", "ESC")
    time.sleep(0.5)
    subprocess.run(["pbcopy"], input=key.encode())
    ipc.cmd("script-message-to", "kandong_settings", "ks-action", "server-cloud", "anthropic")
    mm = T.wait_for(lambda: os.path.exists(out + "/open-menu.json") and json.load(open(out + "/open-menu.json")), 20)
    check(mm and mm.get("type") == "kandong_settings_models", "列出 Claude 的模型清單")
    first = mm["items"][0] if mm else {}
    check(first.get("hint", "").startswith("推薦") and "claude-haiku" in first.get("hint", ""), "第一個是推薦的 Haiku：" + first.get("hint", ""))
    model_id = first.get("hint", "").split("· ")[-1]
    ipc.cmd("script-message-to", "kandong_settings", "ks-action", "cloud-model", model_id)
    fc = T.wait_for(lambda: T.read_kv(cfg + "/script-opts/floattranslate.conf").get("provider") == "anthropic"
                    and T.read_kv(cfg + "/script-opts/floattranslate.conf"), 40)
    check(fc and fc.get("endpoint") == "https://api.anthropic.com/v1/messages", "endpoint 寫進設定")
    check(fc and fc.get("key_ref") == "anthropic" and fc.get("api_key") == "", "設定檔只記 key_ref，api_key 空白")
    check(fc and fc.get("reasoning_effort") == "low", "記住接受的思考程度：" + str(fc and fc.get("reasoning_effort")))
    conf_text = open(cfg + "/script-opts/floattranslate.conf", encoding="utf-8").read()
    check(key not in conf_text, "金鑰沒有寫進設定檔")
    tl = open(out + "/translator.log", encoding="utf-8").read() if os.path.exists(out + "/translator.log") else ""
    check("ft-server-changed\thttps://api.anthropic.com/v1/messages\t" + model_id in tl and key not in tl, "通知翻譯腳本，訊息裡沒有金鑰")
    log = open(out + "/mpv.log", encoding="utf-8", errors="replace").read()
    check(key not in log, "mpv 紀錄檔裡沒有金鑰")
    for l in [l for l in log.splitlines() if key in l][:6]:
        print("     LEAK:", l.replace(key, "<KEY>")[:230])
    r = subprocess.run(["security", "find-generic-password", "-s", "KanDong API key", "-a", "anthropic", "-w"], capture_output=True, text=True)
    check(r.stdout.strip() == key, "鑰匙圈存的是同一把")
    ipc.cmd("script-binding", "kandong_settings/open-settings")
    time.sleep(1)
    m2 = json.load(open(out + "/open-menu.json"))
    check(m2["items"][0]["title"].startswith("目前：雲端 API：Claude"), "目前：" + m2["items"][0]["title"])
    subprocess.run(["pbcopy"], input=b"not a key either")
    os.remove(out + "/open-menu.json")
    ipc.cmd("script-message-to", "kandong_settings", "ks-action", "server-cloud", "anthropic")
    mm2 = T.wait_for(lambda: os.path.exists(out + "/open-menu.json") and json.load(open(out + "/open-menu.json")), 20)
    log = open(out + "/mpv.log", encoding="utf-8", errors="replace").read()
    check(mm2 and mm2.get("type") == "kandong_settings_models" and "沿用這台電腦已存的 Claude 金鑰" in log, "已存過 → 沿用、直接列模型")
    check(key not in log, "整段流程跑完，mpv 除錯紀錄裡仍沒有金鑰")
    ipc.cmd("script-message-to", "kandong_settings", "ks-action", "forget-keys")
    time.sleep(3)
    r = subprocess.run(["security", "find-generic-password", "-s", "KanDong API key", "-a", "anthropic"], capture_output=True)
    check(r.returncode != 0, "刪除金鑰後鑰匙圈裡沒有了")
    fc2 = T.read_kv(cfg + "/script-opts/floattranslate.conf")
    check(fc2.get("provider") == "" and fc2.get("endpoint", "").startswith("http://127.0.0.1"), "刪除金鑰後改回這台電腦")
finally:
    subprocess.run(["pbcopy"], input=saved_clip)
    mpv.terminate()
    subprocess.run(["security", "delete-generic-password", "-s", "KanDong API key", "-a", "anthropic"], capture_output=True)
    shutil.rmtree(tmp, ignore_errors=True)
print("全部通過" if all(ok) else "FAIL %d 項" % ok.count(False))
sys.exit(0 if all(ok) else 1)
