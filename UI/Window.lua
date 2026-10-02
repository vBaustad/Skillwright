-- Skillwright - the guide window: Now / Route / Shopping / Settings.
-- Opens beside the profession window for that profession, or on its own from /skw and the minimap button.
local ADDON, SW = ...
local U = SW.UI
local Plan = SW.Plan

local W, H = 400, 560
local ROW = 26
-- A list is a column of facts and sits tighter than the route's own steps, which are things to go
-- and do. These are row HEIGHTS, and the step between rows is the same number - the two drifted
-- apart once and every row overlapped the next by eight pixels.
local TIGHT = 18
local HEADER = 22
local win
local views = {}          -- [id] = { frame, build, refresh }
-- The settings live in the YippYapp window (LibForever); the gear in the corner opens them. Without the
-- lib they stay a tab of our own, so nothing is stranded.
local HOSTED_SETTINGS = false
local VIEW_ORDER = { { value = "now", label = "Now" }, { value = "route", label = "Route" },
                     { value = "shop", label = "Shopping" }, { value = "settings", label = "Settings" } }

local AltMenu   -- "or make this instead" (defined below, used by the Now view's widgets)

-- A price we do not have. Skillwright never invents one: vendor prices and an auction scan are facts,
-- and everything else is simply unknown until the player scans.
local function NoPrice(src) return src == "unknown" or src == nil end

-- "12g 30s", or plain words when the price is not something we know.
local function Cost(copper, partial)
    if copper == nil then return "|cff8a8a8ano price|r" end
    return (partial and "|cff8a8a8aat least|r " or "") .. SW.MoneyShort(copper)
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

-- What "we think skill N" is worth, measured against the 45 trainer requirements this addon has
-- recorded from the game itself, plus four First Aid ones cross-checked against wowhead: the only
-- property we hold to is that it is never EARLY. See DECISIONS.md for what that cost and why.
local GUESS_NOTE = "We only know the trainer's real number once you have stood in front of one. Until "
    .. "then we go by when the recipe turns yellow, which in every requirement we have been able to "
    .. "check is at or after the real one - so we would rather say later than send you to a trainer "
    .. "who will not teach you. Open any trainer for this profession once and the plan turns exact."

-- Why part of a bill has no price: before any auction prices it's a hint to scan; after a scan, the item
-- simply wasn't listed (or Auctionator/TSM has no price for it).
local function NoPriceNote()
    local status = SW.Prices.Status()
    if status == "none" or status == "stale" then
        return "Only vendor prices are known. Open the auction house and press Scan prices for the rest."
    end
    return "Materials nobody was selling have no price - they are counted as unknown, not guessed."
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
        return false                                    -- nothing to press: the caller says so in words
    elseif isEnchant and SW.Enchant.OneAtATime(s.spell) then
        btn:SetText(("Enchant  (%d left)"):format(cur.left))   -- onto an item the game takes one click per cast
    else
        btn:SetText(("Craft %d"):format(n))
    end
    btn:SetEnabled(true)
    return true
end

local function BuildNow(f)
    local sf = U.Scroll(f)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -22, 0)
    local c = sf.child
    f.sf, f.c = sf, c
    -- The one handle anything outside this file has on the Now card. The offline harness had been
    -- reaching for SkillwrightFrame.card, which never existed, so its card assertions were passing
    -- without ever looking at a card.
    if win then win.card = c end

    c.icon = U.IconButton(c, 40)
    c.icon:SetPoint("TOPLEFT", 4, -4)
    c.title = U.Text(c, "GameFontNormalLarge", "LEFT", true)
    c.title:SetPoint("RIGHT", c, "RIGHT", -4, 0)   -- left edge depends on whether there is an icon
    c.sub = U.Text(c, "GameFontHighlight", "LEFT", true)
    c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -4, 0)

    c.learn = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.why = U.Text(c, "GameFontHighlightSmall", "LEFT", true)   -- why this card differs from the route
    -- Recipes that are the same for the plan (Rough Sharpening Stone / Rough Weightstone): the player picks
    c.alts = CreateFrame("Button", nil, c)
    c.alts:SetHeight(22)
    c.alts.bg = c.alts:CreateTexture(nil, "BACKGROUND")
    c.alts.bg:SetAllPoints()
    c.alts.bg:SetColorTexture(1, 0.82, 0.3, 0.07)
    c.alts.edge = c.alts:CreateTexture(nil, "BORDER")
    c.alts.edge:SetPoint("TOPLEFT")
    c.alts.edge:SetPoint("BOTTOMLEFT")
    c.alts.edge:SetWidth(2)
    c.alts.edge:SetColorTexture(1, 0.82, 0.3, 0.55)
    c.alts.hl = c.alts:CreateTexture(nil, "HIGHLIGHT")
    c.alts.hl:SetAllPoints()
    c.alts.hl:SetColorTexture(1, 1, 1, 0.10)
    c.altsText = U.Text(c.alts, "GameFontHighlightSmall", "LEFT", true)
    c.altsText:SetPoint("TOPLEFT", 8, -4)   -- width set where it is measured, never by anchors
    c.altsChev = U.Text(c.alts, "GameFontNormalSmall", "RIGHT", false)
    c.altsChev:SetPoint("TOPRIGHT", -7, -4)
    c.altsChev:SetText("|cffffd100v|r")
    c.alts:SetScript("OnClick", function(self)
        win.altsShowAll = false      -- every fresh open starts short again
        AltMenu(self)
    end)
    c.alts:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Make something else", 1, 0.82, 0.3)
        GameTooltip:AddLine("Click for every recipe that would raise this skill right now - what each "
            .. "one costs, and how many you could make from what is already in your bags. Pick one and "
            .. "Skillwright remembers it for this profession.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    c.alts:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.warn = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.matsHead = U.Heading(c, "Materials for this step")
    c.mats = {}
    c.info = U.Text(c, "GameFontHighlightSmall", "LEFT", true)
    c.diverge = U.Text(c, "GameFontHighlightSmall", "LEFT", true)  -- only when the two modes disagree HERE

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
    c.learnBox.head:SetPoint("TOPLEFT", 10, -8)   -- width is set where it is measured, never by anchors
    c.learnBox.rows = {}
    for i = 1, 4 do
        local r = CreateFrame("Frame", nil, c.learnBox)
        r:SetHeight(22)
        r.icon = U.IconButton(r, 20)
        r.icon:SetPoint("TOPLEFT", 0, 0)
        r.text = U.Text(r, "GameFontHighlight", "LEFT", true)
        r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2)
        -- Only a guessed requirement has anything to say, and it has a lot: see GUESS_NOTE.
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.guess then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Our guess, not the trainer's number", 1, 0.82, 0.3)
            GameTooltip:AddLine(GUESS_NOTE, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        c.learnBox.rows[i] = r
    end
    c.learnBox.later = U.Text(c.learnBox, "GameFontHighlightSmall", "LEFT", true)
    c.learnBox.where = U.Text(c.learnBox, "GameFontHighlight", "LEFT", true)
    c.learnBox.mean = U.Text(c.learnBox, "GameFontHighlightSmall", "LEFT", true)
    c.learnBox.hint = U.Text(c.learnBox, "GameFontHighlightSmall", "LEFT", true)
    c.learnBox:Hide()

    c.trainBtn = U.Button(c, "Train", 120, 24)
    c.trainBtn:SetScript("OnClick", function(self) SW.Trainer.Train(self.list or {}) end)


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
        -- tipExtra alone is enough. A "Train Expert Blacksmithing" row has no item and no spell,
        -- only the function that writes its lines, so this returned before showing anything - and
        -- that row is the one whose text is cut off, which left no way at all to read it.
        if not (self.tipItem or self.tipSpell or self.tipExtra) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.tipItem and self.tipItem > 0 then
            GameTooltip:SetItemByID(self.tipItem)
        elseif self.tipSpell then
            GameTooltip:SetSpellByID(self.tipSpell)
        end
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
    local rank = math.max(1, SW.Prof.Rank(prof))
    -- WHAT THE MENU WILL NOT OFFER. A grey recipe gives nothing, ever - listing it is offering the
    -- player a way to waste materials. Below that, the solver already refuses to PLAN anything under
    -- CHANCE_FLOOR, and a menu that offers what the planner would reject is the guide arguing with
    -- itself. The exception is a recipe you can make right now from what is in your bags: that is a
    -- "use these up" offer rather than a plan, which is why it says how much skill it is worth.
    local function worthOffering(yellow, grey, canMake)
        if not (yellow and grey) then return true end     -- nothing to judge it on: leave it in
        local chance = SW.Solver.Chance(yellow, grey, rank)
        if chance <= 0 then return false end
        return chance >= SW.Solver.CHANCE_FLOOR or (canMake or 0) > 0
    end
    -- Built as a list first, because how many there are decides how many are shown.
    local rows = {}
    local function row(spell, label) rows[#rows + 1] = { spell = spell, label = label } end
    do
        -- everything that is a guaranteed skill-up right now, cheapest-to-finish first
        local listed = {}
        for _, o in ipairs(cur.orange or {}) do
            listed[o.spell] = true
            if worthOffering(o.yellow, o.grey, o.canMake) then
                local mats = {}
                for i = 1, #o.mats, 2 do
                    mats[#mats + 1] = ("%dx %s"):format(o.mats[i + 1], U.ItemName and U.ItemName(o.mats[i])
                        or (SW.ItemName(o.mats[i]) or ("item " .. o.mats[i])))
                end
                local label = ("%s  |cff8a8a8a%s|r"):format(U.RecipeName(o.spell), table.concat(mats, " + "))
                if (o.canMake or 0) > 0 then
                    label = label .. ("  |cff40bf40you can make %d|r"):format(o.canMake)
                    -- and what those are worth, so "might as well use them up" has a number on it
                    for _, e in ipairs(Plan.Leftovers(prof) or {}) do
                        if e.spell == o.spell then
                            label = label .. (e.points >= 0.75
                                and ("|cff8a8a8a, about %d skill|r"):format(math.floor(e.points + 0.5))
                                or "|cff8a8a8a, probably no skill|r")
                            break
                        end
                    end
                end
                if (o.missing or 0) > 0 then
                    label = label .. ("  |cff8a8a8a%s to buy|r"):format(SW.MoneyShort(o.missing))
                end
                row(o.spell, label)
            end
        end
        -- and the recipes that are interchangeable for the plan itself
        for _, a in ipairs(step.alts or {}) do
            if not listed[a.spell] and worthOffering(a.yellow, a.grey, 0) then
                local extra = (a.cost or 0) - (step.costEach or 0)
                local label = U.RecipeName(a.spell)
                if extra > 0 then
                    label = label .. ("  |cff8a8a8a+%s each|r"):format(SW.MoneyShort(extra))
                elseif extra < 0 then
                    label = label .. ("  |cff40bf40%s less each|r"):format(SW.MoneyShort(-extra))
                end
                row(a.spell, label)
            end
        end
    end

    -- HOW MANY TO SHOW. At Blacksmithing 97 there are two dozen recipes that would all give a
    -- skill point, and a menu of two dozen is not a choice, it is a wall - the second time the
    -- user has said a page of this addon shows too much. The list is already sorted by what you
    -- would still have to buy, so the top of it is the part worth reading; the rest is one click
    -- away rather than gone. A recipe you have already picked is always shown, whatever it costs.
    local SHOW = 8
    local shown = rows
    if not win.altsShowAll and #rows > SHOW + 1 then
        shown = {}
        for _, r in ipairs(rows) do
            if #shown < SHOW or Plan.Preferred(prof, r.spell) then shown[#shown + 1] = r end
        end
    end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Make instead")
        root:CreateRadio("Let Skillwright choose", function() return not Plan.Preferred(prof, step.spell)
            and not step.chosenByPlayer end, function() Plan.Prefer(prof, nil) end)
        for _, r in ipairs(shown) do
            root:CreateRadio(r.label, function() return Plan.Preferred(prof, r.spell) end,
                function() Plan.Prefer(prof, r.spell) end)
        end
        if #shown < #rows then
            root:CreateButton(("|cff8a8a8aShow all %d|r"):format(#rows), function()
                win.altsShowAll = true
                AltMenu(owner)
            end)
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
            local price = m.full or m.unit                  -- what a shop charges, not what we ranked by
            local right = (n and price) and Cost(n * price, false) or ""
            tt:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
        end
        if step.vendorOnly then
            tt:AddLine("Every material comes from a vendor.", 0.4, 0.8, 0.4)
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
    -- The alts line wraps, and a wrapped line only reports its real height once something has said
    -- how wide it is. Placing and sizing it in one place keeps the three callers honest.
    -- One place sizes and shows it, so the three callers cannot drift apart - and the text is
    -- measured at the width it will really have, inside the panel and clear of the chevron.
    local function showAlts(text)
        c.altsText:SetText(text)
        c.alts:SetWidth(width - 10)
        c.altsText:SetWidth(width - 10 - 8 - 18)
        c.alts:SetHeight(math.max(22, c.altsText:GetStringHeight() + 8))
        c.alts:Show()
    end

    local function place(widget, x, gap, h)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", c, "TOPLEFT", x or 4, y - (gap or 0))
        if widget.GetStringHeight and not widget.line then widget:SetWidth(width - (x or 4) - 6) end
        widget:Show()
        local hh = h or (widget.GetStringHeight and widget:GetStringHeight()) or widget:GetHeight()
        y = y - (gap or 0) - hh
    end

    -- the recipe card is as tall as its (wrapping) title and subtitle, at least the icon
    -- Where the title starts: beside the icon, or at the card's own margin when there is none.
    -- Every branch that shows or hides the icon calls this, or it inherits the last render's anchor.
    local function titleAt(hasIcon)
        c.title:ClearAllPoints()
        c.title:SetPoint("RIGHT", c, "RIGHT", -4, 0)
        if hasIcon then
            c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -1)
        else
            c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 4, -5)
        end
    end

    local function headerY()
        -- no icon, no 48 pixels of icon to clear
        local floor = c.icon:IsShown() and 48 or 20
        return -math.max(floor, c.title:GetStringHeight() + c.sub:GetStringHeight() + 14)
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
    for _, w in ipairs({ c.learn, c.why, c.alts, c.learnBox, c.diverge, c.warn, c.matsHead, c.info, c.craftBtn, c.buyBtn, c.trainBtn,
                         c.targetLabel, c.targetSlot, c.targetText, c.autoCB }) do
        w:Hide()
        if w.line then w.line:Hide() end
    end
    HidePool(c.mats, 1)

    if win.noGuideFor then
        c.icon:Hide()
        titleAt(false)
        local plannable = {}
        for _, id in ipairs(SW.Prof.All()) do plannable[#plannable + 1] = SW.ProfName(id) end
        c.title:SetText(("Skillwright has no guide for %s"):format(SW.ProfName(win.noGuideFor)))
        c.sub:SetText(("|cff8a8a8aIt plans crafting professions: %s. Open one of those, or pick it above.|r")
            :format(table.concat(plannable, ", ")))
        c:SetHeight(80)
        return
    end

    if not cur then
        c.icon:Hide()
        titleAt(false)
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
        titleAt(true)
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
        -- Needed up here as well as below: the header must not describe a recipe they cannot make yet
        -- as though it were today's work.
        local needsTraining = have and not cur.known and not (tool and tool.buy)
        if tool then
            titleAt(true)
            c.icon:Show()
            c.icon:Set(tool.item, tool.spell)
            c.title:SetText(("|cffffd100First:|r %s"):format(ItemText(tool.item)))
            c.sub:SetText(("%s one - |cffffffff%s|r needs it."):format(tool.buy and "Buy" or "Make", U.RecipeName(s.spell)))
        else
            -- The action is the headline. Naming the recipe here, in the place and colour the card
            -- uses for "make this", read as "you have this" - and it kept the eye off the panel that
            -- says what to actually do. The recipe is still named one line down, in a sentence, and
            -- it has its own row with its own icon inside that panel.
            if needsTraining then
                c.icon:Hide()
                titleAt(false)
                c.title:SetText(("Go to a %s trainer"):format(SW.ProfName(prof)))
                c.sub:SetText(("|cff8a8a8aThe next step is|r |cffffd100%s|r|cff8a8a8a, which you "
                    .. "haven't learned. About|r |cffffffff%d|r |cff8a8a8aof them would take you from "
                    .. "skill|r |cffffffff%d|r |cff8a8a8ato|r |cffffffff%d|r|cff8a8a8a.|r")
                    :format(U.RecipeName(s.spell), cur.left, cur.rank, s.to))
            else
                c.icon:Set(s.item, s.spell, StepTooltip(s))
                c.icon:Show()
                titleAt(true)
                -- A recipe the PLAYER asked for is named as theirs, on the line that names it.
                -- The marker used to sit at the end of the "Make instead" sentence, which names a
                -- DIFFERENT recipe - so a chosen step at 158 crafts read as Fastest recommending
                -- 158 crafts over the 31 in the very next line. It also fired on `swapped`, which
                -- is the guide substituting a recipe by itself: not the player's doing, and not
                -- something to hand them the blame for.
                local yours = ""
                if Plan.Preferred(prof, s.spell) then
                    yours = "  |cff40bf40(your choice)|r"
                elseif cur.swapped then
                    yours = "  |cff8a8a8a(swapped in - you cannot make the route's recipe)|r"
                end
                c.title:SetText(U.Colored(cur.color, U.RecipeName(s.spell))
                    .. (s.qty > 1 and (" |cff8a8a8ax" .. s.qty .. "|r") or "") .. yours)
                c.sub:SetText(("|cff8a8a8aAbout|r |cffffffff%d|r |cff8a8a8aof these takes you from skill|r "
                    .. "|cffffffff%d|r |cff8a8a8ato|r |cffffffff%d|r"):format(cur.left, cur.rank, s.to))
            end
        end
        y = headerY()

        -- Learned? Where from?
        local learn
        if not have then
            learn = ("|cffffd100Preview|r - you don't have %s. The plan starts from skill 1."):format(SW.ProfName(prof))
        elseif tool and tool.buy then
            learn = "Sold by vendors (tools usually sit with the trade supplies)."
        elseif cur.known then
            learn = nil                                  -- the normal case needs no words
        else
            local svc = SW.Trainer.services[subject.spell]
            if svc and svc.type == "available" then
                learn = "|cffff8040Not learned yet|r - this trainer teaches it."
            elseif subject.source == "c" then
                learn = "|cffff8040Not learned yet|r - " .. CAMP_QUEST_HINT
            elseif subject.source and subject.source:match("^s:") then
                learn = ("|cffff8040Not learned yet|r - a %s specialization recipe."):format(subject.source:sub(3))
            else
                learn = subject.learnEstimated
                    and ("|cffff8040Not learned yet|r - a trainer teaches it. We think around skill %d; "
                         .. "that is our own guess and it usually reads late."):format(subject.learn or 1)
                    or ("|cffff8040Not learned yet|r - learn it at a trainer (needs skill %d)."):format(
                        subject.learn or 1)
            end
        end
        -- Not learned yet: the whole point of the page is "go and learn it", so say it loudly.
        if needsTraining then
            local box = c.learnBox
            local due = Plan.TrainingDue(prof)
            box.head:SetText(due and ("Train |cffffd100%s %s|r first"):format(due.name, SW.ProfName(prof))
                or "Learn this at a trainer")
            -- Width first, then measure - the same order place() uses, and the only one that reports a
            -- wrapped line's real height. Getting it the other way round is what drew these lines on
            -- top of each other.
            local lineW = width - 8 - 18
            box.head:SetWidth(lineW)
            local by = -8 - box.head:GetStringHeight() - 6
            local function boxLine(fs, gap)
                fs:ClearAllPoints()
                fs:SetWidth(lineW)
                fs:SetPoint("TOPLEFT", box, "TOPLEFT", 10, by - gap)
                fs:Show()
                by = by - gap - fs:GetStringHeight()
            end

            -- this recipe, then the next few the route needs and the character doesn't know
            local list = { { spell = subject.spell, item = subject.item, learn = subject.learn,
                             est = subject.learnEstimated } }
            if route then
                for i = cur.idx + 1, #route.steps do
                    local st = route.steps[i]
                    if not SW.Prof.Knows(prof, st.spell) and st.spell ~= subject.spell then
                        list[#list + 1] = { spell = st.spell, item = st.item, learn = st.learn, est = st.learnEstimated }
                        if #list >= #box.rows then break end
                    end
                end
            end
            -- The header reads as an instruction for THIS trip, so the list under it must only mean
            -- that. The player walked to Ironforge with four of these and could learn one: every
            -- number was right and nothing said which of them were for later.
            local rank = cur.rank or 0
            local now, later = {}, {}
            for _, e in ipairs(list) do
                local svc = SW.Trainer.services[e.spell]
                -- the trainer standing in front of us beats any number we hold
                if (svc and svc.type == "available") or (e.learn or 1) <= rank then
                    now[#now + 1] = e
                else
                    later[#later + 1] = e
                end
            end
            local i = 0
            local function draw(e, dim)
                i = i + 1
                local r = box.rows[i]
                if not r then return end
                r.icon:Set(e.item, e.spell, nil)
                r.guess = e.est
                local svc = SW.Trainer.services[e.spell]
                local cost = SW.DB().trainerCost and SW.DB().trainerCost[e.spell]
                local src = SW.RecipeSource(e.spell)
                if src and src.kind == "vendor" then cost = cost or src.price end
                -- A guessed number is not the game's number, and ours is 20 skill late as often as
                -- not - so it is never printed the way a recorded one is.
                local req = e.est and ("|cff8a8a8a(we think skill %d)|r"):format(e.learn or 1)
                    or ("|cff8a8a8a(skill %d)|r"):format(e.learn or 1)
                r.text:SetText(("%s%s|r  %s%s%s"):format(dim and "|cff8a8a8a" or "", U.RecipeName(e.spell), req,
                    cost and ("  |cff8a8a8a" .. SW.MoneyShort(cost) .. "|r") or "",
                    (svc and svc.type == "available") and "  |cff40bf40this trainer has it|r" or ""))
                r.text:SetWidth(lineW - 28)                 -- measure what will actually be drawn
                local h = math.max(22, r.text:GetStringHeight() + 4)
                r:SetHeight(h)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", box, "TOPLEFT", 10, by)
                r:SetPoint("RIGHT", box, "RIGHT", -8, 0)
                r:Show()
                by = by - h
            end
            for _, e in ipairs(now) do draw(e, false) end
            if #later > 0 and i < #box.rows then
                box.later:SetText(#now > 0 and "|cff8a8a8aNot yet - come back for these:|r"
                    or "|cff8a8a8aNothing here yet. These come later:|r")
                boxLine(box.later, 2)
                by = by - 4
                for _, e in ipairs(later) do draw(e, true) end
            else
                box.later:Hide()
            end
            for j = i + 1, #box.rows do box.rows[j]:Hide() end

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
            boxLine(box.where, 6)

            if where and not seen then
                box.hint:SetText("|cff8a8a8a" .. where .. "|r")
                boxLine(box.hint, 4)
            else
                box.hint:Hide()
            end
            -- something useful while they walk to the trainer - a suggestion, never the instruction
            local mw = cur.meanwhile
            if mw then
                local extra = ""
                for i = (cur.idx or 1) + 1, #((route and route.steps) or {}) do
                    for _, m in ipairs(route.steps[i].mats or {}) do
                        if m.id == mw.item then extra = (" - these go into %s later"):format(
                            U.RecipeName(route.steps[i].spell)) break end
                    end
                    if extra ~= "" then break end
                end
                box.mean:SetText(("|cff8a8a8aMeanwhile you could make|r |cffffd100%s|r|cff8a8a8a: about %d "
                    .. "crafts%s.|r"):format(U.RecipeName(mw.spell), mw.crafts or 0, extra))
                boxLine(box.mean, 6)
            else
                box.mean:Hide()
            end
            box:SetHeight(math.max(60, -by + 10))
            place(box, 4, 8)
            box:SetPoint("RIGHT", c, "RIGHT", -4, 0)
            box:Show()
        else
            if learn then
                c.learn:SetText(learn)
                place(c.learn, 4, 6)
            end
        end

        -- The route wanted something the character cannot make yet: say so, name it, and say what would
        -- unblock it. Without this the page silently suggests a different recipe from the Route tab.
        if cur.blockedBy then
            local b = cur.blockedBy
            local svc = SW.Trainer.services[b.spell]
            local how
            if svc and svc.type == "available" then
                how = "this trainer teaches it"
            elseif b.source == "c" then
                how = "the camping quest teaches it"
            elseif b.source == "r" then
                how = "you need to find the recipe"
            else
                how = b.learnEstimated
                    and ("a trainer teaches it - we think around skill %d, which is a guess"):format(b.learn or 1)
                    or ("a trainer teaches it from skill %d"):format(b.learn or 1)
            end
            -- Two different situations, two different sentences. When they can walk in and learn it, the
            -- card gives an instruction and the numbers that make it obviously right; when they cannot,
            -- describing the block is the useful thing, because nothing is actionable yet.
            local canLearnNow = (cur.rank or 0) >= (b.learn or 1) and b.source ~= "r"
            if canLearnNow then
                local compare = (b.crafts and cur.left and b.crafts < cur.left)
                    and (" |cff8a8a8a- %d crafts to %d instead of %d.|r"):format(b.crafts, s.to, cur.left)
                    or "."
                local lead = (svc and svc.type == "available")
                    and ("|cff40bf40Learn|r |cffffd100%s|r |cff40bf40from this trainer, right here|r")
                        :format(U.RecipeName(b.spell))
                    or ("|cff40bf40Go and learn|r |cffffd100%s|r |cff40bf40at a trainer|r")
                        :format(U.RecipeName(b.spell))
                c.why:SetText(lead .. compare .. "\n|cff8a8a8aUntil then, this is the best you can make.|r")
            else
                c.why:SetText(("|cffffd100The route wants|r %s |cffffd100here|r |cff8a8a8a- you have not "
                    .. "learned it yet (%s). Until then this is the best you can make.|r")
                    :format(U.RecipeName(b.spell), how))
            end
            place(c.why, 4, 6)
        elseif cur.feeds then
            c.why:SetText(("|cff8a8a8aThese are also the materials for|r |cffffd100%s|r|cff8a8a8a, "
                .. "further along the route.|r"):format(U.RecipeName(cur.feeds)))
            place(c.why, 4, 6)
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
                showAlts(("|cff8a8a8aMake instead:|r |cffffd100%s|r |cff8a8a8a- %s%s|r")
                    :format(U.RecipeName(other.spell), table.concat(bits, ", "),
                        #orange > 2 and (", +%d more"):format(#orange - 2) or ""))
                place(c.alts, 4, 4)
            end
        elseif s.alts and #s.alts > 0 then
            local a = s.alts[1]
            local extra = (a.cost or 0) - (s.costEach or 0)
            local tail = extra > 0 and (", %s more each"):format(SW.MoneyShort(extra))
                or (extra < 0 and (", %s less each"):format(SW.MoneyShort(-extra)) or ", same cost")
            local more = #s.alts > 1 and (" |cff8a8a8a(+%d more)|r"):format(#s.alts - 1) or ""
            showAlts(("|cff8a8a8aMake instead:|r |cffffd100%s|r |cff8a8a8a- same skill-ups%s|r%s")
                :format(U.RecipeName(a.spell), tail, more))
            place(c.alts, 4, 4)
        elseif (#(cur.orange or {}) > 0) or #(Plan.Leftovers(prof, s.spell) or {}) > 0 then
            -- nothing worth naming, but there IS something else you could make: say so plainly, so the
            -- menu is reachable instead of hidden behind a sentence that had no reason to appear
            showAlts("|cff8a8a8aMake something else instead|r")
            place(c.alts, 4, 4)
        else
            c.alts:Hide()
        end

        -- The route runs the whole profession now, so what stops is the character, not the plan. Say
        -- which rank they are held at and what lifts it - and, for the ranks that come from a book or a
        -- quest rather than a trainer, say that instead of "at a trainer".
        local capText
        local due = have and Plan.TrainingDue(prof)
        local capped = have and route and route.to and (cp.max or 0) > 0 and route.to >= cp.max
            and cp.max < SW.Ceiling(prof)
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
            c.warn:SetText(("|cffff6060Your skill stops at %d until you train.|r Learn |cffffd100%s %s|r "
                .. "to go further.%s%s"):format(cp.max, name, SW.ProfName(prof), need,
                hint and ("\n|cff8a8a8a" .. hint .. "|r") or ""))
            capText = true                               -- drawn further down, with the rest of the route
        end

        -- Materials
        place(c.matsHead, 4, 14, 14)
        c.matsHead.line:Show()
        local perRow = math.max(1, math.floor((width - 8) / 64))
        local rowY = y - 6
        local vendorBuy, bankLines, partial = {}, {}, false
        for i, m in ipairs(cur.mats) do
            local cell = MatCell(c, i)
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", c, "TOPLEFT", 14 + col * 64, rowY - row * 56)
            cell:Set(m.id, nil, function(tt)
                tt:AddLine(" ")
                tt:AddDoubleLine("Have / need", ("%d / %d"):format(m.have, m.need), 1, 0.82, 0.3, 1, 1, 1)
                if m.bank > 0 then tt:AddLine(("%d of those are in your bank."):format(m.bank), 0.5, 0.65, 1) end
                local each = m.full or m.unit
                tt:AddDoubleLine("Price each", each and Cost(each, false) or "|cff8a8a8ano price|r",
                    0.7, 0.7, 0.7, 1, 1, 1)
            end)
            cell.count:SetText(("%s%d|r/%d"):format(m.have >= m.need and "|cff40bf40" or "|cffff6060", m.have, m.need))
            cell:Show()
            if m.short > 0 then SW.Prices.AddToBuy(vendorBuy, m.id, m.short, m.full or m.unit) end
            if m.bank > 0 then bankLines[#bankLines + 1] = ("%d %s"):format(m.bank, ItemText(m.id)) end
            if NoPrice(m.priceSource) then partial = true end
        end
        local rows = math.ceil(#cur.mats / perRow)
        y = rowY - rows * 56

        if tool and tool.buy then SW.Prices.AddToBuy(vendorBuy, tool.item, 1, tool.cost or 0) end

        local info = {}
        if tool then
            info[#info + 1] = tool.cost and ("It costs about %s. You only need one."):format(SW.MoneyShort(tool.cost))
                or "You only need one."
        elseif cur.enough then
            info[#info + 1] = "|cff40bf40You already have the materials for this.|r"
        else
            -- ONE money line. What you still have to lay out, and what it really costs you once the
            -- products are sold - the second number is the one that decides anything, and on its own
            -- line it read as a separate bill.
            local back = Plan.Resale(s, cur.left)
            local out = (cur.missingCost or 0) > 0 and cur.missingCost or (Plan.StepCost(s) * cur.left)
            local line = ("Still to buy: %s%s"):format(Cost(out, partial),
                partial and " |cff8a8a8a(only what we can price)|r" or "")
            if back and back > 0 and out and out > 0 then
                local net = out - back
                line = line .. (net > 0
                    and ("|cff8a8a8a - about|r %s |cff8a8a8aafter you sell them.|r"):format(SW.MoneyShort(net))
                    or ("|cff40bf40 - it pays for itself.|r"))
            else
                line = line .. "."
            end
            info[#info + 1] = line
        end
        -- ONE blocker line, and only when something is actually in the way. Being short of gold is not
        -- the end of the step: the money comes back as you sell, so the way through is part of the same
        -- sentence rather than a line of its own.
        if not tool then
            local short, purse = Plan.Shortfall(cur)
            local canNow = cur.craftable or 0
            if short then
                info[#info + 1] = ("|cffff6060You have %s - all of it at once needs %s more.|r%s"):format(
                    SW.MoneyShort(purse), SW.MoneyShort(short),
                    canNow > 0 and ("|cff8a8a8a Make %d, sell, buy the rest.|r"):format(canNow) or "")
            elseif canNow <= 0 and cur.known then
                local missing = {}
                for _, m in ipairs(cur.mats) do
                    if m.short > 0 then missing[#missing + 1] = ("%d more %s"):format(m.short, ItemText(m.id)) end
                end
                if #missing > 0 then
                    info[#info + 1] = ("|cffff8040You need %s|r |cff8a8a8a- the Shopping tab has the rest.|r")
                        :format(table.concat(missing, ", "))
                end
            end
        end
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
            if SetupCraftButton(c.craftBtn, cur, prof) then placeButton(c.craftBtn) end
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

        -- What stops the route, then what comes next: both are about the road ahead, not this craft.
        if capText then place(c.warn, 4, 12) end

        -- "Up next" used to be here: the first four rows of the Route tab, printed a second time
        -- on the page whose job is the NEXT thing to do. The tab is one click away and shows all of
        -- them, grouped, with the trainer visits in place.
    end

    -- Three more blocks used to sit here and they have all moved to the Route tab, where the route
    -- lives: where trainer recipes run out (a list about skill 285, on the page of someone standing
    -- at 97 - and the Route tab's own note already pointed here for it), what the rest of the route
    -- costs, and what the other mode would cost. None of them answers "what do I do next".

    -- The one place the two modes visibly disagree is on the step in front of you, and there the
    -- player is not asking how we weigh materials - they are asking which one to believe. So the line
    -- appears there and nowhere else: never a standing footnote about how the modes work.
    local otherSpell = Plan.Divergence(prof, s and s.spell)
    if otherSpell then
        local fastName = SW.Settings().mode == "fast" and U.RecipeName(s.spell) or U.RecipeName(otherSpell)
        local cheapName = SW.Settings().mode == "fast" and U.RecipeName(otherSpell) or U.RecipeName(s.spell)
        -- What they actually disagree about. This used to say Fastest weighs materials by what
        -- a vendor pays, which stopped being true the day the weighting came out and went on being
        -- printed on the card - the one place a player would read it and believe it.
        c.diverge:SetText(("|cff8a8a8aFastest says|r %s|cff8a8a8a, Cheapest says|r %s|cff8a8a8a - they "
            .. "disagree because Fastest counts crafts and reads no price at all, while Cheapest ranks "
            .. "by what the auction charges. With a scan this fresh, Cheapest has the better numbers.|r")
            :format(fastName, cheapName))
        place(c.diverge, 4, 4)
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
    -- the only handle on the Route page from outside this file. Like win.card, which existed for
    -- the same reason: without one the page cannot be asked anything.
    win.routePage = f
end

-- `numberFirst` puts the skill column ahead of the icon, which is what a column you sort by wants.
-- Applied on every call, not once at build: these rows are pooled, and the same frame is a list row
-- on one pass and a route step on the next.
local function RouteRow(f, i, numberFirst)
    local r = f.rows[i]
    if r then
        r:Layout(numberFirst)
        return r
    end
    r = LineRow(f.c, f.rows, i)
    r:SetHeight(ROW)
    r.icon:SetSize(22, 22)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    -- Not Options_List_Active: that atlas is not in this client, which is how the selected
    -- mode button ended up with no marking at all. These rows had no background for the same
    -- reason, and nobody noticed because a missing atlas simply draws nothing.
    r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.range = U.Text(r, "GameFontNormalSmall")
    r.range:SetWidth(52)
    function r:Layout(numberFirst)
        -- these rows are pooled: a frame that was a dark group header on one pass is an ordinary
        -- row on the next, and must not keep the bar or the rarity border with it
        self.bg:SetColorTexture(1, 1, 1, 0.05)
        if self.rarity then self.rarity:Hide() end
        -- A ROW'S HEIGHT AND THE STEP BETWEEN ROWS ARE THE SAME MEASUREMENT. The list's spacing
        -- was tightened to TIGHT and the rows left at ROW with a 22-pixel icon, so every row
        -- overlapped the next by eight and every icon leaned into the line below.
        local h = numberFirst and TIGHT or ROW
        self:SetHeight(h)
        self.icon:SetSize(h - 4, h - 4)
        self.icon:ClearAllPoints()
        self.range:ClearAllPoints()
        self.text:ClearAllPoints()
        if numberFirst then
            self.range:SetWidth(26)
            self.range:SetJustifyH("RIGHT")
            self.range:SetPoint("LEFT", 2, 0)
            self.icon:SetPoint("LEFT", self.range, "RIGHT", 6, 0)
            self.text:SetPoint("LEFT", self.icon, "RIGHT", 6, 0)
        else
            self.range:SetWidth(52)
            self.range:SetJustifyH("LEFT")
            self.icon:SetPoint("LEFT", 2, 0)
            self.range:SetPoint("LEFT", self.icon, "RIGHT", 6, 0)
            self.text:SetPoint("LEFT", self.range, "RIGHT", 6, 0)
        end
        -- LEFT, always. A FontString that is right-justified and too long for its box keeps
        -- the END of the string and clips the start, so "Silver Rod" came out as "er Rod". These
        -- rows are pooled and everything else about them is set per call; this was not.
        self.text:SetJustifyH("LEFT")
        self.text:SetPoint("RIGHT", self.right, "LEFT", -6, 0)
    end
    r:Layout(numberFirst)
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", r.range, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    return r
end

-- A list is a column of facts, not a page of cards: these rows sit closer together than the
-- route's own steps, which are things to go and do.


-- WHAT'S TRAINABLE, in the three groups the class trainer's own panel uses: what you can learn
-- standing at the trainer, what is close, and what is a long way off. Collapsed by default - the
-- page is for the route, and this is a reference list you go and open.
-- Four labels of the same shape: what you do about this group, in two or three words. They used
-- to be "Learn at a trainer" / "Find the recipe" / "Not enough skill yet" / "Too late to help",
-- which is four different kinds of phrase and reads as four unrelated ideas.
local TRAIN_GROUPS = {
    { key = "now",    label = "Learn now",      live = true },
    { key = "recipe", label = "Find the recipe", live = true },
    { key = "soon",   label = "Not yet" },
    { key = "dead",   label = "Outgrown",        dim = true },
}

-- An icon's border carries rarity, the way the game carries it everywhere else. That leaves the
-- text free for craft difficulty, which is what a profession list is for - the two were fighting
-- over one colour before, and I had swapped between them twice.
local function RarityBorder(r, item)
    if not r.rarity then
        r.rarity = r:CreateTexture(nil, "BACKGROUND")
        r.rarity:SetColorTexture(1, 1, 1, 1)
    end
    r.rarity:ClearAllPoints()
    r.rarity:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -1, 1)
    r.rarity:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
    local q = item and item > 0 and C_Item and C_Item.GetItemQualityByID
        and C_Item.GetItemQualityByID(item)
    local c = q and q > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then
        r.rarity:SetColorTexture(c.r, c.g, c.b, 0.9)
        r.rarity:Show()
    else
        r.rarity:Hide()          -- common and poor get no border, as in the bags
    end
end

local function DrawTrainable(f, prof, c, y, n)
    local list = Plan.Trainable(prof)
    if not list then return y, n end
    local total = #list.now + #list.recipe + #list.soon
    if total == 0 then return y, n end

    local groupOpen, drawnGroups = SW.Settings().trainGroupOpen or {}, 0
    for _, g in ipairs(TRAIN_GROUPS) do
        local rows = list[g.key]
        if #rows > 0 then
            local shownGroup = groupOpen[g.key] and true or false
            -- A header is not a row with a different colour. Full width, a solid bar, the label
            -- at the left and the count at the far right, and air above it so the groups read as
            -- groups - but not above the first one, which already has the column heading over it.
            if drawnGroups > 0 then y = y - 6 end
            drawnGroups = drawnGroups + 1
            n = n + 1
            local h = RouteRow(f, n, true)
            h.bg:Show()
            h.bg:SetColorTexture(0, 0, 0, 0.45)
            h.icon:SetTexture(nil)
            if h.rarity then h.rarity:Hide() end
            h.range:SetText("")
            -- The column label lives here, in the one row that was always going to be drawn.
            -- It used to have a bar of its own above a section heading that had a bar of its own,
            -- which is three stacked bars before the first recipe.
            h.range:SetText("|cff8a8a8askill|r")
            h.text:SetText(("%s |cffffd100%s|r"):format(shownGroup and "-" or "+", g.label))
            h.right:SetText(("|cff8a8a8a%d|r"):format(#rows))
            h.tipExtra = function(tt)
                tt:AddLine(g.label, 1, 0.82, 0.3)
                tt:AddLine("|cff8a8a8askill|r on the left: what you need to learn it.",
                    0.85, 0.85, 0.85, true)
                tt:AddLine("The number on the right of each row is the skill it stops giving you "
                    .. "anything at. The further that is from where you are, the longer it pays.",
                    0.85, 0.85, 0.85, true)
                tt:AddLine(("The name is the colour the trade window gives it: %s always, %s "
                    .. "usually, %s sometimes, %s never."):format(
                    U.Colored("orange", "orange"), U.Colored("yellow", "yellow"),
                    U.Colored("green", "green"), U.Colored("grey", "grey")), 0.6, 0.6, 0.6, true)
            end
            h.tipItem, h.tipSpell = nil, nil
            h:SetHeight(HEADER)
            h:SetScript("OnMouseUp", function()
                local open = SW.Settings().trainGroupOpen
                open[g.key] = not open[g.key] or nil
                SW.RefreshWindow()
            end)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
            h:SetPoint("RIGHT", c, "RIGHT", 0, 0)
            h:Show()
            y = y - HEADER

            for _, row in ipairs(shownGroup and rows or {}) do
                local reach = row.need <= list.rank
                n = n + 1
                local r = RouteRow(f, n, true)
                r.bg:Hide()
                r.icon:SetTexture(U.RecipeIcon(row.item, row.spell))
                RarityBorder(r, row.item)
                -- The skill it takes to learn, first, because that is what the list is sorted
                -- by - and coloured by what the recipe is worth at your level, which is the one
                -- place that colour is about the same thing the number is.
                r.range:SetText(U.Colored(row.colour, tostring(row.need)))
                -- The name says what the ITEM is. Difficulty moved to the number, which is
                -- already about skill, so the two are not fighting over one colour any more.
                r.text:SetText((row.item and row.item > 0 and U.ItemQualityColor(row.item)
                    or "|cffffffff") .. U.RecipeName(row.spell) .. "|r")
                r.text:SetAlpha(g.dim and 0.5 or 1)
                -- and the level you need to USE it, which is the "can I wear this" question. Not
                -- in our data - Items.lua carries itemLevel, which is a different number - so it
                -- comes from the client, and a row it has not cached shows nothing there rather
                -- than a wrong number.
                local useLevel = row.item and row.item > 0 and C_Item and C_Item.GetItemInfo
                    and select(5, C_Item.GetItemInfo(row.item))
                r.right:SetText((row.estimated and "|cffff8040*?|r " or "")
                    .. ((useLevel and useLevel > 1) and ("|cff8a8a8alvl %d|r"):format(useLevel) or ""))
                r.tipItem, r.tipSpell, r.tipExtra = row.item, row.spell, nil
                r:SetScript("OnMouseUp", nil)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", c, "TOPLEFT", 12, y)
                r:SetPoint("RIGHT", c, "RIGHT", -2, 0)
                r:Show()
                y = y - TIGHT
            end
        end
    end
    return y - 4, n
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
    -- HOW MUCH OF THE ROUTE TO DRAW. All of it pushed everything under it off the page, and the
    -- list below went unseen. The steps that do not fit are named in a line rather than dropped.
    local SHOW_STEPS = 8
    local drawnSteps, skippedSteps = 0, 0
    local routeOpen = SW.Settings().routeOpen ~= false

    -- The route folds away like the groups below it: same bar, same + and -, same saved state.
    n = n + 1
    local rhead = RouteRow(f, n, true)
    rhead:SetHeight(HEADER)
    rhead.bg:Show()
    rhead.bg:SetColorTexture(0, 0, 0, 0.45)
    rhead.icon:SetTexture(nil)
    if rhead.rarity then rhead.rarity:Hide() end
    rhead.range:SetText("|cff8a8a8askill|r")
    rhead.text:SetText(("%s |cffffd100The route|r"):format(routeOpen and "-" or "+"))
    rhead.right:SetText(("|cff8a8a8a%d to %d|r"):format(rank, route.to))
    rhead.tipItem, rhead.tipSpell = nil, nil
    rhead.tipExtra = function(tt)
        tt:AddLine("The route", 1, 0.82, 0.3)
        tt:AddLine("What to make next, in order, from where you are to the end of the profession. "
            .. "Click to fold it away.", 0.85, 0.85, 0.85, true)
    end
    rhead:SetScript("OnMouseUp", function()
        SW.Settings().routeOpen = not routeOpen
        SW.RefreshWindow()
    end)
    rhead:ClearAllPoints()
    rhead:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
    rhead:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    rhead:Show()
    y = y - HEADER
    if not routeOpen then SHOW_STEPS = 0 end
    local owned = Plan.OwnedTools()
    for _, row in ipairs(Plan.Rows(prof) or {}) do
        -- A trainer visit is a step of the route: it is the thing to do next when you reach that rank.
        if row.train and row.train.at > rank and routeOpen then
            local b = row.train
            n = n + 1
            local r = RouteRow(f, n)
            r.bg:Hide()
            r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            r.range:SetText(("|cffffd100%d|r"):format(b.at))
            local hint = b.name and SW.TrainerHint and SW.TrainerHint(prof, b.name)
            r.text:SetText(("|cffffd100Train %s %s|r%s"):format(b.name or "the next rank", SW.ProfName(prof),
                hint and "  |cff8a8a8a(where?)|r" or ""))
            r.right:SetText(b.need and ("|cff8a8a8aneeds skill %d|r"):format(b.need) or "")
            r.tipItem, r.tipSpell, r.tipExtra = nil, nil, function(tt)
                tt:AddLine(("Train %s %s"):format(b.name or "the next rank", SW.ProfName(prof)), 1, 0.82, 0.3)
                tt:AddLine(("Your skill stops at %d until you do."):format(b.at), 0.85, 0.85, 0.85, true)
                if hint then tt:AddLine(hint, 0.6, 0.8, 1, true) end
                if not b.name then
                    tt:AddLine("WoW: Forever adds a rank above Artisan. The client data does not say what "
                        .. "it is called or how far it goes, so Skillwright will not guess - it plans as "
                        .. "far as the recipes reach.", 0.6, 0.6, 0.6, true)
                end
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
            r:SetPoint("RIGHT", c, "RIGHT", -2, 0)
            r:Show()
            y = y - ROW - 1
        end
        local s = row.step
        if s and s.to > rank and drawnSteps >= SHOW_STEPS then
            skippedSteps = skippedSteps + 1
            s = nil
        end
        if s and s.to > rank then
            drawnSteps = drawnSteps + 1
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
            local partial = false
            for _, m in ipairs(s.mats) do if NoPrice(m.priceSource) then partial = true end end
            local known = SW.Prof.Knows(prof, s.spell)
            local guessed = not known and s.learnEstimated
            r.text:SetText((known and "" or (guessed and "|cffff8040*?|r " or "|cffff8040*|r "))
                .. U.RecipeName(s.spell) .. " " .. SourceTag(s.source) .. MatsTag(s))
            local crafts = current and Plan.CraftsLeft(s, rank) or s.crafts
            r.right:SetText(("x%d  %s"):format(crafts, Cost(crafts * Plan.StepCost(s), partial)))
            r.tipItem, r.tipSpell, r.tipExtra = s.item, s.spell, StepTooltip(s)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
            r:SetPoint("RIGHT", c, "RIGHT", -2, 0)
            r:Show()
            y = y - ROW - 1
        end
    end
    -- WHAT STAYS ON THE PAGE, AND WHAT YOU GO AND ASK FOR. This was eight notes stacked under
    -- the route: a legend, the estimate marker explained, where the plan ends and why, the cost
    -- against your purse, how far prices reach, why the route stops, the remaining total, and
    -- which mode you are on. The fourth time a page here has been called too much to read.
    --
    -- The total is what someone is looking for; the legend only earns its line when a marker is
    -- actually on screen above it. Every reason moved to the hover on the total.
    local notes, why = {}, {}

    local restCrafts, restCost = Plan.Remaining(prof)
    if restCrafts > 0 then
        notes[#notes + 1] = ("|cff8a8a8aAbout|r |cffffd100%d|r |cff8a8a8acrafts and|r |cffffd100%s|r "
            .. "|cff8a8a8aleft, skill %d to %d.|r"):format(restCrafts, SW.MoneyShort(restCost), rank, route.to)
    end

    if skippedSteps > 0 and routeOpen then
        n = n + 1
        local more = RouteRow(f, n)
        more.bg:Hide()
        more.icon:SetTexture(nil)
        if more.rarity then more.rarity:Hide() end
        more.range:SetText("")
        more.text:SetText(("|cff8a8a8a... and %d more steps, to skill %d|r")
            :format(skippedSteps, route.to))
        more.right:SetText("")
        more.tipItem, more.tipSpell, more.tipExtra = nil, nil, nil
        more:SetScript("OnMouseUp", nil)
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
        more:SetPoint("RIGHT", c, "RIGHT", -4, 0)
        more:Show()
        y = y - ROW
    end

    -- the legend, only for the markers that are really up there
    local anyUnlearned, anyEstimated = false, false
    for _, st in ipairs(route.steps) do
        if st.to > rank and not SW.Prof.Knows(prof, st.spell) then
            anyUnlearned = true
            if st.learnEstimated then anyEstimated = true end
        end
    end
    local marks = {}
    if anyUnlearned then marks[#marks + 1] = "|cffff8040*|r not learned yet" end
    if anyEstimated then marks[#marks + 1] = "|cffff8040*?|r skill it needs is our estimate" end
    if route.pricedTo or (restCost or 0) > 0 then
        marks[#marks + 1] = "|cff8a8a8aat least|r = some materials have no price"
    end
    if #marks > 0 then notes[#notes + 1] = "|cff8a8a8a" .. table.concat(marks, "   ") .. "|r" end

    -- and the reasons, for whoever wants them
    if anyEstimated then
        why[#why + 1] = "The skill a trainer recipe needs is not in the game data, so some of these "
            .. "numbers are ours. Open the trainer once and Skillwright uses the real one."
    end
    local ceiling = SW.Ceiling(prof)
    why[#why + 1] = ceiling > SW.MAX_RANK
        and ("Planned to %d: a character here has reached that, past the 300 the game data stops at.")
            :format(ceiling)
        or "Planned to 300, the highest skill any recipe in this build needs."
    local reach, total, purse = Plan.GoldReach(prof)
    if reach and total and purse and reach < route.to then
        why[#why + 1] = ("The rest costs about %s and you have %s: enough to reach about %d.")
            :format(SW.MoneyShort(total), SW.MoneyShort(purse), reach)
    end
    if route.pricedTo and route.pricedTo > route.from and route.pricedTo < route.to then
        why[#why + 1] = ("Planned on price up to %d. Nothing above that has a price, so from there "
            .. "it is the shortest route."):format(route.pricedTo)
    end
    if route.gapAt then
        -- NAME WHAT ENDS IT. This used to say the route stopped because no trainer recipe went
        -- past that rank, and blame recipes from unknown drops. For every profession where a
        -- route really does stop, that is not what stops it - a workstation does, and we have
        -- carried which one on every recipe since the beginning without ever saying it.
        local stations = Plan.GapStations(prof, route.gapAt)
        if stations then
            -- one sentence, not two: the page is three lines and this is one fact
            local bits = {}
            for _, st in ipairs(stations) do
                bits[#bits + 1] = ("|cffffd100%s|r|cff8a8a8a (%d, to %d)|r")
                    :format(st.name, st.count, st.to)
            end
            notes[#notes + 1] = ("|cff8a8a8aEnds at|r |cffffd100%d|r|cff8a8a8a - past that you "
                .. "need|r %s"):format(route.gapAt, table.concat(bits, ", "))
            why[#why + 1] = ("The recipes that would carry it further can only be made standing at "
                .. "a workstation, and the plan cannot assume you will travel to one. They are in "
                .. "the list below, under the group for what you have the skill for.")
        else
            notes[#notes + 1] = ("|cff8a8a8aThe route ends at|r |cffffd100%d|r|cff8a8a8a.|r")
                :format(route.gapAt)
            why[#why + 1] = ("No trainer recipe gives skill past %d. Most of Forever's new recipes "
                .. "come from recipe items whose drops and vendors aren't known yet, so the plan "
                .. "can only use one once you have learned it."):format(route.gapAt)
        end
    end
    local trade = Plan.TradeOff(prof)
    if trade then
        why[#why + 1] = ("You are on %s. %s"):format(
            SW.Settings().mode == "fast" and "Fastest" or "Cheapest", trade)
    end

    f.note:SetScript("OnEnter", #why > 0 and function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("About this route", 1, 0.82, 0.3)
        for _, line in ipairs(why) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end or nil)
    f.note:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.note:EnableMouse(#why > 0)

    -- The list goes here: under the steps, above the summary. The note is the last word on the
    -- page and a reference list does not belong after it.
    y, n = DrawTrainable(f, prof, c, y - 4, n)

    f.note:SetText(table.concat(notes, "\n"))
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y - 8)
    f.note:SetWidth(c:GetWidth() - 10)
    y = y - 8 - f.note:GetStringHeight()

    c:SetHeight(-y + 16)
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
    local y, n, nh, total, partial = -2, 0, 0, 0, false
    local buyList = {}
    for _, g in ipairs(groups) do
        nh = nh + 1
        local h = f.heads[nh]
        if not h then h = U.Heading(c, ""); f.heads[nh] = h end
        h:SetText(("%s |cff8a8a8a(to %d)|r  %s"):format(g.tier.name, g.tier.cap,
            Cost(g.cost, (g.unpriced or 0) > 0)))
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 2, y - 6)
        h:Show(); h.line:Show()
        y = y - 26
        -- dearest first, and the ones we cannot price last: they still have to be bought.
        table.sort(g.order, function(a, b)
            local av, bv = a.unit and a.need * a.unit or -1, b.unit and b.need * b.unit or -1
            if av ~= bv then return av > bv end
            return a.need > b.need
        end)
        for _, e in ipairs(g.order) do
            n = n + 1
            local r = LineRow(c, f.rows, n)
            r.icon:SetTexture(U.ItemIcon(e.id))
            r.text:SetText(ItemText(e.id))
            local col = e.have >= e.need and "|cff40bf40" or "|cffffffff"
            r.right:SetText(("%s%d|r/%d  %s"):format(col, math.min(e.have, e.need), e.need,
                e.unit and Cost(e.need * e.unit, false) or "|cff8a8a8ano price|r"))
            r.tipItem, r.tipSpell = e.id, nil
            r.tipExtra = function(tt)
                tt:AddLine(" ")
                tt:AddDoubleLine("Have / need", ("%d / %d"):format(e.have, e.need), 1, 0.82, 0.3, 1, 1, 1)
                local src = ({ ah = "auction house", vendor = "vendor", craft = "made from its own materials",
                    unknown = "no price yet - scan the auction house" })[e.priceSource] or e.priceSource
                tt:AddDoubleLine("Price each", e.unit and SW.MoneyShort(e.unit) or "|cff8a8a8ano price|r",
                    0.7, 0.7, 0.7, 1, 1, 1)
                tt:AddLine("Source: " .. src, 0.6, 0.6, 0.6)
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", 6, y)
            r:SetPoint("RIGHT", c, "RIGHT", -2, 0)
            r:Show()
            y = y - 21
            if e.unit then total = total + e.need * e.unit end
            if NoPrice(e.priceSource) then partial = true end
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
    -- How much of the bill we cannot see matters more the longer the route is: on a full 1-350 plan
    -- "at least 40g" can be a tenth of the truth, and the count is the only honest way to say so.
    local unpricedItems, allItems = 0, 0
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.order) do
            allItems = allItems + 1
            if not e.unit then unpricedItems = unpricedItems + 1 end
        end
    end
    f.total:SetText(("Total: %s%s"):format(Cost(total, partial),
        partial and ("\n|cff8a8a8a%d of the %d materials have no price. %s|r"):format(
            unpricedItems, allItems, NoPriceNote()) or ""))
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
            m.sub:SetText(("%d to go  |cff8a8a8a%d > %d|r%s"):format(cur.left, cur.rank, s.to,
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
        if cur.known and SW.Prof.IsOpen(prof) and not (tool and tool.buy)
            and SetupCraftButton(m.craft, cur, prof) then
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
    if minimal then win.priceNote:Hide() end        -- shown again by UpdatePriceNote, if it has something to say
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

-- The strip that says there are no auction prices yet; the body moves down under it.
local function UpdatePriceNote()
    local note, status = win.priceNote, SW.Prices.Status()
    local text
    if SW.dataLost then
        -- worth saying before anything about prices: it explains every empty number on the page
        text = "|cffffd100Your saved Skillwright data didn't load|r - prices, trainer skills and the recipe "
            .. "you were following all start empty this session. That is a WoW: Forever bug, not something "
            .. "you did. Skillwright learns it again as you play."
    end
    -- Cheapest as far as the prices reach: the one case where the strip is not about missing prices
    -- but about where the plan changes its mind.
    local route = win.prof and Plan.RouteIfReady(win.prof)
    local pricedTo = route and route.pricedTo
    if not text and SW.Settings().mode == "cheap" and route and pricedTo
       and pricedTo > route.from and pricedTo < route.to then
        text = ("|cffffd100Cheapest to %d.|r Above that nothing on the route has a price, so the rest of "
            .. "it is the |cffffd100shortest|r one - fewest crafts, whatever they cost."):format(pricedTo)
    end
    if not text then
    if win.view ~= "settings" and (status == "none" or status == "stale") then
        local atAH = SW.Prices.CanScan()
        if status == "stale" then
            text = ("|cffffd100Auction prices are out of date|r (scanned %s), so the gold numbers may be wrong. %s")
                :format(SW.Prices.Ago(SW.DB().ahScanned), atAH and "Press |cffffd100Scan prices|r below."
                    or "Scan again at the auction house.")
        else
            text = "|cffffd100No auction prices yet|r - so this is the |cffffd100shortest route|r: the fewest "
                .. "crafts, whatever the materials cost. Vendor prices are used where we know them, and "
                .. "nothing else is guessed. "
                .. (atAH and "Press |cffffd100Scan prices|r below to plan for gold instead."
                    or "Scan at the auction house (or install Auctionator or TSM) to plan for gold.")
        end
    end
    end
    -- Where the body starts is part of this decision, so it is made on every refresh, whoever else
    -- may have touched the strip. Re-measuring the wrapped text is the expensive half, and only that
    -- is skipped when the words have not changed.
    local changed = text ~= note.shownText
    note.shownText = text
    win.body:ClearAllPoints()
    win.body:SetPoint("BOTTOMRIGHT", -10, 34)
    if text then
        if changed then
            note.text:SetText(text)
            -- WIDTH FIRST, THEN MEASURE. A FontString reports its UNWRAPPED height until something
            -- has told it how wide it is, so this used to draw the strip one line tall, then
            -- measure again a frame later and grow it - and the whole panel below jumped down.
            -- That is what read as "it loads and then shows properly". The card's own place()
            -- helper has done it in this order for months; this never learned.
            note.text:SetWidth(win:GetWidth() - 40)
            note:SetHeight(math.ceil(note.text:GetStringHeight()) + 10)
        end
        note:Show()
        win.body:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -6)
    else
        note:Hide()
        win.body:SetPoint("TOPLEFT", 12, -90)
    end
end

local function Refresh()
    if not win or not win:IsShown() then return end
    -- the drawing follows whatever the guide is about, including a profession it cannot plan
    SW.SetCardArt(win.noGuideFor or win.prof)
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
    -- Cheapest needs prices: without them both buttons plan the same shortest route, and saying so beats
    -- letting the player think a choice is being made. There are two kinds of "no prices", and they are
    -- not the same offer: a scan fixes the first, and nothing fixes the second until somebody lists the
    -- materials for sale.
    local unpriced = win.prof and Plan.PricesUnknown(win.prof)
    local scanWouldHelp = SW.Prices.Status() == "none" or SW.Prices.Status() == "stale"
    local reach, reachKnown = nil, true
    if win.prof then reach, reachKnown = Plan.CheapReach(win.prof) end
    -- Only worth solving the other route to label a button when the label would otherwise be bad news:
    -- if the page is not about to call Cheapest unavailable, there is nothing to check.
    -- ...but not while the page is still being drawn. This is a second full solve, and asking for
    -- it at the moment the window opens is a noticeable stall for a button label. It can wait.
    if unpriced and not reachKnown then
        local prof = win.prof
        SW.Debounce("cheapLabel", 1.5, function()
            if win and win:IsShown() and win.prof == prof and not Plan.Solving(prof) then
                Plan.Route(prof, "cheap")
            end
        end)
    end
    for _, b in ipairs(win.mode.buttons or {}) do
        if b.value == "cheap" then
            if not reachKnown then
                -- no cheap route yet, so no claim: never call a mode unavailable on a guess
                b.fs:SetText("Cheapest")
                b.altTooltip = nil
            elseif reach then
                -- it works, and it says how far: "No prices" over a route that really was costed to
                -- 150 is how a player ends up on the dearer plan believing it is the only one.
                b.fs:SetText("Cheapest")
                b.altTooltip = ("Planned on price up to %d. Above that nothing on the route has a price, "
                    .. "so from there it takes the shortest way."):format(reach)
            elseif not unpriced then
                b.fs:SetText("Cheapest")
                b.altTooltip = nil
            elseif scanWouldHelp then
                b.fs:SetText("Scan to see")
                b.altTooltip = "No auction prices yet, so there is nothing to rank by gold. Scan at the "
                    .. "auction house and this becomes a real choice."
            else
                b.fs:SetText("No prices")
                b.altTooltip = "Some materials on this route are not sold by vendors and nobody had them "
                    .. "listed at the last scan, so the gold cost of the route is not known."
            end
        end
    end
    -- The mode you are on is always marked, even when the other one cannot be planned. This used to
    -- clear the selection outright whenever anything on the route had no price, so neither button
    -- was marked and the window never said which mode it was showing you. Cheapest says so in its
    -- own label ("Scan to see", "No prices") - that is not a reason to unmark Fastest.
    win.mode:Select(SW.Settings().mode)
    UpdatePriceNote()
    local v = views[win.view]
    if v and v.frame then v.refresh(v.frame) end
    -- Footer: where prices come from, and the scan button at the auction house.
    local src = SW.Prices.SourceText()
    win.status:SetText(src and ("|cff8a8a8aPrices:|r " .. src)
        or "|cff8a8a8aPrices: vendors only - nothing else is priced until you scan|r")
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
                -- inside the frame, not on it. The panel's lines and corners are drawn on the
                -- body's own bounds, so the content has to stand off them - including the
                -- scrollbar, whose arrows were sitting on the top and bottom edges.
                v.frame:SetPoint("TOPLEFT", 10, -10)
                v.frame:SetPoint("BOTTOMRIGHT", -10, 10)
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

-- WE ARE NOT THE ONLY ADDON ATTACHED TO THIS WINDOW. Profession Master, TradeSkillMaster, a skin
-- that moves ProfessionsFrame - any of them can already be sitting where we want to be, and a guide
-- printed over someone else's panel is worse than a guide the player has to move once.
--
-- The first attempt at this asked "is any shown frame in this rectangle", walking UIParent's
-- children. It does not work, and the way it failed is the lesson: Blizzard's own containers -
-- BottomManagedFrameContainer, the tooltip frames, the Edit Mode dialogs - are shown frames with
-- real coordinates, so nearly every spot reads as occupied. The guide then found both sides taken,
-- stopped attaching and appeared halfway across the screen. A test cannot catch that, because the
-- harness has no Blizzard UI in it.
--
-- So the question is narrower and answerable: is something ANCHORED TO THIS WINDOW already there.
-- An addon that puts a panel beside the profession window anchors it to the profession window;
-- that is what "another addon changed this window" looks like from the outside. A frame that
-- merely happens to be on screen is not our business and never was.
--
-- Everything here is wrapped, because reading a frame can raise. In Forever some frames are
-- forbidden to addon code and even IsShown() on one throws - which it did, from this function.
local hostBtn          -- our own button on the profession window: never something to dodge
local function Try(fn, a, b)
    local ok, v1, v2, v3, v4 = pcall(fn, a, b)
    if ok then return v1, v2, v3, v4 end
end

local function Rect(f)
    if not f then return end
    if Try(f.IsForbidden, f) then return end
    if not f.GetRight then return end
    local l, r = Try(f.GetLeft, f), Try(f.GetRight, f)
    local b, t = Try(f.GetBottom, f), Try(f.GetTop, f)
    if not (l and r and b and t) then return end
    return l, r, b, t
end

-- Frames that have made themselves part of this window: its own children, and anything at the top
-- level that anchors to it.
local function AttachedFrames(host)
    local out = {}
    local ok, kids = pcall(function() return { host:GetChildren() } end)
    if ok then
        for _, f in ipairs(kids) do out[#out + 1] = f end
    end
    for _, f in ipairs({ UIParent:GetChildren() }) do
        for i = 1, (Try(f.GetNumPoints, f) or 0) do
            local _, rel = Try(f.GetPoint, f, i)
            if rel == host then
                out[#out + 1] = f
                break
            end
        end
    end
    return out
end

local function Occupied(x1, x2, y1, y2, host)
    local hl, hr, hb, ht = Rect(host)
    local hw = (hl and hr) and (hr - hl) or 0
    local hh = (hb and ht) and (ht - hb) or 0
    for _, f in ipairs(AttachedFrames(host)) do
        if f ~= win and f ~= host and f ~= hostBtn and Try(f.IsShown, f) and (Try(f.GetAlpha, f) or 1) > 0.1 then
            local l, r, b, t = Rect(f)
            -- The window's own backdrop and nine-slice fill it edge to edge and mean nothing here.
            -- Size alone does not identify them - an addon's panel beside the window can be just as
            -- big - so what marks them out is that they sit INSIDE the window and cover most of it.
            local inside = l and l >= hl - 2 and r <= hr + 2 and b >= hb - 2 and t <= ht + 2
            local big = inside and hw > 0 and (r - l) > hw * 0.6 and (t - b) > hh * 0.6
            if l and not big and (r - l) > 8 and (t - b) > 8 then
                if l < x2 and r > x1 and b < y2 and t > y1 then return true, f end
            end
        end
    end
    return false
end

-- Put the guide against one side of the host, right first because that is where it has always been
-- and where the player expects it. Returns false when neither side is free.
local function AttachBeside(host)
    local l, r, b, t = Rect(host)
    if not l then
        win:SetPoint("TOPLEFT", host, "TOPRIGHT", HostOverhang(host) + 4, 0)
        return true
    end
    local w, h = win:GetWidth(), win:GetHeight()
    local pad = HostOverhang(host) + 4
    -- right, then left. A side that runs off the screen is not a side.
    if r + pad + w <= UIParent:GetWidth() and not Occupied(r + pad, r + pad + w, t - h, t, host) then
        win:SetPoint("TOPLEFT", host, "TOPRIGHT", pad, 0)
        return true
    end
    if l - 4 - w >= 0 and not Occupied(l - 4 - w, l - 4, t - h, t, host) then
        win:SetPoint("TOPRIGHT", host, "TOPLEFT", -4, 0)
        return true
    end
    return false
end

-- Anchor: beside the open profession window when attached, else where the player left it.
function SW.Anchor()
    if not win then return end
    win:ClearAllPoints()
    local host = ProfessionsFrame
    if win.attached and SW.Settings().attach and host and host:IsShown() then
        if AttachBeside(host) then
            -- the tabs are laid out a moment after the window shows; measure again then
            if not win.reanchoring then
                win.reanchoring = true
                C_Timer.After(0.1, function()
                    win.reanchoring = false
                    if win.attached and host:IsShown() then
                        win:ClearAllPoints()
                        if not AttachBeside(host) then win.attached = false; SW.Anchor() end
                    end
                end)
            end
            return
        end
        -- both sides are taken. Stop pretending to be attached rather than land on someone's panel.
        win.attached = false
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
    close:SetScript("OnClick", function() SW.CloseWindow() end)

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
        { value = "fast", label = "Fastest", tooltip = "The fewest crafts. It reads no prices at all." },
    }, 136, function(v, btn)
        -- "Cheapest" with nothing to rank is a promise we cannot keep: offer the scan instead of a fake
        -- route. But only when the CHEAP route really cannot be costed - not when the fast one on screen
        -- happens to mention an unpriced material at skill 280.
        local reach, reachKnown = nil, true
        if v == "cheap" and win.prof then reach, reachKnown = Plan.CheapReach(win.prof) end
        if v == "cheap" and win.prof and reachKnown and not reach then
            if SW.Prices.CanScan() then
                SW.Prices.StartScan()
            else
                SW.msg("open the auction house and press |cffffd100Scan prices|r - without prices the guide "
                    .. "plans the shortest route instead.")
            end
            return
        end
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
    -- well in from the panel's left corner, so they belong to the frame rather than starting at
    -- the very edge of it
    win.tabs:SetPoint("TOPLEFT", 26, -58)
    local divider = win:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 14, -91)
    divider:SetPoint("TOPRIGHT", -16, -91)

    win.body = CreateFrame("Frame", nil, win)
    -- The tabs are 33 tall from y = -58, so their baseline is -91 and the panel starts one pixel
    -- under it. Overlapping them into the panel was tried and looks worse: common-insideframe is a
    -- single drawn texture with its own top edge, so a tab on top of it covers part of that line
    -- and leaves a break rather than joining. A nine-slice could open a seam where the tab sits;
    -- one stretched texture cannot.
    win.body:SetPoint("TOPLEFT", 12, -90)
    win.body:SetPoint("BOTTOMRIGHT", -10, 34)

    -- The profession window's own panel art, so the guide reads as part of it rather than as
    -- a box parked next to it. Both names come from Blizzard's XML for this build, not from
    -- memory: Profession-Background-Template2 is the illustration behind the crafting page
    -- (Blizzard_ProfessionsFrame.xml) and common-insideframe is the inner panel with the thin
    -- lines and the corner pieces (Blizzard_ProfessionsRecipeSchematicForm.xml).
    --
    -- Checked before use. An atlas that is not in this client fails silently and leaves an
    -- untextured rectangle, which is how the selected mode button ended up invisible.
    local function atlas(tex, name)
        if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(name) then
            SW.dbg("no atlas %s in this client", name)
            tex:Hide()
            return false
        end
        tex:SetAtlas(name)
        return true
    end

    -- The drawing sits behind everything and is drawn faint: it is a watermark, not a picture,
    -- and the words on top of it have to stay the easiest thing to read. It lives on the WINDOW
    -- rather than on the body, so nothing inside the body can cover it, and changes with the
    -- profession in SetCardArt below.
    win.art = win:CreateTexture(nil, "BORDER", nil, -8)
    win.art:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, 0)
    win.art:SetPoint("BOTTOMRIGHT", win.body, "BOTTOMRIGHT", 0, 0)
    win.art:SetAlpha(0.5)
    win.atlasOK = atlas

    -- THE PANEL, nine-sliced. common-insideframe is one texture stretched to fit: its corner art
    -- distorts at any size but the one it was drawn for, and its top edge is a single unbroken
    -- line, which is why a tab laid over it leaves a break rather than merging into it.
    -- InsetFrameTemplate is the client's own nine-slice - corners at their true size, edges
    -- stretched one way only - so it is right at any size and its top edge is drawn in pieces.
    local ok, inset = pcall(CreateFrame, "Frame", nil, win.body, "InsetFrameTemplate")
    if ok and inset then
        inset:SetPoint("TOPLEFT", 0, 0)
        inset:SetPoint("BOTTOMRIGHT", 0, 0)
        inset:SetFrameLevel(math.max(0, win.body:GetFrameLevel() - 1))
        -- The template brings an opaque fill with it, and it was sitting on the profession drawing.
        -- We want its EDGES - the nine-slice - and nothing else.
        for _, fill in ipairs({ inset.Bg, inset.bg, inset.Center, inset.Background }) do
            if fill and fill.Hide then fill:Hide() end
        end
        win.inset = inset
    else
        -- no template in this client: keep the texture rather than hand-draw a copy of Blizzard's
        -- art, which would be wrong the first time they change it
        SW.dbg("no InsetFrameTemplate - falling back to the flat border")
        win.inset = win.body:CreateTexture(nil, "BORDER")
        win.inset:SetPoint("TOPLEFT", 0, 0)
        win.inset:SetPoint("BOTTOMRIGHT", 0, 0)
        atlas(win.inset, "common-insideframe")
    end

    -- "No auction prices yet": a strip above the tabs' content while there is nothing to cost a route with
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
        GameTooltip:AddLine(src and ("From: " .. src)
            or "No auction prices yet. Vendor prices are used where we know them; nothing else is priced.",
            0.85, 0.85, 0.85, true)
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
    -- Not win.priceNote: UpdatePriceNote decides when that is on screen, and two owners meant a
    -- hidden strip coming back with stale text under the page's own content.
    win.fullOnly = { pb, win.mode, divider, win.body, win.scan, win.status, win.statusHit }
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
    -- This used to decide, from inside Hide(), whether the PLAYER had closed the guide - by
    -- assuming any hide the addon had not wrapped was theirs. It is not knowable here, and the
    -- case it got wrong is the common one: Escape over the profession window runs LibForever's
    -- escape stand-in first, and that hides the frontmost of our windows before TRADE_SKILL_CLOSE
    -- arrives. So Escape always counted as closing the guide for good. The decision is a saved
    -- setting now, written by the two controls that mean it.
    win:HookScript("OnHide", function()
        win.dashSkip = false
        win.autoShown = false
        SW.UpdateHostButton()
    end)
    win:Hide()
end

-- The drawing the profession window puts behind its page, one per profession. The names are
-- from the client's own atlas table, not from a spelling in Blizzard's XML: the XML says
-- "Profession-Background-Template2" and what exists is "profession-background-template2-c60".
local CARD_ART = {
    [164] = "blacksmithing", [165] = "leatherworking", [171] = "alchemy",   [197] = "tailoring",
    [202] = "engineering",   [333] = "enchanting",     [185] = "cooking",   [129] = "firstaid",
    [186] = "mining",        [182] = "herbalism",      [393] = "skinning",  [356] = "fishing",
}

-- What the profession window is drawing behind its own page, right now. This beats any name
-- we can write down: it is right for this profession, this build and this client because it
-- IS what the client chose. Wrapped, because reading another addon's frame can raise.
local function LiveCardArt()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local bg = page and page.SchematicForm and page.SchematicForm.Background
    if not (bg and bg.GetAtlas) then return end
    local ok, atlasName = pcall(bg.GetAtlas, bg)
    -- a string or nothing: GetAtlas returns nil for a plain texture, and anything else is not a
    -- name we can hand to SetAtlas
    if ok and type(atlasName) == "string" and atlasName ~= "" then return atlasName end
end

function SW.SetCardArt(prof)
    if not (win and win.art) then return end
    -- the live one when the window is open; the table when the guide was opened on its own
    local name = LiveCardArt()
    if not name then
        local suffix = CARD_ART[prof]
        name = suffix and ("profession-background-card-%s-c60"):format(suffix)
    end
    if not name then
        win.art:Hide()
        return
    end
    if win.atlasOK and win.atlasOK(win.art, name) then win.art:Show() end
end

-- Show the guide for a profession (nil = the best guess) on a tab (nil = keep the current one).
function SW.ShowWindow(prof, view, attached)
    Build()
    SW.Settings().guideClosed = false      -- they asked for it back
    -- A profession we carry no recipes for has no plan to show, and asking for one anyway walks
    -- into Plan with nil data and throws. Callers should not have to know that.
    if prof and not SW.PROFESSIONS[prof] then prof = nil end
    -- "Skillwright has no guide for Mining" is about the profession window that was open, not about
    -- the guide. Asking for a profession by name answers it, and leaving it set meant the card kept
    -- apologising for a window that had long since closed.
    if prof then win.noGuideFor = nil end
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

-- The player closing the guide, as opposed to it going away with the window it sits beside.
function SW.CloseWindow()
    SW.Settings().guideClosed = true
    if win then win:Hide() end
    SW.UpdateHostButton()
end

function SW.ToggleWindow()
    if win and win:IsShown() then SW.CloseWindow() else SW.ShowWindow() end
end

function SW.WindowShown() return win and win:IsShown() end

-- THE WAY BACK. Closing the guide sticks, so there has to be somewhere obvious to get it again,
-- and the profession window is where the player already is.
--
-- It is one of that window's own side tabs, built from the same template Blizzard builds the
-- profession tabs from (Blizzard_ProfessionsFrame.xml: ProfessionsFrameRightTabTemplateWrapper,
-- each tab anchored TOPLEFT to the one above it, 2 pixels down). So it is not a lookalike - it is
-- the same widget with our icon in it, and it stays right whatever the client does to that art.
--
-- The first attempt was a button on the title bar. It was the wrong idea twice over: it sat where
-- other addons like to put theirs, and it looked bolted on. This column already means "another
-- page of this window", which is what the guide is.
local hostTab
local function BuildHostTab()
    local host = ProfessionsFrame
    if hostTab or not host then return end
    -- The template comes with Blizzard_Professions, which is loaded on demand. If it is not there,
    -- we simply have no tab: the minimap button and /skw are the way in, and a hand-drawn
    -- imitation would be worse than nothing.
    -- Blizzard declares these tabs as <Frame> in XML and then calls SetChecked on them, so the
    -- type CreateFrame wants is not something the XML can be read for. Try each, and take the
    -- first that comes back with the icon the template is supposed to provide.
    for _, kind in ipairs({ "CheckButton", "Button", "Frame" }) do
        local ok, f = pcall(CreateFrame, kind, "SkillwrightHostTab", host,
            "ProfessionsFrameRightTabTemplateWrapper")
        if ok and f and f.Icon then
            hostTab = f
            SW.dbg("host tab built from the profession template as a %s", kind)
            break
        end
        if ok and f then f:Hide() end
    end
    if not hostTab then
        -- No template, so no lookalike: a hand-drawn copy of Blizzard's art would be wrong the
        -- first time they change it. A plain square in the same column is honest and still gets
        -- the player back to the guide.
        SW.dbg("no profession tab template - falling back to a plain button")
        hostTab = CreateFrame("Button", "SkillwrightHostTab", host)
        hostTab:SetSize(32, 32)
        hostTab.Icon = hostTab:CreateTexture(nil, "ARTWORK")
        hostTab.Icon:SetPoint("TOPLEFT", 3, -3)
        hostTab.Icon:SetPoint("BOTTOMRIGHT", -3, 3)
        local edge = hostTab:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(0, 0, 0, 0.6)
        local hl = hostTab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.2)
        hostTab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tooltipText or "Skillwright", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        hostTab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    _G.SkillwrightHostButton = hostTab      -- the name the tests and /skw know it by
    hostTab.Icon:SetTexture("Interface\\AddOns\\Skillwright\\Media\\minimap")
    hostTab.tooltipText = "Skillwright"
    hostTab:SetScript("OnClick", function()
        if SW.WindowShown() then
            SW.CloseWindow()    -- pressing the tab to close is the player deciding, and it sticks
            return
        end
        local open = SW.Prof.OpenLine()
        if open and SW.PROFESSIONS[open] then
            SW.ShowWindow(open, nil, true)
        else
            -- Mining, Herbalism, Fishing. Open on a profession we can actually guide - the one they
            -- were last on, or their first - rather than on a page that only says no. If they have
            -- none at all there is nothing to fall back to, and then the card says so plainly.
            local fallback = SW.DefaultProf()
            SW.ShowWindow(fallback, nil, true)
            if not (fallback and SW.PROFESSIONS[fallback]) then
                win.noGuideFor = open
                SW.RefreshWindow()
            end
        end
        win.autoShown = false   -- they asked for it by hand; it does not vanish with the host
        SW.UpdateHostButton()
    end)
end

-- Place it under the last profession tab, and keep it there when that number changes.
function SW.UpdateHostButton()
    local host = ProfessionsFrame
    if not host or not host:IsShown() then
        if hostTab then hostTab:Hide() end
        return
    end
    -- The tab is part of the column, so it stays in it. Hiding it for Mining or Fishing made the
    -- column change length as the player clicked between professions, and a tab that comes and goes
    -- does not look like it belongs there. What it does when pressed is where honesty lives, not
    -- whether it is there at all.
    BuildHostTab()
    if not hostTab then return end

    -- the last tab the client is actually showing; it hides the unused ones at the end
    local above = host.ProfessionsOverviewTab
    for _, tab in ipairs(host.rightProfessionTabs or {}) do
        if tab ~= hostTab and tab:IsShown() then above = tab end
    end
    hostTab:ClearAllPoints()
    if above then
        hostTab:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2)
    else
        hostTab:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -60)
    end
    -- lit while the guide is up, exactly as the tab of the page you are on
    if hostTab.SetChecked then hostTab:SetChecked(SW.WindowShown() and true or false) end
    -- the template draws its own tooltip from this, so it has to say what pressing it will do
    local open = SW.Prof.OpenLine()
    if open and not SW.PROFESSIONS[open] then
        hostTab.tooltipText = "Skillwright - no route for " .. (SW.ProfName(open) or "this one")
    else
        hostTab.tooltipText = "Skillwright"
    end
    hostTab:Show()
end

-- A hide the ADDON decided on: the profession window closed, or opened onto something we have no
-- guide for. It must not read as the player dismissing the guide, or the guide never comes back.
local function AutoHide()
    win.autoHiding = true
    win:Hide()
    win.autoHiding = false
    win.autoShown = false
end

-- Opening a profession window opens (and attaches) its guide; closing it closes a guide it opened.
local function OnProfessionOpen(id)
    -- A profession we have no guide for (Mining's smelting, Herbalism, Fishing): the guide has nothing
    -- to say about it, so it must not sit beside that window showing a different profession's route.
    if not SW.PROFESSIONS[id] then
        if win and win:IsShown() then
            if win.autoShown then
                AutoHide()                 -- it came with a profession window; it goes with this one
            else
                -- The player opened it, so it stays - beside the window, where it was. It used to
                -- detach here, which sent it to its free-floating position the moment you clicked
                -- Fishing: from the player's side the guide simply jumped across the screen. The
                -- window is still open and the guide still belongs next to it; all that changed is
                -- that it has nothing to plan, and the card says so.
                win.noGuideFor = id
                SW.Anchor()
                SW.RefreshWindow()
            end
        end
        return
    end
    -- the window may not exist yet: this event is what opens it the first time
    if win then win.noGuideFor = nil end
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
    if SW.Settings().autoOpen and not SW.Settings().guideClosed then
        SW.ShowWindow(id, nil, true)
        win.autoShown = true
    end
end

-- Blizzard rebuilds its side tabs when the professions change, and ours sits under the last one.
local hookedTabs
local function HookTabRefresh()
    if hookedTabs or not (ProfessionsFrame and ProfessionsFrame.RefreshRightTabs) then return end
    hookedTabs = true
    hooksecurefunc(ProfessionsFrame, "RefreshRightTabs", function() SW.UpdateHostButton() end)
end

SW.Listen("PROFESSION_OPEN", function(id)
    OnProfessionOpen(id)
    HookTabRefresh()
    -- Whatever that decided, the profession window is open and needs its button. This used to sit
    -- at the end of the handler, below two returns - including the one for "the guide is already
    -- showing", which is the path nearly every profession window takes. The button was therefore
    -- missing exactly when the player was looking at it.
    SW.UpdateHostButton()
    -- the tabs and the title bar are laid out a moment later, and the button dodges them
    C_Timer.After(0.1, SW.UpdateHostButton)
end)
SW.Listen("PROFESSION_CLOSED", function()
    if not win or not win:IsShown() then return end
    win.noGuideFor = nil
    -- It goes with the window, whoever opened it. It used to stay and detach when the PLAYER had
    -- opened it, which put a lone guide in the middle of the screen the moment they pressed Escape
    -- - it had not reopened, it had jumped, but there is no way to tell those apart by looking.
    -- That rule dates from before there was a tab to get the guide back with.
    --
    -- This is the addon's doing, not the player's, so it does NOT count as dismissing the guide:
    -- the next profession window brings it back. Only the X, Escape or the tab keep it away.
    AutoHide()
end)
-- The profession window can be moved by the UI panel manager; re-anchor when it is (re)shown.
SW.Listen("LOGIN", function()
    hooksecurefunc("ShowUIPanel", function(frame)
        if frame ~= ProfessionsFrame then return end
        if win and win.attached then SW.Anchor() end
        SW.UpdateHostButton()
    end)
end)

-- DATA_LOST arrives a second or two after login: a guide opened before then has to be told, or it keeps
-- looking like a fresh install until something else redraws it.
for _, ev in ipairs({ "PLAN_CHANGED", "RANKS_CHANGED", "MERCHANT_CHANGED", "TRAINER_CHANGED", "SCAN_STATE", "RECIPES_CHANGED",
                     "PROFESSION_UPDATED", "PRICES_CHANGED", "DATA_LOST" }) do
    SW.Listen(ev, SW.RefreshWindow)
end
SW.On("BAG_UPDATE_DELAYED", SW.RefreshWindow)
-- names arrive one item at a time: coalesce the redraws, but don't let a stream of them postpone it
SW.On("GET_ITEM_INFO_RECEIVED", function() SW.Coalesce("itemInfo", 0.3, Refresh) end)
SW.On("AUCTION_HOUSE_SHOW", SW.RefreshWindow)
SW.On("AUCTION_HOUSE_CLOSED", SW.RefreshWindow)
SW.On("TRADE_SKILL_LIST_UPDATE", SW.RefreshWindow)
