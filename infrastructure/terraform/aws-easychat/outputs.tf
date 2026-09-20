output "server_elastic_ip" {
  description = "The static public Elastic IP allocated to the Easy Chat production server"
  value       = aws_eip.server_eip.public_ip
}

output "server_instance_id" {
  description = "The EC2 Instance ID of the Easy Chat production server"
  value       = aws_instance.easychat_server.id
}

output "s3_media_bucket_name" {
  description = "The AWS S3 bucket name for encrypted media storage"
  value       = aws_s3_bucket.media_bucket.id
}

output "s3_media_bucket_arn" {
  description = "The ARN of the AWS S3 media storage bucket"
  value       = aws_s3_bucket.media_bucket.arn
}

output "vpc_id" {
  description = "The dedicated VPC ID for Easy Chat (isolated from any other project)"
  value       = aws_vpc.easychat_vpc.id
}

output "dns_setup_instructions" {
  description = "DNS setup instructions for api.easychat.com"
  value       = "Create an A record in your DNS provider pointing 'api.easychat.com' to ${aws_eip.server_eip.public_ip}."
}

output "ssm_connect_command" {
  description = "AWS Systems Manager command to connect securely without SSH port 22"
  value       = "aws ssm start-session --target ${aws_instance.easychat_server.id} --region ${var.aws_region}"
}
