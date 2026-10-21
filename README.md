# howudoin

Plays a random **"howudoin"** whenever you land a critical hit.

Damage, healing and auto-attacks all count. Crits that finish off a target get their own special sound, and an optional filter keeps the sound for your *best* crits only.

## Features

- **Random sound on every crit.** Picks from 14 clips (`howudoin1.ogg` to `howudoin14.ogg`) for spell damage, heals and weapon swings.
- **Finisher sound.** A different clip plays when a crit finishes the job (overkill damage, or a killing blow on WoW: Forever).
- **Weapon (white) crit toggle.** Turn off the sound for auto-attack crits and keep it for spells and abilities.
- **Throttle.** An optional 2-second cooldown between sounds, to tame melee classes and AoE.
- **Best-crit filter.** Only play for crits within a few percent of your personal best with that spell, so weak crits stay quiet.
- **Crit records.** Tracks your highest crit for every spell and shows them on request.
- **Settings window.** Every option in one place (type `/howudoin`), including your best crits and test buttons.
- **Per-character settings.** Everything is saved per character.
- **Works on Classic Era and the WoW: Forever beta.** The addon picks the right detection method for the client automatically.

## Supported clients

| Client | Interface | How crits are detected |
| --- | --- | --- |
| Classic Era | 11509 | Combat log (exact) |
| WoW: Forever (beta) | 16001 | Unit events (best effort, see [WoW: Forever notes](#wow-forever-notes)) |

Other Classic versions aren't declared in the `.toc`. Add their interface numbers to the `## Interface:` line (comma-separated) if you want to try them. They should use the combat-log path, but those clients are untested.

## Installation

1. Download and extract so the folder is named exactly `howudoin`.
2. Place it in your AddOns folder:
   - Classic Era: `World of Warcraft/_classic_era_/Interface/AddOns/howudoin`
   - Forever beta: `World of Warcraft/_classic_beta_/Interface/AddOns/howudoin`
3. Restart the game (a new addon folder won't appear on `/reload`).

Expected layout:

```
howudoin/
├── howudoin.toc
├── main.lua
├── Options.lua
├── icon.png
├── finisher/
│   └── finisher.ogg
└── sounds/
    ├── howudoin1.ogg
    ├── ...
    └── howudoin14.ogg
```

The file name in `howudoin.toc` must match `main.lua` exactly, including capitalization.

## Commands

Type `/howudoin` to open the settings window. You can also find it under **Options > AddOns > howudoin**. Everything below is also available as a command.

| Command | What it does | Default |
| --- | --- | --- |
| `/howudoin` | Open the settings window | |
| `/howudoin swing` | Toggle: play the sound on weapon (white) crits | On |
| `/howudoin swingsolo` | Toggle: only credit auto-attack crits to you while solo (Forever only) | On |
| `/howudoin overkill` | Toggle: play the finisher sound on crits that finish the target | On |
| `/howudoin throttle` | Toggle: minimum 2 seconds between sounds | Off |
| `/howudoin best` | Toggle: only play for crits close to your best with that spell | Off |
| `/howudoin tolerance <0-100>` | How close to your best counts, in percent. `0` means new records only | 5 |
| `/howudoin records` | Show your best crits (top 10, highest first) | |
| `/howudoin reset` | Clear all crit records | |
| `/howudoin help` | Print this list in chat (and play a sample sound) | |
| `/howudoin buffer` | Print the recent casts the addon is tracking (Forever troubleshooting) | |
| `/howudoin debug` | Toggle troubleshooting output (see [Troubleshooting](#troubleshooting)) | Off |

## Best-crit filter

Every crit you land updates a record for that spell. With the filter on (`/howudoin best`), a crit only plays if it is within the tolerance of your record. A new record always plays.

Example with the default 5% tolerance and a Fireball record of 1000:

| Fireball crit | Result |
| --- | --- |
| 1200 | Plays, new record |
| 960 | Plays (at least 950) |
| 950 | Plays |
| 940 | Skipped |

How it works in detail:

- **Records are per spell.** Frostbolt crits are compared with your best Frostbolt crit, not your best Pyroblast. Auto-attacks count as their own entry, and healing is tracked separately from damage.
- **New ranks start fresh.** A higher spell rank is a different spell and builds its own record.
- **Records are tracked even with the filter off.** If you switch it on later, you already have history to compare against.
- **The filter applies to the finisher sound too.** A weak crit that happens to kill is skipped, like any other weak crit.
- **Tolerance `0` is "records only."** The sound only plays when you beat or tie your best.
- **Damage rolls vary.** Spells and weapons hit for a range, so a tight tolerance is picky. If 5% feels too quiet, try 10 to 15.
- **One lucky crit raises the bar.** A huge crit from a cooldown or proc becomes the record, and normal crits after it may be skipped until you run `/howudoin reset`.
- **If the game hides a crit's damage number, the sound plays as normal.** The addon can't measure it, so it doesn't filter it or record it (see below).

## WoW: Forever notes

WoW: Forever follows Midnight's addon rules: addons have no combat log, and some combat information is hidden from them. howudoin handles this by watching unit combat events, which report that a unit took a crit but not who caused it. It keeps a short record of your recent casts (instant spells, cast-time spells and channels) and credits a crit to you when:

- it lands on your **current target** (damage) or on a **friendly unit** (healing), and
- its timing lines up with one of your recent casts on that target, or, for damage, you are auto-attacking.

Because of that, expect some differences from Classic Era:

- Auto-attack crits only count while you're **solo** by default, because in a group another melee player's crit can't be told apart from yours. Turn that off with `/howudoin swingsolo` if you'd rather accept the occasional false sound.
- Area spells only count on your current target.
- Damage-over-time ticks, pets and totems aren't supported.
- The finisher sound plays when your crit **kills** the target. For heals, it plays when the target ends up at full health, which the game often hides during combat, so heal finishers will rarely trigger.
- If the game hides combat values (for example in some dungeons and raids), crits can't be detected there and you'll hear nothing. If only the damage number is hidden, you'll still hear the sound, but the best-crit filter can't judge it.
- Only physical hits count as auto-attacks, so a pet's or damage-over-time crit can't trigger the white-crit sound.
- Projectiles with more than about a second of travel time can land outside the matching window and stay silent. If a single cast could have caused the hit, a slightly late one is still accepted.

Forever support is based on the beta and may need tuning as the game changes.

## Saved settings

Settings are saved per character in `howudoinCharSettings`:

| Key | Meaning | Default |
| --- | --- | --- |
| `TRIGGER_ON_SWING` | Sound on weapon (white) crits | `true` |
| `SWING_SOLO_ONLY` | Forever only: credit auto-attack crits to you only while solo | `true` |
| `FINISHER_ON_OVERKILL` | Finisher sound on crits that finish the target | `true` |
| `THROTTLE_SOUNDS` | 2-second cooldown between sounds | `false` |
| `BEST_CRIT_ONLY` | Best-crit filter | `false` |
| `BEST_TOLERANCE` | Best-crit tolerance, in percent | `5` |
| `BEST_CRITS` | Your crit records, by spell | empty |

Settings from earlier versions are kept when you update. New options are added with their defaults.

## Customizing

**Replace the sounds.** Put your own `.ogg` files in `sounds/` named `howudoin1.ogg` upward, and set `NUM_SOUNDS` at the top of `main.lua` to match how many you have. The finisher is `finisher/finisher.ogg`.

**Tuning constants** (top of `main.lua`):

| Constant | Default | Meaning |
| --- | --- | --- |
| `THROTTLE_SECONDS` | 2 | Cooldown used by the throttle option |
| `NUM_SOUNDS` | 14 | How many `howudoinN.ogg` files exist |
| `FINISHER_CHECK_DELAY` | 0.1 | Forever only: wait before checking whether the crit killed the target |
| `DUPLICATE_WINDOW` | 0.1 | Forever only: ignores repeat events for the same hit |
| `INSTANT_WINDOW`, `INSTANT_LOOSE`, `CAST_EARLY_SLACK`, `CAST_LATE_WINDOW`, `CHANNEL_LATE_WINDOW`, `HIGH_CONFIDENCE`, `LOOSE_CONFIDENCE`, `UNCONFIRMED_GRACE` | see `main.lua` | Forever only: how closely a crit must line up with one of your casts |

## Troubleshooting

**No sound at all.** Run `/howudoin`. If you hear the sample, the sound files are fine and the problem is detection. If you don't, check that the files are in the right folders and that your game sound is on.

**Sample plays, but crits don't (Forever).** Run `/howudoin debug` and land a few crits. The addon prints each unit combat event it sees (with `<secret>` where the game hides a value) and how it judged each crit against your records. Include that output in a bug report. `/howudoin buffer` lists the casts the addon currently remembers, which helps when a crit is credited to the wrong spell or not at all.

**The filter seems to skip too much.** Raise the tolerance (`/howudoin tolerance 15`), or run `/howudoin records` to check whether one outlier crit is holding a record too high, and `/howudoin reset` if so.

**The addon shows as out of date.** The `## Interface:` line in `howudoin.toc` needs your client's number. Run `/dump select(4, GetBuildInfo())` in game to see it.

## Changelog

### 0.1.0

- Added WoW: Forever beta support (no combat log required).
- New: best-crit filter, tolerance setting, crit records, and the `best`, `tolerance`, `records` and `reset` commands.
- New: settings window (Options > AddOns > howudoin, or `/howudoin`) and an addon list icon.
- New: cast-matching for WoW: Forever, so crits are credited to a specific cast. It ignores failed and interrupted casts, times hits from the moment a cast actually completes (so pushback doesn't matter), and only counts physical hits as auto-attacks.
- New: `/howudoin swingsolo` and `/howudoin buffer`.
- New: `/howudoin debug`.
- Fixed: heal finisher never triggered on overhealing crits.
- Fixed: throttle now has sub-second accuracy, and normal and finisher sounds share one cooldown.
- Fixed: errors when the `.toc` is missing a title or version.
- Changed: `/howudoin` with no arguments now opens the settings window. `/howudoin help` prints the command list.

## Credits

Created by Truetard.
