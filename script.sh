set -e
# import cli cmd functions
source cli_helper.sh

function setup {
  create_security_groupe
  create_keypair
  
  SUBNETS_1=$(aws ec2 describe-subnets --query "Subnets[0].SubnetId" --output text)
  SUBNETS_2=$(aws ec2 describe-subnets --query "Subnets[1].SubnetId" --output text)
  #Arrays of instanceIds for each cluster
  CLUSTER_ONE_INSTANCES=()
  CLUSTER_TWO_INSTANCES=()
  
  echo "Launch EC2 instances... "
  for i in {1..4}; do
    CLUSTER_ONE_INSTANCES+=("$(launch_ec2_instance $SUBNETS_1 "t2.large")")
    CLUSTER_TWO_INSTANCES+=("$(launch_ec2_instance $SUBNETS_2 "m4.large")")
  done
  #Launch the 9th instance
  CLUSTER_ONE_INSTANCES+=("$(launch_ec2_instance $SUBNETS_1 "t2.large")")
  echo "Done"

  
}
#Setup the load balancer configs
echo "Create an application load balancer... "
ALB_ARN=$(create_alb)
echo "Done"

echo "Create target groups"
ALB_TARGET_GROUP1_ARN=$(create_target_group "cluster1")
ALB_TARGET_GROUP2_ARN=$(create_target_group "cluster2")
echo "Done"

echo -n "Wait for instances to enter 'running' state... "
aws ec2 wait instance-running --instance-ids ${CLUSTER_ONE_INSTANCES[@]} ${CLUSTER_TWO_INSTANCES[@]}
echo "Instances are ready!"


