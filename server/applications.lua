ApplicationsModule = ApplicationsModule or {}

function ApplicationsModule.IsEnabled()
    return Config.Modules and Config.Modules.Applications == true
end

local function appCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function appAudit(orgType, orgName, action, actor, target, metadata)
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

local function appResourceStarted(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function appPhoneMode()
    local mode = tostring(Config.Integrations and Config.Integrations.phone or 'none')
    if mode ~= 'auto' then return mode end
    if appResourceStarted('yseries') then return 'yseries' end
    if appResourceStarted('qb-phone') then return 'qb-phone' end
    if appResourceStarted('qs-smartphone') then return 'qs-smartphone' end
    return 'none'
end

local function appPhoneNotify(identifier, title, message)
    local mode = appPhoneMode()
    if mode == 'none' then return false end
    local ok = pcall(function()
        if mode == 'yseries' then
            exports.yseries:SendNotification(identifier, { title = title, message = message })
        elseif mode == 'qb-phone' then
            TriggerEvent('qb-phone:server:sendNewMailToOffline', identifier, {
                sender = 'Org Suite',
                subject = title,
                message = message
            })
        elseif mode == 'qs-smartphone' then
            TriggerEvent('qs-smartphone:server:sendNotify', identifier, {
                title = title,
                message = message
            })
        end
    end)
    return ok
end

function ApplicationsModule.Create(orgType, orgName, payload)
    if not ApplicationsModule.IsEnabled() then
        return false, 'Applications disabled'
    end
    local applicantIdentifier = appCleanText(payload and payload.identifier, 80)
    local applicantName = appCleanText(payload and payload.name, 100)
    local phone = appCleanText(payload and payload.phone, 40)
    local answers = type(payload and payload.answers) == 'table' and payload.answers or {}

    if applicantName == '' then
        return false, 'Applicant name required'
    end

    local id = MySQL.insert.await([[INSERT INTO bossmenu_job_applications (org_type, org_name, applicant_identifier, applicant_name, applicant_phone, answers, status)
        VALUES (?, ?, ?, ?, ?, ?, 'pending')]], {
        orgType,
        orgName,
        applicantIdentifier ~= '' and applicantIdentifier or nil,
        applicantName,
        phone ~= '' and phone or nil,
        json.encode(answers)
    })
    appAudit(orgType, orgName, 'application_create', applicantIdentifier, nil, { applicationId = id, applicantName = applicantName })
    TriggerEvent('qb-management:server:hook', 'OnApplicationCreated', {
        orgType = orgType,
        orgName = orgName,
        applicationId = id,
        applicantIdentifier = applicantIdentifier,
        applicantName = applicantName
    })
    if applicantIdentifier ~= '' then
        appPhoneNotify(applicantIdentifier, 'Application Received', ('Your application to %s is pending review.'):format(orgName))
    end
    return true, { id = id }
end

function ApplicationsModule.List(orgType, orgName, status, search)
    local where = 'WHERE org_type = ? AND org_name = ?'
    local params = { orgType, orgName }
    local cleanStatus = appCleanText(status, 24)
    if cleanStatus ~= '' and cleanStatus ~= 'all' then
        where = where .. ' AND status = ?'
        params[#params + 1] = cleanStatus
    end
    local q = appCleanText(search, 64)
    if q ~= '' then
        where = where .. ' AND (applicant_name LIKE ? OR applicant_identifier LIKE ?)'
        params[#params + 1] = '%' .. q .. '%'
        params[#params + 1] = '%' .. q .. '%'
    end

    local rows = MySQL.query.await(([[SELECT id, applicant_identifier, applicant_name, applicant_phone, answers, status, decision_reason, decided_by, created_at, updated_at
        FROM bossmenu_job_applications
        %s
        ORDER BY id DESC
        LIMIT 500]]):format(where), params) or {}
    for i = 1, #rows do
        rows[i].answers = (type(rows[i].answers) == 'string' and json.decode(rows[i].answers)) or rows[i].answers or {}
    end
    return rows
end

function ApplicationsModule.Decide(orgType, orgName, applicationId, status, reason, actor)
    if not ApplicationsModule.IsEnabled() then
        return false, 'Applications disabled'
    end
    local id = tonumber(applicationId) or 0
    local newStatus = appCleanText(status, 24)
    local decisionReason = appCleanText(reason, 255)
    if id < 1 then return false, 'Invalid application' end
    if newStatus ~= 'accepted' and newStatus ~= 'rejected' and newStatus ~= 'archived' then
        return false, 'Invalid status'
    end
    local row = MySQL.single.await('SELECT id, applicant_identifier, applicant_name, status FROM bossmenu_job_applications WHERE id = ? AND org_type = ? AND org_name = ? LIMIT 1', {
        id, orgType, orgName
    })
    if not row then
        return false, 'Application not found'
    end
    MySQL.update.await([[UPDATE bossmenu_job_applications
        SET status = ?, decision_reason = ?, decided_by = ?, updated_at = NOW()
        WHERE id = ?]], {
        newStatus, decisionReason ~= '' and decisionReason or nil, actor, id
    })
    appAudit(orgType, orgName, 'application_decide', actor, row.applicant_identifier, {
        applicationId = id,
        status = newStatus,
        reason = decisionReason
    })
    if newStatus == 'accepted' then
        TriggerEvent('qb-management:server:hook', 'OnApplicationAccepted', {
            orgType = orgType,
            orgName = orgName,
            applicationId = id,
            applicantIdentifier = row.applicant_identifier,
            actor = actor
        })
        if row.applicant_identifier and row.applicant_identifier ~= '' then
            appPhoneNotify(row.applicant_identifier, 'Application Accepted', ('Your application to %s was accepted.'):format(orgName))
        end
    elseif newStatus == 'rejected' then
        TriggerEvent('qb-management:server:hook', 'OnApplicationRejected', {
            orgType = orgType,
            orgName = orgName,
            applicationId = id,
            applicantIdentifier = row.applicant_identifier,
            actor = actor
        })
        if row.applicant_identifier and row.applicant_identifier ~= '' then
            appPhoneNotify(row.applicant_identifier, 'Application Rejected', ('Your application to %s was rejected.'):format(orgName))
        end
    end
    return true
end
