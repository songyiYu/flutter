#!/usr/bin/env bash
# Copyright 2014 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -e

function deploy {
  local total_tries="$1"
  local remaining_tries=$(($total_tries - 1))
  shift
  while [[ "$remaining_tries" > 0 ]]; do
    (cd "$FLUTTER_ROOT/dev/docs" && firebase --debug deploy --token "$FIREBASE_TOKEN" --project "$@") && break
    remaining_tries=$(($remaining_tries - 1))
    echo "Error: Unable to deploy documentation to Firebase. Retrying in five seconds... ($remaining_tries tries left)"
    sleep 5
  done

  [[ "$remaining_tries" == 0 ]] && {
    echo "Command still failed after $total_tries tries: '$@'"
    cat firebase-debug.log || echo "Unable to show contents of firebase-debug.log."
    return 1
  }
  return 0
}

function script_location() {
  local script_location="${BASH_SOURCE[0]}"
  # Resolve symlinks
  while [[ -h "$script_location" ]]; do
    DIR="$(cd -P "$( dirname "$script_location")" >/dev/null && pwd)"
    script_location="$(readlink "$script_location")"
    [[ "$script_location" != /* ]] && script_location="$DIR/$script_location"
  done
  echo "$(cd -P "$(dirname "$script_location")" >/dev/null && pwd)"
}

function generate_docs() {
    # Install and activate dartdoc.
    "$PUB" global activate dartdoc 0.32.1

    # This script generates a unified doc set, and creates
    # a custom index.html, placing everything into dev/docs/doc.
    (cd "$FLUTTER_ROOT/dev/tools" && "$FLUTTER" pub get)
    (cd "$FLUTTER_ROOT/dev/tools" && "$PUB" get)
    (cd "$FLUTTER_ROOT" && "$DART" --disable-dart-dev "$FLUTTER_ROOT/dev/tools/dartdoc.dart")
    (cd "$FLUTTER_ROOT" && "$DART" --disable-dart-dev "$FLUTTER_ROOT/dev/tools/java_and_objc_doc.dart")
}

# Zip up the docs so people can download them for offline usage.
function create_offline_zip() {
  # Must be run from "$FLUTTER_ROOT/dev/docs"
  echo "$(date): Zipping Flutter offline docs archive."
  rm -rf flutter.docs.zip doc/offline
  (cd ./doc; zip -r -9 -q ../flutter.docs.zip .)
}

# Generate the docset for Flutter docs for use with Dash, Zeal, and Velocity.
function create_docset() {
  # Must be run from "$FLUTTER_ROOT/dev/docs"
  # Must have dashing installed: go get -u github.com/technosophos/dashing
  # Dashing produces a LOT of log output (~30MB), so we redirect it, and just
  # show the end of it if there was a problem.
  echo "$(date): Building Flutter docset."
  rm -rf flutter.docset
  # If dashing gets stuck, Cirrus will time out the build after an hour, and we
  # never get to see the logs. Thus, we run it in the background and tail the logs
  # while we wait for it to complete.
  dashing_log=/tmp/dashing.log
  dashing build --source ./doc --config ./dashing.json > $dashing_log 2>&1 &
  dashing_pid=$!
  wait $dashing_pid && \
  cp ./doc/flutter/static-assets/favicon.png ./flutter.docset/icon.png && \
  "$DART" --disable-dart-dev ./dashing_postprocess.dart && \
  tar cf flutter.docset.tar.gz --use-compress-program="gzip --best" flutter.docset
  if [[ $? -ne 0 ]]; then
      >&2 echo "Dashing docset generation failed"
      tail -200 $dashing_log
      exit 1
  fi
}

function deploy_docs() {
    # Ensure google webmaster tools can verify our site.
    cp "$FLUTTER_ROOT/dev/docs/google2ed1af765c529f57.html" "$FLUTTER_ROOT/dev/docs/doc"

    case "$CIRRUS_BRANCH" in
        master)
            echo "$(date): Updating $CIRRUS_BRANCH docs: https://master-api.flutter.dev/"
            # Disable search indexing on the master staging site so searches get only
            # the stable site.
            echo -e "User-agent: *\nDisallow: /" > "$FLUTTER_ROOT/dev/docs/doc/robots.txt"
            export FIREBASE_TOKEN="$FIREBASE_MASTER_TOKEN"
            deploy 5 master-docs-flutter-dev
            ;;
        stable)
            echo "$(date): Updating $CIRRUS_BRANCH docs: https://api.flutter.dev/"
            # Enable search indexing on the master staging site so searches get only
            # the stable site.
            echo -e "# All robots welcome!" > "$FLUTTER_ROOT/dev/docs/doc/robots.txt"
            export FIREBASE_TOKEN="$FIREBASE_PUBLIC_TOKEN"
            deploy 5 docs-flutter-dev
            ;;
        *)
            >&2 echo "Docs deployment cannot be run on the $CIRRUS_BRANCH branch."
            exit 1
    esac
}

# Move the offline archives into place, after all the processing of the doc
# directory is done. This avoids the tools recursively processing the archives
# as part of their process.
function move_offline_into_place() {
  # Must be run from "$FLUTTER_ROOT/dev/docs"
  echo "$(date): Moving offline data into place."
  mkdir -p doc/offline
  mv flutter.docs.zip doc/offline/flutter.docs.zip
  du -sh doc/offline/flutter.docs.zip
  # TODO(tvolkert): re-enable (https://github.com/flutter/flutter/issues/60646)
  # if [[ "$CIRRUS_BRANCH" == "stable" ]]; then
  #   echo -e "<entry>\n  <version>${FLUTTER_VERSION}</version>\n  <url>https://api.flutter.dev/offline/flutter.docset.tar.gz</url>\n</entry>" > doc/offline/flutter.xml
  # else
  #   echo -e "<entry>\n  <version>${FLUTTER_VERSION}</version>\n  <url>https://master-api.flutter.dev/offline/flutter.docset.tar.gz</url>\n</entry>" > doc/offline/flutter.xml
  # fi
  # mv flutter.docset.tar.gz doc/offline/flutter.docset.tar.gz
  # du -sh doc/offline/flutter.docset.tar.gz
}

# So that users can run this script from anywhere and it will work as expected.
SCRIPT_LOCATION="$(script_location)"
# Sets the Flutter root to be "$(script_location)/../..": This script assumes
# that it resides two directory levels down from the root, so if that changes,
# then this line will need to as well.
FLUTTER_ROOT="$(dirname "$(dirname "$SCRIPT_LOCATION")")"

echo "$(date): Running docs.sh"

if [[ ! -d "$FLUTTER_ROOT" || ! -f "$FLUTTER_ROOT/bin/flutter" ]]; then
  >&2 echo "Unable to locate the Flutter installation (using FLUTTER_ROOT: $FLUTTER_ROOT)"
  exit 1
fi

FLUTTER_BIN="$FLUTTER_ROOT/bin"
DART_BIN="$FLUTTER_ROOT/bin/cache/dart-sdk/bin"
FLUTTER="$FLUTTER_BIN/flutter"
DART="$DART_BIN/dart"
PUB="$DART_BIN/pub"
export PATH="$FLUTTER_BIN:$DART_BIN:$PATH"

# Make sure dart is installed by invoking flutter to download it.
"$FLUTTER" --version
FLUTTER_VERSION=$(cat "$FLUTTER_ROOT/version")

# If the pub cache directory exists in the root, then use that.
FLUTTER_PUB_CACHE="$FLUTTER_ROOT/.pub-cache"
if [[ -d "$FLUTTER_PUB_CACHE" ]]; then
  # This has to be exported, because pub interprets setting it to the empty
  # string in the same way as setting it to ".".
  export PUB_CACHE="${PUB_CACHE:-"$FLUTTER_PUB_CACHE"}"
fi

generate_docs
if [[ -n "$CIRRUS_CI" && -z "$CIRRUS_PR" ]]; then
    (cd "$FLUTTER_ROOT/dev/docs"; create_offline_zip)
    # TODO(tvolkert): re-enable (https://github.com/flutter/flutter/issues/60646)
    # (cd "$FLUTTER_ROOT/dev/docs"; create_docset)
    (cd "$FLUTTER_ROOT/dev/docs"; move_offline_into_place)
    deploy_docs
fi
