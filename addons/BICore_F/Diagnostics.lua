-- BICore_F Diagnostics.lua | 0.1.0-dev.1
-- A bounded, read-only bridge. Provider outputs are untrusted data.
local addonIdentifier, addonNamespace = ...
local diagnostics = {}
addonNamespace.Diagnostics = diagnostics
local registry = addonNamespace.Registry
local protocolVersion = "BI-DIAG-1"
local maximumReportBytes = 65536
local allowedOutcomes = {PASS=true, WARN=true, FAIL=true, NOT_TESTED=true, NOT_APPLICABLE=true}
local allowedEvidence = {SOURCE_VERIFIED=true, DOCUMENTED=true, STATIC_PASS=true,
    STATIC_FAIL=true, FIELD_PASS=true, FIELD_FAIL=true, NOT_TESTED=true, UNKNOWN=true}

local function isSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local successful, secret = pcall(issecretvalue, value)
    return not successful or secret == true
end

local function safeText(value, maximumBytes)
    if isSecret(value) or type(value) ~= "string" or #value > maximumBytes then return nil end
    -- No chat formatting, links, control codes, URLs, email addresses or token-like fields.
    if value:find("[%c|<>]") or value:find("://", 1, true)
        or value:find("[%w_.%-]+@[%w_.%-]+")
        or value:lower():find("bearer", 1, true)
        or value:lower():find("password", 1, true)
        or value:lower():find("token", 1, true) then return nil end
    return value
end

local function safeNumber(value)
    return not isSecret(value) and type(value) == "number"
        and value >= 0 and value < math.huge and value == value
end

local function fail(reason)
    return nil, reason or "PROVIDER_MALFORMED"
end

-- Check all provider fields at fixed depth. Do not traverse arbitrary tables.
local function validateSnapshot(rawSnapshot, descriptor)
    if isSecret(rawSnapshot) or type(rawSnapshot) ~= "table" then return fail() end
    if rawSnapshot.protocolVersion ~= protocolVersion then return fail("PROTOCOL_UNSUPPORTED") end
    if rawSnapshot.addonIdentifier ~= descriptor.addonIdentifier then return fail() end
    if rawSnapshot.targetClientFamily ~= "FOREVER"
        and rawSnapshot.targetClientFamily ~= "UNKNOWN" then return fail() end
    if rawSnapshot.snapshotCompleteness ~= "COMPLETE"
        and rawSnapshot.snapshotCompleteness ~= "PARTIAL"
        and rawSnapshot.snapshotCompleteness ~= "UNKNOWN" then return fail() end
    if rawSnapshot.overallHealth ~= "HEALTHY"
        and rawSnapshot.overallHealth ~= "DEGRADED"
        and rawSnapshot.overallHealth ~= "UNKNOWN" then return fail() end
    if type(rawSnapshot.reportTruncated) ~= "boolean" then return fail() end
    if not safeNumber(rawSnapshot.requiredChecksCount)
        or rawSnapshot.requiredChecksCount % 1 ~= 0 then return fail() end
    if rawSnapshot.captureSessionSeconds ~= nil
        and not safeNumber(rawSnapshot.captureSessionSeconds) then return fail() end
    local addonVersion = safeText(rawSnapshot.addonVersion or "UNKNOWN", 80)
    local clientBuild = safeText(rawSnapshot.clientBuildText or "UNKNOWN", 80)
    local providerRevision = safeText(rawSnapshot.providerRevision or "UNKNOWN", 80)
    if not addonVersion or not clientBuild or not providerRevision then return fail() end
    if isSecret(rawSnapshot.checks) or type(rawSnapshot.checks) ~= "table"
        or #rawSnapshot.checks > 128 then return fail() end
    if rawSnapshot.recentErrors ~= nil and
        (isSecret(rawSnapshot.recentErrors) or type(rawSnapshot.recentErrors) ~= "table"
        or #rawSnapshot.recentErrors > 64) then return fail() end
    if rawSnapshot.notes ~= nil and
        (isSecret(rawSnapshot.notes) or type(rawSnapshot.notes) ~= "table"
        or #rawSnapshot.notes > 32) then return fail() end

    local normalizedChecks, normalizedErrors, normalizedNotes = {}, {}, {}
    local seenCheckIdentifiers = {}
    local actualRequiredCount = 0
    local hasFailure, hasUnknown = false, false
    for checkIndex, rawCheck in ipairs(rawSnapshot.checks) do
        if isSecret(rawCheck) or type(rawCheck) ~= "table" then return fail() end
        local checkIdentifier = safeText(rawCheck.checkIdentifier, 96)
        local componentName = safeText(rawCheck.componentName or "UNKNOWN", 96)
        local observedResult = safeText(rawCheck.observedResult or "UNKNOWN", 256)
        local attemptedOperation = safeText(rawCheck.attemptedOperation or "UNKNOWN", 256)
        if not checkIdentifier or not componentName or not observedResult
            or not attemptedOperation or seenCheckIdentifiers[checkIdentifier]
            or not allowedOutcomes[rawCheck.outcome]
            or not allowedEvidence[rawCheck.evidenceKind]
            or type(rawCheck.requiredForHealthy) ~= "boolean" then return fail() end
        if rawCheck.observedAtSessionSeconds ~= nil
            and not safeNumber(rawCheck.observedAtSessionSeconds) then return fail() end
        seenCheckIdentifiers[checkIdentifier] = true
        normalizedChecks[#normalizedChecks + 1] = {
            checkIdentifier = checkIdentifier, componentName = componentName,
            observedResult = observedResult, attemptedOperation = attemptedOperation,
            outcome = rawCheck.outcome, evidenceKind = rawCheck.evidenceKind,
            requiredForHealthy = rawCheck.requiredForHealthy,
        }
        if rawCheck.requiredForHealthy then
            actualRequiredCount = actualRequiredCount + 1
            if rawCheck.outcome == "FAIL" or rawCheck.outcome == "WARN" then
                hasFailure = true
            elseif rawCheck.outcome == "PASS" then
                if rawCheck.evidenceKind ~= "FIELD_PASS" then hasUnknown = true end
            elseif rawCheck.outcome == "NOT_APPLICABLE" then
                if rawCheck.evidenceKind ~= "FIELD_PASS"
                    or observedResult == "UNKNOWN" then hasUnknown = true end
            else
                hasUnknown = true
            end
        elseif rawCheck.outcome == "FAIL" then
            hasFailure = true
        elseif rawCheck.outcome == "WARN" then
            hasUnknown = true
        end
    end
    if actualRequiredCount ~= rawSnapshot.requiredChecksCount then return fail() end
    if actualRequiredCount == 0 then hasUnknown = true end
    for _, rawError in ipairs(rawSnapshot.recentErrors or {}) do
        if isSecret(rawError) or type(rawError) ~= "table" then return fail() end
        local errorIdentifier = safeText(rawError.errorIdentifier, 96)
        local componentName = safeText(rawError.componentName or "UNKNOWN", 96)
        local message = safeText(rawError.sanitizedMessage or "REDACTED", 512)
        if not errorIdentifier or not componentName or not message
            or (rawError.severity ~= "WARN" and rawError.severity ~= "FAIL") then return fail() end
        normalizedErrors[#normalizedErrors + 1] = {
            errorIdentifier = errorIdentifier, componentName = componentName,
            sanitizedMessage = message, severity = rawError.severity,
        }
        if rawError.severity == "FAIL" then hasFailure = true else hasUnknown = true end
    end
    for _, rawNote in ipairs(rawSnapshot.notes or {}) do
        local note = safeText(rawNote, 256)
        if not note then return fail() end
        normalizedNotes[#normalizedNotes + 1] = note
    end
    if rawSnapshot.overallHealth == "DEGRADED" then hasFailure = true end
    if rawSnapshot.snapshotCompleteness ~= "COMPLETE"
        or rawSnapshot.reportTruncated or rawSnapshot.targetClientFamily ~= "FOREVER" then
        hasUnknown = true
    end
    return {
        addonVersion = addonVersion, clientBuild = clientBuild,
        providerRevision = providerRevision, checks = normalizedChecks,
        errors = normalizedErrors, notes = normalizedNotes,
        requiredChecksCount = actualRequiredCount,
        completeness = rawSnapshot.snapshotCompleteness,
        hasFailure = hasFailure, hasUnknown = hasUnknown,
    }
end

local function formatReport(descriptor, color, reason, snapshot, loadState)
    local lines = {
        "BEESTWOOD INDUSTRIES - BI CORE DIAGNOSTIC REPORT",
        "Addon: " .. descriptor.displayName .. " (" .. descriptor.addonIdentifier .. ")",
        "Status: " .. color .. " - " .. reason,
        "Load state: " .. loadState,
        "Captured: current session; wall clock not asserted",
    }
    if snapshot then
        lines[#lines + 1] = "Addon version: " .. snapshot.addonVersion
        lines[#lines + 1] = "Client build: " .. snapshot.clientBuild
        lines[#lines + 1] = "Provider revision: " .. snapshot.providerRevision
        lines[#lines + 1] = "Completeness: " .. snapshot.completeness
        lines[#lines + 1] = "Required checks: " .. snapshot.requiredChecksCount
        for _, check in ipairs(snapshot.checks) do
            lines[#lines + 1] = (check.requiredForHealthy and "[REQUIRED] " or "[OPTIONAL] ")
                .. check.checkIdentifier .. " - " .. check.outcome .. " (" .. check.evidenceKind .. ")"
                .. " | " .. check.observedResult
        end
        for _, recentError in ipairs(snapshot.errors) do
            lines[#lines + 1] = "ERROR " .. recentError.errorIdentifier .. " - "
                .. recentError.severity .. " | " .. recentError.sanitizedMessage
        end
        for _, note in ipairs(snapshot.notes) do lines[#lines + 1] = "Note: " .. note end
    else
        lines[#lines + 1] = "No validated provider snapshot is available."
        lines[#lines + 1] = "This is a limited Core-generated explanation, not addon certification."
    end
    lines[#lines + 1] = "Forever gameplay validation: NOT CERTIFIED BY BI CORE"
    local report = table.concat(lines, "\n")
    if #report > maximumReportBytes then
        return report:sub(1, maximumReportBytes - 96)
            .. "\n[INCOMPLETE: REPORT EXCEEDED 64 KiB; CONTENT OMITTED]", false
    end
    return report, true
end

-- Capture never changes addon state. A known provider exception is red; an
-- unavailable provider is gray. The result is immutable after UI selection.
function diagnostics.Capture(descriptor, requestedDetailLevel)
    local loadState, reason = registry.GetLoadState(descriptor.addonIdentifier)
    local color, snapshot = "GRAY", nil
    if loadState == "LOADED" then
        local provider = registry.ResolveProvider(descriptor)
        if not provider then
            reason = "PROVIDER_UNAVAILABLE"
        else
            local successful, rawSnapshot, providerReason = pcall(provider, requestedDetailLevel)
            if not successful then
                color, reason = "RED", "PROVIDER_THROWN"
            elseif rawSnapshot == nil then
                reason = providerReason == "NOT_READY" and "PROVIDER_NOT_READY" or "PROVIDER_FAULT"
                if reason == "PROVIDER_FAULT" then color = "RED" end
            else
                local validated, result, validationReason = pcall(validateSnapshot, rawSnapshot, descriptor)
                if not validated then
                    color, reason = "RED", "PROVIDER_MALFORMED"
                elseif not result then
                    reason = validationReason
                    color = reason == "PROTOCOL_UNSUPPORTED" and "GRAY" or "RED"
                else
                    snapshot = result
                    if snapshot.hasFailure then
                        color, reason = "RED", "REQUIRED_CHECK_FAILED"
                    elseif snapshot.hasUnknown then
                        reason = "REQUIRED_CHECK_UNTESTED"
                    else
                        color, reason = "GREEN", "LIVE_CHECKS_PASSED"
                    end
                end
            end
        end
    end
    local formatted, report, complete = pcall(formatReport, descriptor, color, reason, snapshot, loadState)
    if not formatted then
        color, reason = "RED", "REPORT_PREPARATION_FAILED"
        report = "BI CORE - RED - REPORT_PREPARATION_FAILED"
        complete = false
    end
    return {addonIdentifier=descriptor.addonIdentifier, color=color, reason=reason,
        loadState=loadState, text=report, complete=complete}
end
