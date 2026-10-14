return function(ctx)
    local WS, RS, Player = ctx.WS, ctx.RS, ctx.Player
    local Story, C = ctx.Story, ctx.C
    local F = ctx.Functions

    -- Ajustes (podem ser mudados em Core.lua dentro da tabela Story):
    --   Story.TravelSpeed  velocidade perto de inimigos/pedra, studs/s (padrao 300)
    --   Story.SpawnTravelSpeed  velocidade nas viagens longas entre Areas (padrao 150)
    --   M1_INTERVAL        intervalo fixo entre M1 (0.1s), definido abaixo
    --   Story.EnemyGap     distancia abaixo do inimigo (padrao 2.5)
    --   Story.RubbleOffset distancia abaixo da pedra (padrao 10)
    local M1_INTERVAL = 0.1 -- intervalo FIXO entre M1 (segundos)
    local ATTACK_RANGE = 8 -- distancia ate o ponto de ataque para comecar a bater

    -- Pontos onde o personagem deve ficar para os mobs de cada Area spawnarem.
    -- A chave e o numero da Area do HUD (Area 1/5, Area 2/5, ...).
    -- Para mudar sem editar este arquivo, defina Story.SpawnPoints em Core.lua.
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
        local interval = M1_INTERVAL
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
    local function stepTo(goal, verticalFirst, speed)
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
    -- Mostra no console apenas quando a mensagem muda (para diagnostico).
    local lastNote
    local function note(msg)
        if msg ~= lastNote then
            lastNote = msg
            warn("[Slow Hub] Story: " .. msg)
        end
    end

    -- Viagem (possivelmente longa) ate o ponto onde os mobs da Area spawnam.
    local function goToSpawn(area, detail)
        local spawn = spawnPointFor(area)
        if not spawn then
            Story.Status = "No spawn point set for Area " .. tostring(area) .. " (" .. detail .. ")"
            note("no spawn point set for Area " .. tostring(area))
            return false
        end
        local remaining = stepTo(spawn, false, Story.SpawnTravelSpeed or 150)
        if remaining and remaining > 2 then
            Story.Status = "Moving to spawn point of Area " .. tostring(area)
            note("moving to spawn point of Area " .. tostring(area))
            return false
        end
        Story.Status = "At spawn point of Area " .. tostring(area) .. "; " .. detail
        note("at spawn point of Area " .. tostring(area))
        return true
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
                note("Area changed: " .. tostring(Story.CurrentArea) .. " -> " .. tostring(hud.Area))
                clearRubbleState()
                Story.EmptySince = nil
            end
            Story.CurrentArea = hud.Area
            Story.TotalAreas = hud.TotalAreas
        end

        -- Garante que nenhum tween antigo brigue com o movimento direto.
        if ctx.S.Travel then F.cancelTravel() end

        local left = hud.Left
        local enemies = livingEnemies()

        ------------------------------------------------------------------
        -- 1) Combate: o HUD diz que faltam inimigos, ou ja ha inimigos vivos
        --    e o HUD nao esta pedindo a pedra.
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

            local target = nearest(enemies)
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
            local remaining = stepTo(goal, true)
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
        -- 2) O HUD pede para quebrar a pedra
        ------------------------------------------------------------------
        if hud.BreakRubble then
            if not mapFolder() then
                Story.Status = "Waiting for World.Map"
                return
            end

            Story.EmptySince = nil

            local rubble, index, center
            if Story.WaitingForWave then
                -- Pedra ja quebrada: segue para o ponto da proxima Area sem
                -- esperar o HUD atualizar.
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
                    -- Segue direto para o proximo ponto (sem esperar um novo passo).
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
            local offset = Story.RubbleOffset or 10
            local remaining = stepTo(center - Vector3.new(0, offset, 0), false)
            if remaining and remaining <= ATTACK_RANGE then
                Story.Status = "Attacking Border" .. tostring(index) .. ".Rubble (-" .. tostring(offset) .. " studs)"
                attackM1()
            else
                Story.Status = "Moving to Border" .. tostring(index) .. ".Rubble (-" .. tostring(offset) .. " studs)"
            end
            return
        end

        ------------------------------------------------------------------
        -- 3) HUD em transicao (sem "N left" e sem "Break the rubble")
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
