#!/bin/bash

function create_security_group {
    echo "Create security group..."
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name benchmarking-security-group \
        --description 'Security group for benchmarking lab' \
        --query 'GroupId' \
        --output text)
        
    echo "SECURITY_GROUP_ID=\"$SECURITY_GROUP_ID\"" >>backup.txt    
    add_security_ingress_rules '[{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow SSH"}]},{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow HTTP"}]}]'
    echo "Done"
}

function add_security_ingress_rules {
    echo "Add ingress rules"
    local rules_permissions=$1
    aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --ip-permissions "${rules_permissions}"
}

function create_keypair {
    echo "Create a key-pair... "
    aws ec2 create-key-pair --key-name keypair --query 'KeyMaterial' --output text >keypair.pem
    ## Change access to key pair to make it secure
    chmod 400 keypair.pem
    echo "Done"
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

function register_targets {
    local group_arn=$1
    local id=$2
    aws elbv2 register-targets --target-group-arn $group_arn --targets Id=$id
}

function deregister_targets {
    local target_group=$1
    local cluster_instnces=$2
    aws elbv2 deregister-targets \
        --target-group-arn $target_group \
        --targets "$(aws ec2 describe-instances \
            --query "Reservations[*].Instances[?contains('$cluster_instnces', InstanceId)].{Id: InstanceId}[]")"
}

function create_alb_listener {
    local alb_arn=$1
    local group1_arn=$2
    local group2_arn=$3
    aws elbv2 create-listener --load-balancer-arn $alb_arn --protocol HTTP --port 80 \
        --default-actions \
        "[
            {
              \"Type\": \"forward\",
              \"ForwardConfig\": {
                \"TargetGroups\": [
                  {
                    \"TargetGroupArn\": \"$group1_arn\",
                    \"Weight\": 500
                  },
                  {
                    \"TargetGroupArn\": \"$group2_arn\",
                    \"Weight\": 500
                  }
                ]
              }
            }
        ]" \
        --query 'Listeners[0].ListenerArn' \
        --output text
}

function create_listener_rules {
    local alb_listener_arn=$1
    local alb_target_group=$2
    local condition=$3
    local priority=$4
    aws elbv2 create-rule \
        --listener-arn $alb_listener_arn \
        --priority $priority \
        --conditions $condition \
        --actions Type=forward,TargetGroupArn=$alb_target_group
}

function tg_health_check_state {
    local target_group=$1
    local cluster_instances=$2
    aws elbv2 wait target-in-service --target-group-arn $target_group \
        --targets "$(aws ec2 describe-instances \
            --query "Reservations[*].Instances[?contains('$cluster_instances', InstanceId)].{Id: InstanceId}[]")"
}

function get_alb_dns {
    local alb_arn=$1
    aws elbv2 describe-load-balancers \
        --load-balancer-arns $alb_arn \
        --query 'LoadBalancers[0].DNSName' \
        --output text
}

function delete_listener {
    local listener_arn=$1
    aws elbv2 delete-listener --listener-arn $listener_arn
}

function delete_target_groups {
    local target_group=$1
    aws elbv2 delete-target-group --target-group-arn $target_group
}

function delete_alb {
    local alb_arn=$1
    aws elbv2 delete-load-balancer --load-balancer-arn $alb_arn
}

function delete_security_group {
    local security_group_id=$1
    aws ec2 delete-security-group --group-id $security_group_id
}
