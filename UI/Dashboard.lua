-- Skillwright - "choose a profession": what the guide shows a character without a crafting profession (none
-- at all, or gathering only), instead of an empty planner. One short card per crafting profession (what it's
-- for, the gathering profession that feeds it, gold or use); cards that use what the character gathers come
-- first with a gold border. A click previews its route. Window.lua decides when it shows.
local ADDON, SW = ...
local U = SW.UI
local D = {}
SW.Dashboard = D

local GREY = "|cff9a9a9a"
local GOLD = "|cffffd100"

local GATHER = {
    herb = { name = "Herbalism", icon = "Interface\\Icons\\Trade_Herbalism" },
    mine = { name = "Mining", icon = "Interface\\Icons\\Trade_Mining" },
    skin = { name = "Skinning", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
    tail = { name = "Tailoring", icon = "Interface\\Icons\\Trade_Tailoring" },
    cloth = { name = "Cloth", icon = "Interface\\Icons\\INV_Fabric_Linen_01" },
}

-- What a gathering profession the character has feeds: "You have Mining. It pairs well with ..."
local FEEDS = {
    [186] = { name = "Mining", crafts = "Blacksmithing or Engineering", what = "your ore", use = "they use your ore" },
    [182] = { name = "Herbalism", crafts = "Alchemy", what = "your herbs", use = "it uses your herbs" },
    [393] = { name = "Skinning", crafts = "Leatherworking", what = "your leather", use = "it uses your leather" },
}

-- gold / use: how much each earns and how much it gives your own character
local CARDS = {
    { id = 171, pair = "herb", feed = 182, with = "with Herbalism",
      text = "Potions, elixirs and flasks for yourself and your group. Herbs and potions always sell.",
      gold = "good", use = "great" },
    { id = 164, pair = "mine", feed = 186, with = "with Mining",
      text = "Weapons, mail and plate, sharpening stones. Best for warriors and paladins.",
      gold = "fair", use = "good" },
    { id = 165, pair = "skin", feed = 393, with = "with Skinning",
      text = "Leather and mail armor and armor kits. Skinning sells well on its own.",
      gold = "good", use = "good" },
    { id = 197, pair = "cloth", with = "cloth drops from humanoids",
      text = "Cloth armor and bags - bags always sell. The cheapest one to level: no gathering needed.",
      gold = "good", use = "good", noPair = true },
    { id = 333, pair = "tail", with = "goes well with Tailoring",
      text = "Enchant your gear and others'. Materials come from disenchanting green items, so it's costly to level.",
      gold = "later", use = "great", noPair = true },
    { id = 202, pair = "mine", feed = 186, with = "with Mining",
      text = "Bombs, gadgets, goggles and scopes. Great fun and strong in PvP, but it earns little.",
      gold = "low", use = "great" },
}

local function Card(parent, info, onPick)
    local c = CreateFrame("Button", nil, parent)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0, 0, 0, 0.35)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Options_List_Hover")
    c.edge = c:CreateTexture(nil, "BORDER")
    c.edge:SetPoint("TOPLEFT")
    c.edge:SetPoint("BOTTOMLEFT")
    c.edge:SetWidth(2)
    c.edge:SetColorTexture(1, 0.82, 0, 0.7)
    c.border = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = c:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1])
        t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        t:SetColorTexture(1, 0.82, 0, 0.9)
        t:Hide()
        c.border[i] = t
    end
    c.info = info

    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(30, 30)
    c.icon:SetPoint("TOPLEFT", 8, -7)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.icon:SetTexture(SW.ProfIcon(info.id))

    c.name = U.Text(c, "GameFontNormal")
    c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 0)
    c.name:SetText(SW.ProfName(info.id))

    -- the gathering profession that feeds it, as a small icon + words on the name line
    local g = GATHER[info.pair]
    c.pairIcon = c:CreateTexture(nil, "ARTWORK")
    c.pairIcon:SetSize(14, 14)
    c.pairIcon:SetPoint("LEFT", c.name, "RIGHT", 8, 0)
    c.pairIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.pairIcon:SetTexture(g.icon)
    c.pair = U.Text(c, "GameFontHighlightSmall")
    c.pair:SetPoint("LEFT", c.pairIcon, "RIGHT", 4, 0)
    c.pair:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    c.pair:SetWordWrap(false)
    c.pair:SetText(GREY .. info.with .. "|r")

    c.text = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.text:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)
    c.text:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    c.text:SetText(info.text)

    c.tags = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.tags:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -3)
    c.tags:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    c.tags:SetText(("%sGold:|r %s     %sFor you:|r %s"):format(GOLD, info.gold, GOLD, info.use))

    c:SetScript("OnClick", function() onPick(info.id) end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SW.ProfName(info.id), 1, 0.82, 0)
        GameTooltip:AddLine(info.noPair and ("Pairs: " .. info.with) or ("Gathering: " .. g.name), 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Click to preview its route to 300.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

-- onPick(professionID) is called when a card is clicked.
function D.Build(f, onPick)
    local sf = U.Scroll(f)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -22, 0)
    local p = sf.child
    f.sf, f.p = sf, p
    local function text(str, template)
        local fs = U.Text(p, template or "GameFontHighlightSmall", "LEFT", true)
        fs:SetText(str)
        return fs
    end
    f.title = text("Choose a profession", "GameFontNormalLarge")
    f.intro = text("", "GameFontHighlight")
    f.cards = {}
    for _, info in ipairs(CARDS) do f.cards[#f.cards + 1] = Card(p, info, onPick) end
    f.learn = text(GOLD .. "Learn one|r at a profession trainer (every capital city has them) and Skillwright plans "
        .. "your route from there: what to craft, how many and what it costs - the cheapest or the fastest way to 300.")
    f.beta = text(GOLD .. "Beta:|r " .. GREY .. "WoW: Forever is newly released and still in beta. Professions and "
        .. "recipes may change, and the guides will get better as we learn more.|r")
end

local function Names(list)
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- The intro, which names the gathering professions the character already has.
local function Intro(gathering)
    if #gathering == 0 then
        return "You have two primary professions. A crafting profession goes best with the gathering profession "
            .. "that feeds it. Two gathering professions make the most gold."
    end
    if #gathering == 1 then
        local g = FEEDS[gathering[1]]
        return ("You have %s%s|r. It pairs well with %s%s|r - %s. Skillwright plans crafting professions, "
            .. "so pick one to learn."):format(GOLD, g.name, GOLD, g.crafts, g.use)
    end
    local names, pairsWith = {}, {}
    for _, id in ipairs(gathering) do
        names[#names + 1] = FEEDS[id].name
        pairsWith[#pairsWith + 1] = ("%s%s|r (%s)"):format(GOLD, FEEDS[id].crafts, FEEDS[id].what)
    end
    return ("You have %s%s|r - the best pair for gold. To craft, swap one for the profession it feeds: %s.")
        :format(GOLD, Names(names), table.concat(pairsWith, "; "))
end

local function Layout(f)
    local gathering = SW.Prof.Gathering and SW.Prof.Gathering() or {}
    local have = {}
    for _, id in ipairs(gathering) do have[id] = true end
    f.intro:SetText((Intro(gathering)))

    -- cards that use what the character gathers first (gold border), then the rest in their usual order
    local order = {}
    for _, c in ipairs(f.cards) do if c.info.feed and have[c.info.feed] then order[#order + 1] = c end end
    for _, c in ipairs(f.cards) do if not (c.info.feed and have[c.info.feed]) then order[#order + 1] = c end end

    local p, last = f.p, nil
    local function place(w, gap)
        w:ClearAllPoints()
        if last then
            w:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -gap)
        else
            w:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -gap)
        end
        w:SetPoint("RIGHT", p, "RIGHT", -4, 0)
        last = w
    end
    place(f.title, 4)
    place(f.intro, 6)
    for _, c in ipairs(order) do
        local hot = c.info.feed and have[c.info.feed]
        for _, t in ipairs(c.border) do t:SetShown(hot and true or false) end
        place(c, 6)
    end
    place(f.learn, 14)
    place(f.beta, 8)
    f.lastWidget = last
    f.order = order
end

-- Card heights follow their wrapped text, which is only measured once shown.
local function Fit(f)
    for _, c in ipairs(f.cards) do
        local h = 7 + c.name:GetStringHeight() + 3 + c.text:GetStringHeight() + 3 + c.tags:GetStringHeight() + 8
        c:SetHeight(math.max(44, math.ceil(h)))
    end
    local top, bottom = f.p:GetTop(), f.lastWidget and f.lastWidget:GetBottom()
    if top and bottom then f.p:SetHeight(top - bottom + 12) else f.p:SetHeight(800) end
end

function D.Refresh(f)
    Layout(f)
    Fit(f)
    C_Timer.After(0, function() Fit(f) end)
end
