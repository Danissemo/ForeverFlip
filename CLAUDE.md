@../CLAUDE.md

The build is run from `C:\FF`; everything the assistant needs is in the file above. The git hooks
(`.githooks`) are on: a commit runs StyLua, `pyflakes` and the whole suite, then installs the addon
into the game and pushes `main`.
