function fish_user_key_bindings
    ### ghq ###
    bind \cg '__ghq_cd_repository'
    if bind -M insert >/dev/null ^/dev/null
          bind -M insert \cg '__ghq_cd_repository'
    end
    # bind \cs 'ghq_fzf'
    # bind \es 'ghq_fzf_godoc'
    ### ghq ###
end

fzf_key_bindings
