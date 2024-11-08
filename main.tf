# Create VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "main-vpc"
  }
}

# Create Subnets
resource "aws_subnet" "main" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-subnet-${count.index}"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Create Route Table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "main-route-table"
  }
}

# Associate Route Table with Subnets
resource "aws_route_table_association" "a" {
  count          = length(aws_subnet.main)
  subnet_id      = aws_subnet.main[count.index].id
  route_table_id = aws_route_table.main.id
}

# Security Group for EC2 Instance
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow MySQL access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# Data Source for Latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.main[0].id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y apache2 php php-mysql
              sudo systemctl start apache2
              sudo systemctl enable apache2

              # Create a simple PHP script
              echo "<?php
              \$conn = new mysqli('${aws_db_instance.main.address}', '${var.db_username}', '${var.db_password}', 'contacts');
              if (\$conn->connect_error) {
                  die('Connection failed: ' . \$conn->connect_error);
              }

              if (\$_SERVER['REQUEST_METHOD'] == 'POST') {
                  \$name = \$_POST['name'];
                  \$email = \$_POST['email'];
                  \$sql = \"INSERT INTO contacts (name, email) VALUES ('\$name', '\$email')\";
                  if (\$conn->query(\$sql) === TRUE) {
                      echo 'New record created successfully<br>';
                  } else {
                      echo 'Error: ' . \$sql . '<br>' . \$conn->error;
                  }
              }

              echo '<form method=\"POST\">
                      Name: <input type=\"text\" name=\"name\"><br>
                      Email: <input type=\"email\" name=\"email\"><br>
                      <input type=\"submit\" value=\"Submit\">
                    </form>';

              echo '<br><a href=\"?action=view\">View Contacts</a>';

              if (isset(\$_GET['action']) && \$_GET['action'] == 'view') {
                  \$result = \$conn->query(\"SELECT * FROM contacts\");
                  if (\$result->num_rows > 0) {
                      echo '<table border=\"1\"><tr><th>ID</th><th>Name</th><th>Email</th></tr>';
                      while(\$row = \$result->fetch_assoc()) {
                          echo '<tr><td>'.\$row['id'].'</td><td>'.\$row['name'].'</td><td>'.\$row['email'].'</td></tr>';
                      }
                      echo '</table>';
                  } else {
                      echo 'No contacts found.';
                  }
              }

              \$conn->close();
              ?>" | sudo tee /var/www/html/index.php

              # Create the contacts database and table
              sudo apt-get install -y mysql-client
              mysql -h ${aws_db_instance.main.address} -u ${var.db_username} -p${var.db_password} -e "CREATE DATABASE IF NOT EXISTS contacts; USE contacts; CREATE TABLE IF NOT EXISTS contacts (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255), email VARCHAR(255));"

              EOF

  tags = {
    Name = "web-server"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "main-subnet-group"
  subnet_ids = aws_subnet.main[*].id

  tags = {
    Name = "main-subnet-group"
  }
}

# RDS MySQL Database
resource "aws_db_instance" "main" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  name                   = "contacts"
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  tags = {
    Name = "rds-instance"
  }
}
