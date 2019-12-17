# terraform-aws-jenkins
A terraform module that builds a jenkins master with an EFS backing and auto scaling EC2 host. 

### Required inputs:

#### config_s3_uri

This poject makes use of the JCasC plugin to automate the inital setup of your master. Please upload a vaild config file to s3 and ensure the jenkins ec2 IAM role will have acceses to it. Then pass in the S3 URI so that the cloud_init script can download and run it. You can just upload an empty document to get a blank install. 

#### dns_zone

You will need a functional Route53 zone in your account. This could be a deligated subdomain if your primarry domain is hosted elsewhere. Pass in a string of the FQDN. i.e. `example.com`

### Optional inputs: 

#### Jenkins Version

By default the cloud_init script will install the latest LTS version of jenkins. You can override the `yum install jenkins` command here. see init.yaml line 19 for usage.

## Usage

module "jenkins_master" {
  source = "kerry-hatcher/jenkins/aws"
  version = "1.1.0"
  dns_zone = "cooldomain.com" 
  config_s3_uri = "all-my-configs-bucket/jenkins.yaml"
}

