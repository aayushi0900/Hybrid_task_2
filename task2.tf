#Login to our profile created: 
provider "aws" {
	region   = "ap-south-1"
	profile  = "aayushi"
}

#Create a key pair:
resource "tls_private_key" "mytask2_p_key"  {
	algorithm = "RSA"
        rsa_bits = 4096
}

resource "aws_key_pair" "mytask2-key" {
	key_name    = "mytask2-key"
	public_key = tls_private_key.mytask2_p_key.public_key_openssh
}

output "key_ssh"{
  value = tls_private_key.mytask2_p_key.public_key_openssh
}

output "mytask2-key"{
  value = tls_private_key.mytask2_p_key.public_key_pem
}

resource "local_file" "mytask2_p_key" {
 depends_on = [tls_private_key.mytask2_p_key]
 content = tls_private_key.mytask2_p_key.private_key_pem
 filename = "key2.pem"
 file_permission = 0400
}


#create a security group:
resource "aws_security_group" "mytask2-sg" {
	name        = "mytask2-sg"
	description = "Allow TLS inbound traffic"
	vpc_id      = "vpc-31e8f559"

	ingress {
	description = "SSH"
	from_port   = 22
	to_port     = 22
	protocol    = "tcp"
	cidr_blocks = [ "0.0.0.0/0" ]
 }

	ingress {
    	description = "HTTP"
    	from_port   = 80
    	to_port     = 80
    	protocol    = "tcp"
    	cidr_blocks = [ "0.0.0.0/0" ]
 }

	egress {
    	from_port   = 0
    	to_port     = 0
    	protocol    = "-1"
    	cidr_blocks = ["0.0.0.0/0"]
 }

  	tags = {
    	Name = "mytask2-sg"
 }
}

#Launching an EC2 instance using the key-pair and security-group we have created:
resource "aws_instance" "mytask2-os" {
  	ami           = "ami-0447a12f28fddb066"
  	instance_type = "t2.micro"
  	availability_zone = "ap-south-1a"
  	key_name      = "mytask2-key"
  	security_groups = [ "mytask2-sg" ]
 
	connection {
    	type     = "ssh"
    	user     = "ec2-user"
    	private_key =  tls_private_key.mytask2_p_key.private_key_pem
    	host     = aws_instance.mytask2-os.public_ip
 }

 	provisioner "remote-exec" {
    	inline = [
      	"sudo yum install httpd  php git -y",
      	"sudo systemctl restart httpd",
      	"sudo systemctl enable httpd",
       ]
 }

	tags = {
    	Name = "mytask2-os"
 }
}

#Create an EFS file system:
resource "aws_efs_file_system" "mytask2-efs" {
  	creation_token="efs"
 
  	tags = {
    	Name = "mytask2-efs"
 }
}


resource "aws_efs_mount_target" "mount" {
       file_system_id = aws_efs_file_system.mytask2-efs.id
       subnet_id = "subnet-bdf5cfd5"
       security_groups= [aws_security_group.mytask2-sg.id]
}

resource "null_resource" "mounting" {
       depends_on = [ aws_efs_mount_target.mount, ]

       connection  { 
           type = "ssh"
           user = "ec2-user"
           private_key = tls_private_key.mytask2_p_key.private_key_pem
           host = aws_instance.mytask2-os.public_ip
       }

       provisioner "remote-exec" {
           inline = [ 
                   "sudo yum install httpd php git -y",
                   "sudo systemctl restart httpd",
                   "sudo systemctl enable httpd",
                   "sudo mkfs.ext4  /dev/xvdf",
                   "sudo mount /dev/xvdf  /var/www/html",
                   "sudo rm -rf /var/www/html/*",
                   "sudo git clone https://github.com/aayushi0900/Hybrid_task_2.git  /var/www/html",
                   "sudo yum install nfs-utils -y"
                  ]
       }
}

#Creating a S3 bucket to store the static data:
resource "aws_s3_bucket" "mytask2-aayu-bucket-0906" {
  	bucket = "mytask2-aayu-bucket-0906"
  	acl    = "public-read"
       
	 versioning {
          enabled = true
        }

        tags = {
          Name = "mytask2-aayu-bucket-0906"
  }
}

resource "aws_s3_bucket_object" "mytask2_object" {
  bucket = aws_s3_bucket.mytask2-aayu-bucket-0906.id
  key    = "myimage.jpg"
  source = "/home/aayushi/Desktop/terraform/Aayushi.jpg"   
  acl = "public-read"
  
  force_destroy = true

}
 
 locals{
             s3_origin_id = "S3-${aws_s3_bucket.mytask2-aayu-bucket-0906.bucket}"
}

# Create Cloudfront distribution:
 resource "aws_cloudfront_distribution" "mytask2_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.mytask2-aayu-bucket-0906.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.mytask2-aayu-bucket-0906.id}"

  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 bucket"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.mytask2-aayu-bucket-0906.id}"

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
    target_origin_id = "${aws_s3_bucket.mytask2-aayu-bucket-0906.id}"

    forwarded_values {
      query_string = false

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

  depends_on = [
   aws_s3_bucket.mytask2-aayu-bucket-0906
]
}
