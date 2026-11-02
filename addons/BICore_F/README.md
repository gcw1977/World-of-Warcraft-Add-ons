# BI Core Forever — 0.1.0-dev.1 (construction candidate)

**Status:** BUILT CANDIDATE — NOT TESTED IN THE FOREVER CLIENT. No stable release.

Install folder: BICore_F. Slash command: /bicore. Subcommands: show, hide, refresh, reset (window position only). No minimap button. The UI is one movable window and remembers its position in BICoreForeverDB; it never touches other addons' SavedVariables.

Buttons show GREEN only after a loaded, compatible provider reports a complete set of actually performed required FIELD_PASS checks. RED means an observed provider/health failure; GRAY means absent, disabled, unloaded, unavailable, incomplete, stale or unknown. Built-in catalog: PackMate, Litterbug, LootHoarder, ResourceHog, Goblinomicon, BodyCount (parked), Completionist and KitMan. All may initially appear GRAY because BI-DIAG-1 providers are separate addon work.

Copy Report does NOT write to the operating-system clipboard. It selects a frozen report part inside the dashboard; the user presses Ctrl+C. Reports exceeding 4096 bytes are divided into numbered parts; each part must be copied separately. No copied-success message is possible.

## Adding future BI family members without changing Core

An addon can opt in via these TOC fields:

    ## X-BICore-Registration: BI-REG-1
    ## X-BICore-Name: ExampleAddon
    ## X-BICore-Provider: ExampleAddon_GetBeestwoodDiagnosticSnapshot

The provider is an OPTIONAL global function owned by the addon:

    function ExampleAddon_GetBeestwoodDiagnosticSnapshot(detailLevel)
        -- Return a new, read-only BI-DIAG-1 snapshot (SUMMARY or FULL).
        -- Do not perform gameplay actions, migrations, repairs or writes.
    end

BI Core discovers opted-in metadata when /bicore opens and on supported addon-load events. The addon works with Core absent. Alternatively, if Core is already loaded, the addon may call BICore_RegisterAddon({protocolVersion="BI-REG-1", addonIdentifier="ExampleAddon_F", displayName="ExampleAddon", providerFunction=ExampleAddon_GetBeestwoodDiagnosticSnapshot}). Registration is bounded to 64 descriptors and rejects malformed/colliding entries. Addons loaded before Core use metadata discovery. Uninstalled addons cannot self-register.

The snapshot schema is documented in DEV-02 D2: protocolVersion BI-DIAG-1; exact addonIdentifier; targetClientFamily FOREVER; overallHealth; snapshotCompleteness; reportTruncated; requiredChecksCount; checks (checkIdentifier, componentName, requiredForHealthy, outcome, evidenceKind, observedResult, attemptedOperation); optional recentErrors, notes, versions and captureSessionSeconds. Required FIELD_PASS checks and honest evidence are mandatory for GREEN. This interface is not a trust or sandbox boundary: WoW addons share a Lua environment.

## Compatibility and test limitations

The TOC Interface 16001 is PROVISIONAL. Actual Forever launch build, C_AddOns signatures, frame templates, EditBox focus/copy limits, Unicode, SavedVariables behavior and provider adoption are NOT_TESTED. Core never calls LoadAddOn, EnableAddOn or target addon gameplay functions except the explicit optional read-only diagnostic provider. The developer cannot prove that an arbitrary third-party provider has no side effects. Static checks do not establish gameplay compatibility.

Source of record: dedicated GitHub construction branch. No merge, tag, stable release or installation is authorized.
