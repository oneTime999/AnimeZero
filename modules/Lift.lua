return function(ctx)
    local WS, RS = ctx.WS, ctx.RS
    local Lift, S, C = ctx.Lift, ctx.S, ctx.C
    local F = ctx.Functions
    local Player = ctx.Player

    local function getPrompt()
        local world = WS:FindFirstChild("World")
        local markers = world and world:FindFirstChild("Markers")
        local lift = markers and markers:FindFirstChild("Lift")
        local prompt = lift and lift:FindFirstChildWhichIsA("ProximityPrompt", true)
        return lift, prompt
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

    function F.liftStep()
        if not Lift.Enabled then return end
        local _, root = F.character()
        if not root then
            Lift.Target = nil
            Lift.Status = "Waiting for character"
            return
        end

        local lift, prompt = getPrompt()
        if not lift or not prompt then
            Lift.Status = "Waiting for Lift prompt"
            Lift.Target = nil
            return
        end

        local enemies = F.enemyFolder()
        local target, distance = nil, math.huge
        if enemies then
            for _, enemy in ipairs(enemies:GetChildren()) do
                if enemy:IsA("Model") and F.living(enemy) then
                    local part = F.partOf(enemy)
                    if part then
                        local d = (root.Position - part.Position).Magnitude
                        if d < distance then
                            target, distance = enemy, d
                        end
                    end
                end
            end
        end

        if target then
            if S.Travel then F.cancelTravel() end
            F.releaseHold()
            Lift.Target = target
            Lift.NextPromptAt = 0
            local positioned = F.enemyPosition(target)
            if positioned and F.living(target) then
                Lift.Status = "Attacking " .. target.Name
                F.attackM1()
                F.autoSkills()
            else
                Lift.Status = "Positioning for " .. target.Name
            end
            return
        end

        Lift.Target = nil
        local part = lift:IsA("BasePart") and lift or lift:FindFirstChildWhichIsA("BasePart", true)
        if not part then
            Lift.Status = "Lift has no usable part"
            return
        end

        local goal = part.CFrame + Vector3.new(0, 2.5, 0)
        local arrived = F.travelTo(goal, "LiftPrompt")
        if not arrived then
            Lift.Status = "Moving to Lift"
            return
        end

        if os.clock() >= Lift.NextPromptAt then
            Lift.NextPromptAt = os.clock() + 1.25
            Lift.PromptAttempts = (Lift.PromptAttempts or 0) + 1
            local activated = activatePrompt(prompt)
            Lift.Status = activated and ("Activating Lift (attempt " .. Lift.PromptAttempts .. ")")
                or "Prompt activation unavailable; retrying"
            if activated then
                task.delay(0.8, function()
                    if Lift.Enabled then
                        F.cancelTravel()
                        F.releaseHold()
                    end
                end)
            end
        else
            Lift.Status = "Waiting for next wave"
        end
    end
end
