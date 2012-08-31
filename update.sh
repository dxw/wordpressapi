#!/bin/sh

set -e

if test ${RUBY}X = X; then
  RUBY=ruby
fi

if [ ! -d wordpress ]; then
  git clone https://github.com/dxw/wordpress.git
fi

cd wordpress
git fetch -t
git checkout `git tag | tail -n1`
cd -

${RUBY} update_codex.rb
${RUBY} doxydoc.rb
