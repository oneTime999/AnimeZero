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
    local FOLLOW_RANGE = 2     -- re-place only if the enemy moved farther than this
    local PLACE_COOLDOWN = 0.12 -- minimum seconds between two re-placements
    local TELEPORT_RANGE = 40  -- farther than this, glide instead of one jump
    local STUCK_REPLACE = 8    -- same enemy for this long: force a fresh placement
    local STUCK_SKIP = 25      -- same enemy for this long: skip it for a while
    local SKIP_TIME = 8        -- seconds a skipped enemy is ignored

    -- Attack placement. false = use the Position / Distance / Height from the
    -- UI (like the normal raid). true = use the fixed values below, which
    -- ignore whatever is saved in the UI.
    local BT_OWN_SETTINGS = false
    local BT_POSITION = "Below"
    local BT_DISTANCE = 0
    local BT_HEIGHT   = 0

    -- Boss phase (last phase): attacking from the ground bugs, so the boss is
    -- always attacked from above, whatever the UI says.
    local BT_BOSS_POSITION = "Above"
    local BT_BOSS_DISTANCE = 2   -- studs above the boss (plus half its height)
    local BT_BOSS_HEIGHT   = 0

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

    -- RunManage.Sheet.Title.Info reads like:
    --   Area 2  •  Wave 2/2  •  <font color="#FFC45C">Nightmare</font>
    -- Only the area and the wave are used.
    local function bathtubInfo()
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        local run = gui and gui:FindFirstChild("RunManage")
        local sheet = run and run:FindFirstChild("Sheet")
        local title = sheet and sheet:FindFirstChild("Title")
        local label = title and title:FindFirstChild("Info")
        if not label or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
            return nil
        end
        local text = string.gsub(label.Text or "", "<[^>]*>", "")
        local area = tonumber(string.match(text, "[Aa]rea%s*(%d+)"))
        local wave, total = string.match(text, "[Ww]ave%s*(%d+)%s*/%s*(%d+)")
        return {Area = area, Wave = tonumber(wave), Total = tonumber(total)}
    end

    -- True while the game is asking for the elevator. The HUD text is
    -- re-read on every call.
    local function bathtubElevatorState()
        local hud = bathtubHud()
        return hud ~= nil and hud.Elevator == true, bathtubInfo()
    end

    local function bathtubDebug(info, active)
        return string.format(" [Area %s | Wave %s/%s | elevator message: %s]",
            tostring(info and info.Area or "?"), tostring(info and info.Wave or "?"),
            tostring(info and info.Total or "?"), active and "yes" or "no")
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

    -- Attacks like the normal raid does (Position / Distance / Height, e.g.
    -- Below), but the character is placed and held floating there instead of
    -- being re-teleported every frame. It is only moved again when the
    -- target changes or the enemy walks away, and never more than once per
    -- PLACE_COOLDOWN. An enemy that does not die is retried, then skipped.
    -- Returns true when the character is in position to attack.
    function F.bathtubPlace(target)
        local _, root = F.character()
        if not root then return false end
        -- The boss is the "0" entry of the enemy folder. While it is alive the
        -- whole phase (boss and any adds) is fought from above.
        local isBoss = target.Name == "0" or Raid.BossPresent == true
        local dest
        if isBoss then
            dest = F.enemyDestination(target, BT_BOSS_POSITION, BT_BOSS_DISTANCE, BT_BOSS_HEIGHT)
        elseif BT_OWN_SETTINGS then
            dest = F.enemyDestination(target, BT_POSITION, BT_DISTANCE, BT_HEIGHT)
        else
            dest = F.enemyDestination(target)
        end
        if not dest then return false end
        F.floatEnable()
        F.disableCollisions()

        local bt = Raid.BT
        if not bt then
            bt = {Elevators = 0}
            Raid.BT = bt
        end
        local now = os.clock()

        -- Switching between ground enemies and the boss needs a fresh placement.
        if bt.PlacedBoss ~= isBoss then
            bt.PlacedBoss = isBoss
            bt.PlacedOn = nil
        end

        -- Watchdog for an enemy that never dies (unreachable / immune).
        if bt.WatchTarget ~= target then
            bt.WatchTarget = target
            bt.WatchSince = now
        end
        local onTarget = now - (bt.WatchSince or now)
        if onTarget >= STUCK_SKIP then
            bt.Skip = bt.Skip or {}
            bt.Skip[target] = now + SKIP_TIME
            bt.WatchTarget, bt.PlacedOn = nil, nil
            Raid.Target = nil
            return false
        elseif onTarget >= STUCK_REPLACE and now - (bt.StuckPlacedAt or 0) >= STUCK_REPLACE then
            bt.StuckPlacedAt = now
            bt.PlacedOn = nil
        end

        local away = (root.Position - dest.Position).Magnitude
        if bt.PlacedOn == target then
            if away <= FOLLOW_RANGE then return true end
            if now - (bt.PlacedAt or 0) < PLACE_COOLDOWN then return true end
        end

        if away > TELEPORT_RANGE then
            F.floatGlide(dest.Position, MOVE_SPEED)
            return false
        end
        F.floatPlace(dest)
        bt.PlacedOn = target
        bt.PlacedAt = now
        return true
    end

    -- Runs every tick while Bathtub is active, whether or not enemies exist.
    -- The elevator counts as taken once it was pressed and the HUD message
    -- went away. Returns true while the game is asking for the elevator.
    function F.bathtubSync(now)
        local bt = Raid.BT
        if not bt then
            bt = {Elevators = 0}
            Raid.BT = bt
        end
        local active = bathtubElevatorState()

        if bt.Fired and not active and now - (bt.FiredAt or 0) > 1 then
            bt.Fired = false
            bt.Arrived = false
            bt.Elevators += 1
            bt.ReadyForExit = false
            bt.PlacedOn = nil
            bt.RideUntil = now + 12
        end

        -- While at the elevator (and during the ride) fly/noclip stay off.
        Raid.Interacting = (active and bt.Arrived == true)
            or (bt.RideUntil ~= nil and now < bt.RideUntil)
        return active
    end

    -- No enemy to attack. Returns true when it handled the step (the raid
    -- logic should not act); false while the boss is involved so the raid
    -- logic keeps control of immunity, targeting and boss-defeat confirmation.
    --
    -- Everything is decided by what the game says (never by whether the
    -- Interact merely exists):
    --   Area 1, enemies gone   -> wait at HOVER_POS
    --   elevator message, Area 1 -> HOVER_POS, then EXIT_STAND_1, press Interact
    --   elevator message, Area 2 -> EXIT_STAND_2, press Interact
    --   Area 3                 -> only kill enemies
    -- With the message up: Interact exists -> spam it; missing -> keep going
    -- to the elevator position.
    function F.bathtubNavigate(now)
        local bt = Raid.BT
        if not bt then
            bt = {Elevators = 0}
            Raid.BT = bt
        end

        local elevatorActive, info = bathtubElevatorState()
        -- The elevator message wins over the boss logic; otherwise the boss
        -- stays under the raid logic's control.
        if not elevatorActive and (Raid.BossPresent or Raid.BossEngaged) then
            bt.BossSeen = true
            return false
        end

        local char, root = F.character()
        if not char or not root then return true end

        -- Area from the game; if unreadable, fall back to the elevators taken.
        local area = info and info.Area or (bt.Elevators + 1)
        local dbg = bathtubDebug(info, elevatorActive)

        local exit, prompt = bathtubExit()
        local promptReady = prompt ~= nil and prompt.Enabled ~= false and prompt:IsDescendantOf(WS)

        -- Riding: the game carries the character; fly/noclip stay off. Only
        -- step in when it got left far behind.
        if bt.RideUntil and now < bt.RideUntil and not elevatorActive then
            local pos = exit and prompt and promptPosition(exit, prompt)
            if pos and (root.Position - pos).Magnitude > 15 then
                F.floatGlide(pos + Vector3.new(0, 2.5, 0), MOVE_SPEED)
            end
            Raid.Status = "Riding the elevator" .. dbg
            return true
        end

        if elevatorActive then
            bt.RideUntil = nil

            -- Area 1: be at the start position first.
            if area <= 1 and not bt.ReadyForExit then
                local remaining = F.floatGlide(HOVER_POS, MOVE_SPEED)
                if remaining and remaining <= 2 then
                    bt.ReadyForExit = true
                else
                    Raid.Status = "Going back to the start position" .. dbg
                    return true
                end
            end

            local stand = area <= 1 and EXIT_STAND_1 or EXIT_STAND_2
            local promptPos = promptReady and promptPosition(exit, prompt) or nil
            if area >= 3 and promptPos then
                stand = promptPos + Vector3.new(0, 2.5, 0)
            elseif promptPos and (stand - promptPos).Magnitude > (prompt.MaxActivationDistance or 10) - 1 then
                -- The fixed point is out of the prompt's reach: use the prompt itself.
                stand = promptPos + Vector3.new(0, 2.5, 0)
            end

            -- Got pushed away after arriving: go back to flying to the point.
            if bt.Arrived and (root.Position - stand).Magnitude > 8 then
                bt.Arrived = false
            end
            if not bt.Arrived then
                local remaining = F.floatGlide(stand, MOVE_SPEED)
                if remaining and remaining <= 1.5 then bt.Arrived = true end
            end

            if bt.Arrived then
                -- Before interacting everything is switched off: fly (float),
                -- noclip, position hold and any tween.
                Raid.Interacting = true
                F.cancelTravel()
                F.releaseHold()
                F.floatDisable()
                F.restoreCollisions()

                if promptReady then
                    if now >= (bt.NextPromptAt or 0) then
                        bt.NextPromptAt = now + 0.25
                        if activatePrompt(prompt) then
                            bt.Fired = true
                            bt.FiredAt = now
                        end
                    end
                    Raid.Status = "Interacting with the elevator" .. dbg
                else
                    Raid.Status = "At the elevator; waiting for the Interact" .. dbg
                end
            else
                Raid.Status = "Moving to the elevator" .. dbg
            end
            return true
        end

        -- Not elevator time.
        bt.Arrived = false
        -- Waiting for enemies. Area 1: at the start position. Later areas:
        -- stay floating exactly where the elevator left us.
        if area <= 1 then
            local remaining = F.floatGlide(HOVER_POS, MOVE_SPEED)
            if remaining and remaining > 1.5 then
                Raid.Status = "Moving to the start position" .. dbg
            else
                Raid.Status = "At the start position; waiting for enemies" .. dbg
            end
        else
            F.floatEnable()
            Raid.Status = "Floating; waiting for enemies" .. dbg
        end
        return true
    end

    -- Watches the elevator message every frame (not only every 0.05s of the
    -- farm loop) so the moment the game asks for the elevator, it goes.
    do
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if not S.Alive then
                if conn then conn:Disconnect() end
                return
            end
            if not Raid.Enabled or Raid.Variant ~= "Bathtub" then return end
            pcall(function()
                local now = os.clock()
                if F.bathtubSync(now) then F.bathtubNavigate(now) end
            end)
        end)
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
        if Raid.Variant == "Bathtub" then
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

        local skipList = Raid.Variant == "Bathtub" and Raid.BT and Raid.BT.Skip or nil
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model.Name ~= "0" and F.living(model) then
                mobCount += 1
                local skipped = skipList and skipList[model] and skipList[model] > now
                local part = not skipped and F.partOf(model) or nil
                if part then
                    local distance = (root.Position - part.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestMob = model
                    end
                end
            end
        end

        -- Bathtub: keep fighting the same enemy until it dies instead of
        -- swapping to whichever is closest each tick (that caused jitter).
        if Raid.Variant == "Bathtub" and closestMob then
            local current = Raid.Target
            local skipped = skipList and current and skipList[current] and skipList[current] > now
            if current and current ~= closestMob and current.Parent == folder
                and current.Name ~= "0" and not skipped and F.living(current) and F.partOf(current) then
                closestMob = current
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
