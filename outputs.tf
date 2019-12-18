output "jenkins_master_ec2_sg" {
  value = aws_security_group.jenkins_master.id
  description = "This is the SG attached to the EC2 running jenkins. You can use this in your parent project to add rules for SSH or anything else you may need"
}
