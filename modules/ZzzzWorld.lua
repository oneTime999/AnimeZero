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

        Zzzz.Target = target
        if not target then
            -- Keep the last combat position while waiting for the next wave.
            if not S.HoldCF and not S.Travel then
                S.HoldCF = root.CFrame
            end
            return
        end

        if F.living(target) and F.enemyPosition(target) then
            F.attackM1()
            F.autoSkills()
        end
    end
end
