Locales = Locales or {}
Locales.current = Locales.current or (Config and Config.Locale) or 'en'

local function formatLocale(value, args)
    if type(value) ~= 'string' then
        return value
    end
    if type(args) ~= 'table' then
        return value
    end
    return (value:gsub('{(%w+)}', function(key)
        local repl = args[key]
        if repl == nil then
            return '{' .. key .. '}'
        end
        return tostring(repl)
    end))
end

local function activeLocale()
    return Locales[Locales.current] or Locales.en or {}
end

function LocaleText(key, args)
    local lang = activeLocale()
    local fallback = Locales.en or {}
    local value = lang[key] or fallback[key] or key
    return formatLocale(value, args)
end

function LocaleNui()
    local lang = activeLocale()
    local fallback = Locales.en or {}
    local nui = {}
    if type(fallback.nui) == 'table' then
        for key, value in pairs(fallback.nui) do
            nui[key] = value
        end
    end
    if type(lang.nui) == 'table' then
        for key, value in pairs(lang.nui) do
            nui[key] = value
        end
    end
    return nui
end

function SetLocale(language)
    if type(language) ~= 'string' then return end
    if Locales[language] then
        Locales.current = language
    end
end
