local map = vim.keymap.set

local opts = {
    noremap = true,
    silent = true,
}

-- ─────────────────────────────────────────────────────────────
-- Files
-- ─────────────────────────────────────────────────────────────

map({ "n", "i", "v" }, "<C-s>", "<cmd>write<cr>", {
    desc = "Save file",
})

-- ─────────────────────────────────────────────────────────────
-- Better movement
-- ─────────────────────────────────────────────────────────────

map("n", "<C-h>", "<C-w>h", opts)
map("n", "<C-j>", "<C-w>j", opts)
map("n", "<C-k>", "<C-w>k", opts)
map("n", "<C-l>", "<C-w>l", opts)

-- ─────────────────────────────────────────────────────────────
-- Window resizing
-- ─────────────────────────────────────────────────────────────

map("n", "<A-Up>", "<cmd>resize +2<cr>", opts)
map("n", "<A-Down>", "<cmd>resize -2<cr>", opts)
map("n", "<A-Left>", "<cmd>vertical resize -2<cr>", opts)
map("n", "<A-Right>", "<cmd>vertical resize +2<cr>", opts)

-- ─────────────────────────────────────────────────────────────
-- Move selected lines
-- ─────────────────────────────────────────────────────────────

map("v", "J", ":m '>+1<cr>gv=gv", opts)
map("v", "K", ":m '<-2<cr>gv=gv", opts)

-- ─────────────────────────────────────────────────────────────
-- Better indentation
-- ─────────────────────────────────────────────────────────────

map("v", "<", "<gv", opts)
map("v", ">", ">gv", opts)

-- ─────────────────────────────────────────────────────────────
-- Search
-- ─────────────────────────────────────────────────────────────

map("n", "<Esc>", "<cmd>nohlsearch<cr>", opts)

-- ─────────────────────────────────────────────────────────────
-- Diagnostics
-- ─────────────────────────────────────────────────────────────

map("n", "[d", function()
    vim.diagnostic.jump({
        count = -1,
        float = true,
    })
end, {
    desc = "Previous diagnostic",
})

map("n", "]d", function()
    vim.diagnostic.jump({
        count = 1,
        float = true,
    })
end, {
    desc = "Next diagnostic",
})

