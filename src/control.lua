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
            error(string.format(
                "hanshino-cave-autodig: defines.direction.%s 是 %s,但 logic.lua 假設是 %d",
                name, tostring(defines.direction[name]), value))
        end
    end
end
assert_direction_defines()

script.on_init(function() end)
