-- Skillwright - the settings, built the same way into the guide's Settings tab and into the page under
-- Blizzard's Options > AddOns, so the two can't drift apart. Minimap and launcher buttons live on the shared
-- YippYapp page (the link block at the bottom).
--
-- Every element is anchored below the one before it, so wrapped text of any length leaves neither gaps nor
-- overlaps, at the guide tab's width as well as the wider Options page.
local ADDON, SW = ...
local U = SW.UI
local Plan = SW.Plan
local Page = {}
SW.SettingsPage = Page

local GREY = "|cff9a9a9a"

function Page.Build(f)
    local sf = U.Scroll(f)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -22, 0)
    local p = sf.child
    f.sf, f.p = sf, p
    f.checks = {}

    local last, lastX = nil, 0
    -- Put `w` under the previous element at indent `x`; `stretch` makes text use the full width.
    local function place(w, x, gap, stretch)
        w:ClearAllPoints()
        if last then
            w:SetPoint("TOPLEFT", last, "BOTTOMLEFT", x - lastX, -(gap or 0))
        else
            w:SetPoint("TOPLEFT", p, "TOPLEFT", x, -(gap or 0))
        end
        if stretch then w:SetPoint("RIGHT", p, "RIGHT", -8, 0) end
        last, lastX = w, x
        return w
    end
    local function text(str, template, x, gap)
        local fs = U.Text(p, template or "GameFontHighlightSmall", "LEFT", true)
        fs:SetText(str)
        return place(fs, x or 4, gap, true)
    end
    local function heading(str)
        return place(U.Heading(p, str), 2, 18)
    end
    -- A checkbox with its explanation in grey underneath. key = a Settings() field.
    local function checkbox(label, key, explain, after)
        local cb = U.Checkbox(p, label)
        cb.key = key
        cb:SetScript("OnClick", function(self)
            SW.Settings()[key] = self:GetChecked() and true or false
            if after then after() end
        end)
        f.checks[#f.checks + 1] = cb
        place(cb, 4, 8)
        if explain then text(GREY .. explain .. "|r", "GameFontHighlightSmall", 32, 0) end
    end

    -- Title and what it is
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetJustifyH("LEFT")
    title:SetText(("Skillwright %sv%s|r"):format(GREY, SW.VERSION))
    place(title, 4, 6)
    text("The cheapest or fastest route to max profession skill, planned from the game's own recipe data and "
        .. "your prices.", "GameFontHighlight", 4, 4)

    -- Route: what the plan looks like
    heading("Route")
    local modeRow = CreateFrame("Frame", nil, p)
    modeRow:SetHeight(24)
    place(modeRow, 4, 8, true)
    local modeLabel = U.Text(modeRow, "GameFontHighlight")
    modeLabel:SetPoint("LEFT", 0, 0)
    modeLabel:SetText("Plan for")
    f.mode = U.Segmented(modeRow, {
        { value = "cheap", label = "Cheapest", tooltip = "The least gold per skill point, from market prices." },
        { value = "fast", label = "Fastest", tooltip = "The fewest crafts per skill point." },
    }, 180, function(v) SW.SetMode(v) end)
    f.mode:SetPoint("LEFT", 70, 0)
    checkbox("Prefer materials from vendors", "preferVendor",
        "Recipes whose materials you can simply buy come first, even if that means a few more crafts.",
        function() Plan.Invalidate() end)
    checkbox("Use materials I already have", "useOwned",
        "Steps you can already make from what's in your bags or bank come first. Valuable (over 1g each) or "
        .. "rare materials are never counted as free.", function() Plan.Invalidate() end)
    -- Specialization: only Leatherworking and Engineering have one, so the profession it belongs to is
    -- always named (and picked here when the character has both).
    local spec = CreateFrame("Frame", nil, p)
    spec:SetHeight(1)
    place(spec, 4, 8, true)
    f.specBox = spec
    f.specLabel = U.Text(spec, "GameFontHighlight")
    f.specLabel:SetPoint("TOPLEFT", 0, 0)
    f.specProfBtn = CreateFrame("Button", nil, spec)
    f.specProfBtn:SetHeight(20)
    f.specProfBtn:SetPoint("LEFT", f.specLabel, "RIGHT", 6, 0)
    f.specProfText = U.Text(f.specProfBtn, "GameFontNormal")
    f.specProfText:SetPoint("LEFT", 0, 0)
    f.specProfArrow = f.specProfBtn:CreateTexture(nil, "ARTWORK")
    f.specProfArrow:SetAtlas("common-dropdown-a-button")
    f.specProfArrow:SetSize(16, 16)
    f.specProfArrow:SetPoint("LEFT", f.specProfText, "RIGHT", 2, -1)
    local hl = f.specProfBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Options_List_Hover")

    -- The guide window
    heading("Guide window")
    checkbox("Open with the profession window", "autoOpen",
        "The guide opens (and closes) with your profession window.")
    checkbox("Attach to the profession window", "attach",
        "It sits beside the profession window and moves with it. Drag it away to place it anywhere.",
        function() SW.Anchor() end)
    checkbox("Minimal window", "minimal",
        "Just the recipe to make, its materials and the Craft button. The - / + button by the close button "
        .. "switches too.", function() SW.SetMinimal(SW.Settings().minimal) end)

    -- Trainers
    heading("Trainers")
    checkbox("Read everything a trainer teaches", "deepTrainerScan",
        "Once per trainer, Skillwright also reads what you can't learn yet, to get the real skill each "
        .. "recipe needs. The trainer's list blinks once while it does. Your own filters are put back.")

    -- Enchanting
    heading("Enchanting")
    checkbox("Say Yes to \"replace enchant\" automatically", "autoReplaceEnchant",
        "When the Craft button enchants an item that already has an enchant. Never for gear you are wearing, "
        .. "and never for anything you enchant yourself.")

    -- How it works, and what it can't know yet
    heading("Good to know")
    text("|cffffd100Prices|r come from Auctionator or TSM when installed, else from your own scan: open the "
        .. "auction house and press |cffffd100Scan prices|r. Without any, prices are estimates (marked est.).",
        nil, 4, 6)
    text("|cffffd100Trainer recipes:|r the game doesn't say what skill one needs until you see it at a trainer. "
        .. "Until then the plan estimates it (marked estimated).", nil, 4, 6)
    text("|cffffd100Recipe drops and vendors|r aren't in the game data yet, so the plan uses those recipes only "
        .. "once you know them - some routes stop before 300. Quest and specialization recipes are listed by "
        .. "hand. Built from WoW: Forever beta data.", nil, 4, 6)

    -- YippYapp: the link to the shared page (minimap and launcher buttons), the welcome page, the footer
    local LIB = SW.LIB
    if LIB.LauncherOptions then place(LIB.LauncherOptions(p, "Skillwright"), 4, 18) end
    -- No welcome button: the YippYapp window this page lives in has its own way there.
    text(GREY .. "|cffffd100/skw|r opens the guide, |cffffd100/skw config|r these settings.\n"
        .. "Part of YippYapp - addons for WoW: Forever that work even better together.|r", nil, 4, 12)
    f.lastWidget = last
end

-- Fit the scroll child to what was laid out (heights of wrapped text are only known once shown).
local function FitHeight(f)
    local top, bottom = f.p:GetTop(), f.lastWidget and f.lastWidget:GetBottom()
    if top and bottom then f.p:SetHeight(top - bottom + 16) else f.p:SetHeight(900) end
end

function Page.Refresh(f, prof)
    for _, cb in ipairs(f.checks) do cb:SetChecked(SW.Settings()[cb.key] and true or false) end
    f.mode:Select(SW.Settings().mode)

    -- Which profession the specialization belongs to: the one the guide last showed when it has one,
    -- else the character's first. Never guessed silently - the name is always on screen.
    local owned = {}
    for _, id in ipairs(SW.Prof.Mine()) do
        if SW.PROFESSIONS[id] and SW.PROFESSIONS[id].specs then owned[#owned + 1] = id end
    end
    local wanted = prof or f.specProf or SW.DefaultProf()
    local specProf
    for _, id in ipairs(owned) do
        if id == wanted then specProf = id end
    end
    if not specProf and f.specProf then
        for _, id in ipairs(owned) do
            if id == f.specProf then specProf = id end
        end
    end
    specProf = specProf or owned[1]
    f.specProf = specProf
    prof = specProf
    local specs = prof and SW.PROFESSIONS[prof] and SW.PROFESSIONS[prof].specs
    if f.spec then f.spec:Hide() end
    if specs then
        f.specLabel:SetText("Specialization for")
        f.specLabel:Show()
        f.specProfText:SetText(SW.ProfName(prof))
        f.specProfBtn:SetWidth(f.specProfText:GetStringWidth() + (#owned > 1 and 22 or 4))
        f.specProfArrow:SetShown(#owned > 1)
        f.specProfBtn:SetShown(true)
        f.specProfBtn:SetScript("OnClick", (#owned > 1) and function(self)
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle("Specialization for")
                for _, id in ipairs(owned) do
                    root:CreateRadio(SW.ProfName(id), function() return f.specProf == id end, function()
                        f.specProf = id
                        Page.Refresh(f, id)
                    end)
                end
            end)
        end or nil)
        f.specProfBtn:SetEnabled(#owned > 1)
        f.specCtl = f.specCtl or {}
        local ctl = f.specCtl[prof]
        if not ctl then
            local items = { { value = "none", label = "None" } }
            for _, s in ipairs(specs) do items[#items + 1] = { value = s, label = s } end
            ctl = U.Segmented(f.specBox, items, math.min(80 * #items, 300), function(v)
                SW.CharProf(prof).spec = (v ~= "none") and v or nil
                Plan.Invalidate(prof)
            end)
            ctl:SetPoint("TOPLEFT", f.specLabel, "BOTTOMLEFT", 0, -4)
            f.specCtl[prof] = ctl
        end
        ctl:Select(Plan.Spec(prof) or "none")
        ctl:Show()
        f.spec = ctl
        f.specBox:SetHeight(44)
    else
        f.specLabel:Hide()
        f.specProfBtn:Hide()
        f.specBox:SetHeight(1)
    end
    FitHeight(f)
    C_Timer.After(0, function() FitHeight(f) end)
end
