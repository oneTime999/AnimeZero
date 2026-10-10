if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Env = (getgenv and getgenv()) or _G
local Root = Env.PcdFnlBossModulesURL
    or "https://raw.githubusercontent.com/oneTime999/AnimeZero/refs/heads/main/"
Root = Root:gsub("/+$", "") .. "/"

local function loadModule(name)
    local url = Root .. "modules/" .. name .. ".lua"
    local source = game:HttpGet(url)
    local chunk, err = loadstring(source)
    assert(chunk, "Unable to compile " .. name .. ": " .. tostring(err))
    local module = chunk()
    assert(type(module) == "function" or name == "Core", "Invalid module: " .. name)
    return module
end

local ctx = loadModule("Core")
local modules = {
    "Enemies", "Movement", "Skills", "Rubble", "Story", "Raids",
    "ZzzzWorld", "UI", "RunRewards", "Webhook", "Profiles", "Runtime"
}

for _, name in ipairs(modules) do
    local factory = loadModule(name)
    local ok, err = pcall(factory, ctx)
    assert(ok, "Module " .. name .. " failed: " .. tostring(err))
end
