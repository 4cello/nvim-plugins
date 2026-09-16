return {
  filetypes = { "nix" },
  containers = {
    binding_set = {
      entries = { "binding" },
      key = "attrpath",
    },
    list_expression = {
      -- Lists may contain any expression node type.
      entries = true,
    },
  },
}
