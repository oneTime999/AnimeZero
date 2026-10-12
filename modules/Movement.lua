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
        if ok and hold then S.HoldCF = cf end
        return ok
    end

    function F.travelTo(cf, tag)
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
            ArrivalAt = nil,
            LastDrift = nil
        }
        return false
    end

    function F.updateTravel()
        local trip = S.Travel
        if not (ctx.Lift and ctx.Lift.Enabled) or not S.Alive or not trip then return end
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
            pos += Vector3.new(0, math.sin(math.pi * alpha) * C.TravelArc, 0)
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
        local d = distanceOverride
        if d == nil then
            d = position == "Below" and (C.BelowAttackGap or 8) or C.Distance
        end
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
        local Lift = ctx.Lift
        if not (Raid.Enabled or ctx.ZzzzWorld.Enabled or (Lift and Lift.Enabled))
            or not C.Noclip then
            return
        end

        local char = Player.Character
        if not char then return end

        -- Reapply every physics step: some games reset CanCollide after movement/respawn.
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

    function F.restoreCollisions()
        for part, original in pairs(S.Collisions) do
            if part and part.Parent then
                pcall(function() part.CanCollide = original end)
            end
        end
        S.Collisions = setmetatable({}, {__mode = "k"})
    end
end
