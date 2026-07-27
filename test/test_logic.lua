-- logic.lua 的單元測試。刻意不用 busted 之類的框架 —— 多一個 luarocks 依賴
-- 換來的只是比較漂亮的輸出,而這裡的斷言需求就只有「相等」和「清單相等」。
package.path = "src/?.lua;" .. package.path
local logic = require("logic")

local failures, total = 0, 0

local function eq(actual, expected, label)
    total = total + 1
    if actual ~= expected then
        failures = failures + 1
        print(string.format("FAIL  %s\n      期望 %s,實際 %s",
            label, tostring(expected), tostring(actual)))
    end
end

-- 比對 {x=,y=} 座標清單,順序有意義。
local function eq_points(actual, expected, label)
    total = total + 1
    local function render(list)
        local parts = {}
        for i, p in ipairs(list) do parts[i] = string.format("(%d,%d)", p.x, p.y) end
        return "[" .. table.concat(parts, " ") .. "]"
    end
    local ok = #actual == #expected
    if ok then
        for i = 1, #expected do
            if actual[i].x ~= expected[i].x or actual[i].y ~= expected[i].y then
                ok = false
                break
            end
        end
    end
    if not ok then
        failures = failures + 1
        print(string.format("FAIL  %s\n      期望 %s,實際 %s",
            label, render(expected), render(actual)))
    end
end

-- ── 方向表 ────────────────────────────────────────────────────────────
-- Factorio 2.0 是 16 方向,north=0 順時針每 22.5 度 +1。角色行走只產生偶數值。
eq(logic.DIRECTION_VECTORS[0].x, 0, "north 的 x 分量")
eq(logic.DIRECTION_VECTORS[0].y, -1, "north 的 y 分量(Factorio 的 y 軸向下)")
eq(logic.DIRECTION_VECTORS[4].x, 1, "east 的 x 分量")
eq(logic.DIRECTION_VECTORS[4].y, 0, "east 的 y 分量")
eq(logic.DIRECTION_VECTORS[8].y, 1, "south 的 y 分量")
eq(logic.DIRECTION_VECTORS[12].x, -1, "west 的 x 分量")
eq(logic.DIRECTION_VECTORS[2].x, 1, "northeast 的 x 分量")
eq(logic.DIRECTION_VECTORS[2].y, -1, "northeast 的 y 分量")

local count = 0
for _ in pairs(logic.DIRECTION_VECTORS) do count = count + 1 end
eq(count, 8, "方向表只收 8 個行走方向,不是全部 16 個")

-- ── snap_direction ────────────────────────────────────────────────────
eq(logic.snap_direction(0), 0, "偶數方向不變")
eq(logic.snap_direction(4), 4, "east 不變")
eq(logic.snap_direction(3), 2, "奇數方向吸附到較小的偶數")
eq(logic.snap_direction(15), 14, "15 吸附到 northwest")
eq(logic.snap_direction(nil), nil, "nil 回傳 nil 而不是爆炸")
eq(logic.snap_direction("north"), nil, "非數字回傳 nil")

-- ── is_diagonal / diagonal_components ────────────────────────────────
eq(logic.is_diagonal(0), false, "north 不是對角線")
eq(logic.is_diagonal(2), true, "northeast 是對角線")
eq(logic.is_diagonal(4), false, "east 不是對角線")
eq(logic.is_diagonal(14), true, "northwest 是對角線")

local a, b = logic.diagonal_components(2)
eq(a, 0, "northeast 的第一分量是 north")
eq(b, 4, "northeast 的第二分量是 east")
local c, d = logic.diagonal_components(14)
eq(c, 12, "northwest 的第一分量是 west")
eq(d, 0, "northwest 的第二分量是 north(要繞回 0,不是 16)")

-- ── cooldown_ticks ────────────────────────────────────────────────────
-- diggy-rock 的 mining_time 是 1.5,基礎角色 mining_speed 是 0.5 -> 3 秒 = 180 tick
eq(logic.cooldown_ticks(1.5, 0.5), 180, "岩石在基礎採礦速度下是 180 tick")
eq(logic.cooldown_ticks(1.0, 0.5), 120, "碎石(mining_time 1.0)是 120 tick")
eq(logic.cooldown_ticks(1.5, 1.0), 90, "採礦速度加倍就減半")
eq(logic.cooldown_ticks(1.5, 0.7), 129, "非整除的情況無條件進位(128.57 -> 129)")
eq(logic.cooldown_ticks(1.5, 0), nil, "速度為 0 回傳 nil 而不是除以零")
eq(logic.cooldown_ticks(1.5, nil), nil, "缺速度回傳 nil")
eq(logic.cooldown_ticks(nil, 0.5), nil, "缺時間回傳 nil")

-- ── logic.lua 必須零 Factorio 依賴 ────────────────────────────────────
-- 這個檔案的存在理由就是「可以在 Factorio 外面測」。一旦有人在裡面用了 game
-- 或 storage,測試就再也跑不起來,而且會是在遊戲裡才發現。用原始碼掃描把這條
-- 規則變成會失敗的測試。
do
    local f = assert(io.open("src/logic.lua", "r"))
    local source = f:read("*a")
    f:close()
    for _, forbidden in ipairs({ "game", "storage", "settings", "defines",
                                 "prototypes", "remote", "script" }) do
        total = total + 1
        -- %f[%w] 是 Lua 的邊界比對,避免 "settings" 誤中註解裡的
        -- "mod-settings" 之類的字。
        if source:find("%f[%w]" .. forbidden .. "%f[%W]%s*[%.%[]") then
            failures = failures + 1
            print(string.format("FAIL  logic.lua 不得依賴 Factorio 全域,卻用了 %s",
                forbidden))
        end
    end
end

print(string.format("\n%d/%d 通過", total - failures, total))
os.exit(failures == 0 and 0 or 1)
