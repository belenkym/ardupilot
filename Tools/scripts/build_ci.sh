#!/bin/bash
# useful script to test all the different build types that we support.
# This helps when doing large merges
# Andrew Tridgell, November 2011

set -ex

. ~/.profile

# CXX and CC are exported by default by travis
#unset CXX CC

export BUILDROOT=/tmp/travis.build.$$
rm -rf $BUILDROOT

# If CI_BUILD_TARGET is not set, default to all of them
if [ -z "$CI_BUILD_TARGET" ]; then
    CI_BUILD_TARGET="sitl linux navio raspilot minlure bebop px4-v2 px4-v4"
fi

declare -A build_platforms
declare -A build_concurrency
declare -A build_extra_clean
declare -A waf_supported_boards

build_platforms=(  ["ArduPlane"]="navio raspilot minlure bebop sitl linux px4-v2"
                   ["ArduCopter"]="navio raspilot minlure bebop sitl linux px4-v2 px4-v4"
                   ["APMrover2"]="navio raspilot minlure bebop sitl linux px4-v2"
                   ["AntennaTracker"]="navio raspilot minlure bebop sitl linux px4-v2"
                   ["Tools/Replay"]="linux")

build_concurrency=(["navio"]="-j2"
                   ["raspilot"]="-j2"
                   ["minlure"]="-j2"
                   ["bebop"]="-j2"
                   ["sitl"]="-j2"
                   ["linux"]="-j2"
                   ["px4-v2"]=""
                   ["px4-v4"]="")

build_extra_clean=(["px4-v2"]="make px4-cleandep")

# special case for SITL testing in CI
if [ "$CI_BUILD_TARGET" = "sitltest" ]; then
    echo "Installing pymavlink"
    git submodule init
    git submodule update
    (cd modules/mavlink/pymavlink && python setup.py build install --user)
    unset BUILDROOT
    echo "Running SITL QuadCopter test"
    Tools/autotest/autotest.py -j2 build.ArduCopter fly.ArduCopter
    echo "Running SITL QuadPlane test"
    Tools/autotest/autotest.py -j2 build.ArduPlane fly.QuadPlane
    exit 0
fi

waf=modules/waf/waf-light

# get list of boards supported by the waf build
for board in $($waf list_boards | head -n1); do waf_supported_boards[$board]=1; done

touch build.log

dump_output() {
   echo Tailing the last 5000 lines of output:
   tail -5000 build.log  
}
error_handler() {
  echo ERROR: An error was encountered with the build.
  dump_output
  exit 1
}
# If an error occurs, run our error handler to output a tail of the build
trap 'error_handler' ERR

# Set up a repeating loop to send some output to Travis.

bash -c "while true; do echo \$(date) - building ...; sleep 30s; done" &
PING_LOOP_PID=$!

if [ $CC = 'clang' ]; then
  export CC="arm-linux-gnueabihf-clang"
  export CXX="arm-linux-gnueabihf-clang++"
  export CCACHE_CPP2=yes
  export CXXFLAGS="-Qunused-arguments -fcolor-diagnostics -Wno-unknown-warning-option -Wno-gnu-designator -Wno-inconsistent-missing-override -Wno-mismatched-tags -Wno-gnu-variable-sized-type-not-at-end -Wno-unknown-pragmas -Wno-c++11-narrowing"
fi

echo "Targets: $CI_BUILD_TARGET"
for t in $CI_BUILD_TARGET; do
    # echo "Starting make based build for target ${t}..."
    # for v in ${!build_platforms[@]}; do
        # if [[ ${build_platforms[$v]} != *$t* ]]; then
            # continue
        # fi
        # echo "Building $v for ${t}..."

        # pushd $v
        # make clean
        # if [ ${build_extra_clean[$t]+_} ]; then
            # ${build_extra_clean[$t]}
        # fi

        # make $t ${build_concurrency[$t]}
        # popd
    # done

    if [[ -n ${waf_supported_boards[$t]} ]]; then
        echo "Starting waf build for board ${t}..."
        $waf configure --board $t --enable-benchmarks
        $waf clean
		which $CC
        $waf -vv ${build_concurrency[$t]} copter >> build.log 2>&1
        if [[ $t == linux ]]; then
            $waf check
        fi
    fi
done

# nicely terminate the ping output loop
kill $PING_LOOP_PID

# The build finished without returning an error so dump a tail of the output
dump_output

echo build OK
exit 0
