# Keep Codex in-process so every launch inherits its caller's environment.
function codex --wraps codex
    command codex -c 'shell_environment_policy.inherit="all"' $argv
end
