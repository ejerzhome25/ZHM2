
                local target = currentTarget
                local myRoot = getPlayerRoot()

                if target and myRoot and isStillValidRunningTarget(target) then
                    local distance = (myRoot.Position - target.root.Position).Magnitude
                    if distance <= NPC_SWING_MAX_DISTANCE then
                        clickGameplayToSwing()
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

-- Keep every feature enabled on execute.
for _, featureKey in ipairs({
    "ZHM_AutoWalk",
    "ZHM_AutoFarm",
    "ZHM_AutoBuy",
    "ZHM_AutoUpgrade",
    "ZHM_AutoAccept",
    "ZHM_AutoPrepareDough",
    "ZHM_AutoBake",
    "ZHM_AutoCollect",
    "ZHM_AutoCollectTip",
    "ZHM_AutoGiveOrder",
    "ZHM_AutoEnableBreads",
    "ZHM_HidePopups",
    "ZHM_AutoSweep",
    "ZHM_NPCAutoSwing",
}) do
    ENV[featureKey] = true
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
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Size = UDim2.new(0, 340, 0, 390)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
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
    return {Row = row, Refresh = refresh, Switch = switch}
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
local masterFarmToggle = createToggle(farmPage, "Auto Farm", "Master bakery automation switch", "ZHM_AutoFarm", true)
local farmChildren = {
    createToggle(farmPage, "Auto Accept", "Accept customer orders", "ZHM_AutoAccept", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Prepare Dough", "Use prep table automatically", "ZHM_AutoPrepareDough", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Bake", "Bake available bread", "ZHM_AutoBake", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Collect", "Collect from every different BakingRack", "ZHM_AutoCollect", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Collect Tip", "Collect available money from the Tip Jar", "ZHM_AutoCollectTip", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Give Order", "Deliver finished orders at the DisplayRack", "ZHM_AutoGiveOrder", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Enable Breads", "Enable bread options", "ZHM_AutoEnableBreads", true, "ZHM_AutoFarm"),
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
local rackMovementToggle = createToggle(movePage, "Auto Rack Movement", "Visit baking racks and display rack", "ZHM_AutoWalk", true)
createInfoCard(movePage, "Live Movement", function()
    if ENV.ZHM_SweepActive then
        return "Sweep active • rack/NPC movement paused"
    elseif ENV.ZHM_NPCBusy then
        return "NPC TP active • rack movement paused"
    elseif ENV.ZHM_AutoWalk then
        return "Rack route active • 28 studs/sec"
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

        if nightNow and not rackNightLock then
            rackNightLock = true
            rackStateBeforeNight = ENV.ZHM_AutoWalk == true
            ENV.ZHM_AutoWalk = false
            rackMovementToggle.Refresh()
            report("AutoWalk", "Night detected • Rack Movement automatically OFF")
        elseif not nightNow and rackNightLock then
            rackNightLock = false
            ENV.ZHM_AutoWalk = rackStateBeforeNight == true
            rackStateBeforeNight = nil
            rackMovementToggle.Refresh()
            report("AutoWalk", ENV.ZHM_AutoWalk and "Day detected • Rack Movement restored ON" or "Day detected • Rack Movement remains OFF")
        elseif nightNow and ENV.ZHM_AutoWalk == true then
            ENV.ZHM_AutoWalk = false
            rackMovementToggle.Refresh()
        end

        task.wait(0.25)
    end
end)

createSection(sidePage, "Side Jobs")
createToggle(sidePage, "Night Auto Sweep", "Sweep trash prompts at night", "ZHM_AutoSweep", true)
createToggle(sidePage, "Rolling Pin Swing", "Auto-equip and swing at detected moving NPCs (12-16 studs/sec)", "ZHM_NPCAutoSwing", true)
createInfoCard(sidePage, "Live Scanner", function()
    return "Sweep: " .. tostring(ENV.ZHM_SweepStatus or "Waiting")
        .. "\nNPC: " .. tostring(ENV.ZHM_NPCStatus or "Idle")
end, 64)

createSection(extraPage, "Extra Automation")
createToggle(extraPage, "Auto Buy All Market", "Buy all GUI Market items + world Buy prompts", "ZHM_AutoBuy", true)
createToggle(extraPage, "Auto Upgrade", "Upgrade bakery items", "ZHM_AutoUpgrade", true)
createToggle(extraPage, "Hide Popups", "Suppress known notifications", "ZHM_HidePopups", true)
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
miniButton.AnchorPoint = Vector2.new(0.5, 0.5)
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
