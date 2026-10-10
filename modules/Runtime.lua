return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local Zzzz = ctx.ZzzzWorld
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions

    local Fluent, AutoSave, SaveManager = ctx.Fluent, ctx.AutoSave, ctx.SaveManager
    local afkConn = Player.Idled:Connect(function()
        if not S.Alive or not C.AFK then return end
        pcall(function()
            VU:CaptureController()
            VU:ClickButton2(Vector2.zero)
        end)
    end)

    function S.Stop()
        if AutoSave.Available and AutoSave.Ready and AutoSave.Dirty then
            pcall(function() SaveManager:Save(AutoSave.Name) end)
        end
        Raid.Enabled = false
        Raid.Target = nil
        Zzzz.Enabled = false
        Zzzz.Target = nil
        if S.Enabled and S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
            local savedNoclip = C.Noclip
            C.Noclip = false
            F.rubblePosition(S.RubbleRef)
            C.Noclip = savedNoclip
        end
        S.Alive = false
        S.Enabled = false
        F.cancelTravel()
        F.releaseHold()
        F.restoreCollisions()
        if S.noclipConn then S.noclipConn:Disconnect() end
        if S.holdConn then S.holdConn:Disconnect() end
        if afkConn then afkConn:Disconnect() end
        if S.UI and not S.UI.Unloaded then
            pcall(function() S.UI:Destroy() end)
        end
    end

    S.holdConn = RunService.Heartbeat:Connect(function()
        pcall(F.updateTravel)
        if not S.Alive or not (S.Enabled or Raid.Enabled or Zzzz.Enabled) or not S.HoldCF or S.Travel then return end
        local cf = S.HoldCF
        local char, root = F.character()
        if not char or not root then return end
        pcall(function()
            if root.Anchored then root.Anchored = false end
            local drift = root.Position - cf.Position
            if drift.Magnitude > 0.45 or math.abs(drift.Y) > 0.2 then
                char:PivotTo(cf)
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end)

    S.noclipConn = RunService.Stepped:Connect(function()
        if S.Alive and (S.Enabled or Raid.Enabled or Zzzz.Enabled) and C.Noclip
            and (Raid.Enabled or Zzzz.Enabled or S.Phase ~= "COMPLETED" or not S.FinalRestored) then
            pcall(F.applyNoclip)
        end
    end)

    Env.PcdBehindStable = S
    Env.PcdHxHHub = S

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            if ctx.EnforceFarmExclusivity then
                pcall(ctx.EnforceFarmExclusivity)
            end
            local ok, err = pcall(function()
                if S.Enabled then F.syncHUDProgress() end
                F.step()
            end)
            if not ok then
                S.Status = "Error: " .. tostring(err)
            end
            if Raid.Enabled then
                local raidOk = pcall(F.raidStep)
                if not raidOk then Raid.Status = "Raid temporarily unavailable" end
            end
            if Zzzz.Enabled then
                pcall(F.zzzzStep)
            end
            task.wait(0.05)
        end
    end)

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            task.wait(1)
            if S.Alive and S.Enabled and C.AutoReplay then
                local now = os.clock()
                local finishingBoss = S.Phase == "KILL_BOSS" and S.BossClearSince
                    and now - S.BossClearSince < 1.5
                local finishingStory = S.Phase == "FINAL_TELEPORT"
                    or (S.Phase == "COMPLETED" and S.FinishAt
                        and now - S.FinishAt < 1.5)
                local holdingResult = false
                if ctx.WebhookPauseReplay then
                    local ok, blocked = pcall(ctx.WebhookPauseReplay)
                    holdingResult = ok and blocked == true
                end
                if not finishingBoss and not finishingStory and not holdingResult then
                    local remote = RS:FindFirstChild("endAction")
                    if remote and remote:IsA("RemoteEvent") then
                        pcall(function()
                            remote:FireServer(buffer.fromstring("\001"))
                        end)
                    end
                end
            end
        end
    end)

end
