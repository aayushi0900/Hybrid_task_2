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

#To upload data to S3 bucket:
resource "null_resource" "remove_and_upload_to_s3" {
  	provisioner "local-exec" {
    	command ="firefox index.html"
}	
	depends_on = [
   	aws_s3_bucket.mytask2-aayu-bucket-0906,
  ]
}

# Create Cloudfront distribution:
resource "aws_cloudfront_distribution" "mytask2-distribution" {
    	origin {
        domain_name = "${aws_s3_bucket.mytask2-aayu-bucket-0906.bucket_regional_domain_name}"
        origin_id = "S3-${aws_s3_bucket.mytask2-aayu-bucket-0906.bucket}"

        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
}
	# By default, show index.html file:
    	default_root_object = "index.html"
    	enabled = true

    	# If there is a 404, return index.html with a HTTP 200 Response:
    	custom_error_response {
        error_caching_min_ttl = 3000
        error_code = 404
        response_code = 200
        response_page_path = "/index.html"
    }

    	default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-${aws_s3_bucket.mytask2-aayu-bucket-0906.bucket}"

        #Not Forward all query strings, cookies and headers:
        forwarded_values {
            query_string = false
	    cookies {
		forward = "none"
	    }
            
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    	# Distributes content to all:
    	price_class = "PriceClass_All"

    	# Restricts who is able to access this content:
    	restrictions {
        geo_restriction {
        # type of restriction, blacklist, whitelist or none:
        restriction_type = "none"
        }
    }

    	# SSL certificate for the service:
    	viewer_certificate {
        cloudfront_default_certificate = true
    }
}

#OUTPUT:
output "cloudfront_ip_addr" {
  	value = aws_cloudfront_distribution.mytask2-distribution.domain_name
}

resource "null_resource" "running_website" {
    depends_on = [null_resource.mounting]
    provisioner "local-exec" {
    command = "chrome ${aws_instance.mytask2-os.public_ip}"
  }
}

