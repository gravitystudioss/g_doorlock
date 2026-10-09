Locales = Locales or {}

local function current()
    return Locales[Config.Locale] or Locales.en or {}
end

function L(key, ...)
    local text = current()[key] or (Locales.en and Locales.en[key]) or key

    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then
            return formatted
        end
    end

    return text
end

-- all strings for the nui, english fills the missing ones
function GetLocaleTable()
    local out = {}
    for k, v in pairs(Locales.en or {}) do
        out[k] = v
    end
    for k, v in pairs(current()) do
        out[k] = v
    end
    return out
end
