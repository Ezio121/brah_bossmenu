local auditResource = GetCurrentResourceName()

AuditModule = AuditModule or {}

if auditResource:lower():sub(-5) == '-init' then
    return
end

AuditModule.queue = AuditModule.queue or {}
AuditModule.processing = AuditModule.processing or false
AuditModule.settingsCache = AuditModule.settingsCache or {}

local DefaultWebhookCategories = {
    'employee',
    'gang',
    'finance',
    'inventory',
    'admin',
    'security',
    'applications',
    'territories',
    'contracts'
}

local function audJson(value)
    if type(value) == 'table' then
        local ok, encoded = pcall(json.encode, value)
        if ok then return encoded end
        return '{}'
    end
    if type(value) == 'string' then return value end
    return '{}'
end

local function audDecode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return {}
end

local function audCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function classifyCategory(action)
    local text = tostring(action or ''):lower()
    if text:find('contract') then return 'contracts' end
    if text:find('gang') or text:find('notoriety') then return 'gang' end
    if text:find('withdraw') or text:find('deposit') or text:find('invoice') or text:find('tax') or text:find('payroll') then return 'finance' end
    if text:find('inventory') or text:find('stash') then return 'inventory' end
    if text:find('application') then return 'applications' end
    if text:find('territor') then return 'territories' end
    if text:find('admin') then return 'admin' end
    if text:find('suspicious') or text:find('security') then return 'security' end
    return 'employee'
end

local function webhookConfig()
    local cfg = Config.Webhooks or {}
    return {
        enabled = cfg.enabled == true and (Config.Modules and Config.Modules.Webhooks == true),
        redact = cfg.redactIdentifiers == true,
        timeoutMs = tonumber(cfg.timeoutMs) or 5000,
        retryBaseMs = tonumber(cfg.retryBaseMs) or 2000,
        maxRetries = tonumber(cfg.maxRetries) or 4,
        batchWindowMs = tonumber(cfg.batchWindowMs) or 3500,
        batchSize = math.max(1, math.min(10, tonumber(cfg.batchSize) or 10)),
        urls = cfg.urls or {}
    }
end

function AuditModule.GetWebhookCategories()
    local cfg = Config.Webhooks or {}
    local categories = type(cfg.categories) == 'table' and cfg.categories or DefaultWebhookCategories
    local out, seen = {}, {}
    for i = 1, #categories do
        local category = audCleanText(categories[i], 32):lower()
        if category ~= '' and not seen[category] then
            seen[category] = true
            out[#out + 1] = category
        end
    end
    return out
end

local function validCategory(category)
    category = audCleanText(category, 32):lower()
    if category == '' then return nil end
    local categories = AuditModule.GetWebhookCategories()
    for i = 1, #categories do
        if categories[i] == category then
            return category
        end
    end
    return nil
end

local function validWebhookUrl(url)
    url = audCleanText(url, 600)
    if url == '' then return '' end
    if url:find('^https://discord%.com/api/webhooks/%d+/[^%s]+$') then return url end
    if url:find('^https://discordapp%.com/api/webhooks/%d+/[^%s]+$') then return url end
    return nil
end

local function settingCacheKey(scopeType, orgType, orgName, category)
    return ('%s:%s:%s:%s'):format(scopeType or '', orgType or '', orgName or '', category or '')
end

local function getStoredWebhook(scopeType, orgType, orgName, category)
    category = validCategory(category)
    if not category then return nil end
    scopeType = audCleanText(scopeType, 16):lower()
    orgType = audCleanText(orgType, 16):lower()
    orgName = audCleanText(orgName, 64)
    if scopeType == 'admin' then
        orgType, orgName = '', ''
    elseif scopeType ~= 'org' then
        return nil
    end

    local key = settingCacheKey(scopeType, orgType, orgName, category)
    local now = GetGameTimer()
    local cached = AuditModule.settingsCache[key]
    if cached and now < (cached.expiresAt or 0) then
        return cached.row
    end

    local row = MySQL.single.await([[SELECT scope_type, org_type, org_name, category, webhook_url, enabled, updated_by, updated_at
        FROM bossmenu_webhook_settings
        WHERE scope_type = ? AND org_type = ? AND org_name = ? AND category = ?
        LIMIT 1]], { scopeType, orgType, orgName, category })
    if row then
        row.enabled = tonumber(row.enabled) == 1
    end
    AuditModule.settingsCache[key] = {
        row = row,
        expiresAt = now + 30000
    }
    return row
end

function AuditModule.GetWebhookSettings(scopeType, orgType, orgName)
    scopeType = audCleanText(scopeType, 16):lower()
    orgType = audCleanText(orgType, 16):lower()
    orgName = audCleanText(orgName, 64)
    if scopeType == 'admin' then
        orgType, orgName = '', ''
    elseif scopeType ~= 'org' then
        return {}
    end

    local rows = MySQL.query.await([[SELECT scope_type, org_type, org_name, category, webhook_url, enabled, updated_by, updated_at
        FROM bossmenu_webhook_settings
        WHERE scope_type = ? AND org_type = ? AND org_name = ?
        ORDER BY category ASC]], { scopeType, orgType, orgName }) or {}
    local byCategory = {}
    for i = 1, #rows do
        local row = rows[i]
        row.enabled = tonumber(row.enabled) == 1
        byCategory[tostring(row.category)] = row
    end
    local out = {}
    local categories = AuditModule.GetWebhookCategories()
    for i = 1, #categories do
        local category = categories[i]
        local row = byCategory[category] or {
            scope_type = scopeType,
            org_type = orgType,
            org_name = orgName,
            category = category,
            webhook_url = '',
            enabled = false
        }
        out[#out + 1] = row
    end
    return out
end

function AuditModule.SaveWebhookSetting(scopeType, orgType, orgName, category, url, enabled, actor)
    scopeType = audCleanText(scopeType, 16):lower()
    orgType = audCleanText(orgType, 16):lower()
    orgName = audCleanText(orgName, 64)
    category = validCategory(category)
    if not category then
        return false, 'Invalid webhook type'
    end
    if scopeType == 'admin' then
        orgType, orgName = '', ''
    elseif scopeType ~= 'org' or orgType == '' or orgName == '' then
        return false, 'Invalid webhook scope'
    end
    local cleanUrl = validWebhookUrl(url)
    if cleanUrl == nil then
        return false, 'Invalid Discord webhook URL'
    end
    local isEnabled = enabled == true and cleanUrl ~= ''
    MySQL.insert.await([[INSERT INTO bossmenu_webhook_settings (scope_type, org_type, org_name, category, webhook_url, enabled, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE webhook_url = VALUES(webhook_url), enabled = VALUES(enabled), updated_by = VALUES(updated_by), updated_at = NOW()]], {
        scopeType, orgType, orgName, category, cleanUrl ~= '' and cleanUrl or nil, isEnabled and 1 or 0, audCleanText(actor, 80)
    })
    AuditModule.settingsCache[settingCacheKey(scopeType, orgType, orgName, category)] = nil
    return true
end

function AuditModule.BuildRow(orgType, orgName, action, actorIdentifier, targetIdentifier, metadata)
    local meta = type(metadata) == 'table' and metadata or {}
    return {
        org_type = orgType or 'boss',
        org_name = orgName or 'unknown',
        action = action or 'unknown',
        actor_identifier = actorIdentifier,
        actor_name = tostring(meta.actorName or meta.actor_name or ''),
        target_identifier = targetIdentifier,
        target_name = tostring(meta.targetName or meta.target_name or ''),
        metadata_json = meta
    }
end

function AuditModule.Write(orgType, orgName, action, actorIdentifier, targetIdentifier, metadata)
    local row = AuditModule.BuildRow(orgType, orgName, action, actorIdentifier, targetIdentifier, metadata)
    local wrote = pcall(function()
        MySQL.insert.await([[INSERT INTO bossmenu_audit (
            org_type, org_name, job, action, actor_identifier, actor_name, target_identifier, target_name, metadata_json, payload
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            row.org_type,
            row.org_name,
            row.org_name,
            row.action,
            row.actor_identifier,
            row.actor_name ~= '' and row.actor_name or nil,
            row.target_identifier,
            row.target_name ~= '' and row.target_name or nil,
            audJson(row.metadata_json),
            audJson(row.metadata_json)
        })
    end)
    if not wrote then
        MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
            VALUES (?, ?, ?, ?, ?)]], {
            row.org_name,
            row.action,
            row.actor_identifier,
            row.target_identifier,
            audJson(row.metadata_json)
        })
    end
    local category = classifyCategory(row.action)
    if category ~= 'security' or (Config.Security and Config.Security.webhookOnSuspiciousAction == true) then
        AuditModule.QueueWebhook(category, row)
    end
    return true
end

function AuditModule.QueueWebhook(category, payload)
    local cfg = webhookConfig()
    if not cfg.enabled then return false end
    category = validCategory(category) or classifyCategory(payload and payload.action)
    if category == 'security' and not (Config.Security and Config.Security.webhookOnSuspiciousAction == true) then
        return false
    end

    local destinations = {}
    local function addDestination(scopeType, url)
        url = audCleanText(url, 600)
        if url == '' then return end
        local key = ('%s:%s:%s'):format(scopeType or 'unknown', category, url)
        if destinations[key] then return end
        destinations[key] = {
            scopeType = scopeType,
            url = url
        }
    end

    local legacyUrl = cfg.urls and cfg.urls[category] or ''
    addDestination('config', legacyUrl)

    local orgType = audCleanText(payload and payload.org_type, 16):lower()
    local orgName = audCleanText(payload and payload.org_name, 64)
    if orgName ~= '' and orgName ~= 'unknown' and orgType ~= 'admin' and orgType ~= 'security' then
        local orgSetting = getStoredWebhook('org', orgType, orgName, category)
        if orgSetting and orgSetting.enabled and orgSetting.webhook_url then
            addDestination('org', orgSetting.webhook_url)
        end
    end

    local adminSetting = getStoredWebhook('admin', '', '', category)
    if adminSetting and adminSetting.enabled and adminSetting.webhook_url then
        addDestination('admin', adminSetting.webhook_url)
    end

    local queued = false
    for _, destination in pairs(destinations) do
        AuditModule.queue[#AuditModule.queue + 1] = {
            category = category,
            scopeType = destination.scopeType,
            url = destination.url,
            payload = payload,
            retries = 0,
            nextAttemptAt = GetGameTimer() + cfg.batchWindowMs
        }
        queued = true
    end
    return queued
end

local function redactedValue(value, enabled)
    if not enabled then return value end
    local text = tostring(value or '')
    if text == '' then return '' end
    if #text <= 4 then return '****' end
    return ('%s****%s'):format(text:sub(1, 2), text:sub(-2))
end

local function webhookEmbed(item)
    local cfg = webhookConfig()
    local payload = item.payload or {}
    local metadata = payload.metadata_json or payload.metadata or {}
    return {
        title = ('[%s] %s'):format(item.category, tostring(payload.action or 'event')),
        color = item.scopeType == 'admin' and 0xE15F5F or 0xC9A24B,
        fields = {
            { name = 'Scope', value = tostring(item.scopeType or 'unknown'), inline = true },
            { name = 'Org Type', value = tostring(payload.org_type or 'unknown'), inline = true },
            { name = 'Org Name', value = tostring(payload.org_name or 'unknown'), inline = true },
            { name = 'Actor', value = redactedValue(payload.actor_identifier, cfg.redact), inline = true },
            { name = 'Target', value = redactedValue(payload.target_identifier, cfg.redact), inline = true },
            { name = 'Metadata', value = ('```json\n%s\n```'):format(audJson(metadata)):sub(1, 1024), inline = false }
        },
        footer = {
            text = ('server:%s'):format(GetConvar('sv_hostname', 'unknown'))
        },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }
end

local function webhookBody(batch)
    local first = batch[1] or {}
    local embeds = {}
    for i = 1, #batch do
        embeds[#embeds + 1] = webhookEmbed(batch[i])
    end
    return {
        username = ('qb-management %s'):format(first.category or 'logs'),
        content = #batch > 1 and ('Batched %s log events'):format(#batch) or nil,
        embeds = embeds
    }
end

local function takeWebhookBatch(firstIndex, cfg)
    local first = AuditModule.queue[firstIndex]
    if not first then return nil end
    local batch = {}
    local indexes = {}
    for i = firstIndex, #AuditModule.queue do
        local item = AuditModule.queue[i]
        if item
            and item.url == first.url
            and item.category == first.category
            and item.scopeType == first.scopeType
            and GetGameTimer() >= (item.nextAttemptAt or 0) then
            batch[#batch + 1] = item
            indexes[#indexes + 1] = i
            if #batch >= cfg.batchSize then
                break
            end
        end
    end
    for i = #indexes, 1, -1 do
        table.remove(AuditModule.queue, indexes[i])
    end
    return batch
end

CreateThread(function()
    while true do
        if #AuditModule.queue == 0 then
            Wait(500)
        else
            local itemIndex, item = nil, nil
            for i = 1, #AuditModule.queue do
                local candidate = AuditModule.queue[i]
                if candidate and GetGameTimer() >= (candidate.nextAttemptAt or 0) then
                    itemIndex, item = i, candidate
                    break
                end
            end
            if item and GetGameTimer() >= (item.nextAttemptAt or 0) then
                local cfg = webhookConfig()
                local batch = takeWebhookBatch(itemIndex, cfg) or { item }
                local body = webhookBody(batch)
                PerformHttpRequest(item.url, function(statusCode)
                    if statusCode and statusCode >= 200 and statusCode < 300 then
                        return
                    else
                        for i = 1, #batch do
                            local failed = batch[i]
                            failed.retries = (failed.retries or 0) + 1
                            if failed.retries < cfg.maxRetries then
                                local backoff = cfg.retryBaseMs * failed.retries
                                failed.nextAttemptAt = GetGameTimer() + backoff
                                AuditModule.queue[#AuditModule.queue + 1] = failed
                            end
                        end
                    end
                end, 'POST', audJson(body), { ['Content-Type'] = 'application/json' })
                Wait(50)
            else
                Wait(50)
            end
        end
    end
end)

function AuditModule.GetLogs(filters)
    filters = type(filters) == 'table' and filters or {}
    local where = { '1=1' }
    local params = {}
    if filters.orgName and tostring(filters.orgName) ~= '' then
        where[#where + 1] = '(COALESCE(org_name, job) = ?)'
        params[#params + 1] = tostring(filters.orgName)
    end
    if filters.action and tostring(filters.action) ~= '' then
        where[#where + 1] = 'action LIKE ?'
        params[#params + 1] = '%' .. tostring(filters.action) .. '%'
    end
    if filters.actor and tostring(filters.actor) ~= '' then
        where[#where + 1] = 'actor_identifier LIKE ?'
        params[#params + 1] = '%' .. tostring(filters.actor) .. '%'
    end
    if filters.target and tostring(filters.target) ~= '' then
        where[#where + 1] = 'target_identifier LIKE ?'
        params[#params + 1] = '%' .. tostring(filters.target) .. '%'
    end
    if filters.dateFrom and tostring(filters.dateFrom) ~= '' then
        where[#where + 1] = 'created_at >= ?'
        params[#params + 1] = tostring(filters.dateFrom)
    end
    if filters.dateTo and tostring(filters.dateTo) ~= '' then
        where[#where + 1] = 'created_at <= ?'
        params[#params + 1] = tostring(filters.dateTo)
    end
    if filters.category and tostring(filters.category) ~= '' then
        local category = tostring(filters.category)
        if category == 'contracts' then
            where[#where + 1] = 'action LIKE ?'
            params[#params + 1] = '%contract%'
        elseif category == 'territories' then
            where[#where + 1] = 'action LIKE ?'
            params[#params + 1] = '%territor%'
        elseif category == 'gang' then
            where[#where + 1] = '(action LIKE ? OR action LIKE ?)'
            params[#params + 1] = '%gang%'
            params[#params + 1] = '%notoriety%'
        end
    end
    local limit = tonumber(filters.limit) or 200
    if limit < 1 then limit = 1 end
    if limit > 1000 then limit = 1000 end
    local sql = ([[SELECT id,
            COALESCE(org_type, 'org') AS org_type,
            COALESCE(org_name, job) AS org_name,
            job,
            action,
            actor_identifier,
            actor_name,
            target_identifier,
            target_name,
            COALESCE(metadata_json, payload) AS payload,
            created_at
        FROM bossmenu_audit
        WHERE %s
        ORDER BY id DESC
        LIMIT ?]]):format(table.concat(where, ' AND '))
    params[#params + 1] = limit
    local rows = MySQL.query.await(sql, params) or {}
    for i = 1, #rows do
        rows[i].payload = audDecode(rows[i].payload)
    end
    return rows
end
