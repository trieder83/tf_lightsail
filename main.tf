terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "eu-central-1"
}

resource "aws_lightsail_key_pair" "lightsail_wg_key_pair" {
  name       = "wg_instance_key"
  public_key = "${file("wg_vpn.key.pub")}"
}

# Create a new GitLab Lightsail Instance
resource "aws_lightsail_instance" "wg_vpn" {
  name              = "wg-vpn"
  availability_zone = var.aws_availability_zone_a
  blueprint_id      = "ubuntu_20_04"
  bundle_id         = "nano_2_0"
  key_pair_name     = "wg_instance_key"
  tags = {
    env = "tftest"
  }

  provisioner "file" {
    source      = "setup_wg.sh"
    destination = "/tmp/setup_wg.sh"

    connection {
      type     = "ssh"
      user     = "ubuntu"
      host     = self.public_ip_address
      private_key = "${file(var.ssh_wg_key_private)}"
    }

  }

  provisioner "remote-exec" {
      inline = [
      "chmod +x /tmp/setup_wg.sh",
      "/tmp/setup_wg.sh ${self.public_ip_address}"
    ]
    connection {
      type     = "ssh"
      user     = "ubuntu"
      host     = self.public_ip_address
      private_key = "${file(var.ssh_wg_key_private)}"
    }
  }
  
}

resource "aws_lightsail_instance_public_ports" "test" {
  instance_name = aws_lightsail_instance.wg_vpn.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }
}
