return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions


    function F.getBorder(number)
        local world = WS:FindFirstChild("World")
        local map = world and world:FindFirstChild("Map")
        local border = map and map:FindFirstChild("Border" .. tostring(number))
        if border and border:IsA("Model") then return border end
        return nil
    end

    function F.getRubble(number)
        local border = F.getBorder(number)
        return border and border:FindFirstChild("Rubble") or nil
    end

    function F.captureRubble(rubble)
        local baseline = {Parts = {}, Visible = 0, Count = 0}
        if not rubble then return baseline end

        local function collect(part)
            baseline.Count += 1
            local visible = part.Transparency < 0.95
                and part.LocalTransparencyModifier < 0.95
            if visible then baseline.Visible += 1 end
            baseline.Parts[part] = {Position = part.Position, WasVisible = visible}
        end

        if rubble:IsA("BasePart") then
            collect(rubble)
        else
            for _, descendant in ipairs(rubble:GetDescendants()) do
                if descendant:IsA("BasePart") then collect(descendant) end
            end
        end
        return baseline
    end

    function F.destroyedFlag(instance)
        if not instance then return false end
        for _, name in ipairs({"Destroyed", "IsDestroyed", "Broken", "IsBroken", "Cleared", "Dead"}) do
            if instance:GetAttribute(name) == true then return true end
            local v = instance:FindFirstChild(name)
            if v and v:IsA("BoolValue") and v.Value then return true end
        end
        for _, name in ipairs({"Health", "HP", "Durability", "Integrity", "CurrentHealth"}) do
            local value = instance:GetAttribute(name)
            if type(value) == "number" and value <= 0 then return true end
            local item = instance:FindFirstChild(name)
            if item and (item:IsA("IntValue") or item:IsA("NumberValue"))
                and item.Value <= 0 then return true end
        end
        return false
    end

    function F.rubbleGone(rubble, baseline)
        if not rubble or not rubble:IsDescendantOf(WS) then
            return true, "Rubble removed"
        end

        if F.destroyedFlag(rubble) or F.destroyedFlag(rubble.Parent) then
            return true, "Destroyed state or zero health"
        end
        local hp = F.hpOf(rubble)
        if hp ~= nil and hp <= 0 then
            return true, "Rubble health depleted"
        end

        local parts = 0
        local visible = 0
        local solid = 0
        local function inspect(part)
            parts += 1
            if part.Transparency < 0.95 and part.LocalTransparencyModifier < 0.95 then
                visible += 1
            end
            if part.CanCollide and part.Transparency < 0.95 then
                solid += 1
            end
        end

        if rubble:IsA("BasePart") then
            inspect(rubble)
        else
            for _, object in ipairs(rubble:GetDescendants()) do
                if object:IsA("BasePart") then inspect(object) end
            end
        end
        if parts == 0 then return true, "Rubble has no parts" end

        if baseline and baseline.Visible > 0 and visible == 0 then
            return true, "Rubble became invisible"
        end

        if baseline and baseline.Count > 0 then
            local originals = 0
            local originalsVisible = 0
            local moved = 0
            for part, info in pairs(baseline.Parts) do
                if part:IsDescendantOf(rubble) then
                    originals += 1
                    if info.WasVisible and part.Transparency < 0.95
                        and part.LocalTransparencyModifier < 0.95 then
                        originalsVisible += 1
                    end
                    if (part.Position - info.Position).Magnitude >= 14 then
                        moved += 1
                    end
                end
            end
            if originals == 0 then
                return true, "Original parts were removed"
            end
            if baseline.Count >= 2 and originals <= baseline.Count * 0.25 then
                return true, "Original parts removed"
            end
            if baseline.Visible > 0 and originalsVisible == 0 then
                return true, "Original parts became invisible"
            end
            if baseline.Count >= 2 and moved >= baseline.Count * 0.8 then
                return true, "Rubble moved after destruction"
            end
        end

        return false, ""
    end

    function F.nextWaveSpawned()
        local folder = F.enemyFolder()
        local points = WaveCoordinates[S.BorderNumber + 1]
        local pos = points and points[1]
        if not folder or not pos then return false end
        if os.clock() - S.RubbleEnteredAt < 1 then return false end

        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and F.living(model) then
                local root = F.partOf(model)
                if root and (root.Position - pos).Magnitude <= C.WaveRadius then
                    local before = S.RubbleEnemySnapshot[model]
                    local hp = F.hpOf(model)
                    if before == nil or (before ~= false and before <= 0
                        and (hp == nil or hp > 0)) then
                        return true
                    end
                end
            end
        end
        return false
    end
end
