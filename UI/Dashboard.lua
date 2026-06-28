-- Skillwright - the dashboard (main hub): every profession this character has in one
-- place, with the guided ones first and clickable; plus the minimap button to open it.
local ADDON, SW = ...
local DB = SW.DB

local DW, ROW_H = 462, 34   -- wide enough for two profession columns
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
    r:SetScript("OnEnter", function(self)
        if self.guide then self.bg:SetColorTexture(1, 1, 1, 0.09) end
        if not self.profName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.profName, 1, 0.82, 0.3)
        local eff = SW.ProfEffort and SW.ProfEffort(self.profName, self._rank or 0)
        if eff then
            if eff.gathering then
                GameTooltip:AddLine(("Gather to 300 — %d zone segment(s) left."):format(eff.segments or 0), 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine(("%d steps  ·  ~%d crafts  ·  %d mats to 300"):format(eff.steps or 0, eff.crafts or 0, eff.mats or 0), 0.8, 0.8, 0.8)
            end
        end
        GameTooltip:AddLine(self._learned and "Click to open the guide." or "Click to preview the full path.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, self.stripe and 0.03 or 0)
        GameTooltip:Hide()
    end)
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
    content:SetSize(DW - 40, 10); content.rows = {}   -- matches the scroll viewport (no h-scroll)
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
    local profs = SW.AllProfessions()
    -- Two columns so all 12 professions fit without a tall scroll.
    local cols, gap = 2, 10
    local colW = math.floor((c:GetWidth() - gap * (cols - 1)) / cols)
    for i, p in ipairs(profs) do
        local r = MakeRow(c, i)
        local col = (i - 1) % cols
        local rowIdx = math.floor((i - 1) / cols)
        -- Every profession is openable: learned ones show your progress; unlearned ones grey
        -- out but still open the guide so you can preview / plan them.
        r.profName, r.guide = p.name, true
        r._rank, r._learned, r._gathering = p.rank, p.learned, p.gathering
        r.icon:SetTexture(SW.ProfIcon(p.name)); r.icon:SetDesaturated(not p.learned)
        r.name:SetText((p.learned and "|cffffffff" or "|cff777777") .. p.name .. "|r")
        if p.learned then
            local mx = p.max > 0 and p.max or 300
            r.rank:SetText(("|cffe8c66a%d|r|cff666666/%d|r"):format(p.rank, mx))
            r.bar:Show(); r.barbg:Show()
            r.bar:SetMinMaxValues(0, mx); r.bar:SetValue(p.rank)
            r.bar:SetStatusBarColor(p.gathering and 0.45 or 0.3, p.gathering and 0.5 or 0.65, p.gathering and 0.6 or 0.3)
            r.status:SetText(p.gathering and "|cff888888gather to level|r" or "|cff7fc8ffopen guide|r")
        else
            r.rank:SetText("|cff666666not learned|r")
            r.bar:Hide(); r.barbg:Hide()
            r.status:SetText("|cff8a7fb0preview|r")
        end
        r.stripe = (rowIdx % 2 == 1); r.bg:SetColorTexture(1, 1, 1, r.stripe and 0.03 or 0)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", col * (colW + gap), -(4 + rowIdx * (ROW_H + 2)))
        r:SetWidth(colW)
        r:Show()
    end
    for i = #profs + 1, #c.rows do c.rows[i]:Hide() end
    local nrows = math.ceil(#profs / cols)
    local totalH = 4 + nrows * (ROW_H + 2)
    c:SetHeight(totalH + 4)
    dash:SetHeight(math.min((UIParent:GetHeight() or 768) - 100, 50 + totalH))
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

-- Global for the keybinding (Bindings.xml).
function SkillwrightToggleDashboard() SW.ToggleDashboard() end

function SW.HideDashboard()
    if dash then dash:Hide() end
end

-- ----- minimap button -----
local mmb
local function UpdateMMBPos()
    if not mmb then return end
    local angle = math.rad(DB().minimapAngle or 210)
    -- Hug the minimap ring; scales with the minimap's actual size so the button
    -- doesn't drift off the edge when the minimap is resized.
    local r = (Minimap:GetWidth() / 2) + 5
    mmb:ClearAllPoints()
    mmb:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(angle), r * math.sin(angle))
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
    local icon = mmb:CreateTexture(nil, "BACKGROUND"); icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local overlay = mmb:CreateTexture(nil, "OVERLAY"); overlay:SetSize(53, 53); overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    -- Hover glow, matching Blizzard's own minimap buttons.
    mmb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
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

-- Optional LibDataBroker launcher. We don't bundle the lib (Skillwright stays dependency-free),
-- so this only activates when another addon has already provided it - giving Titan Panel /
-- ChocolateBar users a Skillwright launcher. Runs at login, when every addon's libs are loaded.
local function SetupBroker()
    if SW._broker then return end
    local LDB = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    SW._broker = LDB:NewDataObject("Skillwright", {
        type = "launcher",
        icon = "Interface\\Icons\\Trade_BlackSmithing",
        label = "Skillwright",
        OnClick = function(_, button)
            if button == "RightButton" then
                if SW.OpenOptions then SW.OpenOptions() end
            elseif SW.ToggleDashboard then
                SW.ToggleDashboard()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Skillwright")
            tt:AddLine("Left-click: dashboard", 0.8, 0.8, 0.8)
            tt:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
        end,
    })
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" then
        BuildMinimap()
        SetupBroker()
    elseif e == "SKILL_LINES_CHANGED" then
        if dash and dash:IsShown() then SW.RefreshDashboard() end
    end
end)
