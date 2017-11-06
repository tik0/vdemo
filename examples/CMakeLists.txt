CMAKE_MINIMUM_REQUIRED(VERSION 2.4)

PROJECT(vdemo_configuration NONE)

# can be used to have a prefix different from install path
IF (NOT DEFINED CMAKE_PREFIX_PATH)
  SET(CMAKE_PREFIX_PATH "${CMAKE_INSTALL_PREFIX}")
ENDIF()

set(ENV{PKG_CONFIG_PATH} "$ENV{PKG_CONFIG_PATH}:${CMAKE_PREFIX_PATH}/lib/pkgconfig" )

INCLUDE(FindPkgConfig)
PKG_SEARCH_MODULE(VDEMO REQUIRED vdemo)

SET(PROGNAME vdemo_scripts)

# these are somehow used in configured files
SET(vdemo_prefix ${VDEMO_PREFIX})
SET(vdemo_demoroot "${CMAKE_INSTALL_PREFIX}/etc/vdemo_scripts")
SET(prefix ${CMAKE_PREFIX_PATH})
SET(bindir "${prefix}/bin")

FILE(GLOB shfiles RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" *.sh)

SET(launchfiles ${shfiles})
FOREACH(item ${launchfiles})
    IF(${item} MATCHES "^vdemo_[^/]*$|.*[_-]config.sh$")
        LIST(REMOVE_ITEM launchfiles ${item})
    ENDIF()
ENDFOREACH(item)

INSTALL(FILES ${shfiles}
        DESTINATION "etc/vdemo_scripts"
        PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ GROUP_EXECUTE WORLD_EXECUTE)

FILE(GLOB components "component_scripts/component_*")
LIST(REMOVE_ITEM components "*~")
INSTALL(FILES ${components}
        DESTINATION "etc/vdemo_scripts/component_scripts"
        PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ OWNER_EXECUTE GROUP_EXECUTE WORLD_EXECUTE)
        
# configure starter script for each demo configuration
FOREACH(launchfile ${launchfiles})
    MESSAGE(STATUS "configuring launcher file for ${launchfile}")
    GET_FILENAME_COMPONENT(demoname ${launchfile} NAME_WE)
    SET(VDEMO_launchfile "${vdemo_demoroot}/${demoname}.sh")
    SET(vdemo_starter "vdemo_${demoname}.sh")
    CONFIGURE_FILE(vdemo_start.in ${vdemo_starter})
    INSTALL(FILES "${PROJECT_BINARY_DIR}/${vdemo_starter}"
        DESTINATION bin
        PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ GROUP_WRITE WORLD_READ OWNER_EXECUTE GROUP_EXECUTE WORLD_EXECUTE)
ENDFOREACH()
