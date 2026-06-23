-- Skillwright - the dashboard (main hub): every profession this character has in one
-- place, with the guided ones first and clickable; plus the minimap button to open it.
local ADDON, SW = ...
local DB = SW.DB

local DW, ROW_H = 300, 34
local dash

-- ----- profession row -----
local function MakeRow(content, i)
    local r = content.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetSize(DW - 30, ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT", 5, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = r:CreateFontString(nil, "ARTWORK", "GameFontNormal"); r.name:SetPoint("TOPLEFT", 38, -4); r.name:SetJustifyH("LEFT")
    r.rank = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.rank:SetPoint("TOPRIGHT", -8, -5); r.rank:SetJustifyH("RIGHT")
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("BOTTOMLEFT", 38, 7); r.bar:SetPoint("BOTTOMRIGHT", -88, 7); r.bar:SetHeight(6)
    r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.barbg = r.bar:CreateTexture(nil, "BACKGROUND"); r.barbg:SetAllPoints(); r.barbg:SetColorTexture(0, 0, 0, 0.5)
    r.status = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"); r.status:SetPoint("BOTTOMRIGHT", -8, 6); r.status:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self) if self.guide then self.bg:SetColorTexture(1, 1, 1, 0.09) end end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, self.stripe and 0.03 or 0) end)
    r:SetScript("OnClick", function(self) if self.guide and SW.ToggleGuideFor then SW.ToggleGuideFor(self.profName) end end)
    content.rows[i] = r
    return r
end

local function BuildDash()
    if dash then return dash end
    local f = CreateFrame("Frame", "SkillwrightDashboard", UIParent, "BackdropTemplate")
    f:SetSize(DW, 300)
    f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pos = DB().dashPos or {}; pos.x = self:GetLeft(); pos.y = self:GetTop(); DB().dashPos = pos
    end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.06, 1)
    SW.Decorate(f)

    f.sceneBg = f:CreateTexture(nil, "BORDER")
    SW.ApplyScene(f.sceneBg)
    f.sceneBg:SetPoint("TOPLEFT", 4, -4); f.sceneBg:SetPoint("BOTTOMRIGHT", -4, 4)
    f.sceneBg:SetAlpha(1); f.sceneBg:SetVertexColor(0.78, 0.78, 0.84)

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetColorTexture(0.16, 0.13, 0.09, 0.95)
    header:SetPoint("TOPLEFT", 4, -4); header:SetPoint("TOPRIGHT", -4, -4); header:SetHeight(24)
    local hr = f:CreateTexture(nil, "ARTWORK")
    hr:SetColorTexture(0.5, 0.42, 0.28, 0.7); hr:SetHeight(1)
    hr:SetPoint("TOPLEFT", 4, -28); hr:SetPoint("TOPRIGHT", -4, -28)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", header, "LEFT", 8, 0); f.title:SetText("|c" .. SW.CREAM .. "Skillwright|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("RIGHT", header, "RIGHT", 2, 0)

    local cog = CreateFrame("Button", nil, f)
    cog:SetSize(16, 16); cog:SetPoint("RIGHT", close, "LEFT", 0, 0)
    cog:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    cog:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
    cog:SetScript("OnClick", function() if SW.OpenOptions then SW.OpenOptions() end end)
    cog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Settings", 1, 0.82, 0.3); GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.charFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.charFS:SetPoint("RIGHT", cog, "LEFT", -4, 0); f.charFS:SetJustifyH("RIGHT")

    local sf = CreateFrame("ScrollFrame", "SkillwrightDashScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -34); sf:SetPoint("BOTTOMRIGHT", -28, 12)
    f.scroll = sf
    local sbDiv = f:CreateTexture(nil, "ARTWORK")
    sbDiv:SetColorTexture(0.5, 0.42, 0.28, 0.6); sbDiv:SetWidth(1)
    sbDiv:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 4, 2); sbDiv:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -2)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(DW - 30, 10); content.rows = {}
    sf:SetScrollChild(content)
    f.content = content

    tinsert(UISpecialFrames, "SkillwrightDashboard")
    SW.RegisterWindow(f)
    SW.ApplyWindowSettings()
    f:Hide()
    dash = f
    return f
end

function SW.RefreshDashboard()
    if not dash then return end
    dash.charFS:SetText("|cffaaaaaa" .. (UnitName("player") or "") .. "|r")
    local c = dash.content
    local profs = SW.CharProfessions()
    local y = 4
    for i, p in ipairs(profs) do
        local r = MakeRow(c, i)
        r.profName, r.guide = p.name, p.hasGuide
        r.icon:SetTexture(SW.ProfIcon(p.name)); r.icon:SetDesaturated(not p.hasGuide)
        r.name:SetText((p.hasGuide and "|cffffffff" or "|cff888888") .. p.name .. "|r")
        r.rank:SetText(("|cffe8c66a%d|r|cff666666/%d|r"):format(p.rank, p.max))
        r.bar:SetMinMaxValues(0, (p.max and p.max > 0) and p.max or 1); r.bar:SetValue(p.rank)
        if p.hasGuide then r.bar:SetStatusBarColor(0.3, 0.65, 0.3) else r.bar:SetStatusBarColor(0.35, 0.35, 0.4) end
        local status = "|cff666666no guide yet|r"
        if p.hasGuide then status = "|cff7fc8ffopen guide|r"
        elseif SW.GATHERING[p.name] then status = "|cff888888gather to level|r" end
        r.status:SetText(status)
        r.stripe = (i % 2 == 0); r.bg:SetColorTexture(1, 1, 1, r.stripe and 0.03 or 0)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(c:GetWidth())
        r:Show()
        y = y + ROW_H + 2
    end
    for i = #profs + 1, #c.rows do c.rows[i]:Hide() end
    if #profs == 0 then
        local r = MakeRow(c, 1)
        r.profName, r.guide = nil, false
        r.icon:SetTexture(nil); r.rank:SetText(""); r.status:SetText("")
        r.name:SetText("|cff888888No professions learned yet.|r"); r.bg:SetColorTexture(0, 0, 0, 0)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -4); r:SetWidth(c:GetWidth()); r:Show()
        y = ROW_H
    end
    c:SetHeight(y + 4)
    dash:SetHeight(math.min((UIParent:GetHeight() or 768) - 100, 50 + y))
end

function SW.ShowDashboard()
    BuildDash()
    dash:ClearAllPoints()
    local pos = DB().dashPos
    if pos and pos.x then dash:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y) else dash:SetPoint("CENTER") end
    SW.RefreshDashboard(); dash:Show()
end

function SW.ToggleDashboard()
    BuildDash()
    if dash:IsShown() then dash:Hide() else SW.ShowDashboard() end
end

function SW.HideDashboard()
    if dash then dash:Hide() end
end

-- ----- minimap button -----
local mmb
local function UpdateMMBPos()
    if not mmb then return end
    local angle = math.rad(DB().minimapAngle or 210)
    mmb:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
end

function SW.UpdateMinimap()
    if not mmb then return end
    if DB().hideMinimap then mmb:Hide() else mmb:Show() end
end

local function BuildMinimap()
    if mmb then return end
    mmb = CreateFrame("Button", "SkillwrightMinimapButton", Minimap)
    mmb:SetSize(31, 31); mmb:SetFrameStrata("MEDIUM"); mmb:SetFrameLevel(8)
    mmb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mmb:RegisterForDrag("LeftButton")
    local icon = mmb:CreateTexture(nil, "BACKGROUND"); icon:SetSize(22, 22); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\Skillwright\\emblem_mm")
    local overlay = mmb:CreateTexture(nil, "OVERLAY"); overlay:SetSize(53, 53); overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mmb:SetScript("OnClick", function(_, b)
        if b == "RightButton" then if SW.OpenOptions then SW.OpenOptions() end else SW.ToggleDashboard() end
    end)
    mmb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Skillwright", 1, 0.82, 0.3)
        GameTooltip:AddLine("Left-click: dashboard", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    mmb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mmb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            DB().minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            UpdateMMBPos()
        end)
    end)
    mmb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    UpdateMMBPos()
    SW.UpdateMinimap()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" then
        BuildMinimap()
    elseif e == "SKILL_LINES_CHANGED" then
        if dash and dash:IsShown() then SW.RefreshDashboard() end
    end
end)
