# BodyCount v0.3.0 - Encounter Ledger (Classic Era)

`/bc` opens Recent / This Session / Last Session / Lifetime tabs. `/bc status` prints totals. `/bc reset` centers the window.

A credited kill requires observed PARTY_KILL. An assist requires observed death and a denied tap. Uncertain deaths remain unknown. Damage comes from player/pet combat events. Ended-but-not-dead encounters become unfinished after 25 seconds without an outgoing damaging event.

Lifetime damage and kills from old versions are preserved; encounter and assist counters begin with this version. Current and last session preserve up to 500 recent encounter summaries while all session totals accumulate. Session rotation occurs on logout/login, not UI reload. Creature types are sampled while units are visible. The type filter cycles via button and currently shows Other for legacy records with no type.

This package is statically validated but requires an in-game Classic Era test before being considered production-ready.
