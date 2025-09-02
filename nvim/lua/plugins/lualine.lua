return {
  "nvim-lualine/lualine.nvim",
  config = function()
    require("lualine").setup({
      options = {
        theme = "melange",
        icons_enabled = true,
        component_separators = { left = '', right = ''},
        section_separators = { left = '', right = ''},
     },
    })
  end,
  dependencies = { "nvim-tree/nvim-web-devicons" },
}
