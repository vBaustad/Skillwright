-- Skillwright - the window: frame, tabs, the three views (Now / Steps / Shopping),
-- docking to the trade window, and the slash + events that drive it.
local ADDON, SW = ...
local DB, msg = SW.DB, SW.msg
local CurrentSkill, CurrentStepIndex = SW.CurrentSkill, SW.CurrentStepIndex
local RemainingMats, ActiveProfession, ItemIcon = SW.RemainingMats, SW.ActiveProfession, SW.ItemIcon
local StepPlan = SW.StepPlan

local W = 348            -- frame width (compact)
local DEFAULT_H = 426    -- fixed height used by every view (Now / Steps / Shopping)
local DEFAULT_X, DEFAULT_Y = 553, 1046  -- default top-left (screen coords) before the player moves it
local DOCK_X, DOCK_Y = -28, -36         -- default attached offset from the host window's top-right

local win
local function ContentW() return (win.scroll:GetWidth() or 330) end

-- The guide is "attached" when the setting is on AND a context window (trade/merchant/trainer)
-- that opened it is visible - then it glues to that window's edge and follows it when moved.
local function IsAttached()
    return (DB().attached ~= false and win and win.dockFrame and win.dockFrame:IsShown()) and true or false
end

-- Rich tooltip for a recipe/step: the crafted item (link, when the trade window is open),
-- where the recipe comes from (trainer vs a bought/dropped pattern), whether you've learned
-- it yet, and the data note.
local function ShowRecipeTooltip(owner, prof, s)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    -- The real crafted item, from the stored item ID (works learned or not, window or not).
    if s.item then
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. s.item)
        GameTooltip:Show()
        return
    end
    -- Try the live trade-skill link (e.g. enchants have no crafted item).
    local idx = SW.RecipeIndex(prof, s.recipe)
    if idx and GetTradeSkillItemLink then
        local link = GetTradeSkillItemLink(idx)
        if link then pcall(GameTooltip.SetHyperlink, GameTooltip, link); GameTooltip:Show(); return end
    end
    -- Fallback when there's genuinely no item to show.
    GameTooltip:AddLine(s.recipe, 1, 1, 1)
    GameTooltip:AddLine(("Skill %d-%d"):format(s.from, s.to), 0.7, 0.7, 0.7)
    if s.vendorPattern then GameTooltip:AddLine("Pattern required (buy from a vendor or find as a drop).", 1, 0.6, 0.2, true)
    else GameTooltip:AddLine("Trainer-taught.", 0.5, 0.8, 1) end
    if s.note then GameTooltip:AddLine(s.note, 0.85, 0.78, 0.55, true) end
    GameTooltip:Show()
end

-- Shift/ctrl-click an item element to link it in chat, dress it up, etc. (no-op on a plain click).
local function LinkItem(id)
    if not (id and HandleModifiedItemClick) then return end
    local link = select(2, GetItemInfo(id))
    if link then HandleModifiedItemClick(link) end
end

-- ----- pooled widgets -----
local function MakeIcon(content, i)
    local b = content.icons[i]
    if b then return b end
    local nm = "SkillwrightMat" .. i
    b = CreateFrame("Button", nm, content, "ItemButtonTemplate")
    b:SetSize(37, 37)
    b.countFS = _G[nm .. "Count"]
    b.hnFS = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.hnFS:SetPoint("TOP", b, "BOTTOM", 0, -1); b.hnFS:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._id then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self._id) end
        GameTooltip:AddLine(("Have %d  /  Need %d"):format(self._have or 0, self._req or 0), 1, 1, 1)
        if (self._bank or 0) > 0 then GameTooltip:AddLine(("(%d of those are in your bank)"):format(self._bank), 0.5, 0.65, 1) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) LinkItem(self._id) end)
    content.icons[i] = b
    return b
end

local function MakeStepRow(content, i)
    local r = content.stepRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetSize(330, 30)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "BORDER"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06); r.hl:Hide()
    r.accent = r:CreateTexture(nil, "ARTWORK"); r.accent:SetWidth(3)
    r.accent:SetPoint("TOPLEFT", 0, 0); r.accent:SetPoint("BOTTOMLEFT", 0, 0); r.accent:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("TOPLEFT", 9, -5)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.top = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); r.top:SetPoint("TOPLEFT", 36, -4); r.top:SetJustifyH("LEFT"); r.top:SetWordWrap(false)
    r.bot = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"); r.bot:SetPoint("TOPLEFT", 36, -18); r.bot:SetJustifyH("LEFT"); r.bot:SetWordWrap(false)
    r:SetScript("OnEnter", function(self) self.hl:Show(); if self._step then ShowRecipeTooltip(self, self._prof, self._step) end end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) LinkItem(self._step and self._step.item) end)
    content.stepRows[i] = r
    return r
end

-- Hoverable "Up next" row (lives inside content.upBox); shows the recipe tooltip on hover.
local function MakeUpRow(content, i)
    local r = content.upRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content.upBox)
    r.fs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.fs:SetPoint("LEFT", 0, 0); r.fs:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self) if self._step then ShowRecipeTooltip(self, self._prof, self._step) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) LinkItem(self._step and self._step.item) end)
    content.upRows[i] = r
    return r
end

-- Route segment row (gathering professions): zones line + an optional note below it.
local function MakeRouteRow(content, i)
    local r = content.routeRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content)
    r.zones = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.zones:SetPoint("TOPLEFT", 12, 0); r.zones:SetJustifyH("LEFT")
    r.note = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    r.note:SetPoint("TOPLEFT", r.zones, "BOTTOMLEFT", 0, -2); r.note:SetJustifyH("LEFT")
    content.routeRows[i] = r
    return r
end

-- Section header used by both Steps and Shopping (tier name + skill range, left accent bar).
local function MakeTierHeader(content, i)
    local r = content.tierHeaders[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content)
    r:SetSize(330, 22)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.accent = r:CreateTexture(nil, "ARTWORK"); r.accent:SetWidth(3); r.accent:SetColorTexture(0.95, 0.82, 0.45, 0.95)
    r.accent:SetPoint("TOPLEFT", 0, 0); r.accent:SetPoint("BOTTOMLEFT", 0, 0)
    r.left = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); r.left:SetPoint("LEFT", 9, 0); r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"); r.right:SetPoint("RIGHT", -6, 0); r.right:SetJustifyH("RIGHT")
    content.tierHeaders[i] = r
    return r
end

local function MakeMatRow(content, i)
    local r = content.matRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetSize(330, 20)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 24, 0); r.name:SetJustifyH("LEFT")
    r.amt = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.amt:SetPoint("RIGHT", -6, 0); r.amt:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.10)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._id then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self._id) end
        GameTooltip:AddLine(("Have %d  /  Need %d"):format(self._have or 0, self._req or 0), 1, 1, 1)
        if (self._bank or 0) > 0 then GameTooltip:AddLine(("(%d of those are in your bank)"):format(self._bank), 0.5, 0.65, 1) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, self._stripe and 0.03 or 0); GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self) LinkItem(self._id) end)
    content.matRows[i] = r
    return r
end

local function BuildWindow()
    if win then return win end
    local f = CreateFrame("Frame", "SkillwrightFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, DEFAULT_H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if IsAttached() then
            -- Remember the new offset from the host window, then re-anchor so it keeps following it.
            local off = DB().dockOffset or {}
            off.x = self:GetLeft() - win.dockFrame:GetRight()
            off.y = self:GetTop() - win.dockFrame:GetTop()
            DB().dockOffset = off
            if SW.ReAnchor then SW.ReAnchor() end
        else
            self.autoShown = false
            local pos = DB().pos; pos.x = self:GetLeft(); pos.y = self:GetTop()
        end
    end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.06, 1)
    SW.Decorate(f)

    -- Faint atmospheric scene behind the content (toggle in settings).
    f.sceneBg = f:CreateTexture(nil, "BORDER")
    SW.ApplyScene(f.sceneBg)
    f.sceneBg:SetPoint("TOPLEFT", 4, -4); f.sceneBg:SetPoint("BOTTOMRIGHT", -4, 4)
    f.sceneBg:SetAlpha(1); f.sceneBg:SetVertexColor(0.78, 0.78, 0.84)

    -- Compact header bar: addon title (left), profession + skill (right), close button.
    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetColorTexture(0.16, 0.13, 0.09, 0.95)
    header:SetPoint("TOPLEFT", 4, -4); header:SetPoint("TOPRIGHT", -4, -4); header:SetHeight(24)
    local hr = f:CreateTexture(nil, "ARTWORK")
    hr:SetColorTexture(0.5, 0.42, 0.28, 0.7); hr:SetHeight(1)
    hr:SetPoint("TOPLEFT", 4, -28); hr:SetPoint("TOPRIGHT", -4, -28)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", header, "LEFT", 8, 0); f.title:SetText("|c" .. SW.CREAM .. "Skillwright|r")

    f.cogBtn = CreateFrame("Button", nil, f)
    f.cogBtn:SetSize(14, 14); f.cogBtn:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
    f.cogBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    f.cogBtn:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
    f.cogBtn:SetScript("OnClick", function() if SW.OpenOptions then SW.OpenOptions() end end)
    f.cogBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Settings", 1, 0.82, 0.3); GameTooltip:Show()
    end)
    f.cogBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("RIGHT", header, "RIGHT", 2, 0)
    f.closeBtn = close

    f.skillFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.skillFS:SetPoint("RIGHT", close, "LEFT", -6, 0); f.skillFS:SetJustifyH("RIGHT")

    -- Footer: a full-width segmented tab control (active = filled + gold text + top accent).
    f.footer = f:CreateTexture(nil, "ARTWORK")
    f.footer:SetColorTexture(0.13, 0.11, 0.07, 0.8)
    f.footer:SetPoint("BOTTOMLEFT", 4, 4); f.footer:SetPoint("BOTTOMRIGHT", -4, 4); f.footer:SetHeight(28)
    f.fdiv = f:CreateTexture(nil, "ARTWORK")
    f.fdiv:SetColorTexture(0.5, 0.42, 0.28, 0.7); f.fdiv:SetHeight(1)
    f.fdiv:SetPoint("BOTTOMLEFT", 4, 32); f.fdiv:SetPoint("BOTTOMRIGHT", -4, 32)

    f.tabs = {}
    local tabNames, tabViews = { "Now", "Steps", "Shopping" }, { "now", "steps", "mats" }
    local segW = (W - 16) / 3
    for i, nm in ipairs(tabNames) do
        local t = CreateFrame("Button", nil, f, "BackdropTemplate")
        t:SetSize(segW, 22)
        if i == 1 then t:SetPoint("BOTTOMLEFT", 6, 6) else t:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 3, 0) end
        t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetAllPoints(); t.bg:SetColorTexture(1, 1, 1, 0)
        t.fs = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t.fs:SetPoint("CENTER", 0, -1); t.fs:SetText(nm)
        t.view = tabViews[i]
        t:SetScript("OnClick", function(self) DB().view = self.view; SW.Refresh() end)
        t:SetScript("OnEnter", function(self)
            if not self.selected then self.bg:SetColorTexture(1, 0.95, 0.8, 0.07); self.fs:SetTextColor(0.95, 0.92, 0.82) end
        end)
        t:SetScript("OnLeave", function(self)
            if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0.22); self.fs:SetTextColor(0.6, 0.57, 0.5) end
        end)
        f.tabs[i] = t
    end

    local sf = CreateFrame("ScrollFrame", "SkillwrightScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -36); sf:SetPoint("BOTTOMRIGHT", -30, 34)
    f.scroll = sf
    local sbDiv = f:CreateTexture(nil, "ARTWORK")
    sbDiv:SetColorTexture(0.5, 0.42, 0.28, 0.6); sbDiv:SetWidth(1)
    sbDiv:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 4, 2); sbDiv:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -2)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(330, 10)
    content.icons, content.stepRows, content.matRows, content.tierHeaders, content.routeRows, content.upRows = {}, {}, {}, {}, {}, {}
    sf:SetScrollChild(content)
    f.content = content
    content.bigFS = content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    content.bigFS:SetPoint("TOPLEFT", 2, -2); content.bigFS:SetWidth(266); content.bigFS:SetJustifyH("LEFT")
    -- Invisible hover region over the big recipe name (FontStrings can't take OnEnter).
    content.bigHit = CreateFrame("Button", nil, content)
    content.bigHit:SetScript("OnEnter", function(self) if self._step then ShowRecipeTooltip(self, self._prof, self._step) end end)
    content.bigHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    content.bigHit:SetScript("OnClick", function(self) LinkItem(self._step and self._step.item) end)
    content.bigHit:Hide()
    content.subFS = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    content.subFS:SetPoint("TOPLEFT", 2, -34); content.subFS:SetWidth(266); content.subFS:SetJustifyH("LEFT")
    -- Training-note callout: a gold left accent bar + wrapped text.
    content.noteBox = CreateFrame("Frame", nil, content)
    content.noteBox.accent = content.noteBox:CreateTexture(nil, "ARTWORK")
    content.noteBox.accent:SetColorTexture(0.85, 0.7, 0.35, 0.85); content.noteBox.accent:SetWidth(2)
    content.noteBox.accent:SetPoint("TOPLEFT", 0, 0); content.noteBox.accent:SetPoint("BOTTOMLEFT", 0, 0)
    content.noteBox.fs = content.noteBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    content.noteBox.fs:SetPoint("TOPLEFT", 8, -1); content.noteBox.fs:SetJustifyH("LEFT")

    -- "Up next" titled inset box.
    content.upBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    content.upBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    content.upBox:SetBackdropColor(0, 0, 0, 0.3)
    content.upBox:SetBackdropBorderColor(0.5, 0.42, 0.28, 0.6)
    content.upBox.title = content.upBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    content.upBox.title:SetPoint("TOPLEFT", 8, -6); content.upBox.title:SetText("|cffe6dcc2Up next|r")
    content.buyFS = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    content.buyFS:SetWidth(266); content.buyFS:SetJustifyH("LEFT")
    content.bankFS = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    content.bankFS:SetWidth(266); content.bankFS:SetJustifyH("LEFT"); content.bankFS:Hide()
    content.buyBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.buyBtn:SetSize(150, 22)
    content.buyBtn:SetScript("OnClick", function() SW.BuyNeededMats() end)
    content.buyBtn:SetScript("OnEnter", function(self) SW.BuyButtonTooltip(self) end)
    content.buyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    content.craftBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.craftBtn:SetSize(104, 22)
    content.craftBtn:SetScript("OnClick", function() SW.CraftCurrent() end)
    content.trainBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.trainBtn:SetSize(160, 22)
    content.trainBtn:SetScript("OnClick", function() SW.TrainNeeded(ActiveProfession()) end)
    content.buyFS:Hide(); content.buyBtn:Hide(); content.craftBtn:Hide(); content.trainBtn:Hide()

    tinsert(UISpecialFrames, "SkillwrightFrame")
    win = f
    SW.RegisterWindow(f)
    SW.ApplyWindowSettings()
    f:Hide()
    return f
end

local function HideGroups()
    if not win then return end
    win.content.bigFS:Hide(); win.content.subFS:Hide(); win.content.bigHit:Hide()
    win.content.noteBox:Hide(); win.content.upBox:Hide()
    win.content.buyFS:Hide(); win.content.bankFS:Hide(); win.content.buyBtn:Hide(); win.content.craftBtn:Hide(); win.content.trainBtn:Hide()
    for _, b in ipairs(win.content.icons) do b:Hide() end
    for _, r in ipairs(win.content.stepRows) do r:Hide() end
    for _, r in ipairs(win.content.matRows) do r:Hide() end
    for _, r in ipairs(win.content.tierHeaders) do r:Hide() end
    for _, r in ipairs(win.content.routeRows) do r:Hide() end
    local ov = win.content.ov
    if ov then
        for _, w in ipairs(ov.widgets) do w:Hide() end
        for _, r in ipairs(ov.roadRows) do r:Hide() end
    end
end

-- ----- vendor buy support (used by the Now view when a merchant is open) -----
-- How many of a mat to buy at the open vendor: the planned amount for supplier mats
-- (threads/dyes/salt), otherwise the shortfall for anything else the vendor happens to
-- stock that the step needs (e.g. Refreshing Spring Water from a general goods vendor).
local function BuyQty(e) return (e.vendor and (e.buyNow or 0)) or (e.short or 0) end

function SW.UpdateBuyButton()
    local c = win and win.content
    if not c then return end
    local plan = win.plan
    if not (plan and not plan.done and win.merchantOpen and win.merchantMap) then c.buyBtn:Hide(); return end
    local any = false
    for _, e in ipairs(plan.mats) do
        if win.merchantMap[e.id] and BuyQty(e) > 0 then any = true end
    end
    if not any then c.buyBtn:Hide(); return end
    c.buyBtn:SetText("Buy needed mats"); c.buyBtn:Show()
end

-- Craft as many of the current recipe as your bag mats allow (needs the trade window open).
function SW.CraftCurrent()
    local plan = win and win.plan
    if not (plan and not plan.done) then return end
    local idx = SW.RecipeIndex(ActiveProfession(), plan.step.recipe)
    if not (idx and DoTradeSkill) then return end
    -- Craft what your bags allow; if that's 0 (e.g. a vendor mat not bought yet) still try the
    -- whole step so a click always does something - the game caps it at available reagents.
    local n = plan.craftableHave or 0
    if n < 1 then n = plan.remaining or 1 end
    local stopAt = plan.step.to
    if GetTradeSkillLine then local _, _, mr = GetTradeSkillLine(); if mr and mr < stopAt then stopAt = mr end end
    win.craftStopAt = stopAt
    win.craftRecipe = plan.step.recipe   -- only auto-stop while THIS recipe is what's cooking
    DoTradeSkill(idx, n)
end

function SW.BuyNeededMats()
    local plan = win and win.plan
    if not (plan and win.merchantOpen and win.merchantMap) then return end
    for _, e in ipairs(plan.mats) do
        local want = BuyQty(e)
        if want > 0 then
            local slot = win.merchantMap[e.id]
            if slot then
                -- Buy a full stack per call: BuyMerchantItem(slot, n) where n <= the item's
                -- max stack avoids ERR_INTERNAL_BAG_ERROR and isn't throttled like 1-at-a-time.
                local _, _, _, _, numAvail = GetMerchantItemInfo(slot)
                local maxStack = (GetItemInfo and select(8, GetItemInfo(e.id))) or 1
                maxStack = math.max(1, maxStack or 1)
                local remaining = want
                if numAvail and numAvail >= 0 then remaining = math.min(remaining, numAvail) end
                local guard = 0
                while remaining > 0 and guard < 60 do
                    guard = guard + 1
                    local n = math.min(remaining, maxStack)
                    BuyMerchantItem(slot, n)
                    remaining = remaining - n
                end
            end
        end
    end
end

function SW.BuyButtonTooltip(btn)
    local plan = win and win.plan
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Buy needed mats", 1, 0.85, 0.2)
    local total = 0
    if plan and win.merchantMap then
        for _, e in ipairs(plan.mats) do
            local want = BuyQty(e)
            if want > 0 and win.merchantMap[e.id] then
                local _, _, price, stack = GetMerchantItemInfo(win.merchantMap[e.id])
                local per = (price and stack and stack > 0) and (price / stack) or 0
                local cost = per * want
                total = total + cost
                local costStr = GetCoinTextureString and GetCoinTextureString(cost) or tostring(cost)
                GameTooltip:AddDoubleLine(("%d %s"):format(want, e.name), costStr, 1, 1, 1, 1, 1, 1)
            end
        end
    end
    if total > 0 then
        GameTooltip:AddLine(" ")
        local t = GetCoinTextureString and GetCoinTextureString(total) or tostring(total)
        GameTooltip:AddDoubleLine("Total", t, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(("Enough to craft %d now."):format((plan and plan.craftableNow) or 0), 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- ----- trainer support (used when a profession trainer window is open) -----
-- Count of trainer services we'd train: for a craft profession only the guide's recipes;
-- for a gathering profession every available service (rank-ups).
function SW.CountTrainable(prof)
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return 0 end
    local want
    if SW.PATHS[prof] then want = {}; for _, s in ipairs(SW.PATHS[prof]) do want[s.recipe] = true end end
    local n = 0
    for i = 1, GetNumTrainerServices() do
        local name, _, st = GetTrainerServiceInfo(i)
        if st == "available" and (not want or want[name]) then n = n + 1 end
    end
    return n
end

function SW.TrainNeeded(prof)
    if not (GetNumTrainerServices and BuyTrainerService) then return end
    local want
    if SW.PATHS[prof] then want = {}; for _, s in ipairs(SW.PATHS[prof]) do want[s.recipe] = true end end
    for i = 1, GetNumTrainerServices() do
        local name, _, st = GetTrainerServiceInfo(i)
        if st == "available" and (not want or want[name]) then BuyTrainerService(i) end
    end
end

local function RenderNow(prof, rank)
    local c = win.content
    local cw = ContentW() - 4
    c.bigFS:SetWidth(cw); c.subFS:SetWidth(cw); c.buyFS:SetWidth(cw); c.bankFS:SetWidth(cw)
    c.bigFS:Show(); c.subFS:Show()
    local plan = StepPlan(prof, rank)
    win.plan = plan
    if not plan or plan.done then
        c.bigFS:ClearAllPoints(); c.bigFS:SetPoint("TOPLEFT", 2, -2)
        c.subFS:ClearAllPoints(); c.subFS:SetPoint("TOPLEFT", 2, -34)
        c.bigFS:SetText("|cff66ff66Max skill!|r")
        c.subFS:SetText((prof or "Profession") .. " is done - nothing left to craft.")
        c.buyFS:Hide(); c.buyBtn:Hide()
        c:SetWidth(ContentW()); c:SetHeight(70); return
    end
    local s = plan.step

    -- Failsafe: detect the trainable cap (current rank == the max you can train to right now).
    local atCap = false
    if GetTradeSkillLine then
        local n, cr, mr = GetTradeSkillLine()
        if n == prof and mr and cr and mr < 300 and cr >= mr then atCap = true end
    end

    if plan.known == false then
        c.bigFS:SetText("|cffff8800Train:|r |cffffffff" .. s.recipe .. "|r")
    else
        c.bigFS:SetText("|cffffffff" .. s.recipe .. "|r" .. (s.vendorPattern and "  |cffff8800(buy pattern)|r" or ""))
    end

    local sub = ("Make |cffffd100%d|r more   -   skill |cffffffff%d|r|cff888888/%d|r"):format(plan.remaining, rank, s.to)
    if atCap then
        sub = sub .. "\n|cffff5555Trainable cap reached - train the next rank to keep gaining skill.|r"
    elseif plan.known == false then
        sub = sub .. "\n|cffff8800You haven't learned this recipe yet - visit your trainer to learn it.|r"
    end
    if plan.craftableNow < plan.remaining then
        sub = sub .. ("\n|cffaaccffYou can craft %d now|r |cff888888with the mats you have|r"):format(plan.craftableNow)
    end
    -- The "Make N more" target is padded so you reliably hit the skill (recipes go green and
    -- skip skill-ups). Show the bare minimum too, so nobody farms hundreds of spare mats.
    if plan.minCrafts and plan.minCrafts < plan.remaining then
        local mn = {}
        for _, e in ipairs(plan.mats) do
            if (e.minNeed or 0) > 0 then mn[#mn + 1] = ("%d %s"):format(e.minNeed, e.name) end
        end
        if #mn > 0 then
            sub = sub .. ("\n|cff888888Minimum if every craft skills up: %d crafts (%s).|r"):format(plan.minCrafts, table.concat(mn, ", "))
        end
    end
    c.subFS:SetText(sub)

    local y = 2
    c.bigFS:ClearAllPoints(); c.bigFS:SetPoint("TOPLEFT", 2, -y)
    -- Hover region over the recipe name -> item / source / learned tooltip.
    c.bigHit:ClearAllPoints(); c.bigHit:SetPoint("TOPLEFT", c.bigFS, "TOPLEFT", 0, 0)
    c.bigHit:SetSize(math.max(40, c.bigFS:GetStringWidth() + 4), (c.bigFS:GetStringHeight() or 22) + 2)
    c.bigHit._step, c.bigHit._prof = s, prof
    c.bigHit:Show()
    y = y + (c.bigFS:GetStringHeight() or 22) + 8
    c.subFS:ClearAllPoints(); c.subFS:SetPoint("TOPLEFT", 2, -y)
    y = y + (c.subFS:GetStringHeight() or 16) + 12

    -- Mat icons, wrapping to multiple rows (48px cells leave room for the have/need line).
    local perRow = math.max(1, math.floor(cw / 48))
    local iconY = y
    for i, e in ipairs(plan.mats) do
        local b = MakeIcon(c, i)
        b._id, b._name, b._have, b._req, b._short, b._bank = e.id, e.name, e.have, e.need, e.short, e.bank
        SetItemButtonTexture(b, ItemIcon(e.id))
        if b.countFS then b.countFS:Hide() end
        b.hnFS:SetText(("%d/%d"):format(e.have, e.need))
        if e.have >= e.need then b.hnFS:SetTextColor(0.4, 1, 0.4) else b.hnFS:SetTextColor(1, 0.45, 0.45) end
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 4 + col * 48, -(iconY + row * 52)); b:Show()
    end
    for i = #plan.mats + 1, #c.icons do c.icons[i]:Hide() end
    y = iconY + math.max(1, math.ceil(#plan.mats / perRow)) * 52

    local buys = {}
    for _, e in ipairs(plan.mats) do
        if e.vendor and (e.buyNow or 0) > 0 then buys[#buys + 1] = ("%d %s"):format(e.buyNow, e.name) end
    end
    if #buys > 0 then
        c.buyFS:SetText("|cffe6b34dBuy from vendor:|r |cffffffff" .. table.concat(buys, ", ") .. "|r")
        c.buyFS:ClearAllPoints(); c.buyFS:SetPoint("TOPLEFT", 2, -y); c.buyFS:Show()
        y = y + (c.buyFS:GetStringHeight() or 14) + 6
    else
        c.buyFS:Hide()
    end

    -- Action button: "Buy needed mats" - shown at a vendor that stocks what we still need.
    c.buyBtn:Hide()
    local buyable = false
    if win.merchantOpen and win.merchantMap then
        for _, e in ipairs(plan.mats) do
            if win.merchantMap[e.id] and BuyQty(e) > 0 then buyable = true; break end
        end
    end
    if buyable then
        c.buyBtn:SetWidth(150); c.buyBtn:SetText("Buy needed mats")
        c.buyBtn:ClearAllPoints(); c.buyBtn:SetPoint("TOPLEFT", 2, -y); c.buyBtn:Show()
        y = y + 28
    end

    -- Bank reminder: mats you already own but have stashed in the bank.
    local banks = {}
    for _, e in ipairs(plan.mats) do
        if (e.bank or 0) > 0 then banks[#banks + 1] = ("%d %s"):format(e.bank, e.name) end
    end
    if #banks > 0 then
        c.bankFS:SetText("|cff7da5ffIn your bank:|r |cffd8d8d8" .. table.concat(banks, ", ") .. "|r |cff666666(withdraw before crafting)|r")
        c.bankFS:ClearAllPoints(); c.bankFS:SetPoint("TOPLEFT", 2, -y); c.bankFS:Show()
        y = y + (c.bankFS:GetStringHeight() or 14) + 6
    else
        c.bankFS:Hide()
    end

    -- Craft button (only when the trade window for this profession is open). The Buy button
    -- is positioned above (under the vendor line); Train lives on the trainer window.
    c.trainBtn:Hide()
    local idx = SW.RecipeIndex(prof, s.recipe)
    if idx then
        -- Always clickable so you can just craft whatever's possible; the game caps it at the
        -- mats in your bags and the stop-at-target failsafe ends the run.
        local n = plan.craftableHave or 0
        c.craftBtn:SetText(n > 0 and ("Craft (%d)"):format(n) or "Craft")
        c.craftBtn:Enable()
        c.craftBtn:ClearAllPoints(); c.craftBtn:SetPoint("TOPLEFT", 2, -y); c.craftBtn:Show()
        y = y + 28
    else
        c.craftBtn:Hide()
    end

    local steps = SW.PATHS[prof]
    -- Training-note callout (gold accent bar + text).
    if s.note then
        c.noteBox.fs:SetWidth(cw - 14)
        c.noteBox.fs:SetText("|cffffcf80" .. s.note .. "|r")
        local nh = (c.noteBox.fs:GetStringHeight() or 12) + 4
        c.noteBox:ClearAllPoints(); c.noteBox:SetPoint("TOPLEFT", 2, -y)
        c.noteBox:SetWidth(cw - 2); c.noteBox:SetHeight(nh); c.noteBox:Show()
        y = y + nh + 10
    end
    -- "Up next" titled box - each upcoming recipe is a hoverable row (item + source tooltip).
    local nx = {}
    for j = plan.idx + 1, math.min(plan.idx + 3, #steps) do nx[#nx + 1] = steps[j] end
    if #nx > 0 then
        local uy = 22
        for k, s2 in ipairs(nx) do
            local r = MakeUpRow(c, k)
            local tag = s2.vendorPattern and "  |cffff8800* pattern|r" or ""
            r.fs:SetText(("|cffffd100[%d-%d]|r  |cffe8dcc2%s|r%s"):format(s2.from, s2.to, s2.recipe, tag))
            r.fs:SetWidth(cw - 22)
            r._step, r._prof = s2, prof
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", c.upBox, "TOPLEFT", 9, -uy)
            r:SetSize(cw - 20, 15); r:Show()
            uy = uy + 16
        end
        for k = #nx + 1, #c.upRows do c.upRows[k]:Hide() end
        c.upBox:ClearAllPoints(); c.upBox:SetPoint("TOPLEFT", 2, -y)
        c.upBox:SetWidth(cw - 2); c.upBox:SetHeight(uy + 6); c.upBox:Show()
        y = y + uy + 10
    else
        for k = 1, #c.upRows do c.upRows[k]:Hide() end
    end

    c:SetWidth(ContentW()); c:SetHeight(y)
end

-- Lazily build the preview-overview widgets (framed icon, title, three stat cards, a "start
-- here" block and the tier roadmap), pooled on the content frame and reused each render.
local function EnsureOverview(c)
    if c.ov then return c.ov end
    local ov = { roadRows = {} }
    c.ov = ov

    ov.iconBorder = c:CreateTexture(nil, "BORDER"); ov.iconBorder:SetColorTexture(0.5, 0.42, 0.28, 0.6)
    ov.icon = c:CreateTexture(nil, "ARTWORK"); ov.icon:SetSize(48, 48); ov.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ov.iconBorder:SetPoint("TOPLEFT", ov.icon, "TOPLEFT", -2, 2); ov.iconBorder:SetPoint("BOTTOMRIGHT", ov.icon, "BOTTOMRIGHT", 2, -2)

    ov.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); ov.title:SetJustifyH("LEFT")
    ov.sub = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ov.sub:SetJustifyH("LEFT")

    ov.cards = {}
    for i = 1, 3 do
        local card = CreateFrame("Frame", nil, c, "BackdropTemplate")
        card:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        card:SetBackdropColor(0.12, 0.1, 0.07, 0.85)
        card:SetBackdropBorderColor(0.5, 0.42, 0.28, 0.7)
        card.num = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); card.num:SetPoint("TOP", 0, -7)
        card.lbl = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); card.lbl:SetPoint("BOTTOM", 0, 7)
        ov.cards[i] = card
    end

    ov.startTitle = c:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ov.startTitle:SetText("|cffe6b34dStart here|r")
    ov.startIcon = c:CreateTexture(nil, "ARTWORK"); ov.startIcon:SetSize(24, 24); ov.startIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ov.startFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ov.startFS:SetJustifyH("LEFT")

    ov.roadTitle = c:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ov.roadTitle:SetText("|cffe6b34dThe path at a glance|r")

    ov.widgets = { ov.iconBorder, ov.icon, ov.title, ov.sub, ov.cards[1], ov.cards[2], ov.cards[3],
                   ov.startTitle, ov.startIcon, ov.startFS, ov.roadTitle }
    return ov
end

-- The Now tab for a profession you HAVEN'T learned: a richer overview of what leveling it
-- involves, instead of pretending you're mid-craft. Steps/Shopping still show the detail.
local function RenderOverview(prof)
    local c = win.content
    local cw = ContentW() - 4
    local ov = EnsureOverview(c)
    local steps = SW.PATHS[prof]

    -- Header: framed icon + name + "preview" subtitle.
    ov.icon:SetTexture(SW.ProfIcon(prof))
    ov.icon:ClearAllPoints(); ov.icon:SetPoint("TOPLEFT", 6, -6); ov.icon:Show(); ov.iconBorder:Show()
    ov.title:SetText("|cffffffff" .. prof .. "|r")
    ov.title:ClearAllPoints(); ov.title:SetPoint("TOPLEFT", ov.icon, "TOPRIGHT", 12, -3); ov.title:Show()
    ov.sub:SetText("|cff9a8cc0Preview|r |cff777777- you haven't learned this yet|r")
    ov.sub:ClearAllPoints(); ov.sub:SetPoint("BOTTOMLEFT", ov.icon, "BOTTOMRIGHT", 12, 5); ov.sub:Show()

    local y = 6 + 48 + 12

    -- Three stat cards: steps / crafts / total mats.
    local eff = SW.ProfEffort(prof, 0) or {}
    local big = BreakUpLargeNumbers or tostring
    local stats = { { tostring(eff.steps or 0), "steps" }, { big(eff.crafts or 0), "crafts" }, { big(eff.mats or 0), "mats" } }
    local gap = 8
    local cardW = math.floor((cw - 4 - gap * 2) / 3)
    for i, card in ipairs(ov.cards) do
        card:SetSize(cardW, 42)
        card:ClearAllPoints(); card:SetPoint("TOPLEFT", 2 + (i - 1) * (cardW + gap), -y)
        card.num:SetText("|cffffd96b" .. stats[i][1] .. "|r")
        card.lbl:SetText("|cff9a9a9a" .. stats[i][2] .. "|r")
        card:Show()
    end
    y = y + 42 + 16

    -- Start here: the first recipe.
    ov.startTitle:ClearAllPoints(); ov.startTitle:SetPoint("TOPLEFT", 4, -y); ov.startTitle:Show()
    y = y + 19
    local s1 = steps and steps[1]
    if s1 then
        ov.startIcon:SetTexture(ItemIcon(s1.item))
        ov.startIcon:ClearAllPoints(); ov.startIcon:SetPoint("TOPLEFT", 6, -y); ov.startIcon:Show()
        ov.startFS:SetWidth(cw - 40)
        ov.startFS:SetText(("|cffffffff%s|r |cff888888(skill %d-%d)|r\n|cffbfb59cLearn %s from a trainer to begin.|r"):format(s1.recipe, s1.from, s1.to, prof))
        ov.startFS:ClearAllPoints(); ov.startFS:SetPoint("TOPLEFT", 36, -y); ov.startFS:Show()
        y = y + math.max(28, (ov.startFS:GetStringHeight() or 28)) + 14
    end

    -- The path at a glance: one line per trainer tier listing its recipes.
    ov.roadTitle:ClearAllPoints(); ov.roadTitle:SetPoint("TOPLEFT", 4, -y); ov.roadTitle:Show()
    y = y + 19
    local ri = 0
    for _, tier in ipairs(SW.TIERS) do
        local lo, hi, tname = tier[1], tier[2], tier[3]
        local recs = {}
        for _, s in ipairs(steps or {}) do
            if s.from >= lo and s.from < hi then recs[#recs + 1] = s.recipe end
        end
        if #recs > 0 then
            ri = ri + 1
            local r = ov.roadRows[ri]
            if not r then
                r = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r:SetJustifyH("LEFT")
                ov.roadRows[ri] = r
            end
            r:SetWidth(cw - 10)
            r:SetText(("|cffe1b94e%s|r |cff777777%d-%d|r   |cffd2cdbf%s|r"):format(tname, lo, hi, table.concat(recs, ", ")))
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, -y); r:Show()
            y = y + (r:GetStringHeight() or 14) + 5
        end
    end
    for i = ri + 1, #ov.roadRows do ov.roadRows[i]:Hide() end
    y = y + 8

    c:SetWidth(ContentW()); c:SetHeight(y)
end

-- Header for a tier section in the Steps/Shopping lists; returns the new y.
local function TierHeader(c, hidx, y, name, lo, hi, isCurrent)
    local hdr = MakeTierHeader(c, hidx)
    hdr.bg:SetColorTexture(0.95, 0.82, 0.45, isCurrent and 0.16 or 0.06)
    hdr.accent:SetColorTexture(isCurrent and 0.4 or 0.95, isCurrent and 0.9 or 0.82, isCurrent and 0.4 or 0.45, 0.95)
    hdr.left:SetText(("|cffe6b34d%s|r%s"):format(name, isCurrent and "  |cff66ff66(you are here)|r" or ""))
    hdr.right:SetText(("skill %d-%d"):format(lo, hi))
    hdr:ClearAllPoints(); hdr:SetPoint("TOPLEFT", 0, -y); hdr:SetWidth(ContentW()); hdr:Show()
    return y + 24
end

local function RenderSteps(prof, rank)
    local steps, c = SW.PATHS[prof], win.content
    local cur = CurrentStepIndex(steps, rank)
    local showDone = DB().showCompleted
    local y, hidx, ri = 0, 0, 0
    for _, tier in ipairs(SW.TIERS) do
        local lo, hi, tname = tier[1], tier[2], tier[3]
        -- A tier shows if it has a current/upcoming step (or any step when "show completed" is on).
        local has = false
        for i, s in ipairs(steps) do if s.from >= lo and s.from < hi and (showDone or i >= cur) then has = true; break end end
        if has then
            hidx = hidx + 1
            y = TierHeader(c, hidx, y, tname, lo, hi, rank >= lo and rank < hi)
            y = y + 3
            local iw = ContentW() - 42
            for i, s in ipairs(steps) do
                if s.from >= lo and s.from < hi and (showDone or i >= cur) then
                    ri = ri + 1
                    local r = MakeStepRow(c, ri)
                    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(ContentW())
                    r._step, r._prof = s, prof
                    r.icon:SetTexture(ItemIcon(s.item))
                    r.top:SetWidth(iw); r.bot:SetWidth(iw)
                    local pat = s.vendorPattern and "  |cffff8800*|r" or ""
                    local matline = {}
                    for _, m in ipairs(s.mats) do matline[#matline + 1] = m[2] .. " " .. m[1] end
                    if i < cur then
                        r.icon:SetDesaturated(true); r.icon:SetAlpha(0.4)
                        r.top:SetText(("|cff6a6a6a[%d-%d]  %dx %s|r"):format(s.from, s.to, s.qty, s.recipe))
                        r.bot:SetText(""); r.bg:SetColorTexture(0, 0, 0, 0); r.accent:Hide()
                        r:SetHeight(22); y = y + 22
                    elseif i == cur then
                        r.icon:SetDesaturated(false); r.icon:SetAlpha(1)
                        r.top:SetText(("|cffffd100[%d-%d]|r  |cffcfcfcf%dx|r |cffffffff%s|r%s"):format(s.from, s.to, s.qty, s.recipe, pat))
                        r.bot:SetText("|cffc2bca8" .. table.concat(matline, ", ") .. "|r")
                        r.bg:SetColorTexture(0.2, 0.46, 0.2, 0.3)
                        r.accent:SetColorTexture(0.45, 0.95, 0.45, 1); r.accent:Show()
                        r:SetHeight(32); y = y + 32
                    else
                        r.icon:SetDesaturated(false); r.icon:SetAlpha(1)
                        r.top:SetText(("|cffe1b94e[%d-%d]|r  |cff999999%dx|r |cffe8dcc2%s|r%s"):format(s.from, s.to, s.qty, s.recipe, pat))
                        r.bot:SetText("|cff8f8a7e" .. table.concat(matline, ", ") .. "|r")
                        r.bg:SetColorTexture(1, 1, 1, (ri % 2 == 0) and 0.025 or 0); r.accent:Hide()
                        r:SetHeight(32); y = y + 32
                    end
                    r:Show()
                end
            end
            y = y + 7
        end
    end
    for k = ri + 1, #c.stepRows do c.stepRows[k]:Hide() end
    c:SetWidth(ContentW()); c:SetHeight(y + 4)
end

local function RenderMats(prof, rank)
    local c = win.content
    local tiers = SW.TierShopping(prof, rank)
    local y, hidx, mi = 0, 0, 0

    for _, tier in ipairs(tiers) do
        hidx = hidx + 1
        y = TierHeader(c, hidx, y, tier.name, tier.lo, tier.hi, tier.current)
        for _, m in ipairs(tier.mats) do
            mi = mi + 1
            local have = (m.id and GetItemCount(m.id, true)) or 0
            local bank = (m.id and math.max(0, have - GetItemCount(m.id))) or 0
            local r = MakeMatRow(c, mi)
            r._id, r._name, r._have, r._req, r._short, r._bank = m.id, m.name, have, m.qty, math.max(0, m.qty - have), bank
            r.icon:SetTexture(ItemIcon(m.id)); r.name:SetText(m.name)
            if tier.current then
                local col = (have >= m.qty) and "|cff66ff66" or "|cffff5552"
                r.amt:SetText(("%s%d|r |cff888888/|r %d"):format(col, have, m.qty))
            else
                r.amt:SetText(("|cffd6bd84%d|r"):format(m.qty))
            end
            r._stripe = (mi % 2 == 0)
            r.bg:SetColorTexture(1, 1, 1, r._stripe and 0.03 or 0)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(ContentW()); r:Show()
            y = y + 20
        end
        y = y + 4
    end
    for i = mi + 1, #c.matRows do c.matRows[i]:Hide() end
    if #tiers == 0 then
        local r = MakeMatRow(c, 1)
        r.icon:SetTexture(nil); r.name:SetText("|cff66ff66Max skill - nothing left to gather.|r"); r.amt:SetText("")
        r.bg:SetColorTexture(0, 0, 0, 0); r._id = nil
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, 0); r:SetWidth(ContentW()); r:Show(); y = 20
    end
    c:SetWidth(ContentW()); c:SetHeight(y + 4)
end

-- Gathering professions: a list of zone-route segments, current one highlighted.
local function RenderRoute(prof, rank)
    local c = win.content
    local segs = SW.ROUTES[prof]
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local cw = ContentW()
    local y, hidx, ridx = 0, 0, 0
    for _, seg in ipairs(segs) do
        if not seg.faction or seg.faction == faction then
            hidx = hidx + 1
            local cur = (rank >= seg.from and rank < seg.to)
            local hdr = MakeTierHeader(c, hidx)
            hdr.bg:SetColorTexture(0.95, 0.82, 0.45, cur and 0.16 or 0.06)
            hdr.accent:SetColorTexture(cur and 0.4 or 0.95, cur and 0.9 or 0.82, cur and 0.4 or 0.45, 0.95)
            hdr.left:SetText(("|cffe6b34dSkill %d-%d|r%s"):format(seg.from, seg.to, cur and "  |cff66ff66(you are here)|r" or ""))
            hdr.right:SetText(seg.faction and ("|cff888888" .. seg.faction .. "|r") or "")
            hdr:ClearAllPoints(); hdr:SetPoint("TOPLEFT", 0, -y); hdr:SetWidth(cw); hdr:Show()
            y = y + 24
            ridx = ridx + 1
            local r = MakeRouteRow(c, ridx)
            r.zones:SetWidth(cw - 18); r.zones:SetText("|cffe8dcc2" .. table.concat(seg.zones, ", ") .. "|r")
            local zh, nh = r.zones:GetStringHeight() or 12, 0
            if seg.note then
                r.note:SetWidth(cw - 18); r.note:SetText("|cff9a9a9a" .. seg.note .. "|r"); r.note:Show()
                nh = (r.note:GetStringHeight() or 12) + 2
            else
                r.note:SetText(""); r.note:Hide()
            end
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(cw); r:SetHeight(zh + nh + 4); r:Show()
            y = y + zh + nh + 12
        end
    end
    for i = hidx + 1, #c.tierHeaders do c.tierHeaders[i]:Hide() end
    for i = ridx + 1, #c.routeRows do c.routeRows[i]:Hide() end
    c:SetWidth(cw); c:SetHeight(y + 4)
end

local function Anchor()
    if not win then return end
    win:ClearAllPoints()
    if IsAttached() then
        -- Anchored to the host window's top-right (so it follows it when moved), at a draggable offset.
        local off = DB().dockOffset or {}
        win:SetPoint("TOPLEFT", win.dockFrame, "TOPRIGHT", off.x or DOCK_X, off.y or DOCK_Y)
    else
        local pos = DB().pos
        -- The spot the player moved it to, or the built-in default until they move it.
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x or DEFAULT_X, pos.y or DEFAULT_Y)
    end
end

-- Re-apply the anchor (used when the attach setting is toggled in options).
function SW.ReAnchor() if win then Anchor() end end

-- A profession has nothing left to show once it reaches the 300 cap; keep the guide hidden for it.
local function IsMaxed(prof)
    return (prof and (SW.CurrentSkill(prof) or 0) >= 300) and true or false
end

-- Bring the guide up, unless the active profession is already maxed (then stay hidden).
local function ShowWin()
    if IsMaxed(ActiveProfession()) then if win then win:Hide() end; return end
    Anchor(); SW.Refresh(); win:Show()
end

function SW.Refresh()
    if not win then return end
    local prof = ActiveProfession()
    if IsMaxed(prof) then win:Hide(); return end
    win.scroll:Show(); win.footer:Show(); win.fdiv:Show()
    for _, t in ipairs(win.tabs) do t:Show() end

    if not prof then win.skillFS:SetText(""); win:SetHeight(DEFAULT_H); HideGroups(); return end
    local rank = CurrentSkill(prof)
    win.skillFS:SetText(("|cffe8c66a%s|r  |cffffffff%d|r|cff888888/300|r"):format(prof, rank))

    HideGroups()
    if SW.ROUTES[prof] then
        -- Gathering profession: route list, no Now/Steps/Shopping tabs.
        for _, t in ipairs(win.tabs) do t:Hide() end
        win.footer:Hide(); win.fdiv:Hide()
        RenderRoute(prof, rank)
    else
        local view = DB().view or "now"
        for _, t in ipairs(win.tabs) do
            local selected = (t.view == view)
            t.selected = selected
            t:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            if selected then
                t.fs:SetTextColor(0.98, 0.93, 0.78)
                t.bg:SetColorTexture(0.85, 0.7, 0.35, 0.18)
                t:SetBackdropBorderColor(0.82, 0.67, 0.38, 0.95)
            else
                t.fs:SetTextColor(0.6, 0.57, 0.5)
                t.bg:SetColorTexture(0, 0, 0, 0.22)
                t:SetBackdropBorderColor(0.34, 0.3, 0.23, 0.7)
            end
        end
        if view == "now" then
            -- Professions you haven't learned get an overview instead of a fake "current step".
            if SW.IsLearned(prof) then RenderNow(prof, rank) else RenderOverview(prof) end
        elseif view == "steps" then RenderSteps(prof, rank)
        else RenderMats(prof, rank) end
    end
    win.scroll:SetVerticalScroll(0)

    -- Every view uses the same fixed height (capped so it never runs off-screen).
    win:SetHeight(math.min((UIParent:GetHeight() or 768) - 80, DEFAULT_H))
end

local function ClearDock()
    win.docked = false; win.autoShown = false; win.context = nil; win.dockFrame = nil
end

-- Show the guide if it isn't already up (used for the settings live-preview).
function SW.EnsureGuide()
    BuildWindow()
    if not win:IsShown() then ClearDock(); Anchor(); SW.Refresh(); win:Show() end
end

-- Clear the saved position so the window returns to its default (docks at the trade window).
function SW.ResetPosition()
    DB().pos = {}
    DB().dockOffset = nil
    if win then Anchor() end
end

-- Previews (professions you haven't learned) should land on the Now/overview tab, not on
-- whatever detail tab you last had open for a real profession.
local function DefaultViewFor(prof)
    if prof and not SW.IsLearned(prof) then DB().view = "now" end
end

-- Open the guide window for a specific profession at its saved/standalone position.
function SW.ShowGuide(prof)
    BuildWindow()
    if prof then DB().active = prof end
    DefaultViewFor(prof)
    ClearDock()
    ShowWin()
end

-- Dashboard click: open this profession's guide, or close it if it's already the one shown.
function SW.ToggleGuideFor(prof)
    BuildWindow()
    if win:IsShown() and not win.docked and DB().active == prof then
        win:Hide()
    else
        if prof then DB().active = prof end
        DefaultViewFor(prof)
        ClearDock()
        ShowWin()
    end
end

local function ToggleGuide()
    BuildWindow()
    if win:IsShown() then win:Hide() else ClearDock(); ShowWin() end
end

-- Global for the keybinding (Bindings.xml).
function SkillwrightToggleGuide() ToggleGuide() end

SLASH_SKILLWRIGHT1 = "/skillwright"
SLASH_SKILLWRIGHT2 = "/sw"
SlashCmdList["SKILLWRIGHT"] = function(input)
    input = (input or ""):lower():gsub("%s", "")
    if input == "config" or input == "options" then
        if SW.OpenOptions then SW.OpenOptions() end
    elseif input == "verify" then
        if SW.VerifyData then SW.VerifyData() end
    elseif input == "guide" then
        ToggleGuide()
    elseif SW.ToggleDashboard then
        SW.ToggleDashboard()
    else
        ToggleGuide()
    end
end

-- Map item-ID -> merchant slot for whatever the open vendor sells (used by the buy button).
local function ScanMerchant()
    win.merchantMap = {}
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, n do
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then win.merchantMap[id] = i end
    end
    win.merchantOpen = true
end

-- Which profession the open trainer teaches (match its services to our recipe sets / names).
function SW.TrainerProfession()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return nil end
    for i = 1, GetNumTrainerServices() do
        local name = GetTrainerServiceInfo(i)
        if name then
            for _, p in ipairs(SW.PROFESSIONS) do if name:find(p, 1, true) then return p end end
            for p, steps in pairs(SW.PATHS) do
                for _, s in ipairs(steps) do if s.recipe == name then return p end end
            end
        end
    end
end

-- Does the open merchant sell vendor mats this profession still needs to buy?
function SW.MerchantActionable(prof)
    if not (prof and SW.PATHS[prof] and win and win.merchantMap) then return false end
    local plan = SW.StepPlan(prof, SW.CurrentSkill(prof))
    if not (plan and not plan.done) then return false end
    for _, e in ipairs(plan.mats) do
        if win.merchantMap[e.id] and BuyQty(e) > 0 then return true end
    end
    return false
end

-- Show the companion for a context. Docks beside the Blizzard window only as the first-time
-- default; once the player has moved it (a saved pos exists), that position wins instead.
local function ShowDocked(frame, prof, ctx)
    BuildWindow()
    if prof then DB().active = prof end
    win.context = ctx; win.autoShown = true; win.dockFrame = frame
    ShowWin()
end

-- A context window closed: hide the companion if it auto-opened it; else just refresh.
local function CloseContext(ctx)
    if not win then return end
    if win.autoShown and win.context == ctx then
        win:Hide(); win.docked = false; win.autoShown = false; win.context = nil; win.dockFrame = nil
    elseif win:IsShown() then
        SW.Refresh()
    end
end

-- ----- buttons attached directly to the merchant / trainer windows (no panel needed) -----
local function MerchantNeed(prof)
    if not (prof and SW.PATHS[prof] and win and win.merchantMap) then return {} end
    local plan = SW.StepPlan(prof, SW.CurrentSkill(prof))
    if not (plan and not plan.done) then return {} end
    local out = {}
    for _, e in ipairs(plan.mats) do
        local slot = win.merchantMap[e.id]
        if slot then
            local n = BuyQty(e)
            if n > 0 then out[#out + 1] = { id = e.id, name = e.name, buyNow = n, slot = slot } end
        end
    end
    return out
end

-- The vendor's needs aggregated across EVERY learned crafting profession the character has, so
-- the merchant button buys what all your professions need here - not just the active one. Mats
-- a vendor stocks that several professions use (e.g. Coarse Thread) are summed.
local function MerchantNeedAll()
    if not (win and win.merchantMap) then return {} end
    local byId, order = {}, {}
    for _, p in ipairs(SW.CharProfessions()) do
        if p.hasGuide and SW.PATHS[p.name] then
            for _, m in ipairs(MerchantNeed(p.name)) do
                local agg = byId[m.id]
                if not agg then
                    agg = { id = m.id, name = m.name, buyNow = 0, slot = m.slot }
                    byId[m.id] = agg; order[#order + 1] = m.id
                end
                agg.buyNow = agg.buyNow + m.buyNow
            end
        end
    end
    local out = {}
    for _, id in ipairs(order) do out[#out + 1] = byId[id] end
    return out
end

local function DoBuy(list)
    for _, m in ipairs(list) do
        local _, _, _, _, numAvail = GetMerchantItemInfo(m.slot)
        local maxStack = (GetItemInfo and select(8, GetItemInfo(m.id))) or 1
        maxStack = math.max(1, maxStack or 1)
        local remaining = m.buyNow
        if numAvail and numAvail >= 0 then remaining = math.min(remaining, numAvail) end
        local g = 0
        while remaining > 0 and g < 60 do
            g = g + 1
            local n = math.min(remaining, maxStack)
            BuyMerchantItem(m.slot, n)
            remaining = remaining - n
        end
    end
end

local merchantBtn
local function UpdateMerchantButton()
    if not _G.MerchantFrame then return end
    if DB().contextButtons == false then if merchantBtn then merchantBtn:Hide() end; return end
    local list = MerchantNeedAll()
    if #list == 0 then if merchantBtn then merchantBtn:Hide() end; return end
    if not merchantBtn then
        merchantBtn = CreateFrame("Button", "SkillwrightMerchantButton", _G.MerchantFrame, "UIPanelButtonTemplate")
        merchantBtn:SetSize(150, 22)
        -- Sit in the open strip just below the vendor's name, above the first item row.
        merchantBtn:SetPoint("TOP", _G.MerchantFrame, "TOP", 0, -38)
        merchantBtn:SetFrameLevel(_G.MerchantFrame:GetFrameLevel() + 10)
        merchantBtn:SetScript("OnClick", function(self) DoBuy(self._list or {}) end)
        merchantBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Buy Skillwright reagents", 1, 0.85, 0.2)
            local total = 0
            for _, m in ipairs(self._list or {}) do
                local _, _, price, stack = GetMerchantItemInfo(m.slot)
                local per = (price and stack and stack > 0) and (price / stack) or 0
                local cost = per * m.buyNow; total = total + cost
                GameTooltip:AddDoubleLine(("%d %s"):format(m.buyNow, m.name),
                    GetCoinTextureString and GetCoinTextureString(cost) or "", 1, 1, 1, 1, 1, 1)
            end
            if total > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Total", GetCoinTextureString and GetCoinTextureString(total) or "", 0.8, 0.8, 0.8, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        merchantBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    merchantBtn._list = list
    merchantBtn:SetText("Buy needed mats")
    merchantBtn:Show()
end

-- The "Train recipes" button lives inside the guide, just above the bottom tabs. When shown it
-- lifts the scroll area so it doesn't cover the list; when hidden the scroll drops back down.
local trainerBtn
local function SetScrollBottom(y)
    if win and win.scroll then win.scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, y) end
end
local function UpdateTrainerButton()
    if not win then return end
    local hide = DB().contextButtons == false or not win.trainerOpen
    local prof = (not hide) and (SW.TrainerProfession() or ActiveProfession()) or nil
    local n = (prof and SW.HasGuide(prof)) and SW.CountTrainable(prof) or 0
    if hide or n == 0 then
        if trainerBtn then trainerBtn:Hide() end
        SetScrollBottom(34)
        return
    end
    if not trainerBtn then
        trainerBtn = CreateFrame("Button", "SkillwrightTrainerButton", win, "UIPanelButtonTemplate")
        trainerBtn:SetHeight(22)
        trainerBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 10, 36)
        trainerBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 36)
        trainerBtn:SetFrameLevel(win:GetFrameLevel() + 5)
        trainerBtn:SetScript("OnClick", function(self) SW.TrainNeeded(self._prof); UpdateTrainerButton() end)
        trainerBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Train Skillwright recipes", 1, 0.85, 0.2)
            GameTooltip:AddLine(("Trains the available recipes %s needs from the guide."):format(self._prof or ""), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        trainerBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    SetScrollBottom(62)
    trainerBtn._prof = prof
    trainerBtn:SetText(("Train recipes (%d)"):format(n))
    trainerBtn:Show()
end

-- A standard button on a Blizzard window (trade/trainer/merchant) to open/close the guide,
-- placed just left of that window's close (X) button.
local function AttachToggle(frame, getCtx)
    if not frame then return end
    if not frame.swToggle then
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(78, 17); b:SetText("Skillwright"); b:SetFrameStrata("HIGH")
        local fs = b:GetFontString(); if fs then fs:SetFontObject("GameFontNormalSmall") end
        local cb = frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"]
        if cb then b:SetPoint("RIGHT", cb, "LEFT", -4, 0)
        else b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -14) end
        b:SetScript("OnClick", function(self)
            BuildWindow()
            if win:IsShown() then win:Hide()
            else local prof, ctx = self.getCtx(); ShowDocked(frame, prof, ctx); win.autoShown = false end
        end)
        frame.swToggle = b
    end
    frame.swToggle.getCtx = getCtx
    frame.swToggle:Show()
end

-- Stop a Skillwright-initiated repeat craft the instant we hit the step's skill target. We
-- check on both TRADE_SKILL_UPDATE and SKILL_LINES_CHANGED: the former can miss the exact
-- skill-up tick during a fast repeat, while SKILL_LINES_CHANGED fires reliably on every skill
-- gain - exactly when we want to stop. StopTradeSkillRepeat cancels the queued repeats;
-- SpellStopCasting aborts the one extra craft that may already be casting (its mats aren't
-- consumed until it finishes, so we save them).
local function MaybeStopCraft()
    if not (win and win.craftStopAt and GetTradeSkillLine) then return end
    local _, cr = GetTradeSkillLine()
    if not (cr and cr >= win.craftStopAt) then return end
    -- Only ever stop the leveling recipe we started. If you've moved on to crafting something
    -- else, leave it completely alone (and disarm so we never interfere with that craft).
    local casting = UnitCastingInfo and UnitCastingInfo("player")
    if win.craftRecipe and casting and casting ~= win.craftRecipe then
        win.craftStopAt, win.craftRecipe = nil, nil
        return
    end
    win.craftStopAt, win.craftRecipe = nil, nil
    if StopTradeSkillRepeat then StopTradeSkillRepeat() end   -- cancel the queued repeats
    if SpellStopCasting then SpellStopCasting() end           -- abort the one extra craft mid-cast
    msg(("reached skill %d - stopped crafting. Train or move to the next step."):format(cr))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_CLOSE")
ev:RegisterEvent("TRADE_SKILL_UPDATE")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_UPDATE")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:RegisterEvent("TRAINER_SHOW")
ev:RegisterEvent("TRAINER_UPDATE")
ev:RegisterEvent("TRAINER_CLOSED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        SW.DB(); SW.CharDB()
        msg("loaded. Open a profession window or type /sw.")
    elseif event == "MERCHANT_SHOW" then
        BuildWindow(); ScanMerchant(); UpdateMerchantButton()
        AttachToggle(_G.MerchantFrame, function() return ActiveProfession(), "merchant" end)
        if win:IsShown() then SW.Refresh() end
    elseif event == "MERCHANT_UPDATE" then
        -- Vendor stock/links can finish loading a moment after MERCHANT_SHOW (and change on
        -- page flips), so re-scan and re-evaluate the buy buttons in case the first scan
        -- missed an item we need.
        if win and win.merchantOpen then
            ScanMerchant(); UpdateMerchantButton()
            if win:IsShown() then SW.Refresh() end
        end
    elseif event == "MERCHANT_CLOSED" then
        if merchantBtn then merchantBtn:Hide() end
        if win then
            win.merchantOpen = false; win.merchantMap = nil
            if win.context == "merchant" and win:IsShown() then
                -- The guide is docked to this vendor, so close it along with the vendor window.
                win:Hide(); ClearDock()
            elseif win:IsShown() then
                SW.Refresh()
            end
        end
    elseif event == "TRAINER_SHOW" then
        BuildWindow(); win.trainerOpen = true
        AttachToggle(_G.ClassTrainerFrame, function() return SW.TrainerProfession() or ActiveProfession(), "trainer" end)
        local prof = SW.TrainerProfession()
        if prof and SW.HasGuide(prof) and DB().autoDock ~= false then
            ShowDocked(_G.ClassTrainerFrame, prof, "trainer")
        end
        UpdateTrainerButton()
        if win:IsShown() then SW.Refresh() end
    elseif event == "TRAINER_UPDATE" then
        UpdateTrainerButton()
    elseif event == "TRAINER_CLOSED" then
        if win then win.trainerOpen = false end
        UpdateTrainerButton()
        CloseContext("trainer")
    elseif event == "TRADE_SKILL_SHOW" then
        local prof = GetTradeSkillLine and GetTradeSkillLine()
        AttachToggle(_G.TradeSkillFrame, function() return (GetTradeSkillLine and GetTradeSkillLine()) or ActiveProfession(), "trade" end)
        if prof and SW.HasGuide(prof) and DB().autoDock ~= false then
            ShowDocked(_G.TradeSkillFrame, prof, "trade")
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        CloseContext("trade")
    elseif event == "SKILL_LINES_CHANGED" then
        -- Most reliable "your skill just went up" signal - stop the craft right here.
        MaybeStopCraft()
        if win and win:IsShown() then SW.Refresh() end
    elseif event == "TRADE_SKILL_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        if event == "BAG_UPDATE_DELAYED" and win and win.merchantOpen then UpdateMerchantButton() end
        if win then
            if event == "TRADE_SKILL_UPDATE" then MaybeStopCraft() end
            if win:IsShown() then SW.Refresh() end
        end
    end
end)
