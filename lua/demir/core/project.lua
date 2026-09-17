local M = {}

-- Deep Analysis and Problems Center deliberately share one analysis scope.
--
-- The ordering below is policy, not merely a list of possible markers.
-- Existing DemirVim behavior is intentionally preserved:
--
--   1. Git repository root
--   2. CMakePresets.json root
--   3. CMakeUserPresets.json root
--   4. CMakeLists.txt root
--   5. Neovim current working directory
--
-- Each marker is resolved independently so the precedence is explicit and
-- cannot be accidentally changed through vim.fs.root() marker grouping.
local ANALYSIS_ROOT_MARKERS = {
	git = ".git",
	cmake_project_presets = "CMakePresets.json",
	cmake_user_presets = "CMakeUserPresets.json",
	cmake = "CMakeLists.txt",
}

local function normalize_path(path)
	if type(path) ~= "string" or path == "" then
		return ""
	end

	return vim.fs.normalize(path)
end

local function canonical_path(path)
	path = normalize_path(path)

	if path == "" then
		return ""
	end

	local real = vim.uv.fs_realpath(path)

	return normalize_path(real or path)
end

local function fallback_cwd()
	return canonical_path(vim.fn.getcwd())
end

local function valid_source(source)
	if type(source) == "string" then
		if source == "" then
			return nil
		end

		return source
	end

	if type(source) == "number" then
		if source == 0 then
			return source
		end

		if vim.api.nvim_buf_is_valid(source) then
			return source
		end
	end

	return nil
end

local function root_for_marker(source, marker)
	local root = vim.fs.root(source, marker)

	if not root then
		return nil
	end

	return canonical_path(root)
end

---Resolve the project scope used by Deep Analysis and Problems Center.
---
---The policy intentionally prefers the enclosing Git repository when one
---exists. This keeps whole-project analysis stable even when the source file
---belongs to a nested CMake subdirectory.
---
---Invalid or unavailable sources safely fall back to Neovim's current
---working directory.
---
---@param source integer|string|nil
---@return string
function M.analysis_root(source)
	source = valid_source(source)

	if source == nil then
		return fallback_cwd()
	end

	return root_for_marker(source, ANALYSIS_ROOT_MARKERS.git)
		or root_for_marker(source, ANALYSIS_ROOT_MARKERS.cmake_project_presets)
		or root_for_marker(source, ANALYSIS_ROOT_MARKERS.cmake_user_presets)
		or root_for_marker(source, ANALYSIS_ROOT_MARKERS.cmake)
		or fallback_cwd()
end

return M
