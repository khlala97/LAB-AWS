#
# error Function
#

set -e
action =$1
function is_error {
  EXIT_CODE=$1
  
  if [[ $EXITE_CODE != 0 ]]; then
    echo "Error!"
    echo "Check error.log file"
    exit
  fi
}

#
# prepare env (keypairs,rules..) Functions
#
function env {

}

#
# deployement Function
#

function dep {

}

#
# benchmarking Function
#
function benchmarking {

}
