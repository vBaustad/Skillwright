-- Skillwright - its page under Blizzard's Options > AddOns: the same page as the guide's Settings tab
-- (SW.SettingsPage builds both), plus a button to open the guide.
local ADDON, SW = ...
local U = SW.UI

local category, content

local function Build()
    if category or not Settings or not Settings.RegisterCanvasLayoutCategory then return end
    local panel = CreateFrame("Frame")
    panel.name = "Skillwright"

    -- The page itself (title, settings, YippYapp link, footer) is the same as the guide's Settings tab.
    local open = U.Button(panel, "Open the guide", 130, 22)
    open:SetPoint("TOPRIGHT", -40, -12)
    open:SetFrameLevel(panel:GetFrameLevel() + 10)
    open:SetScript("OnClick", function()
        SW.ShowWindow(nil, "now")
    end)

    content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", 12, -10)
    content:SetPoint("BOTTOMRIGHT", -8, 8)
    SW.SettingsPage.Build(content)

    panel:SetScript("OnShow", function() SW.SettingsPage.Refresh(content, SW.DefaultProf()) end)
    -- A subcategory under YippYapp in Options > AddOns (LibForever), else a page of its own
    if SW.LIB.RegisterOptionsPage then
        category = SW.LIB.RegisterOptionsPage("Skillwright", panel)
    end
    if not category then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Skillwright")
        Settings.RegisterAddOnCategory(category)
    end
end

-- Blizzard's Options window at Skillwright's page. It can't open in combat: say so.
function SW.OpenBlizzardOptions()
    if not category then return false end
    if InCombatLockdown() then
        SW.msg("the Options window can't open in combat - |cffffd100/skw config|r shows the same settings in the guide.")
        return false
    end
    Settings.OpenToCategory(category:GetID())
    return true
end

-- The one way into the settings (right-click on the icon, /skw config): the guide's Settings tab, which
-- opens any time - in combat too, with or without a profession window. Blizzard's page if the guide can't.
function SW.OpenSettings()
    local ok = pcall(SW.ShowWindow, nil, "settings")
    if ok and SW.WindowShown() then return end
    SW.OpenBlizzardOptions()
end

SW.Listen("LOGIN", Build)
