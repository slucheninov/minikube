#!/usr/bin/env zsh

emulate -L zsh
setopt sh_word_split

export COLUMNS=1
list="first second third"
select var in $list; do
  if [ x"$var" != x"" ]; then
    echo $var
  return
  fi
done