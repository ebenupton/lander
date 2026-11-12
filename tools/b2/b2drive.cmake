# Adds Lander's b2drive target to b2's own CMake build without changing b2:
# b2's configure is run with -DCMAKE_PROJECT_b2_INCLUDE=<this file> (build.sh),
# which defers the target to the end of b2's top-level CMakeLists.txt, once
# its libraries (beeb_lib, shared_lib, stb_image_lib) are defined.
set(B2DRIVE_DIR ${CMAKE_CURRENT_LIST_DIR} CACHE INTERNAL "")
cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL _b2drive_add)
function(_b2drive_add)
  add_executable(b2drive ${B2DRIVE_DIR}/b2drive.cpp)
  target_link_libraries(b2drive PRIVATE shared_lib beeb_lib stb_image_lib)
  set_target_properties(b2drive PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
  b2_target_boilerplate(b2drive)
endfunction()
