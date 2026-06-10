Framework = Framework or {}

local function getState(name)
    return GetResourceState(name)
end

local function started(name)
    local state = getState(name)
    return state == 'started' or state == 'starting'
end

local function detectFramework()
    local wanted = tostring(Config.Framework or 'auto'):lower()
    if wanted ~= 'auto' then
        return wanted
    end

    if started('qbx_core') then return 'qbox' end
    if started('qb-core') then return 'qb' end
    if started('es_extended') then return 'esx' end
    if started('ox_core') then return 'ox' end
    return 'unknown'
end

Framework.Name = detectFramework()

function Framework.Is(name)
    return Framework.Name == name
end

function Framework.GetName()
    return Framework.Name
end

if not IsDuplicityVersion() then
    local function qbData()
        local ok, data = pcall(function()
            if Framework.Is('qbox') and exports.qbx_core and exports.qbx_core.GetPlayerData then
                return exports.qbx_core:GetPlayerData()
            end
            return exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
        end)
        if not ok or type(data) ~= 'table' then return nil end
        return data
    end

    function Framework.GetClientPlayerData()
        if Framework.Is('qb') or Framework.Is('qbox') then
            local data = qbData()
            if not data then return nil end
            local job = data.job or {}
            local gang = data.gang or {}
            return {
                identifier = data.citizenid,
                name = ((data.charinfo and data.charinfo.firstname) or 'Unknown') .. ' ' .. ((data.charinfo and data.charinfo.lastname) or ''),
                job = {
                    name = job.name,
                    label = job.label or job.name,
                    grade = tonumber(job.grade and (job.grade.level or job.grade) or 0) or 0,
                    isBoss = job.isboss == true,
                    onDuty = job.onduty == true
                },
                gang = {
                    name = gang.name,
                    label = gang.label or gang.name,
                    grade = tonumber(gang.grade and (gang.grade.level or gang.grade) or 0) or 0,
                    isBoss = gang.isboss == true
                }
            }
        elseif Framework.Is('esx') then
            local ESX = exports['es_extended']:getSharedObject()
            local data = ESX.GetPlayerData()
            if not data then return nil end
            local job = data.job or {}
            local grade = tonumber(job.grade) or 0
            local bossByName = tostring(job.grade_name or ''):lower() == 'boss'
            local minGrade = tonumber(Config.MinBossGrade or 99) or 99
            return {
                identifier = data.identifier,
                name = data.name or 'Unknown',
                job = {
                    name = job.name,
                    label = job.label or job.name,
                    grade = grade,
                    isBoss = bossByName or grade >= minGrade,
                    onDuty = true
                },
                gang = nil
            }
        elseif Framework.Is('ox') then
            local state = LocalPlayer and LocalPlayer.state or {}
            local groups = state and state.groups or {}
            local active = state and state.activeGroup
            local jobName = active
            local grade = 0
            if type(groups) == 'table' then
                if not jobName then
                    for k, v in pairs(groups) do
                        if type(v) == 'number' then
                            jobName = k
                            grade = v
                            break
                        end
                    end
                else
                    grade = tonumber(groups[jobName]) or 0
                end
            end
            return {
                identifier = state and state.charid,
                name = GetPlayerName(PlayerId()),
                job = {
                    name = jobName,
                    label = jobName,
                    grade = grade,
                    isBoss = grade >= 3,
                    onDuty = true
                },
                gang = nil
            }
        end

        return nil
    end
end
