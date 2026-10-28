- `gh` in Bash goes through a broker; reads run at once, the three writes below
  open a dialog on the user's screen and run only if they click Allow. The
  session has no GitHub login. Use it when a skill or the user asks for `gh`
  output, or to shape JSON with `--jq`. Only these forms work:
  - `gh pr list [--state open|closed|merged|all] [--author A] [--search Q] [--limit N]`
  - `gh pr view N [--comments] [--json f1,f2] [--jq EXPR]`
  - `gh pr diff N|BRANCH [--name-only]`
  - `gh pr checks N [--json f1,f2] [--jq EXPR]`
  - `gh issue list [--state S] [--search Q] [--limit N]`, `gh issue view N`
  - `gh run list [--branch B] [--limit N]`, `gh run view ID [--log-failed]`
  - `gh api repos/{owner}/{repo}/pulls/N/comments` (inline review comments)
  - Another repo: add `-R owner/name`, or pass a PR or issue URL. Only this repo
    and the user's listed repos work.
  - Writes (the user approves each in a dialog; wait for the result, never retry
    a denial): `gh pr comment N --body TEXT`, `gh issue comment N --body TEXT`,
    `gh pr create --title T --body TEXT --head BRANCH [--base BRANCH] [--draft]`
- `gh` refuses everything else: merge, review, checkout, auth, api with a method
  or body, `--body-file`, `--hostname`.
- Shortcut: `short` in Bash runs the user's Shortcut CLI through a broker; the
  session has no token. Only these forms work:
  - Find: `short search WORDS` (`short find` is the same), e.g.
    `short search owner:me state:"In Progress"`; filters
    `-o OWNER -s STATE -l LABEL -t TEXT -e N -y TYPE`, output `-f FORMAT`, `-q`
  - Read: `short story ID`, `short epics`, `short epic view ID`,
    `short epic stories ID`, `short iterations [-C]`, `short iteration view ID`,
    `short iteration stories ID`, `short labels`, `short label stories ID`,
    `short label epics ID`, `short teams`, `short team view ID`,
    `short team stories ID`, `short members [-s NAME]`, `short workflows`,
    `short docs`, `short doc view ID`
  - Change, only when the user asked (it writes to Shortcut):
    `short story ID -c "comment" -s STATE -e N -o OWNER -l LABEL`,
    `short story ID --task "text"`, `short story ID --task-complete "text"`,
    `short create -t TITLE [-d TEXT] [-s STATE] [-o OWNER] [-l LABEL]`
- `short` refuses install, api, workspace, deletes, `--open`, `--git-branch`,
  `--from-git`, `--download` and `search --save`.
- A refusal that lists what is allowed (fields, qualifiers, flags, commands):
  retry once with an allowed form that does the same job. If none does, or the
  error says "read-only", "not on this machine's gh-repos list" or "broker is
  not running", stop and tell the user. Never work around it with curl, git
  remotes or tokens.
