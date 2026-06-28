-- Skillwright - guild-market results side panel. Lists who in the guild is selling the
-- (non-vendor) mats for the current step, at what price; click a seller to open a GFM-style
-- whisper so you can arrange the face-to-face trade. Data comes from Core/Market.lua.
local ADDON, SW = ...
local M = SW.GuildMarket

local panel
local ROW_H = 18

-- Copper -> short "1g2s45c" string, matching how GuildFoundMarket writes prices in whispers.
local function coinShort(c)
    c = math.floor((c or 0) + 0.5)
    local g = math.floor(c / 10000); c = c % 10000
    local s = math.floor(c / 100); local cp = c % 100
    local out = ""
    if g > 0 then out = out .. g .. "g" end
    if s > 0 then out = out .. s .. "s" end
    if cp > 0 then out = out .. cp .. "c" end
    return out == "" and "0c" or out
end

-- Open a whisper to the seller, pre-filled with the item link + price (exactly GFM's format,
-- so the seller recognises it): "/w Seller [Item]@1g2s5c ". The player sends it themselves.
local function whisperSeller(seller, itemID, price)
    local link = (GetItemInfo and select(2, GetItemInfo(itemID))) or ("[item:" .. itemID .. "]")
    local body = (price and price > 0) and (link .. "@" .. coinShort(price) .. " ") or (link .. " ")
    if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. seller .. " " .. body) end
end

local function MakeRow(c, i)
    local r = c.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, c)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 4, 0); r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -4, 0); r.right:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self) if self._seller then self.bg:SetColorTexture(1, 1, 1, 0.10) end end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0, 0, 0, 0) end)
    r:SetScript("OnClick", function(self)
        if self._seller then whisperSeller(self._seller, self._id, self._price) end
    end)
    c.rows[i] = r
    return r
end

local function Build()
    if panel then return panel end
    local f = CreateFrame("Frame", "SkillwrightGuildBuy", UIParent, "BackdropTemplate")
    f:SetSize(214, 220)
    f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 })
    f:SetBackdropColor(0.05, 0.05, 0.06, 1)
    if SW.Decorate then SW.Decorate(f) end

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetColorTexture(0.16, 0.13, 0.09, 0.95)
    header:SetPoint("TOPLEFT", 4, -4); header:SetPoint("TOPRIGHT", -4, -4); header:SetHeight(22)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("LEFT", header, "LEFT", 8, 0); f.title:SetText("|c" .. (SW.CREAM or "ffebdec2") .. "Guild Market|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("RIGHT", header, "RIGHT", 2, 0)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 8, 8); f.hint:SetPoint("BOTTOMRIGHT", -8, 8); f.hint:SetJustifyH("LEFT")
    f.hint:SetText("|cff888888Click a seller to whisper them.|r")

    local sf = CreateFrame("ScrollFrame", "SkillwrightGuildBuyScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -30); sf:SetPoint("BOTTOMRIGHT", -26, 24)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(170, 10); content.rows = {}
    sf:SetScrollChild(content)
    f.scroll, f.content = sf, content

    tinsert(UISpecialFrames, "SkillwrightGuildBuy")
    panel = f
    f:Hide()
    return f
end

-- Rebuild the list from the latest cached offers for the items we're tracking.
function SW.RefreshGuildBuy()
    if not panel or not panel:IsShown() then return end
    local c = panel.content
    local y, n = 4, 0
    local function nextRow()
        n = n + 1
        return MakeRow(c, n)
    end
    for _, id in ipairs(panel.items or {}) do
        local name = (GetItemInfo and GetItemInfo(id)) or ("item:" .. id)
        local icon = (GetItemInfoInstant and select(5, GetItemInfoInstant(id))) or "Interface\\Icons\\INV_Misc_QuestionMark"
        local h = nextRow()
        h._seller, h._id, h._price = nil, nil, nil
        h.icon:SetTexture(icon); h.icon:Show()
        h.left:ClearAllPoints(); h.left:SetPoint("LEFT", 20, 0)
        h.left:SetText("|cffe8dcc2" .. name .. "|r"); h.right:SetText("")
        h.bg:SetColorTexture(0.95, 0.82, 0.45, 0.10)
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("TOPRIGHT", 0, -y); h:Show()
        y = y + ROW_H + 1

        local offers = M.GetAll(id)
        if #offers == 0 then
            local e = nextRow()
            e._seller, e._id, e._price = nil, nil, nil
            e.icon:Hide(); e.left:ClearAllPoints(); e.left:SetPoint("LEFT", 8, 0)
            e.left:SetText("|cff777777searching / no sellers found|r"); e.right:SetText("")
            e.bg:SetColorTexture(0, 0, 0, 0)
            e:ClearAllPoints(); e:SetPoint("TOPLEFT", 0, -y); e:SetPoint("TOPRIGHT", 0, -y); e:Show()
            y = y + ROW_H
        else
            for _, o in ipairs(offers) do
                local r = nextRow()
                r._seller, r._id, r._price = o.seller, id, o.price
                r.icon:Hide(); r.left:ClearAllPoints(); r.left:SetPoint("LEFT", 8, 0)
                r.left:SetText(("|cff66ccff%s|r |cff999999x%d|r"):format(o.seller, o.qty or 0))
                r.right:SetText(GetCoinTextureString and GetCoinTextureString(o.price) or coinShort(o.price))
                r.bg:SetColorTexture(0, 0, 0, 0)
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y); r:Show()
                y = y + ROW_H
            end
        end
        y = y + 5
    end
    for i = n + 1, #c.rows do c.rows[i]:Hide() end
    c:SetHeight(math.max(10, y + 4))
    panel:SetHeight(math.min(440, 58 + y))
end

-- Open the panel for a set of item IDs (docked to the right of the guide) and refresh it.
function SW.ShowGuildBuy(items)
    Build()
    panel.items = items or {}
    panel:ClearAllPoints()
    local guide = _G.SkillwrightFrame
    if guide and guide:IsShown() then
        panel:SetPoint("TOPLEFT", guide, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("CENTER")
    end
    panel:Show()
    SW.RefreshGuildBuy()
end

function SW.HideGuildBuy() if panel then panel:Hide() end end
