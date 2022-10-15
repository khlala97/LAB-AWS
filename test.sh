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

function create_security_group {
    echo "Create security group..."
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name benchmarking-security-group \
    --description 'Security group for benchmarking lab' \
    --query 'GroupId'\
    --output text)

    echo "SECURITY_GROUP_ID=\"$SECURITY_GROUP_ID\"" >> env.txt

    add_security_ingress_rules '[{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow SSH"}]},{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow HTTP"}]}]' > /dev/null 2> error.log
    echo "Done"
}

function add_security_ingress_rules {
    echo "Add ingress rules"
    local rules_permissions=$1
    aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --ip-permissions "${rules_permissions}"
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
