#!/usr/bin/env bash

set -e

COMMAND=$1

function rm_branchs() {
  echo "🔍 Getting current branch..."
  current_branch=$(git branch --show-current)

  echo "🗑️ Removing all branches except '$current_branch'..."
  deleted_branches=$(git branch | grep -v "\*" | tr -d ' ')

  if [[ -z "$deleted_branches" ]]; then
    echo "✅ No branches to delete."
    return
  fi

  # Delete and show each branch
  for branch in $deleted_branches; do
    git branch -D "$branch"
    echo "❌ Deleted branch: $branch"
  done

  echo "✅ Done. Current branch is still: $current_branch"
}

function help() {
  echo "Dotfiles script usage:"
  echo "  rm_branchs - Remove all branches except the current one"
}

case "$COMMAND" in
  rm_branchs) rm_branchs ;;
  help | *) help ;;
esac
