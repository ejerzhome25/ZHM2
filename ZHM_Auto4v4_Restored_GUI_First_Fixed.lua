-- ZHM | Event Spawnable Scanner + Precise Tween Collector + Auto Matchmaking 4v4
-- Client-side Roblox Lua; run after joining the game.
-- The collection remote is invoked WITHOUT arguments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local spawnables = workspace:WaitForChild("SpawnablesClient", 15)
if not spawnables then
    warn("[ZHM] Workspace.SpawnablesClient not found")
    return
end

local packages = ReplicatedStorage:WaitForChild("Packages", 15)
local networking = packages and packages:WaitForChild("Networking", 15)
-- Networking frameworks often store the slash-delimited path as ONE instance name.
-- Support both "Networking['RE/Events/CollectEventSpawnable']" and nested folders.
local collectRemote = networking and networking:FindFirstChild("RE/Events/CollectEventSpawnable")
if not collectRemote and networking then
    local re = networking:FindFirstChild("RE")
    local events = re and re:FindFirstChild("Events")
    collectRemote = events and events:FindFirstChild("CollectEventSpawnable")
end
if not collectRemote and networking then
    -- Briefly wait for a late-loaded RemoteEvent with the direct name.
    collectRemote = networking:WaitForChild("RE/Events/CollectEventSpawnable", 10)
end
if not (collectRemote and collectRemote:IsA("RemoteEvent")) then
    warn("[ZHM] CollectEventSpawnable RemoteEvent not found")
    return
end

-- Shut down any previous copy of this script.
local env = (getgenv and getgenv()) or _G
if env.ZHM_EventCollect_Stop then
    pcall(env.ZHM_EventCollect_Stop)
end
-- Avoid a duplicate collector loop if the older standalone Auto Event is active.
if env.ZHM_AutoEvent and type(env.ZHM_AutoEvent.Stop) == "function" then
    pcall(env.ZHM_AutoEvent.Stop)
end

local running = true
local autoCollect = true
local autoEvent = true -- Independent remote-only collection loop; may run alongside tween collector
local eventInterval = 0.35 -- seconds, configurable 0.10 to 3.00
local eventAttempts = 0 -- calls attempted, not confirmed successful collections
local eventLastError = nil
local showESP = true
local auto4v4 = true -- auto queue ON at execution; supports QUEUE / QUEUE AGAIN
local autoDecline = true -- automatically decline RejoinPopup when visible
local declineAttempts = 0 -- attempt counter, not confirmed popup closures
local playHandled = false -- one attempt per visible PLAY screen
local lowModelHandled = false -- legacy state, retained for compatibility
local resetMatchmakingAttempts = nil
local tweenSpeed = 100 -- studs / second
local arrivalDistance = 0.8 -- precise 3D distance from model center (studs)
local retryAfter = 5 -- cooldown per model after collection attempt
local maxESP = 100 -- safety limit to avoid overcrowding / lag

local activeTween = nil
local lastAttempt = setmetatable({}, {__mode = "k"})
local espObjects = {}
local connections = {}
local candidates = {}
local liveModelCount = 0 -- live outermost collectable-model count
local scannerReady = false -- prevents acting on uninitialized model count
local currentTarget = nil

local gui = Instance.new("ScreenGui")
gui.Name = "ZHM_EventSpawnable_Collector"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function make(class, props, parent)
    local inst = Instance.new(class)
    for key, value in pairs(props) do
        inst[key] = value
    end
    inst.Parent = parent
    return inst
end

local main = make("Frame", {
    Name = "Panel", Size = UDim2.fromOffset(275, 475),
    Position = UDim2.new(0.5, -138, 0.3, 0),
    BackgroundColor3 = Color3.fromRGB(22, 26, 35),
    BorderSizePixel = 0,
}, gui)
make("UICorner", {CornerRadius = UDim.new(0, 12)}, main)
make("UIStroke", {Color = Color3.fromRGB(75, 104, 130), Thickness = 1.2}, main)
local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 43), BackgroundColor3 = Color3.fromRGB(32, 41, 55),
    BorderSizePixel = 0,
}, main)
make("UICorner", {CornerRadius = UDim.new(0, 12)}, header)
make("TextLabel", {
    Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -65, 1, 0),
    BackgroundTransparency = 1, Text = "ZHM  |  EVENT COLLECT",
    TextColor3 = Color3.fromRGB(235, 247, 255), TextSize = 14,
    Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local mini = make("TextButton", {
    Position = UDim2.new(1, -36, 0, 6), Size = UDim2.fromOffset(29, 29),
    BackgroundColor3 = Color3.fromRGB(55, 69, 87), BorderSizePixel = 0,
    Text = "−", TextSize = 20, Font = Enum.Font.GothamBold,
    TextColor3 = Color3.new(1, 1, 1),
}, header)
make("UICorner", {CornerRadius = UDim.new(0, 7)}, mini)

local function button(text, y)
    local b = make("TextButton", {
        Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 34),
        BackgroundColor3 = Color3.fromRGB(43, 61, 79), BorderSizePixel = 0,
        Text = text, TextSize = 13, Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(240, 250, 255),
    }, main)
    make("UICorner", {CornerRadius = UDim.new(0, 7)}, b)
    return b
end
local collectBtn = button("AUTO COLLECT: ON", 51)
local espBtn = button("MODEL ESP + NAMES: ON", 91)
local matchBtn = button("AUTO PLAY 4V4 (QUEUE): ON", 131)
local eventBtn = button("NO-MOVEMENT AUTO EVENT: ON", 171)
local slowerEventBtn = make("TextButton", {
    Position = UDim2.fromOffset(12, 211), Size = UDim2.fromOffset(37, 28),
    BackgroundColor3 = Color3.fromRGB(43, 61, 79), BorderSizePixel = 0,
    Text = "−", TextSize = 17, Font = Enum.Font.GothamBold,
    TextColor3 = Color3.fromRGB(240, 250, 255),
}, main)
make("UICorner", {CornerRadius = UDim.new(0, 7)}, slowerEventBtn)
local eventIntervalLabel = make("TextLabel", {
    Position = UDim2.fromOffset(57, 211), Size = UDim2.fromOffset(160, 28),
    BackgroundTransparency = 1, Text = "Event interval: 0.35 sec",
    TextColor3 = Color3.fromRGB(219, 228, 239),
    TextSize = 11, Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Center,
}, main)
local fasterEventBtn = make("TextButton", {
    Position = UDim2.fromOffset(226, 211), Size = UDim2.fromOffset(37, 28),
    BackgroundColor3 = Color3.fromRGB(43, 61, 79), BorderSizePixel = 0,
    Text = "+", TextSize = 17, Font = Enum.Font.GothamBold,
    TextColor3 = Color3.fromRGB(240, 250, 255),
}, main)
make("UICorner", {CornerRadius = UDim.new(0, 7)}, fasterEventBtn)
make("TextLabel", {
    Position = UDim2.fromOffset(13, 252), Size = UDim2.fromOffset(125, 25),
    BackgroundTransparency = 1, Text = "Tween speed (studs/s)",
    TextColor3 = Color3.fromRGB(219, 228, 239),
    TextSize = 11, Font = Enum.Font.GothamSemibold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)
local speedBox = make("TextBox", {
    Position = UDim2.fromOffset(158, 249), Size = UDim2.fromOffset(104, 29),
    BackgroundColor3 = Color3.fromRGB(42, 53, 68), BorderSizePixel = 0,
    Text = tostring(tweenSpeed), ClearTextOnFocus = false,
    TextSize = 13, Font = Enum.Font.GothamBold,
    TextColor3 = Color3.new(1, 1, 1),
}, main)
make("UICorner", {CornerRadius = UDim.new(0, 6)}, speedBox)
local countLabel = make("TextLabel", {
    Position = UDim2.fromOffset(12, 285), Size = UDim2.new(1, -24, 0, 21),
    BackgroundTransparency = 1, Text = "Live models: scanning...",
    TextSize = 12, Font = Enum.Font.GothamSemibold,
    TextColor3 = Color3.fromRGB(133, 221, 209),
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)
local statusLabel = make("TextLabel", {
    Position = UDim2.fromOffset(12, 308), Size = UDim2.new(1, -24, 0, 24),
    BackgroundTransparency = 1, Text = "Status: starting",
    TextSize = 11, Font = Enum.Font.Gotham,
    TextColor3 = Color3.fromRGB(197, 210, 225),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, main)

local matchStatus = make("TextLabel", {
    Position = UDim2.fromOffset(12, 333), Size = UDim2.new(1, -24, 0, 26),
    BackgroundTransparency = 1, Text = "4v4: Decline > Queue > Play > models",
    TextSize = 11, Font = Enum.Font.GothamSemibold,
    TextColor3 = Color3.fromRGB(163, 205, 249),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, main)

local eventStatus = make("TextLabel", {
    Position = UDim2.fromOffset(12, 365), Size = UDim2.new(1, -24, 0, 25),
    BackgroundTransparency = 1, Text = "No-move event: OFF | Calls: 0",
    TextSize = 11, Font = Enum.Font.GothamSemibold,
    TextColor3 = Color3.fromRGB(133, 221, 209),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, main)

local declineBtn = button("AUTO DECLINE REJOIN: ON", 403)
local declineStatus = make("TextLabel", {
    Position = UDim2.fromOffset(12, 441), Size = UDim2.new(1, -24, 0, 22),
    BackgroundTransparency = 1, Text = "Rejoin popup: waiting",
    TextSize = 11, Font = Enum.Font.GothamSemibold,
    TextColor3 = Color3.fromRGB(163, 205, 249),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, main)

local bubble = make("TextButton", {
    Name = "OpenButton", Size = UDim2.fromOffset(48, 48),
    Position = UDim2.new(0, 20, 0.5, 0), Visible = false,
    BackgroundColor3 = Color3.fromRGB(32, 47, 64), BorderSizePixel = 0,
    Text = "ZHM", TextSize = 13, Font = Enum.Font.GothamBold,
    TextColor3 = Color3.new(1, 1, 1),
}, gui)
make("UICorner", {CornerRadius = UDim.new(1, 0)}, bubble)
make("UIStroke", {Color = Color3.fromRGB(84, 197, 226), Thickness = 2}, bubble)

-- Start minimized on execution; tap the floating ZHM circle to reopen.
main.Visible = false
bubble.Visible = true

-- Touch + mouse dragging from header; bubble draggable too.
local function draggable(target, grip)
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    local c1 = grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, target.Position
            local endConnection
            endConnection = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    endConnection:Disconnect()
                end
            end)
        end
    end)
    local c2 = grip.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    local c3 = UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart and startPos then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    table.insert(connections, c1)
    table.insert(connections, c2)
    table.insert(connections, c3)
end
-- Header buttons are still clickable; drag only when starting away from minimize.
draggable(main, header)
draggable(bubble, bubble)

local function getRoot()
    local character = player.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid or humanoid.Health <= 0 then return nil end
    return root
end

-- Get the actual center of the model, rather than the first arbitrary child part.
-- Bounding box stays accurate even when the model has no PrimaryPart.
local function targetPosition(model)
    if not model or not model.Parent then return nil end
    local ok, bounds = pcall(function()
        return model:GetBoundingBox()
    end)
    if ok and bounds then
        return bounds.Position
    end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function getPart(model)
    if not model or not model.Parent then return nil end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

-- A collectible is the outermost Model under SpawnablesClient, even inside folders.
-- This prevents targeting every decorative sub-model within a collectible.
local function isCollectibleModel(inst)
    if not inst:IsA("Model") or not inst:IsDescendantOf(spawnables) then return false end
    local parent = inst.Parent
    while parent and parent ~= spawnables do
        if parent:IsA("Model") then return false end
        parent = parent.Parent
    end
    return getPart(inst) ~= nil
end

local function refreshCandidates()
    table.clear(candidates)
    for _, inst in ipairs(spawnables:GetDescendants()) do
        if inst:IsA("Model") and isCollectibleModel(inst) then
            candidates[#candidates + 1] = inst
        end
    end
end

local function removeESP(model)
    local entry = espObjects[model]
    if entry then
        if entry.highlight then entry.highlight:Destroy() end
        if entry.tag then entry.tag:Destroy() end
        espObjects[model] = nil
    end
end
local function addESP(model, part)
    if espObjects[model] then
        local item = espObjects[model]
        if item.tag and item.tag.Adornee ~= part then item.tag.Adornee = part end
        return
    end
    local hl = Instance.new("Highlight")
    hl.Name = "ZHM_EventHighlight"
    hl.Adornee = model
    hl.FillColor = Color3.fromRGB(0, 213, 194)
    hl.FillTransparency = 0.75
    hl.OutlineColor = Color3.fromRGB(60, 255, 217)
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = gui

    local tag = Instance.new("BillboardGui")
    tag.Name = "ZHM_EventNameTag"
    tag.Adornee = part
    tag.AlwaysOnTop = true
    tag.MaxDistance = 1000
    tag.Size = UDim2.fromOffset(175, 42)
    tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    tag.Parent = gui
    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.fromScale(1, 1)
    txt.BackgroundTransparency = 1
    txt.Text = model.Name
    txt.TextColor3 = Color3.fromRGB(255, 255, 255)
    txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    txt.TextStrokeTransparency = 0.15
    txt.TextSize = 14
    txt.Font = Enum.Font.GothamBold
    txt.TextTruncate = Enum.TextTruncate.AtEnd
    txt.Parent = tag
    espObjects[model] = {highlight = hl, tag = tag}
end

local function updateESP(root)
    if not showESP then
        for model in pairs(espObjects) do removeESP(model) end
        return
    end
    local nearby = {}
    for _, model in ipairs(candidates) do
        local part = getPart(model)
        if part then
            nearby[#nearby + 1] = {
                model = model, part = part,
                distance = root and (part.Position - root.Position).Magnitude or 0,
            }
        end
    end
    table.sort(nearby, function(a, b) return a.distance < b.distance end)
    local displayed = {}
    for i = 1, math.min(maxESP, #nearby) do
        local item = nearby[i]
        displayed[item.model] = true
        addESP(item.model, item.part)
    end
    for model in pairs(espObjects) do
        if not displayed[model] then removeESP(model) end
    end
end

local function nearestEligible(root)
    local best, bestPosition, bestDistance = nil, nil, math.huge
    local now = os.clock()
    for _, model in ipairs(candidates) do
        if isCollectibleModel(model) and (not lastAttempt[model] or now - lastAttempt[model] >= retryAfter) then
            local position = targetPosition(model)
            if position then
                local distance = (position - root.Position).Magnitude
                if distance < bestDistance then
                    best, bestPosition, bestDistance = model, position, distance
                end
            end
        end
    end
    return best, bestPosition, bestDistance
end

local function stopTween()
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end
end

local function stopAll()
    if not running then return end
    running = false
    stopTween()
    for model in pairs(espObjects) do removeESP(model) end
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    gui:Destroy()
    if env.ZHM_EventCollect_Stop == stopAll then
        env.ZHM_EventCollect_Stop = nil
    end
end
env.ZHM_EventCollect_Stop = stopAll

-- Both collection modes are independent and can be enabled simultaneously.
-- "No-movement" only means this extra loop never moves the character itself;
-- the tween collector can still move the character while both are enabled.
local function refreshCollectorButtons()
    collectBtn.Text = "AUTO COLLECT (TWEEN): " .. (autoCollect and "ON" or "OFF")
    collectBtn.BackgroundColor3 = autoCollect and Color3.fromRGB(43, 61, 79) or Color3.fromRGB(88, 49, 56)
    eventBtn.Text = "NO-MOVEMENT AUTO EVENT: " .. (autoEvent and "ON" or "OFF")
    eventBtn.BackgroundColor3 = autoEvent and Color3.fromRGB(28, 125, 93) or Color3.fromRGB(88, 49, 56)
end
local function refreshEventInterval()
    eventIntervalLabel.Text = ("Event interval: %.2f sec"):format(eventInterval)
end
refreshCollectorButtons()
refreshEventInterval()

collectBtn.MouseButton1Click:Connect(function()
    autoCollect = not autoCollect
    if not autoCollect then
        stopTween()
        currentTarget = nil
    end
    refreshCollectorButtons()
end)
eventBtn.MouseButton1Click:Connect(function()
    -- This remote-only loop never changes or stops tween collection.
    autoEvent = not autoEvent
    refreshCollectorButtons()
end)
slowerEventBtn.MouseButton1Click:Connect(function()
    eventInterval = math.max(0.10, math.floor((eventInterval - 0.05) * 100 + 0.5) / 100)
    refreshEventInterval()
end)
fasterEventBtn.MouseButton1Click:Connect(function()
    eventInterval = math.min(3.00, math.floor((eventInterval + 0.05) * 100 + 0.5) / 100)
    refreshEventInterval()
end)
matchBtn.MouseButton1Click:Connect(function()
    auto4v4 = not auto4v4
    matchBtn.Text = "AUTO PLAY 4V4 (QUEUE): " .. (auto4v4 and "ON" or "OFF")
    matchBtn.BackgroundColor3 = auto4v4 and Color3.fromRGB(43, 61, 79) or Color3.fromRGB(88, 49, 56)
    playHandled = false -- re-arm both trigger sources
    lowModelHandled = false
    if resetMatchmakingAttempts then resetMatchmakingAttempts() end
    matchStatus.Text = auto4v4 and "4v4: Decline > Queue > Play > models" or "4v4: disabled"
end)
declineBtn.MouseButton1Click:Connect(function()
    autoDecline = not autoDecline
    declineBtn.Text = "AUTO DECLINE REJOIN: " .. (autoDecline and "ON" or "OFF")
    declineBtn.BackgroundColor3 = autoDecline and Color3.fromRGB(43, 61, 79)
        or Color3.fromRGB(88, 49, 56)
    if not autoDecline then declineStatus.Text = "Rejoin popup: auto decline paused" end
end)
espBtn.MouseButton1Click:Connect(function()
    showESP = not showESP
    espBtn.Text = "MODEL ESP + NAMES: " .. (showESP and "ON" or "OFF")
    espBtn.BackgroundColor3 = showESP and Color3.fromRGB(43, 61, 79) or Color3.fromRGB(88, 49, 56)
    if not showESP then updateESP(nil) end
end)
speedBox.FocusLost:Connect(function()
    local num = tonumber(speedBox.Text)
    if num and num >= 5 and num <= 1000 then
        tweenSpeed = num
        stopTween()
    end
    speedBox.Text = tostring(tweenSpeed)
end)
mini.MouseButton1Click:Connect(function()
    main.Visible = false
    bubble.Position = main.Position
    bubble.Visible = true
end)
bubble.MouseButton1Click:Connect(function()
    bubble.Visible = false
    main.Position = bubble.Position
    main.Visible = true
end)

-- Fresh scan at startup and when models are inserted/removed. Periodic refresh
-- also catches models that receive their parts just after they are created.
local dirty = true
table.insert(connections, spawnables.DescendantAdded:Connect(function(inst)
    if inst:IsA("Model") or inst:IsA("BasePart") then dirty = true end
end))
table.insert(connections, spawnables.DescendantRemoving:Connect(function(inst)
    if inst:IsA("Model") or inst:IsA("BasePart") then dirty = true end
    if espObjects[inst] then removeESP(inst) end
end))
table.insert(connections, player.CharacterRemoving:Connect(function()
    stopTween()
    currentTarget = nil
end))

-- Scanner is intentionally separate from movement so the UI stays live.
task.spawn(function()
    while running do
        if dirty then
            dirty = false
            refreshCandidates()
        end
        liveModelCount = #candidates
        scannerReady = true
        countLabel.Text = "Live models: " .. tostring(liveModelCount)
        updateESP(getRoot())
        task.wait(0.55)
        -- Periodic recheck even if a model was added without parts initially.
        dirty = true
    end
end)

-- Independent remote-only collection loop: adds no tween, teleport, or movement of its own.
-- Sending FireServer successfully does not prove the server awarded an event.
task.spawn(function()
    while running do
        if autoEvent then
            if not collectRemote or not collectRemote.Parent then
                local n = ReplicatedStorage:FindFirstChild("Packages")
                n = n and n:FindFirstChild("Networking")
                collectRemote = n and n:FindFirstChild("RE/Events/CollectEventSpawnable")
                if not collectRemote and n then
                    local re = n:FindFirstChild("RE")
                    local ev = re and re:FindFirstChild("Events")
                    collectRemote = ev and ev:FindFirstChild("CollectEventSpawnable")
                end
            end
            if collectRemote and collectRemote:IsA("RemoteEvent") then
                local ok, err = pcall(function()
                    collectRemote:FireServer() -- zero arguments, no movement
                end)
                if ok then
                    eventAttempts = eventAttempts + 1
                    eventStatus.Text = ("No-move event: sending | Calls: %d"):format(eventAttempts)
                else
                    eventLastError = tostring(err)
                    eventStatus.Text = "No-move event: remote error"
                    warn("[ZHM No-Movement Event] " .. eventLastError)
                end
            else
                eventStatus.Text = "No-move event: remote missing"
            end
            task.wait(eventInterval)
        else
            eventStatus.Text = ("No-move event: OFF | Calls: %d"):format(eventAttempts)
            task.wait(0.15)
        end
    end
end)

-- Lock each target until precisely reached. Only then choose the next one.
-- Small direct-to-center tween segments allow moving models to be tracked
-- without selecting a different, closer model mid-route.
local function tweenExactlyToModel(target)
    while running and autoCollect do
        local root = getRoot()
        if not root or not isCollectibleModel(target) then return false end
        local destination = targetPosition(target)
        if not destination then return false end
        local distance = (destination - root.Position).Magnitude
        if distance <= arrivalDistance then
            stopTween()
            return true
        end

        statusLabel.Text = ("Tweening: %s (%.1f studs)"):format(target.Name, distance)
        -- A short segment ends at the exact model position if close enough.
        local duration = math.min(distance / tweenSpeed, 0.20)
        local ratio = math.min(1, tweenSpeed * duration / distance)
        local goalPosition = root.Position:Lerp(destination, ratio)
        local goalCFrame = CFrame.new(goalPosition) * root.CFrame.Rotation
        local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
            CFrame = goalCFrame,
        })
        activeTween = tween
        tween:Play()

        -- Wait for this specific step; cancel if the model vanishes or toggled off.
        local started = os.clock()
        while running and autoCollect and activeTween == tween
            and os.clock() - started < duration + 0.08 do
            if not target:IsDescendantOf(spawnables) then break end
            task.wait(0.025)
        end
        if activeTween == tween then
            tween:Cancel()
            activeTween = nil
        end
        -- If the model changed position while moving, recompute a fresh goal.
        task.wait(0.015)
    end
    return false
end

task.spawn(function()
    while running do
        if not autoCollect then
            currentTarget = nil
            statusLabel.Text = "Status: paused"
            task.wait(0.2)
        else
            local root = getRoot()
            if not root then
                statusLabel.Text = "Status: waiting for character"
                task.wait(0.3)
            else
                local target = nearestEligible(root)
                if not target then
                    currentTarget = nil
                    statusLabel.Text = "Status: waiting for spawnables"
                    task.wait(0.2)
                else
                    -- Target never switches to a new model until exact arrival.
                    currentTarget = target
                    local arrived = tweenExactlyToModel(target)
                    if arrived and running and autoCollect and isCollectibleModel(target) then
                        local currentRoot = getRoot()
                        local pos = targetPosition(target)
                        if currentRoot and pos
                            and (currentRoot.Position - pos).Magnitude <= arrivalDistance then
                            lastAttempt[target] = os.clock()
                            statusLabel.Text = "Collecting: " .. target.Name
                            -- The supplied CollectEventSpawnable remote takes no arguments.
                            local ok, err = pcall(function()
                                collectRemote:FireServer()
                            end)
                            if not ok then
                                warn("[ZHM] Collection remote failed: " .. tostring(err))
                            end
                            -- Immediately look for a different nearest model.
                            task.wait(0.15)
                        end
                    end
                    currentTarget = nil
                    task.wait(0.025)
                end
            end
        end
    end
end)


-- ZHM 4v4 / restored visible PLAY detection.
-- Priority: visible DECLINE > QUEUE/QUEUE AGAIN > PLAY > model count 1..19 > idle.
-- Visible GUI uses the original button scan and firesignal-first activation
-- that was used in the earlier PLAY-on-GUI version.
-- IMPORTANT: FireServer() for matchmaking is intentionally not guessed here:
-- the available action log does not show matchmaking's remote arguments.
local function shown(inst)
    if not inst then return false end
    while inst and inst ~= playerGui do
        if inst:IsA("GuiObject") and not inst.Visible then return false end
        if inst:IsA("ScreenGui") and not inst.Enabled then return false end
        inst = inst.Parent
    end
    return true
end

local function buttonUnder(inst)
    if not inst then return nil end
    if inst:IsA("GuiButton") then return inst end
    return inst:FindFirstChildWhichIsA("GuiButton", true)
end

local function textIs(inst, wanted)
    if not inst then return false end
    wanted = wanted:upper()
    if inst:IsA("TextLabel") or inst:IsA("TextButton") then
        if tostring(inst.Text):match("^%s*(.-)%s*$"):upper() == wanted then
            return true
        end
    end
    for _, child in ipairs(inst:GetDescendants()) do
        if (child:IsA("TextLabel") or child:IsA("TextButton"))
            and shown(child)
            and tostring(child.Text):match("^%s*(.-)%s*$"):upper() == wanted then
            return true
        end
    end
    return false
end

local function visiblePlayButton(mm, actionObject)
    if not mm or not shown(mm) then return nil end
    -- Use the original action path, but scan other PLAY buttons when necessary.
    if actionObject and shown(actionObject) and textIs(actionObject, "PLAY") then
        local btn = buttonUnder(actionObject)
        if btn and btn.Active and shown(btn) then return btn end
    end
    for _, child in ipairs(mm:GetDescendants()) do
        if child:IsA("GuiButton") and child.Active and shown(child)
            and textIs(child, "PLAY") then
            return child
        end
    end
    return nil
end

local function visible4v4Button(mm, modeObject)
    if not mm then return nil end
    if modeObject and shown(modeObject) then
        local btn = buttonUnder(modeObject)
        if btn and btn.Active and shown(btn) then return btn end
    end
    for _, child in ipairs(mm:GetDescendants()) do
        if child:IsA("GuiButton") and child.Active and shown(child)
            and textIs(child, "4V4") then
            return child
        end
    end
    return nil
end

local function pressGuiButton(btn)
    if not btn or not btn.Active then return false end
    -- Restore the previous working order: firesignal BEFORE getconnections.
    if type(firesignal) == "function" then
        if pcall(function() firesignal(btn.Activated) end) then return true end
        if pcall(function() firesignal(btn.MouseButton1Click) end) then return true end
    end
    if type(getconnections) == "function" then
        for _, sig in ipairs({btn.Activated, btn.MouseButton1Click}) do
            local ok, listeners = pcall(function() return getconnections(sig) end)
            if ok and type(listeners) == "table" then
                for _, conn in ipairs(listeners) do
                    if type(conn.Fire) == "function" then
                        if pcall(function() conn:Fire() end) then return true end
                    end
                end
            end
        end
    end
    return false
end

-- Shared priority gate: when a visible RejoinPopup Decline control exists,
-- matchmaking must never attempt to select a mode or press PLAY.
local function rejoinDeclineVisible()
    if not autoDecline then return false end
    local rejoinGui = playerGui:FindFirstChild("RejoinPopup")
    local popup = rejoinGui and rejoinGui:FindFirstChild("Popup")
    local declineObject = popup and popup:FindFirstChild("Decline")
    local btn = buttonUnder(declineObject)
    return btn ~= nil and btn.Active and shown(btn)
end

-- Auto Decline has PRIORITY over all Auto Play 4v4 attempts.
-- Its visible popup suspends matchmaking but does not interrupt collection.
-- Retries are spaced out if a popup remains visible after a signal is sent.
task.spawn(function()
    local lastDeclineTime = -math.huge
    local lastDeclineButton = nil
    while running do
        if not autoDecline then
            lastDeclineButton = nil
        else
            local rejoinGui = playerGui:FindFirstChild("RejoinPopup")
            local popup = rejoinGui and rejoinGui:FindFirstChild("Popup")
            local declineObject = popup and popup:FindFirstChild("Decline")
            local declineButton = buttonUnder(declineObject)
            local visible = declineButton and declineButton.Active and shown(declineButton)
            if visible then
                -- New popup/button gets an immediate attempt, persistent popups
                -- get a bounded retry rather than per-frame button spam.
                local now = os.clock()
                if declineButton ~= lastDeclineButton or now - lastDeclineTime >= 2 then
                    lastDeclineButton = declineButton
                    lastDeclineTime = now
                    if pressGuiButton(declineButton) then
                        declineAttempts = declineAttempts + 1
                        declineStatus.Text = ("Rejoin popup: Decline pressed (%d)"):format(declineAttempts)
                    else
                        declineStatus.Text = "Rejoin popup: decline handler unavailable"
                    end
                end
            else
                lastDeclineButton = nil
                declineStatus.Text = ("Rejoin popup: waiting | attempts %d"):format(declineAttempts)
            end
        end
        task.wait(0.25)
    end
end)

local function matchmakingControls(mm)
    if not mm then return nil, nil end
    local bottom = mm:FindFirstChild("Bottom")
    local sel = bottom and bottom:FindFirstChild("SelectedMode")
    local mode = sel and sel:FindFirstChild("4v4")
    local mainSection = bottom and bottom:FindFirstChild("Main")
    local action = mainSection and mainSection:FindFirstChild("Action")
    return mode, action
end

local function queueActive(action)
    if not action then return false end
    local items = {action}
    for _, d in ipairs(action:GetDescendants()) do items[#items + 1] = d end
    for _, item in ipairs(items) do
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            local t = tostring(item.Text):upper()
            if t:find("CANCEL", 1, true) or t:find("SEARCHING", 1, true)
                or t:find("QUEUED", 1, true) or t:find("LEAVE QUEUE", 1, true) then
                return true
            end
        end
    end
    return false
end

-- Detect exact actionable button labels, including TextLabels nested in ImageButtons.
-- The Action GUI was recorded in the logs; rematch remote arguments were NOT,
-- so this feature presses the GUI rather than guessing a FireServer payload.
local function visibleQueueButton(mm, actionObject)
    local function exactQueue(text)
        local clean = tostring(text or ""):gsub("<[^>]*>", "")
        clean = clean:upper():gsub("%s+", " "):match("^%s*(.-)%s*$")
        return clean == "QUEUE AGAIN" or clean == "QUEUE"
    end
    local function matches(button)
        if not button or not button:IsA("GuiButton") or not button.Active or not shown(button) then
            return false
        end
        if button:IsA("TextButton") and exactQueue(button.Text) then return true end
        for _, label in ipairs(button:GetDescendants()) do
            if (label:IsA("TextLabel") or label:IsA("TextButton"))
                and shown(label) and exactQueue(label.Text) then
                return true
            end
        end
        return false
    end

    -- Try the logged matchmaking Action path first.
    if actionObject and shown(actionObject) then
        local btn = buttonUnder(actionObject)
        if matches(btn) then return btn end
    end

    -- Queue Again can also appear in a post-match/rejoin screen, not Matchmaking.
    -- Only choose actual visible, active buttons, never a status label or overlay.
    local function search(root)
        if not root then return nil end
        if matches(root) then return root end
        for _, item in ipairs(root:GetDescendants()) do
            if item:IsA("GuiButton") and matches(item) then return item end
        end
        return nil
    end
    return search(mm) or search(playerGui)
end

local lastMatchAttempt = -math.huge
local retrySeconds = 5
local playedThisAppearance = false
local lastSeenPlay = nil
local lastSeenQueue = nil
local queuePressAttempts = 0
resetMatchmakingAttempts = function()
    playedThisAppearance = false
    lastSeenPlay = nil
    lastSeenQueue = nil
    lastMatchAttempt = -math.huge
end

local function attemptGui(mm, modeObject)
    if rejoinDeclineVisible() then return false, "4v4: waiting for Auto Decline" end
    local modeBtn = visible4v4Button(mm, modeObject)
    if not modeBtn then return false, "4v4: PLAY found; 4v4 button missing" end
    if not pressGuiButton(modeBtn) then
        return false, "4v4: unable to activate 4v4 mode"
    end
    task.wait(0.2)
    if not running or not auto4v4 then return false, "4v4: stopped" end
    if rejoinDeclineVisible() then return false, "4v4: waiting for Auto Decline" end
    local _, newAction = matchmakingControls(mm)
    if visibleQueueButton(mm, newAction) then
        return false, "4v4: QUEUE GUI appeared; deferring PLAY"
    end
    local newPlay = visiblePlayButton(mm, newAction)
    if not newPlay then return false, "4v4: PLAY disappeared after mode select" end
    if pressGuiButton(newPlay) then
        return true, "4v4: 4v4 + PLAY attempted"
    end
    return false, "4v4: unable to activate PLAY"
end

-- Hidden GUI handler attempt when live model count is below 20. This is a
-- fallback, not a second GUI attempt; it will never run while a visible PLAY
-- button exists. Server may reject it or the GUI may not be loaded at all.
local function attemptLowModels(mm, modeObject, actionObject)
    if rejoinDeclineVisible() then return false, "4v4: waiting for Auto Decline" end
    if not mm then return false, "4v4: <20 models; matchmaking GUI not loaded" end
    local modeBtn = buttonUnder(modeObject)
    local actionBtn = buttonUnder(actionObject)
    if not modeBtn or not actionBtn then
        return false, "4v4: <20 models; hidden GUI controls missing"
    end
    if not pressGuiButton(modeBtn) then
        return false, "4v4: <20 models; 4v4 handler unavailable"
    end
    task.wait(0.2)
    if not running or not auto4v4 then return false, "4v4: stopped" end
    if rejoinDeclineVisible() then return false, "4v4: waiting for Auto Decline" end
    local _, updatedAction = matchmakingControls(mm)
    if visibleQueueButton(mm, updatedAction) then
        return false, "4v4: QUEUE GUI appeared; deferring model trigger"
    end
    actionBtn = buttonUnder(updatedAction)
    if actionBtn and pressGuiButton(actionBtn) then
        return true, "4v4: <20 models; hidden PLAY attempted"
    end
    return false, "4v4: <20 models; PLAY handler unavailable"
end

task.spawn(function()
    while running do
        if not auto4v4 then
            matchStatus.Text = "4v4: disabled"
            playedThisAppearance = false
            lastSeenPlay = nil
            lastSeenQueue = nil
        elseif rejoinDeclineVisible() then
            -- Highest priority: Auto Decline handles the popup; don't even try
            -- selecting 4v4 or pressing PLAY until the rejoin dialog vanishes.
            playedThisAppearance = false
            lastSeenPlay = nil
            lastSeenQueue = nil
            lastMatchAttempt = -math.huge -- resume immediately after dismissal
            matchStatus.Text = "4v4: paused -- Auto Decline priority"
        else
            local mm = playerGui:FindFirstChild("Matchmaking")
            local modeObject, actionObject = matchmakingControls(mm)
            local queueBtn = visibleQueueButton(mm, actionObject)
            local playBtn = visiblePlayButton(mm, actionObject)
            local count = liveModelCount
            local below20 = scannerReady and count >= 1 and count <= 19
            local queued = queueActive(actionObject)
            local now = os.clock()

            if queueBtn then
                -- Queue/Queue Again has priority over PLAY and model count.
                -- Immediately attempt when a new button appears, then throttle
                -- retries while it remains visible (never invoke two paths).
                playedThisAppearance = false
                lastSeenPlay = nil
                if lastSeenQueue ~= queueBtn then
                    lastSeenQueue = queueBtn
                    lastMatchAttempt = -math.huge
                end
                if now - lastMatchAttempt >= retrySeconds then
                    lastMatchAttempt = now
                    if pressGuiButton(queueBtn) then
                        queuePressAttempts = queuePressAttempts + 1
                        matchStatus.Text = ("4v4: QUEUE pressed (%d); awaiting change"):format(queuePressAttempts)
                    else
                        matchStatus.Text = "4v4: QUEUE visible; button handler unavailable"
                    end
                else
                    matchStatus.Text = "4v4: QUEUE visible; waiting/retry cooldown"
                end
            elseif queued and not playBtn then
                lastSeenQueue = nil
                -- A visible PLAY control has priority over stale queue labels.
                playedThisAppearance = true
                matchStatus.Text = "4v4: queue already active"
            elseif playBtn then
                lastSeenQueue = nil
                -- PLAY priority whenever no visible QUEUE action exists; overrides
                -- the model counter, including when models <20.
                if lastSeenPlay ~= playBtn then
                    playedThisAppearance = false
                    lastSeenPlay = playBtn
                end
                if not playedThisAppearance and now - lastMatchAttempt >= retrySeconds then
                    lastMatchAttempt = now
                    local ok, message = attemptGui(mm, modeObject)
                    playedThisAppearance = ok
                    matchStatus.Text = "GUI priority | " .. message
                elseif playedThisAppearance then
                    matchStatus.Text = "4v4: GUI PLAY attempted; awaiting transition"
                else
                    matchStatus.Text = "4v4: GUI retry cooldown"
                end
            else
                lastSeenQueue = nil
                -- Re-arm visible GUI next time it appears.
                playedThisAppearance = false
                lastSeenPlay = nil
                if below20 then
                    if now - lastMatchAttempt >= retrySeconds then
                        lastMatchAttempt = now
                        local _, message = attemptLowModels(mm, modeObject, actionObject)
                        matchStatus.Text = message
                    else
                        matchStatus.Text = "4v4: <20 models; waiting to retry"
                    end
                elseif not scannerReady then
                    matchStatus.Text = "4v4: scanning models..."
                else
                    matchStatus.Text = ("4v4: %d models; waiting for PLAY"):format(count)
                end
            end
        end
        task.wait(0.35)
    end
end)

print("[ZHM] Priority Decline > QUEUE/QUEUE AGAIN > PLAY GUI > models 1-19; both collectors ON")
