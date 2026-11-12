"""Extract the exact tagged release's changelog notes, with a legacy base-version fallback."""

import argparse
import pathlib
import re


def render(changelog: str, version: str, repository: str) -> str:
    sections = {}
    current = None
    for line in changelog.splitlines():
        heading = re.match(r'^## \[([^]]+)\]', line)
        if heading:
            current = heading.group(1)
            sections[current] = []
        elif current and not re.match(r'^\[[^]]+\]: ', line):
            sections[current].append(line)
    selected = version if version in sections else version.split('-', 1)[0]
    body = '\n'.join(sections.get(selected, [])).strip()
    if not body:
        raise ValueError(f'No changelog notes for {version}')
    warning = ''
    if '-' in version:
        warning = (
            '> [!WARNING]\n> Beta for testing. What to check in game:\n'
            f'> [the current checklist](https://github.com/{repository}/blob/v{version}/docs/testing.md#current-beta-checklist),\n'
            f'> how to report: [Beta testing](https://github.com/{repository}/blob/v{version}/docs/testing.md#beta-testing).\n\n'
        )
    return warning + body + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--repository', default='Danissemo/ForeverFlip')
    parser.add_argument('--changelog', type=pathlib.Path, default=pathlib.Path('CHANGELOG.md'))
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        notes = render(args.changelog.read_text(encoding='utf-8'), args.version, args.repository)
    except ValueError as error:
        parser.error(str(error))
    args.output.write_text(notes, encoding='utf-8')


if __name__ == '__main__':
    main()
