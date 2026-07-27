-- 兩個熱鍵。預設鍵位(Shift+X、Shift+C)已在實機確認過,跟 base 遊戲和伺服器
-- 上其他啟用中的模組都沒有衝突。日後這台伺服器換了模組組合,加新模組前建議
-- 先用遊戲內的「控制設定」畫面確認一次這兩個按鍵沒有被別的模組佔用。
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
