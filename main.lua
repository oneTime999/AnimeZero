if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Env = (getgenv and getgenv()) or _G
local Root = Env.PcdFnlBossModulesURL
    or "https://raw.githubusercontent.com/oneTime999/AnimeZero/refs/heads/main/"
Root = Root:gsub("/+$", "") .. "/"

local function loadModule(name)
    local url = Root .. "modules/" .. name .. ".lua"
    local source, lastError
    for attempt = 1, 4 do
        local ok, result = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and type(result) == "string" and #result > 0 then
            source = result
            break
        end
        lastError = result
        if attempt < 4 then task.wait(math.min(attempt, 3)) end
    end
    assert(source, "Unable to download " .. name .. ": " .. tostring(lastError))
    local chunk, err = loadstring(source)
    assert(chunk, "Unable to compile " .. name .. ": " .. tostring(err))
    local module = chunk()
    assert(type(module) == "function" or name == "Core", "Invalid module: " .. name)
    return module
end

local ctx = loadModule("Core")
local modules = {
    "Enemies", "Movement", "Skills", "Rubble", "Story", "Raids",
    "ZzzzWorld", "UI", "Drops", "RunRewards", "Webhook", "Profiles", "Runtime", "Recovery"
}

-- Nonessential integrations should never stop all three farms from starting.
local optional = {Drops = true, RunRewards = true, Webhook = true, Profiles = true, Recovery = true}
for _, name in ipairs(modules) do
    local loaded, moduleOrError = pcall(loadModule, name)
    if not loaded then
        if optional[name] then
            warn("[Slow Hub] Optional module " .. name .. ": " .. tostring(moduleOrError))
        else
            error("Unable to start " .. name .. ": " .. tostring(moduleOrError))
        end
    else
        local ok, err = pcall(moduleOrError, ctx)
        if not ok then
            if optional[name] then
                warn("[Slow Hub] Optional module " .. name .. ": " .. tostring(err))
            else
                error("Module " .. name .. " failed: " .. tostring(err))
            end
        end
    end
end
