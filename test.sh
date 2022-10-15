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
function create_keypair {
  echo -n "Create a key-pair"
  aws ec2 create-key-pair --key-name keypair --query 'KeyMaterial' --output text > keypair.pem 2> error.log
  is_error $?
  #CHange access permissions to keypair for security 
  chmod 400 keypair.pem
  echo "Done!"
  
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
