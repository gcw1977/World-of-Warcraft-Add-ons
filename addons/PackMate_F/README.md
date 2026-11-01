# PackMate Forever — 0.1.0-dev.1

**Development candidate only. NOT_TESTED in World of Warcraft: Forever.**
Independent implementation; Classic remains under addons/PackMate_C.
The historical, unrecoverable 0.4.0-dev03.1 prototype is not this build.

## Installation and interface

Repository source lives at addons/PackMate_F; the ZIP's actual WoW addon directory is PackMate so the game can load PackMate.toc. The provisional TOC interface number is **16001** from earlier beta documentation, NOT confirmed for launch. Verify the live client interface before testing. Do not replace an installed known-good addon or existing SavedVariables without a backup.

## HUD

Two compact graphical rows: upper XP progress when a valid current/required XP pair is available; lower loyalty bar deliberately neutral/nonquantitative because a numerical loyalty scale is not verified. The frame border follows happiness green/yellow/red or neutral unknown. Hover for pet identity, numeric XP, loyalty description, training points if supported, observed XP total, and unavailable explanations. Drag to move; lower-right grip to resize. Free-floating by default; no protected pet-frame anchoring.

## Commands

/pm, /packmate, /petledger (aliases registered only when not already claimed).

/pm help, /pm status, /pm diag, /pm show, /pm hide, /pm reset, /pm sassy, /pm stoic, /pm mute, /pm xp on, /pm xp off.

Reset changes only geometry and visibility, never statistics. Mute blocks automatic notices but not explicit command replies. Sassy content reminders are scheduled at +30/+60 seconds and unhappy reminders at +60/+180 seconds, with stale stages discarded. The initial happiness observation is silent.

## Data and safety

Uses only PackMateForeverDatabase, partitioned by player GUID and pet GUID; no automatic Classic import. XP is an **observed increase**, never proven per-kill credit. First observation and level gaps do not fabricate XP. Invalid database input is preserved untouched, with session-only fallback. Pet GUID or character identity unavailable means no persistent ledger mutation. All Forever runtime behavior, APIs, events, protected UI interactions and saved-variable persistence require owner-led field tests.

No BI Core dependency; optional OpenPackMateStatusHud() opens the micro-HUD.

## Version lineage

New Forever line begins at 0.1.0-dev.1. Every distinct packaged candidate receives a new prerelease number. No stable release or tag has been approved.
