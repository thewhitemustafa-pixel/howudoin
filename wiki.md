# howudoin — User Guide

Welcome to **howudoin**, the addon that celebrates your critical hits with a random *howudoin*.

This guide covers everyday use, settings, crit records, and troubleshooting.

For installation instructions, supported clients, and project details, see the [README](README.md).

## Getting Started

After installing the addon and restarting the game, type:

`/howudoin`

This opens the settings window. Use its sound-test controls to confirm that audio files load. If the settings window cannot open on your client, the addon falls back to text help and plays a sample sound.

**A successful sound test confirms that audio playback works.** It does not guarantee that crit detection is working; sound testing is independent of combat detection.

By default:

- Critical damage, healing, and weapon swings can trigger a sound.
- Finishing crits use a separate sound.
- Sounds are not throttled.
- All crits are eligible to play, subject to the detection limitations of your client.
- Your crit records are tracked even when the best-crit filter is disabled.

Settings and records are saved separately for each character.

## Commands

All commands begin with `/howudoin`. Commands that toggle a setting switch it between enabled and disabled each time you use them.

| Command | What it does | Default |
| --- | --- | --- |
| `/howudoin` | Open the settings window (or fall back to text help and a sample sound) | — |
| `/howudoin swing` | Toggle sounds for weapon (white) crits | On |
| `/howudoin swingsolo` | On Forever, only attribute auto-attack crits while solo | On |
| `/howudoin overkill` | Toggle the special finisher sound | On |
| `/howudoin throttle` | Toggle the two-second sound cooldown | Off |
| `/howudoin best` | Toggle the best-crit filter | Off |
| `/howudoin tolerance 10` | Set the best-crit tolerance to 10% | 5% |
| `/howudoin records` | Show your ten highest recorded crits | — |
| `/howudoin buffer` | Show the recent casts tracked by Forever attribution | — |
| `/howudoin reset` | Clear all crit records | — |
| `/howudoin debug` | Toggle diagnostic output | Off |
| `/howudoin help` | Print command help in chat and play a sample sound | — |

### Weapon crits: `swing`

Use `/howudoin swing` to enable or disable sounds for ordinary weapon swings.

This setting affects auto-attack crits. It does not disable crit sounds from spells and abilities.

### Finisher sounds: `overkill`

Use `/howudoin overkill` to toggle the special sound for finishing crits.

On Classic Era, the addon uses the combat log's overkill information. On WoW: Forever, it checks whether the target dies after a critical hit.

These methods are not equivalent, so finisher behavior can differ between clients.

### Sound cooldown: `throttle`

Use `/howudoin throttle` to enable or disable a two-second cooldown between sounds.

When enabled, the cooldown is shared by regular and finisher sounds. A sound of either type can prevent another from playing during the cooldown.

This is particularly useful for fast-attacking characters and situations with many simultaneous targets.

### Best-crit filter: `best`

Use `/howudoin best` to enable or disable the best-crit filter.

When enabled, the addon only plays sounds for crits that meet your configured tolerance relative to the highest recorded crit for that spell. New records always qualify.

See [Understanding Crit Records](#understanding-crit-records) for details.

## Understanding Crit Records

howudoin keeps a record of your highest observed crits. Records are saved per character and continue updating even while the best-crit filter is turned off.

### Setting the tolerance

Use:

`/howudoin tolerance 10`

The number is a percentage from 0 to 100. It determines how far below your recorded best a crit can fall and still qualify for a sound.

For example, suppose your highest recorded Fireball crit is 1,000.

| New Fireball crit | 5% tolerance | Result |
| --- | --- | --- |
| 1,200 | — | Plays; new record |
| 1,000 | 950 minimum | Plays |
| 960 | 950 minimum | Plays |
| 950 | 950 minimum | Plays |
| 940 | 950 minimum | Skipped |

The minimum qualifying value is calculated as:

`Recorded best × (1 − tolerance / 100)`

A tolerance of 0 means **record-level crits only**: a crit must equal or exceed your previous best. Ties qualify; the crit does not have to set a strictly higher record.

### Records are tracked separately

- **Different spells:** Fireball and Frostbolt have separate records.
- **Different ranks:** Spell ranks with different spell IDs have separate records.
- **Healing and damage:** Healing records are separate from damage records.
- **Auto-attacks:** Weapon crits have their own record.

On WoW: Forever, spell attribution is less reliable because the game does not provide the same combat-log information. A record can occasionally be associated with the wrong spell.

### Viewing and resetting records

Use `/howudoin records` to display your ten highest recorded crits.

Use `/howudoin reset` to clear all crit records for the current character.

**Tip:** A single unusually large crit from a cooldown or proc can raise the bar for future crits of that spell. If the filter becomes too selective, increase the tolerance or reset your records.

If the game hides the damage value, the addon cannot measure that crit. Such a crit may still play a sound, but it will not update the record or be filtered by its damage amount.

## Troubleshooting

### No sound at all

1. Type `/howudoin`.
2. Confirm that the sample sound plays.
3. Check that game sound is enabled and audible.
4. Confirm that the `howudoin` folder contains the expected sound files in the `sounds` and `finisher` directories.
5. If you installed the addon while the game was running, restart the game.

If the sample works but crits do not trigger sounds, continue below.

### The sample plays, but crits do not

First, identify which client you are using.

**Classic Era**

The addon uses combat-log events to identify your critical hits. If the sample plays but no crit sounds occur, enable debug output:

`/howudoin debug`

Land a few crits and inspect the output for errors or unexpected behavior. Include relevant output in a bug report.

**WoW: Forever**

The addon uses unit-combat events because it cannot rely on the Classic combat-log path.

It can only evaluate events whose relevant information is available to the addon. If the game hides the event type or other required values, the addon cannot identify the crit. The addon correlates these events with a short buffer of your recent casts, using timing and target information where available.

Try testing outside a dungeon or raid, where combat information may be more accessible. Enable debug output with `/howudoin debug` and inspect the events the addon reports.

If the addon works in the open world but not in an instance, this may be an API restriction rather than a broken installation.

The addon rejects a crit when multiple buffered casts share the same highest attribution score. This can mean a missed sound during overlapping casts, but avoids arbitrarily crediting the crit to one of them. A delayed finisher check also verifies that the affected unit token still identifies the same unit; if that cannot be confirmed, it uses the regular crit sound instead.

### Sounds trigger for another player's crit

This is a known limitation of the WoW: Forever detection method.

The unit-combat event does not identify who caused the critical hit. The addon infers that a crit belongs to you based on your recent casts, your current target, or your auto-attack state.

In a group, another player's spell crit on your target can therefore still be mistaken for yours when it coincides with a recent cast. For auto-attacks, `/howudoin swingsolo` suppresses swing attribution while grouped by default; turning it off accepts a greater risk of false sounds. There is no setting that completely eliminates spell-attribution ambiguity.

### Area-of-effect spells do not behave as expected

On WoW: Forever, damage detection is limited to your current target. Crits against other targets hit by an area spell may not trigger sounds.

The Classic Era combat-log implementation does not have this same current-target limitation.

### Damage sounds play, but the finisher sound does not

On Classic Era, the special sound depends on the combat log reporting overkill damage.

On WoW: Forever, the addon checks whether the target is dead shortly after the crit. This is an approximation, not an exact overkill measurement.

For healing, the addon checks whether the target reaches full health. The game may hide health values during combat, preventing this check from succeeding.

### The best-crit filter skips too many sounds

1. Check your records with `/howudoin records`.
2. Increase the tolerance, for example `/howudoin tolerance 15`.
3. If an unusually large crit is holding the record too high, use `/howudoin reset`.

Remember that records are maintained even while the filter is disabled. On WoW: Forever, incorrect spell attribution can also affect which record is used.

### The addon is marked as out of date

Deal with it. I'll fix it later.

### How to report a bug

When reporting a problem, include:

- Which client you are using: Classic Era or WoW: Forever.
- What you expected to happen and what actually happened.
- Whether `/howudoin` plays its sample sound.
- Whether the problem occurs in the open world, in a group, or in an instance.
- Debug output from `/howudoin debug`, if relevant.

To disable debug output afterward, run `/howudoin debug` again.

## Known Limitations

### Classic Era

Classic Era uses the combat log to identify critical hits and their sources. This is the more reliable detection path.

### WoW: Forever

WoW: Forever uses a best-effort detection method based on unit-combat events. Because the source of a critical hit is not exposed through this event, the addon cannot always determine who caused it.

Expect possible misattribution in groups, incomplete area-of-effect coverage, limitations around pets and damage-over-time effects, and missing detections when combat values are hidden.

These limitations come from the available game API, not from the sound settings.

## Changelog

### 0.2.0

- Rejects equally strong competing cast matches on WoW: Forever instead of choosing one arbitrarily.
- Verifies the target's GUID before classifying a delayed finisher; if the unit identity is unavailable or changed, plays the regular crit sound.
- Clarifies that 0% best-crit tolerance includes ties with the current record.
- Updates command documentation for `swingsolo`, `buffer`, and `help`.

### 0.1.0

- Added WoW: Forever beta support and best-effort cast attribution.
- Added the best-crit filter, crit records, settings window, and troubleshooting commands.

## Need More Information?

See the [README](README.md) for installation, supported clients, customization, and project details.

Happy critting. howudoin
