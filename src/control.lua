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
        if s.enemy_count == nil then s.enemy_count = 0 end
        if s.next_tick == nil then s.next_tick = 0 end
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
