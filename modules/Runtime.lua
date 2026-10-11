return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
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
    local pendingRespawnAt, pendingReason = nil, nil
    local observedCharacter = nil

    local function queueFarmRecovery(reason)
        if not S.Alive or not (S.Enabled or Raid.Enabled or Zzzz.Enabled) then return end
        if S.Enabled then
            pendingRespawnAt = os.clock()
            pendingReason = reason
            S.Target = nil
            S.BossTarget = nil
            S.Status = "Waiting for respawn: " .. reason
        end
        F.cancelTravel()
        F.releaseHold()
        if Raid.Enabled then
            Raid.Target = nil
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
            Raid.Status = "Waiting for respawn: " .. reason
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
        observedCharacter = character
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
        if S.Enabled and S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
            local savedNoclip = C.Noclip
            C.Noclip = false
            F.rubblePosition(S.RubbleRef)
            C.Noclip = savedNoclip
        end
        S.Alive = false
        S.Enabled = false
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
        if S.Alive and S.Enabled and allowed("Story") then
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
            or not ((S.Enabled and allowed("Story"))
                or (Raid.Enabled and allowed("Raids"))
                or (Zzzz.Enabled and allowed("Zzz"))) then return end
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
            and ((S.Enabled and allowed("Story"))
                or (Raid.Enabled and allowed("Raids"))
                or (Zzzz.Enabled and allowed("Zzz")))
            and (Raid.Enabled or Zzzz.Enabled or S.Phase ~= "COMPLETED" or not S.FinalRestored) then
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
        if mode == "Story" then
            S.Status = "Retrying Story after an error"
        elseif mode == "HUD sync" then
            S.Status = "HUD refresh failed; Story still running"
        elseif mode == "Raid" then
            Raid.Status = "Retrying Raid after an error"
        elseif mode == "Zzz" then
            Zzzz.Status = "Retrying Zzz World after an error"
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
            if S.Enabled and allowed("Story") then
                safeStep("HUD sync", F.syncHUDProgress)
                safeStep("Story", F.step)
            end
            if Raid.Enabled and allowed("Raids") then
                safeStep("Raid", F.raidStep)
            end
            if Zzzz.Enabled and allowed("Zzz") then
                safeStep("Zzz", F.zzzzStep)
            end
            task.wait(0.05)
        end
    end)

    -- Watchdog keeps Auto Story enabled while repairing stale state after
    -- deaths, in-server replays and targeting failures.
    task.spawn(function()
        local lastPhase, phaseSince = nil, os.clock()
        local trackedEnemy, lastHealth, lastProgress = nil, nil, os.clock()
        local targetMissingSince = nil

        while S.Alive and not Fluent.Unloaded do
            task.wait(0.6)
            if not S.Alive or not S.Enabled or not allowed("Story") then
                trackedEnemy, lastHealth = nil, nil
                targetMissingSince = nil
                lastPhase = nil
                phaseSince = os.clock()
                pendingRespawnAt, pendingReason = nil, nil
            else
                local now = os.clock()
                local character = Player.Character
                local validCharacter = F.character() ~= nil
                if S.Phase ~= lastPhase then
                    lastPhase, phaseSince = S.Phase, now
                    trackedEnemy, lastHealth, lastProgress = nil, nil, now
                    targetMissingSince = nil
                end

                if pendingRespawnAt then
                    if validCharacter and character == observedCharacter
                        and now - pendingRespawnAt >= 0.5 then
                        local reason = pendingReason or "respawn"
                        pendingRespawnAt, pendingReason = nil, nil
                        local ok, recovered = pcall(F.recoverStory,
                            "after " .. reason, false)
                        if ok and recovered then
                            warn("[Slow Hub] Auto Story recovered after respawn")
                            trackedEnemy, lastHealth, lastProgress = nil, nil, now
                            targetMissingSince = nil
                        end
                    end
                elseif validCharacter and F.recoverStory then
                    local lastRecovery = S.StoryLastRecoveryAt or -math.huge
                    local canRecover = now - lastRecovery >= 12
                    if S.Phase == "COMPLETED" and canRecover
                        and now - (S.FinishAt or now) >= 2
                        and ctx.ReadMatchStore then
                        local ok, _, matchPhase = pcall(ctx.ReadMatchStore)
                        if ok and matchPhase == "active" then
                            pcall(F.recoverStory, "new active match", true)
                            lastPhase = nil
                            warn("[Slow Hub] Story restarted for next match")
                        end
                    elseif S.Phase == "KILL_ENEMIES"
                        or S.Phase == "KILL_BOSS" then
                        local target = S.Phase == "KILL_BOSS"
                            and S.BossTarget or S.Target
                        if target and F.living(target) then
                            local hp = F.hpOf(target)
                            if target ~= trackedEnemy then
                                trackedEnemy, lastHealth, lastProgress =
                                    target, hp, now
                            elseif hp and lastHealth and hp < lastHealth - 0.01 then
                                lastProgress = now
                            end
                            lastHealth = hp
                            targetMissingSince = nil
                            local lastAttack = math.max(
                                S.StoryLastAttackAt or phaseSince, phaseSince)
                            local attackStalled = now - lastAttack >= 12
                            local damageStalled = hp ~= nil
                                and now - lastProgress >= 22
                            if canRecover and (attackStalled or damageStalled) then
                                local reason = attackStalled
                                    and "no attack attempts" or "damage stalled"
                                pcall(F.recoverStory, reason, false)
                                trackedEnemy, lastHealth, lastProgress =
                                    nil, nil, now
                                lastPhase = nil
                                warn("[Slow Hub] Story combat recovered: " .. reason)
                            end
                        else
                            trackedEnemy, lastHealth, lastProgress =
                                nil, nil, now
                            if F.livingEnemyExists() then
                                targetMissingSince = targetMissingSince or now
                                if canRecover and now - targetMissingSince >= 10 then
                                    pcall(F.recoverStory, "lost enemy target", false)
                                    targetMissingSince = nil
                                    lastPhase = nil
                                    warn("[Slow Hub] Story target acquisition recovered")
                                end
                            else
                                targetMissingSince = nil
                            end
                        end
                    elseif S.Phase == "WAIT_BOSS" and canRecover
                        and now - phaseSince >= (F.livingEnemyExists() and 35 or 65) then
                        local ok, recovered = pcall(F.recoverStory,
                            "waiting for boss too long", false)
                        if ok and recovered then
                            lastPhase = nil
                            warn("[Slow Hub] Story boss wait recovered")
                        end
                    elseif canRecover
                        and ((S.Phase == "GO_WAVE" or S.Phase == "GO_SECOND_WAVE")
                            and now - phaseSince >= 30
                            or S.Phase == "WAIT_AREA_CHANGE"
                            and now - phaseSince >= 45
                            or S.Phase == "BREAK_RUBBLE"
                            and now - phaseSince >= 40
                            and (not S.RubbleRef
                                or not F.rubblePart(S.RubbleRef))) then
                        local reason = "stalled in " .. tostring(S.Phase)
                        local ok, recovered = pcall(F.recoverStory, reason, false)
                        if ok and recovered then
                            lastPhase = nil
                            warn("[Slow Hub] Story recovered: " .. reason)
                        end
                    end
                end
            end
        end
    end)

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
            local replayMode = (S.Enabled and allowed("Story")) and "Story"
                or ((Zzzz.Enabled and allowed("Zzz")) and "Zzz" or nil)
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
                if replayMode == "Zzz" then
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
                else
                    finished = (S.Phase == "COMPLETED"
                        and now - (S.FinishAt or now) >= 2)
                        or matchPhase == "finished" or screenEnabled
                end

                local holdingResult = false
                if ctx.WebhookPauseReplay then
                    local ok, value = pcall(ctx.WebhookPauseReplay)
                    holdingResult = ok and value == true
                end

                -- Keep retrying Zzz World until the server reports a new active round.
                -- A short interval handles delayed/laggy clients without a tight spam loop.
                local interval = replayMode == "Zzz" and 2 or 3
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
                            if replayMode == "Zzz" then
                                infiniteAttempts += 1
                                Zzzz.Status = "Retry requested (" 
                                    .. tostring(infiniteAttempts) .. "); waiting for next round"
                                if infiniteAttempts % 10 == 0 then
                                    warn("[Slow Hub] Zzz World is still waiting for a new round; retrying")
                                end
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
