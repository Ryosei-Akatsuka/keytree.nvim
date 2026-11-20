-- keytree.nvim entry point.
--
-- This file only registers the command; the implementation lives under
-- lua/keytree/ and is loaded on first use.

if vim.g.loaded_keytree then
  return
end
vim.g.loaded_keytree = 1

vim.api.nvim_create_user_command("KeymapTree", function()
  require("keytree").show()
end, {
  desc = "Show all keymaps as a tree",
})
