-- Slow Hub - public launcher.
-- The key window now runs inside the Luarmor-protected script
-- (see luarmor_bootstrap.lua), so no script_key is needed here.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10512942223 then
    warn("[Slow Hub] Only the official Anime Zero experience is supported")
    return
end

local Env = (getgenv and getgenv()) or _G

-- Running the launcher twice must not produce duplicate farm loops.
local running = Env.PcdBehindStable
if type(running) == "table" and running.Alive
    and running.UI and not running.UI.Unloaded then
    return
end

local SCRIPT_ID = "4148cbb709649588d331629184124c57"
local URLS = {
    "https://api.luarmor.net/files/v4/loaders/%s.lua",
    "https://api.luarmor.net/files/v3/loaders/%s.lua"
}

for _, pattern in ipairs(URLS) do
    local ok, source = pcall(function()
        return game:HttpGet(string.format(pattern, SCRIPT_ID))
    end)
    if ok and type(source) == "string" and #source > 0 and not source:match("^%s*<") then
        local start, err = loadstring(source)
        if start then
            return start()
        end
        warn("[Slow Hub] Luarmor loader failed to compile: " .. tostring(err))
    end
end

warn("[Slow Hub] Could not reach the Luarmor loader. Check your connection and try again.")
