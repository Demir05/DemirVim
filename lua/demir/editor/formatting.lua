local M = {}

local conform = require("conform")

-- ─────────────────────────────────────────────────────────────
-- Formatting Policy
-- ─────────────────────────────────────────────────────────────

local FORMAT_TIMEOUT_MS = 3000

local function valid_buffer(bufnr)
	return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

local function normal_buffer(bufnr)
	return valid_buffer(bufnr) and vim.bo[bufnr].buftype == ""
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = "Formatting",
	})
end

conform.setup({
	formatters_by_ft = {
		-- C / C++
		c = {
			"clang_format",
		},

		cpp = {
			"clang_format",
		},

		objc = {
			"clang_format",
		},

		objcpp = {
			"clang_format",
		},

		-- Lua
		lua = {
			"stylua",
		},

		-- CMake
		cmake = {
			"gersemi",
		},

		-- Shell
		sh = {
			"shfmt",
		},

		bash = {
			"shfmt",
		},

		-- JSON
		json = {
			"prettier",
		},

		jsonc = {
			"prettier",
		},

		-- YAML
		yaml = {
			"prettier",
		},

		-- Markdown
		markdown = {
			"prettier",
		},

		-- JavaScript / TypeScript
		javascript = {
			"prettier",
		},

		javascriptreact = {
			"prettier",
		},

		typescript = {
			"prettier",
		},

		typescriptreact = {
			"prettier",
		},

		-- Web
		html = {
			"prettier",
		},

		css = {
			"prettier",
		},

		scss = {
			"prettier",
		},

		less = {
			"prettier",
		},
	},

	-- Keep one formatting policy everywhere:
	-- prefer a configured Conform formatter and fall back to LSP formatting
	-- only when no external formatter is available for the buffer.
	default_format_opts = {
		lsp_format = "fallback",
	},

	notify_on_error = true,
	notify_no_formatters = true,

	-- Format on save for normal source files. Markdown remains manual-only.
	format_on_save = function(bufnr)
		if not normal_buffer(bufnr) then
			return nil
		end

		if vim.bo[bufnr].filetype == "markdown" then
			return nil
		end

		return {
			timeout_ms = FORMAT_TIMEOUT_MS,
		}
	end,
})

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

function M.can_format(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if not normal_buffer(bufnr) then
		return false
	end

	local ok, formatters, will_use_lsp = pcall(conform.list_formatters_to_run, bufnr)

	if not ok then
		return false
	end

	return (type(formatters) == "table" and #formatters > 0) or will_use_lsp == true
end

function M.format_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if not normal_buffer(bufnr) then
		notify("The current buffer is not a normal file buffer.", vim.log.levels.WARN)
		return false
	end

	if not M.can_format(bufnr) then
		notify("No formatter is available for the current buffer.", vim.log.levels.WARN)
		return false
	end

	local ok, attempted = pcall(conform.format, {
		bufnr = bufnr,
		async = true,
	})

	if not ok then
		notify("Formatting could not be started: " .. tostring(attempted), vim.log.levels.ERROR)
		return false
	end

	return attempted == true
end

-- ─────────────────────────────────────────────────────────────
-- Keymap
-- ─────────────────────────────────────────────────────────────

vim.keymap.set("n", "<leader>m", function()
	M.format_buffer(vim.api.nvim_get_current_buf())
end, {
	desc = "Format file",
})

return M
