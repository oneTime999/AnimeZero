return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions

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
    local Combat = Window:AddTab({Title = "Combat", Icon = "flame"})
    local Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
    local Webhooks = Window:AddTab({Title = "Webhooks", Icon = "bell"})
    local Profiles = Window:AddTab({Title = "Profiles", Icon = "save"})

    local storyToggle
    local raidToggle
    local zzzzToggle

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
        if running <= 1 then return end

        local selected = ctx.ActiveFarmMode
        if selected ~= "Story" and selected ~= "Raids" and selected ~= "Zzz" then
            selected = S.Enabled and "Story"
                or Raid.Enabled and "Raids"
                or "Zzz"
        end
        switchToMode(selected)
    end

    Story:AddSection("HxH Story")

    storyToggle = Story:AddToggle("V11_Enable", {
        Title = "Auto HxH Story",
        Description = "Automatically farms Story",
        Default = false,
        Callback = function(value)
            if value then switchToMode("Story") end
            S.Enabled = value
            if value then
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
        Title = "Auto Shadow Monarch Raid",
        Description = "Automatically farms Shadow Monarch Raid",
        Default = false,
        Callback = function(value)
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
        Title = "Auto Zzz World",
        Description = "Automatically farms Zzz World",
        Default = false,
        Callback = function(value)
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

    Combat:AddSection("Basic Attacks")

    Combat:AddToggle("V11_M1", {
        Title = "Auto M1", Default = true,
        Callback = function(value) C.M1 = value end
    })
    Combat:AddSlider("V11_M1Delay", {
        Title = "M1 Interval", Min = 0.1, Max = 1.5,
        Default = 0.2, Rounding = 2,
        Callback = function(value) C.M1Interval = value end
    })

    Combat:AddSection("Automatic Skills")

    Combat:AddToggle("V11_AutoSkills", {
        Title = "Auto Skills", Description = "Uses skills automatically", Default = true,
        Callback = function(value) C.Skills = value end
    })
    Combat:AddToggle("V11_SkillsOnRubble", {
        Title = "Skills on Rubble", Description = "Uses skills on rubble", Default = false,
        Callback = function(value) C.SkillsOnBorder = value end
    })
    Combat:AddSlider("Stable_SkillHold", {
        Title = "Key Press Duration", Description = "Adjusts skill key press duration",
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
            Title = "Use Interval (seconds)", Min = 0.1, Max = 10,
            Default = skill.Delay, Rounding = 2,
            Callback = function(value) skill.Delay = value end
        })
    end

    Settings:AddSection("Farm Automation")

    Settings:AddToggle("Stable_AutoReplay", {
        Title = "Auto Replay",
        Description = "Replays matches automatically",
        Default = true,
        Callback = function(value) C.AutoReplay = value end
    })

    Settings:AddToggle("HxH_AutoCollectDrops", {
        Title = "Auto Collect Drops",
        Description = "Collects drops automatically",
        Default = false,
        Callback = function(enabled)
            C.AutoCollectDrops = enabled
        end
    })

    Settings:AddSection("Positioning")

    Settings:AddDropdown("V11_Position", {
        Title = "Enemy Position",
        Description = "Changes position around enemies",
        Values = {"Behind", "Above", "Inside", "Below", "Front", "Left", "Right"},
        Default = "Behind",
        Callback = function(value) C.Position = value end
    })
    Settings:AddSlider("V11_Distance", {
        Title = "Enemy Distance", Description = "Adjusts distance from enemies", Min = 1, Max = 12,
        Default = 3, Rounding = 1,
        Callback = function(value) C.Distance = value end
    })
    Settings:AddToggle("V11_Noclip", {
        Title = "Noclip", Default = true,
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

    Settings:AddSection("Travel")

    Settings:AddDropdown("V11_TravelMethod", {
        Title = "Travel Method",
        Description = "Changes movement method",
        Values = {"Tween", "Teleport"},
        Default = "Tween",
        Callback = function(value) C.TravelMethod = value end
    })
    Settings:AddSlider("V11_TravelSpeed", {
        Title = "Tween Speed (studs/s)", Min = 60, Max = 300,
        Default = 170, Rounding = 0,
        Callback = function(value) C.TravelSpeed = value end
    })
    Settings:AddSection("General")

    Settings:AddToggle("V11_AntiAFK", {
        Title = "Anti AFK", Default = true,
        Callback = function(value) C.AFK = value end
    })

    Settings:AddSection("Farm Monitor")
    local statusLine = Settings:AddParagraph({
        Title = "Farm Status", Content = "Waiting for farm activation"
    })
    local activityLine = Settings:AddParagraph({
        Title = "Farm Activity", Content = "NPCs: 0"
    })
    local recoveryLine = Settings:AddParagraph({
        Title = "Auto Recovery", Content = "No recovery needed"
    })
    local errorLine = Settings:AddParagraph({
        Title = "Last Error", Content = "None"
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
                    display(statusLine, "status",
                        tostring(data.Mode or "Off") .. " - " .. tostring(data.State or "Idle"))
                    display(activityLine, "activity",
                        "NPCs: " .. tostring(data.NPCs or 0)
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
