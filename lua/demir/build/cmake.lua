local cmake = require("cmake-tools")
local buildsentry = require("buildsentry")

-- ─────────────────────────────────────────────────────────────
-- CMake Tools
-- ─────────────────────────────────────────────────────────────

cmake.setup({
    cmake_command = "cmake",
    ctest_command = "ctest",

    -- Derleyici, build tipi, generator ve build dizini için
    -- tek gerçek kaynak CMakePresets.json olsun.
    cmake_use_preset = true,

    -- Dosya kaydederken arka planda sürpriz configure işlemleri yapma.
    -- Configure işlemleri kontrollü ve görünür olsun.
    cmake_regenerate_on_save = false,

    -- Bu bilgiler zaten CMakeLists.txt / CMakePresets.json içinde.
    -- Aynı ayarı iki farklı yerde tutmuyoruz.
    cmake_generate_options = {},
    cmake_build_options = {},

    -- ─────────────────────────────────────────────────────────
    -- Debug
    -- ─────────────────────────────────────────────────────────
    --
    -- cmake-tools varsayılan olarak codelldb kullanır.
    -- Biz native GDB DAP kullanıyoruz.
    --
    -- CMakeDebug seçili executable target'ın program yolunu
    -- kendi ekler. Burada sadece adapter davranışını belirliyoruz.
    cmake_dap_configuration = {
        name = "C++ Debug",
        type = "gdb",
        request = "launch",

        -- Breakpoint yoksa main() girişinde otomatik durma.
        stopAtBeginningOfMainSubprogram = false,

        -- İlk makine talimatında da otomatik durma.
        stopOnEntry = false,
    },

    -- cmake-tools compile_commands.json symlink'i oluşturmasın.
    -- Aktif profile göre bunu aşağıda kendimiz yönetiyoruz.
    cmake_compile_commands_options = {
        action = "none",
    },

    cmake_always_use_terminal = false,
})

-- ─────────────────────────────────────────────────────────────
-- BuildSentry
-- ─────────────────────────────────────────────────────────────

buildsentry.setup({
    -- Configure, Build ve Run çıktıları BuildSentry içerisinde
    -- gösterilsin.
    attach_cmake_tools = true,
})

-- BuildSentry task geçmişine saat + süre ekle.
require("demir.build.buildsentry_time").setup()

-- ─────────────────────────────────────────────────────────────
-- Yardımcılar
-- ─────────────────────────────────────────────────────────────

local function project_root()
    local root = vim.fs.root(vim.fn.getcwd(), {
        "CMakePresets.json",
        "CMakeLists.txt",
        ".git",
    })

    return root or vim.fn.getcwd()
end

local function save_all()
    local ok, err = pcall(
        vim.cmd,
        "silent wall"
    )

    if not ok then
        vim.notify(
            "Dosyalar kaydedilemedi:\n" .. tostring(err),
            vim.log.levels.ERROR,
            {
                title = "Build",
            }
        )

        return false
    end

    return true
end

-- cmake-tools get_build_directory() bazı sürümlerde string,
-- bazı sürümlerde Plenary Path nesnesi döndürebilir.
local function get_build_directory_string()
    local build_path = cmake.get_build_directory()

    if not build_path then
        return nil
    end

    if type(build_path) == "string" then
        return build_path
    end

    if type(build_path) == "table" then
        if type(build_path.filename) == "string" then
            return build_path.filename
        end

        if type(build_path.absolute) == "function" then
            local ok, absolute = pcall(
                build_path.absolute,
                build_path
            )

            if ok and type(absolute) == "string" then
                return absolute
            end
        end
    end

    return nil
end

local function refresh_compile_commands()
    local root = project_root()

    local build_dir =
        get_build_directory_string()

    if not build_dir or build_dir == "" then
        vim.notify(
            "Aktif CMake build dizini bulunamadı.",
            vim.log.levels.ERROR,
            {
                title = "CMake",
            }
        )

        return false
    end

    -- Göreli yol gelirse proje köküne göre mutlaklaştır.
    if not vim.startswith(build_dir, "/") then
        build_dir = vim.fs.joinpath(
            root,
            build_dir
        )
    end

    build_dir =
        vim.fs.normalize(build_dir)

    local source =
        vim.fs.joinpath(
            build_dir,
            "compile_commands.json"
        )

    local target =
        vim.fs.joinpath(
            root,
            "compile_commands.json"
        )

    if not vim.uv.fs_stat(source) then
        vim.notify(
            "compile_commands.json bulunamadı:\n"
                .. source,
            vim.log.levels.ERROR,
            {
                title = "CMake",
            }
        )

        return false
    end

    -- Aktif profil değiştiğinde proje kökündeki compilation
    -- database bağlantısını yeni build dizinine yönlendir.
    local result = vim.system({
        "ln",
        "-sfn",
        source,
        target,
    }, {
        text = true,
    }):wait()

    if result.code ~= 0 then
        vim.notify(
            "compile_commands.json bağlantısı kurulamadı:\n"
                .. (result.stderr or "Bilinmeyen hata"),
            vim.log.levels.ERROR,
            {
                title = "CMake",
            }
        )

        return false
    end

    return true
end

local function restart_clangd()
    pcall(
        vim.cmd,
        "lsp restart clangd"
    )
end

local function preset_name()
    local preset =
        cmake.get_build_preset()

    if type(preset) == "string" then
        return preset
    end

    if type(preset) == "table" then
        return preset.name
            or preset.displayName
            or "Bilinmeyen"
    end

    return "Bilinmeyen"
end

-- ─────────────────────────────────────────────────────────────
-- Derleme Profili
-- ─────────────────────────────────────────────────────────────

local function select_profile()
    cmake.select_build_preset(function(result)
        if not result:is_ok() then
            return
        end

        -- Build preset seçildiğinde cmake-tools ilişkili
        -- configure preset'i de otomatik olarak seçer.
        cmake.generate(
            {
                bang = false,
                fargs = {},
            },
            function(generate_result)
                if not generate_result:is_ok() then
                    vim.notify(
                        "CMake yapılandırması başarısız.",
                        vim.log.levels.ERROR,
                        {
                            title = "CMake",
                        }
                    )

                    return
                end

                if not refresh_compile_commands() then
                    return
                end

                -- Yeni compilation database'i clangd yeniden okusun.
                restart_clangd()

                vim.notify(
                    "Aktif derleme profili: "
                        .. preset_name(),
                    vim.log.levels.INFO,
                    {
                        title = "CMake",
                    }
                )
            end
        )
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Configure
-- ─────────────────────────────────────────────────────────────

local function configure_project()
    if not save_all() then
        return
    end

    vim.cmd("CMakeGenerate")
end

-- ─────────────────────────────────────────────────────────────
-- Build
-- ─────────────────────────────────────────────────────────────

local function build_project()
    if not save_all() then
        return
    end

    vim.cmd("CMakeBuild")
end

-- ─────────────────────────────────────────────────────────────
-- Run
-- ─────────────────────────────────────────────────────────────

local function run_project()
    if not save_all() then
        return
    end

    vim.cmd("CMakeRun")
end

-- ─────────────────────────────────────────────────────────────
-- Kısayollar
-- ─────────────────────────────────────────────────────────────

local map = vim.keymap.set

-- Space+b
-- BuildSentry dashboard.
map(
    "n",
    "<leader>b",
    function()
        buildsentry.open()
    end,
    {
        desc = "Derleme merkezi",
    }
)

-- Space+c
-- GCC Debug / GCC Release / Clang Debug / Clang Release.
map(
    "n",
    "<leader>c",
    select_profile,
    {
        desc = "Derleme profili",
    }
)

-- F6
-- Kaydet + CMake Configure.
map(
    { "n", "i", "v" },
    "<F6>",
    configure_project,
    {
        desc = "CMake yapılandır",
    }
)

-- F7
-- Kaydet + Build.
map(
    { "n", "i", "v" },
    "<F7>",
    build_project,
    {
        desc = "Projeyi derle",
    }
)

-- Ctrl+F5
-- Kaydet + Run.
map(
    { "n", "i", "v" },
    "<C-F5>",
    run_project,
    {
        desc = "Derle ve çalıştır",
    }
)

-- Space+R
-- Ctrl+F5 terminal tarafından yakalanmazsa alternatif.
map(
    "n",
    "<leader>R",
    run_project,
    {
        desc = "Derle ve çalıştır",
    }
)
