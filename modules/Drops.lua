return function(ctx)
    local RS, C, S = ctx.RS, ctx.C, ctx.S
    local Player = ctx.Player
    local activeDrops = {}
    local lastSent = {}
    local subscribed, subscription = false, nil
    local lastSubscribeAttempt = -math.huge

    local function readAtom(atom)
        if atom == nil then return nil end
        local ok, result = pcall(function()
            return atom:get()
        end)
        return ok and result or nil
    end

    local function subscribe()
        if subscribed or os.clock() - lastSubscribeAttempt < 8 then
            return subscribed
        end
        lastSubscribeAttempt = os.clock()

        local root = RS:FindFirstChild("game")
        local stores = root and root:FindFirstChild("stores")
        local moduleScript = stores and stores:FindFirstChild("dropStore")
        if not (moduleScript and moduleScript:IsA("ModuleScript")) then
            return false
        end

        local ok, dropStore = pcall(require, moduleScript)
        if not ok or type(dropStore) ~= "table" then
            return false
        end
        local state = dropStore.store and dropStore.store.state
        if not state then return false end

        -- dropController uses the exact same store and obtains:
        -- drop.kind:get(), drop.position:get(), and the drop ID.
        local success, handle = pcall(function()
            return state:forPairs(function(dropId, drop)
                if dropId == nil or drop == nil or not S.Alive then
                    return
                end

                local record = {drop = drop}
                activeDrops[dropId] = record
                return function()
                    if activeDrops[dropId] == record then
                        activeDrops[dropId] = nil
                    end
                    lastSent[dropId] = nil
                end
            end)
        end)
        if not success then return false end

        subscription = handle
        subscribed = true
        return true
    end

    local function unsubscribe()
        if type(subscription) == "function" then
            pcall(subscription)
        elseif typeof(subscription) == "RBXScriptConnection" then
            pcall(function() subscription:Disconnect() end)
        end
        table.clear(activeDrops)
        table.clear(lastSent)
        subscribed = false
        subscription = nil
    end

    task.spawn(function()
        while S.Alive and not (ctx.Fluent and ctx.Fluent.Unloaded) do
            if C.AutoCollectDrops and subscribe() then
                local character = Player.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local remote = RS:FindFirstChild("recoverDrop")

                if root and humanoid and humanoid.Health > 0
                    and remote and remote:IsA("RemoteEvent") then
                    local now = os.clock()
                    local collected = 0

                    for dropId, record in pairs(activeDrops) do
                        if collected >= 2 then break end
                        local drop = record.drop
                        local kind = drop and readAtom(drop.kind)
                        local position = drop and readAtom(drop.position)

                        if (kind == "cash" or kind == "health")
                            and typeof(position) == "Vector3"
                            and (root.Position - position).Magnitude <= 12
                            and now - (lastSent[dropId] or -math.huge) >= 2 then
                            lastSent[dropId] = now
                            local ok = pcall(function()
                                remote:FireServer(dropId)
                            end)
                            if ok then collected += 1 end
                        end
                    end
                end
            end
            task.wait(0.25)
        end
        unsubscribe()
    end)
end
