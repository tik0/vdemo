source "$VDEMO_demoRoot/example_config.sh"

# instead of launching vdemo2 with -s we specify the port here to allow for
# different ports for different configurations
export VDEMO_SERVER_PORT=4443
export VDEMO_SERVER_KEY=demo

host01=${host01:-localhost}

##############################################################################
# COMPONENT LIST
##############################################################################
#   Options:
#      -w <n> wait n seconds for process to start completely
#      -W <n> set delay an asynchronous check is performed in case -w is not specified
#      -l     activate logging for the component
#      -x     detect and use remote X server for the component
#      -n     do not include in autostart
#      -g <s> allow to define a group (string: name of group)
#      -L <n> component level, affects starting order (numeric: level)
#      -d <n> detach time, automatically detaches screen after n seconds, or
#             leaves it open all the time (-1), default is 10 seconds
#      -t     title of the component / provide unique names for multiple instances on the same host
#      -v     export variable varname=var to component script
#      -r     ask to restart component on crash
#      -R     automatically component on crash
#      -Q     Quit vdemo if component terminates


export VDEMO_components="
funcvartest,             $host01,            -t specific_title -L 1  -g mygroup -w 0 -W 1 -x:
funcvartest,             $host01,            -L 1  -g mygroup -w 0 -W 1 -x:
"
