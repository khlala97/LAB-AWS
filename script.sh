set -e
# import cli cmd functions
source utils/cli_helper.sh

function setup {

    #Setup network security
    create_security_group
    create_keypair

    #Setup EC2 instances
    SUBNETS_1=$(aws ec2 describe-subnets --query "Subnets[0].SubnetId" --output text)
    SUBNETS_2=$(aws ec2 describe-subnets --query "Subnets[1].SubnetId" --output text)
    CLUSTER_ONE_INSTANCES=() #Arrays of instanceIds for each cluster
    CLUSTER_TWO_INSTANCES=()

    echo "Launch EC2 instances... "
    for i in {1..4}; do
        CLUSTER_ONE_INSTANCES+=("$(launch_ec2_instance $SUBNETS_1 "t2.large")")
        CLUSTER_TWO_INSTANCES+=("$(launch_ec2_instance $SUBNETS_2 "m4.large")")
    done
    #Launch the 9th instance
    CLUSTER_ONE_INSTANCES+=("$(launch_ec2_instance $SUBNETS_1 "t2.large")")
    echo "Done"

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

    #Register the instances in the target groups
    echo "Register the instances in the target groups..."
    for id in ${CLUSTER_ONE_INSTANCES[@]}; do
        register_targets $ALB_TARGET_GROUP1_ARN $id
    done

    for id in ${AWS_CLUSTER_TWO_INSTANCES[@]}; do
        register_targets $ALB_TARGET_GROUP2_ARN $id
    done
    echo "Success!"

    echo -n "Create path rules for alb listener... "
    #Create a listener for your load balancer with a default rule that forwards requests to your target group
    ALB_LISTNER_ARN=$(create_alb_listener $ALB_ARN $ALB_TARGET_GROUP1_ARN $ALB_TARGET_GROUP2_ARN)

    #Create a rule using a path condition and a forward action for cluster 1 & 2
    echo "Create listener rules for cluster 1 and cluster 2"
    create_listener_rules $ALB_LISTNER_ARN $ALB_TARGET_GROUP1_ARN "file://config/cluster1-routing.json" 5
    create_listener_rules $ALB_LISTNER_ARN $ALB_TARGET_GROUP2_ARN "file://config/cluster2-routing.json" 6
    echo "Success!"

    echo "Wait for alb to become available"
    aws elbv2 wait load-balancer-available --load-balancer-arns $ALB_ARN

    echo "Wait for target groups to pass health checks..."
    tg_health_check_state $ALB_TARGET_GROUP1_ARN $CLUSTER_ONE_INSTANCES
    tg_health_check_state $ALB_TARGET_GROUP2_ARN $CLUSTER_TWO_INSTANCES

    ALB_DNS=$(get_alb_dns $ALB_ARN)

    echo "Setup completed"
}

function start_benchmarking {
    local alb_dns=$1
    cd docker
    # Build a custom image to run the banchmark script
    docker build -t bench-script .
    # Run the banchmark script inside a docker container
    docker run --rm bench-script benchmarking $alb_dns
}

setup
start_benchmarking $ALB_DNS