return function(ctx)
    local WS, RS, Player = ctx.WS, ctx.RS, ctx.Player
    local Story, C = ctx.Story, ctx.C
    local F = ctx.Functions

    -- Tunables (configurable through the Story table in Core.lua):
    --   Story.TravelSpeed / Story.SpawnTravelSpeed: movement speed
    --   M1_INTERVAL: delay between basic attacks (defined below)
    --   Story.EnemyGap / Story.RubbleOffset: positioning offsets
    local M1_INTERVAL = 0 -- intervalo FIXO entre M1: 0 = um disparo por frame
    local ATTACK_RANGE = 5 -- distancia ate o ponto de ataque para comecar a bater

    -- Per-area reference points, keyed by the HUD area number.
    -- Can be overridden through Story.SpawnPoints in Core.lua.
    local DEFAULT_SPAWNS = {
        [1] = Vector3.new(-14, 3, 211.5),
        [2] = Vector3.new(-11.476058959960938, 2.999999523162842, 109.21253967285156),
        [3] = Vector3.new(-7.1162285804748535, 2.9999990463256836, -114.92596435546875),
        [4] = Vector3.new(315.3019714355469, 2.999999523162842, -200.8307342529297),
        [5] = Vector3.new(343.00030517578125, 2.999999523162842, -72.57113647460938),
    }

    local function spawnPointFor(area)
        if not area then return nil end
        local list = Story.SpawnPoints or DEFAULT_SPAWNS
        return list[area]
    end

    ----------------------------------------------------------------------
    -- HUD
    ----------------------------------------------------------------------
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
            BreakRubble = string.find(lower, "break the rubble", 1, true) ~= nil
        }
    end

    ----------------------------------------------------------------------
    -- Barrier lookup
    ----------------------------------------------------------------------
    local function mapFolder()
        local world = WS:FindFirstChild("World")
        return world and world:FindFirstChild("Map")
    end

    local function collectParts(object, minTransparency)
        local parts = {}
        if object:IsA("BasePart") and object.Transparency < minTransparency then
            table.insert(parts, object)
        end
        for _, part in ipairs(object:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < minTransparency then
                table.insert(parts, part)
            end
        end
        return parts
    end

    local function centerOf(parts)
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
        return (minV + maxV) * 0.5
    end

    -- Returns the barrier and its center while it is present (cached briefly).
    local rubbleCache = {}
    local function rubbleAt(index)
        local now = os.clock()
        local cached = rubbleCache[index]
        if cached and cached.Rubble.Parent and now - cached.At < 0.2 then
            return cached.Rubble, cached.Center
        end
        rubbleCache[index] = nil

        local map = mapFolder()
        local border = map and map:FindFirstChild("Border" .. tostring(index))
        local rubble = border and border:FindFirstChild("Rubble")
        if not rubble then return nil end
        local parts = collectParts(rubble, 0.98)
        if #parts == 0 then return nil end
        local center = centerOf(parts)
        rubbleCache[index] = {Rubble = rubble, Center = center, At = now}
        return rubble, center
    end

    -- Resolves the active barrier for the given area.
    local function findActiveRubble(area)
        local map = mapFolder()
        if not map then return nil end

        if area then
            local rubble, center = rubbleAt(area)
            if rubble then return rubble, area, center end
        end

        local indices = {}
        for _, child in ipairs(map:GetChildren()) do
            local n = tonumber(child.Name:match("^Border(%d+)$"))
            if n then table.insert(indices, n) end
        end
        table.sort(indices)
        for _, n in ipairs(indices) do
            local rubble, center = rubbleAt(n)
            if rubble then return rubble, n, center end
        end
    end

    ----------------------------------------------------------------------
    -- Enemies
    ----------------------------------------------------------------------
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

    -- Keeps the current target until it is no longer valid.
    local function pickTarget(enemies)
        local current = Story.Target
        if current and current.Parent and F.living(current) then
            for _, enemy in ipairs(enemies) do
                if enemy == current then return current end
            end
        end
        return nearest(enemies)
    end

    ----------------------------------------------------------------------
    -- Combat and movement
    ----------------------------------------------------------------------
    -- Requests an attack; dispatched by the attack loop below.
    local function attackM1()
        -- Skills must run even if basic attacks are turned off.
        Story.WantAttackAt = os.clock()
        if C.M1 then
            Story.WantM1At = os.clock()
        end
    end

    -- Orientation helper.
    local function facingCFrame(pos, target, upHint)
        local dir = target - pos
        if dir.Magnitude < 0.01 then return nil end
        local unit = dir.Unit
        local up = Vector3.yAxis
        if math.abs(unit:Dot(up)) > 0.95 then
            up = upHint or Vector3.zAxis
            if math.abs(unit:Dot(up)) > 0.95 then up = Vector3.xAxis end
        end
        return CFrame.lookAt(pos, target, up)
    end

    -- Advances the character toward a goal on each step.
    -- Returns the remaining distance (nil if no character is available).
    -- Optional lookAt / upHint control the orientation.
    local function stepTo(goal, verticalFirst, speed, lookAt, upHint)
        local _, root = F.character()
        if not root then return nil end

        local now = os.clock()
        local dt = math.clamp(now - (Story.LastMoveAt or (now - 0.05)), 0.03, 0.15)
        Story.LastMoveAt = now

        local pos = root.Position
        local aim = goal
        if verticalFirst and math.abs(pos.Y - goal.Y) > 3 then
            aim = Vector3.new(pos.X, goal.Y, pos.Z)
        end

        local delta = aim - pos
        local dist = delta.Magnitude
        local maxStep = (speed or Story.TravelSpeed or 300) * dt
        local nextPos = aim
        if dist > maxStep and dist > 0 then
            nextPos = pos + delta.Unit * maxStep
        end

        -- Keeps the position stable between steps.
        local frame = CFrame.new(nextPos) * root.CFrame.Rotation
        if lookAt and Story.FaceTarget ~= false then
            frame = facingCFrame(nextPos, lookAt, upHint) or frame
        end
        F.setPosition(frame, 0.25, true)
        return (goal - nextPos).Magnitude
    end

    local function resetEnemyState()
        Story.Target = nil
        Story.MoveEnemy = nil
        Story.MovePhase = nil
        Story.EnemyY = nil
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

    ----------------------------------------------------------------------
    -- Start request handling.
    ----------------------------------------------------------------------
    local Env = ctx.Env
    task.spawn(function()
        local wasEnabled, pending, forced = false, false, false
        while ctx.S.Alive and not (ctx.Fluent and ctx.Fluent.Unloaded) do
            local enabled = Story.Enabled == true
            if enabled and not wasEnabled then
                -- Reset per-run state when the mode is enabled.
                Story.MatchOver = false
                Story.MatchStarted = false
                Story.Settling, Story.SettlePoint, Story.Paused = false, nil, false
                Story.EndActionTries = 0
                Story.EndEnemies = nil
                pending = true
            elseif not enabled then
                pending, forced = false, false
                Story.VotePending = false
            end
            wasEnabled = enabled

            if enabled and Story.VotePending then
                Story.VotePending = false
                pending, forced = true, true
            end

            if pending then
                local jobId = (game.JobId ~= "" and game.JobId) or "studio"
                if not forced and Env.SlowHubStoryVoteJob == jobId then
                    pending = false
                else
                    local remote = RS and RS:FindFirstChild("startVote")
                    if remote then
                        local ok, err = pcall(function() remote:FireServer(nil) end)
                        if ok then
                            Env.SlowHubStoryVoteJob = jobId
                            pending, forced = false, false
                        else
                            warn("[Slow Hub] startVote failed: " .. tostring(err))
                        end
                    end
                end
            end
            task.wait(0.25)
        end
    end)

    ----------------------------------------------------------------------
    -- Attack loop.
    ----------------------------------------------------------------------
    task.spawn(function()
        local remote
        while ctx.S.Alive and not (ctx.Fluent and ctx.Fluent.Unloaded) do
            local want = Story.Enabled == true
                and Story.MatchOver ~= true
                and C.M1
                and (os.clock() - (Story.WantM1At or -math.huge)) < 0.25
            if want then
                if not remote or not remote.Parent then
                    remote = RS and RS:FindFirstChild("performM1")
                end
                if remote then
                    pcall(function() remote:FireServer(nil) end)
                else
                    Story.Status = "performM1 RemoteEvent not found"
                end
            end
            -- Auto skills while we are in attack range (was missing in Story).
            local attacking = Story.Enabled == true
                and Story.MatchOver ~= true
                and (os.clock() - (Story.WantAttackAt or -math.huge)) < 0.25
            if attacking and C.Skills and F.autoSkills then
                pcall(F.autoSkills)
            end
            task.wait(M1_INTERVAL)
        end
    end)

    ----------------------------------------------------------------------
    -- Main step
    ----------------------------------------------------------------------
    -- Console diagnostics (logged on change only).
    local lastNote
    local function note(msg)
        if msg ~= lastNote then
            lastNote = msg
            warn("[Slow Hub] Story: " .. msg)
        end
    end

    ----------------------------------------------------------------------
    -- Match lifecycle.
    ----------------------------------------------------------------------
    local function readMatchStatus()
        local fn = ctx.ReadMatchStatus
        if type(fn) ~= "function" then return nil end
        local ok, status = pcall(fn)
        if ok and type(status) == "string" then return status end
        return nil
    end

    local function endScreenOpen()
        local gui = Player and Player:FindFirstChildOfClass("PlayerGui")
        local screen = gui and gui:FindFirstChild("EndScreen")
        return screen ~= nil and screen:IsA("ScreenGui") and screen.Enabled == true
    end

    local function nearestSpawnPoint(root)
        local list = Story.SpawnPoints or DEFAULT_SPAWNS
        local best, bestDistance
        for _, point in pairs(list) do
            local d = Vector2.new(point.X - root.Position.X, point.Z - root.Position.Z).Magnitude
            if not bestDistance or d < bestDistance then
                best, bestDistance = point, d
            end
        end
        return best
    end

    -- Post-match cleanup.
    local function settleAfterMatch()
        local _, root = F.character()
        local timedOut = os.clock() - (Story.SettleAt or 0) > 4
        if root and not timedOut then
            Story.SettlePoint = Story.SettlePoint or nearestSpawnPoint(root)
            if Story.SettlePoint then
                local remaining = stepTo(Story.SettlePoint, false, Story.SpawnTravelSpeed or 150)
                if remaining and remaining > 2 then return end
            end
        end
        Story.Settling, Story.SettlePoint = false, nil
        Story.EndActionTries = 0
        Story.EndActionAt = os.clock() - 3
        Story.Paused = true
        F.cancelTravel()
        F.releaseHold()
        F.restoreCollisions()
        note("match finished: movement released; waiting for the next match")
    end

    -- Returns true while the match is over.
    local function updateMatchState()
        local now = os.clock()
        if now - (Story.LastMatchCheck or 0) < 0.25 then
            return Story.MatchOver == true
        end
        Story.LastMatchCheck = now

        local status = readMatchStatus()
        local endScreen = endScreenOpen()

        -- A dead or freshly respawned player must not be mistaken for a finished
        -- match: the status is only trusted for a settled, living character and
        -- only after it has stayed non-active for a moment.
        local character = Player and Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local alive = humanoid ~= nil and humanoid.Health > 0
        if Story.LastCharacter ~= character then
            Story.LastCharacter = character
            Story.CharacterChangedAt = now
        end
        local settled = alive and now - (Story.CharacterChangedAt or 0) > 5

        if Story.MatchOver ~= true then
            if status == "active" then Story.MatchStarted = true end
            if settled and status ~= nil and status ~= "active" and Story.MatchStarted then
                Story.InactiveSince = Story.InactiveSince or now
            else
                Story.InactiveSince = nil
            end
            local statusEnded = Story.InactiveSince ~= nil and now - Story.InactiveSince >= 2
            if endScreen or statusEnded then
                Story.InactiveSince = nil
                Story.MatchOver = true
                Story.WantM1At = 0
                -- Snapshot current enemies to detect new ones later.
                Story.EndEnemies = setmetatable({}, {__mode = "k"})
                for _, enemy in ipairs(livingEnemies()) do
                    Story.EndEnemies[enemy] = true
                end
                -- Cancel active actions and begin post-match cleanup.
                F.cancelTravel()
                resetEnemyState()
                clearRubbleState()
                Story.Settling = true
                Story.SettleAt = now
                Story.SettlePoint = nil
                note("match finished (" .. tostring(endScreen and "EndScreen" or status) .. "); settling")
            end
            return Story.MatchOver == true
        end

        -- Waiting for the next match.
        local newEnemy = false
        for _, enemy in ipairs(livingEnemies()) do
            if not (Story.EndEnemies and Story.EndEnemies[enemy]) then
                newEnemy = true
                break
            end
        end
        -- A visible wave counter also proves the match is running again.
        local hud = readHud()
        local hudActive = hud ~= nil and ((hud.Left ~= nil and hud.Left > 0) or hud.BreakRubble)
        if not endScreen and (status == "active" or newEnemy or hudActive) then
            Story.MatchOver = false
            Story.MatchStarted = true
            Story.Settling, Story.SettlePoint, Story.Paused = false, nil, false
            Story.EndActionTries = 0
            Story.EndEnemies = nil
            Story.CurrentArea, Story.TotalAreas = nil, nil
            Story.LastMoveAt = nil
            resetEnemyState()
            clearRubbleState()
            F.cancelTravel()
            F.releaseHold()
            Story.VotePending = true
            note("new match detected; restarting Story and firing startVote")
            return false
        end
        return true
    end

    -- Travel to the reference point of an area.
    local function goToSpawn(area, detail)
        local spawn = spawnPointFor(area)
        if not spawn then
            Story.Status = "No spawn point set for Area " .. tostring(area) .. " (" .. detail .. ")"
            note("no spawn point set for Area " .. tostring(area))
            return false
        end
        local remaining = stepTo(spawn, false, Story.SpawnTravelSpeed or 150)
        if not remaining then
            Story.Status = "Waiting for character"
            return false
        end
        if remaining > 2 then
            Story.Status = "Moving to spawn point of Area " .. tostring(area)
            note("moving to spawn point of Area " .. tostring(area))
            return false
        end
        Story.Status = "At spawn point of Area " .. tostring(area) .. "; " .. detail
        note("at spawn point of Area " .. tostring(area))
        return true
    end

    -- Post-match action through the shared endAction remote (1 = replay,
    -- 2 = next stage). Follows the global Auto Next Stage / Auto Replay options;
    -- next stage wins when both are on. Sent a few times at most.
    local function sendEndAction()
        local mode = (C.AutoNextStage and 2) or (C.AutoReplay and 1) or nil
        if not mode then return end
        if (Story.EndActionTries or 0) >= 3 then return end
        local now = os.clock()
        if now - (Story.EndActionAt or 0) < 4 then return end

        local remote = RS and RS:FindFirstChild("endAction")
        local nested = false
        if not remote then
            local packets = RS and RS:FindFirstChild("runPackets")
            remote = packets and packets:FindFirstChild("endAction")
            nested = remote ~= nil
        end
        if not remote then return end

        Story.EndActionAt = now
        Story.EndActionTries = (Story.EndActionTries or 0) + 1
        local ok, err = pcall(function()
            if nested then
                remote:FireServer(mode)
            else
                remote:FireServer(buffer.fromstring(string.char(mode)))
            end
        end)
        note((mode == 2 and "next" or "replay") .. " requested" .. (ok and "" or (": " .. tostring(err))))
    end

    function F.storyStep()
        if not Story.Enabled then return end

        if updateMatchState() then
            if Story.Settling then
                settleAfterMatch()
                Story.Status = "Match finished; moving to a safe spot"
            else
                Story.Status = "Match finished; waiting for the next match (Story stays on)"
                sendEndAction()
            end
            return
        end

        local hud = readHud()
        if not hud then
            Story.Status = "Waiting for RoundHUD EnemyCount"
            return
        end

        if hud.Area then
            if Story.CurrentArea and Story.CurrentArea ~= hud.Area then
                note("Area changed: " .. tostring(Story.CurrentArea) .. " -> " .. tostring(hud.Area))
                clearRubbleState()
                Story.EmptySince = nil
            end
            Story.CurrentArea = hud.Area
            Story.TotalAreas = hud.TotalAreas
        end

        -- Cancel any leftover travel state.
        if ctx.S.Travel then F.cancelTravel() end

        local left = hud.Left
        local enemies = livingEnemies()

        ------------------------------------------------------------------
        -- 1) Combat
        ------------------------------------------------------------------
        if (left ~= nil and left > 0) or (not hud.BreakRubble and #enemies > 0) then
            clearRubbleState()
            Story.EmptySince = nil

            if #enemies == 0 then
                resetEnemyState()
                local detail = "waiting for NPCs" .. (left and (" (" .. left .. " left)") or "")
                goToSpawn(hud.Area or Story.CurrentArea, detail)
                return
            end

            local target = pickTarget(enemies)
            local part = target and F.partOf(target)
            if not target or not part then
                Story.Status = "Waiting for target (" .. tostring(left) .. " left)"
                return
            end

            Story.Target = target
            local goal = Vector3.new(
                part.Position.X,
                part.Position.Y - part.Size.Y * 0.5 - (Story.EnemyGap or 2.5),
                part.Position.Z
            )
            local remaining = stepTo(goal, true, nil, part.Position, part.CFrame.LookVector)
            if remaining and remaining <= ATTACK_RANGE then
                Story.Status = "Attacking below: " .. target.Name .. " (" .. tostring(left) .. " left)"
                attackM1()
            else
                Story.Status = "Moving below: " .. target.Name .. " (" .. tostring(left) .. " left)"
            end
            return
        end

        resetEnemyState()

        ------------------------------------------------------------------
        -- 2) Barrier
        ------------------------------------------------------------------
        if hud.BreakRubble then
            if not mapFolder() then
                Story.Status = "Waiting for World.Map"
                return
            end

            Story.EmptySince = nil

            local rubble, index, center
            if Story.WaitingForWave then
                -- Barrier cleared; continue to the next area.
                goToSpawn((Story.CurrentArea or 0) + 1, "rubble cleared")
                return
            end

            if Story.ActiveRubbleIndex then
                index = Story.ActiveRubbleIndex
                rubble, center = rubbleAt(index)
                if not rubble then
                    note("Border" .. tostring(index) .. ".Rubble broken")
                    Story.ActiveRubbleIndex = nil
                    Story.RubbleWasTargeted = false
                    Story.WaitingForWave = true
                    -- Continue immediately.
                    goToSpawn((Story.CurrentArea or 0) + 1, "rubble cleared")
                    return
                end
            else
                rubble, index, center = findActiveRubble(Story.CurrentArea)
                if not rubble then
                    Story.Status = "HUD requests rubble; no visible Border#.Rubble found"
                    note("no visible Border#.Rubble found")
                    return
                end
                Story.ActiveRubbleIndex = index
                Story.RubbleName = rubble:GetFullName()
                note("targeting " .. Story.RubbleName)
            end

            Story.RubbleWasTargeted = true
            local offset = (Story.RubbleOffsets and Story.RubbleOffsets[index])
                or Story.RubbleOffset or 10
            local standPoint = Story.RubbleStandPoints and Story.RubbleStandPoints[index]
            local goal = standPoint or (center - Vector3.new(0, offset, 0))
            local where = standPoint and "fixed point" or ("-" .. tostring(offset) .. " studs")
            local remaining = stepTo(goal, false, nil, center, Vector3.zAxis)
            -- A fixed point is the exact limit, so only attack once we are on it.
            local range = standPoint and 1.5 or ATTACK_RANGE
            if remaining and remaining <= range then
                Story.Status = "Attacking Border" .. tostring(index) .. ".Rubble (" .. where .. ")"
                attackM1()
            else
                Story.Status = "Moving to Border" .. tostring(index) .. ".Rubble (" .. where .. ")"
            end
            return
        end

        ------------------------------------------------------------------
        -- 3) Transitional HUD state
        ------------------------------------------------------------------
        if left == 0 then
            Story.Status = "Area cleared; waiting for rubble prompt"
            return
        end

        local area = hud.Area or Story.CurrentArea
        if Story.WaitingForWave then area = (Story.CurrentArea or 0) + 1 end
        goToSpawn(area, "HUD: " .. tostring(hud.Text))
    end
end
