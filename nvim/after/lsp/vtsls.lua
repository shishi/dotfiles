---@type vim.lsp.Config
return {
  init_options = {
    plugins = {
      {
        name = '@vue/typescript-plugin',
        location = '/usr/local/lib/node_modules/@vue/typescript-plugin',
        languages = { 'javascript', 'typescript', 'vue' },
      },
    },
  },
  filetypes = {
    'javascript',
    'javascriptreact',
    'javascript.jsx',
    'typescript',
    'typescriptreact',
    'typescript.tsx',
    'vue',
  },
}
