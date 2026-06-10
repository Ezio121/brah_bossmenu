TerritoriesModule = TerritoriesModule or {}

function TerritoriesModule.IsEnabled()
    return Config.Modules and Config.Modules.GangTerritories == true
end

local function terrCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function terrDecode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then
        return decoded
    end
    return {}
end

local function terrSrcNearCoords(src, coords, maxDistance)
    local nSrc = tonumber(src) or 0
    if nSrc < 1 then return false end
    local ped = GetPlayerPed(nSrc)
    if not ped or ped <= 0 then return false end
    local pos = GetEntityCoords(ped)
    local cx = tonumber(coords and coords.x) or nil
    local cy = tonumber(coords and coords.y) or nil
    local cz = tonumber(coords and coords.z) or nil
    if not cx or not cy or not cz then return false end
    local dist = #(vector3(pos.x, pos.y, pos.z) - vector3(cx, cy, cz))
    return dist <= (tonumber(maxDistance) or 25.0), dist
end

local function terrAudit(gangName, action, actor, metadata)
    if AuditModule and AuditModule.Write then
        AuditModule.Write('gang', gangName, 'territory_' .. tostring(action), actor, nil, metadata or {})
        return
    end
    MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
        VALUES (?, ?, ?, ?, ?)]], {
        gangName,
        'territory_' .. tostring(action),
        actor,
        nil,
        metadata and json.encode(metadata) or nil
    })
end

local function terrSystems()
    return Config.GangSystems or {}
end

local function terrDefendSeconds()
    return math.max(30, tonumber(terrSystems().territoryDefendSeconds) or 180)
end

local function terrRewardAmount()
    return math.max(0, tonumber(terrSystems().territoryReward) or 0)
end

local function terrLossPenalty()
    return math.max(0, tonumber(terrSystems().territoryLossPenalty) or 0)
end

local function terrTagCfg()
    local sys = terrSystems()
    return {
        enabled = sys.territoryTaggingEnabled == true,
        minVertices = math.max(3, tonumber(sys.territoryTagMinVertices) or 4),
        maxVertices = math.max(4, tonumber(sys.territoryTagMaxVertices) or 12),
        closeDistance = math.max(2.0, tonumber(sys.territoryTagCloseDistance) or 12.0),
        maxSpan = math.max(60.0, tonumber(sys.territoryTagMaxSpanMeters) or 350.0),
        minArea = math.max(200.0, tonumber(sys.territoryTagMinArea) or 800.0),
        maxArea = math.max(1200.0, tonumber(sys.territoryTagMaxArea) or 50000.0),
        maxPointAgeMinutes = math.max(5, tonumber(sys.territoryTagMaxPointAgeMinutes) or 45),
        territoryType = terrCleanText(sys.territoryTagTerritoryType or 'basic', 32)
    }
end

local function terrDist2(a, b)
    local ax, ay = tonumber(a and a.x) or 0.0, tonumber(a and a.y) or 0.0
    local bx, by = tonumber(b and b.x) or 0.0, tonumber(b and b.y) or 0.0
    local dx, dy = ax - bx, ay - by
    return math.sqrt((dx * dx) + (dy * dy))
end

local function terrPolygonArea(points)
    if type(points) ~= 'table' or #points < 3 then return 0.0 end
    local sum = 0.0
    for i = 1, #points do
        local j = (i % #points) + 1
        local xi, yi = tonumber(points[i].x) or 0.0, tonumber(points[i].y) or 0.0
        local xj, yj = tonumber(points[j].x) or 0.0, tonumber(points[j].y) or 0.0
        sum = sum + ((xi * yj) - (xj * yi))
    end
    return math.abs(sum) * 0.5
end

local function terrCentroid(points)
    local sx, sy, sz, n = 0.0, 0.0, 0.0, 0
    for i = 1, #points do
        local p = points[i]
        if p then
            sx = sx + (tonumber(p.x) or 0.0)
            sy = sy + (tonumber(p.y) or 0.0)
            sz = sz + (tonumber(p.z) or 0.0)
            n = n + 1
        end
    end
    if n < 1 then
        return { x = 0.0, y = 0.0, z = 0.0 }
    end
    return { x = sx / n, y = sy / n, z = sz / n }
end

local function terrMaxSpan(points)
    local maxD = 0.0
    for i = 1, #points do
        for j = i + 1, #points do
            local d = terrDist2(points[i], points[j])
            if d > maxD then
                maxD = d
            end
        end
    end
    return maxD
end

function TerritoriesModule.List(gangName)
    local rows = MySQL.query.await([[SELECT id, territory_name, territory_type, owner_gang, coords, metadata, updated_at
        FROM bossmenu_gang_territories
        ORDER BY territory_name ASC]]) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local metadata = terrDecode(row.metadata)
        if row.owner_gang == gangName or metadata.contestedBy == gangName then
            out[#out + 1] = {
                id = row.id,
                territory_name = row.territory_name,
                territory_type = row.territory_type,
                owner_gang = row.owner_gang,
                coords = terrDecode(row.coords),
                metadata = metadata,
                updated_at = row.updated_at
            }
        end
    end
    return out
end

function TerritoriesModule.Leaderboard()
    local days = math.max(1, tonumber(terrSystems().territoryLeaderboardDays) or 30)
    local rows = MySQL.query.await([[SELECT COALESCE(org_name, job) AS gang, COUNT(*) AS captures
        FROM bossmenu_audit
        WHERE action = 'territory_capture_complete'
          AND created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
        GROUP BY COALESCE(org_name, job)
        ORDER BY captures DESC
        LIMIT 20]], { days }) or {}
    return rows
end

function TerritoriesModule.BeginCapture(gangName, payload, actor, src)
    if not TerritoriesModule.IsEnabled() then
        return false, 'Territories disabled'
    end
    local territoryName = terrCleanText(payload and payload.territory, 80)
    local territoryType = terrCleanText(payload and payload.territoryType, 32)
    local coords = type(payload and payload.coords) == 'table' and payload.coords or { x = 0.0, y = 0.0, z = 0.0 }
    local minutes = tonumber(payload and payload.minutes) or 5
    if territoryName == '' then return false, 'Invalid territory' end
    if territoryType == '' then territoryType = 'basic' end

    local row = MySQL.single.await('SELECT id, owner_gang, metadata FROM bossmenu_gang_territories WHERE territory_name = ? LIMIT 1', { territoryName })
    local metadata = terrDecode(row and row.metadata)
    if row and tostring(row.owner_gang or '') == tostring(gangName) then
        return false, 'Your gang already owns this territory'
    end
    local now = os.time()
    local cooldownUntil = tonumber(metadata.cooldownUntil) or 0
    if cooldownUntil > now then
        return false, 'Territory is on cooldown'
    end
    metadata.contestedBy = gangName
    metadata.previousOwner = row and row.owner_gang or nil
    metadata.contestedAt = now
    metadata.defendUntil = now + terrDefendSeconds()
    metadata.contestedUntil = now + math.max(30, minutes * 60)
    metadata.captureActor = actor

    local distMax = tonumber(Config.Security and Config.Security.maxMarkerCreateDistance or 15.0) or 15.0
    local checkCoords = coords
    if row then
        local existing = MySQL.single.await('SELECT coords FROM bossmenu_gang_territories WHERE id = ? LIMIT 1', { row.id })
        local decoded = terrDecode(existing and existing.coords)
        if decoded and decoded.x and decoded.y and decoded.z then
            checkCoords = decoded
        end
    end
    local near = terrSrcNearCoords(src, checkCoords, distMax * 2.0)
    if not near then
        return false, 'Too far from territory'
    end

    if row then
        MySQL.update.await([[UPDATE bossmenu_gang_territories
            SET territory_type = ?, metadata = ?, updated_at = NOW()
            WHERE id = ?]], {
            territoryType, json.encode(metadata), row.id
        })
    else
        MySQL.insert.await([[INSERT INTO bossmenu_gang_territories (territory_name, territory_type, owner_gang, coords, metadata)
            VALUES (?, ?, NULL, ?, ?)]], {
            territoryName, territoryType, json.encode(coords), json.encode(metadata)
        })
    end
    terrAudit(gangName, 'capture_begin', actor, {
        territory = territoryName,
        territoryType = territoryType,
        contestedUntil = metadata.contestedUntil,
        defendUntil = metadata.defendUntil
    })

    TriggerEvent('qb-management:server:hook', 'territory_capture_started', {
        gang = gangName,
        territory = territoryName,
        contestedUntil = metadata.contestedUntil,
        defendUntil = metadata.defendUntil,
        actor = actor
    })
    return true, {
        territory = territoryName,
        contestedUntil = metadata.contestedUntil,
        defendUntil = metadata.defendUntil
    }
end

function TerritoriesModule.CompleteCapture(gangName, payload, actor, src)
    if not TerritoriesModule.IsEnabled() then
        return false, 'Territories disabled'
    end
    local territoryName = terrCleanText(payload and payload.territory, 80)
    local cooldownMinutes = tonumber(payload and payload.cooldownMinutes) or 30
    if territoryName == '' then return false, 'Invalid territory' end
    local row = MySQL.single.await('SELECT id, metadata, coords FROM bossmenu_gang_territories WHERE territory_name = ? LIMIT 1', { territoryName })
    if not row then return false, 'Territory not found' end

    local metadata = terrDecode(row.metadata)
    if tostring(metadata.contestedBy or '') ~= tostring(gangName) then
        return false, 'Territory is not contested by your gang'
    end
    local now = os.time()
    local defendUntil = tonumber(metadata.defendUntil) or 0
    if defendUntil > now then
        return false, 'Defend timer still active'
    end

    local distMax = tonumber(Config.Security and Config.Security.maxMarkerCreateDistance or 15.0) or 15.0
    local near = terrSrcNearCoords(src, terrDecode(row.coords), distMax * 2.0)
    if not near then
        return false, 'Too far from territory'
    end

    metadata.contestedBy = nil
    metadata.contestedUntil = nil
    metadata.defendUntil = nil
    metadata.cooldownUntil = os.time() + math.max(60, cooldownMinutes * 60)
    metadata.lastCapturedBy = gangName
    metadata.lastCaptureActor = actor
    local previousOwner = metadata.previousOwner
    metadata.previousOwner = nil
    local reward = terrRewardAmount()
    local penalty = terrLossPenalty()

    MySQL.update.await([[UPDATE bossmenu_gang_territories
        SET owner_gang = ?, metadata = ?, updated_at = NOW()
        WHERE id = ?]], {
        gangName, json.encode(metadata), row.id
    })
    terrAudit(gangName, 'capture_complete', actor, {
        territory = territoryName,
        cooldownUntil = metadata.cooldownUntil,
        reward = reward,
        previousOwner = previousOwner,
        penalty = penalty
    })

    TriggerEvent('qb-management:server:hook', 'territory_capture_completed', {
        gang = gangName,
        territory = territoryName,
        cooldownUntil = metadata.cooldownUntil,
        reward = reward,
        previousOwner = previousOwner,
        penalty = penalty,
        actor = actor
    })
    return true, {
        territory = territoryName,
        owner = gangName,
        cooldownUntil = metadata.cooldownUntil,
        previousOwner = previousOwner,
        reward = reward,
        penalty = penalty
    }
end

function TerritoriesModule.TryAutoClaimFromGraffiti(gangName, actor, src, payload)
    local cfg = terrTagCfg()
    if not TerritoriesModule.IsEnabled() or cfg.enabled ~= true then
        return false, 'Territory tagging disabled'
    end

    local rows = MySQL.query.await([[SELECT id, coords, metadata, UNIX_TIMESTAMP(created_at) AS created_ts
        FROM bossmenu_gang_graffiti
        WHERE gang_name = ?
        ORDER BY id DESC
        LIMIT 500]], { gangName }) or {}
    if #rows < cfg.minVertices + 1 then
        return false, 'Not enough tag points'
    end

    local now = os.time()
    local pathIdWanted = terrCleanText(payload and payload.pathId, 64)
    local pointsDesc = {}
    for i = 1, #rows do
        local row = rows[i]
        local metadata = terrDecode(row.metadata)
        local coords = terrDecode(row.coords)
        local tagKind = terrCleanText(metadata.tagKind or '', 32)
        if (metadata.territoryPoint == true or tagKind == 'territory_point') and coords.x and coords.y then
            local use = true
            if pathIdWanted ~= '' then
                use = terrCleanText(metadata.pathId, 64) == pathIdWanted
            end
            if use then
                local createdAt = tonumber(row.created_ts) or now
                if (now - createdAt) <= (cfg.maxPointAgeMinutes * 60) then
                    pointsDesc[#pointsDesc + 1] = {
                        id = tonumber(row.id),
                        x = tonumber(coords.x) or 0.0,
                        y = tonumber(coords.y) or 0.0,
                        z = tonumber(coords.z) or 0.0
                    }
                end
            end
        end
    end

    if #pointsDesc < cfg.minVertices + 1 then
        return false, 'Not enough recent territory tag points'
    end

    local points = {}
    local maxCount = math.min(#pointsDesc, cfg.maxVertices + 1)
    for i = maxCount, 1, -1 do
        points[#points + 1] = pointsDesc[i]
    end
    if #points < cfg.minVertices + 1 then
        return false, 'Not enough vertices'
    end

    local first = points[1]
    local last = points[#points]
    if terrDist2(first, last) > cfg.closeDistance then
        return false, 'Polygon not closed yet'
    end

    local polygon = {}
    for i = 1, #points - 1 do
        polygon[#polygon + 1] = points[i]
    end
    if #polygon < cfg.minVertices then
        return false, 'Polygon needs more corners'
    end

    local span = terrMaxSpan(polygon)
    if span > cfg.maxSpan then
        return false, 'Territory polygon too large'
    end

    local area = terrPolygonArea(polygon)
    if area < cfg.minArea then
        return false, 'Territory polygon too small'
    end
    if area > cfg.maxArea then
        return false, 'Territory polygon too large'
    end

    local center = terrCentroid(polygon)
    local near = terrSrcNearCoords(src, center, (tonumber(Config.Security and Config.Security.maxMarkerCreateDistance or 15.0) or 15.0) * 8.0)
    if not near then
        return false, 'Too far from tag territory center'
    end

    local pathPart = pathIdWanted ~= '' and pathIdWanted or tostring(points[#points].id or os.time())
    local territoryName = terrCleanText((payload and payload.territory) or ('TAG-' .. string.upper(gangName) .. '-' .. pathPart), 80)
    if territoryName == '' then
        territoryName = ('TAG-%s-%d'):format(string.upper(gangName), os.time())
    end

    local row = MySQL.single.await('SELECT id, owner_gang, metadata FROM bossmenu_gang_territories WHERE territory_name = ? LIMIT 1', { territoryName })
    local metadata = terrDecode(row and row.metadata)
    metadata.createdByTags = true
    metadata.polygon = polygon
    metadata.closedByTagId = last.id
    metadata.tagPointIds = {}
    for i = 1, #polygon do
        metadata.tagPointIds[#metadata.tagPointIds + 1] = polygon[i].id
    end
    metadata.lastCapturedBy = gangName
    metadata.lastCaptureActor = actor
    metadata.lastPolygonArea = area
    metadata.lastPolygonSpan = span
    metadata.lastPolygonAt = os.time()
    metadata.cooldownUntil = nil
    metadata.contestedBy = nil
    metadata.contestedUntil = nil
    metadata.defendUntil = nil

    if row then
        MySQL.update.await([[UPDATE bossmenu_gang_territories
            SET owner_gang = ?, territory_type = ?, coords = ?, metadata = ?, updated_at = NOW()
            WHERE id = ?]], {
            gangName, cfg.territoryType ~= '' and cfg.territoryType or 'basic', json.encode(center), json.encode(metadata), row.id
        })
    else
        MySQL.insert.await([[INSERT INTO bossmenu_gang_territories (territory_name, territory_type, owner_gang, coords, metadata)
            VALUES (?, ?, ?, ?, ?)]], {
            territoryName, cfg.territoryType ~= '' and cfg.territoryType or 'basic', gangName, json.encode(center), json.encode(metadata)
        })
    end

    terrAudit(gangName, 'capture_complete', actor, {
        territory = territoryName,
        autoFromTags = true,
        area = area,
        span = span,
        points = #polygon
    })
    TriggerEvent('qb-management:server:hook', 'territory_capture_completed', {
        gang = gangName,
        territory = territoryName,
        actor = actor,
        autoFromTags = true,
        area = area,
        span = span,
        points = #polygon
    })
    return true, {
        territory = territoryName,
        owner = gangName,
        autoFromTags = true,
        area = area,
        span = span,
        points = #polygon,
        coords = center,
        polygon = polygon
    }
end
