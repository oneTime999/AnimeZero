return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions

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
        if S.Alive and S.Enabled then
            local ok, err = pcall(F.updateTravel)
            if not ok then
                F.cancelTravel()
                if os.clock() - lastTravelErrorAt >= 15 then
                    lastTravelErrorAt = os.clock()
                    warn("[Slow Hub] Travel recovered: " .. tostring(err))
                end
            end
        end
        if not S.Alive or not (S.Enabled or Raid.Enabled or Zzzz.Enabled) or not S.HoldCF or S.Travel then return end
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
        if S.Alive and (S.Enabled or Raid.Enabled or Zzzz.Enabled) and C.Noclip
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
        elseif mode == "Raid" then
            Raid.Status = "Retrying Raid after an error"
        else
            Zzzz.Status = "Retrying Zzz World after an error"
        end
        if now - (lastStepErrorAt[mode] or -math.huge) >= 12 then
            lastStepErrorAt[mode] = now
            warn("[Slow Hub] " .. mode .. " step error: " .. tostring(err))
            F.cancelTravel()
            F.releaseHold()
            if F.resetSkillQueue then F.resetSkillQueue() end
        end
    end

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            if ctx.EnforceFarmExclusivity then
                safeStep("Mode sync", ctx.EnforceFarmExclusivity)
            end
            if S.Enabled then
                safeStep("HUD sync", F.syncHUDProgress)
                safeStep("Story", F.step)
            end
            if Raid.Enabled then
                safeStep("Raid", F.raidStep)
            end
            if Zzzz.Enabled then
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
            if not S.Alive or not S.Enabled then
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
                        and now - phaseSince >= 35
                        and F.livingEnemyExists() then
                        pcall(F.recoverStory, "waiting for boss too long", false)
                        lastPhase = nil
                        warn("[Slow Hub] Story boss wait recovered")
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            task.wait(1)
            if S.Alive and S.Enabled and C.AutoReplay then
                local now = os.clock()
                local finishingBoss = S.Phase == "KILL_BOSS" and S.BossClearSince
                    and now - S.BossClearSince < 1.5
                local finishingStory = S.Phase == "FINAL_TELEPORT"
                    or (S.Phase == "COMPLETED" and S.FinishAt
                        and now - S.FinishAt < 1.5)
                local holdingResult = false
                if ctx.WebhookPauseReplay then
                    local ok, blocked = pcall(ctx.WebhookPauseReplay)
                    holdingResult = ok and blocked == true
                end
                if not finishingBoss and not finishingStory and not holdingResult then
                    local remote = RS:FindFirstChild("endAction")
                    if remote and remote:IsA("RemoteEvent") then
                        pcall(function()
                            remote:FireServer(buffer.fromstring("\001"))
                        end)
                    end
                end
            end
        end
    end)

end
