local wk = require("which-key")

wk.setup({
	preset = "modern",

	delay = 200,

	icons = {
		mappings = true,
	},
})

wk.add({
	{
		"<leader>e",
		desc = "Dosya gezgini",
	},

	{
		"<leader>f",
		desc = "Dosya bul",
	},

	{
		"<leader>?",
		desc = "Tuş rehberi",
	},

	{
		"<leader>p",
		desc = "Proje problemleri",
	},

	{
		"<leader>b",
		desc = "Derleme merkezi",
	},

	{
		"<leader>m",
		desc = "Dosyayı biçimlendir",
	},

	{
		"<leader>M",
		desc = "Markdown görünümü",
	},

	{
		"<leader>i",
		desc = "AI sohbeti",
	},
})
