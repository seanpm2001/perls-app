#!/usr/bin/env bash

set -eEuo pipefail
shopt -s extglob;

##########################################################################
# This is the Cake bootstrapper script for Linux and OS X.
# This file was downloaded from https://github.com/cake-build/resources
# Feel free to change this file to fit your needs.
# This file has been modified from its original version to fit this need.
##########################################################################

# Define directories.
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TOOLS_DIR=$SCRIPT_DIR/tools
ADDINS_DIR=$TOOLS_DIR/Addins
MODULES_DIR=$TOOLS_DIR/Modules
NUGET_EXE=$TOOLS_DIR/nuget.exe
MANIFEST_FILE=$SCRIPT_DIR/.config/dotnet-tools.json
PACKAGES_CONFIG=$TOOLS_DIR/packages.config
PACKAGES_CONFIG_MD5=$TOOLS_DIR/packages.config.md5sum
ADDINS_PACKAGES_CONFIG=$ADDINS_DIR/packages.config
MODULES_PACKAGES_CONFIG=$MODULES_DIR/packages.config

export CAKE_PATHS_TOOLS=$TOOLS_DIR
export CAKE_PATHS_ADDINS=$ADDINS_DIR
export CAKE_PATHS_MODULES=$MODULES_DIR

# Define md5sum or md5 depending on Linux/OSX
MD5_EXE=
if [[ "$(uname -s)" == "Darwin" ]]; then
    MD5_EXE="md5 -r"
else
    MD5_EXE="md5sum"
fi

# Define default arguments.
SCRIPT=$SCRIPT_DIR/build.cake
CAKE_ARGUMENTS=()

# Parse arguments.
while [ ${#} -gt 0 ]; do
    case "${1}" in
        \-\-script=+(*))
          IFS='='; ARRAY=(${1}); unset IFS;
          SCRIPT="${ARRAY[1]-}"
        ;;
        \-\-+([a-zA-Z])=+(*)) # double dash flags ONLY (mainly to avoid parsing bugs)
          if [[ "${1}" =~ "=" ]]; then # check if we have an equals sign
            IFS='='; ARRAY=(${1}); unset IFS;

            # check that the value after the = is valid
            if [ -z "${ARRAY[1]-}" ]; then
              echo "Invalid value for flag: \"${1}\""
              exit 1
            fi

            CAKE_ARGUMENTS+=("${1}")
          elif [ -z "${2:-}" ]; then # check if 2 is bound
            # if not, we better have an equals sign
            if [[ "${1}" =~ "=" ]]; then
              IFS='='; ARRAY=(${1}); unset IFS;

              # check that the value after the = is valid
              if [ -z ${ARRAY[1]-} ]; then
                echo "Invalid value for flag: \"${1}\""
                exit 1
              fi

              CAKE_ARGUMENTS+=("${1}")
            else
              echo "Expected \"=\" or another argument for flag \"${1}\""
              exit 1
            fi
          else # if 2 is bound but we have an equals, assume "--flag value"
            echo "Please provide an equals sign to tie flags to their values."
            exit 1
          fi
        ;;
        \-+([A-Za-z])=+(*)) # single dash flags
          echo "Please use double dash flags: single dashes are unsupported, as they should be."
          exit 1
        ;;
        \-\-+([a-zA-Z])) # double dash, implicitly true
          CAKE_ARGUMENTS+=("${1}=true")
        ;;
        *)
          echo "Error: unrecognized argument ${1}"
          exit 1
        ;;
    esac
    shift
done

# Make sure the tools folder exist.
if [ ! -d "$TOOLS_DIR" ]; then
  mkdir "$TOOLS_DIR"
fi

# Make sure that packages.config exist.
if [ ! -f "$TOOLS_DIR/packages.config" ]; then
    echo "Downloading packages.config..."
    curl -Lsfo "$TOOLS_DIR/packages.config" https://cakebuild.net/download/bootstrapper/packages
    if [ $? -ne 0 ]; then
        echo "An error occurred while downloading packages.config."
        exit 1
    fi
fi

# Download NuGet if it does not exist.
if [ ! -f "$NUGET_EXE" ]; then
    echo "Downloading NuGet..."
    curl -Lsfo "$NUGET_EXE" https://dist.nuget.org/win-x86-commandline/latest/nuget.exe
    if [ $? -ne 0 ]; then
        echo "An error occurred while downloading nuget.exe."
        exit 1
    fi
fi

# Restore tools from NuGet.
pushd "$TOOLS_DIR" >/dev/null
if [ ! -f "$PACKAGES_CONFIG_MD5" ] || [ "$( cat "$PACKAGES_CONFIG_MD5" | sed 's/\r$//' )" != "$( $MD5_EXE "$PACKAGES_CONFIG" | awk '{ print $1 }' )" ]; then
    find . -type d ! -name . ! -name 'Cake.Bakery' | xargs rm -rf
fi

mono "$NUGET_EXE" install -ExcludeVersion
if [ $? -ne 0 ]; then
    echo "Could not restore NuGet tools."
    exit 1
fi

$MD5_EXE "$PACKAGES_CONFIG" | awk '{ print $1 }' >| "$PACKAGES_CONFIG_MD5"

popd >/dev/null

# Restore addins from NuGet.
if [ -f "$ADDINS_PACKAGES_CONFIG" ]; then
    pushd "$ADDINS_DIR" >/dev/null

    mono "$NUGET_EXE" install -ExcludeVersion
    if [ $? -ne 0 ]; then
        echo "Could not restore NuGet addins."
        exit 1
    fi

    popd >/dev/null
fi

# Restore modules from NuGet.
if [ -f "$MODULES_PACKAGES_CONFIG" ]; then
    pushd "$MODULES_DIR" >/dev/null

    mono "$NUGET_EXE" install -ExcludeVersion
    if [ $? -ne 0 ]; then
        echo "Could not restore NuGet modules."
        exit 1
    fi

    popd >/dev/null
fi

# Restore dotnet tools from NuGet.
if [ -f "${MANIFEST_FILE}" ]; then
  dotnet tool restore

  if [ $? -ne 0 ]; then
      echo "Could not restore dotnet tools."
      exit 1
  fi
fi

# this is to support git actions in Cake on ARM machines
# note this completely assumes building on macOS
if [ "$(arch)" = "arm64" ]; then
  ln -s ./tools/LibGit2Sharp.NativeBinaries.2.0.315-alpha.0.9/runtimes/osx-arm64/native/libgit2-b7bad55.dylib libgit2-b7bad55 || true
else
  ln -s ./tools/LibGit2Sharp.NativeBinaries.2.0.315-alpha.0.9/runtimes/osx-x64/native/libgit2-b7bad55.dylib libgit2-b7bad55 || true
fi

# Make sure that Cake has been installed as a dotnet tool.
dotnet cake --version

if [ $? -ne 0 ]; then
    echo "Unable to run Cake as a dotnet tool."
    exit 1
fi

if [[ "${CAKE_ARGUMENTS[@]+"${CAKE_ARGUMENTS[@]}"}" ]]; then
    echo "Bootstrapper parsed the following arguments:"

    for arg in "${CAKE_ARGUMENTS[@]}"; do
        echo "  $arg"
    done
else
    echo "No arguments provided."
fi

echo "Bootstrap completing, starting Cake..."

# Start Cake
exec dotnet cake "${SCRIPT}" "${CAKE_ARGUMENTS[@]+"${CAKE_ARGUMENTS[@]}"}"
