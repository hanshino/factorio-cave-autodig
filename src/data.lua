-- 只留開關這一個熱鍵。Shift+C(切換模式)在實機測試時跟伺服器上其他啟用中的
-- 模組卡到了,而模式切換本來就有 GUI 面板的下拉選單可以做同一件事,所以直接
-- 拿掉這個熱鍵,不另外挑一個新鍵位頂替 —— 面板已經是權威路徑,不需要兩條路
-- 做同一件事。Shift+X 開關本身沒有回報衝突,維持不變。
data:extend({
    {
        type = "custom-input",
        name = "autodig-toggle",
        key_sequence = "SHIFT + X",
        order = "a",
    },
})
