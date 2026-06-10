InventoryModule = InventoryModule or {}
InventoryModule._stashReady = InventoryModule._stashReady or {}
InventoryModule._warned = InventoryModule._warned or {}

function InventoryModule.GetIntegration()
    local integrations = Config.Integrations or {}
    local mode = tostring(integrations.inventory or 'auto')
    if mode ~= 'auto' then
        return mode
    end
    if GetResourceState('ox_inventory') == 'started' then return 'ox_inventory' end
    if GetResourceState('qb-inventory') == 'started' then return 'qb-inventory' end
    if GetResourceState('ps-inventory') == 'started' then return 'ps-inventory' end
    if GetResourceState('lj-inventory') == 'started' then return 'lj-inventory' end
    if GetResourceState('qs-inventory') == 'started' then return 'qs-inventory' end
    return 'none'
end

local function invCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function invNum(value, min, max)
    local n = tonumber(value)
    if not n then return nil end
    if min and n < min then return nil end
    if max and n > max then return nil end
    return n
end

local function invWarnOnce(key, message)
    if InventoryModule._warned[key] then return end
    InventoryModule._warned[key] = true
    print(('[%s] inventory integration warning: %s'):format(GetCurrentResourceName(), message))
end

local function invCall(resource, fn, ...)
    local args = { ... }
    local ok, result = pcall(function()
        return exports[resource][fn](table.unpack(args))
    end)
    if not ok then return nil end
    return result
end

local function stashId(orgType, orgName)
    return ('bm:%s:%s'):format(tostring(orgType or 'boss'), tostring(orgName or 'unknown'))
end

local function ensureOxStash(orgType, orgName)
    local id = stashId(orgType, orgName)
    if InventoryModule._stashReady[id] then
        return id
    end
    local label = ('%s %s Stash'):format(orgType == 'gang' and 'Gang' or 'Organization', tostring(orgName))
    pcall(function()
        exports.ox_inventory:RegisterStash(id, label, 250, 1000000, false)
    end)
    InventoryModule._stashReady[id] = true
    return id
end

local function invAudit(orgType, orgName, action, actor, target, metadata)
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

function InventoryModule.IsEnabled()
    return Config.Modules and Config.Modules.BusinessInventory == true
end

local function moveViaOx(orgType, orgName, actorSource, item, amount, metadata, direction)
    local src = invNum(actorSource, 1)
    if not src then return false, 'Invalid source' end
    local stash = ensureOxStash(orgType, orgName)

    if direction == 'deposit' then
        local removed = invCall('ox_inventory', 'RemoveItem', src, item, amount, metadata)
        if removed ~= true then
            return false, 'Insufficient item amount'
        end
        local added = invCall('ox_inventory', 'AddItem', stash, item, amount, metadata)
        if added ~= true then
            invCall('ox_inventory', 'AddItem', src, item, amount, metadata)
            return false, 'Stash add failed'
        end
        return true
    end

    local removed = invCall('ox_inventory', 'RemoveItem', stash, item, amount, metadata)
    if removed ~= true then
        return false, 'Insufficient item amount'
    end
    local added = invCall('ox_inventory', 'AddItem', src, item, amount, metadata)
    if added ~= true then
        invCall('ox_inventory', 'AddItem', stash, item, amount, metadata)
        return false, 'Cannot carry item'
    end
    return true
end

local function moveViaQb(orgType, orgName, actorSource, item, amount, metadata, direction)
    local src = invNum(actorSource, 1)
    if not src then return false, 'Invalid source' end
    local stash = stashId(orgType, orgName)

    if direction == 'deposit' then
        local okRemove = invCall('qb-inventory', 'RemoveItem', src, item, amount, false, nil, 'qb-management')
        if okRemove ~= true then
            return false, 'Insufficient item amount'
        end
        local okAdd = invCall('qb-inventory', 'AddToStash', stash, item, amount, false, metadata or {}, 'qb-management')
        if okAdd ~= true then
            invCall('qb-inventory', 'AddItem', src, item, amount, false, metadata or {}, 'qb-management')
            return false, 'Stash add failed'
        end
        return true
    end

    local okTake = invCall('qb-inventory', 'RemoveFromStash', stash, item, amount, false, 'qb-management')
    if okTake ~= true then
        return false, 'Insufficient item amount'
    end
    local okGive = invCall('qb-inventory', 'AddItem', src, item, amount, false, metadata or {}, 'qb-management')
    if okGive ~= true then
        invCall('qb-inventory', 'AddToStash', stash, item, amount, false, metadata or {}, 'qb-management')
        return false, 'Cannot carry item'
    end
    return true
end

local function moveViaQbFamily(resourceName, orgType, orgName, actorSource, item, amount, metadata, direction)
    local src = invNum(actorSource, 1)
    if not src then return false, 'Invalid source' end
    local stash = stashId(orgType, orgName)

    if direction == 'deposit' then
        local okRemove = invCall(resourceName, 'RemoveItem', src, item, amount, false, nil, 'qb-management')
        if okRemove ~= true then
            return false, 'Insufficient item amount'
        end
        local okAdd = invCall(resourceName, 'AddToStash', stash, item, amount, false, metadata or {}, 'qb-management')
        if okAdd ~= true then
            invCall(resourceName, 'AddItem', src, item, amount, false, metadata or {}, 'qb-management')
            return false, 'Stash add failed'
        end
        return true
    end

    local okTake = invCall(resourceName, 'RemoveFromStash', stash, item, amount, false, 'qb-management')
    if okTake ~= true then
        return false, 'Insufficient item amount'
    end
    local okGive = invCall(resourceName, 'AddItem', src, item, amount, false, metadata or {}, 'qb-management')
    if okGive ~= true then
        invCall(resourceName, 'AddToStash', stash, item, amount, false, metadata or {}, 'qb-management')
        return false, 'Cannot carry item'
    end
    return true
end

local function moveViaQs(orgType, orgName, actorSource, item, amount, metadata, direction)
    local src = invNum(actorSource, 1)
    if not src then return false, 'Invalid source' end
    local stash = stashId(orgType, orgName)

    if direction == 'deposit' then
        local removed = invCall('qs-inventory', 'RemoveItem', src, item, amount)
        if removed ~= true then
            return false, 'Insufficient item amount'
        end
        local stored = invCall('qs-inventory', 'AddItemToStash', stash, item, amount, metadata or {})
        if stored ~= true then
            invCall('qs-inventory', 'AddItem', src, item, amount, metadata or {})
            return false, 'Stash add failed'
        end
        return true
    end

    local pulled = invCall('qs-inventory', 'RemoveItemFromStash', stash, item, amount)
    if pulled ~= true then
        return false, 'Insufficient item amount'
    end
    local given = invCall('qs-inventory', 'AddItem', src, item, amount, metadata or {})
    if given ~= true then
        invCall('qs-inventory', 'AddItemToStash', stash, item, amount, metadata or {})
        return false, 'Cannot carry item'
    end
    return true
end

function InventoryModule.GetItems(orgType, orgName)
    local backend = InventoryModule.GetIntegration()
    if backend == 'ox_inventory' then
        local stash = ensureOxStash(orgType, orgName)
        local items = invCall('ox_inventory', 'GetInventoryItems', stash) or {}
        local out = {}
        for i = 1, #items do
            local row = items[i]
            out[#out + 1] = {
                item_name = row.name or row.item or '',
                amount = tonumber(row.count or row.amount) or 0,
                metadata = row.metadata or {},
                updated_at = nil
            }
        end
        table.sort(out, function(a, b) return tostring(a.item_name) < tostring(b.item_name) end)
        return out
    end

    local rows = MySQL.query.await([[SELECT item_name, amount, metadata, updated_at
        FROM bossmenu_org_inventory
        WHERE org_type = ? AND org_name = ?
        ORDER BY item_name ASC]], { orgType, orgName }) or {}
    for i = 1, #rows do
        rows[i].amount = tonumber(rows[i].amount) or 0
        rows[i].metadata = (type(rows[i].metadata) == 'string' and json.decode(rows[i].metadata)) or rows[i].metadata or {}
    end
    return rows
end

function InventoryModule.ModifyItem(orgType, orgName, itemName, amountDelta, actor, actionLabel, metadata, actorSource)
    local item = invCleanText(itemName, 80)
    local delta = tonumber(amountDelta) or 0
    if item == '' or delta == 0 then
        return false, 'Invalid item or amount'
    end

    local backend = InventoryModule.GetIntegration()
    local direction = delta > 0 and 'deposit' or 'withdraw'
    local absDelta = math.abs(delta)
    local integrationOK = false
    local integrationErr = nil

    if backend == 'ox_inventory' then
        integrationOK, integrationErr = moveViaOx(orgType, orgName, actorSource, item, absDelta, metadata, direction)
    elseif backend == 'qb-inventory' then
        integrationOK, integrationErr = moveViaQb(orgType, orgName, actorSource, item, absDelta, metadata, direction)
    elseif backend == 'ps-inventory' then
        integrationOK, integrationErr = moveViaQbFamily('ps-inventory', orgType, orgName, actorSource, item, absDelta, metadata, direction)
    elseif backend == 'lj-inventory' then
        integrationOK, integrationErr = moveViaQbFamily('lj-inventory', orgType, orgName, actorSource, item, absDelta, metadata, direction)
    elseif backend == 'qs-inventory' then
        integrationOK, integrationErr = moveViaQs(orgType, orgName, actorSource, item, absDelta, metadata, direction)
    elseif backend ~= 'none' then
        invWarnOnce(backend, ('unknown backend "%s", using db fallback'):format(backend))
    end

    if backend ~= 'none' and backend ~= 'auto' then
        if integrationOK ~= true and integrationErr then
            return false, integrationErr
        end
        if integrationOK ~= true then
            invWarnOnce(backend .. ':fallback', ('backend "%s" action unsupported, using db fallback'):format(backend))
        end
    end

    MySQL.insert.await([[INSERT INTO bossmenu_org_inventory (org_type, org_name, item_name, amount, metadata)
        VALUES (?, ?, ?, 0, ?)
        ON DUPLICATE KEY UPDATE item_name = VALUES(item_name)]], {
        orgType, orgName, item, json.encode(metadata or {})
    })

    local affected = 0
    if delta > 0 then
        affected = MySQL.update.await([[UPDATE bossmenu_org_inventory
            SET amount = amount + ?, metadata = COALESCE(?, metadata), updated_at = NOW()
            WHERE org_type = ? AND org_name = ? AND item_name = ?]], {
            delta, metadata and json.encode(metadata) or nil, orgType, orgName, item
        })
    else
        affected = MySQL.update.await([[UPDATE bossmenu_org_inventory
            SET amount = amount + ?, metadata = COALESCE(?, metadata), updated_at = NOW()
            WHERE org_type = ? AND org_name = ? AND item_name = ? AND amount >= ?]], {
            delta, metadata and json.encode(metadata) or nil, orgType, orgName, item, math.abs(delta)
        })
    end

    if (affected or 0) < 1 then
        return false, 'Insufficient item amount'
    end

    MySQL.insert.await([[INSERT INTO bossmenu_org_inventory_logs (org_type, org_name, action, item_name, amount, actor_identifier, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        orgType, orgName, invCleanText(actionLabel, 24), item, absDelta, actor, metadata and json.encode(metadata) or nil
    })
    invAudit(orgType, orgName, 'inventory_' .. invCleanText(actionLabel, 24), actor, nil, {
        item = item,
        delta = delta,
        backend = backend
    })
    TriggerEvent('qb-management:server:hook', 'inventory_changed', {
        orgType = orgType,
        orgName = orgName,
        action = actionLabel,
        item = item,
        delta = delta,
        actor = actor
    })
    return true
end

function InventoryModule.GetLogs(orgType, orgName, limit)
    local nLimit = tonumber(limit) or 100
    if nLimit < 1 then nLimit = 1 end
    if nLimit > 500 then nLimit = 500 end
    local rows = MySQL.query.await([[SELECT id, action, item_name, amount, actor_identifier, target_identifier, metadata, created_at
        FROM bossmenu_org_inventory_logs
        WHERE org_type = ? AND org_name = ?
        ORDER BY id DESC
        LIMIT ?]], { orgType, orgName, nLimit }) or {}
    for i = 1, #rows do
        rows[i].metadata = (type(rows[i].metadata) == 'string' and json.decode(rows[i].metadata)) or rows[i].metadata or {}
    end
    return rows
end
