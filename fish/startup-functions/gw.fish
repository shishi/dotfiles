function gw -d "Pick a git worktree with fzf and cd into it"
    # git-wt の表形式は列区切りが空白なので、連続空白を含むパスを復元できない。
    # --json なら空白で壊れない (改行を含むパスは git-wt 側が切り詰めるため非対応)
    # @tsv はパス中の \ やタブをエスケープしてしまうので生の連結で組み立て、
    # 分割回数を 2 に制限してパス側のタブを保つ
    set -l line (git-wt --json \
        | jq -r '.[] | (if .current then "*" else " " end) + "\t" + (.branch // "(detached)") + "\t" + .path' \
        | fzf --delimiter \t)
    test -n "$line"; or return
    set -l dir (string split -m2 -f3 \t -- $line)
    if test -d "$dir"
        cd $dir
    else
        echo "gw: not a directory: $dir" >&2
        return 1
    end
end
