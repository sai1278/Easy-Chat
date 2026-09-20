resource "aws_security_group" "easychat_sg" {
  name        = "${var.project_name}-server-sg"
  description = "Security group for Easy Chat production server (Strict minimal public exposure)"
  vpc_id      = aws_vpc.easychat_vpc.id

  # Inbound HTTP (port 80) for ACME TLS certificate validation and HTTPS redirection
  ingress {
    description = "HTTP Let's Encrypt validation and HTTPS redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound HTTPS (port 443) for secure API endpoints and WSS WebSocket stream
  ingress {
    description = "HTTPS API and WSS WebSocket traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional restricted SSH (port 22) - only added if explicitly configured.
  # Recommendation: Use AWS SSM Session Manager instead of public SSH.
  dynamic "ingress" {
    for_each = var.admin_ssh_cidr != null ? [var.admin_ssh_cidr] : []
    content {
      description = "Restricted Administrator SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # All outbound traffic allowed (updates, push notification dispatch, S3 API calls)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-server-sg"
  }
}
