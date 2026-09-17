local M = {}

-- LSP workspace ownership is authoritative for semantic tools. These markers
-- are used only when a live client does not expose workspace_folders/root_dir.
-- Keep them at equal priority so the nearest matching ancestor wins.
local FALLBACK_ROOT_MARKERS = {
	{
		".clangd",
		"compile_commands.json",
		"compile_flags.txt",
		"CMakePresets.json",
		"CMakeUserPresets.json",
		"CMakeLists.txt",
		".git",
	},
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

local function uri_to_file(uri)
	if type(uri) ~= "string" or not uri:match("^file:") then
		return nil
	end

	local ok, file = pcall(vim.uri_to_fname, uri)

	if not ok or type(file) ~= "string" or file == "" then
		return nil
	end

	return canonical_path(file)
end

local function path_in_root(root, file)
	root = canonical_path(root)
	file = canonical_path(file)

	if root == "" or file == "" then
		return false
	end

	return file == root or vim.fs.relpath(root, file) ~= nil
end

---Collect the workspace roots owned by an LSP client.
---
---workspace_folders and root_dir are authoritative. Filesystem markers are a
---display/navigation fallback only for clients that expose neither value.
---Returned roots are canonicalized and ordered from the most specific root to
---the least specific one.
---
---@param client table|nil
---@param source_file string
---@return string primary_root
---@return string[] roots
function M.collect_roots(client, source_file)
	source_file = canonical_path(source_file)

	local roots = {}
	local seen = {}

	local function add_root(root)
		root = canonical_path(root)

		if root == "" or seen[root] then
			return
		end

		seen[root] = true
		table.insert(roots, root)
	end

	for _, folder in ipairs(type(client and client.workspace_folders) == "table" and client.workspace_folders or {}) do
		if type(folder) == "table" and folder.uri then
			add_root(uri_to_file(folder.uri))
		end
	end

	if client and type(client.root_dir) == "string" then
		add_root(client.root_dir)
	end

	if #roots == 0 then
		local fallback_source = source_file ~= "" and source_file or vim.fn.getcwd()
		local fallback = vim.fs.root(fallback_source, FALLBACK_ROOT_MARKERS)

		add_root(fallback or vim.fn.getcwd())
	end

	-- When multiple workspace folders contain the same source file they form an
	-- ancestor chain. The longest canonical path is therefore the most specific.
	table.sort(roots, function(a, b)
		if #a ~= #b then
			return #a > #b
		end

		return a < b
	end)

	for _, root in ipairs(roots) do
		if path_in_root(root, source_file) then
			return root, roots
		end
	end

	return roots[1], roots
end

---Return a path relative to the most specific matching workspace root.
---
---@param roots string[]|nil
---@param file string
---@return string|nil
function M.relative_path(roots, file)
	file = canonical_path(file)

	if file == "" then
		return nil
	end

	for _, root in ipairs(type(roots) == "table" and roots or {}) do
		local relative = vim.fs.relpath(root, file)

		if relative then
			return relative
		end
	end

	return nil
end

M.canonical_path = canonical_path
M.path_in_root = path_in_root

return M
