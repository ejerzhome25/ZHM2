--[[
    ZHM EGG + PLOT AUTOMATION
    Combined from:
      - All Plots Model Scanner
      - Area Egg Live Scanner
      - ZHM UI Template
      - Pickup action log / PickablePrompt flow

    FEATURES
      * Finds your own plot first.
      * Scans models in every plot; your plot is highlighted stronger.
      * Plot ESP never scans egg models.
      * Egg ESP scans only eggs OUTSIDE Workspace.Plots.
      * Removes egg ESP when you OR another player picks the egg up.
      * Multi-select egg target dropdown.
      * Auto TP -> selected egg -> trigger pickup -> TP back to your plot.
      * Live Backpack inventory scanner + idle auto-equip Treadmill tool.
      * Auto-place Backpack eggs inside your own plot without a manual click.
      * Instant Proximity using fireproximityprompt.
      * Auto hatch own placed eggs using EggService.HatchEgg(uid).
      * Mobile/PC friendly ZHM UI shell.
      * ALL scanners are live/event-driven with a fallback rescan.
]]

--// SERVICES
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// STOP OLD COPY
local ENV = (getgenv and getgenv()) or _G
if ENV.__ZHM_EGG_PLOT_STOP then
    pcall(ENV.__ZHM_EGG_PLOT_STOP)
end

local RUNNING = true
local Connections = {}

local function bind(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Connections, connection)
    return connection
end

--// EASY CONFIG
local GUI_NAME = "ZHM_EggPlotHub"
local HUB_TITLE = "ZHM AUTOMATION HUB"
local MINI_TEXT = "Z"

local TAB_DEFINITIONS = {
    {Key = "Main", Label = "MAIN"},
    {Key = "Eggs", Label = "EGGS"},
    {Key = "Sell", Label = "SELL"},
    {Key = "Settings", Label = "SETTINGS"},
}

--// AUTOMATION SETTINGS
-- Low-lag timings: live events still do the fast work; these loops are only fallbacks.
local EGG_UPDATE_RATE = 0.35
local PLOT_UPDATE_RATE = 0.60
local TARGET_SCAN_RATE = 0.25
local LIVE_EVENT_DELAY = 0.04
-- Full Workspace rescans are expensive, so keep them rare.
local RESCAN_RATE = 12.00
local MAX_ESP_DISTANCE = 5000

local TP_HEIGHT = 3
local AUTO_PICKUP_RETRIES = 5
local AUTO_PICKUP_TIMEOUT = 1.80
local AUTO_LOOP_DELAY = 0.20
local EGG_STAY_TIME = 0.50
local RETURN_DELAY = 0.02
local IDLE_TREADMILL_EQUIP_RATE = 1.25
local AUTO_BUY_TREADMILL_RATE = 3.00 -- low-lag fallback; new payloads are event-driven
local AUTO_CLAIM_TRAINING_BONUS_RATE = 1.50
local AUTO_PLACE_SCAN_RATE = 0.35
local AUTO_PLACE_DELAY = 0.28
local AUTO_PLACE_CLICK_SETTLE = 0.18
local AUTO_HATCH_SCAN_RATE = 0.50 -- fallback only; CLAIM is event-driven
local AUTO_HATCH_UID_COOLDOWN = 0.10
local AUTO_HATCH_POST_INVOKE_DELAY = 0
local FIRST_EGG_SCAN_RATE = 1.00 -- fallback only; live UI signals detect CLAIM instantly

-- Progression automation.
local AUTO_UPGRADE_RATE = 0.65
local AUTO_PLOT_UPGRADE_RATE = 0.80
local AUTO_REBIRTH_RATE = 1.00

local State = {
    AutoPickup = false,
    AutoPickupUserEnabled = false,
    AutoPickupSuspendedByAutoPlace = false,
    AutoEquipTreadmill = true,
    AutoBuyTreadmill = false,
    AutoClaimTrainingBonus = true,
    AutoEquipBestAnimals = false,
    FPSBoost = false,
    FPSGui = nil,
    AutoPlaceEggs = true, -- Method 1: Growing Eggs == 0 starts a fill cycle.
    AutoPlaceAfterPickup = false, -- Method 2: ignore Growing Eggs; place after pickup/no target.
    PlacingEggs = false,
    MaxEggLimitReached = false,
    GrowingEggs = nil,
    GrowingEggMax = nil,
    GrowingEggCounterReady = false,

    -- Live first-egg scanner.
    FirstEggName = "No Egg",
    FirstEggUID = nil,
    FirstEggAction = "SEARCHING",
    FirstEggScannerReady = false,

    AutoHatchEggs = false,
    HatchingEggs = false,

    AutoUpgrade = false,
    AutoUpgradePlot = false,
    AutoRebirth = false,
    AutoBuyTrail = false,
    AutoEquipTrail = true,

    InstantProximity = true,
    EggESP = false,
    PlotESP = false,
    ShowDistance = false,
    SelectedEggs = {},
    Busy = false,
    CurrentTarget = nil,

    -- Avoid repeatedly writing identical strings into TextLabels every scan tick.
    StatusCache = {},
    MaxEggWarningObject = nil,
}


--// CONFIGURATION REGISTRY + PERSISTENT SAVE / AUTO LOAD
-- Stored on State (not top-level locals) to stay below Luau's 200-local register limit.
-- Uses common executor file APIs when available. Falls back to in-session memory
-- if the executor does not expose writefile/readfile.
State.ConfigRegistry = {
    Toggles = {},
    MultiSelects = {},
}

State.ConfigSystem = {
    HttpService = game:GetService("HttpService"),
    Folder = "ZHM_Automation_Hub",
    ConfigFolder = "ZHM_Automation_Hub/configs",
    AutoLoadFile = "ZHM_Automation_Hub/autoload.json",
    StatusCard = nil,
    NameInput = nil,
    Loading = false,
    Memory = ENV.__ZHM_CONFIG_MEMORY or {},
    MemoryAutoLoad = ENV.__ZHM_AUTOLOAD_CONFIG,
}
ENV.__ZHM_CONFIG_MEMORY = State.ConfigSystem.Memory

function State.ConfigSystem.SetStatus(message)
    message = tostring(message or "")
    if State.ConfigSystem.StatusCard and State.ConfigSystem.StatusCard.SetText then
        State.ConfigSystem.StatusCard.SetText(message)
    end
    print("[ZHM Config] " .. message)
end

function State.ConfigSystem.SanitizeName(value)
    value = tostring(value or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("[^%w%s_%-]", "")
    value = value:gsub("%s+", "_")
    if #value > 48 then
        value = value:sub(1, 48)
    end
    return value
end

function State.ConfigSystem.HasFileApi()
    return typeof(writefile) == "function" and typeof(readfile) == "function"
end

function State.ConfigSystem.EnsureFolders()
    if typeof(makefolder) ~= "function" then
        return false
    end

    pcall(function()
        if typeof(isfolder) ~= "function" or not isfolder(State.ConfigSystem.Folder) then
            makefolder(State.ConfigSystem.Folder)
        end
    end)

    pcall(function()
        if typeof(isfolder) ~= "function" or not isfolder(State.ConfigSystem.ConfigFolder) then
            makefolder(State.ConfigSystem.ConfigFolder)
        end
    end)

    return true
end

function State.ConfigSystem.ConfigPath(name)
    local safe = State.ConfigSystem.SanitizeName(name)
    if safe == "" then
        return nil, nil
    end
    return State.ConfigSystem.ConfigFolder .. "/" .. safe .. ".json", safe
end

function State.ConfigSystem.FileExists(path)
    if typeof(isfile) == "function" then
        local ok, exists = pcall(isfile, path)
        return ok and exists == true
    end

    if typeof(readfile) == "function" then
        local ok = pcall(readfile, path)
        return ok
    end

    return false
end

function State.ConfigSystem.Capture()
    local data = {
        Version = 1,
        SavedAt = os.time(),
        Toggles = {},
        MultiSelects = {},
    }

    for title, controller in pairs(State.ConfigRegistry.Toggles) do
        if controller and controller.Get then
            local ok, value = pcall(controller.Get)
            if ok then
                data.Toggles[title] = value == true
            end
        end
    end

    for title, controller in pairs(State.ConfigRegistry.MultiSelects) do
        if controller and controller.Get then
            local ok, selection = pcall(controller.Get)
            if ok and typeof(selection) == "table" then
                data.MultiSelects[title] = selection
            end
        end
    end

    return data
end

function State.ConfigSystem.Apply(data)
    if typeof(data) ~= "table" then
        return false, "invalid config data"
    end

    State.ConfigSystem.Loading = true

    -- Apply selections first so Auto TP has its targets before its toggle turns on.
    if typeof(data.MultiSelects) == "table" then
        for title, values in pairs(data.MultiSelects) do
            local controller = State.ConfigRegistry.MultiSelects[title]
            if controller and controller.Set and typeof(values) == "table" then
                pcall(controller.Set, values)
            end
        end
    end

    if typeof(data.Toggles) == "table" then
        for title, value in pairs(data.Toggles) do
            local controller = State.ConfigRegistry.Toggles[title]
            if controller and controller.Set and type(value) == "boolean" then
                pcall(controller.Set, value)
            end
        end
    end

    State.ConfigSystem.Loading = false
    return true
end

function State.ConfigSystem.Save(name)
    local path, safe = State.ConfigSystem.ConfigPath(name)
    if not path then
        State.ConfigSystem.SetStatus("Enter a config name first.")
        return false
    end

    local data = State.ConfigSystem.Capture()
    local okEncode, encoded = pcall(function()
        return State.ConfigSystem.HttpService:JSONEncode(data)
    end)

    if not okEncode then
        State.ConfigSystem.SetStatus("Save failed: JSON encode error.")
        return false
    end

    State.ConfigSystem.Memory[safe] = data

    if State.ConfigSystem.HasFileApi() then
        State.ConfigSystem.EnsureFolders()
        local okWrite, err = pcall(writefile, path, encoded)
        if not okWrite then
            State.ConfigSystem.SetStatus("Save failed: " .. tostring(err))
            return false
        end
        State.ConfigSystem.SetStatus("Saved config: " .. safe)
        return true
    end

    State.ConfigSystem.SetStatus("Saved config in-session: " .. safe .. " | executor file API unavailable")
    return true
end

function State.ConfigSystem.Read(name)
    local path, safe = State.ConfigSystem.ConfigPath(name)
    if not path then
        return nil, nil, "enter a config name first"
    end

    if State.ConfigSystem.HasFileApi() and State.ConfigSystem.FileExists(path) then
        local okRead, raw = pcall(readfile, path)
        if not okRead then
            return nil, safe, tostring(raw)
        end

        local okDecode, data = pcall(function()
            return State.ConfigSystem.HttpService:JSONDecode(raw)
        end)
        if not okDecode or typeof(data) ~= "table" then
            return nil, safe, "invalid config JSON"
        end
        return data, safe
    end

    local memory = State.ConfigSystem.Memory[safe]
    if typeof(memory) == "table" then
        return memory, safe
    end

    return nil, safe, "config not found"
end

function State.ConfigSystem.Load(name, isAuto)
    local data, safe, err = State.ConfigSystem.Read(name)
    if not data then
        State.ConfigSystem.SetStatus((isAuto and "Auto load failed: " or "Load failed: ") .. tostring(err))
        return false
    end

    local ok, applyErr = State.ConfigSystem.Apply(data)
    if not ok then
        State.ConfigSystem.SetStatus((isAuto and "Auto load failed: " or "Load failed: ") .. tostring(applyErr))
        return false
    end

    if State.ConfigSystem.NameInput and State.ConfigSystem.NameInput.Set then
        State.ConfigSystem.NameInput.Set(safe)
    end

    State.ConfigSystem.SetStatus((isAuto and "Auto loaded config: " or "Loaded config: ") .. tostring(safe))
    return true
end

function State.ConfigSystem.SetAutoLoad(name)
    local _, safe = State.ConfigSystem.ConfigPath(name)
    if not safe then
        State.ConfigSystem.SetStatus("Enter a config name first.")
        return false
    end

    local data = State.ConfigSystem.Read(safe)
    if not data then
        State.ConfigSystem.SetStatus("Save the config before setting Auto Load.")
        return false
    end

    State.ConfigSystem.MemoryAutoLoad = safe
    ENV.__ZHM_AUTOLOAD_CONFIG = safe

    if State.ConfigSystem.HasFileApi() then
        State.ConfigSystem.EnsureFolders()
        local encoded = State.ConfigSystem.HttpService:JSONEncode({Name = safe})
        local okWrite, err = pcall(writefile, State.ConfigSystem.AutoLoadFile, encoded)
        if not okWrite then
            State.ConfigSystem.SetStatus("Could not set Auto Load: " .. tostring(err))
            return false
        end
    end

    State.ConfigSystem.SetStatus("Auto Load set to: " .. safe)
    return true
end

function State.ConfigSystem.ClearAutoLoad()
    State.ConfigSystem.MemoryAutoLoad = nil
    ENV.__ZHM_AUTOLOAD_CONFIG = nil

    if typeof(delfile) == "function" and State.ConfigSystem.FileExists(State.ConfigSystem.AutoLoadFile) then
        pcall(delfile, State.ConfigSystem.AutoLoadFile)
    elseif State.ConfigSystem.HasFileApi() then
        -- Empty marker for executors without delfile.
        pcall(writefile, State.ConfigSystem.AutoLoadFile, State.ConfigSystem.HttpService:JSONEncode({Name = ""}))
    end

    State.ConfigSystem.SetStatus("Auto Load cleared.")
end

function State.ConfigSystem.GetAutoLoadName()
    if State.ConfigSystem.HasFileApi() and State.ConfigSystem.FileExists(State.ConfigSystem.AutoLoadFile) then
        local okRead, raw = pcall(readfile, State.ConfigSystem.AutoLoadFile)
        if okRead then
            local okDecode, data = pcall(function()
                return State.ConfigSystem.HttpService:JSONDecode(raw)
            end)
            if okDecode and typeof(data) == "table" then
                local safe = State.ConfigSystem.SanitizeName(data.Name)
                if safe ~= "" then
                    return safe
                end
            end
        end
    end

    return State.ConfigSystem.MemoryAutoLoad
end

function State.ConfigSystem.AutoLoad()
    local name = State.ConfigSystem.GetAutoLoadName()
    if not name or name == "" then
        State.ConfigSystem.SetStatus("No Auto Load config set.")
        return false
    end

    return State.ConfigSystem.Load(name, true)
end

--// EXTREME FPS BOOSTER + FPS COUNTER
-- Toggleable/reversible version based on the supplied booster.
-- ON: applies low-graphics optimization + 60 FPS cap + top-center counter.
-- OFF: restores properties captured before the boost whenever possible.
local FPSBooster = {
    Enabled = false,
    Originals = setmetatable({}, {__mode = "k"}),
    CounterConnection = nil,
    QualityLevel = nil,
    SavedQualityLevel = nil,
}

local function fpsRemember(object, property)
    if not object then return end

    local data = FPSBooster.Originals[object]
    if not data then
        data = {}
        FPSBooster.Originals[object] = data
    end

    if data[property] ~= nil then
        return
    end

    local ok, value = pcall(function()
        return object[property]
    end)

    if ok then
        data[property] = {Value = value}
    end
end

local function fpsSet(object, property, value)
    if not object then return end
    fpsRemember(object, property)
    pcall(function()
        object[property] = value
    end)
end

local function fpsRestoreObject(object, data)
    if not object or not data then return end

    for property, entry in pairs(data) do
        pcall(function()
            object[property] = entry.Value
        end)
    end
end

function FPSBooster.DestroyCounter()
    if FPSBooster.CounterConnection then
        pcall(function()
            FPSBooster.CounterConnection:Disconnect()
        end)
        FPSBooster.CounterConnection = nil
    end

    if State.FPSGui and State.FPSGui.Parent then
        State.FPSGui:Destroy()
    end
    State.FPSGui = nil

    local oldCounter = playerGui:FindFirstChild("ZHM_FPS_Counter")
    if oldCounter then
        oldCounter:Destroy()
    end
end

function FPSBooster.CreateCounter()
    FPSBooster.DestroyCounter()

    if not FPSBooster.Enabled then
        return
    end

    local RunService = game:GetService("RunService")

    local FPSGui = Instance.new("ScreenGui")
    FPSGui.Name = "ZHM_FPS_Counter"
    FPSGui.ResetOnSpawn = false
    FPSGui.IgnoreGuiInset = true
    FPSGui.DisplayOrder = 999999
    FPSGui.Parent = playerGui
    State.FPSGui = FPSGui

    local FPSFrame = Instance.new("Frame")
    FPSFrame.Name = "FPSFrame"
    FPSFrame.Size = UDim2.new(0, 132, 0, 36)
    FPSFrame.AnchorPoint = Vector2.new(0.5, 0)
    FPSFrame.Position = UDim2.new(0.5, 0, 0, 8)
    FPSFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
    FPSFrame.BackgroundTransparency = 0.08
    FPSFrame.BorderSizePixel = 0
    FPSFrame.Parent = FPSGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = FPSFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(53, 59, 70)
    stroke.Thickness = 1
    stroke.Transparency = 0.25
    stroke.Parent = FPSFrame

    local FPSLabel = Instance.new("TextLabel")
    FPSLabel.Name = "FPS"
    FPSLabel.Size = UDim2.fromScale(1, 1)
    FPSLabel.BackgroundTransparency = 1
    FPSLabel.Text = "FPS: --"
    FPSLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
    FPSLabel.TextSize = 15
    FPSLabel.Font = Enum.Font.GothamBold
    FPSLabel.Parent = FPSFrame

    local frameCount = 0
    local elapsed = 0
    local lastFPS = -1

    FPSBooster.CounterConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if not RUNNING or not FPSBooster.Enabled or not FPSLabel.Parent then
            return
        end

        frameCount += 1
        elapsed += deltaTime

        if elapsed >= 0.5 then
            local fps = math.floor(frameCount / elapsed + 0.5)
            frameCount = 0
            elapsed = 0

            if fps ~= lastFPS then
                lastFPS = fps
                FPSLabel.Text = "FPS: " .. tostring(fps)

                if fps >= 60 then
                    FPSLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
                elseif fps >= 30 then
                    FPSLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
                else
                    FPSLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                end
            end
        end
    end)
end

function FPSBooster.OptimizeObject(object)
    if not FPSBooster.Enabled or not RUNNING or not object then
        return
    end

    -- HARDCORE WORLD-TEXTURE STRIP. Everything is changed through fpsSet()
    -- so the original property is remembered and can be restored when OFF.
    if object:IsA("BasePart") then
        fpsSet(object, "Material", Enum.Material.SmoothPlastic)
        fpsSet(object, "Reflectance", 0)
        fpsSet(object, "CastShadow", false)

        -- Remove custom material variants if the class supports it.
        fpsSet(object, "MaterialVariant", "")

        if object:IsA("MeshPart") then
            fpsSet(object, "RenderFidelity", Enum.RenderFidelity.Performance)
            -- Removes the mesh's baked texture while FPS Boost is ON.
            fpsSet(object, "TextureID", "")
        elseif object:IsA("UnionOperation") then
            fpsSet(object, "RenderFidelity", Enum.RenderFidelity.Performance)
            fpsSet(object, "UsePartColor", true)
        end

    elseif object:IsA("SpecialMesh") then
        -- Classic meshes can carry their own texture separately from the Part.
        fpsSet(object, "TextureId", "")

    elseif object:IsA("Decal") or object:IsA("Texture") then
        -- Hide + clear image content. Keeping the instance makes the change reversible.
        fpsSet(object, "Transparency", 1)
        fpsSet(object, "Texture", "")

    elseif object:IsA("SurfaceAppearance") then
        -- Strip PBR maps (color/normal/metal/roughness).
        fpsSet(object, "ColorMap", "")
        fpsSet(object, "NormalMap", "")
        fpsSet(object, "MetalnessMap", "")
        fpsSet(object, "RoughnessMap", "")

    elseif object:IsA("Sky") then
        -- Remove skybox + sun/moon textures.
        fpsSet(object, "SkyboxBk", "")
        fpsSet(object, "SkyboxDn", "")
        fpsSet(object, "SkyboxFt", "")
        fpsSet(object, "SkyboxLf", "")
        fpsSet(object, "SkyboxRt", "")
        fpsSet(object, "SkyboxUp", "")
        fpsSet(object, "SunTextureId", "")
        fpsSet(object, "MoonTextureId", "")
        fpsSet(object, "CelestialBodiesShown", false)

    elseif object:IsA("ParticleEmitter")
        or object:IsA("Smoke")
        or object:IsA("Fire")
        or object:IsA("Sparkles")
        or object:IsA("Trail")
        or object:IsA("Beam")
        or object:IsA("PointLight")
        or object:IsA("SpotLight")
        or object:IsA("SurfaceLight")
        or object:IsA("Highlight")
        or object:IsA("PostEffect") then

        fpsSet(object, "Enabled", false)

    elseif object:IsA("Explosion") then
        -- Keep the instance alive; only suppress visible effects.
        fpsSet(object, "Visible", false)

    elseif object:IsA("Atmosphere") then
        fpsSet(object, "Density", 0)
        fpsSet(object, "Haze", 0)
        fpsSet(object, "Glare", 0)

    elseif object:IsA("Clouds") then
        fpsSet(object, "Enabled", false)
        fpsSet(object, "Cover", 0)
        fpsSet(object, "Density", 0)
    end
end

function FPSBooster.ApplyEnvironment()
    local Lighting = game:GetService("Lighting")
    local Terrain = Workspace:FindFirstChildOfClass("Terrain")

    fpsSet(Lighting, "GlobalShadows", false)
    fpsSet(Lighting, "Brightness", 1)
    fpsSet(Lighting, "FogStart", 0)
    fpsSet(Lighting, "FogEnd", 1000000)
    fpsSet(Lighting, "EnvironmentDiffuseScale", 0)
    fpsSet(Lighting, "EnvironmentSpecularScale", 0)

    if Terrain then
        fpsSet(Terrain, "WaterWaveSize", 0)
        fpsSet(Terrain, "WaterWaveSpeed", 0)
        fpsSet(Terrain, "WaterReflectance", 0)
        fpsSet(Terrain, "WaterTransparency", 1)
        -- Removes terrain grass/detail decoration while boost is enabled.
        fpsSet(Terrain, "Decoration", false)
    end
end

function FPSBooster.Enable()
    if FPSBooster.Enabled or not RUNNING then
        return
    end

    FPSBooster.Enabled = true
    State.FPSBoost = true

    if FPSBooster.QualityLevel == nil then
        pcall(function()
            FPSBooster.QualityLevel = settings().Rendering.QualityLevel
        end)
    end

    if FPSBooster.SavedQualityLevel == nil then
        pcall(function()
            FPSBooster.SavedQualityLevel =
                UserSettings():GetService("UserGameSettings").SavedQualityLevel
        end)
    end

    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)

    pcall(function()
        UserSettings():GetService("UserGameSettings").SavedQualityLevel =
            Enum.SavedQualitySetting.QualityLevel1
    end)

    if setfpscap then
        pcall(function()
            setfpscap(60)
        end)
    end

    FPSBooster.ApplyEnvironment()
    FPSBooster.CreateCounter()

    task.spawn(function()
        local descendants = Workspace:GetDescendants()
        local processed = 0

        for _, object in ipairs(descendants) do
            if not RUNNING or not FPSBooster.Enabled then
                break
            end

            FPSBooster.OptimizeObject(object)
            processed += 1

            if processed % 400 == 0 then
                task.wait()
            end
        end
    end)

    for _, object in ipairs(game:GetService("Lighting"):GetDescendants()) do
        FPSBooster.OptimizeObject(object)
    end

    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        for _, object in ipairs(terrain:GetDescendants()) do
            FPSBooster.OptimizeObject(object)
        end
    end

    print("[ZHM FPS] Booster ON | HARDCORE texture strip + 60 FPS cap")
end

function FPSBooster.Disable()
    if not FPSBooster.Enabled then
        FPSBooster.DestroyCounter()
        State.FPSBoost = false
        return
    end

    FPSBooster.Enabled = false
    State.FPSBoost = false
    FPSBooster.DestroyCounter()

    for object, data in pairs(FPSBooster.Originals) do
        fpsRestoreObject(object, data)
    end

    FPSBooster.Originals = setmetatable({}, {__mode = "k"})

    if FPSBooster.QualityLevel ~= nil then
        pcall(function()
            settings().Rendering.QualityLevel = FPSBooster.QualityLevel
        end)
    end

    if FPSBooster.SavedQualityLevel ~= nil then
        pcall(function()
            UserSettings():GetService("UserGameSettings").SavedQualityLevel =
                FPSBooster.SavedQualityLevel
        end)
    end

    if setfpscap then
        local uncapped = pcall(function()
            -- Most executors treat 0 as uncapped/default.
            setfpscap(0)
        end)

        if not uncapped then
            pcall(function()
                setfpscap(999)
            end)
        end
    end

    print("[ZHM FPS] Booster OFF | visuals restored where possible")
end

function FPSBooster.SetEnabled(enabled)
    if enabled then
        FPSBooster.Enable()
    else
        FPSBooster.Disable()
    end
end

-- Keep live optimization ready, but only alter new objects while the toggle is ON.
bind(Workspace.DescendantAdded, function(object)
    if FPSBooster.Enabled then
        task.defer(FPSBooster.OptimizeObject, object)
    end
end)

bind(game:GetService("Lighting").DescendantAdded, function(object)
    if FPSBooster.Enabled then
        task.defer(FPSBooster.OptimizeObject, object)
    end
end)

-- FPS Booster starts OFF. It only runs after the user turns the FPS Boost toggle ON.

--// THEME - FROM THE PROVIDED ZHM UI TEMPLATE
local UI_BG      = Color3.fromRGB(18, 20, 25)
local UI_PANEL   = Color3.fromRGB(25, 28, 34)
local UI_PANEL_2 = Color3.fromRGB(33, 37, 45)
local UI_ACCENT  = Color3.fromRGB(75, 140, 255)
local UI_TEXT    = Color3.fromRGB(242, 244, 248)
local UI_MUTED   = Color3.fromRGB(145, 151, 163)
local UI_STROKE  = Color3.fromRGB(53, 59, 70)
local UI_DANGER  = Color3.fromRGB(235, 92, 92)

--// HELPERS
local function cleanName(name)
    name = tostring(name or "")
    name = name:gsub("%(Clone%)", "")
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    return string.lower(name)
end

local function getCharacterRoot()
    local character = player.Character
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

local function zeroVelocity(root)
    if not root then return end
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function tpToCFrame(cf)
    local root = getCharacterRoot()
    if not root or not cf then return false end
    zeroVelocity(root)
    root.CFrame = cf
    zeroVelocity(root)
    return true
end

local function getObjectPart(object)
    if not object then return nil end

    if object:IsA("BasePart") then
        return object
    end

    if object:IsA("Model") then
        if object.PrimaryPart then
            return object.PrimaryPart
        end

        local preferredNames = {
            "PrimaryPart", "Egg", "egg", "Main", "Root",
            "Handle", "HumanoidRootPart", "Head"
        }

        for _, name in ipairs(preferredNames) do
            local part = object:FindFirstChild(name, true)
            if part and part:IsA("BasePart") then
                return part
            end
        end

        for _, descendant in ipairs(object:GetDescendants()) do
            if descendant:IsA("BasePart") then
                return descendant
            end
        end
    end

    return nil
end

--// PLOTS
local PlotsFolder = Workspace:WaitForChild("Plots")

local function getTopLevelPlot(object)
    local current = object
    while current do
        if current.Parent == PlotsFolder then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function findPlotBySign()
    local username = string.lower(player.Name)

    for _, object in ipairs(PlotsFolder:GetDescendants()) do
        local objectName = string.lower(object.Name)

        if string.find(objectName, username, 1, true)
            and string.find(objectName, "floatingplotsign", 1, true) then

            local plot = getTopLevelPlot(object)
            if plot then
                return plot
            end
        end
    end

    return nil
end

local function findPlotByOwner()
    for _, plot in ipairs(PlotsFolder:GetChildren()) do
        local ownerUserId =
            plot:GetAttribute("OwnerUserId")
            or plot:GetAttribute("UserId")
            or plot:GetAttribute("PlayerUserId")

        if tonumber(ownerUserId) == player.UserId then
            return plot
        end

        local ownerName =
            plot:GetAttribute("Owner")
            or plot:GetAttribute("OwnerName")
            or plot:GetAttribute("PlayerName")

        if ownerName and string.lower(tostring(ownerName)) == string.lower(player.Name) then
            return plot
        end

        for _, object in ipairs(plot:GetDescendants()) do
            if object:IsA("ObjectValue") and object.Value == player then
                return plot
            end

            if object:IsA("StringValue") then
                local n = string.lower(object.Name)
                if n == "owner" or n == "player" or n == "ownername" then
                    if string.lower(tostring(object.Value)) == string.lower(player.Name) then
                        return plot
                    end
                end
            elseif object:IsA("IntValue") or object:IsA("NumberValue") then
                local n = string.lower(object.Name)
                if n == "userid" or n == "owneruserid" or n == "playeruserid" then
                    if tonumber(object.Value) == player.UserId then
                        return plot
                    end
                end
            end
        end
    end

    return nil
end

local function findMyPlot()
    return findPlotBySign() or findPlotByOwner()
end

local MyPlot = nil

repeat
    MyPlot = findMyPlot()
    if not MyPlot then
        warn("[ZHM] Waiting for your plot...")
        task.wait(1)
    end
until MyPlot or not RUNNING

if not RUNNING then
    return
end

local function isInsideAnyPlot(object)
    return object and PlotsFolder and object:IsDescendantOf(PlotsFolder) or false
end

local function isMyPlot(plot)
    return plot ~= nil and plot == MyPlot
end

local function getMyPlotReturnCFrame()
    if not MyPlot or not MyPlot.Parent then
        MyPlot = findMyPlot()
    end

    if not MyPlot then
        return nil
    end

    local surface = MyPlot:FindFirstChild("PlotSurface", true)
    if surface and surface:IsA("BasePart") then
        return surface.CFrame * CFrame.new(0, TP_HEIGHT, 0)
    end

    if MyPlot:IsA("Model") then
        if MyPlot.PrimaryPart then
            return MyPlot.PrimaryPart.CFrame * CFrame.new(0, TP_HEIGHT, 0)
        end

        local ok, pivot = pcall(function()
            return MyPlot:GetPivot()
        end)

        if ok and pivot then
            return pivot * CFrame.new(0, TP_HEIGHT, 0)
        end
    end

    local part = MyPlot:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.CFrame * CFrame.new(0, TP_HEIGHT, 0)
    end

    return nil
end

--// LOAD AREAS CONFIG
local Configs = ReplicatedStorage:WaitForChild("Configs")
local AreasModule = Configs:WaitForChild("AreasConfig")

local configOk, AreasConfig = pcall(require, AreasModule)
if not configOk or not AreasConfig or not AreasConfig.AREAS then
    warn("[ZHM] Failed to load AreasConfig:", AreasConfig)
    return
end

local EggDatabase = {}
local EggOptions = {}

for areaName, areaData in pairs(AreasConfig.AREAS) do
    if areaData.eggs then
        for _, eggData in ipairs(areaData.eggs) do
            local key = cleanName(eggData.id)
            local info = {
                EggName = eggData.id,
                AreaName = areaName,
                AreaDisplay = areaData.id or areaName,
                Chance = eggData.chance or 0,
                AreaOrder = areaData.order or 999,
            }

            EggDatabase[key] = info

            table.insert(EggOptions, {
                Value = eggData.id,
                Label = string.format(
                    "%s  |  %s  |  %s%%",
                    eggData.id,
                    areaName,
                    tostring(eggData.chance or 0)
                ),
                Order = info.AreaOrder,
                Chance = info.Chance,
            })
        end
    end
end

table.sort(EggOptions, function(a, b)
    if a.Order == b.Order then
        return a.Chance > b.Chance
    end
    return a.Order < b.Order
end)

local function getEggInfo(object)
    if not object then return nil end
    return EggDatabase[cleanName(object.Name)]
end

local function isEggName(name)
    local cleaned = cleanName(name)
    return EggDatabase[cleaned] ~= nil or string.sub(cleaned, -4) == "_egg"
end

local function isInsideEggModel(object)
    local current = object

    while current and current ~= Workspace and current ~= PlotsFolder do
        if current:IsA("Model") and isEggName(current.Name) then
            return true
        end
        current = current.Parent
    end

    return false
end

local function findEggAncestor(object)
    local current = object

    while current and current ~= Workspace do
        if getEggInfo(current) then
            return current
        end
        current = current.Parent
    end

    return nil
end

--// SCANNER STORAGE
local oldPlotFolder = playerGui:FindFirstChild("ZHM_AllPlotScanner")
if oldPlotFolder then oldPlotFolder:Destroy() end

local oldEggFolder = playerGui:FindFirstChild("ZHM_AreaEggScanner")
if oldEggFolder then oldEggFolder:Destroy() end

local PlotScannerFolder = Instance.new("Folder")
PlotScannerFolder.Name = "ZHM_AllPlotScanner"
PlotScannerFolder.Parent = playerGui

local EggScannerFolder = Instance.new("Folder")
EggScannerFolder.Name = "ZHM_AreaEggScanner"
EggScannerFolder.Parent = playerGui

local PlotTracked = {}
local EggTracked = {}
local CollectedEggs = setmetatable({}, {__mode = "k"})
-- Stores the prompt/position that existed when an egg was collected.
-- This lets the scanner recognize when the game RECYCLES the same egg instance.
local CollectedEggMeta = setmetatable({}, {__mode = "k"})
local ConnectedEggPrompts = setmetatable({}, {__mode = "k"})
local InstantPromptConnections = setmetatable({}, {__mode = "k"})
local LiveEggCandidates = setmetatable({}, {__mode = "k"})
local WatchedPlots = setmetatable({}, {__mode = "k"})
local WatchedOwnerValues = setmetatable({}, {__mode = "k"})
local WatchedFloatingSigns = setmetatable({}, {__mode = "k"})

--// UI STATUS HOOKS
local PlotStatusCard = nil
local AutoStatusCard = nil
local TargetStatusCard = nil
local BackpackStatusCard = nil
local TreadmillStatusCard = nil
local GrowingEggStatusCard = nil
local HatchStatusCard = nil
local ProgressionStatusCard = nil

-- Forward-declared so the live first-egg scanner can immediately wake
-- Auto Hatch when Action changes to CLAIM.
local HatchSystem = nil

local function setPlotStatus(text)
    text = tostring(text or "")
    if PlotStatusCard then
        if State.StatusCache.Plot == text then return end
        State.StatusCache.Plot = text
        PlotStatusCard.SetText(text)
    else
        State.StatusCache.Plot = nil
    end
end

local function setAutoStatus(text)
    text = tostring(text or "")
    if AutoStatusCard then
        if State.StatusCache.Auto == text then return end
        State.StatusCache.Auto = text
        AutoStatusCard.SetText(text)
    else
        State.StatusCache.Auto = nil
    end
end

local function setTargetStatus(text)
    text = tostring(text or "")
    if TargetStatusCard then
        if State.StatusCache.Target == text then return end
        State.StatusCache.Target = text
        TargetStatusCard.SetText(text)
    else
        State.StatusCache.Target = nil
    end
end

local function setBackpackStatus(text)
    text = tostring(text or "")
    if BackpackStatusCard then
        if State.StatusCache.Backpack == text then return end
        State.StatusCache.Backpack = text
        BackpackStatusCard.SetText(text)
    else
        State.StatusCache.Backpack = nil
    end
end

local function setTreadmillStatus(text)
    text = tostring(text or "")
    if TreadmillStatusCard then
        if State.StatusCache.Treadmill == text then return end
        State.StatusCache.Treadmill = text
        TreadmillStatusCard.SetText(text)
    else
        State.StatusCache.Treadmill = nil
    end
end

local function setGrowingEggStatus(text)
    text = tostring(text or "")
    if GrowingEggStatusCard then
        if State.StatusCache.Growing == text then return end
        State.StatusCache.Growing = text
        GrowingEggStatusCard.SetText(text)
    else
        State.StatusCache.Growing = nil
    end
end

local function setHatchStatus(text)
    text = tostring(text or "")
    if HatchStatusCard then
        if State.StatusCache.Hatch == text then return end
        State.StatusCache.Hatch = text
        HatchStatusCard.SetText(text)
    else
        State.StatusCache.Hatch = nil
    end
end

local function setProgressionStatus(text)
    text = tostring(text or "")
    if ProgressionStatusCard then
        if State.StatusCache.Progression == text then return end
        State.StatusCache.Progression = text
        ProgressionStatusCard.SetText(text)
    else
        State.StatusCache.Progression = nil
    end
end

--// PLOT ESP
local MyPlotHighlight = nil

local function removePlotESP(model)
    local data = PlotTracked[model]
    if not data then return end

    if data.Highlight then
        data.Highlight:Destroy()
    end

    if data.Billboard then
        data.Billboard:Destroy()
    end

    PlotTracked[model] = nil
end

local function createPlotESP(model)
    if not State.PlotESP then return end
    if not model or not model:IsA("Model") then return end
    if PlotTracked[model] then return end

    local plot = getTopLevelPlot(model)
    if not plot or model == plot then return end

    -- Never scan eggs or models nested inside an egg.
    if isInsideEggModel(model) then return end

    local part = getObjectPart(model)
    if not part then return end

    local ownPlot = isMyPlot(plot)

    local highlight = Instance.new("Highlight")
    highlight.Name = ownPlot and "ZHM_MY_PLOT_ESP" or "ZHM_OTHER_PLOT_ESP"
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    if ownPlot then
        highlight.FillColor = Color3.fromRGB(255, 220, 0)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        highlight.FillTransparency = 0.30
        highlight.OutlineTransparency = 0
    else
        highlight.FillColor = Color3.fromRGB(70, 170, 255)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        highlight.FillTransparency = 0.82
        highlight.OutlineTransparency = 0.45
    end

    highlight.Enabled = State.PlotESP
    highlight.Parent = PlotScannerFolder

    local billboard = Instance.new("BillboardGui")
    billboard.Name = ownPlot and "ZHM_MyPlotName" or "ZHM_OtherPlotName"
    billboard.Adornee = part
    billboard.Size = ownPlot
        and UDim2.new(0, 280, 0, 65)
        or UDim2.new(0, 220, 0, 55)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = MAX_ESP_DISTANCE
    billboard.Enabled = State.PlotESP
    billboard.Parent = PlotScannerFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextWrapped = true
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0
    label.TextSize = ownPlot and 16 or 12
    label.TextColor3 = ownPlot
        and Color3.fromRGB(255, 235, 50)
        or Color3.fromRGB(220, 235, 255)
    label.Parent = billboard

    PlotTracked[model] = {
        Plot = plot,
        IsMine = ownPlot,
        Part = part,
        Highlight = highlight,
        Billboard = billboard,
        Label = label,
    }
end

local function refreshMyPlotHighlight()
    if MyPlotHighlight then
        MyPlotHighlight:Destroy()
        MyPlotHighlight = nil
    end

    if not State.PlotESP or not MyPlot or not MyPlot.Parent then
        return
    end

    local adornee = nil

    if MyPlot:IsA("Model") then
        adornee = MyPlot
    else
        adornee = MyPlot:FindFirstChild("PlotSurface", true)
            or MyPlot:FindFirstChildWhichIsA("BasePart", true)
    end

    if not adornee then return end

    MyPlotHighlight = Instance.new("Highlight")
    MyPlotHighlight.Name = "ZHM_MY_WHOLE_PLOT"
    MyPlotHighlight.Adornee = adornee
    MyPlotHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    MyPlotHighlight.FillColor = Color3.fromRGB(255, 220, 0)
    MyPlotHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    MyPlotHighlight.FillTransparency = 0.90
    MyPlotHighlight.OutlineTransparency = 0
    MyPlotHighlight.Enabled = State.PlotESP
    MyPlotHighlight.Parent = PlotScannerFolder
end

local function clearPlotESP()
    local keys = {}
    for model in pairs(PlotTracked) do
        table.insert(keys, model)
    end

    for _, model in ipairs(keys) do
        removePlotESP(model)
    end

    if MyPlotHighlight then
        MyPlotHighlight:Destroy()
        MyPlotHighlight = nil
    end
end

local function scanAllPlots()
    if not State.PlotESP then return end

    for _, plot in ipairs(PlotsFolder:GetChildren()) do
        for _, object in ipairs(plot:GetDescendants()) do
            if object:IsA("Model") and not isInsideEggModel(object) then
                createPlotESP(object)
            end
        end
    end
end

--// LIVE MY-PLOT DETECTION / OWNERSHIP WATCHER
local function refreshMyPlotLive(reason)
    if not RUNNING then return end

    local found = findMyPlot()

    if found ~= MyPlot then
        MyPlot = found
        clearPlotESP()

        if MyPlot then
            refreshMyPlotHighlight()
            scanAllPlots()
            setPlotStatus("Found: " .. MyPlot:GetFullName())
        else
            setPlotStatus("Searching for your plot...")
        end
    elseif MyPlot then
        -- Ownership may have become valid after a value/attribute changed.
        refreshMyPlotHighlight()
    end
end

local function queueMyPlotRefresh(reason)
    task.defer(function()
        task.wait(LIVE_EVENT_DELAY)
        refreshMyPlotLive(reason)
    end)
end

local function isOwnerValueCandidate(object)
    if not object then return false end

    if object:IsA("ObjectValue") then
        return true
    end

    local n = string.lower(object.Name)

    if object:IsA("StringValue") then
        return n == "owner" or n == "player" or n == "ownername"
    end

    if object:IsA("IntValue") or object:IsA("NumberValue") then
        return n == "userid" or n == "owneruserid" or n == "playeruserid"
    end

    return false
end

local function watchOwnerValue(object)
    if not isOwnerValueCandidate(object) or WatchedOwnerValues[object] then
        return
    end

    WatchedOwnerValues[object] = true
    bind(object.Changed, function()
        queueMyPlotRefresh("owner value changed")
    end)
end

local function watchFloatingSign(object)
    if not object or WatchedFloatingSigns[object] then return end

    local lowered = string.lower(object.Name)
    if not string.find(lowered, "floatingplotsign", 1, true) then
        return
    end

    WatchedFloatingSigns[object] = true
    bind(object:GetPropertyChangedSignal("Name"), function()
        queueMyPlotRefresh("floating sign renamed")
    end)
end

local function watchPlotOwnership(plot)
    if not plot or plot.Parent ~= PlotsFolder or WatchedPlots[plot] then
        return
    end

    WatchedPlots[plot] = true

    for _, attributeName in ipairs({
        "OwnerUserId", "UserId", "PlayerUserId",
        "Owner", "OwnerName", "PlayerName",
    }) do
        bind(plot:GetAttributeChangedSignal(attributeName), function()
            queueMyPlotRefresh("plot attribute changed")
        end)
    end

    for _, descendant in ipairs(plot:GetDescendants()) do
        watchOwnerValue(descendant)
        watchFloatingSign(descendant)
    end
end

for _, plot in ipairs(PlotsFolder:GetChildren()) do
    watchPlotOwnership(plot)
end

--// EGG COLLECTION DETECTION
local CollectionAttributeNames = {
    "Collected",
    "Claimed",
    "PickedUp",
    "Picked",
    "Taken",
    "Opened",
}

local function hasCollectedState(object)
    if not object then return false end

    for _, name in ipairs(CollectionAttributeNames) do
        if object:GetAttribute(name) == true then
            return true
        end
    end

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("BoolValue") then
            for _, name in ipairs(CollectionAttributeNames) do
                if string.lower(descendant.Name) == string.lower(name)
                    and descendant.Value == true then
                    return true
                end
            end
        end
    end

    return false
end

local function getEggPrompts(object)
    local prompts = {}

    if not object then
        return prompts
    end

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            table.insert(prompts, descendant)
        end
    end

    return prompts
end

local function getBestEggPrompt(object)
    local prompts = getEggPrompts(object)

    -- Prefer PickablePrompt / Pickup prompt from the observed game flow.
    for _, prompt in ipairs(prompts) do
        local n = string.lower(prompt.Name .. " " .. tostring(prompt.ActionText))
        if string.find(n, "pick", 1, true) or string.find(n, "pickup", 1, true) then
            return prompt
        end
    end

    return prompts[1]
end

local function hasActivePrompt(object)
    local prompts = getEggPrompts(object)

    if #prompts == 0 then
        return false, false
    end

    for _, prompt in ipairs(prompts) do
        if prompt.Enabled then
            return true, true
        end
    end

    return false, true
end

local function removeEggESP(object)
    local data = EggTracked[object]
    if not data then return end

    if data.Highlight then
        data.Highlight:Destroy()
    end

    if data.Billboard then
        data.Billboard:Destroy()
    end

    EggTracked[object] = nil
end

local function markCollected(object, reason)
    if not object or not getEggInfo(object) then
        return
    end

    if CollectedEggs[object] then
        return
    end

    local collectedPart = getObjectPart(object)
    local collectedPrompt = getBestEggPrompt(object)

    CollectedEggs[object] = true
    CollectedEggMeta[object] = {
        At = os.clock(),
        Parent = object.Parent,
        Position = collectedPart and collectedPart.Position or nil,
        Prompt = collectedPrompt,
    }

    removeEggESP(object)

    if State.CurrentTarget == object then
        setTargetStatus(
            cleanName(object.Name)
            .. " collected"
            .. (reason and (" - " .. reason) or "")
        )
    end
end

--// RECYCLED / RESPAWNED EGG RECOVERY
-- Some servers keep the same egg Model after pickup and later re-enable or
-- recreate its PickablePrompt. The old script kept CollectedEggs[egg] = true
-- forever, so that recycled egg could never be scanned again.
local function reviveEgg(object, reason)
    if not object or not object.Parent or isInsideAnyPlot(object) then
        return false
    end

    if not getEggInfo(object) then
        return false
    end

    CollectedEggs[object] = nil
    CollectedEggMeta[object] = nil

    local data = EggTracked[object]
    if data then
        data.PromptMissingSince = nil
        data.HadPrompt = #getEggPrompts(object) > 0
    end

    print(
        "[ZHM] Egg available again:",
        cleanName(object.Name),
        "|",
        reason or "live recovery"
    )

    return true
end

local function shouldReviveCollectedEgg(object)
    if not object or not CollectedEggs[object] or isInsideAnyPlot(object) then
        return false
    end

    local prompt = getBestEggPrompt(object)
    if not prompt or not prompt.Parent or not prompt.Enabled then
        return false
    end

    local meta = CollectedEggMeta[object]

    -- A new prompt instance is a strong signal that this egg was respawned.
    if meta and meta.Prompt and prompt ~= meta.Prompt then
        return true
    end

    -- Recycled egg model moved to a new spawn while keeping the same name/model.
    local part = getObjectPart(object)
    if meta and meta.Position and part then
        if (part.Position - meta.Position).Magnitude >= 4 then
            return true
        end
    end

    return false
end

--// PICKUP PROMPT NONSTOP FIRE
-- Only targets Pickup / Pickable prompts. Other proximity prompts are untouched.
State.PickupPromptSpam = {
    Watched = setmetatable({}, {__mode = "k"}),
    Delay = 0.05,
}

function State.PickupPromptSpam.IsPickup(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return false
    end

    local text = string.lower(
        tostring(prompt.Name or "")
        .. " "
        .. tostring(prompt.ActionText or "")
        .. " "
        .. tostring(prompt.ObjectText or "")
    )

    return string.find(text, "pickup", 1, true) ~= nil
        or string.find(text, "pick up", 1, true) ~= nil
        or string.find(text, "pickable", 1, true) ~= nil
end

function State.PickupPromptSpam.Watch(prompt)
    if not prompt
        or not prompt:IsA("ProximityPrompt")
        or State.PickupPromptSpam.Watched[prompt] then
        return
    end

    if not State.PickupPromptSpam.IsPickup(prompt) then
        return
    end

    State.PickupPromptSpam.Watched[prompt] = true

    -- RESTORED PICKUP METHOD:
    -- Keep the pickup/pickable prompt armed and spam only the LOCKED Auto Pickup
    -- target. This brings back the reliable old prompt-spam behavior without
    -- firing unrelated pickup prompts while Auto Pickup is OFF.
    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        if prompt.MaxActivationDistance < 20 then
            prompt.MaxActivationDistance = 20
        end
    end)

    task.spawn(function()
        while RUNNING and prompt and prompt.Parent do
            if State.AutoPickup
                and State.CurrentTarget ~= nil
                and prompt.Enabled
                and typeof(fireproximityprompt) == "function" then

                local promptEgg = findEggAncestor(prompt)

                if promptEgg == State.CurrentTarget then
                    pcall(function()
                        fireproximityprompt(prompt, 0)
                    end)
                end
            end

            task.wait(State.PickupPromptSpam.Delay)
        end

        State.PickupPromptSpam.Watched[prompt] = nil
    end)
end

--// INSTANT PROXIMITY
local function instantFire(prompt)
    if not prompt or not prompt.Parent then
        return false
    end

    if typeof(fireproximityprompt) ~= "function" then
        return false
    end

    local ok = pcall(function()
        fireproximityprompt(prompt, 0)
    end)

    return ok
end

local function connectInstantPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return
    end

    State.PickupPromptSpam.Watch(prompt)

    if InstantPromptConnections[prompt] then
        return
    end

    local connection = prompt.PromptButtonHoldBegan:Connect(function()
        if not RUNNING or not State.InstantProximity then
            return
        end

        if prompt.HoldDuration <= 0 then
            return
        end

        instantFire(prompt)
    end)

    InstantPromptConnections[prompt] = connection
    table.insert(Connections, connection)

    pcall(function()
        bind(prompt:GetPropertyChangedSignal("ActionText"), function()
            if RUNNING then
                State.PickupPromptSpam.Watch(prompt)
            end
        end)
    end)

    pcall(function()
        bind(prompt:GetPropertyChangedSignal("Name"), function()
            if RUNNING then
                State.PickupPromptSpam.Watch(prompt)
            end
        end)
    end)
end

local function connectAllInstantPrompts()
    local descendants = Workspace:GetDescendants()

    for index, object in ipairs(descendants) do
        if object:IsA("ProximityPrompt") then
            connectInstantPrompt(object)
        end

        -- Yield during the initial world pass so executing the hub does not
        -- produce one large frame hitch on maps with many instances.
        if index % 500 == 0 then
            task.wait()
        end
    end
end

--// EGG ESP
local function createEggESP(object)
    -- Egg ESP is hidden from this UI and OFF by default. Do not allocate
    -- Highlights/Billboards or update them unless the feature is explicitly ON.
    if not State.EggESP then return end
    if not object or not object.Parent then return end
    if EggTracked[object] then return end
    if CollectedEggs[object] then return end
    if isInsideAnyPlot(object) then return end

    local info = getEggInfo(object)
    if not info then return end

    local activePrompt = hasActivePrompt(object)

    -- If the server exposes an enabled pickup prompt, the egg is currently
    -- available even if an old Collected/Claimed value was not reset.
    if hasCollectedState(object) and not activePrompt then
        CollectedEggs[object] = true
        return
    end

    local part = getObjectPart(object)
    if not part then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ZHM_AreaEggHighlight"
    highlight.Adornee = object
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(255, 210, 45)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.70
    highlight.OutlineTransparency = 0
    highlight.Enabled = State.EggESP
    highlight.Parent = EggScannerFolder

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ZHM_AreaEggName"
    billboard.Adornee = part
    billboard.Size = UDim2.new(0, 250, 0, 90)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = MAX_ESP_DISTANCE
    billboard.Enabled = State.EggESP
    billboard.Parent = EggScannerFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextWrapped = true
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0
    label.Parent = billboard

    EggTracked[object] = {
        Part = part,
        Info = info,
        Highlight = highlight,
        Billboard = billboard,
        Label = label,
        HadPrompt = #getEggPrompts(object) > 0,
        PromptMissingSince = nil,
    }
end

local function connectEggPrompts(object)
    if not object or isInsideAnyPlot(object) then
        return
    end

    for _, prompt in ipairs(getEggPrompts(object)) do
        connectInstantPrompt(prompt)

        if not ConnectedEggPrompts[prompt] then
            ConnectedEggPrompts[prompt] = true

            bind(prompt.Triggered, function(triggeringPlayer)
                local egg = findEggAncestor(prompt)
                if egg and not isInsideAnyPlot(egg) then
                    local who = triggeringPlayer and triggeringPlayer.Name or "player"
                    markCollected(egg, "picked by " .. who)
                end
            end)

            bind(prompt:GetPropertyChangedSignal("Enabled"), function()
                local egg = findEggAncestor(prompt)

                if prompt.Enabled then
                    -- IMPORTANT: many eggs are recycled instead of destroyed.
                    -- When their prompt becomes enabled again, make the same
                    -- egg instance eligible for ESP/targeting immediately.
                    if egg and not isInsideAnyPlot(egg) then
                        if CollectedEggs[egg] then
                            reviveEgg(egg, "pickup prompt re-enabled")
                        end

                        task.defer(function()
                            task.wait(LIVE_EVENT_DELAY)
                            if RUNNING and egg.Parent then
                                createEggESP(egg)
                                connectEggPrompts(egg)
                            end
                        end)
                    end

                    return
                end

                if not egg or isInsideAnyPlot(egg) or CollectedEggs[egg] then
                    return
                end

                task.delay(0.35, function()
                    if not RUNNING
                        or not egg.Parent
                        or CollectedEggs[egg]
                        or isInsideAnyPlot(egg) then
                        return
                    end

                    local active, had = hasActivePrompt(egg)
                    if had and not active then
                        markCollected(egg, "pickup prompt disabled")
                    end
                end)
            end)
        end
    end
end

local function reconcileEgg(object)
    if not RUNNING or not object or not object.Parent then
        return
    end

    if not (object:IsA("Model") or object:IsA("BasePart")) then
        return
    end

    if not getEggInfo(object) then
        return
    end

    if isInsideAnyPlot(object) then
        -- Eggs placed in any player plot are never part of the world egg scanner.
        removeEggESP(object)
        return
    end

    if CollectedEggs[object] then
        if shouldReviveCollectedEgg(object) then
            reviveEgg(object, "recycled egg detected")
        else
            removeEggESP(object)
            return
        end
    end

    local activePrompt = hasActivePrompt(object)

    if hasCollectedState(object) and not activePrompt then
        markCollected(object, "server collection state")
        return
    end

    createEggESP(object)
    connectEggPrompts(object)
end

local function watchEggCandidate(object)
    if not object or LiveEggCandidates[object] then return end
    if not (object:IsA("Model") or object:IsA("BasePart")) then return end
    if not getEggInfo(object) then return end

    LiveEggCandidates[object] = true

    bind(object.AncestryChanged, function()
        task.defer(function()
            task.wait(LIVE_EVENT_DELAY)
            if RUNNING and object.Parent then
                reconcileEgg(object)
            else
                removeEggESP(object)
            end
        end)
    end)

    -- Some games recycle an egg instance by changing its name/type.
    bind(object:GetPropertyChangedSignal("Name"), function()
        task.defer(function()
            task.wait(LIVE_EVENT_DELAY)
            if not RUNNING then return end

            if getEggInfo(object) then
                CollectedEggs[object] = nil
                reconcileEgg(object)
            else
                removeEggESP(object)
            end
        end)
    end)
end

local function scanEggs()
    for _, object in ipairs(Workspace:GetDescendants()) do
        if (object:IsA("Model") or object:IsA("BasePart"))
            and getEggInfo(object) then

            -- If the game recycled an old egg instance and its pickup prompt is
            -- active again, immediately make it live instead of waiting for the
            -- slower recovery path.
            if CollectedEggs[object] and not isInsideAnyPlot(object) then
                local prompt = getBestEggPrompt(object)

                if prompt and prompt.Parent and prompt.Enabled then
                    reviveEgg(object, "live scanner active prompt")
                end
            end

            watchEggCandidate(object)
            reconcileEgg(object)
        end
    end
end

--// GLOBAL PICKUP DETECTION - YOUR PICKUP OR OTHER PLAYER PICKUP
bind(ProximityPromptService.PromptTriggered, function(prompt, triggeringPlayer)
    local egg = findEggAncestor(prompt)

    if egg and not isInsideAnyPlot(egg) then
        local who = triggeringPlayer and triggeringPlayer.Name or "player"
        markCollected(egg, "picked by " .. who)
    end
end)

--// LIVE WORKSPACE / PLOT CONNECTIONS
-- Workspace events catch brand-new instances. PlotsFolder events also catch
-- models that are re-parented between existing Workspace folders/plots.
bind(Workspace.DescendantAdded, function(object)
    if object:IsA("ProximityPrompt") then
        connectInstantPrompt(object)

        task.defer(function()
            task.wait(LIVE_EVENT_DELAY)
            if not RUNNING then return end

            local egg = findEggAncestor(object)
            if egg then
                -- If a collected/recycled egg receives a NEW enabled prompt,
                -- it is live again and must return to the scanner immediately.
                if CollectedEggs[egg] and object.Enabled then
                    local meta = CollectedEggMeta[egg]
                    if not meta or not meta.Prompt or object ~= meta.Prompt then
                        reviveEgg(egg, "new pickup prompt added")
                    end
                end

                watchEggCandidate(egg)
                reconcileEgg(egg)

                if EggTracked[egg] then
                    EggTracked[egg].HadPrompt = true
                end

                connectEggPrompts(egg)
            end
        end)

        return
    end

    if object:IsA("Model") or object:IsA("BasePart") then
        task.defer(function()
            task.wait(LIVE_EVENT_DELAY)
            if not RUNNING or not object.Parent then return end

            if getEggInfo(object) then
                -- A brand-new instance is eligible again even if the game reuses a name.
                CollectedEggs[object] = nil
                watchEggCandidate(object)
                reconcileEgg(object)
            end

            if object:IsA("Model") and isInsideAnyPlot(object) then
                createPlotESP(object)
            end
        end)
    end
end)

bind(Workspace.DescendantRemoving, function(object)
    if EggTracked[object] then
        removeEggESP(object)
    end

    if PlotTracked[object] then
        removePlotESP(object)
    end

    if object:IsA("ProximityPrompt") then
        local egg = findEggAncestor(object)

        if egg and EggTracked[egg] and not CollectedEggs[egg] then
            task.delay(0.25, function()
                if not RUNNING
                    or not egg.Parent
                    or CollectedEggs[egg]
                    or isInsideAnyPlot(egg) then
                    return
                end

                local active = hasActivePrompt(egg)
                if EggTracked[egg]
                    and EggTracked[egg].HadPrompt
                    and not active then
                    markCollected(egg, "pickup prompt removed")
                end
            end)
        end
    end
end)

-- Direct plot descendant events make Plot ESP truly live even when objects are
-- moved from one plot to another without ever leaving Workspace.
bind(PlotsFolder.DescendantAdded, function(object)
    if object:IsA("Model") then
        task.defer(function()
            task.wait(LIVE_EVENT_DELAY)
            if RUNNING and object.Parent then
                createPlotESP(object)
            end
        end)
    end

    if (object:IsA("Model") or object:IsA("BasePart")) and getEggInfo(object) then
        watchEggCandidate(object)
        task.defer(function()
            task.wait(LIVE_EVENT_DELAY)
            if RUNNING and object.Parent then
                reconcileEgg(object)
            end
        end)
    end

    local ownerRelevant = isOwnerValueCandidate(object)
        or string.find(string.lower(object.Name), "floatingplotsign", 1, true) ~= nil

    watchOwnerValue(object)
    watchFloatingSign(object)

    if ownerRelevant then
        queueMyPlotRefresh("plot ownership descendant added")
    end
end)

bind(PlotsFolder.DescendantRemoving, function(object)
    if PlotTracked[object] then
        removePlotESP(object)
    end

    if getEggInfo(object) then
        task.defer(function()
            task.wait(LIVE_EVENT_DELAY)
            if RUNNING and object.Parent and object:IsDescendantOf(Workspace) then
                watchEggCandidate(object)
                reconcileEgg(object)
            end
        end)
    end

    local ownerRelevant = isOwnerValueCandidate(object)
        or string.find(string.lower(object.Name), "floatingplotsign", 1, true) ~= nil

    if ownerRelevant then
        queueMyPlotRefresh("plot ownership descendant removed")
    end
end)

bind(PlotsFolder.ChildAdded, function(plot)
    watchPlotOwnership(plot)
    queueMyPlotRefresh("plot added")

    task.defer(function()
        task.wait(LIVE_EVENT_DELAY)
        if RUNNING then
            scanAllPlots()
        end
    end)
end)

bind(PlotsFolder.ChildRemoved, function()
    queueMyPlotRefresh("plot removed")
end)

--// AUTO EGG TARGETING
local function getSelectedCount()
    local count = 0
    for _, selected in pairs(State.SelectedEggs) do
        if selected then
            count += 1
        end
    end
    return count
end

local function isSelectedEgg(egg)
    local info = getEggInfo(egg)
    return info and State.SelectedEggs[info.EggName] == true
end

local function getNearestSelectedEgg()
    local root = getCharacterRoot()
    local origin = root and root.Position or nil

    local bestEgg = nil
    local bestDistance = math.huge

    -- Targeting is intentionally independent from Egg ESP. Even if ESP was
    -- temporarily recreated/removed, the live candidate registry still sees it.
    for egg in pairs(LiveEggCandidates) do
        if egg
            and egg.Parent
            and egg:IsDescendantOf(Workspace)
            and not isInsideAnyPlot(egg)
            and isSelectedEgg(egg) then

            if CollectedEggs[egg] and shouldReviveCollectedEgg(egg) then
                reviveEgg(egg, "target scanner detected recycled egg")
                reconcileEgg(egg)
            end

            if not CollectedEggs[egg] then
                local part = getObjectPart(egg)
                local prompt = getBestEggPrompt(egg)

                if part and prompt and prompt.Parent and prompt.Enabled then
                    -- Rebuild internal tracking if an egg is available but its
                    -- ESP/tracker was removed by an earlier recycle event.
                    if not EggTracked[egg] then
                        reconcileEgg(egg)
                    end

                    local distance = origin
                        and (part.Position - origin).Magnitude
                        or 0

                    if distance < bestDistance then
                        bestDistance = distance
                        bestEgg = egg
                    end
                end
            end
        end
    end

    return bestEgg, bestDistance
end

local function triggerEggPickup(egg)
    if not egg or not egg.Parent or CollectedEggs[egg] then
        return false
    end

    local deadline = os.clock() + AUTO_PICKUP_TIMEOUT
    local lastTpAt = 0
    local arrivedAt = nil

    local function finishAtEgg(result)
        if arrivedAt then
            local remaining = (arrivedAt + EGG_STAY_TIME) - os.clock()
            if remaining > 0 then
                task.wait(remaining)
            end
        end
        return result
    end

    while RUNNING
        and State.AutoPickup
        and State.CurrentTarget == egg
        and os.clock() < deadline do

        if not egg.Parent or not egg:IsDescendantOf(Workspace) then
            return finishAtEgg(true)
        end

        if CollectedEggs[egg] then
            return finishAtEgg(true)
        end

        if hasCollectedState(egg) then
            markCollected(egg, "collection state")
            return finishAtEgg(true)
        end

        -- Re-acquire every loop because some eggs replace/rebuild the prompt.
        local prompt = getBestEggPrompt(egg)

        if not prompt or not prompt.Parent then
            task.wait(0.03)
            continue
        end

        -- Find the exact BasePart that owns the ProximityPrompt.
        local promptPart = prompt.Parent
        while promptPart
            and promptPart ~= egg
            and not promptPart:IsA("BasePart") do
            promptPart = promptPart.Parent
        end

        if not promptPart or not promptPart:IsA("BasePart") then
            promptPart = getObjectPart(egg)
        end

        if not promptPart then
            task.wait(0.03)
            continue
        end

        -- Make this specific pickup prompt easy to trigger.
        pcall(function()
            prompt.HoldDuration = 0
            prompt.RequiresLineOfSight = false

            if prompt.MaxActivationDistance < 20 then
                prompt.MaxActivationDistance = 20
            end
        end)

        -- Keep snapping to the SAME target so physics / other scripts cannot
        -- drift the player away before the pickup registers.
        local now = os.clock()
        if now - lastTpAt >= 0.07 then
            local targetCF = promptPart.CFrame * CFrame.new(0, 2.2, 0)
            tpToCFrame(targetCF)
            lastTpAt = now

            -- Start the fixed stay timer on the FIRST successful TP to the egg.
            -- Keep the player locked here for 0.50s while the old prompt-spam
            -- pickup method runs, then the main cycle returns to the plot fast.
            if not arrivedAt then
                arrivedAt = os.clock()
                deadline = math.min(deadline, arrivedAt + EGG_STAY_TIME)
            end
        end

        -- Pickup firing is handled by PickupPromptSpam.Watch().
        -- Do not double-fire here; the restored 0.05s target-locked spam loop
        -- owns prompt activation while Auto Pickup is running.

        -- Strong pickup confirmation checks.
        if CollectedEggs[egg] or not egg:IsDescendantOf(Workspace) then
            return finishAtEgg(true)
        end

        if hasCollectedState(egg) then
            markCollected(egg, "collection state")
            return finishAtEgg(true)
        end

        local active, had = hasActivePrompt(egg)
        if had and not active then
            markCollected(egg, "pickup prompt unavailable")
            return finishAtEgg(true)
        end

        task.wait(0.04)
    end

    return finishAtEgg(
        CollectedEggs[egg] == true
        or not egg.Parent
        or not egg:IsDescendantOf(Workspace)
    )
end

local function returnToMyPlot()
    local returnCF = getMyPlotReturnCFrame()

    if not returnCF then
        setAutoStatus("Could not find your PlotSurface.")
        return false
    end

    local ok = tpToCFrame(returnCF)

    if ok then
        setAutoStatus("Returned to your plot.")

        -- Do not wait for the 3-second fallback. Refresh the live egg registry
        -- immediately after every pickup/return cycle.
        task.defer(function()
            task.wait(0.08)
            if RUNNING then
                scanEggs()

                for egg in pairs(LiveEggCandidates) do
                    if egg and egg.Parent and egg:IsDescendantOf(Workspace) then
                        reconcileEgg(egg)
                    end
                end
            end
        end)
    end

    return ok
end

--// LIVE BACKPACK INVENTORY SCANNER + AUTO BUY / BEST AUTO EQUIP TREADMILL
-- IMPORTANT: kept inside ONE table to avoid Luau's 200-local register limit.
local Treadmill = {}

Treadmill.InventoryBoundContainers = setmetatable({}, {__mode = "k"})
Treadmill.LastInventorySignature = ""
Treadmill.CachedTool = nil
Treadmill.BuyRemoteCache = nil
Treadmill.EquipRemoteCache = nil
Treadmill.ClaimBonusRemoteCache = nil
Treadmill.Buying = false
Treadmill.ClaimingBonus = false
Treadmill.ScanQueued = false
Treadmill.LiveState = nil

-- Known treadmill payloads.
-- The ActionLogs confirmed BuyTrainTool accepts the payload ID directly.
-- New treadmill IDs discovered by the live payload scanner are appended automatically.
-- Last rank is treated as the newest/best discovered tier for Auto Equip.
Treadmill.Tiers = {
    {Id = "golden_treadmill",   Rank = 1,  Label = "Golden Treadmill"},
    {Id = "diamond_treadmill",  Rank = 2,  Label = "Diamond Treadmill"},
    {Id = "devil_treadmill",    Rank = 3,  Label = "Devil Treadmill"},
    {Id = "desert_treadmill",   Rank = 4,  Label = "Desert Treadmill"},
    {Id = "aqua_treadmill",     Rank = 5,  Label = "Aqua Treadmill"},
    {Id = "lava_treadmill",     Rank = 6,  Label = "Lava Treadmill"},

    -- Confirmed by ActionLogs(9).txt.
    {Id = "galaxy_treadmill",   Rank = 7,  Label = "Galaxy Treadmill"},
    {Id = "jurassic_treadmill", Rank = 8,  Label = "Jurassic Treadmill"},
    {Id = "frozen_treadmill",   Rank = 9,  Label = "Frozen Treadmill"},
    {Id = "sakura_treadmill",   Rank = 10, Label = "Sakura Treadmill"},
    {Id = "hacked_treadmill",   Rank = 11, Label = "Hacked Treadmill"},
    {Id = "balrog_treadmill",   Rank = 12, Label = "Balrog Treadmill"},
    {Id = "magia_treadmill",    Rank = 13, Label = "Magia Treadmill"},
    {Id = "dojo_treadmill",     Rank = 14, Label = "Dojo Treadmill"},
    {Id = "void_treadmill",     Rank = 15, Label = "Void Treadmill"},
}

Treadmill.ById = {}
for _, tier in ipairs(Treadmill.Tiers) do
    Treadmill.ById[tier.Id] = tier
end

-- Dynamic payload scanner state.
Treadmill.PayloadScanQueued = false
Treadmill.PayloadScannerStarted = false
Treadmill.PayloadSources = {}
Treadmill.LastPayloadSignature = ""
Treadmill.PayloadFallbackRate = 60 -- full fallback scan is rare; live events do the normal work
Treadmill.BuyRetryAt = {}
Treadmill.BuyRetryDelay = 6.0
Treadmill.BuyAcceptedCooldown = 15.0
Treadmill.MaxAutoBuysPerPass = 3

local function treadmillPayloadLabel(id)
    local base = tostring(id or ""):gsub("_treadmill$", "")
    base = base:gsub("_", " ")

    local words = {}
    for word in base:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
    end

    local label = table.concat(words, " ")
    if label == "" then
        label = tostring(id or "Unknown")
    end

    return label .. " Treadmill"
end

function Treadmill.RegisterPayload(rawValue, source)
    local id = string.lower(tostring(rawValue or ""))
    id = id:gsub("%(clone%)", "")
    id = id:gsub("[%s%-]+", "_")
    id = id:gsub("[^%w_]", "")
    id = id:gsub("_+", "_")
    id = id:gsub("^_+", "")
    id = id:gsub("_+$", "")

    -- BuyTrainTool payloads observed in the logs use <name>_treadmill.
    if id == "" or not id:match("^[%w_]+_treadmill$") then
        return false
    end

    -- Ignore generic/basic names as dynamic "new" tiers.
    if id == "treadmill" or id == "basic_treadmill" then
        return false
    end

    if Treadmill.ById[id] then
        if source then
            Treadmill.PayloadSources[id] = Treadmill.PayloadSources[id] or tostring(source)
        end
        return false
    end

    local tier = {
        Id = id,
        Rank = #Treadmill.Tiers + 1,
        Label = treadmillPayloadLabel(id),
        Dynamic = true,
    }

    table.insert(Treadmill.Tiers, tier)
    Treadmill.ById[id] = tier
    Treadmill.PayloadSources[id] = tostring(source or "live scanner")

    print(
        "[ZHM] NEW TREADMILL PAYLOAD DETECTED:",
        id,
        "| source:",
        tostring(source or "live scanner")
    )

    return true
end

function Treadmill.LearnPayloadFromObject(object)
    if not object then
        return false
    end

    -- LOW-LAG FILTER:
    -- Most game instances have nothing to do with treadmills. Do cheap string
    -- checks first and only inspect attributes for plausible config objects.
    local changed = false
    local objectName = tostring(object.Name or "")
    local lowerName = string.lower(objectName)
    local nameLooksRelevant = string.find(lowerName, "treadmill", 1, true) ~= nil
        or string.find(lowerName, "train", 1, true) ~= nil

    if nameLooksRelevant then
        if Treadmill.RegisterPayload(objectName, objectName) then
            changed = true
        end
    end

    if object:IsA("StringValue") then
        local value = tostring(object.Value or "")
        if string.find(string.lower(value), "treadmill", 1, true)
            and Treadmill.RegisterPayload(value, objectName .. ".Value") then
            changed = true
        end
    end

    -- Attribute discovery is useful for generic config entries, but doing nine
    -- GetAttribute calls on every Workspace object was expensive. Inspect all
    -- attributes once only for likely config/value objects or ReplicatedStorage.
    local inspectAttributes = nameLooksRelevant
        or object:IsA("ValueBase")
        or object:IsDescendantOf(ReplicatedStorage)

    if inspectAttributes then
        local ok, attributes = pcall(function()
            return object:GetAttributes()
        end)

        if ok and attributes then
            for attributeName, value in pairs(attributes) do
                if type(value) == "string" then
                    local lowerAttribute = string.lower(tostring(attributeName))
                    local lowerValue = string.lower(value)

                    if (string.find(lowerAttribute, "id", 1, true)
                        or string.find(lowerAttribute, "tool", 1, true)
                        or string.find(lowerAttribute, "treadmill", 1, true))
                        and string.find(lowerValue, "treadmill", 1, true)
                        and Treadmill.RegisterPayload(
                            value,
                            objectName .. "@" .. tostring(attributeName)
                        ) then

                        changed = true
                    end
                end
            end
        end
    end

    return changed
end

function Treadmill.ScanPayloads()
    local changed = false

    -- LOW-LAG DISCOVERY:
    -- Treadmill/config assets are expected in ReplicatedStorage. Do NOT full-scan
    -- Workspace every fallback cycle. Workspace additions are handled live by
    -- DescendantAdded below, while Backpack/Character are tiny and cheap to scan.
    local roots = {ReplicatedStorage}
    local backpack = player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
    if backpack then table.insert(roots, backpack) end
    if player.Character then table.insert(roots, player.Character) end

    for _, location in ipairs(roots) do
        for _, object in ipairs(location:GetDescendants()) do
            if Treadmill.LearnPayloadFromObject(object) then
                changed = true
            end
        end
    end

    local ids = {}
    for _, tier in ipairs(Treadmill.Tiers) do
        table.insert(ids, tier.Id)
    end

    local signature = table.concat(ids, "|")
    local signatureChanged = signature ~= Treadmill.LastPayloadSignature
    Treadmill.LastPayloadSignature = signature

    return changed or signatureChanged
end

function Treadmill.GetPayloadTiers()
    local payloads = {}
    for _, tier in ipairs(Treadmill.Tiers) do
        if tier and tier.Id and tier.Id:match("^[%w_]+_treadmill$") then
            table.insert(payloads, tier)
        end
    end
    return payloads
end

function Treadmill.QueuePayloadScan()
    if Treadmill.PayloadScanQueued then
        return
    end

    Treadmill.PayloadScanQueued = true
    task.defer(function()
        task.wait(0.08)
        Treadmill.PayloadScanQueued = false

        if not RUNNING then
            return
        end

        -- The DescendantAdded handler already learned the new payload. Avoid a
        -- second full ReplicatedStorage/Workspace scan here.
        Treadmill.UpdateScanner()

        -- Newly discovered payloads can be tried immediately. RunBuyPass has
        -- per-payload cooldowns, so bursts of new instances cannot spam remotes.
        if State.AutoBuyTreadmill
            and not Treadmill.Buying
            and Treadmill.RunBuyPass then

            task.defer(function()
                task.wait(0.05)
                if RUNNING and State.AutoBuyTreadmill and not Treadmill.Buying then
                    Treadmill.RunBuyPass(false)
                end
            end)
        end
    end)
end

function Treadmill.StartPayloadScanner()
    if Treadmill.PayloadScannerStarted then
        return
    end
    Treadmill.PayloadScannerStarted = true

    -- One initial discovery pass. Normal updates after this are event-driven.
    Treadmill.ScanPayloads()

    bind(ReplicatedStorage.DescendantAdded, function(object)
        if Treadmill.LearnPayloadFromObject(object) then
            Treadmill.QueuePayloadScan()
        end
    end)

    -- Workspace can be extremely active. Learn only from the single new object;
    -- never rescan all of Workspace because one instance was added.
    bind(Workspace.DescendantAdded, function(object)
        if Treadmill.LearnPayloadFromObject(object) then
            Treadmill.QueuePayloadScan()
        end
    end)

    -- Rare safety fallback for renamed/changed config values that do not create
    -- new instances. It scans ReplicatedStorage + tiny player containers only.
    task.spawn(function()
        while RUNNING do
            task.wait(Treadmill.PayloadFallbackRate)
            if RUNNING and Treadmill.ScanPayloads() then
                Treadmill.UpdateScanner()
            end
        end
    end)
end

function Treadmill.Normalize(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("%(clone%)", "")
    value = value:gsub("[%s%-]+", "_")
    value = value:gsub("[^%w_]", "")
    value = value:gsub("_+", "_")
    value = value:gsub("^_+", "")
    value = value:gsub("_+$", "")

    for _, tier in ipairs(Treadmill.Tiers) do
        local token = tier.Id:gsub("_treadmill$", "")
        if value == tier.Id
            or (string.find(value, token, 1, true)
                and string.find(value, "treadmill", 1, true)) then
            return tier.Id
        end
    end

    return value
end

function Treadmill.IsTool(object)
    if not object or not object:IsA("Tool") then
        return false
    end

    local id = Treadmill.Normalize(object.Name)
    return id == "treadmill"
        or id == "basic_treadmill"
        or Treadmill.ById[id] ~= nil
        or string.find(id, "treadmill", 1, true) ~= nil
end

function Treadmill.GetBackpack()
    return player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
end

function Treadmill.CollectTools()
    local tools = {}
    local seen = {}

    local function addContainer(container, location)
        if not container then return end
        for _, object in ipairs(container:GetChildren()) do
            if object:IsA("Tool") and not seen[object] then
                seen[object] = true
                table.insert(tools, {
                    Tool = object,
                    Name = object.Name,
                    Location = location,
                })
            end
        end
    end

    addContainer(Treadmill.GetBackpack(), "Backpack")
    addContainer(player.Character, "Equipped")

    table.sort(tools, function(a, b)
        return string.lower(a.Name) < string.lower(b.Name)
    end)

    return tools
end

function Treadmill.Rank(name)
    local id = Treadmill.Normalize(name)
    local tier = Treadmill.ById[id]

    if tier then
        return tier.Rank, tier
    end

    if id == "treadmill"
        or id == "basic_treadmill"
        or string.find(id, "treadmill", 1, true) then
        return 0, {Id = id, Rank = 0, Label = tostring(name)}
    end

    return -1, nil
end

function Treadmill.FindBest()
    local tools = Treadmill.CollectTools()
    local bestEntry = nil
    local bestTier = nil
    local bestRank = -1

    for _, entry in ipairs(tools) do
        if Treadmill.IsTool(entry.Tool) then
            local rank, tier = Treadmill.Rank(entry.Name)
            if rank > bestRank then
                bestRank = rank
                bestEntry = entry
                bestTier = tier
            end
        end
    end

    if bestEntry then
        return bestEntry.Tool, bestEntry.Location, tools, bestTier
    end

    return nil, nil, tools, nil
end

function Treadmill.BuildLiveState()
    local tools = Treadmill.CollectTools()
    local ownedById = {}
    local ownedLabels = {}
    local bestEntry = nil
    local bestTier = nil
    local bestRank = -1
    local equippedTier = nil
    local equippedRank = -1

    for _, entry in ipairs(tools) do
        if Treadmill.IsTool(entry.Tool) then
            local rank, tier = Treadmill.Rank(entry.Name)

            if tier and rank >= 0 then
                if tier.Id and Treadmill.ById[tier.Id] then
                    ownedById[tier.Id] = true
                end

                if rank > bestRank then
                    bestRank = rank
                    bestTier = tier
                    bestEntry = entry
                end

                if entry.Location == "Equipped" and rank > equippedRank then
                    equippedRank = rank
                    equippedTier = tier
                end
            end
        end
    end

    for _, tier in ipairs(Treadmill.Tiers) do
        if ownedById[tier.Id] then
            table.insert(ownedLabels, tier.Label)
        end
    end

    local nextTier = nil

    -- Find the first detected payload that is not currently owned.
    -- This works even when the game adds a new treadmill dynamically.
    for _, tier in ipairs(Treadmill.Tiers) do
        if not ownedById[tier.Id] then
            nextTier = tier
            break
        end
    end

    local live = {
        Tools = tools,
        OwnedById = ownedById,
        OwnedLabels = ownedLabels,
        BestEntry = bestEntry,
        BestTier = bestTier,
        BestRank = bestRank,
        EquippedTier = equippedTier,
        EquippedRank = equippedRank,
        NextTier = nextTier,
    }

    Treadmill.LiveState = live
    return live
end

function Treadmill.UpdateScanner()
    local live = Treadmill.BuildLiveState()
    local treadmill = live.BestEntry and live.BestEntry.Tool or nil
    local location = live.BestEntry and live.BestEntry.Location or nil
    local tier = live.BestTier

    Treadmill.CachedTool = treadmill

    local names = {}
    for _, entry in ipairs(live.Tools) do
        table.insert(names, entry.Name)
    end

    Treadmill.LastInventorySignature =
        table.concat(names, "|")
        .. "|"
        .. tostring(location or "")
        .. "|"
        .. tostring(live.EquippedTier and live.EquippedTier.Id or "")

    local inventoryText = #names > 0 and table.concat(names, ", ") or "No tools"

    if treadmill then
        setBackpackStatus(string.format(
            "Best Treadmill: %s (%s)\nTools: %s",
            tier and tier.Label or treadmill.Name,
            location or "Found",
            inventoryText
        ))
    else
        setBackpackStatus("Best Treadmill: NOT FOUND\nTools: " .. inventoryText)
    end

    local ownedText = #live.OwnedLabels > 0
        and table.concat(live.OwnedLabels, ", ")
        or "None"

    local bestText = live.BestTier and live.BestTier.Label or "None"
    local equippedText = live.EquippedTier and live.EquippedTier.Label or "None"
    local nextText = live.NextTier and live.NextTier.Label or "All detected tiers owned"

    local buyReady = Treadmill.FindBuyRemote() and "READY" or "NOT FOUND"
    local equipReady = Treadmill.FindEquipRemote() and "READY" or "NOT FOUND"

    setTreadmillStatus(
        "Owned: "
        .. ownedText
        .. "\nBest: "
        .. bestText
        .. " | Equipped: "
        .. equippedText
        .. "\nPayloads: "
        .. tostring(#Treadmill.Tiers)
        .. " detected | Next Buy: "
        .. nextText
        .. " | Buy RF: "
        .. buyReady
        .. " | Equip RF: "
        .. equipReady
    )

    return treadmill, location, tier, live
end

function Treadmill.QueueScan()
    if Treadmill.ScanQueued then
        return
    end

    Treadmill.ScanQueued = true

    task.defer(function()
        task.wait(0.06)

        if not RUNNING then
            Treadmill.ScanQueued = false
            return
        end

        Treadmill.UpdateScanner()
        Treadmill.ScanQueued = false

        if State.AutoEquipTreadmill
            and not State.PlacingEggs
            and not State.HatchingEggs
            and State.CurrentTarget == nil then

            local live = Treadmill.LiveState
            local best = live and live.BestTier
            local equipped = live and live.EquippedTier

            if best and (not equipped or best.Rank > equipped.Rank) then
                task.defer(function()
                    task.wait(0.03)
                    if RUNNING and State.AutoEquipTreadmill then
                        Treadmill.EquipBest()
                    end
                end)
            end
        end
    end)
end

function Treadmill.BindContainer(container)
    if not container or Treadmill.InventoryBoundContainers[container] then
        return
    end

    Treadmill.InventoryBoundContainers[container] = true

    bind(container.ChildAdded, function(object)
        if object:IsA("Tool") then
            Treadmill.QueueScan()
        end
    end)

    bind(container.ChildRemoved, function(object)
        if object:IsA("Tool") then
            Treadmill.QueueScan()
        end
    end)
end

function Treadmill.BindScanner()
    local backpack = Treadmill.GetBackpack()
    if backpack then
        Treadmill.BindContainer(backpack)
    end

    if player.Character then
        Treadmill.BindContainer(player.Character)
    end

    bind(player.ChildAdded, function(object)
        if object:IsA("Backpack") or object.Name == "Backpack" then
            Treadmill.BindContainer(object)
            Treadmill.QueueScan()
        end
    end)

    bind(player.CharacterAdded, function(character)
        Treadmill.BindContainer(character)
        task.defer(function()
            task.wait(0.15)
            if RUNNING then
                local backpackNow = Treadmill.GetBackpack()
                if backpackNow then
                    Treadmill.BindContainer(backpackNow)
                end
                Treadmill.UpdateScanner()
            end
        end)
    end)

    Treadmill.UpdateScanner()
end

function Treadmill.HasAncestorNamed(object, targetName)
    local current = object
    while current and current ~= ReplicatedStorage do
        if current.Name == targetName then
            return true
        end
        current = current.Parent
    end
    return false
end

function Treadmill.FindTrainingRemote(remoteName)
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return nil
    end

    for _, object in ipairs(packages:GetDescendants()) do
        if object:IsA("RemoteFunction")
            and object.Name == remoteName
            and object.Parent
            and object.Parent.Name == "RF"
            and Treadmill.HasAncestorNamed(object, "TrainingService") then
            return object
        end
    end

    return nil
end

function Treadmill.FindBuyRemote()
    if Treadmill.BuyRemoteCache and Treadmill.BuyRemoteCache.Parent then
        return Treadmill.BuyRemoteCache
    end
    Treadmill.BuyRemoteCache = Treadmill.FindTrainingRemote("BuyTrainTool")
    return Treadmill.BuyRemoteCache
end

function Treadmill.FindEquipRemote()
    if Treadmill.EquipRemoteCache and Treadmill.EquipRemoteCache.Parent then
        return Treadmill.EquipRemoteCache
    end
    Treadmill.EquipRemoteCache = Treadmill.FindTrainingRemote("EquipTrainTool")
    return Treadmill.EquipRemoteCache
end

function Treadmill.FindClaimBonusRemote()
    if Treadmill.ClaimBonusRemoteCache and Treadmill.ClaimBonusRemoteCache.Parent then
        return Treadmill.ClaimBonusRemoteCache
    end

    Treadmill.ClaimBonusRemoteCache = Treadmill.FindTrainingRemote("ClaimBonus")
    return Treadmill.ClaimBonusRemoteCache
end

-- Exact x2 training-bonus button path from the provided working script:
-- PlayerGui.SpeedEffect.LeftContainer.Currency.Speed.x2Speed.Button
-- IMPORTANT: this does NOT force any GUI visible and does NOT use firesignal().
function Treadmill.GetBonusButton()
    local speedEffect = playerGui:FindFirstChild("SpeedEffect")
    local leftContainer = speedEffect and speedEffect:FindFirstChild("LeftContainer")
    local currency = leftContainer and leftContainer:FindFirstChild("Currency")
    local speed = currency and currency:FindFirstChild("Speed")
    local x2Speed = speed and speed:FindFirstChild("x2Speed")
    local button = x2Speed and x2Speed:FindFirstChild("Button")

    if button and button:IsA("GuiButton") then
        return button
    end

    return nil
end

function Treadmill.IsBonusButtonVisible(button)
    if not button or not button.Parent or not button.Visible then
        return false
    end

    if button.AbsoluteSize.X <= 0 or button.AbsoluteSize.Y <= 0 then
        return false
    end

    local current = button.Parent
    while current and current ~= playerGui do
        if current:IsA("GuiObject") and current.Visible == false then
            return false
        end

        if current:IsA("LayerCollector") and current.Enabled == false then
            return false
        end

        current = current.Parent
    end

    return true
end

function Treadmill.ClickBonusButton(button)
    if not Treadmill.IsBonusButtonVisible(button) then
        return false
    end

    local position = button.AbsolutePosition
    local size = button.AbsoluteSize
    local x = position.X + (size.X / 2)
    local y = position.Y + (size.Y / 2)

    local ok = pcall(function()
        VirtualInputManager:SendMouseMoveEvent(x, y, game)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)

    return ok
end

function Treadmill.RemoteClaimBonus()
    local remote = Treadmill.FindClaimBonusRemote()
    if not remote then
        return false, "ClaimBonus remote not found"
    end

    local ok, result = pcall(function()
        return remote:InvokeServer()
    end)

    if not ok then
        Treadmill.ClaimBonusRemoteCache = nil
        return false, tostring(result)
    end

    if result == false then
        return false, "server returned false"
    end

    return true, result
end

function Treadmill.ClaimBonus(force)
    if not RUNNING or Treadmill.ClaimingBonus then
        return false
    end

    if not force and not State.AutoClaimTrainingBonus then
        return false
    end

    Treadmill.ClaimingBonus = true

    -- Preferred method: click the exact visible x2 bonus button like the
    -- supplied fixed standalone script. We never show/open the UI ourselves.
    local button = Treadmill.GetBonusButton()
    local success = false
    local method = nil
    local detail = nil

    if button and Treadmill.IsBonusButtonVisible(button) then
        success = Treadmill.ClickBonusButton(button)
        if success then
            method = "x2 button"
        end
    end

    -- Fallback: exact TrainingService.RF.ClaimBonus:InvokeServer().
    -- This is used when the button is hidden/unavailable or physical click fails.
    if not success then
        success, detail = Treadmill.RemoteClaimBonus()
        if success then
            method = "ClaimBonus remote"
        end
    end

    Treadmill.ClaimingBonus = false

    if force then
        if success then
            setAutoStatus("Training bonus claimed via " .. tostring(method) .. ".")
        else
            setAutoStatus("Training bonus unavailable: " .. tostring(detail or "not claimable yet"))
        end
    end

    return success
end

function Treadmill.BuyTier(tierId)
    local remote = Treadmill.FindBuyRemote()
    if not remote then
        return false
    end

    local ok, result = pcall(function()
        return remote:InvokeServer(tierId)
    end)

    if not ok then
        Treadmill.BuyRemoteCache = nil
        return false
    end

    return result ~= false
end

function Treadmill.EquipTier(tierId)
    local remote = Treadmill.FindEquipRemote()
    if not remote then
        return false
    end

    local ok, result = pcall(function()
        return remote:InvokeServer(tierId)
    end)

    if not ok then
        Treadmill.EquipRemoteCache = nil
        return false
    end

    return result ~= false
end

function Treadmill.EquipBest()
    if not RUNNING or not State.AutoEquipTreadmill then
        return false
    end

    if State.PlacingEggs
        or State.HatchingEggs
        or State.CurrentTarget ~= nil then
        return false
    end

    local tool, location, _, tier = Treadmill.FindBest()

    if not tool or not tier then
        setAutoStatus("No treadmill detected in Backpack/Character.")
        return false
    end

    local character = player.Character
    if not character then
        return false
    end

    if tool.Parent == character then
        return true
    end

    local label = tier.Label or tool.Name
    setAutoStatus("Equipping best treadmill: " .. tostring(label))

    ------------------------------------------------------------
    -- METHOD 1: physical Tool equip first.
    ------------------------------------------------------------
    local backpack = Treadmill.GetBackpack()
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid and backpack and tool.Parent == backpack then
        pcall(function()
            humanoid:UnequipTools()
        end)

        task.wait(0.03)

        pcall(function()
            humanoid:EquipTool(tool)
        end)

        task.wait(0.08)

        if tool.Parent == character then
            Treadmill.UpdateScanner()
            setAutoStatus("Best treadmill equipped: " .. tostring(label))
            return true
        end
    end

    ------------------------------------------------------------
    -- METHOD 2: EquipTrainTool remote fallback.
    ------------------------------------------------------------
    if tier.Rank > 0
        and Treadmill.ById[tier.Id]
        and Treadmill.EquipTier(tier.Id) then

        task.wait(0.10)

        local rescannedTool, rescannedLocation = Treadmill.FindBest()

        if rescannedTool and rescannedLocation == "Equipped" then
            Treadmill.UpdateScanner()
            setAutoStatus("Best treadmill equipped: " .. tostring(label))
            return true
        end

        if rescannedTool
            and rescannedTool.Parent == Treadmill.GetBackpack()
            and humanoid then

            pcall(function()
                humanoid:UnequipTools()
                humanoid:EquipTool(rescannedTool)
            end)

            task.wait(0.08)

            if rescannedTool.Parent == character then
                Treadmill.UpdateScanner()
                setAutoStatus("Best treadmill equipped: " .. tostring(label))
                return true
            end
        end
    end

    Treadmill.UpdateScanner()
    setAutoStatus("Treadmill detected but equip failed; retrying automatically.")
    return false
end

function Treadmill.RunBuyPass(force)
    if Treadmill.Buying or not RUNNING then
        return false
    end

    if not force and not State.AutoBuyTreadmill then
        return false
    end

    local remote = Treadmill.FindBuyRemote()
    if not remote then
        setAutoStatus("Auto Buy Treadmill: BuyTrainTool remote not found yet.")
        return false
    end

    local payloads = Treadmill.GetPayloadTiers()
    if #payloads == 0 then
        setAutoStatus("Auto Buy Treadmill: scanner found no treadmill payloads yet.")
        return false
    end

    -- Build inventory state once per pass instead of rescanning for every tier.
    local live = Treadmill.BuildLiveState()
    local owned = live.OwnedById or {}
    local now = os.clock()
    local candidates = {}

    for _, tier in ipairs(payloads) do
        if tier and tier.Id and not owned[tier.Id] then
            local retryAt = Treadmill.BuyRetryAt[tier.Id] or 0
            if force or now >= retryAt then
                table.insert(candidates, tier)
            end
        end
    end

    if #candidates == 0 then
        return false
    end

    Treadmill.Buying = true
    local accepted = 0
    local attempted = 0
    local maxAttempts = force and #candidates or math.min(#candidates, Treadmill.MaxAutoBuysPerPass)

    for i = 1, maxAttempts do
        if not RUNNING then
            break
        end
        if not force and not State.AutoBuyTreadmill then
            break
        end

        local tier = candidates[i]
        attempted += 1

        local ok = Treadmill.BuyTier(tier.Id)
        local t = os.clock()

        if ok then
            accepted += 1
            -- Give inventory/server replication time before this same payload is
            -- considered again. This prevents buying an already accepted tier
            -- dozens of times while the Tool is still replicating.
            Treadmill.BuyRetryAt[tier.Id] = t + Treadmill.BuyAcceptedCooldown
        else
            Treadmill.BuyRetryAt[tier.Id] = t + Treadmill.BuyRetryDelay
        end

        -- Small ordered spacing; only a few payloads are attempted per auto pass.
        task.wait(0.06)
    end

    Treadmill.Buying = false

    -- Inventory ChildAdded normally refreshes the live scanner for successful
    -- buys. Only force a scan here for manual passes or accepted calls.
    if force or accepted > 0 then
        task.defer(function()
            task.wait(0.15)
            if RUNNING then
                Treadmill.UpdateScanner()
            end
        end)
    end

    if State.AutoEquipTreadmill
        and accepted > 0
        and not State.PlacingEggs
        and not State.HatchingEggs
        and State.CurrentTarget == nil then

        task.defer(function()
            task.wait(0.12)
            if RUNNING and State.AutoEquipTreadmill then
                Treadmill.EquipBest()
            end
        end)
    end

    if force or accepted > 0 then
        setAutoStatus(
            "Treadmill buy | attempted: "
            .. tostring(attempted)
            .. " | accepted: "
            .. tostring(accepted)
            .. " | payloads: "
            .. tostring(#payloads)
        )
    end

    return accepted > 0
end


-- Start the live treadmill payload discovery before inventory scanner/status.
Treadmill.StartPayloadScanner()
Treadmill.BindScanner()

-- Auto buy loop.
task.spawn(function()
    while RUNNING do
        task.wait(AUTO_BUY_TREADMILL_RATE)
        if State.AutoBuyTreadmill then
            Treadmill.RunBuyPass(false)
        end
    end
end)

-- Live scanner handles inventory changes immediately.
-- This slower loop is only a safety fallback in case the game mutates tools
-- without firing the expected Backpack/Character child events.
task.spawn(function()
    while RUNNING do
        task.wait(IDLE_TREADMILL_EQUIP_RATE)

        if State.AutoEquipTreadmill
            and not State.PlacingEggs
            and not State.HatchingEggs
            and State.CurrentTarget == nil then

            local _, _, _, live = Treadmill.UpdateScanner()
            local best = live and live.BestTier
            local equipped = live and live.EquippedTier

            if best and (not equipped or best.Rank > equipped.Rank) then
                Treadmill.EquipBest()
            end
        end
    end
end)

-- Auto claim treadmill-training bonus. The confirmed ClaimBonus RF takes no arguments.
task.spawn(function()
    while RUNNING do
        task.wait(AUTO_CLAIM_TRAINING_BONUS_RATE)

        if State.AutoClaimTrainingBonus then
            Treadmill.ClaimBonus(false)
        end
    end
end)


--// AUTO EQUIP BEST ANIMALS - EVERY 10 SECONDS
-- Exact observed call:
-- AnimalService.RF.EquipBest:InvokeServer()
-- Kept on State instead of new top-level locals to avoid Luau's 200-local limit.
State.AnimalEquipBest = {
    Remote = nil,
    Running = false,
    Interval = 10,
}

function State.AnimalEquipBest.FindRemote()
    if State.AnimalEquipBest.Remote and State.AnimalEquipBest.Remote.Parent then
        return State.AnimalEquipBest.Remote
    end

    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return nil
    end

    -- Prefer the exact Knit path shape: AnimalService -> RF -> EquipBest.
    for _, object in ipairs(packages:GetDescendants()) do
        if object:IsA("RemoteFunction")
            and object.Name == "EquipBest"
            and object.Parent
            and object.Parent.Name == "RF" then

            local current = object.Parent
            while current and current ~= packages do
                if current.Name == "AnimalService" then
                    State.AnimalEquipBest.Remote = object
                    return object
                end
                current = current.Parent
            end
        end
    end

    return nil
end

function State.AnimalEquipBest.Run(force)
    if not RUNNING or State.AnimalEquipBest.Running then
        return false
    end

    if not force and not State.AutoEquipBestAnimals then
        return false
    end

    local remote = State.AnimalEquipBest.FindRemote()
    if not remote then
        if force then
            setAutoStatus("Equip Best Animals: AnimalService.RF.EquipBest not found.")
        end
        return false
    end

    State.AnimalEquipBest.Running = true

    local ok, result = pcall(function()
        return remote:InvokeServer()
    end)

    State.AnimalEquipBest.Running = false

    if not ok then
        State.AnimalEquipBest.Remote = nil
        if force then
            setAutoStatus("Equip Best Animals failed: " .. tostring(result))
        end
        return false
    end

    if result == false then
        if force then
            setAutoStatus("Equip Best Animals: server returned false.")
        end
        return false
    end

    if force then
        setAutoStatus("Best animals equipped.")
    end

    return true
end

-- Lightweight 10-second loop. The remote is cached after first discovery,
-- so it does not rescan Packages every cycle unless the remote disappears.
task.spawn(function()
    while RUNNING do
        task.wait(State.AnimalEquipBest.Interval)

        if State.AutoEquipBestAnimals then
            State.AnimalEquipBest.Run(false)
        end
    end
end)

--// AUTO PLACE BACKPACK EGGS IN MY PLOT
-- The observed PlaceEgg RemoteFunction takes no visible arguments, so placement
-- is driven like the normal client flow: equip an egg, target a point on our
-- PlotSurface, programmatically click it, then use PlaceEgg as a fallback.
local PlaceEggRemote = nil
local PlacementSlot = 0
local PlacementAttemptedAt = setmetatable({}, {__mode = "k"})

--// MAXIMUM EGG LIMIT UI DETECTOR
-- When the game shows:
-- "You have reached the maximum number of eggs you can place!"
-- The current fill cycle stops only when this warning appears; Auto Place itself stays enabled.
local MAX_EGG_LIMIT_TEXT = "maximum number of eggs you can place"
local MAX_EGG_UI_SCAN_RATE = 1.25 -- only used while placing / waiting on MAX
local AutoPlaceToggleController = nil
local AutoPickupToggleController = nil
-- Max warning cache is stored in State to avoid adding another top-level Luau register.

local function isTextGuiObject(object)
    return object
        and (
            object:IsA("TextLabel")
            or object:IsA("TextButton")
            or object:IsA("TextBox")
        )
end

local function isGuiObjectActuallyVisible(object)
    if not object or not object:IsDescendantOf(playerGui) then
        return false
    end

    local current = object

    while current and current ~= playerGui do
        if current:IsA("GuiObject") and current.Visible == false then
            return false
        end

        if current:IsA("LayerCollector") and current.Enabled == false then
            return false
        end

        current = current.Parent
    end

    return true
end

local function isMaxEggLimitTextObject(object)
    if not isTextGuiObject(object) then
        return false
    end

    local value = string.lower(tostring(object.Text or ""))

    if not string.find(value, MAX_EGG_LIMIT_TEXT, 1, true) then
        return false
    end

    return isGuiObjectActuallyVisible(object)
end

local function isMaxEggLimitVisible()
    -- Fast path: once the game reuses the same warning label, avoid rescanning
    -- the entire PlayerGui on every placement check.
    if State.MaxEggWarningObject and State.MaxEggWarningObject.Parent then
        if isMaxEggLimitTextObject(State.MaxEggWarningObject) then
            return true, State.MaxEggWarningObject
        end
    else
        State.MaxEggWarningObject = nil
    end

    for _, object in ipairs(playerGui:GetDescendants()) do
        if isMaxEggLimitTextObject(object) then
            State.MaxEggWarningObject = object
            return true, object
        end
    end

    return false, nil
end

local function stopAutoPlaceForMaxEggLimit(source)
    local wasActive = State.AutoPlaceEggs or State.PlacingEggs
    local alreadyPaused = State.MaxEggLimitReached

    -- IMPORTANT:
    -- Do NOT disable Auto Place. The warning only pauses the current fill cycle.
    -- The live Growing Eggs detector will unlock placement again when count = 0.
    State.MaxEggLimitReached = true

    if wasActive and not alreadyPaused then
        print(
            "[ZHM] Auto Place PAUSED: maximum egg placement warning detected.",
            source or ""
        )
    end

    if alreadyPaused then
        return
    end

    task.delay(0.02, function()
        if RUNNING and State.MaxEggLimitReached then
            setAutoStatus("Auto Place PAUSED: plot full. Waiting for Growing Eggs = 0.")
        end
    end)
end

local function checkMaxEggLimitUI()
    local visible, object = isMaxEggLimitVisible()

    if visible then
        stopAutoPlaceForMaxEggLimit(
            object and object:GetFullName() or "screen message"
        )
        return true
    end

    return false
end


--// LOW-LAG LIVE GROWING EGGS DETECTOR
-- Adapted from the provided ZHM optimized detector:
-- scan once -> lock onto the real counter -> update only when its text changes.
local GrowingCounterObject = nil
local GrowingCounterTextConnection = nil
local GrowingCounterContentConnection = nil
local GrowingCounterDestroyConnection = nil
local GrowingCounterFinding = false

local function cleanGrowingCounterText(value)
    if type(value) ~= "string" then
        return ""
    end

    value = value:gsub("<.->", "")
    value = value:gsub("\194\160", " ")
    value = value:gsub("%s+", " ")
    return value
end

local function getGrowingCounterText(object)
    if not object then
        return ""
    end

    local value = ""

    pcall(function()
        value = object.ContentText
    end)

    if value == "" then
        pcall(function()
            value = object.Text
        end)
    end

    return cleanGrowingCounterText(value)
end

local function parseGrowingCounter(value)
    value = cleanGrowingCounterText(value)

    local current, maximum = value:match("(%d+)%s*/%s*(%d+)")
    current = tonumber(current)
    maximum = tonumber(maximum)

    if not current or not maximum or maximum <= 0 then
        return nil
    end

    if current < 0 or current > maximum then
        return nil
    end

    return current, maximum
end

local function findGrowingCounter()
    local bestObject = nil
    local bestScore = -1

    for _, object in ipairs(playerGui:GetDescendants()) do
        if isTextGuiObject(object) then
            local value = getGrowingCounterText(object)
            local current, maximum = parseGrowingCounter(value)

            if current and maximum then
                local lowerText = string.lower(value)
                local lowerPath = string.lower(object:GetFullName())
                local score = 0

                if string.find(lowerText, "growing eggs", 1, true) then
                    score += 1000
                end

                if string.find(lowerPath, "egg_frame", 1, true) then
                    score += 300
                end

                if string.find(lowerPath, "egg", 1, true) then
                    score += 100
                end

                if maximum >= 10 and maximum <= 100 then
                    score += 25
                end

                if score > bestScore then
                    bestScore = score
                    bestObject = object
                end
            end
        end
    end

    return bestObject, bestScore
end


--// FIRST EGG LIVE ACTION SCANNER
-- Uses the provided Growing Eggs scanner logic:
-- PlayerGui.Windows.Egg_Frame -> ItemsContainer -> first visible/top-most card.
local GrowingEggFrameCache = nil
local GrowingItemsContainerCache = nil

-- IMPORTANT:
-- The Growing Eggs window does NOT need to be open for the scanner to work.
-- Roblox keeps the Egg_Frame rows/text alive while the parent window is hidden,
-- so this scanner intentionally ignores ancestor Visible/Enabled state.
--
-- This fixes the old behavior where Auto Hatch only detected CLAIM after the
-- player manually opened/tapped the Eggs window.
local function isVisibleEggGui(object)
    if not object or not object:IsA("GuiObject") then
        return false
    end

    -- Do not require object.Visible or any ancestor to be visible.
    -- Hidden Egg_Frame children still contain the live CLAIM/SKIP/READY text.
    return true
end

local function looksLikeGrowingEggUID(value)
    value = tostring(value or "")

    if #value < 16 then
        return false
    end

    -- Normal UUID used by the game.
    if string.match(value, "^[%x]+%-%x+%-%x+%-%x+%-%x+$") then
        return true
    end

    -- Permissive fallback in case the game changes UID format.
    return string.find(value, "-", 1, true) ~= nil
end

local function findGrowingEggFrame()
    if GrowingEggFrameCache and GrowingEggFrameCache.Parent then
        return GrowingEggFrameCache
    end

    local windows = playerGui:FindFirstChild("Windows")
    local frame = windows and windows:FindFirstChild("Egg_Frame")

    if frame then
        GrowingEggFrameCache = frame
        return frame
    end

    for _, object in ipairs(playerGui:GetDescendants()) do
        if object.Name == "Egg_Frame" then
            GrowingEggFrameCache = object
            return object
        end
    end

    GrowingEggFrameCache = nil
    return nil
end

local function findGrowingItemsContainer()
    if GrowingItemsContainerCache and GrowingItemsContainerCache.Parent then
        return GrowingItemsContainerCache
    end

    local eggFrame = findGrowingEggFrame()
    if not eggFrame then
        GrowingItemsContainerCache = nil
        return nil
    end

    local items = eggFrame:FindFirstChild("ItemsContainer", true)
    GrowingItemsContainerCache = items

    return items
end

local function findFirstGrowingEggCard()
    local items = findGrowingItemsContainer()
    if not items then
        return nil
    end

    -- LOW-LAG: select the best row in one pass instead of allocating two
    -- arrays and sorting them every CLAIM/SKIP refresh.
    local bestUid = nil
    local bestUidOrder = math.huge
    local bestFallback = nil
    local bestFallbackOrder = math.huge

    for _, child in ipairs(items:GetChildren()) do
        if child:IsA("GuiObject") then
            local order = tonumber(child.LayoutOrder) or 0

            if looksLikeGrowingEggUID(child.Name) then
                if not bestUid
                    or order < bestUidOrder
                    or (order == bestUidOrder and tostring(child.Name) < tostring(bestUid.Name)) then

                    bestUid = child
                    bestUidOrder = order
                end
            elseif not bestFallback
                or order < bestFallbackOrder
                or (order == bestFallbackOrder and tostring(child.Name) < tostring(bestFallback.Name)) then

                bestFallback = child
                bestFallbackOrder = order
            end
        end
    end

    return bestUid or bestFallback
end

local function getGrowingEggCardText(card)
    if not card then
        return ""
    end

    local texts = {}

    if isTextGuiObject(card) then
        local value = getGrowingCounterText(card)
        if value ~= "" then
            table.insert(texts, value)
        end
    end

    for _, object in ipairs(card:GetDescendants()) do
        -- Read text even while Egg_Frame / the row / the label is hidden.
        -- The game updates these values in the background.
        if isTextGuiObject(object) then
            local value = getGrowingCounterText(object)

            if value ~= "" then
                table.insert(texts, value)
            end
        end
    end

    return table.concat(texts, " | ")
end

local function detectGrowingEggName(card)
    if not card then
        return "No Egg"
    end

    for _, object in ipairs(card:GetDescendants()) do
        -- Egg name text is still useful when the Eggs window is closed.
        if isTextGuiObject(object) then
            local value = getGrowingCounterText(object)
            local lower = string.lower(value)

            if value ~= ""
                and string.find(lower, "egg", 1, true)
                and not string.find(lower, "growing eggs", 1, true) then

                return value
            end
        end
    end

    return "Unknown Egg"
end

local function detectGrowingEggAction(card)
    if not card then
        return "NONE"
    end

    local combined = string.upper(getGrowingEggCardText(card))

    -- CLAIM has priority over every other action.
    if string.find(combined, "CLAIM", 1, true) then
        return "CLAIM"
    end

    -- Some versions use READY for a finished egg.
    if string.find(combined, "READY", 1, true) then
        return "CLAIM"
    end

    -- IMPORTANT: SKIP is a growing egg and MUST NOT trigger Auto Hatch.
    if string.find(combined, "SKIP", 1, true) then
        return "SKIP"
    end

    return "GROWING"
end

local function refreshGrowingEggScannerCard()
    local current = State.GrowingEggs
    local maximum = State.GrowingEggMax
    local free = nil

    if type(current) == "number" and type(maximum) == "number" then
        free = math.max(0, maximum - current)
    end

    local countText = "--/--"
    if current ~= nil and maximum ~= nil then
        countText = tostring(current) .. "/" .. tostring(maximum)
    end

    local freeText = free ~= nil and tostring(free) or "--"
    local eggText = tostring(State.FirstEggName or "No Egg")
    local actionText = tostring(State.FirstEggAction or "SEARCHING")

    setGrowingEggStatus(
        "Growing: "
        .. countText
        .. " | Free: "
        .. freeText
        .. "\nFirst Egg: "
        .. eggText
        .. " | Action: "
        .. actionText
    )
end

local function publishGrowingEggState()
    -- Optional shared live state for other ZHM scripts/debugging.
    ENV.__ZHM_GROWING_EGG_LIVE = {
        GrowingEggs = State.GrowingEggs,
        MaxEggs = State.GrowingEggMax,
        FirstEggName = State.FirstEggName,
        FirstEggUID = State.FirstEggUID,
        Action = State.FirstEggAction,
        Ready = State.FirstEggScannerReady,
    }
end

local function updateFirstGrowingEggAction()
    local card = findFirstGrowingEggCard()

    local newName = "No Egg"
    local newUID = nil
    local newAction = "NONE"

    if card then
        newName = detectGrowingEggName(card)
        newUID = tostring(card.Name or "")
        newAction = detectGrowingEggAction(card)
    end

    local changed =
        State.FirstEggName ~= newName
        or State.FirstEggUID ~= newUID
        or State.FirstEggAction ~= newAction
        or not State.FirstEggScannerReady

    State.FirstEggName = newName
    State.FirstEggUID = newUID
    State.FirstEggAction = newAction
    State.FirstEggScannerReady = true

    publishGrowingEggState()
    refreshGrowingEggScannerCard()

    if not changed then
        return
    end

    print(
        "[ZHM] First Egg LIVE:",
        newName,
        "| UID:",
        tostring(newUID),
        "| Action:",
        newAction
    )

    if State.AutoHatchEggs then
        if newAction == "CLAIM" then
            setHatchStatus("ON | Action: CLAIM | claiming first egg...")

            -- Trigger immediately on the CLAIM transition.
            local claimUID = newUID

            task.spawn(function()
                if RUNNING
                    and State.AutoHatchEggs
                    and State.FirstEggAction == "CLAIM"
                    and State.FirstEggUID == claimUID
                    and HatchSystem
                    and HatchSystem.Run then

                    HatchSystem.Run(false)
                end
            end)

        elseif newAction == "SKIP" then
            setHatchStatus("ON | Action: SKIP | waiting - Auto Hatch blocked.")

        elseif newAction == "GROWING" then
            setHatchStatus("ON | Action: GROWING | waiting.")

        else
            setHatchStatus("ON | Action: " .. newAction .. " | waiting.")
        end
    end
end

local function disconnectGrowingCounterSignals()
    if GrowingCounterTextConnection then
        GrowingCounterTextConnection:Disconnect()
        GrowingCounterTextConnection = nil
    end

    if GrowingCounterContentConnection then
        GrowingCounterContentConnection:Disconnect()
        GrowingCounterContentConnection = nil
    end

    if GrowingCounterDestroyConnection then
        GrowingCounterDestroyConnection:Disconnect()
        GrowingCounterDestroyConnection = nil
    end
end

local function updateGrowingEggCount()
    if not GrowingCounterObject or not GrowingCounterObject.Parent then
        State.GrowingEggCounterReady = false
        return false
    end

    local current, maximum = parseGrowingCounter(
        getGrowingCounterText(GrowingCounterObject)
    )

    if not current or not maximum then
        State.GrowingEggCounterReady = false
        return false
    end

    local changed =
        State.GrowingEggs ~= current
        or State.GrowingEggMax ~= maximum
        or not State.GrowingEggCounterReady

    State.GrowingEggs = current
    State.GrowingEggMax = maximum
    State.GrowingEggCounterReady = true

    publishGrowingEggState()
    refreshGrowingEggScannerCard()

    if changed then
        print(
            "[ZHM] Growing Eggs LIVE:",
            tostring(current) .. "/" .. tostring(maximum)
        )

        -- A previous full-plot warning is only released after the live counter
        -- says 0 AND the old warning is no longer visible.
        if current == 0 and State.MaxEggLimitReached then
            task.defer(function()
                task.wait(0.05)

                if not RUNNING
                    or not State.GrowingEggCounterReady
                    or State.GrowingEggs ~= 0 then
                    return
                end

                local warningVisible = isMaxEggLimitVisible()

                if not warningVisible then
                    State.MaxEggLimitReached = false
                    setAutoStatus("Growing Eggs = 0. Auto Place resumed.")
                end
            end)
        elseif current > 0 and State.AutoPlaceEggs and not State.PlacingEggs then
            setAutoStatus(
                "Auto Place waiting: Growing Eggs "
                .. tostring(current)
                .. "/"
                .. tostring(maximum)
            )
        end
    end

    return true
end

local function lockGrowingCounter()
    if GrowingCounterFinding then
        return
    end

    GrowingCounterFinding = true
    disconnectGrowingCounterSignals()
    State.GrowingEggCounterReady = false

    local object, score = findGrowingCounter()

    if not object then
        GrowingCounterObject = nil
        GrowingCounterFinding = false
        return
    end

    GrowingCounterObject = object

    print(
        "[ZHM] Growing Eggs counter locked:",
        object:GetFullName(),
        "Score:",
        score
    )

    GrowingCounterTextConnection =
        object:GetPropertyChangedSignal("Text"):Connect(function()
            updateGrowingEggCount()
        end)

    pcall(function()
        GrowingCounterContentConnection =
            object:GetPropertyChangedSignal("ContentText"):Connect(function()
                updateGrowingEggCount()
            end)
    end)

    GrowingCounterDestroyConnection =
        object.AncestryChanged:Connect(function()
            if not object.Parent then
                GrowingCounterObject = nil
                State.GrowingEggCounterReady = false

                task.delay(0.50, function()
                    if RUNNING then
                        lockGrowingCounter()
                    end
                end)
            end
        end)

    updateGrowingEggCount()
    GrowingCounterFinding = false
end

-- Safety recovery only. This does NOT continuously full-scan PlayerGui.
task.spawn(function()
    while RUNNING do
        task.wait(5)

        if not GrowingCounterObject or not GrowingCounterObject.Parent then
            lockGrowingCounter()
        else
            updateGrowingEggCount()
        end
    end
end)

-- Initial lock.
task.defer(function()
    task.wait(0.25)
    if RUNNING then
        lockGrowingCounter()
    end
end)

-- First egg CLAIM/SKIP scanner.
-- Slow loop is fallback only. Normal CLAIM detection is event-driven below.
task.spawn(function()
    while RUNNING do
        updateFirstGrowingEggAction()
        task.wait(FIRST_EGG_SCAN_RATE)
    end
end)

-- ZERO-INTENTIONAL-DELAY CLAIM DETECTION.
-- Watches only Egg_Frame.ItemsContainer, not the entire UI continuously.
State.FirstEggLive = {
    Watched = setmetatable({}, {__mode = "k"}),
    Refreshing = false,
    Queued = false,
}

function State.FirstEggLive.IsInside(object)
    if not object then
        return false
    end

    -- Avoid GetFullName()/lowercase allocations for every PlayerGui addition.
    local current = object
    local foundItems = false
    local depth = 0

    while current and current ~= playerGui and depth < 18 do
        if current.Name == "ItemsContainer" then
            foundItems = true
        elseif foundItems and current.Name == "Egg_Frame" then
            return true
        end

        current = current.Parent
        depth += 1
    end

    return false
end

function State.FirstEggLive.Refresh()
    if not RUNNING or State.FirstEggLive.Refreshing or State.FirstEggLive.Queued then
        return
    end

    -- Several labels often change during the same frame. Collapse that burst
    -- into a single scanner refresh.
    State.FirstEggLive.Queued = true

    task.defer(function()
        State.FirstEggLive.Queued = false

        if not RUNNING or State.FirstEggLive.Refreshing then
            return
        end

        State.FirstEggLive.Refreshing = true
        pcall(updateFirstGrowingEggAction)
        State.FirstEggLive.Refreshing = false
    end)
end

function State.FirstEggLive.Watch(object)
    if not object
        or State.FirstEggLive.Watched[object]
        or not State.FirstEggLive.IsInside(object) then
        return
    end

    State.FirstEggLive.Watched[object] = true

    if object:IsA("TextLabel")
        or object:IsA("TextButton")
        or object:IsA("TextBox") then

        -- Text changes are sufficient for CLAIM / READY / SKIP. We deliberately
        -- do not bind Visible/ContentText for every descendant because the Eggs
        -- window can stay hidden and those extra signals create needless churn.
        pcall(function()
            bind(object:GetPropertyChangedSignal("Text"), State.FirstEggLive.Refresh)
        end)
    end
end

function State.FirstEggLive.WatchCurrent()
    local items = findGrowingItemsContainer()
    if not items then
        return
    end

    State.FirstEggLive.Watch(items)

    for _, object in ipairs(items:GetDescendants()) do
        State.FirstEggLive.Watch(object)
    end
end

State.FirstEggLive.WatchCurrent()

bind(playerGui.DescendantAdded, function(object)
    if State.FirstEggLive.IsInside(object) then
        State.FirstEggLive.Watch(object)
        State.FirstEggLive.Refresh()
    elseif object.Name == "Egg_Frame" or object.Name == "ItemsContainer" then
        GrowingEggFrameCache = nil
        GrowingItemsContainerCache = nil
        State.FirstEggLive.WatchCurrent()
        State.FirstEggLive.Refresh()
    end
end)

bind(playerGui.DescendantRemoving, function(object)
    if State.FirstEggLive.IsInside(object) then
        task.defer(State.FirstEggLive.Refresh)
    end
end)

-- Recover cached Egg_Frame / ItemsContainer when the game rebuilds the UI.
bind(playerGui.DescendantAdded, function(object)
    if object.Name == "Egg_Frame" or object.Name == "ItemsContainer" then
        GrowingEggFrameCache = nil
        GrowingItemsContainerCache = nil

        task.defer(function()
            if RUNNING then
                State.FirstEggLive.WatchCurrent()
                updateFirstGrowingEggAction()
            end
        end)
    end
end)

bind(playerGui.DescendantRemoving, function(object)
    if object == State.MaxEggWarningObject then
        State.MaxEggWarningObject = nil
    end

    if object == GrowingEggFrameCache or object == GrowingItemsContainerCache then
        GrowingEggFrameCache = nil
        GrowingItemsContainerCache = nil
        State.FirstEggScannerReady = false
    end
end)

-- Live event + fast fallback polling, because some games reuse one TextLabel
-- and only change its Text/Visible state instead of creating a new object.
bind(playerGui.DescendantAdded, function(object)
    if not isTextGuiObject(object) then
        return
    end

    task.defer(function()
        task.wait(0.01)

        if RUNNING and isMaxEggLimitTextObject(object) then
            State.MaxEggWarningObject = object
            stopAutoPlaceForMaxEggLimit(object:GetFullName())
        end
    end)
end)

task.spawn(function()
    while RUNNING do
        task.wait(MAX_EGG_UI_SCAN_RATE)

        -- No reason to scan the whole PlayerGui while placement is idle.
        if State.PlacingEggs or State.MaxEggLimitReached then
            checkMaxEggLimitUI()
        end
    end
end)

local function findPlaceEggRemote()
    if PlaceEggRemote and PlaceEggRemote.Parent then
        return PlaceEggRemote
    end

    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return nil
    end

    local fallback = nil

    for _, object in ipairs(packages:GetDescendants()) do
        if object.Name == "PlaceEgg" and object:IsA("RemoteFunction") then
            local full = string.lower(object:GetFullName())

            -- Prefer EggService.RF.PlaceEgg when multiple remotes share the name.
            if string.find(full, "eggservice", 1, true)
                and string.find(full, ".rf.", 1, true) then
                PlaceEggRemote = object
                return object
            end

            fallback = fallback or object
        end
    end

    PlaceEggRemote = fallback
    return fallback
end

local function isInventoryEggTool(item)
    if not item or not item:IsA("Tool") then
        return false
    end

    local n = cleanName(item.Name)

    if EggDatabase[n] then
        return true
    end

    if string.find(n, "egg", 1, true) then
        return true
    end

    if item:GetAttribute("Egg") ~= nil
        or item:GetAttribute("EggType") ~= nil
        or item:GetAttribute("EggName") ~= nil
        or item:GetAttribute("IsEgg") == true then
        return true
    end

    for _, child in ipairs(item:GetDescendants()) do
        local childName = cleanName(child.Name)
        if childName == "egg"
            or childName == "eggtype"
            or childName == "eggname" then
            return true
        end
    end

    return false
end

local function getBackpackEggTools()
    local eggs = {}
    local backpack = Treadmill.GetBackpack()

    if backpack then
        for _, object in ipairs(backpack:GetChildren()) do
            if isInventoryEggTool(object) then
                table.insert(eggs, object)
            end
        end
    end

    table.sort(eggs, function(a, b)
        return string.lower(a.Name) < string.lower(b.Name)
    end)

    return eggs
end

local function getMyPlotSurface()
    if not MyPlot or not MyPlot.Parent then
        MyPlot = findMyPlot()
    end

    if not MyPlot then
        return nil
    end

    local surface = MyPlot:FindFirstChild("PlotSurface", true)
    if surface and surface:IsA("BasePart") then
        return surface
    end

    return MyPlot:FindFirstChildWhichIsA("BasePart", true)
end

local function getNextPlotPlacementPosition()
    local surface = getMyPlotSurface()
    if not surface then
        return nil, nil
    end

    PlacementSlot += 1

    -- HANDS-FREE PLOT PLACEMENT:
    -- Spread eggs automatically through a 7x7 serpentine grid inside the plot.
    -- The user never needs to aim the mouse at a placement point manually.
    local cols = 5
    local rows = 5
    local index = (PlacementSlot - 1) % (cols * rows)
    local zIndex = math.floor(index / cols)
    local xIndex = index % cols

    -- Serpentine order keeps consecutive placements near each other instead of
    -- jumping from one side of the plot to the other every row.
    if zIndex % 2 == 1 then
        xIndex = (cols - 1) - xIndex
    end

    local xAlpha = cols > 1 and (xIndex / (cols - 1) - 0.5) or 0
    local zAlpha = rows > 1 and (zIndex / (rows - 1) - 0.5) or 0

    -- Keep a safe border so eggs are not placed on the very edge of PlotSurface.
    local xOffset = xAlpha * surface.Size.X * 0.60
    local zOffset = zAlpha * surface.Size.Z * 0.60
    local localY = surface.Size.Y * 0.5 + 0.08

    local pointCF = surface.CFrame * CFrame.new(xOffset, localY, zOffset)
    return pointCF.Position, surface
end

local function equipInventoryEgg(tool)
    if not tool or not tool.Parent then
        return false
    end

    local character = player.Character
    if not character then
        return false
    end

    if tool.Parent == character then
        return true
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end

    local backpack = Treadmill.GetBackpack()
    if not backpack or tool.Parent ~= backpack then
        return false
    end

    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)

    task.wait(0.08)
    return ok and tool.Parent == character
end

local function programmaticPlotClick(worldPosition, tool)
    if not worldPosition or not tool or not tool.Parent then
        return false
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return false
    end

    local restoreType = camera.CameraType
    local restoreCF = camera.CFrame
    local originalMouse = UserInputService:GetMouseLocation()

    -- Snapshot placement state AFTER the egg is equipped. This lets us confirm
    -- stacked/reused egg Tools without trusting a nil RemoteFunction result.
    local beforeGrowing = tonumber(State.GrowingEggs)
    local beforeAttributes = tool:GetAttributes()
    local beforeValues = {}

    for _, object in ipairs(tool:GetDescendants()) do
        if object:IsA("ValueBase") then
            beforeValues[object] = object.Value
        end
    end

    local function stillInInventory()
        if not tool or not tool.Parent then
            return false
        end

        local backpack = Treadmill.GetBackpack()
        local character = player.Character
        return tool.Parent == backpack or tool.Parent == character
    end

    local function placementObserved()
        if not stillInInventory() then
            return true
        end

        local growingNow = tonumber(State.GrowingEggs)
        if beforeGrowing and growingNow and growingNow > beforeGrowing then
            return true
        end

        if tool and tool.Parent then
            for key, oldValue in pairs(beforeAttributes) do
                if tool:GetAttribute(key) ~= oldValue then
                    return true
                end
            end

            for object, oldValue in pairs(beforeValues) do
                if not object.Parent or object.Value ~= oldValue then
                    return true
                end
            end
        end

        return false
    end

    -- Temporarily hide only the ZHM hub so the synthetic click cannot be
    -- swallowed by one of our own buttons.
    local hiddenGui = nil
    local hiddenGuiWasEnabled = nil
    local guiParents = {playerGui, CoreGui}

    if gethui then
        local okHui, hui = pcall(gethui)
        if okHui and hui then
            table.insert(guiParents, 1, hui)
        end
    end

    for _, parent in ipairs(guiParents) do
        local candidate = parent and parent:FindFirstChild(GUI_NAME)
        if candidate and candidate:IsA("ScreenGui") then
            hiddenGui = candidate
            hiddenGuiWasEnabled = candidate.Enabled
            candidate.Enabled = false
            break
        end
    end

    -- Aim at the generated plot point. Keep the camera/cursor here until every
    -- placement method has finished; the user's real mouse position is irrelevant.
    pcall(function()
        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.lookAt(
            worldPosition + Vector3.new(0, 24, 8),
            worldPosition
        )
    end)

    pcall(function()
        game:GetService("RunService").RenderStepped:Wait()
    end)
    task.wait(0.03)

    local point = camera:WorldToScreenPoint(worldPosition)

    -- Re-aim from almost directly above if the first projection is invalid.
    if point.Z <= 0 then
        pcall(function()
            camera.CFrame = CFrame.lookAt(
                worldPosition + Vector3.new(0, 28, 2),
                worldPosition
            )
        end)

        pcall(function()
            game:GetService("RunService").RenderStepped:Wait()
        end)
        task.wait(0.03)
        point = camera:WorldToScreenPoint(worldPosition)
    end

    local okVIM, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)

    local function moveVirtualMouse()
        if not okVIM or not vim or point.Z <= 0 then
            return false
        end

        return pcall(function()
            -- Re-send the position several times so Mouse.Hit updates before the
            -- placement controller reads it.
            vim:SendMouseMoveEvent(point.X, point.Y, game)
            task.wait(0.025)
            vim:SendMouseMoveEvent(point.X, point.Y, game)
            task.wait(0.025)
            vim:SendMouseMoveEvent(point.X, point.Y, game)
        end)
    end

    local function sendVirtualClick()
        if not moveVirtualMouse() then
            return false
        end

        return pcall(function()
            task.wait(0.035)
            vim:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0)
            task.wait(0.055)
            vim:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0)
        end)
    end

    local success = false

    -- Method A: normal click while the virtual pointer is over our generated
    -- point. This is closest to manually clicking inside the plot.
    sendVirtualClick()
    task.wait(0.16)
    success = placementObserved()

    -- Method B: Tool:Activate while Mouse.Hit is still aimed at the generated
    -- point. Some versions of the placement controller react to Activated.
    if not success and stillInInventory() then
        moveVirtualMouse()

        pcall(function()
            tool:Activate()
        end)

        task.wait(0.18)
        success = placementObserved()
    end

    -- Method C: repeat a click after Tool:Activate. This helps clients where
    -- equipping/activating creates the placement listener one frame late.
    if not success and stillInInventory() then
        sendVirtualClick()
        task.wait(0.18)
        success = placementObserved()
    end

    -- Method D: observed no-argument PlaceEgg RF fallback. Do NOT treat nil as
    -- automatic success; wait for inventory / Growing Eggs / Tool state to change.
    if not success
        and stillInInventory()
        and not State.MaxEggLimitReached
        and not checkMaxEggLimitUI() then

        moveVirtualMouse()

        local remote = findPlaceEggRemote()
        if remote then
            pcall(function()
                remote:InvokeServer()
            end)

            local deadline = os.clock() + 0.55
            repeat
                task.wait(0.05)
                success = placementObserved()
            until success
                or os.clock() >= deadline
                or State.MaxEggLimitReached
                or checkMaxEggLimitUI()
        end
    end

    -- Restore the user's camera/cursor only after all placement methods have
    -- completed, so manual mouse pointing is never required.
    if okVIM and vim then
        pcall(function()
            vim:SendMouseMoveEvent(originalMouse.X, originalMouse.Y, game)
        end)
    end

    pcall(function()
        camera.CFrame = restoreCF
        camera.CameraType = restoreType
    end)

    if hiddenGui and hiddenGui.Parent then
        hiddenGui.Enabled = hiddenGuiWasEnabled ~= false
    end

    return success
end
local function eggStillInInventory(tool)
    if not tool or not tool.Parent then
        return false
    end

    local backpack = Treadmill.GetBackpack()
    local character = player.Character
    return tool.Parent == backpack or tool.Parent == character
end

local function placeOneBackpackEgg(tool)
    if not RUNNING
        or (not State.AutoPlaceEggs and not State.AutoPlaceAfterPickup)
        or State.MaxEggLimitReached then
        return false
    end

    if checkMaxEggLimitUI() then
        return false
    end

    if not tool or not tool.Parent or not isInventoryEggTool(tool) then
        return false
    end

    local now = os.clock()
    local last = PlacementAttemptedAt[tool]
    if last and now - last < 0.40 then
        return false
    end
    PlacementAttemptedAt[tool] = now

    local placementPosition, surface = getNextPlotPlacementPosition()
    if not placementPosition or not surface then
        setAutoStatus("Auto Place: PlotSurface not found.")
        return false
    end

    -- Ensure the normal placement controller considers us inside our own plot.
    local root = getCharacterRoot()
    if root then
        local flatDistance = (Vector3.new(root.Position.X, 0, root.Position.Z)
            - Vector3.new(surface.Position.X, 0, surface.Position.Z)).Magnitude

        if flatDistance > math.max(surface.Size.X, surface.Size.Z) * 0.75 then
            tpToCFrame(surface.CFrame * CFrame.new(0, TP_HEIGHT, 0))
            task.wait(0.10)
        end
    else
        return false
    end

    if not equipInventoryEgg(tool) then
        setAutoStatus("Auto Place: couldn't equip " .. tool.Name)
        return false
    end

    setAutoStatus("Auto Place: placing " .. tool.Name .. "...")

    -- HANDS-FREE placement owns the virtual aim for the full placement
    -- sequence. No manual mouse pointing is required.
    local placed = programmaticPlotClick(placementPosition, tool)
    task.wait(0.06)

    if checkMaxEggLimitUI() or State.MaxEggLimitReached then
        return false
    end

    if placed or not eggStillInInventory(tool) then
        Treadmill.UpdateScanner()
        return true
    end

    setAutoStatus("Auto Place: hands-free placement not confirmed; retrying next slot.")
    return false
end

local function suspendAutoPickupForAutoPlace()
    State.AutoPickupSuspendedByAutoPlace = true

    -- Keep the user's toggle preference separately. Actual pickup must be OFF
    -- while placement owns the character/plot.
    State.AutoPickup = false

    if State.AutoPickupUserEnabled then
        setAutoStatus("Auto Place active: Auto TP + Pickup temporarily paused.")
    end
end

local function restoreAutoPickupAfterAutoPlace()
    State.AutoPickupSuspendedByAutoPlace = false

    -- If the user turned Auto TP + Pickup OFF while placement was running,
    -- AutoPickupUserEnabled is false and it stays OFF.
    State.AutoPickup = State.AutoPickupUserEnabled

    if State.AutoPickupUserEnabled then
        setAutoStatus("Auto Place finished. Auto TP + Pickup restored.")
    end
end

local function hasBackpackEggs()
    local eggs = getBackpackEggTools()
    return #eggs > 0, eggs
end

local function placeAllBackpackEggs(alreadyBusy, ignoreGrowingGate)
    ignoreGrowingGate = ignoreGrowingGate == true

    local function modeEnabled()
        if ignoreGrowingGate then
            return State.AutoPlaceAfterPickup == true
        end
        return State.AutoPlaceEggs == true
    end

    if not RUNNING
        or not modeEnabled()
        or State.PlacingEggs
        or State.MaxEggLimitReached then
        return false
    end

    -- METHOD 1 uses Growing Eggs == 0 as its trigger.
    -- METHOD 2 (after pickup / no target) intentionally ignores the Growing Eggs count.
    if not ignoreGrowingGate then
        if not State.GrowingEggCounterReady or State.GrowingEggs ~= 0 then
            return false
        end
    end

    if checkMaxEggLimitUI() then
        return false
    end

    local hasEggs, firstEggs = hasBackpackEggs()

    -- HARD GATE:
    -- If no egg is detected in Backpack, do absolutely nothing.
    -- No placement remote, no TP for placement, no fill cycle.
    if not hasEggs then
        setAutoStatus("Auto Place waiting: no egg detected in Backpack.")
        return false
    end

    local ownedBusy = not alreadyBusy
    if ownedBusy then
        if State.Busy then
            return false
        end
        State.Busy = true
    end

    State.PlacingEggs = true
    suspendAutoPickupForAutoPlace()

    -- Work from our own plot for the entire fill cycle.
    local returnCF = getMyPlotReturnCFrame()
    if returnCF then
        tpToCFrame(returnCF)
        task.wait(0.10)
    end

    local placed = 0
    local noProgressPasses = 0
    local emptyPasses = 0

    while RUNNING
        and modeEnabled()
        and not State.MaxEggLimitReached do

        -- This is the MAIN stop condition.
        if checkMaxEggLimitUI() then
            break
        end

        -- Rescan every pass. This is important for stacked/reused egg Tools:
        -- one Tool instance can remain in Backpack after a successful placement.
        local hasEggsNow, eggs = hasBackpackEggs()

        if not hasEggsNow then
            -- Backpack is currently empty, so do not attempt PlaceEgg at all.
            emptyPasses += 1

            -- Small grace period in case the inventory UI/server is still updating.
            if emptyPasses >= 3 then
                setAutoStatus("Auto Place waiting: no egg detected in Backpack.")
                break
            end

            task.wait(0.12)
            continue
        end

        emptyPasses = 0
        local placedThisPass = 0

        for _, eggTool in ipairs(eggs) do
            if not RUNNING
                or not modeEnabled()
                or State.MaxEggLimitReached
                or checkMaxEggLimitUI() then
                break
            end

            if eggTool
                and eggTool.Parent
                and placeOneBackpackEgg(eggTool) then

                placed += 1
                placedThisPass += 1
            end

            -- Small delay keeps the loop responsive while still filling quickly.
            task.wait(AUTO_PLACE_DELAY)
        end

        if State.MaxEggLimitReached or checkMaxEggLimitUI() then
            break
        end

        if placedThisPass > 0 then
            noProgressPasses = 0
        else
            noProgressPasses += 1

            -- A stacked Tool may temporarily hit PlacementAttemptedAt cooldown.
            -- Wait and retry instead of ending after one Backpack pass.
            task.wait(0.25)

            -- Avoid an endless loop if the game changed and every placement method
            -- is failing for reasons unrelated to the egg-cap warning.
            if noProgressPasses >= 5 then
                break
            end
        end
    end

    State.PlacingEggs = false
    Treadmill.UpdateScanner()
    restoreAutoPickupAfterAutoPlace()

    if ownedBusy then
        State.Busy = false
    end

    if State.MaxEggLimitReached then
        if ignoreGrowingGate then
            setAutoStatus(
                "Method 2: MAX reached after "
                .. tostring(placed)
                .. " placement(s)."
            )
        else
            setAutoStatus(
                "Method 1: MAX reached after "
                .. tostring(placed)
                .. " placement(s). Waiting for Growing Eggs = 0."
            )
        end
        return placed > 0
    end

    if placed > 0 then
        local remaining = #getBackpackEggTools()

        if remaining == 0 then
            setAutoStatus(
                "Auto Place: Backpack empty after "
                .. tostring(placed)
                .. " placement(s)."
            )
        else
            setAutoStatus(
                "Auto Place: "
                .. tostring(placed)
                .. " placement(s); no further progress."
            )
        end

        return true
    end

    return false
end

-- Independent live auto-place loop.
-- LOOP:
--   Growing Eggs == 0 -> BEGIN fill cycle
--   keep placing/rescanning Backpack regardless of the count rising
--   maximum warning   -> STOP current fill cycle immediately
--   live counter == 0 and warning gone -> begin the next fill cycle
task.spawn(function()
    while RUNNING do
        task.wait(AUTO_PLACE_SCAN_RATE)

        if State.AutoPlaceEggs
            and State.GrowingEggCounterReady
            and State.GrowingEggs == 0
            and not State.Busy
            and State.CurrentTarget == nil
            and not State.PlacingEggs then

            if State.MaxEggLimitReached then
                local warningVisible = isMaxEggLimitVisible()

                if not warningVisible then
                    State.MaxEggLimitReached = false
                    setAutoStatus("Growing Eggs = 0. Starting next Auto Place cycle.")
                end
            end

            if not State.MaxEggLimitReached then
                local hasEggsNow = hasBackpackEggs()

                if hasEggsNow then
                    placeAllBackpackEggs(false)
                else
                    setAutoStatus("Auto Place waiting: no egg detected in Backpack.")
                end
            end
        end
    end
end)

--// AUTO HATCH / AUTO CLAIM PLACED EGGS
-- The latest action log shows the actual claim flow:
--   PlayerGui.Windows.Egg_Frame.Frame.ItemsContainer.<UID>.Button
--   -> EggService.RF.HatchEgg
-- We therefore use the GUI row name as the authoritative egg UID first.
-- Runtime/save records remain only as a fallback when the hatch UI is not built.
-- HatchSystem was forward-declared above so the live CLAIM scanner can wake it.
do
    local function buildHatchSystem()
        local remoteCache = nil
        local attemptedAt = {}
        -- Session lock: once HatchEgg accepts a UID, never spam that same UID
        -- again while stale CLAIM text is still present.
        local claimedUIDs = {}
        local eggCmdsModule = nil
        local saveModule = nil
        local watchedButtons = setmetatable({}, {__mode = "k"})

        local function findRemote()
            if remoteCache and remoteCache.Parent then
                return remoteCache
            end

            local packages = ReplicatedStorage:FindFirstChild("Packages")
            if not packages then
                return nil
            end

            local fallback = nil

            for _, object in ipairs(packages:GetDescendants()) do
                if object.Name == "HatchEgg" and object:IsA("RemoteFunction") then
                    local full = string.lower(object:GetFullName())

                    if string.find(full, "eggservice", 1, true)
                        and string.find(full, ".rf.", 1, true) then
                        remoteCache = object
                        return object
                    end

                    fallback = fallback or object
                end
            end

            remoteCache = fallback
            return fallback
        end

        local function looksLikeUid(value)
            value = tostring(value or "")

            if #value < 16 then
                return false
            end

            -- Normal UUID used by the game: 8-4-4-4-12.
            if string.match(
                value,
                "^[%x]+%-%x+%-%x+%-%x+%-%x+$"
            ) then
                return true
            end

            -- Keep a permissive fallback in case the game changes UID format.
            return string.find(value, "-", 1, true) ~= nil
        end

        local function findItemsContainer()
            local windows = playerGui:FindFirstChild("Windows")
            local eggFrame = windows and windows:FindFirstChild("Egg_Frame")
            local frame = eggFrame and eggFrame:FindFirstChild("Frame")
            local items = frame and frame:FindFirstChild("ItemsContainer")

            if items then
                return items
            end

            -- Dynamic fallback in case another layer/frame is inserted later.
            for _, object in ipairs(playerGui:GetDescendants()) do
                if object.Name == "ItemsContainer" then
                    local full = string.lower(object:GetFullName())
                    if string.find(full, "egg_frame", 1, true) then
                        return object
                    end
                end
            end

            return nil
        end

        local function collectGuiRows()
            local rows = {}
            local seen = {}
            local items = findItemsContainer()

            if not items then
                return rows
            end

            for _, entry in ipairs(items:GetChildren()) do
                local uid = tostring(entry.Name or "")
                local button = entry:FindFirstChild("Button", true)

                if looksLikeUid(uid)
                    and button
                    and button:IsA("GuiButton")
                    and not seen[uid] then

                    seen[uid] = true
                    table.insert(rows, {
                        UID = uid,
                        Button = button,
                        Entry = entry,
                        Source = "GUI",
                    })
                end
            end

            table.sort(rows, function(a, b)
                return a.UID < b.UID
            end)

            return rows
        end

        local function loadRuntimeModules()
            if eggCmdsModule and saveModule then
                return eggCmdsModule, saveModule
            end

            local library = ReplicatedStorage:FindFirstChild("Library")
            local client = library and library:FindFirstChild("Client")

            if not eggCmdsModule and client then
                local moduleScript = client:FindFirstChild("EggCmds")
                if moduleScript and moduleScript:IsA("ModuleScript") then
                    local ok, result = pcall(require, moduleScript)
                    if ok and typeof(result) == "table" then
                        eggCmdsModule = result
                    end
                end
            end

            if not saveModule and client then
                local moduleScript = client:FindFirstChild("Save")
                if moduleScript and moduleScript:IsA("ModuleScript") then
                    local ok, result = pcall(require, moduleScript)
                    if ok and typeof(result) == "table" then
                        saveModule = result
                    end
                end
            end

            return eggCmdsModule, saveModule
        end

        local function collectRuntimeRows(existingRows)
            local rows = existingRows or {}
            local seen = {}

            for _, row in ipairs(rows) do
                seen[tostring(row.UID)] = true
            end

            local eggCmds, saveApi = loadRuntimeModules()

            if eggCmds then
                pcall(function()
                    if typeof(eggCmds.RequestRuntimeSnapshot) == "function" then
                        eggCmds.RequestRuntimeSnapshot()
                    end
                end)

                local ok, snapshot = pcall(function()
                    if typeof(eggCmds.GetRuntimeSnapshot) == "function" then
                        return eggCmds.GetRuntimeSnapshot()
                    end
                    return nil
                end)

                if ok and typeof(snapshot) == "table" then
                    for _, ownerEntry in ipairs(snapshot) do
                        if typeof(ownerEntry) == "table"
                            and tonumber(ownerEntry.OwnerUserId) == tonumber(player.UserId)
                            and typeof(ownerEntry.Records) == "table" then

                            for uid, record in pairs(ownerEntry.Records) do
                                uid = tostring(uid)

                                if uid ~= ""
                                    and typeof(record) == "table"
                                    and record.Placement ~= nil
                                    and not seen[uid] then

                                    seen[uid] = true
                                    table.insert(rows, {
                                        UID = uid,
                                        Record = record,
                                        Source = "Runtime",
                                    })
                                end
                            end
                        end
                    end
                end
            end

            if #rows == 0 and saveApi and typeof(saveApi.Get) == "function" then
                local ok, save = pcall(function()
                    return saveApi.Get(player)
                end)

                if ok and typeof(save) == "table"
                    and typeof(save.EggInventory) == "table" then

                    for uid, record in pairs(save.EggInventory) do
                        uid = tostring(uid)

                        if uid ~= ""
                            and typeof(record) == "table"
                            and record.Placement ~= nil
                            and not seen[uid] then

                            seen[uid] = true
                            table.insert(rows, {
                                UID = uid,
                                Record = record,
                                Source = "Save",
                            })
                        end
                    end
                end
            end

            table.sort(rows, function(a, b)
                return a.UID < b.UID
            end)

            return rows
        end

        local function collectRows()
            -- GUI is authoritative because this is the exact path seen in the
            -- user's successful manual hatch action log.
            local rows = collectGuiRows()

            -- Merge runtime data too. It lets Auto Hatch keep working if the GUI
            -- has not rendered yet or the egg list window is closed/not built.
            return collectRuntimeRows(rows)
        end

        local function fireButton(button)
            if not button or not button.Parent then
                return false
            end

            local fired = false

            if firesignal then
                local ok = pcall(function()
                    firesignal(button.Activated)
                end)

                fired = ok
            end

            return fired
        end

        local function invokeUid(uid)
            local remote = findRemote()
            if not remote then
                return false, "HatchEgg remote not found"
            end

            local ok, result = pcall(function()
                return remote:InvokeServer(uid)
            end)

            if not ok then
                return false, tostring(result)
            end

            -- Some Knit RFs return nil even on success, so nil is NOT treated
            -- as failure. Only an explicit false means the server rejected it.
            if result == false then
                return false, "server returned false"
            end

            return true, result
        end

        local function tryRow(row, force)
            if not row then
                return false
            end

            local uid = tostring(row.UID or "")
            if uid == "" then
                return false
            end

            if not force and claimedUIDs[uid] then
                return false
            end

            local now = os.clock()
            local last = attemptedAt[uid]

            if not force and last and now - last < AUTO_HATCH_UID_COOLDOWN then
                return false
            end

            attemptedAt[uid] = now

            -- AUTO mode: CLAIM means call HatchEgg immediately.
            -- Lock the UID after the first accepted call so a stale hidden
            -- CLAIM label cannot cause duplicate HatchEgg requests.
            if not force then
                local ok = invokeUid(uid)

                if ok then
                    claimedUIDs[uid] = true
                end

                return ok
            end

            -- Manual mode can still reproduce the normal GUI action first.
            if row.Button and row.Button.Parent then
                local entryBefore = row.Entry
                local clicked = fireButton(row.Button)

                if clicked and (not entryBefore or not entryBefore.Parent) then
                    return true
                end
            end

            return invokeUid(uid)
        end

        local hatching = false

        local function run(forceOnePass)
            if not RUNNING or hatching then
                return false
            end

            if not forceOnePass and not State.AutoHatchEggs then
                return false
            end

            -- AUTO MODE HARD GATE:
            -- CLAIM = allowed.
            -- SKIP/GROWING/NONE/SEARCHING = absolutely no click and no HatchEgg RF.
            if not forceOnePass then
                if not State.FirstEggScannerReady then
                    setHatchStatus("ON | waiting for first-egg scanner...")
                    return false
                end

                if State.FirstEggAction ~= "CLAIM" then
                    setHatchStatus(
                        "ON | Action: "
                        .. tostring(State.FirstEggAction)
                        .. " | waiting - no hatch."
                    )
                    return false
                end

                if not State.FirstEggUID or State.FirstEggUID == "" then
                    setHatchStatus("ON | CLAIM detected but first egg UID is missing.")
                    return false
                end
            end

            if State.Busy or State.PlacingEggs or State.CurrentTarget ~= nil then
                return false
            end

            if not findRemote() then
                setHatchStatus("HatchEgg remote not found.")
                return false
            end

            local rows = collectRows()

            -- In AUTO mode only the exact first egg reported as CLAIM may be used.
            -- Never iterate through SKIP/growing rows.
            if not forceOnePass then
                local targetUID = tostring(State.FirstEggUID)
                local targetRow = nil

                for _, row in ipairs(rows) do
                    if tostring(row.UID) == targetUID then
                        targetRow = row
                        break
                    end
                end

                if not targetRow then
                    setHatchStatus(
                        "ON | Action: CLAIM | waiting for matching UID "
                        .. targetUID
                    )
                    return false
                end

                rows = {targetRow}
            end

            if #rows == 0 then
                setHatchStatus("No hatch/claim egg entries detected yet.")
                return false
            end

            hatching = true
            State.HatchingEggs = true

            local accepted = 0

            if forceOnePass then
                setHatchStatus(
                    "Manual hatch pass | detected "
                    .. tostring(#rows)
                    .. " egg(s)."
                )
            else
                setHatchStatus(
                    "ON | Action: CLAIM | UID: "
                    .. tostring(State.FirstEggUID)
                )
            end

            for _, row in ipairs(rows) do
                if not RUNNING then
                    break
                end

                if not forceOnePass then
                    if not State.AutoHatchEggs then
                        break
                    end

                    -- Re-check immediately before firing.
                    -- If CLAIM changed to SKIP while queued, cancel.
                    if State.FirstEggAction ~= "CLAIM"
                        or tostring(State.FirstEggUID or "") ~= tostring(row.UID) then

                        setHatchStatus(
                            "Auto Hatch cancelled: Action changed to "
                            .. tostring(State.FirstEggAction)
                        )
                        break
                    end
                end

                if State.Busy or State.PlacingEggs or State.CurrentTarget ~= nil then
                    break
                end

                if tryRow(row, forceOnePass) then
                    accepted += 1
                end

                if forceOnePass then
                    task.wait(0.03)
                end
            end

            State.HatchingEggs = false
            hatching = false

            task.defer(function()
                if RUNNING then
                    updateFirstGrowingEggAction()

                    if State.AutoHatchEggs then
                        if State.FirstEggAction == "CLAIM" then
                            setHatchStatus(
                                "ON | CLAIM still detected | waiting for next scan."
                            )
                        else
                            setHatchStatus(
                                "ON | Action: "
                                .. tostring(State.FirstEggAction)
                                .. " | waiting."
                            )
                        end
                    end
                end
            end)

            return accepted > 0
        end

        local function watchButton(button)
            if not button or watchedButtons[button] then
                return
            end

            if not button:IsA("GuiButton") or button.Name ~= "Button" then
                return
            end

            local entry = button.Parent
            if not entry or not looksLikeUid(entry.Name) then
                return
            end

            local full = string.lower(button:GetFullName())
            if not string.find(full, "egg_frame", 1, true)
                or not string.find(full, "itemscontainer", 1, true) then
                return
            end

            watchedButtons[button] = true

            -- A visible button by itself is NOT enough.
            -- Only queue Auto Hatch when the live scanner says the FIRST egg is CLAIM
            -- and this button belongs to that exact UID.
            local function queue()
                if RUNNING
                    and State.AutoHatchEggs
                    and State.FirstEggAction == "CLAIM"
                    and tostring(State.FirstEggUID or "") == tostring(entry.Name)
                    and not State.Busy
                    and not State.PlacingEggs
                    and State.CurrentTarget == nil then

                    task.spawn(function()
                        if RUNNING
                            and State.AutoHatchEggs
                            and State.FirstEggAction == "CLAIM"
                            and tostring(State.FirstEggUID or "") == tostring(entry.Name) then

                            run(false)
                        end
                    end)
                end
            end

            pcall(function()
                bind(button:GetPropertyChangedSignal("Visible"), queue)
            end)

            queue()
        end

        -- Watch existing and future hatch UI rows live.
        task.defer(function()
            task.wait(0.05)
            if not RUNNING then
                return
            end

            for _, object in ipairs(playerGui:GetDescendants()) do
                if object:IsA("GuiButton") and object.Name == "Button" then
                    watchButton(object)
                end
            end
        end)

        bind(playerGui.DescendantAdded, function(object)
            if object:IsA("GuiButton") and object.Name == "Button" then
                if RUNNING and object.Parent then
                    watchButton(object)
                end
            end
        end)

        -- Independent live loop. The event watcher above handles ready buttons
        -- quickly; this loop is a fallback for GUI/runtime state changes.
        task.spawn(function()
            while RUNNING do
                task.wait(AUTO_HATCH_SCAN_RATE)

                if State.AutoHatchEggs
                    and State.FirstEggScannerReady
                    and State.FirstEggAction == "CLAIM"
                    and not State.HatchingEggs
                    and not State.Busy
                    and not State.PlacingEggs
                    and State.CurrentTarget == nil then

                    run(false)
                end
            end
        end)

        return {
            FindRemote = findRemote,
            Collect = collectRows,
            Run = run,
        }
    end

    HatchSystem = buildHatchSystem()
end

local function tryAutoPlaceMethod2(reason)
    if not RUNNING
        or not State.AutoPlaceAfterPickup
        or State.PlacingEggs then
        return false
    end

    -- The MAX flag may be left from an earlier full plot. If the actual warning
    -- disappeared after eggs hatched, unlock Method 2 immediately.
    if State.MaxEggLimitReached then
        local warningVisible = isMaxEggLimitVisible()
        if warningVisible then
            return false
        end
        State.MaxEggLimitReached = false
    end

    if checkMaxEggLimitUI() then
        return false
    end

    local hasEggsNow = hasBackpackEggs()
    if not hasEggsNow then
        return false
    end

    local ownedBusy = not State.Busy
    if ownedBusy then
        State.Busy = true
    end

    State.CurrentTarget = nil
    setAutoStatus(reason or "Method 2 -> Auto Place from Backpack.")
    local placed = placeAllBackpackEggs(true, true)

    if ownedBusy then
        State.Busy = false
    end

    return placed
end

local function runAutoPickupCycle()
    if State.Busy or not State.AutoPickup then
        return
    end

    if getSelectedCount() == 0 then
        if State.AutoPlaceAfterPickup then
            setTargetStatus("No TP target selected. Checking Backpack for Method 2...")
            if tryAutoPlaceMethod2("No TP target selected. Method 2 -> Auto Place from Backpack.") then
                return
            end
        end

        setAutoStatus("Select at least one egg in the EGGS tab.")
        return
    end

    local egg, distance = getNearestSelectedEgg()

    if not egg then
        setTargetStatus("No selected egg currently available.")

        -- METHOD 2: no world target -> place anything already in Backpack.
        -- This path intentionally ignores the Growing Eggs counter.
        if State.AutoPlaceAfterPickup then
            tryAutoPlaceMethod2("No TP target available. Method 2 -> Auto Place from Backpack.")
        end

        return
    end

    local info = getEggInfo(egg)

    -- HARD TARGET LOCK.
    -- Do not select another egg until this one is collected, disappears,
    -- or all retries are exhausted.
    State.Busy = true
    State.CurrentTarget = egg

    setTargetStatus(
        string.format(
            "LOCKED: %s | %s | %d studs",
            info and info.EggName or egg.Name,
            info and info.AreaName or "?",
            math.floor(distance or 0)
        )
    )

    local picked = false

    for attempt = 1, AUTO_PICKUP_RETRIES do
        if not RUNNING or not State.AutoPickup then
            break
        end

        if State.CurrentTarget ~= egg then
            break
        end

        if CollectedEggs[egg]
            or not egg.Parent
            or not egg:IsDescendantOf(Workspace) then

            picked = true
            break
        end

        setAutoStatus(
            string.format(
                "TP locked to %s | pickup attempt %d/%d",
                info and info.EggName or egg.Name,
                attempt,
                AUTO_PICKUP_RETRIES
            )
        )

        picked = triggerEggPickup(egg)

        if picked then
            break
        end

        -- Stay on the SAME egg and retry quickly.
        task.wait(0.08)
    end

    if picked then
        setAutoStatus("Pickup confirmed. Returning to your plot...")
        task.wait(RETURN_DELAY)
        returnToMyPlot()
    else
        -- Still return safely, but do not mark the egg collected.
        setAutoStatus("Target pickup timed out. Returning to plot, then retrying.")
        task.wait(RETURN_DELAY)
        returnToMyPlot()
    end

    -- Process the newly collected Backpack egg before releasing the target lock.
    if picked then
        task.wait(0.03)

        if State.AutoPlaceAfterPickup then
            -- METHOD 2 handles stale MAX state itself and intentionally ignores
            -- the Growing Eggs counter.
            tryAutoPlaceMethod2("Pickup returned to plot. Method 2 -> placing egg now.")

        elseif not State.MaxEggLimitReached
            and not checkMaxEggLimitUI()
            and State.AutoPlaceEggs
            and State.GrowingEggCounterReady
            and State.GrowingEggs == 0 then

            -- METHOD 1: preserve the original Growing Eggs == 0 behavior.
            placeAllBackpackEggs(true, false)
        end
    end

    State.CurrentTarget = nil
    State.Busy = false
end

--// LIVE TARGET SCANNER
-- Keeps the Current Target card updated even when Auto Pickup is OFF.
task.spawn(function()
    while RUNNING do
        task.wait(TARGET_SCAN_RATE)

        if not State.Busy then
            local selectedCount = getSelectedCount()

            if selectedCount > 0 then
                local egg, distance = getNearestSelectedEgg()

                if egg then
                    local info = getEggInfo(egg)
                    setTargetStatus(
                        string.format(
                            "LIVE: %s | %s | %d studs",
                            info and info.EggName or egg.Name,
                            info and info.AreaName or "?",
                            math.floor(distance or 0)
                        )
                    )
                else
                    setTargetStatus("LIVE: no selected egg currently available.")
                end
            end
        end
    end
end)

--// BACKGROUND LOOPS
task.spawn(function()
    while RUNNING do
        task.wait(EGG_UPDATE_RATE)

        -- No Egg ESP UI is exposed in this build, so avoid all per-egg visual
        -- maintenance while the feature is OFF.
        if not State.EggESP then
            continue
        end

        local root = getCharacterRoot()
        local playerPosition = root and root.Position or nil

        local keys = {}
        for object in pairs(EggTracked) do
            table.insert(keys, object)
        end

        for _, object in ipairs(keys) do
            local data = EggTracked[object]

            if data then
                if CollectedEggs[object]
                    or not object.Parent
                    or not object:IsDescendantOf(Workspace)
                    or isInsideAnyPlot(object) then

                    removeEggESP(object)
                elseif hasCollectedState(object) and not hasActivePrompt(object) then
                    markCollected(object, "collection state changed")
                else
                    if not data.Part or not data.Part.Parent then
                        data.Part = getObjectPart(object)
                        if data.Part then
                            data.Billboard.Adornee = data.Part
                        end
                    end

                    if data.HadPrompt then
                        local active, hadPromptNow = hasActivePrompt(object)

                        if not active then
                            if not data.PromptMissingSince then
                                data.PromptMissingSince = os.clock()
                            elseif os.clock() - data.PromptMissingSince >= 0.50 then
                                markCollected(
                                    object,
                                    hadPromptNow
                                        and "prompt disabled"
                                        or "prompt disappeared"
                                )
                            end
                        else
                            data.PromptMissingSince = nil
                        end
                    end

                    if EggTracked[object] and data.Part then
                        local distance = playerPosition
                            and (data.Part.Position - playerPosition).Magnitude
                            or 0

                        local visible =
                            State.EggESP
                            and distance <= MAX_ESP_DISTANCE

                        data.Highlight.Enabled = visible
                        data.Billboard.Enabled = visible

                        if visible then
                            local info = data.Info
                            local lines = {
                                info.EggName,
                                info.AreaDisplay,
                                "Chance: " .. tostring(info.Chance) .. "%",
                            }

                            if State.ShowDistance then
                                table.insert(
                                    lines,
                                    "[" .. math.floor(distance) .. " studs]"
                                )
                            end

                            data.Label.Text = table.concat(lines, "\n")
                        end
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while RUNNING do
        task.wait(PLOT_UPDATE_RATE)

        if not State.PlotESP then
            continue
        end

        local root = getCharacterRoot()
        local playerPosition = root and root.Position or nil

        local keys = {}
        for model in pairs(PlotTracked) do
            table.insert(keys, model)
        end

        for _, model in ipairs(keys) do
            local data = PlotTracked[model]

            if data then
                if not model.Parent
                    or not model:IsDescendantOf(PlotsFolder)
                    or isInsideEggModel(model) then

                    removePlotESP(model)
                else
                    local currentPlot = getTopLevelPlot(model)
                    local nowMine = isMyPlot(currentPlot)

                    if not currentPlot then
                        removePlotESP(model)
                    elseif data.Plot ~= currentPlot or data.IsMine ~= nowMine then
                        removePlotESP(model)
                        createPlotESP(model)
                    else
                        if not data.Part or not data.Part.Parent then
                            data.Part = getObjectPart(model)
                            if data.Part then
                                data.Billboard.Adornee = data.Part
                            end
                        end

                        if data.Part then
                            local distance = playerPosition
                                and (data.Part.Position - playerPosition).Magnitude
                                or 0

                            local visible =
                                State.PlotESP
                                and distance <= MAX_ESP_DISTANCE

                            data.Highlight.Enabled = visible
                            data.Billboard.Enabled = visible

                            if visible then
                                local distanceText = State.ShowDistance
                                    and (" [" .. math.floor(distance) .. " studs]")
                                    or ""

                                if data.IsMine then
                                    data.Label.Text =
                                        "★ MY PLOT ★\n"
                                        .. model.Name
                                        .. distanceText
                                else
                                    data.Label.Text =
                                        model.Name
                                        .. (State.ShowDistance
                                            and ("\n[" .. math.floor(distance) .. " studs]")
                                            or "")
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while RUNNING do
        task.wait(RESCAN_RATE)

        -- Fallback validation only; normal detection is event-driven/live.
        -- Avoid expensive full-world work when the related feature is idle.
        if not MyPlot or not MyPlot.Parent or State.PlotESP then
            refreshMyPlotLive("fallback rescan")
        end

        if State.EggESP or State.AutoPickup or getSelectedCount() > 0 then
            scanEggs()
        end

        if State.PlotESP then
            scanAllPlots()
        end
    end
end)

task.spawn(function()
    while RUNNING do
        local selectedCount = getSelectedCount()
        local needEggWork = State.AutoPickup or State.EggESP or selectedCount > 0

        if needEggWork then
            -- Validate only when egg targeting/ESP is actually being used.
            for egg in pairs(LiveEggCandidates) do
                if not egg
                    or not egg.Parent
                    or not egg:IsDescendantOf(Workspace) then

                    LiveEggCandidates[egg] = nil

                elseif getEggInfo(egg) and not isInsideAnyPlot(egg) then
                    if CollectedEggs[egg] then
                        local prompt = getBestEggPrompt(egg)

                        if prompt and prompt.Parent and prompt.Enabled then
                            reviveEgg(egg, "live registry validation")

                            if State.EggESP then
                                reconcileEgg(egg)
                            end
                        end
                    elseif State.EggESP and not EggTracked[egg] then
                        reconcileEgg(egg)
                    end
                end
            end
        end

        if State.AutoPickup and not State.Busy then
            runAutoPickupCycle()
        end

        task.wait(AUTO_LOOP_DELAY)
    end
end)

--// INITIAL SCANS
-- Connect existing prompts in the background so the UI/script does not stall
-- while walking a very large Workspace.
task.spawn(connectAllInstantPrompts)

-- World egg/plot scans are deferred until their feature is actually needed.
-- Workspace.DescendantAdded keeps future objects live in the meantime.
if State.EggESP or getSelectedCount() > 0 then
    scanEggs()
end

if State.PlotESP then
    scanAllPlots()
    refreshMyPlotHighlight()
end

--============================================================
-- ZHM UI TEMPLATE
-- Runs in its own task/function scope to avoid Luau's 200-local-register limit
-- and avoid ambiguous IIFE syntax after the previous function call.
--============================================================

task.spawn(function()

local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 10)
    corner.Parent = parent
    return corner
end

local function addStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or UI_STROKE
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

local function getGuiParents()
    local parents = {}

    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then
            table.insert(parents, hui)
        end
    end

    table.insert(parents, CoreGui)
    table.insert(parents, playerGui)
    return parents
end

local function destroyNamedGui(name)
    for _, parent in ipairs(getGuiParents()) do
        pcall(function()
            local old = parent:FindFirstChild(name)
            if old then
                old:Destroy()
            end
        end)
    end
end

local function mountGui(gui)
    if gethui then
        local ok, hui = pcall(gethui)

        if ok and hui then
            local mounted = pcall(function()
                gui.Parent = hui
            end)

            if mounted and gui.Parent then
                return gui.Parent
            end
        end
    end

    local mounted = pcall(function()
        gui.Parent = CoreGui
    end)

    if not mounted or not gui.Parent then
        gui.Parent = playerGui
    end

    return gui.Parent
end

local function makeDraggable(handle, target)
    target = target or handle

    local dragging = false
    local dragInput
    local dragStart
    local startPosition

    handle.Active = true

    bind(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPosition = target.Position

            bind(input.Changed, function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    bind(handle.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    bind(UserInputService.InputChanged, function(input)
        if dragging and input == dragInput and dragStart and startPosition then
            local delta = input.Position - dragStart

            target.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

local function applyResponsiveScale(scaleObject, baseWidth, baseHeight)
    local viewportConnection
    local cameraConnection

    local function update()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local viewport = camera.ViewportSize
        local widthScale = viewport.X / (baseWidth or 420)
        local heightScale = viewport.Y / (baseHeight or 520)
        local scale = math.clamp(math.min(widthScale, heightScale, 1), 0.55, 1)

        scaleObject.Scale = scale
    end

    local function bindCamera()
        if viewportConnection then
            viewportConnection:Disconnect()
            viewportConnection = nil
        end

        local camera = Workspace.CurrentCamera

        if camera then
            viewportConnection =
                camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
        end

        update()
    end

    bindCamera()

    cameraConnection =
        Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

    return function()
        if viewportConnection then viewportConnection:Disconnect() end
        if cameraConnection then cameraConnection:Disconnect() end
    end
end

--// AUTO UPGRADE + AUTO REBIRTH
-- Observed action-log calls:
--   UpgradesService.RF.Upgrade("CloneCooldown", 1)
--   UpgradesService.RF.Upgrade("MaxClones", 1)
--   UpgradesService.RF.Upgrade("CloneMaxSteal", 1)
--   RebirthService.RF.Rebirth()
local ProgressionSystem = {}

do
    local upgradeRemoteCache = nil
    local rebirthRemoteCache = nil

    local UPGRADE_ORDER = {
        "CloneCooldown",
        "MaxClones",
        "CloneMaxSteal",
    }

    local function hasAncestorNamed(object, targetName)
        local current = object

        while current and current ~= ReplicatedStorage do
            if current.Name == targetName then
                return true
            end
            current = current.Parent
        end

        return false
    end

    local function findKnitRF(serviceName, remoteName)
        local packages = ReplicatedStorage:FindFirstChild("Packages")
        if not packages then
            return nil
        end

        for _, object in ipairs(packages:GetDescendants()) do
            if object:IsA("RemoteFunction")
                and object.Name == remoteName
                and object.Parent
                and object.Parent.Name == "RF"
                and hasAncestorNamed(object, serviceName) then

                return object
            end
        end

        return nil
    end

    local function findUpgradeRemote()
        if upgradeRemoteCache and upgradeRemoteCache.Parent then
            return upgradeRemoteCache
        end

        upgradeRemoteCache = findKnitRF("UpgradesService", "Upgrade")
        return upgradeRemoteCache
    end

    local function findRebirthRemote()
        if rebirthRemoteCache and rebirthRemoteCache.Parent then
            return rebirthRemoteCache
        end

        rebirthRemoteCache = findKnitRF("RebirthService", "Rebirth")
        return rebirthRemoteCache
    end

    local function invokeUpgrade(upgradeName)
        local remote = findUpgradeRemote()

        if not remote then
            return false, "Upgrade remote not found"
        end

        local ok, result = pcall(function()
            return remote:InvokeServer(upgradeName, 1)
        end)

        if not ok then
            upgradeRemoteCache = nil
            return false, tostring(result)
        end

        if result == false then
            return false, "server returned false"
        end

        return true, result
    end

    local function invokeRebirth()
        local remote = findRebirthRemote()

        if not remote then
            return false, "Rebirth remote not found"
        end

        local ok, result = pcall(function()
            return remote:InvokeServer()
        end)

        if not ok then
            rebirthRemoteCache = nil
            return false, tostring(result)
        end

        if result == false then
            return false, "server returned false"
        end

        return true, result
    end

    local function updateStatus(extra)
        local text =
            "Auto Upgrade: "
            .. (State.AutoUpgrade and "ON" or "OFF")
            .. " | Plot Upgrade: "
            .. (State.AutoUpgradePlot and "ON" or "OFF")
            .. " | Auto Rebirth: "
            .. (State.AutoRebirth and "ON" or "OFF")

        if extra and extra ~= "" then
            text = text .. "\n" .. extra
        end

        setProgressionStatus(text)
    end

    local upgradeRunning = false
    local plotUpgradeRunning = false
    local rebirthRunning = false

    local function runUpgradePass(force)
        if upgradeRunning or not RUNNING then
            return false
        end

        if not force and not State.AutoUpgrade then
            return false
        end

        upgradeRunning = true

        local accepted = 0
        local lastInfo = "Upgrade pass finished."

        for _, upgradeName in ipairs(UPGRADE_ORDER) do
            if not RUNNING then
                break
            end

            if not force and not State.AutoUpgrade then
                break
            end

            local ok, result = invokeUpgrade(upgradeName)

            if ok then
                accepted += 1
                lastInfo = "Last upgrade: " .. upgradeName
            else
                lastInfo =
                    "Waiting: "
                    .. upgradeName
                    .. " | "
                    .. tostring(result)
            end

            task.wait(0.06)
        end

        upgradeRunning = false

        updateStatus(
            lastInfo
            .. " | accepted "
            .. tostring(accepted)
            .. "/"
            .. tostring(#UPGRADE_ORDER)
        )

        return accepted > 0
    end

    local function runPlotUpgradePass(force)
        if plotUpgradeRunning or not RUNNING then
            return false
        end

        if not force and not State.AutoUpgradePlot then
            return false
        end

        plotUpgradeRunning = true
        local ok, result = invokeUpgrade("PlotUpgrade")
        plotUpgradeRunning = false

        if ok then
            updateStatus("Plot upgrade request accepted.")
        else
            updateStatus("Plot upgrade waiting: " .. tostring(result))
        end

        return ok
    end

    local function runRebirthPass(force)
        if rebirthRunning or not RUNNING then
            return false
        end

        if not force and not State.AutoRebirth then
            return false
        end

        rebirthRunning = true
        local ok, result = invokeRebirth()
        rebirthRunning = false

        if ok then
            updateStatus("Rebirth request accepted.")
        else
            updateStatus("Rebirth waiting: " .. tostring(result))
        end

        return ok
    end

    task.spawn(function()
        while RUNNING do
            task.wait(AUTO_UPGRADE_RATE)

            if State.AutoUpgrade then
                runUpgradePass(false)
            end
        end
    end)

    task.spawn(function()
        while RUNNING do
            task.wait(AUTO_PLOT_UPGRADE_RATE)

            if State.AutoUpgradePlot then
                runPlotUpgradePass(false)
            end
        end
    end)

    task.spawn(function()
        while RUNNING do
            task.wait(AUTO_REBIRTH_RATE)

            if State.AutoRebirth then
                runRebirthPass(false)
            end
        end
    end)

    ProgressionSystem.FindUpgradeRemote = findUpgradeRemote
    ProgressionSystem.FindRebirthRemote = findRebirthRemote
    ProgressionSystem.RunUpgradePass = runUpgradePass
    ProgressionSystem.RunPlotUpgradePass = runPlotUpgradePass
    ProgressionSystem.RunRebirthPass = runRebirthPass
    ProgressionSystem.UpdateStatus = updateStatus
end

--// TRAIL AUTOMATION
-- Buy order from the supplied action log:
-- Green -> Blue -> Pink -> Yellow -> Red -> Black -> White -> Rainbow
-- Rainbow is treated as the best tier.
State.Trail = {
    Tiers = {
        {Id = "green",   Label = "Green"},
        {Id = "blue",    Label = "Blue"},
        {Id = "pink",    Label = "Pink"},
        {Id = "yellow",  Label = "Yellow"},
        {Id = "red",     Label = "Red"},
        {Id = "black",   Label = "Black"},
        {Id = "white",   Label = "White"},
        {Id = "rainbow", Label = "Rainbow"},
    },
    BuyRemote = nil,
    EquipRemote = nil,
    Buying = false,
    Equipping = false,
    OwnedHints = {},
    BuyRate = 1.25,
    EquipRetryRate = 8.00,
}

function State.Trail.HasAncestor(object, wanted)
    local current = object
    while current and current ~= ReplicatedStorage do
        if current.Name == wanted then
            return true
        end
        current = current.Parent
    end
    return false
end

function State.Trail.FindBuyRemote()
    if State.Trail.BuyRemote and State.Trail.BuyRemote.Parent then
        return State.Trail.BuyRemote
    end

    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return nil
    end

    for _, object in ipairs(packages:GetDescendants()) do
        if (object:IsA("RemoteFunction") or object:IsA("RemoteEvent"))
            and object.Name == "BuyTrail"
            and State.Trail.HasAncestor(object, "TrailService") then

            State.Trail.BuyRemote = object
            return object
        end
    end

    return nil
end

function State.Trail.FindEquipRemote()
    if State.Trail.EquipRemote and State.Trail.EquipRemote.Parent then
        return State.Trail.EquipRemote
    end

    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return nil
    end

    local fallback = nil

    for _, object in ipairs(packages:GetDescendants()) do
        if (object:IsA("RemoteFunction") or object:IsA("RemoteEvent"))
            and State.Trail.HasAncestor(object, "TrailService") then

            local n = string.lower(object.Name)

            if n == "equiptrail" then
                State.Trail.EquipRemote = object
                return object
            end

            if string.find(n, "equip", 1, true)
                and string.find(n, "trail", 1, true) then

                -- Prefer RemoteFunction because it can tell us if the tier
                -- was rejected, allowing best-owned discovery.
                if object:IsA("RemoteFunction") then
                    State.Trail.EquipRemote = object
                    return object
                end

                fallback = fallback or object
            end
        end
    end

    State.Trail.EquipRemote = fallback
    return fallback
end

function State.Trail.Call(remote, value)
    if not remote or not remote.Parent then
        return false, "remote missing"
    end

    if remote:IsA("RemoteFunction") then
        local ok, result = pcall(function()
            return remote:InvokeServer(value)
        end)

        if not ok then
            return false, tostring(result)
        end

        if result == false then
            return false, "server returned false"
        end

        return true, result
    end

    if remote:IsA("RemoteEvent") then
        local ok, err = pcall(function()
            remote:FireServer(value)
        end)

        return ok, err
    end

    return false, "unsupported remote"
end

function State.Trail.BuyPass(force)
    if State.Trail.Buying or not RUNNING then
        return false
    end

    if not force and not State.AutoBuyTrail then
        return false
    end

    local remote = State.Trail.FindBuyRemote()
    if not remote then
        setAutoStatus("Auto Buy Trail: BuyTrail remote not found.")
        return false
    end

    State.Trail.Buying = true
    local accepted = 0

    for _, tier in ipairs(State.Trail.Tiers) do
        if not RUNNING then
            break
        end

        if not force and not State.AutoBuyTrail then
            break
        end

        local ok = State.Trail.Call(remote, tier.Id)

        if ok then
            accepted += 1
            State.Trail.OwnedHints[tier.Id] = true
        end

        task.wait(0.05)
    end

    State.Trail.Buying = false

    if State.AutoEquipTrail then
        task.defer(State.Trail.EquipBest)
    end

    setAutoStatus(
        "Trail buy pass: "
        .. tostring(accepted)
        .. "/"
        .. tostring(#State.Trail.Tiers)
        .. " accepted | best: Rainbow"
    )

    return accepted > 0
end

function State.Trail.EquipBest()
    if State.Trail.Equipping or not RUNNING or not State.AutoEquipTrail then
        return false
    end

    local remote = State.Trail.FindEquipRemote()

    if not remote then
        setAutoStatus("Auto Equip Trail: equip remote not found yet.")
        return false
    end

    State.Trail.Equipping = true

    -- RemoteFunction: probe from BEST -> WORST. First accepted tier is the
    -- highest trail the server says you can equip.
    if remote:IsA("RemoteFunction") then
        for i = #State.Trail.Tiers, 1, -1 do
            local tier = State.Trail.Tiers[i]
            local ok = State.Trail.Call(remote, tier.Id)

            if ok then
                State.Trail.OwnedHints[tier.Id] = true
                State.Trail.Equipping = false
                setAutoStatus("Best trail equipped: " .. tier.Label)
                return true
            end
        end

        State.Trail.Equipping = false
        setAutoStatus("No owned trail accepted by equip remote.")
        return false
    end

    -- RemoteEvent cannot report rejection. Use the highest tier we have a
    -- purchase/ownership hint for rather than blindly firing every tier.
    for i = #State.Trail.Tiers, 1, -1 do
        local tier = State.Trail.Tiers[i]

        if State.Trail.OwnedHints[tier.Id] then
            local ok = State.Trail.Call(remote, tier.Id)
            State.Trail.Equipping = false

            if ok then
                setAutoStatus("Best known trail equipped: " .. tier.Label)
                return true
            end

            return false
        end
    end

    State.Trail.Equipping = false
    setAutoStatus("Trail equip remote found, but owned tier is not known yet.")
    return false
end

task.spawn(function()
    while RUNNING do
        if State.AutoBuyTrail then
            task.wait(State.Trail.BuyRate)

            if RUNNING and State.AutoBuyTrail then
                State.Trail.BuyPass(false)
            end

        elseif State.AutoEquipTrail then
            -- Auto Equip used to probe the server every second even when nothing
            -- changed. A slower retry preserves recovery without remote spam.
            task.wait(State.Trail.EquipRetryRate)

            if RUNNING and State.AutoEquipTrail and not State.AutoBuyTrail then
                State.Trail.EquipBest()
            end

        else
            task.wait(1.00)
        end
    end
end)

--// AUTO SELL: ANIMALS / BRAINROTS + EGGS
-- Uses the confirmed InventoryService RF calls from the supplied working scripts:
--   SellBrainrot:InvokeServer(UUID)
--   SellEgg:InvokeServer(UUID)
-- Kept inside State.Sell so the main chunk does not gain a large number of locals.
State.Sell = {
    AnimalEnabled = false,
    EggEnabled = false,
    SellingAnimals = false,
    SellingEggs = false,
    SelectedAnimals = {},
    SelectedMutations = {},
    SelectedEggs = {},
    AnimalOptions = {},
    MutationOptions = {},
    EggOptions = {},
    AnimalBaseSet = {},
    EggMap = {},
    SellBrainrot = nil,
    SellEgg = nil,
    StatusCard = nil,
    Interval = 2.00,
    SellDelay = 0.12,
    KnownMutations = {"Diamond", "Gold", "Radioactive", "Rainbow"},
    NameFields = {
        "BrainrotName", "AnimalName", "PetName", "ItemName", "DisplayName",
        "Species", "Brainrot", "Animal", "Pet", "Type",
    },
    MutationFields = {
        "Mutation", "MutationName", "MutationType", "Variant", "VariantName",
        "Trait", "TraitName",
    },
    UUIDFields = {
        "UUID", "Uuid", "uuid", "UID", "Uid", "uid", "GUID", "Guid", "guid",
        "BrainrotUUID", "BrainrotUuid", "BrainrotId", "BrainrotID",
        "AnimalId", "AnimalID", "EggUUID", "EggUuid", "EggId", "EggID",
        "ItemUUID", "ItemId", "ItemID", "PetId", "PetID", "Id", "ID",
    },
    EggNameFields = {
        "EggName", "EggType", "ItemName", "DisplayName", "ModelName", "Egg", "Type", "Name",
    },
}

function State.Sell.Lower(value)
    return string.lower(tostring(value or ""))
end

function State.Sell.Trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function State.Sell.Title(value)
    return tostring(value or ""):gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end)
end

function State.Sell.Count(tbl)
    local count = 0
    for _, value in pairs(tbl or {}) do
        if value then count += 1 end
    end
    return count
end

function State.Sell.SetStatus(message)
    message = tostring(message or "")
    if State.Sell.StatusCard then
        State.Sell.StatusCard.SetText(message)
    end
    print("[ZHM AutoSell] " .. message)
end

function State.Sell.IsUUID(value)
    value = tostring(value or "")
    return value:match(
        "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    ) ~= nil
end

function State.Sell.ReadField(object, fields)
    if not object then return nil end

    for _, field in ipairs(fields or {}) do
        local ok, value = pcall(function()
            return object:GetAttribute(field)
        end)
        if ok and value ~= nil then
            return value
        end
    end

    for _, field in ipairs(fields or {}) do
        local child = object:FindFirstChild(field)
        if child and child:IsA("ValueBase") then
            local ok, value = pcall(function() return child.Value end)
            if ok and value ~= nil then
                return value
            end
        end
    end

    return nil
end

function State.Sell.UUIDOnObject(object)
    if not object then return nil end
    if State.Sell.IsUUID(object.Name) then return tostring(object.Name) end

    for _, field in ipairs(State.Sell.UUIDFields) do
        local ok, value = pcall(function()
            return object:GetAttribute(field)
        end)
        if ok and State.Sell.IsUUID(value) then
            return tostring(value)
        end
    end

    local ok, attrs = pcall(function() return object:GetAttributes() end)
    if ok and attrs then
        for _, value in pairs(attrs) do
            if State.Sell.IsUUID(value) then
                return tostring(value)
            end
        end
    end

    for _, child in ipairs(object:GetChildren()) do
        if child:IsA("ValueBase") then
            local valueOk, value = pcall(function() return child.Value end)
            if valueOk and State.Sell.IsUUID(value) then
                return tostring(value)
            end
        end
    end

    return nil
end

function State.Sell.GetUUID(object)
    if not object then return nil end

    local uuid = State.Sell.UUIDOnObject(object)
    if uuid then return uuid end

    for _, descendant in ipairs(object:GetDescendants()) do
        uuid = State.Sell.UUIDOnObject(descendant)
        if uuid then return uuid end
    end

    local parent = object.Parent
    local depth = 0
    while parent and depth < 7 do
        uuid = State.Sell.UUIDOnObject(parent)
        if uuid then return uuid end
        if parent == player or parent == ReplicatedStorage or parent == game then
            break
        end
        parent = parent.Parent
        depth += 1
    end

    return nil
end

function State.Sell.FindInventoryRemote(remoteName)
    local cached = remoteName == "SellEgg" and State.Sell.SellEgg or State.Sell.SellBrainrot
    if cached and cached.Parent then return cached end

    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then return nil end

    for _, object in ipairs(packages:GetDescendants()) do
        if object:IsA("RemoteFunction") and object.Name == remoteName then
            local full = State.Sell.Lower(object:GetFullName())
            if string.find(full, "inventoryservice", 1, true)
                and string.find(full, ".rf.", 1, true) then
                if remoteName == "SellEgg" then
                    State.Sell.SellEgg = object
                else
                    State.Sell.SellBrainrot = object
                end
                return object
            end
        end
    end

    return nil
end

function State.Sell.GetInventoryRoots()
    local roots = {}
    local used = {}

    local function add(object)
        if object and not used[object] then
            used[object] = true
            table.insert(roots, object)
        end
    end

    for _, name in ipairs({
        "Inventory", "Inventories", "Brainrot", "Brainrots", "Animal", "Animals",
        "Pet", "Pets", "Egg", "Eggs", "Items", "Data", "PlayerData", "Profile",
    }) do
        add(player:FindFirstChild(name))
    end

    add(player:FindFirstChild("Backpack"))
    add(player.Character)

    for _, containerName in ipairs({
        "PlayerData", "Players", "Inventory", "Inventories", "Profiles", "PlayerProfiles",
    }) do
        local container = ReplicatedStorage:FindFirstChild(containerName)
        if container then
            add(container:FindFirstChild(player.Name))
            add(container:FindFirstChild(tostring(player.UserId)))
        end
    end

    return roots
end

function State.Sell.MutationFromName(name)
    local lowered = State.Sell.Lower(name)
    for _, mutation in ipairs(State.Sell.KnownMutations) do
        local m = State.Sell.Lower(mutation)
        for _, pattern in ipairs({m .. "_", m .. "-", m .. " ", "_" .. m, "-" .. m, " " .. m}) do
            if string.find(lowered, pattern, 1, true) then
                return mutation
            end
        end
    end
    return nil
end

function State.Sell.StripMutation(name)
    name = State.Sell.Trim(name)

    for _, mutation in ipairs(State.Sell.KnownMutations) do
        local m = State.Sell.Lower(mutation)
        local current = State.Sell.Lower(name)
        for _, prefix in ipairs({m .. "_", m .. "-", m .. " "}) do
            if string.sub(current, 1, #prefix) == prefix then
                name = string.sub(name, #prefix + 1)
                break
            end
        end
    end

    for _, mutation in ipairs(State.Sell.KnownMutations) do
        local m = State.Sell.Lower(mutation)
        local current = State.Sell.Lower(name)
        for _, suffix in ipairs({"_" .. m, "-" .. m, " " .. m}) do
            if #current >= #suffix and string.sub(current, -#suffix) == suffix then
                name = string.sub(name, 1, #name - #suffix)
                break
            end
        end
    end

    return State.Sell.Trim(name)
end

function State.Sell.BaseAnimalName(name)
    name = State.Sell.StripMutation(name)
    name = name:gsub("_", " "):gsub("%-", " "):gsub("%s+", " ")
    name = State.Sell.Trim(name)
    if name == "" or State.Sell.IsUUID(name) then return nil end

    local words = {}
    for word in string.gmatch(name, "%S+") do
        table.insert(words, word)
    end
    if #words == 0 then return nil end

    -- Matches the supplied smart matcher: Dark Sentinel / Azure Sentinel -> Sentinel.
    return State.Sell.Title(words[#words])
end

function State.Sell.IsGenericAnimalName(name)
    local lowered = State.Sell.Lower(name)
    for _, value in ipairs({
        "animal", "animals", "brainrot", "brainrots", "pet", "pets", "inventory",
        "inventories", "item", "items", "data", "profile", "folder", "models",
        "mutation", "mutations", "variant", "variants", "config", "configuration",
    }) do
        if lowered == value then return true end
    end
    return false
end

function State.Sell.GetAnimalRawName(object)
    local value = State.Sell.ReadField(object, State.Sell.NameFields)
    if value ~= nil then
        value = State.Sell.Trim(value)
        if value ~= "" and not State.Sell.IsUUID(value) then return value end
    end

    if not State.Sell.IsGenericAnimalName(object.Name) and not State.Sell.IsUUID(object.Name) then
        return object.Name
    end

    return nil
end

function State.Sell.GetMutation(object, rawName)
    local value = State.Sell.ReadField(object, State.Sell.MutationFields)
    if value ~= nil then
        local text = State.Sell.Trim(value)
        local lowered = State.Sell.Lower(text)
        if lowered == "" or lowered == "none" or lowered == "nil"
            or lowered == "default" or lowered == "normal" then
            return "Normal"
        end
        for _, mutation in ipairs(State.Sell.KnownMutations) do
            if State.Sell.Lower(mutation) == lowered then return mutation end
        end
        return State.Sell.Title(text)
    end

    return State.Sell.MutationFromName(object.Name)
        or State.Sell.MutationFromName(rawName)
        or "Normal"
end

function State.Sell.PathLooksAnimal(object)
    local current = object
    local depth = 0
    while current and depth < 5 do
        local n = State.Sell.Lower(current.Name)
        if string.find(n, "brainrot", 1, true)
            or string.find(n, "animal", 1, true)
            or string.find(n, "pet", 1, true) then
            return true
        end
        current = current.Parent
        depth += 1
    end
    return false
end

function State.Sell.ScanAnimalCatalog()
    local options, seen = {}, {}

    local function add(value)
        value = State.Sell.Trim(value)
        if value == "" then return end
        local key = State.Sell.Lower(value)
        if seen[key] then return end
        seen[key] = true
        table.insert(options, value)
    end

    for _, object in ipairs(ReplicatedStorage:GetDescendants()) do
        if object:IsA("Folder") or object:IsA("Model") or object:IsA("Configuration") then
            local parent = object.Parent
            if parent then
                local context = State.Sell.Lower(parent.Name)
                if parent.Parent then
                    context = context .. " " .. State.Sell.Lower(parent.Parent.Name)
                end
                if string.find(context, "brainrot", 1, true)
                    or string.find(context, "animal", 1, true)
                    or string.find(context, "pet", 1, true) then
                    if not State.Sell.IsGenericAnimalName(object.Name)
                        and not State.Sell.IsUUID(object.Name) then
                        local base = State.Sell.BaseAnimalName(object.Name)
                        if base then add(base) end
                    end
                end
            end
        end
    end

    table.sort(options, function(a, b) return State.Sell.Lower(a) < State.Sell.Lower(b) end)

    State.Sell.AnimalBaseSet = {}
    for _, value in ipairs(options) do
        State.Sell.AnimalBaseSet[State.Sell.Lower(value)] = true
    end
    return options
end

function State.Sell.ScanAnimals()
    local records, used = {}, {}

    for _, root in ipairs(State.Sell.GetInventoryRoots()) do
        local objects = {root}
        for _, descendant in ipairs(root:GetDescendants()) do
            table.insert(objects, descendant)
        end

        for _, object in ipairs(objects) do
            if object:IsA("Folder") or object:IsA("Model") or object:IsA("Tool")
                or object:IsA("Configuration") then
                local raw = State.Sell.GetAnimalRawName(object)
                if raw then
                    local base = State.Sell.BaseAnimalName(raw)
                    local baseKey = base and State.Sell.Lower(base) or ""
                    local explicitField = State.Sell.ReadField(object, State.Sell.NameFields) ~= nil
                        or State.Sell.ReadField(object, State.Sell.MutationFields) ~= nil
                    local likelyAnimal = explicitField or State.Sell.PathLooksAnimal(object)
                        or State.Sell.AnimalBaseSet[baseKey] == true

                    if base and likelyAnimal and baseKey ~= "egg" then
                        local uuid = State.Sell.GetUUID(object)
                        local key = uuid and ("UUID:" .. uuid) or object:GetFullName()
                        if not used[key] then
                            used[key] = true
                            table.insert(records, {
                                instance = object,
                                rawName = raw,
                                baseName = base,
                                mutation = State.Sell.GetMutation(object, raw),
                                uuid = uuid,
                            })
                        end
                    end
                end
            end
        end
    end

    return records
end

function State.Sell.CleanEggName(raw)
    local name = State.Sell.Lower(State.Sell.Trim(raw))
    name = name:gsub("_", " "):gsub("%-", " "):gsub("%s+", " ")
    name = State.Sell.Trim(name)
    name = name:gsub("%s+egg$", ""):gsub("^egg%s+", "")
    name = State.Sell.Trim(name)
    if name == "" then return nil end
    return State.Sell.Title(name)
end

function State.Sell.ScanEggCatalog()
    local options, seen = {}, {}
    State.Sell.EggMap = {}

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local eggModels = assets and assets:FindFirstChild("EggModels")
    if not eggModels then return options end

    for _, object in ipairs(eggModels:GetChildren()) do
        local display = State.Sell.CleanEggName(object.Name)
        if display then
            local key = State.Sell.Lower(display)
            if not seen[key] then
                seen[key] = true
                local info = {raw = object.Name, display = display}
                table.insert(options, display)
                State.Sell.EggMap[key] = info
                State.Sell.EggMap[State.Sell.Lower(object.Name)] = info
            end
        end
    end

    table.sort(options, function(a, b) return State.Sell.Lower(a) < State.Sell.Lower(b) end)
    return options
end

function State.Sell.IdentifyEggText(text)
    if text == nil then return nil end
    local rawKey = State.Sell.Lower(State.Sell.Trim(text))
    local direct = State.Sell.EggMap[rawKey]
    if direct then return direct end
    local cleaned = State.Sell.CleanEggName(text)
    return cleaned and State.Sell.EggMap[State.Sell.Lower(cleaned)] or nil
end

function State.Sell.IdentifyEggObject(object)
    local egg = State.Sell.IdentifyEggText(object.Name)
    if egg then return egg end

    for _, field in ipairs(State.Sell.EggNameFields) do
        local value = State.Sell.ReadField(object, {field})
        egg = State.Sell.IdentifyEggText(value)
        if egg then return egg end
    end

    if object:IsA("StringValue") then
        egg = State.Sell.IdentifyEggText(object.Value)
        if egg then return egg end
    end

    return nil
end

function State.Sell.ScanEggs()
    local records, used = {}, {}

    for _, root in ipairs(State.Sell.GetInventoryRoots()) do
        local objects = {root}
        for _, descendant in ipairs(root:GetDescendants()) do
            table.insert(objects, descendant)
        end

        for _, object in ipairs(objects) do
            local egg = State.Sell.IdentifyEggObject(object)
            if egg then
                local uuid = State.Sell.GetUUID(object)
                local key = uuid and ("UUID:" .. uuid) or object:GetFullName()
                if not used[key] then
                    used[key] = true
                    table.insert(records, {
                        instance = object,
                        display = egg.display,
                        raw = egg.raw,
                        uuid = uuid,
                    })
                end
            end
        end
    end

    return records
end

function State.Sell.BuildCatalogs()
    local animals = State.Sell.ScanAnimalCatalog()
    local animalSeen = {}
    for _, value in ipairs(animals) do animalSeen[State.Sell.Lower(value)] = true end

    local animalRecords = State.Sell.ScanAnimals()
    for _, record in ipairs(animalRecords) do
        local key = State.Sell.Lower(record.baseName)
        if not animalSeen[key] then
            animalSeen[key] = true
            table.insert(animals, record.baseName)
            State.Sell.AnimalBaseSet[key] = true
        end
    end
    table.sort(animals, function(a, b) return State.Sell.Lower(a) < State.Sell.Lower(b) end)

    local mutations, mutationSeen = {}, {}
    local function addMutation(value)
        value = tostring(value or "")
        local key = State.Sell.Lower(value)
        if value ~= "" and not mutationSeen[key] then
            mutationSeen[key] = true
            table.insert(mutations, value)
        end
    end
    addMutation("Normal")
    for _, mutation in ipairs(State.Sell.KnownMutations) do addMutation(mutation) end
    for _, record in ipairs(animalRecords) do addMutation(record.mutation) end

    local eggs = State.Sell.ScanEggCatalog()

    State.Sell.AnimalOptions = {}
    for _, value in ipairs(animals) do
        table.insert(State.Sell.AnimalOptions, {Value = value, Label = value})
    end

    State.Sell.MutationOptions = {}
    for _, value in ipairs(mutations) do
        table.insert(State.Sell.MutationOptions, {Value = value, Label = value})
    end

    State.Sell.EggOptions = {}
    for _, value in ipairs(eggs) do
        table.insert(State.Sell.EggOptions, {Value = value, Label = value})
    end

    return #animals, #mutations, #eggs
end

function State.Sell.CallRemote(remote, uuid)
    if not remote or not remote.Parent or not State.Sell.IsUUID(uuid) then
        return false
    end

    local ok, result = pcall(function()
        return remote:InvokeServer(tostring(uuid))
    end)

    if not ok then
        warn("[ZHM AutoSell] Sell remote error:", result)
        return false
    end

    return result ~= false
end

function State.Sell.SellAnimalsOnce(force)
    if State.Sell.SellingAnimals or not RUNNING then return false end
    if not force and not State.Sell.AnimalEnabled then return false end

    if State.Sell.Count(State.Sell.SelectedAnimals) == 0 then
        State.Sell.SetStatus("Animal Auto Sell waiting: select at least one animal.")
        return false
    end
    if State.Sell.Count(State.Sell.SelectedMutations) == 0 then
        State.Sell.SetStatus("Animal Auto Sell waiting: select at least one mutation.")
        return false
    end

    local remote = State.Sell.FindInventoryRemote("SellBrainrot")
    if not remote then
        State.Sell.SetStatus("SellBrainrot remote not found.")
        return false
    end

    State.Sell.SellingAnimals = true
    local records = State.Sell.ScanAnimals()
    local matched, sold, missing = 0, 0, 0

    for _, record in ipairs(records) do
        if not RUNNING then break end
        local animalMatch = State.Sell.SelectedAnimals[record.baseName] == true
        local mutationMatch = State.Sell.SelectedMutations[record.mutation] == true
        if animalMatch and mutationMatch then
            matched += 1
            local uuid = record.uuid or State.Sell.GetUUID(record.instance)
            if uuid then
                State.Sell.SetStatus(
                    "Selling animal: " .. record.baseName .. " | " .. record.mutation
                )
                if State.Sell.CallRemote(remote, uuid) then sold += 1 end
                task.wait(State.Sell.SellDelay)
            else
                missing += 1
            end
        end
    end

    State.Sell.SellingAnimals = false
    State.Sell.SetStatus(
        "Animals matched: " .. matched .. " | sold: " .. sold .. " | missing UUID: " .. missing
    )
    return sold > 0
end

function State.Sell.SellEggsOnce(force)
    if State.Sell.SellingEggs or not RUNNING then return false end
    if not force and not State.Sell.EggEnabled then return false end

    if State.Sell.Count(State.Sell.SelectedEggs) == 0 then
        State.Sell.SetStatus("Egg Auto Sell waiting: select at least one egg.")
        return false
    end

    local remote = State.Sell.FindInventoryRemote("SellEgg")
    if not remote then
        State.Sell.SetStatus("SellEgg remote not found.")
        return false
    end

    State.Sell.SellingEggs = true
    local records = State.Sell.ScanEggs()
    local matched, sold, missing = 0, 0, 0

    for _, record in ipairs(records) do
        if not RUNNING then break end
        if State.Sell.SelectedEggs[record.display] == true then
            matched += 1
            local uuid = record.uuid or State.Sell.GetUUID(record.instance)
            if uuid then
                State.Sell.SetStatus("Selling egg: " .. record.display)
                if State.Sell.CallRemote(remote, uuid) then sold += 1 end
                task.wait(State.Sell.SellDelay)
            else
                missing += 1
            end
        end
    end

    State.Sell.SellingEggs = false
    State.Sell.SetStatus(
        "Eggs matched: " .. matched .. " | sold: " .. sold .. " | missing UUID: " .. missing
    )
    return sold > 0
end

-- Build static dropdown catalogs once before the UI is created.
do
    local ok, animals, mutations, eggs = pcall(State.Sell.BuildCatalogs)
    if ok then
        print("[ZHM AutoSell] Dropdowns:", animals, "animals |", mutations, "mutations |", eggs, "eggs")
    else
        warn("[ZHM AutoSell] Initial catalog scan failed:", animals)
    end
end

-- Shared auto-sell loop. Both features can be ON at the same time.
task.spawn(function()
    while RUNNING do
        task.wait(State.Sell.Interval)

        if State.Sell.AnimalEnabled then
            State.Sell.SellAnimalsOnce(false)
        end

        if State.Sell.EggEnabled then
            State.Sell.SellEggsOnce(false)
        end
    end
end)

--// CLEAN OLD GUI
destroyNamedGui(GUI_NAME)

--// ROOT GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 9999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mountGui(screenGui)

--// MAIN WINDOW
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Size = UDim2.new(0, 380, 0, 460)
mainFrame.Position = UDim2.new(0.28, 0, 0.20, 0)
mainFrame.BackgroundColor3 = UI_BG
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
addCorner(mainFrame, 10)
addStroke(mainFrame, UI_STROKE, 1, 0.15)

local mainScale = Instance.new("UIScale")
mainScale.Scale = 1
mainScale.Parent = mainFrame

local disconnectResponsiveScale =
    applyResponsiveScale(mainScale, 410, 500)

--// HEADER
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = UI_PANEL
header.BorderSizePixel = 0
header.Parent = mainFrame
addCorner(header, 10)

local headerMask = Instance.new("Frame")
headerMask.Name = "HeaderMask"
headerMask.Size = UDim2.new(1, 0, 0, 10)
headerMask.Position = UDim2.new(0, 0, 1, -10)
headerMask.BackgroundColor3 = UI_PANEL
headerMask.BorderSizePixel = 0
headerMask.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -92, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = HUB_TITLE
titleLabel.TextColor3 = UI_TEXT
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name = "Minimize"
minimizeBtn.Size = UDim2.new(0, 30, 0, 26)
minimizeBtn.Position = UDim2.new(1, -68, 0, 9)
minimizeBtn.BackgroundColor3 = UI_PANEL_2
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = UI_TEXT
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 15
minimizeBtn.Parent = header
addCorner(minimizeBtn, 7)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.new(0, 30, 0, 26)
closeBtn.Position = UDim2.new(1, -34, 0, 9)
closeBtn.BackgroundColor3 = UI_PANEL_2
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = UI_DANGER
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.Parent = header
addCorner(closeBtn, 7)

makeDraggable(header, mainFrame)

--// BODY
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, -16, 1, -52)
body.Position = UDim2.new(0, 8, 0, 48)
body.BackgroundTransparency = 1
body.Parent = mainFrame

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, 0, 0, 32)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar

local pageHost = Instance.new("Frame")
pageHost.Name = "Pages"
pageHost.Size = UDim2.new(1, 0, 1, -38)
pageHost.Position = UDim2.new(0, 0, 0, 38)
pageHost.BackgroundTransparency = 1
pageHost.ClipsDescendants = true
pageHost.Parent = body

local pages = {}
local tabButtons = {}
local TAB_COUNT = #TAB_DEFINITIONS

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 2
    page.ScrollBarImageColor3 = UI_ACCENT
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = pageHost

    local padding = Instance.new("UIPadding")
    padding.PaddingBottom = UDim.new(0, 6)
    padding.Parent = page

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = page

    pages[name] = page
    return page
end

local function createTab(name, label)
    local button = Instance.new("TextButton")
    button.Name = name .. "Tab"
    button.Size = UDim2.new(1 / TAB_COUNT, -3, 1, 0)
    button.BackgroundColor3 = UI_PANEL
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Text = label
    button.TextColor3 = UI_MUTED
    button.Font = Enum.Font.GothamBold
    button.TextSize = 9
    button.Parent = tabBar
    addCorner(button, 7)

    tabButtons[name] = button
    return button
end

local function setActivePage(name)
    for pageName, page in pairs(pages) do
        page.Visible = pageName == name
    end

    for tabName, button in pairs(tabButtons) do
        local selected = tabName == name
        button.BackgroundColor3 = selected and UI_ACCENT or UI_PANEL
        button.TextColor3 = selected
            and Color3.fromRGB(255, 255, 255)
            or UI_MUTED
    end
end

local function createSection(parent, title)
    local label = Instance.new("TextLabel")
    label.Name = title:gsub("%s+", "") .. "Section"
    label.Size = UDim2.new(1, 0, 0, 24)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = UI_MUTED
    label.Font = Enum.Font.GothamBold
    label.TextSize = 9
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function createToggle(parent, title, description, defaultValue, callback)
    local enabled = defaultValue == true

    local row = Instance.new("Frame")
    row.Name = title:gsub("%W+", "") .. "Toggle"
    row.Size = UDim2.new(1, 0, 0, description and 50 or 42)
    row.BackgroundColor3 = UI_PANEL
    row.BorderSizePixel = 0
    row.Parent = parent
    addCorner(row, 8)
    addStroke(row, UI_STROKE, 1, 0.45)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -82, 0, 18)
    label.Position = UDim2.new(0, 10, 0, description and 6 or 11)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = UI_TEXT
    label.Font = Enum.Font.GothamBold
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    if description then
        local desc = Instance.new("TextLabel")
        desc.Size = UDim2.new(1, -82, 0, 18)
        desc.Position = UDim2.new(0, 10, 0, 25)
        desc.BackgroundTransparency = 1
        desc.Text = description
        desc.TextColor3 = UI_MUTED
        desc.Font = Enum.Font.Gotham
        desc.TextSize = 7
        desc.TextTruncate = Enum.TextTruncate.AtEnd
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.Parent = row
    end

    local switch = Instance.new("TextButton")
    switch.Name = "Switch"
    switch.Size = UDim2.new(0, 54, 0, 28)
    switch.Position = UDim2.new(1, -64, 0.5, -14)
    switch.BorderSizePixel = 0
    switch.AutoButtonColor = true
    switch.Font = Enum.Font.GothamBold
    switch.TextSize = 9
    switch.Parent = row
    addCorner(switch, 7)

    local function refresh()
        switch.Text = enabled and "ON" or "OFF"
        switch.BackgroundColor3 = enabled and UI_ACCENT or UI_PANEL_2
        switch.TextColor3 = enabled
            and Color3.fromRGB(255, 255, 255)
            or UI_MUTED
    end

    bind(switch.Activated, function()
        enabled = not enabled
        refresh()

        if callback then
            task.spawn(callback, enabled)
        end
    end)

    refresh()

    local controller = {
        Row = row,
        Switch = switch,
        Get = function()
            return enabled
        end,
        Set = function(value)
            enabled = value == true
            refresh()

            if callback then
                task.spawn(callback, enabled)
            end
        end,
        Refresh = refresh,
    }

    State.ConfigRegistry.Toggles[title] = controller
    return controller
end

local function createButton(parent, text, callback)
    local button = Instance.new("TextButton")
    button.Name = text:gsub("%W+", "") .. "Button"
    button.Size = UDim2.new(1, 0, 0, 38)
    button.BackgroundColor3 = UI_PANEL
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = UI_TEXT
    button.Font = Enum.Font.GothamBold
    button.TextSize = 10
    button.Parent = parent
    addCorner(button, 8)
    addStroke(button, UI_STROKE, 1, 0.45)

    bind(button.Activated, function()
        if callback then
            task.spawn(callback)
        end
    end)

    return button
end


local function createTextInput(parent, title, placeholder, defaultValue)
    local card = Instance.new("Frame")
    card.Name = title:gsub("%W+", "") .. "Input"
    card.Size = UDim2.new(1, 0, 0, 58)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 16)
    label.Position = UDim2.new(0, 10, 0, 5)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = UI_TEXT
    label.Font = Enum.Font.GothamBold
    label.TextSize = 9
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local box = Instance.new("TextBox")
    box.Name = "Value"
    box.Size = UDim2.new(1, -20, 0, 27)
    box.Position = UDim2.new(0, 10, 0, 25)
    box.BackgroundColor3 = UI_PANEL_2
    box.BorderSizePixel = 0
    box.Text = tostring(defaultValue or "")
    box.PlaceholderText = tostring(placeholder or "")
    box.PlaceholderColor3 = UI_MUTED
    box.TextColor3 = UI_TEXT
    box.Font = Enum.Font.GothamMedium
    box.TextSize = 9
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.Parent = card
    addCorner(box, 7)

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = box

    return {
        Card = card,
        Box = box,
        Get = function()
            return tostring(box.Text or "")
        end,
        Set = function(value)
            box.Text = tostring(value or "")
        end,
    }
end

local function createInfoCard(parent, title, textValue, height)
    local card = Instance.new("Frame")
    card.Name = title:gsub("%W+", "") .. "Info"
    card.Size = UDim2.new(1, 0, 0, height or 62)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -20, 0, 17)
    titleText.Position = UDim2.new(0, 10, 0, 7)
    titleText.BackgroundTransparency = 1
    titleText.Text = title
    titleText.TextColor3 = UI_TEXT
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 9
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = card

    local value = Instance.new("TextLabel")
    value.Size = UDim2.new(1, -20, 1, -27)
    value.Position = UDim2.new(0, 10, 0, 24)
    value.BackgroundTransparency = 1
    value.Text = textValue or "Ready"
    value.TextColor3 = UI_MUTED
    value.Font = Enum.Font.Gotham
    value.TextSize = 8
    value.TextWrapped = true
    value.TextXAlignment = Enum.TextXAlignment.Left
    value.TextYAlignment = Enum.TextYAlignment.Top
    value.Parent = card

    return {
        Card = card,
        Label = value,
        SetText = function(text)
            value.Text = tostring(text or "")
        end,
    }
end

--// MULTI-SELECT DROPDOWN
-- Search + Select All + Deselect All are built into EVERY multi-select dropdown.
local function createMultiSelect(parent, title, options, defaultSelected, callback, noun)
    local selected = {}
    local expanded = false
    local searchQuery = ""
    noun = tostring(noun or "items")

    for key, value in pairs(defaultSelected or {}) do
        if value then
            selected[key] = true
        end
    end

    local card = Instance.new("Frame")
    card.Name = title:gsub("%W+", "") .. "MultiSelect"
    card.Size = UDim2.new(1, 0, 0, 52)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -20, 0, 16)
    titleText.Position = UDim2.new(0, 10, 0, 5)
    titleText.BackgroundTransparency = 1
    titleText.Text = title
    titleText.TextColor3 = UI_TEXT
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 9
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = card

    local headerButton = Instance.new("TextButton")
    headerButton.Size = UDim2.new(1, -20, 0, 24)
    headerButton.Position = UDim2.new(0, 10, 0, 23)
    headerButton.BackgroundColor3 = UI_PANEL_2
    headerButton.BorderSizePixel = 0
    headerButton.TextColor3 = UI_MUTED
    headerButton.Font = Enum.Font.GothamMedium
    headerButton.TextSize = 8
    headerButton.TextXAlignment = Enum.TextXAlignment.Left
    headerButton.Parent = card
    addCorner(headerButton, 7)

    -- Search box (applies to this dropdown only).
    local searchBox = Instance.new("TextBox")
    searchBox.Name = "Search"
    searchBox.Size = UDim2.new(1, -20, 0, 28)
    searchBox.Position = UDim2.new(0, 10, 0, 54)
    searchBox.BackgroundColor3 = UI_PANEL_2
    searchBox.BorderSizePixel = 0
    searchBox.Text = ""
    searchBox.PlaceholderText = "Search " .. noun .. "..."
    searchBox.PlaceholderColor3 = UI_MUTED
    searchBox.TextColor3 = UI_TEXT
    searchBox.Font = Enum.Font.GothamMedium
    searchBox.TextSize = 8
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.Visible = false
    searchBox.Parent = card
    addCorner(searchBox, 7)

    local searchPadding = Instance.new("UIPadding")
    searchPadding.PaddingLeft = UDim.new(0, 8)
    searchPadding.PaddingRight = UDim.new(0, 8)
    searchPadding.Parent = searchBox

    -- Per-dropdown Select All / Deselect All controls.
    local selectAllButton = Instance.new("TextButton")
    selectAllButton.Name = "SelectAll"
    selectAllButton.Size = UDim2.new(0.5, -12, 0, 26)
    selectAllButton.Position = UDim2.new(0, 10, 0, 87)
    selectAllButton.BackgroundColor3 = UI_ACCENT
    selectAllButton.BorderSizePixel = 0
    selectAllButton.Text = "SELECT ALL"
    selectAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    selectAllButton.Font = Enum.Font.GothamBold
    selectAllButton.TextSize = 8
    selectAllButton.Visible = false
    selectAllButton.Parent = card
    addCorner(selectAllButton, 6)

    local deselectAllButton = Instance.new("TextButton")
    deselectAllButton.Name = "DeselectAll"
    deselectAllButton.Size = UDim2.new(0.5, -12, 0, 26)
    deselectAllButton.Position = UDim2.new(0.5, 2, 0, 87)
    deselectAllButton.BackgroundColor3 = UI_PANEL_2
    deselectAllButton.BorderSizePixel = 0
    deselectAllButton.Text = "DESELECT ALL"
    deselectAllButton.TextColor3 = UI_TEXT
    deselectAllButton.Font = Enum.Font.GothamBold
    deselectAllButton.TextSize = 8
    deselectAllButton.Visible = false
    deselectAllButton.Parent = card
    addCorner(deselectAllButton, 6)

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Position = UDim2.new(0, 10, 0, 119)
    listFrame.Size = UDim2.new(1, -20, 0, 170)
    listFrame.BackgroundColor3 = UI_PANEL_2
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 2
    listFrame.ScrollBarImageColor3 = UI_ACCENT
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listFrame.CanvasSize = UDim2.new()
    listFrame.Visible = false
    listFrame.Parent = card
    addCorner(listFrame, 7)

    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingTop = UDim.new(0, 4)
    listPadding.PaddingBottom = UDim.new(0, 4)
    listPadding.PaddingLeft = UDim.new(0, 4)
    listPadding.PaddingRight = UDim.new(0, 4)
    listPadding.Parent = listFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 3)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = listFrame

    local optionButtons = {}

    local function normalizeSearch(value)
        value = string.lower(tostring(value or ""))
        value = value:gsub("^%s+", "")
        value = value:gsub("%s+$", "")
        return value
    end

    local function copySelection()
        local copy = {}
        for key, value in pairs(selected) do
            copy[key] = value
        end
        return copy
    end

    local function refreshOptions()
        local query = normalizeSearch(searchQuery)

        for _, option in ipairs(options) do
            local button = optionButtons[option.Value]

            if button then
                local isSelected = selected[option.Value] == true
                local label = tostring(option.Label or option.Value or "")
                local valueText = tostring(option.Value or "")
                local haystack = string.lower(label .. " " .. valueText)
                local matches = query == ""
                    or string.find(haystack, query, 1, true) ~= nil

                button.Visible = matches
                button.Text =
                    "  "
                    .. (isSelected and "✓ " or "")
                    .. label
                button.BackgroundColor3 = isSelected and UI_ACCENT or UI_PANEL
                button.TextColor3 = isSelected
                    and Color3.fromRGB(255, 255, 255)
                    or UI_TEXT
            end
        end
    end

    local function refreshSummary()
        local names = {}

        for _, option in ipairs(options) do
            if selected[option.Value] then
                table.insert(names, option.Value)
            end
        end

        if #names == 0 then
            headerButton.Text = "  Select " .. noun .. (expanded and " ▲" or " ▼")
        elseif #names <= 2 then
            headerButton.Text =
                "  "
                .. table.concat(names, ", ")
                .. (expanded and " ▲" or " ▼")
        else
            headerButton.Text =
                "  "
                .. tostring(#names)
                .. " " .. noun .. " selected"
                .. (expanded and " ▲" or " ▼")
        end

        refreshOptions()
    end

    local function emit()
        refreshSummary()

        if callback then
            task.spawn(callback, copySelection())
        end
    end

    for index, option in ipairs(options) do
        local button = Instance.new("TextButton")
        button.Name = tostring(option.Value) .. "Option"
        button.LayoutOrder = index
        button.Size = UDim2.new(1, 0, 0, 28)
        button.BackgroundColor3 = UI_PANEL
        button.BorderSizePixel = 0
        button.Text = ""
        button.TextColor3 = UI_TEXT
        button.Font = Enum.Font.GothamMedium
        button.TextSize = 8
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.Parent = listFrame
        addCorner(button, 6)

        optionButtons[option.Value] = button

        bind(button.Activated, function()
            selected[option.Value] = not selected[option.Value]
            emit()
        end)
    end

    bind(searchBox:GetPropertyChangedSignal("Text"), function()
        searchQuery = searchBox.Text
        refreshOptions()
    end)

    bind(selectAllButton.Activated, function()
        -- Select every item in THIS dropdown, regardless of the current search.
        for _, option in ipairs(options) do
            selected[option.Value] = true
        end

        emit()
    end)

    bind(deselectAllButton.Activated, function()
        table.clear(selected)
        emit()
    end)

    bind(headerButton.Activated, function()
        expanded = not expanded

        searchBox.Visible = expanded
        selectAllButton.Visible = expanded
        deselectAllButton.Visible = expanded
        listFrame.Visible = expanded

        card.Size = expanded
            and UDim2.new(1, 0, 0, 296)
            or UDim2.new(1, 0, 0, 52)

        refreshSummary()
    end)

    refreshSummary()

    local controller = {
        Card = card,
        Get = copySelection,
        SelectAll = function()
            for _, option in ipairs(options) do
                selected[option.Value] = true
            end
            emit()
        end,
        DeselectAll = function()
            table.clear(selected)
            emit()
        end,
        Search = function(query)
            searchBox.Text = tostring(query or "")
        end,
        Set = function(values)
            table.clear(selected)

            for key, value in pairs(values or {}) do
                if value then
                    selected[key] = true
                end
            end

            emit()
        end,
    }

    State.ConfigRegistry.MultiSelects[title] = controller
    return controller
end

--// BUILD TABS
for _, tab in ipairs(TAB_DEFINITIONS) do
    local page = createPage(tab.Key)
    local button = createTab(tab.Key, tab.Label)

    bind(button.Activated, function()
        setActivePage(tab.Key)
    end)
end

--// MAIN TAB
local mainPage = pages.Main
createSection(mainPage, "STATUS")

PlotStatusCard =
    createInfoCard(
        mainPage,
        "My Plot",
        MyPlot and MyPlot:GetFullName() or "Searching...",
        58
    )

AutoStatusCard =
    createInfoCard(
        mainPage,
        "Automation",
        "Ready. Select eggs in the EGGS tab.",
        58
    )

TargetStatusCard =
    createInfoCard(
        mainPage,
        "Current Target",
        "None",
        58
    )

BackpackStatusCard =
    createInfoCard(
        mainPage,
        "Backpack Scanner",
        "Scanning inventory...",
        72
    )

GrowingEggStatusCard =
    createInfoCard(
        mainPage,
        "Growing Eggs Scanner",
        "Growing: --/-- | Free: --\nFirst Egg: -- | Action: SEARCHING",
        72
    )

HatchStatusCard =
    createInfoCard(
        mainPage,
        "Auto Hatch",
        "OFF | waiting for placed eggs",
        58
    )

ProgressionStatusCard =
    createInfoCard(
        mainPage,
        "Progression",
        "Auto Upgrade: OFF | Plot Upgrade: OFF | Auto Rebirth: OFF",
        62
    )

createButton(mainPage, "RETURN TO MY PLOT", function()
    returnToMyPlot()
end)

createButton(mainPage, "RESCAN NOW", function()
    scanEggs()
    scanAllPlots()
    refreshMyPlotHighlight()
    Treadmill.UpdateScanner()
    updateGrowingEggCount()
    updateFirstGrowingEggAction()
    task.defer(function()
        local rows = HatchSystem.Collect()
        setHatchStatus("Placed eggs detected: " .. tostring(#rows))
    end)
    setAutoStatus("Rescan complete.")
end)

--// EGGS TAB
local eggsPage = pages.Eggs
createSection(eggsPage, "TARGET EGGS")

createMultiSelect(
    eggsPage,
    "Egg Targets (Multi Select)",
    EggOptions,
    State.SelectedEggs,
    function(selection)
        State.SelectedEggs = selection

        local count = getSelectedCount()

        if count == 0 then
            setTargetStatus("No target eggs selected.")
        else
            setTargetStatus(tostring(count) .. " egg type(s) selected.")

            -- Existing world eggs may predate this selection. Scan once now,
            -- instead of paying for a full scan every few seconds while idle.
            task.defer(function()
                if RUNNING then
                    scanEggs()
                end
            end)
        end
    end,
    "eggs"
)

createSection(eggsPage, "EGG PICKUP")

AutoPickupToggleController = createToggle(
    eggsPage,
    "Auto TP + Pickup",
    "Nearest selected egg → pickup → return to your plot",
    false,
    function(enabled)
        -- This is the USER preference. Auto Place may temporarily suppress
        -- the actual State.AutoPickup without changing this preference.
        State.AutoPickupUserEnabled = enabled

        if State.PlacingEggs or State.AutoPickupSuspendedByAutoPlace then
            State.AutoPickup = false

            if enabled then
                setAutoStatus("Auto Pickup queued ON after Auto Place finishes.")
            else
                setAutoStatus("Auto Pickup OFF.")
            end
            return
        end

        State.AutoPickup = enabled

        if enabled then
            if getSelectedCount() == 0 then
                setAutoStatus("Auto Pickup ON, but no eggs are selected.")
            else
                setAutoStatus("Auto Pickup ON.")
            end
        else
            setAutoStatus("Auto Pickup OFF.")
        end
    end
)

createSection(eggsPage, "EGG PLACEMENT")

AutoPlaceToggleController = createToggle(
    eggsPage,
    "Auto Place Method 1 - Growing Eggs",
    "Growing Eggs = 0 starts fill • keeps placing until MAX warning",
    true,
    function(enabled)
        if not enabled then
            -- User requested Auto Place to stay permanently enabled.
            State.AutoPlaceEggs = true

            setAutoStatus("Auto Place is locked ON.")

            task.delay(0.05, function()
                if RUNNING
                    and AutoPlaceToggleController
                    and AutoPlaceToggleController.Get
                    and AutoPlaceToggleController.Set
                    and not AutoPlaceToggleController.Get() then

                    AutoPlaceToggleController.Set(true)
                end
            end)

            return
        end

        State.AutoPlaceEggs = true

        if checkMaxEggLimitUI() then
            setAutoStatus("Auto Place ON but paused by the full-plot warning.")
            return
        end

        if not State.GrowingEggCounterReady then
            setAutoStatus("Auto Place ON. Waiting for Growing Eggs detector...")
            return
        end

        if State.GrowingEggs ~= 0 then
            setAutoStatus(
                "Auto Place ON. Waiting for Growing Eggs = 0 (now "
                .. tostring(State.GrowingEggs)
                .. ")."
            )
            return
        end

        setAutoStatus("Auto Place ON. Filling until the MAX warning appears.")

        task.defer(function()
            task.wait(0.08)

            if RUNNING
                and State.AutoPlaceEggs
                and State.GrowingEggCounterReady
                and State.GrowingEggs == 0
                and not State.MaxEggLimitReached
                and not State.Busy then

                placeAllBackpackEggs(false)
            end
        end)
    end
)

createToggle(
    eggsPage,
    "Auto Place Method 2 - After Pickup / No Target",
    "No Growing Eggs gate • hands-free grid placement after pickup / no TP target",
    false,
    function(enabled)
        State.AutoPlaceAfterPickup = enabled

        if enabled then
            setAutoStatus("Auto Place Method 2 ON | after pickup / no target | ignores Growing Eggs.")

            -- If Auto Pickup is already ON but there is currently no target,
            -- the normal pickup cycle will immediately fall back to placement.
        else
            setAutoStatus("Auto Place Method 2 OFF.")
        end
    end
)

createButton(eggsPage, "PLACE BACKPACK EGGS NOW", function()
    if State.Busy then
        setAutoStatus("Wait until the current automation finishes.")
        return
    end

    if not State.GrowingEggCounterReady then
        setAutoStatus("Growing Eggs detector is not ready yet.")
        return
    end

    if State.GrowingEggs ~= 0 then
        setAutoStatus(
            "Cannot place yet: Growing Eggs is "
            .. tostring(State.GrowingEggs)
            .. ". Waiting for 0."
        )
        return
    end

    if checkMaxEggLimitUI() then
        setAutoStatus("Cannot place: full-plot warning is still visible.")
        return
    end

    local hasEggsNow = hasBackpackEggs()

    if not hasEggsNow then
        setAutoStatus("No egg detected in Backpack. Nothing to place.")
        return
    end

    State.MaxEggLimitReached = false
    State.AutoPlaceEggs = true
    placeAllBackpackEggs(false)
end)

createSection(eggsPage, "EGG HATCHING")

createToggle(
    eggsPage,
    "Auto Hatch Placed Eggs",
    "CLAIM only • SKIP/GROWING never triggers HatchEgg",
    false,
    function(enabled)
        State.AutoHatchEggs = enabled

        if enabled then
            updateFirstGrowingEggAction()

            if not HatchSystem.FindRemote() then
                setHatchStatus("ON | HatchEgg remote not found yet.")
                return
            end

            if State.FirstEggAction == "CLAIM" then
                setHatchStatus("ON | Action: CLAIM | triggering Auto Hatch...")

                task.defer(function()
                    task.wait(0.03)

                    if RUNNING
                        and State.AutoHatchEggs
                        and State.FirstEggAction == "CLAIM" then

                        HatchSystem.Run(false)
                    end
                end)

            elseif State.FirstEggAction == "SKIP" then
                setHatchStatus("ON | Action: SKIP | waiting - no hatch.")

            else
                setHatchStatus(
                    "ON | Action: "
                    .. tostring(State.FirstEggAction)
                    .. " | waiting."
                )
            end
        else
            State.AutoHatchEggs = false
            State.HatchingEggs = false
            setHatchStatus("OFF | waiting for Action: CLAIM")
        end
    end
)

createButton(eggsPage, "HATCH PLACED EGGS NOW", function()
    if State.Busy or State.PlacingEggs then
        setHatchStatus("Wait until current TP/place automation finishes.")
        return
    end

    local wasEnabled = State.AutoHatchEggs
    State.AutoHatchEggs = true
    HatchSystem.Run(true)
    State.AutoHatchEggs = wasEnabled
end)

--// SELL TAB
local sellPage = pages.Sell
createSection(sellPage, "AUTO SELL STATUS")

State.Sell.StatusCard = createInfoCard(
    sellPage,
    "Seller",
    "Ready. Choose animals + mutations and/or eggs below.",
    62
)

createSection(sellPage, "ANIMALS / BRAINROTS")

createMultiSelect(
    sellPage,
    "Animals (Multi Select)",
    State.Sell.AnimalOptions,
    State.Sell.SelectedAnimals,
    function(selection)
        State.Sell.SelectedAnimals = selection
        State.Sell.SetStatus(
            "Selected animals: " .. tostring(State.Sell.Count(selection))
        )
    end,
    "animals"
)

createMultiSelect(
    sellPage,
    "Mutations (Multi Select)",
    State.Sell.MutationOptions,
    State.Sell.SelectedMutations,
    function(selection)
        State.Sell.SelectedMutations = selection
        State.Sell.SetStatus(
            "Selected mutations: " .. tostring(State.Sell.Count(selection))
        )
    end,
    "mutations"
)

createToggle(
    sellPage,
    "Auto Sell Animals",
    "Sells only when BOTH the animal and mutation are selected",
    false,
    function(enabled)
        State.Sell.AnimalEnabled = enabled
        if enabled then
            State.Sell.SetStatus("Auto Sell Animals ON.")
            task.defer(function()
                if RUNNING and State.Sell.AnimalEnabled then
                    State.Sell.SellAnimalsOnce(false)
                end
            end)
        else
            State.Sell.SetStatus("Auto Sell Animals OFF.")
        end
    end
)

createButton(sellPage, "SELL MATCHING ANIMALS NOW", function()
    State.Sell.SellAnimalsOnce(true)
end)

createSection(sellPage, "EGGS")

createMultiSelect(
    sellPage,
    "Eggs (Multi Select)",
    State.Sell.EggOptions,
    State.Sell.SelectedEggs,
    function(selection)
        State.Sell.SelectedEggs = selection
        State.Sell.SetStatus(
            "Selected sell eggs: " .. tostring(State.Sell.Count(selection))
        )
    end,
    "eggs"
)

createToggle(
    sellPage,
    "Auto Sell Eggs",
    "Sells selected owned egg types by their UUID",
    false,
    function(enabled)
        State.Sell.EggEnabled = enabled
        if enabled then
            State.Sell.SetStatus("Auto Sell Eggs ON.")
            task.defer(function()
                if RUNNING and State.Sell.EggEnabled then
                    State.Sell.SellEggsOnce(false)
                end
            end)
        else
            State.Sell.SetStatus("Auto Sell Eggs OFF.")
        end
    end
)

createButton(sellPage, "SELL MATCHING EGGS NOW", function()
    State.Sell.SellEggsOnce(true)
end)

createInfoCard(
    sellPage,
    "Matching",
    "Animal selling uses Animal AND Mutation together. Example: Sentinel + Diamond sells Diamond Sentinel variants. Egg selling uses the selected egg type only.",
    78
)

--// SETTINGS TAB
local settingsPage = pages.Settings

createSection(settingsPage, "ANIMAL EQUIP")

createToggle(
    settingsPage,
    "Auto Equip Best Animals",
    "Calls AnimalService EquipBest immediately, then every 10 seconds",
    false,
    function(enabled)
        State.AutoEquipBestAnimals = enabled

        if enabled then
            setAutoStatus("Auto Equip Best Animals ON | every 10 seconds.")

            task.defer(function()
                task.wait(0.05)
                if RUNNING and State.AutoEquipBestAnimals then
                    State.AnimalEquipBest.Run(false)
                end
            end)
        else
            setAutoStatus("Auto Equip Best Animals OFF.")
        end
    end
)

createButton(settingsPage, "EQUIP BEST ANIMALS NOW", function()
    State.AnimalEquipBest.Run(true)
end)

createSection(settingsPage, "TREADMILL TRAINING")

TreadmillStatusCard =
    createInfoCard(
        settingsPage,
        "Treadmill Live Scanner + Payload Discovery",
        "Scanning owned / equipped treadmill tiers...",
        86
    )

Treadmill.UpdateScanner()

createToggle(
    settingsPage,
    "Auto Buy Treadmill",
    "Payload scanner auto-updates BuyTrainTool IDs and buys every detected treadmill",
    false,
    function(enabled)
        State.AutoBuyTreadmill = enabled

        if enabled then
            if Treadmill.FindBuyRemote() then
                setAutoStatus("Auto Buy Treadmill ON | live payload scanner active.")
            else
                setAutoStatus("Auto Buy Treadmill ON | BuyTrainTool remote not found yet.")
            end

            task.defer(function()
                task.wait(0.05)

                if RUNNING and State.AutoBuyTreadmill then
                    Treadmill.RunBuyPass(false)
                end
            end)
        else
            setAutoStatus("Auto Buy Treadmill OFF.")
        end
    end
)

createButton(settingsPage, "BUY DETECTED TREADMILLS ONCE", function()
    Treadmill.RunBuyPass(true)
end)

createToggle(
    settingsPage,
    "Auto Claim Training Bonus",
    "Clicks the exact x2 bonus button; ClaimBonus remote is fallback",
    true,
    function(enabled)
        State.AutoClaimTrainingBonus = enabled

        if enabled then
            if Treadmill.FindClaimBonusRemote() then
                setAutoStatus("Auto Claim Training Bonus ON.")
            else
                setAutoStatus("Auto Claim Training Bonus ON | ClaimBonus remote not found yet.")
            end

            task.defer(function()
                task.wait(0.05)
                if RUNNING and State.AutoClaimTrainingBonus then
                    Treadmill.ClaimBonus(false)
                end
            end)
        else
            setAutoStatus("Auto Claim Training Bonus OFF.")
        end
    end
)

createButton(settingsPage, "CLAIM TRAINING BONUS NOW", function()
    Treadmill.ClaimBonus(true)
end)

createToggle(
    settingsPage,
    "Auto Equip Treadmill",
    "Live scanner auto-equips the highest owned treadmill whenever inventory changes",
    true,
    function(enabled)
        State.AutoEquipTreadmill = enabled

        if enabled then
            Treadmill.UpdateScanner()
            setAutoStatus("Auto Equip BEST Treadmill ON | Lava is highest priority.")

            if not State.PlacingEggs
                and not State.HatchingEggs
                and State.CurrentTarget == nil then

                task.defer(function()
                    task.wait(0.05)

                    if RUNNING
                        and State.AutoEquipTreadmill
                        and not State.PlacingEggs
                        and not State.HatchingEggs
                        and State.CurrentTarget == nil then

                        Treadmill.EquipBest()
                    end
                end)
            end
        else
            setAutoStatus("Auto Equip Treadmill OFF.")
        end
    end
)



createSection(settingsPage, "PROGRESSION")

createToggle(
    settingsPage,
    "Auto Upgrade",
    "Cycles CloneCooldown → MaxClones → CloneMaxSteal",
    false,
    function(enabled)
        State.AutoUpgrade = enabled

        if enabled then
            if ProgressionSystem.FindUpgradeRemote() then
                ProgressionSystem.UpdateStatus("Auto Upgrade enabled.")
            else
                ProgressionSystem.UpdateStatus("Auto Upgrade ON | Upgrade remote not found yet.")
            end

            task.defer(function()
                task.wait(0.05)
                if RUNNING and State.AutoUpgrade then
                    ProgressionSystem.RunUpgradePass(false)
                end
            end)
        else
            ProgressionSystem.UpdateStatus("Auto Upgrade disabled.")
        end
    end
)

createToggle(
    settingsPage,
    "Auto Upgrade Plot",
    "Uses UpgradesService PlotUpgrade +1 whenever the server allows it",
    false,
    function(enabled)
        State.AutoUpgradePlot = enabled

        if enabled then
            if ProgressionSystem.FindUpgradeRemote() then
                ProgressionSystem.UpdateStatus("Auto Plot Upgrade enabled.")
            else
                ProgressionSystem.UpdateStatus("Auto Plot Upgrade ON | Upgrade remote not found yet.")
            end

            task.defer(function()
                task.wait(0.05)
                if RUNNING and State.AutoUpgradePlot then
                    ProgressionSystem.RunPlotUpgradePass(false)
                end
            end)
        else
            ProgressionSystem.UpdateStatus("Auto Plot Upgrade disabled.")
        end
    end
)

createToggle(
    settingsPage,
    "Auto Rebirth",
    "Automatically requests rebirth whenever the server allows it",
    false,
    function(enabled)
        State.AutoRebirth = enabled

        if enabled then
            if ProgressionSystem.FindRebirthRemote() then
                ProgressionSystem.UpdateStatus("Auto Rebirth enabled.")
            else
                ProgressionSystem.UpdateStatus("Auto Rebirth ON | Rebirth remote not found yet.")
            end

            task.defer(function()
                task.wait(0.05)
                if RUNNING and State.AutoRebirth then
                    ProgressionSystem.RunRebirthPass(false)
                end
            end)
        else
            ProgressionSystem.UpdateStatus("Auto Rebirth disabled.")
        end
    end
)

createSection(settingsPage, "TRAILS")

createToggle(
    settingsPage,
    "Auto Buy Trail",
    "Green → Blue → Pink → Yellow → Red → Black → White → Rainbow",
    false,
    function(enabled)
        State.AutoBuyTrail = enabled

        if enabled then
            setAutoStatus("Auto Buy Trail ON | upgrading toward Rainbow.")

            task.defer(function()
                if RUNNING and State.AutoBuyTrail then
                    State.Trail.BuyPass(false)
                end
            end)
        else
            setAutoStatus("Auto Buy Trail OFF.")
        end
    end
)

createToggle(
    settingsPage,
    "Auto Equip Best Trail",
    "Best owned priority: Rainbow → White → Black → Red → Yellow → Pink → Blue → Green",
    true,
    function(enabled)
        State.AutoEquipTrail = enabled

        if enabled then
            setAutoStatus("Auto Equip Best Trail ON.")

            task.defer(function()
                if RUNNING and State.AutoEquipTrail then
                    State.Trail.EquipBest()
                end
            end)
        else
            setAutoStatus("Auto Equip Best Trail OFF.")
        end
    end
)

createButton(settingsPage, "BUY TRAILS ONCE", function()
    State.Trail.BuyPass(true)
end)

createButton(settingsPage, "EQUIP BEST TRAIL NOW", function()
    State.Trail.EquipBest()
end)

createButton(settingsPage, "UPGRADE ALL ONCE", function()
    ProgressionSystem.RunUpgradePass(true)
end)

createButton(settingsPage, "UPGRADE PLOT ONCE", function()
    ProgressionSystem.RunPlotUpgradePass(true)
end)

createButton(settingsPage, "REBIRTH ONCE", function()
    ProgressionSystem.RunRebirthPass(true)
end)


createSection(settingsPage, "CONFIGURATION")

State.ConfigSystem.NameInput = createTextInput(
    settingsPage,
    "Config Name",
    "Example: MainFarm",
    ""
)

State.ConfigSystem.StatusCard = createInfoCard(
    settingsPage,
    "Config Status",
    "Enter a name, save it, then set that named config as Auto Load.",
    64
)

createButton(settingsPage, "SAVE NAMED CONFIG", function()
    State.ConfigSystem.Save(State.ConfigSystem.NameInput.Get())
end)

createButton(settingsPage, "LOAD NAMED CONFIG", function()
    State.ConfigSystem.Load(State.ConfigSystem.NameInput.Get(), false)
end)

createButton(settingsPage, "SET NAMED CONFIG AS AUTO LOAD", function()
    State.ConfigSystem.SetAutoLoad(State.ConfigSystem.NameInput.Get())
end)

createButton(settingsPage, "CLEAR AUTO LOAD CONFIG", function()
    State.ConfigSystem.ClearAutoLoad()
end)

createSection(settingsPage, "PERFORMANCE")

createToggle(
    settingsPage,
    "FPS Boost",
    "Hardcore low graphics + texture/PBR strip + 60 FPS cap; OFF restores captured visuals",
    false,
    function(enabled)
        FPSBooster.SetEnabled(enabled)

        if enabled then
            setAutoStatus("FPS Boost ON | 60 FPS cap + counter enabled.")
        else
            setAutoStatus("FPS Boost OFF | restoring normal visuals.")
        end
    end
)

createSection(settingsPage, "PROMPTS")

createToggle(
    settingsPage,
    "Instant Proximity",
    "Uses fireproximityprompt when a hold begins",
    true,
    function(enabled)
        State.InstantProximity = enabled
        if enabled then
            connectAllInstantPrompts()
            setAutoStatus("Instant Proximity ON.")
        else
            setAutoStatus("Instant Proximity OFF.")
        end
    end
)

createInfoCard(
    settingsPage,
    "Live Scanners",
    "Eggs, own-plot ownership, prompts, moved objects, removals and target selection update live. A slower full rescan runs only as backup.",
    86
)

createInfoCard(
    settingsPage,
    "Pickup Logic",
    "Egg pickup uses the egg's PickablePrompt/Pickup prompt. Collected eggs are removed when any player's pickup is detected.",
    76
)

--// MINIMIZE / RESTORE
local minimized = false

local miniButton = Instance.new("TextButton")
miniButton.Name = "MiniButton"
miniButton.AnchorPoint = Vector2.new(0.5, 0.5)
miniButton.Size = UDim2.new(0, 46, 0, 46)
miniButton.Position = mainFrame.Position
miniButton.BackgroundColor3 = UI_PANEL
miniButton.BorderSizePixel = 0
miniButton.Text = MINI_TEXT
miniButton.TextColor3 = UI_TEXT
miniButton.Font = Enum.Font.GothamBold
miniButton.TextSize = 16
miniButton.Visible = false
miniButton.Parent = screenGui
addCorner(miniButton, 10)
addStroke(miniButton, UI_STROKE, 1, 0.15)
makeDraggable(miniButton, miniButton)

local function setMinimized(value)
    minimized = value == true

    if minimized then
        miniButton.Position = mainFrame.Position
        mainFrame.Visible = false
        miniButton.Visible = true
    else
        mainFrame.Position = miniButton.Position
        miniButton.Visible = false
        mainFrame.Visible = true
    end
end

bind(minimizeBtn.Activated, function()
    setMinimized(true)
end)

bind(miniButton.Activated, function()
    setMinimized(false)
end)

-- Start minimized every time the script executes.
-- The mini button stays at the upper-middle-left spawn position.
setMinimized(true)

--// CLEANUP
local function cleanup()
    if not RUNNING then
        return
    end

    RUNNING = false
    State.AutoPickup = false
    State.AutoEquipTreadmill = false
    State.AutoBuyTreadmill = false
    State.AutoClaimTrainingBonus = false
    State.AutoEquipBestAnimals = false
    State.AutoPlaceEggs = false
    State.AutoPlaceAfterPickup = false
    State.PlacingEggs = false
    State.AutoHatchEggs = false
    State.HatchingEggs = false
    State.AutoUpgrade = false
    State.AutoUpgradePlot = false
    State.AutoRebirth = false
    State.AutoBuyTrail = false
    State.AutoEquipTrail = false
    FPSBooster.SetEnabled(false)
    if State.Sell then
        State.Sell.AnimalEnabled = false
        State.Sell.EggEnabled = false
    end
    State.Busy = false

    ENV.__ZHM_GROWING_EGG_LIVE = nil

    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(Connections)

    clearPlotESP()

    local eggKeys = {}
    for egg in pairs(EggTracked) do
        table.insert(eggKeys, egg)
    end

    for _, egg in ipairs(eggKeys) do
        removeEggESP(egg)
    end

    if PlotScannerFolder then
        PlotScannerFolder:Destroy()
    end

    if EggScannerFolder then
        EggScannerFolder:Destroy()
    end

    if disconnectResponsiveScale then
        disconnectResponsiveScale()
    end

    if State.FPSGui and State.FPSGui.Parent then
        State.FPSGui:Destroy()
        State.FPSGui = nil
    end

    if screenGui and screenGui.Parent then
        screenGui:Destroy()
    end
end

ENV.__ZHM_EGG_PLOT_STOP = cleanup

bind(closeBtn.Activated, function()
    cleanup()
end)

--// DEFAULT PAGE
if TAB_DEFINITIONS[1] then
    setActivePage(TAB_DEFINITIONS[1].Key)
end

setPlotStatus("Found: " .. MyPlot:GetFullName())
setAutoStatus("Ready. Select one or more target eggs.")
setTargetStatus("None")
Treadmill.UpdateScanner()
refreshGrowingEggScannerCard()
updateFirstGrowingEggAction()
ProgressionSystem.UpdateStatus("Ready.")

-- Apply the named Auto Load config only after every toggle/dropdown controller
-- has been created and all automation systems are ready.
task.defer(function()
    task.wait(0.20)
    if RUNNING then
        State.ConfigSystem.AutoLoad()
    end
end)


--// HIDE ALL POP-UP TEXT
-- Aggressive but UI-safe: keeps the ZHM hub visible while suppressing
-- temporary notification/banner/error text created by the game.
-- IMPORTANT: ClaimBonus has NO special GUI exemption. Never force game GUI visible.
do
    local WatchedPopupText = setmetatable({}, {__mode = "k"})
    local BlockedPopupText = setmetatable({}, {__mode = "k"})
    local BlockedPopupOriginals = setmetatable({}, {__mode = "k"})

    local POPUP_NAME_WORDS = {
        "notification", "notify", "popup", "pop_up", "toast",
        "alert", "warning", "error", "message", "announcement",
        "announce", "banner", "feedback", "purchase", "insufficient",
    }

    local function isTextGuiObject(object)
        return object
            and (
                object:IsA("TextLabel")
                or object:IsA("TextButton")
                or object:IsA("TextBox")
            )
    end

    local function isInsideZHMGui(object)
        return screenGui
            and screenGui.Parent
            and object
            and object:IsDescendantOf(screenGui)
    end

    -- Growing Eggs is automation state, not a popup. Never let the global
    -- popup blocker hide Egg_Frame text because Auto Hatch reads CLAIM/SKIP/READY
    -- from these labels even while the window itself is closed.
    local function isInsideGrowingEggGui(object)
        if not object then
            return false
        end

        local current = object
        local depth = 0

        while current and current ~= playerGui and depth < 16 do
            if current.Name == "Egg_Frame" then
                return true
            end

            current = current.Parent
            depth += 1
        end

        return false
    end

    local function readPopupText(object)
        if not object then
            return ""
        end

        local value = ""

        pcall(function()
            value = object.ContentText
        end)

        if value == "" then
            pcall(function()
                value = object.Text
            end)
        end

        return tostring(value or "")
    end

    local function isKnownWarningText(value)
        value = string.lower(tostring(value or ""))

        return string.find(value, "not enough cash", 1, true) ~= nil
            or string.find(value, "do not have enough cash", 1, true) ~= nil
            or string.find(value, "don't have enough cash", 1, true) ~= nil
            or string.find(value, "don’t have enough cash", 1, true) ~= nil
            or string.find(value, "already at max level", 1, true) ~= nil
            or string.find(value, "maximum rebirth level", 1, true) ~= nil
            or string.find(value, "already own this", 1, true) ~= nil
            or string.find(value, "don't own this", 1, true) ~= nil
            or string.find(value, "don’t own this", 1, true) ~= nil
            or string.find(value, "do not own this", 1, true) ~= nil
            or string.find(value, "can't carry any more eggs", 1, true) ~= nil
            or string.find(value, "can’t carry any more eggs", 1, true) ~= nil
            or string.find(value, "maximum number of eggs", 1, true) ~= nil
    end

    local function hasPopupLikeAncestor(object)
        local current = object
        local depth = 0

        while current and current ~= playerGui and depth < 8 do
            local n = string.lower(tostring(current.Name or ""))

            for _, word in ipairs(POPUP_NAME_WORDS) do
                if string.find(n, word, 1, true) then
                    return true
                end
            end

            current = current.Parent
            depth += 1
        end

        return false
    end

    local function looksLikeScreenPopup(object, textValue)
        if not isTextGuiObject(object) then
            return false
        end

        textValue = tostring(textValue or "")
        if textValue == "" or #textValue > 350 then
            return false
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return false
        end

        local ok, pos, size, textSize, textScaled = pcall(function()
            return object.AbsolutePosition,
                object.AbsoluteSize,
                object.TextSize,
                object.TextScaled
        end)

        if not ok or not pos or not size then
            return false
        end

        local viewport = camera.ViewportSize
        if viewport.X <= 0 or viewport.Y <= 0 then
            return false
        end

        local centerX = pos.X + (size.X * 0.5)
        local centerY = pos.Y + (size.Y * 0.5)

        local horizontallyCentral = math.abs(centerX - viewport.X * 0.5) <= viewport.X * 0.40
        local upperOrMiddleScreen = centerY <= viewport.Y * 0.62
        local wideEnough = size.X >= viewport.X * 0.22
        local notFullScreenPanel = size.Y <= viewport.Y * 0.30
        local visuallyProminent = textScaled == true or (tonumber(textSize) or 0) >= 18

        return horizontallyCentral
            and upperOrMiddleScreen
            and wideEnough
            and notFullScreenPanel
            and visuallyProminent
    end

    local function forceHidePopupText(object)
        if not object
            or not object.Parent
            or isInsideZHMGui(object)
            or isInsideGrowingEggGui(object) then
            return
        end


        if not BlockedPopupOriginals[object] then
            local original = {
                Visible = true,
                TextTransparency = 0,
                TextStrokeTransparency = 1,
                Parent = nil,
                ParentVisible = true,
            }

            pcall(function() original.Visible = object.Visible end)
            pcall(function() original.TextTransparency = object.TextTransparency end)
            pcall(function() original.TextStrokeTransparency = object.TextStrokeTransparency end)

            local parent = object.Parent
            if parent and parent:IsA("GuiObject") then
                original.Parent = parent
                pcall(function() original.ParentVisible = parent.Visible end)
            end

            BlockedPopupOriginals[object] = original
        end

        BlockedPopupText[object] = true

        pcall(function()
            object.Visible = false
        end)

        pcall(function()
            object.TextTransparency = 1
        end)

        pcall(function()
            object.TextStrokeTransparency = 1
        end)

        -- If the notification has a dedicated small wrapper, hide that too.
        local parent = object.Parent
        if parent and parent:IsA("GuiObject") and hasPopupLikeAncestor(parent) then
            pcall(function()
                parent.Visible = false
            end)
        end
    end

    local function shouldHidePopup(object, aggressiveCheck)
        if not isTextGuiObject(object)
            or not object.Parent
            or isInsideZHMGui(object)
            or isInsideGrowingEggGui(object) then
            return false
        end

        local value = readPopupText(object)


        if isKnownWarningText(value) then
            return true
        end

        if hasPopupLikeAncestor(object) then
            return true
        end

        if aggressiveCheck and looksLikeScreenPopup(object, value) then
            return true
        end

        return false
    end

    local function checkPopupText(object, aggressiveCheck)
        if shouldHidePopup(object, aggressiveCheck) then
            forceHidePopupText(object)
        end
    end

    local function watchPopupText(object, isNewObject)
        if not isTextGuiObject(object)
            or WatchedPopupText[object]
            or isInsideZHMGui(object)
            or isInsideGrowingEggGui(object) then
            return
        end

        WatchedPopupText[object] = true
        checkPopupText(object, isNewObject == true)

        bind(object:GetPropertyChangedSignal("Text"), function()
            if RUNNING and object.Parent then
                -- Text changes are the important reuse signal. Avoid binding
                -- ContentText + both transparency properties on every label.
                checkPopupText(object, true)
            end
        end)

        bind(object:GetPropertyChangedSignal("Visible"), function()
            if not RUNNING or not object.Parent then
                return
            end

            if BlockedPopupText[object] then
                if object.Visible then
                    forceHidePopupText(object)
                end
            elseif object.Visible then
                checkPopupText(object, true)
            end
        end)
    end

    -- Scan existing UI. Existing ordinary HUD text is preserved unless it is
    -- clearly inside a popup/notification container or matches a warning.
    task.defer(function()
        task.wait(0.05)

        if not RUNNING then
            return
        end

        for _, object in ipairs(playerGui:GetDescendants()) do
            if isTextGuiObject(object)
                and not isInsideZHMGui(object)
                and not isInsideGrowingEggGui(object) then

                local value = readPopupText(object)

                -- Existing permanent HUD labels do not need 2+ property
                -- connections each. Only subscribe likely popup/warning labels;
                -- brand-new transient labels are still handled below.
                if isKnownWarningText(value) or hasPopupLikeAncestor(object) then
                    watchPopupText(object, false)
                end
            end
        end
    end)

    -- New text objects are checked more aggressively because transient popups
    -- are commonly cloned into PlayerGui only when they appear.
    bind(playerGui.DescendantAdded, function(object)
        if isTextGuiObject(object) then
            task.defer(function()
                task.wait(0.01)

                if RUNNING and object.Parent then
                    watchPopupText(object, true)
                end
            end)
        end
    end)
end

print("==========================================")
print("[ZHM] EGG + PLOT HUB ENABLED")
print("[ZHM] My Plot:", MyPlot:GetFullName())
print("[ZHM] Auto TP/Pickup: ready")
print("[ZHM] Treadmills: dynamic BuyTrainTool payload scanner | auto-discovers new *_treadmill IDs")
print("[ZHM] Auto Equip: BEST AVAILABLE | Lava is highest priority")
print("[ZHM] Auto Equip Best Animals: toggleable | every 10 seconds")
print("[ZHM] Auto Claim Training Bonus: exact x2 physical click + ClaimBonus RF fallback")
print("[ZHM] FPS Booster: HARDCORE texture/PBR strip | default OFF | manual toggle")
print("[ZHM] Pop-up blocker: ON | no ClaimBonus UI exemption")
print("[ZHM] Auto Place Method 1: Growing Eggs 0 starts fill | KEEP PLACING until MAX warning")
print("[ZHM] Auto Place Method 2: after pickup / no TP target | ignores Growing Eggs")
print("[ZHM] Growing Egg Action Scanner: CLAIM / SKIP / GROWING / NONE")
print("[ZHM] Auto Hatch: CLAIM-ONLY | SKIP never triggers HatchEgg")
print("[ZHM] Auto Upgrade: CloneCooldown / MaxClones / CloneMaxSteal")
print("[ZHM] Auto Plot Upgrade: PlotUpgrade +1")
print("[ZHM] Auto Rebirth: ready")
print("[ZHM] Trails: Auto Buy Green -> Blue -> Pink -> Yellow -> Red -> Black -> White -> Rainbow")
print("[ZHM] Auto Equip Trail: BEST OWNED | Rainbow highest priority")
print("[ZHM] Auto Sell Animals: multi-select Animal + Mutation | SellBrainrot UUID")
print("[ZHM] Auto Sell Eggs: multi-select Egg | SellEgg UUID")
print("[ZHM] Auto Hatch CLAIM detection: EVENT-DRIVEN / no intentional delay")
print("[ZHM] Pickup Prompt Spam: ON | Pickup/Pickable fires every 0.05s | egg stay 0.50s")
print("[ZHM] Auto TP Egg: HARD TARGET LOCK + exact prompt-part teleport")
print("[ZHM] Treadmill Equip: Backpack Tool first + EquipTrainTool fallback")
print("[ZHM] Instant Proximity: ON")
print("[ZHM] All scanners: LIVE / event-driven")
print("[ZHM] Recycled egg recovery: ON")
print("[ZHM] Config system: named Save / Load / persistent Auto Load ready")
print("==========================================")

end)
