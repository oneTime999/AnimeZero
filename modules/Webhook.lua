return function(ctx)
    local S, Player, Webhooks, Fluent = ctx.S, ctx.Player, ctx.Webhooks, ctx.Fluent
    local HttpService = game:GetService("HttpService")
    local Config = {
        Enabled = false,
        Url = "",
        FarmTotals = true,
        Fields = {
            Result = true, Duration = true, Difficulty = true, Kills = true, Damage = true,
            EXP = true, GemsEarned = true, Rewards = true,
            Coins = true, Dice = true, LuckyDice = true,
            Gems = true, EnchantGems = true, Items = true
        }
    }

    Webhooks:AddSection("Connection")
    Webhooks:AddToggle("HxH_WebhookEnabled", {
        Title = "Match Notifications",
        Description = "Automatically send one report when the result screen appears",
        Default = false,
        Callback = function(value) Config.Enabled = value end
    })
    Webhooks:AddInput("HxH_WebhookURL", {
        Title = "Discord Webhook URL",
        Description = "Stored in your local profile only",
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
    addFieldOption("HxH_WebhookRewards", "Include Rewards Section", "Rewards")

    Webhooks:AddSection("Reward Types")
    addFieldOption("HxH_WebhookCoins", "Coins", "Coins")
    addFieldOption("HxH_WebhookDice", "Dice", "Dice")
    addFieldOption("HxH_WebhookLuckyDice", "Lucky Dice", "LuckyDice")
    addFieldOption("HxH_WebhookGems", "Gems (Rewards)", "Gems")
    addFieldOption("HxH_WebhookEnchantGems", "Enchant Gems", "EnchantGems")
    addFieldOption("HxH_WebhookItems", "Other Item Drops", "Items")

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

    local rewardNames = {
        CoinSlot = "Coins",
        DiceSlot = "Dice",
        LuckyDiceSlot = "Lucky Dice",
        GemsSlot = "Gems",
        EnchantGemsSlot = "Enchant Gems"
    }

    local function amountOf(main)
        local amount = clean(getText(main, "Amount") or getText(main, "AmountShadow"))
        if amount == "" then return "" end
        local first = amount:sub(1, 1)
        if first == "x" or first == "X" then
            return "×" .. amount:sub(2):gsub("^%s+", "")
        end
        if amount:sub(1, 2) == "×" then return amount end
        if first == "$" then return amount end
        if amount:match("^[%d%.,]+[%a]*$") then return "×" .. amount end
        return amount
    end

    local Session = {
        Rounds = 0,
        Wins = 0,
        Losses = 0,
        Totals = {},
        EXP = 0,
        GemsEarned = 0,
        Seconds = 0,
        StartedAt = os.time()
    }

    local function resetSession()
        Session.Rounds, Session.Wins, Session.Losses = 0, 0, 0
        Session.Totals, Session.EXP, Session.GemsEarned = {}, 0, 0
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

    local slotCategories = {
        CoinSlot = "Coins",
        DiceSlot = "Dice",
        LuckyDiceSlot = "LuckyDice",
        GemsSlot = "Gems",
        EnchantGemsSlot = "EnchantGems",
        Slot = "Items"
    }

    local function isShownWithin(object, boundary)
        local cursor = object
        while cursor and cursor ~= boundary do
            if cursor:IsA("GuiObject") and not cursor.Visible then
                return false
            end
            cursor = cursor.Parent
        end
        return cursor == boundary
    end

    local function scanRewardCards(container)
        local collected, results = {}, {}
        if not container then return results end

        -- Real reward cards can be direct children or nested in a layout.
        for _, slot in ipairs(container:GetDescendants()) do
            if slot:IsA("GuiObject") and isShownWithin(slot, container) then
                local main = slot:FindFirstChild("Main")
                if main and main:IsA("GuiObject") and main.Visible then
                    local category = slotCategories[slot.Name]
                    if not category and main:FindFirstChild("AmountShadow", true) then
                        category = "Items"
                    end

                    if category then
                        local name = rewardNames[slot.Name]
                        if not name then
                            name = clean(getText(main, "Txt")
                                or getText(main, "TxtShadow")
                                or getText(main, "ItemName"))
                        end

                        local raw = clean(getText(main, "Amount")
                            or getText(main, "AmountShadow"))
                        if name and name ~= "" and (raw ~= "" or category == "Items") then
                            local amount = parseNumber(raw)
                            local key = category .. "|" .. name
                            local item = collected[key]
                            if not item then
                                item = {
                                    Name = name, Category = category,
                                    Amount = 0, Numeric = amount ~= nil, Raw = raw
                                }
                                collected[key] = item
                                table.insert(results, item)
                            end
                            if amount then
                                item.Amount = item.Amount + amount
                            else
                                item.Numeric = false
                            end
                        end
                    end
                end
            end
        end
        return results
    end

    local function getRewards(holder)
        local rewardsFrame = holder:FindFirstChild("RewardsFrame", true)
        if not rewardsFrame then return {}, "missing" end

        local cut = rewardsFrame:FindFirstChild("CutFrame")
        local grid = cut and cut:FindFirstChild("Holder")
        local rewards = scanRewardCards(grid or rewardsFrame)
        if #rewards == 0 and grid then
            rewards = scanRewardCards(rewardsFrame)
        end
        if #rewards > 0 then return rewards, "found" end

        local empty = rewardsFrame:FindFirstChild("Empty")
        if empty and empty:IsA("GuiObject") and empty.Visible then
            return {}, "empty"
        end
        return {}, "pending"
    end

    local function getProfitFallback()
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        if not gui then return {} end
        for _, managerName in ipairs({"RunManage", "InfiniteManage"}) do
            local manager = gui:FindFirstChild(managerName)
            local sheet = manager and manager:FindFirstChild("Sheet")
            local profits = sheet and sheet:FindFirstChild("Profits")
            local list = profits and profits:FindFirstChild("List")
            local result = scanRewardCards(list)
            if #result > 0 then return result end
        end
        return {}
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
        local rewards, rewardState = getRewards(holder)
        if #rewards == 0 and rewardState ~= "empty" then
            local profits = getProfitFallback()
            if #profits > 0 then
                rewards, rewardState = profits, "profits"
            end
        end
        local difficulty = getStageDifficulty()
        local rewardSignature = {}
        for _, reward in ipairs(rewards) do
            table.insert(rewardSignature, reward.Name .. ":"
                .. tostring(reward.Amount) .. ":" .. reward.Raw)
        end
        local signature = table.concat({
            result, stats["Play Time"] or "", stats["Damage Dealt"] or "",
            stats["Enemies Killed"] or "", stats["EXP Earned"] or "",
            stats["Gems Earned"] or "", difficulty or "", rewardState,
            table.concat(rewardSignature, "|")
        }, "\n")
        return {
            Win = win, Stats = stats, Rewards = rewards,
            RewardsStatus = rewardState, Difficulty = difficulty,
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
        Session.EXP = Session.EXP + (parseNumber(report.Stats["EXP Earned"]) or 0)
        Session.GemsEarned = Session.GemsEarned
            + (parseNumber(report.Stats["Gems Earned"]) or 0)
        Session.Seconds = Session.Seconds + secondsOf(report.Stats["Play Time"])
        for _, reward in ipairs(report.Rewards) do
            if reward.Numeric then
                local key = reward.Category .. "|" .. reward.Name
                Session.Totals[key] = (Session.Totals[key] or 0) + reward.Amount
            end
        end
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

    local function rewardLines(report, isTest)
        local lines = {}
        for _, item in ipairs(report.Rewards) do
            if Config.Fields[item.Category] then
                local raw = item.Raw or ""
                local label
                if item.Numeric then
                    label = "+" .. formatNumber(item.Amount)
                    if Config.FarmTotals and not isTest then
                        local key = item.Category .. "|" .. item.Name
                        label = label .. " (" .. formatNumber(Session.Totals[key] or item.Amount) .. " total)"
                    end
                else
                    label = raw ~= "" and raw or "x1"
                end
                table.insert(lines, item.Name .. ": " .. label)
            end
        end
        return lines
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
            local lines = rewardLines(report, isTest)
            local rewards = #lines > 0 and table.concat(lines, "\n")
                or (#report.Rewards > 0 and "No selected reward types matched"
                    or report.RewardsStatus == "empty" and "No rewards earned"
                    or "Rewards not captured")
            if #rewards > 1000 then
                rewards = rewards:sub(1, 995) .. "..."
            end
            addField(true, "Rewards", rewards, false)
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
            description = isTest and "Preview only - example values, not real rewards." or nil,
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
        local examples = {
            {Name = "Coins", Category = "Coins", Amount = 1000, Numeric = true, Raw = "$1000"},
            {Name = "Dice", Category = "Dice", Amount = 3, Numeric = true, Raw = "x3"},
            {Name = "Lucky Dice", Category = "LuckyDice", Amount = 1, Numeric = true, Raw = "x1"},
            {Name = "Gems", Category = "Gems", Amount = 200, Numeric = true, Raw = "x200"},
            {Name = "Enchant Gems", Category = "EnchantGems", Amount = 5, Numeric = true, Raw = "x5"},
            {Name = "Curse Ball", Category = "Items", Amount = 2, Numeric = true, Raw = "x2"}
        }
        return {
            Win = true,
            Difficulty = "Hard",
            RewardsStatus = "found",
            Stats = {
                ["Play Time"] = "00:05:42",
                ["Enemies Killed"] = "35",
                ["Damage Dealt"] = "1.25M",
                ["EXP Earned"] = "3900",
                ["Gems Earned"] = "200"
            },
            Rewards = examples
        }
    end

    Webhooks:AddSection("Farm Session")
    Webhooks:AddToggle("HxH_WebhookFarmTotals", {
        Title = "Show Accumulated Farm Totals",
        Description = "Each reward shows this round and the session total",
        Default = true,
        Callback = function(value) Config.FarmTotals = value end
    })
    Webhooks:AddButton({
        Title = "Reset Farm Session",
        Description = "Clear accumulated rewards and round counters for this server",
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
        Description = "Send a sample Discord notification using your selected fields",
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

    local watchedScreen, enabledConnection = nil, nil
    local openedAt, lastChangeAt = 0, 0
    local lastReport, lastSignature = nil, nil
    local reportedThisOpening = false
    local lastRecordedSignature, lastRecordedAt = nil, -math.huge

    local function storeBestReport(report)
        if not report then return end
        local function rank(value)
            if not value then return -1 end
            local state = value.RewardsStatus
            local weight = state == "found" and 10000
                or state == "profits" and 1000
                or state == "empty" and 100 or 0
            return weight + #value.Rewards
        end
        if rank(report) >= rank(lastReport) then
            lastReport = report
        elseif lastReport and not lastReport.Difficulty and report.Difficulty then
            lastReport.Difficulty = report.Difficulty
        end
    end

    local function finishCapture(report)
        if reportedThisOpening or not report then return end
        reportedThisOpening = true

        local now = os.clock()
        -- Avoid counting a brief hide/show animation as a second round.
        if report.Signature == lastRecordedSignature
            and now - lastRecordedAt < 4 then return end

        if #report.Rewards == 0 and report.RewardsStatus ~= "empty" then
            warn("[Slow Hub] Rewards not captured, status: "
                .. tostring(report.RewardsStatus))
        end

        recordSession(report)
        lastRecordedSignature, lastRecordedAt = report.Signature, now

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

    local function closeCapture()
        if openedAt > 0 and not reportedThisOpening then
            -- Keep the latest captured values even if replay closes the UI
            -- before the next polling interval.
            finishCapture(lastReport)
        end
        openedAt, lastChangeAt = 0, 0
        lastReport, lastSignature = nil, nil
        reportedThisOpening = false
    end

    local function observe()
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local screen = gui and gui:FindFirstChild("EndScreen")

        if screen ~= watchedScreen then
            closeCapture()
            if enabledConnection then enabledConnection:Disconnect() end
            enabledConnection = nil
            watchedScreen = screen
            if screen and screen:IsA("ScreenGui") then
                enabledConnection = screen:GetPropertyChangedSignal("Enabled"):Connect(function()
                    -- Capture on property transition, not only on a timer.
                    if not S.Alive then return end
                    if watchedScreen == screen then
                        if screen.Enabled then
                            if openedAt == 0 then openedAt = os.clock() end
                            local found = readResult(screen)
                            if found then
                                storeBestReport(found)
                                lastSignature = found.Signature
                                lastChangeAt = os.clock()
                            end
                        else
                            local final = readResult(screen)
                            if final then storeBestReport(final) end
                            closeCapture()
                        end
                    end
                end)
            end
        end

        if not screen or not screen:IsA("ScreenGui") or not screen.Enabled then
            if openedAt > 0 then closeCapture() end
            return
        end

        local now = os.clock()
        if openedAt == 0 then openedAt = now end
        if reportedThisOpening then return end
        local found = readResult(screen)
        if found then
            if found.Signature ~= lastSignature then
                lastSignature, lastChangeAt = found.Signature, now
            end
            storeBestReport(found)
        end

        if lastReport then
            local stable = now - lastChangeAt
            local age = now - openedAt
            -- Wait for reward slots to finish populating. The first
            -- EndScreen frame often has stats but no drops yet.
            local state = lastReport.RewardsStatus
            if (state == "found" and age >= 0.65 and stable >= 0.65)
                or (state == "empty" and age >= 1.15 and stable >= 0.45)
                or (age >= 2.8 and stable >= 0.4)
                or age >= 3.5 then
                finishCapture(lastReport)
            end
        end
    end

    ctx.WebhookCaptureNow = observe
    ctx.WebhookPauseReplay = function()
        observe()
        if not Config.Enabled then return false end
        return openedAt > 0 and not reportedThisOpening
            and os.clock() - openedAt < 3.5
    end

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            local ok, err = pcall(observe)
            if not ok then
                warn("[Slow Hub] EndScreen capture error: " .. tostring(err))
            end
            task.wait(0.08)
        end
        if enabledConnection then enabledConnection:Disconnect() end
    end)
end
