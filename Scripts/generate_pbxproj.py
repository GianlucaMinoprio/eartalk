#!/usr/bin/env python3
"""Generate EarTalk.xcodeproj/project.pbxproj from the Swift sources on disk."""
from __future__ import annotations

import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = "EarTalk"
BUNDLE = "com.gianlucaminoprio.eartalk"
TEAM = "W936BTJL69"

SWIFT = [
    ("App", "EarTalkApp.swift"),
    ("App", "SessionController.swift"),
    ("Models", "Models.swift"),
    ("Services", "AudioCaptureService.swift"),
    ("Services", "SpeechPlayer.swift"),
    ("Services", "SuperGrokAuth.swift"),
    ("Services", "XAIClient.swift"),
    ("Utilities", "KeychainStore.swift"),
    ("Utilities", "SpokenLanguage.swift"),
    ("Views", "RootView.swift"),
    ("Views", "SettingsView.swift"),
    ("Views", "SuperGrokSignInView.swift"),
    ("Views", "CaptionBoardView.swift"),
]


def nid() -> str:
    return uuid.uuid4().hex[:24].upper()


def main() -> None:
    ids = {name: nid() for name in [
        "project", "main_group", "products", "app_group",
        "app_dir", "models_dir", "services_dir", "views_dir", "utils_dir",
        "assets_ref", "plist_ref", "product_ref",
        "native_target", "sources_phase", "frameworks_phase", "resources_phase",
        "proj_debug", "proj_release", "tgt_debug", "tgt_release",
        "proj_cfgs", "tgt_cfgs", "assets_build",
    ]}
    file_ids = {}
    build_ids = {}
    for folder, name in SWIFT:
        file_ids[name] = nid()
        build_ids[name] = nid()

    def children(folder: str) -> str:
        lines = []
        for f, name in SWIFT:
            if f == folder:
                lines.append(f"\t\t\t\t{file_ids[name]} /* {name} */,")
        return "\n".join(lines)

    file_refs = []
    for folder, name in SWIFT:
        file_refs.append(
            f"\t\t{file_ids[name]} /* {name} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
        )
    file_refs.append(
        f"\t\t{ids['plist_ref']} /* Info.plist */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
    )
    file_refs.append(
        f"\t\t{ids['assets_ref']} /* Assets.xcassets */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};"
    )
    file_refs.append(
        f"\t\t{ids['product_ref']} /* {APP}.app */ = "
        f"{{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )

    build_files = [
        f"\t\t{build_ids[name]} /* {name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ids[name]} /* {name} */; }};"
        for _, name in SWIFT
    ]
    build_files.append(
        f"\t\t{ids['assets_build']} /* Assets.xcassets in Resources */ = "
        f"{{isa = PBXBuildFile; fileRef = {ids['assets_ref']} /* Assets.xcassets */; }};"
    )

    sources_list = "\n".join(
        f"\t\t\t\t{build_ids[name]} /* {name} in Sources */," for _, name in SWIFT
    )

    shared = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
"""

    target_settings = f"""
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = {TEAM};
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = {APP}/Info.plist;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
"""

    pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{ids['frameworks_phase']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids['app_dir']} /* App */ = {{
			isa = PBXGroup;
			children = (
{children('App')}
			);
			path = App;
			sourceTree = "<group>";
		}};
		{ids['models_dir']} /* Models */ = {{
			isa = PBXGroup;
			children = (
{children('Models')}
			);
			path = Models;
			sourceTree = "<group>";
		}};
		{ids['services_dir']} /* Services */ = {{
			isa = PBXGroup;
			children = (
{children('Services')}
			);
			path = Services;
			sourceTree = "<group>";
		}};
		{ids['views_dir']} /* Views */ = {{
			isa = PBXGroup;
			children = (
{children('Views')}
			);
			path = Views;
			sourceTree = "<group>";
		}};
		{ids['utils_dir']} /* Utilities */ = {{
			isa = PBXGroup;
			children = (
{children('Utilities')}
			);
			path = Utilities;
			sourceTree = "<group>";
		}};
		{ids['app_group']} /* {APP} */ = {{
			isa = PBXGroup;
			children = (
				{ids['app_dir']} /* App */,
				{ids['models_dir']} /* Models */,
				{ids['services_dir']} /* Services */,
				{ids['views_dir']} /* Views */,
				{ids['utils_dir']} /* Utilities */,
				{ids['assets_ref']} /* Assets.xcassets */,
				{ids['plist_ref']} /* Info.plist */,
			);
			path = {APP};
			sourceTree = "<group>";
		}};
		{ids['products']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids['product_ref']} /* {APP}.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{ids['main_group']} = {{
			isa = PBXGroup;
			children = (
				{ids['app_group']} /* {APP} */,
				{ids['products']} /* Products */,
			);
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ids['native_target']} /* {APP} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['tgt_cfgs']} /* Build configuration list for PBXNativeTarget "{APP}" */;
			buildPhases = (
				{ids['sources_phase']} /* Sources */,
				{ids['frameworks_phase']} /* Frameworks */,
				{ids['resources_phase']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = {APP};
			productName = {APP};
			productReference = {ids['product_ref']} /* {APP}.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 2700;
				TargetAttributes = {{
					{ids['native_target']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {ids['proj_cfgs']} /* Build configuration list for PBXProject "{APP}" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {ids['main_group']};
			productRefGroup = {ids['products']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids['native_target']} /* {APP} */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids['resources_phase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ids['assets_build']} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids['sources_phase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{sources_list}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{ids['proj_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{shared}
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{ids['proj_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{shared}
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
			}};
			name = Release;
		}};
		{ids['tgt_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{target_settings}			}};
			name = Debug;
		}};
		{ids['tgt_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{target_settings}			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids['tgt_cfgs']} /* Build configuration list for PBXNativeTarget "{APP}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['tgt_debug']} /* Debug */,
				{ids['tgt_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['proj_cfgs']} /* Build configuration list for PBXProject "{APP}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['proj_debug']} /* Debug */,
				{ids['proj_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {ids['project']} /* Project object */;
}}
"""

    proj_path = ROOT / f"{APP}.xcodeproj" / "project.pbxproj"
    proj_path.parent.mkdir(parents=True, exist_ok=True)
    proj_path.write_text(pbx)
    print(f"Wrote {proj_path}")
    print(f"NATIVE_TARGET={ids['native_target']}")

    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
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
               BlueprintIdentifier = "{ids['native_target']}"
               BuildableName = "{APP}.app"
               BlueprintName = "{APP}"
               ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
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
            BlueprintIdentifier = "{ids['native_target']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids['native_target']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
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
    scheme_path = ROOT / f"{APP}.xcodeproj/xcshareddata/xcschemes/{APP}.xcscheme"
    scheme_path.parent.mkdir(parents=True, exist_ok=True)
    scheme_path.write_text(scheme)
    print(f"Wrote {scheme_path}")


if __name__ == "__main__":
    main()
