# gh-worktree

A `gh` CLI extension for managing git worktrees with GitHub context.

Work on multiple branches simultaneously — each in its own directory — without stashing or switching.

## Installation

```sh
gh extension install liux4989/gh-worktreex
```

Or, to install from a local clone:

```sh
gh extension install .
```

## Commands

| Command | Description |
|---------|-------------|
| `gh worktree list` | List all active worktrees |
| `gh worktree add <branch>` | Create a worktree for a branch (creates branch if absent) |
| `gh worktree pr <number>` | Check out a GitHub PR in its own worktree |
| `gh worktree rm <path\|branch>` | Remove a worktree (optionally deletes the branch) |
| `gh worktree clean` | Remove worktrees for merged/deleted branches |
| `cd $(gh worktree cd <branch\|pr>)` | Navigate to a worktree directory |

## Usage

### List worktrees

```sh
gh worktree list
```

```
Worktrees:
  /home/user/myrepo                          a1b2c3d  main
  /home/user/myrepo-feature-login            d4e5f6a  feature/login
  /home/user/myrepo-pr-42                    7b8c9d0  pr/42
```

### Create a worktree for a branch

```sh
gh worktree add feature/my-thing
```

Creates the branch if it does not already exist, then places the worktree at `../myrepo-feature-my-thing`.

### Review a Pull Request in isolation

```sh
gh worktree pr 42
```

Fetches PR #42's branch, creates a worktree at `../myrepo-pr-42`, and prints the path.

### Navigate to a worktree

```sh
cd $(gh worktree cd feature/my-thing)
cd $(gh worktree cd 42)   # by PR number
```

### Remove a worktree

```sh
gh worktree rm feature/my-thing   # by branch name
gh worktree rm ../myrepo-pr-42    # by path
```

Prompts whether to also delete the local branch.

### Clean up merged branches

```sh
gh worktree clean
```

Prunes stale metadata, then interactively removes worktrees for branches already merged into `HEAD`.

## How worktrees are named

Worktrees are placed **one level above** the repository root, named:

```
<repo-name>-<branch-with-slashes-as-dashes>
<repo-name>-pr-<number>
```

Example — repo `myapp`, branch `feature/auth`:

```
~/projects/myapp/           ← main worktree
~/projects/myapp-feature-auth/  ← worktree for feature/auth
~/projects/myapp-pr-99/     ← worktree for PR #99
```

## Requirements

- `git` 2.5+
- [`gh`](https://cli.github.com) CLI (only for `pr` command)
- bash 4+

## License

MIT
