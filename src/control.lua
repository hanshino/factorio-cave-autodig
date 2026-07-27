-- Factorio 事件接線層。所有決策邏輯都在 logic.lua,這裡只負責把世界狀態摘要
-- 成純資料、呼叫 logic、再把結果變成 API 呼叫。
local logic = require("logic")

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

local MODES = { "forward", "cursor" }

local function default_mode(player)
    return settings.get_player_settings(player)["autodig-default-mode"].value
end

local function state_for(player_index)
    local players = storage.autodig.players
    local s = players[player_index]
    if not s then
        s = {
            enabled = false,
            mode = "forward",
            next_tick = 0,
            facing = nil,          -- latch 的最後有效行走方向
            last_walk_tick = nil,  -- 最後一次 walking_state.walking 為真的 tick
            enemy_count = 0,       -- 上次掃描到的附近敵人數
        }
        players[player_index] = s
    end
    return s
end

local function init_storage()
    storage.autodig = storage.autodig or {}
    storage.autodig.players = storage.autodig.players or {}
    -- 應力探針介面不見時每個 session 只警告一次,不要洗版。
    storage.autodig.probe_warned = storage.autodig.probe_warned or false
end

script.on_init(init_storage)
-- 這個 mod 目前沒有舊版可遷移,但骨架先留好:未來加欄位時,舊存檔裡的
-- entry 會缺那個欄位,state_for 只在「整個 entry 不存在」時才補預設值。
script.on_configuration_changed(function()
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
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then state_for(event.player_index).mode = default_mode(player) end
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
        s.next_tick = 0
        s.last_walk_tick = nil
        -- 開啟當下先記住現場的敵人數,否則第一次掃描會把「本來就在旁邊的怪」
        -- 誤判成新增而立刻自我關閉。
        s.enemy_count = nil
        player.print({ "autodig.enabled", mode_label(s.mode) })
    else
        player.print({ "autodig.disabled" })
    end
end)

script.on_event("autodig-cycle-mode", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local s = state_for(event.player_index)
    s.mode = (s.mode == MODES[1]) and MODES[2] or MODES[1]
    player.print({ "autodig.mode-switched", mode_label(s.mode) })
end)

local COVER = { ["diggy-rock"] = true, ["diggy-rubble"] = true }

local function stop(player, s, reason_key, ...)
    s.enabled = false
    player.print({ reason_key, ... })
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

-- 真正動手。回傳 true 表示挖成功(呼叫端據此設冷卻)。
local function try_dig(player, s, entity)
    local cooldown = cooldown_for(player, entity.name)
    if not cooldown then return false end
    -- 第二參數給 false:東西塞不下時回傳 false,而不是灑一地。
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

script.on_event(defines.events.on_tick, function()
    for player_index, s in pairs(storage.autodig.players) do
        if s.enabled then
            local player = game.get_player(player_index)
            if not player then
                s.enabled = false
            elseif logic.ready_to_dig({
                enabled = s.enabled,
                has_character = player.character ~= nil,
                tick = game.tick,
                next_tick = s.next_tick,
            }) then
                local user = settings.get_player_settings(player)
                local include_rubble = user["autodig-include-rubble"].value
                if s.mode == "cursor" then
                    local target = cursor_target(player, include_rubble)
                    if target then try_dig(player, s, target) end
                end
            elseif s.enabled and player.character == nil then
                stop(player, s, "autodig.stopped-no-character")
            end
        end
    end
end)
