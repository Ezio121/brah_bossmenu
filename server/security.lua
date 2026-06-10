SecurityModule = SecurityModule or {}
SecurityModule.failedChecks = SecurityModule.failedChecks or {}
SecurityModule.lockouts = SecurityModule.lockouts or {}

local function secNow()
    return os.time()
end

function SecurityModule.RecordFailure(source, reason)
    local key = tostring(source or 0)
    local row = SecurityModule.failedChecks[key] or { count = 0, last = 0, reasons = {} }
    row.count = row.count + 1
    row.last = secNow()
    row.reasons[#row.reasons + 1] = tostring(reason or 'unknown')
    if #row.reasons > 20 then
        table.remove(row.reasons, 1)
    end
    SecurityModule.failedChecks[key] = row

    local threshold = tonumber(Config.Security and Config.Security.lockoutFailThreshold or 12) or 12
    local lockSeconds = tonumber(Config.Security and Config.Security.lockoutSeconds or 120) or 120
    if row.count >= threshold then
        SecurityModule.lockouts[key] = row.last + lockSeconds
        row.count = 0
        row.reasons = {}
    end

    return row
end

function SecurityModule.GetFailureState(source)
    return SecurityModule.failedChecks[tostring(source or 0)]
end

function SecurityModule.IsLocked(source)
    local key = tostring(source or 0)
    local untilTs = tonumber(SecurityModule.lockouts[key] or 0) or 0
    if untilTs <= 0 then
        return false, 0
    end
    local now = secNow()
    if now >= untilTs then
        SecurityModule.lockouts[key] = nil
        return false, 0
    end
    return true, untilTs - now
end

function SecurityModule.ClearFailure(source)
    local key = tostring(source or 0)
    SecurityModule.failedChecks[key] = nil
    SecurityModule.lockouts[key] = nil
end
