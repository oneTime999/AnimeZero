-- Slow Hub - key activation and local key persistence.
-- No script_key is required at the top of the public loader.
local CONFIG = {
    ScriptId = "4148cbb709649588d331629184124c57",
    GetKeyUrl = "https://link-center.net/1375550/t4EuIc7CPrXi",
    KeyFile = "SlowHubKey.txt",
    LegacyKeyFile = "SlowHub_AnimeZero_LuarmorKey.txt", -- old name, migrated automatically
    SDK = "https://sdkapi-public.luarmor.net/library.lua",
    LoaderUrls = {
        "https://api.luarmor.net/files/v4/loaders/%s.lua",
        "https://api.luarmor.net/files/v3/loaders/%s.lua"
    },
    Fluent = "https://raw.githubusercontent.com/oneTime999/PcdFnlBossUI/refs/heads/main/main.lua"
}

if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 10512942223 then
    warn("[Slow Hub] This loader only works in Anime Zero (universe 10512942223)")
    return
end

local Env = (getgenv and getgenv()) or _G

-- Debug log. It never contains the key itself, only its length.
-- Open the key window and press "Copy Debug Log" to copy it.
local logLines = {}
Env.SlowHubKeyLog = logLines
local function dbg(message)
    local line = string.format("[%0.1fs] %s", os.clock() % 100000, tostring(message))
    logLines[#logLines + 1] = line
    if #logLines > 80 then table.remove(logLines, 1) end
    warn("[Slow Hub][key] " .. tostring(message))
end
dbg("executor: " .. tostring((identifyexecutor and select(1, identifyexecutor())) or "unknown"))

-- Running the loader twice must not produce duplicate farm loops.
local running = Env.PcdBehindStable
if type(running) == "table" and running.Alive
    and running.UI and not running.UI.Unloaded then
    return
end

-- All users, including developers, must pass Luarmor key validation.

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

    -- Key saved under the old file name: keep it working and move it to the new name.
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
    local ok = pcall(writefile, CONFIG.KeyFile, value)
    return ok
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

local oldUI = Env.SlowHubKeyScreen
if oldUI and not oldUI.Unloaded then
    pcall(function() oldUI:Destroy() end)
end
Env.SlowHubKeyScreen = nil

local sdk, screen, checking = nil, nil, false
local userInput = ""
local openScreen, activate

local errors = {
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

local function notify(message)
    if screen and not screen.Unloaded then
        pcall(function()
            screen:Notify({Title = "Slow Hub", Content = message, Duration = 6})
        end)
    end
end

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

local function loadedHub(previous)
    local hub = Env.PcdBehindStable
    if type(hub) == "table" and hub ~= previous and hub.Alive
        and hub.UI and not hub.UI.Unloaded and hub.UI.Window then
        return hub
    end
    return nil
end

-- Hands the key to the Luarmor-protected script.
-- Per the Luarmor docs, script_key must exist BEFORE the protected loader runs.
-- It is published in every global table executors expose, and also written
-- into the very chunk that runs the loader ("script_key = '...'; <loader>").
local function publishKey(key)
    Env.script_key = key
    pcall(function() _G.script_key = key end)
    pcall(function() shared.script_key = key end)
    pcall(function() script_key = key end)
    pcall(function()
        if getgenv then getgenv().script_key = key end
    end)
    local seen = pcall(function() return getgenv().script_key end)
        and type(getgenv().script_key) == "string"
    dbg(string.format("script_key published (len=%d, visible in getgenv=%s)",
        #key, tostring(seen)))
end

local function runProtected(library, key)
    publishKey(key)

    if key:match("^[%w%-_]+$") then
        for _, pattern in ipairs(CONFIG.LoaderUrls) do
            local url = string.format(pattern, CONFIG.ScriptId)
            local fetched, body = pcall(function() return game:HttpGet(url) end)
            if fetched and type(body) == "string" and #body > 0
                and not body:match("^%s*<") then
                dbg(string.format("loader fetched (%s, %d bytes)",
                    url:match("/files/(v%d)/") or "?", #body))
                local chunk, compileError = loadstring(
                    string.format("script_key=%q;\n", key) .. body)
                if chunk then
                    dbg("running Luarmor loader with script_key on top")
                    chunk()
                    dbg("Luarmor loader returned")
                    return
                end
                dbg("loader failed to compile: " .. tostring(compileError))
            else
                dbg(string.format("loader fetch failed (%s)",
                    url:match("/files/(v%d)/") or "?"))
            end
        end
    else
        dbg("key has unusual characters; using the SDK loader")
    end

    -- Fallback: the SDK loader (script_key global already published above).
    dbg("falling back to library.load_script()")
    library.load_script()
    dbg("library.load_script() returned")
end

local function closeScreen()
    local closing = screen
    screen = nil
    if Env.SlowHubKeyScreen == closing then
        Env.SlowHubKeyScreen = nil
    end
    if closing and not closing.Unloaded then
        pcall(function() closing:Destroy() end)
    end
end

local function watchExpiration(expire, hub)
    local old = Env.SlowHubKeySession
    if type(old) == "table" then old.Active = false end
    local session = {Active = true, Expire = expire}
    Env.SlowHubKeySession = session

    -- A lifetime key has an expiry of -1 or 0. Temporary keys are
    -- rechecked online on every subsequent execution of this loader.
    if type(expire) ~= "number" or expire <= 0 then return end
    if expire <= os.time() then return end

    task.spawn(function()
        while session.Active and Env.SlowHubKeySession == session do
            task.wait(10)
            if os.time() >= expire then
                session.Active = false
                clearSavedKey()
                Env.script_key = nil
                script_key = nil
                if type(hub.Stop) == "function" and hub.Alive then
                    pcall(hub.Stop)
                end
                openScreen("Your key has expired. Enter a new key.")
                break
            end
        end
    end)
end

activate = function(key, fromCache)
    key = clean(key)
    if key == "" then
        return false, "Enter your key first."
    end

    dbg(string.format("activate (key length %d, from cache: %s)", #key, tostring(fromCache == true)))
    local library, sdkError = getSDK()
    if not library then
        dbg("SDK unavailable: " .. tostring(sdkError))
        return false, sdkError
    end

    local checked, status = pcall(function()
        return library.check_key(key)
    end)
    if not checked or type(status) ~= "table" then
        return false, "Could not verify your key. Try again."
    end

    dbg("check_key -> " .. tostring(status.code))
    if status.code ~= "KEY_VALID" then
        -- Only permanently invalid cached keys are erased.
        -- Transient network/HWID problems must not destroy a valid key.
        if fromCache and (status.code == "KEY_EXPIRED"
            or status.code == "KEY_BANNED"
            or status.code == "KEY_INCORRECT"
            or status.code == "KEY_INVALID") then
            clearSavedKey()
        end
        return false, errors[status.code]
            or ("Luarmor verification failed: " .. tostring(status.code))
    end

    local previousHub = Env.PcdBehindStable

    -- The key is only handed over AFTER Luarmor has accepted it.
    local started, loadError = pcall(function()
        runProtected(library, key)
    end)
    if not started then
        dbg("protected loader error: " .. tostring(loadError))
        warn("[Slow Hub] Protected loader: " .. tostring(loadError))
        return false, "Key valid, but the script could not be loaded."
    end

    local hub
    for _ = 1, 100 do
        hub = loadedHub(previousHub)
        if hub then break end
        task.wait(0.2)
    end
    if not hub then
        dbg("hub did not appear within 20s")
        return false, "Key valid, but Slow Hub did not open. Try again."
    end
    dbg("hub opened")

    if not saveKey(key) then
        warn("[Slow Hub] This executor cannot save the key locally.")
    end

    local expire = status.data and tonumber(status.data.auth_expire)
    -- The main window is open, so the activation window can now close.
    closeScreen()
    watchExpiration(expire, hub)
    return true
end

openScreen = function(message)
    if screen and not screen.Unloaded then
        if message then notify(message) end
        return
    end

    local ok, library = pcall(function()
        return loadstring(game:HttpGet(CONFIG.Fluent))()
    end)
    if not ok or type(library) ~= "table" then
        warn("[Slow Hub] Could not open key UI: " .. tostring(library))
        return
    end

    screen = library
    Env.SlowHubKeyScreen = library
    userInput = ""

    -- Sized to the screen so the key window also fits phones.
    local uis = game:GetService("UserInputService")
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local touchOnly = uis.TouchEnabled and not uis.KeyboardEnabled

    local window = library:CreateWindow({
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

    tab:AddInput("SlowHub_LuarmorKey", {
        Title = "Enter Key",
        Placeholder = "Paste your Luarmor key",
        Default = "",
        Finished = false,
        Callback = function(value) userInput = clean(value) end
    })

    tab:AddButton({
        Title = "Check Key",
        Description = "Validate key and start Slow Hub",
        Callback = function()
            if checking then return end
            local typed = clean(userInput)
            local cached = savedKey()
            local key = typed ~= "" and typed or cached
            if not key then
                notify("Enter your key first.")
                return
            end

            checking = true
            task.spawn(function()
                local success, result = activate(key, typed == "" and cached ~= nil)
                checking = false
                if not success then notify(result) end
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

    if message then
        task.defer(function()
            if screen == library then notify(message) end
        end)
    end
end

local cached = savedKey()
if cached then
    checking = true
    task.spawn(function()
        local success, reason = activate(cached, true)
        checking = false
        if not success then
            openScreen(reason or "Enter your key.")
        end
    end)
else
    openScreen()
end
