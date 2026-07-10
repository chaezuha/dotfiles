return {
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "clang-format",
        "black",
        "prettier",
        "shfmt",
        "google-java-format",
        "stylua",
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        c = { "clang-format" },
        cpp = { "clang-format" },
        python = { "black" },
        lua = { "stylua" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        markdown = { "prettier" },
        html = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        rust = { "rustfmt" },
        java = { "google-java-format" },
        sh = { "shfmt" },
      },
    },
  },
}
