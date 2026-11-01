-- 看懂 KanDong：設定選單「翻譯模型與伺服器」（右鍵 → 設定 → 翻譯模型與伺服器…）
--
-- 做四件事：
--   1. 列出找得到的翻譯模型（KanDong/models、~/.cache/kandong/models、LM Studio 的模型資料夾），
--      並顯示目前在用哪一個。
--   2. 在播放器裡下載模型（Hugging Face 官方網址；可續傳；下載完比對官方 SHA256，不符就刪掉）。
--   3. 換模型：選好的模型記在 script-opts/kandong_settings.conf 的 model_path；
--      引擎由啟動器（mac/kandong.sh、Windows 的 scripts/launch.ps1）負責開關，
--      這支只寫一個「請換模型」的要求檔，啟動器換好後寫回狀態檔。
--      不是用「看懂」啟動器開的播放器沒有人接要求 → 只記住選擇，下次用「看懂」開就生效。
--   4. 改連其他翻譯伺服器（Ollama、LM Studio、區網另一台）：先實際翻一句測試，成功才寫進
--      floattranslate.conf，並通知翻譯腳本立刻改用。
--
-- 與啟動器之間的檔案（都在 control_dir，啟動器用 script-opts 帶進來）：
--   engine-request.txt  這支寫、啟動器讀完就刪：id=… action=switch|stop|asr model=…
--   engine-status.txt   啟動器寫：id=（最後處理的要求）state=ready|loading|failed|none|external|remote|stopped
--                       model=（目前載入的模型檔）error=（白話錯誤訊息）

local mp = require "mp"
local utils = require "mp.utils"
local msg = require "mp.msg"
local options = require "mp.options"

local o = {
    models_dir = "",   -- 啟動器帶進來；Windows 沒帶時用 mpv.exe 旁的 models
    control_dir = "",  -- 啟動器帶進來；Windows 沒帶時用 mpv.exe 旁的 logs
    model_path = "",   -- 使用者選的翻譯模型（空白＝依記憶體自動選）
    engine_port = 8080, -- 本機翻譯引擎的埠（啟動器帶進來）
    catalog_file = "", -- 測試用：用另一份 JSON 取代內建模型清單
}
options.read_options(o, "kandong_settings")

local DEFAULT_ENDPOINT = ("http://127.0.0.1:%d/v1/chat/completions"):format(o.engine_port)
local DEFAULT_MODEL = "tencent/Hy-MT2-7B-GGUF"
local MENU_TYPE = "kandong_settings"
local SELF = mp.get_script_name()

-- MODELS-BEGIN（要跟 mac/download-models.sh、packaging/windows/scripts/download-models.ps1、
-- packaging/models-README.txt 一致；tests/check_catalog.py 會比對）
local CATALOG = {
    { file = "Hy-MT2-7B-Q4_K_M.gguf", kind = "translate", label = "Hy-MT2 7B（標準）",
      note = "翻得比較好，建議記憶體 16GB 以上",
      url = "https://huggingface.co/tencent/Hy-MT2-7B-GGUF/resolve/main/Hy-MT2-7B-Q4_K_M.gguf",
      sha = "9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b", size = 4624648896 },
    { file = "Hy-MT2-1.8B-Q4_K_M.gguf", kind = "translate", label = "Hy-MT2 1.8B（輕量）",
      note = "快很多，記憶體 8GB 或電腦較舊選這個",
      url = "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/main/Hy-MT2-1.8B-Q4_K_M.gguf",
      sha = "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699", size = 1133080448 },
    { file = "ggml-large-v3-turbo-q5_0.bin", kind = "asr", label = "語音辨識模型（Whisper）",
      note = "只有看「沒字幕的影片」才需要",
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
      sha = "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", size = 574041195 },
}
-- MODELS-END

local platform = mp.get_property("platform")
    or (package.config:sub(1, 1) == "\\" and "windows" or "darwin")
local is_windows = platform == "windows"

-- ===== 小工具 =====

local function osd(text, dur)
    mp.osd_message("看懂：" .. text, dur or 4)
    msg.info(text) -- 畫面訊息不會進 mpv 的記錄檔，另外記一筆方便查問題
end

local function join(a, b) return utils.join_path(a, b) end

local function file_size(path)
    local info = path and path ~= "" and utils.file_info(path)
    if info and info.is_file then return info.size end
    return nil
end

local function dir_exists(path)
    local info = path and path ~= "" and utils.file_info(path)
    return info and info.is_dir or false
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

local function expand(p) return mp.command_native({ "expand-path", p }) end

local function basename(p) return (p:gsub("[/\\]+$", ""):match("([^/\\]+)$")) or p end

local function norm_path(p)
    if not p then return "" end
    local s = p:gsub("\\", "/"):gsub("/+$", "")
    if is_windows then s = s:lower() end
    return s
end

local function same_path(a, b) return a and b and a ~= "" and norm_path(a) == norm_path(b) end

local function fmt_size(bytes)
    if not bytes then return "" end
    if bytes >= 1e9 then return ("%.1f GB"):format(bytes / 1e9) end
    return ("%d MB"):format(math.floor(bytes / 1e6 + 0.5))
end

local function clean_line(s) return (tostring(s or ""):gsub("[\r\n]", " ")) end

-- 截前 n 個 byte，但不切在中文字中間
local function utf8_head(s, n)
    if #s <= n then return s end
    local cut = n
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut) .. "…"
end

local function strip_quotes(s)
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
    return s
end

if o.models_dir == "" and is_windows then o.models_dir = expand("~~exe_dir/models") end
if o.control_dir == "" and is_windows then o.control_dir = expand("~~exe_dir/logs") end

if o.catalog_file ~= "" then
    local data = read_file(o.catalog_file)
    local ok, parsed = pcall(utils.parse_json, data or "")
    if ok and type(parsed) == "table" then CATALOG = parsed end
end

local function catalog_by_file(name)
    for _, e in ipairs(CATALOG) do
        if name and e.file:lower() == name:lower() then return e end
    end
    return nil
end

local function model_label(path)
    if not path or path == "" then return "（未知）" end
    local e = catalog_by_file(basename(path))
    if e then return e.label end
    return (basename(path):gsub("%.[Gg][Gg][Uu][Ff]$", ""))
end

-- ===== 設定檔（script-opts/*.conf，key=value）=====

local function conf_path(name) return expand("~~/script-opts/" .. name) end

local function conf_read(name)
    local out = {}
    local data = read_file(conf_path(name)) or ""
    for line in data:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_%-]+)=(.*)$")
        if k then out[k] = v end -- 同一個 key 出現多次時後面的算數（與 mpv、啟動器一致）
    end
    return out
end

-- updates：{ {key, value}, ... }；同 key 每一行都改掉，沒有就加在檔尾；其他行原樣保留
local function conf_write(name, updates)
    local path = conf_path(name)
    local data = read_file(path) or ""
    local eol = data:find("\r\n", 1, true) and "\r\n" or "\n"
    local lines = {}
    for line in data:gmatch("([^\n]*)\n?") do
        lines[#lines + 1] = (line:gsub("\r$", ""))
    end
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
    for _, kv in ipairs(updates) do
        local key, value = kv[1], clean_line(kv[2])
        local found = false
        for i, line in ipairs(lines) do
            if line:sub(1, #key + 1) == key .. "=" then
                lines[i] = key .. "=" .. value
                found = true
            end
        end
        if not found then lines[#lines + 1] = key .. "=" .. value end
    end
    if not write_file(path, table.concat(lines, eol) .. eol) then
        osd("寫不進設定檔：" .. path, 6)
        return false
    end
    return true
end

local function current_server()
    local c = conf_read("floattranslate.conf")
    return {
        endpoint = (c.endpoint and c.endpoint ~= "") and c.endpoint or DEFAULT_ENDPOINT,
        model = (c.model and c.model ~= "") and c.model or DEFAULT_MODEL,
        api_key = c.api_key or "",
    }
end

local function is_local_endpoint(endpoint)
    local port = tostring(o.engine_port)
    return endpoint:match("^https?://127%.0%.0%.1:" .. port .. "/") ~= nil
        or endpoint:match("^https?://localhost:" .. port .. "/") ~= nil
end

local function host_of(url) return url:match("^%a+://([^/]+)") or url end

-- ===== 與啟動器溝通 =====

local function control_file(name)
    if o.control_dir == "" then return nil end
    return join(o.control_dir, name)
end

local function read_status()
    local path = control_file("engine-status.txt")
    local data = path and read_file(path)
    if not data then return nil end
    local st = {}
    for line in data:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then st[k] = v end
    end
    if not st.state then return nil end
    return st
end

local req_seq = 0
local function send_request(action, model)
    local path = control_file("engine-request.txt")
    if not path or not dir_exists(o.control_dir) then return nil end
    req_seq = req_seq + 1
    local id = ("%d-%d"):format(os.time(), req_seq)
    local body = "id=" .. id .. "\naction=" .. action .. "\nmodel=" .. clean_line(model) .. "\n"
    -- 先寫暫存檔再改名：啟動器不會讀到寫一半的要求
    local tmp = path .. ".tmp"
    if not write_file(tmp, body) then return nil end
    os.remove(path)
    if not os.rename(tmp, path) then
        os.remove(tmp)
        return nil
    end
    return id
end

local function tell_translator(...)
    mp.commandv("script-message-to", "floattranslate", ...)
end

-- ===== 找模型 =====

local function home_dir() return os.getenv("HOME") or os.getenv("USERPROFILE") or "" end

local function scan_dir(dir, depth, origin, out, seen)
    if not dir_exists(dir) then return end
    for _, f in ipairs(utils.readdir(dir, "files") or {}) do
        local lower = f:lower()
        if lower:match("%.gguf$") and not lower:find("mmproj", 1, true) then
            local p = join(dir, f)
            if not seen[norm_path(p)] then
                seen[norm_path(p)] = true
                out[#out + 1] = { path = p, name = f, size = file_size(p), origin = origin }
            end
        end
    end
    if depth > 0 then
        for _, d in ipairs(utils.readdir(dir, "dirs") or {}) do
            if d:sub(1, 1) ~= "." then scan_dir(join(dir, d), depth - 1, origin, out, seen) end
        end
    end
end

local function find_models()
    local out, seen = {}, {}
    if o.models_dir ~= "" then scan_dir(o.models_dir, 1, "models", out, seen) end
    local home = home_dir()
    if home ~= "" then
        scan_dir(join(home, ".cache/kandong/models"), 0, "cache", out, seen)
        scan_dir(join(home, ".lmstudio/models"), 3, "lmstudio", out, seen)
        scan_dir(join(home, ".cache/lm-studio/models"), 3, "lmstudio", out, seen)
    end
    -- 使用者用「其他位置的模型檔」選的、不在上面資料夾的那一個
    local chosen = o.model_path
    if chosen ~= "" and file_size(chosen) and not seen[norm_path(chosen)] then
        out[#out + 1] = { path = chosen, name = basename(chosen), size = file_size(chosen), origin = "custom" }
    end
    -- 內建清單的模型排前面（7B、1.8B），其他照檔名
    local rank = {}
    for i, e in ipairs(CATALOG) do rank[e.file:lower()] = i end
    table.sort(out, function(a, b)
        local ra, rb = rank[a.name:lower()] or 99, rank[b.name:lower()] or 99
        if ra ~= rb then return ra < rb end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- ===== 選單 =====

local menu_open = false
local dl = nil          -- 進行中的下載
local switching = nil   -- 進行中的換模型
local build_menu        -- 前向宣告

local function act(...) return { "script-message-to", SELF, "ks-action", ... } end

local function have_uosc()
    return dir_exists(expand("~~/scripts/uosc"))
end

local function open_or_update(data, update)
    if have_uosc() then
        mp.commandv("script-message-to", "uosc", update and "update-menu" or "open-menu", utils.format_json(data))
        menu_open = true
        return
    end
    if update then return end
    -- 沒有 uosc（例如自己裝的 mpv、IINA）：退回 mpv 內建的文字選單
    local ok, input = pcall(require, "mp.input")
    if not ok or not input.select then
        osd("這個選單需要看懂內附的介面（uosc）", 5)
        return
    end
    local flat, labels = {}, {}
    local function walk(items, prefix)
        for _, it in ipairs(items) do
            if it.items then
                walk(it.items, prefix .. it.title .. " › ")
            elseif it.value and it.selectable ~= false then
                flat[#flat + 1] = it.value
                labels[#labels + 1] = prefix .. it.title .. ((it.hint and it.hint ~= "") and ("（" .. it.hint .. "）") or "")
            end
        end
    end
    walk(data.items, "")
    input.select({
        prompt = data.title .. "：",
        items = labels,
        submit = function(i)
            local up = table.unpack or unpack
            if flat[i] then mp.commandv(up(flat[i])) end
        end,
    })
end

local function refresh_menu()
    if menu_open and have_uosc() then open_or_update(build_menu(), true) end
end

local function status_line(st, server)
    if not is_local_endpoint(server.endpoint) then
        return ("外部伺服器 %s（模型 %s）"):format(host_of(server.endpoint), server.model)
    end
    if switching then return "換模型中：" .. model_label(switching.target) .. "…" end
    if not st then
        return "這台電腦（不是用「看懂」開的，看不到目前用哪個模型）"
    end
    if st.state == "ready" then return "這台電腦：" .. model_label(st.model) end
    if st.state == "loading" then return "載入中：" .. model_label(st.model) .. "…" end
    if st.state == "none" then return "還沒有翻譯模型——請先在下面下載一個" end
    if st.state == "external" then return "這台電腦 8080 埠上別的翻譯服務（不是看懂開的）" end
    if st.state == "failed" then return "翻譯引擎沒有開起來：" .. (st.error or "") end
    if st.state == "stopped" then return "這台電腦的翻譯引擎已關閉" end
    return "這台電腦"
end

local function download_hint(e)
    local dest = o.models_dir ~= "" and join(o.models_dir, e.file)
    if dl and dl.entry.file == e.file then
        if dl.phase == "verify" then return "檢查檔案中…" end
        local got = file_size(dl.part) or 0
        local pct = math.floor(got * 100 / e.size)
        local speed = dl.rate and dl.rate > 0 and (" · %.1f MB/s"):format(dl.rate / 1e6) or ""
        return ("下載中 %d%%%s"):format(pct, speed)
    end
    local part = dest and file_size(dest .. ".part")
    if part and part > 0 then
        return ("上次下到 %d%%，點一下接著下載"):format(math.floor(part * 100 / e.size))
    end
    return fmt_size(e.size)
end

build_menu = function()
    local st = read_status()
    local server = current_server()
    local local_mode = is_local_endpoint(server.endpoint)
    local items = {}
    local function add(t) items[#items + 1] = t end

    add({ title = "目前：" .. status_line(st, server), selectable = false, muted = true, separator = true })

    -- 這台電腦的模型
    add({ title = "這台電腦的翻譯模型", selectable = false, bold = true })
    local found = find_models()
    local in_use = local_mode and st and st.state == "ready" and st.model or nil
    for _, m in ipairs(found) do
        local e = catalog_by_file(m.name)
        local hint = fmt_size(m.size)
        if same_path(m.path, in_use) then
            hint = "使用中 · " .. hint
        elseif not e then
            hint = hint .. " · 自己加的"
        end
        add({ title = model_label(m.path), hint = hint, active = same_path(m.path, in_use) or nil,
              value = act("switch", m.path) })
    end
    if #found == 0 then
        add({ title = "（還沒有，請先下載下面的模型）", selectable = false, muted = true })
    end
    items[#items].separator = true

    -- 下載
    add({ title = "下載模型（Hugging Face 官方，會檢查檔案是否完整）", selectable = false, bold = true })
    local any_dl = false
    for _, e in ipairs(CATALOG) do
        local dest = o.models_dir ~= "" and join(o.models_dir, e.file)
        if not (dest and file_size(dest)) then
            any_dl = true
            add({ title = "下載 " .. e.label, hint = download_hint(e), keep_open = true,
                  value = act("download", e.file) })
        end
    end
    if dl then
        add({ title = "停止下載", hint = "下次會從中斷的地方接著下載", keep_open = true, value = act("cancel-download") })
    end
    if not any_dl then
        add({ title = "內建的模型都已經下載好了", selectable = false, muted = true })
    end
    items[#items].separator = true

    -- 其他
    add({ title = "開啟模型資料夾", hint = "把 .gguf 檔放進去，重開這個選單就會出現", value = act("open-folder") })
    add({ title = "使用其他位置的模型檔…", hint = "貼上 .gguf 檔的完整路徑", value = act("custom-path") })
    local server_items = {
        { title = "Ollama（這台電腦）", hint = "127.0.0.1:11434", value = act("server-preset", "http://127.0.0.1:11434/v1/chat/completions") },
        { title = "LM Studio（這台電腦）", hint = "127.0.0.1:1234", value = act("server-preset", "http://127.0.0.1:1234/v1/chat/completions") },
        { title = "自己輸入網址…", hint = "區網另一台電腦、其他 OpenAI 相容服務", value = act("server-custom") },
    }
    if not local_mode then
        server_items[#server_items + 1] = { title = "改回這台電腦內建的翻譯模型", value = act("server-local") }
    end
    add({ title = "連到其他翻譯伺服器", hint = local_mode and "" or ("使用中：" .. host_of(server.endpoint)),
          items = server_items })

    return {
        type = MENU_TYPE,
        title = "翻譯模型與伺服器",
        items = items,
        footnote = "自己加的模型不一定翻得好：看懂的翻譯指令是為 Hy-MT2 調的。",
        on_close = { "script-message-to", SELF, "ks-action", "menu-closed" },
    }
end

local function open_menu()
    open_or_update(build_menu(), false)
end

-- ===== 換模型 =====

local poll_timer = nil
local function stop_poll() if poll_timer then poll_timer:kill(); poll_timer = nil end end

local function finish_switch(text, dur)
    switching = nil
    stop_poll()
    tell_translator("ft-engine-ready")
    if text then osd(text, dur or 5) end
    refresh_menu()
end

local function poll_switch()
    if not switching then return stop_poll() end
    local s = switching
    local elapsed = mp.get_time() - s.t0
    local req = control_file("engine-request.txt")
    if req and file_size(req) and elapsed > 5 then
        -- 啟動器沒有在接要求（播放器不是用「看懂」開的）
        os.remove(req)
        return finish_switch("已記住你的選擇：下次用「看懂」開啟時會改用 " .. model_label(s.target), 6)
    end
    local st = read_status()
    if st and st.id == s.id then
        if st.state == "ready" and same_path(st.model, s.target) then
            return finish_switch("已換成 " .. model_label(s.target) .. "，繼續翻譯", 4)
        elseif st.state == "ready" then
            -- 新模型開不起來，啟動器已換回原本的
            conf_write("kandong_settings.conf", { { "model_path", st.model } })
            o.model_path = st.model
            return finish_switch("換不成 " .. model_label(s.target) .. "：" .. (st.error or "")
                .. "；已換回 " .. model_label(st.model), 8)
        elseif st.state ~= "loading" then
            return finish_switch("換模型失敗：" .. (st.error ~= "" and st.error or st.state), 8)
        end
    end
    if elapsed > 300 then
        return finish_switch("換模型等太久（超過 5 分鐘），請看 logs 資料夾裡的 translate-engine.log", 8)
    end
    if math.floor(elapsed) % 5 == 0 and math.floor(elapsed) ~= s.last_note then
        s.last_note = math.floor(elapsed)
        osd(("正在換成 %s…（%d 秒；大模型第一次載入要 10–60 秒，期間暫停翻譯）"):format(
            model_label(s.target), math.floor(elapsed)), 3)
    end
end

local function server_set(endpoint, model, api_key)
    conf_write("floattranslate.conf", { { "endpoint", endpoint }, { "model", model }, { "api_key", api_key } })
    tell_translator("ft-server-changed", endpoint, model, api_key)
end

local function switch_model(path)
    if switching then return osd("上一個換模型還在進行中，請稍等", 3) end
    if not file_size(path) then return osd("找不到這個模型檔：" .. path, 5) end
    local was_remote = not is_local_endpoint(current_server().endpoint)
    if was_remote then
        server_set(DEFAULT_ENDPOINT, DEFAULT_MODEL, "")
    end
    conf_write("kandong_settings.conf", { { "model_path", path } })
    o.model_path = path
    local st = read_status()
    if not st then
        return osd("已記住你的選擇：下次用「看懂」開啟時會改用 " .. model_label(path), 6)
    end
    if st.state == "external" then
        return osd("8080 埠上的翻譯服務不是看懂開的，這裡沒辦法替它換模型（選擇已記住）", 7)
    end
    if st.state == "ready" and same_path(st.model, path) then
        refresh_menu()
        return osd((was_remote and "已改回這台電腦：" or "已經在用 ") .. model_label(path), 4)
    end
    local id = send_request("switch", path)
    if not id then return osd("寫不進 logs 資料夾，沒辦法換模型", 5) end
    tell_translator("ft-engine-pause")
    switching = { id = id, target = path, t0 = mp.get_time() }
    osd("正在換成 " .. model_label(path) .. "…（期間暫停翻譯）", 4)
    stop_poll()
    poll_timer = mp.add_periodic_timer(0.5, poll_switch)
    refresh_menu()
end

-- ===== 下載 =====

local dl_timer = nil

local function hash_args(path)
    if is_windows then return { "certutil", "-hashfile", path, "SHA256" } end
    return { "shasum", "-a", "256", path }
end

local function parse_hash(out)
    for line in (out or ""):gmatch("[^\r\n]+") do
        local compact = line:gsub("%s", ""):lower()
        local hex = compact:match("^(%x+)") or ""
        if #hex == 64 then return hex end
    end
    return nil
end

local function dl_done(text, dur)
    if dl_timer then dl_timer:kill(); dl_timer = nil end
    dl = nil
    if text then osd(text, dur or 6) end
    refresh_menu()
end

local function after_download(e, dest)
    if e.kind == "asr" then
        local st = read_status()
        if st then send_request("asr", dest) end
        return dl_done("語音辨識模型下載完成。重新開啟沒字幕的影片就會用到", 7)
    end
    local st = read_status()
    local server = current_server()
    if st and is_local_endpoint(server.endpoint)
        and (st.state == "none" or st.state == "failed" or st.state == "stopped") then
        dl_done(nil)
        osd("下載完成：" .. e.label .. "，馬上開始使用", 4)
        return switch_model(dest)
    end
    dl_done("下載完成：" .. e.label .. "。要換成它就在這個選單點它一下", 7)
end

local function verify(e, part, dest)
    dl.phase = "verify"
    osd("下載完成，檢查檔案是否完整（大檔要等一下）…", 5)
    refresh_menu()
    dl.id = mp.command_native_async({
        name = "subprocess", args = hash_args(part),
        capture_stdout = true, capture_stderr = true, playback_only = false,
    }, function(success, res)
        if not dl then return end
        if not success or not res or res.status ~= 0 then
            if res and res.killed_by_us then return end
            return dl_done("沒辦法檢查檔案（" .. tostring(res and res.stderr or "") .. "）", 6)
        end
        local got = parse_hash(res.stdout)
        if got ~= e.sha:lower() then
            os.remove(part)
            return dl_done("檔案檢查不符（可能下載不完整），已刪除，請再下載一次", 7)
        end
        os.remove(dest)
        local ok, err = os.rename(part, dest)
        if not ok then return dl_done("檔案改名失敗：" .. tostring(err), 6) end
        after_download(e, dest)
    end)
end

local function start_download(file)
    local e = catalog_by_file(file)
    if not e then return end
    if dl then return osd("正在下載 " .. dl.entry.label .. "，一次下載一個", 3) end
    if o.models_dir == "" or not dir_exists(o.models_dir) then
        return osd("找不到模型資料夾（請用「看懂」啟動，或在 kandong_settings.conf 設 models_dir）", 6)
    end
    local dest = join(o.models_dir, e.file)
    if file_size(dest) then return osd("已經有 " .. e.label, 3) end
    local part = dest .. ".part"
    dl = { entry = e, part = part, dest = dest, phase = "download", t0 = mp.get_time(),
           last_size = file_size(part) or 0, last_t = mp.get_time(), last_pct_note = -1 }
    osd("開始下載 " .. e.label .. "（" .. fmt_size(e.size) .. "；可以繼續看片，進度在這個選單）", 5)
    dl.id = mp.command_native_async({
        name = "subprocess",
        args = { "curl", "-L", "--fail", "-sS", "--retry", "5", "--retry-delay", "3", "-C", "-", "-o", part, e.url },
        capture_stdout = true, capture_stderr = true, playback_only = false,
    }, function(success, res)
        if not dl or dl.entry ~= e then return end
        if res and res.killed_by_us then return end
        local got = file_size(part) or 0
        if (not success or not res or res.status ~= 0) and got ~= e.size then
            local err = tostring(res and res.stderr or ""):gsub("%s+$", ""):sub(1, 120)
            return dl_done("下載失敗（" .. err .. "）。網路或磁碟空間有問題時會這樣，修好後再點一次就會接著下載", 8)
        end
        verify(e, part, dest)
    end)
    dl_timer = mp.add_periodic_timer(1, function()
        if not dl or dl.phase ~= "download" then return end
        local now, size = mp.get_time(), file_size(dl.part) or 0
        local dt = now - dl.last_t
        if dt >= 2 then
            dl.rate = (size - dl.last_size) / dt
            dl.last_size, dl.last_t = size, now
        end
        local pct = math.floor(size * 100 / e.size)
        if pct >= dl.last_pct_note + 10 then
            dl.last_pct_note = pct - pct % 10
            osd(("下載 %s：%d%%"):format(e.label, pct), 2)
        end
        refresh_menu()
    end)
    refresh_menu()
end

local function cancel_download()
    if not dl then return end
    if dl.id then mp.abort_async_command(dl.id) end
    dl_done("已停止下載。下次點同一個模型會從中斷的地方接著下載", 5)
end

-- ===== 其他翻譯伺服器 =====

local pending = nil -- { endpoint, api_key }

local function normalize_endpoint(text)
    local s = strip_quotes(text):gsub("/+$", "")
    if s == "" then return nil end
    if not s:match("^%a+://") then s = "http://" .. s end
    if s:match("/chat/completions$") then return s end
    if s:match("/v1$") then return s .. "/chat/completions" end
    return s .. "/v1/chat/completions"
end

local function models_url(endpoint) return (endpoint:gsub("/chat/completions$", "/models")) end

local function curl_json(args, callback)
    mp.command_native_async({
        name = "subprocess", args = args,
        capture_stdout = true, capture_stderr = true, playback_only = false,
    }, function(success, res)
        if not success or not res or res.status ~= 0 then
            return callback(nil, tostring(res and res.stderr or "連不上"):gsub("%s+$", ""):sub(1, 120))
        end
        local ok, parsed = pcall(utils.parse_json, res.stdout or "")
        if not ok or type(parsed) ~= "table" then
            return callback(nil, "回應不是 JSON：" .. tostring(res.stdout):sub(1, 80))
        end
        callback(parsed, nil)
    end)
end

local function auth_args(args, key)
    if key and key ~= "" then
        args[#args + 1] = "-H"
        args[#args + 1] = "Authorization: Bearer " .. key
    end
    return args
end

local function test_and_save(endpoint, model, key)
    osd("測試翻譯中（" .. host_of(endpoint) .. "，模型 " .. model .. "）…", 30)
    local body = utils.format_json({
        model = model,
        messages = { { role = "user", content =
            "Translate the following segment into Traditional Chinese, without additional explanation.\n\nGood morning." } },
        max_tokens = 64, temperature = 0.2,
    })
    local tmp = join(os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp", "kandong-server-test.json")
    if not write_file(tmp, body) then return osd("寫不進暫存檔，無法測試", 5) end
    local args = auth_args({ "curl", "-sS", "--max-time", "120", "-X", "POST", endpoint,
        "-H", "Content-Type: application/json" }, key)
    args[#args + 1] = "--data-binary"
    args[#args + 1] = "@" .. tmp
    curl_json(args, function(parsed, err)
        os.remove(tmp)
        local content = parsed and parsed.choices and parsed.choices[1] and parsed.choices[1].message
            and parsed.choices[1].message.content
        if parsed and parsed.error then
            err = type(parsed.error) == "table" and tostring(parsed.error.message) or tostring(parsed.error)
        end
        if type(content) ~= "string" or content:gsub("%s", "") == "" then
            return osd("連線測試失敗，設定沒有改：" .. tostring(err or "沒有拿到譯文"), 8)
        end
        server_set(endpoint, model, key)
        local st = read_status()
        if st and st.state == "ready" then send_request("stop", "") end -- 不用本機模型了，把記憶體還給電腦
        osd(("已改用 %s（模型 %s）。測試翻譯：Good morning. → %s"):format(
            host_of(endpoint), model, utf8_head((content:gsub("%s+", " ")), 90)), 7)
        refresh_menu()
    end)
end

local function ask_text(prompt, default, cb)
    local ok, input = pcall(require, "mp.input")
    if not ok or not input.get then return osd("這個 mpv 版本不支援輸入框，請改用 mpv 0.39 以上", 5) end
    input.get({
        prompt = prompt,
        default_text = default or "",
        submit = function(text)
            input.terminate()
            cb(text)
        end,
    })
end

local function pick_model(endpoint, key)
    osd("向伺服器查詢有哪些模型…", 10)
    curl_json(auth_args({ "curl", "-sS", "--max-time", "8", models_url(endpoint) }, key), function(parsed, err)
        local ids = {}
        if parsed and type(parsed.data) == "table" then
            for _, m in ipairs(parsed.data) do
                if type(m) == "table" and type(m.id) == "string" then ids[#ids + 1] = m.id end
            end
        end
        mp.osd_message("")
        if #ids == 0 then
            if err then osd("查不到模型清單（" .. err .. "），請自己輸入模型名稱", 5) end
            return ask_text("模型名稱（例如 qwen2.5:7b）：", "", function(name)
                name = strip_quotes(name)
                if name ~= "" then test_and_save(endpoint, name, key) end
            end)
        end
        pending = { endpoint = endpoint, api_key = key }
        local items = {}
        for _, id in ipairs(ids) do items[#items + 1] = { title = id, value = act("server-model", id) } end
        open_or_update({ type = MENU_TYPE .. "_models", title = "選要用來翻譯的模型（" .. host_of(endpoint) .. "）",
                         items = items }, false)
    end)
end

-- ===== 指令 =====

local actions = {}

actions["switch"] = function(path) switch_model(path) end
actions["download"] = function(file) start_download(file) end
actions["cancel-download"] = function() cancel_download() end
actions["menu-closed"] = function() menu_open = false end

actions["open-folder"] = function()
    if o.models_dir == "" then return osd("找不到模型資料夾", 4) end
    local args = is_windows and { "explorer", o.models_dir }
        or (platform == "darwin" and { "open", o.models_dir } or { "xdg-open", o.models_dir })
    mp.command_native_async({ name = "subprocess", args = args, playback_only = false, detach = true }, function() end)
end

actions["custom-path"] = function()
    ask_text("貼上 .gguf 模型檔的完整路徑：", "", function(text)
        local p = strip_quotes(text)
        if p == "" then return end
        if not p:lower():match("%.gguf$") then return osd("要選副檔名是 .gguf 的模型檔", 5) end
        if not file_size(p) then return osd("找不到這個檔案：" .. p, 5) end
        osd("自己加的模型不一定翻得好（看懂的翻譯指令是為 Hy-MT2 調的）", 4)
        switch_model(p)
    end)
end

actions["server-preset"] = function(endpoint) pick_model(endpoint, "") end

actions["server-custom"] = function()
    local cur = current_server()
    local default = is_local_endpoint(cur.endpoint) and "" or cur.endpoint
    ask_text("翻譯伺服器網址（例如 http://192.168.1.20:8080）：", default, function(text)
        local endpoint = normalize_endpoint(text)
        if not endpoint then return end
        ask_text("API key（沒有就直接按 Enter）：", "", function(key)
            pick_model(endpoint, strip_quotes(key))
        end)
    end)
end

actions["server-model"] = function(id)
    if not pending then return end
    local p = pending
    pending = nil
    test_and_save(p.endpoint, id, p.api_key)
end

actions["server-local"] = function()
    local target = o.model_path ~= "" and file_size(o.model_path) and o.model_path or nil
    if not target then
        for _, m in ipairs(find_models()) do
            if catalog_by_file(m.name) then target = m.path; break end
        end
    end
    server_set(DEFAULT_ENDPOINT, DEFAULT_MODEL, "")
    if target then return switch_model(target) end
    osd("已改回這台電腦，但還沒有翻譯模型：請在這個選單下載一個", 6)
    refresh_menu()
end

mp.register_script_message("ks-action", function(name, ...)
    local fn = actions[name]
    if fn then fn(...) else msg.warn("unknown action " .. tostring(name)) end
end)

mp.add_key_binding(nil, "open-settings", open_menu)

-- 開檔時：還沒有模型就提示一次去哪裡下載；引擎沒開就先讓翻譯腳本別一直重試
local hinted = false
mp.register_event("file-loaded", function()
    local st = read_status()
    local server = current_server()
    if not st or not is_local_endpoint(server.endpoint) then return end
    if st.state == "none" or st.state == "failed" or st.state == "stopped" then
        tell_translator("ft-engine-pause")
        if not hinted then
            hinted = true
            mp.add_timeout(1.5, function()
                osd(st.state == "none" and "還沒有翻譯模型：按右鍵 → 設定 → 翻譯模型與伺服器，就能直接下載"
                    or "翻譯引擎沒有開：按右鍵 → 設定 → 翻譯模型與伺服器，選一個模型", 8)
            end)
        end
    end
end)

mp.register_event("shutdown", function()
    if dl and dl.id then mp.abort_async_command(dl.id) end
end)
