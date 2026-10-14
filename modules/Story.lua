return function(ctx)
    local WS = ctx.WS
    local Player = ctx.Player
    local Story = ctx.Story
    local F = ctx.Functions

    local function readHud()
        local playerGui = Player and Player:FindFirstChildOfClass("PlayerGui")
        local hud = playerGui and playerGui:FindFirstChild("RoundHUD")
        local container = hud and hud:FindFirstChild("Container")
        local topPart = container and container:FindFirstChild("TopPart")
        local remainingFrame = topPart and topPart:FindFirstChild("RemainingFrame")
        local label = remainingFrame and remainingFrame:FindFirstChild("EnemyCount")

        if not label or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
            return nil
        end

        local text = label.Text or ""
        local lower = string.lower(text)
        local area, total = lower:match("area%s*(%d+)%s*/%s*(%d+)")
        local left = lower:match("(%d+)%s+left")
        local breakRubble = string.find(lower, "break the rubble to continue", 1, true) ~= nil

        return {
            Text = text,
            Area = tonumber(area),
            TotalAreas = tonumber(total),
            Left = tonumber(left),
            BreakRubble = breakRubble
        }
    end

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
        local targetY = part.Position.Y - part.Size.Y * 0.5 - (Story.EnemyGap or 2.5)
        -- First lower vertically at the current X/Z. If already below the
        -- target's feet, keep the current lower height rather than rising.
        Story.EnemyY = math.min(root.Position.Y, targetY)
        F.cancelTravel()
        F.releaseHold()
    end

    local function positionUnderEnemy(target)
        local _, root = F.character()
        local part = F.partOf(target)
        if not root or not part then return false end

        local desiredY = part.Position.Y - part.Size.Y * 0.5 - (Story.EnemyGap or 2.5)

        if Story.MoveEnemy ~= target or not Story.MovePhase then
            resetEnemyTravel(target, root, part)
        elseif Story.MovePhase == "Attack" then
            local deltaXZ = Vector2.new(
                root.Position.X - part.Position.X,
                root.Position.Z - part.Position.Z
            ).Magnitude

            if deltaXZ > 4 or math.abs(root.Position.Y - desiredY) > 1.5 then
                resetEnemyTravel(target, root, part)
            end
        end

        if Story.MovePhase == "Descend" then
            local descendPosition = Vector3.new(root.Position.X, Story.EnemyY, root.Position.Z)
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
            local attackPosition = Vector3.new(part.Position.X, Story.EnemyY, part.Position.Z)
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

        return Story.MovePhase == "Attack"
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

    local function clearRubbleState()
        local hadRubbleState = Story.ActiveRubbleIndex ~= nil
            or Story.RubbleWasTargeted == true
            or Story.WaitingForWave == true

        Story.ActiveRubbleIndex = nil
        Story.RubbleWasTargeted = false
        Story.WaitingForWave = false

        -- Do not interrupt the enemy's descend/approach tween on every HUD
        -- update. Cancel movement only when leaving an actual rubble phase.
        if hadRubbleState then
            F.cancelTravel()
            F.releaseHold()
        end
    end

    function F.storyStep()
        if not Story.Enabled then return end

        local hud = readHud()
        if not hud then
            Story.Status = "Waiting for RoundHUD EnemyCount"
            return
        end

        -- Area and count are read from the actual round HUD, not inferred
        -- from the current contents of workspace.enemies.
        if hud.Area then
            if Story.CurrentArea and Story.CurrentArea ~= hud.Area then
                clearRubbleState()
                Story.EmptySince = nil
            end
            Story.CurrentArea = hud.Area
            Story.TotalAreas = hud.TotalAreas
        end

        local rootFolder = rubbleRoot()
        if not rootFolder then
            Story.Status = "Waiting for World.Map.Border1.Rubble"
            return
        end

        if hud.Left ~= nil and hud.Left > 0 then
            clearRubbleState()
            Story.EmptySince = nil

            local enemies = livingEnemies()
            if #enemies == 0 then
                Story.Target = nil
                resetEnemyState()
                Story.Status = "HUD says " .. hud.Left .. " left; waiting for enemy spawn"
                return
            end

            local target = nearest(enemies)
            if not target then
                Story.Status = "Waiting for a valid enemy target (" .. hud.Left .. " left)"
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

        if not hud.BreakRubble then
            resetEnemyState()
            Story.Status = "Waiting for HUD: " .. hud.Text
            return
        end

        resetEnemyState()
        Story.EmptySince = nil

        if Story.WaitingForWave then
            Story.Status = "Rubble cleared; waiting for the next Area counter"
            return
        end

        local wantedIndex = Story.CurrentArea or Story.ActiveRubbleIndex
        local object, index, center = getRubbleDetails(rootFolder, wantedIndex)

        -- If Auto Story starts while the HUD is already on the break prompt,
        -- use the first visible RubbleN as a fallback to establish the area index.
        if not object and not wantedIndex then
            object, index, center = getRubbleDetails(rootFolder)
            if index then
                Story.CurrentArea = index
            end
        end

        if not object or not center then
            if Story.RubbleWasTargeted then
                Story.WaitingForWave = true
                F.cancelTravel()
                F.releaseHold()
                Story.Status = "Rubble" .. tostring(wantedIndex) .. " disappeared; waiting for next Area"
            else
                Story.Status = "Waiting for active Rubble" .. tostring(wantedIndex or "?")
            end
            return
        end

        Story.ActiveRubbleIndex = index
        Story.RubbleWasTargeted = true

        local destination = center - Vector3.new(0, Story.RubbleOffset or 10, 0)
        local arrived = F.travelTo(
            CFrame.new(destination),
            "Story:Rubble:" .. tostring(index),
            0
        )

        if arrived then
            F.setPosition(CFrame.new(destination), 1, true)
            Story.Status = "Attacking Rubble" .. tostring(index) .. " (-10 studs)"
            F.attackM1()
        else
            Story.Status = "Moving to Rubble" .. tostring(index) .. " (-10 studs)"
        end
    end
end
