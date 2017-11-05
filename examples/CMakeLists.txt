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
FILE(GLOB infiles RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" *.sh.in)

# Remove scripts from file list (in source builds or should not be installed)
FOREACH(item ${shfiles})
    IF(${item} MATCHES "[^/]*[-_]config.sh$")
        LIST(REMOVE_ITEM shfiles ${item})
    ENDIF()
ENDFOREACH(item)

SET(launchfiles ${shfiles})
FOREACH(item ${launchfiles})
    IF(${item} MATCHES "^vdemo_[^/]*$|[^/]*-config.sh$")
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
        
# configure config files to inject variables
SET(configfiles)
FOREACH(file ${infiles})
    STRING(REGEX REPLACE "^(.*)\\.in$" "\\1" configfile ${file})
    LIST(APPEND configfiles ${configfile})
    CONFIGURE_FILE(${file} "${CMAKE_CURRENT_BINARY_DIR}/${configfile}" @ONLY)
    INSTALL(FILES "${CMAKE_CURRENT_BINARY_DIR}/${configfile}"
            DESTINATION "etc/vdemo_scripts"
            PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ OWNER_EXECUTE GROUP_EXECUTE WORLD_EXECUTE)
ENDFOREACH()

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
        
# install data
file(GLOB data_files RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "data/*")
foreach(data_file ${data_files})
    # check whether we need to configure this file
    if(data_file MATCHES ".*\\.in$")
        message(STATUS "configuring data file ${data_file}")
        string(REGEX REPLACE "^(.*)\\.in$" "\\1" filename ${data_file})
        configure_file(${data_file} "${CMAKE_CURRENT_BINARY_DIR}/${filename}" @ONLY)
        install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${filename}"
                DESTINATION "etc/vdemo_scripts/data")
    else()
        install(FILES ${data_file}
                DESTINATION "etc/vdemo_scripts/data")
    endif()
endforeach()
