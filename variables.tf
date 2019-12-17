variable "jenkins_version" {
  type = "string"
  default = "jenkins"
  description = "this variable gets passed to yum for jenkins installer. see init.yaml line 19 for usage."
}

variable "config_s3_uri" {
  type = "string" 
  description = "this is the S3 object contating the configuration as code document. Should look like s3://bucketname/jenkins.yaml"
}

variable "dns_zone" {
  type = "string"
  description = "The FQDN of a zone in your account. We will create a new A record of jenkins pointing to the ALB of the jenkins master"
}

