-- ConfigUI.lua - Configuration interface for PlayerKillAnnounce
-- This adds a graphical user interface for all settings of the addon
local configFrame = nil

-- Add this near other default settings
PKA_ShowTooltipKillInfo = true -- New default setting

-- Default messages as fallbacks
local PlayerKillMessageDefault = PlayerKillMessageDefault or "Enemyplayername killed!"
local KillStreakEndedMessageDefault = KillStreakEndedMessageDefault or "My kill streak of STREAKCOUNT has ended!"
local NewStreakRecordMessageDefault = NewStreakRecordMessageDefault or "NEW PERSONAL BEST: Kill streak of STREAKCOUNT!"
local NewMultiKillRecordMessageDefault = NewMultiKillRecordMessageDefault or
    "NEW PERSONAL BEST: Multi-kill of MULTIKILLCOUNT!"

local PKA_CONFIG_HEADER_R = 1.0
local PKA_CONFIG_HEADER_G = 0.82
local PKA_CONFIG_HEADER_B = 0.0

local SECTION_TOP_MARGIN = 30
local SECTION_SPACING = 40
local HEADER_ELEMENT_SPACING = 15
local CHECKBOX_SPACING = 5
local FIELD_SPACING = 5
local BUTTON_BOTTOM_MARGIN = 20

PKA_EnableKillSounds = true

local function ShowResetStatsConfirmation()
    StaticPopupDialogs["PKA_RESET_STATS"] = {
        text = "Are you sure you want to reset all kill statistics? This cannot be undone.",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            PKA_CurrentKillStreak = 0
            PKA_HighestKillStreak = 0
            PKA_MultiKillCount = 0
            PKA_HighestMultiKill = 0
            PKA_KillCounts = {}
            PKA_SaveSettings()
            PKA_UpdateConfigStats()
            print("All kill statistics have been reset!")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("PKA_RESET_STATS")
end

local function ShowResetDefaultsConfirmation()
    StaticPopupDialogs["PKA_RESET_DEFAULTS"] = {
        text = "Are you sure you want to reset all settings to defaults? This will not affect your kill statistics.",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            PKA_KillAnnounceMessage = PlayerKillMessageDefault
            PKA_KillStreakEndedMessage = KillStreakEndedMessageDefault
            PKA_NewStreakRecordMessage = NewStreakRecordMessageDefault
            PKA_NewMultiKillRecordMessage = NewMultiKillRecordMessageDefault
            PKA_EnableKillAnnounce = true
            PKA_EnableRecordAnnounce = true
            PKA_MultiKillThreshold = 3

            -- Update UI with reset values
            if configFrame then
                PKA_UpdateConfigUI()
            end

            PKA_SaveSettings()
            print("All settings have been reset to default values!")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("PKA_RESET_DEFAULTS")
end

local function CreateSectionHeader(parent, text, xOffset, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    header:SetText(text)
    header:SetTextColor(PKA_CONFIG_HEADER_R, PKA_CONFIG_HEADER_G, PKA_CONFIG_HEADER_B)


    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetSize(parent:GetWidth() - (xOffset * 2), 1)
    line:SetColorTexture(0.5, 0.5, 0.5, 0.7)

    return header, line
end

local function CreateInputField(parent, labelText, width, initialValue, onTextChangedFunc)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 50)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    label:SetText(labelText)

    local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    editBox:SetSize(width - 20, 20)
    editBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -5)
    editBox:SetAutoFocus(false)
    editBox:SetText(initialValue or "")

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and onTextChangedFunc then
            onTextChangedFunc(self:GetText())
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(initialValue)
        self:ClearFocus()
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if onTextChangedFunc then
            onTextChangedFunc(self:GetText())
        end
        self:ClearFocus()
    end)

    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if onTextChangedFunc then
            onTextChangedFunc(self:GetText())
        end
    end)

    return container, editBox
end

local function CreateCheckbox(parent, labelText, initialValue, onClickFunc)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    checkbox:SetChecked(initialValue)
    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        onClickFunc(checked)
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
    label:SetText(labelText)

    return checkbox, label
end

local function CreateButton(parent, text, width, height, onClickFunc)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    button:SetScript("OnClick", onClickFunc)

    return button
end

local function EnsureDefaultValues()
    if not PKA_KillAnnounceMessage then PKA_KillAnnounceMessage = PlayerKillMessageDefault end
    if not PKA_KillStreakEndedMessage then PKA_KillStreakEndedMessage = KillStreakEndedMessageDefault end
    if not PKA_NewStreakRecordMessage then PKA_NewStreakRecordMessage = NewStreakRecordMessageDefault end
    if not PKA_NewMultiKillRecordMessage then PKA_NewMultiKillRecordMessage = NewMultiKillRecordMessageDefault end
    if PKA_EnableKillAnnounce == nil then PKA_EnableKillAnnounce = true end
    if PKA_EnableRecordAnnounce == nil then PKA_EnableRecordAnnounce = true end
    if PKA_MultiKillThreshold == nil then PKA_MultiKillThreshold = 3 end
    if PKA_ShowTooltipKillInfo == nil then PKA_ShowTooltipKillInfo = true end
end

local function CreateAnnouncementSection(parent, yOffset)
    local header, line = CreateSectionHeader(parent, "Announcement Settings", 20, yOffset)
    local currentY = yOffset

    -- Auto BG Mode checkbox with tooltip
    local autoBGMode, autoBGModeLabel = CreateCheckbox(parent, "Auto Battleground Mode (No announcements, only killing blows count)",
        PKA_AutoBattlegroundMode, function(checked)
            PKA_AutoBattlegroundMode = checked
            PKA_SaveSettings()
            PKA_CheckBattlegroundStatus()
        end)
    autoBGMode:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -HEADER_ELEMENT_SPACING)
    parent.autoBGMode = autoBGMode

    -- Add tooltip for Auto BG Mode
    autoBGMode:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto Battleground Mode")
        GameTooltip:AddLine("Automatically detects when you enter battlegrounds.", 1, 1, 1, true)
        GameTooltip:AddLine("In battlegrounds:", 1, 1, 1, true)
        GameTooltip:AddLine("• Only your or your pet's killing blows count", 1, 1, 1, true)
        GameTooltip:AddLine("• No messages are posted to group chat", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoBGMode:SetScript("OnLeave", function() GameTooltip:Hide() end)


    local manualBGMode, manualBGModeLabel = CreateCheckbox(parent, "Force Battleground Mode",
        PKA_BattlegroundMode, function(checked)
            PKA_BattlegroundMode = checked
            PKA_SaveSettings()
            PKA_CheckBattlegroundStatus()
        end)
    manualBGMode:SetPoint("TOPLEFT", autoBGMode, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 5)
    parent.manualBGMode = manualBGMode

    -- Add tooltip for manual BG Mode
    manualBGMode:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Force Battleground Mode")
        GameTooltip:AddLine("Enable battleground conditions anywhere in the world.", 1, 1, 1, true)
        GameTooltip:AddLine("When enabled:", 1, 1, 1, true)
        GameTooltip:AddLine("• Only your or your pet's killing blows are counted", 1, 1, 1, true)
        GameTooltip:AddLine("• Prevents chat spam in crowded PvP situations", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    manualBGMode:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Add tooltip checkbox right after battleground mode
    local tooltipKillInfo, tooltipKillInfoLabel = CreateCheckbox(parent,
        "Show kill statistics in enemy player tooltips",
        PKA_ShowTooltipKillInfo,
        function(checked)
            PKA_ShowTooltipKillInfo = checked
            PKA_SaveSettings()
        end)
    tooltipKillInfo:SetPoint("TOPLEFT", manualBGMode, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 5)
    parent.tooltipKillInfo = tooltipKillInfo

    -- Add tooltip explanation
    tooltipKillInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Enemy Player Tooltips")
        GameTooltip:AddLine("When enabled, shows your kill statistics for enemy players when you mouse over them.", 1, 1, 1, true)
        GameTooltip:AddLine("Displays kill count over this player.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tooltipKillInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local enableKillAnnounce, enableKillAnnounceLabel = CreateCheckbox(parent, "Enable kill announcements to party chat",
        PKA_EnableKillAnnounce, function(checked)
            PKA_EnableKillAnnounce = checked
            PKA_SaveSettings()
        end)
    enableKillAnnounce:SetPoint("TOPLEFT", tooltipKillInfo, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 5)
    parent.enableKillAnnounce = enableKillAnnounce

    -- Rest of the function remains the same...
    local enableRecordAnnounce, enableRecordAnnounceLabel = CreateCheckbox(parent, "Announce new records to party chat",
        PKA_EnableRecordAnnounce, function(checked)
            PKA_EnableRecordAnnounce = checked
            PKA_SaveSettings()
        end)
    enableRecordAnnounce:SetPoint("TOPLEFT", enableKillAnnounce, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 5)
    parent.enableRecordAnnounce = enableRecordAnnounce


    local enableKillSounds, enableKillSoundsLabel = CreateCheckbox(parent, "Enable multi-kill sound effects",
        PKA_EnableKillSounds, function(checked)
            PKA_EnableKillSounds = checked
            PKA_SaveSettings()
        end)
    enableKillSounds:SetPoint("TOPLEFT", enableRecordAnnounce, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 5)
    parent.enableKillSounds = enableKillSounds

    return 220
end

local function CreateMessageTemplatesSection(parent, yOffset)
    -- Add extra spacing before the Party Messages section
    yOffset = yOffset - 35

    local header, line = CreateSectionHeader(parent, "Party Messages", 20, yOffset)

    local killMsgContainer, killMsgEditBox = CreateInputField(
        parent,
        "Kill announcement message (\"Enemyplayername\" will be replaced with the player's name):",
        560,
        PKA_KillAnnounceMessage,
        function(text)
            PKA_KillAnnounceMessage = text
            PKA_SaveSettings()
        end
    )
    killMsgContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -HEADER_ELEMENT_SPACING)

    local streakEndedContainer, streakEndedEditBox = CreateInputField(
        parent,
        "Kill streak ended message (\"STREAKCOUNT\" will be replaced with the streak count):",
        560,
        PKA_KillStreakEndedMessage,
        function(text)
            PKA_KillStreakEndedMessage = text
            PKA_SaveSettings()
        end
    )
    streakEndedContainer:SetPoint("TOPLEFT", killMsgContainer, "BOTTOMLEFT", 0, -FIELD_SPACING)

    local newStreakContainer, newStreakEditBox = CreateInputField(
        parent,
        "New streak record message (\"STREAKCOUNT\" will be replaced with the streak count):",
        560,
        PKA_NewStreakRecordMessage,
        function(text)
            PKA_NewStreakRecordMessage = text
            PKA_SaveSettings()
        end
    )
    newStreakContainer:SetPoint("TOPLEFT", streakEndedContainer, "BOTTOMLEFT", 0, -FIELD_SPACING)

    local multiKillContainer, multiKillEditBox = CreateInputField(
        parent,
        "New multi-kill record message (\"MULTIKILLCOUNT\" will be replaced with the count):",
        560,
        PKA_NewMultiKillRecordMessage,
        function(text)
            PKA_NewMultiKillRecordMessage = text
            PKA_SaveSettings()
        end
    )
    multiKillContainer:SetPoint("TOPLEFT", newStreakContainer, "BOTTOMLEFT", 0, -FIELD_SPACING)

    -- Add section header for Multi-Kill settings
    local multiKillHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    multiKillHeader:SetPoint("TOPLEFT", multiKillContainer, "BOTTOMLEFT", 0, -20)
    multiKillHeader:SetText("Multi-Kill Announce")

    -- Add the threshold slider and description
    local slider = CreateFrame("Slider", "PKA_MultiKillThresholdSlider", parent, "OptionsSliderTemplate")
    slider:SetWidth(200)
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", multiKillHeader, "BOTTOMLEFT", 40, -20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(2, 10)
    slider:SetValueStep(1)
    slider:SetValue(PKA_MultiKillThreshold or 3)
    getglobal(slider:GetName() .. "Low"):SetText("Double")
    getglobal(slider:GetName() .. "High"):SetText("Deca")
    getglobal(slider:GetName() .. "Text"):SetText("Multi-Kill Announce Threshold: " .. (PKA_MultiKillThreshold or 3))
    parent.multiKillSlider = slider

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        self:SetValue(value)
        getglobal(self:GetName() .. "Text"):SetText("Multi-Kill Announce Threshold: " .. value)
        PKA_MultiKillThreshold = value
        PKA_SaveSettings()
    end)

    -- Slider description
    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -5)
    desc:SetText("Set the minimum multi-kill count to announce in party chat")
    desc:SetJustifyH("LEFT")
    desc:SetWidth(350)

    -- Return UI elements for potential updates
    return {
        killMsg = killMsgEditBox,
        streakEnded = streakEndedEditBox,
        newStreak = newStreakEditBox,
        multiKill = multiKillEditBox,
        multiKillSlider = slider,
        multiKillDesc = desc
    }
end

local function CreateActionButtons(parent)
    -- Create a centered container for buttons
    local buttonContainer = CreateFrame("Frame", nil, parent)
    buttonContainer:SetSize(200, 200)  -- Fixed width container
    buttonContainer:SetPoint("CENTER")

    -- Consistent button sizes and spacing
    local buttonWidth = 160  -- Fixed width for all buttons
    local buttonHeight = 25  -- Fixed height for all buttons
    local buttonSpacing = 15 -- Space between buttons

    -- Create buttons with consistent sizing
    local showStatsBtn = CreateButton(buttonContainer, "Show Statistics", buttonWidth, buttonHeight, function()
        PKA_CreateStatisticsFrame()
    end)

    local killsListBtn = CreateButton(buttonContainer, "Show Kills List", buttonWidth, buttonHeight, function()
        PKA_CreateKillStatsFrame()
    end)

    local resetStatsBtn = CreateButton(buttonContainer, "Reset Statistics", buttonWidth, buttonHeight, function()
        ShowResetStatsConfirmation()
    end)

    local defaultsBtn = CreateButton(buttonContainer, "Reset to Defaults", buttonWidth, buttonHeight, function()
        ShowResetDefaultsConfirmation()
    end)

    -- Stack buttons vertically with even spacing
    showStatsBtn:SetPoint("TOP", buttonContainer, "TOP", 0, 0)
    killsListBtn:SetPoint("TOP", showStatsBtn, "BOTTOM", 0, -buttonSpacing)
    resetStatsBtn:SetPoint("TOP", killsListBtn, "BOTTOM", 0, -buttonSpacing)
    defaultsBtn:SetPoint("TOP", resetStatsBtn, "BOTTOM", 0, -buttonSpacing)

    return {
        showStatsBtn = showStatsBtn,
        killsListBtn = killsListBtn,
        resetBtn = resetStatsBtn,
        defaultsBtn = defaultsBtn
    }
end

local function CreateMainFrame()
    local frame = CreateFrame("Frame", "PKAConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 600) -- Reduced from 650 to 600
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Add a close button handler
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    tinsert(UISpecialFrames, "PKAConfigFrame")

    frame.TitleText:SetText("PlayerKillAnnounce Configuration")

    return frame
end

function PKA_UpdateConfigStats()
    if configFrame and configFrame.statsText then
        configFrame.statsText:SetText(string.format(
            "Current Kill Streak: %d\nHighest Kill Streak: %d\nHighest Multi-Kill: %d",
            PKA_CurrentKillStreak or 0,
            PKA_HighestKillStreak or 0,
            PKA_HighestMultiKill or 0
        ))
    end
end

function PKA_UpdateConfigUI()
    if not configFrame then return end

    if configFrame.enableKillAnnounce then
        configFrame.enableKillAnnounce:SetChecked(PKA_EnableKillAnnounce)
    end

    if configFrame.enableRecordAnnounce then
        configFrame.enableRecordAnnounce:SetChecked(PKA_EnableRecordAnnounce)
    end

    if configFrame.multiKillSlider then
        configFrame.multiKillSlider:SetValue(PKA_MultiKillThreshold)
        -- Also update the slider text
        local sliderName = configFrame.multiKillSlider:GetName()
        if sliderName then
            getglobal(sliderName .. "Text"):SetText("Multi-Kill Announce Threshold: " .. PKA_MultiKillThreshold)
        end
    end

    if configFrame.editBoxes then
        configFrame.editBoxes.killMsg:SetText(PKA_KillAnnounceMessage)
        configFrame.editBoxes.streakEnded:SetText(PKA_KillStreakEndedMessage)
        configFrame.editBoxes.newStreak:SetText(PKA_NewStreakRecordMessage)
        configFrame.editBoxes.multiKill.SetText(PKA_NewMultiKillRecordMessage)
    end

    if configFrame.tooltipKillInfo then
        configFrame.tooltipKillInfo:SetChecked(PKA_ShowTooltipKillInfo)
    end

    PKA_UpdateConfigStats()
end

local function CreateTabSystem(parent)
    local tabWidth = 85  -- Smaller initial width
    local tabHeight = 32
    local tabs = {}
    local tabFrames = {}

    local tabContainer = CreateFrame("Frame", nil, parent)
    tabContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 7, -25)
    tabContainer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -7, 7)

    -- Create tab buttons
    local tabNames = {"General", "Messages", "Reset"}
    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", parent:GetName().."Tab"..i, parent, "CharacterFrameTabButtonTemplate")
        tab:SetText(name)
        tab:SetID(i)

        -- Set initial size
        tab:SetSize(tabWidth, tabHeight)

        -- Get references to all tab textures
        local tabMiddle = _G[tab:GetName().."Middle"]
        local tabLeft = _G[tab:GetName().."Left"]
        local tabRight = _G[tab:GetName().."Right"]
        local tabSelectedMiddle = _G[tab:GetName().."SelectedMiddle"]
        local tabSelectedLeft = _G[tab:GetName().."SelectedLeft"]
        local tabSelectedRight = _G[tab:GetName().."SelectedRight"]
        local tabText = _G[tab:GetName().."Text"]

        -- Fix texture sizes immediately
        if tabMiddle then
            tabMiddle:ClearAllPoints()
            tabMiddle:SetPoint("LEFT", tabLeft, "RIGHT", 0, 0)
            tabMiddle:SetWidth(tabWidth - 31)
        end
        if tabSelectedMiddle then
            tabSelectedMiddle:ClearAllPoints()
            tabSelectedMiddle:SetPoint("LEFT", tabSelectedLeft, "RIGHT", 0, 0)
            tabSelectedMiddle:SetWidth(tabWidth - 31)
        end

        -- Position tabs with proper spacing
        if i == 1 then
            tab:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 5, 0)
        else
            tab:SetPoint("LEFT", tabs[i-1], "RIGHT", -8, 0)
        end

        -- Force proper text positioning
        if tabText then
            tabText:ClearAllPoints()
            tabText:SetPoint("CENTER", tab, "CENTER", 0, 2)
            tabText:SetJustifyH("CENTER")
            tabText:SetWidth(tabWidth - 40)
        end

        -- Create content frame for this tab
        local contentFrame = CreateFrame("Frame", nil, tabContainer)
        contentFrame:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", 0, -5)
        contentFrame:SetPoint("BOTTOMRIGHT", tabContainer, "BOTTOMRIGHT")
        contentFrame:Hide()

        tabFrames[i] = contentFrame
        table.insert(tabs, tab)

        -- Set up click handler
        tab:SetScript("OnClick", function()
            PanelTemplates_SetTab(parent, i)
            for index, frame in ipairs(tabFrames) do
                if index == i then
                    frame:Show()
                    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
                else
                    frame:Hide()
                end
            end
        end)
    end

    parent.tabs = tabs
    parent.numTabs = #tabs
    PanelTemplates_SetNumTabs(parent, #tabs)
    PanelTemplates_SetTab(parent, 1)
    tabFrames[1]:Show()

    -- Force resize and texture setup
    for i, tab in ipairs(tabs) do
        PanelTemplates_TabResize(tab, 0)
    end

    return tabFrames
end

function PKA_CreateConfigFrame()
    if configFrame then
        configFrame:Show()
        return
    end

    EnsureDefaultValues()
    configFrame = CreateMainFrame()
    PKA_FrameManager:RegisterFrame(configFrame, "ConfigUI")

    -- Create tab system
    local tabFrames = CreateTabSystem(configFrame)

    -- General Tab (Tab 1)
    local currentY = -10
    local announcementHeight = CreateAnnouncementSection(tabFrames[1], currentY)

    -- Messages Tab (Tab 2)
    configFrame.editBoxes = CreateMessageTemplatesSection(tabFrames[2], -10)

    -- Reset Tab (Tab 3) - Add this section
    local resetButtons = CreateActionButtons(tabFrames[3])
    configFrame.resetButtons = resetButtons

    -- Initialize first tab
    PanelTemplates_SetTab(configFrame, 1)
    tabFrames[1]:Show()

    return configFrame
end

function PKA_CreateConfigUI()
    if configFrame then
        PKA_FrameManager:ShowFrame("Config")
        return
    end

    PKA_CreateConfigFrame()
end

-- Hook into the slash command handler if it exists already
if not ConfigUI_OriginalSlashHandler and PKA_SlashCommandHandler then
    ConfigUI_OriginalSlashHandler = PKA_SlashCommandHandler

    function PKA_SlashCommandHandler(msg)
        local command, rest = msg:match("^(%S*)%s*(.-)$")
        command = string.lower(command or "")

        if command == "config" or command == "options" or command == "settings" then
            PKA_CreateConfigUI()
        elseif ConfigUI_OriginalSlashHandler then
            ConfigUI_OriginalSlashHandler(msg)
        else
            -- Fallback if original handler somehow became nil
            print("Error: Original command handler not found.")
            PrintSlashCommandUsage()
        end
    end
end

-- Only modify PrintSlashCommandUsage if we haven't done so already
if not ConfigUI_ModifiedPrintUsage then
    ConfigUI_ModifiedPrintUsage = true

    -- The main EventHandlers.lua file now includes all usage information
    -- No need to modify PrintSlashCommandUsage anymore
end
