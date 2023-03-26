#!/bin/bash -e

# Copyright (c) 2011  Zotero
#                     Center for History and New Media
#                     George Mason University, Fairfax, Virginia, USA
#                     http://zotero.org
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

CALLDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CALLDIR/config.sh"

## Sniff the channel from the code to be built
set +e
FULL_VERSION=`perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version.*/\1/;' "$ZOTERO_BUILD_DIR/xpi/build/staging/install.rdf"`

IS_JURISM=$(echo $FULL_VERSION | grep -c '[0-9]m[0-9]')
IS_SOURCE=$(echo $FULL_VERSION | grep -c '\(SOURCE\|-dev.\)')
IS_BETA=$(echo $FULL_VERSION | grep -c 'm[0-9]\+-beta\.[0-9]')
IS_RELEASE=$(echo $FULL_VERSION | grep -c '[0-9]m[0-9]\+$')
set -e

if [ $IS_JURISM -eq 1 ]; then
    if [ $IS_RELEASE -eq 1 ]; then
        UPDATE_CHANNEL="release"
    elif [ $IS_BETA -eq 1 ]; then
        UPDATE_CHANNEL="beta"
    elif [ $IS_SOURCE -eq 1 ]; then
        UPDATE_CHANNEL="source"
    else
        echo Version in $ZOTERO_BUILD_DIR/build/staging/install.rdf is neither release, nor beta, nor source.
	exit 1
    fi
else
    echo Content at $ZOTERO_BUILD_DIR/xpi/build/staging/ is not a Juris-M client.
    exit 1
fi



if [ "`uname`" = "Darwin" ]; then
	MAC_NATIVE=1
else
	MAC_NATIVE=0
fi
if [ "`uname -o 2> /dev/null`" = "Cygwin" ]; then
	WIN_NATIVE=1
else
	WIN_NATIVE=0
fi

set +e
gsed --version > /dev/null 2<&1
if [ $? -gt 0 ]; then
    GSED="sed"
else
    GSED="gsed"
fi
gfind --version > /dev/null 2<&1
if [ $? -gt 0 ]; then
    GFIND="find"
else
    GFIND="gfind"
fi
set -e

function usage {
	cat >&2 <<DONE
Usage: $0 -p PLATFORMS
Options
 -t                  add devtools
 -p PLATFORMS        build for platforms PLATFORMS (m=Mac, w=Windows, l=Linux)
 -e                  enforce signing
 -s                  don't package; only build binaries in staging/ directory
DONE
	exit 1
}

BUILD_DIR=`mktemp -d`
function cleanup {
	rm -rf $BUILD_DIR
}
trap cleanup EXIT

function abspath {
	echo $(cd $(dirname $1); pwd)/$(basename $1);
}

SOURCE_DIR=""
ZIP_FILE=""
BUILD_MAC=0
BUILD_WIN32=0
BUILD_LINUX=0
PACKAGE=1
DEVTOOLS=0
SOURCE_DIR="$ZOTERO_BUILD_DIR/xpi/build/staging"

while getopts "d:c:p:tse" opt; do
	case $opt in
        d)
            echo Juris-M \(-d\): setting SOURCE_DIR to: $SOURCE_DIR
            ;;
        c)
            echo Juris-M \(-c\): setting UPDATE_CHANNEL to: $UPDATE_CHANNEL
            ;;
		p)
			for i in `seq 0 1 $((${#OPTARG}-1))`
			do
				case ${OPTARG:i:1} in
					m) BUILD_MAC=1;;
					w) BUILD_WIN32=1;;
					l) BUILD_LINUX=1;;
					*)
						echo "$0: Invalid platform option ${OPTARG:i:1}"
						usage
						;;
				esac
			done
			;;
		t)
			DEVTOOLS=1
			;;
		e)
			SIGN=1
			;;
		s)
			PACKAGE=0
			;;
		*)
			usage
			;;
	esac
	shift $((OPTIND-1)); OPTIND=1
done

if [[ -z $PLATFORM ]]; then
	if [ "`uname`" = "Darwin" ]; then
		BUILD_MAC=1
	elif [ "`uname`" = "Linux" ]; then
		BUILD_LINUX=1
	elif [ "`uname -o 2> /dev/null`" = "Cygwin" ]; then
		BUILD_WIN32=1
	fi
fi

# Require at least one platform
if [[ $BUILD_MAC == 0 ]] && [[ $BUILD_WIN32 == 0 ]] && [[ $BUILD_LINUX == 0 ]]; then
	usage
fi

# Bundle devtools with dev builds
if [ $UPDATE_CHANNEL == "beta" ] || [ $UPDATE_CHANNEL == "dev" ]; then
	DEVTOOLS=1
fi

BUILD_ID=`date +%Y%m%d%H%M%S`

shopt -s extglob
mkdir -p "$BUILD_DIR/zotero"
rm -rf "$STAGE_DIR"
mkdir "$STAGE_DIR"
rm -rf "$DIST_DIR"
mkdir "$DIST_DIR"

# Save build id, which is needed for updates manifest
echo $BUILD_ID > "$DIST_DIR/build_id"

if [ -z "$UPDATE_CHANNEL" ]; then UPDATE_CHANNEL="default"; fi

if [ -n "$ZIP_FILE" ]; then
	ZIP_FILE="`abspath $ZIP_FILE`"
	echo "Building from $ZIP_FILE"
	unzip -q $ZIP_FILE -d "$BUILD_DIR/zotero"
else
	# TODO: Could probably just mv instead, at least if these repos are merged
	rsync -a "$SOURCE_DIR/" "$BUILD_DIR/zotero/"
fi

cd "$BUILD_DIR/zotero"

# 5.0.96.3 / 5.0.97-beta.37+ddc7be75c
VERSION=`perl -ne 'print and last if s/.*<em:version>(.+)<\/em:version>.*/\1/;' install.rdf`
# 5.0.96 / 5.0.97
VERSION_NUMERIC=`perl -ne 'print and last if s/.*<em:version>(\d+\.\d+(\.\d+)?).*<\/em:version>.*/\1/;' install.rdf`
if [ -z "$VERSION" ]; then
	echo "Version number not found in install.rdf"
	exit 1
fi
rm install.rdf

echo
echo "Version: $VERSION"

# Delete Mozilla signing info if present
rm -rf META-INF

# Copy branding
cp -R "$CALLDIR/assets/branding" "$BUILD_DIR/zotero/chrome/branding"

# Add to chrome manifest
echo "" >> "$BUILD_DIR/zotero/chrome.manifest"
cat "$CALLDIR/assets/chrome.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"

# Copy Error Console files
cp "$CALLDIR/assets/console/jsconsole-clhandler.js" "$BUILD_DIR/zotero/components/"
echo >> "$BUILD_DIR/zotero/chrome.manifest"
cat "$CALLDIR/assets/console/jsconsole-clhandler.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"
cp -R "$CALLDIR/assets/console/content" "$BUILD_DIR/zotero/chrome/console"
cp -R "$CALLDIR/assets/console/skin/osx" "$BUILD_DIR/zotero/chrome/console/skin"
cp -R "$CALLDIR/assets/console/locale/en-US" "$BUILD_DIR/zotero/chrome/console/locale"
cat "$CALLDIR/assets/console/jsconsole.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"

# Delete files that shouldn't be distributed
${GFIND} "$BUILD_DIR/zotero/chrome" -name .DS_Store -exec rm -f {} \;

# Zip chrome into JAR
cd "$BUILD_DIR/zotero"
zip -r -q jurism.jar chrome deleted.txt resource styles.zip translators.index translators.zip styles translators.json translators style-modules juris-maps juris-abbrevs
rm -rf "chrome/"* install.rdf deleted.txt resource styles.zip translators.index translators.zip styles translators.json translators style-modules juris-maps juris-abbrevs

# Copy updater.ini
cp "$CALLDIR/assets/updater.ini" "$BUILD_DIR/zotero"

# Adjust chrome.manifest
perl -pi -e 's^(chrome|resource)/^jar:jurism.jar\!/$1/^g' "$BUILD_DIR/zotero/chrome.manifest"

# Adjust connector pref
perl -pi -e 's/pref\("extensions\.zotero\.httpServer\.enabled", false\);/pref("extensions.zotero.httpServer.enabled", true);/g' "$BUILD_DIR/zotero/defaults/preferences/zotero.js"
perl -pi -e 's/pref\("extensions\.zotero\.connector\.enabled", false\);/pref("extensions.zotero.connector.enabled", true);/g' "$BUILD_DIR/zotero/defaults/preferences/zotero.js"

# Copy icons
cp -r "$CALLDIR/assets/icons" "$BUILD_DIR/zotero/chrome/icons"

# Copy application.ini and modify
cp "$CALLDIR/assets/application.ini" "$BUILD_DIR/application.ini"
perl -pi -e "s/\{\{VERSION}}/$VERSION/" "$BUILD_DIR/application.ini"
perl -pi -e "s/\{\{BUILDID}}/$BUILD_ID/" "$BUILD_DIR/application.ini"

# Copy prefs.js and modify
cp "$CALLDIR/assets/prefs.js" "$BUILD_DIR/zotero/defaults/preferences"
perl -pi -e 's/pref\("app\.update\.channel", "[^"]*"\);/pref\("app\.update\.channel", "'"$UPDATE_CHANNEL"'");/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"

# Add devtools manifest and prefs
if [ $DEVTOOLS -eq 1 ]; then
	# Adjust paths for .jar
	cat "$CALLDIR/assets/devtools.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"
	perl -pi -e 's/chrome\/locale\/en-US\/devtools\//jar:devtools.jar!\/locale\/en-US\/devtools\//' "$BUILD_DIR/zotero/chrome.manifest"
	perl -pi -e 's/chrome\/devtools\//jar:devtools.jar!\//' "$BUILD_DIR/zotero/chrome.manifest"
	
	echo 'pref("devtools.debugger.remote-enabled", true);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	echo 'pref("devtools.debugger.remote-port", 6100);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	echo 'pref("devtools.debugger.prompt-connection", false);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
fi

echo -n "Channel: "
grep app.update.channel "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
echo

# Remove unnecessary files
${GFIND} "$BUILD_DIR" -name .DS_Store -exec rm -f {} \;
rm -rf "$BUILD_DIR/zotero/test"

cd "$CALLDIR"

# Mac
if [ $BUILD_MAC == 1 ]; then
	echo 'Building Jurism.app'
		
	# Set up directory structure
	APPDIR="$STAGE_DIR/Jurism.app"
	rm -rf "$APPDIR"
	mkdir "$APPDIR"
	chmod 755 "$APPDIR"
	cp -r "$CALLDIR/mac/Contents" "$APPDIR"
	CONTENTSDIR="$APPDIR/Contents"
	
	# Modify platform-specific prefs
	perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_MAC"'/g' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	# Fix horizontal mousewheel scrolling (this is set to 4 in the Fx60 .app greprefs.js, but
	# defaults to 1 in later versions of Firefox, and needs to be 1 to work on macOS)
	echo 'pref("mousewheel.with_shift.action", 1);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	
	# Merge relevant assets from Firefox
	mkdir "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/MacOS/"!(firefox|firefox-bin|crashreporter.app|pingsender|updater.app) "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/Resources/"!(application.ini|updater.ini|update-settings.ini|browser|devtools-files|precomplete|removed-files|webapprt*|*.icns|defaults|*.lproj) "$CONTENTSDIR/Resources"

	# Use our own launcher
	cp "$CALLDIR/mac/jurism" "$CONTENTSDIR/MacOS/jurism"
	cp "$BUILD_DIR/application.ini" "$CONTENTSDIR/Resources"

	# TEMP: Modified versions of some Firefox components for Big Sur, placed in xulrunner/MacOS
	cp "$MAC_RUNTIME_PATH/../MacOS/"{libc++.1.dylib,libnss3.dylib,XUL} "$CONTENTSDIR/MacOS/"

	# Use our own updater, because Mozilla's requires updates signed by Mozilla
	cd "$CONTENTSDIR/MacOS"
	tar -xjf "$CALLDIR/mac/updater.tar.bz2"

	# Copy PDF tools and data
	cp "$CALLDIR/pdftools/pdftotext-mac" "$CONTENTSDIR/MacOS/pdftotext"
	cp "$CALLDIR/pdftools/pdfinfo-mac" "$CONTENTSDIR/MacOS/pdfinfo"
	cp -R "$CALLDIR/pdftools/poppler-data" "$CONTENTSDIR/Resources/"

	# Modify Info.plist
	perl -pi -e "s/\{\{VERSION\}\}/$VERSION/" "$CONTENTSDIR/Info.plist"
	perl -pi -e "s/\{\{VERSION_NUMERIC\}\}/$VERSION_NUMERIC/" "$CONTENTSDIR/Info.plist"
	if [ $UPDATE_CHANNEL == "beta" ] || [ $UPDATE_CHANNEL == "dev" ]; then
		perl -pi -e "s/org\.zotero\.zotero/org.zotero.zotero-$UPDATE_CHANNEL/" "$CONTENTSDIR/Info.plist"
	# TEMP: Necessary on Ventura until Zotero 7
	elif [ $UPDATE_CHANNEL == "source" ]; then
		perl -pi -e "s/org\.zotero\.zotero/org.zotero.zotero-dev/" "$CONTENTSDIR/Info.plist"
	fi
	perl -pi -e "s/\{\{VERSION\}\}/$VERSION/" "$CONTENTSDIR/Info.plist"
	# Needed for "monkeypatch" Windows builds: 
	# http://www.nntp.perl.org/group/perl.perl5.porters/2010/08/msg162834.html
	rm -f "$CONTENTSDIR/Info.plist.bak"

	set +e
	echo
	grep -B 1 org.zotero.zotero "$CONTENTSDIR/Info.plist"
	echo
	grep -A 1 CFBundleShortVersionString "$CONTENTSDIR/Info.plist"
	echo
	grep -A 1 CFBundleVersion "$CONTENTSDIR/Info.plist"
	echo
	set -e

	# Add components
	cp -R "$BUILD_DIR/zotero/"* "$CONTENTSDIR/Resources"
	
	# Add Mac-specific Standalone assets
	cd "$CALLDIR/assets/mac"
	zip -r -q "$CONTENTSDIR/Resources/jurism.jar" *
	
	# Add devtools
	if [ $DEVTOOLS -eq 1 ]; then
		# Create devtools.jar
		cd "$BUILD_DIR"
		mkdir -p devtools/locale
		cp -r "$MAC_RUNTIME_PATH"/Contents/Resources/devtools-files/chrome/devtools/* devtools/
		cp -r "$MAC_RUNTIME_PATH"/Contents/Resources/devtools-files/chrome/locale/* devtools/locale/
		cd devtools
		zip -r -q ../devtools.jar *
		cd ..
		rm -rf devtools
		mv devtools.jar "$CONTENTSDIR/Resources/"
		
		cp "$MAC_RUNTIME_PATH/Contents/Resources/devtools-files/components/interfaces.xpt" "$CONTENTSDIR/Resources/components/"
	fi
	
	# Add word processor plug-ins
	mkdir "$CONTENTSDIR/Resources/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-mac-integration" "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$CONTENTSDIR/Resources/extensions/zoteroOpenOfficeIntegration@zotero.org"
	echo
	for ext in "zoteroMacWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
        perl -pi -e 's|^(</Description>)|        <em:targetApplication>\n                <Description>\n                        <em:id>juris-m\@juris-m.github.io</em:id>\n                        <em:minVersion>4.0</em:minVersion>\n                        <em:maxVersion>5.0.*</em:maxVersion>\n                </Description>\n        </em:targetApplication>\n${1}|' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		rm -rf "$CONTENTSDIR/Resources/extensions/$ext/.git" "$CONTENTSDIR/Resources/extensions/$ext/.github"
	done
	# Default preferenes are no longer read from built-in extensions in Firefox 60
	echo >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-word-for-mac-integration/defaults/preferences/zoteroMacWordIntegration.js" >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	echo >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	echo
    # Add Abbreviation Filter (abbrevs-filter)
	cp -RH "$CALLDIR/modules/abbrevs-filter" "$CONTENTSDIR/Resources/extensions/abbrevs-filter@juris-m.github.io"
    
    # Add Bluebook signal helper (bluebook-signals-for-zotero)
	cp -RH "$CALLDIR/modules/bluebook-signals-for-zotero" "$CONTENTSDIR/Resources/extensions/bluebook-signals-for-zotero@mystery-lab.com"
	
    # Add ODF/RTF Scan (zotero-odf-scan)
	cp -RH "$CALLDIR/modules/zotero-odf-scan-plugin" "$CONTENTSDIR/Resources/extensions/rtf-odf-scan-for-zotero@mystery-lab.com"
	
	# Delete extraneous files
	${GFIND} "$CONTENTSDIR" -depth -type d -name .git -exec rm -rf {} \;
	${GFIND} "$CONTENTSDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
	${GFIND} "$CONTENTSDIR/Resources/extensions" -depth -type d -name build -exec rm -rf {} \;
	${GFIND} "$CONTENTSDIR/Resources/extensions" -depth -type d -name node_modules -exec rm -rf {} \;

	# Copy over removed-files and make a precomplete file since it
	# needs to be stable for the signature
	cp "$CALLDIR/update-packaging/removed-files_mac" "$CONTENTSDIR/Resources/removed-files"
	touch "$CONTENTSDIR/Resources/precomplete"
	
	# Sign
	if [ $SIGN == 1 ]; then
		# Unlock keychain if a password is provided (necessary for building from a shell)
		if [ -n "$KEYCHAIN_PASSWORD" ]; then
			security -v unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/$KEYCHAIN.keychain-db
		fi
		# Clear extended attributes, which can cause codesign to fail
		/usr/bin/xattr -cr "$APPDIR"

		# Sign app
		entitlements_file="$CALLDIR/mac/entitlements.xml"
		/usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" \
			"$APPDIR/Contents/MacOS/pdftotext" \
			"$APPDIR/Contents/MacOS/pdfinfo" \
			"$APPDIR/Contents/MacOS/XUL" \
			"$APPDIR/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater"
		find "$APPDIR/Contents" -name '*.dylib' -exec /usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" {} \;
		find "$APPDIR/Contents" -name '*.app' -exec /usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" {} \;
		/usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" "$APPDIR/Contents/MacOS/zotero"
		
		# Bundle and sign Safari App Extension
		#
		# Even though it's signed by Xcode, we sign it again to make sure it matches the parent app signature
		if [[ -n "$SAFARI_APPEX" ]] && [[ -d "$SAFARI_APPEX" ]]; then
			echo
			# Extract entitlements, which differ from parent app
			/usr/bin/codesign -d --entitlements :"$BUILD_DIR/safari-entitlements.plist" $SAFARI_APPEX
			mkdir "$APPDIR/Contents/PlugIns"
			cp -R $SAFARI_APPEX "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex"
			# Add suffix to appex bundle identifier
			if [ $UPDATE_CHANNEL == "beta" ] || [ $UPDATE_CHANNEL == "dev" ] || [ $UPDATE_CHANNEL == "source" ]; then
				perl -pi -e "s/org\.zotero\.SafariExtensionApp\.SafariExtension/org.zotero.SafariExtensionApp.SafariExtension-$UPDATE_CHANNEL/" "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex/Contents/Info.plist"
			fi
			find "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex/Contents" -name '*.dylib' -exec /usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" {} \;
			/usr/bin/codesign --force --options runtime --entitlements "$BUILD_DIR/safari-entitlements.plist" --sign "$DEVELOPER_ID" "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex"
		fi
		
		# Sign final app package
		echo
		/usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" "$APPDIR"
		
		# Verify app
		/usr/bin/codesign --verify -vvvv "$APPDIR"
		# Verify Safari App Extension
		if [[ -n "$SAFARI_APPEX" ]] && [[ -d "$SAFARI_APPEX" ]]; then
			echo
			/usr/bin/codesign --verify -vvvv "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex"
		fi
	fi
	echo FINISHED BASIC BUNDLING I GUESS
	# Build and notarize disk image
	if [ $PACKAGE == 1 ]; then
		echo PACKAGE TOGGLE OK
		if [ $MAC_NATIVE == 1 ]; then
			echo MAC_NATIVE OK
			echo "Creating Mac installer"
			dmg="$DIST_DIR/Jurism-$VERSION.dmg"
			"$CALLDIR/mac/pkg-dmg" --source "$STAGE_DIR/Jurism.app" \
				--target "$dmg" \
				--sourcefile --volname Jurism --copy "$CALLDIR/mac/DSStore:/.DS_Store" \
				--symlink /Applications:"/Drag Here to Install" > /dev/null
		  #if [ false ]; then	
#			# Upload disk image to Apple
#			output=$("$CALLDIR/scripts/notarize_mac_app" "$dmg")
#			echo
#			echo "$output"
#			echo
#			id=$(echo "$output" | plutil -extract notarization-upload.RequestUUID xml1 -o - - | sed -n "s/.*<string>\(.*\)<\/string>.*/\1/p")
#			echo "Notarization request identifier: $id"
#			echo
#			
#			sleep 60
#			
#			# Check back every 30 seconds, for up to an hour
#			i="0"
#			while [ $i -lt 120 ]
#			do
#				status=$("$CALLDIR/scripts/notarization_status" $id)
#				if [[ $status != "in progress" ]]; then
#					break
#				fi
#				echo "Notarization in progress"
#				sleep 30
#				i=$[$i+1]
#			done
#			
#			# Staple notarization info to disk image
#			if [ $status == "success" ]; then
#				"$CALLDIR/scripts/notarization_stapler" "$dmg"
#			else
#				echo "Notarization failed!"
#
#				"$CALLDIR/scripts/notarization_status" $id
#				exit 1
#			fi
#			
#			echo "Notarization complete"
#		     fi
		else
			echo 'Not building on Mac; creating Mac distribution as a zip file'
			rm -f "$DIST_DIR/Jurism_mac.zip"
			cd "$STAGE_DIR" && zip -rqX "$DIST_DIR/Jurism-$VERSION.zip" Jurism.app
		fi
	fi
fi

# Win32
if [ $BUILD_WIN32 == 1 ]; then
	echo 'Building Jurism_win32'
	
	# Set up directory
	APPDIR="$STAGE_DIR/Jurism_win32"
	rm -rf "$APPDIR"
	mkdir "$APPDIR"
	
	# Modify platform-specific prefs
	perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_WIN"'/g' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	
	# Copy relevant assets from Firefox
	cp -R "$WIN32_RUNTIME_PATH"/!(application.ini|browser|defaults|devtools-files|crashreporter*|firefox.exe|maintenanceservice*|precomplete|removed-files|uninstall|update*) "$APPDIR"

	## JURISM, PRE-fx60
	## Copy jurism.exe, which is xulrunner-stub from https://github.com/duanyao/xulrunner-stub
	## modified with ReplaceVistaIcon.exe and edited with Resource Hacker
	##
	##   "$CALLDIR/win/ReplaceVistaIcon/ReplaceVistaIcon.exe" \
	##       "`cygpath -w \"$APPDIR/jurism.exe\"`" \
	##       "`cygpath -w \"$CALLDIR/assets/icons/default/main-window.ico\"`"
	##
	#cp "$CALLDIR/win/jurism.exe" "$APPDIR"

	# Copy zotero_win32.exe, which is built directly from Firefox source
	#
	# After the initial build the temporary resource in "C:\mozilla-source\obj-i686-pc-mingw32\browser\app\module.res"
	# is modified with Visual Studio resource editor where icon and file details are changed.
	# Then firefox.exe is rebuilt again
	cp "$CALLDIR/win/zotero_win32.exe" "$APPDIR/jurism.exe"
	
	# Update .exe version number (only possible on Windows)
	if [ $WIN_NATIVE == 1 ]; then
		# FileVersion is limited to four integers, so it won't be properly updated for non-release
		# builds (e.g., we'll show 5.0.97.0 for 5.0.97-beta.37). ProductVersion will be the full
		# version string.
		rcedit "`cygpath -w \"$APPDIR/jurism.exe\"`" \
			--set-file-version "$VERSION_NUMERIC" \
			--set-product-version "$VERSION"
	fi
	
	# Use our own updater, because Mozilla's requires updates signed by Mozilla
	cp "$CALLDIR/win/updater.exe" "$APPDIR"
	cat "$CALLDIR/win/installer/updater_append.ini" >> "$APPDIR/updater.ini"

	# Copy PDF tools and data
	cp "$CALLDIR/pdftools/pdftotext-win.exe" "$APPDIR/pdftotext.exe"
	cp "$CALLDIR/pdftools/pdfinfo-win.exe" "$APPDIR/pdfinfo.exe"
	cp -R "$CALLDIR/pdftools/poppler-data" "$APPDIR/"
	
	cp -R "$BUILD_DIR/zotero/"* "$BUILD_DIR/application.ini" "$APPDIR"
	
	# Add Windows-specific Standalone assets
	cd "$CALLDIR/assets/win"
	zip -r -q "$APPDIR/jurism.jar" *
	
	# Add devtools
	if [ $DEVTOOLS -eq 1 ]; then
		# Create devtools.jar
		cd "$BUILD_DIR"
		mkdir -p devtools/locale
		cp -r "$WIN32_RUNTIME_PATH"/devtools-files/chrome/devtools/* devtools/
		cp -r "$WIN32_RUNTIME_PATH"/devtools-files/chrome/locale/* devtools/locale/
		cd devtools
		zip -r -q ../devtools.jar *
		cd ..
		rm -rf devtools
		mv devtools.jar "$APPDIR"
		
		cp "$WIN32_RUNTIME_PATH/devtools-files/components/interfaces.xpt" "$APPDIR/components/"
	fi
	
	# Add word processor plug-ins
        mkdir "$APPDIR/extensions"
        cp -RH "$CALLDIR/modules/zotero-word-for-windows-integration" "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org"
        cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
        echo
        for ext in "zoteroWinWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
                perl -pi -e 's|^(</Description>)|        <em:targetApplication>\n                <Description>\n                        <em:id>juris-m\@juris-m.github.io</em:id>\n                        <em:minVersion>4.0</em:minVersion>\n                        <em:maxVersion>6.0.*</em:maxVersion>\n                </Description>\n        </em:targetApplication>\n${1}|' "$APPDIR/extensions/$ext/install.rdf"
                perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/$ext/install.rdf"
                echo -n "$ext Version: "
                perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/$ext/install.rdf"
                rm -rf "$APPDIR/extensions/$ext/.git"
        done
        echo
    # Add Abbreviation Filter (abbrevs-filter)
	cp -RH "$CALLDIR/modules/abbrevs-filter" "$APPDIR/extensions/abbrevs-filter@juris-m.github.io"

    # Add Bluebook signal helper (bluebook-signals-for-zotero)
	cp -RH "$CALLDIR/modules/bluebook-signals-for-zotero" "$APPDIR/extensions/bluebook-signals-for-zotero@mystery-lab.com"
	# Default preferenes are no longer read from built-in extensions in Firefox 60
	echo >> "$APPDIR/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-word-for-windows-integration/defaults/preferences/zoteroWinWordIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
	echo >> "$APPDIR/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
	echo >> "$APPDIR/defaults/preferences/prefs.js"
	echo

	# Delete extraneous files
	find "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
	find "$APPDIR" \( -name .DS_Store -or -name '.git*' -or -name '.travis.yml' -or -name update.rdf -or -name '*.bak' \) -exec rm -f {} \;
	find "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
	find "$APPDIR" \( -name '*.exe' -or -name '*.dll' \) -exec chmod 755 {} \;
	
    # Add ODF/RTF Scan (zotero-odf-scan)
	cp -RH "$CALLDIR/modules/zotero-odf-scan-plugin" "$APPDIR/extensions/rtf-odf-scan-for-zotero@mystery-lab.com"
		
	# Delete extraneous files
	${GFIND} "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
	${GFIND} "$APPDIR" \( -name .DS_Store -or -name '.git*' -or -name '.travis.yml' -or -name update.rdf -or -name '*.bak' \) -exec rm -f {} \;
	${GFIND} "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
	${GFIND} "$APPDIR" \( -name '*.exe' -or -name '*.dll' \) -exec chmod 755 {} \;
	${GFIND} "$APPDIR/extensions" -depth -type d -name node_modules -exec rm -rf {} \;


	if [ $PACKAGE == 1 ]; then
		if [ $WIN_NATIVE == 1 ]; then
			INSTALLER_PATH="$DIST_DIR/Jurism-${VERSION}_setup.exe"
			
			echo 'Creating Windows installer'
			# Copy installer files
			cp -r "$CALLDIR/win/installer" "$BUILD_DIR/win_installer"
			
			# Build and sign uninstaller
			perl -pi -e "s/\{\{VERSION}}/$VERSION/" "$BUILD_DIR/win_installer/defines.nsi"
			"`cygpath -u \"${NSIS_DIR}makensis.exe\"`" /V1 "`cygpath -w \"$BUILD_DIR/win_installer/uninstaller.nsi\"`"
			mkdir "$APPDIR/uninstall"
			mv "$BUILD_DIR/win_installer/helper.exe" "$APPDIR/uninstall"
			
			# Sign zotero.exe, updater, uninstaller and PDF tools
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC" \
					/du "$SIGNATURE_URL" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/jurism.exe\"`"
				sleep $SIGNTOOL_DELAY

				#
				# Windows doesn't check DLL signatures
				#
				#for dll in "$APPDIR/"*.dll "$APPDIR/"*.dll; do
				#	"`cygpath -u \"$SIGNTOOL\"`" \
				#		sign /n "$SIGNTOOL_CERT_SUBJECT" \
				#		/d "$SIGNATURE_DESC" \
				#		/fd SHA256 \
				#		/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
				#		/td SHA256 \
				#		"`cygpath -w \"$dll\"`"
				#done
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Updater" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/updater.exe\"`"
				sleep $SIGNTOOL_DELAY
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Uninstaller" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/uninstall/helper.exe\"`"
				sleep $SIGNTOOL_DELAY
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC PDF Converter" \
					/fd SHA256 \
                                        /tr "$SIGNTOOL_TIMESTAMP_SERVER" \
                                        /td SHA256 \
					"`cygpath -w \"$APPDIR/pdftotext.exe\"`"
				sleep $SIGNTOOL_DELAY
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC PDF Info" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/pdfinfo.exe\"`"
				sleep $SIGNTOOL_DELAY
			fi
			
			# Stage installer
			INSTALLER_STAGE_DIR="$BUILD_DIR/win_installer/staging"
			mkdir "$INSTALLER_STAGE_DIR"
			cp -R "$APPDIR" "$INSTALLER_STAGE_DIR/core"
			
			# Build and sign setup.exe
			"`cygpath -u \"${NSIS_DIR}makensis.exe\"`" /V1 "`cygpath -w \"$BUILD_DIR/win_installer/installer.nsi\"`"
			mv "$BUILD_DIR/win_installer/setup.exe" "$INSTALLER_STAGE_DIR"
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Setup" \
					/du "$SIGNATURE_URL" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$INSTALLER_STAGE_DIR/setup.exe\"`"
				sleep $SIGNTOOL_DELAY
			fi
			
			# Compress application
			cd "$INSTALLER_STAGE_DIR" && 7z a -r -t7z "`cygpath -w \"$BUILD_DIR/app_win32.7z\"`" \
				-mx -m0=BCJ2 -m1=LZMA:d24 -m2=LZMA:d19 -m3=LZMA:d19  -mb0:1 -mb0s1:2 -mb0s2:3 > /dev/null
				
			# Compress 7zSD.sfx
			upx --best -o "`cygpath -w \"$BUILD_DIR/7zSD.sfx\"`" \
				"`cygpath -w \"$CALLDIR/win/installer/7zstub/firefox/7zSD.sfx\"`" > /dev/null
			
			# Combine 7zSD.sfx and app.tag into setup.exe
			cat "$BUILD_DIR/7zSD.sfx" "$CALLDIR/win/installer/app.tag" \
				"$BUILD_DIR/app_win32.7z" > "$INSTALLER_PATH"
			
			# Sign Zotero_setup.exe
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Setup" \
					/du "$SIGNATURE_URL" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
                                        /td SHA256 \
					"`cygpath -w \"$INSTALLER_PATH\"`"
			fi
			
			chmod 755 "$INSTALLER_PATH"
		else
			echo 'Not building on Windows; only building zip file'
		fi
		cd "$STAGE_DIR" && zip -rqX "$DIST_DIR/Jurism-${VERSION}_win32.zip" Jurism_win32
	fi
fi

# Linux
if [ $BUILD_LINUX == 1 ]; then
	for arch in "i686" "x86_64"; do
		RUNTIME_PATH=`eval echo '$LINUX_'$arch'_RUNTIME_PATH'`
		
		# Set up directory
		echo 'Building Jurism_linux-'$arch
		APPDIR="$STAGE_DIR/Jurism_linux-$arch"
		rm -rf "$APPDIR"
		mkdir "$APPDIR"
		
		# Merge relevant assets from Firefox
		cp -r "$RUNTIME_PATH/"!(application.ini|browser|defaults|devtools-files|crashreporter|crashreporter.ini|firefox-bin|pingsender|precomplete|removed-files|run-mozilla.sh|update-settings.ini|updater|updater.ini) "$APPDIR"
		
		# Use our own launcher that calls the original Firefox executable with -app
		mv "$APPDIR"/firefox "$APPDIR"/jurism-bin
		cp "$CALLDIR/linux/jurism" "$APPDIR"/jurism
		
		# Copy Ubuntu launcher files
		cp "$CALLDIR/linux/jurism.desktop" "$APPDIR"
		cp "$CALLDIR/linux/set_launcher_icon" "$APPDIR"
		
		# Use our own updater, because Mozilla's requires updates signed by Mozilla
		cp "$CALLDIR/linux/updater-$arch" "$APPDIR"/updater

		# Copy PDF tools and data
		cp "$CALLDIR/pdftools/pdftotext-linux-$arch" "$APPDIR/pdftotext"
		cp "$CALLDIR/pdftools/pdfinfo-linux-$arch" "$APPDIR/pdfinfo"
		cp -R "$CALLDIR/pdftools/poppler-data" "$APPDIR/"
		
		cp -R "$BUILD_DIR/zotero/"* "$BUILD_DIR/application.ini" "$APPDIR"
		
		# Modify platform-specific prefs
		perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
        perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_LINUX"'/g' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
		
		# Add Unix-specific Standalone assets
		cd "$CALLDIR/assets/unix"
		zip -0 -r -q "$APPDIR/jurism.jar" *
		
		# Add devtools
		if [ $DEVTOOLS -eq 1 ]; then
			# Create devtools.jar
			cd "$BUILD_DIR"
			mkdir -p devtools/locale
			cp -r "$RUNTIME_PATH"/devtools-files/chrome/devtools/* devtools/
			cp -r "$RUNTIME_PATH"/devtools-files/chrome/locale/* devtools/locale/
			cd devtools
			zip -r -q ../devtools.jar *
			cd ..
			rm -rf devtools
			mv devtools.jar "$APPDIR"
			
			cp "$RUNTIME_PATH/devtools-files/components/interfaces.xpt" "$APPDIR/components/"
		fi
        
		# Add word processor plug-ins
		mkdir "$APPDIR/extensions"
		cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
		perl -pi -e 's|^(</Description>)|        <em:targetApplication>\n                <Description>\n                        <em:id>juris-m\@juris-m.github.io</em:id>\n                        <em:minVersion>4.0</em:minVersion>\n                        <em:maxVersion>5.0.*</em:maxVersion>\n                </Description>\n        </em:targetApplication>\n${1}|' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		echo -n "zoteroOpenOfficeIntegration@zotero.org Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		rm -rf "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/.git"
		rm -rf "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/.git" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/.github"
        
        # Add Abbreviation Filter (abbrevs-filter)
		cp -RH "$CALLDIR/modules/abbrevs-filter" "$APPDIR/extensions/abbrevs-filter@juris-m.github.io"

        # Add Bluebook signal helper (bluebook-signals-for-zotero)
		cp -RH "$CALLDIR/modules/bluebook-signals-for-zotero" "$APPDIR/extensions/bluebook-signals-for-zotero@mystery-lab.com"
		
        # Add ODF/RTF Scan (zotero-odf-scan)
		cp -RH "$CALLDIR/modules/zotero-odf-scan-plugin" "$APPDIR/extensions/rtf-odf-scan-for-zotero@mystery-lab.com"

		# Default preferenes are no longer read from built-in extensions in Firefox 60
		echo >> "$APPDIR/defaults/preferences/prefs.js"
		cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
		echo >> "$APPDIR/defaults/preferences/prefs.js"
		
		# Delete extraneous files
		${GFIND} "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
		${GFIND} "$APPDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
		${GFIND} "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
		${GFIND} "$APPDIR/extensions" -depth -type d -name node_modules -exec rm -rf {} \;
		
		if [ $PACKAGE == 1 ]; then
			# Create tar
			rm -f "$DIST_DIR/Jurism-${VERSION}_linux-$arch.tar.bz2"
			cd "$STAGE_DIR"
			tar -cjf "$DIST_DIR/Jurism-${VERSION}_linux-$arch.tar.bz2" "Jurism_linux-$arch"
		fi
	done
fi

rm -rf $BUILD_DIR
