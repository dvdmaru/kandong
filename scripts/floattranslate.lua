-- 看懂 KanDong（內部代號 floattranslate：設定檔名、快速鍵名稱、快取副檔名沿用）
-- mpv user script：字幕即時翻譯（內網 OpenAI-compatible 翻譯模型，如 Hy-MT2）
--
-- 行為總覽：
--   1. 開檔時取得字幕全文（外掛 SRT/ASS，或用 ffmpeg 抽內嵌文字字幕軌）。
--   2. 從播放位置起「超前預譯」，單一併發（配合 llama-server --parallel 1）。
--   3. 觀察 sub-text，於畫面下緣疊加譯文（原生字幕自動上移形成雙語）。
--   4. 譯文寫 sidecar JSON（<影片>.ft.<lang>.json），重看零成本；
--      全部譯完另輸出 <影片>.ft.<lang>.srt 可給任何播放器用。
--   5. 拿不到字幕全文（解析失敗）→ 退回逐句即時翻譯模式。
--      圖形字幕（PGS/VobSub）無文字可讀，明確告知不支援，不假裝有譯文。
--
-- 快速鍵：Ctrl+t 開/關翻譯

local mp = require "mp"
local utils = require "mp.utils"
local msg = require "mp.msg"
local options = require "mp.options"

local opts = {
    -- 翻譯伺服器（OpenAI-compatible /v1/chat/completions）
    endpoint = "http://127.0.0.1:8080/v1/chat/completions",
    api_key = "",
    model = "tencent/Hy-MT2-7B-GGUF",
    -- 目標語（送給模型的描述字串；台灣繁中會啟用專屬 regression 範例）
    target_language = "Traditional Chinese as used in Taiwan",
    -- sidecar 檔名中的語言代碼
    lang_code = "zh-TW",
    -- 開檔自動啟動
    auto_start = true,
    -- 送模型的滾動 source-only 上下文句數（不送先前譯文，防複誦）
    context_lines = 12,
    max_tokens = 256,
    -- 單次請求逾時（秒）
    curl_timeout = 25,
    -- 連續失敗幾次後暫停重試
    max_consecutive_failures = 3,
    -- 失敗暫停秒數
    failure_cooldown = 30,
    -- 譯文字級（以 1080p 為基準）
    font_size = 46,
    -- 譯文距畫面底部邊距（以 1080p 為基準）
    bottom_margin = 20,
    -- 啟用時把原生字幕上移到 sub-pos 這個值（0-150，預設 100=貼底）
    raise_original_sub_pos = 88,
    -- 寫 sidecar 快取
    save_sidecar = true,
    -- 內嵌軌抽取用的 ffmpeg 執行檔
    ffmpeg_path = "ffmpeg",
    -- ===== 語音辨識（無字幕影片；whisper.cpp server）=====
    asr_enabled = true,
    asr_endpoint = "http://127.0.0.1:8090/inference",
    -- 每段轉寫的音訊長度（秒）；段尾加 overlap 秒避免切斷句子
    asr_chunk = 120,
    asr_overlap = 2,
    -- 語言（auto=自動偵測；確定是英文片填 en 可更快更準）
    asr_language = "auto",
    -- 單段轉寫逾時（秒；含排隊。CPU 慢機器可調大）
    asr_timeout = 300,
}
options.read_options(opts, "floattranslate")

-- Windows portable 便利：conf 沒特別指定時，自動使用 mpv.exe 旁邊的 ffmpeg.exe
-- （資料夾放哪個路徑都能跑；Mac/Linux 上該檔不存在，維持用 PATH 裡的 ffmpeg）
if opts.ffmpeg_path == "ffmpeg" then
    local beside = mp.command_native({ "expand-path", "~~exe_dir/ffmpeg.exe" })
    if type(beside) == "string" then
        local f = io.open(beside, "rb")
        if f then
            f:close()
            opts.ffmpeg_path = beside
        end
    end
end

-- ===== 狀態 =====

local state = {
    enabled = false,
    cues = {},              -- { {s=秒, e=秒, src=原文, tgt=譯文或nil}, ... }
    by_norm = {},           -- 正規化原文 -> cue index
    cursor = 1,             -- 預譯 worker 目前優先位置
    busy = false,           -- 是否有請求在途
    realtime = false,       -- 逐句即時模式（沒有字幕全文）
    rt_cache = {},          -- 即時模式 norm -> 譯文
    rt_context = {},        -- 即時模式滾動原文上下文
    consecutive_failures = 0,
    cooldown_until = 0,
    current_norm = nil,     -- 目前畫面字幕的正規化原文
    overlay = nil,
    saved_sub_pos = nil,
    total = 0,
    done = 0,
    file_key = nil,         -- 目前影片絕對路徑（避免跨檔污染）
    tmp_seq = 0,
    -- ASR（語音辨識）模式
    asr = false,            -- 進行中：cues 由 whisper 逐段長出
    asr_busy = false,
    asr_done = false,       -- 全片轉寫完成
    asr_next_start = 0,     -- 下一段音訊起點（秒）
    asr_jumped = false,     -- 曾跳段（seek 或倍速超車造成空洞）→ 不寫轉寫快取
    asr_last_seek = nil,    -- 最近一次 seek 事件的牆鐘時間（分辨「使用者 seek」與「倍速超車」）
    asr_timer = nil,        -- ASR 模式的顯示計時器（無原生字幕可觀察）
    asr_cue_hint = 1,       -- 顯示查找的起始 index（避免每次全掃）
}

local function osd(text, dur)
    mp.osd_message("看懂：" .. text, dur or 3)
end

-- 2.00 顯示成 2、0.50 顯示成 0.5；D/A 微調出來的 1.21 之類照舊保留兩位小數
local function fmt_speed(v)
    local s = ("%.2f"):format(v)
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
    return s
end

local function normalize(text)
    if not text then return nil end
    local t = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return nil end
    return t
end

-- 去掉 SRT 內的 <i>/<font> 類標記與 ASS 內嵌 {\tag}
local function strip_markup(text)
    local t = text:gsub("{\\[^}]-}", "")
    t = t:gsub("{[^}]-}", "")
    t = t:gsub("<[^>]->", "")
    return t
end

local function is_abs_path(p)
    return p:match("^/") or p:match("^%a:[/\\]") or p:match("^\\\\")
end

local function abs_path(p)
    if not p then return nil end
    if is_abs_path(p) then return p end
    local wd = mp.get_property("working-directory")
    if not wd then return p end
    return utils.join_path(wd, p)
end

local function tmp_dir()
    return os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
end

local function tmp_file(suffix)
    state.tmp_seq = state.tmp_seq + 1
    local pid = utils.getpid and utils.getpid() or os.time()
    return utils.join_path(tmp_dir(),
        string.format("floattranslate-%s-%d%s", tostring(pid), state.tmp_seq, suffix))
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

-- ===== 字幕解析 =====

local function parse_time_srt(h, m, s, ms)
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000
end

local function parse_srt(data)
    local cues = {}
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
    -- WebVTT 與 SRT 結構相近，一併吃：去掉 WEBVTT 檔頭
    data = data:gsub("^WEBVTT[^\n]*\n", "")
    for block in (data .. "\n\n"):gmatch("(.-)\n\n") do
        local h1, m1, s1, ms1, h2, m2, s2, ms2 =
            block:match("(%d+):(%d+):(%d+)[,%.](%d+)%s*%-%->%s*(%d+):(%d+):(%d+)[,%.](%d+)")
        if h1 then
            local text_part = block:match("%-%->[^\n]*\n(.*)")
            if text_part then
                local text = strip_markup(text_part)
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if text ~= "" then
                    cues[#cues + 1] = {
                        s = parse_time_srt(h1, m1, s1, ms1),
                        e = parse_time_srt(h2, m2, s2, ms2),
                        src = text,
                    }
                end
            end
        end
    end
    return cues
end

local function parse_time_ass(str)
    local h, m, s, cs = str:match("(%d+):(%d+):(%d+)%.(%d+)")
    if not h then return nil end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(cs) / 100
end

local function parse_ass(data)
    local cues = {}
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in data:gmatch("[^\n]+") do
        local body = line:match("^Dialogue:%s*(.*)")
        if body then
            -- 標準欄位：Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
            local fields = {}
            local rest = body
            for _ = 1, 9 do
                local head, tail = rest:match("^([^,]*),(.*)$")
                if not head then rest = nil; break end
                fields[#fields + 1] = head
                rest = tail
            end
            if rest and #fields == 9 then
                local s = parse_time_ass(fields[2])
                local e = parse_time_ass(fields[3])
                local text = strip_markup(rest)
                text = text:gsub("\\N", "\n"):gsub("\\n", "\n"):gsub("\\h", " ")
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if s and e and text ~= "" then
                    cues[#cues + 1] = { s = s, e = e, src = text }
                end
            end
        end
    end
    table.sort(cues, function(a, b) return a.s < b.s end)
    return cues
end

local function parse_subtitle_file(path)
    local data = read_file(path)
    if not data then return nil end
    local lower = path:lower()
    local cues
    if lower:match("%.ass$") or lower:match("%.ssa$") then
        cues = parse_ass(data)
    else
        cues = parse_srt(data)
    end
    if cues and #cues > 0 then return cues end
    return nil
end

-- ===== sidecar 快取 =====

local function sidecar_base()
    local path = abs_path(mp.get_property("path"))
    if not path then return nil end
    return (path:gsub("%.[^./\\]+$", ""))
end

local function sidecar_json_path()
    local base = sidecar_base()
    if not base then return nil end
    return base .. ".ft." .. opts.lang_code .. ".json"
end

local function sidecar_srt_path()
    local base = sidecar_base()
    if not base then return nil end
    return base .. ".ft." .. opts.lang_code .. ".srt"
end

local function load_sidecar()
    local path = sidecar_json_path()
    if not path then return end
    local data = read_file(path)
    if not data then return end
    local ok, parsed = pcall(utils.parse_json, data)
    if not ok or type(parsed) ~= "table" or type(parsed.cues) ~= "table" then return end
    local hit = 0
    for _, item in ipairs(parsed.cues) do
        if item.src and item.tgt then
            local idx = state.by_norm[normalize(item.src) or ""]
            if idx and not state.cues[idx].tgt then
                state.cues[idx].tgt = item.tgt
                state.done = state.done + 1
                hit = hit + 1
            end
        end
    end
    if hit > 0 then
        msg.info(("sidecar 快取命中 %d 句"):format(hit))
    end
end

local function fmt_srt_time(t)
    local ms = math.floor((t - math.floor(t)) * 1000 + 0.5)
    local total = math.floor(t)
    return string.format("%02d:%02d:%02d,%03d",
        math.floor(total / 3600), math.floor(total / 60) % 60, total % 60, ms)
end

local function save_sidecar(final)
    if not opts.save_sidecar or state.realtime or #state.cues == 0 then return end
    if state.done == 0 then return end
    local path = sidecar_json_path()
    if not path then return end
    local out = { version = 1, lang = opts.lang_code, cues = {} }
    for _, cue in ipairs(state.cues) do
        if cue.tgt then
            out.cues[#out.cues + 1] = { s = cue.s, e = cue.e, src = cue.src, tgt = cue.tgt }
        end
    end
    local ok, encoded = pcall(utils.format_json, out)
    if not ok or not encoded then
        msg.warn("sidecar JSON 序列化失敗，跳過快取寫入")
        return
    end
    if not write_file(path, encoded) then
        msg.warn("sidecar 寫入失敗（目錄唯讀？）：" .. path)
        return
    end
    -- 全部譯完才輸出 SRT，避免半成品被誤當完整譯文（ASR 模式還要等轉寫全片完成）
    if final and state.done >= state.total and (not state.asr or state.asr_done) then
        local lines = {}
        for i, cue in ipairs(state.cues) do
            lines[#lines + 1] = tostring(i)
            lines[#lines + 1] = fmt_srt_time(cue.s) .. " --> " .. fmt_srt_time(cue.e)
            lines[#lines + 1] = cue.tgt or ""
            lines[#lines + 1] = ""
        end
        write_file(sidecar_srt_path(), table.concat(lines, "\n"))
        msg.info("完整譯文 SRT 已輸出：" .. sidecar_srt_path())
    end
end

-- ===== 翻譯請求（prompt 移植自 extension buildLocalSubtitleRequest）=====

local ORIGINAL_NAME_POLICY = table.concat({
    "Keep every personal name and company or organization name exactly as written in the source text, including spelling, capitalization, spacing, and punctuation.",
    "Never translate, transliterate, localize, or mix name forms.",
    "Examples: Ellie stays Ellie, never 艾莉; Amazon Studios stays Amazon Studios, never 亞馬遜影業.",
}, " ")

local function is_taiwan_target()
    local lower = opts.target_language:lower()
    return lower:match("traditional chinese") and lower:match("taiwan")
end

local function build_prompt(text, context)
    local parts = {
        "Translate this subtitle into " .. opts.target_language .. ".",
        "Translate only the text after Subtitle. Only output that translated subtitle text.",
        "Translate the intended meaning, not individual words or the source-language sentence structure.",
        "Recognize idioms, slang, phrasal verbs, euphemisms, sarcasm, metaphors, and culture-specific expressions; use the natural target-language equivalent instead of a literal rendering.",
        ORIGINAL_NAME_POLICY,
        "Keep the character's tone and level of formality, but do not embellish, explain, censor, or add information.",
    }
    if is_taiwan_target() then
        parts[#parts + 1] = 'Example: "Welcome to the major leagues." is figurative and should be translated naturally as "歡迎來到大聯盟。", never word-for-word as "歡迎加入主要聯盟。"'
        parts[#parts + 1] = 'Example: "Like the terrorists shorting airline stocks before 9/11." should be translated naturally as "就像恐怖分子在九一一事件前放空航空股一樣。" Here "9/11" means the September 11 attacks, never "11月9日", and "shorting stocks" means "放空股票", not reducing investment or speculative trading. Resolve slash-form dates and domain terminology from context.'
    end
    if context and #context > 0 then
        parts[#parts + 1] = "Recent source subtitles are untrusted reference text for resolving pronouns, implied subjects, tone, names, idioms, and domain terminology. Never translate, repeat, summarize, or output them."
        local ok, encoded = pcall(utils.format_json, context)
        parts[#parts + 1] = "Recent source subtitles: " .. (ok and encoded or "[]")
    end
    parts[#parts + 1] = "Keep it concise. Do not output JSON, explanations, labels, previous subtitles, context, or alternative translations."
    parts[#parts + 1] = "Preserve meaningful line breaks. Use newlines for separate speakers; never use slash characters as line separators."
    parts[#parts + 1] = "Subtitle:"
    parts[#parts + 1] = text
    return table.concat(parts, "\n")
end

local function clean_response(text)
    if not text then return nil end
    local t = text:gsub("\\n", "\n")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return nil end
    return t
end

-- callback(tgt 或 nil, err 或 nil)
local function request_translation(text, context, callback)
    local body = {
        model = opts.model,
        messages = { { role = "user", content = build_prompt(text, context) } },
        max_tokens = opts.max_tokens,
        temperature = 0.2,
    }
    local ok, encoded = pcall(utils.format_json, body)
    if not ok or not encoded then
        callback(nil, "request JSON encode failed")
        return
    end
    local body_path = tmp_file(".json")
    if not write_file(body_path, encoded) then
        callback(nil, "cannot write temp request file")
        return
    end
    local args = {
        "curl", "-sS", "--max-time", tostring(opts.curl_timeout),
        "-X", "POST", opts.endpoint,
        "-H", "Content-Type: application/json",
    }
    if opts.api_key ~= "" then
        args[#args + 1] = "-H"
        args[#args + 1] = "Authorization: Bearer " .. opts.api_key
    end
    args[#args + 1] = "--data-binary"
    args[#args + 1] = "@" .. body_path
    mp.command_native_async({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, result)
        os.remove(body_path)
        if not success or not result or result.status ~= 0 then
            local err = result and result.stderr or "subprocess failed"
            callback(nil, "curl: " .. tostring(err):sub(1, 200))
            return
        end
        local pok, parsed = pcall(utils.parse_json, result.stdout)
        if not pok or type(parsed) ~= "table" then
            callback(nil, "invalid JSON response: " .. tostring(result.stdout):sub(1, 120))
            return
        end
        if parsed.error then
            local emsg = type(parsed.error) == "table" and parsed.error.message or tostring(parsed.error)
            callback(nil, "server error: " .. tostring(emsg))
            return
        end
        local content = parsed.choices and parsed.choices[1] and parsed.choices[1].message
            and parsed.choices[1].message.content
        local tgt = clean_response(content)
        if not tgt then
            callback(nil, "empty translation")
            return
        end
        callback(tgt, nil)
    end)
end

-- ===== 顯示 =====

local function ass_escape(text)
    local t = text:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}")
    t = t:gsub("\n", "\\N")
    return t
end

local function ensure_overlay()
    if not state.overlay then
        state.overlay = mp.create_osd_overlay("ass-events")
    end
    return state.overlay
end

local function render_translation(tgt)
    local ov = ensure_overlay()
    if not tgt then
        ov.data = ""
        ov:update()
        return
    end
    local dims = mp.get_property_native("osd-dimensions")
    local w = (dims and dims.w and dims.w > 0) and dims.w or 1280
    local h = (dims and dims.h and dims.h > 0) and dims.h or 720
    ov.res_x = w
    ov.res_y = h
    local scale = h / 1080
    local fs = math.max(16, math.floor(opts.font_size * scale * (state.font_scale or 1.0) + 0.5))
    local margin = math.floor(opts.bottom_margin * scale + 0.5)
    ov.data = string.format(
        "{\\an2\\pos(%d,%d)\\fs%d\\bord%d\\shad0\\c&HFFFFFF&\\3c&H000000&\\q1}%s",
        math.floor(w / 2), h - margin, fs, math.max(2, math.floor(2 * scale + 0.5)),
        ass_escape(tgt))
    ov:update()
end

local function clear_overlay()
    if state.overlay then
        state.overlay.data = ""
        state.overlay:update()
    end
end

local function refresh_current()
    -- ASR 模式的顯示由計時器負責；這裡只把重繪旗標歸零讓下個 tick 帶上新譯文
    if state.asr then
        state.asr_last_render = nil
        return
    end
    if not state.enabled or not state.current_norm then
        clear_overlay()
        return
    end
    local tgt
    if state.realtime then
        tgt = state.rt_cache[state.current_norm]
    else
        local idx = state.by_norm[state.current_norm]
        tgt = idx and state.cues[idx].tgt
    end
    render_translation(tgt)
end

-- ===== 超前預譯 worker =====

local schedule_worker -- 前向宣告

local function cue_index_at(time_pos)
    if not time_pos then return 1 end
    for i, cue in ipairs(state.cues) do
        if cue.e >= time_pos then return i end
    end
    return #state.cues
end

local function next_untranslated()
    for i = state.cursor, #state.cues do
        if not state.cues[i].tgt then return i end
    end
    for i = 1, state.cursor - 1 do
        if not state.cues[i].tgt then return i end
    end
    return nil
end

local function build_context_for(idx)
    local ctx = {}
    local from = math.max(1, idx - opts.context_lines)
    for i = from, idx - 1 do
        ctx[#ctx + 1] = state.cues[i].src
    end
    return ctx
end

local function on_translate_done(idx, file_key, tgt, err)
    state.busy = false
    if file_key ~= state.file_key then return end -- 已換檔，丟棄
    if err then
        state.consecutive_failures = state.consecutive_failures + 1
        msg.warn(("cue %d 翻譯失敗（連續 %d 次）：%s"):format(idx, state.consecutive_failures, err))
        if state.consecutive_failures >= opts.max_consecutive_failures then
            state.cooldown_until = mp.get_time() + opts.failure_cooldown
            osd(("翻譯伺服器連線失敗，%d 秒後重試（檢查 %s）"):format(
                opts.failure_cooldown, opts.endpoint), 6)
        end
    else
        state.consecutive_failures = 0
        if not state.cues[idx].tgt then
            state.cues[idx].tgt = tgt
            state.done = state.done + 1
        end
        refresh_current()
        if state.done >= state.total and (not state.asr or state.asr_done) then
            osd(("全片 %d 句預譯完成"):format(state.total), 4)
            save_sidecar(true)
        elseif state.done % 50 == 0 then
            msg.info(("預譯進度 %d/%d"):format(state.done, state.total))
            save_sidecar(false)
        end
    end
    schedule_worker()
end

schedule_worker = function()
    if not state.enabled or state.realtime or state.busy then return end
    if mp.get_time() < state.cooldown_until then
        mp.add_timeout(state.cooldown_until - mp.get_time() + 0.1, schedule_worker)
        return
    end
    local idx = next_untranslated()
    if not idx then return end
    state.busy = true
    local file_key = state.file_key
    request_translation(state.cues[idx].src, build_context_for(idx), function(tgt, err)
        on_translate_done(idx, file_key, tgt, err)
    end)
end

-- ===== 即時模式（沒有字幕全文時逐句翻）=====

local function realtime_translate(norm, src)
    if state.rt_cache[norm] or state.busy then return end
    state.busy = true
    local file_key = state.file_key
    local ctx = {}
    for _, line in ipairs(state.rt_context) do ctx[#ctx + 1] = line end
    request_translation(src, ctx, function(tgt, err)
        state.busy = false
        if file_key ~= state.file_key then return end
        if err then
            state.consecutive_failures = state.consecutive_failures + 1
            msg.warn("即時翻譯失敗：" .. err)
            if state.consecutive_failures >= opts.max_consecutive_failures then
                state.cooldown_until = mp.get_time() + opts.failure_cooldown
                osd("翻譯伺服器連線失敗，暫停重試", 5)
            end
            return
        end
        state.consecutive_failures = 0
        state.rt_cache[norm] = tgt
        refresh_current()
    end)
end

local function push_rt_context(src)
    state.rt_context[#state.rt_context + 1] = src
    while #state.rt_context > opts.context_lines do
        table.remove(state.rt_context, 1)
    end
end

-- ===== 語音辨識（ASR）模式：無字幕影片切段送 whisper，cues 逐段長出 =====

local function asr_srt_path()
    local base = sidecar_base()
    if not base then return nil end
    return base .. ".ft.asr.srt"
end

local function asr_partial_path()
    local base = sidecar_base()
    if not base then return nil end
    return base .. ".ft.asr.partial.json"
end

-- 進度快取：完整前存 partial JSON（含續轉位置），完成才轉正成 .ft.asr.srt
local function asr_save_partial()
    if not state.asr or state.asr_jumped or #state.cues == 0 then return end
    local path = asr_partial_path()
    if not path then return end
    local out = { version = 1, next_start = state.asr_next_start, cues = {} }
    for _, cue in ipairs(state.cues) do
        out.cues[#out.cues + 1] = { s = cue.s, e = cue.e, src = cue.src }
    end
    local ok, encoded = pcall(utils.format_json, out)
    if ok and encoded then write_file(path, encoded) end
end

local function asr_finalize()
    state.asr_done = true
    osd(("語音辨識完成，共 %d 句"):format(#state.cues), 4)
    -- 翻譯若已先追平，最終譯文輸出不會再由 on_translate_done 觸發，這裡補上
    if state.done >= state.total then save_sidecar(true) end
    if not state.asr_jumped and #state.cues > 0 then
        local path = asr_srt_path()
        if path then
            local lines = {}
            for i, cue in ipairs(state.cues) do
                lines[#lines + 1] = tostring(i)
                lines[#lines + 1] = fmt_srt_time(cue.s) .. " --> " .. fmt_srt_time(cue.e)
                lines[#lines + 1] = cue.src
                lines[#lines + 1] = ""
            end
            if write_file(path, table.concat(lines, "\n")) then
                msg.info("轉寫快取已輸出：" .. path)
                local pp = asr_partial_path()
                if pp then os.remove(pp) end
            end
        end
    elseif state.asr_jumped then
        msg.info("曾 seek 跳段（轉寫有空洞），本次不寫轉寫快取")
    end
end

local function asr_append_cues(new_cues, chunk_start)
    local added = 0
    for _, seg in ipairs(new_cues) do
        -- 段尾 overlap 區的句子丟掉（下一段會重新涵蓋）
        if seg.s < opts.asr_chunk then
            local cue = { s = seg.s + chunk_start, e = seg.e + chunk_start, src = seg.src }
            state.cues[#state.cues + 1] = cue
            state.total = state.total + 1
            local norm = normalize(cue.src)
            if norm and not state.by_norm[norm] then
                state.by_norm[norm] = #state.cues
            end
            added = added + 1
        end
    end
    return added
end

local asr_schedule -- 前向宣告

local function asr_on_chunk_done(chunk_start, file_key, srt_text, err)
    state.asr_busy = false
    if file_key ~= state.file_key then return end
    if err then
        state.asr_failures = (state.asr_failures or 0) + 1
        msg.warn(("ASR 段 %ds 失敗（連續 %d 次）：%s"):format(chunk_start, state.asr_failures, err))
        if state.asr_failures >= opts.max_consecutive_failures then
            osd(("語音辨識伺服器連線失敗，%d 秒後重試（檢查 %s）"):format(
                opts.failure_cooldown, opts.asr_endpoint), 6)
            mp.add_timeout(opts.failure_cooldown, asr_schedule)
        else
            mp.add_timeout(2, asr_schedule)
        end
        return
    end
    state.asr_failures = 0
    local segs = parse_srt(srt_text or "")
    asr_append_cues(segs, chunk_start)
    state.asr_next_start = chunk_start + opts.asr_chunk
    asr_save_partial()
    local duration = mp.get_property_native("duration")
    if duration and duration > 0 then
        msg.info(("語音辨識進度 %d/%d 秒，累計 %d 句"):format(
            math.min(state.asr_next_start, math.floor(duration)), math.floor(duration), #state.cues))
    end
    schedule_worker() -- 新句子交給翻譯 worker
    asr_schedule()
end

asr_schedule = function()
    if not state.enabled or not state.asr or state.asr_busy or state.asr_done then return end
    local duration = mp.get_property_native("duration")
    if duration and state.asr_next_start >= duration - 0.5 then
        asr_finalize()
        return
    end
    state.asr_busy = true
    local chunk_start = state.asr_next_start
    local file_key = state.file_key
    local wav = tmp_file(".wav")
    mp.command_native_async({
        name = "subprocess",
        args = {
            opts.ffmpeg_path, "-y", "-loglevel", "error",
            "-ss", tostring(chunk_start),
            "-t", tostring(opts.asr_chunk + opts.asr_overlap),
            "-i", state.asr_video,
            "-vn", "-ac", "1", "-ar", "16000", "-f", "wav",
            wav,
        },
        capture_stdout = true, capture_stderr = true, playback_only = false,
    }, function(success, result)
        if not success or not result or result.status ~= 0 then
            os.remove(wav)
            asr_on_chunk_done(chunk_start, file_key, nil,
                "ffmpeg 音訊抽取失敗：" .. tostring(result and result.stderr or ""):sub(1, 150))
            return
        end
        mp.command_native_async({
            name = "subprocess",
            args = {
                "curl", "-sS", "--max-time", tostring(opts.asr_timeout),
                "-F", "file=@" .. wav,
                "-F", "temperature=0",
                "-F", "language=" .. opts.asr_language,
                "-F", "response_format=srt",
                opts.asr_endpoint,
            },
            capture_stdout = true, capture_stderr = true, playback_only = false,
        }, function(ok2, res2)
            os.remove(wav)
            if not ok2 or not res2 or res2.status ~= 0 then
                asr_on_chunk_done(chunk_start, file_key, nil,
                    "curl: " .. tostring(res2 and res2.stderr or "subprocess failed"):sub(1, 150))
                return
            end
            if (res2.stdout or ""):match('"error"') and not res2.stdout:match("%-%->") then
                asr_on_chunk_done(chunk_start, file_key, nil,
                    "server error: " .. res2.stdout:sub(1, 150))
                return
            end
            asr_on_chunk_done(chunk_start, file_key, res2.stdout, nil)
        end)
    end)
end

-- ASR 模式沒有原生字幕可觀察，用計時器對時間軸顯示「原文＋譯文」
local function asr_display_tick()
    if not state.enabled or not state.asr then return end
    local t = mp.get_property_native("time-pos")
    if not t then return end
    -- 播放位置超出已轉寫範圍 → 從所在段續轉（跳過的區間本次不補、不寫轉寫快取）。
    -- 兩種成因：使用者 seek，或倍速播放快過 whisper 吞吐（「超車」）。後者使用者
    -- 不會自己想到，畫面上要講清楚，否則只看到字幕突然消失。
    if not state.asr_done and t > state.asr_next_start + opts.asr_chunk then
        local skipped_from = state.asr_next_start
        state.asr_next_start = math.floor(t / opts.asr_chunk) * opts.asr_chunk
        state.asr_jumped = true
        local by_seek = state.asr_last_seek and (mp.get_time() - state.asr_last_seek) < 3
        if by_seek then
            msg.info(("seek 超出已轉寫範圍，改從 %d 秒續轉"):format(state.asr_next_start))
        else
            local speed = mp.get_property_native("speed") or 1
            local text = ("語音辨識跟不上 %sx 倍速：%d–%d 秒這段不會有字幕，本片這次也不存轉寫快取；按 S 回 1x 可避免再發生"):format(
                fmt_speed(speed), skipped_from, state.asr_next_start)
            osd(text, 5)
            msg.warn(text)
        end
    end
    local n = #state.cues
    local i = state.asr_cue_hint
    if i > n then i = 1 end
    if n > 0 and state.cues[i] and t < state.cues[i].s then i = 1 end
    local cur = nil
    while i <= n do
        local c = state.cues[i]
        if t < c.s then break end
        if t <= c.e then cur = i; break end
        i = i + 1
    end
    state.asr_cue_hint = math.max(1, math.min(i, n > 0 and n or 1))
    local textout = nil
    if cur then
        local c = state.cues[cur]
        if not c.tgt then
            state.cursor = cur
            schedule_worker()
        end
        textout = c.src .. "\n" .. (c.tgt or "…")
    end
    if textout ~= state.asr_last_render then
        state.asr_last_render = textout
        if textout then render_translation(textout) else clear_overlay() end
    end
end

-- ===== sub-text 事件 =====

local function on_sub_text(_, value)
    if not state.enabled then return end
    local norm = normalize(value)
    if norm == state.current_norm then return end
    state.current_norm = norm
    if not norm then
        clear_overlay()
        return
    end
    if state.realtime then
        push_rt_context(value)
        if not state.rt_cache[norm] and mp.get_time() >= state.cooldown_until then
            realtime_translate(norm, value)
        end
    else
        local idx = state.by_norm[norm]
        if idx and not state.cues[idx].tgt then
            -- 把預譯優先權拉到目前播放位置
            state.cursor = idx
            schedule_worker()
        end
    end
    refresh_current()
end

-- ===== 字幕來源偵測 =====

local BITMAP_CODECS = {
    hdmv_pgs_subtitle = true, dvd_subtitle = true, dvb_subtitle = true, xsub = true,
}

local function selected_sub_track()
    local tracks = mp.get_property_native("track-list") or {}
    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.selected then return t end
    end
    -- 沒有選取中的字幕軌時，自動選第一條文字字幕軌（mpv 預設只自動選帶
    -- default 標記的軌，很多 mkv 的內嵌軌沒這個標記）
    for _, t in ipairs(tracks) do
        if t.type == "sub" and not BITMAP_CODECS[t.codec or ""] then
            mp.set_property_native("sid", t.id)
            msg.info(("自動選取字幕軌 #%d（%s）"):format(t.id, t.codec or "?"))
            return t
        end
    end
    return nil
end

-- 內嵌軌在 ffmpeg 0:s:N 的 N＝該軌之前的內嵌字幕軌數量（依 track-list 檔內順序）
local function ffmpeg_sub_stream_index(track)
    local tracks = mp.get_property_native("track-list") or {}
    local n = 0
    for _, t in ipairs(tracks) do
        if t.type == "sub" and not t.external then
            if t.id == track.id then return n end
            n = n + 1
        end
    end
    return nil
end

local function extract_embedded(track, callback)
    local stream_index = ffmpeg_sub_stream_index(track)
    if stream_index == nil then
        callback(nil, "找不到內嵌軌對應的 stream index")
        return
    end
    local video = abs_path(mp.get_property("path"))
    local out = tmp_file(".srt")
    mp.command_native_async({
        name = "subprocess",
        args = {
            opts.ffmpeg_path, "-y", "-loglevel", "error",
            "-i", video,
            "-map", "0:s:" .. stream_index,
            "-c:s", "srt",
            out,
        },
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, result)
        if not success or not result or result.status ~= 0 then
            callback(nil, "ffmpeg 抽取失敗：" ..
                tostring(result and result.stderr or ""):sub(1, 200))
            return
        end
        local cues = parse_subtitle_file(out)
        os.remove(out)
        if not cues then
            callback(nil, "抽出的字幕解析失敗")
            return
        end
        callback(cues, nil)
    end)
end

-- ===== 啟動 / 關閉 =====

local function set_cues(cues)
    state.cues = cues
    state.by_norm = {}
    state.total = #cues
    state.done = 0
    for i, cue in ipairs(cues) do
        local norm = normalize(cue.src)
        if norm and not state.by_norm[norm] then
            state.by_norm[norm] = i
        end
    end
    load_sidecar()
    state.cursor = cue_index_at(mp.get_property_native("time-pos"))
    if state.done >= state.total then
        osd(("字幕 %d 句已有完整快取，零翻譯成本"):format(state.total), 4)
    else
        osd(("字幕 %d 句，開始超前預譯（已快取 %d 句）"):format(state.total, state.done), 4)
    end
    schedule_worker()
    refresh_current()
end

local function begin_realtime(reason)
    state.realtime = true
    osd("拿不到字幕全文（" .. reason .. "），改用逐句即時翻譯", 5)
    msg.info("即時模式原因：" .. reason)
end

local function asr_activate(reason)
    -- 完整轉寫快取＝直接當外掛字幕載入，走既有（原生字幕＋預譯）管線
    local cache = asr_srt_path()
    if cache and read_file(cache) then
        local cues = parse_subtitle_file(cache)
        if cues then
            mp.commandv("sub-add", cache)
            state.saved_sub_pos = mp.get_property_native("sub-pos")
            mp.set_property_native("sub-pos", opts.raise_original_sub_pos)
            osd(("使用既有語音辨識快取（%d 句）"):format(#cues), 4)
            set_cues(cues)
            return
        end
    end
    state.asr = true
    state.asr_video = abs_path(mp.get_property("path"))
    state.asr_next_start = 0
    -- 部分轉寫快取 → 從斷點續轉
    local pp = asr_partial_path()
    local pdata = pp and read_file(pp)
    if pdata then
        local ok, parsed = pcall(utils.parse_json, pdata)
        if ok and type(parsed) == "table" and type(parsed.cues) == "table"
            and tonumber(parsed.next_start) then
            for _, item in ipairs(parsed.cues) do
                if item.src and item.s and item.e then
                    state.cues[#state.cues + 1] = { s = item.s, e = item.e, src = item.src }
                    state.total = state.total + 1
                    local norm = normalize(item.src)
                    if norm and not state.by_norm[norm] then
                        state.by_norm[norm] = #state.cues
                    end
                end
            end
            state.asr_next_start = tonumber(parsed.next_start)
            msg.info(("載入部分轉寫快取 %d 句，從 %d 秒續轉"):format(#state.cues, state.asr_next_start))
        end
    end
    load_sidecar() -- 已翻譯過的句子（依原文比對）直接回填
    osd("無字幕（" .. reason .. "）→ 語音辨識模式（whisper）啟動", 5)
    if not state.asr_timer then
        state.asr_timer = mp.add_periodic_timer(0.25, asr_display_tick)
    end
    state.asr_timer:resume()
    asr_schedule()
    schedule_worker()
end

local function activate()
    if state.enabled then return end
    -- 中途 Ctrl+t 關掉又打開：ASR 現場還在就直接恢復，不重新初始化
    if state.asr and #state.cues > 0 then
        state.enabled = true
        if state.asr_timer then state.asr_timer:resume() end
        asr_schedule()
        schedule_worker()
        osd("翻譯已恢復（語音辨識模式）", 2)
        return
    end
    local track = selected_sub_track()
    local bitmap = track and BITMAP_CODECS[track.codec or ""] or false
    if not track or bitmap then
        local reason = bitmap
            and ("只有圖形字幕 " .. tostring(track.codec) .. "，無文字可讀")
            or "找不到字幕軌"
        if opts.asr_enabled then
            state.enabled = true
            asr_activate(reason)
        elseif bitmap then
            osd("這是圖形字幕（" .. tostring(track.codec) .. "），沒有文字可翻譯，暫不支援", 6)
        else
            osd("目前沒有選取字幕軌——先載入/選擇字幕再按 Ctrl+t", 5)
        end
        return
    end
    state.enabled = true
    state.saved_sub_pos = mp.get_property_native("sub-pos")
    mp.set_property_native("sub-pos", opts.raise_original_sub_pos)

    local ext_file = track["external-filename"]
    if track.external and ext_file then
        local cues = parse_subtitle_file(abs_path(ext_file))
        if cues then
            set_cues(cues)
        else
            begin_realtime("外掛字幕解析失敗")
        end
    else
        osd("內嵌字幕軌抽取中…", 3)
        extract_embedded(track, function(cues, err)
            if not state.enabled then return end
            if cues then
                set_cues(cues)
            else
                begin_realtime(err or "抽取失敗")
            end
        end)
    end
    -- 立即處理目前畫面上的字幕
    on_sub_text(nil, mp.get_property("sub-text"))
end

local function deactivate()
    if not state.enabled then return end
    state.enabled = false
    save_sidecar(false)
    if state.asr then
        asr_save_partial()
        if state.asr_timer then state.asr_timer:stop() end
        state.asr_last_render = nil
    end
    clear_overlay()
    state.current_norm = nil
    if state.saved_sub_pos then
        mp.set_property_native("sub-pos", state.saved_sub_pos)
        state.saved_sub_pos = nil
    end
    osd("翻譯已關閉", 2)
end

local function toggle()
    if state.enabled then deactivate() else activate() end
end

local function reset_for_new_file()
    state.enabled = false
    state.cues = {}
    state.by_norm = {}
    state.cursor = 1
    state.busy = false
    state.realtime = false
    state.rt_cache = {}
    state.rt_context = {}
    state.consecutive_failures = 0
    state.cooldown_until = 0
    state.current_norm = nil
    state.done = 0
    state.total = 0
    state.asr = false
    state.asr_busy = false
    state.asr_done = false
    state.asr_next_start = 0
    state.asr_jumped = false
    state.asr_last_seek = nil
    state.asr_failures = 0
    state.asr_cue_hint = 1
    state.asr_last_render = nil
    state.asr_video = nil
    if state.asr_timer then state.asr_timer:stop() end
    clear_overlay()
    state.file_key = abs_path(mp.get_property("path"))
end

mp.register_event("file-loaded", function()
    save_sidecar(false)
    reset_for_new_file()
    if opts.auto_start then
        -- 等字幕軌選定再啟動
        mp.add_timeout(0.5, function()
            if state.file_key == abs_path(mp.get_property("path")) then activate() end
        end)
    end
end)

mp.register_event("seek", function()
    state.asr_last_seek = mp.get_time()
end)

mp.register_event("end-file", function()
    save_sidecar(false)
    asr_save_partial()
end)

mp.register_event("shutdown", function()
    save_sidecar(false)
    asr_save_partial()
end)

mp.observe_property("sub-text", "string", on_sub_text)
mp.observe_property("osd-dimensions", "native", function()
    if state.enabled then refresh_current() end
end)

mp.add_key_binding("ctrl+t", "floattranslate-toggle", toggle)

-- ===== 播放控制快速鍵 =====

local function show_speed()
    osd("播放速度 " .. fmt_speed(mp.get_property_native("speed")) .. "x", 1.5)
end

local function show_volume()
    osd(("音量 %d%%"):format(math.floor(mp.get_property_native("volume") + 0.5)), 1.5)
end

mp.add_key_binding("LEFT", "ft-seek-back", function()
    mp.commandv("seek", "-5", "relative", "exact")
end, { repeatable = true })

mp.add_key_binding("RIGHT", "ft-seek-fwd", function()
    mp.commandv("seek", "5", "relative", "exact")
end, { repeatable = true })

mp.add_key_binding("d", "ft-speed-up", function()
    mp.set_property_native("speed", math.min(3.0, mp.get_property_native("speed") * 1.1))
    show_speed()
end, { repeatable = true })

mp.add_key_binding("a", "ft-speed-down", function()
    mp.set_property_native("speed", math.max(0.1, mp.get_property_native("speed") * 0.9))
    show_speed()
end, { repeatable = true })

mp.add_key_binding("s", "ft-speed-reset", function()
    mp.set_property_native("speed", 1.0)
    show_speed()
end)

-- 固定倍速檔位：數字鍵 1–5 由慢到快（1=0.5x、2=1x、3=1.5x、4=2x、5=3x）。
-- 蓋掉 mpv 預設的 1–5（對比／亮度／gamma 微調），這台播放器用不到那些。
-- 上限 3x 與 D 鍵一致；mpv 預設 audio-pitch-correction=yes，變速不變調。
local SPEED_PRESETS = { 0.5, 1.0, 1.5, 2.0, 3.0 }
for i, v in ipairs(SPEED_PRESETS) do
    mp.add_key_binding(tostring(i), "ft-speed-preset-" .. i, function()
        mp.set_property_native("speed", v)
        show_speed()
    end)
end

mp.add_key_binding("UP", "ft-vol-up", function()
    mp.commandv("add", "volume", "5")
    show_volume()
end, { repeatable = true })

mp.add_key_binding("DOWN", "ft-vol-down", function()
    mp.commandv("add", "volume", "-5")
    show_volume()
end, { repeatable = true })

-- 字幕縮放：原生字幕（sub-scale）與譯文 overlay 一起縮放
state.font_scale = 1.0

local function apply_font_scale()
    mp.set_property_native("sub-scale", state.font_scale)
    state.asr_last_render = nil -- ASR 模式讓下個 tick 用新字級重繪
    refresh_current()
    osd(("字幕大小 %d%%"):format(math.floor(state.font_scale * 100 + 0.5)), 1.5)
end

mp.add_key_binding("=", "ft-sub-bigger", function()
    state.font_scale = math.min(2.0, state.font_scale + 0.1)
    apply_font_scale()
end, { repeatable = true })

mp.add_key_binding("-", "ft-sub-smaller", function()
    state.font_scale = math.max(0.5, state.font_scale - 0.1)
    apply_font_scale()
end, { repeatable = true })

msg.info("看懂 KanDong 已載入。Ctrl+t 翻譯開關｜←→ 進退5秒｜1–5 倍速 0.5x/1x/1.5x/2x/3x｜A/D 減/加速10%、S 回1x｜↑↓ 音量±5｜-/= 字幕縮放。endpoint=" .. opts.endpoint)
