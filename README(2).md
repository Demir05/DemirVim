# Demir Neovim

CachyOS / Arch Linux üzerinde çalışan, native `vim.pack` kullanan kişisel Neovim IDE yapılandırması.

Amaç; Neovim'in hızını ve sadeliğini korurken C/C++, Lua, CMake, Markdown, JSON, YAML ve Bash için IDE düzeyinde tamamlama, LSP, tanılama, dosya arama, terminal ve GitHub Copilot desteği sağlamaktır.

## Özellikler

- Native Neovim paket yöneticisi: `vim.pack`
- Gruber Darker renk teması
- Nerd Font ikonları
- Snacks dosya gezgini, picker, grep, terminal ve bildirim sistemi
- Which-key tuş yardım menüsü
- Lualine durum çubuğu
- Tree-sitter sözdizimi ayrıştırma
- Blink completion ve snippet sistemi
- Native Neovim LSP
- C/C++ için `clangd`
- Lua, JSON, YAML, Markdown, Bash ve CMake language server desteği
- GitHub Copilot + Blink entegrasyonu
- Proje içi tuş rehberi: `:Keys` veya `<Space>?`

## Sistem gereksinimleri

Bu yapılandırma CachyOS / Arch Linux için hazırlanmıştır.

Önerilen temel ortam:

- Neovim 0.12+
- Git
- GCC
- Clang
- CMake
- Ninja
- GDB
- Wayland üzerinde `wl-clipboard`
- Bir Nerd Font

## Hızlı kurulum

### 1. Bağımlılıkları kur

Depoda bulunan kurulum betiğini çalıştır:

```bash
chmod +x install-deps.sh
./install-deps.sh
```

Betiğin yaptığı kurulum kabaca şu gruplardan oluşur:

- Neovim ve paket indirme araçları
- Snacks için `ripgrep` ve `fd`
- Tree-sitter için `tree-sitter-cli` ve C derleyicisi
- C/C++ geliştirme araçları
- Language server'lar
- Bash analiz / biçimlendirme araçları
- Nerd Font
- Wayland clipboard desteği

CMake language server Arch resmi deposunda bulunmadığı için betik onu `paru` veya `yay` üzerinden AUR'dan kurmaya çalışır.

### 2. Yapılandırmayı yerleştir

Mevcut Neovim yapılandırmasını yedeklemek istersen:

```bash
mv ~/.config/nvim ~/.config/nvim.backup
```

Ardından bu depoyu Neovim yapılandırma dizinine klonla:

```bash
git clone <REPOSITORY_URL> ~/.config/nvim
```

### 3. Neovim'i ilk kez başlat

```bash
nvim
```

İlk açılışta `vim.pack` gerekli eklentileri indirir.

Tree-sitter parser'ları da yapılandırmada tanımlanan dillere göre kurulur.

İlk açılış normalden biraz daha uzun sürebilir.

## GitHub Copilot

Copilot tamamlamaları Blink menüsüne entegredir.

İlk kurulumdan sonra Neovim içinde:

```vim
:Copilot auth
```

komutunu çalıştır ve GitHub hesabınla giriş yap.

Mevcut yapılandırma native Copilot binary language server kullanır.

Copilot'un kendi inline paneli ve ayrı suggestion arayüzü kapalıdır. Tamamlamalar Blink üzerinden tek bir menüde gösterilir.

## Language Server'lar

Yapılandırmada aşağıdaki sunucular etkinleştirilmiştir:

| Dil / dosya türü | Language server | Sistem paketi |
| --- | --- | --- |
| C / C++ | `clangd` | `clang` |
| Lua | `lua_ls` | `lua-language-server` |
| JSON | `jsonls` | `vscode-json-languageserver` |
| YAML | `yamlls` | `yaml-language-server` |
| Markdown | `marksman` | `marksman` |
| Bash | `bashls` | `bash-language-server` |
| CMake | `cmake` | `cmake-language-server` (AUR) |

`clang` paketi ayrıca `clang-format` ve `clang-tidy` araçlarını da sağlar.

## C/C++ proje desteği

C/C++ projelerinde `clangd`'nin doğru çalışması için mümkün olduğunda bir `compile_commands.json` kullanılmalıdır.

CMake projelerinde:

```bash
cmake -S . -B build -G Ninja \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

ve ardından:

```bash
cmake --build build
```

kullanılabilir.

Proje `.clangd` dosyası farklı bir compilation database dizini belirtmiyorsa `clangd`, proje yapısına göre `compile_commands.json` arar.

## Dış bağımlılıklar neden gerekli?

### `ripgrep`

Snacks picker içindeki hızlı metin arama işlemleri için kullanılır.

### `fd`

Dosya bulma işlemlerini hızlandırır.

### `tree-sitter-cli`

Tree-sitter parser'larının kurulması ve güncellenmesi için gereklidir.

### GCC / Clang

Tree-sitter parser derlemeleri için bir C derleyicisi gerekir.

C/C++ tarafında:

- GCC ana proje derleyicisi olarak kullanılabilir.
- `clangd` LSP sağlar.
- `clang-format` biçimlendirme sağlar.
- `clang-tidy` statik analiz sağlar.

### Nerd Font

`nvim-web-devicons`, Snacks ve durum çubuğundaki ikonların doğru görünmesi için gereklidir.

Varsayılan öneri:

```text
JetBrainsMono Nerd Font
```

### Node.js

Copilot native binary modunda Node.js zorunlu değildir.

Ancak JSON, YAML ve Bash language server paketlerinin bir kısmı Node.js tabanlıdır. Bu nedenle kurulum betiği Node.js'i de yükler.

## Temel tuşlar

Leader tuşu:

```text
Space
```

Önemli kısayollar:

| Tuş | İşlev |
| --- | --- |
| `<Space>e` | Dosya gezgini |
| `<Space>f` | Projede dosya bul |
| `<Space>ff` | Home altında dosya bul |
| `<Space>F` | Dosya içeriklerinde ara |
| `<Space>t` | Terminal |
| `<Space>?` | Tuş rehberi |
| `K` | LSP hover |
| `gd` | Tanıma git |
| `gD` | Declaration |
| `gr` | References |
| `gI` | Implementation |
| `gy` | Type definition |
| `<Space>r` | Yeniden adlandır |
| `<Space>a` | Code action |
| `<Space>h` | Function signature |

Daha ayrıntılı rehber için:

```vim
:Keys
```

## Özel düzenleme modeli

Bu yapılandırmada standart Vim davranışının bazı kısımları bilinçli olarak değiştirilmiştir.

```text
c = cut
C = copy
d = delete
p = paste
```

Kesme ve kopyalama sistem clipboard'u kullanır.

Silme işlemi black-hole register kullanır, böylece mevcut clipboard içeriği korunur.

Örnekler:

```text
cw   -> kelimeyi kes
Cw   -> kelimeyi kopyala
dw   -> kelimeyi sil

cc   -> satırı kes
CC   -> satırı kopyala
dd   -> satırı sil
```

## Sağlık kontrolü

Kurulumdan sonra Neovim içinde şu kontroller kullanılabilir:

```vim
:checkhealth
:checkhealth nvim-treesitter
:checkhealth vim.lsp
:checkhealth snacks
```

Aktif LSP istemcilerini görmek için:

```vim
:lua vim.print(vim.lsp.get_clients({ bufnr = 0 }))
```

## Komut satırı kontrolleri

Kurulumun ardından temel araçları kontrol etmek için:

```bash
nvim --version
git --version

rg --version
fd --version

gcc --version
g++ --version

clangd --version
clang-format --version
clang-tidy --version

cmake --version
ninja --version
gdb --version

tree-sitter --version

lua-language-server --version
bash-language-server --version
yaml-language-server --version
marksman --version

cmake-language-server --version
```

JSON language server için:

```bash
vscode-json-language-server --help
```

## Yapılandırma yapısı

```text
~/.config/nvim/
├── init.lua
├── TUTORIAL.md
└── lua/
    └── demir/
        ├── ai/
        │   └── copilot.lua
        ├── core/
        │   ├── autocmds.lua
        │   ├── keymaps.lua
        │   ├── options.lua
        │   └── tutorial.lua
        ├── editor/
        │   ├── completion.lua
        │   └── treesitter.lua
        ├── lsp/
        │   ├── diagnostics.lua
        │   ├── init.lua
        │   └── keymaps.lua
        ├── ui/
        │   ├── icons.lua
        │   ├── snacks.lua
        │   ├── statusline.lua
        │   ├── theme.lua
        │   └── whichkey.lua
        └── packages.lua
```

## Eklentiler

Ana eklentiler:

```text
folke/snacks.nvim
folke/which-key.nvim
nvim-lualine/lualine.nvim
nvim-treesitter/nvim-treesitter
blazkowolf/gruber-darker.nvim
nvim-tree/nvim-web-devicons
Saghen/blink.cmp
rafamadriz/friendly-snippets
neovim/nvim-lspconfig
zbirenbaum/copilot.lua
fang2hou/blink-copilot
```

## Notlar

Snacks image özelliği bu yapılandırmada etkin değildir. Bu nedenle Kitty Graphics Protocol, ImageMagick, Mermaid CLI, LaTeX veya benzeri image-rendering bağımlılıklarının kurulması gerekmez.

Blink fuzzy matcher desteklenen sistemlerde hazır Rust binary'sini kullanabilir. Normal kurulum için Rust toolchain zorunlu değildir.

Neovim yapılandırması geliştikçe bu README de güncellenmelidir.
