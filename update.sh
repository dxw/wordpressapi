#!/bin/sh

set -e

if [ ! -d wordpress ]; then
  git clone https://github.com/dxw/wordpress.git
fi

cd wordpress
git fetch -t
git checkout `git tag | tail -n1`
cd -

ruby update_codex.rb
ruby doxydoc.rb
