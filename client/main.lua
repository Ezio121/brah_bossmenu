local uiOpen = false
local sessionToken = nil
local playerData = nil
local customGangRole = nil
local pending = {}
local requestId = 0
local worldGraffiti = {}
local lastGraffitiSyncAt = 0
local graffitiTextureCache = {}
local graffitiTextureCap = 64

local function refreshPlayerData()
    playerData = Framework.GetClientPlayerData()
end

local function useInbuiltGangFrames()
    local value = Config.useinbuiltgangframes
    if value == nil then value = Config.UseInbuiltGangFrames end
    if value == nil then return true end
    return value == true
end

local function usingCustomGangBackend()
    local framework = Framework.GetName()
    return Config.EnableGangMenu == true and (not useInbuiltGangFrames()) and (framework == 'qb' or framework == 'esx')
end

local function hasRoleAccess(role, minGrade)
    if not role or not role.name then return false end
    if role.isBoss then return true end
    return (role.grade or 0) >= (tonumber(minGrade) or 99)
end

local function isBoss()
    return hasRoleAccess(playerData and playerData.job, Config.MinBossGrade)
end

local function isGangBoss()
    local role = customGangRole or (playerData and playerData.gang)
    return hasRoleAccess(role, Config.MinGangBossGrade)
end

local function roleName(menuType)
    if menuType == 'gang' then
        local role = customGangRole or (playerData and playerData.gang)
        return role and role.name
    end
    return playerData and playerData.job and playerData.job.name
end

local function isAtOwnRole(menuType, groupName)
    return roleName(menuType) == groupName
end

local function canOpenMenu(menuType)
    if menuType == 'gang' then
        if Config.EnableGangMenu ~= true then return false end
        if isGangBoss() then return true end
        return usingCustomGangBackend()
    end
    return isBoss()
end

local function closeUi()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function gangSystemsCfg()
    return type(Config.GangSystems) == 'table' and Config.GangSystems or {}
end

local function clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

local function uriEncode(input)
    input = tostring(input or '')
    input = input:gsub('\n', '\r\n')
    input = input:gsub('([^%w%-_%.~ ])', function(char)
        return string.format('%%%02X', string.byte(char))
    end)
    return (input:gsub(' ', '%%20'))
end

local function hashString(input)
    local h = 2166136261
    input = tostring(input or '')
    for i = 1, #input do
        h = (h ~ string.byte(input, i)) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    end
    return h
end

local function releaseGraffitiTexture(id)
    local entry = graffitiTextureCache[id]
    if not entry then return end
    if entry.dui then
        DestroyDui(entry.dui)
    end
    graffitiTextureCache[id] = nil
end

local function enforceGraffitiTextureCap()
    local count = 0
    for _ in pairs(graffitiTextureCache) do count = count + 1 end
    if count <= graffitiTextureCap then return end
    local sorted = {}
    for id, entry in pairs(graffitiTextureCache) do
        sorted[#sorted + 1] = { id = id, lastSeen = tonumber(entry.lastSeen or 0) or 0 }
    end
    table.sort(sorted, function(a, b) return a.lastSeen < b.lastSeen end)
    local toDrop = count - graffitiTextureCap
    for i = 1, toDrop do
        local row = sorted[i]
        if row then
            releaseGraffitiTexture(row.id)
        end
    end
end

local function buildGraffitiMarkup(render)
    local tagData = {
        text = tostring(render.text or ''),
        gang = tostring(render.gang or ''),
        style = tostring(render.style or 'street'),
        seed = tonumber(render.seed or 0) or 0,
        r = tonumber(render.r or 235) or 235,
        g = tonumber(render.g or 185) or 185,
        b = tonumber(render.b or 95) or 95,
        drift = tonumber(render.drift or 0.0) or 0.0
    }
    local payload = json.encode(tagData) or '{}'
    return ([[<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<style>
html, body { margin:0; padding:0; width:100%%; height:100%%; background:transparent; overflow:hidden; }
canvas { width:100%%; height:100%%; background:transparent; image-rendering:auto; }
</style>
</head>
<body>
<canvas id="c" width="1024" height="512"></canvas>
<script>
const cfg = %s;
const cvs = document.getElementById('c');
const ctx = cvs.getContext('2d', { alpha: true });
let seed = (cfg.seed >>> 0) || 1;
function rnd(){ seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; }
function c(v){ return Math.max(0, Math.min(255, Math.round(v))); }
function rgba(r,g,b,a){ return `rgba(${c(r)},${c(g)},${c(b)},${Math.max(0, Math.min(1, a))})`; }
function pick(a){ return a[Math.floor(rnd() * a.length)] || a[0]; }
ctx.clearRect(0, 0, cvs.width, cvs.height);
const w = cvs.width, h = cvs.height;
const text = (cfg.text && String(cfg.text).trim().length > 0 ? String(cfg.text) : String(cfg.gang || 'TAG')).slice(0, 36);
const baseR = cfg.r || 225, baseG = cfg.g || 175, baseB = cfg.b || 95;
const fonts = ['Impact','Arial Black','Trebuchet MS','Verdana','Tahoma','Brush Script MT'];
const fontSize = 148 + Math.floor(rnd() * 34);
const skew = (-0.18 + rnd() * 0.36);
const rot = (-0.11 + rnd() * 0.22) + (Number(cfg.drift) || 0);
const posX = w * 0.5 + ((rnd() - 0.5) * 40);
const posY = h * 0.56 + ((rnd() - 0.5) * 36);
ctx.save();
ctx.translate(posX, posY);
ctx.rotate(rot);
ctx.transform(1, 0, skew, 1, 0, 0);
ctx.textAlign = 'center';
ctx.textBaseline = 'middle';
ctx.font = `italic ${fontSize}px ${pick(fonts)}`;
ctx.lineJoin = 'round';
ctx.lineCap = 'round';
const outline = 14 + Math.floor(rnd() * 10);
for(let i=0;i<6;i++){
  ctx.strokeStyle = rgba(8, 12, 18, 0.42 - (i * 0.055));
  ctx.lineWidth = outline + i * 3;
  ctx.strokeText(text, i * 0.8 - 2, i * 0.45 - 1);
}
const grad = ctx.createLinearGradient(-w*0.34, -h*0.18, w*0.36, h*0.18);
grad.addColorStop(0, rgba(baseR + 36, baseG + 36, baseB + 30, 0.96));
grad.addColorStop(0.55, rgba(baseR, baseG, baseB, 0.98));
grad.addColorStop(1, rgba(baseR - 42, baseG - 34, baseB - 34, 0.95));
ctx.fillStyle = grad;
ctx.shadowColor = rgba(baseR + 10, baseG + 10, baseB + 10, 0.26);
ctx.shadowBlur = 18;
ctx.fillText(text, 0, 0);
ctx.shadowBlur = 0;
ctx.lineWidth = Math.max(3, Math.floor(outline * 0.34));
ctx.strokeStyle = rgba(250, 242, 220, 0.44);
ctx.strokeText(text, 0, 0);
for(let i=0;i<220;i++){
  const rx = (rnd() - 0.5) * (w * 0.72);
  const ry = (rnd() - 0.5) * (h * 0.40);
  const rad = 0.8 + rnd() * 2.2;
  const alpha = 0.07 + rnd() * 0.11;
  ctx.fillStyle = rgba(baseR + (rnd()-0.5)*50, baseG + (rnd()-0.5)*40, baseB + (rnd()-0.5)*45, alpha);
  ctx.beginPath();
  ctx.arc(rx, ry, rad, 0, Math.PI * 2);
  ctx.fill();
}
const dripCount = 8 + Math.floor(rnd() * 10);
ctx.strokeStyle = rgba(baseR + 8, baseG + 4, baseB + 4, 0.58);
ctx.fillStyle = rgba(baseR + 14, baseG + 8, baseB + 6, 0.46);
for(let i=0;i<dripCount;i++){
  const dx = (rnd() - 0.5) * (w * 0.43);
  const dy = 18 + rnd() * 62;
  const len = 16 + rnd() * 66;
  const lw = 1.6 + rnd() * 3.4;
  ctx.lineWidth = lw;
  ctx.beginPath();
  ctx.moveTo(dx, dy);
  ctx.bezierCurveTo(dx + (rnd()-0.5)*6, dy + len * 0.35, dx + (rnd()-0.5)*12, dy + len * 0.7, dx + (rnd()-0.5)*8, dy + len);
  ctx.stroke();
  ctx.beginPath();
  ctx.ellipse(dx + (rnd()-0.5)*5, dy + len + 4, lw * 1.5, lw * 2.2, 0, 0, Math.PI * 2);
  ctx.fill();
}
ctx.lineWidth = 4 + rnd() * 2.5;
ctx.strokeStyle = rgba(240, 232, 208, 0.32);
ctx.beginPath();
ctx.moveTo(-w * (0.22 + rnd()*0.05), h * (0.12 + rnd()*0.06));
ctx.lineTo(w * (0.18 + rnd()*0.08), h * (0.06 + rnd()*0.08));
ctx.stroke();
ctx.restore();
</script>
</body>
</html>]]):format(payload)
end

local function ensureGraffitiTexture(row, r, g, b)
    local id = tonumber(row and row.id)
    if not id then return nil end
    local text = tostring(row.text_label or '')
    local style = tostring(row.style_name or '')
    local gang = tostring(row.gang_name or '')
    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    local key = table.concat({
        tostring(id),
        text,
        style,
        gang,
        tostring(metadata.pathId or ''),
        tostring(metadata.tagKind or '')
    }, '|')
    local current = graffitiTextureCache[id]
    local now = GetGameTimer()
    if current and current.key == key then
        current.lastSeen = now
        return current
    end

    if current then
        releaseGraffitiTexture(id)
    end

    local seed = hashString(key)
    local markup = buildGraffitiMarkup({
        text = text ~= '' and text or gang,
        gang = gang,
        style = style,
        seed = seed,
        r = r,
        g = g,
        b = b,
        drift = ((seed % 1000) / 1000.0 - 0.5) * 0.08
    })

    local txdName = ('bm_graff_%d_%d'):format(id, now % 100000)
    local txnName = 'tag'
    local dui = CreateDui('data:text/html;charset=utf-8,' .. uriEncode(markup), 1024, 512)
    if not dui or dui == 0 then
        return nil
    end

    local duiHandle = GetDuiHandle(dui)
    if not duiHandle then
        DestroyDui(dui)
        return nil
    end

    local txd = CreateRuntimeTxd(txdName)
    if not txd then
        DestroyDui(dui)
        return nil
    end

    local texture = CreateRuntimeTextureFromDuiHandle(txd, txnName, duiHandle)
    if not texture then
        DestroyDui(dui)
        return nil
    end

    local entry = {
        key = key,
        dui = dui,
        txdName = txdName,
        txnName = txnName,
        createdAt = now,
        lastSeen = now,
        width = 0.17 + clamp((#text / 44.0), 0.0, 0.11),
        height = 0.085 + clamp((#text / 100.0), 0.0, 0.03),
        alpha = 210
    }

    graffitiTextureCache[id] = entry
    enforceGraffitiTextureCap()
    return entry
end

local function drawGraffitiTextureWorld(row, dist, r, g, b)
    local c = row.coords or {}
    local texture = ensureGraffitiTexture(row, r, g, b)
    if not texture then return end
    texture.lastSeen = GetGameTimer()
    local ease = clamp(1.0 - ((dist - 1.0) / 24.0), 0.30, 1.0)
    local alpha = clamp(math.floor((texture.alpha or 210) * ease), 95, 235)
    local sizeMul = clamp(1.0 - ((dist - 2.0) / 45.0), 0.72, 1.0)
    SetDrawOrigin(tonumber(c.x), tonumber(c.y), (tonumber(c.z) or 0.0) + 0.06, 0)
    DrawSprite(texture.txdName, texture.txnName, 0.0, 0.0, texture.width * sizeMul, texture.height * sizeMul, 0.0, 255, 255, 255, alpha)
    ClearDrawOrigin()
end

local function colorFromGang(gangName)
    local h = GetHashKey(tostring(gangName or ''))
    local r = math.abs((h * 31) % 155) + 80
    local g = math.abs((h * 17) % 155) + 80
    local b = math.abs((h * 7) % 155) + 80
    return r, g, b
end

local function upsertWorldGraffitiRow(row)
    if type(row) ~= 'table' then return end
    local id = tonumber(row.id)
    local coords = type(row.coords) == 'table' and row.coords or nil
    if not id or not coords or not coords.x or not coords.y or not coords.z then
        return
    end
    worldGraffiti[id] = row
end

local function rpc(action, payload)
    requestId = requestId + 1
    local id = requestId
    local p = promise.new()
    pending[id] = p

    TriggerServerEvent('qb-management:server:rpc', id, action, payload or {}, sessionToken)

    SetTimeout(12000, function()
        if pending[id] then
            pending[id] = nil
            p:resolve({ ok = false, error = 'timeout' })
        end
    end)

    return Citizen.Await(p)
end

RegisterNetEvent('qb-management:client:rpcResponse', function(id, ok, data, err)
    local p = pending[id]
    if not p then return end
    pending[id] = nil
    p:resolve({
        ok = ok == true,
        data = data,
        error = err
    })
end)

local function openMenu(menuType)
    menuType = menuType == 'gang' and 'gang' or 'boss'
    refreshPlayerData()
    if not canOpenMenu(menuType) then
        return
    end

    local res = rpc('open', { menuType = menuType })
    if not res.ok then
        return
    end

    sessionToken = res.data and res.data.token or nil
    if not sessionToken then
        return
    end

    uiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'open',
        payload = res.data
    })
end

local function registerRoleTargetZones(menuType, map, label)
    if type(map) ~= 'table' then return end

    if Config.TargetResource == 'ox_target' and GetResourceState('ox_target') == 'started' then
        for groupName, coordsList in pairs(map) do
            for i = 1, #coordsList do
                local coords = coordsList[i]
                exports.ox_target:addSphereZone({
                    coords = coords,
                    radius = 1.0,
                    options = {
                        {
                            name = ('%s_%s_%s'):format(menuType, groupName, i),
                            icon = 'fa-solid fa-briefcase',
                            label = label,
                            canInteract = function()
                                refreshPlayerData()
                                return canOpenMenu(menuType) and isAtOwnRole(menuType, groupName)
                            end,
                            onSelect = function()
                                openMenu(menuType)
                            end
                        }
                    }
                })
            end
        end
        return
    end

    if Config.TargetResource == 'qb-target' and GetResourceState('qb-target') == 'started' then
        for groupName, coordsList in pairs(map) do
            for i = 1, #coordsList do
                local coords = coordsList[i]
                local zoneName = ('%s_%s_%s'):format(menuType, groupName, i)
                exports['qb-target']:AddCircleZone(zoneName, coords, 0.5, {
                    name = zoneName,
                    debugPoly = false,
                    useZ = true
                }, {
                    options = {
                        {
                            type = 'client',
                            icon = 'fas fa-briefcase',
                            label = label,
                            action = function()
                                openMenu(menuType)
                            end,
                            canInteract = function()
                                refreshPlayerData()
                                return canOpenMenu(menuType) and isAtOwnRole(menuType, groupName)
                            end
                        }
                    },
                    distance = 2.0
                })
            end
        end
    end
end

local function registerTargetZones()
    if not Config.UseTarget then return end
    registerRoleTargetZones('boss', Config.BossMenus, 'Boss Menu')
    if Config.EnableGangMenu then
        registerRoleTargetZones('gang', Config.GangMenus, 'Gang Menu')
    end
end

RegisterNetEvent('qb-management:client:openMenu', function(data)
    local menuType = data and data.menuType or 'boss'
    openMenu(menuType)
end)

RegisterNetEvent('qb-bossmenu:client:OpenMenu', function()
    openMenu('boss')
end)

RegisterNetEvent('qb-gangmenu:client:OpenMenu', function()
    openMenu('gang')
end)

RegisterNetEvent('qb-management:client:syncGangRole', function(role)
    if type(role) ~= 'table' then return end
    customGangRole = {
        name = role.name,
        label = role.label or role.name,
        grade = tonumber(role.grade) or 0,
        isBoss = role.isBoss == true,
        onDuty = true
    }
end)

if Config.UseCommand ~= false then
    RegisterCommand(Config.OpenBossCommand or Config.OpenCommand or 'bossmenu', function()
        openMenu('boss')
    end, false)

    if Config.EnableGangMenu then
        RegisterCommand(Config.OpenGangCommand or 'gangmenu', function()
            openMenu('gang')
        end, false)
    end
end

CreateThread(function()
    refreshPlayerData()
    if usingCustomGangBackend() then
        TriggerServerEvent('qb-management:server:requestGangRoleSync')
    end
    registerTargetZones()

    if Config.UseTarget then
        return
    end

    local shown = false
    while true do
        local waitMs = tonumber(Config.Performance and Config.Performance.markerFarSleep or 1000) or 1000

        refreshPlayerData()
        local coords = GetEntityCoords(PlayerPedId())

        local function drawMenuMarkers(menuType, pointsByGroup, text)
            if type(pointsByGroup) ~= 'table' or not canOpenMenu(menuType) then
                return false
            end

            local near = false
            for groupName, points in pairs(pointsByGroup) do
                if isAtOwnRole(menuType, groupName) then
                    for i = 1, #points do
                        local point = points[i]
                        local dist = #(coords - point)
                        if dist < 6.0 then
                            near = true
                            waitMs = tonumber(Config.Performance and Config.Performance.markerNearSleep or 0) or 0
                            DrawMarker(2, point.x, point.y, point.z + 0.05, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.2, 0.2, 0.2, 255, 198, 70, 160, false, true, 2, nil, nil, false)
                            if dist <= (tonumber(Config.InteractionDistance) or 2.0) then
                                if not shown then
                                    shown = true
                                    BeginTextCommandDisplayHelp('STRING')
                                    AddTextComponentSubstringPlayerName(text)
                                    EndTextCommandDisplayHelp(0, false, false, -1)
                                end
                                if IsControlJustReleased(0, 38) then
                                    openMenu(menuType)
                                end
                            end
                        end
                    end
                end
            end

            return near
        end

        local anyNear = false
        anyNear = drawMenuMarkers('boss', Config.BossMenus, 'Press ~INPUT_CONTEXT~ to open Boss Menu') or anyNear
        if Config.EnableGangMenu then
            anyNear = drawMenuMarkers('gang', Config.GangMenus, 'Press ~INPUT_CONTEXT~ to open Gang Menu') or anyNear
        end

        if shown and not anyNear then
            shown = false
        end

        Wait(waitMs)
    end
end)

RegisterNetEvent('qb-management:client:worldGraffitiSnapshot', function(rows)
    for id in pairs(worldGraffiti) do
        releaseGraffitiTexture(id)
    end
    worldGraffiti = {}
    if type(rows) ~= 'table' then return end
    for i = 1, #rows do
        upsertWorldGraffitiRow(rows[i])
    end
    lastGraffitiSyncAt = GetGameTimer()
end)

RegisterNetEvent('qb-management:client:worldGraffitiUpsert', function(row)
    upsertWorldGraffitiRow(row)
end)

RegisterNetEvent('qb-management:client:worldGraffitiRemove', function(data)
    local id = tonumber(type(data) == 'table' and data.id or data)
    if not id then return end
    releaseGraffitiTexture(id)
    worldGraffiti[id] = nil
end)

CreateThread(function()
    if Config.Modules and Config.Modules.GangGraffiti ~= true then
        return
    end
    Wait(1500)
    TriggerServerEvent('qb-management:server:requestWorldGraffiti')
    while true do
        local cfg = gangSystemsCfg()
        local renderDist = tonumber(cfg.graffitiRenderDistance or 55.0) or 55.0
        local drawDist = tonumber(cfg.graffitiDrawDistance or 22.0) or 22.0
        graffitiTextureCap = math.max(12, tonumber(cfg.graffitiMaxActiveRenders or 64) or 64)
        local near = false
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        for id, row in pairs(worldGraffiti) do
            local c = row.coords or {}
            if c.x and c.y and c.z then
                local dx = pos.x - (tonumber(c.x) or 0.0)
                local dy = pos.y - (tonumber(c.y) or 0.0)
                local dz = pos.z - (tonumber(c.z) or 0.0)
                local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
                if dist <= renderDist then
                    near = true
                    if dist <= drawDist then
                        local gang = tostring(row.gang_name or '')
                        local r, g, b = colorFromGang(gang)
                        drawGraffitiTextureWorld(row, dist, r, g, b)
                    else
                        local cached = graffitiTextureCache[id]
                        if cached then
                            cached.lastSeen = GetGameTimer()
                        end
                    end
                end
            end
        end

        local nowTick = GetGameTimer()
        for id, entry in pairs(graffitiTextureCache) do
            if nowTick - (tonumber(entry.lastSeen or 0) or 0) > 180000 then
                releaseGraffitiTexture(id)
            end
        end

        local now = GetGameTimer()
        if now - (lastGraffitiSyncAt or 0) > 60000 then
            TriggerServerEvent('qb-management:server:requestWorldGraffiti')
            lastGraffitiSyncAt = now
        end

        if near then
            Wait(0)
        else
            Wait(900)
        end
    end
end)

RegisterNUICallback('close', function(_, cb)
    if hasActiveProfileCaptures() then
        cancelAllProfileCaptures('Capture cancelled')
    end
    rpc('close', {})
    sessionToken = nil
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    local res = rpc('refresh', {})
    cb(res)
end)

RegisterNUICallback('hire', function(data, cb)
    local res = rpc('hire', { source = data and data.source })
    cb(res)
end)

RegisterNUICallback('setGrade', function(data, cb)
    local res = rpc('set_grade', {
        identifier = data and data.identifier,
        grade = data and data.grade
    })
    cb(res)
end)

RegisterNUICallback('fire', function(data, cb)
    local res = rpc('fire', {
        identifier = data and data.identifier,
        reason = data and data.reason
    })
    cb(res)
end)

RegisterNUICallback('deposit', function(data, cb)
    local res = rpc('deposit', { amount = data and data.amount })
    cb(res)
end)

RegisterNUICallback('withdraw', function(data, cb)
    local res = rpc('withdraw', {
        amount = data and data.amount,
        reason = data and data.reason
    })
    cb(res)
end)

RegisterNUICallback('getRanks', function(_, cb)
    cb(rpc('get_ranks', {}))
end)

RegisterNUICallback('createRank', function(data, cb)
    cb(rpc('create_rank', data or {}))
end)

RegisterNUICallback('updateRank', function(data, cb)
    cb(rpc('update_rank', data or {}))
end)

RegisterNUICallback('deleteRank', function(data, cb)
    cb(rpc('delete_rank', data or {}))
end)

RegisterNUICallback('reassignRank', function(data, cb)
    cb(rpc('reassign_rank', data or {}))
end)

RegisterNUICallback('getRankPermissions', function(data, cb)
    cb(rpc('get_rank_permissions', data or {}))
end)

RegisterNUICallback('setRankPermission', function(data, cb)
    cb(rpc('set_rank_permission', data or {}))
end)

RegisterNUICallback('moduleAction', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end
    local action = tostring(data.action or '')
    if action == '' then
        cb({ ok = false, error = 'invalid_action' })
        return
    end
    cb(rpc(action, data.payload or {}))
end)

RegisterNUICallback('territoryTagPoint', function(data, cb)
    local ped = PlayerPedId()
    if not ped or ped == 0 then
        cb({ ok = false, error = 'ped_unavailable' })
        return
    end
    local pos = GetEntityCoords(ped)
    local pathId = tostring(data and data.pathId or '')
    local style = tostring(data and data.style or 'territory')
    local text = tostring(data and data.text or '')
    local ttlMinutes = tonumber(data and data.ttlMinutes)
    local incomingMetadata = type(data and data.metadata) == 'table' and data.metadata or {}
    local metadata = {
        territoryPoint = true,
        pathId = pathId
    }
    for k, v in pairs(incomingMetadata) do
        metadata[k] = v
    end
    local payload = {
        coords = { x = pos.x, y = pos.y, z = pos.z },
        style = style,
        text = text,
        pathId = pathId,
        territoryPoint = true,
        ttlMinutes = ttlMinutes,
        metadata = metadata
    }
    cb(rpc('graffiti_place', payload))
end)

RegisterNUICallback('territoryCleanNearest', function(_, cb)
    local ped = PlayerPedId()
    if not ped or ped == 0 then
        cb({ ok = false, error = 'ped_unavailable' })
        return
    end
    local pos = GetEntityCoords(ped)
    local nearestId, nearestDist = nil, 99999.0
    for id, row in pairs(worldGraffiti) do
        local c = row.coords or {}
        if c.x and c.y and c.z then
            local dx, dy, dz = pos.x - (tonumber(c.x) or 0.0), pos.y - (tonumber(c.y) or 0.0), pos.z - (tonumber(c.z) or 0.0)
            local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
            if dist < nearestDist then
                nearestDist = dist
                nearestId = tonumber(id)
            end
        end
    end
    if not nearestId or nearestDist > ((tonumber(Config.Security and Config.Security.maxMarkerCreateDistance or 15.0) or 15.0) * 2.0) then
        cb({ ok = false, error = 'no_nearby_graffiti' })
        return
    end
    cb(rpc('graffiti_delete', { id = nearestId, allowCrossGangClean = true }))
end)

local function registerForward(name, action)
    RegisterNUICallback(name, function(data, cb)
        cb(rpc(action, data or {}))
    end)
end

registerForward('getMemberProfile', 'get_member_profile')
registerForward('updateMemberProfile', 'update_member_profile')
registerForward('updateMemberStrikes', 'update_member_strikes')
registerForward('searchMembers', 'search_members')
registerForward('setSalary', 'set_salary')
registerForward('runPayroll', 'run_payroll')
registerForward('inventoryList', 'inventory_list')
registerForward('inventoryDeposit', 'inventory_deposit')
registerForward('inventoryWithdraw', 'inventory_withdraw')
registerForward('uniformsList', 'uniforms_list')
registerForward('uniformsSave', 'uniforms_save')
registerForward('uniformsDelete', 'uniforms_delete')
registerForward('uniformsApply', 'uniforms_apply')
registerForward('uniformsPreview', 'uniforms_preview')
registerForward('uniformsRestore', 'uniforms_restore')
registerForward('applicationsSubmit', 'applications_submit')
registerForward('applicationsList', 'applications_list')
registerForward('applicationsDecide', 'applications_decide')
registerForward('announcementsCreate', 'announcements_create')
registerForward('announcementsList', 'announcements_list')
registerForward('orgMarkersList', 'org_markers_list')
registerForward('orgMarkersUpsert', 'org_markers_upsert')
registerForward('orgMarkersDelete', 'org_markers_delete')
registerForward('orgGaragesList', 'org_garages_list')
registerForward('orgGaragesUpsert', 'org_garages_upsert')
registerForward('orgGaragesDelete', 'org_garages_delete')
registerForward('adminListOrgs', 'admin_list_orgs')
registerForward('adminAddFunds', 'admin_add_funds')
registerForward('adminRemoveFunds', 'admin_remove_funds')
registerForward('adminActions', 'admin_actions')
registerForward('adminDisableOrg', 'admin_disable_org')
registerForward('adminEnableOrg', 'admin_enable_org')
registerForward('adminForceAddMember', 'admin_force_add_member')
registerForward('adminForceRemoveMember', 'admin_force_remove_member')
registerForward('adminForceSetGrade', 'admin_force_set_grade')
registerForward('adminChangeLeader', 'admin_change_leader')
registerForward('adminDeleteInternalGang', 'admin_delete_internal_gang')
registerForward('adminSuspicious', 'admin_suspicious')
registerForward('adminExportLogs', 'admin_export_logs')
registerForward('adminWebhooksGet', 'admin_webhooks_get')
registerForward('adminWebhooksSave', 'admin_webhooks_save')
registerForward('taxesSet', 'taxes_set')
registerForward('invoiceCreate', 'invoice_create')
registerForward('invoiceStatus', 'invoice_status')
registerForward('analytics', 'analytics')
registerForward('auditLogs', 'audit_logs')
registerForward('webhookSettingsGet', 'webhook_settings_get')
registerForward('webhookSettingsSave', 'webhook_settings_save')
registerForward('gangNotoriety', 'gang_notoriety')
registerForward('gangMarkerUpsert', 'gang_marker_upsert')
registerForward('gangMarkerDelete', 'gang_marker_delete')
registerForward('territoryList', 'territory_list')
registerForward('territoryBegin', 'territory_begin')
registerForward('territoryComplete', 'territory_complete')
registerForward('contractsList', 'contracts_list')
registerForward('contractsCreate', 'contracts_create')
registerForward('contractsAccept', 'contracts_accept')
registerForward('contractsComplete', 'contracts_complete')
registerForward('racketsList', 'rackets_list')
registerForward('racketsUpsert', 'rackets_upsert')
registerForward('racketsUpgrade', 'rackets_upgrade')
registerForward('racketsClaim', 'rackets_claim')
registerForward('graffitiList', 'graffiti_list')
registerForward('graffitiPlace', 'graffiti_place')
registerForward('graffitiDelete', 'graffiti_delete')

RegisterNUICallback('escape', function(_, cb)
    if hasActiveProfileCaptures() then
        cancelAllProfileCaptures('Capture cancelled')
    end
    rpc('close', {})
    sessionToken = nil
    closeUi()
    cb({ ok = true })
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', refreshPlayerData)
RegisterNetEvent('QBCore:Client:OnGangUpdate', refreshPlayerData)
RegisterNetEvent('esx:setJob', refreshPlayerData)
RegisterNetEvent('ox:setGroup', refreshPlayerData)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshPlayerData()
    if usingCustomGangBackend() then
        TriggerServerEvent('qb-management:server:requestGangRoleSync')
    end
end)

RegisterNetEvent('esx:playerLoaded', function()
    refreshPlayerData()
    if usingCustomGangBackend() then
        TriggerServerEvent('qb-management:server:requestGangRoleSync')
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    customGangRole = nil
end)

local savedUniformState = nil

local function snapshotPed()
    local ped = PlayerPedId()
    local data = { components = {}, props = {} }
    for comp = 0, 11 do
        data.components[comp] = {
            drawable = GetPedDrawableVariation(ped, comp),
            texture = GetPedTextureVariation(ped, comp),
            palette = GetPedPaletteVariation(ped, comp)
        }
    end
    for prop = 0, 7 do
        data.props[prop] = {
            drawable = GetPedPropIndex(ped, prop),
            texture = GetPedPropTextureIndex(ped, prop)
        }
    end
    return data
end

local function applyRawAppearance(raw)
    if type(raw) ~= 'table' then return end
    local ped = PlayerPedId()
    local components = raw.components or raw.component or raw.clothes or {}
    local props = raw.props or raw.prop or {}

    for compKey, compData in pairs(components) do
        local comp = tonumber(compKey)
        if comp and type(compData) == 'table' then
            SetPedComponentVariation(
                ped,
                comp,
                tonumber(compData.drawable or compData[1] or 0) or 0,
                tonumber(compData.texture or compData[2] or 0) or 0,
                tonumber(compData.palette or compData[3] or 0) or 0
            )
        end
    end
    for propKey, propData in pairs(props) do
        local prop = tonumber(propKey)
        if prop and type(propData) == 'table' then
            local drawable = tonumber(propData.drawable or propData[1] or -1) or -1
            if drawable < 0 then
                ClearPedProp(ped, prop)
            else
                SetPedPropIndex(
                    ped,
                    prop,
                    drawable,
                    tonumber(propData.texture or propData[2] or 0) or 0,
                    true
                )
            end
        end
    end
end

local function callExportSafe(resource, fn, ...)
    local args = { ... }
    local ok, result = pcall(function()
        return exports[resource][fn](table.unpack(args))
    end)
    if not ok then return nil end
    return result
end

local activeNativeCamera = nil
local cctvFxActive = false
local profileCaptureCams = {}
local profileCaptureStates = {}

local function hasActiveProfileCaptures()
    return next(profileCaptureStates) ~= nil
end

local function finalizeProfileCapture(requestId, notifyServer, errorReason)
    requestId = tostring(requestId or '')
    if requestId == '' then return false end

    local state = profileCaptureStates[requestId]
    if not state and not profileCaptureCams[requestId] then
        SendNUIMessage({
            action = 'captureVisibility',
            payload = { show = true }
        })
        return false
    end

    profileCaptureStates[requestId] = nil

    local cam = profileCaptureCams[requestId]
    if cam then
        DestroyCam(cam, false)
        profileCaptureCams[requestId] = nil
    end

    if not activeNativeCamera and next(profileCaptureCams) == nil then
        RenderScriptCams(false, true, 200, true, true)
        ClearFocus()
    end

    SendNUIMessage({
        action = 'captureVisibility',
        payload = { show = true }
    })

    if notifyServer and state and state.reported ~= true then
        state.reported = true
        TriggerServerEvent('qb-management:server:profileCaptureData', requestId, nil, nil, errorReason or 'Capture cancelled')
    end

    return true
end

local function cancelAllProfileCaptures(errorReason)
    local pending = {}
    for requestId in pairs(profileCaptureStates) do
        pending[#pending + 1] = requestId
    end
    for i = 1, #pending do
        finalizeProfileCapture(pending[i], true, errorReason or 'Capture cancelled')
    end
end

local function closeNativeCamera()
    if activeNativeCamera then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(activeNativeCamera, false)
        ClearFocus()
        activeNativeCamera = nil
    end
end

local function setCctvFx(active, label, provider)
    if active then
        if not cctvFxActive then
            cctvFxActive = true
            SetTimecycleModifier('scanline_cam_cheap')
            SetTimecycleModifierStrength(0.9)
        end
        SendNUIMessage({
            action = 'cameraOverlay',
            payload = {
                show = true,
                label = label or 'CCTV FEED',
                provider = provider or 'SYSTEM'
            }
        })
    else
        if cctvFxActive then
            cctvFxActive = false
            ClearTimecycleModifier()
        end
        SendNUIMessage({
            action = 'cameraOverlay',
            payload = { show = false }
        })
    end
end

local function openNativeCamera(feed)
    if type(feed) ~= 'table' then return false end
    local coords = type(feed.coords) == 'table' and feed.coords or nil
    if not coords then return false end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return false end
    local w = tonumber(coords.w) or 0.0
    closeNativeCamera()
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, x, y, z)
    SetCamRot(cam, -10.0, 0.0, w, 2)
    SetCamFov(cam, tonumber(coords.fov) or 55.0)
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    RenderScriptCams(true, true, 350, true, true)
    activeNativeCamera = cam
    return true
end

CreateThread(function()
    while true do
        if hasActiveProfileCaptures() then
            if IsControlJustReleased(0, 177) or IsControlJustReleased(0, 200) then -- BACKSPACE / ESC
                cancelAllProfileCaptures('Capture cancelled')
            end
            Wait(0)
        elseif activeNativeCamera then
            if IsControlJustReleased(0, 177) or IsControlJustReleased(0, 200) then -- BACKSPACE / ESC
                closeNativeCamera()
                setCctvFx(false)
            end
            Wait(0)
        elseif cctvFxActive then
            if IsControlJustReleased(0, 177) or IsControlJustReleased(0, 200) then
                setCctvFx(false)
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

local function resourceReady(name)
    if not name or name == '' then return true end
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function triggerEventSafe(resourceName, eventName, ...)
    if not eventName or eventName == '' then return false end
    if resourceName and resourceName ~= '' and not resourceReady(resourceName) then
        return false
    end
    TriggerEvent(eventName, ...)
    return true
end

local function openCameraWithProvider(provider, feed)
    provider = tostring(provider or 'native'):lower()
    if provider == 'none' then
        return false
    end

    local feedId = feed and feed.id or nil

    if provider == 'native' then
        return openNativeCamera(feed)
    end

    if provider == 'qb-policejob' then
        return triggerEventSafe('qb-policejob', 'police:client:ActiveCamera', feedId)
    end

    if provider == 'esx_policejob' then
        return triggerEventSafe('esx_policejob', 'esx_policejob:openCCTV', feedId)
    end

    if provider == 'rcore_cctv' then
        return callExportSafe('rcore_cctv', 'OpenCamera', feedId) ~= nil
            or callExportSafe('rcore_cctv', 'openCamera', feedId) ~= nil
            or triggerEventSafe('rcore_cctv', 'rcore_cctv:openCamera', feedId)
    end

    if provider == 'loaf_cctv' then
        return callExportSafe('loaf_cctv', 'Open', feedId) ~= nil
            or callExportSafe('loaf_cctv', 'open', feedId) ~= nil
            or triggerEventSafe('loaf_cctv', 'loaf_cctv:open', feedId)
    end

    if provider == 'okokcctv' then
        return callExportSafe('okokCCTV', 'OpenCCTV', feedId) ~= nil
            or callExportSafe('okokcctv', 'OpenCCTV', feedId) ~= nil
            or triggerEventSafe('okokCCTV', 'okokCCTV:open', feedId)
            or triggerEventSafe('okokcctv', 'okokCCTV:open', feedId)
    end

    if provider == 'tk_cctv' then
        return callExportSafe('tk_cctv', 'openCamera', feedId) ~= nil
            or triggerEventSafe('tk_cctv', 'tk_cctv:open', feedId)
    end

    local cfg = Config.Cameras and Config.Cameras.providers and Config.Cameras.providers[provider]
    if type(cfg) == 'table' then
        local resource = tostring(cfg.resource or '')
        local openEvent = tostring(cfg.openEvent or '')
        local openArgsMode = tostring(cfg.openArgsMode or 'feed')
        if cfg.useExport == true then
            local exportName = tostring(cfg.exportName or '')
            if exportName ~= '' then
                if openArgsMode == 'id' then
                    return callExportSafe(resource, exportName, feedId) ~= nil
                elseif openArgsMode == 'label' then
                    return callExportSafe(resource, exportName, feed and feed.label or '') ~= nil
                elseif openArgsMode == 'raw' then
                    return callExportSafe(resource, exportName, cfg) ~= nil
                end
                return callExportSafe(resource, exportName, feed) ~= nil
            end
        end
        if openEvent ~= '' then
            if openArgsMode == 'id' then
                return triggerEventSafe(resource, openEvent, feedId)
            elseif openArgsMode == 'label' then
                return triggerEventSafe(resource, openEvent, feed and feed.label or '')
            elseif openArgsMode == 'raw' then
                return triggerEventSafe(resource, openEvent, cfg)
            end
            return triggerEventSafe(resource, openEvent, feed)
        end
    end

    if resourceReady(provider) then
        local exportCandidates = { 'OpenCamera', 'openCamera', 'OpenCCTV', 'openCCTV', 'Open', 'open' }
        for i = 1, #exportCandidates do
            if callExportSafe(provider, exportCandidates[i], feedId) ~= nil
                or callExportSafe(provider, exportCandidates[i], feed) ~= nil then
                return true
            end
        end
    end

    return openNativeCamera(feed)
end

RegisterNetEvent('qb-management:client:uniformAction', function(data)
    if type(data) ~= 'table' then return end
    local op = tostring(data.op or '')
    if op == 'restore' then
        if savedUniformState then
            applyRawAppearance(savedUniformState)
            savedUniformState = nil
        end
        return
    end

    local uniform = data.uniform or {}
    local integration = tostring(data.integration or 'none')
    local ped = PlayerPedId()
    local isFemale = IsPedModel(ped, `mp_f_freemode_01`)
    local payload = isFemale and (uniform.female or {}) or (uniform.male or {})
    if type(payload) ~= 'table' then payload = {} end

    if not savedUniformState then
        savedUniformState = snapshotPed()
    end

    local applied = false
    if integration == 'illenium-appearance' then
        applied = callExportSafe('illenium-appearance', 'setPedAppearance', ped, payload) ~= nil
            or callExportSafe('illenium-appearance', 'setPlayerAppearance', payload) ~= nil
    elseif integration == 'fivem-appearance' then
        applied = callExportSafe('fivem-appearance', 'setPedAppearance', ped, payload) ~= nil
            or callExportSafe('fivem-appearance', 'setPlayerAppearance', payload) ~= nil
    elseif integration == 'qb-clothing' then
        TriggerEvent('qb-clothing:client:loadOutfit', payload)
        applied = true
    elseif integration == 'skinchanger' then
        TriggerEvent('skinchanger:loadSkin', payload)
        applied = true
    end

    if not applied then
        applyRawAppearance(payload)
    end
end)

RegisterNetEvent('qb-management:client:openCamera', function(data)
    if type(data) ~= 'table' then return end
    if uiOpen and data.closeMenu == true then
        rpc('close', {})
        sessionToken = nil
        closeUi()
    end
    local label = data.feed and data.feed.label or 'CCTV FEED'
    setCctvFx(true, label, data.provider)
    local ok = openCameraWithProvider(data.provider, data.feed or {})
    if not ok then
        openNativeCamera(data.feed or {})
    end
end)

RegisterNetEvent('qb-management:client:openOrgStash', function(data)
    if type(data) ~= 'table' then return end
    local backend = tostring(data.backend or 'none')
    local stashId = tostring(data.stashId or '')
    if stashId == '' then return end
    local meta = {
        label = tostring(data.label or stashId),
        slots = tonumber(data.slots) or 250,
        maxweight = tonumber(data.maxWeight) or 1000000,
        maxWeight = tonumber(data.maxWeight) or 1000000
    }

    if backend == 'ox_inventory' then
        pcall(function()
            exports.ox_inventory:openInventory('stash', stashId)
        end)
        return
    end

    if backend == 'qb-inventory' then
        pcall(function()
            exports['qb-inventory']:OpenInventory('stash', stashId, meta)
        end)
        return
    end

    if backend == 'ps-inventory' then
        pcall(function()
            exports['ps-inventory']:OpenInventory('stash', stashId, meta)
        end)
        return
    end

    if backend == 'lj-inventory' then
        pcall(function()
            exports['lj-inventory']:OpenInventory('stash', stashId, meta)
        end)
        return
    end

    if backend == 'qs-inventory' then
        local ok = false
        ok = pcall(function()
            exports['qs-inventory']:OpenInventory('stash', stashId)
        end)
        if not ok then
            pcall(function()
                TriggerServerEvent('inventory:server:OpenInventory', 'stash', stashId, meta)
                TriggerEvent('inventory:client:SetCurrentStash', stashId)
            end)
        end
        return
    end
end)

RegisterNetEvent('qb-management:client:prepareProfileCapture', function(data)
    local requestId = tostring(data and data.requestId or '')
    if requestId == '' then return end

    local function resourceReady(name)
        if not name or name == '' then return false end
        local state = GetResourceState(name)
        return state == 'started' or state == 'starting'
    end

    local function captureByExport(resource, exportName, options, callbackFirst)
        if not resourceReady(resource) then
            return false, ('provider %s not started'):format(resource)
        end
        local p = promise.new()
        local done = false
        local function resolve(data)
            if done then return end
            done = true
            p:resolve(data)
        end

        local function cb(dataUri)
            resolve(dataUri)
        end

        local ok = false
        if callbackFirst then
            ok = pcall(function()
                exports[resource][exportName](cb, options or {})
            end)
            if not ok then
                ok = pcall(function()
                    exports[resource][exportName](cb)
                end)
            end
        else
            ok = pcall(function()
                exports[resource][exportName](options or {}, cb)
            end)
            if not ok then
                ok = pcall(function()
                    exports[resource][exportName](cb)
                end)
            end
        end

        if not ok then
            return false, ('provider export failed: %s:%s'):format(resource, exportName)
        end

        SetTimeout(9000, function()
            resolve(false)
        end)

        local result = Citizen.Await(p)
        if type(result) == 'string' and result:find('^data:image/') then
            return true, result
        end
        return false, ('provider returned invalid data: %s'):format(resource)
    end

    local function captureWithProviders(providers, options)
        providers = type(providers) == 'table' and providers or {}
        local lastErr = 'No provider accepted the request'
        for i = 1, #providers do
            local row = providers[i]
            local name = tostring((type(row) == 'table' and row.name) or row or '')
            local resource = tostring((type(row) == 'table' and row.resource) or name)
            local mode = tostring((type(row) == 'table' and row.mode) or 'screenshot_basic_client')
            local exportName = tostring((type(row) == 'table' and row.exportName) or '')
            local callbackFirst = type(row) == 'table' and row.callbackFirst == true or false
            if exportName == '' then
                exportName = 'requestScreenshot'
            end

            local ok, dataOrErr
            if mode == 'client_export' or mode == 'screenshot_basic_client' then
                ok, dataOrErr = captureByExport(resource, exportName, options, callbackFirst)
            else
                ok, dataOrErr = false, ('unsupported provider mode: %s'):format(mode)
            end
            if ok then
                return true, dataOrErr, name ~= '' and name or resource
            end
            lastErr = tostring(dataOrErr or lastErr)
        end
        return false, nil, lastErr
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 then
        TriggerServerEvent('qb-management:server:profileCaptureData', requestId, nil, nil, 'Player ped unavailable')
        return
    end

    SendNUIMessage({
        action = 'captureVisibility',
        payload = { show = false }
    })

    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local fw = GetEntityForwardVector(ped)
    local camX = head.x + (fw.x * 0.62)
    local camY = head.y + (fw.y * 0.62)
    local camZ = head.z + 0.10

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not cam or cam == 0 then
        SendNUIMessage({
            action = 'captureVisibility',
            payload = { show = true }
        })
        TriggerServerEvent('qb-management:server:profileCaptureData', requestId, nil, nil, 'Failed to create capture camera')
        return
    end

    SetCamCoord(cam, camX, camY, camZ)
    PointCamAtCoord(cam, head.x, head.y, head.z + 0.03)
    SetCamFov(cam, 30.0)
    SetFocusPosAndVel(head.x, head.y, head.z, 0.0, 0.0, 0.0)
    RenderScriptCams(true, true, 250, true, true)
    profileCaptureCams[requestId] = cam
    profileCaptureStates[requestId] = {
        reported = false
    }

    SetTimeout(12000, function()
        if profileCaptureStates[requestId] then
            finalizeProfileCapture(requestId, true, 'Capture timed out')
        end
    end)

    local options = type(data.options) == 'table' and data.options or {}
    local ok, payload, providerOrErr = false, nil, 'Capture failed'
    local captureOk, captureErr = pcall(function()
        Wait(300)
        ok, payload, providerOrErr = captureWithProviders(data.providers, options)
    end)

    local state = profileCaptureStates[requestId]
    if not state then
        return
    end

    state.reported = true
    finalizeProfileCapture(requestId, false)

    if not captureOk then
        TriggerServerEvent('qb-management:server:profileCaptureData', requestId, nil, nil, ('Capture runtime error: %s'):format(tostring(captureErr)))
        return
    end

    if ok then
        TriggerServerEvent('qb-management:server:profileCaptureData', requestId, payload, providerOrErr, nil)
    else
        TriggerServerEvent('qb-management:server:profileCaptureData', requestId, nil, nil, providerOrErr)
    end
end)

RegisterNetEvent('qb-management:client:finishProfileCapture', function(requestId)
    finalizeProfileCapture(requestId, false)
end)

RegisterNetEvent('qb-management:client:profileCaptureResult', function(data)
    SendNUIMessage({
        action = 'profileCaptureResult',
        payload = data or {}
    })
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    cancelAllProfileCaptures('Resource stopped')
    for key in pairs(profileCaptureCams) do
        finalizeProfileCapture(key, false)
    end
    RenderScriptCams(false, true, 150, true, true)
    ClearFocus()
    setCctvFx(false)
    closeNativeCamera()
    closeUi()
end)
