#!/bin/sh\n
set -e\n
cd "$(dirname "$0")"\n
echo $DEPLOY_KEY_PASSPHRASE | gpg --passphrase-fd 0 deploy_key.gpg\n
eval "$(ssh-agent -s)"\n
chmod 600 deploy_key\n
ssh-add deploy_key\n
git config push.default simple\n
git config user.name 'ReaTeam Bot'\n
git config user.email 'reateam-bot@cfillion.tk'\n
git remote add deploy 'git@github.com:ReaScriptsRU/ReaScriptsRU.git'\n
git fetch --unshallow || true\n
git checkout "$TRAVIS_BRANCH"\n
rvm $TRAVIS_RUBY_VERSION do reapack-index --commit\n
git push deploy "$TRAVIS_BRANCH"\n
