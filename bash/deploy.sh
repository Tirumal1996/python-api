#!/bin/bash

# Variables
AWS_ACCOUNT_ID="$1"
AWS_REGION="us-east-1"
ECR_REPO_NAME="flask-api"
IMAGE_TAG="latest"
CLUSTER_NAME="flask-cluster"
SERVICE_NAME="flask-service"
HEALTH_CHECK_URL="http://$2:5000"
NAME="python-api"
GIT_REPO="https://github.com/Tirumal1996/$NAME.git"

#Clone Repo
git clone $GIT_REPO
cd $NAME
# Build Docker image
docker build -t $ECR_REPO_NAME:$IMAGE_TAG .

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Tag Docker image
docker tag $ECR_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG

# Push Docker image to ECR
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG

cd ../task
# Update ECS service with new task definition
TASK_DEFINITION=$(aws ecs register-task-definition --cli-input-json file://task-definition.json | jq -r '.taskDefinition.taskDefinitionArn')
echo "Registered new task definition: $TASK_DEFINITION"

# Update ECS service
aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --task-definition $TASK_DEFINITION
echo "Updated ECS service with new task definition"

aws ecs wait services-stable --cluster "${clusterName}" --services "${serviceName}"

# Health check
until $(curl --output /dev/null --silent --head --fail $HEALTH_CHECK_URL); do
    printf '.'
    sleep 5
done

echo "Health check passed. Deployment successful."
