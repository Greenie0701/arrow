#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceDir,
    
    [Parameter(Mandatory=$true)]
    [string]$BuildDir
)

$ErrorActionPreference = "Stop"

$source_dir = Join-Path $SourceDir "cpp"
$build_dir = Join-Path $BuildDir "cpp"

# Set default values
if (-not $env:ARROW_OFFLINE) { $env:ARROW_OFFLINE = "OFF" }
if (-not $env:ARROW_USE_CCACHE) { $env:ARROW_USE_CCACHE = "OFF" }
if (-not $env:BUILD_DOCS_CPP) { $env:BUILD_DOCS_CPP = "OFF" }

# Configure git if available
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global --add safe.directory $SourceDir
}

# Handle threading-dependent features
if ($env:ARROW_ENABLE_THREADING -eq "OFF") {
    $env:ARROW_AZURE = "OFF"
    $env:ARROW_FLIGHT = "OFF"
    $env:ARROW_FLIGHT_SQL = "OFF"
    $env:ARROW_GCS = "OFF"
    $env:ARROW_JEMALLOC = "OFF"
    $env:ARROW_MIMALLOC = "OFF"
    $env:ARROW_S3 = "OFF"
    $env:ARROW_WITH_OPENTELEMETRY = "OFF"
}

# Show ccache statistics before build if enabled
if ($env:ARROW_USE_CCACHE -eq "ON") {
    Write-Host "===`n=== ccache statistics before build`n==="
    try {
        ccache -sv 2>$null
    } catch {
        try {
            ccache -s
        } catch {
            # Ignore if ccache not available
        }
    }
}

# Get number of processors
$n_jobs = $env:NUMBER_OF_PROCESSORS
if (-not $n_jobs) { $n_jobs = 1 }

# Create and enter build directory
if (-not (Test-Path $build_dir)) {
    New-Item -ItemType Directory -Path $build_dir -Force | Out-Null
}
Push-Location $build_dir

try {
    # Handle offline build mode
    if ($env:ARROW_OFFLINE -eq "ON") {
        $thirdparty_script = Join-Path $source_dir "thirdparty" "download_dependencies.sh"
        $thirdparty_dir = Join-Path $PWD "thirdparty"
        
        if (Test-Path $thirdparty_script) {
            bash "$thirdparty_script" "$thirdparty_dir" > enable_offline_build.sh
            . .\enable_offline_build.sh
        }
    }

    # Configure CMake arguments for ARM64 cross-compilation with vcpkg
    $cmake_args = @(
        "-DCMAKE_SYSTEM_NAME=Windows"
        "-DCMAKE_SYSTEM_PROCESSOR=ARM64"
        "-DCMAKE_C_COMPILER=clang-cl"
        "-DCMAKE_CXX_COMPILER=clang-cl"
        "-DCMAKE_C_COMPILER_TARGET=aarch64-pc-windows-msvc"
        "-DCMAKE_CXX_COMPILER_TARGET=aarch64-pc-windows-msvc"
        "-DCMAKE_TOOLCHAIN_FILE=$($env:VCPKG_ROOT)/scripts/buildsystems/vcpkg.cmake"
        "-DVCPKG_TARGET_TRIPLET=arm64-windows"
        "-DARROW_DEPENDENCY_SOURCE=SYSTEM"
        "-Dabsl_SOURCE=$($env:absl_SOURCE ?? '')"
        "-DARROW_ACERO=$($env:ARROW_ACERO ?? 'OFF')"
        "-DARROW_AZURE=$($env:ARROW_AZURE ?? 'OFF')"
        "-DARROW_BOOST_USE_SHARED=$($env:ARROW_BOOST_USE_SHARED ?? 'ON')"
        "-DARROW_BUILD_BENCHMARKS_REFERENCE=$($env:ARROW_BUILD_BENCHMARKS ?? 'OFF')"
        "-DARROW_BUILD_BENCHMARKS=$($env:ARROW_BUILD_BENCHMARKS ?? 'OFF')"
        "-DARROW_BUILD_EXAMPLES=$($env:ARROW_BUILD_EXAMPLES ?? 'OFF')"
        "-DARROW_BUILD_INTEGRATION=$($env:ARROW_BUILD_INTEGRATION ?? 'OFF')"
        "-DARROW_BUILD_SHARED=$($env:ARROW_BUILD_SHARED ?? 'ON')"
        "-DARROW_BUILD_STATIC=$($env:ARROW_BUILD_STATIC ?? 'ON')"
        "-DARROW_BUILD_TESTS=$($env:ARROW_BUILD_TESTS ?? 'OFF')"
        "-DARROW_BUILD_UTILITIES=$($env:ARROW_BUILD_UTILITIES ?? 'ON')"
        "-DARROW_COMPUTE=$($env:ARROW_COMPUTE ?? 'ON')"
        "-DARROW_CSV=$($env:ARROW_CSV ?? 'ON')"
        "-DARROW_CUDA=$($env:ARROW_CUDA ?? 'OFF')"
        "-DARROW_CXXFLAGS=$($env:ARROW_CXXFLAGS ?? '')"
        "-DARROW_CXX_FLAGS_DEBUG=$($env:ARROW_CXX_FLAGS_DEBUG ?? '')"
        "-DARROW_CXX_FLAGS_RELEASE=$($env:ARROW_CXX_FLAGS_RELEASE ?? '')"
        "-DARROW_CXX_FLAGS_RELWITHDEBINFO=$($env:ARROW_CXX_FLAGS_RELWITHDEBINFO ?? '')"
        "-DARROW_C_FLAGS_DEBUG=$($env:ARROW_C_FLAGS_DEBUG ?? '')"
        "-DARROW_C_FLAGS_RELEASE=$($env:ARROW_C_FLAGS_RELEASE ?? '')"
        "-DARROW_C_FLAGS_RELWITHDEBINFO=$($env:ARROW_C_FLAGS_RELWITHDEBINFO ?? '')"
        "-DARROW_DATASET=$($env:ARROW_DATASET ?? 'OFF')"
        "-DARROW_DEPENDENCY_SOURCE=$($env:ARROW_DEPENDENCY_SOURCE ?? 'AUTO')"
        "-DARROW_DEPENDENCY_USE_SHARED=$($env:ARROW_DEPENDENCY_USE_SHARED ?? 'ON')"
        "-DARROW_ENABLE_THREADING=$($env:ARROW_ENABLE_THREADING ?? 'ON')"
        "-DARROW_ENABLE_TIMING_TESTS=$($env:ARROW_ENABLE_TIMING_TESTS ?? 'ON')"
        "-DARROW_EXTRA_ERROR_CONTEXT=$($env:ARROW_EXTRA_ERROR_CONTEXT ?? 'OFF')"
        "-DARROW_FILESYSTEM=$($env:ARROW_FILESYSTEM ?? 'ON')"
        "-DARROW_FLIGHT=$($env:ARROW_FLIGHT ?? 'OFF')"
        "-DARROW_FLIGHT_SQL=$($env:ARROW_FLIGHT_SQL ?? 'OFF')"
        "-DARROW_FUZZING=$($env:ARROW_FUZZING ?? 'OFF')"
        "-DARROW_GANDIVA_PC_CXX_FLAGS=$($env:ARROW_GANDIVA_PC_CXX_FLAGS ?? '')"
        "-DARROW_GANDIVA=$($env:ARROW_GANDIVA ?? 'OFF')"
        "-DARROW_GCS=$($env:ARROW_GCS ?? 'OFF')"
        "-DARROW_HDFS=$($env:ARROW_HDFS ?? 'ON')"
        "-DARROW_INSTALL_NAME_RPATH=$($env:ARROW_INSTALL_NAME_RPATH ?? 'ON')"
        "-DARROW_JEMALLOC=$($env:ARROW_JEMALLOC ?? 'OFF')"
        "-DARROW_JSON=$($env:ARROW_JSON ?? 'ON')"
        "-DARROW_LARGE_MEMORY_TESTS=$($env:ARROW_LARGE_MEMORY_TESTS ?? 'OFF')"
        "-DARROW_MIMALLOC=$($env:ARROW_MIMALLOC ?? 'ON')"
        "-DARROW_ORC=$($env:ARROW_ORC ?? 'OFF')"
        "-DARROW_PARQUET=$($env:ARROW_PARQUET ?? 'OFF')"
        "-DARROW_RUNTIME_SIMD_LEVEL=$($env:ARROW_RUNTIME_SIMD_LEVEL ?? 'MAX')"
        "-DARROW_S3=$($env:ARROW_S3 ?? 'OFF')"
        "-DARROW_SIMD_LEVEL=$($env:ARROW_SIMD_LEVEL ?? 'DEFAULT')"
        "-DARROW_SKYHOOK=$($env:ARROW_SKYHOOK ?? 'OFF')"
        "-DARROW_SUBSTRAIT=$($env:ARROW_SUBSTRAIT ?? 'OFF')"
        "-DARROW_TEST_LINKAGE=$($env:ARROW_TEST_LINKAGE ?? 'shared')"
        "-DARROW_TEST_MEMCHECK=$($env:ARROW_TEST_MEMCHECK ?? 'OFF')"
        "-DARROW_USE_ASAN=$($env:ARROW_USE_ASAN ?? 'OFF')"
        "-DARROW_USE_CCACHE=$($env:ARROW_USE_CCACHE ?? 'ON')"
        "-DARROW_USE_GLOG=$($env:ARROW_USE_GLOG ?? 'OFF')"
        "-DARROW_USE_LD_GOLD=$($env:ARROW_USE_LD_GOLD ?? 'OFF')"
        "-DARROW_USE_LLD=$($env:ARROW_USE_LLD ?? 'OFF')"
        "-DARROW_USE_MOLD=$($env:ARROW_USE_MOLD ?? 'OFF')"
        "-DARROW_USE_STATIC_CRT=$($env:ARROW_USE_STATIC_CRT ?? 'OFF')"
        "-DARROW_USE_TSAN=$($env:ARROW_USE_TSAN ?? 'OFF')"
        "-DARROW_USE_UBSAN=$($env:ARROW_USE_UBSAN ?? 'OFF')"
        "-DARROW_VERBOSE_THIRDPARTY_BUILD=$($env:ARROW_VERBOSE_THIRDPARTY_BUILD ?? 'OFF')"
        "-DARROW_WITH_BROTLI=$($env:ARROW_WITH_BROTLI ?? 'OFF')"
        "-DARROW_WITH_BZ2=$($env:ARROW_WITH_BZ2 ?? 'OFF')"
        "-DARROW_WITH_LZ4=$($env:ARROW_WITH_LZ4 ?? 'OFF')"
        "-DARROW_WITH_OPENTELEMETRY=$($env:ARROW_WITH_OPENTELEMETRY ?? 'OFF')"
        "-DARROW_WITH_MUSL=$($env:ARROW_WITH_MUSL ?? 'OFF')"
        "-DARROW_WITH_SNAPPY=$($env:ARROW_WITH_SNAPPY ?? 'OFF')"
        "-DARROW_WITH_UTF8PROC=$($env:ARROW_WITH_UTF8PROC ?? 'ON')"
        "-DARROW_WITH_ZLIB=$($env:ARROW_WITH_ZLIB ?? 'OFF')"
        "-DARROW_WITH_ZSTD=$($env:ARROW_WITH_ZSTD ?? 'OFF')"
        "-DAWSSDK_SOURCE=$($env:AWSSDK_SOURCE ?? '')"
        "-DAzure_SOURCE=$($env:Azure_SOURCE ?? '')"
        "-Dbenchmark_SOURCE=$($env:benchmark_SOURCE ?? '')"
        "-DBOOST_SOURCE=$($env:BOOST_SOURCE ?? '')"
        "-DBrotli_SOURCE=$($env:Brotli_SOURCE ?? '')"
        "-DBUILD_WARNING_LEVEL=$($env:BUILD_WARNING_LEVEL ?? 'CHECKIN')"
        "-Dc-ares_SOURCE=$($env:cares_SOURCE ?? '')"
        "-DCMAKE_BUILD_TYPE=$($env:ARROW_BUILD_TYPE ?? 'debug')"
        "-DCMAKE_VERBOSE_MAKEFILE=$($env:CMAKE_VERBOSE_MAKEFILE ?? 'OFF')"
        "-DCMAKE_C_FLAGS=$($env:CFLAGS ?? '')"
        "-DCMAKE_CXX_FLAGS=$($env:CXXFLAGS ?? '')"
        "-DCMAKE_CXX_STANDARD=$($env:CMAKE_CXX_STANDARD ?? '17')"
        "-DCMAKE_INSTALL_LIBDIR=$($env:CMAKE_INSTALL_LIBDIR ?? 'lib')"
        "-DCMAKE_INSTALL_PREFIX=$($env:CMAKE_INSTALL_PREFIX ?? $env:ARROW_HOME)"
        "-DCMAKE_UNITY_BUILD=$($env:CMAKE_UNITY_BUILD ?? 'OFF')"
        "-DCUDAToolkit_ROOT=$($env:CUDAToolkit_ROOT ?? '')"
        "-Dgflags_SOURCE=$($env:gflags_SOURCE ?? '')"
        "-Dgoogle_cloud_cpp_storage_SOURCE=$($env:google_cloud_cpp_storage_SOURCE ?? '')"
        "-DgRPC_SOURCE=$($env:gRPC_SOURCE ?? '')"
        "-DGTest_SOURCE=$($env:GTest_SOURCE ?? '')"
        "-Dlz4_SOURCE=$($env:lz4_SOURCE ?? '')"
        "-Dopentelemetry-cpp_SOURCE=$($env:opentelemetry_cpp_SOURCE ?? '')"
        "-DORC_SOURCE=$($env:ORC_SOURCE ?? '')"
        "-DPARQUET_BUILD_EXAMPLES=$($env:PARQUET_BUILD_EXAMPLES ?? 'OFF')"
        "-DPARQUET_BUILD_EXECUTABLES=$($env:PARQUET_BUILD_EXECUTABLES ?? 'OFF')"
        "-DPARQUET_REQUIRE_ENCRYPTION=$($env:PARQUET_REQUIRE_ENCRYPTION ?? 'ON')"
        "-DProtobuf_SOURCE=$($env:Protobuf_SOURCE ?? '')"
        "-DRapidJSON_SOURCE=$($env:RapidJSON_SOURCE ?? '')"
        "-Dre2_SOURCE=$($env:re2_SOURCE ?? '')"
        "-DSnappy_SOURCE=$($env:Snappy_SOURCE ?? '')"
        "-DThrift_SOURCE=$($env:Thrift_SOURCE ?? '')"
        "-Dutf8proc_SOURCE=$($env:utf8proc_SOURCE ?? '')"
        "-Dzstd_SOURCE=$($env:zstd_SOURCE ?? '')"
        "-Dxsimd_SOURCE=$($env:xsimd_SOURCE ?? '')"
        "-G"
        "$($env:CMAKE_GENERATOR ?? 'Ninja')"
    )

    # Add any additional CMake arguments from environment
    if ($env:ARROW_CMAKE_ARGS) {
        $additional_args = $env:ARROW_CMAKE_ARGS -split '\s+'
        $cmake_args += $additional_args
    }

    # Add source directory
    $cmake_args += $source_dir

    # Run CMake configuration
    & cmake @cmake_args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    # Set parallel build level
    $build_parallel = $env:ARROW_BUILD_PARALLEL ?? ($n_jobs + 1)
    if (-not $env:CMAKE_BUILD_PARALLEL_LEVEL) {
        $env:CMAKE_BUILD_PARALLEL_LEVEL = $build_parallel
    }

    # Build and install with timing
    Measure-Command {
        & cmake --build . --target install
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    } | ForEach-Object { Write-Host "time $($_.TotalSeconds.ToString('F3'))s" }

    # Save disk space by removing large temporary build products
    Get-ChildItem -Path . -Recurse -Name "*.obj" | Remove-Item -Force -ErrorAction SilentlyContinue

    # Handle offline build cleanup
    if ($env:ARROW_OFFLINE -eq "ON") {
        # Restore network configuration if modified
    }

} finally {
    Pop-Location
}

# Show ccache statistics after build if enabled
if ($env:ARROW_USE_CCACHE -eq "ON") {
    Write-Host "===`n=== ccache statistics after build`n==="
    try {
        ccache -sv 2>$null
    } catch {
        try {
            ccache -s
        } catch {
            # Ignore if ccache not available
        }
    }
}

# Show sccache statistics if available
if (Get-Command sccache -ErrorAction SilentlyContinue) {
    Write-Host "=== sccache stats after the build ==="
    sccache --show-stats
}

# Build documentation if requested
if ($env:BUILD_DOCS_CPP -eq "ON") {
    $apidoc_dir = Join-Path $source_dir "apidoc"
    if (Test-Path $apidoc_dir) {
        Push-Location $apidoc_dir
        try {
            $env:OUTPUT_DIRECTORY = Join-Path $build_dir "apidoc"
            if (Get-Command doxygen -ErrorAction SilentlyContinue) {
                doxygen
            }
        } finally {
            Pop-Location
        }
    }
}
