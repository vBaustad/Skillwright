-- Skillwright - settings page (Interface Options -> AddOns -> Skillwright).
local ADDON, SW = ...
local DB = SW.DB
local BMC_URL = "buymeacoffee.com/vbaustad"

StaticPopupDialogs["SKILLWRIGHT_BMC"] = {
    text = "Thanks for using Skillwright!\nCopy the link below if you'd like to buy me a coffee.",
    button1 = CLOSE,
    hasEditBox = true, editBoxWidth = 260,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox
        if not eb then return end
        eb:SetText(BMC_URL); eb:HighlightText(); eb:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local panel
local function BuildOptions()
    if panel then return end
    panel = CreateFrame("Frame")
    panel.name = "Skillwright"
    -- Tidy the dashboard away while settings are up; the guide opens only on request (the
    -- "Show guide window" button below) so you can preview opacity / size / background live.
    panel:SetScript("OnShow", function()
        if SW.HideDashboard then SW.HideDashboard() end
    end)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16); title:SetText("Skillwright")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(520); sub:SetJustifyH("LEFT")
    sub:SetText("Profession leveling helper - the optimal craft path to max skill, with a live shopping list.")

    local function checkbox(x, y, label, get, set)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(26, 26); cb:SetPoint("TOPLEFT", x, y)
        local l = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        l:SetPoint("LEFT", cb, "RIGHT", 2, 0); l:SetText(label)
        cb:SetChecked(get())
        cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        return cb
    end

    local sec = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sec:SetPoint("TOPLEFT", 16, -52); sec:SetText("|cffe6b34dBehaviour|r")

    -- Left column
    checkbox(16, -76, "Open with the profession window",
        function() return DB().autoDock ~= false end,
        function(v) DB().autoDock = v end)
    checkbox(16, -102, "Attach to the profession window",
        function() return DB().attached ~= false end,
        function(v) DB().attached = v; if SW.ReAnchor then SW.ReAnchor() end end)
    checkbox(16, -128, "Show the minimap button",
        function() return not DB().hideMinimap end,
        function(v) DB().hideMinimap = not v; if SW.UpdateMinimap then SW.UpdateMinimap() end end)
    checkbox(16, -154, "Buy / Train buttons on vendors & trainers",
        function() return DB().contextButtons ~= false end,
        function(v) DB().contextButtons = v end)
    -- Right column
    checkbox(300, -76, "Show completed steps",
        function() return DB().showCompleted == true end,
        function(v) DB().showCompleted = v; if SW.Refresh then SW.Refresh() end end)
    checkbox(300, -102, "Lock window position",
        function() return DB().locked == true end,
        function(v) DB().locked = v end)
    checkbox(300, -128, "Atmospheric background",
        function() return DB().showBackground ~= false end,
        function(v) DB().showBackground = v; if SW.ApplyWindowSettings then SW.ApplyWindowSettings() end end)

    local sec2 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sec2:SetPoint("TOPLEFT", 16, -192); sec2:SetText("|cffe6b34dAppearance|r")

    local function slider(name, y, label, lowT, highT, lo, hi, step, get, set)
        local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
        s:SetWidth(220); s:SetPoint("TOPLEFT", 22, y)
        s:SetMinMaxValues(lo, hi); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
        _G[name .. "Low"]:SetText(lowT); _G[name .. "High"]:SetText(highT); _G[name .. "Text"]:SetText(label)
        s:SetValue(get())
        s:SetScript("OnValueChanged", function(_, v) set(v); if SW.ApplyWindowSettings then SW.ApplyWindowSettings() end end)
        return s
    end

    slider("SkillwrightAlphaSlider", -236, "Window opacity", "faint", "solid", 0.3, 1, 0.05,
        function() return DB().alpha or 1 end, function(v) DB().alpha = v end)
    slider("SkillwrightSceneSlider", -236, "Background strength", "subtle", "full", 0.2, 1, 0.05,
        function() return DB().sceneAlpha or 1 end, function(v) DB().sceneAlpha = v end)
    _G["SkillwrightSceneSlider"]:ClearAllPoints()
    _G["SkillwrightSceneSlider"]:SetPoint("TOPLEFT", 300, -236)
    slider("SkillwrightScaleSlider", -288, "Window size", "small", "large", 0.7, 1.3, 0.05,
        function() return DB().scale or 1 end, function(v) DB().scale = v end)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(170, 22); reset:SetPoint("TOPLEFT", 300, -288)
    reset:SetText("Reset window position")
    reset:SetScript("OnClick", function() if SW.ResetPosition then SW.ResetPosition() end end)

    -- Open the guide here so you can watch opacity / size / background change as you drag.
    local preview = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    preview:SetSize(170, 22); preview:SetPoint("TOPLEFT", 22, -322)
    preview:SetText("Show guide window")
    preview:SetScript("OnClick", function() if SW.EnsureGuide then SW.EnsureGuide() end end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -356)
    hint:SetText("|cffffd100/sw|r opens the dashboard, |cffffd100/sw guide|r the guide window.")

    -- "Buy me a coffee" support link.
    local coffee = CreateFrame("Button", nil, panel)
    coffee:SetSize(24, 24); coffee:SetPoint("BOTTOMLEFT", 16, 14)
    local ctex = coffee:CreateTexture(nil, "ARTWORK")
    ctex:SetAllPoints(); ctex:SetTexture("Interface\\AddOns\\Skillwright\\bmc-logo"); ctex:SetAlpha(0.7)
    local clbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clbl:SetPoint("LEFT", coffee, "RIGHT", 6, 0); clbl:SetText("|cff888888if you want to support|r")
    coffee:SetScript("OnEnter", function(self)
        ctex:SetAlpha(1); clbl:SetText("|cffffc840if you want to support|r")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Buy me a coffee", 1, 0.85, 0.2)
        GameTooltip:AddLine(BMC_URL, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to copy the link.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    coffee:SetScript("OnLeave", function()
        ctex:SetAlpha(0.7); clbl:SetText("|cff888888if you want to support|r"); GameTooltip:Hide()
    end)
    coffee:SetScript("OnClick", function() StaticPopup_Show("SKILLWRIGHT_BMC") end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "Skillwright")
        cat.ID = "Skillwright"
        Settings.RegisterAddOnCategory(cat)
        SW.optCategory = cat
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function SW.OpenOptions()
    BuildOptions()
    if Settings and Settings.OpenToCategory and SW.optCategory then
        Settings.OpenToCategory(SW.optCategory.ID or SW.optCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() BuildOptions() end)
