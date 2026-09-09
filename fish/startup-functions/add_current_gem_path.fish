function add_current_gem_path
    set -x PATH $HOME/.local/share/gem/ruby/(ruby -e "print Gem.ruby_api_version")/bin $PATH
end
