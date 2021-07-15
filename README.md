# vdemo

This is a fork from: https://code.cor-lab.de/projects/vdemo

## Shell environment

Every component shell script is executed within a shell environment that has loaded ~/.bashrc (as a non-interactive shell) as well as the vdemo master shell script provided as argument to vdemo2 commandline.
Additionally, all variables from the local environment that are listed within the shell variable $VDEMO_exports, will be exported to the remote shell environments.

## Component List Syntax

The variable VDEMO_components is a colon-separated (:) list of components. Each component entry in turn is a comma-separated list of component name, host, options. The following component-specific options are available:

```
  -w <n> timeout (seconds) for a process to become ready after start (default: 5s)
         If zero or negative, vdemo will wait forever for this component, frequently checking it.
  -W <n> time (seconds) when to check a component after start the first time
         Only takes effect, when -w 0 is specified. 
  -l     activate initial logging for the component
  -x     use own X server for the component
  -n     do not include in level/group/auto start
  -g <s> allow to define a group (string: name of group)
  -L <n> component level, affects starting order (numeric: level)
  -d <n> detach time, automatically detaches screen after n seconds, or
         leaves it open all the time (-1), default is 10 seconds
  -t     title of the component / provide unique names for multiple instances on the same host
  -v     export variable varname=var to component script
  -Q     Stop the whole vdemo system in a clean fashion in case the respective components
         stops on its own (or is killed externally) but not when the stop button is pressed
  -R     auto-restart the component if it dies
  -r     auto-restart the component if it dies - after a confirmation dialog
  ```

### Tabs

To organize a plenty of components more clearly, they can be arranged on tabs. To this end, insert the name of the tab into the components list (again colon-separated from other components, but without comma-separated list of other infos). All subsequent components will show up on the most recently mentioned tab.
Example

```
export VDEMO_components=" 
spreaddaemon,${PC_CORE_1},-l -w 0 -g spread -L 0:
spreaddaemon,${PC_CORE_2},-l -w 0 -g spread -L 0:
components:
device-manager,${PC_HOMEAUTOMATION},-l -g homeautomation -v DB_PATH=$datadir/db/device-db -L 1:
location-manager,${PC_HOMEAUTOMATION},-l -g homeautomation -v DB_PATH=$datadir/db/location-db -L 1:
moreComponents:
roscore,${PC_FLOBI_WARDROBE},-l -t roscore_wardrobe -w 4 -g flobi_w -L 1:
roscore,${PC_FLOBI_KITCHEN},-l -t roscore_kitchen -w 4 -g flobi_k -L 1:
" 
```

Please note that the $VDEMO_components variable **needs to start with a component and not a tab definition!**

## Component Functions

### component

Called to start the component. All variables to be used in this function, either need to be exported to the environment beforehand or defined locally within the function.
Several processes can be launched in the component function (and send to background). However, the main process should be launched last and **must not** be send to background.
The component is considered as stopped if the component function terminates, i.e. the last process terminates.

### stop_component

Stopping of components often needs to be customized to adapt to the special requirements of more complex components, starting several processes.
The default behaviour is to call vdemo_stop_signal_children $1 SIGINT 2, where $1 is the title of the component provided as an argument by vdemo, SIGINT is the signal to use for stopping, and 2 is a 2sec timeout to wait for the processes to be stopped.
This function sends the given signal to all top-level processes spawned in the function component.

However, some processes ignore SIGINT or take longer to shutdown. In this case you should customize the stopping behaviour, specifying an own stop_component function.
An important example are shell scripts which are launched from the component function: bash doesn't react to SIGINT at all. Sending a SIGTERM quits bash, but leaves launched child processes open.
A prominent example is MaryServer, which is launching java from a bash script within the component function. This component requires the following stop function:

```
function stop_component {
    local PIDS=$(all_children --filter bash\|tee\|screen $(vdemo_pidFromScreen $1))
    echo "killing processes $PIDS" 
    kill -SIGINT $PIDS > /dev/null 2>&1
    for i in {1..50}; do
        sleep 0.1
        kill -0 $PIDS > /dev/null 2>&1 || break
    done
}
```

The function all_children provided by vdemo lists all PIDs of the component's screen process and its children, eventually filtering out the given command names.
Subsequently, these processes can be killed. The loop waits for actual termination of those processes (with a timeout of 5s = 50*0.1s).

### on_stop

After stopping a component using stop_component, some cleanup code can be executed by defining the function on_stop.

To summarize, when stopping a component, the following things happen:
- stop_component is called (if defined, otherwise: vdemo_stop_signal_children $1 SIGINT 2)
- if there are any remaining processes originally associated to that component, they will be killed
- finally, on_stop will we called for some cleanup

### on_check

Typically a component is considered to be running, when its corresponding screen process is alive. However, some components might be broken/not responding although there are still running.
To this end, the function on_check can be provided. If present, the function is called additionally to the screen-process-alive test and its return value is used to judge the state of the component.
If non-zero, the component is considered to be in an error state. A typical example is to check for responsiveness of a specific port:

```
function on_check {
    nc -w 1 -z 0.0.0.0 "$SPREAD_PORT" 
}
```

Vice-versa, components might be running independently from vdemo, and thus often interfere with a demo. In this case on_check would indicate a running component, although no screen process is present. This is indicated in vdemo with orange component color. The following indicator colors are used:


* ![#d3d3d3](https://via.placeholder.com/40x32.png/d3d3d3/ffffff?text=check) unknown
* ![#ffff00](https://via.placeholder.com/40x32.png/ffff00/ffffff?text=check) starting
* ![#008000](https://via.placeholder.com/40x32.png/008000/ffffff?text=check) running + responding
* ![#ffa500](https://via.placeholder.com/40x32.png/ffa500/ffffff?text=check) responding, but not started from vdemo
* ![#ffc0cb](https://via.placeholder.com/40x32.png/ffc0cb/ffffff?text=check) running, but not responding
* ![#ff0000](https://via.placeholder.com/40x32.png/ff0000/ffffff?text=check) not running

## Spread configuration

To facilitate creation of spread configuration files, a spread configuration is automatically generated when no SPREAD_CONFIG environment variable is defined in the master script.
To this end, all machines where a spread daemon should be started, are grouped into segments using the first three IP octets. For each segment an own spread multicast group is created
using the multicast IP address 225.xxx.yyy.zzz where the three octets xxx.yyy.zzz are the last three IP octets of the first machine within a segment.
This way, we hope to ensure, that every setup configuration obtains its own multicast groups.

## vdemo2 commandline options

```
-a  --auto               automatically start all components
-l  --log                enable logging for all components
-d  --detach time        set default detach time in seconds
                          0: start detached
                         <0: never detach
-r  --logrotate          enable log rotation
-v  --verbose [level]    set verbosity [level]
                         >0: increasing verbosity
                         -1: also suppress message boxes
-f  --fifo <file>        create fifo for text-based remote-control of vdemo gui
                         accepting:
                         (start | stop | check) (<component> | <group> | ALL)
-Q  --quit <components>  space separated list of components to quit vdemo on
```
