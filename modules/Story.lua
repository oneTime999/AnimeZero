return function(ctx)
    local WS, RS, Player = ctx.WS, ctx.RS, ctx.Player
    local Story, C = ctx.Story, ctx.C
    local F = ctx.Functions

    local function readHud()
        local playerGui = Player and Player:FindFirstChildOfClass("PlayerGui")
        local hud = playerGui and playerGui:FindFirstChild("RoundHUD")
        local container = hud and hud:FindFirstChild("Container")
        local topPart = container and container:FindFirstChild("TopPart")
        local frame = topPart and topPart:FindFirstChild("RemainingFrame")
        local label = frame and frame:FindFirstChild("EnemyCount")
        if not label or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
            return nil
        end

        local text = label.Text or ""
        local lower = string.lower(text)
        local area, total = lower:match("area%s*(%d+)%s*/%s*(%d+)")
        local left = lower:match("(%d+)%s+left")
        return {
            Text = text,
            Area = tonumber(area),
            TotalAreas = tonumber(total),
            Left = tonumber(left),
            BreakRubble = string.find(lower, "break the rubble to continue", 1, true) ~= nil
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
        local candidates, seen = {}, {}
        local objects = {root}
        for _, descendant in ipairs(root:GetDescendants()) do
            table.insert(objects, descendant)
        end

        -- RubbleN may be nested under a Model or Folder rather than a direct child.
        for _, object in ipairs(objects) do
            local index = tonumber(object.Name:match("^Rubble(%d+)$"))
            if index and (wantedIndex == nil or index == wantedIndex) and not seen[object] then
                seen[object] = true
                table.insert(candidates, {Object = object, Index = index})
            end
        end
        table.sort(candidates, function(a, b) return a.Index < b.Index end)

        for _, entry in ipairs(candidates) do
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
                    local p, half = part.Position, part.Size * 0.5
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
                return entry.Object, entry.Index, (minV + maxV) * 0.5
            end
        end
    end

    local function livingEnemies()
        local folder = F.enemyFolder()
        local found = {}
        if not folder then return found end

        local function scan(container)
            for _, object in ipairs(container:GetChildren()) do
                if object:IsA("Model") then
                    if F.living(object) and F.partOf(object) then
                        table.insert(found, object)
                    end
                elseif object:IsA("Folder") then
                    scan(object)
                end
            end
        end

        scan(folder)
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

    local function attackM1()
        if not C.M1 then return end
        local now = os.clock()
        local interval = Story.M1Interval or 0.12
        if now - (Story.LastM1 or 0) < interval then return end

        local remote = RS and RS:FindFirstChild("performM1")
        if not remote or not remote:IsA("RemoteEvent") then
            Story.Status = "performM1 RemoteEvent not found"
            return
        end

        Story.LastM1 = now
        local ok, err = pcall(function() remote:FireServer(nil) end)
        if not ok then Story.Status = "M1 failed: " .. tostring(err) end
    end

    local function resetEnemyTravel(target, root, part)
        Story.MoveEnemy = target
        Story.MovePhase = "Descend"
        -- First descend at the current X/Z to the intended attack height,
        -- then move horizontally under the NPC.
        Story.EnemyY = part.Position.Y - part.Size.Y * 0.5 - (Story.EnemyGap or 2.5)
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
            local descend = Vector3.new(root.Position.X, Story.EnemyY, root.Position.Z)
            local arrived = F.travelTo(
                CFrame.new(descend),
                "Story:EnemyDescend:" .. target:GetDebugId(),
                0,
                Story.TravelSpeed or 300
            )
            if arrived then
                Story.MovePhase = "Approach"
                F.cancelTravel()
                F.releaseHold()
            end
            return false
        end

        if Story.MovePhase == "Approach" then
            local goal = Vector3.new(part.Position.X, Story.EnemyY, part.Position.Z)
            local arrived = F.travelTo(
                CFrame.new(goal),
                "Story:EnemyApproach:" .. target:GetDebugId(),
                0,
                Story.TravelSpeed or 300
            )
            if arrived then
                F.setPosition(CFrame.new(goal), 1, true)
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

        -- The counter is authoritative: do not head for a barrier while the
        -- HUD says there are enemies still alive.
        if hud.Left ~= nil and hud.Left > 0 then
            clearRubbleState()
            Story.EmptySince = nil

            local enemies = livingEnemies()
            if #enemies == 0 then
                resetEnemyState()
                Story.Status = "HUD says " .. hud.Left .. " left; waiting for NPC spawn"
                return
            end

            local target = nearest(enemies)
            if not target then
                Story.Status = "Waiting for target (" .. hud.Left .. " left)"
                return
            end

            if Story.Target ~= target then
                resetEnemyState()
                Story.Target = target
            end

            if F.living(target) and positionUnderEnemy(target) then
                Story.Status = "Attacking below: " .. target.Name
                attackM1()
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
            Story.Status = "Rubble cleared; waiting for next Area counter"
            return
        end

        if Story.ActiveRubbleIndex then
            local object = getRubbleDetails(rootFolder, Story.ActiveRubbleIndex)
            if not object then
                Story.Status = "Rubble" .. tostring(Story.ActiveRubbleIndex) .. " disappeared; waiting for next Area"
                Story.ActiveRubbleIndex = nil
                Story.RubbleWasTargeted = false
                Story.WaitingForWave = true
                F.cancelTravel()
                F.releaseHold()
                return
            end
        else
            local object, index = getRubbleDetails(rootFolder, Story.CurrentArea)
            -- Prefer RubbleN matching the HUD's area; if its naming differs,
            -- fall back to the first visible RubbleN found anywhere underneath.
            if not object then
                object, index = getRubbleDetails(rootFolder)
            end
            if not object then
                Story.Status = "HUD requests rubble; no visible RubbleN found"
                return
            end
            Story.ActiveRubbleIndex = index
        end

        local object, index, center = getRubbleDetails(rootFolder, Story.ActiveRubbleIndex)
        if not object or not center then
            Story.Status = "Waiting for active Rubble" .. tostring(Story.ActiveRubbleIndex)
            return
        end

        Story.RubbleWasTargeted = true
        local destination = center - Vector3.new(0, Story.RubbleOffset or 10, 0)
        local arrived = F.travelTo(
            CFrame.new(destination),
            "Story:Rubble:" .. tostring(index),
            0,
            Story.TravelSpeed or 300
        )

        if arrived then
            F.setPosition(CFrame.new(destination), 1, true)
            Story.Status = "Attacking Rubble" .. tostring(index) .. " (-10 studs)"
            attackM1()
        else
            Story.Status = "Moving to Rubble" .. tostring(index) .. " (-10 studs)"
        end
    end
end
