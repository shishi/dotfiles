function __dotfiles_reload_config --on-event fish_prompt
    set -l config_dir (path dirname $__dotfiles_fish_config_path)
    set -l files $__dotfiles_fish_config_path $config_dir/startup-functions/*.fish $config_dir/functions/__dotfiles_reload_config.fish
    # Compare content so multiple saves within the same second are detected.
    set -l checksums (command cksum -- $files)
    or return
    set -l fingerprint (string join \n -- $checksums)

    if test "$argv[1]" = --remember
        set -g __dotfiles_fish_config_fingerprint "$fingerprint"
        return
    end
    test "$fingerprint" = "$__dotfiles_fish_config_fingerprint"; and return

    # Remember failed attempts too, avoiding the same error on every prompt.
    set -g __dotfiles_fish_config_fingerprint "$fingerprint"
    set -l fish_binary (status fish-path)
    for file in $files
        command $fish_binary --no-config --no-execute "$file"
        or return
    end
    source $__dotfiles_fish_config_path
end
