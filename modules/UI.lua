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

    -- Window sized to the screen, so it fits phones as well as desktops.
    local UIS = game:GetService("UserInputService")
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local touchOnly = UIS.TouchEnabled and not UIS.KeyboardEnabled
    local windowWidth = math.clamp(viewport.X - 80, 300, 570)
    local windowHeight = math.clamp(viewport.Y - 80, 240, 480)

    local Window = Fluent:CreateWindow({
        Title = "Slow Hub",
        SubTitle = "Anime Zero",
        TabWidth = touchOnly and 110 or 150,
        Size = UDim2.fromOffset(windowWidth, windowHeight),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl,
        Icon = 113561419067782
    })

    -- The open/close circle now lives in the PcdFnlBossUI library itself
    -- (tap the minimize button to hide the window, tap the circle to restore it).

    local Raids = Window:AddTab({Title = "Raids", Icon = "swords"})
    local ZzzzTab = Window:AddTab({Title = "Zzz World", Icon = "infinity"})
    local LiftTab = Window:AddTab({Title = "Trial", Icon = "arrow-up-down"})
    local StoryTab = Window:AddTab({Title = "Story", Icon = "map"})
    local Combat = Window:AddTab({Title = "Combat", Icon = "flame"})
    local Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
    local Webhooks = Window:AddTab({Title = "Webhooks", Icon = "bell"})
    local Profiles = Window:AddTab({Title = "Interface", Icon = "save"})

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
        Title = "Auto Farm",
        Description = "Kills the enemies and the boss, then starts a new round if Auto Replay is on (Settings).",
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
        Title = "Auto Farm",
        Description = "Fights from above and takes the elevators between areas by itself. Ignores the Attack Position setting.",
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
                Raid.Interacting = false
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
                Raid.Interacting = false
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
        Title = "Auto Farm",
        Description = "Fights Infinite Waves non-stop and retries when the round ends (needs Auto Replay in Settings).",
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

    LiftTab:AddSection("Endless Trial")

    liftToggle = LiftTab:AddToggle("AnimeZero_LiftAutoFarm", {
        Title = "Auto Farm",
        Description = "Fights the Endless Trial and uses the Interact at the center of the map to go to the next floor. Only works inside the Endless Trial.",
        Default = false,
        Callback = function(value)
            if value then
                -- Keep the UI preference saved across places; the farm only runs
                -- while the player is inside the Endless Trial.
                if not Guard.Allowed("Lift") then
                    Lift.Enabled = false
                    Lift.Target = nil
                    Lift.Status = "Saved, waiting for Trial mode"
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

    -- Restore the saved Trial toggle: when the player is inside the Endless
    -- Trial it is switched back on by itself.
    task.spawn(function()
        local deadline = os.clock() + 30
        repeat
            if not S.Alive or Fluent.Unloaded then return end
            if liftToggle and liftToggle.Value and Guard.Allowed("Lift") then
                task.wait(1)
                if not S.Alive or Fluent.Unloaded then return end
                if not Lift.Enabled then
                    liftToggle:SetValue(false)
                    liftToggle:SetValue(true)
                end
                return
            end
            if liftToggle and liftToggle.Value then
                Lift.Enabled = false
                Lift.Status = "Saved, waiting for Trial mode"
            end
            task.wait(0.5)
        until os.clock() >= deadline
    end)

    StoryTab:AddSection("Story")
    storyToggle = StoryTab:AddToggle("AnimeZero_AutoStory", {
        Title = "Auto Farm",
        Description = "Clears the Story waves and moves through the areas automatically. Replay and next stage are set in Settings.",
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

    Combat:AddSection("Basic Attack")

    Combat:AddToggle("V11_M1", {
        Title = "Auto Basic Attack (M1)",
        Description = "Attacks automatically while a farm is running.",
        Default = true,
        Callback = function(value) C.M1 = value end
    })
    Combat:AddSlider("V11_M1Delay", {
        Title = "Basic Attack Interval",
        Description = "Seconds between basic attacks. Lower is faster.",
        Min = 0.1, Max = 1.5, Default = 0.2, Rounding = 2,
        Callback = function(value) C.M1Interval = value end
    })

    Combat:AddSection("Skills")

    Combat:AddToggle("V11_AutoSkills", {
        Title = "Auto Skills",
        Description = "Uses your skills automatically while a farm is running. Each skill can be turned off below.",
        Default = true,
        Callback = function(value) C.Skills = value end
    })
    Combat:AddDropdown("V11_SkillInputMethod", {
        Title = "Skill Input Method",
        Description = "How the skill keys are sent. Leave on Automatic; if skills do not fire (some mobile executors), try another.",
        Values = {"Automatic", "VirtualInputManager", "keypress"},
        Default = "Automatic",
        Callback = function(value) C.SkillInput = value end
    })
    Combat:AddSlider("Stable_SkillHold", {
        Title = "Key Press Length",
        Description = "How long each skill key is held, in seconds.",
        Min = 0.02, Max = 0.4, Default = 0.06, Rounding = 2,
        Callback = function(value) C.SkillKeyHold = value end
    })

    local keyLabel = {One = "1", Two = "2", Three = "3", G = "G"}
    local function skillLabel(skill)
        return skill.Name .. " (" .. (keyLabel[skill.Key.Name] or skill.Key.Name) .. ")"
    end

    Combat:AddSection("Skills On / Off")
    for index = 1, 4 do
        local skill = Skill[index]
        Combat:AddToggle("V11_SkillEnabled" .. index, {
            Title = skillLabel(skill),
            Description = "Use this skill automatically.",
            Default = true,
            Callback = function(value) skill.Enabled = value end
        })
    end

    Combat:AddSection("Skill Intervals")
    for index = 1, 4 do
        local skill = Skill[index]
        Combat:AddSlider("V11_SkillDelay" .. index, {
            Title = skillLabel(skill),
            Description = "Seconds between uses of this skill.",
            Min = 0.1, Max = 10, Default = skill.Delay, Rounding = 2,
            Callback = function(value) skill.Delay = value end
        })
    end

    Settings:AddSection("Farm Behavior")

    Settings:AddToggle("Stable_AutoReplay", {
        Title = "Auto Replay",
        Description = "Starts a new round automatically when one ends (Raids, Zzz World and Story).",
        Default = true,
        Callback = function(value) C.AutoReplay = value end
    })
    Settings:AddToggle("Stable_AutoNextStage", {
        Title = "Auto Next Stage",
        Description = "Story only: after clearing a stage, goes to the next one instead of replaying it.",
        Default = false,
        Callback = function(value) C.AutoNextStage = value end
    })

    Settings:AddToggle("AZ_AutoReset", {
        Title = "Auto Reset Character",
        Description = "Raids and Zzz World: resets your character if mobs are alive but nothing takes damage for the time below, or if no mob spawns for 3x that time (minimum 30s).",
        Default = true,
        Callback = function(value) C.AutoReset = value end
    })
    Settings:AddSlider("AZ_AutoResetDelay", {
        Title = "Auto Reset Time",
        Description = "Seconds without damage / without mobs before the character is reset.",
        Min = 5, Max = 60, Default = 10, Rounding = 0,
        Callback = function(value) C.AutoResetDelay = value end
    })

    Settings:AddSection("Attack Position")

    Settings:AddDropdown("V11_Position", {
        Title = "Attack Position",
        Description = "Where the character stands around the enemy. Not used by Spirit's Bathtub, which always attacks from above.",
        Values = {"Behind", "Above", "Inside", "Below", "Front", "Left", "Right"},
        Default = "Behind",
        Callback = function(value) C.Position = value end
    })
    Settings:AddSlider("V11_Distance", {
        Title = "Enemy Distance (studs)",
        Description = "Extra distance from the enemy. 0 is the closest.",
        Min = 0, Max = 50, Default = 0, Rounding = 1,
        Callback = function(value) C.Distance = value end
    })

    Settings:AddSection("Movement")

    Settings:AddDropdown("V11_TravelMethod", {
        Title = "Movement Method",
        Description = "Tween glides to the target; Teleport jumps there instantly.",
        Values = {"Tween", "Teleport"},
        Default = "Tween",
        Callback = function(value) C.TravelMethod = value end
    })
    Settings:AddSlider("V11_TravelSpeed", {
        Title = "Movement Speed (studs/s)",
        Description = "Tween speed. Has no effect when the method is Teleport.",
        Min = 60, Max = 300, Default = 170, Rounding = 0,
        Callback = function(value) C.TravelSpeed = value end
    })
    Settings:AddToggle("V11_Noclip", {
        Title = "Noclip",
        Description = "Lets the character pass through walls and floors while a farm is running.",
        Default = true,
        Callback = function(value)
            C.Noclip = value
            if not value then
                F.restoreCollisions()
            end
        end
    })

    Settings:AddSection("General")

    Settings:AddToggle("V11_AntiAFK", {
        Title = "Anti-AFK",
        Description = "Stops the game from kicking you for being idle.",
        Default = true,
        Callback = function(value) C.AFK = value end
    })

    ctx.Fluent = Fluent
    ctx.Window = Window
    ctx.Settings = Settings
    ctx.Webhooks = Webhooks
    ctx.Profiles = Profiles
end
