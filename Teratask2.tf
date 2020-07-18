provider "aws" {
  region     = "ap-south-1"
  profile    = "terraform"
}





#Creating key_pairs
resource "tls_private_key" "myprkey" {
  algorithm   = "RSA"
  rsa_bits = 4096
}
resource "aws_key_pair" "newkey1" {
  key_name   = "new-key"
  public_key = tls_private_key.myprkey.public_key_openssh
}


#Creation of Security groups
#security group which allow the port 80 (http) & port 22 (ssh)

resource "aws_security_group" "mynewsg1" {
  name        = "newsg1"
  description = "Allow HTTP inbound traffic"
  

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "nfs from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "newsg1" 
  }
}





#Creating instances with using amazon linux 2 AMI and instance type t2.micro


resource "aws_instance" "mygit1" {
  ami          = "ami-0732b62d310b80e97"
  instance_type = "t2.micro"
  key_name = aws_key_pair.newkey1.key_name 
  security_groups = ["newsg1"]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.myprkey.private_key_pem
    host     = aws_instance.mygit1.public_ip
  }

#Remote execute to configure with webserver, php and git
 
 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "newos-task2"
  }
}


output "My_public_ip" {
  value = aws_instance.mygit1.public_ip
}

#In this we'll save the public ip into local text file 
resource "null_resource" "nullLocal1" { 
  provisioner "local-exec" {
    command = "echo ${aws_instance.mygit1.public_ip} > pubip.txt"
  }
}

resource "null_resource" "local2" { 
  depends_on = [
    null_resource.local1,aws_cloudfront_distribution.mys3distribution1
  ]
  provisioner "local-exec" {
    command = "start chrome ${aws_instance.mygit1.public_ip}"
  }
}

#Output the availability zone
output "myaz11"{

  value = aws_instance.mygit1.subnet_id
}







#Now we'll create efs and then we'll mount targets.

resource "aws_efs_file_system" "efsfile" {
  tags = {
    Name = "newfile"
  }
}


resource "aws_efs_mount_target" "newmount" {
  file_system_id = aws_efs_file_system.efsfile.id
  subnet_id      = aws_instance.mygit1.subnet_id
}







#Now here we'll create partition after attachment of SSH
#We would formate it and mount our ebs 1gb at /var/www/html folder
#And we'll also clear the content of /var/www/html then clone our code from github repo.
resource "null_resource" "local1" { 
  depends_on = [
    aws_efs_mount_target.newmount,
  ]
  
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.myprkey.private_key_pem
    host     = aws_instance.mygit1.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/SanskarTripathi/Terraform-task1-Code.git /var/www/html/",
    ]
  }
}




#Create S3 bucket with public read access 

resource "aws_s3_bucket" "newbucket128" {
  bucket = "newbucket128"
  force_destroy = true 

  versioning {
    enabled = true
  }

  grant {
    type        = "Group"
    permissions = ["READ"]
    uri         = "http://acs.amazonaws.com/groups/global/AllUsers"
  }


tags = {
    Name        = "newbucket128"
    Environment = "Dev"
  }
}

#Here we'll add one image with public-read acl 
resource "aws_s3_bucket_object" "newbuckobj11" {
  bucket = "newbucket128"
  key    = "tera.png"
  source = "C:/Users/anmol/Downloads/tera.png"
  etag = filemd5("C:/Users/anmol/Downloads/tera.png")
  acl = "public-read"
  depends_on = [
    aws_s3_bucket.newbucket128
  ]
   
}

locals {
  s3_origin_id = "myS3Originid1"
}




#Create cloudfront distribution with previously created s3 as the origin after adding one image.

resource "aws_cloudfront_distribution" "mys3distribution1" {

  origin {
    domain_name = aws_s3_bucket.newbucket128.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "The image of terraform"
  default_root_object = "tera.png"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.myprkey.private_key_pem
    host     = aws_instance.mygit1.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.newbuckobj11.key}' height='200px' width='200px'>\" >> /var/www/html/index.php",
      "EOF",
    ]
  }
}



