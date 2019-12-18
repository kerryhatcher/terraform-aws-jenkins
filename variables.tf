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

variable "extra_boot_script" {
    type = "string"
    description = "an S3 object containing a bash shell script that will be ran at the end of jenkins install. Create an empty file if you don't need this" 
}
