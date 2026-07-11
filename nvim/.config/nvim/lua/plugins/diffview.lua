return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview" },
    { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>", desc = "File history (Diffview)" },
  },
  opts = {},
}
