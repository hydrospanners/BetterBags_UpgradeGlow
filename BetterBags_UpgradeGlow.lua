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

    for _, line in ipairs(tooltipData.lines) do
        if line.type == TRACK_LINE_TYPE then
            return findUpgradeTrackText(line.leftText) or findUpgradeTrackText(line.rightText)
        end
    end
    return nil
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

local function isUpgradeForSlot(bagData, slot)
    if slot == INVSLOT_OFFHAND then
        local mainhand = items:GetItemDataFromInventorySlot(INVSLOT_MAINHAND)
        if mainhand and mainhand.itemInfo and (
            mainhand.itemInfo.itemEquipLoc == "INVTYPE_2HWEAPON" or
            mainhand.itemInfo.itemEquipLoc == "INVTYPE_RANGED"
        ) then
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
    if not isWrongArmorType(data) and not isUnusableWeapon(data) then
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
eqFrame:SetScript("OnEvent", function()
    events:SendMessage(ctx, "bags/FullRefreshAll")
end)

events:RegisterMessage("item/Updated", updateGlow)

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
