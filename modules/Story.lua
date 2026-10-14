return function(ctx)
    local WS = ctx.WS
    local Story = ctx.Story
    local F = ctx.Functions

    local function rubbleRoot()
        local world = WS:FindFirstChild("World")
        local map = world and world:FindFirstChild("Map")
        local border = map and map:FindFirstChild("Border1")
        return border and border:FindFirstChild("Rubble")
    end

    local function currentRubble(root)
        if not root then return nil end
        local list = {}
        for _, object in ipairs(root:GetChildren()) do
            local index = tonumber(object.Name:match("^Rubble(%d+)$"))
            if index then
                table.insert(list, {object = object, index = index})
            end
        end
        table.sort(list, function(a, b) return a.index < b.index end)

        for _, entry in ipairs(list) do
            local parts = {}
            if entry.object:IsA("BasePart") and entry.object.Transparency < 1 then
                table.insert(parts, entry.object)
            end
            for _, part in ipairs(entry.object:GetDescendants()) do
                if part:IsA("BasePart") and part.Transparency < 1 then
                    table.insert(parts, part)
                end
            end
            if #parts > 0 then
                local minV = Vector3.new(math.huge, math.huge, math.huge)
                local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
                for _, part in ipairs(parts) do
                    local p, h = part.Position, part.Size * 0.5
                    minV = Vector3.new(math.min(minV.X,p.X-h.X), math.min(minV.Y,p.Y-h.Y), math.min(minV.Z,p.Z-h.Z))
                    maxV = Vector3.new(math.max(maxV.X,p.X+h.X), math.max(maxV.Y,p.Y+h.Y), math.max(maxV.Z,p.Z+h.Z))
                end
                return entry.object, entry.index, (minV + maxV) * 0.5
            end
        end
    end

    local function livingEnemies()
        local folder = F.enemyFolder()
        local found = {}
        if not folder then return found end

        local function scan(container)
            for _, enemy in ipairs(container:GetChildren()) do
                if enemy:IsA("Model") then
                    if F.living(enemy) and F.partOf(enemy) then
                        table.insert(found, enemy)
                    else
                        scan(enemy)
                    end
                elseif enemy:IsA("Folder") then
                    scan(enemy)
                end
            end
        end

        scan(folder)
        return found
    end

    local function nearest(enemies)
        local _, root = F.character()
        if not root then return nil end
        local target, best = nil, math.huge
        for _, enemy in ipairs(enemies) do
            local part = F.partOf(enemy)
            if part then
                local distance = (part.Position - root.Position).Magnitude
                if distance < best then target, best = enemy, distance end
            end
        end
        return target
    end

    function F.storyStep()
        if not Story.Enabled then return end
        local rubble = rubbleRoot()
        if not rubble then
            Story.Status = "Waiting for Rubble folder"
            return
        end

        local enemies = livingEnemies()
        if #enemies > 0 then
            Story.EmptySince = nil
            local target = nearest(enemies)
            Story.Target = target
            if target then
                if F.enemyPosition(target, "Below", Story.EnemyGap or 2.5, 0) and F.living(target) then
                    Story.Status = "Attacking enemy: " .. target.Name
                    F.attackM1()
                else
                    Story.Status = "Moving below enemy: " .. target.Name
                end
            end
            return
        end

        Story.Target = nil
        Story.EmptySince = Story.EmptySince or os.clock()
        if os.clock() - Story.EmptySince < 1 then
            Story.Status = "Confirming wave clear"
            return
        end

        local object, index, center = currentRubble(rubble)
        if not object then
            Story.Status = "Waiting for next Rubble to appear"
            return
        end

        local destination = center - Vector3.new(0, Story.RubbleOffset or 10, 0)
        local arrived = F.travelTo(CFrame.new(destination), "Story:Rubble" .. index)
        if arrived then
            F.setPosition(CFrame.new(destination), 0.8, true)
            Story.Status = "At Rubble" .. index
            F.attackM1()
        else
            Story.Status = "Moving to Rubble" .. index
        end
    end
end
