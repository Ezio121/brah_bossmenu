GangsModule = GangsModule or {}

function GangsModule.IsEnabled()
    return Config.EnableGangMenu == true
end

local function gangCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function gangAudit(orgName, action, actor, target, metadata)
    if AuditModule and AuditModule.Write then
        AuditModule.Write('gang', orgName, 'gang:' .. action, actor, target, metadata or {})
        return
    end
    MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
        VALUES (?, ?, ?, ?, ?)]], {
        orgName,
        'gang:' .. action,
        actor,
        target,
        metadata and json.encode(metadata) or nil
    })
end

local function gsConfig()
    return Config.GangSystems or {}
end

local function gsNumber(value, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    return n
end

local function gsNow()
    return os.time()
end

function GangsModule.IsNotorietyEnabled()
    return Config.Modules and Config.Modules.GangNotoriety == true
end

function GangsModule.GetNotoriety(gangName)
    local row = MySQL.single.await('SELECT points, updated_at FROM bossmenu_gang_notoriety WHERE gang_name = ? LIMIT 1', { gangName })
    if not row then
        return { points = 0, updatedAt = nil }
    end
    return {
        points = tonumber(row.points) or 0,
        updatedAt = row.updated_at
    }
end

function GangsModule.ModifyNotoriety(gangName, amount, reason, actor)
    if not GangsModule.IsNotorietyEnabled() then
        return false, 'Notoriety disabled'
    end
    local n = tonumber(amount) or 0
    if n == 0 then
        return false, 'Invalid amount'
    end
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_gang_notoriety (gang_name, points) VALUES (?, 0)', { gangName })
    if n > 0 then
        MySQL.update.await('UPDATE bossmenu_gang_notoriety SET points = points + ?, updated_at = NOW() WHERE gang_name = ?', { n, gangName })
    else
        MySQL.update.await('UPDATE bossmenu_gang_notoriety SET points = GREATEST(points + ?, 0), updated_at = NOW() WHERE gang_name = ?', { n, gangName })
    end
    gangAudit(gangName, 'notoriety_change', actor, nil, { amount = n, reason = gangCleanText(reason, 255) })
    TriggerEvent('qb-management:server:hook', 'OnGangNotorietyChanged', {
        gang = gangName,
        delta = n,
        reason = reason,
        actor = actor
    })
    return true, GangsModule.GetNotoriety(gangName)
end

function GangsModule.UpsertMarker(gangName, payload, actor)
    if Config.Modules and Config.Modules.GangMarkers ~= true then
        return false, 'Gang markers disabled'
    end
    local markerType = gangCleanText(payload and payload.markerType, 32)
    local coords = type(payload and payload.coords) == 'table' and payload.coords or nil
    local markerData = type(payload and payload.data) == 'table' and payload.data or {}
    local id = tonumber(payload and payload.id) or 0
    if markerType == '' or not coords then
        return false, 'Invalid marker payload'
    end

    if id > 0 then
        local affected = MySQL.update.await([[UPDATE bossmenu_gang_markers
            SET marker_type = ?, coords = ?, marker_data = ?
            WHERE id = ? AND gang_name = ?]], {
            markerType, json.encode(coords), json.encode(markerData), id, gangName
        })
        if (affected or 0) < 1 then
            return false, 'Marker not found'
        end
    else
        id = MySQL.insert.await([[INSERT INTO bossmenu_gang_markers (gang_name, marker_type, coords, marker_data, created_by)
            VALUES (?, ?, ?, ?, ?)]], {
            gangName, markerType, json.encode(coords), json.encode(markerData), actor
        })
    end
    gangAudit(gangName, 'marker_upsert', actor, nil, { id = id, markerType = markerType })
    return true, { id = id }
end

function GangsModule.ListMarkers(gangName)
    local rows = MySQL.query.await([[SELECT id, marker_type, coords, marker_data, created_by, created_at
        FROM bossmenu_gang_markers
        WHERE gang_name = ?
        ORDER BY id DESC]], { gangName }) or {}
    for i = 1, #rows do
        rows[i].coords = (type(rows[i].coords) == 'string' and json.decode(rows[i].coords)) or rows[i].coords or {}
        rows[i].marker_data = (type(rows[i].marker_data) == 'string' and json.decode(rows[i].marker_data)) or rows[i].marker_data or {}
    end
    return rows
end

function GangsModule.DeleteMarker(gangName, markerId, actor)
    local id = tonumber(markerId) or 0
    if id < 1 then return false, 'Invalid marker' end
    local affected = MySQL.update.await('DELETE FROM bossmenu_gang_markers WHERE id = ? AND gang_name = ?', { id, gangName })
    if (affected or 0) < 1 then
        return false, 'Marker not found'
    end
    gangAudit(gangName, 'marker_delete', actor, nil, { id = id })
    return true
end

function GangsModule.IsRacketsEnabled()
    return Config.Modules and Config.Modules.GangRackets == true
end

function GangsModule.IsGraffitiEnabled()
    return Config.Modules and Config.Modules.GangGraffiti == true
end

function GangsModule.ListRackets(gangName)
    local rows = MySQL.query.await([[SELECT id, territory_name, level, stored_income, upgrades, updated_at
        FROM bossmenu_gang_rackets
        WHERE gang_name = ?
        ORDER BY id DESC]], { gangName }) or {}
    for i = 1, #rows do
        rows[i].upgrades = (type(rows[i].upgrades) == 'string' and json.decode(rows[i].upgrades)) or rows[i].upgrades or {}
    end
    return rows
end

function GangsModule.UpsertRacket(gangName, payload, actor)
    if not GangsModule.IsRacketsEnabled() then
        return false, 'Rackets disabled'
    end
    local id = tonumber(payload and payload.id) or 0
    local territory = gangCleanText(payload and payload.territory, 80)
    local level = math.max(1, tonumber(payload and payload.level) or 1)
    local income = math.max(0, tonumber(payload and payload.storedIncome) or 0)
    local upgrades = type(payload and payload.upgrades) == 'table' and payload.upgrades or {}
    local sanitized = {
        income_rate = math.max(0, math.min(50, tonumber(upgrades.income_rate) or 0)),
        storage_capacity = math.max(0, math.min(50, tonumber(upgrades.storage_capacity) or 0)),
        security = math.max(0, math.min(50, tonumber(upgrades.security) or 0)),
        cooldown_reduction = math.max(0, math.min(50, tonumber(upgrades.cooldown_reduction) or 0)),
        _lastTick = tonumber(upgrades._lastTick) or gsNow(),
        _lastClaimAt = tonumber(upgrades._lastClaimAt) or 0
    }
    level = math.max(level, 1 + math.floor((sanitized.income_rate + sanitized.storage_capacity + sanitized.security + sanitized.cooldown_reduction) / 10))

    if id > 0 then
        local affected = MySQL.update.await([[UPDATE bossmenu_gang_rackets
            SET territory_name = ?, level = ?, stored_income = ?, upgrades = ?, updated_at = NOW()
            WHERE id = ? AND gang_name = ?]], {
            territory ~= '' and territory or nil, level, income, json.encode(sanitized), id, gangName
        })
        if (affected or 0) < 1 then
            return false, 'Racket not found'
        end
    else
        id = MySQL.insert.await([[INSERT INTO bossmenu_gang_rackets (gang_name, territory_name, level, stored_income, upgrades)
            VALUES (?, ?, ?, ?, ?)]], {
            gangName, territory ~= '' and territory or nil, level, income, json.encode(sanitized)
        })
    end
    gangAudit(gangName, 'racket_upsert', actor, nil, {
        id = id,
        territory = territory,
        level = level,
        upgrades = sanitized
    })
    return true, { id = id }
end

function GangsModule.UpgradeRacket(gangName, racketId, upgradeType, actor)
    if not GangsModule.IsRacketsEnabled() then
        return false, 'Rackets disabled'
    end
    local id = tonumber(racketId) or 0
    if id < 1 then return false, 'Invalid racket' end
    local uType = gangCleanText(upgradeType, 32)
    if uType ~= 'income_rate' and uType ~= 'storage_capacity' and uType ~= 'security' and uType ~= 'cooldown_reduction' then
        return false, 'Invalid upgrade type'
    end

    local row = MySQL.single.await('SELECT level, upgrades FROM bossmenu_gang_rackets WHERE id = ? AND gang_name = ? LIMIT 1', { id, gangName })
    if not row then
        return false, 'Racket not found'
    end
    local upgrades = (type(row.upgrades) == 'string' and json.decode(row.upgrades)) or row.upgrades or {}
    local current = tonumber(upgrades[uType]) or 0
    if current >= 50 then
        return false, 'Upgrade maxed'
    end
    upgrades[uType] = current + 1
    upgrades._lastTick = tonumber(upgrades._lastTick) or gsNow()
    local level = math.max(1, tonumber(row.level) or 1)
    if (current + 1) % 5 == 0 then
        level = level + 1
    end
    MySQL.update.await('UPDATE bossmenu_gang_rackets SET level = ?, upgrades = ?, updated_at = NOW() WHERE id = ?', {
        level, json.encode(upgrades), id
    })
    gangAudit(gangName, 'racket_upgrade', actor, nil, { id = id, upgradeType = uType, value = upgrades[uType], level = level })
    return true, {
        id = id,
        level = level,
        upgrades = upgrades
    }
end

function GangsModule.ClaimRacketIncome(gangName, racketId, actor)
    if not GangsModule.IsRacketsEnabled() then
        return false, 'Rackets disabled'
    end
    local id = tonumber(racketId) or 0
    if id < 1 then return false, 'Invalid racket' end
    local row = MySQL.single.await('SELECT id, stored_income, upgrades FROM bossmenu_gang_rackets WHERE id = ? AND gang_name = ? LIMIT 1', { id, gangName })
    if not row then return false, 'Racket not found' end
    local amount = tonumber(row.stored_income) or 0
    if amount <= 0 then return false, 'No income available' end
    local upgrades = (type(row.upgrades) == 'string' and json.decode(row.upgrades)) or row.upgrades or {}
    local now = gsNow()
    local cooldown = math.max(10, 60 - math.floor((tonumber(upgrades.cooldown_reduction) or 0) / 2))
    local lastClaimAt = tonumber(upgrades._lastClaimAt) or 0
    if lastClaimAt > 0 and now - lastClaimAt < cooldown then
        return false, 'Racket claim cooldown active'
    end
    upgrades._lastClaimAt = now
    MySQL.update.await('UPDATE bossmenu_gang_rackets SET stored_income = 0, upgrades = ?, updated_at = NOW() WHERE id = ?', {
        json.encode(upgrades), id
    })
    gangAudit(gangName, 'racket_claim', actor, nil, { id = id, amount = amount })
    return true, { amount = amount, cooldownSeconds = cooldown }
end

function GangsModule.TickRackets()
    if not GangsModule.IsRacketsEnabled() then
        return 0
    end
    local rows = MySQL.query.await('SELECT id, gang_name, level, stored_income, upgrades FROM bossmenu_gang_rackets') or {}
    local tickMinutes = math.max(5, gsNumber(gsConfig().racketIncomeTickMinutes, 20))
    local baseIncome = math.max(1, gsNumber(gsConfig().racketBaseIncome, 250))
    local touched = 0
    local now = gsNow()
    for i = 1, #rows do
        local row = rows[i]
        local upgrades = (type(row.upgrades) == 'string' and json.decode(row.upgrades)) or row.upgrades or {}
        local lastTick = tonumber(upgrades._lastTick) or now
        local elapsed = now - lastTick
        if elapsed >= tickMinutes * 60 then
            local ticks = math.floor(elapsed / (tickMinutes * 60))
            local level = math.max(1, tonumber(row.level) or 1)
            local incomeRate = tonumber(upgrades.income_rate) or 0
            local storageCap = 10000 + (tonumber(upgrades.storage_capacity) or 0) * 500
            local perTick = math.floor((baseIncome * level) * (1 + (incomeRate * 0.02)))
            local newStored = (tonumber(row.stored_income) or 0) + (ticks * perTick)
            if newStored > storageCap then
                newStored = storageCap
            end
            upgrades._lastTick = now
            MySQL.update.await('UPDATE bossmenu_gang_rackets SET stored_income = ?, upgrades = ?, updated_at = NOW() WHERE id = ?', {
                newStored, json.encode(upgrades), row.id
            })
            touched = touched + 1
        end
    end
    return touched
end

function GangsModule.ListGraffiti(gangName)
    MySQL.update.await('DELETE FROM bossmenu_gang_graffiti WHERE expires_at IS NOT NULL AND expires_at <= NOW()')
    local rows = MySQL.query.await([[SELECT id, gang_name, style_name, text_label, coords, metadata, expires_at, placed_by, created_at
        FROM bossmenu_gang_graffiti
        WHERE gang_name = ?
        ORDER BY id DESC
        LIMIT 500]], { gangName }) or {}
    for i = 1, #rows do
        rows[i].coords = (type(rows[i].coords) == 'string' and json.decode(rows[i].coords)) or rows[i].coords or {}
        rows[i].metadata = (type(rows[i].metadata) == 'string' and json.decode(rows[i].metadata)) or rows[i].metadata or {}
    end
    return rows
end

function GangsModule.ListWorldGraffiti()
    MySQL.update.await('DELETE FROM bossmenu_gang_graffiti WHERE expires_at IS NOT NULL AND expires_at <= NOW()')
    local rows = MySQL.query.await([[SELECT id, gang_name, style_name, text_label, coords, metadata, expires_at, placed_by, created_at
        FROM bossmenu_gang_graffiti
        ORDER BY id DESC
        LIMIT 1200]]) or {}
    for i = 1, #rows do
        rows[i].coords = (type(rows[i].coords) == 'string' and json.decode(rows[i].coords)) or rows[i].coords or {}
        rows[i].metadata = (type(rows[i].metadata) == 'string' and json.decode(rows[i].metadata)) or rows[i].metadata or {}
    end
    return rows
end

function GangsModule.PlaceGraffiti(gangName, payload, actor, actorSource)
    if not GangsModule.IsGraffitiEnabled() then
        return false, 'Graffiti disabled'
    end
    local style = gangCleanText(payload and payload.style, 64)
    local text = gangCleanText(payload and payload.text, 120)
    local coords = type(payload and payload.coords) == 'table' and payload.coords or nil
    local territoryPoint = payload and payload.territoryPoint == true
    local ttlMinutes = tonumber(payload and payload.ttlMinutes)
    if not ttlMinutes then
        ttlMinutes = territoryPoint and gsNumber(gsConfig().territoryTagDefaultTtlMinutes, 0) or gsNumber(gsConfig().graffitiDefaultTtlMinutes, 120)
    end
    if not coords then return false, 'Invalid coords' end
    local gangMax = math.max(10, gsNumber(gsConfig().graffitiMaxPerGang, 120))
    local playerMax = math.max(5, gsNumber(gsConfig().graffitiMaxPerPlayer, 30))
    local minDistance = math.max(1.0, gsNumber(gsConfig().graffitiMinDistance, 8.0))

    local gangCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bossmenu_gang_graffiti WHERE gang_name = ?', { gangName }) or 0) or 0
    if gangCount >= gangMax then
        return false, 'Gang graffiti limit reached'
    end
    local playerCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bossmenu_gang_graffiti WHERE gang_name = ? AND placed_by = ?', {
        gangName, actor
    }) or 0) or 0
    if playerCount >= playerMax then
        return false, 'Player graffiti limit reached'
    end

    local rows = MySQL.query.await('SELECT id, coords FROM bossmenu_gang_graffiti WHERE gang_name = ? ORDER BY id DESC LIMIT 300', { gangName }) or {}
    local cx, cy, cz = tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0
    for i = 1, #rows do
        local c = (type(rows[i].coords) == 'string' and json.decode(rows[i].coords)) or rows[i].coords or {}
        local dx = (tonumber(c.x) or 0.0) - cx
        local dy = (tonumber(c.y) or 0.0) - cy
        local dz = (tonumber(c.z) or 0.0) - cz
        local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
        if dist < minDistance then
            return false, 'Graffiti too close to existing tag'
        end
    end

    local metadata = type(payload and payload.metadata) == 'table' and payload.metadata or {}
    metadata.tagKind = territoryPoint and 'territory_point' or (metadata.tagKind or 'graffiti')
    metadata.pathId = metadata.pathId or tostring(payload and payload.pathId or '')
    metadata.wallNormal = type(payload and payload.wallNormal) == 'table' and payload.wallNormal or metadata.wallNormal
    metadata.surface = metadata.surface or (payload and payload.surface)
    local expiresAt = nil
    if tonumber(ttlMinutes) and tonumber(ttlMinutes) > 0 then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + math.max(60, tonumber(ttlMinutes) * 60))
    end
    local id = MySQL.insert.await([[INSERT INTO bossmenu_gang_graffiti (gang_name, style_name, text_label, coords, metadata, expires_at, placed_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        gangName, style ~= '' and style or nil, text ~= '' and text or nil, json.encode(coords), json.encode(metadata), expiresAt, actor
    })
    gangAudit(gangName, 'graffiti_place', actor, nil, { id = id, style = style, text = text, tagKind = metadata.tagKind })
    return true, {
        id = id,
        gang_name = gangName,
        style_name = style ~= '' and style or nil,
        text_label = text ~= '' and text or nil,
        coords = coords,
        metadata = metadata,
        expires_at = expiresAt,
        placed_by = actor
    }
end

function GangsModule.DeleteGraffiti(gangName, graffitiId, actor, actorSource, allowCrossGang)
    if not GangsModule.IsGraffitiEnabled() then
        return false, 'Graffiti disabled'
    end
    local id = tonumber(graffitiId) or 0
    if id < 1 then return false, 'Invalid graffiti' end
    local row = MySQL.single.await('SELECT id, gang_name, coords FROM bossmenu_gang_graffiti WHERE id = ? LIMIT 1', { id })
    if not row then
        return false, 'Graffiti not found'
    end

    local src = tonumber(actorSource) or 0
    if src > 0 then
        local ped = GetPlayerPed(src)
        if ped and ped > 0 then
            local pos = GetEntityCoords(ped)
            local coords = (type(row.coords) == 'string' and json.decode(row.coords)) or row.coords or {}
            local dx = (tonumber(coords.x) or 0.0) - pos.x
            local dy = (tonumber(coords.y) or 0.0) - pos.y
            local dz = (tonumber(coords.z) or 0.0) - pos.z
            local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
            local maxDist = tonumber(Config.Security and Config.Security.maxMarkerCreateDistance or 15.0) or 15.0
            if dist > (maxDist * 2.0) then
                return false, 'Too far from graffiti position'
            end
        end
    end

    if allowCrossGang ~= true and tostring(row.gang_name or '') ~= tostring(gangName or '') then
        return false, 'Cannot clean rival gang graffiti'
    end

    local affected = MySQL.update.await('DELETE FROM bossmenu_gang_graffiti WHERE id = ?', { id })
    if (affected or 0) < 1 then
        return false, 'Graffiti not found'
    end
    gangAudit(gangName, 'graffiti_delete', actor, nil, { id = id, targetGang = row.gang_name, crossGang = allowCrossGang == true })
    return true, { id = id, targetGang = row.gang_name }
end
