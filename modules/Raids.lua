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
    -- Fixed points of the run (confirmed positions).
    local HOVER_POS    = Vector3.new(-136.13002014160156, 11.75649642944336, -52.7960319519043)
    local EXIT_STAND_1 = Vector3.new(-168.78439331054688, 13.094907760620117, -47.073699951171875)
    local EXIT_STAND_2 = Vector3.new(385.58929443359375, 104.64099884033203, -56.74423599243164)
    local MOVE_SPEED   = 200   -- studs/second while gliding between points
    local ATTACK_DIST  = 5     -- horizontal distance to the enemy while attacking
    local ATTACK_HEIGHT = 4    -- height above the enemy while attacking
    local TELEPORT_RANGE = 40  -- farther than this, glide instead of one jump

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

    -- Floats in front of the enemy and stays there. The character is moved
    -- only when the target changes or the enemy walks away, never every frame.
    -- Returns true when the character is in position to attack.
    function F.bathtubPlace(target)
        local part = F.partOf(target)
        local _, root = F.character()
        if not part or not root then return false end
        F.floatEnable()
        F.disableCollisions()

        local bt = Raid.BT
        if not bt then
            bt = {Elevators = 0}
            Raid.BT = bt
        end

        local offset = root.Position - part.Position
        local flat = Vector3.new(offset.X, 0, offset.Z)
        local near = flat.Magnitude <= ATTACK_DIST + 4 and math.abs(offset.Y) <= ATTACK_HEIGHT + 5
        if bt.PlacedOn == target and near then return true end

        local side = flat.Magnitude > 0.1 and flat.Unit or -part.CFrame.LookVector
        local pos = part.Position + side * ATTACK_DIST + Vector3.new(0, ATTACK_HEIGHT, 0)
        if (root.Position - pos).Magnitude > TELEPORT_RANGE then
            F.floatGlide(pos, MOVE_SPEED)
            return false
        end
        local faceTo = Vector3.new(part.Position.X, pos.Y, part.Position.Z)
        F.floatPlace(CFrame.lookAt(pos, faceTo))
        bt.PlacedOn = target
        return true
    end

    -- Runs every tick while Bathtub is active, whether or not enemies exist.
    -- Re-reads the HUD text each time (it is the most reliable signal) and
    -- counts the elevator as taken once it was pressed and both the message
    -- and the Interact are gone. Returns true while the elevator message is up.
    function F.bathtubSync(now)
        local bt = Raid.BT
        if not bt then
            bt = {Elevators = 0}
            Raid.BT = bt
        end
        local hud = bathtubHud()
        local elevatorMsg = hud ~= nil and hud.Elevator == true
        local _, prompt = bathtubExit()
        local promptReady = prompt ~= nil and prompt.Enabled ~= false and prompt:IsDescendantOf(WS)

        if bt.Fired and not elevatorMsg and not promptReady then
            bt.Fired = false
            bt.Elevators += 1
            bt.ReadyForExit = false
            bt.PlacedOn = nil
            bt.RideUntil = now + 12
        end
        return elevatorMsg
    end

    -- No enemy to attack. Returns true when it handled the step (the raid
    -- logic should not act); false while the boss is involved so the raid
    -- logic keeps control of immunity, targeting and boss-defeat confirmation.
    --
    -- Flow:
    --   start            -> go to HOVER_POS and float there until enemies spawn
    --   enemies          -> raidStep attacks them (bathtubPlace)
    --   cleared          -> back to HOVER_POS, waiting for the next wave
    --   elevator message -> (from HOVER_POS) go to EXIT_STAND_1, use the prompt
    --   2nd elevator msg -> go to EXIT_STAND_2, use the same prompt
    --   last wave        -> only kill enemies, the round ends by itself
    function F.bathtubNavigate(now)
        local bt = Raid.BT
        if not bt then
            bt = {Elevators = 0}
            Raid.BT = bt
        end
        if Raid.BossPresent or Raid.BossEngaged then
            bt.BossSeen = true
            return false
        end

        local char, root = F.character()
        if not char or not root then return true end

        local hud = bathtubHud()
        local elevatorMsg = hud ~= nil and hud.Elevator

        -- Is there an Interact to press right now?
        local exit, prompt = bathtubExit()
        local promptReady = prompt ~= nil and prompt.Enabled ~= false and prompt:IsDescendantOf(WS)

        -- Riding: the Exit marker moves with the elevator. Only step in when
        -- the character gets left behind, instead of correcting it every frame
        -- (that fought the game's own movement and made the character spin).
        if bt.RideUntil and now < bt.RideUntil then
            local pos = exit and prompt and promptPosition(exit, prompt)
            F.floatEnable()
            if pos and (root.Position - pos).Magnitude > 8 then
                F.floatGlide(pos + Vector3.new(0, 2.5, 0), MOVE_SPEED)
            end
            Raid.Status = "Riding the elevator"
            return true
        end

        -- Elevator time: the message is up OR the Interact exists.
        --   * Interact exists   -> spam it (and stay within its reach)
        --   * Interact missing  -> keep going to the elevator position
        if elevatorMsg or promptReady then
            -- First elevator, nothing to press yet: be at the start position first.
            if bt.Elevators == 0 and not bt.ReadyForExit and not promptReady then
                local remaining = F.floatGlide(HOVER_POS, MOVE_SPEED)
                if remaining and remaining <= 2 then
                    bt.ReadyForExit = true
                else
                    Raid.Status = "Going back to the start position"
                    return true
                end
            end

            local stand = bt.Elevators == 0 and EXIT_STAND_1 or EXIT_STAND_2
            local promptPos = promptReady and promptPosition(exit, prompt) or nil
            -- If the fixed point is out of the prompt's reach, use the prompt itself.
            if promptPos and (stand - promptPos).Magnitude > (prompt.MaxActivationDistance or 10) - 1 then
                stand = promptPos + Vector3.new(0, 2.5, 0)
            end

            local remaining = F.floatGlide(stand, MOVE_SPEED)

            if promptReady then
                if now >= (bt.NextPromptAt or 0) then
                    bt.NextPromptAt = now + 0.25
                    if activatePrompt(prompt) then bt.Fired = true end
                end
                Raid.Status = "Interacting with the elevator"
            elseif remaining and remaining > 1.5 then
                Raid.Status = "Moving to the elevator"
            else
                Raid.Status = "At the elevator; waiting for the Interact"
            end
            return true
        end

        -- Waiting for enemies. First section: always at the start position.
        -- Later sections: stay floating exactly where the elevator left us.
        if bt.Elevators == 0 then
            local remaining = F.floatGlide(HOVER_POS, MOVE_SPEED)
            if remaining and remaining > 1.5 then
                Raid.Status = "Moving to the start position"
            else
                Raid.Status = "At the start position; waiting for enemies"
            end
        else
            F.floatEnable()
            Raid.Status = "Floating; waiting for enemies"
        end
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

        -- Bathtub: the elevator message beats everything else, even if an
        -- enemy is still listed. Checked every tick.
        if Raid.Variant == "Bathtub" and not Raid.RoundFinished then
            local elevatorMsg = F.bathtubSync(now)
            if elevatorMsg and F.bathtubNavigate(now) then
                Raid.Target = nil
                return
            end
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
            Raid.BT = Raid.BT or {Elevators = 0}
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
            if Raid.Variant == "Bathtub" then F.floatDisable() end
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

        if F.living(target) then
            local placed
            if Raid.Variant == "Bathtub" then
                placed = F.bathtubPlace(target)
            else
                placed = F.enemyPosition(target)
            end
            if placed then
                F.attackM1()
                F.autoSkills()
            end
        end
    end

end
