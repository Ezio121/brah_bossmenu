RanksModule = RanksModule or {}

function RanksModule.IsEnabled()
    return Config.Modules and Config.Modules.DynamicRanks == true
end
