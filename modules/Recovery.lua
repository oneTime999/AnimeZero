return function(ctx)
    local S, C, Raid, Zzzz = ctx.S, ctx.C, ctx.Raid, ctx.ZzzzWorld
    local Player, F = ctx.Player, ctx.Functions
    local Fluent = ctx.Fluent
    local Monitor = ctx.FarmMonitor
    local Guard = ctx.GameGuard
    local function guardMode(mode)
        return mode == "Raid" and "Raids" or mode
    end

    local EMPTY_DELAY = 30
    local DAMAGE_DELAY = 120
    local FALL_DELAY = 5
    local STEP_GAP = 30
    local FINAL_GAP = 90
    local ACTION_GAP = 15

    local mode, activeSince, lastCharacter = nil, 0, nil
    local startPosition, emptySince, fallSince = nil, nil, nil
    local lastDamageAt, lastSpawnAt = os.clock(), nil
    local lastHealth = setmetatable({}, {__mode = "k"})
    local lastSeen = setmetatable({}, {__mode = "k"})
    local lastNPCCount = 0
    local lastActionAt = -math.huge
    local stage, stallKind = 0, nil
    local warnedAfterFinal = false

    local function selectedFarm()
        if Raid.Enabled then return "Raid" end
        if Zzzz.Enabled then return "Zzz" end
        return nil
    end

    local function onResult(selected)
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
        -- Raid and Zzz have no validated map-wide spawn coordinates.
        -- Use the recorded starting point, updated upon respawn.
        return startPosition
    end

    local function clearCombat(selected)
        F.cancelTravel()
        F.releaseHold()
        if F.resetSkillQueue then F.resetSkillQueue() end
        S.LastM1 = 0

        if selected == "Raid" then
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
        if not S.Alive or selectedFarm() ~= selected or onResult(selected)
            or not Guard or not Guard.Allowed(guardMode(selected)) then
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

        if level == 3 and selected == "Raid" then
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
            startPosition = selected and root
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
        if not Guard or not Guard.Allowed(guardMode(selected)) then
            Monitor.State, Monitor.NPCs = "Waiting for correct match", 0
            return
        end
        if not root then
            Monitor.State, Monitor.NPCs = "Waiting for character", 0
            return
        end
        if char ~= lastCharacter then
            lastCharacter = char
            startPosition = CFrame.new(root.Position + Vector3.new(0, 3, 0))
            activeSince = now
            resetProgress(now)
        end

        if not startPosition then
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

        local waitingForMobs = true
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

        local noMobDelay = selected == "Zzz" and 45 or EMPTY_DELAY
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

    ----------------------------------------------------------------------
    -- Auto Reset watchdog (Raids and Zzz World).
    -- If no mob takes damage, or no mob is alive/spawning, for
    -- C.AutoResetDelay seconds (default 10), the character is reset and the
    -- farm carries on normally with the new character.
    ----------------------------------------------------------------------
    local wdMode, wdChar = nil, nil
    local wdDamageAt, wdEmptySince, wdLastCount = os.clock(), nil, 0
    local wdHealth = setmetatable({}, {__mode = "k"})
    local wdSeen = setmetatable({}, {__mode = "k"})
    local wdBusyUntil = 0

    local function wdReset(now)
        wdDamageAt, wdEmptySince, wdLastCount = now, nil, 0
        wdHealth = setmetatable({}, {__mode = "k"})
        wdSeen = setmetatable({}, {__mode = "k"})
    end

    local function resetCharacter(selected, reason)
        local char = Player.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return false end

        warn(string.format("[Slow Hub] Auto Reset (%s): %s", selected, reason))
        Monitor.Recoveries += 1
        Monitor.LastActionAt = os.clock()
        Monitor.LastReason = "Auto reset: " .. reason
        Monitor.State = "Resetting character"

        F.cancelTravel()
        F.releaseHold()
        if F.airUnlock then pcall(F.airUnlock) end
        if F.resetSkillQueue then F.resetSkillQueue() end
        S.LastM1 = 0

        local ok = pcall(function() humanoid.Health = 0 end)
        if not ok or humanoid.Health > 0 then
            pcall(function() char:BreakJoints() end)
        end
        return true
    end

    local function watchdogStep()
        local now = os.clock()
        local selected = selectedFarm()
        local char, root = F.character()
        local delay = math.max(tonumber(C.AutoResetDelay) or 10, 3)

        if selected ~= wdMode then
            wdMode = selected
            wdChar = char
            wdReset(now)
        end
        if not selected or not C.AutoReset or not S.Alive then
            wdReset(now)
            return
        end
        -- Spirit's Bathtub is an elevator/exploration flow, not a mob wave farm.
        if selected == "Raid" and (Raid.Variant == "Bathtub" or Raid.Interacting) then
            wdReset(now)
            return
        end
        if not Guard or not Guard.Allowed(guardMode(selected)) then
            wdReset(now)
            return
        end
        if not char or not root then
            wdChar = nil
            wdReset(now)
            return
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            wdReset(now)
            return
        end
        -- New character: give it a full window before judging it.
        if char ~= wdChar then
            wdChar = char
            wdReset(now)
            return
        end
        if now < wdBusyUntil or onResult(selected) then
            wdReset(now)
            return
        end
        -- Zzz World: only judge while the round is actually active.
        if selected == "Zzz" and ctx.ReadMatchStatus then
            local ok, status = pcall(ctx.ReadMatchStatus)
            if ok and status ~= nil and status ~= "active" then
                wdReset(now)
                return
            end
        end

        local folder = F.enemyFolder()
        local seen = {}
        local npcs, hpKnown, tookDamage, spawned = 0, false, false, false
        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                if npc:IsA("Model") and not seen[npc] and F.living(npc) then
                    seen[npc] = true
                    npcs += 1
                    if not wdSeen[npc] then spawned = true end
                    wdSeen[npc] = true
                    local hp = F.hpOf(npc)
                    if type(hp) == "number" then
                        hpKnown = true
                        local previous = wdHealth[npc]
                        if type(previous) == "number" and hp < previous - 0.01 then
                            tookDamage = true
                        end
                        wdHealth[npc] = hp
                    end
                end
            end
        end
        for npc in pairs(wdHealth) do if not seen[npc] then wdHealth[npc] = nil end end
        for npc in pairs(wdSeen) do if not seen[npc] then wdSeen[npc] = nil end end

        if tookDamage then
            wdDamageAt = now
        elseif spawned and wdLastCount == 0 then
            -- A fresh wave gets its own damage window.
            wdDamageAt = now
        end
        wdLastCount = npcs

        -- The invulnerable raid boss alone does not count as a mob to fight.
        local onlyImmuneBoss = selected == "Raid" and Raid.BossImmune
            and Raid.BossPresent and npcs == 1
        if npcs == 0 or onlyImmuneBoss then
            wdEmptySince = wdEmptySince or now
        else
            wdEmptySince = nil
        end

        local reason
        if wdEmptySince and now - wdEmptySince >= delay then
            reason = string.format("no mob spawned for %ds", math.floor(now - wdEmptySince))
        elseif npcs > 0 and not onlyImmuneBoss and hpKnown and now - wdDamageAt >= delay then
            reason = string.format("no damage dealt for %ds", math.floor(now - wdDamageAt))
        end

        if reason and resetCharacter(selected, reason) then
            -- Let the respawn happen before judging again.
            wdBusyUntil = now + 3
            wdChar = nil
            wdReset(now)
        end
    end

    task.spawn(function()
        local lastWarning = -math.huge
        while S.Alive and not (Fluent and Fluent.Unloaded) do
            task.wait(0.5)
            local ok, err = pcall(watchdogStep)
            if not ok and os.clock() - lastWarning >= 15 then
                lastWarning = os.clock()
                warn("[Slow Hub] Auto Reset watchdog: " .. tostring(err))
            end
        end
    end)
end
