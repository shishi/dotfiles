Pry.config.editor = 'emacsclient -n --alternate-editor vim'

Pry.config.pager = false if ENV['INSIDE_EMACS']
Pry.config.correct_indent = false if ENV['INSIDE_EMACS']

if defined?(PryByebug)
  Pry.commands.alias_command 'c', 'continue'
  Pry.commands.alias_command 's', 'step'
  Pry.commands.alias_command 'n', 'next'
  Pry.commands.alias_command 'f', 'finish'
end
