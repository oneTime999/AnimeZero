return function(ctx)
    local RS, C, S = ctx.RS, ctx.C, ctx.S
    local activeDrops = {}
    local lastSent = {}
    local subscribed, subscription = false, nil
    local lastSubscribeAttempt = -math.huge

    local function subscribe()
        if subscribed or os.clock() - lastSubscribeAttempt < 8 then
            return subscribed
        end
        lastSubscribeAttempt = os.clock()

        local root = RS:FindFirstChild("game")
        local stores = root and root:FindFirstChild("stores")
        local script = stores and stores:FindFirstChild("dropStore")
        if not (script and script:IsA("ModuleScript")) then
            return false
        end

        local ok, storeModule = pcall(require, script)
        if not ok or type(storeModule) ~= "table" then
            return false
        end

        local state = storeModule.store and storeModule.store.state
        if not state then return false end

        -- dropController receives the drop's actual ID from forPairs
        -- and sends that ID to recoverDrop once it is picked up.
        local success, handle = pcall(function()
            return state:forPairs(function(dropId)
                if dropId == nil or not S.Alive then return end
                activeDrops[dropId] = true

                return function()
                    activeDrops[dropId] = nil
                    lastSent[dropId] = nil
                end
            end)
        end)
        if not success then return false end

        subscribed = true
        subscription = handle
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
    end

    task.spawn(function()
        while S.Alive and not (ctx.Fluent and ctx.Fluent.Unloaded) do
            if C.AutoCollectDrops then
                if subscribe() then
                    local remote = RS:FindFirstChild("recoverDrop")
                    if remote and remote:IsA("RemoteEvent") then
                        local now = os.clock()
                        local sent = 0
                        for dropId in pairs(activeDrops) do
                            if sent >= 2 then break end
                            if now - (lastSent[dropId] or -math.huge) >= 2 then
                                lastSent[dropId] = now
                                -- Avoid moving the character or fighting the
                                -- existing Story/Raid positioning controllers.
                                local ok = pcall(function()
                                    remote:FireServer(dropId)
                                end)
                                if ok then sent += 1 end
                            end
                        end
                    end
                end
            end
            task.wait(0.25)
        end
        unsubscribe()
    end)
end
