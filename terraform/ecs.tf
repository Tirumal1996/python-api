variable "fname" {
  type    = string
  default = "flask"
}

variable "aws_account" {
  type    = string
  default = "035578590291"
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

resource "aws_ecs_task_definition" "flask_task_def" {
  family                   = "${var.fname}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      "name": "${var.fname}-api",
      "image": "${var.aws_account}.dkr.ecr.us-east-1.amazonaws.com/${var.fname}-api:latest",
      "enableExecuteCommand": true,
      "cpu": 512,
      "memory": 1024,
      "portMappings": [
        {
          "containerPort": 5000,
          "hostPort": 5000
        }
      ],
      "essential": true,
      "healthCheck": {
          "Command": ["CMD-SHELL","curl -f http://localhost:5000/ || exit 1"],
          "Interval": 30,
          "Timeout": 5,
          "Retries": 3,
          "StartPeriod": 60
      }
    }
  ])

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
