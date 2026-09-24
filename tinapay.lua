-- // Services Setup
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")

local ENV = (getgenv and getgenv()) or _G

-- Instant Proximity is a permanent core feature: always ON, not config-controlled.
ENV.ZHM_AutoNearestPrompt = true

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- FOV CHANGER CORE
-- No separate FOV GUI. Controls are installed directly inside ZHM HUB -> EXTRA.
--------------------------------------------------------------------------------
-- Clean up the old standalone FOV window if a previous version is still loaded.
if playerGui:FindFirstChild("FOVChanger") then
    playerGui:FindFirstChild("FOVChanger"):Destroy()
end


-- MAIN ZHM SCOPE
-- Keeps this very large module from exhausting Luau's 200-local-register limit.
do
-- ADAPTIVE LIVE INSTANT PROXIMITY
-- PC keeps the current safe live behavior.
-- Mobile uses a lighter PromptShown-only method to avoid touch UI glitches.
local IS_MOBILE_DEVICE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function makePromptInstantSafe(prompt)
    if ENV.ZHM_AutoNearestPrompt ~= true then return end
    if not prompt or not prompt:IsA("ProximityPrompt") then return end

    pcall(function()
        prompt.HoldDuration = 0
    end)
end

if IS_MOBILE_DEVICE then
    ------------------------------------------------------------------------
    -- MOBILE MODE
    -- Do NOT scan/edit every prompt in Workspace.
    -- Only modify a prompt when Roblox actually displays it to this player.
    -- This prevents large batches of prompt-property updates from fighting
    -- with the mobile touch ProximityPrompt UI.
    ------------------------------------------------------------------------
    ProximityPromptService.PromptShown:Connect(function(prompt)
        makePromptInstantSafe(prompt)
    end)

else
    ------------------------------------------------------------------------
    -- PC MODE
    -- Preserve the version that was already working well on desktop.
    ------------------------------------------------------------------------

    -- Existing prompts.
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            makePromptInstantSafe(obj)
        end
    end

    -- Newly-created prompts.
    Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("ProximityPrompt") then
            makePromptInstantSafe(obj)

            -- Some games configure HoldDuration just after parenting.
            task.delay(0.05, function()
                if obj and obj.Parent then
                    makePromptInstantSafe(obj)
                end
            end)
        end
    end)

    -- Re-apply whenever a prompt becomes visible.
    ProximityPromptService.PromptShown:Connect(function(prompt)
        makePromptInstantSafe(prompt)
    end)
end

--------------------------------------------------------------------------------
-- ZHM HUB - SHARED UI / COMPATIBILITY HELPERS
--------------------------------------------------------------------------------
-- Integrated FOV state is opt-in. Executing the hub does not change the camera.
ENV.ZHM_FOV = tonumber(ENV.ZHM_FOV)
    or (Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView)
    or 70
ENV.ZHM_FOVActive = false
ENV.ZHM_ApplyFOV = function(value)
    value = tonumber(value)
    if not value then return false end

    value = math.clamp(value, 1, 120)
    ENV.ZHM_FOV = value
    ENV.ZHM_FOVActive = true

    local camera = Workspace.CurrentCamera
    if camera then
        camera.FieldOfView = value
    end

    return true
end

-- Only re-apply FOV after the user has enabled/applied it from the UI (or loaded a config).
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    task.wait()
    if ENV.ZHM_FOVActive == true and ENV.ZHM_ApplyFOV then
        ENV.ZHM_ApplyFOV(ENV.ZHM_FOV or 70)
    end
end)

local controller = { CancelGeneration = 0 }
ENV.ZHM_Controller = controller

-- Every optional user-facing feature starts OFF on every execution.
-- Instant Proximity is the one exception and stays permanently ON.
-- Saved settings are restored automatically on execute when a config file exists.
ENV.ZHM_ConfigKeys = {
    "ZHM_AutoWalk",
    "ZHM_AutoFarm",
    "ZHM_AutoBuy",
    "ZHM_AutoBuyBakingRack",
    "ZHM_AutoUpgrade",
    "ZHM_SpamDisplayRackPrompts",
    "ZHM_BakingRackScanner",
    "ZHM_ExpandBakingRackPrompts",
    "ZHM_AutoSweep",
    "ZHM_NPCAutoTP",
    "ZHM_NPCAutoSwing",
    "ZHM_AutoAccept",
    "ZHM_AutoPrepareDough",
    "ZHM_AutoBake",
    "ZHM_AutoCollect",
    "ZHM_AutoCollectTip",
    "ZHM_AutoGiveOrder",
    "ZHM_AutoPayCashier",
    "ZHM_AutoEnableBreads",
    "ZHM_HidePopups",
    "ZHM_NPCHitbox",
    "ZHM_NPCHitboxESP",
}
for _, featureKey in ipairs(ENV.ZHM_ConfigKeys) do
    ENV[featureKey] = false
end
ENV.ZHM_AutoNearestPrompt = true

local TP_DELAY = 1 -- 1 second between movement teleports.
ENV.ZHM_BakingRackStatus = "BakingRack scanner disabled"
ENV.ZHM_BuyBakingRackStatus = "Auto Buy Baking Rack disabled"
ENV.ZHM_SweepActive = false
ENV.ZHM_NPCBusy = false
ENV.ZHM_NPCStatus = "Swing scanner idle"
ENV.ZHM_SweepStatus = "Waiting"
ENV.ZHM_SwingRollingPinNow = nil -- refreshed later by the Rolling Pin module
if type(ENV.CashierAutoAccept) == "table" then
    ENV.CashierAutoAccept.Enabled = false
    ENV.CashierAutoAccept = nil
end

local THEME = {
    Background  = Color3.fromRGB(13, 14, 22),
    Surface     = Color3.fromRGB(20, 22, 34),
    Surface2    = Color3.fromRGB(28, 30, 46),
    Surface3    = Color3.fromRGB(38, 41, 61),
    Accent      = Color3.fromRGB(124, 58, 237),  -- Vibrant Violet
    Accent2     = Color3.fromRGB(6, 182, 212),    -- Electric Cyan
    Success     = Color3.fromRGB(16, 185, 129),
    Danger      = Color3.fromRGB(239, 68, 68),
    Warning     = Color3.fromRGB(245, 158, 11),
    Text        = Color3.fromRGB(248, 250, 252),
    Muted       = Color3.fromRGB(148, 163, 184),
    Stroke      = Color3.fromRGB(51, 65, 85)
}


local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 10)
    corner.Parent = parent
    return corner
end

local function addStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or THEME.Stroke
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

local function addGradient(parent, colorA, colorB, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, colorA),
        ColorSequenceKeypoint.new(1, colorB)
    })
    gradient.Rotation = rotation or 0
    gradient.Parent = parent
    return gradient
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
            local existing = parent:FindFirstChild(name)
            if existing then
                existing:Destroy()
            end
        end)
    end
end

local function mountGui(gui)
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then
            local mounted = pcall(function() gui.Parent = hui end)
            if mounted and gui.Parent then return gui.Parent end
        end
    end

    local mounted = pcall(function() gui.Parent = CoreGui end)
    if not mounted or not gui.Parent then
        gui.Parent = playerGui
    end

    return gui.Parent
end

local function bindPressAnimation(button, hoverColor)
    if not button or not button:IsA("GuiButton") then return end

    button.AutoButtonColor = false
    local pressScale = Instance.new("UIScale")
    pressScale.Name = "PressScale"
    pressScale.Scale = 1
    pressScale.Parent = button

    local baseColor = button.BackgroundColor3

    button.MouseEnter:Connect(function()
        if hoverColor then button.BackgroundColor3 = hoverColor end
    end)

    button.MouseLeave:Connect(function()
        if hoverColor then button.BackgroundColor3 = baseColor end
        pressScale.Scale = 1
    end)

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressScale.Scale = 0.95
        end
    end)

    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressScale.Scale = 1
        end
    end)
end

local function makeDraggable(handle, target)
    target = target or handle
    local dragging = false
    local dragInput, dragStart, startPosition

    handle.Active = true

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = target.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
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
    local function update()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local viewport = camera.ViewportSize
        local widthScale = viewport.X / (baseWidth or 420)
        local heightScale = viewport.Y / (baseHeight or 520)
        local scale = math.clamp(math.min(widthScale, heightScale, 1), 0.55, 1)

        scaleObject.Scale = scale
        scaleObject:SetAttribute("ResponsiveScale", scale)
    end

    update()

    if Workspace.CurrentCamera then
        Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
    end

    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        task.wait()
        update()
    end)

    return update
end

--------------------------------------------------------------------------------
-- 0. KEYLESS START
-- Key UI / validation removed. Script continues immediately on execute.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STATIONARY AUTOMATION (OPTIMIZED FOR NO DELAY)
--------------------------------------------------------------------------------
ENV.ZHM_AutoFarm = ENV.ZHM_AutoFarm == true
ENV.ZHM_AutoBuy = ENV.ZHM_AutoBuy == true
ENV.ZHM_AutoUpgrade = ENV.ZHM_AutoUpgrade == true
for _, key in ipairs({ "ZHM_AutoAccept", "ZHM_AutoPrepareDough", "ZHM_AutoBake", "ZHM_AutoCollect", "ZHM_AutoCollectTip", "ZHM_AutoGiveOrder", "ZHM_AutoPayCashier", "ZHM_AutoEnableBreads", "ZHM_HidePopups" }) do
    if ENV[key] == nil then ENV[key] = false end
end
if ENV.ZHM_SilentBakeUI == nil then ENV.ZHM_SilentBakeUI = true end
ENV.ZHM_PlotName = ENV.ZHM_PlotName or "Plot4"
ENV.ZHM_FeatureStatus = {}

local function isCurrent()
    return ENV.ZHM_Controller == controller
end

local function running(key)
    if not isCurrent() or ENV[key] ~= true then
        return false
    end

    -- Trash sweeping owns movement/interaction while an actionable sweep prompt exists.
    -- Toggle values are NOT changed; jobs simply pause and automatically resume afterward.
    if ENV.ZHM_SweepActive == true then
        return false
    end

    -- NPC Auto TP temporarily owns character movement while a valid running Customer
    -- target is active. Pause only the rack-route movement so it cannot instantly
    -- teleport the player away from the detected NPC. Other non-movement jobs continue.
    if key == "ZHM_AutoWalk" and ENV.ZHM_NPCBusy == true then
        return false
    end

    return true
end

local function farming(key)
    if not isCurrent() or ENV.ZHM_AutoFarm ~= true or ENV[key] ~= true then
        return false
    end

    -- Keep the two non-movement delivery jobs alive even while Night Auto Sweep
    -- temporarily owns character movement. This prevents Collect / Give Order
    -- from dying in the middle of a night cycle. Other bakery jobs still pause.
    if ENV.ZHM_SweepActive == true then
        return key == "ZHM_AutoCollect"
            or key == "ZHM_AutoCollectTip"
            or key == "ZHM_AutoGiveOrder"
    end

    return true
end

local notices = {}
local function report(feature, message)
    if not isCurrent() then return end
    ENV.ZHM_FeatureStatus[feature] = message
    local last = notices[feature]
    if not last or os.clock() - last >= 20 then
        notices[feature] = os.clock()
        warn("[ZHM/" .. feature .. "] " .. message)
    end
end

local function resolve(root, names)
    for _, name in ipairs(names) do
        root = root and root:FindFirstChild(name)
        if not root then return nil end
    end
    return root
end

local function ui(names)
    return resolve(player:FindFirstChildOfClass("PlayerGui"), names)
end

local function findMyPlot()
    local shops = resolve(Workspace, { "Game", "Shops" })
    if not shops then return nil end

    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    local closestPlot = nil
    local shortestDist = math.huge

    for _, plot in ipairs(shops:GetChildren()) do
        local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")
        if owner and owner:IsA("ValueBase") then
            if owner.Value == player or owner.Value == player.Name or owner.Value == player.UserId then
                return plot
            end
        end

        if plot:GetAttribute("OwnerUserId") == player.UserId then
            return plot
        end

        if rootPart then
            local anyPart = plot:FindFirstChildWhichIsA("BasePart", true)
            if anyPart then
                local dist = (rootPart.Position - anyPart.Position).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    closestPlot = plot
                end
            end
        end
    end

    return shops:FindFirstChild(ENV.ZHM_PlotName) or closestPlot
end

--------------------------------------------------------------------------------
-- INSTANT TP / RACK MOVEMENT
-- All rack-route tween/Lerp movement has been replaced with direct CFrame TP.
--------------------------------------------------------------------------------
local function getPartFromContainer(container)
    if not container then return nil end
    if container:IsA("BasePart") then return container end
    if container:IsA("Model") and container.PrimaryPart then return container.PrimaryPart end
    return container:FindFirstChildWhichIsA("BasePart", true)
end

local function getDisplayRackPos(plot)
    if not plot then return nil end
    local equipment = plot:FindFirstChild("Equipment") or plot

    for _, desc in ipairs(equipment:GetDescendants()) do
        local lowerName = desc.Name:lower()
        if lowerName:find("displayrack", 1, true) or lowerName:find("display", 1, true) then
            local part = getPartFromContainer(desc)
            if part then return part.Position end
        end
    end

    return nil
end

-- Dough PrepTable destination used at the end of every rack route.
local function getPrepTablePos(plot)
    if not plot then return nil end

    -- Known game path first.
    local position = plot:FindFirstChild("Position")
    local prepTable = position and position:FindFirstChild("PrepTable")
    if prepTable then
        local part = getPartFromContainer(prepTable)
        if part then return part.Position end
    end

    -- Compatibility fallback for renamed/nested PrepTable objects.
    for _, desc in ipairs(plot:GetDescendants()) do
        local lowerName = string.lower(desc.Name or "")
        if lowerName == "preptable"
            or lowerName:find("preptable", 1, true)
            or lowerName:find("doughprep", 1, true) then
            local part = getPartFromContainer(desc)
            if part then return part.Position end
        end
    end

    -- Final fallback: use the PrepTablePrompt's parent part/model.
    local prompt = plot:FindFirstChild("PrepTablePrompt", true)
    if prompt then
        local part = getPartFromContainer(prompt.Parent)
        if part then return part.Position end
    end

    return nil
end

-- Cashier destination used after the Dough PrepTable.
local function getCashierPos(plot)
    if not plot then return nil end

    -- Prefer known objects inside the plot Position folder.
    local position = plot:FindFirstChild("Position") or plot:FindFirstChild("Positions")
    if position then
        for _, wanted in ipairs({
            "Cashier", "CashierPosition", "CashierCounter",
            "CashRegister", "Register", "RegisterPosition"
        }) do
            local obj = position:FindFirstChild(wanted) or position:FindFirstChild(wanted, true)
            if obj then
                local part = getPartFromContainer(obj) or getPartFromContainer(obj.Parent)
                if part then return part.Position end
            end
        end
    end

    -- Compatibility fallback for renamed/nested cashier/register objects.
    for _, desc in ipairs(plot:GetDescendants()) do
        local lowerName = string.lower(desc.Name or "")
        if lowerName:find("cashier", 1, true)
            or lowerName:find("cashregister", 1, true)
            or lowerName == "register"
            or lowerName:find("registerposition", 1, true) then

            local part = getPartFromContainer(desc) or getPartFromContainer(desc.Parent)
            if part then return part.Position end
        end
    end

    -- Final fallback: use CashierPrompt's parent.
    local prompt = plot:FindFirstChild("CashierPrompt", true)
    if prompt then
        local part = getPartFromContainer(prompt.Parent)
        if part then return part.Position end
    end

    return nil
end

-- Oven destination used after the Cashier before restarting the BakingRack loop.
local function getOvenPos(plot)
    if not plot then return nil end

    local equipment = plot:FindFirstChild("Equipment") or plot

    -- Exact path used by the current baking system.
    local ovenRoot = resolve(equipment, { "Oven", "BrownOven", "PlacementRoot" })
    if ovenRoot then
        local part = getPartFromContainer(ovenRoot) or getPartFromContainer(ovenRoot.Parent)
        if part then return part.Position end
    end

    -- Prefer an actual Oven/BrownOven object in Equipment.
    for _, wanted in ipairs({ "BrownOven", "Oven" }) do
        local obj = equipment:FindFirstChild(wanted, true)
        if obj then
            local part = getPartFromContainer(obj) or getPartFromContainer(obj.Parent)
            if part then return part.Position end
        end
    end

    -- Compatibility fallback for renamed oven models.
    for _, desc in ipairs(equipment:GetDescendants()) do
        local lowerName = string.lower(desc.Name or "")
        if lowerName:find("oven", 1, true)
            and not lowerName:find("prompt", 1, true) then
            local part = getPartFromContainer(desc) or getPartFromContainer(desc.Parent)
            if part then return part.Position end
        end
    end

    -- Final fallback: use the BakePrompt's parent/ancestor.
    local prompt = plot:FindFirstChild("BakePrompt", true)
    if prompt then
        local current = prompt.Parent
        while current and current ~= plot do
            local part = getPartFromContainer(current)
            if part then return part.Position end
            current = current.Parent
        end
    end

    return nil
end

local function getAllBakingRacks(plot)
    if not plot then return {} end
    local equipment = plot:FindFirstChild("Equipment") or plot
    local racks = {}
    local seenParts = {}

    for _, desc in ipairs(equipment:GetDescendants()) do
        local lowerName = desc.Name:lower()
        if (lowerName:find("bakingrack", 1, true) or lowerName:find("normalbakingrack", 1, true))
            and not lowerName:find("prompt", 1, true) then
            local part = getPartFromContainer(desc)
            if part and not seenParts[part] then
                seenParts[part] = true
                table.insert(racks, { instance = desc, part = part, position = part.Position })
            end
        end
    end

    return racks
end

local function teleportToPosition(targetPos)
    if not running("ZHM_AutoWalk") then return false end

    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    rootPart.CFrame = CFrame.new(targetPos) * rootPart.CFrame.Rotation
    return true
end

local function getRackNumber(name)
    -- If the game names racks like BakingRack1 / BakingRack2 / Rack 3,
    -- use that number for a clean 1 -> 9 route.
    local value = tostring(name or "")
    local number = value:match("(%d+)%D*$")
    return tonumber(number)
end

local function buildFixedBakingRackRoute(plot)
    local racks = getAllBakingRacks(plot)
    if #racks <= 1 then return racks end

    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    local startPosition = rootPart and rootPart.Position or nil

    -- IMPORTANT: this sort happens ONCE when a route starts.
    -- It is NOT recalculated after each teleport, so the order cannot jump around.
    table.sort(racks, function(a, b)
        local nameA = a.instance and a.instance.Name or ""
        local nameB = b.instance and b.instance.Name or ""
        local numberA = getRackNumber(nameA)
        local numberB = getRackNumber(nameB)

        -- Best case: racks have numbers in their names. Visit 1,2,3...9.
        if numberA and numberB and numberA ~= numberB then
            return numberA < numberB
        elseif numberA and not numberB then
            return true
        elseif numberB and not numberA then
            return false
        end

        -- If all racks use the same name, preserve the old "farthest first" idea,
        -- but calculate it only from the player's position at the START of the cycle.
        if startPosition then
            local distanceA = (startPosition - a.position).Magnitude
            local distanceB = (startPosition - b.position).Magnitude
            if math.abs(distanceA - distanceB) > 0.01 then
                return distanceA > distanceB
            end
        end

        -- Stable position fallback so equal/same-name racks never shuffle randomly.
        if math.abs(a.position.X - b.position.X) > 0.01 then
            return a.position.X < b.position.X
        end
        if math.abs(a.position.Z - b.position.Z) > 0.01 then
            return a.position.Z < b.position.Z
        end
        if math.abs(a.position.Y - b.position.Y) > 0.01 then
            return a.position.Y < b.position.Y
        end

        local pathA = ""
        local pathB = ""
        pcall(function() pathA = a.instance:GetFullName() end)
        pcall(function() pathB = b.instance:GetFullName() end)
        return pathA < pathB
    end)

    return racks
end

local function startAutoWalk()
    task.spawn(function()
        local route = {}
        local routeIndex = 1
        local routePlot = nil

        local function resetRoute()
            route = {}
            routeIndex = 1
            routePlot = nil
        end

        local function ensureRoute(plot)
            -- Build the route once per full cycle (or if the player's plot changes).
            if routePlot ~= plot or #route == 0 then
                routePlot = plot
                route = buildFixedBakingRackRoute(plot)
                routeIndex = 1

                report(
                    "AutoWalk",
                    "Fixed BakingRack route ready: " .. tostring(#route) .. " rack(s)."
                )
            end
        end

        while isCurrent() do
            if running("ZHM_AutoWalk") then
                local myPlot = findMyPlot()

                if myPlot then
                    ensureRoute(myPlot)

                    -- Visit exactly one rack at a time using the route captured above.
                    if routeIndex <= #route then
                        local rack = route[routeIndex]

                        -- If a rack streamed out / disappeared, skip only that entry.
                        if rack and rack.instance and rack.instance.Parent
                            and rack.part and rack.part.Parent then

                            -- Refresh its current position in case the model moved slightly.
                            rack.position = rack.part.Position

                            report(
                                "AutoWalk",
                                "TP BakingRack " .. tostring(routeIndex) .. "/" .. tostring(#route)
                                    .. ": " .. tostring(rack.instance.Name)
                            )

                            if teleportToPosition(rack.position + Vector3.new(0, 2.5, 0))
                                and running("ZHM_AutoWalk") then
                                task.wait(TP_DELAY)
                            end
                        end

                        -- Advance ONCE. No re-sorting from the new player position.
                        routeIndex += 1
                    else
                        local displayPos = getDisplayRackPos(myPlot)

                        if displayPos then
                            report("AutoWalk", "All " .. tostring(#route) .. " BakingRacks visited • TP to DisplayRack...")
                            if teleportToPosition(displayPos + Vector3.new(0, 2.5, 0))
                                and running("ZHM_AutoWalk") then
                                -- Stay at the DisplayRack for exactly 7 seconds.
                                task.wait(7)

                                -- After DisplayRack, TP to the Dough PrepTable before
                                -- resetting the rack route and starting the next loop.
                                if running("ZHM_AutoWalk") then
                                    local prepPos = getPrepTablePos(myPlot)
                                    if prepPos then
                                        report("AutoWalk", "DisplayRack complete • TP to Dough PrepTable...")
                                        if teleportToPosition(prepPos + Vector3.new(0, 2.5, 0))
                                            and running("ZHM_AutoWalk") then
                                            task.wait(TP_DELAY)

                                            -- Next stop: Cashier, then force Rolling Pin swings.
                                            if running("ZHM_AutoWalk") then
                                                local cashierPos = getCashierPos(myPlot)
                                                if cashierPos then
                                                    report("AutoWalk", "PrepTable complete • TP to Cashier...")
                                                    if teleportToPosition(cashierPos + Vector3.new(0, 2.5, 0))
                                                        and running("ZHM_AutoWalk") then

                                                        local swingEnd = os.clock() + 2
                                                        local swingAttempts = 0
                                                        local successfulSwings = 0

                                                        while isCurrent()
                                                            and running("ZHM_AutoWalk")
                                                            and os.clock() < swingEnd do

                                                            local swingNow = ENV.ZHM_SwingRollingPinNow
                                                            if type(swingNow) == "function" then
                                                                swingAttempts += 1
                                                                local ok, swung = pcall(swingNow)
                                                                if ok and swung then
                                                                    successfulSwings += 1
                                                                end
                                                            end

                                                            RunService.Heartbeat:Wait()
                                                        end

                                                        if swingAttempts > 0 then
                                                            report(
                                                                "AutoWalk",
                                                                "Cashier reached • Rolling Pin spammed for 2s ("
                                                                    .. tostring(successfulSwings)
                                                                    .. "/"
                                                                    .. tostring(swingAttempts)
                                                                    .. " successful)."
                                                            )
                                                        else
                                                            report(
                                                                "AutoWalk",
                                                                "Cashier reached • Rolling Pin module was not ready during 2s spam."
                                                            )
                                                        end

                                                        -- Final stop before looping: TP from Cashier to Oven.
                                                        if running("ZHM_AutoWalk") then
                                                            local ovenPos = getOvenPos(myPlot)
                                                            if ovenPos then
                                                                report("AutoWalk", "Cashier complete • TP to Oven • stay 1.5s • restart BakingRack loop...")
                                                                if teleportToPosition(ovenPos + Vector3.new(0, 2.5, 0))
                                                                    and running("ZHM_AutoWalk") then
                                                                    task.wait(1.5)
                                                                end
                                                            else
                                                                report("AutoWalk", "Oven not found; restarting BakingRack loop.")
                                                                task.wait(0.25)
                                                            end
                                                        end
                                                    end
                                                else
                                                    -- Cashier was not detected: skip it and go directly to the Oven.
                                                    local ovenPos = getOvenPos(myPlot)
                                                    if ovenPos then
                                                        report("AutoWalk", "Cashier not found • TP directly to Oven • stay 1.5s • restart BakingRack loop...")
                                                        if teleportToPosition(ovenPos + Vector3.new(0, 2.5, 0))
                                                            and running("ZHM_AutoWalk") then
                                                            task.wait(1.5)
                                                        end
                                                    else
                                                        report("AutoWalk", "Cashier and Oven not found; restarting BakingRack loop.")
                                                        task.wait(0.25)
                                                    end
                                                end
                                            end
                                        end
                                    else
                                        report("AutoWalk", "Dough PrepTable not found; restarting rack route.")
                                        task.wait(0.25)
                                    end
                                end
                            end
                        else
                            task.wait(0.5)
                        end

                        -- Full cycle completed. Re-scan all BakingRacks ONCE and create
                        -- a fresh fixed route for the next cycle.
                        resetRoute()
                    end
                else
                    resetRoute()
                    task.wait(0.5)
                end
            else
                resetRoute()
                task.wait(0.5)
            end

            task.wait(0.05)
        end
    end)
end

startAutoWalk()

--------------------------------------------------------------------------------
-- AUTOMATION HELPERS
--------------------------------------------------------------------------------
local function binding(container)
    if not container then return nil end
    assert(type(getconnections) == "function", "getconnections unavailable")
    local buttons = {}
    if container:IsA("GuiButton") then buttons[#buttons + 1] = container end
    for _, child in ipairs(container:GetDescendants()) do
        if child:IsA("GuiButton") then buttons[#buttons + 1] = child end
    end
    for _, button in ipairs(buttons) do
        for _, event in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Up", "MouseButton1Down" }) do
            local active = {}
            for _, connection in ipairs(getconnections(button[event])) do
                if connection.Enabled ~= false and connection.ForeignState ~= true
                    and connection.LuaConnection ~= false then
                    active[#active + 1] = connection
                end
            end
            if #active > 0 then return { Button = button, Event = event, Connections = active } end
        end
    end
end

local function triggerButton(container, feature)
    if not isCurrent() then return false end
    local target = binding(container)
    if not target then
        report(feature, "Button missing or no supported active handler exposed.")
        return false
    end
    local args = table.pack()
    if target.Event == "Activated" then
        args = table.pack(nil, 1)
    elseif target.Event == "MouseButton1Down" or target.Event == "MouseButton1Up" then
        local center = target.Button.AbsolutePosition + target.Button.AbsoluteSize / 2
        args = table.pack(center.X, center.Y)
    end
    local canFire = true
    for _, connection in ipairs(target.Connections) do
        if type(connection.Fire) ~= "function" then canFire = false end
    end
    if canFire then
        for _, connection in ipairs(target.Connections) do
            if not isCurrent() then return false end
            connection:Fire(table.unpack(args, 1, args.n))
        end
    elseif type(firesignal) == "function" then
        firesignal(target.Button[target.Event], table.unpack(args, 1, args.n))
    else
        error("Neither Connection:Fire nor firesignal is available")
    end
    return true
end

local function firePromptSafe(prompt, feature)
    if not isCurrent() then return false end
    if not prompt or not prompt:IsA("ProximityPrompt") then
        report(feature, "Prompt missing on the configured plot.")
        return false
    end
    if not prompt.Enabled then return false end
    if type(fireproximityprompt) ~= "function" then
        report(feature, "fireproximityprompt unavailable.")
        return false
    end

    pcall(function() prompt.HoldDuration = 0 end)
    pcall(function() prompt.RequiresLineOfSight = false end)
    pcall(function() prompt.ClickablePrompt = true end)
    pcall(function()
        prompt.MaxActivationDistance = math.max(
            tonumber(prompt.MaxActivationDistance) or 0,
            100000
        )
    end)

    -- Executors differ on which fireproximityprompt signature they support.
    local ok = pcall(function() fireproximityprompt(prompt, 0, true) end)
    if not ok then
        ok = pcall(function() fireproximityprompt(prompt, 0) end)
    end
    if not ok then
        ok = pcall(function() fireproximityprompt(prompt) end)
    end
    return ok
end

--------------------------------------------------------------------------------
-- AUTO PRESS NEAREST CLICKABLE PROMPT
-- Supports both ProximityPrompt and ClickDetector and only fires the nearest
-- usable interaction anywhere in Workspace, choosing the closest to the player.
--------------------------------------------------------------------------------
local AUTO_NEAREST_ACTIVATION_DISTANCE = 1000000000 -- practical unlimited range
local AUTO_NEAREST_SCAN_DELAY = 0 -- no artificial scan delay; loop runs every frame
local AUTO_NEAREST_COOLDOWN = 0 -- no refire cooldown

local nearestInteractions = setmetatable({}, { __mode = "k" })
local nearestLastFire = setmetatable({}, { __mode = "k" })

local function registerNearestInteraction(obj)
    if obj and (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")) then
        nearestInteractions[obj] = true
    end
end

for _, obj in ipairs(Workspace:GetDescendants()) do
    registerNearestInteraction(obj)
end

Workspace.DescendantAdded:Connect(registerNearestInteraction)
Workspace.DescendantRemoving:Connect(function(obj)
    nearestInteractions[obj] = nil
    nearestLastFire[obj] = nil
end)

local function getNearestInteractionPart(interaction)
    if not interaction then return nil end

    local current = interaction.Parent
    while current and current ~= Workspace do
        if current:IsA("Attachment") then
            local parent = current.Parent
            if parent and parent:IsA("BasePart") then return parent end
        elseif current:IsA("BasePart") then
            return current
        elseif current:IsA("Model") then
            local part = current.PrimaryPart
                or current:FindFirstChild("HumanoidRootPart")
                or current:FindFirstChildWhichIsA("BasePart", true)
            if part then return part end
        end
        current = current.Parent
    end

    return nil
end

local function nearestInteractionAllowed(interaction, distance)
    if not interaction or not interaction.Parent then return false end
    -- No distance cap: the nearest valid interaction can be anywhere in Workspace.

    if interaction:IsA("ProximityPrompt") then
        return interaction.Enabled == true
    end

    if interaction:IsA("ClickDetector") then
        return true
    end

    return false
end

local function getNearestClickableInteraction()
    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    local closest = nil
    local closestDistance = math.huge

    for interaction in pairs(nearestInteractions) do
        if interaction and interaction.Parent then
            local part = getNearestInteractionPart(interaction)
            if part then
                local distance = (rootPart.Position - part.Position).Magnitude
                if distance < closestDistance
                    and nearestInteractionAllowed(interaction, distance) then
                    closest = interaction
                    closestDistance = distance
                end
            end
        else
            nearestInteractions[interaction] = nil
            nearestLastFire[interaction] = nil
        end
    end

    return closest, closestDistance
end

local function pressNearestClickableInteraction(interaction)
    if not interaction or not interaction.Parent then return false end

    local now = os.clock()
    -- No artificial cooldown: nearest interaction may fire again on the next frame.

    if interaction:IsA("ProximityPrompt") then
        if not interaction.Enabled or type(fireproximityprompt) ~= "function" then
            return false
        end

        pcall(function() interaction.HoldDuration = 0 end)
        pcall(function() interaction.RequiresLineOfSight = false end)
        pcall(function()
            interaction.MaxActivationDistance = math.max(interaction.MaxActivationDistance, AUTO_NEAREST_ACTIVATION_DISTANCE)
        end)

        -- Try the most aggressive instant form first, then executor-compatible fallbacks.
        local ok = pcall(function() fireproximityprompt(interaction, 0, true) end)
        if not ok then
            ok = pcall(function() fireproximityprompt(interaction, 0) end)
        end
        if not ok then
            ok = pcall(function() fireproximityprompt(interaction) end)
        end

        if ok then
            nearestLastFire[interaction] = now
            return true
        end
    elseif interaction:IsA("ClickDetector") then
        if type(fireclickdetector) ~= "function" then return false end

        pcall(function()
            interaction.MaxActivationDistance = math.max(interaction.MaxActivationDistance, AUTO_NEAREST_ACTIVATION_DISTANCE)
        end)

        local ok = pcall(function() fireclickdetector(interaction) end)
        if ok then
            nearestLastFire[interaction] = now
            return true
        end
    end

    return false
end

local function autoNearestPromptEnabled()
    -- IMPORTANT: do not use running() here. running() intentionally pauses jobs
    -- while ZHM_SweepActive is true, but nearest prompt pressing must stay alive
    -- during night sweeping so sweep/nearby prompts can still fire instantly.
    return isCurrent() and ENV.ZHM_AutoNearestPrompt == true
end

local function startAutoNearestPrompt()
    task.spawn(function()
        while isCurrent() do
            if autoNearestPromptEnabled() then
                local interaction = getNearestClickableInteraction()
                if interaction then
                    pressNearestClickableInteraction(interaction)
                end
            end
            RunService.Heartbeat:Wait() -- fastest safe loop: once per rendered/simulation frame
        end
    end)
end

startAutoNearestPrompt()

--------------------------------------------------------------------------------
-- AUTO BUY BAKING RACK: DYNAMIC MY-PLOT DIRECT SPAM (NO TELEPORT)
-- Dynamically resolves the player's owned plot, then repeatedly fires:
--   MyPlot.Equipment.BakingRack["1".."100"].BuyBakingRackPrompt
-- No TP is used. Prompts are made instant + long-range and fired every 0.10s.
--------------------------------------------------------------------------------
local AUTO_BUY_BAKING_RACK_SCAN_DELAY = 0.10

-- Separate resolver for Auto Buy so this feature follows the supplied
-- standalone script without changing the plot logic used by other ZHM features.
local function findAutoBuyBakingRackPlot()
    local shops = Workspace:FindFirstChild("Game")
        and Workspace.Game:FindFirstChild("Shops")

    if not shops then
        return nil
    end

    for _, plot in ipairs(shops:GetChildren()) do
        local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")

        if owner and owner:IsA("ValueBase") then
            if owner.Value == player
                or owner.Value == player.Name
                or owner.Value == player.UserId then
                return plot
            end
        end

        if plot:GetAttribute("OwnerUserId") == player.UserId then
            return plot
        end
    end

    -- Same compatibility fallback as the supplied script.
    return shops:FindFirstChild("Plot1")
end

local function startAutoBuyBakingRack()
    task.spawn(function()
        while isCurrent() do
            if ENV.ZHM_AutoBuyBakingRack == true then
                -- Re-find the plot/folders every loop because purchases can rebuild
                -- rack instances and some servers may assign a different plot.
                local plot = findAutoBuyBakingRackPlot()
                local equipmentFolder = plot and plot:FindFirstChild("Equipment")
                local bakingRackFolder = equipmentFolder and equipmentFolder:FindFirstChild("BakingRack")

                if bakingRackFolder then
                    local found = 0
                    local fired = 0

                    for i = 1, 100 do
                        if not isCurrent() then return end
                        if ENV.ZHM_AutoBuyBakingRack ~= true then break end

                        local rackModel = bakingRackFolder:FindFirstChild(tostring(i))
                        if rackModel then
                            local prompt = rackModel:FindFirstChild("BuyBakingRackPrompt")
                            if prompt and prompt:IsA("ProximityPrompt") then
                                found += 1

                                -- Supplied no-TP direct prompt method.
                                pcall(function()
                                    prompt.HoldDuration = 0
                                    prompt.MaxActivationDistance = 999999
                                end)

                                local ok = pcall(function()
                                    fireproximityprompt(prompt)
                                end)

                                if ok then
                                    fired += 1
                                end
                            end
                        end
                    end

                    if found > 0 then
                        ENV.ZHM_BuyBakingRackStatus =
                            "SPAMMING • " .. tostring(plot and plot.Name or "Unknown Plot")
                            .. " • found " .. tostring(found)
                            .. " • fired " .. tostring(fired)
                    else
                        ENV.ZHM_BuyBakingRackStatus =
                            "SPAMMING • " .. tostring(plot and plot.Name or "Unknown Plot")
                            .. " • BakingRack found • no numbered prompts"
                    end
                elseif plot then
                    ENV.ZHM_BuyBakingRackStatus =
                        "SPAMMING • " .. tostring(plot.Name)
                        .. " • BakingRack folder not found in Equipment"
                else
                    ENV.ZHM_BuyBakingRackStatus =
                        "SPAMMING • owned plot not found"
                end
            else
                ENV.ZHM_BuyBakingRackStatus = "Auto Buy Baking Rack disabled"
            end

            task.wait(AUTO_BUY_BAKING_RACK_SCAN_DELAY)
        end
    end)
end

startAutoBuyBakingRack()

--------------------------------------------------------------------------------
-- DISPLAYRACK: SPAM ALL NEARBY PROXIMITY PROMPTS
-- While the player is standing near the DisplayRack, fire EVERY enabled
-- ProximityPrompt around the rack every Heartbeat with no artificial delay.
--------------------------------------------------------------------------------
local DISPLAY_RACK_PLAYER_RADIUS = 15
local DISPLAY_RACK_PROMPT_RADIUS = 30

local function startDisplayRackPromptSpam()
    task.spawn(function()
        while isCurrent() do
            if ENV.ZHM_SpamDisplayRackPrompts == true and running("ZHM_AutoWalk") then
                local plot = findMyPlot()
                local displayPos = plot and getDisplayRackPos(plot)

                local char = player.Character
                local rootPart = char and char:FindFirstChild("HumanoidRootPart")

                if displayPos and rootPart then
                    local playerDistance = (rootPart.Position - displayPos).Magnitude

                    if playerDistance <= DISPLAY_RACK_PLAYER_RADIUS then
                        for interaction in pairs(nearestInteractions) do
                            if not isCurrent() then return end

                            if interaction
                                and interaction.Parent
                                and interaction:IsA("ProximityPrompt")
                                and interaction.Enabled then

                                local interactionPart = getNearestInteractionPart(interaction)
                                if interactionPart then
                                    local rackDistance = (interactionPart.Position - displayPos).Magnitude

                                    if rackDistance <= DISPLAY_RACK_PROMPT_RADIUS then
                                        -- Reuse the instant/no-hold firing path. There is intentionally
                                        -- no cooldown, so every valid prompt can fire again next Heartbeat.
                                        pressNearestClickableInteraction(interaction)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            RunService.Heartbeat:Wait()
        end
    end)
end

startDisplayRackPromptSpam()

local function sortedChildren(container)
    local children = container:GetChildren()
    table.sort(children, function(a, b) return a.Name < b.Name end)
    return children
end

local customerIndex = 0
local function autoAccept()
    local body = ui({ "MainUI", "Cashier", "Frame", "Body" })
    local accept = resolve(body, { "Actions", "AcceptButton" })
    if not binding(accept) then report("Accept", "Cashier Accept handler unavailable."); return end
    local rows = body:FindFirstChild("OrdersRow")
    local candidates = {}
    if rows then
        for _, row in ipairs(sortedChildren(rows)) do
            if row.Name:match("^Customer%d+$") then candidates[#candidates + 1] = row end
        end
    end
    if #candidates > 0 then
        customerIndex = customerIndex % #candidates + 1
        if not triggerButton(candidates[customerIndex], "Accept") then return end
        task.wait()
        if not farming("ZHM_AutoAccept") then return end
    end
    accept = ui({ "MainUI", "Cashier", "Frame", "Body", "Actions", "AcceptButton" })
    if triggerButton(accept, "Accept") then report("Accept", "Accept handler dispatched.") end
end

local function autoPrepareDough()
    local plot = findMyPlot()
    local prompt = resolve(plot, { "Position", "PrepTable", "PrepTablePrompt" })
        or (plot and plot:FindFirstChild("PrepTablePrompt", true))
    if firePromptSafe(prompt, "Dough") then report("Dough", "Prepare Dough prompt dispatched.") end
end

local bakeAllBreads

do
--------------------------------------------------------------------------------
-- AUTO BAKE V5 - ACTION-LOG LOOP (PROMPT -> SELECT -> BAKE -> REPEAT)
--
-- New game structure observed:
--   StarterPlayerScripts.Client.Controllers.BakeSelectController
--   StarterPlayerScripts.Client.Controllers.BakeProgressController
--   StarterPlayerScripts.Client.Controllers.BakeryController
--
-- New action flow observed:
--   Oven BakePrompt
--     -> numbered BakeSelect rows (100,101,102...) / Buttons.Select
--     -> StackTemplate / Buttons.Bake
--     -> ReplicatedStorage.Network.Packet.RemoteEvent
--
-- IMPORTANT:
-- We intentionally let the game's OWN BakeSelectController invoke the final
-- network packet instead of guessing undocumented FireServer arguments.
-- The menu is kept logically active but moved off-screen, so Auto Bake is silent.
--------------------------------------------------------------------------------

local bakeState = {
    Busy = false,
    LastBatchSignature = "",
    LastBatchTime = 0,
    NextAttempt = 0,
    BatchCounter = 0,
    ControllerStatusReported = false,
}

local silentBakeFrame = nil
local silentBakeOriginalPosition = nil

local function getBakeControllersFolder()
    -- Runtime location after StarterPlayerScripts is cloned to LocalPlayer.PlayerScripts.
    local playerScripts = player:FindFirstChild("PlayerScripts")
    local client = playerScripts and playerScripts:FindFirstChild("Client")
    local controllers = client and client:FindFirstChild("Controllers")
    if controllers then
        return controllers
    end

    -- Studio/source-layout fallback matching the screenshot.
    local starterPlayer = game:GetService("StarterPlayer")
    local starterScripts = starterPlayer and starterPlayer:FindFirstChild("StarterPlayerScripts")
    client = starterScripts and starterScripts:FindFirstChild("Client")
    controllers = client and client:FindFirstChild("Controllers")

    return controllers
end

local function getBakeControllerStatus()
    local folder = getBakeControllersFolder()
    if not folder then
        return false, "Controllers folder not found yet"
    end

    local selectController = folder:FindFirstChild("BakeSelectController")
    local progressController = folder:FindFirstChild("BakeProgressController")
    local bakeryController = folder:FindFirstChild("BakeryController")

    local ready = selectController ~= nil and bakeryController ~= nil

    local pieces = {
        "BakeSelect=" .. (selectController and "YES" or "NO"),
        "BakeProgress=" .. (progressController and "YES" or "NO"),
        "Bakery=" .. (bakeryController and "YES" or "NO"),
    }

    return ready, table.concat(pieces, " | ")
end

local function restoreSilentBakeUI()
    if silentBakeFrame
        and silentBakeFrame.Parent
        and silentBakeOriginalPosition then
        pcall(function()
            silentBakeFrame.Position = silentBakeOriginalPosition
        end)
    end

    silentBakeFrame = nil
    silentBakeOriginalPosition = nil
end

local function setSilentBakeUI(frame, enabled)
    if not frame or not frame:IsA("GuiObject") then
        if not enabled then
            restoreSilentBakeUI()
        end
        return
    end

    if enabled then
        if silentBakeFrame ~= frame then
            restoreSilentBakeUI()
            silentBakeFrame = frame
            silentBakeOriginalPosition = frame.Position
        elseif silentBakeOriginalPosition == nil then
            silentBakeOriginalPosition = frame.Position
        end

        -- Do NOT set Visible=false. The game's BakeSelectController may depend on
        -- the UI remaining logically open. Moving it off-screen keeps handlers alive.
        pcall(function()
            frame.Position = UDim2.new(8, 0, 8, 0)
        end)
    else
        restoreSilentBakeUI()
    end
end

local function getBakeFrame()
    return ui({ "MainUI", "BakeSelect", "Frame" })
end

local function guiHierarchyVisible(guiObject)
    if not guiObject or not guiObject.Parent then
        return false
    end

    local current = guiObject

    while current and current ~= playerGui do
        if current:IsA("GuiObject") and current.Visible == false then
            return false
        end

        if current:IsA("ScreenGui") and current.Enabled == false then
            return false
        end

        current = current.Parent
    end

    return true
end

local function getBakeScrollingFrame()
    local frame = getBakeFrame()
    if not frame then return nil, nil end

    local list = frame:FindFirstChild("ScrollingFrame")
    return frame, list
end

local function findBakePrompt(plot)
    if not plot then return nil end

    -- Exact path from the new action log first.
    local exact = resolve(plot, {
        "Equipment", "Oven", "BrownOven", "PlacementRoot", "BakePrompt"
    })

    if exact and exact:IsA("ProximityPrompt") then
        return exact
    end

    -- Oven-specific recursive fallback.
    local equipment = plot:FindFirstChild("Equipment") or plot
    local best = nil

    for _, obj in ipairs(equipment:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local lowerName = string.lower(obj.Name or "")
            local action = string.lower(tostring(obj.ActionText or ""))

            if lowerName == "bakeprompt"
                or lowerName:find("bake", 1, true)
                or action == "bake"
                or action:find("bake", 1, true) then

                -- Prefer a prompt whose ancestry contains Oven.
                local current = obj.Parent
                local underOven = false

                while current and current ~= plot do
                    if string.lower(current.Name or ""):find("oven", 1, true) then
                        underOven = true
                        break
                    end
                    current = current.Parent
                end

                if underOven then
                    return obj
                end

                best = best or obj
            end
        end
    end

    return best
end

local function fireBakePromptRobust(prompt)
    if not prompt
        or not prompt.Parent
        or not prompt:IsA("ProximityPrompt")
        or not prompt.Enabled then
        return false
    end

    pcall(function() prompt.HoldDuration = 0 end)
    pcall(function() prompt.RequiresLineOfSight = false end)
    pcall(function()
        prompt.MaxActivationDistance = math.max(
            tonumber(prompt.MaxActivationDistance) or 0,
            100000
        )
    end)

    if type(fireproximityprompt) ~= "function" then
        return false
    end

    local ok = pcall(function()
        fireproximityprompt(prompt, 0, true)
    end)

    if not ok then
        ok = pcall(function()
            fireproximityprompt(prompt, 0)
        end)
    end

    if not ok then
        ok = pcall(function()
            fireproximityprompt(prompt)
        end)
    end

    return ok
end

local function triggerBakeGuiButton(button, feature)
    if not button
        or not button.Parent
        or not button:IsA("GuiButton") then
        return false
    end

    -- First use the hub's normal callback-dispatch helper.
    local ok, fired = pcall(function()
        return triggerButton(button, feature)
    end)

    if ok and fired then
        return true
    end

    -- Compatibility fallback for controllers that reconnect handlers after the
    -- first scan or expose only one signal path to the executor.
    if type(firesignal) == "function" then
        local signalWorked = false

        local function trySignal(signal, ...)
            if not signal then return end

            -- Luau does not allow a nested closure to directly capture `...`.
            -- Pack the varargs first, then unpack them inside pcall.
            local signalArgs = table.pack(...)

            local worked = pcall(function()
                firesignal(
                    signal,
                    table.unpack(signalArgs, 1, signalArgs.n)
                )
            end)

            if worked then
                signalWorked = true
            end
        end

        trySignal(button.Activated, nil, 1)
        trySignal(button.MouseButton1Click)
        trySignal(button.MouseButton1Down, 0, 0)
        trySignal(button.MouseButton1Up, 0, 0)

        if signalWorked then
            return true
        end
    end

    -- Last callback fallback using getconnections directly.
    if type(getconnections) == "function" then
        for _, eventName in ipairs({
            "Activated",
            "MouseButton1Click",
            "MouseButton1Down",
            "MouseButton1Up",
        }) do
            local signal = button[eventName]

            if signal then
                local success, connections = pcall(getconnections, signal)

                if success and connections then
                    for _, connection in ipairs(connections) do
                        if type(connection.Fire) == "function" then
                            local worked = pcall(function()
                                if eventName == "Activated" then
                                    connection:Fire(nil, 1)
                                elseif eventName == "MouseButton1Down"
                                    or eventName == "MouseButton1Up" then
                                    connection:Fire(0, 0)
                                else
                                    connection:Fire()
                                end
                            end)

                            if worked then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

local function waitUntil(predicate, timeoutSeconds, step)
    local deadline = os.clock() + (timeoutSeconds or 1)
    step = step or 0.03

    while isCurrent() and os.clock() < deadline do
        local ok, result = pcall(predicate)
        if ok and result then
            return true
        end
        task.wait(step)
    end

    return false
end

local function bakeSelectButtonUsable(button)
    if not button
        or not button.Parent
        or not button:IsA("GuiButton") then
        return false
    end

    -- A hidden Select button is not currently available.
    if button.Visible == false then
        return false
    end

    -- Newer Roblox GuiButtons expose Interactable. Use it when available,
    -- but remain compatible with executors / game versions where it is absent.
    local okInteractable, interactable = pcall(function()
        return button.Interactable
    end)

    if okInteractable and interactable == false then
        return false
    end

    return true
end

local function getSelectableBakeRows(list)
    local rows = {}

    if not list then
        return rows
    end

    -- Read the live list every pass. Do not cache rows because BakeSelectController
    -- can destroy/recreate them after each successful bake.
    for _, row in ipairs(list:GetChildren()) do
        local number = tonumber(row.Name)

        if number then
            local selectButton = resolve(row, {
                "Main_Frame", "Buttons", "Select"
            })

            if bakeSelectButtonUsable(selectButton) then
                rows[#rows + 1] = {
                    Number = number,
                    Name = row.Name,
                    Row = row,
                    Button = selectButton,
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.Number ~= b.Number then
            return a.Number < b.Number
        end

        return tostring(a.Name) < tostring(b.Name)
    end)

    return rows
end

local function makeBakeSignature(rows, count)
    local parts = {}
    count = math.min(count or #rows, #rows)

    for i = 1, count do
        parts[#parts + 1] = tostring(rows[i].Name)
    end

    return table.concat(parts, ",")
end

local function findFinalBakeButton(list)
    if not list then return nil end

    -- Exact new UI path from the action log.
    local exact = resolve(list, {
        "StackTemplate", "Main_Frame", "Buttons", "Bake"
    })

    if exact and exact:IsA("GuiButton") then
        return exact
    end

    -- Compatibility fallback if StackTemplate gets renamed.
    for _, obj in ipairs(list:GetDescendants()) do
        if obj:IsA("GuiButton")
            and string.lower(obj.Name or "") == "bake" then

            local parentName = obj.Parent and string.lower(obj.Parent.Name or "") or ""

            if parentName == "buttons"
                or string.lower(obj:GetFullName()):find("stack", 1, true) then
                return obj
            end
        end
    end

    return nil
end

local function getBakeProgressVisible()
    -- Optional progress GUI detector. We do not depend on a fixed exact hierarchy;
    -- this only gives the state machine an extra success signal.
    local mainUI = playerGui:FindFirstChild("MainUI")
    if not mainUI then return false end

    for _, obj in ipairs(mainUI:GetDescendants()) do
        if obj:IsA("GuiObject") then
            local lower = string.lower(obj.Name or "")

            if (lower:find("bakeprogress", 1, true)
                or lower:find("bakingprogress", 1, true))
                and obj.Visible then
                return true
            end
        end
    end

    return false
end

local function openBakeMenu(plot)
    local frame, list = getBakeScrollingFrame()

    if frame and list and guiHierarchyVisible(frame) then
        if ENV.ZHM_SilentBakeUI == true then
            setSilentBakeUI(frame, true)
        end
        return frame, list
    end

    local prompt = findBakePrompt(plot)
    if not prompt then
        report("Bake", "BakePrompt not found on your current plot.")
        return nil, nil
    end

    if not fireBakePromptRobust(prompt) then
        report("Bake", "BakePrompt could not be fired.")
        return nil, nil
    end

    -- Wait for BakeSelectController to create/open the new menu.
    local opened = waitUntil(function()
        local currentFrame, currentList = getBakeScrollingFrame()
        return currentFrame
            and currentList
            and guiHierarchyVisible(currentFrame)
    end, 1.25, 0.025)

    if not opened then
        report("Bake", "BakeSelectController did not open the menu yet.")
        return nil, nil
    end

    frame, list = getBakeScrollingFrame()

    if frame and ENV.ZHM_SilentBakeUI == true then
        setSilentBakeUI(frame, true)
    end

    -- Wait briefly for numbered stack rows to populate.
    waitUntil(function()
        return #getSelectableBakeRows(list) > 0
    end, 0.75, 0.025)

    return frame, list
end

local function reopenBakeMenuFromPrompt(plot)
    -- Match the captured action logs exactly:
    -- BakePrompt -> Select row(s) -> Bake -> then BakePrompt again.
    local frame = getBakeFrame()

    -- Restore/move any previous logical BakeSelect frame before reopening.
    if frame and ENV.ZHM_SilentBakeUI == true then
        setSilentBakeUI(frame, true)
    end

    local prompt = findBakePrompt(plot)
    if not prompt then
        report("Bake", "BakePrompt not found on your current plot.")
        return nil, nil
    end

    if not fireBakePromptRobust(prompt) then
        report("Bake", "BakePrompt could not be fired.")
        return nil, nil
    end

    local opened = waitUntil(function()
        local currentFrame, currentList = getBakeScrollingFrame()
        return currentFrame
            and currentList
            and guiHierarchyVisible(currentFrame)
    end, 1.25, 0.025)

    if not opened then
        report("Bake", "BakeSelect menu did not open after BakePrompt.")
        return nil, nil
    end

    local currentFrame, currentList = getBakeScrollingFrame()

    if currentFrame and ENV.ZHM_SilentBakeUI == true then
        setSilentBakeUI(currentFrame, true)
    end

    -- Wait for at least one selectable numbered row.
    waitUntil(function()
        return #getSelectableBakeRows(currentList) > 0
    end, 0.75, 0.025)

    return currentFrame, currentList
end

local function runAutoBakeCycle()
    if not farming("ZHM_AutoBake") then
        return
    end

    local plot = findMyPlot()
    if not plot then
        report("Bake", "Waiting for your plot.")
        bakeState.NextAttempt = os.clock() + 0.25
        return
    end

    if not bakeState.ControllerStatusReported then
        local _, status = getBakeControllerStatus()
        report("Bake", "Controller scan: " .. status)
        bakeState.ControllerStatusReported = true
    end

    local completedInWorker = 0

    while farming("ZHM_AutoBake") and isCurrent() do
        -- ACTION LOG STEP 1:
        -- Fire Oven BakePrompt every single cycle.
        local frame, list = reopenBakeMenuFromPrompt(plot)

        if not frame or not list or not farming("ZHM_AutoBake") then
            bakeState.NextAttempt = os.clock() + 0.20
            return
        end

        -- ACTION LOG STEP 2:
        -- Read the current numbered rows and select the first 3 that exist.
        -- No persistent "already selected" memory is used. If the game shows the
        -- same row IDs again in a later cycle, they may be selected again.
        local rows = getSelectableBakeRows(list)

        if #rows == 0 then
            report("Bake", "BakePrompt opened, but no selectable bread rows are available.")
            bakeState.NextAttempt = os.clock() + 0.20
            return
        end

        local batchCount = math.min(3, #rows)
        local signature = makeBakeSignature(rows, batchCount)
        local selected = 0

        for i = 1, batchCount do
            if not farming("ZHM_AutoBake") then
                return
            end

            local entry = rows[i]

            if entry
                and entry.Button
                and entry.Button.Parent
                and bakeSelectButtonUsable(entry.Button) then

                if triggerBakeGuiButton(entry.Button, "BakeSelect") then
                    selected += 1

                    -- Logs show sequential Select presses before Bake.
                    task.wait(0.05)
                end
            end
        end

        if selected <= 0 then
            report("Bake", "Select callbacks did not fire for current bread rows.")
            bakeState.NextAttempt = os.clock() + 0.25
            return
        end

        -- ACTION LOG STEP 3:
        -- Press StackTemplate.Main_Frame.Buttons.Bake.
        local finalBake = findFinalBakeButton(list)

        if not finalBake then
            report("Bake", "Bake button not found after selecting bread.")
            bakeState.NextAttempt = os.clock() + 0.25
            return
        end

        if not triggerBakeGuiButton(finalBake, "Bake") then
            report("Bake", "Final Bake callback could not be dispatched.")
            bakeState.NextAttempt = os.clock() + 0.25
            return
        end

        bakeState.BatchCounter += 1
        bakeState.LastBatchSignature = signature
        bakeState.LastBatchTime = os.clock()
        completedInWorker += 1

        report(
            "Bake",
            "Action-log batch #" .. tostring(bakeState.BatchCounter)
                .. " • selected " .. tostring(selected)
                .. " row(s) [" .. signature .. "] • Bake pressed."
        )

        -- ACTION LOG STEP 4:
        -- Wait for the current BakeSelect interaction to be consumed/refresh.
        -- Then the loop starts again from BakePrompt.
        waitUntil(function()
            local currentFrame, currentList = getBakeScrollingFrame()

            if not currentFrame or not currentList then
                return true
            end

            if not guiHierarchyVisible(currentFrame) then
                return true
            end

            local currentRows = getSelectableBakeRows(currentList)
            local currentSignature = makeBakeSignature(
                currentRows,
                math.min(3, #currentRows)
            )

            return #currentRows == 0 or currentSignature ~= signature
        end, 1.35, 0.04)

        -- Small controller settle delay, then immediately repeat from BakePrompt.
        task.wait(0.12)

        -- Yield occasionally so the other automation modules stay responsive.
        if completedInWorker >= 12 then
            bakeState.NextAttempt = os.clock() + 0.05
            return
        end
    end
end

-- Keep BakeSelect permanently off-screen while Auto Bake is enabled.
task.spawn(function()
    while isCurrent() do
        local frame = getBakeFrame()

        if ENV.ZHM_SilentBakeUI == true
            and farming("ZHM_AutoBake")
            and frame then
            setSilentBakeUI(frame, true)
        elseif silentBakeFrame then
            restoreSilentBakeUI()
        end

        task.wait(0.03)
    end

    restoreSilentBakeUI()
end)

bakeAllBreads = function()
    if not farming("ZHM_AutoBake") then
        if silentBakeFrame then
            restoreSilentBakeUI()
        end
        return
    end

    if bakeState.Busy then
        return
    end

    if os.clock() < (bakeState.NextAttempt or 0) then
        return
    end

    bakeState.Busy = true

    -- Run the continuous bake worker separately so waiting for the controller/UI/server
    -- does not freeze Accept, Collect, Give Order, Pay Cashier, etc.
    task.spawn(function()
        local ok, err = xpcall(runAutoBakeCycle, function(message)
            return tostring(message)
        end)

        if not ok then
            report("Bake", "Auto Bake error: " .. tostring(err))
            bakeState.NextAttempt = os.clock() + 0.35
        end

        -- Always release Busy so the scheduler can start the next live scan.
        bakeState.Busy = false
    end)
end

end -- AUTO BAKE V3 isolated scope

local enabledBreadButtons = setmetatable({}, { __mode = "k" })
local function autoEnableBreads()
    local list = ui({ "MainUI", "Breads", "Frame", "ScrollingFrame" })
    if not list then report("Breads", "Bread Enable controls unavailable."); return end
    for _, row in ipairs(sortedChildren(list)) do
        if not farming("ZHM_AutoEnableBreads") then return end
        local button = resolve(row, { "Main_Frame", "Buttons", "Enable" })
        if button and not enabledBreadButtons[button] and (not button:IsA("GuiObject") or button.Visible) then
            if triggerButton(button, "Breads") then enabledBreadButtons[button] = true end
            task.wait()
        end
    end
end

-- AUTO GIVE ORDER: separate delivery logic from Auto Collect.
-- This catches prompts whose ActionText changes dynamically to "Give Order",
-- plus common delivery prompt names such as RackDeliverPrompt / DeliverPrompt.
local function isGiveOrderPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return false
    end

    local name = string.lower(prompt.Name or "")
    local action = string.lower(tostring(prompt.ActionText or ""))
    local objectText = string.lower(tostring(prompt.ObjectText or ""))
    local compactAction = action:gsub("[%s_%-]+", "")
    local compactName = name:gsub("[%s_%-]+", "")

    local orderAction = action:find("give order", 1, true) ~= nil
        or action:find("deliver", 1, true) ~= nil
        or action:find("serve", 1, true) ~= nil
        or action:find("hand order", 1, true) ~= nil
        or compactAction:find("giveorder", 1, true) ~= nil
        or compactAction:find("deliverorder", 1, true) ~= nil

    local orderName = compactName == "rackdeliverprompt"
        or compactName == "deliverprompt"
        or compactName == "giveorderprompt"
        or compactName:find("giveorder", 1, true) ~= nil
        or compactName:find("deliver", 1, true) ~= nil

    local orderText = objectText:find("give order", 1, true) ~= nil
        or objectText:find("customer order", 1, true) ~= nil
        or objectText:find("order", 1, true) ~= nil and (orderAction or orderName)

    return orderAction or orderName or orderText
end

local function fireGiveOrderPrompt(prompt)
    if not farming("ZHM_AutoGiveOrder") then return false end
    if not prompt or not prompt.Parent or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end
    if not isGiveOrderPrompt(prompt) then return false end
    if type(fireproximityprompt) ~= "function" then
        report("GiveOrder", "fireproximityprompt unavailable.")
        return false
    end

    -- Delivery prompts are frequently recreated mid-game, so configure the live
    -- instance every time and use the same robust firing path as other prompts.
    pcall(function() prompt.HoldDuration = 0 end)
    pcall(function() prompt.RequiresLineOfSight = false end)
    pcall(function() prompt.ClickablePrompt = true end)
    pcall(function()
        prompt.MaxActivationDistance = math.max(
            tonumber(prompt.MaxActivationDistance) or 0,
            100000
        )
    end)

    return firePromptSafe(prompt, "GiveOrder")
end

local giveOrderCache = {}
local giveOrderCachePlot = nil
local giveOrderNextScan = 0

local function getGiveOrderPrompts(plot)
    local now = os.clock()
    local needScan = plot ~= giveOrderCachePlot or now >= giveOrderNextScan

    if not needScan then
        for _, prompt in ipairs(giveOrderCache) do
            if not prompt or not prompt.Parent then
                needScan = true
                break
            end
        end
    end

    if needScan then
        giveOrderCachePlot = plot
        -- Re-scan quickly because the game can replace / retask delivery prompts mid-game.
        giveOrderNextScan = now + 0.05
        giveOrderCache = {}

        if plot then
            for _, obj in ipairs(plot:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and isGiveOrderPrompt(obj) then
                    giveOrderCache[#giveOrderCache + 1] = obj
                end
            end
        end
    end

    return giveOrderCache
end

local function autoGiveOrder()
    if not farming("ZHM_AutoGiveOrder") then return end

    local plot = findMyPlot()
    if not plot then
        report("GiveOrder", "Waiting for your plot.")
        return
    end

    local prompts = getGiveOrderPrompts(plot)
    local fired = 0

    for _, prompt in ipairs(prompts) do
        if not farming("ZHM_AutoGiveOrder") then return end
        if prompt and prompt.Parent and prompt.Enabled and isGiveOrderPrompt(prompt) then
            if fireGiveOrderPrompt(prompt) then
                fired += 1
            end
            task.wait(0.02)
        end
    end

    if fired > 0 then
        report("GiveOrder", "Give Order dispatched on " .. tostring(fired) .. " prompt(s).")
    end
end

-- AUTO COLLECT TIP: dedicated Tip Jar collection logic.
-- This is separate from BakingRack Auto Collect because Tip Jar prompts/clicks
-- are a different interaction and may only become enabled when tips are ready.
local function normalizedCompactText(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-]+", "")
end

local function objectLooksLikeTipJar(obj, stopAt)
    local current = obj
    while current and current ~= stopAt do
        local compact = normalizedCompactText(current.Name)
        if compact == "tip"
            or compact == "tips"
            or compact:find("tipjar", 1, true)
            or compact:find("tipbox", 1, true)
            or compact:find("tipmoney", 1, true) then
            return true
        end
        current = current.Parent
    end
    return false
end

local function isTipPrompt(prompt, plot)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end

    local name = normalizedCompactText(prompt.Name)
    local action = normalizedCompactText(prompt.ActionText)
    local objectText = normalizedCompactText(prompt.ObjectText)
    local ancestryLooksLikeTip = objectLooksLikeTipJar(prompt.Parent, plot and plot.Parent)

    local mentionsTip = name:find("tip", 1, true) ~= nil
        or action:find("tip", 1, true) ~= nil
        or objectText:find("tip", 1, true) ~= nil
        or ancestryLooksLikeTip

    if not mentionsTip then return false end

    -- If it lives under a TipJar object, allow the prompt even when the game uses a
    -- generic ActionText such as "Collect". Otherwise require tip/collect semantics.
    return ancestryLooksLikeTip
        or action:find("collect", 1, true) ~= nil
        or action:find("claim", 1, true) ~= nil
        or action:find("take", 1, true) ~= nil
        or action:find("empty", 1, true) ~= nil
        or action:find("tip", 1, true) ~= nil
        or name:find("tip", 1, true) ~= nil
end

local function isTipClickDetector(detector, plot)
    if not detector or not detector:IsA("ClickDetector") then return false end
    return objectLooksLikeTipJar(detector.Parent, plot and plot.Parent)
end

local tipInteractionCache = {}
local tipInteractionCachePlot = nil
local tipInteractionNextScan = 0

local function getTipInteractions(plot)
    local now = os.clock()
    local needScan = plot ~= tipInteractionCachePlot or now >= tipInteractionNextScan

    if not needScan then
        for _, item in ipairs(tipInteractionCache) do
            if not item or not item.Parent then
                needScan = true
                break
            end
        end
    end

    if needScan then
        tipInteractionCachePlot = plot
        tipInteractionNextScan = now + 0.15
        tipInteractionCache = {}

        if plot then
            for _, obj in ipairs(plot:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and isTipPrompt(obj, plot) then
                    tipInteractionCache[#tipInteractionCache + 1] = obj
                elseif obj:IsA("ClickDetector") and isTipClickDetector(obj, plot) then
                    tipInteractionCache[#tipInteractionCache + 1] = obj
                end
            end
        end
    end

    return tipInteractionCache
end

local function fireTipInteraction(item, plot)
    if not farming("ZHM_AutoCollectTip") then return false end
    if not item or not item.Parent then return false end

    if item:IsA("ProximityPrompt") then
        if not item.Enabled or not isTipPrompt(item, plot) then return false end

        pcall(function() item.HoldDuration = 0 end)
        pcall(function() item.RequiresLineOfSight = false end)
        pcall(function() item.MaxActivationDistance = math.max(item.MaxActivationDistance, 35) end)

        if type(fireproximityprompt) ~= "function" then
            report("Tip", "fireproximityprompt unavailable.")
            return false
        end

        local ok = pcall(function() fireproximityprompt(item, 0) end)
        if not ok then
            ok = pcall(function() fireproximityprompt(item) end)
        end
        return ok
    end

    if item:IsA("ClickDetector") then
        if not isTipClickDetector(item, plot) then return false end
        if type(fireclickdetector) ~= "function" then
            report("Tip", "fireclickdetector unavailable for this Tip Jar.")
            return false
        end
        return pcall(function() fireclickdetector(item) end)
    end

    return false
end

local function autoCollectTip()
    if not farming("ZHM_AutoCollectTip") then return end

    local plot = findMyPlot()
    if not plot then
        report("Tip", "Waiting for your plot.")
        return
    end

    local interactions = getTipInteractions(plot)
    local fired = 0

    for _, item in ipairs(interactions) do
        if not farming("ZHM_AutoCollectTip") then return end
        if fireTipInteraction(item, plot) then
            fired += 1
        end
        task.wait(0.02)
    end

    if fired > 0 then
        report("Tip", "Collected Tip Jar interaction(s): " .. tostring(fired))
    end
end

-- AUTO COLLECT: process every DIFFERENT BakingRack on the player's plot.
-- Prompts are grouped by their nearest BakingRack ancestor so duplicate descendants
-- from the same rack do not cause that rack to be counted more than once.
local function isRackCollectPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end

    local name = string.lower(prompt.Name or "")
    local action = string.lower(tostring(prompt.ActionText or ""))
    local objectText = string.lower(tostring(prompt.ObjectText or ""))
    local compactName = name:gsub("[%s_%-]+", "")
    local compactAction = action:gsub("[%s_%-]+", "")

    if name == "bakeprompt" or name == "cashierprompt" or isGiveOrderPrompt(prompt) then
        return false
    end

    return compactName == "pickupllaneraprompt"
        or compactName == "displayrackprompt"
        or compactName:find("collect", 1, true) ~= nil
        or compactName:find("pickup", 1, true) ~= nil
        or compactName:find("take", 1, true) ~= nil
        or compactAction == "collect"
        or compactAction:find("collect", 1, true) ~= nil
        or compactAction:find("pickup", 1, true) ~= nil
        or compactAction:find("take", 1, true) ~= nil
        or action:find("grab", 1, true) ~= nil
        or (objectText:find("bread", 1, true) ~= nil and action ~= "bake")
        or (objectText:find("tray", 1, true) ~= nil and (action:find("take", 1, true) or action:find("collect", 1, true)))
end

local function isBakingRackObject(obj)
    if not obj then return false end
    local name = string.lower(obj.Name or "")
    return (name:find("bakingrack", 1, true) ~= nil
        or name:find("normalbakingrack", 1, true) ~= nil)
        and not name:find("prompt", 1, true)
end

local function nearestBakingRackAncestor(obj, stopAt)
    local current = obj and obj.Parent
    while current and current ~= stopAt do
        if isBakingRackObject(current) then
            return current
        end
        current = current.Parent
    end
    return nil
end

--------------------------------------------------------------------------------
-- BAKINGRACK LIVE SCANNER + TARGETED CLICKABLE PROMPT EXPANDER
-- Scans only the player's own BakingRacks. It does NOT expand unrelated prompts.
-- Kept inside one spawned function to avoid adding long-lived locals to the main hub.
--------------------------------------------------------------------------------
task.spawn(function()
    local PROMPT_DISTANCE = 1000
    local ASSOCIATION_RADIUS = 12
    local SCAN_INTERVAL = 0.20

    local function getRackForInteraction(interaction, plot, rackInfos)
        if not interaction or not interaction.Parent or not plot then return nil end

        -- Best case: the prompt/click detector is parented under a BakingRack.
        local rack = nearestBakingRackAncestor(interaction, plot.Parent)
        if rack then return rack end

        -- Compatibility fallback: some builds put the interaction beside the rack.
        local interactionPart = getNearestInteractionPart(interaction)
        if not interactionPart then return nil end

        local closestRack = nil
        local closestDistance = ASSOCIATION_RADIUS

        for _, rackInfo in ipairs(rackInfos or {}) do
            local rackPart = rackInfo.part
            if rackPart and rackPart.Parent then
                local distance = (interactionPart.Position - rackPart.Position).Magnitude
                if distance <= closestDistance then
                    closestDistance = distance
                    closestRack = rackInfo.instance
                end
            end
        end

        return closestRack
    end

    local function expandInteraction(interaction)
        if ENV.ZHM_ExpandBakingRackPrompts ~= true then return false end
        if not interaction or not interaction.Parent then return false end

        if interaction:IsA("ProximityPrompt") then
            pcall(function() interaction.HoldDuration = 0 end)
            pcall(function() interaction.RequiresLineOfSight = false end)
            pcall(function() interaction.ClickablePrompt = true end)
            pcall(function()
                interaction.MaxActivationDistance = math.max(
                    tonumber(interaction.MaxActivationDistance) or 0,
                    PROMPT_DISTANCE
                )
            end)
            return true
        end

        if interaction:IsA("ClickDetector") then
            pcall(function()
                interaction.MaxActivationDistance = math.max(
                    tonumber(interaction.MaxActivationDistance) or 0,
                    PROMPT_DISTANCE
                )
            end)
            return true
        end

        return false
    end

    local function scanOnce()
        if ENV.ZHM_BakingRackScanner ~= true then
            ENV.ZHM_BakingRackStatus = "BakingRack scanner disabled"
            return
        end

        local plot = findMyPlot()
        if not plot then
            ENV.ZHM_BakingRackStatus = "Waiting for your bakery plot..."
            return
        end

        local rackInfos = getAllBakingRacks(plot)
        local rackSet = {}
        for _, info in ipairs(rackInfos) do
            if info.instance then rackSet[info.instance] = true end
        end

        local proximityCount = 0
        local clickCount = 0
        local enabledPromptCount = 0
        local expandedCount = 0
        local seenInteractions = setmetatable({}, { __mode = "k" })

        -- Scan the plot for interactions that belong to / sit directly beside a BakingRack.
        for _, obj in ipairs(plot:GetDescendants()) do
            if obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") then
                local rack = getRackForInteraction(obj, plot, rackInfos)
                if rack and rackSet[rack] and not seenInteractions[obj] then
                    seenInteractions[obj] = true

                    if obj:IsA("ProximityPrompt") then
                        proximityCount += 1
                        if obj.Enabled then enabledPromptCount += 1 end
                    else
                        clickCount += 1
                    end

                    if expandInteraction(obj) then expandedCount += 1 end
                end
            end
        end

        -- Extra pass through each rack for streamed descendants added between scans.
        for _, info in ipairs(rackInfos) do
            local rack = info.instance
            if rack and rack.Parent then
                for _, obj in ipairs(rack:GetDescendants()) do
                    if (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector"))
                        and not seenInteractions[obj] then
                        seenInteractions[obj] = true

                        if obj:IsA("ProximityPrompt") then
                            proximityCount += 1
                            if obj.Enabled then enabledPromptCount += 1 end
                        else
                            clickCount += 1
                        end

                        if expandInteraction(obj) then expandedCount += 1 end
                    end
                end
            end
        end

        local nearestDistanceText = "N/A"
        local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if rootPart and #rackInfos > 0 then
            local nearestDistance = math.huge
            for _, info in ipairs(rackInfos) do
                if info.part and info.part.Parent then
                    nearestDistance = math.min(nearestDistance, (rootPart.Position - info.part.Position).Magnitude)
                end
            end
            if nearestDistance < math.huge then
                nearestDistanceText = string.format("%.1f studs", nearestDistance)
            end
        end

        local rangeText = ENV.ZHM_ExpandBakingRackPrompts == true
            and (tostring(PROMPT_DISTANCE) .. " studs")
            or "Normal"

        ENV.ZHM_BakingRackStatus =
            "Racks: " .. tostring(#rackInfos)
            .. " | Prompts: " .. tostring(proximityCount)
            .. " | Clicks: " .. tostring(clickCount)
            .. "\nEnabled prompts: " .. tostring(enabledPromptCount)
            .. " | Expanded: " .. tostring(expandedCount)
            .. "\nNearest rack: " .. nearestDistanceText
            .. " | Range: " .. rangeText
    end

    while isCurrent() do
        local ok, err = pcall(scanOnce)
        if not ok then
            ENV.ZHM_BakingRackStatus = "Scanner error: " .. tostring(err)
        end
        task.wait(SCAN_INTERVAL)
    end
end)

local function collectEquipmentPrompts()
    local plot = findMyPlot()
    if not plot then
        report("Collect", "Plot unavailable; check ZHM_PlotName.")
        return
    end

    local equipment = plot:FindFirstChild("Equipment") or plot
    local rackGroups = {}
    local rackOrder = {}
    local seenPrompts = {}
    local otherPrompts = {}

    -- Keep the original reliable grouping behavior: collect ALL valid prompts from
    -- each BakingRack. A rack can expose more than one pickup prompt at the same time.
    for _, obj in ipairs(plot:GetDescendants()) do
        if not farming("ZHM_AutoCollect") then return end

        if obj:IsA("ProximityPrompt") and isRackCollectPrompt(obj) then
            local rack = nearestBakingRackAncestor(obj, plot.Parent)

            if rack then
                if not rackGroups[rack] then
                    rackGroups[rack] = {}
                    rackOrder[#rackOrder + 1] = rack
                end

                if not seenPrompts[obj] then
                    seenPrompts[obj] = true
                    rackGroups[rack][#rackGroups[rack] + 1] = obj
                end
            elseif not seenPrompts[obj] then
                -- Preserve DisplayRack / other supported equipment collection.
                seenPrompts[obj] = true
                otherPrompts[#otherPrompts + 1] = obj
            end
        end
    end

    -- Compatibility pass for prompts that are descendants of a BakingRack but were
    -- missed during the main Equipment scan because of streaming/reparenting timing.
    for _, rackInfo in ipairs(getAllBakingRacks(plot)) do
        if not farming("ZHM_AutoCollect") then return end

        local rack = rackInfo.instance
        if rack and rack.Parent then
            local prompts = rackGroups[rack]
            if not prompts then
                prompts = {}
            end

            for _, obj in ipairs(rack:GetDescendants()) do
                if obj:IsA("ProximityPrompt")
                    and isRackCollectPrompt(obj)
                    and not seenPrompts[obj] then
                    seenPrompts[obj] = true
                    prompts[#prompts + 1] = obj
                end
            end

            if #prompts > 0 and not rackGroups[rack] then
                rackGroups[rack] = prompts
                rackOrder[#rackOrder + 1] = rack
            end
        end
    end

    -- Stable rack order avoids one rack randomly getting priority every scan.
    table.sort(rackOrder, function(a, b)
        local okA, fullA = pcall(function() return a:GetFullName() end)
        local okB, fullB = pcall(function() return b:GetFullName() end)
        return (okA and fullA or a.Name) < (okB and fullB or b.Name)
    end)

    local racksProcessed = 0
    local promptsFired = 0

    -- IMPORTANT: fire EVERY valid prompt on the rack. Do not choose only one.
    -- Prompts are fired as a burst, then yield only once after that rack. This is much
    -- faster than yielding after every bread while still giving the server a frame to update.
    for _, rack in ipairs(rackOrder) do
        if not farming("ZHM_AutoCollect") then return end

        local prompts = rackGroups[rack]
        local firedThisRack = false

        if prompts then
            for _, prompt in ipairs(prompts) do
                if not farming("ZHM_AutoCollect") then return end

                if prompt and prompt.Parent and prompt.Enabled and isRackCollectPrompt(prompt) then
                    -- Keep the same firing method that already worked in the original script.
                    -- Only make the prompt instant/easier to reach before firing it.
                    pcall(function() prompt.HoldDuration = 0 end)
                    pcall(function() prompt.RequiresLineOfSight = false end)
                    pcall(function()
                        prompt.MaxActivationDistance = math.max(tonumber(prompt.MaxActivationDistance) or 0, 100000)
                    end)

                    if firePromptSafe(prompt, "Collect") then
                        promptsFired += 1
                        firedThisRack = true
                    end
                end
            end
        end

        if firedThisRack then
            racksProcessed += 1
            RunService.Heartbeat:Wait()
        end
    end

    -- Preserve collection from DisplayRack / other supported equipment prompts.
    local extraPromptsFired = 0
    for _, prompt in ipairs(otherPrompts) do
        if not farming("ZHM_AutoCollect") then return end

        if prompt and prompt.Parent and prompt.Enabled and isRackCollectPrompt(prompt) then
            pcall(function() prompt.HoldDuration = 0 end)
            pcall(function() prompt.RequiresLineOfSight = false end)
            pcall(function()
                prompt.MaxActivationDistance = math.max(tonumber(prompt.MaxActivationDistance) or 0, 100000)
            end)

            if firePromptSafe(prompt, "Collect") then
                extraPromptsFired += 1
            end
        end
    end

    if extraPromptsFired > 0 then
        RunService.Heartbeat:Wait()
    end

    if racksProcessed > 0 or extraPromptsFired > 0 then
        report(
            "Collect",
            "Collected from "
                .. tostring(racksProcessed)
                .. " BakingRack(s), "
                .. tostring(promptsFired)
                .. " rack prompt(s), "
                .. tostring(extraPromptsFired)
                .. " other prompt(s)."
        )
    end
end

-- AUTO BUY ALL MARKET V2
-- Robust Market GUI discovery + category cycling + scrolling + world Buy fallback.
local MARKET_OPEN_WAIT = 0.12
local MARKET_CATEGORY_WAIT = 0.10
local MARKET_SCROLL_WAIT = 0.035
local MARKET_BUY_WAIT = 0.01
local MARKET_PASS_WAIT = 0.15
local MARKET_MAX_REBUILDS = 24
local WORLD_BUY_RADIUS = 160
local WORLD_BUY_COOLDOWN = 0.30

local worldBuyLastFire = setmetatable({}, { __mode = "k" })

local function compactMarketText(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%./%(%)%[%]:]+", "")
end

local function buttonTextBlob(obj, depth)
    if not obj then return "" end
    depth = depth or 3

    local values = { obj.Name or "" }

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        values[#values + 1] = obj.Text or ""
    elseif obj:IsA("StringValue") then
        values[#values + 1] = tostring(obj.Value or "")
    end

    local queue = { { object = obj, level = 0 } }
    local head = 1

    while head <= #queue do
        local entry = queue[head]
        head += 1

        if entry.level < depth then
            for _, child in ipairs(entry.object:GetChildren()) do
                values[#values + 1] = child.Name or ""

                if child:IsA("TextLabel")
                    or child:IsA("TextButton")
                    or child:IsA("TextBox") then
                    values[#values + 1] = child.Text or ""
                elseif child:IsA("StringValue") then
                    values[#values + 1] = tostring(child.Value or "")
                end

                queue[#queue + 1] = {
                    object = child,
                    level = entry.level + 1,
                }
            end
        end
    end

    return string.lower(table.concat(values, " "))
end

local function getMarketRoot()
    local mainUI = playerGui:FindFirstChild("MainUI")

    -- Known path first.
    if mainUI then
        local market = mainUI:FindFirstChild("Market")
            or mainUI:FindFirstChild("Market", true)
        if market then return market end
    end

    -- Compatibility fallback for renamed Market / Shop / Store containers.
    for _, obj in ipairs(playerGui:GetDescendants()) do
        local name = compactMarketText(obj.Name)
        if (name == "market"
            or name == "shop"
            or name == "store"
            or name:find("marketui", 1, true)
            or name:find("shopui", 1, true))
            and (obj:IsA("GuiObject") or obj:IsA("ScreenGui")) then
            return obj
        end
    end

    return nil
end

local function guiIsActuallyVisible(obj)
    if not obj then return false end

    local current = obj
    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        elseif current:IsA("ScreenGui") and not current.Enabled then
            return false
        end
        current = current.Parent
    end

    return true
end

local function getMarketFrame()
    local market = getMarketRoot()
    if not market then return nil end

    if market:IsA("GuiObject") and market.Name == "Frame" then
        return market
    end

    return market:FindFirstChild("Frame")
        or market:FindFirstChild("Frame", true)
        or market
end

local function getClickable(container)
    if not container then return nil end
    if container:IsA("GuiButton") then return container end
    return container:FindFirstChildWhichIsA("GuiButton", true)
end

local function fireGuiControl(container)
    local button = getClickable(container)
    if not button then return false end

    -- Direct callback path. Works even if the Market panel itself is hidden.
    if type(getconnections) == "function" then
        for _, eventName in ipairs({
            "Activated",
            "MouseButton1Click",
            "MouseButton1Up",
            "MouseButton1Down",
        }) do
            local signal = button[eventName]
            if signal then
                local ok, connections = pcall(getconnections, signal)
                if ok and connections then
                    local fired = false

                    for _, connection in ipairs(connections) do
                        if connection.Enabled ~= false
                            and connection.ForeignState ~= true
                            and connection.LuaConnection ~= false
                            and type(connection.Fire) == "function" then

                            local success = pcall(function()
                                if eventName == "Activated" then
                                    connection:Fire(nil, 1)
                                elseif eventName == "MouseButton1Down"
                                    or eventName == "MouseButton1Up" then
                                    local center =
                                        button.AbsolutePosition + button.AbsoluteSize / 2
                                    connection:Fire(center.X, center.Y)
                                else
                                    connection:Fire()
                                end
                            end)

                            fired = fired or success
                        end
                    end

                    if fired then return true end
                end
            end
        end
    end

    if type(firesignal) == "function" then
        for _, eventName in ipairs({ "Activated", "MouseButton1Click" }) do
            local signal = button[eventName]
            if signal then
                local ok = pcall(function()
                    if eventName == "Activated" then
                        firesignal(signal, nil, 1)
                    else
                        firesignal(signal)
                    end
                end)
                if ok then return true end
            end
        end
    end

    -- Executor-independent fallback: actual mouse click if visible on screen.
    if guiIsActuallyVisible(button)
        and button.AbsoluteSize.X > 1
        and button.AbsoluteSize.Y > 1 then

        local center = button.AbsolutePosition + button.AbsoluteSize / 2
        local x = math.floor(center.X)
        local y = math.floor(center.Y)

        local ok = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            RunService.Heartbeat:Wait()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)

        if ok then return true end
    end

    return false
end

local function looksLikeMarketLauncher(button, marketRoot)
    if not button or not button:IsA("GuiButton") then return false end
    if marketRoot and button:IsDescendantOf(marketRoot) then return false end

    local compact = compactMarketText(buttonTextBlob(button, 2))
    return compact == "market"
        or compact == "shop"
        or compact == "store"
        or compact:find("openmarket", 1, true) ~= nil
        or compact:find("marketbutton", 1, true) ~= nil
        or compact:find("shopbutton", 1, true) ~= nil
end

local function tryOpenMarket()
    local market = getMarketRoot()

    if market and guiIsActuallyVisible(market) then
        return market
    end

    -- Try the game's actual Market launcher first.
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("GuiButton") and looksLikeMarketLauncher(obj, market) then
            fireGuiControl(obj)
            task.wait(MARKET_OPEN_WAIT)

            market = getMarketRoot()
            if market then return market end
        end
    end

    -- Last fallback: locally expose the Market tree so real click fallback can work.
    market = getMarketRoot()
    if market then
        local current = market
        while current and current ~= playerGui do
            pcall(function()
                if current:IsA("GuiObject") then
                    current.Visible = true
                elseif current:IsA("ScreenGui") then
                    current.Enabled = true
                end
            end)
            current = current.Parent
        end
    end

    return market
end

local function getCategoryRoot(frame)
    if not frame then return nil end

    for _, wanted in ipairs({
        "Category", "Categories", "Tabs", "Tab", "Buttons",
    }) do
        local found = frame:FindFirstChild(wanted)
            or frame:FindFirstChild(wanted, true)
        if found then
            local compact = compactMarketText(found.Name)
            if compact:find("categor", 1, true)
                or compact:find("tab", 1, true)
                or wanted == "Category"
                or wanted == "Categories" then
                return found
            end
        end
    end

    return nil
end

local function isLikelyCategoryButton(button, categoryRoot)
    if not button or not button:IsA("GuiButton") then return false end

    if categoryRoot and button:IsDescendantOf(categoryRoot) then
        return true
    end

    local compact = compactMarketText(buttonTextBlob(button, 2))

    return compact:find("equipment", 1, true) ~= nil
        or compact:find("furniture", 1, true) ~= nil
        or compact:find("decor", 1, true) ~= nil
        or compact:find("decoration", 1, true) ~= nil
        or compact:find("bakery", 1, true) ~= nil
        or compact:find("other", 1, true) ~= nil
        or compact:find("misc", 1, true) ~= nil
end

local function collectMarketCategories(frame)
    local result = {}
    local seen = {}
    if not frame then return result end

    local categoryRoot = getCategoryRoot(frame)

    if categoryRoot then
        if categoryRoot:IsA("GuiButton") then
            seen[categoryRoot] = true
            result[#result + 1] = categoryRoot
        end

        for _, obj in ipairs(categoryRoot:GetDescendants()) do
            if obj:IsA("GuiButton") and not seen[obj] then
                seen[obj] = true
                result[#result + 1] = obj
            end
        end
    else
        for _, obj in ipairs(frame:GetDescendants()) do
            if obj:IsA("GuiButton")
                and not seen[obj]
                and isLikelyCategoryButton(obj, nil) then
                seen[obj] = true
                result[#result + 1] = obj
            end
        end
    end

    table.sort(result, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    return result
end

local function hasPurchaseAncestor(button, frame)
    local current = button

    for _ = 1, 8 do
        if not current or current == frame then break end

        local compact = compactMarketText(current.Name)
        if compact == "buy"
            or compact == "money"
            or compact == "purchase"
            or compact == "cash"
            or compact:find("buybutton", 1, true)
            or compact:find("purchasebutton", 1, true)
            or compact:find("moneybutton", 1, true) then
            return true
        end

        current = current.Parent
    end

    return false
end

local function looksLikePurchaseButton(button, frame, categoryRoot)
    if not button or not button:IsA("GuiButton") then return false end
    if categoryRoot and button:IsDescendantOf(categoryRoot) then return false end

    local ownName = compactMarketText(button.Name)
    local ownText = button:IsA("TextButton")
        and compactMarketText(button.Text)
        or ""
    local blob = compactMarketText(buttonTextBlob(button, 3))

    if ownName == "buy"
        or ownName == "money"
        or ownName == "purchase"
        or ownName == "cash"
        or ownText == "buy"
        or ownText == "purchase"
        or ownName:find("buybutton", 1, true)
        or ownName:find("purchasebutton", 1, true)
        or ownName:find("moneybutton", 1, true)
        or blob:find("buynow", 1, true)
        or hasPurchaseAncestor(button, frame) then
        return true
    end

    -- Common structure: generic ImageButton inside a row/Frame containing
    -- Money / Price / Cost text or a peso sign.
    local parent = button.Parent
    for _ = 1, 4 do
        if not parent or parent == frame then break end

        local parentBlob = string.lower(buttonTextBlob(parent, 2))
        local compactParent = compactMarketText(parentBlob)

        local hasMoney =
            compactParent:find("money", 1, true) ~= nil
            or compactParent:find("price", 1, true) ~= nil
            or compactParent:find("cost", 1, true) ~= nil
            or parentBlob:find("₱", 1, true) ~= nil
            or parentBlob:find("$", 1, true) ~= nil

        if hasMoney then
            return true
        end

        parent = parent.Parent
    end

    return false
end

local function collectPurchaseButtons(frame)
    local result = {}
    local seen = {}
    if not frame then return result end

    local categoryRoot = getCategoryRoot(frame)

    for _, obj in ipairs(frame:GetDescendants()) do
        if obj:IsA("GuiButton")
            and not seen[obj]
            and looksLikePurchaseButton(obj, frame, categoryRoot) then
            seen[obj] = true
            result[#result + 1] = obj
        end
    end

    table.sort(result, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    return result
end

local function getMarketScrollFrames(frame)
    local result = {}
    if not frame then return result end

    for _, obj in ipairs(frame:GetDescendants()) do
        if obj:IsA("ScrollingFrame") then
            result[#result + 1] = obj
        end
    end

    return result
end

local function buyVisibleMaterializedRows(frame)
    local total = 0
    local rebuilds = 0
    local attempted = setmetatable({}, { __mode = "k" })

    while running("ZHM_AutoBuy") and rebuilds < MARKET_MAX_REBUILDS do
        rebuilds += 1
        frame = getMarketFrame() or frame
        if not frame then break end

        local buttons = collectPurchaseButtons(frame)
        local foundNew = false

        for _, button in ipairs(buttons) do
            if not running("ZHM_AutoBuy") then break end

            if button
                and button.Parent
                and not attempted[button] then
                attempted[button] = true
                foundNew = true

                if fireGuiControl(button) then
                    total += 1
                end

                task.wait(MARKET_BUY_WAIT)
            end
        end

        if not foundNew then break end
        RunService.Heartbeat:Wait()
    end

    return total
end

local function scanAllMarketScrollPositions(frame)
    local total = 0
    if not frame then return total end

    local scrollFrames = getMarketScrollFrames(frame)

    -- Buy currently materialized rows first.
    total += buyVisibleMaterializedRows(frame)

    for _, scrolling in ipairs(scrollFrames) do
        if not running("ZHM_AutoBuy") then break end
        if scrolling and scrolling.Parent then
            local original = scrolling.CanvasPosition
            local maxY = math.max(
                0,
                scrolling.AbsoluteCanvasSize.Y - scrolling.AbsoluteWindowSize.Y
            )

            local stepY = math.max(
                scrolling.AbsoluteWindowSize.Y * 0.75,
                120
            )

            local y = 0
            while running("ZHM_AutoBuy") and y <= maxY + 1 do
                pcall(function()
                    scrolling.CanvasPosition = Vector2.new(original.X, y)
                end)

                RunService.Heartbeat:Wait()
                task.wait(MARKET_SCROLL_WAIT)

                frame = getMarketFrame() or frame
                total += buyVisibleMaterializedRows(frame)

                y += stepY
            end

            pcall(function()
                scrolling.CanvasPosition = original
            end)
        end
    end

    return total
end

local function buyAllMarketGui()
    if not running("ZHM_AutoBuy") then return 0 end

    tryOpenMarket()
    task.wait(MARKET_OPEN_WAIT)

    local frame = getMarketFrame()
    if not frame then
        report("Market", "Market UI not found yet; waiting for it to load.")
        return 0
    end

    local total = 0

    -- Current category/page.
    total += scanAllMarketScrollPositions(frame)

    -- Every category/tab.
    local initialCategories = collectMarketCategories(frame)
    local count = #initialCategories

    for index = 1, count do
        if not running("ZHM_AutoBuy") then break end

        frame = getMarketFrame() or frame
        local liveCategories = collectMarketCategories(frame)
        local category = liveCategories[index] or initialCategories[index]

        if category and category.Parent then
            fireGuiControl(category)
            task.wait(MARKET_CATEGORY_WAIT)
            RunService.Heartbeat:Wait()

            frame = getMarketFrame() or frame
            total += scanAllMarketScrollPositions(frame)
        end
    end

    return total
end

-- Generic world Buy/Purchase fallback. This catches Market items implemented as
-- ProximityPrompts instead of GUI buttons.
local function getPromptPart(prompt)
    if not prompt then return nil end

    local current = prompt.Parent
    while current and current ~= Workspace do
        if current:IsA("Attachment") then
            local parent = current.Parent
            if parent and parent:IsA("BasePart") then
                return parent
            end
        elseif current:IsA("BasePart") then
            return current
        elseif current:IsA("Model") then
            local part = current.PrimaryPart
                or current:FindFirstChild("HumanoidRootPart")
                or current:FindFirstChildWhichIsA("BasePart", true)
            if part then return part end
        end

        current = current.Parent
    end

    return nil
end

local function isWorldBuyPrompt(prompt)
    if not prompt
        or not prompt:IsA("ProximityPrompt")
        or not prompt.Enabled then
        return false
    end

    local action = compactMarketText(prompt.ActionText)
    local name = compactMarketText(prompt.Name)

    return action == "buy"
        or action:find("buy", 1, true) ~= nil
        or action:find("purchase", 1, true) ~= nil
        or name:find("buyprompt", 1, true) ~= nil
        or name:find("purchaseprompt", 1, true) ~= nil
end

local function fireAllNearbyWorldBuyPrompts()
    if not running("ZHM_AutoBuy") then return 0 end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return 0 end

    local candidates = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and isWorldBuyPrompt(obj) then
            local part = getPromptPart(obj)
            if part then
                local distance = (root.Position - part.Position).Magnitude
                if distance <= WORLD_BUY_RADIUS then
                    candidates[#candidates + 1] = {
                        prompt = obj,
                        distance = distance,
                    }
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.distance < b.distance
    end)

    local total = 0

    for _, entry in ipairs(candidates) do
        if not running("ZHM_AutoBuy") then break end

        local prompt = entry.prompt
        local now = os.clock()
        local last = worldBuyLastFire[prompt] or 0

        if now - last >= WORLD_BUY_COOLDOWN then
            worldBuyLastFire[prompt] = now

            pcall(function() prompt.HoldDuration = 0 end)
            pcall(function() prompt.RequiresLineOfSight = false end)
            pcall(function()
                prompt.MaxActivationDistance =
                    math.max(prompt.MaxActivationDistance, 60)
            end)

            if type(fireproximityprompt) == "function" then
                local ok = pcall(function()
                    fireproximityprompt(prompt, 0)
                end)

                if not ok then
                    ok = pcall(function()
                        fireproximityprompt(prompt)
                    end)
                end

                if ok then total += 1 end
            end
        end
    end

    return total
end

local function autoBuyMarket()
    if not running("ZHM_AutoBuy") then return end

    local guiBought = buyAllMarketGui()

    if not running("ZHM_AutoBuy") then return end

    local worldBought = fireAllNearbyWorldBuyPrompts()

    if guiBought > 0 or worldBought > 0 then
        report(
            "Market",
            "Auto Buy All • GUI "
                .. tostring(guiBought)
                .. " • World "
                .. tostring(worldBought)
        )
    else
        report(
            "Market",
            "Scanning all Market categories, scroll rows, and nearby Buy prompts."
        )
    end

    task.wait(MARKET_PASS_WAIT)
end

--------------------------------------------------------------------------------
-- AUTO PAY CASHIER / WORKER SALARY
-- Uses the logged Bakery worker PaySalary button.
--------------------------------------------------------------------------------
local function getBakeryWorkerItems()
    return ui({ "MainUI", "Bakery", "Frame", "ScrollingFrame", "Worker", "Items" })
end

local function tryInitializeBakeryWorkerUI()
    local items = getBakeryWorkerItems()
    if items then return items end

    -- Exact launcher family from the user's action log.
    local bakeryButton =
        ui({ "SideButtons", "Box", "RightColumn", "BakeryButton" })
        or playerGui:FindFirstChild("BakeryButton", true)

    if bakeryButton and bakeryButton:IsA("GuiButton") then
        pcall(function()
            triggerButton(bakeryButton, "PayCashier")
        end)
        task.wait(0.05)
    end

    return getBakeryWorkerItems()
end

local function autoPayCashier()
    if not farming("ZHM_AutoPayCashier") then return end

    local items = tryInitializeBakeryWorkerUI()
    if not items then
        report("PayCashier", "Cashier/worker salary controls unavailable.")
        return
    end

    local buttons = {}
    local seen = {}

    -- Prefer the exact WorkerTemplate path when present.
    local workerTemplate = items:FindFirstChild("WorkerTemplate")
    if workerTemplate then
        local exactButton = resolve(workerTemplate, { "Main_Frame", "Buttons", "PaySalary" })
        if exactButton and exactButton:IsA("GuiButton") then
            seen[exactButton] = true
            buttons[#buttons + 1] = exactButton
        end
    end

    -- Also support cloned/multiple worker rows.
    for _, obj in ipairs(items:GetDescendants()) do
        if obj:IsA("GuiButton")
            and string.lower(obj.Name or "") == "paysalary"
            and not seen[obj] then
            seen[obj] = true
            buttons[#buttons + 1] = obj
        end
    end

    if #buttons == 0 then
        report("PayCashier", "PaySalary button not found yet.")
        return
    end

    local paid = 0
    for _, button in ipairs(buttons) do
        if not farming("ZHM_AutoPayCashier") then return end

        -- Fire the game's actual PaySalary GUI callback.
        local ok, fired = pcall(function()
            return triggerButton(button, "PayCashier")
        end)

        if ok and fired then
            paid += 1
        end
    end

    if paid > 0 then
        report("PayCashier", "PaySalary dispatched on " .. tostring(paid) .. " worker button(s).")
    end
end

local function autoUpgradeBakery()
    local items = ui({ "MainUI", "Bakery", "Frame", "ScrollingFrame", "Upgrade", "Items" })
    if not items then report("Upgrade", "Upgrade Money controls unavailable."); return end
    for _, item in ipairs(sortedChildren(items)) do
        if not running("ZHM_AutoUpgrade") then return end
        local button = resolve(item, { "Main_Frame", "Buttons", "Money" })
        if button then triggerButton(button, "Upgrade"); task.wait() end
    end
end

local farmJobs = {
    { Key = "ZHM_AutoAccept", Name = "Accept", Interval = 0.05, Run = autoAccept },
    { Key = "ZHM_AutoPrepareDough", Name = "Dough", Interval = 0.1, Run = autoPrepareDough },
    { Key = "ZHM_AutoBake", Name = "Bake", Interval = 0.05, Run = bakeAllBreads },
    { Key = "ZHM_AutoCollect", Name = "Collect", Interval = 0.05, Run = collectEquipmentPrompts },
    { Key = "ZHM_AutoCollectTip", Name = "Tip", Interval = 0.08, Run = autoCollectTip },
    { Key = "ZHM_AutoGiveOrder", Name = "GiveOrder", Interval = 0.05, Run = autoGiveOrder },
    { Key = "ZHM_AutoPayCashier", Name = "PayCashier", Interval = 0.25, Run = autoPayCashier },
    { Key = "ZHM_AutoEnableBreads", Name = "Breads", Interval = 0.2, Run = autoEnableBreads },
}

local function startAutomation()
    -- Run every bakery feature in its own worker. A collect scan, UI refresh, or
    -- bake wait can no longer stall Give Order / Collect later in the round.
    for _, definition in ipairs(farmJobs) do
        local job = definition
        task.spawn(function()
            while isCurrent() do
                if farming(job.Key) then
                    local ok, err = pcall(job.Run)
                    if not ok then report(job.Name, tostring(err)) end
                    task.wait(job.Interval)
                else
                    task.wait(0.03)
                end
            end
        end)
    end

    for _, definition in ipairs({
        { Key = "ZHM_AutoBuy", Name = "Market", Run = autoBuyMarket },
        { Key = "ZHM_AutoUpgrade", Name = "Upgrade", Run = autoUpgradeBakery },
    }) do
        local job = definition
        task.spawn(function()
            while isCurrent() do
                if running(job.Key) then
                    local ok, err = pcall(job.Run)
                    if not ok then report(job.Name, tostring(err)) end
                end
                task.wait()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- 6A. NIGHT TRASH AUTO SWEEP - DIRECT SWEEPPROMPT HEARTBEAT SPAM
-- Logged action path:
--   Workspace.SideJobTrash.SideJobTrash.SweepPrompt
--
-- While Night Auto Sweep is enabled and it is night:
--   1) Resolve the exact logged SweepPrompt every frame so recreated trash still works.
--   2) Keep the prompt instant/reachable.
--   3) Stay near the active trash prompt when needed.
--   4) Fire the prompt every Heartbeat while it remains enabled.
--   5) Fall back to the older live sweep scanner only if the exact path is missing.
--------------------------------------------------------------------------------
do
    local SWEEP_TP_HEIGHT_OFFSET = 2.5
    local SWEEP_TP_BACK_OFFSET = 1.5
    local SWEEP_RETP_DISTANCE = 12
    local SWEEP_RETP_COOLDOWN = 0.20
    local SWEEP_FALLBACK_RESCAN = 0.10

    local lastSweepPrompt = nil
    local lastSweepTeleport = 0
    local lastFallbackScan = 0
    local fallbackPrompts = {}

    local function guiObjectActive(obj)
        if not obj or not obj:IsA("GuiObject") or not obj.Visible then
            return false
        end

        local current = obj.Parent
        while current and current ~= playerGui do
            if current:IsA("GuiObject") and not current.Visible then
                return false
            end
            current = current.Parent
        end

        return true
    end

    local function getWeatherFrame()
        local weatherUI = playerGui:FindFirstChild("WeatherUI")
        return weatherUI and weatherUI:FindFirstChild("Frame") or nil
    end

    local function isNight()
        local frame = getWeatherFrame()
        if frame then
            local night = frame:FindFirstChild("Night")
            local day = frame:FindFirstChild("Day")

            if night and guiObjectActive(night) then return true end
            if day and guiObjectActive(day) then return false end

            for _, obj in ipairs(frame:GetDescendants()) do
                local lower = string.lower(obj.Name or "")
                if lower == "night" and guiObjectActive(obj) then
                    return true
                elseif lower == "day" and guiObjectActive(obj) then
                    return false
                end
            end
        end

        -- Fallback if WeatherUI is recreated/missing.
        local lighting = game:GetService("Lighting")
        local clockTime = tonumber(lighting.ClockTime)
        if clockTime then
            return clockTime >= 18 or clockTime < 6
        end

        return false
    end

    local function getCharacter()
        return player.Character or player.CharacterAdded:Wait()
    end

    local function getRoot()
        local character = getCharacter()
        return character and character:FindFirstChild("HumanoidRootPart") or nil
    end

    local function getPromptPart(prompt)
        if not prompt then return nil end
        local current = prompt.Parent

        while current and current ~= Workspace do
            if current:IsA("BasePart") then
                return current
            elseif current:IsA("Model") then
                local part = current.PrimaryPart
                    or current:FindFirstChild("HumanoidRootPart")
                    or current:FindFirstChildWhichIsA("BasePart", true)
                if part then return part end
            end
            current = current.Parent
        end

        return nil
    end

    -- Exact path from ActionLogs V10:
    -- Workspace.SideJobTrash.SideJobTrash.SweepPrompt
    local function getExactSweepPrompt()
        local outer = Workspace:FindFirstChild("SideJobTrash")
        if not outer then return nil end

        local inner = outer:FindFirstChild("SideJobTrash")
        local prompt = inner and inner:FindFirstChild("SweepPrompt")

        if prompt and prompt:IsA("ProximityPrompt") then
            return prompt
        end

        -- Small exact-name fallback inside SideJobTrash in case one nesting level changes.
        prompt = outer:FindFirstChild("SweepPrompt", true)
        if prompt and prompt:IsA("ProximityPrompt") then
            return prompt
        end

        return nil
    end

    local function getFallbackSweepPrompts()
        local now = os.clock()
        if now - lastFallbackScan < SWEEP_FALLBACK_RESCAN then
            return fallbackPrompts
        end

        lastFallbackScan = now
        fallbackPrompts = {}
        local seen = setmetatable({}, { __mode = "k" })

        local function scan(container)
            if not container then return end

            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and obj.Enabled and not seen[obj] then
                    local name = string.lower(obj.Name or "")
                    local action = string.lower(tostring(obj.ActionText or ""))
                    local objectText = string.lower(tostring(obj.ObjectText or ""))
                    local path = ""
                    pcall(function() path = string.lower(obj:GetFullName()) end)

                    local looksLikeSweep = name == "sweep"
                        or name == "sweepprompt"
                        or name:find("sweep", 1, true) ~= nil
                        or action:find("sweep", 1, true) ~= nil
                        or (objectText:find("trash", 1, true) ~= nil and action ~= "")
                        or path:find("sidejobtrash", 1, true) ~= nil

                    if looksLikeSweep then
                        seen[obj] = true
                        fallbackPrompts[#fallbackPrompts + 1] = obj
                    end
                end
            end
        end

        local trashRoot = Workspace:FindFirstChild("SideJobTrash")
        scan(trashRoot)

        if #fallbackPrompts == 0 then
            scan(Workspace)
        end

        return fallbackPrompts
    end

    local function makePromptInstant(prompt)
        if not prompt then return end
        pcall(function() prompt.HoldDuration = 0 end)
        pcall(function() prompt.RequiresLineOfSight = false end)
        pcall(function() prompt.ClickablePrompt = true end)
        pcall(function()
            prompt.MaxActivationDistance = math.max(
                tonumber(prompt.MaxActivationDistance) or 0,
                100000
            )
        end)
    end

    local function keepNearSweepPrompt(prompt)
        local root = getRoot()
        local part = getPromptPart(prompt)
        if not root or not part then return false end

        local distance = (root.Position - part.Position).Magnitude
        local now = os.clock()

        -- TP once for a newly recreated prompt, or again only if something moved us away.
        if prompt ~= lastSweepPrompt
            or (distance > SWEEP_RETP_DISTANCE and now - lastSweepTeleport >= SWEEP_RETP_COOLDOWN) then

            root.CFrame = part.CFrame * CFrame.new(0, SWEEP_TP_HEIGHT_OFFSET, SWEEP_TP_BACK_OFFSET)
            lastSweepTeleport = now
        end

        lastSweepPrompt = prompt
        return true
    end

    local function fireSweepPromptOnce(prompt)
        if not prompt or not prompt.Parent or not prompt.Enabled then
            return false
        end

        makePromptInstant(prompt)

        if type(fireproximityprompt) == "function" then
            local ok = pcall(function()
                fireproximityprompt(prompt, 0, true)
            end)

            if not ok then
                ok = pcall(function()
                    fireproximityprompt(prompt, 0)
                end)
            end

            if not ok then
                ok = pcall(function()
                    fireproximityprompt(prompt)
                end)
            end

            if ok then
                return true
            end
        end

        -- Executor fallback when fireproximityprompt is unavailable/fails.
        local keyCode = prompt.KeyboardKeyCode
        if keyCode and keyCode ~= Enum.KeyCode.Unknown then
            return pcall(function()
                VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
            end)
        end

        return false
    end

    task.spawn(function()
        while isCurrent() do
            if ENV.ZHM_AutoSweep ~= true then
                ENV.ZHM_SweepActive = false
                ENV.ZHM_SweepStatus = "OFF"
                lastSweepPrompt = nil
                RunService.Heartbeat:Wait()
            elseif not isNight() then
                ENV.ZHM_SweepActive = false
                ENV.ZHM_SweepStatus = "Waiting for night"
                lastSweepPrompt = nil
                RunService.Heartbeat:Wait()
            else
                -- PRIMARY METHOD: exact logged path, spammed every Heartbeat at night.
                local exactPrompt = getExactSweepPrompt()

                if exactPrompt and exactPrompt.Parent and exactPrompt.Enabled then
                    ENV.ZHM_SweepActive = true
                    ENV.ZHM_NPCBusy = false

                    keepNearSweepPrompt(exactPrompt)
                    local fired = fireSweepPromptOnce(exactPrompt)

                    ENV.ZHM_SweepStatus = fired
                        and "Night • DIRECT SweepPrompt SPAM"
                        or "Night • SweepPrompt found • retrying"
                else
                    -- FALLBACK: if the exact path is temporarily missing/reparented,
                    -- keep the previous live scanner as a compatibility safety net.
                    local prompts = getFallbackSweepPrompts()
                    local activePrompt = nil

                    for _, prompt in ipairs(prompts) do
                        if prompt and prompt.Parent and prompt.Enabled then
                            activePrompt = prompt
                            break
                        end
                    end

                    if activePrompt then
                        ENV.ZHM_SweepActive = true
                        ENV.ZHM_NPCBusy = false

                        keepNearSweepPrompt(activePrompt)
                        local fired = fireSweepPromptOnce(activePrompt)

                        ENV.ZHM_SweepStatus = fired
                            and "Night • fallback Sweep SPAM"
                            or "Night • fallback prompt • retrying"
                    else
                        ENV.ZHM_SweepActive = false
                        ENV.ZHM_SweepStatus = "Night • no active trash prompt"
                        lastSweepPrompt = nil
                    end
                end

                -- No artificial sweep delay: the prompt is attempted once every Heartbeat.
                RunService.Heartbeat:Wait()
            end
        end

        ENV.ZHM_SweepActive = false
        ENV.ZHM_SweepStatus = "Stopped"
    end)
end

--------------------------------------------------------------------------------
-- 6B. LIVE CUSTOMER.HEAD.RUNAWAYEXCLAM SCANNER + AUTO TP + 3-SECOND ROLLING PIN SWING
--------------------------------------------------------------------------------
do
    local ROLLING_PIN_SLOT = "1"
    local rollingPinEquippedThisCharacter = false
    local equipInProgress = false
    local equipActionDoneThisCharacter = false -- one successful equip/select action per character
    local directEquipTriedThisCharacter = false -- never spam Humanoid:EquipTool

    -- STRICT live target rules:
    --   1) Model name must be exactly "Customer" (case-insensitive).
    --   2) Customer must be alive and have HumanoidRootPart + Head.
    --   3) Head must contain a live object named exactly "RunawayExclam".
    --   4) Customer must be within the local scan zone around OutsideWall or DisplayRack.
    -- A valid target is teleported to automatically, then the already-equipped
    -- Rolling Pin swings for exactly 3 seconds without touching equip/unequip state.
    local CUSTOMER_MODEL_NAME = "customer"
    local RUNAWAY_MARKER_NAME = "RunawayExclam"
    local NPC_SWING_DURATION = 3.0
    local NPC_ZONE_SCAN_RADIUS = 20 -- only around OutsideWall / DisplayRack
    local NPC_SCAN_INTERVAL = 0.08
    local NPC_SWING_INTERVAL = 0.08
    local NPC_CLICK_HOLD_TIME = 0.025
    local NPC_SWING_MAX_DISTANCE = 1000000000 -- target was already validated by Customer.Head.RunawayExclam
    local NPC_TP_KEEP_DISTANCE = 3.0 -- stay close enough to hit without stacking inside the NPC
    local NPC_TP_REPOSITION_DISTANCE = 5.0 -- re-TP only after the NPC moves away from us
    local NPC_TP_VERTICAL_OFFSET = 0.5

    local cachedPlot = nil
    local cachedPlotParts = nil
    local cachedPlotPartsFor = nil
    local cachedNPCZoneParts = nil
    local cachedNPCZonePartsFor = nil
    local cachedNPCZonePartsAt = 0
    local cachedNPCZoneHasOutsideWall = false
    local cachedNPCZoneHasDisplayRack = false
    local currentTarget = nil

    local function getHotbarSlot1()
        local pg = player:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end

        -- Known custom/default-like backpack path used by this game.
        local backpackGui = pg:FindFirstChild("BackpackGui")
        local backpack = backpackGui and backpackGui:FindFirstChild("Backpack")
        local hotbar = backpack and backpack:FindFirstChild("Hotbar")
        local slot = hotbar and hotbar:FindFirstChild(ROLLING_PIN_SLOT)
        if slot then return slot end

        -- Fallback: find a visible GuiObject named "1" whose descendants say Rolling Pin.
        for _, obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("GuiObject") and obj.Name == ROLLING_PIN_SLOT then
                local textFound = false
                if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                    local text = string.lower(tostring(obj.Text or ""))
                    textFound = text:find("rolling", 1, true) ~= nil and text:find("pin", 1, true) ~= nil
                end
                if not textFound then
                    for _, d in ipairs(obj:GetDescendants()) do
                        if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                            local text = string.lower(tostring(d.Text or ""))
                            if text:find("rolling", 1, true) and text:find("pin", 1, true) then
                                textFound = true
                                break
                            end
                        end
                    end
                end
                if textFound then return obj end
            end
        end

        return nil
    end

    local function slotShowsRollingPin(slot)
        if not slot or not slot:IsA("GuiObject") then return false end

        local function textMatches(obj)
            if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
                return false
            end
            local text = string.lower(tostring(obj.Text or ""))
            return text:find("rolling", 1, true) ~= nil and text:find("pin", 1, true) ~= nil
        end

        if textMatches(slot) then return true end
        for _, d in ipairs(slot:GetDescendants()) do
            if textMatches(d) then return true end
        end
        return false
    end

    local function virtualClickGuiOnce(guiObject)
        if not guiObject or not guiObject:IsA("GuiObject") then return false end
        local size = guiObject.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then return false end

        local pos = guiObject.AbsolutePosition
        local x = math.floor(pos.X + size.X / 2)
        local y = math.floor(pos.Y + size.Y / 2)

        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.035)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    local function pressRollingPinHotkeyOnce()
        -- A single 1-key press is more reliable than firing several GUI signals and,
        -- importantly, cannot create the old equip -> unequip double-toggle by itself.
        local ok = pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
            task.wait(0.04)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
        end)
        return ok
    end

    local function isRollingPinTool(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local compact = string.lower(tool.Name or ""):gsub("[%s_%-]+", "")
        return compact:find("rollingpin", 1, true) ~= nil
            or compact == "pin"
            or compact:find("bat", 1, true) ~= nil
    end

    local function findRollingPinTool()
        local character = player.Character
        if character then
            for _, obj in ipairs(character:GetChildren()) do
                if isRollingPinTool(obj) then
                    return obj, true
                end
            end
        end

        local backpack = player:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, obj in ipairs(backpack:GetChildren()) do
                if isRollingPinTool(obj) then
                    return obj, false
                end
            end
        end

        return nil, false
    end

    local function waitForEquippedTool(timeout)
        local deadline = os.clock() + (timeout or 0.75)
        repeat
            local liveTool, liveEquipped = findRollingPinTool()
            if liveTool and liveEquipped then
                rollingPinEquippedThisCharacter = true
                return true
            end
            RunService.Heartbeat:Wait()
        until not isCurrent() or os.clock() >= deadline
        return false
    end

    local function equipRollingPinOnce()
        if equipInProgress or equipActionDoneThisCharacter then
            return rollingPinEquippedThisCharacter
        end
        if ENV.ZHM_NPCAutoSwing ~= true then return false end

        equipInProgress = true

        -- IMPORTANT: do not mark the one-time action as consumed until the Rolling Pin
        -- actually exists. This fixes the old startup race where the script ran before
        -- BackpackGui / the Tool had loaded and permanently gave up after that first miss.
        while isCurrent()
            and ENV.ZHM_NPCAutoSwing == true
            and not equipActionDoneThisCharacter do

            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local tool, equipped = findRollingPinTool()

            -- Already equipped before this script got to it: accept that state and stop.
            if tool and equipped then
                rollingPinEquippedThisCharacter = true
                equipActionDoneThisCharacter = true
                break
            end

            -- Best path: equip the actual Tool exactly once after both Tool + Humanoid exist.
            if tool and humanoid and not directEquipTriedThisCharacter then
                directEquipTriedThisCharacter = true
                local called = pcall(function()
                    humanoid:EquipTool(tool)
                end)

                if called and waitForEquippedTool(1.0) then
                    equipActionDoneThisCharacter = true
                    break
                end

                -- Never call EquipTool again for this character. If the game uses a
                -- custom hotbar instead, the code below may perform one slot selection.
            end

            -- Custom inventory path. Wait until slot 1 is visibly the Rolling Pin, then
            -- perform ONE selection action. On desktop use the game's normal "1" hotkey;
            -- on touch-only devices click the visible slot once.
            local slot = getHotbarSlot1()
            if slot and slot:IsA("GuiObject") and slot.Visible
                and slot.AbsoluteSize.X > 0 and slot.AbsoluteSize.Y > 0
                and slotShowsRollingPin(slot) then

                local selected = false
                if IS_MOBILE_DEVICE then
                    selected = virtualClickGuiOnce(slot)
                else
                    selected = pressRollingPinHotkeyOnce()
                    if not selected then
                        selected = virtualClickGuiOnce(slot)
                    end
                end

                if selected then
                    -- Custom inventories may not expose an equipped Tool in Character.
                    -- The input above is intentionally sent exactly once; from here on,
                    -- swing code only attacks and never touches equipment again.
                    task.wait(0.12)
                    local liveTool, liveEquipped = findRollingPinTool()
                    rollingPinEquippedThisCharacter = (liveTool and liveEquipped) or true
                    equipActionDoneThisCharacter = true
                    break
                end
            end

            -- Keep waiting for inventory/UI replication. This is still "equip once":
            -- no equip/select input has been sent yet, so waiting does not toggle anything.
            task.wait(0.10)
        end

        equipInProgress = false
        return rollingPinEquippedThisCharacter
    end

    -- Start one waiter on execution. It waits for the Rolling Pin to actually load,
    -- then performs exactly one equip/select action for this character.
    task.spawn(function()
        while isCurrent() and not equipActionDoneThisCharacter do
            if ENV.ZHM_NPCAutoSwing == true then
                equipRollingPinOnce()
            end
            if not equipActionDoneThisCharacter then
                task.wait(0.10)
            end
        end
    end)

    player.CharacterAdded:Connect(function()
        rollingPinEquippedThisCharacter = false
        equipInProgress = false
        equipActionDoneThisCharacter = false
        directEquipTriedThisCharacter = false
        cachedPlot = nil
        cachedPlotParts = nil
        cachedPlotPartsFor = nil
        currentTarget = nil
        ENV.ZHM_NPCBusy = false

        -- New character = new inventory instance, so do one fresh equip for that spawn.
        task.spawn(function()
            while isCurrent() and not equipActionDoneThisCharacter do
                if ENV.ZHM_NPCAutoSwing == true then
                    equipRollingPinOnce()
                end
                if not equipActionDoneThisCharacter then
                    task.wait(0.10)
                end
            end
        end)
    end)

    local function getPlayerRoot()
        local character = player.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local function isPlayerCharacter(model)
        return model and Players:GetPlayerFromCharacter(model) ~= nil
    end

    local function isCustomerModel(model)
        return model
            and model:IsA("Model")
            and string.lower(tostring(model.Name or "")) == CUSTOMER_MODEL_NAME
    end

    local function getRunawayMarker(model)
        if not model or not model:IsA("Model") then return nil, nil end

        -- Exact live path shown in Explorer: Customer > Head > RunawayExclam.
        local head = model:FindFirstChild("Head")
        if not head or not head:IsA("BasePart") then return nil, nil end

        local marker = head:FindFirstChild(RUNAWAY_MARKER_NAME)
        if not marker then return nil, head end
        return marker, head
    end

    local function isRunawayMarkerActive(marker, head)
        if not marker or not marker.Parent then return false end
        if not head or not head.Parent or marker.Parent ~= head then return false end
        if marker.Name ~= RUNAWAY_MARKER_NAME then return false end

        -- If the marker exposes a normal visibility/enabled property, respect it.
        -- Unknown marker classes are considered active while the exact object exists.
        if marker:IsA("BillboardGui") or marker:IsA("SurfaceGui") then
            return marker.Enabled == true
        elseif marker:IsA("GuiObject") then
            return marker.Visible == true
        elseif marker:IsA("ParticleEmitter") or marker:IsA("Trail") or marker:IsA("Beam") then
            return marker.Enabled == true
        end

        return true
    end

    local function getPlotPositionFolder(plot)
        if not plot then return nil end
        return plot:FindFirstChild("Position") or plot:FindFirstChild("Positions") or plot
    end

    local function getModelRoot(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChild("HumanoidRootPart", true)
            or model.PrimaryPart
            or model:FindFirstChild("UpperTorso", true)
            or model:FindFirstChild("Torso", true)
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getPlotParts(plot)
        if not plot then return {} end

        if cachedPlotPartsFor == plot and cachedPlotParts then
            local live = false
            for _, part in ipairs(cachedPlotParts) do
                if part and part.Parent then
                    live = true
                    break
                end
            end
            if live then return cachedPlotParts end
        end

        local root = getPlotPositionFolder(plot)
        local parts = {}
        local seen = {}

        local function addPart(part)
            if part and part:IsA("BasePart") and not seen[part] then
                seen[part] = true
                parts[#parts + 1] = part
            end
        end

        if root then
            if root:IsA("BasePart") then addPart(root) end
            for _, obj in ipairs(root:GetDescendants()) do
                addPart(obj)
            end
        end

        -- Fallback only if the Position folder has no physical parts.
        if #parts == 0 then
            if plot:IsA("BasePart") then addPart(plot) end
            for _, obj in ipairs(plot:GetDescendants()) do
                addPart(obj)
            end
        end

        cachedPlotPartsFor = plot
        cachedPlotParts = parts
        return parts
    end

    local function distancePointToPart(position, part)
        if not position or not part or not part.Parent then return math.huge end

        local localPoint = part.CFrame:PointToObjectSpace(position)
        local half = part.Size * 0.5
        local closest = Vector3.new(
            math.clamp(localPoint.X, -half.X, half.X),
            math.clamp(localPoint.Y, -half.Y, half.Y),
            math.clamp(localPoint.Z, -half.Z, half.Z)
        )

        return (localPoint - closest).Magnitude
    end

    local function distanceToMyPlot(position, plot)
        if not position or not plot then return math.huge end

        local nearest = math.huge
        for _, part in ipairs(getPlotParts(plot)) do
            if part and part.Parent then
                local d = distancePointToPart(position, part)
                if d < nearest then
                    nearest = d
                    if nearest <= 0.05 then break end
                end
            end
        end
        return nearest
    end

    local function plotDistanceFromPlayer(plot)
        local myRoot = getPlayerRoot()
        if not myRoot or not plot then return math.huge end
        return distanceToMyPlot(myRoot.Position, plot)
    end

    local function findNPCPlot()
        if cachedPlot and cachedPlot.Parent then return cachedPlot end

        local gameFolder = Workspace:FindFirstChild("Game")
        local shops = gameFolder and gameFolder:FindFirstChild("Shops")
        if not shops then return nil end

        -- Prefer explicit ownership so the scanner always starts from YOUR plot.
        for _, plot in ipairs(shops:GetChildren()) do
            local owner = plot:FindFirstChild("Owner")
                or plot:FindFirstChild("Player")
                or plot:FindFirstChild("OwnerPlayer")
                or plot:FindFirstChild("PlotOwner")

            if owner and owner:IsA("ValueBase") then
                local value = owner.Value
                if value == player or value == player.Name or value == player.UserId then
                    cachedPlot = plot
                    cachedPlotParts = nil
                    cachedPlotPartsFor = nil
                    return plot
                end
            end

            local ownerUserId = plot:GetAttribute("OwnerUserId")
            local ownerName = plot:GetAttribute("Owner")
                or plot:GetAttribute("OwnerName")
                or plot:GetAttribute("PlayerName")

            if ownerUserId == player.UserId or ownerName == player.Name then
                cachedPlot = plot
                cachedPlotParts = nil
                cachedPlotPartsFor = nil
                return plot
            end
        end

        -- Fallback: nearest plot to the player.
        local closestPlot = nil
        local closestDistance = math.huge
        for _, plot in ipairs(shops:GetChildren()) do
            local d = plotDistanceFromPlayer(plot)
            if d < closestDistance then
                closestDistance = d
                closestPlot = plot
            end
        end

        cachedPlot = closestPlot
        cachedPlotParts = nil
        cachedPlotPartsFor = nil
        return closestPlot
    end

    -- Build the ONLY two NPC scan zones we care about: OutsideWall and DisplayRack.
    -- This is intentionally separate from getPlotParts(), which is still used only to
    -- identify the player's plot. NPC candidate scanning never covers the whole plot.
    local function compactObjectName(name)
        return string.lower(tostring(name or "")):gsub("[%s_%-]+", "")
    end

    local function getNPCScanZoneParts(plot)
        if not plot then return {}, false, false end

        local now = os.clock()
        if cachedNPCZonePartsFor == plot
            and cachedNPCZoneParts
            and now - cachedNPCZonePartsAt < 1.0 then
            return cachedNPCZoneParts,
                cachedNPCZoneHasOutsideWall,
                cachedNPCZoneHasDisplayRack
        end

        local parts = {}
        local seen = {}
        local foundOutsideWall = false
        local foundDisplayRack = false

        local function addPart(part)
            if part and part:IsA("BasePart") and part.Parent and not seen[part] then
                seen[part] = true
                parts[#parts + 1] = part
            end
        end

        local function addContainerParts(container)
            if not container then return end

            if container:IsA("BasePart") then
                addPart(container)
            end

            for _, descendant in ipairs(container:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    addPart(descendant)
                end
            end
        end

        -- Match the named plot objects themselves, then use the physical parts under
        -- each one. This works whether OutsideWall / DisplayRack is a Part, Model,
        -- Folder, or a nested equipment container.
        for _, obj in ipairs(plot:GetDescendants()) do
            local compact = compactObjectName(obj.Name)

            if compact:find("outsidewall", 1, true) then
                foundOutsideWall = true
                addContainerParts(obj)
            elseif compact:find("displayrack", 1, true) then
                foundDisplayRack = true
                addContainerParts(obj)
            end
        end

        cachedNPCZonePartsFor = plot
        cachedNPCZoneParts = parts
        cachedNPCZonePartsAt = now
        cachedNPCZoneHasOutsideWall = foundOutsideWall
        cachedNPCZoneHasDisplayRack = foundDisplayRack

        return parts, foundOutsideWall, foundDisplayRack
    end

    local function distanceToNPCScanZone(position, plot)
        if not position or not plot then return math.huge end

        local zoneParts = getNPCScanZoneParts(plot)
        local nearest = math.huge

        for _, part in ipairs(zoneParts) do
            if part and part.Parent then
                local distance = distancePointToPart(position, part)
                if distance < nearest then
                    nearest = distance
                    if nearest <= 0.05 then break end
                end
            end
        end

        return nearest
    end

    local function getNPCZoneCandidateParts(plot)
        local zoneParts, hasOutsideWall, hasDisplayRack = getNPCScanZoneParts(plot)
        if #zoneParts == 0 then
            return {}, hasOutsideWall, hasDisplayRack
        end

        local overlap = OverlapParams.new()
        overlap.FilterType = Enum.RaycastFilterType.Exclude
        overlap.FilterDescendantsInstances = player.Character and { player.Character } or {}
        overlap.MaxParts = 0

        local results = {}
        local seenParts = {}
        local expand = NPC_ZONE_SCAN_RADIUS * 2
        local expansion = Vector3.new(expand, expand, expand)

        -- Query only small expanded boxes around the two named zones. Roblox's spatial
        -- query handles nearby parts directly, so NPCs elsewhere in the map are not
        -- iterated or speed-checked at all.
        for _, anchorPart in ipairs(zoneParts) do
            if anchorPart and anchorPart.Parent then
                local scanSize = anchorPart.Size + expansion
                local ok, nearbyParts = pcall(function()
                    return Workspace:GetPartBoundsInBox(anchorPart.CFrame, scanSize, overlap)
                end)

                if ok and nearbyParts then
                    for _, nearbyPart in ipairs(nearbyParts) do
                        if nearbyPart and nearbyPart.Parent and not seenParts[nearbyPart] then
                            seenParts[nearbyPart] = true
                            results[#results + 1] = nearbyPart
                        end
                    end
                end
            end
        end

        return results, hasOutsideWall, hasDisplayRack
    end

    local function getHumanoidModelFromPart(part)
        if not part then return nil, nil end

        local current = part.Parent
        while current and current ~= Workspace do
            if current:IsA("Model") then
                local humanoid = current:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    return current, humanoid
                end
            end
            current = current.Parent
        end

        return nil, nil
    end

    local function isStillValidRunawayTarget(target)
        if not target or not target.model or not target.model.Parent then return false end
        if isPlayerCharacter(target.model) or not isCustomerModel(target.model) then return false end
        if not target.root or not target.root.Parent or not target.root:IsA("BasePart") then return false end
        if target.root.Name ~= "HumanoidRootPart" then return false end
        if not target.humanoid or not target.humanoid.Parent or target.humanoid.Health <= 0 then return false end

        local marker, head = getRunawayMarker(target.model)
        if not marker or not isRunawayMarkerActive(marker, head) then return false end

        local myPlot = target.plot
        if not myPlot or not myPlot.Parent then
            myPlot = findNPCPlot()
        end
        if not myPlot then return false end

        -- The Customer must STILL be near OutsideWall or DisplayRack. Moving into the
        -- rest of the plot/map immediately drops it as a target.
        local zoneDistance = distanceToNPCScanZone(target.root.Position, myPlot)
        if zoneDistance > NPC_ZONE_SCAN_RADIUS then return false end

        target.runawayMarker = marker
        target.head = head
        target.zoneDistance = zoneDistance
        target.plotDistance = zoneDistance -- compatibility with any external status readers
        target.plot = myPlot
        return true
    end

    local function teleportToRunawayCustomer(target)
        if ENV.ZHM_NPCAutoTP ~= true then return false end
        if not target or not target.root or not target.root.Parent then return false end

        local myRoot = getPlayerRoot()
        if not myRoot or not myRoot.Parent then return false end

        local targetRoot = target.root
        local currentDistance = (myRoot.Position - targetRoot.Position).Magnitude

        -- Once close enough, do not spam CFrame every scan. Reposition only when
        -- the runaway Customer creates some distance again.
        if currentDistance <= NPC_TP_REPOSITION_DISTANCE then
            return true
        end

        -- Stand a few studs to the NPC's side and face it. This avoids placing the
        -- player's root directly inside the NPC while still keeping melee range.
        local side = targetRoot.CFrame.RightVector
        if side.Magnitude < 0.1 then
            side = Vector3.new(1, 0, 0)
        end

        local destination = targetRoot.Position
            + side.Unit * NPC_TP_KEEP_DISTANCE
            + Vector3.new(0, NPC_TP_VERTICAL_OFFSET, 0)

        local lookAt = targetRoot.Position + Vector3.new(0, NPC_TP_VERTICAL_OFFSET, 0)
        local ok = pcall(function()
            myRoot.CFrame = CFrame.lookAt(destination, lookAt)
        end)

        return ok
    end

    -- One 3-second burst per live marker appearance. Once RunawayExclam disappears
    -- or becomes inactive, the same Customer can trigger again the next time it appears.
    local handledRunawayMarkers = setmetatable({}, { __mode = "k" })

    local function refreshHandledRunawayMarkers()
        for marker in pairs(handledRunawayMarkers) do
            local head = marker and marker.Parent
            if not marker
                or not marker.Parent
                or not head
                or not head:IsA("BasePart")
                or not isRunawayMarkerActive(marker, head) then
                handledRunawayMarkers[marker] = nil
            end
        end
    end

    local function findNearestRunawayCustomer()
        local myPlot = findNPCPlot()
        if not myPlot then
            ENV.ZHM_NPCStatus = "LIVE scanner • waiting for your plot"
            return nil, 0
        end

        local candidateParts, hasOutsideWall, hasDisplayRack = getNPCZoneCandidateParts(myPlot)
        if not hasOutsideWall and not hasDisplayRack then
            ENV.ZHM_NPCStatus = "LIVE scanner • waiting for OutsideWall / DisplayRack"
            return nil, 0
        end

        refreshHandledRunawayMarkers()

        local best = nil
        local bestZoneDistance = math.huge
        local seenModels = {}
        local liveCount = 0

        -- LIVE SCANNER: only parts returned by the OutsideWall / DisplayRack spatial
        -- queries can become candidates. The marker is checked every scan pass, so a
        -- newly-created Customer > Head > RunawayExclam is picked up immediately.
        for _, part in ipairs(candidateParts) do
            local model, humanoid = getHumanoidModelFromPart(part)

            if model
                and humanoid
                and humanoid.Health > 0
                and not seenModels[model]
                and not isPlayerCharacter(model)
                and isCustomerModel(model) then

                seenModels[model] = true

                local root = model:FindFirstChild("HumanoidRootPart")
                local marker, head = getRunawayMarker(model)

                if root
                    and root:IsA("BasePart")
                    and root.Parent
                    and head
                    and marker
                    and isRunawayMarkerActive(marker, head) then

                    local zoneDistance = distanceToNPCScanZone(root.Position, myPlot)
                    if zoneDistance <= NPC_ZONE_SCAN_RADIUS then
                        liveCount += 1

                        if handledRunawayMarkers[marker] ~= true and zoneDistance < bestZoneDistance then
                            bestZoneDistance = zoneDistance
                            best = {
                                model = model,
                                root = root,
                                head = head,
                                humanoid = humanoid,
                                runawayMarker = marker,
                                zoneDistance = zoneDistance,
                                plotDistance = zoneDistance, -- compatibility
                                plot = myPlot,
                            }
                        end
                    end
                end
            end
        end

        return best, liveCount
    end

    local function clickGameplayToSwing()
        local camera = Workspace.CurrentCamera
        if not camera then return false end
        local viewport = camera.ViewportSize
        local x = math.floor(viewport.X * 0.5)
        local y = math.floor(viewport.Y * 0.60)

        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(NPC_CLICK_HOLD_TIME)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    local function swingRollingPinRobust()
        if not isCurrent() or ENV.ZHM_NPCAutoSwing ~= true then return false end

        -- SWING ONLY. Never equip, unequip, click the hotbar, or call EquipTool here.
        local tool, equipped = findRollingPinTool()
        if tool and equipped then
            rollingPinEquippedThisCharacter = true
            return pcall(function() tool:Activate() end)
        end

        -- Compatibility path for custom inventories where the equipped item is not
        -- exposed as a Backpack/Character Tool. This is a gameplay swing click only;
        -- it never touches the inventory/hotbar.
        if rollingPinEquippedThisCharacter then
            return clickGameplayToSwing()
        end

        return false
    end

    -- Shared one-shot swing used by the movement route when it reaches the Cashier.
    ENV.ZHM_SwingRollingPinNow = function()
        if not isCurrent()
            or ENV.ZHM_NPCAutoSwing ~= true
            or ENV.ZHM_SweepActive == true then
            return false
        end

        return swingRollingPinRobust()
    end

    task.spawn(function()
        while isCurrent() do
            local anyNPCFeature = ENV.ZHM_NPCAutoSwing == true or ENV.ZHM_NPCAutoTP == true

            if anyNPCFeature and ENV.ZHM_SweepActive ~= true then
                refreshHandledRunawayMarkers()

                -- Keep the active Customer for only one 3-second swing burst.
                if currentTarget then
                    if not isStillValidRunawayTarget(currentTarget) then
                        currentTarget = nil
                        ENV.ZHM_NPCBusy = false
                    elseif os.clock() >= (currentTarget.swingUntil or 0) then
                        if currentTarget.runawayMarker then
                            handledRunawayMarkers[currentTarget.runawayMarker] = true
                        end
                        currentTarget = nil
                        ENV.ZHM_NPCBusy = false
                    end
                end

                if not currentTarget then
                    local target, liveCount = findNearestRunawayCustomer()
                    ENV.ZHM_NPCRunawayLiveCount = liveCount or 0
                    if target and isStillValidRunawayTarget(target) then
                        target.swingUntil = os.clock() + NPC_SWING_DURATION
                        currentTarget = target
                    end
                end

                local target = currentTarget
                if target and isStillValidRunawayTarget(target) then
                    -- Mark NPC movement ownership BEFORE teleporting so the rack-route
                    -- loop pauses instead of immediately overriding this CFrame.
                    ENV.ZHM_NPCBusy = ENV.ZHM_NPCAutoTP == true

                    local tpWorked = false
                    if ENV.ZHM_NPCAutoTP == true then
                        tpWorked = teleportToRunawayCustomer(target)
                    end

                    local remaining = math.max(0, (target.swingUntil or os.clock()) - os.clock())
                    ENV.ZHM_NPCStatus = "LIVE " .. tostring(ENV.ZHM_NPCRunawayLiveCount or 1) .. " • "
                        .. target.model.Name .. " > Head > RunawayExclam"
                        .. (ENV.ZHM_NPCAutoTP == true and (tpWorked and " • TP" or " • TP failed") or "")
                        .. " • swing " .. string.format("%.1f", remaining) .. "s"
                        .. " • " .. string.format("%.1f", target.zoneDistance or target.plotDistance or 0)
                        .. "/" .. tostring(NPC_ZONE_SCAN_RADIUS) .. " from OutsideWall/DisplayRack"
                else
                    ENV.ZHM_NPCBusy = false
                    local liveCount = ENV.ZHM_NPCRunawayLiveCount or 0
                    ENV.ZHM_NPCStatus = "LIVE scanner • " .. tostring(liveCount)
                        .. " RunawayExclam • Customer > Head > RunawayExclam • OutsideWall/DisplayRack"
                end
            else
                currentTarget = nil
                ENV.ZHM_NPCBusy = false
                ENV.ZHM_NPCStatus = ENV.ZHM_SweepActive == true and "Paused by sweep" or "OFF"
            end

            task.wait(NPC_SCAN_INTERVAL)
        end

        currentTarget = nil
        ENV.ZHM_NPCBusy = false
        ENV.ZHM_NPCStatus = "Stopped"
    end)

    task.spawn(function()
        while isCurrent() do
            if ENV.ZHM_NPCAutoSwing == true and ENV.ZHM_SweepActive ~= true then
                local target = currentTarget
                local myRoot = getPlayerRoot()

                if target
                    and myRoot
                    and os.clock() < (target.swingUntil or 0)
                    and isStillValidRunawayTarget(target) then

                    local distance = (myRoot.Position - target.root.Position).Magnitude
                    if distance <= NPC_SWING_MAX_DISTANCE then
                        local swung = swingRollingPinRobust()
                        if swung then
                            local remaining = math.max(0, (target.swingUntil or os.clock()) - os.clock())
                            ENV.ZHM_NPCStatus = "LIVE " .. tostring(ENV.ZHM_NPCRunawayLiveCount or 1) .. " • "
                                .. target.model.Name .. " > Head > RunawayExclam • swinging "
                                .. string.format("%.1f", remaining) .. "s"
                        end
                    end
                end
            end

            task.wait(NPC_SWING_INTERVAL)
        end
    end)
end

--------------------------------------------------------------------------------
-- 7. SMART POP-UP SUPPRESSOR
--------------------------------------------------------------------------------
local POPUP_KEYWORDS = {
    "bread slots", "fully stocked", "unlocked", "exp bar",
    "pesos reserved", "already baking", "display rack", "prep table", "tip jar"
}

local watchedLabels = setmetatable({}, {__mode = "k"})

local function shouldSuppressText(text)
    text = tostring(text or "")
    local lower = string.lower(text)
    for _, keyword in ipairs(POPUP_KEYWORDS) do
        if string.find(lower, keyword, 1, true) then return true end
    end
    return string.match(text, "%[X%d+%]") ~= nil
end

local function hideNotificationLabel(label)
    if not isCurrent() or not ENV.ZHM_HidePopups then return end
    if not label or not label:IsA("TextLabel") or not shouldSuppressText(label.Text) then return end

    pcall(function()
        if label.Parent and label.Parent:IsA("GuiObject") then
            label.Parent.Visible = false
        else
            label.Visible = false
        end
    end)
end

local function watchNotificationLabel(label)
    if not isCurrent() or not label or not label:IsA("TextLabel") or watchedLabels[label] then return end
    watchedLabels[label] = true
    hideNotificationLabel(label)
    label:GetPropertyChangedSignal("Text"):Connect(function() hideNotificationLabel(label) end)
end

for _, desc in ipairs(playerGui:GetDescendants()) do watchNotificationLabel(desc) end
playerGui.DescendantAdded:Connect(function(desc) if desc:IsA("TextLabel") then watchNotificationLabel(desc) end end)

--------------------------------------------------------------------------------
-- 8. SIMPLE / OPTIMIZED UI
--------------------------------------------------------------------------------
destroyNamedGui("ZHM_MasterUI")

-- Startup reset: clear stale runtime state first.
-- A saved config is auto-loaded below after the config loader is defined.
-- Instant Proximity is permanent and remains ON.
for _, featureKey in ipairs(ENV.ZHM_ConfigKeys or {}) do
    ENV[featureKey] = false
end
ENV.ZHM_AutoNearestPrompt = true
ENV.ZHM_FOVActive = false

-- Persistent config: saved settings auto-load on every execution when available.
ENV.ZHM_ConfigFile = "ZHM_HUB_config.json"
ENV.ZHM_ConfigStatus = "Checking saved config..."

ENV.ZHM_RefreshAllToggles = nil -- assigned after UI toggles are constructed

ENV.ZHM_SaveConfig = function()
    if type(writefile) ~= "function" then
        ENV.ZHM_ConfigStatus = "Save unavailable: writefile is not supported"
        return false
    end

    local data = {
        Version = 1,
        Features = {},
        FOV = tonumber(ENV.ZHM_FOV) or 70,
        FOVActive = ENV.ZHM_FOVActive == true,
    }

    for _, key in ipairs(ENV.ZHM_ConfigKeys or {}) do
        data.Features[key] = ENV[key] == true
    end

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then
        ENV.ZHM_ConfigStatus = "Save failed: JSON encode error"
        return false
    end

    local wrote, err = pcall(function()
        writefile(ENV.ZHM_ConfigFile, encoded)
    end)
    ENV.ZHM_ConfigStatus = wrote and "Config saved" or ("Save failed: " .. tostring(err))
    return wrote
end

ENV.ZHM_LoadConfig = function()
    if type(readfile) ~= "function" then
        ENV.ZHM_ConfigStatus = "Load unavailable: readfile is not supported"
        return false
    end

    if type(isfile) == "function" then
        local okFile, exists = pcall(isfile, ENV.ZHM_ConfigFile)
        if okFile and not exists then
            ENV.ZHM_ConfigStatus = "No saved config found"
            return false
        end
    end

    local okRead, raw = pcall(function()
        return readfile(ENV.ZHM_ConfigFile)
    end)
    if not okRead or type(raw) ~= "string" then
        ENV.ZHM_ConfigStatus = "No saved config found"
        return false
    end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not okDecode or type(data) ~= "table" then
        ENV.ZHM_ConfigStatus = "Load failed: invalid config"
        return false
    end

    -- Clear optional states first, then restore saved values.
    -- This loader is used both automatically on execute and by the LOAD CONFIG button.
    -- Instant Proximity is intentionally not part of the saved config.
    for _, key in ipairs(ENV.ZHM_ConfigKeys or {}) do
        ENV[key] = false
    end
    ENV.ZHM_AutoNearestPrompt = true

    if type(data.Features) == "table" then
        for _, key in ipairs(ENV.ZHM_ConfigKeys or {}) do
            ENV[key] = data.Features[key] == true
        end
    end
    ENV.ZHM_AutoNearestPrompt = true

    ENV.ZHM_FOVActive = false
    if data.FOVActive == true and tonumber(data.FOV) and ENV.ZHM_ApplyFOV then
        ENV.ZHM_ApplyFOV(tonumber(data.FOV))
    elseif tonumber(data.FOV) then
        ENV.ZHM_FOV = math.clamp(tonumber(data.FOV), 1, 120)
    end

    if type(ENV.ZHM_RefreshAllToggles) == "function" then
        pcall(ENV.ZHM_RefreshAllToggles)
    end
    if type(ENV.ZHM_RefreshFOVUI) == "function" then
        pcall(ENV.ZHM_RefreshFOVUI)
    end

    ENV.ZHM_ConfigStatus = "Config loaded"
    return true
end

-- AUTO LOAD SAVED CONFIG ON EXECUTE
-- If no config exists (or file APIs are unavailable), the hub safely keeps defaults OFF.
do
    local loaded = ENV.ZHM_LoadConfig()
    if loaded then
        ENV.ZHM_ConfigStatus = "Config auto-loaded on execute"
    end
end

ENV.ZHM_AllFeaturesOff = function()
    for _, key in ipairs(ENV.ZHM_ConfigKeys or {}) do
        ENV[key] = false
    end
    -- ALL OFF only disables optional features; Instant Proximity stays permanently enabled.
    ENV.ZHM_AutoNearestPrompt = true
    ENV.ZHM_FOVActive = false
    ENV.ZHM_NPCBusy = false
    ENV.ZHM_SweepActive = false

    if type(ENV.ZHM_RefreshAllToggles) == "function" then
        pcall(ENV.ZHM_RefreshAllToggles)
    end
    if type(ENV.ZHM_RefreshFOVUI) == "function" then
        pcall(ENV.ZHM_RefreshFOVUI)
    end

    ENV.ZHM_ConfigStatus = "Optional features disabled • Instant Proximity stays ON"
    return true
end

local UI_BG = Color3.fromRGB(18, 20, 25)
local UI_PANEL = Color3.fromRGB(25, 28, 34)
local UI_PANEL_2 = Color3.fromRGB(33, 37, 45)
local UI_ACCENT = Color3.fromRGB(75, 140, 255)
local UI_TEXT = Color3.fromRGB(242, 244, 248)
local UI_MUTED = Color3.fromRGB(145, 151, 163)
local UI_STROKE = Color3.fromRGB(53, 59, 70)
local UI_DANGER = Color3.fromRGB(235, 92, 92)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZHM_MasterUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 9999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mountGui(screenGui)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
-- Spawn the main hub on the LEFT side of the screen.
-- Keep a small 10 px margin while staying vertically centered.
mainFrame.AnchorPoint = Vector2.new(0, 0.5)
mainFrame.Size = UDim2.new(0, 340, 0, 390)
mainFrame.Position = UDim2.new(0, 10, 0.5, 0)
mainFrame.BackgroundColor3 = UI_BG
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
addCorner(mainFrame, 10)
addStroke(mainFrame, UI_STROKE, 1, 0.15)

local mainScale = Instance.new("UIScale")
mainScale.Scale = 1
mainScale.Parent = mainFrame
applyResponsiveScale(mainScale, 370, 430)

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = UI_PANEL
header.BorderSizePixel = 0
header.Parent = mainFrame
addCorner(header, 10)

local headerMask = Instance.new("Frame")
headerMask.Size = UDim2.new(1, 0, 0, 10)
headerMask.Position = UDim2.new(0, 0, 1, -10)
headerMask.BackgroundColor3 = UI_PANEL
headerMask.BorderSizePixel = 0
headerMask.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -92, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "ZHM HUB"
titleLabel.TextColor3 = UI_TEXT
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local minimizeBtn = Instance.new("TextButton")
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

closeBtn.Activated:Connect(function()
    screenGui:Destroy()
end)

makeDraggable(header, mainFrame)

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
local infoUpdaters = {}
local toggleRegistry = {}
local TAB_COUNT = 4

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
        button.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or UI_MUTED
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

local function createToggle(parent, title, description, envKey, defaultValue, masterKey)
    if ENV[envKey] == nil then ENV[envKey] = defaultValue == true end

    local row = Instance.new("Frame")
    row.Name = envKey
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

    local desc = nil
    if description then
        desc = Instance.new("TextLabel")
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
        local enabled = ENV[envKey] == true
        local masterEnabled = not masterKey or ENV[masterKey] == true

        switch.Text = enabled and "ON" or "OFF"
        switch.BackgroundColor3 = enabled and UI_ACCENT or UI_PANEL_2
        switch.TextColor3 = enabled and Color3.fromRGB(255, 255, 255) or UI_MUTED

        local disabledByMaster = masterKey and not masterEnabled
        row.BackgroundTransparency = disabledByMaster and 0.25 or 0
        label.TextTransparency = disabledByMaster and 0.35 or 0
        if desc then desc.TextTransparency = disabledByMaster and 0.45 or 0 end
        switch.BackgroundTransparency = disabledByMaster and 0.2 or 0
    end

    switch.Activated:Connect(function()
        ENV[envKey] = not (ENV[envKey] == true)
        refresh()
    end)

    refresh()
    local toggleObject = {Row = row, Refresh = refresh, Switch = switch}
    toggleRegistry[envKey] = toggleObject
    return toggleObject
end

local function createInfoCard(parent, title, getText, height)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, height or 62)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local titleLabel2 = Instance.new("TextLabel")
    titleLabel2.Size = UDim2.new(1, -20, 0, 17)
    titleLabel2.Position = UDim2.new(0, 10, 0, 7)
    titleLabel2.BackgroundTransparency = 1
    titleLabel2.Text = title
    titleLabel2.TextColor3 = UI_TEXT
    titleLabel2.Font = Enum.Font.GothamBold
    titleLabel2.TextSize = 9
    titleLabel2.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel2.Parent = card

    local value = Instance.new("TextLabel")
    value.Size = UDim2.new(1, -20, 1, -27)
    value.Position = UDim2.new(0, 10, 0, 24)
    value.BackgroundTransparency = 1
    value.Text = "Ready"
    value.TextColor3 = UI_MUTED
    value.Font = Enum.Font.Gotham
    value.TextSize = 8
    value.TextWrapped = true
    value.TextXAlignment = Enum.TextXAlignment.Left
    value.TextYAlignment = Enum.TextYAlignment.Top
    value.Parent = card

    infoUpdaters[#infoUpdaters + 1] = function()
        if not value.Parent then return end
        local ok, textValue = pcall(getText)
        if ok then value.Text = tostring(textValue or "Ready") end
    end

    return card
end

local farmPage = createPage("Farm")
local movePage = createPage("Movement")
local sidePage = createPage("SideJobs")
local extraPage = createPage("Extra")

local farmTab = createTab("Farm", "FARM")
local moveTab = createTab("Movement", "MOVE")
local sideTab = createTab("SideJobs", "SIDE")
local extraTab = createTab("Extra", "EXTRA")

farmTab.Activated:Connect(function() setActivePage("Farm") end)
moveTab.Activated:Connect(function() setActivePage("Movement") end)
sideTab.Activated:Connect(function() setActivePage("SideJobs") end)
extraTab.Activated:Connect(function() setActivePage("Extra") end)

createSection(farmPage, "Bakery Automation")
local masterFarmToggle = createToggle(farmPage, "Auto Farm", "Master bakery automation switch", "ZHM_AutoFarm", false)
local farmChildren = {
    createToggle(farmPage, "Auto Accept", "Accept customer orders", "ZHM_AutoAccept", false, "ZHM_AutoFarm"),
    createToggle(farmPage, "Prepare Dough", "Use prep table automatically", "ZHM_AutoPrepareDough", false, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Bake", "Controller-aware silent baking loop", "ZHM_AutoBake", false, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Collect", "Collect from every different BakingRack", "ZHM_AutoCollect", false, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Collect Tip", "Collect available money from the Tip Jar", "ZHM_AutoCollectTip", false, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Give Order", "Deliver finished orders at the DisplayRack", "ZHM_AutoGiveOrder", false, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Pay Cashier", "Automatically press the Bakery worker PaySalary button", "ZHM_AutoPayCashier", false, "ZHM_AutoFarm"),
    createToggle(farmPage, "Enable Breads", "Enable bread options", "ZHM_AutoEnableBreads", false, "ZHM_AutoFarm"),
}
masterFarmToggle.Switch.Activated:Connect(function()
    task.defer(function()
        for _, toggleObj in ipairs(farmChildren) do
            toggleObj.Refresh()
        end
    end)
end)
createInfoCard(farmPage, "Bakery Status", function()
    return "Farm: " .. (ENV.ZHM_AutoFarm and "Enabled" or "Disabled")
        .. "\nBuy: " .. (ENV.ZHM_AutoBuy and "Enabled" or "Disabled")
        .. "\nUpgrade: " .. (ENV.ZHM_AutoUpgrade and "Enabled" or "Disabled")
end, 66)

createSection(movePage, "Movement")
local rackMovementToggle = createToggle(movePage, "Auto Rack Movement", "Instant TP between baking racks and display rack", "ZHM_AutoWalk", false)
createToggle(movePage, "BakingRack Scanner", "Live scan racks, prompts and click detectors", "ZHM_BakingRackScanner", false)
createToggle(movePage, "Expand BakingRack Prompts", "1000-stud range • clickable • no line-of-sight • instant hold", "ZHM_ExpandBakingRackPrompts", false)
createToggle(movePage, "DisplayRack Prompt Spam", "Fire enabled prompts around DisplayRack while rack movement is active", "ZHM_SpamDisplayRackPrompts", false)
createInfoCard(movePage, "Instant Proximity", function()
    return "Always ON • instant prompt hold + nearest prompt automation"
end, 52)
createInfoCard(movePage, "BakingRack Live Scanner", function()
    return tostring(ENV.ZHM_BakingRackStatus or "Scanning BakingRacks...")
end, 76)
createInfoCard(movePage, "Live Movement", function()
    if ENV.ZHM_SweepActive then
        return "Sweep active • rack paused • instant prompts ACTIVE"
    elseif ENV.ZHM_NPCBusy then
        return "NPC TP active • rack movement paused"
    elseif ENV.ZHM_AutoWalk then
        return "Rack TP active • 1s delay • DisplayRack 10s • PrepTable loop"
    end
    return "Movement idle"
end, 56)

-- Automatically disable Rack Movement for the entire night, not only while trash exists.
-- Restore the exact state the user had before night when day returns.
local rackStateBeforeNight = nil
local rackNightLock = false

local function guiVisibleForNightCheck(obj)
    if not obj or not obj:IsA("GuiObject") or not obj.Visible then return false end
    local current = obj.Parent
    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        current = current.Parent
    end
    return true
end

local function detectNightForRack()
    local weatherUI = playerGui:FindFirstChild("WeatherUI")
    local frame = weatherUI and weatherUI:FindFirstChild("Frame")
    if not frame then return false end

    local night = frame:FindFirstChild("Night")
    local day = frame:FindFirstChild("Day")

    if night and guiVisibleForNightCheck(night) then return true end
    if day and guiVisibleForNightCheck(day) then return false end

    for _, obj in ipairs(frame:GetDescendants()) do
        local lower = obj.Name:lower()
        if lower == "night" and guiVisibleForNightCheck(obj) then
            return true
        elseif lower == "day" and guiVisibleForNightCheck(obj) then
            return false
        end
    end

    return false
end

task.spawn(function()
    while isCurrent() do
        local nightNow = detectNightForRack()
        local nightSweepOwnsMovement = nightNow and ENV.ZHM_AutoSweep == true

        -- No feature is auto-enabled here. Night coordination only pauses/restores
        -- rack movement after the user has explicitly enabled Night Auto Sweep.
        if nightSweepOwnsMovement and not rackNightLock then
            rackNightLock = true
            rackStateBeforeNight = ENV.ZHM_AutoWalk == true
            ENV.ZHM_AutoWalk = false
            rackMovementToggle.Refresh()
            report("AutoWalk", "Night Auto Sweep active • Rack Movement paused")
        elseif not nightSweepOwnsMovement and rackNightLock then
            rackNightLock = false
            ENV.ZHM_AutoWalk = rackStateBeforeNight == true
            rackStateBeforeNight = nil
            rackMovementToggle.Refresh()
            report("AutoWalk", ENV.ZHM_AutoWalk and "Rack Movement restored ON" or "Rack Movement remains OFF")
        elseif nightSweepOwnsMovement and ENV.ZHM_AutoWalk == true then
            ENV.ZHM_AutoWalk = false
            rackMovementToggle.Refresh()
        end

        task.wait(0.25)
    end
end)

createSection(sidePage, "Side Jobs")
createToggle(sidePage, "Night Auto Sweep", "Sweep trash prompts at night", "ZHM_AutoSweep", false)
createToggle(sidePage, "NPC Auto TP", "LIVE scanner • OutsideWall/DisplayRack • Customer > Head > RunawayExclam • TP", "ZHM_NPCAutoTP", false)
createToggle(sidePage, "Rolling Pin Swing", "Customer > Head > RunawayExclam • auto swing for 3 seconds • live scan", "ZHM_NPCAutoSwing", false)
createInfoCard(sidePage, "Live Scanner", function()
    return "Sweep: " .. tostring(ENV.ZHM_SweepStatus or "Waiting")
        .. "\nNPC: " .. tostring(ENV.ZHM_NPCStatus or "Idle")
end, 64)

createSection(extraPage, "Extra Automation")
createToggle(extraPage, "Auto Buy All Market", "Buy all GUI Market items + world Buy prompts", "ZHM_AutoBuy", false)
createToggle(extraPage, "Auto Buy Baking Rack", "Dynamic my-plot BakingRack 1-100 spam every 0.1s • no TP", "ZHM_AutoBuyBakingRack", false)
createInfoCard(extraPage, "Baking Rack Buyer", function()
    return tostring(ENV.ZHM_BuyBakingRackStatus or "Auto Buy Baking Rack disabled")
end, 54)
createToggle(extraPage, "Auto Upgrade", "Upgrade bakery items", "ZHM_AutoUpgrade", false)
createToggle(extraPage, "Hide Popups", "Suppress known notifications", "ZHM_HidePopups", false)
createToggle(extraPage, "NPC Hitbox", "Expand NPC HumanoidRootPart hitbox to 8 x 6 x 8", "ZHM_NPCHitbox", false)
createToggle(extraPage, "NPC Hitbox ESP", "Transparent hitbox ESP • requires NPC Hitbox", "ZHM_NPCHitboxESP", false, "ZHM_NPCHitbox")

createSection(extraPage, "Camera / FOV")

-- Build the FOV changer inside the existing ZHM UI.
-- Kept inside its own function so the large hub does not approach Luau's local-register limit.
ENV.ZHM_BuildFOVControl = function(parent)
    local card = Instance.new("Frame")
    card.Name = "FOVControl"
    card.Size = UDim2.new(1, 0, 0, 126)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.55, 0, 0, 20)
    label.Position = UDim2.new(0, 10, 0, 7)
    label.BackgroundTransparency = 1
    label.Text = "Field of View"
    label.TextColor3 = UI_TEXT
    label.Font = Enum.Font.GothamBold
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local current = Instance.new("TextLabel")
    current.Size = UDim2.new(0.45, -10, 0, 20)
    current.Position = UDim2.new(0.55, 0, 0, 7)
    current.BackgroundTransparency = 1
    current.Text = "Current: " .. tostring(ENV.ZHM_FOV or 120)
    current.TextColor3 = UI_MUTED
    current.Font = Enum.Font.Gotham
    current.TextSize = 8
    current.TextXAlignment = Enum.TextXAlignment.Right
    current.Parent = card

    local input = Instance.new("TextBox")
    input.Name = "FOVInput"
    input.Size = UDim2.new(1, -100, 0, 30)
    input.Position = UDim2.new(0, 10, 0, 32)
    input.BackgroundColor3 = UI_PANEL_2
    input.BorderSizePixel = 0
    input.ClearTextOnFocus = false
    input.PlaceholderText = "FOV 1-120"
    input.Text = tostring(ENV.ZHM_FOV or 120)
    input.TextColor3 = UI_TEXT
    input.PlaceholderColor3 = UI_MUTED
    input.Font = Enum.Font.GothamMedium
    input.TextSize = 10
    input.Parent = card
    addCorner(input, 7)

    local apply = Instance.new("TextButton")
    apply.Name = "ApplyFOV"
    apply.Size = UDim2.new(0, 74, 0, 30)
    apply.Position = UDim2.new(1, -84, 0, 32)
    apply.BackgroundColor3 = UI_ACCENT
    apply.BorderSizePixel = 0
    apply.Text = "APPLY"
    apply.TextColor3 = Color3.fromRGB(255, 255, 255)
    apply.Font = Enum.Font.GothamBold
    apply.TextSize = 9
    apply.Parent = card
    addCorner(apply, 7)

    local quickLabel = Instance.new("TextLabel")
    quickLabel.Size = UDim2.new(1, -20, 0, 16)
    quickLabel.Position = UDim2.new(0, 10, 0, 67)
    quickLabel.BackgroundTransparency = 1
    quickLabel.Text = "Quick Select"
    quickLabel.TextColor3 = UI_MUTED
    quickLabel.Font = Enum.Font.GothamBold
    quickLabel.TextSize = 8
    quickLabel.TextXAlignment = Enum.TextXAlignment.Left
    quickLabel.Parent = card

    local quickHolder = Instance.new("Frame")
    quickHolder.Size = UDim2.new(1, -20, 0, 30)
    quickHolder.Position = UDim2.new(0, 10, 0, 87)
    quickHolder.BackgroundTransparency = 1
    quickHolder.Parent = card

    local quickLayout = Instance.new("UIListLayout")
    quickLayout.FillDirection = Enum.FillDirection.Horizontal
    quickLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    quickLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    quickLayout.Padding = UDim.new(0, 4)
    quickLayout.Parent = quickHolder

    ENV.ZHM_RefreshFOVUI = function()
        input.Text = tostring(math.floor((tonumber(ENV.ZHM_FOV) or 70) + 0.5))
        current.Text = (ENV.ZHM_FOVActive == true and "Current: " or "Saved: ") .. tostring(math.floor((tonumber(ENV.ZHM_FOV) or 70) + 0.5))
        for _, child in ipairs(quickHolder:GetChildren()) do
            if child:IsA("TextButton") then
                child.BackgroundColor3 = tonumber(child.Text) == tonumber(ENV.ZHM_FOV) and UI_ACCENT or UI_PANEL_2
            end
        end
    end

    local function setFOV(value)
        value = tonumber(value)
        if not value or value < 1 or value > 120 then
            input.Text = "1-120 only"
            return
        end

        if ENV.ZHM_ApplyFOV and ENV.ZHM_ApplyFOV(value) then
            ENV.ZHM_RefreshFOVUI()
        end
    end

    apply.Activated:Connect(function()
        setFOV(input.Text)
    end)

    input.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            setFOV(input.Text)
        end
    end)

    for _, value in ipairs({70, 80, 90, 100, 110, 120}) do
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, 45, 0, 26)
        button.BackgroundColor3 = value == ENV.ZHM_FOV and UI_ACCENT or UI_PANEL_2
        button.BorderSizePixel = 0
        button.Text = tostring(value)
        button.TextColor3 = UI_TEXT
        button.Font = Enum.Font.GothamBold
        button.TextSize = 8
        button.Parent = quickHolder
        addCorner(button, 6)

        button.Activated:Connect(function()
            setFOV(value)
            for _, child in ipairs(quickHolder:GetChildren()) do
                if child:IsA("TextButton") then
                    child.BackgroundColor3 = tonumber(child.Text) == value and UI_ACCENT or UI_PANEL_2
                end
            end
        end)
    end

    return card
end

ENV.ZHM_BuildFOVControl(extraPage)
ENV.ZHM_BuildFOVControl = nil

ENV.ZHM_RefreshAllToggles = function()
    for _, toggleObject in pairs(toggleRegistry) do
        if toggleObject and type(toggleObject.Refresh) == "function" then
            toggleObject.Refresh()
        end
    end
end

createSection(extraPage, "Configuration")
do
    local card = Instance.new("Frame")
    card.Name = "ConfigControl"
    card.Size = UDim2.new(1, 0, 0, 92)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.Parent = extraPage
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 24)
    status.Position = UDim2.new(0, 10, 0, 8)
    status.BackgroundTransparency = 1
    status.Text = tostring(ENV.ZHM_ConfigStatus)
    status.TextColor3 = UI_MUTED
    status.Font = Enum.Font.Gotham
    status.TextSize = 8
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = card

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -20, 0, 36)
    holder.Position = UDim2.new(0, 10, 0, 44)
    holder.BackgroundTransparency = 1
    holder.Parent = card

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 6)
    layout.Parent = holder

    local function configButton(textValue, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, 92, 0, 32)
        button.BackgroundColor3 = UI_PANEL_2
        button.BorderSizePixel = 0
        button.Text = textValue
        button.TextColor3 = UI_TEXT
        button.Font = Enum.Font.GothamBold
        button.TextSize = 8
        button.Parent = holder
        addCorner(button, 7)
        button.Activated:Connect(function()
            callback()
            status.Text = tostring(ENV.ZHM_ConfigStatus or "Ready")
        end)
        return button
    end

    configButton("SAVE CONFIG", function() ENV.ZHM_SaveConfig() end)
    configButton("LOAD CONFIG", function() ENV.ZHM_LoadConfig() end)
    configButton("ALL OFF", function() ENV.ZHM_AllFeaturesOff() end)

    infoUpdaters[#infoUpdaters + 1] = function()
        if status.Parent then
            status.Text = tostring(ENV.ZHM_ConfigStatus or "Ready")
        end
    end
end

createInfoCard(extraPage, "Status", function()
    local latestFeature, latestMessage
    for feature, message in pairs(ENV.ZHM_FeatureStatus) do
        latestFeature = feature
        latestMessage = message
    end
    if latestFeature and latestMessage then
        return tostring(latestFeature) .. ": " .. tostring(latestMessage)
    end
    return "Ready"
end, 58)

-- One shared status refresh loop instead of one loop per card.
task.spawn(function()
    while isCurrent() and screenGui.Parent do
        for _, updater in ipairs(infoUpdaters) do
            updater()
        end
        task.wait(0.5)
    end
end)

-- Simple compact mode. No tweens, shadows, pulsing, or animated gradients.
local minimized = false
local expandedSize = mainFrame.Size
local expandedPosition = mainFrame.Position

local miniButton = Instance.new("TextButton")
miniButton.Name = "MiniButton"
-- Match the main frame anchor so minimizing/restoring does not shift horizontally.
miniButton.AnchorPoint = Vector2.new(0, 0.5)
miniButton.Size = UDim2.new(0, 46, 0, 46)
miniButton.Position = expandedPosition
miniButton.BackgroundColor3 = UI_PANEL
miniButton.BorderSizePixel = 0
miniButton.Text = "Z"
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

minimizeBtn.Activated:Connect(function()
    setMinimized(true)
end)

miniButton.Activated:Connect(function()
    setMinimized(false)
end)

setActivePage("Farm")
startAutomation()

task.delay(0.45, function()
    if screenGui and screenGui.Parent and not minimized then
        setMinimized(true)
    end
end)

print("[ZHM Simple UI] Loaded: optimized UI + existing automation")
end -- MAIN ZHM SCOPE

--// ==================== MERGED: STABLE NPC HITBOX + ESP ====================
--// =========================================================
--// STABLE NPC HITBOX EXPANDER + TRANSPARENT ESP
--// NPC ONLY
--// Reduced physics interference
--// =========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer


--// STOP OLD VERSION
if getgenv().StableNPCHitbox then
    getgenv().StableNPCHitbox.Enabled = false
end

task.wait(0.15)


--// =========================================================
--// CONFIG
--// =========================================================

local Config = {
    -- Controller remains alive so the UI can enable/disable the feature at runtime.
    Enabled = true,

    -- Smaller and safer
    HitboxSize = Vector3.new(8, 6, 8),

    -- How often new NPCs are detected
    ScanDelay = 0.75,

    -- How often we verify that the server
    -- hasn't reset the hitbox
    VerifyDelay = 1,

    ESP = false,

    -- Nearly invisible ESP
    ESPTransparency = 0.94,

    StatusUI = true
}

getgenv().StableNPCHitbox = Config


--// =========================================================
--// STATE
--// =========================================================

local NPCs = {}
local Modified = {}
local Visuals = {}

local LastScan = 0
local LastVerify = 0

local NPCCount = 0
local ActiveCount = 0


--// =========================================================
--// VISUAL FOLDER
--// =========================================================

local oldFolder =
    CoreGui:FindFirstChild("StableNPCHitboxVisuals")

if oldFolder then
    oldFolder:Destroy()
end


local VisualFolder = Instance.new("Folder")
VisualFolder.Name = "StableNPCHitboxVisuals"
VisualFolder.Parent = CoreGui


--// =========================================================
--// UI
--// =========================================================

local GUI = Instance.new("ScreenGui")
GUI.Name = "StableNPCHitboxUI"
GUI.ResetOnSpawn = false
GUI.Enabled = false
GUI.Parent = CoreGui


local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 235, 0, 90)
Frame.Position = UDim2.new(0, 10, 0, 10)

Frame.BackgroundColor3 =
    Color3.fromRGB(12, 14, 18)

Frame.BackgroundTransparency = 0.15
Frame.BorderSizePixel = 0
Frame.Parent = GUI


local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Frame


local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(70, 230, 140)
Stroke.Transparency = 0.4
Stroke.Thickness = 1
Stroke.Parent = Frame


local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -14, 1, -10)
Status.Position = UDim2.new(0, 7, 0, 5)

Status.BackgroundTransparency = 1

Status.Font = Enum.Font.GothamMedium
Status.TextSize = 12

Status.TextColor3 =
    Color3.fromRGB(255, 255, 255)

Status.TextXAlignment =
    Enum.TextXAlignment.Left

Status.TextYAlignment =
    Enum.TextYAlignment.Top

Status.Parent = Frame


--// =========================================================
--// HELPERS
--// =========================================================

local function IsPlayerCharacter(model)

    return model
        and Players:GetPlayerFromCharacter(model) ~= nil
end


local function GetHumanoid(model)

    if not model then
        return nil
    end

    return model:FindFirstChildWhichIsA("Humanoid")
end


local function GetRoot(model)

    if not model then
        return nil
    end


    local root =
        model:FindFirstChild("HumanoidRootPart")

    if root and root:IsA("BasePart") then
        return root
    end


    return nil
end


--// =========================================================
--// NPC SCAN
--// =========================================================

local function ScanNPCs()

    local found = {}

    local myCharacter =
        LocalPlayer.Character


    for _, object in ipairs(
        workspace:GetDescendants()
    ) do

        if object:IsA("Model")
            and object ~= myCharacter
            and not IsPlayerCharacter(object)
        then

            local humanoid =
                GetHumanoid(object)

            local root =
                GetRoot(object)


            if humanoid
                and root
                and humanoid.Health > 0
            then

                table.insert(found, object)
            end
        end
    end


    NPCs = found
    NPCCount = #found
end


--// =========================================================
--// SAVE ORIGINAL
--// =========================================================

local function SaveOriginal(part)

    if Modified[part] then
        return
    end


    Modified[part] = {
        Size = part.Size,

        CanCollide =
            part.CanCollide,

        CanTouch =
            part.CanTouch,

        CanQuery =
            part.CanQuery
    }
end


--// =========================================================
--// ESP
--// =========================================================

local function RemoveESP(npc)

    local visual = Visuals[npc]

    if visual then

        pcall(function()
            visual:Destroy()
        end)

        Visuals[npc] = nil
    end
end


local function UpdateESP(npc, root)

    if not Config.ESP then
        RemoveESP(npc)
        return
    end


    local visual =
        Visuals[npc]


    if not visual then

        visual =
            Instance.new("BoxHandleAdornment")

        visual.Name =
            "NPCHitboxESP"

        visual.AlwaysOnTop =
            true

        visual.ZIndex =
            5

        visual.Color3 =
            Color3.fromRGB(
                70,
                230,
                140
            )

        visual.Transparency =
            Config.ESPTransparency

        visual.Parent =
            VisualFolder


        Visuals[npc] =
            visual
    end


    visual.Adornee = root

    visual.Size =
        Config.HitboxSize

    visual.Transparency =
        Config.ESPTransparency
end


--// =========================================================
--// APPLY HITBOX
--// =========================================================

local function ApplyHitbox(npc)

    local root =
        GetRoot(npc)


    if not root then
        return false
    end


    SaveOriginal(root)


    -- Only write properties if needed.
    -- This avoids constantly fighting the NPC physics.
    pcall(function()

        if root.Size ~= Config.HitboxSize then
            root.Size = Config.HitboxSize
        end


        if root.CanCollide ~= false then
            root.CanCollide = false
        end


        if root.CanTouch ~= true then
            root.CanTouch = true
        end


        if root.CanQuery ~= true then
            root.CanQuery = true
        end

    end)


    UpdateESP(
        npc,
        root
    )


    return true
end


--// =========================================================
--// RESTORE
--// =========================================================

local function RestorePart(part)

    local original =
        Modified[part]


    if not original then
        return
    end


    if part.Parent then

        pcall(function()

            part.Size =
                original.Size

            part.CanCollide =
                original.CanCollide

            part.CanTouch =
                original.CanTouch

            part.CanQuery =
                original.CanQuery

        end)
    end


    Modified[part] =
        nil
end


--// =========================================================
--// INITIAL STATE
--// =========================================================
-- No NPC scan happens until NPC Hitbox is enabled from ZHM HUB.


--// =========================================================
--// MAIN LOOP
--// =========================================================

task.spawn(function()

    local wasFeatureEnabled = false

    local function ClearHitboxChanges()
        for part in pairs(Modified) do
            RestorePart(part)
        end

        for npc in pairs(Visuals) do
            RemoveESP(npc)
        end

        NPCs = {}
        NPCCount = 0
        ActiveCount = 0
    end

    while Config.Enabled do

        local featureEnabled = ENV.ZHM_NPCHitbox == true
        Config.ESP = featureEnabled and ENV.ZHM_NPCHitboxESP == true
        GUI.Enabled = featureEnabled and Config.StatusUI == true

        if not featureEnabled then
            if wasFeatureEnabled then
                ClearHitboxChanges()
            end

            wasFeatureEnabled = false
            RunService.Heartbeat:Wait()
            continue
        end

        if not wasFeatureEnabled then
            LastScan = 0
            LastVerify = 0
            ScanNPCs()
        end
        wasFeatureEnabled = true

        local now = tick()

        -- Find newly spawned NPCs only while the feature is enabled.
        if now - LastScan >= Config.ScanDelay then
            ScanNPCs()
            LastScan = now
        end

        ActiveCount = 0

        -- Only verify hitbox properties roughly once per second.
        if now - LastVerify >= Config.VerifyDelay then
            for _, npc in ipairs(NPCs) do
                if npc
                    and npc.Parent
                    and not IsPlayerCharacter(npc)
                then
                    local humanoid = GetHumanoid(npc)
                    local root = GetRoot(npc)

                    if humanoid
                        and humanoid.Health > 0
                        and root
                    then
                        if ApplyHitbox(npc) then
                            ActiveCount += 1
                        end
                    end
                end
            end

            LastVerify = now
        else
            for _, npc in ipairs(NPCs) do
                local humanoid = npc and GetHumanoid(npc)
                local root = npc and GetRoot(npc)

                if npc
                    and npc.Parent
                    and humanoid
                    and humanoid.Health > 0
                    and root
                then
                    ActiveCount += 1
                end
            end
        end

        -- Cleanup destroyed / dead NPCs.
        for part in pairs(Modified) do
            if not part.Parent then
                Modified[part] = nil
            else
                local npc = part:FindFirstAncestorWhichIsA("Model")
                local humanoid = npc and GetHumanoid(npc)

                if not npc
                    or IsPlayerCharacter(npc)
                    or not humanoid
                    or humanoid.Health <= 0
                then
                    if npc then
                        RemoveESP(npc)
                    end
                    RestorePart(part)
                end
            end
        end

        for npc in pairs(Visuals) do
            if not npc.Parent
                or IsPlayerCharacter(npc)
                or not Config.ESP
            then
                RemoveESP(npc)
            end
        end

        Status.Text =
            "NPC HITBOX: " .. (featureEnabled and "ON" or "OFF") .. "\n"
            .. "NPCs: " .. tostring(NPCCount)
            .. " | Active: " .. tostring(ActiveCount)
            .. "\nHitbox: 8 x 6 x 8"
            .. "\nESP: " .. (Config.ESP and "ON (94% transparent)" or "OFF")

        RunService.Heartbeat:Wait()
    end

    ClearHitboxChanges()

    pcall(function()
        GUI:Destroy()
    end)

    pcall(function()
        VisualFolder:Destroy()
    end)

end)
