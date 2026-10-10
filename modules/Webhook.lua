return function(ctx)
    local S, Player, Webhooks, Fluent = ctx.S, ctx.Player, ctx.Webhooks, ctx.Fluent
    local HttpService = game:GetService("HttpService")
    local Config = {
        Enabled = false,
        Url = "",
        FarmTotals = true,
        Fields = {
            Result = true, Duration = true, Difficulty = true, Kills = true, Damage = true,
            EXP = true, GemsEarned = true,
            Rewards = true, Coins = true, RewardGems = true,
            TraitRerolls = true, Materials = true
        }
    }

    Webhooks:AddSection("Connection")
    Webhooks:AddToggle("HxH_WebhookEnabled", {
        Title = "Match Notifications",
        Description = "Sends match results to Discord",
        Default = false,
        Callback = function(value) Config.Enabled = value end
    })
    Webhooks:AddInput("HxH_WebhookURL", {
        Title = "Discord Webhook URL",
        Description = "Where notifications are sent",
        Default = "",
        Placeholder = "https://discord.com/api/webhooks/...",
        Finished = false,
        Callback = function(value)
            Config.Url = type(value) == "string"
                and (value:match("^%s*(.-)%s*$") or "") or ""
        end
    })

    local function addFieldOption(id, title, key, description)
        Webhooks:AddToggle(id, {
            Title = title,
            Description = description,
            Default = true,
            Callback = function(value) Config.Fields[key] = value end
        })
    end

    Webhooks:AddSection("Match Information")
    addFieldOption("HxH_WebhookResult", "Victory / Defeat", "Result")
    addFieldOption("HxH_WebhookDuration", "Match Duration", "Duration")
    addFieldOption("HxH_WebhookDifficulty", "Stage Difficulty", "Difficulty")
    addFieldOption("HxH_WebhookKills", "Enemies Killed", "Kills")
    addFieldOption("HxH_WebhookDamage", "Damage Dealt", "Damage")
    addFieldOption("HxH_WebhookEXP", "EXP Earned", "EXP")
    addFieldOption("HxH_WebhookGemsEarned", "Gems Earned (Stats)", "GemsEarned")
    Webhooks:AddSection("Rewards")
    addFieldOption("HxH_WebhookRewards", "Show Earned Rewards", "Rewards")
    addFieldOption("HxH_WebhookCoins", "Coins / Gold", "Coins")
    addFieldOption("HxH_WebhookRewardGems", "Gems", "RewardGems")
    addFieldOption("HxH_WebhookTraitRerolls", "Trait Rerolls", "TraitRerolls")
    addFieldOption("HxH_WebhookMaterials", "Materials", "Materials")

    local function getText(parent, name)
        local label = parent and parent:FindFirstChild(name, true)
        if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
            return label.Text
        end
        return nil
    end

    local function clean(value)
        if type(value) ~= "string" then return "" end
        value = value:gsub("<[^>]+>", ""):gsub("[%c]", " "):gsub("%s+", " ")
        return value:match("^%s*(.-)%s*$") or ""
    end

    local Session = {
        Rounds = 0,
        Wins = 0,
        Losses = 0,
        EXP = 0,
        GemsEarned = 0,
        Rewards = {},
        Seconds = 0,
        StartedAt = os.time()
    }

    local function resetSession()
        Session.Rounds, Session.Wins, Session.Losses = 0, 0, 0
        Session.EXP, Session.GemsEarned = 0, 0
        Session.Rewards = {}
        Session.Seconds = 0
        Session.StartedAt = os.time()
    end

    local function parseNumber(raw)
        if type(raw) == "number" then return raw end
        raw = clean(raw):gsub("[xX$]", ""):gsub("×", "")
            :gsub("%s+", "")
        local digits, suffix = raw:match("^([%d%.,]+)([kKmMbBtT]?)$")
        if not digits then return nil end
        if digits:find(",") and digits:find("%.") then
            digits = digits:gsub(",", "")
        elseif digits:find(",") then
            if digits:match(",%d%d%d$") then
                digits = digits:gsub(",", "")
            else
                digits = digits:gsub(",", ".")
            end
        elseif digits:match("%.%d%d%d$") then
            digits = digits:gsub("%.", "")
        end
        local num = tonumber(digits)
        if not num then return nil end
        local scale = {k = 1e3, m = 1e6, b = 1e9, t = 1e12}
        return num * (scale[suffix:lower()] or 1)
    end

    local function formatNumber(num)
        if type(num) ~= "number" then return "0" end
        if math.abs(num) >= 1e12 then return string.format("%.2fT", num / 1e12) end
        if math.abs(num) >= 1e9 then return string.format("%.2fB", num / 1e9) end
        local str = string.format("%.2f", num)
        str = str:gsub("0+$", ""):gsub("%.$", "")
        local integer, fraction = str:match("^(%-?%d+)(%.%d+)$")
        if not integer then integer, fraction = str, "" end
        integer = integer:reverse():gsub("(%d%d%d)", "%1,")
            :reverse():gsub("^,", "")
        return integer .. fraction
    end

    local function getStageDifficulty()
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        if not gui then return nil end

        -- Difficulty selection offers choices, but RunManage/InfiniteManage
        -- display the difficulty of the actual stage.
        local infinite = ctx.ZzzzWorld and ctx.ZzzzWorld.Enabled
        local candidates = infinite
            and {"InfiniteManage", "RunManage"}
            or {"RunManage", "InfiniteManage"}

        for _, name in ipairs(candidates) do
            local manager = gui:FindFirstChild(name)
            local sheet = manager and manager:FindFirstChild("Sheet")
            local title = sheet and sheet:FindFirstChild("Title")
            local label = title and title:FindFirstChild("Info")
            if label and label:IsA("TextLabel") then
                local value = clean(label.Text):lower()
                for _, difficulty in ipairs({"Nightmare", "Hard", "Medium", "Easy"}) do
                    if value:find(difficulty:lower(), 1, true) then
                        return difficulty
                    end
                end
            end
        end
        return nil
    end

    local function getStats(holder)
        local found = {}
        local frame = holder:FindFirstChild("StatsFrame")
        local list = frame and frame:FindFirstChild("Holder")
        if not list then return found end

        for _, entry in ipairs(list:GetChildren()) do
            if entry:IsA("GuiObject") and entry.Visible then
                local title = clean(getText(entry, "Title")):gsub(":$", "")
                local value = clean(getText(entry, "Value"))
                if title ~= "" and value ~= "" then found[title] = value end
            end
        end
        return found
    end

    local function secondsOf(value)
        local h, m, s = clean(value):match("^(%d+):(%d+):(%d+)$")
        if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) end
        local min, sec = clean(value):match("^(%d+):(%d+)$")
        if min then return tonumber(min) * 60 + tonumber(sec) end
        return 0
    end

    local function readResult(screen)
        local holder = screen:FindFirstChild("Holder")
        if not holder then return nil end
        local center = holder:FindFirstChild("ConstraintedHolder")
        local result = clean(getText(center, "ResultText"))
        local upper = result:upper()
        local win = upper:find("VICTORY", 1, true) ~= nil
            or upper:find("YOU WIN", 1, true) ~= nil
        local defeat = upper:find("DEFEAT", 1, true) ~= nil
            or upper:find("YOU LOSE", 1, true) ~= nil
        if not win and not defeat then return nil end

        local stats = getStats(holder)
        local difficulty = getStageDifficulty()
        local signature = table.concat({
            result, stats["Play Time"] or "", stats["Damage Dealt"] or "",
            stats["Enemies Killed"] or "", stats["EXP Earned"] or "",
            stats["Gems Earned"] or "", difficulty or ""
        }, "\n")
        return {
            Win = win, Stats = stats, Difficulty = difficulty,
            Signature = signature
        }
    end

    local function recordSession(report)
        Session.Rounds = Session.Rounds + 1
        if report.Win then
            Session.Wins = Session.Wins + 1
        else
            Session.Losses = Session.Losses + 1
        end
        Session.EXP = Session.EXP
            + (report.RawEXP or parseNumber(report.Stats["EXP Earned"]) or 0)
        Session.GemsEarned = Session.GemsEarned
            + (report.RawGems or parseNumber(report.Stats["Gems Earned"]) or 0)
        for _, reward in ipairs(report.Rewards or {}) do
            local key = reward.Key or reward.Name
            Session.Rewards[key] =
                (Session.Rewards[key] or 0) + reward.Amount
        end
        Session.Seconds = Session.Seconds + secondsOf(report.Stats["Play Time"])
    end

    local function httpRequest()
        local env = (getgenv and getgenv()) or _G
        if type(env.request) == "function" then return env.request end
        if type(env.http_request) == "function" then return env.http_request end
        if type(request) == "function" then return request end
        if type(http_request) == "function" then return http_request end
        if type(syn) == "table" and type(syn.request) == "function" then
            return syn.request
        end
        if type(http) == "table" and type(http.request) == "function" then
            return http.request
        end
    end

    local function postEmbed(embed)
        local url = Config.Url
        if type(url) ~= "string" or not (url:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+$")
            or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$")) then
            return false, "Please enter a valid Discord webhook URL"
        end

        local requestFn = httpRequest()
        if not requestFn then
            return false, "HTTP request function is unavailable"
        end

        local body = HttpService:JSONEncode({
            username = "Slow Hub",
            content = "Player: ||" .. Player.Name .. "||",
            allowed_mentions = {parse = {}},
            embeds = {embed}
        })
        local ok, response = pcall(requestFn, {
            Url = url,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = body
        })
        if not ok then return false, "HTTP request failed" end

        local status = type(response) == "table"
            and tonumber(response.StatusCode or response.Status or response.status_code)
        if status then
            if status >= 200 and status < 300 then return true, "HTTP " .. status end
            return false, "Discord returned HTTP " .. status
        end
        if type(response) == "table" and response.Success == false then
            return false, "Request was rejected"
        end
        return nil, "Request sent; delivery status unavailable"
    end

    local function formatDuration(seconds)
        seconds = math.max(0, math.floor(seconds))
        return string.format("%02d:%02d:%02d",
            math.floor(seconds / 3600), math.floor(seconds / 60) % 60,
            seconds % 60)
    end

    local function send(report, isTest)
        local stats, options = report.Stats, Config.Fields
        local fields = {}
        local function addField(enabled, name, value, inline)
            if enabled then
                table.insert(fields, {
                    name = name,
                    value = (value and value ~= "") and tostring(value) or "N/A",
                    inline = inline ~= false
                })
            end
        end

        addField(options.Result, "Result", report.Win and "Victory" or "Defeat")
        addField(options.Duration, "Duration", stats["Play Time"])
        addField(options.Difficulty, "Difficulty", report.Difficulty or "Not detected")
        addField(options.Kills, "Enemies Killed", stats["Enemies Killed"])
        addField(options.Damage, "Damage Dealt", stats["Damage Dealt"])

        local earnedEXP = stats["EXP Earned"]
        if earnedEXP and Config.FarmTotals and not isTest then
            earnedEXP = earnedEXP .. " (" .. formatNumber(Session.EXP) .. " total)"
        end
        addField(options.EXP, "EXP Earned", earnedEXP)

        local earnedGems = stats["Gems Earned"]
        if earnedGems and Config.FarmTotals and not isTest then
            earnedGems = earnedGems .. " (" .. formatNumber(Session.GemsEarned) .. " total)"
        end
        addField(options.GemsEarned, "Gems Earned", earnedGems)

        if options.Rewards then
            local lines = {}
            for _, item in ipairs(report.Rewards or {}) do
                if options[item.Category] then
                    local earned = "+" .. formatNumber(item.Amount)
                    if Config.FarmTotals and not isTest then
                        earned = earned .. " ("
                            .. formatNumber(Session.Rewards[item.Key or item.Name]
                                or item.Amount)
                            .. " total)"
                    end
                    table.insert(lines, item.Name .. ": " .. earned)
                end
            end
            local content = #lines > 0 and table.concat(lines, "\n")
                or (report.Source == "RunStore"
                    and "No rewards in selected categories"
                    or "Rewards unavailable from UI fallback")
            if #content > 1000 then content = content:sub(1, 995) .. "..." end
            addField(true, "Rewards", content, false)
        end

        if Config.FarmTotals and not isTest then
            addField(true, "Farm Session",
                "Rounds: " .. Session.Rounds
                .. " | Victories: " .. Session.Wins
                .. " | Defeats: " .. Session.Losses
                .. "\nTotal play time: " .. formatDuration(Session.Seconds),
                false)
        end

        local payload = {
            title = isTest and "Slow Hub - Test Notification"
                or "Anime Zero - Match Results",
            color = isTest and 3447003
                or (options.Result and (report.Win and 5763719 or 15548997) or 9807270),
            description = isTest and "Test message with example match statistics and rewards." or nil,
            fields = fields,
            footer = {text = isTest and "Slow Hub • Test Notification"
                or "Slow Hub • Anime Zero"}
        }
        if #fields == 0 then
            payload.description = (payload.description or "")
                .. "\nNo fields selected for this notification."
        end
        return postEmbed(payload)
    end

    local function testReport()
        return {
            Win = true,
            Difficulty = "Hard",
            Stats = {
                ["Play Time"] = "00:05:42",
                ["Enemies Killed"] = "35",
                ["Damage Dealt"] = "1.25M",
                ["EXP Earned"] = "3900",
                ["Gems Earned"] = "200"
            },
            Source = "RunStore",
            Rewards = {
                {Name = "Coins", Category = "Coins", Amount = 1000},
                {Name = "Gems", Category = "RewardGems", Amount = 200},
                {Name = "Trait Rerolls", Category = "TraitRerolls", Amount = 3},
                {Name = "Material #101", Category = "Materials", Amount = 2}
            },
        }
    end

    Webhooks:AddSection("Farm Session")
    Webhooks:AddToggle("HxH_WebhookFarmTotals", {
        Title = "Show Accumulated Farm Totals",
        Description = "Shows accumulated farm totals",
        Default = true,
        Callback = function(value) Config.FarmTotals = value end
    })
    Webhooks:AddButton({
        Title = "Reset Farm Session",
        Description = "Resets farm totals",
        Callback = function()
            resetSession()
            Fluent:Notify({
                Title = "Farm Session",
                Content = "Accumulated farm totals reset",
                Duration = 4
            })
        end
    })

    Webhooks:AddSection("Notifications")
    Webhooks:AddButton({
        Title = "Test Webhook Notifications",
        Description = "Sends a test notification",
        Callback = function()
            task.spawn(function()
                local success, message = send(testReport(), true)
                Fluent:Notify({
                    Title = "Webhook Test",
                    Content = success == true and "Test notification sent"
                        or success == false and "Test notification failed"
                        or "Test request submitted",
                    SubContent = message,
                    Duration = 6
                })
            end)
        end
    })

    local lastRecordedAt = -math.huge
    local terminalIdentity = nil
    local terminalSince = 0
    local terminalProcessed = false
    local sourcePhase = "unavailable"
    local guiOpenedAt = 0
    local guiAlreadyReported = false
    local lastGUIReport = nil
    local lastWarnAt = -math.huge

    local function finishCapture(report)
        if not report then return end
        local now = os.clock()
        -- Prevent a GUI fallback and runStore snapshot from counting twice.
        if now - lastRecordedAt < 4 then return end

        lastRecordedAt = now
        recordSession(report)
        if Config.Enabled and Config.Url ~= "" then
            task.spawn(function()
                local success, message = send(report, false)
                if success ~= true then
                    warn("[Slow Hub] Match webhook: " .. tostring(message))
                    if success == false then
                        Fluent:Notify({
                            Title = "Match Webhook",
                            Content = "Could not send match results",
                            SubContent = message,
                            Duration = 6
                        })
                    end
                end
            end)
        end
    end

    local function observe()
        local now = os.clock()
        local ok, report, phase, identity = pcall(ctx.ReadMatchStore)
        if not ok then
            phase, report = "unavailable", nil
            if now - lastWarnAt > 20 then
                warn("[Slow Hub] runStore read failed")
                lastWarnAt = now
            end
        end
        sourcePhase = phase or "unavailable"

        if sourcePhase == "active" then
            terminalIdentity = nil
            terminalSince = 0
            terminalProcessed = false
        elseif sourcePhase == "finished" and report then
            if terminalIdentity ~= identity then
                terminalIdentity = identity
                terminalSince = now
                terminalProcessed = false
            end
            if not terminalProcessed and now - terminalSince >= 0.35 then
                terminalProcessed = true
                finishCapture(report)
            end
        end

        -- UI fallback is used only if runStore is inaccessible.
        -- It does not attempt to invent item rewards.
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local screen = gui and gui:FindFirstChild("EndScreen")
        local isOpen = screen and screen:IsA("ScreenGui") and screen.Enabled
        if isOpen then
            if guiOpenedAt == 0 then
                guiOpenedAt = now
                guiAlreadyReported = false
                lastGUIReport = nil
            end
            if sourcePhase == "unavailable" and not guiAlreadyReported then
                local found = readResult(screen)
                if found then
                    found.Source = "GUI"
                    lastGUIReport = found
                end
                if lastGUIReport and now - guiOpenedAt >= 1 then
                    guiAlreadyReported = true
                    finishCapture(lastGUIReport)
                end
            end
        else
            if guiOpenedAt > 0 and lastGUIReport
                and not guiAlreadyReported
                and sourcePhase == "unavailable" then
                finishCapture(lastGUIReport)
            end
            guiOpenedAt = 0
            guiAlreadyReported = false
            lastGUIReport = nil
        end
    end

    ctx.WebhookCaptureNow = observe
    ctx.WebhookPauseReplay = function()
        if not Config.Enabled then return false end
        local now = os.clock()
        if sourcePhase == "finished" and not terminalProcessed
            and now - terminalSince < 1.5 then
            return true
        end
        return guiOpenedAt > 0 and not guiAlreadyReported
            and now - guiOpenedAt < 1.6
    end

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            local ok, err = pcall(observe)
            if not ok and os.clock() - lastWarnAt > 20 then
                lastWarnAt = os.clock()
                warn("[Slow Hub] Match tracker: " .. tostring(err))
            end
            task.wait(0.1)
        end
    end)
end
