return function(ctx)
    local HttpService = game:GetService("HttpService")
    local Player, WS = ctx.Player, ctx.WS

    local UNIVERSE_ID = 10512942223
    local FILE = "SlowHub_AnimeZero_Places_v1.json"
    local NAMES = {Story = "HxH Story", Raids = "Shadow Monarch", Zzz = "Zzz World"}
    local records = {}

    local function modeValue()
        local value = WS:GetAttribute("Mode")
        if type(value) ~= "string" or value == "" then return "" end
        return value:lower():match("^%s*(.-)%s*$") or ""
    end

    local function loadRecords()
        if type(readfile) ~= "function" then return end
        local ok, raw = pcall(readfile, FILE)
        if not ok or type(raw) ~= "string" then return end
        local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not decoded or type(data) ~= "table"
            or tonumber(data.UniverseId) ~= UNIVERSE_ID
            or type(data.Modes) ~= "table" then return end
        for key in pairs(NAMES) do
            local entry = data.Modes[key]
            if type(entry) == "table"
                and type(entry.PlaceId) == "number"
                and entry.PlaceId > 0
                and type(entry.ModeAttribute) == "string" then
                records[key] = {
                    PlaceId = entry.PlaceId,
                    ModeAttribute = entry.ModeAttribute
                }
            end
        end
    end
    loadRecords()

    local function saveRecords()
        if type(writefile) ~= "function" then
            return false, "File storage is unavailable; registration will last only this session"
        end
        local ok, err = pcall(writefile, FILE, HttpService:JSONEncode({
            UniverseId = UNIVERSE_ID, Modes = records
        }))
        if not ok then return false, tostring(err) end
        return true
    end

    local Guard = {}
    function Guard.Allowed(mode)
        if game.GameId ~= UNIVERSE_ID or not NAMES[mode] then return false end
        local entry = records[mode]
        if not entry or entry.PlaceId ~= game.PlaceId then return false end
        local value = modeValue()
        return entry.ModeAttribute == value
    end

    function Guard.Reason(mode)
        if game.GameId ~= UNIVERSE_ID then
            return "This is not the official Anime Zero experience"
        end
        if not NAMES[mode] then return "Unknown farm mode" end
        local entry = records[mode]
        if not entry then
            return "Register " .. NAMES[mode] .. " in its actual match first"
        end
        if entry.PlaceId ~= game.PlaceId then
            return NAMES[mode] .. " is registered to a different Place"
        end
        if entry.ModeAttribute ~= modeValue() then
            return NAMES[mode] .. " is not the current game mode"
        end
        return "Allowed"
    end

    function Guard.Register(mode)
        if not NAMES[mode] then return false, "Unknown farm" end
        if game.GameId ~= UNIVERSE_ID then
            return false, "Only Anime Zero is supported"
        end
        local candidate = {
            PlaceId = game.PlaceId,
            ModeAttribute = modeValue()
        }
        if candidate.PlaceId == 114574503491412 then
            return false, "This is the main lobby. Enter the intended match first"
        end
        for other, entry in pairs(records) do
            if other ~= mode and entry.PlaceId == candidate.PlaceId then
                if candidate.ModeAttribute == "" or entry.ModeAttribute == ""
                    or entry.ModeAttribute == candidate.ModeAttribute then
                    return false, "Cannot distinguish this Place from "
                        .. NAMES[other] .. ". Copy diagnostics and send them for verification"
                end
            end
        end
        records[mode] = candidate
        local persisted, err = saveRecords()
        if not persisted then
            warn("[Slow Hub] Place registration not saved: " .. tostring(err))
            return true, NAMES[mode] .. " registered for this session only"
        end
        return true, NAMES[mode] .. " linked to Place " .. tostring(candidate.PlaceId)
    end

    function Guard.Status()
        local pieces = {}
        for _, key in ipairs({"Story", "Raids", "Zzz"}) do
            local entry = records[key]
            local state = not entry and "Not registered"
                or (Guard.Allowed(key) and "Allowed" or "Other Place/mode")
            table.insert(pieces, NAMES[key] .. ": " .. state)
        end
        return table.concat(pieces, " | ")
    end

    function Guard.Diagnostics()
        local attributes = WS:GetAttributes()
        local keys = {}
        for key in pairs(attributes) do
            table.insert(keys, tostring(key))
        end
        table.sort(keys)
        local lines = {
            "Anime Zero - Slow Hub place diagnostics",
            "GameId (universe): " .. tostring(game.GameId),
            "PlaceId: " .. tostring(game.PlaceId),
            "JobId present: " .. tostring(game.JobId ~= ""),
            "Workspace Mode: " .. (modeValue() ~= "" and modeValue() or "(missing)"),
            "Workspace attributes:"
        }
        for _, key in ipairs(keys) do
            local value = attributes[key]
            if type(value) == "string" or type(value) == "number"
                or type(value) == "boolean" then
                table.insert(lines, "  " .. key .. " = " .. tostring(value))
            end
        end
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        for _, name in ipairs({"RunManage", "InfiniteManage", "BossBar", "EndScreen"}) do
            local object = gui and gui:FindFirstChild(name)
            local visible = object and object:IsA("ScreenGui") and object.Enabled
            table.insert(lines, "GUI " .. name .. ": " ..
                (object and (visible and "enabled" or "present") or "missing"))
        end
        return table.concat(lines, "\n")
    end

    ctx.GameGuard = Guard
end
