#!/bin/bash
set -e

REPO_URL="git@github.com:2xa-team/vpn-tgbot.git"
REPO_DIR="vpn-tgbot"
BRANCH="main"
FILES="docker-compose.prod.yaml
example.env"

mkdir "$REPO_DIR"
cd "$REPO_DIR"

git init
git remote add origin "$REPO_URL"
git config core.sparseCheckout true

echo "$FILES" > .git/info/sparse-checkout

git fetch origin "$BRANCH"
git checkout "$BRANCH"

echo "✅ Files $FILES uploaded in $(pwd)"
