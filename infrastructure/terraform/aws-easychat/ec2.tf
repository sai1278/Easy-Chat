data "aws_ami" "ubuntu_24" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "easychat_server" {
  ami                    = data.aws_ami.ubuntu_24.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.easychat_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root-ebs"
    }
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              # Update and install prerequisite packages
              apt-get update -y
              apt-get install -y ca-certificates curl gnupg lsb-release ufw git certbot

              # Add official Docker repository
              install -m 0755 -d /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
              chmod a+r /etc/apt/keyrings/docker.asc
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list

              # Install Docker Engine and Docker Compose Plugin
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

              # Enable and start Docker
              systemctl enable docker
              systemctl start docker

              # Configure UFW Host Firewall
              ufw default deny incoming
              ufw default allow outgoing
              ufw allow 80/tcp
              ufw allow 443/tcp
              ufw --force enable

              # Configure 2GB Swap space on root EBS to prevent OOM panic on t3.medium
              if [ ! -f /swapfile ]; then
                fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
                sysctl vm.swappiness=10
                echo 'vm.swappiness=10' >> /etc/sysctl.d/99-easychat-swap.conf
              fi

              # Create Easy Chat deployment directory structure
              mkdir -p /opt/easychat/{docker,data,nginx/certs,scripts}
              chmod 750 /opt/easychat

              echo "Easy Chat host setup completed successfully at $(date)" > /opt/easychat/setup_complete.txt
              EOF

  tags = {
    Name = "${var.project_name}-production-server"
  }
}
