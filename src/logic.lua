-- 純決策核心:完全不碰 game / storage / settings / defines / prototypes /
-- remote / script。所有輸入輸出都是普通 Lua 表。
--
-- 為什麼要這樣切:Factorio mod 沒辦法在無頭環境測玩家行為(無頭伺服器沒有角色)。
-- 把決策抽成純函式,就能用一般 Lua 直譯器在遊戲外面跑單元測試,只留下真正需要
-- 世界狀態的部分靠實機驗證。test/test_logic.lua 有一個掃原始碼的測試在強制
-- 執行這條規則。
local logic = {}

-- 模式清單的唯一來源。control.lua 的熱鍵輪替和 gui.lua 的下拉選單都讀這裡 ——
-- 兩邊各自寫一份字面量的話,將來新增模式時漏改一邊會讓熱鍵和 GUI 對「現在是
-- 哪個模式」各說各話,而且不會有任何錯誤訊息。
-- 順序有意義:熱鍵是在這個清單裡循環,而 settings.lua 的 allowed_values
-- 必須與這裡一致。
logic.MODES = { "forward", "cursor", "clear" }

-- Factorio 2.0 的 defines.direction 是 16 方向,north=0,順時針每 22.5 度 +1。
-- 角色行走只會產生 8 個偶數值,所以這裡只收偶數。
-- 刻意寫成字面數字來保持這個檔案的純淨;control.lua 載入時會斷言引擎的
-- defines 與這份表一致,萬一未來引擎改了編號會立刻被抓到。
-- 注意 Factorio 的 y 軸向下,所以 north 是 y = -1。
logic.DIRECTION_VECTORS = {
    [0]  = { x =  0, y = -1 }, -- north
    [2]  = { x =  1, y = -1 }, -- northeast
    [4]  = { x =  1, y =  0 }, -- east
    [6]  = { x =  1, y =  1 }, -- southeast
    [8]  = { x =  0, y =  1 }, -- south
    [10] = { x = -1, y =  1 }, -- southwest
    [12] = { x = -1, y =  0 }, -- west
    [14] = { x = -1, y = -1 }, -- northwest
}

-- 把任意 16 方向值吸附到最接近的 8 方向值。行走理論上只給偶數,但吸附一次就
-- 不必信任這個假設。
function logic.snap_direction(dir)
    if type(dir) ~= "number" then return nil end
    return dir - (dir % 2)
end

-- 這裡加的 nil 防呆跟 snap_direction / cooldown_ticks 不是同一種保證 ——
-- 那兩個的 nil 是「不知道/沒有值」的哨兵,呼叫端看到 nil 就知道要另外處理;
-- is_diagonal(nil) 回傳 false 跟「這個方向就是正交」是同一個值,呼叫端根本
-- 分不出差異。這裡買的是別的東西:失敗的時機更早、更便宜、也更好讀。沒有
-- 這道防呆,diagonal_components(nil) 不會真的不炸,只是把炸點往後挪一行 ——
-- forward_candidates 接著會拿 nil 去查 DIRECTION_VECTORS[nil](Lua 允許,
-- 結果是 nil),再對它取 .x 才真正爆炸,錯誤訊息會是「attempt to index a nil
-- value」而不是這裡的「attempt to perform arithmetic on a nil value」——
-- 除錯時前者離真正的成因(方向是 nil)更遠。加了防呆之後,模組裡處理方向值
-- 的四個函式(snap_direction、is_diagonal、diagonal_components、
-- cooldown_ticks)在呼叫端看起來至少是統一的姿態:遇到爛輸入都直接回傳,
-- 不會半路噴一個跟輸入本身無關的 Lua 內部錯誤。
function logic.is_diagonal(dir)
    if type(dir) ~= "number" then return false end
    return dir % 4 == 2
end

-- 對角線方向拆成兩個相鄰的正交方向。northeast(2) -> north(0), east(4)。
-- northwest(14) 的第二分量要繞回 0。
function logic.diagonal_components(dir)
    if type(dir) ~= "number" then return nil, nil end
    return (dir - 2) % 16, (dir + 2) % 16
end

-- 挖一顆需要幾 tick。mining_time 一律從實體原型讀,不寫死,這樣 the-cave 改
-- 數值或玩家升級採礦科技都會自動跟上。
function logic.cooldown_ticks(mining_time, mining_speed)
    if not mining_time or not mining_speed or mining_speed <= 0 then return nil end
    return math.ceil(60 * mining_time / mining_speed)
end

-- 回傳這一輪要「依序嘗試」的候選格,呼叫端挑第一個有 cover entity 且構得到的挖。
--
-- 用「有序候選清單」而不是「輪替計數器」是刻意的:清單本身就編碼了優先序,
-- 不需要在 storage 裡存輪到第幾格的狀態,也就不會有狀態跟世界不同步的問題。
-- 左側清掉了,下一輪左側就沒有 cover,自然輪到右側。
function logic.forward_candidates(px, py, dir, width)
    dir = logic.snap_direction(dir)
    local v = dir and logic.DIRECTION_VECTORS[dir]
    if not v then return {} end

    -- 對角線拆成兩個正交分量,不挖對角格本身(見測試裡的說明)。
    -- 寬度設定在這裡刻意忽略。
    if logic.is_diagonal(dir) then
        local a, b = logic.diagonal_components(dir)
        local va, vb = logic.DIRECTION_VECTORS[a], logic.DIRECTION_VECTORS[b]
        return {
            { x = px + va.x, y = py + va.y },
            { x = px + vb.x, y = py + vb.y },
        }
    end

    local front = { x = px + v.x, y = py + v.y }
    if width ~= 3 then return { front } end

    -- 垂直於行進方向的兩側,就是方向值 ±4(90 度)。
    local left  = logic.DIRECTION_VECTORS[(dir - 4) % 16]
    local right = logic.DIRECTION_VECTORS[(dir + 4) % 16]
    return {
        { x = front.x + left.x,  y = front.y + left.y },
        { x = front.x + right.x, y = front.y + right.y },
        front,
    }
end

-- 不需要任何世界查詢的前置判斷。先過這關才值得去做 find_entities_filtered
-- 和壓力探針那些比較貴的事。
function logic.ready_to_dig(s)
    if not s.enabled then return false end
    if not s.has_character then return false end
    if s.tick < s.next_tick then return false end
    return true
end

-- walking_state.direction 只在 walking == true 時有效(官方文件明載),所以
-- 必須自己記住最後一次有效的方向。
function logic.latch_direction(prev, walking, direction)
    if walking and direction then return direction end
    return prev
end

-- 玩家現在是不是在往某個方向推。撞牆時 walking_state.walking 已經在實機
-- 驗證過仍為 true(它反映的是輸入意圖,不是實際位移),前進模式因此不能只
-- 靠 walking 本身判斷玩家是否還想繼續走。寬限期同時也是一項獨立的需求:
-- 放開方向鍵之後,自動挖掘要在半秒內停下來,不能無限期黏著最後一個方向挖。
function logic.walk_active(tick, last_walk_tick, grace)
    if not last_walk_tick then return false end
    return (tick - last_walk_tick) <= grace
end

-- 世界查詢做完之後的安全閘。回傳 nil 表示通過,否則回傳停止原因的代號。
-- 壓力先於敵人回報,因為塌陷會直接壓死玩家,敵人至少還能跑。
function logic.blocked_reason(s)
    if s.collapse_enabled and s.stress and s.stress >= s.stress_margin then
        return "stress"
    end
    if s.enemy_guard and s.prev_enemy_count and s.enemy_count > s.prev_enemy_count then
        return "enemy"
    end
    return nil
end

-- 清除模式:在一批候選點裡挑離玩家最近的一個,回傳它在清單裡的索引。
-- 用平方距離比較,省一次開根號,且不影響大小順序。points 為空回傳 nil。
--
-- 只回傳索引而不是座標本身,是因為呼叫端(control.lua)手上除了座標還有
-- 對應的 LuaEntity 物件 —— 這個函式不該知道 Factorio 實體長什麼樣子,
-- 純函式只管「哪個最近」,把索引對應回真正的實體是呼叫端的事。
function logic.nearest_point(px, py, points)
    if not points or #points == 0 then return nil end
    local best_index, best_dist
    for i, p in ipairs(points) do
        local dx, dy = p.x - px, p.y - py
        local dist = dx * dx + dy * dy
        if not best_dist or dist < best_dist then
            best_dist = dist
            best_index = i
        end
    end
    return best_index
end

return logic
