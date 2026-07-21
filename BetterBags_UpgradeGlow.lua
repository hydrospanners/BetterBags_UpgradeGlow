-- BetterBags_UpgradeGlow: Highlights bag items that have higher item level than the equipped slot(s).
-- Dual-slot aware (rings, trinkets, weapons). Private addon.

local addonName = ...
local BetterBags = LibStub("AceAddon-3.0"):GetAddon("BetterBags", true)
if not BetterBags then return end

local items = BetterBags:GetModule("Items")
local events = BetterBags:GetModule("Events")
local context = BetterBags:GetModule("Context")

local ctx = context:New("UpgradeGlow")

local GLOW_LAYER = "OVERLAY"
local GLOW_ATLAS = "bags-glow-white"
local TRACK_LINE_TYPE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemUpgradeLevel or 32

-- Ascendant Voidforged bonus IDs (Midnight 12.x); see ChonkyCharacterSheet gearDB for reference.
local VOIDFORGED_BONUS_IDS = {
    [13653] = true, -- Hero-track Voidforged
    [13654] = true, -- Myth-track Voidforged
}

local TRACKS = {
    Explorer = { label = "Exp", color = { 0.62, 0.62, 0.62 } },
    Adventurer = { label = "Adv", color = { 0.20, 0.95, 0.35 } },
    Veteran = { label = "Vet", color = { 0.25, 0.70, 1.00 } },
    Champion = { label = "Champ", color = { 0.75, 0.45, 1.00 } },
    Hero = { label = "Hero", color = { 1.00, 0.55, 0.15 } },
    Myth = { label = "Myth", color = { 1.00, 0.20, 0.20 } },
    Void = { label = "Void", color = { 0.55, 0.20, 0.85 } },
    Spore = { label = "Spore", color = { 0.15, 0.65, 0.30 } },
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

    local text = decoration:CreateFontString(nil, GLOW_LAYER, "NumberFontNormalSmall")
    text:SetPoint("TOPRIGHT", decoration, "TOPRIGHT", -2, -2)
    text:SetJustifyH("RIGHT")
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

local function isVoidforgedItem(data)
    local linkInfo = data.itemLinkInfo
    if not linkInfo or not linkInfo.bonusIDs then return false end
    for _, bonusID in ipairs(linkInfo.bonusIDs) do
        if VOIDFORGED_BONUS_IDS[tonumber(bonusID)] then
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
    if isVoidforgedItem(data) then return "Void" end

    if not C_TooltipInfo or not C_TooltipInfo.GetBagItem then return nil end
    if not data.bagid or not data.slotid then return nil end

    local tooltipData = C_TooltipInfo.GetBagItem(data.bagid, data.slotid)
    if not tooltipData or not tooltipData.lines then return nil end

    -- Sporefused ("Sporefused: Myth") and season-crafted ("Radiance Crafted")
    -- gear has no ItemUpgradeLevel line, so those are matched on plain tooltip
    -- text. Sporefused tooltips can also carry a "Mythic" difficulty line, so
    -- Spore/Craft win over a track hit. Line 1 is skipped: that's the item
    -- name, and an item can be *named* "Sporefused ..." without being one.
    local trackFromLine
    for i, line in ipairs(tooltipData.lines) do
        if i > 1 and line.leftText then
            -- Plain finds only: leftText can carry embedded color codes and
            -- even multiple visual lines (the Sporefused line arrives as
            -- "Mythic\nSporefused: Myth"), so end-anchored patterns like
            -- "Crafted$" never match ("...Crafted|r").
            if line.leftText:find("Sporefused", 1, true) then return "Spore" end
            if line.leftText:find("Crafted", 1, true) then return "Craft" end
        end
        if not trackFromLine and line.type == TRACK_LINE_TYPE then
            trackFromLine = findUpgradeTrackText(line.leftText) or findUpgradeTrackText(line.rightText)
        end
    end
    return trackFromLine
end

local function updateTrackText(data, decoration)
    local trackName = getUpgradeTrack(data)
    local track = trackName and TRACKS[trackName]
    if not track then
        if decoration.UpgradeGlowTrackText then
            decoration.UpgradeGlowTrackText:Hide()
        end
        return
    end

    local text = ensureTrackText(decoration)
    text:SetText(track.label)
    text:SetTextColor(track.color[1], track.color[2], track.color[3], 1)
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
    if not isWrongArmorType(data) and not isUnusableWeapon(data)
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
        tex:Show()
    else
        if decoration.UpgradeGlowTex then
            decoration.UpgradeGlowTex:Hide()
        end
    end
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

-- Refresh once after load so already-open bags get glows
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(_, _, name)
    if name == addonName then
        loadFrame:UnregisterEvent("ADDON_LOADED")
        C_Timer.After(0.2, function()
            events:SendMessage(ctx, "bags/FullRefreshAll")
        end)
    end
end)
