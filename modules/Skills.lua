return function(ctx)
    local RS = ctx.RS
    local VIM = ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local F = ctx.Functions
    local UIS = game:GetService("UserInputService")

    local function farming()
        return Raid.Enabled or Zzzz.Enabled
            or (ctx.Lift and ctx.Lift.Enabled)
            or (ctx.Story and ctx.Story.Enabled)
    end

    ----------------------------------------------------------------------
    -- Basic attack (unchanged)
    ----------------------------------------------------------------------
    function F.attackM1()
        if not C.M1 or not farming() then return end
        local now = os.clock()
        if now - S.LastM1 < C.M1Interval then return end
        local remote = RS:FindFirstChild("performM1")
        if not remote or not remote:IsA("RemoteEvent") then
            S.Status = "M1 unavailable"
            return
        end
        S.LastM1 = now
        remote:FireServer(nil)
    end

    ----------------------------------------------------------------------
    -- Input verification
    -- pcall() succeeding does NOT mean the game received the key (that was
    -- the old bug: VirtualInputManager "worked" but the game ignored it, and
    -- keypress was never tried). We listen to UserInputService and record
    -- whether each key really arrived, and whether the game was allowed to
    -- process it (processed == true means a UI/TextBox swallowed it).
    ----------------------------------------------------------------------
    local seen = {}
    local conn
    conn = UIS.InputBegan:Connect(function(input, processed)
        if not S.Alive then
            if conn then conn:Disconnect() end
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            seen[input.KeyCode] = {t = os.clock(), processed = processed}
        end
    end)

    -- A focused TextBox (e.g. a field in the hub UI or the chat) makes the
    -- game ignore every key. Release it before sending skills.
    local function releaseFocus()
        local ok, box = pcall(function() return UIS:GetFocusedTextBox() end)
        if ok and box then
            pcall(function() box:ReleaseFocus() end)
            return true
        end
        return false
    end

    local function holdTime()
        return math.max(C.SkillKeyHold or 0.06, 0.05)
    end

    function F.pressKey(skill)
        if type(keypress) ~= "function" or type(keyrelease) ~= "function" then
            return false
        end
        if not pcall(keypress, skill.VK) then return false end
        task.wait(holdTime())
        pcall(keyrelease, skill.VK)
        return true
    end

    function F.pressVirtualKey(skill)
        if not VIM then return false end
        local pressed = pcall(function()
            VIM:SendKeyEvent(true, skill.Key, false, game)
        end)
        if not pressed then return false end
        task.wait(holdTime())
        pcall(function()
            VIM:SendKeyEvent(false, skill.Key, false, game)
        end)
        return true
    end

    -- Returns "ok" | "blocked" | "unverified" | "unavailable"
    local function dispatch(method, skill)
        releaseFocus()
        local startedAt = os.clock()
        seen[skill.Key] = nil
        local sent
        if method == "keypress" then
            sent = F.pressKey(skill)
        else
            sent = F.pressVirtualKey(skill)
        end
        if not sent then return "unavailable" end

        local event = seen[skill.Key]
        if not event then
            task.wait(0.05) -- the event can land a frame late
            event = seen[skill.Key]
        end
        if event and event.t >= startedAt - 0.01 then
            return event.processed and "blocked" or "ok"
        end
        return "unverified"
    end

    local function methodOrder()
        local mode = C.SkillInput
        if mode == "keypress" then return {"keypress"} end
        if mode == "VirtualInputManager" then return {"VirtualInputManager"} end

        local order
        if S.SkillMethod then
            -- Remember what worked on this machine.
            order = {S.SkillMethod,
                S.SkillMethod == "keypress" and "VirtualInputManager" or "keypress"}
        elseif UIS.KeyboardEnabled and not UIS.TouchEnabled then
            order = {"keypress", "VirtualInputManager"} -- PC: real key first
        else
            order = {"VirtualInputManager", "keypress"} -- mobile
        end
        if not S.SkillMethod and S.SkillFlip then
            order = {order[2], order[1]}
        end
        return order
    end

    function F.invokeSkill(skill)
        local blockedBy, missing = nil, 0
        local order = methodOrder()

        for _, method in ipairs(order) do
            local result = dispatch(method, skill)
            if result == "ok" then
                S.SkillMethod = (C.SkillInput == "Automatic") and method or S.SkillMethod
                S.SkillBlind = 0
                S.SkillStatus = skill.Name .. ": key reached the game (" .. method .. ")"
                return true
            elseif result == "unverified" then
                -- Sent, but the executor never reported the key back. Do not
                -- send a second copy; rotate the method every few presses so
                -- both get a chance.
                S.SkillBlind = (S.SkillBlind or 0) + 1
                if S.SkillBlind % 4 == 0 then S.SkillFlip = not S.SkillFlip end
                S.SkillStatus = skill.Name .. ": sent via " .. method .. " (not verifiable)"
                return true
            elseif result == "blocked" then
                blockedBy = method
            else
                missing += 1
            end
        end

        if blockedBy then
            S.SkillStatus = skill.Name .. ": key was blocked by a focused UI/TextBox. "
                .. "Click on the game screen once."
        elseif missing == #order then
            S.SkillStatus = skill.Name .. ": no keyboard input available in this executor"
        else
            S.SkillStatus = skill.Name .. ": input failed"
        end
        return false
    end

    ----------------------------------------------------------------------
    -- Skill queue
    ----------------------------------------------------------------------
    local MIN_INPUT_GAP = 0.25
    local lastInputAt = 0
    local failedInputs = 0
    local pausedUntil = 0
    local nextSkillIndex = 1
    local dispatching = false
    local dispatchStarted = 0
    local generation = 0

    function F.resetSkillQueue()
        generation += 1
        dispatching = false
        dispatchStarted = 0
        for _, skill in ipairs(Skill) do
            skill.Busy = false
            skill.Last = -math.huge
        end
    end

    function F.autoSkills()
        if not C.Skills or not farming() then return end

        local now = os.clock()
        if dispatching and now - dispatchStarted > 3 then
            F.resetSkillQueue()
            S.SkillStatus = "Skill input timeout: queue recovered"
        end
        if dispatching then return end
        if now < pausedUntil or now - lastInputAt < (C.SkillInputGap or MIN_INPUT_GAP) then
            return
        end

        for offset = 0, #Skill - 1 do
            local index = (nextSkillIndex + offset - 1) % #Skill + 1
            local skill = Skill[index]
            if skill.Enabled and not skill.Busy and now - skill.Last >= skill.Delay then
                nextSkillIndex = index % #Skill + 1
                skill.Busy = true
                dispatching = true
                dispatchStarted = now
                local token = generation

                -- One input at a time so keys cannot overlap or cancel.
                task.spawn(function()
                    local ok, result = pcall(F.invokeSkill, skill)
                    if not ok then
                        S.SkillStatus = skill.Name .. ": " .. tostring(result)
                    end
                    lastInputAt = os.clock()
                    if ok and result then
                        failedInputs = 0
                    else
                        failedInputs += 1
                        if failedInputs >= 5 then
                            failedInputs = 0
                            pausedUntil = os.clock() + 10
                            S.SkillStatus = "Skill input paused for 10s after repeated failures"
                        end
                    end
                    if generation == token then
                        skill.Last = os.clock()
                        skill.Busy = false
                        dispatching = false
                        dispatchStarted = 0
                    end
                end)
                return
            end
        end
    end
end
