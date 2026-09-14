require("copilot").setup({
    -- Copilot'ın kendi hayalet yazısını kullanmıyoruz.
    -- Önerileri Blink içerisinde göstereceğiz.
    suggestion = {
        enabled = false,
    },

    panel = {
        enabled = false,
    },

    -- Markdown'da da AI tamamlama kullan.
    filetypes = {
        markdown = true,
        help = false,
    },

    -- CachyOS/Linux için native Copilot sunucusu.
    server = {
        type = "binary",
    },
})
