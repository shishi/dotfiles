function docker_run_with_current_user_and_dir
    docker run -it --rm -v /etc/group:/etc/group:ro -v /etc/passwd:/etc/passwd:ro -u (id -u $USER):(id -g $USER) -v (pwd):/src -w /src -e HOME=/src $argv
end
