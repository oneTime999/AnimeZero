return function(ctx)
    local F = ctx.Functions
    local Zzzz = ctx.ZzzzWorld
    local S = ctx.S

    function F.zzzzStep()
        if not Zzzz.Enabled then return end

        local _, root = F.character()
        if not root then
            Zzzz.Target = nil
            F.releaseHold()
            return
        end

        local enemies = F.enemyFolder()
        if not enemies then
            Zzzz.Target = nil
            if not S.HoldCF and not S.Travel then
                S.HoldCF = root.CFrame
            end
            return
        end

        local now = os.clock()
        local target = Zzzz.Target
        if not target or target.Parent ~= enemies or not F.living(target) then
            target = nil
        end

        if not target then
            local distance = math.huge
            for _, enemy in ipairs(enemies:GetChildren()) do
                if enemy:IsA("Model") and F.living(enemy) then
                    local part = F.partOf(enemy)
                    if part then
                        local current = (root.Position - part.Position).Magnitude
                        if current < distance then
                            target = enemy
                            distance = current
                        end
                    end
                end
            end
        end

        if not target then
            Zzzz.Target = nil
            Zzzz.LastHealth = nil
            Zzzz.LastProgressAt = nil
            -- Keep the last combat position while waiting for the next wave.
            if not S.HoldCF and not S.Travel then
                S.HoldCF = root.CFrame
            end
            Zzzz.Status = "Waiting for the next wave"
            return
        end

        local hp = F.hpOf(target)
        if target ~= Zzzz.Target then
            Zzzz.LastHealth = hp
            Zzzz.LastProgressAt = now
        elseif hp and Zzzz.LastHealth and hp < Zzzz.LastHealth - 0.01 then
            Zzzz.LastProgressAt = now
        end
        Zzzz.Target = target
        Zzzz.LastHealth = hp

        if now - (Zzzz.LastProgressAt or now) >= 20
            and now - (Zzzz.LastRecoveryAt or -math.huge) >= 12 then
            Zzzz.LastRecoveryAt = now
            Zzzz.LastProgressAt = now
            Zzzz.Target = nil
            F.releaseHold()
            if F.resetSkillQueue then F.resetSkillQueue() end
            S.LastM1 = 0
            Zzzz.Status = "Retrying stalled Zzz World combat"
            warn("[Slow Hub] Zzz World combat stalled; retrying target")
            return
        end

        if F.living(target) and F.enemyPosition(target) then
            Zzzz.Status = "Attacking " .. target.Name
            F.attackM1()
            F.autoSkills()
        else
            Zzzz.PositionFailedAt = Zzzz.PositionFailedAt or now
            if now - Zzzz.PositionFailedAt >= 6 then
                Zzzz.Target = nil
                Zzzz.PositionFailedAt = nil
                F.releaseHold()
            end
            Zzzz.Status = "Retrying Zzz World positioning"
            return
        end
        Zzzz.PositionFailedAt = nil
    end
end
