from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import copier
import pytest
from copier import Settings

TEMPLATE_ROOT = Path(__file__).resolve().parents[1]
IOS = "ios"

# Hermetic git identity so tests never read (or depend on) the machine's git configuration.
GIT_TEST_ENV = {
    "GIT_AUTHOR_NAME": "Test User",
    "GIT_AUTHOR_EMAIL": "test@example.invalid",
    "GIT_COMMITTER_NAME": "Test User",
    "GIT_COMMITTER_EMAIL": "test@example.invalid",
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
}


def run_git(cwd: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-c", "commit.gpgsign=false", "-C", str(cwd), *args],
        capture_output=True, text=True, env={**os.environ, **GIT_TEST_ENV}, check=True,
    )  # fmt: skip
    return result.stdout


def snapshot_repo(destination: Path) -> Path:
    """Copy copier.yml and template/ (never .git, .venv or build products) into a new committed git repo.

    Tests render from a snapshot, so they do not depend on the real repository's commits, tags or uncommitted
    state. Xcode and SwiftPM build products inside the working tree are left out.
    """
    destination.mkdir(parents=True)
    shutil.copy2(TEMPLATE_ROOT / "copier.yml", destination / "copier.yml")
    shutil.copytree(
        TEMPLATE_ROOT / "template", destination / "template",
        ignore=shutil.ignore_patterns(".build", "DerivedData", "xcuserdata", ".swiftpm", "*.xcresult"),
    )  # fmt: skip
    run_git(destination, "init", "-q", "-b", "main")
    run_git(destination, "add", "-A")
    run_git(destination, "commit", "-q", "-m", "snapshot")
    return destination


def render(source: Path | str, destination: Path, *, ref: str | None = "HEAD", **answers: object):
    data = {"app_name": "sample-app", **answers}
    return copier.run_copy(
        str(source), destination, data=data, defaults=True, vcs_ref=ref,
        settings=Settings(), unsafe=False, quiet=True,
    )  # fmt: skip


@pytest.fixture(scope="session")
def template_repo(tmp_path_factory: pytest.TempPathFactory) -> Path:
    return snapshot_repo(tmp_path_factory.mktemp("snapshot") / "native-ios-template")


@pytest.fixture(scope="session")
def rendered(template_repo: Path, tmp_path_factory: pytest.TempPathFactory) -> Path:
    destination = tmp_path_factory.mktemp("rendered") / "project"
    destination.mkdir()
    render(template_repo, destination)
    return destination
