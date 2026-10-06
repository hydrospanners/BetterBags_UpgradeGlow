-- BetterBags_UpgradeGlow: Highlights bag items that have higher item level than the equipped slot(s).
-- Dual-slot aware (rings, trinkets, weapons). Private addon.

local addonName = ...
local BetterBags = LibStub("AceAddon-3.0"):GetAddon("BetterBags", true)
if not BetterBags then return end

local items = BetterBags:GetModule("Items")
local events = BetterBags:GetModule("Events")
local context = BetterBags:GetModule("Context")
local config = BetterBags:GetModule("Config")

local ctx = context:New("UpgradeGlow")

local GLOW_LAYER = "OVERLAY"
-- The only glow atlas we rely on. BetterBags itself uses it for the "new item"
-- flash, so it is known to exist; any colour comes from SetVertexColor rather
-- than from a differently-named atlas.
local GLOW_ATLAS = "bags-glow-white"
local TRACK_LINE_TYPE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemUpgradeLevel or 32

-- Where the track badge sits on the item button. Configurable because other
-- BetterBags plugins and themes draw their own icons on these corners.
local BADGE_POINTS = {
    { label = "Top right", point = "TOPRIGHT", x = -2, y = -2 },
    { label = "Top left", point = "TOPLEFT", x = 2, y = -2 },
    { label = "Bottom right", point = "BOTTOMRIGHT", x = -2, y = 2 },
    { label = "Bottom left", point = "BOTTOMLEFT", x = 2, y = 2 },
}

-- Ascendant Voidforged bonus IDs (Midnight 12.x); see ChonkyCharacterSheet gearDB for reference.
-- Season 2 Ascendant Venomstones reuse these IDs (no new tag in 12.1.5 data),
-- so the badge says "Asc" and fits both seasons. The key stays "Void" so
-- saved renames and recolours carry over.
local VOIDFORGED_BONUS_IDS = {
    [13653] = true, -- Hero-track Voidforged
    [13654] = true, -- Myth-track Voidforged
}

-- Season 2 cantrip gear from The Venomous Abyss; IDs from raidbots
-- https://www.raidbots.com/static/data/live/bonuses.json (same source as the
-- Voidforged IDs). Venomcursed: the very-rare Myth 9 armor from the last two
-- bosses, one bonus ID per stat cantrip.
local VENOMCURSED_BONUS_IDS = {
    [13708] = true, -- Venomcursed Critical Strike
    [13846] = true, -- Venomcursed Mastery
    [13847] = true, -- Venomcursed Haste
    [13987] = true, -- Venomcursed Ascendance
}

-- Corrosive: the raid's Ula'tek-themed special-effect items. Bonus ID only, no
-- tooltip text fallback — "Corrosive" also appears in these items' own effect
-- text and can appear on unrelated items, so a plain text find would
-- false-positive where the bonus ID cannot.
local CORROSIVE_BONUS_IDS = {
    [13731] = true, [13732] = true, [13734] = true, [13735] = true,
    [13736] = true, [13737] = true, [13738] = true, [13739] = true,
    [13741] = true, [13742] = true, [13743] = true, [13744] = true,
    [13745] = true, [13746] = true, [13829] = true, [13830] = true,
    [13831] = true, [13832] = true, [13833] = true, [13834] = true,
}

local TRACKS = {
    Explorer = { label = "Exp", color = { 0.62, 0.62, 0.62 } },
    Adventurer = { label = "Adv", color = { 0.20, 0.95, 0.35 } },
    Veteran = { label = "Vet", color = { 0.25, 0.70, 1.00 } },
    Champion = { label = "Champ", color = { 0.75, 0.45, 1.00 } },
    Hero = { label = "Hero", color = { 1.00, 0.55, 0.15 } },
    Myth = { label = "Myth", color = { 1.00, 0.20, 0.20 } },
    Void = { label = "Asc", title = "Ascendant", color = { 0.70, 0.20, 0.95 } },
    Spore = { label = "Spore", color = { 0.15, 0.65, 0.30 } },
    Venom = { label = "Venom", color = { 0.65, 1.00, 0.25 } },
    Corrosive = { label = "Corr", color = { 0.10, 0.75, 0.55 } },
    Craft = { label = "Craft", color = { 1.00, 0.80, 0.20 } },
}

local TRACK_ORDER = {
    "Adventurer",
    "Champion",
    "Hero",
    "Mythic", -- tooltip alias; normalized to Myth below
    "Explorer",
    "Veteran",
    "Myth",
}

-- Tracks in the order they're offered in the options panel.
local TRACK_SETTINGS_ORDER = {
    "Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth", "Void", "Spore", "Venom", "Corrosive", "Craft",
}

-- Saved settings. `db` is swapped for the real saved table on ADDON_LOADED;
-- every closure below reads the upvalue, so they follow it.
local db = {}

local function applyDefaults(t)
    if t.enableGlow == nil then t.enableGlow = true end
    if t.enableBadges == nil then t.enableBadges = true end
    t.glowColor = t.glowColor or { 1, 1, 1, 1 }
    t.badgePoint = t.badgePoint or "TOPRIGHT"
    t.trackLabels = t.trackLabels or {}
    t.trackColors = t.trackColors or {}
end

applyDefaults(db)

-- An empty label hides that track's badge, so this doubles as a per-track toggle.
local function trackLabel(name)
    local custom = db.trackLabels[name]
    if custom then return custom end
    return TRACKS[name].label
end

local function trackColor(name)
    local c = db.trackColors[name] or TRACKS[name].color
    return c[1], c[2], c[3], c[4] or 1
end

local function badgeAnchor()
    for _, entry in ipairs(BADGE_POINTS) do
        if entry.point == db.badgePoint then return entry end
    end
    return BADGE_POINTS[1]
end

local function ensureGlowTexture(decoration)
    if decoration.UpgradeGlowTex then return decoration.UpgradeGlowTex end
    local tex = decoration:CreateTexture(nil, GLOW_LAYER)
    tex:SetAtlas(GLOW_ATLAS)
    tex:SetAllPoints(decoration)
    tex:SetBlendMode("ADD")
    decoration.UpgradeGlowTex = tex
    return tex
end

local function ensureTrackText(decoration)
    if decoration.UpgradeGlowTrackText then return decoration.UpgradeGlowTrackText end

    -- Anchoring happens in updateTrackText so a corner change applies to
    -- buttons whose font string already exists.
    local text = decoration:CreateFontString(nil, GLOW_LAYER, "NumberFontNormalSmall")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    decoration.UpgradeGlowTrackText = text
    return text
end

local function hideDecorations(decoration)
    if decoration.UpgradeGlowTex then
        decoration.UpgradeGlowTex:Hide()
    end
    if decoration.UpgradeGlowTrackText then
        decoration.UpgradeGlowTrackText:Hide()
    end
end

local function hasAnyBonusID(data, wanted)
    local linkInfo = data.itemLinkInfo
    if not linkInfo or not linkInfo.bonusIDs then return false end
    for _, bonusID in ipairs(linkInfo.bonusIDs) do
        if wanted[tonumber(bonusID)] then
            return true
        end
    end
    return false
end

local function findUpgradeTrackText(text)
    if not text or text == "" then return nil end
    if text:find("Voidforged") then return "Void" end
    for _, trackName in ipairs(TRACK_ORDER) do
        if text:find(trackName) then
            if trackName == "Mythic" then return "Myth" end
            return trackName
        end
    end
    return nil
end

local function getUpgradeTrack(data)
    if hasAnyBonusID(data, VOIDFORGED_BONUS_IDS) then return "Void" end
    if hasAnyBonusID(data, VENOMCURSED_BONUS_IDS) then return "Venom" end
    if hasAnyBonusID(data, CORROSIVE_BONUS_IDS) then return "Corrosive" end

    if not C_TooltipInfo or not C_TooltipInfo.GetBagItem then return nil end
    if not data.bagid or not data.slotid then return nil end

    local tooltipData = C_TooltipInfo.GetBagItem(data.bagid, data.slotid)
    if not tooltipData or not tooltipData.lines then return nil end

    -- Sporefused ("Sporefused: Myth") and season-crafted ("Radiance Crafted",
    -- "Tidal Crafted") gear has no ItemUpgradeLevel line, so those are matched
    -- on plain tooltip text. These tooltips can also carry a "Mythic"
    -- difficulty line, so the special tags win over a track hit. The
    -- Venomcursed find is a fallback for cantrip variants Blizzard adds after
    -- the bonus ID table above. Line 1 is skipped: that's the item name, and
    -- an item can be *named* "Sporefused ..." without being one.
    local trackFromLine
    for i, line in ipairs(tooltipData.lines) do
        if i > 1 and line.leftText then
            -- Plain finds only: leftText can carry embedded color codes and
            -- even multiple visual lines (the Sporefused line arrives as
            -- "Mythic\nSporefused: Myth"), so end-anchored patterns like
            -- "Crafted$" never match ("...Crafted|r").
            if line.leftText:find("Venomcursed", 1, true) then return "Venom" end
            if line.leftText:find("Sporefused", 1, true) then return "Spore" end
            if line.leftText:find("Crafted", 1, true) then return "Craft" end
        end
        if not trackFromLine and line.type == TRACK_LINE_TYPE then
            trackFromLine = findUpgradeTrackText(line.leftText) or findUpgradeTrackText(line.rightText)
        end
    end
    return trackFromLine
end

local function hideTrackText(decoration)
    if decoration.UpgradeGlowTrackText then
        decoration.UpgradeGlowTrackText:Hide()
    end
end

local function updateTrackText(data, decoration)
    if not db.enableBadges then
        hideTrackText(decoration)
        return
    end

    local trackName = getUpgradeTrack(data)
    if not trackName or not TRACKS[trackName] then
        hideTrackText(decoration)
        return
    end

    local label = trackLabel(trackName)
    if label == "" then
        hideTrackText(decoration)
        return
    end

    local anchor = badgeAnchor()
    local text = ensureTrackText(decoration)
    text:ClearAllPoints()
    text:SetPoint(anchor.point, decoration, anchor.point, anchor.x, anchor.y)
    text:SetJustifyH(anchor.point:find("RIGHT") and "RIGHT" or "LEFT")
    text:SetText(label)
    text:SetTextColor(trackColor(trackName))
    text:Show()
end

-- Armor-type filter: don't glow gear your class can't main (e.g. a mail piece
-- for a plate wearer). Class -> preferred armor subclass. Cross-checked against
-- RCLootCouncil's autopass table (live retail reference).
local CLASS_ARMOR = {
    WARRIOR = Enum.ItemArmorSubclass.Plate,
    PALADIN = Enum.ItemArmorSubclass.Plate,
    DEATHKNIGHT = Enum.ItemArmorSubclass.Plate,
    HUNTER = Enum.ItemArmorSubclass.Mail,
    SHAMAN = Enum.ItemArmorSubclass.Mail,
    EVOKER = Enum.ItemArmorSubclass.Mail,
    ROGUE = Enum.ItemArmorSubclass.Leather,
    DRUID = Enum.ItemArmorSubclass.Leather,
    MONK = Enum.ItemArmorSubclass.Leather,
    DEMONHUNTER = Enum.ItemArmorSubclass.Leather,
    MAGE = Enum.ItemArmorSubclass.Cloth,
    WARLOCK = Enum.ItemArmorSubclass.Cloth,
    PRIEST = Enum.ItemArmorSubclass.Cloth,
}

local _, playerClassFile = UnitClass("player")
local preferredArmor = CLASS_ARMOR[playerClassFile]

-- Only the main armor slots carry an armor-type requirement. Cloaks, shirts,
-- tabards, rings, necks and trinkets are intentionally excluded — every class
-- can wear those regardless of armor type.
local ARMOR_TYPE_SLOTS = {
    INVTYPE_HEAD = true,
    INVTYPE_SHOULDER = true,
    INVTYPE_CHEST = true,
    INVTYPE_ROBE = true,
    INVTYPE_WAIST = true,
    INVTYPE_LEGS = true,
    INVTYPE_FEET = true,
    INVTYPE_WRIST = true,
    INVTYPE_HAND = true,
}

-- Purely cosmetic slots: tabards and shirts can roll an item level but never
-- affect your gear, so they must never glow or show a track badge.
local IGNORED_SLOTS = {
    INVTYPE_TABARD = true,
    INVTYPE_BODY = true, -- shirt
}

local GATED_ARMOR = {
    [Enum.ItemArmorSubclass.Cloth] = true,
    [Enum.ItemArmorSubclass.Leather] = true,
    [Enum.ItemArmorSubclass.Mail] = true,
    [Enum.ItemArmorSubclass.Plate] = true,
}

-- True when the item is wearable armor in a gated slot whose armor type is not
-- the one this class mains -> it must never glow as an upgrade.
local function isWrongArmorType(data)
    if not preferredArmor then return false end
    local info = data.itemInfo
    if not info or not ARMOR_TYPE_SLOTS[info.itemEquipLoc] then return false end
    if info.classID ~= Enum.ItemClass.Armor then return false end
    if not GATED_ARMOR[info.subclassID] then return false end
    return info.subclassID ~= preferredArmor
end

-- Weapon-proficiency filter: don't glow weapons your class can't equip at all
-- (e.g. a two-handed axe for a mage, a dagger for a paladin). Each entry lists
-- the classes that *cannot* use that weapon subclass, ported verbatim from
-- RCLootCouncil's autopass weapon table (Utils/autopass.lua, live retail
-- reference); spec unions are already baked in (e.g. mages may use 1H swords
-- and daggers, just not 2H weapons). Subclasses without a class restriction
-- (fishing poles, etc.) are simply absent and never filtered.
local WEAPON_AUTOPASS = {
    [Enum.ItemWeaponSubclass.Axe1H]    = { DRUID = true, PRIEST = true, MAGE = true, WARLOCK = true },
    [Enum.ItemWeaponSubclass.Axe2H]    = { DRUID = true, ROGUE = true, MONK = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Bows]     = { DEATHKNIGHT = true, PALADIN = true, DRUID = true, MONK = true, SHAMAN = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true, WARRIOR = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Crossbow] = { DEATHKNIGHT = true, PALADIN = true, DRUID = true, MONK = true, SHAMAN = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true, WARRIOR = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Dagger]   = { DEATHKNIGHT = true, PALADIN = true, MONK = true, DEMONHUNTER = true },
    [Enum.ItemWeaponSubclass.Guns]     = { DEATHKNIGHT = true, PALADIN = true, DRUID = true, MONK = true, SHAMAN = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true, WARRIOR = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Mace1H]   = { HUNTER = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true },
    [Enum.ItemWeaponSubclass.Mace2H]   = { MONK = true, ROGUE = true, HUNTER = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true },
    [Enum.ItemWeaponSubclass.Polearm]  = { ROGUE = true, SHAMAN = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Sword1H]  = { DRUID = true, SHAMAN = true, PRIEST = true },
    [Enum.ItemWeaponSubclass.Sword2H]  = { DRUID = true, MONK = true, ROGUE = true, SHAMAN = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Staff]    = { DEATHKNIGHT = true, PALADIN = true, ROGUE = true, DEMONHUNTER = true },
    [Enum.ItemWeaponSubclass.Wand]     = { WARRIOR = true, DEATHKNIGHT = true, PALADIN = true, DRUID = true, MONK = true, ROGUE = true, HUNTER = true, SHAMAN = true, DEMONHUNTER = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Warglaive] = { WARRIOR = true, DEATHKNIGHT = true, PALADIN = true, DRUID = true, MONK = true, ROGUE = true, PRIEST = true, MAGE = true, WARLOCK = true, HUNTER = true, SHAMAN = true, EVOKER = true },
    [Enum.ItemWeaponSubclass.Unarmed]  = { DEATHKNIGHT = true, PALADIN = true, PRIEST = true, MAGE = true, WARLOCK = true }, -- Fist weapons
}

-- True when the item is a weapon whose type this class cannot equip -> never glow it.
local function isUnusableWeapon(data)
    local info = data.itemInfo
    if not info or info.classID ~= Enum.ItemClass.Weapon then return false end
    local denied = WEAPON_AUTOPASS[info.subclassID]
    return denied ~= nil and denied[playerClassFile] == true
end

-- Shields sit outside both filters above: armor, but not in a gated armor
-- slot, and not a weapon. Denied classes ported verbatim from RCLootCouncil's
-- autopass table (usable by Warrior, Paladin, Shaman only).
local SHIELD_AUTOPASS = { DEATHKNIGHT = true, DRUID = true, MONK = true, ROGUE = true, HUNTER = true, PRIEST = true, MAGE = true, WARLOCK = true, DEMONHUNTER = true, EVOKER = true }

local function isUnusableShield(data)
    local info = data.itemInfo
    if not info or info.classID ~= Enum.ItemClass.Armor then return false end
    if info.subclassID ~= Enum.ItemArmorSubclass.Shield then return false end
    return SHIELD_AUTOPASS[playerClassFile] == true
end

-- An item above the character's level can't be equipped yet -> never glow it.
local function isLevelLocked(data)
    return (data.itemInfo.itemMinLevel or 0) > UnitLevel("player")
end

local OTHER_PAIR_SLOT = {
    [INVSLOT_FINGER1] = INVSLOT_FINGER2,
    [INVSLOT_FINGER2] = INVSLOT_FINGER1,
    [INVSLOT_TRINKET1] = INVSLOT_TRINKET2,
    [INVSLOT_TRINKET2] = INVSLOT_TRINKET1,
    [INVSLOT_MAINHAND] = INVSLOT_OFFHAND,
    [INVSLOT_OFFHAND] = INVSLOT_MAINHAND,
}

-- True when at most one copy of the item can be worn (plain "Unique" or
-- "Unique-Equipped"). Category limits of 2+ (e.g. "Unique-Equipped:
-- Embellished (2)") allow a second copy, so they don't count.
local function isUniqueEquipped(data)
    if not C_Item.GetItemUniquenessByID then return false end
    local isUnique, _, limitCount = C_Item.GetItemUniquenessByID(data.itemInfo.itemLink)
    return isUnique == true and (limitCount == nil or limitCount <= 1)
end

local function isUpgradeForSlot(bagData, slot)
    -- Inventory types BetterBags can't map arrive as slot 0 (e.g. profession
    -- tools); without this guard they'd compare against nil -> ilvl 0 -> glow.
    if slot < INVSLOT_FIRST_EQUIPPED or slot > INVSLOT_LAST_EQUIPPED then
        return false
    end

    if slot == INVSLOT_OFFHAND then
        -- A weapon in the off-hand needs dual wield (spec-dependent); shields
        -- and held-in-off-hand items don't.
        if bagData.itemInfo.classID == Enum.ItemClass.Weapon and not CanDualWield() then
            return false
        end
        -- A 2H or ranged main hand blocks the off-hand slot entirely. Wands
        -- are INVTYPE_RANGEDRIGHT too but don't block it, so they still allow
        -- off-hand frill comparisons.
        local mainhand = items:GetItemDataFromInventorySlot(INVSLOT_MAINHAND)
        if mainhand and mainhand.itemInfo and (
            mainhand.itemInfo.itemEquipLoc == "INVTYPE_2HWEAPON" or
            mainhand.itemInfo.itemEquipLoc == "INVTYPE_RANGED" or
            (mainhand.itemInfo.itemEquipLoc == "INVTYPE_RANGEDRIGHT" and
                mainhand.itemInfo.subclassID ~= Enum.ItemWeaponSubclass.Wand)
        ) then
            return false
        end
    end

    -- A unique-equipped item can't sit next to a copy of itself: when its twin
    -- slot holds the same item, the only legal move is swapping into that
    -- copy's own slot, so this slot's comparison is void. (Covers getting the
    -- same trinket twice as loot.)
    local otherSlot = OTHER_PAIR_SLOT[slot]
    if otherSlot then
        local other = items:GetItemDataFromInventorySlot(otherSlot)
        if other and other.itemInfo and other.itemInfo.itemID == bagData.itemInfo.itemID
            and isUniqueEquipped(bagData) then
            return false
        end
    end

    local bagIlvl = bagData.itemInfo.currentItemLevel or 0
    local equippedItem = items:GetItemDataFromInventorySlot(slot)
    local equippedIlvl = 0
    if equippedItem and equippedItem.itemInfo and not equippedItem.isItemEmpty then
        equippedIlvl = equippedItem.itemInfo.currentItemLevel or 0
    end
    return bagIlvl > equippedIlvl
end

local function updateGlow(_, item, decoration)
    if not item or not decoration then return end
    local data = item:GetItemData()
    if not data or not data.itemInfo or data.isItemEmpty then
        hideDecorations(decoration)
        return
    end
    if IGNORED_SLOTS[data.itemInfo.itemEquipLoc] then
        hideDecorations(decoration)
        return
    end
    if not data.inventorySlots or #data.inventorySlots == 0 then
        hideDecorations(decoration)
        return
    end
    if not C_Item or not C_Item.IsEquippableItem(data.itemInfo.itemLink) then
        hideDecorations(decoration)
        return
    end

    updateTrackText(data, decoration)

    local show = false
    if db.enableGlow and not isWrongArmorType(data) and not isUnusableWeapon(data)
        and not isUnusableShield(data) and not isLevelLocked(data) then
        for _, slot in pairs(data.inventorySlots) do
            if isUpgradeForSlot(data, slot) then
                show = true
                break
            end
        end
    end

    if show then
        local tex = ensureGlowTexture(decoration)
        local c = db.glowColor
        tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        tex:Show()
    else
        if decoration.UpgradeGlowTex then
            decoration.UpgradeGlowTex:Hide()
        end
    end
end

-- Options
--
-- BetterBags' AddPluginConfig flattens the options table and walks it with
-- pairs(), so an entry per setting comes out in a scrambled order. Instead we
-- hand it a single entry whose name function builds the whole panel against
-- config.configFrame, which keeps the settings in the order written here.
-- (Same hook BetterBags_iLvl uses for its slider.)

local refreshTimer
local function refresh()
    if refreshTimer then refreshTimer:Cancel() end
    -- The colour picker fires on every swatch drag, so coalesce the redraws.
    refreshTimer = C_Timer.NewTimer(0.2, function()
        refreshTimer = nil
        events:SendMessage(ctx, "bags/FullRefreshAll")
    end)
end

-- BetterBags anchors a colour swatch in the left gutter (x=0), matching where
-- it puts checkboxes. That reads fine in a run of checkboxes, but here the
-- swatches sit among input boxes whose text column starts at x=37, so a
-- gutter swatch looks stranded to the left of everything it belongs to.
-- Pull it into the text column instead. Guarded so a BetterBags layout change
-- falls back to the stock position rather than erroring.
local CONTENT_INDENT = 37

local function addAlignedColor(f, opts)
    f:AddColor(opts)
    local container = config.configFrame.layout and config.configFrame.layout.nextFrame
    if container and container.colorPicker then
        container.colorPicker:ClearAllPoints()
        container.colorPicker:SetPoint("TOPLEFT", container, "TOPLEFT", CONTENT_INDENT, 0)
    end
end

-- Swatch size matches the input box height so the two sit on one line.
local SWATCH_SIZE = 20
-- Blizzard's round colour-swatch texture, as used by BetterBags' own AddColor.
local SWATCH_TEXTURE = 5014189
local SWATCH_MASK = "Interface/CHARACTERFRAME/TempPortraitAlphaMask"

-- Track name -> swatch texture, so the reset button can repaint swatches we
-- built ourselves (BetterBags' ReloadAllFormElements only knows its own).
local trackSwatches = {}

-- One row per track: the text box and its colour swatch side by side, so a
-- track reads as a single setting instead of two unrelated controls. BetterBags
-- has no combined widget, so the swatch is built into the input box's own
-- container. If that container ever stops exposing .input we fall back to a
-- separate colour row rather than dropping the control.
local function addTrackRow(f, name)
    f:AddInputBox({
        title = TRACKS[name].title or name,
        description = "",
        getValue = function() return trackLabel(name) end,
        setValue = function(_, value)
            db.trackLabels[name] = value
            refresh()
        end,
    })

    local container = config.configFrame.layout and config.configFrame.layout.nextFrame
    if not container or not container.input then
        addAlignedColor(f, {
            title = (TRACKS[name].title or name) .. " colour",
            description = "",
            getValue = function()
                local r, g, b, a = trackColor(name)
                return { red = r, green = g, blue = b, alpha = a }
            end,
            setValue = function(_, value)
                db.trackColors[name] = { value.red, value.green, value.blue, value.alpha }
                refresh()
            end,
        })
        return
    end

    -- Free up room at the end of the input row for the swatch. Re-anchoring
    -- RIGHT replaces the full-width anchor AddInputBox set.
    container.input:SetPoint("RIGHT", container, "RIGHT", -(SWATCH_SIZE + 13), 0)

    local swatch = CreateFrame("Frame", nil, container)
    swatch:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    swatch:SetPoint("LEFT", container.input, "RIGHT", 8, 0)
    -- A bare Frame takes no mouse input until asked, so OnMouseDown below
    -- would never fire without this.
    swatch:EnableMouse(true)

    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(SWATCH_TEXTURE)
    local mask = swatch:CreateMaskTexture()
    mask:SetAllPoints(tex)
    mask:SetTexture(SWATCH_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask)
    tex:SetVertexColor(trackColor(name))
    trackSwatches[name] = tex

    local function apply(r, g, b, a)
        db.trackColors[name] = { r, g, b, a }
        tex:SetVertexColor(r, g, b, a)
        refresh()
    end

    local function fromPicker()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        apply(r, g, b, ColorPickerFrame:GetColorAlpha())
    end

    swatch:SetScript("OnMouseDown", function()
        -- Captured before the picker opens so Cancel can put it back; the
        -- stock BetterBags colour rows just keep whatever you dragged to.
        local r, g, b, a = trackColor(name)
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = fromPicker,
            opacityFunc = fromPicker,
            cancelFunc = function() apply(r, g, b, a) end,
            hasOpacity = true,
            opacity = a,
            r = r, g = g, b = b,
        })
    end)
end

local function badgePointLabels()
    local labels = {}
    for _, entry in ipairs(BADGE_POINTS) do
        table.insert(labels, entry.label)
    end
    return labels
end

local function buildPanel()
    local f = config.configFrame

    f:AddInlineSubSection({
        title = "Upgrade glow",
        description = "Glows bag items with a higher item level than the one you have equipped.",
    })

    f:AddCheckbox({
        title = "Show upgrade glow",
        description = "Turn the glow off to keep only the track badges.",
        getValue = function() return db.enableGlow end,
        setValue = function(_, value)
            db.enableGlow = value
            refresh()
        end,
    })

    addAlignedColor(f, {
        title = "Glow colour",
        description = "Colour and opacity of the glow.",
        getValue = function()
            local c = db.glowColor
            return { red = c[1], green = c[2], blue = c[3], alpha = c[4] or 1 }
        end,
        setValue = function(_, value)
            db.glowColor = { value.red, value.green, value.blue, value.alpha }
            refresh()
        end,
    })

    f:AddInlineSubSection({
        title = "Track badges",
        description = "The small track label drawn in the corner of an item.",
    })

    f:AddCheckbox({
        title = "Show track badges",
        description = "Turn the badges off to keep only the glow.",
        getValue = function() return db.enableBadges end,
        setValue = function(_, value)
            db.enableBadges = value
            refresh()
        end,
    })

    f:AddDropdown({
        title = "Badge corner",
        description = "Move the badge if it covers an icon drawn by another addon.",
        items = badgePointLabels(),
        getValue = function(_, value) return value == badgeAnchor().label end,
        setValue = function(_, value)
            for _, entry in ipairs(BADGE_POINTS) do
                if entry.label == value then
                    db.badgePoint = entry.point
                    break
                end
            end
            refresh()
        end,
    })

    f:AddInlineSubSection({
        title = "Badge text and colours",
        description = "Rename or recolour each track. Clear the text to hide that track entirely.",
    })

    for _, name in ipairs(TRACK_SETTINGS_ORDER) do
        addTrackRow(f, name)
    end

    f:AddButtonGroup({
        ButtonOptions = { {
            title = "Reset badge text and colours",
            onClick = function()
                wipe(db.trackLabels)
                wipe(db.trackColors)
                -- Repaints BetterBags' own widgets; our swatches aren't
                -- registered with it, so they're repainted here.
                config.configFrame:ReloadAllFormElements()
                for trackName, tex in pairs(trackSwatches) do
                    tex:SetVertexColor(trackColor(trackName))
                end
                refresh()
            end,
        } },
    })
end

-- We do not subscribe to item/Clearing so the upgrade glow is not reset when
-- the "recent item clear" button is pressed; visibility is set only in updateGlow.
-- Visibility is set only in updateGlow so the upgrade glow persists through that action.

local eqFrame = CreateFrame("Frame")
eqFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Dual wield is spec-dependent, so off-hand glows must re-evaluate on respec.
eqFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
eqFrame:SetScript("OnEvent", function()
    events:SendMessage(ctx, "bags/FullRefreshAll")
end)

events:RegisterMessage("item/Updated", updateGlow)

-- Debug: /bbug <item name substring> dumps the raw C_TooltipInfo lines and
-- item link for the first matching bag item. The on-screen tooltip can contain
-- display-layer lines that are absent from the raw data, so badge detection
-- must be verified against this dump, not against what the tooltip shows.
local issecret = issecretvalue or function() return false end
local function safeText(v)
    if v == nil then return "-" end
    if issecret(v) then return "<secret>" end
    return tostring(v)
end

SLASH_BBUPGRADEGLOW1 = "/bbug"
SlashCmdList.BBUPGRADEGLOW = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if msg == "" then
        print("UpgradeGlow: usage /bbug <item name substring>")
        return
    end
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            local name = link and link:match("%[(.-)%]")
            if name and name:lower():find(msg, 1, true) then
                print("UpgradeGlow dump: " .. name .. " (bag " .. bag .. ", slot " .. slot .. ")")
                print("link: " .. link:gsub("|", "||"))
                local td = C_TooltipInfo.GetBagItem(bag, slot)
                if td and td.lines then
                    for i, line in ipairs(td.lines) do
                        print(i .. " [type " .. safeText(line.type) .. "] " ..
                            safeText(line.leftText) .. " / " .. safeText(line.rightText))
                    end
                else
                    print("no tooltip data")
                end
                return
            end
        end
    end
    print("UpgradeGlow: no bag item matching '" .. msg .. "'")
end

-- Load saved settings, register the options panel, and refresh once so bags
-- that are already open pick up the glows.
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(_, _, name)
    if name == addonName then
        loadFrame:UnregisterEvent("ADDON_LOADED")

        BetterBags_UpgradeGlowDB = BetterBags_UpgradeGlowDB or {}
        db = BetterBags_UpgradeGlowDB
        applyDefaults(db)

        -- One entry: its name function builds the panel in order. See buildPanel.
        config:AddPluginConfig("Upgrade Glow", {
            panel = { name = function() buildPanel() end },
        })

        C_Timer.After(0.2, function()
            events:SendMessage(ctx, "bags/FullRefreshAll")
        end)
    end
end)
