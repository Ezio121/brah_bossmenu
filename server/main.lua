local resource = GetCurrentResourceName()

if resource:lower():sub(-5) == '-init' then
    print(('[%s] init bootstrap detected; runtime server initialization skipped'):format(resource))
    return
end

BrahBossmenuRuntimeReady = false
BrahBossmenuResourceStopping = false

local ResourceStopping = false
local RuntimeInitializationStarted = false

local function waitForRuntimeReady()
    while not BrahBossmenuRuntimeReady and not ResourceStopping do
        Wait(250)
    end
    return BrahBossmenuRuntimeReady == true and not ResourceStopping
end

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resource then return end
    ResourceStopping = true
    BrahBossmenuResourceStopping = true
    BrahBossmenuRuntimeReady = false
end)

local frameworkName = Framework.GetName()

local QBCore
local ESX
if frameworkName == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif frameworkName == 'qbox' then
    if GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
    end
elseif frameworkName == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
end

local Sessions = {}
local RateBuckets = {}
local EmployeeCache = {}
local GradeCache = {}
local CustomRankCache = {}
local PermissionCache = {}
local CustomGangCache = {}
local OrgStateCache = {}
local HookSubscriptions = {}
local NextHookId = 0
local SeenRequests = {}
local ProfileImageRequests = {}
local getInbuiltGangDefinition
local getInbuiltGangLabelAndMax

local function nowMs()
    return GetGameTimer()
end

local function unix()
    return os.time()
end

local function cleanText(text, maxLen)
    local value = tostring(text or '')
    value = value:gsub('[\r\n\t]', ' ')
    value = value:gsub('%s%s+', ' ')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #value > maxLen then
        value = value:sub(1, maxLen)
    end
    return value
end

local function safeNumber(value, min, max)
    local n = tonumber(value)
    if not n then return nil end
    n = math.floor(n)
    if min and n < min then return nil end
    if max and n > max then return nil end
    return n
end

local function decodeJson(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' then return nil end
    local ok, value = pcall(json.decode, raw)
    if ok then return value end
    return nil
end

-- Declared early because startup migration/sync paths use these before later blocks.
getInbuiltGangDefinition = function(gangName)
    local defs = Config.InbuiltGangDefinitions
    if type(defs) == 'table' and type(defs[gangName]) == 'table' then
        return defs[gangName]
    end
    return nil
end

getInbuiltGangLabelAndMax = function(gangName)
    local def = getInbuiltGangDefinition(gangName)
    local label = def and def.label or gangName
    local maxGrade = tonumber(def and def.maxGrade) or nil
    if not maxGrade then
        local ranks = def and def.ranks or nil
        if type(ranks) == 'table' then
            local best = -1
            for k in pairs(ranks) do
                local n = tonumber(k)
                if n and n > best then
                    best = n
                end
            end
            if best >= 0 then
                maxGrade = best
            end
        end
    end
    if not maxGrade then
        maxGrade = 4
    end
    return label, maxGrade
end

local function useInbuiltGangFrames()
    local value = Config.useinbuiltgangframes
    if value == nil then
        value = Config.UseInbuiltGangFrames
    end
    if value == nil then
        return true
    end
    return value == true
end

local function supportsCustomGangBackend()
    return frameworkName == 'qb' or frameworkName == 'esx'
end

local function usingCustomGangBackend()
    return Config.EnableGangMenu == true and (not useInbuiltGangFrames()) and supportsCustomGangBackend()
end

local function notify(src, message, kind)
    kind = kind or 'inform'
    if frameworkName == 'qb' or frameworkName == 'qbox' then
        TriggerClientEvent('QBCore:Notify', src, message, kind == 'inform' and 'primary' or kind)
        return
    end
    if frameworkName == 'esx' then
        TriggerClientEvent('esx:showNotification', src, message)
        return
    end
    if frameworkName == 'ox' then
        TriggerClientEvent('ox_lib:notify', src, { type = kind, description = message })
        return
    end
    TriggerClientEvent('chat:addMessage', src, { args = { '[management]', message } })
end

local function rateGroup(action)
    if action == 'deposit' or action == 'withdraw' then
        return 'money'
    end
    if action == 'hire' or action == 'set_grade' or action == 'fire' then
        return 'manage'
    end
    return 'nui'
end

local function rateCheck(src, action)
    if not (Config.Security and Config.Security.enableActionCooldowns == true) then
        return true
    end
    local cfg = Config.Security and Config.Security.rateLimits and Config.Security.rateLimits[rateGroup(action)] or { count = 24, windowMs = 5000 }
    local key = ('%s:%s'):format(src, rateGroup(action))
    local bucket = RateBuckets[key]
    local now = nowMs()

    if not bucket or now > bucket.resetAt then
        RateBuckets[key] = {
            count = 1,
            resetAt = now + (cfg.windowMs or 5000)
        }
        return true
    end

    if bucket.count >= (cfg.count or 24) then
        return false
    end

    bucket.count = bucket.count + 1
    return true
end

local function emitHook(name, payload)
    TriggerEvent('qb-management:server:hook', name, payload)
    TriggerEvent(('qb-management:server:hook:%s'):format(name), payload)
    local subscriptions = HookSubscriptions[name]
    if subscriptions then
        for _, sub in pairs(subscriptions) do
            if sub and sub.eventName then
                TriggerEvent(sub.eventName, payload)
            end
        end
    end
    if AuditModule and AuditModule.QueueWebhook then
        local actionName = tostring(name or '')
        local row = {
            org_type = payload and payload.menuType or payload and payload.orgType or 'org',
            org_name = payload and payload.role or payload and payload.orgName or 'unknown',
            action = actionName,
            actor_identifier = payload and payload.actor or payload and payload.source,
            target_identifier = payload and payload.target,
            metadata_json = payload or {}
        }
        local category = 'employee'
        local text = actionName:lower()
        if text:find('contract') then category = 'contracts'
        elseif text:find('gang') or text:find('notoriety') then category = 'gang'
        elseif text:find('inventory') or text:find('stash') then category = 'inventory'
        elseif text:find('withdraw') or text:find('deposit') or text:find('finance') or text:find('payroll') then category = 'finance'
        elseif text:find('application') then category = 'applications'
        elseif text:find('territor') then category = 'territories'
        elseif text:find('admin') then category = 'admin'
        elseif text:find('suspicious') or text:find('security') then category = 'security'
        end
        if category ~= 'security' or (Config.Security and Config.Security.webhookOnSuspiciousAction == true) then
            AuditModule.QueueWebhook(category, row)
        end
    end
end

exports('RegisterHook', function(name, eventName)
    name = cleanText(name, 80)
    eventName = cleanText(eventName, 120)
    if name == '' or eventName == '' then
        return nil
    end
    NextHookId = NextHookId + 1
    HookSubscriptions[name] = HookSubscriptions[name] or {}
    HookSubscriptions[name][NextHookId] = {
        id = NextHookId,
        eventName = eventName
    }
    return NextHookId
end)

exports('UnregisterHook', function(name, hookId)
    if not HookSubscriptions[name] then return false end
    if HookSubscriptions[name][hookId] then
        HookSubscriptions[name][hookId] = nil
        return true
    end
    return false
end)

local function getQbLikeName(player)
    local pd = player and player.PlayerData
    local ch = pd and pd.charinfo
    if ch then
        return (ch.firstname or 'Unknown') .. ' ' .. (ch.lastname or '')
    end
    return pd and pd.name or 'Unknown'
end

local function getQbLikeRole(player, key)
    local data = player and player.PlayerData and player.PlayerData[key] or {}
    local level = tonumber((data.grade and (data.grade.level or data.grade)) or 0) or 0
    return {
        name = data.name,
        label = data.label or data.name,
        grade = level,
        isBoss = data.isboss == true,
        onDuty = data.onduty == true
    }
end

local function getOxPlayer(src)
    local ok, player = pcall(function()
        return Ox.GetPlayer(src)
    end)
    if ok then return player end
    return nil
end

local function getOxRole(player)
    if not player then return nil end
    local groupName, grade = player.getGroupByType('job')
    if not groupName then return nil end
    grade = tonumber(grade or 0) or 0
    return {
        name = groupName,
        label = groupName,
        grade = grade,
        isBoss = grade >= 3,
        onDuty = true
    }
end

local function getEsxRole(xPlayer)
    local job = xPlayer and xPlayer.job or {}
    local grade = tonumber(job.grade) or 0
    local gradeName = tostring(job.grade_name or ''):lower()
    return {
        name = job.name,
        label = job.label or job.name,
        grade = grade,
        isBoss = gradeName == 'boss',
        onDuty = true
    }
end

local function getCustomGangForIdentifier(identifier)
    local key = tostring(identifier or '')
    if key == '' then
        return nil
    end

    local cached = CustomGangCache[key]
    local now = nowMs()
    if cached and now < cached.expiresAt then
        return cached.role
    end

    local row = MySQL.single.await([[SELECT gm.gang_name, gm.grade, g.label, g.max_grade
        FROM bossmenu_gang_members gm
        LEFT JOIN bossmenu_gangs g ON g.name = gm.gang_name
        WHERE gm.identifier = ?
        LIMIT 1]], { key })

    local role
    if row and row.gang_name then
        local level = tonumber(row.grade) or 0
        local fallbackLabel, fallbackMaxGrade = getInbuiltGangLabelAndMax(row.gang_name)
        local maxGrade = tonumber(row.max_grade) or tonumber(fallbackMaxGrade) or 4
        role = {
            name = row.gang_name,
            label = row.label or fallbackLabel or row.gang_name,
            grade = level,
            isBoss = level >= maxGrade,
            onDuty = true
        }
    else
        role = {
            name = nil,
            label = nil,
            grade = 0,
            isBoss = false,
            onDuty = true
        }
    end

    CustomGangCache[key] = {
        role = role,
        expiresAt = now + 3000
    }

    return role
end

local function invalidateCustomGang(identifier)
    if not identifier then return end
    CustomGangCache[tostring(identifier)] = nil
end

local function getPlayerState(src)
    src = tonumber(src)
    if not src or src < 1 then return nil end

    if frameworkName == 'qb' then
        local player = QBCore and QBCore.Functions.GetPlayer(src)
        if not player then return nil end
        local pd = player.PlayerData
        local gangRole = usingCustomGangBackend() and getCustomGangForIdentifier(pd.citizenid) or getQbLikeRole(player, 'gang')
        return {
            source = src,
            identifier = pd.citizenid,
            name = getQbLikeName(player),
            job = getQbLikeRole(player, 'job'),
            gang = gangRole,
            raw = player
        }
    end

    if frameworkName == 'qbox' then
        local player = exports.qbx_core:GetPlayer(src)
        if not player then return nil end
        local pd = player.PlayerData or {}
        return {
            source = src,
            identifier = pd.citizenid,
            name = getQbLikeName(player),
            job = getQbLikeRole(player, 'job'),
            gang = getQbLikeRole(player, 'gang'),
            raw = player
        }
    end

    if frameworkName == 'esx' then
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if not xPlayer then return nil end
        local gangRole = usingCustomGangBackend() and getCustomGangForIdentifier(xPlayer.identifier) or nil
        return {
            source = src,
            identifier = xPlayer.identifier,
            name = xPlayer.getName and xPlayer.getName() or GetPlayerName(src),
            job = getEsxRole(xPlayer),
            gang = gangRole,
            raw = xPlayer
        }
    end

    if frameworkName == 'ox' then
        local player = getOxPlayer(src)
        if not player then return nil end
        local first = player.get('firstName') or ''
        local last = player.get('lastName') or ''
        local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
        if name == '' then name = GetPlayerName(src) end
        return {
            source = src,
            identifier = tostring(player.charId or player.stateId or src),
            name = name,
            job = getOxRole(player),
            gang = nil,
            raw = player
        }
    end

    return nil
end

local function getMenuType(value)
    return value == 'gang' and 'gang' or 'boss'
end

local function roleFromMenu(player, menuType)
    if menuType == 'gang' then
        return player.gang
    end
    return player.job
end

local function hasRoleAccess(player, menuType)
    local role = roleFromMenu(player, menuType)
    if not role or not role.name then return false end
    if role.isBoss then return true end
    local minGrade = menuType == 'gang' and (Config.MinGangBossGrade or 99) or (Config.MinBossGrade or 99)
    return (role.grade or 0) >= tonumber(minGrade)
end

local function roleIcon(menuType, roleName)
    if menuType == 'gang' then
        return (Config.GangIcons and Config.GangIcons[roleName]) or Config.DefaultIcon or 'fa-briefcase'
    end
    return (Config.JobIcons and Config.JobIcons[roleName]) or Config.DefaultIcon or 'fa-briefcase'
end

local ORG_ARCHETYPES = {
    corporate = {
        id = 'corporate',
        title = 'Executive Operations',
        subtitle = 'Commercial command and growth orchestration',
        deck = 'Executive Command Deck',
        memberTabLabel = 'Workforce',
        membersLabel = 'Staff',
        nearbyLabel = 'Candidates',
        financeLabel = 'Treasury',
        ledgerLabel = 'Finance Activity Feed',
        financeInput = 'Transfer amount',
        depositLabel = 'Deposit',
        withdrawLabel = 'Withdraw',
        opsLabel = 'Commercial Operations',
        keywords = { 'business', 'company', 'corp', 'executive', 'manager', 'director', 'ceo', 'retail', 'office' },
        colors = { a = '#d7b56a', b = '#345f8a', c = '#0d2740' }
    },
    law = {
        id = 'law',
        title = 'Law Enforcement Command',
        subtitle = 'Operational readiness and incident governance',
        deck = 'Tactical Command Grid',
        memberTabLabel = 'Officers',
        membersLabel = 'Officers',
        nearbyLabel = 'Field Units',
        financeLabel = 'Department Budget',
        ledgerLabel = 'Budget & Action Feed',
        financeInput = 'Budget adjustment amount',
        depositLabel = 'Allocate',
        withdrawLabel = 'Consume',
        opsLabel = 'Public Safety Operations',
        keywords = { 'police', 'sheriff', 'trooper', 'state', 'lspd', 'bcso', 'sasp', 'pd', 'swat', 'officer', 'deputy', 'chief', 'captain', 'sergeant' },
        colors = { a = '#73d0ff', b = '#5f8fd8', c = '#132f59' }
    },
    medical = {
        id = 'medical',
        title = 'Medical Administration',
        subtitle = 'Clinical staffing and service continuity',
        deck = 'Medical Operations Deck',
        memberTabLabel = 'Medical Staff',
        membersLabel = 'Medical Staff',
        nearbyLabel = 'On-call Staff',
        financeLabel = 'Medical Budget',
        ledgerLabel = 'Funding Activity',
        financeInput = 'Allocation amount',
        depositLabel = 'Fund',
        withdrawLabel = 'Spend',
        opsLabel = 'Healthcare Operations',
        keywords = { 'ambulance', 'ems', 'hospital', 'medic', 'doctor', 'nurse', 'clinic', 'trauma' },
        colors = { a = '#79e2c5', b = '#4aa7b8', c = '#124250' }
    },
    mechanic = {
        id = 'mechanic',
        title = 'Workshop Administration',
        subtitle = 'Shop throughput and service workforce control',
        deck = 'Workshop Command Deck',
        memberTabLabel = 'Technicians',
        membersLabel = 'Technicians',
        nearbyLabel = 'Applicants Nearby',
        financeLabel = 'Shop Treasury',
        ledgerLabel = 'Service Ledger Feed',
        financeInput = 'Service fund amount',
        depositLabel = 'Add Funds',
        withdrawLabel = 'Use Funds',
        opsLabel = 'Service Operations',
        keywords = { 'mechanic', 'tuner', 'auto', 'garage', 'bennys', 'repair', 'customs', 'workshop' },
        colors = { a = '#f4bf72', b = '#ca7a2c', c = '#47321a' }
    },
    dealer = {
        id = 'dealer',
        title = 'Dealership Command',
        subtitle = 'Sales force coordination and revenue oversight',
        deck = 'Dealership Command Deck',
        memberTabLabel = 'Sales Team',
        membersLabel = 'Sales Team',
        nearbyLabel = 'Prospects Nearby',
        financeLabel = 'Sales Treasury',
        ledgerLabel = 'Sales Ledger Feed',
        financeInput = 'Sales account amount',
        depositLabel = 'Deposit',
        withdrawLabel = 'Withdraw',
        opsLabel = 'Sales Operations',
        keywords = { 'dealer', 'dealership', 'vehicle', 'cars', 'motors', 'luxury', 'autos', 'sales' },
        colors = { a = '#f0d083', b = '#8f6ad8', c = '#2b2148' }
    },
    hospitality = {
        id = 'hospitality',
        title = 'Hospitality Operations',
        subtitle = 'Guest experience and venue workforce management',
        deck = 'Venue Command Deck',
        memberTabLabel = 'Crew',
        membersLabel = 'Crew Members',
        nearbyLabel = 'Walk-in Staff',
        financeLabel = 'Venue Treasury',
        ledgerLabel = 'Venue Finance Feed',
        financeInput = 'Venue transfer amount',
        depositLabel = 'Deposit',
        withdrawLabel = 'Withdraw',
        opsLabel = 'Venue Operations',
        keywords = { 'restaurant', 'bar', 'club', 'nightclub', 'casino', 'hotel', 'lounge', 'bahama' },
        colors = { a = '#e6a86f', b = '#be5474', c = '#4b243a' }
    },
    logistics = {
        id = 'logistics',
        title = 'Logistics Command',
        subtitle = 'Delivery network and labor coordination',
        deck = 'Dispatch Operations Deck',
        memberTabLabel = 'Drivers',
        membersLabel = 'Drivers & Crew',
        nearbyLabel = 'Available Drivers',
        financeLabel = 'Fleet Treasury',
        ledgerLabel = 'Dispatch Ledger Feed',
        financeInput = 'Fleet budget amount',
        depositLabel = 'Allocate',
        withdrawLabel = 'Consume',
        opsLabel = 'Logistics Operations',
        keywords = { 'trucker', 'logistics', 'delivery', 'transport', 'dispatch', 'fleet', 'cargo' },
        colors = { a = '#8ac5ff', b = '#4c7abd', c = '#213556' }
    },
    security = {
        id = 'security',
        title = 'Security Administration',
        subtitle = 'Protective operations and guard command control',
        deck = 'Security Command Deck',
        memberTabLabel = 'Guards',
        membersLabel = 'Guard Units',
        nearbyLabel = 'Deployable Units',
        financeLabel = 'Security Budget',
        ledgerLabel = 'Security Action Feed',
        financeInput = 'Security budget amount',
        depositLabel = 'Allocate',
        withdrawLabel = 'Use',
        opsLabel = 'Security Operations',
        keywords = { 'security', 'guard', 'protection', 'watch', 'patrol', 'response' },
        colors = { a = '#9fd7f2', b = '#447693', c = '#1e3b4d' }
    },
    gang_street = {
        id = 'gang_street',
        title = 'Street Command',
        subtitle = 'Territory pressure and crew orchestration',
        deck = 'Street Operations Deck',
        memberTabLabel = 'Crew',
        membersLabel = 'Crew Members',
        nearbyLabel = 'Nearby Recruits',
        financeLabel = 'Cash Locker',
        ledgerLabel = 'Street Activity Feed',
        financeInput = 'Cash locker amount',
        depositLabel = 'Stash',
        withdrawLabel = 'Pull',
        opsLabel = 'Gang Operations',
        keywords = { 'gang', 'street', 'hood', 'crew', 'block', 'set', 'fam', 'og' },
        colors = { a = '#e7b86a', b = '#b24f3e', c = '#4a241f' }
    },
    gang_biker = {
        id = 'gang_biker',
        title = 'Motor Club Command',
        subtitle = 'Chapter leadership and club operations',
        deck = 'Chapter Operations Deck',
        memberTabLabel = 'Riders',
        membersLabel = 'Club Members',
        nearbyLabel = 'Prospects Nearby',
        financeLabel = 'Club Treasury',
        ledgerLabel = 'Club Ledger Feed',
        financeInput = 'Club transfer amount',
        depositLabel = 'Deposit',
        withdrawLabel = 'Withdraw',
        opsLabel = 'Motor Club Operations',
        keywords = { 'mc', 'motor', 'bike', 'biker', 'chapter', 'road', 'rider', 'president', 'sergeant at arms' },
        colors = { a = '#f0c788', b = '#8c4b36', c = '#3b261f' }
    },
    gang_cartel = {
        id = 'gang_cartel',
        title = 'Cartel Operations',
        subtitle = 'Network command and expansion control',
        deck = 'Cartel Operations Deck',
        memberTabLabel = 'Operatives',
        membersLabel = 'Operatives',
        nearbyLabel = 'Runners Nearby',
        financeLabel = 'Network Treasury',
        ledgerLabel = 'Network Ledger Feed',
        financeInput = 'Network amount',
        depositLabel = 'Deposit',
        withdrawLabel = 'Withdraw',
        opsLabel = 'Network Operations',
        keywords = { 'cartel', 'sinaloa', 'familia', 'sicario', 'jefe', 'narcos', 'drug', 'plaza' },
        colors = { a = '#f4ca7f', b = '#3f8f5d', c = '#1f412f' }
    },
    gang_mafia = {
        id = 'gang_mafia',
        title = 'Syndicate Command',
        subtitle = 'Family hierarchy and enterprise control',
        deck = 'Syndicate Operations Deck',
        memberTabLabel = 'Associates',
        membersLabel = 'Family Members',
        nearbyLabel = 'Associates Nearby',
        financeLabel = 'Family Treasury',
        ledgerLabel = 'Family Ledger Feed',
        financeInput = 'Family account amount',
        depositLabel = 'Deposit',
        withdrawLabel = 'Withdraw',
        opsLabel = 'Syndicate Operations',
        keywords = { 'mafia', 'mob', 'family', 'consigliere', 'underboss', 'capo', 'don', 'syndicate' },
        colors = { a = '#d3b37a', b = '#915f5f', c = '#35242b' }
    }
}

local function inferOrgProfile(menuType, roleName, roleLabel, grades)
    local isGang = menuType == 'gang'
    local overrideMap = type(Config.OrgArchetypeOverrides) == 'table' and Config.OrgArchetypeOverrides or {}
    local override = overrideMap[tostring(roleName or ''):lower()] or overrideMap[tostring(roleLabel or ''):lower()]
    if override and ORG_ARCHETYPES[tostring(override)] then
        return ORG_ARCHETYPES[tostring(override)]
    end
    local corpus = ('%s %s'):format(tostring(roleName or ''), tostring(roleLabel or '')):lower()
    if type(grades) == 'table' then
        for i = 1, #grades do
            local rankName = cleanText(grades[i] and grades[i].name, 64)
            if rankName ~= '' then
                corpus = corpus .. ' ' .. rankName:lower()
            end
        end
    end

    local candidates = isGang
        and { 'gang_street', 'gang_biker', 'gang_cartel', 'gang_mafia' }
        or { 'law', 'medical', 'mechanic', 'dealer', 'hospitality', 'logistics', 'security', 'corporate' }

    local best = isGang and 'gang_street' or 'corporate'
    local bestScore = -1
    for i = 1, #candidates do
        local id = candidates[i]
        local def = ORG_ARCHETYPES[id]
        local score = 0
        if def and type(def.keywords) == 'table' then
            for k = 1, #def.keywords do
                local keyword = tostring(def.keywords[k] or ''):lower()
                if keyword ~= '' and corpus:find(keyword, 1, true) then
                    score = score + 3
                end
            end
        end
        if isGang and id:sub(1, 5) == 'gang_' then
            score = score + 1
        end
        if score > bestScore then
            best = id
            bestScore = score
        end
    end

    return ORG_ARCHETYPES[best] or ORG_ARCHETYPES.corporate
end

local function financeAllowed(menuType)
    if menuType == 'boss' then
        return true
    end
    return menuType == 'gang' and Config.Modules and Config.Modules.GangCashLocker == true
end

local function isModuleEnabled(name)
    return Config.Modules and Config.Modules[name] == true
end

local function stashKey(orgType, orgName)
    return ('bm:%s:%s'):format(tostring(orgType or 'boss'), tostring(orgName or 'unknown'))
end

local function getStashIntegration()
    if not InventoryModule or not InventoryModule.GetIntegration then
        return 'none'
    end
    local backend = tostring(InventoryModule.GetIntegration() or 'none')
    if backend == '' then backend = 'none' end
    return backend
end

local hasContextPermission = function()
    return false
end

local function canUseOrgStash(context)
    if not context or context.menuType ~= 'boss' then
        return false
    end
    if hasContextPermission(context, 'view_inventory')
        or hasContextPermission(context, 'deposit_items')
        or hasContextPermission(context, 'withdraw_items')
        or hasContextPermission(context, 'lock_inventory') then
        return true
    end
    return false
end

local function stashOpenMeta(context)
    local orgType = context.menuType == 'gang' and 'gang' or 'boss'
    local orgName = context.role.name
    local key = stashKey(orgType, orgName)
    local label = ('%s Boss Stash'):format(context.role.label or orgName)
    return {
        orgType = orgType,
        orgName = orgName,
        stashId = key,
        label = label,
        slots = tonumber(Config.StashSlots or 250) or 250,
        maxWeight = tonumber(Config.StashMaxWeight or 1000000) or 1000000
    }
end

local function cameraModuleEnabled()
    return isModuleEnabled('Cameras')
end

local function getCameraConfig()
    return type(Config.Cameras) == 'table' and Config.Cameras or {}
end

local function cameraIntegration()
    return cleanText(Config.Integrations and Config.Integrations.camera or 'auto', 32):lower()
end

local function autoCameraProvider()
    local cfg = getCameraConfig()
    local order = type(cfg.autoProviderOrder) == 'table' and cfg.autoProviderOrder
        or { 'qb-policejob', 'esx_policejob', 'rcore_cctv', 'loaf_cctv', 'okokCCTV', 'tk_cctv', 'native' }
    for i = 1, #order do
        local name = cleanText(order[i], 40)
        if name == 'native' then
            return 'native'
        end
        local state = GetResourceState(name)
        if state == 'started' or state == 'starting' then
            return name
        end
    end
    return 'native'
end

local function resolveCameraProvider(context, archetypeId)
    local cfg = getCameraConfig()
    local byOrg = type(cfg.providerByOrg) == 'table' and cfg.providerByOrg or {}
    local orgProvider = byOrg[tostring(context.role.name or ''):lower()]
    if orgProvider and cleanText(orgProvider, 40) ~= '' then
        return cleanText(orgProvider, 40)
    end
    local integration = cameraIntegration()
    if integration == 'auto' then
        return autoCameraProvider()
    end
    if integration == 'none' then
        return 'none'
    end
    return integration
end

local function canUseArchetypeCameras(archetypeId)
    local cfg = getCameraConfig()
    local allowed = type(cfg.allowedArchetypes) == 'table' and cfg.allowedArchetypes or nil
    if not allowed then
        return true
    end
    return allowed[tostring(archetypeId or '')] == true
end

local function sanitizeCameraFeed(raw, indexFallback)
    if type(raw) ~= 'table' then return nil end
    local id = cleanText(raw.id, 64)
    if id == '' then
        id = ('cam_%s'):format(tostring(indexFallback or 0))
    end
    local label = cleanText(raw.label, 80)
    if label == '' then
        label = id
    end
    local icon = cleanText(raw.icon, 32)
    local coords = nil
    if type(raw.coords) == 'table' then
        local x = tonumber(raw.coords.x)
        local y = tonumber(raw.coords.y)
        local z = tonumber(raw.coords.z)
        if x and y and z then
            coords = {
                x = x, y = y, z = z,
                w = tonumber(raw.coords.w) or tonumber(raw.coords.h) or 0.0
            }
        end
    end
    return {
        id = id,
        label = label,
        icon = icon ~= '' and icon or 'camera',
        coords = coords,
        providerData = type(raw.providerData) == 'table' and raw.providerData or {}
    }
end

local function resolveCameraFeeds(context, archetypeId)
    local cfg = getCameraConfig()
    local feeds = {}
    local byOrg = type(cfg.feedsByOrg) == 'table' and cfg.feedsByOrg or {}
    local byArch = type(cfg.feedsByArchetype) == 'table' and cfg.feedsByArchetype or {}
    local orgKey = tostring(context.role.name or ''):lower()

    local source = nil
    if type(byOrg[orgKey]) == 'table' then
        source = byOrg[orgKey]
    elseif type(byArch[tostring(archetypeId or '')]) == 'table' then
        source = byArch[tostring(archetypeId or '')]
    end

    if type(source) == 'table' then
        for i = 1, #source do
            local row = sanitizeCameraFeed(source[i], i)
            if row then
                feeds[#feeds + 1] = row
            end
        end
    end

    return feeds
end

local function getScreenshotConfig()
    return type(Config.Screenshots) == 'table' and Config.Screenshots or {}
end

local function screenshotIntegration()
    return cleanText(Config.Integrations and Config.Integrations.screenshot or 'auto', 32):lower()
end

local function resolveScreenshotProviders()
    local cfg = getScreenshotConfig()
    local integration = screenshotIntegration()
    if integration == 'none' then
        return {}
    end

    local providersCfg = type(cfg.providers) == 'table' and cfg.providers or {}
    local out = {}
    local seen = {}

    local function addProviderByName(name)
        local key = cleanText(name, 64)
        if key == '' or seen[key] then return end
        seen[key] = true
        local def = providersCfg[key]
        if type(def) == 'table' then
            local resource = cleanText(def.resource or key, 64)
            if resource ~= '' then
                out[#out + 1] = {
                    name = key,
                    resource = resource,
                    mode = cleanText(def.mode or 'screenshot_basic_client', 64),
                    exportName = cleanText(def.exportName or '', 64),
                    callbackFirst = def.callbackFirst == true
                }
                return
            end
        end
        out[#out + 1] = {
            name = key,
            resource = key,
            mode = 'screenshot_basic_client',
            exportName = '',
            callbackFirst = false
        }
    end

    if integration ~= 'auto' then
        addProviderByName(integration)
        return out
    end

    local order = type(cfg.autoProviderOrder) == 'table' and cfg.autoProviderOrder
        or { 'screenshot-basic', 'screencapture', 'screenhost-basic' }
    for i = 1, #order do
        addProviderByName(order[i])
    end

    return out
end

local function getOrgTypeByMenu(menuType)
    return menuType == 'gang' and 'gang' or 'boss'
end

local function gradeCacheKey(menuType, roleName)
    return ('%s:%s'):format(menuType, roleName)
end

local function customRankCacheKey(menuType, roleName)
    return ('%s:%s'):format(menuType, roleName)
end

local function permissionCacheKey(menuType, roleName, grade)
    return ('%s:%s:%s'):format(menuType, roleName, tonumber(grade) or 0)
end

local function clearEmployeeCache(menuType, roleName)
    EmployeeCache[('%s:%s'):format(menuType, roleName)] = nil
end

local function invalidateOrganizationCaches(menuType, roleName)
    local base = ('%s:%s'):format(menuType, roleName)
    GradeCache[base] = nil
    CustomRankCache[base] = nil
    clearEmployeeCache(menuType, roleName)
    for key in pairs(PermissionCache) do
        if key:sub(1, #base) == base then
            PermissionCache[key] = nil
        end
    end
end

local function orgStateCacheKey(orgType, orgName)
    return ('%s:%s'):format(tostring(orgType or 'boss'), tostring(orgName or 'unknown'))
end

local function invalidateOrgStateCache(orgType, orgName)
    OrgStateCache[orgStateCacheKey(orgType, orgName)] = nil
end

local function getOrgState(orgType, orgName)
    local key = orgStateCacheKey(orgType, orgName)
    local cached = OrgStateCache[key]
    local now = nowMs()
    if cached and now < cached.expiresAt then
        return cached.state
    end
    local row = MySQL.single.await([[SELECT disabled, reason, updated_by, updated_at
        FROM bossmenu_org_state
        WHERE org_type = ? AND org_name = ?
        LIMIT 1]], { tostring(orgType), tostring(orgName) })
    local state = {
        disabled = row and tonumber(row.disabled) == 1 or false,
        reason = row and cleanText(row.reason, 255) or '',
        updatedBy = row and cleanText(row.updated_by, 80) or nil,
        updatedAt = row and row.updated_at or nil
    }
    OrgStateCache[key] = {
        state = state,
        expiresAt = now + 5000
    }
    return state
end

local function setOrgState(orgType, orgName, disabled, reason, actor)
    MySQL.insert.await([[INSERT INTO bossmenu_org_state (org_type, org_name, disabled, reason, updated_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE disabled = VALUES(disabled), reason = VALUES(reason), updated_by = VALUES(updated_by), updated_at = NOW()]], {
        tostring(orgType),
        tostring(orgName),
        disabled == true and 1 or 0,
        cleanText(reason, 255),
        cleanText(actor, 80)
    })
    invalidateOrgStateCache(orgType, orgName)
end

local function maxMoneyAmount()
    local value = Config.Security and (Config.Security.maxMoneyActionAmount or Config.Security.maxAmount) or 5000000
    return tonumber(value) or 5000000
end

local function ensureTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_accounts (
        job VARCHAR(64) NOT NULL PRIMARY KEY,
        balance BIGINT NOT NULL DEFAULT 0,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_ledger (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        job VARCHAR(64) NOT NULL,
        action VARCHAR(32) NOT NULL,
        amount INT NOT NULL,
        actor_identifier VARCHAR(80) NULL,
        target_identifier VARCHAR(80) NULL,
        note VARCHAR(255) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_job_created (job, created_at)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_audit (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        job VARCHAR(64) NOT NULL,
        action VARCHAR(40) NOT NULL,
        actor_identifier VARCHAR(80) NULL,
        target_identifier VARCHAR(80) NULL,
        payload JSON NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_job_created (job, created_at)
    )]])

    local function ensureAuditColumn(columnName, definition)
        local exists = MySQL.scalar.await([[SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bossmenu_audit' AND COLUMN_NAME = ?
            LIMIT 1]], { columnName })
        if not exists then
            MySQL.query.await(('ALTER TABLE bossmenu_audit ADD COLUMN %s %s'):format(columnName, definition))
        end
    end

    ensureAuditColumn('org_type', "VARCHAR(16) NULL AFTER id")
    ensureAuditColumn('org_name', "VARCHAR(64) NULL AFTER org_type")
    ensureAuditColumn('actor_name', "VARCHAR(120) NULL AFTER actor_identifier")
    ensureAuditColumn('target_name', "VARCHAR(120) NULL AFTER target_identifier")
    ensureAuditColumn('metadata_json', "JSON NULL AFTER payload")

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gangs (
        name VARCHAR(64) NOT NULL PRIMARY KEY,
        label VARCHAR(80) NOT NULL,
        max_grade INT NOT NULL DEFAULT 4,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gang_members (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        gang_name VARCHAR(64) NOT NULL,
        identifier VARCHAR(80) NOT NULL,
        grade INT NOT NULL DEFAULT 0,
        joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_gang_identifier (gang_name, identifier),
        UNIQUE KEY uq_identifier (identifier),
        INDEX idx_gang_grade (gang_name, grade)
    )]])

    -- Optional module foundations (idempotent migrations).
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_rank_permissions (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        grade INT NOT NULL,
        permission_key VARCHAR(64) NOT NULL,
        allowed TINYINT(1) NOT NULL DEFAULT 0,
        updated_by VARCHAR(80) NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_rank_permission (org_type, org_name, grade, permission_key)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_custom_ranks (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        grade INT NOT NULL,
        rank_name VARCHAR(64) NOT NULL,
        rank_icon VARCHAR(64) NULL,
        rank_style JSON NULL,
        salary_type VARCHAR(24) NULL,
        salary_amount INT NULL,
        description TEXT NULL,
        protected_rank TINYINT(1) NOT NULL DEFAULT 0,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_custom_rank (org_type, org_name, grade)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_employee_profiles (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        identifier VARCHAR(80) NOT NULL,
        joined_at DATETIME NULL,
        hired_by VARCHAR(80) NULL,
        notes TEXT NULL,
        strikes INT NOT NULL DEFAULT 0,
        photo_url LONGTEXT NULL,
        metadata JSON NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_profile (org_type, org_name, identifier)
    )]])
    MySQL.query.await('ALTER TABLE bossmenu_employee_profiles MODIFY COLUMN photo_url LONGTEXT NULL')

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_employee_activity (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        identifier VARCHAR(80) NOT NULL,
        action VARCHAR(64) NOT NULL,
        details JSON NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_emp_activity (org_type, org_name, identifier, created_at)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_salary_overrides (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        identifier VARCHAR(80) NULL,
        grade INT NULL,
        salary_type VARCHAR(24) NOT NULL DEFAULT 'custom',
        salary_amount INT NOT NULL DEFAULT 0,
        updated_by VARCHAR(80) NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_salary_scope (org_type, org_name, identifier, grade)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_payroll_runs (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        run_type VARCHAR(24) NOT NULL DEFAULT 'manual',
        total_amount INT NOT NULL DEFAULT 0,
        paid_count INT NOT NULL DEFAULT 0,
        failed_count INT NOT NULL DEFAULT 0,
        status VARCHAR(24) NOT NULL DEFAULT 'completed',
        metadata JSON NULL,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_org_inventory (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        item_name VARCHAR(80) NOT NULL,
        amount INT NOT NULL DEFAULT 0,
        metadata JSON NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_org_item (org_type, org_name, item_name)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_org_inventory_logs (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        action VARCHAR(24) NOT NULL,
        item_name VARCHAR(80) NOT NULL,
        amount INT NOT NULL DEFAULT 0,
        actor_identifier VARCHAR(80) NULL,
        target_identifier VARCHAR(80) NULL,
        metadata JSON NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_org_inv_log (org_type, org_name, created_at)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_org_uniforms (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        uniform_name VARCHAR(80) NOT NULL,
        male_data JSON NULL,
        female_data JSON NULL,
        rank_map JSON NULL,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_org_markers (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        marker_type VARCHAR(32) NOT NULL,
        coords JSON NOT NULL,
        marker_data JSON NULL,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_org_garages (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        name VARCHAR(80) NOT NULL,
        coords JSON NOT NULL,
        options_json JSON NULL,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_job_applications (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        applicant_identifier VARCHAR(80) NULL,
        applicant_name VARCHAR(100) NOT NULL,
        applicant_phone VARCHAR(40) NULL,
        answers JSON NULL,
        status VARCHAR(24) NOT NULL DEFAULT 'pending',
        decision_reason TEXT NULL,
        decided_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_announcements (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        title VARCHAR(120) NOT NULL,
        body TEXT NOT NULL,
        pinned TINYINT(1) NOT NULL DEFAULT 0,
        visibility_json JSON NULL,
        expires_at DATETIME NULL,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_admin_actions (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        admin_identifier VARCHAR(80) NOT NULL,
        action VARCHAR(64) NOT NULL,
        org_type VARCHAR(16) NULL,
        org_name VARCHAR(64) NULL,
        target_identifier VARCHAR(80) NULL,
        metadata JSON NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_webhook_settings (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        scope_type VARCHAR(16) NOT NULL,
        org_type VARCHAR(16) NOT NULL DEFAULT '',
        org_name VARCHAR(64) NOT NULL DEFAULT '',
        category VARCHAR(32) NOT NULL,
        webhook_url TEXT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        updated_by VARCHAR(80) NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_webhook_scope (scope_type, org_type, org_name, category),
        INDEX idx_webhook_scope (scope_type, org_type, org_name)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_org_state (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        disabled TINYINT(1) NOT NULL DEFAULT 0,
        reason VARCHAR(255) NULL,
        updated_by VARCHAR(80) NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_org_state (org_type, org_name)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_tax_accounts (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NOT NULL,
        org_name VARCHAR(64) NOT NULL,
        balance_due INT NOT NULL DEFAULT 0,
        next_due_at DATETIME NULL,
        grace_ends_at DATETIME NULL,
        metadata JSON NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_tax_account (org_type, org_name)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_bills_invoices (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        org_type VARCHAR(16) NULL,
        org_name VARCHAR(64) NULL,
        issuer_identifier VARCHAR(80) NULL,
        target_identifier VARCHAR(80) NULL,
        target_org_type VARCHAR(16) NULL,
        target_org_name VARCHAR(64) NULL,
        amount INT NOT NULL DEFAULT 0,
        reason VARCHAR(255) NULL,
        status VARCHAR(24) NOT NULL DEFAULT 'unpaid',
        metadata JSON NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_scheduled_tasks (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        module_name VARCHAR(40) NOT NULL,
        task_type VARCHAR(80) NOT NULL,
        payload JSON NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        last_run_at DATETIME NULL,
        next_run_at DATETIME NULL,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_sched_next (enabled, next_run_at)
    )]])

    local function ensureScheduledColumn(columnName, definition)
        local exists = MySQL.scalar.await([[SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bossmenu_scheduled_tasks' AND COLUMN_NAME = ?
            LIMIT 1]], { columnName })
        if not exists then
            MySQL.query.await(('ALTER TABLE bossmenu_scheduled_tasks ADD COLUMN %s %s'):format(columnName, definition))
        end
    end

    ensureScheduledColumn('task_type', "VARCHAR(80) NOT NULL DEFAULT 'payroll_run'")
    ensureScheduledColumn('enabled', "TINYINT(1) NOT NULL DEFAULT 1")
    ensureScheduledColumn('last_run_at', "DATETIME NULL")
    ensureScheduledColumn('next_run_at', "DATETIME NULL")
    ensureScheduledColumn('updated_at', "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gang_notoriety (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        gang_name VARCHAR(64) NOT NULL,
        points INT NOT NULL DEFAULT 0,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_gang_notoriety (gang_name)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gang_markers (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        gang_name VARCHAR(64) NOT NULL,
        marker_type VARCHAR(32) NOT NULL,
        coords JSON NOT NULL,
        marker_data JSON NULL,
        created_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gang_territories (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        territory_name VARCHAR(80) NOT NULL,
        territory_type VARCHAR(32) NOT NULL DEFAULT 'basic',
        owner_gang VARCHAR(64) NULL,
        coords JSON NOT NULL,
        metadata JSON NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_territory_name (territory_name)
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gang_rackets (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        gang_name VARCHAR(64) NOT NULL,
        territory_name VARCHAR(80) NULL,
        level INT NOT NULL DEFAULT 1,
        stored_income INT NOT NULL DEFAULT 0,
        upgrades JSON NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gang_graffiti (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        gang_name VARCHAR(64) NOT NULL,
        style_name VARCHAR(64) NULL,
        text_label VARCHAR(120) NULL,
        coords JSON NOT NULL,
        metadata JSON NULL,
        expires_at DATETIME NULL,
        placed_by VARCHAR(80) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])
    MySQL.query.await('ALTER TABLE bossmenu_gang_graffiti ADD COLUMN IF NOT EXISTS metadata JSON NULL')

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_gang_contracts (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        gang_name VARCHAR(64) NOT NULL,
        contract_type VARCHAR(40) NOT NULL,
        status VARCHAR(24) NOT NULL DEFAULT 'available',
        reward_json JSON NULL,
        payload JSON NULL,
        accepted_by VARCHAR(80) NULL,
        accepted_at DATETIME NULL,
        completed_at DATETIME NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bossmenu_hidden_workshop_profiles (
        gang_name VARCHAR(64) NOT NULL PRIMARY KEY,
        reputation INT NOT NULL DEFAULT 0,
        level INT NOT NULL DEFAULT 1,
        jobs_completed INT NOT NULL DEFAULT 0,
        jobs_failed INT NOT NULL DEFAULT 0,
        early_cashouts INT NOT NULL DEFAULT 0,
        cars_stripped INT NOT NULL DEFAULT 0,
        total_cash_earned INT NOT NULL DEFAULT 0,
        total_parts_earned INT NOT NULL DEFAULT 0,
        heat INT NOT NULL DEFAULT 0,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])
end

local function ensureGangDefinitions()
    local seen = {}
    if type(Config.GangMenus) == 'table' then
        for name in pairs(Config.GangMenus) do
            seen[tostring(name)] = true
        end
    end
    if type(Config.InbuiltGangDefinitions) == 'table' then
        for name in pairs(Config.InbuiltGangDefinitions) do
            seen[tostring(name)] = true
        end
    end

    for name in pairs(seen) do
        local label, maxGrade = getInbuiltGangLabelAndMax(name)
        MySQL.insert.await([[INSERT INTO bossmenu_gangs (name, label, max_grade)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE label = VALUES(label), max_grade = VALUES(max_grade)]], {
            tostring(name),
            tostring(label or name),
            tonumber(maxGrade) or 4
        })
    end
end

local function waitForOxmysqlConnection()
    while not ResourceStopping do
        if GetResourceState('oxmysql') == 'started' then
            local ok = pcall(function()
                return MySQL.scalar.await('SELECT 1')
            end)
            if ok then
                return true
            end
        end

        Wait(250)
    end

    return false
end

local function initializeRuntimeDatabase()
    if RuntimeInitializationStarted then
        return
    end

    RuntimeInitializationStarted = true

    CreateThread(function()
        if not waitForOxmysqlConnection() then
            return
        end

        local ok, err = pcall(function()
            ensureTables()
            ensureGangDefinitions()
            if Config.EnableGangMenu == true and (not useInbuiltGangFrames()) and (not supportsCustomGangBackend()) then
                print(('[%s] custom gang backend is only supported on QB/ESX. framework=%s, using framework gang backend instead.'):format(resource, frameworkName))
            end
        end)

        if ok then
            BrahBossmenuRuntimeReady = true
            if Config.Debug == true then
                print(('[%s] database initialization complete'):format(resource))
            end
        else
            BrahBossmenuRuntimeReady = false
            print(('[%s] database initialization failed: %s'):format(resource, tostring(err)))
        end
    end)
end

initializeRuntimeDatabase()

local BankingBackend

local function resourceStarted(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local PhoneBackend
local function resolvePhoneBackend()
    if PhoneBackend then return PhoneBackend end
    local wanted = cleanText(Config.Integrations and Config.Integrations.phone or 'none', 32):lower()
    if wanted ~= '' and wanted ~= 'auto' then
        PhoneBackend = wanted
        return PhoneBackend
    end
    if resourceStarted('yseries') then PhoneBackend = 'yseries'
    elseif resourceStarted('qb-phone') then PhoneBackend = 'qb-phone'
    elseif resourceStarted('qs-smartphone') then PhoneBackend = 'qs-smartphone'
    else PhoneBackend = 'none' end
    return PhoneBackend
end

local function sendPhoneNotification(identifier, title, message)
    local backend = resolvePhoneBackend()
    if backend == 'none' then return false end
    local target = cleanText(identifier, 80)
    if target == '' then return false end
    local ok = pcall(function()
        if backend == 'yseries' then
            exports.yseries:SendNotification(target, { title = title, message = message })
        elseif backend == 'qb-phone' then
            TriggerEvent('qb-phone:server:sendNewMailToOffline', target, {
                sender = 'Org Suite',
                subject = title,
                message = message
            })
        elseif backend == 'qs-smartphone' then
            TriggerEvent('qs-smartphone:server:sendNotify', target, { title = title, message = message })
        end
    end)
    return ok
end

local function resolveBankingBackend()
    if BankingBackend then
        return BankingBackend
    end
    local wanted = cleanText(Config.Integrations and Config.Integrations.banking or 'auto', 40):lower()
    if wanted ~= '' and wanted ~= 'auto' then
        BankingBackend = wanted
        return BankingBackend
    end
    if resourceStarted('qb-banking') then
        BankingBackend = 'qb-banking'
    elseif resourceStarted('Renewed-Banking') then
        BankingBackend = 'renewed-banking'
    elseif resourceStarted('okokBanking') then
        BankingBackend = 'okokbanking'
    elseif resourceStarted('esx_addonaccount') then
        BankingBackend = 'esx_addonaccount'
    else
        BankingBackend = 'none'
    end
    return BankingBackend
end

local function tryExportCall(resourceName, exportName, ...)
    if not resourceStarted(resourceName) then return nil end
    local resourceExports = exports[resourceName]
    if not resourceExports then return nil end
    local fn = resourceExports[exportName]
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

local function bankingAccountName(roleName)
    local backend = resolveBankingBackend()
    if backend == 'esx_addonaccount' then
        return ('society_%s'):format(tostring(roleName))
    end
    return tostring(roleName)
end

local function getAddonAccount(accountName)
    if not resourceStarted('esx_addonaccount') then return nil end
    local p = promise.new()
    TriggerEvent('esx_addonaccount:getSharedAccount', accountName, function(account)
        p:resolve(account)
    end)
    return Citizen.Await(p)
end

local function mirrorSocietyMoney(roleName, amount, mode, reason)
    local backend = resolveBankingBackend()
    if backend == 'none' then return false end

    local account = bankingAccountName(roleName)
    local money = tonumber(amount) or 0
    if money <= 0 then return false end

    if backend == 'qb-banking' then
        local label = reason or resource
        if mode == 'add' then
            return tryExportCall('qb-banking', 'AddMoney', account, money, label) == true
                or tryExportCall('qb-banking', 'AddAccountMoney', account, money, label) == true
        end
        return tryExportCall('qb-banking', 'RemoveMoney', account, money, label) == true
            or tryExportCall('qb-banking', 'RemoveAccountMoney', account, money, label) == true
    end

    if backend == 'renewed-banking' then
        local label = reason or resource
        if mode == 'add' then
            return tryExportCall('Renewed-Banking', 'addAccountMoney', account, money, label) == true
                or tryExportCall('Renewed-Banking', 'AddAccountMoney', account, money, label) == true
        end
        return tryExportCall('Renewed-Banking', 'removeAccountMoney', account, money, label) == true
            or tryExportCall('Renewed-Banking', 'RemoveAccountMoney', account, money, label) == true
    end

    if backend == 'okokbanking' then
        if mode == 'add' then
            return tryExportCall('okokBanking', 'AddMoney', account, money) == true
        end
        return tryExportCall('okokBanking', 'RemoveMoney', account, money) == true
    end

    if backend == 'esx_addonaccount' then
        local shared = getAddonAccount(account)
        if not shared then return false end
        if mode == 'add' and shared.addMoney then
            shared.addMoney(money)
            return true
        end
        if mode == 'remove' and shared.removeMoney and tonumber(shared.money or 0) >= money then
            shared.removeMoney(money)
            return true
        end
    end
    return false
end

CreateThread(function()
    Wait(1000)
    if Config.Debug == true then
        print(('[%s] banking integration=%s'):format(resource, tostring(resolveBankingBackend())))
    end
end)

local function ensureAccount(roleName)
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_accounts (job, balance) VALUES (?, 0)', { roleName })
end

local function getBalance(roleName)
    ensureAccount(roleName)
    local balance = MySQL.scalar.await('SELECT balance FROM bossmenu_accounts WHERE job = ? LIMIT 1', { roleName })
    return tonumber(balance) or 0
end

local function runPayrollForOrg(orgType, orgName, actor, mode)
    local employees = getEmployeesForRole(orgType == 'gang' and 'gang' or 'boss', orgName)
    return FinanceModule.RunPayroll(
        orgType,
        orgName,
        employees,
        function(roleName) return getBalance(roleName) end,
        function(roleName, amount)
            ensureAccount(roleName)
            local affected = MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance - ? WHERE job = ? AND balance >= ?', {
                amount, roleName, amount
            })
            if (affected or 0) > 0 then
                mirrorSocietyMoney(roleName, amount, 'remove', 'scheduled_payroll')
            end
            return (affected or 0) > 0
        end,
        actor or 'scheduler',
        mode or 'scheduled'
    )
end

local function runTaxCycle()
    if not (isModuleEnabled('Taxes') and Config.TaxSettings and Config.TaxSettings.enabled == true) then
        return
    end
    local recurringDays = math.max(1, tonumber(Config.TaxSettings.recurringDays or 7) or 7)
    local graceDays = math.max(0, tonumber(Config.TaxSettings.graceDays or 2) or 2)
    local penaltyPercent = math.max(0, tonumber(Config.TaxSettings.penaltyPercent or 10) or 10)
    local autoPayDefault = Config.TaxSettings.autoPayDefault == true

    local rows = MySQL.query.await([[SELECT org_type, org_name, balance_due, next_due_at, grace_ends_at, metadata
        FROM bossmenu_tax_accounts
        WHERE next_due_at IS NOT NULL AND next_due_at <= NOW()
        LIMIT 200]]) or {}
    for i = 1, #rows do
        local row = rows[i]
        local orgType = cleanText(row.org_type, 16)
        local orgName = cleanText(row.org_name, 64)
        if orgName == '' then
            goto continue
        end
        local due = math.max(0, tonumber(row.balance_due) or 0)
        local metadata = decodeJson(row.metadata) or {}
        local autoPay = metadata.autoPay == true or autoPayDefault
        local paid = false
        if due > 0 and autoPay then
            local ok = FinanceModule.PayTaxDue(orgType, orgName, { amount = due }, 'scheduler_tax')
            paid = ok == true
        end

        if due > 0 and not paid then
            local penalty = math.floor(due * (penaltyPercent / 100))
            local newDue = due + penalty
            MySQL.update.await([[UPDATE bossmenu_tax_accounts
                SET balance_due = ?, grace_ends_at = DATE_ADD(NOW(), INTERVAL ? DAY), next_due_at = DATE_ADD(NOW(), INTERVAL ? DAY), updated_at = NOW()
                WHERE org_type = ? AND org_name = ?]], {
                newDue, graceDays, recurringDays, orgType, orgName
            })
            addAudit(orgName, 'tax_cycle_failed', 'scheduler_tax', nil, {
                due = due,
                penalty = penalty,
                newDue = newDue
            })
            emitHook('OnTaxFailed', {
                orgType = orgType,
                orgName = orgName,
                amount = due,
                reason = 'autopay_failed_or_disabled',
                actor = 'scheduler_tax'
            })
        else
            MySQL.update.await([[UPDATE bossmenu_tax_accounts
                SET next_due_at = DATE_ADD(NOW(), INTERVAL ? DAY), grace_ends_at = DATE_ADD(NOW(), INTERVAL ? DAY), updated_at = NOW()
                WHERE org_type = ? AND org_name = ?]], {
                recurringDays, graceDays, orgType, orgName
            })
            addAudit(orgName, 'tax_cycle_processed', 'scheduler_tax', nil, {
                due = due,
                paid = paid
            })
        end
        ::continue::
    end
end

CreateThread(function()
    if not waitForRuntimeReady() then return end
    while true do
        local pollMs = math.max(5, tonumber(Config.ScheduledTasks and Config.ScheduledTasks.pollIntervalSeconds or 15) or 15) * 1000
        if Config.Modules and Config.Modules.ScheduledTasks == true and Config.ScheduledTasks and Config.ScheduledTasks.enabled == true then
            local tasks = MySQL.query.await([[SELECT id, module_name, task_type, payload, next_run_at
                FROM bossmenu_scheduled_tasks
                WHERE enabled = 1 AND next_run_at IS NOT NULL AND next_run_at <= NOW()
                ORDER BY id ASC
                LIMIT 20]]) or {}
            for _, task in ipairs(tasks) do
                local payload = decodeJson(task.payload) or {}
                local taskType = cleanText(task.task_type, 48)
                local intervalSeconds = math.max(60, tonumber(payload.intervalSeconds) or 3600)
                local success = false
                local metadata = {}

                if taskType == 'payroll_run' then
                    local orgType = cleanText(payload.orgType, 16)
                    if orgType ~= 'gang' then orgType = 'boss' end
                    local orgName = cleanText(payload.orgName, 64)
                    if orgName ~= '' and isModuleEnabled('Payroll') then
                        local ok, dataOrErr = runPayrollForOrg(orgType, orgName, 'scheduler', 'scheduled')
                        success = ok == true
                        metadata = type(dataOrErr) == 'table' and dataOrErr or { error = dataOrErr }
                    else
                        metadata = { error = 'invalid_org_or_module_disabled' }
                    end
                else
                    metadata = { error = 'unsupported_task_type' }
                end

                addAudit('scheduler', success and 'scheduled_task_success' or 'scheduled_task_failed', 'scheduler', nil, {
                    taskId = task.id,
                    taskType = taskType,
                    payload = payload,
                    metadata = metadata
                })

                MySQL.update.await([[UPDATE bossmenu_scheduled_tasks
                    SET last_run_at = NOW(), next_run_at = DATE_ADD(NOW(), INTERVAL ? SECOND), payload = ?
                    WHERE id = ?]], {
                    intervalSeconds,
                    json.encode(payload),
                    task.id
                })
            end
        end
        Wait(pollMs)
    end
end)

CreateThread(function()
    if not waitForRuntimeReady() then return end
    while true do
        local intervalMinutes = math.max(5, tonumber(Config.Payroll and Config.Payroll.autoIntervalMinutes or 60) or 60)
        Wait(intervalMinutes * 60000)
        if not (isModuleEnabled('Payroll') and Config.Payroll and Config.Payroll.autoEnabled == true) then
            goto continue
        end
        local rows = MySQL.query.await('SELECT job FROM bossmenu_accounts ORDER BY job ASC') or {}
        for _, row in ipairs(rows) do
            local orgName = cleanText(row.job, 64)
            if orgName ~= '' then
                runPayrollForOrg('boss', orgName, 'scheduler_auto', 'auto')
            end
        end
        ::continue::
    end
end)

CreateThread(function()
    if not waitForRuntimeReady() then return end
    while true do
        local intervalMinutes = math.max(5, tonumber(Config.TaxSettings and Config.TaxSettings.intervalMinutes or 30) or 30)
        Wait(intervalMinutes * 60000)
        runTaxCycle()
    end
end)

CreateThread(function()
    if not waitForRuntimeReady() then return end
    while true do
        local intervalMinutes = math.max(5, tonumber(Config.GangSystems and Config.GangSystems.racketIncomeTickMinutes or 20) or 20)
        Wait(intervalMinutes * 60000)
        if isModuleEnabled('GangRackets') and GangsModule and GangsModule.TickRackets then
            local touched = GangsModule.TickRackets()
            if touched > 0 and Config.Debug == true then
                print(('[%s] rackets tick updated=%s'):format(resource, touched))
            end
        end
        if isModuleEnabled('GangGraffiti') then
            MySQL.update.await('DELETE FROM bossmenu_gang_graffiti WHERE expires_at IS NOT NULL AND expires_at <= NOW()')
        end
    end
end)

local function addLedger(roleName, action, amount, actor, target, note)
    MySQL.insert.await([[INSERT INTO bossmenu_ledger (job, action, amount, actor_identifier, target_identifier, note)
        VALUES (?, ?, ?, ?, ?, ?)]], {
        roleName, action, tonumber(amount) or 0, actor, target, cleanText(note, 255)
    })
end

local function addAudit(roleName, action, actor, target, payload)
    local orgType = 'boss'
    local text = tostring(action or ''):lower()
    if text:find('gang') or text:find('contract') or text:find('territor') or text:find('racket') or text:find('graffiti') then
        orgType = 'gang'
    elseif text:find('admin') then
        orgType = 'admin'
    elseif text:find('security') or text:find('suspicious') then
        orgType = 'security'
    end
    if AuditModule and AuditModule.Write then
        return AuditModule.Write(orgType, roleName, action, actor, target, payload or {})
    end
    MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
        VALUES (?, ?, ?, ?, ?)]], {
        roleName, action, actor, target, payload and json.encode(payload) or nil
    })
end

local function createSession(src, menuType, roleName)
    local token = ('%d:%d:%d'):format(src, unix(), math.random(100000, 999999))
    local ttl = tonumber(Config.Security and Config.Security.sessionTokenTtlSeconds or 120) or 120
    Sessions[src] = {
        token = token,
        menuType = menuType,
        roleName = roleName,
        expiresAt = unix() + ttl
    }
    return token
end

local function verifySession(src, token)
    local session = Sessions[src]
    if not session then return nil end
    if session.expiresAt < unix() then
        Sessions[src] = nil
        return nil
    end
    if session.token ~= token then
        return nil
    end
    session.expiresAt = unix() + (tonumber(Config.Security and Config.Security.sessionTokenTtlSeconds or 120) or 120)
    return session
end

local function getOnlinePlayers()
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then out[#out + 1] = src end
    end
    return out
end

local function isIdentifierOnline(identifier)
    local target = tostring(identifier or '')
    if target == '' then return false end
    for _, src in ipairs(getOnlinePlayers()) do
        local state = getPlayerState(src)
        if state and tostring(state.identifier or '') == target then
            return true
        end
    end
    return false
end

getInbuiltGangDefinition = function(gangName)
    local defs = Config.InbuiltGangDefinitions
    if type(defs) == 'table' and type(defs[gangName]) == 'table' then
        return defs[gangName]
    end
    return nil
end

getInbuiltGangLabelAndMax = function(gangName)
    local def = getInbuiltGangDefinition(gangName)
    local label = def and def.label or gangName
    local maxGrade = tonumber(def and def.maxGrade) or nil
    if not maxGrade then
        local ranks = def and def.ranks or nil
        if type(ranks) == 'table' then
            local best = -1
            for k in pairs(ranks) do
                local n = tonumber(k)
                if n and n > best then
                    best = n
                end
            end
            if best >= 0 then
                maxGrade = best
            end
        end
    end
    if not maxGrade then
        maxGrade = 4
    end
    return label, maxGrade
end

local function mergeStyle(baseStyle, overrideStyle)
    local out = {}
    if type(baseStyle) == 'table' then
        for k, v in pairs(baseStyle) do
            out[k] = v
        end
    end
    if type(overrideStyle) == 'table' then
        for k, v in pairs(overrideStyle) do
            out[k] = v
        end
    end
    return out
end

local function customGangGrades(gangName)
    local rows = {}
    local def = getInbuiltGangDefinition(gangName)
    local defaultStyle = (def and type(def.style) == 'table') and def.style or {}

    if def and type(def.ranks) == 'table' then
        for level, rankData in pairs(def.ranks) do
            local nLevel = tonumber(level)
            if nLevel then
                if type(rankData) == 'table' then
                    rows[#rows + 1] = {
                        level = nLevel,
                        name = tostring(rankData.name or ('Grade ' .. nLevel)),
                        isBoss = false,
                        style = mergeStyle(defaultStyle, rankData.style)
                    }
                else
                    rows[#rows + 1] = {
                        level = nLevel,
                        name = tostring(rankData),
                        isBoss = false,
                        style = mergeStyle(defaultStyle, nil)
                    }
                end
            end
        end
    else
        local rankMap = Config.InbuiltGangRanks or {}
        for i = 0, 20 do
            if rankMap[i] then
                rows[#rows + 1] = {
                    level = i,
                    name = tostring(rankMap[i]),
                    isBoss = false,
                    style = mergeStyle(defaultStyle, nil)
                }
            end
        end
    end

    if #rows == 0 then
        rows = {
            { level = 0, name = 'Recruit', isBoss = false, style = mergeStyle(defaultStyle, nil) },
            { level = 1, name = 'Member', isBoss = false, style = mergeStyle(defaultStyle, nil) },
            { level = 2, name = 'Shot Caller', isBoss = false, style = mergeStyle(defaultStyle, nil) },
            { level = 3, name = 'Underboss', isBoss = false, style = mergeStyle(defaultStyle, nil) },
            { level = 4, name = 'Boss', isBoss = true, style = mergeStyle(defaultStyle, nil) }
        }
    end
    table.sort(rows, function(a, b) return a.level < b.level end)
    local _, configuredMax = getInbuiltGangLabelAndMax(gangName)
    local maxLevel = configuredMax
    if not maxLevel then
        maxLevel = rows[#rows].level or 0
    end
    for i = 1, #rows do
        if rows[i].level == maxLevel then
            rows[i].isBoss = true
        end
    end
    return rows
end

local function getCustomRanks(menuType, roleName)
    local key = customRankCacheKey(menuType, roleName)
    local cached = CustomRankCache[key]
    if cached and nowMs() < cached.expiresAt then
        return cached.rows
    end

    local rows = {}
    if isModuleEnabled('DynamicRanks') then
        rows = MySQL.query.await([[SELECT grade, rank_name, rank_icon, rank_style, salary_type, salary_amount, description, protected_rank
            FROM bossmenu_custom_ranks
            WHERE org_type = ? AND org_name = ?
            ORDER BY grade ASC]], {
            getOrgTypeByMenu(menuType),
            roleName
        }) or {}
    end

    CustomRankCache[key] = {
        rows = rows,
        expiresAt = nowMs() + 3000
    }
    return rows
end

local function applyCustomRanks(menuType, roleName, grades)
    if not isModuleEnabled('DynamicRanks') then
        return grades
    end

    local merged = {}
    local index = {}
    for _, base in ipairs(grades) do
        local row = {
            level = tonumber(base.level) or 0,
            name = tostring(base.name or 'Member'),
            isBoss = base.isBoss == true,
            style = type(base.style) == 'table' and base.style or nil,
            icon = base.icon,
            salaryType = base.salaryType,
            salaryAmount = base.salaryAmount,
            description = base.description,
            protected = base.protected == true,
            custom = base.custom == true
        }
        merged[#merged + 1] = row
        index[row.level] = row
    end

    local customRows = getCustomRanks(menuType, roleName)
    for _, raw in ipairs(customRows) do
        local level = tonumber(raw.grade)
        if level then
            local rank = index[level]
            local style = decodeJson(raw.rank_style)
            if rank then
                rank.name = tostring(raw.rank_name or rank.name)
                rank.icon = cleanText(raw.rank_icon, 64)
                rank.style = mergeStyle(rank.style, style)
                rank.salaryType = cleanText(raw.salary_type, 24)
                rank.salaryAmount = tonumber(raw.salary_amount) or 0
                rank.description = cleanText(raw.description, 512)
                rank.protected = tonumber(raw.protected_rank) == 1
                rank.custom = true
            else
                rank = {
                    level = level,
                    name = tostring(raw.rank_name or ('Grade ' .. level)),
                    isBoss = false,
                    style = type(style) == 'table' and style or nil,
                    icon = cleanText(raw.rank_icon, 64),
                    salaryType = cleanText(raw.salary_type, 24),
                    salaryAmount = tonumber(raw.salary_amount) or 0,
                    description = cleanText(raw.description, 512),
                    protected = tonumber(raw.protected_rank) == 1,
                    custom = true
                }
                merged[#merged + 1] = rank
                index[level] = rank
            end
        end
    end

    table.sort(merged, function(a, b) return a.level < b.level end)
    local maxLevel = merged[#merged] and merged[#merged].level or 0
    local hasBoss = false
    for i = 1, #merged do
        if merged[i].isBoss == true then
            hasBoss = true
            break
        end
    end
    if not hasBoss then
        for i = 1, #merged do
            merged[i].isBoss = merged[i].level == maxLevel
        end
    end

    return merged
end

local function getKnownPermissionMap(menuType)
    return GetKnownPermissions(getOrgTypeByMenu(menuType)) or {}
end

local function getGradePermissionMap(menuType, roleName, grade)
    local key = permissionCacheKey(menuType, roleName, grade)
    local cached = PermissionCache[key]
    if cached and nowMs() < cached.expiresAt then
        return cached.map
    end

    local known = getKnownPermissionMap(menuType)
    local strictMode = Config.Security and Config.Security.strictPermissionMode == true
    local map = {}
    for permissionKey in pairs(known) do
        map[permissionKey] = strictMode and false or true
    end

    if isModuleEnabled('RankPermissions') then
        local rows = MySQL.query.await([[SELECT permission_key, allowed
            FROM bossmenu_rank_permissions
            WHERE org_type = ? AND org_name = ? AND grade = ?]], {
            getOrgTypeByMenu(menuType),
            roleName,
            tonumber(grade) or 0
        }) or {}

        if #rows == 0 then
            for permissionKey in pairs(known) do
                map[permissionKey] = true
            end
        else
            for _, row in ipairs(rows) do
                local permissionKey = tostring(row.permission_key or '')
                if known[permissionKey] ~= nil then
                    map[permissionKey] = tonumber(row.allowed) == 1
                end
            end
        end
    else
        for permissionKey in pairs(known) do
            map[permissionKey] = true
        end
    end

    PermissionCache[key] = {
        map = map,
        expiresAt = nowMs() + 2000
    }

    return map
end

hasContextPermission = function(context, permissionKey)
    if not context or type(permissionKey) ~= 'string' or permissionKey == '' then
        return false
    end

    local known = getKnownPermissionMap(context.menuType)
    if known[permissionKey] == nil then
        return Config.Security and Config.Security.strictPermissionMode ~= true
    end

    local map = getGradePermissionMap(context.menuType, context.role.name, context.role.grade or 0)
    return map[permissionKey] == true
end

local function getRoleGrades(menuType, roleName)
    local key = gradeCacheKey(menuType, roleName)
    if GradeCache[key] then return GradeCache[key] end

    local grades = {}
    if menuType == 'gang' then
        if usingCustomGangBackend() then
            grades = customGangGrades(roleName)
        elseif frameworkName == 'qb' then
            local data = QBCore and QBCore.Shared and QBCore.Shared.Gangs and QBCore.Shared.Gangs[roleName]
            if data and data.grades then
                for k, v in pairs(data.grades) do
                    local level = tonumber(k) or tonumber(v.level) or 0
                    grades[#grades + 1] = { level = level, name = v.name or ('Grade ' .. level), isBoss = v.isboss == true, style = nil }
                end
            end
        elseif frameworkName == 'qbox' then
            local ok, data = pcall(function()
                return exports.qbx_core:GetGang(roleName)
            end)
            if ok and data and data.grades then
                for k, v in pairs(data.grades) do
                    local level = tonumber(k) or tonumber(v.level) or 0
                    grades[#grades + 1] = { level = level, name = v.name or ('Grade ' .. level), isBoss = v.isboss == true or v.isBoss == true, style = nil }
                end
            end
        end
    else
        if frameworkName == 'qb' then
            local data = QBCore and QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[roleName]
            if data and data.grades then
                for k, v in pairs(data.grades) do
                    local level = tonumber(k) or tonumber(v.level) or 0
                    grades[#grades + 1] = { level = level, name = v.name or ('Grade ' .. level), isBoss = v.isboss == true, style = nil }
                end
            end
        elseif frameworkName == 'qbox' then
            local ok, data = pcall(function()
                return exports.qbx_core:GetJob(roleName)
            end)
            if ok and data and data.grades then
                for k, v in pairs(data.grades) do
                    local level = tonumber(k) or tonumber(v.level) or 0
                    grades[#grades + 1] = { level = level, name = v.name or ('Grade ' .. level), isBoss = v.isboss == true or v.isBoss == true, style = nil }
                end
            end
        elseif frameworkName == 'esx' then
            local rows = MySQL.query.await('SELECT grade, label, name FROM job_grades WHERE job_name = ? ORDER BY grade ASC', { roleName }) or {}
            for _, row in ipairs(rows) do
                grades[#grades + 1] = {
                    level = tonumber(row.grade) or 0,
                    name = row.label or row.name or ('Grade ' .. tostring(row.grade)),
                    isBoss = tostring(row.name or ''):lower() == 'boss',
                    style = nil
                }
            end
        elseif frameworkName == 'ox' then
            local ok, group = pcall(function()
                return Ox.GetGroup(roleName)
            end)
            if ok and group and group.grades then
                for k, v in pairs(group.grades) do
                    local level = tonumber(k) or tonumber(v.id) or 0
                    grades[#grades + 1] = { level = level, name = v.label or v.name or ('Grade ' .. level), isBoss = false, style = nil }
                end
            end
        end
    end

    if #grades == 0 then
        grades[1] = { level = 0, name = 'Member', isBoss = false, style = nil }
    end
    table.sort(grades, function(a, b) return a.level < b.level end)
    local maxLevel = grades[#grades].level or 0
    for i = 1, #grades do
        if grades[i].level == maxLevel then
            grades[i].isBoss = true
        end
    end

    grades = applyCustomRanks(menuType, roleName, grades)
    GradeCache[key] = grades
    return grades
end

local function getGradeMeta(menuType, roleName, level)
    local grades = getRoleGrades(menuType, roleName)
    for _, g in ipairs(grades) do
        if g.level == tonumber(level) then
            return g
        end
    end
    return {
        level = tonumber(level) or 0,
        name = 'Grade ' .. tostring(level),
        isBoss = false
    }
end

local function buildEmployeeRow(menuType, roleName, identifier, name, level, online, source)
    local grade = getGradeMeta(menuType, roleName, level)
    return {
        identifier = tostring(identifier),
        name = cleanText(name, 80),
        online = online == true,
        source = source,
        grade = grade,
        isBoss = grade.isBoss == true
    }
end

local function qbLikeRoleColumn(menuType)
    return menuType == 'gang' and 'gangJsonColumn' or 'jobJsonColumn'
end

local function fetchOfflineQbLike(menuType, roleName, onlineMap)
    local db = frameworkName == 'qbox' and Config.Database.qbox or Config.Database.qb
    local jsonColumn = db[qbLikeRoleColumn(menuType)]
    if not jsonColumn then return {} end

    local query = ([[SELECT %s AS identifier, %s AS charinfo, %s AS roledata
        FROM %s
        WHERE JSON_UNQUOTE(JSON_EXTRACT(%s, '$.name')) = ?]]):format(
        db.identifierColumn, db.charinfoColumn, jsonColumn, db.playerTable, jsonColumn
    )
    local rows = MySQL.query.await(query, { roleName }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local identifier = tostring(row.identifier)
        if not onlineMap[identifier] then
            local charinfo = decodeJson(row.charinfo) or {}
            local role = decodeJson(row.roledata) or {}
            local gradeRaw = role.grade and (role.grade.level or role.grade) or 0
            local level = tonumber(gradeRaw) or 0
            local fullname = ((charinfo.firstname or 'Unknown') .. ' ' .. (charinfo.lastname or '')):gsub('%s+$', '')
            out[#out + 1] = buildEmployeeRow(menuType, roleName, identifier, fullname, level, false, nil)
        end
    end
    return out
end

local function fetchOfflineCustomGang(roleName, onlineMap)
    local rows = MySQL.query.await([[SELECT gm.identifier, gm.grade, p.charinfo
        FROM bossmenu_gang_members gm
        LEFT JOIN players p ON p.citizenid = gm.identifier
        WHERE gm.gang_name = ?]], { roleName }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local identifier = tostring(row.identifier)
        if not onlineMap[identifier] then
            local charinfo = decodeJson(row.charinfo) or {}
            local fullname = ((charinfo.firstname or 'Unknown') .. ' ' .. (charinfo.lastname or '')):gsub('%s+$', '')
            out[#out + 1] = buildEmployeeRow('gang', roleName, identifier, fullname, tonumber(row.grade) or 0, false, nil)
        end
    end
    return out
end

local function fetchOfflineEsx(roleName, onlineMap)
    local db = Config.Database.esx
    local query = ([[SELECT %s AS identifier, %s AS firstname, %s AS lastname, %s AS grade
        FROM %s
        WHERE %s = ?]]):format(
        db.identifierColumn, db.firstnameColumn, db.lastnameColumn, db.gradeColumn, db.playerTable, db.jobColumn
    )
    local rows = MySQL.query.await(query, { roleName }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local identifier = tostring(row.identifier)
        if not onlineMap[identifier] then
            local fullname = ((row.firstname or 'Unknown') .. ' ' .. (row.lastname or '')):gsub('%s+$', '')
            out[#out + 1] = buildEmployeeRow('boss', roleName, identifier, fullname, tonumber(row.grade) or 0, false, nil)
        end
    end
    return out
end

local function fetchOfflineOx(roleName, onlineMap)
    local db = Config.Database.ox
    local query = ([[SELECT %s AS identifier, %s AS firstname, %s AS lastname,
        COALESCE(JSON_EXTRACT(%s, '$."%s"'), 0) AS grade
        FROM %s
        WHERE JSON_EXTRACT(%s, '$."%s"') IS NOT NULL]]):format(
        db.identifierColumn, db.firstnameColumn, db.lastnameColumn,
        db.groupsColumn, roleName, db.playerTable, db.groupsColumn, roleName
    )
    local rows = MySQL.query.await(query, {}) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local identifier = tostring(row.identifier)
        if not onlineMap[identifier] then
            local level = tonumber(row.grade) or tonumber(tostring(row.grade):gsub('"', '')) or 0
            local fullname = ((row.firstname or 'Unknown') .. ' ' .. (row.lastname or '')):gsub('%s+$', '')
            out[#out + 1] = buildEmployeeRow('boss', roleName, identifier, fullname, level, false, nil)
        end
    end
    return out
end

local function getEmployeesForRole(menuType, roleName)
    local cacheKey = ('%s:%s'):format(menuType, roleName)
    local cached = EmployeeCache[cacheKey]
    local ttl = tonumber(Config.Performance and Config.Performance.employeeCacheMs or 4000) or 4000
    if cached and nowMs() < cached.expiresAt then
        return cached.rows
    end

    local rows = {}
    local onlineMap = {}
    for _, src in ipairs(getOnlinePlayers()) do
        local player = getPlayerState(src)
        if player then
            local role = roleFromMenu(player, menuType)
            if role and role.name == roleName then
                rows[#rows + 1] = buildEmployeeRow(menuType, roleName, player.identifier, player.name, role.grade or 0, true, src)
                onlineMap[tostring(player.identifier)] = true
            end
        end
    end

    local offline = {}
    if menuType == 'gang' and usingCustomGangBackend() then
        offline = fetchOfflineCustomGang(roleName, onlineMap)
    elseif frameworkName == 'qb' or frameworkName == 'qbox' then
        offline = fetchOfflineQbLike(menuType, roleName, onlineMap)
    elseif frameworkName == 'esx' and menuType == 'boss' then
        offline = fetchOfflineEsx(roleName, onlineMap)
    elseif frameworkName == 'ox' and menuType == 'boss' then
        offline = fetchOfflineOx(roleName, onlineMap)
    end

    for _, row in ipairs(offline) do
        rows[#rows + 1] = row
    end

    table.sort(rows, function(a, b)
        if a.online ~= b.online then
            return a.online
        end
        if a.grade.level ~= b.grade.level then
            return a.grade.level > b.grade.level
        end
        return (a.name or '') < (b.name or '')
    end)

    EmployeeCache[cacheKey] = {
        rows = rows,
        expiresAt = nowMs() + ttl
    }
    return rows
end

local function getRoleMemberIdentifiersByGrade(menuType, roleName, grade)
    grade = tonumber(grade) or 0

    if menuType == 'gang' and usingCustomGangBackend() then
        local rows = MySQL.query.await('SELECT identifier FROM bossmenu_gang_members WHERE gang_name = ? AND grade = ?', { roleName, grade }) or {}
        local out = {}
        for _, row in ipairs(rows) do
            out[#out + 1] = tostring(row.identifier)
        end
        return out
    end

    if frameworkName == 'qb' or frameworkName == 'qbox' then
        local db = frameworkName == 'qbox' and Config.Database.qbox or Config.Database.qb
        local jsonColumn = db[qbLikeRoleColumn(menuType)]
        if not jsonColumn then return {} end
        local query = ([[SELECT %s AS identifier
            FROM %s
            WHERE JSON_UNQUOTE(JSON_EXTRACT(%s, '$.name')) = ?
            AND CAST(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(%s, '$.grade.level'), JSON_EXTRACT(%s, '$.grade'))) AS SIGNED) = ?]]):format(
            db.identifierColumn, db.playerTable, jsonColumn, jsonColumn, jsonColumn
        )
        local rows = MySQL.query.await(query, { roleName, grade }) or {}
        local out = {}
        for _, row in ipairs(rows) do
            out[#out + 1] = tostring(row.identifier)
        end
        return out
    end

    if frameworkName == 'esx' and menuType == 'boss' then
        local db = Config.Database.esx
        local query = ([[SELECT %s AS identifier FROM %s WHERE %s = ? AND %s = ?]]):format(
            db.identifierColumn, db.playerTable, db.jobColumn, db.gradeColumn
        )
        local rows = MySQL.query.await(query, { roleName, grade }) or {}
        local out = {}
        for _, row in ipairs(rows) do
            out[#out + 1] = tostring(row.identifier)
        end
        return out
    end

    if frameworkName == 'ox' and menuType == 'boss' then
        local db = Config.Database.ox
        local query = ([[SELECT %s AS identifier FROM %s
            WHERE CAST(JSON_UNQUOTE(JSON_EXTRACT(%s, '$."%s"')) AS SIGNED) = ?]]):format(
            db.identifierColumn, db.playerTable, db.groupsColumn, roleName
        )
        local rows = MySQL.query.await(query, { grade }) or {}
        local out = {}
        for _, row in ipairs(rows) do
            out[#out + 1] = tostring(row.identifier)
        end
        return out
    end

    return {}
end

local function getRoleMemberCountByGrade(menuType, roleName, grade)
    local identifiers = getRoleMemberIdentifiersByGrade(menuType, roleName, grade)
    return #identifiers
end

local function getNearbyPlayers(src)
    local out = {}
    local ped = GetPlayerPed(src)
    if ped == 0 then return out end
    local pos = GetEntityCoords(ped)
    local range = tonumber(Config.Performance and Config.Performance.nearbyRange or 10.0) or 10.0

    for _, targetSrc in ipairs(getOnlinePlayers()) do
        if targetSrc ~= src then
            local tPed = GetPlayerPed(targetSrc)
            if tPed ~= 0 then
                local dist = #(pos - GetEntityCoords(tPed))
                if dist <= range then
                    local target = getPlayerState(targetSrc)
                    if target then
                        out[#out + 1] = {
                            source = targetSrc,
                            identifier = target.identifier,
                            name = target.name,
                            distance = math.floor(dist * 100) / 100
                        }
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return a.distance < b.distance
    end)
    return out
end

local function syncCustomGangToClientBySource(src)
    if not usingCustomGangBackend() then return end
    local player = getPlayerState(src)
    if not player then return end
    TriggerClientEvent('qb-management:client:syncGangRole', src, player.gang)
end

local function syncCustomGangToClientByIdentifier(identifier)
    if not usingCustomGangBackend() then return end
    for _, src in ipairs(getOnlinePlayers()) do
        local state = getPlayerState(src)
        if state and state.identifier == identifier then
            TriggerClientEvent('qb-management:client:syncGangRole', src, state.gang)
            break
        end
    end
end

local function upsertCustomGangMember(identifier, gangName, grade)
    MySQL.insert.await([[INSERT INTO bossmenu_gang_members (gang_name, identifier, grade)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE gang_name = VALUES(gang_name), grade = VALUES(grade)]], {
        gangName, identifier, grade
    })
    invalidateCustomGang(identifier)
    syncCustomGangToClientByIdentifier(identifier)
end

local function removeCustomGangMember(identifier)
    MySQL.update.await('DELETE FROM bossmenu_gang_members WHERE identifier = ?', { identifier })
    invalidateCustomGang(identifier)
    syncCustomGangToClientByIdentifier(identifier)
end

local function setRoleForIdentifier(menuType, identifier, roleName, grade)
    if menuType == 'gang' then
        if usingCustomGangBackend() then
            upsertCustomGangMember(identifier, roleName, grade)
            return true
        end

        if frameworkName == 'qb' then
            local online = QBCore.Functions.GetPlayerByCitizenId(identifier)
            if online then
                local ok = online.Functions.SetGang(roleName, grade)
                if ok then online.Functions.Save() end
                return ok == true
            end
            local offline = QBCore.Functions.GetOfflinePlayerByCitizenId(identifier)
            if offline then
                local ok = offline.Functions.SetGang(roleName, grade)
                if ok then offline.Functions.Save() end
                return ok == true
            end
            return false
        end

        if frameworkName == 'qbox' then
            return exports.qbx_core:SetGang(identifier, roleName, grade) == true
        end

        return false
    end

    if frameworkName == 'qb' then
        local online = QBCore.Functions.GetPlayerByCitizenId(identifier)
        if online then
            local ok = online.Functions.SetJob(roleName, grade)
            if ok then online.Functions.Save() end
            return ok == true
        end
        local offline = QBCore.Functions.GetOfflinePlayerByCitizenId(identifier)
        if offline then
            local ok = offline.Functions.SetJob(roleName, grade)
            if ok then offline.Functions.Save() end
            return ok == true
        end
        return false
    end

    if frameworkName == 'qbox' then
        return exports.qbx_core:SetJob(identifier, roleName, grade) == true
    end

    if frameworkName == 'esx' then
        local online = ESX.GetPlayerFromIdentifier(identifier)
        if online then
            online.setJob(roleName, grade)
            return true
        end
        local db = Config.Database.esx
        local affected = MySQL.update.await(([[UPDATE %s SET %s = ?, %s = ? WHERE %s = ?]]):format(
            db.playerTable, db.jobColumn, db.gradeColumn, db.identifierColumn
        ), { roleName, grade, identifier })
        return (affected or 0) > 0
    end

    if frameworkName == 'ox' then
        local source = exports.ox_core.GetSource and exports.ox_core:GetSource(identifier) or 0
        local player = source > 0 and getOxPlayer(source) or nil
        if player then
            local ok = player.setGroup(roleName, grade)
            if ok and player.setActiveGroup then
                player.setActiveGroup(roleName)
            end
            return ok == true
        end
        local db = Config.Database.ox
        local affected = MySQL.update.await(([[UPDATE %s
            SET %s = JSON_SET(COALESCE(%s, JSON_OBJECT()), '$."%s"', ?)
            WHERE %s = ?]]):format(
            db.playerTable, db.groupsColumn, db.groupsColumn, roleName, db.identifierColumn
        ), { grade, identifier })
        return (affected or 0) > 0
    end

    return false
end

local function removeRoleForIdentifier(menuType, identifier, roleName)
    if menuType == 'gang' then
        if usingCustomGangBackend() then
            removeCustomGangMember(identifier)
            return true
        end

        if frameworkName == 'qb' then
            return setRoleForIdentifier('gang', identifier, Config.Society.noGangName or 'none', 0)
        end
        if frameworkName == 'qbox' then
            return exports.qbx_core:RemovePlayerFromGang(identifier, roleName) == true
        end
        return false
    end

    if frameworkName == 'qb' then
        return setRoleForIdentifier('boss', identifier, Config.Society.unemployedName or 'unemployed', 0)
    end
    if frameworkName == 'qbox' then
        return exports.qbx_core:SetJob(identifier, Config.Society.unemployedName or 'unemployed', 0) == true
    end
    if frameworkName == 'esx' then
        return setRoleForIdentifier('boss', identifier, Config.Society.unemployedName or 'unemployed', 0)
    end
    if frameworkName == 'ox' then
        local source = exports.ox_core.GetSource and exports.ox_core:GetSource(identifier) or 0
        local player = source > 0 and getOxPlayer(source) or nil
        if player then
            return player.setGroup(roleName, 0) == true
        end
        local db = Config.Database.ox
        local affected = MySQL.update.await(([[UPDATE %s
            SET %s = JSON_REMOVE(COALESCE(%s, JSON_OBJECT()), '$."%s"')
            WHERE %s = ?]]):format(
            db.playerTable, db.groupsColumn, db.groupsColumn, roleName, db.identifierColumn
        ), { identifier })
        return (affected or 0) > 0
    end
    return false
end

local function removeCash(player, amount)
    if frameworkName == 'qb' then
        return player.raw.Functions.RemoveMoney('cash', amount, 'management_deposit') == true
    end
    if frameworkName == 'qbox' then
        return exports.qbx_core:RemoveMoney(player.identifier, 'cash', amount, 'management_deposit') == true
    end
    if frameworkName == 'esx' then
        if player.raw.getMoney() < amount then return false end
        player.raw.removeMoney(amount)
        return true
    end
    if frameworkName == 'ox' then
        local account = player.raw.getAccount and player.raw.getAccount()
        if not account then return false end
        return account.removeBalance(amount) == true
    end
    return false
end

local function addCash(player, amount)
    if frameworkName == 'qb' then
        player.raw.Functions.AddMoney('cash', amount, 'management_withdraw')
        return true
    end
    if frameworkName == 'qbox' then
        return exports.qbx_core:AddMoney(player.identifier, 'cash', amount, 'management_withdraw') == true
    end
    if frameworkName == 'esx' then
        player.raw.addMoney(amount)
        return true
    end
    if frameworkName == 'ox' then
        local account = player.raw.getAccount and player.raw.getAccount()
        if not account then return false end
        return account.addBalance(amount) == true
    end
    return false
end

local function getLedger(roleName)
    return MySQL.query.await([[SELECT id, action, amount, actor_identifier, target_identifier, note, created_at
        FROM bossmenu_ledger WHERE job = ? ORDER BY id DESC LIMIT 100]], { roleName }) or {}
end

local function buildOpenPayload(context)
    local menuType = context.menuType
    local role = context.role
    local grades = getRoleGrades(menuType, role.name)
    local orgProfile = inferOrgProfile(menuType, role.name, role.label, grades)
    local cameraProvider = resolveCameraProvider(context, orgProfile and orgProfile.id or 'corporate')
    local cameraFeeds = resolveCameraFeeds(context, orgProfile and orgProfile.id or 'corporate')
    local stashBackend = getStashIntegration()
    local stashAllowed = canUseOrgStash(context) and stashBackend ~= 'none'
    local groupStyle = nil
    if menuType == 'gang' and usingCustomGangBackend() then
        local def = getInbuiltGangDefinition(role.name)
        if def and type(def.style) == 'table' then
            groupStyle = def.style
        end
    end

    return {
        framework = frameworkName,
        menuType = menuType,
        groupName = role.name,
        groupStyle = groupStyle,
        orgProfile = orgProfile,
        hasFinance = financeAllowed(menuType),
        modules = Config.Modules or {},
        integrations = Config.Integrations or {},
        locale = LocaleNui and LocaleNui() or {},
        job = {
            name = role.name,
            label = role.label,
            grade = role.grade,
            isBoss = role.isBoss,
            icon = roleIcon(menuType, role.name)
        },
        settings = {
            maxAmount = maxMoneyAmount(),
            cameraProvider = cameraProvider,
            cameraFeedCount = #cameraFeeds,
            cameraCloseMenuOnOpen = getCameraConfig().closeMenuOnOpen == true,
            stashAvailable = stashAllowed,
            stashIntegration = stashBackend
        },
        grades = grades,
        permissions = getGradePermissionMap(menuType, role.name, role.grade or 0),
        balance = financeAllowed(menuType) and getBalance(role.name) or 0,
        ledger = financeAllowed(menuType) and getLedger(role.name) or {}
    }
end

local function getMemberGrade(context, identifier)
    local employees = getEmployeesForRole(context.menuType, context.role.name)
    for _, row in ipairs(employees) do
        if row.identifier == identifier then
            return tonumber(row.grade and row.grade.level) or 0
        end
    end
    return nil
end

local function getMemberRowByIdentifier(context, identifier)
    if not context or not identifier or identifier == '' then
        return nil
    end
    local employees = getEmployeesForRole(context.menuType, context.role.name)
    for i = 1, #employees do
        local row = employees[i]
        if tostring(row.identifier) == tostring(identifier) then
            return row
        end
    end
    return nil
end

local function genderLabel(value)
    local raw = tostring(value or ''):lower()
    if raw == '0' or raw == 'm' or raw == 'male' then return 'Male' end
    if raw == '1' or raw == 'f' or raw == 'female' then return 'Female' end
    if raw ~= '' then
        return raw:gsub('^%l', string.upper)
    end
    return 'Unknown'
end

local function getOnlineStateByIdentifier(identifier)
    local id = tostring(identifier or '')
    if id == '' then return nil end
    for _, src in ipairs(getOnlinePlayers()) do
        local state = getPlayerState(src)
        if state and tostring(state.identifier or '') == id then
            return state
        end
    end
    return nil
end

local function getFrameworkCharacterDetails(identifier, onlineState)
    local out = {
        framework = frameworkName,
        identifier = tostring(identifier or ''),
        source = nil,
        ping = nil,
        firstName = nil,
        lastName = nil,
        fullName = nil,
        dateOfBirth = nil,
        gender = nil,
        nationality = nil,
        phone = nil,
        license = nil,
        jobName = nil,
        jobLabel = nil,
        jobGrade = nil,
        jobGradeLabel = nil,
        gangName = nil,
        gangLabel = nil,
        gangGrade = nil,
        gangGradeLabel = nil,
        metadata = {}
    }

    if frameworkName == 'qb' or frameworkName == 'qbox' then
        if onlineState and onlineState.raw and onlineState.raw.PlayerData then
            local pd = onlineState.raw.PlayerData
            local ch = type(pd.charinfo) == 'table' and pd.charinfo or {}
            local job = type(pd.job) == 'table' and pd.job or {}
            local gang = type(pd.gang) == 'table' and pd.gang or {}
            local jobGrade = type(job.grade) == 'table' and (job.grade.level or 0) or (job.grade or 0)
            local gangGrade = type(gang.grade) == 'table' and (gang.grade.level or 0) or (gang.grade or 0)
            out.source = tonumber(onlineState.source) or nil
            out.ping = out.source and GetPlayerPing(out.source) or nil
            out.firstName = ch.firstname
            out.lastName = ch.lastname
            out.fullName = cleanText((tostring(ch.firstname or '') .. ' ' .. tostring(ch.lastname or '')), 80)
            out.dateOfBirth = ch.birthdate or ch.dob
            out.gender = genderLabel(ch.gender)
            out.nationality = ch.nationality
            out.phone = ch.phone
            out.license = pd.license
            out.jobName = job.name
            out.jobLabel = job.label or job.name
            out.jobGrade = tonumber(jobGrade) or 0
            out.jobGradeLabel = type(job.grade) == 'table' and job.grade.name or tostring(jobGrade)
            out.gangName = gang.name
            out.gangLabel = gang.label or gang.name
            out.gangGrade = tonumber(gangGrade) or 0
            out.gangGradeLabel = type(gang.grade) == 'table' and gang.grade.name or tostring(gangGrade)
            out.metadata = type(pd.metadata) == 'table' and pd.metadata or {}
            return out
        end

        local db = frameworkName == 'qbox' and Config.Database.qbox or Config.Database.qb
        local query = ([[SELECT %s AS identifier, %s AS charinfo, %s AS job, %s AS gang
            FROM %s
            WHERE %s = ?
            LIMIT 1]]):format(
            db.identifierColumn, db.charinfoColumn, db.jobJsonColumn, db.gangJsonColumn,
            db.playerTable, db.identifierColumn
        )
        local row = MySQL.single.await(query, { identifier })
        if row then
            local ch = decodeJson(row.charinfo) or {}
            local job = decodeJson(row.job) or {}
            local gang = decodeJson(row.gang) or {}
            local jobGrade = job.grade and (job.grade.level or job.grade) or 0
            local gangGrade = gang.grade and (gang.grade.level or gang.grade) or 0
            out.firstName = ch.firstname
            out.lastName = ch.lastname
            out.fullName = cleanText((tostring(ch.firstname or '') .. ' ' .. tostring(ch.lastname or '')), 80)
            out.dateOfBirth = ch.birthdate or ch.dob
            out.gender = genderLabel(ch.gender)
            out.nationality = ch.nationality
            out.phone = ch.phone
            out.jobName = job.name
            out.jobLabel = job.label or job.name
            out.jobGrade = tonumber(jobGrade) or 0
            out.jobGradeLabel = type(job.grade) == 'table' and job.grade.name or tostring(jobGrade or 0)
            out.gangName = gang.name
            out.gangLabel = gang.label or gang.name
            out.gangGrade = tonumber(gangGrade) or 0
            out.gangGradeLabel = type(gang.grade) == 'table' and gang.grade.name or tostring(gangGrade or 0)
        end
        return out
    end

    if frameworkName == 'esx' then
        if onlineState and onlineState.raw then
            local xp = onlineState.raw
            local pd = type(xp) == 'table' and xp or {}
            local job = pd.job or {}
            out.source = tonumber(onlineState.source) or nil
            out.ping = out.source and GetPlayerPing(out.source) or nil
            out.firstName = pd.firstName
            out.lastName = pd.lastName
            out.fullName = cleanText((tostring(pd.firstName or '') .. ' ' .. tostring(pd.lastName or '')), 80)
            out.dateOfBirth = pd.dateofbirth
            out.gender = genderLabel(pd.sex)
            out.phone = pd.phone_number
            out.license = pd.license
            out.jobName = job.name
            out.jobLabel = job.label or job.name
            out.jobGrade = tonumber(job.grade) or 0
            out.jobGradeLabel = job.grade_label or job.grade_name or tostring(out.jobGrade)
            if xp.getMeta then
                out.metadata = xp.getMeta() or {}
            end
            return out
        end

        local db = Config.Database.esx
        local query = ([[SELECT %s AS identifier, %s AS firstname, %s AS lastname, %s AS job, %s AS grade
            FROM %s
            WHERE %s = ?
            LIMIT 1]]):format(
            db.identifierColumn, db.firstnameColumn, db.lastnameColumn, db.jobColumn, db.gradeColumn,
            db.playerTable, db.identifierColumn
        )
        local row = MySQL.single.await(query, { identifier })
        if row then
            out.firstName = row.firstname
            out.lastName = row.lastname
            out.fullName = cleanText((tostring(row.firstname or '') .. ' ' .. tostring(row.lastname or '')), 80)
            out.jobName = row.job
            out.jobLabel = row.job
            out.jobGrade = tonumber(row.grade) or 0
            out.jobGradeLabel = tostring(row.grade or 0)
        end
        return out
    end

    if frameworkName == 'ox' then
        if onlineState and onlineState.raw then
            local player = onlineState.raw
            local first = player.get and player.get('firstName') or nil
            local last = player.get and player.get('lastName') or nil
            local groupName, groupGrade = nil, nil
            if player.getGroupByType then
                groupName, groupGrade = player.getGroupByType('job')
            end
            out.source = tonumber(onlineState.source) or nil
            out.ping = out.source and GetPlayerPing(out.source) or nil
            out.firstName = first
            out.lastName = last
            out.fullName = cleanText((tostring(first or '') .. ' ' .. tostring(last or '')), 80)
            out.jobName = groupName
            out.jobLabel = groupName
            out.jobGrade = tonumber(groupGrade) or 0
            out.jobGradeLabel = tostring(out.jobGrade)
            out.metadata = {
                stateId = player.stateId,
                charId = player.charId
            }
            return out
        end

        local db = Config.Database.ox
        local query = ([[SELECT %s AS identifier, %s AS firstname, %s AS lastname
            FROM %s
            WHERE %s = ?
            LIMIT 1]]):format(
            db.identifierColumn, db.firstnameColumn, db.lastnameColumn,
            db.playerTable, db.identifierColumn
        )
        local row = MySQL.single.await(query, { identifier })
        if row then
            out.firstName = row.firstname
            out.lastName = row.lastname
            out.fullName = cleanText((tostring(row.firstname or '') .. ' ' .. tostring(row.lastname or '')), 80)
        end
    end

    return out
end

local function getContextFromPlayer(src, menuType)
    local player = getPlayerState(src)
    if not player then
        return nil, 'Player unavailable'
    end
    if menuType == 'gang' and Config.EnableGangMenu ~= true then
        return nil, 'Gang menu disabled'
    end
    local role = roleFromMenu(player, menuType)
    if not role or not role.name then
        return nil, 'No valid role'
    end
    local orgType = getOrgTypeByMenu(menuType)
    local state = getOrgState(orgType, role.name)
    if state.disabled then
        return nil, 'Organization disabled'
    end
    if not hasRoleAccess(player, menuType) then
        return nil, 'Not authorized'
    end
    local context = {
        player = player,
        menuType = menuType,
        role = role
    }
    if not hasContextPermission(context, 'open_menu') then
        return nil, 'No permission'
    end
    return context, nil
end

local function getContextFromSession(src, token)
    local session = verifySession(src, tostring(token or ''))
    if not session then
        return nil, 'Invalid session'
    end
    local context, err = getContextFromPlayer(src, session.menuType)
    if not context then
        return nil, err
    end
    if context.role.name ~= session.roleName then
        return nil, 'Role changed, reopen menu'
    end
    context.session = session
    return context, nil
end

local function actionRefresh(context, src)
    local listPermission = context.menuType == 'gang' and 'view_members' or 'view_employees'
    if not hasContextPermission(context, listPermission) then
        return false, 'No permission'
    end

    clearEmployeeCache(context.menuType, context.role.name)
    local canViewFinance = financeAllowed(context.menuType) and hasContextPermission(context, 'view_finance')
    local canViewLedger = financeAllowed(context.menuType) and hasContextPermission(context, 'view_ledger')
    return true, {
        balance = canViewFinance and getBalance(context.role.name) or 0,
        grades = getRoleGrades(context.menuType, context.role.name),
        permissions = getGradePermissionMap(context.menuType, context.role.name, context.role.grade or 0),
        employees = getEmployeesForRole(context.menuType, context.role.name),
        nearby = getNearbyPlayers(src),
        ledger = canViewLedger and getLedger(context.role.name) or {}
    }
end

local function actionHire(context, payload, src)
    local permission = context.menuType == 'gang' and 'invite_member' or 'hire_employee'
    if not hasContextPermission(context, permission) then
        return false, 'No permission'
    end

    local targetSrc = safeNumber(payload and payload.source, 1)
    if not targetSrc then return false, 'Invalid target' end
    local target = getPlayerState(targetSrc)
    if not target then return false, 'Target not found' end
    local maxHireDistance = tonumber(Config.Security and Config.Security.maxHireDistance or 10.0) or 10.0
    local actorPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if actorPed ~= 0 and targetPed ~= 0 then
        local distance = #(GetEntityCoords(actorPed) - GetEntityCoords(targetPed))
        if distance > maxHireDistance then
            return false, 'Target too far away'
        end
    end

    local ok = setRoleForIdentifier(context.menuType, target.identifier, context.role.name, 0)
    if not ok then return false, 'Could not hire target' end

    clearEmployeeCache(context.menuType, context.role.name)
    local hookName = context.menuType == 'gang' and 'gang_member_hired' or 'employee_hired'
    local payloadHook = {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        target = target.identifier
    }
    emitHook(hookName, payloadHook)
    if context.menuType == 'gang' then
        emitHook('OnGangMemberHired', payloadHook)
    else
        emitHook('OnEmployeeHired', payloadHook)
    end
    addAudit(context.role.name, context.menuType .. '_hire', context.player.identifier, target.identifier, { source = src })
    notify(src, ('Hired %s'):format(target.name), 'success')
    notify(target.source, ('You joined %s'):format(context.role.label or context.role.name), 'success')
    return true, {
        grades = getRoleGrades(context.menuType, context.role.name),
        employees = getEmployeesForRole(context.menuType, context.role.name),
        nearby = getNearbyPlayers(src)
    }
end

local function actionSetGrade(context, payload)
    local editPermission = 'promote_employee'
    local downPermission = 'demote_employee'
    if context.menuType == 'gang' then
        editPermission = 'promote_member'
        downPermission = 'demote_member'
    end

    local identifier = cleanText(payload and payload.identifier, 80)
    local grade = safeNumber(payload and payload.grade, 0, 100)
    if identifier == '' or not grade then
        return false, 'Invalid payload'
    end
    if grade > (context.role.grade or 0) then
        return false, 'Cannot set grade above your own'
    end

    local currentGrade = getMemberGrade(context, identifier)
    if currentGrade then
        if grade > currentGrade and not hasContextPermission(context, editPermission) then
            return false, 'No permission'
        end
        if grade < currentGrade and not hasContextPermission(context, downPermission) then
            return false, 'No permission'
        end
        if grade == currentGrade and (not hasContextPermission(context, editPermission) and not hasContextPermission(context, downPermission)) then
            return false, 'No permission'
        end
    else
        if not hasContextPermission(context, editPermission) then
            return false, 'No permission'
        end
    end

    local ok = setRoleForIdentifier(context.menuType, identifier, context.role.name, grade)
    if not ok then return false, 'Grade update failed' end

    clearEmployeeCache(context.menuType, context.role.name)
    local hookName = context.menuType == 'gang' and 'gang_member_grade_updated' or 'employee_grade_updated'
    local hookPayload = {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        target = identifier,
        grade = grade
    }
    emitHook(hookName, hookPayload)
    if context.menuType == 'gang' then
        emitHook('OnGangMemberGradeUpdated', hookPayload)
        if currentGrade and grade > currentGrade then
            emitHook('OnGangMemberPromoted', hookPayload)
        elseif currentGrade and grade < currentGrade then
            emitHook('OnGangMemberDemoted', hookPayload)
        end
    else
        emitHook('OnEmployeeGradeUpdated', hookPayload)
        if currentGrade and grade > currentGrade then
            emitHook('OnEmployeePromoted', hookPayload)
        elseif currentGrade and grade < currentGrade then
            emitHook('OnEmployeeDemoted', hookPayload)
        end
    end
    addAudit(context.role.name, context.menuType .. '_set_grade', context.player.identifier, identifier, { grade = grade })
    return true, {
        grades = getRoleGrades(context.menuType, context.role.name),
        employees = getEmployeesForRole(context.menuType, context.role.name)
    }
end

local function actionFire(context, payload)
    local permission = context.menuType == 'gang' and 'kick_member' or 'fire_employee'
    if not hasContextPermission(context, permission) then
        return false, 'No permission'
    end

    local identifier = cleanText(payload and payload.identifier, 80)
    local reason = cleanText(payload and payload.reason, 255)
    if identifier == '' then return false, 'Invalid payload' end
    if Config.Security and Config.Security.requireReasonForFire == true and reason == '' then
        return false, 'Reason required'
    end
    if Config.Security and Config.Security.allowOfflineFire == false and not isIdentifierOnline(identifier) then
        return false, 'Offline fire disabled'
    end
    if identifier == context.player.identifier then
        return false, 'Cannot remove yourself'
    end

    local ok = removeRoleForIdentifier(context.menuType, identifier, context.role.name)
    if not ok then return false, 'Could not remove member' end

    clearEmployeeCache(context.menuType, context.role.name)
    local hookName = context.menuType == 'gang' and 'gang_member_fired' or 'employee_fired'
    local hookPayload = {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        target = identifier
    }
    emitHook(hookName, hookPayload)
    if context.menuType == 'gang' then
        emitHook('OnGangMemberFired', hookPayload)
    else
        emitHook('OnEmployeeFired', hookPayload)
    end
    addAudit(context.role.name, context.menuType .. '_fire', context.player.identifier, identifier, { reason = reason ~= '' and reason or nil })
    return true, {
        grades = getRoleGrades(context.menuType, context.role.name),
        employees = getEmployeesForRole(context.menuType, context.role.name)
    }
end

local function actionDeposit(context, payload)
    if not financeAllowed(context.menuType) then
        return false, 'Finance unavailable for this menu'
    end
    local permission = context.menuType == 'gang' and 'manage_cash_locker' or 'deposit_money'
    if not hasContextPermission(context, permission) then
        return false, 'No permission'
    end
    local maxAmount = maxMoneyAmount()
    local amount = safeNumber(payload and payload.amount, 1, maxAmount)
    if not amount then return false, 'Invalid amount' end

    local ok = removeCash(context.player, amount)
    if not ok then return false, 'Not enough cash' end

    ensureAccount(context.role.name)
    MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { amount, context.role.name })
    mirrorSocietyMoney(context.role.name, amount, 'add', context.menuType == 'gang' and 'gang_cash_locker_deposit' or 'boss_deposit')
    addLedger(context.role.name, 'deposit', amount, context.player.identifier, nil, 'Boss deposit')
    addAudit(context.role.name, 'deposit', context.player.identifier, nil, { amount = amount })
    emitHook('society_deposit', {
        role = context.role.name,
        actor = context.player.identifier,
        amount = amount
    })
    return true, {
        balance = getBalance(context.role.name),
        ledger = getLedger(context.role.name)
    }
end

local function actionWithdraw(context, payload)
    if not financeAllowed(context.menuType) then
        return false, 'Finance unavailable for this menu'
    end
    local permission = context.menuType == 'gang' and 'manage_cash_locker' or 'withdraw_money'
    if not hasContextPermission(context, permission) then
        return false, 'No permission'
    end
    local reason = cleanText(payload and payload.reason, 255)
    if Config.Security and Config.Security.requireReasonForWithdraw == true and reason == '' then
        return false, 'Reason required'
    end
    local maxAmount = maxMoneyAmount()
    local amount = safeNumber(payload and payload.amount, 1, maxAmount)
    if not amount then return false, 'Invalid amount' end
    if Config.Security and Config.Security.requireSecondApprovalForLargeWithdraw == true then
        local threshold = tonumber(Config.Security.largeWithdrawThreshold or 250000) or 250000
        if amount >= threshold and not hasContextPermission(context, 'approve_withdrawals') then
            return false, 'Large withdraw requires approval'
        end
    end

    ensureAccount(context.role.name)
    local affected = MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance - ? WHERE job = ? AND balance >= ?', {
        amount, context.role.name, amount
    })
    if (affected or 0) < 1 then
        return false, 'Insufficient society funds'
    end

    local ok = addCash(context.player, amount)
    if not ok then
        MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { amount, context.role.name })
        return false, 'Could not give cash'
    end
    mirrorSocietyMoney(context.role.name, amount, 'remove', context.menuType == 'gang' and 'gang_cash_locker_withdraw' or 'boss_withdraw')

    addLedger(context.role.name, 'withdraw', amount, context.player.identifier, nil, reason ~= '' and reason or 'Boss withdraw')
    addAudit(context.role.name, 'withdraw', context.player.identifier, nil, { amount = amount, reason = reason ~= '' and reason or nil })
    emitHook('society_withdraw', {
        role = context.role.name,
        actor = context.player.identifier,
        amount = amount
    })
    return true, {
        balance = getBalance(context.role.name),
        ledger = getLedger(context.role.name)
    }
end

local function actionGetRanks(context)
    local permission = 'edit_ranks'
    if not hasContextPermission(context, permission) then
        return false, 'No permission'
    end

    local grades = getRoleGrades(context.menuType, context.role.name)
    local out = {}
    for _, grade in ipairs(grades) do
        out[#out + 1] = {
            level = grade.level,
            name = grade.name,
            isBoss = grade.isBoss == true,
            icon = grade.icon,
            style = grade.style,
            salaryType = grade.salaryType,
            salaryAmount = grade.salaryAmount,
            description = grade.description,
            protected = grade.protected == true,
            custom = grade.custom == true,
            assigned = getRoleMemberCountByGrade(context.menuType, context.role.name, grade.level)
        }
    end
    return true, { ranks = out }
end

local function normalizeRankPayload(payload)
    local level = safeNumber(payload and payload.grade, 0, 100)
    local rankName = cleanText(payload and payload.name, 64)
    local rankIcon = cleanText(payload and payload.icon, 64)
    local description = cleanText(payload and payload.description, 512)
    local salaryType = cleanText(payload and payload.salaryType, 24)
    local salaryAmount = safeNumber(payload and payload.salaryAmount, 0, maxMoneyAmount())
    local style = payload and payload.style or nil
    if type(style) ~= 'table' then
        style = decodeJson(style)
    end
    if type(style) ~= 'table' then
        style = nil
    end
    if salaryType == '' then salaryType = 'framework' end
    if salaryType ~= 'framework' and salaryType ~= 'custom' and salaryType ~= 'unpaid' then
        salaryType = 'framework'
    end
    if salaryType == 'unpaid' then
        salaryAmount = 0
    end
    if salaryAmount == nil then
        salaryAmount = 0
    end
    return {
        level = level,
        rankName = rankName,
        rankIcon = rankIcon ~= '' and rankIcon or nil,
        description = description ~= '' and description or nil,
        salaryType = salaryType,
        salaryAmount = salaryAmount,
        style = style
    }
end

local function actionCreateRank(context, payload)
    if not isModuleEnabled('DynamicRanks') then
        return false, 'Dynamic ranks disabled'
    end
    if not hasContextPermission(context, 'edit_ranks') then
        return false, 'No permission'
    end

    local data = normalizeRankPayload(payload)
    if not data.level or data.rankName == '' then
        return false, 'Invalid payload'
    end
    if data.level > (context.role.grade or 0) then
        return false, 'Cannot create rank above your own grade'
    end

    local orgType = getOrgTypeByMenu(context.menuType)
    local exists = MySQL.single.await([[SELECT id FROM bossmenu_custom_ranks
        WHERE org_type = ? AND org_name = ? AND grade = ? LIMIT 1]], {
        orgType, context.role.name, data.level
    })
    if exists then
        return false, 'Rank already exists'
    end

    MySQL.insert.await([[INSERT INTO bossmenu_custom_ranks (org_type, org_name, grade, rank_name, rank_icon, rank_style, salary_type, salary_amount, description, protected_rank, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)]], {
        orgType,
        context.role.name,
        data.level,
        data.rankName,
        data.rankIcon,
        data.style and json.encode(data.style) or nil,
        data.salaryType,
        data.salaryAmount,
        data.description,
        context.player.identifier
    })

    invalidateOrganizationCaches(context.menuType, context.role.name)
    addAudit(context.role.name, context.menuType .. '_rank_create', context.player.identifier, nil, {
        grade = data.level,
        name = data.rankName
    })
    emitHook(context.menuType == 'gang' and 'gang_rank_created' or 'employee_rank_created', {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        grade = data.level,
        name = data.rankName
    })
    return actionGetRanks(context)
end

local function actionUpdateRank(context, payload)
    if not isModuleEnabled('DynamicRanks') then
        return false, 'Dynamic ranks disabled'
    end
    if not hasContextPermission(context, 'edit_ranks') then
        return false, 'No permission'
    end

    local fromGrade = safeNumber(payload and payload.grade, 0, 100)
    if not fromGrade then
        return false, 'Invalid rank'
    end
    local data = normalizeRankPayload(payload)
    local toGrade = safeNumber(payload and payload.newGrade, 0, 100) or fromGrade
    if toGrade > (context.role.grade or 0) then
        return false, 'Cannot move rank above your own grade'
    end
    if data.rankName == '' then
        return false, 'Invalid rank name'
    end

    local orgType = getOrgTypeByMenu(context.menuType)
    local row = MySQL.single.await([[SELECT id, protected_rank FROM bossmenu_custom_ranks
        WHERE org_type = ? AND org_name = ? AND grade = ? LIMIT 1]], {
        orgType, context.role.name, fromGrade
    })
    if not row then
        return false, 'Custom rank not found'
    end
    if tonumber(row.protected_rank) == 1 then
        return false, 'Protected rank cannot be edited'
    end

    if toGrade ~= fromGrade then
        local hasMembers = getRoleMemberCountByGrade(context.menuType, context.role.name, fromGrade) > 0
        if hasMembers then
            return false, 'Reassign members before changing grade'
        end
        local taken = MySQL.single.await([[SELECT id FROM bossmenu_custom_ranks
            WHERE org_type = ? AND org_name = ? AND grade = ? LIMIT 1]], {
            orgType, context.role.name, toGrade
        })
        if taken then
            return false, 'Target grade already exists'
        end
    end

    MySQL.update.await([[UPDATE bossmenu_custom_ranks
        SET grade = ?, rank_name = ?, rank_icon = ?, rank_style = ?, salary_type = ?, salary_amount = ?, description = ?
        WHERE id = ?]], {
        toGrade,
        data.rankName,
        data.rankIcon,
        data.style and json.encode(data.style) or nil,
        data.salaryType,
        data.salaryAmount,
        data.description,
        row.id
    })

    invalidateOrganizationCaches(context.menuType, context.role.name)
    addAudit(context.role.name, context.menuType .. '_rank_update', context.player.identifier, nil, {
        from = fromGrade,
        to = toGrade,
        name = data.rankName
    })
    emitHook(context.menuType == 'gang' and 'gang_rank_updated' or 'employee_rank_updated', {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        from = fromGrade,
        to = toGrade
    })
    return actionGetRanks(context)
end

local function actionReassignRank(context, payload)
    if not isModuleEnabled('DynamicRanks') then
        return false, 'Dynamic ranks disabled'
    end
    if not hasContextPermission(context, 'edit_ranks') then
        return false, 'No permission'
    end

    local fromGrade = safeNumber(payload and payload.fromGrade, 0, 100)
    local toGrade = safeNumber(payload and payload.toGrade, 0, 100)
    if not fromGrade or not toGrade or fromGrade == toGrade then
        return false, 'Invalid grades'
    end
    if toGrade > (context.role.grade or 0) then
        return false, 'Cannot reassign to grade above your own'
    end

    local identifiers = getRoleMemberIdentifiersByGrade(context.menuType, context.role.name, fromGrade)
    local moved = 0
    for _, identifier in ipairs(identifiers) do
        local ok = setRoleForIdentifier(context.menuType, identifier, context.role.name, toGrade)
        if ok then
            moved = moved + 1
        end
    end

    invalidateOrganizationCaches(context.menuType, context.role.name)
    addAudit(context.role.name, context.menuType .. '_rank_reassign', context.player.identifier, nil, {
        from = fromGrade,
        to = toGrade,
        moved = moved
    })
    emitHook(context.menuType == 'gang' and 'gang_rank_reassigned' or 'employee_rank_reassigned', {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        from = fromGrade,
        to = toGrade,
        moved = moved
    })
    return true, {
        moved = moved,
        employees = getEmployeesForRole(context.menuType, context.role.name),
        ranks = getRoleGrades(context.menuType, context.role.name)
    }
end

local function actionDeleteRank(context, payload)
    if not isModuleEnabled('DynamicRanks') then
        return false, 'Dynamic ranks disabled'
    end
    if not hasContextPermission(context, 'edit_ranks') then
        return false, 'No permission'
    end

    local grade = safeNumber(payload and payload.grade, 0, 100)
    local reassignTo = safeNumber(payload and payload.reassignTo, 0, 100)
    if not grade then
        return false, 'Invalid rank'
    end

    local orgType = getOrgTypeByMenu(context.menuType)
    local row = MySQL.single.await([[SELECT id, protected_rank FROM bossmenu_custom_ranks
        WHERE org_type = ? AND org_name = ? AND grade = ? LIMIT 1]], {
        orgType, context.role.name, grade
    })
    if not row then
        return false, 'Custom rank not found'
    end
    if tonumber(row.protected_rank) == 1 then
        return false, 'Protected rank cannot be deleted'
    end

    local identifiers = getRoleMemberIdentifiersByGrade(context.menuType, context.role.name, grade)
    if #identifiers > 0 then
        if not reassignTo then
            return false, 'Rank has assigned members; provide reassign grade'
        end
        if reassignTo > (context.role.grade or 0) then
            return false, 'Cannot reassign above your own grade'
        end
        for _, identifier in ipairs(identifiers) do
            setRoleForIdentifier(context.menuType, identifier, context.role.name, reassignTo)
        end
    end

    MySQL.update.await('DELETE FROM bossmenu_custom_ranks WHERE id = ?', { row.id })
    invalidateOrganizationCaches(context.menuType, context.role.name)

    addAudit(context.role.name, context.menuType .. '_rank_delete', context.player.identifier, nil, {
        grade = grade,
        reassignTo = reassignTo
    })
    emitHook(context.menuType == 'gang' and 'gang_rank_deleted' or 'employee_rank_deleted', {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        grade = grade,
        reassignTo = reassignTo
    })
    return actionGetRanks(context)
end

local function actionGetRankPermissions(context, payload)
    if not hasContextPermission(context, 'edit_permissions') then
        return false, 'No permission'
    end
    local grade = safeNumber(payload and payload.grade, 0, 100)
    if grade == nil then
        grade = context.role.grade or 0
    end
    return true, {
        grade = grade,
        permissions = getGradePermissionMap(context.menuType, context.role.name, grade),
        knownPermissions = getKnownPermissionMap(context.menuType)
    }
end

local function actionSetRankPermission(context, payload)
    if not isModuleEnabled('RankPermissions') then
        return false, 'Rank permissions disabled'
    end
    if not hasContextPermission(context, 'edit_permissions') then
        return false, 'No permission'
    end

    local grade = safeNumber(payload and payload.grade, 0, 100)
    local permissionKey = cleanText(payload and payload.permission, 64)
    local allowed = payload and payload.allowed == true
    if not grade or permissionKey == '' then
        return false, 'Invalid payload'
    end
    local known = getKnownPermissionMap(context.menuType)
    if known[permissionKey] == nil then
        return false, 'Unknown permission key'
    end

    MySQL.insert.await([[INSERT INTO bossmenu_rank_permissions (org_type, org_name, grade, permission_key, allowed, updated_by)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE allowed = VALUES(allowed), updated_by = VALUES(updated_by)]], {
        getOrgTypeByMenu(context.menuType),
        context.role.name,
        grade,
        permissionKey,
        allowed and 1 or 0,
        context.player.identifier
    })

    invalidateOrganizationCaches(context.menuType, context.role.name)
    addAudit(context.role.name, context.menuType .. '_permission_set', context.player.identifier, nil, {
        grade = grade,
        permission = permissionKey,
        allowed = allowed
    })
    emitHook(context.menuType == 'gang' and 'gang_permission_updated' or 'employee_permission_updated', {
        menuType = context.menuType,
        role = context.role.name,
        actor = context.player.identifier,
        grade = grade,
        permission = permissionKey,
        allowed = allowed
    })
    return actionGetRankPermissions(context, { grade = grade })
end

local function memberViewPermission(menuType)
    return menuType == 'gang' and 'view_members' or 'view_employees'
end

local function actionGetMemberProfile(context, payload)
    if not isModuleEnabled('EmployeeProfiles') then
        return false, 'Employee profiles disabled'
    end
    if not hasContextPermission(context, memberViewPermission(context.menuType)) then
        return false, 'No permission'
    end
    local identifier = cleanText(payload and payload.identifier, 80)
    if identifier == '' then
        local srcCandidate = safeNumber(payload and payload.source, 1)
        if srcCandidate then
            local target = getPlayerState(srcCandidate)
            if target then
                identifier = cleanText(target.identifier, 80)
            end
        end
    end
    if identifier == '' then
        return false, 'Invalid identifier'
    end
    local member = getMemberRowByIdentifier(context, identifier)
    if not member then
        return false, 'Member not found in this organization'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local profile = EmployeesModule.GetProfile(orgType, context.role.name, identifier)
    local activity = EmployeesModule.GetActivity(orgType, context.role.name, identifier, 25)
    local memberGrade = getMemberGrade(context, identifier)
    local onlineState = member.source and getPlayerState(member.source) or getOnlineStateByIdentifier(identifier)
    local character = getFrameworkCharacterDetails(identifier, onlineState)
    profile.metadata = type(profile.metadata) == 'table' and profile.metadata or {}
    profile.metadata.character = character
    return true, {
        profile = profile,
        activity = activity,
        currentGrade = memberGrade,
        member = member,
        character = character
    }
end

local function cleanupProfileImageRequests()
    local now = nowMs()
    for key, req in pairs(ProfileImageRequests) do
        if not req or now > (req.expiresAt or 0) then
            ProfileImageRequests[key] = nil
        end
    end
end

local function actionGenerateMemberProfileImage(context, payload)
    if not isModuleEnabled('EmployeeProfiles') then
        return false, 'Employee profiles disabled'
    end
    if not hasContextPermission(context, 'edit_permissions') then
        return false, 'No permission'
    end
    local providers = resolveScreenshotProviders()
    if #providers < 1 then
        return false, 'No screenshot provider configured'
    end

    local identifier = cleanText(payload and payload.identifier, 80)
    if identifier == '' then
        return false, 'Invalid identifier'
    end

    local member = getMemberRowByIdentifier(context, identifier)
    if not member then
        return false, 'Member not found in this organization'
    end
    local targetSource = tonumber(member.source) or 0
    if targetSource < 1 then
        return false, 'Member must be online for image capture'
    end

    cleanupProfileImageRequests()
    local requestId = ('%d:%d:%d'):format(context.player.source, nowMs(), math.random(1000, 999999))
    ProfileImageRequests[requestId] = {
        id = requestId,
        actorSource = context.player.source,
        actorIdentifier = context.player.identifier,
        targetSource = targetSource,
        targetIdentifier = identifier,
        orgType = getOrgTypeByMenu(context.menuType),
        orgName = context.role.name,
        expiresAt = nowMs() + 25000
    }

    local shotCfg = getScreenshotConfig()
    TriggerClientEvent('qb-management:client:prepareProfileCapture', targetSource, {
        requestId = requestId,
        options = {
            encoding = cleanText(shotCfg.encoding or 'webp', 16),
            quality = tonumber(shotCfg.quality) or 0.28
        },
        providers = providers
    })

    addAudit(context.role.name, context.menuType .. '_profile_image_request', context.player.identifier, identifier, {
        requestId = requestId,
        targetSource = targetSource
    })

    return true, {
        queued = true,
        requestId = requestId,
        identifier = identifier
    }
end

local function actionUpdateMemberProfile(context, payload)
    if not isModuleEnabled('EmployeeProfiles') then
        return false, 'Employee profiles disabled'
    end
    if not hasContextPermission(context, 'edit_permissions') then
        return false, 'No permission'
    end
    local identifier = cleanText(payload and payload.identifier, 80)
    if identifier == '' then
        return false, 'Invalid identifier'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local existing = EmployeesModule.GetProfile(orgType, context.role.name, identifier)
    local merged = payload or {}
    if type(merged.metadata) ~= 'table' then
        merged.metadata = type(existing.metadata) == 'table' and existing.metadata or {}
    end
    local profile = EmployeesModule.UpsertProfile(orgType, context.role.name, identifier, merged, context.player.identifier)
    return true, { profile = profile }
end

local function actionUpdateStrikes(context, payload)
    if not isModuleEnabled('EmployeeProfiles') then
        return false, 'Employee profiles disabled'
    end
    if not hasContextPermission(context, 'fire_employee') and not hasContextPermission(context, 'kick_member') then
        return false, 'No permission'
    end
    local identifier = cleanText(payload and payload.identifier, 80)
    local amount = tonumber(payload and payload.amount) or 0
    if identifier == '' or amount == 0 then
        return false, 'Invalid payload'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local ok, dataOrErr = EmployeesModule.AddStrike(orgType, context.role.name, identifier, amount, payload and payload.reason, context.player.identifier)
    if not ok then
        return false, dataOrErr
    end
    return true, { profile = dataOrErr }
end

local function actionSearchMembers(context, payload)
    if not hasContextPermission(context, memberViewPermission(context.menuType)) then
        return false, 'No permission'
    end
    local rows = getEmployeesForRole(context.menuType, context.role.name)
    local filtered = EmployeesModule.FilterAndSortRows(rows, payload or {})
    return true, { employees = filtered }
end

local function actionSetSalary(context, payload)
    if not isModuleEnabled('SalaryManagement') then
        return false, 'Salary management disabled'
    end
    if not hasContextPermission(context, 'edit_ranks') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local ok, err = FinanceModule.SetSalaryOverride(orgType, context.role.name, payload or {}, context.player.identifier)
    if not ok then
        return false, err
    end
    return true, { ok = true }
end

local function actionRunPayroll(context)
    if not isModuleEnabled('Payroll') then
        return false, 'Payroll disabled'
    end
    if not hasContextPermission(context, 'view_finance') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local ok, dataOrErr = runPayrollForOrg(orgType, context.role.name, context.player.identifier, 'manual')
    if not ok then
        return false, dataOrErr
    end
    return true, {
        payroll = dataOrErr,
        balance = getBalance(context.role.name)
    }
end

local function actionInventoryList(context)
    if not isModuleEnabled('BusinessInventory') then
        return false, 'Business inventory disabled'
    end
    if not hasContextPermission(context, 'view_inventory') and not hasContextPermission(context, 'manage_stash') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    return true, {
        items = InventoryModule.GetItems(orgType, context.role.name),
        logs = InventoryModule.GetLogs(orgType, context.role.name, 100)
    }
end

local function actionInventoryModify(context, payload, op)
    if not isModuleEnabled('BusinessInventory') then
        return false, 'Business inventory disabled'
    end
    local permission = op == 'deposit' and 'deposit_items' or 'withdraw_items'
    if context.menuType == 'gang' then
        permission = 'manage_stash'
    end
    if not hasContextPermission(context, permission) then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local amount = tonumber(payload and payload.amount) or 0
    if amount <= 0 then
        return false, 'Invalid amount'
    end
    if op == 'withdraw' then amount = -amount end
    local ok, err = InventoryModule.ModifyItem(
        orgType,
        context.role.name,
        payload and payload.item,
        amount,
        context.player.identifier,
        op,
        payload and payload.metadata,
        context.player.source
    )
    if not ok then
        return false, err
    end
    return actionInventoryList(context)
end

local function actionOpenBossStash(context, src)
    if context.menuType ~= 'boss' then
        return false, 'Boss stash is only available in boss mode'
    end
    if not canUseOrgStash(context) then
        return false, 'No permission'
    end
    local backend = getStashIntegration()
    if backend == 'none' then
        return false, 'No inventory integration configured'
    end

    local meta = stashOpenMeta(context)
    if backend == 'ox_inventory' then
        pcall(function()
            exports.ox_inventory:RegisterStash(meta.stashId, meta.label, meta.slots, meta.maxWeight, false)
        end)
    elseif backend == 'qs-inventory' then
        pcall(function()
            exports['qs-inventory']:RegisterStash(src, meta.stashId, meta.slots, meta.maxWeight)
        end)
    end

    TriggerClientEvent('qb-management:client:openOrgStash', src, {
        backend = backend,
        stashId = meta.stashId,
        label = meta.label,
        slots = meta.slots,
        maxWeight = meta.maxWeight
    })
    addAudit(context.role.name, context.menuType .. '_stash_open', context.player.identifier, nil, {
        backend = backend,
        stashId = meta.stashId
    })
    emitHook('stash_opened', {
        orgType = context.menuType,
        orgName = context.role.name,
        actor = context.player.identifier,
        backend = backend,
        stashId = meta.stashId
    })
    return true, { opened = true }
end

local function actionUniforms(context, payload, op)
    if not isModuleEnabled('Uniforms') then
        return false, 'Uniforms disabled'
    end
    if not hasContextPermission(context, 'manage_uniforms') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    if op == 'list' then
        return true, { uniforms = UniformsModule.List(orgType, context.role.name) }
    end
    if op == 'save' then
        local ok, dataOrErr = UniformsModule.Save(orgType, context.role.name, payload or {}, context.player.identifier)
        if not ok then return false, dataOrErr end
        return true, { uniform = dataOrErr, uniforms = UniformsModule.List(orgType, context.role.name) }
    end
    if op == 'apply' or op == 'preview' or op == 'restore' then
        local ok, err = UniformsModule.Apply(orgType, context.role.name, payload and payload.id, context.player.identifier, context.player.source, op)
        if not ok then return false, err end
        return true, { ok = true }
    end
    local ok, err = UniformsModule.Delete(orgType, context.role.name, payload and payload.id, context.player.identifier)
    if not ok then return false, err end
    return true, { uniforms = UniformsModule.List(orgType, context.role.name) }
end

local function actionApplications(context, payload, op)
    if not isModuleEnabled('Applications') then
        return false, 'Applications disabled'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    if op == 'submit' then
        return ApplicationsModule.Create(orgType, context.role.name, payload or {})
    end
    if not hasContextPermission(context, 'manage_applications') then
        return false, 'No permission'
    end
    if op == 'list' then
        return true, { applications = ApplicationsModule.List(orgType, context.role.name, payload and payload.status, payload and payload.search) }
    end
    local ok, err = ApplicationsModule.Decide(
        orgType,
        context.role.name,
        payload and payload.id,
        payload and payload.status,
        payload and payload.reason,
        context.player.identifier
    )
    if not ok then return false, err end
    if payload and payload.status == 'accepted' and payload.autoHire ~= false then
        local rows = ApplicationsModule.List(orgType, context.role.name, 'accepted', nil)
        local acceptedIdentifier = nil
        for i = 1, #rows do
            if tonumber(rows[i].id) == tonumber(payload.id) then
                acceptedIdentifier = cleanText(rows[i].applicant_identifier, 80)
                break
            end
        end
        if acceptedIdentifier and acceptedIdentifier ~= '' then
            local offerGrade = safeNumber(payload.offerGrade, 0, 100) or 0
            setRoleForIdentifier(context.menuType, acceptedIdentifier, context.role.name, offerGrade)
            clearEmployeeCache(context.menuType, context.role.name)
            addAudit(context.role.name, context.menuType .. '_application_hire', context.player.identifier, acceptedIdentifier, {
                applicationId = tonumber(payload.id) or 0,
                grade = offerGrade
            })
        end
    end
    return true, { applications = ApplicationsModule.List(orgType, context.role.name, 'all', nil) }
end

local function actionCreateAnnouncement(context, payload)
    if not isModuleEnabled('Announcements') then
        return false, 'Announcements disabled'
    end
    if not hasContextPermission(context, 'create_announcements') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local title = cleanText(payload and payload.title, 120)
    local body = cleanText(payload and payload.body, 4000)
    local pinned = payload and payload.pinned == true
    local expiresAt = cleanText(payload and payload.expiresAt, 30)
    if title == '' or body == '' then
        return false, 'Title and body required'
    end
    MySQL.insert.await([[INSERT INTO bossmenu_announcements (org_type, org_name, title, body, pinned, visibility_json, expires_at, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)]], {
        orgType, context.role.name, title, body, pinned and 1 or 0, payload and payload.visibility and json.encode(payload.visibility) or nil,
        expiresAt ~= '' and expiresAt or nil, context.player.identifier
    })
    local members = getEmployeesForRole(context.menuType, context.role.name)
    for i = 1, #members do
        local identifier = cleanText(members[i].identifier, 80)
        if identifier ~= '' then
            sendPhoneNotification(identifier, title, body)
        end
    end
    addAudit(context.role.name, context.menuType .. '_announcement_create', context.player.identifier, nil, { title = title })
    return true, { ok = true }
end

local function actionListAnnouncements(context)
    if not isModuleEnabled('Announcements') then
        return false, 'Announcements disabled'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local rows = MySQL.query.await([[SELECT id, title, body, pinned, visibility_json, expires_at, created_by, created_at
        FROM bossmenu_announcements
        WHERE org_type = ? AND org_name = ?
        ORDER BY pinned DESC, id DESC
        LIMIT 200]], { orgType, context.role.name }) or {}
    for i = 1, #rows do
        rows[i].visibility_json = decodeJson(rows[i].visibility_json) or {}
    end
    return true, { announcements = rows }
end

local function actionOrgMarkers(context, payload, op)
    if not hasContextPermission(context, 'manage_markers') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    if op == 'list' then
        local rows = MySQL.query.await([[SELECT id, marker_type, coords, marker_data, created_by, created_at, updated_at
            FROM bossmenu_org_markers
            WHERE org_type = ? AND org_name = ?
            ORDER BY id DESC]], { orgType, context.role.name }) or {}
        for i = 1, #rows do
            rows[i].coords = decodeJson(rows[i].coords) or {}
            rows[i].marker_data = decodeJson(rows[i].marker_data) or {}
        end
        return true, { markers = rows }
    end
    if op == 'delete' then
        local id = safeNumber(payload and payload.id, 1)
        if not id then return false, 'Invalid marker id' end
        local affected = MySQL.update.await('DELETE FROM bossmenu_org_markers WHERE id = ? AND org_type = ? AND org_name = ?', {
            id, orgType, context.role.name
        })
        if (affected or 0) < 1 then return false, 'Marker not found' end
        addAudit(context.role.name, context.menuType .. '_marker_delete', context.player.identifier, nil, { id = id })
        return true, { ok = true }
    end
    local markerType = cleanText(payload and payload.markerType, 32)
    local coords = type(payload and payload.coords) == 'table' and payload.coords or nil
    local markerData = type(payload and payload.data) == 'table' and payload.data or {}
    local id = safeNumber(payload and payload.id, 1)
    if markerType == '' or not coords then return false, 'Invalid marker payload' end

    local actorPed = GetPlayerPed(context.player.source)
    if actorPed ~= 0 then
        local myCoords = GetEntityCoords(actorPed)
        local target = vec3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
        local maxDist = tonumber(Config.Security and Config.Security.maxMarkerCreateDistance or 15.0) or 15.0
        if #(myCoords - target) > maxDist then
            return false, 'Marker is too far from player'
        end
    end

    if id then
        local affected = MySQL.update.await([[UPDATE bossmenu_org_markers
            SET marker_type = ?, coords = ?, marker_data = ?, updated_at = NOW()
            WHERE id = ? AND org_type = ? AND org_name = ?]], {
            markerType, json.encode(coords), json.encode(markerData), id, orgType, context.role.name
        })
        if (affected or 0) < 1 then return false, 'Marker not found' end
    else
        id = MySQL.insert.await([[INSERT INTO bossmenu_org_markers (org_type, org_name, marker_type, coords, marker_data, created_by)
            VALUES (?, ?, ?, ?, ?, ?)]], {
            orgType, context.role.name, markerType, json.encode(coords), json.encode(markerData), context.player.identifier
        })
    end
    addAudit(context.role.name, context.menuType .. '_marker_upsert', context.player.identifier, nil, { id = id, markerType = markerType })
    return true, { id = id }
end

local function actionOrgGarages(context, payload, op)
    if context.menuType == 'gang' and not isModuleEnabled('GangGarages') then
        return false, 'Gang garages disabled'
    end
    if not hasContextPermission(context, 'manage_garage') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    if op == 'list' then
        local rows = MySQL.query.await([[SELECT id, name, coords, options_json, created_by, created_at
            FROM bossmenu_org_garages
            WHERE org_type = ? AND org_name = ?
            ORDER BY id DESC]], { orgType, context.role.name }) or {}
        for i = 1, #rows do
            rows[i].coords = decodeJson(rows[i].coords) or {}
            rows[i].options_json = decodeJson(rows[i].options_json) or {}
        end
        return true, { garages = rows }
    end
    if op == 'delete' then
        local id = safeNumber(payload and payload.id, 1)
        if not id then return false, 'Invalid garage id' end
        local affected = MySQL.update.await('DELETE FROM bossmenu_org_garages WHERE id = ? AND org_type = ? AND org_name = ?', {
            id, orgType, context.role.name
        })
        if (affected or 0) < 1 then return false, 'Garage not found' end
        addAudit(context.role.name, context.menuType .. '_garage_delete', context.player.identifier, nil, { id = id })
        return true, { ok = true }
    end
    local id = safeNumber(payload and payload.id, 1)
    local name = cleanText(payload and payload.name, 80)
    local coords = type(payload and payload.coords) == 'table' and payload.coords or nil
    local options = type(payload and payload.options) == 'table' and payload.options or {}
    if name == '' or not coords then return false, 'Invalid garage payload' end

    if id then
        local affected = MySQL.update.await([[UPDATE bossmenu_org_garages
            SET name = ?, coords = ?, options_json = ?
            WHERE id = ? AND org_type = ? AND org_name = ?]], {
            name, json.encode(coords), json.encode(options), id, orgType, context.role.name
        })
        if (affected or 0) < 1 then return false, 'Garage not found' end
    else
        id = MySQL.insert.await([[INSERT INTO bossmenu_org_garages (org_type, org_name, name, coords, options_json, created_by)
            VALUES (?, ?, ?, ?, ?, ?)]], {
            orgType, context.role.name, name, json.encode(coords), json.encode(options), context.player.identifier
        })
    end
    addAudit(context.role.name, context.menuType .. '_garage_upsert', context.player.identifier, nil, { id = id, name = name })
    return true, { id = id }
end

local function actionAdmin(context, payload, op)
    if not isModuleEnabled('AdminPanel') then
        return false, 'Admin panel disabled'
    end
    if not AdminModule.IsAdmin(context.player.source, context.player) then
        return false, 'No permission'
    end
    if op == 'list_orgs' then
        return true, AdminModule.ListOrganizations()
    end
    if op == 'add_funds' then
        return AdminModule.AddFunds(payload and payload.orgType, cleanText(payload and payload.orgName, 64), tonumber(payload and payload.amount), context.player.identifier)
    end
    if op == 'remove_funds' then
        return AdminModule.RemoveFunds(payload and payload.orgType, cleanText(payload and payload.orgName, 64), tonumber(payload and payload.amount), context.player.identifier)
    end
    if op == 'actions' then
        return true, { actions = AdminModule.GetRecentAdminActions(payload and payload.limit) }
    end
    if op == 'webhooks_get' then
        if not AuditModule or not AuditModule.GetWebhookSettings then
            return false, 'Webhook module unavailable'
        end
        return true, {
            categories = AuditModule.GetWebhookCategories and AuditModule.GetWebhookCategories() or {},
            settings = AuditModule.GetWebhookSettings('admin', '', '')
        }
    end
    if op == 'webhooks_save' then
        if not AuditModule or not AuditModule.SaveWebhookSetting then
            return false, 'Webhook module unavailable'
        end
        payload = type(payload) == 'table' and payload or {}
        local ok, err = AuditModule.SaveWebhookSetting(
            'admin',
            '',
            '',
            payload.category,
            payload.webhookUrl,
            payload.enabled == true,
            context.player.identifier
        )
        if not ok then
            return false, err
        end
        addAudit('admin', 'admin_webhook_setting_saved', context.player.identifier, nil, {
            category = cleanText(payload.category, 32),
            enabled = payload.enabled == true,
            hasUrl = cleanText(payload.webhookUrl, 600) ~= ''
        })
        return true, {
            categories = AuditModule.GetWebhookCategories and AuditModule.GetWebhookCategories() or {},
            settings = AuditModule.GetWebhookSettings('admin', '', '')
        }
    end
    payload = type(payload) == 'table' and payload or {}

    local function adminLog(action, orgType, orgName, target, metadata)
        local meta = type(metadata) == 'table' and metadata or {}
        meta.orgType = orgType
        meta.orgName = orgName
        MySQL.insert.await([[INSERT INTO bossmenu_admin_actions (admin_identifier, action, org_type, org_name, target_identifier, metadata)
            VALUES (?, ?, ?, ?, ?, ?)]], {
            context.player.identifier,
            tostring(action),
            orgType,
            orgName,
            target,
            json.encode(meta)
        })
        addAudit(orgName or 'admin', 'admin_' .. tostring(action), context.player.identifier, target, meta)
    end

    local orgType = cleanText(payload.orgType, 16)
    if orgType ~= 'gang' then orgType = 'boss' end
    local orgName = cleanText(payload.orgName, 64)
    local reason = cleanText(payload.reason, 255)

    local function resolveIdentifier()
        local identifier = cleanText(payload.identifier, 80)
        if identifier ~= '' then
            return identifier
        end
        local targetSrc = safeNumber(payload.target or payload.source, 1)
        if targetSrc then
            local state = getPlayerState(targetSrc)
            if state and state.identifier then
                return tostring(state.identifier)
            end
        end
        return nil
    end

    if op == 'disable_org' then
        if orgName == '' then return false, 'Invalid organization' end
        setOrgState(orgType, orgName, true, reason ~= '' and reason or 'disabled by admin', context.player.identifier)
        adminLog(op, orgType, orgName, nil, { reason = reason })
        emitHook('admin_org_disabled', { orgType = orgType, orgName = orgName, actor = context.player.identifier, reason = reason })
        return true
    end
    if op == 'enable_org' then
        if orgName == '' then return false, 'Invalid organization' end
        setOrgState(orgType, orgName, false, reason, context.player.identifier)
        adminLog(op, orgType, orgName, nil, { reason = reason })
        emitHook('admin_org_enabled', { orgType = orgType, orgName = orgName, actor = context.player.identifier, reason = reason })
        return true
    end
    if op == 'force_add_member' then
        if orgName == '' then return false, 'Invalid organization' end
        local identifier = resolveIdentifier()
        if not identifier then return false, 'Invalid target' end
        local grade = safeNumber(payload.grade, 0, 100) or 0
        local ok = setRoleForIdentifier(orgType == 'gang' and 'gang' or 'boss', identifier, orgName, grade)
        if not ok then return false, 'Failed to add member' end
        invalidateOrganizationCaches(orgType == 'gang' and 'gang' or 'boss', orgName)
        adminLog(op, orgType, orgName, identifier, { grade = grade })
        return true
    end
    if op == 'force_remove_member' then
        if orgName == '' then return false, 'Invalid organization' end
        local identifier = resolveIdentifier()
        if not identifier then return false, 'Invalid target' end
        local ok = removeRoleForIdentifier(orgType == 'gang' and 'gang' or 'boss', identifier, orgName)
        if not ok then return false, 'Failed to remove member' end
        invalidateOrganizationCaches(orgType == 'gang' and 'gang' or 'boss', orgName)
        adminLog(op, orgType, orgName, identifier, { reason = reason })
        return true
    end
    if op == 'force_set_grade' then
        if orgName == '' then return false, 'Invalid organization' end
        local identifier = resolveIdentifier()
        local grade = safeNumber(payload.grade, 0, 100)
        if not identifier or grade == nil then return false, 'Invalid payload' end
        local ok = setRoleForIdentifier(orgType == 'gang' and 'gang' or 'boss', identifier, orgName, grade)
        if not ok then return false, 'Failed to set grade' end
        invalidateOrganizationCaches(orgType == 'gang' and 'gang' or 'boss', orgName)
        adminLog(op, orgType, orgName, identifier, { grade = grade })
        return true
    end
    if op == 'change_leader' then
        if orgName == '' then return false, 'Invalid organization' end
        local identifier = resolveIdentifier()
        if not identifier then return false, 'Invalid target' end
        local grades = getRoleGrades(orgType == 'gang' and 'gang' or 'boss', orgName)
        local topGrade = 0
        for i = 1, #grades do
            topGrade = math.max(topGrade, tonumber(grades[i].level) or 0)
        end
        local ok = setRoleForIdentifier(orgType == 'gang' and 'gang' or 'boss', identifier, orgName, topGrade)
        if not ok then return false, 'Failed to change leader' end
        invalidateOrganizationCaches(orgType == 'gang' and 'gang' or 'boss', orgName)
        adminLog(op, orgType, orgName, identifier, { grade = topGrade })
        emitHook('admin_leader_changed', { orgType = orgType, orgName = orgName, target = identifier, actor = context.player.identifier })
        return true
    end
    if op == 'delete_internal_gang' then
        if orgType ~= 'gang' then return false, 'Gang action only' end
        if useInbuiltGangFrames() then
            return false, 'Internal gang backend not active'
        end
        if not supportsCustomGangBackend() then
            return false, 'Unsupported framework'
        end
        if orgName == '' then return false, 'Invalid gang' end
        if tostring(payload.confirm or '') ~= 'DELETE' then
            return false, 'Confirmation required'
        end
        MySQL.update.await('DELETE FROM bossmenu_gang_members WHERE gang_name = ?', { orgName })
        MySQL.update.await('DELETE FROM bossmenu_gangs WHERE name = ?', { orgName })
        MySQL.update.await('DELETE FROM bossmenu_gang_markers WHERE gang_name = ?', { orgName })
        MySQL.update.await('DELETE FROM bossmenu_gang_notoriety WHERE gang_name = ?', { orgName })
        MySQL.update.await('DELETE FROM bossmenu_gang_rackets WHERE gang_name = ?', { orgName })
        MySQL.update.await('DELETE FROM bossmenu_gang_graffiti WHERE gang_name = ?', { orgName })
        MySQL.update.await('DELETE FROM bossmenu_gang_contracts WHERE gang_name = ?', { orgName })
        MySQL.update.await('DELETE FROM bossmenu_hidden_workshop_profiles WHERE gang_name = ?', { orgName })
        invalidateOrganizationCaches('gang', orgName)
        adminLog(op, orgType, orgName, nil, { confirm = true })
        emitHook('admin_internal_gang_deleted', { orgName = orgName, actor = context.player.identifier })
        return true
    end
    if op == 'suspicious' then
        local rows = MySQL.query.await([[SELECT id, action, actor_identifier, payload, created_at
            FROM bossmenu_audit
            WHERE (COALESCE(org_type, '') = 'security' OR action LIKE 'suspicious_%')
            ORDER BY id DESC
            LIMIT ?]], { safeNumber(payload.limit, 1, 500) or 100 }) or {}
        for i = 1, #rows do
            rows[i].payload = decodeJson(rows[i].payload) or {}
        end
        return true, { suspicious = rows }
    end
    if op == 'export_logs' then
        local rows = AuditModule and AuditModule.GetLogs and AuditModule.GetLogs({
            orgName = orgName ~= '' and orgName or nil,
            action = cleanText(payload.action, 64),
            actor = cleanText(payload.actor, 80),
            target = cleanText(payload.target, 80),
            dateFrom = cleanText(payload.dateFrom, 32),
            dateTo = cleanText(payload.dateTo, 32),
            limit = safeNumber(payload.limit, 1, 1000) or 500
        }) or {}
        return true, { logs = rows }
    end
    return false, 'Invalid admin action'
end

local function actionTaxes(context, payload)
    if not isModuleEnabled('Taxes') then
        return false, 'Taxes disabled'
    end
    if not hasContextPermission(context, 'manage_taxes') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    local mode = cleanText(payload and payload.mode, 24)
    if mode == 'get' then
        return true, { tax = FinanceModule.GetTaxAccount(orgType, context.role.name) }
    end
    if mode == 'pay' then
        local ok, dataOrErr = FinanceModule.PayTaxDue(orgType, context.role.name, payload or {}, context.player.identifier)
        if not ok then
            return false, dataOrErr
        end
        return true, dataOrErr
    end
    local ok, err = FinanceModule.SetTaxAccount(orgType, context.role.name, payload or {}, context.player.identifier)
    if not ok then return false, err end
    return true, { ok = true, tax = FinanceModule.GetTaxAccount(orgType, context.role.name) }
end

local function actionTaxesGet(context)
    if not isModuleEnabled('Taxes') then
        return false, 'Taxes disabled'
    end
    if not hasContextPermission(context, 'manage_taxes') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    return true, { tax = FinanceModule.GetTaxAccount(orgType, context.role.name) }
end

local function actionInvoices(context, payload, op)
    if not isModuleEnabled('BillsInvoices') then
        return false, 'Bills/Invoices disabled'
    end
    if not hasContextPermission(context, 'manage_bills') then
        return false, 'No permission'
    end
    local orgType = getOrgTypeByMenu(context.menuType)
    if op == 'list' then
        return true, {
            invoices = FinanceModule.ListInvoices(orgType, context.role.name, payload and payload.status, payload and payload.limit)
        }
    end
    if op == 'create' then
        return FinanceModule.CreateInvoice(orgType, context.role.name, payload or {}, context.player.identifier)
    end
    return FinanceModule.UpdateInvoiceStatus(
        orgType,
        context.role.name,
        payload and payload.id,
        payload and payload.status,
        context.player.identifier,
        payload and payload.note
    )
end

local function actionAnalytics(context)
    if not isModuleEnabled('Analytics') then
        return false, 'Analytics disabled'
    end
    if not hasContextPermission(context, 'view_analytics') and not hasContextPermission(context, 'view_activity_logs') then
        return false, 'No permission'
    end
    local employees = getEmployeesForRole(context.menuType, context.role.name)
    local online = 0
    for _, row in ipairs(employees) do
        if row.online then online = online + 1 end
    end
    local auditRows = MySQL.query.await([[SELECT action, COUNT(*) AS total
        FROM bossmenu_audit
        WHERE job = ?
        GROUP BY action
        ORDER BY total DESC
        LIMIT 20]], { context.role.name }) or {}
    local financeTotalsRows = MySQL.query.await([[SELECT action, COALESCE(SUM(amount), 0) AS total
        FROM bossmenu_ledger
        WHERE job = ?
        GROUP BY action]], { context.role.name }) or {}

    local financeTotals = { deposits = 0, withdrawals = 0, net = 0 }
    for i = 1, #financeTotalsRows do
        local action = tostring(financeTotalsRows[i].action or '')
        local total = tonumber(financeTotalsRows[i].total) or 0
        if action == 'deposit' or action == 'api_deposit' then
            financeTotals.deposits = financeTotals.deposits + total
        elseif action == 'withdraw' or action == 'api_withdraw' then
            financeTotals.withdrawals = financeTotals.withdrawals + total
        end
    end
    financeTotals.net = financeTotals.deposits - financeTotals.withdrawals

    local trendActions = MySQL.query.await([[SELECT DATE(created_at) AS day, action, COUNT(*) AS total
        FROM bossmenu_audit
        WHERE COALESCE(org_name, job) = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
        GROUP BY DATE(created_at), action
        ORDER BY day ASC]], { context.role.name }) or {}
    local trendFinance = MySQL.query.await([[SELECT DATE(created_at) AS day,
            COALESCE(SUM(CASE WHEN action IN ('deposit','api_deposit') THEN amount ELSE 0 END), 0) AS deposits,
            COALESCE(SUM(CASE WHEN action IN ('withdraw','api_withdraw') THEN amount ELSE 0 END), 0) AS withdrawals
        FROM bossmenu_ledger
        WHERE job = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
        GROUP BY DATE(created_at)
        ORDER BY day ASC]], { context.role.name }) or {}
    local payrollTotals = MySQL.single.await([[SELECT
            COALESCE(SUM(total_amount),0) AS total,
            COALESCE(SUM(paid_count),0) AS paid_count,
            COALESCE(SUM(failed_count),0) AS failed_count
        FROM bossmenu_payroll_runs
        WHERE org_type = ? AND org_name = ?]], {
        getOrgTypeByMenu(context.menuType),
        context.role.name
    }) or { total = 0, paid_count = 0, failed_count = 0 }
    local inventoryMovement = MySQL.query.await([[SELECT action, COALESCE(SUM(amount),0) AS total
        FROM bossmenu_org_inventory_logs
        WHERE org_type = ? AND org_name = ?
        GROUP BY action]], {
        getOrgTypeByMenu(context.menuType),
        context.role.name
    }) or {}
    local topActive = MySQL.query.await([[SELECT identifier, COUNT(*) AS actions
        FROM bossmenu_employee_activity
        WHERE org_type = ? AND org_name = ?
        GROUP BY identifier
        ORDER BY actions DESC
        LIMIT 10]], {
        getOrgTypeByMenu(context.menuType),
        context.role.name
    }) or {}
    local suspicious = MySQL.query.await([[SELECT id, action, actor_identifier, created_at
        FROM bossmenu_audit
        WHERE (COALESCE(org_type, '') = 'security' OR action LIKE 'suspicious_%')
          AND created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
        ORDER BY id DESC
        LIMIT 30]]) or {}

    local gangExtra = nil
    if context.menuType == 'gang' then
        local notoriety = GangsModule.GetNotoriety(context.role.name)
        local territoryCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bossmenu_gang_territories WHERE owner_gang = ?', { context.role.name }) or 0) or 0
        local racketIncome = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(stored_income),0) FROM bossmenu_gang_rackets WHERE gang_name = ?', { context.role.name }) or 0) or 0
        local graffitiCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bossmenu_gang_graffiti WHERE gang_name = ?', { context.role.name }) or 0) or 0
        local contractCompletions = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM bossmenu_gang_contracts WHERE gang_name = ? AND status = 'completed'", { context.role.name }) or 0) or 0
        local workshop = HiddenWorkshopModule and HiddenWorkshopModule.IsEnabled and HiddenWorkshopModule.IsEnabled()
            and MySQL.single.await([[SELECT reputation, level, jobs_completed, jobs_failed, early_cashouts, cars_stripped, total_cash_earned, total_parts_earned, heat
                FROM bossmenu_hidden_workshop_profiles
                WHERE gang_name = ?
                LIMIT 1]], { context.role.name })
            or nil
        gangExtra = {
            notoriety = notoriety,
            territoryCount = territoryCount,
            racketIncome = racketIncome,
            graffitiCount = graffitiCount,
            contractCompletions = contractCompletions,
            hiddenWorkshop = workshop and {
                reputation = tonumber(workshop.reputation) or 0,
                level = tonumber(workshop.level) or 1,
                jobsCompleted = tonumber(workshop.jobs_completed) or 0,
                jobsFailed = tonumber(workshop.jobs_failed) or 0,
                earlyCashouts = tonumber(workshop.early_cashouts) or 0,
                carsStripped = tonumber(workshop.cars_stripped) or 0,
                totalCashEarned = tonumber(workshop.total_cash_earned) or 0,
                totalPartsEarned = tonumber(workshop.total_parts_earned) or 0,
                heat = tonumber(workshop.heat) or 0
            } or nil
        }
    end

    return true, {
        employees = { total = #employees, online = online, offline = #employees - online },
        actions = auditRows,
        finance = financeTotals,
        trends = {
            actions = trendActions,
            finance = trendFinance
        },
        payroll = {
            total = tonumber(payrollTotals.total) or 0,
            paidCount = tonumber(payrollTotals.paid_count) or 0,
            failedCount = tonumber(payrollTotals.failed_count) or 0
        },
        inventory = inventoryMovement,
        topActive = topActive,
        suspicious = suspicious,
        gang = gangExtra
    }
end

local function actionAuditLogs(context, payload)
    local canView = hasContextPermission(context, 'view_ledger')
        or hasContextPermission(context, 'view_activity_logs')
        or hasContextPermission(context, 'view_analytics')
    if not canView then
        return false, 'No permission'
    end
    if not AuditModule or not AuditModule.GetLogs then
        return false, 'Audit module unavailable'
    end
    payload = type(payload) == 'table' and payload or {}
    payload.orgName = context.role.name
    local rows = AuditModule.GetLogs(payload)
    return true, { logs = rows }
end

local function actionWebhookSettings(context, payload, op)
    if not isModuleEnabled('Webhooks') then
        return false, 'Webhooks disabled'
    end
    if not AuditModule or not AuditModule.GetWebhookSettings then
        return false, 'Webhook module unavailable'
    end
    if not hasContextPermission(context, 'manage_webhooks') then
        return false, 'No permission'
    end

    local orgType = getOrgTypeByMenu(context.menuType)
    if op == 'get' then
        return true, {
            categories = AuditModule.GetWebhookCategories and AuditModule.GetWebhookCategories() or {},
            settings = AuditModule.GetWebhookSettings('org', orgType, context.role.name)
        }
    end

    if op == 'save' then
        payload = type(payload) == 'table' and payload or {}
        local ok, err = AuditModule.SaveWebhookSetting(
            'org',
            orgType,
            context.role.name,
            payload.category,
            payload.webhookUrl,
            payload.enabled == true,
            context.player.identifier
        )
        if not ok then
            return false, err
        end
        addAudit(context.role.name, context.menuType .. '_webhook_setting_saved', context.player.identifier, nil, {
            category = cleanText(payload.category, 32),
            enabled = payload.enabled == true,
            hasUrl = cleanText(payload.webhookUrl, 600) ~= ''
        })
        return true, {
            categories = AuditModule.GetWebhookCategories and AuditModule.GetWebhookCategories() or {},
            settings = AuditModule.GetWebhookSettings('org', orgType, context.role.name)
        }
    end

    return false, 'Invalid webhook action'
end

local function actionGangNotoriety(context, payload)
    if context.menuType ~= 'gang' then
        return false, 'Gang only action'
    end
    if not isModuleEnabled('GangNotoriety') then
        return false, 'Gang notoriety disabled'
    end
    if payload and payload.mode == 'set' then
        if not hasContextPermission(context, 'view_notoriety') then
            return false, 'No permission'
        end
        return GangsModule.ModifyNotoriety(context.role.name, tonumber(payload.amount) or 0, payload.reason, context.player.identifier)
    end
    return true, GangsModule.GetNotoriety(context.role.name)
end

local function actionGangMarker(context, payload, op)
    if context.menuType ~= 'gang' then
        return false, 'Gang only action'
    end
    if not isModuleEnabled('GangMarkers') then
        return false, 'Gang markers disabled'
    end
    if not hasContextPermission(context, 'manage_markers') then
        return false, 'No permission'
    end
    if op == 'list' then
        return true, { markers = GangsModule.ListMarkers(context.role.name) }
    end
    if op == 'delete' then
        return GangsModule.DeleteMarker(context.role.name, payload and payload.id, context.player.identifier)
    end
    return GangsModule.UpsertMarker(context.role.name, payload or {}, context.player.identifier)
end

local function actionTerritory(context, payload, op, src)
    if context.menuType ~= 'gang' then
        return false, 'Gang only action'
    end
    if not isModuleEnabled('GangTerritories') then
        return false, 'Territories disabled'
    end
    if op == 'list' then
        return true, {
            territories = TerritoriesModule.List(context.role.name),
            leaderboard = TerritoriesModule.Leaderboard()
        }
    end
    if not hasContextPermission(context, 'manage_territories') then
        return false, 'No permission'
    end
    if op == 'begin' then
        return TerritoriesModule.BeginCapture(context.role.name, payload or {}, context.player.identifier, src)
    end
    local ok, dataOrErr = TerritoriesModule.CompleteCapture(context.role.name, payload or {}, context.player.identifier, src)
    if not ok then
        return false, dataOrErr
    end
    local data = type(dataOrErr) == 'table' and dataOrErr or {}
    local reward = safeNumber(data.reward, 0, maxMoneyAmount()) or 0
    local penalty = safeNumber(data.penalty, 0, maxMoneyAmount()) or 0
    if reward > 0 then
        ensureAccount(context.role.name)
        MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { reward, context.role.name })
        mirrorSocietyMoney(context.role.name, reward, 'add', 'territory_capture_reward')
        addLedger(context.role.name, 'territory_reward', reward, context.player.identifier, nil, 'Territory capture reward')
    end
    local prevOwner = cleanText(data.previousOwner, 64)
    if prevOwner ~= '' and penalty > 0 then
        ensureAccount(prevOwner)
        MySQL.update.await('UPDATE bossmenu_accounts SET balance = GREATEST(balance - ?, 0) WHERE job = ?', { penalty, prevOwner })
        mirrorSocietyMoney(prevOwner, penalty, 'remove', 'territory_loss_penalty')
        addLedger(prevOwner, 'territory_penalty', penalty, context.player.identifier, context.role.name, 'Territory loss penalty')
    end
    return true, {
        capture = data,
        territories = TerritoriesModule.List(context.role.name),
        leaderboard = TerritoriesModule.Leaderboard(),
        balance = getBalance(context.role.name)
    }
end

local function actionContract(context, payload, op)
    if context.menuType ~= 'gang' then
        return false, 'Gang only action'
    end
    if not isModuleEnabled('GangContracts') then
        return false, 'Contracts disabled'
    end
    if op == 'list' then
        return true, { contracts = ContractsModule.List(context.role.name, payload and payload.status) }
    end
    if not hasContextPermission(context, 'accept_contracts') then
        return false, 'No permission'
    end
    if op == 'create' then
        return ContractsModule.Create(context.role.name, payload or {}, context.player.identifier)
    end
    if op == 'accept' then
        return ContractsModule.Accept(context.role.name, payload and payload.id, context.player.identifier)
    end
    if op == 'complete' then
        local ok, dataOrErr = ContractsModule.Complete(context.role.name, payload and payload.id, context.player.identifier, payload and payload.success ~= false)
        if not ok then
            return false, dataOrErr
        end
        local result = type(dataOrErr) == 'table' and dataOrErr or {}
        if result.status == 'completed' then
            local reward = type(result.reward) == 'table' and result.reward or {}
            local money = safeNumber(reward.money, 0, maxMoneyAmount()) or 0
            local notoriety = safeNumber(reward.notoriety, 0, 1000000) or 0
            if money > 0 then
                ensureAccount(context.role.name)
                MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { money, context.role.name })
                mirrorSocietyMoney(context.role.name, money, 'add', 'gang_contract_reward')
                addLedger(context.role.name, 'contract_reward', money, context.player.identifier, nil, 'Gang contract reward')
            end
            if notoriety > 0 and GangsModule.IsNotorietyEnabled() then
                GangsModule.ModifyNotoriety(context.role.name, notoriety, 'contract_reward', context.player.identifier)
            end
            result.balance = getBalance(context.role.name)
        end
        return true, result
    end
    return false, 'Invalid contract action'
end

local function actionWorkshop(context, payload, op)
    if context.menuType ~= 'gang' then
        return false, 'Gang only action'
    end
    if not HiddenWorkshopModule or not HiddenWorkshopModule.IsEnabled or not HiddenWorkshopModule.IsEnabled() then
        return false, 'Hidden workshop disabled'
    end
    if not hasContextPermission(context, 'manage_hidden_workshop') then
        return false, 'No permission'
    end

    if op == 'overview' then
        return true, HiddenWorkshopModule.GetState(context.role.name)
    end
    if op == 'create' then
        return HiddenWorkshopModule.Create(context.role.name, payload or {}, context.player.identifier)
    end
    if op == 'accept' then
        return HiddenWorkshopModule.Accept(context.role.name, payload and payload.id, context.player.identifier)
    end
    if op == 'progress' then
        return HiddenWorkshopModule.Progress(context.role.name, payload and payload.id, context.player.identifier, payload or {})
    end
    if op == 'cashout' then
        local ok, dataOrErr = HiddenWorkshopModule.EarlyCashout(context.role.name, payload and payload.id, context.player.identifier)
        if not ok then
            return false, dataOrErr
        end
        local result = type(dataOrErr) == 'table' and dataOrErr or {}
        local reward = type(result.reward) == 'table' and result.reward or {}
        local accountMoney = safeNumber(reward.accountMoney, 0, maxMoneyAmount()) or 0
        if accountMoney > 0 then
            ensureAccount(context.role.name)
            MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { accountMoney, context.role.name })
            mirrorSocietyMoney(context.role.name, accountMoney, 'add', 'hidden_workshop_cashout')
            addLedger(context.role.name, 'hidden_workshop_cashout', accountMoney, context.player.identifier, nil, 'Hidden workshop early cashout')
        end
        result.balance = getBalance(context.role.name)
        return true, result
    end
    if op == 'complete' then
        local ok, dataOrErr = HiddenWorkshopModule.Complete(context.role.name, payload and payload.id, context.player.identifier)
        if not ok then
            return false, dataOrErr
        end
        local result = type(dataOrErr) == 'table' and dataOrErr or {}
        local reward = type(result.reward) == 'table' and result.reward or {}
        local accountMoney = safeNumber(reward.accountMoney, 0, maxMoneyAmount()) or 0
        if accountMoney > 0 then
            ensureAccount(context.role.name)
            MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { accountMoney, context.role.name })
            mirrorSocietyMoney(context.role.name, accountMoney, 'add', 'hidden_workshop_payout')
            addLedger(context.role.name, 'hidden_workshop_payout', accountMoney, context.player.identifier, nil, 'Hidden workshop payout')
        end
        result.balance = getBalance(context.role.name)
        return true, result
    end
    if op == 'fail' then
        return HiddenWorkshopModule.Fail(context.role.name, payload and payload.id, context.player.identifier, payload and payload.reason)
    end
    return false, 'Invalid workshop action'
end

local function actionRacket(context, payload, op)
    if context.menuType ~= 'gang' then
        return false, 'Gang only action'
    end
    if not isModuleEnabled('GangRackets') then
        return false, 'Rackets disabled'
    end
    if op == 'list' then
        GangsModule.TickRackets()
        return true, { rackets = GangsModule.ListRackets(context.role.name) }
    end
    if not hasContextPermission(context, 'start_rackets') then
        return false, 'No permission'
    end
    if op == 'upsert' then
        return GangsModule.UpsertRacket(context.role.name, payload or {}, context.player.identifier)
    end
    if op == 'upgrade' then
        local upgradeType = cleanText(payload and payload.upgradeType, 32)
        local racketId = safeNumber(payload and payload.id, 1)
        if not racketId or upgradeType == '' then
            return false, 'Invalid upgrade payload'
        end
        local moneyCost = safeNumber(payload and payload.moneyCost, 0, maxMoneyAmount()) or 0
        local notorietyCost = safeNumber(payload and payload.notorietyCost, 0, 1000000) or 0
        if notorietyCost > 0 and GangsModule.IsNotorietyEnabled() then
            local current = GangsModule.GetNotoriety(context.role.name)
            if tonumber(current.points or 0) < notorietyCost then
                return false, 'Not enough notoriety'
            end
        end
        if moneyCost > 0 then
            ensureAccount(context.role.name)
            local affected = MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance - ? WHERE job = ? AND balance >= ?', {
                moneyCost, context.role.name, moneyCost
            })
            if (affected or 0) < 1 then
                return false, 'Insufficient gang funds'
            end
            mirrorSocietyMoney(context.role.name, moneyCost, 'remove', 'racket_upgrade_cost')
            addLedger(context.role.name, 'racket_upgrade_cost', moneyCost, context.player.identifier, nil, upgradeType)
        end
        if notorietyCost > 0 and GangsModule.IsNotorietyEnabled() then
            GangsModule.ModifyNotoriety(context.role.name, -notorietyCost, 'racket_upgrade', context.player.identifier)
        end
        local ok, dataOrErr = GangsModule.UpgradeRacket(context.role.name, racketId, upgradeType, context.player.identifier)
        if not ok then
            return false, dataOrErr
        end
        return true, {
            upgrade = dataOrErr,
            rackets = GangsModule.ListRackets(context.role.name),
            balance = getBalance(context.role.name)
        }
    end
    if op == 'claim' then
        local ok, dataOrErr = GangsModule.ClaimRacketIncome(context.role.name, payload and payload.id, context.player.identifier)
        if not ok then return false, dataOrErr end
        if dataOrErr and tonumber(dataOrErr.amount or 0) > 0 then
            ensureAccount(context.role.name)
            MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', {
                tonumber(dataOrErr.amount), context.role.name
            })
            mirrorSocietyMoney(context.role.name, tonumber(dataOrErr.amount), 'add', 'gang_racket_income')
            addLedger(context.role.name, 'racket_income', tonumber(dataOrErr.amount), context.player.identifier, nil, 'Racket income claim')
        end
        return true, {
            payout = dataOrErr,
            rackets = GangsModule.ListRackets(context.role.name),
            balance = getBalance(context.role.name)
        }
    end
    return false, 'Invalid racket action'
end

local function actionGraffiti(context, payload, op, src)
    if context.menuType ~= 'gang' then
        return false, 'Gang only action'
    end
    if not isModuleEnabled('GangGraffiti') then
        return false, 'Graffiti disabled'
    end
    if op == 'list' then
        return true, { graffiti = GangsModule.ListGraffiti(context.role.name) }
    end
    if not hasContextPermission(context, 'manage_graffiti') then
        return false, 'No permission'
    end
    if op == 'place' then
        local ok, dataOrErr = GangsModule.PlaceGraffiti(context.role.name, payload or {}, context.player.identifier, src)
        if not ok then
            return false, dataOrErr
        end
        local placed = dataOrErr
        TriggerClientEvent('qb-management:client:worldGraffitiUpsert', -1, placed)

        local territoryAuto = nil
        if TerritoriesModule and TerritoriesModule.TryAutoClaimFromGraffiti and isModuleEnabled('GangTerritories') then
            local tOk, tDataOrErr = TerritoriesModule.TryAutoClaimFromGraffiti(context.role.name, context.player.identifier, src, payload or {})
            if tOk then
                territoryAuto = tDataOrErr
            end
        end
        return true, {
            graffiti = placed,
            territoryAuto = territoryAuto
        }
    end
    if op == 'delete' then
        local allowCrossGang = payload and payload.allowCrossGangClean == true
        local ok, dataOrErr = GangsModule.DeleteGraffiti(context.role.name, payload and payload.id, context.player.identifier, src, allowCrossGang)
        if not ok then
            return false, dataOrErr
        end
        TriggerClientEvent('qb-management:client:worldGraffitiRemove', -1, {
            id = dataOrErr and dataOrErr.id
        })
        return true, dataOrErr
    end
    return false, 'Invalid graffiti action'
end

local function actionCameraList(context)
    if not cameraModuleEnabled() then
        return false, 'Cameras module disabled'
    end
    if not hasContextPermission(context, 'view_cameras') and not hasContextPermission(context, 'view_analytics') then
        return false, 'No permission'
    end

    local grades = getRoleGrades(context.menuType, context.role.name)
    local profile = inferOrgProfile(context.menuType, context.role.name, context.role.label, grades)
    local archetypeId = profile and profile.id or 'corporate'
    if not canUseArchetypeCameras(archetypeId) then
        return true, { provider = 'none', archetype = archetypeId, feeds = {} }
    end

    local feeds = resolveCameraFeeds(context, archetypeId)
    local provider = resolveCameraProvider(context, archetypeId)
    return true, {
        provider = provider,
        archetype = archetypeId,
        feeds = feeds
    }
end

local function actionCameraOpen(context, payload, src)
    if not cameraModuleEnabled() then
        return false, 'Cameras module disabled'
    end
    if not hasContextPermission(context, 'view_cameras') and not hasContextPermission(context, 'view_analytics') then
        return false, 'No permission'
    end

    local ok, list = actionCameraList(context)
    if not ok then return false, list end
    local feedId = cleanText(payload and payload.id, 64)
    if feedId == '' then
        return false, 'Invalid camera id'
    end

    local selected = nil
    local feeds = type(list.feeds) == 'table' and list.feeds or {}
    for i = 1, #feeds do
        if tostring(feeds[i].id) == feedId then
            selected = feeds[i]
            break
        end
    end
    if not selected then
        return false, 'Camera not found'
    end

    local provider = tostring(list.provider or 'none')
    if provider == 'none' then
        return false, 'No camera provider configured'
    end

    TriggerClientEvent('qb-management:client:openCamera', src, {
        provider = provider,
        feed = selected,
        closeMenu = getCameraConfig().closeMenuOnOpen == true
    })

    addAudit(context.role.name, context.menuType .. '_camera_open', context.player.identifier, nil, {
        provider = provider,
        id = selected.id,
        label = selected.label
    })
    emitHook('camera_opened', {
        orgType = context.menuType,
        orgName = context.role.name,
        actor = context.player.identifier,
        provider = provider,
        cameraId = selected.id
    })

    return true, {
        opened = true,
        provider = provider,
        id = selected.id
    }
end

local function openPayload(src, payload)
    local menuType = getMenuType(payload and payload.menuType)
    local context, err = getContextFromPlayer(src, menuType)
    if not context then return false, err end

    local token = createSession(src, menuType, context.role.name)
    local out = buildOpenPayload(context)
    out.token = token
    out.employees = getEmployeesForRole(menuType, context.role.name)
    out.nearby = getNearbyPlayers(src)

    if menuType == 'gang' and usingCustomGangBackend() then
        syncCustomGangToClientBySource(src)
    end

    emitHook(menuType == 'gang' and 'gang_menu_opened' or 'boss_menu_opened', {
        menuType = menuType,
        role = context.role.name,
        actor = context.player.identifier
    })

    return true, out
end

local Handlers = {
    open = function(src, payload)
        return openPayload(src, payload)
    end,
    close = function(src)
        Sessions[src] = nil
        return true, { ok = true }
    end,
    refresh = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionRefresh(context, src)
    end,
    hire = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionHire(context, payload, src)
    end,
    set_grade = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionSetGrade(context, payload)
    end,
    fire = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionFire(context, payload)
    end,
    deposit = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionDeposit(context, payload)
    end,
    withdraw = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWithdraw(context, payload)
    end,
    get_ranks = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGetRanks(context)
    end,
    create_rank = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionCreateRank(context, payload)
    end,
    update_rank = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUpdateRank(context, payload)
    end,
    delete_rank = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionDeleteRank(context, payload)
    end,
    reassign_rank = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionReassignRank(context, payload)
    end,
    get_rank_permissions = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGetRankPermissions(context, payload)
    end,
    set_rank_permission = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionSetRankPermission(context, payload)
    end,
    get_member_profile = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGetMemberProfile(context, payload)
    end,
    update_member_profile = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUpdateMemberProfile(context, payload)
    end,
    generate_member_profile_image = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGenerateMemberProfileImage(context, payload)
    end,
    update_member_strikes = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUpdateStrikes(context, payload)
    end,
    search_members = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionSearchMembers(context, payload)
    end,
    set_salary = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionSetSalary(context, payload)
    end,
    run_payroll = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionRunPayroll(context)
    end,
    inventory_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionInventoryList(context)
    end,
    inventory_deposit = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionInventoryModify(context, payload, 'deposit')
    end,
    inventory_withdraw = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionInventoryModify(context, payload, 'withdraw')
    end,
    stash_open = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionOpenBossStash(context, src)
    end,
    uniforms_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUniforms(context, payload, 'list')
    end,
    uniforms_save = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUniforms(context, payload, 'save')
    end,
    uniforms_delete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUniforms(context, payload, 'delete')
    end,
    uniforms_apply = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUniforms(context, payload, 'apply')
    end,
    uniforms_preview = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUniforms(context, payload, 'preview')
    end,
    uniforms_restore = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionUniforms(context, payload, 'restore')
    end,
    applications_submit = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionApplications(context, payload, 'submit')
    end,
    applications_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionApplications(context, payload, 'list')
    end,
    applications_decide = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionApplications(context, payload, 'decide')
    end,
    announcements_create = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionCreateAnnouncement(context, payload)
    end,
    announcements_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionListAnnouncements(context)
    end,
    camera_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionCameraList(context)
    end,
    camera_open = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionCameraOpen(context, payload, src)
    end,
    org_markers_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionOrgMarkers(context, payload, 'list')
    end,
    org_markers_upsert = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionOrgMarkers(context, payload, 'upsert')
    end,
    org_markers_delete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionOrgMarkers(context, payload, 'delete')
    end,
    org_garages_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionOrgGarages(context, payload, 'list')
    end,
    org_garages_upsert = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionOrgGarages(context, payload, 'upsert')
    end,
    org_garages_delete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionOrgGarages(context, payload, 'delete')
    end,
    admin_list_orgs = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'list_orgs')
    end,
    admin_add_funds = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'add_funds')
    end,
    admin_remove_funds = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'remove_funds')
    end,
    admin_actions = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'actions')
    end,
    admin_disable_org = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'disable_org')
    end,
    admin_enable_org = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'enable_org')
    end,
    admin_force_add_member = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'force_add_member')
    end,
    admin_force_remove_member = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'force_remove_member')
    end,
    admin_force_set_grade = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'force_set_grade')
    end,
    admin_change_leader = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'change_leader')
    end,
    admin_delete_internal_gang = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'delete_internal_gang')
    end,
    admin_suspicious = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'suspicious')
    end,
    admin_export_logs = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'export_logs')
    end,
    admin_webhooks_get = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'webhooks_get')
    end,
    admin_webhooks_save = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAdmin(context, payload, 'webhooks_save')
    end,
    taxes_set = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionTaxes(context, payload)
    end,
    taxes_get = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionTaxesGet(context)
    end,
    taxes_pay = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        local p = type(payload) == 'table' and payload or {}
        p.mode = 'pay'
        return actionTaxes(context, p)
    end,
    invoice_create = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionInvoices(context, payload, 'create')
    end,
    invoice_status = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionInvoices(context, payload, 'status')
    end,
    invoice_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionInvoices(context, payload, 'list')
    end,
    analytics = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAnalytics(context)
    end,
    audit_logs = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionAuditLogs(context, payload)
    end,
    webhook_settings_get = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWebhookSettings(context, payload, 'get')
    end,
    webhook_settings_save = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWebhookSettings(context, payload, 'save')
    end,
    gang_notoriety = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGangNotoriety(context, payload)
    end,
    gang_marker_upsert = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGangMarker(context, payload, 'upsert')
    end,
    gang_marker_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGangMarker(context, payload, 'list')
    end,
    gang_marker_delete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGangMarker(context, payload, 'delete')
    end,
    territory_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionTerritory(context, payload, 'list', src)
    end,
    territory_begin = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionTerritory(context, payload, 'begin', src)
    end,
    territory_complete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionTerritory(context, payload, 'complete', src)
    end,
    contracts_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionContract(context, payload, 'list')
    end,
    contracts_create = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionContract(context, payload, 'create')
    end,
    contracts_accept = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionContract(context, payload, 'accept')
    end,
    contracts_complete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionContract(context, payload, 'complete')
    end,
    workshop_overview = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWorkshop(context, payload, 'overview')
    end,
    workshop_create = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWorkshop(context, payload, 'create')
    end,
    workshop_accept = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWorkshop(context, payload, 'accept')
    end,
    workshop_progress = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWorkshop(context, payload, 'progress')
    end,
    workshop_cashout = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWorkshop(context, payload, 'cashout')
    end,
    workshop_complete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWorkshop(context, payload, 'complete')
    end,
    workshop_fail = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionWorkshop(context, payload, 'fail')
    end,
    rackets_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionRacket(context, payload, 'list')
    end,
    rackets_upsert = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionRacket(context, payload, 'upsert')
    end,
    rackets_upgrade = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionRacket(context, payload, 'upgrade')
    end,
    rackets_claim = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionRacket(context, payload, 'claim')
    end,
    graffiti_list = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGraffiti(context, payload, 'list')
    end,
    graffiti_place = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGraffiti(context, payload, 'place', src)
    end,
    graffiti_delete = function(src, payload, token)
        local context, err = getContextFromSession(src, token)
        if not context then return false, err end
        return actionGraffiti(context, payload, 'delete')
    end
}

local function flagSuspicious(src, action, reason, payload)
    if SecurityModule and SecurityModule.RecordFailure then
        SecurityModule.RecordFailure(src, ('%s:%s'):format(action or 'unknown', reason or 'unknown'))
    end
    addAudit('security', 'suspicious_' .. tostring(action or 'unknown'), tostring(src), nil, {
        reason = reason,
        payload = payload
    })
    emitHook('suspicious_action', {
        source = src,
        action = action,
        reason = reason
    })
end

RegisterNetEvent('qb-management:server:rpc', function(requestId, action, payload, token)
    local src = source
    local nonceWindowMs = (tonumber(Config.Security and Config.Security.nonceTtlSeconds or 30) or 30) * 1000
    local function respond(ok, data, err)
        TriggerClientEvent('qb-management:client:rpcResponse', src, requestId, ok, data, err)
    end

    if type(requestId) ~= 'number' or requestId < 1 then
        return
    end

    if BrahBossmenuRuntimeReady ~= true then
        respond(false, nil, 'Resource initializing')
        return
    end

    local seen = SeenRequests[src]
    local now = nowMs()
    if not seen then
        seen = { map = {}, pruneAt = now + nonceWindowMs }
        SeenRequests[src] = seen
    end
    if seen.map[requestId] and now - seen.map[requestId] < nonceWindowMs then
        flagSuspicious(src, action, 'replay_request_id', { requestId = requestId })
        respond(false, nil, 'Duplicate request')
        return
    end
    seen.map[requestId] = now
    if now > seen.pruneAt then
        local cut = now - nonceWindowMs
        for id, ts in pairs(seen.map) do
            if ts < cut then
                seen.map[id] = nil
            end
        end
        seen.pruneAt = now + nonceWindowMs
    end

    action = tostring(action or '')
    if action == '' or not Handlers[action] then
        flagSuspicious(src, action, 'unknown_action', payload)
        respond(false, nil, 'Unknown action')
        return
    end

    if SecurityModule and SecurityModule.IsLocked then
        local locked, remaining = SecurityModule.IsLocked(src)
        if locked then
            respond(false, nil, ('Temporarily locked (%ss)'):format(remaining))
            return
        end
    end

    if not rateCheck(src, action) then
        flagSuspicious(src, action, 'rate_limited', nil)
        respond(false, nil, 'Rate limited')
        return
    end

    local ok, success, dataOrErr = pcall(Handlers[action], src, payload, token)
    if not ok then
        print(('[%s] rpc error on %s from %s: %s'):format(resource, action, src, tostring(success)))
        respond(false, nil, 'Internal error')
        return
    end

    if success then
        if SecurityModule and SecurityModule.ClearFailure then
            SecurityModule.ClearFailure(src)
        end
        respond(true, dataOrErr, nil)
    else
        local reason = tostring(dataOrErr or 'Action failed')
        if reason == 'No permission' or reason == 'Invalid session' or reason == 'Organization mismatch' then
            flagSuspicious(src, action, reason, payload)
        end
        if action == 'deposit' or action == 'withdraw' then
            local amount = tonumber(payload and payload.amount) or 0
            local threshold = tonumber(Config.Security and Config.Security.largeWithdrawThreshold or 250000) or 250000
            if amount > threshold * 4 then
                flagSuspicious(src, action, 'huge_money_attempt', { amount = amount })
            end
        end
        respond(false, nil, dataOrErr or 'Action failed')
    end
end)

RegisterNetEvent('qb-management:server:profileCapturePrepared', function(requestId, prepared)
    -- Backward-compat noop for older clients. New flow uses profileCaptureData.
    local src = source
    local reqId = cleanText(requestId, 80)
    local req = ProfileImageRequests[reqId]
    if not req then
        return
    end
    if tonumber(req.targetSource) ~= tonumber(src) then
        return
    end
    if prepared ~= true then
        ProfileImageRequests[reqId] = nil
        TriggerClientEvent('qb-management:client:finishProfileCapture', src, reqId)
        TriggerClientEvent('qb-management:client:profileCaptureResult', req.actorSource, {
            ok = false,
            identifier = req.targetIdentifier,
            error = 'Capture cancelled'
        })
    end
end)

RegisterNetEvent('qb-management:server:profileCaptureData', function(requestId, data, providerName, errorReason)
    local src = source
    local reqId = cleanText(requestId, 80)
    local req = ProfileImageRequests[reqId]
    if not req then
        flagSuspicious(src, 'profile_capture', 'unknown_capture_request', { requestId = reqId })
        return
    end

    if tonumber(req.targetSource) ~= tonumber(src) then
        flagSuspicious(src, 'profile_capture', 'capture_source_mismatch', {
            requestId = reqId,
            expected = req.targetSource
        })
        return
    end

    if nowMs() > (req.expiresAt or 0) then
        ProfileImageRequests[reqId] = nil
        TriggerClientEvent('qb-management:client:finishProfileCapture', src, reqId)
        return
    end

    TriggerClientEvent('qb-management:client:finishProfileCapture', src, reqId)

    if type(data) ~= 'string' or data == '' then
        ProfileImageRequests[reqId] = nil
        TriggerClientEvent('qb-management:client:profileCaptureResult', req.actorSource, {
            ok = false,
            identifier = req.targetIdentifier,
            error = cleanText(errorReason, 120) ~= '' and cleanText(errorReason, 120) or 'Capture failed'
        })
        return
    end

    local pending = ProfileImageRequests[reqId]
    ProfileImageRequests[reqId] = nil
    if not pending then
        return
    end

    local photoData = tostring(data or '')
    if not photoData:find('^data:image/') then
        TriggerClientEvent('qb-management:client:profileCaptureResult', pending.actorSource, {
            ok = false,
            identifier = pending.targetIdentifier,
            error = 'Screenshot data unavailable'
        })
        return
    end

    local maxBytes = tonumber((getScreenshotConfig() or {}).maxBytes) or 1800000
    if #photoData > maxBytes then
        TriggerClientEvent('qb-management:client:profileCaptureResult', pending.actorSource, {
            ok = false,
            identifier = pending.targetIdentifier,
            error = 'Captured image too large for profile storage'
        })
        return
    end

    local current = EmployeesModule.GetProfile(pending.orgType, pending.orgName, pending.targetIdentifier)
    local metadata = type(current.metadata) == 'table' and current.metadata or {}
    metadata.generatedImage = {
        at = os.date('%Y-%m-%d %H:%M:%S'),
        by = pending.actorIdentifier,
        captureSource = pending.targetSource,
        provider = cleanText(providerName, 64)
    }
    local profile = EmployeesModule.UpsertProfile(
        pending.orgType,
        pending.orgName,
        pending.targetIdentifier,
        {
            notes = current.notes or '',
            photoUrl = photoData,
            metadata = metadata
        },
        pending.actorIdentifier
    )
    EmployeesModule.AppendActivity(
        pending.orgType,
        pending.orgName,
        pending.targetIdentifier,
        'profile_image_generated',
        {
            actor = pending.actorIdentifier,
            source = pending.targetSource,
            provider = cleanText(providerName, 64)
        }
    )

    addAudit(pending.orgName, pending.orgType .. '_profile_image_generated', pending.actorIdentifier, pending.targetIdentifier, {
        requestId = reqId,
        source = pending.targetSource,
        provider = cleanText(providerName, 64)
    })
    emitHook('member_profile_image_generated', {
        menuType = pending.orgType == 'gang' and 'gang' or 'boss',
        role = pending.orgName,
        actor = pending.actorIdentifier,
        target = pending.targetIdentifier
    })
    invalidateOrganizationCaches(pending.orgType == 'gang' and 'gang' or 'boss', pending.orgName)

    TriggerClientEvent('qb-management:client:profileCaptureResult', pending.actorSource, {
        ok = true,
        identifier = pending.targetIdentifier,
        profile = profile
    })
end)

local function legacyContext(src, menuType)
    local context, err = getContextFromPlayer(src, menuType)
    return context, err
end

local function parseLegacyIdentifier(target)
    if type(target) == 'table' then
        return cleanText(target.citizenid or target.cid or target.identifier or target.target or '', 80)
    end
    return cleanText(target or '', 80)
end

local function parseLegacySource(target)
    if type(target) == 'table' then
        return safeNumber(target.id or target.sourceplayer or target.source or target.target, 1)
    end
    return safeNumber(target, 1)
end

RegisterNetEvent('qb-bossmenu:server:HireEmployee', function(recruit)
    local src = source
    local context = legacyContext(src, 'boss')
    if not context then return end
    local targetSrc = parseLegacySource(recruit)
    if not targetSrc then return end
    actionHire(context, { source = targetSrc }, src)
end)

RegisterNetEvent('qb-bossmenu:server:FireEmployee', function(target)
    local src = source
    local context = legacyContext(src, 'boss')
    if not context then return end
    local identifier = parseLegacyIdentifier(target)
    if identifier == '' then return end
    actionFire(context, { identifier = identifier })
end)

RegisterNetEvent('qb-bossmenu:server:GradeUpdate', function(data)
    local src = source
    local context = legacyContext(src, 'boss')
    if not context then return end
    if type(data) ~= 'table' then return end
    actionSetGrade(context, {
        identifier = cleanText(data.cid or data.identifier, 80),
        grade = tonumber(data.grade) or 0
    })
end)

RegisterNetEvent('qb-bossmenu:server:addMoney', function(_, amount)
    local src = source
    local context = legacyContext(src, 'boss')
    if not context then return end
    local ok, _ = actionDeposit(context, { amount = amount })
    if ok then
        notify(src, 'Deposited successfully', 'success')
    end
end)

RegisterNetEvent('qb-bossmenu:server:withdrawMoney', function(_, amount)
    local src = source
    local context = legacyContext(src, 'boss')
    if not context then return end
    local ok, _ = actionWithdraw(context, { amount = amount })
    if ok then
        notify(src, 'Withdrawn successfully', 'success')
    end
end)

RegisterNetEvent('qb-gangmenu:server:HireMember', function(recruit)
    local src = source
    local context = legacyContext(src, 'gang')
    if not context then return end
    local targetSrc = parseLegacySource(recruit)
    if not targetSrc then return end
    actionHire(context, { source = targetSrc }, src)
end)

RegisterNetEvent('qb-gangmenu:server:FireMember', function(target)
    local src = source
    local context = legacyContext(src, 'gang')
    if not context then return end
    local identifier = parseLegacyIdentifier(target)
    if identifier == '' then return end
    actionFire(context, { identifier = identifier })
end)

RegisterNetEvent('qb-gangmenu:server:GradeUpdate', function(data)
    local src = source
    local context = legacyContext(src, 'gang')
    if not context then return end
    if type(data) ~= 'table' then return end
    actionSetGrade(context, {
        identifier = cleanText(data.cid or data.identifier, 80),
        grade = tonumber(data.grade) or 0
    })
end)

if QBCore and QBCore.Functions and QBCore.Functions.CreateCallback then
    QBCore.Functions.CreateCallback('qb-bossmenu:server:GetEmployees', function(source, cb)
        local context = legacyContext(source, 'boss')
        if not context then return cb({}) end
        cb(getEmployeesForRole('boss', context.role.name))
    end)

    QBCore.Functions.CreateCallback('qb-gangmenu:server:GetEmployees', function(source, cb)
        local context = legacyContext(source, 'gang')
        if not context then return cb({}) end
        cb(getEmployeesForRole('gang', context.role.name))
    end)

    QBCore.Functions.CreateCallback('qb-bossmenu:getplayers', function(source, cb)
        cb(getNearbyPlayers(source))
    end)

    QBCore.Functions.CreateCallback('qb-gangmenu:getplayers', function(source, cb)
        cb(getNearbyPlayers(source))
    end)
end

RegisterNetEvent('qb-management:server:requestGangRoleSync', function()
    local src = source
    if usingCustomGangBackend() then
        syncCustomGangToClientBySource(src)
    end
end)

RegisterNetEvent('qb-management:server:requestWorldGraffiti', function()
    local src = source
    if not isModuleEnabled('GangGraffiti') then
        TriggerClientEvent('qb-management:client:worldGraffitiSnapshot', src, {})
        return
    end
    if not GangsModule or not GangsModule.ListWorldGraffiti then
        TriggerClientEvent('qb-management:client:worldGraffitiSnapshot', src, {})
        return
    end
    TriggerClientEvent('qb-management:client:worldGraffitiSnapshot', src, GangsModule.ListWorldGraffiti())
end)

RegisterNetEvent('qb-management:server:SubmitApplication', function(data)
    local src = source
    if not isModuleEnabled('Applications') then
        return
    end
    local player = getPlayerState(src)
    local orgType = data and data.orgType or 'boss'
    local orgName = cleanText(data and data.orgName, 64)
    if orgName == '' then
        return
    end
    ApplicationsModule.Create(orgType == 'gang' and 'gang' or 'boss', orgName, {
        identifier = player and player.identifier or nil,
        name = player and player.name or GetPlayerName(src),
        phone = data and data.phone or nil,
        answers = data and data.answers or {}
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    Sessions[src] = nil
    SeenRequests[src] = nil
    for key, req in pairs(ProfileImageRequests) do
        if req and (tonumber(req.targetSource) == tonumber(src) or tonumber(req.actorSource) == tonumber(src)) then
            ProfileImageRequests[key] = nil
        end
    end
end)

local function getOrgConfig(orgType, orgName)
    orgType = orgType == 'gang' and 'gang' or 'boss'
    local icon = roleIcon(orgType, orgName)
    return {
        type = orgType,
        name = orgName,
        icon = icon,
        modules = Config.Modules or {},
        integrations = Config.Integrations or {}
    }
end

local function createAuditRow(orgType, orgName, action, actor, target, metadata)
    if AuditModule and AuditModule.Write then
        AuditModule.Write(tostring(orgType or 'boss'), tostring(orgName or 'unknown'), tostring(action or 'custom'), actor, target, metadata or {})
    else
        addAudit(orgName, action, actor, target, metadata)
    end
    emitHook('api_audit_created', {
        orgType = orgType,
        orgName = orgName,
        action = action,
        actor = actor,
        target = target
    })
    return true
end

local function getNotoriety(gangName)
    local row = MySQL.single.await('SELECT points FROM bossmenu_gang_notoriety WHERE gang_name = ? LIMIT 1', { gangName })
    return tonumber(row and row.points) or 0
end

local function addNotoriety(gangName, amount, reason, actor)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_gang_notoriety (gang_name, points) VALUES (?, 0)', { gangName })
    MySQL.update.await('UPDATE bossmenu_gang_notoriety SET points = points + ? WHERE gang_name = ?', { amount, gangName })
    addAudit(gangName, 'gang_notoriety_add', actor, nil, { amount = amount, reason = reason })
    emitHook('OnGangNotorietyChanged', { gang = gangName, delta = amount, reason = reason, actor = actor })
    return true
end

local function removeNotoriety(gangName, amount, reason, actor)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_gang_notoriety (gang_name, points) VALUES (?, 0)', { gangName })
    MySQL.update.await('UPDATE bossmenu_gang_notoriety SET points = GREATEST(points - ?, 0) WHERE gang_name = ?', { amount, gangName })
    addAudit(gangName, 'gang_notoriety_remove', actor, nil, { amount = amount, reason = reason })
    emitHook('OnGangNotorietyChanged', { gang = gangName, delta = -amount, reason = reason, actor = actor })
    return true
end

local function publicApiEnabled()
    return BrahBossmenuRuntimeReady == true and (not Config.Modules or Config.Modules.PublicAPI ~= false)
end

exports('OpenBossMenu', function(src, jobName)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    local context, err = getContextFromPlayer(src, 'boss')
    if not context then return false, err end
    if jobName and tostring(jobName) ~= tostring(context.role.name) then
        return false, 'Organization mismatch'
    end
    TriggerClientEvent('qb-management:client:openMenu', src, { menuType = 'boss' })
    return true
end)

exports('IsBoss', function(src, jobName)
    if not publicApiEnabled() then return false end
    local context = getContextFromPlayer(src, 'boss')
    if not context then return false end
    if jobName and tostring(context.role.name) ~= tostring(jobName) then
        return false
    end
    return true
end)

exports('HasBossPermission', function(src, jobName, permission)
    if not publicApiEnabled() then return false end
    local context = getContextFromPlayer(src, 'boss')
    if not context then return false end
    if jobName and tostring(context.role.name) ~= tostring(jobName) then return false end
    return hasContextPermission(context, tostring(permission or ''))
end)

exports('GetEmployees', function(jobName)
    if not publicApiEnabled() then return {} end
    if not jobName then return {} end
    return getEmployeesForRole('boss', tostring(jobName))
end)

exports('HireEmployee', function(job, target, grade, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    local targetState = getPlayerState(target)
    if not targetState then return false end
    local level = tonumber(grade) or 0
    local ok = setRoleForIdentifier('boss', targetState.identifier, tostring(job), level)
    if ok then
        addAudit(tostring(job), 'api_hire_employee', actor, targetState.identifier, { grade = level })
    end
    return ok
end)

exports('FireEmployee', function(job, targetIdentifier, reason, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    local ok = removeRoleForIdentifier('boss', tostring(targetIdentifier), tostring(job))
    if ok then
        addAudit(tostring(job), 'api_fire_employee', actor, tostring(targetIdentifier), { reason = reason })
    end
    return ok
end)

exports('AddSocietyMoney', function(job, amount, reason, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    ensureAccount(job)
    MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance + ? WHERE job = ?', { amount, job })
    mirrorSocietyMoney(job, amount, 'add', reason or 'api_deposit')
    addLedger(job, 'api_deposit', amount, actor, nil, reason or 'api')
    addAudit(job, 'api_add_society_money', actor, nil, { amount = amount, reason = reason })
    return true
end)

exports('RemoveSocietyMoney', function(job, amount, reason, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    ensureAccount(job)
    local affected = MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance - ? WHERE job = ? AND balance >= ?', { amount, job, amount })
    if (affected or 0) < 1 then return false end
    mirrorSocietyMoney(job, amount, 'remove', reason or 'api_withdraw')
    addLedger(job, 'api_withdraw', amount, actor, nil, reason or 'api')
    addAudit(job, 'api_remove_society_money', actor, nil, { amount = amount, reason = reason })
    return true
end)

exports('GetSocietyBalance', function(job)
    if not publicApiEnabled() then return 0 end
    return getBalance(tostring(job))
end)

exports('OpenGangMenu', function(src, gangName)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    local context, err = getContextFromPlayer(src, 'gang')
    if not context then return false, err end
    if gangName and tostring(gangName) ~= tostring(context.role.name) then
        return false, 'Organization mismatch'
    end
    TriggerClientEvent('qb-management:client:openMenu', src, { menuType = 'gang' })
    return true
end)

exports('IsGangLeader', function(src, gangName)
    if not publicApiEnabled() then return false end
    local context = getContextFromPlayer(src, 'gang')
    if not context then return false end
    if gangName and tostring(context.role.name) ~= tostring(gangName) then return false end
    return true
end)

exports('HasGangPermission', function(src, gangName, permission)
    if not publicApiEnabled() then return false end
    local context = getContextFromPlayer(src, 'gang')
    if not context then return false end
    if gangName and tostring(context.role.name) ~= tostring(gangName) then return false end
    return hasContextPermission(context, tostring(permission or ''))
end)

exports('GetGangMembers', function(gangName)
    if not publicApiEnabled() then return {} end
    if not gangName then return {} end
    return getEmployeesForRole('gang', tostring(gangName))
end)

exports('AddGangMember', function(gang, target, grade, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    local targetState = getPlayerState(target)
    if not targetState then return false end
    local level = tonumber(grade) or 0
    local ok = setRoleForIdentifier('gang', targetState.identifier, tostring(gang), level)
    if ok then
        addAudit(tostring(gang), 'api_add_gang_member', actor, targetState.identifier, { grade = level })
    end
    return ok
end)

exports('RemoveGangMember', function(gang, targetIdentifier, reason, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    local ok = removeRoleForIdentifier('gang', tostring(targetIdentifier), tostring(gang))
    if ok then
        addAudit(tostring(gang), 'api_remove_gang_member', actor, tostring(targetIdentifier), { reason = reason })
    end
    return ok
end)

exports('GetGangNotoriety', function(gang)
    if not publicApiEnabled() then return 0 end
    return getNotoriety(tostring(gang))
end)

exports('AddGangNotoriety', function(gang, amount, reason, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    return addNotoriety(tostring(gang), amount, reason, actor)
end)

exports('RemoveGangNotoriety', function(gang, amount, reason, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    return removeNotoriety(tostring(gang), amount, reason, actor)
end)

exports('CreateAuditLog', function(orgType, orgName, action, actor, target, metadata)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    return createAuditRow(orgType, orgName, action, actor, target, metadata)
end)

exports('GetOrgConfig', function(orgType, orgName)
    if not publicApiEnabled() then return {} end
    return getOrgConfig(orgType, orgName)
end)

exports('SubmitApplication', function(orgType, orgName, payload)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    if not ApplicationsModule or not ApplicationsModule.Create then
        return false, 'Applications module unavailable'
    end
    orgType = tostring(orgType or 'boss')
    orgName = tostring(orgName or '')
    if orgName == '' then
        return false, 'Invalid organization'
    end
    return ApplicationsModule.Create(orgType, orgName, payload or {})
end)

exports('CreateInvoice', function(orgType, orgName, payload, actor)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    if not FinanceModule or not FinanceModule.CreateInvoice then
        return false, 'Finance module unavailable'
    end
    return FinanceModule.CreateInvoice(tostring(orgType or 'boss'), tostring(orgName or ''), payload or {}, actor)
end)

exports('SetInvoiceStatus', function(orgType, orgName, invoiceId, status, actor, note)
    if not publicApiEnabled() then return false, 'Public API disabled' end
    if not FinanceModule or not FinanceModule.UpdateInvoiceStatus then
        return false, 'Finance module unavailable'
    end
    return FinanceModule.UpdateInvoiceStatus(tostring(orgType or 'boss'), tostring(orgName or ''), invoiceId, status, actor, note)
end)

local function handleQBCorePlayerLoaded(player, fromNet)
    if not usingCustomGangBackend() then return end

    if type(player) ~= 'table' or type(player.PlayerData) ~= 'table' then
        if fromNet then
            local netSrc = tonumber(source) or 0
            if netSrc > 0 then
                flagSuspicious(netSrc, 'framework_event_spoof', 'invalid_qb_onplayerloaded_payload', {
                    event = 'QBCore:Server:OnPlayerLoaded'
                })
            end
        end
        return
    end

    local playerSrc = tonumber(player.PlayerData.source) or 0
    if fromNet then
        local netSrc = tonumber(source) or 0
        if netSrc <= 0 or playerSrc ~= netSrc then
            if netSrc > 0 then
                flagSuspicious(netSrc, 'framework_event_spoof', 'qb_onplayerloaded_source_mismatch', {
                    event = 'QBCore:Server:OnPlayerLoaded',
                    payloadSource = playerSrc
                })
            end
            return
        end
    end

    if playerSrc > 0 then
        syncCustomGangToClientBySource(playerSrc)
    end
end

AddEventHandler('QBCore:Server:OnPlayerLoaded', function(player)
    handleQBCorePlayerLoaded(player, (tonumber(source) or 0) > 0)
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    if not usingCustomGangBackend() then return end
    local src = tonumber(playerId)
    if src and src > 0 then
        syncCustomGangToClientBySource(src)
    end
end)

RegisterCommand('bossframework', function(src)
    local message = ('[%s] framework=%s, inbuiltGang=%s'):format(resource, frameworkName, tostring(useInbuiltGangFrames()))
    if src == 0 then
        print(message)
    else
        notify(src, message, 'inform')
    end
end, true)

local function canUseDebugCommand(src)
    if Config.Debug ~= true then
        return false
    end
    if src == 0 then
        return true
    end
    return IsPlayerAceAllowed(src, 'bossmenu.admin')
end

RegisterCommand('bm_debug_org', function(src, args)
    if not canUseDebugCommand(src) then return end
    local menuType = tostring(args[1] or 'boss')
    local orgName = tostring(args[2] or '')
    if orgName == '' then
        if src > 0 then notify(src, 'Usage: /bm_debug_org boss|gang name', 'error') end
        return
    end
    local employees = getEmployeesForRole(menuType == 'gang' and 'gang' or 'boss', orgName)
    local message = ('org=%s:%s members=%s'):format(menuType, orgName, tostring(#employees))
    if src == 0 then
        print(('[%s] %s'):format(resource, message))
    else
        notify(src, message, 'inform')
    end
end, true)

RegisterCommand('bm_test_audit', function(src)
    if not canUseDebugCommand(src) then return end
    local actor = src > 0 and tostring(src) or 'console'
    addAudit('debug', 'bm_test_audit', actor, nil, { at = os.time() })
    if src > 0 then notify(src, 'Audit test written', 'success') end
end, true)

RegisterCommand('bm_test_webhook', function(src)
    if not canUseDebugCommand(src) then return end
    emitHook('debug_webhook_test', {
        source = src,
        at = os.time()
    })
    if src > 0 then notify(src, 'Webhook test hook emitted', 'success') end
end, true)

RegisterCommand('bm_reload_permissions', function(src)
    if not canUseDebugCommand(src) then return end
    PermissionCache = {}
    if src > 0 then notify(src, 'Permission cache cleared', 'success') end
end, true)

RegisterCommand('bm_migrate', function(src)
    if not canUseDebugCommand(src) then return end
    ensureTables()
    ensureGangDefinitions()
    if src > 0 then notify(src, 'Migrations executed', 'success') end
end, true)

RegisterCommand('bm_seed_demo', function(src)
    if not canUseDebugCommand(src) then return end
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_accounts (job, balance) VALUES (?, ?)', { 'police', 100000 })
    MySQL.insert.await('INSERT IGNORE INTO bossmenu_gangs (name, label, max_grade) VALUES (?, ?, ?)', { 'lostmc', 'The Lost MC', 4 })
    addAudit('debug', 'bm_seed_demo', src > 0 and tostring(src) or 'console', nil, nil)
    if src > 0 then notify(src, 'Demo seed inserted', 'success') end
end, true)

RegisterCommand('bm_clear_demo', function(src)
    if not canUseDebugCommand(src) then return end
    MySQL.update.await('DELETE FROM bossmenu_accounts WHERE job = ?', { 'police' })
    addAudit('debug', 'bm_clear_demo', src > 0 and tostring(src) or 'console', nil, nil)
    if src > 0 then notify(src, 'Demo data cleared', 'success') end
end, true)

exports('GetFrameworkName', function()
    return frameworkName
end)

exports('IsUsingInbuiltGangFrames', function()
    return useInbuiltGangFrames()
end)

