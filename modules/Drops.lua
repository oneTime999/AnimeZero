return function(ctx)
    local RS, C, S = ctx.RS, ctx.C, ctx.S
    local Player = ctx.Player
    local records, lastAttempt = {}, {}
    local store, release = nil, nil
    local lastStoreProbe = -math.huge
    local lastRequestAt = -math.huge
    local lastRemoteErrorAt = -math.huge

    local function validId(value)
        local id = tonumber(value)
        if id and id == math.floor(id) and id >= 0 and id <= 65535 then
            return id
        end
        return nil
    end

    local function readAtom(value)
        if value == nil then return nil end
        if type(value) ~= "table" or type(value.get) ~= "function" then
            return value
        end
        local ok, result = pcall(value.get, value)
        return ok and result or nil
    end

    local function readPosition(drop)
        if type(drop) ~= "table" then return nil end
        local position = readAtom(drop.position)
        return typeof(position) == "Vector3" and position or nil
    end

    local function remember(rawId, drop)
        local id = validId(rawId)
        if not id or drop == nil then return end
        local previous = records[id]
        if not previous or previous.drop ~= drop then
            records[id] = {drop = drop, seenAt = os.clock()}
            lastAttempt[id] = nil
        end
    end

    local function connectStore()
        if store then return store end
        local now = os.clock()
        if now - lastStoreProbe < 5 then return nil end
        lastStoreProbe = now

        local gameFolder = RS:FindFirstChild("game")
        local stores = gameFolder and gameFolder:FindFirstChild("stores")
        local module = stores and stores:FindFirstChild("dropStore")
        if not (module and module:IsA("ModuleScript")) then return nil end

        local ok, result = pcall(require, module)
        local state = ok and type(result) == "table"
            and result.store and result.store.state
        if not state then return nil end
        store = state

        -- This is the same listener used by the game's dropController.
        -- It identifies each drop by its actual u16 store key.
        if type(state.forPairs) == "function" then
            local subscribed, subscription = pcall(function()
                return state:forPairs(function(id, drop)
                    if not S.Alive then return end
                    remember(id, drop)
                    local numericId = validId(id)
                    return function()
                        if numericId and records[numericId]
                            and records[numericId].drop == drop then
                            records[numericId] = nil
                            lastAttempt[numericId] = nil
                        end
                    end
                end)
            end)
            if subscribed then
                release = subscription
            else
                warn("[Slow Hub] Drop store listener unavailable; using snapshot")
            end
        end
        return store
    end

    local function snapshot()
        local state = connectStore()
        if not state then return end

        -- Covers drops already present before the listener was installed.
        -- Also allows recovery if a particular forPairs callback was missed.
        if type(state.getAll) ~= "function" then return end
        local ok, entries = pcall(state.getAll, state)
        if not ok or type(entries) ~= "table" then return end

        local present = {}
        for rawId, drop in pairs(entries) do
            local id = validId(rawId)
            if id and drop ~= nil then
                present[id] = true
                remember(id, drop)
            end
        end
        for id in pairs(records) do
            if not present[id] then
                records[id] = nil
                lastAttempt[id] = nil
            end
        end
    end

    local function pickup()
        local remote = RS:FindFirstChild("recoverDrop")
        if not (remote and remote:IsA("RemoteEvent")) then return end
        if os.clock() - lastRequestAt < 0.3 then return end

        local character = Player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid or humanoid.Health <= 0 then return end

        local chosen, closest = nil, math.huge
        local now = os.clock()
        for id, record in pairs(records) do
            if now - record.seenAt >= 0.15
                and now - (lastAttempt[id] or -math.huge) >= 2 then
                local position = readPosition(record.drop)
                local distance = position and (position - root.Position).Magnitude
                    or math.huge
                if not chosen or distance < closest then
                    chosen, closest = id, distance
                end
            end
        end

        if chosen == nil then return end
        lastRequestAt = now
        lastAttempt[chosen] = now

        -- The numeric argument is the drop's actual ID, not a fixed ID.
        -- Sending a request does not guarantee the server accepted it.
        local ok, err = pcall(function()
            remote:FireServer(chosen)
        end)
        if not ok and now - lastRemoteErrorAt > 15 then
            lastRemoteErrorAt = now
            warn("[Slow Hub] Auto Collect Drops: " .. tostring(err))
        end
    end

    task.spawn(function()
        while S.Alive and not (ctx.Fluent and ctx.Fluent.Unloaded) do
            if C.AutoCollectDrops then
                local ok, err = pcall(function()
                    snapshot()
                    pickup()
                end)
                if not ok and os.clock() - lastRemoteErrorAt > 15 then
                    lastRemoteErrorAt = os.clock()
                    warn("[Slow Hub] Drop collector: " .. tostring(err))
                end
            end
            task.wait(0.15)
        end
        if type(release) == "function" then
            pcall(release)
        elseif typeof(release) == "RBXScriptConnection" then
            pcall(function() release:Disconnect() end)
        end
        table.clear(records)
        table.clear(lastAttempt)
    end)
end
