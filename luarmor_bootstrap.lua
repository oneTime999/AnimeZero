-- Upload this small script to Luarmor.
-- It runs after Luarmor authentication and always fetches the latest main.lua.
-- Note: a public GitHub repository can still be run without this loader.
local url = "https://raw.githubusercontent.com/oneTime999/AnimeZero/refs/heads/main/main.lua"
local source = game:HttpGet(url)
local run, err = loadstring(source)
assert(run, "Slow Hub main.lua failed to compile: " .. tostring(err))
run()
