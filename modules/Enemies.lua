return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions

    function F.character()
        local char = Player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if root and hum and hum.Health > 0 then return char, root end
    end

    function F.partOf(model)
        if not model or not model:IsA("Model") then return end
        return model:FindFirstChild("HumanoidRootPart", true)
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    function F.hpOf(model)
        local hum = model:FindFirstChildWhichIsA("Humanoid", true)
        if hum then return hum.Health end
        for _, name in ipairs({"Health", "HP", "CurrentHealth", "CurrentHP"}) do
            local attr = model:GetAttribute(name)
            if type(attr) == "number" then return attr end
            local val = model:FindFirstChild(name, true)
            if val and (val:IsA("IntValue") or val:IsA("NumberValue")) then
                return val.Value
            end
        end
        return nil
    end

    function F.living(model)
        if not model or not model:IsA("Model") or not model:IsDescendantOf(WS) then return false end
        if not F.partOf(model) then return false end
        if model:GetAttribute("Dead") == true or model:GetAttribute("IsDead") == true
           or model:GetAttribute("Alive") == false then return false end
        local hp = F.hpOf(model)
        return hp == nil or hp > 0
    end

    function F.enemyFolder()
        return WS:FindFirstChild("enemies")
    end

    function F.readDifficulty()
        local now = os.clock()
        if now - S.LastDifficultyScan < 0.4 then
            return S.Difficulty
        end
        S.LastDifficultyScan = now

        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local uiArea, uiWave, uiTotal, detected
        if gui then
            for _, object in ipairs(gui:GetDescendants()) do
                if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Visible then
                    local value = object.Text:lower()
                    local area = tonumber(value:match("area%s*(%d+)"))
                    local wave, total = value:match("wave%s*(%d+)%s*/%s*(%d+)")
                    if area and wave and total then
                        if not uiArea or area == S.BorderNumber then
                            uiArea, uiWave, uiTotal = area, tonumber(wave), tonumber(total)
                            if value:find("nightmare", 1, true) then
                                detected = "Nightmare"
                            elseif value:find("hard", 1, true) then
                                detected = "Hard"
                            elseif value:find("medium", 1, true) then
                                detected = "Medium"
                            elseif value:find("easy", 1, true) then
                                detected = "Easy"
                            end
                        end
                        if area == S.BorderNumber then break end
                    end
                end
            end
        end

        if uiArea then
            S.HUDDisplayedArea = uiArea
            S.HUDDisplayedWave = uiWave
            S.HUDDisplayedTotal = uiTotal
            S.HUDLastSeen = now
            S.CachedHUDWave = uiArea == S.BorderNumber and uiWave or nil
        elseif now - S.HUDLastSeen >= 2 then
            S.HUDDisplayedArea = nil
            S.HUDDisplayedWave = nil
            S.HUDDisplayedTotal = nil
            S.CachedHUDWave = nil
        end

        if uiTotal then
            S.Difficulty = detected or (uiTotal >= 2 and "Nightmare" or "Easy")
            S.ExpectedSubWaves = S.Difficulty == "Nightmare" and 2 or 1
        end
        return S.Difficulty
    end

    function F.currentHUDWave()
        if S.HUDDisplayedArea == S.BorderNumber
            and os.clock() - S.HUDLastSeen < 2 then
            return S.HUDDisplayedWave
        end
        return nil
    end

    function F.isInCurrentWave(model)
        return F.partOf(model) ~= nil
    end

    function F.isStale(model, now)
        local hp = F.hpOf(model)
        local info = S.TargetProgress[model]
        if not info then
            info = {Health = hp, LastProgress = now}
            S.TargetProgress[model] = info
            return false
        end

        if hp ~= nil and info.Health ~= nil and hp < info.Health - 0.001 then
            info.LastProgress = now
        end
        info.Health = hp

        if now - info.LastProgress >= C.StaleTargetWait then
            S.Ignored[model] = true
            S.IgnoredStale += 1
            S.Status = "Skipping unresponsive enemy: " .. model.Name
            return true
        end
        return false
    end

    function F.findEnemy()
        local folder = F.enemyFolder()
        local _, root = F.character()
        if not folder or not root then return nil end

        local previousTarget = S.Target
        local nearest, nearestDistance = nil, math.huge
        local retained = nil
        local now = os.clock()

        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and F.isInCurrentWave(model) then
                S.WaveModels[model] = true

                if F.living(model) and not S.Ignored[model] then
                    if model == previousTarget then retained = model end
                    local part = F.partOf(model)
                    local distance = (root.Position - part.Position).Magnitude
                    if distance < nearestDistance then
                        nearestDistance = distance
                        nearest = model
                    end
                end
            end
        end

        local target = retained or nearest
        if target ~= S.Target then
            S.Target = target
            S.TargetSince = now
        end

        if target and F.isStale(target, now) then
            S.Target = nil
            return nil
        end

        return target
    end

    function F.livingEnemyExists()
        local folder = F.enemyFolder()
        if not folder then return false end
        for _, model in ipairs(folder:GetChildren()) do
            if F.living(model) then
                return true
            end
        end
        return false
    end

    local lastEnemyRecheck = -math.huge
    function F.findActiveEnemy()
        local target = F.findEnemy()
        if target then return target end
        if not F.livingEnemyExists() then return nil end

        local now = os.clock()
        if now - lastEnemyRecheck >= 0.6 then
            S.Ignored = {}
            S.TargetProgress = setmetatable({}, {__mode = "k"})
            S.Target = nil
            lastEnemyRecheck = now
        end
        return F.findEnemy()
    end

end
