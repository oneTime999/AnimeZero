return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local F = ctx.Functions

    function F.cancelTravel()
        S.Travel = nil
        S.ArrivedTag = nil
    end

    function F.releaseHold()
        S.HoldCF = nil
    end

    function F.holdCombatPosition()
        if C.Position == "Below" and C.Noclip and not S.Travel then
            local _, root = F.character()
            if root then
                S.HoldCF = S.HoldCF or root.CFrame
                return
            end
        end
        F.releaseHold()
    end

    -- Moves the character toward a goal on each call (no tween state).
    -- Returns the remaining distance, or nil when there is no character.
    -- upright = true: arrive standing (keeps only the current heading), instead
    -- of keeping a lying / face-up orientation.
    function F.stepTo(goal, speed, upright)
        local _, root = F.character()
        if not root then return nil end
        F.disableCollisions()

        local now = os.clock()
        local dt = math.clamp(now - (S.LastStepAt or (now - 0.05)), 0.03, 0.15)
        S.LastStepAt = now

        local pos = root.Position
        local delta = goal - pos
        local dist = delta.Magnitude
        local maxStep = (speed or 150) * dt
        local nextPos = goal
        if dist > maxStep and dist > 0 then
            nextPos = pos + delta.Unit * maxStep
        end

        local rotation = root.CFrame.Rotation
        if upright then
            local look = root.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude < 0.2 then
                local up = root.CFrame.UpVector
                flat = Vector3.new(up.X, 0, up.Z)
            end
            if flat.Magnitude < 0.2 then flat = Vector3.zAxis end
            rotation = CFrame.lookAt(Vector3.zero, flat.Unit).Rotation
        end

        F.setPosition(CFrame.new(nextPos) * rotation, 0.25, true)
        return (goal - nextPos).Magnitude
    end

    -- Spirit's Bathtub always runs with collisions off, regardless of the
    -- Noclip setting: climbing back to the ground would otherwise get stuck
    -- against the floor.
    local function bathtubActive()
        return Raid.Enabled and Raid.Variant == "Bathtub"
    end

    function F.disableCollisions()
        local char = Player.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if S.Collisions[part] == nil then
                    S.Collisions[part] = part.CanCollide
                end
                if part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end

    local function endScreenOpen()
        local gui = Player and Player:FindFirstChildOfClass("PlayerGui")
        local screen = gui and gui:FindFirstChild("EndScreen")
        return screen ~= nil and screen:IsA("ScreenGui") and screen.Enabled == true
    end

    -- Keeps the character fixed at S.HoldCF (position and orientation) and
    -- clears its velocity, so it cannot sink or fall while collisions are off.
    -- With noclip on and no hold set, the current spot is held automatically
    -- (except after a round ends, when the game must be free to move the player).
    function F.pinHold()
        -- Spirit's Bathtub floats with F.floatEnable (BodyVelocity), so the
        -- constant re-teleport of the hold is never used there.
        if bathtubActive() then return end
        local char, root = F.character()
        if not char or not root then return end
        if S.PinChar ~= char then
            S.PinChar = char
            S.LastSafeCF = nil
        end

        if not S.HoldCF then
            local Story, Zzz = ctx.Story, ctx.ZzzzWorld
            if not (C.Noclip or bathtubActive())
                or (Raid.Enabled and Raid.RoundFinished)
                or (Zzz and Zzz.Enabled and Zzz.RoundFinished)
                or (Story and Story.Enabled and (Story.MatchOver or Story.Paused))
                or endScreenOpen() then
                return
            end
            local safe = S.LastSafeCF
            if safe and root.Position.Y < safe.Position.Y - 6 then
                S.HoldCF = safe -- fell: return to the last safe position
            else
                S.HoldCF = root.CFrame
            end
        end

        local cf = S.HoldCF
        if root.Anchored then root.Anchored = false end
        local drift = root.Position - cf.Position
        if drift.Magnitude > 0.15 or root.CFrame.LookVector:Dot(cf.LookVector) < 0.995 then
            char:PivotTo(cf)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        S.LastSafeCF = cf
    end

    ----------------------------------------------------------------------
    -- Float controller (Spirit's Bathtub)
    -- A BodyVelocity with zero velocity cancels gravity, so the character
    -- stays where it was placed. It is moved only when a new position is
    -- wanted, never re-teleported every frame.
    ----------------------------------------------------------------------
    local FLOAT_VEL, FLOAT_GYRO = "AZ_FloatVel", "AZ_FloatGyro"

    -- Standing-up rotation that keeps only the current heading.
    local function uprightRotation(root)
        local look = root.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 0.2 then
            local up = root.CFrame.UpVector
            flat = Vector3.new(up.X, 0, up.Z)
        end
        if flat.Magnitude < 0.2 then flat = Vector3.zAxis end
        return CFrame.lookAt(Vector3.zero, flat.Unit).Rotation
    end

    function F.floatEnable()
        local char, root = F.character()
        if not root then return nil end
        local huge = Vector3.new(1e9, 1e9, 1e9)
        local vel = root:FindFirstChild(FLOAT_VEL)
        if not vel then
            vel = Instance.new("BodyVelocity")
            vel.Name = FLOAT_VEL
            vel.MaxForce = huge
            vel.P = 1e5
            vel.Velocity = Vector3.zero
            vel.Parent = root
        end
        local gyro = root:FindFirstChild(FLOAT_GYRO)
        if not gyro then
            gyro = Instance.new("BodyGyro")
            gyro.Name = FLOAT_GYRO
            gyro.MaxTorque = huge
            gyro.P = 1e4
            gyro.D = 500
            gyro.CFrame = root.CFrame
            gyro.Parent = root
        end

        -- Never keep a lying / upside-down pose (the camera rolls with it):
        -- stand the character up once and aim the gyro at the upright pose.
        if root.CFrame.UpVector.Y < 0.97 then
            local cf = CFrame.new(root.Position) * uprightRotation(root)
            pcall(function()
                if root.Anchored then root.Anchored = false end
                char:PivotTo(cf)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
            gyro.CFrame = cf
        end
        return root, gyro
    end

    function F.floatDisable()
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        for _, name in ipairs({FLOAT_VEL, FLOAT_GYRO}) do
            local obj = root:FindFirstChild(name)
            if obj then obj:Destroy() end
        end
    end

    -- Puts the character at cf in one move and keeps it there.
    function F.floatPlace(cf)
        local char = F.character()
        local root, gyro = F.floatEnable()
        if not char or not root then return false end
        F.disableCollisions()
        local ok = pcall(function()
            if root.Anchored then root.Anchored = false end
            char:PivotTo(cf)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if gyro then gyro.CFrame = cf end
        end)
        if ok then S.LastSafeCF = cf end
        return ok
    end

    -- Glides toward goal while floating. Once the goal is reached it does
    -- nothing at all (no teleporting while already in place).
    -- Returns the remaining distance, or nil when there is no character.
    function F.floatGlide(goal, speed)
        local root = F.floatEnable()
        if not root then return nil end
        F.disableCollisions()

        local delta = goal - root.Position
        local dist = delta.Magnitude
        if dist <= 0.5 then return dist end

        local now = os.clock()
        local dt = math.clamp(now - (S.FloatStepAt or (now - 0.05)), 0.03, 0.15)
        S.FloatStepAt = now

        local nextPos = goal
        local maxStep = (speed or 200) * dt
        if dist > maxStep then nextPos = root.Position + delta.Unit * maxStep end

        local look = root.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 0.2 then flat = Vector3.zAxis end
        F.floatPlace(CFrame.new(nextPos) * CFrame.lookAt(Vector3.zero, flat.Unit).Rotation)
        return (goal - nextPos).Magnitude
    end

    -- Rescue from a real fall: if the character is dropping fast and is well
    -- below its last safe position, put it back and hold it there. Slow or
    -- one-frame moves (elevators, server teleports) are left alone.
    function F.voidGuard()
        local char, root = F.character()
        if not char or not root then return end
        if S.PinChar ~= char then
            S.PinChar = char
            S.LastSafeCF = nil
        end
        local safe = S.LastSafeCF
        if safe and root.Position.Y < safe.Position.Y - 8
            and root.AssemblyLinearVelocity.Y < -35 then
            pcall(function()
                char:PivotTo(safe)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
            S.HoldCF = safe
        end
    end

    function F.setPosition(cf, tolerance, hold)
        local char, root = F.character()
        if not char then return false end

        local ok = pcall(function()
            if root.Anchored then root.Anchored = false end
            if (root.Position - cf.Position).Magnitude > (tolerance or 0.6) then
                char:PivotTo(cf)
            else
                root.CFrame = cf
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        if ok and hold then
            S.HoldCF = cf
            S.LastSafeCF = cf
        end
        return ok
    end

    function F.travelTo(cf, tag, arc)
        if S.ArrivedTag == tag then
            local _, root = F.character()
            if root and (root.Position - cf.Position).Magnitude <= 4 then
                return true
            end
            S.ArrivedTag = nil
        end

        local char, root = F.character()
        if not char or not root then return false end
        if S.Travel and S.Travel.Tag == tag then return false end

        S.Travel = nil
        F.releaseHold()
        local distance = (root.Position - cf.Position).Magnitude
        local duration = C.TravelMethod == "Tween"
            and math.clamp(distance / math.max(C.TravelSpeed, 10), 0.15, 8)
            or 0

        S.Travel = {
            Tag = tag,
            Start = root.CFrame,
            Goal = cf,
            Started = os.clock(),
            Duration = duration,
            Arc = arc,
            ArrivalAt = nil,
            LastDrift = nil
        }
        return false
    end

    function F.updateTravel()
        local trip = S.Travel
        if not ((ctx.Lift and ctx.Lift.Enabled) or (ctx.Story and ctx.Story.Enabled)) or not S.Alive or not trip then return end
        local char, root = F.character()
        if not char or not root then return end
        local now = os.clock()
        -- Recover if the server keeps rejecting the tween destination.
        -- Discard stale travel state so it cannot block later movement.
        if now - trip.Started > trip.Duration + 5 then
            S.Travel = nil
            S.ArrivedTag = nil
            F.releaseHold()
            S.Status = "Retrying stalled travel"
            return
        end
        local alpha = trip.Duration > 0
            and math.clamp((now - trip.Started) / trip.Duration, 0, 1)
            or 1
        local eased = alpha * alpha * (3 - 2 * alpha)
        local pos = trip.Start.Position:Lerp(trip.Goal.Position, eased)

        if trip.Duration > 0 then
            local arc = trip.Arc == nil and C.TravelArc or trip.Arc
            pos += Vector3.new(0, math.sin(math.pi * alpha) * arc, 0)
        end
        local frame = CFrame.new(pos) * trip.Goal.Rotation

        pcall(function()
            if root.Anchored then root.Anchored = false end
            char:PivotTo(frame)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)

        if alpha < 1 then
            S.Status = string.format("Tween %s: %d%%", trip.Tag, math.floor(alpha * 100))
            return
        end

        if (root.Position - trip.Goal.Position).Magnitude > 4 then
            trip.ArrivalAt = nil
            return
        end
        trip.ArrivalAt = trip.ArrivalAt or now
        if now - trip.ArrivalAt >= C.ArrivalConfirm then
            local tag, target = trip.Tag, trip.Goal
            S.Travel = nil
            S.ArrivedTag = tag
            S.HoldCF = target
        end
    end

    local lastCombatPositionAt = nil

    function F.enemyPosition(enemy, positionOverride, distanceOverride, heightOverride)
        local part = F.partOf(enemy)
        if not part then return false end

        -- Mode overrides let Trial use one consistent offset without changing
        -- the user's saved positioning settings for Raids or Zzz World.
        local position = positionOverride or C.Position
        local d = distanceOverride == nil and C.Distance or distanceOverride
        local height = heightOverride == nil and C.Height or heightOverride
        local cf = part.CFrame
        local offset
        if position == "Inside" then
            offset = Vector3.zero
        elseif position == "Above" then
            offset = Vector3.new(0, d + part.Size.Y * 0.5, 0)
        elseif position == "Below" then
            offset = Vector3.new(0, -d - part.Size.Y * 0.5, 0)
        elseif position == "Front" then
            offset = cf.LookVector * d
        elseif position == "Left" then
            offset = -cf.RightVector * d
        elseif position == "Right" then
            offset = cf.RightVector * d
        else
            offset = -cf.LookVector * d
        end

        local pos = part.Position + offset + Vector3.new(0, height, 0)
        local look = Vector3.new(part.Position.X, pos.Y, part.Position.Z)
        local up = Vector3.yAxis

        if position == "Below" then
            -- Face the enemy above instead of looking horizontally under the map.
            look = part.Position
            if (look - pos).Magnitude > 0.01 then
                up = cf.LookVector
                if math.abs((look - pos).Unit:Dot(up)) > 0.95 then
                    up = cf.RightVector
                end
            end
        end

        if (pos - look).Magnitude < 0.01 then
            look = pos + cf.LookVector
        end
        local destination = CFrame.lookAt(pos, look, up)

        if C.TravelMethod == "Tween" then
            local _, root = F.character()
            if not root then return false end

            local now = os.clock()
            local dt = lastCombatPositionAt
                and math.clamp(now - lastCombatPositionAt, 1 / 60, 0.12)
                or 1 / 60
            lastCombatPositionAt = now

            local distance = (root.Position - pos).Magnitude
            if distance > 0.75 then
                local alpha = math.min(1, C.TravelSpeed * dt / distance)
                destination = root.CFrame:Lerp(destination, alpha)
            end
        else
            lastCombatPositionAt = nil
        end

        return F.setPosition(destination, 0.25, true)
    end

    function F.applyNoclip()
        local Lift, Story = ctx.Lift, ctx.Story
        -- Story paused (match finished): do not reapply noclip.
        if Story and Story.Paused then return end
        if not (Raid.Enabled or ctx.ZzzzWorld.Enabled or (Lift and Lift.Enabled) or (Story and Story.Enabled))
            or not (C.Noclip or bathtubActive()) then
            return
        end

        -- Reapply every physics step: some games reset CanCollide after movement/respawn.
        F.disableCollisions()
    end

    function F.restoreCollisions()
        for part, original in pairs(S.Collisions) do
            if part and part.Parent then
                pcall(function() part.CanCollide = original end)
            end
        end
        S.Collisions = setmetatable({}, {__mode = "k"})
    end
end
