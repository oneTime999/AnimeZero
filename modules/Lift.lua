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

    local function groundCFrameAt(desiredPosition, targetPosition, character, enemies)
        local _, root = F.character()
        if not root then return nil end

        character = character or Player.Character
        enemies = enemies or F.enemyFolder()

        local excluded = {}
        if character then table.insert(excluded, character) end
        if enemies then table.insert(excluded, enemies) end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = excluded
        params.IgnoreWater = true

        local originY = math.max(desiredPosition.Y, root.Position.Y)
        if targetPosition then originY = math.max(originY, targetPosition.Y) end
        local origin = Vector3.new(desiredPosition.X, originY + 40, desiredPosition.Z)
        local hit = WS:Raycast(origin, Vector3.new(0, -300, 0), params)
        if not hit then return nil end

        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local hipHeight = humanoid and humanoid.HipHeight or 2
        local rootHalfHeight = root.Size.Y * 0.5
        local position = Vector3.new(
            desiredPosition.X,
            hit.Position.Y + hipHeight + rootHalfHeight,
            desiredPosition.Z
        )

        local lookAt
        if targetPosition then
            lookAt = Vector3.new(targetPosition.X, position.Y, targetPosition.Z)
        else
            local forward = root.CFrame.LookVector
            lookAt = position + Vector3.new(forward.X, 0, forward.Z)
        end
        if (lookAt - position).Magnitude < 0.05 then
            lookAt = position + Vector3.new(0, 0, -1)
        end
        return CFrame.lookAt(position, lookAt)
    end

    local function positionOnGround(target, enemies)
        local character, root = F.character()
        local targetPart = F.partOf(target)
        if not character or not root or not targetPart then return false end

        -- Stay close to the enemy, but keep the character on the floor.
        local away = Vector3.new(
            root.Position.X - targetPart.Position.X,
            0,
            root.Position.Z - targetPart.Position.Z
        )
        if away.Magnitude < 0.1 then
            away = Vector3.new(-targetPart.CFrame.LookVector.X, 0, -targetPart.CFrame.LookVector.Z)
        end
        if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
        away = away.Unit

        local distance = math.min(Lift.GroundDistance or GROUND_DISTANCE, 3.5)
        local desired = targetPart.Position + away * distance
        local groundCF = groundCFrameAt(desired, targetPart.Position, character, enemies)
        if not groundCF then
            Lift.Status = "Searching for safe ground"
            return false
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            if Lift.PreviousAutoRotate == nil then
                Lift.PreviousAutoRotate = humanoid.AutoRotate
            end
            humanoid.AutoRotate = false
        end

        -- Rotate the character onto their back: face points upward, body lies horizontally.
        local floorY = groundCF.Position.Y
            - ((humanoid and humanoid.HipHeight) or 2)
            - (root.Size.Y * 0.5)
        local lyingPosition = Vector3.new(desired.X, floorY + math.max(root.Size.Z * 0.5, 1.25), desired.Z)
        local lyingCF = CFrame.lookAt(
            lyingPosition,
            lyingPosition + Vector3.new(0, 1, 0),
            Vector3.new(0, 0, 1)
        )

        F.cancelTravel()
        local positioned = F.setPosition(lyingCF, 0.4, true)
        if positioned then
            Lift.GroundPosition = lyingCF
        end
        return positioned
    end

    local function settleOnGround()
        local character, root = F.character()
        if not character or not root then return false end
        local groundCF = groundCFrameAt(root.Position, nil, character, F.enemyFolder())
        if not groundCF then return false end
        F.setPosition(groundCF, 0.5, true)
        Lift.GroundPosition = groundCF
        return true
    end

    local function bumpAndSettle()
        local character, root = F.character()
        if not character or not root then return end

        F.cancelTravel()
        F.releaseHold()
        local base = groundCFrameAt(root.Position, nil, character, F.enemyFolder())
            or root.CFrame
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

            if positionOnGround(target, enemies) and F.living(target) then
                Lift.Status = "Ground combat: " .. target.Name
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

        if Lift.AutoNextFloor and Lift.HadEnemies then
            Lift.EmptySince = Lift.EmptySince or os.clock()
            if os.clock() - Lift.EmptySince >= CLEAR_CONFIRM then
                if Lift.NextFloorBusy or os.clock() < (Lift.NextFloorAt or 0) then
                    fireNextFloor()
                    return
                end
                if fireNextFloor() then return end
            else
                Lift.Status = "Confirming floor clear"
                return
            end
        end

        -- Keep the previous prompt path as a fallback if the remote is unavailable
        -- or Auto Next Floor is turned off.
        fallbackToLift(lift, prompt)
    end
end
