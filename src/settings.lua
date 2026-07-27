data:extend({
    {
        type = "string-setting",
        setting_type = "runtime-per-user",
        name = "autodig-default-mode",
        default_value = "cursor",
        allowed_values = { "forward", "cursor" },
        order = "a",
    },
    {
        type = "int-setting",
        setting_type = "runtime-per-user",
        name = "autodig-tunnel-width",
        default_value = 1,
        allowed_values = { 1, 3 },
        order = "b",
    },
    {
        type = "bool-setting",
        setting_type = "runtime-per-user",
        name = "autodig-include-rubble",
        default_value = true,
        order = "c",
    },
    {
        type = "bool-setting",
        setting_type = "runtime-per-user",
        name = "autodig-enemy-guard",
        default_value = true,
        order = "d",
    },
    -- 這個刻意是 runtime-global 而不是 per-user:它是伺服器層級的安全參數,
    -- 不該讓個別玩家自己把它調鬆。
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "autodig-stress-margin",
        default_value = 3.0,
        minimum_value = 2.0,
        maximum_value = 3.5,
        order = "e",
    },
})
