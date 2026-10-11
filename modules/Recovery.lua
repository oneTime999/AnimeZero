return function(ctx)
    local S, C, Raid, Zzzz = ctx.S, ctx.C, ctx.Raid, ctx.ZzzzWorld
    local Player, F = ctx.Player, ctx.Functions
    local WaveCoordinates = ctx.WaveCoordinates
    local Fluent = ctx.Fluent
    local Monitor = ctx.FarmMonitor

    local EMPTY_DELAY = 30
    local DAMAGE_DELAY = 120
    local FALL_DELAY = 5
    local STEP_GAP = 30
    local FINAL_GAP = 90
    local ACTION_GAP = 15

    local mode, activeSince, lastCharacter, lastArea = nil, 0, nil, nil
    local startPosition, emptySince, fallSince = nil, nil, nil
    local lastDamageAt, lastSpawnAt = os.clock(), nil
    local lastHealth = setmetatable({}, {__mode = "k"})
    local lastSeen = setmetatable({}, {__mode = "k"})
    local lastNPCCount = 0
    local lastActionAt = -math.huge
    local stage, stallKind = 0, nil
    local warnedAfterFinal = false

    local function selectedFarm()
        if S.Enabled then return "Story" end
        if Raid.Enabled then return "Raid" end
        if Zzzz.Enabled then return "Zzz" end
        return nil
    end

    local function onResult(selected)
        if selected == "Story" and
            (S.Phase == "COMPLETED" or S.Phase == "FINAL_TELEPORT") then
            return true
        end
        if selected == "Raid" and Raid.RoundFinished then
            return true
        end
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local screen = gui and gui:FindFirstChild("EndScreen")
        return screen ~= nil and screen:IsA("ScreenGui") and screen.Enabled
    end

    local function resetProgress(now)
        emptySince, fallSince = nil, nil
        lastDamageAt = now
        lastHealth = setmetatable({}, {__mode = "k"})
        lastSeen = setmetatable({}, {__mode = "k"})
        lastNPCCount = 0
        stage, stallKind, warnedAfterFinal = 0, nil, false
        Monitor.RecoveryStage = 0
    end

    local function safePosition(selected, root)
        if selected == "Story" then
            local area = WaveCoordinates[S.BorderNumber]
            local point = area and area[1]
            if not point then
                local first = WaveCoordinates[C.FirstBorder]
                point = first and first[1]
            end
            if point then
                return CFrame.new(point + Vector3.new(0, 3, 0))
            end
        end
        -- Raid and Zzz have no validated map-wide spawn coordinates.
        -- Use the recorded starting point, updated upon respawn.
        return startPosition
    end

    local function clearCombat(selected)
        F.cancelTravel()
        F.releaseHold()
        if F.resetSkillQueue then F.resetSkillQueue() end
        S.LastM1 = 0

        if selected == "Story" then
            S.Target = nil
            S.BossTarget = nil
            S.TargetProgress = setmetatable({}, {__mode = "k"})
            S.Ignored = {}
            S.StoryPositionFailedAt = nil
        elseif selected == "Raid" then
            Raid.Target = nil
            Raid.BossGoneAt = nil
        else
            Zzzz.Target = nil
            Zzzz.LastHealth = nil
            Zzzz.LastProgressAt = nil
            Zzzz.PositionFailedAt = nil
        end
    end

    local function takeAction(selected, level, reason, root)
        local now = os.clock()
        if not S.Alive or selectedFarm() ~= selected or onResult(selected) then
            return false
        end
        if now - lastActionAt < ACTION_GAP then return false end

        local destination = safePosition(selected, root)
        if level >= 2 and not destination then
            Monitor.State = "Waiting for a safe position"
            return false
        end

        lastActionAt = now
        clearCombat(selected)

        local moved = true
        if level >= 2 then
            moved = F.setPosition(destination, 0.6, false)
        end

        if level == 3 and selected == "Story" then
            local ok, recovered = pcall(F.recoverStory,
                "watchdog: " .. reason, false)
            if not ok or not recovered then
                Monitor.LastError = "Story recovery failed"
                Monitor.LastErrorAt = now
            end
        elseif level == 3 and selected == "Raid" then
            -- Refresh targeting without falsifying a finished match.
            Raid.BossGoneAt = nil
            Raid.NextReplayAt = 0
        elseif level == 3 then
            Zzzz.LastRecoveryAt = nil
        end

        stage = level
        Monitor.RecoveryStage = level
        Monitor.Recoveries += 1
        Monitor.LastActionAt = now
        Monitor.LastReason = reason
        Monitor.State = "Recovering " .. level .. "/3"
        warn(string.format("[Slow Hub] %s recovery %d/3: %s (moved=%s)",
            selected, level, reason, tostring(moved)))
        return true
    end

    local function monitorStep()
        local now = os.clock()
        local selected = selectedFarm()
        local char, root = F.character()

        if selected ~= mode then
            mode = selected
            activeSince = now
            lastCharacter = char
            lastArea = selected == "Story"
                and (tostring(S.BorderNumber) .. "/" .. tostring(S.SubWave))
                or nil
            startPosition = selected and selected ~= "Story" and root
                and CFrame.new(root.Position + Vector3.new(0, 3, 0))
                or nil
            lastSpawnAt = nil
            Monitor.LastSpawnAt = nil
            Monitor.LastDamageAt = nil
            resetProgress(now)
            Monitor.Mode = selected or "Off"
        end

        if not selected then
            Monitor.State, Monitor.NPCs = "Idle", 0
            return
        end
        if not root then
            Monitor.State, Monitor.NPCs = "Waiting for character", 0
            return
        end
        if char ~= lastCharacter then
            lastCharacter = char
            if selected ~= "Story" then
                startPosition = CFrame.new(root.Position + Vector3.new(0, 3, 0))
            end
            activeSince = now
            resetProgress(now)
        end

        if selected == "Story" then
            local area = tostring(S.BorderNumber) .. "/" .. tostring(S.SubWave)
            if area ~= lastArea then
                lastArea = area
                activeSince = now
                resetProgress(now)
            end
        elseif not startPosition then
            startPosition = CFrame.new(root.Position + Vector3.new(0, 3, 0))
        end

        if onResult(selected) then
            Monitor.State, Monitor.NPCs = "Waiting for next match", 0
            resetProgress(now)
            return
        end

        local position = safePosition(selected, root)
        if position and root.Position.Y < position.Position.Y - 75 then
            fallSince = fallSince or now
        else
            fallSince = nil
        end
        if fallSince and now - fallSince >= FALL_DELAY then
            if takeAction(selected, 2, "fell below the map", root) then
                fallSince = nil
                resetProgress(now)
                Monitor.State = "Repositioned after falling"
            end
            return
        end

        local folder = F.enemyFolder()
        local seen = {}
        local npcs, hpKnown, tookDamage, spawned = 0, false, false, false

        local function track(npc)
            if not npc or seen[npc] or not F.living(npc) then return end
            seen[npc] = true
            npcs += 1
            local hp = F.hpOf(npc)
            local previous = lastHealth[npc]
            if not lastSeen[npc] then spawned = true end
            lastSeen[npc] = true
            if type(hp) == "number" then
                hpKnown = true
                if type(previous) == "number" and hp < previous - 0.01 then
                    tookDamage = true
                end
                lastHealth[npc] = hp
            end
        end

        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                if npc:IsA("Model") then track(npc) end
            end
        end
        if selected == "Story" and S.Phase == "KILL_BOSS" then
            track(S.BossTarget)
        end
        for npc in pairs(lastHealth) do
            if not seen[npc] then lastHealth[npc] = nil end
        end
        for npc in pairs(lastSeen) do
            if not seen[npc] then lastSeen[npc] = nil end
        end

        Monitor.NPCs = npcs
        if spawned then
            lastSpawnAt, Monitor.LastSpawnAt = now, now
        end
        -- Only actual HP loss counts as damage. New NPCs are activity,
        -- but should not mask a long period of ineffective combat.
        if tookDamage then
            lastDamageAt, Monitor.LastDamageAt = now, now
        elseif spawned and lastNPCCount == 0 then
            -- A genuinely new wave gets its own initial damage window.
            lastDamageAt = now
        end
        if tookDamage or (spawned and lastNPCCount == 0) then
            stage, stallKind, warnedAfterFinal = 0, nil, false
            Monitor.RecoveryStage = 0
        end
        lastNPCCount = npcs

        local waitingForMobs = selected ~= "Story"
            or S.Phase == "WAIT_ENEMIES" or S.Phase == "WAIT_SECOND_WAVE"
            or S.Phase == "WAIT_BOSS" or S.Phase == "KILL_ENEMIES"
            or S.Phase == "KILL_BOSS"
        local onlyImmuneBoss = selected == "Raid" and Raid.BossImmune
            and Raid.BossPresent and npcs == 1

        if waitingForMobs and (npcs == 0 or onlyImmuneBoss) then
            emptySince = emptySince or now
        else
            emptySince = nil
        end

        if now - activeSince < 15 then
            Monitor.State = "Starting farm"
            return
        end

        local noMobDelay = selected == "Story" and S.Phase == "WAIT_BOSS"
            and 65 or (selected == "Zzz" and 45 or EMPTY_DELAY)
        local cause, elapsed, threshold
        if emptySince then
            cause = "no NPCs"
            elapsed = now - emptySince
            threshold = noMobDelay
        elseif npcs > 0 and hpKnown and waitingForMobs
            and not onlyImmuneBoss then
            cause = "no NPC damage"
            elapsed = now - lastDamageAt
            threshold = DAMAGE_DELAY
        end

        if not cause then
            Monitor.State = "Running"
            return
        end

        if cause ~= stallKind then
            stallKind = cause
            stage = 0
            warnedAfterFinal = false
            Monitor.RecoveryStage = 0
        end
        if elapsed < threshold then
            Monitor.State = cause == "no NPCs"
                and ("Waiting for NPCs (" .. math.floor(elapsed) .. "s)")
                or ("Monitoring combat (" .. math.floor(elapsed) .. "s)")
            return
        end

        local expectedLevel = elapsed >= threshold + FINAL_GAP and 3
            or elapsed >= threshold + STEP_GAP and 2 or 1

        -- Run one step at a time, even when the monitor was temporarily
        -- suspended. Never spam a teleport or repeatedly flip the UI toggle.
        if expectedLevel > stage then
            takeAction(selected, stage + 1, cause, root)
        elseif stage == 3 then
            Monitor.State = "Stalled - check game/server"
            if not warnedAfterFinal then
                warnedAfterFinal = true
                warn("[Slow Hub] Farm is still stalled after all recovery steps")
            end
        else
            Monitor.State = "Watching recovery " .. stage .. "/3"
        end
    end

    task.spawn(function()
        local lastWarning = -math.huge
        while S.Alive and not (Fluent and Fluent.Unloaded) do
            task.wait(1)
            local ok, err = pcall(monitorStep)
            if not ok and os.clock() - lastWarning >= 15 then
                lastWarning = os.clock()
                Monitor.LastError = tostring(err):sub(1, 180)
                Monitor.LastErrorAt = os.clock()
                warn("[Slow Hub] Farm monitor: " .. tostring(err))
            end
        end
    end)
end
