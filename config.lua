Config = Config or {}

Config.Framework = 'auto' -- auto | qb | esx | qbox | ox
Config.Locale = 'en' -- en | es | de
Config.Debug = true
Config.MinBossGrade = 99 -- Used only when framework does not expose explicit boss flag
Config.MinGangBossGrade = 99 -- Same fallback, but for gang menu access
Config.useinbuiltgangframes = true -- true = use framework gang system, false = use built-in gang system for QB/ESX

Config.UseTarget = false
Config.TargetResource = 'ox_target' -- ox_target | qb-target
Config.UseCommand = true
Config.OpenBossCommand = 'bossmenu'
Config.OpenGangCommand = 'gangmenu'
Config.InteractionDistance = 2.0
Config.EnableGangMenu = true

Config.BossMenus = {
    police = { vec3(447.16, -974.31, 30.47) },
    ambulance = { vec3(311.21, -599.36, 43.29) },
    cardealer = { vec3(-32.94, -1114.64, 26.42) },
    mechanic = { vec3(-347.59, -133.35, 39.01) },
    harmony = { vec3(1186.83, 2637.78, 39.27) }
}

Config.GangMenus = {
    lostmc = { vec3(0.0, 0.0, 0.0) },
    ballas = { vec3(0.0, 0.0, 0.0) },
    vagos = { vec3(0.0, 0.0, 0.0) },
    cartel = { vec3(0.0, 0.0, 0.0) }
}

Config.InbuiltGangRanks = {
    [0] = 'Recruit',
    [1] = 'Member',
    [2] = 'Shot Caller',
    [3] = 'Underboss',
    [4] = 'Boss'
}

-- Advanced built-in gang model (used when Config.useinbuiltgangframes = false for QB/ESX).
-- You can define custom label + rank naming/style per gang.
Config.InbuiltGangDefinitions = {
    lostmc = {
        label = 'The Lost MC',
        maxGrade = 4,
        style = {
            borderColor = '#8d9fb8',
            badgeBackground = '#1f2a3a',
            badgeColor = '#d7e1f0'
        },
        ranks = {
            [0] = { name = 'Prospect', style = { badgeBackground = '#1a2433', badgeColor = '#b9c7dc' } },
            [1] = { name = 'Road Captain', style = { badgeBackground = '#233247', badgeColor = '#d4e0f1' } },
            [2] = { name = 'Sergeant at Arms', style = { badgeBackground = '#2c3f58', badgeColor = '#e5eefb' } },
            [3] = { name = 'Vice President', style = { badgeBackground = '#37506f', badgeColor = '#f3f8ff' } },
            [4] = { name = 'President', style = { badgeBackground = '#4a6488', badgeColor = '#ffffff' } },
        }
    },
    ballas = {
        label = 'Ballas',
        maxGrade = 4,
        style = {
            borderColor = '#7f4cb3',
            badgeBackground = '#2a193c',
            badgeColor = '#e5d1ff'
        },
        ranks = {
            [0] = { name = 'Youngin', style = { badgeBackground = '#241534', badgeColor = '#d7bbfb' } },
            [1] = { name = 'Runner', style = { badgeBackground = '#301e45', badgeColor = '#e4ccff' } },
            [2] = { name = 'Enforcer', style = { badgeBackground = '#3b2755', badgeColor = '#eddcff' } },
            [3] = { name = 'Lieutenant', style = { badgeBackground = '#4a3368', badgeColor = '#f6ecff' } },
            [4] = { name = 'OG', style = { badgeBackground = '#5e4383', badgeColor = '#ffffff' } },
        }
    },
    vagos = {
        label = 'Vagos',
        maxGrade = 4,
        style = {
            borderColor = '#b88a2f',
            badgeBackground = '#3c2d12',
            badgeColor = '#ffeac4'
        },
        ranks = {
            [0] = { name = 'Soldado', style = { badgeBackground = '#33260f', badgeColor = '#f2d8a8' } },
            [1] = { name = 'Veterano', style = { badgeBackground = '#463214', badgeColor = '#ffe3b6' } },
            [2] = { name = 'Capitan', style = { badgeBackground = '#5b421b', badgeColor = '#ffeecf' } },
            [3] = { name = 'Teniente', style = { badgeBackground = '#715326', badgeColor = '#fff5de' } },
            [4] = { name = 'Jefe', style = { badgeBackground = '#8f6b33', badgeColor = '#ffffff' } },
        }
    },
    cartel = {
        label = 'Cartel',
        maxGrade = 4,
        style = {
            borderColor = '#5d8f5d',
            badgeBackground = '#1f3521',
            badgeColor = '#d7f0d7'
        },
        ranks = {
            [0] = { name = 'Foot Soldier', style = { badgeBackground = '#1a2d1c', badgeColor = '#c4e2c4' } },
            [1] = { name = 'Collector', style = { badgeBackground = '#243f27', badgeColor = '#d4efd4' } },
            [2] = { name = 'Plaza Lead', style = { badgeBackground = '#2f5333', badgeColor = '#e3f7e3' } },
            [3] = { name = 'Lieutenant', style = { badgeBackground = '#3a673f', badgeColor = '#f1fdf1' } },
            [4] = { name = 'Patron', style = { badgeBackground = '#4a844f', badgeColor = '#ffffff' } },
        }
    }
}

Config.JobIcons = {
    police = 'fa-shield-halved',
    ambulance = 'fa-truck-medical',
    mechanic = 'fa-screwdriver-wrench',
    cardealer = 'fa-car-side'
}

Config.GangIcons = {
    lostmc = 'fa-skull',
    ballas = 'fa-hand-fist',
    vagos = 'fa-mask-face',
    cartel = 'fa-dragon'
}

Config.DefaultIcon = 'fa-briefcase'

-- Optional hard overrides for smart org archetype detection (keyed by lowercased role name or label).
-- Valid ids: corporate, law, medical, mechanic, dealer, hospitality, logistics, security,
-- gang_street, gang_biker, gang_cartel, gang_mafia
Config.OrgArchetypeOverrides = {
    -- ['police'] = 'law',
    -- ['vehicle dealer'] = 'dealer'
}

Config.Modules = {
    DynamicRanks = true,
    RankPermissions = true,
    EmployeeProfiles = true,
    SalaryManagement = true,
    Payroll = true,
    BusinessInventory = true,
    BusinessVault = true,
    GangCashLocker = true,
    Uniforms = true,
    Applications = true,
    Announcements = true,
    AdminPanel = true,
    Taxes = true,
    BillsInvoices = true,
    ScheduledTasks = true,
    GangNotoriety = true,
    GangMarkers = true,
    GangGarages = true,
    GangTerritories = true,
    GangRackets = true,
    GangGraffiti = true,
    GangContracts = true,
    Webhooks = true,
    Analytics = true,
    Cameras = true,
    PublicAPI = true
}

Config.Webhooks = {
    enabled = true,
    redactIdentifiers = false,
    timeoutMs = 5000,
    retryBaseMs = 2000,
    maxRetries = 4,
    batchWindowMs = 3500,
    batchSize = 10,
    categories = {
        'employee',
        'gang',
        'finance',
        'inventory',
        'admin',
        'security',
        'applications',
        'territories',
        'contracts'
    },
    urls = {
        employee = '',
        gang = '',
        finance = '',
        inventory = '',
        admin = '',
        security = '',
        applications = '',
        territories = '',
        contracts = ''
    }
}

Config.Integrations = {
    inventory = 'auto', -- auto | ox_inventory | qb-inventory | ps-inventory | lj-inventory | qs-inventory | none
    clothing = 'auto', -- auto | qb-clothing | illenium-appearance | fivem-appearance | skinchanger | none
    banking = 'auto', -- auto | qb-banking | Renewed-Banking | okokBanking | esx_addonaccount | none
    tax = 'none', -- none | auto | ap-government
    target = 'auto', -- auto | ox_target | qb-target | none
    menuNotify = 'auto', -- auto | framework | ox_lib | custom
    phone = 'none', -- none | yseries | qb-phone | qs-smartphone | custom
    camera = 'auto', -- auto | qb-policejob | esx_policejob | rcore_cctv | loaf_cctv | okokCCTV | tk_cctv | native | custom | none
    screenshot = 'auto' -- auto | screenshot-basic | screencapture | screenhost-basic | custom | none
}

Config.Screenshots = {
    encoding = 'webp',
    quality = 0.28,
    maxBytes = 1800000,
    -- Auto fallback order. Any provider with screenshot-basic compatible client export
    -- (requestScreenshot) can be added here without code changes.
    autoProviderOrder = {
        'screenshot-basic',
        'screencapture',
        'screenhost-basic'
    },
    providers = {
        -- screenshot-basic compatible client export:
        -- exports['resource']:requestScreenshot(options, cb)
        ['screenshot-basic'] = { resource = 'screenshot-basic', mode = 'screenshot_basic_client' },
        ['screencapture'] = { resource = 'screencapture', mode = 'screenshot_basic_client' },
        ['screenhost-basic'] = { resource = 'screenhost-basic', mode = 'screenshot_basic_client' },
        -- Custom provider example (callback export):
        -- custom = { resource = 'my_capture', mode = 'client_export', exportName = 'requestScreenshot', callbackFirst = false }
    }
}

Config.Cameras = {
    closeMenuOnOpen = true,
    allowedArchetypes = {
        law = true,
        security = true
    },
    autoProviderOrder = {
        'qb-policejob',
        'esx_policejob',
        'rcore_cctv',
        'loaf_cctv',
        'okokCCTV',
        'tk_cctv',
        'native'
    },
    -- Optional per-org override for provider selection.
    providerByOrg = {
        -- police = 'qb-policejob'
    },
    -- Optional direct provider map (for custom scripts).
    providers = {
        custom = {
            resource = '',
            openEvent = '',
            openArgsMode = 'feed', -- feed | id | label | raw
            useExport = false,
            exportName = '',
            exportArgsMode = 'feed'
        }
    },
    -- Camera feeds prioritized by org name if present.
    feedsByOrg = {
        police = {
            { id = 'mrpd_front', label = 'MRPD Front', icon = 'shield', coords = { x = 432.45, y = -982.30, z = 36.20, w = 180.0 } },
            { id = 'mrpd_garage', label = 'MRPD Garage', icon = 'garage', coords = { x = 449.20, y = -1018.40, z = 35.80, w = 90.0 } },
            { id = 'pillbox_front', label = 'Pillbox Front', icon = 'medical', coords = { x = 298.50, y = -584.10, z = 49.40, w = 160.0 } },
            { id = 'legion_square', label = 'Legion Square', icon = 'city', coords = { x = 169.80, y = -985.40, z = 34.80, w = 30.0 } }
        }
    },
    feedsByArchetype = {
        law = {
            { id = 'pd_lobby', label = 'PD Lobby', icon = 'shield', coords = { x = 441.10, y = -981.40, z = 34.80, w = 180.0 } },
            { id = 'city_hall', label = 'City Hall Exterior', icon = 'city', coords = { x = -539.20, y = -208.20, z = 43.20, w = 65.0 } }
        },
        security = {
            { id = 'security_plaza', label = 'Plaza Security', icon = 'watch', coords = { x = 238.30, y = -876.10, z = 34.20, w = 250.0 } }
        }
    }
}

Config.Security = {
    sessionTokenTtlSeconds = 120,
    nonceTtlSeconds = 30,
    maxAmount = 5000000,
    maxHireDistance = 10.0,
    maxMarkerCreateDistance = 15.0,
    maxMoneyActionAmount = 5000000,
    allowOfflineFire = true,
    requireReasonForFire = false,
    requireReasonForWithdraw = false,
    requireSecondApprovalForLargeWithdraw = false,
    largeWithdrawThreshold = 250000,
    enableActionCooldowns = true,
    webhookOnSuspiciousAction = false,
    strictPermissionMode = true,
    lockoutFailThreshold = 12,
    lockoutSeconds = 120,
    rateLimits = {
        nui = { count = 24, windowMs = 5000 },
        money = { count = 8, windowMs = 8000 },
        manage = { count = 10, windowMs = 8000 }
    }
}

Config.Payroll = {
    allowPartial = true,
    autoEnabled = false,
    autoIntervalMinutes = 60
}

Config.ScheduledTasks = {
    enabled = false,
    pollIntervalSeconds = 15
}

Config.TaxSettings = {
    enabled = true,
    intervalMinutes = 30,
    recurringDays = 7,
    autoPayDefault = false,
    graceDays = 2,
    penaltyPercent = 10,
    apGovernmentLabel = 'Business'
}

Config.GangContractTemplates = {
    delivery = { money = 5000, notoriety = 2 },
    collection = { money = 4500, notoriety = 1 },
    robbery_setup = { money = 7000, notoriety = 3 },
    dealer_task = { money = 5200, notoriety = 2 },
    territory_disruption = { money = 6000, notoriety = 2 },
    item_sourcing = { money = 4800, notoriety = 1 }
}

Config.GangSystems = {
    territoryDefendSeconds = 180,
    territoryReward = 0,
    territoryLossPenalty = 0,
    territoryLeaderboardDays = 30,
    racketIncomeTickMinutes = 20,
    racketBaseIncome = 250,
    graffitiDefaultTtlMinutes = 120,
    graffitiMaxPerGang = 120,
    graffitiMaxPerPlayer = 30,
    graffitiMinDistance = 8.0,
    territoryTaggingEnabled = true,
    territoryTagDefaultTtlMinutes = 0, -- 0 = no expiry; clean manually
    territoryTagMinVertices = 4,
    territoryTagMaxVertices = 12,
    territoryTagCloseDistance = 12.0,
    territoryTagMaxSpanMeters = 350.0,
    territoryTagMinArea = 800.0,
    territoryTagMaxArea = 50000.0,
    territoryTagMaxPointAgeMinutes = 45,
    territoryTagTerritoryType = 'basic',
    graffitiRenderDistance = 55.0,
    graffitiDrawDistance = 22.0,
    graffitiMaxActiveRenders = 64,
    graffitiRenderTagPrefix = true,
    contractCooldownSeconds = 120,
    contractMaxActive = 6
}

Config.Performance = {
    employeeCacheMs = 4000,
    nearbyRange = 10.0,
    markerFarSleep = 1000,
    markerNearSleep = 0
}

Config.Society = {
    unemployedName = 'unemployed',
    unemployedLabel = 'Unemployed',
    noGangName = 'none',
    noGangLabel = 'No Gang'
}

Config.Database = {
    qb = {
        playerTable = 'players',
        identifierColumn = 'citizenid',
        nameColumn = 'name',
        charinfoColumn = 'charinfo',
        jobJsonColumn = 'job',
        gangJsonColumn = 'gang'
    },
    qbox = {
        playerTable = 'players',
        identifierColumn = 'citizenid',
        nameColumn = 'name',
        charinfoColumn = 'charinfo',
        jobJsonColumn = 'job',
        gangJsonColumn = 'gang'
    },
    esx = {
        playerTable = 'users',
        identifierColumn = 'identifier',
        firstnameColumn = 'firstname',
        lastnameColumn = 'lastname',
        jobColumn = 'job',
        gradeColumn = 'job_grade'
    },
    ox = {
        -- Adjust these if your ox_core schema differs.
        playerTable = 'characters',
        identifierColumn = 'charid',
        firstnameColumn = 'firstName',
        lastnameColumn = 'lastName',
        groupsColumn = 'groups'
    }
}
