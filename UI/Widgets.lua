-- Skillwright - shared UI building blocks, in the style of Blizzard's Options panel
-- (Forever swaps the art behind Blizzard's atlas names, so these come out in Forever's bronze).
local ADDON, SW = ...
local U = {}
SW.UI = U

function U.Window(name, parent, w, h, title)
    local f = CreateFrame("Frame", name, parent or UIParent, "SettingsFrameTemplate")
    f:SetSize(w, h)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.NineSlice.Text:SetText(title or "")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 7, -18)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetAtlas("heavybronze-frame-background")
    if f.Bg then f.Bg:Hide() end
    return f
end

function U.Tabs(parent, items, onSelect)
    local ctl = { buttons = {} }
    local prev
    for _, item in ipairs(items) do
        local b = CreateFrame("Button", nil, parent, "MinimalTabTemplate")
        b:SetHeight(33)
        b.value = item.value
        b.Text:SetText(item.label)
        b:SetWidth(b.Text:GetStringWidth() + 28)
        if prev then b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 3, 0) end
        b:SetScript("OnClick", function() ctl:Select(item.value, true) end)
        ctl.buttons[#ctl.buttons + 1] = b
        prev = b
    end
    function ctl:SetPoint(...) self.buttons[1]:SetPoint(...) end
    function ctl:Select(value, fire)
        self.value = value
        for _, b in ipairs(self.buttons) do b:SetSelected(b.value == value) end
        if fire and onSelect then onSelect(value) end
    end
    return ctl
end

function U.Text(parent, template, justify, wrap)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(wrap and true or false)
    return fs
end

function U.Button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 80, h or 22)
    b:SetText(text)
    local fs = b:GetFontString()
    if fs then fs:SetFontObject("GameFontNormalSmall") end
    return b
end

function U.Checkbox(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local l = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    l:SetPoint("LEFT", cb, "RIGHT", 3, 0)
    l:SetText(label)
    cb.label = l
    return cb
end

-- Two or more choices in a row, like the Options panel's category list.
function U.Segmented(parent, items, width, onSelect)
    local ctl = CreateFrame("Frame", nil, parent)
    local segW = math.floor(width / #items)
    ctl:SetSize(segW * #items, 22)
    ctl.buttons = {}
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, ctl)
        b:SetSize(segW - 2, 22)
        b:SetPoint("LEFT", (i - 1) * segW, 0)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetAtlas("Options_List_Active")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetAtlas("Options_List_Hover")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText(item.label)
        b.fs = fs
        b.value = item.value
        b:SetScript("OnClick", function() ctl:Select(item.value, true) end)
        if item.tooltip then
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(item.label, 1, 0.82, 0.3)
                GameTooltip:AddLine(item.tooltip, 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        ctl.buttons[i] = b
    end
    function ctl:Select(value, fire)
        self.value = value
        for _, b in ipairs(self.buttons) do
            local on = b.value == value
            b.bg:SetShown(on)
            b.fs:SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall")
        end
        if fire and onSelect then onSelect(value) end
    end
    ctl:Select(items[1].value)
    return ctl
end

function U.Heading(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetAtlas("Options_HorizontalDivider")
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    fs.line = line
    return fs
end

-- A vertical scroll area; content goes on .child, whose height the caller sets after layout.
function U.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w) end)
    sf.child = child
    return sf
end

-- ---------------------------------------------------------------------------
-- Items and recipes
-- ---------------------------------------------------------------------------
function U.ItemName(id)
    return SW.ItemName(id)
end

function U.ItemIcon(id)
    return (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400
end

function U.ItemQualityColor(id)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and c.hex or "|cffffffff"
end

-- Spell names don't change once the client knows them, so they are remembered: the route and shopping
-- lists ask for every row on every refresh.
local spellNames = {}
function U.RecipeName(spell)
    local cached = spellNames[spell]
    if cached then return cached end
    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
    if name then
        spellNames[spell] = name
        return name
    end
    return "recipe " .. spell
end

-- Icon of what a recipe makes (the enchant's spell icon for enchants).
function U.RecipeIcon(item, spell)
    if item and item > 0 then return U.ItemIcon(item) end
    return (spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)) or 134400
end

function U.ItemLink(id)
    local _, link = C_Item.GetItemInfo(id)
    return link
end

-- Shift-click an item into chat (or any other modified click the game supports).
function U.HandleItemClick(id)
    local link = id and U.ItemLink(id)
    if link and IsModifiedClick() then HandleModifiedItemClick(link) return true end
end

-- Small icon button that shows an item's (or spell's) real tooltip and links on shift-click.
function U.IconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.tex = t
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        if not self.item and not self.spell then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item and self.item > 0 then GameTooltip:SetItemByID(self.item) else GameTooltip:SetSpellByID(self.spell) end
        if self.extra then self.extra(GameTooltip) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.item and self.item > 0 then U.HandleItemClick(self.item) end
    end)
    function b:Set(item, spell, extra)
        self.item, self.spell, self.extra = item, spell, extra
        if item or spell then self.tex:SetTexture(U.RecipeIcon(item, spell)) end
    end
    return b
end

-- Difficulty colours, as the profession window shows them.
U.COLOR = { orange = "ffff8040", yellow = "ffffff00", green = "ff40bf40", grey = "ff808080" }

function U.Colored(color, text)
    return "|c" .. (U.COLOR[color] or "ffffffff") .. text .. "|r"
end
