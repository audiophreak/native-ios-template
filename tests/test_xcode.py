"""What needs Xcode: the generated client is reproducible, the package passes, the app builds for the simulator,
the Release build requires https, and the release check leaves a committed project's tree clean. Skipped without
Xcode; CI runs them on a macOS runner. No signing is involved."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import copier
import pytest
from copier import Settings
from copier.errors import UserMessageError

from conftest import render, run_git

pytestmark = [pytest.mark.xcode, pytest.mark.skipif(shutil.which("xcodebuild") is None, reason="needs Xcode")]


def sh(args: list[str], cwd: Path, timeout: int = 1800) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False)


@pytest.fixture(scope="module")
def ios(rendered: Path) -> Path:
    return rendered / "ios"


def test_the_committed_client_is_exactly_what_the_pinned_generator_produces(ios: Path) -> None:
    result = sh(["sh", "scripts/check-generated.sh"], ios)
    assert result.returncode == 0, (result.stdout + result.stderr)[-3000:]


def test_the_contract_check_follows_the_web_projects_contract(ios: Path) -> None:
    assert sh(["sh", "scripts/check-contract.sh"], ios).returncode == 0  # no ../openapi next to the test project: checksum only
    web = ios.parent / "openapi"
    web.mkdir()
    shutil.copy2(ios / "Contract/openapi.json", web / "openapi.json")
    assert sh(["sh", "scripts/check-contract.sh"], ios).returncode == 0
    (web / "openapi.json").write_text((web / "openapi.json").read_text().replace('"1.0.0"', '"1.1.0"', 1))
    stale = sh(["sh", "scripts/check-contract.sh"], ios)
    assert stale.returncode == 1 and "sync-contract" in stale.stderr


def test_the_package_tests_pass(ios: Path) -> None:
    result = sh(["swift", "test"], ios / "Packages/AppCore")
    assert result.returncode == 0, (result.stdout + result.stderr)[-4000:]
    assert "Test run with" in result.stdout + result.stderr and "failed" not in (result.stdout + result.stderr).split("Test run with")[-1].splitlines()[0]


def test_the_app_builds_for_the_simulator_without_signing_and_resolution_uses_the_committed_pins(ios: Path) -> None:
    sim = sh(["sh", "scripts/simulator.sh"], ios)
    assert sim.returncode == 0, sim.stderr
    result = sh(["xcodebuild", "build", "-project", "App.xcodeproj", "-scheme", "App", "-destination", f"id={sim.stdout.strip()}", "-derivedDataPath", ".derived-data/build", "-onlyUsePackageVersionsFromResolvedFile"], ios)
    assert result.returncode == 0, (result.stdout + result.stderr)[-4000:]
    assert (ios / ".derived-data/build/Build/Products/Debug-iphonesimulator/App.app").is_dir()



def test_the_release_build_requires_https_and_has_no_transport_security_exception(ios: Path) -> None:
    result = sh(["sh", "scripts/check-release-config.sh"], ios)
    assert result.returncode == 0, (result.stdout + result.stderr)[-3000:]
    assert "https://api.example.com" in result.stdout and "no App Transport Security exception" in result.stdout


def committed_project(template_repo: Path, tmp_path: Path) -> Path:
    """A freshly generated layer, committed, as a person has it right after `devkit new` and `git commit`."""
    project = tmp_path / "project"
    project.mkdir()
    render(template_repo, project)
    run_git(project, "init", "-q", "-b", "main")
    run_git(project, "add", "-A")
    run_git(project, "commit", "-q", "-m", "generated")
    return project


def git_visible_changes(project: Path) -> str:
    return run_git(project, "status", "--porcelain", "--untracked-files=all")  # exactly what devkit upgrade refuses on


def update_preview(project: Path) -> None:
    """Copier's own update of this layer (what devkit upgrade --layer native runs); it refuses a dirty tree first."""
    copier.run_update(project, answers_file=Path(".copier-answers.ios.yml"), vcs_ref="HEAD", defaults=True, overwrite=True,
                      skip_answered=True, settings=Settings(), unsafe=False, quiet=True, pretend=True)  # fmt: skip


def test_the_release_check_leaves_a_committed_project_clean_so_an_upgrade_is_not_refused(template_repo: Path, tmp_path: Path) -> None:
    project = committed_project(template_repo, tmp_path)
    result = sh(["sh", "scripts/check-release-config.sh"], project / "ios")
    assert result.returncode == 0, (result.stdout + result.stderr)[-3000:]
    assert git_visible_changes(project) == ""
    assert (project / "ios/.derived-data/release.log").is_file()  # the log is kept, in the ignored build area
    update_preview(project)  # not refused
    # Negative control: a stray file (what v0.1.0's log was) does make the update refuse.
    (project / "ios/.derived-data-release.log").write_text("stray\n")
    with pytest.raises(UserMessageError, match="dirty"):
        update_preview(project)


def test_a_failing_release_check_shows_the_build_error_and_still_leaves_the_tree_clean(template_repo: Path, tmp_path: Path) -> None:
    project = committed_project(template_repo, tmp_path)
    (project / "ios/App/Broken.swift").write_text("let broken: Int = \"not a number\"\n")  # a compile error in the app target
    run_git(project, "add", "-A")
    run_git(project, "commit", "-q", "-m", "a change that does not compile")
    result = sh(["sh", "scripts/check-release-config.sh"], project / "ios")
    assert result.returncode == 1
    assert "Broken.swift" in result.stdout and "error" in result.stdout  # the tail of the build log is shown
    assert "ios/.derived-data/release.log" in result.stderr
    assert git_visible_changes(project) == ""
