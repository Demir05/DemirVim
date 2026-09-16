local capabilities = require("blink.cmp").get_lsp_capabilities()

-- ─────────────────────────────────────────────────────────────
-- LSP Client Capabilities
-- ─────────────────────────────────────────────────────────────

capabilities.textDocument = capabilities.textDocument or {}

-- Keep the hierarchy capabilities explicit. They are consumed by the custom
-- Call Hierarchy and Type Hierarchy UIs and are harmless if the completion
-- capability provider already advertised them.
capabilities.textDocument.callHierarchy = capabilities.textDocument.callHierarchy or {
	dynamicRegistration = false,
}

capabilities.textDocument.typeHierarchy = capabilities.textDocument.typeHierarchy or {
	dynamicRegistration = false,
}

-- Shared defaults are merged into every enabled LSP configuration by Neovim.
vim.lsp.config("*", {
	capabilities = capabilities,
})

-- ─────────────────────────────────────────────────────────────
-- Lua
-- ─────────────────────────────────────────────────────────────

vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			runtime = {
				version = "LuaJIT",
			},

			diagnostics = {
				globals = {
					"vim",
				},
			},

			workspace = {
				checkThirdParty = false,
				library = vim.api.nvim_get_runtime_file("", true),
			},

			telemetry = {
				enable = false,
			},
		},
	},
})

-- ─────────────────────────────────────────────────────────────
-- Language Servers
-- ─────────────────────────────────────────────────────────────

local servers = {
	"clangd", -- C / C++
	"lua_ls", -- Lua
	"jsonls", -- JSON / JSONC
	"yamlls", -- YAML
	"marksman", -- Markdown
	"bashls", -- Bash / shell
	"cmake", -- CMake
}

vim.lsp.enable(servers)

-- ─────────────────────────────────────────────────────────────
-- Semantic Tools
-- ─────────────────────────────────────────────────────────────

require("demir.lsp.call_hierarchy")
require("demir.lsp.type_hierarchy")
require("demir.lsp.clangd")
