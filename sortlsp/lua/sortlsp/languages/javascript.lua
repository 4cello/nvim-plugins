return {
  filetypes = { "javascript", "typescript", "typescriptreact" },
  containers = {
    object = {
      entries = { "pair", "property", "property_definition", "field_definition" },
      key = "key",
      separator = ",",
    },
    array = {
      -- Arrays may contain any expression node type.
      entries = true,
      separator = ",",
    },
  },
}
