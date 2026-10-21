local ADDON_ID = 'howudoin'
local FINISHER = 'Interface/AddOns/howudoin/finisher/finisher.ogg'
local SOUND_PATH = 'Interface/AddOns/howudoin/sounds/howudoin%d.ogg'
local NUM_SOUNDS = 14
local THROTTLE_SECONDS = 2

-- Forever-only tuning (no combat log, so crits are credited to you by timing):
local ATTRIBUTION_WINDOW = 1.5   -- seconds after one of YOUR casts that a crit on your target counts as yours
local FINISHER_CHECK_DELAY = 0.1 -- seconds to wait before checking "did that crit kill / fully heal the target?"
local DUPLICATE_WINDOW = 0.1     -- UNIT_COMBAT can fire once per unit token for the same hit; ignore repeats

-- GetAddOnMetadata moved to C_AddOns in modern clients (and the global is gone on Forever).
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local ADDON_VERSION = GetMetadata(ADDON_ID, 'Version') or '?'
local ADDON_TITLE = GetMetadata(ADDON_ID, 'Title') or ADDON_ID

-- WoW: Forever runs on Midnight's addon rules: addons get NO combat log, and combat values can be
-- "secret". Anything that has issecretvalue() is on those rules, so use it as the switch.
local IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local HAS_COMBAT_LOG = CombatLogGetCurrentEventInfo ~= nil and issecretvalue == nil and not IS_FOREVER

local DEFAULTS = {
  TRIGGER_ON_SWING = true,
  FINISHER_ON_OVERKILL = true,
  THROTTLE_SOUNDS = false,
  BEST_CRIT_ONLY = false, -- only play for crits close to your best crit with that spell
  BEST_TOLERANCE = 5,     -- "close" = within this many percent of your best (0 = new records only)
}
-- Your records live in howudoinCharSettings.BEST_CRITS (created in InitSettings).

local debugMode = false
local PLAYER_GUID -- legacy (combat log) path only

-- Helpers

local function printHowudoin(...)
  print('|cFF9BDBF5' .. ADDON_TITLE .. '|r', 'v' .. ADDON_VERSION, ...)
end

local function formatSetting(setting)
  if setting then
    return '|cFF4caf50ENABLED|r'
  else
    return '|cFFf44336DISABLED|r'
  end
end

local function ends_with(str, ending)
  return ending == '' or str:sub(-#ending) == ending
end

local function IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value)
end

-- Calls func, returns its result, or nil if it errored or returned a secret value.
local function SafeCall(func, ...)
  local ok, result = pcall(func, ...)
  if ok and not IsSecret(result) then
    return result
  end
end

local function DebugValue(value)
  if IsSecret(value) then
    return '<secret>'
  end
  return tostring(value)
end

-- Sound

local lastPlayed = 0

local function CooldownReady()
  local now = GetTime()
  if now - lastPlayed < THROTTLE_SECONDS then
    return false
  end
  lastPlayed = now
  return true
end

local function PlayRandomHowudoin()
  PlaySoundFile(SOUND_PATH:format(math.random(1, NUM_SOUNDS)), 'Master')
end

-- One entry point for every crit, whichever backend detected it.
local function PlayCritSound(isFinisher)
  if howudoinCharSettings.THROTTLE_SOUNDS and not CooldownReady() then
    return
  end
  if isFinisher then
    PlaySoundFile(FINISHER, 'Master')
  else
    PlayRandomHowudoin()
  end
end

-- Best-crit tracking
--
-- Every crit credited to you updates a per-spell record (auto attacks count as their own "spell",
-- and heals are tracked separately from damage). With BEST_CRIT_ONLY on, a crit only plays if it is
-- within BEST_TOLERANCE percent of the record. A new record always plays. Records are kept even
-- while the filter is off, so turning it on later starts with your history.
--
-- If the game hides the damage number (secret value) we can't measure it, so the crit plays as
-- usual and no record is touched.

local function CritIsWorthPlaying(key, name, amount)
  if type(amount) ~= 'number' or IsSecret(amount) then
    if debugMode then
      printHowudoin('best-crit:', key, 'amount unreadable -> plays normally')
    end
    return true
  end

  local settings = howudoinCharSettings
  local records = settings.BEST_CRITS
  local best = records[key]

  if not best or amount > best.amount then
    records[key] = { amount = amount, name = name }
    if debugMode then
      printHowudoin('best-crit:', key, amount, 'NEW RECORD')
    end
    return true
  end

  local cutoff = best.amount * (1 - settings.BEST_TOLERANCE / 100)
  local passes = amount >= cutoff
  if debugMode then
    printHowudoin('best-crit:', key, amount, format('best=%.0f needs>=%.0f', best.amount, cutoff), passes and 'PLAYS' or 'skipped')
  end
  return passes or not settings.BEST_CRIT_ONLY
end

-- Backend 1: combat log (Classic Era / TBC / MoP Classic). This is your original logic.

local function OnCombatLog()
  PLAYER_GUID = PLAYER_GUID or UnitGUID('player')

  local _, subevent, _, sourceGUID = CombatLogGetCurrentEventInfo()
  if sourceGUID ~= PLAYER_GUID then
    return
  end

  local isSwing = subevent == 'SWING_DAMAGE'
  local isHeal = ends_with(subevent, '_HEAL')
  if not (isSwing or isHeal or ends_with(subevent, '_DAMAGE')) then
    return
  end

  -- Payload positions (after the 11 base params):
  --   SWING_DAMAGE: amount(12) overkill(13) school(14) resisted(15) blocked(16) absorbed(17) critical(18)
  --   SPELL_*_DAMAGE: spellId(12) name(13) school(14) amount(15) overkill(16) school(17) ... absorbed(20) critical(21)
  --   SPELL_*_HEAL: spellId(12) name(13) school(14) amount(15) overhealing(16) absorbed(17) critical(18)
  local info = { CombatLogGetCurrentEventInfo() }
  local excess, critical, amount, key, name
  if isSwing then
    excess, critical, amount = info[13], info[18], info[12]
    key, name = 'swing', 'Auto Attack'
  elseif isHeal then
    excess, critical, amount = info[16], info[18], info[15]
    key, name = 'heal:' .. info[12], info[13]
  else
    excess, critical, amount = info[16], info[21], info[15]
    key, name = 'dmg:' .. info[12], info[13]
  end

  if not critical then
    return
  end
  if isSwing and not howudoinCharSettings.TRIGGER_ON_SWING then
    return
  end
  if not CritIsWorthPlaying(key, name, amount) then
    return
  end

  PlayCritSound(howudoinCharSettings.FINISHER_ON_OVERKILL and excess ~= nil and excess > 0)
end

-- Backend 2: unit events (WoW: Forever). No combat log, so we watch UNIT_COMBAT, which tells us a
-- unit took damage/healing and whether it was a crit, but NOT who caused it. We credit it to you
-- when it lands on your target shortly after one of your casts (or while you are auto-attacking).

local lastCastTime = 0
local lastCastSpellID
local lastTriggerTime = 0

local function CastRecently()
  return GetTime() - lastCastTime <= ATTRIBUTION_WINDOW
end

local function IsAutoAttacking()
  local isCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
  return isCurrentSpell ~= nil and SafeCall(isCurrentSpell, 6603) == true -- 6603 = Attack
end

-- Stand-in for "overkill" / "overheal": did the crit kill the target (damage) or leave it full (heal)?
local function TargetFinished(unit, isHeal)
  if isHeal then
    local health, maxHealth = SafeCall(UnitHealth, unit), SafeCall(UnitHealthMax, unit)
    return health ~= nil and maxHealth ~= nil and health >= maxHealth
  end
  return SafeCall(UnitIsDead, unit) == true
end

local function OnSpellcastSucceeded(_, _, spellID)
  lastCastTime = GetTime()
  lastCastSpellID = spellID
end

-- Record key + display name for a crit credited to your last cast (or to your auto attack).
local function SpellKey(kind, spellID)
  if type(spellID) ~= 'number' or IsSecret(spellID) then
    return kind .. ':unknown', kind == 'heal' and 'Heals' or 'Damage spells'
  end
  local name = C_Spell and C_Spell.GetSpellName and SafeCall(C_Spell.GetSpellName, spellID)
  return kind .. ':' .. spellID, name or ('Spell ' .. spellID)
end

local function OnUnitCombat(unit, action, flagText, amount, schoolMask)
  if debugMode then
    printHowudoin('UNIT_COMBAT', 'unit=' .. DebugValue(unit), 'action=' .. DebugValue(action),
      'flag=' .. DebugValue(flagText), 'amount=' .. DebugValue(amount), 'school=' .. DebugValue(schoolMask),
      format('lastCast=%.2fs ago', GetTime() - lastCastTime))
  end

  -- Secret values can't be compared; if the game hides these we simply can't detect the crit.
  if IsSecret(unit) or IsSecret(action) or IsSecret(flagText) then
    return
  end
  if flagText ~= 'CRITICAL' then
    return
  end

  local isHeal = action == 'HEAL'
  if not isHeal and action ~= 'WOUND' then
    return
  end

  local castRecently = CastRecently()

  if isHeal then
    -- Heal crits count on friendly units only, and only right after you cast something.
    if SafeCall(UnitCanAssist, 'player', unit) == false or not castRecently then
      return
    end
  else
    -- Damage crits count on your target only (one token per hit, so no duplicate sounds).
    if unit ~= 'target' or SafeCall(UnitCanAttack, 'player', unit) == false then
      return
    end
    if not castRecently then
      -- No recent cast: only a white (auto-attack) swing could have done it.
      if not IsAutoAttacking() or not howudoinCharSettings.TRIGGER_ON_SWING then
        return
      end
    end
  end

  local now = GetTime()
  if now - lastTriggerTime < DUPLICATE_WINDOW then
    return
  end
  lastTriggerTime = now

  local key, name
  if castRecently then
    key, name = SpellKey(isHeal and 'heal' or 'dmg', lastCastSpellID)
  else
    key, name = 'swing', 'Auto Attack'
  end
  if not CritIsWorthPlaying(key, name, amount) then
    return
  end

  if howudoinCharSettings.FINISHER_ON_OVERKILL then
    -- Give the game a moment to register the death / health change before we look.
    C_Timer.After(FINISHER_CHECK_DELAY, function()
      PlayCritSound(TargetFinished(unit, isHeal))
    end)
  else
    PlayCritSound(false)
  end
end

-- Settings & slash commands

local function InitSettings()
  local firstRun = howudoinCharSettings == nil
  if firstRun then
    howudoinCharSettings = {}
  end
  for key, default in pairs(DEFAULTS) do
    if howudoinCharSettings[key] == nil then
      howudoinCharSettings[key] = default
    end
  end
  howudoinCharSettings.BEST_CRITS = howudoinCharSettings.BEST_CRITS or {}
  if firstRun then
    printHowudoin('Welcome to howudoin! Defaults set, type /howudoin to see the options.')
  end
end

local MAX_RECORDS_SHOWN = 10

local function ShowRecords()
  local list = {}
  for _, record in pairs(howudoinCharSettings.BEST_CRITS) do
    list[#list + 1] = record
  end
  if #list == 0 then
    printHowudoin('-- No crit records yet. Go land some crits!')
    return
  end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  printHowudoin('-- Your best crits')
  for i = 1, math.min(#list, MAX_RECORDS_SHOWN) do
    print(format('  %s: %.0f', list[i].name or '?', list[i].amount))
  end
  if #list > MAX_RECORDS_SHOWN then
    print(format('  ...and %d more', #list - MAX_RECORDS_SHOWN))
  end
end

local function SetTolerance(arg)
  local percent = tonumber(arg)
  if not percent or percent < 0 or percent > 100 then
    printHowudoin('-- Usage: /howudoin tolerance <0-100>   Currently', howudoinCharSettings.BEST_TOLERANCE .. '%')
    return
  end
  howudoinCharSettings.BEST_TOLERANCE = percent
  printHowudoin('-- Best-crit tolerance set to', percent .. '%')
end

local TOGGLES = {
  swing = {
    key = 'TRIGGER_ON_SWING',
    on = function() return 'Sound triggers on Weapon(White) crits.' end,
  },
  overkill = {
    key = 'FINISHER_ON_OVERKILL',
    on = function() return 'Different howudoin sound for finishing crits (overkill / killing blow).' end,
  },
  throttle = {
    key = 'THROTTLE_SOUNDS',
    on = function() return 'Sets a cooldown of ' .. THROTTLE_SECONDS .. ' seconds between sounds (Helps reduce spam for melee classes and for AOE).' end,
  },
  best = {
    key = 'BEST_CRIT_ONLY',
    on = function() return 'Only play for crits within ' .. howudoinCharSettings.BEST_TOLERANCE .. '% of your best crit with that spell.' end,
  },
}

SLASH_HOWUDOIN1 = '/howudoin'
SlashCmdList['HOWUDOIN'] = function(input)
  local command, arg = strtrim(input or ''):lower():match('^(%S*)%s*(.-)$')
  local settings = howudoinCharSettings
  local toggle = TOGGLES[command]

  if toggle then
    settings[toggle.key] = not settings[toggle.key]
    printHowudoin('--', toggle.on(), formatSetting(settings[toggle.key]))
  elseif command == 'tolerance' then
    SetTolerance(arg)
  elseif command == 'records' then
    ShowRecords()
  elseif command == 'reset' then
    settings.BEST_CRITS = {}
    printHowudoin('-- Crit records cleared.')
  elseif command == 'debug' then
    debugMode = not debugMode
    printHowudoin('-- Debug output (best-crit decisions' .. (HAS_COMBAT_LOG and '' or ', raw UNIT_COMBAT events') .. ').', formatSetting(debugMode))
  else
    PlayRandomHowudoin()
    printHowudoin('Config')
    print('  Plays a random howudoin when you land a crit!')
    print('  Mode: ' .. (HAS_COMBAT_LOG and 'combat log' or 'unit events (no combat log available)') .. '|n')
    print('/howudoin swing|n-- Toggle - Sound triggers on Weapon(White) crits.', 'Currently', formatSetting(settings.TRIGGER_ON_SWING))
    print('/howudoin overkill|n-- Toggle - Different howudoin sound for finishing crits (overkill / killing blow).', 'Currently', formatSetting(settings.FINISHER_ON_OVERKILL))
    print('/howudoin throttle|n-- Toggle - Sets a ' .. THROTTLE_SECONDS .. ' second cooldown on sounds playing (Helps reduce spam for melee classes and for AOE).', 'Currently', formatSetting(settings.THROTTLE_SOUNDS))
    print('/howudoin best|n-- Toggle - Only play for crits close to your best crit with that spell.', 'Currently', formatSetting(settings.BEST_CRIT_ONLY))
    print('/howudoin tolerance <0-100>|n-- How close to your best counts, in percent (0 = new records only).', 'Currently', settings.BEST_TOLERANCE .. '%')
    print('/howudoin records|n-- Show your best crits.')
    print('/howudoin reset|n-- Clear your crit records.')
    print('/howudoin debug|n-- Toggle - Print what the addon sees, for troubleshooting.', 'Currently', formatSetting(debugMode))
  end
end

-- Wiring

local handlers = {}
local frame = CreateFrame('Frame')

handlers.ADDON_LOADED = function(name)
  if name ~= ADDON_ID then
    return
  end
  frame:UnregisterEvent('ADDON_LOADED')
  InitSettings()

  -- Only register the events the current client allows. Registering COMBAT_LOG_EVENT_UNFILTERED on
  -- Midnight-rules clients raises a forbidden-action error, so it must never be touched there.
  if HAS_COMBAT_LOG then
    frame:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
  else
    frame:RegisterEvent('UNIT_COMBAT')
    frame:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
  end
end
handlers.COMBAT_LOG_EVENT_UNFILTERED = OnCombatLog
handlers.UNIT_COMBAT = OnUnitCombat
handlers.UNIT_SPELLCAST_SUCCEEDED = OnSpellcastSucceeded

frame:RegisterEvent('ADDON_LOADED')
frame:SetScript('OnEvent', function(_, event, ...)
  local handler = handlers[event]
  if handler then
    handler(...)
  end
end)
