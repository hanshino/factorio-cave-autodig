-- Factorio 事件接線層。所有決策邏輯都在 logic.lua,這裡只負責把世界狀態摘要
-- 成純資料、呼叫 logic、再把結果變成 API 呼叫。
local logic = require("logic")
local autodig_gui = require("gui")

-- logic.lua 為了保持可測而把方向值寫成字面數字。這裡驗證引擎的 defines 真的
-- 是那些值 —— 萬一未來 Factorio 改了編號,這個錯誤會在載入時就炸出來,而不是
-- 變成「自動挖掘往錯的方向挖」這種要玩很久才發現的怪 bug。
local function assert_direction_defines()
    local expected = {
        north = 0, northeast = 2, east = 4, southeast = 6,
        south = 8, southwest = 10, west = 12, northwest = 14,
    }
    for name, value in pairs(expected) do
        if defines.direction[name] ~= value then
            -- 這則訊息刻意不走 locale:error() 收不了 LocalisedString,而且它在
            -- 載入階段就中止 mod,玩家永遠看不到。用英文是因為這個 mod 會發布到
            -- mod portal,讀到這段崩潰訊息的人不一定看得懂中文。
            error(string.format(
                "hanshino-cave-autodig: defines.direction.%s is %s but logic.lua assumes %d",
                name, tostring(defines.direction[name]), value))
        end
    end
end
assert_direction_defines()

local function default_mode(player)
    return settings.get_player_settings(player)["autodig-default-mode"].value
end

local function state_for(player_index)
    local players = storage.autodig.players
    local s = players[player_index]
    if not s then
        -- 呼叫端在事件開頭都已經確認過 game.get_player(player_index) 不是 nil,
        -- 這裡重新拿一次是同一個物件。新 entry 套用玩家的預設模式設定,讓
        -- mod 安裝前就存在的玩家跟全新玩家拿到一樣的預設值 —— 不能寫死字面量,
        -- 那樣 settings.lua 的 default_value 跟這裡就是兩個要保持同步的地方。
        local player = game.get_player(player_index)
        s = {
            enabled = false,
            mode = default_mode(player),
            next_tick = 0,
            facing = nil,          -- latch 的最後有效行走方向
            last_walk_tick = nil,  -- 最後一次 walking_state.walking 為真的 tick
            -- nil 是有意義的哨兵,代表「還沒有基準」,不是省略初始值。
            -- 見 blocked_reason 和 try_dig 裡對這個欄位的說明。
            enemy_count = nil,
        }
        players[player_index] = s
    end
    return s
end

local function init_storage()
    storage.autodig = storage.autodig or {}
    storage.autodig.players = storage.autodig.players or {}
    -- 這兩個警告旗標都存在 storage 裡,跟著存檔走 —— 是「每個存檔只警告一次」,
    -- 不是「每個 session」:重新連上同一個存檔不會讓警告再跳出來。應力探針
    -- (diggy-v1.debug_max_stress 這個 remote 介面)和塌陷開關設定
    -- (the-cave-collapse-mode 這個 startup setting)是兩個獨立的失敗模式,
    -- 各自一個旗標,見 warn_probe_once / warn_collapse_setting_missing_once。
    storage.autodig.probe_warned = storage.autodig.probe_warned or false
    storage.autodig.collapse_setting_warned = storage.autodig.collapse_setting_warned or false
end

script.on_init(init_storage)
-- 這個 mod 目前沒有舊版可遷移,但骨架先留好:未來加欄位時,舊存檔裡的
-- entry 會缺那個欄位,state_for 只在「整個 entry 不存在」時才補預設值。
script.on_configuration_changed(function(event)
    init_storage()
    for _, s in pairs(storage.autodig.players) do
        -- next_tick 一定要有值:ready_to_dig 拿它跟 game.tick 做 < 比較,nil 會直接報錯。
        if s.next_tick == nil then s.next_tick = 0 end
        -- enemy_count 刻意「不」補值。nil 在這裡是有意義的哨兵,代表「還沒抓到基準,
        -- 第一次挖不要比較」,而 Lua 分不出「欄位不存在」和「欄位存在但是 nil」——
        -- 補成 0 會把哨兵變成「基準是 0 隻敵人」,於是玩家旁邊本來就有怪的時候,
        -- 下一次挖掘會誤判成敵人增加而自我關閉。舊存檔缺這個欄位時讀到 nil,
        -- 那正好就是安全的預設值。
    end

    -- 只有這個 mod 自己的版本變了,才重新解除兩個警告旗標 —— 別的 mod 更新
    -- 觸發的 configuration_changed 不該讓警告重新武裝,那樣玩家會在什麼都
    -- 沒修好的情況下又看到一次同一則警告。版本真的變了,代表這個 mod 有機會
    -- 已經更新過偵測邏輯,或 The Cave 已經修好了介面,讓警告能再有一次機會
    -- 派上用場,而不是永遠卡死在第一次警告,即使問題後來解決了也不會再提醒。
    local own_changes = event.mod_changes and event.mod_changes["hanshino-cave-autodig"]
    if own_changes and own_changes.old_version ~= own_changes.new_version then
        storage.autodig.probe_warned = false
        storage.autodig.collapse_setting_warned = false
    end

    -- mod 更新後舊的 GUI 元素可能結構不同,直接砍掉重建最省事。
    for _, player in pairs(game.players) do
        autodig_gui.destroy(player)
        autodig_gui.build(player)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        -- state_for 現在會自己在建立新 entry 時讀取玩家的預設模式設定,
        -- 這裡不用再重複賦值一次。
        state_for(event.player_index)
        autodig_gui.build(player)
    end
end)

script.on_event(defines.events.on_player_removed, function(event)
    storage.autodig.players[event.player_index] = nil
end)

local function mode_label(mode)
    return { "autodig.mode-" .. mode }
end

script.on_event("autodig-toggle", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local s = state_for(event.player_index)
    s.enabled = not s.enabled
    if s.enabled then
        -- next_tick 刻意不歸零。歸零等於允許連按兩次熱鍵就把冷卻繞過去,
        -- 立刻再挖一次 —— 這是對「等同手挖速度」這個核心約束的直接違反。
        -- 停用期間保留的 next_tick 本來就正確地跨過關閉/開啟這個循環。
        s.last_walk_tick = nil
        -- 開啟當下先記住現場的敵人數,否則第一次掃描會把「本來就在旁邊的怪」
        -- 誤判成新增而立刻自我關閉。
        s.enemy_count = nil
        player.print({ "autodig.enabled", mode_label(s.mode) })
    else
        player.print({ "autodig.disabled" })
    end
    autodig_gui.refresh(player, s)
end)

-- 原本這裡還有一個 autodig-cycle-mode 熱鍵(Shift+C),實機測試時跟伺服器上
-- 其他啟用中的模組卡到了。切換模式本來就有 GUI 面板的下拉選單能做同一件事,
-- 所以直接拿掉這個熱鍵,不另外挑一個新鍵位頂替 —— 面板是權威路徑,不需要
-- 兩條路做同一件事。對應的 data.lua custom-input 定義也已移除。

local COVER = { ["diggy-rock"] = true, ["diggy-rubble"] = true }

-- 放開方向鍵之後還能挖多久。撞牆時 walking_state.walking 已經在實機驗證過
-- 仍為 true(它反映的是輸入意圖,不是實際位移),前進模式因此不能只靠
-- walking 本身判斷玩家是否還想繼續走。寬限期同時也是一項獨立的需求:
-- 放開方向鍵之後,自動挖掘要在半秒內停下來,不能無限期黏著最後一個方向挖。
local WALK_GRACE_TICKS = 30

local ENEMY_SCAN_RADIUS = 15
-- 壓力探針的取樣半框。max_in_area 內部以 step 2 掃 cell,所以 ±4 是 5x5 = 25
-- 個 cell。以每 3 秒一次的挖掘節奏計成本可忽略;真的量到偏重就縮成 ±2。
local STRESS_PROBE_HALF = 4

-- 每個 stop 路徑都經過這裡,所以面板刷新放在這裡一次做完,而不是要求每個
-- 呼叫端自己記得呼叫 —— 現在有四個呼叫點,漏掉一次就會讓面板顯示「挖掘中」
-- 但其實已經停了。
local function stop(player, s, reason_key, ...)
    s.enabled = false
    player.print({ reason_key, ... })
    autodig_gui.refresh(player, s)
end

-- 角色的有效採礦速度。基礎值來自角色原型(原版是 0.5),再加上角色本身和
-- 勢力的採礦速度加成 —— 科技升級因此會自動反映在自動挖掘的速度上。
local function mining_speed_for(player)
    local character = player.character
    if not character then return nil end
    local base = character.prototype.mining_speed
    if not base or base <= 0 then return nil end
    -- 兩個加成是「相乘」不是相加。官方 API 文件對 manual_mining_speed_modifier 的
    -- 說法是「actual mining speed will be multiplied by 1 + modifier」,wiki 的手挖
    -- 公式也是 (1 + 勢力加成) * (1 + 角色加成) * 角色採礦速度 / 挖掘時間。
    -- 寫成 (1 + a + b) 只有在其中一個為 0 時才剛好正確 —— 兩個都非零時會低估
    -- 有效速度,也就是挖得比手挖慢;反過來的情境同樣會讓「等同手挖」這個前提失效。
    return base * (1 + player.character_mining_speed_modifier)
                * (1 + player.force.manual_mining_speed_modifier)
end

-- mining_time 一律從實體原型讀,不寫死。diggy-rock 是 1.5、diggy-rubble 是 1.0,
-- 但 the-cave 隨時可能改,而且這樣碎石和岩石的不同耗時自動就對了。
local function cooldown_for(player, entity_name)
    local proto = prototypes.entity[entity_name]
    local props = proto and proto.mineable_properties
    if not props or not props.minable then return nil end
    return logic.cooldown_ticks(props.mining_time, mining_speed_for(player))
end

-- the-cave 的塌陷系統是不是開著。跨 mod 讀 startup setting 是合法的。
--
-- 回傳第二個值代表「這個設定本身在 settings.startup 裡完全找不到」——這跟
-- 「找到了,但值不是 enabled」是兩種完全不同的情況:後者是使用者/伺服器
-- 自己選擇關掉,正常且該保持沉默;前者代表 the-cave-collapse-mode 這個名稱
-- 本身消失了(The Cave 改了設定名稱),整道塌陷閘會不聲不響地失效,表現起來
-- 跟「使用者自己關掉」一模一樣 —— 但沒有人真的做了這個選擇。呼叫端要分得出
-- 這兩種情況,才能只在後者警告。
local function collapse_enabled()
    local setting = settings.startup["the-cave-collapse-mode"]
    if setting == nil then return false, "missing" end
    return setting.value == "enabled"
end

-- 向 the-cave 問這一帶目前的最大岩層應力。
--
-- 這個 remote 函式在上游被註解成「Headless test hooks (used by the maintainer's
-- automated benchmarks)」,也就是說它不是穩定的公開 API,隨時可能改名或消失。
-- 所以:先檢查介面在不在,再 pcall 包住呼叫,壞掉時只關閉這道閘並警告一次,
-- 絕不讓整個 mod 崩掉。
local function stress_at(surface, x, y)
    if not remote.interfaces["diggy-v1"]
        or not remote.interfaces["diggy-v1"]["debug_max_stress"] then
        return nil, "missing"
    end
    local h = STRESS_PROBE_HALF
    local ok, value = pcall(remote.call, "diggy-v1", "debug_max_stress",
        surface.index, x - h, y - h, x + h, y + h)
    if not ok or type(value) ~= "number" then return nil, "error" end
    return value
end

local function enemy_count_near(surface, position)
    return surface.count_entities_filtered({
        position = position,
        radius = ENEMY_SCAN_RADIUS,
        type = { "unit", "unit-spawner", "turret" },
        force = "enemy",
    })
end

-- 應力探針壞掉時每個存檔只警告一次,不要洗版。這是伺服器層級的狀況
-- (The Cave 的介面本身壞了,不是某個玩家個人的問題),所以用 game.print
-- 讓每個在線玩家都看到,而不是只有剛好觸發這次挖掘的那一個人。
local function warn_probe_once()
    if storage.autodig.probe_warned then return end
    storage.autodig.probe_warned = true
    game.print({ "autodig.probe-unavailable" })
end

-- the-cave-collapse-mode 這個 startup setting 本身找不到時,每個存檔只警告
-- 一次 —— 跟應力探針是兩個獨立的失敗模式,理由同上,各自一個旗標分開計。
local function warn_collapse_setting_missing_once()
    if storage.autodig.collapse_setting_warned then return end
    storage.autodig.collapse_setting_warned = true
    game.print({ "autodig.collapse-setting-missing" })
end

-- 真正動手,成功時會在函式內自己設定冷卻(不是靠呼叫端)。回傳 true 表示挖成功。
local function try_dig(player, s, entity)
    local cooldown = cooldown_for(player, entity.name)
    if not cooldown then return false end

    local position = entity.position
    local x, y = math.floor(position.x), math.floor(position.y)
    local user = settings.get_player_settings(player)

    -- player.surface 在 Space Age 的遠端視角(remote view)下是攝影機所在的
    -- 星球,不是角色的 —— 但下面用到 player.surface 的兩個查詢,對象(entity /
    -- position)本來就是靠同一個 player.surface 找到的,彼此一致,不會查錯
    -- 星球。真正擋住遠端視角亂挖的是呼叫端(cursor_target / forward_target)
    -- 裡對 can_reach_entity 的檢查,那是相對角色量測的,詳見 forward_target
    -- 裡的完整說明。
    local gate_collapse, collapse_problem = collapse_enabled()
    if collapse_problem then
        warn_collapse_setting_missing_once()
    end
    local stress, probe_problem
    if gate_collapse then
        stress, probe_problem = stress_at(player.surface, x, y)
        if probe_problem then
            warn_probe_once()
            -- 探針壞掉就降級成沒有這道閘,而不是停止挖掘。
            gate_collapse = false
        end
    end

    local margin = settings.global["autodig-stress-margin"].value
    local enemy_guard = user["autodig-enemy-guard"].value
    local enemies = enemy_guard and enemy_count_near(player.surface, position) or 0

    local reason = logic.blocked_reason({
        collapse_enabled = gate_collapse,
        stress = stress,
        stress_margin = margin,
        enemy_guard = enemy_guard,
        enemy_count = enemies,
        -- 剛開啟時 enemy_count 是 nil,代表「還沒有基準」,這一輪不比較,
        -- 只把現場的敵人數記下來當基準。否則一開啟就會被本來就在旁邊的怪
        -- 誤判成新增而立刻自我關閉。
        prev_enemy_count = s.enemy_count,
    })
    -- 警戒關閉時不要覆寫基準。寫 0 進去等於宣稱「附近沒有敵人」,於是重新開啟
    -- 警戒後的第一次挖掘會把本來就在旁邊的怪判成新增而自我關閉。nil 表示
    -- 「沒有基準」,blocked_reason 會跳過比較,下一次挖掘再重新抓基準。
    s.enemy_count = enemy_guard and enemies or nil

    if reason == "stress" then
        stop(player, s, "autodig.stopped-stress",
            string.format("%.2f", stress), string.format("%.2f", margin))
        return false
    elseif reason == "enemy" then
        stop(player, s, "autodig.stopped-enemy")
        return false
    end

    if not player.mine_entity(entity, false) then
        stop(player, s, "autodig.stopped-inventory")
        return false
    end
    s.next_tick = game.tick + cooldown
    return true
end

-- 游標模式:滑鼠指著的就是目標。player.selected 是同步的複製狀態
-- (選取變更是會廣播的 input action,而且有 on_selected_entity_changed 事件),
-- 所以拿它做決策不會破壞多人的 determinism。
local function cursor_target(player, include_rubble)
    local entity = player.selected
    if not entity or not entity.valid then return nil end
    if not COVER[entity.name] then return nil end
    if entity.name == "diggy-rubble" and not include_rubble then return nil end
    if not player.can_reach_entity(entity) then return nil end
    return entity
end

-- the-cave 把 cover 實體放在格子中心 (x + 0.5, y + 0.5),所以用半徑 0.4 的
-- 點查詢剛好只會命中那一格的那一顆。
local function cover_at(surface, x, y, include_rubble)
    local names = include_rubble and { "diggy-rock", "diggy-rubble" } or { "diggy-rock" }
    local found = surface.find_entities_filtered({
        position = { x + 0.5, y + 0.5 },
        radius = 0.4,
        name = names,
        limit = 1,
    })
    return found[1]
end

-- 前進模式:依 logic 給的優先序,挑第一個「有 cover 且構得到」的候選格。
-- 候選格全是空地時回傳 nil —— 呼叫端什麼都不做。絕不因為正前方是空地就
-- 轉去挖旁邊的牆:那會把隧道兩側掏空,既失去方向控制又推高塌陷壓力。
local function forward_target(player, s, width, include_rubble)
    if not logic.walk_active(game.tick, s.last_walk_tick, WALK_GRACE_TICKS) then
        return nil
    end
    -- player.position 在 Space Age 的遠端視角(remote view)下是攝影機的位置,
    -- 不是角色的 —— 遠端視角時 player.character 依然非 nil,所以 on_tick 裡
    -- 「沒有角色」的判斷擋不住這個情況,底下算出來的候選格會圍著攝影機而不是
    -- 角色。真正兜住這件事的是下面迴圈裡的 player.can_reach_entity:它是相對
    -- 角色量測的,遠端視角時角色通常構不到候選格,檢查自然會失敗。這一行不能
    -- 被當成「反正下面會擋掉,這裡多餘」而移除或弱化 can_reach_entity 的呼叫。
    local position = player.position
    local px, py = math.floor(position.x), math.floor(position.y)
    local candidates = logic.forward_candidates(px, py, s.facing, width)
    for _, c in ipairs(candidates) do
        local entity = cover_at(player.surface, c.x, c.y, include_rubble)
        if entity and player.can_reach_entity(entity) then
            return entity
        end
    end
    return nil
end

-- 清除模式:在玩家 resource_reach_distance 範圍內找所有 cover 實體,挑距離
-- 最近、且通過 can_reach_entity 的那一顆——不需要滑鼠指、也不需要對著牆走,
-- 只要範圍內有構得到的石頭或碎石就自動清掉。
--
-- find_entities_filtered 的圓形範圍量的是「實體中心到查詢點」,can_reach_entity
-- 量的是「碰撞箱最近的一點到角色」——README 記載的實機驗證顯示兩者在邊界附近
-- 會差到 0.5~0.7 格(剛好是 diggy-rock 的碰撞箱半徑)。所以範圍查詢只用來
-- 縮小候選集,真正「構不構得到」一律交給 can_reach_entity 判定,這樣清除模式
-- 跟 cursor_target / forward_target 兩個模式共用同一條距離防線,不會自己另外
-- 認定一個更寬鬆或更嚴格的範圍。
-- resource_reach_distance 隨 the-cave 的採礦距離科技成長(開局約 3.2 格,滿級
-- 約 23 格),完全比照玩家手動點擊的判定,不是這個模式自己另外設定的參數。
-- player.position 在遠端視角下是攝影機位置,同 forward_target 的說明——
-- can_reach_entity 一樣是相對角色量測,遠端視角時自然會把範圍內的東西都
-- 判定為構不到,不需要額外處理。
local function clear_target(player, include_rubble)
    local reach = player.resource_reach_distance
    if not reach or reach <= 0 then return nil end
    local names = include_rubble and { "diggy-rock", "diggy-rubble" } or { "diggy-rock" }
    local found = player.surface.find_entities_filtered({
        position = player.position,
        radius = reach,
        name = names,
    })
    if #found == 0 then return nil end

    local reachable, points = {}, {}
    for _, entity in ipairs(found) do
        if player.can_reach_entity(entity) then
            reachable[#reachable + 1] = entity
            points[#points + 1] = entity.position
        end
    end
    local index = logic.nearest_point(player.position.x, player.position.y, points)
    return index and reachable[index]
end

script.on_event(defines.events.on_tick, function()
    for player_index, s in pairs(storage.autodig.players) do
        if s.enabled then
            local player = game.get_player(player_index)
            if not player then
                -- stop() 需要一個活著的 player 物件才能 print 訊息和刷新面板,
                -- 玩家已經斷線拿不到 player,所以這裡只能直接關旗標,不能走 stop()。
                s.enabled = false
            elseif not player.character then
                stop(player, s, "autodig.stopped-no-character")
            else
                -- 每 tick 更新,與冷卻無關:玩家轉向後不該等到下次冷卻才生效。
                -- walking_state.direction 只在 walking 為 true 時有效,所以交給
                -- logic.latch_direction 處理「該不該採信這次讀到的方向」。
                local walking_state = player.walking_state
                s.facing = logic.latch_direction(s.facing,
                    walking_state.walking, walking_state.direction)
                if walking_state.walking then s.last_walk_tick = game.tick end

                if logic.ready_to_dig({
                    enabled = s.enabled,
                    has_character = true,
                    tick = game.tick,
                    next_tick = s.next_tick,
                }) then
                    local user = settings.get_player_settings(player)
                    local include_rubble = user["autodig-include-rubble"].value
                    local target
                    if s.mode == "cursor" then
                        target = cursor_target(player, include_rubble)
                    elseif s.mode == "clear" then
                        target = clear_target(player, include_rubble)
                    else
                        target = forward_target(player, s,
                            user["autodig-tunnel-width"].value, include_rubble)
                    end
                    if target then try_dig(player, s, target) end
                end
            end
        end
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    -- 別的 mod 可能在同一個事件派送裡把這個元素毀掉,而我們拿到的還是同一個
    -- event.element。讀一個 invalid LuaGuiElement 的任何屬性都會 raise,而
    -- event handler 裡的未處理錯誤會直接把整台伺服器帶走。
    -- 這不是理論風險:the-cave 是硬依賴所以先派送,它的 welcome_gui 在玩家點
    -- 確認鈕時會 destroy 那顆按鈕所在的整個 frame(scripts/welcome_gui.lua)。
    -- the-cave 自己每個 handler 開頭都檢查 element.valid,我們也必須檢查。
    if not (event.element and event.element.valid) then return end
    -- 只有前綴確認是我們自己的元素才值得建立 per-player state ——
    -- 否則任何 mod 的任何 GUI 互動都會在 storage.autodig.players 建一個
    -- entry,讓 on_tick 迴圈平白多跑一個從沒真的用過自動挖掘的玩家。
    -- gui.lua 裡各自的名稱判斷仍然是權威判斷,這裡只是提早退出。
    if event.element.name:sub(1, 8) ~= "autodig-" then return end
    autodig_gui.on_click(player, state_for(event.player_index), event.element)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    -- 同 on_gui_click:忽略已經 invalid 或不是本 mod 的元素,見上方註解。
    if not (event.element and event.element.valid) then return end
    if event.element.name:sub(1, 8) ~= "autodig-" then return end
    local s = state_for(event.player_index)
    local was_enabled = s.enabled
    local handled, power_changed = autodig_gui.on_checkbox(player, s, event.element)
    if power_changed then
        if s.enabled and not was_enabled then
            -- 與熱鍵開啟時完全相同的重置(next_tick 刻意不歸零,理由同熱鍵)。
            s.last_walk_tick = nil
            s.enemy_count = nil
            player.print({ "autodig.enabled", mode_label(s.mode) })
        elseif was_enabled and not s.enabled then
            player.print({ "autodig.disabled" })
        end
    end
    if handled then autodig_gui.refresh(player, s) end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    -- 同 on_gui_click:忽略已經 invalid 或不是本 mod 的元素,見上方註解。
    if not (event.element and event.element.valid) then return end
    if event.element.name:sub(1, 8) ~= "autodig-" then return end
    local s = state_for(event.player_index)
    if autodig_gui.on_selection(player, s, event.element) then
        autodig_gui.refresh(player, s)
    end
end)
