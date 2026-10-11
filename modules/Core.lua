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
    AutoReplay = true,
    AutoCollectDrops = false
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

local ZzzzWorld = {
    Enabled = false,
    Target = nil
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


return {
    Players = Players, RS = RS, WS = WS, RunService = RunService,
    VU = VU, Player = Player, Env = Env, VIM = VIM,
    C = C, S = S, Raid = Raid, ZzzzWorld = ZzzzWorld, Skill = Skill,
    RubbleCoordinates = RubbleCoordinates, WaveCoordinates = WaveCoordinates,
    LastBorder = LastBorder, LastEnemyWave = LastEnemyWave,
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
