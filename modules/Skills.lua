return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local F = ctx.Functions


    function F.attackM1()
        if not C.M1 or not (Raid.Enabled or Zzzz.Enabled or (ctx.Lift and ctx.Lift.Enabled) or (ctx.Story and ctx.Story.Enabled)) then return end
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

    function F.pressKey(skill)
        if type(keypress) ~= "function" or type(keyrelease) ~= "function" then
            return false
        end
        local pressed = pcall(keypress, skill.VK)
        if not pressed then return false end
        task.wait(C.SkillKeyHold)
        pcall(keyrelease, skill.VK)
        return true
    end

    function F.pressVirtualKey(skill)
        if not VIM then return false end
        local pressed = pcall(function()
            VIM:SendKeyEvent(true, skill.Key, false, game)
        end)
        if not pressed then return false end
        task.wait(C.SkillKeyHold)
        pcall(function()
            VIM:SendKeyEvent(false, skill.Key, false, game)
        end)
        return true
    end

    function F.invokeSkill(skill)
        local used, method = false, ""
        if C.SkillInput == "keypress" then
            used, method = F.pressKey(skill), "keypress"
        elseif C.SkillInput == "VirtualInputManager" then
            used, method = F.pressVirtualKey(skill), "VirtualInputManager"
        else
            -- Automatic: one input path per press (sending both at once crashed
            -- the client). On PC the real OS-level keypress is the reliable path,
            -- because VirtualInputManager "succeeds" even when the game ignores
            -- it, so it never fell back. On mobile/touch, VIM stays first.
            local UIS = game:GetService("UserInputService")
            local isPC = UIS.KeyboardEnabled and not UIS.TouchEnabled
            if isPC then
                used, method = F.pressKey(skill), "keypress"
                if not used then
                    used, method = F.pressVirtualKey(skill), "VirtualInputManager"
                end
            else
                used, method = F.pressVirtualKey(skill), "VirtualInputManager"
                if not used then
                    used, method = F.pressKey(skill), "keypress"
                end
            end
        end

        S.SkillStatus = skill.Name .. ": " .. (used
            and ("Input sent through " .. method)
            or "Keyboard input unavailable")
        return used
    end

    local MIN_INPUT_GAP = 0.25 -- minimum time between two skill inputs (seconds)
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
        if not C.Skills or not (Raid.Enabled or Zzzz.Enabled or (ctx.Lift and ctx.Lift.Enabled) or (ctx.Story and ctx.Story.Enabled)) then
            return
        end

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
            if skill.Enabled and not skill.Busy
                and now - skill.Last >= skill.Delay then
                nextSkillIndex = index % #Skill + 1
                skill.Busy = true
                dispatching = true
                dispatchStarted = now
                local token = generation

                -- Queue inputs one at a time so simultaneous key presses
                -- cannot cancel or overlap one another during a long farm.
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
                            pausedUntil = os.clock() + 30
                            S.SkillStatus = "Skill input paused for 30s after repeated failures"
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
