return function(ctx)
    local S, C, Raid, Zzzz = ctx.S, ctx.C, ctx.Raid, ctx.ZzzzWorld
    local Player, WS, F = ctx.Player, ctx.WS, ctx.Functions
    local WaveCoordinates = ctx.WaveCoordinates
    local Fluent = ctx.Fluent

    local EMPTY_TIMEOUT = 30
    local DAMAGE_TIMEOUT = 120
    local OUT_OF_BOUNDS_TIMEOUT = 5
    local RECOVERY_COOLDOWN = 45

    local mode, since, lastRecovery = nil, os.clock(), -math.huge
    local emptySince, lastDamageAt, fallenSince = nil, os.clock(), nil
    local lastHealth = setmetatable({}, {__mode = "k"})
    local origin = nil
    local attempts = 0

    local function activeMode()
        if S.Enabled then return "Story" end
        if Raid.Enabled then return "Raid" end
        if Zzzz.Enabled then return "Zzz" end
    end

    local function matchFinished(selected)
        if selected == "Story" and
            (S.Phase == "COMPLETED" or S.Phase == "FINAL_TELEPORT") then
            return true
        end
        if selected == "Raid" and Raid.RoundFinished then return true end

        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local screen = gui and gui:FindFirstChild("EndScreen")
        if screen and screen:IsA("ScreenGui") and screen.Enabled then
            return true
        end

        if ctx.ReadMatchStore then
            local ok, _, matchPhase = pcall(ctx.ReadMatchStore)
            if ok and matchPhase == "finished" then return true end
        end
        return false
    end

    local function stageOrigin(selected, root)
        if selected == "Story" then
            local current = S.BorderNumber
            local locations = WaveCoordinates[current]
            local point = locations and locations[1]
            if not point then
                locations = WaveCoordinates[C.FirstBorder]
                point = locations and locations[1]
            end
            if point then return CFrame.new(point + Vector3.new(0, 3, 0)) end
        end
        return origin or (root and root.CFrame)
    end

    local function resetSample(now)
        emptySince = nil
        lastDamageAt = now
        fallenSince = nil
        lastHealth = setmetatable({}, {__mode = "k"})
    end

    local function recover(selected, why, root)
        local now = os.clock()
        if now - lastRecovery < RECOVERY_COOLDOWN
            or not S.Alive or activeMode() ~= selected
            or matchFinished(selected) then
            return
        end

        local destination = stageOrigin(selected, root)
        if not destination then return end
        lastRecovery = now
        attempts += 1

        -- A recovery is not an UI toggle. Keep the selected farm enabled.
        -- Clear stale travel, held position and queued keyboard actions.
        F.cancelTravel()
        F.releaseHold()
        if F.resetSkillQueue then F.resetSkillQueue() end
        S.LastM1 = 0

        local moved = F.setPosition(destination, 0.6, false)
        if selected == "Story" then
            local ok, recovered = pcall(F.recoverStory,
                "automatic recovery: " .. why, false)
            S.Status = (ok and recovered and moved)
                and "Repositioned Story after " .. why
                or "Retrying Story recovery after " .. why
        elseif selected == "Raid" then
            Raid.Target = nil
            Raid.BossGoneAt = nil
            Raid.BossImmune = true
            Raid.NextReplayAt = 0
            Raid.Status = moved and "Repositioned Raid after " .. why
                or "Retrying Raid positioning"
        else
            Zzzz.Target = nil
            Zzzz.LastHealth = nil
            Zzzz.LastProgressAt = nil
            Zzzz.PositionFailedAt = nil
            Zzzz.Status = moved and "Repositioned Zzz World after " .. why
                or "Retrying Zzz World positioning"
        end

        resetSample(now)
        warn(string.format(
            "[Slow Hub] %s recovery #%d: %s (positioned: %s)",
            selected, attempts, why, tostring(moved)
        ))
    end

    task.spawn(function()
        while S.Alive and not (Fluent and Fluent.Unloaded) do
            task.wait(1)
            local now = os.clock()
            local currentMode = activeMode()
            local char, root = F.character()

            if currentMode ~= mode then
                mode = currentMode
                since = now
                attempts = 0
                lastRecovery = -math.huge
                origin = (currentMode ~= "Story" and root)
                    and CFrame.new(root.Position + Vector3.new(0, 3, 0))
                    or nil
                resetSample(now)
            end

            if mode and root then
                -- If the user enables Raid or Zzz before respawning, capture
                -- an actual initial position as soon as a character appears.
                if mode ~= "Story" and not origin then
                    origin = CFrame.new(root.Position + Vector3.new(0, 3, 0))
                end

                if matchFinished(mode) then
                    resetSample(now)
                else
                    local start = stageOrigin(mode, root)
                    -- A position dozens of studs below the known start
                    -- indicates a fall, not the intended "Below" attack offset.
                    if start and root.Position.Y < start.Position.Y - 75 then
                        fallenSince = fallenSince or now
                    else
                        fallenSince = nil
                    end

                    local seen = {}
                    local livingCount, hpKnown = 0, false
                    local damaged = false
                    local enemies = F.enemyFolder()

                    if enemies then
                        for _, npc in ipairs(enemies:GetChildren()) do
                            if npc:IsA("Model") and F.living(npc) then
                                seen[npc] = true
                                livingCount += 1
                                local hp = F.hpOf(npc)
                                if type(hp) == "number" then
                                    hpKnown = true
                                    local previous = lastHealth[npc]
                                    if previous and hp < previous - 0.01 then
                                        damaged = true
                                    end
                                    lastHealth[npc] = hp
                                end
                            end
                        end
                    end

                    -- Story bosses may exist outside Workspace.enemies.
                    if mode == "Story" and S.Phase == "KILL_BOSS" then
                        local boss = S.BossTarget
                        if boss and not seen[boss] and F.living(boss) then
                            livingCount += 1
                            seen[boss] = true
                            local hp = F.hpOf(boss)
                            if type(hp) == "number" then
                                hpKnown = true
                                local previous = lastHealth[boss]
                                if previous and hp < previous - 0.01 then
                                    damaged = true
                                end
                                lastHealth[boss] = hp
                            end
                        end
                    end

                    -- Remove HP samples for despawned enemies. This also
                    -- avoids retaining old identities across successive waves.
                    for npc in pairs(lastHealth) do
                        if not seen[npc] then
                            lastHealth[npc] = nil
                        end
                    end

                    if damaged then
                        lastDamageAt = now
                    end

                    local waitingForMobs = mode ~= "Story"
                        or S.Phase == "WAIT_ENEMIES"
                        or S.Phase == "WAIT_SECOND_WAVE"
                        or S.Phase == "KILL_ENEMIES"
                        or S.Phase == "KILL_BOSS"

                    if livingCount == 0 and waitingForMobs then
                        emptySince = emptySince or now
                    else
                        emptySince = nil
                    end

                    -- Ignore ordinary warm-up and post-match transitions.
                    if now - since >= 15 then
                        if fallenSince
                            and now - fallenSince >= OUT_OF_BOUNDS_TIMEOUT then
                            recover(mode, "fell below the map", root)
                        elseif emptySince and now - emptySince >= EMPTY_TIMEOUT then
                            recover(mode, "no NPCs for 30 seconds", root)
                        elseif livingCount > 0 and hpKnown
                            and not (mode == "Raid"
                                and Raid.BossImmune and livingCount == 1)
                            and now - lastDamageAt >= DAMAGE_TIMEOUT then
                            recover(mode, "no NPC damage for 120 seconds", root)
                        end
                    end
                end
            end
        end
    end)
end
