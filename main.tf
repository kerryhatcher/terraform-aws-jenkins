/*
Lock the module to a spific version of terraform to reduce version issues. 
*/
terraform {
  required_version = "0.12.10"
}

/*
Configure the AWS Provider
TODO: Credentails and region should be configured via envorment vars or aws config file per https://www.terraform.io/docs/providers/index.html
*/
provider "aws" {
  version = "~> 2.0" 
}

#Select the default VPC in the region we are connected to. 
#TODO: Support VPCs other than the default.
data "aws_vpc" "main" {
  //id = "${var.vpc_id}"
  default = true
}


#What AMI to use? 
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

#Get all the subnets in the provided VPC. #TODO: add filtering options. 
data "aws_subnet_ids" "subnets" {
  vpc_id = "${data.aws_vpc.main.id}"
}
/*
The Auto Scaling Group (ASG) automaticly starts up a single master when none is present. 
EC2s can come and go without notice so it's important that we ensure another one will come back in its place. 
There should never be more that one master running at a time. 
*/
resource "aws_autoscaling_group" "jenkis_master" {
  name = "${aws_launch_template.jenkins_master.name}-${aws_launch_template.jenkins_master.latest_version}-asg"
  vpc_zone_identifier = "${data.aws_subnet_ids.subnets.ids}"
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1
  metrics_granularity = "1Minute"
  enabled_metrics = ["GroupMinSize", "GroupMaxSize", "GroupMaxSize", "GroupMaxSize", "GroupPendingInstances", "GroupTotalInstances"]


  launch_template {
    id      = "${aws_launch_template.jenkins_master.id}"
    version = "$Latest"
  }
  depends_on = [
    aws_efs_mount_target.jenkins_master_1
  ]
}

#The lanch template defines the atrobutes of the master EC2 that the auto scaleing group will create. 
resource "aws_launch_template" "jenkins_master" {
  name_prefix   = "jenkins_master_${terraform.workspace}_"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "c5.xlarge"
  key_name      = "hatch_key"
  network_interfaces {
    associate_public_ip_address = true
    security_groups = ["${aws_security_group.jenkins_master.id}"]
  }
  iam_instance_profile {
      name = "${aws_iam_instance_profile.jenkins_master_profile.name}"
  }
  monitoring {
    enabled = true
  }
  user_data = "${data.template_cloudinit_config.init_script.rendered}"

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "Jenkins_master_${terraform.workspace}"
    }
  }

  //data.template_cloudinit_config.user_data.rendered
}


#TODO: Git rid of these stupid waits. I don't like it.... 
data "template_file" "init_script" {
  template = "${file("${path.module}/init.yaml")}"

  vars = {
    extra_boot_script = "${var.extra_boot_script}"
    config_s3_uri = "${var.config_s3_uri}"
    efs_id = "${aws_efs_file_system.jenkins_master.id}" 
    jenkins_version = var.jenkins_version
    //consul_address = "${aws_instance.consul.private_ip}"
  }
}

data "template_cloudinit_config" "init_script" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = "${data.template_file.init_script.rendered}"
  }
}

######## EFS ########

/*
EFS is very important. Everything else can be rebuilt without issue except the EFS cluster. Loss of this will result in data loss and necciate a recovery from backup or redeploy from code (if all your configs have been saved to code). 
*/

#TODO: add vars to hanle throughput_mode, provisioned_throughput_in_mibps, and performance_mode 
resource "aws_efs_file_system" "jenkins_master" {
  tags = {
    Name = "jenkins_master_${terraform.workspace}"
  }
}

resource "aws_efs_mount_target" "jenkins_master_1" {
  //count = length(data.aws_subnet_ids.subnets.ids)
  for_each = data.aws_subnet_ids.subnets.ids
  file_system_id = "${aws_efs_file_system.jenkins_master.id}"
  subnet_id = each.value
  security_groups = [aws_security_group.efs_mount_target.id]
}


resource "aws_security_group" "efs_mount_target" {
  name        = "jenkins_master_efs_${terraform.workspace}"
  description = "Allow EFS inbound traffic"
  vpc_id      = "${data.aws_vpc.main.id}"

  #TODO: lock down ingress
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    security_groups = ["${aws_security_group.jenkins_master.id}"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}




resource "aws_security_group" "jenkins_master" {
  name        = "jenkins_master_ec2_${terraform.workspace}"
  description = "Allow TLS inbound traffic"
  vpc_id      = "${data.aws_vpc.main.id}"

  #TODO: lock down ingress
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = ["${aws_security_group.jenkins_master_alb.id}"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}



# Instance Profile sets what IAM role to use
resource "aws_iam_instance_profile" "jenkins_master_profile" {
  name = "jenkins_master_${terraform.workspace}"
  role = aws_iam_role.jenkins_master.name

}

resource "aws_iam_role" "jenkins_master" {
  name = "jenkins_master_${terraform.workspace}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    tag-key = "tag-value"
  }
}

resource "aws_iam_policy" "jenkins_master" {
  name        = "jenkins_master_policy_${terraform.workspace}"
  description = "The policy for the jenkins master ec2"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:Describe*",
        "s3:*",
        "secretsmanager:ListSecrets"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:*:*:*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "jenkins_master" {
  role       = "${aws_iam_role.jenkins_master.name}"
  policy_arn = "${aws_iam_policy.jenkins_master.arn}"
}



################### Front End Section ###################


resource "aws_lb" "jenkins_master" {
  name               = "jenkins-master-${terraform.workspace}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.jenkins_master_alb.id}"]
  subnets            = "${data.aws_subnet_ids.subnets.ids}"

  enable_deletion_protection = false

  /* TODO: Access logs
  access_logs {
    bucket  = "${aws_s3_bucket.lb_logs.bucket}"
    prefix  = "test-lb"
    enabled = true
  }
  */

  tags = {
    Environment = "Jenkins"
  }
}

resource "aws_autoscaling_attachment" "jenks_master" {
  autoscaling_group_name = "${aws_autoscaling_group.jenkis_master.id}"
  alb_target_group_arn   = "${aws_alb_target_group.jenkins_master.arn}"
}

resource "aws_alb_target_group" "jenkins_master" {
  name     = "jenkins-master-${terraform.workspace}"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = "${data.aws_vpc.main.id}"
}

resource "aws_lb_listener" "jenkins_master" {
  load_balancer_arn = "${aws_lb.jenkins_master.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "${aws_acm_certificate.jenkins_master.arn}"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_alb_target_group.jenkins_master.arn}"
  }
}

resource "aws_lb_listener" "jenkins_master_http" {
  load_balancer_arn = "${aws_lb.jenkins_master.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


resource "aws_route53_record" "jenkins" {
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name    = "jenkins"
  type    = "A"
  alias {
    name                   = "${aws_lb.jenkins_master.dns_name}"
    zone_id                = "${aws_lb.jenkins_master.zone_id}"
    evaluate_target_health = true
  }
}



data "aws_route53_zone" "selected" {
  name         = "${var.dns_zone}"
  private_zone = false
}

resource "aws_acm_certificate" "jenkins_master" {
  domain_name       = "${aws_route53_record.jenkins.fqdn}"
  validation_method = "DNS"

  tags = {
    Environment = "Jenkins"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  name    = "${aws_acm_certificate.jenkins_master.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.jenkins_master.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.selected.id}"
  records = ["${aws_acm_certificate.jenkins_master.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}



resource "aws_security_group" "jenkins_master_alb" {
  name        = "jenkins_master_ALB_${terraform.workspace}"
  description = "Allow inbound traffic"
  vpc_id      = "${data.aws_vpc.main.id}"

  #TODO: lock down ingress
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}


#TODO: EFS BACKUP

#TODO: var the jenkins install verson 

#TODO: var the instance                      

#TODO: WAF

#TODO: Config File  & S3