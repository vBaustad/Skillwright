-- Skillwright - core: shared namespace, saved variables, and the data registration API.
-- Everything cross-file hangs off the SW table (the addon's second vararg).
local ADDON, SW = ...

SW.version = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "0.4.0"

-- Key Bindings UI labels (Esc -> Key Bindings -> Skillwright). The bindings themselves live in
-- Bindings.xml and call the SkillwrightToggle* globals defined in the UI files.
BINDING_HEADER_SKILLWRIGHT = "Skillwright"
BINDING_NAME_SKILLWRIGHT_DASHBOARD = "Toggle dashboard"
BINDING_NAME_SKILLWRIGHT_GUIDE = "Toggle guide window"

-- [professionName] = { { from, to, qty, recipe, vendorPattern?, mats={ {name, total, itemId}, ... } }, ... }
SW.PATHS = {}
function SW.RegisterPath(profession, steps) SW.PATHS[profession] = steps end

-- Gathering professions level by farming routes, not crafting. ROUTES[prof] = ordered
-- segments { from, to, faction?, zones={...}, note? }.
SW.ROUTES = {}
function SW.RegisterRoute(profession, segments) SW.ROUTES[profession] = segments end

-- True if Skillwright has any guide data (craft path or gathering route) for a profession.
function SW.HasGuide(profession) return SW.PATHS[profession] ~= nil or SW.ROUTES[profession] ~= nil end

-- Trainer rank tiers (Classic primary professions all gate at 75/150/225). Used to split
-- the Steps and Shopping views into "1-75 do this, 75-150 do this" sections.
SW.TIERS = { { 1, 75, "Apprentice" }, { 75, 150, "Journeyman" }, { 150, 225, "Expert" }, { 225, 300, "Artisan" } }

-- Mats you can simply buy from a profession supplier (threads, dyes, vials, flux, salt).
-- Used to split "farm this" from "just buy this" and to power the vendor buy calculation.
SW.VENDOR_MATS = {
    [2320] = true, [2321] = true, [4291] = true, [8343] = true, [14341] = true, -- threads
    [2604] = true, [2605] = true, [2871] = true, [4341] = true,                 -- dyes (gray, green, black, red)
    [6260] = true, [6261] = true,                                               -- dyes (blue, orange)
    [2324] = true,                                                              -- Bleach
    [3372] = true, [3371] = true, [8925] = true,                                -- vials (empty, leaded, crystal)
    [2880] = true,                                                             -- Weak Flux
    [2692] = true,                                                              -- salt
    [159]  = true,                                                              -- Refreshing Spring Water (cooking)
}
function SW.IsVendorMat(id) return (id and SW.VENDOR_MATS[id]) and true or false end

-- Recognised professions (used by the dashboard to detect what a character has).
SW.PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Leatherworking", "Mining", "Skinning", "Tailoring",
    "Cooking", "First Aid", "Fishing",
}
SW.PROF_ICON = {
    Alchemy = "Interface\\Icons\\Trade_Alchemy",
    Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
    Enchanting = "Interface\\Icons\\Trade_Engraving",
    Engineering = "Interface\\Icons\\Trade_Engineering",
    Herbalism = "Interface\\Icons\\Trade_Herbalism",
    Leatherworking = "Interface\\Icons\\Trade_LeatherWorking",
    Mining = "Interface\\Icons\\Trade_Mining",
    Skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    Tailoring = "Interface\\Icons\\Trade_Tailoring",
    Cooking = "Interface\\Icons\\INV_Misc_Food_15",
    ["First Aid"] = "Interface\\Icons\\INV_Misc_Bandage_08",
    Fishing = "Interface\\Icons\\Trade_Fishing",
}
function SW.ProfIcon(name) return SW.PROF_ICON[name] or "Interface\\Icons\\INV_Misc_QuestionMark" end

-- Gathering professions level by gathering, not crafting, so they never get a craft path.
SW.GATHERING = { Herbalism = true, Mining = true, Skinning = true, Fishing = true }

-- Window appearance settings, applied to every registered Skillwright window.
SW._windows = {}
function SW.RegisterWindow(f) SW._windows[#SW._windows + 1] = f end

-- Warm cream used for titles (matches the polished look of frames like FreshSoD).
SW.CREAM = "ffebdec2"

-- Atmospheric panel backdrop. We borrow the Group Finder's own scene off its live frame
-- (LFGBrowseFrameFrameBackground in the Blizzard_GroupFinder_VanillaStyle addon); if that
-- isn't available we fall back to a stock marble texture that always renders.
SW.SCENE = "Interface\\FrameGeneral\\UI-Background-Marble"

-- Returns (atlas, file) for the Group Finder background, loading that Blizzard addon if needed.
function SW.SceneSource()
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_GroupFinder_VanillaStyle") end
    for _, n in ipairs({ "LFGBrowseFrameBackgroundArt", "LFGBrowseFrameFrameBackground", "LFGBrowseFrameFrameBackgroundBottom" }) do
        local r = _G[n]
        if r then
            local atlas = r.GetAtlas and r:GetAtlas()
            if atlas and atlas ~= "" then return atlas, nil end
            local file = r.GetTexture and r:GetTexture()
            if file and file ~= "" then return nil, file end
        end
    end
end

function SW.ApplyScene(tex)
    local atlas, file = SW.SceneSource()
    if atlas then pcall(tex.SetAtlas, tex, atlas, false)
    elseif file then tex:SetTexture(file)
    else tex:SetTexture(SW.SCENE) end
end

-- Float an ornate gold border just outside a frame (decorative only - clicks pass through).
function SW.Decorate(frame, outset)
    if frame.deco then return frame.deco end
    outset = outset or 7
    local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    b:SetPoint("TOPLEFT", -outset, outset)
    b:SetPoint("BOTTOMRIGHT", outset, -outset)
    b:SetFrameLevel(frame:GetFrameLevel() + 4)
    b:EnableMouse(false)
    b:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 28, tile = true, tileSize = 28 })
    frame.deco = b
    return b
end
function SW.ApplyWindowSettings()
    local a, sc = SW.DB().alpha or 1, SW.DB().scale or 1
    local showBg = SW.DB().showBackground ~= false
    local sceneA = SW.DB().sceneAlpha or 1
    for _, f in ipairs(SW._windows) do
        if f then
            f:SetAlpha(a); f:SetScale(sc)
            if f.sceneBg then f.sceneBg:SetShown(showBg); f.sceneBg:SetAlpha(sceneA) end
        end
    end
end

function SW.msg(t) print("|cff7fc8ffSkillwright|r: " .. t) end

-- Account-wide settings (window position, active profession, view, collapsed).
-- pos = { x = <screen left>, y = <screen top> } shared by every view; empty = centered.
function SW.DB()
    SkillwrightDB = SkillwrightDB or {}
    SkillwrightDB.pos = SkillwrightDB.pos or {}
    return SkillwrightDB
end

-- Per-character data (last-known profession skill ranks).
function SW.CharDB()
    SkillwrightCharDB = SkillwrightCharDB or {}
    SkillwrightCharDB.skill = SkillwrightCharDB.skill or {}
    return SkillwrightCharDB
end
