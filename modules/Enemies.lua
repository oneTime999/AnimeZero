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
        -- Reconsider skipped mobs only after trying other targets for a while.
        -- Resetting the list every 0.6 s caused a permanent retry loop.
        if now - lastEnemyRecheck >= 4 then
            S.Ignored = {}
            S.TargetProgress = setmetatable({}, {__mode = "k"})
            S.Target = nil
            lastEnemyRecheck = now
            return F.findEnemy()
        end
        return nil
    end

end
