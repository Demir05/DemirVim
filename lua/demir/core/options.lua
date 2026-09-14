local opt = vim.opt

-- ─────────────────────────────────────────────────────────────
-- Interface
-- ─────────────────────────────────────────────────────────────

opt.number = true
opt.relativenumber = false

opt.cursorline = true
opt.signcolumn = "yes"

opt.termguicolors = true

opt.showmode = false

opt.scrolloff = 8
opt.sidescrolloff = 8

-- ─────────────────────────────────────────────────────────────
-- Editing
-- ─────────────────────────────────────────────────────────────

opt.expandtab = true
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4

opt.smartindent = true

opt.wrap = false

opt.backspace = {
    "indent",
    "eol",
    "start",
}

-- ─────────────────────────────────────────────────────────────
-- Searching
-- ─────────────────────────────────────────────────────────────

opt.ignorecase = true
opt.smartcase = true

opt.incsearch = true

-- ─────────────────────────────────────────────────────────────
-- Splits
-- ─────────────────────────────────────────────────────────────

opt.splitright = true
opt.splitbelow = true

-- ─────────────────────────────────────────────────────────────
-- Completion
-- ─────────────────────────────────────────────────────────────

opt.completeopt = {
    "menu",
    "menuone",
    "noselect",
    "popup",
}

opt.pumheight = 12

-- ─────────────────────────────────────────────────────────────
-- Responsiveness
-- ─────────────────────────────────────────────────────────────

opt.updatetime = 200
opt.timeoutlen = 400

-- ─────────────────────────────────────────────────────────────
-- Files
-- ─────────────────────────────────────────────────────────────

opt.swapfile = false
opt.backup = false
opt.writebackup = false

opt.undofile = true

-- ─────────────────────────────────────────────────────────────
-- Clipboard
-- ─────────────────────────────────────────────────────────────

opt.clipboard = "unnamedplus"

-- ─────────────────────────────────────────────────────────────
-- Mouse
-- ─────────────────────────────────────────────────────────────

opt.mouse = "a"

-- ─────────────────────────────────────────────────────────────
-- Miscellaneous
-- ─────────────────────────────────────────────────────────────

opt.confirm = true

opt.fillchars = {
    eob = " ",
}

opt.list = true

opt.listchars = {
    tab = "» ",
    trail = "·",
    nbsp = "␣",
}
