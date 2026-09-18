-- Skillwright - the guide window: Now / Route / Shopping / Settings.
-- Opens beside the profession window for that profession, or on its own from /sw and the launcher.
local ADDON, SW = ...
local U = SW.UI
local Plan = SW.Plan

local W, H = 400, 560
local ROW = 26
local win
local views = {}          -- [id] = { frame, build, refresh }
local VIEW_ORDER = { { value = "now", label = "Now" }, { value = "route", label = "Route" },
                     { value = "shop", label = "Shopping" }, { value = "settings", label = "Settings" } }

local function Est(src) return src == "est" end

-- "12g 30s", with a grey "est." in front when any part of it is a guess.
local function Cost(copper, estimated)
    return (estimated and "|cff8a8a8aest.|r " or "") .. SW.MoneyShort(copper)
end

local function ItemText(id)
    local name = U.ItemName(id)
    return name and (U.ItemQualityColor(id) .. name .. "|r") or ("|cff8a8a8aitem " .. id .. "|r")
end

local function SourceTag(src)
    if src == "r" then return "|cff8a8a8a(recipe)|r" end
    if src == "q" then return "|cff8a8a8a(quest)|r" end
    local spec = src and src:match("^s:(.+)$")
    if spec then return "|cff8a8a8a(" .. spec .. ")|r" end
    return ""
end

-- ---------------------------------------------------------------------------
-- Now
-- ---------------------------------------------------------------------------
local function BuildNow(f)
    local sf = U.Scroll(f)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -22, 0)
    local c = sf.child
    f.sf, f.c = sf, c

    c.icon = U.IconButton(c, 40)
    c.icon:SetPoint("TOPLEFT", 4, -4)
    c.title = U.Text(c, "GameFontNormalLarge")
    c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -1)
    c.title:SetPoint("RIGHT", c, "RIGHT", -4, 0)
    c.sub = U.Text(c, "GameFontHighlight")
    c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -4, 0)

    c.learn = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.warn = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.matsHead = U.Heading(c, "Materials for this step")
    c.mats = {}
    c.info = U.Text(c, "GameFontHighlightSmall", "LEFT", true)

    c.craftBtn = U.Button(c, "Craft", 110, 24)
    c.craftBtn:SetScript("OnClick", function(self)
        if self.spell and self.n and self.n > 0 then C_TradeSkillUI.CraftRecipe(self.spell, self.n) end
    end)
    c.buyBtn = U.Button(c, "Buy materials", 120, 24)
    c.buyBtn:SetScript("OnClick", function(self)
        for _, m in ipairs(self.list or {}) do SW.Prices.Buy(m.id, m.qty) end
    end)
    c.buyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Buy from this merchant", 1, 0.82, 0.3)
        local total = 0
        for _, m in ipairs(self.list or {}) do
            GameTooltip:AddDoubleLine(m.qty .. " x " .. ItemText(m.id), SW.MoneyShort(m.qty * m.unit), 1, 1, 1, 1, 1, 1)
            total = total + m.qty * m.unit
        end
        GameTooltip:AddDoubleLine("Total", SW.MoneyShort(total), 1, 0.82, 0.3, 1, 1, 1)
        GameTooltip:Show()
    end)
    c.buyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.trainBtn = U.Button(c, "Train", 120, 24)
    c.trainBtn:SetScript("OnClick", function(self) SW.Trainer.Train(self.list or {}) end)

    c.nextHead = U.Heading(c, "Up next")
    c.next = {}
    c.gapHead = U.Heading(c, "Where trainer recipes run out")
    c.gapText = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.gap = {}
    c.total = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
end

local function MatCell(c, i)
    local cell = c.mats[i]
    if cell then return cell end
    cell = U.IconButton(c, 34)
    cell.count = U.Text(cell, "GameFontHighlightSmall", "CENTER")
    cell.count:SetPoint("TOP", cell, "BOTTOM", 0, -2)
    c.mats[i] = cell
    return cell
end

-- A row with an icon and a line of text (Up next, gap options).
local function LineRow(parent, pool, i)
    local r = pool[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetHeight(20)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.text = U.Text(r, "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", -60, 0)
    r.right = U.Text(r, "GameFontHighlightSmall", "RIGHT")
    r.right:SetPoint("RIGHT", -2, 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Options_List_Hover")
    r:SetScript("OnEnter", function(self)
        if not self.tipItem and not self.tipSpell then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.tipItem and self.tipItem > 0 then GameTooltip:SetItemByID(self.tipItem) else GameTooltip:SetSpellByID(self.tipSpell) end
        if self.tipExtra then self.tipExtra(GameTooltip) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) if self.tipItem then U.HandleItemClick(self.tipItem) end end)
    pool[i] = r
    return r
end

local function HidePool(pool, from)
    for i = from, #pool do pool[i]:Hide() end
end

local function StepTooltip(step)
    return function(tt)
        tt:AddLine(" ")
        tt:AddLine(("Skill %d-%d: about %d crafts"):format(step.from, step.to, step.crafts), 1, 0.82, 0.3)
        for _, m in ipairs(step.mats) do
            tt:AddDoubleLine(m.count .. " x " .. ItemText(m.id), Cost(m.count * m.unit, Est(m.priceSource)), 1, 1, 1, 1, 1, 1)
        end
        if step.source ~= "r" and step.source ~= "q" then
            tt:AddLine(("Learn at a trainer from skill %d%s"):format(step.learn, step.learnEstimated and " (estimate)" or ""), 0.7, 0.7, 0.7)
        end
    end
end

local function RefreshNow(f)
    local c = f.c
    local prof = win.prof
    local cur = Plan.Current(prof)
    local width = f.sf:GetWidth()
    c:SetWidth(width)
    local y = -4
    local function place(widget, x, gap, h)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", c, "TOPLEFT", x or 4, y - (gap or 0))
        if widget.GetStringHeight and not widget.line then widget:SetWidth(width - (x or 4) - 6) end
        widget:Show()
        local hh = h or (widget.GetStringHeight and widget:GetStringHeight()) or widget:GetHeight()
        y = y - (gap or 0) - hh
    end

    local cp = SW.CharProf(prof)
    local have = cp.has
    for _, w in ipairs({ c.learn, c.warn, c.matsHead, c.info, c.craftBtn, c.buyBtn, c.trainBtn, c.nextHead, c.gapHead, c.gapText, c.total }) do
        w:Hide()
        if w.line then w.line:Hide() end
    end
    HidePool(c.mats, 1); HidePool(c.next, 1); HidePool(c.gap, 1)

    if not cur then
        c.icon:Hide()
        c.title:SetText("No data for this profession")
        c.sub:SetText("")
        c:SetHeight(60)
        return
    end
    local route = cur.route

    if cur.done then
        c.icon:Set(nil, nil)
        c.icon.tex:SetTexture(SW.ProfIcon(prof))
        c.icon:Show()
        if route.gapAt then
            c.title:SetText("No trainer recipe left")
            c.sub:SetText(("Nothing you can learn raises %s past %d yet."):format(SW.ProfName(prof), route.gapAt))
        else
            c.title:SetText(("%s is done"):format(SW.ProfName(prof)))
            c.sub:SetText(("Skill %d."):format(cur.rank))
        end
        y = -54
    else
        local s = cur.step
        c.icon:Set(s.item, s.spell, StepTooltip(s))
        c.icon:Show()
        c.title:SetText(U.Colored(cur.color, U.RecipeName(s.spell)) .. (s.qty > 1 and (" |cff8a8a8ax" .. s.qty .. "|r") or ""))
        c.sub:SetText(("Make about |cffffffff%d|r more|cff8a8a8a(skill %d to %d)|r"):format(cur.left, cur.rank, s.to))
        y = -54

        -- Learned? Where from?
        local learn
        if not have then
            learn = ("|cffffd100Preview|r - you don't have %s. The plan starts from skill 1."):format(SW.ProfName(prof))
        elseif cur.known then
            learn = "|cff40bf40Learned.|r"
        else
            local svc = SW.Trainer.services[s.spell]
            if svc and svc.type == "available" then
                learn = "|cffff8040Not learned yet|r - this trainer teaches it."
            elseif s.source:match("^s:") then
                learn = ("|cffff8040Not learned yet|r - a %s specialization recipe."):format(s.source:sub(3))
            else
                learn = ("|cffff8040Not learned yet|r - learn it at a trainer (needs skill %d%s)."):format(
                    s.learn, s.learnEstimated and ", estimated" or "")
            end
        end
        c.learn:SetText(learn)
        place(c.learn, 4, 6)

        local due = have and Plan.TrainingDue(prof)
        if due then
            c.warn:SetText(("|cffff6060Your skill is capped at %d.|r Learn |cffffd100%s %s|r at a trainer."):format(
                cp.max, due.name, SW.ProfName(prof)))
            place(c.warn, 4, 6)
        end

        -- Materials
        place(c.matsHead, 4, 14, 14)
        c.matsHead.line:Show()
        local perRow = math.max(1, math.floor((width - 8) / 64))
        local rowY = y - 6
        local vendorBuy, bankLines, estimated = {}, {}, false
        for i, m in ipairs(cur.mats) do
            local cell = MatCell(c, i)
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", c, "TOPLEFT", 14 + col * 64, rowY - row * 56)
            cell:Set(m.id, nil, function(tt)
                tt:AddLine(" ")
                tt:AddDoubleLine("Have / need", ("%d / %d"):format(m.have, m.need), 1, 0.82, 0.3, 1, 1, 1)
                if m.bank > 0 then tt:AddLine(("%d of those are in your bank."):format(m.bank), 0.5, 0.65, 1) end
                tt:AddDoubleLine("Price each", Cost(m.unit, Est(m.priceSource)), 0.7, 0.7, 0.7, 1, 1, 1)
            end)
            cell.count:SetText(("%s%d|r/%d"):format(m.have >= m.need and "|cff40bf40" or "|cffff6060", m.have, m.need))
            cell:Show()
            if m.short > 0 and SW.Prices.merchant[m.id] then
                vendorBuy[#vendorBuy + 1] = { id = m.id, qty = m.short, unit = m.unit }
            end
            if m.bank > 0 then bankLines[#bankLines + 1] = ("%d %s"):format(m.bank, ItemText(m.id)) end
            if Est(m.priceSource) then estimated = true end
        end
        local rows = math.ceil(#cur.mats / perRow)
        y = rowY - rows * 56

        local info = {}
        info[#info + 1] = ("This step costs about %s%s."):format(Cost(s.costEach * cur.left, estimated),
            estimated and " |cff8a8a8a(some prices are estimates)|r" or "")
        if #bankLines > 0 then info[#info + 1] = "|cff7da5ffIn your bank:|r " .. table.concat(bankLines, ", ") end
        c.info:SetText(table.concat(info, "\n"))
        place(c.info, 4, 4)

        -- Actions
        local x = 4
        local anyAction = false
        if have and cur.known and SW.Prof.IsOpen(prof) then
            local n = cur.craftable
            c.craftBtn.spell, c.craftBtn.n = s.spell, n
            c.craftBtn:SetText(n > 0 and ("Craft %d"):format(n) or "Missing materials")
            c.craftBtn:SetEnabled(n > 0)
            c.craftBtn:ClearAllPoints()
            c.craftBtn:SetPoint("TOPLEFT", c, "TOPLEFT", x, y - 8)
            c.craftBtn:Show()
            x = x + 116
            anyAction = true
        end
        if #vendorBuy > 0 then
            c.buyBtn.list = vendorBuy
            c.buyBtn:ClearAllPoints()
            c.buyBtn:SetPoint("TOPLEFT", c, "TOPLEFT", x, y - 8)
            c.buyBtn:Show()
            x = x + 126
            anyAction = true
        end
        local svcs = SW.Trainer.RouteServices(prof, route)
        if #svcs > 0 then
            c.trainBtn.list = svcs
            c.trainBtn:SetText(("Train %d recipe%s"):format(#svcs, #svcs == 1 and "" or "s"))
            c.trainBtn:ClearAllPoints()
            c.trainBtn:SetPoint("TOPLEFT", c, "TOPLEFT", x, y - 8)
            c.trainBtn:Show()
            anyAction = true
        end
        if anyAction then y = y - 36 end

        -- Up next
        local shown = 0
        for i = cur.idx + 1, math.min(#route.steps, cur.idx + 4) do
            if shown == 0 then
                place(c.nextHead, 4, 12, 14)
                c.nextHead.line:Show()
                y = y - 4
            end
            shown = shown + 1
            local st = route.steps[i]
            local r = LineRow(c, c.next, shown)
            r.icon:SetTexture(U.RecipeIcon(st.item, st.spell))
            r.text:SetText(("|cffffd100%d-%d|r  %s %s"):format(st.from, st.to, U.RecipeName(st.spell), SourceTag(st.source)))
            r.right:SetText(("x%d"):format(st.crafts))
            r.tipItem, r.tipSpell, r.tipExtra = st.item, st.spell, StepTooltip(st)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
            r:SetPoint("RIGHT", c, "RIGHT", -4, 0)
            r:Show()
            y = y - 21
        end
    end

    -- Where the plan stops: recipes that would carry it further
    if route.gapAt and route.gapOptions then
        place(c.gapHead, 4, 12, 14)
        c.gapHead.line:Show()
        c.gapText:SetText(("Trainer recipes stop giving skill at |cffffd100%d|r. Any of these would keep you going - "
            .. "they come from recipes, quests or a specialization:"):format(route.gapAt))
        place(c.gapText, 4, 4)
        y = y - 4
        for i, g in ipairs(route.gapOptions) do
            local r = LineRow(c, c.gap, i)
            r.icon:SetTexture(U.RecipeIcon(g.item, g.spell))
            r.text:SetText(("%s %s"):format(U.RecipeName(g.spell), SourceTag(g.source)))
            r.right:SetText(("|cffff8040%d|r |cffffff00%d|r |cff808080%d|r"):format(g.learn, g.yellow, g.grey))
            r.tipItem = (g.recipeItem and g.recipeItem > 0) and g.recipeItem or g.item
            r.tipSpell, r.tipExtra = g.spell, nil
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
            r:SetPoint("RIGHT", c, "RIGHT", -4, 0)
            r:Show()
            y = y - 21
        end
    end

    local crafts, cost = Plan.Remaining(prof)
    if crafts > 0 then
        c.total:SetText(("|cff8a8a8aRest of the route: about|r %d crafts |cff8a8a8aand|r %s|cff8a8a8a, skill %d to %d.|r"):format(
            crafts, SW.MoneyShort(cost), math.max(1, cur.rank), route.to))
        place(c.total, 4, 14)
    end
    c:SetHeight(-y + 10)
end

-- ---------------------------------------------------------------------------
-- Route
-- ---------------------------------------------------------------------------
local function BuildRoute(f)
    local sf = U.Scroll(f)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -22, 0)
    f.sf, f.c = sf, sf.child
    f.rows = {}
    f.note = U.Text(sf.child, "GameFontHighlightSmall", "LEFT", true)
end

local function RouteRow(f, i)
    local r = f.rows[i]
    if r then return r end
    r = LineRow(f.c, f.rows, i)
    r:SetHeight(ROW)
    r.icon:SetSize(22, 22)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetAtlas("Options_List_Active")
    r.range = U.Text(r, "GameFontNormalSmall")
    r.range:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.range:SetWidth(52)
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", r.range, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT", -70, 0)
    return r
end

local function RefreshRoute(f)
    local prof = win.prof
    local route = Plan.Route(prof)
    local c = f.c
    c:SetWidth(f.sf:GetWidth())
    HidePool(f.rows, 1)
    if not route then f.note:SetText("") return end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local y, n = -2, 0
    for _, s in ipairs(route.steps) do
        if s.to > rank then
            n = n + 1
            local r = RouteRow(f, n)
            local current = rank >= s.from and rank < s.to
            r.bg:SetShown(current)
            r.icon:SetTexture(U.RecipeIcon(s.item, s.spell))
            r.range:SetText(("%d-%d"):format(s.from, s.to))
            local est = false
            for _, m in ipairs(s.mats) do if Est(m.priceSource) then est = true end end
            local known = SW.Prof.Knows(prof, s.spell)
            r.text:SetText((known and "" or "|cffff8040*|r ") .. U.RecipeName(s.spell) .. " " .. SourceTag(s.source))
            local crafts = current and Plan.CraftsLeft(s, rank) or s.crafts
            r.right:SetText(("x%d  %s"):format(crafts, Cost(crafts * s.costEach, est)))
            r.tipItem, r.tipSpell, r.tipExtra = s.item, s.spell, StepTooltip(s)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
            r:SetPoint("RIGHT", c, "RIGHT", -2, 0)
            r:Show()
            y = y - ROW - 1
        end
    end
    local notes = { "|cffff8040*|r not learned yet.  |cff8a8a8aest.|r price includes estimates." }
    if route.gapAt then
        notes[#notes + 1] = ("The route ends at |cffffd100%d|r: no trainer recipe gives skill past that. See Now for recipes that would."):format(route.gapAt)
    end
    f.note:SetText(table.concat(notes, "\n"))
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y - 8)
    f.note:SetWidth(c:GetWidth() - 10)
    c:SetHeight(-y + 16 + f.note:GetStringHeight())
end

-- ---------------------------------------------------------------------------
-- Shopping
-- ---------------------------------------------------------------------------
local function BuildShop(f)
    local sf = U.Scroll(f)
    sf:SetPoint("TOPLEFT", 0, -30)
    sf:SetPoint("BOTTOMRIGHT", -22, 0)
    f.sf, f.c = sf, sf.child
    f.rows, f.heads = {}, {}
    f.buy = U.Button(f, "Buy from this merchant", 170, 22)
    f.buy:SetPoint("TOPLEFT", 0, -2)
    f.buy:SetScript("OnClick", function(self)
        for _, m in ipairs(self.list or {}) do SW.Prices.Buy(m.id, m.qty) end
    end)
    f.hint = U.Text(f, "GameFontHighlightSmall", "LEFT", true)
    f.hint:SetPoint("TOPLEFT", 2, -6)
    f.hint:SetPoint("RIGHT", -4, 0)
    f.total = U.Text(sf.child, "GameFontHighlightSmall", "LEFT", true)
end

local function RefreshShop(f)
    local prof = win.prof
    local c = f.c
    c:SetWidth(f.sf:GetWidth())
    HidePool(f.rows, 1)
    for _, h in ipairs(f.heads) do h:Hide(); h.line:Hide() end
    local groups = Plan.Shopping(prof)
    local y, n, nh, total, est = -2, 0, 0, 0, false
    local buyList = {}
    for _, g in ipairs(groups) do
        nh = nh + 1
        local h = f.heads[nh]
        if not h then h = U.Heading(c, ""); f.heads[nh] = h end
        h:SetText(("%s |cff8a8a8a(to %d)|r  %s"):format(g.tier.name, g.tier.cap, SW.MoneyShort(g.cost)))
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 2, y - 6)
        h:Show(); h.line:Show()
        y = y - 26
        table.sort(g.order, function(a, b) return a.need * a.unit > b.need * b.unit end)
        for _, e in ipairs(g.order) do
            n = n + 1
            local r = LineRow(c, f.rows, n)
            r.icon:SetTexture(U.ItemIcon(e.id))
            r.text:SetText(ItemText(e.id))
            local col = e.have >= e.need and "|cff40bf40" or "|cffffffff"
            r.right:SetText(("%s%d|r/%d  %s"):format(col, math.min(e.have, e.need), e.need, Cost(e.need * e.unit, Est(e.priceSource))))
            r.text:SetPoint("RIGHT", -110, 0)
            r.tipItem, r.tipSpell = e.id, nil
            r.tipExtra = function(tt)
                tt:AddLine(" ")
                tt:AddDoubleLine("Have / need", ("%d / %d"):format(e.have, e.need), 1, 0.82, 0.3, 1, 1, 1)
                local src = ({ ah = "auction house", vendor = "vendor", craft = "made from its own materials", est = "estimate - no price data" })[e.priceSource] or e.priceSource
                tt:AddDoubleLine("Price each", SW.MoneyShort(e.unit), 0.7, 0.7, 0.7, 1, 1, 1)
                tt:AddLine("Source: " .. src, 0.6, 0.6, 0.6)
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", 6, y)
            r:SetPoint("RIGHT", c, "RIGHT", -2, 0)
            r:Show()
            y = y - 21
            total = total + e.need * e.unit
            if Est(e.priceSource) then est = true end
            if e.short > 0 and SW.Prices.merchant[e.id] then
                local ex
                for _, b in ipairs(buyList) do if b.id == e.id then ex = b end end
                if ex then ex.qty = ex.qty + e.short else buyList[#buyList + 1] = { id = e.id, qty = e.short, unit = e.unit } end
            end
        end
    end
    if #buyList > 0 then
        f.buy.list = buyList
        f.buy:SetText(("Buy %d item type%s from this merchant"):format(#buyList, #buyList == 1 and "" or "s"))
        f.buy:SetWidth(f.buy:GetFontString():GetStringWidth() + 30)
        f.buy:Show()
        f.hint:Hide()
    else
        f.buy:Hide()
        f.hint:SetText("|cff8a8a8aEverything still needed for the rest of the route.|r")
        f.hint:Show()
    end
    f.total:SetText(("Total: %s%s"):format(Cost(total, est),
        est and "\n|cff8a8a8aest. = includes estimates. Open the auction house and press Scan prices for real ones.|r" or ""))
    f.total:ClearAllPoints()
    f.total:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y - 10)
    f.total:SetWidth(c:GetWidth() - 10)
    c:SetHeight(-y + 20 + f.total:GetStringHeight())
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local function BuildSettings(f)
    local checks = {}
    f.checks = checks
    local y = -6
    local function heading(text)
        local h = U.Heading(f, text)
        h:SetPoint("TOPLEFT", 2, y)
        y = y - 26
    end
    local function checkbox(label, key, tip, after)
        local cb = U.Checkbox(f, label)
        cb:SetPoint("TOPLEFT", 4, y)
        cb.key = key
        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked() and true or false
            if self.invert then v = not v end
            SW.Settings()[key] = v
            if after then after() end
        end)
        if tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label, 1, 0.82, 0.3)
                GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        checks[#checks + 1] = cb
        y = y - 28
    end
    heading("Window")
    checkbox("Open with the profession window", "autoOpen")
    checkbox("Attach to the profession window", "attach", nil, function() SW.Anchor() end)
    checkbox("Show the minimap button", "hideMinimap", nil, function() SW.UpdateMinimap() end)
    checks[#checks].invert = true
    y = y - 6
    heading("Route")
    checkbox("Use camp stations", "allowCamp",
        "Plan recipes that need one of Forever's camp stations (Tanning Rack, Spinning Wheel, Master Forge ...). "
        .. "Leave off unless you have one.", function() Plan.Invalidate() end)

    f.specLabel = U.Text(f, "GameFontHighlight")
    f.specLabel:SetPoint("TOPLEFT", 8, y - 4)
    f.specY = y - 22
    y = y - 60

    local help = U.Text(f, "GameFontHighlightSmall", "LEFT", true)
    help:SetPoint("TOPLEFT", 4, y)
    help:SetPoint("RIGHT", -4, 0)
    help:SetText("|cffffd100How the plan works|r\n"
        .. "Skillwright picks, for every skill point, the recipe with the lowest cost (Cheapest) or the fewest crafts "
        .. "(Fastest) per skill-up, from the recipes a trainer teaches and the ones you already know.\n\n"
        .. "|cffffd100Prices|r come from Auctionator or TSM when installed, else from your own scan: open the auction house "
        .. "and press |cffffd100Scan prices|r. Without any, prices are estimates (marked est.).\n\n"
        .. "|cffffd100Trainers|r: the game doesn't say what skill a trainer recipe needs until you see it at a trainer. "
        .. "Visit your trainer once and the plan uses the real numbers.")
end

local function RefreshSettings(f)
    for _, cb in ipairs(f.checks) do
        local v = SW.Settings()[cb.key] and true or false
        if cb.invert then v = not v end
        cb:SetChecked(v)
    end
    local prof = win.prof
    local specs = SW.PROFESSIONS[prof] and SW.PROFESSIONS[prof].specs
    if f.spec then f.spec:Hide() end
    if specs then
        f.specLabel:SetText(("%s specialization"):format(SW.ProfName(prof)))
        f.specLabel:Show()
        f.specCtl = f.specCtl or {}
        local ctl = f.specCtl[prof]
        if not ctl then
            local items = { { value = "none", label = "None" } }
            for _, s in ipairs(specs) do items[#items + 1] = { value = s, label = s } end
            ctl = U.Segmented(f, items, 90 * #items, function(v)
                SW.CharProf(prof).spec = (v ~= "none") and v or nil
                Plan.Invalidate(prof)
            end)
            ctl:SetPoint("TOPLEFT", 8, f.specY)
            f.specCtl[prof] = ctl
        end
        ctl:Select(Plan.Spec(prof) or "none")
        ctl:Show()
        f.spec = ctl
    else
        f.specLabel:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local function DefaultProf()
    local open = SW.Prof.OpenLine()
    if open and SW.PROFESSIONS[open] then return open end
    local last = SW.CharDB().lastProf
    if last and SW.PROFESSIONS[last] then return last end
    return SW.Prof.Mine()[1] or SW.Prof.All()[1]
end

local function Refresh()
    if not win or not win:IsShown() then return end
    local prof = win.prof
    local cp = SW.CharProf(prof)
    win.profIcon:SetTexture(SW.ProfIcon(prof))
    if cp.has then
        win.profText:SetText(("%s  |cffffffff%d|r|cff8a8a8a/%d|r"):format(SW.ProfName(prof), cp.rank or 0, cp.max or 0))
    else
        win.profText:SetText(("%s  |cff8a8a8a(preview)|r"):format(SW.ProfName(prof)))
    end
    win.mode:Select(SW.Settings().mode)
    local v = views[win.view]
    if v and v.frame then v.refresh(v.frame) end
    -- Footer: where prices come from, and the scan button at the auction house.
    local src = SW.Prices.SourceText()
    win.status:SetText(src and ("|cff8a8a8aPrices:|r " .. src) or "|cff8a8a8aPrices: estimates - scan the auction house for real ones|r")
    win.scan:SetShown(SW.Prices.CanScan() and true or false)
    win.scan:SetEnabled(not SW.Prices.Scanning())
    win.scan:SetText(SW.Prices.Scanning() and "Scanning..." or "Scan prices")
end

function SW.RefreshWindow()
    SW.Debounce("uiRefresh", 0.1, Refresh)
end

local function SelectView(id)
    win.view = id
    for vid, v in pairs(views) do
        if vid == id then
            if not v.frame then
                v.frame = CreateFrame("Frame", nil, win.body)
                v.frame:SetAllPoints()
                v.build(v.frame)
            end
            v.frame:Show()
        elseif v.frame then
            v.frame:Hide()
        end
    end
    win.tabs:Select(id)
    Refresh()
end

-- Anchor: beside the open profession window when attached, else where the player left it.
function SW.Anchor()
    if not win then return end
    win:ClearAllPoints()
    local host = ProfessionsFrame
    if win.attached and SW.Settings().attach and host and host:IsShown() then
        win:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, 0)
        return
    end
    local pos = SW.DB().pos
    if pos and pos.x then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
    end
end

local function OpenProfMenu(owner)
    local function pick(id)
        win.prof = id
        SW.CharDB().lastProf = id
        Refresh()
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle("Profession")
            local mine = {}
            for _, id in ipairs(SW.Prof.Mine()) do mine[id] = true end
            for _, id in ipairs(SW.Prof.All()) do
                local cp = SW.CharProf(id)
                local label = mine[id] and ("%s |cff8a8a8a%d|r"):format(SW.ProfName(id), cp.rank or 0)
                    or ("|cff8a8a8a%s (preview)|r"):format(SW.ProfName(id))
                root:CreateRadio(label, function() return win.prof == id end, function() pick(id) end)
            end
        end)
    else
        local all = SW.Prof.All()
        local nextIdx = 1
        for i, id in ipairs(all) do if id == win.prof then nextIdx = i % #all + 1 end end
        pick(all[nextIdx])
    end
end

local function Build()
    if win then return end
    win = U.Window("SkillwrightFrame", UIParent, W, H, "Skillwright")
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SW.DB().pos = { x = self:GetLeft(), y = self:GetTop() }
        self.attached = false
    end)

    local close = win.ClosePanelButton or win.CloseButton
    if not close then
        close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts")
        close:SetPoint("TOPRIGHT", 0, 1)
    end
    close:SetScript("OnClick", function() win:Hide() end)

    -- Profession picker
    local pb = CreateFrame("Button", nil, win)
    pb:SetPoint("TOPLEFT", 18, -30)
    pb:SetSize(210, 24)
    win.profIcon = pb:CreateTexture(nil, "ARTWORK")
    win.profIcon:SetSize(22, 22)
    win.profIcon:SetPoint("LEFT", 0, 0)
    win.profIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    win.profText = U.Text(pb, "GameFontNormal")
    win.profText:SetPoint("LEFT", win.profIcon, "RIGHT", 6, 0)
    local arrow = pb:CreateTexture(nil, "ARTWORK")
    arrow:SetAtlas("common-dropdown-a-button")
    arrow:SetSize(18, 18)
    arrow:SetPoint("LEFT", win.profText, "RIGHT", 4, -1)
    local hl = pb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Options_List_Hover")
    pb:SetScript("OnClick", OpenProfMenu)

    -- Cheapest / Fastest
    win.mode = U.Segmented(win, {
        { value = "cheap", label = "Cheapest", tooltip = "The least gold per skill point, from market prices." },
        { value = "fast", label = "Fastest", tooltip = "The fewest crafts per skill point (orange and yellow recipes first)." },
    }, 150, function(v) SW.SetMode(v) end)
    win.mode:SetPoint("TOPRIGHT", -18, -31)

    win.tabs = U.Tabs(win, VIEW_ORDER, SelectView)
    win.tabs:SetPoint("TOPLEFT", 16, -58)
    local divider = win:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 14, -91)
    divider:SetPoint("TOPRIGHT", -16, -91)

    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", 16, -98)
    win.body:SetPoint("BOTTOMRIGHT", -12, 40)

    win.scan = U.Button(win, "Scan prices", 100, 22)
    win.scan:SetPoint("BOTTOMRIGHT", -14, 12)
    win.scan:SetScript("OnClick", function() SW.Prices.StartScan() end)
    win.status = U.Text(win, "GameFontHighlightSmall")
    win.status:SetPoint("BOTTOMLEFT", 18, 17)
    win.status:SetPoint("RIGHT", win.scan, "LEFT", -8, 0)

    views.now = { build = BuildNow, refresh = RefreshNow }
    views.route = { build = BuildRoute, refresh = RefreshRoute }
    views.shop = { build = BuildShop, refresh = RefreshShop }
    views.settings = { build = BuildSettings, refresh = RefreshSettings }

    win:SetScript("OnShow", function() SW.RefreshWindow() end)
    win:Hide()
end

-- Show the guide for a profession (nil = the best guess) on a tab (nil = keep the current one).
function SW.ShowWindow(prof, view, attached)
    Build()
    win.prof = prof or win.prof or DefaultProf()
    if not win.prof then return end
    SW.CharDB().lastProf = win.prof
    win.attached = attached and true or false
    SW.Anchor()
    win:Show()
    SelectView(view or win.view or "now")
end

function SW.ToggleWindow()
    if win and win:IsShown() then win:Hide() else SW.ShowWindow() end
end

function SW.WindowShown() return win and win:IsShown() end

-- Opening a profession window opens (and attaches) its guide; closing it closes a guide it opened.
SW.Listen("PROFESSION_OPEN", function(id)
    if not SW.PROFESSIONS[id] then return end
    if win and win:IsShown() then
        if win.prof ~= id or not win.attached then
            local wasAuto = win.autoShown
            SW.ShowWindow(id, nil, true)
            win.autoShown = wasAuto
        else
            SW.RefreshWindow()
        end
        return
    end
    if SW.Settings().autoOpen then
        SW.ShowWindow(id, nil, true)
        win.autoShown = true
    end
end)
SW.Listen("PROFESSION_CLOSED", function()
    if not win or not win:IsShown() then return end
    if win.autoShown then
        win:Hide()
        win.autoShown = false
    else
        win.attached = false
        SW.Anchor()
    end
end)
-- The profession window can be moved by the UI panel manager; re-anchor when it is (re)shown.
SW.Listen("LOGIN", function()
    hooksecurefunc("ShowUIPanel", function(frame)
        if frame == ProfessionsFrame and win and win.attached then SW.Anchor() end
    end)
end)

for _, ev in ipairs({ "PLAN_CHANGED", "RANKS_CHANGED", "MERCHANT_CHANGED", "TRAINER_CHANGED", "SCAN_STATE", "RECIPES_CHANGED" }) do
    SW.Listen(ev, SW.RefreshWindow)
end
SW.On("BAG_UPDATE_DELAYED", SW.RefreshWindow)
SW.On("GET_ITEM_INFO_RECEIVED", function() SW.Debounce("itemInfo", 0.4, Refresh) end)
SW.On("AUCTION_HOUSE_SHOW", SW.RefreshWindow)
SW.On("AUCTION_HOUSE_CLOSED", SW.RefreshWindow)
SW.On("TRADE_SKILL_LIST_UPDATE", SW.RefreshWindow)
