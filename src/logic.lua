-- 純決策核心:完全不碰 game / storage / settings / defines / prototypes /
-- remote / script。所有輸入輸出都是普通 Lua 表。
--
-- 為什麼要這樣切:Factorio mod 沒辦法在無頭環境測玩家行為(無頭伺服器沒有角色)。
-- 把決策抽成純函式,就能用一般 Lua 直譯器在遊戲外面跑單元測試,只留下真正需要
-- 世界狀態的部分靠實機驗證。test/test_logic.lua 有一個掃原始碼的測試在強制
-- 執行這條規則。
local logic = {}

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

function logic.is_diagonal(dir)
    return dir % 4 == 2
end

-- 對角線方向拆成兩個相鄰的正交方向。northeast(2) -> north(0), east(4)。
-- northwest(14) 的第二分量要繞回 0。
function logic.diagonal_components(dir)
    return (dir - 2) % 16, (dir + 2) % 16
end

-- 挖一顆需要幾 tick。mining_time 一律從實體原型讀,不寫死,這樣 the-cave 改
-- 數值或玩家升級採礦科技都會自動跟上。
function logic.cooldown_ticks(mining_time, mining_speed)
    if not mining_time or not mining_speed or mining_speed <= 0 then return nil end
    return math.ceil(60 * mining_time / mining_speed)
end

return logic
