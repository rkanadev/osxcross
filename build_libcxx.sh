#!/usr/bin/env bash

pushd "${0%/*}" &>/dev/null

export LC_ALL="C"

`tools/osxcross_conf.sh`

if [ $? -ne 0 ]; then
    echo "you need to complete ./build.sh first, before you can start building libc++"
    exit 1
fi


set -e

eval `osxcross-conf`

if [ `echo "${OSXCROSS_SDK_VERSION}<10.7" | bc -l` -eq 1 ]; then
    echo "you must use the SDK from 10.7 or newer to get libc++ compiled"
    exit 1
fi

# How many concurrent jobs should be used for compiling?
JOBS=`tools/get_cpu_count.sh`

# libc++ version to build
LIBCXX_VERSION=3.3

function require
{
    which $1 &>/dev/null
    while [ $? -ne 0 ]
    do
        echo ""
        read -p "Install $1 then press enter"
        which $1 &>/dev/null
    done
}

BASE_DIR=`pwd`

set +e
require wget
require cmake
set -e

pushd $OSXCROSS_BUILD_DIR

trap 'test $? -eq 0 || rm -f $OSXCROSS_BUILD_DIR/have_libcxx*' EXIT

if [ ! -f "have_libcxx_${LIBCXX_VERSION}_${OSXCROSS_TARGET}" ]; then

pushd $OSXCROSS_TARBALL_DIR
wget -c "http://llvm.org/releases/3.3/libcxx-${LIBCXX_VERSION}.src.tar.gz"
popd

tar xzfv "$OSXCROSS_TARBALL_DIR/libcxx-${LIBCXX_VERSION}.src.tar.gz"
pushd libcxx-${LIBCXX_VERSION}*
rm -rf build
mkdir build

pushd build

# remove conflicting versions
rm -rf $OSXCROSS_SDK/usr/include/c++/v1
rm -rf $OSXCROSS_SDK/usr/lib/libc++.dylib
rm -rf $OSXCROSS_SDK/usr/lib/libc++.*.dylib

function cmakeerror()
{
    echo -e "\e[1m"
    echo "It looks like CMake failed."
    echo "If you see something like:"
    echo -e "\e[31m"
    echo "CMake Error at /usr/share/cmake-2.8/Modules/Platform/Darwin.cmake:<LINE NUMBER> (list):"
    echo "  list sub-command REMOVE_DUPLICATES requires list to be present."
    echo -e "\e[0m\e[1m"
    echo "Then either remove this line (look for the LINE NUMBER) or comment it out (with #) in /usr/share/cmake-.../Modules/Platform/Darwin.cmake"
    echo "It appears to be a bug in CMake."
    echo ""
    echo "Then re-run this script."
    echo -e "\e[0m"
    exit 1
}

cmake .. \
    -DCMAKE_CXX_COMPILER=x86_64-apple-$OSXCROSS_TARGET-clang++ \
    -DCMAKE_C_COMPILER=x86_64-apple-$OSXCROSS_TARGET-clang \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_OSX_SYSROOT=$OSXCROSS_SDK \
    -DLIBCXX_ENABLE_SHARED=No \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$OSXCROSS_SDK/../libcxx_$OSXCROSS_SDK_VERSION \
    -DCMAKE_AR=$OSXCROSS_CCTOOLS_PATH/x86_64-apple-$OSXCROSS_TARGET-ar \
    -DCMAKE_RANLIB=$OSXCROSS_CCTOOLS_PATH/x86_64-apple-$OSXCROSS_TARGET-ranlib \
    -DCMAKE_CXX_FLAGS="-arch i386 -arch x86_64" || cmakeerror

make -j$JOBS
make install -j$JOBS

popd #build
popd #libcxx

touch "have_libcxx_${LIBCXX_VERSION}_${OSXCROSS_TARGET}"

fi #have libcxx

popd #build dir

function test_compiler_clang
{
    echo -ne "testing $2 -stdlib=libc++ ... "
    $1 $3 -O2 -stdlib=libc++ -std=c++11 -Wall -o test
    rm test
    echo "ok"
}

function test_compiler_gcc
{
    echo -ne "testing $2 ... "
    $1 $3 -O2 -std=c++0x -Wall -o test
    rm test
    echo "ok"
}

HAVE_GCC=0

echo ""
echo "testing libc++ (including a lot c++11 headers + linking a small test program)"
echo ""

test_compiler_clang i386-apple-$OSXCROSS_TARGET-clang++ o32-clang++ $BASE_DIR/oclang/test_libcxx.cpp
test_compiler_clang x86_64-apple-$OSXCROSS_TARGET-clang++ o64-clang++ $BASE_DIR/oclang/test_libcxx.cpp

which i386-apple-$OSXCROSS_TARGET-g++-libc++ &>/dev/null && \
    HAVE_GCC=1 \
    test_compiler_gcc i386-apple-$OSXCROSS_TARGET-g++-libc++ o32-g++-libc++ $BASE_DIR/oclang/test_libcxx.cpp

which x86_64-apple-$OSXCROSS_TARGET-g++-libc++ &>/dev/null && \
    HAVE_GCC=1 && \
    test_compiler_gcc x86_64-apple-$OSXCROSS_TARGET-g++-libc++ o64-g++-libc++ $BASE_DIR/oclang/test_libcxx.cpp

echo ""
echo "Done!"
echo ""
echo "Example usage:"
echo ""
if [ $HAVE_GCC -eq 1 ]; then
echo "Clang:"
echo ""
fi
echo "Example 1: o32-clang++ -stdlib=libc++ -Wall test.cpp -o test"
echo "Example 2: o64-clang++ -stdlib=libc++ -std=c++11 -Wall test.cpp"
echo "Example 3: o32-clang++-libc++ -Wall test.cpp -o test"
echo "Example 4: o64-clang++-libc++ -std=c++11 -Wall test.cpp -o test"
echo "Example 5: x86_64-apple-$OSXCROSS_TARGET-clang++-libc++ -Wall test.cpp -o test"
echo "Example 6: i386-apple-$OSXCROSS_TARGET-clang++-libc++ -std=c++11 -Wall test.cpp -o test"
echo ""
if [ $HAVE_GCC -eq 1 ]; then
echo "GCC:"
echo ""
echo "Example 1: o32-g++-libc++ -Wall test.cpp -o test"
echo "Example 2: o64-g++-libc++ -std=c++1y -Wall test.cpp -o test"
echo "Example 3: x86_64-apple-$OSXCROSS_TARGET-g++-libc++ -Wall test.cpp -o test"
echo "Example 4: i386-apple-$OSXCROSS_TARGET-g++-libc++ -std=c++1y -Wall test.cpp -o test"
echo ""
fi
