# Toolchain source snapshot

These are the setup scripts used at C:/FF for this release, including exact
tool/dependency locks. To recreate the C:/FF layout, place this setup directory
at C:/FF/setup and this repository at C:/FF/development/foreverflip. Do not run
the registrar from this embedded snapshot: its parent must be the workspace
containing .tools, references and development.

Install-Toolchain.ps1 is syntax-checked; a fresh full network installation has
not been rerun over the user's working tools. Base Python and Git still depend
on Codex. Existing MCP registration and stdio verification passed locally.
CI installs its own pinned Lua tools and Python dependencies instead.
