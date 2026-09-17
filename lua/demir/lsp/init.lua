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
-- Server-Specific Configuration
-- ─────────────────────────────────────────────────────────────

-- Server-specific overrides must be registered before vim.lsp.enable().
-- demir.lsp.clangd configures the clangd command while preserving the
-- configuration supplied by nvim-lspconfig.
require("demir.lsp.clangd")

-- ─────────────────────────────────────────────────────────────
-- LSP Runtime Behavior
-- ─────────────────────────────────────────────────────────────

-- Register the LspAttach handler before enabling any server.
--
-- vim.lsp.enable() also checks already-existing matching buffers, so the
-- handler must be ready before a client has an opportunity to attach.
require("demir.lsp.keymaps")

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
