ClientMarkers = ClientMarkers or {}

function ClientMarkers.IsEnabled()
    return Config.UseTarget ~= true
end
