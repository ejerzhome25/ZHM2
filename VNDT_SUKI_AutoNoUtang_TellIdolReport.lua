--//====================================================
--// VNDT SUKI - FULL UPDATED - AUTO NO UTANG + TELL IDOL REPORT
--//====================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--//====================================================
--// SESSION GUARD
--//====================================================

local ENV = (getgenv and getgenv()) or _G

ENV.__VNDT_SUKI_SESSION =
    (ENV.__VNDT_SUKI_SESSION or 0) + 1

local SESSION = ENV.__VNDT_SUKI_SESSION

local function Alive()
    return ENV.__VNDT_SUKI_SESSION == SESSION
end

--//====================================================
--// REMOVE OLD VNDT
--//====================================================

pcall(function()
    local Old = PlayerGui:FindFirstChild("VNDT_Suki")
    if Old then
        Old:Destroy()
    end
end)

--//====================================================
--// REMOTES
--//====================================================

local SukiRemotes =
    ReplicatedStorage:WaitForChild("SukiRemotes")

local Grocery =
    SukiRemotes:WaitForChild("Grocery")

local Jump =
    SukiRemotes:WaitForChild("Jump")

local Upgrades =
    SukiRemotes:WaitForChild("Upgrades")

local Singil =
    SukiRemotes:WaitForChild("Singil")

--//====================================================
--// TOGGLES
--//====================================================

local AUTO_BUY = true

local AUTO_ROUTE = true
local AUTO_TAKE = true
local AUTO_GIVE = true

local AUTO_FREEZER = true

local AUTO_UPGRADES = false

local AUTO_UTANG = false
local AUTO_NO_UTANG = false
local AUTO_SINGIL = false
local AUTO_REPORT = false

local AUTO_HIDE_POPUPS = true

local HIDE_LISTA_UI = true

--//====================================================
--// AUTO BUY
--//====================================================

local MarketItems = {
    "mantika",
    "load",
    "shampoo",
    "pandesal",
    "icecandy",
    "softdrink",
    "kola",
}

local BUY_QUANTITY = 1

local BUY_ITEM_DELAY = 0.05
local BUY_ROUND_DELAY = 0.05

--//====================================================
--// ROUTE
--//====================================================

local MARKET_WAIT = 5

local STORE_LOAD_WAIT = 0.75
local STORE_WAIT = 6

local STORE_ACTION_DELAY = 0.10

local PROMPT_DISTANCE = 100000

--//====================================================
--// TELL IDOL / AUTO REPORT
--//====================================================

local REPORT_TP_WAIT = 0.15
local REPORT_GUI_WAIT = 0.25
local REPORT_BUTTON_DELAY = 0.05

local ReportBusy = false

--//====================================================
--// FREEZER
--//====================================================

local FREEZER_ON_TIME = 30
local FREEZER_OFF_TIME = 120

local FREEZER_CHECK_DELAY = 0.25

local CachedStore = nil

--//====================================================
--// UPGRADES
--//====================================================

local UpgradeList = {
    "counter",
    "fridge",
    "light",
    "tambay",
    "patubo",
    "tambaylook",
    "basket",
    "kitchen",
    "shacks",
    "household",
    "rack",
    "tarproof",
    "longtarp",
    "generator",
    "openwindow",
    "bigsign",
}

local UPGRADE_ITEM_DELAY = 0.35
local UPGRADE_ROUND_DELAY = 1

--//====================================================
--// UTANG
--//====================================================

local UTANG_SCAN_DELAY = 0.05
local UTANG_COOLDOWN = 0.10

local LastUtangClick = 0

--//====================================================
--// SINGIL
--//====================================================

local SINGIL_DELAY = 2
local FALLBACK_SINGIL = "baby"

local SingilBusy = false
local LastSingilTime = 0

--//====================================================
--// POPUPS
--//====================================================

local POPUP_SCAN_DELAY = 0.05

--//====================================================
--// SAFE FIRE
--//====================================================

local function SafeFire(Remote, ...)

    if not Alive() then
        return false
    end

    local Args = {...}

    return pcall(function()
        Remote:FireServer(
            table.unpack(Args)
        )
    end)
end

--//====================================================
--// CHARACTER
--//====================================================

local function GetCharacter()

    local Character = Player.Character

    if not Character
    or not Character.Parent
    then

        Character =
            Player.CharacterAdded:Wait()
    end

    return Character
end

local function GetRoot()

    local Character =
        GetCharacter()

    return
        Character:FindFirstChild("HumanoidRootPart")
        or Character:WaitForChild("HumanoidRootPart")
end

--//====================================================
--// GUI VISIBLE
--//====================================================

local function IsGuiVisible(Object)

    if not Object
    or not Object.Parent
    then
        return false
    end

    local Current = Object

    while Current
    and Current ~= PlayerGui
    do

        if Current:IsA("GuiObject")
        and Current.Visible == false
        then

            return false
        end

        Current = Current.Parent
    end

    return true
end

--//====================================================
--// BUTTON FIRE
--//====================================================

local function FireGuiButton(Button)

    if not Alive()
    or not Button
    or not Button.Parent
    or not Button:IsA("GuiButton")
    then

        return false
    end

    --------------------------------------------------
    -- Connection callback first
    --------------------------------------------------

    if getconnections then

        local Fired = false

        pcall(function()

            for _, Connection in ipairs(
                getconnections(
                    Button.Activated
                )
            ) do

                if Connection.Fire then

                    Connection:Fire()
                    Fired = true

                elseif Connection.Function then

                    Connection.Function()
                    Fired = true
                end
            end
        end)

        if Fired then
            return true
        end
    end

    --------------------------------------------------
    -- Activated
    --------------------------------------------------

    if firesignal then

        local Success =
            pcall(function()

                firesignal(
                    Button.Activated
                )
            end)

        if Success then
            return true
        end
    end

    --------------------------------------------------
    -- MouseButton1Click
    --------------------------------------------------

    if firesignal
    and Button:IsA("TextButton")
    then

        local Success =
            pcall(function()

                firesignal(
                    Button.MouseButton1Click
                )
            end)

        if Success then
            return true
        end
    end

    return false
end

--//====================================================
--// PROMPTS
--//====================================================

local function ExpandPrompt(Prompt)

    if not Prompt
    or not Prompt.Parent
    then
        return
    end

    pcall(function()

        Prompt.Enabled = true
        Prompt.HoldDuration = 0

        Prompt.MaxActivationDistance =
            PROMPT_DISTANCE

        Prompt.RequiresLineOfSight = false

        Prompt.Exclusivity =
            Enum.ProximityPromptExclusivity.AlwaysShow
    end)
end

local function FirePrompt(Prompt)

    if not Alive()
    or not Prompt
    or not Prompt.Parent
    then

        return false
    end

    ExpandPrompt(Prompt)

    if fireproximityprompt then

        local Success =
            pcall(function()

                fireproximityprompt(
                    Prompt
                )
            end)

        if Success then
            return true
        end
    end

    return pcall(function()

        Prompt:InputHoldBegin()

        task.wait()

        Prompt:InputHoldEnd()
    end)
end

--//====================================================
--// AUTO BUY - 0.05 SEC
--//====================================================

local function BuyAll()

    for _, ItemName in ipairs(
        MarketItems
    ) do

        if not AUTO_BUY
        or not Alive()
        then
            break
        end

        pcall(function()

            Grocery:FireServer(
                ItemName,
                BUY_QUANTITY
            )
        end)

        task.wait(
            BUY_ITEM_DELAY
        )
    end
end

task.spawn(function()

    while Alive() do

        if AUTO_BUY then

            BuyAll()

            task.wait(
                BUY_ROUND_DELAY
            )

        else

            task.wait(0.10)
        end
    end
end)

--//====================================================
--// TELEPORT
--//====================================================

local function TeleportTo(Location)

    SafeFire(
        Jump,
        Location
    )
end

--//====================================================
--// PROMPT POSITION
--//====================================================

local function GetPromptPosition(Prompt)

    if not Prompt then
        return nil
    end

    local Parent =
        Prompt.Parent

    if Parent:IsA("BasePart") then
        return Parent.Position
    end

    if Parent:IsA("Attachment") then
        return Parent.WorldPosition
    end

    local Part =
        Prompt:FindFirstAncestorWhichIsA(
            "BasePart"
        )

    if Part then
        return Part.Position
    end

    return nil
end

--//====================================================
--// FIND TAKE
--//====================================================

local function FindTakeInStall(Stall)

    if not Stall then
        return nil
    end

    local Shelf =
        Stall:FindFirstChild(
            "ShelfAll",
            true
        )

    if Shelf then

        local Take =
            Shelf:FindFirstChild(
                "TakeAll",
                true
            )

        if Take
        and Take:IsA("ProximityPrompt")
        then

            return Take
        end
    end

    for _, Object in ipairs(
        Stall:GetDescendants()
    ) do

        if Object:IsA("ProximityPrompt") then

            local Name =
                string.upper(
                    Object.Name or ""
                )

            local Action =
                string.upper(
                    Object.ActionText or ""
                )

            if
                Name == "TAKE"
                or Name == "TAKEALL"
                or Action == "TAKE"
                or Action == "TAKE ALL"
            then

                return Object
            end
        end
    end

    return nil
end

--//====================================================
--// FIND GIVE
--//====================================================

local function FindGiveInStall(Stall)

    if not Stall then
        return nil
    end

    local Counter =
        Stall:FindFirstChild(
            "Counter",
            true
        )

    if Counter then

        local Give =
            Counter:FindFirstChild(
                "GIVE",
                true
            )

        if Give
        and Give:IsA("ProximityPrompt")
        then

            return Give
        end
    end

    for _, Object in ipairs(
        Stall:GetDescendants()
    ) do

        if Object:IsA("ProximityPrompt") then

            local Name =
                string.upper(
                    Object.Name or ""
                )

            local Action =
                string.upper(
                    Object.ActionText or ""
                )

            if
                Name == "GIVE"
                or Action == "GIVE"
            then

                return Object
            end
        end
    end

    return nil
end

--//====================================================
--// FIND MY STORE
--//====================================================

local function FindMyStore()

    local Suki =
        Workspace:FindFirstChild("Suki")

    if not Suki then
        return nil
    end

    local Stalls =
        Suki:FindFirstChild("Stalls")

    if not Stalls then
        return nil
    end

    local Root =
        GetRoot()

    local BestStore = nil
    local BestDistance = math.huge

    for _, Stall in ipairs(
        Stalls:GetChildren()
    ) do

        local Take =
            FindTakeInStall(Stall)

        local Give =
            FindGiveInStall(Stall)

        if Take or Give then

            local Distance =
                math.huge

            if Take then

                local Position =
                    GetPromptPosition(Take)

                if Position then

                    Distance =
                        math.min(
                            Distance,
                            (
                                Root.Position
                                - Position
                            ).Magnitude
                        )
                end
            end

            if Give then

                local Position =
                    GetPromptPosition(Give)

                if Position then

                    Distance =
                        math.min(
                            Distance,
                            (
                                Root.Position
                                - Position
                            ).Magnitude
                        )
                end
            end

            if Distance < BestDistance then

                BestDistance = Distance
                BestStore = Stall
            end
        end
    end

    if BestStore then
        CachedStore = BestStore
    end

    return BestStore
end

--//====================================================
--// STORE TAKE + GIVE
--//====================================================

local function RunStoreAutomation(
    Store,
    Duration
)

    if not Store then
        return
    end

    CachedStore = Store

    local TakePrompt =
        FindTakeInStall(Store)

    local GivePrompt =
        FindGiveInStall(Store)

    local Started = os.clock()

    while
        Alive()
        and AUTO_ROUTE
        and Store
        and Store.Parent
        and
        os.clock() - Started < Duration
    do

        if not TakePrompt
        or not TakePrompt.Parent
        then

            TakePrompt =
                FindTakeInStall(Store)
        end

        if not GivePrompt
        or not GivePrompt.Parent
        then

            GivePrompt =
                FindGiveInStall(Store)
        end

        if AUTO_TAKE
        and TakePrompt
        then

            FirePrompt(
                TakePrompt
            )
        end

        if AUTO_GIVE
        and GivePrompt
        then

            FirePrompt(
                GivePrompt
            )
        end

        task.wait(
            STORE_ACTION_DELAY
        )
    end
end

--//====================================================
--// TELL IDOL + AUTO REPORT
--//
--// Exact flow from the action log:
--// Workspace.Suki.Hall.Mesa["TELL IDOL"]
--// -> SukiHUD["IDOL IN ACTION"].Body.<customer>.Button
--//====================================================

local function GetTellIdolPrompt()

    local Suki =
        Workspace:FindFirstChild(
            "Suki"
        )

    local Hall =
        Suki
        and Suki:FindFirstChild(
            "Hall"
        )

    local Mesa =
        Hall
        and Hall:FindFirstChild(
            "Mesa"
        )

    if not Mesa then
        return nil
    end

    local Prompt =
        Mesa:FindFirstChild(
            "TELL IDOL"
        )

    if Prompt
    and Prompt:IsA("ProximityPrompt")
    then

        return Prompt
    end

    Prompt =
        Mesa:FindFirstChild(
            "TELL IDOL",
            true
        )

    if Prompt
    and Prompt:IsA("ProximityPrompt")
    then

        return Prompt
    end

    return nil
end

local function GetPromptWorldPosition(Prompt)

    if not Prompt
    or not Prompt.Parent
    then

        return nil
    end

    local Parent =
        Prompt.Parent

    if Parent:IsA("Attachment") then
        return Parent.WorldPosition
    end

    if Parent:IsA("BasePart") then
        return Parent.Position
    end

    local Part =
        Prompt:FindFirstAncestorWhichIsA(
            "BasePart"
        )

    if Part then
        return Part.Position
    end

    return nil
end

local function TeleportCharacterToPrompt(Prompt)

    if not Alive()
    or not Prompt
    or not Prompt.Parent
    then

        return false
    end

    local Position =
        GetPromptWorldPosition(
            Prompt
        )

    if not Position then
        return false
    end

    local Root =
        GetRoot()

    if not Root then
        return false
    end

    return pcall(function()

        -- Small offset so the character does not spawn inside the table/model.
        Root.CFrame =
            CFrame.new(
                Position
                + Vector3.new(
                    0,
                    2,
                    2
                )
            )
    end)
end

local function GetIdolActionFrame()

    local HUD =
        PlayerGui:FindFirstChild(
            "SukiHUD"
        )

    if not HUD then
        return nil
    end

    return
        HUD:FindFirstChild(
            "IDOL IN ACTION"
        )
end

local function GetIdolReportBody()

    local Idol =
        GetIdolActionFrame()

    if not Idol then
        return nil
    end

    return
        Idol:FindFirstChild(
            "Body"
        )
end

local function ButtonShowsReport(Button)

    if not Button
    or not Button.Parent
    or not Button:IsA("GuiButton")
    then

        return false
    end

    local function Matches(Text)

        return
            string.find(
                string.upper(
                    tostring(
                        Text
                        or ""
                    )
                ),
                "REPORT",
                1,
                true
            )
            ~= nil
    end

    if string.upper(
        tostring(
            Button.Name
        )
    ) == "REPORT"
    then

        return true
    end

    if Button:IsA("TextButton")
    and Matches(
        Button.Text
    )
    then

        return true
    end

    for _, Child in ipairs(
        Button:GetDescendants()
    ) do

        if Child:IsA("TextLabel")
        or Child:IsA("TextButton")
        then

            if Matches(
                Child.Text
            )
            then

                return true
            end
        end
    end

    return false
end

local function GetIdolReportButtons()

    local Results = {}
    local Added = {}

    local Body =
        GetIdolReportBody()

    if not Body then
        return Results
    end

    --------------------------------------------------
    -- Exact structure first:
    -- Body.<customer>.Button
    --------------------------------------------------

    for _, Row in ipairs(
        Body:GetChildren()
    ) do

        local Button =
            Row:FindFirstChild(
                "Button"
            )

        if Button
        and Button:IsA("GuiButton")
        and ButtonShowsReport(
            Button
        )
        then

            Added[Button] = true

            table.insert(
                Results,
                Button
            )
        end
    end

    --------------------------------------------------
    -- Fallback only inside IDOL IN ACTION.Body
    --------------------------------------------------

    for _, Object in ipairs(
        Body:GetDescendants()
    ) do

        if Object:IsA("GuiButton")
        and not Added[Object]
        and ButtonShowsReport(
            Object
        )
        then

            Added[Object] = true

            table.insert(
                Results,
                Object
            )
        end
    end

    table.sort(
        Results,
        function(A, B)

            local AP =
                A.AbsolutePosition

            local BP =
                B.AbsolutePosition

            if AP.Y == BP.Y then
                return AP.X < BP.X
            end

            return AP.Y < BP.Y
        end
    )

    return Results
end

local function CloseIdolAction()

    local Idol =
        GetIdolActionFrame()

    if not Idol then
        return
    end

    local Head =
        Idol:FindFirstChild(
            "Head"
        )

    local Close =
        Head
        and Head:FindFirstChild(
            "Close"
        )

    if Close
    and Close:IsA("GuiButton")
    then

        FireGuiButton(
            Close
        )
    end
end

local function RunTellIdolReport()

    if not AUTO_REPORT
    or ReportBusy
    or not Alive()
    then

        return false
    end

    ReportBusy = true

    local Prompt =
        GetTellIdolPrompt()

    if not Prompt then

        ReportBusy = false
        return false
    end

    --------------------------------------------------
    -- TP to TELL IDOL after the 6-second store stay
    --------------------------------------------------

    TeleportCharacterToPrompt(
        Prompt
    )

    task.wait(
        REPORT_TP_WAIT
    )

    if not AUTO_REPORT
    or not Alive()
    then

        ReportBusy = false
        return false
    end

    --------------------------------------------------
    -- Open IDOL IN ACTION through the real prompt
    --------------------------------------------------

    FirePrompt(
        Prompt
    )

    task.wait(
        REPORT_GUI_WAIT
    )

    --------------------------------------------------
    -- Click every real REPORT button
    --------------------------------------------------

    local Buttons =
        GetIdolReportButtons()

    for _, Button in ipairs(
        Buttons
    ) do

        if not AUTO_REPORT
        or not Alive()
        then

            break
        end

        if Button
        and Button.Parent
        and ButtonShowsReport(
            Button
        )
        then

            FireGuiButton(
                Button
            )

            task.wait(
                REPORT_BUTTON_DELAY
            )
        end
    end

    --------------------------------------------------
    -- Close IDOL IN ACTION so it is ready next route
    --------------------------------------------------

    CloseIdolAction()

    ReportBusy = false

    return true
end

--//====================================================
--// ROUTE
--//====================================================

task.spawn(function()

    while Alive() do

        if AUTO_ROUTE then

            --------------------------------------------------
            -- BAGSAKAN
            --------------------------------------------------

            TeleportTo(
                "bagsakan"
            )

            task.wait(
                MARKET_WAIT
            )

            if not Alive() then
                break
            end

            --------------------------------------------------
            -- STORE
            --------------------------------------------------

            TeleportTo(
                "store"
            )

            task.wait(
                STORE_LOAD_WAIT
            )

            local Store =
                FindMyStore()

            if Store then

                RunStoreAutomation(
                    Store,
                    STORE_WAIT
                )

            else

                task.wait(
                    STORE_WAIT
                )
            end

            --------------------------------------------------
            -- AFTER STORE STAYS 6 SEC:
            -- TP -> TELL IDOL -> AUTO REPORT
            --------------------------------------------------

            if AUTO_REPORT
            and AUTO_ROUTE
            and Alive()
            then

                RunTellIdolReport()
            end

        else

            task.wait(0.20)
        end
    end
end)

--//====================================================
--// FREEZER PROMPT
--//====================================================

local function FindFreezerPrompt(Store)

    if not Store
    or not Store.Parent
    then

        return nil
    end

    --------------------------------------------------
    -- Exact path from action log structure
    --------------------------------------------------

    local Upgrade =
        Store:FindFirstChild(
            "Upgrade_fridge"
        )

    if Upgrade then

        local Switch =
            Upgrade:FindFirstChild(
                "FridgeSwitch",
                true
            )

        if Switch then

            local Prompt =
                Switch:FindFirstChild(
                    "FreezerPrompt",
                    true
                )

            if Prompt
            and Prompt:IsA("ProximityPrompt")
            then

                return Prompt
            end
        end
    end

    --------------------------------------------------
    -- Fallback live scan
    --------------------------------------------------

    for _, Object in ipairs(
        Store:GetDescendants()
    ) do

        if Object:IsA("ProximityPrompt") then

            local Blob =
                string.upper(
                    tostring(Object.Name)
                    .. " "
                    .. tostring(Object.ActionText)
                    .. " "
                    .. tostring(Object.ObjectText)
                )

            if
                string.find(
                    Blob,
                    "FREEZER",
                    1,
                    true
                )
            then

                return Object
            end
        end
    end

    return nil
end

--//====================================================
--// FREEZER STATE
--//
--// Prompt says "Freezer OFF"
--// = freezer is currently ON
--// = pressing it will turn OFF
--//
--// Prompt says "Freezer ON"
--// = freezer is currently OFF
--// = pressing it will turn ON
--//====================================================

local function GetFreezerState(Prompt)

    if not Prompt
    or not Prompt.Parent
    then

        return nil
    end

    local Blob =
        string.upper(
            tostring(Prompt.Name)
            .. " "
            .. tostring(Prompt.ActionText)
            .. " "
            .. tostring(Prompt.ObjectText)
        )

    if string.find(
        Blob,
        "FREEZER OFF",
        1,
        true
    )
    then

        return true
    end

    if string.find(
        Blob,
        "FREEZER ON",
        1,
        true
    )
    then

        return false
    end

    return nil
end

--//====================================================
--// SET FREEZER STATE
--//====================================================

local function SetFreezerState(
    WantedOn
)

    if not AUTO_FREEZER
    or not Alive()
    then

        return false
    end

    local Store =
        CachedStore

    if not Store
    or not Store.Parent
    then

        Store =
            FindMyStore()
    end

    if not Store then
        return false
    end

    local Prompt =
        FindFreezerPrompt(
            Store
        )

    if not Prompt then
        return false
    end

    ExpandPrompt(Prompt)

    local Current =
        GetFreezerState(
            Prompt
        )

    --------------------------------------------------
    -- Already correct
    --------------------------------------------------

    if Current == WantedOn then
        return true
    end

    --------------------------------------------------
    -- Only press if state was positively detected.
    -- Prevents accidental double toggles.
    --------------------------------------------------

    if Current ~= nil then

        FirePrompt(
            Prompt
        )

        task.wait(0.20)

        return true
    end

    return false
end

--//====================================================
--// FREEZER TIMER WAIT
--//====================================================

local function FreezerWait(Seconds)

    local Start =
        os.clock()

    while Alive()
    and AUTO_FREEZER
    and
    os.clock() - Start < Seconds
    do

        task.wait(
            FREEZER_CHECK_DELAY
        )
    end
end

--//====================================================
--// AUTO FREEZER CYCLE
--//
--// ON  30 SEC
--// OFF 120 SEC
--// REPEAT
--//====================================================

task.spawn(function()

    while Alive() do

        if not AUTO_FREEZER then

            task.wait(0.50)

        elseif not CachedStore
        or not CachedStore.Parent
        then

            --------------------------------------------------
            -- Wait until route has identified your store
            --------------------------------------------------

            task.wait(0.50)

        else

            --------------------------------------------------
            -- FREEZER ON
            --------------------------------------------------

            local OnSuccess =
                SetFreezerState(
                    true
                )

            if OnSuccess then

                FreezerWait(
                    FREEZER_ON_TIME
                )

                if AUTO_FREEZER
                and Alive()
                then

                    --------------------------------------------------
                    -- FREEZER OFF
                    --------------------------------------------------

                    SetFreezerState(
                        false
                    )

                    FreezerWait(
                        FREEZER_OFF_TIME
                    )
                end

            else

                task.wait(1)
            end
        end
    end
end)

--//====================================================
--// AUTO UPGRADE
--//====================================================

local UpgradeBusy = false

local function UpgradeAll()

    if UpgradeBusy
    or not Alive()
    then
        return
    end

    UpgradeBusy = true

    for _, UpgradeName in ipairs(
        UpgradeList
    ) do

        if not AUTO_UPGRADES
        or not Alive()
        then
            break
        end

        SafeFire(
            Upgrades,
            UpgradeName,
            false
        )

        task.wait(
            UPGRADE_ITEM_DELAY
        )
    end

    UpgradeBusy = false
end

task.spawn(function()

    while Alive() do

        if AUTO_UPGRADES then

            UpgradeAll()

            task.wait(
                UPGRADE_ROUND_DELAY
            )

        else

            UpgradeBusy = false

            task.wait(0.25)
        end
    end
end)

--//====================================================
--// AUTO UTANG / AUTO NO UTANG
--//====================================================

local function GetAskButton(ButtonName)

    local HUD =
        PlayerGui:FindFirstChild(
            "SukiHUD"
        )

    if not HUD then
        return nil
    end

    local Ask =
        HUD:FindFirstChild(
            "Ask"
        )

    if not Ask then
        return nil
    end

    local Button =
        Ask:FindFirstChild(
            ButtonName
        )

    if Button
    and Button:IsA("GuiButton")
    then
        return Button
    end

    return nil
end

--//====================================================
--// AUTO ACCEPT UTANG
--//====================================================

local function AutoAcceptUtang()

    -- Auto NO Utang has priority if both are enabled.
    if AUTO_NO_UTANG then
        return
    end

    if not AUTO_UTANG
    or not Alive()
    then
        return
    end

    local Yes =
        GetAskButton(
            "Yes"
        )

    if not Yes
    or not IsGuiVisible(Yes)
    then
        return
    end

    if
        os.clock() - LastUtangClick
        < UTANG_COOLDOWN
    then
        return
    end

    if FireGuiButton(Yes) then
        LastUtangClick = os.clock()
    end
end

--//====================================================
--// AUTO NO UTANG
--//====================================================

local function AutoRejectUtang()

    if not AUTO_NO_UTANG
    or not Alive()
    then
        return
    end

    local No =
        GetAskButton(
            "No"
        )

    if not No
    or not IsGuiVisible(No)
    then
        return
    end

    if
        os.clock() - LastUtangClick
        < UTANG_COOLDOWN
    then
        return
    end

    if FireGuiButton(No) then
        LastUtangClick = os.clock()
    end
end

local function HandleUtangPrompt()

    if not Alive() then
        return
    end

    if AUTO_NO_UTANG then
        AutoRejectUtang()
    elseif AUTO_UTANG then
        AutoAcceptUtang()
    end
end

task.spawn(function()

    while Alive() do

        if AUTO_NO_UTANG
        or AUTO_UTANG
        then

            HandleUtangPrompt()

            task.wait(
                UTANG_SCAN_DELAY
            )

        else

            task.wait(0.20)
        end
    end
end)

-- Live detection when the Ask buttons are recreated/opened.
PlayerGui.DescendantAdded:Connect(
    function(Object)

        if not Alive() then
            return
        end

        if Object:IsA("GuiButton")
        and (
            Object.Name == "Yes"
            or Object.Name == "No"
        )
        then

            task.defer(function()

                task.wait()

                if Alive() then
                    HandleUtangPrompt()
                end
            end)
        end
    end
)

--//====================================================
--// LISTA
--//====================================================

local HiddenListaPanels = {}

local function IsDescendantOf(
    Object,
    Parent
)

    local Current = Object

    while Current do

        if Current == Parent then
            return true
        end

        Current =
            Current.Parent
    end

    return false
end

local function FindGuiButtonInside(Object)

    if not Object then
        return nil
    end

    if Object:IsA("GuiButton") then
        return Object
    end

    for _, Child in ipairs(
        Object:GetDescendants()
    ) do

        if Child:IsA("GuiButton") then
            return Child
        end
    end

    local Current =
        Object.Parent

    while Current
    and Current ~= PlayerGui
    do

        if Current:IsA("GuiButton") then
            return Current
        end

        Current =
            Current.Parent
    end

    return nil
end

--//====================================================
--// FIND LISTA PANELS
--//====================================================

local function FindListaPanels()

    local Results = {}
    local Added = {}

    local HUD =
        PlayerGui:FindFirstChild(
            "SukiHUD"
        )

    if not HUD then
        return Results
    end

    local Rail =
        HUD:FindFirstChild(
            "Rail"
        )

    for _, Object in ipairs(
        HUD:GetDescendants()
    ) do

        if Object:IsA("TextLabel")
        or Object:IsA("TextButton")
        then

            local Text =
                string.upper(
                    tostring(
                        Object.Text or ""
                    )
                )

            if
                Text == "LISTA"
                or
                string.find(
                    Text,
                    "PEOPLE OWE YOU",
                    1,
                    true
                )
            then

                if not (
                    Rail
                    and
                    IsDescendantOf(
                        Object,
                        Rail
                    )
                )
                then

                    local Current =
                        Object.Parent

                    while Current
                    and Current ~= HUD
                    do

                        if Current:IsA("GuiObject") then

                            local Size =
                                Current.AbsoluteSize

                            if
                                Size.X >= 220
                                and
                                Size.Y >= 130
                            then

                                if not Added[
                                    Current
                                ]
                                then

                                    Added[
                                        Current
                                    ] = true

                                    table.insert(
                                        Results,
                                        Current
                                    )
                                end

                                break
                            end
                        end

                        Current =
                            Current.Parent
                    end
                end
            end
        end
    end

    for Panel in pairs(
        HiddenListaPanels
    ) do

        if Panel
        and Panel.Parent
        and not Added[Panel]
        then

            table.insert(
                Results,
                Panel
            )
        end
    end

    return Results
end

--//====================================================
--// OPEN LISTA
--//====================================================

local function OpenLista()

    if #FindListaPanels() > 0 then
        return true
    end

    local HUD =
        PlayerGui:FindFirstChild(
            "SukiHUD"
        )

    if not HUD then
        return false
    end

    local Rail =
        HUD:FindFirstChild(
            "Rail"
        )

    if not Rail then
        return false
    end

    local Lista =
        Rail:FindFirstChild(
            "LISTA"
        )

    if not Lista then
        return false
    end

    local Button =
        FindGuiButtonInside(
            Lista
        )

    if not Button then
        return false
    end

    FireGuiButton(
        Button
    )

    task.wait(0.25)

    return
        #FindListaPanels() > 0
end

--//====================================================
--// HIDE LISTA
--//====================================================

local function HideListaUI()

    if not HIDE_LISTA_UI
    or not Alive()
    then
        return
    end

    if not AUTO_SINGIL
    then
        return
    end

    for _, Panel in ipairs(
        FindListaPanels()
    ) do

        if not HiddenListaPanels[
            Panel
        ]
        then

            HiddenListaPanels[
                Panel
            ] = {
                Position =
                    Panel.Position
            }
        end

        pcall(function()

            Panel.Position =
                UDim2.new(
                    5,
                    0,
                    5,
                    0
                )
        end)
    end
end

local function RestoreListaUI()

    if AUTO_SINGIL
    then
        return
    end

    for Panel, Data in pairs(
        HiddenListaPanels
    ) do

        if Panel
        and Panel.Parent
        then

            pcall(function()

                Panel.Position =
                    Data.Position
            end)
        end
    end

    table.clear(
        HiddenListaPanels
    )
end

--//====================================================
--// SINGIL
--//====================================================

local function ButtonShowsSingil(Button)

    if not Button
    or not Button:IsA("GuiButton")
    then
        return false
    end

    local function Match(Text)

        return
            string.find(
                string.upper(
                    tostring(Text or "")
                ),
                "SINGIL",
                1,
                true
            ) ~= nil
    end

    if Button:IsA("TextButton")
    and Match(Button.Text)
    then

        return true
    end

    for _, Child in ipairs(
        Button:GetDescendants()
    ) do

        if Child:IsA("TextLabel")
        or Child:IsA("TextButton")
        then

            if Match(Child.Text) then
                return true
            end
        end
    end

    return false
end

local function FindSingilButtons()

    local Results = {}

    for _, Panel in ipairs(
        FindListaPanels()
    ) do

        for _, Object in ipairs(
            Panel:GetDescendants()
        ) do

            if Object:IsA("GuiButton")
            and ButtonShowsSingil(Object)
            then

                table.insert(
                    Results,
                    Object
                )
            end
        end
    end

    table.sort(
        Results,
        function(A, B)

            return
                A.AbsolutePosition.Y
                <
                B.AbsolutePosition.Y
        end
    )

    return Results
end

local function SingilOnce()

    if not AUTO_SINGIL
    or SingilBusy
    or not Alive()
    then

        return
    end

    if
        os.clock() - LastSingilTime
        < SINGIL_DELAY
    then

        return
    end

    SingilBusy = true

    OpenLista()

    task.wait(0.10)

    local Buttons =
        FindSingilButtons()

    local Success = false

    if Buttons[1] then

        Success =
            FireGuiButton(
                Buttons[1]
            )
    end

    if not Success then

        Success =
            pcall(function()

                Singil:FireServer(
                    FALLBACK_SINGIL
                )
            end)
    end

    HideListaUI()

    if Success then
        LastSingilTime = os.clock()
    end

    SingilBusy = false
end

task.spawn(function()

    while Alive() do

        if AUTO_SINGIL then

            SingilOnce()

            task.wait(0.10)

        else

            task.wait(0.25)
        end
    end
end)

--//====================================================
--// HIDE INVITE FRIEND UI
--// Exact GUI: InviteAsk
--//====================================================

local function HideInviteUI()

    local Invite =
        PlayerGui:FindFirstChild(
            "InviteAsk"
        )

    if Invite then

        if Invite:IsA("ScreenGui") then

            pcall(function()

                Invite.Enabled = false
            end)
        end

        for _, Object in ipairs(
            Invite:GetDescendants()
        ) do

            if Object:IsA("GuiObject") then

                pcall(function()

                    Object.Visible = false
                end)
            end
        end
    end
end

--//====================================================
--// POPUP HIDER
--//====================================================

local ProtectedGui = {
    ["VNDT_Suki"] = true,
    ["SukiHUD"] = true,
    ["SukiTop"] = true,
    ["ProximityPrompts"] = true,

    ["LB_served"] = true,
    ["LB_today"] = true,
    ["LB_trusted"] = true,
    ["LB_time"] = true,
}

local function GetGuiRoot(Object)

    local Current = Object

    while Current
    and Current ~= PlayerGui
    do

        if Current:IsA("ScreenGui")
        or Current:IsA("SurfaceGui")
        then

            return Current
        end

        Current = Current.Parent
    end

    return nil
end

local function HideKnownPopups()

    --------------------------------------------------
    -- INVITE FRIEND
    --------------------------------------------------

    HideInviteUI()

    --------------------------------------------------
    -- TOASTS
    --------------------------------------------------

    local Toast =
        PlayerGui:FindFirstChild(
            "SukiToasts"
        )

    if Toast then

        if Toast:IsA("ScreenGui") then

            pcall(function()

                Toast.Enabled = false
            end)
        end

        for _, Object in ipairs(
            Toast:GetDescendants()
        ) do

            if Object:IsA("GuiObject") then

                pcall(function()

                    Object.Visible = false
                end)
            end
        end
    end

    --------------------------------------------------
    -- GUIDE POPUPS
    --------------------------------------------------

    local Guide =
        PlayerGui:FindFirstChild(
            "GuideArrowHint"
        )

    if Guide then

        if Guide:IsA("ScreenGui") then

            pcall(function()

                Guide.Enabled = false
            end)
        end

        for _, Object in ipairs(
            Guide:GetDescendants()
        ) do

            if Object:IsA("TextLabel")
            or Object:IsA("TextButton")
            then

                pcall(function()

                    Object.Visible = false
                end)
            end
        end
    end
end

local function HideGenericPopup(
    Object
)

    if not AUTO_HIDE_POPUPS
    or not Alive()
    then
        return
    end

    if not (
        Object:IsA("TextLabel")
        or Object:IsA("TextButton")
        or Object:IsA("TextBox")
    )
    then
        return
    end

    local Root =
        GetGuiRoot(
            Object
        )

    if not Root
    or ProtectedGui[
        Root.Name
    ]
    then

        return
    end

    local Candidate =
        Object

    local Current =
        Object

    for _ = 1, 6 do

        if not Current
        or Current == PlayerGui
        then
            break
        end

        if Current:IsA("GuiObject") then

            Candidate =
                Current
        end

        Current =
            Current.Parent
    end

    pcall(function()

        Candidate.Visible =
            false
    end)
end

local function ScanPopupText()

    if not AUTO_HIDE_POPUPS
    or not Alive()
    then
        return
    end

    HideKnownPopups()

    for _, Object in ipairs(
        PlayerGui:GetDescendants()
    ) do

        HideGenericPopup(
            Object
        )
    end
end

PlayerGui.DescendantAdded:Connect(
    function(Object)

        if not AUTO_HIDE_POPUPS
        or not Alive()
        then

            return
        end

        task.defer(function()

            task.wait()

            if AUTO_HIDE_POPUPS
            and Alive()
            then

                HideKnownPopups()

                HideGenericPopup(
                    Object
                )
            end
        end)
    end
)

task.spawn(function()

    while Alive() do

        if AUTO_HIDE_POPUPS then

            ScanPopupText()

            task.wait(
                POPUP_SCAN_DELAY
            )

        else

            task.wait(0.25)
        end
    end
end)

--//====================================================
--// VNDT UI
--//====================================================

local ScreenGui =
    Instance.new("ScreenGui")

ScreenGui.Name = "VNDT_Suki"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.Parent = PlayerGui

--//====================================================
--// MAIN
--//====================================================

local Main =
    Instance.new("Frame")

Main.Name = "Main"

Main.Size =
    UDim2.fromOffset(
        300,
        390
    )

Main.Position =
    UDim2.new(
        0.5,
        -150,
        0.5,
        -195
    )

Main.BackgroundColor3 =
    Color3.fromRGB(
        18,
        18,
        24
    )

Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui

local MainCorner =
    Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(0, 14)

MainCorner.Parent = Main

local MainStroke =
    Instance.new("UIStroke")

MainStroke.Thickness = 1

MainStroke.Color =
    Color3.fromRGB(
        65,
        65,
        80
    )

MainStroke.Transparency = 0.25
MainStroke.Parent = Main

--//====================================================
--// TOP
--//====================================================

local Top =
    Instance.new("Frame")

Top.Size =
    UDim2.new(
        1,
        0,
        0,
        50
    )

Top.BackgroundColor3 =
    Color3.fromRGB(
        26,
        26,
        34
    )

Top.BorderSizePixel = 0
Top.Active = true
Top.Parent = Main

local TopCorner =
    Instance.new("UICorner")

TopCorner.CornerRadius =
    UDim.new(0, 14)

TopCorner.Parent = Top

local Title =
    Instance.new("TextLabel")

Title.Size =
    UDim2.new(
        1,
        -65,
        1,
        0
    )

Title.Position =
    UDim2.fromOffset(
        16,
        0
    )

Title.BackgroundTransparency = 1
Title.Text = "VNDT"

Title.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        250
    )

Title.TextSize = 22
Title.Font = Enum.Font.GothamBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent = Top

local Minimize =
    Instance.new("TextButton")

Minimize.Size =
    UDim2.fromOffset(
        38,
        32
    )

Minimize.Position =
    UDim2.new(
        1,
        -46,
        0.5,
        -16
    )

Minimize.BackgroundColor3 =
    Color3.fromRGB(
        42,
        42,
        54
    )

Minimize.BorderSizePixel = 0
Minimize.Text = "—"

Minimize.TextColor3 =
    Color3.new(
        1,
        1,
        1
    )

Minimize.TextSize = 18
Minimize.Font = Enum.Font.GothamBold
Minimize.Parent = Top

--//====================================================
--// SCROLL
--//====================================================

local Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(
        8,
        58
    )

Scroll.Size =
    UDim2.new(
        1,
        -16,
        1,
        -66
    )

Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6

Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

Scroll.CanvasSize =
    UDim2.fromOffset(0, 0)

Scroll.ScrollingDirection =
    Enum.ScrollingDirection.Y

Scroll.Parent = Main

local Layout =
    Instance.new("UIListLayout")

Layout.Padding =
    UDim.new(0, 7)

Layout.SortOrder =
    Enum.SortOrder.LayoutOrder

Layout.Parent = Scroll

local Padding =
    Instance.new("UIPadding")

Padding.PaddingLeft =
    UDim.new(0, 4)

Padding.PaddingRight =
    UDim.new(0, 4)

Padding.PaddingTop =
    UDim.new(0, 4)

Padding.PaddingBottom =
    UDim.new(0, 10)

Padding.Parent = Scroll

--//====================================================
--// SECTION
--//====================================================

local function CreateSection(Text)

    local Label =
        Instance.new("TextLabel")

    Label.Size =
        UDim2.new(
            1,
            -8,
            0,
            28
        )

    Label.BackgroundTransparency = 1
    Label.Text = Text

    Label.TextColor3 =
        Color3.fromRGB(
            170,
            170,
            185
        )

    Label.TextSize = 12
    Label.Font = Enum.Font.GothamBold

    Label.TextXAlignment =
        Enum.TextXAlignment.Left

    Label.Parent = Scroll
end

--//====================================================
--// TOGGLE
--//====================================================

local function CreateToggle(
    Text,
    Default,
    Callback
)

    local Enabled =
        Default

    local Button =
        Instance.new("TextButton")

    Button.Size =
        UDim2.new(
            1,
            -8,
            0,
            44
        )

    Button.BackgroundColor3 =
        Color3.fromRGB(
            31,
            31,
            40
        )

    Button.BorderSizePixel = 0
    Button.Text = ""
    Button.AutoButtonColor = false
    Button.Parent = Scroll

    local Corner =
        Instance.new("UICorner")

    Corner.CornerRadius =
        UDim.new(0, 10)

    Corner.Parent = Button

    local Label =
        Instance.new("TextLabel")

    Label.Size =
        UDim2.new(
            1,
            -90,
            1,
            0
        )

    Label.Position =
        UDim2.fromOffset(
            12,
            0
        )

    Label.BackgroundTransparency = 1
    Label.Text = Text

    Label.TextColor3 =
        Color3.fromRGB(
            235,
            235,
            242
        )

    Label.TextSize = 14
    Label.Font = Enum.Font.GothamMedium

    Label.TextXAlignment =
        Enum.TextXAlignment.Left

    Label.Parent = Button

    local State =
        Instance.new("TextLabel")

    State.Size =
        UDim2.fromOffset(
            58,
            28
        )

    State.Position =
        UDim2.new(
            1,
            -70,
            0.5,
            -14
        )

    State.BorderSizePixel = 0

    State.TextColor3 =
        Color3.new(
            1,
            1,
            1
        )

    State.TextSize = 12
    State.Font = Enum.Font.GothamBold
    State.Parent = Button

    local StateCorner =
        Instance.new("UICorner")

    StateCorner.CornerRadius =
        UDim.new(1, 0)

    StateCorner.Parent = State

    local function Refresh()

        if Enabled then

            State.Text = "ON"

            State.BackgroundColor3 =
                Color3.fromRGB(
                    45,
                    165,
                    105
                )

        else

            State.Text = "OFF"

            State.BackgroundColor3 =
                Color3.fromRGB(
                    85,
                    85,
                    100
                )
        end
    end

    Refresh()

    Button.Activated:Connect(
        function()

            Enabled =
                not Enabled

            Refresh()

            Callback(
                Enabled
            )
        end
    )
end

--//====================================================
--// AUTOMATION UI
--//====================================================

CreateSection("AUTOMATION")

CreateToggle(
    "Auto Buy All - 0.05s",
    AUTO_BUY,
    function(Value)

        AUTO_BUY = Value
    end
)

CreateToggle(
    "Market / Store Route",
    AUTO_ROUTE,
    function(Value)

        AUTO_ROUTE = Value
    end
)

CreateToggle(
    "Auto Report After Store",
    AUTO_REPORT,
    function(Value)

        AUTO_REPORT = Value
        ReportBusy = false
    end
)

CreateToggle(
    "Auto Take",
    AUTO_TAKE,
    function(Value)

        AUTO_TAKE = Value
    end
)

CreateToggle(
    "Auto Give",
    AUTO_GIVE,
    function(Value)

        AUTO_GIVE = Value
    end
)

CreateToggle(
    "Auto Freezer 30s / 2m",
    AUTO_FREEZER,
    function(Value)

        AUTO_FREEZER = Value
    end
)

CreateToggle(
    "Hide All Popup Text",
    AUTO_HIDE_POPUPS,
    function(Value)

        AUTO_HIDE_POPUPS =
            Value

        if Value then

            task.defer(
                ScanPopupText
            )
        end
    end
)

--//====================================================
--// UPGRADES
--//====================================================

CreateSection("UPGRADES")

CreateToggle(
    "Auto Upgrade All",
    AUTO_UPGRADES,
    function(Value)

        AUTO_UPGRADES = Value
    end
)

--//====================================================
--// UTANG / LISTA
--//====================================================

CreateSection("UTANG / LISTA")

CreateToggle(
    "Auto Accept Utang",
    AUTO_UTANG,
    function(Value)

        AUTO_UTANG = Value

        if Value then

            task.defer(
                AutoAcceptUtang
            )
        end
    end
)

CreateToggle(
    "Auto NO Utang",
    AUTO_NO_UTANG,
    function(Value)

        AUTO_NO_UTANG = Value

        if Value then

            LastUtangClick = 0

            task.defer(
                HandleUtangPrompt
            )
        end
    end
)

CreateToggle(
    "Auto Singil All - 2 Sec",
    AUTO_SINGIL,
    function(Value)

        AUTO_SINGIL = Value

        if Value then

            LastSingilTime = 0
            SingilBusy = false

            task.defer(function()

                OpenLista()

                task.wait(0.15)

                HideListaUI()
            end)

        else

            SingilBusy = false

            RestoreListaUI()
        end
    end
)

--//====================================================
--// DRAG MOBILE + PC
--//====================================================

local Dragging = false
local DragInput = nil
local DragStart = nil
local StartPosition = nil

local function UpdateDrag(Input)

    local Delta =
        Input.Position
        - DragStart

    Main.Position =
        UDim2.new(
            StartPosition.X.Scale,
            StartPosition.X.Offset + Delta.X,
            StartPosition.Y.Scale,
            StartPosition.Y.Offset + Delta.Y
        )
end

Top.InputBegan:Connect(
    function(Input)

        if
            Input.UserInputType
            == Enum.UserInputType.MouseButton1
            or
            Input.UserInputType
            == Enum.UserInputType.Touch
        then

            Dragging = true
            DragStart = Input.Position
            StartPosition = Main.Position

            Input.Changed:Connect(
                function()

                    if
                        Input.UserInputState
                        == Enum.UserInputState.End
                    then

                        Dragging = false
                    end
                end
            )
        end
    end
)

Top.InputChanged:Connect(
    function(Input)

        if
            Input.UserInputType
            == Enum.UserInputType.MouseMovement
            or
            Input.UserInputType
            == Enum.UserInputType.Touch
        then

            DragInput = Input
        end
    end
)

UserInputService.InputChanged:Connect(
    function(Input)

        if Dragging
        and Input == DragInput
        then

            UpdateDrag(
                Input
            )
        end
    end
)

--//====================================================
--// MINIMIZE
--//====================================================

local Minimized = false

Minimize.Activated:Connect(
    function()

        Minimized =
            not Minimized

        Scroll.Visible =
            not Minimized

        if Minimized then

            Main.Size =
                UDim2.fromOffset(
                    300,
                    50
                )

            Minimize.Text = "+"

        else

            Main.Size =
                UDim2.fromOffset(
                    300,
                    390
                )

            Minimize.Text = "—"
        end
    end
)