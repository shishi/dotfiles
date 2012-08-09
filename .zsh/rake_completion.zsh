function _rake_does_task_list_need_generating () {
  if [ ! -f .rake_tasks ]; then
    return 0;
  else
    accurate=$(stat -c%m .rake_tasks)
    changed=$(stat -c%m Rakefile)
    return $(expr $accurate '>=' $changed)
  fi
}

function _rake () {
  if [ -f Rakefile ]; then
    if _rake_does_task_list_need_generating; then
      echo "\nGenerating .rake_tasks..." > /dev/stderr
      rake --silent --tasks | cut -d " " -f 2 > .rake_tasks
    fi
    reply=( `cat .rake_tasks` )
  fi
}

compctl -K _rake rake