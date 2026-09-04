---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — المواقع
    ---------------------------
    كل فرع (branch) وحدة مستقلة لها محطاتها وبلبها وحساب مبيعاتها.
    تقدر تضيف فروع بلا حدود — فقط انسخ الجدول وغيّر id والإحداثيات.

    كيف تجيب إحداثيات؟  اكتب بالشات:  /ic_coords
    ينسخ لك سطر جاهز فيه vector3 و vector4 والهيدنق (يتطلب رتبة أدمن، انظر server/main.lua).
]]

Locations = {}

-- ────────────────────────────────────────────────────────────
-- الفروع
-- ────────────────────────────────────────────────────────────
Locations.Branches = {
    {
        id = 'vespucci',
        label = 'مثلجات فيسبوتشي',
        -- مركز الفرع (يُستخدم للبلب ولتوزيع الطلبات)
        center = vec3(-1223.5, -1576.9, 4.6),

        blip = {
            enabled = true,
            sprite = 93,        -- أيقونة مطعم
            color = 2,          -- أخضر
            scale = 0.75,
            label = 'مثلجات فيسبوتشي',
            shortRange = true,
        },

        -- نقطة تسجيل الدوام
        duty = {
            coords = vec3(-1225.31, -1580.02, 4.61),
            size = vec3(1.2, 1.2, 2.0),
            rotation = 35.0,
        },

        -- الكاشير (الفوترة اليدوية + استقبال طلبات الزبائن)
        register = {
            coords = vec3(-1220.05, -1578.30, 4.61),
            size = vec3(1.6, 1.0, 1.5),
            rotation = 35.0,
        },

        -- موقف الزبائن NPC (يقف الزبون هنا وينتظر طلبه)
        customer = {
            -- vector4: x, y, z, heading
            stand = vec4(-1218.95, -1580.35, 4.61, 215.0),
            -- من أين يمشي الزبون قبل ما يوصل الكاونتر
            walkFrom = vec3(-1212.60, -1585.10, 4.30),
        },

        -- الفريزر = ستاش الفرع
        freezer = {
            coords = vec3(-1227.80, -1576.10, 4.61),
            size = vec3(1.4, 1.4, 2.0),
            rotation = 35.0,
            slots = 60,
            maxWeight = 180000,  -- 180kg
        },

        -- محطات العمل. كل محطة تُطابق مفتاحًا في config/recipes.lua
        stations = {
            {
                id = 'softserve',
                label = 'ماكينة السوفت سيرف',
                coords = vec3(-1222.90, -1576.20, 4.61),
                size = vec3(1.4, 1.0, 1.6),
                rotation = 35.0,
                icon = 'ice-cream',
            },
            {
                id = 'prep',
                label = 'طاولة التحضير',
                coords = vec3(-1224.65, -1574.90, 4.61),
                size = vec3(2.0, 1.2, 1.5),
                rotation = 35.0,
                icon = 'utensils',
            },
            {
                id = 'blender',
                label = 'الخلاط',
                coords = vec3(-1221.40, -1574.55, 4.61),
                size = vec3(1.0, 1.0, 1.5),
                rotation = 35.0,
                icon = 'blender',
            },
            {
                id = 'oven',
                label = 'فرن الوافل',
                coords = vec3(-1226.15, -1573.40, 4.61),
                size = vec3(1.4, 1.0, 1.8),
                rotation = 35.0,
                icon = 'fire-burner',
            },
        },

        -- مكتب المدير (منيو البوس)
        boss = {
            coords = vec3(-1229.10, -1571.90, 4.61),
            size = vec3(1.2, 1.2, 2.0),
            rotation = 35.0,
        },

        -- نقطة استلام المواد الخام من المورّد
        supply = {
            coords = vec3(-1231.20, -1578.50, 4.61),
            size = vec3(1.6, 1.6, 2.0),
            rotation = 35.0,
        },

        -- إخراج شاحنة جولة التوريد
        supplyVehicle = {
            spawn = vec4(-1216.10, -1564.85, 3.60, 125.0),
        },

        -- إخراج عربة المثلجات
        truck = {
            spawn = vec4(-1210.35, -1568.20, 3.60, 125.0),
            -- نقطة تسليم/تخزين العربة
            park = vec3(-1210.35, -1568.20, 3.60),
        },
    },
}

-- ────────────────────────────────────────────────────────────
-- نقاط جولة التوريد بالشاحنة
-- يُختار منها عشوائيًا بعدد Config.Supply.run.pickups
-- ────────────────────────────────────────────────────────────
Locations.SupplyPickups = {
    { label = 'مستودع الألبان',    coords = vec3(96.85, 6412.05, 31.40) },
    { label = 'مزرعة الفواكه',      coords = vec3(2225.35, 5157.05, 58.95) },
    { label = 'ميناء البضائع',      coords = vec3(-337.15, -2695.45, 6.00) },
    { label = 'مصنع السكر',         coords = vec3(1204.15, -3115.65, 5.55) },
    { label = 'سوق الجملة',         coords = vec3(-1058.05, -1400.75, 5.55) },
}

-- ────────────────────────────────────────────────────────────
-- نقاط البيع المتنقل (عربة المثلجات)
-- weight = وزن احتمالية الزبائن في هذه النقطة
-- ────────────────────────────────────────────────────────────
Locations.TruckSpots = {
    { label = 'شاطئ فيسبوتشي',      coords = vec3(-1180.25, -1500.40, 4.35), radius = 35.0, weight = 5 },
    { label = 'رصيف ديل بيرو',      coords = vec3(-1620.50, -1032.85, 13.15), radius = 30.0, weight = 4 },
    { label = 'حديقة ليجيون',        coords = vec3(210.35, -935.50, 30.70),   radius = 25.0, weight = 4 },
    { label = 'ملعب فيسبوتشي',       coords = vec3(-1231.90, -1470.10, 4.35), radius = 25.0, weight = 3 },
    { label = 'مطار لوس سانتوس',     coords = vec3(-1037.15, -2737.55, 20.15), radius = 30.0, weight = 2 },
    { label = 'جبل تشيلياد',         coords = vec3(450.85, 5566.30, 781.20),  radius = 20.0, weight = 1 },
    { label = 'ساندي شورز',          coords = vec3(1961.45, 3740.60, 32.35),  radius = 25.0, weight = 2 },
}

-- ────────────────────────────────────────────────────────────
-- موديلات الزبائن NPC
-- ────────────────────────────────────────────────────────────
Locations.CustomerModels = {
    'a_f_y_beach_01', 'a_m_y_beach_01', 'a_m_y_beach_02',
    'a_f_y_tourist_01', 'a_m_y_tourist_01', 'a_f_y_hipster_01',
    'a_m_y_hipster_01', 'a_f_m_beach_01', 'a_m_m_tourist_01',
    'a_f_y_genhot_01', 'a_m_y_genstreet_01', 'a_f_y_soucent_01',
}

-- ────────────────────────────────────────────────────────────
-- دوال مساعدة (تُستخدم على الطرفين)
-- ────────────────────────────────────────────────────────────

---يرجّع تعريف فرع حسب المعرّف
---@param id string
---@return table|nil
function Locations.getBranch(id)
    for i = 1, #Locations.Branches do
        if Locations.Branches[i].id == id then
            return Locations.Branches[i]
        end
    end
    return nil
end

---يرجّع تعريف محطة داخل فرع
---@param branchId string
---@param stationId string
---@return table|nil
function Locations.getStation(branchId, stationId)
    local branch = Locations.getBranch(branchId)
    if not branch or not branch.stations then return nil end
    for i = 1, #branch.stations do
        if branch.stations[i].id == stationId then
            return branch.stations[i]
        end
    end
    return nil
end

---يرجّع أقرب فرع لإحداثيات معينة، مع المسافة
---@param coords vector3
---@return table|nil branch, number distance
function Locations.getNearestBranch(coords)
    local best, bestDist
    for i = 1, #Locations.Branches do
        local branch = Locations.Branches[i]
        local dist = #(coords - branch.center)
        if not bestDist or dist < bestDist then
            best, bestDist = branch, dist
        end
    end
    return best, bestDist or math.huge
end
