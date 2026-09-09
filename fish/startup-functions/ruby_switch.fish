function ruby_switch --description "switch ruby in current shell via nixpkgs"
    if test (count $argv) -eq 0
        echo "Usage: ruby_switch <version>  (e.g. ruby_switch 3.3)"
        return 1
    end

    if not type -q nix
        echo "ruby_switch: nix not found (this function requires nix)" >&2
        return 1
    end

    set -l attr $argv[1]
    string match -q 'ruby*' $attr; or set attr ruby_(string replace -a . _ $attr)

    set -l outs (nix build --no-link --print-out-paths nixpkgs#$attr)
    if test $status -ne 0; or test -z "$outs[1]"
        echo "ruby_switch: you do not have version $argv[1] (nixpkgs#$attr not available)" >&2
        set -l sys (uname -m | string replace arm64 aarch64)-(string lower (uname -s))
        set -l avail (nix eval --raw nixpkgs#legacyPackages.$sys --apply 'p: builtins.concatStringsSep " " (builtins.filter (n: builtins.match "ruby(_[0-9]+_[0-9]+)?" n != null) (builtins.attrNames p))' 2>/dev/null)
        test -n "$avail"; and echo "ruby_switch: available: $avail" >&2
        return 1
    end

    # 前回の切り替え分(store の ruby と対応する gem bin)を PATH から掃除して重複を防ぐ
    set -l keep
    for p in $PATH
        if string match -q '/nix/store/*-ruby-*/bin' $p
            continue
        end
        if string match -q "$HOME/.local/share/gem/ruby/*/bin" $p
            continue
        end
        set -a keep $p
    end
    set -x PATH $outs[1]/bin $keep

    functions -q add_current_gem_path; and add_current_gem_path
    echo "switched to "(ruby --version)
end
