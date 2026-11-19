"""Every `devkit` command the template's documentation shows exists in the platform CLI, with options it accepts.

The generated `ios/README.md` once told people to run a devkit subcommand that does not exist. The command line
below is the one of developer-platform v0.8.0 (`devkit COMMAND --help`); devkit is not a dependency of this
repository, so it is written down here and must be updated together with a devkit release that changes it.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from conftest import TEMPLATE_ROOT

GLOBAL = {"--help", "-h", "--version"}
DEVKIT_OPTIONS: dict[str, set[str]] = {
    "doctor": set(),
    "new": {"--description", "--output-dir", "--profile", "--set", "--template", "--template-ref", "--native-template",
            "--native-template-ref", "--native-set", "--dry-run"},
    "upgrade": {"--to", "--set", "--profile", "--layer", "--dry-run"},
    "status": set(),
    "native add": {"--native-template", "--native-template-ref", "--native-set", "--dry-run"},
}  # fmt: skip
CHOICES = {"--layer": {"auto", "web", "native"}, "--profile": {"web-core", "full-stack", "native-ios"}}

# `devkit` followed by its arguments, up to the end of the command (end of line, a backtick, a comment, a bracket or prose).
INVOCATION = re.compile(r"\bdevkit\s+([a-z][a-z-]*)((?:\s+(?!#)[^\s`)|;,]+)*)")


def invocations(text: str) -> list[tuple[str, list[str]]]:
    found = []
    for match in INVOCATION.finditer(text):
        command, rest = match.group(1), match.group(2).split()
        if command == "native":
            command = "native " + (rest.pop(0) if rest else "")
        found.append((command, rest))
    return found


def problems(text: str) -> list[str]:
    bad = []
    for command, args in invocations(text):
        if command not in DEVKIT_OPTIONS:
            bad.append(f"devkit {command}: no such command")
            continue
        for i, arg in enumerate(args):
            if not arg.startswith("-"):
                continue
            name, _, value = arg.partition("=")
            if name not in DEVKIT_OPTIONS[command] | GLOBAL:
                bad.append(f"devkit {command}: no option {name}")
            choice = value or (args[i + 1] if i + 1 < len(args) else "")
            if name in CHOICES and re.fullmatch(r"[a-z-]+", choice) and choice not in CHOICES[name] and "|" not in choice:
                bad.append(f"devkit {command} {name}: not a choice: {choice}")
    return bad


def documentation(rendered: Path) -> dict[str, str]:
    """Everything a person or an agent reads: the rendered layer's docs and scripts, and this repository's docs."""
    docs = {}
    for path in [*sorted((rendered / "ios").rglob("*.md")), *sorted((rendered / "ios/scripts").iterdir())]:
        if ".build" not in path.parts and ".derived-data" not in path.parts and path.is_file():
            docs[str(path.relative_to(rendered))] = path.read_text()
    for path in [TEMPLATE_ROOT / "README.md", TEMPLATE_ROOT / "AGENTS.md", *sorted((TEMPLATE_ROOT / "docs").glob("*.md"))]:
        docs[str(path.relative_to(TEMPLATE_ROOT))] = path.read_text()
    return docs


def test_every_devkit_command_in_the_documentation_exists(rendered: Path) -> None:
    docs = documentation(rendered)
    assert sum(len(invocations(text)) for text in docs.values()) >= 5  # the README does document the CLI
    found = {name: problems(text) for name, text in docs.items()}
    assert {name: bad for name, bad in found.items() if bad} == {}


def test_no_document_mentions_the_nonexistent_upgrade_native_command(rendered: Path) -> None:
    for name, text in documentation(rendered).items():
        assert "upgrade-native" not in text, name


def test_the_generated_readme_documents_the_layered_upgrade(rendered: Path) -> None:
    readme = (rendered / "ios/README.md").read_text()
    for phrase in ("devkit status PROJECT", "devkit upgrade PROJECT --layer native", "devkit upgrade PROJECT --layer web",
                   "--answers-file .copier-answers.ios.yml", "clean git working tree"):  # fmt: skip
        assert phrase in readme, phrase


@pytest.mark.parametrize(
    "text",
    ["run `devkit upgrade-native`", "`devkit new app --database postgres`", "`devkit upgrade . --layer ios`",
     "`devkit native remove .`", "`devkit status . --layer web`"],
)  # fmt: skip
def test_the_checker_rejects_what_does_not_exist(text: str) -> None:
    assert problems(text)


@pytest.mark.parametrize(
    "text",
    ["`devkit upgrade PROJECT --layer native --dry-run`", "`devkit new NAME --profile native-ios --set database=postgres`",
     "`devkit native add PROJECT`", "devkit status PROJECT   # both layers", "`devkit upgrade PROJECT --layer web|native`"],
)  # fmt: skip
def test_the_checker_accepts_real_commands(text: str) -> None:
    assert problems(text) == []
