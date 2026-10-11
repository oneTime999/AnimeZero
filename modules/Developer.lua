return function(ctx)
    local Guard = ctx.GameGuard
    if not Guard or not Guard.IsDeveloper() then return end

    local Tab = ctx.DeveloperTab
    local Fluent = ctx.Fluent
    local Monitor = ctx.FarmMonitor
    local F = ctx.Functions
    if not Tab or not Fluent then return end

    local function notify(title, description)
        Fluent:Notify({
            Title = title,
            Content = tostring(description),
            Duration = 6
        })
    end

    local function safeTask(callback)
        task.spawn(function()
            local ok, err = pcall(callback)
            if not ok then
                warn("[Slow Hub Dev] " .. tostring(err))
                notify("Developer Tool", "Test failed; check the console")
            end
        end)
    end

    local function copyText(value)
        local copy = setclipboard or toclipboard
        if type(copy) ~= "function" then
            warn("[Slow Hub Dev] Diagnostics:\n" .. value)
            return false
        end
        return pcall(copy, value)
    end

    Tab:AddSection("Developer Access")
    Tab:AddParagraph({
        Title = "Private Testing",
        Content = "Developer: " .. ctx.Player.Name
            .. " | Test tools are hidden from regular users. "
            .. "Use only in the correct match."
    })
    local modeInfo = Tab:AddParagraph({
        Title = "Place & Mode",
        Content = Guard.ModeName()
    })

    Tab:AddButton({
        Title = "Copy Place Diagnostics",
        Description = "Universe, Place, Workspace.Mode and guard decisions",
        Callback = function()
            if not Guard.IsDeveloper() then return end
            local copied = copyText(Guard.Diagnostics())
            notify("Place Diagnostics", copied
                and "Copied to clipboard" or "Clipboard unavailable; see console")
        end
    })

    Tab:AddButton({
        Title = "Inspect Current Farm",
        Description = "Print the current farm state without changing gameplay",
        Callback = function()
            if not Guard.IsDeveloper() then return end
            local data = {
                "Mode: " .. Guard.ModeName(),
                "Story: " .. tostring(ctx.S.Enabled) .. " | " .. tostring(ctx.S.Phase),
                "Raid: " .. tostring(ctx.Raid.Enabled) .. " | " .. tostring(ctx.Raid.Status),
                "Zzz: " .. tostring(ctx.ZzzzWorld.Enabled) .. " | "
                    .. tostring(ctx.ZzzzWorld.Status),
                "NPCs: " .. tostring(Monitor.NPCs),
                "Watchdog: " .. tostring(Monitor.State),
                "Recoveries: " .. tostring(Monitor.Recoveries),
                "Last error: " .. tostring(Monitor.LastError)
            }
            local message = table.concat(data, "\n")
            local copied = copyText(message)
            notify("Farm Inspection", copied
                and "Farm state copied" or "Farm state printed to console")
        end
    })

    Tab:AddButton({
        Title = "Inspect RunStore",
        Description = "Check the active/finished result source without sending a webhook",
        Callback = function()
            if not Guard.IsDeveloper() then return end
            safeTask(function()
                if type(ctx.ReadMatchStore) ~= "function" then
                    notify("RunStore", "RunStore reader unavailable")
                    return
                end
                local report, phase, _, err = ctx.ReadMatchStore()
                local line = "RunStore phase: " .. tostring(phase)
                    .. " | Source: " .. tostring(report and report.Source)
                    .. " | Error: " .. tostring(err)
                warn("[Slow Hub Dev] " .. line)
                notify("RunStore Inspection", line)
            end)
        end
    })

    Tab:AddSection("Recovery Tests")
    Tab:AddParagraph({
        Title = "Controlled Tests",
        Content = "Farm must be enabled in its exact match. "
            .. "Tests share the normal 15-second recovery cooldown."
    })

    for _, test in ipairs({
        {Stage = 1, Title = "Test Target Reset",
            Description = "Clear target, held position and skill queue"},
        {Stage = 2, Title = "Test Safe Reposition",
            Description = "Reset targets and move to the known safe position"},
        {Stage = 3, Title = "Test Full Recovery",
            Description = "Reposition and restore the selected farm state"}
    }) do
        Tab:AddButton({
            Title = test.Title,
            Description = test.Description,
            Callback = function()
                if not Guard.IsDeveloper() then return end
                safeTask(function()
                    if type(ctx.DevForceRecovery) ~= "function" then
                        notify("Recovery Test", "Recovery module unavailable")
                        return
                    end
                    local ok, message = ctx.DevForceRecovery(test.Stage)
                    notify(ok and "Recovery Triggered" or "Recovery Unavailable", message)
                end)
            end
        })
    end

    Tab:AddSection("Webhook Test")
    Tab:AddButton({
        Title = "Send Test Webhook",
        Description = "Send a sample result to the configured Discord webhook",
        Callback = function()
            if not Guard.IsDeveloper() then return end
            safeTask(function()
                if type(ctx.DeveloperWebhookTest) ~= "function" then
                    notify("Webhook Test", "Webhook module unavailable")
                    return
                end
                local success, message = ctx.DeveloperWebhookTest()
                notify(success == true and "Test Sent"
                    or success == false and "Test Failed"
                    or "Test Submitted", message or "No status returned")
            end)
        end
    })

    task.spawn(function()
        while ctx.S.Alive and not Fluent.Unloaded and Guard.IsDeveloper() do
            local message = Guard.ModeName() .. " | Place " .. tostring(game.PlaceId)
                .. " | Mode " .. tostring(ctx.WS:GetAttribute("Mode"))
            if modeInfo and type(modeInfo.SetDesc) == "function" then
                pcall(function() modeInfo:SetDesc(message) end)
            end
            task.wait(3)
        end
    end)
end
