return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local Lift = ctx.Lift
    local Story = ctx.Story
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

    local Raids = Window:AddTab({Title = "Raids", Icon = "swords"})
    local ZzzzTab = Window:AddTab({Title = "Zzz World", Icon = "infinity"})
    local LiftTab = Window:AddTab({Title = "Trial", Icon = "arrow-up-down"})
    local StoryTab = Window:AddTab({Title = "Story", Icon = "map"})
    local Combat = Window:AddTab({Title = "Combat", Icon = "flame"})
    local Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
    local Webhooks = Window:AddTab({Title = "Webhooks", Icon = "bell"})
    local Profiles = Window:AddTab({Title = "Profiles", Icon = "save"})

    local raidToggle
    local zzzzToggle
    local liftToggle
    local storyToggle
    local bathtubToggle

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
            {Key = "Raids", State = Raid, Toggle = (Raid.Variant == "Bathtub" and bathtubToggle) or raidToggle},
            {Key = "Zzz", State = Zzzz, Toggle = zzzzToggle},
            {Key = "Lift", State = Lift, Toggle = liftToggle},
            {Key = "Story", State = Story, Toggle = storyToggle}
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

        if selected ~= "Raids" then
            Raid.Enabled = false
            Raid.Target = nil
            if raidToggle and raidToggle.Value then
                raidToggle:SetValue(false)
            end
            if bathtubToggle and bathtubToggle.Value then
                bathtubToggle:SetValue(false)
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

        if selected ~= "Story" then
            Story.Enabled = false
            Story.Target = nil
            if storyToggle and storyToggle.Value then storyToggle:SetValue(false) end
        end
    end

    ctx.EnforceFarmExclusivity = function()
        local running = (Raid.Enabled and 1 or 0)
            + (Zzzz.Enabled and 1 or 0)
            + (Lift.Enabled and 1 or 0)
            + (Story.Enabled and 1 or 0)
        if running <= 1 then return end

        local selected = ctx.ActiveFarmMode
        if selected ~= "Raids" and selected ~= "Zzz" and selected ~= "Lift" and selected ~= "Story" then
            selected = Raid.Enabled and "Raids"
                or Lift.Enabled and "Lift"
                or Story.Enabled and "Story"
                or "Zzz"
        end
        switchToMode(selected)
    end

    Raids:AddSection("Shadow Monarch")

    raidToggle = Raids:AddToggle("HxH_ShadowMonarchRaid", {
        Title = "Shadow Monarch Raid",
        Description = "Automated farming for Shadow Monarch raids.",
        Default = false,
        Callback = function(value)
            if value then
                if bathtubToggle and bathtubToggle.Value then bathtubToggle:SetValue(false) end
                Raid.Variant = nil
                Raid.BT, Raid.BTEndSeen, Raid.BTGoneAt = nil, false, nil
            end
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
            elseif not Zzzz.Enabled and not Lift.Enabled then
                F.releaseHold()
                F.restoreCollisions()
            end
        end
    })

    Raids:AddSection("Spirit's Bathtub")

    bathtubToggle = Raids:AddToggle("AnimeZero_SpiritsBathtub", {
        Title = "Spirit's Bathtub",
        Description = "Automated farming for Spirit's Bathtub.",
        Default = false,
        Callback = function(value)
            if value then
                if raidToggle and raidToggle.Value then raidToggle:SetValue(false) end
                Raid.Variant = "Bathtub"
                if denyActivation("Raids", bathtubToggle) then
                    Raid.Variant = nil
                    return
                end
                switchToMode("Raids")
                Raid.Enabled = true
                Raid.Target = nil
                Raid.BossImmune = true
                Raid.BossPresent = false
                Raid.BossEngaged = false
                Raid.BossGoneAt = nil
                Raid.ReplayUntil = 0
                Raid.NextReplayAt = 0
                Raid.WebhookRoundFinishedAt = nil
                Raid.RoundFinished = false
                Raid.BT, Raid.BTEndSeen, Raid.BTGoneAt = nil, false, nil
                Raid.Status = "Starting Spirit's Bathtub"
                F.cancelTravel()
                F.releaseHold()
                S.LastM1 = 0
                for _, skill in ipairs(Skill) do
                    skill.Last = -math.huge
                end
            elseif Raid.Variant == "Bathtub" then
                Raid.Enabled = false
                Raid.Target = nil
                Raid.BossEngaged = false
                Raid.BossGoneAt = nil
                Raid.RoundFinished = false
                Raid.BT, Raid.BTEndSeen, Raid.BTGoneAt = nil, false, nil
                if F.floatDisable then F.floatDisable() end
                if ctx.ActiveFarmMode == "Raids" then ctx.ActiveFarmMode = nil end
                Raid.Status = "Disabled"
                if not Zzzz.Enabled and not Lift.Enabled then
                    F.releaseHold()
                    F.restoreCollisions()
                end
            end
        end
    })


    ZzzzTab:AddSection("Infinite Waves")

    zzzzToggle = ZzzzTab:AddToggle("HxH_ZzzzWorld", {
        Title = "Zzz World Auto Farm",
        Description = "Automated farming for Infinite Waves.",
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
            elseif not Raid.Enabled and not Lift.Enabled then
                F.releaseHold()
                F.restoreCollisions()
            end
        end
    })

    LiftTab:AddSection("Endless Trial Floors")
    LiftTab:AddToggle("AnimeZero_LiftAutoNextFloor", {
        Title = "Auto Next Floor",
        Description = "Advances to the next Trial floor automatically.",
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
        Title = "Trial Auto Farm",
        Description = "Automated farming for Endless Trial.",
        Default = false,
        Callback = function(value)
            if value then
                -- Keep the UI preference enabled across places, but only run the farm
                -- in the confirmed Lift place when its prompt is present.
                if not Guard.Allowed("Lift") then
                    Lift.Enabled = false
                    Lift.Target = nil
                    Lift.Status = "Saved, waiting for Trial mode"
                    return
                end
                local world = WS:FindFirstChild("World")
                local markers = world and world:FindFirstChild("Markers")
                local lift = markers and markers:FindFirstChild("Lift")
                local prompt = lift and lift:FindFirstChildWhichIsA("ProximityPrompt", true)
                if not prompt then
                    Lift.Enabled = false
                    Lift.Target = nil
                    Lift.Status = "Waiting for Trial interaction"
                    return
                end
                switchToMode("Lift")
                Lift.Enabled = true
                Lift.Target = nil
                Lift.Status = "Starting Trial farm"
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
                if not Raid.Enabled and not Zzzz.Enabled then
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
            Title = "Trial Auto Farm",
            Content = "The Trial interaction was not detected. Enable the farm manually when the mode is ready.",
            Duration = 6
        })
    end)

    StoryTab:AddSection("Story Waves")
    storyToggle = StoryTab:AddToggle("AnimeZero_AutoStory", {
        Title = "Auto Story",
        Description = "Automated progression for Story mode.",
        Default = false,
        Callback = function(value)
            if value then
                switchToMode("Story")
                Story.Enabled = true
                Story.Target = nil
                Story.MoveEnemy = nil
                Story.MovePhase = nil
                Story.EnemyY = nil
                Story.EmptySince = nil
                Story.CurrentArea = nil
                Story.TotalAreas = nil
                Story.WaitingForWave = false
                Story.ActiveRubbleIndex = nil
                Story.RubbleWasTargeted = false
                Story.Status = "Waiting for Story HUD"
                F.cancelTravel()
                F.releaseHold()
                S.LastM1 = 0
                for _, skill in ipairs(Skill) do skill.Last = -math.huge end
                if F.resetSkillQueue then F.resetSkillQueue() end
            else
                Story.Enabled = false
                Story.Target = nil
                Story.MoveEnemy = nil
                Story.MovePhase = nil
                Story.EnemyY = nil
                Story.EmptySince = nil
                Story.CurrentArea = nil
                Story.TotalAreas = nil
                Story.WaitingForWave = false
                Story.ActiveRubbleIndex = nil
                Story.RubbleWasTargeted = false
                F.cancelTravel()
                F.releaseHold()
                if ctx.ActiveFarmMode == "Story" then ctx.ActiveFarmMode = nil end
                if not Raid.Enabled and not Zzzz.Enabled and not Lift.Enabled then F.restoreCollisions() end
                Story.Status = "Disabled"
            end
        end
    })

    StoryTab:AddToggle("AnimeZero_StoryAutoNext", {
        Title = "Auto Next",
        Description = "Advances to the next stage after completion.",
        Default = false,
        Callback = function(value) Story.AutoNext = value end
    })

    StoryTab:AddToggle("AnimeZero_StoryAutoReplay", {
        Title = "Auto Replay",
        Description = "Starts a new run after completion.",
        Default = false,
        Callback = function(value) Story.AutoReplay = value end
    })

    Combat:AddSection("Combat Automation")

    Combat:AddToggle("V11_M1", {
        Title = "Auto Basic Attack (M1)",
        Description = "Enables automatic basic attacks.", Default = true,
        Callback = function(value) C.M1 = value end
    })
    Combat:AddSlider("V11_M1Delay", {
        Title = "Attack Interval", Description = "Delay between basic attacks.", Min = 0.1, Max = 1.5,
        Default = 0.2, Rounding = 2,
        Callback = function(value) C.M1Interval = value end
    })

    Combat:AddSection("Skill Automation")

    Combat:AddToggle("V11_AutoSkills", {
        Title = "Auto Skills", Description = "Enables automatic skill usage.", Default = true,
        Callback = function(value) C.Skills = value end
    })
    Combat:AddSlider("Stable_SkillHold", {
        Title = "Skill Input Duration", Description = "Duration of each skill input.",
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
            Title = "Skill Input Interval (s)", Description = "Delay between uses of this skill.", Min = 0.1, Max = 10,
            Default = skill.Delay, Rounding = 2,
            Callback = function(value) skill.Delay = value end
        })
    end

    Settings:AddSection("Automation")

    Settings:AddToggle("Stable_AutoReplay", {
        Title = "Auto Replay",
        Description = "Starts a new run automatically after completion.",
        Default = true,
        Callback = function(value) C.AutoReplay = value end
    })

    Settings:AddToggle("Stable_AutoCollectDrops", {
        Title = "Auto Collect Drops",
        Description = "Collects drops automatically.",
        Default = false,
        Callback = function(value) C.AutoCollectDrops = value end
    })

    Settings:AddSection("Combat Positioning")

    Settings:AddDropdown("V11_Position", {
        Title = "Attack Position",
        Description = "Positioning preset for supported modes.",
        Values = {"Behind", "Above", "Inside", "Below", "Front", "Left", "Right"},
        Default = "Behind",
        Callback = function(value) C.Position = value end
    })
    Settings:AddSlider("V11_Distance", {
        Title = "Enemy Distance (studs)", Description = "Positioning distance for supported modes.", Min = 1, Max = 50,
        Default = 12, Rounding = 1,
        Callback = function(value) C.Distance = value end
    })
    Settings:AddToggle("V11_Noclip", {
        Title = "Noclip", Description = "Adjusts character collisions while a mode is active.", Default = true,
        Callback = function(value)
            C.Noclip = value
            if not value then
                F.restoreCollisions()
            end
        end
    })

    Settings:AddSection("Movement")

    Settings:AddDropdown("V11_TravelMethod", {
        Title = "Movement Method",
        Description = "Selects the movement style.",
        Values = {"Tween", "Teleport"},
        Default = "Tween",
        Callback = function(value) C.TravelMethod = value end
    })
    Settings:AddSlider("V11_TravelSpeed", {
        Title = "Movement Speed (studs/s)", Description = "Controls movement speed.", Min = 60, Max = 300,
        Default = 170, Rounding = 0,
        Callback = function(value) C.TravelSpeed = value end
    })
    Settings:AddSection("General Options")

    Settings:AddToggle("V11_AntiAFK", {
        Title = "Anti-AFK", Description = "Helps prevent idle disconnection.", Default = true,
        Callback = function(value) C.AFK = value end
    })

    ctx.Fluent = Fluent
    ctx.Window = Window
    ctx.Settings = Settings
    ctx.Webhooks = Webhooks
    ctx.Profiles = Profiles
end
