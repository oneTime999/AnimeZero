return function(ctx)
    local Player, WS = ctx.Player, ctx.WS

    -- Confirmed from Anime Zero's three actual matches.
    -- All three share one PlaceId and differ by Workspace.Mode.
    local UNIVERSE_ID = 10512942223
    local MATCH_PLACE_ID = 109151342576374
    local MODES = {
        Story = {Name = "HxH Story", Value = "hxh"},
        Raids = {Name = "Shadow Monarch", Value = "sololevelingraid"},
        Zzz = {Name = "Zzz World", Value = "infinite"}
    }

    local function currentMode()
        local value = WS:GetAttribute("Mode")
        if type(value) ~= "string" and type(value) ~= "number" then
            return ""
        end
        return tostring(value):lower():match("^%s*(.-)%s*$") or ""
    end

    local Guard = {}

    function Guard.IsDeveloper()
        -- This is the Roblox username (Player.Name), NOT DisplayName.
        -- Client-only feature visibility is not a secure permission boundary.
        return Player.Name:lower() == "z16qe2"
    end

    function Guard.Detected()
        if game.GameId ~= UNIVERSE_ID or game.PlaceId ~= MATCH_PLACE_ID then
            return nil
        end
        local value = currentMode()
        for key, info in pairs(MODES) do
            if info.Value == value then return key end
        end
        return nil
    end

    function Guard.Allowed(mode)
        local entry = MODES[mode]
        return entry ~= nil
            and game.GameId == UNIVERSE_ID
            and game.PlaceId == MATCH_PLACE_ID
            and currentMode() == entry.Value
    end

    function Guard.Reason(mode)
        local entry = MODES[mode]
        if not entry then return "Unknown farm mode" end
        if game.GameId ~= UNIVERSE_ID then
            return "Slow Hub only supports Anime Zero"
        end
        if game.PlaceId ~= MATCH_PLACE_ID then
            return "Enter the Anime Zero match before enabling this farm"
        end
        if currentMode() ~= entry.Value then
            return "Current match is not " .. entry.Name
        end
        return "Allowed"
    end

    function Guard.ModeName()
        local mode = Guard.Detected()
        return mode and MODES[mode].Name or "Lobby / Unsupported mode"
    end

    function Guard.Status()
        return Guard.ModeName()
    end

    function Guard.Diagnostics()
        if not Guard.IsDeveloper() then
            return "Developer diagnostics restricted"
        end
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local lines = {
            "Slow Hub | Anime Zero diagnostics",
            "Universe ID: " .. tostring(game.GameId),
            "Place ID: " .. tostring(game.PlaceId),
            "Workspace.Mode: " .. (currentMode() ~= "" and currentMode() or "(missing)"),
            "Detected mode: " .. Guard.ModeName(),
            "Story allowed: " .. tostring(Guard.Allowed("Story")),
            "Shadow Monarch allowed: " .. tostring(Guard.Allowed("Raids")),
            "Zzz World allowed: " .. tostring(Guard.Allowed("Zzz"))
        }
        for _, name in ipairs({"RunManage", "InfiniteManage", "BossBar", "EndScreen"}) do
            local object = gui and gui:FindFirstChild(name)
            table.insert(lines, "GUI " .. name .. ": "
                .. (object and (object:IsA("ScreenGui")
                    and object.Enabled and "enabled" or "present") or "missing"))
        end
        local active = ctx.FarmMonitor
        if active then
            table.insert(lines, "Farm: " .. tostring(active.Mode))
            table.insert(lines, "State: " .. tostring(active.State))
            table.insert(lines, "Detected NPCs: " .. tostring(active.NPCs))
            table.insert(lines, "Recoveries: " .. tostring(active.Recoveries))
            table.insert(lines, "Last error: " .. tostring(active.LastError))
        end
        return table.concat(lines, "\n")
    end

    ctx.GameGuard = Guard
end
