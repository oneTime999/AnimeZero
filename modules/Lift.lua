return function(ctx)
    local WS, RS = ctx.WS, ctx.RS
    local Lift, S = ctx.Lift, ctx.S
    local F = ctx.Functions
    local Player = ctx.Player

    local CLEAR_CONFIRM = 0.85
    local FLOOR_BUMP_HEIGHT = 4
    local FLOOR_BUMP_TIME = 0.12
    local NEXT_FLOOR_COOLDOWN = 2.5
    local GROUND_DISTANCE = 7.5

    local function getLift()
        local world = WS:FindFirstChild("World")
        local markers = world and world:FindFirstChild("Markers")
        local lift = markers and markers:FindFirstChild("Lift")
        local prompt = lift and lift:FindFirstChildWhichIsA("ProximityPrompt", true)
        return lift, prompt
    end

    local function getEnemies()
        local folder = F.enemyFolder()
        local target, distance = nil, math.huge
        local _, root = F.character()
        if not folder or not root then return nil, folder end

        for _, enemy in ipairs(folder:GetChildren()) do
            if enemy:IsA("Model") and F.living(enemy) then
                local part = F.partOf(enemy)
                if part then
                    local d = (root.Position - part.Position).Magnitude
                    if d < distance then
                        target, distance = enemy, d
                    end
                end
            end
        end
        return target, folder
    end

    local function positionBelowTarget(target)
        local character = Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            if Lift.PreviousAutoRotate == nil then Lift.PreviousAutoRotate = humanoid.AutoRotate end
            humanoid.AutoRotate = false
        end
        -- Lift always attacks from below; the height offset is locked at zero.
        local oldPosition, oldHeight = ctx.C.Position, ctx.C.Height
        ctx.C.Position, ctx.C.Height = "Below", 0
        local ok = F.enemyPosition(target)
        ctx.C.Position, ctx.C.Height = oldPosition, oldHeight
        return ok
    end

    local function settleOnGround()
        local character, root = F.character()
        if not character or not root then return false end
        local goal = root.CFrame
        F.setPosition(goal, 0.5, true)
        Lift.GroundPosition = goal
        return true
    end

    local function bumpAndSettle()
        local character, root = F.character()
        if not character or not root then return end

        F.cancelTravel()
        F.releaseHold()
        local base = root.CFrame
        F.setPosition(base + Vector3.new(0, FLOOR_BUMP_HEIGHT, 0), 0, false)
        task.wait(FLOOR_BUMP_TIME)

        -- Never move a newly respawned character back to the previous character's location.
        if Lift.Enabled and S.Alive and Player.Character == character then
            if not settleOnGround() then
                F.setPosition(base, 0.5, true)
            end
        end
    end

    local function fireNextFloor()
        if Lift.NextFloorBusy then
            Lift.Status = "Requesting next floor"
            return false
        end
        local now = os.clock()
        if now < (Lift.NextFloorAt or 0) then
            Lift.Status = "Waiting for next-floor cooldown"
            return false
        end

        local remote = RS:FindFirstChild("endAction")
        if not remote then
            local packets = RS:FindFirstChild("runPackets")
            remote = packets and packets:FindFirstChild("endAction")
        end
        if not remote or not remote:IsA("RemoteEvent") then
            Lift.Status = "Next Floor remote not found; using Lift fallback"
            return false
        end
        if not buffer or type(buffer.fromstring) ~= "function" then
            Lift.Status = "Buffer API unavailable; using Lift fallback"
            return false
        end

        Lift.NextFloorBusy = true
        Lift.NextFloorAt = now + NEXT_FLOOR_COOLDOWN
        local ok, err = pcall(function()
            remote:FireServer(buffer.fromstring("\002"))
        end)
        if not ok then
            Lift.NextFloorBusy = false
            Lift.Status = "Next Floor request failed: " .. tostring(err)
            return false
        end

        Lift.Status = "Next Floor requested"
        Lift.WaitingForWave = true
        Lift.HadEnemies = false
        Lift.EmptySince = nil
        task.spawn(function()
            bumpAndSettle()
            task.wait(0.6)
            Lift.NextFloorBusy = false
        end)
        return true
    end

    local function activatePrompt(prompt)
        if not prompt or not prompt:IsDescendantOf(WS) then return false end
        local ok = false
        if type(fireproximityprompt) == "function" then
            ok = pcall(fireproximityprompt, prompt)
        end
        if not ok then
            ok = pcall(function()
                prompt:InputHoldBegin()
                task.wait(math.max(prompt.HoldDuration, 0.1))
                prompt:InputHoldEnd()
            end)
        end
        return ok
    end

    local function fallbackToLift(lift, prompt)
        local part = lift and (lift:IsA("BasePart") and lift or lift:FindFirstChildWhichIsA("BasePart", true))
        if not part then
            Lift.Status = "Lift has no usable part"
            return
        end

        local goal = part.CFrame + Vector3.new(0, 2.5, 0)
        local arrived = F.travelTo(goal, "LiftPrompt")
        if not arrived then
            Lift.Status = "Moving to Lift"
            return
        end

        if os.clock() >= (Lift.NextPromptAt or 0) then
            Lift.NextPromptAt = os.clock() + 1.25
            Lift.PromptAttempts = (Lift.PromptAttempts or 0) + 1
            local activated = activatePrompt(prompt)
            Lift.Status = activated
                and ("Activating Lift (attempt " .. Lift.PromptAttempts .. ")")
                or "Lift activation unavailable; retrying"
            if activated then
                task.delay(0.8, function()
                    if Lift.Enabled then
                        F.cancelTravel()
                        F.releaseHold()
                    end
                end)
            end
            return activated
        else
            Lift.Status = "Waiting for next wave"
        end
    end

    function F.liftStep()
        if not Lift.Enabled then
            local character = Player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid and Lift.PreviousAutoRotate ~= nil then
                humanoid.AutoRotate = Lift.PreviousAutoRotate
                Lift.PreviousAutoRotate = nil
            end
            return
        end
        local _, root = F.character()
        if not root then
            Lift.Target = nil
            Lift.Status = "Waiting for character"
            return
        end

        local lift, prompt = getLift()
        if not lift or not prompt then
            Lift.Status = "Waiting for Lift mode"
            Lift.Target = nil
            return
        end

        local target, enemies = getEnemies()
        if target then
            Lift.HadEnemies = true
            Lift.EmptySince = nil
            Lift.WaitingForWave = false
            Lift.NextFloorBusy = false
            Lift.Target = target

            if positionBelowTarget(target) and F.living(target) then
                Lift.Status = "Below-target combat: " .. target.Name
                F.attackM1()
                F.autoSkills()
            end
            return
        end

        Lift.Target = nil
        if Lift.WaitingForWave then
            Lift.Status = "Waiting for next floor wave"
            return
        end

        if Lift.HadEnemies then
            Lift.EmptySince = Lift.EmptySince or os.clock()
            if os.clock() - Lift.EmptySince < CLEAR_CONFIRM then
                Lift.Status = "Confirming floor clear"
                return
            end

            -- Reach and activate Interact before requesting the next floor.
            local activated = fallbackToLift(lift, prompt)
            if activated then
                if Lift.AutoNextFloor then
                    fireNextFloor()
                else
                    Lift.Status = "Lift Interact activated"
                end
                return
            end
            if Lift.AutoNextFloor and os.clock() >= (Lift.NextFloorAt or 0)
                and not Lift.NextFloorBusy then
                -- Give the prompt path a short chance to complete before remote fallback.
                if os.clock() - (Lift.EmptySince or os.clock()) >= 4 then
                    if fireNextFloor() then return end
                end
            end
            return
        end

        fallbackToLift(lift, prompt)
    end
end
