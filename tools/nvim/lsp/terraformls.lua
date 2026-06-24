return {
  filetypes = { 'terraform', 'hcl', 'tf' },
  settings = {
    terraform = {
      experimentalFeatures = {
        validateOnSave = true,
      },
    },
  },
}
