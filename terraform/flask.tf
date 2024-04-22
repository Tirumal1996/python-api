variable "fname" {
  type    = string
  default = "flasky"
}

variable "aws_account" {
  type    = string
  default = "035578590291"
}

terraform {
  backend "s3" {
    bucket         = "flask-tr-s3"
    key            = "tfstate/state"
    region         = "us-east-1"
    dynamodb_table = "trdynamodb"
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-east-1" # Replace with your desired region
}

resource "aws_lb" "flask_api_nlb" {
  name               = "${var.fname}-api-nlb"
  load_balancer_type = "network"
  subnets            = [aws_subnet.public_subnet.id]
  security_groups    = [aws_security_group.flask_api_sg.id]
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.flask_api_nlb.arn
  port              = "5000"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_api_tg.arn
  }
}

resource "aws_lb_target_group" "flask_api_tg" {
  name        = "${var.fname}-api-tg"
  port        = 5000
  protocol    = "TCP"
  vpc_id      = aws_vpc.flask_vpc.id
  target_type = "ip"
}

# Create an ECS cluster
resource "aws_ecs_cluster" "flask_cluster" {
  name = "${var.fname}-cluster"
}

# Create an ECS Task Execution Role
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json
}

data "aws_iam_policy_document" "ecs_task_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs_task_execution_role_policy.arn
}

# Create a task definition for the Flask API
resource "aws_ecs_task_definition" "flask_task_def" {
  family                  = "${var.fname}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = <<DEFINITION
[
  {
    "name": "${var.fname}-api",
    "image": "${var.aws_account}.dkr.ecr.us-east-1.amazonaws.com/${var.fname}-api:latest",
    "cpu": 512,
    "memory": 1024,
    "portMappings": [
      {
        "containerPort": 5000,
        "hostPort": 5000
      }
    ],
    "essential": true
  }
]
DEFINITION
}

# Create an ECS service with a public IP
resource "aws_ecs_service" "flask_service" {
  name            = "${var.fname}-service"
  cluster         = aws_ecs_cluster.flask_cluster.id
  task_definition = aws_ecs_task_definition.flask_task_def.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Assign a public IP to the ECS task
  load_balancer {
    target_group_arn = aws_lb_target_group.flask_api_tg.arn
    container_name   = "${var.fname}-api"
    container_port   = 5000
  }

  network_configuration {
    assign_public_ip = true
    subnets          = [aws_subnet.public_subnet.id]
    security_groups  = [aws_security_group.flask_api_sg.id]
  }
  depends_on = [aws_lb_listener.front_end]
}

# Create a VPC
resource "aws_vpc" "flask_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.flask_vpc.id
  cidr_block = "10.0.1.0/24"
}

# Create an internet gateway
resource "aws_internet_gateway" "flask_igw" {
  vpc_id = aws_vpc.flask_vpc.id
}

# Create a route table for the public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.flask_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.flask_igw.id
  }
}

# Associate the public subnet with the route table
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a security group for the Flask API
resource "aws_security_group" "flask_api_sg" {
  name_prefix = "${var.fname}-api-sg-"
  vpc_id      = aws_vpc.flask_vpc.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Change this to your desired IP range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.flask_task_def.arn
  description = "The ARN of the ECS Task Definition"
}
