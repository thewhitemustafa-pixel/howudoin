local ADDON_ID = 'howudoin'
local FINISHER = 'Interface/AddOns/howudoin/finisher/finisher.ogg'
local SOUND_PATH = 'Interface/AddOns/howudoin/sounds/howudoin%d.ogg'
local NUM_SOUNDS = 14
local THROTTLE_SECONDS = 2

-- Forever-only tuning (no combat log, so crits are credited to you by timing):
local FINISHER_CHECK_DELAY = 0.1 -- seconds to wait before checking "did that crit kill / fully heal the target?"
local DUPLICATE_WINDOW = 0.1     -- UNIT_COMBAT can fire once per unit token for the same hit; ignore repeats

-- Cast-buffer / attribution tuning
local ATTRIBUTION_WINDOW   = 1.5  -- legacy fallback window (kept for compatibility); not used by the new path
local MAX_CASTS            = 12   -- buffer size
local CAST_BUFFER_MAX_AGE  = 15   -- seconds before a cast is pruned
local DEDUP_MAX_AGE        = 30   -- seconds before a per-castGUID dedup entry is pruned
local INSTANT_WINDOW       = 0.35 -- tight window after an instant cast
local INSTANT_LOOSE        = 0.75 -- loose window after an instant cast
local CAST_EARLY_SLACK     = 0.15 -- how far before the expected completion time a hit can land
local CAST_LATE_WINDOW     = 0.50 -- minimum window after expected completion (projectile travel)
local CHANNEL_LATE_WINDOW  = 0.50 -- extra window after a channel ends
local HIGH_CONFIDENCE      = 3    -- score needed to attribute a crit to a specific cast

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
  SWING_SOLO_ONLY  = true,  -- only attribute auto-attack crits to you while solo
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

local function ClearTable(tbl)
  for k in pairs(tbl) do
    tbl[k] = nil
  end
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

-- Spell metadata helpers

local function GetSpellName(spellID)
  if type(spellID) ~= 'number' or IsSecret(spellID) then
    return nil
  end
  if C_Spell and C_Spell.GetSpellName then
    return SafeCall(C_Spell.GetSpellName, spellID)
  end
end

local function GetSpellCastTime(spellID)
  if type(spellID) ~= 'number' or IsSecret(spellID) then
    return 0
  end
  if not (C_Spell and C_Spell.GetSpellInfo) then
    return 0
  end
  local info = SafeCall(C_Spell.GetSpellInfo, spellID)
  if not info then
    return 0
  end
  local castTime = info.castTime
  if IsSecret(castTime) or type(castTime) ~= 'number' then
    return 0
  end
  return castTime / 1000
end

-- Cast buffer + attribution scoring (Forever path)

local castBuffer = {}          -- newest-first array of cast records
local lastCritByCastGUID = {}  -- [castGUID] = last crit time, for per-cast dedup
local lastSwingCritTime = 0    -- global dedup for the swing fallback
local inCombat = false
local nextSyntheticCastID = 0

local function PruneCastBuffer()
  local now = GetTime()
  local i = 1
  while i <= #castBuffer do
    if now - castBuffer[i].startTime > CAST_BUFFER_MAX_AGE then
      table.remove(castBuffer, i)
    else
      i = i + 1
    end
  end
  for guid, t in pairs(lastCritByCastGUID) do
    if now - t > DEDUP_MAX_AGE then
      lastCritByCastGUID[guid] = nil
    end
  end
end

local function PushCast(entry)
  PruneCastBuffer()
  if not entry.castGUID then
    nextSyntheticCastID = nextSyntheticCastID + 1
    entry.castGUID = 'synth_' .. nextSyntheticCastID
  end
  table.insert(castBuffer, 1, entry)
  if #castBuffer > MAX_CASTS then
    table.remove(castBuffer)
  end
end

local function FindCastByGUID(castGUID)
  if not castGUID then
    return nil
  end
  for _, cast in ipairs(castBuffer) do
    if cast.castGUID == castGUID then
      return cast
    end
  end
end

-- Score a crit against every buffered cast. Returns (bestScore, bestMatch).
-- score 4 = strong match, 2 = loose match, 1 = weak/borderline, 0 = no match.
local function ScoreCrit(unit, now)
  local unitGUID = SafeCall(UnitGUID, unit)
  local bestScore, bestMatch = 0, nil

  for _, cast in ipairs(castBuffer) do
    -- Target check: if we know which unit the cast was aimed at, the crit must land on it.
    if cast.targetGUID and unitGUID and cast.targetGUID ~= unitGUID then
      goto continue
    end

    local age = now - cast.startTime
    local score = 0

    if cast.isChannel then
      -- Channels/empowers can tick at any point between start and end.
      if age >= -0.2 and age <= cast.castTime + CHANNEL_LATE_WINDOW then
        score = 4
      elseif age >= -0.5 and age <= cast.castTime + 1.0 then
        score = 2
      end
    elseif cast.castTime == 0 then
      -- Instant casts land almost immediately.
      if age >= -0.2 and age <= INSTANT_WINDOW then
        score = 4
      elseif age >= 0 and age <= INSTANT_LOOSE then
        score = 2
      end
    else
      -- Cast-time spells land near start + castTime + projectile travel.
      local expected = cast.castTime
      local lateWindow = math.max(CAST_LATE_WINDOW, expected * 0.25)
      if age >= expected - CAST_EARLY_SLACK and age <= expected + lateWindow then
        score = 4
      elseif age >= expected and age <= expected + 1.0 then
        score = 2
      end
      -- If the cast hasn't completed yet, it can't have produced a hit (non-channel).
      if not cast.confirmed and age < cast.castTime then
        score = 0
      end
    end

    if score > bestScore then
      bestScore = score
      bestMatch = cast
    end

    ::continue::
  end

  return bestScore, bestMatch
end

local function DumpCastBuffer()
  if #castBuffer == 0 then
    printHowudoin('cast buffer: (empty)')
    return
  end
  local now = GetTime()
  printHowudoin('cast buffer (' .. #castBuffer .. ' entries):')
  for i, c in ipairs(castBuffer) do
    print(format('  [%d] spell=%s castGUID=%s tgt=%s age=%.2fs ct=%.2fs ch=%s em=%s cf=%s',
      i,
      tostring(c.spellID),
      tostring(c.castGUID),
      tostring(c.targetGUID),
      now - c.startTime,
      c.castTime,
      tostring(c.isChannel),
      tostring(c.isEmpower),
      tostring(c.confirmed)))
  end
end

-- Backend 1: combat log (Classic Era / TBC / MoP Classic). Unchanged from the original.

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

-- Backend 2: unit events (WoW: Forever). We can't read the combat log, so we correlate UNIT_COMBAT
-- crits against a buffer of the casts the player has recently made. A crit is credited to the player
-- only when it lines up with a specific cast on a specific target at a time consistent with that
-- spell's cast time.

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

-- Record key + display name for a crit credited to a specific cast (or to your auto attack).
local function SpellKey(kind, spellID)
  if type(spellID) ~= 'number' or IsSecret(spellID) then
    return kind .. ':unknown', kind == 'heal' and 'Heals' or 'Damage spells'
  end
  local name = GetSpellName(spellID)
  return kind .. ':' .. spellID, name or ('Spell ' .. spellID)
end

-- UNIT_SPELLCAST_SENT: fires when the player begins casting. Arg 1 is the unit the cast is aimed at
-- (a token like "target" or "focus"), which we save so the crit has to land on the intended unit.
local function OnSpellcastSent(unitTarget, castGUID, spellID)
  local targetGUID = unitTarget and SafeCall(UnitGUID, unitTarget) or nil
  PushCast({
    spellID = spellID,
    castGUID = castGUID,
    targetGUID = targetGUID,
    startTime = GetTime(),
    castTime = GetSpellCastTime(spellID),
    isChannel = false,
    isEmpower = false,
    confirmed = false,
  })
  if debugMode then
    printHowudoin('SENT', spellID, castGUID, 'target=' .. tostring(targetGUID))
  end
end

local function OnSpellcastSucceeded(_, castGUID, spellID)
  local existing = FindCastByGUID(castGUID)
  if existing then
    existing.confirmed = true
    existing.succeededAt = GetTime()
    if debugMode then
      printHowudoin('SUCCEEDED', spellID, castGUID, '(confirmed)')
    end
    return
  end
  -- No SENT record (some procs / instants never fire SENT). Reconstruct using the spell's cast time.
  local castTime = GetSpellCastTime(spellID)
  local now = GetTime()
  PushCast({
    spellID = spellID,
    castGUID = castGUID,
    targetGUID = SafeCall(UnitGUID, 'target'),
    startTime = now - castTime,
    castTime = castTime,
    isChannel = false,
    isEmpower = false,
    confirmed = true,
    succeededAt = now,
  })
  if debugMode then
    printHowudoin('SUCCEEDED', spellID, castGUID, '(fallback, no SENT)')
  end
end

local function OnChannelStart(_, castGUID, spellID)
  local existing = FindCastByGUID(castGUID)
  if existing then
    existing.isChannel = true
  else
    PushCast({
      spellID = spellID,
      castGUID = castGUID,
      targetGUID = SafeCall(UnitGUID, 'target'),
      startTime = GetTime(),
      castTime = GetSpellCastTime(spellID),
      isChannel = true,
      isEmpower = false,
      confirmed = true,
    })
  end
  if debugMode then
    printHowudoin('CHANNEL_START', spellID, castGUID)
  end
end

local function OnEmpowerStart(_, castGUID, spellID)
  local existing = FindCastByGUID(castGUID)
  if existing then
    existing.isEmpower = true
  else
    PushCast({
      spellID = spellID,
      castGUID = castGUID,
      targetGUID = SafeCall(UnitGUID, 'target'),
      startTime = GetTime(),
      castTime = GetSpellCastTime(spellID),
      isChannel = false,
      isEmpower = true,
      confirmed = true,
    })
  end
  if debugMode then
    printHowudoin('EMPOWER_START', spellID, castGUID)
  end
end

local function OnUnitCombat(unit, action, flagText, amount, schoolMask)
  if debugMode then
    printHowudoin('UNIT_COMBAT', 'unit=' .. DebugValue(unit), 'action=' .. DebugValue(action),
      'flag=' .. DebugValue(flagText), 'amount=' .. DebugValue(amount), 'school=' .. DebugValue(schoolMask))
  end

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

  if isHeal then
    if SafeCall(UnitCanAssist, 'player', unit) == false then
      return
    end
  else
    if unit ~= 'target' then
      return
    end
    if SafeCall(UnitCanAttack, 'player', unit) == false then
      return
    end
  end

  local now = GetTime()
  local score, matchedCast = ScoreCrit(unit, now)
  local key, name

  if score >= HIGH_CONFIDENCE and matchedCast then
    -- High-confidence match: this crit lines up with a specific cast.
    key, name = SpellKey(isHeal and 'heal' or 'dmg', matchedCast.spellID)
    local lastCrit = lastCritByCastGUID[matchedCast.castGUID] or 0
    if now - lastCrit < DUPLICATE_WINDOW then
      if debugMode then
        printHowudoin('dedup: crit for castGUID ' .. tostring(matchedCast.castGUID) .. ' too soon, skipping')
      end
      return
    end
    lastCritByCastGUID[matchedCast.castGUID] = now
    if debugMode then
      printHowudoin('attributed to cast', matchedCast.spellID, 'score=' .. score)
    end

  elseif (not isHeal) and IsAutoAttacking() and howudoinCharSettings.TRIGGER_ON_SWING then
    -- No cast match at all: could be an auto-attack. Gate by group state because in groups another
    -- melee player could be the source.
    local inGroup = SafeCall(IsInGroup) == true or SafeCall(IsInRaid) == true
    if inGroup and howudoinCharSettings.SWING_SOLO_ONLY then
      if debugMode then
        printHowudoin('swing: in group, SWING_SOLO_ONLY on -> skipping (score=' .. score .. ')')
      end
      return
    end
    if now - lastSwingCritTime < DUPLICATE_WINDOW then
      return
    end
    lastSwingCritTime = now
    key, name = 'swing', 'Auto Attack'
    if debugMode then
      printHowudoin('attributed to auto-attack (score=' .. score .. ')')
    end

  else
    -- score is 1-2 (weak match, likely another player) or 0 with no valid alternative.
    if debugMode then
      printHowudoin('rejected: score=' .. score, 'isHeal=' .. tostring(isHeal))
    end
    return
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
  swingsolo = {
    key = 'SWING_SOLO_ONLY',
    on = function() return 'Only attribute auto-attack crits to you while solo (avoids other players in groups).' end,
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
    printHowudoin('-- Debug output (best-crit decisions' .. (HAS_COMBAT_LOG and '' or ', UNIT_COMBAT events, cast buffer') .. ').', formatSetting(debugMode))
  elseif command == 'buffer' then
    DumpCastBuffer()
  else
    PlayRandomHowudoin()
    printHowudoin('Config')
    print('  Plays a random howudoin when you land a crit!')
    print('  Mode: ' .. (HAS_COMBAT_LOG and 'combat log' or 'unit events (no combat log available)') .. '|n')
    print('/howudoin swing|n-- Toggle - Sound triggers on Weapon(White) crits.', 'Currently', formatSetting(settings.TRIGGER_ON_SWING))
    print('/howudoin swingsolo|n-- Toggle - Only credit auto-attack crits to you while solo.', 'Currently', formatSetting(settings.SWING_SOLO_ONLY))
    print('/howudoin overkill|n-- Toggle - Different howudoin sound for finishing crits (overkill / killing blow).', 'Currently', formatSetting(settings.FINISHER_ON_OVERKILL))
    print('/howudoin throttle|n-- Toggle - Sets a ' .. THROTTLE_SECONDS .. ' second cooldown on sounds playing (Helps reduce spam for melee classes and for AOE).', 'Currently', formatSetting(settings.THROTTLE_SOUNDS))
    print('/howudoin best|n-- Toggle - Only play for crits close to your best crit with that spell.', 'Currently', formatSetting(settings.BEST_CRIT_ONLY))
    print('/howudoin tolerance <0-100>|n-- How close to your best counts, in percent (0 = new records only).', 'Currently', settings.BEST_TOLERANCE .. '%')
    print('/howudoin records|n-- Show your best crits.')
    print('/howudoin reset|n-- Clear your crit records.')
    print('/howudoin buffer|n-- Dump the current cast buffer (for troubleshooting).')
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
    -- Forever: build a small cast timeline and match crits against it.
    frame:RegisterEvent('UNIT_COMBAT')
    frame:RegisterEvent('UNIT_SPELLCAST_SENT')
    frame:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
    frame:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_START', 'player')
    frame:RegisterUnitEvent('UNIT_SPELLCAST_EMPOWER_START', 'player')
    frame:RegisterEvent('PLAYER_REGEN_DISABLED')
    frame:RegisterEvent('PLAYER_REGEN_ENABLED')
  end
end
handlers.COMBAT_LOG_EVENT_UNFILTERED = OnCombatLog
handlers.UNIT_COMBAT = OnUnitCombat
handlers.UNIT_SPELLCAST_SENT = OnSpellcastSent
handlers.UNIT_SPELLCAST_SUCCEEDED = OnSpellcastSucceeded
handlers.UNIT_SPELLCAST_CHANNEL_START = OnChannelStart
handlers.UNIT_SPELLCAST_EMPOWER_START = OnEmpowerStart
handlers.PLAYER_REGEN_DISABLED = function()
  inCombat = true
end
handlers.PLAYER_REGEN_ENABLED = function()
  inCombat = false
  ClearTable(castBuffer)
  ClearTable(lastCritByCastGUID)
end

frame:RegisterEvent('ADDON_LOADED')
frame:SetScript('OnEvent', function(_, event, ...)
  local handler = handlers[event]
  if handler then
    handler(...)
  end
end)