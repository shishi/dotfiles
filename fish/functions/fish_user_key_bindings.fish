function fish_user_key_bindings
  # from ghq_key_bindings.fish
  bind \cg '__ghq_repository_search'
  if bind -M insert >/dev/null 2>/dev/null
    bind -M insert \cg '__ghq_repository_search'
  end
end

fzf_key_bindings
