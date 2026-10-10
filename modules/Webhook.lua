return function(ctx)
    local S, Player, Webhooks, Fluent = ctx.S, ctx.Player, ctx.Webhooks, ctx.Fluent
    local HttpService = game:GetService("HttpService")
    local Config = {
        Enabled = false,
        Url = "",
        Fields = {
            Result = true, Duration = true, Kills = true, Damage = true,
            EXP = true, GemsEarned = true, MVP = true, Rewards = true,
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
    addFieldOption("HxH_WebhookKills", "Enemies Killed", "Kills")
    addFieldOption("HxH_WebhookDamage", "Damage Dealt", "Damage")
    addFieldOption("HxH_WebhookEXP", "EXP Earned", "EXP")
    addFieldOption("HxH_WebhookGemsEarned", "Gems Earned (Stats)", "GemsEarned")
    addFieldOption("HxH_WebhookMVP", "MVP", "MVP")
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

    local function getRewards(holder)
        local rewardFrame = holder:FindFirstChild("RewardsFrame")
        local cut = rewardFrame and rewardFrame:FindFirstChild("CutFrame")
        local grid = cut and cut:FindFirstChild("Holder")
        local result, unique = {}, {}
        if not grid then return result end

        for _, slot in ipairs(grid:GetChildren()) do
            local category = ({
                CoinSlot = "Coins",
                DiceSlot = "Dice",
                LuckyDiceSlot = "LuckyDice",
                GemsSlot = "Gems",
                EnchantGemsSlot = "EnchantGems",
                Slot = "Items"
            })[slot.Name]
            if slot:IsA("GuiObject") and slot.Visible
                and category and Config.Fields[category] then
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
            username = "AnimeZero",
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

    local function send(report, isTest)
        local stats = report.Stats
        local options = Config.Fields
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
        addField(options.Kills, "Enemies Killed", stats["Enemies Killed"])
        addField(options.Damage, "Damage Dealt", stats["Damage Dealt"])
        addField(options.EXP, "EXP Earned", stats["EXP Earned"])
        addField(options.GemsEarned, "Gems Earned", stats["Gems Earned"])
        addField(options.MVP and report.MVP ~= "", "MVP", report.MVP)

        if options.Rewards then
            local rewards = #report.Rewards > 0
                and table.concat(report.Rewards, "\n")
                or "No rewards listed"
            if #rewards > 1000 then
                rewards = rewards:sub(1, 995) .. "..."
            end
            addField(true, "Rewards", rewards, false)
        end

        local payload = {
            title = isTest and "AnimeZero - Test Notification"
                or "AnimeZero - Match Results",
            color = isTest and 3447003
                or (options.Result and (report.Win and 5763719 or 15548997) or 9807270),
            description = isTest and "Preview only - these are example values, not real drops." or nil,
            fields = fields,
            footer = {text = isTest and "Webhook connection test"
                or "EndScreen - Match completed"}
        }
        return postEmbed(payload)
    end

    local function testReport()
        local rewards = {}
        local options = Config.Fields
        if options.Coins then table.insert(rewards, "Coins ×1000") end
        if options.Dice then table.insert(rewards, "Dice ×3") end
        if options.LuckyDice then table.insert(rewards, "Lucky Dice ×1") end
        if options.Gems then table.insert(rewards, "Gems ×200") end
        if options.EnchantGems then table.insert(rewards, "Enchant Gems ×5") end
        if options.Items then table.insert(rewards, "Curse Ball ×2") end
        return {
            Win = true,
            Stats = {
                ["Play Time"] = "00:05:42",
                ["Enemies Killed"] = "35",
                ["Damage Dealt"] = "1.25M",
                ["EXP Earned"] = "3900",
                ["Gems Earned"] = "200"
            },
            MVP = "Example Player",
            Rewards = rewards
        }
    end

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
