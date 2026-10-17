-- Slow Hub - script that lives INSIDE Luarmor.
-- Upload this whole file to Luarmor and let Luarmor obfuscate it.
--
-- 1) LRM_INIT_SCRIPT runs BEFORE Luarmor authenticates. It shows the key
--    window, validates the key and sets script_key, all in the same place,
--    so there is no hand-over between scripts and Luarmor never asks again.
-- 2) Everything after it only runs once Luarmor accepted the key.
--
-- NOTE (from the Luarmor docs): the function inside LRM_INIT_SCRIPT is NOT
-- obfuscated, runs in its own context (no upvalues) and may exist only once.

LRM_INIT_SCRIPT(function()
    local CONFIG = {
        ScriptId = "4148cbb709649588d331629184124c57",
        GetKeyUrl = "https://link-center.net/1375550/t4EuIc7CPrXi",
        KeyFile = "SlowHubKey.txt",
        LegacyKeyFile = "SlowHub_AnimeZero_LuarmorKey.txt",
        SDK = "https://sdkapi-public.luarmor.net/library.lua",
        Fluent = "https://raw.githubusercontent.com/oneTime999/PcdFnlBossUI/refs/heads/main/main.lua"
    }

    local Env = (getgenv and getgenv()) or _G

    local logLines = {}
    Env.SlowHubKeyLog = logLines
    local function dbg(message)
        logLines[#logLines + 1] = string.format("[%0.1fs] %s", os.clock() % 100000, tostring(message))
        if #logLines > 60 then table.remove(logLines, 1) end
        warn("[Slow Hub][key] " .. tostring(message))
    end

    local function clean(value)
        if type(value) ~= "string" then return "" end
        return value:match("^%s*(.-)%s*$") or ""
    end

    local function readKeyFile(path)
        if type(readfile) ~= "function" then return nil end
        local ok, content = pcall(readfile, path)
        if not ok then return nil end
        content = clean(content)
        if content == "" or #content > 256 then return nil end
        return content
    end

    local function savedKey()
        local content = readKeyFile(CONFIG.KeyFile)
        if content then return content end
        content = readKeyFile(CONFIG.LegacyKeyFile)
        if content and type(writefile) == "function" then
            if pcall(writefile, CONFIG.KeyFile, content) and type(delfile) == "function" then
                pcall(delfile, CONFIG.LegacyKeyFile)
            end
        end
        return content
    end

    local function saveKey(value)
        if type(writefile) ~= "function" then return false end
        return (pcall(writefile, CONFIG.KeyFile, value))
    end

    local function clearSavedKey()
        for _, path in ipairs({CONFIG.KeyFile, CONFIG.LegacyKeyFile}) do
            local removed = false
            if type(delfile) == "function" then
                removed = pcall(delfile, path)
            end
            if not removed and type(writefile) == "function" then
                pcall(writefile, path, "")
            end
        end
    end

    local messages = {
        KEY_EXPIRED = "Key expired. Get a new key.",
        KEY_BANNED = "This key is blocked.",
        KEY_HWID_LOCKED = "Key linked to another device.",
        KEY_INCORRECT = "Incorrect key.",
        KEY_INVALID = "Invalid key format.",
        SCRIPT_ID_INCORRECT = "Luarmor script ID not found.",
        SCRIPT_ID_INVALID = "Invalid Luarmor script ID.",
        INVALID_EXECUTOR = "This executor is not supported by Luarmor.",
        SECURITY_ERROR = "Luarmor security check failed.",
        TIME_ERROR = "Your device time could not be verified.",
        UNKNOWN_ERROR = "Luarmor is temporarily unavailable."
    }

    local sdk
    local function getSDK()
        if sdk then return sdk end
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(CONFIG.SDK))()
        end)
        if not ok or type(result) ~= "table" then
            return nil, "Could not connect to Luarmor. Try again."
        end
        result.script_id = CONFIG.ScriptId
        sdk = result
        return result
    end

    -- Returns true when the key is valid. Otherwise false + a message.
    local function validate(key, fromCache)
        key = clean(key)
        if key == "" then return false, "Enter your key first." end

        local library, sdkError = getSDK()
        if not library then return false, sdkError end

        local ok, status = pcall(function() return library.check_key(key) end)
        if not ok or type(status) ~= "table" then
            return false, "Could not verify your key. Try again."
        end
        dbg("check_key -> " .. tostring(status.code) .. " (key length " .. #key .. ")")

        if status.code ~= "KEY_VALID" then
            if fromCache and (status.code == "KEY_EXPIRED" or status.code == "KEY_BANNED"
                or status.code == "KEY_INCORRECT" or status.code == "KEY_INVALID") then
                clearSavedKey()
            end
            return false, messages[status.code]
                or ("Luarmor verification failed: " .. tostring(status.code))
        end
        return true
    end

    local function acceptKey(key)
        -- This is the line Luarmor reads right after this function returns.
        script_key = key
        Env.script_key = key
        pcall(function() _G.script_key = key end)
        saveKey(key)
        dbg("script_key set (length " .. #key .. ")")
    end

    -- 1) A saved key skips the window entirely.
    local cached = savedKey()
    if cached then
        local ok = validate(cached, true)
        if ok then
            acceptKey(cached)
            return
        end
    end

    -- 2) Otherwise show the key window and wait until a valid key is entered.
    local okLib, screen = pcall(function()
        return loadstring(game:HttpGet(CONFIG.Fluent))()
    end)
    if not okLib or type(screen) ~= "table" then
        error("[Slow Hub] Could not open the key window: " .. tostring(screen), 0)
    end

    local function notify(message)
        if screen and not screen.Unloaded then
            pcall(function()
                screen:Notify({Title = "Slow Hub", Content = message, Duration = 6})
            end)
        end
    end

    local uis = game:GetService("UserInputService")
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local touchOnly = uis.TouchEnabled and not uis.KeyboardEnabled

    local window = screen:CreateWindow({
        Title = "Slow Hub",
        SubTitle = "Key Activation",
        TabWidth = touchOnly and 110 or 150,
        Size = UDim2.fromOffset(math.clamp(viewport.X - 60, 280, 460), math.clamp(viewport.Y - 60, 220, 330)),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl
    })
    local tab = window:AddTab({Title = "Key System", Icon = "key-round"})
    tab:AddSection("Activate")

    local typed = ""
    local checking = false
    local acceptedKey = nil

    tab:AddInput("SlowHub_LuarmorKey", {
        Title = "Enter Key",
        Placeholder = "Paste your Luarmor key",
        Default = "",
        Finished = false,
        Callback = function(value) typed = clean(value) end
    })

    tab:AddButton({
        Title = "Check Key",
        Description = "Validate key and start Slow Hub",
        Callback = function()
            if checking or acceptedKey then return end
            local key = typed ~= "" and typed or savedKey()
            if not key then
                notify("Enter your key first.")
                return
            end
            checking = true
            task.spawn(function()
                local ok, message = validate(key, false)
                checking = false
                if ok then
                    acceptedKey = key
                    notify("Key valid! Loading Slow Hub...")
                else
                    notify(message)
                end
            end)
        end
    })

    tab:AddButton({
        Title = "Get Key",
        Description = "Copy the link to obtain a new key",
        Callback = function()
            local copy = setclipboard or toclipboard
            if type(copy) ~= "function" then
                notify("Clipboard is unavailable.")
                return
            end
            local ok = pcall(copy, CONFIG.GetKeyUrl)
            notify(ok and "Key link copied." or "Could not copy the link.")
        end
    })

    tab:AddButton({
        Title = "Copy Debug Log",
        Description = "Copy the step-by-step log (the key is never included)",
        Callback = function()
            local copy = setclipboard or toclipboard
            if type(copy) ~= "function" then
                notify("Clipboard is unavailable. Check the console (F9).")
                return
            end
            local ok = pcall(copy, table.concat(logLines, "\n"))
            notify(ok and "Debug log copied." or "Could not copy the log.")
        end
    })

    tab:AddButton({
        Title = "Clear Saved Key",
        Description = "Forget the locally saved key",
        Callback = function()
            clearSavedKey()
            notify("Locally saved key cleared.")
        end
    })

    -- Block here (required by LRM_INIT_SCRIPT) until a valid key is accepted.
    -- If the key window is closed without a key, stop quietly instead of
    -- letting Luarmor kick the player with "no key found".
    while not acceptedKey do
        if screen.Unloaded then
            error("[Slow Hub] Key window closed. Run the script again.", 0)
        end
        task.wait(0.2)
    end

    acceptKey(acceptedKey)
    task.wait(0.3)
    pcall(function() screen:Destroy() end)
end)

----------------------------------------------------------------------
-- From here on the key has been accepted by Luarmor.
----------------------------------------------------------------------
local Env = (getgenv and getgenv()) or _G
local url = "https://raw.githubusercontent.com/oneTime999/AnimeZero/refs/heads/main/main.lua"
local source = game:HttpGet(url)
local run, err = loadstring(source)
assert(run, "Slow Hub main.lua failed to compile: " .. tostring(err))
run()

-- Temporary keys: stop the hub and forget the key when it expires.
-- LRM_SecondsLeft is a Luarmor runtime variable (math.huge for lifetime keys).
local secondsLeft = LRM_SecondsLeft
if type(secondsLeft) == "number" and secondsLeft > 0 and secondsLeft < 1e9 then
    task.delay(secondsLeft + 1, function()
        for _, path in ipairs({"SlowHubKey.txt", "SlowHub_AnimeZero_LuarmorKey.txt"}) do
            local removed = false
            if type(delfile) == "function" then removed = pcall(delfile, path) end
            if not removed and type(writefile) == "function" then pcall(writefile, path, "") end
        end
        local hub = Env.PcdBehindStable
        if type(hub) == "table" and hub.Alive and type(hub.Stop) == "function" then
            pcall(hub.Stop)
        end
        warn("[Slow Hub] Your key has expired. Run the script again with a new key.")
    end)
end
