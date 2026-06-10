AdminModule = AdminModule or {}

function AdminModule.IsEnabled()
    return Config.Modules and Config.Modules.AdminPanel == true
end

local function adAudit(action, actor, target, metadata)
    MySQL.insert.await([[INSERT INTO bossmenu_admin_actions (admin_identifier, action, org_type, org_name, target_identifier, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], {
        actor,
        action,
        metadata and metadata.orgType or nil,
        metadata and metadata.orgName or nil,
        target,
        metadata and json.encode(metadata) or nil
    })
    if AuditModule and AuditModule.Write then
        AuditModule.Write('admin', metadata and metadata.orgName or 'global', 'admin:' .. tostring(action), actor, target, metadata or {})
    end
end

function AdminModule.IsAdmin(source, playerState)
    if not AdminModule.IsEnabled() then
        return false
    end
    if IsPlayerAceAllowed(source, 'bossmenu.admin') then
        return true
    end
    if type(Config.AdminCheck) == 'function' then
        local ok, allowed = pcall(Config.AdminCheck, source, playerState)
        if ok and allowed == true then
            return true
        end
    end
    if playerState and playerState.job and tostring(playerState.job.name):lower() == 'admin' then
        return true
    end
    return false
end

function AdminModule.ListOrganizations()
    local jobs = MySQL.query.await([[SELECT a.job AS name, a.balance,
            (SELECT COUNT(*) FROM bossmenu_org_state s WHERE s.org_type = 'boss' AND s.org_name = a.job AND s.disabled = 1) AS disabled
        FROM bossmenu_accounts a
        ORDER BY a.job ASC]]) or {}
    local gangs = MySQL.query.await([[SELECT g.name, g.label, g.max_grade,
            (SELECT COUNT(*) FROM bossmenu_gang_members m WHERE m.gang_name = g.name) AS member_count,
            (SELECT COUNT(*) FROM bossmenu_org_state s WHERE s.org_type = 'gang' AND s.org_name = g.name AND s.disabled = 1) AS disabled
        FROM bossmenu_gangs g
        ORDER BY g.name ASC]]) or {}
    local latestActions = MySQL.query.await([[SELECT id, action, org_type, org_name, target_identifier, created_at
        FROM bossmenu_admin_actions
        ORDER BY id DESC
        LIMIT 20]]) or {}
    return { jobs = jobs, gangs = gangs, latestActions = latestActions }
end

function AdminModule.AddFunds(orgType, orgName, amount, actor)
    local n = tonumber(amount) or 0
    if n <= 0 then return false, 'Invalid amount' end
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_accounts (job, balance) VALUES (?, 0)', { orgName })
    MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { n, orgName })
    adAudit('add_funds', actor, nil, { orgType = orgType, orgName = orgName, amount = n })
    return true
end

function AdminModule.RemoveFunds(orgType, orgName, amount, actor)
    local n = tonumber(amount) or 0
    if n <= 0 then return false, 'Invalid amount' end
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_accounts (job, balance) VALUES (?, 0)', { orgName })
    local affected = MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance - ? WHERE job = ? AND balance >= ?', {
        n, orgName, n
    })
    if (affected or 0) < 1 then
        return false, 'Insufficient balance'
    end
    adAudit('remove_funds', actor, nil, { orgType = orgType, orgName = orgName, amount = n })
    return true
end

function AdminModule.GetRecentAdminActions(limit)
    local nLimit = tonumber(limit) or 100
    if nLimit < 1 then nLimit = 1 end
    if nLimit > 500 then nLimit = 500 end
    local rows = MySQL.query.await([[SELECT id, admin_identifier, action, org_type, org_name, target_identifier, metadata, created_at
        FROM bossmenu_admin_actions
        ORDER BY id DESC
        LIMIT ?]], { nLimit }) or {}
    for i = 1, #rows do
        rows[i].metadata = (type(rows[i].metadata) == 'string' and json.decode(rows[i].metadata)) or rows[i].metadata or {}
    end
    return rows
end
