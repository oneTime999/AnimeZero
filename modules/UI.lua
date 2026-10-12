return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local Lift = ctx.Lift
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions
    local Guard = assert(ctx.GameGuard, "GameGuard module is required")

    local Fluent = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/oneTime999/PcdFnlBossUI/refs/heads/main/main.lua"
    ))()
    S.UI = Fluent

    local Window = Fluent:CreateWindow({
        Title = "Slow Hub",
        SubTitle = "Anime Zero",
        TabWidth = 150,
        Size = UDim2.fromOffset(570, 480),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl
    })

    local Story = Window:AddTab({Title = "Story", Icon = "book-open"})
    local Raids = Window:AddTab({Title = "Raids", Icon = "swords"})
    local ZzzzTab = Window:AddTab({Title = "Zzz World", Icon = "infinity"})
    local LiftTab = Window:AddTab({Title = "Lift", Icon = "arrow-up-down"})
    local Combat = Window:AddTab({Title = "Combat", Icon = "flame"})
    local Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
    local Webhooks = Window:AddTab({Title = "Webhooks", Icon = "bell"})
    local Profiles = Window:AddTab({Title = "Profiles", Icon = "save"})

    local storyToggle
    local raidToggle
    local zzzzToggle
    local liftToggle

    local function denyActivation(mode, toggle)
        if Guard.Allowed(mode) then return false end
        local message = Guard.Reason(mode)
        Fluent:Notify({
            Title = "Wrong Place / Mode",
            Content = message,
            Duration = 7
        })
        task.defer(function()
            if toggle and toggle.Value then toggle:SetValue(false) end
        end)
        return true
    end

    local invalidSince = {}
    ctx.EnforceFarmLocation = function()
        for _, entry in ipairs({
            {Key = "Story", State = S, Toggle = storyToggle},
            {Key = "Raids", State = Raid, Toggle = raidToggle},
            {Key = "Zzz", State = Zzzz, Toggle = zzzzToggle},
            {Key = "Lift", State = Lift, Toggle = liftToggle}
        }) do
            if entry.State.Enabled and not Guard.Allowed(entry.Key) then
                invalidSince[entry.Key] = invalidSince[entry.Key] or os.clock()
                -- Permit short round transitions before changing the saved toggle.
                -- The runtime already blocks all farm actions immediately.
                if os.clock() - invalidSince[entry.Key] >= 10 then
                    entry.State.Enabled = false
                    if entry.Toggle and entry.Toggle.Value then
                        entry.Toggle:SetValue(false)
                    end
                    invalidSince[entry.Key] = nil
                    Fluent:Notify({
                        Title = "Farm Stopped",
                        Content = Guard.Reason(entry.Key),
                        Duration = 7
                    })
                end
            else
                invalidSince[entry.Key] = nil
            end
        end
    end

    local function switchToMode(selected)
        ctx.ActiveFarmMode = selected

        if selected ~= "Story" then
            S.Enabled = false
            if storyToggle and storyToggle.Value then
                storyToggle:SetValue(false)
            end
        end

        if selected ~= "Raids" then
            Raid.Enabled = false
            Raid.Target = nil
            if raidToggle and raidToggle.Value then
                raidToggle:SetValue(false)
            end
        end

        if selected ~= "Lift" then
            Lift.Enabled = false
            Lift.Target = nil
            if liftToggle and liftToggle.Value then liftToggle:SetValue(false) end
        end

        if selected ~= "Zzz" then
            Zzzz.Enabled = false
            Zzzz.Target = nil
            if zzzzToggle and zzzzToggle.Value then
                zzzzToggle:SetValue(false)
            end
        end
    end

    ctx.EnforceFarmExclusivity = function()
        local running = (S.Enabled and 1 or 0)
            + (Raid.Enabled and 1 or 0)
            + (Zzzz.Enabled and 1 or 0)
            + (Lift.Enabled and 1 or 0)
        if running <= 1 then return end

        local selected = ctx.ActiveFarmMode
        if selected ~= "Story" and selected ~= "Raids" and selected ~= "Zzz" and selected ~= "Lift" then
            selected = S.Enabled and "Story"
                or Raid.Enabled and "Raids"
                or Lift.Enabled and "Lift"
                or "Zzz"
        end
        switchToMode(selected)
    end

    Story:AddSection("HxH Story")

    storyToggle = Story:AddToggle("V11_Enable", {
        Title = "Story Auto Farm",
        Description = "Automatically clears HxH Story waves and advances through the stage.",
        Default = false,
        Callback = function(value)
            if value and denyActivation("Story", storyToggle) then return end
            if value then switchToMode("Story") end
            S.Enabled = value
            if value then
                -- Send Story start vote only once per server, including toggle reactivation.
                local serverKey = tostring(game.JobId ~= "" and game.JobId or game.PlaceId)
                local voteKey = "AnimeZero_StoryStartVote_" .. serverKey
                if not Env[voteKey] then
                    Env[voteKey] = true
                    local startVote = RS:FindFirstChild("startVote")
                    if startVote and startVote:IsA("RemoteEvent") then
                        pcall(function() startVote:FireServer(nil) end)
                    end
                end

                S.OldModels = setmetatable({}, {__mode = "k"})
                S.OldDead = setmetatable({}, {__mode = "k"})
                S.WaveModels = {}
                S.Ignored = {}
                S.TargetProgress = setmetatable({}, {__mode = "k"})
                S.IgnoredStale = 0
                S.LastM1 = 0
                S.FinalRestored = false
                S.CachedDifficulty = nil
                S.LastDifficultyScan = 0
                for _, skill in ipairs(Skill) do
                    skill.Last = -math.huge
                end
                F.toWave(C.FirstBorder, 1)
            else
                if ctx.ActiveFarmMode == "Story" then
                    ctx.ActiveFarmMode = nil
                end
                F.cancelTravel()
                F.releaseHold()
                if not ctx.ActiveFarmMode and S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
                    local prior = C.Noclip
                    C.Noclip = false
                    F.rubblePosition(S.RubbleRef)
                    C.Noclip = prior
                end
                F.restoreCollisions()
                F.setPhase("GO_WAVE", "Disabled")
            end
        end
    })


    Raids:AddSection("Shadow Monarch")

    raidToggle = Raids:AddToggle("HxH_ShadowMonarchRaid", {
        Title = "Shadow Monarch Raid",
        Description = "Automates combat during Shadow Monarch raids.",
        Default = false,
        Callback = function(value)
            if value and denyActivation("Raids", raidToggle) then return end
            if value then switchToMode("Raids") end
            Raid.Enabled = value
            if not value and ctx.ActiveFarmMode == "Raids" then
                ctx.ActiveFarmMode = nil
            end
            Raid.Target = nil
            Raid.BossImmune = true
            Raid.BossPresent = false
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
            Raid.ReplayUntil = 0
            Raid.NextReplayAt = 0
            Raid.WebhookRoundFinishedAt = nil
            Raid.RoundFinished = false
            Raid.Status = value and "Waiting for raid enemies" or "Disabled"
            if value then
                F.cancelTravel()
                F.releaseHold()
                S.LastM1 = 0
                for _, skill in ipairs(Skill) do
                    skill.Last = -math.huge
                end
            elseif not S.Enabled then
                F.releaseHold()
                F.restoreCollisions()
            end
        end
    })


    ZzzzTab:AddSection("Infinite Waves")

    zzzzToggle = ZzzzTab:AddToggle("HxH_ZzzzWorld", {
        Title = "Zzz World Auto Farm",
        Description = "Automatically handles enemies across Infinite Waves.",
        Default = false,
        Callback = function(value)
            if value and denyActivation("Zzz", zzzzToggle) then return end
            if value then switchToMode("Zzz") end
            Zzzz.Enabled = value
            Zzzz.Target = nil
            Zzzz.LastHealth = nil
            Zzzz.LastProgressAt = nil
            Zzzz.LastRecoveryAt = nil
            Zzzz.PositionFailedAt = nil
            if not value and ctx.ActiveFarmMode == "Zzz" then
                ctx.ActiveFarmMode = nil
            end

            if value then
                F.cancelTravel()
                F.releaseHold()
                S.LastM1 = 0
                for _, skill in ipairs(Skill) do
                    skill.Last = -math.huge
                end
            elseif not S.Enabled and not Raid.Enabled then
                F.releaseHold()
                F.restoreCollisions()
            end
        end
    })

    LiftTab:AddSection("Endless Lift Waves")
    LiftTab:AddToggle("AnimeZero_LiftAutoNextFloor", {
        Title = "Auto Next Floor",
        Description = "Requests the next floor after all enemies are cleared.",
        Default = true,
        Callback = function(value)
            Lift.AutoNextFloor = value
            if not value then
                Lift.EmptySince = nil
                Lift.HadEnemies = false
            end
        end
    })

    liftToggle = LiftTab:AddToggle("AnimeZero_LiftAutoFarm", {
        Title = "Lift Auto Farm",
        Description = "Fights from a safe ground position and advances after each floor is cleared.",
        Default = false,
        Callback = function(value)
            if value then
                -- Keep the UI preference enabled across places, but only run the farm
                -- in the confirmed Lift place when its prompt is present.
                if not Guard.Allowed("Lift") then
                    Lift.Enabled = false
                    Lift.Target = nil
                    Lift.Status = "Saved, waiting for Lift place"
                    return
                end
                local world = WS:FindFirstChild("World")
                local markers = world and world:FindFirstChild("Markers")
                local lift = markers and markers:FindFirstChild("Lift")
                local prompt = lift and lift:FindFirstChildWhichIsA("ProximityPrompt", true)
                if not prompt then
                    Lift.Enabled = false
                    Lift.Target = nil
                    Lift.Status = "Waiting for Lift prompt"
                    return
                end
                switchToMode("Lift")
                Lift.Enabled = true
                Lift.Target = nil
                Lift.Status = "Starting Lift farm"
                Lift.NextPromptAt = 0
                Lift.PromptAttempts = 0
                Lift.PromptHolding = false
                Lift.PromptHoldCF = nil
                F.cancelTravel()
                F.releaseHold()
                S.LastM1 = 0
                for _, skill in ipairs(Skill) do skill.Last = -math.huge end
            else
                Lift.Enabled = false
                Lift.Target = nil
                Lift.PromptHolding = false
                Lift.PromptHoldCF = nil
                if ctx.ActiveFarmMode == "Lift" then ctx.ActiveFarmMode = nil end
                F.cancelTravel()
                F.releaseHold()
                if not S.Enabled and not Raid.Enabled and not Zzzz.Enabled then
                    F.restoreCollisions()
                end
                Lift.Status = "Disabled"
            end
        end
    })

    -- Restore the saved Lift toggle preference; execution remains place-guarded.
    task.spawn(function()
        if game.GameId ~= 10512942223 or game.PlaceId ~= 109151342576374 then
            if liftToggle and liftToggle.Value then
                Lift.Enabled = false
                Lift.Status = "Saved, waiting for Lift place"
            end
            return
        end

        local deadline = os.clock() + 30
        repeat
            if not S.Alive or Fluent.Unloaded then return end
            local world = WS:FindFirstChild("World")
            local markers = world and world:FindFirstChild("Markers")
            local lift = markers and markers:FindFirstChild("Lift")
            local prompt = lift and lift:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and liftToggle then
                task.wait(1)
                if not S.Alive or Fluent.Unloaded then return end
                if not liftToggle.Value then
                    liftToggle:SetValue(true)
                end
                return
            end
            task.wait(0.5)
        until os.clock() >= deadline

        Fluent:Notify({
            Title = "Lift Auto Farm",
            Content = "The Lift prompt was not detected. Enable the farm manually when the mode is ready.",
            Duration = 6
        })
    end)

    Combat:AddSection("Combat Automation")

    Combat:AddToggle("V11_M1", {
        Title = "Auto Basic Attack (M1)",
        Description = "Repeats basic attacks at the selected interval.", Default = true,
        Callback = function(value) C.M1 = value end
    })
    Combat:AddSlider("V11_M1Delay", {
        Title = "Attack Interval", Description = "Time between consecutive basic attacks.", Min = 0.1, Max = 1.5,
        Default = 0.2, Rounding = 2,
        Callback = function(value) C.M1Interval = value end
    })

    Combat:AddSection("Skill Automation")

    Combat:AddToggle("V11_AutoSkills", {
        Title = "Auto Skills", Description = "Automatically activates enabled skills when available.", Default = true,
        Callback = function(value) C.Skills = value end
    })
    Combat:AddToggle("V11_SkillsOnRubble", {
        Title = "Use Skills on Barriers", Description = "Allows skills to be used while breaking stage barriers.", Default = false,
        Callback = function(value) C.SkillsOnBorder = value end
    })
    Combat:AddSlider("Stable_SkillHold", {
        Title = "Skill Input Duration", Description = "Controls how long each skill key is held.",
        Min = 0.02, Max = 0.4, Default = 0.06, Rounding = 2,
        Callback = function(value) C.SkillKeyHold = value end
    })

    for _, index in ipairs({4, 1, 2, 3}) do
        local skill = Skill[index]
        local section = Combat:AddSection(skill.Name .. " (" .. skill.Key.Name .. ")")
        section:AddToggle("V11_SkillEnabled" .. index, {
            Title = "Auto " .. skill.Name, Default = true,
            Callback = function(value) skill.Enabled = value end
        })
        section:AddSlider("V11_SkillDelay" .. index, {
            Title = "Skill Cooldown Interval (s)", Min = 0.1, Max = 10,
            Default = skill.Delay, Rounding = 2,
            Callback = function(value) skill.Delay = value end
        })
    end

    Settings:AddSection("Automation")

    Settings:AddToggle("Stable_AutoReplay", {
        Title = "Auto Replay",
        Description = "Automatically starts the next run when the current match ends.",
        Default = true,
        Callback = function(value) C.AutoReplay = value end
    })

    Settings:AddSection("Combat Positioning")

    Settings:AddDropdown("V11_Position", {
        Title = "Attack Position",
        Description = "Choose where your character stays relative to the target.",
        Values = {"Behind", "Above", "Inside", "Below", "Front", "Left", "Right"},
        Default = "Below",
        Callback = function(value) C.Position = value end
    })
    Settings:AddSlider("V11_Distance", {
        Title = "Enemy Distance (studs)", Description = "Distance used for NPC targets.", Min = 1, Max = 50,
        Default = 12, Rounding = 1,
        Callback = function(value) C.Distance = value end
    })
    Settings:AddSlider("V11_RubbleDistance", {
        Title = "Rubble Distance (studs)", Description = "Separate vertical offset for Story rubble. Start at 0 and adjust gradually.", Min = 0, Max = 50,
        Default = 0, Rounding = 1,
        Callback = function(value) C.RubbleDistance = value end
    })
    Settings:AddToggle("V11_Noclip", {
        Title = "Noclip", Description = "Temporarily passes through obstacles during movement.", Default = true,
        Callback = function(value)
            C.Noclip = value
            if not value then
                if S.Enabled and S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
                    local cf = F.rubbleCFrame(S.RubbleRef)
                    if cf then F.setPosition(cf, 0.35, true) end
                end
                F.restoreCollisions()
            end
        end
    })

    Settings:AddSection("Movement")

    Settings:AddDropdown("V11_TravelMethod", {
        Title = "Movement Method",
        Description = "Choose smooth tween movement or direct teleport movement.",
        Values = {"Tween", "Teleport"},
        Default = "Tween",
        Callback = function(value) C.TravelMethod = value end
    })
    Settings:AddSlider("V11_TravelSpeed", {
        Title = "Movement Speed (studs/s)", Description = "Speed used by tween-based movement.", Min = 60, Max = 300,
        Default = 170, Rounding = 0,
        Callback = function(value) C.TravelSpeed = value end
    })
    Settings:AddSection("General Options")

    Settings:AddToggle("V11_AntiAFK", {
        Title = "Anti-AFK", Description = "Helps prevent idle disconnection.", Default = true,
        Callback = function(value) C.AFK = value end
    })

    Settings:AddSection("Live Status")
    local matchLine = Settings:AddParagraph({
        Title = "Detected Mode",
        Content = Guard.ModeName()
    })
    local statusLine = Settings:AddParagraph({
        Title = "Automation Status", Content = "Ready when a farm is enabled"
    })
    local activityLine = Settings:AddParagraph({
        Title = "Activity", Content = "Enemies detected: 0"
    })
    local recoveryLine = Settings:AddParagraph({
        Title = "Recovery", Content = "No recovery action required"
    })
    local errorLine = Settings:AddParagraph({
        Title = "Latest Error", Content = "No errors reported"
    })

    local function age(at)
        if type(at) ~= "number" then return "Never" end
        local elapsed = math.max(0, math.floor(os.clock() - at))
        if elapsed < 60 then return elapsed .. "s ago" end
        if elapsed < 3600 then return math.floor(elapsed / 60) .. "m ago" end
        return math.floor(elapsed / 3600) .. "h ago"
    end

    local lastDescriptions = {}
    local function display(element, key, value)
        if lastDescriptions[key] ~= value then
            lastDescriptions[key] = value
            if element and type(element.SetDesc) == "function" then
                element:SetDesc(value)
            end
        end
    end

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            local data = ctx.FarmMonitor
            if data then
                local ok, err = pcall(function()
                    display(matchLine, "match",
                        Guard.ModeName())
                    display(statusLine, "status",
                        tostring(data.Mode or "Off") .. " - " .. tostring(data.State or "Idle"))
                    display(activityLine, "activity",
                        "Enemies: " .. tostring(data.NPCs or 0)
                        .. " | Last damage: " .. age(data.LastDamageAt)
                        .. " | Last spawn: " .. age(data.LastSpawnAt))
                    display(recoveryLine, "recovery",
                        "Stage: " .. tostring(data.RecoveryStage or 0) .. "/3"
                        .. " | Recoveries: " .. tostring(data.Recoveries or 0)
                        .. " | Last: " .. tostring(data.LastReason or "None"))
                    display(errorLine, "error", tostring(data.LastError or "None"))
                end)
                if not ok then
                    warn("[Slow Hub] Farm monitor UI: " .. tostring(err))
                    break
                end
            end
            task.wait(2)
        end
    end)

    ctx.Fluent = Fluent
    ctx.Window = Window
    ctx.Settings = Settings
    ctx.Webhooks = Webhooks
    ctx.Profiles = Profiles
end
