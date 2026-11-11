#!/usr/bin/env python3
"""雲端 API 模式的真機測試（會打真的 OpenAI／Claude／Gemini API，花費約幾美分）。

不在 CI 跑；三家換代、改了 script-modules/kandong_cloud.lua 之後手動跑一次。

  python3 tests/live_cloud_test.py                 # 三家都測
  python3 tests/live_cloud_test.py anthropic       # 只測一家
  python3 tests/live_cloud_test.py --keep-keys     # 測完不刪鑰匙圈裡看懂的金鑰

金鑰從這些檔案讀（可用環境變數 KANDONG_TEST_KEY_FILE_<OPENAI|ANTHROPIC|GOOGLE> 改路徑）：
  openai    ~/.config/openai/key
  anthropic ~/.config/anthropic/key
  google    ~/.config/gemini/key
金鑰永遠不印出來；只回報「存進去讀回來是否一致」「有沒有出現在程序命令列」這類是非結果。

兩層：
  1. 模組層：真的存進 Mac 鑰匙圈再讀回來、抓模型清單、從最快的思考程度往下試翻一句。
  2. 端對端：真的 floattranslate.lua 播一段 24 句字幕的測試影片，量全片預譯完成要幾秒
     （同時送 3 句與 1 句各一次）。
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
KEY_FILES = {
    "openai": os.path.join(HOME, ".config/openai/key"),
    "anthropic": os.path.join(HOME, ".config/anthropic/key"),
    "google": os.path.join(HOME, ".config/gemini/key"),
}

SUBS = [
    "Welcome to the major leagues, kid.",
    "Ellie said she'd be here by noon.",
    "We can't afford to drop the ball on this one.",
    "Amazon Studios wants the final cut by Friday.",
    "Like the terrorists shorting airline stocks before 9/11.",
    "Break a leg out there tonight.",
    "I'm not buying it. Something's off.",
    "- Where were you last night?\n- Out. Why?",
    "That's a long shot, but it might work.",
    "He's been under the weather all week.",
    "Let's call it a day.",
    "You're pulling my leg, right?",
    "The board meets on 3/4 to review the numbers.",
    "Don't count your chickens before they hatch.",
    "She nailed the interview.",
    "We're back to square one.",
    "Keep your eyes peeled for anything unusual.",
    "It's not rocket science.",
    "Marcus, hold the line. I'll be right back.",
    "That ship has sailed.",
    "Spill the beans. What happened?",
    "I'll take a rain check on dinner.",
    "Bite the bullet and sign it.",
    "See you on the flip side.",
]

PROBE = r'''
local utils = require "mp.utils"
do
    local dir = mp.command_native({ "expand-path", "~~/script-modules" })
    package.path = dir .. "/?.lua;" .. package.path
end
local cloud = require "kandong_cloud"
local out = mp.get_opt("probe_out")
local jobs
do
    local f = io.open(mp.get_opt("probe_jobs"), "rb"); jobs = utils.parse_json(f:read("*a")); f:close()
end
local results = {}

local function save()
    local f = io.open(out, "wb"); f:write(utils.format_json(results)); f:close()
end

local function read_key(path)
    local f = io.open(path, "rb"); if not f then return nil end
    local k = f:read("*a"); f:close(); os.remove(path)
    return (k:gsub("%s+$", ""))
end

local function ps_has(key)
    local r = mp.command_native({ name = "subprocess", args = { "ps", "-axww", "-o", "args=" },
        capture_stdout = true, playback_only = false })
    return (r.stdout or ""):find(key, 1, true) ~= nil
end

local PROMPT = "Translate the following segment into Traditional Chinese, without additional explanation.\n\nWelcome to the major leagues."

local function run(i)
    local job = jobs[i]
    if not job then save(); mp.commandv("quit"); return end
    local res = { provider = job.provider }
    results[#results + 1] = res
    local key = read_key(job.key_file)
    res.key_valid = cloud.valid_key(key)
    if not res.key_valid then return run(i + 1) end
    cloud.secret_store(job.provider, key, function(ok, err)
        res.store_ok = ok; res.store_err = err
        cloud.secret_read(job.provider, function(got)
            res.read_matches = (got == key)
            local t0 = mp.get_time()
            local leaked = false
            cloud.list_models(job.provider, key, function(list, err2)
                res.models_seconds = mp.get_time() - t0
                res.key_in_process_args = leaked
                res.models_err = err2
                res.models_count = list and #list or 0
                res.models_top = {}
                for j = 1, math.min(8, list and #list or 0) do res.models_top[j] = list[j].id end
                if not list or #list == 0 then return run(i + 1) end
                local model = list[1].id
                res.model = model
                local efforts = cloud.PROVIDERS[job.provider].efforts
                res.tried = {}
                local function try(k)
                    local effort = efforts[k]
                    local t1 = mp.get_time()
                    cloud.request(cloud.chat_spec(job.provider, key, model, PROMPT, effort, 60), function(code, parsed, err3)
                        res.tried[#res.tried + 1] = { effort = effort, code = code or 0,
                            rejected = cloud.effort_rejected(code, parsed) and true or false,
                            err = code ~= 200 and (cloud.error_text(parsed) or err3 or ""):sub(1, 160) or nil }
                        if code ~= 200 and k < #efforts and cloud.effort_rejected(code, parsed) then return try(k + 1) end
                        res.effort = effort
                        res.text = code == 200 and cloud.chat_text(job.provider, parsed) or nil
                        res.translate_seconds = mp.get_time() - t1
                        if code ~= 200 then res.explained = (cloud.explain(job.provider, code, parsed, err3)) end
                        -- 錯誤金鑰：白話錯誤訊息
                        cloud.request(cloud.chat_spec(job.provider, "sk-wrong-key-for-test-000000", model, PROMPT, "", 30),
                            function(c4, p4, e4)
                                res.bad_key_code = c4
                                res.bad_key_message = (cloud.explain(job.provider, c4, p4, e4))
                                run(i + 1)
                            end)
                    end)
                end
                try(1)
            end)
            leaked = ps_has(key)
        end)
    end)
end
mp.add_timeout(0.2, function() run(1) end)
'''


def norm_key(raw):
    raw = raw.strip()
    if "\n" in raw:
        raw = raw.splitlines()[0].strip()
    if "=" in raw.split()[0] and raw.split("=", 1)[0].isupper():
        raw = raw.split("=", 1)[1].strip().strip('"').strip("'")
    return raw


def make_cfg(tmp, name):
    cfg = os.path.join(tmp, name)
    os.makedirs(cfg + "/scripts")
    os.makedirs(cfg + "/script-opts")
    shutil.copytree(os.path.join(REPO, "script-modules"), cfg + "/script-modules")
    return cfg


def module_layer(tmp, providers):
    cfg = make_cfg(tmp, "probe-cfg")
    open(cfg + "/scripts/probe.lua", "w").write(PROBE)
    jobs = []
    for p in providers:
        kf = os.environ.get("KANDONG_TEST_KEY_FILE_" + p.upper(), KEY_FILES[p])
        tf = os.path.join(tmp, p + ".k")
        fd = os.open(tf, os.O_WRONLY | os.O_CREAT, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(read_key(p))
        jobs.append({"provider": p, "key_file": tf})
    out = os.path.join(tmp, "probe.json")
    jobs_file = os.path.join(tmp, "jobs.json")
    json.dump(jobs, open(jobs_file, "w"))
    subprocess.run(["mpv", "--config-dir=" + cfg, "--idle=yes", "--vo=null", "--ao=null", "--no-terminal",
                    "--log-file=" + os.path.join(tmp, "probe.log"),
                    "--script-opts=probe_out=" + out + ",probe_jobs=" + jobs_file],
                   timeout=600)
    if not os.path.exists(out):
        log = open(os.path.join(tmp, "probe.log"), encoding="utf-8", errors="replace").read()
        print("\n".join(l for l in log.splitlines() if "[probe]" in l and ("[e]" in l or "[w]" in l))[-2000:])
    for j in jobs:
        if os.path.exists(j["key_file"]):
            os.remove(j["key_file"])
    return json.load(open(out))


def srt_time(t):
    return "%02d:%02d:%02d,%03d" % (t // 3600, t // 60 % 60, t % 60, round(t * 1000) % 1000)


def read_key(provider):
    kf = os.environ.get("KANDONG_TEST_KEY_FILE_" + provider.upper(), KEY_FILES[provider])
    return norm_key(open(kf).read())


def e2e(tmp, provider, model, effort, concurrency):
    cfg = make_cfg(tmp, "e2e-%s-%d" % (provider, concurrency))
    shutil.copy(os.path.join(REPO, "scripts/floattranslate.lua"), cfg + "/scripts/")
    endpoint = {"openai": "https://api.openai.com/v1/chat/completions",
                "anthropic": "https://api.anthropic.com/v1/messages",
                "google": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"}[provider]
    conf = open(os.path.join(REPO, "script-opts/floattranslate.conf"), encoding="utf-8").read()
    lines = [l for l in conf.splitlines() if not l.split("=")[0] in
             ("endpoint", "model", "provider", "key_ref", "reasoning_effort", "cloud_concurrency", "asr_enabled")]
    lines += ["endpoint=" + endpoint, "model=" + model, "provider=" + provider, "key_ref=" + provider,
              "reasoning_effort=" + effort, "cloud_concurrency=%d" % concurrency, "asr_enabled=no"]
    open(cfg + "/script-opts/floattranslate.conf", "w", encoding="utf-8").write("\n".join(lines) + "\n")
    vdir = os.path.join(tmp, "v-%s-%d" % (provider, concurrency))
    os.makedirs(vdir)
    video = os.path.join(vdir, "clip.mkv")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=5:duration=65",
                    "-c:v", "libx264", "-preset", "ultrafast", video], check=True)
    with open(os.path.join(vdir, "clip.srt"), "w", encoding="utf-8") as f:
        for i, s in enumerate(SUBS):
            f.write("%d\n%s --> %s\n%s\n\n" % (i + 1, srt_time(i * 2.5 + 0.5), srt_time(i * 2.5 + 2.4), s))
    done = os.path.join(vdir, "clip.ft.zh-TW.srt")
    t0 = time.time()
    proc = subprocess.Popen(["mpv", "--config-dir=" + cfg, "--vo=null", "--ao=null", "--no-terminal", "--pause",
                             "--log-file=" + os.path.join(vdir, "mpv.log"), video])
    while time.time() - t0 < 180 and not os.path.exists(done):
        time.sleep(0.2)
    elapsed = time.time() - t0
    proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()
    if not os.path.exists(done):
        log = open(os.path.join(vdir, "mpv.log"), encoding="utf-8", errors="replace").read()
        warn = [l for l in log.splitlines() if "[w][floattranslate]" in l or "[e][floattranslate]" in l][-3:]
        return {"done": False, "seconds": round(elapsed, 1), "warnings": warn}
    cues = json.load(open(os.path.join(vdir, "clip.ft.zh-TW.json")))["cues"]
    log = open(os.path.join(vdir, "mpv.log"), encoding="utf-8", errors="replace").read()
    return {"done": True, "seconds": round(elapsed, 1), "cues": len(cues),
            "key_in_debug_log": read_key(provider) in log,
            "samples": [(c["src"], c["tgt"]) for c in cues if c["src"].startswith(("Welcome", "Ellie", "Amazon", "Like the", "The board"))]}


def delete_keys(providers):
    for p in providers:
        subprocess.run(["security", "delete-generic-password", "-s", "KanDong API key", "-a", p],
                       capture_output=True)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    keep = "--keep-keys" in sys.argv
    providers = args or ["openai", "anthropic", "google"]
    tmp = tempfile.mkdtemp(prefix="kd-live-")
    fails = []
    try:
        print("== 模組層（鑰匙圈、模型清單、思考程度、錯誤訊息）")
        res = module_layer(tmp, providers)
        plog = open(os.path.join(tmp, "probe.log"), encoding="utf-8", errors="replace").read()
        for p in providers:
            if read_key(p) in plog:
                fails.append(p + " 金鑰出現在 mpv 除錯紀錄")
        best = {}
        for r in res:
            p = r["provider"]
            ok = r.get("key_valid") and r.get("store_ok") and r.get("read_matches") and r.get("text") \
                and not r.get("key_in_process_args")
            print(json.dumps({k: v for k, v in r.items()}, ensure_ascii=False, indent=1))
            if not ok:
                fails.append(p + " 模組層")
            else:
                best[p] = (r["model"], r["effort"])
        print("== 端對端（真的 floattranslate.lua，24 句字幕）")
        for p, (model, effort) in best.items():
            for conc in (3, 1):
                r = e2e(tmp, p, model, effort, conc)
                print(p, model, "同時 %d 句" % conc, json.dumps(r, ensure_ascii=False))
                if not r["done"] or r.get("cues") != len(SUBS) or r.get("key_in_debug_log"):
                    fails.append("%s 端對端（同時 %d 句）" % (p, conc))
    finally:
        if not keep:
            delete_keys(providers)
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n" + ("全部通過" if not fails else "FAIL：" + "、".join(fails)))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
