-- Slow Hub - public launcher (no script_key required)
if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10512942223 then
    warn("[Slow Hub] Only the official Anime Zero experience is supported")
    return
end

local url = "https://raw.githubusercontent.com/oneTime999/AnimeZero/refs/heads/main/key_loader.lua"
local source = game:HttpGet(url)
local start, err = loadstring(source)
assert(start, "Unable to load Slow Hub key screen: " .. tostring(err))
start()
