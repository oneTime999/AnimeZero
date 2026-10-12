return function(ctx)
    local WS = ctx.WS
    local Player = ctx.Player
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
        local folder = WS:FindFirstChild("enemies") or WS:FindFirstChild("Enemies")
        if folder then return folder end
        for _, child in ipairs(WS:GetChildren()) do
            if child:IsA("Folder") and string.lower(child.Name) == "enemies" then
                return child
            end
        end
        return nil
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


end
