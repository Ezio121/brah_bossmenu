ContractsModule = ContractsModule or {}
ContractsModule.cooldowns = ContractsModule.cooldowns or {}

function ContractsModule.IsEnabled()
    return Config.Modules and Config.Modules.GangContracts == true
end

local function ctCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function ctAudit(gangName, action, actor, target, metadata)
    if AuditModule and AuditModule.Write then
        AuditModule.Write('gang', gangName, 'contract_' .. tostring(action), actor, target, metadata or {})
        return
    end
    MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
        VALUES (?, ?, ?, ?, ?)]], {
        gangName,
        'contract_' .. tostring(action),
        actor,
        target,
        metadata and json.encode(metadata) or nil
    })
end

local function contractTemplate(contractType)
    local templates = Config.GangContractTemplates or {}
    return templates[contractType]
end

local function contractCooldownSeconds()
    return tonumber(Config.GangSystems and Config.GangSystems.contractCooldownSeconds or 120) or 120
end

local function contractMaxActive()
    return tonumber(Config.GangSystems and Config.GangSystems.contractMaxActive or 6) or 6
end

local function nowUnix()
    return os.time()
end

function ContractsModule.List(gangName, status)
    local cleanStatus = ctCleanText(status, 24)
    local rows
    if cleanStatus ~= '' and cleanStatus ~= 'all' then
        rows = MySQL.query.await([[SELECT id, contract_type, status, reward_json, payload, accepted_by, accepted_at, completed_at, created_at
            FROM bossmenu_gang_contracts
            WHERE gang_name = ? AND status = ? AND contract_type NOT LIKE 'hw\_%' ESCAPE '\'
            ORDER BY id DESC LIMIT 200]], { gangName, cleanStatus }) or {}
    else
        rows = MySQL.query.await([[SELECT id, contract_type, status, reward_json, payload, accepted_by, accepted_at, completed_at, created_at
            FROM bossmenu_gang_contracts
            WHERE gang_name = ? AND contract_type NOT LIKE 'hw\_%' ESCAPE '\'
            ORDER BY id DESC LIMIT 200]], { gangName }) or {}
    end
    for i = 1, #rows do
        rows[i].reward_json = (type(rows[i].reward_json) == 'string' and json.decode(rows[i].reward_json)) or rows[i].reward_json or {}
        rows[i].payload = (type(rows[i].payload) == 'string' and json.decode(rows[i].payload)) or rows[i].payload or {}
    end
    return rows
end

function ContractsModule.Create(gangName, payload, actor)
    if not ContractsModule.IsEnabled() then
        return false, 'Contracts disabled'
    end
    local contractType = ctCleanText(payload and payload.contractType, 40)
    local template = contractTemplate(contractType)
    local data = type(payload and payload.payload) == 'table' and payload.payload or {}
    local reward = type(template) == 'table' and template or {}
    if contractType == '' then
        return false, 'Invalid contract type'
    end
    if not template then
        return false, 'Unsupported contract type'
    end
    local activeCount = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM bossmenu_gang_contracts
        WHERE gang_name = ? AND status IN ('available','active')]], { gangName }) or 0) or 0
    if activeCount >= contractMaxActive() then
        return false, 'Active contract limit reached'
    end
    local key = tostring(gangName) .. ':create'
    local last = tonumber(ContractsModule.cooldowns[key] or 0) or 0
    local now = nowUnix()
    if now - last < contractCooldownSeconds() then
        return false, 'Contract board cooldown active'
    end
    ContractsModule.cooldowns[key] = now
    local id = MySQL.insert.await([[INSERT INTO bossmenu_gang_contracts (gang_name, contract_type, status, reward_json, payload)
        VALUES (?, ?, 'available', ?, ?)]], {
        gangName, contractType, json.encode(reward), json.encode(data)
    })
    ctAudit(gangName, 'create', actor, nil, {
        id = id,
        contractType = contractType
    })
    TriggerEvent('qb-management:server:hook', 'gang_contract_created', {
        gang = gangName,
        contractId = id,
        contractType = contractType,
        actor = actor
    })
    return true, { id = id }
end

function ContractsModule.Accept(gangName, contractId, actor)
    if not ContractsModule.IsEnabled() then
        return false, 'Contracts disabled'
    end
    local id = tonumber(contractId) or 0
    if id < 1 then return false, 'Invalid contract' end
    local contractType = MySQL.scalar.await('SELECT contract_type FROM bossmenu_gang_contracts WHERE id = ? AND gang_name = ? LIMIT 1', {
        id, gangName
    })
    if HiddenWorkshopModule and HiddenWorkshopModule.IsWorkshopContractType and HiddenWorkshopModule.IsWorkshopContractType(contractType) then
        return false, 'Use the hidden workshop board for this contract'
    end
    local activeCount = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM bossmenu_gang_contracts
        WHERE gang_name = ? AND status = 'active']], { gangName }) or 0) or 0
    if activeCount >= contractMaxActive() then
        return false, 'Too many active contracts'
    end
    local affected = MySQL.update.await([[UPDATE bossmenu_gang_contracts
        SET status = 'active', accepted_by = ?, accepted_at = NOW()
        WHERE id = ? AND gang_name = ? AND status = 'available']], {
        actor, id, gangName
    })
    if (affected or 0) < 1 then
        return false, 'Contract unavailable'
    end
    ctAudit(gangName, 'accept', actor, nil, { id = id })
    TriggerEvent('qb-management:server:hook', 'OnGangContractAccepted', {
        gang = gangName,
        contractId = id,
        actor = actor
    })
    return true
end

function ContractsModule.Complete(gangName, contractId, actor, success)
    if not ContractsModule.IsEnabled() then
        return false, 'Contracts disabled'
    end
    local id = tonumber(contractId) or 0
    if id < 1 then return false, 'Invalid contract' end
    local row = MySQL.single.await([[SELECT reward_json, payload, contract_type
        FROM bossmenu_gang_contracts
        WHERE id = ? AND gang_name = ? LIMIT 1]], {
        id, gangName
    })
    if not row then
        return false, 'Contract not found'
    end
    if HiddenWorkshopModule and HiddenWorkshopModule.IsWorkshopContractType and HiddenWorkshopModule.IsWorkshopContractType(row.contract_type) then
        return false, 'Use the hidden workshop flow for this contract'
    end
    local finalStatus = success == false and 'failed' or 'completed'
    local affected = MySQL.update.await([[UPDATE bossmenu_gang_contracts
        SET status = ?, completed_at = NOW()
        WHERE id = ? AND gang_name = ? AND status = 'active']], {
        finalStatus, id, gangName
    })
    if (affected or 0) < 1 then
        return false, 'Contract not active'
    end
    ctAudit(gangName, finalStatus, actor, nil, { id = id })
    TriggerEvent('qb-management:server:hook', finalStatus == 'completed' and 'OnGangContractCompleted' or 'OnGangContractFailed', {
        gang = gangName,
        contractId = id,
        actor = actor
    })
    return true, {
        id = id,
        status = finalStatus,
        reward = (type(row.reward_json) == 'string' and json.decode(row.reward_json)) or row.reward_json or {},
        payload = (type(row.payload) == 'string' and json.decode(row.payload)) or row.payload or {},
        contractType = row.contract_type
    }
end
