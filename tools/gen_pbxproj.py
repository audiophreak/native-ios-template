#!/usr/bin/env python3
"""Maintainer tool: writes template/ios/App.xcodeproj (project.pbxproj and the shared scheme).

    uv run python tools/gen_pbxproj.py            # write the files
    uv run python tools/gen_pbxproj.py --check    # change nothing; exit 1 if a committed file differs

The project is committed and static: nothing in it is templated (names, bundle identifier, API address and the
Info.plist all come from ios/Config/*.xcconfig, which are). App/ and AppTests/ are Xcode "synchronized folders", so
a new Swift file in either is part of its target without editing this project. Everything else lives in the local
Swift package ios/Packages/AppCore. Identifiers are derived from names, so the output is deterministic.
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "template/ios/App.xcodeproj"


def oid(name: str) -> str:
    return hashlib.md5(f"native-ios-template:{name}".encode()).hexdigest()[:24].upper()


I = {name: oid(name) for name in [
    "project", "main_group", "products_group", "config_group", "app_group", "tests_group", "app_product", "tests_product",
    "shared_cfg", "debug_cfg", "release_cfg", "info_debug", "info_release", "app_target", "tests_target",
    "app_sources", "app_frameworks", "app_resources", "tests_sources", "tests_frameworks", "tests_resources",
    "pkg_ref", "app_dep_core", "tests_dep_core", "app_build_core", "tests_build_core", "proxy", "target_dep",
    "proj_cfg_list", "proj_debug", "proj_release", "app_cfg_list", "app_debug", "app_release",
    "tests_cfg_list", "tests_debug", "tests_release",
]}  # fmt: skip


def project() -> str:
    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['app_build_core']} /* AppCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['app_dep_core']} /* AppCore */; }};
		{I['tests_build_core']} /* AppCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['tests_dep_core']} /* AppCore */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I['proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['app_target']};
			remoteInfo = App;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		{I['app_product']} /* App.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['tests_product']} /* AppTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = AppTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['shared_cfg']} /* Shared.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Shared.xcconfig; sourceTree = "<group>"; }};
		{I['debug_cfg']} /* Debug.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Debug.xcconfig; sourceTree = "<group>"; }};
		{I['release_cfg']} /* Release.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = "<group>"; }};
		{I['info_debug']} /* Info-Debug.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Info-Debug.plist"; sourceTree = "<group>"; }};
		{I['info_release']} /* Info-Release.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Info-Release.plist"; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['app_group']} /* App */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = App;
			sourceTree = "<group>";
		}};
		{I['tests_group']} /* AppTests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = AppTests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['app_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['app_build_core']} /* AppCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['tests_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['tests_build_core']} /* AppCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['main_group']} = {{
			isa = PBXGroup;
			children = (
				{I['app_group']} /* App */,
				{I['tests_group']} /* AppTests */,
				{I['config_group']} /* Config */,
				{I['products_group']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['config_group']} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{I['shared_cfg']} /* Shared.xcconfig */,
				{I['debug_cfg']} /* Debug.xcconfig */,
				{I['release_cfg']} /* Release.xcconfig */,
				{I['info_debug']} /* Info-Debug.plist */,
				{I['info_release']} /* Info-Release.plist */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{I['products_group']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['app_product']} /* App.app */,
				{I['tests_product']} /* AppTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['app_target']} /* App */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['app_cfg_list']} /* Build configuration list for PBXNativeTarget "App" */;
			buildPhases = (
				{I['app_sources']} /* Sources */,
				{I['app_frameworks']} /* Frameworks */,
				{I['app_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['app_group']} /* App */,
			);
			name = App;
			packageProductDependencies = (
				{I['app_dep_core']} /* AppCore */,
			);
			productName = App;
			productReference = {I['app_product']} /* App.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['tests_target']} /* AppTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['tests_cfg_list']} /* Build configuration list for PBXNativeTarget "AppTests" */;
			buildPhases = (
				{I['tests_sources']} /* Sources */,
				{I['tests_frameworks']} /* Frameworks */,
				{I['tests_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{I['target_dep']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['tests_group']} /* AppTests */,
			);
			name = AppTests;
			packageProductDependencies = (
				{I['tests_dep_core']} /* AppCore */,
			);
			productName = AppTests;
			productReference = {I['tests_product']} /* AppTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
				TargetAttributes = {{
					{I['app_target']} = {{
						CreatedOnToolsVersion = 26.0;
					}};
					{I['tests_target']} = {{
						CreatedOnToolsVersion = 26.0;
						TestTargetID = {I['app_target']};
					}};
				}};
			}};
			buildConfigurationList = {I['proj_cfg_list']} /* Build configuration list for PBXProject "App" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {I['main_group']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I['pkg_ref']} /* XCLocalSwiftPackageReference "Packages/AppCore" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['products_group']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['app_target']} /* App */,
				{I['tests_target']} /* AppTests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['app_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['tests_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['app_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['tests_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I['target_dep']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['app_target']} /* App */;
			targetProxy = {I['proxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{I['proj_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			baseConfigurationReference = {I['debug_cfg']} /* Debug.xcconfig */;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{I['proj_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			baseConfigurationReference = {I['release_cfg']} /* Release.xcconfig */;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{I['app_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = NO;
				PRODUCT_NAME = "$(TARGET_NAME)";
			}};
			name = Debug;
		}};
		{I['app_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = NO;
				PRODUCT_NAME = "$(TARGET_NAME)";
			}};
			name = Release;
		}};
		{I['tests_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "";
				PRODUCT_BUNDLE_IDENTIFIER = "$(PRODUCT_BUNDLE_IDENTIFIER_BASE).tests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/App.app/App";
			}};
			name = Debug;
		}};
		{I['tests_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "";
				PRODUCT_BUNDLE_IDENTIFIER = "$(PRODUCT_BUNDLE_IDENTIFIER_BASE).tests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/App.app/App";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I['proj_cfg_list']} /* Build configuration list for PBXProject "App" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['proj_debug']} /* Debug */,
				{I['proj_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['app_cfg_list']} /* Build configuration list for PBXNativeTarget "App" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['app_debug']} /* Debug */,
				{I['app_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['tests_cfg_list']} /* Build configuration list for PBXNativeTarget "AppTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['tests_debug']} /* Debug */,
				{I['tests_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I['pkg_ref']} /* XCLocalSwiftPackageReference "Packages/AppCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/AppCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I['app_dep_core']} /* AppCore */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = AppCore;
		}};
		{I['tests_dep_core']} /* AppCore */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = AppCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""


def scheme() -> str:
    def ref(target: str, name: str, product: str) -> str:
        return f"""BlueprintIdentifier = "{I[target]}"
               BuildableName = "{product}"
               BlueprintName = "{name}"
               ReferencedContainer = "container:App.xcodeproj\""""

    app = ref("app_target", "App", "App.app")
    tests = ref("tests_target", "AppTests", "AppTests.xctest")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               {app}>
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      disablePerformanceAntipatternChecker = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               {tests}>
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            {app}>
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


FILES = {
    PROJECT / "project.pbxproj": project,
    PROJECT / "xcshareddata/xcschemes/App.xcscheme": scheme,
}


def main() -> int:
    check = "--check" in sys.argv
    stale = []
    for path, make in FILES.items():
        text = make()
        if check:
            if not path.is_file() or path.read_text() != text:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    if stale:
        print("out of date: " + ", ".join(stale) + " (run tools/gen_pbxproj.py)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
