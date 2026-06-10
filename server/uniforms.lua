UniformsModule = UniformsModule or {}

function UniformsModule.GetIntegration()
    local integrations = Config.Integrations or {}
    local mode = tostring(integrations.clothing or 'auto')
    if mode ~= 'auto' then
        return mode
    end
    if GetResourceState('illenium-appearance') == 'started' then return 'illenium-appearance' end
    if GetResourceState('fivem-appearance') == 'started' then return 'fivem-appearance' end
    if GetResourceState('qb-clothing') == 'started' then return 'qb-clothing' end
    if GetResourceState('skinchanger') == 'started' then return 'skinchanger' end
    return 'none'
end

function UniformsModule.IsEnabled()
    return Config.Modules and Config.Modules.Uniforms == true
end

local function ufCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function ufAudit(orgType, orgName, action, actor, target, metadata)
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

function UniformsModule.List(orgType, orgName)
    local rows = MySQL.query.await([[SELECT id, uniform_name, male_data, female_data, rank_map, created_by, created_at, updated_at
        FROM bossmenu_org_uniforms
        WHERE org_type = ? AND org_name = ?
        ORDER BY id DESC]], { orgType, orgName }) or {}
    for i = 1, #rows do
        rows[i].male_data = (type(rows[i].male_data) == 'string' and json.decode(rows[i].male_data)) or rows[i].male_data or {}
        rows[i].female_data = (type(rows[i].female_data) == 'string' and json.decode(rows[i].female_data)) or rows[i].female_data or {}
        rows[i].rank_map = (type(rows[i].rank_map) == 'string' and json.decode(rows[i].rank_map)) or rows[i].rank_map or {}
    end
    return rows
end

function UniformsModule.Save(orgType, orgName, payload, actor)
    local id = tonumber(payload and payload.id) or 0
    local name = ufCleanText(payload and payload.name, 80)
    local maleData = type(payload and payload.maleData) == 'table' and payload.maleData or {}
    local femaleData = type(payload and payload.femaleData) == 'table' and payload.femaleData or {}
    local rankMap = type(payload and payload.rankMap) == 'table' and payload.rankMap or {}
    if name == '' then
        return false, 'Invalid uniform name'
    end

    if id > 0 then
        local affected = MySQL.update.await([[UPDATE bossmenu_org_uniforms
            SET uniform_name = ?, male_data = ?, female_data = ?, rank_map = ?, updated_at = NOW()
            WHERE id = ? AND org_type = ? AND org_name = ?]], {
            name, json.encode(maleData), json.encode(femaleData), json.encode(rankMap), id, orgType, orgName
        })
        if (affected or 0) < 1 then
            return false, 'Uniform not found'
        end
        ufAudit(orgType, orgName, 'uniform_update', actor, nil, { id = id, name = name })
    else
        id = MySQL.insert.await([[INSERT INTO bossmenu_org_uniforms (org_type, org_name, uniform_name, male_data, female_data, rank_map, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?)]], {
            orgType, orgName, name, json.encode(maleData), json.encode(femaleData), json.encode(rankMap), actor
        })
        ufAudit(orgType, orgName, 'uniform_create', actor, nil, { id = id, name = name })
    end

    TriggerEvent('qb-management:server:hook', 'uniform_saved', {
        orgType = orgType,
        orgName = orgName,
        id = id,
        name = name,
        actor = actor
    })
    return true, { id = id, name = name }
end

function UniformsModule.Delete(orgType, orgName, uniformId, actor)
    local id = tonumber(uniformId) or 0
    if id < 1 then
        return false, 'Invalid uniform'
    end
    local affected = MySQL.update.await('DELETE FROM bossmenu_org_uniforms WHERE id = ? AND org_type = ? AND org_name = ?', {
        id, orgType, orgName
    })
    if (affected or 0) < 1 then
        return false, 'Uniform not found'
    end
    ufAudit(orgType, orgName, 'uniform_delete', actor, nil, { id = id })
    TriggerEvent('qb-management:server:hook', 'uniform_deleted', {
        orgType = orgType,
        orgName = orgName,
        id = id,
        actor = actor
    })
    return true
end

local function findUniform(orgType, orgName, uniformId)
    local id = tonumber(uniformId) or 0
    if id < 1 then return nil end
    local row = MySQL.single.await([[SELECT id, uniform_name, male_data, female_data, rank_map
        FROM bossmenu_org_uniforms
        WHERE id = ? AND org_type = ? AND org_name = ?
        LIMIT 1]], { id, orgType, orgName })
    if not row then return nil end
    row.male_data = (type(row.male_data) == 'string' and json.decode(row.male_data)) or row.male_data or {}
    row.female_data = (type(row.female_data) == 'string' and json.decode(row.female_data)) or row.female_data or {}
    row.rank_map = (type(row.rank_map) == 'string' and json.decode(row.rank_map)) or row.rank_map or {}
    return row
end

function UniformsModule.Apply(orgType, orgName, uniformId, actor, actorSource, op)
    if not UniformsModule.IsEnabled() then
        return false, 'Uniforms disabled'
    end
    local src = tonumber(actorSource) or 0
    if src < 1 then
        return false, 'Invalid source'
    end
    local operation = ufCleanText(op, 16)
    if operation ~= 'preview' and operation ~= 'apply' and operation ~= 'restore' then
        return false, 'Invalid uniform action'
    end

    if operation == 'restore' then
        TriggerClientEvent('qb-management:client:uniformAction', src, {
            op = 'restore',
            integration = UniformsModule.GetIntegration()
        })
        ufAudit(orgType, orgName, 'uniform_restore', actor, actor, nil)
        return true
    end

    local uniform = findUniform(orgType, orgName, uniformId)
    if not uniform then
        return false, 'Uniform not found'
    end

    TriggerClientEvent('qb-management:client:uniformAction', src, {
        op = operation,
        integration = UniformsModule.GetIntegration(),
        uniform = {
            id = uniform.id,
            name = uniform.uniform_name,
            male = uniform.male_data,
            female = uniform.female_data,
            rankMap = uniform.rank_map
        }
    })
    ufAudit(orgType, orgName, operation == 'preview' and 'uniform_preview' or 'uniform_apply', actor, actor, {
        id = uniform.id,
        name = uniform.uniform_name
    })
    TriggerEvent('qb-management:server:hook', operation == 'preview' and 'uniform_previewed' or 'uniform_applied', {
        orgType = orgType,
        orgName = orgName,
        id = uniform.id,
        actor = actor
    })
    return true
end
