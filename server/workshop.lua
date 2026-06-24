HiddenWorkshopModule = HiddenWorkshopModule or {}
HiddenWorkshopModule.cooldowns = HiddenWorkshopModule.cooldowns or {}

local HW_PREFIX = 'hw_'

local function hwCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function hwNumber(value, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    return n
end

local function hwDecode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, parsed = pcall(json.decode, value)
    if ok and type(parsed) == 'table' then
        return parsed
    end
    return {}
end

local function hwEncode(value)
    local ok, encoded = pcall(json.encode, value or {})
    if ok then return encoded end
    return '{}'
end

local function hwNow()
    return os.time()
end

local function hwCfg()
    return Config.HiddenWorkshop or {}
end

function HiddenWorkshopModule.IsEnabled()
    return Config.EnableGangMenu == true and Config.Modules and Config.Modules.HiddenWorkshop == true
end

function HiddenWorkshopModule.IsWorkshopContractType(contractType)
    return tostring(contractType or ''):sub(1, #HW_PREFIX) == HW_PREFIX
end

local function hwAudit(gangName, action, actor, target, metadata)
    if AuditModule and AuditModule.Write then
        AuditModule.Write('gang', gangName, 'workshop_' .. tostring(action), actor, target, metadata or {})
        return
    end
    MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
        VALUES (?, ?, ?, ?, ?)]], {
        gangName,
        'workshop_' .. tostring(action),
        actor,
        target,
        hwEncode(metadata or {})
    })
end

local function levelThresholds()
    local cfg = hwCfg()
    local rows = type(cfg.levelThresholds) == 'table' and cfg.levelThresholds or { 0, 120, 320, 700, 1300 }
    if #rows == 0 then
        return { 0 }
    end
    return rows
end

local function calculateLevel(reputation)
    local level = 1
    local points = tonumber(reputation) or 0
    local thresholds = levelThresholds()
    for i = 1, #thresholds do
        if points >= (tonumber(thresholds[i]) or 0) then
            level = i
        end
    end
    return level
end

local function getContractTypeConfig(contractType)
    local cfg = hwCfg()
    local contracts = cfg.contractTypes or {}
    return contracts[contractType]
end

local function getVehicleClassConfig(classKey)
    local cfg = hwCfg()
    local classes = cfg.vehicleClasses or {}
    return classes[classKey]
end

local function randomFromList(rows, fallback)
    if type(rows) ~= 'table' or #rows == 0 then
        return fallback
    end
    return rows[math.random(1, #rows)] or fallback
end

local function getProfile(gangName)
    local cleanGang = hwCleanText(gangName, 64)
    MySQL.insert.await([[INSERT IGNORE INTO bossmenu_hidden_workshop_profiles
        (gang_name, reputation, level, jobs_completed, jobs_failed, early_cashouts, cars_stripped, total_cash_earned, total_parts_earned, heat)
        VALUES (?, 0, 1, 0, 0, 0, 0, 0, 0, 0)]], { cleanGang })

    local row = MySQL.single.await([[SELECT gang_name, reputation, level, jobs_completed, jobs_failed, early_cashouts, cars_stripped,
            total_cash_earned, total_parts_earned, heat, updated_at
        FROM bossmenu_hidden_workshop_profiles
        WHERE gang_name = ?
        LIMIT 1]], { cleanGang }) or {
        gang_name = cleanGang,
        reputation = 0,
        level = 1,
        jobs_completed = 0,
        jobs_failed = 0,
        early_cashouts = 0,
        cars_stripped = 0,
        total_cash_earned = 0,
        total_parts_earned = 0,
        heat = 0
    }

    row.reputation = tonumber(row.reputation) or 0
    row.level = calculateLevel(row.reputation)
    row.jobs_completed = tonumber(row.jobs_completed) or 0
    row.jobs_failed = tonumber(row.jobs_failed) or 0
    row.early_cashouts = tonumber(row.early_cashouts) or 0
    row.cars_stripped = tonumber(row.cars_stripped) or 0
    row.total_cash_earned = tonumber(row.total_cash_earned) or 0
    row.total_parts_earned = tonumber(row.total_parts_earned) or 0
    row.heat = tonumber(row.heat) or 0
    row.nextLevelAt = levelThresholds()[row.level + 1]
    row.benefits = {
        cashBonusPercent = math.floor(((hwNumber(hwCfg().cashBonusPercentPerLevel, 0.06) or 0.06) * math.max(row.level - 1, 0)) * 100),
        repBonusPercent = math.floor(((hwNumber(hwCfg().repBonusPercentPerLevel, 0.05) or 0.05) * math.max(row.level - 1, 0)) * 100),
        extraPartChancePercent = math.floor(((hwNumber(hwCfg().extraPartChancePerLevel, 0.08) or 0.08) * math.max(row.level - 1, 0)) * 100),
        cashoutPenaltyReduction = math.floor((hwNumber(hwCfg().penaltyReductionPerLevel, 4) or 4) * math.max(row.level - 1, 0))
    }

    MySQL.update.await('UPDATE bossmenu_hidden_workshop_profiles SET level = ?, updated_at = NOW() WHERE gang_name = ?', {
        row.level, cleanGang
    })

    return row
end

local function saveProfileStats(gangName, profile, stats)
    local reputation = math.max(0, (tonumber(profile.reputation) or 0) + (tonumber(stats.reputation) or 0))
    local jobsCompleted = math.max(0, (tonumber(profile.jobs_completed) or 0) + (tonumber(stats.jobs_completed) or 0))
    local jobsFailed = math.max(0, (tonumber(profile.jobs_failed) or 0) + (tonumber(stats.jobs_failed) or 0))
    local earlyCashouts = math.max(0, (tonumber(profile.early_cashouts) or 0) + (tonumber(stats.early_cashouts) or 0))
    local carsStripped = math.max(0, (tonumber(profile.cars_stripped) or 0) + (tonumber(stats.cars_stripped) or 0))
    local totalCash = math.max(0, (tonumber(profile.total_cash_earned) or 0) + (tonumber(stats.total_cash_earned) or 0))
    local totalParts = math.max(0, (tonumber(profile.total_parts_earned) or 0) + (tonumber(stats.total_parts_earned) or 0))
    local heat = math.max(0, (tonumber(profile.heat) or 0) + (tonumber(stats.heat) or 0))
    local level = calculateLevel(reputation)

    MySQL.update.await([[UPDATE bossmenu_hidden_workshop_profiles
        SET reputation = ?, level = ?, jobs_completed = ?, jobs_failed = ?, early_cashouts = ?,
            cars_stripped = ?, total_cash_earned = ?, total_parts_earned = ?, heat = ?, updated_at = NOW()
        WHERE gang_name = ?]], {
        reputation, level, jobsCompleted, jobsFailed, earlyCashouts, carsStripped, totalCash, totalParts, heat, hwCleanText(gangName, 64)
    })

    return getProfile(gangName)
end

local function listWorkshopContracts(gangName, status)
    local cleanGang = hwCleanText(gangName, 64)
    local cleanStatus = hwCleanText(status, 24)
    local rows
    if cleanStatus ~= '' and cleanStatus ~= 'all' then
        rows = MySQL.query.await([[SELECT id, gang_name, contract_type, status, reward_json, payload, accepted_by, accepted_at, completed_at, created_at
            FROM bossmenu_gang_contracts
            WHERE gang_name = ? AND contract_type LIKE 'hw\_%' ESCAPE '\' AND status = ?
            ORDER BY id DESC
            LIMIT 80]], { cleanGang, cleanStatus }) or {}
    else
        rows = MySQL.query.await([[SELECT id, gang_name, contract_type, status, reward_json, payload, accepted_by, accepted_at, completed_at, created_at
            FROM bossmenu_gang_contracts
            WHERE gang_name = ? AND contract_type LIKE 'hw\_%' ESCAPE '\'
            ORDER BY id DESC
            LIMIT 80]], { cleanGang }) or {}
    end

    for i = 1, #rows do
        rows[i].reward = hwDecode(rows[i].reward_json)
        rows[i].payload = hwDecode(rows[i].payload)
        rows[i].contractType = tostring(rows[i].contract_type or ''):gsub('^' .. HW_PREFIX, '')
        rows[i].progress = {
            stripped = tonumber(rows[i].payload.totalStripped) or 0,
            required = tonumber(rows[i].payload.totalRequired) or 0,
            ratio = 0
        }
        if rows[i].progress.required > 0 then
            rows[i].progress.ratio = math.min(1, rows[i].progress.stripped / rows[i].progress.required)
        end
    end

    return rows
end

local function activeWorkshopCount(gangName)
    return tonumber(MySQL.scalar.await([[SELECT COUNT(*)
        FROM bossmenu_gang_contracts
        WHERE gang_name = ? AND contract_type LIKE 'hw\_%' ESCAPE '\' AND status = 'active']], {
        hwCleanText(gangName, 64)
    }) or 0) or 0
end

local function buildPartPlan(contractType, vehicleClass, profileLevel)
    local cfg = hwCfg()
    local contractCfg = getContractTypeConfig(contractType) or {}
    local classCfg = getVehicleClassConfig(vehicleClass) or {}
    local catalog = cfg.partCatalog or {}
    local plan = {}
    local totalRequired = 0
    local partMultiplier = hwNumber(contractCfg.partMultiplier, 1.0) or 1.0

    for partKey, def in pairs(classCfg.parts or {}) do
        local minCount = math.max(1, math.floor(hwNumber(def.min, 1) or 1))
        local maxCount = math.max(minCount, math.floor(hwNumber(def.max, minCount) or minCount))
        local qty = math.random(minCount, maxCount)
        qty = math.max(1, math.floor(qty * partMultiplier))
        local partCfg = catalog[partKey] or {}
        plan[#plan + 1] = {
            key = partKey,
            label = hwCleanText(partCfg.label or partKey, 64),
            item = hwCleanText(partCfg.item or partKey, 64),
            unitValue = math.max(0, math.floor(hwNumber(partCfg.unitValue, 0) or 0)),
            required = qty,
            stripped = 0,
            awarded = 0
        }
        totalRequired = totalRequired + qty
    end

    local guaranteed = contractCfg.guaranteedParts or {}
    for i = 1, #guaranteed do
        local key = tostring(guaranteed[i])
        local found = false
        for j = 1, #plan do
            if plan[j].key == key then
                plan[j].required = plan[j].required + 1
                totalRequired = totalRequired + 1
                found = true
                break
            end
        end
        if not found and catalog[key] then
            plan[#plan + 1] = {
                key = key,
                label = hwCleanText(catalog[key].label or key, 64),
                item = hwCleanText(catalog[key].item or key, 64),
                unitValue = math.max(0, math.floor(hwNumber(catalog[key].unitValue, 0) or 0)),
                required = 1,
                stripped = 0,
                awarded = 0
            }
            totalRequired = totalRequired + 1
        end
    end

    table.sort(plan, function(a, b)
        return tostring(a.label) < tostring(b.label)
    end)

    return plan, totalRequired
end

local function buildWorkshopContract(gangName, contractType, payload, actor)
    local cleanGang = hwCleanText(gangName, 64)
    local cleanType = hwCleanText(contractType, 40)
    local contractCfg = getContractTypeConfig(cleanType)
    if not contractCfg then
        return false, 'Unsupported workshop contract type'
    end

    local profile = getProfile(cleanGang)
    local classOptions = contractCfg.vehicleClasses or {}
    local requestedClass = hwCleanText(payload and payload.vehicleClass, 32)
    local vehicleClass = requestedClass ~= '' and requestedClass or randomFromList(classOptions, classOptions[1])
    if vehicleClass == '' then
        return false, 'No vehicle class configured'
    end

    local classCfg = getVehicleClassConfig(vehicleClass)
    if not classCfg then
        return false, 'Unsupported vehicle class'
    end

    local partPlan, totalRequired = buildPartPlan(cleanType, vehicleClass, profile.level)
    local cashBonusPct = (hwNumber(hwCfg().cashBonusPercentPerLevel, 0.06) or 0.06) * math.max(profile.level - 1, 0)
    local repBonusPct = (hwNumber(hwCfg().repBonusPercentPerLevel, 0.05) or 0.05) * math.max(profile.level - 1, 0)

    local baseMoney = math.max(0, math.floor((hwNumber(classCfg.payout, 0) or 0) + (hwNumber(contractCfg.bonusPayout, 0) or 0)))
    local baseNotoriety = math.max(0, math.floor((hwNumber(classCfg.notoriety, 0) or 0) + (hwNumber(contractCfg.bonusNotoriety, 0) or 0)))
    local baseRep = math.max(0, math.floor((hwNumber(classCfg.reputation, 0) or 0) + (hwNumber(contractCfg.bonusReputation, 0) or 0)))
    local bonusMoney = math.floor(baseMoney * cashBonusPct)
    local bonusRep = math.floor(baseRep * repBonusPct)

    local reward = {
        money = baseMoney + bonusMoney,
        notoriety = baseNotoriety,
        reputation = baseRep + bonusRep
    }

    local contractPayload = {
        hiddenWorkshop = true,
        workshopType = cleanType,
        contractLabel = hwCleanText(contractCfg.label or cleanType, 64),
        description = hwCleanText(contractCfg.description or '', 160),
        vehicleClass = vehicleClass,
        vehicleLabel = hwCleanText(classCfg.label or vehicleClass, 64),
        targetModel = hwCleanText(randomFromList(classCfg.models or {}, classCfg.label or vehicleClass), 64),
        parts = partPlan,
        totalRequired = totalRequired,
        totalStripped = 0,
        totalAwarded = 0,
        earlyCashoutPenaltyPercent = math.max(5, (hwNumber(hwCfg().earlyCashoutPenaltyPercent, 35) or 35) - ((hwNumber(hwCfg().penaltyReductionPerLevel, 4) or 4) * math.max(profile.level - 1, 0))),
        payoutMode = hwCleanText(hwCfg().payoutMode or 'dirty_item', 24),
        heat = math.max(0, math.floor(hwNumber(classCfg.heat, 0) or 0)),
        stage = 'available',
        createdBy = actor,
        createdAt = hwNow(),
        levelSnapshot = profile.level
    }

    local id = MySQL.insert.await([[INSERT INTO bossmenu_gang_contracts (gang_name, contract_type, status, reward_json, payload)
        VALUES (?, ?, 'available', ?, ?)]], {
        cleanGang,
        HW_PREFIX .. cleanType,
        hwEncode(reward),
        hwEncode(contractPayload)
    })

    hwAudit(cleanGang, 'created', actor, nil, {
        contractId = id,
        contractType = cleanType,
        vehicleClass = vehicleClass
    })

    return true, {
        id = id,
        reward = reward,
        payload = contractPayload,
        profile = profile
    }
end

local function getWorkshopContract(gangName, contractId)
    local row = MySQL.single.await([[SELECT id, gang_name, contract_type, status, reward_json, payload, accepted_by, accepted_at, completed_at, created_at
        FROM bossmenu_gang_contracts
        WHERE id = ? AND gang_name = ? AND contract_type LIKE 'hw\_%' ESCAPE '\'
        LIMIT 1]], {
        tonumber(contractId) or 0,
        hwCleanText(gangName, 64)
    })
    if not row then return nil end
    row.reward = hwDecode(row.reward_json)
    row.payload = hwDecode(row.payload)
    row.contractType = tostring(row.contract_type or ''):gsub('^' .. HW_PREFIX, '')
    return row
end

local function updateContractPayload(contractId, payload)
    MySQL.update.await('UPDATE bossmenu_gang_contracts SET payload = ? WHERE id = ?', {
        hwEncode(payload),
        tonumber(contractId) or 0
    })
end

local function contractTypeOptions()
    local rows = {}
    for id, def in pairs(hwCfg().contractTypes or {}) do
        rows[#rows + 1] = {
            id = id,
            label = hwCleanText(def.label or id, 64),
            description = hwCleanText(def.description or '', 160),
            classes = def.vehicleClasses or {}
        }
    end
    table.sort(rows, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return rows
end

local function partCatalogRows()
    local rows = {}
    for key, def in pairs(hwCfg().partCatalog or {}) do
        rows[#rows + 1] = {
            key = key,
            label = hwCleanText(def.label or key, 64),
            item = hwCleanText(def.item or key, 64),
            unitValue = math.max(0, math.floor(hwNumber(def.unitValue, 0) or 0))
        }
    end
    table.sort(rows, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return rows
end

local function applyDirtyCashReward(gangName, actor, contractId, amount)
    local cfg = hwCfg()
    local item = hwCleanText(cfg.payoutItem or 'markedbills', 64)
    local count = math.max(1, math.floor(hwNumber(cfg.payoutItemCount, 1) or 1))
    local metadataKey = hwCleanText(cfg.payoutMetadataKey or 'worth', 32)
    local metadata = {
        hiddenWorkshop = true,
        contractId = tonumber(contractId) or 0
    }
    metadata[metadataKey] = math.max(0, math.floor(hwNumber(amount, 0) or 0))
    return InventoryModule.AddOrganizationItem('gang', gangName, item, count, actor, 'hidden_cash', metadata)
end

local function finalizeWorkshop(gangName, contractId, actor, finalStatus, ratio)
    local row = getWorkshopContract(gangName, contractId)
    if not row then
        return false, 'Workshop contract not found'
    end
    if row.status ~= 'active' then
        return false, 'Workshop contract not active'
    end

    local reward = type(row.reward) == 'table' and row.reward or {}
    local payload = type(row.payload) == 'table' and row.payload or {}
    local stripped = tonumber(payload.totalStripped) or 0
    local required = tonumber(payload.totalRequired) or 0
    local scaledRatio = math.max(0, math.min(1, tonumber(ratio) or 0))
    local statusOut = finalStatus

    if required > 0 and scaledRatio <= 0 then
        scaledRatio = math.max(0, math.min(1, stripped / required))
    end

    local money = 0
    local rep = 0
    local notoriety = 0
    local earlyCashout = finalStatus == 'cashed_out'

    if finalStatus == 'completed' then
        scaledRatio = 1
    end

    if finalStatus == 'failed' then
        money, rep, notoriety = 0, 0, 0
    else
        money = math.max(0, math.floor((hwNumber(reward.money, 0) or 0) * scaledRatio))
        rep = math.max(0, math.floor((hwNumber(reward.reputation, 0) or 0) * (earlyCashout and math.max(0.35, scaledRatio) or scaledRatio)))
        notoriety = math.max(0, math.floor((hwNumber(reward.notoriety, 0) or 0) * (earlyCashout and math.max(0.5, scaledRatio) or scaledRatio)))
        if earlyCashout then
            money = math.floor(money * (1 - ((tonumber(payload.earlyCashoutPenaltyPercent) or 35) / 100)))
        end
    end

    payload.stage = statusOut
    payload.finishedAt = hwNow()
    payload.finalRatio = scaledRatio
    updateContractPayload(contractId, payload)

    local affected = MySQL.update.await([[UPDATE bossmenu_gang_contracts
        SET status = ?, completed_at = NOW()
        WHERE id = ? AND gang_name = ? AND status = 'active']], {
        statusOut,
        tonumber(contractId) or 0,
        hwCleanText(gangName, 64)
    })

    if (affected or 0) < 1 then
        return false, 'Failed to finalize workshop contract'
    end

    if notoriety > 0 and GangsModule and GangsModule.IsNotorietyEnabled and GangsModule.IsNotorietyEnabled() and GangsModule.ModifyNotoriety then
        GangsModule.ModifyNotoriety(gangName, notoriety, 'hidden_workshop', actor)
    end

    local payoutMode = hwCleanText(payload.payoutMode or hwCfg().payoutMode or 'dirty_item', 24)
    local accountMoney = 0
    local dirtyCash = 0
    if money > 0 then
        if payoutMode == 'account' then
            accountMoney = money
        else
            local ok, err = applyDirtyCashReward(gangName, actor, contractId, money)
            if not ok then
                accountMoney = money
                payoutMode = 'account_fallback'
                hwAudit(gangName, 'cash_fallback', actor, nil, {
                    contractId = contractId,
                    money = money,
                    error = err or 'stash_reward_failed'
                })
            else
                dirtyCash = money
            end
        end
    end

    local profile = saveProfileStats(gangName, getProfile(gangName), {
        reputation = rep,
        jobs_completed = finalStatus == 'failed' and 0 or 1,
        jobs_failed = finalStatus == 'failed' and 1 or 0,
        early_cashouts = earlyCashout and 1 or 0,
        cars_stripped = finalStatus == 'failed' and 0 or 1,
        total_cash_earned = money,
        total_parts_earned = tonumber(payload.totalAwarded) or 0,
        heat = finalStatus == 'completed' and -math.max(1, math.floor((tonumber(payload.heat) or 0) / 2))
            or (finalStatus == 'cashed_out' and -1 or 1)
    })

    hwAudit(gangName, statusOut, actor, nil, {
        contractId = contractId,
        ratio = scaledRatio,
        money = money,
        reputation = rep,
        notoriety = notoriety
    })

    return true, {
        id = tonumber(contractId) or 0,
        status = statusOut,
        reward = {
            money = money,
            accountMoney = accountMoney,
            dirtyCash = dirtyCash,
            notoriety = notoriety,
            reputation = rep,
            payoutMode = payoutMode
        },
        profile = profile,
        contract = getWorkshopContract(gangName, contractId)
    }
end

function HiddenWorkshopModule.GetState(gangName)
    local cleanGang = hwCleanText(gangName, 64)
    local profile = getProfile(cleanGang)
    local contracts = listWorkshopContracts(cleanGang, 'all')
    return {
        profile = profile,
        contracts = contracts,
        contractTypes = contractTypeOptions(),
        partsCatalog = partCatalogRows(),
        payoutMode = hwCleanText(hwCfg().payoutMode or 'dirty_item', 24),
        maxOpenContracts = math.max(1, math.floor(hwNumber(hwCfg().maxOpenContracts, 4) or 4)),
        maxActiveContracts = math.max(1, math.floor(hwNumber(hwCfg().maxActiveContracts, 1) or 1))
    }
end

function HiddenWorkshopModule.Create(gangName, payload, actor)
    if not HiddenWorkshopModule.IsEnabled() then
        return false, 'Hidden workshop disabled'
    end

    local cleanGang = hwCleanText(gangName, 64)
    local contractType = hwCleanText(payload and payload.contractType, 40)
    if contractType == '' then
        return false, 'Invalid workshop contract type'
    end

    local openContracts = tonumber(MySQL.scalar.await([[SELECT COUNT(*)
        FROM bossmenu_gang_contracts
        WHERE gang_name = ? AND contract_type LIKE 'hw\_%' ESCAPE '\' AND status IN ('available', 'active')]], {
        cleanGang
    }) or 0) or 0
    local maxOpen = math.max(1, math.floor(hwNumber(hwCfg().maxOpenContracts, 4) or 4))
    if openContracts >= maxOpen then
        return false, 'Workshop contract limit reached'
    end

    local key = cleanGang .. ':create'
    local now = hwNow()
    local last = tonumber(HiddenWorkshopModule.cooldowns[key] or 0) or 0
    local cooldown = math.max(5, math.floor(hwNumber(hwCfg().createCooldownSeconds, 90) or 90))
    if now - last < cooldown then
        return false, 'Workshop board cooling down'
    end
    HiddenWorkshopModule.cooldowns[key] = now

    local ok, dataOrErr = buildWorkshopContract(cleanGang, contractType, payload and payload.payload or payload, actor)
    if not ok then
        return false, dataOrErr
    end
    return true, HiddenWorkshopModule.GetState(cleanGang)
end

function HiddenWorkshopModule.Accept(gangName, contractId, actor)
    if not HiddenWorkshopModule.IsEnabled() then
        return false, 'Hidden workshop disabled'
    end
    local row = getWorkshopContract(gangName, contractId)
    if not row then
        return false, 'Workshop contract not found'
    end
    if row.status ~= 'available' then
        return false, 'Workshop contract unavailable'
    end
    local maxActive = math.max(1, math.floor(hwNumber(hwCfg().maxActiveContracts, 1) or 1))
    if activeWorkshopCount(gangName) >= maxActive then
        return false, 'Hidden workshop already busy'
    end

    row.payload.stage = 'active'
    row.payload.acceptedAt = hwNow()
    local affected = MySQL.update.await([[UPDATE bossmenu_gang_contracts
        SET status = 'active', accepted_by = ?, accepted_at = NOW(), payload = ?
        WHERE id = ? AND gang_name = ? AND status = 'available']], {
        actor,
        hwEncode(row.payload),
        tonumber(contractId) or 0,
        hwCleanText(gangName, 64)
    })
    if (affected or 0) < 1 then
        return false, 'Workshop contract unavailable'
    end

    saveProfileStats(gangName, getProfile(gangName), {
        heat = math.max(0, tonumber(row.payload.heat) or 0)
    })

    hwAudit(gangName, 'accepted', actor, nil, {
        contractId = contractId,
        contractType = row.contractType
    })
    return true, HiddenWorkshopModule.GetState(gangName)
end

function HiddenWorkshopModule.Progress(gangName, contractId, actor, payload)
    if not HiddenWorkshopModule.IsEnabled() then
        return false, 'Hidden workshop disabled'
    end
    local row = getWorkshopContract(gangName, contractId)
    if not row then
        return false, 'Workshop contract not found'
    end
    if row.status ~= 'active' then
        return false, 'Workshop contract not active'
    end

    local contractPayload = row.payload or {}
    local partKey = hwCleanText(payload and payload.partKey, 64)
    local amount = math.max(1, math.floor(hwNumber(payload and payload.amount, 1) or 1))
    local selected
    for i = 1, #(contractPayload.parts or {}) do
        local part = contractPayload.parts[i]
        if partKey == '' then
            if (tonumber(part.stripped) or 0) < (tonumber(part.required) or 0) then
                selected = part
                break
            end
        elseif tostring(part.key) == partKey then
            selected = part
            break
        end
    end

    if not selected then
        return false, 'No remaining parts for this contract'
    end

    local remaining = math.max(0, (tonumber(selected.required) or 0) - (tonumber(selected.stripped) or 0))
    if remaining <= 0 then
        return false, 'Selected part already stripped'
    end

    local strippedNow = math.min(amount, remaining)
    selected.stripped = (tonumber(selected.stripped) or 0) + strippedNow

    local profile = getProfile(gangName)
    local bonusChance = math.max(0, (hwNumber(hwCfg().extraPartChancePerLevel, 0.08) or 0.08) * math.max(profile.level - 1, 0))
    local awarded = strippedNow
    if bonusChance > 0 and math.random() < bonusChance then
        awarded = awarded + 1
    end
    selected.awarded = (tonumber(selected.awarded) or 0) + awarded
    contractPayload.totalStripped = (tonumber(contractPayload.totalStripped) or 0) + strippedNow
    contractPayload.totalAwarded = (tonumber(contractPayload.totalAwarded) or 0) + awarded
    contractPayload.lastStripAt = hwNow()
    if (tonumber(contractPayload.totalStripped) or 0) >= (tonumber(contractPayload.totalRequired) or 0) then
        contractPayload.stage = 'ready_cashout'
    end

    local ok, err = InventoryModule.AddOrganizationItem('gang', gangName, selected.item or selected.key, awarded, actor, 'hidden_strip', {
        hiddenWorkshop = true,
        contractId = tonumber(contractId) or 0,
        vehicleClass = contractPayload.vehicleClass,
        partKey = selected.key
    })
    if not ok then
        return false, err or 'Failed to award stripped part'
    end

    updateContractPayload(contractId, contractPayload)

    hwAudit(gangName, 'progress', actor, nil, {
        contractId = contractId,
        partKey = selected.key,
        stripped = strippedNow,
        awarded = awarded
    })
    return true, HiddenWorkshopModule.GetState(gangName)
end

function HiddenWorkshopModule.EarlyCashout(gangName, contractId, actor)
    if not HiddenWorkshopModule.IsEnabled() then
        return false, 'Hidden workshop disabled'
    end
    local row = getWorkshopContract(gangName, contractId)
    if not row then
        return false, 'Workshop contract not found'
    end
    local payload = row.payload or {}
    if (tonumber(payload.totalStripped) or 0) <= 0 then
        return false, 'Strip at least one part before cashing out'
    end
    return finalizeWorkshop(gangName, contractId, actor, 'cashed_out', nil)
end

function HiddenWorkshopModule.Complete(gangName, contractId, actor)
    if not HiddenWorkshopModule.IsEnabled() then
        return false, 'Hidden workshop disabled'
    end
    local row = getWorkshopContract(gangName, contractId)
    if not row then
        return false, 'Workshop contract not found'
    end
    local payload = row.payload or {}
    local required = tonumber(payload.totalRequired) or 0
    local stripped = tonumber(payload.totalStripped) or 0
    if required < 1 or stripped < required then
        return false, 'Workshop strip is not complete yet'
    end
    return finalizeWorkshop(gangName, contractId, actor, 'completed', 1)
end

function HiddenWorkshopModule.Fail(gangName, contractId, actor, reason)
    if not HiddenWorkshopModule.IsEnabled() then
        return false, 'Hidden workshop disabled'
    end
    local ok, dataOrErr = finalizeWorkshop(gangName, contractId, actor, 'failed', 0)
    if not ok then
        return false, dataOrErr
    end
    hwAudit(gangName, 'failed_note', actor, nil, {
        contractId = contractId,
        reason = hwCleanText(reason, 255)
    })
    return true, HiddenWorkshopModule.GetState(gangName)
end
