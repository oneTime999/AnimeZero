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
    Distance = 0,
    Height = 0,
    M1Interval = 0.2,
    ConfirmClear = 1.0,
    M1 = true,
    Skills = true,
    AFK = true,
    SkillInput = "Automatic",
    SkillKeyHold = 0.06,
    Noclip = true,
    TravelMethod = "Tween",
    TravelSpeed = 170,
    TravelArc = 10,
    ArrivalConfirm = 0.55,
    AutoReplay = true,
    AutoNextStage = false,
    AutoReset = true,
    AutoResetDelay = 10
}

local S = {
    Alive = true,
    LastM1 = 0,
    Status = "Disabled",
    SkillStatus = "Not used yet",
    UI = nil,
    Collisions = setmetatable({}, {__mode = "k"}),
    HoldCF = nil,
    Travel = nil,
    ArrivedTag = nil
}

local ZzzzWorld = {
    Enabled = false,
    Target = nil
}

local Lift = {
    Enabled = false,
    Target = nil,
    Status = "Disabled",
    NextPromptAt = 0,
    PromptAttempts = 0,
    AutoNextFloor = true,
    AttackGap = 8,
    HadEnemies = false,
    EmptySince = nil,
    WaitingForWave = false,
    NextFloorBusy = false,
    NextFloorAt = 0
}

local Story = {
    Enabled = false,
    Target = nil,
    Status = "Disabled",
    EmptySince = nil,
    RubbleOffset = 10,
    -- Per-rock override of the distance below the rock ([Border number] = studs).
    -- Used only for rocks that have no fixed stand point below.
    RubbleOffsets = {},
    -- Per-rock fixed position to stand on while hitting it ([Border number] = Vector3).
    -- Rock 2 is only hit from this spot (the furthest back the hit still reaches).
    RubbleStandPoints = {
        [2] = Vector3.new(-8.813241004943848, 2.9999992847442627, -93.86968231201172),
    },
    EnemyGap = 2.5
}

local Raid = {
    Enabled = false,
    Status = "Disabled",
    Target = nil,
    BossImmune = true,
    BossPresent = false,
    BossEngaged = false,
    BossGoneAt = nil,
    ReplayUntil = 0,
    RoundFinished = false
}

local Skill = {
    {Name = "Skill 1", Key = Enum.KeyCode.One, VK = 0x31, Delay = 0.1, Enabled = true, Last = -math.huge},
    {Name = "Skill 2", Key = Enum.KeyCode.Two, VK = 0x32, Delay = 0.1, Enabled = true, Last = -math.huge},
    {Name = "Skill 3", Key = Enum.KeyCode.Three, VK = 0x33, Delay = 0.1, Enabled = true, Last = -math.huge},
    {Name = "Ultimate", Key = Enum.KeyCode.G, VK = 0x47, Delay = 0.1, Enabled = true, Last = -math.huge}
}


return {
    Players = Players, RS = RS, WS = WS, RunService = RunService,
    VU = VU, Player = Player, Env = Env, VIM = VIM,
    C = C, S = S, Raid = Raid, ZzzzWorld = ZzzzWorld, Lift = Lift, Story = Story, Skill = Skill,
    Functions = {},
    FarmMonitor = {
        Mode = "Off",
        State = "Idle",
        NPCs = 0,
        LastDamageAt = nil,
        LastSpawnAt = nil,
        LastError = "None",
        LastErrorAt = nil,
        RecoveryStage = 0,
        Recoveries = 0,
        LastReason = "None",
        LastActionAt = nil
    }
}
