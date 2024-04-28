
# Create a VPC
resource "aws_vpc" "flask_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create a private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.flask_vpc.id
  cidr_block = "10.0.2.0/24"
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

