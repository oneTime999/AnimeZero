return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
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
                remote:FireServer(buffer.fromstring("\001"))
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

    ----------------------------------------------------------------------
    -- Spirit's Bathtub (Raid.Variant == "Bathtub")
    -- Combat, boss immunity, replay and round end stay with the raid logic;
    -- this only handles reaching the points that make enemies spawn.
    ----------------------------------------------------------------------
    local BATHTUB_ENTRY = Vector3.new(-136.5164337158203, 3.8978652954101562, -54.95354461669922)

    local function bathtubHud()
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local hud = gui and gui:FindFirstChild("RoundHUD")
        local container = hud and hud:FindFirstChild("Container")
        local topPart = container and container:FindFirstChild("TopPart")
        local frame = topPart and topPart:FindFirstChild("RemainingFrame")
        local label = frame and frame:FindFirstChild("EnemyCount")
        if not label or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
            return nil
        end
        local lower = string.lower(label.Text or "")
        return {
            Text = label.Text,
            Left = tonumber(lower:match("(%d+)%s+left")),
            Elevator = string.find(lower, "head to the elevator", 1, true) ~= nil
        }
    end

    -- The Exit marker changes position between sections but keeps its name,
    -- so it is resolved by path every time and never stored.
    local function bathtubExit()
        local world = WS:FindFirstChild("World")
        local markers = world and world:FindFirstChild("Markers")
        local exit = markers and markers:FindFirstChild("Exit")
        if not exit then return nil end
        local prompt = exit:FindFirstChild("ExitPrompt", true)
            or exit:FindFirstChildWhichIsA("ProximityPrompt", true)
        return exit, prompt
    end

    local function promptPosition(exit, prompt)
        local holder = prompt and prompt.Parent
        if holder then
            if holder:IsA("BasePart") then return holder.Position end
            if holder:IsA("Attachment") then return holder.WorldPosition end
            if holder:IsA("Model") then return holder:GetPivot().Position end
        end
        if exit then
            if exit:IsA("BasePart") then return exit.Position end
            if exit:IsA("Model") then return exit:GetPivot().Position end
            local part = exit:FindFirstChildWhichIsA("BasePart", true)
            if part then return part.Position end
        end
        return nil
    end

    local function activatePrompt(prompt)
        if not prompt or not prompt:IsDescendantOf(WS) then return false end
        local ok = false
        if type(fireproximityprompt) == "function" then
            ok = pcall(fireproximityprompt, prompt)
        end
        if not ok then
            ok = pcall(function()
                prompt:InputHoldBegin()
                task.wait(math.max(prompt.HoldDuration, 0.1))
                prompt:InputHoldEnd()
            end)
        end
        return ok
    end

    -- Returns true when it handled the step (the raid logic should not act).
    -- Returns false while the boss is involved, so the raid logic keeps
    -- control of immunity, targeting and boss-defeat confirmation.
    function F.bathtubNavigate(now)
        local bt = Raid.BT
        if not bt then
            bt = {Stage = 1}
            Raid.BT = bt
        end
        if Raid.BossPresent or Raid.BossEngaged then
            bt.BossSeen = true
            return false
        end

        local hud = bathtubHud()
        local left = hud and hud.Left
        local waiting = left ~= nil and left > 0

        -- Fallback when the HUD message is missing: later sections cleared for
        -- a few seconds with nothing left to spawn.
        -- Only used when the HUD is unavailable: with the HUD present the
        -- elevator message is trusted, so the gap between two waves is never
        -- mistaken for a cleared section.
        if hud == nil and bt.Stage >= 2 and not bt.BossSeen then
            bt.ClearedSince = bt.ClearedSince or now
        else
            bt.ClearedSince = nil
        end
        local cleared = bt.ClearedSince ~= nil and now - bt.ClearedSince >= 3

        -- Elevator: go to the Exit marker and interact with its prompt.
        if (hud and hud.Elevator) or cleared then
            local exit, prompt = bathtubExit()
            local pos = exit and prompt and promptPosition(exit, prompt)
            if not pos then
                Raid.Status = "Waiting for the Exit prompt"
                return true
            end

            local remaining = F.stepTo(pos + Vector3.new(0, 2.5, 0), 150)
            if not remaining then
                Raid.Status = "Waiting for character"
            elseif remaining > 3 then
                Raid.Status = "Moving to the elevator"
            elseif prompt.Enabled == false then
                Raid.Status = "Elevator not ready"
            elseif now >= (bt.NextPromptAt or 0) then
                bt.NextPromptAt = now + 1.25
                if activatePrompt(prompt) then
                    bt.Stage = math.max(bt.Stage, 2)
                    bt.ClearedSince = nil
                    -- The old entry point is meaningless after the ride, and the
                    -- marker moves with the elevator: follow it for a while.
                    bt.Anchor = nil
                    bt.FollowUntil = now + 15
                    Raid.Status = "Interact activated; waiting for enemies"
                else
                    Raid.Status = "Exit interaction unavailable; retrying"
                end
            else
                Raid.Status = "Waiting at the elevator"
            end
            return true
        end

        -- First section: enemies spawn once the entry point is reached.
        if bt.Stage == 1 and not bt.Anchor and (left == nil or left > 0) then
            local remaining = F.stepTo(BATHTUB_ENTRY, 150)
            if not remaining then
                Raid.Status = "Waiting for character"
            elseif remaining > 2 then
                Raid.Status = "Moving to the entry point"
            else
                bt.Anchor = BATHTUB_ENTRY
                Raid.Status = "At the entry point; waiting for enemies"
            end
            return true
        end

        -- Riding the elevator: stay on it while the marker moves.
        if bt.FollowUntil and now < bt.FollowUntil then
            local exit, prompt = bathtubExit()
            local pos = exit and prompt and promptPosition(exit, prompt)
            if pos then
                F.stepTo(pos + Vector3.new(0, 2.5, 0), 150)
                Raid.Status = "Riding the elevator"
                return true
            end
        end

        -- After a respawn in the first section, go back to the entry point.
        local char, root = F.character()
        if bt.Char and char and bt.Char ~= char then bt.Returning = true end
        bt.Char = char or bt.Char
        if bt.Returning and bt.Anchor then
            local remaining = F.stepTo(bt.Anchor, 150)
            if remaining and remaining > 3 then
                Raid.Status = "Returning to the entry point"
                return true
            end
            bt.Returning = false
        end

        -- Between waves: stay fixed exactly where the last attack position was
        -- (never released, so there is nothing to fall from).
        local hold = S.HoldCF
        if hold then
            F.setPosition(hold, 0.25, true)
        elseif root then
            F.setPosition(root.CFrame, 0.25, true)
        end
        Raid.Status = "Waiting for enemies to spawn"
        return true
    end

    function F.raidStep()
        if not Raid.Enabled then return end

        local now = os.clock()
        -- Detect both wins and losses before waiting for a respawn.
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local endScreen = gui and gui:FindFirstChild("EndScreen")
        local resultVisible = endScreen and endScreen:IsA("ScreenGui") and endScreen.Enabled
        local resultFlag = gui and gui:GetAttribute("EndScreenActive") == true
        if resultVisible or resultFlag then Raid.BTEndSeen = true end
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
            if Raid.Variant == "Bathtub" and not Raid.RoundFinished and F.bathtubNavigate(now) then
                Raid.Target = nil
                return
            end
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
        if Raid.Variant == "Bathtub" and Raid.BossPresent then
            Raid.BT = Raid.BT or {Stage = 1}
            Raid.BT.BossSeen = true
        end

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
            local newRound = mobCount > 0 or Raid.BossPresent
            if not newRound and Raid.Variant == "Bathtub" then
                -- Enemies only spawn after reaching the entry point, so a new run
                -- is recognized by the end screen closing for a moment.
                if resultVisible or resultFlag then
                    Raid.BTGoneAt = nil
                elseif Raid.BTEndSeen then
                    Raid.BTGoneAt = Raid.BTGoneAt or now
                    newRound = now - Raid.BTGoneAt >= 1.5
                end
            end
            if newRound then
                Raid.BT = nil
                Raid.BTEndSeen = false
                Raid.BTGoneAt = nil
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

        if not target and Raid.Variant == "Bathtub" and F.bathtubNavigate(now) then
            Raid.Target = nil
            return
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
