return {
  "nvim-telescope/telescope.nvim",
  branch = "0.1.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- pretty icons (optional):
    -- "nvim-tree/nvim-web-devicons",
  },
  cmd = "Telescope",
  keys = {
    { "<leader>tf", function() require("telescope.builtin").find_files() end, desc = "Find files" },
    { "<leader>tg", function() require("telescope.builtin").live_grep() end,  desc = "Live grep"  },
    { "<leader>tb", function() require("telescope.builtin").buffers() end,    desc = "Buffers"    },
    { "<leader>th", function() require("telescope.builtin").help_tags() end,  desc = "Help"       },
  },
  config = function()
    require("telescope").setup({
      defaults = {
        mappings = {
          i = {
            ["<C-u>"] = false,
            ["<C-d>"] = false,
          },
        },
      },
    })
  end,
}
