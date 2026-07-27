-- 自動挖掘的控制面板。所有參數直接讀寫 mod 設定,不另外存一份 ——
-- 這樣 GUI 和 Factorio 內建的設定介面永遠一致。只有 enabled 存在 storage,
-- 因為那是執行狀態不是偏好。
local logic = require("logic")

local gui = {}

local TOP_BUTTON = "autodig-open"
local PANEL = "autodig-panel"
local WIDTHS = { 1, 3 }

local function user_setting(player, name)
    return settings.get_player_settings(player)[name].value
end

local function set_user_setting(player, name, value)
    settings.get_player_settings(player)[name] = { value = value }
end

-- 在清單裡找出某個值的索引,找不到就回傳 1。dropdown 的 selected_index 是
-- 1-based,而且給錯會直接報錯,所以絕不能直接拿設定值當索引用。
local function index_of(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return 1
end

function gui.destroy(player)
    for _, parent in pairs({ player.gui.top, player.gui.screen }) do
        for _, name in pairs({ TOP_BUTTON, PANEL }) do
            local element = parent[name]
            if element then element.destroy() end
        end
    end
end

-- 只建常駐按鈕。面板要按了才開。
function gui.build(player)
    if not player.gui.top[TOP_BUTTON] then
        player.gui.top.add {
            type = "button",
            name = TOP_BUTTON,
            caption = { "autodig.gui-open" },
        }
    end
end

local function build_panel(player, state)
    local frame = player.gui.screen.add {
        type = "frame",
        name = PANEL,
        caption = { "autodig.gui-title" },
        direction = "vertical",
    }
    frame.auto_center = true

    frame.add {
        type = "checkbox",
        name = "autodig-power",
        caption = { "autodig.gui-power" },
        state = state.enabled,
    }

    local mode_items = {}
    for i, m in ipairs(logic.MODES) do mode_items[i] = { "autodig.mode-" .. m } end
    frame.add { type = "label", caption = { "autodig.gui-mode" } }
    frame.add {
        type = "drop-down",
        name = "autodig-mode",
        items = mode_items,
        selected_index = index_of(logic.MODES, state.mode),
    }

    local width_items = {}
    for i, w in ipairs(WIDTHS) do width_items[i] = { "autodig.gui-width-" .. w } end
    frame.add { type = "label", caption = { "autodig.gui-width" } }
    frame.add {
        type = "drop-down",
        name = "autodig-width",
        items = width_items,
        selected_index = index_of(WIDTHS, user_setting(player, "autodig-tunnel-width")),
    }

    frame.add {
        type = "checkbox",
        name = "autodig-rubble",
        caption = { "autodig.gui-rubble" },
        state = user_setting(player, "autodig-include-rubble"),
    }
    frame.add {
        type = "checkbox",
        name = "autodig-guard",
        caption = { "autodig.gui-guard" },
        state = user_setting(player, "autodig-enemy-guard"),
    }

    frame.add { type = "label", name = "autodig-status" }
    return frame
end

-- 把面板的顯示狀態拉回與真實狀態一致。熱鍵和 GUI 都能改開關,所以任何一邊
-- 改動之後都要呼叫這個,否則兩個介面會各說各話。面板沒開就什麼都不做。
function gui.refresh(player, state)
    local frame = player.gui.screen[PANEL]
    if not frame then return end
    frame["autodig-power"].state = state.enabled
    frame["autodig-mode"].selected_index = index_of(logic.MODES, state.mode)
    -- 只分「挖掘中」跟「已關閉」兩種,沒有「待命」——這個函式只在開關/模式/
    -- 設定變動時被呼叫,不是每 tick 都跑,所以沒有辦法即時分辨「已啟動但這一刻
    -- 前方剛好沒有目標」跟「持續在挖」。要做出準確的待命狀態需要每 tick 刷新
    -- 這個面板,對一台正式伺服器來說,為了這種裝飾性的資訊值不回那個成本。
    -- 刻意不加對應的字串,免得以後有人「順手」把它接上去。
    local key = "autodig.gui-state-off"
    if state.enabled then
        key = "autodig.gui-state-running"
    end
    frame["autodig-status"].caption = { "autodig.gui-status", { key } }
end

-- 回傳 true 表示這個點擊是我們的,呼叫端就不用再往下判斷。
function gui.on_click(player, state, element)
    if element.name ~= TOP_BUTTON then return false end
    local frame = player.gui.screen[PANEL]
    if frame then
        frame.destroy()
    else
        build_panel(player, state)
        gui.refresh(player, state)
    end
    return true
end

-- 勾選框:開關存 storage,其餘兩個直接寫回 mod 設定。
function gui.on_checkbox(player, state, element)
    if element.name == "autodig-power" then
        state.enabled = element.state
        return true, true -- 有處理、開關有變動
    elseif element.name == "autodig-rubble" then
        set_user_setting(player, "autodig-include-rubble", element.state)
        return true, false
    elseif element.name == "autodig-guard" then
        set_user_setting(player, "autodig-enemy-guard", element.state)
        return true, false
    end
    return false, false
end

function gui.on_selection(player, state, element)
    if element.name == "autodig-mode" then
        state.mode = logic.MODES[element.selected_index] or logic.MODES[1]
        return true
    elseif element.name == "autodig-width" then
        set_user_setting(player, "autodig-tunnel-width",
            WIDTHS[element.selected_index] or WIDTHS[1])
        return true
    end
    return false
end

return gui
