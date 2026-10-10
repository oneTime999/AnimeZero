return function(ctx)
    local S, Player, Settings = ctx.S, ctx.Player, ctx.Settings
    local HttpService = game:GetService("HttpService")
    local Config = {Enabled = false, Url = ""}

    Settings:AddSection("Match Webhook")
    Settings:AddToggle("HxH_WebhookEnabled", {
        Title = "Match Webhook",
        Description = "Send match results and rewards after EndScreen opens",
        Default = false,
        Callback = function(value) Config.Enabled = value end
    })
    Settings:AddInput("HxH_WebhookURL", {
        Title = "Discord Webhook URL",
        Description = "Saved in your local profile, never in the GitHub code",
        Default = "",
        Placeholder = "https://discord.com/api/webhooks/...",
        Finished = true,
        Callback = function(value)
            Config.Url = type(value) == "string"
                and (value:match("^%s*(.-)%s*$") or "") or ""
        end
    })

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

    local function getRewards(holder)
        local rewardFrame = holder:FindFirstChild("RewardsFrame")
        local cut = rewardFrame and rewardFrame:FindFirstChild("CutFrame")
        local grid = cut and cut:FindFirstChild("Holder")
        local result, unique = {}, {}
        if not grid then return result end

        for _, slot in ipairs(grid:GetChildren()) do
            if slot:IsA("GuiObject") and slot.Visible then
                local main = slot:FindFirstChild("Main")
                if main and main:IsA("GuiObject") and main.Visible then
                    local name = rewardNames[slot.Name]
                    if slot.Name == "Slot" then
                        name = clean(getText(main, "Txt") or getText(main, "TxtShadow"))
                    end
                    if name and name ~= "" then
                        local amount = amountOf(main)
                        local value = name .. (amount ~= "" and (" " .. amount) or "")
                        if not unique[value] then
                            unique[value] = true
                            table.insert(result, value)
                        end
                    end
                end
            end
        end
        return result
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
        if not stats["Play Time"] then return nil end
        local rewards = getRewards(holder)
        local mvp = clean(getText(center, "MVPResult"))
        local signature = table.concat({
            result, stats["Play Time"] or "", stats["Damage Dealt"] or "",
            stats["Enemies Killed"] or "", stats["EXP Earned"] or "",
            stats["Gems Earned"] or "", mvp, table.concat(rewards, "|")
        }, "\n")
        return {
            Win = win, Stats = stats, Rewards = rewards,
            MVP = mvp, Signature = signature
        }
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

    local function send(report)
        local url = Config.Url
        if not (url:match("^https://discord%.com/api/webhooks/%d+/.+")
            or url:match("^https://discordapp%.com/api/webhooks/%d+/.+")) then
            warn("[AnimeZero] Invalid Discord webhook URL")
            return
        end
        local requestFn = httpRequest()
        if not requestFn then
            warn("[AnimeZero] HTTP request is unavailable")
            return
        end

        local stats = report.Stats
        local rewards = #report.Rewards > 0
            and table.concat(report.Rewards, "\n")
            or "No rewards listed"
        if #rewards > 1000 then
            rewards = rewards:sub(1, 995) .. "..."
        end

        local fields = {
            {name = "Result", value = report.Win and "Victory" or "Defeat", inline = true},
            {name = "Duration", value = stats["Play Time"] or "N/A", inline = true},
            {name = "Enemies Killed", value = stats["Enemies Killed"] or "N/A", inline = true},
            {name = "Damage Dealt", value = stats["Damage Dealt"] or "N/A", inline = true},
            {name = "EXP Earned", value = stats["EXP Earned"] or "N/A", inline = true},
            {name = "Gems Earned", value = stats["Gems Earned"] or "N/A", inline = true},
            {name = "Rewards", value = rewards, inline = false}
        }
        if report.MVP ~= "" then
            table.insert(fields, 3, {name = "MVP", value = report.MVP, inline = true})
        end

        local json = HttpService:JSONEncode({
            username = "AnimeZero",
            allowed_mentions = {parse = {}},
            embeds = {{
                title = "AnimeZero - Match Results",
                color = report.Win and 5763719 or 15548997,
                fields = fields,
                footer = {text = "EndScreen - Match completed"}
            }}
        })
        local ok, response = pcall(requestFn, {
            Url = url, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = json
        })
        if not ok then
            warn("[AnimeZero] Could not send match webhook")
            return
        end
        local code = type(response) == "table"
            and tonumber(response.StatusCode or response.Status or response.status_code)
        if code and (code < 200 or code >= 300) then
            warn("[AnimeZero] Discord webhook HTTP " .. tostring(code))
        end
    end

    task.spawn(function()
        local lastScreen, openedAt = nil, 0
        local lastSignature, stableAt = nil, 0
        local alreadySent = false

        while S.Alive and not ctx.Fluent.Unloaded do
            local gui = Player:FindFirstChildOfClass("PlayerGui")
            local screen = gui and gui:FindFirstChild("EndScreen")
            if lastScreen ~= screen then
                lastScreen, openedAt = screen, 0
                lastSignature, stableAt = nil, 0
                alreadySent = false
            end

            if not screen or not screen:IsA("ScreenGui") or not screen.Enabled then
                openedAt, stableAt = 0, 0
                lastSignature = nil
                alreadySent = false
            else
                local now = os.clock()
                if openedAt == 0 then openedAt = now end

                if Config.Enabled and Config.Url ~= "" and not alreadySent
                    and now - openedAt >= 1.5 then
                    local report = readResult(screen)
                    if report then
                        if lastSignature ~= report.Signature then
                            lastSignature, stableAt = report.Signature, now
                        elseif now - stableAt >= 1 then
                            alreadySent = true
                            task.spawn(send, report)
                        end
                    end
                end
            end
            task.wait(0.3)
        end
    end)
end
