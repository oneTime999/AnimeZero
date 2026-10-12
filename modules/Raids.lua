return function(ctx)
    local RS, Player = ctx.RS, ctx.Player
    local C, Raid = ctx.C, ctx.Raid
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
        local now = os.clock()
        if now < (Raid.NextReplayAt or 0) then return end
        Raid.NextReplayAt = now + 8

        -- The current Retry event is nested under runPackets.endAction.
        -- Preserve the root-level buffer call only as a compatibility fallback.
        local packets = RS:FindFirstChild("runPackets")
        local remote = packets and packets:FindFirstChild("endAction")
        local nestedRemote = remote ~= nil
        if not remote then
            remote = RS:FindFirstChild("endAction")
        end
        if not remote or not remote:IsA("RemoteEvent") then
            Raid.Status = "Waiting for replay remote"
            return
        end
        local ok = pcall(function()
            if nestedRemote then
                remote:FireServer(1)
            elseif buffer and type(buffer.fromstring) == "function" then
                remote:FireServer(buffer.fromstring("\\001"))
            else
                remote:FireServer(1)
            end
        end)

        if ok then
            -- Do not mark the round as restarted until enemies actually
            -- appear. Sending a RemoteEvent does not confirm server success.
            Raid.RoundFinished = true
            Raid.ReplayUntil = now + 2
            Raid.Target = nil
            F.releaseHold()
            Raid.Status = "Replay requested; waiting for the next round"
        else
            Raid.Status = "Replay unavailable; retrying"
        end
    end

    function F.raidStep()
        if not Raid.Enabled then return end

        local now = os.clock()
        -- Detect both wins and losses before waiting for a respawn.
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local endScreen = gui and gui:FindFirstChild("EndScreen")
        local resultVisible = endScreen and endScreen:IsA("ScreenGui") and endScreen.Enabled
        local resultFlag = gui and gui:GetAttribute("EndScreenActive") == true
        if (resultVisible or resultFlag) and not Raid.RoundFinished then
            Raid.RoundFinished = true
            Raid.Target = nil
            Raid.BossGoneAt = nil
            Raid.WebhookRoundFinishedAt = now
            F.releaseHold()
            Raid.Status = "Match ended; preparing replay"
        end
        if not F.character() then
            F.releaseHold()
            if Raid.RoundFinished and C.AutoReplay and now >= (Raid.NextReplayAt or 0) then
                local blocked = false
                if ctx.WebhookPauseReplay then
                    local ok, value = pcall(ctx.WebhookPauseReplay)
                    blocked = ok and value == true
                end
                if not blocked then F.raidReplay() end
            else
                Raid.Status = "Waiting for character"
            end
            return
        end

        if Raid.ReplayUntil > 0 and now >= Raid.ReplayUntil then
            Raid.ReplayUntil = 0
        end

        local folder = F.enemyFolder()
        if not folder then
            Raid.Target = nil
            F.releaseHold()
            if Raid.RoundFinished and C.AutoReplay then
                local blocked = false
                if ctx.WebhookPauseReplay then
                    local ok, value = pcall(ctx.WebhookPauseReplay)
                    blocked = ok and value == true
                end
                if not blocked then F.raidReplay() end
            else
                Raid.Status = "Waiting for raid enemies"
            end
            return
        end

        local tag = F.getRaidBossTag()
        -- Missing BossBar text is not proof that the boss is immune.
        -- Try combat if the server has no visible immunity indication.
        Raid.BossImmune = tag ~= nil
            and string.find(string.upper(tag), "IMMUNE", 1, true) ~= nil

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
            Raid.WebhookRoundFinishedAt = Raid.WebhookRoundFinishedAt or now
            if mobCount > 0 or Raid.BossPresent then
                Raid.RoundFinished = false
                Raid.BossEngaged = false
                Raid.BossGoneAt = nil
                Raid.ReplayUntil = 0
                Raid.NextReplayAt = 0
                Raid.WebhookRoundFinishedAt = nil
                Raid.Status = "New raid wave detected"
            elseif C.AutoReplay then
                local grace = now - Raid.WebhookRoundFinishedAt < 1.5
                local holdingResult = false
                if ctx.WebhookPauseReplay then
                    local ok, blocked = pcall(ctx.WebhookPauseReplay)
                    holdingResult = ok and blocked == true
                end
                if grace or holdingResult then
                    Raid.Status = "Waiting for match report before replay"
                elseif now < (Raid.NextReplayAt or 0) then
                    Raid.Status = "Waiting for the next raid round"
                else
                    F.raidReplay()
                end
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
            F.holdCombatPosition()
            return
        end

        if F.living(target) and F.enemyPosition(target) then
            F.attackM1()
            F.autoSkills()
        end
    end

end
