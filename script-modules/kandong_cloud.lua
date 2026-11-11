-- 看懂 KanDong：雲端翻譯 API（OpenAI／Claude／Gemini）與金鑰存放的共用模組
--
-- scripts/floattranslate.lua（翻譯）與 scripts/kandong_settings.lua（設定選單）都用這一份，
-- 三家的網址、參數、錯誤訊息只寫在這裡，免得兩邊各改各的。
-- mpv 會把 ~~/script-modules 加進 Lua 的 package.path，所以用 require "kandong_cloud" 載入；
-- 放在 scripts/ 以外，mpv 才不會把它當成一支獨立腳本執行。
--
-- 金鑰：
--   Mac     → 鑰匙圈（security 指令；服務名「KanDong API key」，帳號＝openai／anthropic／google／custom）
--   Windows → %APPDATA%\KanDong\keys\<帳號>.dpapi（Windows DPAPI 加密，只有同一個 Windows 使用者解得開）
--   其他    → ~/.config/kandong/keys/<帳號>（權限 600）
--   都不放在看懂的資料夾裡：整個資料夾複製給別人時，金鑰不會跟著走。
--   交給 security／PowerShell／curl 時寫進「只有本人讀得到」的暫存檔、用完立刻刪：
--     - 不放命令列（ps 看得到命令列）；
--     - 也不走 subprocess 的 stdin_data——mpv 開除錯紀錄（--log-file）時會把每個指令連同 stdin 內容寫進紀錄檔。
--   設定選單讀金鑰也優先讀剪貼簿（讀屬性不會進紀錄檔）；在 mpv 輸入框打字的內容會進除錯紀錄，只當最後手段。

local mp = require "mp"
local utils = require "mp.utils"

local M = {}

M.SERVICE = "KanDong API key"

local platform = mp.get_property("platform")
    or (package.config:sub(1, 1) == "\\" and "windows" or "darwin")
M.platform = platform

-- ===== 三家 =====

local function bearer(key) return { "Authorization: Bearer " .. key } end

M.PROVIDERS = {
    openai = {
        label = "OpenAI",
        endpoint = "https://api.openai.com/v1/chat/completions",
        models_url = "https://api.openai.com/v1/models",
        console = "platform.openai.com",
        auth = bearer,
        -- 依序試：不思考最快；舊模型不認得 none 就退一步
        efforts = { "none", "minimal", "low", "" },
        max_tokens = 1024,
        keep = function(id) return id:match("^gpt%-") or id:match("^o%d") end,
        drop = { "image", "audio", "realtime", "tts", "transcribe", "search", "embed",
                 "moderation", "cyber", "live", "codex", "instruct", "computer" },
        -- 推薦順序只用來排序與標「推薦」，不決定哪些能選（清單一律向 OpenAI 即時查）
        rank = { { "luna", 1 }, { "nano", 2 }, { "mini", 2 }, { "terra", 3 }, { "sol", 4 } },
    },
    anthropic = {
        label = "Claude",
        endpoint = "https://api.anthropic.com/v1/messages",
        models_url = "https://api.anthropic.com/v1/models?limit=100",
        console = "console.anthropic.com",
        auth = function(key) return { "x-api-key: " .. key } end,
        extra_headers = { "anthropic-version: 2023-06-01" },
        efforts = { "low", "" },
        max_tokens = 2048,
        keep = function(id) return id:match("^claude%-") end,
        drop = {},
        rank = { { "haiku", 1 }, { "sonnet", 2 }, { "opus", 3 } },
    },
    google = {
        label = "Gemini",
        endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        models_url = "https://generativelanguage.googleapis.com/v1beta/openai/models",
        console = "aistudio.google.com",
        auth = bearer,
        efforts = { "none", "minimal", "low", "" },
        max_tokens = 2048,
        keep = function(id) return id:match("gemini") end,
        drop = { "embed", "image", "tts", "audio", "live", "robotics", "computer", "aqa", "omni" },
        rank = { { "flash%-lite", 2 }, { "flash", 1 } },
    },
}

function M.provider(name) return name and M.PROVIDERS[name] or nil end

-- ===== 只有本人讀得到的暫存檔 =====

local seq = 0
local function private_dir()
    if platform == "darwin" then return os.getenv("TMPDIR") end -- 每個使用者一個、權限 700
    if platform == "windows" then return os.getenv("TEMP") end  -- %LOCALAPPDATA%\Temp，只有本人
    local d = os.getenv("XDG_RUNTIME_DIR")                       -- Linux：每個使用者一個、權限 700
    return d ~= "" and d or nil
end

-- 寫入私人暫存檔，回傳路徑（寫不了回 nil；呼叫的人負責 os.remove）
local function write_private(data)
    local dir = private_dir()
    if not dir or dir == "" then return nil end
    seq = seq + 1
    local pid = utils.getpid and utils.getpid() or 0
    local path = utils.join_path(dir, ("kandong-%d-%d-%d.tmp"):format(pid, seq, math.random(1, 1e9)))
    local f = io.open(path, "wb")
    if not f then return nil end
    f:write(data)
    f:close()
    return path
end

-- ===== curl（網址、標頭、內容都寫進私人暫存檔用 -K 讀：金鑰不上命令列、不進 mpv 紀錄）=====

local function cfg_quote(s)
    return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- spec = { url=, headers={...}, body=table 或 nil, timeout=秒 }
-- cb(http_code 或 nil, parsed JSON 或 nil, curl 錯誤字串 或 nil)
function M.request(spec, cb)
    local lines = { "url = " .. cfg_quote(spec.url) }
    for _, h in ipairs(spec.headers or {}) do
        lines[#lines + 1] = "header = " .. cfg_quote(h)
    end
    if spec.body then
        local ok, encoded = pcall(utils.format_json, spec.body)
        if not ok or not encoded then return cb(nil, nil, "request JSON encode failed") end
        lines[#lines + 1] = "header = " .. cfg_quote("Content-Type: application/json")
        lines[#lines + 1] = "data-binary = " .. cfg_quote(encoded)
    end
    local cfg = write_private(table.concat(lines, "\n") .. "\n")
    if not cfg then return cb(nil, nil, "寫不了暫存檔") end
    mp.command_native_async({
        name = "subprocess",
        args = { "curl", "-sS", "--max-time", tostring(spec.timeout or 30), "-K", cfg,
                 "-w", "\n%{http_code}" },
        capture_stdout = true, capture_stderr = true, playback_only = false,
    }, function(success, res)
        os.remove(cfg)
        if not success or not res or res.status ~= 0 then
            local err = tostring(res and res.stderr or "subprocess failed"):gsub("%s+$", "")
            return cb(nil, nil, err:sub(1, 160))
        end
        local out = res.stdout or ""
        local body, code = out:match("^(.*)\n(%d%d%d)%s*$")
        if not code then return cb(nil, nil, "no HTTP status") end
        local pok, parsed = pcall(utils.parse_json, body)
        cb(tonumber(code), (pok and type(parsed) == "table") and parsed or nil, nil)
    end)
end

-- ===== 一句翻譯 =====

-- 回傳 curl 用的 spec（含金鑰標頭）
function M.chat_spec(pname, key, model, prompt, effort, timeout)
    local p = M.PROVIDERS[pname]
    local headers = {}
    for _, h in ipairs(p.auth(key)) do headers[#headers + 1] = h end
    for _, h in ipairs(p.extra_headers or {}) do headers[#headers + 1] = h end
    local body = { model = model, messages = { { role = "user", content = prompt } } }
    if pname == "anthropic" then
        -- 新一代 Claude 不接受 temperature（送了整個請求 400），所以不送
        body.max_tokens = p.max_tokens
        if effort and effort ~= "" then body.output_config = { effort = effort } end
    elseif pname == "openai" then
        -- GPT-5 以後不接受 temperature 與 max_tokens
        body.max_completion_tokens = p.max_tokens
        if effort and effort ~= "" then body.reasoning_effort = effort end
    else
        body.max_tokens = p.max_tokens
        if effort and effort ~= "" then body.reasoning_effort = effort end
    end
    return { url = p.endpoint, headers = headers, body = body, timeout = timeout or 30 }
end

function M.chat_text(pname, parsed)
    if type(parsed) ~= "table" then return nil end
    if pname == "anthropic" then
        local parts = {}
        for _, b in ipairs(parsed.content or {}) do
            if type(b) == "table" and b.type == "text" and type(b.text) == "string" then
                parts[#parts + 1] = b.text
            end
        end
        local t = table.concat(parts, "\n")
        return t ~= "" and t or nil
    end
    local c = parsed.choices and parsed.choices[1] and parsed.choices[1].message
        and parsed.choices[1].message.content
    return type(c) == "string" and c or nil
end

local function error_text(parsed)
    if type(parsed) ~= "table" then return "" end
    local e = parsed.error
    if type(e) == "table" then return tostring(e.message or e.type or "") end
    if type(e) == "string" then return e end
    if type(parsed[1]) == "table" and type(parsed[1].error) == "table" then
        return tostring(parsed[1].error.message or "") -- Gemini 有時回陣列
    end
    return ""
end
M.error_text = error_text

-- 錯誤是不是在說「不認得思考程度這個參數」（換下一檔再試）
function M.effort_rejected(code, parsed)
    if code ~= 400 and code ~= 422 then return false end
    local t = error_text(parsed):lower()
    return t:match("reasoning") or t:match("effort") or t:match("output_config")
        or t:match("thinking") or false
end

-- 把錯誤翻成一般人看得懂的話；retry=true 表示稍後自動重試就好（限流、忙線）
function M.explain(pname, code, parsed, curl_err)
    local p = M.PROVIDERS[pname] or { label = "翻譯伺服器", console = "" }
    if not code then
        return ("連不上 %s（%s）。請檢查網路"):format(p.label, tostring(curl_err or "")), true
    end
    local t = error_text(parsed)
    local lt = t:lower()
    if lt:match("quota") or lt:match("billing") or lt:match("credit") or lt:match("insufficient")
        or lt:match("exceeded your current") then
        return ("%s 帳戶的額度用完了，請到 %s 加值或查看用量"):format(p.label, p.console), false
    end
    if code == 401 or code == 403 or lt:match("api key not valid") or lt:match("valid api key")
        or lt:match("invalid api key") or lt:match("incorrect api key") then
        return ("%s API 金鑰不對、已撤銷，或沒有使用這個模型的權限"):format(p.label), false
    end
    if code == 404 or lt:match("interactions api") or lt:match("not supported for") then
        return "找不到這個模型（可能已下架）：請到右鍵 → 設定 → 翻譯模型與伺服器重新選一個", false
    end
    if code == 429 then
        return ("%s 暫時限制請求次數，稍後會自動重試"):format(p.label), true
    end
    if code >= 500 then
        return ("%s 暫時忙線（%d），稍後會自動重試"):format(p.label, code), true
    end
    return ("%s 回覆錯誤（%d）：%s"):format(p.label, code, t:sub(1, 120)), false
end

-- ===== 模型清單 =====

local function rank_of(p, id)
    local r = 9
    for _, pr in ipairs(p.rank or {}) do
        if id:match(pr[1]) then r = pr[2]; break end
    end
    -- 預覽版與帶日期的固定版本（claude-haiku-4-5-20251001、gpt-…-2025-08-07）往後排
    if id:match("preview") or id:match("exp") or id:match("%d%d%d%d%-%d%d%-%d%d")
        or id:match("%-20%d%d%d%d%d%d$") then r = r + 5 end
    -- 會自己跳版本的別名（gemini-flash-latest）排在明確版本號後面，推薦看得出是哪一版的
    if id:match("latest") then r = r + 1 end
    return r
end

-- cb({ {id=, title=}... } 已排序（第一個＝推薦）, 錯誤訊息)
function M.list_models(pname, key, cb)
    local p = M.PROVIDERS[pname]
    local headers = {}
    for _, h in ipairs(p.auth(key)) do headers[#headers + 1] = h end
    for _, h in ipairs(p.extra_headers or {}) do headers[#headers + 1] = h end
    M.request({ url = p.models_url, headers = headers, timeout = 15 }, function(code, parsed, err)
        if code ~= 200 or type(parsed) ~= "table" or type(parsed.data) ~= "table" then
            local text = M.explain(pname, code, parsed, err)
            return cb(nil, text)
        end
        local list = {}
        for _, m in ipairs(parsed.data) do
            local id = type(m) == "table" and type(m.id) == "string" and m.id:gsub("^models/", "") or nil
            if id and p.keep(id) then
                local bad = false
                for _, d in ipairs(p.drop) do
                    if id:find(d, 1, true) then bad = true; break end
                end
                if not bad then
                    list[#list + 1] = { id = id, title = (type(m.display_name) == "string" and m.display_name ~= "")
                        and m.display_name or id, rank = rank_of(p, id) }
                end
            end
        end
        table.sort(list, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.id > b.id -- 版本號大的（較新）排前面
        end)
        cb(list, #list == 0 and ("%s 沒有回傳可用來翻譯的模型"):format(p.label) or nil)
    end)
end

-- ===== 金鑰存放 =====

-- 只接受常見金鑰字元，順便擋掉貼進來的空白、引號、換行
function M.valid_key(key)
    return type(key) == "string" and #key >= 8 and #key <= 400 and key:match("^[%w%-_%.~+/=:]+$") ~= nil
end

-- 剪貼簿裡的字看起來是不是這一家的金鑰（看開頭格式；Google 新格式是 AQ. 開頭）
function M.looks_like(pname, s)
    if not M.valid_key(s) then return false end
    if pname == "anthropic" then return s:match("^sk%-ant%-") ~= nil end
    if pname == "openai" then return s:match("^sk%-") ~= nil and not s:match("^sk%-ant%-") end
    if pname == "google" then return s:match("^AIza") ~= nil or s:match("^AQ%.") ~= nil end
    return false
end

-- 顯示用：只露最後 4 碼
function M.mask(s) return "…" .. tostring(s):sub(-4) end

local ACCOUNTS = { openai = true, anthropic = true, google = true, custom = true }

local function ps_args(script)
    return { "powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script }
end

local function home() return os.getenv("HOME") or "" end

local function run(args, cb)
    mp.command_native_async({
        name = "subprocess", args = args,
        capture_stdout = true, capture_stderr = true, playback_only = false,
    }, function(success, res)
        cb(success and res and res.status == 0, res and res.stdout or "", res and res.stderr or "")
    end)
end

-- cb(ok, 錯誤訊息)
function M.secret_store(account, key, cb)
    if not ACCOUNTS[account] then return cb(false, "unknown account") end
    if not M.valid_key(key) then return cb(false, "金鑰格式不對（含空白或特殊字元？請重新複製）") end
    if platform == "darwin" then
        -- security -i 從檔案讀指令：金鑰不出現在命令列。-U＝已存在就更新
        local tmp = write_private(('add-generic-password -U -s "%s" -a "%s" -l "KanDong %s" -w "%s"\n'):format(
            M.SERVICE, account, account, key))
        if not tmp then return cb(false, "寫不了暫存檔") end
        return run({ "sh", "-c", 'security -i < "$1"', "sh", tmp }, function()
            os.remove(tmp)
            -- security -i 失敗也回 0，以讀回來為準
            M.secret_read(account, function(got)
                if got == key then cb(true) else cb(false, "存不進鑰匙圈") end
            end)
        end)
    elseif platform == "windows" then
        local tmp = write_private(key)
        if not tmp then return cb(false, "寫不了暫存檔") end
        local script = "$t='" .. tmp:gsub("'", "''") .. "';"
            .. "$k=(Get-Content -Raw -Path $t).Trim(); Remove-Item -Force -Path $t;"
            .. "$d=Join-Path $env:APPDATA 'KanDong\\keys';"
            .. "New-Item -ItemType Directory -Force -Path $d | Out-Null;"
            .. "ConvertTo-SecureString $k -AsPlainText -Force | ConvertFrom-SecureString"
            .. " | Set-Content -Encoding ascii -Path (Join-Path $d '" .. account .. ".dpapi')"
        return run(ps_args(script), function(ok, _, err)
            os.remove(tmp)
            cb(ok, ok and nil or ("存不進 Windows 加密存放區：" .. err:sub(1, 120)))
        end)
    else
        local tmp = write_private(key)
        if not tmp then return cb(false, "寫不了暫存檔") end
        local dir = home() .. "/.config/kandong/keys"
        return run({ "sh", "-c", 'umask 077 && mkdir -p "$1" && cat "$3" > "$1/$2"', "sh", dir, account, tmp },
            function(ok, _, err)
                os.remove(tmp)
                cb(ok, ok and nil or err:sub(1, 120))
            end)
    end
end

-- cb(金鑰 或 nil)
function M.secret_read(account, cb)
    if not ACCOUNTS[account] then return cb(nil) end
    local args
    if platform == "darwin" then
        args = { "security", "find-generic-password", "-s", M.SERVICE, "-a", account, "-w" }
    elseif platform == "windows" then
        args = ps_args("$p=Join-Path $env:APPDATA 'KanDong\\keys\\" .. account .. ".dpapi';"
            .. "if(!(Test-Path $p)){exit 3};"
            .. "$s=Get-Content -Path $p | ConvertTo-SecureString;"
            .. "[Console]::Out.Write([Runtime.InteropServices.Marshal]::PtrToStringBSTR("
            .. "[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)))")
    else
        args = { "cat", home() .. "/.config/kandong/keys/" .. account }
    end
    run(args, function(ok, out)
        local key = ok and out:gsub("%s+$", ""):gsub("^%s+", "") or ""
        cb(key ~= "" and key or nil)
    end)
end

-- cb(ok)
function M.secret_delete(account, cb)
    if not ACCOUNTS[account] then return cb(false) end
    local args
    if platform == "darwin" then
        args = { "security", "delete-generic-password", "-s", M.SERVICE, "-a", account }
    elseif platform == "windows" then
        args = ps_args("Remove-Item -ErrorAction SilentlyContinue -Path (Join-Path $env:APPDATA 'KanDong\\keys\\"
            .. account .. ".dpapi')")
    else
        args = { "rm", "-f", home() .. "/.config/kandong/keys/" .. account }
    end
    run(args, function(ok) cb(ok) end)
end

M.ACCOUNT_LIST = { "openai", "anthropic", "google", "custom" }

return M
