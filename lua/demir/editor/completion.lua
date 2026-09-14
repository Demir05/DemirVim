local cmp = require("blink.cmp")

cmp.setup({
    -- ─────────────────────────────────────────────────────────
    -- Tuşlar
    -- ─────────────────────────────────────────────────────────
    --
    -- Enter       Seçili öneriyi kabul et
    -- Tab         Snippet içindeki sonraki alana git
    -- Shift+Tab   Önceki alana git
    -- Ctrl+Space  Öneri menüsünü elle aç
    -- Up / Down   Öneriler arasında gezin
    -- ─────────────────────────────────────────────────────────

    keymap = {
        preset = "enter",
    },

    -- ─────────────────────────────────────────────────────────
    -- Görünüm
    -- ─────────────────────────────────────────────────────────

    appearance = {
        nerd_font_variant = "mono",
    },

    -- ─────────────────────────────────────────────────────────
    -- Completion
    -- ─────────────────────────────────────────────────────────

    completion = {
        list = {
            selection = {
                -- İlk öneriyi otomatik seçme.
                -- Enter'a yanlışlıkla basıldığında istemsiz
                -- completion yapılmasını engeller.
                preselect = false,
                auto_insert = false,
            },
        },

        documentation = {
            auto_show = true,
            auto_show_delay_ms = 300,
        },

        ghost_text = {
            enabled = true,
        },
    },

    -- ─────────────────────────────────────────────────────────
    -- Kaynaklar
    -- ─────────────────────────────────────────────────────────

    sources = {
        default = {
            "lsp",
            "copilot",
            "path",
            "snippets",
            "buffer",
        },

        providers = {
            copilot = {
                name = "Copilot",
                module = "blink-copilot",

                -- Copilot asenkron çalışsın.
                -- Diğer completion kaynaklarını bekletmesin.
                async = true,

                -- AI önerilerini görünür kıl ama LSP'yi tamamen
                -- ezip geçecek kadar yüksek öncelik verme.
                score_offset = 20,

                opts = {
                    -- Aynı anda en fazla üç AI önerisi.
                    max_completions = 3,

                    -- Copilot bazen ilk istekte sonuç döndürmeyebilir.
                    max_attempts = 4,

                    -- Completion menüsünde görünecek isim.
                    kind_name = "Copilot",

                    -- Nerd Font Copilot ikonu.
                    kind_icon = " ",

                    -- Çok sık API isteği göndermesin.
                    debounce = 200,
                },
            },
        },
    },

    -- ─────────────────────────────────────────────────────────
    -- Snippets
    -- ─────────────────────────────────────────────────────────

    snippets = {
        preset = "default",
    },

    -- ─────────────────────────────────────────────────────────
    -- Fuzzy Matching
    -- ─────────────────────────────────────────────────────────

    fuzzy = {
        implementation = "prefer_rust_with_warning",
    },
})

