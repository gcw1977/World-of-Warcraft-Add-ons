# CODE RED — SOURCE RESCUE PROTOCOL
Effective 2026-11-01. Mandatory for all Beestwood Industries code-producing agents, construction tasks, remediation tasks, packaging tasks, and any mission producing source or build artifacts.

## Immediate distress condition
At the first confirmed failure to upload, commit, or otherwise durably preserve generated source or package artifacts, interrupt ordinary mission workflow. Stop long reports, optional testing, repeated attempts via the failing transfer path, and nonessential work. Switch priority to preserving as much complete source as possible before the execution environment ends.

## Rescue order
1. Try a different available durable direct-write path once (prefer a verified GitHub source commit).
2. If an upload/transfer bridge is unavailable, write text source directly to the project's writable permanent report storage, one original file per independent text asset where possible. Prefer raw plain-text files (.lua, .toc, .xml, .md, etc.); when raw text file creation is unsupported, write plain source as Google Docs text, one source file per document.
3. Preserve executable modules and loading manifest/TOC first. Then rescue all remaining source, configuration, tests, and supporting text. Save files incrementally rather than keeping all unsaved until the end.
4. Chunk long files into ordered pieces if necessary. Preserve their exact content and numbering. Do not introduce markdown fences, smart punctuation or unintended formatting.
5. Keep a tiny recovery index: original paths, durable links, chunk order, expected sizes/hashes if available, and verified/missing status. Verify by fetching saved source where possible.
6. If time/storage fails, deliver surviving code and plainly identify missing files. Never substitute a narrative or hash-only report for source.

## Status gate
A mission cannot declare a successful, completed build without retrievable, verified complete source and a preserved version identity. A recovered partial code dump is an emergency salvage result, not a completed build. Only owner approval authorizes promotion to stable/release, and historical records are never silently renumbered.

## Operational priority
CODE > custody verification > minimal recovery index > narrative report. This protocol overrides normal report formatting and AAR verbosity whenever triggered. No agent may exhaust its task writing a polished account of an unsaved source tree.
