provider "aws"{
  region    = "ap-south-1"
  profile   = "Cloud2"
}

resource "tls_private_key" "aws-key" {
  algorithm   = "RSA"
}
resource "aws_key_pair" "key-pass" {
  key_name   = "deployer-key"
  public_key = tls_private_key.aws-key.public_key_openssh 
}

resource "aws_security_group" "WebServerSG"{
   name = "ServiceSG"
   vpc_id = "vpc-54b9a43c"
   
   ingress{
          from_port=443
          to_port = 443
          protocol="tcp"
          cidr_blocks=["0.0.0.0/0"]
    }
   ingress{
          from_port=80
          to_port = 80
          protocol="tcp"
          cidr_blocks=["0.0.0.0/0"]
    }

   ingress{
            from_port=22
          to_port = 22
          protocol="tcp"
          cidr_blocks=["0.0.0.0/0"]
     }
    egress{	
          from_port=0
          to_port = 0
          protocol="-1"
          cidr_blocks=["0.0.0.0/0"]
     }
   }
 
resource "aws_instance" "WebServer" {
  ami            = "ami-09a7bbd08886aafdf"
  instance_type  = "t2.micro"
  key_name       = aws_key_pair.key-pass.key_name
  security_groups = ["${aws_security_group.WebServerSG.name}"]
  

   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.aws-key.private_key_pem
    host     = aws_instance.WebServer.public_ip
  }
    provisioner "remote-exec" {
     inline = [
       "sudo yum install httpd  php git -y",
       "sudo systemctl restart httpd",
       "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "Web_OS"
   }
}


resource "aws_efs_file_system" "efs" {
  creation_token = "web-efs"

  tags = {
    Name = "efs"
  }
}

resource "aws_efs_mount_target" "alpha" {
  file_system_id = "${aws_efs_file_system.efs.id}"
  subnet_id      = "${aws_instance.WebServer.subnet_id}"
  security_groups = [aws_security_group.WebServerSG.id]
}

output "myos_ip" {
  value = aws_instance.WebServer.public_ip
 }

resource "null_resource" "nulllocal"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.WebServer.public_ip} > publicip.txt"
  	}
}



resource "null_resource" "efs-attach"  {

depends_on = [aws_efs_mount_target.alpha
    ,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.aws-key.private_key_pem
    host     = aws_instance.WebServer.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdd",
      "sudo mount  /dev/xvdd  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/shishupal-cmd/HybridMultiCloud_2.git /var/www/html/"
    ]
  }
}

resource "aws_s3_bucket" "bucket-img" {
  depends_on = [
       null_resource.efs-attach,
   ]

  bucket = "aws-task-2"
  acl    = "public-read"
  tags = {
    Name = "mybucket2"
      Environment="Dev"
   }
 }

  
  

resource "aws_s3_bucket_object" "image" {

depends_on = [
       aws_s3_bucket.bucket-img
]
  key                    = "cloud.png"
  bucket                 = aws_s3_bucket.bucket-img.bucket
  acl                    = "public-read"
  source                 = "C:\\Users\\LENOVO PC\\Desktop\\my-image\\cloud.png"
  etag                   = "${filemd5("C:\\Users\\LENOVO PC\\Desktop\\my-image\\cloud.png")}"
}

locals {
  s3_origin_id = "S3-${aws_s3_bucket.bucket-img.bucket}"
}



resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.bucket-img.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.bucket-img.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 bucket"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.bucket-img.id}"

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

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${aws_s3_bucket.bucket-img.id}"
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

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
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
    private_key = tls_private_key.aws-key.private_key_pem
    host     = aws_instance.WebServer.public_ip
  }
  

 
   provisioner "remote-exec"{
      inline= [
         "sudo su << EOF",
                   "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.image.key}' width='300' height='400'>\" >> /var/www/html/index.html",
                                       "EOF",
  ]
   }
}
  
