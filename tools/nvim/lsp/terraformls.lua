return {
  filetypes = { 'terraform', 'hcl' },
  settings = {
    terraform = {
      experimentalFeatures = {
        validateOnSave = true,
      },
    },
  },
}
