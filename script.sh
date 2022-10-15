set -e
# import cli cmd functions
source test.sh

function setup {
  create_security_groupe
  create_keypair
  
  SUBNETS_1=$(aws ec2 describe-subnets --query "Subnets[0].SubnetId" --output text)
  SUBNETS_2=$(aws ec2 describe-subnets --query "Subnets[1].SubnetId" --output text)
  #Arrays of instanceIds for each cluster
  CLUSTER_ONE_INSTANCES=()
  CLUSTER_TWO_INSTANCES=()
  
  
  
}
