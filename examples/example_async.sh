source "$VDEMO_demoRoot/example_config.sh"

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
checkdemo,             $host01,            -t sleep01-01A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep01-01B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep01-02A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep01-02B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep01-03A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep01-03B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep01-04A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep01-04B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep01-05A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep01-05B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep01-06A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep01-06B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep01-07A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep01-07B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep01-08A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep01-08B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep01-09A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep01-09B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep01-10A -L 1  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep01-10B -L 1  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep02-01A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep02-01B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep02-02A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep02-02B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep02-03A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep02-03B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep02-04A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep02-04B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep02-05A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep02-05B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep02-06A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep02-06B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep02-07A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep02-07B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep02-08A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep02-08B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep02-09A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep02-09B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep02-10A -L 2  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep02-10B -L 2  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep03-01A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep03-01B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep03-02A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep03-02B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep03-03A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep03-03B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep03-04A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep03-04B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep03-05A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep03-05B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep03-06A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep03-06B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep03-07A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep03-07B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep03-08A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep03-08B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep03-09A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep03-09B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep03-10A -L 3  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep03-10B -L 3  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep04-01A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep04-01B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep04-02A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep04-02B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep04-03A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep04-03B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep04-04A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep04-04B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep04-05A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep04-05B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep04-06A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep04-06B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep04-07A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep04-07B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep04-08A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep04-08B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep04-09A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep04-09B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep04-10A -L 4  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep04-10B -L 4  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep05-01A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host01,            -t sleep05-01B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep05-02A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host02,            -t sleep05-02B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep05-03A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host03,            -t sleep05-03B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep05-04A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host04,            -t sleep05-04B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep05-05A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host05,            -t sleep05-05B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep05-06A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host06,            -t sleep05-06B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep05-07A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host07,            -t sleep05-07B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep05-08A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host08,            -t sleep05-08B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep05-09A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host09,            -t sleep05-09B -L 5  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep05-10A -L 5  -g sleepers -w 10 -x:
checkdemo,             $host10,            -t sleep05-10B -L 5  -g sleepers -w 10 -x:
"
