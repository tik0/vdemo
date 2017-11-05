export VDEMO_demoRoot="$(dirname "${BASH_SOURCE[0]}")"

# instead of launching vdemo2 with -s we specify the port here to allow for
# different ports for different configurations
export VDEMO_SERVER_PORT=4443
export VDEMO_SERVER_KEY=demo

host01="localhost"
host02="localhost"
host03="localhost"
host04="localhost"
host05="localhost"
host06="localhost"
host07="localhost"
host08="localhost"
host09="localhost"
host10="localhost"

source "$VDEMO_demoRoot/example_base.sh"
