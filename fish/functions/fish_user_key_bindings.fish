function fish_user_key_bindings
    # retain the default key bindings
    # for mode in default insert visual
    #     fish_default_key_bindings -M $mode
    # end
    # fish_vi_key_bindings --no-erase

    fish_vi_key_bindings

    # use jj to escape from insert mode
    # if test "$__fish_active_key_bindings" = fish_vi_key_bindings
    #     bind -M insert -m default jj force-repaint
    # end

    # from ghq_key_bindings.fish
    bind \cg ghq_repository_search
    if bind -M insert >/dev/null 2>&1
        bind -M insert \cg ghq_repository_search
    end
end

fzf_key_bindings
