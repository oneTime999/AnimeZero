return function(ctx)
    local RS, RunService, VU = ctx.RS, ctx.RunService, ctx.VU
    local Player, Env = ctx.Player, ctx.Env
    local C, S, Raid = ctx.C, ctx.S, ctx.Raid
    local Zzzz = ctx.ZzzzWorld
    local Lift = ctx.Lift
    local F = ctx.Functions
    local function allowed(mode)
        return ctx.GameGuard and ctx.GameGuard.Allowed(mode) == true
    end

    local Fluent, AutoSave, SaveManager = ctx.Fluent, ctx.AutoSave or {Available = false}, ctx.SaveManager
    local afkConn = Player.Idled:Connect(function()
        if not S.Alive or not C.AFK then return end
        pcall(function()
            VU:CaptureController()
            VU:ClickButton2(Vector2.zero)
        end)
    end)

    local characterAddedConn, humanoidDiedConn

    local function queueFarmRecovery(reason)
        if not S.Alive or not (Raid.Enabled or Zzzz.Enabled or Lift.Enabled) then return end
        F.cancelTravel()
        F.releaseHold()
        if Raid.Enabled then
            Raid.Target = nil
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
            Raid.Status = "Waiting for respawn: " .. reason
        end
        if Lift.Enabled then
            Lift.Target = nil
            Lift.Status = "Waiting for respawn"
        end
        if Zzzz.Enabled then
            Zzzz.Target = nil
            Zzzz.LastHealth = nil
            Zzzz.LastProgressAt = nil
            Zzzz.PositionFailedAt = nil
            Zzzz.Status = "Waiting for respawn: " .. reason
        end
        if F.resetSkillQueue then F.resetSkillQueue() end
        S.LastM1 = 0
    end

    local function attachCharacter(character)
        if humanoidDiedConn then
            humanoidDiedConn:Disconnect()
            humanoidDiedConn = nil
        end
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 10)
        if not S.Alive or Player.Character ~= character or not humanoid then
            return
        end
        humanoidDiedConn = humanoid.Died:Connect(function()
            if Player.Character == character then
                queueFarmRecovery("character died")
            end
        end)
    end

    characterAddedConn = Player.CharacterAdded:Connect(function(character)
        if S.Alive then
            queueFarmRecovery("character respawned")
        end
        task.spawn(attachCharacter, character)
    end)
    if Player.Character then
        task.spawn(attachCharacter, Player.Character)
    end

    function S.Stop()
        if AutoSave.Available and AutoSave.Ready and AutoSave.Dirty then
            pcall(function() SaveManager:Save(AutoSave.Name) end)
        end
        Raid.Enabled = false
        Raid.Target = nil
        Zzzz.Enabled = false
        Zzzz.Target = nil
        Lift.Enabled = false
        Lift.Target = nil
        S.Alive = false
        F.cancelTravel()
        F.releaseHold()
        F.restoreCollisions()
        if S.noclipConn then S.noclipConn:Disconnect() end
        if S.holdConn then S.holdConn:Disconnect() end
        if afkConn then afkConn:Disconnect() end
        if humanoidDiedConn then humanoidDiedConn:Disconnect() end
        if characterAddedConn then characterAddedConn:Disconnect() end
        if S.UI and not S.UI.Unloaded then
            pcall(function() S.UI:Destroy() end)
        end
    end

    local lastTravelErrorAt = -math.huge
    S.holdConn = RunService.Heartbeat:Connect(function()
        if S.Alive and Lift.Enabled then
            local ok, err = pcall(F.updateTravel)
            if not ok then
                F.cancelTravel()
                if os.clock() - lastTravelErrorAt >= 15 then
                    lastTravelErrorAt = os.clock()
                    warn("[Slow Hub] Travel recovered: " .. tostring(err))
                end
            end
        end
        if not S.Alive or not S.HoldCF or S.Travel
            or not ((Raid.Enabled and allowed("Raids"))
                or (Zzzz.Enabled and allowed("Zzz")) or Lift.Enabled) then return end
        local cf = S.HoldCF
        local char, root = F.character()
        if not char or not root then return end
        pcall(function()
            if root.Anchored then root.Anchored = false end
            local drift = root.Position - cf.Position
            if drift.Magnitude > 0.45 or math.abs(drift.Y) > 0.2 then
                char:PivotTo(cf)
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end)

    S.noclipConn = RunService.Stepped:Connect(function()
        if S.Alive and C.Noclip
            and ((Raid.Enabled and allowed("Raids"))
                or (Zzzz.Enabled and allowed("Zzz")) or Lift.Enabled) then
            pcall(F.applyNoclip)
        end
    end)

    Env.PcdBehindStable = S
    Env.PcdHxHHub = S

    local lastStepErrorAt = {}
    local function safeStep(mode, callback)
        local ok, err = pcall(callback)
        if ok then return end
        local now = os.clock()
        if mode == "Raid" then
            Raid.Status = "Retrying Raid after an error"
        elseif mode == "Zzz" then
            Zzzz.Status = "Retrying Zzz World after an error"
        elseif mode == "Trial" then
            Lift.Status = "Retrying Trial after an error"
        end
        if now - (lastStepErrorAt[mode] or -math.huge) >= 12 then
            lastStepErrorAt[mode] = now
            if ctx.FarmMonitor then
                ctx.FarmMonitor.LastError = (mode .. ": " .. tostring(err)):sub(1, 180)
                ctx.FarmMonitor.LastErrorAt = now
            end
            warn("[Slow Hub] " .. mode .. " step error: " .. tostring(err))
            F.cancelTravel()
            F.releaseHold()
            if F.resetSkillQueue then F.resetSkillQueue() end
        end
    end

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            if ctx.EnforceFarmLocation then
                safeStep("Location", ctx.EnforceFarmLocation)
            end
            if ctx.EnforceFarmExclusivity then
                safeStep("Mode sync", ctx.EnforceFarmExclusivity)
            end
            if Raid.Enabled and allowed("Raids") then
                safeStep("Raid", F.raidStep)
            end
            if Zzzz.Enabled and allowed("Zzz") then
                safeStep("Zzz", F.zzzzStep)
            end
            if Lift.Enabled then
                safeStep("Trial", F.liftStep)
            end
            task.wait(0.05)
        end
    end)

    -- Rate-limited drop pickup, enabled only while a supported farm is active.
    task.spawn(function()
        local nextCollectAt = 0
        local lastWarningAt = -math.huge
        while S.Alive and not Fluent.Unloaded do
            task.wait(0.25)
            local active = (Raid.Enabled and allowed("Raids"))
                or (Zzzz.Enabled and allowed("Zzz"))
                or (Lift.Enabled and allowed("Lift"))
            local now = os.clock()
            if C.AutoCollectDrops and active and now >= nextCollectAt then
                nextCollectAt = now + 1
                local remote = RS:FindFirstChild("recoverDrop")
                if not remote then
                    local packets = RS:FindFirstChild("runPackets")
                    remote = packets and packets:FindFirstChild("recoverDrop")
                end
                if remote and remote:IsA("RemoteEvent") then
                    local ok, err = pcall(function()
                        remote:FireServer(7)
                    end)
                    if not ok and now - lastWarningAt >= 15 then
                        lastWarningAt = now
                        warn("[Slow Hub] Auto Collect Drops error: " .. tostring(err))
                    end
                elseif now - lastWarningAt >= 15 then
                    lastWarningAt = now
                    warn("[Slow Hub] Auto Collect Drops: recoverDrop RemoteEvent not found")
                end
            end
        end
    end())

    -- Raid watchdog: an enabled farm can remain on a living but
    -- unresponsive target forever without this progress check.
    task.spawn(function()
        local tracked, lastHealth, lastProgress = nil, nil, os.clock()
        local lastRepair = -math.huge
        while S.Alive and not Fluent.Unloaded do
            task.wait(0.8)
            local now = os.clock()
            if Raid.Enabled and allowed("Raids") and not Raid.RoundFinished
                and F.character() then
                local target = Raid.Target
                if target and F.living(target)
                    and not (target.Name == "0" and Raid.BossImmune) then
                    local hp = F.hpOf(target)
                    if target ~= tracked then
                        tracked, lastHealth, lastProgress = target, hp, now
                    else
                        if hp and lastHealth and hp < lastHealth - 0.01 then
                            lastProgress = now
                        end
                        lastHealth = hp
                    end
                    if now - lastProgress >= 22 and now - lastRepair >= 12 then
                        lastRepair = now
                        tracked, lastHealth, lastProgress = nil, nil, now
                        Raid.Target = nil
                        F.releaseHold()
                        if F.resetSkillQueue then F.resetSkillQueue() end
                        S.LastM1 = 0
                        Raid.Status = "Retrying stalled raid combat"
                        warn("[Slow Hub] Raid combat stalled; retrying target")
                    end
                else
                    tracked, lastHealth, lastProgress = nil, nil, now
                end
            else
                tracked, lastHealth, lastProgress = nil, nil, now
            end
        end
    end)

    -- Matches use runPackets.endAction:fire(1) for Retry.
    -- Infinite mode's participant status and EndScreenActive are more
    -- reliable than waiting for all enemies to vanish or seeing 'active'
    -- before the hub is enabled. A completed screen is sufficient.
    task.spawn(function()
        local lastReplayRequestAt = -math.huge
        local lastReplayMode = nil
        local infiniteFinishedSince = nil
        local infiniteAttempts = 0
        local lastReplayWarnAt = -math.huge

        while S.Alive and not Fluent.Unloaded do
            task.wait(0.5)
            local replayMode = (Zzzz.Enabled and allowed("Zzz")) and "Zzz" or nil
            if replayMode ~= lastReplayMode then
                lastReplayMode = replayMode
                lastReplayRequestAt = -math.huge
                infiniteFinishedSince = nil
                infiniteAttempts = 0
            end

            if S.Alive and replayMode and C.AutoReplay then
                local now = os.clock()
                local gui = Player:FindFirstChildOfClass("PlayerGui")
                local screen = gui and gui:FindFirstChild("EndScreen")
                local screenEnabled = screen and screen:IsA("ScreenGui")
                    and screen.Enabled == true
                local endActive = gui and gui:GetAttribute("EndScreenActive") == true

                local matchPhase
                if ctx.ReadMatchStore then
                    local ok, _, phase = pcall(ctx.ReadMatchStore)
                    if ok then matchPhase = phase end
                end

                local finished
                local status, travelStatus
                    if ctx.ReadMatchStatus then
                        local ok, value, _, travel = pcall(ctx.ReadMatchStatus)
                        if ok then
                            status = value
                            travelStatus = travel
                        end
                    end

                    -- The game sets EndScreenActive when the local
                    -- participant changes from active to a terminal state.
                    -- Exclude live combat regardless of transitional GUI.
                    if status == "active" then
                        infiniteFinishedSince = nil
                        infiniteAttempts = 0
                        finished = false
                    else
                        local terminal = status ~= nil and status ~= "waiting"
                            and status ~= "queued" and status ~= "active"
                        local resultVisible = endActive or screenEnabled
                        local confirmed = terminal or resultVisible
                            or (status == nil and matchPhase == "finished")
                        -- The real Retry button is disabled until the
                        -- server reports travelStatus == "idle". Sending
                        -- earlier can waste every replay attempt.
                        if status ~= nil and travelStatus ~= nil
                            and travelStatus ~= "idle" then
                            confirmed = false
                        end
                        if confirmed then
                            infiniteFinishedSince = infiniteFinishedSince or now
                            finished = now - infiniteFinishedSince >= 1
                        else
                            infiniteFinishedSince = nil
                            finished = false
                        end
                    end

                local holdingResult = false
                if ctx.WebhookPauseReplay then
                    local ok, value = pcall(ctx.WebhookPauseReplay)
                    holdingResult = ok and value == true
                end

                -- Keep retrying Zzz World until the server reports a new active round.
                -- A short interval handles delayed/laggy clients without a tight spam loop.
                local interval = 2
                if finished and not holdingResult
                    and now - lastReplayRequestAt >= interval then
                    -- The game's Retry event is nested under ReplicatedStorage.runPackets.
                    -- Resolve the actual path instead of looking only at ReplicatedStorage's root.
                    local packets = RS:FindFirstChild("runPackets")
                    local remote = packets and packets:FindFirstChild("endAction")
                    if remote and remote:IsA("RemoteEvent") then
                        lastReplayRequestAt = now
                        local ok, err = pcall(function()
                            remote:FireServer(1)
                        end)
                        if ok then
                            infiniteAttempts += 1
                            Zzzz.Status = "Retry requested ("
                                .. tostring(infiniteAttempts) .. "); waiting for next round"
                            if infiniteAttempts % 10 == 0 then
                                warn("[Slow Hub] Zzz World is still waiting for a new round; retrying")
                            end
                        elseif now - lastReplayWarnAt >= 12 then
                            lastReplayWarnAt = now
                            warn("[Slow Hub] Auto Replay error: " .. tostring(err))
                        end
                    elseif now - lastReplayWarnAt >= 12 then
                        lastReplayWarnAt = now
                        warn("[Slow Hub] Missing endAction replay RemoteEvent")
                    end
                end
            end
        end
    end)

end
