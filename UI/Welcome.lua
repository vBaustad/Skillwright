-- Skillwright - its page in the shared YippYapp welcome window (LibForever). No window of our own and no
-- "new" marks: the page is opened from /yippyapp or the "Welcome / what's new" button in Settings.
local ADDON, SW = ...
local LIB = SW.LIB

-- Kept short: the page is about 570 x 250-300.
local SECTIONS = {
    { "What it does",
      "Plans your profession from your current skill to 300 from the game's own recipe data: which recipe to "
      .. "make, how many, the materials and the cost. Pick |cffffd100Cheapest|r or |cffffd100Fastest|r; recipes "
      .. "with vendor materials come first, and tools like enchanting rods get their own steps." },
    { "Getting started",
      "Open your profession window and the guide opens beside it - or click the Skillwright icon on the "
      .. "minimap (behind the YippYapp button if you use several YippYapp addons), or type |cffffd100/skw|r. Craft from the Now tab; Route and Shopping show the rest. "
      .. "Settings: the guide's Settings tab (|cffffd100/skw config|r or right-click the icon), or Options > "
      .. "AddOns > Skillwright." },
    { "Trainers, vendors and the auction house",
      "Visit a trainer and Skillwright learns what each recipe needs and offers to train your route. At a vendor "
      .. "it buys what you're short of. At the auction house, |cffffd100Scan prices|r gives Cheapest real prices." },
    { "Good to know",
      "Built from WoW: Forever beta data. Where recipe items drop or are sold isn't known yet, so routes use "
      .. "trainer recipes and the ones you already know." },
}

local function Build(page)
    local w = (page:GetWidth() or 570) - 16
    local y = -4
    for _, s in ipairs(SECTIONS) do
        local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOPLEFT", 8, y)
        head:SetText(s[1])
        y = y - 16
        local body = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", 8, y)
        body:SetWidth(w)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)
        body:SetText(s[2])
        y = y - body:GetStringHeight() - 10
    end
    local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    open:SetSize(150, 22)
    open:SetPoint("TOPLEFT", 8, y - 2)
    open:SetText("Open Skillwright")
    open:SetScript("OnClick", function() SW.ShowWindow() end)
end

SW.Listen("LOGIN", function()
    if not LIB or not LIB.RegisterWelcome then return end
    LIB.RegisterWelcome({
        id = "Skillwright",
        title = "Skillwright",
        subtitle = "The cheapest or fastest route to max profession skill.",
        icon = "Interface\\AddOns\\Skillwright\\Media\\icon",
        version = 1,
        order = 20,
        build = Build,
    }, SW.DB())
end)
