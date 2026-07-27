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

-- 邊界防呆:非數字回傳安全值,而不是讓 dir % 4 之類的算術直接炸出 error。
-- 這換來的是更早、更好讀的失敗點,不是跟 snap_direction / cooldown_ticks
-- 完全一樣的保證——理由見 logic.lua 裡這兩個函式上面的註解。
eq(logic.is_diagonal(nil), false, "is_diagonal(nil) 回傳 false 而不是爆炸")
eq(logic.is_diagonal("north"), false, "is_diagonal 對非數字回傳 false")
local e, f = logic.diagonal_components(nil)
eq(e, nil, "diagonal_components(nil) 第一分量回傳 nil")
eq(f, nil, "diagonal_components(nil) 第二分量回傳 nil")

-- ── cooldown_ticks ────────────────────────────────────────────────────
-- diggy-rock 的 mining_time 是 1.5,基礎角色 mining_speed 是 0.5 -> 3 秒 = 180 tick
eq(logic.cooldown_ticks(1.5, 0.5), 180, "岩石在基礎採礦速度下是 180 tick")
eq(logic.cooldown_ticks(1.0, 0.5), 120, "碎石(mining_time 1.0)是 120 tick")
eq(logic.cooldown_ticks(1.5, 1.0), 90, "採礦速度加倍就減半")
eq(logic.cooldown_ticks(1.5, 0.7), 129, "非整除的情況無條件進位(128.57 -> 129)")
eq(logic.cooldown_ticks(1.5, 0), nil, "速度為 0 回傳 nil 而不是除以零")
eq(logic.cooldown_ticks(1.5, nil), nil, "缺速度回傳 nil")
eq(logic.cooldown_ticks(nil, 0.5), nil, "缺時間回傳 nil")

-- ── forward_candidates ────────────────────────────────────────────────
-- 玩家在格子 (10, 10)。

-- 正交 + 寬度 1:就是正前方一格。
eq_points(logic.forward_candidates(10, 10, 0, 1), { { x = 10, y = 9 } },
    "往北寬度 1")
eq_points(logic.forward_candidates(10, 10, 4, 1), { { x = 11, y = 10 } },
    "往東寬度 1")
eq_points(logic.forward_candidates(10, 10, 8, 1), { { x = 10, y = 11 } },
    "往南寬度 1")
eq_points(logic.forward_candidates(10, 10, 12, 1), { { x = 9, y = 10 } },
    "往西寬度 1")

-- 正交 + 寬度 3:順序必須是「左、右、中」。
-- 中間那格一清掉玩家就往前走一步,先挖中間會把兩側缺口留在身後,挖出來就不是
-- 完整的 3 格走廊。中間留到最後,玩家只會在整片切面清乾淨之後才前進。
eq_points(logic.forward_candidates(10, 10, 0, 3),
    { { x = 9, y = 9 }, { x = 11, y = 9 }, { x = 10, y = 9 } },
    "往北寬度 3 的順序是左(西)、右(東)、中")
eq_points(logic.forward_candidates(10, 10, 4, 3),
    { { x = 11, y = 9 }, { x = 11, y = 11 }, { x = 11, y = 10 } },
    "往東寬度 3 的順序是左(北)、右(南)、中")
-- 南、西再補一組,確保 (dir - 4) % 16 / (dir + 4) % 16 的環繞算術兩邊都測到,
-- 不是只有 north 那組剛好用到負數取餘的分支。
eq_points(logic.forward_candidates(10, 10, 8, 3),
    { { x = 11, y = 11 }, { x = 9, y = 11 }, { x = 10, y = 11 } },
    "往南寬度 3 的順序是左(東)、右(西)、中")
eq_points(logic.forward_candidates(10, 10, 12, 3),
    { { x = 9, y = 11 }, { x = 9, y = 9 }, { x = 9, y = 10 } },
    "往西寬度 3 的順序是左(南)、右(北)、中")

-- 對角線:拆成兩個正交分量,不挖對角格本身。
-- 直接挖對角格會挖出角色走不進去的階梯 —— Factorio 的碰撞不允許穿對角縫隙,
-- 結果是一條自己進不去的隧道。
eq_points(logic.forward_candidates(10, 10, 2, 1),
    { { x = 10, y = 9 }, { x = 11, y = 10 } },
    "往東北拆成北、東兩格")
eq_points(logic.forward_candidates(10, 10, 14, 1),
    { { x = 9, y = 10 }, { x = 10, y = 9 } },
    "往西北拆成西、北兩格")
-- 東南、西南再補一組,湊齊全部四個對角方向。
eq_points(logic.forward_candidates(10, 10, 6, 1),
    { { x = 11, y = 10 }, { x = 10, y = 11 } },
    "往東南拆成東、南兩格")
eq_points(logic.forward_candidates(10, 10, 10, 1),
    { { x = 10, y = 11 }, { x = 9, y = 10 } },
    "往西南拆成南、西兩格")

-- 對角線忽略寬度設定。寬度 3 疊在階梯拆解上語意不明,而且沒有實際需求。
eq_points(logic.forward_candidates(10, 10, 2, 3),
    { { x = 10, y = 9 }, { x = 11, y = 10 } },
    "對角線忽略寬度 3")

-- 壞輸入回傳空清單,呼叫端自然什麼都不做。
eq_points(logic.forward_candidates(10, 10, nil, 1), {}, "方向為 nil 回傳空清單")
eq(#logic.forward_candidates(10, 10, 99, 1), 0, "無效方向值回傳空清單")

-- 奇數方向先吸附再算。
eq_points(logic.forward_candidates(10, 10, 1, 1), { { x = 10, y = 9 } },
    "方向 1 吸附成 north")

-- ── ready_to_dig ──────────────────────────────────────────────────────
local function ready(over)
    local s = { enabled = true, has_character = true, tick = 100, next_tick = 100 }
    for k, v in pairs(over or {}) do s[k] = v end
    return logic.ready_to_dig(s)
end
eq(ready(), true, "全部就緒時可以挖")
eq(ready{ enabled = false }, false, "沒開啟就不挖")
eq(ready{ has_character = false }, false, "沒有角色就不挖(遠端視角、觀察者、死亡)")
eq(ready{ tick = 99 }, false, "冷卻還沒到不挖")
eq(ready{ tick = 101 }, true, "冷卻過了可以挖")

-- ── latch_direction ───────────────────────────────────────────────────
-- walking_state.direction 只在 walking == true 時有效(官方文件明載),
-- 站著不動時那個值不可信,所以必須自己記住最後一次有效的方向。
eq(logic.latch_direction(0, true, 4), 4, "行走中就更新成當前方向")
eq(logic.latch_direction(0, false, 8), 0, "沒在走時保留舊值,不信任當前方向")
eq(logic.latch_direction(nil, true, 4), 4, "第一次有方向就記住")
eq(logic.latch_direction(4, false, nil), 4, "沒在走且方向為 nil 時保留舊值")
eq(logic.latch_direction(4, true, nil), 4, "行走中但方向為 nil 也保留舊值")

-- north = 0 是個看起來像「假值」的合法方向。實作用的是
-- `if walking and direction then`,Lua 裡 0 是真值,所以這裡本該正確,
-- 但如果哪天有人把它改成別的語言常見的「0 是假」寫法,這兩條會先炸。
eq(logic.latch_direction(4, true, 0), 0, "方向為 0(north)時要真的採信,不能被當成沒方向")
eq(logic.latch_direction(0, false, 4), 0, "上次 latch 住的方向是 0 時,沒在走要能正確保留這個 0")

-- ── walk_active ───────────────────────────────────────────────────────
-- 前進模式需要知道「玩家現在是不是在往某個方向推」。撞牆時
-- walking_state.walking 已經實機驗證過仍為 true(它反映輸入意圖不是實際
-- 位移)。寬限期不是那次驗證的保險,而是一項獨立需求:放開方向鍵之後,
-- 自動挖掘要在半秒內停下來,不能無限期黏著最後一個方向繼續挖。
eq(logic.walk_active(100, 100, 30), true, "這一 tick 正在走")
eq(logic.walk_active(130, 100, 30), true, "寬限期邊界內仍算在走")
eq(logic.walk_active(131, 100, 30), false, "超過寬限期就不算")
eq(logic.walk_active(100, nil, 30), false, "從來沒走過就不算")

-- tick 0 跟 last_walk_tick 0 都是合法值(遊戲剛開始的第一個 tick),不是
-- 「還沒發生」的意思 —— 只有 nil 才是。實作用 `if not last_walk_tick then`,
-- Lua 的 0 是真值所以本該正確,這裡直接釘住避免以後被改壞。
eq(logic.walk_active(0, 0, 30), true, "tick 0 且 last_walk_tick 0 時仍算在走,0 不是 nil")
eq(logic.walk_active(30, 0, 30), true, "從 tick 0 開始算,寬限期邊界內仍算在走")
eq(logic.walk_active(31, 0, 30), false, "從 tick 0 開始算,超過寬限期就不算")

-- ── blocked_reason ────────────────────────────────────────────────────
local function blocked(over)
    local s = {
        collapse_enabled = true, stress = 1.0, stress_margin = 3.0,
        enemy_guard = true, enemy_count = 0, prev_enemy_count = 0,
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return logic.blocked_reason(s)
end
eq(blocked(), nil, "一切正常時不擋")
eq(blocked{ stress = 3.0 }, "stress", "壓力達到邊界就擋(邊界是含的)")
eq(blocked{ stress = 3.5 }, "stress", "壓力超過邊界就擋")
eq(blocked{ stress = 2.99 }, nil, "壓力略低於邊界不擋")
eq(blocked{ stress = 3.5, collapse_enabled = false }, nil,
    "the-cave 關掉塌陷時整道閘跳過")
eq(blocked{ stress = nil }, nil, "探針拿不到值時不擋(介面壞掉已另外警告過)")
eq(blocked{ enemy_count = 1 }, "enemy", "敵人變多就擋")
eq(blocked{ enemy_count = 1, enemy_guard = false }, nil, "關掉警戒就不擋")
eq(blocked{ enemy_count = 0, prev_enemy_count = 5 }, nil, "敵人變少不擋")
eq(blocked{ stress = 3.5, enemy_count = 1 }, "stress", "壓力優先於敵人回報")

-- ── MODES ─────────────────────────────────────────────────────────────
-- 這份清單是 control.lua 與 gui.lua 的共同來源,也必須與 settings.lua 的
-- allowed_values 一致。把它釘住,免得有人改了其中一邊。
eq(#logic.MODES, 2, "目前只有兩種模式")
eq(logic.MODES[1], "forward", "第一個模式是 forward(settings.lua 的預設值仍是 cursor,較容易上手,與是否已實作無關)")
eq(logic.MODES[2], "cursor", "第二個模式是 cursor")

-- ── logic.lua 必須零 Factorio 依賴 ────────────────────────────────────
-- 這個檔案的存在理由就是「可以在 Factorio 外面測」。一旦有人在裡面用了 game
-- 或 storage,測試就再也跑不起來,而且會是在遊戲裡才發現。用原始碼掃描把這條
-- 規則變成會失敗的測試。
--
-- 掃描前先剝掉註解:散文裡提到 defines.direction 是正常的,不該被當成依賴。
-- 字串字面量刻意「不」剝掉 —— _G["game"] 必須抓得到,而純邏輯模組裡出現這些
-- 字的字串本來就值得看一眼。
local FORBIDDEN_GLOBALS = { "game", "storage", "settings", "defines",
                            "prototypes", "remote", "script" }

local function strip_lua_comments(source)
    -- 區塊註解要先剝,否則裡面的 -- 會讓行註解規則咬到 ]] 之前就停。
    -- %1 反向參照讓 --[==[ ... ]==] 這種長括號也能正確配對。
    source = source:gsub("%-%-%[(=*)%[.-%]%1%]", " ")
    return (source:gsub("%-%-[^\n]*", " "))
end

-- 回傳這段原始碼裡出現的禁用全域名稱清單(依 FORBIDDEN_GLOBALS 的順序)。
local function find_factorio_globals(source)
    local code = strip_lua_comments(source)
    local hits = {}
    for _, word in ipairs(FORBIDDEN_GLOBALS) do
        -- %f[%w_] / %f[^%w_] 是識別字邊界,所以 gamer 和 mystorage 不會誤中。
        if code:find("%f[%w_]" .. word .. "%f[^%w_]") then
            hits[#hits + 1] = word
        end
    end
    return hits
end

-- 掃描器自己也要有測試。只拿它掃一個「本來就乾淨」的檔案,證明不了它抓得到
-- 任何東西 —— 一個永遠回傳空清單的函式也會通過那種檢查。
local function eq_hits(source, expected, label)
    eq(table.concat(find_factorio_globals(source), ","), expected, label)
end

eq_hits("local t = game.tick", "game", "抓得到直接的點存取")
eq_hits("local x = storage[key]", "storage", "抓得到中括號存取")
eq_hits("local g = game", "game", "抓得到別名(舊 pattern 漏掉的)")
eq_hits("game:foo()", "game", "抓得到冒號呼叫(舊 pattern 漏掉的)")
eq_hits('local f = _G["game"]', "game", "抓得到 _G 字串索引(舊 pattern 漏掉的)")
eq_hits("-- Factorio 2.0 的 defines.direction 是 16 方向", "",
    "行註解裡提到 defines.direction 不算依賴(舊 pattern 誤抓的)")
eq_hits("--[[ storage.foo ]] local x = 1", "",
    "區塊註解裡的 storage 不算依賴")
eq_hits("--[==[ remote.call ]==] local x = 1", "",
    "長括號區塊註解也要剝掉")
eq_hits("local gamer = 1", "", "gamer 不是 game")
eq_hits("local x = mystorage.y", "", "mystorage 不是 storage")
eq_hits("local a = settings and defines", "settings,defines",
    "同一行多個依賴都要抓到,依 FORBIDDEN_GLOBALS 順序")

do
    local f = assert(io.open("src/logic.lua", "r"))
    local source = f:read("*a")
    f:close()
    eq(table.concat(find_factorio_globals(source), ","), "",
        "src/logic.lua 不得依賴任何 Factorio 全域")
end

print(string.format("\n%d/%d 通過", total - failures, total))
os.exit(failures == 0 and 0 or 1)
