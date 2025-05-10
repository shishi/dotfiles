# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
function __fish_devenv_global_optspecs
	string join \n V/version v/verbose q/quiet log-format= j/max-jobs= u/cores= s/system= i/impure eval-cache no-eval-cache refresh-eval-cache offline c/clean= nix-debugger n/nix-option= o/override-input= O/option= h/help
end

function __fish_devenv_needs_command
	# Figure out if the current invocation already has a command.
	set -l cmd (commandline -opc)
	set -e cmd[1]
	argparse -s (__fish_devenv_global_optspecs) -- $cmd 2>/dev/null
	or return
	if set -q argv[1]
		# Also print the command, so this can be used to figure out what it is.
		echo $argv[1]
		return 1
	end
	return 0
end

function __fish_devenv_using_subcommand
	set -l cmd (__fish_devenv_needs_command)
	test -z "$cmd"
	and return 1
	contains -- $cmd[1] $argv
end

complete -c devenv -n "__fish_devenv_needs_command" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_needs_command" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_needs_command" -s u -l cores -d 'Maximum number CPU cores being used by a single build.' -r
complete -c devenv -n "__fish_devenv_needs_command" -s s -l system -r
complete -c devenv -n "__fish_devenv_needs_command" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_needs_command" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_needs_command" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_needs_command" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_needs_command" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_needs_command" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_needs_command" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_needs_command" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_needs_command" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_needs_command" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_needs_command" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_needs_command" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_needs_command" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_needs_command" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "init" -d 'Scaffold devenv.yaml, devenv.nix, .gitignore and .envrc.'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "generate" -d 'Generate devenv.yaml and devenv.nix using AI'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "shell" -d 'Activate the developer environment. https://devenv.sh/basics/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "update" -d 'Update devenv.lock from devenv.yaml inputs. http://devenv.sh/inputs/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "search" -d 'Search for packages and options in nixpkgs. https://devenv.sh/packages/#searching-for-a-file'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "info" -d 'Print information about this developer environment.'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "up" -d 'Start processes in the foreground. https://devenv.sh/processes/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "processes" -d 'Start or stop processes. https://devenv.sh/processes/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "tasks" -d 'Run tasks. https://devenv.sh/tasks/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "test" -d 'Run tests. http://devenv.sh/tests/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "container" -d 'Build, copy, or run a container. https://devenv.sh/containers/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "inputs" -d 'Add an input to devenv.yaml. https://devenv.sh/inputs/'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "repl" -d 'Launch an interactive environment for inspecting the devenv configuration.'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "gc" -d 'Delete previous shell generations. See https://devenv.sh/garbage-collection'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "build" -d 'Build any attribute in devenv.nix.'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "direnvrc" -d 'Print a direnvrc that adds devenv support to direnv. See https://devenv.sh/automatic-shell-activation.'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "version" -d 'Print the version of devenv.'
complete -c devenv -n "__fish_devenv_needs_command" -f -a "assemble"
complete -c devenv -n "__fish_devenv_needs_command" -f -a "print-dev-env"
complete -c devenv -n "__fish_devenv_needs_command" -f -a "generate-json-schema"
complete -c devenv -n "__fish_devenv_needs_command" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand init" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand init" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand init" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand init" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand init" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand init" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand init" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand init" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand init" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand init" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand init" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand init" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand init" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand init" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand init" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand init" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand init" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l host -r
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l exclude -d 'Paths to exclude during generation.' -r -F
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l disable-telemetry
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand generate" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand shell" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand update" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand update" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand update" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand update" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand update" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand update" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand update" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand update" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand update" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand update" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand update" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand update" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand update" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand update" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand update" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand update" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand update" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand search" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand search" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand search" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand search" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand search" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand search" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand search" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand search" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand search" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand search" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand search" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand search" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand search" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand search" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand search" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand search" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand search" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand info" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand info" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand info" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand info" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand info" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand info" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand info" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand info" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand info" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand info" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand info" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand info" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand info" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand info" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand info" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand info" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand info" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand up" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand up" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand up" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand up" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand up" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand up" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand up" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand up" -s d -l detach -d 'Start processes in the background.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand up" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand up" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand up" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -f -a "up" -d 'Start processes in the foreground.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -f -a "down" -d 'Stop processes running in the background.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and not __fish_seen_subcommand_from up down help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s d -l detach -d 'Start processes in the background.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from up" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from down" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from help" -f -a "up" -d 'Start processes in the foreground.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from help" -f -a "down" -d 'Stop processes running in the background.'
complete -c devenv -n "__fish_devenv_using_subcommand processes; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -f -a "run" -d 'Run tasks.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and not __fish_seen_subcommand_from run help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from run" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from help" -f -a "run" -d 'Run tasks.'
complete -c devenv -n "__fish_devenv_using_subcommand tasks; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand test" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand test" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand test" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand test" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand test" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand test" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand test" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand test" -s d -l dont-override-dotfile -d 'Don\'t override .devenv to a temporary directory.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand test" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand test" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand test" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s r -l registry -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l copy-args -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l copy
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l docker-run
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -a "build" -d 'Build a container.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -a "copy" -d 'Copy a container to registry.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -a "run" -d 'Run a container.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and not __fish_seen_subcommand_from build copy run help" -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from build" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from copy" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from run" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from help" -f -a "build" -d 'Build a container.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from help" -f -a "copy" -d 'Copy a container to registry.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from help" -f -a "run" -d 'Run a container.'
complete -c devenv -n "__fish_devenv_using_subcommand container; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -f -a "add" -d 'Add an input to devenv.yaml.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and not __fish_seen_subcommand_from add help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s f -l follows -d 'What inputs should follow your inputs?' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from add" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from help" -f -a "add" -d 'Add an input to devenv.yaml.'
complete -c devenv -n "__fish_devenv_using_subcommand inputs; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand repl" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand gc" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand build" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand build" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand build" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand build" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand build" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand build" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand build" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand build" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand build" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand build" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand build" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand build" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand build" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand build" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand build" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand build" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand build" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand direnvrc" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand version" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand version" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand version" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand version" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand version" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand version" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand version" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand version" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand version" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand version" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand version" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand version" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand version" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand version" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand version" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand version" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand version" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand assemble" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -l json
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand print-dev-env" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -l log-format -d 'Configure the output format of the logs.' -r -f -a "cli\t'The default human-readable log format used in the CLI'
tracing-full\t'A verbose structured log format used for debugging'
tracing-pretty\t'A pretty human-readable log format used for debugging'"
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s j -l max-jobs -d 'Maximum number of Nix builds at any time.' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s s -l system -r
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s c -l clean -d 'Ignore existing environment variables when entering the shell. Pass a list of comma-separated environment variables to let through.' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s n -l nix-option -d 'Pass additional options to nix commands' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s o -l override-input -d 'Override inputs in devenv.yaml' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s O -l option -d 'Override configuration options with typed values' -r
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s V -l version -d 'Print version information'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s v -l verbose -d 'Enable additional debug logs.'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s q -l quiet -d 'Silence all logs'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s i -l impure -d 'Relax the hermeticity of the environment.'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -l eval-cache -d 'Cache the results of Nix evaluation.'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -l no-eval-cache -d 'Disable caching of Nix evaluation results.'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -l refresh-eval-cache -d 'Force a refresh of the Nix evaluation cache.'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -l offline -d 'Disable substituters and consider all previously downloaded files up-to-date.'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -l nix-debugger -d 'Enter the Nix debugger on failure.'
complete -c devenv -n "__fish_devenv_using_subcommand generate-json-schema" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "init" -d 'Scaffold devenv.yaml, devenv.nix, .gitignore and .envrc.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "generate" -d 'Generate devenv.yaml and devenv.nix using AI'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "shell" -d 'Activate the developer environment. https://devenv.sh/basics/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "update" -d 'Update devenv.lock from devenv.yaml inputs. http://devenv.sh/inputs/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "search" -d 'Search for packages and options in nixpkgs. https://devenv.sh/packages/#searching-for-a-file'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "info" -d 'Print information about this developer environment.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "up" -d 'Start processes in the foreground. https://devenv.sh/processes/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "processes" -d 'Start or stop processes. https://devenv.sh/processes/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "tasks" -d 'Run tasks. https://devenv.sh/tasks/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "test" -d 'Run tests. http://devenv.sh/tests/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "container" -d 'Build, copy, or run a container. https://devenv.sh/containers/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "inputs" -d 'Add an input to devenv.yaml. https://devenv.sh/inputs/'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "repl" -d 'Launch an interactive environment for inspecting the devenv configuration.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "gc" -d 'Delete previous shell generations. See https://devenv.sh/garbage-collection'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "build" -d 'Build any attribute in devenv.nix.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "direnvrc" -d 'Print a direnvrc that adds devenv support to direnv. See https://devenv.sh/automatic-shell-activation.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "version" -d 'Print the version of devenv.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "assemble"
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "print-dev-env"
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "generate-json-schema"
complete -c devenv -n "__fish_devenv_using_subcommand help; and not __fish_seen_subcommand_from init generate shell update search info up processes tasks test container inputs repl gc build direnvrc version assemble print-dev-env generate-json-schema help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c devenv -n "__fish_devenv_using_subcommand help; and __fish_seen_subcommand_from processes" -f -a "up" -d 'Start processes in the foreground.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and __fish_seen_subcommand_from processes" -f -a "down" -d 'Stop processes running in the background.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and __fish_seen_subcommand_from tasks" -f -a "run" -d 'Run tasks.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and __fish_seen_subcommand_from container" -f -a "build" -d 'Build a container.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and __fish_seen_subcommand_from container" -f -a "copy" -d 'Copy a container to registry.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and __fish_seen_subcommand_from container" -f -a "run" -d 'Run a container.'
complete -c devenv -n "__fish_devenv_using_subcommand help; and __fish_seen_subcommand_from inputs" -f -a "add" -d 'Add an input to devenv.yaml.'
