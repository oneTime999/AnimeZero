return function(ctx)
    local WS, RS, Player = ctx.WS, ctx.RS, ctx.Player
    local Story, C = ctx.Story, ctx.C
    local F = ctx.Functions

    -- Ajustes (podem ser mudados em Core.lua dentro da tabela Story):
    --   Story.TravelSpeed  velocidade em studs/segundo (padrao 300)
    --   Story.M1Interval   intervalo entre M1 (padrao: o slider de M1 da UI)
    --   Story.EnemyGap     distancia abaixo do inimigo (padrao 2.5)
    --   Story.RubbleOffset distancia abaixo da pedra (padrao 10)
    local ATTACK_RANGE = 8 -- distancia ate o ponto de ataque para comecar a bater

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
    -- Pedras (Rubble): Workspace.World.Map.Border<N>.Rubble
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

    -- Centro da pedra Border<index>.Rubble se ela ainda existe e esta visivel.
    local function rubbleAt(index)
        local map = mapFolder()
        local border = map and map:FindFirstChild("Border" .. tostring(index))
        local rubble = border and border:FindFirstChild("Rubble")
        if not rubble then return nil end
        local parts = collectParts(rubble, 0.98)
        if #parts == 0 then return nil end
        return rubble, centerOf(parts)
    end

    -- Prefere a Border com o mesmo numero da Area do HUD; se ela nao existir,
    -- usa a de menor numero que ainda tem pedra visivel.
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
    -- Inimigos
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

    ----------------------------------------------------------------------
    -- Ataque e movimento
    ----------------------------------------------------------------------
    local function attackM1()
        if not C.M1 then return end
        local now = os.clock()
        local interval = Story.M1Interval or C.M1Interval or 0.2
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

    -- Move o personagem em direcao a "goal" a cada passo (sem tween, sem
    -- confirmacao de chegada), entao nao ha atraso entre um alvo e outro.
    -- verticalFirst: ajusta primeiro a altura, depois anda na horizontal.
    -- Retorna a distancia restante ate o objetivo (nil se nao ha personagem).
    local function stepTo(goal, verticalFirst)
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
        local maxStep = (Story.TravelSpeed or 300) * dt
        local nextPos = aim
        if dist > maxStep and dist > 0 then
            nextPos = pos + delta.Unit * maxStep
        end

        -- hold = true: o Heartbeat do Runtime mantem o personagem parado
        -- no ponto, sem arrastar de volta para uma posicao antiga.
        F.setPosition(CFrame.new(nextPos) * root.CFrame.Rotation, 0.25, true)
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
    -- startVote: dispara 1x ao ativar o Auto Story e nao repete no mesmo
    -- servidor (controlado por game.JobId). Se desligar e ligar de novo no
    -- mesmo servidor, nao dispara outra vez.
    ----------------------------------------------------------------------
    local Env = ctx.Env
    task.spawn(function()
        local wasEnabled, pending = false, false
        while ctx.S.Alive and not (ctx.Fluent and ctx.Fluent.Unloaded) do
            local enabled = Story.Enabled == true
            if enabled and not wasEnabled then
                pending = true
            elseif not enabled then
                pending = false
            end
            wasEnabled = enabled

            if pending then
                local jobId = (game.JobId ~= "" and game.JobId) or "studio"
                if Env.SlowHubStoryVoteJob == jobId then
                    pending = false
                else
                    local remote = RS and RS:FindFirstChild("startVote")
                    if remote then
                        local ok, err = pcall(function() remote:FireServer(nil) end)
                        if ok then
                            Env.SlowHubStoryVoteJob = jobId
                            pending = false
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
    -- Passo principal (chamado pelo Runtime a cada 0.05s)
    ----------------------------------------------------------------------
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

        -- Garante que nenhum tween antigo brigue com o movimento direto.
        if ctx.S.Travel then F.cancelTravel() end

        ------------------------------------------------------------------
        -- 1) Ainda existem inimigos: ir para baixo deles e bater
        ------------------------------------------------------------------
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
            local part = target and F.partOf(target)
            if not target or not part then
                Story.Status = "Waiting for target (" .. hud.Left .. " left)"
                return
            end

            Story.Target = target
            local goal = Vector3.new(
                part.Position.X,
                part.Position.Y - part.Size.Y * 0.5 - (Story.EnemyGap or 2.5),
                part.Position.Z
            )
            local remaining = stepTo(goal, true)
            if remaining and remaining <= ATTACK_RANGE then
                Story.Status = "Attacking below: " .. target.Name .. " (" .. hud.Left .. " left)"
                attackM1()
            else
                Story.Status = "Moving below: " .. target.Name .. " (" .. hud.Left .. " left)"
            end
            return
        end

        ------------------------------------------------------------------
        -- 2) Sem inimigos e o HUD pede para quebrar a pedra
        ------------------------------------------------------------------
        resetEnemyState()

        if not hud.BreakRubble then
            Story.Status = "Waiting for HUD: " .. hud.Text
            return
        end

        if not mapFolder() then
            Story.Status = "Waiting for World.Map"
            return
        end

        Story.EmptySince = nil
        if Story.WaitingForWave then
            Story.Status = "Rubble cleared; waiting for next Area counter"
            return
        end

        local rubble, index, center
        if Story.ActiveRubbleIndex then
            rubble, center = rubbleAt(Story.ActiveRubbleIndex)
            index = Story.ActiveRubbleIndex
            if not rubble then
                -- A pedra ativa sumiu: foi quebrada. Espera o contador mudar de Area.
                Story.Status = "Border" .. tostring(index) .. ".Rubble broken; waiting for next Area"
                Story.ActiveRubbleIndex = nil
                Story.RubbleWasTargeted = false
                Story.WaitingForWave = true
                F.cancelTravel()
                F.releaseHold()
                return
            end
        else
            rubble, index, center = findActiveRubble(Story.CurrentArea)
            if not rubble then
                Story.Status = "HUD requests rubble; no visible Border#.Rubble found"
                return
            end
            Story.ActiveRubbleIndex = index
            Story.RubbleName = rubble:GetFullName()
        end

        Story.RubbleWasTargeted = true
        local offset = Story.RubbleOffset or 10
        local destination = center - Vector3.new(0, offset, 0)
        local remaining = stepTo(destination, false)
        if remaining and remaining <= ATTACK_RANGE then
            Story.Status = "Attacking Border" .. tostring(index) .. ".Rubble (-" .. tostring(offset) .. " studs)"
            attackM1()
        else
            Story.Status = "Moving to Border" .. tostring(index) .. ".Rubble (-" .. tostring(offset) .. " studs)"
        end
    end
end
