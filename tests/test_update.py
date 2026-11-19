"""The layer upgrades on its own (`copier update` with its own answers file) and keeps the project's work."""

from __future__ import annotations

import shutil
from pathlib import Path

import copier
import yaml
from copier import Settings

from conftest import TEMPLATE_ROOT, run_git

ANSWERS = ".copier-answers.ios.yml"
WEB_FILES = {".copier-answers.yml": "_commit: v0.7.0\napp_name: sample-app\nauth: true\nnative_client: true\n", "package.json": '{"name":"sample-app"}\n', "AGENTS.md": "web rules\n", ".gitignore": "node_modules\n"}


def release(repo: Path, tag: str, edit=None) -> None:
    if edit:
        edit(repo / "template")
    run_git(repo, "add", "-A")
    run_git(repo, "commit", "-q", "--allow-empty", "-m", f"release {tag}")
    run_git(repo, "tag", tag)


def history(tmp_path: Path) -> Path:
    repo = tmp_path / "native-ios-template"
    repo.mkdir()
    shutil.copy2(TEMPLATE_ROOT / "copier.yml", repo / "copier.yml")
    shutil.copytree(TEMPLATE_ROOT / "template", repo / "template", ignore=shutil.ignore_patterns(".build", ".derived-data", "xcuserdata"))
    run_git(repo, "init", "-q", "-b", "main")
    release(repo, "v0.1.0")
    return repo


def update(project: Path, ref: str) -> None:
    copier.run_update(project, answers_file=Path(ANSWERS), vcs_ref=ref, defaults=True, overwrite=True, skip_answered=True, settings=Settings(), unsafe=False, quiet=True)


def test_the_layer_updates_by_itself_keeping_user_work_and_leaving_the_web_files_alone(tmp_path: Path) -> None:
    repo = history(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    for name, text in WEB_FILES.items():
        (project / name).write_text(text)
    copier.run_copy(str(repo), project, data={"app_name": "sample-app"}, defaults=True, vcs_ref="v0.1.0", settings=Settings(), unsafe=False, quiet=True)
    run_git(project, "init", "-q", "-b", "main")
    (project / "ios/App/MyOwnView.swift").write_text("import SwiftUI\nstruct MyOwnView: View { var body: some View { Text(\"mine\") } }\n")
    shared = project / "ios/Config/Shared.xcconfig"
    shared.write_text(shared.read_text() + "\nMARKETING_VERSION = 1.2.3\n")
    run_git(project, "add", "-A")
    run_git(project, "commit", "-q", "-m", "initial and my work")
    web_before = {name: (project / name).read_bytes() for name in WEB_FILES}
    assert yaml.safe_load((project / ANSWERS).read_text())["_commit"] == "v0.1.0"

    def edit(template: Path) -> None:
        script = template / "ios/scripts/test.sh"
        script.write_text(script.read_text() + "\n# a later improvement\n")
        readme = template / "ios/README.md.jinja"
        readme.write_text(readme.read_text() + "\nA later note.\n")

    release(repo, "v0.1.1", edit)
    update(project, "v0.1.1")

    assert "# a later improvement" in (project / "ios/scripts/test.sh").read_text() and "A later note." in (project / "ios/README.md").read_text()
    assert (project / "ios/App/MyOwnView.swift").read_text().startswith("import SwiftUI")
    assert "MARKETING_VERSION = 1.2.3" in shared.read_text()
    assert yaml.safe_load((project / ANSWERS).read_text())["_commit"] == "v0.1.1"
    assert {name: (project / name).read_bytes() for name in WEB_FILES} == web_before  # the web layer is untouched, answers file included
    assert "<<<<<<<" not in "".join(p.read_text(errors="replace") for p in (project / "ios").rglob("*") if p.is_file() and p.suffix in {".swift", ".xcconfig", ".sh", ".md"} and ".build" not in p.parts)
