output "aws_region" {
  description = "AWS Region used for the deployment."
  value       = "us-east-1"
}

output "availability_zone" {
  description = "Availability Zone used for the public subnet and EC2 instance."
  value       = aws_instance.minecraft.availability_zone
}

output "instance_id" {
  description = "EC2 instance ID used by the reboot verification script."
  value       = aws_instance.minecraft.id
}

output "instance_public_ip" {
  description = "Public IPv4 address of the Minecraft server."
  value       = aws_instance.minecraft.public_ip
}

output "minecraft_server_address" {
  description = "Address for a Minecraft client connection."
  value       = "${aws_instance.minecraft.public_ip}:25565"
}

output "nmap_verification_command" {
  description = "Command used to verify the public Minecraft service."
  value       = "nmap -sV -Pn -p T:25565 ${aws_instance.minecraft.public_ip}"
}
