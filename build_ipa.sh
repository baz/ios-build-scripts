#!/bin/bash
# Below are required environment variables with some example content:
# SDK='iphoneos4.1'
# FORMATTED_TARGET_LIST='-alltargets'
# CONFIGURATION='Ad Hoc'
# DISTRIBUTION_CERTIFICATE='iPhone Distribution: Your Company Pty Ltd'
# PROVISIONING_PROFILE_PATH='/Users/tomcat/Library/MobileDevice/Provisioning Profiles/Your_Company_Ad_Hoc.mobileprovision'
# GIT_BINARY='/usr/local/git/bin/git'
# REMOTE_HOST='your.remote.host.com'
# REMOTE_PARENT_PATH='/www/docs/ios_builds'
# MANIFEST_SCRIPT_LOCATION='http://git.yourserver.com/ios-build-scripts/ios-build-scripts/blobs/raw/master/generate_manifest.py'
# ROOT_DEPLOYMENT_ADDRESS='http://your.remote.host.com/ios_builds'
# ARCHIVE_FILENAME='beta_archive.zip'
# KEYCHAIN_LOCATION='/Users/tomcat/Library/Keychains/Your Company.keychain'
# KEYCHAIN_PASSWORD='Password'

# Build project
security default-keychain -s "$KEYCHAIN_LOCATION"
security unlock-keychain -p $KEYCHAIN_PASSWORD "$KEYCHAIN_LOCATION"
xcodebuild -sdk "$SDK" $FORMATTED_TARGET_LIST -configuration "$CONFIGURATION" clean build

GIT_HASH=$(git log --pretty=format:'' | wc -l)-$($GIT_BINARY rev-parse --short HEAD)
BUILD_DIRECTORY="$(pwd)/build/${CONFIGURATION}-iphoneos"
cd "$BUILD_DIRECTORY" || die "Build directory does not exist."
MANIFEST_SCRIPT=$(curl -fsS $MANIFEST_SCRIPT_LOCATION)
MANIFEST_OUTPUT_HTML_FILENAME='index.html'
MANIFEST_OUTPUT_MANIFEST_FILENAME='manifest.plist'
for APP_FILENAME in *.app; do
	APP_NAME=$(echo "$APP_FILENAME" | sed -e 's/.app//')
	IPA_FILENAME="$APP_NAME.ipa"
	DSYM_FILEPATH="$APP_FILENAME.dSYM"

	/usr/bin/xcrun -sdk iphoneos PackageApplication -v "$APP_FILENAME" -o "$BUILD_DIRECTORY/$IPA_FILENAME" --sign "$DISTRIBUTION_CERTIFICATE" --embed "$PROVISIONING_PROFILE_PATH"

	# Create legacy archive for pre iOS4.0 users
	cp "$PROVISIONING_PROFILE_PATH" .
	PROVISIONING_PROFILE_FILENAME=$(basename "$PROVISIONING_PROFILE_PATH")
	zip "$ARCHIVE_FILENAME" "$IPA_FILENAME" "$PROVISIONING_PROFILE_FILENAME"
	rm "$PROVISIONING_PROFILE_FILENAME"

	# Output of this is index.html and manifest.plist
	python -c "$MANIFEST_SCRIPT" -f "$APP_FILENAME" -d "$ROOT_DEPLOYMENT_ADDRESS/$APP_NAME/$GIT_HASH/$MANIFEST_OUTPUT_MANIFEST_FILENAME" -a "$ARCHIVE_FILENAME"

	# Create tarball with .ipa, dSYM directory, legacy build and generated manifest files and scp them all across
	PAYLOAD_FILENAME='payload.tar'
	tar -cf $PAYLOAD_FILENAME "$IPA_FILENAME" "$DSYM_FILEPATH" "$ARCHIVE_FILENAME" "$MANIFEST_OUTPUT_HTML_FILENAME" "$MANIFEST_OUTPUT_MANIFEST_FILENAME"

	QUOTE='"'
	ssh $REMOTE_HOST "cd $REMOTE_PARENT_PATH; rm -rf ${QUOTE}$APP_NAME${QUOTE}; mkdir -p ${QUOTE}$APP_NAME${QUOTE}/$GIT_HASH;"
	scp "$PAYLOAD_FILENAME" "$REMOTE_HOST:$REMOTE_PARENT_PATH/${QUOTE}$APP_NAME${QUOTE}/$GIT_HASH"
	ssh $REMOTE_HOST "cd $REMOTE_PARENT_PATH/${QUOTE}$APP_NAME${QUOTE}/$GIT_HASH; tar -xf $PAYLOAD_FILENAME; rm $PAYLOAD_FILENAME"

	# Clean up
	rm "$IPA_FILENAME"
	rm "$ARCHIVE_FILENAME"
	rm "$MANIFEST_OUTPUT_HTML_FILENAME"
	rm "$MANIFEST_OUTPUT_MANIFEST_FILENAME"
	rm "$PAYLOAD_FILENAME"
done
