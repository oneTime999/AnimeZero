return function(ctx)
    local RS, C, S = ctx.RS, ctx.C, ctx.S
    local Player, F = ctx.Player, ctx.Functions
    local records = {}
    local attempts = {}
    local dropState, subscription
    local lastProbe, lastScan, lastSend = -math.huge, -math.huge, -math.huge
    local lastWarning = -math.huge
    local scanIndex = 0
    local approach = nil
    local monitor = {
        Status = "Waiting", Source = "Not connected", Found = 0,
        InRange = 0, LastID = nil, Attempts = 0, Confirmed = 0,
        LastError = nil
    }
    ctx.DropMonitor = monitor

    local function getAtom(atom)
        if atom == nil then return nil end
        local ok, value = pcall(function() return atom:get() end)
        return ok and value or nil
    end

    local function validId(value)
        local id = tonumber(value)
        if id and id % 1 == 0 and id >= 0 and id <= 255 then
            return id
        end
        return nil
    end

    local function remember(id, drop)
        id = validId(id)
        if id == nil or not drop then return end
        local entry = records[id]
        if not entry then
            records[id] = {Drop = drop, AddedAt = os.clock()}
        else
            -- Proxy tables may be recreated without changing the drop ID.
            entry.Drop = drop
        end
    end

    local function forget(id, expected)
        local entry = records[id]
        if entry and (not expected or entry.Drop == expected) then
            records[id] = nil
            attempts[id] = nil
            if monitor.LastID == id then monitor.Confirmed += 1 end
        end
    end

    local function connect()
        if dropState then return true end
        if os.clock() - lastProbe < 4 then return false end
        lastProbe = os.clock()
        local root = RS:FindFirstChild("game")
        local stores = root and root:FindFirstChild("stores")
        local module = stores and stores:FindFirstChild("dropStore")
        if not (module and module:IsA("ModuleScript")) then
            monitor.Status = "DropStore unavailable"
            return false
        end
        local ok, value = pcall(require, module)
        local store = ok and type(value) == "table" and value.store
        local state = store and store.state
        if not state then
            monitor.Status = "Unable to access DropStore"
            return false
        end
        dropState = state
        monitor.Source = "ReplicatedStorage.game.stores.dropStore"

        local success, handler = pcall(function()
            return state:forPairs(function(rawId, drop)
                if not S.Alive then return end
                local id = validId(rawId)
                remember(id, drop)
                return function()
                    if id ~= nil then
                        forget(id, drop)
                    end
                end
            end)
        end)
        if success then
            subscription = handler
        else
            monitor.LastError = "DropStore observer unavailable; using direct scan"
        end
        monitor.Status = "Connected"
        return true
    end

    local function scan()
        if not dropState or os.clock() - lastScan < 0.3 then return end
        lastScan = os.clock()

        -- The game allocates drop IDs from 0 through 255. Query keys
        -- directly as a fallback when the observer or snapshot is delayed.
        local ok, all = pcall(function() return dropState:getAll() end)
        if ok and type(all) == "table" then
            local active = {}
            for rawId, drop in pairs(all) do
                local id = validId(rawId)
                if id ~= nil and drop then
                    active[id] = true
                    remember(id, drop)
                end
            end
            -- Only remove known records if getAll returns an authoritative
            -- snapshot. This also confirms previous recoverDrop requests.
            for id, entry in pairs(records) do
                if not active[id] then forget(id, entry.Drop) end
            end
        else
            for _ = 1, 32 do
                local id = scanIndex
                scanIndex = (scanIndex + 1) % 256
                local found, drop = pcall(function() return dropState:get(id) end)
                if found and drop ~= nil then
                    remember(id, drop)
                elseif found then
                    forget(id)
                end
            end
        end
    end

    local function readPosition(drop)
        if not drop then return nil end
        local ok, position = pcall(function()
            return getAtom(drop.position)
        end)
        return ok and typeof(position) == "Vector3" and position or nil
    end

    local function currentlyIdle()
        if S.Travel or S.Phase == "FINAL_TELEPORT"
            or S.Phase == "COMPLETED" then return false end
        if S.Enabled and S.Target then return false end
        if ctx.Raid.Enabled and ctx.Raid.Target then return false end
        if ctx.ZzzzWorld.Enabled and ctx.ZzzzWorld.Target then return false end
        if not (S.Enabled or ctx.Raid.Enabled or ctx.ZzzzWorld.Enabled) then
            return false
        end
        local guard = ctx.GameGuard
        local currentMode = S.Enabled and "Story"
            or (ctx.Raid.Enabled and "Raids" or "Zzz")
        if not guard or not guard.Allowed(currentMode) then return false end
        local ok, enemies = pcall(F.livingEnemyExists)
        return ok and not enemies
    end

    local function restorePosition(state)
        if approach ~= state then return end
        approach = nil
        if not S.Alive then return end
        -- Do not override the farm if it resumed attacking a new wave.
        if S.HoldCF ~= state.PickupCF then return end
        S.HoldCF = state.OriginalHold
        local char, root = F.character()
        if char and root then
            pcall(F.setPosition, state.OriginalCF, 0.6, false)
        end
    end

    local function maybeApproach(id, position, root, now)
        if approach or not currentlyIdle() then return false end
        local distance = (position - root.Position).Magnitude
        if distance <= 11 or distance > 75 then return false end
        local pickCF = CFrame.new(position + Vector3.new(0, 3, 0))
        local state = {
            ID = id, OriginalCF = root.CFrame,
            OriginalHold = S.HoldCF, PickupCF = pickCF
        }
        if F.setPosition(pickCF, 0.6, false) then
            approach = state
            S.HoldCF = pickCF
            monitor.Status = "Approaching drop " .. tostring(id)
            task.delay(1.1, function() restorePosition(state) end)
            return true
        end
        return false
    end

    local function pickup()
        local remote = RS:FindFirstChild("recoverDrop")
        if not remote or not remote:IsA("RemoteEvent") then
            monitor.Status = "recoverDrop remote missing"
            return
        end
        local _, root = F.character()
        if not root then return end
        local now = os.clock()
        if now - lastSend < 0.35 then return end

        local selected, bestDistance, inRange, count = nil, math.huge, 0, 0
        local nearestFar, farDistance, farPosition
        for id, record in pairs(records) do
            count += 1
            local pos = readPosition(record.Drop)
            if pos then
                local distance = (pos - root.Position).Magnitude
                if distance <= 12 then inRange += 1 end
                if now - record.AddedAt >= 1.4
                    and now - (attempts[id] or -math.huge) >= 2 then
                    if distance <= 12 and distance < bestDistance then
                        selected, bestDistance = id, distance
                    elseif distance > 12 and distance < farDistance then
                        nearestFar, farDistance, farPosition = id, distance, pos
                    end
                end
            end
        end
        monitor.Found, monitor.InRange = count, inRange

        if selected == nil then
            if nearestFar ~= nil then
                maybeApproach(nearestFar, farPosition, root, now)
                monitor.Status = approach and "Moving to nearby drop"
                    or "Waiting for a drop in pickup range"
            else
                monitor.Status = count > 0 and "Waiting for drop to be ready"
                    or "Waiting for drops"
            end
            return
        end
        attempts[selected], lastSend = now, now
        monitor.LastID = selected
        monitor.Attempts += 1
        monitor.Status = "Requesting drop " .. tostring(selected)
        local ok, err = pcall(function()
            -- The argument is a u16 dropStore ID, not a fixed drop number.
            remote:FireServer(selected)
        end)
        if not ok then
            monitor.LastError = tostring(err)
            if now - lastWarning >= 15 then
                lastWarning = now
                warn("[Slow Hub] recoverDrop failed: " .. tostring(err))
            end
        end
    end

    task.spawn(function()
        while S.Alive and not (ctx.Fluent and ctx.Fluent.Unloaded) do
            if C.AutoCollectDrops then
                local ok, err = pcall(function()
                    if connect() then
                        scan()
                        pickup()
                    end
                end)
                if not ok then
                    monitor.LastError = tostring(err)
                    if os.clock() - lastWarning > 15 then
                        lastWarning = os.clock()
                        warn("[Slow Hub] Auto Collect Drops error: " .. tostring(err))
                    end
                end
            elseif monitor.Status ~= "Disabled" then
                monitor.Status = "Disabled"
            end
            task.wait(0.15)
        end
        if approach then restorePosition(approach) end
        if type(subscription) == "function" then
            pcall(subscription)
        elseif typeof(subscription) == "RBXScriptConnection" then
            pcall(function() subscription:Disconnect() end)
        end
    end)

    if ctx.GameGuard and ctx.GameGuard.IsDeveloper() then
        ctx.DeveloperTests = ctx.DeveloperTests or {}
        table.insert(ctx.DeveloperTests, {
            Title = "Inspect Auto Collect Drops",
            Description = "Check live drop IDs, pickup range and last requests",
            Run = function()
                if not ctx.GameGuard.IsDeveloper() then
                    return false, "Developer only"
                end
                local ids = {}
                for id in pairs(records) do table.insert(ids, id) end
                table.sort(ids)
                local message = "Status: " .. tostring(monitor.Status)
                    .. " | Source: " .. tostring(monitor.Source)
                    .. " | Active drops: " .. tostring(monitor.Found)
                    .. " | In range: " .. tostring(monitor.InRange)
                    .. " | Requests: " .. tostring(monitor.Attempts)
                    .. " | Drops removed: " .. tostring(monitor.Confirmed)
                    .. " | Last ID: " .. tostring(monitor.LastID)
                    .. " | Known IDs: " .. table.concat(ids, ",")
                    .. " | Error: " .. tostring(monitor.LastError or "None")
                warn("[Slow Hub Drop Debug] " .. message)
                return true, message
            end
        })
    end
end
