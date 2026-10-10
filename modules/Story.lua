return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions


    function F.setPhase(phase, message)
        if S.Phase ~= phase then
            F.cancelTravel()
            F.releaseHold()
        end
        S.Phase = phase
        S.Status = message
        S.EmptyAt = nil
        S.Target = nil
    end

    function F.secondWaveAvailable()
        local folder = F.enemyFolder()
        if not folder then return false end
        F.readDifficulty()
        local visibleWave = F.currentHUDWave()
        if visibleWave and visibleWave < 2 then return false end
        local confirmedByHUD = visibleWave and visibleWave >= 2
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and F.living(model) and F.isInCurrentWave(model) then
                local old = S.SecondWaveSnapshot[model]
                if not old then
                    return true
                end
                local hp = F.hpOf(model)
                if (old.Health ~= nil and hp ~= nil and hp > old.Health + 0.01)
                    or (not old.Alive and (hp == nil or hp > 0))
                    or confirmedByHUD then
                    return true
                end
            end
        end
        return false
    end

    function F.waitForSecondWave()
        local folder = F.enemyFolder()
        S.SecondWaveSnapshot = {}
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and F.isInCurrentWave(model) then
                    S.SecondWaveSnapshot[model] = {
                        Health = F.hpOf(model),
                        Alive = F.living(model)
                    }
                end
            end
        end
        S.SecondWaveWaitAt = os.clock()
        S.SubWave = math.min(2, S.ExpectedSubWaves)
        F.setPhase("GO_SECOND_WAVE", "Returning to spawn for wave 2")
    end

    function F.beginRubble()
        F.releaseHold()
        S.RubbleRef = nil
        S.RubbleBaseline = nil
        S.RubbleObserved = false
        S.RubbleClearSince = nil
        S.MissingRubbleAt = nil
        S.RubbleEnteredAt = os.clock()
        S.RubbleReason = ""
        S.RubbleEnemySnapshot = {}
        local folder = F.enemyFolder()
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") then
                    S.RubbleEnemySnapshot[model] = F.hpOf(model) or false
                end
            end
        end
        F.setPhase("BREAK_RUBBLE", "Moving to Rubble " .. S.BorderNumber)
    end

    function F.beginWave(finalWave)
        F.releaseHold()
        S.FinalMode = finalWave == true
        S.BossEncountered = false
        S.WaveModels = {}
        S.Ignored = {}
        S.TargetProgress = setmetatable({}, {__mode = "k"})
        S.IgnoredStale = 0
        F.setPhase("KILL_ENEMIES", finalWave
            and "Clearing final wave" or "Clearing enemies")
    end

    function F.toWave(number, wave)
        F.releaseHold()
        S.BorderNumber = number
        S.WaveNumber = wave or 1
        local points = WaveCoordinates[number]
        S.WaveCoordinate = points and points[S.WaveNumber] or nil
        S.RubbleRef = nil
        S.MissingRubbleAt = nil
        S.RubbleBaseline = nil
        S.RubbleObserved = false
        S.RubbleClearSince = nil
        S.RubbleEnemySnapshot = {}
        S.FinalMode = (number == LastEnemyWave)
        S.BossTarget = nil
        S.BossEncountered = false
        S.BossClearSince = nil
        S.BossWaitAt = 0
        S.BossSnapshot = setmetatable({}, {__mode = "k"})
        S.SubWave = 1
        S.SecondWaveSnapshot = {}
        S.SecondWaveWaitAt = 0
        S.CachedHUDWave = nil
        S.WaveModels = {}
        S.Ignored = {}
        S.TargetProgress = setmetatable({}, {__mode = "k"})
        S.IgnoredStale = 0
        S.SpawnTimeExceeded = false
        S.SpawnRetries = 0
        S.EnteredWaitAt = 0
        S.WaveVisitedAt = 0
        S.SpawnAt = 0
        S.Status = "Moving to wave " .. tostring(number)
        F.setPhase("GO_WAVE", string.format("Moving to wave %d", S.BorderNumber))
    end

    function F.snapshotOldMobs()
        for model in pairs(S.WaveModels) do
            if model and model.Parent then
                S.OldModels[model] = true
                local hp = F.hpOf(model)
                S.OldDead[model] = (hp ~= nil and hp <= 0)
            end
        end
    end

    function F.afterRubble()
        F.releaseHold()
        F.snapshotOldMobs()

        if S.BorderNumber <= LastBorder then
            local oldArea = S.BorderNumber
            local now = os.clock()
            if S.HUDDisplayedArea == oldArea and now - S.HUDLastSeen < 1.5 then
                F.setPhase("WAIT_AREA_CHANGE", "Rubble cleared; waiting for the game to advance")
            else
                S.HUDPreviousArea = oldArea
                S.HUDSyncGraceUntil = now + 1.5
                F.toWave(oldArea + 1, 1)
            end
        end
    end

    function F.bossCandidates()
        local result = {}
        local seen = {}
        local function add(model)
            if model and model:IsA("Model") and not seen[model] then
                seen[model] = true
                table.insert(result, model)
            end
        end

        local enemies = F.enemyFolder()
        if enemies then
            for _, child in ipairs(enemies:GetChildren()) do
                add(child)
            end
        end

        for _, name in ipairs({"Boss", "boss", "Bosses", "bosses"}) do
            local folder = WS:FindFirstChild(name)
            if folder then
                add(folder)
                for _, child in ipairs(folder:GetChildren()) do
                    add(child)
                end
            end
        end
        return result
    end

    function F.bossNearFinal(model)
        local part = F.partOf(model)
        if not part then return false end
        local spawn = WaveCoordinates[LastEnemyWave][1]
        return (part.Position - spawn).Magnitude <= math.max(C.WaveRadius, 170)
    end

    function F.bossNamed(model)
        return model.Name:lower():find("boss", 1, true) ~= nil
            or model.Name:lower():find("chefao", 1, true) ~= nil
    end

    function F.beginBossWait()
        S.BossSnapshot = setmetatable({}, {__mode = "k"})
        for _, model in ipairs(F.bossCandidates()) do
            if F.bossNearFinal(model) then
                S.BossSnapshot[model] = {
                    WasAlive = F.living(model),
                    HP = F.hpOf(model)
                }
            end
        end
        S.BossTarget = nil
        S.BossClearSince = nil
        S.BossWaitAt = os.clock()
        F.setPhase("WAIT_BOSS", "Final wave cleared; waiting for boss")
    end

    function F.findSpawnedBoss()
        local nearest, nearestDist = nil, math.huge
        local _, root = F.character()
        if not root then return nil end
        for _, model in ipairs(F.bossCandidates()) do
            if F.living(model) and F.bossNearFinal(model) then
                local earlier = S.BossSnapshot[model]
                local hp = F.hpOf(model)
                local revived = earlier and not earlier.WasAlive
                    and (hp == nil or hp > 0)
                local newlySpawned = earlier == nil
                local explicitlyBoss = F.bossNamed(model)
                if newlySpawned or revived or explicitlyBoss then
                    local part = F.partOf(model)
                    local dist = (root.Position - part.Position).Magnitude
                    if dist < nearestDist then
                        nearest = model
                        nearestDist = dist
                    end
                end
            end
        end
        return nearest
    end

    function F.syncHUDProgress()
        F.readDifficulty()
        local now = os.clock()
        local area = S.HUDDisplayedArea
        if not area or area < 1 or area > LastEnemyWave
            or now - S.HUDLastSeen > 1.5 then
            S.HUDSyncCandidate = nil
            return
        end

        if S.HUDSyncCandidate ~= area then
            S.HUDSyncCandidate = area
            S.HUDSyncSince = now
            return
        end
        if now - S.HUDSyncSince < 0.25 then return end

        if area ~= S.BorderNumber then
            if now < S.HUDSyncGraceUntil and area == S.HUDPreviousArea then
                return
            end
            S.HUDSyncGraceUntil = 0
            S.HUDPreviousArea = nil
            S.OldModels = setmetatable({}, {__mode = "k"})
            S.OldDead = setmetatable({}, {__mode = "k"})
            S.LastM1 = 0
            F.toWave(area, 1)
            S.Status = "Area " .. area .. " confirmed by game"
            return
        end

        local displayedWave = F.currentHUDWave()
        if displayedWave and displayedWave > S.SubWave
            and displayedWave <= S.ExpectedSubWaves
            and S.Phase ~= "KILL_BOSS" and S.Phase ~= "WAIT_BOSS"
            and S.Phase ~= "FINAL_TELEPORT" and S.Phase ~= "COMPLETED" then
            S.SubWave = displayedWave
            S.TargetProgress = setmetatable({}, {__mode = "k"})
            S.Ignored = {}
            F.setPhase("GO_WAVE", string.format(
                "Game advanced to wave %d/%d", displayedWave, S.ExpectedSubWaves
            ))
        end
    end

    function F.step()
        if not S.Enabled then return end
        if not F.character() then
            F.releaseHold()
            S.Status = "Waiting for character"
            return
        end

        if S.Phase == "GO_WAVE" then
            F.readDifficulty()
            if not S.WaveCoordinate then
                S.Status = "Wave destination unavailable"
                return
            end

            local dest = CFrame.new(S.WaveCoordinate)
            local tag = "NPCs " .. tostring(S.BorderNumber)
            if not F.travelTo(dest, tag) then
                if not S.Travel then S.Status = "Preparing " .. tag end
                return
            end

            S.WaveVisitedAt = os.clock()
            S.SpawnAt = S.WaveVisitedAt + C.SpawnDelay
            S.EnteredWaitAt = S.WaveVisitedAt
            F.setPhase("WAIT_ENEMIES", string.format(
                "Wave %d: waiting for enemies", S.BorderNumber
            ))
            if C.LockOnWave then S.HoldCF = dest end
            return
        end


        if S.Phase == "WAIT_ENEMIES" then
            S.Status = string.format("Wave %d: waiting for enemies", S.BorderNumber)
            if os.clock() < S.SpawnAt then return end
            if F.findActiveEnemy() then
                F.beginWave(S.BorderNumber == LastEnemyWave)
            elseif F.livingEnemyExists() then
                S.Status = "Active enemies detected; acquiring target"
            elseif os.clock() - S.EnteredWaitAt >= (S.BorderNumber == 1
                and S.SubWave == 1 and C.FirstWaveSpawnWait or C.MaxSpawnWait) then
                F.readDifficulty()
                local hudWave = F.currentHUDWave()
                if S.FinalMode and S.SubWave < S.ExpectedSubWaves
                    and hudWave and hudWave <= S.SubWave then
                    S.Status = "Waiting for the next wave on the HUD"
                elseif S.FinalMode then
                    F.beginBossWait()
                else
                    F.beginRubble()
                end
            else
                local limit = S.BorderNumber == 1 and S.SubWave == 1
                    and C.FirstWaveSpawnWait or C.MaxSpawnWait
                local remain = math.max(0, limit - (os.clock() - S.EnteredWaitAt))
                S.Status = string.format("Wave %d: waiting for enemies (%.1fs)",
                    S.BorderNumber, remain)
            end
            return
        end

        if S.Phase == "WAIT_AREA_CHANGE" then
            F.readDifficulty()
            if S.HUDDisplayedArea == S.BorderNumber
                and os.clock() - S.HUDLastSeen < 1.5 then
                S.Status = "Waiting for area " .. (S.BorderNumber + 1) .. " in game"
            elseif os.clock() - S.HUDLastSeen >= 1.5 then
                S.HUDPreviousArea = S.BorderNumber
                S.HUDSyncGraceUntil = os.clock() + 1.5
                F.toWave(S.BorderNumber + 1, 1)
            end
            return
        end

        if S.Phase == "GO_SECOND_WAVE" then
            if not S.WaveCoordinate then return end
            local dest = CFrame.new(S.WaveCoordinate)
            local tag = "Area " .. tostring(S.BorderNumber) .. " wave 2"
            if not F.travelTo(dest, tag) then return end
            S.SecondWaveWaitAt = os.clock()
            F.setPhase("WAIT_SECOND_WAVE", "Waiting for the second enemy wave")
            if C.LockOnWave then S.HoldCF = dest end
            return
        end

        if S.Phase == "WAIT_SECOND_WAVE" then
            F.readDifficulty()
            if F.secondWaveAvailable() then
                S.SubWave = 2
                F.beginWave(S.BorderNumber == LastEnemyWave)
                S.Status = "Area " .. S.BorderNumber .. ": attacking wave 2/2"
            elseif F.livingEnemyExists() then
                F.beginWave(S.BorderNumber == LastEnemyWave)
                S.Status = "Active enemies detected; clearing current wave"
            elseif os.clock() - S.SecondWaveWaitAt >= C.MaxSpawnWait then
                if S.FinalMode then
                    F.beginBossWait()
                else
                    F.beginRubble()
                end
            else
                S.Status = string.format("Area %d: waiting for wave 2/2 (%.1fs)",
                    S.BorderNumber, os.clock() - S.SecondWaveWaitAt)
            end
            return
        end

        if S.Phase == "KILL_ENEMIES" then
            F.readDifficulty()
            local target = F.findActiveEnemy()
            if target then
                if S.FinalMode and (F.bossNamed(target) or S.EmptyAt ~= nil) then
                    S.BossEncountered = true
                end
                S.EmptyAt = nil
                S.Status = string.format("Wave %d: attacking %s",
                    S.BorderNumber, target.Name)
                if F.enemyPosition(target) and F.living(target) then
                    F.attackM1()
                    F.autoSkills()
                end
            elseif F.livingEnemyExists() then
                S.EmptyAt = nil
                S.Status = "Active enemies detected; acquiring target"
            else
                F.holdCombatPosition()
                S.EmptyAt = S.EmptyAt or os.clock()
                local remaining = math.max(0, C.ConfirmClear - (os.clock() - S.EmptyAt))
                S.Status = string.format("Wave cleared in %.1fs | skipped: %d", remaining, S.IgnoredStale)

                if os.clock() - S.EmptyAt >= C.ConfirmClear then
                    if S.SubWave < S.ExpectedSubWaves then
                        local hudWave = F.currentHUDWave()
                        if hudWave and hudWave > S.SubWave then
                            F.waitForSecondWave()
                        elseif os.clock() - S.EmptyAt >= C.MaxSpawnWait then
                            if S.FinalMode then
                                S.Status = "Waiting for the final wave to advance"
                            else
                                F.beginRubble()
                            end
                        else
                            S.Status = string.format("Wave %d/%d: waiting for HUD or rubble",
                                S.SubWave, S.ExpectedSubWaves)
                        end
                    elseif S.FinalMode then
                        if S.BossEncountered then
                            F.setPhase("FINAL_TELEPORT", "Boss defeated")
                        else
                            F.beginBossWait()
                        end
                    else
                        F.beginRubble()
                    end
                end
            end
            return
        end

        if S.Phase == "BREAK_RUBBLE" then
            F.readDifficulty()
            local hudWave = F.currentHUDWave()
            if S.SubWave < S.ExpectedSubWaves
                and hudWave and hudWave > S.SubWave then
                F.waitForSecondWave()
                return
            end

            if S.HUDDisplayedArea == S.BorderNumber + 1
                and os.clock() - S.HUDLastSeen < 2 then
                S.RubbleReason = "Next area confirmed by HUD"
                F.afterRubble()
                return
            end

            if F.findActiveEnemy() or F.livingEnemyExists() then
                F.beginWave(S.BorderNumber == LastEnemyWave)
                S.Status = "Active enemies detected; returning to combat"
                return
            end

            local now = os.clock()
            local elapsed = now - S.RubbleEnteredAt
            local current = F.getRubble(S.BorderNumber)

            if current and current ~= S.RubbleRef then
                S.RubbleRef = current
                S.RubbleBaseline = F.captureRubble(current)
                S.RubbleObserved = true
                S.MissingRubbleAt = nil
                S.RubbleClearSince = nil
            end

            local gone, reason = false, ""
            if S.RubbleRef then
                gone, reason = F.rubbleGone(S.RubbleRef, S.RubbleBaseline)
            elseif not current then
                gone, reason = true, "Rubble not found"
            end

            if F.nextWaveSpawned() then
                gone, reason = true, "Next wave spawned"
            end

            if gone then
                if hudWave and hudWave < S.ExpectedSubWaves then
                    S.Status = string.format("Rubble cleared; waiting for Wave %d/%d",
                        S.ExpectedSubWaves, S.ExpectedSubWaves)
                    F.releaseHold()
                    S.RubbleClearSince = nil
                    return
                end
                S.RubbleClearSince = S.RubbleClearSince or now
                S.Status = string.format("Rubble %d: confirming (%s)",
                    S.BorderNumber, reason)
                F.releaseHold()
                if now - S.RubbleClearSince >= C.RubbleClearConfirm then
                    S.RubbleReason = reason
                    F.afterRubble()
                end
                return
            end
            S.RubbleClearSince = nil

            if C.AdvanceOnRubbleTimeout and elapsed >= C.RubbleTimeout
                and (not hudWave or hudWave >= S.ExpectedSubWaves) then
                S.RubbleReason = "Rubble timeout"
                S.Status = "Rubble timeout reached; proceeding"
                F.afterRubble()
                return
            end

            if not current then
                S.Status = string.format("Rubble %d not found (%.0fs)",
                    S.BorderNumber, elapsed)
                return
            end

            local frame = F.rubbleCFrame(current)
            if not frame then
                S.Status = "Rubble destination unavailable"
                return
            end
            local tag = "Rubble" .. tostring(S.BorderNumber)
            if not F.travelTo(frame, tag) then
                if not S.Travel then S.Status = "Moving to " .. tag end
                return
            end
            S.Status = string.format("Breaking Border%d.Rubble (%.1fs)",
                S.BorderNumber, elapsed)
            if F.rubblePosition(current) then
                F.attackM1()
                if C.SkillsOnBorder then F.autoSkills() end
            end
            return
        end

        if S.Phase == "WAIT_BOSS" then
            local boss = F.findSpawnedBoss()
            if boss then
                S.BossTarget = boss
                S.BossClearSince = nil
                F.setPhase("KILL_BOSS", "Boss found: " .. boss.Name)
                return
            end
            S.Status = string.format("Waiting for boss (%.1fs)",
                os.clock() - S.BossWaitAt)
            return
        end

        if S.Phase == "KILL_BOSS" then
            local boss = S.BossTarget
            if boss and F.living(boss) then
                S.BossClearSince = nil
                S.Status = "Attacking boss: " .. boss.Name
                if F.enemyPosition(boss) and F.living(boss) then
                    F.attackM1()
                    F.autoSkills()
                end
            else
                S.BossClearSince = S.BossClearSince or os.clock()
                S.Status = "Boss defeated; confirming clear"
                if os.clock() - S.BossClearSince >= C.ConfirmClear then
                    F.setPhase("FINAL_TELEPORT", "Boss defeated")
                end
            end
            return
        end

        if S.Phase == "FINAL_TELEPORT" then
            F.cancelTravel()
            F.releaseHold()
            F.restoreCollisions()
            S.FinishAt = os.clock()
            S.FinalRestored = true
            F.setPhase("COMPLETED", "Boss cleared; waiting for the next round")
            return
        end

        if S.Phase == "COMPLETED" then
            if os.clock() >= S.FinishAt and not S.FinalRestored then
                F.releaseHold()
                F.restoreCollisions()
                S.FinalRestored = true
                S.Status = "Run completed"
            end
            return
        end
    end

end
