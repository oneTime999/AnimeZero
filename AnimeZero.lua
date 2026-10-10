if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VU = game:GetService("VirtualUser")
local Player = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G

for _, name in ipairs({"PcdBehindFarm", "PcdBehindV2", "PcdBehindV3", "PcdBehindV4", "PcdBehindV5", "PcdBehindV6", "PcdBehindV7", "PcdBehindV8", "PcdBehindV9", "PcdBehindV10", "PcdBehindV11", "PcdBehindV12", "PcdBehindAutoFarm", "PcdBehindStable", "PcdHxHHub"}) do
    local old = Env[name]
    if type(old) == "table" and type(old.Stop) == "function" then
        pcall(old.Stop)
    end
end

local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local C = {
    Position = "Behind",
    Distance = 3,
    Height = 0,
    M1Interval = 0.2,
    ConfirmClear = 1.0,
    UnknownHPTimeout = 15,
    SpawnDelay = 0.35,
    MaxSpawnWait = 2,
    FirstWaveSpawnWait = 5,
    StaleTargetWait = 10,
    WaveRadius = 110,
    FirstBorder = 1,
    M1 = true,
    Skills = true,
    SkillsOnBorder = false,
    AFK = true,
    SkillInput = "Automatic",
    DifficultyMode = "Automatic",
    SkillKeyHold = 0.06,
    Noclip = true,
    TravelMethod = "Tween",
    TravelSpeed = 170,
    TravelArc = 10,
    ArrivalConfirm = 0.55,
    LockOnRubble = true,
    LockOnWave = true,
    RubblePosition = "Inside",
    RubbleAboveGap = 3,
    FinalSettleTime = 5,
    RubbleClearConfirm = 0.6,
    RubbleTimeout = 25,
    AdvanceOnRubbleTimeout = false,
    AutoReplay = true
}

local S = {
    Alive = true,
    Enabled = false,
    Phase = "GO_WAVE",
    WaveNumber = 1,
    SubWave = 1,
    ExpectedSubWaves = 1,
    Difficulty = "Easy",
    SecondWaveSnapshot = {},
    SecondWaveWaitAt = 0,
    LastDifficultyScan = 0,
    CachedDifficulty = nil,
    CachedHUDWave = nil,
    HUDDisplayedArea = nil,
    HUDDisplayedWave = nil,
    HUDDisplayedTotal = nil,
    HUDLastSeen = 0,
    WaveCoordinate = nil,
    BorderNumber = C.FirstBorder,
    RubbleRef = nil,
    Target = nil,
    TargetSince = 0,
    EmptyAt = nil,
    SpawnAt = 0,
    EnteredWaitAt = 0,
    LastM1 = 0,
    WaveModels = {},
    TargetProgress = setmetatable({}, {__mode = "k"}),
    IgnoredStale = 0,
    SpawnTimeExceeded = false,
    SpawnRetries = 0,
    OldModels = setmetatable({}, {__mode = "k"}),
    OldDead = setmetatable({}, {__mode = "k"}),
    Ignored = {},
    Status = "Disabled",
    SkillStatus = "Not used yet",
    UI = nil,
    RootLocked = nil,
    PreviousAnchored = nil,
    WaveVisitedAt = 0,
    Collisions = setmetatable({}, {__mode = "k"}),
    HoldCF = nil,
    MissingRubbleAt = nil,
    FinalMode = false,
    FinishAt = 0,
    FinalRestored = false,
    BossWaitAt = 0,
    BossTarget = nil,
    BossEncountered = false,
    BossSnapshot = setmetatable({}, {__mode = "k"}),
    BossClearSince = nil,
    RubbleEnteredAt = 0,
    RubbleClearSince = nil,
    RubbleBaseline = nil,
    RubbleObserved = false,
    RubbleEnemySnapshot = {},
    RubbleReason = "",
    Travel = nil,
    ArrivedTag = nil,
    TravelError = nil,
    HUDSyncCandidate = nil,
    HUDSyncSince = 0,
    HUDSyncGraceUntil = 0,
    HUDPreviousArea = nil
}

local Raid = {
    Enabled = false,
    AutoReplay = true,
    Status = "Disabled",
    Target = nil,
    BossImmune = true,
    BossPresent = false,
    BossEngaged = false,
    BossGoneAt = nil,
    ReplayUntil = 0,
    RoundFinished = false
}

local RubbleCoordinates = {
    [1] = Vector3.new(-21.018918991088867, 3, 148.80140686035156),
    [2] = Vector3.new(-14.256156921386719, 2.999999761581421, -95.90302276611328),
    [3] = Vector3.new(287.8456115722656, 9.391059, -200.16021728515625),
    [4] = Vector3.new(586.5828857421875, 7.643509, -196.41197204589844)
}

local LastBorder = 4
local LastEnemyWave = 5
local WaveCoordinates = {
    [1] = {Vector3.new(-13.791829109191895, 3, 208.84181213378906)},
    [2] = {Vector3.new(-14.480622291564941, 2.999999523162842, 66.72674560546875)},
    [3] = {Vector3.new(-4.803671360015869, 3, -139.56661987304688)},
    [4] = {Vector3.new(372.3541259765625, 3, -199.7725830078125)},
    [5] = {Vector3.new(274.6661071777344, 2.999999761581421, -44.3554573059082)}
}

local Skill = {
    {Name = "Skill 1", Key = Enum.KeyCode.One, VK = 0x31, Delay = 0.1, Enabled = true, Last = -math.huge},
    {Name = "Skill 2", Key = Enum.KeyCode.Two, VK = 0x32, Delay = 0.1, Enabled = true, Last = -math.huge},
    {Name = "Skill 3", Key = Enum.KeyCode.Three, VK = 0x33, Delay = 0.1, Enabled = true, Last = -math.huge},
    {Name = "Ultimate", Key = Enum.KeyCode.G, VK = 0x47, Delay = 0.1, Enabled = true, Last = -math.huge}
}

local function character()
    local char = Player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if root and hum and hum.Health > 0 then return char, root end
end

local function partOf(model)
    if not model or not model:IsA("Model") then return end
    return model:FindFirstChild("HumanoidRootPart", true)
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function hpOf(model)
    local hum = model:FindFirstChildWhichIsA("Humanoid", true)
    if hum then return hum.Health end
    for _, name in ipairs({"Health", "HP", "CurrentHealth", "CurrentHP"}) do
        local attr = model:GetAttribute(name)
        if type(attr) == "number" then return attr end
        local val = model:FindFirstChild(name, true)
        if val and (val:IsA("IntValue") or val:IsA("NumberValue")) then
            return val.Value
        end
    end
    return nil
end

local function living(model)
    if not model or not model:IsA("Model") or not model:IsDescendantOf(WS) then return false end
    if not partOf(model) then return false end
    if model:GetAttribute("Dead") == true or model:GetAttribute("IsDead") == true
       or model:GetAttribute("Alive") == false then return false end
    local hp = hpOf(model)
    return hp == nil or hp > 0
end

local function enemyFolder()
    return WS:FindFirstChild("enemies")
end

local function readDifficulty()
    local now = os.clock()
    if now - S.LastDifficultyScan < 0.4 then
        return S.Difficulty
    end
    S.LastDifficultyScan = now

    local gui = Player:FindFirstChildOfClass("PlayerGui")
    local uiArea, uiWave, uiTotal, detected
    if gui then
        for _, object in ipairs(gui:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Visible then
                local value = object.Text:lower()
                local area = tonumber(value:match("area%s*(%d+)"))
                local wave, total = value:match("wave%s*(%d+)%s*/%s*(%d+)")
                if area and wave and total then
                    if not uiArea or area == S.BorderNumber then
                        uiArea, uiWave, uiTotal = area, tonumber(wave), tonumber(total)
                        detected = value:find("nightmare", 1, true) and "Nightmare"
                            or (value:find("easy", 1, true) and "Easy" or nil)
                    end
                    if area == S.BorderNumber then break end
                end
            end
        end
    end

    if uiArea then
        S.HUDDisplayedArea = uiArea
        S.HUDDisplayedWave = uiWave
        S.HUDDisplayedTotal = uiTotal
        S.HUDLastSeen = now
        S.CachedHUDWave = uiArea == S.BorderNumber and uiWave or nil
    elseif now - S.HUDLastSeen >= 2 then
        S.HUDDisplayedArea = nil
        S.HUDDisplayedWave = nil
        S.HUDDisplayedTotal = nil
        S.CachedHUDWave = nil
    end

    if C.DifficultyMode ~= "Automatic" then
        S.Difficulty = C.DifficultyMode
        S.ExpectedSubWaves = C.DifficultyMode == "Nightmare" and 2 or 1
    elseif uiTotal then
        S.Difficulty = detected or (uiTotal >= 2 and "Nightmare" or "Easy")
        S.ExpectedSubWaves = uiTotal
    end
    return S.Difficulty
end

local function currentHUDWave()
    if S.HUDDisplayedArea == S.BorderNumber
        and os.clock() - S.HUDLastSeen < 2 then
        return S.HUDDisplayedWave
    end
    return nil
end

local function isInCurrentWave(model)
    return partOf(model) ~= nil
end

local function isStale(model, now)
    local hp = hpOf(model)
    local info = S.TargetProgress[model]
    if not info then
        info = {Health = hp, LastProgress = now}
        S.TargetProgress[model] = info
        return false
    end

    if hp ~= nil and info.Health ~= nil and hp < info.Health - 0.001 then
        info.LastProgress = now
    end
    info.Health = hp

    if now - info.LastProgress >= C.StaleTargetWait then
        S.Ignored[model] = true
        S.IgnoredStale += 1
        S.Status = "Skipping unresponsive enemy: " .. model.Name
        return true
    end
    return false
end

local function findEnemy()
    local folder = enemyFolder()
    local _, root = character()
    if not folder or not root then return nil end

    local previousTarget = S.Target
    local nearest, nearestDistance = nil, math.huge
    local retained = nil
    local now = os.clock()

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and isInCurrentWave(model) then
            S.WaveModels[model] = true

            if living(model) and not S.Ignored[model] then
                if model == previousTarget then retained = model end
                local part = partOf(model)
                local distance = (root.Position - part.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearest = model
                end
            end
        end
    end

    local target = retained or nearest
    if target ~= S.Target then
        S.Target = target
        S.TargetSince = now
    end

    if target and isStale(target, now) then
        S.Target = nil
        return nil
    end

    return target
end

local function livingEnemyExists()
    local folder = enemyFolder()
    if not folder then return false end
    for _, model in ipairs(folder:GetChildren()) do
        if living(model) then
            return true
        end
    end
    return false
end

local lastEnemyRecheck = -math.huge
local function findActiveEnemy()
    local target = findEnemy()
    if target then return target end
    if not livingEnemyExists() then return nil end

    local now = os.clock()
    if now - lastEnemyRecheck >= 0.6 then
        S.Ignored = {}
        S.TargetProgress = setmetatable({}, {__mode = "k"})
        S.Target = nil
        lastEnemyRecheck = now
    end
    return findEnemy()
end

local function cancelTravel()
    S.Travel = nil
    S.ArrivedTag = nil
end

local function releaseHold()
    S.HoldCF = nil
end

local function setPosition(cf, tolerance, hold)
    local char, root = character()
    if not char then return false end

    local ok = pcall(function()
        if root.Anchored then root.Anchored = false end
        if (root.Position - cf.Position).Magnitude > (tolerance or 0.6) then
            char:PivotTo(cf)
        else
            root.CFrame = cf
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    if ok and hold then S.HoldCF = cf end
    return ok
end

local function travelTo(cf, tag)
    if S.ArrivedTag == tag then
        local _, root = character()
        if root and (root.Position - cf.Position).Magnitude <= 4 then
            return true
        end
        S.ArrivedTag = nil
    end

    local char, root = character()
    if not char or not root then return false end
    if S.Travel and S.Travel.Tag == tag then return false end

    S.Travel = nil
    releaseHold()
    local distance = (root.Position - cf.Position).Magnitude
    local duration = C.TravelMethod == "Tween"
        and math.clamp(distance / math.max(C.TravelSpeed, 10), 0.15, 8)
        or 0

    S.Travel = {
        Tag = tag,
        Start = root.CFrame,
        Goal = cf,
        Started = os.clock(),
        Duration = duration,
        ArrivalAt = nil,
        LastDrift = nil
    }
    return false
end

local function updateTravel()
    local trip = S.Travel
    if not S.Enabled or not S.Alive or not trip then return end
    local char, root = character()
    if not char or not root then return end
    local now = os.clock()
    local alpha = trip.Duration > 0
        and math.clamp((now - trip.Started) / trip.Duration, 0, 1)
        or 1
    local eased = alpha * alpha * (3 - 2 * alpha)
    local pos = trip.Start.Position:Lerp(trip.Goal.Position, eased)

    if trip.Duration > 0 then
        pos += Vector3.new(0, math.sin(math.pi * alpha) * C.TravelArc, 0)
    end
    local frame = CFrame.new(pos) * trip.Goal.Rotation

    pcall(function()
        if root.Anchored then root.Anchored = false end
        char:PivotTo(frame)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    if alpha < 1 then
        S.Status = string.format("Tween %s: %d%%", trip.Tag, math.floor(alpha * 100))
        return
    end

    if (root.Position - trip.Goal.Position).Magnitude > 4 then
        trip.ArrivalAt = nil
        return
    end
    trip.ArrivalAt = trip.ArrivalAt or now
    if now - trip.ArrivalAt >= C.ArrivalConfirm then
        local tag, target = trip.Tag, trip.Goal
        S.Travel = nil
        S.ArrivedTag = tag
        S.HoldCF = target
    end
end

local function enemyPosition(enemy)
    local part = partOf(enemy)
    if not part then return false end

    local d = C.Distance
    local cf = part.CFrame
    local offset
    if C.Position == "Inside" then
        offset = Vector3.zero
    elseif C.Position == "Above" then
        offset = Vector3.new(0, d + part.Size.Y * 0.5, 0)
    elseif C.Position == "Below" then
        offset = Vector3.new(0, -d - part.Size.Y * 0.5, 0)
    elseif C.Position == "Front" then
        offset = cf.LookVector * d
    elseif C.Position == "Left" then
        offset = -cf.RightVector * d
    elseif C.Position == "Right" then
        offset = cf.RightVector * d
    else
        offset = -cf.LookVector * d
    end

    local pos = part.Position + offset + Vector3.new(0, C.Height, 0)
    local look = Vector3.new(part.Position.X, pos.Y, part.Position.Z)
    if (pos - look).Magnitude < 0.01 then
        look = pos + cf.LookVector
    end
    return setPosition(CFrame.lookAt(pos, look), 0.55, true)
end

local function rubbleBounds(rubble)
    if not rubble then return end
    if rubble:IsA("Model") then
        local found = rubble:FindFirstChildWhichIsA("BasePart", true)
        if not found then return end
        return rubble:GetBoundingBox()
    elseif rubble:IsA("BasePart") then
        return rubble.CFrame, rubble.Size
    elseif rubble:IsA("Folder") then
        local low, high
        for _, part in ipairs(rubble:GetDescendants()) do
            if part:IsA("BasePart") then
                local center, half = part.Position, part.Size * 0.5
                local a, b = center - half, center + half
                low = low and Vector3.new(math.min(low.X, a.X), math.min(low.Y, a.Y), math.min(low.Z, a.Z)) or a
                high = high and Vector3.new(math.max(high.X, b.X), math.max(high.Y, b.Y), math.max(high.Z, b.Z)) or b
            end
        end
        if low then return CFrame.new((low + high) * 0.5), high - low end
    end
end

local function rubblePart(rubble)
    if not rubble or not rubble:IsDescendantOf(WS) then return nil end
    if rubble:IsA("BasePart") then return rubble end
    if rubble:IsA("Model") and rubble.PrimaryPart then
        return rubble.PrimaryPart
    end

    for _, preferred in ipairs({"Hitbox", "Main", "Rock", "Rubble", "Root"}) do
        local candidate = rubble:FindFirstChild(preferred, true)
        if candidate and candidate:IsA("BasePart") then return candidate end
    end

    local largest, size = nil, -1
    for _, descendant in ipairs(rubble:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local d = descendant.Size
            local volume = d.X * d.Y * d.Z
            if volume > size then
                largest, size = descendant, volume
            end
        end
    end
    return largest
end

local function rubbleCFrame(rubble)
    local dest = RubbleCoordinates[S.BorderNumber]
    local main = rubblePart(rubble)
    if not dest and main then dest = main.Position end
    if not dest then return nil end
    if C.RubblePosition == "Above" or not C.Noclip then
        local cf, size = rubbleBounds(rubble)
        local safeY = dest.Y + C.RubbleAboveGap
        if cf then
            local halfY = math.abs(cf.RightVector.Y) * size.X / 2
                + math.abs(cf.UpVector.Y) * size.Y / 2
                + math.abs(cf.LookVector.Y) * size.Z / 2
            safeY = math.max(safeY, cf.Position.Y + halfY + C.RubbleAboveGap)
        end
        dest = Vector3.new(dest.X, safeY, dest.Z)
    end
    local face = main and main.Position or dest + Vector3.new(0, 0, -1)
    local look = Vector3.new(face.X, dest.Y, face.Z)
    if (look - dest).Magnitude < 0.05 then
        look = dest + Vector3.new(0, 0, -1)
    end
    return CFrame.lookAt(dest, look)
end

local function rubblePosition(rubble)
    local cf = rubbleCFrame(rubble)
    return cf and setPosition(cf, 0.35, C.LockOnRubble) or false
end

local function applyNoclip()
    if not (S.Enabled or Raid.Enabled) or not C.Noclip then return end
    local char = Player.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if S.Collisions[part] == nil then
                S.Collisions[part] = part.CanCollide
            end
            if part.CanCollide then part.CanCollide = false end
        end
    end
end

local function restoreCollisions()
    for part, original in pairs(S.Collisions) do
        if part and part.Parent then
            pcall(function() part.CanCollide = original end)
        end
    end
    S.Collisions = setmetatable({}, {__mode = "k"})
end

local function attackM1()
    if not C.M1 or not (S.Enabled or Raid.Enabled) then return end
    local now = os.clock()
    if now - S.LastM1 < C.M1Interval then return end
    local remote = RS:FindFirstChild("performM1")
    if not remote or not remote:IsA("RemoteEvent") then
        S.Status = "M1 unavailable"
        return
    end
    S.LastM1 = now
    remote:FireServer(nil)
end

local function pressKey(skill)
    if type(keypress) ~= "function" or type(keyrelease) ~= "function" then
        return false
    end
    local pressed = pcall(keypress, skill.VK)
    if not pressed then return false end
    task.wait(C.SkillKeyHold)
    pcall(keyrelease, skill.VK)
    return true
end

local function pressVirtualKey(skill)
    if not VIM then return false end
    local pressed = pcall(function()
        VIM:SendKeyEvent(true, skill.Key, false, game)
    end)
    if not pressed then return false end
    task.wait(C.SkillKeyHold)
    pcall(function()
        VIM:SendKeyEvent(false, skill.Key, false, game)
    end)
    return true
end

local function invokeSkill(skill)
    local used, method = false, ""
    if C.SkillInput == "keypress" then
        used, method = pressKey(skill), "keypress"
    elseif C.SkillInput == "VirtualInputManager" then
        used, method = pressVirtualKey(skill), "VirtualInputManager"
    else
        local viaVirtual = pressVirtualKey(skill)
        local viaKey = pressKey(skill)
        used = viaVirtual or viaKey
        method = viaVirtual and viaKey and "VirtualInputManager + keypress"
            or (viaVirtual and "VirtualInputManager" or "keypress")
    end

    S.SkillStatus = skill.Name .. ": " .. (used
        and ("Input sent through " .. method)
        or "Keyboard input unavailable")
    return used
end

local function autoSkills()
    if not C.Skills or not (S.Enabled or Raid.Enabled) then return end
    local now = os.clock()
    for _, skill in ipairs(Skill) do
        if skill.Enabled and not skill.Busy and now - skill.Last >= skill.Delay then
            skill.Busy = true
            skill.Last = now
            task.spawn(function()
                local ok, err = pcall(invokeSkill, skill)
                if not ok then
                    S.SkillStatus = skill.Name .. ": " .. tostring(err)
                end
                skill.Busy = false
            end)
        end
    end
end

local function getBorder(number)
    local world = WS:FindFirstChild("World")
    local map = world and world:FindFirstChild("Map")
    local border = map and map:FindFirstChild("Border" .. tostring(number))
    if border and border:IsA("Model") then return border end
    return nil
end

local function getRubble(number)
    local border = getBorder(number)
    return border and border:FindFirstChild("Rubble") or nil
end

local function captureRubble(rubble)
    local baseline = {Parts = {}, Visible = 0, Count = 0}
    if not rubble then return baseline end

    local function collect(part)
        baseline.Count += 1
        local visible = part.Transparency < 0.95
            and part.LocalTransparencyModifier < 0.95
        if visible then baseline.Visible += 1 end
        baseline.Parts[part] = {Position = part.Position, WasVisible = visible}
    end

    if rubble:IsA("BasePart") then
        collect(rubble)
    else
        for _, descendant in ipairs(rubble:GetDescendants()) do
            if descendant:IsA("BasePart") then collect(descendant) end
        end
    end
    return baseline
end

local function destroyedFlag(instance)
    if not instance then return false end
    for _, name in ipairs({"Destroyed", "IsDestroyed", "Broken", "IsBroken", "Cleared", "Dead"}) do
        if instance:GetAttribute(name) == true then return true end
        local v = instance:FindFirstChild(name)
        if v and v:IsA("BoolValue") and v.Value then return true end
    end
    for _, name in ipairs({"Health", "HP", "Durability", "Integrity", "CurrentHealth"}) do
        local value = instance:GetAttribute(name)
        if type(value) == "number" and value <= 0 then return true end
        local item = instance:FindFirstChild(name)
        if item and (item:IsA("IntValue") or item:IsA("NumberValue"))
            and item.Value <= 0 then return true end
    end
    return false
end

local function rubbleGone(rubble, baseline)
    if not rubble or not rubble:IsDescendantOf(WS) then
        return true, "Rubble removed"
    end

    if destroyedFlag(rubble) or destroyedFlag(rubble.Parent) then
        return true, "Destroyed state or zero health"
    end
    local hp = hpOf(rubble)
    if hp ~= nil and hp <= 0 then
        return true, "Rubble health depleted"
    end

    local parts = 0
    local visible = 0
    local solid = 0
    local function inspect(part)
        parts += 1
        if part.Transparency < 0.95 and part.LocalTransparencyModifier < 0.95 then
            visible += 1
        end
        if part.CanCollide and part.Transparency < 0.95 then
            solid += 1
        end
    end

    if rubble:IsA("BasePart") then
        inspect(rubble)
    else
        for _, object in ipairs(rubble:GetDescendants()) do
            if object:IsA("BasePart") then inspect(object) end
        end
    end
    if parts == 0 then return true, "Rubble has no parts" end

    if baseline and baseline.Visible > 0 and visible == 0 then
        return true, "Rubble became invisible"
    end

    if baseline and baseline.Count > 0 then
        local originals = 0
        local originalsVisible = 0
        local moved = 0
        for part, info in pairs(baseline.Parts) do
            if part:IsDescendantOf(rubble) then
                originals += 1
                if info.WasVisible and part.Transparency < 0.95
                    and part.LocalTransparencyModifier < 0.95 then
                    originalsVisible += 1
                end
                if (part.Position - info.Position).Magnitude >= 14 then
                    moved += 1
                end
            end
        end
        if originals == 0 then
            return true, "Original parts were removed"
        end
        if baseline.Count >= 2 and originals <= baseline.Count * 0.25 then
            return true, "Original parts removed"
        end
        if baseline.Visible > 0 and originalsVisible == 0 then
            return true, "Original parts became invisible"
        end
        if baseline.Count >= 2 and moved >= baseline.Count * 0.8 then
            return true, "Rubble moved after destruction"
        end
    end

    return false, ""
end

local function nextWaveSpawned()
    local folder = enemyFolder()
    local points = WaveCoordinates[S.BorderNumber + 1]
    local pos = points and points[1]
    if not folder or not pos then return false end
    if os.clock() - S.RubbleEnteredAt < 1 then return false end

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and living(model) then
            local root = partOf(model)
            if root and (root.Position - pos).Magnitude <= C.WaveRadius then
                local before = S.RubbleEnemySnapshot[model]
                local hp = hpOf(model)
                if before == nil or (before ~= false and before <= 0
                    and (hp == nil or hp > 0)) then
                    return true
                end
            end
        end
    end
    return false
end

local function setPhase(phase, message)
    if S.Phase ~= phase then
        cancelTravel()
        releaseHold()
    end
    S.Phase = phase
    S.Status = message
    S.EmptyAt = nil
    S.Target = nil
end

local function secondWaveAvailable()
    local folder = enemyFolder()
    if not folder then return false end
    readDifficulty()
    local visibleWave = currentHUDWave()
    if visibleWave and visibleWave < 2 then return false end
    local confirmedByHUD = visibleWave and visibleWave >= 2
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and living(model) and isInCurrentWave(model) then
            local old = S.SecondWaveSnapshot[model]
            if not old then
                return true
            end
            local hp = hpOf(model)
            if (old.Health ~= nil and hp ~= nil and hp > old.Health + 0.01)
                or (not old.Alive and (hp == nil or hp > 0))
                or confirmedByHUD then
                return true
            end
        end
    end
    return false
end

local function waitForSecondWave()
    local folder = enemyFolder()
    S.SecondWaveSnapshot = {}
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and isInCurrentWave(model) then
                S.SecondWaveSnapshot[model] = {
                    Health = hpOf(model),
                    Alive = living(model)
                }
            end
        end
    end
    S.SecondWaveWaitAt = os.clock()
    S.SubWave = math.min(2, S.ExpectedSubWaves)
    setPhase("GO_SECOND_WAVE", "Returning to spawn for wave 2")
end

local function beginRubble()
    releaseHold()
    S.RubbleRef = nil
    S.RubbleBaseline = nil
    S.RubbleObserved = false
    S.RubbleClearSince = nil
    S.MissingRubbleAt = nil
    S.RubbleEnteredAt = os.clock()
    S.RubbleReason = ""
    S.RubbleEnemySnapshot = {}
    local folder = enemyFolder()
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                S.RubbleEnemySnapshot[model] = hpOf(model) or false
            end
        end
    end
    setPhase("BREAK_RUBBLE", "Moving to Rubble " .. S.BorderNumber)
end

local function beginWave(finalWave)
    releaseHold()
    S.FinalMode = finalWave == true
    S.BossEncountered = false
    S.WaveModels = {}
    S.Ignored = {}
    S.TargetProgress = setmetatable({}, {__mode = "k"})
    S.IgnoredStale = 0
    setPhase("KILL_ENEMIES", finalWave
        and "Clearing final wave" or "Clearing enemies")
end

local function toWave(number, wave)
    releaseHold()
    S.BorderNumber = number
    S.WaveNumber = wave or 1
    local points = WaveCoordinates[number]
    S.WaveCoordinate = points and points[S.WaveNumber] or nil
    S.RubbleRef = nil
    S.MissingRubbleAt = nil
    S.RubbleBaseline = nil
    S.RubbleObserved = false
    S.RubbleClearSince = nil
    S.RubbleEnemySnapshot = {}
    S.FinalMode = (number == LastEnemyWave)
    S.BossTarget = nil
    S.BossEncountered = false
    S.BossClearSince = nil
    S.BossWaitAt = 0
    S.BossSnapshot = setmetatable({}, {__mode = "k"})
    S.SubWave = 1
    S.SecondWaveSnapshot = {}
    S.SecondWaveWaitAt = 0
    S.CachedHUDWave = nil
    S.WaveModels = {}
    S.Ignored = {}
    S.TargetProgress = setmetatable({}, {__mode = "k"})
    S.IgnoredStale = 0
    S.SpawnTimeExceeded = false
    S.SpawnRetries = 0
    S.EnteredWaitAt = 0
    S.WaveVisitedAt = 0
    S.SpawnAt = 0
    S.Status = "Moving to wave " .. tostring(number)
    setPhase("GO_WAVE", string.format("Moving to wave %d", S.BorderNumber))
end

local function snapshotOldMobs()
    for model in pairs(S.WaveModels) do
        if model and model.Parent then
            S.OldModels[model] = true
            local hp = hpOf(model)
            S.OldDead[model] = (hp ~= nil and hp <= 0)
        end
    end
end

local function afterRubble()
    releaseHold()
    snapshotOldMobs()

    if S.BorderNumber <= LastBorder then
        local oldArea = S.BorderNumber
        local now = os.clock()
        if S.HUDDisplayedArea == oldArea and now - S.HUDLastSeen < 1.5 then
            setPhase("WAIT_AREA_CHANGE", "Rubble cleared; waiting for the game to advance")
        else
            S.HUDPreviousArea = oldArea
            S.HUDSyncGraceUntil = now + 1.5
            toWave(oldArea + 1, 1)
        end
    end
end

local function bossCandidates()
    local result = {}
    local seen = {}
    local function add(model)
        if model and model:IsA("Model") and not seen[model] then
            seen[model] = true
            table.insert(result, model)
        end
    end

    local enemies = enemyFolder()
    if enemies then
        for _, child in ipairs(enemies:GetChildren()) do
            add(child)
        end
    end

    for _, name in ipairs({"Boss", "boss", "Bosses", "bosses"}) do
        local folder = WS:FindFirstChild(name)
        if folder then
            add(folder)
            for _, child in ipairs(folder:GetChildren()) do
                add(child)
            end
        end
    end
    return result
end

local function bossNearFinal(model)
    local part = partOf(model)
    if not part then return false end
    local spawn = WaveCoordinates[LastEnemyWave][1]
    return (part.Position - spawn).Magnitude <= math.max(C.WaveRadius, 170)
end

local function bossNamed(model)
    return model.Name:lower():find("boss", 1, true) ~= nil
        or model.Name:lower():find("chefao", 1, true) ~= nil
end

local function beginBossWait()
    S.BossSnapshot = setmetatable({}, {__mode = "k"})
    for _, model in ipairs(bossCandidates()) do
        if bossNearFinal(model) then
            S.BossSnapshot[model] = {
                WasAlive = living(model),
                HP = hpOf(model)
            }
        end
    end
    S.BossTarget = nil
    S.BossClearSince = nil
    S.BossWaitAt = os.clock()
    setPhase("WAIT_BOSS", "Final wave cleared; waiting for boss")
end

local function findSpawnedBoss()
    local nearest, nearestDist = nil, math.huge
    local _, root = character()
    if not root then return nil end
    for _, model in ipairs(bossCandidates()) do
        if living(model) and bossNearFinal(model) then
            local earlier = S.BossSnapshot[model]
            local hp = hpOf(model)
            local revived = earlier and not earlier.WasAlive
                and (hp == nil or hp > 0)
            local newlySpawned = earlier == nil
            local explicitlyBoss = bossNamed(model)
            if newlySpawned or revived or explicitlyBoss then
                local part = partOf(model)
                local dist = (root.Position - part.Position).Magnitude
                if dist < nearestDist then
                    nearest = model
                    nearestDist = dist
                end
            end
        end
    end
    return nearest
end

local function syncHUDProgress()
    readDifficulty()
    local now = os.clock()
    local area = S.HUDDisplayedArea
    if not area or area < 1 or area > LastEnemyWave
        or now - S.HUDLastSeen > 1.5 then
        S.HUDSyncCandidate = nil
        return
    end

    if S.HUDSyncCandidate ~= area then
        S.HUDSyncCandidate = area
        S.HUDSyncSince = now
        return
    end
    if now - S.HUDSyncSince < 0.25 then return end

    if area ~= S.BorderNumber then
        if now < S.HUDSyncGraceUntil and area == S.HUDPreviousArea then
            return
        end
        S.HUDSyncGraceUntil = 0
        S.HUDPreviousArea = nil
        S.OldModels = setmetatable({}, {__mode = "k"})
        S.OldDead = setmetatable({}, {__mode = "k"})
        S.LastM1 = 0
        toWave(area, 1)
        S.Status = "Area " .. area .. " confirmed by game"
        return
    end

    local displayedWave = currentHUDWave()
    if displayedWave and displayedWave > S.SubWave
        and displayedWave <= S.ExpectedSubWaves
        and S.Phase ~= "KILL_BOSS" and S.Phase ~= "WAIT_BOSS"
        and S.Phase ~= "FINAL_TELEPORT" and S.Phase ~= "COMPLETED" then
        S.SubWave = displayedWave
        S.TargetProgress = setmetatable({}, {__mode = "k"})
        S.Ignored = {}
        setPhase("GO_WAVE", string.format(
            "Game advanced to wave %d/%d", displayedWave, S.ExpectedSubWaves
        ))
    end
end

local function step()
    if not S.Enabled then return end
    if not character() then
        releaseHold()
        S.Status = "Waiting for character"
        return
    end

    if S.Phase == "GO_WAVE" then
        readDifficulty()
        if not S.WaveCoordinate then
            S.Status = "Wave destination unavailable"
            return
        end

        local dest = CFrame.new(S.WaveCoordinate)
        local tag = "NPCs " .. tostring(S.BorderNumber)
        if not travelTo(dest, tag) then
            if not S.Travel then S.Status = "Preparing " .. tag end
            return
        end

        S.WaveVisitedAt = os.clock()
        S.SpawnAt = S.WaveVisitedAt + C.SpawnDelay
        S.EnteredWaitAt = S.WaveVisitedAt
        setPhase("WAIT_ENEMIES", string.format(
            "Wave %d: waiting for enemies", S.BorderNumber
        ))
        if C.LockOnWave then S.HoldCF = dest end
        return
    end


    if S.Phase == "WAIT_ENEMIES" then
        S.Status = string.format("Wave %d: waiting for enemies", S.BorderNumber)
        if os.clock() < S.SpawnAt then return end
        if findActiveEnemy() then
            beginWave(S.BorderNumber == LastEnemyWave)
        elseif livingEnemyExists() then
            S.Status = "Active enemies detected; acquiring target"
        elseif os.clock() - S.EnteredWaitAt >= (S.BorderNumber == 1
            and S.SubWave == 1 and C.FirstWaveSpawnWait or C.MaxSpawnWait) then
            readDifficulty()
            local hudWave = currentHUDWave()
            if S.FinalMode and S.SubWave < S.ExpectedSubWaves
                and hudWave and hudWave <= S.SubWave then
                S.Status = "Waiting for the next wave on the HUD"
            elseif S.FinalMode then
                beginBossWait()
            else
                beginRubble()
            end
        else
            local limit = S.BorderNumber == 1 and S.SubWave == 1
                and C.FirstWaveSpawnWait or C.MaxSpawnWait
            local remain = math.max(0, limit - (os.clock() - S.EnteredWaitAt))
            S.Status = string.format("Wave %d: waiting for enemies (%.1fs)",
                S.BorderNumber, remain)
        end
        return
    end

    if S.Phase == "WAIT_AREA_CHANGE" then
        readDifficulty()
        if S.HUDDisplayedArea == S.BorderNumber
            and os.clock() - S.HUDLastSeen < 1.5 then
            S.Status = "Waiting for area " .. (S.BorderNumber + 1) .. " in game"
        elseif os.clock() - S.HUDLastSeen >= 1.5 then
            S.HUDPreviousArea = S.BorderNumber
            S.HUDSyncGraceUntil = os.clock() + 1.5
            toWave(S.BorderNumber + 1, 1)
        end
        return
    end

    if S.Phase == "GO_SECOND_WAVE" then
        if not S.WaveCoordinate then return end
        local dest = CFrame.new(S.WaveCoordinate)
        local tag = "Area " .. tostring(S.BorderNumber) .. " wave 2"
        if not travelTo(dest, tag) then return end
        S.SecondWaveWaitAt = os.clock()
        setPhase("WAIT_SECOND_WAVE", "Waiting for the second enemy wave")
        if C.LockOnWave then S.HoldCF = dest end
        return
    end

    if S.Phase == "WAIT_SECOND_WAVE" then
        readDifficulty()
        if secondWaveAvailable() then
            S.SubWave = 2
            beginWave(S.BorderNumber == LastEnemyWave)
            S.Status = "Area " .. S.BorderNumber .. ": attacking wave 2/2"
        elseif livingEnemyExists() then
            beginWave(S.BorderNumber == LastEnemyWave)
            S.Status = "Active enemies detected; clearing current wave"
        elseif os.clock() - S.SecondWaveWaitAt >= C.MaxSpawnWait then
            if S.FinalMode then
                beginBossWait()
            else
                beginRubble()
            end
        else
            S.Status = string.format("Area %d: waiting for wave 2/2 (%.1fs)",
                S.BorderNumber, os.clock() - S.SecondWaveWaitAt)
        end
        return
    end

    if S.Phase == "KILL_ENEMIES" then
        readDifficulty()
        local target = findActiveEnemy()
        if target then
            if S.FinalMode and (bossNamed(target) or S.EmptyAt ~= nil) then
                S.BossEncountered = true
            end
            S.EmptyAt = nil
            S.Status = string.format("Wave %d: attacking %s",
                S.BorderNumber, target.Name)
            if enemyPosition(target) and living(target) then
                attackM1()
                autoSkills()
            end
        elseif livingEnemyExists() then
            S.EmptyAt = nil
            S.Status = "Active enemies detected; acquiring target"
        else
            releaseHold()
            S.EmptyAt = S.EmptyAt or os.clock()
            local remaining = math.max(0, C.ConfirmClear - (os.clock() - S.EmptyAt))
            S.Status = string.format("Wave cleared in %.1fs | skipped: %d", remaining, S.IgnoredStale)

            if os.clock() - S.EmptyAt >= C.ConfirmClear then
                if S.SubWave < S.ExpectedSubWaves then
                    local hudWave = currentHUDWave()
                    if hudWave and hudWave > S.SubWave then
                        waitForSecondWave()
                    elseif os.clock() - S.EmptyAt >= C.MaxSpawnWait then
                        if S.FinalMode then
                            S.Status = "Waiting for the final wave to advance"
                        else
                            beginRubble()
                        end
                    else
                        S.Status = string.format("Wave %d/%d: waiting for HUD or rubble",
                            S.SubWave, S.ExpectedSubWaves)
                    end
                elseif S.FinalMode then
                    if S.BossEncountered then
                        setPhase("FINAL_TELEPORT", "Boss defeated")
                    else
                        beginBossWait()
                    end
                else
                    beginRubble()
                end
            end
        end
        return
    end

    if S.Phase == "BREAK_RUBBLE" then
        readDifficulty()
        local hudWave = currentHUDWave()
        if S.SubWave < S.ExpectedSubWaves
            and hudWave and hudWave > S.SubWave then
            waitForSecondWave()
            return
        end

        if S.HUDDisplayedArea == S.BorderNumber + 1
            and os.clock() - S.HUDLastSeen < 2 then
            S.RubbleReason = "Next area confirmed by HUD"
            afterRubble()
            return
        end

        if findActiveEnemy() or livingEnemyExists() then
            beginWave(S.BorderNumber == LastEnemyWave)
            S.Status = "Active enemies detected; returning to combat"
            return
        end

        local now = os.clock()
        local elapsed = now - S.RubbleEnteredAt
        local current = getRubble(S.BorderNumber)

        if current and current ~= S.RubbleRef then
            S.RubbleRef = current
            S.RubbleBaseline = captureRubble(current)
            S.RubbleObserved = true
            S.MissingRubbleAt = nil
            S.RubbleClearSince = nil
        end

        local gone, reason = false, ""
        if S.RubbleRef then
            gone, reason = rubbleGone(S.RubbleRef, S.RubbleBaseline)
        elseif not current then
            gone, reason = true, "Rubble not found"
        end

        if nextWaveSpawned() then
            gone, reason = true, "Next wave spawned"
        end

        if gone then
            if hudWave and hudWave < S.ExpectedSubWaves then
                S.Status = string.format("Rubble cleared; waiting for Wave %d/%d",
                    S.ExpectedSubWaves, S.ExpectedSubWaves)
                releaseHold()
                S.RubbleClearSince = nil
                return
            end
            S.RubbleClearSince = S.RubbleClearSince or now
            S.Status = string.format("Rubble %d: confirming (%s)",
                S.BorderNumber, reason)
            releaseHold()
            if now - S.RubbleClearSince >= C.RubbleClearConfirm then
                S.RubbleReason = reason
                afterRubble()
            end
            return
        end
        S.RubbleClearSince = nil

        if C.AdvanceOnRubbleTimeout and elapsed >= C.RubbleTimeout
            and (not hudWave or hudWave >= S.ExpectedSubWaves) then
            S.RubbleReason = "Rubble timeout"
            S.Status = "Rubble timeout reached; proceeding"
            afterRubble()
            return
        end

        if not current then
            S.Status = string.format("Rubble %d not found (%.0fs)",
                S.BorderNumber, elapsed)
            return
        end

        local frame = rubbleCFrame(current)
        if not frame then
            S.Status = "Rubble destination unavailable"
            return
        end
        local tag = "Rubble" .. tostring(S.BorderNumber)
        if not travelTo(frame, tag) then
            if not S.Travel then S.Status = "Moving to " .. tag end
            return
        end
        S.Status = string.format("Breaking Border%d.Rubble (%.1fs)",
            S.BorderNumber, elapsed)
        if rubblePosition(current) then
            attackM1()
            if C.SkillsOnBorder then autoSkills() end
        end
        return
    end

    if S.Phase == "WAIT_BOSS" then
        local boss = findSpawnedBoss()
        if boss then
            S.BossTarget = boss
            S.BossClearSince = nil
            setPhase("KILL_BOSS", "Boss found: " .. boss.Name)
            return
        end
        S.Status = string.format("Waiting for boss (%.1fs)",
            os.clock() - S.BossWaitAt)
        return
    end

    if S.Phase == "KILL_BOSS" then
        local boss = S.BossTarget
        if boss and living(boss) then
            S.BossClearSince = nil
            S.Status = "Attacking boss: " .. boss.Name
            if enemyPosition(boss) and living(boss) then
                attackM1()
                autoSkills()
            end
        else
            S.BossClearSince = S.BossClearSince or os.clock()
            S.Status = "Boss defeated; confirming clear"
            if os.clock() - S.BossClearSince >= C.ConfirmClear then
                setPhase("FINAL_TELEPORT", "Boss defeated")
            end
        end
        return
    end

    if S.Phase == "FINAL_TELEPORT" then
        cancelTravel()
        releaseHold()
        restoreCollisions()
        S.FinishAt = os.clock()
        S.FinalRestored = true
        setPhase("COMPLETED", "Boss cleared; waiting for the next round")
        return
    end

    if S.Phase == "COMPLETED" then
        if os.clock() >= S.FinishAt and not S.FinalRestored then
            releaseHold()
            restoreCollisions()
            S.FinalRestored = true
            S.Status = "Run completed"
        end
        return
    end
end

local function getRaidBossTag()
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

local function raidReplay()
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
        releaseHold()
        Raid.Status = "Replay sent; waiting 5 seconds"
    else
        Raid.Status = "Waiting to retry replay"
    end
end

local function raidStep()
    if not Raid.Enabled or S.Enabled then return end

    if not character() then
        releaseHold()
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

    local folder = enemyFolder()
    if not folder then
        Raid.Target = nil
        releaseHold()
        Raid.Status = "Waiting for raid enemies"
        return
    end

    local tag = getRaidBossTag()
    Raid.BossImmune = not tag or string.find(string.upper(tag), "IMMUNE", 1, true) ~= nil

    local boss = folder:FindFirstChild("0")
    Raid.BossPresent = boss ~= nil and living(boss)

    local _, root = character()
    local closestMob, closestDistance = nil, math.huge
    local mobCount = 0

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model.Name ~= "0" and living(model) then
            mobCount += 1
            local part = partOf(model)
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
        releaseHold()
        if mobCount > 0 or Raid.BossPresent then
            Raid.RoundFinished = false
            Raid.BossEngaged = false
            Raid.BossGoneAt = nil
        elseif Raid.AutoReplay then
            raidReplay()
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
            releaseHold()
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
        releaseHold()
        return
    end

    if living(target) and enemyPosition(target) then
        attackM1()
        autoSkills()
    end
end

local Fluent = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/oneTime999/PcdFnlBossUI/refs/heads/main/main.lua"
))()
S.UI = Fluent

local Window = Fluent:CreateWindow({
    Title = "Pcd Fnl Boss",
    SubTitle = "Story & Raids",
    TabWidth = 150,
    Size = UDim2.fromOffset(570, 480),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Story = Window:AddTab({Title = "Story", Icon = "book-open"})
local Raids = Window:AddTab({Title = "Raids", Icon = "swords"})
local SkillsTab = Window:AddTab({Title = "Skills", Icon = "zap"})
local Settings = Window:AddTab({Title = "Settings", Icon = "settings"})

local storyToggle
local raidToggle

storyToggle = Story:AddToggle("V11_Enable", {
    Title = "Auto HxH Story",
    Description = "Waves 1-5, rubble and final boss",
    Default = false,
    Callback = function(value)
        S.Enabled = value
        if value and Raid.Enabled then
            Raid.Enabled = false
            Raid.Target = nil
            Raid.Status = "Disabled"
            if raidToggle then raidToggle:SetValue(false) end
        end
        if value then
            S.OldModels = setmetatable({}, {__mode = "k"})
            S.OldDead = setmetatable({}, {__mode = "k"})
            S.WaveModels = {}
            S.Ignored = {}
            S.TargetProgress = setmetatable({}, {__mode = "k"})
            S.IgnoredStale = 0
            S.LastM1 = 0
            S.FinalRestored = false
            S.CachedDifficulty = nil
            S.LastDifficultyScan = 0
            for _, skill in ipairs(Skill) do
                skill.Last = -math.huge
            end
            toWave(C.FirstBorder, 1)
        else
            cancelTravel()
            releaseHold()
            if S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
                local prior = C.Noclip
                C.Noclip = false
                rubblePosition(S.RubbleRef)
                C.Noclip = prior
            end
            restoreCollisions()
            setPhase("GO_WAVE", "Disabled")
        end
    end
})

local Stat = Story:AddParagraph({Title = "Progress", Content = "Disabled"})

Story:AddButton({
    Title = "Skip Current Stage",
    Description = "Enemies to rubble, rubble to next area",
    Callback = function()
        if not S.Enabled then
            S.Status = "Enable Auto Farm first"
            return
        end

        local phase = S.Phase
        if phase == "GO_WAVE" or phase == "WAIT_ENEMIES"
            or phase == "KILL_ENEMIES" or phase == "GO_SECOND_WAVE"
            or phase == "WAIT_SECOND_WAVE" then
            if S.FinalMode then
                beginBossWait()
            else
                beginRubble()
            end
        elseif phase == "BREAK_RUBBLE" then
            afterRubble()
        elseif phase == "WAIT_BOSS" or phase == "KILL_BOSS" then
            setPhase("FINAL_TELEPORT", "Boss stage skipped")
        elseif phase == "COMPLETED" then
            toWave(C.FirstBorder, 1)
        end
    end
})

Story:AddDropdown("Stable_Difficulty", {
    Title = "Difficulty",
    Values = {"Automatic", "Easy", "Nightmare"},
    Default = "Automatic",
    Callback = function(value)
        C.DifficultyMode = value
        readDifficulty()
    end
})

Story:AddToggle("Stable_AutoReplay", {
    Title = "Auto Replay", Default = true,
    Callback = function(value) C.AutoReplay = value end
})

Story:AddButton({Title = "Restart Progress", Callback = function()
    S.OldModels = setmetatable({}, {__mode = "k"})
    S.OldDead = setmetatable({}, {__mode = "k"})
    S.FinalRestored = false
    toWave(C.FirstBorder, 1)
end})



raidToggle = Raids:AddToggle("HxH_ShadowMonarchRaid", {
    Title = "Auto Shadow Monarch Raid",
    Description = "Fight raid enemies; attack boss 0 only when not immune",
    Default = false,
    Callback = function(value)
        if value and S.Enabled then
            if storyToggle then storyToggle:SetValue(false) end
        end
        Raid.Enabled = value
        Raid.Target = nil
        Raid.BossImmune = true
        Raid.BossPresent = false
        Raid.BossEngaged = false
        Raid.BossGoneAt = nil
        Raid.ReplayUntil = 0
        Raid.RoundFinished = false
        Raid.Status = value and "Waiting for raid enemies" or "Disabled"
        if value then
            cancelTravel()
            releaseHold()
            S.LastM1 = 0
            for _, skill in ipairs(Skill) do
                skill.Last = -math.huge
            end
        elseif not S.Enabled then
            releaseHold()
            restoreCollisions()
        end
    end
})

Raids:AddToggle("HxH_RaidAutoReplay", {
    Title = "Auto Replay",
    Description = "Replay after defeating the boss; wait 5 seconds",
    Default = true,
    Callback = function(value)
        Raid.AutoReplay = value
    end
})

local RaidStat = Raids:AddParagraph({
    Title = "Shadow Monarch Raid",
    Content = "Disabled"
})

SkillsTab:AddToggle("V11_AutoSkills", {
    Title = "Auto Skills", Default = true,
    Callback = function(value) C.Skills = value end
})
SkillsTab:AddToggle("V11_SkillsOnRubble", {
    Title = "Skills on Rubble", Default = false,
    Callback = function(value) C.SkillsOnBorder = value end
})
SkillsTab:AddDropdown("V11_InputMethod", {
    Title = "Skill Input Method",
    Values = {"Automatic", "keypress", "VirtualInputManager"},
    Default = "Automatic",
    Callback = function(value) C.SkillInput = value end
})

SkillsTab:AddSlider("Stable_SkillHold", {
    Title = "Key Press Duration",
    Min = 0.02, Max = 0.4, Default = 0.06, Rounding = 2,
    Callback = function(value) C.SkillKeyHold = value end
})

for _, index in ipairs({4, 1, 2, 3}) do
    local skill = Skill[index]
    local section = SkillsTab:AddSection(skill.Name .. " (" .. skill.Key.Name .. ")")
    section:AddToggle("V11_SkillEnabled" .. index, {
        Title = "Auto " .. skill.Name, Default = true,
        Callback = function(value) skill.Enabled = value end
    })
    section:AddSlider("V11_SkillDelay" .. index, {
        Title = "Interval (seconds)", Min = 0.1, Max = 10,
        Default = skill.Delay, Rounding = 2,
        Callback = function(value) skill.Delay = value end
    })
end

Settings:AddDropdown("V11_Position", {
    Title = "Enemy Position",
    Values = {"Behind", "Above", "Inside", "Below", "Front", "Left", "Right"},
    Default = "Behind",
    Callback = function(value) C.Position = value end
})
Settings:AddDropdown("V11_RubblePosition", {
    Title = "Rubble Position",
    Values = {"Inside", "Above"},
    Default = "Inside",
    Callback = function(value) C.RubblePosition = value end
})
Settings:AddSlider("V11_Distance", {
    Title = "Enemy Distance", Min = 1, Max = 12,
    Default = 3, Rounding = 1,
    Callback = function(value) C.Distance = value end
})
Settings:AddDropdown("V11_TravelMethod", {
    Title = "Travel Method",
    Description = "Choose Tween or Teleport",
    Values = {"Tween", "Teleport"},
    Default = "Tween",
    Callback = function(value) C.TravelMethod = value end
})
Settings:AddSlider("V11_TravelSpeed", {
    Title = "Tween Speed (studs/s)", Min = 60, Max = 300,
    Default = 170, Rounding = 0,
    Callback = function(value) C.TravelSpeed = value end
})
Settings:AddToggle("V11_M1", {
    Title = "Auto M1", Default = true,
    Callback = function(value) C.M1 = value end
})
Settings:AddToggle("V11_Noclip", {
    Title = "Noclip", Default = true,
    Callback = function(value)
        C.Noclip = value
        if not value then
            if S.Enabled and S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
                local cf = rubbleCFrame(S.RubbleRef)
                if cf then setPosition(cf, 0.35, true) end
            end
            restoreCollisions()
        end
    end
})

Settings:AddSlider("V11_M1Delay", {
    Title = "M1 Interval", Min = 0.1, Max = 1.5,
    Default = 0.2, Rounding = 2,
    Callback = function(value) C.M1Interval = value end
})
Settings:AddSlider("V11_Radius", {
    Title = "Wave Radius (studs)", Min = 30, Max = 200,
    Default = 110, Rounding = 0,
    Callback = function(value) C.WaveRadius = value end
})
Settings:AddSlider("V11_SpawnConfirm", {
    Title = "Wave Clear Delay", Min = 1, Max = 5,
    Default = 1, Rounding = 1,
    Callback = function(value) C.ConfirmClear = value end
})
Settings:AddSlider("Stable_SpawnSkip_MaxWait", {
    Title = "Max Spawn Wait", Min = 1, Max = 15,
    Default = 2, Rounding = 0,
    Callback = function(value) C.MaxSpawnWait = value end
})
Settings:AddSlider("V11_StaleTarget", {
    Title = "Unresponsive Enemy Timeout", Min = 5, Max = 40,
    Default = 10, Rounding = 0,
    Callback = function(value) C.StaleTargetWait = value end
})
Settings:AddSlider("V11_TweenArc", {
    Title = "Tween Arc Height", Min = 0, Max = 25,
    Default = 10, Rounding = 0,
    Callback = function(value) C.TravelArc = value end
})
Settings:AddSlider("V11_RubbleAbove", {
    Title = "Height Above Rubble", Min = 1, Max = 10,
    Default = 3, Rounding = 0,
    Callback = function(value) C.RubbleAboveGap = value end
})
Settings:AddToggle("V11_WaveLock", {
    Title = "Hold Position During Spawn", Default = true,
    Callback = function(value)
        C.LockOnWave = value
        if not value and S.Phase == "WAIT_ENEMIES" then releaseHold() end
    end
})
Settings:AddToggle("V11_RubbleLock", {
    Title = "Hold Position on Rubble", Default = true,
    Callback = function(value)
        C.LockOnRubble = value
        if not value and S.Phase == "BREAK_RUBBLE" then releaseHold() end
    end
})
Settings:AddToggle("V11_RubbleTimeoutEnabled", {
    Title = "Advance on Rubble Timeout",
    Description = "Optional fallback; disabled to prevent skipped areas",
    Default = false,
    Callback = function(value) C.AdvanceOnRubbleTimeout = value end
})
Settings:AddSlider("V11_RubbleTimeout", {
    Title = "Rubble Timeout", Min = 10, Max = 90,
    Default = 25, Rounding = 0,
    Callback = function(value) C.RubbleTimeout = value end
})
Settings:AddToggle("V11_AntiAFK", {
    Title = "Anti AFK", Default = true,
    Callback = function(value) C.AFK = value end
})

local SaveManager = Fluent.SaveManager
local InterfaceManager = Fluent.InterfaceManager
if SaveManager and SaveManager.FileSystemAvailable then
    SaveManager:SetLibrary(Fluent)
    SaveManager:SetFolder("PcdFnlBossV11")
    SaveManager:SetIgnoreIndexes({"V11_Enable", "HxH_ShadowMonarchRaid"})
    SaveManager:BuildConfigSection(Settings)
end
if InterfaceManager and InterfaceManager.FileSystemAvailable then
    InterfaceManager:SetLibrary(Fluent)
    InterfaceManager:SetFolder("PcdFnlBossInterface")
    InterfaceManager:BuildInterfaceSection(Settings)
end
Window:SelectTab(1)
if SaveManager and SaveManager.FileSystemAvailable then
    pcall(function() SaveManager:LoadAutoloadConfig() end)
end

local afkConn = Player.Idled:Connect(function()
    if not S.Alive or not C.AFK then return end
    pcall(function()
        VU:CaptureController()
        VU:ClickButton2(Vector2.zero)
    end)
end)

function S.Stop()
    Raid.Enabled = false
    Raid.Target = nil
    if S.Enabled and S.Phase == "BREAK_RUBBLE" and S.RubbleRef then
        local savedNoclip = C.Noclip
        C.Noclip = false
        rubblePosition(S.RubbleRef)
        C.Noclip = savedNoclip
    end
    S.Alive = false
    S.Enabled = false
    cancelTravel()
    releaseHold()
    restoreCollisions()
    if S.noclipConn then S.noclipConn:Disconnect() end
    if S.holdConn then S.holdConn:Disconnect() end
    if afkConn then afkConn:Disconnect() end
    if S.UI and not S.UI.Unloaded then
        pcall(function() S.UI:Destroy() end)
    end
end

S.holdConn = RunService.Heartbeat:Connect(function()
    pcall(updateTravel)
    if not S.Alive or not (S.Enabled or Raid.Enabled) or not S.HoldCF or S.Travel then return end
    local cf = S.HoldCF
    local char, root = character()
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
        pcall(applyNoclip)
    end
end)

Env.PcdBehindStable = S
Env.PcdHxHHub = S

task.spawn(function()
    while S.Alive and not Fluent.Unloaded do
        local ok, err = pcall(function()
            if S.Enabled then syncHUDProgress() end
            step()
        end)
        if not ok then
            S.Status = "Error: " .. tostring(err)
        end
        if Raid.Enabled then
            local raidOk = pcall(raidStep)
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
