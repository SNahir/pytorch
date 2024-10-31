# This will define the following variables:
# SYCL_FOUND               : True if the system has the SYCL library.
# SYCL_INCLUDE_DIR         : Include directories needed to use SYCL.
# SYCL_LIBRARY_DIR         ：The path to the SYCL library.
# SYCL_LIBRARY             : SYCL library fullname.
# SYCL_COMPILER_VERSION    : SYCL compiler version.

include(FindPackageHandleStandardArgs)

set(SYCL_ROOT "")
if(DEFINED ENV{SYCL_ROOT})
  set(SYCL_ROOT $ENV{SYCL_ROOT})
elseif(DEFINED ENV{CMPLR_ROOT})
  set(SYCL_ROOT $ENV{CMPLR_ROOT})
endif()

string(COMPARE EQUAL "${SYCL_ROOT}" "" nosyclfound)
if(nosyclfound)
  set(SYCL_FOUND False)
  set(SYCL_REASON_FAILURE "SYCL library not set!!")
  set(SYCL_NOT_FOUND_MESSAGE "${SYCL_REASON_FAILURE}")
  return()
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Linux")
  set(SYCL_EXECUTABLE_NAME icpx)
elseif(CMAKE_SYSTEM_NAME MATCHES "Windows")
  set(SYCL_EXECUTABLE_NAME icx)
endif()

# Find SYCL compiler executable.
find_program(
  SYCL_COMPILER
  NAMES ${SYCL_EXECUTABLE_NAME}
  PATHS "${SYCL_ROOT}"
  PATH_SUFFIXES bin bin64
  NO_DEFAULT_PATH
  )

function(parse_sycl_compiler_version version_number)
  # Generate a small C++ source code file to determine the SYCL compiler version.
  set(SOURCE_CODE
  "
    #include <iostream>
    int main() {
    #if defined(__INTEL_LLVM_COMPILER)
      std::cout << \"__INTEL_LLVM_COMPILER=\" << __INTEL_LLVM_COMPILER << std::endl;
    #endif
      return 0;
    }
  ")
  set(SOURCE_CODE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
  set(SOURCE_CODE_FILE "${SOURCE_CODE_DIR}/sycl_compiler_version.cpp")
  set(SOURCE_CODE_EXCUTABLE_NAME "${SOURCE_CODE_FILE}.exe")
  file(WRITE ${SOURCE_CODE_FILE} "${SOURCE_CODE}")
  # Compile the source code file.
  execute_process(
    COMMAND "${SYCL_COMPILER}"
    "-fsycl"
    ${SOURCE_CODE_FILE}
    "-o"
    ${SOURCE_CODE_EXCUTABLE_NAME}
    WORKING_DIRECTORY ${SOURCE_CODE_DIR}
    RESULT_VARIABLE result
    TIMEOUT 60
    )
  if(result)
    return()
  endif()
  # Run the generated executable to output et the SYCL compiler version.
  execute_process(
    COMMAND ${SOURCE_CODE_EXCUTABLE_NAME}
    WORKING_DIRECTORY ${SOURCE_CODE_DIR}
    OUTPUT_VARIABLE output
    RESULT_VARIABLE result
    TIMEOUT 60
    )
  if(result)
    return()
  endif()
  # Parse the version number from the output.
  string(REGEX REPLACE "^__INTEL_LLVM_COMPILER=" "" VERSION_NUMBER_MATCH "${output}")
  set(${version_number} "${VERSION_NUMBER_MATCH}" PARENT_SCOPE)
endfunction()

parse_sycl_compiler_version(SYCL_COMPILER_VERSION)

if(NOT SYCL_COMPILER_VERSION)
  set(SYCL_FOUND False)
  set(SYCL_REASON_FAILURE "Cannot parse sycl compiler version to get SYCL_COMPILER_VERSION!")
  set(SYCL_NOT_FOUND_MESSAGE "${SYCL_REASON_FAILURE}")
  return()
endif()

# Find include path from binary.
find_file(
  SYCL_INCLUDE_DIR
  NAMES include
  HINTS ${SYCL_ROOT}
  NO_DEFAULT_PATH
  )

# Find include/sycl path from include path.
find_file(
  SYCL_INCLUDE_SYCL_DIR
  NAMES sycl
  HINTS ${SYCL_ROOT}/include/
  NO_DEFAULT_PATH
  )

# Due to the unrecognized compilation option `-fsycl` in other compiler.
list(APPEND SYCL_INCLUDE_DIR ${SYCL_INCLUDE_SYCL_DIR})

# Find library directory from binary.
find_file(
  SYCL_LIBRARY_DIR
  NAMES lib lib64
  HINTS ${SYCL_ROOT}
  NO_DEFAULT_PATH
  )

# Define the old version of SYCL toolkit that is compatible with the current version of PyTorch.
set(PYTORCH_2_5_SYCL_TOOLKIT_VERSION 20249999)

# By default, we use libsycl.so on Linux and sycl.lib on Windows as the SYCL library name.
if (SYCL_COMPILER_VERSION VERSION_LESS_EQUAL PYTORCH_2_5_SYCL_TOOLKIT_VERSION)
  # Don't use if(LINUX) here since this requires cmake>=3.25 and file is installed
  # and used by other projects.
  # See: https://cmake.org/cmake/help/v3.25/variable/LINUX.html
  if(CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(sycl_lib_suffix "-preview")
  elseif(CMAKE_SYSTEM_NAME MATCHES "Windows")
    # On Windows, the SYCL library is named sycl7.lib until PYTORCH_2_5_SYCL_TOOLKIT_VERSION.
    # sycl.lib is supported in the later version.
    set(sycl_lib_sufix "7")
  endif()
endif()

# Find SYCL library fullname.
find_library(
  SYCL_LIBRARY
  NAMES "sycl${sycl_lib_suffix}"
  HINTS ${SYCL_LIBRARY_DIR}
  NO_DEFAULT_PATH
)

# Find OpenCL library fullname, which is a dependency of oneDNN.
find_library(
  OCL_LIBRARY
  NAMES OpenCL
  HINTS ${SYCL_LIBRARY_DIR}
  NO_DEFAULT_PATH
)

if((NOT SYCL_LIBRARY) OR (NOT OCL_LIBRARY))
  set(SYCL_FOUND False)
  set(SYCL_REASON_FAILURE "SYCL library is incomplete!!")
  set(SYCL_NOT_FOUND_MESSAGE "${SYCL_REASON_FAILURE}")
  return()
endif()

find_package_handle_standard_args(
  SYCL
  FOUND_VAR SYCL_FOUND
  REQUIRED_VARS SYCL_INCLUDE_DIR SYCL_LIBRARY_DIR SYCL_LIBRARY
  REASON_FAILURE_MESSAGE "${SYCL_REASON_FAILURE}"
  VERSION_VAR SYCL_COMPILER_VERSION
  )
