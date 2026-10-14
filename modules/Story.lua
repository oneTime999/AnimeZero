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

    local function getRubbleDetails(root, wantedIndex)
        if not root then return nil end
        local rubbleObjects = {}

        for _, object in ipairs(root:GetChildren()) do
            local index = tonumber(object.Name:match("^Rubble(%d+)$"))
            if index and (wantedIndex == nil or index == wantedIndex) then
                table.insert(rubbleObjects, {Object = object, Index = index})
            end
        end

        table.sort(rubbleObjects, function(a, b)
            return a.Index < b.Index
        end)

        for _, entry in ipairs(rubbleObjects) do
            local parts = {}
            if entry.Object:IsA("BasePart") and entry.Object.Transparency < 0.98 then
                table.insert(parts, entry.Object)
            end

            for _, part in ipairs(entry.Object:GetDescendants()) do
                if part:IsA("BasePart") and part.Transparency < 0.98 then
                    table.insert(parts, part)
                end
            end

            if #parts > 0 then
                local minV = Vector3.new(math.huge, math.huge, math.huge)
                local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)

                for _, part in ipairs(parts) do
                    local p = part.Position
                    local half = part.Size * 0.5
                    minV = Vector3.new(
                        math.min(minV.X, p.X - half.X),
                        math.min(minV.Y, p.Y - half.Y),
                        math.min(minV.Z, p.Z - half.Z)
                    )
                    maxV = Vector3.new(
                        math.max(maxV.X, p.X + half.X),
                        math.max(maxV.Y, p.Y + half.Y),
                        math.max(maxV.Z, p.Z + half.Z)
                    )
                end

                return entry.Object, entry.Index, (minV + maxV) * 0.5, parts
            end
        end
    end

    local function livingEnemies()
        local folder = F.enemyFolder()
        local found = {}
        if not folder then return found end

        -- The arena normally places enemy models directly in workspace.enemies.
        -- Scan child folders too, but do not recurse into an enemy model.
        local function scanFolder(container)
            for _, object in ipairs(container:GetChildren()) do
                if object:IsA("Model") then
                    if F.living(object) and F.partOf(object) then
                        table.insert(found, object)
                    end
                elseif object:IsA("Folder") then
                    scanFolder(object)
                end
            end
        end

        scanFolder(folder)
        return found
    end

    local function nearest(enemies)
        local _, root = F.character()
        if not root then return nil end

        local target, bestDistance = nil, math.huge
        for _, enemy in ipairs(enemies) do
            local part = F.partOf(enemy)
            if part then
                local distance = (part.Position - root.Position).Magnitude
                if distance < bestDistance then
                    target, bestDistance = enemy, distance
                end
            end
        end
        return target
    end

    local function resetEnemyTravel(target, root, part)
        Story.MoveEnemy = target
        Story.MovePhase = "Descend"
        Story.EnemyY = part.Position.Y - part.Size.Y * 0.5 - (Story.EnemyGap or 2.5)
        F.cancelTravel()
        F.releaseHold()
    end

    local function positionUnderEnemy(target)
        local _, root = F.character()
        local part = F.partOf(target)
        if not root or not part then
            return false
        end

        local desiredY = part.Position.Y - part.Size.Y * 0.5 - (Story.EnemyGap or 2.5)

        if Story.MoveEnemy ~= target or not Story.MovePhase then
            resetEnemyTravel(target, root, part)
        elseif Story.MovePhase == "Attack" then
            local deltaXZ = Vector2.new(
                root.Position.X - part.Position.X,
                root.Position.Z - part.Position.Z
            ).Magnitude

            -- If the target moves away or below us, repeat the safe two-stage move.
            if deltaXZ > 4 or math.abs(root.Position.Y - desiredY) > 1.5 then
                resetEnemyTravel(target, root, part)
            end
        end

        if Story.MovePhase == "Descend" then
            local descendPosition = Vector3.new(
                root.Position.X,
                Story.EnemyY,
                root.Position.Z
            )
            local arrived = F.travelTo(
                CFrame.new(descendPosition),
                "Story:EnemyDescend:" .. target.Name,
                0
            )

            if arrived then
                Story.MovePhase = "Approach"
                F.cancelTravel()
                F.releaseHold()
            end
            return false
        end

        if Story.MovePhase == "Approach" then
            local attackPosition = Vector3.new(
                part.Position.X,
                Story.EnemyY,
                part.Position.Z
            )
            local arrived = F.travelTo(
                CFrame.new(attackPosition),
                "Story:EnemyApproach:" .. target.Name,
                0
            )

            if arrived then
                F.setPosition(CFrame.new(attackPosition), 1, true)
                Story.MovePhase = "Attack"
                return true
            end
            return false
        end

        if Story.MovePhase == "Attack" then
            -- Hold the established position. If the NPC moves enough to matter,
            -- the threshold check above restarts the two-stage approach.
            return true
        end

        return false
    end

    local function resetEnemyState()
        Story.Target = nil
        if Story.MoveEnemy or Story.MovePhase then
            Story.MoveEnemy = nil
            Story.MovePhase = nil
            Story.EnemyY = nil
            F.cancelTravel()
            F.releaseHold()
        end
    end

    function F.storyStep()
        if not Story.Enabled then return end

        local rootFolder = rubbleRoot()
        if not rootFolder then
            Story.Status = "Waiting for Rubble folder"
            return
        end

        local enemies = livingEnemies()
        if #enemies > 0 then
            Story.EmptySince = nil
            Story.WaitingForWave = false
            Story.ActiveRubbleIndex = nil

            local target = nearest(enemies)
            if not target then
                Story.Status = "Waiting for a valid enemy target"
                return
            end

            if Story.Target ~= target then
                resetEnemyState()
                Story.Target = target
            end

            if F.living(target) and positionUnderEnemy(target) then
                Story.Status = "Attacking from below: " .. target.Name
                F.attackM1()
            else
                Story.Status = "Descending, then approaching below: " .. target.Name
            end
            return
        end

        resetEnemyState()
        Story.EmptySince = Story.EmptySince or os.clock()

        if Story.WaitingForWave then
            Story.Status = "Barrier cleared; waiting for next wave"
            return
        end

        if os.clock() - Story.EmptySince < 1 then
            Story.Status = "Confirming wave clear"
            return
        end

        if Story.ActiveRubbleIndex then
            local object, index, center = getRubbleDetails(rootFolder, Story.ActiveRubbleIndex)
            if not object then
                Story.Status = "Rubble" .. tostring(Story.ActiveRubbleIndex) .. " cleared; waiting for next wave"
                Story.ActiveRubbleIndex = nil
                Story.WaitingForWave = true
                F.cancelTravel()
                F.releaseHold()
                return
            end
        else
            local object, index = getRubbleDetails(rootFolder)
            if not object then
                Story.Status = "Waiting for the next active rubble"
                return
            end
            Story.ActiveRubbleIndex = index
        end

        local object, index, center = getRubbleDetails(rootFolder, Story.ActiveRubbleIndex)
        if not object or not center then
            Story.Status = "Waiting for active Rubble" .. tostring(Story.ActiveRubbleIndex)
            return
        end

        local destination = center - Vector3.new(0, Story.RubbleOffset or 10, 0)
        local arrived = F.travelTo(
            CFrame.new(destination),
            "Story:Rubble:" .. tostring(index),
            0
        )

        if arrived then
            F.setPosition(CFrame.new(destination), 1, true)
            Story.Status = "Attacking Rubble" .. tostring(index)
            F.attackM1()
        else
            Story.Status = "Moving to Rubble" .. tostring(index) .. " (10 studs below)"
        end
    end
end
