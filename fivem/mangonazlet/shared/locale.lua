---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Locale module
    Self-contained: no dependency on ox_lib's convar-driven locale, so the same
    strings can be handed to Lua, to the NUI, and to server-side notifications.
]]

MN = MN or {}
MN.Locales = MN.Locales or {}

local active, fallback

---Resolve the active language table. Falls back to English, then to an empty
---table, so a missing locale file can never hard-crash the resource.
local function resolve()
    fallback = MN.Locales.en or {}
    active = MN.Locales[Config and Config.Locale or 'en'] or fallback
end

---Translate a key, formatting any %s placeholders.
---Returns the key itself when missing so a typo shows up in-game as the key
---rather than crashing or rendering "nil".
---@param key string
---@return string
function T(key, ...)
    if not active then resolve() end

    local value = active[key]
    if value == nil then value = fallback[key] end
    if type(value) ~= 'string' then return key end

    if select('#', ...) == 0 then return value end

    local ok, formatted = pcall(string.format, value, ...)
    return ok and formatted or value
end

---Text direction of the active language ('rtl' | 'ltr'). Drives the NUI.
---@return string
function MN.dir()
    if not active then resolve() end
    return active.dir or 'ltr'
end

---The whole active table — handed to the NUI in one message so the interface
---never has to round-trip per string.
---@return table
function MN.localeTable()
    if not active then resolve() end
    local out = {}
    for k, v in pairs(fallback) do out[k] = v end
    for k, v in pairs(active) do out[k] = v end
    return out
end

---Re-resolve after Config loads (load order safety).
function MN.reloadLocale() resolve() end
