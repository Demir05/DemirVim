local Snacks = require("snacks")

Snacks.setup({
    explorer = {
        enabled = true,
    },

    picker = {
        enabled = true,
    },

    input = {
        enabled = true,
    },

    notifier = {
        enabled = true,
    },

    terminal = {
        enabled = true,

        win = {
            position = "bottom",
            height = 0.30,
        },
    },
})

local map = vim.keymap.set

-- Dosya gezgini.
map("n", "<leader>e", function()
    Snacks.explorer()
end, {
    desc = "Dosya gezgini",
})

-- Mevcut proje veya dizinde dosya bul.
map("n", "<leader>f", function()
    Snacks.picker.files()
end, {
    desc = "Dosya bul",
})

-- Kişisel dizinde dosya bul.
map("n", "<leader>ff", function()
    Snacks.picker.files({
        cwd = vim.env.HOME,
        hidden = true,
    })
end, {
    desc = "Kişisel dosyalarda ara",
})

-- Mevcut proje veya dizindeki dosya içeriklerinde ara.
map("n", "<leader>F", function()
    Snacks.picker.grep()
end, {
    desc = "Dosya içeriklerinde ara",
})

-- Terminali aç / kapat.
map({ "n", "t" }, "<leader>t", function()
    Snacks.terminal.toggle()
end, {
    desc = "Terminal",
})
