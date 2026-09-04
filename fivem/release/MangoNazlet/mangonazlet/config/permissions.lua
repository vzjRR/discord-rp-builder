---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Job, grades and permissions.

    This file is also the source the installer uses to register the job with
    whichever framework is running, so the grades below are what appear in
    qbx_core / qb-core / ESX. Change them here only; nowhere else.
]]

Permissions = {}

-- Job name registered with the framework.
Permissions.job = 'mangonazlet'

-- Grades. Key = grade level as the framework stores it.
--   label   { en, ar } shown in-game and registered as the framework grade name
--   pay     framework paycheck value AND the MangoNazlet payroll amount
--   perms   what this grade may do (see MN.PERM)
Permissions.grades = {
    [0] = {
        label = { en = 'Trainee', ar = 'متدرب' },
        pay = 250,
        perms = { craft = true, register = false, storage = true, supply = false, manage = false },
    },
    [1] = {
        label = { en = 'Scooper', ar = 'موزّع' },
        pay = 400,
        perms = { craft = true, register = true, storage = true, supply = false, manage = false },
    },
    [2] = {
        label = { en = 'Ice Cream Maker', ar = 'صانع مثلجات' },
        pay = 600,
        perms = { craft = true, register = true, storage = true, supply = true, manage = false },
    },
    [3] = {
        label = { en = 'Supervisor', ar = 'مشرف' },
        pay = 850,
        perms = { craft = true, register = true, storage = true, supply = true, manage = false },
    },
    [4] = {
        label = { en = 'Manager', ar = 'مدير' },
        pay = 1100,
        perms = { craft = true, register = true, storage = true, supply = true, manage = true },
    },
    [5] = {
        label = { en = 'Owner', ar = 'المالك' },
        pay = 1500,
        perms = { craft = true, register = true, storage = true, supply = true, manage = true },
        owner = true,
    },
}

-- Grade given by the management menu when hiring.
Permissions.hireGrade = 0

-- Highest grade the management menu may assign. Keeps managers from minting
-- owners; only a server admin can create one via /mn:setjob.
Permissions.maxAssignable = 4

-- ═══════════════════════════════════════════════════════════════
-- Helpers — used identically on client and server
-- ═══════════════════════════════════════════════════════════════

---Grade definition. Never nil: an unknown grade falls back to the lowest,
---so a mismatched framework grade can never accidentally grant permissions.
---@param grade any
---@return table
function Permissions.grade(grade)
    local level = tonumber(grade) or 0
    return Permissions.grades[level] or Permissions.grades[0]
end

---@param grade any
---@param lang? string
---@return string
function Permissions.gradeLabel(grade, lang)
    local def = Permissions.grade(grade)
    lang = lang or (Config and Config.Locale) or 'en'
    return def.label[lang] or def.label.en
end

---@param grade any
---@param permission string
---@return boolean
function Permissions.can(grade, permission)
    return Permissions.grade(grade).perms[permission] == true
end

---@param grade any
---@return boolean
function Permissions.isOwner(grade)
    return Permissions.grade(grade).owner == true
end

---Highest grade defined.
---@return number
function Permissions.maxGrade()
    local max = 0
    for level in pairs(Permissions.grades) do
        if level > max then max = level end
    end
    return max
end

---Payroll amount for a grade.
---@param grade any
---@return number
function Permissions.pay(grade)
    return Permissions.grade(grade).pay or 0
end

---Ordered grade list, used by menus and by the installer.
---@return table[] { level, label, pay, owner }
function Permissions.ordered()
    local out = {}
    for level, def in pairs(Permissions.grades) do
        out[#out + 1] = { level = level, def = def }
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end
