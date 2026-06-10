ServerFramework = ServerFramework or {}

function ServerFramework.GetName()
    if type(Framework) == 'table' and Framework.GetName then
        return Framework.GetName()
    end
    return 'unknown'
end
