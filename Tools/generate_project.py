# -*- coding: utf-8 -*-
"""
Того · генератор Xcode-проекта.

Проект собирается скриптом, а не руками в Xcode: так его не разносит
конфликтами в pbxproj и видно, из чего он состоит.

Папки подключены как synchronized root groups (objectVersion 77) — новые
файлы попадают в сборку сами, добавлять их в проект не нужно.
TogoShared входит и в приложение, и в виджет: общий код существует
в одном экземпляре.

    make project      # перегенерировать Togo.xcodeproj
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_c = [0]
def uid(tag=None):
    _c[0] += 1
    return "%024X" % (0xA0000000000000000000 + _c[0])

# --- ids
PROJECT        = uid()
MAIN_GROUP     = uid()
PRODUCTS_GROUP = uid()
CONFIG_GROUP   = uid()

SYNC_APP    = uid(); SYNC_WIDGET = uid(); SYNC_TESTS = uid(); SYNC_UITESTS = uid()
SYNC_SHARED = uid()
# Имена нужны для комментариев /* Togo */ в ссылках: без них файл читается
# хуже, и — важнее — расходится с тем, что пишет Xcode.
SYNC_NAMES = {SYNC_APP: 'Togo', SYNC_WIDGET: 'TogoWidgets', SYNC_TESTS: 'TogoTests',
              SYNC_UITESTS: 'TogoUITests', SYNC_SHARED: 'TogoShared'}

PROD_APP    = uid(); PROD_WIDGET = uid(); PROD_TESTS = uid(); PROD_UITESTS = uid()

T_APP = uid(); T_WIDGET = uid(); T_TESTS = uid(); T_UITESTS = uid()

# build phases
SRC_APP=uid(); FRM_APP=uid(); RES_APP=uid(); EMB_APP=uid()
SRC_WID=uid(); FRM_WID=uid(); RES_WID=uid()
SRC_TST=uid(); FRM_TST=uid(); RES_TST=uid()
SRC_UIT=uid(); FRM_UIT=uid(); RES_UIT=uid()

# build file / proxies
BF_WIDGET_EMBED = uid()
PROXY_WIDGET = uid(); DEP_WIDGET = uid()
PROXY_TESTS  = uid(); DEP_TESTS  = uid()
PROXY_UITESTS= uid(); DEP_UITESTS= uid()

# config lists
CL_PROJECT=uid(); CL_APP=uid(); CL_WID=uid(); CL_TST=uid(); CL_UIT=uid()
BC_PROJ_D=uid(); BC_PROJ_R=uid()
BC_APP_D=uid();  BC_APP_R=uid()
BC_WID_D=uid();  BC_WID_R=uid()
BC_TST_D=uid();  BC_TST_R=uid()
BC_UIT_D=uid();  BC_UIT_R=uid()

# xcconfig / plist file refs
FR_SHARED=uid(); FR_DEBUG=uid(); FR_RELEASE=uid()
XCCONFIG_NAMES = {FR_SHARED: 'Shared.xcconfig', FR_DEBUG: 'Debug.xcconfig',
                  FR_RELEASE: 'Release.xcconfig'}
FR_APP_PLIST=uid(); FR_WID_PLIST=uid()
FR_APP_ENT=uid(); FR_WID_ENT=uid()
FR_APP_ENT_P=uid(); FR_WID_ENT_P=uid()
FR_STOREKIT=uid()

def q(s):
    return '"%s"' % s

L = []
a = L.append

a('// !$*UTF8*$!')
a('{')
a('\tarchiveVersion = 1;')
a('\tclasses = {')
a('\t};')
a('\tobjectVersion = 77;')
# `rootObject` пишется в самом конце, после закрытия objects: так его
# ставит Xcode, и так лежит в репозитории. Порядок ключей в plist
# значения не имеет, но CI сравнивает файлы ТЕКСТОМ (ci.yml:78-79),
# и разный текст одного смысла красит сборку впустую.
a('\tobjects = {')

# PBXBuildFile
a('')
a('/* Begin PBXBuildFile section */')
a('\t\t%s /* TogoWidgetsExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = %s /* TogoWidgetsExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };' % (BF_WIDGET_EMBED, PROD_WIDGET))
a('/* End PBXBuildFile section */')

# PBXContainerItemProxy
a('')
a('/* Begin PBXContainerItemProxy section */')
for pid, tgt, name in ((PROXY_WIDGET, T_WIDGET, 'TogoWidgetsExtension'),
                       (PROXY_TESTS, T_APP, 'Togo'),
                       (PROXY_UITESTS, T_APP, 'Togo')):
    a('\t\t%s /* PBXContainerItemProxy */ = {' % pid)
    a('\t\t\tisa = PBXContainerItemProxy;')
    a('\t\t\tcontainerPortal = %s /* Project object */;' % PROJECT)
    a('\t\t\tproxyType = 1;')
    a('\t\t\tremoteGlobalIDString = %s;' % tgt)
    a('\t\t\tremoteInfo = %s;' % name)
    a('\t\t};')
a('/* End PBXContainerItemProxy section */')

# PBXCopyFilesBuildPhase
a('')
a('/* Begin PBXCopyFilesBuildPhase section */')
a('\t\t%s /* Embed Foundation Extensions */ = {' % EMB_APP)
a('\t\t\tisa = PBXCopyFilesBuildPhase;')
a('\t\t\tbuildActionMask = 2147483647;')
a('\t\t\tdstPath = "";')
a('\t\t\tdstSubfolderSpec = 13;')
a('\t\t\tfiles = (')
a('\t\t\t\t%s /* TogoWidgetsExtension.appex in Embed Foundation Extensions */,' % BF_WIDGET_EMBED)
a('\t\t\t);')
a('\t\t\tname = "Embed Foundation Extensions";')
a('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
a('\t\t};')
a('/* End PBXCopyFilesBuildPhase section */')

# PBXFileReference
a('')
a('/* Begin PBXFileReference section */')
a('\t\t%s /* Togo.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Togo.app; sourceTree = BUILT_PRODUCTS_DIR; };' % PROD_APP)
a('\t\t%s /* TogoWidgetsExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = TogoWidgetsExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };' % PROD_WIDGET)
a('\t\t%s /* TogoTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TogoTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };' % PROD_TESTS)
a('\t\t%s /* TogoUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TogoUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };' % PROD_UITESTS)
a('\t\t%s /* Shared.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Shared.xcconfig; sourceTree = "<group>"; };' % FR_SHARED)
a('\t\t%s /* Debug.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Debug.xcconfig; sourceTree = "<group>"; };' % FR_DEBUG)
a('\t\t%s /* Release.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = "<group>"; };' % FR_RELEASE)
a('\t\t%s /* Togo-Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Togo-Info.plist"; sourceTree = "<group>"; };' % FR_APP_PLIST)
a('\t\t%s /* TogoWidgets-Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "TogoWidgets-Info.plist"; sourceTree = "<group>"; };' % FR_WID_PLIST)
a('\t\t%s /* Togo.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Togo.entitlements; sourceTree = "<group>"; };' % FR_APP_ENT)
a('\t\t%s /* TogoWidgets.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = TogoWidgets.entitlements; sourceTree = "<group>"; };' % FR_WID_ENT)
a('\t\t%s /* Togo-Personal.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "Togo-Personal.entitlements"; sourceTree = "<group>"; };' % FR_APP_ENT_P)
a('\t\t%s /* TogoWidgets-Personal.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "TogoWidgets-Personal.entitlements"; sourceTree = "<group>"; };' % FR_WID_ENT_P)
a('\t\t%s /* Togo.storekit */ = {isa = PBXFileReference; lastKnownFileType = text; path = Togo.storekit; sourceTree = "<group>"; };' % FR_STOREKIT)
a('/* End PBXFileReference section */')

# PBXFileSystemSynchronizedRootGroup
a('')
a('/* Begin PBXFileSystemSynchronizedRootGroup section */')
# Форма и порядок — те, в которых пишет Xcode: он переписывает файл при
# каждом открытии проекта, и однострочная запись с explicitFileTypes
# превращалась у него в эту. Смысл один и тот же, а CI сравнивает текст.
for gid, path in ((SYNC_APP,'Togo'), (SYNC_WIDGET,'TogoWidgets'), (SYNC_TESTS,'TogoTests'), (SYNC_UITESTS,'TogoUITests'), (SYNC_SHARED,'TogoShared')):
    a('\t\t%s /* %s */ = {' % (gid, path))
    a('\t\t\tisa = PBXFileSystemSynchronizedRootGroup;')
    a('\t\t\tpath = %s;' % path)
    a('\t\t\tsourceTree = "<group>";')
    a('\t\t};')
a('/* End PBXFileSystemSynchronizedRootGroup section */')

# PBXFrameworksBuildPhase
a('')
a('/* Begin PBXFrameworksBuildPhase section */')
for pid in (FRM_APP, FRM_WID, FRM_TST, FRM_UIT):
    a('\t\t%s /* Frameworks */ = {' % pid)
    a('\t\t\tisa = PBXFrameworksBuildPhase;')
    a('\t\t\tbuildActionMask = 2147483647;')
    a('\t\t\tfiles = (')
    a('\t\t\t);')
    a('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    a('\t\t};')
a('/* End PBXFrameworksBuildPhase section */')

# PBXGroup
a('')
a('/* Begin PBXGroup section */')
a('\t\t%s = {' % MAIN_GROUP)
a('\t\t\tisa = PBXGroup;')
a('\t\t\tchildren = (')
a('\t\t\t\t%s /* Configuration */,' % CONFIG_GROUP)
a('\t\t\t\t%s /* TogoShared */,' % SYNC_SHARED)
a('\t\t\t\t%s /* Togo */,' % SYNC_APP)
a('\t\t\t\t%s /* TogoWidgets */,' % SYNC_WIDGET)
a('\t\t\t\t%s /* TogoTests */,' % SYNC_TESTS)
a('\t\t\t\t%s /* TogoUITests */,' % SYNC_UITESTS)
a('\t\t\t\t%s /* Products */,' % PRODUCTS_GROUP)
a('\t\t\t);')
a('\t\t\tsourceTree = "<group>";')
a('\t\t};')
a('\t\t%s /* Products */ = {' % PRODUCTS_GROUP)
a('\t\t\tisa = PBXGroup;')
a('\t\t\tchildren = (')
for p, n in ((PROD_APP,'Togo.app'), (PROD_WIDGET,'TogoWidgetsExtension.appex'), (PROD_TESTS,'TogoTests.xctest'), (PROD_UITESTS,'TogoUITests.xctest')):
    a('\t\t\t\t%s /* %s */,' % (p, n))
a('\t\t\t);')
a('\t\t\tname = Products;')
a('\t\t\tsourceTree = "<group>";')
a('\t\t};')
a('\t\t%s /* Configuration */ = {' % CONFIG_GROUP)
a('\t\t\tisa = PBXGroup;')
a('\t\t\tchildren = (')
for p, n in ((FR_SHARED,'Shared.xcconfig'), (FR_DEBUG,'Debug.xcconfig'), (FR_RELEASE,'Release.xcconfig'),
             (FR_APP_PLIST,'Togo-Info.plist'), (FR_WID_PLIST,'TogoWidgets-Info.plist'),
             (FR_APP_ENT,'Togo.entitlements'), (FR_WID_ENT,'TogoWidgets.entitlements'),
             (FR_APP_ENT_P,'Togo-Personal.entitlements'), (FR_WID_ENT_P,'TogoWidgets-Personal.entitlements'),
             (FR_STOREKIT,'Togo.storekit')):
    a('\t\t\t\t%s /* %s */,' % (p, n))
a('\t\t\t);')
a('\t\t\tpath = Configuration;')
a('\t\t\tsourceTree = "<group>";')
a('\t\t};')
a('/* End PBXGroup section */')

# PBXNativeTarget
a('')
a('/* Begin PBXNativeTarget section */')

def native(tid, name, cl, phases, sync, deps, prod, prodname, ptype):
    syncs = sync if isinstance(sync, (list, tuple)) else [sync]
    a('\t\t%s /* %s */ = {' % (tid, name))
    a('\t\t\tisa = PBXNativeTarget;')
    a('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;' % (cl, name))
    a('\t\t\tbuildPhases = (')
    for ph, phn in phases:
        a('\t\t\t\t%s /* %s */,' % (ph, phn))
    a('\t\t\t);')
    a('\t\t\tbuildRules = (')
    a('\t\t\t);')
    a('\t\t\tdependencies = (')
    for d in deps:
        a('\t\t\t\t%s /* PBXTargetDependency */,' % d)
    a('\t\t\t);')
    a('\t\t\tfileSystemSynchronizedGroups = (')
    for gid in syncs:
        a('\t\t\t\t%s /* %s */,' % (gid, SYNC_NAMES[gid]))
    a('\t\t\t);')
    a('\t\t\tname = %s;' % name)
    a('\t\t\tpackageProductDependencies = (')
    a('\t\t\t);')
    a('\t\t\tproductName = %s;' % name)
    a('\t\t\tproductReference = %s /* %s */;' % (prod, prodname))
    a('\t\t\tproductType = "%s";' % ptype)
    a('\t\t};')

native(T_APP, 'Togo', CL_APP,
       [(SRC_APP,'Sources'), (FRM_APP,'Frameworks'), (RES_APP,'Resources'), (EMB_APP,'Embed Foundation Extensions')],
       [SYNC_APP, SYNC_SHARED], [DEP_WIDGET], PROD_APP, 'Togo.app', 'com.apple.product-type.application')
native(T_WIDGET, 'TogoWidgetsExtension', CL_WID,
       [(SRC_WID,'Sources'), (FRM_WID,'Frameworks'), (RES_WID,'Resources')],
       [SYNC_WIDGET, SYNC_SHARED], [], PROD_WIDGET, 'TogoWidgetsExtension.appex', 'com.apple.product-type.app-extension')
native(T_TESTS, 'TogoTests', CL_TST,
       [(SRC_TST,'Sources'), (FRM_TST,'Frameworks'), (RES_TST,'Resources')],
       SYNC_TESTS, [DEP_TESTS], PROD_TESTS, 'TogoTests.xctest', 'com.apple.product-type.bundle.unit-test')
native(T_UITESTS, 'TogoUITests', CL_UIT,
       [(SRC_UIT,'Sources'), (FRM_UIT,'Frameworks'), (RES_UIT,'Resources')],
       SYNC_UITESTS, [DEP_UITESTS], PROD_UITESTS, 'TogoUITests.xctest', 'com.apple.product-type.bundle.ui-testing')
a('/* End PBXNativeTarget section */')

# PBXProject
a('')
a('/* Begin PBXProject section */')
a('\t\t%s /* Project object */ = {' % PROJECT)
a('\t\t\tisa = PBXProject;')
a('\t\t\tattributes = {')
a('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
a('\t\t\t\tLastSwiftUpdateCheck = 2660;')
a('\t\t\t\tLastUpgradeCheck = 2660;')
a('\t\t\t\tTargetAttributes = {')
a('\t\t\t\t\t%s = {' % T_TESTS)
a('\t\t\t\t\t\tTestTargetID = %s;' % T_APP)
a('\t\t\t\t\t};')
a('\t\t\t\t\t%s = {' % T_UITESTS)
a('\t\t\t\t\t\tTestTargetID = %s;' % T_APP)
a('\t\t\t\t\t};')
a('\t\t\t\t};')
a('\t\t\t};')
a('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "Togo" */;' % CL_PROJECT)
a('\t\t\tdevelopmentRegion = ru;')
a('\t\t\thasScannedForEncodings = 0;')
# Языки проекта. Украинского здесь не было до 23.09.2026, хотя
# в каталогах и в бандле он есть: `uk.lproj` собирается, язык
# не теряется — проверено бандлом, а не рассуждением.
#
# Плохо другое. Отсюда языки берут двое:
#   · `xcodebuild -exportLocalizations` — поэтому `uk.xcloc`
#     не выгружался, и отдать каталог носителю стандартным путём
#     было нельзя;
#   · любой сторож полноты, если он берёт языки у проекта, —
#     а брать их надо именно там, иначе копия списка в тесте
#     однажды отстанет.
#
# То есть украинский **жил без охраны**: сторож спросил бы про
# `ru`, `en`, `fr` и промолчал бы, не заглянув в украинский вовсе.
# Доказано подделкой у Gamut: убрали `uk` из списка — покрытие
# прошло, а согласие проекта с каталогами упало.
a('\t\t\tknownRegions = (')
a('\t\t\t\tru,')
a('\t\t\t\ten,')
a('\t\t\t\tfr,')
a('\t\t\t\tuk,')
a('\t\t\t\tBase,')
a('\t\t\t);')
a('\t\t\tmainGroup = %s;' % MAIN_GROUP)
a('\t\t\tminimizedProjectReferenceProxies = 1;')
a('\t\t\tpreferredProjectObjectVersion = 77;')
a('\t\t\tproductRefGroup = %s /* Products */;' % PRODUCTS_GROUP)
a('\t\t\tprojectDirPath = "";')
a('\t\t\tprojectRoot = "";')
a('\t\t\ttargets = (')
for t, n in ((T_APP,'Togo'), (T_WIDGET,'TogoWidgetsExtension'), (T_TESTS,'TogoTests'), (T_UITESTS,'TogoUITests')):
    a('\t\t\t\t%s /* %s */,' % (t, n))
a('\t\t\t);')
a('\t\t};')
a('/* End PBXProject section */')

# Resources phases
a('')
a('/* Begin PBXResourcesBuildPhase section */')
for pid in (RES_APP, RES_WID, RES_TST, RES_UIT):
    a('\t\t%s /* Resources */ = {' % pid)
    a('\t\t\tisa = PBXResourcesBuildPhase;')
    a('\t\t\tbuildActionMask = 2147483647;')
    a('\t\t\tfiles = (')
    a('\t\t\t);')
    a('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    a('\t\t};')
a('/* End PBXResourcesBuildPhase section */')

a('')
a('/* Begin PBXSourcesBuildPhase section */')
for pid in (SRC_APP, SRC_WID, SRC_TST, SRC_UIT):
    a('\t\t%s /* Sources */ = {' % pid)
    a('\t\t\tisa = PBXSourcesBuildPhase;')
    a('\t\t\tbuildActionMask = 2147483647;')
    a('\t\t\tfiles = (')
    a('\t\t\t);')
    a('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    a('\t\t};')
a('/* End PBXSourcesBuildPhase section */')

# Target dependencies
a('')
a('/* Begin PBXTargetDependency section */')
for did, tgt, name, proxy in ((DEP_WIDGET, T_WIDGET, 'TogoWidgetsExtension', PROXY_WIDGET),
                              (DEP_TESTS, T_APP, 'Togo', PROXY_TESTS),
                              (DEP_UITESTS, T_APP, 'Togo', PROXY_UITESTS)):
    a('\t\t%s /* PBXTargetDependency */ = {' % did)
    a('\t\t\tisa = PBXTargetDependency;')
    a('\t\t\ttarget = %s /* %s */;' % (tgt, name))
    a('\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;' % proxy)
    a('\t\t};')
a('/* End PBXTargetDependency section */')

# XCBuildConfiguration
a('')
a('/* Begin XCBuildConfiguration section */')

_SAFE = re.compile(r'^[A-Za-z0-9_$/.-]+$')
def qv(v):
    # Старый формат plist: без кавычек допустимы только [A-Za-z0-9_$/.-].
    if v.startswith('"') or v.startswith('('):
        return v
    if _SAFE.match(v):
        return v
    return '"%s"' % v.replace('\\', '\\\\').replace('"', '\\"')

def cfg(cid, name, base, settings):
    a('\t\t%s /* %s */ = {' % (cid, name))
    a('\t\t\tisa = XCBuildConfiguration;')
    if base:
        a('\t\t\tbaseConfigurationReference = %s /* %s */;' % (base, XCCONFIG_NAMES[base]))
    a('\t\t\tbuildSettings = {')
    for k in sorted(settings):
        v = settings[k]
        # Список пишется в скобках, по значению на строку — так пишет Xcode.
        if isinstance(v, (list, tuple)):
            a('\t\t\t\t%s = (' % k)
            for item in v:
                a('\t\t\t\t\t%s,' % qv(item))
            a('\t\t\t\t);')
            continue
        a('\t\t\t\t%s = %s;' % (k, qv(v)))
    a('\t\t\t};')
    a('\t\t\tname = %s;' % name)
    a('\t\t};')

PROJ_COMMON = {
    'ALWAYS_SEARCH_USER_PATHS': 'NO',
    'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS': 'YES',
    'CLANG_ANALYZER_NONNULL': 'YES',
    'CLANG_ENABLE_MODULES': 'YES',
    'CLANG_ENABLE_OBJC_ARC': 'YES',
    'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES',
    'COPY_PHASE_STRIP': 'NO',
    'DEAD_CODE_STRIPPING': 'YES',
    'ENABLE_STRICT_OBJC_MSGSEND': 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
    'GCC_C_LANGUAGE_STANDARD': 'gnu17',
    'GCC_NO_COMMON_BLOCKS': 'YES',
    'GCC_WARN_UNDECLARED_SELECTOR': 'YES',
    'GCC_WARN_UNUSED_FUNCTION': 'YES',
    'GCC_WARN_UNUSED_VARIABLE': 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
    'LOCALIZATION_PREFERS_STRING_CATALOGS': 'YES',
    'SDKROOT': 'iphoneos',
    'SWIFT_APPROACHABLE_CONCURRENCY': 'YES',
    'SWIFT_DEFAULT_ACTOR_ISOLATION': 'MainActor',
    'SWIFT_EMIT_LOC_STRINGS': 'YES',
    'SWIFT_VERSION': '6.0',
}
d = dict(PROJ_COMMON); d.update({
    'DEBUG_INFORMATION_FORMAT': 'dwarf',
    'ENABLE_TESTABILITY': 'YES',
    'GCC_DYNAMIC_NO_PIC': 'NO',
    'GCC_OPTIMIZATION_LEVEL': '0',
    'GCC_PREPROCESSOR_DEFINITIONS': ['"DEBUG=1"', '"$(inherited)"'],
    'MTL_ENABLE_DEBUG_INFO': 'INCLUDE_SOURCE',
    'ONLY_ACTIVE_ARCH': 'YES',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '"DEBUG $(inherited)"',
    'SWIFT_OPTIMIZATION_LEVEL': '"-Onone"',
})
cfg(BC_PROJ_D, 'Debug', FR_DEBUG, d)
d = dict(PROJ_COMMON); d.update({
    'DEBUG_INFORMATION_FORMAT': '"dwarf-with-dsym"',
    'ENABLE_NS_ASSERTIONS': 'NO',
    'MTL_ENABLE_DEBUG_INFO': 'NO',
    'SWIFT_COMPILATION_MODE': 'wholemodule',
    'VALIDATE_PRODUCT': 'YES',
})
cfg(BC_PROJ_R, 'Release', FR_RELEASE, d)

APP = {
    # Иконка — проект Icon Composer `Togo/Resources/Togo.icon`, а не
    # `AppIcon.appiconset`. Имя здесь без расширения, как и у каталога.
    #
    # `Togo/` — синхронизированная группа, поэтому `.icon` попадает
    # в таргет сам: отдельной записи в проекте не нужно, и править
    # `project.pbxproj` руками не надо (он генерируется этим файлом).
    #
    # `AppIcon.appiconset` ОСТАВЛЕН рядом нарочно, не удалён: деплоймент
    # у нас 17.0, а `.icon` — механизм iOS 26. Нужен ли классический
    # каталог запасом для 17–25, чтением не выяснить — это решает
    # сборка: смотреть, какие размеры `actool` положил в бандл.
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'Togo',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
    'CODE_SIGN_ENTITLEMENTS': 'Configuration/Togo$(ENTITLEMENTS_VARIANT).entitlements',
    'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '$(BUILD_NUMBER)',
    'DEVELOPMENT_ASSET_PATHS': '""',
    'DEVELOPMENT_TEAM': '$(DEVELOPMENT_TEAM)',
    'ENABLE_PREVIEWS': 'YES',
    'GENERATE_INFOPLIST_FILE': 'NO',
    'INFOPLIST_FILE': '"Configuration/Togo-Info.plist"',
    'LD_RUNPATH_SEARCH_PATHS': '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
    'MARKETING_VERSION': '$(MARKETING_VERSION)',
    'PRODUCT_BUNDLE_IDENTIFIER': '$(APP_BUNDLE_ID)',
    'PRODUCT_NAME': '"$(TARGET_NAME)"',
    'SWIFT_EMIT_LOC_STRINGS': 'YES',
    'TARGETED_DEVICE_FAMILY': '1',
}
cfg(BC_APP_D, 'Debug', None, APP)
cfg(BC_APP_R, 'Release', None, APP)

WID = {
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
    'ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME': 'WidgetBackground',
    'CODE_SIGN_ENTITLEMENTS': 'Configuration/TogoWidgets$(ENTITLEMENTS_VARIANT).entitlements',
    'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '$(BUILD_NUMBER)',
    'DEVELOPMENT_TEAM': '$(DEVELOPMENT_TEAM)',
    'ENABLE_PREVIEWS': 'YES',
    'GENERATE_INFOPLIST_FILE': 'NO',
    'INFOPLIST_FILE': '"Configuration/TogoWidgets-Info.plist"',
    'LD_RUNPATH_SEARCH_PATHS': '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t\t"@executable_path/../../Frameworks",\n\t\t\t\t)',
    'MARKETING_VERSION': '$(MARKETING_VERSION)',
    'PRODUCT_BUNDLE_IDENTIFIER': '$(APP_BUNDLE_ID).widgets',
    'PRODUCT_NAME': '"$(TARGET_NAME)"',
    'SKIP_INSTALL': 'YES',
    'SWIFT_EMIT_LOC_STRINGS': 'YES',
    'TARGETED_DEVICE_FAMILY': '1',
}
cfg(BC_WID_D, 'Debug', None, WID)
cfg(BC_WID_R, 'Release', None, WID)

TST = {
    'BUNDLE_LOADER': '"$(TEST_HOST)"',
    'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '$(BUILD_NUMBER)',
    'DEVELOPMENT_TEAM': '$(DEVELOPMENT_TEAM)',
    'GENERATE_INFOPLIST_FILE': 'YES',
    'MARKETING_VERSION': '$(MARKETING_VERSION)',
    'PRODUCT_BUNDLE_IDENTIFIER': '$(APP_BUNDLE_ID).tests',
    'PRODUCT_NAME': '"$(TARGET_NAME)"',
    'TARGETED_DEVICE_FAMILY': '1',
    'TEST_HOST': '"$(BUILT_PRODUCTS_DIR)/Togo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Togo"',
}
cfg(BC_TST_D, 'Debug', None, TST)
cfg(BC_TST_R, 'Release', None, TST)

UIT = {
    'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '$(BUILD_NUMBER)',
    'DEVELOPMENT_TEAM': '$(DEVELOPMENT_TEAM)',
    'GENERATE_INFOPLIST_FILE': 'YES',
    'MARKETING_VERSION': '$(MARKETING_VERSION)',
    'PRODUCT_BUNDLE_IDENTIFIER': '$(APP_BUNDLE_ID).uitests',
    'PRODUCT_NAME': '"$(TARGET_NAME)"',
    'TARGETED_DEVICE_FAMILY': '1',
    'TEST_TARGET_NAME': 'Togo',
}
cfg(BC_UIT_D, 'Debug', None, UIT)
cfg(BC_UIT_R, 'Release', None, UIT)
a('/* End XCBuildConfiguration section */')

# XCConfigurationList
a('')
a('/* Begin XCConfigurationList section */')
for clid, name, dbg, rel, kind in ((CL_PROJECT, 'Togo', BC_PROJ_D, BC_PROJ_R, 'PBXProject'),
                                   (CL_APP, 'Togo', BC_APP_D, BC_APP_R, 'PBXNativeTarget'),
                                   (CL_WID, 'TogoWidgetsExtension', BC_WID_D, BC_WID_R, 'PBXNativeTarget'),
                                   (CL_TST, 'TogoTests', BC_TST_D, BC_TST_R, 'PBXNativeTarget'),
                                   (CL_UIT, 'TogoUITests', BC_UIT_D, BC_UIT_R, 'PBXNativeTarget')):
    a('\t\t%s /* Build configuration list for %s "%s" */ = {' % (clid, kind, name))
    a('\t\t\tisa = XCConfigurationList;')
    a('\t\t\tbuildConfigurations = (')
    a('\t\t\t\t%s /* Debug */,' % dbg)
    a('\t\t\t\t%s /* Release */,' % rel)
    a('\t\t\t);')
    a('\t\t\tdefaultConfigurationIsVisible = 0;')
    a('\t\t\tdefaultConfigurationName = Release;')
    a('\t\t};')
a('/* End XCConfigurationList section */')

a('\t};')
a('\trootObject = %s /* Project object */;' % PROJECT)
a('}')

SCHEME = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{APP}" BuildableName="Togo.app" BlueprintName="Togo" ReferencedContainer="container:Togo.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{TESTS}" BuildableName="TogoTests.xctest" BlueprintName="TogoTests" ReferencedContainer="container:Togo.xcodeproj"/>
         </TestableReference>
         <TestableReference skipped="NO">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{UITESTS}" BuildableName="TogoUITests.xctest" BlueprintName="TogoUITests" ReferencedContainer="container:Togo.xcodeproj"/>
         </TestableReference>
      </Testables>
      <!-- Тот же файл, что и у запуска: тесты, идущие из Xcode, видят
           цены, а не пустой экран «Цены не загрузились».
           Проверено: `xcodebuild test` этот файл не подхватывает —
           UI-тест поднимает приложение сам, мимо схемы. Снимок «Того Pro»
           с настоящими ценами снимается только из Xcode. -->
      <StoreKitConfigurationFileReference identifier="../../../Configuration/Togo.storekit"/>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{APP}" BuildableName="Togo.app" BlueprintName="Togo" ReferencedContainer="container:Togo.xcodeproj"/>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference identifier="../../../Configuration/Togo.storekit"/>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{APP}" BuildableName="Togo.app" BlueprintName="Togo" ReferencedContainer="container:Togo.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''

scheme_dir = os.path.join(ROOT, 'Togo.xcodeproj', 'xcshareddata', 'xcschemes')
os.makedirs(scheme_dir, exist_ok=True)
with open(os.path.join(scheme_dir, 'Togo.xcscheme'), 'w') as f:
    f.write(SCHEME.replace('{APP}', T_APP).replace('{TESTS}', T_TESTS).replace('{UITESTS}', T_UITESTS))
print('wrote', os.path.join(scheme_dir, 'Togo.xcscheme'))

out_dir = os.path.join(ROOT, 'Togo.xcodeproj')
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, 'project.pbxproj'), 'w') as f:
    f.write('\n'.join(L) + '\n')
print('wrote', os.path.join(out_dir, 'project.pbxproj'))
