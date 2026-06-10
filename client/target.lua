ClientTarget = ClientTarget or {}

function ClientTarget.GetIntegration()
    local integrations = Config.Integrations or {}
    if integrations.target and integrations.target ~= 'auto' then
        return integrations.target
    end
    return Config.TargetResource or 'auto'
end
