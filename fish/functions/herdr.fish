# Keep the tracked Herdr plugin lock in sync after successful mutations.
function herdr --wraps herdr
    command herdr $argv
    set -l herdr_status $status

    if test $herdr_status -eq 0; and test (count $argv) -ge 2; and test "$argv[1]" = plugin; and contains -- "$argv[2]" install uninstall
        bash ~/.agent-shared/bin/herdr-plugins.sh record
        return $status
    end

    return $herdr_status
end
