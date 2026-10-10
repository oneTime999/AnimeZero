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
        Title = "Pcd Fnl Boss",
        SubTitle = "Story, Raids & Zzzz World",
        TabWidth = 150,
        Size = UDim2.fromOffset(570, 480),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl
    })

    local Story = Window:AddTab({Title = "Story", Icon = "book-open"})
    local Raids = Window:AddTab({Title = "Raids", Icon = "swords"})
    local ZzzzTab = Window:AddTab({Title = "Auto Zzz World", Icon = "infinity"})
    local SkillsTab = Window:AddTab({Title = "Skills", Icon = "flame"})
    local Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
    local Profiles = Window:AddTab({Title = "Profiles", Icon = "save"})

    local storyToggle
    local raidToggle
    local zzzzToggle

    Story:AddSection("HxH Story")

    storyToggle = Story:AddToggle("V11_Enable", {
        Title = "Auto HxH Story",
        Description = "Clear waves, break rubble, and defeat the final boss",
        Default = false,
        Callback = function(value)
            S.Enabled = value
            if value and Raid.Enabled then
                Raid.Enabled = false
                Raid.Target = nil
                Raid.Status = "Disabled"
                if raidToggle then raidToggle:SetValue(false) end
            end
            if value and Zzzz.Enabled and zzzzToggle then
                zzzzToggle:SetValue(false)
            end
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
                F.cancelTravel()
                F.releaseHold()
                if S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
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
        Description = "Clear mobs and attack the boss when vulnerable",
        Default = false,
        Callback = function(value)
            if value and S.Enabled then
                if storyToggle then storyToggle:SetValue(false) end
            end
            if value and Zzzz.Enabled and zzzzToggle then
                zzzzToggle:SetValue(false)
            end
            Raid.Enabled = value
            Raid.Target = nil
            Raid.BossImmune = true
            Raid.BossPresent = false
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
            Raid.ReplayUntil = 0
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
        Description = "Automatically defeat enemies as each wave spawns",
        Default = false,
        Callback = function(value)
            if value and S.Enabled and storyToggle then
                storyToggle:SetValue(false)
            end
            if value and Raid.Enabled and raidToggle then
                raidToggle:SetValue(false)
            end

            Zzzz.Enabled = value
            Zzzz.Target = nil

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

    SkillsTab:AddSection("Skill Automation")

    SkillsTab:AddToggle("V11_AutoSkills", {
        Title = "Auto Skills", Description = "Automatically use enabled abilities", Default = true,
        Callback = function(value) C.Skills = value end
    })
    SkillsTab:AddToggle("V11_SkillsOnRubble", {
        Title = "Skills on Rubble", Description = "Use abilities while breaking barriers", Default = false,
        Callback = function(value) C.SkillsOnBorder = value end
    })
    SkillsTab:AddSlider("Stable_SkillHold", {
        Title = "Key Press Duration", Description = "How long each skill key is held",
        Min = 0.02, Max = 0.4, Default = 0.06, Rounding = 2,
        Callback = function(value) C.SkillKeyHold = value end
    })

    for _, index in ipairs({4, 1, 2, 3}) do
        local skill = Skill[index]
        local section = SkillsTab:AddSection(skill.Name .. " (" .. skill.Key.Name .. ")")
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

    Settings:AddSection("Auto Replay")

    Settings:AddToggle("Stable_AutoReplay", {
        Title = "Auto Replay",
        Description = "Automatically replay Story and Raids",
        Default = true,
        Callback = function(value) C.AutoReplay = value end
    })

    Settings:AddSection("Movement")

    Settings:AddDropdown("V11_Position", {
        Title = "Enemy Position",
        Description = "Below attacks upward through the ground (requires Noclip); Behind is behind the target",
        Values = {"Behind", "Above", "Inside", "Below", "Front", "Left", "Right"},
        Default = "Behind",
        Callback = function(value) C.Position = value end
    })
    Settings:AddSlider("V11_Distance", {
        Title = "Enemy Distance", Description = "Offset from the target", Min = 1, Max = 12,
        Default = 3, Rounding = 1,
        Callback = function(value) C.Distance = value end
    })
    Settings:AddDropdown("V11_TravelMethod", {
        Title = "Travel Method",
        Description = "Tween for smooth travel, Teleport for instant moves",
        Values = {"Tween", "Teleport"},
        Default = "Tween",
        Callback = function(value) C.TravelMethod = value end
    })
    Settings:AddSlider("V11_TravelSpeed", {
        Title = "Tween Speed (studs/s)", Min = 60, Max = 300,
        Default = 170, Rounding = 0,
        Callback = function(value) C.TravelSpeed = value end
    })
    Settings:AddSection("Combat")

    Settings:AddToggle("V11_M1", {
        Title = "Auto M1", Default = true,
        Callback = function(value) C.M1 = value end
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

    Settings:AddSlider("V11_M1Delay", {
        Title = "M1 Interval", Min = 0.1, Max = 1.5,
        Default = 0.2, Rounding = 2,
        Callback = function(value) C.M1Interval = value end
    })
    Settings:AddSection("Advanced Movement")

    Settings:AddSlider("V11_TweenArc", {
        Title = "Tween Arc Height", Min = 0, Max = 25,
        Default = 10, Rounding = 0,
        Callback = function(value) C.TravelArc = value end
    })
    Settings:AddSlider("V11_RubbleAbove", {
        Title = "Height Above Rubble", Min = 1, Max = 10,
        Default = 3, Rounding = 0,
        Callback = function(value) C.RubbleAboveGap = value end
    })
    Settings:AddToggle("V11_WaveLock", {
        Title = "Hold Position During Spawn", Default = true,
        Callback = function(value)
            C.LockOnWave = value
            if not value and S.Phase == "WAIT_ENEMIES" then F.releaseHold() end
        end
    })
    Settings:AddToggle("V11_RubbleLock", {
        Title = "Hold Position on Rubble", Default = true,
        Callback = function(value)
            C.LockOnRubble = value
            if not value and S.Phase == "BREAK_RUBBLE" then F.releaseHold() end
        end
    })
    Settings:AddToggle("V11_AntiAFK", {
        Title = "Anti AFK", Default = true,
        Callback = function(value) C.AFK = value end
    })


    ctx.Fluent = Fluent
    ctx.Window = Window
    ctx.Profiles = Profiles
end
