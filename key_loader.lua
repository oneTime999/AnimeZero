-- Slow Hub - standalone key activation screen
-- Fill in these two values before distributing this loader.
local CONFIG = {
    ScriptId = "YOUR_LUARMOR_SCRIPT_ID",
    GetKeyUrl = "YOUR_LINKVERTISE_URL"
}

if not game:IsLoaded() then game.Loaded:Wait() end

local Env = (getgenv and getgenv()) or _G
if Env.SlowHubKeyScreen and not Env.SlowHubKeyScreen.Unloaded then
    pcall(function() Env.SlowHubKeyScreen:Destroy() end)
end

local Fluent = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/oneTime999/PcdFnlBossUI/refs/heads/main/main.lua"
))()
Env.SlowHubKeyScreen = Fluent

local Window = Fluent:CreateWindow({
    Title = "Slow Hub",
    SubTitle = "Key Activation",
    TabWidth = 150,
    Size = UDim2.fromOffset(460, 330),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Keys = Window:AddTab({Title = "Key System", Icon = "key-round"})
Keys:AddSection("Activate")
local enteredKey = ""
local busy = false

local function notify(message)
    Fluent:Notify({
        Title = "Slow Hub",
        Content = message,
        Duration = 6
    })
end

Keys:AddInput("SlowHub_LuarmorKey", {
    Title = "Enter Key",
    Placeholder = "Paste your Luarmor key",
    Default = "",
    Finished = false,
    Callback = function(value)
        enteredKey = type(value) == "string"
            and (value:match("^%s*(.-)%s*$") or "")
            or ""
    end
})

Keys:AddButton({
    Title = "Check Key",
    Description = "Activate Slow Hub",
    Callback = function()
        if busy then return end
        if CONFIG.ScriptId == "YOUR_LUARMOR_SCRIPT_ID"
            or CONFIG.ScriptId == "" then
            notify("Luarmor Script ID is not configured")
            return
        end
        if enteredKey == "" then
            notify("Enter your key first")
            return
        end

        busy = true
        task.spawn(function()
            local ok, sdk = pcall(function()
                return loadstring(game:HttpGet(
                    "https://sdkapi-public.luarmor.net/library.lua"
                ))()
            end)
            if not ok or type(sdk) ~= "table" then
                busy = false
                notify("Could not connect to Luarmor")
                return
            end

            sdk.script_id = CONFIG.ScriptId
            local checked, status = pcall(function()
                return sdk.check_key(enteredKey)
            end)
            if not checked or type(status) ~= "table" then
                busy = false
                notify("Could not verify your key")
                return
            end

            if status.code ~= "KEY_VALID" then
                busy = false
                local explanations = {
                    KEY_EXPIRED = "Your key has expired",
                    KEY_BANNED = "This key is blocked",
                    KEY_HWID_LOCKED = "Key linked to another device",
                    KEY_INCORRECT = "Invalid key",
                    KEY_INVALID = "Invalid key format"
                }
                notify(explanations[status.code]
                    or ("Activation failed: " .. tostring(status.code)))
                return
            end

            -- Luarmor expects script_key to be set before load_script().
            script_key = enteredKey
            Env.script_key = enteredKey
            notify("Key accepted. Loading Slow Hub...")
            local loaded, err = pcall(function()
                sdk.load_script()
            end)
            busy = false
            if not loaded then
                warn("[Slow Hub] Luarmor load error: " .. tostring(err))
                notify("Could not load Slow Hub")
                return
            end
            pcall(function()
                Fluent:Destroy()
            end)
            if Env.SlowHubKeyScreen == Fluent then
                Env.SlowHubKeyScreen = nil
            end
        end)
    end
})

Keys:AddButton({
    Title = "Get Key",
    Description = "Copy the key link",
    Callback = function()
        local url = CONFIG.GetKeyUrl
        if type(url) ~= "string"
            or not url:match("^https://")
            or url == "YOUR_LINKVERTISE_URL" then
            notify("Get Key link is not configured")
            return
        end

        local copy = setclipboard or toclipboard
        if type(copy) ~= "function" then
            notify("Clipboard is unavailable")
            return
        end
        local ok = pcall(copy, url)
        notify(ok and "Key link copied" or "Could not copy the link")
    end
})
