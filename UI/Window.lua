-- Skillwright - the guide window: Now / Route / Shopping / Settings.
-- Opens beside the profession window for that profession, or on its own from /skw and the minimap button.
local ADDON, SW = ...
local U = SW.UI
local Plan = SW.Plan

local W, H = 400, 560
local ROW = 26
local win
local views = {}          -- [id] = { frame, build, refresh }
-- The settings live in the YippYapp window (LibForever); the gear in the corner opens them. Without the
-- lib they stay a tab of our own, so nothing is stranded.
local HOSTED_SETTINGS = false
local VIEW_ORDER = { { value = "now", label = "Now" }, { value = "route", label = "Route" },
                     { value = "shop", label = "Shopping" }, { value = "settings", label = "Settings" } }

local AltMenu   -- "or make this instead" (defined below, used by the Now view's widgets)

local function Est(src) return src == "est" end

-- "12g 30s", with a grey "est." in front when any part of it is a guess.
local function Cost(copper, estimated)
    return (estimated and "|cff8a8a8aest.|r " or "") .. SW.MoneyShort(copper)
end

-- An item's name, while the client is still loading it, and if it never arrives.
local function ItemText(id)
    local name, waits = SW.ItemName(id)
    if name then return U.ItemQualityColor(id) .. name .. "|r" end
    if waits > 6 then return ("|cff8a8a8aUnknown item (%d)|r"):format(id) end
    return "|cff8a8a8aLoading...|r"
end

-- Tier-1 camp recipes: the quest "Camping 101: <Profession>" (from a camping NPC, not the trainer) at skill 20.
local CAMP_QUEST_HINT = "taught by the quest \"Camping 101\" from a camping NPC (not the trainer) once your "
    .. "skill is 20."

-- What "est." means right now: before any auction prices it's a hint to scan; after a scan, the item simply
-- wasn't listed (or Auctionator/TSM has no price for it).
local function EstNote()
    local status = SW.Prices.Status()
    if status == "none" or status == "stale" then
        return "est. = estimated price. Open the auction house and press Scan prices for real ones."
    end
    return "est. = nobody was selling it at the auction house, so the price is estimated."
end

-- True only when every material has a real vendor price behind it.
local function AllFromVendor(mats)
    if not mats or #mats == 0 then return false end
    for _, m in ipairs(mats) do
        if m.priceSource ~= "vendor" then return false end
    end
    return true
end

-- Tags on a route row have to read plainly on their own: if one needs explaining, it is the wrong words.
local function SourceTag(src)
    if src == "r" then return "|cff8a8a8a(you need the recipe first)|r" end
    if src == "q" then return "|cff8a8a8a(from a quest)|r" end
    if src == "c" then return "|cff8a8a8a(from the camping quest)|r" end
    local spec = src and src:match("^s:(.+)$")
    if spec then return ("|cff8a8a8a(needs %s)|r"):format(spec) end
    return ""
end

-- What the materials for a step mean for the player: already in the bags, or simply buyable.
local MatsTag
function SW.MatsTagForTest(step) return MatsTag(step) end
MatsTag = function(step)
    if step.haveMats then return " |cff40bf40(you have the mats)|r" end
    if step.vendorOnly and AllFromVendor(step.mats) then return " |cff40bf40(mats from a vendor)|r" end
    return ""
end

-- ---------------------------------------------------------------------------
-- Now
-- ---------------------------------------------------------------------------
-- Click on an enchant's target slot (full and minimal view): pick the item from a menu, right-click clears.
local function TargetSlotClick(self, button)
    local spell = self.spell
    if not spell then return end
    if button == "RightButton" then
        SW.Enchant.choice[spell] = false
        SW.RefreshWindow()
        return
    end
    local current, targets = SW.Enchant.Target(spell)
    if not targets or #targets == 0 then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle("Enchant onto")
        for _, t in ipairs(targets) do
            local label = ("|T%s:16|t %s%s"):format(U.ItemIcon(t.id), t.link or ItemText(t.id),
                t.equipped and " |cffff6060(worn)|r" or "")
            root:CreateRadio(label, function() return current and current.guid == t.guid end, function()
                SW.Enchant.choice[spell] = t.guid
                SW.RefreshWindow()
            end)
        end
        root:CreateRadio("No target", function() return current == nil end, function()
            SW.Enchant.choice[spell] = false
            SW.RefreshWindow()
        end)
    end)
end

-- The Craft button's job for a step (full and minimal view): what it crafts and what it says.
local function CraftClick(self)
    if self.spell and self.n and self.n > 0 then SW.CraftStep(self.spell, self.n, self.enchant) end
end

local function SetupCraftButton(btn, cur, prof)
    local s, tool = cur.step, cur.tool
    local isEnchant = not tool and SW.Enchant.IsEnchant(s)
    local n = cur.craftable
    btn.spell, btn.n, btn.enchant = tool and tool.spell or s.spell, n, isEnchant
    if n <= 0 then
        btn:SetText("Missing materials")
    elseif isEnchant and SW.Enchant.OneAtATime(s.spell) then
        btn:SetText(("Enchant  (%d left)"):format(cur.left))   -- onto an item the game takes one click per cast
    else
        btn:SetText(("Craft %d"):format(n))
    end
    btn:SetEnabled(n > 0)
end

local function BuildNow(f)
    local sf = U.Scroll(f)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -22, 0)
    local c = sf.child
    f.sf, f.c = sf, c

    c.icon = U.IconButton(c, 40)
    c.icon:SetPoint("TOPLEFT", 4, -4)
    c.title = U.Text(c, "GameFontNormalLarge", "LEFT", true)
    c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -1)
    c.title:SetPoint("RIGHT", c, "RIGHT", -4, 0)
    c.sub = U.Text(c, "GameFontHighlight", "LEFT", true)
    c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -4, 0)

    c.learn = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    -- Recipes that are the same for the plan (Rough Sharpening Stone / Rough Weightstone): the player picks
    c.alts = CreateFrame("Button", nil, c)
    c.alts:SetHeight(16)
    c.altsText = U.Text(c.alts, "GameFontHighlightSmall", "LEFT", true)
    c.altsText:SetPoint("TOPLEFT", 0, 0)
    c.altsText:SetPoint("RIGHT", c.alts, "RIGHT", 0, 0)
    c.alts:SetScript("OnClick", function(self) AltMenu(self) end)
    c.alts:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Same for the plan", 1, 0.82, 0.3)
        GameTooltip:AddLine("These give the same skill from the same kind of materials. Pick the one you "
            .. "actually want; Skillwright remembers it for this profession.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    c.alts:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.warn = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.matsHead = U.Heading(c, "Materials for this step")
    c.mats = {}
    c.info = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.trade = U.Text(c, "GameFontHighlightSmall", "LEFT", true)   -- what the other mode would cost

    c.craftBtn = U.Button(c, "Craft", 110, 24)
    c.craftBtn:SetScript("OnClick", CraftClick)

    -- Enchants: the item it goes on, as a slot like the profession window's "Optional Target"
    c.targetLabel = U.Text(c, "GameFontNormal")
    c.targetLabel:SetText("Optional Target:")
    local slot = CreateFrame("Button", nil, c)
    slot:SetSize(36, 36)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints()
    slot.bg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.plus = slot:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge")
    slot.plus:SetPoint("BOTTOMRIGHT", -1, 0)
    slot.plus:SetText("+")
    local shl = slot:CreateTexture(nil, "HIGHLIGHT")
    shl:SetAllPoints()
    shl:SetColorTexture(1, 1, 1, 0.12)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.link then
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click: choose another item.  Right-click: no target.", 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine("Select Item to Enchant", 1, 0.82, 0.3)
            GameTooltip:AddLine("Pick an item from your bags for Craft to enchant.", 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot:SetScript("OnClick", TargetSlotClick)
    c.targetSlot = slot
    c.targetText = U.Text(c, "GameFontHighlight", "LEFT", true)
    -- Same setting as in Settings, right where it matters
    c.autoCB = U.Checkbox(c, "Say Yes to \"replace enchant\" automatically")
    c.autoCB.label:SetFontObject("GameFontHighlightSmall")
    c.autoCB:SetScript("OnClick", function(self)
        SW.Settings().autoReplaceEnchant = self:GetChecked() and true or false
    end)
    c.autoCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Replace enchant", 1, 0.82, 0.3)
        GameTooltip:AddLine("Every cast onto the same item asks whether to replace the enchant it already has. "
            .. "With this on, Skillwright answers Yes - only for casts started from its own Craft button, and "
            .. "never for gear you are wearing.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    c.autoCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.buyBtn = U.Button(c, "Buy materials", 120, 24)
    c.buyBtn:SetScript("OnClick", function(self) SW.Prices.ConfirmBuy(self.list) end)
    c.buyBtn:SetScript("OnEnter", function(self) SW.Prices.BuyTooltip(self, self.list) end)
    c.buyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- "Go and learn this": the panel that takes over the page when a recipe has to be trained first,
    -- because that is what actually blocks the route.
    c.learnBox = CreateFrame("Frame", nil, c)
    c.learnBox.bg = c.learnBox:CreateTexture(nil, "BACKGROUND")
    c.learnBox.bg:SetAllPoints()
    c.learnBox.bg:SetColorTexture(0, 0, 0, 0.35)
    c.learnBox.edge = c.learnBox:CreateTexture(nil, "BORDER")
    c.learnBox.edge:SetPoint("TOPLEFT")
    c.learnBox.edge:SetPoint("BOTTOMLEFT")
    c.learnBox.edge:SetWidth(3)
    c.learnBox.edge:SetColorTexture(1, 0.5, 0.25, 0.9)
    c.learnBox.head = U.Text(c.learnBox, "GameFontNormalLarge", "LEFT", true)
    c.learnBox.head:SetPoint("TOPLEFT", 10, -8)
    c.learnBox.head:SetPoint("RIGHT", c.learnBox, "RIGHT", -8, 0)
    c.learnBox.rows = {}
    for i = 1, 4 do
        local r = CreateFrame("Frame", nil, c.learnBox)
        r:SetHeight(22)
        r.icon = U.IconButton(r, 20)
        r.icon:SetPoint("TOPLEFT", 0, 0)
        r.text = U.Text(r, "GameFontHighlight", "LEFT", true)
        r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2)
        r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r:Hide()
        c.learnBox.rows[i] = r
    end
    c.learnBox.where = U.Text(c.learnBox, "GameFontHighlight", "LEFT", true)
    c.learnBox.hint = U.Text(c.learnBox, "GameFontHighlightSmall", "LEFT", true)
    c.learnBox:Hide()

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
    r.right = U.Text(r, "GameFontHighlightSmall", "RIGHT")
    r.right:SetPoint("RIGHT", -2, 0)
    r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
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

-- The "or make this instead" menu: every recipe that is interchangeable here, with what it costs, plus
-- "whichever is cheapest" to forget the choice.
AltMenu = function(owner)
    local prof = win.prof
    local cur = Plan.Current(prof)
    local step = cur and cur.step
    if not step then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Make instead")
        root:CreateRadio("Let Skillwright choose", function() return not Plan.Preferred(prof, step.spell)
            and not step.chosenByPlayer end, function() Plan.Prefer(prof, nil) end)
        -- everything that is a guaranteed skill-up right now, cheapest-to-finish first
        local listed = {}
        for _, o in ipairs(cur.orange or {}) do
            listed[o.spell] = true
            local mats = {}
            for i = 1, #o.mats, 2 do
                mats[#mats + 1] = ("%dx %s"):format(o.mats[i + 1], U.ItemName and U.ItemName(o.mats[i])
                    or (SW.ItemName(o.mats[i]) or ("item " .. o.mats[i])))
            end
            local label = ("%s  |cff8a8a8a%s|r"):format(U.RecipeName(o.spell), table.concat(mats, " + "))
            if (o.canMake or 0) > 0 then
                label = label .. ("  |cff40bf40you can make %d|r"):format(o.canMake)
            end
            if (o.missing or 0) > 0 then
                label = label .. ("  |cff8a8a8a%s to buy|r"):format(SW.MoneyShort(o.missing))
            end
            root:CreateRadio(label, function() return Plan.Preferred(prof, o.spell) end,
                function() Plan.Prefer(prof, o.spell) end)
        end
        -- and the recipes that are interchangeable for the plan itself
        for _, a in ipairs(step.alts or {}) do
            if not listed[a.spell] then
                local extra = (a.cost or 0) - (step.costEach or 0)
                local label = U.RecipeName(a.spell)
                if extra > 0 then
                    label = label .. ("  |cff8a8a8a+%s each|r"):format(SW.MoneyShort(extra))
                elseif extra < 0 then
                    label = label .. ("  |cff40bf40%s less each|r"):format(SW.MoneyShort(-extra))
                end
                root:CreateRadio(label, function() return Plan.Preferred(prof, a.spell) end,
                    function() Plan.Prefer(prof, a.spell) end)
            end
        end
    end)
end

-- Exposed so the offline test can build tooltips: hover code is otherwise never exercised.
local StepTooltip
function SW.StepTooltipForTest(step) return StepTooltip(step) end
StepTooltip = function(step)
    return function(tt)
        tt:AddLine(" ")
        tt:AddLine(("Skill %d-%d: about %d crafts"):format(step.from or 0, step.to or 0, step.crafts or 0),
            1, 0.82, 0.3)
        -- a tooltip runs on hover, where a mistake is only ever seen by the player: it degrades, never throws
        for _, m in ipairs(step.mats or {}) do
            local n = m.count or m.per
            local left = n and (n .. " x " .. ItemText(m.id)) or ItemText(m.id)
            local right = (n and m.unit) and Cost(n * m.unit, Est(m.priceSource)) or ""
            tt:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
        end
        if step.source == "c" then
            tt:AddLine((CAMP_QUEST_HINT:gsub("^%l", string.upper)), 0.7, 0.7, 0.7, true)
        elseif step.source ~= "r" and step.source ~= "q" then
            tt:AddLine(("Learn at a trainer from skill %d%s"):format(step.learn or 1,
                step.learnEstimated and " (estimate)" or ""), 0.7, 0.7, 0.7)
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

    -- the recipe card is as tall as its (wrapping) title and subtitle, at least the icon
    local function headerY()
        return -math.max(48, c.title:GetStringHeight() + c.sub:GetStringHeight() + 14)
    end
    -- lay action buttons out left to right, sized to their text, wrapping to a new row when full
    local bx, rowUsed = 4, false
    local function placeButton(btn)
        local fs = btn:GetFontString()
        btn:SetWidth(math.max(96, (fs and fs:GetStringWidth() or 60) + 28))
        if bx > 4 and bx + btn:GetWidth() > width - 4 then
            y = y - 30
            bx = 4
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", c, "TOPLEFT", bx, y - 8)
        btn:Show()
        bx = bx + btn:GetWidth() + 6
        rowUsed = true
    end

    local cp = SW.CharProf(prof)
    local have = cp.has
    for _, w in ipairs({ c.learn, c.alts, c.learnBox, c.trade, c.warn, c.matsHead, c.info, c.craftBtn, c.buyBtn, c.trainBtn, c.nextHead, c.gapHead, c.gapText, c.total,
                         c.targetLabel, c.targetSlot, c.targetText, c.autoCB }) do
        w:Hide()
        if w.line then w.line:Hide() end
    end
    HidePool(c.mats, 1); HidePool(c.next, 1); HidePool(c.gap, 1)

    if not cur then
        c.icon:Hide()
        local solving = Plan.Solving(prof)
        c.title:SetText(solving and "Working out your route..." or "No data for this profession")
        c.sub:SetText(solving and "|cff8a8a8aA moment - this only happens when the plan changes.|r" or "")
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
        y = headerY()
    else
        local s = cur.step
        local tool = cur.tool
        -- What the card is about: a tool to make/buy first, or the step's recipe.
        local subject = tool or s
        if tool then
            c.icon:Set(tool.item, tool.spell)
            c.title:SetText(("|cffffd100First:|r %s"):format(ItemText(tool.item)))
            c.sub:SetText(("%s one - |cffffffff%s|r needs it."):format(tool.buy and "Buy" or "Make", U.RecipeName(s.spell)))
        else
            c.icon:Set(s.item, s.spell, StepTooltip(s))
            c.title:SetText(U.Colored(cur.color, U.RecipeName(s.spell)) .. (s.qty > 1 and (" |cff8a8a8ax" .. s.qty .. "|r") or ""))
            c.sub:SetText(("Make about |cffffffff%d|r more  |cff8a8a8a(skill %d to %d)|r"):format(cur.left, cur.rank, s.to))
        end
        c.icon:Show()
        y = headerY()

        -- Learned? Where from?
        local learn
        if not have then
            learn = ("|cffffd100Preview|r - you don't have %s. The plan starts from skill 1."):format(SW.ProfName(prof))
        elseif tool and tool.buy then
            learn = "Sold by vendors (tools usually sit with the trade supplies)."
        elseif cur.known then
            learn = "|cff40bf40Learned.|r"
        else
            local svc = SW.Trainer.services[subject.spell]
            if svc and svc.type == "available" then
                learn = "|cffff8040Not learned yet|r - this trainer teaches it."
            elseif subject.source == "c" then
                learn = "|cffff8040Not learned yet|r - " .. CAMP_QUEST_HINT
            elseif subject.source and subject.source:match("^s:") then
                learn = ("|cffff8040Not learned yet|r - a %s specialization recipe."):format(subject.source:sub(3))
            else
                learn = ("|cffff8040Not learned yet|r - learn it at a trainer (needs skill %d%s)."):format(
                    subject.learn or 1, subject.learnEstimated and ", estimated" or "")
            end
        end
        -- Not learned yet: the whole point of the page is "go and learn it", so say it loudly.
        local needsTraining = have and not cur.known and not (tool and tool.buy)
        if needsTraining then
            local box = c.learnBox
            local due = Plan.TrainingDue(prof)
            box.head:SetText(due and ("Train |cffffd100%s %s|r first"):format(due.name, SW.ProfName(prof))
                or "Learn this at a trainer")
            local by = -8 - box.head:GetStringHeight() - 6

            -- this recipe, then the next few the route needs and the character doesn't know
            local list = { { spell = subject.spell, item = subject.item, learn = subject.learn,
                             est = subject.learnEstimated } }
            if route then
                for i = cur.idx + 1, #route.steps do
                    local st = route.steps[i]
                    if not (cp.known and cp.known[st.spell]) and st.spell ~= subject.spell then
                        list[#list + 1] = { spell = st.spell, item = st.item, learn = st.learn, est = st.learnEstimated }
                        if #list >= #box.rows then break end
                    end
                end
            end
            for i, r in ipairs(box.rows) do
                local e = list[i]
                if e then
                    r.icon:Set(e.item, e.spell, nil)
                    local svc = SW.Trainer.services[e.spell]
                    local cost = SW.DB().trainerCost and SW.DB().trainerCost[e.spell]
                    local src = SW.RecipeSource(e.spell)
                    if src and src.kind == "vendor" then cost = cost or src.price end
                    r.text:SetText(("%s  |cff8a8a8a(skill %d%s)|r%s%s"):format(U.RecipeName(e.spell), e.learn or 1,
                        e.est and ", estimated" or "", cost and ("  |cff8a8a8a" .. SW.MoneyShort(cost) .. "|r") or "",
                        (svc and svc.type == "available") and "  |cff40bf40this trainer has it|r" or ""))
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", box, "TOPLEFT", 10, by)
                    r:SetPoint("RIGHT", box, "RIGHT", -8, 0)
                    r:Show()
                    by = by - 22
                else
                    r:Hide()
                end
            end

            -- where: what we have seen ourselves first, Classic knowledge last, nothing invented
            -- A recipe we have seen on sale beats everything: it names the shop and the town.
            local sold = SW.RecipeSource(subject.spell)
            local where, seen = SW.Trainer.WhereIs(prof, due and due.name or "Expert")
            if sold and sold.kind == "vendor" then
                local place = sold.spot and sold.zone and ("%s, %s"):format(sold.zone, sold.spot) or sold.zone or "?"
                box.where:SetText(("|cffffd100Sold by:|r %s - %s%s"):format(sold.who, place,
                    sold.limited and ("  |cffff8040limited stock (%d)|r"):format(sold.limited) or ""))
                where, seen = nil, true
            elseif SW.Trainer.prof == prof then
                box.where:SetText("|cff40bf40You are at the right trainer.|r")
            elseif where and seen then
                box.where:SetText(("|cffffd100Where:|r %s"):format(where))
            else
                box.where:SetText("|cffffd100Where:|r |cff8a8a8ayou haven't met a "
                    .. SW.ProfName(prof) .. " trainer yet - ask a guard in a capital city.|r")
            end
            box.where:ClearAllPoints()
            box.where:SetPoint("TOPLEFT", box, "TOPLEFT", 10, by - 6)
            box.where:SetPoint("RIGHT", box, "RIGHT", -8, 0)
            by = by - 6 - box.where:GetStringHeight()

            if where and not seen then
                box.hint:SetText("|cff8a8a8a" .. where .. "|r")
                box.hint:ClearAllPoints()
                box.hint:SetPoint("TOPLEFT", box, "TOPLEFT", 10, by - 4)
                box.hint:SetPoint("RIGHT", box, "RIGHT", -8, 0)
                box.hint:Show()
                by = by - 4 - box.hint:GetStringHeight()
            else
                box.hint:Hide()
            end
            box:SetHeight(math.max(60, -by + 10))
            place(box, 4, 8)
            box:SetPoint("RIGHT", c, "RIGHT", -4, 0)
            box:Show()
        else
            c.learn:SetText(learn)
            place(c.learn, 4, 6)
        end

        -- Several recipes are guaranteed skill-ups right now: name the runner-up and let them choose
        local orange = cur.orange
        if orange and #orange > 1 then
            local other
            for _, o in ipairs(orange) do
                if o.spell ~= s.spell then other = o break end
            end
            if other then
                local mine = orange[1].spell == s.spell and orange[1] or nil
                local bits = {}
                if other.guaranteed then bits[#bits + 1] = "always works" end
                if other.crafts then bits[#bits + 1] = ("about %d crafts"):format(other.crafts or 0) end
                if (other.canMake or 0) > 0 then
                    bits[#bits + 1] = ("you can make %d"):format(other.canMake)
                elseif (other.missing or 0) > 0 then
                    bits[#bits + 1] = ("%s to buy"):format(SW.MoneyShort(other.missing))
                end
                c.altsText:SetText(("|cff8a8a8aor|r |cffffd100%s|r |cff8a8a8a- %s%s|r%s")
                    :format(U.RecipeName(other.spell), table.concat(bits, ", "),
                        #orange > 2 and (", +%d more"):format(#orange - 2) or "",
                        (cur.swapped or (mine and mine.chosen)) and "  |cff40bf40(your choice)|r" or ""))
                c.alts:Show()
                place(c.alts, 4, 2)
                c.alts:SetHeight(math.max(14, c.altsText:GetStringHeight()))
            end
        elseif s.alts and #s.alts > 0 then
            local a = s.alts[1]
            local extra = (a.cost or 0) - (s.costEach or 0)
            local tail = extra > 0 and (", %s more each"):format(SW.MoneyShort(extra))
                or (extra < 0 and (", %s less each"):format(SW.MoneyShort(-extra)) or ", same cost")
            local more = #s.alts > 1 and (" |cff8a8a8a(+%d more)|r"):format(#s.alts - 1) or ""
            c.altsText:SetText(("|cff8a8a8aor|r |cffffd100%s|r |cff8a8a8a- same skill-ups%s|r%s%s")
                :format(U.RecipeName(a.spell), tail, more,
                    s.chosenByPlayer and "  |cff40bf40(your choice)|r" or ""))
            c.alts:Show()
            place(c.alts, 4, 2)
            c.alts:SetHeight(math.max(14, c.altsText:GetStringHeight()))
        else
            c.alts:Hide()
        end

        -- The route stops at the rank the character can reach, so say what lifts it - and, for the ranks
        -- that come from a book or a quest rather than a trainer, say that instead of "at a trainer".
        local due = have and Plan.TrainingDue(prof)
        local capped = have and route and route.to and (cp.max or 0) > 0 and route.to >= cp.max
            and cp.max < SW.MAX_RANK
        if due or capped then
            local tier = due
            if not tier then
                for _, t in ipairs(SW.TIERS) do
                    if t.cap > (cp.max or 0) then tier = t break end
                end
            end
            local name = tier and tier.name or "the next rank"
            local hint = SW.TrainerHint and tier and SW.TrainerHint(prof, tier.name)
            local need = tier and tier.need and (cp.rank or 0) < tier.need
                and (" |cff8a8a8a(needs skill %d)|r"):format(tier.need) or ""
            c.warn:SetText(("|cffff6060The route stops at %d.|r Learn |cffffd100%s %s|r to go further.%s%s"):format(
                cp.max, name, SW.ProfName(prof), need, hint and ("\n|cff8a8a8a" .. hint .. "|r") or ""))
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
            if m.short > 0 then SW.Prices.AddToBuy(vendorBuy, m.id, m.short, m.unit) end
            if m.bank > 0 then bankLines[#bankLines + 1] = ("%d %s"):format(m.bank, ItemText(m.id)) end
            if Est(m.priceSource) then estimated = true end
        end
        local rows = math.ceil(#cur.mats / perRow)
        y = rowY - rows * 56

        if tool and tool.buy then SW.Prices.AddToBuy(vendorBuy, tool.item, 1, tool.cost or 0) end

        local info = {}
        if tool then
            info[#info + 1] = ("It costs about %s. You only need one."):format(Cost(tool.cost or 0, estimated))
        else
            info[#info + 1] = ("This step costs about %s%s."):format(Cost(s.costEach * cur.left, estimated),
                estimated and " |cff8a8a8a(some prices are estimates)|r" or "")
            -- Only say "from a vendor" when we actually know a vendor price for every material: a guess
            -- from an item's sell price is not a vendor, and saying so sends people shopping for ore.
            if s.haveMats then
                info[#info + 1] = "|cff40bf40You already have the materials for this.|r"
            elseif s.vendorOnly and AllFromVendor(cur.mats) then
                info[#info + 1] = "|cff40bf40Every material comes from a vendor.|r"
            end
        end
        if #bankLines > 0 then info[#info + 1] = "|cff7da5ffIn your bank:|r " .. table.concat(bankLines, ", ") end
        c.info:SetText(table.concat(info, "\n"))
        place(c.info, 4, 4)

        -- Enchants: which item it goes on
        for _, w in ipairs({ c.targetLabel, c.targetSlot, c.targetText, c.autoCB }) do w:Hide() end
        local isEnchant = not tool and SW.Enchant.IsEnchant(s)
        if isEnchant and have and SW.Prof.IsOpen(prof) then
            local target, targets = SW.Enchant.Target(s.spell)
            if targets then
                c.targetLabel:ClearAllPoints()
                c.targetLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y - 12)
                c.targetLabel:Show()
                local slot = c.targetSlot
                slot.spell = s.spell
                slot.link = target and target.link
                slot.icon:SetShown(target ~= nil)
                if target then slot.icon:SetTexture(U.ItemIcon(target.id)) end
                slot.plus:SetShown(target == nil and #targets > 0)
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", c, "TOPLEFT", 6, y - 30)
                slot:Show()
                c.targetText:ClearAllPoints()
                c.targetText:SetPoint("LEFT", slot, "RIGHT", 8, 0)
                c.targetText:SetWidth(width - 70)
                if target then
                    c.targetText:SetText((target.link or ItemText(target.id)) .. (target.equipped and " |cffff6060(worn)|r" or ""))
                elseif #targets == 0 then
                    c.targetText:SetText("|cff8a8a8aNothing in your bags this can go on.|r")
                else
                    c.targetText:SetText("Select Item to Enchant")
                end
                c.targetText:Show()
                y = y - 72
                c.autoCB:SetChecked(SW.Settings().autoReplaceEnchant and true or false)
                c.autoCB:ClearAllPoints()
                c.autoCB:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y + 2)
                c.autoCB:Show()
                y = y - 22
            end
        end

        -- Actions
        if have and cur.known and SW.Prof.IsOpen(prof) and not (tool and tool.buy) then
            SetupCraftButton(c.craftBtn, cur, prof)
            placeButton(c.craftBtn)
        end
        if #vendorBuy > 0 then
            c.buyBtn.list = vendorBuy
            placeButton(c.buyBtn)
        end
        local svcs = SW.Trainer.RouteServices(prof, route)
        if #svcs > 0 then
            c.trainBtn.list = svcs
            c.trainBtn:SetText(("Train %d recipe%s"):format(#svcs, #svcs == 1 and "" or "s"))
            placeButton(c.trainBtn)
        end
        if rowUsed then y = y - 36 end

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
            r.right:SetText(("x%d"):format(st.crafts or 0))
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
        c.gapText:SetText(("Trainer recipes stop giving skill at |cffffd100%d|r. Most of Forever's new recipes come "
            .. "from recipe items whose drops and vendors aren't known yet, so the plan can only use them once you've "
            .. "learned them. Any of these would keep you going:"):format(route.gapAt))
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

    -- What the other mode would cost, so the choice is a decision and not a coin flip.
    local trade = Plan.TradeOff(prof)
    if trade then
        c.trade:SetText(("|cff8a8a8aYou are on|r |cffffd100%s|r|cff8a8a8a.|r %s"):format(
            SW.Settings().mode == "fast" and "Fastest" or "Cheapest", trade))
        place(c.trade, 4, 4)
    elseif Plan.Solving(prof, SW.Settings().mode == "fast" and "cheap" or "fast") then
        c.trade:SetText("|cff8a8a8aWorking out what the other route would cost...|r")
        place(c.trade, 4, 4)
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
    r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    return r
end

local function RefreshRoute(f)
    local prof = win.prof
    local route = Plan.Route(prof)
    local c = f.c
    c:SetWidth(f.sf:GetWidth())
    HidePool(f.rows, 1)
    if not route then
        f.note:SetText(Plan.Solving(prof) and "|cff8a8a8aWorking out your route...|r" or "")
        return
    end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local y, n = -2, 0
    local owned = Plan.OwnedTools()
    for _, s in ipairs(route.steps) do
        if s.to > rank then
            -- tools this step needs that you don't have yet
            for _, t in ipairs(s.prereqs or {}) do
                if not SW.Solver.HasTool(t.category, owned) then
                    n = n + 1
                    local r = RouteRow(f, n)
                    r.bg:Hide()
                    r.icon:SetTexture(U.ItemIcon(t.item))
                    r.range:SetText("|cffffd100tool|r")
                    r.text:SetText(("%s %s"):format(t.buy and "Buy" or "Make", ItemText(t.item)))
                    r.right:SetText(("x1  %s"):format(Cost(t.cost or 0, false)))
                    r.tipItem, r.tipSpell, r.tipExtra = t.item, t.spell, nil
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
                    r:SetPoint("RIGHT", c, "RIGHT", -2, 0)
                    r:Show()
                    y = y - ROW - 1
                end
            end
            n = n + 1
            local r = RouteRow(f, n)
            local current = rank >= s.from and rank < s.to
            r.bg:SetShown(current)
            r.icon:SetTexture(U.RecipeIcon(s.item, s.spell))
            r.range:SetText(("%d-%d"):format(s.from, s.to))
            local est = false
            for _, m in ipairs(s.mats) do if Est(m.priceSource) then est = true end end
            local known = SW.Prof.Knows(prof, s.spell)
            r.text:SetText((known and "" or "|cffff8040*|r ") .. U.RecipeName(s.spell) .. " " .. SourceTag(s.source)
                .. MatsTag(s))
            local crafts = current and Plan.CraftsLeft(s, rank) or s.crafts
            r.right:SetText(("x%d  %s"):format(crafts, Cost(crafts * (s.costEach or 0), est)))
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
    f.buy:SetScript("OnClick", function(self) SW.Prices.ConfirmBuy(self.list) end)
    f.buy:SetScript("OnEnter", function(self) SW.Prices.BuyTooltip(self, self.list) end)
    f.buy:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hint = U.Text(f, "GameFontHighlightSmall", "LEFT", true)
    f.hint:SetPoint("TOPLEFT", 2, -6)
    f.hint:SetPoint("RIGHT", -4, 0)
    f.total = U.Text(sf.child, "GameFontHighlightSmall", "LEFT", true)
    f.trade = U.Text(sf.child, "GameFontHighlightSmall", "LEFT", true)   -- what the other mode would cost
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
            if e.short > 0 then SW.Prices.AddToBuy(buyList, e.id, e.short, e.unit) end
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
    local trade = Plan.TradeOff(prof)
    if trade then
        f.trade:SetText(("|cff8a8a8aYou are on|r |cffffd100%s|r|cff8a8a8a.|r %s"):format(
            SW.Settings().mode == "fast" and "Fastest" or "Cheapest", trade))
        f.trade:ClearAllPoints()
        f.trade:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y - 8)
        f.trade:SetWidth(c:GetWidth() - 10)
        f.trade:Show()
        y = y - f.trade:GetStringHeight() - 6
    else
        f.trade:Hide()
    end
    f.total:SetText(("Total: %s%s"):format(Cost(total, est),
        est and ("\n|cff8a8a8a" .. EstNote() .. "|r") or ""))
    f.total:ClearAllPoints()
    f.total:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y - 10)
    f.total:SetWidth(c:GetWidth() - 10)
    c:SetHeight(-y + 20 + f.total:GetStringHeight())
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
function SW.DefaultProf()
    local open = SW.Prof.OpenLine()
    if open and SW.PROFESSIONS[open] then return open end
    local last = SW.CharDB().lastProf
    if last and SW.PROFESSIONS[last] then return last end
    return SW.Prof.Mine()[1] or SW.Prof.All()[1]
end

-- ---------------------------------------------------------------------------
-- Minimal: just the step, its materials and the Craft button
-- ---------------------------------------------------------------------------
local MINI_W = 260
local MINI_PAD = 4    -- inside the mini frame, which is already inset from the window edge

local function BuildMini()
    local m = CreateFrame("Frame", nil, win)
    m:SetPoint("TOPLEFT", 14, -28)
    m:SetPoint("BOTTOMRIGHT", -14, 12)
    m.icon = U.IconButton(m, 32)
    m.icon:SetPoint("TOPLEFT", MINI_PAD, -2)
    m.title = U.Text(m, "GameFontNormal", "LEFT", true)
    m.title:SetPoint("TOPLEFT", m.icon, "TOPRIGHT", 8, 0)
    m.title:SetPoint("RIGHT", m, "RIGHT", -MINI_PAD, 0)
    m.sub = U.Text(m, "GameFontHighlightSmall", "LEFT", true)
    m.sub:SetPoint("TOPLEFT", m.title, "BOTTOMLEFT", 0, -3)
    m.sub:SetPoint("RIGHT", m, "RIGHT", -MINI_PAD, 0)
    m.mats = {}
    m.slot = U.IconButton(m, 30)
    m.slot.bg = m.slot:CreateTexture(nil, "BACKGROUND")
    m.slot.bg:SetAllPoints()
    m.slot.bg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    m.slot.plus = m.slot:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge")
    m.slot.plus:SetPoint("BOTTOMRIGHT", -1, 0)
    m.slot.plus:SetText("+")
    m.slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    m.slot:SetScript("OnClick", TargetSlotClick)
    m.slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:AddLine("Select Item to Enchant", 1, 0.82, 0.3) end
        GameTooltip:AddLine("Click: choose.  Right-click: no target.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    m.craft = U.Button(m, "Craft", MINI_W - 28 - 2 * MINI_PAD, 24)
    m.craft:SetScript("OnClick", CraftClick)
    m.note = U.Text(m, "GameFontHighlightSmall", "LEFT", true)
    win.mini = m
    m:Hide()
end

local function RefreshMini()
    local m = win.mini
    local prof = win.prof
    for _, c in ipairs(m.mats) do c:Hide() end
    m.slot:Hide(); m.craft:Hide(); m.note:Hide()
    local cur = Plan.Current(prof)
    local h
    if not cur or cur.done then
        m.icon:Set(nil, nil)
        m.icon.tex:SetTexture(SW.ProfIcon(prof))
        m.title:SetText(SW.ProfName(prof))
        m.sub:SetText(cur and cur.route and cur.route.gapAt and ("No trainer recipe past %d"):format(cur.route.gapAt)
            or (Plan.Solving(prof) and "Working out your route..." or "Nothing to do"))
        h = 70
    else
        local s, tool = cur.step, cur.tool
        if tool then
            m.icon:Set(tool.item, tool.spell)
            m.title:SetText("|cffffd100First:|r " .. ItemText(tool.item))
            m.sub:SetText((tool.buy and "Buy" or "Make") .. " one")
        else
            m.icon:Set(s.item, s.spell, StepTooltip(s))
            m.title:SetText(U.Colored(cur.color, U.RecipeName(s.spell)))
            m.sub:SetText(("%d more  |cff8a8a8a%d > %d|r%s"):format(cur.left, cur.rank, s.to,
                cur.known and "" or "  |cffff8040not learned|r"))
        end
        -- materials under the (wrapping) title, the enchant target at the right; rows of icons as needed
        local top = -math.max(38, m.title:GetStringHeight() + m.sub:GetStringHeight() + 12)
        local isEnchantHere = not tool and SW.Enchant.IsEnchant(s) and cur.known and SW.Prof.IsOpen(prof)
        local room = MINI_W - 28 - 2 * MINI_PAD - (isEnchantHere and 40 or 0)
        local perRow = math.max(1, math.floor(room / 44))
        for i, mat in ipairs(cur.mats) do
            local cell = m.mats[i]
            if not cell then
                cell = U.IconButton(m, 28)
                cell.count = U.Text(cell, "GameFontHighlightSmall", "CENTER")
                cell.count:SetPoint("TOP", cell, "BOTTOM", 0, -1)
                m.mats[i] = cell
            end
            cell:Set(mat.id, nil)
            cell.count:SetText(("%s%d|r/%d"):format(mat.have >= mat.need and "|cff40bf40" or "|cffff6060", mat.have, mat.need))
            cell:ClearAllPoints()
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            cell:SetPoint("TOPLEFT", m, "TOPLEFT", MINI_PAD + col * 44, top - row * 46)
            cell:Show()
        end
        local matRows = math.max(1, math.ceil(#cur.mats / perRow))
        local isEnchant = not tool and SW.Enchant.IsEnchant(s)
        if isEnchant and cur.known and SW.Prof.IsOpen(prof) then
            local target, targets = SW.Enchant.Target(s.spell)
            if targets and #targets > 0 then
                m.slot.spell = s.spell
                m.slot.link = target and target.link
                m.slot.tex:SetTexture(target and U.ItemIcon(target.id) or nil)
                m.slot.tex:SetShown(target ~= nil)
                m.slot.plus:SetShown(target == nil)
                m.slot:ClearAllPoints()
                m.slot:SetPoint("TOPRIGHT", m, "TOPRIGHT", -MINI_PAD, top)
                m.slot:Show()
            end
        end
        h = -top + matRows * 46
        if cur.known and SW.Prof.IsOpen(prof) and not (tool and tool.buy) then
            SetupCraftButton(m.craft, cur, prof)
            m.craft:ClearAllPoints()
            m.craft:SetPoint("TOPLEFT", m, "TOPLEFT", MINI_PAD, -h - 4)
            m.craft:Show()
            h = h + 32
        elseif not SW.Prof.IsOpen(prof) and cur.known then
            m.note:SetText("|cff8a8a8aOpen the profession window to craft.|r")
            m.note:ClearAllPoints()
            m.note:SetPoint("TOPLEFT", m, "TOPLEFT", MINI_PAD, -h - 4)
            m.note:SetWidth(MINI_W - 28 - 2 * MINI_PAD)
            m.note:Show()
            h = h + 20
        end
    end
    win:SetSize(MINI_W, h + 44)
end

local function ApplyMode()
    local minimal = SW.Settings().minimal
    if minimal and not win.mini then BuildMini() end
    for _, w in ipairs(win.fullOnly) do w:SetShown(not minimal) end
    if win.mini then win.mini:SetShown(minimal and true or false) end
    win.sizeBtn:SetText(minimal and "+" or "-")
    if not minimal then win:SetSize(W, H) end
end

function SW.SetMinimal(on)
    SW.Settings().minimal = on and true or false
    if win then
        ApplyMode()
        SW.RefreshWindow()
    end
end

-- ---------------------------------------------------------------------------
-- No crafting profession yet (gathering-only counts as none): "choose a profession" instead of an empty
-- planner (UI/Dashboard.lua).
-- Not when the guide opened with a profession window, for a particular profession or tab, or after a
-- card was clicked to preview a route; closing the guide brings it back.
-- ---------------------------------------------------------------------------
local function FirstPrimary()
    for _, id in ipairs(SW.Prof.Mine()) do
        if id ~= 185 and id ~= 129 then return id end
    end
    return SW.DefaultProf()
end

-- Shows or hides the dashboard; true while it is showing.
local function UpdateDashboard()
    if not (SW.Dashboard and SW.Prof.NoCrafting() and not win.attached and not win.dashSkip) then
        if win.dash and win.dash:IsShown() then
            win.dash:Hide()
            win.sizeBtn:Show()
            -- just learned one: plan that, not the last preview
            if not SW.Prof.NoCrafting() then
                win.prof = FirstPrimary()
                SW.CharDB().lastProf = win.prof
            end
        end
        return false
    end
    if not win.dash then
        win.dash = CreateFrame("Frame", nil, win)
        win.dash:SetPoint("TOPLEFT", 16, -30)
        win.dash:SetPoint("BOTTOMRIGHT", -12, 12)
        SW.Dashboard.Build(win.dash, function(id)
            win.dashSkip = true
            win.prof = id
            SW.CharDB().lastProf = id
            SW.RefreshWindow()
        end)
    end
    for _, w in ipairs(win.fullOnly) do w:Hide() end
    if win.mini then win.mini:Hide() end
    win.sizeBtn:Hide()
    win:SetSize(W, H)
    win.dash:Show()
    SW.Dashboard.Refresh(win.dash)
    return true
end

-- The strip that says costs are estimates until there are auction prices; the body moves down under it.
local function UpdatePriceNote()
    local note, status = win.priceNote, SW.Prices.Status()
    local text
    if SW.dataLost then
        -- worth saying before anything about prices: it explains every empty number on the page
        text = "|cffffd100Your saved Skillwright data didn't load|r - prices, trainer skills and the recipe "
            .. "you were following all start empty this session. That is a WoW: Forever bug, not something "
            .. "you did. Skillwright learns it again as you play."
    end
    if not text then
    if win.view ~= "settings" and (status == "none" or status == "stale") then
        local atAH = SW.Prices.CanScan()
        if status == "stale" then
            text = ("|cffffd100Auction prices are out of date|r (scanned %s), so costs are estimates again. %s")
                :format(SW.Prices.Ago(SW.DB().ahScanned), atAH and "Press |cffffd100Scan prices|r below."
                    or "Scan again at the auction house.")
        else
            text = "|cffffd100No auction prices yet|r - costs are estimates (marked est.). "
                .. (atAH and "Press |cffffd100Scan prices|r below - it takes a few seconds."
                    or "Open the auction house and press |cffffd100Scan prices|r (or install Auctionator or TSM).")
        end
    end
    end
    -- Nothing to do when it already says this: every refresh would otherwise re-measure and re-anchor.
    if text == note.shownText then return end
    note.shownText = text
    win.body:ClearAllPoints()
    win.body:SetPoint("BOTTOMRIGHT", -12, 40)
    if text then
        note.text:SetText(text)
        note:SetHeight(math.ceil(note.text:GetStringHeight()) + 10)
        note:Show()
        -- wrapped height is only right once the strip has its width
        C_Timer.After(0, function() note:SetHeight(math.ceil(note.text:GetStringHeight()) + 10) end)
        win.body:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -6)
    else
        note:Hide()
        win.body:SetPoint("TOPLEFT", 16, -98)
    end
end

local function Refresh()
    if not win or not win:IsShown() then return end
    if UpdateDashboard() then return end
    ApplyMode()
    if SW.Settings().minimal then
        RefreshMini()
        return
    end
    local prof = win.prof
    local cp = SW.CharProf(prof)
    win.profIcon:SetTexture(SW.ProfIcon(prof))
    if cp.has then
        win.profText:SetText(("%s |cffffffff%d|r|cff8a8a8a/%d|r"):format(SW.ProfName(prof), cp.rank or 0, cp.max or 0))
    else
        win.profText:SetText(("%s  |cff8a8a8a(preview)|r"):format(SW.ProfName(prof)))
    end
    win.mode:Select(SW.Settings().mode)
    UpdatePriceNote()
    local v = views[win.view]
    if v and v.frame then v.refresh(v.frame) end
    -- Footer: where prices come from, and the scan button at the auction house.
    local src = SW.Prices.SourceText()
    win.status:SetText(src and ("|cff8a8a8aPrices:|r " .. src) or "|cff8a8a8aPrices: estimated (no auction data)|r")
    win.scan:SetShown(SW.Prices.CanScan() and true or false)
    win.status:SetPoint("RIGHT", win.scan:IsShown() and win.scan or win, win.scan:IsShown() and "LEFT" or "RIGHT", win.scan:IsShown() and -8 or -18, 0)
    win.scan:SetEnabled(not SW.Prices.Scanning())
    win.scan:SetText(SW.Prices.Scanning() and "Scanning..." or "Scan prices")
end

function SW.RefreshWindow()
    SW.Debounce("uiRefresh", 0.1, Refresh)
end

local function SelectView(id)
    -- the lib hosts the settings: the tab is gone, so asking for it opens the YippYapp window
    if id == "settings" and HOSTED_SETTINGS then
        SW.LIB.OpenAddonSettings("Skillwright")
        id = win.view or "now"
    end
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

-- How far past its right edge the profession window reaches: Forever hangs its tabs off the right side.
local function HostOverhang(host)
    local edge = host:GetRight()
    if not edge then return 0 end
    local far = edge
    local function scan(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsShown() then
                local r = child:GetRight()
                -- only small things hanging off the edge count, not a detached panel
                if r and r > far and r - edge < 80 and (child:GetWidth() or 0) < 200 then far = r end
                if depth < 2 then scan(child, depth + 1) end
            end
        end
    end
    scan(host, 0)
    return math.max(0, far - edge)
end

-- Anchor: beside the open profession window when attached, else where the player left it.
function SW.Anchor()
    if not win then return end
    win:ClearAllPoints()
    local host = ProfessionsFrame
    if win.attached and SW.Settings().attach and host and host:IsShown() then
        win:SetPoint("TOPLEFT", host, "TOPRIGHT", HostOverhang(host) + 4, 0)
        -- the tabs are laid out a moment after the window shows; measure again then
        if not win.reanchoring then
            win.reanchoring = true
            C_Timer.After(0.1, function()
                win.reanchoring = false
                if win.attached and host:IsShown() then
                    win:ClearAllPoints()
                    win:SetPoint("TOPLEFT", host, "TOPRIGHT", HostOverhang(host) + 4, 0)
                end
            end)
        end
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
            if SW.Prof.NoCrafting() then
                root:CreateButton("|cffffd100Choosing a profession|r", function()
                    win.dashSkip = false
                    Refresh()
                end)
            end
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
    win:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
    -- LibForever's shared window handling: strata, front-to-back order with our other windows, dragging,
    -- the saved position (SkillwrightDB.pos) and Escape. Dragging also unhooks the guide from the
    -- profession window.
    SW.LIB.RegisterWindow(win, SW.DB(), "pos")
    win:HookScript("OnDragStop", function(self) self.attached = false end)

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
    win.profText:SetWidth(168)
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
    }, 136, function(v)
        -- stay on the recipe being crafted if the other route uses it here as well
        local cur = Plan.Current(win.prof)
        local step = cur and cur.step
        Plan.SetActive(win.prof, step and step.spell or nil, step and step.to or nil)
        SW.SetMode(v)
    end)
    win.mode:SetPoint("TOPRIGHT", -18, -31)

    HOSTED_SETTINGS = SW.LIB.OpenAddonSettings ~= nil
    local tabItems = VIEW_ORDER
    if HOSTED_SETTINGS then
        tabItems = {}
        for _, item in ipairs(VIEW_ORDER) do
            if item.value ~= "settings" then tabItems[#tabItems + 1] = item end
        end
    end
    win.tabs = U.Tabs(win, tabItems, SelectView)
    win.tabs:SetPoint("TOPLEFT", 16, -58)
    local divider = win:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 14, -91)
    divider:SetPoint("TOPRIGHT", -16, -91)

    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", 16, -98)
    win.body:SetPoint("BOTTOMRIGHT", -12, 40)

    -- "No auction prices yet": a strip above the tabs' content while costs are estimates
    local note = CreateFrame("Frame", nil, win)
    note:SetPoint("TOPLEFT", 16, -96)
    note:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    note.bg = note:CreateTexture(nil, "BACKGROUND")
    note.bg:SetAllPoints()
    note.bg:SetColorTexture(1, 0.82, 0, 0.08)
    note.edge = note:CreateTexture(nil, "BORDER")
    note.edge:SetPoint("TOPLEFT")
    note.edge:SetPoint("BOTTOMLEFT")
    note.edge:SetWidth(2)
    note.edge:SetColorTexture(1, 0.82, 0, 0.8)
    note.text = U.Text(note, "GameFontHighlightSmall", "LEFT", true)
    note.text:SetPoint("TOPLEFT", 8, -5)
    note.text:SetPoint("RIGHT", note, "RIGHT", -6, 0)
    note:Hide()
    win.priceNote = note

    win.scan = U.Button(win, "Scan prices", 100, 22)
    win.scan:SetPoint("BOTTOMRIGHT", -14, 12)
    win.scan:SetScript("OnClick", function() SW.Prices.StartScan() end)
    win.status = U.Text(win, "GameFontHighlightSmall")
    win.status:SetPoint("BOTTOMLEFT", 18, 17)
    win.status:SetPoint("RIGHT", win, "RIGHT", -18, 0)
    local statusHit = CreateFrame("Frame", nil, win)
    statusHit:SetPoint("TOPLEFT", win.status, "TOPLEFT", 0, 4)
    statusHit:SetPoint("BOTTOMRIGHT", win.status, "BOTTOMRIGHT", 0, -4)
    statusHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Prices", 1, 0.82, 0.3)
        local src = SW.Prices.SourceText()
        GameTooltip:AddLine(src and ("From: " .. src) or "No auction prices yet, so materials that aren't sold by vendors are estimated.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Open the auction house and press Scan prices, or install Auctionator or TSM.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    statusHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.statusHit = statusHit

    -- Settings: the YippYapp window when the lib hosts them, else our own tab
    win.gear = CreateFrame("Button", nil, win)
    win.gear:SetSize(18, 18)
    local gearTex = win.gear:CreateTexture(nil, "ARTWORK")
    gearTex:SetAllPoints()
    gearTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    local gearHL = win.gear:CreateTexture(nil, "HIGHLIGHT")
    gearHL:SetAllPoints()
    gearHL:SetColorTexture(1, 1, 1, 0.2)
    win.gear:SetScript("OnClick", function() SW.OpenSettings() end)
    win.gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Settings", 1, 0.82, 0.3)
        GameTooltip:AddLine("Route, guide window and enchanting options.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    win.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.gear:SetShown(HOSTED_SETTINGS)

    -- Full / minimal switch, left of the close button
    win.sizeBtn = U.Button(win, "-", 22, 18)
    win.sizeBtn:SetPoint("RIGHT", close, "LEFT", -2, 0)
    win.gear:SetPoint("RIGHT", win.sizeBtn, "LEFT", -4, 0)
    win.sizeBtn:SetScript("OnClick", function() SW.SetMinimal(not SW.Settings().minimal) end)
    win.sizeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(SW.Settings().minimal and "Full window" or "Minimal window", 1, 0.82, 0.3)
        GameTooltip:AddLine(SW.Settings().minimal and "Back to the full guide with the route, shopping list and settings."
            or "Just the recipe to make, its materials and the Craft button.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    win.sizeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Everything the minimal window hides
    win.fullOnly = { pb, win.mode, divider, win.body, win.scan, win.status, win.statusHit, win.priceNote }
    if HOSTED_SETTINGS then win.fullOnly[#win.fullOnly + 1] = win.gear end
    for _, b in ipairs(win.tabs.buttons) do win.fullOnly[#win.fullOnly + 1] = b end

    views.now = { build = BuildNow, refresh = RefreshNow }
    views.route = { build = BuildRoute, refresh = RefreshRoute }
    views.shop = { build = BuildShop, refresh = RefreshShop }
    views.settings = { build = SW.SettingsPage.Build, refresh = function(f) SW.SettingsPage.Refresh(f, win.prof) end }

    win:HookScript("OnShow", function()
        SW.Prof.ScanRanks()
        SW.RefreshWindow()
    end)
    win:HookScript("OnHide", function() win.dashSkip = false end)
    win:Hide()
end

-- Show the guide for a profession (nil = the best guess) on a tab (nil = keep the current one).
function SW.ShowWindow(prof, view, attached)
    Build()
    win.prof = prof or win.prof or SW.DefaultProf()
    if not win.prof then return end
    SW.CharDB().lastProf = win.prof
    -- asking for a particular tab (settings from /skw config) needs the full window
    if view and view ~= "now" and SW.Settings().minimal then SW.Settings().minimal = false end
    win.attached = attached and true or false
    -- asked for a profession or a tab: show it, not "choose a profession"
    if prof or attached or (view and view ~= "now") then win.dashSkip = true end
    SW.Anchor()
    win:Show()
    -- the shared window handling places a window on its first show; attached, we sit by the profession window
    if win.attached then SW.Anchor() end
    SelectView(view or win.view or "now")
end

function SW.ToggleWindow()
    if win and win:IsShown() then win:Hide() else SW.ShowWindow() end
end

function SW.WindowShown() return win and win:IsShown() end

-- Opening a profession window opens (and attaches) its guide; closing it closes a guide it opened.
SW.Listen("PROFESSION_OPEN", function(id)
    -- A profession we have no guide for (Mining's smelting, Herbalism, Fishing): the guide has nothing
    -- to say about it, so it must not sit beside that window showing a different profession's route.
    if not SW.PROFESSIONS[id] then
        if win and win:IsShown() then
            if win.autoShown then
                win:Hide()                 -- it came with a profession window; it goes with this one
                win.autoShown = false
            elseif win.attached then
                win.attached = false       -- the player opened it: leave it, but not glued to that window
                SW.Anchor()
            end
        end
        return
    end
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

-- DATA_LOST arrives a second or two after login: a guide opened before then has to be told, or it keeps
-- looking like a fresh install until something else redraws it.
for _, ev in ipairs({ "PLAN_CHANGED", "RANKS_CHANGED", "MERCHANT_CHANGED", "TRAINER_CHANGED", "SCAN_STATE", "RECIPES_CHANGED",
                     "PROFESSION_UPDATED", "DATA_LOST" }) do
    SW.Listen(ev, SW.RefreshWindow)
end
SW.On("BAG_UPDATE_DELAYED", SW.RefreshWindow)
-- names arrive one item at a time: coalesce the redraws, but don't let a stream of them postpone it
SW.On("GET_ITEM_INFO_RECEIVED", function() SW.Coalesce("itemInfo", 0.3, Refresh) end)
SW.On("AUCTION_HOUSE_SHOW", SW.RefreshWindow)
SW.On("AUCTION_HOUSE_CLOSED", SW.RefreshWindow)
SW.On("TRADE_SKILL_LIST_UPDATE", SW.RefreshWindow)
