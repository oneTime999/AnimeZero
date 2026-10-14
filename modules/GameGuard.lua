return function(ctx)
    local Player, WS = ctx.Player, ctx.WS

    -- Confirmed from Anime Zero's three actual matches.
    -- All three share one PlaceId and differ by Workspace.Mode.
    local UNIVERSE_ID = 10512942223
    local MATCH_PLACE_ID = 109151342576374
    local MODES = {
        Raids = {Name = "Shadow Monarch", Value = "sololevelingraid"},
        Zzz = {Name = "Zzz World", Value = "infinite"},
        Lift = {Name = "Endless Trial", Value = "lift"},
        Story = {Name = "Story", Value = "story"}
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
        -- Roblox usernames (Player.Name), not DisplayName.
        -- Client-side visibility is not a secure permission boundary.
        local username = Player.Name:lower()
        return username == "z16qe2"
            or username == "do_nopp"
            or username == "batema2024"
    end

    function Guard.Detected()
        if game.GameId ~= UNIVERSE_ID or game.PlaceId ~= MATCH_PLACE_ID then
            return nil
        end
        local value = currentMode()
        for key, info in pairs(MODES) do
            if key ~= "Lift" and info.Value == value then return key end
        end
        local world = WS:FindFirstChild("World")
        local markers = world and world:FindFirstChild("Markers")
        local lift = markers and markers:FindFirstChild("Lift")
        if lift and lift:FindFirstChildWhichIsA("ProximityPrompt", true) then
            return "Lift"
        end
        local map = world and world:FindFirstChild("Map")
        if map and WS:FindFirstChild("enemies") then
            for _, child in ipairs(map:GetChildren()) do
                if child.Name:match("^Border%d+$") and child:FindFirstChild("Rubble") then
                    return "Story"
                end
            end
        end
        return nil
    end

    function Guard.Allowed(mode)
        local entry = MODES[mode]
        if not entry or game.GameId ~= UNIVERSE_ID or game.PlaceId ~= MATCH_PLACE_ID then
            return false
        end
        if mode == "Lift" then
            local world = WS:FindFirstChild("World")
            local markers = world and world:FindFirstChild("Markers")
            local lift = markers and markers:FindFirstChild("Lift")
            return lift ~= nil and lift:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
        end
        if mode == "Story" then
            -- Nao depende de Border1.Rubble nem do HUD: as pedras somem ao
            -- serem quebradas e o farm precisa continuar nas proximas Areas.
            -- Story vale para qualquer partida que nao seja Raid, Zzz ou Trial.
            local value = currentMode()
            if value == MODES.Raids.Value or value == MODES.Zzz.Value then
                return false
            end
            local world = WS:FindFirstChild("World")
            local markers = world and world:FindFirstChild("Markers")
            local lift = markers and markers:FindFirstChild("Lift")
            if lift and lift:FindFirstChildWhichIsA("ProximityPrompt", true) then
                return false
            end
            return true
        end
        return currentMode() == entry.Value
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
        if mode == "Lift" then
            local world = WS:FindFirstChild("World")
            local markers = world and world:FindFirstChild("Markers")
            local lift = markers and markers:FindFirstChild("Lift")
            if not lift or not lift:FindFirstChildWhichIsA("ProximityPrompt", true) then
                return "Enter the Endless Trial mode before enabling this farm"
            end
            return "Allowed"
        end
        if mode == "Story" then
            if Guard.Allowed("Story") then return "Allowed" end
            return "Auto Story is not available in Shadow Monarch, Zzz World or Endless Trial"
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

    ctx.GameGuard = Guard
end
