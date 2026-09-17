local lualine = require("lualine")

local TUTORIAL_CONTEXT = "tutorial"
local CONTEXT_VAR = "demir_statusline_context"

-- ─────────────────────────────────────────────────────────────
-- Buffer Context
-- ─────────────────────────────────────────────────────────────

local function current_buffer()
    local buf = vim.api.nvim_get_current_buf()

    if not vim.api.nvim_buf_is_valid(buf) then
        return nil
    end

    return buf
end

local function buffer_context(buf)
    if not buf then
        return nil
    end

    local value = vim.b[buf][CONTEXT_VAR]

    if type(value) == "string" and value ~= "" then
        return value
    end

    return nil
end

local function buffer_name(buf)
    if not buf then
        return ""
    end

    return vim.api.nvim_buf_get_name(buf)
end

local function is_tutorial_buffer(buf)
    if not buf then
        return false
    end

    -- Primary contract: the tutorial producer marks its scratch buffer
    -- explicitly. This works even when the buffer deliberately has no real
    -- filesystem path.
    if buffer_context(buf) == TUTORIAL_CONTEXT then
        return true
    end

    local name = buffer_name(buf)

    -- Compatibility fallbacks:
    --   1. an explicitly named DemirVim tutorial scratch buffer;
    --   2. TUTORIAL.md opened as a real Markdown file.
    if name:match("^demir://tutorial/") then
        return true
    end

    return vim.bo[buf].filetype == "markdown" and name:match("TUTORIAL%.md$") ~= nil
end

local function is_snacks_picker_buffer(buf)
    if not buf then
        return false
    end

    local ft = vim.bo[buf].filetype

    return ft == "snacks_picker_list" or ft == "snacks_picker_input"
end

local function context_name()
    local buf = current_buffer()

    if not buf then
        return ""
    end

    local ft = vim.bo[buf].filetype
    local bt = vim.bo[buf].buftype
    local name = buffer_name(buf)

    -- DemirVim-owned semantic scratch contexts must be identified before
    -- generic nofile/new-buffer handling.
    if is_tutorial_buffer(buf) then
        return "󰋖  TUŞ REHBERİ"
    end

    -- snacks_picker_list is shared by Explorer and the other Snacks pickers.
    -- Calling every picker "EXPLORER" is therefore incorrect. Keep the
    -- statusline honest without depending on Snacks' internal picker fields.
    if is_snacks_picker_buffer(buf) then
        return "󰈞  PICKER"
    end

    if bt == "terminal" then
        return "󰆍  TERMINAL"
    end

    if bt == "help" then
        return "󰋖  HELP"
    end

    if bt == "quickfix" then
        return "󰁨  QUICKFIX"
    end

    if bt == "prompt" then
        return "󰘳  PROMPT"
    end

    -- Do not present arbitrary plugin-owned scratch buffers as real files.
    if bt ~= "" then
        if ft ~= "" then
            return string.format("󰈔  %s", ft:upper())
        end

        return "󰈔  SCRATCH"
    end

    if name == "" then
        return "󰈔  YENİ BUFFER"
    end

    local cwd = vim.fn.getcwd()
    local relative = nil

    if cwd ~= "" then
        relative = vim.fs.relpath(cwd, name)
    end

    if not relative then
        relative = vim.fn.fnamemodify(name, ":~")
    end

    if vim.bo[buf].modified then
        relative = relative .. " [+]"
    end

    if vim.bo[buf].readonly or not vim.bo[buf].modifiable then
        relative = relative .. " [RO]"
    end

    return relative
end

-- ─────────────────────────────────────────────────────────────
-- Working Directory Context
-- ─────────────────────────────────────────────────────────────

local function cwd_name()
    local cwd = vim.fn.getcwd()

    if cwd == "" then
        return ""
    end

    local tail = vim.fn.fnamemodify(cwd, ":t")

    if tail == "" then
        tail = cwd
    end

    return "󰉋  " .. tail
end

local function show_file_metadata()
    local buf = current_buffer()

    if not buf then
        return false
    end

    return vim.bo[buf].buftype == "" and not is_tutorial_buffer(buf) and not is_snacks_picker_buffer(buf)
end

local function show_location()
    local buf = current_buffer()

    if not buf then
        return false
    end

    return vim.bo[buf].buftype ~= "terminal" and not is_snacks_picker_buffer(buf)
end

-- ─────────────────────────────────────────────────────────────
-- Lualine
-- ─────────────────────────────────────────────────────────────

lualine.setup({
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
                cwd_name,
                cond = function()
                    return vim.o.columns > 100
                end,
            },
        },

        lualine_x = {
            {
                "filetype",
                cond = show_file_metadata,
            },

            {
                "encoding",
                fmt = string.upper,
                cond = show_file_metadata,
            },

            {
                "fileformat",
                cond = show_file_metadata,
            },
        },

        lualine_y = {
            {
                "progress",
                cond = show_file_metadata,
            },
        },

        lualine_z = {
            {
                "location",
                cond = show_location,
            },
        },
    },

    inactive_sections = {
        lualine_a = {},
        lualine_b = {},

        lualine_c = {
            context_name,
        },

        lualine_x = {
            {
                "location",
                cond = show_location,
            },
        },

        lualine_y = {},
        lualine_z = {},
    },
})
