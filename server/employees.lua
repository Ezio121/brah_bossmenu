EmployeesModule = EmployeesModule or {}

local function emCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function emNow()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function emAudit(orgType, orgName, action, actor, target, metadata)
    if AuditModule and AuditModule.Write then
        AuditModule.Write(orgType, orgName, ('%s:%s'):format(orgType, action), actor, target, metadata or {})
        return
    end
    MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
        VALUES (?, ?, ?, ?, ?)]], {
        orgName,
        ('%s:%s'):format(orgType, action),
        actor,
        target,
        metadata and json.encode(metadata) or nil
    })
end

function EmployeesModule.IsEnabled()
    return Config.Modules and Config.Modules.EmployeeProfiles == true
end

function EmployeesModule.GetProfile(orgType, orgName, identifier)
    local row = MySQL.single.await([[SELECT identifier, joined_at, hired_by, notes, strikes, photo_url, metadata, updated_at
        FROM bossmenu_employee_profiles
        WHERE org_type = ? AND org_name = ? AND identifier = ?
        LIMIT 1]], { orgType, orgName, identifier })
    if not row then
        return {
            identifier = identifier,
            joinedAt = nil,
            hiredBy = nil,
            notes = '',
            strikes = 0,
            photoUrl = nil,
            metadata = {},
            updatedAt = nil
        }
    end
    return {
        identifier = tostring(row.identifier),
        joinedAt = row.joined_at,
        hiredBy = row.hired_by,
        notes = row.notes or '',
        strikes = tonumber(row.strikes) or 0,
        photoUrl = row.photo_url,
        metadata = (type(row.metadata) == 'string' and json.decode(row.metadata)) or row.metadata or {},
        updatedAt = row.updated_at
    }
end

function EmployeesModule.UpsertProfile(orgType, orgName, identifier, payload, actor)
    local notes = emCleanText(payload and payload.notes, 2048)
    local photoUrl = emCleanText(payload and payload.photoUrl, 2000000)
    if photoUrl == '' then photoUrl = nil end
    local metadata = payload and payload.metadata
    if type(metadata) ~= 'table' then
        metadata = {}
    end

    MySQL.insert.await([[INSERT INTO bossmenu_employee_profiles (org_type, org_name, identifier, notes, photo_url, metadata, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE notes = VALUES(notes), photo_url = VALUES(photo_url), metadata = VALUES(metadata), updated_at = VALUES(updated_at)]], {
        orgType,
        orgName,
        identifier,
        notes ~= '' and notes or nil,
        photoUrl,
        json.encode(metadata),
        emNow()
    })

    emAudit(orgType, orgName, 'profile_update', actor, identifier, {
        hasNotes = notes ~= '',
        hasPhoto = photoUrl ~= nil
    })
    TriggerEvent('qb-management:server:hook', 'member_profile_updated', {
        orgType = orgType,
        orgName = orgName,
        actor = actor,
        target = identifier
    })
    return EmployeesModule.GetProfile(orgType, orgName, identifier)
end

function EmployeesModule.AddStrike(orgType, orgName, identifier, amount, reason, actor)
    local n = tonumber(amount) or 0
    if n == 0 then
        return false, 'Invalid strike amount'
    end
    MySQL.insert.await([[INSERT INTO bossmenu_employee_profiles (org_type, org_name, identifier, strikes)
        VALUES (?, ?, ?, 0)
        ON DUPLICATE KEY UPDATE identifier = VALUES(identifier)]], {
        orgType, orgName, identifier
    })
    MySQL.update.await([[UPDATE bossmenu_employee_profiles
        SET strikes = GREATEST(strikes + ?, 0), updated_at = ?
        WHERE org_type = ? AND org_name = ? AND identifier = ?]], {
        n, emNow(), orgType, orgName, identifier
    })

    EmployeesModule.AppendActivity(orgType, orgName, identifier, n > 0 and 'strike_added' or 'strike_removed', {
        amount = n,
        reason = emCleanText(reason, 255),
        actor = actor
    })
    emAudit(orgType, orgName, 'profile_strike', actor, identifier, { amount = n, reason = reason })
    return true, EmployeesModule.GetProfile(orgType, orgName, identifier)
end

function EmployeesModule.AppendActivity(orgType, orgName, identifier, action, details)
    MySQL.insert.await([[INSERT INTO bossmenu_employee_activity (org_type, org_name, identifier, action, details)
        VALUES (?, ?, ?, ?, ?)]], {
        orgType, orgName, identifier, emCleanText(action, 64), details and json.encode(details) or nil
    })
end

function EmployeesModule.GetActivity(orgType, orgName, identifier, limit)
    local nLimit = tonumber(limit) or 25
    if nLimit < 1 then nLimit = 1 end
    if nLimit > 200 then nLimit = 200 end
    local rows = MySQL.query.await([[SELECT id, action, details, created_at
        FROM bossmenu_employee_activity
        WHERE org_type = ? AND org_name = ? AND identifier = ?
        ORDER BY id DESC
        LIMIT ?]], { orgType, orgName, identifier, nLimit }) or {}
    for i = 1, #rows do
        rows[i].details = (type(rows[i].details) == 'string' and json.decode(rows[i].details)) or rows[i].details or {}
    end
    return rows
end

function EmployeesModule.FilterAndSortRows(rows, opts)
    opts = type(opts) == 'table' and opts or {}
    local q = emCleanText(opts.search, 64):lower()
    local online = opts.online
    local rank = tonumber(opts.rank)
    local sortBy = emCleanText(opts.sortBy, 32)
    if sortBy == '' then sortBy = 'rank' end
    local dir = emCleanText(opts.sortDir, 8)
    if dir ~= 'asc' and dir ~= 'desc' then dir = 'desc' end

    local filtered = {}
    for _, row in ipairs(rows or {}) do
        local ok = true
        if q ~= '' then
            local hay = (tostring(row.name or '') .. ' ' .. tostring(row.identifier or '') .. ' ' .. tostring(row.grade and row.grade.name or '')):lower()
            ok = hay:find(q, 1, true) ~= nil
        end
        if ok and type(online) == 'boolean' then
            ok = row.online == online
        end
        if ok and rank ~= nil then
            ok = tonumber(row.grade and row.grade.level or -1) == rank
        end
        if ok then
            filtered[#filtered + 1] = row
        end
    end

    table.sort(filtered, function(a, b)
        local av, bv
        if sortBy == 'name' then
            av, bv = tostring(a.name or ''), tostring(b.name or '')
        elseif sortBy == 'join_date' then
            av, bv = tostring(a.joinedAt or ''), tostring(b.joinedAt or '')
        elseif sortBy == 'last_seen' then
            av, bv = tostring(a.lastSeen or ''), tostring(b.lastSeen or '')
        else
            av, bv = tonumber(a.grade and a.grade.level) or 0, tonumber(b.grade and b.grade.level) or 0
        end
        if dir == 'asc' then
            return av < bv
        end
        return av > bv
    end)
    return filtered
end
