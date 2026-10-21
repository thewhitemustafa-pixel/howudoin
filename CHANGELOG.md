# Changelog

## 0.2.0

### Improved
- WoW: Forever cast attribution now rejects a crit when multiple buffered casts share the same highest score. This avoids silently crediting the crit to whichever matching cast happens to be visited first.
- Delayed finisher checks now capture the affected unit's GUID and verify that the unit token still refers to that same unit before checking death or health.

### Clarified
- A best-crit tolerance of `0%` means a crit must tie or beat the recorded best. Ties qualify; a strictly higher record is not required.
- README and wiki guidance now describe the current commands and Forever attribution limitations more consistently.

### Notes
- Classic Era's combat-log detection path is unchanged.
- WoW: Forever - Completely refactored crit attribution filtering into robust multi-layer approach
- WoW: Forever - Added best effort deduplication
- WoW: Forever - Combat cast events now log in a buffer matched to casts and target
- WoW: Forever - Added confidence scoring evaluation to reduce false attributions
- WoW: Forever remains best-effort: its unit-combat events do not reliably identify the source of a crit. The new checks reduce avoidable false attribution but cannot make the underlying event source-aware.
- If a finisher check cannot verify the affected unit's identity, the regular crit sound plays instead of the finisher sound.

## 0.1.5
- Added the settings window, addon-list icon, Forever cast matching, swing-solo option, cast-buffer diagnostics, and debug output.
- Fixed healing-finisher handling and sound throttle timing.
- Begun refactor of combat attribution filters

## 0.1.0

- Added WoW: Forever beta support (no combat log required).
- Added the best-crit filter, tolerance setting, crit records, and related commands.
