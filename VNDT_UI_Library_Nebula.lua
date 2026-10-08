--[[
    VNDT UI Library — ALIEN CORE EDITION
    Dark bio-tech / alien interface
    No background image dependency
    Mobile-first, responsive, readable, reusable
    Version: 6.0-alien
]]

local VNDT = {}
VNDT.__index = VNDT

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local Theme = {
    Background = Color3.fromRGB(9, 12, 13),
    Background2 = Color3.fromRGB(13, 17, 18),
    Surface = Color3.fromRGB(18, 23, 24),
    Surface2 = Color3.fromRGB(24, 31, 31),
    Surface3 = Color3.fromRGB(31, 40, 39),
    Surface4 = Color3.fromRGB(41, 52, 49),

    Stroke = Color3.fromRGB(59, 78, 73),
    StrokeSoft = Color3.fromRGB(43, 58, 55),

    Text = Color3.fromRGB(252, 255, 253),
    Muted = Color3.fromRGB(215, 226, 222),
    Muted2 = Color3.fromRGB(166, 186, 178),

    Accent = Color3.fromRGB(102, 255, 143),
    Accent2 = Color3.fromRGB(45, 230, 196),
    Accent3 = Color3.fromRGB(190, 255, 89),

    Success = Color3.fromRGB(105, 255, 154),
    Danger = Color3.fromRGB(255, 91, 113),
    Warning = Color3.fromRGB(255, 205, 92),
}

local function New(className, props)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        if key ~= "Parent" then
            object[key] = value
        end
    end
    if props and props.Parent then
        object.Parent = props.Parent
    end
    return object
end

local function Corner(parent, radius)
    return New("UICorner", {
        CornerRadius = UDim.new(0, radius or 12),
        Parent = parent,
    })
end

local function Stroke(parent, color, thickness, transparency)
    return New("UIStroke", {
        Color = color or Theme.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function Gradient(parent, colors, rotation, transparency)
    local gradient = New("UIGradient", {
        Rotation = rotation or 0,
        Parent = parent,
    })

    if typeof(colors) == "ColorSequence" then
        gradient.Color = colors
    elseif type(colors) == "table" and #colors >= 2 then
        local points = {}
        for index, color in ipairs(colors) do
            table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
        end
        gradient.Color = ColorSequence.new(points)
    end

    if transparency then
        gradient.Transparency = transparency
    end

    return gradient
end

local function Padding(parent, left, right, top, bottom)
    return New("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or top or 0),
        Parent = parent,
    })
end

local function Tween(object, goal, duration, style, direction)
    if not object or not object.Parent then
        return nil
    end

    local tween = TweenService:Create(
        object,
        TweenInfo.new(
            duration or 0.16,
            style or Enum.EasingStyle.Quad,
            direction or Enum.EasingDirection.Out
        ),
        goal
    )
    tween:Play()
    return tween
end

local function LoopTween(object, duration, goal, reverses)
    if not object then return nil end

    local tween = TweenService:Create(
        object,
        TweenInfo.new(
            duration,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,
            reverses == true
        ),
        goal
    )
    tween:Play()
    return tween
end

local function Label(parent, text, size, color, font)
    return New("TextLabel", {
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = color or Theme.Text,
        TextSize = size or 14,
        Font = font or Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTransparency = 0,
        Parent = parent,
    })
end

local function Button(parent, props)
    props = props or {}
    props.Parent = parent
    props.AutoButtonColor = false
    props.Text = props.Text or ""
    return New("TextButton", props)
end

local function GetGuiParent()
    local ok, result = pcall(function()
        if gethui then
            return gethui()
        end
        return game:GetService("CoreGui")
    end)

    if ok and result then
        return result
    end

    if LocalPlayer then
        return LocalPlayer:WaitForChild("PlayerGui")
    end

    return game:GetService("CoreGui")
end

local function SetCanvas(scroller, layout, extra)
    local function update()
        scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + (extra or 12))
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
    update()
end

local function CreateDragger(handle, target, clampCallback)
    local dragging = false
    local dragStart
    local startPosition
    local activeInput

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = target.Position
            activeInput = input

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if clampCallback then
                        task.defer(clampCallback)
                    end
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end

        if input == activeInput
        or input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
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

local function CreateRow(parent, height)
    local row = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height or 52),
        ClipsDescendants = true,
        Parent = parent,
    })
    Corner(row, 15)

    local rowStroke = Stroke(row, Theme.StrokeSoft, 1, 0.08)

    Gradient(
        row,
        {
            Color3.fromRGB(23, 29, 29),
            Theme.Surface,
            Color3.fromRGB(16, 21, 22),
        },
        90
    )

    local energy = New("Frame", {
        BackgroundColor3 = Theme.Accent2,
        BackgroundTransparency = 0.88,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(3, height or 52),
        Parent = row,
    })
    Corner(energy, 999)
    Gradient(energy, {Theme.Accent3, Theme.Accent2}, 90)

    return row, rowStroke, energy
end

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

function VNDT:SetTheme(partial)
    for key, value in pairs(partial or {}) do
        if Theme[key] ~= nil then
            Theme[key] = value
        end
    end
end

function VNDT:GetTheme()
    return Theme
end

function VNDT:CreateWindow(config)
    config = config or {}

    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

    local width = config.Width or 620
    local height = config.Height or 430

    if isMobile then
        width = math.floor(math.min(config.MobileWidth or 520, math.max(300, viewport.X - 16)))
        height = math.floor(math.min(config.MobileHeight or 390, math.max(300, viewport.Y - 20)))
    end

    local gui = New("ScreenGui", {
        Name = "VNDT_Alien_" .. HttpService:GenerateGUID(false),
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = GetGuiParent(),
    })

    local shadow = New("ImageLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width + 34, height + 34),
        Image = "rbxassetid://1316045217",
        ImageColor3 = Color3.fromRGB(0, 0, 0),
        ImageTransparency = 0.48,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(10, 10, 118, 118),
        Parent = gui,
    })

    local main = New("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = gui,
    })
    Corner(main, 22)
    local mainStroke = Stroke(main, Theme.Accent2, 1.25, 0.54)

    Gradient(
        main,
        {
            Color3.fromRGB(14, 18, 19),
            Theme.Background,
            Color3.fromRGB(7, 10, 11),
        },
        120
    )

    -- Static alien glow zones. No image assets.
    local glowTopRight = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, 40, 0, -25),
        Size = UDim2.fromOffset(320, 250),
        BackgroundColor3 = Theme.Accent2,
        BackgroundTransparency = 0.90,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = main,
    })
    Corner(glowTopRight, 999)

    Gradient(
        glowTopRight,
        {Theme.Accent2, Theme.Accent, Color3.fromRGB(10, 15, 15)},
        45,
        NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.72),
            NumberSequenceKeypoint.new(0.55, 0.90),
            NumberSequenceKeypoint.new(1, 1),
        })
    )

    local glowBottomLeft = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, -30, 1, 35),
        Size = UDim2.fromOffset(280, 220),
        BackgroundColor3 = Theme.Accent3,
        BackgroundTransparency = 0.94,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = main,
    })
    Corner(glowBottomLeft, 999)

    -- Alien grid / circuit accents.
    local gridLayer = New("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 0,
        Parent = main,
    })

    for i = 1, 7 do
        local line = New("Frame", {
            BackgroundColor3 = Theme.Accent2,
            BackgroundTransparency = 0.955,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, i / 8, 0),
            Size = UDim2.new(1, 0, 0, 1),
            ZIndex = 0,
            Parent = gridLayer,
        })
        if i % 2 == 0 then
            line.BackgroundColor3 = Theme.Accent3
        end
    end

    for i = 1, 9 do
        local line = New("Frame", {
            BackgroundColor3 = Theme.Accent2,
            BackgroundTransparency = 0.97,
            BorderSizePixel = 0,
            Position = UDim2.new(i / 10, 0, 0, 0),
            Size = UDim2.new(0, 1, 1, 0),
            ZIndex = 0,
            Parent = gridLayer,
        })
        if i % 3 == 0 then
            line.BackgroundColor3 = Theme.Accent3
        end
    end

    -- Moving scan beam.
    local scanBeam = New("Frame", {
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, -26),
        Size = UDim2.new(1, 0, 0, 26),
        ZIndex = 1,
        Parent = main,
    })

    Gradient(
        scanBeam,
        {Theme.Accent2, Theme.Accent3, Theme.Accent2},
        0,
        NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.48, 0.72),
            NumberSequenceKeypoint.new(0.52, 0.72),
            NumberSequenceKeypoint.new(1, 1),
        })
    )

    local scanTween = TweenService:Create(
        scanBeam,
        TweenInfo.new(7.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false, 1.2),
        {Position = UDim2.new(0, 0, 1, 10)}
    )
    scanTween:Play()

    -- Animated top energy rail.
    local rail = New("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 3),
        ZIndex = 5,
        Parent = main,
    })
    local railGradient = Gradient(
        rail,
        {Theme.Accent3, Theme.Accent, Theme.Accent2, Theme.Accent3},
        0
    )
    LoopTween(railGradient, 5.5, {Rotation = 360}, false)

    local topHeight = isMobile and 60 or 66

    local topbar = New("Frame", {
        Name = "Topbar",
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, topHeight),
        ZIndex = 4,
        Parent = main,
    })

    Gradient(
        topbar,
        {
            Color3.fromRGB(24, 31, 31),
            Theme.Surface,
            Color3.fromRGB(15, 20, 21),
        },
        90
    )

    New("Frame", {
        BackgroundColor3 = Theme.Accent2,
        BackgroundTransparency = 0.78,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
        ZIndex = 5,
        Parent = topbar,
    })

    local emblem = New("Frame", {
        Position = UDim2.fromOffset(15, isMobile and 11 or 13),
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        ZIndex = 6,
        Parent = topbar,
    })
    Corner(emblem, 10)
    Stroke(emblem, Theme.Accent2, 1, 0.28)
    Gradient(emblem, {Theme.Surface4, Theme.Surface2}, 90)

    local emblemText = Label(emblem, "⌬", 20, Theme.Accent, Enum.Font.GothamBold)
    emblemText.Size = UDim2.fromScale(1, 1)
    emblemText.TextXAlignment = Enum.TextXAlignment.Center
    emblemText.ZIndex = 7

    local title = Label(topbar, config.Name or "VNDT", isMobile and 17 or 18, Theme.Text, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(58, isMobile and 7 or 10)
    title.Size = UDim2.new(1, -170, 0, 25)
    title.ZIndex = 6

    local subtitle = Label(
        topbar,
        config.Subtitle or "ALIEN CORE // ONLINE",
        11,
        Theme.Muted,
        Enum.Font.GothamBold
    )
    subtitle.Position = UDim2.fromOffset(58, isMobile and 31 or 36)
    subtitle.Size = UDim2.new(1, -170, 0, 17)
    subtitle.ZIndex = 6

    local liveDot = New("Frame", {
        BackgroundColor3 = Theme.Success,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 58, 1, -8),
        Size = UDim2.fromOffset(5, 5),
        ZIndex = 7,
        Parent = topbar,
    })
    Corner(liveDot, 999)

    local dotScale = New("UIScale", {
        Scale = 1,
        Parent = liveDot,
    })
    LoopTween(dotScale, 1.4, {Scale = 1.55}, true)

    local function CreateTopButton(symbol, xOffset, danger)
        local button = Button(topbar, {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, xOffset, 0.5, 0),
            Size = UDim2.fromOffset(isMobile and 40 or 38, isMobile and 40 or 38),
            BackgroundColor3 = Theme.Surface2,
            Text = symbol,
            TextColor3 = Theme.Text,
            TextSize = 17,
            Font = Enum.Font.GothamBold,
            ZIndex = 6,
        })
        Corner(button, 12)
        local border = Stroke(button, danger and Theme.Danger or Theme.Stroke, 1, 0.30)
        Gradient(button, {Theme.Surface3, Theme.Surface2}, 90)

        button.MouseEnter:Connect(function()
            Tween(button, {
                BackgroundColor3 = danger and Color3.fromRGB(75, 31, 38) or Theme.Surface4,
            }, 0.12)
            Tween(border, {
                Transparency = 0.04,
                Color = danger and Theme.Danger or Theme.Accent2,
            }, 0.12)
        end)

        button.MouseLeave:Connect(function()
            Tween(button, {BackgroundColor3 = Theme.Surface2}, 0.12)
            Tween(border, {
                Transparency = 0.30,
                Color = danger and Theme.Danger or Theme.Stroke,
            }, 0.12)
        end)

        return button
    end

    local minimize = CreateTopButton("—", -58, false)
    local close = CreateTopButton("×", -14, true)

    local mobileTabHeight = isMobile and 54 or 0
    local sidebarWidth = isMobile and 0 or 170

    local sidebar = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, topHeight),
        Size = isMobile
            and UDim2.new(1, 0, 0, mobileTabHeight)
            or UDim2.new(0, sidebarWidth, 1, -topHeight),
        ZIndex = 3,
        Parent = main,
    })

    Gradient(
        sidebar,
        {Color3.fromRGB(20, 26, 26), Theme.Surface, Color3.fromRGB(13, 18, 18)},
        isMobile and 0 or 90
    )

    local tabList = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = isMobile and UDim2.fromOffset(8, 5) or UDim2.fromOffset(10, 10),
        Size = isMobile and UDim2.new(1, -16, 1, -10) or UDim2.new(1, -20, 1, -20),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = isMobile and 0 or 3,
        ScrollBarImageColor3 = Theme.Accent2,
        ScrollingDirection = isMobile and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ZIndex = 4,
        Parent = sidebar,
    })

    local tabLayout = New("UIListLayout", {
        FillDirection = isMobile and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabList,
    })

    if isMobile then
        local function updateTabCanvas()
            tabList.CanvasSize = UDim2.fromOffset(tabLayout.AbsoluteContentSize.X + 8, 0)
        end
        tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateTabCanvas)
        updateTabCanvas()
    else
        SetCanvas(tabList, tabLayout, 8)
    end

    local pages = New("Frame", {
        BackgroundTransparency = 1,
        Position = isMobile
            and UDim2.fromOffset(0, topHeight + mobileTabHeight)
            or UDim2.fromOffset(sidebarWidth, topHeight),
        Size = isMobile
            and UDim2.new(1, 0, 1, -topHeight - mobileTabHeight)
            or UDim2.new(1, -sidebarWidth, 1, -topHeight),
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = main,
    })

    -- Alien floating restore core.
    local orb = Button(gui, {
        Name = "VNDT_AlienCore",
        Position = UDim2.fromOffset(18, 78),
        Size = UDim2.fromOffset(isMobile and 66 or 62, isMobile and 66 or 62),
        BackgroundColor3 = Theme.Surface2,
        Text = "",
        Visible = false,
        ZIndex = 999,
        Active = true,
    })
    Corner(orb, 999)
    local orbStroke = Stroke(orb, Theme.Accent2, 2, 0.12)

    local orbGradient = Gradient(
        orb,
        {Color3.fromRGB(31, 47, 43), Theme.Surface2, Color3.fromRGB(17, 26, 25)},
        45
    )

    local orbRing = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -10, 1, -10),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.88,
        BorderSizePixel = 0,
        ZIndex = 1000,
        Parent = orb,
    })
    Corner(orbRing, 999)
    local ringStroke = Stroke(orbRing, Theme.Accent, 1.5, 0.22)
    Gradient(orbRing, {Theme.Accent3, Theme.Accent2}, 45)

    local orbCore = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(isMobile and 29 or 27, isMobile and 29 or 27),
        BackgroundColor3 = Theme.Accent2,
        BorderSizePixel = 0,
        ZIndex = 1001,
        Parent = orb,
    })
    Corner(orbCore, 999)
    Gradient(orbCore, {Theme.Accent3, Theme.Accent, Theme.Accent2}, 45)

    local coreText = Label(orbCore, "V", 15, Color3.fromRGB(4, 15, 12), Enum.Font.GothamBold)
    coreText.Size = UDim2.fromScale(1, 1)
    coreText.TextXAlignment = Enum.TextXAlignment.Center
    coreText.ZIndex = 1002

    local orbScale = New("UIScale", {
        Scale = 1,
        Parent = orb,
    })

    LoopTween(orbScale, 1.8, {Scale = 1.055}, true)
    LoopTween(orbStroke, 2.2, {Transparency = 0.52}, true)
    LoopTween(ringStroke, 1.6, {Transparency = 0.62}, true)
    LoopTween(orbGradient, 6.0, {Rotation = 405}, false)

    local function ClampMain()
        local cam = workspace.CurrentCamera
        if not cam then return end

        local vp = cam.ViewportSize
        local absolute = main.AbsoluteSize
        local pos = main.AbsolutePosition

        local x = math.clamp(pos.X, 6, math.max(6, vp.X - absolute.X - 6))
        local y = math.clamp(pos.Y, 6, math.max(6, vp.Y - absolute.Y - 6))

        main.AnchorPoint = Vector2.new(0, 0)
        main.Position = UDim2.fromOffset(x, y)
        shadow.AnchorPoint = Vector2.new(0, 0)
        shadow.Position = UDim2.fromOffset(x - 17, y - 17)
    end

    local function ClampOrb()
        local cam = workspace.CurrentCamera
        if not cam then return end

        local vp = cam.ViewportSize
        local size = orb.AbsoluteSize
        local pos = orb.AbsolutePosition

        orb.Position = UDim2.fromOffset(
            math.clamp(pos.X, 8, math.max(8, vp.X - size.X - 8)),
            math.clamp(pos.Y, 8, math.max(8, vp.Y - size.Y - 8))
        )
    end

    local self = setmetatable({
        Gui = gui,
        Main = main,
        Shadow = shadow,
        Topbar = topbar,
        Sidebar = sidebar,
        TabList = tabList,
        Pages = pages,
        Tabs = {},
        SelectedTab = nil,
        Minimized = false,
        Orb = orb,
        Mobile = isMobile,
        Effects = {
            ScanTween = scanTween,
        },
    }, Window)

    CreateDragger(topbar, main, ClampMain)

    local orbDragging = false
    local orbMoved = false
    local orbStart
    local orbStartPosition

    orb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            orbDragging = true
            orbMoved = false
            orbStart = input.Position
            orbStartPosition = orb.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    orbDragging = false
                    task.defer(ClampOrb)
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not orbDragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - orbStart
        if delta.Magnitude > 5 then
            orbMoved = true
        end

        orb.Position = UDim2.new(
            orbStartPosition.X.Scale,
            orbStartPosition.X.Offset + delta.X,
            orbStartPosition.Y.Scale,
            orbStartPosition.Y.Offset + delta.Y
        )
    end)

    local function SetMinimized(state)
        self.Minimized = state == true

        if self.Minimized then
            main.Visible = false
            shadow.Visible = false
            orb.Visible = true
            ClampOrb()
        else
            orb.Visible = false
            main.Visible = true
            shadow.Visible = true

            main.BackgroundTransparency = 0.12
            Tween(main, {BackgroundTransparency = 0}, 0.16)
            Tween(mainStroke, {Transparency = 0.40}, 0.16)
            task.delay(0.18, function()
                if mainStroke.Parent then
                    Tween(mainStroke, {Transparency = 0.54}, 0.22)
                end
            end)
        end
    end

    minimize.MouseButton1Click:Connect(function()
        SetMinimized(true)
    end)

    orb.MouseButton1Click:Connect(function()
        if orbMoved then
            orbMoved = false
            return
        end
        SetMinimized(false)
    end)

    close.MouseButton1Click:Connect(function()
        if self.Effects.ScanTween then
            self.Effects.ScanTween:Cancel()
        end

        Tween(main, {
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(math.floor(main.AbsoluteSize.X * 0.96), math.floor(main.AbsoluteSize.Y * 0.96)),
        }, 0.14)

        Tween(shadow, {ImageTransparency = 1}, 0.14)
        orb.Visible = false

        task.delay(0.16, function()
            if gui then
                gui:Destroy()
            end
        end)
    end)

    -- Responsive mobile orientation handling.
    if camera and isMobile then
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if not gui.Parent then return end

            local vp = camera.ViewportSize
            local newWidth = math.floor(math.min(config.MobileWidth or 520, math.max(300, vp.X - 16)))
            local newHeight = math.floor(math.min(config.MobileHeight or 390, math.max(300, vp.Y - 20)))

            main.AnchorPoint = Vector2.new(0.5, 0.5)
            main.Position = UDim2.fromScale(0.5, 0.5)
            main.Size = UDim2.fromOffset(newWidth, newHeight)

            shadow.AnchorPoint = Vector2.new(0.5, 0.5)
            shadow.Position = UDim2.fromScale(0.5, 0.5)
            shadow.Size = UDim2.fromOffset(newWidth + 34, newHeight + 34)

            ClampOrb()
        end)
    end

    return self
end

function Window:CreateTab(name)
    local isMobile = self.Mobile

    local tabButton = Button(self.TabList, {
        Size = isMobile and UDim2.fromOffset(118, 42) or UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Theme.Surface,
        Text = "",
        LayoutOrder = #self.Tabs + 1,
        ZIndex = 5,
    })
    Corner(tabButton, 13)

    local tabStroke = Stroke(tabButton, Theme.StrokeSoft, 1, 0.18)
    Gradient(tabButton, {Theme.Surface2, Theme.Surface}, 90)

    local indicator = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(4, 22),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 6,
        Parent = tabButton,
    })
    Corner(indicator, 999)
    Gradient(indicator, {Theme.Accent3, Theme.Accent2}, 90)

    local text = Label(tabButton, name or "Tab", 13, Theme.Muted, Enum.Font.GothamBold)
    text.Position = UDim2.fromOffset(14, 0)
    text.Size = UDim2.new(1, -20, 1, 0)
    text.TextTruncate = Enum.TextTruncate.AtEnd
    text.ZIndex = 6

    local page = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = isMobile and 7 or 3,
        ScrollBarImageColor3 = Theme.Accent2,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        Visible = false,
        ZIndex = 3,
        Parent = self.Pages,
    })

    Padding(page, isMobile and 12 or 16, isMobile and 12 or 16, 14, 14)

    local layout = New("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = page,
    })
    SetCanvas(page, layout, 22)

    local tab = setmetatable({
        Window = self,
        Button = tabButton,
        Stroke = tabStroke,
        Indicator = indicator,
        Text = text,
        Page = page,
        Layout = layout,
    }, Tab)

    table.insert(self.Tabs, tab)

    tabButton.MouseButton1Click:Connect(function()
        self:SelectTab(tab)
    end)

    tabButton.MouseEnter:Connect(function()
        if self.SelectedTab ~= tab then
            Tween(tabButton, {BackgroundColor3 = Theme.Surface3}, 0.12)
            Tween(tabStroke, {Color = Theme.Accent2, Transparency = 0.42}, 0.12)
            Tween(text, {TextColor3 = Theme.Text}, 0.12)
        end
    end)

    tabButton.MouseLeave:Connect(function()
        if self.SelectedTab ~= tab then
            Tween(tabButton, {BackgroundColor3 = Theme.Surface}, 0.12)
            Tween(tabStroke, {Color = Theme.StrokeSoft, Transparency = 0.18}, 0.12)
            Tween(text, {TextColor3 = Theme.Muted}, 0.12)
        end
    end)

    if not self.SelectedTab then
        self:SelectTab(tab)
    end

    return tab
end

function Window:SelectTab(tab)
    self.SelectedTab = tab

    for _, current in ipairs(self.Tabs) do
        local selected = current == tab
        current.Page.Visible = selected

        Tween(current.Button, {
            BackgroundColor3 = selected and Theme.Surface3 or Theme.Surface,
        }, 0.14)

        Tween(current.Text, {
            TextColor3 = selected and Theme.Text or Theme.Muted,
        }, 0.14)

        Tween(current.Indicator, {
            BackgroundTransparency = selected and 0 or 1,
        }, 0.14)

        Tween(current.Stroke, {
            Color = selected and Theme.Accent2 or Theme.StrokeSoft,
            Transparency = selected and 0.18 or 0.18,
        }, 0.14)
    end
end

function Window:Notify(config)
    config = config or {}

    local holder = self.Gui:FindFirstChild("VNDT_AlienNotifications")

    if not holder then
        holder = New("Frame", {
            Name = "VNDT_AlienNotifications",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -12, 1, -12),
            Size = UDim2.fromOffset(318, 320),
            ZIndex = 1100,
            Parent = self.Gui,
        })

        New("UIListLayout", {
            Padding = UDim.new(0, 8),
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = holder,
        })
    end

    local card = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(304, 82),
        BackgroundTransparency = 0.03,
        ZIndex = 1101,
        Parent = holder,
    })
    Corner(card, 15)
    local cardStroke = Stroke(card, Theme.Accent2, 1, 0.32)

    Gradient(
        card,
        {Color3.fromRGB(28, 36, 35), Theme.Surface, Color3.fromRGB(15, 20, 20)},
        90
    )

    local rail = New("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 4, 1, 0),
        ZIndex = 1102,
        Parent = card,
    })
    Corner(rail, 999)
    Gradient(rail, {Theme.Accent3, Theme.Accent2}, 90)

    local glyph = Label(card, "⌬", 17, Theme.Accent, Enum.Font.GothamBold)
    glyph.Position = UDim2.fromOffset(16, 8)
    glyph.Size = UDim2.fromOffset(24, 22)
    glyph.ZIndex = 1102

    local title = Label(card, config.Title or "VNDT", 13, Theme.Text, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(42, 8)
    title.Size = UDim2.new(1, -54, 0, 22)
    title.ZIndex = 1102

    local content = Label(card, config.Content or "", 12, Theme.Muted, Enum.Font.GothamBold)
    content.Position = UDim2.fromOffset(16, 32)
    content.Size = UDim2.new(1, -30, 0, 34)
    content.TextWrapped = true
    content.TextYAlignment = Enum.TextYAlignment.Top
    content.ZIndex = 1102

    local progress = New("Frame", {
        BackgroundColor3 = Theme.Accent2,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 5, 1, -3),
        Size = UDim2.new(1, -10, 0, 2),
        ZIndex = 1103,
        Parent = card,
    })
    Corner(progress, 999)
    Gradient(progress, {Theme.Accent3, Theme.Accent2}, 0)

    local duration = config.Duration or 3
    progress.Size = UDim2.new(1, -10, 0, 2)
    Tween(progress, {Size = UDim2.new(0, 0, 0, 2)}, duration, Enum.EasingStyle.Linear)

    Tween(cardStroke, {Transparency = 0.08}, 0.18)
    task.delay(0.35, function()
        if cardStroke.Parent then
            Tween(cardStroke, {Transparency = 0.32}, 0.25)
        end
    end)

    task.delay(duration, function()
        if not card.Parent then return end

        Tween(card, {BackgroundTransparency = 1}, 0.18)
        Tween(title, {TextTransparency = 1}, 0.18)
        Tween(content, {TextTransparency = 1}, 0.18)
        Tween(glyph, {TextTransparency = 1}, 0.18)

        task.delay(0.20, function()
            if card then
                card:Destroy()
            end
        end)
    end)
end

function Window:SetVisible(state)
    self.Gui.Enabled = state == true
end

function Window:Destroy()
    if self.Gui then
        self.Gui:Destroy()
    end
end

function Tab:CreateSection(text)
    local holder = New("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 26),
        Parent = self.Page,
    })

    local line = New("Frame", {
        BackgroundColor3 = Theme.StrokeSoft,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0.5, 7),
        Size = UDim2.new(1, 0, 0, 1),
        Parent = holder,
    })

    Gradient(line, {Theme.Accent2, Theme.StrokeSoft, Theme.StrokeSoft}, 0)

    local chip = New("Frame", {
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(190, 23),
        Parent = holder,
    })
    Corner(chip, 999)

    local glyph = Label(chip, "⌁", 13, Theme.Accent2, Enum.Font.GothamBold)
    glyph.Position = UDim2.fromOffset(3, 0)
    glyph.Size = UDim2.fromOffset(18, 23)

    local title = Label(chip, string.upper(text or "SECTION"), 11, Theme.Text, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(22, 0)
    title.Size = UDim2.new(1, -24, 1, 0)

    return holder
end

function Tab:CreateLabel(text)
    local row = CreateRow(self.Page, 46)

    local content = Label(row, text or "Label", 13, Theme.Muted, Enum.Font.GothamBold)
    content.Position = UDim2.fromOffset(15, 0)
    content.Size = UDim2.new(1, -30, 1, 0)
    content.TextTruncate = Enum.TextTruncate.AtEnd

    local api = {}

    function api:Set(value)
        content.Text = tostring(value)
    end

    function api:Get()
        return content.Text
    end

    return api
end

function Tab:CreateButton(config)
    config = config or {}
    local hasDescription = type(config.Description) == "string" and config.Description ~= ""

    local row, rowStroke, energy = CreateRow(self.Page, hasDescription and 64 or 52)

    local title = Label(row, config.Name or "Button", 13, Theme.Text, Enum.Font.GothamBold)
    title.Position = hasDescription and UDim2.fromOffset(15, 7) or UDim2.fromOffset(15, 0)
    title.Size = hasDescription and UDim2.new(1, -60, 0, 23) or UDim2.new(1, -60, 1, 0)

    local description
    if hasDescription then
        description = Label(row, config.Description, 11, Theme.Muted, Enum.Font.GothamBold)
        description.Position = UDim2.fromOffset(15, 32)
        description.Size = UDim2.new(1, -60, 0, 18)
        description.TextTruncate = Enum.TextTruncate.AtEnd
    end

    local action = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -13, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row,
    })
    Corner(action, 10)
    Stroke(action, Theme.Stroke, 1, 0.26)

    local arrow = Label(action, "›", 18, Theme.Accent2, Enum.Font.GothamBold)
    arrow.Size = UDim2.fromScale(1, 1)
    arrow.TextXAlignment = Enum.TextXAlignment.Center

    local hit = Button(row, {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
    })

    hit.MouseEnter:Connect(function()
        Tween(row, {BackgroundColor3 = Theme.Surface2}, 0.12)
        Tween(rowStroke, {Color = Theme.Accent2, Transparency = 0.28}, 0.12)
        Tween(energy, {BackgroundTransparency = 0.28}, 0.12)
        Tween(action, {BackgroundColor3 = Theme.Surface4}, 0.12)
    end)

    hit.MouseLeave:Connect(function()
        Tween(row, {BackgroundColor3 = Theme.Surface}, 0.12)
        Tween(rowStroke, {Color = Theme.StrokeSoft, Transparency = 0.08}, 0.12)
        Tween(energy, {BackgroundTransparency = 0.88}, 0.12)
        Tween(action, {BackgroundColor3 = Theme.Surface3}, 0.12)
    end)

    hit.MouseButton1Click:Connect(function()
        Tween(action, {Size = UDim2.fromOffset(24, 24)}, 0.08)
        task.delay(0.08, function()
            if action.Parent then
                Tween(action, {Size = UDim2.fromOffset(28, 28)}, 0.10)
            end
        end)

        if config.Callback then
            task.spawn(config.Callback)
        end
    end)

    local api = {}

    function api:SetName(value)
        title.Text = tostring(value)
    end

    function api:SetDescription(value)
        if description then
            description.Text = tostring(value or "")
        end
    end

    return api
end

function Tab:CreateToggle(config)
    config = config or {}

    local value = config.Default == true
    local hasDescription = type(config.Description) == "string" and config.Description ~= ""

    local row, rowStroke, energy = CreateRow(self.Page, hasDescription and 66 or 54)

    local title = Label(row, config.Name or "Toggle", 13, Theme.Text, Enum.Font.GothamBold)
    title.Position = hasDescription and UDim2.fromOffset(15, 7) or UDim2.fromOffset(15, 0)
    title.Size = hasDescription and UDim2.new(1, -88, 0, 23) or UDim2.new(1, -88, 1, 0)

    local description
    if hasDescription then
        description = Label(row, config.Description, 11, Theme.Muted, Enum.Font.GothamBold)
        description.Position = UDim2.fromOffset(15, 33)
        description.Size = UDim2.new(1, -88, 0, 18)
        description.TextTruncate = Enum.TextTruncate.AtEnd
    end

    local track = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(50, 28),
        BackgroundColor3 = value and Theme.Accent2 or Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row,
    })
    Corner(track, 999)
    local trackStroke = Stroke(track, value and Theme.Accent or Theme.Stroke, 1, value and 0.10 or 0.30)

    local trackGradient = Gradient(
        track,
        value and {Theme.Accent3, Theme.Accent2} or {Theme.Surface4, Theme.Surface3},
        0
    )

    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = value and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 14, 0.5, 0),
        Size = UDim2.fromOffset(21, 21),
        BackgroundColor3 = value and Color3.fromRGB(9, 24, 18) or Color3.fromRGB(240, 245, 242),
        BorderSizePixel = 0,
        Parent = track,
    })
    Corner(knob, 999)

    local core = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = value and Theme.Accent3 or Theme.Stroke,
        BorderSizePixel = 0,
        Parent = knob,
    })
    Corner(core, 999)

    local api = {}

    local function render(fire)
        Tween(track, {
            BackgroundColor3 = value and Theme.Accent2 or Theme.Surface3,
        }, 0.15)

        Tween(trackStroke, {
            Color = value and Theme.Accent or Theme.Stroke,
            Transparency = value and 0.10 or 0.30,
        }, 0.15)

        Tween(knob, {
            Position = value and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 14, 0.5, 0),
            BackgroundColor3 = value and Color3.fromRGB(9, 24, 18) or Color3.fromRGB(240, 245, 242),
        }, 0.15)

        Tween(core, {
            BackgroundColor3 = value and Theme.Accent3 or Theme.Stroke,
        }, 0.15)

        trackGradient.Color = value
            and ColorSequence.new(Theme.Accent3, Theme.Accent2)
            or ColorSequence.new(Theme.Surface4, Theme.Surface3)

        Tween(energy, {
            BackgroundTransparency = value and 0.42 or 0.88,
        }, 0.15)

        if fire and config.Callback then
            task.spawn(config.Callback, value)
        end
    end

    local hit = Button(row, {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
    })

    hit.MouseEnter:Connect(function()
        Tween(row, {BackgroundColor3 = Theme.Surface2}, 0.12)
        Tween(rowStroke, {Color = Theme.Accent2, Transparency = 0.38}, 0.12)
    end)

    hit.MouseLeave:Connect(function()
        Tween(row, {BackgroundColor3 = Theme.Surface}, 0.12)
        Tween(rowStroke, {Color = Theme.StrokeSoft, Transparency = 0.08}, 0.12)
    end)

    hit.MouseButton1Click:Connect(function()
        value = not value
        render(true)
    end)

    function api:Set(newValue)
        value = newValue == true
        render(true)
    end

    function api:Get()
        return value
    end

    function api:SetDescription(newValue)
        if description then
            description.Text = tostring(newValue or "")
        end
    end

    render(false)
    return api
end

function Tab:CreateSlider(config)
    config = config or {}

    local minimum = config.Min or 0
    local maximum = config.Max or 100
    local increment = config.Increment or 1
    local value = math.clamp(config.Default or minimum, minimum, maximum)

    local row, rowStroke, energy = CreateRow(self.Page, 80)

    local title = Label(row, config.Name or "Slider", 13, Theme.Text, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(15, 8)
    title.Size = UDim2.new(1, -102, 0, 23)

    local valueChip = New("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 8),
        Size = UDim2.fromOffset(78, 24),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row,
    })
    Corner(valueChip, 999)
    Stroke(valueChip, Theme.Stroke, 1, 0.28)
    Gradient(valueChip, {Theme.Surface4, Theme.Surface3}, 0)

    local valueText = Label(valueChip, "", 11, Theme.Accent3, Enum.Font.GothamBold)
    valueText.Size = UDim2.fromScale(1, 1)
    valueText.TextXAlignment = Enum.TextXAlignment.Center

    local hitArea = New("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 42),
        Size = UDim2.new(1, -28, 0, 30),
        Parent = row,
    })

    local bar = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 8),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = hitArea,
    })
    Corner(bar, 999)

    local fill = New("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = bar,
    })
    Corner(fill, 999)
    Gradient(fill, {Theme.Accent3, Theme.Accent, Theme.Accent2}, 0)

    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(17, 17),
        BackgroundColor3 = Color3.fromRGB(13, 28, 22),
        BorderSizePixel = 0,
        Parent = bar,
    })
    Corner(knob, 999)
    Stroke(knob, Theme.Accent, 2, 0.10)

    local dragging = false
    local api = {}

    local function setValue(newValue, fire)
        newValue = math.clamp(newValue, minimum, maximum)
        newValue = math.floor((newValue / increment) + 0.5) * increment
        newValue = math.clamp(newValue, minimum, maximum)
        value = newValue

        local alpha = (value - minimum) / math.max(maximum - minimum, 1)
        fill.Size = UDim2.fromScale(alpha, 1)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueText.Text = tostring(value) .. (config.Suffix or "")

        if fire and config.Callback then
            task.spawn(config.Callback, value)
        end
    end

    local function setFromX(x)
        local alpha = math.clamp(
            (x - hitArea.AbsolutePosition.X) / math.max(1, hitArea.AbsoluteSize.X),
            0,
            1
        )

        setValue(minimum + (maximum - minimum) * alpha, true)
    end

    hitArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            Tween(energy, {BackgroundTransparency = 0.28}, 0.10)
            Tween(rowStroke, {Color = Theme.Accent2, Transparency = 0.26}, 0.10)
            setFromX(input.Position.X)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            setFromX(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                Tween(energy, {BackgroundTransparency = 0.88}, 0.12)
                Tween(rowStroke, {Color = Theme.StrokeSoft, Transparency = 0.08}, 0.12)
            end
        end
    end)

    function api:Set(newValue)
        setValue(tonumber(newValue) or minimum, true)
    end

    function api:Get()
        return value
    end

    setValue(value, false)
    return api
end

function Tab:CreateInput(config)
    config = config or {}

    local row, rowStroke, energy = CreateRow(self.Page, 60)

    local title = Label(row, config.Name or "Input", 13, Theme.Text, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(15, 0)
    title.Size = UDim2.new(0.36, 0, 1, 0)

    local holder = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.new(0.60, 0, 0, 36),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Parent = row,
    })
    Corner(holder, 11)

    local holderStroke = Stroke(holder, Theme.Stroke, 1, 0.24)
    Gradient(holder, {Theme.Surface3, Theme.Surface2}, 90)

    local box = New("TextBox", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(11, 0),
        Size = UDim2.new(1, -22, 1, 0),
        ClearTextOnFocus = false,
        Text = tostring(config.Default or ""),
        PlaceholderText = config.Placeholder or "Type...",
        PlaceholderColor3 = Theme.Muted2,
        TextColor3 = Theme.Text,
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })

    box.Focused:Connect(function()
        Tween(holder, {BackgroundColor3 = Theme.Surface3}, 0.12)
        Tween(holderStroke, {Color = Theme.Accent2, Transparency = 0.12}, 0.12)
        Tween(rowStroke, {Color = Theme.Accent2, Transparency = 0.34}, 0.12)
        Tween(energy, {BackgroundTransparency = 0.30}, 0.12)
    end)

    box.FocusLost:Connect(function(enterPressed)
        Tween(holder, {BackgroundColor3 = Theme.Surface2}, 0.12)
        Tween(holderStroke, {Color = Theme.Stroke, Transparency = 0.24}, 0.12)
        Tween(rowStroke, {Color = Theme.StrokeSoft, Transparency = 0.08}, 0.12)
        Tween(energy, {BackgroundTransparency = 0.88}, 0.12)

        if config.Callback then
            task.spawn(config.Callback, box.Text, enterPressed)
        end
    end)

    local api = {}

    function api:Set(value)
        box.Text = tostring(value)
        if config.Callback then
            task.spawn(config.Callback, box.Text, false)
        end
    end

    function api:Get()
        return box.Text
    end

    return api
end

function Tab:CreateDropdown(config)
    config = config or {}

    local options = config.Options or {}
    local selected = config.Default
    local opened = false
    local closedHeight = 60

    local holder, holderStroke, energy = CreateRow(self.Page, closedHeight)
    holder.ClipsDescendants = true

    local header = Button(holder, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, closedHeight),
    })

    local title = Label(header, config.Name or "Dropdown", 13, Theme.Text, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(15, 0)
    title.Size = UDim2.new(0.40, 0, 1, 0)

    local chip = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -39, 0.5, 0),
        Size = UDim2.fromOffset(188, 34),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = header,
    })
    Corner(chip, 999)
    local chipStroke = Stroke(chip, Theme.Stroke, 1, 0.24)
    Gradient(chip, {Theme.Surface4, Theme.Surface3}, 0)

    local summary = Label(
        chip,
        selected and tostring(selected) or (config.Placeholder or "Select"),
        12,
        selected and Theme.Text or Theme.Muted,
        Enum.Font.GothamBold
    )
    summary.Position = UDim2.fromOffset(12, 0)
    summary.Size = UDim2.new(1, -38, 1, 0)
    summary.TextTruncate = Enum.TextTruncate.AtEnd

    local arrow = Label(chip, "⌄", 14, Theme.Accent2, Enum.Font.GothamBold)
    arrow.AnchorPoint = Vector2.new(1, 0.5)
    arrow.Position = UDim2.new(1, -10, 0.5, 0)
    arrow.Size = UDim2.fromOffset(16, 16)
    arrow.TextXAlignment = Enum.TextXAlignment.Center

    local list = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, closedHeight),
        Size = UDim2.new(1, -20, 0, 0),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = self.Window.Mobile and 7 or 4,
        ScrollBarImageColor3 = Theme.Accent2,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        Parent = holder,
    })

    local listLayout = New("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })
    SetCanvas(list, listLayout, 4)

    local optionObjects = {}
    local api = {}

    local function updateVisuals()
        summary.Text = selected and tostring(selected) or (config.Placeholder or "Select")
        summary.TextColor3 = selected and Theme.Text or Theme.Muted

        for option, data in pairs(optionObjects) do
            local active = option == selected
            data.button.BackgroundColor3 = active and Theme.Surface4 or Theme.Surface2
            data.text.TextColor3 = active and Theme.Accent3 or Theme.Text
            data.marker.BackgroundTransparency = active and 0 or 1
        end
    end

    local function choose(value, fire)
        selected = value
        updateVisuals()

        if fire and config.Callback then
            task.spawn(config.Callback, selected)
        end
    end

    local function close()
        opened = false
        Tween(holder, {Size = UDim2.new(1, 0, 0, closedHeight)}, 0.16)
        Tween(arrow, {Rotation = 0}, 0.16)
        Tween(holderStroke, {Color = Theme.StrokeSoft, Transparency = 0.08}, 0.16)
        Tween(chipStroke, {Color = Theme.Stroke, Transparency = 0.24}, 0.16)
        Tween(energy, {BackgroundTransparency = 0.88}, 0.16)
    end

    local function rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("Frame") and child ~= listLayout then
                child:Destroy()
            end
        end

        table.clear(optionObjects)

        for index, option in ipairs(options) do
            local item = New("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 42),
                LayoutOrder = index,
                Parent = list,
            })

            local optionButton = Button(item, {
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Text = "",
            })
            Corner(optionButton, 12)
            Stroke(optionButton, Theme.StrokeSoft, 1, 0.30)
            Gradient(optionButton, {Theme.Surface3, Theme.Surface2}, 90)

            local marker = New("Frame", {
                BackgroundColor3 = Theme.Accent2,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, 8),
                Size = UDim2.fromOffset(3, 26),
                Parent = optionButton,
            })
            Corner(marker, 999)

            local optionText = Label(
                optionButton,
                tostring(option),
                12,
                Theme.Text,
                Enum.Font.GothamBold
            )
            optionText.Position = UDim2.fromOffset(13, 0)
            optionText.Size = UDim2.new(1, -26, 1, 0)
            optionText.TextTruncate = Enum.TextTruncate.AtEnd

            optionObjects[option] = {
                button = optionButton,
                text = optionText,
                marker = marker,
            }

            optionButton.MouseEnter:Connect(function()
                if selected ~= option then
                    Tween(optionButton, {BackgroundColor3 = Theme.Surface3}, 0.10)
                end
            end)

            optionButton.MouseLeave:Connect(function()
                if selected ~= option then
                    Tween(optionButton, {BackgroundColor3 = Theme.Surface2}, 0.10)
                end
            end)

            optionButton.MouseButton1Click:Connect(function()
                choose(option, true)
                close()
            end)
        end

        updateVisuals()
    end

    local function open()
        opened = true

        local height = math.min(math.max(48, #options * 48), 220)
        list.Size = UDim2.new(1, -20, 0, height)

        Tween(holder, {
            Size = UDim2.new(1, 0, 0, closedHeight + height + 8),
        }, 0.16)

        Tween(arrow, {Rotation = 180}, 0.16)
        Tween(holderStroke, {Color = Theme.Accent2, Transparency = 0.30}, 0.16)
        Tween(chipStroke, {Color = Theme.Accent2, Transparency = 0.10}, 0.16)
        Tween(energy, {BackgroundTransparency = 0.30}, 0.16)
    end

    header.MouseButton1Click:Connect(function()
        if opened then
            close()
        else
            open()
        end
    end)

    function api:Set(value, fireCallback)
        choose(value, fireCallback == true)
    end

    function api:Get()
        return selected
    end

    function api:SetOptions(newOptions)
        options = newOptions or {}
        rebuild()
        updateVisuals()
    end

    rebuild()
    return api
end

function Tab:CreateMultiDropdown(config)
    config = config or {}

    local options = config.Options or {}
    local selected = config.Selected or config.Default or {}
    local opened = false
    local query = ""
    local closedHeight = 60
    local maxListHeight = config.MaxHeight or 210

    local holder, holderStroke, energy = CreateRow(self.Page, closedHeight)
    holder.ClipsDescendants = true

    local header = Button(holder, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, closedHeight),
    })

    local title = Label(header, config.Name or "Multi Select", 13, Theme.Text, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(15, 0)
    title.Size = UDim2.new(0.39, 0, 1, 0)

    local chip = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -39, 0.5, 0),
        Size = UDim2.fromOffset(195, 34),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = header,
    })
    Corner(chip, 999)
    local chipStroke = Stroke(chip, Theme.Stroke, 1, 0.24)
    Gradient(chip, {Theme.Surface4, Theme.Surface3}, 0)

    local summary = Label(
        chip,
        config.Placeholder or "None selected",
        12,
        Theme.Muted,
        Enum.Font.GothamBold
    )
    summary.Position = UDim2.fromOffset(12, 0)
    summary.Size = UDim2.new(1, -38, 1, 0)
    summary.TextTruncate = Enum.TextTruncate.AtEnd

    local arrow = Label(chip, "⌄", 14, Theme.Accent2, Enum.Font.GothamBold)
    arrow.AnchorPoint = Vector2.new(1, 0.5)
    arrow.Position = UDim2.new(1, -10, 0.5, 0)
    arrow.Size = UDim2.fromOffset(16, 16)
    arrow.TextXAlignment = Enum.TextXAlignment.Center

    local body = New("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, closedHeight),
        Size = UDim2.new(1, -20, 0, 0),
        Parent = holder,
    })

    local searchHolder = New("Frame", {
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 36),
        Parent = body,
    })
    Corner(searchHolder, 11)
    local searchStroke = Stroke(searchHolder, Theme.Stroke, 1, 0.24)
    Gradient(searchHolder, {Theme.Surface3, Theme.Surface2}, 90)

    local searchIcon = Label(searchHolder, "⌕", 14, Theme.Accent2, Enum.Font.GothamBold)
    searchIcon.Position = UDim2.fromOffset(10, 0)
    searchIcon.Size = UDim2.fromOffset(20, 36)
    searchIcon.TextXAlignment = Enum.TextXAlignment.Center

    local searchBox = New("TextBox", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(34, 0),
        Size = UDim2.new(1, -44, 1, 0),
        ClearTextOnFocus = false,
        Text = "",
        PlaceholderText = config.SearchPlaceholder or "Search...",
        PlaceholderColor3 = Theme.Muted2,
        TextColor3 = Theme.Text,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = searchHolder,
    })

    local list = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 0, 44),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = self.Window.Mobile and 7 or 4,
        ScrollBarImageColor3 = Theme.Accent2,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        Parent = body,
    })

    local listLayout = New("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })
    SetCanvas(list, listLayout, 4)

    local rows = {}
    local api = {}

    local function countSelected()
        local count = 0
        local only

        for _, option in ipairs(options) do
            if selected[option] == true then
                count += 1
                only = option
            end
        end

        return count, only
    end

    local function updateSummary()
        local count, only = countSelected()

        if count == 0 then
            summary.Text = config.Placeholder or "None selected"
            summary.TextColor3 = Theme.Muted
        elseif count == 1 then
            summary.Text = tostring(only)
            summary.TextColor3 = Theme.Text
        else
            summary.Text = tostring(count) .. " selected"
            summary.TextColor3 = Theme.Accent3
        end
    end

    local function matches(option)
        if query == "" then
            return true
        end

        return string.find(
            string.lower(tostring(option)),
            query,
            1,
            true
        ) ~= nil
    end

    local function resizeBody(animate)
        local shown = 0

        for _, data in pairs(rows) do
            if data.frame.Visible then
                shown += 1
            end
        end

        local listHeight = math.min(
            maxListHeight,
            math.max(46, shown * 48)
        )

        list.Size = UDim2.new(1, 0, 0, listHeight)
        body.Size = UDim2.new(1, -20, 0, 42 + listHeight)

        if opened then
            local target = UDim2.new(1, 0, 0, closedHeight + 50 + listHeight)
            if animate then
                Tween(holder, {Size = target}, 0.16)
            else
                holder.Size = target
            end
        end
    end

    local function refresh()
        for option, data in pairs(rows) do
            local active = selected[option] == true
            data.frame.Visible = matches(option)
            data.button.BackgroundColor3 = active and Theme.Surface4 or Theme.Surface2
            data.text.TextColor3 = active and Theme.Accent3 or Theme.Text
            data.marker.BackgroundTransparency = active and 0 or 1
            data.check.TextTransparency = active and 0 or 1
        end

        updateSummary()
        resizeBody(false)
    end

    local function rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("Frame") and child ~= listLayout then
                child:Destroy()
            end
        end

        table.clear(rows)

        for index, option in ipairs(options) do
            local frame = New("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 42),
                LayoutOrder = index,
                Parent = list,
            })

            local optionButton = Button(frame, {
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Text = "",
            })
            Corner(optionButton, 12)
            Stroke(optionButton, Theme.StrokeSoft, 1, 0.30)
            Gradient(optionButton, {Theme.Surface3, Theme.Surface2}, 90)

            local marker = New("Frame", {
                BackgroundColor3 = Theme.Accent2,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, 8),
                Size = UDim2.fromOffset(3, 26),
                Parent = optionButton,
            })
            Corner(marker, 999)

            local optionText = Label(
                optionButton,
                tostring(option),
                12,
                Theme.Text,
                Enum.Font.GothamBold
            )
            optionText.Position = UDim2.fromOffset(13, 0)
            optionText.Size = UDim2.new(1, -52, 1, 0)
            optionText.TextTruncate = Enum.TextTruncate.AtEnd

            local check = Label(
                optionButton,
                "✓",
                12,
                Theme.Accent3,
                Enum.Font.GothamBold
            )
            check.AnchorPoint = Vector2.new(1, 0.5)
            check.Position = UDim2.new(1, -13, 0.5, 0)
            check.Size = UDim2.fromOffset(20, 20)
            check.TextXAlignment = Enum.TextXAlignment.Center
            check.TextTransparency = 1

            rows[option] = {
                frame = frame,
                button = optionButton,
                text = optionText,
                marker = marker,
                check = check,
            }

            optionButton.MouseButton1Click:Connect(function()
                selected[option] = not (selected[option] == true)
                refresh()

                if config.Callback then
                    task.spawn(config.Callback, option, selected[option], selected)
                end
            end)
        end

        refresh()
    end

    local function setOpen(state)
        opened = state == true

        if opened then
            resizeBody(true)
            Tween(arrow, {Rotation = 180}, 0.16)
            Tween(holderStroke, {Color = Theme.Accent2, Transparency = 0.30}, 0.16)
            Tween(chipStroke, {Color = Theme.Accent2, Transparency = 0.10}, 0.16)
            Tween(energy, {BackgroundTransparency = 0.30}, 0.16)
        else
            Tween(holder, {Size = UDim2.new(1, 0, 0, closedHeight)}, 0.16)
            Tween(arrow, {Rotation = 0}, 0.16)
            Tween(holderStroke, {Color = Theme.StrokeSoft, Transparency = 0.08}, 0.16)
            Tween(chipStroke, {Color = Theme.Stroke, Transparency = 0.24}, 0.16)
            Tween(energy, {BackgroundTransparency = 0.88}, 0.16)
        end
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not opened)
    end)

    searchBox.Focused:Connect(function()
        Tween(searchStroke, {Color = Theme.Accent2, Transparency = 0.10}, 0.12)
    end)

    searchBox.FocusLost:Connect(function()
        Tween(searchStroke, {Color = Theme.Stroke, Transparency = 0.24}, 0.12)
    end)

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        query = string.lower(searchBox.Text or "")
        refresh()
    end)

    function api:SetOptions(newOptions)
        options = newOptions or {}
        rebuild()
    end

    function api:Refresh(newOptions)
        if newOptions then
            options = newOptions
        end
        rebuild()
    end

    function api:GetSelected()
        return selected
    end

    function api:SetSelected(map, fire)
        for key in pairs(selected) do
            selected[key] = nil
        end

        for key, enabled in pairs(map or {}) do
            if enabled == true then
                selected[key] = true
            end
        end

        refresh()

        if fire and config.Callback then
            task.spawn(config.Callback, nil, nil, selected)
        end
    end

    function api:Clear(fire)
        for key in pairs(selected) do
            selected[key] = nil
        end

        refresh()

        if fire and config.Callback then
            task.spawn(config.Callback, nil, nil, selected)
        end
    end

    rebuild()
    return api
end

VNDT.Version = "6.0-alien"
VNDT.Theme = Theme

return VNDT
