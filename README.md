# Webserver Deploymeny Using Terraform and EFS
![alt text](https://miro.medium.com/max/1500/1*WCXUqu-Lgeo6ZiUzlXnTLg.png)

# Prequiuiste for this project
  **Should  have**
  - An  AWS account
  - AWS command  installed
  - Terraform  command installed
  
# Project Description
- Create Security group which allow the port 80.
- Launch EC2 instance.
- In  EC2 instance use the existing key or provided key and security group which we have  already created 
- Launch one Volume using the EFS service and attach it in your vpc, then mount that volume into /var/www/html
- Developer have uploded the code into github repo also the repo has some images.
- Copy the github repo code into /var/www/html
- Create S3 bucket, and copy/deploy the images from github repo into the s3 bucket and change the permission to public readable.
- Create a Cloudfront using s3 bucket(which contains images) and use the Cloudfront URL to  update in code in /var/www/html
 
 # Let's now build the whole infrastructure
   
   # Step1
   **First we have to login with some user iusing CLI, it should be already created**
     ![Job1](/images/awsprofile.jpg/)
   
      
   # Step2
   **Set the provider as AWS**
   ```
   provider "aws"{
  region    = "ap-south-1"
  profile   = "Cloud2"
}
```
   
   # Step3
   **Create a key_pair to login to instance**
 
   ```
   resource "tls_private_key" "aws-key" {
  algorithm   = "RSA"
}
resource "aws_key_pair" "key-pass" {
  key_name   = "deployer-key"
  public_key = tls_private_key.aws-key.public_key_openssh 
}
```
   # Step4
   **Create a security group which allow port 80 , 443 , 22**
  - Port 22 for SSH
  - Port 80  for HTTP   
  - Port 443 for HTTPS/SSL 
 ```
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
 ```
   # Step5
   **Create EFS storage**
   ```
   resource "aws_efs_file_system" "efs" {
  creation_token = "web-efs"

  tags = {
    Name = "efs"
  }
}
```
  **Mounting EFS storage to a folder in EC2 instance**
  ```
  resource "aws_efs_mount_target" "alpha" {
  file_system_id = "${aws_efs_file_system.efs.id}"
  subnet_id      = "${aws_instance.WebServer.subnet_id}"
  security_groups = [aws_security_group.WebServerSG.id]
}
```
 **Attaching it to EC2 instance , formatting , and dowload the data form github**
 ```
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


```
   
   # Step6
   **Create a S3 Bucket **
     - To keep our static data
     - Change the access mode to public readable
   ```
   
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
 ```
   **Adding object to Bucket**
 ```
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


```
# Step7
**Create instance and Configure Web server with SSH**

```
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
```

  # Step8
  **Create CloudFront 
  ```
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
  
```
 # Now after creating the code run the following commands
   ```
   terraform init
   terraform validate
   terraform plan
   terraform apply --auto-approve
   ```
 # Here is our Infrastructure
   - Key_Pair
     ![Job1](/images/Key.jpg/)
   - Security_group
     ![Job1](/images/SG1.jpg/)'
   - EFS_Storage
     ![Job1](/images/EFS.jpg/)
     ![Job1](/images/Amazon EFS and 4 more pages - Personal - Microsoft​ Edge 08-09-2020 22_50_35.jpg/)
   - S3 Bucket
     ![Job1](/images/S3.jpg/)
   - AWS Instance
     ![Job1](/images/Instance.jpg/)
   - CloudFront
     ![Job1](/images/CloudFront1.jpg/)
     ![Job1](/images/CloudFront.jpg/)
  # Congratulation 
   # Here is the output obtained by going to Instance public IP 
   ![Job1](/images/Output.jpg/)




   
