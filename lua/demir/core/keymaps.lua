local function map(modes, lhs, rhs, desc, extra)
	local options = {
		silent = true,
		desc = desc,
	}

	if extra then
		options = vim.tbl_extend("force", options, extra)
	end

	vim.keymap.set(modes, lhs, rhs, options)
end

-- ─────────────────────────────────────────────────────────────
-- Files
-- ─────────────────────────────────────────────────────────────

map({ "n", "i", "x" }, "<C-s>", "<cmd>write<cr>", "Save file")

-- ─────────────────────────────────────────────────────────────
-- Editing operators
-- ─────────────────────────────────────────────────────────────
--
-- DemirVim deliberately replaces Vim's default editing model:
--
--   c = cut
--   C = copy
--   d = delete
--
-- Cut and copy explicitly use the system clipboard register (+).
-- Delete explicitly uses the black-hole register (_) so deleting text
-- never replaces the current clipboard contents.
--
-- The underlying Vim operators remain native:
--
--   c -> "+d
--   C -> "+y
--   d -> "_d
--
-- This preserves motions, counts, text objects, linewise operations,
-- blockwise operations, and the normal operator grammar.

-- Cut.
map("n", "c", '"+d', "Cut")

-- Repeating the logical cut operator cuts the current line.
--
-- A dedicated mapping is required because the native operator produced by
-- the first logical 'c' is 'd'; without this mapping, a second 'c' would not
-- form the native 'dd' line operation.
map("n", "cc", '"+dd', "Cut line")

-- Copy.
map("n", "C", '"+y', "Copy")

-- Repeating the logical copy operator copies the current line.
map("n", "CC", '"+yy', "Copy line")

-- Delete without modifying clipboard/register history.
map("n", "d", '"_d', "Delete")

-- ─────────────────────────────────────────────────────────────
-- Visual editing
-- ─────────────────────────────────────────────────────────────

map("x", "c", '"+d', "Cut selection")
map("x", "C", '"+y', "Copy selection")
map("x", "d", '"_d', "Delete selection")

-- ─────────────────────────────────────────────────────────────
-- Window navigation
-- ─────────────────────────────────────────────────────────────

map("n", "<C-h>", "<C-w>h", "Focus left window")
map("n", "<C-j>", "<C-w>j", "Focus lower window")
map("n", "<C-k>", "<C-w>k", "Focus upper window")
map("n", "<C-l>", "<C-w>l", "Focus right window")

-- ─────────────────────────────────────────────────────────────
-- Window resizing
-- ─────────────────────────────────────────────────────────────

map("n", "<A-Up>", "<cmd>resize +2<cr>", "Increase window height")
map("n", "<A-Down>", "<cmd>resize -2<cr>", "Decrease window height")
map("n", "<A-Left>", "<cmd>vertical resize -2<cr>", "Decrease window width")
map("n", "<A-Right>", "<cmd>vertical resize +2<cr>", "Increase window width")

-- ─────────────────────────────────────────────────────────────
-- Move selected lines
-- ─────────────────────────────────────────────────────────────

map("x", "J", ":m '>+1<cr>gv=gv", "Move selection down")
map("x", "K", ":m '<-2<cr>gv=gv", "Move selection up")

-- ─────────────────────────────────────────────────────────────
-- Better indentation
-- ─────────────────────────────────────────────────────────────

map("x", "<", "<gv", "Indent selection left")
map("x", ">", ">gv", "Indent selection right")

-- ─────────────────────────────────────────────────────────────
-- Search
-- ─────────────────────────────────────────────────────────────

map("n", "<Esc>", "<cmd>nohlsearch<cr>", "Clear search highlight")

-- ─────────────────────────────────────────────────────────────
-- Diagnostics
-- ─────────────────────────────────────────────────────────────

map("n", "[d", function()
	vim.diagnostic.jump({
		count = -1,
		float = true,
	})
end, "Previous diagnostic")

map("n", "]d", function()
	vim.diagnostic.jump({
		count = 1,
		float = true,
	})
end, "Next diagnostic")
