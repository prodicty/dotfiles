return {
  ---@diagnostic disable: undefined-field
  "mfussenegger/nvim-jdtls",
  ft = "java",
  config = function()
    local jdtls = require("jdtls")
    local jdtls_setup = require("jdtls.setup")

    local function find_java_runtime()
      local java_home = os.getenv("JAVA_HOME")
      if java_home then
        return java_home
      end
      local java_exec = vim.fn.resolve(vim.fn.exepath("java"))
      if java_exec ~= "" then
        return vim.fn.fnamemodify(java_exec, ":h:h")
      end
      vim.notify("jdtls: could not detect Java runtime. Set JAVA_HOME.", vim.log.levels.WARN)
      return nil
    end

    -- Derive the jdtls runtime name dynamically
    local function get_java_se_name(java_home)
      local java_exec = java_home and (java_home .. "/bin/java") or vim.fn.exepath("java")
      local handle = io.popen(java_exec .. " -version 2>&1")
      if not handle then
        return "JavaSE-25"
      end
      local output = handle:read("*a")
      handle:close()

      local version_str = output:match('"([%d%.]+)"')
      if not version_str then
        return "JavaSE-25"
      end

      local major = tonumber(version_str:match("^(%d+)"))
      if not major then
        return "JavaSE-25"
      end

      if major == 1 then
        -- Legacy format: 1.8.x → JavaSE-1.8
        local minor = tonumber(version_str:match("^%d+%.(%d+)"))
        return minor and ("JavaSE-1." .. minor) or "JavaSE-1.8"
      else
        return "JavaSE-" .. major
      end
    end

    local function get_os_config()
      if vim.fn.has("mac") == 1 then
        return "mac"
      end
      if vim.fn.has("win32") == 1 then
        return "win"
      end
      return "linux"
    end

    local function get_config()
      local mason_path = vim.fn.stdpath("data") .. "/mason"
      local jdtls_path = mason_path .. "/packages/jdtls"
      local equinox_path = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar")
      local config_path = jdtls_path .. "/config_" .. get_os_config()
      local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
      local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. project_name

      local java_debug_path = mason_path .. "/packages/java-debug-adapter"
      local java_debug_bundle = vim.split(
        vim.fn.glob(java_debug_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar"),
        "\n",
        { trimempty = true }
      )

      local java_test_path = mason_path .. "/packages/java-test"
      local java_test_bundle =
        vim.split(vim.fn.glob(java_test_path .. "/extension/server/*.jar"), "\n", { trimempty = true })

      local bundles = {}
      vim.list_extend(bundles, java_debug_bundle)
      vim.list_extend(bundles, java_test_bundle)

      -- Resolve once per config build
      local java_home = find_java_runtime()
      local java_se_name = get_java_se_name(java_home)

      return {
        cmd = {
          vim.fn.exepath("java"),
          "-Declipse.application=org.eclipse.jdt.ls.core.id1",
          "-Dosgi.bundles.defaultStartLevel=4",
          "-Declipse.product=org.eclipse.jdt.ls.core.product",
          "-Dlog.protocol=true",
          "-Dlog.level=ALL",
          "-Xmx2g",
          "--add-modules=ALL-SYSTEM",
          "--add-opens",
          "java.base/java.util=ALL-UNNAMED",
          "--add-opens",
          "java.base/java.lang=ALL-UNNAMED",
          "-jar",
          equinox_path,
          "-configuration",
          config_path,
          "-data",
          workspace_dir,
        },

        root_dir = jdtls_setup.find_root({
          ".git",
          "mvnw",
          "gradlew",
          "pom.xml",
          "build.gradle",
          "build.gradle.kts",
        }),

        capabilities = require("blink.cmp").get_lsp_capabilities(),

        init_options = {
          bundles = bundles,
          extendedClientCapabilities = jdtls.extendedClientCapabilities,
        },

        settings = {
          java = {
            format = {
              enabled = true,
              settings = {
                url = vim.fn.stdpath("config") .. "/format/eclipse-formatter.xml",
                profile = "Custom-4Spaces",
              },
            },
            saveActions = { organizeImports = true },
            eclipse = { downloadSources = true },
            maven = { downloadSources = true },
            gradle = { enabled = true },
            inlayHints = { parameterNames = { enabled = "all" } },
            completion = {
              favoriteStaticMembers = {
                "org.junit.jupiter.api.Assertions.*",
                "org.mockito.Mockito.*",
                "org.mockito.ArgumentMatchers.*",
              },
              importOrder = { "com", "java", "javax", "io", "org" },
            },
            sources = {
              organizeImports = {
                starThreshold = 9999,
                staticStarThreshold = 9999,
              },
            },
            configuration = {
              runtimes = {
                {
                  name = java_se_name,
                  path = java_home,
                  default = true,
                },
              },
            },
          },
        },

        on_attach = function(_, bufnr)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "Java: " .. desc })
          end

          map("<leader>ji", jdtls.organize_imports, "Organize imports")
          map("<leader>jev", jdtls.extract_variable, "Extract variable")
          map("<leader>jec", jdtls.extract_constant, "Extract constant")
          map("<leader>ju", jdtls.update_project_config, "Update project config")
          map("<leader>jt", jdtls.goto_subjects, "Go to test/impl")

          map("<leader>jb", function()
            jdtls.compile("incremental")
          end, "Build incremental")
          map("<leader>jB", function()
            jdtls.compile("full")
          end, "Build full")

          vim.keymap.set({ "n", "v" }, "<leader>jem", function()
            jdtls.extract_method(true)
          end, { buffer = bufnr, desc = "Java: Extract method" })

          vim.keymap.set(
            { "n", "v" },
            "<leader><CR>",
            jdtls.code_action,
            { buffer = bufnr, desc = "Java: Code action" }
          )

          jdtls.setup_dap({ hotcodereplace = "auto" })
          jdtls.setup_dap_main_class_configs()
        end,
      }
    end

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "java",
      callback = function()
        jdtls.start_or_attach(get_config())
      end,
    })
  end,
}
