-- howudoin settings window (Game Menu > Options > AddOns > howudoin, or just type /howudoin).
--
-- Every control reads and writes howudoinCharSettings directly, so the window and the slash
-- commands always agree. The panel is built the first time it is shown (not at load), because by
-- then the saved settings are guaranteed to exist.

local _, ns = ...

local PANEL_NAME = 'howudoin'
local ICON_PATH = 'Interface\\AddOns\\howudoin\\icon.png'
local RECORDS_SHOWN = 5
local CONFIRM_SECONDS = 4

local panel, category
local built = false
local refreshing = false -- true while we push saved values into the controls
local refreshers = {}

local function Settings_()
  return howudoinCharSettings
end

-- Widgets ----------------------------------------------------------------------------------------

local function AddTooltip(widget, title, text)
  widget:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(text, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  widget:SetScript('OnLeave', function()
    GameTooltip:Hide()
  end)
end

local function Section(parent, title, y)
  local label = parent:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
  label:SetPoint('TOPLEFT', parent, 'TOPLEFT', 16, y)
  label:SetText(title)

  local line = parent:CreateTexture(nil, 'ARTWORK')
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetHeight(1)
  line:SetPoint('TOPLEFT', label, 'BOTTOMLEFT', 0, -4)
  line:SetPoint('RIGHT', parent, 'RIGHT', -16, 0)
  return y - 28
end

-- A labelled checkbox bound to one saved setting. Returns the next free y and the checkbox.
local function Checkbox(parent, y, indent, label, tooltip, key)
  local check = CreateFrame('CheckButton', nil, parent, 'UICheckButtonTemplate')
  check:SetSize(26, 26)
  check:SetPoint('TOPLEFT', parent, 'TOPLEFT', 16 + indent, y)

  local text = parent:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
  text:SetPoint('LEFT', check, 'RIGHT', 4, 1)
  text:SetText(label)
  check.label = text

  check:SetScript('OnClick', function(self)
    Settings_()[key] = self:GetChecked() and true or false
    ns.RefreshOptions()
  end)
  AddTooltip(check, label, tooltip)

  refreshers[#refreshers + 1] = function()
    check:SetChecked(Settings_()[key] and true or false)
  end
  return y - 28, check
end

local function SetCheckEnabled(check, enabled)
  check:SetEnabled(enabled)
  if enabled then
    check.label:SetTextColor(1, 1, 1)
  else
    check.label:SetTextColor(0.5, 0.5, 0.5)
  end
end

-- A 0-100 slider built from plain textures so it does not depend on any Blizzard slider template.
local function ToleranceSlider(parent, y)
  local title = parent:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
  title:SetPoint('TOPLEFT', parent, 'TOPLEFT', 48, y)
  title:SetText('How close to your best counts:')

  local value = parent:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
  value:SetPoint('LEFT', title, 'RIGHT', 8, 0)

  local slider = CreateFrame('Slider', nil, parent)
  slider:SetOrientation('HORIZONTAL')
  slider:SetSize(260, 16)
  slider:SetPoint('TOPLEFT', parent, 'TOPLEFT', 52, y - 26)
  slider:SetMinMaxValues(0, 100)
  slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then
    slider:SetObeyStepOnDrag(true)
  end

  local track = slider:CreateTexture(nil, 'BACKGROUND')
  track:SetColorTexture(0.3, 0.3, 0.3, 0.9)
  track:SetHeight(4)
  track:SetPoint('LEFT', slider, 'LEFT', 0, 0)
  track:SetPoint('RIGHT', slider, 'RIGHT', 0, 0)

  slider:SetThumbTexture('Interface\\Buttons\\UI-SliderBar-Button-Horizontal')
  local thumb = slider:GetThumbTexture()
  if thumb then
    thumb:SetSize(20, 20)
  end

  local hint = parent:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  hint:SetPoint('TOPLEFT', slider, 'BOTTOMLEFT', 0, -6)
  hint:SetText('0% = only new records play.  Damage rolls vary, so 10-15% is a good start.')

  slider:SetScript('OnValueChanged', function(_, newValue)
    newValue = math.floor(newValue + 0.5)
    value:SetText(newValue .. '%')
    if not refreshing then
      Settings_().BEST_TOLERANCE = newValue
    end
  end)
  AddTooltip(slider, 'Tolerance', 'A crit plays if it is at least this close to your best crit with that spell.')

  refreshers[#refreshers + 1] = function()
    slider:SetValue(Settings_().BEST_TOLERANCE or 5)
    value:SetText((Settings_().BEST_TOLERANCE or 5) .. '%')
  end
  return y - 74
end

local function Button(parent, text, width, x, y, onClick)
  local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
  button:SetSize(width, 24)
  button:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
  button:SetText(text)
  button:SetScript('OnClick', onClick)
  return button
end

-- The panel -------------------------------------------------------------------------------------

local recordsText

local function Refresh()
  refreshing = true
  for _, refresh in ipairs(refreshers) do
    refresh()
  end
  refreshing = false

  if recordsText then
    local list = ns.GetSortedRecords()
    if #list == 0 then
      recordsText:SetText('No crits recorded yet. Go land some!')
    else
      local lines = {}
      for i = 1, math.min(#list, RECORDS_SHOWN) do
        lines[#lines + 1] = string.format('%s  -  %.0f', list[i].name or '?', list[i].amount)
      end
      if #list > RECORDS_SHOWN then
        lines[#lines + 1] = string.format('...and %d more (/howudoin records)', #list - RECORDS_SHOWN)
      end
      recordsText:SetText(table.concat(lines, '\n'))
    end
  end
end

local function Build()
  if built then
    return
  end
  built = true

  -- Header
  local icon = panel:CreateTexture(nil, 'ARTWORK')
  icon:SetSize(44, 44)
  icon:SetPoint('TOPLEFT', panel, 'TOPLEFT', 16, -16)
  icon:SetTexture(ICON_PATH)

  local title = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
  title:SetPoint('TOPLEFT', icon, 'TOPRIGHT', 10, -2)
  title:SetText(ns.ADDON_TITLE .. '  |cFF9BDBF5v' .. ns.ADDON_VERSION .. '|r')

  local subtitle = panel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
  subtitle:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -4)
  subtitle:SetText('Plays a random howudoin when you land a crit!  Detection: ' ..
    (ns.HAS_COMBAT_LOG and 'combat log' or 'unit events (no combat log on this client)'))

  local y = -80

  -- Sounds
  y = Section(panel, 'Sounds', y)
  local check
  y = Checkbox(panel, y, 0, 'Play on weapon (white) crits',
    'Also play the sound for auto-attack crits, not just spells and abilities.', 'TRIGGER_ON_SWING')
  if not ns.HAS_COMBAT_LOG then
    y, check = Checkbox(panel, y, 24, 'Only while solo',
      'Without a combat log, other melee players in your group can be mistaken for you. With this on, auto-attack crits only play when you are not in a party or raid.',
      'SWING_SOLO_ONLY')
    local swingCheck = check
    refreshers[#refreshers + 1] = function()
      SetCheckEnabled(swingCheck, Settings_().TRIGGER_ON_SWING and true or false)
    end
  end
  y = Checkbox(panel, y, 0, 'Finisher sound on killing blows',
    'Play a different sound when your crit finishes off the target (overkill on the combat log, a kill on clients without one).', 'FINISHER_ON_OVERKILL')
  y = Checkbox(panel, y, 0, 'Throttle sounds (' .. ns.THROTTLE_SECONDS .. ' second cooldown)',
    'Limit how often a sound can play. Helps with melee classes and area damage.', 'THROTTLE_SOUNDS')

  -- Best-crit filter
  y = y - 8
  y = Section(panel, 'Best-crit filter', y)
  y = Checkbox(panel, y, 0, 'Only play for crits close to my best',
    'Each spell keeps its own record. A crit only plays if it is within the tolerance below of that record. A new record always plays.', 'BEST_CRIT_ONLY')
  y = ToleranceSlider(panel, y)

  -- Records
  local recordsHeader = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
  recordsHeader:SetPoint('TOPLEFT', panel, 'TOPLEFT', 16, y)
  recordsHeader:SetText('Your best crits')
  recordsText = panel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
  recordsText:SetPoint('TOPLEFT', recordsHeader, 'BOTTOMLEFT', 0, -6)
  recordsText:SetJustifyH('LEFT')
  recordsText:SetWidth(420)
  y = y - 20 - (RECORDS_SHOWN + 1) * 13 - 12

  -- Buttons
  Button(panel, 'Test sound', 100, 16, y, function() ns.PlayRandomHowudoin() end)
  Button(panel, 'Test finisher', 100, 122, y, function() ns.PlayFinisher() end)

  local confirming = false
  local resetButton
  resetButton = Button(panel, 'Reset records', 120, 228, y, function()
    if not confirming then
      confirming = true
      resetButton:SetText('Click to confirm')
      C_Timer.After(CONFIRM_SECONDS, function()
        confirming = false
        resetButton:SetText('Reset records')
      end)
      return
    end
    confirming = false
    resetButton:SetText('Reset records')
    ns.ResetRecords()
    Refresh()
  end)
  resetButton:SetWidth(130)
end

-- Public hooks used by main.lua ---------------------------------------------------------------

function ns.RefreshOptions()
  if built then
    Refresh()
  end
end

-- Returns true if the window was opened.
function ns.OpenOptions()
  if not category then
    return false
  end
  local ok = pcall(Settings.OpenToCategory, category:GetID())
  return ok
end

function ns.InitOptions()
  -- Both Classic Era (1.15.4+) and Forever have the Settings API; anything older just keeps the
  -- slash commands.
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end

  panel = CreateFrame('Frame')
  panel.name = PANEL_NAME
  panel:Hide()
  panel:SetScript('OnShow', function()
    Build()
    Refresh()
  end)

  -- The "Defaults" button in the Settings window resets the settings (not your records).
  panel.OnDefault = function()
    for key, default in pairs(ns.DEFAULTS) do
      Settings_()[key] = default
    end
    Refresh()
  end

  local ok, result = pcall(Settings.RegisterCanvasLayoutCategory, panel, PANEL_NAME)
  if not ok or not result then
    return
  end
  category = result
  Settings.RegisterAddOnCategory(category)
end
