#!/bin/bash
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

function launch_ec2_instance {
    local subnet=$1
    local instance_type=$2
    aws ec2 run-instances \
        --image-id ami-09e67e426f25ce0d7 \
        --instance-type $instance_type \
        --count 1 \
        --subnet-id $subnet --key-name keypair \
        --monitoring "Enabled=true" \
        --security-group-ids $SECURITY_GROUP_ID \
        --user-data file://config/flask_setup.txt \
        --query 'Instances[*].InstanceId[]' \
        --output text
}


function create_alb {
    local aws_subnets=$(aws ec2 describe-subnets --query 'Subnets[*].SubnetId' --output text)
    aws elbv2 create-load-balancer \
        --name application-load-balancer \
        --subnets $aws_subnets \
        --security-groups $SECURITY_GROUP_ID \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text
}

function create_target_group {
    local vpc_id=$(aws ec2 describe-vpcs --query 'Vpcs[?IsDefault==`true`].VpcId' --output text)
    local group_name=$1
    aws elbv2 create-target-group \
        --name $group_name \
        --protocol HTTP --port 80 \
        --vpc-id $vpc_id \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text
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
