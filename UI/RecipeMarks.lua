-- Skillwright - a gold * in the profession window's recipe list beside every recipe you could make
-- once you have bought what a vendor sells. Everything else it needs - ore, cloth, herbs, leather - is
-- in your bags already. Blizzard's own [n] beside a name still says how many you can make without
-- buying anything, so the two together answer "what can I make here, and what must I buy first".
--
-- Drawn on Blizzard's rows through the hook Blizzard gives addons for exactly this (ScrollUtil's
-- initialized-frame callback). Nothing of theirs is replaced or wrapped, so the list keeps working in
-- combat and nothing we do here can taint it.
local ADDON, SW = ...
local M = {}
SW.RecipeMarks = M

local bySpell                                       -- [recipe spell] = row from Data/Recipes.lua
local marks = setmetatable({}, { __mode = "k" })    -- [Blizzard's row] = our "*"
local hooked = false

local function Recipe(spell)
    if not bySpell then
        bySpell = {}
        for _, data in pairs(SW.Data.professions) do
            for _, r in ipairs(data[2]) do bySpell[r[1]] = r end
        end
    end
    return bySpell[spell]
end

--- Whether a vendor sells this item: a vendor reagent in the game data, or anything this account
--- has seen on a merchant.
function M.FromVendor(id)
    local facts = SW.Data.items[id]
    if facts and facts[1] > 0 then return true end
    return SW.DB().vendor[id] ~= nil
end

--- True when the bags hold enough of every material a vendor does NOT sell to make the recipe once.
--- A recipe our data does not have gets no mark: silence rather than a guess.
function M.Ready(spell)
    local r = spell and Recipe(spell)
    if not r then return false end
    local mats = r[10]
    if #mats == 0 then return false end
    for i = 1, #mats, 2 do
        local id, need = mats[i], mats[i + 1]
        if not M.FromVendor(id) and (C_Item.GetItemCount(id) or 0) < need then return false end
    end
    return true
end

-- Only our own professions. A guildie's linked recipe list, or an NPC crafting for us, is not
-- something the bags can make.
local function Mine()
    if not (Professions and Professions.InLocalCraftingMode) then return true end
    local ok, mine = pcall(Professions.InLocalCraftingMode)
    return ok and mine and true or false
end

local function Mark(row, node)
    local data = node and node.GetData and node:GetData()
    local info = type(data) == "table" and data.recipeInfo
    local star = marks[row]
    local show = info and info.learned and SW.Settings().recipeMarks and Mine() and M.Ready(info.recipeID)
    if not show then
        if star then star:Hide() end
        return
    end
    if not star then
        star = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        star:SetText("*")
        marks[row] = star
    end
    -- After Blizzard's " [3] " when it is there (it ends in a space), else straight after the name.
    star:ClearAllPoints()
    if row.Count and row.Count:IsShown() then
        star:SetPoint("LEFT", row.Count, "RIGHT", 0, 0)
    else
        star:SetPoint("LEFT", row.Label, "RIGHT", 2, 0)
    end
    star:Show()
end
M.Mark = Mark    -- for the offline tests

local function ScrollBox()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local list = page and page.RecipeList
    return list and list.ScrollBox
end

--- Redraw the marks on the rows already showing: the bags changed, or the setting did.
function M.Refresh()
    if not hooked then return end
    local box = ScrollBox()
    if not box then return end
    box:ForEachFrame(function(row, node) Mark(row, node) end)
end

-- The recipe list exists once Blizzard's profession window has loaded, which is by the time it opens.
local function Hook()
    if hooked then return end
    local box = ScrollBox()
    if not (box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    hooked = true
    ScrollUtil.AddInitializedFrameCallback(box, function(_, row, node) Mark(row, node) end, M, false)
end

SW.Listen("PROFESSION_OPEN", function()
    Hook()
    M.Refresh()
end)
SW.Listen("MERCHANT_CHANGED", M.Refresh)
SW.On("BAG_UPDATE_DELAYED", function()
    if hooked and ProfessionsFrame and ProfessionsFrame:IsShown() then
        SW.Coalesce("recipeMarks", 0.2, M.Refresh)
    end
end)
