-- Skillwright - ways in: the shared launcher notch, the addon compartment, the minimap button
-- (LibDBIcon through LibForever) and a Scan prices button on the auction house.
local ADDON, SW = ...
local U = SW.UI
local LIB = SW.LIB

local ICON = "Interface\\AddOns\\Skillwright\\Media\\notch"

local function OnClick(button)
    if button == "RightButton" then SW.OpenSettings() else SW.ToggleWindow() end
end

local function Tooltip(tt)
    tt:AddLine("Skillwright", 1, 0.82, 0.3)
    local prof = SW.CharDB().lastProf or SW.Prof.Mine()[1]
    if prof and SW.CharProf(prof).has then
        local crafts, cost = SW.Plan.Remaining(prof)
        tt:AddLine(("%s %d: about %d crafts and %s to go"):format(SW.ProfName(prof), SW.Prof.Rank(prof), crafts, SW.MoneyShort(cost)), 1, 1, 1)
    end
    tt:AddLine("Left-click: open the guide", 0.8, 0.8, 0.8)
    tt:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
end

-- ---------------------------------------------------------------------------
-- Minimap button: the standard LibDBIcon button, through LibForever (stored in SkillwrightDB.minimap)
-- ---------------------------------------------------------------------------
local function BuildMinimap()
    if not LIB.RegisterMinimapButton then return end
    local settings = SW.Settings()
    local firstTime = SW.DB().minimap == nil
    local ok = LIB.RegisterMinimapButton("Skillwright", {
        icon = "Interface\\AddOns\\Skillwright\\Media\\minimap",
        label = "Skillwright",
        OnClick = function(_, button) OnClick(button) end,
        OnTooltipShow = function(tt) Tooltip(tt) end,
        migrateAngle = settings.minimapAngle,    -- where the old hand-made button was, in degrees
    }, SW.DB())
    -- one-time move of the old button's settings: it stays hidden if it was, then the old keys go
    if ok and firstTime and settings.hideMinimap then LIB.SetMinimapButtonShown("Skillwright", false) end
    settings.minimapAngle, settings.hideMinimap = nil, nil
end

-- ---------------------------------------------------------------------------
-- Addon compartment (wired from the .toc) and the shared launcher notch
-- ---------------------------------------------------------------------------
function Skillwright_OnAddonCompartmentClick(_, button) OnClick(button) end
function Skillwright_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    Tooltip(GameTooltip)
    GameTooltip:Show()
end
function Skillwright_OnAddonCompartmentLeave() GameTooltip:Hide() end

local function RegisterNotch()
    if not LIB.RegisterLauncher then return end
    LIB.RegisterLauncher({
        id = "Skillwright", label = "Skillwright", order = 20, icon = ICON,
        onClick = OnClick,
        status = function()
            local prof = SW.CharDB().lastProf or SW.Prof.Mine()[1]
            if not prof or not SW.CharProf(prof).has then return nil end
            return ("%s %d/%d"):format(SW.ProfName(prof), SW.Prof.Rank(prof), SW.CharProf(prof).max or 0)
        end,
        tooltip = { "Left-click: open the guide", "Right-click: settings" },
    }, SW.DB())
end

-- ---------------------------------------------------------------------------
-- Auction house: a Scan prices button on its frame
-- ---------------------------------------------------------------------------
local ahBtn
SW.On("AUCTION_HOUSE_SHOW", function()
    if not AuctionHouseFrame then return end
    if not ahBtn then
        ahBtn = U.Button(AuctionHouseFrame, "Skillwright: scan prices", 170, 22)
        ahBtn:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -60, -1)
        ahBtn:SetFrameStrata("HIGH")
        ahBtn:SetScript("OnClick", function() SW.Prices.StartScan() end)
        ahBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Scan prices", 1, 0.82, 0.3)
            GameTooltip:AddLine("Reads the whole auction house once (allowed every 15 minutes) and keeps the prices of "
                .. "profession materials, so Cheapest routes use real prices.", 0.85, 0.85, 0.85, true)
            local src = SW.Prices.SourceText()
            if src then GameTooltip:AddLine("Now: " .. src, 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    ahBtn:SetEnabled(not SW.Prices.Scanning())
end)
SW.Listen("SCAN_STATE", function()
    if ahBtn then
        ahBtn:SetEnabled(not SW.Prices.Scanning())
        ahBtn:SetText(SW.Prices.Scanning() and "Scanning..." or "Skillwright: scan prices")
    end
end)

SW.Listen("LOGIN", BuildMinimap)
SW.Listen("LOGIN", RegisterNotch)
