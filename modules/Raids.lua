return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions

    function F.getRaidBossTag()
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local bar = gui and gui:FindFirstChild("BossBar")
        local container = bar and bar:FindFirstChild("Container")
        local header = container and container:FindFirstChild("Header")
        local tag = header and header:FindFirstChild("Tag")
        if tag and (tag:IsA("TextLabel") or tag:IsA("TextButton")) then
            return tag.Text
        end
        return nil
    end

    function F.raidReplay()
        local remote = RS:FindFirstChild("endAction")
        if not remote or not remote:IsA("RemoteEvent") then
            Raid.Status = "Waiting for replay remote"
            return
        end

        local ok = pcall(function()
            remote:FireServer(buffer.fromstring("\001"))
        end)

        if ok then
            Raid.RoundFinished = false
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
            Raid.Target = nil
            Raid.ReplayUntil = os.clock() + 5
            F.releaseHold()
            Raid.Status = "Replay sent; waiting 5 seconds"
        else
            Raid.Status = "Waiting to retry replay"
        end
    end

    function F.raidStep()
        if not Raid.Enabled or S.Enabled then return end

        if not F.character() then
            F.releaseHold()
            Raid.Status = "Waiting for character"
            return
        end

        local now = os.clock()
        if Raid.ReplayUntil > 0 then
            if now < Raid.ReplayUntil then
                Raid.Status = string.format("Replay cooldown: %.1fs", Raid.ReplayUntil - now)
                return
            end
            Raid.ReplayUntil = 0
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
            Raid.RoundFinished = false
            Raid.Target = nil
        end

        local folder = F.enemyFolder()
        if not folder then
            Raid.Target = nil
            F.releaseHold()
            Raid.Status = "Waiting for raid enemies"
            return
        end

        local tag = F.getRaidBossTag()
        Raid.BossImmune = not tag or string.find(string.upper(tag), "IMMUNE", 1, true) ~= nil

        local boss = folder:FindFirstChild("0")
        Raid.BossPresent = boss ~= nil and F.living(boss)

        local _, root = F.character()
        local closestMob, closestDistance = nil, math.huge
        local mobCount = 0

        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model.Name ~= "0" and F.living(model) then
                mobCount += 1
                local part = F.partOf(model)
                if part then
                    local distance = (root.Position - part.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestMob = model
                    end
                end
            end
        end

        if Raid.RoundFinished then
            Raid.Target = nil
            F.releaseHold()
            if mobCount > 0 or Raid.BossPresent then
                Raid.RoundFinished = false
                Raid.BossEngaged = false
                Raid.BossGoneAt = nil
            elseif Raid.AutoReplay then
                F.raidReplay()
            else
                Raid.Status = "Boss defeated"
            end
            return
        end

        local target
        if closestMob then
            target = closestMob
            Raid.BossGoneAt = nil
            if Raid.BossPresent and Raid.BossImmune then
                Raid.BossEngaged = false
            end
            Raid.Status = string.format("Clearing raid enemies (%d remaining)", mobCount)
        elseif Raid.BossPresent and not Raid.BossImmune then
            target = boss
            Raid.BossEngaged = true
            Raid.BossGoneAt = nil
            Raid.Status = "Attacking Shadow Monarch boss"
        elseif Raid.BossPresent then
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
            Raid.Status = "Boss immune; waiting for enemies or vulnerability"
        elseif Raid.BossEngaged and mobCount == 0 then
            Raid.BossGoneAt = Raid.BossGoneAt or now
            if now - Raid.BossGoneAt >= C.ConfirmClear then
                Raid.RoundFinished = true
                F.releaseHold()
                Raid.Status = "Boss defeated"
            else
                Raid.Status = "Confirming boss defeat"
            end
        else
            Raid.BossGoneAt = nil
            Raid.Status = "Waiting for raid enemies"
        end

        Raid.Target = target
        if not target then
            F.releaseHold()
            return
        end

        if F.living(target) and F.enemyPosition(target) then
            F.attackM1()
            F.autoSkills()
        end
    end

end
