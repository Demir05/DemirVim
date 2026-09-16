local M = {}

-- Keep clangd-specific process policy isolated from the general LSP
-- orchestration. nvim-lspconfig still provides filetypes, root markers,
-- offset-encoding negotiation, and clangd-specific helper commands.
local command = {
	"clangd",
	"--background-index",
	"--clang-tidy",
	"--enable-config",
}

-- vim.lsp.config() merges this table with the clangd configuration supplied
-- by nvim-lspconfig. Only the process command is overridden here.
vim.lsp.config("clangd", {
	cmd = command,
})

M.command = vim.deepcopy(command)

return M
