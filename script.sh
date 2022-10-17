set -e
# import cli cmd functions
source utils/cli_helper.sh

function setup {
    if [[ -f "backup.txt" ]]; then
        rm -f keypair.pem
    fi

    #Setup network security
    create_security_group
    create_keypair

    #Setup EC2 instances
    SUBNETS_1=$(aws ec2 describe-subnets --query "Subnets[0].SubnetId" --output text)
    SUBNETS_2=$(aws ec2 describe-subnets --query "Subnets[1].SubnetId" --output text)
    CLUSTER_ONE_INSTANCES=() #Arrays of instanceIds for each cluster
    CLUSTER_TWO_INSTANCES=()

    echo "Launch EC2 instances..."
    for i in {1..4}; do
        CLUSTER_ONE_INSTANCES+=("$(launch_ec2_instance $SUBNETS_1 "t2.large")")
        CLUSTER_TWO_INSTANCES+=("$(launch_ec2_instance $SUBNETS_2 "m4.large")")
    done
    # a list per cluster that contain the ip of instances 
    #Launch the 9th instance
    CLUSTER_ONE_INSTANCES+=("$(launch_ec2_instance $SUBNETS_1 "t2.large")")
    echo "CLUSTER_ONE_INSTANCES=\"$CLUSTER_ONE_INSTANCES\"" >>backup.txt
    echo "CLUSTER_TWO_INSTANCES=\"$CLUSTER_TWO_INSTANCES\"" >>backup.txt
    echo "Done"

    #Setup the load balancer configs
    echo "Create an application load balancer..."
    ALB_ARN=$(create_alb)
    echo "ALB_ARN=\"$ALB_ARN\"" >>backup.txt
    echo "Done"

    echo "Create target groups"
    ALB_TARGET_GROUP1_ARN=$(create_target_group "cluster1")
    ALB_TARGET_GROUP2_ARN=$(create_target_group "cluster2")
    echo "ALB_TARGET_GROUP1_ARN=\"$ALB_TARGET_GROUP1_ARN\"" >>backup.txt
    echo "ALB_TARGET_GROUP2_ARN=\"$ALB_TARGET_GROUP2_ARN\"" >>backup.txt
    echo "Done"

    echo "Create path rules for alb listener..."
    #Create a listener for your load balancer with a default rule that forwards requests to your target group
    ALB_LISTNER_ARN=$(create_alb_listener $ALB_ARN $ALB_TARGET_GROUP1_ARN $ALB_TARGET_GROUP2_ARN)
    echo "ALB_LISTNER_ARN=\"$ALB_LISTNER_ARN\"" >>backup.txt

    #Create a rule using a path condition and a forward action for cluster 1 & 2
    echo "Create listener rules for cluster 1 and cluster 2"
    create_listener_rules $ALB_LISTNER_ARN $ALB_TARGET_GROUP1_ARN "file://config/cluster1-routing.json" 5
    create_listener_rules $ALB_LISTNER_ARN $ALB_TARGET_GROUP2_ARN "file://config/cluster2-routing.json" 6
    echo "Done"

    echo "Wait for instances to enter 'running' state..."
    aws ec2 wait instance-running --instance-ids ${CLUSTER_ONE_INSTANCES[@]} ${CLUSTER_TWO_INSTANCES[@]}
    echo "Instances are ready!"

    #Register the instances in the target groups
    echo "Register the instances in the target groups..."
    for id in ${CLUSTER_ONE_INSTANCES[@]}; do
        register_targets $ALB_TARGET_GROUP1_ARN $id
    done

    for id in ${CLUSTER_TWO_INSTANCES[@]}; do
        register_targets $ALB_TARGET_GROUP2_ARN $id
    done
    echo "Done"

    echo "Wait for alb to become available"
    aws elbv2 wait load-balancer-available --load-balancer-arns $ALB_ARN

    echo "Wait for target groups to pass health checks..."
    tg_health_check_state $ALB_TARGET_GROUP1_ARN $CLUSTER_ONE_INSTANCES
    tg_health_check_state $ALB_TARGET_GROUP2_ARN $CLUSTER_TWO_INSTANCES

    ALB_DNS=$(get_alb_dns $ALB_ARN)
    echo "ALB_DNS=\"$ALB_DNS\"" >>backup.txt

    echo "Setup completed"
}

function start_benchmarking {
    if [[ -f "backup.txt" ]]; then
        source backup.txt
    fi
    cd docker
    # Build a custom image to run the banchmark script
    docker build -t bench-script .
    # Run the banchmark script inside a docker container
    docker run --rm bench-script benchmarking $ALB_DNS
    cd ..
}

function visualization {
    if [[ -f "backup.txt" ]]; then
        source backup.txt
    fi
    aws cloudwatch get-metric-widget-image --metric-widget '{
        "metrics": [
            [ "AWS/ApplicationELB", "RequestCount", "TargetGroup", "targetgroup/cluster1/'"${ALB_TARGET_GROUP1_ARN##*/}"'", "LoadBalancer", "app/application-load-balancer/'"${ALB_ARN##*/}"'", "AvailabilityZone", "us-east-1a" ],
            [ "...", "targetgroup/cluster2/'"${ALB_TARGET_GROUP2_ARN##*/}"'", ".", ".", ".", "us-east-1b" ]
        ],
        "title": "Request Count",
        "width": 1500,
        "height": 250,
        "start": "-PT30M"
      }' --output text | base64 -d >| app/static/metrics/request_count.png

    aws cloudwatch get-metric-widget-image --metric-widget '{
      "metrics": [
          [ "AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/application-load-balancer/'"${ALB_ARN##*/}"'", "AvailabilityZone", "us-east-1a" ],
          [ "...", "us-east-1b" ]
      ],
      "title": "Target Response Time per AZ",
      "width": 1500,
      "height": 250,
      "start": "-PT30M"
     }' --output text | base64 -d >|app/static/metrics/target_response_time_AZ.png

    aws cloudwatch get-metric-widget-image --metric-widget '{
      "title": "Target Response Time per Group",
      "metrics": [
          [ "AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", "targetgroup/cluster1/'"${ALB_TARGET_GROUP1_ARN##*/}"'", "LoadBalancer", "app/application-load-balancer/'"${ALB_ARN##*/}"'" ],
          [ "...", "targetgroup/cluster2/'"${ALB_TARGET_GROUP2_ARN##*/}"'", ".", "." ]
      ],
      "width": 1500,
      "height": 250,
      "start": "-PT30M"
      }' --output text | base64 -d >| app/static/metrics/target_response_time_TG.png

    aws cloudwatch get-metric-widget-image --metric-widget '{
        "title": "CPU utilizations (%)",
        "metrics": [
            [ "AWS/EC2", "CPUUtilization", "InstanceType", "m4.large" ],
            [ "...", "t2.large" ]
        ],
        "width": 1500,
        "height": 250,
        "start": "-PT30M"
      }' --output text | base64 -d >|app/static/metrics/cpuutilization.png

    aws cloudwatch get-metric-widget-image --metric-widget '{
        "title": "Network In",
        "metrics": [
            [ "AWS/EC2", "NetworkIn", "InstanceType", "m4.large" ],
            [ "...", "t2.large" ]
        ],
        "width": 1500,
        "height": 250,
        "start": "-PT30M"
      }' --output text | base64 -d >| app/static/metrics/networking.png

    # Display collected metrcis in a html page using flask
    python3 app/app.py

}

function wipe {
    ## Delete the listener
    if [[ -n "${ALB_LISTNER_ARN}" ]]; then
        echo "Delete the listener... "
        delete_listener $ALB_LISTNER_ARN
        echo "Done"
    fi

    ## Deregister targets
    if [[ -n "${ALB_TARGET_GROUP1_ARN}" ]] && [[ -n $CLUSTER_ONE_INSTANCES ]]; then
        echo "Deregister targets..."
        deregister_targets $ALB_TARGET_GROUP1_ARN $CLUSTER_ONE_INSTANCES
        echo "done for cluster 1"
    fi
    if [[ -n "${ALB_TARGET_GROUP2_ARN}" ]] && [[ -n $CLUSTER_TWO_INSTANCES ]]; then
        deregister_targets $ALB_TARGET_GROUP2_ARN $CLUSTER_TWO_INSTANCES
        echo "done for cluster 2"
    fi

    ## Delete target groups
    if [[ -n "${ALB_TARGET_GROUP1_ARN}" ]]; then
        echo "Delete target groups..."
        delete_target_groups $ALB_TARGET_GROUP1_ARN
        echo "group deleted for cluster 1"
    fi
    if [[ -n "${ALB_TARGET_GROUP2_ARN}" ]]; then
        delete_target_groups $ALB_TARGET_GROUP2_ARN
        echo "group deleted for cluster 2"
    fi

    ## Delete Application Load Balancer
    if [[ -n "${ALB_ARN}" ]]; then
        echo "Delete Application Load Balancer..."
        delete_alb $ALB_ARN
        echo "Application Load Balancer deleted"
    fi

    ## Terminate the ec2 instances
    if [[ -n "${CLUSTER_ONE_INSTANCES}" ]]; then
        echo "Terminate the ec2 instances... Ok"
        aws ec2 wait instance-running --instance-ids ${CLUSTER_ONE_INSTANCES[@]} ${CLUSTER_TWO_INSTANCES[@]}
        aws ec2 terminate-instances --instance-ids ${CLUSTER_ONE_INSTANCES[@]} ${CLUSTER_TWO_INSTANCES[@]}

        ## Wait for instances to enter 'terminated' state
        echo "Wait for instances to enter 'terminated' state..."
        aws ec2 wait instance-terminated --instance-ids ${CLUSTER_ONE_INSTANCES[@]} ${CLUSTER_TWO_INSTANCES[@]}
        echo "instance terminated"
    fi

    ## Delete key pair
    echo "Delete key pair..."
    aws ec2 delete-key-pair --key-name keypair
    rm -f keypair.pem
    echo "key pair Deleted"

    ## Delete custom security group
    if [[ -n "$SECURITY_GROUP_ID" ]]; then
        echo "Delete custom security group..."
        delete_security_group $SECURITY_GROUP_ID
        echo "Security-group deleted"
    fi
}

setup
start_benchmarking $ALB_DNS
visualization
wipe
