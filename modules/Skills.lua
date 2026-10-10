return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions


    function F.attackM1()
        if not C.M1 or not (S.Enabled or Raid.Enabled or Zzzz.Enabled) then return end
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
            local viaVirtual = F.pressVirtualKey(skill)
            local viaKey = F.pressKey(skill)
            used = viaVirtual or viaKey
            method = viaVirtual and viaKey and "VirtualInputManager + keypress"
                or (viaVirtual and "VirtualInputManager" or "keypress")
        end

        S.SkillStatus = skill.Name .. ": " .. (used
            and ("Input sent through " .. method)
            or "Keyboard input unavailable")
        return used
    end

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
        if not C.Skills or not (S.Enabled or Raid.Enabled or Zzzz.Enabled) then
            return
        end

        local now = os.clock()
        if dispatching and now - dispatchStarted > 3 then
            F.resetSkillQueue()
            S.SkillStatus = "Skill input timeout: queue recovered"
        end
        if dispatching then return end
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
                    local ok, err = pcall(F.invokeSkill, skill)
                    if not ok then
                        S.SkillStatus = skill.Name .. ": " .. tostring(err)
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
