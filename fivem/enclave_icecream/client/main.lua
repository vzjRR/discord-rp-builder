---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — نواة العميل
    -------------------------------
    الحالة المحلية، البلبس، الإشعارات المترجمة، وتقرير حالة العالم للسيرفر.
]]

IC = IC or {}
IC.client = IC.client or {}

-- الفرع الحالي القريب من اللاعب
IC.currentBranch = nil
-- هل اللاعب مشغول بعملية (تصنيع/جولة) — يمنع التداخل
IC.busy = false

local blips = {}

-- ────────────────────────────────────────────────────────────
-- الإشعارات المترجمة (السيرفر يرسل المفتاح، العميل يترجم)
-- ────────────────────────────────────────────────────────────

RegisterNetEvent('icecream:client:notify', function(key, kind, args)
    if type(key) ~= 'string' then return end
    local message
    if type(args) == 'table' and #args > 0 then
        message = L(key, table.unpack(args))
    else
        message = L(key)
    end
    IC.notify(message, kind)
end)

-- ────────────────────────────────────────────────────────────
-- البلبس
-- ────────────────────────────────────────────────────────────

local function createBlips()
    if not Config.UI.blips then return end

    for i = 1, #Locations.Branches do
        local branch = Locations.Branches[i]
        local cfg = branch.blip
        if cfg and cfg.enabled then
            local blip = AddBlipForCoord(branch.center.x, branch.center.y, branch.center.z)
            SetBlipSprite(blip, cfg.sprite or 93)
            SetBlipColour(blip, cfg.color or 2)
            SetBlipScale(blip, cfg.scale or 0.75)
            SetBlipAsShortRange(blip, cfg.shortRange ~= false)
            SetBlipDisplay(blip, 4)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(cfg.label or branch.label)
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end
end

local function removeBlips()
    for i = 1, #blips do
        if DoesBlipExist(blips[i]) then RemoveBlip(blips[i]) end
    end
    blips = {}
end

-- ────────────────────────────────────────────────────────────
-- تتبّع الفرع الأقرب
-- ────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        local sleep = 2000
        local ped = PlayerPedId()

        if IC.isEmployee() then
            local coords = GetEntityCoords(ped)
            local branch, distance = Locations.getNearestBranch(coords)

            if branch and distance < 100.0 then
                sleep = 1000
                if IC.currentBranch ~= branch.id then
                    IC.currentBranch = branch.id
                    TriggerEvent('icecream:client:branchChanged', branch.id)
                end
            elseif IC.currentBranch then
                IC.currentBranch = nil
                TriggerEvent('icecream:client:branchChanged', nil)
            end
        elseif IC.currentBranch then
            IC.currentBranch = nil
            TriggerEvent('icecream:client:branchChanged', nil)
        end

        Wait(sleep)
    end
end)

-- ────────────────────────────────────────────────────────────
-- TextUI عند نقطة الدوام
-- ────────────────────────────────────────────────────────────

if Config.UI.textUI then
    CreateThread(function()
        local shown = false

        while true do
            local sleep = 1000
            local nearDuty = false

            if IC.isEmployee() and IC.currentBranch then
                local branch = Locations.getBranch(IC.currentBranch)
                if branch and branch.duty then
                    local distance = #(GetEntityCoords(PlayerPedId()) - branch.duty.coords)
                    nearDuty = distance <= 3.0
                    if distance < 15.0 then sleep = 400 end
                end
            end

            if nearDuty and not shown then
                lib.showTextUI(L('duty_textui'), {
                    position = 'left-center',
                    icon = 'clipboard-user',
                })
                shown = true
            elseif not nearDuty and shown then
                lib.hideTextUI()
                shown = false
            end

            Wait(sleep)
        end
    end)
end

-- ────────────────────────────────────────────────────────────
-- تقرير ساعة/طقس اللعبة للسيرفر (يستخدمه نظام تسعير الطلبات)
-- ────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(60000)
        if IC.isWorking() then
            TriggerServerEvent('icecream:server:reportWorld', GetClockHours(), GetPrevWeatherTypeHashName())
        end
    end
end)

-- ────────────────────────────────────────────────────────────
-- أدوات عامة للعميل
-- ────────────────────────────────────────────────────────────

---يشغّل أنيميشن حلقيًا على اللاعب
---@param anim table|nil { dict, clip }
---@param flag? number
function IC.client.playAnim(anim, flag)
    if not anim or not anim.dict then return end
    if not IC.loadAnimDict(anim.dict) then return end
    TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 3.0, -1.0, -1, flag or 49, 0, false, false, false)
end

function IC.client.stopAnim()
    ClearPedTasks(PlayerPedId())
end

---يقفل الإدخال أثناء عملية ويعيده بعدها
---@param state boolean
function IC.client.setBusy(state)
    IC.busy = state and true or false
end

---تحذير الذوبان الدوري
if Config.Melting.enabled then
    CreateThread(function()
        local warned = false
        while true do
            Wait(Config.Melting.checkInterval * 1000)

            if IC.isWorking() and IC.inventory == 'ox' then
                local melting = false
                for item in pairs(Recipes.byResult) do
                    if Recipes.isPerishable(item) then
                        local slots = exports.ox_inventory:Search('slots', item)
                        if type(slots) == 'table' then
                            for _, slot in ipairs(slots) do
                                local madeAt = slot.metadata and tonumber(slot.metadata.madeAt)
                                if madeAt and (os.time() - madeAt) / 60 > Config.Melting.freshMinutes then
                                    melting = true
                                    break
                                end
                            end
                        end
                        if melting then break end
                    end
                end

                if melting and not warned then
                    IC.notify(L('melt_warning'), 'warning')
                    warned = true
                elseif not melting then
                    warned = false
                end
            end
        end
    end)
end

-- ────────────────────────────────────────────────────────────
-- دورة الحياة
-- ────────────────────────────────────────────────────────────

AddEventHandler('icecream:client:playerLoaded', function()
    removeBlips()
    createBlips()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= IC.resource then return end
    removeBlips()
    lib.hideTextUI()
    IC.client.stopAnim()
end)

CreateThread(function()
    Wait(1500)
    createBlips()
end)
