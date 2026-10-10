return function(ctx)
    local Player = ctx.Player
    local RS = ctx.RS
    local module, lastAttempt, loadError = nil, -math.huge, "Not checked"

    local function getModule()
        if module then return module end
        if os.clock() - lastAttempt < 8 then return nil end
        lastAttempt = os.clock()
        local root = RS:FindFirstChild("game")
        local stores = root and root:FindFirstChild("stores")
        local script = stores and stores:FindFirstChild("runStore")
        if not (script and script:IsA("ModuleScript")) then
            loadError = "runStore module not found"
            return nil
        end
        local ok, value = pcall(require, script)
        if not ok or type(value) ~= "table" or not value.store
            or not value.store.state then
            loadError = "runStore could not be accessed"
            return nil
        end
        module, loadError = value, nil
        return module
    end

    local function get(atom)
        if atom == nil then return nil end
        local ok, value = pcall(function() return atom:get() end)
        return ok and value or nil
    end

    local function positive(value)
        local n = tonumber(value)
        if not n or n ~= n then return 0 end
        return math.max(0, n)
    end

    local function pretty(value)
        local n = positive(value)
        if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
        if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
        if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
        return tostring(math.floor(n + 0.5)):reverse()
            :gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    end

    local function timeText(value)
        local seconds = math.floor(positive(value))
        return string.format("%02d:%02d:%02d",
            math.floor(seconds / 3600), math.floor(seconds / 60) % 60,
            seconds % 60)
    end

    local function getDifficulty()
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        if not gui then return nil end
        local infinite = ctx.ZzzzWorld and ctx.ZzzzWorld.Enabled
        local managers = infinite
            and {"InfiniteManage", "RunManage"}
            or {"RunManage", "InfiniteManage"}
        for _, name in ipairs(managers) do
            local manager = gui:FindFirstChild(name)
            local sheet = manager and manager:FindFirstChild("Sheet")
            local title = sheet and sheet:FindFirstChild("Title")
            local label = title and title:FindFirstChild("Info")
            if label and label:IsA("TextLabel") then
                local text = label.Text:lower()
                for _, item in ipairs({"Nightmare", "Hard", "Medium", "Easy"}) do
                    if text:find(item:lower(), 1, true) then
                        return item
                    end
                end
            end
        end
        return nil
    end

    ctx.ReadMatchStore = function()
        local source = getModule()
        if not source then return nil, "unavailable", nil, loadError end
        local state = source.store.state
        local ok, participant = pcall(function()
            return state.participants:get(tostring(Player.UserId))
        end)
        if not ok or participant == nil then
            return nil, "unavailable", nil, "Participant not available"
        end
        local rawStatus = get(participant.status)
        if rawStatus == nil then
            return nil, "unavailable", nil, "Status not available"
        end
        local status = tostring(rawStatus):lower()
        if status == "active" then
            return nil, "active", tostring(participant), nil
        end

        local function value(field)
            return positive(get(participant[field]))
        end
        local earned = value("earned") + value("bonus")
        local gems = value("gems")
        local rerolls = value("crystals")
        local materialString = get(participant.materials)
        if type(materialString) ~= "string" then materialString = "" end
        local rewards = {}
        local function add(label, category, n)
            if n > 0 then
                table.insert(rewards, {
                    Name = label, Category = category, Amount = n
                })
            end
        end
        add("Coins", "Coins", earned)
        add("Gems", "RewardGems", gems)
        add("Trait Rerolls", "TraitRerolls", rerolls)

        local materialTotals, ids = {}, {}
        for id, quantity in materialString:gmatch("(%d+):(%d+)") do
            if not materialTotals[id] then
                materialTotals[id] = 0
                table.insert(ids, id)
            end
            materialTotals[id] = materialTotals[id] + positive(quantity)
        end
        table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
        for _, id in ipairs(ids) do
            add("Material #" .. id, "Materials", materialTotals[id])
        end

        local outcome = status
        if status == "failed" and workspace:GetAttribute("Mode") == "sakamoto"
            and value("bonus") > 0 then
            outcome = "victory"
        end
        local win = outcome == "victory" or outcome == "won"
            or outcome == "success" or outcome == "completed"
        local signature = table.concat({
            tostring(participant), tostring(get(state.finishedAt)),
            tostring(status), tostring(earned), tostring(gems),
            tostring(rerolls), materialString
        }, "|")
        local report = {
            Win = win, Source = "RunStore",
            Difficulty = getDifficulty(),
            Rewards = rewards, Signature = signature,
            RawEXP = value("xp"), RawGems = gems,
            Stats = {
                ["Play Time"] = timeText(value("elapsed")),
                ["Enemies Killed"] = pretty(value("kills")),
                ["Damage Dealt"] = pretty(value("damage")),
                ["EXP Earned"] = pretty(value("xp")),
                ["Gems Earned"] = pretty(gems)
            }
        }
        return report, "finished", tostring(participant), nil
    end
end
