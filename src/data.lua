-- 兩個熱鍵。預設鍵位需要在實機確認不與 base 或伺服器上其他 8 個啟用模組衝突
-- (見 Task 9 的驗證清單)。
data:extend({
    {
        type = "custom-input",
        name = "autodig-toggle",
        key_sequence = "SHIFT + X",
        order = "a",
    },
    {
        type = "custom-input",
        name = "autodig-cycle-mode",
        key_sequence = "SHIFT + C",
        order = "b",
    },
})
