return function(ctx)
    local Players, RS, WS, RunService, VU = ctx.Players, ctx.RS, ctx.WS, ctx.RunService, ctx.VU
    local Player, Env, VIM = ctx.Player, ctx.Env, ctx.VIM
    local C, S, Raid, Skill = ctx.C, ctx.S, ctx.Raid, ctx.Skill
    local RubbleCoordinates, WaveCoordinates = ctx.RubbleCoordinates, ctx.WaveCoordinates
    local LastBorder, LastEnemyWave = ctx.LastBorder, ctx.LastEnemyWave
    local F = ctx.Functions

    local Fluent, AutoSave, SaveManager = ctx.Fluent, ctx.AutoSave, ctx.SaveManager
    local Stat, RaidStat = ctx.StoryStatus, ctx.RaidStatus
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
        if not S.Alive or not (S.Enabled or Raid.Enabled) or not S.HoldCF or S.Travel then return end
        local cf = S.HoldCF
        local char, root = F.character()
        if not char or not root then return end
        pcall(function()
            if root.Anchored then root.Anchored = false end
            if (root.Position - cf.Position).Magnitude > 0.45 then
                char:PivotTo(cf)
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end)

    S.noclipConn = RunService.Stepped:Connect(function()
        if S.Alive and (S.Enabled or Raid.Enabled) and C.Noclip
            and (Raid.Enabled or S.Phase ~= "COMPLETED" or not S.FinalRestored) then
            pcall(F.applyNoclip)
        end
    end)

    Env.PcdBehindStable = S
    Env.PcdHxHHub = S

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
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
            task.wait(0.05)
        end
    end)

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            task.wait(5)
            if S.Alive and S.Enabled and C.AutoReplay then
                local remote = RS:FindFirstChild("endAction")
                if remote and remote:IsA("RemoteEvent") then
                    pcall(function()
                        remote:FireServer(buffer.fromstring("\001"))
                    end)
                end
            end
        end
    end)

    task.spawn(function()
        while S.Alive and not Fluent.Unloaded do
            pcall(function()
                Stat:SetDesc(string.format("Mode: %s | Area: %d | Wave: %d/%d\n%s",
                    S.Difficulty, S.BorderNumber, S.SubWave, S.ExpectedSubWaves, S.Status))
                RaidStat:SetDesc(Raid.Status)
            end)
            task.wait(0.5)
        end
    end)

end
