vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- ─────────────────────────────────────────────────────────────
-- Core
-- ─────────────────────────────────────────────────────────────

require("demir.core.options")
require("demir.core.keymaps")
require("demir.core.autocmds")
require("demir.core.tutorial")

-- ─────────────────────────────────────────────────────────────
-- Packages
-- ─────────────────────────────────────────────────────────────

require("demir.packages")

-- ─────────────────────────────────────────────────────────────
-- UI
-- ─────────────────────────────────────────────────────────────

require("demir.ui.theme")
require("demir.ui.icons")
require("demir.ui.snacks")
require("demir.ui.context_menu")
require("demir.ui.whichkey")
require("demir.ui.statusline")

-- ─────────────────────────────────────────────────────────────
-- Editor
-- ─────────────────────────────────────────────────────────────

require("demir.editor.treesitter")
require("demir.editor.completion")
require("demir.editor.formatting")
require("demir.editor.markdown")

-- ─────────────────────────────────────────────────────────────
-- LSP
-- ─────────────────────────────────────────────────────────────

require("demir.lsp")
require("demir.lsp.diagnostics")

-- AI
require("demir.ai.copilot")
require("demir.ai.chat")
-- AI

-- ─────────────────────────────────────────────────────────────
-- Build
-- ─────────────────────────────────────────────────────────────

require("demir.build.cmake")
-- Debug
require("demir.debug")
