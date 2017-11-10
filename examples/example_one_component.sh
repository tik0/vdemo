source "$VDEMO_demoRoot/example_config.sh"

# instead of launching vdemo2 with -s we specify the port here to allow for
# different ports for different configurations
export VDEMO_SERVER_PORT=4443
export VDEMO_SERVER_KEY=demo

host01=${host01:-localhost}
host02=${host02:-localhost}
host03=${host03:-localhost}
host04=${host04:-localhost}
host05=${host05:-localhost}
host06=${host06:-localhost}
host07=${host07:-localhost}
host08=${host08:-localhost}
host09=${host09:-localhost}
host10=${host10:-localhost}

##############################################################################
# COMPONENT LIST
##############################################################################
#   Options:
#      -w <n> wait n seconds for process to start completely
#      -W <n> set delay an asynchronous check is performed in case -w is not specified
#      -l     activate initial logging for the component
#      -x     use own X server for the component
#      -n     do not include in autostart
#      -g <s> allow to define a group (string: name of group)
#      -L <n> component level, affects starting order (numeric: level)
#      -d <n> detach time, automatically detaches screen after n seconds, or
#             leaves it open all the time (-1), default is 10 seconds
#      -t     title of the component / provide unique names for multiple instances on the same host
#      -v     export variable varname=var to component script


export VDEMO_components="
sleep,             $host01,            -t sleep01-01A -L 1  -g sleepers -w 0 -W 1 -x:
"
