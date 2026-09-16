local M = {}

local diagnostic = vim.diagnostic
local severity = diagnostic.severity

-- ─────────────────────────────────────────────────────────────
-- Diagnostic Appearance
-- ─────────────────────────────────────────────────────────────

local icons = {
	[severity.ERROR] = "",
	[severity.WARN] = "",
	[severity.INFO] = "",
	[severity.HINT] = "",
}

local sign_highlights = {
	[severity.ERROR] = "DiagnosticSignError",
	[severity.WARN] = "DiagnosticSignWarn",
	[severity.INFO] = "DiagnosticSignInfo",
	[severity.HINT] = "DiagnosticSignHint",
}

local function truncate_display(text, max_width)
	if vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end

	local ellipsis = "…"
	local target_width = math.max(0, max_width - vim.fn.strdisplaywidth(ellipsis))
	local low = 0
	local high = vim.fn.strchars(text)

	while low < high do
		local mid = math.floor((low + high + 1) / 2)
		local part = vim.fn.strcharpart(text, 0, mid)

		if vim.fn.strdisplaywidth(part) <= target_width then
			low = mid
		else
			high = mid - 1
		end
	end

	return vim.fn.strcharpart(text, 0, low) .. ellipsis
end

local function compact_message(item)
	local message = tostring(item.message or ""):gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")

	return truncate_display(message, 100)
end

-- ─────────────────────────────────────────────────────────────
-- Global Diagnostic Policy
-- ─────────────────────────────────────────────────────────────

diagnostic.config({
	-- ERROR > WARN > INFO > HINT.
	severity_sort = true,

	-- Preserve the existing live-feedback behavior while typing.
	update_in_insert = true,

	-- Sign column.
	signs = {
		priority = 20,
		text = icons,
	},

	-- Keep the editor visually quiet: underline only errors and warnings.
	underline = {
		severity = {
			min = severity.WARN,
		},
	},

	-- Show short inline text only for the current line and only for
	-- errors/warnings. Other lines retain signs and underlines.
	virtual_text = {
		current_line = true,

		severity = {
			min = severity.WARN,
		},

		spacing = 2,
		source = false,

		prefix = function(item)
			return icons[item.severity] or "●"
		end,

		format = compact_message,
	},

	virtual_lines = false,

	-- Diagnostic popup.
	float = {
		border = "rounded",
		scope = "line",
		severity_sort = true,
		source = "if_many",

		header = {
			" 󰒡 Diagnostics ",
			"DiagnosticInfo",
		},

		prefix = function(item)
			return (icons[item.severity] or "●") .. " ", sign_highlights[item.severity] or "DiagnosticSignInfo"
		end,

		suffix = function(item)
			if item.code ~= nil and tostring(item.code) ~= "" then
				return "  [" .. tostring(item.code) .. "]", "Comment"
			end

			return ""
		end,

		max_width = 100,
		max_height = 25,
	},

	-- Do not wrap from the final diagnostic back to the first one.
	jump = {
		wrap = false,
	},
})

M.icons = icons
M.sign_highlights = sign_highlights

return M
