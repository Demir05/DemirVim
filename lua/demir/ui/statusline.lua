local function context_name()
    local ft = vim.bo.filetype
    local bt = vim.bo.buftype

    -- Snacks picker / explorer
    if ft == "snacks_picker_list" then
        return "󰙅  EXPLORER"
    end

    -- Terminal
    if bt == "terminal" then
        return "󰆍  TERMINAL"
    end

    -- Tuş rehberi
    if ft == "markdown" then
        local name = vim.api.nvim_buf_get_name(0)

        if name:match("TUTORIAL%.md$") then
            return "󰋖  TUŞ REHBERİ"
        end
    end

    -- Gerçek dosya
    local name = vim.api.nvim_buf_get_name(0)

    if name == "" then
        return "󰈔  YENİ BUFFER"
    end

    local relative = vim.fn.fnamemodify(name, ":~:.")

    if vim.bo.modified then
        relative = relative .. " [+]"
    end

    if vim.bo.readonly then
        relative = relative .. " [RO]"
    end

    return relative
end

local function project_name()
    local cwd = vim.fn.getcwd()

    if cwd == "" then
        return ""
    end

    return "󰉋  " .. vim.fn.fnamemodify(cwd, ":t")
end

require("lualine").setup({
    options = {
        icons_enabled = true,

        theme = "auto",

        component_separators = {
            left = "│",
            right = "│",
        },

        section_separators = {
            left = "",
            right = "",
        },

        globalstatus = true,
    },

    sections = {
        lualine_a = {
            {
                "mode",
                fmt = string.upper,
            },
        },

        lualine_b = {
            {
                "branch",
                icon = "",
            },

            {
                "diff",
                symbols = {
                    added = "+",
                    modified = "~",
                    removed = "-",
                },
            },

            "diagnostics",
        },

        lualine_c = {
            {
                context_name,
            },

            {
                project_name,
                cond = function()
                    return vim.o.columns > 100
                end,
            },
        },

        lualine_x = {
            {
                "filetype",
                cond = function()
                    return vim.bo.buftype == ""
                end,
            },

            {
                "encoding",
                fmt = string.upper,
                cond = function()
                    return vim.bo.buftype == ""
                end,
            },

            {
                "fileformat",
                cond = function()
                    return vim.bo.buftype == ""
                end,
            },
        },

        lualine_y = {
            {
                "progress",
                cond = function()
                    return vim.bo.buftype == ""
                end,
            },
        },

        lualine_z = {
            "location",
        },
    },

    inactive_sections = {
        lualine_a = {},
        lualine_b = {},

        lualine_c = {
            context_name,
        },

        lualine_x = {
            "location",
        },

        lualine_y = {},
        lualine_z = {},
    },
})
